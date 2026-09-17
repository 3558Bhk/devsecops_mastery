# 🎓 `09` — TOOL MASTERY · ONE FOLDER PER CI/CD TOOL
### Jenkins · GitHub Actions · Azure DevOps — each a **complete, self-contained course**: install → fundamentals → all three scenarios → all six projects (including MERN) → troubleshooting → tasks.

> **Why this folder exists when `08-SCENARIO-DEPLOYMENTS/` already does:**
> `08` is organised **scenario-first** — it answers *"what is CI-only, and how do the three tools each do it?"* That is the **comparison** view, and it is the right view for interviews.
> This folder is organised **tool-first** — it answers *"I have chosen Jenkins. Teach me all of Jenkins."* That is the **mastery** view, and it is the right view for actually running one of these in production.
>
> ⭐ **Neither replaces the other.** Read `08` to understand the three scenarios; live in one folder here to become dangerous in one tool.

---

## 📂 The three tool folders

| Folder | Tool | Files | ⭐ What makes this tool worth mastering | Verdict for the `shop` estate |
|---|---|---|---|---|
| [`jenkins/`](./jenkins/) | 🔨 **Jenkins LTS 2.568.3** | 8 | The only one where **you own everything** — so it is the only one that teaches you what a CI system actually *is*. Dynamic Kubernetes agents, folder-scoped credentials, Kaniko without a Docker socket, shared libraries in Groovy | **Case 3** in the CI/CD path. Choose it for on-prem, air-gapped, extreme customisation, or legacy integration |
| [`github-actions/`](./github-actions/) | 🐙 **GitHub Actions** | 8 | The largest ecosystem on earth (30 000+ actions) and ⭐ the best **keyless** story: OIDC to GHCR, to the cluster, and to cosign — no long-lived secret anywhere | **Case 2** in the CI/CD path. Choose it when your code is on GitHub |
| [`azure-devops/`](./azure-devops/) | 🔷 **Azure DevOps** | 8 | ⭐ The best **built-in governance**: Environments + Approvals + Checks, Workload Identity Federation, and a compile-time template system that is stricter than anything the other two have | **Case 1** in the CI/CD path. Choose it for a Microsoft/Azure shop that wants Boards + Repos + Pipelines together |

### The identical file layout in all three folders

```
<tool>/
├── README.md                              ← the course map + one line per file
├── 00-INSTALL-AND-FUNDAMENTALS.md         ← get it running, then the 8 concepts
├── 01-SCENARIO-1-CI-ONLY.md               ← ① build · test · scan · sign · publish → STOP
├── 02-SCENARIO-2-CASE-1-DELIVERY.md       ← ②🔒 deploy an existing digest, HUMAN approval gate
├── 03-SCENARIO-2-CASE-2-DEPLOYMENT.md     ← ②🤖 deploy an existing digest, FULLY automatic
├── 04-SCENARIO-3-CI-PLUS-CD.md            ← ③ commit → production, end to end
├── 05-PROJECT-DEPLOYMENTS.md              ← all SIX projects, one section each
└── 06-TASKS-AND-INTERVIEW.md              ← tasks + ⭐ answers at the END
```

⭐ **Same eight files, same order, same section numbering in all three.** That is deliberate: when you have done one folder, the other two are a diff, not a new course — and being able to say *exactly* what differs is the senior interview answer.

---

## 🧩 The six projects every tool folder deploys

| # | Project | Shape | Stack | Why it is in the curriculum |
|---|---|---|---|---|
| 1 | `shop-ui` | **A** — FE only | React 19 + nginx | ⭐ runtime config, cache headers, bundle gates |
| 2 | `static-site` | **A** — FE only | nginx + HTML | the minimal version of shape A |
| 3 | `shop-api` | **B** — BE only | Java 21 + Spring Boot | ⭐⭐ Testcontainers, Flyway, the JVM warm-up |
| 4 | `checkout` · `payment-mock` | **B** — BE only | Go 1.25 | ⭐ `scratch` images, `-race`, `govulncheck` |
| 5 | `order-worker` | **B** — BE only | Python 3.13 | ⭐ a queue consumer: no HTTP, heartbeat readiness |
| 6 | `shop-ui` + `shop-api` | **C** — FE+BE, one stack | React + Java | ⭐⭐ version skew, expand/contract, contract tests |
| 7 | `shop-ui` + `order-worker` + `checkout` + `payment-mock` | **D** — FE+BE, different languages | React + Go + Python | ⭐ fan-out CI, dependency order, protobuf |
| 8 | **`shop-mern`** | ⭐⭐ **E — MERN** | React 19 + Node 24 + Express 5 + MongoDB 8 | **the stateful database is INSIDE the release** |

