# 04 · Semantic Conventions

The naming standard that makes telemetry from different languages, frameworks and vendors *mean the same thing*. Also, right now, the area with the most active breaking-change risk in OTel — because the **V0 → V1 convention migration is happening in production, gated behind Collector feature flags**.

Verified against **semantic-conventions v1.44.0** and **opentelemetry-collector-contrib v0.161.0**.

---

## 4.1 Why conventions exist at all

Without them:
```
service A (Java):   http.method = "GET",   net.peer.name = "db-1"
service B (Go):     request.method = "get", db_host = "db-1"
service C (Python): method = "GET",        peer.hostname = "db-1"
```
Three services, one dashboard, zero reusable queries. Every backend's out-of-the-box dashboard breaks per language.

With them:
```
all three:  http.request.method = "GET"   server.address = "db-1"
```
One query, one dashboard, one alert — regardless of who wrote the service.

★ **This is the actual reason to prefer OTel over a vendor agent**, more than vendor lock-in: a vendor agent gives *you* consistency inside *their* product. Conventions give you consistency across languages, across backends, and across time.

---

## 4.2 Stability levels — read the label, always

Every attribute, metric and span name in the semconv repo carries one of these. **They are not interchangeable and the difference determines whether you can build on them.**

| Level | Meaning | Can you build dashboards/alerts on it? |
|---|---|---|
| **Development** | Actively being designed. **Breaking changes expected without notice** | No. Prototype only |
| **Experimental** (was "Alpha") | Shape agreed, details may change. Breaking changes will be announced | Cautiously, with a plan to migrate |
| **Release Candidate** | Feature-complete, final validation | Yes, with light risk |
| **Stable** | **Backwards-compatible changes only.** Renames require a formal deprecation + migration path | **Yes. This is what you build on** |
| **Deprecated** | Superseded. Still emitted for compatibility, but going away | Migrate off |
| **Obsolete** | Removed. Do not use | No |

**How to check:** the semconv docs page for each attribute states its stability, and the YAML model files in the repo carry `stability:` fields. The Collector's `components` command shows per-component stability per signal — e.g. `tail_sampling` is `traces: Beta`, `filter` is `Alpha` for all signals, `debug` exporter is `Alpha`.

★ **A stability asymmetry worth internalising:** component stability and *convention* stability are independent. You can have a **Beta** processor emitting **Stable** attribute names, and a **Stable** exporter emitting **Experimental** conventions. Check both.

---

## 4.3 The V0 → V1 migration — what's happening right now ★

This is the biggest practical semconv topic in 2026 and it's poorly documented outside the repo.

**Background:** OTel's HTTP, RPC, database and messaging conventions were rewritten. The old set is informally called **V0**, the new **V1**. Examples:

| V0 (old) | V1 (new) |
|---|---|
| `http.method` | **`http.request.method`** |
| `http.status_code` | **`http.response.status_code`** |
| `http.url` | **`url.full`** |
| `http.scheme` | **`url.scheme`** |
| `http.route` | `http.route` (unchanged) |
| `http.target` | **`url.path`** + `url.query` |
| `http.host` / `net.host.name` | **`server.address`** |
| `net.peer.name` / `http.client_ip` | **`client.address`** |
| `net.peer.port` | **`server.port`** |
| `db.system` | **`db.system.name`** |
| `db.statement` | **`db.query.text`** |
| `db.name` | **`db.namespace`** |
| `db.operation` | **`db.operation.name`** |
| `db.sql.table` | **`db.collection.name`** |
| `deployment.environment` | **`deployment.environment.name`** |
| `messaging.message_id` | `messaging.message.id` |
| `rpc.service` | `rpc.service` (with `server.address` for the peer) |
| HTTP server span name `HTTP GET` | **`{http.request.method} {http.route}`** e.g. `GET /users/:id` |
| HTTP server metric `http.server.duration` | **`http.server.request.duration`** (seconds, histogram) |

### It's feature-gated in the Collector

The Collector can emit **either or both** convention sets, controlled per-component by feature gates.

