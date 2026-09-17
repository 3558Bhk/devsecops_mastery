# Lab 05 — Logs into Loki, and the Correlation Triangle

**Goal:** get logs into Loki the *supported* way, correlate them with traces from **both** an instrumented and an uninstrumented source, and verify that redaction actually works.

**Time:** 60 minutes. **Prerequisites:** Docker, ~5 GB RAM (six services).

**Read [`../../07-logs.md`](../../07-logs.md) first**, then skim [`../../13-backends.md`](../../13-backends.md) for the Loki-specific parts.

---

## ★★ Start here: there is no `loki` exporter

If you search for "OpenTelemetry Collector Loki", most results still tell you this:

```yaml
exporters:
  loki:
    endpoint: http://loki:3100/loki/api/v1/push
```

**That component does not exist in contrib v0.161.0.** It was removed. Try it:

```
'exporters' unknown type: "loki" for id: "loki" (valid values: [...])
```

★ **`loki` is a RECEIVER only** — it's how the Collector *ingests* Prometheus-format logs, not how it exports them.

**The supported path is `otlphttp` against Loki's native OTLP endpoint** (Loki ≥ 3.0):

```yaml
exporters:
  otlphttp/loki:
    endpoint: http://loki:3100/otlp     # ★ BASE only
```

★ **Do not write the full path.** The exporter appends `/v1/logs` itself, so `http://loki:3100/otlp/v1/logs` becomes `/otlp/v1/logs/v1/logs` and you get a 404 that looks like a Loki bug.

---

## Two log paths, on purpose

| | **OTLP path** | **`file_log` path** |
|---|---|---|
| Source | `checkout` (Python, zero-code instrumented) | `legacy-app` (plain shell, **no SDK**) |
| Where `trace_id` lives | ★ First-class `LogRecord.traceId` field | ★ **Inside the JSON body text** |
| Receiver | `otlp` | `file_log/legacy` |
| How it correlates | Loki's OTLP ingestion maps it automatically | **`transform/correlate-file-log` must promote it** |
| Real-world analogue | Your own services | Third-party binary, legacy monolith, vendor appliance |

**The second path is the interesting one.** You cannot instrument it. You can still correlate it — by normalising it onto the OTel field name in the Collector:

```yaml
transform/correlate-file-log:
  log_statements:
    - context: log
      statements:
        - set(attributes["trace_id"], body["trace_id"]) where IsString(body["trace_id"])
```

★ **That one line is why a single Grafana derived field serves both sources.** Without it you maintain a regex per log format, forever — and the Grafana docs say exactly that:
> *"If your applications use different trace ID field names, you need a separate derived field entry for each format. To simplify this, **standardize on OpenTelemetry structured metadata**."*

---

## Run it

```bash
cd labs/lab-05-logs-and-correlation
docker compose up -d --build
docker compose ps
```

| URL | What |
|---|---|
| **http://localhost:3000** | Grafana → *OpenTelemetry Labs* → **Lab 05 — Logs & Correlation** |
| http://localhost:3100 | Loki |
| http://localhost:3200 | Tempo |
| http://localhost:9090 | Prometheus |
| http://localhost:8000 | Demo app |
| http://localhost:8888/metrics | Collector telemetry |

```bash
docker compose logs -f collector | grep -i -E "loki|file_log|redact"
docker compose down -v
```

---

## Exercise 1 — Verify both paths arrived

Grafana → Explore → **Loki**:
```logql
{service_name="checkout-service"}
{service_name="legacy-uninstrumented"}
```

★ **If the second is empty**, the `file_log` receiver isn't finding the file. Check in order:
1. Volume sharing — `legacy-app` mounts `legacy-logs:/var/log/legacy` (rw), the Collector mounts the **same named volume** `:ro`.
2. `include: [/var/log/legacy/*.log]` — the glob must match from **inside the Collector container**.
3. `start_at: end` — the Collector only reads lines written **after** it started. Wait ~10 s.
4. `docker compose exec collector ls /var/log/legacy` ★ **fails — the contrib image is distroless** (no shell). Check from the host instead: `docker compose logs legacy-app`.