**The MERN project spec lives in one place, tool-agnostic:** [`../08-SCENARIO-DEPLOYMENTS/01-MERN-STACK-PROJECT.md`](../08-SCENARIO-DEPLOYMENTS/01-MERN-STACK-PROJECT.md). Every tool folder deploys *that* spec, so the three implementations are genuinely comparable.

⭐ **The MERN *application* is already built — do not rebuild it here:** [`docker-learning-path/17-PROJECT-14-mern-stack.md`](../../docker-learning-path/17-PROJECT-14-mern-stack.md) (**Docker P14** — images, Compose, the replica set, migrations, backups) and [`kubernetes-learning-path/18-PROJECT-15-mern-stack.md`](../../kubernetes-learning-path/18-PROJECT-15-mern-stack.md) (**K8s P15** — the StatefulSet, the gated migration Job, the backup CronJob, the three-probe split). **These folders build pipelines around those two projects.** ⛔ If you have not done P14/P15, the `05-PROJECT-DEPLOYMENTS.md` shape-E section will not make sense.

### ⭐ Shape E is the one that is actually new

| | Shapes A–D | ⭐ Shape E (MERN) |
|---|---|---|
| The database | **outside** the release (P13, deployed separately) | **inside** the release |
| The schema | enforced by the database | ⛔ enforced by the **application** |
| The migration ledger | Flyway / Alembic provide one | ⛔ **you build one** (`migrate-mongo`) |
| The rollback | image rollback (+ the schema caveat) | image rollback **+ a data restore** |
| CI infrastructure | Postgres / RabbitMQ | ⭐ a real **mongod replica set** |
| The contract test | `openapi-diff` + codegen + a drift gate | ⭐ **`tsc -b`** — one language, one shared package |

> *"The toolchain got easier and the data got harder, at the same time."* — the sentence that defines shape E.

---

## 🔁 The three scenarios, restated

| | Scenario | The one rule that defines it | What must NOT exist |
|---|---|---|---|
| **①** | **CI only** | Build it, prove it, publish a **digest** — then **stop** | ⛔ any credential that could deploy. "Cannot deploy" must be a **fact**, not an intention |
| **② 🔒** | **CD only — Case 1, Continuous *Delivery*** | The artifact already exists; every build is **deployable**; a **human** presses the button | ⛔ a build step. The pipeline must not be able to produce the artifact it deploys |
| **② 🤖** | **CD only — Case 2, Continuous *Deployment*** | Every green build goes to production **automatically**; the human is replaced by smoke gates, canary analysis and auto-rollback | ⛔ a human in the path — and ⛔ any of the five prerequisites being unmet |
| **③** | **CI + CD both** | The whole path, per application shape | ⛔ one pipeline holding both credentials |

⭐⭐ **The invariant that runs through all 28 files in `08` and all 24 here:**

> **The artifact that leaves CI is byte-for-byte the artifact that CD deploys — and you prove it with a digest, not a tag.**

**The four checks that make that a fact rather than a hope:**

| # | Check | Where |
|---|---|---|
| 1 | **Is it a digest?** `@sha256:[0-9a-f]{64}`, never `:latest`, never `:v1.2.3` | CD input validation |
| 2 | **Provenance** — `cosign verify`, pinned to the CI workflow on `main` | before anything deploys |
| 3 | **Did *staging* run this exact digest?** | read from the cluster, not from a variable |
| 4 | ⭐ **Read it back from the cluster** with a JSONPath **name filter** | after the rollout — `[?(@.name=='svc')]`, never `[0]` |

---

## 🗺️ Which folder should you be in?

