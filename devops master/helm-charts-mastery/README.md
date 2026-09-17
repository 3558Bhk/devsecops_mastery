# ⎈ Helm Charts Mastery — From `helm create` to Publishing Signed Charts

### The complete path: what Helm actually does, how Go templating works, how to design a `values.yaml` other people can use, how to build a real chart from scratch, how releases and revisions are stored, how to test and lint, how to publish to an OCI registry with cosign signatures, and how to upgrade without downtime.

> **WHAT this folder is:** a self-contained course in 19 files. You start never having written a template and finish able to design, build, test, sign, publish and operate a chart that a hundred developers use every day.
>
> **WHY it exists separately from [`../kubernetes-learning-path/17-PROJECT-14-helm-gitops.md`](../kubernetes-learning-path/17-PROJECT-14-helm-gitops.md):** that file (K8s Project 14) teaches you to **use** Helm — scaffold a chart for `shop-api`, add environment values files, wire it to Argo CD. It is a *project*. This folder teaches you **how Helm works** — the template engine, the three-way merge, release storage as Secrets, hook lifecycle, dependency resolution, library charts, schema validation. It is a *mastery course*. Do P14 first if you have never touched Helm; then come here.
>
> **TARGET:** you can already write Kubernetes YAML. By the end you can debug `helm upgrade` failures that other people solve by deleting the release and reinstalling — which is the exact skill that separates a senior platform engineer from a mid-level one.

---

## 🔒 Version anchors — pinned and verified

| Component | Version | Verified | Notes |
|---|---|---|---|
| **Helm** | **v3.21.x** | 2026-08-15 | ⭐ **This folder is written and tested against Helm v3.** |
| **Helm v4** | **4.1.x / 4.2.x** | mid-2026 | ⚠️ v4 ships **in parallel with v3, not as a replacement** — both lines are actively maintained. File [`02`](02-INSTALL-HELM-AND-FIRST-RELEASE.md) §"v3 vs v4" gives the differences that actually bite, and every file flags where v4 changes behaviour |
| **`apiVersion`** | **`v2`** | — | ⛔ `v1` charts are Helm 2 era. Never write one |
| **Chart format** | OCI + classic HTTPS repos | — | file [`12`](12-CI-CD-PUBLISHING-OCI-COSIGN.md); **OCI is the modern default**, `index.yaml` repos are legacy but everywhere |
| **cosign** | **v3.0.2** | — | for signing charts and images — matches the version pinned in [`../cicd-learning-path/`](../cicd-learning-path/README.md) |
| **helm-unittest** | latest v0.8.x | — | the `helm.sh/helm-unittest` plugin, file [`11`](11-TESTING-LINTING-SCHEMA-VALIDATION.md) |
| **chart-testing (`ct`)** | v3.x | — | the CNCF's PR-linting tool for chart repos |
| **helmfile** | latest | — | file [`14`](14-HELMFILE-KUSTOMIZE-ARGO-CD.md) |
| **Kubernetes** | **1.34+** | 2026-08-15 | set `kubeVersion` in `Chart.yaml` — ⭐ and file `13` explains what happens when you don't |
| **Argo CD** | **3.x** | — | GitOps consumer of your charts, file [`14`](14-HELMFILE-KUSTOMIZE-ARGO-CD.md) |

---

## 📇 The 19 files — one line each