---

## Exercise 2 — ★★ Labels vs structured metadata (the cost decision)

Loki **indexes labels** and stores everything else as **structured metadata**. Only labels create streams, and **stream count is your bill**.

See what's a label:
```logql
count by (service_name) (count_over_time({service_name=~".+"}[5m]))
```

Now try to filter by trace ID:
```logql
{service_name="checkout-service"} | trace_id=`<paste a 32-hex ID>`
```

**It works — and it cost zero streams.** That's structured metadata.

★ **Now try the thing you must never do** — promote `trace_id` to a label. In `loki-config.yaml`, add it to the promoted list:
```yaml
  otlp_config:
    default_resource_attributes_as_index_labels:
      - service.name
      - trace_id          # ★ NEVER DO THIS
```
```bash
docker compose restart loki collector
```

Watch `max_global_streams_per_user` get approached. **One stream per trace** = one stream per request. Loki's own docs put it plainly:
> *"Labels that take on many distinct values, such as `pod`, `host`, `thread`, `duration`, **`traceId`**, or **`spanId`**, can create hundreds of thousands or even millions of streams, causing slow queries, high memory usage, and **log loss at ingest**."*

**The rule:** a label must have a **bounded, small** set of values. `service_name`, `namespace`, `log_level` qualify. `trace_id`, `pod`, `request_id` do not. Revert.

---

## Exercise 3 — ★★ Redaction: verify it, don't assume it

The `legacy-app` writer emits this on **every line**:
```json
{"password":"hunter2","card":"4111 1111 1111 1111", ...}
```

**Go look in Loki.** Search:
```logql
{service_name="legacy-uninstrumented"} |= "hunter2"
```

★ **This must return NOTHING.** If it returns lines, your redaction is not working and you have plaintext credentials in your log store.

**Two verified traps:**

**1. `hash_function: sha256` is INVALID.** The allowed values are not the names you'd guess:
```
'hash_function' unknown HashFunction sha256, allowed functions are
sha1, sha3, md5, hmac-sha256 and hmac-sha512
```
★ Note the asymmetry — bare SHA-256 is absent, but the HMAC variants use a **dash**. And `md5`/`sha1` are offered despite being broken (fine for redaction fingerprints, never for security). The `hmac-*` variants also require `hmac_key`.

**2. ★★ The redaction processor emits NO internal metrics.** Verified: there is no `generated_telemetry.go`, and its `metadata.yaml` declares none. There is **no `otelcol_processor_redaction_*` metric**. Do not write an alert against one — it will never fire and never error.

What it *does* produce is **attributes on the data**:

| Attribute | With |
|---|---|
| `redaction.masked.count` / `allowed.count` / `ignored.count` | `summary: info` |
| ★ `redaction.masked.keys` | `summary: debug` — **leaks the field names you redacted** |

**So to alert on redaction you must derive a metric from the attribute.** That's the `span_metrics/redaction_audit` connector in this config, with `redaction.masked.count` as a dimension → `redaction_audit_calls_total{redaction_masked_count="N"}`. See dashboard panel 6, and Lab 02 for the same pattern on traces.

**Why this matters:** *"redaction stopped working"* is a **compliance incident**, not a performance one. If you can't alert on it, you'll find out from an audit.

---

## Exercise 4 — ★ Processor ORDER, which `validate` will not check

The `logs` pipeline order is deliberate:

```
memory_limiter → resource/enrich → transform/correlate-file-log
  → attributes/loki-labels → redaction/logs → filter/log-noise → batch
```

**Reorder it and break things:**

