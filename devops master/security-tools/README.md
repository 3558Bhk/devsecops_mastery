# 🔐 Security Tools Mastery — Trivy · SonarQube · Checkov

### Three scanners, three different layers of your software, three separate self-contained courses. Each sub-folder takes you from "never installed it" to "I run this in CI on every commit, I have custom policies, and I can explain every finding to an auditor."

> **WHAT this folder is:** a parent folder with **one course per tool** — [`trivy/`](trivy/README.md), [`sonarqube/`](sonarqube/README.md), [`checkov/`](checkov/README.md) — each 9 files and complete on its own, plus **4 shared files** that only make sense once you have met all three.
>
> **WHY three folders and not one file:** because these tools do not overlap as much as people think, and they fail in completely different ways. Trivy finds a CVE in your base image. SonarQube finds a null-dereference in your Java. Checkov finds that your Deployment runs as root. ⛔ **None of them would ever find what the other two find.** Treating them as interchangeable is why teams buy three licences and get value from one.
>
> **TARGET:** you can build a Docker image and run a CI pipeline. By the end you can stand up all three, wire them into Jenkins / GitHub Actions / Azure DevOps, write custom policies, triage 500 findings down to the 6 that matter, and defend your gate thresholds in a security review.

---

## 🧭 Start here: which tool finds what

⭐ **This is the whole folder in one picture.** Everything else is depth.

```
                    YOUR SOFTWARE, IN FOUR LAYERS

  ┌──────────────────────────────────────────────────────────────────┐
  │  LAYER 4 · INFRASTRUCTURE AS CODE                                │
  │  Dockerfile · Kubernetes YAML · Helm charts · Terraform ·        │
  │  CloudFormation · Kustomize · Bicep · Ansible                    │
  │                                                                  │
  │   🔵 CHECKOV  ────────────────────────────────  ⭐ also TRIVY    │
  │   1,000+ policies, graph-based               (misconfig scanner) │
  │   "runs as root", "no NetworkPolicy",                            │
  │   "S3 bucket public", "CKV_K8S_21"                               │
  └──────────────────────────────────────────────────────────────────┘
  ┌──────────────────────────────────────────────────────────────────┐
  │  LAYER 3 · THE BUILT ARTIFACT                                    │
  │  container images · filesystems · SBOMs · registries · git repos │
  │                                                                  │
  │   🟢 TRIVY  ──────────────────────────────────────────────────   │
  │   CVEs in OS packages AND language deps, secrets, licenses,      │
  │   SBOM (CycloneDX/SPDX), misconfig, `trivy k8s` cluster-wide     │
  └──────────────────────────────────────────────────────────────────┘
  ┌──────────────────────────────────────────────────────────────────┐
  │  LAYER 2 · THE SOURCE CODE                                       │
  │  Java · TypeScript · Python · Go · C# · JS · PHP · Ruby · …      │
  │                                                                  │
  │   🟣 SONARQUBE  ───────────────────────────────────────────────   │
  │   bugs · code smells · vulnerabilities · coverage ·              │
  │   duplication · ⭐ the Quality Gate · tech-debt tracking         │
  └──────────────────────────────────────────────────────────────────┘
  ┌──────────────────────────────────────────────────────────────────┐
  │  LAYER 1 · RUNTIME & SUPPLY CHAIN                                │
  │  what is actually running, and whether you can prove it          │
  │                                                                  │
  │   🟢 trivy-operator (in-cluster CRs) · cosign signatures ·       │
  │      SBOM attestation · ⭐ pinning by digest                     │
  └──────────────────────────────────────────────────────────────────┘
```

### The decision table

