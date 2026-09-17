# Cheatsheet · Alertmanager

## Config skeleton

```yaml
global:
  resolve_timeout: 5m
  smtp_smarthost: 'smtp.example.com:587'
  smtp_from: 'alerts@example.com'
  smtp_auth_username: '...'
  smtp_auth_password_file: /etc/alertmanager/secrets/smtp-pass
  smtp_require_tls: true
  slack_api_url_file: /etc/alertmanager/secrets/slack-url
  pagerduty_url: 'https://events.pagerduty.com/v2/enqueue'
  http_config: {proxy_url: '...', follow_redirects: true}

templates: ['/etc/alertmanager/templates/*.tmpl']
route: { ... }
receivers: [ ... ]
inhibit_rules: [ ... ]
time_intervals: [ ... ]
```
Every secret field has a `_file` variant: `slack_api_url_file`, `smtp_auth_password_file`, `pagerduty_routing_key_file`, `webhook_configs.http_config.bearer_token_file`, `opsgenie_api_key_file`, …

## Route

```yaml
route:
  receiver: catchall            # REQUIRED on the root
  group_by: ['alertname', 'cluster', 'service']   # ['...'] = all labels = no grouping
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  continue: false
  routes:
    - matchers: [ severity = "page" ]
      receiver: pagerduty-critical
      group_wait: 10s
      repeat_interval: 2h
      continue: false
      mute_time_intervals: []
      active_time_intervals: []
```

**Matching syntax** (prefer `matchers:` — `match:`/`match_re:` are deprecated):
```yaml
matchers:
  - severity = "page"
  - severity != "info"
  - alertname =~ "Node.*"       # regex, fully anchored
  - team !~ "sandbox|test"
  - 'severity = "page"'         # quote the whole matcher if needed
```
UTF-8 matchers supported since 0.27.

**Tree rules:** depth-first, first matching leaf wins · `continue: true` also evaluates siblings · children inherit everything except that `group_by` is **replaced**, not merged · a route with no matchers matches all.

## The four timings

| Parameter | Default | Meaning |
|---|---|---|
| `group_wait` | 30s | Wait after the **first** alert of a **new group** before sending, so siblings join |
| `group_interval` | 5m | Wait before sending about **new alerts in an existing group** (also gates resolved) |
| `repeat_interval` | 4h | Re-send the **same still-firing** group |
| `global.resolve_timeout` | 5m | No update for this long ⇒ alert declared resolved |

Pages: `10–30s / 5m / 2–4h` · Tickets: `5m / 1h / 24h`. Never `repeat_interval < group_interval`.

## Inhibition

```yaml
inhibit_rules:
  - source_matchers: [ alertname = "NodeDown" ]
    target_matchers: [ severity =~ "page|ticket" ]
    equal: ['instance']
```
`equal` labels must exist **and match** on both source and target — the #1 reason inhibition silently fails. Inhibition suppresses **notifications only**; alerts still show in the UI.

## Silences

```bash
amtool silence add --author="me@x.com" --comment="why" --duration=2h \
  cluster="prod-2" severity="ticket"
amtool silence add --expires=2026-09-15T02:00:00+05:30 --comment="DB maint" alertname="X"
amtool silence query
amtool silence query --expired
amtool silence expire <id>
amtool silence import --file=silences.json
```
```bash
curl -XPOST localhost:9093/api/v2/silences -H 'Content-Type: application/json' -d '{
  "matchers":[{"name":"cluster","value":"prod-2","isRegex":false,"isEqual":true}],
  "startsAt":"2026-09-14T18:00:00+05:30","endsAt":"2026-09-14T20:00:00+05:30",
  "createdBy":"me@x.com","comment":"upgrade"}'
curl -XDELETE localhost:9093/api/v2/silence/<id>
```
Always: author + comment + expiry + narrow matchers.

## Time intervals