★★ **Read this first — the values below come from `otelcol-contrib featuregate`, NOT from `--help`.** The `--feature-gates` default string printed by `otelcol-contrib --help` **disagrees with the real registered values** for several gates in v0.161.0. Verified examples:

| Gate | `--help` shows | `featuregate` shows | Source of truth |
|---|---|---|---|
| `processor.filter.defaultErrorModeIgnore` | `-` (off) | **true** | Source: `createDefaultConfig()` sets `ErrorMode: ottl.IgnoreError`; doc says *"The default value is `ignore`"* → **`featuregate` is right** |
| `processor.k8sattributes.DontEmitV0K8sConventions` | `-` (off) | **true** | Code reads the gate; a validation error exists for enabling it without `EmitV1` → **`featuregate` is right** |
| `connector.routing.defaultErrorModeIgnore` | `-` (off) | **true** | Consistent with the above two |

★ **Rule: always use `otelcol-contrib featuregate` to read gate state. Treat the `--help` default string as unreliable.** Getting this wrong inverts your understanding of default behaviour.

### The actual gate states in v0.161.0 (verified)

| Component | `EmitV1*` | `DontEmitV0*` | Stage | **What it emits** |
|---|:---:|:---:|---|---|
| **`processor.k8sattributes`** | **true** | **true** | Beta | ★ **V1 (new) names ONLY** |
| `extension.azureencoding` | **true** | **true** | Beta | ★ **V1 only** |
| `pkg.translator.faro` (deployment.environment) | **true** | **true** | Beta | ★ **V1 only** |
| `pkg.translator.zipkin` — **network** attrs | **true** | **true** | Beta | ★ **V1 only** |
| `extension.encoding.awslogsencoding` (RPC) | **true** | **false** | Beta/Alpha | ★ **BOTH V0 and V1** |
| `extension.encoding.googlecloudlogentryencoding` | — | **true** | Beta | V0 suppressed |
| `receiver.hostmetrics` + `scraper.process` | false | false | Alpha | **V0 (legacy) only** |
| `pkg.translator.zipkin` — http / scope / cloud_resource | false | false | Alpha | **V0 only** |
| `pkg.translator.jaeger` — http | false | false | Alpha | **V0 only** |
| `receiver.awsecscontainermetrics` | false | false | Alpha | **V0 only** |
| `receiver.awsxray` — http | false | false | Alpha | **V0 only** |
| `processor.resourcedetection.elasticbeanstalk` | false | false | Alpha | **V0 only** |
| `pkg.translator.azurelogs` | false | false | Alpha | **V0 only** |
| `receiver.apache` (new metric format) | false | false | Alpha | **old format only** |
| `receiver.postgresql.useOTelSemconv` / `.separateSchemaAttr` | false | false | Alpha | legacy names |
| `translator.skywalking.useStableSemconv` | false | false | Alpha | legacy |
| `stanza.udp.useStableNetworkAttributes` | false | false | Alpha | **deprecated `net.*` attrs** |
| `spanmetrics.statusCodeConvention.useOtelPrefix` | false | — | Alpha | `status.code=STATUS_CODE_ERROR`, **not** `otel.status_code=ERROR` |
| `processor.k8sattributes.telemetry.*` (its own metrics) | **newFormat true** | **disableOld true** | Beta | new format only |

★ **The real pattern is NOT "most components emit both." Almost none do.** Read the **stage** column:

- **Beta gates enabled** → **migration COMPLETE. V1 only.** (`k8s_attributes`, `azureencoding`, `faro`, zipkin network)
- **Alpha gates disabled** → **migration NOT STARTED. V0 only.** (host_metrics, process scraper, most translators)
- **Mixed** → **mid-migration, emits both.** (only `awslogsencoding`, and only for RPC)
- **Split within one component** → ★ **`pkg.translator.zipkin` has finished `network` but not `http`, `scope` or `cloud_resource`.** One translator, two conventions simultaneously.