| Swap | What breaks |
|---|---|
| `redaction` **before** `transform/correlate-file-log` | ★ Redaction may mask `trace_id` before you promote it — **correlation silently dies**, logs still flow |
| `filter` **before** `redaction` | A body filter written against plaintext stops matching once values are masked |
| `batch` **first** | Batching before processing wastes work on data you're about to drop |
| `memory_limiter` not first | Process can OOM before the limiter protects it (★ runtime warning only, never a validation error) |

**Verify it's not checked:** move `batch` to position 1 and run
```bash
otelcol-contrib validate --config=otel-collector-config.yaml
```
★ **It passes.** Ordering is a correctness concern the validator does not model.

---

## Exercise 5 — ★★ The trace→log hop, and the two keys everyone gets wrong

Open a trace in Tempo, click a span, click **Logs for this span**. If nothing appears, it's one of these — **both fail silently**:

### Gotcha 1: the provisioning key is `tracesToLogsV2`, not `tracesToLogs`

From the current Grafana docs, verbatim:
> *"You can provision the trace to logs configuration using the **`tracesToLogsV2`** block in your data source YAML file."*

`tracesToLogs` is the legacy V1 shape. Grafana doesn't reject it loudly, which is why stale examples keep circulating. **V2 adds `customQuery` + `query`**, which is what you actually need with OTLP logs.

### Gotcha 2: `filterByTraceID: true` returns NOTHING for OTLP-ingested logs

`filterByTraceID` requires `trace_id` to be an **indexed label**. With OTLP ingestion it's **structured metadata** — so enabling it produces an **empty result, not an error**.

The correct V2 shape:
```yaml
tracesToLogsV2:
  datasourceUid: lab05-loki
  tags:
    - key: service.name
      value: service_name          # ★ dots → underscores
  filterByTraceID: false           # ★ false, deliberately
  customQuery: true
  query: '{${__tags}} | trace_id=`${__trace.traceId}`'
```

★ **And the label-mapping trap, from the docs verbatim:**
> *"The Loki label name you enter must exactly match the label name on your Loki streams. **A mismatch silently breaks the correlation with no error shown.**"*

Plus the remapping subtlety:
> *"The automatic dot-to-underscore remapping only applies to these **default** tags: `cluster`, `hostname`, `namespace`, `pod`, `service.name`, `service.namespace`. **For custom tags, you must specify the remapped name explicitly.**"*

### Gotcha 3: `spanStartTimeShift: 0` can return no logs

> *"A span's timestamps are precise to the millisecond, but log lines are often written slightly before or after the span boundary. **The default value of `0` can return no logs** if timestamps don't align exactly."*

Use `-2s`/`+2s` minimum; this lab uses `-1h`/`+1h` because the app buffers logs.

---

## Exercise 6 — ★ The log→trace hop: `matcherRegex`, and `matcherType: label`

In Loki Explore, a log line with a trace ID should show a **clickable link**. Three verified facts:

**1. The key is `matcherRegex`, NOT `regex`.** A `regex:` key is **silently ignored** — the link simply never appears, with no error. Grafana's own provisioning example uses `matcherRegex`.

**2. `matcherType` has exactly two values: `regex` and `label`.** ★ `byName` is **not valid**. The `label` field is barely documented — a Grafana community user had to read the *source* to find it:
> *"there is a `matcherType` field, which can be set to `label`"*

**3. `matcherType: label` is the one you want for OTLP logs**, because per the docs it *"matches any label: indexed, parsed, or **structured metadata**"*. And its value is a regex against the **label key**:
```yaml
- name: TraceID
  matcherType: label
  matcherRegex: "trace[_]?id"     # catches trace_id, traceid, traceId in ONE entry
  datasourceUid: lab05-tempo
  url: "$${__value.raw}"
```
★ `$$` — provisioning YAML needs the dollar escaped or Grafana interpolates it.

**Break it deliberately:** change `matcherRegex` to `regex` and restart Grafana. The link vanishes. No log line anywhere complains.

