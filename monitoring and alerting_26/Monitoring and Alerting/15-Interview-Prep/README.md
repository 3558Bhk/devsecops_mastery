# 15 · Interview Prep

**Level:** consolidation · **Time:** ~3 h + repeated revision · **Goal:** answer monitoring/alerting questions with structure, numbers and trade-offs — not definitions.

---

## How to answer

Interviewers in this domain are testing three things:

1. **Do you have opinions backed by experience?** ("We alert on symptoms because…")
2. **Do you know the trade-offs?** (histogram vs summary, pull vs push, Thanos vs Mimir)
3. **Can you debug under pressure?** ("the alert didn't fire" — walk the pipeline)

**Format that works:** *answer in one sentence → explain the mechanism → give the trade-off → give a concrete example from your work.* Numbers beat adjectives: "we cut pages from 40 to 4 per shift by moving cause alerts to tickets and adding inhibition" is a senior answer.

Never say "it depends" without immediately saying *what it depends on*.

---

## A · Fundamentals

**1. What's the difference between monitoring, alerting and observability?**
Monitoring is collecting and visualising telemetry to answer *what is happening*. Alerting is deciding that a human must act now and delivering that to them. Observability is a *property of the system* — can you diagnose a failure mode you've never seen before from its external outputs? Metrics, logs and traces are the instruments; observability is the outcome you get when they're well correlated.