| Question you are asking | Tool | Why |
|---|---|---|
| "Is there a known CVE in this image?" | 🟢 **Trivy** | It has the vulnerability databases (NVD, GHSA, language-specific) and maps them to OS + language packages |
| "Is my code correct, readable and covered by tests?" | 🟣 **SonarQube** | Static *analysis* of source — dataflow, taint tracking, cyclomatic complexity, coverage from your test runner |
| "Is this Kubernetes manifest / Terraform insecure?" | 🔵 **Checkov** | 1,000+ IaC policies, **graph-based** so it reasons about relationships between resources |
| "Is my Dockerfile insecure?" | 🔵 **Checkov** *and* 🟢 **Trivy** | ⭐ Both do it. Checkov is policy-first (`CKV_DOCKER_*`), Trivy is bundled-with-CVEs. Run both — they rarely agree |
| "Did I commit a secret?" | 🟢 **Trivy** or 🔵 **Checkov** | Trivy's secret scanning is stronger; Checkov has entropy + live key verification |
| "What is in this image, for an auditor?" | 🟢 **Trivy** | SBOM generation — CycloneDX and SPDX, with attestation |
| "Is everything in my cluster misconfigured?" | 🟢 **trivy-operator** | Runs Trivy continuously as CRDs → `VulnerabilityReport`, `ConfigAuditReport` |
| "Is my tech debt getting worse over time?" | 🟣 **SonarQube** | ⭐ The only one of the three with **history, trends and a ratchet** (Quality Gate on *new code*) |
| "Can I block a merge on any of this?" | **all three** | Each has a CI exit code. File [`01`](01-PIPELINE-INTEGRATION-ALL-THREE.md) puts them in one pipeline in the right order |

⭐ **The overlap that confuses everyone:** Trivy has a `misconfiguration` scanner and Checkov scans Dockerfiles and Helm charts. So both tools do IaC. **The difference is the source of truth for the rule.** Checkov's rules are *policy* — often compliance-mapped (CIS, SOC 2, HIPAA, PCI DSS), and you write your own in Python or YAML. Trivy's are *opinionated defaults* bundled next to its CVE engine, convenient but shallower. ⭐ **If you must pick one for IaC, pick Checkov.** If you already run Trivy for CVEs and want a cheap second opinion, leave Trivy's misconfig on and accept the noise.

---

## 🔒 Version anchors — pinned and verified

| Component | Version | Verified | Notes |
|---|---|---|---|
| **Trivy** | **v0.74.0** | 2026-08-14 | ⭐ **Pin by digest, not by tag.** See the incident note below |
| **trivy-operator** | **v0.32.0** | 2026-07-08 | the in-cluster Kubernetes-native scanner |
| **`aquasecurity/trivy-action`** | **v0.35.0** | — | ⭐ **the only tag that was NOT compromised** in March 2026 — protected by GitHub's immutable releases |
| **`aquasecurity/setup-trivy`** | **v0.2.6** | — | |
| **SonarQube Server** | **2026.4.1** | 2026-08-07 | the commercial/LTS line |
| **SonarQube Community Build** | **26.9.0.129388** | 2026-09-02 | ⭐ monthly releases, **one month of support each** — see the note below |
| **SonarQube Helm chart** | **2026.4.1** | 2026-08-07 | `community.enabled: true` installs the Community Build |
| **Checkov** | **3.3.17** | 2026-09-10 | Python **3.9–3.12** for pip installs |
| **Checkov GitHub Action** | **v12.1347.0** | — | `bridgecrewio/checkov-action` |
| **cosign** | **v3.0.2** | — | signing/verification — matches [`../cicd-learning-path/`](../cicd-learning-path/README.md) |
| **Java (SonarQube scanner host)** | **17 or 21** | — | ⚠️ SonarQube 2026.x dropped older JVMs; the *analysed* code can still be Java 8+ |

### ⛔⛔ Two things that changed in 2026 — read before you copy any command

**1. Trivy was supply-chain compromised on 19–20 March 2026.**

An attacker using compromised credentials force-pushed **76 of 77 version tags** in `aquasecurity/trivy-action` and **all 7 tags** in `aquasecurity/setup-trivy`, redirecting them to malicious commits, and published a **malicious Trivy binary as `v0.69.4`** via the compromised `aqua-bot` service account. The malicious binaries exfiltrated to an ICP blockchain C2 (`…raw.icp0.io`).

