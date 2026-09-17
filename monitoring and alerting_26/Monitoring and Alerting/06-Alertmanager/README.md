# 06 · Alertmanager  ★ deep dive

**Level:** core · **Time:** ~4 h + Lab 5 · **Goal:** design a routing tree that delivers the right alert to the right team, grouped, inhibited, silenced and templated — and prove it works with `amtool`.

**Version referenced:** Alertmanager **0.34** (`time_intervals`, UTF-8 matchers, Jira/incident.io/Mattermost notifiers).

---

## 1. What Alertmanager does

Prometheus evaluates rules and produces **alerts**. Alertmanager turns those into **notifications**. Its five jobs:

| Job | Mechanism | Why it exists |
|---|---|---|
| **Deduplicate** | Alert **fingerprint** (hash of label set) | Two Prometheus replicas → one notification |
| **Group** | `group_by` + `group_wait`/`group_interval` | 400 pod alerts → 1 message |
| **Inhibit** | `inhibit_rules` | Node down ⇒ silence all its pod alerts |
| **Silence** | Matchers + expiry, via UI/API/`amtool` | Planned maintenance without editing config |
| **Route** | A tree of matchers → receivers | Right team, right channel, right urgency |

It does **not** evaluate PromQL, and it does **not** store metrics.

```
Prometheus ──HTTP POST /api/v2/alerts──► Alertmanager ──► Slack / PagerDuty / Email / Webhook / …
    (also: every replica posts the same alerts → dedupe happens here)
```

---

## 2. The anatomy of `alertmanager.yml`

```yaml
global:
  resolve_timeout: 5m                # after this with no update, an alert is considered resolved
  smtp_smarthost: 'smtp.example.com:587'
  smtp_from: 'alertmanager@example.com'
  smtp_auth_username: 'alerts@example.com'
  smtp_auth_password_file: /etc/alertmanager/secrets/smtp-pass
  smtp_require_tls: true
  slack_api_url_file: /etc/alertmanager/secrets/slack-webhook   # or slack_api_url:
  pagerduty_url: 'https://events.pagerduty.com/v2/enqueue'
  http_config:                        # default for all notifiers
    proxy_url: 'http://proxy.corp:3128'
    follow_redirects: true
  # opsgenie_api_key_file, victorops_api_key_file, wechat_api_secret_file, ...

templates:
  - '/etc/alertmanager/templates/*.tmpl'

route: { ... }            # exactly one root route
receivers: [ ... ]        # at least one; referenced by name from routes
inhibit_rules: [ ... ]
time_intervals: [ ... ]   # named windows for muting/activation
# mute_time_intervals:    # DEPRECATED since 0.24 — use time_intervals
```

**Validate and reload:**
```bash
amtool check-config alertmanager.yml
amtool check-config --alertmanager.url=http://localhost:9093 alertmanager.yml
kill -HUP $(pgrep alertmanager)              # or POST /-/reload
curl -XPOST localhost:9093/-/reload
```

**Secrets:** every `*_secret`/`*_password`/`*_url` field has a `_file` variant (`slack_api_url_file`, `smtp_auth_password_file`, `pagerduty_routing_key_file`). Use those with mounted Kubernetes Secrets — never inline credentials in a config that lives in Git.

---

## 3. Routing — the part that decides who gets woken up

```yaml
route:
  receiver: default-catchall        # REQUIRED on the root route
  group_by: ['alertname', 'cluster', 'service']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h

  routes:
    # ── 1. Monitoring's own emergencies go straight to SRE ────────────────
    - matchers:
        - alertname =~ "Prometheus.*|Alertmanager.*|Watchdog"
      receiver: sre-pagerduty
      group_by: ['alertname', 'cluster']
      group_wait: 10s
      repeat_interval: 1h
      continue: false

    # ── 2. Everything critical pages the owning team ──────────────────────
    - matchers:
        - severity = "page"
      routes:
        - matchers: [ team = "checkout" ]
          receiver: checkout-pagerduty
        - matchers: [ team = "payments" ]
          receiver: payments-pagerduty
        - matchers: [ team =~ ".+" ]                # any other team with a team label
          receiver: oncall-generic
          active_time_intervals: []                 # pages 24/7
      group_wait: 15s
      group_interval: 5m
      repeat_interval: 4h

    # ── 3. Warnings become tickets, business hours only ───────────────────
    - matchers:
        - severity = "ticket"
      receiver: jira-and-slack-warnings
      group_by: ['alertname', 'service']
      group_wait: 5m
      group_interval: 30m
      repeat_interval: 24h
      active_time_intervals: [business-hours-ist]

    # ── 4. Non-urgent overnight noise gets muted ──────────────────────────
    - matchers:
        - severity = "info"
      receiver: slack-monitoring
      mute_time_intervals: [nights-and-weekends]
      repeat_interval: 24h

    # ── 5. Per-namespace override, and keep matching siblings ─────────────
    - matchers:
        - namespace = "sandbox"
      receiver: slack-sandbox
      continue: true          # also let other routes see this alert
```

