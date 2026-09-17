# 🟡 SCENARIO 3 · FRONTEND + BACKEND, ONE STACK — CI + CD END TO END
### Docker/K8s P10: `shop-ui` (React 19) + `shop-api` (Java 21 / Spring Boot). The release manifest, expand/contract, backend-first ordering, and the contract test that makes the pair safe.

> **The shape:** two services, two languages, **one deployable unit** — because a new frontend calling an old backend (or the reverse) is a state nobody tested.
> **The central problem:** ⭐⭐ **version skew.** Two artifacts, deployed non-atomically, serving users whose browsers hold the *previous* frontend for as long as cache dictates.

---

## 📇 Contents

| § | What |
|---|---|
| [1](#1---the-problem-version-skew) | ⭐⭐ The problem: version skew — the timeline that breaks production |
| [2](#2--the-four-defences) | The four defences, in order of importance |
| [3](#3---expandcontract--the-discipline-that-removes-the-problem) | ⭐⭐ Expand/contract — the discipline that removes the problem |
| [4](#4---the-architecture-two-ci-one-manifest-one-cd) | ⭐ The architecture: two CI, one manifest, one CD |
| [5](#5--the-release-manifest) | The release manifest — the atomic pair |
| [6](#6---the-contract-test) | ⭐⭐ The contract test — the only thing that proves the pair agrees |
| [7](#7--ci--github-actions) | CI — GitHub Actions, both services plus the manifest job |
| [8](#8--ci--azure-devops-and-jenkins) | CI — Azure DevOps and Jenkins, the differences that matter |
| [9](#9---cd--the-ordered-pair) | ⭐ CD — the ordered pair, one approval, roll-back-both |
| [10](#10---case-1-or--case-2---split-them) | 🔒 Case 1 or 🤖 Case 2 — ⭐ **split them** |
| [11](#11--️-run-it-end-to-end--the-acceptance-checks) | ▶️ Run it end to end — the acceptance checks |
| [12](#12--troubleshooting) | Troubleshooting |
| [13](#13---tasks--answers-at-the-end) | Tasks and answers — **answers at the END** |

---

## 1 · ⭐⭐ The problem: version skew

```
t0  FE v1  calls GET /api/v1/orders        BE v1  serves it            ✅
t1                                          BE v2  REMOVES /api/v1/orders
t2  FE v1  (still open in 40,000 browsers) ─▶ BE v2                     ⛔ 404
t3  FE v2  deployed                         BE v2                       ✅
    ⭐ BETWEEN t1 AND t3, EVERY USER WITH AN OPEN TAB IS BROKEN.

    And the length of that window is NOT controlled by your pipeline.
    It is controlled by:
      • how long a browser keeps a tab open        (hours)
      • how long index.html is cached              (your nginx config)
      • how long a Service Worker caches           (if you have one)
      • how long a CDN caches                      (your TTL)
    ⭐ It is measured in HOURS, not in the 90 seconds your rollout takes.
```

**Why the pipeline cannot fix this:** you can deploy the backend and the frontend 90 seconds apart, and be *atomic* from Kubernetes' point of view. But the frontend that matters is not the one in the cluster — it is the one **already running in the user's browser**. That copy was delivered hours ago and you cannot recall it.

⭐ **This is the key insight of the whole shape:** for a frontend+backend pair, "atomic deployment" is not achievable, so **backward compatibility is not optional** — it is the only mechanism available.

---

## 2 · The four defences

| # | Defence | What it means | Where it lives |
|---|---|---|---|
| **1** | ⭐⭐ **Expand / contract** (parallel change) | BE **adds** the new thing and **keeps** the old. FE migrates. A **later** release removes the old. **No single deploy is ever breaking** | the API design, enforced in review |
| **2** | ⭐ **Deploy order: BE first, then FE** | the backend must serve *both* frontends at all times. The reverse order guarantees a breakage window | the CD pipeline (§9) |
| **3** | ⭐ **API versioning in the path** | `/api/v1/…`, `/api/v2/…`, served **concurrently** | the API design |
| **4** | **A contract test** | CI proves FE's *actual* expectations against BE's *actual* responses, before either is deployed | §6 |

**Plus two that make failure detectable rather than silent:**

| # | Mechanism | Effect |
|---|---|---|
| **5** | ⭐ `contract-version` declared by both sides | a mismatch is **detected**, not guessed |
| **6** | ⭐ Graceful degradation in the FE | a 404 on one endpoint shows "please refresh", not a blank page |

---

## 3 · ⭐⭐ Expand/contract — the discipline that removes the problem

```
✅ THREE RELEASES, EACH INDEPENDENTLY SAFE AND INDEPENDENTLY REVERTIBLE

RELEASE 1 (backend only)
   ADD   GET /api/v2/orders        returning {orderId, quantity, totalCents}
   KEEP  GET /api/v1/orders        returning {orderId, qty, total}
   ⭐ old FE works. new FE would work. NOTHING BREAKS.
   ⭐ revertible: remove v2. Nobody was using it.

RELEASE 2 (frontend only)
   SWITCH the frontend to /api/v2/orders
   ⭐ v1 is now unused but STILL SERVED, so a cached v1 frontend still works.
   ⭐ revertible: ship the old frontend digest again. v1 is still there.

RELEASE 3 (backend only) — LATER, and only after evidence
   REMOVE GET /api/v1/orders
   ⭐ ONLY after telemetry shows zero v1 traffic for N days.
   ⭐ revertible: add v1 back. Expensive but possible.

⛔ THE SINGLE-RELEASE VERSION
   ONE PR that changes the endpoint in the backend AND the call in the frontend.
   It looks CLEANER. It is more reviewable. It is smaller.
   ⛔ AND IT IS NOT DEPLOYABLE WITHOUT A BREAKING WINDOW — because the two
     halves roll out over minutes (and the browser half over hours), and
     never atomically.
```

### 3.1 The same discipline for a field rename

```
⛔ BREAKING:      orders.qty  →  orders.quantity        (one release)

✅ EXPAND/CONTRACT — three releases:
   1. BE accepts BOTH `qty` and `quantity` on input; emits BOTH on output.
      ⭐ old FE sends `qty`, still works.
   2. FE sends `quantity`, reads `quantity`.
      ⭐ `qty` is still accepted AND still emitted, so a cached old FE works.
   3. BE stops accepting/emitting `qty`.
      ⭐ ONLY after telemetry confirms zero `qty` traffic.
```

### 3.2 ⭐ The rule that makes it enforceable

```
A BACKEND CHANGE IS DEPLOYABLE IF AND ONLY IF:
   the PREVIOUS frontend works against the NEW backend.

A FRONTEND CHANGE IS DEPLOYABLE IF AND ONLY IF:
   the NEW frontend works against the CURRENT (previous) backend.

⭐ BOTH DIRECTIONS. That is what "no single deploy is ever breaking" means,
  and it is a REVIEW QUESTION, not a pipeline feature. No CI system can
  save you from a breaking change deployed atomically — but §6's contract
  test can FAIL THE BUILD when it happens.
```

---

## 4 · ⭐ The architecture: two CI, one manifest, one CD

```
OPTION 1 — TWO INDEPENDENT PIPELINES
   apps/shop-ui/**  → ci-shop-ui  → digest-ui
   apps/shop-api/** → ci-shop-api → digest-api
   ✅ fastest feedback, smallest blast radius
   ⛔ CANNOT guarantee FE and BE are deployed as a compatible PAIR

OPTION 2 — ONE PIPELINE, TWO ARTIFACTS
   any change → ci-monorepo → {digest-ui, digest-api} → one manifest
   ✅ the manifest is an atomic compatible pair
   ⛔ a CSS typo rebuilds and re-tests the Java service (6 minutes)

OPTION 3 — ⭐⭐ TWO CI PIPELINES + ONE MANIFEST JOB + ONE CD PIPELINE
   ci-shop-ui  → digest-ui  ─┐
                             ├→ manifest job → release-manifest.txt
   ci-shop-api → digest-api ─┘         │
                                       ▼
                                 cd-shop-pair  (ordered: api → ui)
   ✅ fast per-service feedback AND an atomic pair AND one deploy decision
   ⚠️ needs a rule for "which digests go together?" — §5.2
```

**Why Option 3:** it keeps CI fast and independent (a frontend change does not run `mvn verify`), while making the **deployment unit** the pair — which is what the skew problem demands.

---

## 5 · The release manifest

### 5.1 The file

```text
# release-manifest.txt — ⭐ ONE file, ONE atomic compatible pair
# release    2026.09.16-1
# contract   2                  ← ⭐⭐ the field that makes skew DETECTABLE
# commit     41ab7c9
shop-api=ghcr.io/3558bhk/shop-api@sha256:41ab7c9e…
shop-ui=ghcr.io/3558bhk/shop-ui@sha256:9f2c1d4a…
```

```json
{
  "release": "2026.09.16-1",
  "contractVersion": 2,
  "commit": "41ab7c9",
  "createdAt": "2026-09-16T09:12:44Z",
  "services": {
    "shop-api": {
      "image": "ghcr.io/3558bhk/shop-api@sha256:41ab7c9e…",
      "migrations": ["V12__add_quantity_column.sql"],
      "backwardCompatible": true,
      "servesContractVersions": [1, 2]
    },
    "shop-ui": {
      "image": "ghcr.io/3558bhk/shop-ui@sha256:9f2c1d4a…",
      "requiresContractVersion": 2,
      "migrations": []
    }
  },
  "deployOrder": ["shop-api", "shop-ui"]
}
```

### 5.2 ⭐ `contract-version` — how skew becomes detectable

```
BACKEND  publishes GET /api/contract-version → {"version": 2, "serves": [1,2]}
FRONTEND is built with CONTRACT_VERSION=2 and checks it AT STARTUP:

  fetch('/api/contract-version')
    .then(r => r.json())
    .then(({ serves }) => {
      if (!serves.includes(MY_CONTRACT_VERSION)) {
        // ⭐ the backend cannot serve me. Do not render a wall of 404s.
        showRefreshBanner('A new version is available — reload to continue.');
      }
    });
```

| Property | ⭐ Why it matters |
|---|---|
| It converts a **silent** failure into a **detected** one | the user sees "please refresh" instead of a broken page |
| It is checkable in **CD** | refuse to promote a pair whose contract versions are incompatible |
| It gives you telemetry | "how many clients are still on contract 1?" answers *when release 3 is safe* |
| ⭐ It does **not** make deployment atomic | nothing can. It makes incompatibility **visible** |

### 5.3 ⭐ The "which digests go together?" rule

| Rule | Effect |
|---|---|
| The manifest job runs when **both** CI pipelines have succeeded for the same commit | ⭐ the pair is defined by the **commit**, not by time |
| If only one service changed, the manifest reuses the **currently deployed** digest for the other | ⭐ so a frontend-only change does not redeploy the backend |
| The manifest is **committed to git** (or published as an artifact) | the pair is durable and auditable |
| CD takes **the manifest**, not two digests | one input, one decision, one atomic unit |

```yaml
# ⭐ resolving "the other service's current digest" — the key trick
- name: Build the manifest
  run: |
    set -euo pipefail
    # shop-api changed in this commit? use CI's new digest. Otherwise reuse
    # ⭐ what is ALREADY RUNNING in production — read from the cluster.
    if [ "${{ needs.changes.outputs.api }}" = "true" ]; then
      API_REF=$(cat /tmp/api/digest.txt)
    else
      API_REF=$(kubectl -n shop-production get deploy shop-api \
        -o jsonpath="{.spec.template.spec.containers[?(@.name=='shop-api')].image}")
      echo "ℹ️ shop-api unchanged — reusing the running digest $API_REF"
    fi
    # …the same for shop-ui…
    printf 'shop-api=%s\nshop-ui=%s\n' "$API_REF" "$UI_REF" > release-manifest.txt
```

---

## 6 · ⭐⭐ The contract test

**The problem it solves:** unit tests prove each side works against **its own assumptions**. Nothing proves the two sides' assumptions **agree**. A green FE suite and a green BE suite can still 404 in production.

```
        FRONTEND                              BACKEND
   ┌──────────────────┐                  ┌──────────────────┐
   │ "I will POST     │                  │ "I accept        │
   │  /api/v2/orders  │                  │  /api/v2/orders  │
   │  {sku, qty}"     │                  │  {sku, quantity}"│
   └────────┬─────────┘                  └────────┬─────────┘
            │   ⛔ BOTH TEST SUITES ARE GREEN      │
            │   ⛔ PRODUCTION RETURNS 400          │
            └──────────────┬──────────────────────┘
                           ▼
              ⭐ THE CONTRACT TEST CATCHES IT IN CI
```

### 6.1 The cheap 80% — `openapi-diff` in the backend's CI

```yaml
# ── in ci-shop-api.yml ─────────────────────────────────────────────────
- name: ⭐⭐ Fail on a BREAKING API change
  run: |
    set -euo pipefail
    # the previous released spec, stored as an artifact / in git
    curl -fsSL "$PREV_SPEC_URL" -o /tmp/old-openapi.json
    ./mvnw -B -ntp spring-boot:run -Dspring-boot.run.arguments=--dump-openapi &
    sleep 40
    curl -fsS localhost:8080/v3/api-docs -o /tmp/new-openapi.json
    npx @openapitools/openapi-diff /tmp/old-openapi.json /tmp/new-openapi.json \
      --fail-on-incompatible
    # ⛔ BREAKING: removed a property · narrowed a type · made an optional
    #             field required · removed an endpoint · removed an enum value
    # ✅ NON-BREAKING: added an optional field · widened a type · added an
    #                 endpoint · added an enum value
```

⭐ **This is the single highest-value line you can add to a shape-C pipeline.** Ten minutes of setup, and it converts "the frontend broke in production" into "the backend build failed, naming the removed field".

### 6.2 ⭐ The frontend half — regenerate the client and fail on drift

```yaml
# ── in ci-shop-ui.yml ──────────────────────────────────────────────────
- name: ⭐ Regenerate the API client from the backend's spec
  run: |
    set -euo pipefail
    curl -fsSL "$BE_SPEC_URL" -o /tmp/openapi.json
    npx openapi-typescript /tmp/openapi.json -o src/api/schema.d.ts
    # ⭐⭐ if the regenerated file DIFFERS from what is committed, the backend
    #   changed the contract and the frontend has NOT caught up. FAIL.
    if ! git diff --exit-code src/api/schema.d.ts; then
      echo "::error::⛔ API contract drifted — regenerate src/api/schema.d.ts"
      git diff src/api/schema.d.ts
      exit 1
    fi
```

### 6.3 ⭐⭐ The strong version — consumer-driven contracts (Pact)

```
1. the CONSUMER (frontend) records what it ACTUALLY does:
     "I will POST /api/v2/orders with {sku: string, qty: int}
      and expect 201 with {orderId: string}"
   → produces a PACT FILE (JSON), published as a CI artifact

2. the PROVIDER (backend) VERIFIES the pact against its REAL running code:
     → replays each recorded interaction, asserts the real response matches
     → ⭐ runs in the BACKEND's CI, against the real controller

3. the broker records compatibility:
     → "shop-api v2.4.1 satisfies shop-ui v1.9.0's contract"
     → ⭐⭐ CD can then REFUSE to promote an incompatible pair
```

| Property | ⭐ Why it matters |
|---|---|
| The provider is tested against the consumer's **real** expectations | not a hand-written mock that also drifted |
| The pact file is **versioned and stored** | you can ask "does BE candidate X satisfy the FE version in production *right now*?" |
| ⭐ It runs in **both** pipelines | the consumer generates; the provider verifies |
| It is the answer to "when is release 3 safe?" | the broker tells you which consumers still expect v1 |

### 6.4 Which one?

| Option | Effort | Catches | ⭐ Verdict |
|---|---|---|---|
| ⛔ Hand-written TS interfaces mirroring Java DTOs | none | nothing | the default, and the reason skew incidents happen |
| ⭐ `openapi-diff --fail-on-incompatible` | 10 min | removed/retyped/narrowed fields | **do this first, today** |
| ⭐ Generate the TS client from OpenAPI + `git diff --exit-code` | 30 min | the frontend not keeping up | **do this second** |
| ⭐⭐ Pact / consumer-driven contracts | a day | everything above, plus *which* consumers still need v1 | when you have more than one consumer, or a release-3 question |

---

## 7 · CI — GitHub Actions

### 7.1 Change detection (so a CSS typo does not run `mvn verify`)

`.github/workflows/ci-shop-pair.yml`

```yaml
name: CI · shop pair
on:
  push:         { branches: [main] }
  pull_request: { branches: [main] }
permissions: { contents: read }

jobs:
  # ── ⭐ WHICH SERVICES CHANGED? ───────────────────────────────────────
  changes:
    runs-on: ubuntu-latest
    outputs:
      api: ${{ steps.f.outputs.api }}
      ui:  ${{ steps.f.outputs.ui }}
    steps:
      - uses: actions/checkout@v7
        with: { fetch-depth: 0 }          # ⭐ needed for a real diff
      - uses: dorny/paths-filter@v3
        id: f
        with:
          filters: |
            api:
              - 'apps/shop-api/**'
              - 'contracts/openapi.yaml'   # ⭐ a contract change affects BOTH
            ui:
              - 'apps/shop-ui/**'
              - 'contracts/openapi.yaml'
            shared:
              - 'k8s/**'
              - '.github/workflows/ci-shop-pair.yml'

  # ── the two builds, IN PARALLEL, only when relevant ──────────────────
  api:
    needs: changes
    if: needs.changes.outputs.api == 'true'
    uses: ./.github/workflows/_ci-java.yml
    with: { app: apps/shop-api, image: shop-api }
    permissions: { contents: read, packages: write, id-token: write }

  ui:
    needs: changes
    if: needs.changes.outputs.ui == 'true'
    uses: ./.github/workflows/_ci-node.yml
    with: { app: apps/shop-ui, image: shop-ui }
    permissions: { contents: read, packages: write, id-token: write }

  # ── ⭐⭐ THE MANIFEST JOB — the atomic pair ─────────────────────────
  manifest:
    name: ⭐ Build the release manifest
    needs: [changes, api, ui]
    if: always() && github.event_name == 'push' && github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    permissions: { contents: read, packages: read }
    outputs:
      manifest: ${{ steps.m.outputs.manifest }}
    steps:
      - uses: actions/checkout@v7
      - name: Resolve both digests
        id: m
        env: { GH_TOKEN: "${{ secrets.GITHUB_TOKEN }}" }
        run: |
          set -euo pipefail
          # ⭐ for each service: the NEW digest if it changed, otherwise the
          #   digest CURRENTLY RUNNING in production (read from the cluster).
          resolve() {
            local svc="$1" changed="$2" job="$3"
            if [ "$changed" = "true" ]; then
              gh run download "${{ github.run_id }}" -n "image-digest-$svc" -D "/tmp/$svc" 2>/dev/null \
                || { echo "::error::$svc changed but published no digest"; exit 1; }
              cat "/tmp/$svc/digest.txt"
            else
              kubectl -n shop-production get deploy "$svc" \
                -o jsonpath="{.spec.template.spec.containers[?(@.name=='$svc')].image}"
            fi
          }
          API=$(resolve shop-api "${{ needs.changes.outputs.api }}" api)
          UI=$(resolve  shop-ui  "${{ needs.changes.outputs.ui }}"  ui)

          # ⭐⭐ CHECK THE CONTRACT VERSIONS ARE COMPATIBLE
          API_CV=$(crane export "$API" - | tar -xO app/contract-version 2>/dev/null || echo 2)
          UI_CV=$(crane export "$UI"  - | tar -xO usr/share/nginx/html/contract-version 2>/dev/null || echo 2)
          [ "$API_CV" = "$UI_CV" ] || [ "$API_CV" -gt "$UI_CV" ] \
            || { echo "::error::⛔ contract mismatch: BE serves $API_CV, FE requires $UI_CV"; exit 1; }
          # ⭐ the backend may serve MORE than the frontend requires (it keeps
          #   old versions during expand/contract). The frontend may NOT require
          #   more than the backend serves.

          cat > release-manifest.txt <<EOF
          # release  $(date -u +%Y.%m.%d)-${{ github.run_number }}
          # contract $UI_CV
          # commit   ${{ github.sha }}
          shop-api=$API
          shop-ui=$UI
          EOF
          cat release-manifest.txt
          echo "manifest<<EOF" >> "$GITHUB_OUTPUT"
          cat release-manifest.txt >> "$GITHUB_OUTPUT"
          echo "EOF" >> "$GITHUB_OUTPUT"
      - uses: actions/upload-artifact@v4
        with: { name: release-manifest, path: release-manifest.txt, retention-days: 90 }

  # ── ⭐ trigger CD with the MANIFEST, not two digests ─────────────────
  trigger-cd:
    needs: manifest
    runs-on: ubuntu-latest
    permissions: { actions: write }
    steps:
      - env: { GH_TOKEN: "${{ secrets.GITHUB_TOKEN }}" }
        run: |
          gh workflow run cd-shop-pair.yml \
            -f manifest='${{ needs.manifest.outputs.manifest }}' \
            -f reason="commit ${{ github.sha }}"
```

⭐ **Two subtleties in `resolve()`:**
- **`always()` on the manifest job** is required because a skipped `api` job reports `skipped`, not `success`, and the default `if:` would skip the manifest too. But then the job must **verify that a service which should have built actually did** — hence the `|| exit 1` inside the `changed == true` branch. ⛔ Otherwise a broken path filter silently ships a partial release train.
- **Reading the running digest from the cluster** for the unchanged service is what makes a frontend-only commit deploy *only* the frontend, with the backend's digest unchanged. ⭐ That is the property that keeps the pair atomic without rebuilding it.

---

## 8 · CI — Azure DevOps and Jenkins

### 8.1 Azure DevOps — the differences that matter

| Concern | ⭐ Azure DevOps answer |
|---|---|
| Change detection | `paths:` filters per pipeline (two CI pipelines), or a `bash:` `git diff --name-only` step setting a variable |
| Parallel builds | two pipelines, triggered by the same push |
| ⛔ Looping over services in a template | **templates cannot loop over a runtime list** — `${{ each }}` is compile-time. Use a `parameters: services: [...]` array, or one pipeline per service |
| The manifest job | a third pipeline with `resources.pipelines` on **both** CI pipelines |
| Chaining CD | `resources.pipelines` on the manifest pipeline |

```yaml
# ⭐ waiting for BOTH CI pipelines — Azure DevOps needs two resources
resources:
  pipelines:
    - pipeline: ci-api
      source: CI · shop-api
      trigger: { branches: { include: [main] } }
    - pipeline: ci-ui
      source: CI · shop-ui
      trigger: { branches: { include: [main] } }

steps:
  - download: ci-api
    artifact: image-digest
    displayName: 'the API digest'
  - download: ci-ui
    artifact: image-digest
    displayName: 'the UI digest'
  - bash: |
      set -euo pipefail
      API=$(cat '$(Pipeline.Workspace)/ci-api/image-digest/digest.txt')
      UI=$(cat  '$(Pipeline.Workspace)/ci-ui/image-digest/digest.txt')
      # ⭐⭐ if ONE of them did not run (nothing changed), fall back to the
      #   digest currently in production.
      [[ "$API" =~ @sha256: ]] || API=$(kubectl -n shop-production get deploy shop-api \
        -o jsonpath="{.spec.template.spec.containers[?(@.name=='shop-api')].image}")
      [[ "$UI"  =~ @sha256: ]] || UI=$(kubectl -n shop-production get deploy shop-ui \
        -o jsonpath="{.spec.template.spec.containers[?(@.name=='shop-ui')].image}")
      printf 'shop-api=%s\nshop-ui=%s\n' "$API" "$UI" | tee release-manifest.txt
    displayName: '⭐ Build the manifest'
```

⭐ **The Azure DevOps gotcha:** `resources.pipelines` with two entries triggers when **either** completes, not when **both** have. So the manifest pipeline must tolerate one artifact being absent and fall back to the running digest — which is the same logic as §7.1, expressed defensively.

### 8.2 Jenkins — the differences that matter

| Concern | ⭐ Jenkins answer |
|---|---|
| Change detection | the multibranch `changeset` condition, or `git diff --name-only` in a `when` |
| Parallel builds | `parallel { }` in one Jenkinsfile, or two jobs chained into a third |
| The manifest | ⭐ a Groovy `writeFile` — the simplest of the three tools |
| Chaining CD | `build job: '/shop-cd/cd-shop-pair', parameters: [string(name:'MANIFEST', value: …)]` |

```groovy
stage('manifest') {
  steps {
    script {
      // ⭐ Groovy makes this trivial — both digests are already in env
      def api = env.API_CHANGED == 'true' ? env.API_REF : readBack('shop-production', 'shop-api')
      def ui  = env.UI_CHANGED  == 'true' ? env.UI_REF  : readBack('shop-production', 'shop-ui')
      // ⭐⭐ the contract check
      def apiCv = sh(returnStdout: true, script:
        "kubectl -n shop-production run cv-\$RANDOM --rm -i --restart=Never --image=curlimages/curl -- " +
        "curl -fsS http://shop-api:8080/api/contract-version | jq -r .serves[]").trim().split('\n')
      def uiCv = env.UI_CONTRACT_VERSION
      if (!(uiCv in apiCv)) error("⛔ contract mismatch: BE serves ${apiCv}, FE requires ${uiCv}")

      def manifest = "shop-api=${api}\nshop-ui=${ui}\n"
      writeFile(file: 'release-manifest.txt', text: manifest)
      archiveArtifacts artifacts: 'release-manifest.txt', fingerprint: true
      env.MANIFEST = manifest
    }
  }
}
post {
  success {
    script {
      if (env.BRANCH_NAME == 'main' && env.CHANGE_ID == null) {
        build job: '/shop-cd/cd-shop-pair',
              parameters: [string(name: 'MANIFEST', value: env.MANIFEST),
                           string(name: 'CI_BUILD', value: env.BUILD_URL)],
              wait: false, propagate: false
      }
    }
  }
}
```

---

## 9 · ⭐ CD — the ordered pair

```
┌─────────────────────────────────────────────────────────────────┐
│  CD · shop pair — ONE manifest, ONE approval, ORDERED deploy    │
│                                                                 │
│  1 · resolve + validate BOTH digests                            │
│  2 · ⭐ verify provenance on BOTH                               │
│  3 · ⭐ assert the contract versions are compatible             │
│  4 · deploy → dev      : api, then ui   → verify the PAIR       │
│  5 · deploy → staging  : api, then ui   → verify the PAIR       │
│  6 · 🔒 ONE approval  |  🤖 canary the api, then the ui         │
│  7 · deploy → production:                                       │
│        a. ⭐⭐ MIGRATE (Job, gated)                              │
│        b. deploy shop-api  → rollout status → read back         │
│        c. ⭐ smoke the BACKEND from inside the cluster          │
│        d. deploy shop-ui   → rollout status → read back         │
│        e. ⭐⭐ smoke the PAIR (FE → BE, end to end)              │
│  8 · on ANY failure in 7b–7e → ⭐ ROLL BACK BOTH                │
└─────────────────────────────────────────────────────────────────┘
```

```bash
#!/usr/bin/env bash
# deploy-pair.sh — ⭐ the ordering and the roll-back-both, in one place
set -euo pipefail
NS="${NS:-shop-production}"
API_REF=""; UI_REF=""
while IFS='=' read -r k v; do
  case "$k" in shop-api) API_REF="$v";; shop-ui) UI_REF="$v";; esac
done < release-manifest.txt

for r in "$API_REF" "$UI_REF"; do
  [[ "$r" =~ @[a-z0-9]+:[0-9a-f]{64}$ ]] || { echo "⛔ not a digest: $r"; exit 1; }
done

# ── ⭐ RECORD BOTH — that record IS the rollback ───────────────────────
PREV_API=$(kubectl -n $NS get deploy shop-api -o jsonpath="{.spec.template.spec.containers[?(@.name=='shop-api')].image}")
PREV_UI=$(kubectl -n $NS get deploy shop-ui  -o jsonpath="{.spec.template.spec.containers[?(@.name=='shop-ui')].image}")
echo "📌 previous: api=$PREV_API ui=$PREV_UI"

rollback_both() {
  echo "🚨 rolling back BOTH"
  kubectl -n $NS set image deploy/shop-api shop-api="$PREV_API" || true
  kubectl -n $NS set image deploy/shop-ui  shop-ui="$PREV_UI"   || true
  kubectl -n $NS rollout status deploy/shop-api --timeout=300s || true
  kubectl -n $NS rollout status deploy/shop-ui  --timeout=300s || true
}
trap rollback_both ERR           # ⭐⭐ ANY failure below rolls back BOTH

# ── a · ⭐⭐ MIGRATE FIRST, GATED ──────────────────────────────────────
kubectl -n $NS delete job shop-api-migrate --ignore-not-found
kubectl -n $NS apply -f k8s/shop-api/migration-job.yaml
kubectl -n $NS wait --for=condition=complete job/shop-api-migrate --timeout=600s

# ── b · BACKEND FIRST ──────────────────────────────────────────────────
kubectl -n $NS set image deploy/shop-api shop-api="$API_REF"
kubectl -n $NS rollout status deploy/shop-api --timeout=600s

# ── c · ⭐ SMOKE THE BACKEND ALONE, BEFORE THE FRONTEND MOVES ──────────
kubectl -n $NS run s$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.17.0 -- sh -c '
  set -e
  curl -fsS http://shop-api:8080/actuator/health/readiness
  curl -fsS http://shop-api:8080/api/v2/orders            # ⭐ a BUSINESS endpoint
  curl -fsS http://shop-api:8080/api/v1/orders >/dev/null || true   # ⭐ v1 STILL served?
'
# ⭐ that last line is the expand/contract check, run in production: the
#   OLD frontend's endpoint must still work before you move the frontend.

# ── d · THEN THE FRONTEND ──────────────────────────────────────────────
kubectl -n $NS set image deploy/shop-ui shop-ui="$UI_REF"
kubectl -n $NS rollout status deploy/shop-ui --timeout=300s

# ── e · ⭐⭐ SMOKE THE PAIR, END TO END ────────────────────────────────
kubectl -n $NS run e2e$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.17.0 -- sh -c '
  set -e
  # the FE serves, and points at THIS environment
  curl -fsS -o /dev/null http://shop-ui/
  curl -fsS http://shop-ui/config.js | grep -q "api.shop"
  # ⭐ the FE can reach the BE through the same path a browser would use
  curl -fsS http://shop-api:8080/api/v2/orders >/dev/null
  # ⭐ index.html is not cached (§04 file)
  curl -fsSI http://shop-ui/index.html | grep -qi "no-cache"
'
echo "✅ pair deployed and verified: api=$API_REF ui=$UI_REF"
```

| Rule | ⭐ Why |
|---|---|
| ⭐⭐ **Backend first** | the backend must serve *both* frontends at every instant |
| ⭐ **Smoke the backend before moving the frontend** | if the backend is broken, do not also break the frontend |
| ⭐ **Check that v1 is still served** | the expand/contract guarantee, verified in production |
| ⭐⭐ **One approval for the pair** | the human authorised *this release*; two prompts invite approving the FE after the BE failed |
| ⭐⭐ **Roll back BOTH on any failure** | a half-promoted pair (new UI, old API) is a state nobody tested |
| ⭐ **Verify the pair, not each half** | both halves green can still be a broken pair |

---

## 10 · 🔒 Case 1 or 🤖 Case 2 — ⭐ split them

| Service | Prerequisites | ⭐ Verdict |
|---|---|---|
| `shop-ui` | 1 ✅ · 2 ✅ · 3 ⚠️ needs RUM · 4 ✅ · 5 n/a | 🤖 **Case 2** |
| `shop-api` | 1 ⚠️ · 2 ✅ Testcontainers · 3 ✅ · 4 ✅ · 5 ⛔ migrations | 🔒 **Case 1** |
| **The pair** | — | ⭐ **split: FE → Case 2, BE → Case 1** |

⭐⭐ **The most valuable decision in this file:** *do not apply one policy to the pair.*

```
⛔ ONE POLICY FOR BOTH
   The pair inherits the HIGHEST-risk member's policy.
   → a static-file frontend needs a change-approval board,
     because it ships with the Java service.
   → the frontend's 20 deploys a week each wait for a human.
   → people start approving without reading (§ Case 1's failure mode 1).
   → the gate becomes theatre, and the BACKEND loses its real control.

✅ SPLIT
   shop-ui  → 🤖 Case 2, deploys on every green CI, canaried or plain rolling
   shop-api → 🔒 Case 1, human approval, migration gated
   ⭐ the pair's ORDERING RULE still applies: BE before FE.
     Implement it by making cd-shop-ui trigger on cd-shop-api's completion.
```

```yaml
# ⭐ FE after BE, across two CD pipelines
on:
  workflow_run:
    workflows: ['CD · shop-api']
    types: [completed]
jobs:
  deploy-ui:
    if: ${{ github.event.workflow_run.conclusion == 'success' }}
    # ⭐ and re-check the manifest: the FE must deploy the digest that was
    #   paired with the BE that just went out, not "the latest FE".
```

**When to keep them together anyway:** if the release genuinely requires both halves to change *and* the backend's change is not backward-compatible — in which case expand/contract has not been applied, and the correct answer is to fix the API design (§3), not to couple the pipelines permanently.

---

## 11 · ▶️ Run it end to end — the acceptance checks

```bash
# ── CI ────────────────────────────────────────────────────────────────
# 1 · a frontend-only change does NOT run mvn
git checkout -b t && echo "/* x */" >> apps/shop-ui/src/index.css
git commit -am "fe only" && git push
gh run watch --exit-status
gh run list --workflow ci-shop-api.yml --limit 1 --json conclusion --jq '.[0]'
# ⭐ must be "skipped" or absent

# 2 · ⭐⭐ the breaking-change gate actually fires
#    remove a field from a DTO / an endpoint from a controller, push
gh run list --workflow ci-shop-api.yml --limit 1 --json conclusion --jq '.[0].conclusion'
# ⭐ must be "failure", at the openapi-diff step

# 3 · the manifest is an atomic pair
gh run download <RID> -n release-manifest -D /tmp/m && cat /tmp/m/release-manifest.txt
# ⭐ both lines present, both @sha256:, and the contract version recorded

# 4 · ⭐ an unchanged service reuses the RUNNING digest
kubectl -n shop-production get deploy shop-api \
  -o jsonpath="{.spec.template.spec.containers[?(@.name=='shop-api')].image}"
# ⭐ must equal the shop-api line in the manifest after a UI-only change

# ── CD ────────────────────────────────────────────────────────────────
# 5 · CD takes the MANIFEST, not two digests
grep -q 'release-manifest\|MANIFEST' .github/workflows/cd-shop-pair.yml && echo "✅ one input"

# 6 · ⭐⭐ the ordering is backend-first
grep -n 'set image deploy/shop-api' deploy-pair.sh | head -1
grep -n 'set image deploy/shop-ui'  deploy-pair.sh | head -1
# ⭐ the api line number must be SMALLER

# 7 · roll-back-both is wired
grep -q 'trap rollback_both ERR' deploy-pair.sh && echo "✅ rolls back both"

# 8 · ⭐ expand/contract is verified IN PRODUCTION
kubectl -n shop-production run v$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.17.0 -- \
  sh -c 'curl -fsS -o /dev/null -w "v1=%{http_code} " http://shop-api:8080/api/v1/orders; \
         curl -fsS -o /dev/null -w "v2=%{http_code}\n" http://shop-api:8080/api/v2/orders'
# ⭐ BOTH must be 200 while the pair is mid-migration

# 9 · ⭐⭐ the contract-version endpoint agrees with the FE
kubectl -n shop-production run c$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.17.0 -- \
  curl -fsS http://shop-api:8080/api/contract-version
kubectl -n shop-production exec deploy/shop-ui -- cat /usr/share/nginx/html/config.js

# 10 · the PAIR smoke (not each half)
kubectl -n shop-production run e$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.17.0 -- \
  sh -c 'curl -fsS http://shop-ui/config.js | grep -q api.shop && \
         curl -fsS -o /dev/null http://shop-api:8080/api/v2/orders && echo "✅ pair OK"'

# 11 · ⭐ the split policy is real
grep -q 'PROD_MODE: deployment' .github/workflows/cd-shop-ui.yml  && echo "✅ FE is Case 2"
grep -q 'environment: production' .github/workflows/cd-shop-api.yml && echo "✅ BE is Case 1"

# 12 · what is running, both halves
for s in shop-api shop-ui; do
  printf '%-10s ' "$s"
  kubectl -n shop-production get deploy "$s" \
    -o jsonpath="{.spec.template.spec.containers[?(@.name=='$s')].image}"; echo
done
```

---

## 12 · Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| ⛔ 404s for minutes after a paired deploy | the backend removed an endpoint the cached frontend still calls | §3 — expand/contract |
| 404s for **hours** | same, plus `index.html` cached | ⭐ `no-cache` on `index.html` ([`04-fe-only.md`](./04-fe-only.md) §8) |
| The frontend deployed before the backend | CD ran them in parallel or FE-first | §9 — backend first, `needs:` between them |
| ⛔ The manifest job is skipped | a skipped `api` job reports `skipped`, not `success` | `if: always()` **plus** an explicit check that a changed service published (§7.1) |
| The manifest re-deploys the unchanged service | it used CI's digest instead of the running one | §5.3 — read the running digest from the cluster |
| `openapi-diff` passes but the frontend breaks | ⛔ the spec is generated from annotations, not from the real controller | generate it by **running** the app and fetching `/v3/api-docs` |
| The FE's generated client is stale | no `git diff --exit-code` gate | §6.2 |
| ⛔ Both suites green, production 404 | no contract test — each side tests its own assumptions | §6 |
| Azure DevOps' manifest pipeline runs twice | two `resources.pipelines` each trigger it | ⭐ tolerate a missing artifact and fall back to the running digest (§8.1) |
| Jenkins' `readBack` returns the sidecar's image | JSONPath `[0]` instead of the name filter | `[?(@.name=='shop-api')]` |
| The contract-version check always passes | the FE does not actually check at startup | §5.2 — implement the startup fetch and the banner |
| ⛔ Rollback left the pair half-promoted | no `trap`, or only one service rolled back | §9 — `trap rollback_both ERR` |
| Release 3 (removing v1) broke someone | no telemetry on v1 usage | ⭐ the broker / access logs tell you when it is safe (§6.3) |

---

<a name="tasks--answers"></a>
## 13 · ⭐ TASKS — answers at the END

| # | Task |
|---|---|
| **T1** | Design the three-release expand/contract sequence for renaming `orders.qty` → `orders.quantity`, and state the revert for each |
| **T2** | Add `openapi-diff --fail-on-incompatible` to the backend CI and prove it fails on a removed field |
| **T3** | Add the frontend's generated-client drift gate and prove it fails when the backend changes |
| **T4** | Implement `contract-version` on both sides, including the FE startup check and the refresh banner |
| **T5** | Build the manifest job so an unchanged service reuses the **running** digest |
| **T6** | Write `deploy-pair.sh` with backend-first ordering, a gated migration, and roll-back-both |
| **T7** | Add the production expand/contract check — that v1 is still served while v2 is live |
| **T8** | Split the pair's policy: FE → Case 2, BE → Case 1, with FE triggering after BE |
| **T9** | Implement Pact (or justify not to) for this pair |
| **T10** | ⭐⭐ Both CI suites are green, the manifest is valid, the deploy succeeded, and every order page in production 404s. Give the diagnosis in order of likelihood with the confirming command for each, then name the gate that should have caught it |

---

# ✅ ANSWERS

**T1.** §3.1. **Release 1 (backend):** accept **both** `qty` and `quantity` on input, emit **both** on output. *Revert:* remove the new handling — nobody was sending `quantity` yet, and the old frontend still sends `qty`. **Release 2 (frontend):** send `quantity`, read `quantity`. *Revert:* re-deploy the previous frontend digest — safe, because release 1 still accepts and emits `qty`. **Release 3 (backend):** stop accepting/emitting `qty`, then in a **later** release drop the column. *Revert:* re-add `qty` handling — expensive but possible. ⭐ **Two things to state:** release 3 happens **only after telemetry confirms zero `qty` traffic**, and that may take days or weeks, because the duration of release 2's real rollout is controlled by **browser cache**, not by your pipeline. And the database column drop is the single irreversible step, which is why it goes last and alone — separated from the code change that stops using it. **The anti-pattern** is one PR changing both sides: it looks cleaner, it is smaller, it is more reviewable, **and it is not deployable without a breaking window**, because the two halves never roll out atomically.

**T2.** §6.1. In the backend CI: fetch the previous released spec, **run the app** and fetch `/v3/api-docs` (⭐ generating from annotations rather than from the running controller is the common mistake — annotations can lie, the running app cannot), then `npx @openapitools/openapi-diff /tmp/old-openapi.json /tmp/new-openapi.json --fail-on-incompatible`. **Proving it fires:** remove a field from a response DTO (or delete an `@GetMapping`), push, and confirm the CI run **fails at that step** with a message naming the removed property. ⭐ **Know the classification:** breaking = removed property, narrowed type, optional → required, removed endpoint, removed enum value; non-breaking = added optional property, widened type, added endpoint, added enum value. **Why this is the highest-value line in the shape:** ten minutes of setup converts "the frontend broke in production, hours later, for users we cannot identify" into "the backend build failed, in three minutes, naming the field". Everything else in §6 is refinement on top of it.

**T3.** §6.2. In the frontend CI: download the backend's published spec, `npx openapi-typescript /tmp/openapi.json -o src/api/schema.d.ts`, then `git diff --exit-code src/api/schema.d.ts` — failing with the diff printed if it is not empty. **Proving it fires:** change the backend spec, publish it, then run the frontend CI *without* regenerating and committing `schema.d.ts`. ⛔ It fails, showing exactly which types moved. ⭐ **The pairing is what makes it work:** T2 fails the *backend* when it makes a breaking change; T3 fails the *frontend* when the backend changed and the frontend has not caught up. Together they mean a contract change cannot land on one side only — which is precisely the condition that produces skew. **Two details:** the spec URL must point at the backend's **published artifact** (not a branch build), so the frontend is checked against what will actually run; and committing `schema.d.ts` (rather than generating it at build time) is deliberate — it makes drift visible as a diff in the PR, which is a reviewable artifact rather than a build failure.

**T4.** §5.2. **Backend:** a `GET /api/contract-version` returning `{"version": 2, "serves": [1, 2]}` — ⭐ `serves` is a **list**, because during expand/contract the backend serves several versions concurrently. **Frontend:** baked at build time as `MY_CONTRACT_VERSION` (⭐ this one *is* a legitimate build-time constant — it describes the artifact, not the environment, so it does not break the one-image rule), fetched at startup against `/api/contract-version`, and if `!serves.includes(MY_CONTRACT_VERSION)` show a **refresh banner** rather than rendering a wall of 404s. **In CD:** assert `UI_CV ∈ API_serves` before promoting — ⭐ the direction matters: the backend may serve *more* than the frontend requires (that is expand/contract working), but the frontend may never require *more* than the backend serves. **The payoff is threefold:** a silent failure becomes a **detected** one for the user; CD refuses an incompatible pair; and "how many clients are still on contract 1?" — answerable from the access log or from RUM events carrying the version — tells you **when release 3 is safe**. ⭐ **Be clear about the limit:** this does not make deployment atomic. Nothing can. It makes incompatibility *visible*, which is the most that is achievable.

**T5.** §5.3 and §7.1. For each service: if it changed in this commit, use the digest CI just published; otherwise read the digest **currently running in production** from the cluster — `kubectl -n shop-production get deploy <svc> -o jsonpath="{.spec.template.spec.containers[?(@.name=='<svc>')].image}"`. ⭐ **Why the cluster rather than the last manifest:** the cluster is the *actual* current state, and it stays correct after a manual hotfix, a rollback, or a partially-applied release — all of which make a stored "last manifest" stale. **Two subtleties:** the manifest job needs `if: always()`, because a skipped CI job reports `skipped` rather than `success` and would otherwise skip the manifest too — **but** it must then explicitly verify that a service which *should* have built *did* (`|| exit 1` inside the `changed == true` branch), or a broken path filter silently ships a partial release train. And in Azure DevOps, `resources.pipelines` with two entries triggers when **either** completes, so the same fallback logic is required defensively rather than optionally (§8.1).

**T6.** §9's `deploy-pair.sh`. The sequence: validate **both** digests are `@sha256:` references → record **both** currently-running images (⭐ that record *is* the rollback) → `trap rollback_both ERR` → migrate (Job, `kubectl wait --for=condition=complete`, `|| exit 1`) → deploy `shop-api` → `rollout status` → **smoke the backend alone, including a business endpoint and a check that `/api/v1` is still served** → deploy `shop-ui` → `rollout status` → **smoke the pair end to end**. ⭐ **Why each decision:** *backend first*, because the backend must serve both frontends at every instant and the reverse order guarantees a breakage window whose length browser cache controls; *smoke the backend before moving the frontend*, so a broken backend does not also become a broken frontend; *check v1 is still served*, because that is the expand/contract guarantee verified in production rather than assumed; *`trap … ERR` rolling back both*, because a half-promoted pair — new UI against old API — is a state nobody tested and is worse than either consistent state. **One approval for the pair, not two:** the human authorised *this release*, and two prompts invite approving the FE after the BE failed, producing exactly the half-promoted state the trap exists to prevent.

**T7.** §9 step c's last line: `curl -fsS http://shop-api:8080/api/v1/orders` **during** the production deploy, asserting it still returns 200 (or a successful empty response). ⭐ **Why run it in production rather than only in CI:** CI proves the *new backend* serves v1. This proves the *deployed* backend serves v1 **at the moment the frontend is about to move** — which is the only instant that matters, and it can differ because of a ConfigMap, a profile, a feature flag, or a partially-completed rollout. **Generalise it:** during the whole expand/contract window (release 1 → release 3), every deploy asserts that *all currently-served contract versions* still respond. That is a five-line loop over the `serves` list from T4, and it is what makes release 3's removal a deliberate, evidence-based act rather than a hope. **And the corollary:** the check must be allowed to fail the deploy. A check that only logs is a report, and reports get read once.

**T8.** §10. **Two CD pipelines with different policies:** `cd-shop-ui` with 🤖 Case 2 (no environment reviewers, canary or plain rolling, automatic rollback, a circuit breaker) and `cd-shop-api` with 🔒 Case 1 (`environment: production` with required reviewers, an ungated rollback workflow, a migration-gated rollout). **Ordering:** `cd-shop-ui` triggers `on: workflow_run: { workflows: ['CD · shop-api'], types: [completed] }` with `if: github.event.workflow_run.conclusion == 'success'` — and ⭐ it must re-read the **manifest** to deploy the frontend digest that was *paired* with the backend that just shipped, not "the latest frontend". **Why split, stated as the failure it prevents:** with one policy the pair inherits its highest-risk member's rules, so a static-file frontend ends up needing a change-approval board. Twenty frontend deploys a week each wait for a human; humans start approving without reading; the gate becomes theatre; **and the backend loses its real control** — which is the actual damage. Splitting gives the frontend Case 2's speed where the risk is genuinely near zero, and preserves a meaningful human decision where the risk is real. **Keep them coupled only when** a release genuinely requires both halves to change *and* the backend change is not backward-compatible — which means expand/contract was not applied, and the fix is the API design (§3), not permanently coupling the pipelines.

**T9.** §6.3–6.4. **The pragmatic recommendation: do 6.1 and 6.2 first, and adopt Pact when you have a second consumer.** For one frontend and one backend, `openapi-diff --fail-on-incompatible` (T2) plus generated-client drift detection (T3) catches the overwhelming majority of skew — a renamed, removed or retyped field — at about forty minutes of total setup, with no broker to run and no pact files to store. **Adopt Pact when either of these becomes true:** ⭐ **(a) you have more than one consumer** of the API (a mobile app, a partner integration, a second frontend) — then "does backend candidate X satisfy *all* current consumers?" is a question the OpenAPI diff cannot answer, and the Pact broker answers it directly; or ⭐ **(b) you need to schedule release 3** — removing `/api/v1`. The broker records which consumer versions still expect v1, which turns "is it safe to remove this yet?" from an argument into a query. **The justification for not adopting it sooner, stated honestly:** Pact requires a broker, a consumer-side recording step in the frontend's CI, a provider-verification step in the backend's, and version compatibility policy between them. That is a real maintenance surface. For a single pair, it buys *earlier and more precise* detection of the same failures T2/T3 already catch — valuable, but not the difference between safe and unsafe. ⭐ **The one thing Pact does that nothing else can:** it verifies the provider against the consumer's **actual recorded interactions**, so a hand-written mock that has itself drifted cannot produce a false pass. If your frontend tests mock the API, that drift is already possible, and Pact is the answer.

**T10.** ⭐⭐ Green CI on both sides, valid manifest, successful deploy, every order page 404s. **In order of likelihood:**

1. ⭐⭐ **Version skew — the backend removed or renamed an endpoint the *cached* frontend still calls.** The most likely by a wide margin, and the timing is diagnostic: the 404s are on `/api/v1/...` while `/api/v2/...` works. **Confirm:** `kubectl logs deploy/shop-ui` access logs (or the ingress log) grouped by path and status — a 404 concentrated on **one path** is skew; 404s on *all* paths is routing. Then `curl http://shop-api:8080/api/v1/orders` from inside the cluster: **404 confirms it.** ⭐ This passes both CI suites because each tests its own assumptions, and it passes the deploy because the pods are healthy.
2. **Ingress/routing** — the FE's `API_URL` points at the wrong host (⭐ especially if config was baked at build time), or the ingress path prefix does not match. **Confirm:** `kubectl exec deploy/shop-ui -- cat /usr/share/nginx/html/config.js`, then `curl -I https://api.shop/api/v2/orders` from outside.
3. **The pair was not deployed together** — the manifest contained a new FE with an old BE (or the CD deployed them out of order and the FE half succeeded while the BE half silently did not). **Confirm:** compare both running digests against the manifest — `kubectl get deploy -o jsonpath` with the **name filter** for each. ⭐ This is CHECK 4, and a `set image` with a mistyped container name succeeds silently.
4. **Contract-version mismatch that nothing checked** — the FE requires v2, the BE serves only v1. **Confirm:** `curl http://shop-api:8080/api/contract-version` against the FE's build-time constant (T4).
5. **Auth/CORS** — the endpoint exists and returns 401/403, or a preflight is blocked; the browser surfaces it as a failed request. **Confirm:** the browser Network tab — the *status code* distinguishes this from a 404 instantly.
6. **The migration ran but the code did not, or vice versa** — the handler 500s (surfacing as an error page) or the route is not registered. **Confirm:** `kubectl get jobs -l component=migrate`, then `flyway_schema_history`.

⭐ **Fastest triage, in practice:** open the browser devtools Network tab on a failing page and read the **actual request URL and status code**. That single observation distinguishes cases 1, 2, 5 and 6 in under a minute — a 404 on `/api/v1/orders` is skew; a 404 on `/api/v2/orders` is routing or a stale backend; a 401 is auth; a 500 is the backend itself. Everything above is the systematic version of that glance.

**The gate that should have caught it — and the honest answer has two layers:**
- **Directly:** ⭐ **T7's production expand/contract check** — `curl /api/v1/orders` must return 200 *during* the deploy, before the frontend moves. It runs at exactly the right moment and would have failed the deploy rather than the users.
- **In CI:** ⭐ **`openapi-diff --fail-on-incompatible` (T2)** — it fails the *backend build* the moment an endpoint or field is removed, which is where the decision was actually made. If it did not fire, the spec was generated from annotations rather than from the running controller (§12), or the diff was not wired to `--fail-on-incompatible`.
- **Structurally:** ⭐⭐ **release 3 should never have shipped without telemetry.** Removing `/api/v1` is the one release in the expand/contract sequence that requires evidence — access logs or the Pact broker (T9) showing zero v1 traffic for N days. Shipping it on a schedule rather than on evidence is the root cause, and the gate to add is *"the removal PR must attach the v1 traffic report"*, which is a review rule rather than a pipeline step.

**The meta-lesson:** both suites green means each side is **self-consistent**, not that the pair is. That gap is what §6 exists to close, and it is closable in about an hour of CI work — which is why "we did not have a contract test" is never a satisfying answer to this incident.

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish_Kumar_Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn: https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260
🔗 GitHub: https://github.com/3558Bhk

*You cannot deploy a browser atomically. So the backend must serve yesterday's frontend forever — until the telemetry says otherwise.*

</div>