---

## Exercise 7 — ★ `file_log` rotation can lose logs silently

★★ **First, a naming trap.** The component was renamed to lower_snake_case — **`file_log`**, not `filelog` — but **the feature gates kept the old prefix.** Verified from `otelcol-contrib featuregate`:

```
filelog.allowFileDeletion                true   Beta
filelog.allowHeaderMetadataParsing       true   Beta
filelog.mtimeSortType                    true   Beta
filelog.protobufCheckpointEncoding       true   Beta
filelog.requireExplicitTopN              false  Alpha
filelog.windows.caseInsensitive          true   Beta
```

So you write `receivers: { file_log/legacy: ... }` but gate it with `--feature-gates=filelog.allowFileDeletion`. **Neither name is a typo**, and `validate` accepts the deprecated `filelog` alias for the component while `components` lists only `file_log`.

**Six gates, four ON by default:**

| Gate | Default | Consequence |
|---|---|---|
| `filelog.allowFileDeletion` | ★ **TRUE (Beta)** | Enables `delete_after_read` — a rotated-away file can be dropped **before it is fully read** |
| `filelog.allowHeaderMetadataParsing` | TRUE (Beta) | Enables the `header` setting — `#header` lines become metadata |
| `filelog.mtimeSortType` | TRUE (Beta) | Enables `ordering_criteria.mode = mtime` — sort by **mtime**, not name |
| `filelog.protobufCheckpointEncoding` | TRUE (Beta) | **Checkpoint storage is protobuf, not JSON** — so your offset file is not human-readable |
| `filelog.windows.caseInsensitive` | TRUE (Beta) | Windows only: include/exclude matching is case-insensitive |
| `filelog.requireExplicitTopN` | **FALSE (Alpha)** | ★ When enabled, `ordering_criteria.top_n` must be set explicitly. **While disabled, an unset `top_n` falls back to the legacy default of 1** — i.e. you read only ONE file when you meant to read several |

★ **If your log rotation is faster than the Collector's read rate, you lose logs and nothing errors.** `poll_interval: 200ms` and `max_log_size: 1MiB` here are chosen so the lab never hits it — but in production, size rotation against your read throughput.

**And the offset:**
```yaml
  filelog/legacy:
    storage: file_storage     # ★ persisted read offset
```
Without `storage`, every Collector restart either **re-reads** the file (duplicates) or **skips** to the end (gaps). With it, tailing resumes exactly. ★ The same `file_storage` extension also backs the `otlphttp/loki` **export queue**, so a restart doesn't drop the log backlog either.

---

## Exercise 8 — The metric→trace hop (exemplars)

Dashboard panel 9. Hover the error-rate line: each **diamond** is a real trace ID attached to a metric sample. Click it → Tempo.

★ **Two things must BOTH be true, or the diamonds are missing with no error:**

1. **Prometheus needs `--enable-feature=exemplar-storage`.** Without it, exemplars are **accepted but not retained** — a completely silent failure.
2. **The datasource must list BOTH label names:**
   ```yaml
   exemplarTraceIdDestinations:
     - name: traceID      # ★ Tempo's metrics_generator
     - name: trace_id     # ★ the OTel SDK / remote-write path
   ```
   Listing only one means **half your exemplars are unclickable**, and nothing tells you.

Now walk the whole triangle: **metric diamond → trace → span → Logs for this span → log line → back to trace.** That loop is the actual product of all this configuration.

---

## The red flags