**Practical consequences — and they're the opposite of what you'd guess:**
1. ★ **The dominant risk is INCONSISTENCY, not extra volume.** Kubernetes attributes arrive under new names while host metrics arrive under legacy names. **A dashboard written against one convention silently returns nothing for data from the other component.** This is the real explanation for *"works for some services and not others."*
2. **`k8s_attributes` already emits V1-only.** If your dashboards query `k8s.pod.annotations.<key>` and get nothing, note the config comment: it's **`k8s.pod.annotation.<key>` (singular)** when `EmitV1K8sConventions` is on. ★ Same for `k8s.pod.label.<key>`. **Singular vs plural — an easy miss.**
3. **`DontEmitV0` cannot be enabled without `EmitV1`** — the processor returns: `processor.k8sattributes.DontEmitV0K8sConventions cannot be enabled without enabling processor.k8sattributes.EmitV1K8sConventions`.
4. **`host_metrics` still emits V0.** Enabling `receiver.hostmetrics.EmitV1SystemConventions` *"supersedes per-scraper gates"* — one switch for all scrapers.
5. **Turning off V0 is a one-way door for your dashboards.** Do it only after every consumer has moved.

**How to flip a gate:**
```bash
# host_metrics → V1 system conventions (all scrapers at once)
otelcol-contrib --config=config.yaml \
  --feature-gates=receiver.hostmetrics.EmitV1SystemConventions

# then, once dashboards have moved, stop emitting V0
otelcol-contrib --config=config.yaml \
  --feature-gates=receiver.hostmetrics.EmitV1SystemConventions,receiver.hostmetrics.DontEmitV0SystemConventions

# k8s_attributes is already V1-only. To go BACK to legacy names you must
# explicitly DISABLE both gates (note the '-' prefixes):
otelcol-contrib --config=config.yaml \
  --feature-gates=-processor.k8sattributes.EmitV1K8sConventions,-processor.k8sattributes.DontEmitV0K8sConventions
```
```bash
# See every gate and its current state — do this before and after any upgrade
otelcol-contrib featuregate
```

### The `schema` processor

Contrib has a **`schema` processor** (present in v0.161.0) whose whole job is translating telemetry from one semconv version to another:
```yaml
processors:
  schema:
    # Translate inbound data emitted against semconv 1.20.0 up to the current
    # version, so all data leaving the Collector is internally consistent.
    # (translate_from / translate_to are configured per signal)
```
★ **This is the right place to normalise** rather than patching each dashboard. Run it at the **gateway** tier so every backend and every consumer sees one convention version, and let agents emit whatever their SDK version produces.

---

## 4.4 The conventions that matter most, by domain

### HTTP (server and client)

**Span names** — ★ low cardinality is the whole point:
```
Good:  GET /users/:id           POST /checkout          HTTP CONNECT
Bad:   GET /users/12345         POST /checkout?session=abc&ref=xyz
```
`http.route` is the templated path. **If your framework doesn't give you the route, your span names will be unbounded** — this is the classic Express/Flask "span name cardinality explosion" and it's fixed by using the framework instrumentation that knows the router, or by normalising in a Collector `transform`.

**Metrics** (V1):
| Metric | Type | Unit | Notes |
|---|---|---|---|
| **`http.server.request.duration`** | Histogram | `s` | The main one. Replaces `http.server.duration` (ms) |
| `http.server.active_requests` | UpDownCounter | `{request}` | In-flight requests — the concurrency signal |
| `http.client.request.duration` | Histogram | `s` | |
| `http.client.open_connections` | UpDownCounter | `{connection}` | Connection pool visibility |

Recommended attributes: `http.request.method`, `http.response.status_code`, `http.route`, `url.scheme`, `network.protocol.version`, `server.address`, `server.port`.

★ **Unit change from ms to s** between V0 and V1 HTTP duration metrics. If you migrate the name but not the unit assumption, your p99 dashboard shows 0.5 instead of 500. **Check the `unit` field, not just the name.**

### Databases

