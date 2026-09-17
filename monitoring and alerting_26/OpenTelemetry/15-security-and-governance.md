# 15 · Security, Privacy & Governance

Telemetry is **data about your users and your systems**, collected automatically, at high volume, by code nobody reviews line-by-line. It is one of the most under-governed data flows in a typical engineering organisation.

*Every configuration in this file was passed through `otelcol-contrib v0.161.0 validate`. Stability levels are from the authoritative component inventory for that release.*

---

## 15.1 Why telemetry is a security surface

Four reasons, and they compound:

1. **It's collected by default.** Instrumentation libraries decide what to capture. A single config flag — `OTEL_INSTRUMENTATION_HTTP_CAPTURE_HEADERS=all` — starts copying **every HTTP header** into your traces, including `Authorization`, `Cookie`, and `X-Api-Key`. Nobody reviewed that as a data-flow decision.
2. **It crosses trust boundaries.** Telemetry routinely leaves the pod, the namespace, the cluster, the VPC, and sometimes the country. Each hop is a place PII can leak.
3. **It has a long tail.** Metrics live for years. A leak today is discoverable in data nobody planned to keep.
4. **The pipeline itself is privileged.** A Collector with `k8s_attributes` has cluster-wide read on pods. A gateway holds **every request's data in memory**. Compromise it and you have a firehose.

★ **The framing that gets budget:** telemetry is not "observability infrastructure," it is **a data-processing system subject to the same controls as your product database** — and usually governed far less.

---

## 15.2 The `redaction` processor — verified configuration

**Stability in v0.161.0:** ★ **`traces: Beta`, `logs: Alpha`, `metrics: Alpha`.** Distributions: **contrib and k8s**.

That stability split matters: **traces redaction is Beta, logs and metrics are Alpha.** If your primary PII exposure is in log bodies, you're relying on Alpha-stage behaviour. **Test it against your real data.**

### Full config (validated)
```yaml
processors:
  redaction:
    # ★ allowed_keys is DESIGNED TO FAIL CLOSED.
    #   If allowed_keys is empty, ALL attributes are removed.
    #   Set allow_all_keys: true to disable the list (blocked_values still applies).
    allow_all_keys: false
    allowed_keys: [description, group, id, name]

    # Processed FIRST — always allowed, never blocked.
    # ★ "should only be used where you know the data is always safe to send"
    ignored_keys: [safe_attribute]
    ignored_key_patterns: ["^safe_.*", ".*_trusted$"]

    # Check AsString() representation — lets you redact sensitive data in INTS
    # (e.g. a credit card stored as a number). ★ Off by default.
    redact_all_types: true

    # Keys matching these regexes have their VALUES masked
    blocked_key_patterns: [".*token.*", ".*api_key.*"]

    # Values matching these are masked. ★ Applied IN LISTED ORDER —
    #   when patterns overlap, the first match determines what the later can match.
    blocked_values:
      - "4[0-9]{12}(?:[0-9]{3})?"                                   # Visa
      - "(5[1-5][0-9]{14})"                                         # MasterCard
      - "(?:[0-9]{1,3}\\.){3}[0-9]{1,3}"                            # IPv4
      - '\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b'        # email

    # ★ allowed_values TAKES PRECEDENCE over blocked_values —
    #   a value matching allowed_values is NOT masked even if it also matches blocked_values
    allowed_values: [".+@mycompany.com"]

    # md5 | sha1 | sha3 (SHA-256) | hmac-sha256 | hmac-sha512
    hash_function: hmac-sha256
    hmac_key: "${env:REDACTION_SECRET_KEY}"

    # debug = counts AND key names | info = counts only | silent = none
    summary: silent

    url_sanitizer:
      enabled: true
      attributes: ["http.url", "url"]
      sanitize_span_name: true          # default true
```

### The processing order ★ (this is the part people get wrong)

```
1. ignored_keys / ignored_key_patterns  → pass through untouched
2. allowed_keys                         → attributes NOT on the list are REMOVED
                                          (their values never reach step 3)
3. blocked_key_patterns                 → matching keys' values are MASKED
4. allowed_values                       → takes precedence, NOT masked
5. blocked_values                       → matching value substrings MASKED
```

