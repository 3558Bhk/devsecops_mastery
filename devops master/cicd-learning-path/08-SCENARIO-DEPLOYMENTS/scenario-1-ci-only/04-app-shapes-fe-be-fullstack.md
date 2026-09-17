# 🧩 SCENARIO 1 · THE FOUR APPLICATION SHAPES
### Frontend only · Backend only · FE + BE · FE + BE in different languages — the CI differences that actually matter, independent of which tool you use.

> **This is the file to read if you only read one.** The three tool files are *parallel*: they express the same ten-step CI shape in GitHub Actions YAML, Azure DevOps YAML, and Jenkins Groovy. This file is *orthogonal* — it explains what changes when the **application** changes, which is the axis that actually determines your pipeline's structure.
>
> **Tool-independent.** Every snippet here is Dockerfile, shell, or pseudocode. Port it to whichever tool you have using [`01`](./01-github-actions-ci.md) / [`02`](./02-azure-devops-ci.md) / [`03`](./03-jenkins-ci.md).

---

## 📇 Contents

| § | What |
|---|---|
| [1](#1--the-universal-ci-shape) | The universal CI shape — what is identical for all four |
| [2](#2---shape-a--frontend-only) | 🔵 **Shape A — FE only** (`shop-ui`, Docker P8 / K8s P8, and P2's static site) |
| [3](#3---shape-b--backend-only) | 🟢 **Shape B — BE only** (`shop-api`, `checkout`, `order-worker`, `payment-mock`) |
| [4](#4---shape-c--fe--be-one-stack) | 🟡 **Shape C — FE + BE, one stack** (Docker P10 / K8s P10, React + Java) |
| [5](#5---shape-d--fe--be-different-languages) | 🟠 **Shape D — FE + BE, different languages** (P11 React+Python, P12 React+Go) |
| [6](#6---the-comparison-table) | ⭐ The comparison table — everything on one page |
| [7](#7---the-contract-test--the-only-thing-that-makes-c-and-d-safe) | ⭐⭐ The contract test — the only thing that makes C and D safe |
| [8](#8--deciding-one-pipeline-or-many) | Deciding: one pipeline or many? |
| [9](#9---the-four-things-that-never-differ) | ⭐ The four things that never differ, whatever the shape |
| [10](#10---tasks--answers-at-the-end) | Tasks and answers — **answers at the END** |

---

## 1 · The universal CI shape

**Identical for all four shapes, all three tools, all four languages:**

```
trigger (path-filtered) → checkout → setup toolchain → restore cache
   → install deps → test → static analysis → build IMAGE (multi-stage)
   → scan the IMAGE → sign → push → ⭐⭐ emit the digest → STOP
```

⭐ **Only three things vary with language**, and they are the *first three* steps:

| # | Varies | React/Node | Java | Go | Python |
|---|---|---|---|---|---|
| 1 | dependency install + cache key | `npm ci` · `package-lock.json` | `mvnw dependency:go-offline` · `pom.xml` | `go mod download` · `go.sum` | `uv sync --frozen` · `uv.lock` |
| 2 | build + test command | `npm run build` · `vitest` | `mvnw -B verify` | `go build` · `go test -race` | `pytest` |
| 3 | runtime base image | `nginx:1.29-alpine` ~50 MB | `temurin:21-jre-alpine` ~230 MB | ⭐ `scratch` ~10 MB | `python:3.13-slim` ~120 MB |

**Everything after step 3 is the same.** That is why this folder has four tool files and one shapes file, rather than sixteen files.

---

## 2 · 🔵 Shape A — Frontend only

**Apps:** `shop-ui` (Docker P8 · K8s P8) · `static-site` (Docker P2)

### 2.1 What makes the frontend different

| Property | Value | Consequence for CI |
|---|---|---|
| Build output | ⭐ **static files**, not a running process | the "artifact" is a directory, then an nginx image wrapping it |
| Test types | unit (Vitest) · a11y · ⭐ **Lighthouse** · ⭐ **bundle size** | two gates that have no backend analogue |
| Build time | 30–90 s | ⭐ fast enough to run on every push to every branch |
| Config | ⚠️ **baked at build time** (`import.meta.env.VITE_*`) | ⭐⭐ the trap in §2.3 |
| Deploy risk | ⭐ **low** — no state, no schema, instant rollback | the risk is **browser caching**, not the server |
| Runtime deps | none (nginx serves files) | the smallest attack surface in the whole estate |

### 2.2 The two frontend-only gates

```bash
# ── GATE 1: bundle size ────────────────────────────────────────────────
# ⭐ WHY: a frontend regression is usually a SIZE regression, and it is
#   invisible to unit tests. Somebody adds a 400 KB date library and every
#   test still passes.
SIZE=$(du -sk dist | cut -f1)
BUDGET=450            # KiB — set it from TODAY's value, then ratchet down
echo "dist = ${SIZE} KiB (budget ${BUDGET} KiB)"
[ "$SIZE" -le "$BUDGET" ] || { echo "::error::bundle over budget"; exit 1; }

# ⭐ BETTER: per-chunk budgets via Lighthouse CI, which catches a 50 KB
#   regression in the critical path even when the total is flat.
npx @lhci/cli autorun --collect.url=http://localhost:4173 \
  --assert.assertions='{"resource-summary:script:size":["error",{"maxNumericValue":307200}]}'

# ── GATE 2: Lighthouse ─────────────────────────────────────────────────
npx @lhci/cli autorun \
  --collect.url=http://localhost:4173 \
  --collect.numberOfRuns=3 \
  --assert.preset=lighthouse:no-pwa \
  --assert.assertions='{"categories:performance":["error",{"minScore":0.9}],
                        "categories:accessibility":["error",{"minScore":0.95}]}'
# ⭐ numberOfRuns=3 and take the MEDIAN. A single Lighthouse run on a shared
#   CI runner has ±10 points of noise. Gating on one run produces flaky
#   failures, and a flaky gate gets disabled — which is worse than no gate.
```

### 2.3 ⭐⭐ THE FRONTEND TRAP: build-time config

```dockerfile
# ⛔ THE WRONG DOCKERFILE — this looks completely reasonable
FROM node:24-alpine AS build
ARG VITE_API_URL                      # ⚠️ baked in at BUILD time
ENV VITE_API_URL=$VITE_API_URL
WORKDIR /app
COPY . .
RUN npm ci && npm run build           # ⭐ Vite INLINES VITE_API_URL into the
                                      #   emitted JS. It is now a string
                                      #   literal inside a .js file.
FROM nginx:1.29-alpine
COPY --from=build /app/dist /usr/share/nginx/html
```

**What that costs you:** one image per environment. `VITE_API_URL=https://api.dev.shop` and `VITE_API_URL=https://api.shop` produce **different bytes** — so the artifact you tested in staging is *not* the artifact you ship to production.

> ⛔ That breaks the digest contract this entire folder exists to enforce, and it does so silently: everything still works, every pipeline is still green, and you have simply lost the guarantee.

```dockerfile
# ✅ THE RIGHT DOCKERFILE — config injected at RUNTIME
FROM node:24-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build                    # ⭐ no API URL baked in

FROM nginx:1.29-alpine
COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
# ⭐⭐ the entrypoint generates a config file the browser fetches at load time
COPY docker-entrypoint.sh /docker-entrypoint.d/40-inject-config.sh
RUN chmod +x /docker-entrypoint.d/40-inject-config.sh
EXPOSE 80
```

```bash
#!/bin/sh
# docker-entrypoint.d/40-inject-config.sh
# ⭐ nginx's official image runs every script in /docker-entrypoint.d/ at
#   container start, BEFORE nginx starts. That is the hook.
set -eu
cat > /usr/share/nginx/html/config.js <<EOF
window.__APP_CONFIG__ = {
  API_URL: "${API_URL:-http://localhost:8080}",
  ENV:     "${APP_ENV:-dev}",
  BUILD:   "${GIT_SHA:-unknown}"
};
EOF
echo "✅ injected API_URL=${API_URL:-http://localhost:8080}"
```

```html
<!-- index.html — ⭐ BEFORE the bundle, so the config exists when it runs -->
<script src="/config.js"></script>
<script type="module" src="/assets/index-abc123.js"></script>
```

```ts
// src/config.ts — the ONE place the app reads runtime config
export const config = {
  apiUrl: (window as any).__APP_CONFIG__?.API_URL ?? import.meta.env.VITE_API_URL,
  env:    (window as any).__APP_CONFIG__?.ENV ?? 'dev',
};
// ⭐ the `?? import.meta.env` fallback keeps local `npm run dev` working
//   without an nginx container.
```

**Result: one image, digest-pinned, deployed unchanged to dev → staging → prod**, with the API URL supplied as an environment variable per deployment. That is the property Scenario 2 depends on.

### 2.4 ⭐ The other frontend-only CI concern: cache busting

| File | Cache policy | Why |
|---|---|---|
| `index.html` | ⭐ **`no-cache`** (revalidate every time) | it is the *entry point*; if the browser caches it, it loads **old asset URLs** |
| `/assets/index-<hash>.js` | ⭐ `immutable, max-age=31536000` | the filename contains a content hash, so it can never change meaning |
| `/config.js` | ⭐ `no-store` | runtime config must be fresh on every load |

```nginx
location = /index.html { add_header Cache-Control "no-cache, must-revalidate"; }
location = /config.js  { add_header Cache-Control "no-store"; }
location /assets/      { add_header Cache-Control "public, max-age=31536000, immutable"; }
```

⛔ **The incident this prevents:** a deploy succeeds, the new image is live, and users see a blank page or `Uncaught TypeError: t.default is not a function` — because their browser cached the old `index.html`, which references asset filenames that no longer exist. It resolves itself on a hard refresh, which is why it is reported as "works for me" and never fixed. **`no-cache` on `index.html` is not optional.**

---

## 3 · 🟢 Shape B — Backend only

**Apps:** `shop-api` (Java, P9) · `checkout` (Go, P12) · `order-worker` (Python, P11) · `payment-mock` (Go)

### 3.1 What makes the backend different

| Property | Consequence for CI |
|---|---|
| ⭐ **It has state — a schema** | CI must verify **migrations**, not just code |
| ⭐ **It has dependencies — a database, a queue** | tests need real infrastructure: **Testcontainers** |
| Build time is minutes, not seconds | ⭐ caching is not optional; it is the difference between a usable and an unusable pipeline |
| Runtime config is env-driven | ✅ **no build-time trap** — unlike shape A |
| Deploy risk is high | ⭐ warmup, connection pools, in-flight requests, migrations |

### 3.2 ⭐ Testcontainers — the gate that makes backend CI mean anything

```java
// ⛔ THE WEAK VERSION: H2 in "Postgres compatibility mode".
//   It is not Postgres. It does not enforce the same constraints, does not
//   have the same types (no real JSONB, no arrays), does not fail on the same
//   SQL. Tests that pass on H2 regularly fail in production — so the gate is
//   decorative, and worse, it is CONFIDENTLY decorative.
@DataJpaTest
@AutoConfigureTestDatabase(replace = NONE)   // with an H2 datasource

// ✅ THE REAL VERSION: an actual Postgres 17, started per test class.
@Testcontainers
@SpringBootTest
class OrderRepositoryIT {
    @Container
    static PostgreSQLContainer<?> PG = new PostgreSQLContainer<>(
        "postgres:17.7"                       // ⭐ pin the version. Ideally
    );                                        //   pin the DIGEST, or your
                                              //   tests change behaviour when
                                              //   Postgres publishes a patch.
    @DynamicPropertySource
    static void props(DynamicPropertyRegistry r) {
        r.add("spring.datasource.url", PG::getJdbcUrl);
        r.add("spring.datasource.username", PG::getUsername);
        r.add("spring.datasource.password", PG::getPassword);
    }
    // ⭐ `static` + `@Container` = ONE container for the whole class, not one
    //   per test. Per-test containers cost ~2 s each and dominate the runtime.
}
```

| Concern | Answer |
|---|---|
| Where does the daemon come from? | 🐙 GitHub-hosted runners **have one**. 🔷 `vmImage` agents **have one**. 🔨 Kubernetes agents **do not** — use a sidecar Postgres or Testcontainers Cloud |
| Is it slow? | ⭐ The first container costs ~2–4 s; reuse across the class makes it cheap. A full IT suite: 30–90 s |
| ⛔ Never do this | mount `/var/run/docker.sock` into a CI agent to "fix" it. That is root on the host |
| Ryuk failing? | `TESTCONTAINERS_RYUK_DISABLED=true` — accept that cleanup happens by agent teardown |

### 3.3 ⭐ Migrations are a CI concern, not just a CD concern

```
CI must prove, on every commit:
  1. the migration SQL PARSES            → flyway validate
  2. it APPLIES to a real empty DB       → Testcontainers + flyway migrate
  3. ⭐ it applies to a COPY OF PRODUCTION'S SCHEMA
                                          → migrate against a restored dump
  4. the code works AFTER the migration  → run the integration tests
  5. ⭐ the migration is REVERSIBLE, or explicitly marked as not
```

⭐⭐ **Check 3 is the one everybody skips, and it is the one that causes the incident.** A migration that applies cleanly to an empty database can fail on a 40-million-row production table — because of a lock timeout, a NOT NULL constraint on existing rows, or a unique index build that takes 20 minutes. `flyway validate` and a clean-DB test cannot see any of that.

```bash
# the shape of the check, in CI:
psql "$CI_DB_URL" -c "CREATE DATABASE shadow TEMPLATE prod_snapshot;"
flyway -url=jdbc:postgresql://ci-db:5432/shadow -locations=classpath:db/migration migrate
# ⭐ fails on: a NOT NULL added to a column with existing nulls, a unique
#   index over duplicated data, a lock that would time out at scale.
```

### 3.4 The four backends, side by side

| | `shop-api` (Java) | `checkout` (Go) | `order-worker` (Python) | `payment-mock` (Go) |
|---|---|---|---|---|
| Build | `mvnw -B -ntp verify` | `go build -trimpath -ldflags="-s -w"` | `uv sync --frozen` | `go build` |
| Test | Surefire + ⭐ Failsafe ITs | `go test -race -count=1 ./...` | `pytest --cov-fail-under=80` | `go test ./...` |
| Infra needed | ⭐ Postgres 17 (Testcontainers) | Postgres + Redis | ⭐ RabbitMQ | none |
| Lint | SpotBugs / ErrorProne | `go vet`, `golangci-lint` | `ruff`, `mypy` | `go vet` |
| CVE scan | `dependency-check`, Trivy | ⭐ `govulncheck` | ⭐ `pip-audit` | `govulncheck` |
| Image | ~230 MB | ⭐ ~10 MB (`scratch`) | ~120 MB (`slim`) | ~10 MB |
| Cold build | 4–8 min | ~40 s | ~60 s | ~40 s |
| Warm build | ⭐ 60–90 s | ~15 s | ~20 s | ~15 s |
| Health endpoint | `/actuator/health/readiness` | `/readyz` | ⭐ **none — a heartbeat** | `/healthz` |
| Migration | ⭐ Flyway | none | Alembic | none |
| Deploy risk | ⭐⭐⭐ highest | low | ⭐⭐ medium (in-flight work) | ⭐ lowest → **canary here** |

⭐ **Two of those cells are the interesting ones:**
- `order-worker` has **no health endpoint** because it is a queue consumer. Its readiness is "connected to the broker and not paused" — a heartbeat file or a pushed metric, not an HTTP probe. See [`../00-PROJECT-INVENTORY.md`](../00-PROJECT-INVENTORY.md) §6.4.
- `payment-mock` has the **lowest deploy risk** in the estate, which makes it the correct **first canary target** when you move to Scenario 2 Case 2. Prove your progressive-delivery machinery on the service where being wrong costs nothing.

---

## 4 · 🟡 Shape C — FE + BE, one stack

**Apps:** Docker P10 / K8s P10 — `shop-ui` (React) + `shop-api` (Java)

### 4.1 The structural question: one pipeline or two?

```
OPTION 1 — TWO PIPELINES (independent)
   apps/shop-ui/**  → ci-shop-ui  → digest-ui
   apps/shop-api/** → ci-shop-api → digest-api
   ⭐ fastest feedback, smallest blast radius
   ⛔ CANNOT guarantee FE and BE are deployed as a compatible PAIR

OPTION 2 — ONE PIPELINE, TWO ARTIFACTS (a release train)
   any change → ci-monorepo → { digest-ui, digest-api } → ONE manifest
   ⭐ the manifest is an ATOMIC, COMPATIBLE PAIR
   ⛔ slower: a CSS typo rebuilds and re-tests the Java service

OPTION 3 — ⭐ TWO CI PIPELINES + ONE MANIFEST JOB  (the answer)
   ci-shop-ui  → digest-ui  ─┐
                             ├→ manifest job → ONE atomic manifest
   ci-shop-api → digest-api ─┘
   ✅ fast per-service feedback AND an atomic pair
   ⚠️ needs a "which digests go together?" rule — §4.3
```

### 4.2 ⭐⭐ The version-skew problem

**The failure mode, concretely:**

```
t0  FE v1 calls GET /api/v1/orders         BE v1 serves it          ✅
t1                                        BE v2 REMOVES /api/v1/orders
t2  FE v1 (still in browsers, cached)  ──▶ BE v2                    ⛔ 404
t3  FE v2 deployed                        BE v2                    ✅
    ⭐ BETWEEN t1 AND t3 EVERY ACTIVE USER IS BROKEN.
       And t2's duration is controlled by BROWSER CACHE, not by you.
```

**The four defences — you need all of them, and they are ordered by importance:**

| # | Defence | What it means | Where it lives |
|---|---|---|---|
| **1** | ⭐⭐ **Expand / contract** (parallel change) | BE **adds** the new endpoint and **keeps** the old one. FE migrates. A **later** release removes the old one. **No single deploy is ever breaking** | the API design, enforced in review |
| **2** | ⭐ **Deploy order: BE first, then FE** | the backend must be able to serve *both* the old and new frontend at all times. The reverse order guarantees a window of breakage | the CD pipeline (Scenario 2/3) |
| **3** | ⭐ **API versioning in the path** | `/api/v1/…`, `/api/v2/…`. Two versions served concurrently | the API design |
| **4** | **A consumer-driven contract test** | CI proves the FE's *actual* expectations against the BE's *actual* responses, before either is deployed | §7 |

```
✅ THE EXPAND/CONTRACT SEQUENCE — three separate, independently safe releases

RELEASE 1 (BE)   add   GET /api/v2/orders      keep /api/v1/orders
                 → old FE works, new FE would work. NOTHING BREAKS.
RELEASE 2 (FE)   switch the frontend to /api/v2/orders
                 → v1 is now unused but still served. NOTHING BREAKS.
RELEASE 3 (BE)   remove /api/v1/orders         ← only after telemetry
                 → confirms zero v1 traffic.
                 ⭐ AND IT IS STILL REVERSIBLE: revert release 2 first.

⛔ THE SINGLE-RELEASE VERSION:
   ONE PR that changes the endpoint in the BE and the call in the FE.
   It looks CLEANER. It is not deployable without a breaking window,
   because the two halves roll out over minutes (or hours, via browser
   cache) and never atomically.
```

⭐ **Defence 1 is a design discipline, not a pipeline feature.** No CI system can save you from a breaking change deployed atomically. This is why "the backend team and frontend team must coordinate releases" is a *smell* — with expand/contract they never have to.

### 4.3 The manifest that makes the pair atomic

```text
# release-manifest.txt — ⭐ ONE file, ONE atomic compatible pair
# release 2026.09.16-1
# contract-version 2        ← ⭐⭐ the field that makes skew detectable
shop-ui=ghcr.io/3558bhk/shop-ui@sha256:9f2c…
shop-api=ghcr.io/3558bhk/shop-api@sha256:41ab…
```

⭐ **`contract-version` is the mechanism.** Both sides declare the API contract version they were built against:
- the BE publishes `/api/contract-version` → `2`
- the FE is built with `CONTRACT_VERSION=2` and checks it at startup
- a mismatch logs an error and (optionally) shows "please refresh" instead of a wall of 404s

That converts a silent, confusing failure into a **detected** one — which is the most you can achieve, since you cannot make two independently-deployed artifacts change atomically.

---

## 5 · 🟠 Shape D — FE + BE, different languages

**Apps:** Docker P11 / K8s P11 (React + Python/FastAPI) · Docker P12 / K8s P12 (React + Go) · plus `payment-mock`

### 5.1 What actually gets harder — and it is not the languages

⭐⭐ **The common belief is that polyglot means "four times the work". It does not.** Because of §1 — only three things vary per language — adding a fourth language adds one more column to a table, not a fourth pipeline design.

**What genuinely gets harder:**

| Real difficulty | Why | Mitigation |
|---|---|---|
| ⭐ **Toolchain drift** | four ecosystems, four update cadences, four CVE streams. `npm audit`, Dependabot, `govulncheck` and `pip-audit` each report differently | one normalised scan step; one place that aggregates |
| ⭐ **Cache pressure** | four dependency caches. On a 10 GB cache quota (GitHub `type=gha`, Azure `Cache@2`) they evict each other | per-service cache **scope**; drop caching for the fast-building services (Go) |
| ⭐ **Agent heterogeneity** | Jenkins needs four containers per pod; GitHub needs four `setup-*` actions | a **matrix** over services, or a per-service job with the right container |
| ⭐⭐ **Contract drift** | FE↔BE skew is now across *ecosystems*, so you cannot share types | §7 — a language-neutral contract (OpenAPI) |
| **Build-time variance** | Java 6 min, Go 15 s. A single pipeline is as slow as its slowest service | ⭐ **parallel stages**, and path filters so unchanged services do not build |
| **Different failure semantics** | Go fails to compile; Python fails at import; Java fails at startup; React fails in the browser | ⭐ smoke-test each service the way *it* fails |

### 5.2 ⭐ The matrix pattern — one job definition, four services

```
services:
  - { name: shop-ui,      context: apps/shop-ui,      lang: node   }
  - { name: shop-api,     context: apps/shop-api,     lang: java   }
  - { name: checkout,     context: apps/checkout,     lang: go     }
  - { name: order-worker, context: apps/order-worker, lang: python }

for each service, IN PARALLEL:
  setup(lang) → install(lang) → test(lang) → build image → scan → push
                                                                    │
                                       ◀────────────────────────────┘
                          collect all digests → ONE manifest
```

| Tool | How |
|---|---|
| 🐙 GitHub Actions | `strategy: matrix: service: [...]` calling a reusable workflow, plus a `needs: [matrix-job]` collector |
| 🔷 Azure DevOps | ⛔ templates cannot loop at compile time over a runtime list — write five `template:` blocks, or use `${{ each }}` over a **parameter** array (compile-time, so it works) |
| 🔨 Jenkins | `parallel { }` with a `script { for (svc in services) { … } }` generating the branches |

⭐ **`fail-fast: false` everywhere.** The default in most tools is to cancel siblings on the first failure. For a polyglot monorepo that is wrong: you want to know that `shop-api` **and** `order-worker` both broke, in one run, not discover them one at a time over three commits.

### 5.3 ⭐ The TypeScript/Go/Python type-sharing problem

Shape C (React + Java) at least has a shared JVM ecosystem. Shape D has nothing:

| Approach | What | Verdict |
|---|---|---|
| ⛔ Hand-written TS interfaces mirroring Python models | they drift, silently, immediately | the default, and the reason skew incidents happen |
| ⭐ **OpenAPI as the single source of truth** | FastAPI **generates** it; Spring generates it via springdoc; Go via swag | ✅ the correct answer |
| ⭐ Generate the TS client **from** the OpenAPI in CI | `openapi-typescript` / `orval` | ✅ then a contract change **fails the FE build** |
| Consumer-driven contracts (Pact) | the FE records what it expects; the BE verifies it | ⭐⭐ the strongest — §7 |
| A shared protobuf/gRPC schema | both sides generate from one `.proto` | ✅ excellent, but changes your API style |

```yaml
# ⭐ the CI step that makes drift a BUILD FAILURE rather than a 3 a.m. page
- name: Regenerate the API client from the backend's OpenAPI
  run: |
    set -euo pipefail
    # the BE publishes its spec as a CI artifact
    curl -fsSL "$BE_SPEC_URL" -o /tmp/openapi.json
    npx openapi-typescript /tmp/openapi.json -o src/api/schema.d.ts
    # ⭐⭐ if the regenerated file DIFFERS from what is committed, the backend
    #   changed the contract and the frontend has not caught up. FAIL.
    if ! git diff --exit-code src/api/schema.d.ts; then
      echo "::error::API contract drifted — regenerate src/api/schema.d.ts"
      exit 1
    fi
```

---

## 6 · ⭐ The comparison table

| | 🔵 A · FE only | 🟢 B · BE only | 🟡 C · FE+BE | 🟠 D · polyglot |
|---|---|---|---|---|
| **Services** | 1 | 1 | 2 | 3–5 |
| **Toolchains** | 1 | 1 | 2 | ⭐ 3–4 |
| **Build time** | 30–90 s | 40 s – 8 min | 3–9 min | 3–9 min (parallel) |
| **Tests** | unit · a11y · ⭐ Lighthouse · bundle size | unit · ⭐ **integration w/ real DB** | both + ⭐ contract | both × N + contract |
| **Infra in CI** | none | ⭐ Testcontainers / sidecar DB | both | ⭐ DB **+ broker** |
| **Config trap** | ⭐⭐ **build-time env** (§2.3) | none (runtime env) | the FE half | the FE half |
| **Cache strategy** | npm | ⭐ Maven/Go/uv — essential | both | ⭐ per-service scope, quota pressure |
| **Pipeline count** | 1 | 1 | ⭐ 2 CI + 1 manifest | ⭐ matrix + 1 manifest |
| **Deploy order matters?** | no | no | ⭐⭐ **YES — BE first** | ⭐ yes, per dependency |
| **The failure that hurts** | stale `index.html` → old asset URLs | a migration that cannot roll back | ⭐⭐ **version skew** | toolchain drift + skew |
| **Rollback** | ⭐ trivial — static files | ⚠️ image yes, **schema no** | ⚠️ **both, in reverse order** | per-service |
| **Canary candidate** | poor (no gradual traffic) | ⭐ `payment-mock`, `checkout` | the BE half | ⭐ the Go services |
| **Scenario 2 difficulty** | easy | medium | ⭐⭐ hard | ⭐⭐ hard |
| **File** | [`../scenario-3-ci-plus-cd/04-fe-only.md`](../scenario-3-ci-plus-cd/04-fe-only.md) | [`…/05-be-only.md`](../scenario-3-ci-plus-cd/05-be-only.md) | [`…/06-fe-plus-be-same-stack.md`](../scenario-3-ci-plus-cd/06-fe-plus-be-same-stack.md) | [`…/07-fe-plus-be-different-langs.md`](../scenario-3-ci-plus-cd/07-fe-plus-be-different-langs.md) |

---

## 7 · ⭐⭐ The contract test — the only thing that makes C and D safe

**The problem it solves:** unit tests prove each side works *against its own assumptions*. Nothing proves the two sides' assumptions **agree**. A green FE suite and a green BE suite can still produce a 404 in production.

```
        FRONTEND                              BACKEND
   ┌──────────────────┐                  ┌──────────────────┐
   │ "I will send     │                  │ "I accept        │
   │  POST /orders    │                  │  POST /orders    │
   │  {sku, qty}"     │                  │  {sku, quantity}"│
   └────────┬─────────┘                  └────────┬─────────┘
            │                                     │
            │      ⛔ BOTH TEST SUITES PASS       │
            │      ⛔ PRODUCTION RETURNS 400      │
            └──────────────┬──────────────────────┘
                           ▼
              ⭐ THE CONTRACT TEST CATCHES IT IN CI
```

### Consumer-driven contracts (Pact) — the shape

```
1. the CONSUMER (frontend) records what it actually does:
     "I will POST /api/v2/orders with {sku: string, qty: int}
      and expect 201 with {orderId: string}"
   → produces a PACT FILE (JSON), published as a CI artifact

2. the PROVIDER (backend) VERIFIES the pact against its real running code:
     → replays each recorded interaction, asserts the real response matches
     → ⭐ this runs in the BACKEND's CI, against the real controller

3. the broker records compatibility:
     → "shop-api v2.4.1 satisfies shop-ui v1.9.0's contract"
     → ⭐⭐ CD can then REFUSE to promote an incompatible pair
```

| Property | Why it matters |
|---|---|
| ⭐ The provider is tested against the consumer's **real** expectations | not a hand-written mock that also drifted |
| The pact file is **versioned and stored** | you can ask "does BE candidate X satisfy FE version Y in production *right now*?" |
| ⭐⭐ It is **language-neutral** | works for React↔Java *and* React↔Go *and* React↔Python — the pact is JSON |
| It runs in **both** pipelines | the consumer generates; the provider verifies |

### The cheaper 80% version — if Pact is too much machinery

```bash
# ⭐ a schema-diff gate. Not as strong as CDC, but it catches the common case:
#   a field renamed, removed, or retyped.
npx @openapitools/openapi-generator-cli validate -i /tmp/new-spec.json
openapi-diff --fail-on-incompatible /tmp/old-spec.json /tmp/new-spec.json
# ⛔ BREAKING: removed a property, narrowed a type, made an optional field required
# ✅ NON-BREAKING: added an optional field, widened a type, added an endpoint
```

⭐ **`openapi-diff --fail-on-incompatible` in the backend's CI is the single highest-value line you can add to a shape C or D pipeline.** It converts "the frontend broke in production" into "the build failed, with a message naming the removed field". Ten minutes of setup.

---

## 8 · Deciding: one pipeline or many?

| Situation | ⭐ Recommendation |
|---|---|
| One service | one pipeline. Obviously |
| 2–3 services, same repo, all deploy together | ⭐ **one pipeline, parallel jobs**, one manifest |
| A monorepo, services deploy independently | ⭐⭐ **one pipeline per service** + path filters + a release-train manifest |
| Shape C with a hard FE↔BE contract | ⭐ two CI pipelines + one manifest job (Option 3, §4.1) |
| Shape D at scale (>5 services) | ⭐ per-service CI + **GitOps** for CD — [`../scenario-3-ci-plus-cd/08-gitops-argocd.md`](../scenario-3-ci-plus-cd/08-gitops-argocd.md) |
| Polyrepo (one repo per service) | one pipeline per repo; the manifest problem becomes a **release coordination** problem |

⭐ **The question that decides it:** *can these services be deployed independently, or must they move together?*
- **Independently** → separate pipelines, separate manifests, maximum velocity.
- **Together** → one manifest, and the manifest is the unit of deployment.

Getting this backwards is expensive in both directions: coupling independent services makes every change a coordinated release; splitting coupled services produces version-skew incidents.

---

## 9 · ⭐ The four things that never differ

Whatever the shape, whatever the tool, whatever the language:

| # | Invariant | Test |
|---|---|---|
| **1** | **CI publishes an image by DIGEST** and records it somewhere CD can read | the manifest contains `@sha256:` for every service it built |
| **2** | **CI never deploys** | ⭐ no deploy verb in the pipeline **and** no cluster credential in scope |
| **3** | **A failed test means no published image** | the image job `needs:` / `dependsOn:` the test job — never `if: always()` |
| **4** | **A PR publishes nothing** | one flag (`DO_PUSH`, `PUBLISH`, `inputs.push`), defaulting to **false** |

⭐⭐ **Those four are the entire content of Scenario 1.** Everything else in this folder — the four shapes, the four languages, the three tools — is *adapter*. If you can state those four and show where each is enforced in your pipeline, you understand CI, and the tool is a detail.

---

<a name="tasks--answers"></a>
## 10 · ⭐ TASKS — answers at the END

| # | Task |
|---|---|
| **T1** | Classify all five `shop` apps into shapes A–D, and say which pipeline count you would give each |
| **T2** | Fix `shop-ui`'s Dockerfile so **one image** serves dev, staging and production. Prove it |
| **T3** | Add a bundle-size gate and a Lighthouse gate to `shop-ui` that do not flake |
| **T4** | Set `index.html` / `/assets/` / `config.js` cache headers correctly and explain the incident you prevented |
| **T5** | Replace an H2-based `@DataJpaTest` with a real Testcontainers Postgres 17 integration test |
| **T6** | Add the migration-shadow-database check (§3.3) to `shop-api`'s CI |
| **T7** | Design the three-release expand/contract sequence for renaming `qty` → `quantity` in the orders API |
| **T8** | Add `openapi-diff --fail-on-incompatible` to `shop-api`'s CI and make the FE build regenerate its client |
| **T9** | Build the four-service matrix with `fail-fast: false` and one manifest collector |
| **T10** | ⭐⭐ Your CI is green for both `shop-ui` and `shop-api`, and production returns 404 for every order. List every mechanism that could produce this, in order of likelihood |

---

# ✅ ANSWERS

**T1.** `shop-ui` → **shape A**, one pipeline. `shop-api`, `checkout`, `order-worker`, `payment-mock` → **shape B**, one pipeline each (four total). Deployed as the P10 pairing → **shape C**: keep the two CI pipelines and add a **manifest job** that emits one atomic pair (Option 3, §4.1). Deployed as P11/P12 (React+Python, React+Go) → **shape D**: a **matrix** over services plus one manifest collector. ⭐ The reasoning to state out loud: pipeline count follows **deployability**, not repository structure. Services that can be deployed independently get independent pipelines; services that must move together get a shared manifest.

**T2.** §2.3 in full. The mechanism: remove `ARG VITE_API_URL` from the build stage; add a `docker-entrypoint.d/` script that writes `/usr/share/nginx/html/config.js` from real environment variables at container start; load it with `<script src="/config.js">` **before** the bundle; read it through a single `src/config.ts` with a `?? import.meta.env` fallback so local dev still works. **Proof:** build **one** image, run it twice with different `API_URL` values, and `curl` each — the served `config.js` differs while `docker image inspect --format '{{.Id}}'` is **identical**. That single check is the whole point: same bytes, different config.

**T3.** §2.2. Two decisions make them non-flaky: **(a)** set the bundle budget from *today's* measured value and ratchet it down deliberately, never up silently; **(b)** Lighthouse with `numberOfRuns=3` and the **median** — a single run on a shared runner carries ±10 points of noise, and a flaky gate gets disabled, which is worse than no gate. Prefer per-chunk budgets (`resource-summary:script:size`) over a total, because a 50 KB regression in the critical path can hide inside a flat total.

**T4.** §2.4. `index.html` → `no-cache, must-revalidate`; `/assets/*` → `public, max-age=31536000, immutable` (safe because the filename carries a content hash); `/config.js` → `no-store`. **The incident prevented:** after a deploy, browsers holding a cached `index.html` request asset filenames that no longer exist → blank page or `Uncaught TypeError`. It "fixes itself" on a hard refresh, so it is reported as intermittent and never root-caused. ⭐ The general rule: *the entry point must never be cached; content-hashed assets should be cached forever.*

**T5.** §3.2. `@Testcontainers` + a `static` `@Container PostgreSQLContainer<>("postgres:17.7")` + `@DynamicPropertySource` to wire the URL. Two details decide whether it is useful: `static` means **one container per class** rather than one per test (per-test costs ~2 s each and dominates runtime), and **pinning the Postgres version** — ideally the digest — so a patch release cannot change your test results. ⭐ Why H2 is worse than nothing: it is not Postgres (no real JSONB, different constraint enforcement, different SQL), so tests pass against it and fail in production. That makes the gate *confidently* decorative.

**T6.** §3.3. In CI: restore a **production schema snapshot** into a shadow database, run `flyway migrate` against it, then run the integration tests. ⭐ This is the check that catches what a clean-database test cannot: a `NOT NULL` added to a column with existing nulls, a unique index over duplicated data, or an index build that would lock a 40-million-row table for twenty minutes. Pair it with the CD-side rule that the migration runs as a **Job that gates the rollout**, so a failure stops the pipeline instead of leaving half the fleet on a new schema.

**T7.** ⭐ Three releases, each independently safe and independently revertible:
- **Release 1 (backend):** accept **both** `qty` and `quantity` on input; emit **both** on output. Nothing breaks — old FE sends `qty`, still works.
- **Release 2 (frontend):** send `quantity`, read `quantity`. `qty` is still accepted and still emitted, so a cached old frontend *still works*.
- **Release 3 (backend):** remove `qty` — ⭐ **only after telemetry confirms zero `qty` traffic**, which may be days or weeks, because browser cache controls how long release 2's rollout really takes.

Reversal at any point is "revert the last release", never "coordinate two teams". The anti-pattern is one PR changing both sides: it looks cleaner and it is **not deployable without a breaking window**, because the two halves never roll out atomically.

**T8.** §5.3 and §7. Backend CI: publish the generated OpenAPI spec as an artifact and run `openapi-diff --fail-on-incompatible` against the previous released spec — so removing or retyping a field fails *that build*. Frontend CI: download the backend's spec, regenerate `src/api/schema.d.ts`, and `git diff --exit-code` it — so an un-updated client fails *this* build. ⭐ Together these two lines convert "the frontend broke in production" into "a build failed, naming the field". If you want more, Pact (§7) gives you consumer-driven verification, and it is language-neutral — which is why it is the right tool for shape D.

**T9.** §5.2. One job definition parameterised by `{name, context, lang}`, expanded as a matrix (GitHub `strategy.matrix`, Jenkins `parallel` from a Groovy loop, Azure `${{ each }}` over a **parameter** array — templates cannot loop over runtime variables). `fail-fast: false` so all four results arrive in one run. Then a collector job that `needs:` the matrix, downloads every `digest-*` artifact, and writes one `release-manifest.txt`. ⭐ The collector must treat a **skipped** service as absent rather than as a failure, and must fail loudly if a service that *should* have built did not — otherwise a broken path filter silently ships a partial release train.

**T10.** ⭐⭐ In order of likelihood:
1. **Version skew (§4.2)** — the backend removed or renamed an endpoint while cached frontends still call the old one. By far the most common cause of "both green, production broken", because *both* test suites test their own assumptions.
2. **A contract change that is backward-compatible in the schema but not in semantics** — the field still exists but its meaning changed (an enum gained a value the FE does not handle; a price moved from cents to dollars).
3. **No contract test at all (§7)** — the FE mocks the API and the BE tests against its own DTOs, so nothing ever compared the two. This is the *root* cause behind 1 and 2.
4. **Routing/ingress misconfiguration** — the FE's `API_URL` points at the wrong host (⭐ especially likely if config is baked at build time, §2.3), or the Ingress path prefix does not match.
5. **Auth/CORS** — the endpoint exists and returns 401/403 or is blocked preflight, surfacing in the browser as a failed request.
6. **A migration applied to the DB but not the code, or vice versa** — the endpoint 404s because the handler failed to start, or 500s because the column is missing.
7. **The FE built against a stale generated client** — §5.3's `git diff --exit-code` gate absent, so the drift never failed a build.

**How you would find out, in order:** open the browser devtools Network tab and read the *actual* failing request and status code (this alone usually distinguishes 1/4/5 from the rest in under a minute) → check the deployed FE's `config.js` for the API URL → `curl` the endpoint directly against the backend service, bypassing the ingress → compare the deployed BE image digest against the manifest to confirm what is actually running. ⭐ The meta-lesson: **both suites green means each side is self-consistent, not that the pair is.** That gap is exactly what §7's contract test exists to close, and its absence is the correct answer to "what should we add so this cannot happen again?"

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish_Kumar_Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn: https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260
🔗 GitHub: https://github.com/3558Bhk

*Four languages differ in three ways. Four shapes differ in one: whether the artifacts must move together.*

</div>
