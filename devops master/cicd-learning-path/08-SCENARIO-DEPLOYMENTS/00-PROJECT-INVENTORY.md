# 📦 `00` — PROJECT INVENTORY
### Every application you built in the Docker and Kubernetes paths, mapped to the exact pipeline that builds it and the exact step that ships it.

> ⭐ **Read this before any scenario folder.** It answers the question the rest of this folder assumes you have already settled: *which app am I shipping, what does its build look like, and what does "deployed" mean for it?*
>
> **Sources:** [`docker-learning-path/`](../../docker-learning-path/) projects **1–14** · [`kubernetes-learning-path/`](../../kubernetes-learning-path/) projects **1–15**. Nothing here is new application code — it is the same code, now with a pipeline around it.
>
> ⭐ **The MERN stack is the one shape whose app was built in *both* source paths:** [`docker-learning-path/17-PROJECT-14-mern-stack.md`](../../docker-learning-path/17-PROJECT-14-mern-stack.md) (**Docker P14** — images, Compose, the replica set, migrations, backups) and [`kubernetes-learning-path/18-PROJECT-15-mern-stack.md`](../../kubernetes-learning-path/18-PROJECT-15-mern-stack.md) (**K8s P15** — the StatefulSet, the gated migration Job, the backup CronJob). [`01-MERN-STACK-PROJECT.md`](01-MERN-STACK-PROJECT.md) is the **CI/CD layer on top of those two**, not a rebuild.

---

## 📇 Contents

