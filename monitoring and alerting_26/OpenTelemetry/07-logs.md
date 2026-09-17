# 07 · Logs

The least mature of the three original signals, and the one people misunderstand most. **OTel does not replace your logging framework.** It bridges it — and understanding that distinction explains every design decision here.

---

## 7.1 What OTel logging is and isn't

| | |
|---|---|
| **Is** | A **log record data model**, an **OTLP transport**, and a **bridge** that connects your existing logger's output to that model — automatically attaching `trace_id`/`span_id` so logs correlate with traces |
| **Is** | A **file/stdout/journald/syslog collection pipeline** in the Collector (`file_log`, `tcp_log`, `udp_log`, `syslog`, `journald`, `named_pipe`, `windows_event_log`) with parsing operators |
| **Isn't** | A logging API you should adopt instead of `slf4j`/`logging`/`logback`/`zap`/`winston` |
| **Isn't** | A log store, search engine, or retention policy. That's Loki, Elasticsearch, ClickHouse, CloudWatch |

★ **The design decision, stated plainly:** the OTel Logs SIG deliberately chose **not** to invent a new logging API. Billions of lines of code log through existing frameworks, those frameworks are deeply integrated with application structure, and rewriting them was never going to happen. So OTel provides:
1. A **standard data model** (so a Java log and a Go log mean the same thing downstream).
2. **Bridges/appender/handlers** that route existing logger output into OTel.
3. **Automatic context injection** — the thing that actually makes it worth doing.

**The single biggest value of OTel logs is the correlation**, not the format.

---

## 7.2 The Logs Bridge model

```
  your code: logger.error("payment failed", order_id=...)
        │
        ▼
  ┌─ Your logging framework ─────────────────────────┐
  │  logback / slf4j / java.util.logging / log4j2    │
  │  Python logging / logging.handlers               │
  │  zap / slog / logrus                             │
  │  winston / pino / bunyan                         │
  │  Serilog / NLog / ILogger                        │
  └──────────────────┬───────────────────────────────┘
                     │  Bridge / Appender / Handler
                     │  (OTel-provided, framework-specific)
                     ▼
  ┌─ OTel Logs SDK ──────────────────────────────────┐
  │  LoggerProvider → LogRecordProcessor             │
  │    BatchLogRecordProcessor (default)             │
  │  ★ INJECTS trace_id + span_id from the current   │
  │    context automatically                         │
  │  Maps severity → SeverityNumber                  │
  └──────────────────┬───────────────────────────────┘
                     │ OTLP exporter
                     ▼
              Collector → Loki / ES / ClickHouse / vendor
```

**Two bridge architectures exist, and choosing between them matters:**

| | **SDK bridge (in-process)** | **Agent/daemon bridge (out-of-process)** |
|---|---|---|
| How | The framework's appender/handler hands records to the OTel Logs SDK in your process | The framework writes to a file/stdout; the Collector's `file_log` receiver tails it |
| `trace_id` injection | **Automatic and exact** — the SDK reads the current context | Must be **in the log line** (structured logging with a `trace_id` field) and parsed out |
| Overhead | In-process CPU/memory; shares your app's fate | Separate process; your app just writes a file |
| Failure mode | If the SDK blocks or the queue fills, **your application is affected** | If the agent dies, logs queue on disk — ★ **much more resilient** |
| Backpressure | Can stall your app | Bounded by disk |
| Deployment | Requires app changes + SDK config | **Zero app changes** if you already log structured JSON |
| Sampling/filtering | At the SDK | At the Collector |

★ **The operational recommendation: for most production systems, prefer the file/agent path** — log structured JSON to stdout or a file, and let the Collector (as a DaemonSet) tail it. Reasons:
1. **Logs must not take down your application.** An in-process exporter with a full queue and a slow backend applies backpressure to your request path. A file on disk does not.
2. **Log volume is 10–100× trace volume.** The overhead argument matters more here.
3. **It works for languages whose logs SDK is immature** — and for third-party components you can't instrument at all.
4. **Crash logs survive.** If the process segfaults, the file has the last lines; an in-process buffer does not. ★ This is the killer argument: **the logs you most want are the ones written immediately before a crash**, and the in-process path is exactly the one that loses them.