| Component | ⛔ Compromised | ✅ Safe |
|---|---|---|
| Trivy binary | **v0.69.4** (published ~18:22–21:42 UTC, 19 Mar 2026) | **v0.69.2 – v0.69.3**, and anything **≥ v0.70.0** |
| `trivy-action` | 76 of 77 tags force-pushed (~17:43 UTC 19 Mar → 05:40 UTC 20 Mar) | **v0.35.0** — immutable-release protected |
| `setup-trivy` | multiple tags | **v0.2.6** |

⭐ **This is not a footnote — it is the single best real-world lesson available about scanner security**, and [`02-SUPPLY-CHAIN-AND-PINNING.md`](02-SUPPLY-CHAIN-AND-PINNING.md) uses it as its entire case study: pin by **digest** and **immutable SHA**, not by mutable tag; prefer GitHub's immutable releases; verify signatures; block unexpected egress from CI runners; and treat your *security tooling* as the highest-value target in your supply chain, because it is the one thing that already has permission to look at everything.

**2. SonarQube Community Edition no longer exists.**

It was replaced by the **SonarQube Community Build**, on a **monthly release train where each version is supported for exactly one month** (26.8 ended support on 2026-09-02, the day 26.9 shipped). There is **no LTS for the Community Build** — if you want long-term support you need SonarQube **Server**. And the update path has required intermediate versions: `25.9.0.x → 25.12.0.x → 26.3.0.x`, with **26.1.0.118079 sometimes needed as an intermediate step** because of database-migration issues in the December 2025 release (25.12.0.117093).

⭐ **Consequence for you:** treat Community Build as *rolling* — plan to upgrade monthly or accept being unsupported — and **always back up the Postgres database before an upgrade**, because SonarQube migrates the schema in place and there is no down-migration. [`sonarqube/06-PRODUCTION-OPERATION.md`](sonarqube/06-PRODUCTION-OPERATION.md) covers the whole upgrade path procedure.

---

## 📁 The folder

### The 4 shared files — read these after you have met at least one tool

| # | File | What you learn | Time |
|---|---|---|---|
| `00` | [`00-WHICH-TOOL-FOR-WHAT.md`](00-WHICH-TOOL-FOR-WHAT.md) | The full decision matrix expanded: the four-layer model, every overlapping capability compared head-to-head, what each tool **cannot** do, and how to build a scanning strategy that is not just "run all three on everything" | 2 h |
| `01` | [`01-PIPELINE-INTEGRATION-ALL-THREE.md`](01-PIPELINE-INTEGRATION-ALL-THREE.md) | ⭐⭐ **One pipeline, three scanners, in the right order**, for all three CI tools (Jenkins · GitHub Actions · Azure DevOps). Gate placement, fail-fast vs fail-late, caching the databases, parallelising, and how to stop the pipeline taking 20 minutes | 4 h |
| `02` | [`02-SUPPLY-CHAIN-AND-PINNING.md`](02-SUPPLY-CHAIN-AND-PINNING.md) | ⭐⭐ **The Trivy v0.69.4 incident as a full case study**, then the general discipline: digest pinning, immutable release refs, cosign verification, SBOM attestation, egress control, and a threat model for your own CI | 3 h |
| `03` | [`03-COMPLIANCE-REPORTING-AND-AUDIT.md`](03-COMPLIANCE-REPORTING-AND-AUDIT.md) | Turning scanner output into something an auditor accepts: SARIF, CycloneDX SBOM, JUnit XML, CIS/SOC 2/PCI DSS/HIPAA mapping, evidence retention, and the triage record that proves a suppressed finding was a *decision* | 3 h |

### The three tool courses — 9 files each, fully self-contained

Each folder follows the identical 9-file shape, so once you have done one you know exactly where everything is in the next:

