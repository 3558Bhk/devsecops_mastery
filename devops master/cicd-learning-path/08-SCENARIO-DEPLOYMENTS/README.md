# 🔀 FOLDER 08 — SCENARIO DEPLOYMENTS
### Deploying everything you built in the Docker & Kubernetes paths — frontend, backend, frontend+backend, and the polyglot stacks — through **all three CI/CD tools**, in **three scenarios**, in **separate folders and files**.

> **This folder is the "so how do I actually ship it?" folder.**
>
> File `07-SCENARIOS-ci-cd-deployments.md` proved the three scenarios work in one long document. This folder takes the same material and **reorganises it the way you will actually use it**: one folder per scenario, one file per tool, one file per application shape. You open the folder for the scenario you are in, the file for the tool you have, and the section for the app you are shipping.
>
> **Scenarios:** ① **CI only** · ② **CD only** (Case 1 *Continuous Delivery* / Case 2 *Continuous Deployment*) · ③ **CI + CD both**
> **Tools:** 🐙 GitHub Actions · 🔷 Azure DevOps · 🔨 Jenkins
> **Apps:** `shop-ui` (React) · `shop-api` (Java 21) · `checkout` (Go) · `order-worker` (Python) · `payment-mock` (Go) · ⭐ **`shop-mern` (React + Node + Express + MongoDB)** · the P13 data tier
> **Targets:** 🐳 Docker / Compose · ☸️ Kubernetes (kind → real cluster) · ☁️ a managed cluster

> ⭐ **Two views of the same material.** This folder is organised **scenario-first** — the *comparison* view, and the right one for interviews. [`../09-TOOL-MASTERY/`](../09-TOOL-MASTERY/) is organised **tool-first** (`jenkins/`, `github-actions/`, `azure-devops/`) — the *mastery* view, where each tool is a complete self-contained course covering all three scenarios and all six projects. Neither replaces the other.

---

## 📁 The folder tree — 29 files

```
08-SCENARIO-DEPLOYMENTS/
│
├── README.md                              ← you are here. the index
├── 00-PROJECT-INVENTORY.md                ← which Docker/K8s project becomes which pipeline
├── 01-MERN-STACK-PROJECT.md               ← ⭐⭐ SHAPE E: the MERN stack, tool-agnostic
│
├── scenario-1-ci-only/                    ① build, test, publish. STOP. no deploy.
│   ├── README.md
│   ├── 01-github-actions-ci.md
│   ├── 02-azure-devops-ci.md
│   ├── 03-jenkins-ci.md
│   └── 04-app-shapes-fe-be-fullstack.md
│
├── scenario-2-cd-only/                    ② an artifact already exists. ship it.
│   ├── README.md
│   ├── 00-delivery-vs-deployment.md       ← ⭐ the distinction that names the two cases
│   │
│   ├── case-1-continuous-delivery/        ← every change is DEPLOYABLE; a human decides
│   │   ├── README.md
│   │   ├── 01-github-actions-delivery.md
│   │   ├── 02-azure-devops-delivery.md
│   │   ├── 03-jenkins-delivery.md
│   │   └── 04-docker-and-k8s-targets.md
│   │
│   └── case-2-continuous-deployment/      ← every change that passes IS deployed. no human.
│       ├── README.md
│       ├── 01-github-actions-deployment.md
│       ├── 02-azure-devops-deployment.md
│       ├── 03-jenkins-deployment.md
│       └── 04-docker-and-k8s-targets.md
│
└── scenario-3-ci-plus-cd/                 ③ the whole path, commit → production
    ├── README.md
    ├── 01-github-actions-full.md
    ├── 02-azure-devops-full.md
    ├── 03-jenkins-full.md
    ├── 04-fe-only.md
    ├── 05-be-only.md
    ├── 06-fe-plus-be-same-stack.md
    ├── 07-fe-plus-be-different-langs.md
    └── 08-gitops-argocd.md
```

---

## 📇 Every file, one line each

### Root