**2. Name the three pillars and when you'd use each.**
Metrics (aggregated numbers over time — cheap, aggregatable, best for alerting and trends, can't tell you *why*). Logs (discrete events — best for root cause and audit, expensive, terrible for alerting at scale). Traces (a tree of spans for one request — best for latency attribution across services, sampled so you may miss the failing request). During an incident: **detect with metrics, localise with traces, diagnose with logs.**

**3. What are the Four Golden Signals?**
Latency (measured separately for success and failure — a fast 500 isn't good), Traffic, Errors, Saturation (the most constrained resource *and its trend*). Plus the two frameworks built on them: **RED** (Rate/Errors/Duration) for request-driven services, **USE** (Utilisation/Saturation/Errors) for resources. I use RED at the service edge for symptom alerts, USE on the resources underneath for cause dashboards.

**4. Pull vs push — trade-offs?**
Pull: the collector controls the scrape rate, has centralised target discovery, and crucially **absence of data is a first-class signal** (`up == 0`). Downsides: needs network reachability to the target, and is awkward for short-lived jobs (hence Pushgateway) and for targets behind NAT. Push: works through NAT, natural for batch jobs and agents, but you only know about what reported in — a dead pusher is silent, so you need explicit heartbeat/staleness alerting.

**5. Symptom vs cause alerting. Why does it matter?**
Symptom alerts measure user-visible impact (error ratio, latency, availability) — these should page, because they're urgent, actionable and rare. Cause alerts measure internal state (CPU 85%, a pod restarted) — these belong on dashboards or in tickets, because high CPU with happy users is *success*, not an incident. Alerting on causes produces alert storms: one node failure generates 400 pod alerts. The exception: cause alerts are legitimately pageable when they're **leading indicators with a clear time-boxed action** — disk full in 4 hours, certificate expiring in 7 days, connection pool at 95%.

**6. What is alert fatigue and how do you fix it?**
It's the state where on-call has learned that pages don't require action. You measure it first — pages per shift, percentage of pages that led to an action, top-N noisiest alerts by count. Then weekly review the top 5 and for each decide **fix / demote / delete**: add or lengthen `for:`, add a traffic guard, use `keep_firing_for:`, group and inhibit in Alertmanager, move cause alerts to tickets, mute non-urgent routes overnight. The policy that raises recall fastest: **every user-reported outage that monitoring didn't catch gets a bug filed against the monitoring system.**

**7. How do you decide an alert should page someone?**
Three tests, all must pass: **urgent** (needs action within minutes), **actionable** (a human can do something about it), **rare** (not routine). If any fails, it's a dashboard panel or a ticket. And every page must have a runbook link — an alert with no documented first action is an unfinished alert.

**8. What's a dead-man's switch and why is it non-negotiable?**
An alert whose expression is `vector(1)` — always firing — routed to an *external* service (Healthchecks.io, PagerDuty heartbeat) that pages you if it *stops* arriving. Without it, a dead Prometheus is an invisible dead Prometheus: no data means no alerts, which looks exactly like "everything is fine". It validates the entire pipeline, including Alertmanager and the notifier.

**9. Monitoring maturity — where do most teams sit?**
Level 0 blind (users report outages) → 1 dashboards only → 2 symptom alerting with paging → 3 SLO-driven with error budgets → 4 predictive + automated remediation + alert-review rituals. Most teams are at 1 and believe they're at 3. The tell: if you can't state your SLO and current burn rate in one sentence, you're not at 3.

---

## B · Prometheus

**10. Describe the lifecycle of a metric sample.**
Service discovery produces candidate targets → `relabel_configs` filters and rewrites them into the final target list → every `scrape_interval` Prometheus GETs `/metrics` and parses the exposition format → `metric_relabel_configs` runs per-sample (keep/drop/rewrite) → samples are appended to the WAL and the in-memory head block → every 2 hours the head is cut into an immutable block on disk → the compactor merges blocks and deletes data past retention → the rule manager evaluates recording and alerting rules on `evaluation_interval`, sending firing alerts to Alertmanager.

**11. `relabel_configs` vs `metric_relabel_configs`?**
`relabel_configs` runs **before** the scrape, at the **target** level — it sees `__meta_*`, `__address__`, `__metrics_path__`, `__param_*`, and decides which targets exist and what labels they get. `metric_relabel_configs` runs **after** the scrape, **per sample** — it sees the actual metric name and labels, and is your cardinality weapon (drop metrics, `labeldrop` volatile labels, normalise paths). If a target is missing, it's `relabel_configs`; if a metric is missing but the target is up, it's `metric_relabel_configs`.

**12. What is cardinality and why does it matter?**
Cardinality is the number of distinct time series, and it's the **product** of the distinct values of each label. One metric with 50 pods × 400 paths × 5 methods × 10 statuses is a million series. Every series costs head-block memory (~1–3 KB), index size, disk and query time. It's the #1 cause of Prometheus OOM. Also **churn** matters — ephemeral labels (pod names, request IDs) create series that live briefly but still cost index writes and memory.

**13. How do you find and fix a cardinality problem?**
Find: `promtool tsdb analyze`, the Status → TSDB Status page, `prometheus_tsdb_head_series`, `rate(prometheus_tsdb_head_series_created_total[5m])` for churn, and `topk(10, count by (__name__)({__name__=~".+"}))`. Fix, in ROI order: drop unused metrics with `metric_relabel_configs`; `labeldrop` high-cardinality labels (`id`, `uid`, `image_id`, `device`); normalise unbounded values (`/users/12345` → `/users/:id`); `hashmod` identifiers into buckets when you need distribution not identity; reduce scrape intervals on low-value jobs; restrict exporters to the metric families you use; shorten raw retention and rely on downsampling; finally shard or move to a remote-write backend.

**14. How does Prometheus do HA?**
It doesn't cluster. You run **two identical replicas** with different `external_labels.replica`, both scraping everything, both sending alerts to all Alertmanagers. Alertmanagers form a gossip cluster and dedupe notifications. Queries see duplicates unless you dedupe at the query layer (Thanos `--query.replica-label`, Mimir HA tracker). Alternatives: **sharding** targets across N servers with `hashmod` on `__address__`, or **federation** pulling recording rules from regional servers.

**15. What's new in Prometheus 3.x?**
New UI with a PromLens-style query tree; **full UTF-8 metric and label names** (so OTel names like `http.server.request.duration` work natively); a **native OTLP receiver** (`--web.enable-otlp-receiver` → `/api/v1/otlp/v1/metrics`) with configurable translation strategies and resource-attribute promotion; **Remote Write 2.0** carrying metadata, exemplars, created timestamps and native histograms with string interning (auto-negotiated, falls back to 1.0); **agent mode promoted to a stable flag** `--agent.mode`; several feature flags became default and were removed; range selectors became left-open right-closed; log fields changed from go-kit `ts`/`caller` to slog `time`/`source`. Native histograms are still experimental behind a flag.

**16. Storage internals and sizing.**
WAL for crash recovery, in-memory head block holding ~2–3 h, immutable 2-hour blocks on disk that get compacted. Empirically ~1–2 bytes per compressed sample. So: `samples/sec = active_series / scrape_interval`; `disk = samples/sec × retention_seconds × 1.5 bytes`. Example: 500k series at 15 s over 30 days ≈ 33k samples/s ≈ 130 GB. Head memory ≈ 1–3 KB × active series, plus several GB for query overhead and GC. Always set **both** `retention.time` and `retention.size`.

**17. When is Pushgateway right, and what do you lose?**
Right for short-lived batch jobs that may not survive a scrape interval. You lose three things: the `up` signal (Pushgateway is always up even if the job died), automatic staleness (pushed metrics persist forever, so a dead job looks healthy — you must alert on `push_time_seconds`), and push-rate control (the app decides how much it sends). Prefer a long-running exporter or OTLP push where possible, and set `honor_labels: true` when scraping it.

**18. Prometheus has no authentication. How do you secure it?**
`--web.config.file` gives TLS and basic auth for the web endpoint (and mTLS via `client_auth_type: RequireAndVerifyClientCert`). Otherwise put a reverse proxy in front for authn/authz, restrict with Kubernetes NetworkPolicy, use `*_file` variants for all secrets so credentials come from mounted Secrets rather than Git, enable RBAC-minimal ServiceAccounts for discovery, and never expose `:9090` to the internet. Also be careful with `--web.enable-admin-api` (delete_series) and `--web.enable-remote-write-receiver`/OTLP (unauthenticated write endpoints).

---

## C · PromQL

**19. The four PromQL types.**
Instant vector (series each with one current sample), range vector (series each with a window of samples — **cannot be graphed directly**, must go through a function), scalar, string.

**20. `rate` vs `irate` vs `increase`.**
`rate` is the per-second average over the window and handles counter resets — use it for alerts and most dashboards. `irate` uses only the last two samples, so it's volatile and spiky — graphs only, never alerts. `increase` is `rate × window` — the extrapolated count over the window, so it can return non-integers like 4.98 for 5 events; that's expected. All three are for **counters only**; gauges use `delta`.

**21. Why must the range window be ≥ 2× the scrape interval?**
Because `rate` needs at least two samples in the window. With a 15 s scrape and a `[15s]` window, a single missed or delayed scrape empties the window and you get gaps and zeros. 4× is the safe default, and in Grafana `$__rate_interval` computes `max(4 × scrape interval, $__interval)` for you — which is why it's the right choice in every panel.

**22. Why is `rate(sum(x)[5m])` wrong?**
Because summing counters from different instances produces a series that *decreases* whenever any instance restarts. `rate` interprets that as a counter reset and compensates, giving you garbage. Always `rate` per-series first, then aggregate: `sum(rate(x[5m]))`. For percentiles the same principle applies in the other order: `rate` per bucket → `sum by (le)` → `histogram_quantile` last.

**23. Write a global p99 latency query and explain it.**
`histogram_quantile(0.99, sum by (le) (rate(http_request_duration_seconds_bucket[5m])))`. `rate` gives per-second bucket rates and handles resets; `sum by (le)` merges all instances into one global bucket set — this is only valid because histogram buckets are **counts**, which are additive; `histogram_quantile` then interpolates linearly within the bucket containing the 99th percentile. That interpolation is why bucket boundaries matter: if all traffic lands in `+Inf`, you learn nothing.

**24. Histogram vs summary — the aggregation argument.**
Histogram buckets are additive across instances, so you can compute a correct global p99 at query time, and you can choose the quantile afterwards. Summaries compute quantiles client-side, so the values are **not aggregatable** — averaging p99s across pods is mathematically wrong. Summaries are cheaper in series count but cost client CPU. Default to histograms; use native histograms when you need high resolution without the bucket-count cost.

**25. `on()` / `ignoring()` / `group_left`?**
Binary operators match one-to-one on identical label sets. When they differ, `ignoring(labels)` excludes those labels from matching and `on(labels)` restricts matching to only those. When one side has multiple series per match (one-to-many), `group_left(extra_labels)` says "the left side is the many side; keep its labels and copy these extra labels from the right". Classic use: dividing per-status error rates by per-job totals, or joining an info metric to attach `version` labels.

**26. What does `< bool 0.1` change?**
Without `bool`, a comparison **filters**: only series satisfying it are returned — which is what you want in an alert expression. With `bool`, **all** series are returned with value 1 or 0, which never filters. Mixing these up is the classic "my alert never fires" or "my alert always fires" bug.

**27. How do you alert on a metric that stops existing?**
`absent(up{job="payments"})` returns 1 when the vector is empty, and `absent_over_time(x[5m])` when there are no samples in the window. Without it, an alert on a missing series can never fire — there's no data to evaluate. Every critical SLI needs an `absent()` companion alert.

**28. Your PromQL query returns empty. Debug it.**
Peel layers. Run the bare metric name — if empty it's a data problem, not a query problem. Add the function — if it goes empty, the range window is too small. Add the aggregation — if empty, the `by` label doesn't exist on the series. Add the division or `and` — if empty, label sets don't match, so use `on()`/`ignoring()`/`group_left`, or check for an extra `pod`/`container`/`instance` label. `NaN` means 0/0 or `histogram_quantile` over an empty bucket set. Duplicate lines in Grafana mean a label you didn't aggregate away.

**29. How do you make PromQL cheaper?**
Always include a metric name (never `{__name__=~".+"}`); aggregate early with `sum by`; replace repeated expensive queries with **recording rules**; avoid subqueries on wide series; set Grafana `Min step` to the scrape interval and use `$__rate_interval`; cap the server with `--query.max-concurrency`, `--query.timeout` and `--query.max-samples`; and use `--query.log-file` to find who's actually expensive.

---

## D · Alerting

**30. Anatomy of an alert rule.**
`expr` (a symptom, ideally referencing a recording rule), `for` (hysteresis), optionally `keep_firing_for` (anti-flap on resolution), `labels` (machine-readable: `severity`, `team`, `service` — these define identity and drive routing), `annotations` (human-readable: `summary` with `$value`, `description`, `runbook`, `dashboard`).

**31. Labels vs annotations — the deciding question.**
"Does this value distinguish one alert from another?" If yes → **label** (it changes the fingerprint, so it changes identity, grouping and can multiply alert volume). If it's descriptive → **annotation** (safe, no identity impact). That's why putting `pod` in an alert's labels for a service-level problem causes an alert storm: you get one alert per pod instead of one per service.

**32. What are the alert states and transitions?**
INACTIVE → PENDING when the expression first becomes true → FIRING after it has been continuously true for `for:` → back to INACTIVE when the expression goes false (and RESOLVED is sent, or held for `keep_firing_for:`). If the expression flickers false during PENDING, the timer **resets**.

**33. How do you size `for:`?**
It must exceed your noise floor: never shorter than `evaluation_interval`, and generally ≥ 2–3 scrape intervals. Target-down 2–5 m; SLO burn 2–15 m (the burn-rate windows already smooth); disk-filling 15–30 m; cert expiry hours; crashloop 5–10 m. If `for:` is longer than the incident, you learn about the outage after it ends — that's when you want multi-window burn rates instead.

**34. Why recording rules before alerts?**
Four reasons: alerts become trivial and cheap (`job:http_error_ratio:rate5m > 0.02`); dashboards and alerts use **exactly the same numbers** so nobody argues about which is right; expensive PromQL is computed once per evaluation interval instead of once per panel per user; and the SLI's history is stored, so you can trend it even after raw data is downsampled. Naming convention `level:metric:operations`, and the `:` matters for federation matchers.

**35. How do you stop flapping?**
Increase `for:`; add `keep_firing_for:` so resolution isn't instant; add hysteresis (fire at 80%, resolve at 70%); widen the range window to ≥ 4× scrape interval; prefer `rate` over `irate`; aggregate away volatile labels so autoscaling doesn't change the denominator; and dedupe replicas. Then measure: `changes(up[30m])` and the count of alerts that resolve within 5 minutes.

**36. How do you test alerts before production?**
Four levels. **Unit tests** with `promtool test rules` — synthetic input series, assert which alerts fire at which `eval_time` with which labels and annotations; this belongs in CI. **Historical validation** — paste the expr into Explore over 7–30 days and confirm it would have fired exactly when you wanted. **End-to-end** — point a receiver at a webhook sink and inspect the rendered payload. **Chaos** — actually break the thing in staging (`docker stop`, inject 500s, fill the disk); if the alert doesn't fire, you don't have monitoring.

**37. What's the biggest anti-pattern you've seen?**
Alerting on every cause with no grouping. A node fails, 400 pod alerts page the same channel, nobody can find the one that matters, and afterwards people silence instead of fixing. The fix is architectural: one symptom page per user-visible impact, cause alerts demoted to tickets or dashboards, Alertmanager grouping by node/service, and an inhibition rule where `NodeDown` suppresses everything with the same `instance`.

---

## E · Alertmanager

**38. What does Alertmanager do?**
Five jobs: **deduplicate** (by fingerprint, so HA replicas don't double-page), **group** (400 alerts → 1 notification), **inhibit** (suppress derived noise), **silence** (time-boxed matchers for planned work), and **route** (a matcher tree to receivers). It does not evaluate PromQL and stores no metrics.

**39. `group_wait` vs `group_interval` vs `repeat_interval`.**
`group_wait` (default 30s) is how long to wait after the *first* alert of a *new* group before sending, so siblings can join. `group_interval` (5m) is how long to wait before sending about *newly added* alerts in an existing group — it also gates resolved notifications. `repeat_interval` (4h) is how often to re-send the *same still-firing* group. `global.resolve_timeout` (5m) declares an alert resolved when updates stop. Pages want short `group_wait` and 2–4 h repeats; tickets want long waits and 24 h repeats. Never set `repeat_interval` below `group_interval`.

**40. How does routing work, and what does `continue` do?**
A single root route with a tree of child routes, walked top-to-bottom depth-first; the **first matching leaf wins**. Children inherit receiver, grouping, timings and intervals from the parent — except `group_by`, which is **replaced**, not merged. `continue: true` makes evaluation proceed to sibling routes too, so one alert can reach multiple receivers (log to Slack *and* page). A route with no matchers matches everything. Prefer matching on labels you control (`severity`, `team`, `service`) over alert-name regexes, because alert names get renamed.

**41. How do inhibition rules work, and why do they silently fail?**
`source_matchers` must be firing, `target_matchers` identify what to suppress, and `equal:` lists label names whose values must be **identical** on both sides. The silent failure is almost always `equal:` — if your `NodeDown` alert carries `node` but the target alerts carry `instance`, they never match and inhibition does nothing. It only suppresses **notifications**; the alerts still exist in the UI. Keep the list short and documented: over-inhibition creates blind spots.

**42. Silence vs inhibition vs mute_time_interval?**
A **silence** is ad-hoc, time-boxed, matcher-based, created at runtime (UI/API/amtool) for planned work — it needs an author, a comment and an expiry, and it lives in Alertmanager's state (so it needs a persistent volume). An **inhibition rule** is permanent config expressing "this alert explains those alerts". A **mute/active time interval** is a recurring schedule (nights, weekends, business hours) attached to a route — and crucially, muted alerts are **dropped, not queued**. Never mute `page` severity.

**43. Why does the `location` field in time_intervals matter?**
Because without it, times are interpreted as **UTC**. For a team in India that shifts your "nights and weekends" window by 5h30m, so alerts you meant to mute get delivered at 2 a.m. and the ones you meant to deliver get muted. Always set `location: 'Asia/Kolkata'` (or whatever IANA zone) explicitly on every interval.

**44. How do you run Alertmanager highly available?**
Three or more replicas (odd number), each with `--cluster.listen-address` and `--cluster.peer` pointing at the others, gossiping over memberlist on port 9094. Every Prometheus sends alerts to **all** Alertmanagers; the cluster dedupes so only one replica sends each notification. Each replica needs a persistent volume for silences and the notification log. If you see triple notifications, the cluster hasn't formed — check peer DNS and 9094 reachability.

**45. Template gotchas?**
`.CommonLabels` and `.CommonAnnotations` contain only values present on **every** alert in the group — if one alert lacks `runbook`, `.CommonAnnotations.runbook` renders empty. Use `(index .Alerts 0).Annotations.runbook` when you need a specific one. Also: `send_resolved: true` for pages and chat; `max_alerts` on webhooks to bound payload size; always include a silence link and a deep-linking dashboard URL with variables pre-filled.

**46. "The alert didn't arrive." Walk me through it.**
Twelve steps backwards through the pipeline: (1) does `expr` return data; (2) is the alert FIRING in Prometheus; (3) did Prometheus send it — check `prometheus_notifications_queue_length` and `alerts_dropped_total`; (4) did Alertmanager receive it; (5) is it silenced; (6) is it inhibited — check `equal:` labels; (7) is it inside a mute window or outside an active window — check the timezone; (8) did it match the route you think — `amtool config routes test --verify.receivers=X`; (9) is it grouped into a notification still within `repeat_interval`; (10) is the notifier failing — `alertmanager_notifications_failed_total`; (11) is the credential/channel valid; (12) is the template rendering empty. The two most common culprits are 8 and 6.

**47. Grafana alerting vs Prometheus + Alertmanager?**
Prometheus rules are YAML in Git, GitOps'd, `promtool`-testable, Kubernetes-native via CRDs, and integrate with the whole CNCF ecosystem — that's the right authority for infra and service alerting. Grafana unified alerting wins for **cross-datasource** alerts (CloudWatch billing, MySQL business tables, Loki log patterns) and for small teams who want a UI. The failure mode is running both for the same signals: two sources of truth, double pages, unclear ownership. Pick one authority per domain and document it.

---

## F · Kubernetes

**48. Where do Kubernetes metrics come from?**
Four sources. **kube-state-metrics** reports the *state of API objects* (`kube_*`: replicas available, pod phase, node conditions, PVC status). **cAdvisor** in the kubelet reports *actual container resource usage* (`container_*`). **kubelet's own `/metrics`** reports kubelet health and runtime operations. **node_exporter** as a DaemonSet reports the host (`node_*`). Plus your apps' own metrics. People confuse KSM and cAdvisor: KSM is what Kubernetes *thinks*, cAdvisor is what the containers *did*.

**49. What does the Prometheus Operator do?**
It reconciles CRDs into running components: `Prometheus` and `Alertmanager` become StatefulSets (and it *generates* their config), `ServiceMonitor`/`PodMonitor`/`Probe`/`ScrapeConfig` define what to scrape, `PrometheusRule` defines recording and alerting rules, `AlertmanagerConfig` adds namespaced routing, `PrometheusAgent` runs agent mode. Benefit: declarative, GitOps-friendly, self-healing, team self-service. Cost: an extra abstraction layer to debug — you often need to inspect the generated `prometheus.yml` inside the secret.

**50. ServiceMonitor vs PodMonitor vs Probe?**
ServiceMonitor scrapes a **Service's endpoints** (match the Service's labels; use the port *name*). PodMonitor scrapes **pods directly** — right for StatefulSets per-pod, DaemonSets, or anything without a Service. Probe runs **blackbox** probes against static targets or Ingresses via a prober URL. ScrapeConfig is the escape hatch for anything those can't express.

**51. Why isn't my ServiceMonitor being picked up?**
Four usual causes, in order: the chart's `serviceMonitorSelectorNilUsesHelmValues` is left `true`, so your monitor needs the chart's `release` label; the **port name** doesn't match the Service's port name (it's a name, not a number); the `namespaceSelector` doesn't include the app's namespace; or the `Prometheus` CR's `serviceMonitorNamespaceSelector` excludes it. Then check RBAC and the generated config in the secret.

**52. What RBAC does Prometheus need?**
Cluster-wide `get/list/watch` on nodes, `nodes/metrics`, `nodes/proxy`, services, endpoints, pods, plus `networking.k8s.io/ingresses` and `discovery.k8s.io/endpointslices`, and `get` on the non-resource URLs `/metrics` and `/metrics/cadvisor`. Missing RBAC shows up as red targets with `403 Forbidden` or as empty discovery results.

**53. Why is Kubernetes monitoring a cardinality problem?**
Every pod, container, namespace and label combination is a dimension, and pods are **ephemeral**, so you get churn as well as volume: series created and destroyed continuously, which costs index writes and head-block memory even though the steady-state count looks fine. cAdvisor alone can produce thousands of series per pod. Controls: drop unused cAdvisor/kubelet metric families, `labeldrop` `id`/`uid`/`image_id`/`device`, drop the `POD` pause container, restrict KSM with allow/denylists, reduce scrape intervals, shorten raw retention with downsampling, and shard by namespace or team.

**54. How do you monitor 20 clusters?**
Per-cluster Prometheus (2 replicas each, `cluster` in `external_labels`) remote-writing to a central store — Mimir, Thanos Receive or VictoriaMetrics — with deduplication on the replica label at query time. Long retention and downsampling in the central store; a global Query/Grafana for cross-cluster views; Thanos Ruler or Mimir Ruler for alerts that need the global view (cluster-wide SLOs). The prerequisite is a **canonical label set** enforced identically in every cluster (`cluster`, `region`, `env`, `team`, `namespace`, `service`) — inconsistent labels are why global views fail. Federation is the lightweight alternative when you only need aggregates and have few clusters.

---

## G · SLOs

**55. SLI vs SLO vs SLA.**
SLI is a *measured ratio* (good events ÷ valid events). SLO is a *target* on that ratio over a window, agreed internally. SLA is a *contract* with a customer and consequences — always looser than the SLO, so you have internal headroom before a contractual breach. Error budget is `1 − SLO`.

**56. How do you choose an SLI?**
It must be an event-count ratio measured as close to the user as possible (LB/ingress beats app, because an app-level SLI reads 100% while the LB returns 502s during an outage). Weight by traffic, not time. Include only what you control — exclude 4xx. One or two SLIs per service: availability and latency cover most of what users care about. And define SLOs per **user journey** rather than per microservice, because users experience journeys.

**57. Why isn't 100% the right SLO?**
It's unachievable, it gives zero budget for experimentation and deploys, and it makes every budget-driven decision collapse to "freeze". Also your SLO can't be better than your worst dependency's. Start loose (99.5%), measure for a quarter, tighten to 99.9% if you're consistently better.

**58. How much downtime does 99.9% allow?**
40.3 minutes over a rolling 28 days; 43.2 minutes over a 30-day month; 1.44 minutes per day; 3.6 seconds per hour. As bad events: 1,000 per million requests. Five nines is 24 seconds a month — that's multi-region active-active territory.

**59. What is a burn rate?**
Observed error ratio ÷ SLO-allowed error ratio. A burn rate of 1 means you'll consume exactly the budget over the SLO window. 14.4 means you'll burn **2% of a 30-day budget in one hour**. It converts "how bad is this?" into "how fast are we spending our allowance?", which is what makes alert thresholds meaningful.

**60. Why multi-window, multi-burn-rate alerting?**
Because naive SLO alerts fail both ways: `error_rate > 0.1% for 5m` pages on blips that don't threaten the budget, and `budget_remaining < 0` only fires *after* you've blown the month. So you alert on the **rate of budget consumption** over four tiers (14.4×/1h+5m page, 6×/6h+30m page, 3×/1d+2h ticket, 1×/3d+6h ticket), and each tier requires **two windows simultaneously**: the long window proves the burn is sustained, the short window proves it's still happening — so a 60-second burst doesn't page you for an hour after it resolved.

**61. What's in an error-budget policy?**
The SLO statement and measurement source (authoritative recording rules, not a vendor dashboard); the budget in minutes and events; a table of budget-remaining thresholds mapped to actions (normal velocity → prioritise reliability → no risky changes → **release freeze** → escalate); the exceptions (security patches, incident fixes, changes that improve the SLI); how planned maintenance is excluded; the owner and review cadence. Without the policy, the SLO is a number nobody acts on.

**62. Your SLO alert fires but users report no problem. Causes?**
The SLI is measured at the wrong layer or with the wrong denominator (e.g. including health-check or synthetic traffic, or including 4xx); zero traffic making the ratio 1/1 = 100% error (needs a traffic guard and `clamp_min`); a single noisy tenant dominating a global ratio (measure per-tenant); a recent change in instrumentation or metric naming silently altering the ratio; or the burn-rate window catching an old incident still in the 1h window while the 5m window has recovered — which the `and` should prevent, so check the rule.

---

## H · Scaling & operations

**63. When does a single Prometheus stop being enough?**
Around 1–2 M active series on one node, or sustained ingest above ~1 M samples/sec, or when query p99 exceeds 5–10 s, or when you need more than ~15–30 days of raw retention, or when you need a global view across clusters, or when HA is a requirement. First symptoms are RAM growth and OOMKills, then slow queries.

**64. Thanos vs Mimir vs VictoriaMetrics.**
**Thanos**: object-storage-backed, sidecar (per existing Prometheus) or Receive (push), global Query with replica dedup, Compactor for downsampling and retention, Ruler for global rules. Best when you already run Prometheis and want long retention plus a global view without changing your ingest path. **Mimir**: built for multi-tenant, very large scale, with a query-frontend that splits and caches queries — the best query performance and the most operational components. **VictoriaMetrics**: simplest to run and by far the best compression (often 2–4× fewer bytes per sample), MetricsQL is a PromQL superset with a few behavioural differences. Managed options (AMP/GMP/Grafana Cloud/Datadog) trade ops for per-sample cost.

**65. What is downsampling and what do you lose?**
The compactor stores 5-minute and 1-hour aggregates of old blocks alongside (or instead of) raw data. You gain enormous query speed and storage savings for long ranges; you lose the ability to see sub-5-minute detail in old data — so a 90-day-old incident can't be debugged at raw resolution. The query layer picks resolution automatically (`max_source_resolution=auto`). Keep raw data as long as your incident-review window needs it (typically 15–30 days).

**66. How do you know remote_write is losing data?**
`rate(prometheus_remote_storage_samples_dropped_total[5m]) > 0` means samples are being **dropped** — that's data loss, page on it. Also watch `prometheus_remote_storage_samples_pending` (queue depth should hover near zero), `prometheus_remote_storage_shards` (pegged at `max_shards` means it can't keep up), `..._samples_failed_total`, `..._retries_total`, and the lag `highest_timestamp_in_seconds − queue_highest_sent_timestamp_seconds`. Fix by raising `max_shards`/`capacity`, adding `write_relabel_configs` drops, or fixing the backend.

**67. How do you reduce monitoring cost?**
Cardinality first (it's ~everything): drop unused metrics and labels, normalise unbounded values, restrict exporters, lengthen scrape intervals on low-value jobs. Then retention tiers (raw 15d → 5m downsampled 1y). Then logs and traces, which usually cost more than metrics: tail-sample traces (keep 100% of errors and slow traces, 1–5% of the rest), turn off `debug` in prod, drop noisy lines at the collector, aggregate log patterns into metrics. Finally, query cost: recording rules and a caching query frontend.

**68. A dashboard is slow. What do you check?**
`prometheus_engine_query_duration_seconds`, the query log (`--query.log-file`) to find the actual expensive query, whether the panel uses `$__rate_interval` or a silly 15 s step over 30 days, whether `Min step` is set, whether the query has a metric-name matcher or is scanning everything, whether it's a subquery over a wide series set, and whether the panel should be backed by a recording rule instead. Then check server-side limits and the Grafana refresh interval — 5 s refresh × 40 panels × 10 viewers is a real load.

---

## I · Incident response & scenario questions

**69. Tell me about an incident you handled.**
Structure it: **detection** (which alert, how fast — MTTD), **triage** (what the dashboard showed, what you ruled out), **root cause**, **mitigation** vs **fix**, **resolution** (MTTR), **postmortem** (blameless, action items with owners and due dates), and **what you changed in the monitoring** as a result. The last part is what distinguishes a senior answer — every incident should produce a monitoring improvement.

**70. Users report the site is slow; your dashboards look fine. Now what?**
First, believe the users — a user-reported problem that monitoring missed is a monitoring bug, so start by finding the gap. Check: are you measuring at the right layer (edge vs app)? Is it a **tail** problem hidden by averages (look at p99/p999 and the heatmap, not the mean)? Is it **one segment** — a region, an ISP, a tenant, a client version, a specific endpoint? Check client-side/RUM data and synthetic probes from the affected region. Check third-party dependencies your server-side metrics don't cover (CDN, DNS, payment provider). Then check for a silent failure: is the scrape even working, did a metric get renamed, is the dashboard variable filtering out the affected service?

**71. You inherit a system with 500 alerts and nobody trusts them. First 30 days?**
Week 1: measure. Export every rule, count fires per alert over 90 days, count how many led to action. Identify the top 20 noisiest and any alert that has never fired (probably broken — test it). Week 2: triage. Delete anything with no action in 90 days; demote cause alerts to tickets; ensure every remaining page has `severity`, `team`, a runbook and a dashboard link. Week 3: add the missing foundations — `up`/TargetDown, Watchdog dead-man's switch, Alertmanager grouping and inhibition, one symptom alert per critical service. Week 4: introduce SLOs for the top 2–3 user journeys with burn-rate alerts, and start a weekly alert-review ritual with a page budget (< 5 per shift). Track MTTD/MTTA/MTTR and alert precision as the success metrics.

**72. Design monitoring for a new microservice. Walk me through it.**
Instrumentation: RED metrics with a latency histogram whose buckets straddle the SLO threshold, dependency metrics (DB, cache, downstream), saturation metrics (in-flight, queue depth and **queue age**, pool utilisation), a build/version info metric, and a business metric for the SLO. Export via `/metrics`, scraped by a ServiceMonitor. Dashboards: three tiers — fleet overview, service RED dashboard with symptoms on top and causes below, and a debug view; variables for namespace/service; deploy annotations; data links to logs and traces. Alerts: `up == 0`, an `absent()` companion on the SLI, multi-window burn rates for availability and latency, plus leading indicators with time-boxed actions (disk, cert, pool exhaustion). Everything as code in Git with `promtool test rules` in CI. On-call: route by `team` label, page vs ticket, runbook per page-level alert, silence process for maintenance. Then agree the SLO and the error-budget policy with the team.

**73. How would you monitor a nightly batch job?**
Three separate questions, three metrics: did it **start** (a heartbeat timestamp, or Pushgateway `push_time_seconds`, or an external watchdog ping — alert on staleness relative to the schedule); did it **succeed** (exit code, records processed vs expected, and a "processed 0 rows" alert because success-with-nothing-done is a classic silent failure); was it **healthy** (duration histogram against a deadline, retry count, and lag since the last successful completion). Prefer a long-running exporter or OTLP push over Pushgateway where possible, because pushed metrics persist forever and a dead job then looks healthy. Add a synthetic check that reads the job's output table to confirm the data landed and is fresh.

**74. Prometheus is OOMKilled. What do you do?**
Immediate: raise the memory limit to stop the bleeding, and check whether it correlates with a deploy (someone shipped an unbounded label). Diagnose: `promtool tsdb analyze`, `prometheus_tsdb_head_series`, `rate(prometheus_tsdb_head_series_created_total[5m])` for churn, `topk(10, count by (__name__)({__name__=~".+"}))`, and the Status → TSDB Status page for top label pairs. Also check query memory: `--query.max-samples` and the query log for an expensive dashboard. Fix: `metric_relabel_configs` drops and `labeldrop`, normalise paths, restrict exporters, increase scrape intervals, shard, then consider a remote-write backend. Prevent: cardinality budgets per team, CI checks rejecting unbounded labels, and a monthly top-10 cardinality report.

**75. How do you monitor the monitoring?**
Prometheus self-metrics: `up`, `prometheus_config_last_reload_successful`, `prometheus_rule_evaluation_failures_total`, `prometheus_rule_group_last_duration_seconds` vs its interval, `prometheus_notifications_queue_length`, `prometheus_notifications_alerts_dropped_total`, `prometheus_tsdb_wal_corruptions_total`, `prometheus_tsdb_head_series`, `scrape_duration_seconds`. Alertmanager: `alertmanager_cluster_members`, `rate(alertmanager_notifications_failed_total[5m])`, `alertmanager_notification_latency_seconds`, active silences count. External probe on the Prometheus and Grafana endpoints. And the **Watchdog** routed to an external dead-man's switch so the whole chain is continuously validated from outside.

---

## J · Rapid-fire (one-line answers)

| Question | Answer |
|---|---|
| Default scrape interval | 1m global; `evaluation_interval` 1m |
| Default Prometheus retention | 15 days (time-based), size unlimited |
| Default Alertmanager `group_wait` / `group_interval` / `repeat_interval` | 30s / 5m / 4h |
| Default `resolve_timeout` | 5m |
| Prometheus port / Alertmanager / node_exporter / blackbox / Pushgateway / KSM / Grafana | 9090 / 9093 / 9100 / 9115 / 9091 / 8080 / 3000 |
| TSDB block duration | 2 hours |
| Staleness marking | ~5 minutes (immediately on target loss) |
| `up` semantics | 1 = last scrape succeeded, 0 = failed; synthetic, one per target |
| Recording rule naming convention | `level:metric:operations` |
| Alert identity | Hash of the label set (fingerprint) |
| Best quantile function | `histogram_quantile` over summed `_bucket` rates |
| Range window minimum | ≥ 2× scrape interval (use 4×) |
| Grafana rate variable | `$__rate_interval` |
| Two flags that make Prometheus an edge collector | `--agent.mode` + `remote_write` |
| Flag to accept OTLP | `--web.enable-otlp-receiver` |
| Flag for exemplars | `--enable-feature=exemplar-storage` |
| Four CI validation commands | `promtool check config`, `promtool check rules`, `promtool test rules`, `amtool check-config` |
| Burn rate for "2% of budget in 1h" | 14.4× (windows 1h and 5m) |
| Budget for 99.9% over 28 days | 40.3 minutes |
| What pages a human | Urgent + actionable + rare |

---

## K · Questions to ask them

Asking good questions is scored too.

1. How do you decide what pages a human versus becoming a ticket — is there an SLO and error-budget policy?
2. What's your current pages-per-shift number, and do you review noisy alerts on a schedule?
3. Who owns the runbooks, and is a runbook required before an alert can page?
4. How is monitoring deployed — GitOps with `promtool` tests in CI, or hand-edited configs?
5. What's your long-term storage architecture, and what's your cardinality governance?
6. How do you measure MTTD/MTTA/MTTR, and what happened to them after the last big incident?
7. Where does monitoring sit organisationally — a platform team, or embedded in product teams?
8. What broke most recently, and how did you find out — did monitoring catch it first?

---

## L · A mock question to practise out loud

> "Our checkout service has a 99.9% availability SLO. Last night it had a 12-minute outage at 3 a.m. and nobody was paged until a customer emailed at 8. Design the fix."

Practise a 4-minute answer covering: which alert *should* have fired (fast burn — 12 min at ~100% errors is a burn rate in the hundreds, so 14.4×/1h+5m should trigger within ~7 minutes); therefore where the pipeline broke (walk the 12-step checklist: rule expression? `for:` too long? metric absent because the service was fully down so nothing reported? — **that last one is the likely answer**: if the outage means no scrapes succeed, your error-ratio SLI has no data, so you need `up`-based and `absent()`-based alerts plus an **external synthetic probe** that doesn't depend on the service reporting); then the notification side (Alertmanager reachable? notifier failing? muted by a time interval? on-call rotation configured? escalation policy?); then the process fixes (Watchdog, external probe, alert-precision review, "every user-reported outage is a monitoring bug" policy, postmortem with action items).

That question is testing whether you know that **a fully-down service stops reporting the very metrics you alert on** — which is why blackbox probes and `up`/`absent()` alerts exist.

---

## Revision schedule

- **Day 1–2:** sections A–C aloud, no notes.
- **Day 3–4:** sections D–F. Write out the 12-step checklist and the four burn-rate tiers from memory.
- **Day 5:** G–I, plus the mock question in L.
- **Day 6:** J rapid-fire, timed. Then re-run the labs in `16-Labs` — nothing consolidates like doing.
- **Before the interview:** only section J and the 12-step checklist.

→ Back to [`README`](../README.md) · Reference: [`14-Cheatsheets`](../14-Cheatsheets/README.md) · Practice: [`16-Labs`](../16-Labs/README.md)