**Upstream's own worked example makes the trap concrete.** With `allowed_keys: [description, email]` and a Visa pattern in `blocked_values`, a span arriving with `credit_card: "4111111111111111"` and `internal_id: "abc-123"` is emitted as:

| Key | Value |
|---|---|
| `description` | `"payment processed"` |
| `email` | `"user@example.com"` |
| `redaction.redacted.keys` | `"credit_card,internal_id"` |
| `redaction.redacted.count` | `"2"` |

★ **"Note that `credit_card` was REMOVED (not masked) because it was not in `allowed_keys` — its value never reached the `blocked_values` check."**

**Why this matters:** if you configure *only* `blocked_values` patterns and leave `allowed_keys` empty, **every attribute is stripped** — you get an empty span, not a scrubbed one. Conversely, if you set `allow_all_keys: true` and rely solely on value patterns, **a new attribute name you didn't anticipate passes through unredacted**. ★ **`allowed_keys` fails closed; `allow_all_keys` fails open. Choose deliberately.**

### HMAC key requirements — verified by `validate` ★

| `hash_function` | Minimum `hmac_key` length | Error if short |
|---|---|---|
| `hmac-sha256` | **32 bytes** | `hmac_key must be at least 32 bytes long for "hmac-sha256", got 6 bytes` |
| `hmac-sha512` | **64 bytes** | `hmac_key must be at least 64 bytes long for "hmac-sha512", got 8 bytes` |
| unset with HMAC | — | ★ `hmac_key must not be empty when hash_function is "hmac-sha256"` |

**Two consequences worth internalising:**

1. **Why HMAC at all.** Upstream is explicit: *"For enhanced security, especially when dealing with **low-entropy data like IP addresses**, HMAC hash functions are recommended over simple hash functions like MD5, SHA1, or SHA3."* ★ **An unsalted SHA-256 of an IPv4 address is trivially reversible** — there are only ~4 billion of them, and a rainbow table takes minutes. HMAC with a secret key makes that infeasible, so you can still **correlate** by hashed IP without **identifying** the IP.
2. **`hmac_key: "${env:REDACTION_SECRET_KEY}"` with the env var unset makes the Collector FAIL TO START.** ★ **This is fail-closed behaviour, and it's good** — but it means a secret-rotation mistake takes down your telemetry pipeline. **Alert on Collector start failures**, and validate the secret exists in your deploy pipeline before rollout.

### `url_sanitizer` — where security meets cardinality ★

> *"Enables sanitization of URLs in specified attributes by removing potentially sensitive information like **UUIDs, timestamps, and other non-essential path segments**. This is particularly useful for **reducing cardinality** in telemetry data while preserving the essential parts of URLs for troubleshooting."*

And for span names: *"By default, when URL sanitization is enabled, **span names for client and server span types that contain `/` characters are automatically sanitized.** This helps reduce cardinality issues caused by high-variability URL paths in span names."*

★ **This is a rare component that fixes a privacy problem and a cost problem simultaneously.** `/users/8f3a2b1c-4d5e-.../orders/99123` becomes `/users/*/orders/*` — the user ID no longer lands in your trace store, *and* your span-name cardinality stops being unbounded. **If you have REST APIs with IDs in paths, enable this.** It's the highest-yield single setting in the processor.

### The audit trail — and why `summary: silent` is usually right

With `summary: debug` or `info`, the processor appends diagnostic attributes:

| Attribute | `info` | `debug` |
|---|:---:|:---:|
| `redaction.redacted.keys` | | ✓ |
| `redaction.redacted.count` | ✓ | ✓ |
| `redaction.masked.keys` | | ✓ |
| `redaction.masked.count` | ✓ | ✓ |
| `redaction.allowed.keys` | | ✓ |
| `redaction.allowed.count` | ✓ | ✓ |
| `redaction.ignored.count` | ✓ | ✓ |