| # | File | Trivy | SonarQube | Checkov |
|---|---|---|---|---|
| — | [`README.md`](trivy/README.md) | the index, one line per file | ← same shape | ← same shape |
| `00` | `00-INSTALL-AND-FUNDAMENTALS.md` | install (binary · Docker · package managers · **verify the signature**), scan targets, DB architecture | install (Docker · Helm chart · Postgres), editions, the analysis model | install (pip · pipx · Docker · brew), frameworks, policy model |
| `01` | `01-FIRST-SCAN-AND-READING-OUTPUT.md` | your first image scan, reading the CVE table, severity vs fixability | your first scan, the dashboard, issues vs findings, the Quality Gate | your first `-d` scan, reading `CKV_*` IDs, passed/failed/skipped |
| `02` | `02-CONFIGURATION-AND-BASELINES.md` | `.trivyignore`, `trivy.yaml`, severity filters, DB mirrors, offline | `sonar-project.properties`, branch analysis, Quality Profiles, **Clean as You Code** | `.checkov.yaml`, `--skip-check`, baselines, `--compact`, frameworks |
| `03` | `03-CI-CD-INTEGRATION.md` | GitHub Actions · Jenkins · Azure DevOps, exit codes, caching the DB, PR comments | ⭐ scanners per language, `sonar-scanner`, CI wrappers, **gate = fail the build** | the Action, the CLI in Jenkins/Azure, SARIF to GitHub code scanning |
| `04` | `04-KUBERNETES-AND-INFRA.md` | ⭐ **`trivy k8s`** and **trivy-operator** — CRDs, `VulnerabilityReport`, cluster-wide scanning, admission control | scanning IaC and K8s manifests (SonarQube's IaC analysis) | ⭐ **Helm charts, Kustomize, live clusters**, graph checks across resources |
| `05` | `05-CUSTOM-RULES-AND-POLICIES.md` | custom Rego policies, license allow-lists, secret rules, SBOM policies | ⭐ **custom rules** (Java/JS plugin API), Quality Profile authoring, taint rules | ⭐ **custom checks in Python AND YAML**, the 36 graph operators, `jsonpath_` |
| `06` | `06-PRODUCTION-OPERATION.md` | DB update cadence, air-gapped installs, Trivy Server mode, tuning out noise | ⭐ **upgrades & migrations** (the Community Build rolling train), Postgres backup, compute-engine tuning, LDAP/SSO | policy-set governance, versioning your policies, framework upgrades |
| `07` | `07-TASKS-AND-INTERVIEW.md` | **20 tasks + answers at END**, 15 interview questions | **20 tasks + answers at END**, 15 interview questions | **20 tasks + answers at END**, 15 interview questions |
| `08` | `08-COMPLETE-CLI-REFERENCE.md` | ⭐ **one single file** — every subcommand & flag | ⭐ every property key & scanner flag | ⭐ every flag & policy ID family |

**Total: 4 shared files + 27 tool files = 31 files, ~110 hours.**

---

## 🚦 Three reading orders

### ⏱️ "I need CI to stop shipping vulnerable images, this week"
```
trivy/00  →  trivy/01  →  trivy/03 (CI)  →  01-PIPELINE-INTEGRATION-ALL-THREE.md
```
**~12 hours.** Trivy first, because it is the one that finds the thing that gets you in the news.

### 🎯 "My team has 4,000 findings and nobody looks at any of them"
```
sonarqube/02 (baselines + Clean as You Code)  →  trivy/02 (.trivyignore)  →
checkov/02 (baselines)  →  03-COMPLIANCE-REPORTING-AND-AUDIT.md (triage evidence)
```
**~14 hours.** ⭐ This is the most common real problem: not "we have no scanning" but "we have scanning and it is ignored". The fix is **gate on new code only** plus an auditable suppression record — and all three tools support exactly that.

### 🏗️ "I am building the security programme"
```
00 (which tool)  →  all three 00/01/02  →  01 (pipeline)  →  02 (supply chain)  →
all three 04/05  →  all three 06  →  03 (compliance)
```
**~110 hours.** Do the capstone-style task sets in each `07` as you go.

---

## 🧭 Where this folder sits in the whole workspace

```
docker-learning-path/                ← builds the images Trivy scans
   └─ 17-PROJECT-14-mern-stack.md    ← multi-stage builds = fewer CVEs to start with
        ↓
kubernetes-learning-path/            ← the manifests Checkov scans
   └─ 17-PROJECT-14-helm-gitops.md   ← the Helm charts Checkov scans as a framework
        ↓
helm-charts-mastery/                 ← ⭐ chart design that passes Checkov by construction
        ↓
security-tools/                      ← 👈 YOU ARE HERE
        ↓
cicd-learning-path/                  ← the pipelines file 01 plugs these into
   └─ 09-TOOL-MASTERY/{jenkins,github-actions,azure-devops}/
```

⭐ **Two-way dependencies worth knowing:**

- **[`../cicd-learning-path/08-SCENARIO-DEPLOYMENTS/`](../cicd-learning-path/08-SCENARIO-DEPLOYMENTS/README.md)** already defines **four gates** every pipeline must pass (digest-shape regex, cosign provenance, staging-ran-this-digest, read-back with a JSONPath name filter). [`01-PIPELINE-INTEGRATION-ALL-THREE.md`](01-PIPELINE-INTEGRATION-ALL-THREE.md) slots the three scanners into that same contract rather than inventing a second one.
- **[`../helm-charts-mastery/08-BUILD-A-REAL-CHART-FROM-SCRATCH.md`](../helm-charts-mastery/08-BUILD-A-REAL-CHART-FROM-SCRATCH.md)** builds the `shop-api` chart. **[`checkov/04-KUBERNETES-AND-INFRA.md`](checkov/04-KUBERNETES-AND-INFRA.md)** then audits it — and finding `CKV_K8S_*` failures in a chart you just wrote yourself is the fastest way to learn both.

**Continuity contract — the same `shop` application everywhere.** All examples scan these: `shop-ui` (React 19 + nginx:80), `shop-api` (Java 21 + Spring Boot 4.1:8080), `checkout` (Go 1.23:9091), `order-worker` (Python 3.13:9092), `payment-mock` (Go 1.23:9093), `mern-web` (React:80), `mern-api` (Node 24 + Express 5:4000), `mern-mongo` (MongoDB 8.0 replica set:27017). Images `ghcr.io/3558bhk/<svc>` **pinned by digest** — which is the same discipline file `02` argues for.

---

## ⭐ The six ideas this folder keeps returning to

1. **These are three different layers, not three competing products.** CVEs in an artifact, defects in source, misconfiguration in IaC. A finding in one is invisible to the other two. Anyone who says "we already have Trivy so we don't need SonarQube" has misunderstood what each does.
2. **A scanner that fails the build on *everything* is a scanner nobody reads.** The single highest-leverage move in all three tools is to **gate on new code only** — SonarQube's "Clean as You Code", Checkov's baseline, Trivy's `--ignore-unfixed` plus severity thresholds. Ratchet forward; never try to boil the ocean.
3. **A suppression is a decision, and decisions need records.** ⛔ A bare `.trivyignore` or `# checkov:skip=CKV_K8S_21` with no comment is technical debt with a security label on it. Every suppression needs an owner, a reason, and an expiry. File `03` gives you the format that survives an audit.
4. **`CRITICAL` is not a priority; fixability and reachability are.** A CRITICAL CVE in a package your code never calls, in a layer that never runs, behind an unexposed port, is less urgent than a MEDIUM in your HTTP parser. Trivy's `--ignore-unfixed` and reachability analysis exist for exactly this.
5. **Your security tooling is the most privileged thing in your CI.** It reads every image, every secret-scanned file, every repo. That is why the Trivy v0.69.4 compromise happened the way it did, and why pinning scanners by digest is not paranoia. File `02`.
6. **The output format decides whether the finding reaches a human.** SARIF → GitHub code scanning → a comment on the pull request, in front of the person who wrote the code. JUnit XML → a CI report. JSON → a ticket. ⭐ All three tools emit SARIF and CycloneDX. Use it, or your findings die in a build log.

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish%20Kumar%20Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn → <https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260>
🐙 GitHub → <https://github.com/3558Bhk>

*Built for engineers who learn by breaking things on purpose.*

</div>