```yaml
time_intervals:
  - name: nights-and-weekends
    time_intervals:
      - times: [{start_time: '19:00', end_time: '23:59'}]
        weekdays: [monday:friday]
        location: 'Asia/Kolkata'
      - weekdays: [saturday, sunday]
        location: 'Asia/Kolkata'
      - months: ['12']
        days_of_month: ['24:31']
        years: ['2026:2030']
```
```yaml
route:
  routes:
    - matchers: [severity = "ticket"]
      active_time_intervals: [business-hours-ist]   # only deliver during
    - matchers: [severity = "info"]
      mute_time_intervals: [nights-and-weekends]    # do not deliver during
```
**`location` is required** — without it, times are **UTC**. Muted alerts are **dropped, not queued**. Top-level `mute_time_intervals:` definitions are deprecated since 0.24 (use `time_intervals:`).

## Receivers

```yaml
receivers:
  - name: email-sre
    email_configs:
      - to: 'sre@example.com'
        send_resolved: true
        headers: {Subject: '{{ template "email.subject" . }}'}
        html: '{{ template "email.html" . }}'

  - name: slack-team
    slack_configs:
      - channel: '#team-alerts'
        api_url_file: /etc/alertmanager/secrets/slack-url
        send_resolved: true
        title: '{{ template "slack.title" . }}'
        text: '{{ template "slack.text" . }}'
        color: '{{ template "__alert_severity_color" . }}'
        mrkdwn_in: ['text','title','fallback']
        actions:
          - {type: button, text: 'Runbook', url: '{{ (index .Alerts 0).Annotations.runbook }}'}
          - {type: button, text: 'Silence', url: '{{ template "__alert_silence_link" . }}'}

  - name: pagerduty-critical
    pagerduty_configs:
      - routing_key_file: /etc/alertmanager/secrets/pd-key
        severity: '{{ if eq .CommonLabels.severity "page" }}critical{{ else }}warning{{ end }}'
        description: '{{ .CommonAnnotations.summary }}'
        class: '{{ .CommonLabels.service }}'
        component: '{{ .CommonLabels.namespace }}'
        details:
          runbook: '{{ .CommonAnnotations.runbook }}'
          dashboard: '{{ .CommonAnnotations.dashboard }}'
          num_alerts: '{{ .Alerts | len }}'
        send_resolved: true

  - name: jira-warnings
    jira_configs:
      - api_url: 'https://x.atlassian.net/rest/api/3'
        project: OPS
        issue_type: Task
        summary: '{{ .CommonLabels.alertname }}: {{ .CommonAnnotations.summary }}'
        priority: Medium
        reopen_duration: 2h

  - name: webhook-auto
    webhook_configs:
      - url: 'http://remediator:5001/alerts'
        send_resolved: true
        max_alerts: 50
        http_config: {bearer_token_file: /etc/alertmanager/secrets/token}
```

**All notifier types:** `email_configs` · `pagerduty_configs` · `slack_configs` · `webhook_configs` · `opsgenie_configs` · `victorops_configs` · `wechat_configs` · `telegram_configs` · `discord_configs` · `webex_configs` · `msteams_configs` · `rocketchat_configs` · `mattermost_configs` (0.30+) · `pushover_configs` · `sns_configs` · `incidentio_configs` (0.29+) · `jira_configs` (0.28+).

## Template data

| Field | Meaning |
|---|---|
| `.Receiver` | receiver name |
| `.Status` | `firing` / `resolved` |
| `.Alerts` · `.Alerts.Firing` · `.Alerts.Resolved` | lists |
| `.GroupLabels` | grouping labels |
| `.CommonLabels` · `.CommonAnnotations` | present on **all** alerts in the group |
| `.ExternalURL` | this Alertmanager |
| `.TruncatedAlerts` | count dropped by `max_alerts` |
| per alert | `.Labels` `.Annotations` `.StartsAt` `.EndsAt` `.GeneratorURL` `.Fingerprint` `.Status` |
| `.SilenceURL` `.TruncatedAlerts` `.Alerts.Firing` | present in real notifications, **absent** in `amtool template render` |

**Functions (Alertmanager 0.34 `DefaultFuncs` — NOT full Sprig):**
`toUpper` `toLower` `title` `trimSpace` `match` `reReplaceAll` `stringSlice` `safeHtml` `safeUrl` `urlUnescape` `since` `now` `date` `tz` `toDate` `mustToDate` `humanizeDuration` `toJson` `base64encode` `base64decode` `list` `append` `dict` `routeLabels` `join` + Go builtins (`printf` `len` `index` `and` `or` `not` `eq/ne/lt/le/gt/ge` `urlquery` `html`).