| Symptom | ★ Cause |
|---|---|
| **`'exporters' unknown type: "loki"`** | **The loki EXPORTER was removed.** Use `otlphttp` → `http://loki:3100/otlp` |
| **404 from Loki** | **You wrote the full `/otlp/v1/logs` path** — the exporter appends `/v1/logs` itself |
| **"Logs for this span" is empty, no error** | **`tracesToLogs` instead of `tracesToLogsV2`**, or a tag label-name mismatch, or `filterByTraceID: true` against metadata |
| **Log→trace link never appears** | **`regex:` instead of `matcherRegex:`** — silently ignored |
| **`matcherType: byName` does nothing** | **Not a valid value.** Only `regex` and `label` |
| **trace_id missing from legacy logs in Loki** | **Not promoted.** `transform` must move `body["trace_id"]` → `attributes["trace_id"]` |
| **Loki stream count exploding** | **trace_id/span_id/pod promoted to labels.** Must stay in structured metadata |
| **`hash_function: sha256` rejected** | **Allowed: `sha1, sha3, md5, hmac-sha256, hmac-sha512`** |
| **No redaction metrics exist** | ★ **The processor emits none.** Derive one from the `redaction.masked.count` attribute |
| **Exemplar diamonds missing** | **`--enable-feature=exemplar-storage`**, and list BOTH `traceID` and `trace_id` |
| **`file_log` reads nothing** | **`start_at: end`** means only new lines; or the glob doesn't match inside the container |
| **Logs duplicated/gapped after restart** | **`file_log` has no `storage:`** — no persisted offset |
| **Logs lost during fast rotation** | ★ **`allowFileDeletion` is TRUE by default** |
| **Filter silently does nothing** | **`error_mode` defaults to `ignore`** — use `propagate` while developing |
| **`docker compose exec collector sh` fails** | ★ **The contrib image is distroless.** No shell, no wget, no apk |

## Rapid recall

- **No `loki` exporter.** `otlphttp` → `http://loki:3100/otlp` (base only; Loki ≥ 3.0).
- Loki OTLP needs **schema v13 + tsdb + `allow_structured_metadata: true`**.
- **Labels = streams = cost.** Only bounded-value keys. `trace_id` → **structured metadata**.
- Attribute **dots become underscores**: `service.name` → label `service_name`.
- Tempo provisioning key is **`tracesToLogsV2`**; use **`customQuery`** with `` | trace_id=`${__trace.traceId}` ``.
- Loki derived field key is **`matcherRegex`**; `matcherType` ∈ {`regex`, `label`}.
- **Redaction emits no metrics** — derive one from `redaction.masked.count`.
- `hash_function` allows **`sha1, sha3, md5, hmac-sha256, hmac-sha512`**.
- Exemplars need **`--enable-feature=exemplar-storage`** + both `traceID` and `trace_id` destinations.
- Processor **order is not validated**. Correlate → label → redact → filter → batch.

---

## What you should now be able to answer

1. How do I send logs from the Collector to Loki? → ★ **`otlphttp` exporter, `endpoint: http://loki:3100/otlp`. There is no `loki` exporter — it was removed.**
2. Why is `trace_id` structured metadata and not a label? → **Labels create streams; one per trace = one per request = Loki falls over.**
3. How do I correlate logs from a service I can't instrument? → **`file_log` + `json_parser` + `transform` to promote `body["trace_id"]` into `attributes["trace_id"]`, landing in the same metadata key as OTLP.**
4. Why is my "Logs for this span" link empty? → **`tracesToLogsV2` not `tracesToLogs`; label name mismatch; or `filterByTraceID: true` against metadata. All silent.**
5. How do I alert on redaction failing? → ★ **The processor emits no metrics. Derive one from the `redaction.masked.count` attribute via a `span_metrics` connector.**
6. What breaks if I redact before correlating? → **You may mask the trace_id you need to join on. Correlation dies silently while logs keep flowing.**
7. Why do I need `storage:` on `file_log`? → **Persisted read offset. Without it you get duplicates or gaps on every restart.**
8. What's the distroless consequence? → **No `exec` into the Collector, no healthcheck CMD. Probe `:13133` from outside.**

→ Next: [`../lab-06-kubernetes/`](../lab-06-kubernetes/) · Back: [`../README.md`](../README.md)
