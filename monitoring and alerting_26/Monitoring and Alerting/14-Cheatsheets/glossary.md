# Cheatsheet · Glossary

Alphabetical. One line each — enough to recognise the term and know where to read more.

| Term | Meaning |
|---|---|
| **Ack (acknowledge)** | On-call confirms receipt of a page; stops escalation. |
| **Active series** | Series with a sample in the last ~5 minutes; drives Prometheus memory. |
| **Active time interval** | Alertmanager window during which a route **only** delivers. |
| **Alert** | A rule expression evaluating non-empty, with state INACTIVE/PENDING/FIRING. |
| **Alert fatigue** | On-call ignoring alerts because most are not actionable. |
| **Alertmanager** | Component that groups, routes, inhibits, silences and delivers notifications. |
| **AlertmanagerConfig** | Prometheus Operator CRD for namespaced routing/receivers. |
| **Amtool** | CLI for Alertmanager: query alerts, manage silences, test routing, validate config. |
| **Annotation** | Descriptive text on an alert rule; does **not** affect alert identity. |
| **Apdex** | Satisfaction score: (satisfied + tolerating/2) / total. |
| **Blackbox monitoring** | Observing a system from outside (synthetic probes) — tells you *that* it's broken. |
| **Blackbox exporter** | Prometheus prober for HTTP/TCP/ICMP/DNS/gRPC endpoints. |
| **Blameless postmortem** | Incident review analysing systems and decisions, not people. |
| **Bucket (`le`)** | Histogram upper bound; `le="0.3"` counts samples ≤ 0.3. |
| **Burn rate** | Observed error ratio ÷ SLO-allowed error ratio. |
| **cAdvisor** | Container metrics collector built into the kubelet. |
| **Cardinality** | Number of distinct time series; the main Prometheus cost/risk driver. |
| **Churn** | Rate at which new series are created (ephemeral labels); as damaging as count. |
| **Collector (OTel)** | Vendor-neutral telemetry pipeline: receive → process → export. |
| **Compactor** | Thanos/Mimir component doing downsampling and retention enforcement. |
| **Counter** | Monotonic metric; query with `rate()`/`increase()`, never raw. |
| **Dead-man's switch** | Always-firing alert routed to an external service that pages when it **stops**. |
| **Delta** | Difference of a gauge over a window (`delta()`). |
| **Downsampling** | Storing lower-resolution aggregates of old data (raw → 5m → 1h). |
| **EndsAt / StartsAt** | Alert timestamps in the Alertmanager payload. |
| **Enum gauge** | One series per possible state, value 1 for the current state. |
| **Error budget** | `1 − SLO`; the unreliability you are allowed to spend. |
| **Error budget policy** | The agreed actions as the budget depletes (up to a release freeze). |
| **Evaluation interval** | How often Prometheus evaluates rule groups. |
| **Exemplar** | A `trace_id` attached to a metric sample; enables metric → trace drill-down. |
| **Exporter** | A process that exposes some system's metrics in Prometheus format. |
| **External labels** | Labels added to all outbound data (federation, remote write, HA identity). |
| **Federation** | One Prometheus scraping aggregates/recording rules from others. |
| **Fingerprint** | Hash of an alert's label set; its identity for grouping/dedup. |
| **Flapping** | An alert oscillating firing↔resolved. |
| **`for:`** | Duration the expression must stay true before an alert fires. |
| **Four Golden Signals** | Latency, traffic, errors, saturation. |
| **Gauge** | Metric that goes up and down; query raw or with `delta()`/`*_over_time()`. |
| **Golden dashboards** | The small set of dashboards used during incidents. |
| **Grafana** | Visualisation + unified alerting; no storage of its own. |
| **Group / group_by** | Alertmanager's aggregation of alerts into one notification. |
| **group_interval / group_wait / repeat_interval** | The three Alertmanager timing knobs. |
| **Head block** | In-memory TSDB chunk holding the last ~2–3 h of samples. |
| **Histogram** | Client-side buckets → `_bucket`, `_sum`, `_count`; aggregatable quantiles. |
| **histogram_quantile()** | PromQL function estimating a quantile from buckets (interpolated). |
| **`honor_labels`** | Keep the target's own labels instead of overwriting them. |
| **Inhibition rule** | Alertmanager rule suppressing target alerts when a source alert fires. |
| **Info metric** | Constant gauge = 1 carrying metadata labels; joined via `group_left`. |
| **Instant vector** | Set of series each with one current sample. |
| **Instrumentation** | Code that emits telemetry. |
| **Irate** | Instantaneous rate from the last two samples; graphs only, never alerts. |
| **Job** | Prometheus scrape_config name; becomes the `job` label. |
| **keep_firing_for** | Keep an alert firing after the expression goes false (anti-flap). |
| **kube-prometheus-stack** | Helm chart: Operator + Prometheus + Alertmanager + Grafana + exporters + rules. |
| **kube-state-metrics (KSM)** | Exporter of Kubernetes object *state* (`kube_*`). |
| **Label** | Key/value dimension of a series; also the grouping and routing axis. |
| **LogQL** | Loki's query language. |
| **Loki** | Log store indexing labels only; logs stay compressed in object storage. |
| **Matcher** | `=`, `!=`, `=~`, `!~` filter on labels (PromQL and Alertmanager routes). |
| **Metric relabeling** | Post-scrape per-sample label filtering/rewriting; the cardinality weapon. |
| **Mimir** | Grafana's horizontally scalable, multi-tenant Prometheus-compatible TSDB. |
| **MTTA / MTTD / MTTR** | Time to acknowledge / detect / resolve. |
| **Mute time interval** | Alertmanager window during which a route does **not** deliver. |
| **Native histogram** | Exponential-bucket histogram; high resolution, low cardinality (experimental). |
| **Notification** | What Alertmanager actually sends. **Alert ≠ notification.** |
| **Observability** | Ability to understand novel failures from a system's outputs. |
| **Offset** | PromQL modifier shifting a query into the past (`offset 1d`). |
| **On-call** | The rotation responsible for acknowledging and acting on pages. |
| **OpenMetrics** | Exposition format standard adding `# UNIT`, `_created`, exemplars. |
| **OpenTelemetry (OTel)** | Vendor-neutral instrumentation standard + SDKs + Collector; OTLP is its protocol. |
| **OTLP receiver** | Prometheus 3 endpoint `/api/v1/otlp/v1/metrics` (`--web.enable-otlp-receiver`). |
| **Page** | Urgent notification requiring immediate human action. |
| **Percentile** | Value below which X% of observations fall (p99). |
| **PodMonitor** | Operator CRD scraping pods directly. |
| **predict_linear()** | PromQL least-squares forecast — "disk full in N hours". |
| **Probe (CRD)** | Operator resource for blackbox probes. |
| **probe_success** | Blackbox metric: 1 if the probe passed. |
| **Prometheus Operator** | Controller turning CRDs into running Prometheus/Alertmanager instances. |
| **PrometheusRule** | Operator CRD holding recording + alerting rule groups. |
| **PromQL** | Prometheus query language. |
| **promtool** | CLI: validate config/rules, unit-test rules, query, analyse TSDB. |
| **Pushgateway** | Accepts pushed metrics from short-lived jobs; metrics persist until deleted. |
| **Pull model** | Collector scrapes targets; absence of data is a first-class signal. |
| **Query frontend** | Mimir/Thanos component that splits, caches and parallelises queries. |
| **Range vector** | Set of series each with a window of samples; not directly graphable. |
| **Rate** | Per-second average of a counter over a window; handles resets. |
| **Receiver** | Alertmanager named bundle of notifier configs. |
| **Recording rule** | Precomputed expression stored as a new series (`level:metric:ops`). |
| **RED** | Rate, Errors, Duration — per-service method. |
| **Relabeling** | Pre-scrape target filtering/rewriting. |
| **Remote write** | Streaming samples to a central TSDB. **Remote Write 2.0** adds metadata/exemplars/native histograms. |
| **resolve_timeout** | Global Alertmanager timer: no update ⇒ alert resolved. |
| **Retention** | How long data is kept (time and/or size based). |
| **Runbook** | Ordered, command-level steps for responding to a specific alert. |
| **Sampling (traces)** | Choosing which traces to keep: head-based or tail-based. |
| **Scrape interval / timeout** | How often targets are scraped; timeout must be ≤ interval. |
| **Service discovery (SD)** | Dynamic target finding (`__meta_*` labels → relabeling). |
| **ServiceMonitor** | Operator CRD scraping a Service's endpoints. |
| **Severity** | Label defining the required human response (page/ticket/info). |
| **Sharding** | Splitting targets across N Prometheus instances (`hashmod`). |
| **Silence** | Time-boxed matcher set suppressing notifications for matching alerts. |
| **SLA / SLI / SLO** | Agreement / Indicator / Objective. |
| **Span** | One unit of work in a trace. |
| **Staleness** | Prometheus marking a series gone (~5 min, or immediately on target loss). |
| **Subquery** | `expr[range:step]` — an expression evaluated over time. Expensive. |
| **Summary** | Client-computed quantiles; **not** aggregatable across instances. |
| **Symptom alert** | Alert on user-visible impact (page). Opposite: **cause alert** (dashboard/ticket). |
| **Target** | A scrape endpoint after service discovery + relabeling. |
| **Tempo** | Grafana's object-storage-backed trace backend (TraceQL). |
| **Thanos** | Object-storage-backed global view, downsampling and HA for Prometheus. |
| **Three pillars** | Metrics, logs, traces. |
| **Time interval** | Alertmanager named window used by `mute_time_intervals`/`active_time_intervals`. |
| **Trace** | A tree of spans sharing a `trace_id`. |
| **TraceQL** | Tempo's trace query language. |
| **TSDB** | Time-series database (Prometheus's storage engine). |
| **`up`** | Synthetic per-target metric: 1 = last scrape succeeded, 0 = failed. |
| **USE** | Utilisation, Saturation, Errors — per-resource method. |
| **Vector matching** | `on()` / `ignoring()` / `group_left` / `group_right` in binary ops. |
| **VictoriaMetrics** | Prometheus-compatible TSDB with very high compression (MetricsQL). |
| **WAL** | Write-ahead log; replayed on restart, deleted only after blocks are written. |
| **Watchdog** | Always-firing dead-man's-switch alert. |
| **Whitebox monitoring** | Observing a system from inside using its own telemetry. |
| **Whitebox vs blackbox** | Internal instrumentation vs external probing; you need both. |
| **`$__rate_interval`** | Grafana variable = `max(4 × scrape interval, $__interval)`; use in every `rate()`. |