### Matching syntax

```yaml
matchers:
  - severity = "page"          # exact       (also written severity == "page")
  - severity != "info"         # not equal
  - alertname =~ "Node.*"      # regex match (fully anchored)
  - team !~ "sandbox|test"     # negative regex
  - 'severity = "page"'        # quote the whole matcher if it contains special chars
```
- Prefer `matchers:` — the old `match:` / `match_re:` maps are **deprecated**.
- Since **0.27**, matchers support **full UTF-8** (label names/values with dots, spaces, non-ASCII). If you hit parser incompatibilities, `--feature-fallback=utf8-strict` / `utf8-loose` control the transition behaviour.
- Match with **labels you control** (`severity`, `team`, `service`, `namespace`) rather than alert-name regexes. Alert names get renamed; labels are a contract.

### `continue` and inheritance

- The tree is walked **top to bottom, depth first**. The **first** matching **leaf** route wins — unless an ancestor or the matched route has `continue: true`, in which case evaluation continues to **sibling** routes (allowing an alert to hit multiple receivers, e.g. "log everything to Slack AND page").
- Children **inherit** `receiver`, `group_by`, `group_wait`, `group_interval`, `repeat_interval`, `mute_time_intervals`, `active_time_intervals` from the parent unless overridden.
- **`group_by` is not merged** — a child's `group_by` fully replaces the parent's. Use `['...']` to group by *all* labels.
- A route with **no matchers** matches everything (a good catch-all; a bad idea mid-tree).

### The four timing parameters (memorise this table)

| Parameter | Default | Applies to | Meaning |
|---|---|---|---|
| **`group_wait`** | 30s | First notification of a **new** group | How long to wait after the *first* alert of a new group arrives, to let siblings join it. Lower = faster pages, more messages. |
| **`group_interval`** | 5m | **Subsequent** notifications for an existing group | How long to wait before sending about *newly added* alerts in the same group. Also gates resolved notifications. |
| **`repeat_interval`** | 4h | **Everything** | How often to re-send the *same, still-firing* group. This is your "still broken" reminder. |
| **`resolve_timeout`** (global) | 5m | Alert lifecycle | If Prometheus stops sending updates for this long, the alert is declared resolved. |

Timeline of an incident:
```
t=0      first alert of group arrives ── wait group_wait (30s)
t=30s    notification #1 sent
t=2m     three more alerts join the group ── wait group_interval (5m)
t=5m     notification #2 sent (contains all 4)
t=9h     still firing ── repeat_interval (4h) → notifications #3 at 5m+4h, #4 at +4h...
t=9h05   problem fixed, Prometheus stops sending ── resolve_timeout (5m) → RESOLVED notification
```

**Tuning heuristics:**
- Pages: `group_wait: 10–30s`, `group_interval: 5m`, `repeat_interval: 2–4h`.
- Tickets: `group_wait: 5m`, `group_interval: 1h`, `repeat_interval: 24h`.
- `repeat_interval` too low ⇒ fatigue; too high ⇒ forgotten incidents. Never set it below `group_interval`.

---

## 4. Grouping in practice

`group_by` determines the **group key**, and one group = one notification.

```yaml
group_by: ['alertname', 'namespace']        # one message per (alertname, namespace)
group_by: ['...']                            # ALL labels → no grouping at all (one msg per alert)
group_by: []                                 # everything into ONE group (dangerous)
```

