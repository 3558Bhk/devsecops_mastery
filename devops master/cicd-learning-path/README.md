# 🚀 CI/CD — The Complete Learning Path

> **Three pipelines. One application. Every concept from "what is a build?" to a hardened, audited, progressive-delivery production pipeline.**
>
> **Case 1 — Azure DevOps** · **Case 2 — GitHub Actions** · **Case 3 — Jenkins**
>
> Written for a **complete beginner**, aimed at **3+ YOE DevOps/SRE interview mastery** and **real production work**.

---

## What this folder gives you

| # | File | What's in it | Time |
|---|---|---|---|
| 00 | [00-ONE-DAY-MASTER-PLAN.md](./00-ONE-DAY-MASTER-PLAN.md) | ⏰ Hour-by-hour plan — **all three cases**, plus a 3-day version | — |
| 01 | [01-CICD-GUIDE.md](./01-CICD-GUIDE.md) | 📖 **Read this first.** Every CI/CD concept from absolute zero | 3–4 h |
| 02 | [02-CASE-1-azure-devops.md](./02-CASE-1-azure-devops.md) | 🔷 **CASE 1 — Azure DevOps**: YAML pipelines, service connections, multi-stage, variable groups, Key Vault, Environments + approvals, self-hosted agents | 6–8 h |
| 03 | [03-CASE-2-github-actions.md](./03-CASE-2-github-actions.md) | 🐙 **CASE 2 — GitHub Actions**: workflows, OIDC, matrix, reusable workflows, composite actions, caching, environments, self-hosted runners, Dependabot, code scanning | 6–8 h |
| 04 | [04-CASE-3-jenkins.md](./04-CASE-3-jenkins.md) | 🔨 **CASE 3 — Jenkins**: K8s install, declarative Jenkinsfile, Kubernetes-plugin agents, shared libraries, credentials, multibranch, JCasC, plugin and security management | 6–8 h |
| 05 | [05-CAPSTONE-END-TO-END.md](./05-CAPSTONE-END-TO-END.md) | 🏆 **The capstone** — the same app through all three, plus GitOps, progressive delivery, security scanning, **5 tasks + answers at the END** | 6–8 h |
| 06 | [06-CHEATSHEET.md](./06-CHEATSHEET.md) | ⚡ Azure DevOps + GitHub Actions + Jenkins on **one page** — reference | — |
| 07 | [07-SCENARIOS-ci-cd-deployments.md](./07-SCENARIOS-ci-cd-deployments.md) | 🔀 **THE THREE SCENARIOS** — ① CI only · ② CD only (**Case 1 Continuous Delivery** / **Case 2 Continuous Deployment**) · ③ CI+CD — deploying the **Docker & K8s projects** (FE only / BE only / FE+BE / polyglot: React, Java, Go, Python) through **all three tools**, plus deploy strategies, rollback drills, **10 tasks + 12 Q&A + 8 interview answers at the END** | 8–10 h |
| **09** | [**09-TOOL-MASTERY/**](./09-TOOL-MASTERY/) | 🎓⭐⭐ **THE TOOL-FIRST VIEW — 3 folders, one per CI/CD tool, each a complete self-contained course.** `jenkins/` · `github-actions/` · `azure-devops/` — install → fundamentals → all three scenarios → all **six** projects (including MERN) → tasks + interview. Same 8 files, same order, same section numbering in all three, so the second and third are a *diff*, not a new course | 35 h **per tool** |
| **08** | [**08-SCENARIO-DEPLOYMENTS/**](./08-SCENARIO-DEPLOYMENTS/) | 📁⭐⭐ **THE SAME THREE SCENARIOS, SPLIT INTO SEPARATE FOLDERS & FILES — 28 files, ~20,200 lines.** This is `07` taken apart and built properly: one folder per scenario, one file per tool, one file per application shape, every pipeline complete and copy-pasteable. **Start here if you want to *run* it; read `07` if you want the narrative.** | 20–30 h |

**Read order:** `01` → `02` → `03` → `04` → `05` → **`07`** → **`08/`**, with `06` open beside you the whole time.

> ⭐ **`07` is the file that answers "so how do I actually deploy what I built?"** It takes the `shop-ui` / `shop-api` / `checkout` / `order-worker` / `payment-mock` apps from the Docker and Kubernetes paths and runs them through the three pipeline shapes every company uses — with the exact YAML/Groovy for Azure DevOps, GitHub Actions and Jenkins, the FE↔BE version-skew defences, canary analysis with automatic rollback, and the GitOps handoff.

### 📁 What is inside folder `08`

```
08-SCENARIO-DEPLOYMENTS/
├── README.md                         ← start here: the map of all 28 files
├── 00-PROJECT-INVENTORY.md           ← every Docker & K8s project → its pipeline
│
├── scenario-1-ci-only/            ①  BUILD, TEST, SCAN, SIGN, PUBLISH — THEN STOP
│   ├── README.md                       (5 files)
│   ├── 01-github-actions-ci.md
│   ├── 02-azure-devops-ci.md
│   ├── 03-jenkins-ci.md
│   └── 04-app-shapes-fe-be-fullstack.md
│
├── scenario-2-cd-only/            ②  THE ARTIFACT ALREADY EXISTS — ONLY DEPLOY IT
│   ├── README.md                       (12 files)
│   ├── 00-delivery-vs-deployment.md    ⭐ Delivery ≠ Deployment, and the 5 prerequisites
│   ├── case-1-continuous-delivery/     🔒 always-deployable + a HUMAN approval gate
│   │   ├── README.md · 01-github-actions-delivery.md · 02-azure-devops-delivery.md
│   │   ├── 03-jenkins-delivery.md · 04-docker-and-k8s-targets.md
│   └── case-2-continuous-deployment/   🤖 fully automatic — the human is replaced by gates
│       ├── README.md · 01-github-actions-deployment.md · 02-azure-devops-deployment.md
│       ├── 03-jenkins-deployment.md · 04-docker-and-k8s-targets.md
│
└── scenario-3-ci-plus-cd/         ③  COMMIT → PRODUCTION, END TO END
    ├── README.md                       (9 files)
    ├── 01-github-actions-full.md       two workflows, chained by workflow_run
    ├── 02-azure-devops-full.md         two pipelines, resources.pipelines + WIF
    ├── 03-jenkins-full.md              two FOLDERS — credential scope IS the boundary
    ├── 04-fe-only.md                   ⭐ runtime config: one image, every environment
    ├── 05-be-only.md                   ⭐ Testcontainers, migrations, the worker problem
    ├── 06-fe-plus-be-same-stack.md     ⭐⭐ version skew, expand/contract, contract tests
    ├── 07-fe-plus-be-different-langs.md ⭐ fan-out CI, dependency order, protobuf contracts
    └── 08-gitops-argocd.md             ⭐⭐ the end state — CI writes a digest to git
```

| Scenario | The one rule that defines it | Files |
|---|---|---|
| **① CI only** | Build it, prove it, publish a **digest** — and **stop**. No deploy credential exists, so "cannot deploy" is a *fact*, not an intention | 5 |
| **② CD only** | The artifact already exists. **Case 1 🔒 Delivery** = always deployable, a human presses the button. **Case 2 🤖 Deployment** = the human is replaced by smoke gates, canary analysis and auto-rollback | 12 |
| **③ CI+CD** | The whole path, per application shape — and one invariant throughout: **the artifact that leaves CI is byte-for-byte the artifact CD deploys, proven by digest** | 9 |

> ⭐⭐ **The sentence that holds all 28 files together:** *CI can push images but cannot deploy; CD can deploy but cannot publish.* That asymmetry is why Scenario 3 uses **two pipelines, never one** — and why GitOps (file `08-gitops-argocd.md`) is the strongest form of it, because there the deploy credential never leaves the cluster.
>
> **Version anchors used in folder 08:** Jenkins LTS 2.568.3 · `actions/checkout@v7`, `setup-java@v5`, `setup-node@v6`, `setup-go@v6` (Go 1.25.0), `setup-python@v6` (Python 3.13) · Argo CD 3.x · Kubernetes v1.37 "Garhwal" · Helm 3.19 · Java 21 / Spring Boot 3.5+ · React 19 / `nginx:1.29-alpine`. Ports: `shop-ui` 80 · `shop-api` 8080 · `checkout` 9091 · `order-worker` 9092 (no HTTP — a queue consumer) · `payment-mock` 9093 · data tier 5432/6379/5672.

---

## Why learn all three?

Because the interview question is never *"can you use Jenkins?"* It's:

> *"We're migrating from Jenkins to GitHub Actions. What breaks, what do you lose, and how do you prove the new pipeline is equivalent to the old one?"*

That question can only be answered by someone who has built the **same pipeline three ways** and knows exactly where each tool's abstractions differ. This path is built to give you that answer.

| | Azure DevOps | GitHub Actions | Jenkins |
|---|---|---|---|
| **Model** | Stages → Jobs → Steps | Jobs → Steps (+ reusable workflows) | Stages → Steps (Pipeline-as-code) |
| **Config language** | YAML | YAML | Groovy (declarative or scripted) |
| **Runs on** | Microsoft-hosted or self-hosted agents | GitHub-hosted or self-hosted runners | The controller or **dynamic Kubernetes agents** |
| **Secrets** | Variable groups, Key Vault, **Workload Identity Federation** (no secret at all) | Environments, secrets, **OIDC federation** | Credentials store, plugins |
| **Approval gates** | ⭐ Environments + Approvals + Checks (built-in, rich) | Environments + required reviewers | ⭐ `input` step / Lockable Resources / plugins |
| **Ecosystem** | Azure-native, Boards/Repos/Artifacts/Test Plans in one product | ⭐ The largest marketplace on earth (30,000+ actions) | ⭐ 1,800+ plugins; can integrate with literally anything |
| **Artifact registry** | Azure Artifacts (NuGet/npm/Maven/Python/Universal) | GitHub Packages / GHCR | Artifactory / Nexus via plugin |
| **Boards / issue tracking** | ⭐ Built in, best in class | GitHub Issues + Projects | None (integrates) |
| **Cost model** | Free tier + parallel-job minutes | ⭐ Free for public repos; minutes for private | Free software; **you pay for the ops** |
| **Ops burden** | None (SaaS) | None (SaaS) | ⭐⭐ **You own everything** — upgrades, plugins, security, disk |
| **Best when** | You're a Microsoft/Azure shop and want Boards+Pipelines+Repos together | Your code is on GitHub and you want the biggest ecosystem | You need on-prem, extreme customisation, legacy integration, or air-gapped |
| **Version anchor** | SaaS (continuously released) | `actions/checkout@v7`, `setup-java@v5`, `ubuntu-latest` = Ubuntu 24.04 | **LTS 2.568.3**, Java 21 minimum |

**The honest summary:** GitHub Actions has the best developer experience and the largest ecosystem. Azure DevOps has the best built-in governance (approvals, checks, boards). Jenkins has the most flexibility and the highest total cost of ownership. **Knowing when NOT to use each one is the senior skill.**

---

## The application you'll pipeline

The same `shop` app from the [Docker](../docker-learning-path/), [Kubernetes](../kubernetes-learning-path/) and [Monitoring](../monitoring-alerting-learning-path/) paths. **Continuity is the point** — by the end you can build it, ship it, deploy it, and observe it.

```
shop/
├── shop-ui/          React + nginx        → image → Deployment   (frontend)
├── shop-api/         Spring Boot 3, Java 21, Maven   → image → Deployment  (backend, port 8080, metrics 9090)
├── checkout/         Go 1.23                        → image → Deployment   (port 8080, metrics 9091)
├── order-worker/     Python 3.13                    → image → Deployment   (metrics 9092)
├── payment-mock/     Go 1.23                        → image → Deployment   (the chaos target)
├── helm/shop/        the Helm chart (values per environment)
└── k8s/              raw manifests (for the non-Helm exercises)
```

| Service | Language | Build tool | Test framework | Image |
|---|---|---|---|---|
| `shop-ui` | JavaScript (React) | npm | Vitest + Playwright | `ghcr.io/3558bhk/shop-ui` |
| `shop-api` | Java 21 | Maven | JUnit 5 + Testcontainers | `ghcr.io/3558bhk/shop-api` |
| `checkout` | Go 1.23 | go modules | `go test -race` | `ghcr.io/3558bhk/checkout` |
| `order-worker` | Python 3.13 | pip | pytest | `ghcr.io/3558bhk/order-worker` |
| `payment-mock` | Go 1.23 | go modules | `go test -race` | `ghcr.io/3558bhk/payment-mock` |

**Target environments:** `dev` → `staging` → `production`, with a manual approval gate before production in every case.

**Registry:** `ghcr.io/3558bhk/…` (GitHub) and `shopacr.azurecr.io` (Azure) — you'll wire both.

**Cluster:** `kind` locally (cluster name `cicd`), and the manifests work unchanged on AKS/EKS/GKE.

---

## What "done" looks like

After all three cases plus the capstone, you will have:

```
✅ THREE complete pipelines for the same repo — Azure DevOps, GitHub Actions, Jenkins —
   and a written comparison of what each one cost you in effort, minutes and risk
✅ Multi-stage pipelines: build → test → scan → package → deploy-dev → approve → deploy-prod
✅ Container images built with BuildKit, multi-stage, distroless, SBOM + provenance attested
✅ Trivy, Semgrep, CodeQL/Defender, gitleaks and dependency scanning as build-breaking gates
✅ Zero long-lived secrets anywhere: OIDC / Workload Identity Federation to every cloud
✅ Helm-based deployment with per-environment values, and a GitOps (Argo CD) variant
✅ Manual approval gates, deployment windows, and branch-protection rules
✅ Canary / blue-green progressive delivery with automatic analysis against Prometheus
✅ Self-hosted agents/runners/Jenkins-agents on Kubernetes, autoscaled
✅ Pipeline-as-code review: CODEOWNERS on the pipeline files, and CI that validates CI
✅ Caching that cuts build time measurably — with the numbers recorded
✅ A rollback that works, tested, in under 60 seconds
✅ Pipeline telemetry: duration, success rate, flaky tests, MTTR — measured, not guessed
✅ 15 tasks with full worked answers across the three cases + 5 capstone tasks
```

---

## Prerequisites

| Need | Why | Check |
|---|---|---|
| A GitHub account | Cases 2 and 3 use it; Case 1 can import from it | `gh auth status` |
| An Azure DevOps account (free) | Case 1 — [dev.azure.com](https://dev.azure.com), free for 5 users | sign in, create an organisation |
| An Azure subscription (**optional**) | Only for the AKR/Key Vault/AKS exercises | `az account show` |
| Docker ≥ 24 with BuildKit | every case builds images | `docker buildx version` |
| kubectl + kind | the deploy targets | `kind version` |
| Helm 3 | the chart-based deploys | `helm version` |
| `gh` CLI | Case 2 heavily | `gh --version` |
| `az` CLI + the `azure-devops` extension | Case 1 heavily | `az --version` |
| Java 21 (for Jenkins) | Jenkins LTS 2.555.1+ **requires Java 21** | `java -version` |
| Git ≥ 2.40 | everywhere | `git --version` |

**No Azure subscription?** Case 1 still works fully — you'll use the Microsoft-hosted agents, an Azure DevOps Git repo, Azure Artifacts and Azure Boards, all free. The AKR/Key Vault/AKS exercises have a documented local equivalent (Docker Hub / a K8s Secret / kind).

**Machine:** 16 GB RAM minimum for the Jenkins-on-Kubernetes case. 8 CPUs makes everything comfortable.

---

## The version anchors (verified)

| Tool | Version | Note |
|---|---|---|
| **Jenkins LTS** | **2.568.3** | ⭐ **Java 21 is the minimum** since 2.555.1; Java 17 support was dropped in April 2026 |
| Jenkins weekly | 2.57x | Don't run weekly in production |
| **GitHub Actions** | `actions/checkout@v7`, `actions/setup-java@v5`, `actions/upload-artifact@v4`, `docker/build-push-action@v6`, `docker/login-action@v3`, `docker/metadata-action@v5`, `aws-actions/configure-aws-credentials@v4` | ⭐ `setup-java` v1–v4 are **deprecated** — upgrade to v5 |
| GitHub runner images | `ubuntu-latest` = **Ubuntu 24.04**, `windows-latest` = **Windows Server 2025**, `macos-latest` = **macOS 15 arm64** | 2 CPUs / 7 GB (private), 4 CPUs / 16 GB (public) |
| **Azure DevOps** | SaaS, continuously released | ⭐ **Workload Identity Federation** for Azure RM service connections is GA and **Microsoft-recommended** (no secrets to rotate). **Microsoft Entra workload identity** service connections (PAT-free Azure DevOps API access) began rolling out in 2026 |
| Kubernetes | 1.37 "Garhwal" | released 2026-08-26 |
| Argo CD | 3.x | the GitOps option in the capstone |
| Trivy | 0.5x–0.6x | `aquasecurity/trivy-action` |
| BuildKit / Docker | 27–29 | multi-stage, `COPY --parents`, `--checksum`, SBOM |
| Go | 1.23 / 1.25 | |
| Java | **21 LTS** (and 25 LTS) | |
| Node | 22 LTS / 24 | |
| Python | 3.13 | |

---

## How to use these files

1. **Read `01-CICD-GUIDE.md` first, in full.** It explains CI vs CD, pipeline anatomy, caching, artifact strategies, environments, approvals, secrets and federation, testing pyramids, progressive delivery, pipeline security and supply chain, DORA metrics, and the 20 mistakes that cost teams the most. Every case file assumes you've read it and refers back to it.
2. **Then pick a case and do it end to end.** Each case file is self-contained: numbered steps, exact commands, expected output, `⛔` warnings for the things that silently fail, and **hands-on tasks with full answers at the END of the file**.
3. **Do all three.** The comparison is where the interview value is. Each case ends with a "what this tool gave me / cost me" section — collect all three and you have your own opinionated answer to "which CI should we use?"
4. **Then the capstone.** It takes the same repo through all three, adds GitOps, progressive delivery, supply-chain security and pipeline telemetry, and ends with 5 tasks that are genuinely interview-level.
5. **Keep `06-CHEATSHEET.md` open.** It has every task, action, plugin, CLI command and gotcha on one page.

**The convention used throughout:**

```bash
# commands you type
✅ expected output you must see
⛔ the failure mode and what it means
⭐ the thing that's worth remembering
⚠️ the gotcha that will cost you an hour
```

---

## Related paths in this workspace

| Path | Folder | Status |
|---|---|---|
| 🐳 Docker | [`../docker-learning-path/`](../docker-learning-path/) | ✅ 19 files |
| ☸️ Kubernetes | [`../kubernetes-learning-path/`](../kubernetes-learning-path/) | ✅ 17 files · ⏳ 3 pending (`00` one-day plan, `02` capstone, `03` cheatsheet) |
| 📊 Monitoring & Alerting | [`../monitoring-alerting-learning-path/`](../monitoring-alerting-learning-path/) | ✅ 7 files |
| 🚀 **CI/CD** | **this folder** | ✅ **9 files + `08-SCENARIO-DEPLOYMENTS/` (29) + `09-TOOL-MASTERY/` (in progress) |
| ☕ Java Full Stack (SDE 3) | [`../java-fullstack-learning-path/`](../java-fullstack-learning-path/) | 🔄 in progress · 5 of ~184 files |

They form one curriculum, on one application:

```
   DOCKER          →  KUBERNETES       →  CI/CD             →  MONITORING
   build it           run it              ship it safely        know when it breaks
   ─────────────────────────────────────────────────────────────────────────
   19 files           17 files (+3)       37 files              7 files
```

The capstone in this folder wires them together: **the pipeline deploys to Kubernetes and then asserts that the observability platform sees the new version** — which is the last mile most tutorials skip.

⭐ **Folder `08` is where all four paths actually meet.** It takes the applications you containerised in the Docker path, the manifests and Helm chart from the Kubernetes path, and the Prometheus/Grafana alerts from the Monitoring path, and makes the *pipeline* responsible for all of them — including the assertion that a canary's error rate, as measured by the monitoring stack, is what decides whether production gets the new digest.

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish_Kumar_Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn: https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260
🔗 GitHub: https://github.com/3558Bhk

*Built for engineers who learn by breaking things on purpose.*

</div>