| # | File | What you learn | Time |
|---|---|---|---|
| `00` | [`00-ONE-DAY-MASTER-PLAN.md`](00-ONE-DAY-MASTER-PLAN.md) | **A usable, tested chart in one day**, hour by hour — scaffold, template, values, helpers, test, package | 8 h |
| `01` | [`01-WHY-HELM-AND-WHAT-IS-A-CHART.md`](01-WHY-HELM-AND-WHAT-IS-A-CHART.md) | The problem Helm solves (⛔ it is *not* "YAML templates"), what a chart is, what a release is, the client/server split that Helm 3 removed, and Helm vs Kustomize vs raw YAML — honestly | 2 h |
| `02` | [`02-INSTALL-HELM-AND-FIRST-RELEASE.md`](02-INSTALL-HELM-AND-FIRST-RELEASE.md) | Install on macOS/Linux/Windows, ⭐ **Helm v3 vs v4 — the differences that actually bite**, repos, `search`, your first `helm install`, and the six commands you will use 90% of the time | 1.5 h |
| `03` | [`03-CHART-ANATOMY.md`](03-CHART-ANATOMY.md) | Every file and directory in a chart and what it does: `Chart.yaml`, `values.yaml`, `values.schema.json`, `templates/`, `_helpers.tpl`, `NOTES.txt`, `crds/`, `.helmignore`, `charts/` | 2 h |
| `04` | [`04-GO-TEMPLATE-SYNTAX-FROM-ZERO.md`](04-GO-TEMPLATE-SYNTAX-FROM-ZERO.md) | ⭐ **The template language properly.** `{{ }}`, actions, the dot (`.`) and scope, variables, `range`, `if`/`else`, `with`, `template`/`include`, pipelines, and the whitespace rules (`{{-` and `-}}`) that cause 80% of broken YAML | 4 h |
| `05` | [`05-SPRIG-FUNCTIONS-AND-PIPELINES.md`](05-SPRIG-FUNCTIONS-AND-PIPELINES.md) | The Sprig function library that Helm ships: `default`, `quote`, `toYaml`, `nindent`, `coalesce`, `ternary`, `regexMatch`, `fromYaml`, `b64enc`, `sha256sum`, date math — and ⛔ the functions you must **never** use (`randAlphaNum`, `now`, `uuidv4`) because they break idempotency | 3 h |
| `06` | [`06-VALUES-DESIGN-AND-PRECEDENCE.md`](06-VALUES-DESIGN-AND-PRECEDENCE.md) | ⭐⭐ **The most important file for real work.** The exact precedence order (7 sources), how deep merge actually behaves, `null` to delete a key, flat vs nested values, and how to design a `values.yaml` that a stranger can use without reading your templates | 4 h |
| `07` | [`07-HELPERS-NAMED-TEMPLATES.md`](07-HELPERS-NAMED-TEMPLATES.md) | `_helpers.tpl` in depth: `define` vs `template` vs `include` (⭐ and why `include` is almost always right), the standard labels helper, naming conventions, and building your own reusable helpers | 3 h |
| `08` | [`08-BUILD-A-REAL-CHART-FROM-SCRATCH.md`](08-BUILD-A-REAL-CHART-FROM-SCRATCH.md) | ⭐⭐ **Build the `shop-api` chart properly.** Deployment, Service, Ingress, ConfigMap, Secret, ServiceAccount, NetworkPolicy, PDB, HPA, ServiceMonitor, `helm test` pod, `NOTES.txt` — with the reasoning for every field | 8 h |
| `09` | [`09-SUBCHARTS-DEPENDENCIES-LIBRARY-CHARTS.md`](09-SUBCHARTS-DEPENDENCIES-LIBRARY-CHARTS.md) | `dependencies`, `condition`, `tags`, `alias`, `import-values`, the `global` values trap, version ranges, `helm dependency update`, and ⭐ **library charts** — the way to share templates across charts without copy-paste | 4 h |
| `10` | [`10-RELEASES-REVISIONS-HOOKS-INTERNALS.md`](10-RELEASES-REVISIONS-HOOKS-INTERNALS.md) | ⭐ **How Helm stores state**: releases as **Secrets** (not ConfigMaps any more), revision numbering, `helm history`, the **three-way strategic merge**, and the complete **hook** lifecycle with weights and delete policies | 3 h |
| `11` | [`11-TESTING-LINTING-SCHEMA-VALIDATION.md`](11-TESTING-LINTING-SCHEMA-VALIDATION.md) | `helm lint`, `helm template`, ⭐ **`values.schema.json`** (JSON Schema validation — the single highest-value 30 minutes in this folder), **helm-unittest**, **chart-testing (`ct`)**, `conftest`/OPA policy on rendered YAML, and `kubeconform` | 4 h |
| `12` | [`12-CI-CD-PUBLISHING-OCI-COSIGN.md`](12-CI-CD-PUBLISHING-OCI-COSIGN.md) | `helm package`, semantic versioning for charts, publishing to an **OCI registry** (`ghcr.io`) vs a classic `index.yaml` repo, ⭐ **signing with cosign and verifying before install**, provenance, and the release pipeline in GitHub Actions / Jenkins / Azure DevOps | 4 h |
| `13` | [`13-UPGRADE-PATTERNS-ZERO-DOWNTIME.md`](13-UPGRADE-PATTERNS-ZERO-DOWNTIME.md) | ⭐⭐ `helm upgrade` in production: `--install`, `--atomic`, `--wait`, `--timeout`, `--dry-run`, immutable fields that refuse to change, CRDs Helm will **never** upgrade for you, hook ordering, and the nine ways an upgrade breaks a running app | 4 h |
| `14` | [`14-HELMFILE-KUSTOMIZE-ARGO-CD.md`](14-HELMFILE-KUSTOMIZE-ARGO-CD.md) | Managing **many releases**: `helmfile.yaml`, environments and layering, then Helm **inside Argo CD** (the three sync strategies), and the honest Helm-vs-Kustomize decision — including using both together | 4 h |
| `15` | [`15-TROUBLESHOOTING-PRODUCTION.md`](15-TROUBLESHOOTING-PRODUCTION.md) | ⭐⭐ **The 16 failures you will actually hit**: `rendered manifests contain a resource that already exists`, a release stuck in `pending-upgrade`, secrets you cannot delete, `Upgrade failed: context deadline exceeded`, CRDs out of date, hooks that never ran, values that silently did nothing — each with symptoms → cause → exact fix | 3 h |
| `16` | [`16-CAPSTONE-PLATFORM-CHART.md`](16-CAPSTONE-PLATFORM-CHART.md) | Build a **platform chart**: a library chart of shared helpers, a per-service chart that consumes it, three environments, schema-validated values, unit tests, cosign-signed OCI publishing, and Argo CD syncing the whole thing | 8 h |
| `17` | [`17-TASKS-AND-INTERVIEW.md`](17-TASKS-AND-INTERVIEW.md) | **40 hands-on tasks with full answers at the END**, plus 30 interview questions with the answers a 3+ YOE platform engineer gives | 6 h |
| `18` | [`18-HELM-CLI-COMPLETE-REFERENCE.md`](18-HELM-CLI-COMPLETE-REFERENCE.md) | ⭐ **One single reference file.** Every `helm` subcommand and the flags that matter, organised by job (install · upgrade · inspect · debug · package · publish · plugin), plus the template quick-reference and the troubleshooting ladder | reference |