Choose grouping by asking: *"what would a human want to see in a single message?"*
- A node failure taking down 40 pods → group by `instance`/`node` so it's one message.
- A bad deploy across a service → group by `service` + `alertname`.
- Independent tenant issues → group by `tenant`, so teams see their own.

> Grouping **hides** detail: 40 alerts in one message means the on-call must click through. Add a `dashboard`/`grafana` link in the template, and include a count (`{{ .Alerts | len }}`).

---

## 5. Inhibition — suppressing derived noise

```yaml
inhibit_rules:
  # 1) If the whole node is down, don't also alert about its pods
  - source_matchers: [ alertname = "NodeDown" ]
    target_matchers: [ severity =~ "page|ticket" ]
    equal: ['instance']

  # 2) Critical suppresses warning for the same alert & service
  - source_matchers: [ severity = "critical" ]
    target_matchers: [ severity = "warning" ]
    equal: ['alertname', 'service', 'namespace']

  # 3) A cluster-wide outage suppresses per-service pages
  - source_matchers: [ alertname = "ClusterUnavailable" ]
    target_matchers: [ severity = "page" ]
    equal: ['cluster']

  # 4) SLO burn suppresses the individual latency/error alerts it explains
  - source_matchers: [ alertname =~ "SLO.*Burn.*" ]
    target_matchers: [ alertname =~ "High.*Latency|High.*ErrorRate" ]
    equal: ['service']
```

- **`source_matchers`** — the alert(s) that must be firing to suppress.
- **`target_matchers`** — the alert(s) to suppress.
- **`equal`** — the label names whose values must be **identical** between source and target for the rule to apply. This is the bit everyone forgets: with `equal: ['instance']`, the source alert **must carry the same `instance` label** as the target. If your `NodeDown` rule labels it `node` instead, inhibition silently does nothing.
- Inhibition only suppresses **notifications**; the alert still exists in the UI/API.
- Keep the list short and documented. Over-inhibition = blind spots during real incidents.
- An alert can't inhibit itself (self-inhibition prevention changed in 0.17+).

---

## 6. Silences — planned, expiring, auditable

A silence is a set of matchers + start/end + creator + comment, stored in Alertmanager (and gossiped across the cluster). Matching alerts are **not** notified while the silence is active.

```bash
# Create with amtool
amtool silence add --author="priya@example.com" \
  --comment="Rolling k8s upgrade on prod-cluster-2" \
  --duration=2h \
  cluster="prod-cluster-2" severity="ticket"

# Common variants
amtool silence add --expires=2026-09-15T02:00:00+05:30 --comment="DB maintenance" alertname="PostgresReplicationLag"
amtool silence add --duration=30m instance="10.0.4.11:9100"     # one host

# Manage
amtool silence query                        # list active
amtool silence query --expired              # history
amtool silence expire <silence-id>          # end it now
amtool silence import --file=silences.json  # bulk

# Check what an alert would do
amtool alert query severity="page"
amtool config routes show                   # print the routing tree  ← excellent for debugging
amtool config routes test --verify.receivers=checkout-pagerduty severity="page" team="checkout"
```
```bash
# API
curl -s localhost:9093/api/v2/silences | jq '.[] | {id,matchers,status}'
curl -s -XPOST localhost:9093/api/v2/silences -H 'Content-Type: application/json' -d '{
  "matchers":[{"name":"cluster","value":"prod-2","isRegex":false,"isEqual":true}],
  "startsAt":"2026-09-14T18:00:00+05:30","endsAt":"2026-09-14T20:00:00+05:30",
  "createdBy":"priya@example.com","comment":"k8s upgrade"}'
```

**Silence discipline (write this into your on-call doc):**
- Always set **`createdBy`** and a **`comment`** explaining why.
- Always set an **expiry**. No open-ended silences — ever.
- Prefer **narrow matchers** (`instance="x"`) over broad ones (`severity=~".+"`).
- Review expiring/expired silences weekly; a silence older than a sprint is a rule that should be fixed or deleted.
- Silences are **not** config — they live in Alertmanager's state. In k8s with an ephemeral Alertmanager, they vanish on pod restart unless you persist `/alertmanager` (PVC).
- Alertmanager 0.28+ supports **silence limits** flags to prevent runaway silences.