**Use the SDK bridge when:** you need guaranteed-exact trace correlation with no logging-format changes, your framework has excellent OTel support (Java's appender is the best), and your log volume is modest.

---

## 7.3 Per-language log integration

### Java — the most mature
```xml
<!-- logback: add the OTel appender -->
<dependency>
  <groupId>io.opentelemetry.instrumentation</groupId>
  <artifactId>opentelemetry-logback-appender-1.0</artifactId>
</dependency>
```
```xml
<appender name="OTEL" class="io.opentelemetry.instrumentation.logback.appender.v1_0.OpenTelemetryAppender">
  <captureExperimentalAttributes>true</captureExperimentalAttributes>
  <captureCodeAttributes>true</captureCodeAttributes>       <!-- file, method, line -->
  <captureMarkerAttribute>true</captureMarkerAttribute>
</appender>
<root level="INFO">
  <appender-ref ref="OTEL"/>
</root>
```
★ **The Java agent (`opentelemetry-javaagent`, 2.31.x) does all of this automatically** for Logback, Log4j2, `java.util.logging` and JBoss LogManager — no dependency, no XML. That's the recommended path. It also injects MDC as log attributes.

**MDC → attributes:** anything in the SLF4J MDC becomes a log record attribute. That's how you get `tenant.id`, `request.id` etc. onto logs without changing every call site. ★ **Which also means MDC cardinality becomes log attribute cardinality** — don't put unbounded values in MDC if you're indexing attributes.

### Python
```bash
pip install opentelemetry-sdk opentelemetry-exporter-otlp
```
```python
import logging
from opentelemetry._logs import set_logger_provider
from opentelemetry.sdk._logs import LoggerProvider, LoggingHandler
from opentelemetry.sdk._logs.export import BatchLogRecordProcessor
from opentelemetry.exporter.otlp.proto.grpc._log_exporter import OTLPLogExporter

provider = LoggerProvider()
provider.add_log_record_processor(BatchLogRecordProcessor(OTLPLogExporter()))
set_logger_provider(provider)

# ★ Attach OTel's handler to the ROOT logger — existing logging calls flow through
handler = LoggingHandler(level=logging.NOTSET, logger_provider=provider)
logging.getLogger().addHandler(handler)
```
Or with zero-code auto-instrumentation:
```bash
export OTEL_PYTHON_LOGGING_AUTO_INSTRUMENTATION_ENABLED=true
opentelemetry-instrument python app.py
```
★ Note `OTEL_PYTHON_LOGGING_AUTO_INSTRUMENTATION_ENABLED` is a **language-specific** variable (`OTEL_{LANGUAGE}_{FEATURE}` convention) and is **bypassed when `OTEL_CONFIG_FILE` is set** — a real migration gotcha.

**The `logging` module's `%(otelTraceID)s` format codes** let you inject trace context into text logs for the file-based path:
```python
logging.basicConfig(format="%(asctime)s %(levelname)s [%(otelServiceName)s] [%(otelTraceID)s.%(otelSpanID)s] %(message)s")
```

### Go — ★ Logs API and SDK at **release candidate**, not yet stable
As of **opentelemetry-go v1.47.0-rc.1 (August 2026)**, the Logs API and SDK were promoted to **release candidate** — the final stage before stable v1 compatibility guarantees. Traces and metrics have been stable for a long time; **logs have not**.

Practical consequence: **in Go, prefer writing structured logs with `log/slog` or `zap` and letting the Collector tail them.** The `file_log` path is language-agnostic, avoids depending on an RC API, and works identically in every service you own.

If you do use the SDK, the modern pattern is a `slog.Handler` bridge:
```go
// slog → OTel logs (or → JSON on stdout for the Collector to tail)
logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
    ReplaceAttr: func(groups []string, a slog.Attr) slog.Attr {
        // inject trace_id/span_id from the current context
        return a
    },
}))
```
★ **Go's `context.Context` requirement makes log-time context injection slightly awkward**: `slog.Info(msg, args...)` has no context, so use `slog.InfoContext(ctx, msg, args...)` — the `*Context` variants exist precisely so a handler can extract the span. **Forgetting `InfoContext` and using `Info` is the #1 Go log-correlation bug.**

### JavaScript / Node
```bash
npm install @opentelemetry/api-logs @opentelemetry/sdk-logs \
            @opentelemetry/exporter-logs-otlp-http \
            @opentelemetry/instrumentation-winston   # or -pino, -bunyan
```
```javascript
const { LoggerProvider, BatchLogRecordProcessor } = require('@opentelemetry/sdk-logs');
const { OTLPLogExporter } = require('@opentelemetry/exporter-logs-otlp-http');
const { logs } = require('@opentelemetry/api-logs');

const provider = new LoggerProvider();
provider.addLogRecordProcessor(new BatchLogRecordProcessor(new OTLPLogExporter()));
logs.setGlobalLoggerProvider(provider);
```
★ **JS SDK 2.x caveats:** the `api-logs` package is on the **unstable** track (`>=0.200.0`), the SDK packages are `>=2.0.0`, and **Node must be `^18.19.0 || >=20.6.0`**. Pino is the most common target and the `instrumentation-pino` package injects trace context into the JSON output — which then works with *either* bridge path.

### .NET
`Serilog`, `NLog` and `Microsoft.Extensions.Logging` all have OTel integration. `ILogger` → OTel is the first-class path via `AddOpenTelemetry().WithLogging()`. Declarative config support is still landing.

---

## 7.4 Collecting logs from files: `file_log` and stanza ★

The Collector's `file_log` receiver (contrib; **renamed from `filelog`**, old name still accepted) is built on **stanza**, a log-parsing framework. This is the workhorse for the agent/daemon path.

```yaml
receivers:
  file_log:
    include: [/var/log/app/*.log]
    exclude: [/var/log/app/*.gz]
    start_at: end                    # ★ 'beginning' backfills; 'end' starts from now
    include_file_name: true
    include_file_path: false
    max_log_size: 1MiB               # split long lines
    # poll_interval: 200ms
    operators:
      # 1. Parse JSON
      - type: json_parser
        parse_from: body
        parse_to: attributes
        timestamp:
          parse_from: attributes.ts
          layout: '%Y-%m-%dT%H:%M:%S.%fZ'

      # 2. Promote trace correlation fields out of attributes
      - type: trace_parser
        trace_id:
          parse_from: attributes.trace_id
        span_id:
          parse_from: attributes.span_id

      # 3. Map severity text to the standard SeverityNumber
      - type: severity_parser
        parse_from: attributes.level
        mapping:
          error: [ERROR, err, SEVERE]
          warn:  [WARN, WARNING]
          info:  [INFO]
          debug: [DEBUG]

      # 4. Move useful fields onto the resource
      - type: move
        from: attributes.service
        to: resource["service.name"]

      # 5. Redact PII BEFORE it leaves the host
      - type: restructure
      - type: regex_parser
        parse_from: body
        regex: '(?P<email>[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+)'
      - type: remove
        field: attributes.email
```

### Stanza operator types you'll actually use
| Operator | Purpose |
|---|---|
| `json_parser` | Parse a JSON body into attributes |
| `regex_parser` | Named capture groups → attributes |
| `timestamp` | Parse and set the record timestamp (**with `layout`** matching your format) |
| `severity_parser` | Map level strings → `SeverityNumber` |
| **`trace_parser`** | ★ **Extract `trace_id`/`span_id` into the record's first-class fields** — this is what makes correlation work on the file path |
| `move` / `copy` / `remove` / `add` | Reshape fields, including into `resource[...]` |
| `restructure` | Reshape nested structures |
| `router` | Branch on conditions (send different formats to different pipelines) |
| `filter` | Drop records by expression |
| `multiline` / `combine` | **Join stack traces into one record** — otherwise each stack frame becomes a separate log line |

★ **`multiline` is the operator people forget, and the result is awful:** a Java stack trace becomes 40 separate log records, unsearchable and 40× the cost. Configure it:
```yaml
receivers:
  file_log:
    include: [/var/log/app/*.log]
    multiline:
      line_start_pattern: '^\d{4}-\d{2}-\d{2}T'   # a new record starts with a timestamp
```

### Relevant feature gates (v0.161.0, from `--help`)
| Gate | Default | Effect |
|---|---|---|
| `filelog.allowFileDeletion` | **on** | Allow deleting rotated files |
| `filelog.allowHeaderMetadataParsing` | **on** | Parse header metadata |
| `filelog.mtimeSortType` | **on** | Sort by mtime when deciding read order |
| `filelog.protobufCheckpointEncoding` | **on** | Checkpoint storage format |
| `filelog.requireExplicitTopN` | **off** | Require explicit top-N |
| `filelog.windows.caseInsensitive` | **off** | Windows case handling |
| `logs.assignKeys` | **on** | Assign keys when parsing |
| `logs.jsonParserArray` | **on** | JSON array parsing |
| `stanza.synchronousLogEmitter` | **off** | Synchronous emission (debugging) |
| `stanza.udp.useStableNetworkAttributes` | **off** | Stable network attribute names |

★ **`start_at: beginning` will backfill your entire log history** into your backend, with **old timestamps** — which may fall outside the retention/index window and vanish, or blow your ingestion budget. Use `beginning` deliberately, in a controlled test, never as a default in production.

---

## 7.5 Trace correlation — the whole point ★

**What you want:** from a trace, see the logs; from a log line, see the trace.

### On the SDK bridge path
Automatic. The bridge reads the current context and sets `trace_id`/`span_id` on the LogRecord. Nothing to configure beyond having the context active (see [`03-context-and-propagation.md`](03-context-and-propagation.md) — **which means your async/threading discipline matters for logs too**).

### On the file path — three things must all work
1. **Your application must write the trace context into the log line.** Structured JSON is easiest:
   ```json
   {"ts":"2026-09-17T10:22:31.482Z","level":"ERROR","service":"checkout","trace_id":"4bf92f3577b34da6a3ce929d0e0e4736","span_id":"00f067aa0ba902b7","msg":"payment failed","order_id":"o-8812"}
   ```
   Every framework has a mechanism: Logback's `%X{trace_id}` / the OTel appender, Python's `%(otelTraceID)s`, `slog` with a `ReplaceAttr` handler and `*Context` methods, Pino's OTel mixin, Serilog's enrichment.
2. **`trace_parser` must lift them into the record's first-class fields** — not leave them as string attributes. Backends join on the first-class fields.
3. **Your backend must be configured to link them.** In Grafana this is a **datasource-level "Trace to Logs" and "Logs to Trace" configuration** with the field mapping. Miss step 3 and everything works but the buttons don't appear — a surprisingly common complaint.

```yaml
# Grafana datasource provisioning: the part people forget
apiVersion: 1
datasources:
  - name: Loki
    type: loki
    access: proxy
    url: http://loki:3100
    jsonData:
      derivedFields:
        - name: TraceID
          matcherRegex: '"trace_id":"(\w+)"'
          url: '$${__value.raw}'
          datasourceUid: tempo        # ★ links the log field to the Tempo datasource
  - name: Tempo
    type: tempo
    access: proxy
    url: http://tempo:3200
    jsonData:
      logsDatasourceUid: loki         # ★ and back again
      tracesToLogs:
        datasourceUid: loki
        filterByTraceID: true
```

### Correlation for **metrics** too
Exemplars are the metrics equivalent ([`06-metrics.md`](06-metrics.md)): a histogram bucket carries a `trace_id`. Together these give you the full triangle — **metric spike → exemplar → trace → log line → root cause** — with clicks instead of timestamp arithmetic. ★ That triangle is the actual deliverable of an OTel deployment; if you have telemetry but can't navigate it, you've built three silos with extra steps.

---

## 7.6 Log volume and cost — the discipline that matters most

**Logs are usually 80–95% of observability spend.** The controls, in order of yield:

| Control | Yield | Where |
|---|---|---|
| **Don't emit it** | Highest | Application code. Review log levels; `DEBUG` in production is almost always a mistake |
| **Filter at the edge** | ★ Very high | Collector DaemonSet, before data leaves the node. Dropping health-check access logs and readiness probes typically cuts **40–70%** with zero information loss |
| **Drop by severity** | High | `filter` processor: drop `severity_number < 9` (below INFO) for high-volume services |
| **Sample logs** | Medium | `probabilistic_sampler` is **Alpha for logs** in v0.161.0. Sample DEBUG, never ERROR |
| **Deduplicate** | Medium | The **`log_dedup` processor** (newer, contrib) collapses repeated identical records with a count — ideal for retry loops and crash-loops emitting the same line thousands of times |
| **Truncate** | Medium | Cap message length; drop `exception.stacktrace` for known-benign types |
| **Redact** | Necessary | `redaction` processor, or stanza `regex_parser` + `remove`. Do this **at the edge**, not at the backend |
| **Tier retention** | High | 7 days hot / 30 days warm / 400 days cold-object-storage. The cheapest log is the one you delete |
| **Compress** | Medium | `exporter.file.nativeCompression` gate; most backends compress natively |

```yaml
processors:
  filter/drop-noise:
    error_mode: ignore
    logs:
      record:
        - 'severity_number < 9 and resource.attributes["service.name"] == "edge-proxy"'
        - 'IsMatch(body, "GET /healthz")'
        - 'attributes["http.route"] == "/readyz"'
  redaction/pii:
    blocked_values:
      - '[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+'    # email
      - '\b\d{3}-\d{2}-\d{4}\b'                              # SSN-shaped
      - '\b(?:\d[ -]*?){13,16}\b'                            # card-shaped
    allowed_keys: []           # ★ empty allowlist = block everything matching, keep nothing
    summary:
      redacted_values: true
      redacted_keys: true
```
★ **Redact in the Collector at the edge, not in the backend.** Once PII reaches the log store it's subject to that store's retention, its access controls, its backups and its cross-region replication. Redacting at the DaemonSet means it never leaves the node — which is a materially different compliance posture, and the one an auditor will accept.

---

## 7.7 Logs vs events vs the `event_name` field

The log record model has an **`event_name`** field, which distinguishes:
- **Logs** — free-form or semi-structured records about what happened. `event_name` empty.
- **Events** — structured, typed occurrences with a known schema. `event_name` set (e.g. `user.signup`, `feature.flag.evaluated`, `k8s.pod.evicted`).

★ **Why this matters:** events with a stable name and schema are **queryable and aggregatable** in a way free-text logs never are. `count(event_name == "user.signup")` is a business metric derived from your log pipeline, with no extra instrumentation. If you have structured domain events, model them as **events** rather than logging them — you get a schema, you get aggregation, and you stop paying to full-text-index what you only ever query by field.

The Collector's **`k8s_events` receiver** (Alpha for logs) and **`k8sobjects` / `k8s_objects` receiver** are examples of this pattern: Kubernetes events become structured OTel log records with meaningful names, which is far more useful than tailing the kubelet's text output.

---

## Red flags

| Doing this | Costs you |
|---|---|
| Replacing your logging framework with the OTel Logs API | Wrong mental model — it's a bridge, not a logger |
| In-process log export for a high-volume service | Backpressure onto your request path; a slow backend slows your app |
| In-process export for crash diagnostics | ★ **The logs written immediately before a crash are exactly the ones a full in-process buffer loses** |
| Not using `*Context` logging methods in Go | No trace correlation. The #1 Go logs bug |
| `slog.Info` instead of `slog.InfoContext` | Same |
| Putting unbounded values in Java's MDC | Log attribute cardinality explosion |
| No `multiline` operator | One stack trace becomes 40 records — unsearchable and 40× the cost |
| `start_at: beginning` in production | Backfills your whole history with old timestamps; may fall outside retention or blow the budget |
| Leaving `trace_id` as a string attribute instead of using `trace_parser` | Backends can't join; the correlation button doesn't work |
| Configuring correlation but not the Grafana datasource links | Everything works and nothing is clickable |
| `DEBUG` logging in production | Usually the single largest line item in the observability bill |
| Redacting at the backend instead of the edge | PII has already entered your store, its backups, and its replication |
| Sampling ERROR logs | You lose exactly the data you need. Sample DEBUG only |
| No dedup for crash-loops and retry storms | The same line 100,000× — use `log_dedup` |
| Depending on Go's Logs SDK for anything critical | ★ **Release candidate as of v1.47.0-rc.1 (Aug 2026), not stable.** Prefer structured logging + `file_log` |
| Free-text logging things you always query by field | Paying for full-text indexing to do an aggregation. Model them as events |

---

## Rapid recall

1. **OTel logs = a data model + OTLP transport + a bridge from your existing logger.** It is not a logging API and not a log store. **The value is correlation, not format.**
2. **Two bridge architectures.** **SDK bridge** (in-process appender): exact automatic `trace_id` injection, but shares your app's fate and can apply backpressure. **File/agent bridge** (Collector `file_log`): zero app changes, resilient, survives crashes, works for any language — but requires `trace_id` in the log line and `trace_parser` to lift it.
3. ★ **Prefer the file path in production.** Logs are 10–100× trace volume, must never take down your app, and **the logs written just before a crash are exactly the ones an in-process buffer loses.**
4. **Per-language maturity:** Java is best (the agent auto-instruments Logback/Log4j2/JUL, MDC → attributes). Python has `LoggingHandler` + `OTEL_PYTHON_LOGGING_AUTO_INSTRUMENTATION_ENABLED` (★ bypassed when `OTEL_CONFIG_FILE` is set). JS `api-logs` is on the **unstable** track and needs **Node ^18.19.0 || >=20.6.0**. **Go's Logs API+SDK is release candidate (v1.47.0-rc.1, Aug 2026), not stable** — use `slog`/`zap` → JSON → `file_log`.
5. **`file_log` + stanza operators:** `json_parser` → `trace_parser` → `severity_parser` → `move` to resource → redaction. ★ **Always configure `multiline`** (line_start_pattern) or a stack trace becomes 40 records.
6. **`severity_number` 1–24 normalises levels across languages.** Alert on the number (≥17 = ERROR), display `severity_text`.
7. **Two timestamps:** `time_unix_nano` (when it happened — what backends index) vs `observed_time_unix_nano` (when seen). ★ Backfilling old files writes old timestamps that can fall outside retention and vanish.
8. **Correlation needs three things:** context in the log line, `trace_parser` into first-class fields, **and the backend configured to link** (Grafana `derivedFields` + `datasourceUid` both directions). Plus **exemplars** for the metric→trace edge — that completes the triangle.
9. **Cost discipline, highest yield first:** don't emit → **filter at the edge** (health checks: 40–70% saving) → drop by severity → **`log_dedup`** for retry/crash storms → truncate → **redact at the edge, not the backend** → tier retention.
10. **Sample DEBUG, never ERROR.** `probabilistic_sampler` is **Alpha for logs** in v0.161.0.
11. **Use `event_name` for structured domain events** — `k8s_events` and `k8s_objects` receivers are the model. A named, schema'd event is aggregatable; free text never is.
12. **Body is `AnyValue`**, not a string — structured JSON can stay structured through the pipeline rather than being flattened and re-parsed at query time.

→ Next: [`08-profiles.md`](08-profiles.md)