| File | One line |
|---|---|
| [`README.md`](./README.md) | The index — the folder tree, this table, the reading order, and how to pick a scenario in 30 seconds |
| [`00-PROJECT-INVENTORY.md`](./00-PROJECT-INVENTORY.md) | ⭐ **Read this first.** Maps all 13 Docker projects and all 14 Kubernetes projects to the exact pipeline that ships them, with ports, images, health endpoints and the file in this folder that covers each |
| [`01-MERN-STACK-PROJECT.md`](./01-MERN-STACK-PROJECT.md) | ⭐⭐ **Shape E — the MERN stack.** React 19 + Node 24 + Express 5 + MongoDB 8, as an npm-workspaces monorepo with a `packages/shared` contract package. The one shape where **the stateful database ships inside the release**: no Flyway (you build the ledger with `migrate-mongo`), no database-level schema (Mongoose enforces it, so two app versions write to one collection during a rollout), a real **mongod replica set** in CI because transactions require one, and a **verified backup as the only rollback**. Tool-agnostic — every tool folder deploys *this* spec |

### ① `scenario-1-ci-only/` — build, test, publish, **stop**

| File | One line |
|---|---|
| [`README.md`](./scenario-1-ci-only/README.md) | What CI-only means, when it is the *right* answer (not a half-built pipeline), and the five things that prove your pipeline really is CI-only |
| [`01-github-actions-ci.md`](./scenario-1-ci-only/01-github-actions-ci.md) | 🐙 CI-only workflows for all five apps — path filters, matrix builds, `actions/cache`, layer caching, OIDC push to GHCR, digest output, and the `permissions:` lockdown |
| [`02-azure-devops-ci.md`](./scenario-1-ci-only/02-azure-devops-ci.md) | 🔷 CI-only YAML — reusable templates, `vmImage`, Maven/npm/Go cache tasks, Workload Identity Federation to ACR, and publishing the digest as a pipeline artifact |
| [`03-jenkins-ci.md`](./scenario-1-ci-only/03-jenkins-ci.md) | 🔨 CI-only declarative Jenkinsfile — dynamic Kubernetes agents, per-language tool containers, credential scoping, and why a CI job must never hold a prod credential |
| [`04-app-shapes-fe-be-fullstack.md`](./scenario-1-ci-only/04-app-shapes-fe-be-fullstack.md) | ⭐ The four application shapes side by side — FE only, BE only, FE+BE monorepo, polyglot — with the CI differences that actually matter for each |

### ② `scenario-2-cd-only/` — an artifact already exists

| File | One line |
|---|---|
| [`README.md`](./scenario-2-cd-only/README.md) | What CD-only means, the artifact contract (a **digest**, never a tag), and how the two cases differ in one sentence each |
| [`00-delivery-vs-deployment.md`](./scenario-2-cd-only/00-delivery-vs-deployment.md) | ⭐⭐ **The most important file in this folder.** Continuous **Delivery** vs continuous **Deployment** — the exact difference, why companies say one and mean the other, the org consequences, and how to tell which one you have from the pipeline alone |

#### Case 1 — Continuous *Delivery* (a human presses the button)

| File | One line |
|---|---|
| [`README.md`](./scenario-2-cd-only/case-1-continuous-delivery/README.md) | The delivery model end to end — what "always deployable" commits you to, and the audit trail you must be able to produce |
| [`01-github-actions-delivery.md`](./scenario-2-cd-only/case-1-continuous-delivery/01-github-actions-delivery.md) | 🐙 `workflow_dispatch` + `environment:` protection rules + required reviewers, and the `wait` job that makes the approval gate visible in the UI |
| [`02-azure-devops-delivery.md`](./scenario-2-cd-only/case-1-continuous-delivery/02-azure-devops-delivery.md) | 🔷 Environments + Approvals + Checks — the best built-in gate of the three tools, plus deployment pools, branch validation and business-hours windows |
| [`03-jenkins-delivery.md`](./scenario-2-cd-only/case-1-continuous-delivery/03-jenkins-delivery.md) | 🔨 The `input` step with `ok`/`submitter`/`parameters`, `milestone` + `lock` for mutual exclusion, and how to make an approval auditable |
| [`04-docker-and-k8s-targets.md`](./scenario-2-cd-only/case-1-continuous-delivery/04-docker-and-k8s-targets.md) | The actual promote step for both targets — `docker compose` pull-and-up on a VM, and `kubectl set image` / Helm / Kustomize on a cluster |