---

## 7. Time intervals (muting & activation windows)

```yaml
time_intervals:
  - name: nights-and-weekends
    time_intervals:
      - times: [{start_time: '18:30', end_time: '23:59'}]
        weekdays: [monday:friday]
        location: 'Asia/Kolkata'
      - times: [{start_time: '00:00', end_time: '09:00'}]
        weekdays: [monday:friday]
        location: 'Asia/Kolkata'
      - weekdays: [saturday, sunday]
        location: 'Asia/Kolkata'

  - name: business-hours-ist
    time_intervals:
      - times: [{start_time: '09:30', end_time: '18:30'}]
        weekdays: [monday:friday]
        location: 'Asia/Kolkata'

  - name: change-freeze
    time_intervals:
      - months: ['12']
        days_of_month: ['24:31']
```

```yaml
route:
  routes:
    - matchers: [ severity = "ticket" ]
      receiver: jira-and-slack-warnings
      active_time_intervals: [business-hours-ist]   # only notify during these windows
    - matchers: [ severity = "info" ]
      receiver: slack-monitoring
      mute_time_intervals: [nights-and-weekends]    # do NOT notify during these windows
```

Notes:
- **`mute_time_intervals`** (in a route) = suppress during; **`active_time_intervals`** = only deliver during. Define the windows once under the top-level `time_intervals:` key and reference by name. The older top-level `mute_time_intervals:` definition block is deprecated since 0.24 but still parsed.
- **`location`** accepts any IANA timezone (`Asia/Kolkata`, `UTC`, `America/New_York`). If omitted, **times are interpreted as UTC** — the classic "why did my mute window fire at the wrong hour" bug (fixed/clarified in 0.23; always set `location` explicitly).
- Format: `HH:MM` (24h, `end_time` may be `24:00`), `weekdays: [monday:friday]`, `days_of_month: ['1:7','-1']` (negative = from month end), `months: ['1:3','12']`, `years: ['2026:2030']`.
- **Muted alerts are dropped, not queued.** They will not be delivered retroactively when the window opens — if the alert is still firing, the next evaluation inside an active window will notify.
- Never mute `page` severity. Mute `ticket`/`info` only.

---

## 8. Receivers and notifiers

A **receiver** is a named bundle of one or more notifier configs. One alert group → all notifiers of the chosen receiver.