⚠️ `join` takes the **separator first**. It's `safeHtml`/`toJson`, not `safeHTML`/`toJSON`. **Unavailable:** `default`, `humanize`, `humanizePercentage`, `humanizeTimestamp`, `first`, `sortByLabel` — those belong to *Prometheus rule annotations*, a different function map.

⚠️ `.CommonAnnotations.x` renders **empty** if any alert in the group lacks it → use `(index .Alerts 0).Annotations.x`.

## HA cluster

```bash
alertmanager --config.file=... --storage.path=/alertmanager \
  --web.listen-address=0.0.0.0:9093 \
  --cluster.listen-address=0.0.0.0:9094 \
  --cluster.peer=am-1.am-headless:9094 \
  --cluster.peer=am-2.am-headless:9094 \
  --cluster.advertise-address=<this-pod-ip>:9094 \
  --cluster.reconnect-timeout=6h --cluster.settle-timeout=1m
```
Odd number ≥ 3 replicas; every Prometheus sends to **all** of them; gossip dedupes notifications.

## Self-monitoring

```promql
up{job="alertmanager"} == 0
alertmanager_cluster_members < 2
rate(alertmanager_notifications_failed_total[5m]) > 0
rate(alertmanager_notifications_total[5m])
alertmanager_notification_latency_seconds{quantile="0.99"}
alertmanager_alerts{state="active"}
alertmanager_alerts{state="suppressed"}
alertmanager_silences{state="active"}
rate(alertmanager_alerts_received_total[5m])
prometheus_notifications_queue_length
prometheus_notifications_alerts_dropped_total
```

## amtool

```bash
amtool check-config alertmanager.yml
amtool check-config --alertmanager.url=http://localhost:9093 alertmanager.yml
amtool config routes show
amtool config routes test --verify.receivers=<name> label="value" ...
amtool alert query [matchers]
amtool alert query --expired
amtool silence add|query|expire|import
amtool template render --template.glob='templates/*.tmpl' --template.text='{{ template "slack.text" . }}'
amtool template render --template.glob='templates/*.tmpl' --template.text='{{ template "email.html" . }}' --template.type=html
amtool template render --template.glob='t.tmpl' --template.text='...' --template.data=alert.json
```
Set `ALERTMANAGER_URL` env var to avoid repeating the flag.

## HTTP API

```
GET  /api/v2/alerts?filter=severity="page"&silenced=false&inhibited=false
GET  /api/v2/alerts/groups
POST /api/v2/alerts                      # inject alerts (great for testing)
GET  /api/v2/silences   POST /api/v2/silences   GET/DELETE /api/v2/silence/{id}
GET  /api/v2/receivers
GET  /api/v2/status                      # cluster info, config, uptime, version
POST /-/reload   POST /-/quit
GET  /-/healthy  /-/ready
GET  /metrics
```

## "The alert didn't arrive" — 12-step checklist

1. Does `expr` return data? (Grafana Explore / `promtool query instant`)
2. Is the alert `FIRING`? (`curl localhost:9090/api/v1/alerts`)
3. Did Prometheus send it? (`prometheus_notifications_queue_length`, `..._alerts_dropped_total`, logs)
4. Did Alertmanager receive it? (AM UI, `alertmanager_alerts_received_total`)
5. Silenced? (AM UI → Silences)
6. Inhibited? (AM UI badge; check `equal:` labels)
7. Inside a `mute_time_interval` / outside an `active_time_interval`? (check `location` timezone)
8. Matched the route you think? (`amtool config routes test --verify.receivers=X`)
9. Grouped into a notification still within `repeat_interval`?
10. Notifier failing? (`alertmanager_notifications_failed_total`, AM logs)
11. Credential/channel valid? (revoked webhook, bot not in channel, wrong routing key)
12. Template rendering empty? (`webhook_configs` → `nc -l 9999`)

Most common: **#8** (label mismatch) and **#6** (`equal:` labels don't line up).
