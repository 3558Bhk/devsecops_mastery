# 🔀 FILE 07 — THE THREE SCENARIOS: CI-only · CD-only · CI+CD

### Deploying the **Docker and Kubernetes projects you already built** (FE, BE, FE+BE polyglot) through **Azure DevOps, GitHub Actions and Jenkins**

> **What this file is.** The other files in this folder teach you each *tool*. This file teaches you the three *shapes of pipeline* that every company actually runs, and it deploys **your** apps — `shop-ui` (React), `shop-api` (Java 21), `checkout` (Go), `order-worker` (Python), `payment-mock` (Go) — the same ones from the Docker and Kubernetes learning paths.
>
> **The three scenarios:**
>
> | | Scenario | Question it answers | Who runs it |
> |---|---|---|---|
> | 1️⃣ | **CI only** | "Is this change *good*?" | Every push / every PR |
> | 2️⃣ | **CD only** — Case 1 *Continuous Delivery*, Case 2 *Continuous Deployment* | "How does an already-built artifact reach an environment?" | On artifact publication / on config-repo change |
> | 3️⃣ | **CI + CD both** | "How does a commit become running software, end to end?" | The whole thing, wired together |
>
> **Read order:** §1 (vocabulary) → §2 (your apps and the three deploy targets) → the scenario you need → §6 (deploy strategies) → §7 (rollback) → §10 (tasks + answers at the END).

---

## 📇 Contents