```yaml
receivers:
  # ── Email ───────────────────────────────────────────────────────────────
  - name: platform-email
    email_configs:
      - to: 'platform-oncall@example.com'
        from: 'alertmanager@example.com'
        send_resolved: true
        headers:
          Subject: '[{{ .Status | toUpper }}] {{ .GroupLabels.alertname }} ({{ .Alerts | len }})'
        html: '{{ template "email.html" . }}'
        require_tls: true

  # ── Slack ───────────────────────────────────────────────────────────────
  - name: checkout-slack
    slack_configs:
      - channel: '#checkout-alerts'          # or a user; must exist / bot must be invited
        send_resolved: true
        api_url_file: /etc/alertmanager/secrets/slack-webhook
        title: '{{ template "slack.title" . }}'
        text: '{{ template "slack.text" . }}'
        color: '{{ if eq .Status "firing" }}danger{{ else }}good{{ end }}'
        mrkdwn_in: ['text', 'title', 'fallback']
        actions:
          - type: button
            text: 'Runbook :book:'
            url: '{{ (index .Alerts 0).Annotations.runbook }}'
          - type: button
            text: 'Dashboard :chart_with_upwards_trend:'
            url: '{{ (index .Alerts 0).Annotations.dashboard }}'
          - type: button
            text: 'Silence :no_bell:'
            url: '{{ template "__alert_silence_link" . }}'

  # ── PagerDuty ───────────────────────────────────────────────────────────
  - name: checkout-pagerduty
    pagerduty_configs:
      - routing_key_file: /etc/alertmanager/secrets/pd-checkout-key   # Events API v2
        severity: '{{ if eq .CommonLabels.severity "page" }}critical{{ else }}warning{{ end }}'
        description: '{{ .CommonAnnotations.summary }}'
        details:
          firing: '{{ .Alerts.Firing | len }}'
          resolved: '{{ .Alerts.Resolved | len }}'
          runbook: '{{ .CommonAnnotations.runbook }}'
          dashboard: '{{ .CommonAnnotations.dashboard }}'
          num_alerts: '{{ .Alerts | len }}'
        class: '{{ .CommonLabels.service }}'
        component: '{{ .CommonLabels.namespace }}'
        group: '{{ .GroupLabels.alertname }}'
        send_resolved: true

  # ── Jira (0.28+) ────────────────────────────────────────────────────────
  - name: jira-and-slack-warnings
    jira_configs:
      - api_url: 'https://example.atlassian.net/rest/api/3'
        project: OPS
        issue_type: Task
        summary: '{{ .CommonLabels.alertname }}: {{ .CommonAnnotations.summary }}'
        description: '{{ .CommonAnnotations.description }}'
        priority: '{{ if eq .CommonLabels.severity "ticket" }}Medium{{ else }}Low{{ end }}'
        labels: ['alertmanager', '{{ .CommonLabels.team }}']
        reopen_duration: 2h
    slack_configs:
      - channel: '#alerts-warnings'
        api_url_file: /etc/alertmanager/secrets/slack-webhook

  # ── Webhook (custom: your own bot, Teams via bridge, ServiceNow, etc.) ──
  - name: webhook-automation
    webhook_configs:
      - url: 'http://auto-remediator:5001/alerts'
        send_resolved: true
        max_alerts: 50                      # cap payload size
        http_config:
          bearer_token_file: /etc/alertmanager/secrets/webhook-token

  # ── Others available ────────────────────────────────────────────────────
  #   opsgenie_configs, victorops_configs, wechat_configs, telegram_configs,
  #   discord_configs, webex_configs, msteams_configs (Teams/Workflows),
  #   rocketchat_configs, mattermost_configs (0.30+), pushover_configs,
  #   sns_configs, incidentio_configs (0.29+)
```

**Receiver design rules:**
- **One receiver per (team × channel × urgency)**. `checkout-pagerduty`, `checkout-slack`, `platform-email`.
- Always set **`send_resolved: true`** for pages and Slack — resolution is half the value.
- **`max_alerts`** on webhooks prevents huge payloads from failing delivery.
- Prefer **`*_file`** secret variants.
- A receiver with **multiple notifier configs** fans out to all of them (e.g. Jira + Slack for tickets).

---

## 9. Notification templates

Alertmanager uses Go templates with its **own** function map (`DefaultFuncs`). It is **not** full Sprig — `default`, `coalesce`, `ternary`, `toJSON` (capital J) do **not** exist and will fail at render time. Data available:

| Field | Meaning |
|---|---|
| `.Receiver` | Name of the receiver |
| `.Status` | `"firing"` or `"resolved"` |
| `.Alerts` | List of alerts; `.Alerts.Firing`, `.Alerts.Resolved` |
| `.GroupLabels` | Labels the group was grouped by |
| `.CommonLabels` | Labels shared by **all** alerts in the group |
| `.CommonAnnotations` | Annotations shared by all alerts in the group |
| `.ExternalURL` | Alertmanager's own URL (for silence links) |
| Per alert: `.Labels`, `.Annotations`, `.StartsAt`, `.EndsAt`, `.GeneratorURL`, `.Fingerprint`, `.Status` | |
| `.SilenceURL`, `.Alerts.Firing`, `.TruncatedAlerts` | Available in **real notifications** (via the internal `extendedAlert`), but **not** in `amtool template render`, which uses the public `template.Alert` type. Prefer the `__alert_silence_link` helper so templates work in both. |

> **Use `.CommonLabels` / `.CommonAnnotations` only for values that truly are common.** If one alert in the group lacks the `runbook` annotation, `.CommonAnnotations.runbook` renders empty. Use `(index .Alerts 0).Annotations.runbook` when you need a specific one.