| Attribute | Meaning |
|---|---|
| `db.system.name` | `postgresql`, `mysql`, `redis`, `mongodb`, `dynamodb` |
| `db.namespace` | Database/schema/keyspace name |
| `db.operation.name` | `SELECT`, `INSERT`, `HGETALL` |
| `db.collection.name` | Table/collection/index |
| **`db.query.text`** | ★ **The actual query. This is PII and a security surface** |
| `db.stored_procedure.name`, `db.query.parameter.*` | |
| `server.address`, `server.port` | The DB host |
| `db.response.status_code`, `error.type` | Failure classification |

★ **`db.query.text` deserves its own decision.** It's enormously useful for debugging and enormously risky for compliance:
- **Bound parameters are usually not inlined** (good), but many ORMs interpolate. Check what your instrumentation actually emits.
- **Table and column names are often confidential** — they reveal your schema to anyone with dashboard access.
- **Long queries cost storage.** A 10 KB query on a hot path is a real bill.
- **Mitigations:** truncate with a Collector `transform` (`truncate_left(attributes["db.query.text"], 200)`), drop it entirely for specific services, or keep it only for error spans:
```yaml
processors:
  transform/db-queries:
    error_mode: ignore
    trace_statements:
      - context: span
        statements:
          # keep the query only when the span errored
          - delete_key(attributes, "db.query.text") where status.code != 2
          - truncate_left(attributes["db.query.text"], 200) where status.code == 2
```

### Messaging

`messaging.system` (`kafka`, `rabbitmq`, `sqs`, `pubsub`), `messaging.operation.name` (`send`, `receive`, `process`, `create`), `messaging.message.id`, `messaging.message.conversation_id`, `messaging.destination.name`, `messaging.batch.message_count`, `messaging.client.id`, plus `server.address`/`server.port`.

★ **`messaging.destination.name` is a cardinality risk if destinations are dynamic** (per-user topics, per-tenant queues, temporary reply queues). Cap it, redact it, or normalise it.

### RPC / gRPC
`rpc.system` (`grpc`, `java`, `dotnet_wcf`), `rpc.service`, `rpc.method`, `rpc.connect_error.code`, and **`rpc.grpc.status_code`** — an integer, which makes "alert on non-zero gRPC status" a one-liner.

### Containers and Kubernetes ★ (stable as of semconv v1.43.0)
`k8s.namespace.name`, `k8s.pod.name`, `k8s.pod.uid`, `k8s.deployment.name`, `k8s.replicaset.name`, `k8s.statefulset.name`, `k8s.daemonset.name`, `k8s.job.name`, `k8s.cronjob.name`, `k8s.node.name`, `k8s.cluster.name`, `k8s.container.name`, `k8s.init_container.name`, `container.id`, `container.name`, `container.image.name`, `container.image.tag`, `container.image.repo_digests`, `container.runtime`.

**The v1.43.0 graduation of the core Kubernetes and container-registry attributes to stable is significant** — it means you can now build long-lived dashboards and alerts on `k8s.deployment.name` without a migration plan. Before that, they were experimental.

### GenAI ★ — moved to its own repository
As of **semconv v1.42.0**, **all `gen_ai.*` attributes, metrics, events and spans were deprecated in the main semantic-conventions repo and moved to a dedicated GenAI semantic conventions repository.** Links into `semantic-conventions/docs/gen-ai` are stale.

What's in them:
| Attribute | Meaning |
|---|---|
| `gen_ai.system` / `gen_ai.provider.name` | `openai`, `anthropic`, `bedrock`, … |
| `gen_ai.request.model` | Model requested |
| `gen_ai.response.model` | Model that actually answered (can differ) |
| `gen_ai.request.temperature` / `top_p` / `max_tokens` | Generation parameters |
| **`gen_ai.usage.input_tokens`** / **`gen_ai.usage.output_tokens`** | ★ The cost driver |
| `gen_ai.response.finish_reasons` | `stop`, `length`, `tool_calls`, `content_filter` |
| `gen_ai.operation.name` | `chat`, `text_completion`, `embeddings`, `execute_tool` |
| `gen_ai.tool.name` / `gen_ai.tool.type` | Tool/function calling |
| `gen_ai.conversation.id` | Session correlation |
| **Prompt/response content** | ★ **Opt-in only.** Off by default for obvious reasons |