For **log records whose body is a map**, a parallel set is added into the body itself: `redaction.body.redacted.keys`, `redaction.body.redacted.count`, `redaction.body.masked.*`, `redaction.body.allowed.*`, `redaction.body.ignored.count`.

★ **Attributes with a zero count are NOT emitted** — the processor only writes audit attributes when an action actually occurred.

★ **Upstream's own warning about `debug`:** *"In some contexts **a list of redacted attributes leaks information**, while it is valuable when integrating and testing a new configuration."*

**Translation:** `redaction.redacted.keys: "credit_card,internal_id,social_security_number"` **tells an attacker exactly which sensitive fields your application handles.** Use `debug` while building and testing the config; **use `silent` in production**, and if you need audit evidence, emit it as a **count** to your own metrics (`info`) rather than as attribute names into telemetry that flows to a third party.

### Compliance use cases, in upstream's words

> - **GDPR** prohibits transfer of personal data like **birthdates, addresses, or IP addresses across borders** without explicit consent. Popular trace aggregation services are located in the US, not the EU.
> - **PRC legislation** prohibits transfer of **geographic coordinates** outside the PRC.
> - **PCI-DSS** prohibits logging certain things or storing them unencrypted.

★ And the disclaimer, verbatim, which is the most important sentence in the README:

> **"The above is written by an engineer, not a lawyer. The redaction processor is intended as ONE LINE OF DEFENCE rather than the only compliance measure in place."**