`/etc/alertmanager/templates/base.tmpl`:
```gotemplate
{{ define "__alert_silence_link" -}}
{{ .ExternalURL }}/#/silences/new?filter=%7B{{ range .CommonLabels.SortedPairs -}}
{{ urlquery .Name }}%3D"{{ urlquery .Value }}"%2C%20{{ end -}}%7D
{{- end }}

{{ define "slack.title" -}}
[{{ .Status | toUpper }}{{ if eq .Status "firing" }}:{{ .Alerts.Firing | len }}{{ end }}]
{{ .CommonLabels.alertname }}{{ if gt (len .CommonLabels) 1 }} ({{ .CommonLabels.SortedPairs | len }} labels){{ end }}
{{- end }}

{{ define "slack.text" -}}
{{ range .Alerts }}
*{{ .Labels.severity | toUpper }}* — {{ .Annotations.summary }}
• service: `{{ .Labels.service }}`  namespace: `{{ .Labels.namespace }}`
• started: {{ .StartsAt.Format "2006-01-02 15:04:05 MST" }} ({{ .StartsAt | since | humanizeDuration }} ago)
• {{ .Annotations.description }}
• <{{ .Annotations.runbook }}|Runbook> · <{{ .Annotations.dashboard }}|Dashboard> · <{{ .GeneratorURL }}|Query> · <{{ template "__alert_silence_link" $ }}|Silence>
{{ end }}
{{- end }}

{{ define "email.subject" -}}
[{{ .Status | toUpper }}] {{ .GroupLabels.alertname }} — {{ .CommonLabels.service }} ({{ .Alerts | len }} alerts)
{{- end }}

{{ define "email.html" -}}
<html><body style="font-family:sans-serif">
<h2>{{ .Status | toUpper }}: {{ .GroupLabels.alertname }}</h2>
<table border="1" cellpadding="6" cellspacing="0">
<tr><th>Severity</th><th>Summary</th><th>Instance</th><th>Started</th><th>Links</th></tr>
{{ range .Alerts }}
<tr>
  <td>{{ .Labels.severity }}</td>
  <td>{{ .Annotations.summary }}</td>
  <td>{{ .Labels.instance }}</td>
  <td>{{ .StartsAt.Format "Jan 2 15:04" }}</td>
  <td><a href="{{ .Annotations.runbook }}">Runbook</a> ·
      <a href="{{ .GeneratorURL }}">Prometheus</a> ·
      <a href='{{ template "__alert_silence_link" $ }}'>Silence</a></td>
</tr>
{{ end }}
</table>
</body></html>
{{- end }}
```