Also present: **retrieval span support** (added in semconv v1.39.0) for RAG pipelines, and a **`gen_ai_normalizer` processor in Collector contrib v0.161.0** — which exists because the various LLM instrumentation libraries (OpenLLMetry, Vercel AI SDK, LangChain, CrewAI) emit *slightly different* shapes and something has to normalise them.

**Status: in development, changing faster than core conventions.** That's precisely why they were split out. **Pin what you depend on and expect renames.** In active use already by VS Code Copilot, OpenAI Codex and Claude Code; supported by Datadog, Honeycomb, New Relic, LangChain, CrewAI and AutoGen.

★ **Prompt/response content capture is a data-governance decision, not a config toggle.** If you enable it, you are shipping user prompts and model outputs — potentially containing PII, credentials, and proprietary text — into your observability backend, where retention, access control and possibly cross-border transfer rules apply. Decide deliberately, with whoever owns compliance, and default to **off with token counts on**. Token counts give you cost and latency observability, which is 90% of what people actually need.

### Other domains worth knowing exist
- **`app.*`** — mobile/frontend: an `app.jank` event was defined in semconv v1.39.0 for UI stutter.
- **`hardware.*`** — datacenter hardware metrics (moved to component files in v1.36.0).
- **`aspnetcore.*`** — ASP.NET Core, including Identity metrics (v1.37.0).
- **`browser.*`, `device.*`, `os.*`, `process.*`, `thread.*`** — client and runtime.
- **`telemetry.sdk.*`**, **`telemetry.distro.*`** — what produced the data.

---

## 4.5 Per-language semconv packages

| Language | Package | Versioning behaviour |
|---|---|---|
| **Go** | `go.opentelemetry.io/otel/semconv/v1.34.0` | ★ **Versioned by import path.** `semconv/v1.30.0` and `semconv/v1.34.0` can coexist in one build — upgrades are incremental, per-dependency |
| **Python** | `opentelemetry-semantic-conventions` (**0.65b0**, Jul 2026) | One version per release; **note the `b0` — still beta track** |
| **Node.js** | `@opentelemetry/semantic-conventions` | Released separately from the SDK; `semconv/v1.43.0` shipped Jul 2026. **Not part of the JS SDK 2.x major** |
| **Java** | `io.opentelemetry.semconv:opentelemetry-semconv` | Separate artifact from the SDK |
| **.NET** | `OpenTelemetry.SemanticConventions` | |
| **Ruby** | `opentelemetry-semantic_conventions` | |
| **PHP** | `open-telemetry/sem-conv` | |

★ **Go's path-versioned package is the best design here** and worth understanding: because the import path contains the version, two libraries in your dependency tree can use different semconv versions simultaneously, and the compiler doesn't care. In other languages, upgrading the semconv package upgrades it for everyone, which is how an "innocent" dependency bump breaks your dashboards.

**The practical risk in non-Go languages:** a transitive dependency upgrade bumps the semconv package, your attribute names change, and your dashboard silently shows no data. **Pin the semconv package explicitly in your lockfile** and treat its upgrade as a migration, not a bump.

---

## 4.6 Normalisation: when your data doesn't follow conventions

Real pipelines contain a mix of OTel-convention data, Prometheus-scraped metrics, vendor-agent data and hand-rolled attributes. Collector contrib handles this in three places:

### 1. The `transform` processor with OTTL
The general-purpose tool. **OTTL** (OpenTelemetry Transformation Language) is a small expression language over telemetry:
```yaml
processors:
  transform/normalise:
    error_mode: ignore          # ignore | propagate | silent
    trace_statements:
      - context: resource
        statements:
          # map the many ways people spell "environment" onto the convention
          - set(attributes["deployment.environment.name"], attributes["env"]) where attributes["env"] != nil
          - delete_key(attributes, "env")
          - set(attributes["service.name"], attributes["appname"]) where attributes["service.name"] == nil
      - context: span
        statements:
          - set(attributes["http.request.method"], attributes["http.method"]) where attributes["http.method"] != nil
          # normalise high-cardinality span names
          - replace_pattern(name, "/users/\\d+", "/users/:id")
          - replace_pattern(attributes["url.full"], "session=[^&]+", "session=REDACTED")
    metric_statements:
      - context: datapoint
        statements:
          - set(attributes["http.response.status_code"], attributes["status"]) where attributes["status"] != nil
```
Contexts available: `resource`, `scope`, `span`, `spanevent`, `metric`, `datapoint`, `log`, `profile`. Note `profile` — **OTTL transforms work on profile data as of v0.148.0+**, which is how you enrich profiles with K8s metadata.