#### Case 2 — Continuous *Deployment* (nobody presses anything)

| File | One line |
|---|---|
| [`README.md`](./scenario-2-cd-only/case-2-continuous-deployment/README.md) | What you must have *before* you are allowed to remove the human — the five prerequisites, and the honest cost |
| [`01-github-actions-deployment.md`](./scenario-2-cd-only/case-2-continuous-deployment/01-github-actions-deployment.md) | 🐙 Fully automated promotion with the safety net that replaces the human — smoke gates, canary analysis, and `rollbacks` as a first-class job |
| [`02-azure-devops-deployment.md`](./scenario-2-cd-only/case-2-continuous-deployment/02-azure-devops-deployment.md) | 🔷 Auto-promotion between stages with deployment gates that query Application Insights / Prometheus instead of asking a person |
| [`03-jenkins-deployment.md`](./scenario-2-cd-only/case-2-continuous-deployment/03-jenkins-deployment.md) | 🔨 Unattended deploy with `when` guards, a quality gate stage, and automatic rollback wired to the health probe |
| [`04-docker-and-k8s-targets.md`](./scenario-2-cd-only/case-2-continuous-deployment/04-docker-and-k8s-targets.md) | Rolling, blue-green and canary on both targets — the exact manifests, the readiness math, and how to verify the rollout actually converged |

### ③ `scenario-3-ci-plus-cd/` — commit → production

| File | One line |
|---|---|
| [`README.md`](./scenario-3-ci-plus-cd/README.md) | The full-path model, the CI/CD boundary and where to draw it, and the one diagram that explains all three tools' shapes |
| [`01-github-actions-full.md`](./scenario-3-ci-plus-cd/01-github-actions-full.md) | 🐙 One repo, CI workflow → artifact → CD workflow, joined by a digest; reusable workflows, OIDC, environments, and the concurrency groups that stop two deploys racing |
| [`02-azure-devops-full.md`](./scenario-3-ci-plus-cd/02-azure-devops-full.md) | 🔷 A single multi-stage YAML pipeline (build → dev → staging → prod) with templates, variable groups, Key Vault and per-stage approvals |
| [`03-jenkins-full.md`](./scenario-3-ci-plus-cd/03-jenkins-full.md) | 🔨 One Jenkinsfile with an agent-per-stage, a shared library for the repeated parts, and multibranch + `when { changeset }` to skip untouched services |
| [`04-fe-only.md`](./scenario-3-ci-plus-cd/04-fe-only.md) | ⭐ **Frontend only** — Docker P8 / K8s P8 `shop-ui`: build, Lighthouse, bundle-size gate, nginx image, CDN vs in-cluster, and cache-busting that cannot break a live session |
| [`05-be-only.md`](./scenario-3-ci-plus-cd/05-be-only.md) | ⭐ **Backend only** — Docker P9 / K8s P9 `shop-api`: Maven build, testcontainers, JVM-in-a-container flags, migration ordering, and zero-downtime Spring Boot rollouts |
| [`06-fe-plus-be-same-stack.md`](./scenario-3-ci-plus-cd/06-fe-plus-be-same-stack.md) | ⭐⭐ **FE + BE together** — Docker P10 / K8s P10 React+Java: the two pipelines, the contract between them, and ⭐ the FE↔BE **version-skew** problem with all four defences |
| [`07-fe-plus-be-different-langs.md`](./scenario-3-ci-plus-cd/07-fe-plus-be-different-langs.md) | ⭐⭐ **Polyglot** — Docker P11/P12, K8s P11/P12 React+Python and React+Go: one pipeline, four toolchains, per-language caching, and why the *image contract* is the only thing that stays constant |
| [`08-gitops-argocd.md`](./scenario-3-ci-plus-cd/08-gitops-argocd.md) | ⭐⭐ **The handoff** — where push-based CD ends and GitOps begins: Argo CD, the config repo, image-updater, drift detection, and K8s P14's Helm charts driven by a pipeline |

---

## 🧭 How to use this folder