**Functions actually available** (Alertmanager 0.34 `DefaultFuncs`, plus Go's `text/template` builtins):

`toUpper` `toLower` `title` `trimSpace` `match` `reReplaceAll` `stringSlice` `safeHtml` `safeUrl` `urlUnescape` `since` `now` `date` `tz` `toDate` `mustToDate` `humanizeDuration` `toJson` `base64encode` `base64decode` `list` `append` `dict` `routeLabels` `join`
builtins: `printf` `print` `println` `len` `index` `slice` `and` `or` `not` `eq` `ne` `lt` `le` `gt` `ge` `urlquery` `html` `js` `call`

⚠️ Three traps:
- **`join` takes the separator FIRST**: `{{ join "," (stringSlice "a" "b") }}` — inverted vs `strings.Join`, deliberately, so it pipelines.
- It is **`safeHtml`** and **`toJson`** (lowercase h / lowercase j). `safeHTML`/`toJSON` are *Prometheus rule* functions, not Alertmanager ones.
- `humanize`, `humanizePercentage`, `humanizeTimestamp`, `first`, `sortByLabel`, `default` are **not** defined here. They exist in **Prometheus rule annotations** (`05-Alerting-Concepts`), which is a different function map — so `{{ $value | humanizePercentage }}` is correct *in a rule* but will break *in a notification template*.

**Test templates without deploying:**
```bash
amtool check-config alertmanager.yml
curl -s -XPOST localhost:9093/api/v2/alerts -H 'Content-Type: application/json' -d '[{
  "labels":{"alertname":"TestAlert","severity":"page","team":"checkout","service":"checkout-api","namespace":"prod"},
  "annotations":{"summary":"This is a test","description":"Verifying templates","runbook":"https://rb.example.com/x","dashboard":"https://g.example.com/d/x"},
  "startsAt":"2026-09-14T12:00:00+05:30"}]'
# then watch it in the UI and in your receiver
```
Even better: point a test receiver at `webhook_configs.url: http://localhost:9999` and `nc -l 9999` to read the rendered JSON.

---

## 10. High availability clustering

Run **3+ replicas** (odd number). Each Prometheus sends alerts to **all** Alertmanagers; they gossip via memberlist, deduplicate, and only one sends each notification.

```bash
alertmanager --config.file=/etc/alertmanager/alertmanager.yml \
  --storage.path=/alertmanager \
  --web.listen-address=0.0.0.0:9093 \
  --cluster.listen-address=0.0.0.0:9094 \
  --cluster.peer=alertmanager-1.alertmanager-headless:9094 \
  --cluster.peer=alertmanager-2.alertmanager-headless:9093 \
  --cluster.advertise-address=10.0.3.21:9094 \
  --cluster.reconnect-timeout=6h \
  --cluster.settle-timeout=1m
```
On the Prometheus side, list **all** Alertmanagers as targets:
```yaml
alerting:
  alertmanagers:
    - kubernetes_sd_configs: [{role: endpoints, namespaces: {names: [monitoring]}}]
      relabel_configs:
        - source_labels: [__meta_kubernetes_service_name]
          regex: alertmanager-operated
          action: keep
        - source_labels: [__meta_kubernetes_endpoint_port_name]
          regex: http-web
          action: keep
```
Check cluster health: `curl -s localhost:9093/api/v2/status | jq '.cluster'` (peers, status `ready`).

**Notification dedup logic:** for each notification group, replicas compute a hash and only the "lowest" peer sends — so you get one message even with three AMs. If you see triple notifications, the cluster is not formed (check `--cluster.peer` DNS and port 9094 reachability).

---

## 11. Observing Alertmanager itself

```promql
# Is it up and clustered?
up{job="alertmanager"} == 0
alertmanager_cluster_members < 2                       # cluster not formed

# Alert throughput and health
rate(alertmanager_alerts_received_total[5m])
alertmanager_alerts{state="active"}
alertmanager_alerts{state="suppressed"}
alertmanager_notifications_total
rate(alertmanager_notifications_failed_total[5m])      # ← MUST be zero; alert on it
alertmanager_notification_requests_total
alertmanager_notification_latency_seconds{quantile="0.99"}
alertmanager_silences{state="active"}
alertmanager_silences_errors_total

# Prometheus → Alertmanager delivery
rate(prometheus_notifications_errors_total[5m])
prometheus_notifications_queue_length                  # backlog = AM unreachable
prometheus_notifications_alerts_dropped_total          # queue overflow, alerts LOST
prometheus_notifications_latency_seconds{quantile="0.99"}
```

**Alerts you must have on your alerting system:**
`AlertmanagerDown`, `AlertmanagerClusterNotFormed`, `AlertmanagerNotificationsFailing`, `PrometheusNotConnectedToAlertmanager` (`prometheus_notifications_queue_length > 0` for 10m), `PrometheusDroppingAlerts` (`prometheus_notifications_alerts_dropped_total > 0`), and the **Watchdog** dead-man's switch (see below).

### Watchdog / dead-man's switch

```yaml
groups:
  - name: watchdog
    rules:
      - alert: Watchdog
        expr: vector(1)          # always true, always firing
        labels:
          severity: none
        annotations:
          summary: "Health-check alert that must ALWAYS be firing."
          description: |
            If an external system stops receiving this alert, the whole
            monitoring pipeline is broken.
```
Route it to a receiver that pings an **external** service (Healthchecks.io, Dead Man's Snitch, Cronitor, PagerDuty heartbeat, or your own canary). That external service pages you if the Watchdog *stops*. Without this, a dead Prometheus is an invisible dead Prometheus.

---

## 12. Grafana Alerting vs Alertmanager — pick one

Since Grafana 9, Grafana has its own **unified alerting** engine that can also run Alertmanager-compatible routing internally.

| | **Prometheus rules + Alertmanager** | **Grafana unified alerting** |
|---|---|---|
| Rule definition | YAML in Git / `PrometheusRule` CRDs | UI or provisioning files; stored in Grafana DB |
| Multi-datasource alerts | No (Prometheus only) | Yes (Loki, CloudWatch, MySQL, …) |
| Kubernetes-native | ✅ CRDs, GitOps, `promtool` tests | Partial |
| Best for | Infra/service alerting at scale | Cross-datasource and business alerts, small teams |
| Risk | Two systems if you also enable Grafana alerts | Alert definitions hidden in a database |

**Recommendation:** in Kubernetes, use **Prometheus rules → Alertmanager** as the single authority, and have Grafana *read* alerts for display only. If you use Grafana alerting, disable duplicate coverage and document which system owns what. Two systems both paging for the same problem is a guaranteed 3 a.m. mess.

---

## 13. Debugging checklist — "the alert didn't arrive"

Work backwards through the pipeline:

| # | Check | Command / where |
|---|---|---|
| 1 | Does the **rule expression** return data? | Grafana Explore / `promtool query instant` |
| 2 | Is the alert in **FIRING** state? | Prometheus UI → Alerts, or `curl localhost:9090/api/v1/alerts` |
| 3 | Did Prometheus **send** it? | `prometheus_notifications_alerts_dropped_total`, `prometheus_notifications_queue_length`, Prometheus logs |
| 4 | Did Alertmanager **receive** it? | AM UI → Alerts; `alertmanager_alerts_received_total` |
| 5 | Is it **silenced**? | AM UI → Silences; `alertmanager_silences{state="active"}` |
| 6 | Is it **inhibited**? | AM UI shows "inhibited" badge; check `equal:` labels match |
| 7 | Is it in a **mute window** / outside an active window? | `amtool config routes show`; check `location` timezone |
| 8 | Did it match the **route you think**? | `amtool config routes test --verify.receivers=X <labels>` |
| 9 | Is it **grouped** into an existing notification still within `repeat_interval`? | AM UI → group view |
| 10 | Did the **notifier fail**? | `alertmanager_notifications_failed_total`, AM logs (`notify error`) |
| 11 | Is the **credential/channel** valid? | Slack webhook revoked, bot not in channel, PD routing key wrong, SMTP auth |
| 12 | Is the **template** rendering empty? | Test with `webhook_configs` → `nc -l 9999` |

The two most common culprits: **(8)** the route didn't match because a label was missing/renamed, and **(6)** inhibition silently suppressed because `equal:` labels didn't line up.

---

## Lab

1. `amtool check-config` the lab's `alertmanager.yml`, then deliberately break a matcher and confirm it fails.
2. `amtool config routes show` — read your tree. Then `amtool config routes test --verify.receivers=critical-page severity="page" team="checkout"` and confirm routing.
3. POST a fake alert with `curl` and watch it appear, get grouped, and be delivered to the webhook receiver (`nc -l 9999`).
4. Create a silence with `amtool silence add --duration=10m alertname="TestAlert"` and confirm the notification stops; expire it early.
5. Add an `inhibit_rule` where `NodeDown` suppresses `InstanceDown` with `equal: ['instance']`, then break the `equal` label and observe inhibition stop working.
6. Add a `mute_time_intervals` entry for the next 2 minutes in `Asia/Kolkata` and confirm the alert is muted; remove the `location` and see the window shift by 5:30.
7. Check `alertmanager_notifications_failed_total` after pointing a receiver at a dead URL.

---

## Self-check

1. Name Alertmanager's five jobs and the config block for each.
2. `group_wait` vs `group_interval` vs `repeat_interval` — one sentence each, plus their defaults.
3. Why does a child route's `group_by` not merge with the parent's?
4. In `inhibit_rules`, what does `equal:` actually require, and why do inhibition rules silently fail?
5. `mute_time_intervals` vs `active_time_intervals` — which would you use for tickets?
6. What happens to alerts during a mute window — are they queued?
7. Difference between a silence and an inhibition rule. When do you use each?
8. How do you run Alertmanager highly available, and what dedupes the notifications?
9. Name the three metrics that tell you notifications are failing to be delivered.
10. What is a Watchdog alert and what external dependency does it require?
11. `.CommonAnnotations.summary` renders empty in your Slack message — why, and what do you use instead?
12. Walk the 12-step checklist for "the alert didn't arrive" from memory.

→ Next: [`07-Grafana-Dashboards`](../07-Grafana-Dashboards/README.md)