Feature gates affecting OTTL — **values from `otelcol-contrib featuregate`, which is authoritative** (see the `--help` warning above): `ottl.PanicDuplicateName` (**true**, Stable), `ottl.contexts.enableOTelColContext` (**true**, Stable — lets statements read Collector-internal state), `ottl.functions.enableLambda` (★ **false**, Alpha), `ottl.set.allowNil` (★ **true**, Beta), and `processor.transform.defaultErrorModeIgnore` (★ **true**, Stable — **so `error_mode` DOES default to `ignore`**, confirmed in source: `createDefaultConfig()` sets `ErrorMode: ottl.IgnoreError` and the config doc reads *"The default value is `ignore`"*). `processor.filter.defaultErrorModeIgnore` is likewise **true**/Stable. ★ **Set `error_mode: propagate` deliberately when you want a bad OTTL statement to fail loudly rather than be swallowed** — with the default, a typo in a statement silently does nothing.

### 2. The `attributes` and `resource` processors
Simpler, non-expression-based: `insert`, `update`, `upsert`, `delete`, `hash`, `extract`, `convert`. **`hash` is the PII-preserving option** — it turns an email into a stable pseudonym you can group by without storing the email.

### 3. The Prometheus translator's label sanitisation
Prometheus label names must match `[a-zA-Z_][a-zA-Z0-9_]*`. OTel attribute names happily contain dots (`http.request.method`). Translation therefore **replaces `.` with `_`**, and:
- `pkg.translator.prometheus.PermissiveLabelSanitization` — **off by default.** When on, invalid characters are replaced rather than dropped, which is more predictable but changes names.
- `exporter.prometheusexporter.DisableAddMetricSuffixes` — **true (Beta)**. ★ **Its effect is not what the name suggests.** Verified from source: when the gate is on, *"the deprecated `add_metric_suffixes` configuration option is ignored and `translation_strategy` is always used"*, and with `translation_strategy` unset `getTranslationConfiguration()` returns `UnderscoreEscapingWithSuffixes`. **So suffixes ARE still added by default** — a counter `http.requests` becomes `http_requests_total`, a histogram `x` becomes `x_bucket`/`x_sum`/`x_count`, and units get appended — **but setting `add_metric_suffixes: false` no longer does anything.** Use `translation_strategy` instead:

| `translation_strategy` | Suffixes | UTF-8 → `_` | Note |
|---|:---:|:---:|---|
| `UnderscoreEscapingWithSuffixes` | **yes** | yes | ★ **the default** |
| `UnderscoreEscapingWithoutSuffixes` | no | yes | |
| `NoUTF8EscapingWithSuffixes` | **yes** | **no** | ★ Keeps UTF-8 names — pairs with Prometheus 3.x native UTF-8 metric names |
| `NoTranslation` | no | no | Pass names through unaltered |

★ **This is the #1 "my metric disappeared" issue when bridging OTel → Prometheus.** You emit `http.server.request.duration`; Prometheus shows `http_server_request_duration_seconds_bucket`. That's correct behaviour, not a bug. Turn the suffix behaviour off only if you have a strong reason and understand you'll be writing non-idiomatic PromQL.

---

## 4.7 A practical semconv governance policy

What to actually write down for your organisation:

