# 🔴 SCENARIO 3 · FRONTEND + BACKEND, DIFFERENT LANGUAGES — CI + CD END TO END
### Docker/K8s P11 & P12: `shop-ui` (React/TS) + `checkout` (Go) + `order-worker` (Python) + `payment-mock` (Go), plus the P13 data tier. The polyglot estate: fan-out CI, a dependency-graph deploy order, per-service risk policies, and partial releases.

> **The shape:** four or more services in **three languages**, one repository, one Kubernetes cluster, one release train — and no two of them fail the same way.
> **The central problem:** ⭐ **a monorepo with per-language toolchains** must produce *independent* artifacts at *independent* speeds while deploying as a *coherent* whole.

---

## 📇 Contents

| § | What |
|---|---|
| [1](#1--what-changes-when-the-stack-is-polyglot) | What changes when the stack is polyglot — six properties |
| [2](#2---the-dependency-graph) | ⭐⭐ The dependency graph — the thing that decides deploy order |
| [3](#3---repo-shape-and-why-it-dictates-ci-cost) | ⭐ Repo shape, and why it dictates CI cost |
| [4](#4---fan-out-ci--one-reusable-workflow-per-language) | ⭐ Fan-out CI — one reusable workflow per language |
| [5](#5--the-three-toolchains-side-by-side) | The three toolchains, side by side — the full reference table |
| [6](#6--build-agents-per-language) | Build agents per language — and the JVM/Go/Python memory problem |
| [7](#7---cross-language-contracts) | ⭐⭐ Cross-language contracts — protobuf is the answer, and its limits |
| [8](#8---cd-with-a-dependency-order) | ⭐ CD with a dependency order, per-service policies, partial releases |
| [9](#9---case-1-or--case-2--per-service) | 🔒 Case 1 or 🤖 Case 2 — per service, and why they differ |
| [10](#10--️-run-it-end-to-end--the-acceptance-checks) | ▶️ Run it end to end — the acceptance checks |
| [11](#11--troubleshooting) | Troubleshooting |
| [12](#12---tasks--answers-at-the-end) | Tasks and answers — **answers at the END** |

---

## 1 · What changes when the stack is polyglot

| # | Property | ⭐ Consequence |
|---|---|---|
| **1** | **Three toolchains in one repo** | one CI config cannot serve all three — you need **reusable workflows / templates / shared libraries**, one per language |
| **2** | ⭐ **Build times differ by 10×** | Go 40 s, Python 60 s, Java 6 min, React 3 min. A serial pipeline wastes minutes; a fan-out pipeline wastes nothing |
| **3** | ⭐ **Caches differ** | `.m2`, Go build cache, `uv.lock`, `node_modules` — four separate cache scopes, keyed differently |
| **4** | **Failure modes differ** | a Go failure is a compile error; a Java failure may be an OOM agent; a Python failure may be a missing native lib |
| **5** | ⭐⭐ **There is a dependency ORDER** | `checkout` → `payment-mock`; `order-worker` consumes what `shop-api` produces. Deploy order is not free choice |
| **6** | **Risk differs per service** | `payment-mock` is trivial; `order-worker` has in-flight messages; `shop-api` has a schema. ⭐ One policy for all is wrong |

**And what does *not* change — which is the reassuring part:**

```
✅ THE ARTIFACT CONTRACT IS IDENTICAL IN EVERY LANGUAGE.
   digest in · digest out · provenance · staging-ran-this-digest · read back.
   ✅ CI cannot deploy; CD cannot build. Same asymmetry.
   ✅ One image, all environments. Same runtime-config discipline (§04).
   ⭐ Only the STAGES differ. The ARCHITECTURE is the architecture you
     have already built four times in this folder.
```

---

## 2 · ⭐⭐ The dependency graph

```
                        ┌──────────────┐
   browser ───────────▶ │   shop-ui    │  React · :80
                        └──────┬───────┘
                               │ HTTP /api/v2
                               ▼
                        ┌──────────────┐        ┌────────────────┐
                        │   shop-api   │──────▶ │  payment-mock  │ Go · :9093
                        │  Java · :8080│        └────────────────┘
                        └──┬────────┬──┘                 ▲
                  AMQP     │        │  HTTP              │
             orders queue  │        └────────────────────┘
                           ▼                   checkout calls it too
                    ┌──────────────┐    ┌──────────────┐
                    │ order-worker │    │   checkout   │ Go · :9091
                    │ Python       │    └──────────────┘
                    └──────┬───────┘
                           │
        ┌──────────────────┼──────────────────┐
        ▼                  ▼                  ▼
   ┌─────────┐      ┌───────────┐      ┌───────────┐
   │ Postgres│      │   Redis   │      │ RabbitMQ  │   ⭐ P13 — 🔒 ALWAYS Case 1
   │  :5432  │      │   :6379   │      │   :5672   │
   └─────────┘      └───────────┘      └───────────┘
```

### 2.1 The deploy order that follows from it

| Order | Service | ⭐ Why here |
|---|---|---|
| **1** | **data tier** (P13) | everything depends on it, and it is 🔒 Case 1, upgraded separately and carefully |
| **2** | `payment-mock` | ⭐ a **leaf dependency** — `checkout` and `shop-api` call it. Deploy the callee first |
| **3** | `shop-api` | the schema owner; ⭐ **migration Job runs here, before the app** |
| **4** | `checkout` | calls `payment-mock` and `shop-api`; both already serve the new contract |
| **5** | `order-worker` | consumes from the queue `shop-api` publishes to; ⭐ the **producer must be compatible before the consumer changes** |
| **6** | `shop-ui` | ⭐ **last, always** — the browser is the least-recallable client |

⭐⭐ **The two rules that generate this order:**

```
RULE A — CALLEE BEFORE CALLER.
   A service that is CALLED must serve both the old and new contract before
   its callers move. Deploy the dependency first.

RULE B — PRODUCER BEFORE CONSUMER (for queues).
   If shop-api starts publishing a new message SHAPE, order-worker must
   already be able to read it. So order-worker deploys BEFORE shop-api
   ⛔ when the change is a new message field — the OPPOSITE of rule A.
   ⭐ The resolution: make the CONSUMER tolerant first (accept both shapes),
     deploy it, THEN deploy the producer that emits the new shape.
     This is expand/contract (§06 file §3) applied to a queue instead of HTTP.
```

⭐ **That asymmetry is the single most-missed thing in polyglot CD.** HTTP is request/response, so callee-first is obvious. A queue is *stored* — a message published by the new producer can sit unread for minutes and be consumed by the **old** consumer. So the consumer must be upgraded first, and must tolerate both shapes during the window. Getting this backwards produces a DLQ full of unreadable messages that you discover hours later.

---

## 3 · ⭐ Repo shape, and why it dictates CI cost

```
⛔ ONE REPO, NO PATH FILTERS
   every commit runs: mvn verify (6m) + go test + pytest + vitest + 4 image builds
   → 20 minutes per commit, for a one-line CSS change
   → people stop reading CI output
   → CI becomes a formality

⛔ FOUR REPOS
   ✅ independent CI, fast feedback
   ⛔ a cross-service change needs four PRs, four reviews, four merges,
      and a way to express "these four commits go together" — which is the
      hardest problem in polyrepo engineering
   ⛔ the release manifest (§06 file §5) becomes cross-repo coordination

✅ ⭐⭐ ONE MONOREPO + PATH FILTERS + FAN-OUT + A MANIFEST
   apps/
     shop-ui/        package.json, vite.config.ts, Dockerfile
     shop-api/       pom.xml, Dockerfile
     checkout/       go.mod, Dockerfile
     order-worker/   pyproject.toml, uv.lock, Dockerfile
     payment-mock/   go.mod, Dockerfile
   contracts/
     api/openapi.yaml          ⭐ the HTTP contract
     events/order-events.proto ⭐⭐ the QUEUE contract
   k8s/
     base/ overlays/{dev,staging,production}/
   .github/workflows/
     _ci-node.yml   _ci-java.yml   _ci-go.yml   _ci-python.yml  ⭐ reusable
     ci-polyglot.yml      ← the fan-out
     cd-shop.yml          ← the dependency-ordered CD
```

| Property | ⭐ Why the monorepo wins here |
|---|---|
| **A contract change is ONE commit** | `contracts/events/order-events.proto` + the Go producer + the Python consumer, reviewed together, merged together, **impossible to half-land** |
| **The manifest is local** | "which digests go together" is answered by the commit SHA, not by cross-repo coordination |
| **Path filters restore CI speed** | a CSS change runs only `_ci-node.yml` |
| **One branch, one history** | `git bisect` works across services |
| ⛔ **The cost** | CODEOWNERS and required-reviewer rules per path become essential, or a frontend PR can merge a Go change nobody reviewed |

```yaml
# ⭐ CODEOWNERS — the control that makes a monorepo safe
/apps/shop-api/**       @shop/backend-java
/apps/checkout/**       @shop/backend-go
/apps/order-worker/**   @shop/backend-python
/apps/shop-ui/**        @shop/frontend
/apps/payment-mock/**   @shop/backend-go
# ⭐⭐ the contract directory needs EVERYONE, because a change here is the
#   one change that can break all four services at once
/contracts/**           @shop/backend-java @shop/backend-go @shop/backend-python @shop/frontend
/k8s/**                 @shop/platform
```

---

## 4 · ⭐ Fan-out CI — one reusable workflow per language

### 4.1 The dispatcher

`.github/workflows/ci-polyglot.yml`

```yaml
name: CI · polyglot
on:
  push:         { branches: [main] }
  pull_request: { branches: [main] }
permissions: { contents: read }

jobs:
  # ── ⭐⭐ 1. WHAT CHANGED? ────────────────────────────────────────────
  changes:
    runs-on: ubuntu-latest
    outputs:
      ui:       ${{ steps.f.outputs.ui }}
      api:      ${{ steps.f.outputs.api }}
      checkout: ${{ steps.f.outputs.checkout }}
      worker:   ${{ steps.f.outputs.worker }}
      payment:  ${{ steps.f.outputs.payment }}
      contracts: ${{ steps.f.outputs.contracts }}
      any:      ${{ steps.f.outputs.any }}
    steps:
      - uses: actions/checkout@v7
        with: { fetch-depth: 0 }
      - uses: dorny/paths-filter@v3
        id: f
        with:
          filters: |
            ui:        ['apps/shop-ui/**']
            api:       ['apps/shop-api/**']
            checkout:  ['apps/checkout/**']
            worker:    ['apps/order-worker/**']
            payment:   ['apps/payment-mock/**']
            # ⭐⭐ A CONTRACT CHANGE TOUCHES EVERY CONSUMER OF THAT CONTRACT.
            #   Forget this and you get the polyglot version of "both green,
            #   production broken".
            contracts: ['contracts/**']
            any:
              - 'apps/**'
              - 'contracts/**'
              - 'k8s/**'

  # ── ⭐ 2. FAN OUT — five jobs, in parallel, only the relevant ones ───
  ui:
    needs: changes
    # ⭐ `contracts` changed → EVERY consumer rebuilds, even if its own
    #   directory did not.
    if: needs.changes.outputs.ui == 'true' || needs.changes.outputs.contracts == 'true'
    uses: ./.github/workflows/_ci-node.yml
    with: { app: apps/shop-ui, image: shop-ui, port: 80 }
    permissions: { contents: read, packages: write, id-token: write }

  api:
    needs: changes
    if: needs.changes.outputs.api == 'true' || needs.changes.outputs.contracts == 'true'
    uses: ./.github/workflows/_ci-java.yml
    with: { app: apps/shop-api, image: shop-api, port: 8080 }
    permissions: { contents: read, packages: write, id-token: write }

  checkout:
    needs: changes
    if: needs.changes.outputs.checkout == 'true' || needs.changes.outputs.contracts == 'true'
    uses: ./.github/workflows/_ci-go.yml
    with: { app: apps/checkout, image: checkout, port: 9091 }
    permissions: { contents: read, packages: write, id-token: write }

  worker:
    needs: changes
    if: needs.changes.outputs.worker == 'true' || needs.changes.outputs.contracts == 'true'
    uses: ./.github/workflows/_ci-python.yml
    with: { app: apps/order-worker, image: order-worker }
    permissions: { contents: read, packages: write, id-token: write }

  payment:
    needs: changes
    if: needs.changes.outputs.payment == 'true'
    uses: ./.github/workflows/_ci-go.yml
    with: { app: apps/payment-mock, image: payment-mock, port: 9093 }
    permissions: { contents: read, packages: write, id-token: write }

  # ── ⭐ 3. CROSS-CUTTING CHECKS (repo-wide, not per-service) ─────────
  repo:
    needs: changes
    if: needs.changes.outputs.any == 'true'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - name: ⭐ Kustomize renders for every overlay
        run: |
          set -euo pipefail
          for env in dev staging production; do
            kubectl kustomize "k8s/overlays/$env" > "/tmp/$env.yaml"
            kubeconform -strict -summary "/tmp/$env.yaml"
            echo "✅ $env renders and validates"
          done
      - name: ⭐⭐ No secret-looking value anywhere in k8s/
        run: |
          set -euo pipefail
          # ⭐ in a monorepo the k8s tree is shared, so one leaked value
          #   compromises every service
          if grep -rniE '(password|secret|token|api[_-]?key)[[:space:]]*:[[:space:]]*[^[:space:]{$]' k8s/ \
               | grep -vE 'secretKeyRef|valueFrom|\$\{|\{\{' ; then
            echo "::error::⛔ plaintext secret in k8s/"; exit 1
          fi
          echo "✅ no plaintext secrets"
      - name: ⭐ Contract files are valid
        run: |
          set -euo pipefail
          npx @redocly/cli lint contracts/api/openapi.yaml
          docker run --rm -v "$PWD/contracts:/c" bufbuild/buf:1.50.0 lint /c/events
          # ⭐⭐ a malformed proto breaks codegen in THREE languages at once
      - name: ⭐ Regenerate and check for drift (all languages)
        run: |
          set -euo pipefail
          buf generate contracts/events --template buf.gen.go.yaml     && git diff --exit-code apps/checkout/gen/
          buf generate contracts/events --template buf.gen.python.yaml  && git diff --exit-code apps/order-worker/gen/
          buf generate contracts/events --template buf.gen.ts.yaml      && git diff --exit-code apps/shop-ui/src/gen/
          # ⭐⭐ THE POLYGLOT CONTRACT GATE: if a .proto changed and the
          #   generated code was not regenerated and committed, FAIL.
          #   This is the single check that prevents "Go publishes field 4,
          #   Python does not know field 4 exists".

  # ── ⭐ 4. THE MANIFEST — only on main, only for what built ──────────
  manifest:
    needs: [changes, ui, api, checkout, worker, payment]
    if: always() && github.event_name == 'push' && github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    permissions: { contents: read, packages: read }
    steps:
      - uses: actions/checkout@v7
      - name: ⭐ Build the polyglot release manifest
        env: { GH_TOKEN: "${{ secrets.GITHUB_TOKEN }}" }
        run: |
          set -euo pipefail
          : > release-manifest.txt
          # ⭐⭐ for EVERY service in the estate: the new digest if it built,
          #   otherwise the digest CURRENTLY RUNNING. The manifest always
          #   describes a COMPLETE, deployable estate — never a partial one.
          for svc in payment-mock shop-api checkout order-worker shop-ui; do
            if [ -s "/tmp/$svc/digest.txt" ] 2>/dev/null; then
              REF=$(cat "/tmp/$svc/digest.txt")
            else
              REF=$(kubectl -n shop-production get deploy "$svc" 2>/dev/null \
                    -o jsonpath="{.spec.template.spec.containers[?(@.name=='$svc')].image}" \
                    || echo "")
            fi
            [[ "$REF" =~ @sha256: ]] || { echo "::error::⛔ no digest for $svc"; exit 1; }
            printf '%s=%s\n' "$svc" "$REF" >> release-manifest.txt
          done
          # ⭐⭐ and assert the deploy order is expressible
          printf '# order=payment-mock,shop-api,checkout,order-worker,shop-ui\n' >> release-manifest.txt
          cat release-manifest.txt
      - uses: actions/upload-artifact@v4
        with: { name: release-manifest, path: release-manifest.txt, retention-days: 90 }
```

### 4.2 ⭐ Why the `contracts` filter is the important line

```
⛔ WITHOUT IT
   someone edits contracts/events/order-events.proto: adds field 4
   → only the `worker` job is skipped-in, because apps/order-worker/** changed too
   → checkout did NOT change on disk, so its job is skipped
   → checkout's GENERATED CODE is not regenerated
   → checkout still publishes the message WITHOUT field 4
   → order-worker expects field 4 → KeyError / zero value → silent data loss
   ⭐ ALL CI JOBS THAT RAN WERE GREEN.

✅ WITH IT
   contracts/** changed → EVERY consumer rebuilds, regenerates, and the
   drift check (§4.1 `repo` job) fails if generated code was not committed.
   ⭐ the failure happens in CI, naming the file, not in production, silently.
```

### 4.3 The three tools' equivalent of a reusable workflow

| | 🐙 GitHub | 🔷 Azure DevOps | 🔨 Jenkins |
|---|---|---|---|
| The per-language unit | ⭐ `workflow_call` reusable workflow | ⭐ `templates/*.yml` with `parameters` | ⭐ **shared library** `vars/ciGo.groovy` |
| Fan-out | `needs: changes` + `if:` per job | ⭐ **template expressions are compile-time** — a runtime list cannot loop. Use one pipeline per service, or `parameters: services:` as a fixed array | `parallel { }` inside one Jenkinsfile |
| Change detection | `dorny/paths-filter@v3` | `paths:` filter per pipeline, or `git diff --name-only` in a `bash:` step | the `changeset` condition on a multibranch trigger, or `git diff` in a `when` |
| The manifest | a `manifest` job with `if: always()` | a third pipeline with `resources.pipelines` on all five | a `manifest` stage writing `release-manifest.txt` |
| ⭐ The trap | a skipped job reports `skipped`, not `success` → `always()` + explicit verification | ⛔ `resources.pipelines` triggers when **any** upstream completes, not all | ⛔ `parallel` stages share one workspace — use distinct `dir()` blocks |

```groovy
// ⭐ Jenkins fan-out — parallel stages, distinct dirs
stage('fan out') {
  parallel {
    stage('shop-ui')   { when { anyOf { changeset 'apps/shop-ui/**'; changeset 'contracts/**' } }
                         steps { dir('apps/shop-ui')   { ciNode(app: 'shop-ui') } } }
    stage('shop-api')  { when { anyOf { changeset 'apps/shop-api/**'; changeset 'contracts/**' } }
                         steps { dir('apps/shop-api')  { ciJava(app: 'shop-api') } } }
    stage('checkout')  { when { anyOf { changeset 'apps/checkout/**'; changeset 'contracts/**' } }
                         steps { dir('apps/checkout')  { ciGo(app: 'checkout') } } }
    stage('worker')    { when { anyOf { changeset 'apps/order-worker/**'; changeset 'contracts/**' } }
                         steps { dir('apps/order-worker') { ciPython(app: 'order-worker') } } }
    stage('payment')   { when { changeset 'apps/payment-mock/**' }
                         steps { dir('apps/payment-mock') { ciGo(app: 'payment-mock') } } }
  }
}
// ⭐⭐ `dir()` is REQUIRED: parallel stages share ONE workspace, so two
//   `go build`s in the same directory will race over the same output file.
```

---

## 5 · The three toolchains, side by side

⭐ **The reference table for the whole polyglot estate.** Every row is a decision you will be asked about in an interview.

| | **Node / React** (`shop-ui`) | **Java** (`shop-api`) | **Go** (`checkout`, `payment-mock`) | **Python** (`order-worker`) |
|---|---|---|---|---|
| **Version pinning** | ⭐ `.nvmrc` + `engines` + `setup-node@v6 node-version-file` | ⭐ `mvnw` wrapper + `setup-java@v5 java-version: '21'` | ⭐ `go.mod`'s `go 1.25.0` + `setup-go@v6` | ⭐ `.python-version` + `setup-python@v6` |
| **Lockfile** | `package-lock.json` | ⛔ none — ⭐ pin the wrapper, `-ntp` | `go.sum` | `uv.lock` |
| **Honour it** | ⛔ never `npm install`; ✅ `npm ci` | `-B -ntp`, no `versions:` plugin in CI | ⛔ never `go get`; ✅ `go mod download` | ⭐ `uv sync --frozen` |
| **Cache key** | `node_modules` ← hash of `package-lock.json` | `~/.m2` ← hash of `pom.xml` | ⭐ **two**: `$GOMODCACHE` ← `go.sum`, and the **build cache** ← source | `.venv` + uv cache ← `uv.lock` |
| **Cache action** | `cache: npm` | `cache: maven` | `cache: true` (setup-go) | `astral-sh/setup-uv@v7 enable-cache` |
| **Install** | `npm ci` | `./mvnw dependency:go-offline` | `go mod download` | `uv sync --frozen --all-extras` |
| **Lint** | `eslint`, `prettier --check` | SpotBugs, Checkstyle, ErrorProne | ⭐ `go vet`, `golangci-lint` | ⭐ `ruff check`, `ruff format --check`, `mypy` |
| **Test** | `vitest run --coverage` | Surefire + ⭐ Failsafe ITs | ⭐ `go test -race -count=1` | `pytest --cov-fail-under=80` |
| **⛔ Test-cache trap** | none | Surefire reruns | ⭐⭐ `-count=1` **required** or `go test` prints `(cached)` and runs nothing | none |
| **Real infra needed** | ⛔ none | ⭐⭐ Postgres (Testcontainers) | Postgres + Redis | ⭐⭐ RabbitMQ |
| **Coverage gate** | `vitest --coverage.thresholds` | JaCoCo `check` rule | ⭐ parse `go tool cover -func` | `--cov-fail-under` |
| **CVE — deps** | `npm audit --audit-level=high` | ⭐ `dependency-check-maven:check` | `go list -m -u all` + Trivy | ⭐ `pip-audit --strict` |
| **CVE — language-specific** | ⛔ none | ⛔ none | ⭐⭐ `govulncheck` (reachability-aware) | ⭐ `bandit -r src/ -ll` |
| **CVE — image** | Trivy | Trivy | Trivy | Trivy |
| **Build flags** | `vite build` (⭐ runtime config, not baked env) | `mvn package -DskipTests` | ⭐ `CGO_ENABLED=0 -trimpath -ldflags="-s -w"` | ⛔ compiles nothing |
| **Static binary?** | n/a | ⛔ needs a JRE | ⭐✅ yes → `FROM scratch` | ⛔ needs an interpreter |
| **Runtime base** | `nginx:1.29-alpine` | `temurin:21-jre-alpine` | ⭐ `scratch` | `python:3.13-slim` |
| **Image size** | ~50 MB | ~230 MB | ⭐ ~10 MB | ~120 MB |
| **Layer trick** | ⭐ `COPY dist/` last | ⭐⭐ Spring Boot `layertools` extraction | `COPY go.mod go.sum` then `COPY . .` | ⭐ `uv sync` then `COPY . .` then `uv sync` again |
| **Reproducibility** | ⭐ `vite build` is not byte-reproducible (hashes are stable, metadata is not) | ⭐ `project.build.outputTimestamp` + `reproducible-build-maven-plugin` | ⭐⭐ `-trimpath` + `SOURCE_DATE_EPOCH` → **byte-identical** | ⛔ `.pyc` timestamps vary unless `PYTHONHASHSEED`/bytecode flags are set |
| **Container memory** | ⛔ n/a (nginx) | ⭐⭐ `-XX:MaxRAMPercentage=75`, never `-Xmx` | ~20 MB, no tuning | ~150 MB, no tuning |
| **Cold start** | instant | ⭐⭐ 20–60 s (JVM + Spring context) | ~50 ms | ~1 s |
| **Needs a `startupProbe`?** | no | ⭐⭐ **yes** — else liveness restart-loops it | no | no |
| **Health endpoint** | `/` (or a `/healthz` location) | `/actuator/health/readiness` | `/readyz` | ⭐ **none — a heartbeat file** ([`05-be-only.md`](./05-be-only.md) §7) |
| **Non-root** | `nginx` image runs as root by default → ⭐ override | `adduser -S app` | ⭐ `USER 65534` on `scratch` | `useradd -r app` |
| **Debuggability** | ✅ `kubectl exec` | ✅ `kubectl exec` | ⛔ **no shell** → `kubectl debug --image=busybox` | ✅ `kubectl exec` |
| **Warm build time** | ~90 s | ⭐ 60–90 s | ~15 s | ~20 s |
| **Cold build time** | 3 min | ⭐⭐ 6–8 min | 40 s | 60 s |
| ⭐ **Deploy risk** | 🟢 low (static files, instant rollback) | 🔴 **high** (schema) | 🟢 **low** (static binary, 50 ms start) | 🟡 medium (in-flight messages) |
| ⭐ **Case** | 🤖 **2** | 🔒 **1** | 🤖 **2 — the pilot** | 🔒 **1** |

---

## 6 · Build agents per language

### 6.1 ⭐ The memory problem nobody sizes for

| Language | Typical agent memory need | What happens when it is short |
|---|---|---|
| **Java** (Maven + Surefire + Testcontainers) | ⭐⭐ **6–8 GB** | `java.lang.OutOfMemoryError: GC overhead limit exceeded`, or the **agent** is killed and the build reports "lost connection" |
| **React** (`vite build`) | ⭐⭐ **4–8 GB** — ⛔ bundling is memory-hungry | `JavaScript heap out of memory` (`FATAL ERROR: Reached heap limit Allocation failed`) |
| **Go** | 1–2 GB | rarely a problem |
| **Python** | 1–2 GB | rarely a problem |

```yaml
# ⭐ the two fixes
# (a) give the toolchain a limit that fits the container
env:
  MAVEN_OPTS: "-Xmx3g -XX:MaxMetaspaceSize=512m"       # ⭐ the Maven JVM
  NODE_OPTIONS: "--max-old-space-size=6144"            # ⭐ the Node heap
  # ⛔ without these, Node's default heap (~2 GB on older, ~4 GB on newer)
  #   is exceeded by a large Vite/webpack build and the process dies with a
  #   message that looks like a code bug.

# (b) size the agent to the language
#    Jenkins Kubernetes pod template:
spec:
  containers:
    - name: maven
      image: maven:3.9.11-eclipse-temurin-21
      resources:
        requests: { cpu: "2", memory: 6Gi }     # ⭐⭐ requests, or the pod is
        limits:   { cpu: "4", memory: 8Gi }     #   scheduled onto a node that
                                                #   cannot hold it and is OOMKilled
```

### 6.2 ⭐ One agent image per language — the pod-template approach

```yaml
# ⭐ Jenkins: four pod templates, one per toolchain, each sized correctly
apiVersion: v1
kind: Pod
metadata: { labels: { jenkins/label: shop-java } }
spec:
  serviceAccountName: jenkins-agent-ci          # ⭐ CI SA — push, not deploy
  containers:
    - name: maven
      image: maven:3.9.11-eclipse-temurin-21
      command: ["sleep"]
      args: ["infinity"]
      resources: { requests: { cpu: "2", memory: 6Gi }, limits: { cpu: "4", memory: 8Gi } }
      volumeMounts:
        - { name: m2, mountPath: /root/.m2 }     # ⭐ a PVC-backed cache
  - name: go-agent       # for the Go services
    image: golang:1.25-alpine
    resources: { requests: { cpu: "1", memory: 1Gi }, limits: { cpu: "2", memory: 2Gi } }
  volumes:
    - name: m2
      persistentVolumeClaim: { claimName: jenkins-m2-cache }
```

| Property | ⭐ Why per-language agents beat one fat agent |
|---|---|
| The image is small | a "everything" agent image is 3 GB and pulls on every build |
| ⭐ Versions are independent | Java 21 → 25 without touching the Node version |
| ⭐ Resources are right-sized | Maven gets 8 GB; Go gets 2 GB. One fat agent must request the max for all |
| ⛔ The cost | four pod templates to maintain, and cross-language builds need two containers in one pod |

---

## 7 · ⭐⭐ Cross-language contracts

**The polyglot estate's hardest problem is not building three languages. It is making them agree.**

### 7.1 HTTP — OpenAPI

```
contracts/api/openapi.yaml          ⭐ ONE source of truth
        │
        ├─▶ Java   : openapi-generator → DTOs + a controller interface
        ├─▶ Go     : oapi-codegen      → structs + a ServerInterface
        ├─▶ TS     : openapi-typescript → types + a typed fetch client
        └─▶ Python : datamodel-code-generator → pydantic models

⭐ THE GATE (in the `repo` CI job, §4.1):
   regenerate ALL of them and `git diff --exit-code`.
   If the .yaml changed and the generated code was not committed → FAIL.

⭐ PLUS (in each service's CI):
   openapi-diff --fail-on-incompatible against the previous released spec.
   (§06 file §6.1 — same check, now with four consumers instead of one.)
```

### 7.2 ⭐⭐ The queue — protobuf, and why JSON is a trap

```
⛔ JSON OVER A QUEUE, WITH NO SCHEMA
   Go:      json.Marshal(OrderEvent{OrderID: "o1", Quantity: 2})
   Python:  data = json.loads(msg.body); qty = data["qty"]
   ⛔ KeyError: 'qty' — at RUNTIME, in PRODUCTION, after the message is
      already in the queue and possibly already acknowledged.
   ⛔ AND: the message is not recoverable by redeploying. It is STORED.

✅ PROTOBUF — contracts/events/order-events.proto
   syntax = "proto3";
   package shop.events.v1;              // ⭐⭐ VERSION IN THE PACKAGE
   message OrderEvent {
     string order_id = 1;
     int32  quantity = 2;               // ⭐ field NUMBERS are the contract
     int64  total_cents = 3;
     // reserved 4;                      // ⭐⭐ NEVER REUSE A FIELD NUMBER
     OrderStatus status = 5;
   }
```

| Proto rule | ⭐ Why |
|---|---|
| **Field numbers are the wire contract, not names** | renaming `quantity` → `qty` is **safe** (the number is unchanged). ⛔ Changing the *number* corrupts every in-flight message |
| ⭐⭐ **`reserved` a removed field's number and name** | so a future developer cannot reuse `4` for something else, which would silently reinterpret old messages |
| **New fields must be optional-by-nature** | proto3 has no `optional` by default — a missing field decodes as the **zero value**. So ⛔ `bool` and `int32` cannot distinguish "absent" from "false"/"0" without `optional` (proto3 syntax supports it) or a wrapper message |
| ⭐ **Never change a field's TYPE** | not even `int32` → `int64`: wire-compatible for varints, but Go and Python generate different types and the consumers must all be regenerated |
| **Version the package**: `shop.events.v1` | so v2 can coexist during expand/contract, exactly like `/api/v1` |

### 7.3 ⭐ The producer/consumer ordering for a queue — restated

```
CHANGE: add `discount_cents` to OrderEvent.

⛔ WRONG ORDER (deploy producer first)
   checkout (new) publishes messages WITH discount_cents
   order-worker (OLD) is still running
   → in proto3 an unknown field is PRESERVED and IGNORED → ✅ actually safe
   → but if the change is a SEMANTIC one (quantity now means something
     different, or a field was REPURPOSED) → ⛔ silent misinterpretation

✅ RIGHT ORDER (deploy the tolerant consumer first)
   1. order-worker: accept BOTH shapes (tolerate the field being absent)
   2. deploy order-worker            ⭐ consumer first
   3. checkout: start EMITTING the new field
   4. deploy checkout                ⭐ producer second
   ⭐ and the window where both shapes are in the queue simultaneously is
     handled by step 1, not by luck.

⛔ WRONG ORDER for a REMOVAL
   1. checkout stops emitting `legacy_id`
   2. order-worker still reads `data.legacy_id` → zero value → ⛔ silent bug
   ✅ reverse: make the consumer stop READING it first, deploy, then stop emitting.
```

⭐ **This is rule B from §2.1, and it is the opposite of rule A.** HTTP is callee-first; queues are consumer-first. Both are "the party that must tolerate the change deploys first" — the difference is only in *who* must tolerate it.

### 7.4 The gate that catches all of it

```bash
# ⭐⭐ in the `repo` CI job — one check, four languages
set -euo pipefail
buf breaking contracts/events --against '.git#branch=main,subdir=contracts/events'
# ⛔ FAILS ON: a removed field · a changed field number · a changed type ·
#             a reused reserved number · a removed enum value · a renamed package
# ✅ ALLOWS:  a new field · a new enum value · a new message
# ⭐ this is `openapi-diff` for protobuf, and it is the difference between
#   "the polyglot estate has a contract" and "it has three languages that
#   happen to agree today".

buf generate && git diff --exit-code     # ⭐ generated code must be committed
```

---

## 8 · ⭐ CD with a dependency order

### 8.1 The manifest, and the order encoded in it

```text
# release-manifest.txt
# release  2026.09.16-1
# commit   41ab7c9
# order=payment-mock,shop-api,checkout,order-worker,shop-ui
payment-mock=ghcr.io/3558bhk/payment-mock@sha256:1a…
shop-api=ghcr.io/3558bhk/shop-api@sha256:41…
checkout=ghcr.io/3558bhk/checkout@sha256:9f…
order-worker=ghcr.io/3558bhk/order-worker@sha256:2c…
shop-ui=ghcr.io/3558bhk/shop-ui@sha256:7d…
```

### 8.2 ⭐ The ordered deploy, with per-service policy

```bash
#!/usr/bin/env bash
# deploy-estate.sh — ⭐ dependency order, per-service policy, roll-back-ALL
set -euo pipefail
NS="${NS:-shop-production}"

# ── parse the manifest ────────────────────────────────────────────────
declare -A REF PREV POLICY=(
  [payment-mock]=auto      # ⭐ 🤖 Case 2 — a leaf, 10 MB, 50 ms start
  [shop-api]=approval      # ⭐ 🔒 Case 1 — owns the schema
  [checkout]=auto          # ⭐ 🤖 Case 2 — static binary, -race tested
  [order-worker]=approval  # ⭐ 🔒 Case 1 — in-flight messages, no HTTP probe
  [shop-ui]=auto           # ⭐ 🤖 Case 2 — static files, instant rollback
)
ORDER="payment-mock shop-api checkout order-worker shop-ui"   # ⭐ §2.1

while IFS='=' read -r k v; do
  [[ "$k" == \#* || -z "$k" ]] && continue
  REF[$k]="$v"
  [[ "$v" =~ @sha256:[0-9a-f]{64}$ ]] || { echo "⛔ not a digest: $k=$v"; exit 1; }
done < release-manifest.txt

# ── ⭐ RECORD THE ENTIRE ESTATE — that record IS the rollback ─────────
for svc in $ORDER; do
  PREV[$svc]=$(kubectl -n $NS get deploy "$svc" \
    -o jsonpath="{.spec.template.spec.containers[?(@.name=='$svc')].image}")
done
echo "📌 previous estate recorded for ${#PREV[@]} services"

rollback_all() {
  echo "🚨 ROLLING BACK THE ENTIRE ESTATE"
  # ⭐⭐ REVERSE ORDER — undo in the opposite sequence you applied,
  #   so the callee stays compatible with the caller at every step.
  for svc in shop-ui order-worker checkout shop-api payment-mock; do
    kubectl -n $NS set image "deploy/$svc" "$svc=${PREV[$svc]}" || true
  done
  for svc in shop-ui order-worker checkout shop-api payment-mock; do
    kubectl -n $NS rollout status "deploy/$svc" --timeout=300s || true
  done
}
trap rollback_all ERR

# ── ⭐ deploy in dependency order, each with its own policy ───────────
for svc in $ORDER; do
  echo "════ $svc ════"

  # ⭐ CHECK 1/2 — provenance, per service
  cosign verify --certificate-oidc-issuer=https://token.actions.githubusercontent.com \
    --certificate-identity-regexp="https://github.com/.*/\.github/workflows/ci-polyglot\.yml@refs/heads/main" \
    "${REF[$svc]}" >/dev/null

  # ⭐⭐ CHECK 3 — did STAGING run THIS digest, for THIS service?
  STG=$(kubectl -n shop-staging get deploy "$svc" \
        -o jsonpath="{.spec.template.spec.containers[?(@.name=='$svc')].image}")
  [ "$STG" = "${REF[$svc]}" ] || {
    echo "⛔ staging ran $STG, not ${REF[$svc]} — this service was NOT validated"; exit 1; }

  # ⭐ the migration gate, only for the service that owns a schema
  if [ "$svc" = "shop-api" ]; then
    kubectl -n $NS delete job shop-api-migrate --ignore-not-found
    kubectl -n $NS apply -f k8s/shop-api/migration-job.yaml
    kubectl -n $NS wait --for=condition=complete job/shop-api-migrate --timeout=600s
  fi

  # ⭐ the policy gate
  if [ "${POLICY[$svc]}" = "approval" ] && [ "${AUTO_APPROVE:-false}" != "true" ]; then
    echo "🔒 $svc requires approval — pausing the pipeline here"
    exit 42                    # ⭐ the CD tool turns this into an input/approval
  fi

  kubectl -n $NS set image "deploy/$svc" "$svc=${REF[$svc]}"
  kubectl -n $NS rollout status "deploy/$svc" --timeout=600s

  # ⭐ CHECK 4 — read it back, per service, with the NAME FILTER
  NOW=$(kubectl -n $NS get deploy "$svc" \
        -o jsonpath="{.spec.template.spec.containers[?(@.name=='$svc')].image}")
  [ "$NOW" = "${REF[$svc]}" ] || { echo "⛔ $svc is running $NOW"; exit 1; }

  # ⭐ per-service smoke — each language has a different one
  smoke "$svc"
done

echo "✅ estate deployed: $(date -u)"
```

```bash
# ⭐ smoke() — because four services in three languages do not smoke alike
smoke() {
  case "$1" in
    payment-mock)
      kubectl -n $NS run s$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.17.0 -- \
        curl -fsS http://payment-mock:9093/healthz ;;
    shop-api)
      kubectl -n $NS run s$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.17.0 -- sh -c '
        curl -fsS http://shop-api:8080/actuator/health/readiness
        curl -fsS http://shop-api:8080/api/v2/orders' ;;          # ⭐ a BUSINESS endpoint
    checkout)
      kubectl -n $NS run s$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.17.0 -- sh -c '
        curl -fsS http://checkout:9091/readyz
        curl -fsS http://checkout:9091/healthz' ;;
    order-worker)
      # ⭐⭐ NO HTTP ENDPOINT — ask the BROKER instead
      curl -fsS -u "$RABBIT_USER:$RABBIT_PASS" \
        http://rabbitmq.$NS.svc:15672/api/queues/shop/orders \
        | jq -e '.consumers > 0 and .messages_ready < 1000' >/dev/null \
        || { echo "⛔ order-worker is not consuming"; return 1; } ;;
    shop-ui)
      kubectl -n $NS run s$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.17.0 -- sh -c '
        curl -fsS -o /dev/null http://shop-ui/
        curl -fsS http://shop-ui/config.js | grep -q "api.shop"
        curl -fsSI http://shop-ui/index.html | grep -qi "no-cache"' ;;
  esac
}
```

### 8.3 ⭐ Partial releases — the polyglot-specific question

```
QUESTION: shop-ui and checkout changed. shop-api, order-worker and
          payment-mock did not. Do you deploy all five?

⛔ DEPLOY ALL FIVE "FOR CONSISTENCY"
   → you redeploy the schema-owning service for a CSS change
   → 🔒 Case 1 approval for a frontend fix
   → the blast radius of a trivial change becomes the whole estate

✅ ⭐ DEPLOY ONLY WHAT CHANGED — and prove the rest is unchanged
   The manifest ALWAYS lists all five (so the estate is fully described),
   but each unchanged service's digest equals the digest ALREADY RUNNING.
   → `kubectl set image` with an identical image is a NO-OP:
     Kubernetes detects no change to the pod template and creates no new
     ReplicaSet. ⭐ Verify that, rather than assuming it.
   → the loop is uniform, the outcome is minimal.
```

```bash
# ⭐ PROVE the no-op, do not assume it
BEFORE=$(kubectl -n $NS get deploy shop-api -o jsonpath='{.metadata.generation}')
kubectl -n $NS set image deploy/shop-api shop-api="${REF[shop-api]}"   # same digest
AFTER=$(kubectl -n $NS get deploy shop-api -o jsonpath='{.metadata.generation}')
[ "$BEFORE" = "$AFTER" ] && echo "✅ no-op: generation unchanged, no new ReplicaSet" \
                         || echo "⚠️ the pod template changed — investigate"
# ⭐ `metadata.generation` increments ONLY when the spec changes. Comparing it
#   is the definitive test, where counting ReplicaSets is ambiguous.
```

### 8.4 ⭐ When the pipeline pauses mid-estate

`shop-api` and `order-worker` are 🔒 Case 1, so the loop above can **stop at an approval while three services are already deployed**. That is a real, reachable state.

| Mitigation | ⭐ What it buys |
|---|---|
| **Deploy the `auto` services first, then pause for the `approval` ones** | ⭐ reorder `ORDER` so approvals come last: `payment-mock, checkout, shop-ui, shop-api, order-worker`. But ⛔ that **violates rule A** (callee before caller) |
| ⭐ **Split into two manifests** | `release-manifest-auto.txt` (Case 2 services, dependency-ordered) and `release-manifest-gated.txt` (Case 1 services). The gated one is deployed as a unit, with the ordering rule preserved *within* it |
| ⭐⭐ **Make the estate tolerate a half-deployed state** | expand/contract everywhere (§7.3), so *any* subset of services at *any* two adjacent versions is a working system. This is the only real answer |
| **A `milestone` / `lock`** (Jenkins) or an environment gate (GitHub/AzDO) | ensures two deploys cannot interleave and produce a state nobody reasoned about |

```
⭐ THE HONEST ANSWER: if your services are expand/contract-clean, a
   half-deployed estate is FINE and you may deploy in any order.
   If they are not, no ordering saves you — you need the approvals to
   cover the WHOLE estate, which means 🔒 Case 1 for everything, which
   means nobody deploys on a Friday afternoon.
   ⭐ So the investment is in the contracts, not in the pipeline.
```

---

## 9 · 🔒 Case 1 or 🤖 Case 2 — per service

Applying the five prerequisites ([`../scenario-2-cd-only/00-delivery-vs-deployment.md`](../scenario-2-cd-only/00-delivery-vs-deployment.md) §6):

| Service | P1 reversible | P2 tests | P3 metrics | P4 digest | P5 migrations | ⭐ Verdict |
|---|---|---|---|---|---|---|
| `payment-mock` | ✅ 10 MB, 50 ms | ✅ | ✅ `/healthz` | ✅ | ✅ n/a | 🤖 **Case 2 — start here** |
| `checkout` | ✅ static binary | ✅ `-race` + ITs | ✅ `/readyz` | ✅ | ✅ n/a | 🤖 **Case 2** |
| `shop-ui` | ✅ static files | ✅ vitest + Lighthouse | ⚠️ needs RUM | ✅ | ✅ n/a | 🤖 **Case 2** |
| `order-worker` | ⚠️ in-flight messages | ⚠️ needs a broker | ⭐ heartbeat, not HTTP | ✅ | ✅ Alembic | 🔒 **Case 1** |
| `shop-api` | ⚠️ | ⭐ Testcontainers | ✅ | ✅ | ⛔ **until expand/contract** | 🔒 **Case 1** |
| **data tier** (P13) | ⛔ **stateful** | ⛔ | ✅ | n/a | ⛔ | 🔒🔒 **Case 1, always, forever** |

⭐ **The adoption order, and it is not arbitrary:** `payment-mock` → `checkout` → `shop-ui` → `order-worker` → `shop-api`. Each step adds exactly one new prerequisite you have to earn:
1. **`payment-mock`** — nothing new. Prove canary, analysis, `abort`, the circuit breaker and the drill where being wrong costs nothing.
2. **`checkout`** — proves a **compiled, statically-linked** service with `-race` coverage. Still no state.
3. **`shop-ui`** — proves 🤖 Case 2 for a service whose real client is a **browser you cannot recall** → forces RUM.
4. **`order-worker`** — the first service with **in-flight work** and no HTTP probe → forces idempotency and broker-based smoke checks.
5. **`shop-api`** — the schema owner → forces expand/contract migrations, and only then is automation honest.

⭐⭐ **Why the data tier is 🔒 forever:** a bad Postgres deploy destroys data with no rollback, and version upgrades are one-way — a newer server writes a data directory an older one cannot read. The only real rollback is a backup, and **a backup you have never restored is a hypothesis**. Upgrade a replica, check lag is zero, fail over, then upgrade the old primary; keep the old binary available; watch for 24 h. ⛔ Never `docker compose pull && up -d`.

---

## 10 · ▶️ Run it end to end — the acceptance checks

```bash
# ── 1 · CI cost is proportional to the change ─────────────────────────
git checkout -b t1 && echo "/* x */" >> apps/shop-ui/src/index.css
git commit -am "fe only" && git push && gh run watch --exit-status
gh run view --json jobs --jq '.jobs[] | "\(.name) \(.conclusion)"'
# ⭐ EXPECT: ui=success · checkout/api/worker/payment=skipped · repo=success
# ⛔ if `api` ran, the path filter is wrong and every commit costs 6 minutes

# ── 2 · ⭐⭐ a CONTRACT change rebuilds EVERY consumer ─────────────────
git checkout -b t2 main
echo '// comment' >> contracts/events/order-events.proto
git commit -am "contract touch" && git push && gh run watch || true
gh run view --json jobs --jq '.jobs[] | select(.name|test("ui|api|checkout|worker")) | "\(.name) \(.conclusion)"'
# ⭐ EXPECT: all four RAN (not skipped), because contracts/** changed

# ── 3 · ⭐⭐ the proto drift gate fires ────────────────────────────────
#    add a field to the .proto, DO NOT run buf generate, push
gh run view --json jobs --jq '.jobs[] | select(.name=="repo") | .conclusion'
# ⭐ EXPECT: failure, at "Regenerate and check for drift"

# ── 4 · ⭐ the breaking-proto gate fires ──────────────────────────────
#    CHANGE a field NUMBER (not add a field), regenerate, commit, push
gh run view --log | grep -i 'buf breaking' | tail -5
# ⭐ EXPECT: "field number changed" / "removed field" — a hard failure

# ── 5 · per-language caches are separate and effective ────────────────
gh run view --json jobs --jq '.jobs[] | "\(.name) \(.startedAt) \(.completedAt)"'
# ⭐ EXPECT: a warm Go build ~15 s, warm Java ~60–90 s, warm Node ~90 s
# ⛔ a cold Java build every time = the cache key or scope is wrong

# ── 6 · the manifest describes a COMPLETE estate ──────────────────────
gh run download <RID> -n release-manifest -D /tmp/m
wc -l /tmp/m/release-manifest.txt        # ⭐ 5 services + 1 order line
grep -c '@sha256:' /tmp/m/release-manifest.txt   # ⭐ 5
grep '^# order=' /tmp/m/release-manifest.txt

# ── 7 · ⭐ an unchanged service reuses the RUNNING digest ─────────────
kubectl -n shop-production get deploy shop-api \
  -o jsonpath="{.spec.template.spec.containers[?(@.name=='shop-api')].image}"
grep '^shop-api=' /tmp/m/release-manifest.txt
# ⭐ after a UI-only change these must be IDENTICAL

# ── 8 · ⭐⭐ `set image` with an identical digest is a NO-OP ───────────
B=$(kubectl -n shop-production get deploy shop-api -o jsonpath='{.metadata.generation}')
kubectl -n shop-production set image deploy/shop-api shop-api="$(grep '^shop-api=' /tmp/m/release-manifest.txt | cut -d= -f2)"
A=$(kubectl -n shop-production get deploy shop-api -o jsonpath='{.metadata.generation}')
[ "$B" = "$A" ] && echo "✅ no-op confirmed" || echo "⛔ the pod template changed"

# ── 9 · ⭐ the deploy ORDER is dependency-correct ─────────────────────
grep -n 'ORDER=' deploy-estate.sh
# ⭐ EXPECT: payment-mock shop-api checkout order-worker shop-ui
#    (leaf callee → schema owner → caller → consumer → browser)

# ── 10 · per-service policies are wired ───────────────────────────────
grep -A6 'POLICY=(' deploy-estate.sh
# ⭐ payment-mock/checkout/shop-ui=auto · shop-api/order-worker=approval

# ── 11 · the rollback covers the WHOLE estate, in REVERSE order ───────
grep -q 'trap rollback_all ERR' deploy-estate.sh && echo "✅ traps any failure"
grep -A3 'ROLLING BACK' deploy-estate.sh | grep 'for svc in'
# ⭐ EXPECT the reverse of ORDER

# ── 12 · ⭐ every service's smoke matches its LANGUAGE ────────────────
grep -A4 'order-worker)' deploy-estate.sh | grep -q 'rabbitmq' && echo "✅ worker smokes via the broker"
grep -A4 'shop-ui)' deploy-estate.sh | grep -q 'config.js' && echo "✅ FE smokes its runtime config"

# ── 13 · agent memory is sized per language ───────────────────────────
grep -q 'MaxRAMPercentage\|MAVEN_OPTS' .github/workflows/_ci-java.yml && echo "✅ JVM sized"
grep -q 'max-old-space-size' .github/workflows/_ci-node.yml && echo "✅ Node heap sized"

# ── 14 · the whole estate, one command ────────────────────────────────
for s in payment-mock shop-api checkout order-worker shop-ui; do
  printf '%-14s ' "$s"
  kubectl -n shop-production get deploy "$s" 2>/dev/null \
    -o jsonpath="{.spec.template.spec.containers[?(@.name=='$s')].image}" || printf '(missing)'
  echo
done
```

---

## 11 · Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| ⛔ Every commit runs all five builds | no path filters | §3, §4.1 — `dorny/paths-filter` per service |
| A contract change broke a service whose directory did not change | ⭐ the `contracts/**` filter is missing from that job's `if:` | §4.2 |
| Go publishes a field Python cannot read | generated code was not regenerated/committed | ⭐ §7.4 `buf generate && git diff --exit-code` |
| ⛔ An old message in the queue is misinterpreted | a field **number** was reused or changed | §7.2 — `reserved`, and `buf breaking` |
| The queue consumer breaks on every deploy | producer deployed before the tolerant consumer | ⭐ §7.3 — consumer first |
| `go test` says `(cached)` | Go's test cache | `-count=1` |
| ⛔ Maven build: `OutOfMemoryError: GC overhead limit exceeded` | agent too small / no `MAVEN_OPTS` | §6.1 — `-Xmx3g`, 6–8 GB agent |
| ⛔ `FATAL ERROR: Reached heap limit Allocation failed` | the Node default heap during `vite build` | ⭐ `NODE_OPTIONS=--max-old-space-size=6144` |
| The Jenkins agent is killed with "lost connection" | the pod hit its memory limit | `resources.limits.memory` on the pod template |
| ⛔ Two parallel Go builds corrupt each other | ⭐ `parallel` stages share one workspace | `dir('apps/checkout') { … }` (§4.3) |
| The manifest job is skipped | a skipped upstream reports `skipped`, not `success` | `if: always()` **plus** explicit verification that a changed service published |
| The manifest lists only changed services | it did not fall back to the running digest | §4.1 — always describe the **complete** estate |
| ⛔ A frontend fix required a schema-owner approval | one policy for the whole estate | §9 — split per service |
| The estate is stuck half-deployed at an approval | Case 1 and Case 2 services interleaved in one loop | ⭐ §8.4 — two manifests, or make the estate expand/contract-clean |
| `set image` created a new ReplicaSet for an unchanged service | the digest string differed (a tag, or a different registry) | ⭐ always compare **digests**, and verify with `metadata.generation` (§8.3) |
| ⛔ `kubectl exec` into the Go pod fails | `scratch` has no shell | `kubectl debug -it <pod> --image=busybox --target=checkout` |
| The JVM pod restart-loops on start | `livenessProbe` fires during warm-up | a `startupProbe` ([`05-be-only.md`](./05-be-only.md) §6.3) |
| Azure DevOps cannot loop over the service list | ⛔ template expressions are compile-time | one pipeline per service, or a fixed `parameters: services:` array |
| `buf breaking` passes but consumers break | it compared against the wrong base | `--against '.git#branch=main,subdir=contracts/events'` |
| A leaked secret in `k8s/` compromised every service | ⭐ in a monorepo the k8s tree is shared | the repo-wide secret grep (§4.1 `repo` job) |

---

<a name="tasks--answers"></a>
## 12 · ⭐ TASKS — answers at the END

| # | Task |
|---|---|
| **T1** | Derive the deploy order for the five-service estate from the dependency graph, and state the two rules that generate it |
| **T2** | Build the fan-out CI with path filters, and prove a CSS-only commit does not run `mvn verify` |
| **T3** | Add the `contracts/**` filter to every consumer job and prove a proto-only change rebuilds all of them |
| **T4** | Add `buf breaking` and the four-language `buf generate && git diff --exit-code` drift gate |
| **T5** | Write the four reusable CI units (`_ci-node`, `_ci-java`, `_ci-go`, `_ci-python`) with the correct cache scope and memory settings for each |
| **T6** | Size the build agents per language and fix both OOM failure modes |
| **T7** | Build the manifest so it always describes the **complete** estate, reusing running digests for unchanged services |
| **T8** | Write `deploy-estate.sh` with dependency order, per-service policy, per-service smoke, and roll-back-all in reverse |
| **T9** | Prove `set image` with an identical digest is a no-op, using a definitive test |
| **T10** | ⭐⭐ A field is added to `OrderEvent`. Give the exact deploy sequence that cannot lose or misinterpret a message, and explain why the obvious sequence fails |
| **T11** | Solve the "pipeline paused mid-estate at an approval" problem and state the honest limitation |

---

# ✅ ANSWERS

**T1.** §2.1. **Order: data tier (P13, separately and always 🔒) → `payment-mock` → `shop-api` → `checkout` → `order-worker` → `shop-ui`.** ⭐ **Rule A — callee before caller:** a service that is *called* must serve both the old and the new contract before its callers move. `payment-mock` is a leaf dependency of both `checkout` and `shop-api`, so it goes first; `shop-api` is called by `checkout` and by the browser, so it precedes both; `shop-ui` is last because **the browser is the least-recallable client** — the copy already open in a tab was delivered hours ago and its lifetime is controlled by cache, not by your pipeline. ⭐ **Rule B — producer before consumer, and it is the *opposite* of rule A for queues:** if `shop-api` starts publishing a new message *shape*, `order-worker` must already be able to read it — so the **tolerant consumer deploys first**, then the producer. **The unifying statement:** *the party that must tolerate the change deploys first.* For HTTP that is the callee (it must answer both old and new requests); for a queue it is the consumer (it must read both old and new messages). ⭐ The reason the two differ is that HTTP is request/response and ephemeral, while a queue is **stored** — a message published by a new producer can sit unread for minutes and be consumed by an old consumer.

**T2.** §4.1. A `changes` job using `dorny/paths-filter@v3` with `fetch-depth: 0` (⭐ required — a shallow clone cannot diff against the base), producing one output per service plus `contracts` and `any`. Each build job then has `needs: changes` and `if: needs.changes.outputs.<svc> == 'true'`. **Proving it:** commit a one-line change to `apps/shop-ui/src/index.css`, push, and inspect `gh run view --json jobs --jq '.jobs[] | "\(.name) \(.conclusion)"'`. ⭐ Expect `ui=success`, `repo=success`, and `api`/`checkout`/`worker`/`payment` = **skipped**. **Why this matters more in a polyglot repo than in a single-language one:** the build times differ by 10× (Go 40 s vs Java 6–8 min cold), so without filters a CSS change costs twenty minutes — and at twenty minutes people stop reading CI output, at which point CI has become a formality that provides no safety. **The trap to check:** a skipped job reports `skipped`, **not** `success`, so any downstream job with a default `if:` will also be skipped. The manifest job therefore needs `if: always()` **and** an explicit verification that a service which should have built actually published a digest (§4.1) — otherwise a broken path filter silently ships a partial release train.

**T3.** §4.2. Add `|| needs.changes.outputs.contracts == 'true'` to the `if:` of **every consumer job** (`ui`, `api`, `checkout`, `worker`) and add `contracts: ['contracts/**']` to the filter block. **Proving it:** touch `contracts/events/order-events.proto` with a comment only — no service directory changes — push, and confirm all four build jobs **ran** rather than being skipped. ⭐ **The failure this prevents, stated precisely:** without the filter, a proto change that adds field 4 rebuilds only the services whose *directories* changed. Suppose the author regenerated `order-worker`'s code but not `checkout`'s: `checkout`'s job is skipped, its generated code is stale, it publishes messages **without** field 4, and `order-worker` reads a zero value. **Every CI job that ran was green**, and the defect is silent data loss discovered days later. This is the polyglot version of "both suites green, production broken" (§06 T10), and the `contracts/**` filter plus the drift gate in T4 are what close it.

**T4.** §7.4, inside the repo-wide `repo` job. **Two checks.** ⭐ **(a) `buf breaking contracts/events --against '.git#branch=main,subdir=contracts/events'`** — compares the working tree's protos against main and **fails** on a removed field, a changed field number, a changed field type, a reused `reserved` number, a removed enum value, or a renamed package; **allows** a new field, a new enum value, or a new message. It is `openapi-diff` for protobuf. ⭐ **(b) `buf generate && git diff --exit-code`** for each of the three target languages (Go, Python, TypeScript), so generated code must be regenerated **and committed** in the same PR. **Plus `buf lint`** for style consistency. **Why (b) needs `--exit-code` and not a warning:** generated code that drifts from its schema is invisible at runtime — the Go struct simply lacks the field, and the compiler is happy because nothing references it. A warning gets read once; a failing build cannot be merged. ⭐ **Why (a) is not redundant with (b):** (b) proves the generated code matches the *current* proto; (a) proves the current proto is *compatible with the previous* one. A change can pass (b) perfectly and still break every in-flight message in the queue — which is the failure mode that has no rollback, because the messages are **stored**.

**T5.** §4 and §5. Four `workflow_call` reusable workflows, each taking `app`, `image` and (where relevant) `port`, and each pinned and cached correctly. ⭐ **Node (`_ci-node.yml`):** `actions/setup-node@v6` with `node-version-file: apps/shop-ui/.nvmrc` and `cache: npm` + `cache-dependency-path: apps/shop-ui/package-lock.json`; `npm ci` (⛔ never `npm install`); `vitest run --coverage` with thresholds; `eslint` + `prettier --check`; a bundle-size gate; and ⭐ `NODE_OPTIONS=--max-old-space-size=6144` for `vite build`. Cache scope `scope=shop-ui`. ⭐ **Java (`_ci-java.yml`):** `setup-java@v5` with `distribution: temurin, java-version: '21', cache: maven`; `./mvnw -B -ntp verify -DskipITs`, then a separate ITs step with **Testcontainers** against a real Postgres 17; `spotbugs:check` + `checkstyle:check`; `dependency-check-maven:check`; the migration-shadow check; ⭐ `MAVEN_OPTS=-Xmx3g -XX:MaxMetaspaceSize=512m`. Cache scope `scope=shop-api`. ⭐ **Go (`_ci-go.yml`):** `setup-go@v6` with `go-version: '1.25.0'` and `cache-dependency-path: <app>/go.sum`; `go vet` + `golangci-lint`; ⭐ `go test -race -count=1 -covermode=atomic`; a coverage gate parsing `go tool cover -func`; `govulncheck`; `CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w"`. ⭐ **Python (`_ci-python.yml`):** `setup-python@v6` + `astral-sh/setup-uv@v7` with `enable-cache` and `cache-dependency-glob: <app>/uv.lock`; ⭐ `uv sync --frozen --all-extras`; `ruff check` + `ruff format --check` + `mypy`; a **real RabbitMQ** (service container or `RabbitMqContainer`); `pytest --cov-fail-under=80`; `pip-audit --strict` + `bandit -r src/ -ll`. **All four end identically:** build with `cache-from/to: type=gha,scope=<image>,mode=max`, `provenance: mode=max`, `sbom: true`, Trivy `exit-code: 1 --severity CRITICAL,HIGH --ignore-unfixed`, `cosign sign`, and emit `<image>@<digest>` into an `image-digest` artifact. ⭐ **The point:** the *stages* differ per language; the *artifact contract* does not. That is why four reusable workflows and one manifest job is the right decomposition rather than one giant job.

**T6.** §6. ⭐ **Two distinct OOM failure modes, and they look different.** **(a) The JVM:** `java.lang.OutOfMemoryError: GC overhead limit exceeded`, or Maven forked Surefire dies mid-suite. Fix with `MAVEN_OPTS="-Xmx3g -XX:MaxMetaspaceSize=512m"` **and** an agent with 6–8 GB. **(b) Node:** `FATAL ERROR: Reached heap limit Allocation failed - JavaScript heap out of memory` during `vite build` — bundling a large React app exceeds Node's default heap. Fix with `NODE_OPTIONS="--max-old-space-size=6144"`. ⭐ **A third, easily-missed one:** the **agent itself** is killed and Jenkins reports "agent lost connection" or GitHub reports the runner "exited unexpectedly" — this is the pod hitting `resources.limits.memory`, not the toolchain. Fix by setting both `requests` and `limits` on the pod template (requests 6Gi/limits 8Gi for Maven), because ⛔ with only a limit and no request the scheduler places the pod on a node that cannot hold it. **Why per-language agents rather than one fat image:** versions stay independent (Java 21→25 without touching Node), resources are right-sized (Maven 8 GB, Go 2 GB — one fat agent must request the maximum for every build), and the image stays small instead of being a 3 GB pull on every build. **The cost:** four pod templates to maintain, and a cross-language build needs two containers in one pod.

**T7.** §4.1's `manifest` job. Loop over the **full service list** (`payment-mock shop-api checkout order-worker shop-ui`), not over what changed: for each, use `/tmp/<svc>/digest.txt` if CI produced one, otherwise read the digest currently running — `kubectl -n shop-production get deploy <svc> -o jsonpath="{.spec.template.spec.containers[?(@.name=='<svc>')].image}"`. Then assert every entry matches `@sha256:` and append an `# order=…` line. ⭐ **Why always complete:** the manifest is the CD's **only** input, so a manifest listing three services forces CD to invent the other two — and "invent" means "use `latest`", which is the trap this whole folder exists to remove. A complete manifest means CD is a uniform loop with no special cases. ⭐ **Why read from the cluster rather than from the previous manifest:** the cluster is the *actual* current state and stays correct after a manual hotfix, a rollback or a partially-applied release — all of which make a stored "last manifest" stale. **Two subtleties:** the job needs `if: always()` because a skipped CI job reports `skipped` not `success`; and it must verify that a service which *should* have built *did* (`|| exit 1` in the changed branch), or a broken path filter ships a partial train. In Azure DevOps, `resources.pipelines` with several entries triggers when **any** completes, so the same fallback is required defensively.

**T8.** §8.2. Parse the manifest into `REF[]`, validate every value is `@[a-z0-9]+:[0-9a-f]{64}$`, and record `PREV[]` for **every** service (⭐ that record *is* the rollback). `trap rollback_all ERR`. Loop over `ORDER="payment-mock shop-api checkout order-worker shop-ui"` and per service: ⭐ **check 1/2** `cosign verify` with `--certificate-identity-regexp` pinned to the CI workflow on `main`; ⭐ **check 3** assert staging ran **this digest for this service**; the migration Job (gated, `kubectl wait --for=condition=complete`) only for `shop-api`; the policy gate (`approval` → `exit 42`, which the CD tool turns into an input/environment approval); `set image`; `rollout status`; ⭐ **check 4** read back with the JSONPath **name filter** `[?(@.name=='<svc>')]`; then `smoke "$svc"`. ⭐ **`rollback_all` iterates in REVERSE order** — `shop-ui order-worker checkout shop-api payment-mock` — so the callee stays compatible with the caller at every step of the undo, mirroring rule A. **`smoke()` is a `case` per service, because four services in three languages do not smoke alike:** `payment-mock` and `checkout` hit `/healthz` and `/readyz`; `shop-api` hits `/actuator/health/readiness` **and a business endpoint** (`/api/v2/orders`); ⭐ `order-worker` has **no HTTP endpoint at all**, so it queries the RabbitMQ management API and asserts `.consumers > 0 and .messages_ready < 1000` — a worker that connects but never consumes shows `consumers=1, ready=∞` and would pass an HTTP-style probe; `shop-ui` checks it serves, that `config.js` points at **this** environment's API, and that `index.html` is `no-cache`.

**T9.** §8.3. **The definitive test is `metadata.generation`.** Read it before, run `kubectl set image` with the identical digest, read it after: equal ⇒ no-op. ⭐ **Why generation and not ReplicaSet counting:** `metadata.generation` increments **only when `.spec` changes**, so it is exactly the property you want to test; counting ReplicaSets is ambiguous (a stale one may linger within `revisionHistoryLimit`), and `rollout status` returns immediately and proves nothing. **The other way to see it:** `kubectl get rs -l app=shop-api --sort-by=.metadata.creationTimestamp -o wide` — no **new** ReplicaSet with a fresh timestamp, and the existing one's `DESIRED` unchanged. ⭐ **Why this matters for partial releases:** it is what makes "deploy the complete manifest every time" safe and cheap. An unchanged service's digest equals the running digest, `set image` writes the same value, Kubernetes detects no pod-template change, creates no ReplicaSet, restarts no pod. The loop stays uniform; the outcome stays minimal. **The one way it silently fails:** if the manifest holds a **tag** (`:sha-abc123`) rather than a digest, or a different registry path, the strings differ and the pod template changes — which is why check 0 in every file here is "is it a digest?".

**T10.** ⭐⭐ **Adding `discount_cents` to `OrderEvent`.** **The sequence that cannot lose or misinterpret a message:**
1. ⭐ **Regenerate and commit code in all consumers first** — `buf generate` for Python, Go and TS; the drift gate (T4) enforces this in the same PR.
2. **Make `order-worker` tolerant:** read `discount_cents` if present, default to `0` if absent. Deploy it. ⭐ **The consumer moves first.**
3. **Then make `checkout` emit it.** Deploy it.
4. Only after telemetry confirms no old consumers remain, treat the field as always-present.

**Why the obvious sequence fails — and the answer has two layers.** The *obvious* sequence is producer-first: change the proto, deploy `checkout`, then deploy `order-worker`. ⭐ **For a purely additive proto3 field, producer-first is actually wire-safe** — an unknown field is **preserved and ignored** by the old consumer, so nothing is lost. That is why people get away with it, and it is the reason the trap is subtle. **The failure is semantic, not syntactic:** between step 3 and the consumer deploy, `checkout` is publishing `discount_cents=500` and `order-worker` is computing totals **without** it. Every order processed in that window is *wrong*, correctly, silently — and because a queue is **stored**, the affected messages may already be acknowledged and gone by the time you notice. There is no rollback: redeploying does not reprocess them. ⛔ **And for any change that is not purely additive** — a changed field number, a repurposed field, a removal, a type change — producer-first is a hard corruption, which is what `buf breaking` exists to refuse at build time. **The general rule (§7.3):** *the party that must tolerate the change deploys first.* For a queue that is the **consumer**, which is the opposite of HTTP's callee-first ordering — and the difference exists because HTTP is ephemeral while a queue stores messages across deploys. **The removal case is the mirror image:** make the consumer stop *reading* the field, deploy, then stop *emitting* it. Doing it the other way leaves the consumer reading a zero value, which is the same silent-wrongness with no error.

**T11.** §8.4. **The state is real and reachable:** with `shop-api` and `order-worker` under 🔒 approval, the loop can stop at an approval while `payment-mock`, `checkout` and `shop-ui` are already deployed. **Four mitigations, in increasing order of honesty.** ⭐ **(a) Split into two manifests** — `release-manifest-auto.txt` (Case 2 services, dependency-ordered among themselves) and `release-manifest-gated.txt` (Case 1 services, ordered among themselves). The gated set deploys as one unit under one approval, so an approval never leaves a *gated* service half-applied. ⛔ **(b) Reorder so approvals come last** looks simpler but **violates rule A** — deploying `shop-ui` before `shop-api` guarantees the skew window of §06 §1, so it is not acceptable. ⭐ **(c) A `milestone`/`lock` (Jenkins) or an environment gate (GitHub/AzDO)** so two deploys cannot interleave and produce a state nobody reasoned about — necessary but not sufficient. ⭐⭐ **(d) The only real answer: make the estate expand/contract-clean**, so *any* subset of services at *any* two adjacent versions is a working system. Then a half-deployed estate is simply fine and the order stops being load-bearing for correctness (it remains useful for minimising the window). **The honest limitation to state:** if the contracts are **not** expand/contract-clean, no ordering saves you — you need the approval to cover the **whole** estate, which means 🔒 Case 1 for everything, which means the frontend waits for a change board and people start approving without reading, which degrades the gate for the services that genuinely need it. ⭐ **So the investment is in the contracts, not in the pipeline** — the same conclusion §06 reaches for the two-service case, and it scales: a polyglot estate's deployability is a property of its `.proto` and `.yaml` files, not of its CI tool.

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish_Kumar_Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn: https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260
🔗 GitHub: https://github.com/3558Bhk

*Three languages, one contract. HTTP deploys callee-first; a queue deploys consumer-first. Get that backwards and the messages are already gone.*

</div>