| § | What |
|---|---|
| [1](#1--the-two-source-paths-and-what-they-left-you-with) | The two source paths, and the deployable artifacts each one produced |
| [2](#2--full-inventory--14-docker-projects) | ⭐ Full inventory — all 14 Docker projects |
| [3](#3--full-inventory--15-kubernetes-projects) | ⭐ Full inventory — all 15 Kubernetes projects |
| [4](#4--the-five-application-shapes) | **The five application shapes** — FE only / BE only / FE+BE / polyglot / ⭐ **MERN** — and which projects belong to each |
| [5](#5--the-two-deployment-targets-and-what-actually-changes) | The two deployment targets, and what actually changes between them |
| [6](#6---per-application-pipeline-profiles) | ⭐⭐ Per-application **pipeline profiles** — the card you copy from when writing a pipeline |
| [7](#7--which-file-in-this-folder-covers-what) | Cross-reference matrix: project → file in this folder |
| [8](#8--prerequisites--what-must-exist-before-any-pipeline-runs) | Prerequisites — what must exist before any pipeline in this folder can run |
| [9](#9---the-three-things-that-differ-per-language--and-the-four-that-never-do) | ⭐ The three things that differ per language — and the four that never do |

---

## 1 · The two source paths, and what they left you with

```
docker-learning-path/                     kubernetes-learning-path/
─────────────────────                     ─────────────────────────
P1  hello-docker                          P1  first pod
P2  static site          ─────────────▶   P2  deployment + service + rollout
P3  config and env       ─────────────▶   P3  ConfigMap + Secret
P4  CLI / entrypoint     ─────────────▶   P4  Job + CronJob + init container
P5  volumes/health/user  ─────────────▶   P5  PVC + StatefulSet
P6  multistage build     ─────────────▶   (every image in P8–P12 uses it)
P7  compose stack        ─────────────▶   P6  Ingress + TLS
P8  React frontend       ═══════════════  P8  React frontend on K8s
P9  Java backend         ═══════════════  P9  Java backend on K8s
P10 React + Java         ═══════════════  P10 React + Java on K8s
P11 React + Python       ═══════════════  P11 React + Python on K8s
P12 React + Go           ═══════════════  P12 React + Go on K8s
P13 Databases (×6)       ═══════════════  P13 Databases on K8s (×6)
                                          P14 Helm charts + Argo CD GitOps
         │                                         │
         └──────────────┬──────────────────────────┘
                        ▼
        ⭐ THIS FOLDER: put a pipeline around all of it
```

**The `═══` rows are the ones you deploy.** P8–P13 exist in *both* paths with the same application code — the Docker path gave you the image, the Kubernetes path gave you the manifests. A CI/CD pipeline joins those two halves: **CI produces the image, CD applies the manifest pointing at that image.** That join is the entire subject of this folder.

**The `───▶` rows are the concepts, not the apps.** Docker P2–P7 and K8s P1–P7 taught you `COPY`/`ENV`/`ENTRYPOINT`/healthchecks/multistage/compose and pods/rollouts/config/secrets/jobs/storage/ingress. You do not pipeline them separately — ⭐ **but every one of them shows up inside the pipelines for P8–P13.** Specifically:

| Concept from | Where it appears in a pipeline |
|---|---|
| Docker P2 `.dockerignore` | ⭐ the single biggest CI cache-killer. Get it wrong and every build re-uploads your whole context |
| Docker P3 `ARG` vs `ENV` | build-time version injection: `--build-arg GIT_SHA=$(git rev-parse HEAD)` |
| Docker P4 `ENTRYPOINT`/`CMD` | why `docker run img --flag` works for the CLI and not for the API |
| Docker P5 `HEALTHCHECK` | the CD smoke gate. Compose uses it; Kubernetes **ignores it** and uses probes |
| Docker P6 multistage | ⭐ why your CI image is 90 MB and not 900 MB, and why the build cache must be exported |
| Docker P7 Compose | the CD target for "deploy to a VM" — `compose pull && compose up -d` |
| K8s P2 rollout | the CD verification step: `kubectl rollout status` |
| K8s P3 ConfigMap/Secret | ⭐ why config changes and image changes are **different deploy events** |
| K8s P4 Job/CronJob | how you run a **database migration** as a pipeline step (not as a side effect) |
| K8s P5 StatefulSet | why the P13 data tier is *not* deployed by the same pipeline as the app tier |
| K8s P6 Ingress | the smoke-test URL, and why kind needs `ingress-nginx` installed first |
| K8s P7 Observability | what the Case 2 automatic gate queries to decide "healthy" |
| K8s P14 Helm/Argo CD | [`scenario-3-ci-plus-cd/08-gitops-argocd.md`](./scenario-3-ci-plus-cd/08-gitops-argocd.md) |

---

## 2 · Full inventory — 14 Docker projects

| # | Project | App produced | Lang / runtime | Container port | Deployable? | Pipeline shape |
|---|---|---|---|---|---|---|
| **P1** | 🥚 Hello, Docker | `hello` | any | — | ⛔ teaching only | none |
| **P2** | 🐣 Static Website | `static-site` | nginx + HTML | 80 | ⚠️ yes, trivially | ⭐ **CI-only** is the right answer — see §4 shape A |
| **P3** | 🐥 Configurable Python App | `config-app` | Python 3.13 | 8000 | ✅ yes | BE-only, env-driven |
| **P4** | 🐤 CLI Tool | `shopctl` | Python / Go | — | ⚠️ not a service | ⭐ **no CD** — you publish a binary/image, not a deployment. See §6.6 |
| **P5** | 🐓 Persistent Data App | `notes` | Python + volume | 8000 | ✅ yes | BE-only + a volume/PVC |
| **P6** | 🦅 Multi-stage Builds | (a technique) | — | — | — | ⭐ appears in **every** pipeline below |
| **P7** | 🦉 Compose Stack | the whole `shop` stack | mixed | many | ✅ yes | ⭐ the **Docker target** for CD — `compose up -d` |
| **P8** | ⚛️ React (Vite) Frontend | **`shop-ui`** | Node 24 → nginx | **80** | ✅ yes | 🔵 **FE only** |
| **P9** | ☕ Java / Spring Boot Backend | **`shop-api`** | Java 21 + Maven | **8080** | ✅ yes | 🟢 **BE only** |
| **P10** | ⚛️+☕ React + Java | `shop-ui` + `shop-api` | Node + Java | 80 / 8080 | ✅ yes | 🟡 **FE + BE, one repo** |
| **P11** | ⚛️+🐍 React + Python | `shop-ui` + `order-worker` | Node + Python 3.13 (FastAPI) | 80 / **9092** | ✅ yes | 🟠 **FE + BE, different langs** |
| **P12** | ⚛️+🐹 React + Go | `shop-ui` + `checkout` | Node + Go 1.23 | 80 / **9091** | ✅ yes | 🟠 **FE + BE, different langs** |
| **P13** | 🗄️ Databases (×6) | postgres · redis · rabbitmq · mongo · mysql · minio | upstream images | 5432 · 6379 · 5672 · 27017 · 3306 · 9000 | ⚠️ **special** | ⭐ **do not build these.** See §6.7 |
| **P14** | 🟣 ⭐ **MERN Stack** | **`mern-web`** + **`mern-api`** + **`mern-mongo`** | Node 24 / React 19 + Express 5 + **MongoDB 8.0** | 80 / **4000** / 27017 | ✅ yes | 🟣⭐ **shape E** — ⭐ the only shape where **the database ships inside the release**. [`01-MERN-STACK-PROJECT.md`](01-MERN-STACK-PROJECT.md) · §6.8 |

**Six extra apps from the Docker capstone** (`02-CAPSTONE-END-TO-END.md`) that also appear here:

| App | Lang | Port | Role |
|---|---|---|---|
| `payment-mock` | Go 1.23 | **9093** | a third-party dependency you control — the ideal canary target |
| `shop-ui` | React 19 + nginx | 80 | the browser entry point |
| `shop-api` | Java 21 + Spring Boot 4.1 | 8080 | the primary backend, `/actuator/prometheus` on the same port |
| `checkout` | Go 1.23 | 9091 | the high-throughput service — the one where image size actually matters |
| `order-worker` | Python 3.13 | 9092 | ⭐ **no HTTP surface** — a queue consumer. Health is a heartbeat, not a probe |
| `migrator` | Java 21 (Flyway) | — | ⭐ a **Job**, not a Deployment. Runs to completion, then exits 0 |

---

## 3 · Full inventory — 15 Kubernetes projects

| # | Project | What it gave you | Used by the pipelines as… |
|---|---|---|---|
| **P1** | 🥇 First Pod | a bare pod, and your first outage | ⛔ never deployed by a pipeline — a bare pod has no rollout and no self-healing |
| **P2** | 🥈 Deployment + Service + zero-downtime rollout | `Deployment`, `Service`, `kubectl rollout status/undo`, `maxSurge`/`maxUnavailable` | ⭐⭐ **the CD verification step for every stateless app** |
| **P3** | 🥉 ConfigMap + Secret | config/secret separation, `envFrom`, checksum annotations | ⭐ the "config changed but nothing happened" fix — a **separate deploy event** |
| **P4** | 🏅 Job + CronJob + init container | run-to-completion workloads | ⭐⭐ **how a DB migration is deployed** — a `Job`, gated before the app rollout |
| **P5** | 💾 PVC + StatefulSet | stable identity and storage | the data tier (P13) — ⚠️ different pipeline, different rules |
| **P6** | 🌐 Ingress + host routing + real TLS | `Ingress`, `cert-manager`, host rules | ⭐ the **smoke-test URL** the CD gate curls |
| **P7** | 📊 Observability | metrics, logs, events, alerts | ⭐⭐ **what the Case 2 automatic gate queries** |
| **P8** | ⚛️ React frontend on K8s | `shop-ui` Deployment + Service + Ingress + nginx config | 🔵 **FE only** |
| **P9** | ☕ Java backend on K8s | `shop-api` Deployment + probes + HPA + resources | 🟢 **BE only** |
| **P10** | 🔗 React + Java full stack | both, plus the FE→BE routing and the network policy | 🟡 **FE + BE** |
| **P11** | 🐍 React + Python full stack | `shop-ui` + `order-worker` (FastAPI) | 🟠 **polyglot** |
| **P12** | 🐹 React + Go full stack | `shop-ui` + `checkout` | 🟠 **polyglot** |
| **P13** | 🗄️ Databases on K8s (×6) | StatefulSets, PVCs, backup CronJobs | ⭐ **promoted, not built** — see §6.7 |
| **P14** | ⎈ Helm charts + Argo CD GitOps | a chart per service, a config repo, Argo CD | ⭐⭐ [`scenario-3-ci-plus-cd/08-gitops-argocd.md`](./scenario-3-ci-plus-cd/08-gitops-argocd.md) |
| **P15** | 🟣 ⭐ **MERN on Kubernetes** | two Deployments + a **replica-set StatefulSet**, the migration as a **gated Job**, the backup as a **verified CronJob** | 🟣⭐ **shape E** — ⭐⭐ the reference implementation for *how a stateful member of a release is deployed*. §6.8 |

⭐ **The single most important line in that table is P4.** Every backend in P9–P12 needs a schema migration, and the correct place for it is a **Kubernetes Job that runs to completion and gates the Deployment rollout** — not a `flyway migrate` inside the container's entrypoint, and not a manual `psql` before the deploy. If your pipeline cannot answer "where does the migration run, and what happens if it fails halfway?", you do not have continuous deployment; you have continuous hope. [`scenario-3-ci-plus-cd/05-be-only.md`](./scenario-3-ci-plus-cd/05-be-only.md) §5 builds it properly.

---

## 4 · The five application shapes

⭐ **This is the axis the user-visible complexity actually runs along.** Not "which tool" — the tool files are parallel and nearly interchangeable. **Which shape** determines your pipeline's structure.

```
SHAPE A ── FRONTEND ONLY              SHAPE B ── BACKEND ONLY
┌───────────────────────┐             ┌───────────────────────┐
│ shop-ui (React+nginx) │             │ shop-api (Java 21)    │
│ static-site (P2)      │             │ checkout  (Go)        │
└───────────────────────┘             │ order-worker (Python) │
  Docker P2, P8                       └───────────────────────┘
  K8s    P8                             Docker P3, P5, P9
                                        K8s    P9

SHAPE C ── FE + BE, ONE STACK         SHAPE D ── FE + BE, DIFFERENT LANGS
┌───────────────────────┐             ┌───────────────────────┐
│ shop-ui  ──┐          │             │ shop-ui      (Node)   │
│            ├─ contract│             │      │                │
│ shop-api ──┘          │             │      ▼   REST/JSON    │
└───────────────────────┘             │ order-worker (Python) │
  Docker P10 · K8s P10                │ checkout     (Go)     │
  both Java-family tooling            │ payment-mock (Go)     │
                                      └───────────────────────┘
                                        Docker P11, P12 · K8s P11, P12
                                        ⭐ 3–4 toolchains in ONE pipeline

SHAPE E ── ⭐ MERN: THE DATABASE SHIPS INSIDE THE RELEASE
┌─────────────────────────────────────────────────────┐
│ shop-mern  (npm workspaces, ONE lockfile, ONE repo) │
│                                                     │
│  apps/web ────────┐  zod contract                   │
│  React 19 + nginx ├─ packages/shared ─┐             │
│                   │                   │             │
│  apps/api ────────┘                   │             │
│  Node 24 + Express 5 ─────────────────┘             │
│         │  Mongoose 8, autoIndex:false              │
│         ▼                                           │
│  ⭐ mongo (replica set ×3) ← INSIDE THE RELEASE     │
│     migrate-mongo ledger · verified backups         │
└─────────────────────────────────────────────────────┘
  Docker P14 · K8s P15 · spec: 01-MERN-STACK-PROJECT.md
  ⭐ one language (TypeScript) — but the hardest pipeline
```

### What actually differs between the shapes

| Concern | 🔵 A · FE only | 🟢 B · BE only | 🟡 C · FE+BE | 🟠 D · polyglot | 🟣 **E · MERN** |
|---|---|---|---|---|---|
| **Build tool** | `npm ci && npm run build` → static files | Maven / `go build` / `uv sync` | both | ⭐ **three or four**, each cached separately | 🟣 **one** (`npm ci` at the workspace root) — but ⭐ **the data tier has a build too** |
| **Test type** | unit (Vitest) + ⭐ Lighthouse + bundle size | unit + ⭐ integration (**testcontainers**) | both, plus a **contract test** | both × N, plus contract tests | unit + ⭐ **integration against a real replica set** (`@testcontainers/mongodb`) + the **zod contract test** in `packages/shared` |
| **Build time** | 30–90 s | ⭐ 2–8 min (JVM + Maven) | 3–9 min | 3–9 min, but **parallelisable** | 4–10 min — ⭐ plus a **migration dry-run** and a **backup-restore verify** |
| **Image size** | ~50 MB (nginx + static) | 200–350 MB (JRE) | both | 50 MB – 350 MB | web ~50 MB · api ~**180 MB** (`--omit=dev`, `dist` only) · mongo = **pinned upstream digest** |
| **Runtime image base** | `nginx:1.29-alpine` | `eclipse-temurin:21-jre-alpine` | both | per-service | `node:24-alpine` + `nginx:1.29-alpine` + ⭐ `mongo@sha256:…` **pinned by digest** |
| **Deploy risk** | ⭐ **low** — static files, instant rollback | ⭐⭐ **high** — schema migrations, connection pools, warmup | ⭐⭐⭐ **highest** — **version skew** between FE and BE | ⭐⭐ high, but failures are **isolated per service** | 🟣⭐⭐⭐⭐ **highest of all** — the app rolls back in seconds, **the data does not roll back at all** |
| **The thing that breaks you** | browser cache serving an old `index.html` against new assets | a migration that cannot be rolled back | ⭐⭐ FE calls an endpoint BE removed | one language's toolchain update breaks the shared pipeline | ⭐⭐ **schemaless = no database-level schema.** Two app versions write to one collection *during* the rollout, and nothing stops them |
| **Rollout strategy** | `RollingUpdate`, or atomic CDN swap | RollingUpdate + ⭐ expand/contract migrations | ⭐ **BE first, then FE** — always | per-service, independently | ⭐ **web 🤖 Case 2 · api 🔒 Case 1 · mongo 🔒🔒 Case 1, separately** — three verdicts, one repo |
| **Pipeline count** | 1 | 1 | ⭐ 1 or 2 (see below) | ⭐ **1 per service**, orchestrated | ⭐ **1 pipeline, 3 components, 3 verdicts** |
| **File in this folder** | [`04-fe-only.md`](./scenario-3-ci-plus-cd/04-fe-only.md) | [`05-be-only.md`](./scenario-3-ci-plus-cd/05-be-only.md) | [`06-fe-plus-be-same-stack.md`](./scenario-3-ci-plus-cd/06-fe-plus-be-same-stack.md) | [`07-fe-plus-be-different-langs.md`](./scenario-3-ci-plus-cd/07-fe-plus-be-different-langs.md) | ⭐⭐ [`01-MERN-STACK-PROJECT.md`](01-MERN-STACK-PROJECT.md) |

### ⭐ The one decision that shapes C and D: one pipeline or many?

| Option | What it looks like | Choose it when |
|---|---|---|
| **One pipeline, all services** | every commit builds and deploys `shop-ui` + `shop-api` + `checkout` | the repo is small, the team is small, and builds are under ~5 min |
| ⭐ **One pipeline per service, path-filtered** | `ci-shop-ui.yml` triggers only on `apps/shop-ui/**` | ⭐ **the default for a monorepo.** Untouched services are not rebuilt, not re-tested, not re-deployed |
| **One CI pipeline, one CD pipeline** | CI builds everything changed; CD promotes a **release train** | you need FE and BE to go out **together** (shape C with a hard contract) |
| ⭐ **CI per service + a "release train" CD** | each service publishes independently; CD deploys a pinned set of digests | shape D at scale — this is what `08-gitops-argocd.md` builds |

⭐⭐ **The rule for shape C (FE+BE):** if the frontend and backend have a **breaking** contract change between them, they must deploy **together**, in a known order — **backend first** (it must be able to serve both the old and the new frontend), then frontend. That single ordering constraint is why shape C is harder than shape D despite having fewer languages. [`06-fe-plus-be-same-stack.md`](./scenario-3-ci-plus-cd/06-fe-plus-be-same-stack.md) §6 gives all four defences against version skew.

---

## 5 · The two deployment targets, and what actually changes

| | 🐳 **Docker / Compose target** | ☸️ **Kubernetes target** |
|---|---|---|
| Where it runs | a VM, a dev laptop, a single EC2 instance | `kind` locally → a real cluster in staging/prod |
| What CD executes | `docker compose pull && docker compose up -d` | `kubectl set image` · `helm upgrade` · `kustomize build \| kubectl apply` · **or Argo CD syncs it for you** |
| What "healthy" means | ⭐ the Compose `healthcheck:` (from Docker P5) | ⭐⭐ `readinessProbe` + `kubectl rollout status` (K8s P2). **Kubernetes ignores the image `HEALTHCHECK`** |
| Scaling | `docker compose up -d --scale svc=3` | `replicas:` + HPA |
| Rollback | re-pin the previous digest and `up -d` again | ⭐ `kubectl rollout undo` — or re-apply the previous manifest |
| Config | `.env` file / `environment:` | ConfigMap + Secret (K8s P3) |
| Secrets | ⛔ `.env` on the host, mode `0600` | Secret + external store (Key Vault / SOPS / External Secrets) |
| Migrations | a one-shot `docker compose run --rm migrator` | ⭐ a **Job** (K8s P4) that gates the rollout |
| Data tier | Compose services with named volumes | StatefulSet + PVC (K8s P5) — or a managed service |
| Zero downtime | ⚠️ hard: there is a brief gap unless you run two Compose projects behind a proxy | ✅ built in, *if* your readiness probe is honest |
| Multi-service ordering | `depends_on` + `condition: service_healthy` | ⭐ init containers, Job gates, or just correct probes |
| **Files in this folder** | [`case-1…/04-docker-and-k8s-targets.md`](./scenario-2-cd-only/case-1-continuous-delivery/04-docker-and-k8s-targets.md) · [`case-2…/04-docker-and-k8s-targets.md`](./scenario-2-cd-only/case-2-continuous-deployment/04-docker-and-k8s-targets.md) | same two files, second half |

⭐ **The one thing that does NOT change between targets: the artifact.** The image digest that CI published is the image digest that CD deploys, whether the destination is `docker compose` or a 200-node cluster. That invariance is why the digest contract (§9) matters more than the target choice.

⚠️ **The kind gotcha, restated because it costs everyone an hour:** a `kind` cluster has **no ingress controller and no `LoadBalancer` support** by default. Install `ingress-nginx` (K8s P6) or use `kubectl port-forward` for smoke tests. And if you build images on the host, kind cannot see them — you must `kind load docker-image` them, or run a local registry and point kind at it (file `05` §1.2).

---

## 6 · ⭐⭐ Per-application pipeline profiles

> **This is the section you copy from.** Each card gives the exact commands a pipeline runs for that app, in order. Every tool file in this folder instantiates these cards in YAML or Groovy — the *content* never changes, only the syntax.

### 6.1 🔵 `shop-ui` — React frontend (Docker P8 · K8s P8)

| Field | Value |
|---|---|
| **Source** | `apps/shop-ui/` — Vite + React 19, TypeScript, nginx runtime |
| **Build** | `npm ci` → `npm run build` → `dist/` |
| **Test** | `npm run test:unit` (Vitest) · `npm run lint` · ⭐ `npm run test:a11y` |
| **Quality gates** | ⭐ bundle size (`dist/` under budget) · Lighthouse perf/a11y/best-practices thresholds |
| **Image** | multistage: `node:24-alpine` (build) → `nginx:1.29-alpine` (run). ~50 MB |
| **Build args** | `VITE_API_URL` ⚠️ **baked at build time** — see the warning below |
| **Port** | 80 |
| **Health** | `GET /` → 200, or `GET /healthz` from a custom nginx location |
| **Deploy** | RollingUpdate. ⭐ Zero-downtime is easy; **cache invalidation is the hard part** |
| **Rollback** | re-pin the previous digest — instant, because static files hold no state |
| **Migration** | none |

⚠️ **THE FRONTEND TRAP THAT RUINS OTHERWISE-GOOD PIPELINES.** Vite inlines `import.meta.env.VITE_*` at **build time**. So a single image cannot serve dev, staging and prod if the API URL differs per environment — you either build three images, or you inject config at **runtime**. The runtime-injection pattern (an `env.js` served by nginx, generated by the entrypoint from real environment variables) is the correct answer and it is built in [`scenario-3-ci-plus-cd/04-fe-only.md`](./scenario-3-ci-plus-cd/04-fe-only.md) §4. ⛔ Building per-environment images means your staging artifact is **not** your production artifact, which breaks the digest contract this whole folder exists to enforce.

### 6.2 🟢 `shop-api` — Java 21 / Spring Boot backend (Docker P9 · K8s P9)

| Field | Value |
|---|---|
| **Source** | `apps/shop-api/` — Maven, Spring Boot **4.1.1**, Java 21 |
| **Build** | `./mvnw -B -ntp clean verify` ⭐ `-B` batch mode, `-ntp` no transfer progress — both cut CI log noise by ~80% |
| **Test** | unit (Surefire) → ⭐ **integration with Testcontainers** (real Postgres 17 in Docker) → contract |
| **Quality gates** | JaCoCo coverage floor · SpotBugs/ErrorProne · ⭐ `dependency:go-offline` cached separately |
| **Image** | multistage: `maven:3.9-eclipse-temurin-21` (build) → `eclipse-temurin:21-jre-alpine` (run). ~230 MB |
| **JVM flags** | ⭐⭐ `-XX:MaxRAMPercentage=75.0` — **never** `-Xmx2g`. Plus `-XX:+HeapDumpOnOutOfMemoryError`, `-XX:+ExitOnOutOfMemoryError` |
| **Port** | 8080 (app + `/actuator/prometheus`) |
| **Health** | `GET /actuator/health/readiness` and `/actuator/health/liveness` — ⭐ **two distinct endpoints** |
| **Warmup** | ⭐⭐ 15–30 s before it is genuinely fast (JIT). `startupProbe` + `minReadySeconds`, or it fails under instant traffic |
| **Deploy** | RollingUpdate, `maxUnavailable: 0`, `maxSurge: 1`. Readiness must be honest or this is not zero-downtime |
| **Rollback** | ⚠️ **the image rolls back; the schema does not.** Requires expand/contract migrations (§6.5) |
| **Migration** | ⭐ Flyway, run as a **Kubernetes Job** before the rollout |

### 6.3 🟢 `checkout` — Go service (Docker P12 · K8s P12)

| Field | Value |
|---|---|
| **Build** | `go build -trimpath -ldflags="-s -w" -o /out/checkout ./cmd/checkout` |
| **Test** | `go test ./... -race -covermode=atomic` ⭐ `-race` in CI only — it is 5–10× slower and finds real bugs |
| **Quality gates** | `go vet` · `golangci-lint run` · `govulncheck ./...` |
| **Image** | ⭐⭐ `FROM scratch` or `gcr.io/distroless/static` — **8–15 MB**. The smallest image in the whole path |
| **Version injection** | `-ldflags "-X main.version=$GIT_SHA"` — no build arg, no runtime lookup |
| **Port** | 9091 |
| **Health** | `GET /healthz` (liveness) · `GET /readyz` (readiness — checks DB + queue) |
| **Deploy** | RollingUpdate. Starts in ~10 ms — ⭐ the ideal **canary** service |
| **Rollback** | re-pin the digest. Trivial: no schema, no warmup, no state |

### 6.4 🟢 `order-worker` — Python queue consumer (Docker P11 · K8s P11)

| Field | Value |
|---|---|
| **Build** | `uv sync --frozen` (or `pip install -r requirements.txt --no-cache-dir`) |
| **Test** | `pytest -q --cov=src --cov-fail-under=80` |
| **Quality gates** | `ruff check` · `ruff format --check` · `mypy` · `pip-audit` |
| **Image** | `python:3.13-slim` → ~120 MB. ⭐ slim, not `alpine` — alpine's musl libc breaks wheels with C extensions |
| **Port** | ⭐ **none that matter.** It is a **queue consumer**, not an HTTP service |
| **Health** | ⭐⭐ **This is the interesting one.** There is no endpoint to probe. Options: a heartbeat file + `exec` probe, a metrics push to Pushgateway, or an HTTP health server on 9092 that reports "last message processed N seconds ago" |
| **Deploy** | RollingUpdate, but ⭐ **`terminationGracePeriodSeconds` must exceed your longest task** or you drop work mid-message |
| **Rollback** | re-pin. ⚠️ But a worker that already processed messages with new logic cannot un-process them |

⭐ **`order-worker` is the app that teaches you probes are not about HTTP.** A readiness probe answers *"can this replica accept work right now?"* For a consumer that means *"am I connected to the broker and not paused?"* — which is a **queue** question, not a network one. [`scenario-3-ci-plus-cd/07-fe-plus-be-different-langs.md`](./scenario-3-ci-plus-cd/07-fe-plus-be-different-langs.md) §5 builds the heartbeat version.

### 6.5 ⭐ The `migrator` — a Job, not a Deployment

| Field | Value |
|---|---|
| **What it is** | Flyway (or Alembic / `goose`) packaged as an image that runs `migrate` and exits |
| **Why separate** | ⭐⭐ so a failed migration **stops the pipeline** instead of leaving half the fleet on a new schema |
| **K8s kind** | `Job` with `backoffLimit: 1`, `ttlSecondsAfterFinished: 600` |
| **Runs** | **before** the app rollout, in the same CD stage, gated |
| **Idempotent?** | ⭐ must be. The pipeline may retry |
| **Rollback** | ⛔ **usually impossible.** This is why migrations must be **expand/contract**: add the new column (nullable), deploy code that writes both and reads old, backfill, deploy code that reads new, then contract (drop old) in a **later release**. Each step is independently deployable *and* independently revertible |
| **Helm hook** | `helm.sh/hook: pre-upgrade` + `hook-weight` — ⚠️ but a hook failure does **not** always block the release the way you expect. Prefer an explicit Job in the pipeline |

### 6.6 ⚠️ `shopctl` — a CLI (Docker P4). Why it has no CD

A CLI is **published**, not **deployed**. There is no running instance to roll out, no readiness to probe, no rollback to orchestrate. Its pipeline is:

```
commit → build → test → ⭐ publish (image + binary + checksum) → ⭐ STOP
```

⭐ That is **Scenario 1 (CI only)**, and it is not an incomplete pipeline — it is the complete and correct one. What you add on top is *release* machinery, not deployment: a GitHub Release with the binaries and a `SHA256SUMS` file, a `latest` tag moved only on a tagged release, and a Homebrew/scoop tap update if you have users. The CD question for a CLI is *"who installs it, and how do they get the update?"* — which is a distribution problem, not a deployment one.

### 6.7 ⭐ Databases (P13) — promoted, never built

| Rule | Why |
|---|---|
| ⛔ **Do not build Postgres/Redis/RabbitMQ images in your pipeline** | You are not the maintainer. Your value-add is zero and your CVE surface is now your problem |
| ✅ **Pin by digest, not by tag** | `postgres:17.7@sha256:abc…` — ⭐ a tag can be re-pushed; a digest cannot |
| ✅ **Promote the pin through a config repo** | the *manifest* changes, not the image. That is a **GitOps** event (K8s P14) |
| ✅ **Patch on a schedule, not on a commit** | a weekly pipeline that bumps digests and opens a PR. Dependabot/Renovate do this for free |
| ⭐ **StatefulSet, not Deployment** | stable identity + stable storage (K8s P5). Rolling one is a **maintenance event**, not a deploy |
| ⭐⭐ **The data tier is not part of the app pipeline** | Different change cadence, different risk profile, different rollback story (⛔ there isn't one), different on-call. Coupling them means a frontend CSS fix can restart your database |
| ✅ **Prefer a managed service in production** | RDS/Cloud SQL/Azure Database. ⭐ The honest senior answer: running Postgres on Kubernetes is a *choice with a cost*, and for most teams the cost exceeds the benefit |

---

### 6.8 🟣⭐ `shop-mern` — MERN (Docker P14 · K8s P15) · **shape E**

> **App built in:** [`../../docker-learning-path/17-PROJECT-14-mern-stack.md`](../../docker-learning-path/17-PROJECT-14-mern-stack.md) and [`../../kubernetes-learning-path/18-PROJECT-15-mern-stack.md`](../../kubernetes-learning-path/18-PROJECT-15-mern-stack.md).
> **CI/CD spec:** [`01-MERN-STACK-PROJECT.md`](01-MERN-STACK-PROJECT.md) — tool-agnostic; every tool folder deploys *that*.

| Field | Value |
|---|---|
| **Repo layout** | npm workspaces monorepo: `apps/web` (React 19 + Vite 7) · `apps/api` (Node 24 + Express 5.1 + Mongoose 8.20) · `packages/shared` (zod 4 contract) — ⭐ **one lockfile at the root** |
| **Images** | `ghcr.io/3558bhk/mern-web` (→ nginx:80) · `ghcr.io/3558bhk/mern-api` (→ :4000) · **`mongo@sha256:…`** — ⛔ never `mongo:8` by tag; the data tier is pinned by **digest** |
| **Ports** | `mern-web` **80** · `mern-api` **4000** · `mern-mongo` **27017** |
| **What makes it shape E** | ⭐⭐ **The stateful database ships inside the release.** Shapes A–D treat Postgres as someone else's problem (§6.7 promotes it). Here it is *your* StatefulSet, *your* PVCs, *your* backup CronJob. |
| **Schema enforcement** | ⛔ **there is none at the database level.** Mongoose validates in-process, so during a rollout **two app versions write to one collection**. Migrations must be **expand/contract**, always backwards-compatible for one release. |
| **Migrations** | `migrate-mongo` 9 → ledger collection **`schema_migrations`**, `useFileHash: true`, ⭐ **`autoIndex: false`** (indexes come from migrations, never from app boot) |
| **CI test stack** | ⭐ **`@testcontainers/mongodb`** with `--replSet rs0` + `rs.initiate()`. ⛔ **Never `mongodb-memory-server`** — it is not a replica set, so transactions and `w=majority` silently pass locally and fail in production |
| **Contract test** | `packages/shared` zod schemas + `z.infer` → **both** sides import the same types. ⛔ never emit JSON/TS from a JSON Schema (two sources of truth). This *replaces* shape C/D's `openapi-diff` |
| **Rollback for the app** | seconds — pin the previous **digest**, redeploy |
| **Rollback for the data** | ⭐⭐ **`mongodump --oplog` + restore-verify + count-compare**, and only if you are willing to lose every write since the backup. **An image rollback is not a data rollback.** |
| **Verdict — `mern-web`** | 🤖 **Case 2 · Continuous Deployment.** Static bundle behind nginx, no schema, instant rollback → fully automatic with smoke + canary gates |
| **Verdict — `mern-api`** | 🔒 **Case 1 · Continuous Delivery.** Schema migrations, connection pools, warmup → always-deployable, **human approval** before production |
| **Verdict — `mern-mongo`** | 🔒🔒 **Case 1, and separately.** ⛔ never in the same approval as the api. A database version change needs its own gate, its own backup, its own rollback plan |
| **Why the toolchain got *easier* and the pipeline got *harder*** | One language (TypeScript), one package manager, one lockfile → the build is simpler than shape D. But **schemaless + stateful-inside-the-release** means the *deployment* is the hardest thing in this folder. ⭐ Do not let "it's all just Node" fool you |

---

## 7 · Which file in this folder covers what

| Project | Scenario 1 (CI) | Scenario 2 (CD) | Scenario 3 (both) |
|---|---|---|---|
| P2 static site | [`s1/04`](./scenario-1-ci-only/04-app-shapes-fe-be-fullstack.md) shape A | [`s2/c1/04`](./scenario-2-cd-only/case-1-continuous-delivery/04-docker-and-k8s-targets.md) Docker target | [`s3/04`](./scenario-3-ci-plus-cd/04-fe-only.md) |
| P3, P5 Python app | [`s1/04`](./scenario-1-ci-only/04-app-shapes-fe-be-fullstack.md) shape B | both target files | [`s3/05`](./scenario-3-ci-plus-cd/05-be-only.md) |
| P4 CLI | ⭐ [`s1/README`](./scenario-1-ci-only/README.md) §"CI-only is the right answer" | — (no CD) | — |
| P7 Compose stack | [`s1/04`](./scenario-1-ci-only/04-app-shapes-fe-be-fullstack.md) | ⭐ both `04-docker-and-k8s-targets.md`, first half | [`s3/06`](./scenario-3-ci-plus-cd/06-fe-plus-be-same-stack.md) |
| **P8 React FE** | [`s1/01`](./scenario-1-ci-only/01-github-actions-ci.md)·[`02`](./scenario-1-ci-only/02-azure-devops-ci.md)·[`03`](./scenario-1-ci-only/03-jenkins-ci.md) + [`s1/04`](./scenario-1-ci-only/04-app-shapes-fe-be-fullstack.md) | all four CD files | ⭐ [`s3/04-fe-only.md`](./scenario-3-ci-plus-cd/04-fe-only.md) |
| **P9 Java BE** | same four | all four CD files | ⭐ [`s3/05-be-only.md`](./scenario-3-ci-plus-cd/05-be-only.md) |
| **P10 React+Java** | [`s1/04`](./scenario-1-ci-only/04-app-shapes-fe-be-fullstack.md) shape C | all four CD files | ⭐⭐ [`s3/06-fe-plus-be-same-stack.md`](./scenario-3-ci-plus-cd/06-fe-plus-be-same-stack.md) |
| **P11 React+Python** | [`s1/04`](./scenario-1-ci-only/04-app-shapes-fe-be-fullstack.md) shape D | all four CD files | ⭐⭐ [`s3/07-fe-plus-be-different-langs.md`](./scenario-3-ci-plus-cd/07-fe-plus-be-different-langs.md) |
| **P12 React+Go** | same | same | ⭐⭐ [`s3/07`](./scenario-3-ci-plus-cd/07-fe-plus-be-different-langs.md) |
| **P13 Databases** | ⛔ not built | §6.7 promotion model | [`s3/08-gitops-argocd.md`](./scenario-3-ci-plus-cd/08-gitops-argocd.md) |
| **K8s P14 Helm/Argo** | — | — | ⭐ [`s3/08-gitops-argocd.md`](./scenario-3-ci-plus-cd/08-gitops-argocd.md) |
| 🟣⭐ **Docker P14 + K8s P15 — MERN (`shop-mern`)** | ⭐ [`01-MERN-STACK-PROJECT.md`](01-MERN-STACK-PROJECT.md) **shape E** + [`s1/04`](./scenario-1-ci-only/04-app-shapes-fe-be-fullstack.md) | all four CD files — ⭐ web 🤖 Case 2 / api 🔒 Case 1 / mongo 🔒🔒 Case 1 | ⭐⭐ [`01-MERN-STACK-PROJECT.md`](01-MERN-STACK-PROJECT.md), then [`s3/07`](./scenario-3-ci-plus-cd/07-fe-plus-be-different-langs.md) + [`s3/08`](./scenario-3-ci-plus-cd/08-gitops-argocd.md) · tool impls in [`../09-TOOL-MASTERY/*/05-PROJECT-DEPLOYMENTS.md`](../09-TOOL-MASTERY/README.md) |
| capstone `payment-mock` | [`s1/04`](./scenario-1-ci-only/04-app-shapes-fe-be-fullstack.md) shape B | ⭐ the canary target in Case 2 | [`s3/07`](./scenario-3-ci-plus-cd/07-fe-plus-be-different-langs.md) |

---

## 8 · Prerequisites — what must exist before any pipeline runs

```bash
# ── 1. the tools ─────────────────────────────────────────────────────────
git --version                 # any recent
docker version                # 27+  (Docker path)
kubectl version --client      # 1.37 (Kubernetes path)
kind version                  # 0.29+
helm version                  # v3.19+   (K8s P14)
java -version                 # ⭐ 21 — Jenkins LTS 2.568.3 requires 21 minimum
node --version                # 24 LTS
go version                    # 1.23
python3 --version             # 3.13

# ── 2. the cluster ───────────────────────────────────────────────────────
kind get clusters | grep -q '^cicd$' || kind create cluster --name cicd
kubectl create namespace shop-dev      --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace shop-staging  --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace shop-production --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace shop-config   --dry-run=client -o yaml | kubectl apply -f -
# ⚠️ kind has NO ingress controller and NO LoadBalancer by default.
#    Install ingress-nginx (K8s P6) or use `kubectl port-forward` for smoke tests.

# ── 3. a registry — pick ONE ─────────────────────────────────────────────
# GitHub:  ghcr.io/3558bhk/...    (a PAT with `write:packages`, or OIDC — no secret)
# Azure:   shopacr.azurecr.io     (`az acr create --sku Basic`)
# Offline: docker run -d -p 5000:5000 --restart=always --name registry registry:3
#          ⭐ for kind you must ALSO tell the cluster where it is — file 05 §1.2

# ── 4. the repo layout every file in this folder assumes ─────────────────
# shop/
# ├── apps/
# │   ├── shop-ui/        Dockerfile  package.json  src/  nginx.conf
# │   ├── shop-api/       Dockerfile  pom.xml  mvnw  src/
# │   ├── checkout/       Dockerfile  go.mod  main.go  main_test.go
# │   ├── order-worker/   Dockerfile  pyproject.toml  src/  tests/
# │   ├── payment-mock/   Dockerfile  go.mod  main.go
# │   └── migrator/       Dockerfile  db/migration/V1__*.sql
# ├── deploy/
# │   ├── base/           ⭐ Kustomize base: the manifests from K8s P8–P13
# │   └── overlays/
# │       ├── dev/  staging/  production/
# ├── charts/             ⭐ Helm charts from K8s P14
# ├── ci/                 templates, reusable workflows, shared-library refs
# └── .github/workflows/  or azure-pipelines.yml or Jenkinsfile

# ── 5. log in once locally so you can test pushes by hand ────────────────
echo "$GHCR_TOKEN" | docker login ghcr.io -u 3558bhk --password-stdin
# ⭐ if you cannot push an image by hand, your pipeline cannot either.
#   Debug it here, with a real error message, not inside a CI log.
```

---

## 9 · ⭐ The three things that differ per language — and the four that never do

**This is the summary that makes the whole folder learnable.** Four toolchains sounds like four times the work. It is not.

### What differs (only three things)

| | React / Node | Java | Go | Python |
|---|---|---|---|---|
| **1. Dependency install + its cache key** | `npm ci` · key on `package-lock.json` | `./mvnw dependency:go-offline` · key on `pom.xml` | `go mod download` · key on `go.sum` | `uv sync --frozen` · key on `uv.lock` |
| **2. Build + test command** | `npm run build` · `vitest run` | `./mvnw -B verify` | `go build ./...` · `go test -race ./...` | `uv run pytest` |
| **3. Runtime base image + its size** | `nginx:1.29-alpine` · ~50 MB | `eclipse-temurin:21-jre-alpine` · ~230 MB | ⭐ `scratch` · ~10 MB | `python:3.13-slim` · ~120 MB |

That is the complete list. Everything else is identical.

### What never differs (four things — ⭐ the artifact contract)

| # | Invariant | Why it is invariant |
|---|---|---|
| **1** | **CI publishes an image by DIGEST** and writes that digest somewhere CD can read it | a tag is mutable; a digest is content-addressed. This is the *only* way "what I tested is what I shipped" can be true |
| **2** | **CD never builds.** It reads a digest and points a manifest at it | the moment CD rebuilds, you have two artifacts and no guarantee they match |
| **3** | **CD verifies with a health signal**, and the signal's *shape* is the same everywhere — is the new version serving, and is the error rate flat | the endpoint differs (`/actuator/health/readiness` vs `/healthz` vs a heartbeat file); the *question* does not |
| **4** | **Rollback means re-pointing at the previous digest**, never "rebuild the old commit" | rebuilding the old commit can produce a *different* image — different base layers, different dependencies resolved. Re-pointing is exact and instant |

⭐⭐ **Say those four in an interview and the language column stops mattering.** The junior answer describes four toolchains. The senior answer describes one contract with a per-language adapter at the front of it — and then names the one place the contract genuinely strains: **shape C, where two artifacts must move together in a specific order.**

---

## Related

| File | Why |
|---|---|
| [`README.md`](./README.md) | the folder index — start here if you have not |
| [`scenario-2-cd-only/00-delivery-vs-deployment.md`](./scenario-2-cd-only/00-delivery-vs-deployment.md) | ⭐⭐ the distinction between the two CD cases, in depth |
| [`scenario-1-ci-only/04-app-shapes-fe-be-fullstack.md`](./scenario-1-ci-only/04-app-shapes-fe-be-fullstack.md) | the four shapes from §4, as working CI pipelines |
| [`../07-SCENARIOS-ci-cd-deployments.md`](../07-SCENARIOS-ci-cd-deployments.md) | the single-file narrative version of this folder |
| [`../../docker-learning-path/`](../../docker-learning-path/) | where the images come from |
| [`../../kubernetes-learning-path/`](../../kubernetes-learning-path/) | where the manifests come from |

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish_Kumar_Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn: https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260
🔗 GitHub: https://github.com/3558Bhk

*Four toolchains differ in three ways. The artifact contract never differs at all.*

</div>