**Total: ~72 hours of focused work.**

---

## 🚦 Three reading orders

### ⏱️ "I have to ship a chart this week"
```
01 (why)  →  03 (anatomy)  →  04 (templates)  →  06 (values)  →  08 (build a real chart)  →  13 (upgrade safely)
```
**~23 hours.** That is the minimum to produce a chart you would not be embarrassed by in review.

### 🎯 "I have an interview this week"
```
00 (one-day plan)  →  01  →  04 (templates)  →  06 (values precedence)  →  10 (internals)  →  13  →  15 (troubleshooting)  →  17 (Q&A)
```
**~30 hours.** Files `06`, `10` and `15` are where the senior-level questions live. Almost nobody can answer "how does Helm store releases?" or "what does `--atomic` actually roll back?"

### 🏗️ "I am building a platform team's chart standard"
```
Read all 19 in order. Files 06, 09, 11, 12 and 16 are the ones you will
turn into internal documentation — they are the "how do we standardise this" files.
```

---

## 🧭 Where this folder sits in the whole workspace

```
docker-learning-path/               ← images
        ↓
kubernetes-learning-path/
   └─ 17-PROJECT-14-helm-gitops.md  ← ⭐ USE Helm (a project). Do this first
        ↓
helm-charts-mastery/                ← 👈 YOU ARE HERE · MASTER Helm
        ↓
prometheus-in-kubernetes/           ← installs a 9000-line chart; files 03/06/13 apply directly
        ↓
security-tools/                     ← Checkov scans your charts (sibling)
        ↓
cicd-learning-path/                 ← publishes and signs them
```