1. **Pin a semconv version per service**, in the lockfile, and record it in the service catalogue. `scope.schema_url` reports it at runtime — you can alert on drift.
2. **Build only on Stable conventions.** Anything Experimental goes in a "may change" section of the dashboard, with an owner and a review date.
3. **Normalise at the gateway, not in the dashboard.** One `schema`/`transform` processor in the central Collector tier. Dashboards query one convention version.
4. **Keep an attribute allowlist for metrics.** `views` with `attribute_keys.included` at the SDK, plus a Collector-side `cardinality_guardian` / `filter`. Allowlists mean an instrumentation upgrade can't silently explode series count. See [`06-metrics.md`](06-metrics.md) and [`14-scale-cost-and-cardinality.md`](14-scale-cost-and-cardinality.md).
5. **Treat `db.query.text`, prompt/response content, and anything matching an email/IP/token pattern as sensitive by default.** Redaction happens in the Collector, before the backend. See [`15-security-and-governance.md`](15-security-and-governance.md).
6. **Have a convention-change runbook.** When V0 emission is turned off, or a semconv minor version renames something: who updates the dashboards, in what order, and how do you verify no gaps.
7. **Review semconv release notes on upgrade.** The v1.42.0 GenAI move and the v1.43.0 Kubernetes graduation both changed what you could rely on. Two minutes of reading prevents a day of debugging.
8. **Contribute your internal conventions upstream** if they're general enough. If they're not, document them in one place with the same rigour — name, type, unit, stability, owner. Undocumented internal attributes are how you end up with 40 ways to spell "tenant".

---

## Red flags

| Doing this | Costs you |
|---|---|
| Building dashboards on Experimental/Development conventions without an owner or review date | Silent breakage, and nobody knows whose job it is to fix |
| Ignoring the stability label entirely | Same, but sooner |
| Assuming `EmitV1*` gates are all off (or all on) | ★ **They're mixed by *stage*: Beta = V1-only, Alpha = V0-only.** Run `otelcol-contrib featuregate` |
| Reading gate defaults from `otelcol-contrib --help` | ★ **That string is wrong for several gates** (`processor.filter.defaultErrorModeIgnore`, `processor.k8sattributes.DontEmitV0K8sConventions`, `connector.routing.defaultErrorModeIgnore`, `ottl.set.allowNil`, `connector.spanmetrics.excludeResourceMetrics`). **Use the `featuregate` subcommand** |
| Writing a dashboard against one semconv generation and assuming it covers everything | ★ **`k8s_attributes` is V1-only while `host_metrics` is V0-only** — the same dashboard can't see both |
| Querying `k8s.pod.annotations.<key>` after the V1 flip | ★ It's **`k8s.pod.annotation.<key>`** (singular) when `EmitV1K8sConventions` is on; same for `k8s.pod.label.<key>` |
| Setting `add_metric_suffixes: false` to stop suffixes | ★ **Deprecated and ignored.** Use `translation_strategy` |
| Turning off `DontEmitV0*` before migrating dashboards | Data gap, and a very confusing incident |
| Not budgeting for dual V0+V1 emission | ~2× attribute/metric volume during the migration window |
| Span names with IDs in them | Unbounded span-name cardinality; backend index explodes |
| Assuming the HTTP duration unit didn't change | V0 was **ms**, V1 is **s**. Your p99 is off by 1000× |
| Letting a dependency bump the semconv package | Attribute names change with no code change from you. Pin it |
| Enabling GenAI prompt/response capture because it's a toggle | You just shipped user prompts and PII into an observability backend |
| Relying on stale `semantic-conventions/docs/gen-ai` links | **Moved to its own repo in v1.42.0** |
| Expecting your metric name in Prometheus to match what you emitted | Suffixes are added by default (`_total`, `_seconds`, `_bucket`). Correct behaviour |
| Hand-patching each dashboard instead of normalising at the gateway | Every new service repeats the problem |
| Storing `db.query.text` untruncated everywhere | PII, schema disclosure, and a large bill |
| Dynamic messaging destinations as an attribute | Cardinality explosion on per-user/per-tenant topics |

---

## Rapid recall