### The 30-second scenario picker

| Your situation | Scenario | Folder |
|---|---|---|
| "We build and test on every commit, but a human runs the deploy" | ① CI only | [`scenario-1-ci-only/`](./scenario-1-ci-only/) |
| "The build happens somewhere else; I just need to promote an artifact" | ② CD only | [`scenario-2-cd-only/`](./scenario-2-cd-only/) |
| "…and a person approves each promotion" | ②·1 **Delivery** | [`case-1-continuous-delivery/`](./scenario-2-cd-only/case-1-continuous-delivery/) |
| "…and it goes to production automatically if the tests pass" | ②·2 **Deployment** | [`case-2-continuous-deployment/`](./scenario-2-cd-only/case-2-continuous-deployment/) |
| "I want the whole thing, commit to production, in one repo" | ③ CI + CD | [`scenario-3-ci-plus-cd/`](./scenario-3-ci-plus-cd/) |
| "I don't know which one my company actually has" | — | ⭐ [`00-delivery-vs-deployment.md`](./scenario-2-cd-only/00-delivery-vs-deployment.md) §7 tells you from the pipeline alone |
| ⭐ "My app is MERN — React, Node, Express, MongoDB" | any | [`01-MERN-STACK-PROJECT.md`](./01-MERN-STACK-PROJECT.md) first — **shape E**, the one where the database ships inside the release |
| ⭐ "I've picked one tool and want to master it completely" | all three | [`../09-TOOL-MASTERY/`](../09-TOOL-MASTERY/) — one folder per tool, all scenarios, all six projects |

### The five application shapes

| Shape | Example | ⭐ The one thing that defines it |
|---|---|---|
| **A** — FE only | `shop-ui`, `static-site` | config must be injected at **runtime**, or you build four images |
| **B** — BE only | `shop-api`, `checkout`, `order-worker`, `payment-mock` | real infrastructure in CI, and a **schema you cannot roll back** |
| **C** — FE+BE, one stack | React + Java | ⭐⭐ **version skew** — the browser holds yesterday's frontend for hours |
| **D** — FE+BE, different languages | React + Go + Python | a **dependency graph** decides deploy order; HTTP and queues order *oppositely* |
| **E** — MERN | ⭐ `shop-mern` | **the stateful database is inside the release**, and nothing enforces the schema but your app |

### The reading order

```
00-PROJECT-INVENTORY.md      ← know exactly which app you are shipping
        │
01-MERN-STACK-PROJECT.md     ← if any of it is MERN (shape E)
        │
00-delivery-vs-deployment.md ← know which of the two CD cases you mean
        │
        ├──▶ scenario-1-ci-only/          if you are building the CI half
        ├──▶ scenario-2-cd-only/          if you are building the CD half
        └──▶ scenario-3-ci-plus-cd/       if you are building both
                 │
                 └── 04 → 05 → 06 → 07    by application shape
                          │
                          └── 08-gitops-argocd.md   when you outgrow push-CD
```

⭐ **Within each scenario folder, read the tool file for the tool you have.** The three tool files are *parallel*, not sequential — they solve the same problem three ways. Read all three only if you are preparing for the "we're migrating from Jenkins to GitHub Actions, what breaks?" interview question, which is the single most common senior CI/CD question and the reason this path teaches all three.

---

## 🧱 The continuity contract

Every file in this folder uses the **same names, ports and image paths** as the Docker, Kubernetes, Monitoring and CI/CD paths. Nothing is renamed for convenience.