⭐ **The three folders that use this one hardest:**

- **[`../prometheus-in-kubernetes/`](../prometheus-in-kubernetes/README.md)** installs `kube-prometheus-stack` — a chart with a **~9,000-line `values.yaml`** and five CRDs. Files [`06`](06-VALUES-DESIGN-AND-PRECEDENCE.md) (values precedence) and [`13`](13-UPGRADE-PATTERNS-ZERO-DOWNTIME.md) (CRDs never upgrade) are prerequisites for doing that safely.
- **[`../security-tools/checkov/`](../security-tools/checkov/README.md)** scans **Helm charts** as a first-class framework. File [`08`](08-BUILD-A-REAL-CHART-FROM-SCRATCH.md) builds the chart Checkov then audits.
- **[`../cicd-learning-path/09-TOOL-MASTERY/`](../cicd-learning-path/09-TOOL-MASTERY/README.md)** publishes and signs charts in Jenkins, GitHub Actions and Azure DevOps. File [`12`](12-CI-CD-PUBLISHING-OCI-COSIGN.md) is the spec those pipelines implement.

**Continuity contract — the same `shop` application everywhere.** This folder builds charts for: `shop-ui` (React 19 + nginx:80), `shop-api` (Java 21 + Spring Boot 4.1:8080), `checkout` (Go 1.23:9091), `order-worker` (Python 3.13:9092), `payment-mock` (Go 1.23:9093), `mern-web` (React:80), `mern-api` (Node 24 + Express 5:4000), `mern-mongo` (MongoDB 8.0 replica set:27017). Images at `ghcr.io/3558bhk/<svc>` **pinned by digest**. Namespaces `shop-{dev,staging,production,canary}`.

---

## ⭐ The seven ideas this folder keeps returning to

1. **Helm is a template engine plus a state machine.** The templating gets all the attention; the *state machine* — releases, revisions, the three-way merge, hooks — is what breaks in production. File `10`.
2. **`include` beats `template`, almost always.** `template` cannot be piped, so you cannot `nindent` its output. This single fact explains most `_helpers.tpl` code you will read. File `04`.
3. **Whitespace control is a correctness issue, not cosmetics.** A missing `{{-` produces a line of spaces in your YAML, which produces a parse error, or worse — silently changes the document structure. File `04`.
4. **Design `values.yaml` for the reader, not the writer.** The test: can someone set the replica count without opening a template? If your values are shaped like your templates instead of like the user's intent, your chart is hard to use. File `06`.
5. **Non-determinism in a template is a bug.** `randAlphaNum`, `now`, `uuidv4` produce different output on every `helm template` — so every upgrade looks like a change, and rollbacks do not roll back. File `05`.
6. **A chart without a schema is a chart with a typo waiting to happen.** `values.schema.json` turns `replicaCount: "3"` from a silent misrender into an immediate error. Highest value-per-minute in this folder. File `11`.
7. **Helm will never upgrade your CRDs. Ever.** By design, since Helm 3. If your chart ships CRDs and you upgrade it, the CRDs stay at their old version and the new controller silently rejects the new fields. Every team learns this once, expensively. Files `09` and `13`.

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish%20Kumar%20Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn → <https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260>
🐙 GitHub → <https://github.com/3558Bhk>

*Built for engineers who learn by breaking things on purpose.*

</div>