1. **Conventions exist so telemetry means the same thing across languages and backends.** That's the real argument for OTel over a vendor agent — consistency across time, not just inside one product.
2. **Stability levels: Development → Experimental → RC → Stable → Deprecated → Obsolete.** Build only on **Stable**. Component stability and convention stability are **independent** — check both.
3. **V0 → V1 is live and feature-gated in the Collector.** Key renames: `http.method`→`http.request.method`, `http.status_code`→`http.response.status_code`, `http.url`→`url.full`, `net.host.name`→`server.address`, `db.statement`→`db.query.text`, `db.system`→`db.system.name`, `deployment.environment`→`deployment.environment.name`, `http.server.duration` (ms) → **`http.server.request.duration` (s)**.
4. ★ **Almost no component emits both V0 and V1 in v0.161.0 — the real pattern is INCONSISTENCY.** Read the gate *stage*: **Beta gates enabled = migration complete, V1 only** (`k8s_attributes`, `azureencoding`, `faro`, zipkin *network*); **Alpha gates disabled = migration not started, V0 only** (`host_metrics`, `scraper.process`, zipkin *http/scope/cloud_resource*, `jaeger`, `awsecscontainermetrics`, `awsxray`, `elasticbeanstalk`, `azurelogs`, `apache`, `postgresql`, `skywalking`, `stanza.udp`); **exactly one emits both** (`extension.encoding.awslogsencoding`, RPC only). ★ **`pkg.translator.zipkin` has finished `network` but not `http`/`scope`/`cloud_resource` — two conventions inside one translator.** The dominant risk is therefore a dashboard written against one convention silently returning nothing for data from the other component — which is the real explanation for *"works for some services and not others."* **Always read state with `otelcol-contrib featuregate`; the `--help` default string is wrong for several gates.**
5. **The `schema` processor** translates between semconv versions — normalise at the **gateway** tier so every consumer sees one version, instead of patching dashboards.
6. **Unit changes are silent killers:** V0 HTTP duration was **milliseconds**, V1 is **seconds**. Read the `unit` field.
7. **Span names must be low cardinality** — `GET /users/:id`, never `GET /users/12345`. If your framework doesn't expose the route, span-name cardinality will explode; fix it in the instrumentation or normalise with `transform`/`replace_pattern`.
8. **K8s + container-registry resource attributes graduated to stable in semconv v1.43.0** — now safe to build long-lived dashboards on `k8s.deployment.name`.
9. **GenAI conventions moved to their own repo in v1.42.0** and are **in development** — pin and expect renames. Collector contrib has a **`gen_ai_normalizer`** processor because LLM libraries emit divergent shapes. **Token counts on by default; prompt/response content is an opt-in governance decision, not a toggle.**
10. **Semconv packages:** Go is **versioned by import path** (multiple versions coexist — best design); other languages ship one version per package, so **pin explicitly** or a transitive bump renames your attributes.
11. **OTel → Prometheus renames your metrics**: dots become underscores and **suffixes are added by default**. `http.server.request.duration` becomes `http_server_request_duration_seconds_bucket`. ★ But `add_metric_suffixes` is **deprecated and ignored** — `DisableAddMetricSuffixes` being true just means **`translation_strategy` governs**, and unset resolves to `UnderscoreEscapingWithSuffixes`. Choose `NoUTF8EscapingWithSuffixes` to keep UTF-8 names with Prometheus 3.x.
12. **OTTL contexts**: `resource`, `scope`, `span`, `spanevent`, `metric`, `datapoint`, `log`, **`profile`**. ★ **`error_mode` DOES default to `ignore`** in v0.161.0 (`processor.transform.defaultErrorModeIgnore` and `processor.filter.defaultErrorModeIgnore` are both **true/Stable**; source confirms `ErrorMode: ottl.IgnoreError`). **A typo'd OTTL statement is therefore swallowed silently** — set `error_mode: propagate` when building and debugging, then decide deliberately.
13. **Governance minimum:** pin semconv version per service, build only on stable, normalise at the gateway, **allowlist** metric attributes, treat `db.query.text`/prompts/PII patterns as sensitive by default, and read the semconv release notes on every upgrade.

→ Next: [`05-traces.md`](05-traces.md)