```
"I want to understand CI vs CD and compare the three tools."
   → ../08-SCENARIO-DEPLOYMENTS/            (scenario-first, 28 files)

"I have Jenkins at work and I need to be excellent at it."
   → ./jenkins/                              (tool-first, 8 files)

"I'm interviewing and they use GitHub Actions."
   → ./github-actions/

"My company is a Microsoft shop."
   → ./azure-devops/

⭐ "I want to be hireable anywhere."
   → do ONE tool folder end to end (Jenkins is the hardest and teaches the
     most), then read the other two folders' `06-TASKS-AND-INTERVIEW.md`
     and the diff tables in `08`. That is ~40 hours, and it is the
     difference between "I've used Jenkins" and "I can migrate you off it."
```

### ⭐ The recommended order

| Step | Do | Why |
|---|---|---|
| 1 | [`../08-SCENARIO-DEPLOYMENTS/README.md`](../08-SCENARIO-DEPLOYMENTS/README.md) + [`00-PROJECT-INVENTORY.md`](../08-SCENARIO-DEPLOYMENTS/00-PROJECT-INVENTORY.md) | know what you are shipping before you learn to ship it |
| 2 | [`../08-SCENARIO-DEPLOYMENTS/01-MERN-STACK-PROJECT.md`](../08-SCENARIO-DEPLOYMENTS/01-MERN-STACK-PROJECT.md) | ⭐ the new shape, tool-agnostic |
| 3 | [`../08-SCENARIO-DEPLOYMENTS/scenario-2-cd-only/00-delivery-vs-deployment.md`](../08-SCENARIO-DEPLOYMENTS/scenario-2-cd-only/00-delivery-vs-deployment.md) | ⭐⭐ Delivery ≠ Deployment, and the five prerequisites |
| 4 | **one** tool folder, files `00` → `06` in order | mastery |
| 5 | the other two folders' `06-TASKS-AND-INTERVIEW.md` | the comparison, which is where the interview value is |
| 6 | [`../08-SCENARIO-DEPLOYMENTS/scenario-3-ci-plus-cd/08-gitops-argocd.md`](../08-SCENARIO-DEPLOYMENTS/scenario-3-ci-plus-cd/08-gitops-argocd.md) | the end state, whatever tool you chose |

---

## ⚖️ The three tools, one honest table

| | 🔨 Jenkins | 🐙 GitHub Actions | 🔷 Azure DevOps |
|---|---|---|---|
| **Config language** | Groovy (declarative or scripted) | YAML | YAML |
| **Unit of reuse** | ⭐ **shared library** (`vars/*.groovy`) | ⭐ **reusable workflow** (`workflow_call`) + composite action | ⭐ **template** (`templates/*.yml`) |
| **Where it runs** | your agents — ⭐ dynamic Kubernetes pods | GitHub-hosted or self-hosted runners | Microsoft-hosted or self-hosted agents |
| **Secrets** | credentials store + plugins | ⭐⭐ **OIDC federation** (no secret at all) | ⭐⭐ **Workload Identity Federation** |
| **Approval gates** | ⛔ none built in — `input` step + Lockable Resources | Environments + required reviewers | ⭐⭐ **Environments + Approvals + Checks** (the richest) |
| **Triggering another pipeline** | `build job: '/folder/job'` — ⭐ absolute path | `workflow_run` — ⛔ four well-known traps | ⭐ `resources.pipelines.trigger` — the cleanest of the three |
| **Building an image** | ⛔ **no Docker socket** → ⭐ **Kaniko** | `docker/build-push-action@v6` + BuildKit | `Docker@2` or BuildKit |
| **Change detection** | `changeset` condition / `git diff` | ⭐ `dorny/paths-filter@v3` | `paths:` filters (per pipeline) |
| **Looping at runtime** | ✅ Groovy — anything | ✅ `matrix` | ⛔ **templates are compile-time** — a runtime list cannot loop |
| **Multi-tenant isolation** | ⭐⭐ **folders** with folder-scoped credentials | repositories + environments | ⭐ **projects** + service connections |
| **Audit trail** | build logs (rotate) → ⭐ write your own JSONL | ⭐ run logs, 90 days on private repos | ⭐ release logs + Boards integration |
| **Ecosystem** | 1 800+ plugins — ⛔ and every one is attack surface | ⭐ 30 000+ actions | Microsoft-first, Boards/Repos/Artifacts/Test Plans |
| **Ops burden** | ⭐⭐ **you own everything** | none (SaaS) | none (SaaS) |
| **Cost model** | free software; ⛔ you pay in ops | free for public repos; minutes for private | free tier + parallel-job minutes |
| **Version anchor** | ⭐ **LTS 2.568.3, Java 21 minimum** | `checkout@v7`, `setup-java@v5`, `setup-node@v6`, `setup-go@v6`, `setup-python@v6` | SaaS, continuously released |
| **Best when** | on-prem, air-gapped, extreme customisation, legacy | your code is on GitHub | you are a Microsoft/Azure shop |