- [0 · Why this file exists](#0--why-this-file-exists)
- [1 · The vocabulary — CI vs CD vs Delivery vs Deployment](#1--the-vocabulary--ci-vs-cd-vs-delivery-vs-deployment)
- [2 · Your apps, and the three deployment targets](#2--your-apps-and-the-three-deployment-targets)
- [3 · SCENARIO 1 — CI ONLY](#3--scenario-1--ci-only-no-deployment-at-all)
- [4 · SCENARIO 2 — CD ONLY](#4--scenario-2--cd-only-starting-from-an-artifact)
  - [4.1 Case 1 — Continuous DELIVERY (a human says yes to prod)](#41-case-1--continuous-delivery-a-human-decides-production)
  - [4.2 Case 2 — Continuous DEPLOYMENT (the machine says yes)](#42-case-2--continuous-deployment-the-machine-decides-production)
- [5 · SCENARIO 3 — CI + CD BOTH](#5--scenario-3--ci--cd-both-the-full-path)
- [6 · How the deploy actually happens — 5 mechanisms × 4 languages](#6--how-the-deploy-actually-happens--5-mechanisms--4-languages)
- [7 · Rollback drills for every scenario](#7--rollback-drills-for-every-scenario)
- [8 · Troubleshooting table](#8--troubleshooting-table)
- [9 · Which scenario do I pick? (decision tree)](#9--which-scenario-do-i-pick)
- [10 · ⭐ Tasks and ANSWERS — at the END](#tasks--answers)

---

## 0 · Why this file exists

You have already built the apps. You have already containerised them. You have already put them on Kubernetes by hand. What is missing is the **automation shape** — and here is the thing nobody tells you:

⭐⭐ **There are only three pipeline shapes in the industry.** Every company you will ever interview at runs some combination of these three. If you can build all three, in all three tools, for a polyglot frontend+backend monorepo, you have covered essentially the whole CI/CD interview surface.

The shapes differ in exactly one thing — **where the automation stops**:

```
        ┌──────────────────────────────────────────────────────────────────────┐
        │                                                                      │
 commit │   CI                    CD                                           │
  ──────▶  build → test → scan →  ──▶  dev ──▶ staging ──▶ prod               │
        │  image → push → sign                                                │
        │                                                                      │
        └──┬──────────────────┬────────────────────────────────────────────────┘
           │                  │
   SCENARIO 1          SCENARIO 2              SCENARIO 3
   stops here ─────────┘  starts here ─────────┘  both, wired together
   "is the artifact      "the artifact already    "commit → running
    good?"                exists; move it"         software"
```

⛔ **The #1 beginner mistake:** writing one giant pipeline that does everything, for every environment, on every push. It is slow (15 minutes to learn your PR broke a lint rule), it is unsafe (the same job that builds also holds prod credentials), and it cannot be reasoned about. **Split it.** Scenario 3 is not "Scenario 1 and 2 glued together" — it is two pipelines with a *contract* between them. That contract is the artifact, and §4.0 explains it properly.

🔑 **The interview line:** "I separate CI from CD deliberately. CI is triggered by code and produces a signed, immutable artifact. CD is triggered by that artifact — never by a commit — and owns the promotion. The benefit is that the credential boundary matches the trust boundary: CI runners never hold production credentials, and the thing that deploys to prod is a small, auditable pipeline whose only input is an artifact digest."

---

## 1 · The vocabulary — CI vs CD vs Delivery vs Deployment

Beginner-safe definitions. Memorise the difference between the last two — it is asked in almost every SDE interview, and most working engineers get it wrong.

| Term | Expands to | What it means | The test |
|---|---|---|---|
| **CI** | Continuous **Integration** | Every change is merged to a shared branch frequently, and every merge is automatically built and tested. | *Does a broken commit get caught before it reaches anyone else?* |
| **CD** | Continuous **Delivery** | Every change that passes CI is automatically deployed to *pre-production* environments and is **always releasable to production** — but a **human presses the button** for prod. | *Could we ship right now, if we chose to?* |
| **CD** | Continuous **Deployment** | Same, except production happens **automatically**, with no human in the loop. | *Did a commit reach prod without anyone clicking?* |
| **CD** | Continuous Delivery **and** Deployment (the umbrella) | The generic abbreviation. ⚠️ Always say which one you mean. | — |

⭐⭐ **The one-sentence difference:** in Continuous **Delivery** every change is *deployable*; in Continuous **Deployment** every change is *deployed*. The first ends with an approval gate; the second ends with an automated guardrail that does the approving.

```
CONTINUOUS DELIVERY (Case 1)
  commit ─▶ CI ─▶ dev ─▶ staging ─▶ 🚪 GATE (human) ─▶ prod
                                     │
                                     └─ the artifact is READY, and can sit
                                        there for hours or days. Release is a
                                        business decision.

CONTINUOUS DEPLOYMENT (Case 2)
  commit ─▶ CI ─▶ dev ─▶ staging ─▶ 🤖 AUTO ─▶ canary ─▶ analysis ─▶ prod
                                     │                │
                                     │                └─ fails? auto-rollback
                                     └─ no human. The gate is replaced by
                                        evidence: tests, SLOs, error budget.
```

### 1.1 Which is "better"? ⭐⭐⭐ the honest answer

Neither. It depends on **blast radius** and **reversibility**.

| Your situation | Choose | Why |
|---|---|---|
| Consumer web app, stateless, canary + auto-rollback, good observability | **Continuous Deployment** | Fast feedback beats ceremony; a bad deploy is reverted in <5 min automatically |
| Banking / payments / healthcare — regulated change control | **Continuous Delivery** | A human approval is a *compliance control*, not a technical one. Auditors require it |
| Databases with irreversible migrations | **Continuous Delivery** (+ expand/contract migrations) | You cannot "roll back" a `DROP COLUMN`. Slow down on purpose |
| Mobile app store releases | **Continuous Delivery** | The store review is the gate whether you like it or not |
| A team of 2 with no on-call rota | **Continuous Delivery** | Auto-deploying to prod at 3 a.m. with nobody watching is not bravery, it is negligence |
| MAANG-scale product with an SRE org and error budgets | **Continuous Deployment** | This is literally why error budgets exist — to *permit* automatic release |

🔑 **The interview line:** "Continuous Deployment is a property of the *system*, not of the pipeline. You can only earn it once deploys are small, reversible, observable and automatically abortable. Until then, Continuous Delivery with a real approval gate is the correct engineering choice — and I'd push back on any team that claims Continuous Deployment without canary analysis and auto-rollback, because what they actually have is 'unattended risky deploys'."

### 1.2 The five things that are NOT CI/CD (and get called it anyway)

| People say | What they mean | Correct term |
|---|---|---|
| "our CI" | a Jenkins job that FTPs a WAR to a server at 2 a.m. | a **scheduled batch job** |
| "CD pipeline" | a script a developer runs from their laptop | **manual release** (the thing CD exists to eliminate) |
| "continuous deployment" | auto-deploy to a **dev** environment | continuous **integration with auto-deploy to non-prod** |
| "we do DevOps" | we installed Jenkins | **a build server** |
| "GitOps" | we `kubectl apply` from a shell step in CI | **push-based deployment** — GitOps means the cluster *pulls* from Git (§5.5) |

---

## 2 · Your apps, and the three deployment targets

### 2.1 The service matrix — this is what you are deploying

These are the exact services from the Docker and Kubernetes learning paths. Same names, same ports, same images.

| Service | Layer | Language | Build tool | Tests | Port | Image |
|---|---|---|---|---|---|---|
| `shop-ui` | **FE** | JavaScript (React) | npm + Vite | Vitest (unit) + Playwright (e2e) | 80 (nginx) | `ghcr.io/3558bhk/shop-ui` |
| `shop-api` | **BE** | Java 21 | Maven (`./mvnw`) | JUnit 5 + Testcontainers | 8080 (+9090 metrics) | `ghcr.io/3558bhk/shop-api` |
| `checkout` | **BE** | Go 1.23 | go modules | `go test -race` | 9091 | `ghcr.io/3558bhk/checkout` |
| `order-worker` | **BE** | Python 3.13 | pip / venv | pytest | 9092 (no HTTP server; queue consumer) | `ghcr.io/3558bhk/order-worker` |
| `payment-mock` | **BE** | Go 1.23 | go modules | `go test -race` | 9093 | `ghcr.io/3558bhk/payment-mock` |
| `postgres`, `redis`, `rabbitmq` | infra | — | — | — | 5432 / 6379 / 5672 | **never built by you** — pinned upstream tags |

⭐ **Every service exposes `/health` (liveness), `/ready` (readiness) and `/metrics` (Prometheus).** That is not a nice-to-have: §6.6 shows that without a readiness probe, a rolling update in Kubernetes *will* drop requests, and your pipeline will report success while users see 502s.

### 2.2 The four deployment shapes you asked for

| Shape | What it is | Services involved | Why it is its own case |
|---|---|---|---|
| **A — FE only** | deploy the React app alone | `shop-ui` | Static assets. No graceful shutdown needed. Cache-busting and `index.html` no-cache are the real problems |
| **B — BE only** | deploy one backend service | `shop-api` *(or)* `checkout` *(or)* `order-worker` | Needs readiness probes, graceful drain, DB migration ordering |
| **C — FE + BE** | deploy both together, as one release | `shop-ui` + `shop-api` | **Version skew.** The FE and BE must be compatible, and for a while they will both be running at once |
| **D — polyglot monorepo** | all five, different languages, one repo | everything | Change detection, parallel builds, per-language caching, one release train |

### 2.3 The three deployment targets (T1 / T2 / T3)

Every scenario below can aim at any of these. Learn all three — interviews ask about all three, and real companies use all three at once.

| | Target | Mechanism | Used by | Reversible in |
|---|---|---|---|---|
| **T1** | **Docker** (single host) | `docker compose pull && docker compose up -d` | dev laptops, demos, single-VM prod, the Docker learning path | seconds (previous tag still on disk) |
| **T2** | **Kubernetes, push** | `kubectl apply` / `helm upgrade` from a pipeline step | most companies, the Kubernetes learning path | `kubectl rollout undo` |
| **T3** | **Kubernetes, GitOps (pull)** | CI writes a digest to a **config repo**; Argo CD syncs it | ⭐ the production-grade answer; the capstone (file 05) | revert the config-repo commit |

```
T1 DOCKER                 T2 K8S PUSH                 T3 GITOPS PULL
─────────                 ───────────                 ──────────────
CI runner                 CI runner                   CI runner
   │                         │                           │
   │ docker push             │ docker push               │ docker push
   ▼                         ▼                           ▼
registry                  registry                    registry
   │                         │                           │
   │ ssh + compose           │ kubectl/helm              │ open PR on config repo
   ▼                         ▼                           ▼
 docker host              ┌──────────┐                ┌────────────┐
                          │ K8s API  │◀───────────────│ shop-config│
                          └──────────┘   Argo CD polls └────────────┘
                                          and syncs       ▲
                                                          │ a HUMAN merges (Delivery)
⛔ CI holds SSH keys   ⚠️ CI holds a kubeconfig       ✅ CI holds NOTHING but
   to prod                  with cluster-admin           write access to a repo
```

⭐⭐⭐ **Why T3 wins for Scenario 2/3:** the CI runner never has a credential that can touch production. The *cluster* pulls. Whoever can merge to `shop-config` can deploy — which means deployment permission becomes a normal, auditable Git permission with `CODEOWNERS`, branch protection and a PR trail. Push-based deploy (T2) requires you to store a long-lived kubeconfig secret in your CI tool, and that secret is almost always over-privileged and almost always outlives the person who created it.

### 2.4 Prerequisites — do this once, before any scenario

```bash
# ── 1. the cluster (from the Kubernetes learning path) ─────────────────────
kind get clusters | grep -q '^cicd$' || kind create cluster --name cicd
kubectl config use-context kind-cicd           # ⭐ the context name is kind-<clustername>
kubectl get nodes                              # ✅ VERIFY: one node, Ready

# ── 2. load the infra namespaces ───────────────────────────────────────────
kubectl create namespace shop-dev       --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace shop-staging   --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace shop-production --dry-run=client -o yaml | kubectl apply -f -
kubectl get ns | grep shop                     # ✅ VERIFY: all three

# ⚠️  kind has NO ingress controller and NO LoadBalancer by default.
#     Install ingress-nginx (see file 05 §1.3) or use port-forward for smoke tests.

# ── 3. the container registry ──────────────────────────────────────────────
# GitHub:      ghcr.io/3558bhk/...       (a PAT with `write:packages`, or OIDC — §3.1)
# Azure:       shopacr.azurecr.io        (`az acr create --sku Basic`)
# Local/offline alternative — no cloud needed at all:
docker run -d --name registry -p 5000:5000 --restart unless-stopped registry:2
#   ⭐ for kind you must ALSO tell the cluster where it is; see file 05 §1.2

# ── 4. log in once locally so you can test pushes by hand ──────────────────
echo "$GHCR_TOKEN" | docker login ghcr.io -u 3558Bhk --password-stdin

# ── 5. the apps (copy them from the Docker/K8s paths) ──────────────────────
ls apps/
# apps/
# ├── checkout/      Dockerfile  go.mod  main.go  main_test.go
# ├── order-worker/  Dockerfile  requirements.txt  worker.py  test_worker.py
# ├── payment-mock/  Dockerfile  go.mod  main.go
# ├── shop-api/      Dockerfile  pom.xml  mvnw  src/
# └── shop-ui/       Dockerfile  package.json  src/  nginx.conf
```

✅ **VERIFY before you continue:** `docker build apps/shop-api -t test:1` succeeds locally, and `kubectl --context kind-cicd -n shop-dev get all` returns without error. If either fails, no pipeline will save you — fix it locally first. ⭐ **Golden rule: never debug a build inside a pipeline. A pipeline is a very slow, very expensive way to run a command.**

---

## 3 · SCENARIO 1 — CI ONLY (no deployment at all)

### 3.0 What CI-only produces, and where the line is

CI's job is to answer **one question**: *is this change good enough to become a release candidate?*

The output is an **artifact**, not a running app. The line is hard:

```
   ┌─────────────────────── SCENARIO 1: CI ONLY ───────────────────────┐
   │                                                                   │
   │  fetch → deps → compile → unit tests → static analysis →          │
   │  security scan → build image → scan image → SBOM → sign →         │
   │  push to registry → publish build metadata                        │
   │                                                        ║          │
   └────────────────────────────────────────────────────────║──────────┘
                                                            ║
                                              ⛔ THE STOP LINE ║
                                                            ║
   ┌──────────────────── SCENARIO 2 PICKS UP HERE ──────────▼──────────┐
   │  take the DIGEST (not the tag) and promote it                     │
   └───────────────────────────────────────────────────────────────────┘
```

**CI must never:** `kubectl` anything, hold a kubeconfig, SSH anywhere, or know that environments exist. ⛔ A CI pipeline with a `deploy-to-dev` step "just to check it works" is how a `kubectl config current-context` typo reaches production. If you need to prove the image runs, do it in an **ephemeral throwaway namespace inside CI** and tear it down in the same job (§3.7).

#### The 9 CI stages, and what each one is actually for

| # | Stage | Tool (examples) | Fails when | ⭐ Why an SDE3 cares |
|---|---|---|---|---|
| 1 | **Fetch + cache deps** | `actions/cache`, Maven `~/.m2`, npm cache, Go build cache | network / lockfile drift | Cache correctness > cache speed. A poisoned cache produces green builds on broken code |
| 2 | **Compile** | `mvnw -q -DskipTests package`, `npm ci && npm run build`, `go build` | syntax / dependency errors | The cheapest possible failure. Put it first |
| 3 | **Unit + integration tests** | JUnit5/Testcontainers, Vitest, Playwright, `go test -race`, pytest | behaviour regression | ⭐ `-race` in Go and Testcontainers in Java are the difference between "tests pass" and "tests are real" |
| 4 | **Static analysis / lint** | Checkstyle+SpotBugs, ESLint, `golangci-lint`, `ruff` | style, dead code, bug patterns | Gate on *new* issues only (`--new-from-rev`) or the team disables it within a month |
| 5 | **Secrets + SCA scan** | Trivy, Gitleaks, Dependabot, OWASP dep-check | leaked credential, CVE in a dependency | ⭐⭐ Fail on **CRITICAL + fixable** only. Failing on every CVE turns the gate into a rubber stamp |
| 6 | **Build image** | `docker buildx` + BuildKit cache | Dockerfile error | Multi-stage, non-root, pinned base **by digest**, `HEALTHCHECK` |
| 7 | **Scan the image** | `trivy image --exit-code 1 --severity CRITICAL` | CVE in the final layer | Scan the *image*, not the lockfile — they disagree constantly |
| 8 | **SBOM + sign** | `syft` (SBOM), `cosign sign` (sigstore) | — | ⭐⭐⭐ Signing is what lets Kyverno refuse unsigned images in prod. Without it, "supply chain security" is a slogan |
| 9 | **Push + publish metadata** | `docker push`, `gh attest`, artifact upload | auth | Push **both** a mutable tag (`main`) and an immutable one (`sha-<gitsha>`), and output the **digest** |

⭐⭐⭐ **The digest is the contract.** `ghcr.io/3558bhk/shop-api:main` can mean something different five minutes from now. `ghcr.io/3558bhk/shop-api@sha256:9f2c…` can never change. **CI outputs a digest; CD consumes a digest.** Everything else in this file follows from that one rule.

### 3.1 🐙 GitHub Actions — CI only

#### 3.1.1 Shape A — **FE only** (`shop-ui`, React)

```yaml
# ══════════════════════════════════════════════════════════════════════
# .github/workflows/ci-frontend.yml
# ══════════════════════════════════════════════════════════════════════
# WHAT   : CI-only pipeline for the React frontend. No deployment step.
# WHY    : shape A — the frontend changes far more often than the backend,
#          so it gets its own fast pipeline (~3 min).
# TARGET : stops at a pushed, signed image + a published digest.
# ══════════════════════════════════════════════════════════════════════

name: ci-frontend

on:
  push:
    branches: [main]
    paths:                          # ⭐ path filter = the polyglot trick.
      - 'apps/shop-ui/**'           #   A Go-only change must not rebuild
      - '.github/workflows/ci-frontend.yml'   #   the React app.
  pull_request:
    branches: [main]
    paths: ['apps/shop-ui/**']
  workflow_dispatch: {}             # ⭐ always add this: lets you re-run
                                    #   manually to test the pipeline itself

# ⭐⭐ LEAST PRIVILEGE. The default token is read/write to everything.
#    `contents: read` is all a CI build needs — until the push job, which
#    needs `packages: write`, declared on that JOB, not here.
permissions:
  contents: read

concurrency:                        # ⭐ cancel superseded runs. If you push
  group: ci-fe-${{ github.ref }}    #   three times in a minute, only the
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}
                                    #   newest matters. BUT: never cancel a
                                    #   run on `main` — it may be mid-push.

env:
  REGISTRY: ghcr.io
  IMAGE: ghcr.io/3558bhk/shop-ui
  APP_DIR: apps/shop-ui

jobs:
  # ── 1. lint + unit tests ───────────────────────────────────────────────
  test:
    name: Lint & unit test
    runs-on: ubuntu-24.04           # ⭐ pin the runner. `ubuntu-latest`
    defaults:                       #   silently changes under you.
      run:
        working-directory: ${{ env.APP_DIR }}
    steps:
      - uses: actions/checkout@v7

      - uses: actions/setup-node@v4
        with:
          node-version: '22'        # ⭐ pin major; match your Dockerfile
          cache: npm                # ⭐ built-in npm cache keyed on the
          cache-dependency-path: ${{ env.APP_DIR }}/package-lock.json

      # `npm ci` — NOT `npm install`. ci deletes node_modules and installs
      # exactly what the lockfile says. `install` may silently UPDATE the
      # lockfile, which means CI and prod build different trees.
      - run: npm ci

      - run: npm run lint           # ESLint. ⛔ never `|| true` this.

      # Vitest. `--coverage` gives you the number to trend over time.
      - run: npm run test -- --run --coverage

      - name: Upload coverage        # artifacts are how you debug a red
        if: always()                 # build after the runner is gone.
        uses: actions/upload-artifact@v4
        with:
          name: fe-coverage
          path: ${{ env.APP_DIR }}/coverage/
          retention-days: 7

  # ── 2. e2e (Playwright) — separate job so it can run in PARALLEL ───────
  e2e:
    name: E2E (Playwright)
    runs-on: ubuntu-24.04
    needs: test                     # ⭐ ordering. Without `needs`, GitHub
    defaults:                       #   runs jobs concurrently by default.
      run:
        working-directory: ${{ env.APP_DIR }}
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-node@v4
        with: { node-version: '22', cache: npm, cache-dependency-path: '${{ env.APP_DIR }}/package-lock.json' }
      - run: npm ci
      - run: npx playwright install --with-deps chromium   # only chromium in
        # CI — installing all three browsers triples the job for no benefit.
      - run: npm run e2e
      - uses: actions/upload-artifact@v4
        if: failure()               # ⭐ only on failure: traces are huge
        with:
          name: playwright-trace
          path: ${{ env.APP_DIR }}/playwright-report/
          retention-days: 3

  # ── 3. build + scan + sign + push ──────────────────────────────────────
  image:
    name: Build, scan, sign & push image
    runs-on: ubuntu-24.04
    needs: [test, e2e]              # ⛔ never build the image before the
    permissions:                    #   tests pass — you'd be publishing
      contents: write               #   broken artifacts.
      packages: write               # push to GHCR
      id-token: write               # ⭐⭐ OIDC: proves "this run came from
                                    #   this repo, this ref" to sigstore,
                                    #   with NO stored secret at all.
      attestations: write           # for `gh attestation`
    outputs:
      digest: ${{ steps.push.outputs.digest }}     # ⭐ THE CONTRACT.
      version: ${{ steps.meta.outputs.version }}   #   CD consumes this.
    steps:
      - uses: actions/checkout@v7

      - uses: docker/setup-buildx-action@v3       # BuildKit + layer cache

      # ⭐ OIDC login — no PAT, no secret to rotate, no leak risk.
      - uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          # username/password omitted → the action uses the OIDC token
          # when `id-token: write` is granted and GHCR trusts the repo.

      - id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.IMAGE }}
          tags: |
            type=sha,prefix=sha-,format=short      # ⭐ immutable: sha-a1b2c3d
            type=ref,event=branch                  # mutable: main
            type=ref,event=pr                      # mutable: pr-42

      - id: push
        uses: docker/build-push-action@v6
        with:
          context: ${{ env.APP_DIR }}
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          # ⭐⭐ registry cache. This is what takes a React build from
          #    4 min to 40 s. `mode=max` caches intermediate layers too.
          cache-from: type=gha,scope=shop-ui
          cache-to: type=gha,scope=shop-ui,mode=max
          provenance: mode=max                     # SLSA provenance attestation
          sbom: true                               # ⭐ in-image SBOM

      # ⭐ scan the FINAL image, not the source tree.
      - uses: aquasecurity/trivy-action@0.28.0     # ⭐ pin actions by version
        with:                                       #   or by full SHA in prod
          image-ref: '${{ env.IMAGE }}@${{ steps.push.outputs.digest }}'
          format: table
          exit-code: '1'                            # ⛔ fail the build
          severity: CRITICAL,HIGH
          ignore-unfixed: true                      # ⭐ no fix = not actionable
                                                    #   = don't block the merge

      # ⭐⭐ sign it. This is what Kyverno verifies in production (file 05 §1.3).
      - name: Sign with cosign (keyless)
        run: |
          cosign sign --yes "${IMAGE}@${DIGEST}"
          echo "::notice::signed ${IMAGE}@${DIGEST}"
        env:
          DIGEST: ${{ steps.push.outputs.digest }}

      # ⭐ the machine-readable attestation: "this digest was built from
      #    this commit, by this workflow". Verifiable later, forever.
      - name: Attest build
        uses: actions/attest-build-provenance@v1
        with:
          subject-name: ${{ env.IMAGE }}
          subject-digest: ${{ steps.push.outputs.digest }}

      - name: Publish digest for CD
        run: |
          # ⭐⭐ write the digest to a file CD can read. In Scenario 3 this
          #    becomes a PR against shop-config. In Scenario 1 it is simply
          #    the end of the road — and that is correct.
          echo "shop-ui=${{ steps.push.outputs.digest }}" > digest.txt
          cat digest.txt
      - uses: actions/upload-artifact@v4
        with: { name: fe-digest, path: digest.txt, retention-days: 30 }
```

✅ **VERIFY:**
```bash
gh run list --workflow ci-frontend.yml --limit 1
gh run watch                              # live log
gh run view <id> --log | grep -i digest   # the sha256 must appear
# then prove the image is real, from your laptop:
docker pull ghcr.io/3558bhk/shop-ui@sha256:<digest>
cosign verify ghcr.io/3558bhk/shop-ui@sha256:<digest> \
  --certificate-identity-regexp='https://github.com/3558Bhk/' \
  --certificate-oidc-issuer='https://token.actions.githubusercontent.com'
```
⛔ **If `cosign verify` fails, you have not built a CI pipeline — you have built a picture of one.**

### 3.1.2 Shape B — **BE only** (`shop-api`, Java 21 + Maven)

The Java-specific parts are the ones people get wrong. Comments carry the weight here.

```yaml
# .github/workflows/ci-backend.yml
name: ci-backend

on:
  push:
    branches: [main]
    paths: ['apps/shop-api/**', '.github/workflows/ci-backend.yml']
  pull_request:
    branches: [main]
    paths: ['apps/shop-api/**']
  workflow_dispatch: {}

permissions: { contents: read }
concurrency:
  group: ci-be-${{ github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}

env:
  IMAGE: ghcr.io/3558bhk/shop-api
  APP_DIR: apps/shop-api

jobs:
  build-and-test:
    name: Build & test (Java 21)
    runs-on: ubuntu-24.04
    defaults: { run: { working-directory: '${{ env.APP_DIR }}' } }
    steps:
      - uses: actions/checkout@v7

      - uses: actions/setup-java@v5
        with:
          distribution: temurin          # ⭐ Temurin, not `oracle` — the
          java-version: '21'             #   Oracle JDK has licence terms.
          cache: maven                   # caches ~/.m2 keyed on pom.xml

      # ⭐⭐ THE MAVEN TRICK EVERYONE MISSES:
      #   -B            batch mode: no colour codes, no interactive prompts.
      #                 Without it the log is full of ANSI escapes.
      #   -ntp          "no transfer progress": suppresses the per-file
      #                 download spam that makes a 40 MB log.
      #   --fail-at-end  run ALL modules, then fail. Default (-ff) stops at
      #                 the first failure, so you fix one error per push and
      #                 take a week to find five bugs.
      #   verify        not `test` — `verify` also runs integration tests
      #                 bound to the integration-test phase.
      - name: Build + test
        run: ./mvnw -B -ntp --fail-at-end verify
        env:
          # ⭐ Testcontainers needs Docker. GitHub runners HAVE a Docker
          #   daemon, so this just works. On Jenkins-in-K8s it does not —
          #   see §3.5.3 (DinD vs the docker socket vs a real DB service).
          TESTCONTAINERS_RYUK_DISABLED: 'false'

      # ⭐ publish the test results even when tests FAIL. This is the single
      #   most useful artifact in the whole pipeline — `if: always()` is
      #   doing the work here; the default is `success()`.
      - name: Publish test report
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: surefire-reports
          path: ${{ env.APP_DIR }}/target/surefire-reports/
          retention-days: 14

      - name: Publish JAR
        uses: actions/upload-artifact@v4
        with:
          name: shop-api-jar
          path: ${{ env.APP_DIR }}/target/*.jar
          retention-days: 7

  static-analysis:
    name: Checkstyle, SpotBugs, OWASP
    runs-on: ubuntu-24.04
    needs: build-and-test
    defaults: { run: { working-directory: '${{ env.APP_DIR }}' } }
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-java@v5
        with: { distribution: temurin, java-version: '21', cache: maven }
      # ⭐ run these in ONE mvn invocation. Three invocations = three
      #   dependency resolutions = three times the wall clock.
      - run: ./mvnw -B -ntp checkstyle:check spotbugs:check
      - name: Dependency CVE scan
        run: ./mvnw -B -ntp org.owasp:dependency-check-maven:check \
              -DfailBuildOnCVSS=7
        # ⚠️ dependency-check downloads the whole NVD (~1 GB) on first run.
        #    In a real team you either cache the NVD mirror or use Trivy on
        #    the built image instead. Do not let this step make CI 12 minutes.
      - uses: actions/upload-artifact@v4
        if: always()
        with: { name: owasp-report, path: '${{ env.APP_DIR }}/target/dependency-check-report.html' }

  image:
    name: Build, scan, sign & push image
    runs-on: ubuntu-24.04
    needs: [build-and-test, static-analysis]
    permissions: { contents: write, packages: write, id-token: write, attestations: write }
    outputs:
      digest: ${{ steps.push.outputs.digest }}
    steps:
      - uses: actions/checkout@v7
      # ⭐⭐ download the JAR the test job already built. Without this you
      #   compile the Java code TWICE, and — much worse — you ship a JAR
      #   that was not the JAR you tested.
      - uses: actions/download-artifact@v4
        with: { name: shop-api-jar, path: '${{ env.APP_DIR }}/target' }

      - uses: docker/setup-buildx-action@v3
      - uses: docker/login-action@v3
        with: { registry: ghcr.io }

      - id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.IMAGE }}
          tags: |
            type=sha,prefix=sha-,format=long
            type=ref,event=branch

      - id: push
        uses: docker/build-push-action@v6
        with:
          context: ${{ env.APP_DIR }}
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha,scope=shop-api
          cache-to: type=gha,scope=shop-api,mode=max
          provenance: mode=max
          sbom: true

      - uses: aquasecurity/trivy-action@0.28.0
        with:
          image-ref: '${{ env.IMAGE }}@${{ steps.push.outputs.digest }}'
          exit-code: '1'
          severity: CRITICAL
          ignore-unfixed: true
          # ⭐ a JVM image is full of "unfixed" CVEs in glibc that will never
          #    be patched this quarter. Blocking on them = a permanently red
          #    pipeline = a team that stops reading it.

      - run: cosign sign --yes "${IMAGE}@${{ steps.push.outputs.digest }}"
        env: { IMAGE: ${{ env.IMAGE }} }

      - uses: actions/attest-build-provenance@v1
        with:
          subject-name: ${{ env.IMAGE }}
          subject-digest: ${{ steps.push.outputs.digest }}
```

⭐⭐ **The JVM caching nuance.** `actions/setup-java`'s `cache: maven` caches `~/.m2/repository` — the *dependencies*. It does **not** cache compiled output. If your build is slow, the fix is usually the Dockerfile, not the pipeline:

```dockerfile
# ⛔ SLOW — every code change invalidates the dependency download
FROM eclipse-temurin:21-jdk AS build
WORKDIR /app
COPY . .                       # ← any change busts the cache here
RUN ./mvnw -B -ntp package

# ✅ FAST — dependencies are a separate, rarely-changing layer
FROM eclipse-temurin:21-jdk AS build
WORKDIR /app
COPY pom.xml mvnw ./           # ← poms change maybe weekly
COPY .mvn .mvn
RUN ./mvnw -B -ntp dependency:go-offline    # ← cached until a pom changes
COPY src ./src                 # ← code changes bust only THIS layer down
RUN ./mvnw -B -ntp -DskipTests package

FROM eclipse-temurin:21-jre AS runtime      # ⭐ JRE not JDK: ~200 MB smaller
WORKDIR /app
RUN groupadd -r app && useradd -r -g app app # ⭐ never run as root
COPY --from=build --chown=app:app /app/target/*.jar app.jar
USER app
EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=3s --start-period=40s --retries=3 \
  CMD wget -qO- http://localhost:8080/actuator/health | grep -q '"UP"'
# ⭐ `--start-period=40s`: Spring Boot takes 15–30 s to start. Without a
#   start period, Docker kills a perfectly healthy container during boot.
ENTRYPOINT ["java","-XX:MaxRAMPercentage=75","-jar","app.jar"]
# ⭐ NEVER `-Xmx2g` in a container. The JVM must size itself from the
#   cgroup limit, or Kubernetes OOMKills it. See file 05 §6.
```

### 3.1.3 Shape D — **polyglot monorepo** (all five services, one workflow)

This is the version to show in an interview. One workflow, change detection, a matrix over languages, parallel per-service builds, one combined artifact.

```yaml
# .github/workflows/ci-monorepo.yml
name: ci-monorepo

on:
  push: { branches: [main] }
  pull_request: { branches: [main] }
  workflow_dispatch: {}

permissions: { contents: read }

jobs:
  # ══ JOB 1: WHAT CHANGED? ═══════════════════════════════════════════════
  # ⭐⭐ The whole polyglot trick lives here. One cheap job computes a set of
  #    booleans; every expensive job is gated on one of them.
  changes:
    runs-on: ubuntu-24.04
    permissions: { contents: read, pull-requests: read }
    outputs:
      ui:       ${{ steps.filter.outputs.ui }}
      api:      ${{ steps.filter.outputs.api }}
      go:       ${{ steps.filter.outputs.go }}
      python:   ${{ steps.filter.outputs.python }}
      infra:    ${{ steps.filter.outputs.infra }}
      any-app:  ${{ steps.filter.outputs.any-app }}
    steps:
      - uses: actions/checkout@v7
      - uses: dorny/paths-filter@v3
        id: filter
        with:
          # ⭐ on `push` to main the comparison base is the previous commit;
          #   on a PR it is the merge base. The action handles both.
          filters: |
            ui:
              - 'apps/shop-ui/**'
            api:
              - 'apps/shop-api/**'
            go:
              - 'apps/checkout/**'
              - 'apps/payment-mock/**'
            python:
              - 'apps/order-worker/**'
            infra:
              - 'deploy/**'                 # k8s manifests / helm chart
              - '.github/workflows/**'
            any-app:
              - 'apps/**'
      - name: Show what changed
        run: |
          echo "ui=${{ steps.filter.outputs.ui }} api=${{ steps.filter.outputs.api }}"
          echo "go=${{ steps.filter.outputs.go }} python=${{ steps.filter.outputs.python }}"

  # ══ JOB 2: THE TWO GO SERVICES AS ONE MATRIX ═══════════════════════════
  # ⭐ `checkout` and `payment-mock` are the SAME language and the SAME
  #    build steps. Do not copy-paste two jobs — matrix them. When you later
  #    add a third Go service you add ONE LINE.
  go:
    needs: changes
    if: needs.changes.outputs.go == 'true'          # ⭐ skipped entirely
    runs-on: ubuntu-24.04                           #   when nothing changed
    strategy:
      fail-fast: false              # ⭐⭐ CRITICAL. Default is `true`, which
      matrix:                       #   CANCELS the sibling matrix jobs when
        service: [checkout, payment-mock]           # one fails. You lose the
    name: Go — ${{ matrix.service }}                # other service's result.
    outputs: {}
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-go@v5
        with:
          go-version-file: apps/${{ matrix.service }}/go.mod   # ⭐ single
          cache-dependency-path: apps/${{ matrix.service }}/go.sum  # source
      # ⭐ THE GO CI INCANTATION, and why each flag exists:
      #   -race    the race detector. Go code without -race in CI is untested.
      #   -shuffle=on   randomise test order → finds hidden ordering deps.
      #   -coverprofile  coverage in a machine-readable form.
      #   ./...    every package in the module, not just the root.
      - run: go test -race -shuffle=on -coverprofile=cover.out ./...
        working-directory: apps/${{ matrix.service }}
      - run: go vet ./...
        working-directory: apps/${{ matrix.service }}
      - name: golangci-lint
        uses: golangci/golangci-lint-action@v6
        with:
          version: v1.61
          working-directory: apps/${{ matrix.service }}
          # ⭐ on a PR, only complain about issues in the CHANGED lines.
          #   Otherwise you inherit 400 pre-existing findings and the linter
          #   gets deleted from the pipeline within a fortnight.
          only-new-issues: ${{ github.event_name == 'pull_request' }}
      - run: go build -o /tmp/${{ matrix.service }} ./...
        working-directory: apps/${{ matrix.service }}
      - run: go tool cover -func=cover.out | tail -1   # total: (statements) %
        working-directory: apps/${{ matrix.service }}

  # ══ JOB 3: PYTHON ══════════════════════════════════════════════════════
  python:
    needs: changes
    if: needs.changes.outputs.python == 'true'
    runs-on: ubuntu-24.04
    defaults: { run: { working-directory: apps/order-worker } }
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-python@v5
        with:
          python-version: '3.13'
          cache: pip
          cache-dependency-path: apps/order-worker/requirements.txt
      - run: |
          python -m venv .venv && . .venv/bin/activate
          pip install -r requirements.txt -r requirements-dev.txt
      - run: . .venv/bin/activate && ruff check . && ruff format --check .
      # ⭐ pytest flags that matter:
      #   -x        stop at first failure (fast feedback) — REMOVE this for
      #             the nightly full run so you see everything
      #   --ff      run last-failed tests FIRST
      #   -n auto   pytest-xdist: parallelise across cores
      #   --cov     coverage
      - run: |
          . .venv/bin/activate
          pytest --ff -n auto --cov=worker --cov-report=xml --cov-report=term
      - uses: actions/upload-artifact@v4
        if: always()
        with: { name: py-coverage, path: apps/order-worker/coverage.xml }

  # ══ JOB 4: FE + JAVA delegate to the dedicated workflows ═══════════════
  # ⭐⭐ Do not duplicate. Call the single-service workflows as REUSABLE
  #    workflows so there is exactly ONE definition of "how we build Java".
  frontend:
    needs: changes
    if: needs.changes.outputs.ui == 'true'
    uses: ./.github/workflows/ci-frontend.yml     # must have
    permissions:                                  # `workflow_call:` in its
      contents: write                             #  `on:` block to be
      packages: write                             #  callable this way.
      id-token: write
      attestations: write

  backend:
    needs: changes
    if: needs.changes.outputs.api == 'true'
    uses: ./.github/workflows/ci-backend.yml
    permissions:
      contents: write
      packages: write
      id-token: write
      attestations: write

  # ══ JOB 5: THE GATE — did everything that ran, pass? ═══════════════════
  # ⭐⭐⭐ Make THIS the required status check in branch protection, not the
  #    individual jobs. Individual jobs get skipped, and a skipped job
  #    satisfies a required check as "passed" — which means a change that
  #    touched only Go can merge without Java ever compiling.
  ci-result:
    name: CI result (the required check)
    runs-on: ubuntu-24.04
    if: always()                                  # ⭐ runs even when a dep
    needs: [changes, go, python, frontend, backend]  # failed or was skipped
    steps:
      - name: Evaluate
        run: |
          # `needs.<job>.result` ∈ {success, failure, cancelled, skipped}
          # ⭐ skipped is FINE (nothing changed). failure is not.
          echo "go       = ${{ needs.go.result }}"
          echo "python   = ${{ needs.python.result }}"
          echo "frontend = ${{ needs.frontend.result }}"
          echo "backend  = ${{ needs.backend.result }}"
          bad=0
          for r in "${{ needs.go.result }}" "${{ needs.python.result }}" \
                   "${{ needs.frontend.result }}" "${{ needs.backend.result }}"; do
            if [ "$r" = "failure" ] || [ "$r" = "cancelled" ]; then bad=1; fi
          done
          [ "$bad" -eq 0 ] || { echo "::error::one or more CI jobs failed"; exit 1; }
          echo "✅ CI green"
```

⭐⭐⭐ **That last job is the interview answer.** Ask any engineer how they gate a polyglot monorepo and most will say "each service has its own required check". That breaks the moment a service's job is skipped. The aggregator pattern — one `if: always()` job that reads every `needs.*.result` and treats `skipped` as acceptable — is what staff engineers actually do.

### 3.2 🔷 Azure DevOps — CI only

#### 3.2.1 The reusable template (write this once, use it five times)

```yaml
# ══════════════════════════════════════════════════════════════════════
# ci/templates/build-test-image.yml   — a reusable CI template
# ══════════════════════════════════════════════════════════════════════
# WHAT   : parameterised template = GitHub's reusable workflow.
# WHY    : five services, one definition of "how we build".
# ⭐ Note `parameters` are resolved at COMPILE time (YAML expansion),
#   `variables` at RUNTIME. Parameters can be used in `if:` conditions
#   and to build task names; variables cannot. Getting this wrong is the
#   most common Azure YAML error.
# ══════════════════════════════════════════════════════════════════════
parameters:
  - name: service            # e.g. shop-api
    type: string
  - name: language           # java | node | go | python
    type: string
    values: [java, node, go, python]
  - name: appDir             # e.g. apps/shop-api
    type: string
  - name: buildCmd
    type: string
    default: ''
  - name: testCmd
    type: string
  - name: registry           # shopacr.azurecr.io  OR  ghcr.io
    type: string
  - name: dockerRegistryServiceConnection
    type: string             # ⭐ a SERVICE CONNECTION, not a secret. ADO
                             #   stores the credential; the YAML only names it.
  - name: pool
    type: object
    default: { vmImage: 'ubuntu-24.04' }

jobs:
  - job: test_${{ parameters.service }}
    displayName: 'Test — ${{ parameters.service }}'
    pool: ${{ parameters.pool }}
    workspace:                       # ⭐ clean the agent workspace. Self-hosted
      clean: all                     #   agents reuse directories between runs,
    steps:                           #   and stale files cause phantom failures.

      - ${{ if eq(parameters.language, 'java') }}:
        - task: JavaToolInstaller@0
          inputs: { versionSpec: '21', jdkArchitectureOption: 'x64',
                    jdkSourceOption: 'PreInstalled' }
        - task: Cache@2
          inputs:
            key: 'maven | "$(Agent.OS)" | ${{ parameters.appDir }}/pom.xml'
            path: $(MAVEN_HOME)/.m2       # ⭐ Azure has no built-in Maven cache
            restoreKeys: maven | "$(Agent.OS)"

      - ${{ if eq(parameters.language, 'node') }}:
        - task: NodeTool@0
          inputs: { versionSpec: '22.x' }

      - ${{ if eq(parameters.language, 'go') }}:
        - task: GoTool@0
          inputs: { version: '1.23.0' }

      - ${{ if eq(parameters.language, 'python') }}:
        - task: UsePythonVersion@0
          inputs: { versionSpec: '3.13' }

      - script: ${{ parameters.testCmd }}
        displayName: 'Run tests'
        workingDirectory: ${{ parameters.appDir }}

      # ⭐ `condition: succeededOrFailed()` = GitHub's `if: always()`.
      - task: PublishTestResults@2
        displayName: 'Publish test results'
        condition: succeededOrFailed()
        inputs:
          testResultsFormat: 'JUnit'          # or VSTest, NUnit, XUnit, cTest
          testResultsFiles: '**/TEST-*.xml'
          searchFolder: ${{ parameters.appDir }}
          failTaskOnFailedTests: true          # ⛔ without this, a failed test
                                               #   is a WARNING and the build
                                               #   goes green. Yes, really.

  - job: image_${{ parameters.service }}
    displayName: 'Image — ${{ parameters.service }}'
    dependsOn: test_${{ parameters.service }}   # ⭐ = GitHub's `needs:`
    pool: ${{ parameters.pool }}
    variables:
      # ⭐⭐ compute the image tag ONCE and reuse it. Inline expressions get
      #   re-evaluated and can drift between steps.
      IMG: ${{ parameters.registry }}/${{ parameters.service }}
      TAG: sha-$(Build.SourceVersion)          # Build.SourceVersion = git SHA
    steps:
      - task: Docker@2
        displayName: 'Login'
        inputs:
          command: login
          containerRegistry: ${{ parameters.dockerRegistryServiceConnection }}

      - task: Docker@2
        displayName: 'Build & push'
        inputs:
          command: buildAndPush
          repository: ${{ parameters.service }}
          Dockerfile: ${{ parameters.appDir }}/Dockerfile
          buildContext: ${{ parameters.appDir }}
          containerRegistry: ${{ parameters.dockerRegistryServiceConnection }}
          tags: |
            $(TAG)
            latest
          arguments: >
            --cache-from $(IMG):latest
            --label "org.opencontainers.image.revision=$(Build.SourceVersion)"

      # ⭐ Trivy as a plain script task. There is a marketplace extension,
      #   but the CLI is more portable and easier to pin.
      - script: |
          set -euo pipefail
          curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh \
            | sh -s -- -b $(Agent.TempDirectory) v0.56.2
          $(Agent.TempDirectory)/trivy image --exit-code 1 \
            --severity CRITICAL --ignore-unfixed \
            $(IMG):$(TAG)
        displayName: 'Trivy scan (fail on CRITICAL)'

      - task: Docker@2
        displayName: 'Logout'
        condition: always()                    # ⭐ never leave a session open
        inputs:
          command: logout
          containerRegistry: ${{ parameters.dockerRegistryServiceConnection }}

      # ⭐⭐ THE HANDOFF TO CD. In Azure DevOps the idiomatic artifact is
      #   a build artifact; in Scenario 2/3 CD downloads it by name.
      - script: |
          echo "${{ parameters.service }}=$(IMG):$(TAG)" > $(Pipeline.Workspace)/img.txt
          docker inspect --format='{{index .RepoDigests 0}}' $(IMG):$(TAG) \
            | tee $(Pipeline.Workspace)/digest.txt
        displayName: 'Record image + digest'
      - task: PublishBuildArtifacts@1
        inputs:
          pathToPublish: $(Pipeline.Workspace)
          artifactName: image-refs              # ⭐ CD consumes THIS name
```

#### 3.2.2 The pipeline that uses it — FE, BE and polyglot in one file

```yaml
# ci-azure.yml   (point a pipeline at this file, or use azure-pipelines.yml)
trigger:
  batch: true              # ⭐ collapse rapid pushes into one run
  branches: { include: [main] }
  paths:
    include: [apps/*]      # ⭐ path filter, same idea as GitHub

pr:
  branches: { include: [main] }

pool: { vmImage: 'ubuntu-24.04' }

variables:
  - group: shop-ci          # ⭐ a variable group. Non-secret config lives here.
  # ⛔ NEVER put secrets in this file or in a plain variable group.
  #    Secrets go in Key Vault, linked via a service connection with
  #    Workload Identity Federation — no client secret to rotate, ever.
  - name: ACR
    value: shopacr.azurecr.io
  - name: ACR_CONN
    value: shop-acr-wif     # ⭐ the service connection name (created in
                            #   Project Settings → Service connections)

stages:
  # ── STAGE: CI ONLY. Note there is deliberately NO deploy stage. ────────
  - stage: CI
    displayName: 'CI — build, test, image (NO deploy)'
    jobs:
      # FE only ──────────────────────────────────────────────────────────
      - template: ci/templates/build-test-image.yml
        parameters:
          service: shop-ui
          language: node
          appDir: apps/shop-ui
          testCmd: 'npm ci && npm run lint && npm run test -- --run'
          registry: $(ACR)
          dockerRegistryServiceConnection: $(ACR_CONN)

      # BE only — Java ───────────────────────────────────────────────────
      - template: ci/templates/build-test-image.yml
        parameters:
          service: shop-api
          language: java
          appDir: apps/shop-api
          testCmd: './mvnw -B -ntp --fail-at-end verify'
          registry: $(ACR)
          dockerRegistryServiceConnection: $(ACR_CONN)

      # BE only — Go ─────────────────────────────────────────────────────
      - template: ci/templates/build-test-image.yml
        parameters:
          service: checkout
          language: go
          appDir: apps/checkout
          testCmd: 'go test -race -shuffle=on ./... && go vet ./...'
          registry: $(ACR)
          dockerRegistryServiceConnection: $(ACR_CONN)

      # BE only — Python ─────────────────────────────────────────────────
      - template: ci/templates/build-test-image.yml
        parameters:
          service: order-worker
          language: python
          appDir: apps/order-worker
          testCmd: 'pip install -r requirements.txt -r requirements-dev.txt && pytest -q'
          registry: $(ACR)
          dockerRegistryServiceConnection: $(ACR_CONN)

  # ⭐⭐ NO deploy stage. That is Scenario 1. The pipeline ENDS with a
  #    published artifact named `image-refs`. Add a `Deploy` stage and you
  #    are in Scenario 3.
```

⭐ **Azure-specific gotchas worth knowing in an interview:**

| Gotcha | Symptom | Fix |
|---|---|---|
| `failTaskOnFailedTests` defaults to false | Tests fail, build is green | Set it to `true` on `PublishTestResults@2` |
| Parallel jobs limited by tier | 5 services build one at a time | Free tier = 1 parallel job. Buy more, or move to self-hosted agents |
| `parameters` vs `variables` | "Unexpected value" at compile time | Parameters are compile-time; use `${{ }}` for them, `$()` for variables |
| Self-hosted agent workspace | Stale `node_modules`, phantom failures | `workspace: clean: all` |
| Agent pool `ubuntu-latest` | Silent OS upgrades break builds | Pin `ubuntu-24.04` |
| Secrets in variable groups | Rotatable by anyone with project access | Key Vault + Workload Identity Federation |

### 3.3 🔨 Jenkins — CI only

#### 3.3.1 A shared library first (this is what makes Jenkins scale)

```groovy
// ══════════════════════════════════════════════════════════════════════
// vars/ciPipeline.groovy   — in a repo named `shop-shared` (a Jenkins
//                            shared library, configured under Manage Jenkins
//                            → System → Global Pipeline Libraries)
// ══════════════════════════════════════════════════════════════════════
// WHAT   : a callable "whole CI pipeline" as one function.
// WHY    : ⭐⭐ a Jenkinsfile per service duplicates 200 lines five times.
//          With a shared library each Jenkinsfile is 6 lines. When you fix
//          a bug in the build you fix it ONCE.
// USAGE  : see §3.3.2
// ══════════════════════════════════════════════════════════════════════

def call(Map cfg) {
  // ⭐ give every parameter a default so callers pass only what differs.
  def service   = cfg.service                       // required
  def appDir    = cfg.appDir    ?: "apps/${service}"
  def language  = cfg.language  ?: 'java'
  def testCmd   = cfg.testCmd                       // required
  def registry  = cfg.registry  ?: 'ghcr.io/3558bhk'
  def image     = "${registry}/${service}"

  pipeline {
    // ⭐⭐ DYNAMIC KUBERNETES AGENT. The agent pod is created for this build
    //    and destroyed after. No idle agents, no shared-state contamination.
    //    This is the single biggest reason to run Jenkins on Kubernetes.
    agent {
      kubernetes {
        defaultContainer 'jnlp'
        yaml """
apiVersion: v1
kind: Pod
metadata:
  labels:
    jenkins-agent: shop-ci
spec:
  # ⭐ never run the build in the jnlp container — it's the agent channel.
  containers:
    - name: maven
      image: maven:3.9-eclipse-temurin-21          # ⭐ pin, don't use latest
      command: ['sleep']
      args: ['infinity']                             # ⭐ keep it alive so the
      resources:                                     #   pipeline can exec in
        requests: { cpu: '500m', memory: '1Gi' }
        limits:   { cpu: '2',    memory: '3Gi' }
      volumeMounts:
        - { name: m2, mountPath: /root/.m2 }         # ⭐ PVC = the dep cache
    - name: node
      image: node:22
      command: ['sleep']
      args: ['infinity']
    - name: golang
      image: golang:1.23
      command: ['sleep']
      args: ['infinity']
    - name: python
      image: python:3.13
      command: ['sleep']
      args: ['infinity']
    - name: docker
      image: docker:27-cli
      command: ['sleep']
      args: ['infinity']
      volumeMounts:
        - { name: docker-sock, mountPath: /var/run/docker.sock }
        # ⚠️⚠️ MOUNTING THE DOCKER SOCKET IS ROOT-EQUIVALENT ON THE NODE.
        #   Acceptable in a single-tenant learning cluster. In a shared
        #   cluster use Kaniko or BuildKit rootless instead — §3.3.3.
    - name: trivy
      image: aquasec/trivy:0.56.2
      command: ['sleep']
      args: ['infinity']
    volumes:
      - name: m2
        persistentVolumeClaim: { claimName: jenkins-m2 }
      - name: docker-sock
        hostPath: { path: /var/run/docker.sock }
  # ⭐ do NOT give this pod a service account with cluster permissions.
  serviceAccountName: jenkins-agent     # minimal RBAC: no cluster roles
"""
      }
    }

    options {
      timestamps()                       // every log line gets a time
      buildDiscarder(logRotator(numToKeepStr: '30'))   // ⭐ disk is the #1
      timeout(time: 30, unit: 'MINUTES') // ⭐ a hung build burns an agent
      disableConcurrentBuilds()          // ⭐ for CI: two runs at once on
                                         //   the same branch corrupt caches
      skipDefaultCheckout(true)          // ⭐ we check out inside a container
    }

    environment {
      // ⭐ credentials() masks the value in logs automatically. Printing it
      //   writes `****`. It is NOT encrypted at rest in the build record —
      //   it is injected as an env var for the duration of the step.
      GHCR_USER = credentials('ghcr-username')
      GHCR_PASS = credentials('ghcr-token')
      GIT_SHA   = "${env.GIT_COMMIT?.take(8) ?: 'local'}"
      TAG       = "sha-${GIT_SHA}"
    }

    stages {
      stage('Checkout') {
        steps {
          // ⭐ checkout scm = "the repo and ref that triggered this job".
          //   Works identically for multibranch, webhook and manual runs.
          checkout scm
        }
      }

      stage('Test') {
        steps {
          // ⭐ `container('x')` selects which pod container runs the shell.
          //   Without it everything runs in `jnlp`, which has no toolchain.
          container(containerFor(language)) {
            dir(appDir) { sh testCmd }
          }
        }
        post {
          // ⭐ publish results whether or not the tests passed.
          always {
            junit allowEmptyResults: true, testResults: "${appDir}/**/TEST-*.xml"
          }
        }
      }

      stage('Build image') {
        steps {
          container('docker') {
            dir(appDir) {
              sh """
                set -eu
                docker build \\
                  --label org.opencontainers.image.revision=\$GIT_COMMIT \\
                  -t ${image}:${TAG} .
              """
            }
          }
        }
      }

      stage('Scan') {
        steps {
          container('trivy') {
            // ⭐ `--exit-code 1` makes Trivy fail the build. Without it,
            //   Trivy prints 400 CVEs and the stage goes GREEN.
            sh "trivy image --exit-code 1 --severity CRITICAL --ignore-unfixed ${image}:${TAG}"
          }
        }
      }

      stage('Push') {
        steps {
          container('docker') {
            sh """
              set -eu
              echo "\$GHCR_PASS" | docker login ghcr.io -u "\$GHCR_USER" --password-stdin
              docker push ${image}:${TAG}
              docker tag  ${image}:${TAG} ${image}:latest
              docker push ${image}:latest
              docker inspect --format='{{index .RepoDigests 0}}' ${image}:${TAG} > digest.txt
              cat digest.txt
            """
            archiveArtifacts artifacts: "${appDir}/digest.txt", fingerprint: true
            // ⭐ fingerprint: true links the artifact to the build, so you can
            //   later ask "which builds produced this exact digest?"
          }
        }
      }
    }

    post {
      always  { container('docker') { sh 'docker logout ghcr.io || true' } }
      failure { echo "⛔ CI FAILED for ${service} — ${env.BUILD_URL}" }
      // ⭐⭐ clean up the agent pod's local images. Jenkins agents on a
      //   shared node fill the disk with dangling images within a week.
      cleanup { container('docker') { sh 'docker system prune -af --volumes || true' } }
    }
  }
}

// ⭐ the language → container mapping, in one place.
private String containerFor(String lang) {
  switch (lang) {
    case 'java':   return 'maven'
    case 'node':   return 'node'
    case 'go':     return 'golang'
    case 'python': return 'python'
    default: throw new IllegalArgumentException("unknown language: ${lang}")
  }
}
```

#### 3.3.2 The five Jenkinsfiles — now six lines each

```groovy
// apps/shop-api/Jenkinsfile  ── BE only (Java) ──────────────────────────
@Library('shop-shared@main') _        // ⭐ pin the library to a ref. An
                                      //   unpinned @Library('shop-shared')
                                      //   tracks the default branch and a
                                      //   bad library commit breaks EVERY
                                      //   job in the company at once.
ciPipeline(
  service : 'shop-api',
  language: 'java',
  testCmd : './mvnw -B -ntp --fail-at-end verify'
)
```

```groovy
// apps/shop-ui/Jenkinsfile  ── FE only (React) ──────────────────────────
@Library('shop-shared@main') _
ciPipeline(
  service : 'shop-ui',
  language: 'node',
  testCmd : 'npm ci && npm run lint && npm run test -- --run'
)
```

```groovy
// Jenkinsfile  (repo root) ── polyglot: all five in PARALLEL ────────────
@Library('shop-shared@main') _

// ⭐⭐ `when { changeset "apps/x/**" }` is Jenkins' path filter. It skips a
//   STAGE when no file under that path changed in this build's commit range.
pipeline {
  agent none                              // ⭐ no top-level agent: each
  options { timestamps() }                //   branch allocates its own

  stages {
    stage('CI') {
      parallel {                          // ⭐ all five services at once
        stage('shop-ui') {
          when { changeset 'apps/shop-ui/**' }
          steps { build job: 'shop/ci-shop-ui' }        // trigger the per-
        }                                               // service multibranch
        stage('shop-api') {                             // job instead of
          when { changeset 'apps/shop-api/**' }         // inlining it, so
          steps { build job: 'shop/ci-shop-api' }       // each keeps its own
        }                                               // history + agent
        stage('checkout') {
          when { changeset 'apps/checkout/**' }
          steps { build job: 'shop/ci-checkout' }
        }
        stage('order-worker') {
          when { changeset 'apps/order-worker/**' }
          steps { build job: 'shop/ci-order-worker' }
        }
        stage('payment-mock') {
          when { changeset 'apps/payment-mock/**' }
          steps { build job: 'shop/ci-payment-mock' }
        }
      }
    }
  }
}
```

#### 3.3.3 ⭐ Building images in Jenkins-on-Kubernetes: the three options

This is asked constantly, because the naive answer is a security hole.

| Option | How | Pros | Cons | Verdict |
|---|---|---|---|---|
| **Docker socket mount** | mount `/var/run/docker.sock` into the agent pod | trivially simple, full Docker feature set, layer cache is the node's | ⛔ **root on the node.** Any build step can create a privileged container and own the cluster | learning clusters only |
| **Docker-in-Docker (dind)** | a `docker:dind` sidecar, `DOCKER_HOST=tcp://localhost:2375` | isolated from the node | needs `privileged: true` (⛔ same problem, differently dressed); no layer cache unless you add one; slow | avoid |
| **Kaniko / BuildKit rootless** | `gcr.io/kaniko-project/executor` or `buildkitd --rootless` in a sidecar | ✅ **no privileges, no socket.** Works with a locked-down PodSecurityPolicy/Standards profile | no BuildKit parity (Kaniko); cache must be a registry or PVC; slower cold | ⭐ **the production answer** |

```groovy
// ✅ Kaniko in a Jenkins Kubernetes agent — no Docker, no privileges.
stage('Build image (kaniko)') {
  steps {
    container('kaniko') {                       // image: gcr.io/kaniko-
      // ⭐ Kaniko writes straight to the registry — it never talks to a
      //   Docker daemon, so there is nothing to mount and nothing to escape.
      sh """
        /kaniko/executor \\
          --context  dir://\$WORKSPACE/apps/shop-api \\
          --dockerfile Dockerfile \\
          --destination ${image}:\${TAG} \\
          --cache=true --cache-repo=${image}-cache \\
          --snapshot-mode=redo \\
          --reproducible \\
          --label org.opencontainers.image.revision=\$GIT_COMMIT
      """
    }
  }
}
// The kaniko container needs the registry credential as a Docker config:
//   secret `docker-config` mounted at /kaniko/.docker/config.json
// ⚠️ Kaniko + `--cache-repo` requires push access to that cache repo too.
```

### 3.4 ⭐ The three tools, same CI-only pipeline, side by side

| Concept | 🐙 GitHub Actions | 🔷 Azure DevOps | 🔨 Jenkins |
|---|---|---|---|
| File location | `.github/workflows/*.yml` | any path, referenced by the pipeline | `Jenkinsfile` (any path) |
| Language | YAML | YAML | Groovy (declarative) |
| Unit of parallelism | `job` (parallel by default) | `job` (parallel by default) | `parallel { stage … }` (explicit) |
| Ordering | `needs: [a, b]` | `dependsOn: [a, b]` | sequential stages / `dependsOn` in matrix |
| Path filter | `on.push.paths` / `dorny/paths-filter` | `trigger.paths` | `when { changeset '…' }` |
| Cancel superseded | `concurrency` + `cancel-in-progress` | `trigger.batch: true` (queues, doesn't cancel) | `disableConcurrentBuilds()` (queues) |
| Runner/agent | `runs-on: ubuntu-24.04` | `pool: { vmImage: 'ubuntu-24.04' }` | `agent { kubernetes { yaml … } }` |
| Reuse | reusable workflow (`workflow_call`) | `template:` | shared library (`vars/*.groovy`) |
| Matrix | `strategy.matrix` | `strategy.matrix` | `matrix { axes { … } }` |
| Dependency cache | `actions/cache`, `setup-*: cache:` | `Cache@2` task | a PVC, or `--cache-from` |
| Secret | `secrets.X` (env-scoped) | variable group / Key Vault | `credentials('id')` |
| No-secret auth | ⭐ OIDC (`id-token: write`) | ⭐ Workload Identity Federation | none — always a stored credential |
| Always-run step | `if: always()` | `condition: succeededOrFailed()` | `post { always { … } }` |
| Artifacts | `upload/download-artifact@v4` | `Publish/PublishBuildArtifacts@1` | `archiveArtifacts` |
| Test report | 3rd-party action / SARIF upload | ⭐ `PublishTestResults@2` (built in) | ⭐ `junit` step (built in) |
| Required gate | branch protection status check | ⭐ branch policy "build must succeed" | GitHub/GitLab status via plugin |
| **Where CI stops** | job `outputs.digest` | artifact `image-refs` | `archiveArtifacts digest.txt` |

### 3.5 ⛔ What Scenario 1 must NOT contain — the audit checklist

Run this against your own pipeline before calling it "CI only":

```bash
# ⭐ if ANY of these appear in a CI-only pipeline, it is not CI-only.
grep -rniE 'kubectl|helm |kustomize|kubeconfig|argocd|ssh |scp |ansible|deploy' \
     .github/workflows/ci-*.yml azure-pipelines.yml Jenkinsfile apps/*/Jenkinsfile

# ⭐ and check the SECRETS the pipeline can see. A CI pipeline that can
#   read a prod credential can deploy to prod, whether or not it does.
gh secret list ; gh variable list
az pipelines variable-group list --org <org> -p <proj> -o table
# Jenkins: Manage Jenkins → Credentials → check the SCOPE. Global credentials
# are visible to every job including forks' PRs. ⛔ Use folder-scoped.
```

| Check | Pass criterion |
|---|---|
| No `kubectl`/`helm`/`ssh` in any CI file | grep returns nothing |
| No cluster credential reachable from CI | the secret list contains no kubeconfig |
| Image is tagged by an **immutable** name | a `sha-…` or digest tag exists |
| Image is **signed** | `cosign verify` succeeds |
| Tests actually fail the build | introduce a deliberate failure once and confirm red |
| Test *results* publish even on failure | `if: always()` / `condition: succeededOrFailed()` / `post{always}` |
| Lint fails the build | `|| true` appears nowhere |
| Scan has `--exit-code 1` | Trivy/Snyk fails on CRITICAL |
| Base images pinned **by digest** | `FROM node:22@sha256:…` not `FROM node:22` |
| Cache scope is per-service | a Java change does not invalidate the npm cache |
| The build is **reproducible** | two runs of the same commit give the same digest (needs `--reproducible`, no `latest` base) |

⭐ **The "does it actually fail" test is the one everyone skips.** A pipeline that has never been seen red is a pipeline that is not testing anything. Deliberately break a test, watch it go red, then revert. Do this the first time you set up *every* pipeline you ever write.

### 3.6 The ephemeral "does it even run?" check (CI-safe, no cluster)

Sometimes you genuinely need to prove the image starts — without deploying anywhere.

```yaml
  smoke:
    name: Ephemeral smoke test (throwaway, torn down in-job)
    runs-on: ubuntu-24.04
    needs: image
    steps:
      # ⭐ a GitHub Actions `services:` container is created for THIS JOB
      #   and destroyed when the job ends. It is not a deployment.
      - name: Run the image and probe it
        run: |
          set -eu
          docker run -d --name smoke -p 18080:8080 \
            ghcr.io/3558bhk/shop-api@${{ needs.image.outputs.digest }}
          # ⭐ poll, don't sleep. `sleep 60` is a guess; a poll is a check.
          for i in $(seq 1 60); do
            if curl -fsS http://localhost:18080/actuator/health | grep -q '"UP"'; then
              echo "✅ up after ${i}s"; break
            fi
            [ "$i" = 60 ] && { echo "⛔ never became healthy"; docker logs smoke; exit 1; }
            sleep 1
          done
          curl -fsS http://localhost:18080/api/v1/products | head -c 200
        # ⭐ `if: always()` on the cleanup, or a failed smoke test leaks a
      - name: Teardown      #   container on the runner.
        if: always()
        run: docker rm -f smoke || true
```

---

## 4 · SCENARIO 2 — CD ONLY (starting from an artifact)

### 4.0 What "CD only" means

⭐⭐ **CD-only pipelines have no source code.** They start from something CI already produced. Their trigger is not a commit — it is one of:

| Trigger | Example | Used by |
|---|---|---|
| **A new image digest appears in the registry** | GHCR/ACR webhook → CD pipeline | push-style CD |
| **A build artifact is published** | Azure DevOps "release triggered by build completion" | classic ADO releases |
| **A file changes in the config repo** | `shop-config/environments/staging/images.yaml` | ⭐ **GitOps — the right answer** |
| **A human clicks "promote"** | `workflow_dispatch` / ADO Release / Jenkins `input` | Continuous Delivery |
| **A schedule** | nightly prod-parity soak | rarely, and only for non-prod |

```
   CI (Scenario 1, already done)                CD (Scenario 2, this file)
   ─────────────────────────────                ───────────────────────────
   commit ─▶ … ─▶ image@sha256:9f2c…  ═══════▶  read digest
                        │                        │
                        │ publish                ▼
                        ▼                    resolve manifest
                 digest.txt / artifact       (helm values, kustomize)
                                                 │
                                                 ▼
                                          dev ─▶ staging ─▶ [gate] ─▶ prod
                                                 │
                                                 ▼
                                          verify: rollout status,
                                          smoke test, metrics, SLO
                                                 │
                                          pass ──┴── fail ─▶ ROLLBACK (§7)
```

The five stages every CD pipeline has, in every tool:

| # | Stage | What it does | Failure mode if you skip it |
|---|---|---|---|
| 1 | **Resolve** | turn "the latest good build" into an exact digest | you deploy something you cannot identify later |
| 2 | **Render** | produce the manifests (Helm/Kustomize/plain) | you deploy untested YAML — the render is the test |
| 3 | **Verify signature & policy** | `cosign verify`, Kyverno/OPA admission | ⛔ anyone who can push to the registry can run code in prod |
| 4 | **Apply + wait** | `kubectl apply` / `helm upgrade --wait` / Argo sync | "apply succeeded" ≠ "the app is up". `--wait` is the difference |
| 5 | **Post-deploy verification** | smoke test + metrics/SLO check | you find out from users, not from the pipeline |

---

### 4.1 Case 1 — Continuous **DELIVERY** (a human decides production)

**Definition:** every change that passes CI is *automatically* deployed to dev and staging, and is *always releasable* to production — but the production release requires a **human approval**.

⭐ **The gate is not a formality.** For it to be a real control it needs: (a) a named, bounded set of approvers, (b) a timeout, (c) an audit record, (d) the ability to see *what* is being approved (the diff, the changelog, the test results) — not just a "Deploy" button.

#### 4.1.1 🐙 GitHub Actions — Continuous Delivery (FE + BE, all languages)

```yaml
# ══════════════════════════════════════════════════════════════════════
# .github/workflows/cd-delivery.yml
# ══════════════════════════════════════════════════════════════════════
# WHAT   : CD-only. Consumes a DIGEST. Promotes dev → staging → [human] → prod
# WHY    : Case 1 — Continuous Delivery. Prod needs an approval.
# TRIGGER: workflow_dispatch (human) OR the registry/config webhook.
#          ⭐ It is NOT triggered by `push`. That is what makes it CD-only.
# ══════════════════════════════════════════════════════════════════════

name: cd-delivery

on:
  workflow_dispatch:                 # ⭐ the human picks WHAT to promote
    inputs:
      service:
        description: 'Service to promote'
        required: true
        type: choice
        options: [shop-ui, shop-api, checkout, order-worker, payment-mock, all]
      digest:
        description: 'Image digest from CI (sha256:…). Leave blank for latest main.'
        required: false
        type: string
      target:
        description: 'Stop after this environment'
        required: true
        type: choice
        options: [dev, staging, production]
        default: staging
  repository_dispatch:               # ⭐ CI can trigger CD without CD
    types: [promote]                 #   watching commits — an explicit
                                     #   contract, not an implicit one.

permissions:
  contents: read                     # ⭐ CD needs to read the manifests repo.
  id-token: write                    # ⭐ OIDC for cluster/registry auth.

concurrency:
  group: cd-${{ inputs.service || 'all' }}-production
  cancel-in-progress: false          # ⛔ NEVER cancel a deploy mid-flight.
                                     #   Half-applied manifests are worse
                                     #   than a slow deploy.

env:
  REGISTRY: ghcr.io/3558bhk

jobs:
  # ── 1. RESOLVE: what exactly are we deploying? ─────────────────────────
  resolve:
    name: Resolve artifact
    runs-on: ubuntu-24.04
    outputs:
      digest: ${{ steps.resolve.outputs.digest }}
      matrix: ${{ steps.resolve.outputs.matrix }}
    steps:
      - uses: actions/checkout@v7
      - id: resolve
        run: |
          set -euo pipefail
          SVC="${{ inputs.service }}"
          if [ "$SVC" = "all" ]; then
            # ⭐ promote the whole release train: read the digests CI wrote.
            #    ONE artifact = ONE release. Never "latest of each" — that
            #    is an untested combination.
            cp release-train.json /tmp/train.json
            echo "matrix=$(jq -c '.services[].name' /tmp/train.json | jq -sc .)" >> "$GITHUB_OUTPUT"
            echo "digest=from-train" >> "$GITHUB_OUTPUT"
            jq . /tmp/train.json
          else
            D="${{ inputs.digest }}"
            if [ -z "$D" ]; then
              # ⭐ no digest given → ask the registry what `main` points at.
              #    Resolve the TAG to a DIGEST immediately. Everything
              #    downstream uses the digest, so a later re-push of `main`
              #    cannot change what this run deploys. ⭐⭐ This is the fix
              #    for "we deployed the wrong build and can't prove it".
              D=$(crane digest "${REGISTRY}/${SVC}:main")
            fi
            echo "digest=$D" >> "$GITHUB_OUTPUT"
            echo "matrix=[\"$SVC\"]" >> "$GITHUB_OUTPUT"
            echo "✅ resolved ${SVC} → $D"
          fi

  # ── 2. RENDER: produce manifests WITHOUT touching a cluster ────────────
  # ⭐⭐ Rendering separately from applying is the single highest-value
  #    practice in CD. `helm template` catches YAML/type errors in 2 seconds;
  #    `helm upgrade` catches them after it has already replaced your
  #    Deployment and left the namespace in a broken state.
  render:
    name: Render manifests
    needs: resolve
    runs-on: ubuntu-24.04
    strategy:
      fail-fast: false
      matrix:
        service: ${{ fromJson(needs.resolve.outputs.matrix) }}
        env: [dev, staging]
    steps:
      - uses: actions/checkout@v7
      - uses: azure/setup-helm@v4
        with: { version: 'v3.16.2' }        # ⭐ pin Helm. Chart behaviour
      - name: helm template + lint          #   changes between minors.
        run: |
          set -euo pipefail
          helm lint deploy/chart \
            --values deploy/values/${{ matrix.env }}.yaml \
            --set image.repository=${REGISTRY}/${{ matrix.service }} \
            --set image.digest=${{ needs.resolve.outputs.digest }}
          helm template ${{ matrix.service }} deploy/chart \
            --namespace shop-${{ matrix.env }} \
            --values deploy/values/${{ matrix.env }}.yaml \
            --set image.repository=${REGISTRY}/${{ matrix.service }} \
            --set image.digest=${{ needs.resolve.outputs.digest }} \
            > rendered-${{ matrix.service }}-${{ matrix.env }}.yaml
          echo "── rendered ──"; head -40 rendered-*.yaml
      # ⭐⭐ POLICY CHECK THE RENDERED YAML, before it can touch anything.
      #    kubeconform = "is it valid K8s schema?"
      #    kubeval/conftest/OPA = "does it violate OUR rules?"
      - name: Schema + policy validation
        run: |
          curl -sL https://github.com/yannh/kubeconform/releases/download/v0.6.7/kubeconform-linux-amd64.tar.gz | tar xz
          ./kubeconform -strict -summary -kubernetes-version 1.31.0 rendered-*.yaml
          # ⭐ `-strict` rejects unknown fields. Without it, a typo'd
          #   `replicaCount` is silently ignored and you deploy 1 replica
          #   instead of 3 — with a green pipeline.
      - uses: actions/upload-artifact@v4
        with:
          name: rendered-${{ matrix.service }}-${{ matrix.env }}
          path: rendered-*.yaml

  # ── 3. DEPLOY TO DEV (automatic) ───────────────────────────────────────
  deploy-dev:
    name: Deploy → dev
    needs: [resolve, render]
    runs-on: ubuntu-24.04
    environment:                        # ⭐ `environment:` is not decoration.
      name: dev                          #   It scopes secrets, records history
      url: https://dev.shop.example/     #   and enables the approval gate.
    strategy:
      fail-fast: false
      matrix:
        service: ${{ fromJson(needs.resolve.outputs.matrix) }}
    steps:
      - uses: actions/checkout@v7
      # ⭐⭐ OIDC → short-lived cluster credential. No kubeconfig secret
      #   stored in GitHub, nothing to rotate, nothing to leak.
      - uses: azure/k8s-set-context@v4
        with:
          method: kubeconfig
          kubeconfig: ${{ secrets.KUBECONFIG_DEV }}    # (or use a cloud
      #   For EKS/AKS/GKE the OIDC version is:                           #
      #   aws-actions/configure-aws-credentials@v4 with role-to-assume   #
      #   then `aws eks update-kubeconfig`. ⭐ prefer that.              #
      # ⭐⭐ THREE FLAGS THAT SEPARATE A DEPLOY FROM AN ATTEMPT:
      #   --atomic   if the release never becomes Ready, roll it back
      #              automatically. Without it a failed upgrade leaves the
      #              namespace half-migrated and the pipeline still exits 0.
      #   --wait     block until every resource reports Ready. Without it,
      #              helm returns the instant the API *accepts* the object,
      #              so the pipeline says "deployed" while the pod is
      #              CrashLoopBackOff.
      #   --timeout  how long --atomic/--wait will wait before giving up.
      # ⚠️ bash gotcha: a `\` continuation must be the LAST character on the
      #   line. `--atomic \   # comment` escapes the SPACE, not the newline,
      #   so the command ends there. Put comments on their own lines.
      - name: Deploy
        run: |
          set -euo pipefail
          helm upgrade --install ${{ matrix.service }} deploy/chart \
            --namespace shop-dev \
            --values deploy/values/dev.yaml \
            --set image.repository=${REGISTRY}/${{ matrix.service }} \
            --set image.digest=${{ needs.resolve.outputs.digest }} \
            --atomic \
            --timeout 5m \
            --wait
      - name: Verify rollout
        run: |
          kubectl -n shop-dev rollout status deploy/${{ matrix.service }} --timeout=300s
          kubectl -n shop-dev get pods -l app=${{ matrix.service }} -o wide
      - name: Smoke test
        run: ./scripts/smoke.sh shop-dev ${{ matrix.service }}
        # ⭐ the smoke test hits /health, /ready and ONE real business
        #   endpoint. It is not the full e2e suite — that ran in CI.

  # ── 4. DEPLOY TO STAGING (automatic) ───────────────────────────────────
  deploy-staging:
    name: Deploy → staging
    needs: [resolve, deploy-dev]
    runs-on: ubuntu-24.04
    environment: { name: staging, url: https://staging.shop.example/ }
    strategy:
      fail-fast: false
      matrix:
        service: ${{ fromJson(needs.resolve.outputs.matrix) }}
    steps:
      - uses: actions/checkout@v7
      - uses: azure/k8s-set-context@v4
        with: { method: kubeconfig, kubeconfig: '${{ secrets.KUBECONFIG_STAGING }}' }
      - run: |
          set -euo pipefail
          helm upgrade --install ${{ matrix.service }} deploy/chart \
            --namespace shop-staging \
            --values deploy/values/staging.yaml \
            --set image.repository=${REGISTRY}/${{ matrix.service }} \
            --set image.digest=${{ needs.resolve.outputs.digest }} \
            --atomic --timeout 5m --wait
      # ⭐⭐ STAGING IS WHERE YOU RUN THE SLOW TESTS. CI ran fast tests;
      #   staging has real dependencies (postgres, redis, rabbitmq) and
      #   real-ish data. This is the gate that makes prod approval safe.
      - name: Full e2e against staging
        run: ./scripts/e2e.sh https://staging.shop.example
      - name: Contract test (FE ↔ BE version skew)
        run: ./scripts/contract-test.sh staging
        # ⭐⭐⭐ for shape C (FE+BE) this is mandatory: it proves the
        #   frontend you are about to ship can talk to the backend already
        #   in prod. See §4.1.4.

  # ── 5. 🚪 THE GATE ─────────────────────────────────────────────────────
  # ⭐⭐⭐ THIS IS WHAT MAKES IT "CONTINUOUS DELIVERY" AND NOT
  #    "CONTINUOUS DEPLOYMENT". In GitHub Actions the gate is implicit:
  #    an `environment:` with required reviewers PAUSES the job until a
  #    human approves. There is no `approve` step to write — you configure
  #    it in Settings → Environments → production → Required reviewers.
  deploy-production:
    name: Deploy → production (APPROVAL REQUIRED)
    needs: [resolve, deploy-staging]
    runs-on: ubuntu-24.04
    environment:                          # ⭐ the gate lives in these
      name: production                    #   three lines + repo settings.
      url: https://shop.example/
    # ⭐⭐ only run this job if the operator asked for production, or if
    #   the release train is being promoted all the way.
    if: ${{ inputs.target == 'production' || inputs.target == '' }}
    strategy:
      fail-fast: false
      matrix:
        service: ${{ fromJson(needs.resolve.outputs.matrix) }}
    steps:
      - uses: actions/checkout@v7
      # ⭐ the prod credential is an ENVIRONMENT secret: it is only
      #   materialised for a job that names `environment: production`,
      #   and only AFTER the approval. A CI job literally cannot read it.
      - uses: azure/k8s-set-context@v4
        with: { method: kubeconfig, kubeconfig: '${{ secrets.KUBECONFIG_PROD }}' }

      - name: Pre-flight — is the cluster healthy right now?
        run: |
          set -euo pipefail
          # ⭐⭐ never deploy into a cluster that is already broken. Check
          #   FIRST, or you will be debugging your deploy during someone
          #   else's incident.
          kubectl get nodes -o wide | tee /dev/stderr | grep -q ' Ready'
          NOTREADY=$(kubectl get pods -n shop-production --field-selector=status.phase!=Running \
                     --no-headers 2>/dev/null | grep -vc 'Completed' || true)
          echo "non-running pods in prod: $NOTREADY"
          # ⭐ an error-budget check: if we've already burned the budget
          #   this month, deploying more risk is the wrong call.
          ./scripts/error-budget-check.sh || {
            echo "⛔ error budget exhausted — promote manually via break-glass";
            exit 1; }

      - name: Deploy
        run: |
          set -euo pipefail
          helm upgrade --install ${{ matrix.service }} deploy/chart \
            --namespace shop-production \
            --values deploy/values/production.yaml \
            --set image.repository=${REGISTRY}/${{ matrix.service }} \
            --set image.digest=${{ needs.resolve.outputs.digest }} \
            --atomic --timeout 10m --wait

      - name: Verify rollout
        run: |
          kubectl -n shop-production rollout status deploy/${{ matrix.service }} --timeout=600s
          kubectl -n shop-production get pods -l app=${{ matrix.service }}

      - name: Post-deploy smoke + metrics
        run: |
          ./scripts/smoke.sh shop-production ${{ matrix.service }}
          # ⭐⭐ watch the golden signals for 5 minutes after the deploy.
          #   In Case 1 (Delivery) a human is watching too; in Case 2
          #   (Deployment) THIS is the watcher.
          ./scripts/watch-metrics.sh shop-production ${{ matrix.service }} 300

      - name: Record the deployment
        if: always()
        run: |
          # ⭐⭐⭐ write an audit line: who, what digest, when, which env.
          #   `helm history` gives you the release; THIS gives you the git
          #   commit and the approver. You will need it during an incident.
          echo "$(date -u +%FT%TZ) prod ${{ matrix.service }} \
                ${{ needs.resolve.outputs.digest }} \
                run=${{ github.run_id }} actor=${{ github.actor }}" \
            >> deploy-audit.log
```

**How the approval gate is configured (GitHub Actions):**

```text
Repo → Settings → Environments → New environment: "production"
  ├─ Required reviewers      → add 2+ people  ⭐ (one reviewer who is also
  │                                          the author is not a control)
  ├─ Wait timer              → 0 (or 5 min for a "cooling off" period)
  ├─ Deployment branches     → restrict to `main` only
  ├─ Environment secrets     → KUBECONFIG_PROD  ⭐ scoped to this env
  └─ ⭐ "Prevent self-review" → ON (GitHub Enterprise)
```

#### 4.1.2 🔷 Azure DevOps — Continuous Delivery (Environments + Approvals)

⭐ Azure DevOps has the richest approval model of the three — **checks** are first-class objects, not just a reviewer list.

```yaml
# cd-delivery-azure.yml — CD only, no build stages
trigger: none                  # ⭐⭐ `trigger: none` = this pipeline is NOT
                               #   triggered by source changes. That single
                               #   line is what makes it CD-only in ADO.
pr: none

pool: { vmImage: 'ubuntu-24.04' }

variables:
  - group: shop-cd                       # non-secret CD config
  - name: ACR
    value: shopacr.azurecr.io

# ⭐⭐⭐ AZURE'S KILLER FEATURE: an explicit approval/check step INSIDE the
#   YAML, in addition to Environment-level approvals configured in the UI.
#   `ManualValidation@1` pauses the stage and notifies people.
stages:
  - stage: resolve
    displayName: '1 · Resolve artifact'
    jobs:
      - job: resolve
        steps:
          - task: DownloadBuildArtifacts@1
            displayName: 'Download the image refs CI published'
            inputs:
              project: '$(System.TeamProject)'
              pipeline: 'shop-ci'                 # ⭐ the CI pipeline
              # ⭐⭐ `latestFromBranch` = "the newest successful build of main".
              #   For a real release train, pin `buildVersionToDownload` to a
              #   specific build ID so a re-run deploys the SAME thing.
              buildVersionToDownload: 'latestFromBranch'
              branchName: 'refs/heads/main'
              itemPattern: 'image-refs/**'
              downloadPath: '$(Pipeline.Workspace)'
          - script: |
              set -euo pipefail
              cat $(Pipeline.Workspace)/image-refs/digest.txt
              # ⭐ resolve tag → digest so the deploy is immutable
              DIGEST=$(az acr repository show \
                --name shopacr --repository shop-api --query 'digest' -o tsv)
              echo "##vso[task.setvariable variable=API_DIGEST;isOutput=true]$DIGEST"
              # ⭐⭐ `##vso[...isOutput=true]` is how a job passes a value to
              #   a later stage. Without isOutput it dies with the job.
            name: dig
            displayName: 'Resolve digests'

  - stage: dev
    displayName: '2 · Deploy → dev'
    dependsOn: resolve
    variables:
      API_DIGEST: $[ stageDependencies.resolve.resolve.outputs['dig.API_DIGEST'] ]
    jobs:
      - deployment: dev_deploy            # ⭐⭐ a `deployment` job, not a
        displayName: 'Deploy shop-api'    #   `job`. Deployment jobs know
        environment:                      #   about environments, strategies
          name: shop-dev                  #   (runOnce/rolling/canary) and
          resourceName: shop-api          #   record deployment history.
        strategy:
          runOnce:                        # ⭐ for K8s, runOnce is right.
            deploy:                       #   `rolling`/`canary` are for
              steps:                      #   VM scale sets.
                - task: HelmDeploy@0
                  inputs:
                    command: upgrade
                    chartType: filepath
                    chartPath: deploy/chart
                    releaseName: shop-api
                    namespace: shop-dev
                    valueFile: deploy/values/dev.yaml
                    # ⭐⭐ `--atomic --wait` are what make a deploy VERIFIED
                    #   rather than merely ATTEMPTED.
                    arguments: >
                      --atomic --timeout 5m --wait
                      --set image.repository=$(ACR)/shop-api
                      --set image.digest=$(API_DIGEST)
                - script: kubectl -n shop-dev rollout status deploy/shop-api --timeout=300s
                - script: ./scripts/smoke.sh shop-dev shop-api

  - stage: staging
    displayName: '3 · Deploy → staging'
    dependsOn: dev
    jobs:
      - deployment: staging_deploy
        environment: { name: shop-staging, resourceName: shop-api }
        strategy:
          runOnce:
            deploy:
              steps:
                - task: HelmDeploy@0
                  inputs:
                    command: upgrade
                    chartType: filepath
                    chartPath: deploy/chart
                    releaseName: shop-api
                    namespace: shop-staging
                    valueFile: deploy/values/staging.yaml
                    arguments: >
                      --atomic --timeout 5m --wait
                      --set image.digest=$(API_DIGEST)
                - script: ./scripts/e2e.sh https://staging.shop.example

  # ══ THE GATE ══════════════════════════════════════════════════════════
  # ⭐⭐⭐ TWO ways to gate in Azure, and you should know both:
  #   (a) Environment → Approvals and checks (UI) — richer: approvals,
  #       branches, business hours, REST checks, agent-version checks.
  #   (b) ManualValidation@1 task in YAML — visible in code, reviewable.
  - stage: approval
    displayName: '4 · 🚪 Human approval for PRODUCTION'
    dependsOn: staging
    pool: server                        # ⭐⭐ an agentless "server" job. It
    jobs:                               #   consumes NO agent minutes while
      - job: approve                    #   it waits — which can be days.
        displayName: 'Wait for release approval'
        timeoutInMinutes: 4320          # ⭐ 3 days. Default is 60 min, and
        steps:                          #   a gate that expires overnight is
          - task: ManualValidation@1    #   a gate nobody can use.
            inputs:
              notifyUsers: |
                release-managers@example.com
                sre-oncall@example.com
              instructions: |
                Review before approving:
                  • digest  : $(API_DIGEST)
                  • staging e2e: $(System.TeamFoundationCollectionUri)…
                  • changelog: compare to the last approved prod release
                ⛔ Do not approve during a freeze window or an open SEV.
              onTimeout: reject         # ⭐ explicit: timeout = NO deploy.
                                        #   The default `reject` is right;
                                        #   never set it to `resume`.

  - stage: production
    displayName: '5 · Deploy → production'
    dependsOn: approval
    # ⭐⭐ belt and braces: require the approval stage AND the environment
    #   check. One can be misconfigured; two failing at once is unlikely.
    jobs:
      - deployment: prod_deploy
        environment:
          name: shop-production            # ⭐ has "Approvals and checks"
          resourceName: shop-api           #   configured in the UI too
        strategy:
          runOnce:
            preDeploy:                     # ⭐ runs BEFORE the deploy steps
              steps:                       #   — perfect for the pre-flight.
                - script: |
                    set -euo pipefail
                    kubectl get nodes | grep -q ' Ready'
                    ./scripts/error-budget-check.sh
                    ./scripts/freeze-window-check.sh   # ⭐ no deploys on
                    echo "✅ pre-flight OK"            #   Fridays or in a
            deploy:                        #   freeze. Say it in code.
              steps:
                - task: HelmDeploy@0
                  inputs:
                    command: upgrade
                    chartType: filepath
                    chartPath: deploy/chart
                    releaseName: shop-api
                    namespace: shop-production
                    valueFile: deploy/values/production.yaml
                    arguments: >
                      --atomic --timeout 10m --wait
                      --set image.digest=$(API_DIGEST)
                - script: kubectl -n shop-production rollout status deploy/shop-api --timeout=600s
                - script: ./scripts/smoke.sh shop-production shop-api
                - script: ./scripts/watch-metrics.sh shop-production shop-api 300
            routeTraffic: {}               # (used by canary strategies)
            postRouteTraffic: {}
            on:
              failure:                     # ⭐⭐ automatic rollback wired
                steps:                     #   into the deployment job.
                  - script: |
                      echo "⛔ deploy failed — rolling back"
                      helm rollback shop-api -n shop-production --wait
                      ./scripts/smoke.sh shop-production shop-api
```

**The Azure Environment check catalogue** (Project → Environments → *env* → Approvals and checks):

| Check | What it enforces | ⭐ Why it matters |
|---|---|---|
| **Approvals** | N named users must approve | the actual Delivery gate |
| **Business hours** | deploys only 10:00–16:00 local | nobody deploys into an empty office |
| **Days of the week** | not Saturday/Sunday | same |
| **Branch control** | only `main`/`release/*` may deploy | ⛔ stops a feature branch reaching prod |
| **Required templates** | a governance YAML must pass | org-wide policy, enforced centrally |
| **REST check** | call an API and require a result | ⭐ change-management integration (ServiceNow), freeze windows, on-call checks |
| **Query work items** | a linked, resolved bug/task must exist | ties every prod change to a tracked reason |
| **Agent version** | minimum agent version | stops deploys from an unpatched agent |

#### 4.1.3 🔨 Jenkins — Continuous Delivery (`input` step)

```groovy
// ══════════════════════════════════════════════════════════════════════
// Jenkinsfile.cd-delivery  — CD only, Continuous DELIVERY
// ══════════════════════════════════════════════════════════════════════
// WHAT   : consume a digest CI produced; promote dev → staging → prod,
//          with a human gate before prod.
// WHY    : Case 1. Jenkins' gate is the `input` step — it PAUSES the
//          pipeline and holds an executor until someone answers.
// ⚠️⚠️   THE BIG JENKINS TRAP: a paused `input` step occupies an EXECUTOR
//          for as long as it waits. Twenty pending approvals can exhaust
//          the controller. Mitigations: `timeout` on the input, a dedicated
//          "gate" agent with many executors, or Milestone/Lockable plugins.
// ══════════════════════════════════════════════════════════════════════

pipeline {
  agent { label 'cd' }              // ⭐ a small, dedicated agent for CD.
                                    //   CD steps are mostly network waits —
                                    //   they don't need 4 CPU.

  options {
    timestamps()
    timeout(time: 3, unit: 'DAYS')  // ⭐ the whole pipeline, including the
    disableConcurrentBuilds()       //   gate, may wait 3 days.
    buildDiscarder(logRotator(numToKeepStr: '50'))
  }

  parameters {                       // ⭐ parameters make this human-drivable
    choice(name: 'SERVICE',
           choices: ['shop-api', 'shop-ui', 'checkout', 'order-worker', 'payment-mock', 'all'],
           description: 'What to promote')
    string(name: 'DIGEST', defaultValue: '',
           description: 'sha256:… from CI. Blank = resolve latest main.')
    choice(name: 'TARGET', choices: ['dev', 'staging', 'production'],
           description: 'Stop after this environment')
    booleanParam(name: 'SKIP_E2E', defaultValue: false,
                 description: '⛔ break-glass only. Requires a reason below.')
    string(name: 'SKIP_REASON', defaultValue: '',
                 description: 'Why are you skipping e2e? (audited)')
  }

  environment {
    HELM = "${tool 'helm-3.16.2'}"     // ⭐ `tool` = a Jenkins Global Tool
                                       //   Configuration entry. Version is
                                       //   managed centrally, not per-job.
    K8S_CRED = 'kubeconfig-prod'       // credential ID, resolved lazily
  }

  stages {
    // ── 1. RESOLVE ──────────────────────────────────────────────────────
    stage('Resolve digest') {
      steps {
        script {
          def svc = params.SERVICE
          def d   = params.DIGEST?.trim()
          if (!d) {
            // ⭐ resolve the tag to a digest NOW. Everything downstream uses
            //   the digest, so a re-push cannot change what we deploy.
            d = sh(returnStdout: true,
                   script: "crane digest ghcr.io/3558bhk/${svc}:main").trim()
          }
          env.DEPLOY_DIGEST = d
          echo "✅ ${svc} → ${d}"
          // ⭐⭐ record it in the build description so the Jenkins UI itself
          //   tells you what each build deployed. Cheap, hugely useful.
          currentBuild.description = "${svc} ${d.take(19)}…"
        }
      }
    }

    // ── 2. RENDER + VALIDATE (no cluster access yet) ────────────────────
    stage('Render & validate') {
      steps {
        sh '''
          set -euo pipefail
          helm lint deploy/chart --values deploy/values/staging.yaml
          helm template "$SERVICE" deploy/chart \
            --namespace shop-staging \
            --values deploy/values/staging.yaml \
            --set image.repository=ghcr.io/3558bhk/$SERVICE \
            --set image.digest=$DEPLOY_DIGEST > rendered.yaml
          kubeconform -strict -summary rendered.yaml
          echo "── first 40 lines ──"; head -40 rendered.yaml
        '''
      }
    }

    // ── 3. VERIFY THE SIGNATURE ⭐⭐⭐ ───────────────────────────────────
    stage('Verify signature') {
      steps {
        // ⭐⭐⭐ If you do this ONE thing, do this. Without signature
        //   verification, anyone with push access to your registry can run
        //   arbitrary code in production. That is not a hypothetical — it is
        //   how most real supply-chain incidents start.
        sh '''
          set -euo pipefail
          cosign verify \
            "ghcr.io/3558bhk/${SERVICE}@${DEPLOY_DIGEST}" \
            --certificate-identity-regexp="https://github.com/3558Bhk/.*/.github/workflows/ci-.*@refs/heads/main" \
            --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
            | jq -r '.[0].critical.identity."docker-reference"'
          echo "✅ signature verified"
        '''
      }
    }

    // ── 4. DEV ──────────────────────────────────────────────────────────
    stage('Deploy → dev') {
      steps {
        // ⭐⭐ withKubeConfig injects a kubeconfig for the block ONLY, and
        //   scrubs it from the environment afterwards. Never `cp` a
        //   kubeconfig into the workspace — workspaces persist and get
        //   archived into artifacts.
        withKubeConfig([credentialsId: 'kubeconfig-dev', contextName: 'kind-cicd']) {
          sh '''
            set -euo pipefail
            helm upgrade --install "$SERVICE" deploy/chart \
              --namespace shop-dev --values deploy/values/dev.yaml \
              --set image.repository=ghcr.io/3558bhk/$SERVICE \
              --set image.digest=$DEPLOY_DIGEST \
              --atomic --timeout 5m --wait
            kubectl -n shop-dev rollout status deploy/$SERVICE --timeout=300s
            ./scripts/smoke.sh shop-dev "$SERVICE"
          '''
        }
      }
    }

    // ── 5. STAGING ──────────────────────────────────────────────────────
    stage('Deploy → staging') {
      steps {
        withKubeConfig([credentialsId: 'kubeconfig-staging', contextName: 'kind-cicd']) {
          sh '''
            set -euo pipefail
            helm upgrade --install "$SERVICE" deploy/chart \
              --namespace shop-staging --values deploy/values/staging.yaml \
              --set image.digest=$DEPLOY_DIGEST --atomic --timeout 5m --wait
          '''
        }
      }
    }
    stage('E2E on staging') {
      when {
        expression { params.TARGET == 'production' }
        not { expression { params.SKIP_E2E } }
      }
      steps { sh './scripts/e2e.sh https://staging.shop.example' }
    }

    // ══ 6. 🚪 THE GATE — Jenkins `input` ════════════════════════════════
    stage('Approval for production') {
      when { expression { params.TARGET == 'production' } }
      steps {
        // ⭐⭐⭐ THE MOST IMPORTANT 25 LINES IN THIS FILE.
        timeout(time: 24, unit: 'HOURS') {        // ⭐ without a timeout this
          script {                                 //   executor is held forever
            def approver = input(
              id: 'prod-approval',
              message: '🚪 Approve PRODUCTION deploy?',
              ok: 'Approve & deploy',
              submitter: 'release-managers,sre-oncall',  // ⭐ a GROUP, not
              submitterParameter: 'APPROVED_BY',         //   individuals.
              // ⭐⭐ `submitterParameter` captures WHO approved into a
              //   variable. Without it you have a gate with no audit trail —
              //   Jenkins knows, but your incident review won't.
              parameters: [
                string(name: 'TICKET',  defaultValue: '',
                       description: 'Change ticket (required)'),
                choice(name: 'STRATEGY', choices: ['canary', 'blue-green', 'rolling'],
                       description: 'Prod rollout strategy'),
                booleanParam(name: 'CONFIRM_FREEZE_CHECKED', defaultValue: false,
                       description: 'I checked the freeze calendar')
              ]
            )
            // ⭐ validate the approval itself. A gate that accepts a blank
            //   ticket number is a gate in name only.
            if (!approver.TICKET?.trim()) {
              error("⛔ approval rejected: TICKET is mandatory")
            }
            if (!approver.CONFIRM_FREEZE_CHECKED) {
              error("⛔ approval rejected: freeze calendar not confirmed")
            }
            if (approver.APPROVED_BY == currentBuild.getBuildCauses('UserIdCause')?.userId) {
              // ⭐⭐ no self-approval. The person who started the run cannot
              //   also be the person who approves it.
              error("⛔ approval rejected: self-approval is not permitted")
            }
            env.APPROVED_BY = approver.APPROVED_BY
            env.TICKET      = approver.TICKET
            env.STRATEGY    = approver.STRATEGY
            echo "✅ approved by ${env.APPROVED_BY} under ${env.TICKET}"
          }
        }
      }
    }

    // ── 7. PRODUCTION ───────────────────────────────────────────────────
    stage('Deploy → production') {
      when { expression { params.TARGET == 'production' } }
      steps {
        withKubeConfig([credentialsId: 'kubeconfig-prod', contextName: 'kind-cicd']) {
          sh '''
            set -euo pipefail
            # ⭐ pre-flight: never deploy into an already-broken cluster
            kubectl get nodes | grep -q ' Ready'
            ./scripts/error-budget-check.sh

            case "$STRATEGY" in
              rolling)
                helm upgrade --install "$SERVICE" deploy/chart \\
                  --namespace shop-production --values deploy/values/production.yaml \\
                  --set image.digest=$DEPLOY_DIGEST --atomic --timeout 10m --wait ;;
              canary)
                # ⭐ Argo Rollouts: create/patch a Rollout, let IT do the
                #   progressive steps and the analysis. See §6.5.
                kubectl argo rollouts set image "$SERVICE" \\
                  "$SERVICE=ghcr.io/3558bhk/$SERVICE@$DEPLOY_DIGEST" -n shop-production ;;
              blue-green)
                kubectl argo rollouts promote "$SERVICE" -n shop-production ;;
            esac

            kubectl -n shop-production rollout status deploy/$SERVICE --timeout=600s || true
            ./scripts/smoke.sh shop-production "$SERVICE"
            ./scripts/watch-metrics.sh shop-production "$SERVICE" 300
          '''
        }
      }
      post {
        success {
          // ⭐⭐⭐ THE AUDIT LINE. Who deployed what, when, under which ticket.
          sh '''echo "$(date -u +%FT%TZ) prod $SERVICE $DEPLOY_DIGEST
                       approver=$APPROVED_BY ticket=$TICKET
                       build=$BUILD_URL" >> deploy-audit.log'''
          archiveArtifacts 'deploy-audit.log'
        }
        failure {
          // ⭐ automatic rollback on failure — §7 has the full drill.
          withKubeConfig([credentialsId: 'kubeconfig-prod', contextName: 'kind-cicd']) {
            sh 'helm rollback "$SERVICE" -n shop-production --wait || true'
          }
          // ⭐⭐ notify. A failed prod deploy that nobody knows about is
          //   worse than no deploy at all.
          slackSend(channel: '#shop-oncall', color: 'danger',
            message: "⛔ PROD deploy FAILED for ${params.SERVICE} — rolled back. ${env.BUILD_URL}")
        }
      }
    }
  }

  post {
    always {
      // ⭐ scrub. If any step leaked a kubeconfig into the workspace, remove it.
      sh 'rm -f $WORKSPACE/.kube/config $WORKSPACE/kubeconfig* 2>/dev/null || true'
      // ⭐ record the result as a commit status so the PR page shows it.
      script {
        currentBuild.result = currentBuild.currentResult
      }
    }
  }
}
```

#### 4.1.4 ⭐⭐⭐ Shape C — FE + BE together: the version-skew problem

This is the hardest part of deploying a frontend and a backend as one release, and it is a favourite staff-level interview question.

**The problem.** During a rolling update, for a period of time **both versions are serving traffic at once**. Worse: browsers cache the frontend. A user who loaded `index.html` ten minutes ago is running the *old* JS bundle against the *new* API.

```
      t=0                t=30s                t=60s              t=10min
   ┌────────┐        ┌────────┐         ┌────────┐          ┌────────┐
   │ BE v1  │        │ BE v1  │         │ BE v2  │          │ BE v2  │
   │ BE v1  │        │ BE v2  │         │ BE v2  │          │ BE v2  │
   └────────┘        └────────┘         └────────┘          └────────┘
        ▲                 ▲                                    ▲
   FE v1 users      FE v1 AND FE v2                      ⛔ FE v1 users
   (fine)           BOTH in flight —                     from a CACHED
                    this is the danger window            index.html (v1 JS)
                                                         hitting BE v2
```

**The four defences, in order of importance:**

| # | Defence | How | Why |
|---|---|---|---|
| 1 | ⭐⭐⭐ **Backwards-compatible API changes only** | Add fields; never remove or rename. Deprecate → wait one release → remove | This is the only real fix. Everything else is mitigation |
| 2 | **Expand / contract (parallel change)** | v2 reads both old and new columns/fields; write both; migrate; then remove the old | Makes an irreversible change into two reversible ones |
| 3 | **Cache-control on `index.html`** | `no-cache` for HTML, long-lived immutable cache for hashed assets | Guarantees the browser revalidates the entry point, so it can never be *stuck* on old JS |
| 4 | **Runtime version check** | FE calls `/api/v1/meta/version`; on mismatch, prompt a reload | Catches the tail of long-lived tabs |

```nginx
# apps/shop-ui/nginx.conf  ⭐ the FE deployment correctness lives HERE
server {
  listen 80;
  root /usr/share/nginx/html;

  # ⭐⭐⭐ index.html must NEVER be cached. It is the entry point that
  #   references the hashed bundles. If it is cached, users keep loading
  #   bundles you deleted in the previous deploy → white screen of death.
  location = /index.html {
    add_header Cache-Control "no-store, no-cache, must-revalidate, max-age=0";
    add_header Pragma "no-cache";
    expires -1;
    etag off;                       # ⭐ no ETag: we want a full refetch
  }

  # ⭐ hashed assets are content-addressed, so they can be cached FOREVER.
  #   Vite emits `assets/app-3f2a1b9c.js` — the hash changes when the
  #   content changes, so a stale file is impossible.
  location /assets/ {
    add_header Cache-Control "public, max-age=31536000, immutable";
  }

  # ⭐ keep the OLD bundles around for one release. If you delete them and
  #   a cached index.html references them, users get 404s on JS.
  #   Practical fix: deploy the new image WITHOUT deleting old assets
  #   (multi-stage copy of both), or accept the reload prompt in defence #4.

  location /api/ {
    proxy_pass http://shop-api.shop-production.svc.cluster.local:8080/;
    proxy_set_header Host $host;
    proxy_set_header X-Request-ID $request_id;   # ⭐ correlate FE→BE logs
  }

  location /health { return 200 'ok'; }          # ⭐ liveness: nginx is up
  location /ready  { return 200 'ready'; }       # ⭐ readiness
}
```

```yaml
# The CD job that enforces compatibility — add this to deploy-staging:
  - name: Contract test (FE ↔ BE)
    run: |
      set -euo pipefail
      # ⭐⭐⭐ Pact-style consumer-driven contract test. The FE is the
      #   consumer; it publishes what it NEEDS. The BE verifies it still
      #   provides it. This is the only automated way to catch a breaking
      #   API change before production.
      # 1. the consumer contract, generated from the FE's API client types
      npx pact-consumer --out pacts/
      # 2. verify it against the BACKEND CURRENTLY IN PROD (not the new one)
      pact-provider-verify \
        --provider shop-api \
        --provider-base-url https://shop.example \
        --publish-verification-results \
        pacts/*.json
      # ⭐ if this fails, the new FE cannot talk to the CURRENT prod BE.
      #   You must deploy the BE first, or make the change compatible.
```

⭐⭐ **Deploy ORDER matters for shape C:**

| Change | Correct order | Why |
|---|---|---|
| BE adds a field, FE reads it | **BE first**, then FE | the FE would read `undefined` from the old BE |
| BE removes a field, FE stops reading it | **FE first**, then BE | the old FE would break against the new BE |
| Both change together | make it two releases | ⛔ a single atomic FE+BE deploy does not exist — browsers are not atomic |
| Breaking change unavoidable | version the endpoint (`/api/v2/…`), run both | the only safe way |

---

### 4.2 Case 2 — Continuous **DEPLOYMENT** (the machine decides production)

**Definition:** every change that passes CI reaches production **automatically**. There is no human gate. In its place there must be **evidence**: automated verification at every step, progressive rollout, and automatic abort.

⭐⭐⭐ **The rule:** *you may remove the human gate only when you can replace everything the human was checking with a machine check.* Make the list explicit before you automate:

| What the human was checking | The machine replacement |
|---|---|
| "does this look sane?" | automated smoke tests + contract tests |
| "are we in a freeze?" | a freeze-calendar API check that fails the pipeline |
| "is prod healthy right now?" | pre-deploy SLO/error-budget gate |
| "did it work?" | post-deploy canary **analysis** against Prometheus (error rate, p99 latency, saturation) |
| "should we roll back?" | automatic rollback on analysis failure, with no human able to delay it |
| "how much risk am I taking?" | **change budget**: N auto-deploys/day; beyond that, require a human |
| "who do I tell?" | automated notification on every prod deploy + on every auto-rollback |

#### 4.2.1 🐙 GitHub Actions — Continuous Deployment with canary + auto-rollback

```yaml
# .github/workflows/cd-deployment.yml
# ══════════════════════════════════════════════════════════════════════
# WHAT   : CD-only, CONTINUOUS DEPLOYMENT. No human gate anywhere.
# WHY    : Case 2. The gate is replaced by Argo Rollouts canary analysis
#          and an automatic abort.
# SAFETY : this pipeline may ONLY be enabled once §4.2.0 is all green.
# ══════════════════════════════════════════════════════════════════════

name: cd-deployment

on:
  # ⭐⭐ the trigger is the REGISTRY, not the repo. A new digest on `main`
  #   means CI already passed. CD does not re-check the code — it cannot,
  #   it has no source. It trusts the signature instead.
  registry_package:
    types: [published, updated]
  workflow_dispatch:
    inputs:
      service: { required: true, type: string }
      digest:  { required: true, type: string }

permissions:
  contents: read
  id-token: write
  packages: read

concurrency:
  group: cd-auto-${{ github.event.registry_package.name || inputs.service }}
  cancel-in-progress: false        # ⛔ never cancel mid-deploy

jobs:
  # ── 0. THE AUTOMATED GATE (replaces the human) ─────────────────────────
  gate:
    name: Automated release gate
    runs-on: ubuntu-24.04
    outputs:
      service: ${{ steps.what.outputs.service }}
      digest:  ${{ steps.what.outputs.digest }}
    steps:
      - uses: actions/checkout@v7
      - id: what
        run: |
          set -euo pipefail
          SVC="${{ github.event.registry_package.name || inputs.service }}"
          SVC="${SVC##*/}"                      # strip the org prefix
          DIG="${{ inputs.digest }}"
          if [ -z "$DIG" ]; then
            DIG=$(crane digest "ghcr.io/3558bhk/${SVC}:main")
          fi
          echo "service=$SVC" >> "$GITHUB_OUTPUT"
          echo "digest=$DIG"  >> "$GITHUB_OUTPUT"

      - name: ⛔ Gate 1 — verify the signature (non-negotiable)
        run: |
          cosign verify "ghcr.io/3558bhk/${{ steps.what.outputs.service }}@${{ steps.what.outputs.digest }}" \
            --certificate-identity-regexp='https://github.com/3558Bhk/.*/\.github/workflows/ci-.*@refs/heads/main' \
            --certificate-oidc-issuer='https://token.actions.githubusercontent.com'
          echo "✅ signed by a trusted CI workflow on main"

      - name: ⛔ Gate 2 — freeze window / change calendar
        run: |
          set -euo pipefail
          # ⭐ a machine-checkable freeze. In a real company this is an API
          #   call to the change-management system. Here: no prod deploys
          #   Fri 16:00 → Mon 09:00 UTC, and never during an open SEV.
          DOW=$(date -u +%u); HOUR=$(date -u +%H)
          if [ "$DOW" -ge 5 ] && [ "$HOUR" -ge 16 ]; then
            echo "::error::⛔ frozen: weekend window"; exit 1
          fi
          if curl -fsS https://status.example.com/api/v1/incidents/open | jq -e '. | length > 0' >/dev/null; then
            echo "::error::⛔ frozen: an incident is open"; exit 1
          fi
          echo "✅ not frozen"

      - name: ⛔ Gate 3 — error budget
        run: |
          set -euo pipefail
          # ⭐⭐ THE ERROR BUDGET IS THE REAL ANSWER to "should we auto-deploy?"
          #   SLO = 99.9% of requests succeed over 28 days → budget = 0.1%.
          #   Burned > 100% → freeze automatic deploys; a human must decide.
          #   This converts a cultural argument into an arithmetic one.
          ./scripts/error-budget-check.sh --slo 0.999 --window 28d

      - name: ⛔ Gate 4 — change budget (rate limit on risk)
        run: |
          set -euo pipefail
          # ⭐ max 6 unattended prod deploys per service per day. Beyond
          #   that, something is wrong (a flapping test, a revert loop) and
          #   a human should look. Implemented as a count of today's
          #   successful runs of this workflow.
          N=$(gh run list --workflow cd-deployment.yml --status success \
              --json databaseId --jq 'length' --limit 200 | head -1 || echo 0)
          echo "deploys today: $N"
          [ "$N" -lt 6 ] || { echo "::error::⛔ change budget exhausted"; exit 1; }

  # ── 1. dev (automatic) ─────────────────────────────────────────────────
  deploy-dev:
    needs: gate
    runs-on: ubuntu-24.04
    environment: dev
    steps:
      - uses: actions/checkout@v7
      - uses: azure/k8s-set-context@v4
        with: { method: kubeconfig, kubeconfig: '${{ secrets.KUBECONFIG_DEV }}' }
      - run: |
          set -euo pipefail
          helm upgrade --install ${{ needs.gate.outputs.service }} deploy/chart \
            --namespace shop-dev --values deploy/values/dev.yaml \
            --set image.digest=${{ needs.gate.outputs.digest }} \
            --atomic --timeout 5m --wait
          ./scripts/smoke.sh shop-dev ${{ needs.gate.outputs.service }}

  # ── 2. staging (automatic) + full verification ─────────────────────────
  deploy-staging:
    needs: [gate, deploy-dev]
    runs-on: ubuntu-24.04
    environment: staging
    steps:
      - uses: actions/checkout@v7
      - uses: azure/k8s-set-context@v4
        with: { method: kubeconfig, kubeconfig: '${{ secrets.KUBECONFIG_STAGING }}' }
      - run: |
          set -euo pipefail
          helm upgrade --install ${{ needs.gate.outputs.service }} deploy/chart \
            --namespace shop-staging --values deploy/values/staging.yaml \
            --set image.digest=${{ needs.gate.outputs.digest }} \
            --atomic --timeout 5m --wait
      - run: ./scripts/e2e.sh https://staging.shop.example
      # ⭐⭐ SOAK. Case 2 has no human watching staging, so give the change
      #   time to fail on its own. 10 minutes catches memory leaks, cron
      #   misfires and connection-pool exhaustion that a 30 s smoke misses.
      - name: Soak (10 min, watch for regressions)
        run: ./scripts/soak.sh shop-staging ${{ needs.gate.outputs.service }} 600

  # ── 3. PRODUCTION via progressive delivery ─────────────────────────────
  # ⭐⭐⭐ The deploy is NOT `helm upgrade`. It is: set the new image on an
  #   Argo Rollouts `Rollout`, and let the controller walk the canary steps
  #   while running Prometheus analysis. If analysis fails, the controller
  #   rolls back BY ITSELF. The pipeline's job is to hand over and watch.
  deploy-production:
    needs: [gate, deploy-staging]
    runs-on: ubuntu-24.04
    environment: production          # ⭐ NO required reviewers configured.
                                     #   That absence is literally what makes
                                     #   this Continuous Deployment.
    steps:
      - uses: actions/checkout@v7
      - uses: azure/k8s-set-context@v4
        with: { method: kubeconfig, kubeconfig: '${{ secrets.KUBECONFIG_PROD }}' }

      - name: Pre-flight
        run: |
          set -euo pipefail
          kubectl get nodes | grep -q ' Ready'
          kubectl -n shop-production get rollout ${{ needs.gate.outputs.service }} -o name

      - name: Set the canary image (hand over to Argo Rollouts)
        run: |
          set -euo pipefail
          SVC=${{ needs.gate.outputs.service }}
          kubectl argo rollouts set image "$SVC" \
            "$SVC=ghcr.io/3558bhk/$SVC@${{ needs.gate.outputs.digest }}" \
            -n shop-production
          # ⭐ the Rollout spec (below) defines: 5% → 25% → 50% → 100%,
          #   with a Prometheus AnalysisTemplate at each pause.

      # ⭐⭐ THE PIPELINE NOW WAITS ON THE CONTROLLER, not on a sleep.
      - name: Watch the progressive rollout
        timeout-minutes: 20
        run: |
          set -euo pipefail
          SVC=${{ needs.gate.outputs.service }}
          kubectl argo rollouts status "$SVC" -n shop-production --watch
          # exits non-zero if the rollout is aborted → the `failure` handler
          # below fires → we verify the automatic rollback happened.

      - name: Post-promote verification
        run: |
          set -euo pipefail
          SVC=${{ needs.gate.outputs.service }}
          ./scripts/smoke.sh shop-production "$SVC"
          ./scripts/watch-metrics.sh shop-production "$SVC" 600
          echo "✅ fully promoted"

      - name: Notify
        if: always()
        run: |
          curl -X POST "$SLACK_WEBHOOK" -H 'Content-Type: application/json' -d "{
            \"text\": \"prod deploy ${{ needs.gate.outputs.service }}
                       ${{ needs.gate.outputs.digest }} →
                       ${{ job.status }} — ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}\"}"
        env: { SLACK_WEBHOOK: '${{ secrets.SLACK_WEBHOOK }}' }

      # ⭐⭐⭐ THE AUTO-ROLLBACK GUARANTEE. Argo Rollouts already reverted the
      #   traffic; this handler makes sure the state is consistent and that
      #   a human is told. In Case 2 the machine must clean up after itself.
      - name: On failure — confirm rollback + page a human
        if: failure()
        run: |
          set -euo pipefail
          SVC=${{ needs.gate.outputs.service }}
          kubectl argo rollouts abort "$SVC" -n shop-production || true
          kubectl argo rollouts status "$SVC" -n shop-production --watch || true
          kubectl -n shop-production get pods -l app=$SVC -o wide
          echo "⛔⛔ AUTO-DEPLOY FAILED AND WAS ABORTED. A human is being paged."
          curl -X POST "$PAGERDUTY_WEBHOOK" -H 'Content-Type: application/json' \
            -d "{\"routing_key\":\"$PD_KEY\",\"event_action\":\"trigger\",
                 \"payload\":{\"summary\":\"CD auto-rollback: $SVC\",
                              \"severity\":\"critical\",
                              \"source\":\"${{ github.run_id }}\"}}"
        env:
          PAGERDUTY_WEBHOOK: https://events.pagerduty.com/v2/enqueue
          PD_KEY: '${{ secrets.PD_ROUTING_KEY }}'
```

The `Rollout` + `AnalysisTemplate` that make this safe (full detail in §6.5):

```yaml
# deploy/rollouts/shop-api-rollout.yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout                       # ⭐ replaces the Deployment. A Rollout
metadata:                           #   IS a workload controller — it manages
  name: shop-api                    #   its own ReplicaSets.
  namespace: shop-production
spec:
  replicas: 6
  strategy:
    canary:
      canaryService: shop-api-canary      # ⭐ traffic routing needs a
      stableService: shop-api-stable      #   stable+canary service pair
      trafficRouting:
        plugins:
          argoproj-labs/gatewayAPI:       # (or nginx / istio / ALB)
            httpRoute: shop-api-route
            namespace: shop-production
      steps:
        - setWeight: 5                # ⭐ 5% of traffic to the new version
        - pause: { duration: 3m }     #   and hold
        - analysis:                   # ⭐⭐ measure before continuing
            templates:
              - templateName: success-rate
              - templateName: latency-p99
            args:
              - name: service
                value: shop-api
        - setWeight: 25
        - pause: { duration: 5m }
        - analysis: { templates: [{ templateName: success-rate }] }
        - setWeight: 50
        - pause: {}                   # ⭐ an EMPTY pause = manual gate.
                                      #   ⛔ remove it for Case 2, keep it
                                      #   for Case 1 (hybrid: automated
                                      #   canary, human final promote).
        - setWeight: 100
      # ⭐⭐⭐ automatic abort. If analysis fails, Rollouts scales the canary
      #   to zero and restores the stable ReplicaSet. No human, no pipeline.
      analysis:
        successfulRunHistoryLimit: 3
        unsuccessfulRunHistoryLimit: 3
  selector: { matchLabels: { app: shop-api } }
  template:
    metadata: { labels: { app: shop-api } }
    spec:
      containers:
        - name: shop-api
          image: ghcr.io/3558bhk/shop-api:placeholder   # set by `rollouts set image`
          ports: [{ containerPort: 8080 }]
          readinessProbe:                # ⭐⭐⭐ without this the canary is
            httpGet: { path: /ready, port: 8080 }   # meaningless: traffic is
            initialDelaySeconds: 20      # sent to a JVM that hasn't warmed.
            periodSeconds: 5
            failureThreshold: 3
          livenessProbe:
            httpGet: { path: /health, port: 8080 }
            initialDelaySeconds: 45      # ⭐ Spring Boot needs time. A too-
            periodSeconds: 10            #   eager liveness probe restart-loops
          resources:                     #   a perfectly healthy pod.
            requests: { cpu: 250m, memory: 512Mi }
            limits:   { cpu: '1',  memory: 1Gi }
---
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata: { name: success-rate }
spec:
  args: [{ name: service }]
  metrics:
    - name: success-rate
      interval: 60s                # ⭐ query every minute
      count: 5                     #   five times
      successCondition: result[0] >= 0.995   # ⭐⭐ ≥99.5% success
      failureLimit: 2              #   tolerate 2 failures, abort on the 3rd
      provider:
        prometheus:
          address: http://prometheus-server.monitoring:9090
          query: |
            sum(rate(http_server_requests_seconds_count{
                  application="{{args.service}}",status!~"5.."}[2m]))
            /
            sum(rate(http_server_requests_seconds_count{
                  application="{{args.service}}"}[2m]))
          # ⭐⭐ THE QUERY IS THE CANARY. If it is wrong, your automated
          #   gate is decoration. Test it by hand in Prometheus FIRST, and
          #   deliberately break the app once to prove it goes red.
```

#### 4.2.2 The three tools — Case 2 gate comparison

| Requirement | 🐙 GitHub Actions | 🔷 Azure DevOps | 🔨 Jenkins |
|---|---|---|---|
| Trigger on artifact, not commit | `registry_package` / `repository_dispatch` | ⭐ `trigger: builds:` (release pipeline) or a service hook | upstream `build job:` / Generic Webhook Trigger |
| No human gate | simply configure **no** required reviewers on the environment | ⭐ remove all Environment checks; `trigger: builds` auto-releases | omit the `input` step |
| Automated pre-checks | a `gate` job with `needs:` | a `preDeploy` hook on the `deployment` job | a `stage('Gate')` with `failFast` |
| Progressive delivery | Argo Rollouts via `kubectl argo rollouts set image` | same (or `Deploy to Kubernetes@1` canary strategy) | same |
| Auto-rollback | Argo `analysis` + `if: failure()` handler | ⭐ `on: failure:` steps in a `deployment` job | `post { failure { … } }` |
| Rate limiting deploys | count runs via `gh run list` | ⭐ Environment check "REST check" against a counter | Lockable Resources plugin / a counter file |
| Audit trail | environment deployment history + `actions/attest` | ⭐⭐ Release → Deployments view (best in class) | `currentBuild.description` + a log artifact |
| Notify | Slack webhook | Service Hooks | `slackSend` |

#### 4.2.3 ⭐⭐⭐ Case 1 vs Case 2 — the 14-row comparison

| Dimension | Case 1 · Continuous **Delivery** | Case 2 · Continuous **Deployment** |
|---|---|---|
| Prod trigger | a human clicks | the artifact appears |
| Time from merge to prod | hours–days | minutes |
| Batch size | large (a release train) | ⭐ tiny (one commit) |
| Risk per deploy | ⛔ high — many changes at once | ✅ low — one change |
| Debuggability | ⛔ "which of 40 commits broke it?" | ✅ `git bisect` on one commit |
| Required automation | tests + an approval UI | tests + canary + **analysis** + auto-rollback + budgets |
| Required observability | dashboards a human reads | ⭐⭐ SLOs the machine reads |
| Prerequisite culture | release manager ownership | on-call ownership, blameless postmortems |
| Compliance fit | ⭐ regulated environments | consumer/internal, unless the regulator accepts automated controls |
| Failure cost | one bad release, noticed late | one bad release, reverted in <5 min |
| Rollback path | human decides | machine decides, human is informed |
| Weekend deploys | never (nobody is there) | ⭐ fine — nobody needs to be there |
| Config | Environment + Required reviewers | Environment + **no** reviewers + Argo analysis |
| Maturity ladder | level 3 | level 4 — you must pass level 3 first |

🔑 **The interview line:** "Continuous Deployment isn't a pipeline setting, it's a maturity level. I'd only enable it once four things are true: deploys are small enough that any single one is low-risk, the rollout is progressive with automated analysis against real SLOs, rollback is automatic and tested — actually tested, by breaking staging on purpose — and there's a change budget that re-introduces a human when the rate of deploys itself looks abnormal. Absent those, Continuous Delivery with a real approval gate is the honest answer, and claiming otherwise in an interview is a red flag."

---

## 5 · SCENARIO 3 — CI + CD BOTH (the full path)

### 5.1 The architectural decision first

⭐⭐ Before writing YAML, decide **how many pipelines** and **where the handoff is**. There are three valid shapes and one wrong one.

| Shape | Description | Pros | Cons | Verdict |
|---|---|---|---|---|
| **3a — One pipeline, many stages** | a single YAML with `CI` → `dev` → `staging` → `prod` stages | easiest to write; one green tick | ⛔ CI credentials and prod credentials in the same trust domain; ⛔ a prod redeploy re-runs CI; ⛔ 40-min pipeline for a one-line lint failure | ok for a toy; ⛔ not for prod |
| **3b — Two pipelines, artifact handoff** | CI pipeline → publishes digest; CD pipeline → triggered by the digest | ✅ credential separation; ✅ CD can re-run without rebuilding; ✅ each is fast | you must design the contract | ⭐ **the standard** |
| **3c — CI pipeline + GitOps CD (Argo)** | CI builds, signs, and opens a PR on `shop-config`; Argo CD syncs the cluster from Git | ✅✅ CI has NO cluster credential at all; ✅ full Git audit; ✅ drift detection & self-heal; ✅ one CD path for every tool and every team | a config repo to maintain; a learning curve | ⭐⭐⭐ **the production-grade answer** — this is what file 05 builds |
| **3d — CD that rebuilds** | the CD pipeline runs the tests again "to be sure" | feels safe | ⛔ you are now deploying an artifact you did not test, because the rebuild is not bit-identical | ⛔ never |

```
SHAPE 3c — RECOMMENDED

  app repo (source)                 config repo (desired state)
  ─────────────────                 ───────────────────────────
      │ commit                             ▲
      ▼                                    │ PR: bump digest
  ┌────────┐   image@sha256:9f2c    ┌──────┴───────┐
  │   CI   │───────────────────────▶│ ghcr.io /    │
  │ (3.1)  │   push + SIGN          │   ACR        │
  └────────┘                        └──────┬───────┘
      │                                    │ pulls by digest
      └── opens PR on config repo          │
                        │            ┌─────▼─────┐
             a HUMAN merges          │  Argo CD  │  ← polls Git every 3 min
             (Case 1: Delivery)      └─────┬─────┘    + webhook on change
             or a bot merges               │ syncs
             (Case 2: Deployment)    ┌─────▼──────────────┐
                                     │ Kubernetes (shop)  │
                                     └────────────────────┘
   ⭐ CI holds: registry write + config-repo PR permission. NOTHING ELSE.
   ⭐ The cluster holds: registry READ. It never talks to CI.
```

### 5.2 🐙 GitHub Actions — full CI + CD (shape 3c, polyglot)

Two files. This is the complete answer to "wire it all together".

```yaml
# ═══ FILE 1 of 2: .github/workflows/ci.yml — build, test, sign, PROPOSE ═══
name: ci

on:
  push: { branches: [main] }
  pull_request: { branches: [main] }

permissions: { contents: read }

jobs:
  changes:
    runs-on: ubuntu-24.04
    outputs: { services: '${{ steps.f.outputs.services }}' }
    steps:
      - uses: actions/checkout@v7
      - id: f
        uses: dorny/paths-filter@v3
        with:
          # ⭐⭐ output a JSON LIST of changed services, so the build job can
          #   matrix over exactly them. This is cleaner than five booleans.
          filters: |
            shop-ui:      ['apps/shop-ui/**']
            shop-api:     ['apps/shop-api/**']
            checkout:     ['apps/checkout/**']
            order-worker: ['apps/order-worker/**']
            payment-mock: ['apps/payment-mock/**']
      - id: list
        run: |
          # turn the filter outputs into a JSON array of only the true ones
          SERVICES=$(jq -nc --argjson f '${{ steps.f.outputs }}' \
            '[$f | to_entries[] | select(.value=="true") | .key]')
          # ⭐ on a push to main with no filter hits (e.g. a README change),
          #   fall back to an empty array so the matrix is a no-op.
          echo "services=$SERVICES" >> "$GITHUB_OUTPUT"
    # (job outputs are referenced below as needs.changes.outputs.services)

  build:
    needs: changes
    if: ${{ needs.changes.outputs.services != '[]' }}
    runs-on: ubuntu-24.04
    strategy:
      fail-fast: false                     # ⭐ build every changed service
      matrix:                              #   even if one fails
        service: ${{ fromJson(needs.changes.outputs.services) }}
        include:
          # ⭐⭐ `include` adds per-service parameters to the matrix without
          #   writing five separate jobs.
          - { service: shop-ui,      lang: node,   test: 'npm ci && npm run lint && npm run test -- --run' }
          - { service: shop-api,     lang: java,   test: './mvnw -B -ntp verify' }
          - { service: checkout,     lang: go,     test: 'go test -race -shuffle=on ./...' }
          - { service: order-worker, lang: python, test: 'pip install -r requirements.txt && pytest -q' }
          - { service: payment-mock, lang: go,     test: 'go test -race ./...' }
    permissions:
      contents: read
      packages: write
      id-token: write
    outputs:
      digests: ${{ steps.done.outputs.digests }}
    steps:
      - uses: actions/checkout@v7
      - run: cd apps/${{ matrix.service }} && ${{ matrix.test }}
      - uses: docker/setup-buildx-action@v3
      - uses: docker/login-action@v3
        with: { registry: ghcr.io }
      - id: push
        uses: docker/build-push-action@v6
        with:
          context: apps/${{ matrix.service }}
          push: true
          tags: |
            ghcr.io/3558bhk/${{ matrix.service }}:sha-${{ github.sha }}
            ghcr.io/3558bhk/${{ matrix.service }}:main
          cache-from: type=gha,scope=${{ matrix.service }}
          cache-to: type=gha,scope=${{ matrix.service }},mode=max
          provenance: mode=max
          sbom: true
      - run: cosign sign --yes "ghcr.io/3558bhk/${{ matrix.service }}@${{ steps.push.outputs.digest }}"
      - run: echo "ghcr.io/3558bhk/${{ matrix.service }}@${{ steps.push.outputs.digest }}" >> "$GITHUB_STEP_SUMMARY"
      - id: done
        run: |
          # ⭐ accumulate per-service digests into a single JSON object that
          #   the next job can read. (In a matrix job, `outputs` is per-leg,
          #   so the aggregation job below re-derives them deterministically.)
          echo "digests={\"${{ matrix.service }}\":\"${{ steps.push.outputs.digest }}\"}" >> "$GITHUB_OUTPUT"

  # ══ THE HANDOFF: CI proposes the new desired state as a PULL REQUEST ══
  # ⭐⭐⭐ This job is the whole point of shape 3c. CI never touches a
  #   cluster. It writes Git. Merging the PR IS the deployment decision —
  #   which means Case 1 (human merges) and Case 2 (a bot merges) differ
  #   by ONE LINE, not by a different architecture.
  propose:
    name: Propose release (PR on shop-config)
    needs: build
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    runs-on: ubuntu-24.04
    permissions:
      contents: read
      pull-requests: write          # ⭐ scoped to THIS job only
    steps:
      - uses: actions/checkout@v7
        with:
          repository: 3558Bhk/shop-config      # ⭐ the CONFIG repo
          path: shop-config
          token: ${{ secrets.CONFIG_REPO_TOKEN }}
      - name: Bump the digests
        run: |
          set -euo pipefail
          cd shop-config
          git checkout -b "release/${GITHUB_SHA::8}"
          for SVC in shop-ui shop-api checkout order-worker payment-mock; do
            # ⭐ resolve what CI just pushed, tag→digest, and write it in.
            D=$(crane digest "ghcr.io/3558bhk/${SVC}:sha-${GITHUB_SHA}" 2>/dev/null || true)
            [ -z "$D" ] && continue            # not changed in this commit
            yq -i ".images.${SVC} = \"${D}\"" environments/staging/images.yaml
            echo "  ${SVC} → ${D}"
          done
          git add -A
          git -c user.name='ci-bot' -c user.email='ci@example.com' \
              commit -m "release: bump digests for ${GITHUB_SHA::8}" || {
                echo "nothing to release"; exit 0; }
          git push origin "release/${GITHUB_SHA::8}"
      - name: Open the promotion PR
        run: |
          cd shop-config
          gh pr create --base main --head "release/${GITHUB_SHA::8}" \
            --title "release: ${GITHUB_SHA::8}" \
            --body "### Promoted by CI
          | service | digest |
          |---|---|
          $(git show --stat --oneline HEAD | tail -n +2)

          - source commit: ${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/commit/${GITHUB_SHA}
          - CI run: ${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}

          ⭐ **Merging this PR deploys to staging.** Production requires the
          separate \`promote-prod\` PR (created after staging verification)."
        env:
          GH_TOKEN: ${{ secrets.CONFIG_REPO_TOKEN }}
```

```yaml
# ═══ FILE 2 of 2: .github/workflows/cd-gitops.yml — in the shop-config repo ═══
# ⭐⭐ This file lives in shop-config, NOT in the app repo. It runs when the
#   config repo changes — i.e. when someone merges a promotion PR.
#   Case 1: a human merges → this runs → Delivery.
#   Case 2: a bot auto-merges after staging analysis → this runs → Deployment.
name: cd-gitops

on:
  push: { branches: [main] }
  workflow_dispatch: {}

permissions: { contents: read, id-token: write }

concurrency:
  group: cd-gitops-production
  cancel-in-progress: false

jobs:
  sync:
    name: Sync cluster to Git
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v7
      - name: Validate the desired state
        run: |
          set -euo pipefail
          # ⭐⭐⭐ the config repo is now PRODUCTION CODE. Lint it like it.
          kubeconform -strict -summary deploy/**/*.yaml
          helm lint chart/
          yq e '.' environments/production/images.yaml > /dev/null   # YAML parse
          # ⭐ policy: no `:latest`, no mutable tags, digests only
          if grep -rn ':latest' environments/ ; then
            echo "::error::⛔ :latest is forbidden in the config repo"; exit 1
          fi
          grep -rEn '@sha256:[0-9a-f]{64}' environments/production/images.yaml
      - name: Tell Argo CD to sync now
        run: |
          set -euo pipefail
          # ⭐⭐ Argo polls every ~3 min by default. For a responsive pipeline
          #   either (a) enable the webhook so Argo reacts instantly, or
          #   (b) trigger the sync explicitly, as here. Prefer (a).
          argocd login argo.shop.example --core --grpc-web
          argocd app sync shop-production --revision main --timeout 600
          argocd app wait shop-production --health --sync --timeout 600
          # ⭐ `app wait --health` is the CD equivalent of `helm --wait`.
      - name: Verify + rollback on failure
        if: failure()
        run: |
          set -euo pipefail
          echo "⛔ sync failed — reverting Git, which is the rollback in GitOps"
          git revert --no-edit HEAD && git push
          argocd app sync shop-production --timeout 600
      - name: Post-deploy verification
        run: ./scripts/smoke.sh shop-production all
```

### 5.3 🔷 Azure DevOps — full CI + CD (classic two-stage: build pipeline → release pipeline)

⭐ Azure DevOps' native answer to Scenario 3 is **two separate objects**: a *build pipeline* (CI) and a *release pipeline* (CD), linked by an artifact. This is the clearest expression of the CI/CD boundary of any of the three tools.

```text
┌── BUILD PIPELINE (YAML, in the app repo) ──────────────────────────────┐
│  trigger: push to main                                                 │
│  stages: CI → publish artifact `image-refs`                            │
└───────────────────────────────┬────────────────────────────────────────┘
                                │ artifact + "release triggered on build
                                │  completion" (a service hook)
┌───────────────────────────────▼────────────────────────────────────────┐
│  RELEASE PIPELINE (classic UI or YAML)                                 │
│   artifacts: shop-ci (build)                                           │
│   stages:  dev  →  staging  →  🚪 approval  →  production              │
│   triggers:                                                            │
│     • "create a release when a build completes"  ← Case 2 (Deployment) │
│     • manual / scheduled                          ← Case 1 (Delivery)  │
│   ⭐ the SAME release pipeline serves both cases. The only difference   │
│      is whether the production stage has an approval check.            │
└────────────────────────────────────────────────────────────────────────┘
```

```yaml
# ci-azure.yml — the CI half (full version in §3.2; abridged here)
trigger: { batch: true, branches: { include: [main] }, paths: { include: [apps/*] } }
pool: { vmImage: 'ubuntu-24.04' }
stages:
  - stage: CI
    jobs:
      - template: ci/templates/build-test-image.yml
        parameters: { service: shop-api, language: java, appDir: apps/shop-api,
                      testCmd: './mvnw -B -ntp verify', registry: shopacr.azurecr.io,
                      dockerRegistryServiceConnection: shop-acr-wif }
      - template: ci/templates/build-test-image.yml
        parameters: { service: shop-ui, language: node, appDir: apps/shop-ui,
                      testCmd: 'npm ci && npm run test -- --run', registry: shopacr.azurecr.io,
                      dockerRegistryServiceConnection: shop-acr-wif }
  # ⭐ the artifact `image-refs` published by the template IS the contract.
```

```yaml
# cd-azure.yml — the CD half, as YAML (Azure now supports multi-stage
# release pipelines in YAML; `deployment` jobs are the release equivalent)
trigger: none                # ⛔ NOT triggered by source
pr: none

resources:
  pipelines:
    - pipeline: shop-ci                # ⭐⭐ THE HANDOFF. This names the CI
      source: shop-ci                  #   pipeline as an artifact source.
      project: Shop                    #   `DownloadPipelineArtifact@2` can
      trigger:                         #   then pull from it.
        branches: { include: [main] }
        # ⭐⭐⭐ THE CASE 1 / CASE 2 SWITCH LIVES RIGHT HERE:
        #   `trigger:` present  → a completed build STARTS this pipeline
        #                         automatically  = CONTINUOUS DEPLOYMENT
        #   `trigger:` removed  → you run it manually / on a schedule
        #                         = CONTINUOUS DELIVERY
        #   Plus the approval stage below. Both together = the full picture.

pool: { vmImage: 'ubuntu-24.04' }
variables:
  - group: shop-cd

stages:
  - stage: fetch
    displayName: '0 · Fetch the CI artifact'
    jobs:
      - job: fetch
        steps:
          - task: DownloadPipelineArtifact@2
            inputs:
              buildType: 'specific'          # or 'current' for the trigger build
              project: Shop
              pipeline: shop-ci
              buildVersionToDownload: 'latestFromBranch'
              branchName: 'refs/heads/main'
              artifactName: image-refs
              targetPath: '$(Pipeline.Workspace)/refs'
          - script: |
              set -euo pipefail
              cat $(Pipeline.Workspace)/refs/digest.txt
              API=$(grep '^shop-api=' $(Pipeline.Workspace)/refs/digest.txt | cut -d= -f2)
              UI=$(grep  '^shop-ui='  $(Pipeline.Workspace)/refs/digest.txt | cut -d= -f2)
              echo "##vso[task.setvariable variable=API_DIGEST;isOutput=true]$API"
              echo "##vso[task.setvariable variable=UI_DIGEST;isOutput=true]$UI"
            name: d

  - stage: dev
    dependsOn: fetch
    variables:
      API_DIGEST: $[ stageDependencies.fetch.fetch.outputs['d.API_DIGEST'] ]
      UI_DIGEST:  $[ stageDependencies.fetch.fetch.outputs['d.UI_DIGEST'] ]
    jobs:
      - deployment: fe_be_dev
        environment: { name: shop-dev }
        strategy:
          runOnce:
            deploy:
              steps:
                - checkout: self                        # ⭐ deployment jobs
                - task: HelmDeploy@0                    #   do NOT check out
                  inputs:                               #   source by default.
                    command: upgrade                    #   You must say so —
                    chartPath: deploy/chart             #   a classic trap.
                    releaseName: shop-api
                    namespace: shop-dev
                    valueFile: deploy/values/dev.yaml
                    arguments: >
                      --atomic --wait --timeout 5m
                      --set image.digest=$(API_DIGEST)
                - task: HelmDeploy@0
                  inputs:
                    command: upgrade
                    chartPath: deploy/chart
                    releaseName: shop-ui
                    namespace: shop-dev
                    valueFile: deploy/values/dev.yaml
                    arguments: '--atomic --wait --set image.digest=$(UI_DIGEST)'
                - script: ./scripts/smoke.sh shop-dev all

  - stage: staging
    dependsOn: dev
    jobs:
      - deployment: fe_be_staging
        environment: { name: shop-staging }
        strategy:
          runOnce:
            deploy:
              steps:
                - checkout: self
                - script: ./scripts/deploy-staging.sh $(API_DIGEST) $(UI_DIGEST)
                - script: ./scripts/e2e.sh https://staging.shop.example
                - script: ./scripts/contract-test.sh staging   # ⭐ FE↔BE skew

  - stage: approval                       # ← Case 1 keeps this; Case 2 deletes it
    displayName: '🚪 Production approval'
    dependsOn: staging
    pool: server
    jobs:
      - job: gate
        timeoutInMinutes: 4320
        steps:
          - task: ManualValidation@1
            inputs:
              notifyUsers: 'release-managers@example.com'
              instructions: 'Digests: $(API_DIGEST) $(UI_DIGEST). Check staging e2e + freeze calendar.'
              onTimeout: reject

  - stage: production
    dependsOn: approval                   # ← Case 2: `dependsOn: staging`
    jobs:
      - deployment: fe_be_prod
        environment: { name: shop-production, resourceName: shop }
        strategy:
          runOnce:
            preDeploy:
              steps:
                - checkout: self
                - script: ./scripts/preflight.sh shop-production
            deploy:
              steps:
                - checkout: self
                - script: ./scripts/deploy-prod.sh $(API_DIGEST) $(UI_DIGEST)
                - script: kubectl -n shop-production rollout status deploy/shop-api --timeout=600s
                - script: ./scripts/smoke.sh shop-production all
                - script: ./scripts/watch-metrics.sh shop-production all 300
            on:
              failure:
                steps:
                  - checkout: self
                  - script: |
                      helm rollback shop-api -n shop-production --wait
                      helm rollback shop-ui  -n shop-production --wait
                      ./scripts/smoke.sh shop-production all
```

### 5.4 🔨 Jenkins — full CI + CD in one multibranch pipeline

```groovy
// ══════════════════════════════════════════════════════════════════════
// Jenkinsfile  — SCENARIO 3: CI + CD, shape 3b (artifact handoff)
// ══════════════════════════════════════════════════════════════════════
// WHAT   : one file, commit → prod, for the polyglot monorepo.
// WHY    : this is the shape most Jenkins shops actually run. It is shape
//          3a/3b hybrid: one pipeline, but the prod stage is a SEPARATE
//          credential domain and can be re-run on its own.
// ⭐     Note `when { branch 'main' }` on the CD stages: PRs get CI only,
//          automatically. That is Scenario 1 and Scenario 3 in one file.
// ══════════════════════════════════════════════════════════════════════

pipeline {
  agent none                        // ⭐ each stage picks its own agent,
                                    //   so a Go stage doesn't wait for the
                                    //   Maven agent to be free.
  options {
    timestamps()
    buildDiscarder(logRotator(numToKeepStr: '40', artifactNumToKeepStr: '10'))
    skipStagesAfterUnstable()       // ⭐ stop early; don't waste 20 minutes
    timeout(time: 90, unit: 'MINUTES')
    parallelsAlwaysFailFast()       // ⭐ when one parallel branch fails,
                                    //   abort the siblings immediately
  }

  environment {
    REGISTRY = 'ghcr.io/3558bhk'
    GIT_SHA  = "${env.GIT_COMMIT?.take(8) ?: 'unknown'}"
  }

  stages {

    // ══ DETECT ═════════════════════════════════════════════════════════
    stage('Detect changes') {
      agent { label 'ci' }
      steps {
        checkout scm
        script {
          // ⭐⭐ `changeset` only works per-stage. To drive a MATRIX from
          //   changed paths you must compute the list yourself.
          def changed = sh(returnStdout: true, script: '''
            set -e
            BASE="${GIT_PREVIOUS_SUCCESSFUL_COMMIT:-HEAD~1}"
            git diff --name-only "$BASE" HEAD || true
          ''').readLines()
          def svcs = []
          if (changed.any { it.startsWith('apps/shop-ui/') })      svcs << 'shop-ui'
          if (changed.any { it.startsWith('apps/shop-api/') })     svcs << 'shop-api'
          if (changed.any { it.startsWith('apps/checkout/') })     svcs << 'checkout'
          if (changed.any { it.startsWith('apps/order-worker/') }) svcs << 'order-worker'
          if (changed.any { it.startsWith('apps/payment-mock/') }) svcs << 'payment-mock'
          if (changed.any { it.startsWith('deploy/') })            svcs = ['shop-ui','shop-api','checkout','order-worker','payment-mock']
          env.CHANGED = svcs.join(',')
          echo "changed services: ${env.CHANGED ?: '(none)'}"
          currentBuild.description = env.CHANGED ?: 'no app changes'
        }
      }
    }

    // ══ CI — one parallel branch per changed service ═══════════════════
    stage('CI') {
      when { expression { env.CHANGED?.trim() } }
      parallel {
        stage('CI · shop-ui') {
          when { expression { env.CHANGED.contains('shop-ui') } }
          agent { kubernetes { yaml uiAgentPod() } }       // ⭐ a function in
          steps {                                          //   the shared lib
            container('node') { dir('apps/shop-ui') {
              sh 'npm ci && npm run lint && npm run test -- --run'
            }}
          }
          post { always { junit 'apps/shop-ui/**/junit.xml' } }
        }
        stage('CI · shop-api') {
          when { expression { env.CHANGED.contains('shop-api') } }
          agent { kubernetes { yaml javaAgentPod() } }
          steps {
            container('maven') { dir('apps/shop-api') {
              sh './mvnw -B -ntp --fail-at-end verify'
            }}
          }
          post { always { junit allowEmptyResults: true,
                                testResults: 'apps/shop-api/target/surefire-reports/*.xml' } }
        }
        stage('CI · go services') {
          when { expression { env.CHANGED =~ /checkout|payment-mock/ } }
          agent { kubernetes { yaml goAgentPod() } }
          steps {
            container('golang') {
              // ⭐⭐ one branch handles BOTH Go services — they share a
              //   toolchain, so sharing an agent halves the pod startup.
              script {
                for (s in ['checkout','payment-mock']) {
                  if (!env.CHANGED.contains(s)) continue
                  dir("apps/${s}") { sh 'go test -race -shuffle=on ./... && go vet ./...' }
                }
              }
            }
          }
        }
        stage('CI · order-worker') {
          when { expression { env.CHANGED.contains('order-worker') } }
          agent { kubernetes { yaml pyAgentPod() } }
          steps {
            container('python') { dir('apps/order-worker') {
              sh 'pip install -r requirements.txt && pytest -q --junitxml=junit.xml'
            }}
          }
          post { always { junit 'apps/order-worker/junit.xml' } }
        }
      }
    }

    // ══ IMAGE — build, scan, sign, push ════════════════════════════════
    stage('Build & sign images') {
      when {
        branch 'main'                       // ⭐⭐ PRs do NOT push images.
        expression { env.CHANGED?.trim() }  //   Pushing from a PR would let a
      }                                     //   fork publish to your registry.
      agent { kubernetes { yaml kanikoAgentPod() } }
      steps {
        container('kaniko') {
          script {
            def digests = [:]
            for (s in env.CHANGED.split(',')) {
              // ⭐ Kaniko: no Docker daemon, no privileged mode (§3.3.3)
              sh """
                /kaniko/executor --context dir://\$WORKSPACE/apps/${s} \\
                  --dockerfile Dockerfile \\
                  --destination ${REGISTRY}/${s}:sha-${GIT_SHA} \\
                  --cache=true --cache-repo=${REGISTRY}/${s}-cache \\
                  --reproducible
              """
              def d = sh(returnStdout: true, script:
                "crane digest ${REGISTRY}/${s}:sha-${GIT_SHA}").trim()
              digests[s] = d
              echo "${s} → ${d}"
            }
            env.DIGESTS = groovy.json.JsonOutput.toJson(digests)
            // ⭐⭐ sign each one — Jenkins has no OIDC, so cosign uses a
            //   key stored as a Jenkins credential. Rotate it like any other.
            withCredentials([file(credentialsId: 'cosign-key', variable: 'COSIGN_KEY'),
                             string(credentialsId: 'cosign-password', variable: 'COSIGN_PASSWORD')]) {
              digests.each { s, d ->
                sh "cosign sign --yes --key \$COSIGN_KEY ${REGISTRY}/${s}@${d}"
              }
            }
            writeFile file: 'digests.json', text: env.DIGESTS
            archiveArtifacts 'digests.json'
            fingerprint true                 // ⭐ link artifact ↔ builds
          }
        }
      }
    }

    // ══ CD: dev (automatic) ════════════════════════════════════════════
    stage('Deploy → dev') {
      when { branch 'main'; expression { env.CHANGED?.trim() } }
      agent { label 'cd' }
      steps { deployTo('shop-dev', 'dev', false) }        // ⭐ shared-lib fn
    }

    // ══ CD: staging (automatic) ════════════════════════════════════════
    stage('Deploy → staging') {
      when { branch 'main' }
      agent { label 'cd' }
      steps {
        deployTo('shop-staging', 'staging', false)
        sh './scripts/e2e.sh https://staging.shop.example'
        sh './scripts/contract-test.sh staging'
      }
    }

    // ══ 🚪 GATE — delete this stage for Case 2 (Continuous Deployment) ══
    stage('Approval') {
      when { branch 'main' }
      agent { label 'gate' }               // ⭐ a cheap agent with many
      steps {                              //   executors, because `input`
        timeout(time: 24, unit: 'HOURS') { //   HOLDS AN EXECUTOR while it
          script {                         //   waits. This is the Jenkins-
            def a = input(                 //   specific cost of a human gate.
              message: '🚪 Promote to PRODUCTION?',
              submitter: 'release-managers',
              submitterParameter: 'APPROVED_BY',
              parameters: [string(name: 'TICKET', description: 'change ticket')])
            if (!a.TICKET?.trim()) { error '⛔ ticket required' }
            env.APPROVED_BY = a.APPROVED_BY
            env.TICKET = a.TICKET
          }
        }
      }
    }

    // ══ CD: production ═════════════════════════════════════════════════
    stage('Deploy → production') {
      when { branch 'main' }
      agent { label 'cd' }
      steps {
        script {
          // ⭐⭐⭐ THE CREDENTIAL BOUNDARY. `kubeconfig-prod` is a
          //   FOLDER-SCOPED credential, visible only to this folder's jobs.
          //   A PR job — which may run attacker-controlled Jenkinsfile code
          //   from a fork — must never be able to read it. Verify the scope
          //   in Manage Jenkins → Credentials → the credential → Scope.
          withCredentials([file(credentialsId: 'cosign-key', variable: 'COSIGN_KEY'),
                           string(credentialsId: 'cosign-password', variable: 'COSIGN_PASSWORD')]) {
            sh '''
              set -euo pipefail
              # verify EVERY digest before it can be deployed
              echo "$DIGESTS" | jq -r 'to_entries[] | "\\(.key) \\(.value)"' |
              while read -r svc dg; do
                cosign verify --key "$COSIGN_KEY" "${REGISTRY}/${svc}@${dg}" >/dev/null
                echo "✅ ${svc} signature OK"
              done
            '''
          }
        }
        deployTo('shop-production', 'production', true)     // canary = true
      }
      post {
        success {
          sh '''echo "$(date -u +%FT%TZ) prod ${CHANGED} ${DIGESTS}
                       approver=${APPROVED_BY:-auto} ticket=${TICKET:-auto}
                       build=${BUILD_URL}" >> deploy-audit.log'''
          archiveArtifacts 'deploy-audit.log'
        }
        failure {
          slackSend(channel: '#shop-oncall', color: 'danger',
            message: "⛔ PROD deploy failed: ${env.CHANGED} — ${env.BUILD_URL}")
        }
      }
    }
  }

  post {
    always  { cleanWs(deleteDirs: true, notFailBuild: true) }   // ⭐ workspace
    success { slackSend(channel: '#shop-ci', color: 'good',     //   plugin. Stale
      message: "✅ ${env.JOB_NAME} #${env.BUILD_NUMBER} (${env.CHANGED})") } // workspaces
    failure { slackSend(channel: '#shop-ci', color: 'danger',   // are the #1 cause
      message: "⛔ ${env.JOB_NAME} #${env.BUILD_NUMBER} FAILED — ${env.BUILD_URL}") } // of "works on
  }                                                              // my machine"
}
```

### 5.5 ⭐⭐⭐ The GitOps variant — and why it is the recommended Scenario 3

Already implemented in §5.2 for GitHub Actions. The key properties, and how to get them in the other two tools:

| Property | Why it matters | GitHub | Azure DevOps | Jenkins |
|---|---|---|---|---|
| CI holds **no** cluster credential | a compromised runner cannot touch prod | CI opens a PR with `pull-requests: write` | CI publishes an artifact; a separate release pipeline holds the connection | folder-scoped credentials + a separate CD job |
| Desired state is in **Git** | the answer to "what is running in prod?" is `git log`, not `kubectl get` | `shop-config` repo | Azure Repos `shop-config` | a `shop-config` Git repo |
| The cluster **pulls** | no inbound firewall holes; works across clouds/VPCs | Argo CD Application | Argo CD | Argo CD |
| **Drift** is detected and healed | someone's emergency `kubectl edit` gets reverted in 3 min | `selfHeal: true` | same | same |
| Rollback = `git revert` | one mechanism, universally understood | ✅ | ✅ | ✅ |

```yaml
# shop-config/argocd/applications/shop-production.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: shop-production
  namespace: argocd
  finalizers: [resources-finalizer.argocd.argoproj.io]   # ⭐ cascade delete
spec:
  project: shop
  source:
    repoURL: https://github.com/3558Bhk/shop-config
    targetRevision: main              # ⭐ the branch = the environment.
    path: environments/production     #   staging tracks `main`; prod can
    helm:                             #   track a `release` tag for extra
      valueFiles:                     #   safety (a human moves the tag).
        - values.yaml
        - images.yaml                 # ⭐ THE FILE CI WRITES. One file,
  destination:                        #   one line per service, one digest.
    server: https://kubernetes.default.svc
    namespace: shop-production
  syncPolicy:
    automated:
      prune: true        # ⭐⭐ delete resources removed from Git. Without
      selfHeal: true     #   this, `kubectl delete` on a live object is
                         #   permanent until someone notices.
    syncOptions:
      - CreateNamespace=true
      - ApplyOutOfSyncOnly=true      # ⭐ don't re-apply unchanged objects
      - ServerSideApply=true         # ⭐⭐ avoids "annotation too long"
                                     #   errors on big CRDs; SSA is the
                                     #   modern default
      - RespectIgnoreDifferences=true
    retry:
      limit: 5
      backoff: { duration: 5s, factor: 2, maxDuration: 3m }
  # ⭐⭐ ignore the fields the cluster owns, or Argo will fight the HPA
  #   forever: it sets replicas=6, the HPA sets replicas=11, Argo sees
  #   drift, sets 6, the HPA sets 11… an infinite flap.
  ignoreDifferences:
    - group: apps
      kind: Deployment
      jsonPointers: [/spec/replicas]
    - group: argoproj.io
      kind: Rollout
      jsonPointers: [/spec/replicas]
```

🔑 **The interview line:** "In Scenario 3 I use GitOps rather than a pipeline that runs `helm upgrade`. CI builds and signs an image and then opens a pull request against a config repository that contains only digests and values. Argo CD syncs the cluster from that repo. Three consequences I care about: the CI runner holds no production credential at all, so a compromised build cannot reach prod; the answer to 'what is running in production' is a `git log` rather than an archaeology exercise; and rollback is a `git revert`, which is the one operation every engineer already knows how to do at 3 a.m. The trade-off is that you now maintain a second repository and you must handle `ignoreDifferences` for anything the cluster owns — replicas under an HPA is the classic one."

### 5.6 Which scenario + which case, for each of the four shapes — summary matrix

| | Shape A · FE only | Shape B · BE only | Shape C · FE+BE | Shape D · polyglot |
|---|---|---|---|---|
| **S1 · CI only** | §3.1.1 / §3.2.2 / §3.3.2 | §3.1.2 / §3.2.1 / §3.3.1 | run both, no ordering needed | §3.1.3 (matrix + aggregator) |
| **S2 · CD Delivery** | §4.1.1 (env gate) | §4.1.1–4.1.3 | §4.1.1 + ⭐§4.1.4 skew | §5.2 `propose` PR, human merges |
| **S2 · CD Deployment** | §4.2.1 (canary is overkill for FE — see note) | §4.2.1 (full canary) | §4.2.1 + contract test | §5.2 with a bot merging |
| **S3 · CI+CD** | §5.2 / §5.3 / §5.4 | same | same + deploy-order rule | ⭐ §5.2 (GitOps) is the answer |
| Recommended target | T3 GitOps | T3 GitOps | T3 GitOps | T3 GitOps |
| Recommended strategy | ⭐ **recreate** or rolling (`maxSurge:1,maxUnavailable:0`) | **rolling**, or canary for `shop-api` | BE first, then FE (§4.1.4) | rolling per service, canary for `shop-api` |
| Special concern | browser cache (§4.1.4 nginx.conf) | JVM warmup + graceful shutdown (§6.6) | version skew | change detection + one release train |

⭐ **Note on the frontend and canaries.** A canary on a *static* frontend is nearly useless: the browser caches the bundle, so "5% of users" is not actually 5% of users, and a bad JS bundle is not detected by server-side error-rate analysis (the failure happens in the browser). For FE the effective guardrails are: **RUM (real-user monitoring) error rates**, a `window.onerror` beacon, and keeping the previous bundle files alive for one release. Canary the BE; instrument the FE.

---

## 6 · How the deploy actually happens — 5 mechanisms × 4 languages

### 6.1 The mechanisms, compared

| Mechanism | Command | Idempotent? | Knows history? | Rollback | Verdict |
|---|---|---|---|---|---|
| **`kubectl set image`** | `kubectl -n X set image deploy/svc svc=img@digest` | ✅ | ⭐ yes — `rollout history` keeps ReplicaSets | `kubectl rollout undo` | the simplest thing that works; great for CD steps |
| **`kubectl apply -f`** | `kubectl apply -f rendered.yaml` | ✅ | ⚠️ via `last-applied-configuration` annotation | revert the file and re-apply | ⭐ use with `--server-side` to avoid the 262 KB annotation limit |
| **Helm** | `helm upgrade --install r chart -f values.yaml --atomic --wait` | ✅ | ⭐⭐ `helm history` = release revisions | `helm rollback r <rev>` | the standard for anything with configuration |
| **Kustomize** | `kubectl apply -k overlays/prod` | ✅ | Git only | revert Git | ⭐ no templating language = no logic bugs in your YAML |
| **Argo CD** | `argocd app sync shop-production` | ✅ | ⭐⭐⭐ Git + sync history + drift detection | `git revert` | the production answer |

⭐⭐ **Helm vs Kustomize — the honest answer.** Helm gives you *parameters* (one chart, many environments, `values.yaml` per env) and hooks (pre-upgrade jobs, migrations). Kustomize gives you *patches* (a base plus per-environment diffs) with no templating language at all — which means nothing can be wrong except the YAML. Most mature shops use **both**: Helm chart as the base, Kustomize overlay for per-cluster differences. If you must pick one: Helm for a product with many customer environments; Kustomize for one product in three of your own environments.

```bash
# ⭐⭐ ALWAYS pass --atomic --wait --timeout with helm in a pipeline.
# ⚠️ bash gotcha: a `\` continuation must be the LAST character on the line.
#    `--atomic \   # comment` escapes the SPACE, not the newline — the command
#    silently ends there and the rest becomes garbage. Comments go on their
#    own lines, or (better) in a table under the command, as here.
helm upgrade --install shop-api deploy/chart \
  -n shop-production -f deploy/values/production.yaml \
  --set image.digest=$DIGEST \
  --atomic \
  --timeout 10m \
  --wait \
  --wait-for-jobs \
  --history-max 10
# ── what each flag is doing ────────────────────────────────────────────────
#  --atomic          roll back automatically if the release never becomes
#                    Ready. Without it a failed upgrade leaves the namespace
#                    half-migrated AND the pipeline exits 0.
#  --timeout 10m     how long --atomic/--wait will wait before giving up.
#  --wait            block until every resource reports Ready. Without it,
#                    helm returns the instant the API *accepts* the object —
#                    "deployed" while the pod is CrashLoopBackOff.
#  --wait-for-jobs   ⭐ ALSO wait for Jobs (migrations!) to COMPLETE.
#                    Without this, helm returns while Flyway is still running,
#                    the pipeline proceeds, and the new app starts against a
#                    half-migrated schema. ⛔ a classic production incident.
#  --history-max 10  ⭐ each history entry is a Secret holding the FULL
#                    manifest. On a busy service that is 10 large Secrets per
#                    release — watch your etcd size. Lower it to 5.
# ───────────────────────────────────────────────────────────────────────────
```

### 6.2 K8s rollout strategies — which one, per service

| Strategy | How | Downtime | Cost | Use for | ⛔ Not for |
|---|---|---|---|---|---|
| **Recreate** | kill all old, then start new | ⛔ yes, seconds | 1× | `shop-ui` (static, fast start), anything with an exclusive lock | any stateful API |
| **RollingUpdate** | `maxSurge`/`maxUnavailable` | ✅ none | ≤1.5× | ⭐ the default: `checkout`, `payment-mock`, `order-worker` | breaking API changes |
| **Blue/Green** | two full stacks, switch the Service selector | ✅ none, instant cutover | 2× | ⭐ `shop-api` major versions; anything you must be able to abandon instantly | expensive workloads, stateful DBs |
| **Canary** | a small % of real traffic, measure, then grow | ✅ none | 1.1× | ⭐⭐ `shop-api` — it has an SLO and enough traffic to measure | low-traffic services (no statistical signal) |
| **A/B** | route by header/user segment | ✅ none | 1.x× | product experiments | reliability-driven release |

```yaml
# ⭐⭐ THE ROLLING UPDATE TUNING that most teams never set — and it is why
#   their "zero-downtime" deploys drop requests.
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1              # create 1 EXTRA pod above the desired count
      maxUnavailable: 0        # ⭐⭐ NEVER allow an unavailable pod. With
                               #   maxUnavailable: 25% (the DEFAULT) and
                               #   replicas: 4, Kubernetes will terminate one
                               #   pod before its replacement is ready. That
                               #   is a dropped request, on every deploy.
  minReadySeconds: 15          # ⭐⭐ a pod must stay Ready for 15 s before
                               #   it counts as available. Without this, a
                               #   pod that passes readiness once and then
                               #   crashes 3 s later is still counted as
                               #   progress, and the rollout marches on
                               #   through a broken version.
  revisionHistoryLimit: 5      # ⭐ keep 5 old ReplicaSets → `rollout undo`
                               #   can go back 5 versions. Default is 10;
                               #   each is real objects in etcd.
  progressDeadlineSeconds: 600 # ⭐ after 10 min without progress the
                               #   Deployment reports `Progressing=False`.
                               #   `kubectl rollout status` uses this to
                               #   decide when to give up. Default is 600;
                               #   for a JVM with a slow start, raise it.
```

### 6.3 Blue/green by hand (no Argo) — the 12-line version

```bash
# ⭐⭐ Blue/green without a controller = deploy a NEW Deployment with a
#   different name, verify it, then flip the Service selector. Atomic cutover.
set -euo pipefail
SVC=shop-api; NS=shop-production
CURRENT=$(kubectl -n $NS get svc $SVC -o jsonpath='{.spec.selector.color}')   # blue
NEW=$([ "$CURRENT" = blue ] && echo green || echo blue)

# 1. deploy the new colour
helm upgrade --install "$SVC-$NEW" deploy/chart -n $NS \
  -f deploy/values/production.yaml \
  --set nameOverride="$SVC-$NEW" --set podLabels.color="$NEW" \
  --set image.digest="$DIGEST" --atomic --wait --timeout 10m

# 2. verify it WITHOUT any user traffic (port-forward, not the Service)
POD=$(kubectl -n $NS get pod -l app=$SVC,color=$NEW -o jsonpath='{.items[0].metadata.name}')
kubectl -n $NS port-forward "$POD" 18080:8080 &
PF=$!; sleep 3
curl -fsS http://localhost:18080/actuator/health | grep -q '"UP"'
./scripts/smoke.sh --direct http://localhost:18080
kill $PF

# 3. ⭐ THE FLIP. One atomic patch. This is the entire cutover.
kubectl -n $NS patch svc $SVC -p "{\"spec\":{\"selector\":{\"app\":\"$SVC\",\"color\":\"$NEW\"}}}"

# 4. verify through the real Service
./scripts/smoke.sh $NS $SVC

# 5. keep the old colour alive for 15 min (instant rollback), then scale down
echo "🔙 rollback = kubectl -n $NS patch svc $SVC -p '{\"spec\":{\"selector\":{\"color\":\"$CURRENT\"}}}'"
( sleep 900 && helm uninstall "$SVC-$CURRENT" -n $NS ) &
```

### 6.4 Argo Rollouts canary — the operator version

Already shown in §4.2.1. The commands you actually type:

```bash
kubectl argo rollouts get rollout shop-api -n shop-production --watch
# ⭐ the ASCII dashboard. This is the single best CD debugging view that
#   exists. It shows step, weight, replicas, and the analysis result live.

kubectl argo rollouts status  shop-api -n shop-production --watch   # exits non-zero on abort
kubectl argo rollouts promote shop-api -n shop-production           # skip the current pause
kubectl argo rollouts abort   shop-api -n shop-production           # ⭐ instant rollback
kubectl argo rollouts retry   rollout shop-api -n shop-production   # retry an aborted rollout
kubectl argo rollouts set image shop-api shop-api=ghcr.io/3558bhk/shop-api@sha256:… -n shop-production
kubectl argo rollouts undo    shop-api -n shop-production --to-revision 4
kubectl argo rollouts dashboard -n argo-rollouts --port 3100        # web UI

# ⭐⭐ TEST THE ROLLBACK ON PURPOSE. In staging:
#   1. deploy a version whose /ready returns 500 after 30 s
#   2. watch the canary analysis fail
#   3. confirm Argo aborts and traffic returns to stable BY ITSELF
#   If you have not seen this work, you do not have continuous deployment —
#   you have unattended deploys.
```

### 6.5 T1 — Docker-only deployment (no Kubernetes)

For the single-host / docker-compose shape from the Docker learning path. This is a legitimate CD target, and interviewers do ask about it.

```yaml
# The CD job for target T1 (Docker host, not Kubernetes)
  deploy-docker-host:
    runs-on: ubuntu-24.04
    environment: dev-vm
    steps:
      - uses: actions/checkout@v7
      - name: Deploy over SSH
        uses: appleboy/ssh-action@v1.0.3
        with:
          host: ${{ secrets.VM_HOST }}
          username: deploy
          key: ${{ secrets.VM_SSH_KEY }}          # ⛔ CI holds an SSH key to
          script_stop: true                       #   prod. This is exactly
          script: |                               #   what GitOps (T3) removes.
            set -euo pipefail
            cd /opt/shop
            # ⭐ pull by DIGEST, not by tag. `docker compose pull` with a
            #   `:latest` tag is how you deploy something unidentifiable.
            export SHOP_API_DIGEST='${{ needs.gate.outputs.digest }}'
            docker compose pull
            docker compose up -d --remove-orphans --wait
            # ⭐⭐ `--wait` blocks until every service reports healthy
            #   (it reads the HEALTHCHECK). Without it, compose returns the
            #   instant the containers are CREATED, and a CrashLooping app
            #   looks like a successful deploy.
            docker compose ps
            docker image prune -af --filter 'until=72h'   # ⭐ disk discipline:
                                                          #   a Docker host
                                                          #   fills up in weeks
```

```yaml
# docker-compose.prod.yaml — the T1 desired state
services:
  shop-api:
    image: ghcr.io/3558bhk/shop-api@${SHOP_API_DIGEST}   # ⭐ digest from env
    restart: unless-stopped
    env_file: [.env.prod]                 # ⛔ never commit this file
    ports: ['8080:8080']
    healthcheck:
      test: ['CMD', 'wget', '-qO-', 'http://localhost:8080/actuator/health']
      interval: 10s
      timeout: 3s
      retries: 5
      start_period: 40s                   # ⭐ JVM warmup. Omit → restart loop.
    deploy:
      resources:
        limits: { cpus: '1.0', memory: 1G }   # ⭐⭐ the JVM must see this.
                                              #   Use -XX:MaxRAMPercentage,
                                              #   never a hard -Xmx.
    logging:
      driver: json-file
      options: { max-size: '50m', max-file: '5' }   # ⭐ unbounded logs fill
                                                    #   the disk. Always set.
```

### 6.6 ⭐ Per-language deployment notes — the things that break only in prod

| | Java (`shop-api`) | Go (`checkout`, `payment-mock`) | Python (`order-worker`) | JS/nginx (`shop-ui`) |
|---|---|---|---|---|
| **Startup time** | 15–40 s (JVM + Spring context) | ⭐ <100 ms | 1–3 s | instant |
| **`start-period` / `initialDelaySeconds`** | ⭐ 40–60 s | 5 s | 10 s | 2 s |
| **Graceful shutdown** | ⭐⭐ `server.shutdown=graceful` + `spring.lifecycle.timeout-per-shutdown-phase=30s` | ⭐⭐ must handle `SIGTERM` yourself — Go does **nothing** by default | `signal.signal(SIGTERM, …)` + finish the current message | nginx: `worker_shutdown_timeout` |
| **SIGTERM default** | handled by Spring if configured | ⛔ **process dies immediately, in-flight requests dropped** | ⛔ default kills the process | handled |
| **Memory** | ⭐⭐ `-XX:MaxRAMPercentage=75`, never `-Xmx` in a container | tiny, static | moderate, watch for leaks | tiny |
| **Warmup** | ⭐⭐ JIT: p99 is 10× worse for the first 60 s → `minReadySeconds: 60` or a warmup probe | none | none (but imports are lazy) | none |
| **Readiness meaning** | "Spring context up AND DB pool reachable" | "listening AND dependencies reachable" | "connected to RabbitMQ" | "nginx serving index.html" |
| **Liveness meaning** | ⛔ **must NOT check the DB** — a DB outage would restart-loop every pod and turn an outage into a catastrophe | same | same | same |
| **Deploy strategy** | canary (has an SLO, has traffic) | rolling | ⭐ rolling, but drain the queue first | recreate or rolling |
| **Special trap** | OOMKilled because `-Xmx` > container limit | dropped requests because SIGTERM is unhandled | ⛔ a killed worker loses an unacked message → set `prefetch=1` and manual ack | ⛔ cached `index.html` → white screen |
| **Migration** | Flyway/Liquibase as a **Job with a helm hook**, `--wait-for-jobs` | golang-migrate as an init container ⛔ (runs per-pod!) → use a Job | Alembic as a Job | n/a |

```go
// ⭐⭐ Go graceful shutdown — the ~25 lines that make a rolling update
//   actually zero-downtime. Without this, EVERY deploy drops requests.
func main() {
    srv := &http.Server{Addr: ":9091", Handler: router()}

    // Serve in the background; main() blocks on signals.
    go func() {
        if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
            log.Fatalf("listen: %v", err)
        }
    }()

    // ⭐ Kubernetes sends SIGTERM, then waits terminationGracePeriodSeconds
    //   (default 30 s), then sends SIGKILL. Everything below must finish
    //   inside that window — so set the shutdown timeout BELOW it.
    quit := make(chan os.Signal, 1)
    signal.Notify(quit, syscall.SIGTERM, syscall.SIGINT)
    <-quit
    log.Println("SIGTERM received — draining")

    // ⭐⭐ there is a race Kubernetes creates: the pod is removed from the
    //   Service endpoints ASYNCHRONOUSLY from the SIGTERM delivery. For a
    //   few hundred ms, traffic still arrives at a pod that is shutting down.
    //   The standard mitigation is a small sleep before closing the listener.
    time.Sleep(5 * time.Second)

    ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
    defer cancel()
    // ⭐ Shutdown() stops accepting new connections and WAITS for in-flight
    //   requests to complete (up to the context deadline). This is the whole
    //   point of the exercise.
    if err := srv.Shutdown(ctx); err != nil {
        log.Printf("forced shutdown: %v", err)
    }
    log.Println("bye")
}
```

```yaml
# ⭐⭐ the matching Kubernetes lifecycle block
spec:
  terminationGracePeriodSeconds: 45      # ⭐ must be > the in-app shutdown
  containers:                            #   timeout (20 s) + the sleep (5 s)
    - name: checkout                     #   + margin. If it's too small,
      lifecycle:                         #   SIGKILL arrives mid-request.
        preStop:
          exec:
            command: ['sh', '-c', 'sleep 5']
            # ⭐⭐ a preStop sleep covers the endpoint-removal race even for
            #   an app that does NOT handle SIGTERM properly. Belt and braces:
            #   do both. This one line fixes most "we see 502s during deploys"
            #   reports.
      readinessProbe:
        httpGet: { path: /ready, port: 9091 }
        periodSeconds: 5
        failureThreshold: 2              # ⭐ remove from the pool FAST
      livenessProbe:
        httpGet: { path: /health, port: 9091 }
        periodSeconds: 10
        failureThreshold: 3              # ⭐ restart SLOWLY. A liveness probe
                                         #   that is too aggressive causes a
                                         #   restart storm during any slowdown.
```

---

## 7 · Rollback drills for every scenario

⭐⭐⭐ **A rollback you have never tested is not a rollback plan.** Run each of these at least once, in dev, and time it.

| # | Situation | Mechanism | Command | Time to recover |
|---|---|---|---|---|
| R1 | new pods never become Ready | Helm `--atomic` did it for you | *(automatic)* | ~0 s (never served) |
| R2 | bad version, must revert now | K8s rollout undo | `kubectl -n shop-production rollout undo deploy/shop-api` | 30–60 s |
| R3 | revert to a *specific* version | rollout undo --to-revision | `kubectl rollout history …` then `--to-revision=4` | 30–60 s |
| R4 | canary is bad, mid-rollout | Argo abort | `kubectl argo rollouts abort shop-api -n shop-production` | ⭐ <10 s (traffic was only 5%) |
| R5 | blue/green, new colour is bad | flip the selector back | `kubectl -n $NS patch svc $SVC -p '{"spec":{"selector":{"color":"blue"}}}'` | ⭐ <2 s |
| R6 | GitOps: config is wrong | `git revert` | `git revert HEAD && git push` → Argo syncs | 1–4 min (poll interval) |
| R7 | the rollback image itself is gone | ⛔ registry retention deleted it | **prevention:** immutable tags + a retention rule that never deletes signed digests | unrecoverable |
| R8 | the database migration is the problem | ⛔ **you cannot roll this back** | prevention: expand/contract migrations, always backwards-compatible | hours (restore) |

```bash
# ══ THE DRILL. Run this end to end once, and time it. ══════════════════
set -euo pipefail
NS=shop-staging; SVC=shop-api

echo "── 1. record the current state ──────────────────────────"
kubectl -n $NS get deploy $SVC -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
kubectl -n $NS rollout history deploy/$SVC

echo "── 2. deploy something deliberately broken ──────────────"
# ⭐ an image that exists but whose app crashes: this exercises the REAL
#   failure mode (CrashLoopBackOff), not a typo'd image name (ErrImagePull),
#   which is a much easier and much rarer failure.
kubectl -n $NS set image deploy/$SVC $SVC=ghcr.io/3558bhk/shop-api:sha-broken

echo "── 3. watch it fail (this is the part people skip) ──────"
kubectl -n $NS rollout status deploy/$SVC --timeout=120s || echo "⛔ rollout did not complete — expected"
kubectl -n $NS get pods -l app=$SVC
kubectl -n $NS describe pod -l app=$SVC | tail -30
kubectl -n $NS logs -l app=$SVC --tail=50 --prefix

echo "── 4. ROLL BACK and TIME IT ─────────────────────────────"
START=$(date +%s)
kubectl -n $NS rollout undo deploy/$SVC
kubectl -n $NS rollout status deploy/$SVC --timeout=300s
echo "✅ recovered in $(( $(date +%s) - START )) seconds"

echo "── 5. verify the OLD version is actually serving ────────"
kubectl -n $NS get deploy $SVC -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
kubectl -n $NS port-forward deploy/$SVC 18080:8080 & sleep 3
curl -fsS http://localhost:18080/actuator/health
kill %1

# ⭐⭐ 6. THE QUESTION THE DRILL ANSWERS:
#   how long between "we noticed" and "users were fine"? If that number is
#   more than 5 minutes, your rollback story is your biggest reliability gap
#   — bigger than any bug you will fix this quarter.
```

---

## 8 · Troubleshooting table

| Symptom | Where | Most likely cause | Fix |
|---|---|---|---|
| "Workflow dispatched but job skipped" | GitHub | `if:` on the job evaluated false, or the path filter didn't match | `gh run view --log` and check the `changes` job output |
| Required check never appears | GitHub | the job was **skipped** and a skipped job doesn't report a status | ⭐ add the aggregator job (§3.1.3 `ci-result`) and require THAT |
| Reusable workflow "invalid permissions" | GitHub | the caller's `permissions:` don't propagate | declare `permissions:` inside the called workflow |
| `docker/login-action` denied | GitHub | `packages: write` missing, or the GHCR package is private and unlinked to the repo | add the permission; GHCR → package settings → link the repo |
| Build is 8 min, mostly Maven downloads | all | no dependency cache, or the Dockerfile `COPY . .` before deps | `cache: maven`; reorder the Dockerfile (§3.1.2) |
| `npm ci` fails, `npm install` works | all | `package-lock.json` is out of sync with `package.json` | run `npm install` locally, **commit the lockfile** |
| Testcontainers "Could not find a valid Docker environment" | Jenkins-in-K8s | no Docker daemon in the agent pod | ⭐ use Kaniko for images and a real DB **service container** for tests, or `TESTCONTAINERS_HOST_OVERRIDE` with a DinD sidecar |
| Trivy prints 400 CVEs and the stage is green | Jenkins | no `--exit-code 1` | add it |
| Trivy fails on an unfixable glibc CVE | all | blocking on non-actionable findings | `--ignore-unfixed true` + a `.trivyignore` with a **ticket number and an expiry date** per line |
| `helm upgrade` succeeds but pods CrashLoop | all | no `--wait`; helm returned on API acceptance | `--atomic --wait --timeout` |
| Rolling update drops requests | K8s | `maxUnavailable: 25%` (the default) + no `preStop` sleep | `maxUnavailable: 0`, `minReadySeconds`, `preStop: sleep 5` (§6.6) |
| 502s only during deploys | K8s | endpoint removal races SIGTERM | ⭐ `preStop` sleep + graceful shutdown in the app |
| Java pod OOMKilled at exactly the limit | K8s | `-Xmx` set higher than the container limit; the JVM ignores the cgroup | remove `-Xmx`, use `-XX:MaxRAMPercentage=75` |
| Java pod restart-loops on startup | K8s | liveness `initialDelaySeconds` too low for a 30 s Spring boot | raise it; add a `startupProbe` instead ⭐ |
| FE shows a white screen after deploy | nginx | `index.html` was cached and references deleted bundles | `no-store` on `index.html`, immutable cache on `/assets/` (§4.1.4) |
| FE calls the old API and gets 400 | FE+BE | version skew during the rollout | deploy order + backwards-compatible APIs + contract test (§4.1.4) |
| Argo shows `OutOfSync` forever | Argo CD | the HPA owns `replicas`, Git says 6 | `ignoreDifferences` on `/spec/replicas` (§5.5) |
| Argo `ComparisonError: annotation too long` | Argo CD | the `last-applied-configuration` annotation on a big object | `ServerSideApply=true` in `syncOptions` |
| Jenkins `input` exhausted all executors | Jenkins | paused approvals hold executors | a dedicated `gate` agent, plus `timeout` on every `input` |
| Jenkins job works manually, fails on webhook | Jenkins | the webhook runs a **different** branch's Jenkinsfile | multibranch + `when { branch }`; never trust `Jenkinsfile` from a PR without a `trusted` check |
| Azure "variable is empty in the next stage" | ADO | missing `isOutput=true` on `##vso[task.setvariable]`, or no `$[ stageDependencies.… ]` | both are required (§4.1.2) |
| Azure deployment job has no source code | ADO | `deployment` jobs don't check out by default | add `- checkout: self` as the first step |
| Azure tests fail but the build is green | ADO | `failTaskOnFailedTests` defaults to false | set it to `true` |
| `kubectl` in CI works locally, fails in the runner | all | the kubeconfig secret has `server: https://127.0.0.1:6443` from kind | ⭐ kind kubeconfigs point at localhost. For CI you need a reachable API server, or run CI **inside** the cluster (Jenkins does this well) |
| cosign verify fails with "no signatures found" | all | the image was pushed by a different identity, or `--yes` wasn't passed at signing | sign with `cosign sign --yes`; verify with the exact `--certificate-identity-regexp` |

⭐ **The single most useful debugging habit:** when a pipeline fails and you cannot see why, run the failing command **by hand in a container on your laptop**:

```bash
docker run --rm -it -v "$PWD:/w" -w /w ubuntu:24.04 bash
# now install the tool and run the exact command. 90% of "CI is broken"
# is "the environment differs from what I assumed".
```

---

## 9 · Which scenario do I pick?

```
START
  │
  ├─ Is the change already built, tested and signed?
  │     NO ─────────────────────────────────────▶ SCENARIO 1 (CI). Full stop.
  │     │                                          Do not add deploy steps.
  │     YES
  │     │
  │     ├─ Does prod need a human decision?
  │     │    YES (regulated / freeze windows / small team / irreversible
  │     │         migrations / no canary analysis yet)
  │     │         └───────────────────────────▶ SCENARIO 2, CASE 1
  │     │                                        Continuous DELIVERY
  │     │
  │     │    NO — and ALL of these are true:
  │     │       ✅ deploys are one-commit-sized
  │     │       ✅ progressive delivery (canary) is in place
  │     │       ✅ automated analysis against real SLOs
  │     │       ✅ automatic rollback, DRILLED (you have seen it work)
  │     │       ✅ an error budget + change budget exist
  │     │       ✅ someone is on call
  │     │         └───────────────────────────▶ SCENARIO 2, CASE 2
  │     │                                        Continuous DEPLOYMENT
  │     │
  │     └─ ANY of those ❌ ───────────────────▶ stay on Case 1 and fix
  │                                              the missing one first
  │
  └─ Do you need the whole commit→prod path in one place?
        └──────────────────────────────────────▶ SCENARIO 3
                                                  shape 3b (artifact handoff)
                                                  or ⭐ shape 3c (GitOps)
```

**A realistic progression** — this is the order to actually build them in:

| Week | Build | Why this order |
|---|---|---|
| 1 | Scenario 1 for ONE service (`shop-api`), one tool | learn the tool without deployment risk |
| 2 | Scenario 1 for all five services (polyglot, change detection) | the matrix + aggregator pattern |
| 3 | Scenario 2 Case 1, target T2 (helm + `--atomic --wait`) | learn to deploy before you learn to deploy automatically |
| 4 | Scenario 2 Case 1, target T3 (GitOps + Argo) | ⭐ remove the cluster credential from CI |
| 5 | Scenario 3, shape 3c, all services | CI proposes, human merges, Argo syncs |
| 6 | Add canary analysis + auto-rollback; **run the rollback drill** | earn the right to Case 2 |
| 7 | Scenario 2 Case 2 for ONE low-risk service (`shop-ui`) | smallest blast radius first |
| 8 | Extend Case 2 to `checkout`/`payment-mock`, keep `shop-api` on Case 1 | risk-proportional automation |

⭐⭐ **That last row is the staff-level insight.** Mature organisations do not have "continuous deployment" as a global property. They have a *per-service* choice, proportional to that service's blast radius and its observability. Claiming blanket Continuous Deployment across a 200-service estate is usually a sign that the guardrails are theatre.

---

<a name="tasks--answers"></a>
## 10 · ⭐ TASKS AND ANSWERS

> **Everything below is practice.** Do the tasks first; the answers are underneath. Each answer includes the *why*, not just the *what*.

### 10.1 Coding / build tasks

| # | Task | Scenario | Tool |
|---|---|---|---|
| **T1** | Write a **CI-only** pipeline for `shop-api` that fails the build when a unit test fails, publishes the test report **even when tests fail**, and pushes an image tagged `sha-<gitsha>` **and** `main`. Prove it goes red by breaking a test. | 1 | your choice |
| **T2** | Extend T1 to the **polyglot monorepo**: only the services whose files changed are built, all in parallel, and a single aggregator job is the required status check. | 1 | GitHub Actions |
| **T3** | Write a **CD-only** pipeline that takes a digest as an input, renders the manifests, validates them with `kubeconform -strict`, deploys to `shop-dev` with `--atomic --wait`, and runs a smoke test. It must contain **no build step and no source-code test**. | 2 | any |
| **T4** | Add the **human gate** to T3 for production. Capture *who* approved and *which ticket*, refuse self-approval, and refuse an empty ticket. Write the audit line. | 2 · Case 1 | Jenkins or Azure |
| **T5** | Replace the human gate in T3 with **four automated gates**: signature verification, freeze-window check, error-budget check, change-budget check. Deploy via an Argo Rollouts canary with a Prometheus `AnalysisTemplate`. | 2 · Case 2 | GitHub Actions |
| **T6** | Implement the **FE+BE version-skew defences**: the `nginx.conf` cache rules, a consumer-driven contract test in staging, and a deploy-order rule encoded in the pipeline. | 2/3 · shape C | any |
| **T7** | Build **Scenario 3, shape 3c**: CI opens a PR on `shop-config` bumping only the changed services' digests; Argo CD syncs; verify that CI holds **no** cluster credential. | 3 | GitHub Actions |
| **T8** | Run the **rollback drill** (§7) end to end in `shop-staging` and record the recovery time. Then make it 2× faster. | all | any |
| **T9** | Add **Go graceful shutdown** + the `preStop` sleep to `checkout`, then prove a rolling update drops **zero** requests by running a load generator during the deploy. | 3 · shape B | any |
| **T10** | Audit your own pipeline against the §3.5 checklist. Fix every failure. | 1 | all |

### 10.2 "What happens?" — reason before you read the answer

| # | Question |
|---|---|
| **Q1** | A GitHub Actions matrix has `fail-fast` at its default. One of five services fails to compile. What happens to the other four? |
| **Q2** | Your branch protection requires the check named `build (shop-api)`. A PR changes only `apps/checkout/**`. Can it merge? |
| **Q3** | You run `helm upgrade --wait` and it succeeds. Are the pods serving traffic? |
| **Q4** | A Deployment has `replicas: 4` and default rolling-update settings. How many pods can be unavailable during an update? |
| **Q5** | Your Go service handles SIGTERM with a graceful `srv.Shutdown(ctx)`. Deploys still produce 502s. Why? |
| **Q6** | Argo CD reports `OutOfSync` immediately after a successful sync, forever, on a Deployment with an HPA. Why? |
| **Q7** | A CI-only pipeline has no `kubectl` anywhere. Is production safe from it? |
| **Q8** | You promote `shop-ui` and `shop-api` in one release. The BE removes a field the FE reads. Which must deploy first for this to be safe? |
| **Q9** | Jenkins' `input` step is waiting for approval. What resource is it consuming while it waits? |
| **Q10** | An Azure DevOps `deployment` job runs `helm upgrade` from `deploy/chart`. It fails: "path not found". Why? |
| **Q11** | Trivy reports 214 CVEs in your Java runtime image; 0 have a fix available. Should the build fail? |
| **Q12** | You deploy by digest. Someone re-pushes the `main` tag five minutes later. What is running in prod? |

### 10.3 Interview questions

| # | Question |
|---|---|
| **I1** | What is the difference between Continuous Delivery and Continuous Deployment? Give me a company where each is correct. |
| **I2** | Design CI/CD for a monorepo with a React frontend, a Java backend and two Go services. What is built when, and how do you avoid rebuilding everything? |
| **I3** | How do you deploy a frontend and a backend that must stay compatible, with zero downtime? |
| **I4** | Your pipeline deploys to prod and you discover a bug 20 minutes later. Walk me through the rollback. Now tell me how you would have made that faster. |
| **I5** | What is GitOps, and what does it buy you over a pipeline that runs `helm upgrade`? What does it cost you? |
| **I6** | How do you prevent a compromised CI runner from deploying to production? |
| **I7** | When is a canary meaningless? |
| **I8** | Your builds take 25 minutes. Nobody waits for them; they merge anyway. Fix it. |

---

### ✅ ANSWERS

#### T1 — CI-only for `shop-api`

The complete file is §3.1.2. The four requirements map to:

| Requirement | Where it is satisfied | The line that does it |
|---|---|---|
| fails on a test failure | the `build-and-test` job | `./mvnw … verify` — Maven returns non-zero, the step fails, the job fails. ⛔ No `\|\| true`, no `continue-on-error` |
| publishes the report **on failure** | the `Publish test report` step | ⭐ `if: always()`. Without it the default `success()` means you get the report exactly when you don't need it |
| two tags | `docker/metadata-action@v5` | `type=sha,prefix=sha-,format=long` (immutable) + `type=ref,event=branch` (mutable) |
| proof it goes red | manual | break a test, push to a branch, confirm red, then `git revert` |

**Why the proof matters:** an untested gate is not a gate. ⭐ Do this once for every pipeline you ever create, and re-do it after any change to the test command.

#### T2 — polyglot change detection

Complete file: §3.1.3. The three moving parts:

1. **`dorny/paths-filter`** computes booleans/JSON for path sets. GitHub's own `on.push.paths` is a *workflow* filter (all or nothing); `paths-filter` is a *job* filter (per service). ⭐ You need the latter for a monorepo.
2. **`if: needs.changes.outputs.X == 'true'`** on each build job → the job is `skipped`, which costs zero minutes.
3. **The aggregator `ci-result` with `if: always()`** → ⭐⭐ this is the answer to Q2. A skipped job satisfies a required status check, so requiring individual jobs lets a Go-only change merge without Java ever compiling. Require the aggregator, which treats `skipped` as fine and `failure`/`cancelled` as fatal.

#### T3 — CD-only, no build

§4.1.1 jobs `resolve` → `render` → `deploy-dev`. The properties that make it genuinely CD-only:

- `on: workflow_dispatch` / `repository_dispatch` / `resources.pipelines` — **never `push`**
- the input is a **digest**, resolved from a tag at the very first step so it cannot change underneath you
- a separate **render** job (`helm template` + `kubeconform -strict`) catches YAML errors in 2 s without cluster access
- `helm upgrade --atomic --wait --timeout` so "succeeded" means *ready*, not *accepted*
- ⭐ `kubeconform -strict` rejects **unknown fields**. Without `-strict`, `replicaCount: 6` (a Helm value typo'd into a manifest) is silently ignored and you deploy 1 replica with a green pipeline.

#### T4 — the human gate

| Tool | Gate mechanism | Captures the approver? | Audit |
|---|---|---|---|
| GitHub Actions | `environment: production` + **Required reviewers** in repo settings | ⭐ partially — visible in the run's deployment log, not as a variable | Environments → deployment history |
| Azure DevOps | Environment → **Approvals and checks**, or `ManualValidation@1` in YAML | ✅ `onTimeout: reject`, `notifyUsers` | ⭐⭐ Release → Deployments view (best) |
| Jenkins | `input` with `submitterParameter: 'APPROVED_BY'` | ✅ into a variable you control | write it yourself (§4.1.3) |

**Refusing self-approval** (§4.1.3): compare `APPROVED_BY` against the user who started the build (`currentBuild.getBuildCauses('UserIdCause')?.userId`). In GitHub/Azure use the "prevent self-review" environment setting.

**Refusing an empty ticket:** validate *inside* the gate step and call `error()`. ⭐ A gate that accepts any click is theatre — the validation is what makes it a control.

**The audit line:** `timestamp | env | service | digest | approver | ticket | build URL`. Append it to a file, archive it as an artifact, and ship it to your log store. During an incident review this is the only record that answers "who put this in prod and why".

#### T5 — the four automated gates + canary

§4.2.1. The mapping from human judgement to machine check:

| Gate | What it replaces | Implementation |
|---|---|---|
| 1 · signature | "is this artifact from our CI?" | `cosign verify` with `--certificate-identity-regexp` pinned to *your repo, your workflow, the main branch* |
| 2 · freeze window | "is now a bad time?" | a calendar/change-management API; fail the job if frozen |
| 3 · error budget | "have we earned the right to take more risk?" | Prometheus: burn rate over 28 d vs the SLO |
| 4 · change budget | "is this rate of change itself abnormal?" | count today's successful prod runs; fail above N |

**Canary analysis:** the `Rollout` walks 5 → 25 → 50 → 100 % with an `AnalysisTemplate` querying Prometheus for success rate and p99. On failure the **controller** scales the canary to zero — the pipeline's `if: failure()` handler only has to `abort`, verify, and page.

⭐⭐⭐ **The most important part of T5 is testing it.** Deploy an image whose `/ready` starts returning 500 after 30 s, and watch the analysis fail and traffic return to stable with no human action. Until you have seen that, you have configured a canary, not earned one.

⚠️ **Two analysis traps:**
- **Too little traffic.** 5 % of 3 requests/minute is not a signal. For low-traffic services, use a *time-based* soak plus synthetic probes instead of ratio-based analysis.
- **The wrong query.** If the PromQL is subtly wrong (missing a label, wrong window), the analysis passes forever. Run the query by hand against a deliberately broken app **before** you trust it.

#### T6 — FE+BE version skew

Four defences, all in §4.1.4:

1. **Backwards-compatible APIs only** — add, never remove/rename. Deprecate → wait a release → remove. ⭐ This is the only *fix*; the rest are mitigations.
2. **`nginx.conf`** — `no-store` on `index.html`, `max-age=31536000, immutable` on `/assets/`. Without the first rule, a cached entry point references bundles you deleted → white screen.
3. **Contract test in staging** — the FE (consumer) publishes what it needs; verify against the backend **currently in production**, not the new one. If it fails, the new FE cannot talk to today's prod BE.
4. **Deploy order** — BE-adds → deploy BE first. BE-removes → deploy FE first. Both-change → make it two releases.

⭐ **Encoding the order in the pipeline:** two `deployment` jobs with `dependsOn`, and a `when`/`if` that selects the order based on the change type. Better: make it impossible to get wrong by *never* shipping a breaking change in one release at all — that is a design constraint, not a pipeline feature.

#### T7 — Scenario 3 shape 3c (GitOps)

§5.2. The three properties to verify:

```bash
# 1. CI holds NO cluster credential
gh secret list --repo 3558Bhk/shop          # ⭐ no KUBECONFIG_* at all
gh variable list --repo 3558Bhk/shop

# 2. CI's only write access is to the config repo
#    the token used in `propose` needs: contents:read on app repo,
#    pull-requests:write + contents:write on shop-config. Nothing else.

# 3. the cluster pulls
kubectl -n argocd get app shop-production \
  -o jsonpath='{.spec.source.repoURL}{"\n"}{.spec.syncPolicy.automated}{"\n"}'
# ✅ repoURL points at shop-config; automated.prune + selfHeal are true
```

**Why this is worth the extra repo:** the CI runner is the most attacker-reachable component in your estate — it executes code from every pull request. Giving it *no* production credential removes an entire class of incident. The cost is a second repository and the `ignoreDifferences` dance for cluster-owned fields (`/spec/replicas` under an HPA is the one that bites everyone).

#### T8 — the rollback drill

§7 has the script. Expected results and the follow-up:

| Step | What you should see | If you don't |
|---|---|---|
| deploy broken image | `rollout status` times out; pods in `CrashLoopBackOff` | you deployed a typo'd tag → that's `ErrImagePullBackOff`, a different (easier) failure. Use a real crashing image |
| `rollout undo` | old ReplicaSet scales back up; `rollout status` succeeds | `revisionHistoryLimit` is 0 → there is nothing to undo |
| timing | ⭐ **30–60 s** for a Go service, **60–120 s** for Spring Boot (JVM start) | if it's >5 min, your image is too big or your probes are wrong |

**How to make it 2× faster:**
1. **Blue/green or canary instead of rolling** — the old version is *already running*, so recovery is a selector flip (<2 s) or an `argo rollouts abort` (<10 s), not a fresh pod start.
2. **Shrink the image** — a JRE base instead of a JDK, `jlink` a custom runtime, multi-stage everything. Pull time dominates recovery time on cold nodes.
3. **Pre-pull** with a DaemonSet or `imagePullPolicy: IfNotPresent` + a pinned digest already on the node.
4. **Detect faster** — the biggest win is usually not the rollback, it's the *time to notice*. Canary analysis at 5 % traffic detects in ~3 min; user reports detect in ~30.

#### T9 — Go graceful shutdown, zero dropped requests

The code is §6.6. The proof:

```bash
# ⭐ a load generator running THROUGH the deploy. If any request fails,
#   your zero-downtime claim is false.
( while true; do
    curl -s -o /dev/null -w '%{http_code}\n' http://localhost:9091/health
    sleep 0.1
  done ) > codes.txt &
LOAD=$!

kubectl -n shop-staging set image deploy/checkout checkout=ghcr.io/3558bhk/checkout:sha-new
kubectl -n shop-staging rollout status deploy/checkout --timeout=300s

sleep 5; kill $LOAD
sort codes.txt | uniq -c
# ✅ EXPECTED:  3000 200        (all 200s)
# ⛔ IF YOU SEE: 2987 200 / 13 502  → requests were dropped.
```

**The two fixes if you see 502s, in order:**
1. `lifecycle.preStop.exec.command: ['sh','-c','sleep 5']` — covers the endpoint-removal race for *any* app, even one that ignores SIGTERM. ⭐ Do this first; it is one line.
2. Handle SIGTERM in the app and call `srv.Shutdown(ctx)` — required for in-flight requests to *complete* rather than merely not-start.
3. `terminationGracePeriodSeconds` > (preStop sleep + shutdown timeout), or SIGKILL arrives mid-request.
4. `maxUnavailable: 0` — otherwise Kubernetes terminates a pod before its replacement is Ready, which drops requests no matter how graceful your app is.

#### T10 — the audit

Run §3.5's grep and checklist. The three failures almost everyone finds:

| Finding | Why it happens | Fix |
|---|---|---|
| A `kubectl` in a CI file | "just to check it deploys" | move it to an ephemeral smoke job inside CI (§3.6) or delete it |
| Base images pinned by tag, not digest | `FROM node:22` is easier | `FROM node:22@sha256:…` + a Renovate/Dependabot rule that bumps digests |
| The scan has no `--exit-code 1` | it was noisy, so someone softened it | restore the exit code, then add `--ignore-unfixed` and a `.trivyignore` **with a ticket and expiry per line** |

---

#### Q1 — matrix `fail-fast`
**The other four are CANCELLED.** `fail-fast` defaults to `true`, which means the first failure aborts its siblings. ⛔ For CI you almost always want `fail-fast: false`: you want to know about *all* five broken services in one run, not discover them one push at a time. (`parallelsAlwaysFailFast()` in Jenkins is the opposite default — it aborts siblings, and you set it deliberately.)

#### Q2 — a skipped required check
**Yes, it can merge — and that is the bug.** A job that never runs reports no status; GitHub treats a required check satisfied by a job that was skipped as passing (the check simply isn't reported as failed). So a Go-only change merges without the Java build ever executing. ⭐ **Fix:** require a single aggregator job that runs `if: always()`, reads every `needs.*.result`, accepts `skipped`, and fails on `failure`/`cancelled` (§3.1.3).

#### Q3 — `helm --wait` succeeded
**Probably, but not certainly.** `--wait` blocks until resources are `Ready`, and `Ready` is defined by *your readiness probe*. If the probe is trivial (`tcpSocket` on the port) the pod can be Ready while the app is broken. ⭐ `--wait` proves the cluster thinks it's healthy; the **smoke test** proves it is. Also note: `--wait` does **not** wait for Jobs unless you add `--wait-for-jobs` — so a Flyway migration can still be running when helm returns.

#### Q4 — default `maxUnavailable`
**One.** The default is `maxUnavailable: 25%`, and Kubernetes **rounds down**: 25 % of 4 = 1. (With `replicas: 3`, 25 % rounds down to 0 — so small deployments are accidentally safe and large ones are not.) Default `maxSurge` is also 25 %, rounded **up**. ⭐ Set `maxUnavailable: 0` explicitly and let `maxSurge: 1` carry the rollout — it costs one extra pod and eliminates a whole class of dropped requests.

#### Q5 — graceful Go, still 502s
**The endpoint-removal race.** Kubernetes does two things when a pod terminates: (a) send SIGTERM to the container, and (b) remove the pod from the Service's Endpoints/EndpointSlice. These happen **concurrently, not in order**. Propagating (b) to every kube-proxy and every ingress controller takes tens to hundreds of milliseconds — during which new requests still arrive at a pod that has already stopped accepting them. ⭐ **Fix:** `lifecycle.preStop.exec: sleep 5`. The sleep happens *before* SIGTERM, so the pod stays fully functional while the endpoint removal propagates. Add `maxUnavailable: 0` and check that your ingress honours readiness.

#### Q6 — permanent `OutOfSync` with an HPA
**Git and the cluster disagree about a field the cluster owns.** Git says `replicas: 6`; the HPA scaled to 11. Argo sees drift, syncs back to 6, the HPA scales to 11, forever. ⭐ **Fix:** `ignoreDifferences` on `/spec/replicas` for Deployments (and Rollouts). The general principle: **anything a controller owns must be excluded from Git, or Git must not specify it at all** — omit `replicas` from the chart entirely when an HPA exists. Same class of problem: `status`, `resourceVersion`, and anything a mutating admission webhook injects (sidecars!).

#### Q7 — CI with no `kubectl`: is prod safe?
**Not necessarily.** Absence of a command is not absence of capability. Check *credentials*, not commands:
- Can the CI runner read a secret that is a kubeconfig, a cloud role, or a registry credential with **write** access to a tag prod pulls? Then it can deploy.
- Does CI push to a tag that CD deploys *automatically* (e.g. `:latest`, or `:main` with a Case 2 trigger)? Then CI **is** deploying, by proxy. ⭐ This is the most common accidental Continuous Deployment in existence.
- Can a pull request from a fork trigger the workflow with `pull-requests: write` or `id-token: write`? Then an outsider can mint an attestation for arbitrary code.

**The real control:** CI may write **immutable, signed** artifacts only; CD resolves by **digest**; prod only accepts images whose signature matches a pinned CI identity; and (best) the cluster **pulls** from Git, so no CI credential can reach it at all.

#### Q8 — the BE removes a field
**Neither order is safe — the change itself is wrong.** If the FE reads a field and the BE removes it, then: FE-first means old-FE + new-BE is never a state (good) but new-FE + old-BE *is* a state during the FE rollout… and BE-first means new-BE + old-FE breaks immediately, and old FE lives on in browser caches for **hours**. ⭐ **The correct answer is expand/contract:** (1) release BE that still emits the field *and* the replacement; (2) release FE that reads only the replacement; (3) after the old FE is provably gone (check RUM for bundle versions), release BE that removes the field. Three reversible releases instead of one irreversible one. Say this in the interview and then say: "and the reason browsers make this harder than services is that you cannot roll back a client."

#### Q9 — what Jenkins `input` consumes
**An executor.** A paused `input` step holds its agent's executor slot for the entire wait — hours or days. Twenty pending approvals on a controller with 20 executors and the whole Jenkins is frozen: no builds, no CD, nothing. ⭐ **Mitigations:** always wrap `input` in `timeout(...)`; put gates on a dedicated cheap agent label with many executors; or move approvals *out* of Jenkins entirely (Azure Environments and GitHub Environments hold no compute while waiting — an agentless `pool: server` job in Azure costs nothing). This is a genuine architectural advantage of the SaaS tools and a real Jenkins ops burden.

#### Q10 — the Azure deployment job can't find the chart
**`deployment` jobs do not check out source by default.** A regular `job` gets an implicit checkout; a `deployment` job (which is about deploying *artifacts*, not source) does not. ⭐ Add `- checkout: self` as the first step. Second-most-common variant: you did check out, but `chartPath` is relative to a different working directory than you assumed — use `$(System.DefaultWorkingDirectory)/deploy/chart`.

#### Q11 — 214 unfixable CVEs
**No — the build should not fail, but the CVEs must not be silently ignored either.** `--ignore-unfixed true` is correct: you cannot act on a finding with no patch, and blocking on it produces a permanently red pipeline, which produces a team that stops reading it, which is worse than the CVE. ⭐⭐ **But** pair it with (a) `.trivyignore` entries that each carry a **ticket number and an expiry date**, (b) a recurring job that re-checks expired ignores, and (c) a compensating control for the actual risk — a distroless or JRE-only base, a read-only root filesystem, no network egress, and a short rebuild cadence so you pick up the patch the day it lands. The interview answer is not "ignore them"; it's "**make them someone's problem with a deadline**."

#### Q12 — deploying by digest, `main` re-pushed
**The digest you deployed.** That is the entire point. `image@sha256:9f2c…` is content-addressed and immutable — re-pushing the tag `main` creates a *different* digest, and your running pods are unaffected. ⭐ Two corollaries worth saying: (1) the *tag* is a pointer that can move, so **resolve tag → digest at the start of CD** and use the digest everywhere downstream — otherwise a slow pipeline can deploy a different artifact than the one it verified; (2) your registry **retention policy** becomes a availability control — if it garbage-collects the digest you might need for a rollback, your rollback plan is fictional. Never delete a signed digest.

---

#### I1 — Delivery vs Deployment
> "Continuous **Delivery** means every change that passes CI is automatically in a production-*ready* state and could be released at the push of a button — but a human pushes it. Continuous **Deployment** means the button is pushed by the machine. The difference is one gate, but the difference in *prerequisites* is enormous: to remove the human you have to replace everything they were checking with an automated equivalent — signature verification, freeze windows, error budget, canary analysis against real SLOs, and a rollback that is automatic and has actually been drilled.
>
> For a company: a **payments or healthcare** firm is correctly on Continuous Delivery — the human approval is a *compliance control*, not a technical one, and an auditor needs to see it. A **consumer product** with an SRE org, error budgets and progressive delivery is correctly on Continuous Deployment, because there the limiting factor is how fast you can learn, and a batch of forty commits teaches you almost nothing about which one broke it.
>
> And the honest caveat: most teams that say they do Continuous Deployment are actually doing 'automatic deploy to dev plus manual prod'. I'd want to see the auto-rollback fire in staging before I believed it."

#### I2 — the polyglot monorepo
> "Four pieces.
>
> **One:** a cheap `changes` job that computes which services were touched — `dorny/paths-filter` on GitHub, `trigger.paths` plus `changeset` on Azure and Jenkins. That's the whole trick to not rebuilding everything; a Go-only commit must not spend four minutes on `npm ci`.
>
> **Two:** a matrix over the changed services, with `fail-fast: false` so one broken service doesn't hide the other four's results. Per-language setup comes from `include:` entries or a shared template / shared library — exactly **one** definition of 'how we build Java', reused by every pipeline.
>
> **Three:** ⭐ an aggregator job with `if: always()` that reads every `needs.*.result`, treats `skipped` as fine and `failure` as fatal, and is the **only** required status check. Without it, a skipped job silently satisfies branch protection and a Go-only change merges without Java compiling.
>
> **Four:** the handoff. CI outputs **digests**, not tags, and never touches a cluster. It opens a PR against a config repo; CD — or Argo — takes it from there. That keeps the credential boundary aligned with the trust boundary: the thing that runs untrusted PR code cannot reach production."

#### I3 — FE + BE compatibility, zero downtime
> "First, the uncomfortable truth: **you cannot deploy a frontend atomically.** Browsers hold your old JS in cache for hours and you cannot roll them back. So the answer is mostly a *design* constraint, not a pipeline trick.
>
> The API changes are backwards-compatible only: add fields, never remove or rename; when you must remove, use expand/contract over three releases. Deploy order follows the change: if the BE adds something the FE reads, BE first; if the BE removes something, FE first.
>
> Mechanically, three things. `nginx` serves `index.html` with `no-store` and hashed `/assets/` with `max-age=31536000, immutable` — that guarantees the entry point is always revalidated, so nobody is permanently stuck on old JS, while the bundles stay fast. A **consumer-driven contract test** in staging verifies the new FE against the backend *currently in production* — if it fails, you must ship the BE first. And the BE rolls out with `maxUnavailable: 0`, `minReadySeconds`, graceful shutdown and a `preStop` sleep, because the endpoint-removal race drops requests even in a perfectly written app.
>
> The residual risk — a long-lived tab running old JS against a new API — is handled by a runtime version check that prompts a reload. I'd rather have a prompt than a white screen."

#### I4 — the 20-minutes-later bug
> "First, **stop the bleeding, then investigate.** If it was a canary, `kubectl argo rollouts abort` — under ten seconds, and only a fraction of users ever saw it. If it was blue/green, flip the Service selector back — two seconds, because the old version is still running. If it was a plain rolling update, `kubectl rollout undo`, which is 30–60 s for a Go service and up to two minutes for Spring Boot because of JVM start.
>
> Then I verify the rollback actually took: the running digest, a smoke test through the real Service, and the golden signals returning to baseline. Only then do I look at *why*.
>
> How I'd make it faster — and this is the more interesting half:
> **Detect faster.** Twenty minutes means a human noticed, which means my analysis is not automated. A canary with a Prometheus `AnalysisTemplate` on error rate and p99 catches it in about three minutes at 5 % traffic, before most users see it.
> **Recover faster.** Rolling update recovery is dominated by starting a new pod. Blue/green or canary keeps the old version warm, so recovery is a pointer flip instead of a cold start.
> **Make it reversible by construction.** If the bug involved a schema change, no rollback helps — that's why migrations are expand/contract and backwards-compatible for at least one release.
> **And drill it.** A rollback nobody has executed is a hypothesis. I run the drill in staging quarterly and time it; the number goes in the runbook."

#### I5 — GitOps vs `helm upgrade` from CI
> "Three things it buys. **Credential separation:** CI holds no production credential at all — it opens a pull request. The CI runner is the most attacker-reachable thing in your estate because it executes code from every pull request, so removing its ability to touch prod eliminates a whole class of incident. **Answerability:** 'what is running in production' becomes `git log` instead of an archaeology exercise across three tools. **Uniform recovery:** rollback is `git revert`, the one operation every engineer already knows at 3 a.m., and it works identically for every service and every team.
>
> What it costs: a second repository to maintain and review; a controller (Argo CD) that is now production infrastructure you must operate, upgrade and monitor; a sync delay unless you wire the webhook; and you must handle **cluster-owned fields** — `ignoreDifferences` on `/spec/replicas` under an HPA, or Argo and the HPA fight forever. Also: GitOps makes the config repo a high-value target, so its `CODEOWNERS`, branch protection and review rules *are* your deployment permissions, and they need the same rigour you'd give prod credentials."

#### I6 — the compromised runner
> "Assume the runner is already compromised and design so that it doesn't matter. Concretely:
> The runner has **no cluster credential** — GitOps, so the cluster pulls from Git. It has registry **write** access only, and prod images must additionally carry a **cosign signature** whose certificate identity is pinned to a specific repo, workflow and branch — verified by **Kyverno** admission control in the cluster, not by the pipeline. So even a perfectly forged push is refused at the API server.
> Cloud auth is **federated** (GitHub OIDC, Azure Workload Identity) — a short-lived, audience-scoped token, not a stored secret that can be exfiltrated and reused.
> `permissions:` is `contents: read` at the workflow level and widened **per job**; `pull_request_target` is banned because it runs base-repo code with write tokens against fork input.
> Fork PRs cannot reach any job that holds a secret — which in Jenkins means folder-scoped credentials, never global ones, because a global credential is visible to a fork's `Jenkinsfile`.
> And the config repo requires a **human review** for the production path, with `CODEOWNERS` that the CI identity is not part of. The last line of defence is not technical: it's that merging to prod config is a permission CI does not have."

#### I7 — when a canary is meaningless
> "Four cases.
> **No traffic.** 5 % of three requests a minute is not a statistical signal; you'll promote on noise. Use a time-based soak plus synthetic probes instead.
> **Slow-burn failures.** A canary window of five minutes cannot see a memory leak that OOMs at hour six, a connection-pool exhaustion under sustained load, or a cron job that runs at 02:00. Canaries catch *fast* regressions only.
> **Client-side failures.** ⭐ This is the big one for a frontend: the error happens in the browser, so server-side success-rate analysis is blind to it. And because of caching, '5 % of users' isn't 5 % of users at all. For FE the real guardrail is RUM error rates and an `window.onerror` beacon — canary the backend, instrument the frontend.
> **Shared-state changes.** If the release mutates a database schema, a cache format or a message contract, the canary and stable versions are not independent — the canary has already changed the world the stable version depends on. That's why migrations must be expand/contract: to make the two versions genuinely coexistable."

#### I8 — 25-minute builds nobody waits for
> "The problem isn't the duration, it's that **feedback arrives after the decision**. Nobody waits, so the pipeline isn't a gate, it's a post-mortem. Two tracks, in this order.
>
> **Make the fast path fast — target under five minutes on a PR.** Split by concern: compile + unit tests + lint on the PR; integration tests, e2e, image build, scanning and signing on merge to `main`. Add change detection so a Go-only PR doesn't run `npm ci`. Fix caching — Maven `~/.m2`, npm, Go build cache, and BuildKit `type=gha` layer cache with a per-service scope. Parallelise: the four services are independent jobs, not sequential stages. And put the cheapest failures first, so a syntax error costs 40 seconds, not 20 minutes.
>
> **Make the slow path not matter.** `concurrency` with `cancel-in-progress` on PRs so three pushes in a minute cost one run, not three. A merge queue so merges are serialised and tested against the real main. And a **tiered gate**: the required check is the five-minute job; the 25-minute suite runs on merge and, if it fails, an automatic revert fires. That way the slow tests still protect main — through *reversal* rather than *prevention* — and developers are never blocked by them.
>
> The measure I'd watch is not build duration, it's **time-to-feedback-on-a-broken-commit**. If a bad commit is reverted automatically within ten minutes, a 25-minute suite is fine. If it sits on main until someone notices, a five-minute suite is not."

---

## Related files

| File | Why you'd go there from here |
|---|---|
| [README.md](./README.md) | the index of this folder |
| [00-ONE-DAY-MASTER-PLAN.md](./00-ONE-DAY-MASTER-PLAN.md) | the hour-by-hour plan; this file is the "day 4+" material |
| [01-CICD-GUIDE.md](./01-CICD-GUIDE.md) | ⭐ read this first if any term in §1 was unfamiliar |
| [02-CASE-1-azure-devops.md](./02-CASE-1-azure-devops.md) | full Azure DevOps depth: service connections, Key Vault, WIF, self-hosted agents |
| [03-CASE-2-github-actions.md](./03-CASE-2-github-actions.md) | full GitHub Actions depth: OIDC, reusable workflows, composite actions, caching |
| [04-CASE-3-jenkins.md](./04-CASE-3-jenkins.md) | full Jenkins depth: K8s install, JCasC, shared libraries, plugin security |
| [05-CAPSTONE-END-TO-END.md](./05-CAPSTONE-END-TO-END.md) | ⭐ the GitOps shape 3c built end to end, with Argo CD, Rollouts, Kyverno and cosign |
| [06-CHEATSHEET.md](./06-CHEATSHEET.md) | the one-page reference for all three tools |
| [../docker-learning-path/](../docker-learning-path/) | where the apps and Dockerfiles came from (target **T1**) |
| [../kubernetes-learning-path/](../kubernetes-learning-path/) | where the manifests, probes and rollout behaviour came from (target **T2**) |
| [../monitoring-alerting-learning-path/](../monitoring-alerting-learning-path/) | ⭐ the Prometheus queries and SLOs that make Case 2's analysis real |

### Version anchors used in this file

| Thing | Version | Note |
|---|---|---|
| Jenkins LTS | **2.568.3** | Java **21** minimum since 2.555.1 |
| GitHub Actions | `actions/checkout@v7`, `setup-java@v5`, `setup-node@v4`, `upload/download-artifact@v4` | `ubuntu-latest` = Ubuntu 24.04 → ⭐ pin `ubuntu-24.04` |
| Azure DevOps | `Docker@2`, `HelmDeploy@0`, `PublishTestResults@2`, `ManualValidation@1`, `Cache@2`, `DownloadPipelineArtifact@2` | `deployment` jobs need an explicit `checkout: self` |
| Helm | **3.16.x** | `--atomic`, `--wait`, `--wait-for-jobs`, `--history-max` |
| Argo CD | **3.x** | `syncOptions: ServerSideApply`, `ignoreDifferences` |
| Argo Rollouts | **1.8+** | `AnalysisTemplate` + Prometheus provider |
| cosign | **2.x** | keyless (OIDC) or key-based; Kyverno verifies |
| Trivy | **0.56.x** | ⭐ `--exit-code 1 --ignore-unfixed` |
| Java (app) | **21** LTS | ⭐ current LTS is **25** (Sept 2025); 21 remains the widest production target |
| Node (FE build) | **22** | match the Dockerfile |
| Go | **1.23** | `-race -shuffle=on` in CI |
| Python | **3.13** | pytest + `-n auto` |
| Kubernetes schemas | **1.31** | `kubeconform -kubernetes-version` must match your cluster |

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish_Kumar_Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn: https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260
🔗 GitHub: https://github.com/3558Bhk

*Three scenarios. Three tools. Four languages. One artifact contract: the digest.*

</div>