| Service | Language | Port | Image | Source project |
|---|---|---|---|---|
| `shop-ui` | React 19 + nginx | 80 | `ghcr.io/3558bhk/shop-ui` | Docker P8 · K8s P8 |
| `shop-api` | Java 21 + Spring Boot | 8080 (+ metrics) | `ghcr.io/3558bhk/shop-api` | Docker P9 · K8s P9 |
| `checkout` | Go 1.23 | 9091 | `ghcr.io/3558bhk/checkout` | Docker P12 · K8s P12 |
| `order-worker` | Python 3.13 | 9092 | `ghcr.io/3558bhk/order-worker` | Docker P11 · K8s P11 |
| `payment-mock` | Go 1.23 | 9093 | `ghcr.io/3558bhk/payment-mock` | Docker capstone |
| data tier | Postgres 17 · Redis 7 · RabbitMQ 4 | 5432 / 6379 / 5672 | upstream images | Docker P13 · K8s P13 |
| ⭐ `mern-web` | React 19 + nginx | 80 | `ghcr.io/3558bhk/mern-web` | **shape E** — [`01-MERN-STACK-PROJECT.md`](./01-MERN-STACK-PROJECT.md) |
| ⭐ `mern-api` | Node 24 + Express 5 + Mongoose 8 | 4000 | `ghcr.io/3558bhk/mern-api` | **shape E** |
| ⭐⭐ `mern-mongo` | MongoDB 8.0 | 27017 | `mongo@sha256:…` (pinned) | **shape E** — a StatefulSet, inside the release |

| Thing | Value |
|---|---|
| Registries | `ghcr.io/3558bhk/<svc>` · `shopacr.azurecr.io/<svc>` · `localhost:5000` (offline) |
| Namespaces | `shop-dev` · `shop-staging` · `shop-production` · `shop-config` |
| Local cluster | `kind` cluster named **`cicd`** |
| Artifact contract | ⭐⭐ **the image digest** — `sha256:…`, never a mutable tag |
| Version anchors | Jenkins **LTS 2.568.3** (Java 21 min) · `actions/checkout@v7`, `setup-java@v5`, `ubuntu-latest` = Ubuntu 24.04 · Azure DevOps SaaS · Argo CD 3.x |

---

## ⭐ The one rule this whole folder exists to teach

> **The artifact that leaves CI and the artifact that CD deploys must be provably the same bytes.**
>
> Not "the same tag". Not "a rebuild from the same commit". **The same digest.**

Every scenario, every tool, every application shape in these 29 files is a variation on enforcing that one sentence. When a pipeline rebuilds the image in the deploy stage, you do not have continuous delivery — you have two builds and a hope. [`00-delivery-vs-deployment.md`](./scenario-2-cd-only/00-delivery-vs-deployment.md) §3 shows you how to check yours in about ninety seconds.

---

## Related

| Where | What |
|---|---|
| ⭐⭐ [`../09-TOOL-MASTERY/`](../09-TOOL-MASTERY/) | **The tool-first view.** Three folders — `jenkins/`, `github-actions/`, `azure-devops/` — each a complete self-contained course (install → fundamentals → all three scenarios → all six projects → tasks). This folder compares the tools; that one masters one |
| [`../07-SCENARIOS-ci-cd-deployments.md`](../07-SCENARIOS-ci-cd-deployments.md) | The single-file version of these three scenarios — read it for the narrative; use this folder for the work |
| [`../01-CICD-GUIDE.md`](../01-CICD-GUIDE.md) | Every CI/CD concept from absolute zero. Read before this folder if any of it is unfamiliar |
| [`../02-CASE-1-azure-devops.md`](../02-CASE-1-azure-devops.md) · [`../03-CASE-2-github-actions.md`](../03-CASE-2-github-actions.md) · [`../04-CASE-3-jenkins.md`](../04-CASE-3-jenkins.md) | The deep tool-by-tool files — syntax, not scenarios |
| [`../05-CAPSTONE-END-TO-END.md`](../05-CAPSTONE-END-TO-END.md) | The capstone: one app, three tools, GitOps CD |
| [`../06-CHEATSHEET.md`](../06-CHEATSHEET.md) | All three tools on one page — keep it open |
| [`../../docker-learning-path/`](../../docker-learning-path/) | Where the applications come from (P1–P13) |
| [`../../kubernetes-learning-path/`](../../kubernetes-learning-path/) | Where the manifests come from (P1–P14, incl. Helm + GitOps) |
| [`../../monitoring-alerting-learning-path/`](../../monitoring-alerting-learning-path/) | What tells you the deploy worked — the gates in Case 2 query this |

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish_Kumar_Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn: https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260
🔗 GitHub: https://github.com/3558Bhk

*Three scenarios. Three tools. Five application shapes. One artifact contract: the digest.*

</div>