⭐⭐ **The one architectural difference that explains most of the others:**

```
Jenkins has NO built-in concept of "an environment you may not deploy to".
   → so you BUILD one, out of FOLDERS and CREDENTIAL SCOPE.
     /shop-ci  holds the registry-push credential and NOTHING else.
     /shop-cd  holds the cluster credential and NOTHING else.
     ⭐ The boundary is not a policy. It is a filesystem fact.

GitHub and Azure DevOps both HAVE that concept (environments).
   → so the boundary is a POLICY you configure, and the risk is that
     someone widens it. Which is why both folders here spend a section on
     the permission map, and on proving the CI side genuinely cannot deploy.
```

**The honest summary:** GitHub Actions has the best developer experience and the largest ecosystem. Azure DevOps has the best built-in governance. Jenkins has the most flexibility and the highest total cost of ownership. ⭐ **Knowing when NOT to use each one is the senior skill.**

---

## 🧰 Shared infrastructure — identical for all three tools

Nothing in this folder depends on which tool you pick. These exist once:

| Thing | Value |
|---|---|
| **Cluster** | `kind`, cluster name `cicd` (works unchanged on AKS/EKS/GKE) |
| **Namespaces** | `shop-dev` · `shop-staging` · `shop-production` · `shop-canary` · `shop-config` |
| **Registries** | `ghcr.io/3558bhk/<svc>` · `shopacr.azurecr.io/<svc>` |
| **Services & ports** | `shop-ui` 80 · `shop-api` 8080 · `checkout` 9091 · `order-worker` 9092 · `payment-mock` 9093 · `mern-web` 80 · `mern-api` 4000 · `mern-mongo` 27017 |
| **Data tier** | Postgres 5432 · Redis 6379 · RabbitMQ 5672 · MongoDB 27017 |
| **Artifact contract** | ⭐⭐ a **digest** — `@sha256:[0-9a-f]{64}` |
| **Signing** | `cosign`, keyless via OIDC where the tool supports it |
| **Scanning** | Trivy (image) · language-specific: `dependency-check` / `govulncheck` / `pip-audit` / `npm audit` |
| **GitOps target** | Argo CD 3.x — [`../08-SCENARIO-DEPLOYMENTS/scenario-3-ci-plus-cd/08-gitops-argocd.md`](../08-SCENARIO-DEPLOYMENTS/scenario-3-ci-plus-cd/08-gitops-argocd.md) |
| **Helm** | 3.19 — charts take `image.digest`, ⛔ never `image.tag` |

---

## 🔗 Related folders

| Path | What it gives you |
|---|---|
| [`../08-SCENARIO-DEPLOYMENTS/`](../08-SCENARIO-DEPLOYMENTS/) | ⭐ the **scenario-first** view — 28 files comparing all three tools per scenario |
| [`../01-CICD-GUIDE.md`](../01-CICD-GUIDE.md) | every CI/CD concept from absolute zero — **read this first if you are a beginner** |
| [`../02-CASE-1-azure-devops.md`](../02-CASE-1-azure-devops.md) · [`../03-CASE-2-github-actions.md`](../03-CASE-2-github-actions.md) · [`../04-CASE-3-jenkins.md`](../04-CASE-3-jenkins.md) | the three tool deep-dives from the core path |
| [`../../docker-learning-path/`](../../docker-learning-path/) | the containers you are shipping (P1–P13) |
| [`../../kubernetes-learning-path/`](../../kubernetes-learning-path/) | the manifests you are deploying to (P1–P14) |
| [`../../monitoring-alerting-learning-path/`](../../monitoring-alerting-learning-path/) | ⭐ the Prometheus signals that decide whether a 🤖 Case 2 canary promotes |

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish_Kumar_Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn: https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260
🔗 GitHub: https://github.com/3558Bhk

*Folder 08 teaches you the three scenarios. This folder teaches you one tool well enough to migrate a company off it.*

</div>