**Do not treat a regex list as a compliance programme.** It is a control. Compliance requires knowing *what* personal data you process (*why* it's necessary, *where* it flows, *who* can see it, *how long* you keep it) — which is a records-of-processing exercise, not a Collector config.

---

## 15.3 Where to redact — the layering decision

| Layer | Pros | Cons | Use for |
|---|---|---|---|
| **Application / SDK** | ★ **Data never leaves the process.** Strongest guarantee. Cheapest | Per-service work; needs deploys; easy to forget in new code | **Don't capture it in the first place** — never put secrets in spans, disable header capture by default |
| **Collector agent (per node)** | ★ **Before data leaves the machine** — no egress, no cross-namespace exposure | Runs on every node; config changes need a DaemonSet rollout | Bulk filtering: health-check logs, known-noisy attributes |
| **Collector gateway** | One place, centrally owned, easy to change | ★ **PII already traversed the network and sat in agent memory** | Vendor egress, cross-border flows, policy enforcement, audit |
| **Backend** | Last chance | ★ **Too late for GDPR/PCI** — the data has already been transferred | Retention, access control |

★ **The rule: redact as early as correctness allows, and enforce at the boundary you don't trust.**

In practice that's **both**: prevent capture in the SDK where you can, filter bulk noise in the node agent, and **enforce the policy at the gateway before egress** — because the gateway is the one place you control completely and audit completely. Defence in depth isn't redundancy here; each layer catches what the others structurally cannot.

---

## 15.4 Transport and pipeline security

### TLS on OTLP receivers and exporters
```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
        tls:
          cert_file: /etc/otel/certs/tls.crt
          key_file: /etc/otel/certs/tls.key
          # ★ client_ca_file enables MUTUAL TLS — require client certificates
          client_ca_file: /etc/otel/certs/ca.crt
          min_version: "1.2"
exporters:
  otlp/vendor:
    endpoint: vendor.example.com:4317
    tls:
      ca_file: /etc/otel/certs/vendor-ca.pem
      # cert_file / key_file for mTLS to the vendor
```

| Decision | Guidance |
|---|---|
| **Pod → node agent** | Plaintext is often acceptable — same node, no network traversal. ★ **But if your CNI doesn't encrypt pod-to-pod traffic and pods can reach each other, a compromised pod can sniff telemetry.** In zero-trust environments, use mTLS or a mesh |
| **Agent → gateway** | ★ **TLS. Always.** Crosses nodes |
| **Gateway → vendor / cross-region** | ★ **TLS + auth, non-negotiable.** Consider mTLS if the vendor supports it |
| **Inside a mesh (Istio/Linkerd)** | The mesh gives you mTLS for free — ★ **but verify the Collector's port is actually in the mesh**, and that `load_balancing` DNS resolution still works through the sidecar |

### Authentication extensions — verified stability
| Extension | Stability (v0.161.0) | Use |
|---|---|---|
| **`basicauth`** | **Beta** | Server-side (validate incoming) or client-side (send credentials) |
| **`bearertokenauth`** | **Beta** | ★ **The common path for vendor APIs** — static token in `Authorization: Bearer` |
| **`oauth2client`** | **Beta** | Client-credentials flow; auto-refresh |
| **`oidcauth`** | — | Validating OIDC/JWT tokens from senders — **multi-tenant gateways** |
| **`headers_setter`** | ★ **Alpha** | Inject arbitrary headers |
| **`awsrequest signing` / `sigv4auth`** | — | AWS-native backends |

```yaml
extensions:
  bearertokenauth/vendor:
    token: "${env:VENDOR_API_TOKEN}"       # ★ never inline in a committed config
  oauth2client/vendor:
    client_id: "${env:VENDOR_CLIENT_ID}"
    client_secret: "${env:VENDOR_CLIENT_SECRET}"
    token_url: https://auth.vendor.com/oauth/token
    endpoint_params: {audience: otel-ingest}
exporters:
  otlphttp/vendor:
    endpoint: https://api.vendor.com
    auth:
      authenticator: bearertokenauth/vendor
    # ★ HTTP, not gRPC — proxies, WAFs and LBs handle it correctly
```

★ **Never commit tokens.** Use `${env:VAR}` and inject from your secret store (Vault, External Secrets Operator, cloud KMS). **Note the fail-closed consequence verified above: an unset env var referenced by a validated field prevents startup.** That's a feature — but it means secret rotation is a deploy-risky operation. **Test rotation in staging.**

### Config-level secret handling ★

**Declarative file-based configuration is stable as of 2026** (`OTEL_CONFIG_FILE`), which makes configs a GitOps artefact — **and therefore makes secrets-in-config a Git-history problem.**

Practices:
- Secrets **only** via `${env:VAR}` or a **confmap provider** backed by Vault/S3/GCS: `--config=vault:secret/data/otel#config`
- ★ **Never `--set exporter.token=xyz` on a command line** — it appears in `ps`, shell history, and container specs
- The Collector's **`print-config` subcommand redacts** by default in recent versions — but **verify before you paste output into a ticket**
- Restrict who can edit the CR/ConfigMap: ★ **anyone who can change the Collector config can exfiltrate every request your platform handles**
- Enable **config file watching** carefully — hot reload means a config change is live without a review gate

### Persistent queues and data at rest
```yaml
extensions:
  file_storage:
    directory: /var/lib/otelcol
    create_directory: true      # ★ without this, validate FAILS if the dir doesn't exist
    timeout: 1s
    compaction:
      on_rebound: true
      directory: /var/tmp/otel
      max_transaction_size: 65536
exporters:
  otlp/vendor:
    sending_queue:
      enabled: true
      storage: file_storage     # ★ queue survives restarts
```

★ **Verified error without `create_directory: true` and a missing path:**
`extensions::file_storage: directory must exist: stat /tmp/does-not-exist-xyz: no such file or directory. You can enable the create_directory option to automatically create it`

**Security implications of persistent queues:**
- **Telemetry lands on disk.** If that volume isn't encrypted, you've created an unencrypted store of PII that outlives the process. ★ **Use encrypted volumes** (encrypted EBS/PD, or LUKS).
- **The volume must be access-controlled.** On Kubernetes, a `hostPath` volume is readable by anything with node access. **Prefer a PVC with a storage class that enforces encryption and access controls.**
- **Queue contents survive a compromise.** An attacker with node access reads every buffered span, including whatever your redaction missed.
- **`compaction` on rebound** rewrites the file — the old data may persist in freed blocks until overwritten. ★ For high-assurance environments, that's a real consideration.

### The Collector's own attack surface
| Control | Action |
|---|---|
| **Component minimisation** | ★ **Full contrib has 108 receivers, 48 exporters, 40 extensions.** Every one is attack surface. **Build a custom distribution with OCB** containing only what you use, or use **`otelcol-k8s`** |
| **Bind addresses** | ★ Internal telemetry defaults to **`localhost:8888`**. Binding it to `0.0.0.0` exposes your Collector's own metrics (including config-derived labels) to the pod network. **Bind `0.0.0.0` only if Prometheus must scrape it, and restrict with NetworkPolicy** |
| **`zpages` extension** | Debug endpoints that **show live span data**. ★ **Never enable in production** without network restriction |
| **`pprof`** | Same — exposes heap contents |
| **`debug` exporter** | ★ `verbosity: detailed` **logs span/log content to stdout**, where it lands in your log store unredacted. **The single easiest accidental PII leak.** Never in production |
| **Image provenance** | Pin by **digest**, use signed images, scan in CI |
| **RunAsNonRoot / readOnlyRootFilesystem / drop capabilities** | Standard pod hardening — ★ note `readOnlyRootFilesystem` conflicts with `file_storage`; mount a writable volume at that path only |
| **NetworkPolicy** | ★ **Restrict who can send to the Collector.** An open OTLP port lets any pod in the cluster inject arbitrary telemetry — including **fabricated metrics that trigger your alerts** and **cardinality bombs that destroy your budget** |
| **RBAC for `k8s_attributes`** | It needs pod/namespace read. **Scope with `filter.namespace` and `filter.node_from_env_var`** to the minimum |

★ **Two attack modes that aren't data leaks and get overlooked:**
- **Telemetry injection.** An unauthenticated OTLP endpoint lets an attacker fabricate spans and metrics. Fabricated `up == 0` alerts cause real incidents; fabricated high-cardinality metrics cause real bills.
- **Denial of observability.** Overload the Collector and you blind the team **during** an incident — which is exactly when an attacker would choose to do it. **Rate-limit and authenticate ingestion in multi-tenant environments.**

### Multi-tenancy
| Need | Mechanism |
|---|---|
| Identify the sender | ★ **`oidcauth`** extension validating a JWT per request; or `headers_setter`/`bearertokenauth` with per-tenant tokens |
| Route by tenant | `routing` connector on a tenant attribute/header |
| Isolate storage | Backend-native tenancy (Mimir `X-Scope-OrgID`, vendor accounts) |
| Attribute tenant identity | `resource` processor adding `tenant.id` — ★ **do this at the gateway after authentication, not from client-supplied data.** A client that sets its own `tenant.id` can write into another tenant's space |
| Quotas | `ratelimit` processor per tenant |

---

## 15.5 Privacy engineering — the parts regexes don't cover

| Principle | Practice |
|---|---|
| **Data minimisation** | ★ **The only reliable control.** Don't capture request bodies, don't capture all headers, don't put user identifiers in span attributes. **A field you never collected cannot leak** |
| **Purpose limitation** | Write down *why* each attribute exists. "Useful" is not a purpose |
| **Pseudonymisation** | Hash stable identifiers with **HMAC and a secret key** so you can correlate without identifying. ★ **Rotate the key periodically** and accept that correlation breaks across rotation |
| **Retention limitation** | Shortest period that serves the purpose — and remember the compliance floor ([`13-backends.md`](13-backends.md)) |
| **Access control** | ★ **Who can query traces?** Trace stores contain request paths, parameters, and errors — effectively a record of user behaviour. **Treat query access as sensitive-data access**, with logging and review |
| **Cross-border transfer** | ★ **Know where your backend physically stores data.** GDPR transfer of IP addresses and birthdates requires a legal basis; **PRC prohibits geographic-coordinate export.** A US-region vendor endpoint may be a compliance problem regardless of redaction quality |
| **DSAR / deletion** | "Erase this user's data" must reach **traces, logs, metrics and profiles**. ★ **Object-storage-backed systems make targeted deletion genuinely hard** — plan for it at design time (short retention is the usual answer) |
| **DPIA** | If you're profiling users or processing at scale, a Data Protection Impact Assessment is likely required. **Observability rollouts frequently trigger one and frequently skip it** |

★ **The uncomfortable truth about trace data:** a trace store is a **behavioural record of your users** — which pages they visited, what they searched for, what failed, when. It is often *more* revealing than your product database, because it captures attempts and errors, not just committed state. **Govern it accordingly.** Most organisations don't.

---

## 15.6 Governance — making the rules stick

### The policy set worth writing down
1. **Default-off for verbose capture.** Header capture, request/response body capture, SQL statement capture, and DEBUG logging are **disabled by default** and require an explicit, reviewed exception.
2. **Attribute allowlists for metrics; volume controls for traces and logs.** Different signals, different levers ([`14-scale-cost-and-cardinality.md`](14-scale-cost-and-cardinality.md)).
3. **No high-cardinality identifiers on metrics.** `user_id`, `order_id`, `session_id`, `trace_id`, IP addresses — **prohibited**. Permitted on spans and logs with redaction.
4. **Every exported metric attribute needs a cardinality estimate at review time.** One question: *"how many distinct values, and does that grow with users?"*
5. **Redaction enforced at the gateway before external egress.** Not optional, not per-team.
6. **Secrets only via `${env:}` or a confmap provider.** Never inline, never `--set` on a command line.
7. **No `debug` exporter or `zpages`/`pprof` in production** without a time-boxed, network-restricted exception.
8. **Ingestion endpoints authenticated and NetworkPolicy-restricted** outside the node-local hop.
9. **Every alert has a runbook; every dashboard has an owner.** Unowned means deleted at the next review.
10. **Retention reviewed quarterly, against documented compliance requirements.**
11. **Sampling policy reviewed with incident response**, because it's a reliability decision.
12. **Collector config changes go through the same review as code** — ★ anyone who can edit it can exfiltrate or fabricate.

### The operating cadence
| Cadence | Activity |
|---|---|
| **Per PR** | Cost/cardinality estimate for new attributes; check for accidental PII in new instrumentation |
| **Monthly** | **Showback** per team; review `processor_cardinality_top.offenders`; review redaction `masked.count` trends |
| **Quarterly** | Retention review; access review for trace/log query; sampling policy review; dependency and CVE scan of Collector images |
| **Annually / on change** | DPIA refresh; data-flow map; cross-border transfer review; incident-response runbook test |

### The data-flow map ★
The single most useful governance artefact, and the one almost nobody has. For each signal, record:

```
signal: traces
  source:        app pods (auto-instrumented + manual spans)
  captured:      span name, duration, http.*, db.*, exception.type/message/stacktrace
  pii present:   user_id (span attr), IP (net.peer.ip), exception messages MAY contain PII
  hop 1:         node agent DaemonSet  (plaintext, same node)
  hop 2:         gateway Deployment    (TLS, cross-node)
  redaction:     redaction processor at gateway — allowed_keys + blocked_values + url_sanitizer
  egress:        vendor OTLP/HTTPS, EU region, mTLS
  storage:       vendor, 14-day retention, EU data residency
  access:        SRE + service owners, SSO, query logged
  legal basis:   legitimate interest; DPIA ref 2026-04-otel
```
**Writing this down is where you discover the problems** — the hop you thought was TLS but isn't, the exception message that carries a customer email, the vendor region that's in the US. ★ **You cannot govern what you haven't mapped, and mapping takes an afternoon.**

---

## Red flags

| Doing this | Costs you |
|---|---|
| `OTEL_INSTRUMENTATION_HTTP_CAPTURE_HEADERS=all` without review | ★ **`Authorization`, `Cookie`, `X-Api-Key` straight into your trace store** |
| Leaving `allowed_keys` empty with `allow_all_keys: false` | **Every attribute stripped** — you get empty spans, not scrubbed ones |
| Setting `allow_all_keys: true` and relying only on value patterns | ★ **Fails open** — an unanticipated attribute name passes through unredacted |
| Unsalted MD5/SHA-256 on IP addresses | ★ **Trivially reversible** — only ~4 billion IPv4 addresses. Use HMAC with a secret key |
| `hmac_key` shorter than 32 bytes (sha256) / 64 bytes (sha512) | **Collector fails to start** with an explicit error |
| `${env:REDACTION_SECRET_KEY}` unset during rotation | ★ **Fail-closed: the Collector won't start.** Test rotation in staging |
| `summary: debug` in production | ★ **`redaction.redacted.keys` tells an attacker exactly which sensitive fields you handle** |
| Relying on the redaction processor as your compliance programme | Upstream says it outright: *"one line of defence rather than the only compliance measure"* |
| Redacting only at the gateway | PII already crossed the network and sat in agent memory — **also redact in the SDK where you can** |
| Redacting only in the SDK | New services and new instrumentation versions will miss it — **also enforce at the egress boundary** |
| `debug` exporter at `verbosity: detailed` in production | ★ **The easiest accidental PII leak** — unredacted content into your log store |
| `zpages`/`pprof` enabled in production | Exposes live span data and heap contents |
| Full contrib in every Collector | ★ **108 receivers + 48 exporters + 40 extensions** of attack surface. Use OCB or `otelcol-k8s` |
| Open OTLP port with no NetworkPolicy | ★ Any pod can **inject fabricated metrics** (fake alerts) or a **cardinality bomb** (real bills) |
| Trusting client-supplied `tenant.id` | A client writes into another tenant's space. Set it at the gateway **after** authentication |
| `file_storage` on an unencrypted volume | An unencrypted on-disk store of PII that outlives the process |
| `file_storage` without `create_directory: true` on a fresh path | ★ **Validation fails at startup** |
| `--set exporter.token=...` on a command line | Visible in `ps`, shell history, and container specs |
| Binding internal telemetry to `0.0.0.0` without a NetworkPolicy | Your Collector's own metrics exposed to the pod network |
| No data-flow map | ★ **You can't govern what you haven't mapped** — and mapping takes an afternoon |
| No access review on trace/log query | Traces are a **behavioural record of your users**, often more revealing than your product DB |
| Assuming short retention solves DSAR deletion | Object-storage backends make **targeted** deletion genuinely hard — plan at design time |

---

## Rapid recall

1. **Telemetry is a data-processing system subject to the same controls as your product database** — and usually governed far less. It's collected **by default**, **crosses trust boundaries**, has a **long tail**, and the pipeline itself is **privileged**.
2. ★ **A single flag — `OTEL_INSTRUMENTATION_HTTP_CAPTURE_HEADERS=all` — copies every HTTP header (`Authorization`, `Cookie`, `X-Api-Key`) into your traces.** Default-off for verbose capture is policy item #1.
3. **`redaction` processor stability in v0.161.0: `traces: Beta`, ★ `logs: Alpha`, `metrics: Alpha`** (contrib + k8s distributions). If your PII exposure is in log bodies, you're on Alpha — **test against real data**.
4. ★ **`allowed_keys` fails CLOSED; `allow_all_keys: true` fails OPEN.** Empty `allowed_keys` removes **all** attributes (you get empty spans, not scrubbed ones). `allow_all_keys: true` means an unanticipated attribute name passes through unredacted. **Choose deliberately.**
5. **Processing order:** `ignored_keys` (first, untouched) → `allowed_keys` (removal) → `blocked_key_patterns` (masking) → `allowed_values` (**takes precedence**) → `blocked_values` (**applied in listed order**; overlapping patterns — first match wins). ★ A key removed at step 2 **never reaches** the value checks.
6. `redact_all_types: true` inspects the `AsString()` representation so you can redact sensitive data **stored as integers** (e.g. a numeric credit card). Off by default.
7. ★ **HMAC, not plain hashing, for low-entropy data.** An unsalted SHA-256 of an IPv4 address is **trivially reversible** (~4 billion possibilities). `hmac-sha256` needs a **≥32-byte** key, `hmac-sha512` **≥64 bytes** — **verified by `validate`**. **An unset `hmac_key` env var makes the Collector fail to start** (fail-closed — good, but makes secret rotation a deploy risk).
8. ★ **`url_sanitizer` fixes privacy and cardinality at once:** `/users/<uuid>/orders/<id>` → `/users/*/orders/*`, and by default also sanitises **client/server span names containing `/`**. **If you have REST APIs with IDs in paths, enable it — highest-yield setting in the processor.**
9. ★ **`summary: silent` in production.** Upstream: *"a list of redacted attributes leaks information."* `redaction.redacted.keys: "credit_card,social_security_number"` tells an attacker exactly what you handle. Use `debug` while building the config; audit via **counts** (`info`) rather than names. Zero-count attributes aren't emitted.
10. **Upstream's own disclaimer, verbatim:** *"The above is written by an engineer, not a lawyer. The redaction processor is intended as **one line of defence** rather than the only compliance measure in place."* **A regex list is not a compliance programme.**
11. **Where to redact: as early as correctness allows, and enforce at the boundary you don't trust.** SDK (data never leaves the process — strongest) **and** node agent (before egress) **and** ★ **gateway (the one place you fully control and audit)**. Backend is too late for GDPR/PCI. **Defence in depth here isn't redundancy** — each layer catches what others structurally cannot.
12. **TLS: pod→node agent** plaintext is often fine (but check CNI encryption and pod-to-pod reachability); ★ **agent→gateway always**; **gateway→vendor always + auth**. ★ **Use OTLP/HTTP, not gRPC, to vendors** — proxies, WAFs and LBs handle it correctly.
13. **Auth extensions:** `basicauth` Beta, `bearertokenauth` Beta (the common vendor path), `oauth2client` Beta, `oidcauth` for multi-tenant gateways, ★ **`headers_setter` Alpha**.
14. ★ **Never commit secrets and never `--set` them on a command line** (visible in `ps`, shell history, container specs). Use `${env:}` or a confmap provider. **Declarative file config is stable since 2026**, making configs a GitOps artefact — and therefore secrets-in-config a **Git-history** problem. **Anyone who can edit the Collector config can exfiltrate every request your platform handles.**
15. **Persistent queues put telemetry on disk.** ★ Use **encrypted volumes**, prefer a PVC over `hostPath`, and remember queue contents **survive a compromise**. `file_storage` **fails validation if the directory doesn't exist** unless `create_directory: true`.
16. **Minimise the attack surface:** full contrib is **108 receivers + 48 exporters + 40 extensions** — build with **OCB** or use **`otelcol-k8s`**. ★ **Never `debug` at `verbosity: detailed`, `zpages`, or `pprof` in production.** Bind internal telemetry to `0.0.0.0:8888` only when Prometheus must scrape it, and restrict with NetworkPolicy.
17. ★ **Two overlooked attack modes:** **telemetry injection** (an open OTLP port lets any pod fabricate metrics → fake alerts → real incidents, or a **cardinality bomb** → real bills) and **denial of observability** (overload the Collector to blind the team *during* an incident — exactly when an attacker would choose). **Authenticate and rate-limit ingestion; NetworkPolicy the endpoints.**
18. **Multi-tenancy:** `oidcauth` to identify senders, `routing` connector to route, backend-native tenancy to isolate — and ★ **set `tenant.id` at the gateway AFTER authentication**, never from client-supplied data.
19. **Privacy beyond regexes:** **data minimisation is the only reliable control** (a field you never collected cannot leak); purpose limitation; HMAC pseudonymisation with **periodic key rotation**; retention limits; ★ **treat trace-query access as sensitive-data access** (traces are a behavioural record of your users, often more revealing than your product DB because they capture attempts and errors); **know where your backend physically stores data** (GDPR transfers, PRC geographic-coordinate export ban); **DSAR deletion reaches all four signals** and is genuinely hard on object storage; **observability rollouts frequently trigger a DPIA and frequently skip it**.
20. **Governance artefact that matters most: the data-flow map** — source, what's captured, PII present, every hop and its encryption, where redaction happens, egress destination and region, retention, access, legal basis. ★ **You cannot govern what you haven't mapped, and mapping takes an afternoon.** Cadence: per-PR cardinality check, monthly showback + top-offenders review, quarterly retention/access/sampling/CVE review, annual DPIA and data-flow refresh.

→ Next: [`16-troubleshooting.md`](16-troubleshooting.md)
