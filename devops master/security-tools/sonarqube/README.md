# 🟣 SonarQube Mastery — Code Quality, the Quality Gate, and Clean as You Code

### The only one of the three tools that understands your *source*: bugs, code smells, security hotspots, taint analysis, test coverage, duplication, and — the part that actually changes behaviour — a **Quality Gate on new code** with history and trends behind it.

> **WHAT SonarQube is:** a **server** (not a CLI) plus per-language **scanners**. The scanner analyses your code locally and pushes a report to the server; the server stores every analysis, computes the **Quality Gate** verdict, tracks trends over time, and tells your CI whether the build passes. ⭐ That server is the whole point — Trivy and Checkov are stateless, SonarQube is **a database of your code's history**, which is what makes the ratchet possible.
>
> **WHY it is not redundant with the other two:** Trivy tells you a *package* has a CVE. Checkov tells you a *manifest* is misconfigured. Neither can tell you that `OrderService.calculateTotal()` has a cyclomatic complexity of 34, a duplicated 60-line block, an SQL injection path from a request parameter, and 0% test coverage. That is **static analysis of source**, and it is a different discipline.
>
> **TARGET:** you write code in at least one supported language and can run a CI pipeline. By the end you will have SonarQube gating pull requests on *new code only*, with branch analysis, PR decoration, custom rules, and an upgrade plan that does not lose your history.

---

## 🔒 Version anchors

| Component | Version | Notes |
|---|---|---|
| **SonarQube Server** | **2026.4.1** (2026-08-07) | the commercial/LTS-supportable line |
| **SonarQube Community Build** | **26.9.0.129388** (2026-09-02) | ⭐ **monthly train, one month of support each** |
| **SonarQube Helm chart** | **2026.4.1** (2026-08-07) | `community.enabled: true` → Community Build |
| **Database** | **PostgreSQL** | ⛔ the embedded H2 is **not supported in production** and cannot be migrated off easily |
| **Server JVM** | **Java 17 or 21** | 2026.x dropped older JVMs; *analysed* code can still be Java 8+ |
| **Compute-engine heap** | ⭐ `1536M` (Community/Developer) · `5G` (Enterprise) | per the official chart's production guidance |

> ⛔⛔ **Two things changed in 2026 — read before you install.**
> **(1) SonarQube Community Edition is gone**, replaced by the **Community Build** on a monthly rolling train where each release is supported for exactly one month. **There is no LTS for Community Build.** If you need long-term support, you need **Server**.
> **(2) The upgrade path has required intermediate hops.** Documented example: `25.9.0.x → 25.12.0.x → 26.3.0.x`. Because of database-migration problems in the December 2025 release (**25.12.0.117093**), **26.1.0.118079** is sometimes required as an intermediate step too. SonarQube migrates its schema **in place with no down-migration** — so [`06-PRODUCTION-OPERATION.md`](06-PRODUCTION-OPERATION.md) starts with "back up Postgres" and never stops saying it.

---

## 📇 The 9 files — one line each

| # | File | What you learn | Time |
|---|---|---|---|
| — | `README.md` | 👈 this index | — |
| `00` | [`00-INSTALL-AND-FUNDAMENTALS.md`](00-INSTALL-AND-FUNDAMENTALS.md) | The **server + scanner** architecture, what an "analysis" is, editions compared, install via Docker and via the ⭐ Helm chart with a real PostgreSQL, the four components (web · compute-engine · search · db), and first login | 4 h |
| `01` | [`01-FIRST-SCAN-AND-READING-OUTPUT.md`](01-FIRST-SCAN-AND-READING-OUTPUT.md) | ⭐ Your first scan, and **how to read the dashboard**: Bug vs Vulnerability vs **Code Smell** vs **Security Hotspot** (⭐ the distinction everyone gets wrong), reliability/security/maintainability ratings, **technical debt**, duplication, coverage, and the project home page | 3 h |
| `02` | [`02-CONFIGURATION-AND-BASELINES.md`](02-CONFIGURATION-AND-BASELINES.md) | ⭐⭐ `sonar-project.properties` every key that matters, **Quality Profiles**, and the **Quality Gate** — including **"Clean as You Code"**: gating on *new code* only, which is the single highest-leverage setting in this folder | 4 h |
| `03` | [`03-CI-CD-INTEGRATION.md`](03-CI-CD-INTEGRATION.md) | Scanners per language (Maven · Gradle · `sonar-scanner` CLI · `sonar-scanner` npm · .NET · Go), ⭐ **GitHub Actions · Jenkins · Azure DevOps**, PR analysis + **PR decoration**, failing the build on gate failure, and coverage report import (JaCoCo · lcov · cobertura) | 5 h |
| `04` | [`04-KUBERNETES-AND-INFRA.md`](04-KUBERNETES-AND-INFRA.md) | Running the **server itself** on Kubernetes properly: the Helm chart, Postgres, persistence for the ES index, resource sizing, ingress + TLS, SSO/LDAP, backups, and SonarQube's **IaC analysis** (Terraform · CloudFormation · Kubernetes · Dockerfile) | 4 h |
| `05` | [`05-CUSTOM-RULES-AND-POLICIES.md`](05-CUSTOM-RULES-AND-POLICIES.md) | ⭐ **Writing custom rules** (the Java plugin API and the JS/TS one), custom Quality Profiles, importing external analysers (ESLint · SpotBugs · Checkstyle) via **generic issue format**, and **taint analysis** — what it needs and why it is edition-gated | 5 h |
| `06` | [`06-PRODUCTION-OPERATION.md`](06-PRODUCTION-OPERATION.md) | ⭐⭐ **Upgrades and migrations** (the rolling Community Build train, intermediate hops, housekeeping), Postgres backup/restore, **database migration** procedure, compute-engine queue tuning, `sonar.ce.*` and `sonar.web.*` JVM settings, and diagnosing a stuck analysis | 4 h |
| `07` | [`07-TASKS-AND-INTERVIEW.md`](07-TASKS-AND-INTERVIEW.md) | **20 hands-on tasks with full answers at the END**, plus 15 interview questions with the answers a 3+ YOE candidate gives | 5 h |
| `08` | [`08-COMPLETE-CLI-REFERENCE.md`](08-COMPLETE-CLI-REFERENCE.md) | ⭐ **One single reference file.** Every `sonar.*` property, every scanner flag, the Web API endpoints you will script against, and the Quality Gate conditions reference | reference |

**Total: ~38 hours.**

---

## 🚦 Reading orders

**⏱️ "Gate my PRs this week"** → `00` → `01` → `02` → `03`  *(~16 h)*
**🎯 "Interview this week"** → `01` → `02` → `06` → `07`  *(~16 h)*
**🏗️ "Roll it out to 40 repos"** → all 9 in order, with `02` and `06` as the deliverable  *(~38 h)*

---

## ⭐ The six ideas this folder keeps returning to

1. **Gate on new code, not all code.** A repo with 4,000 existing issues cannot pass a gate on everything, so the gate gets disabled, and then you have no gate. **"Clean as You Code"** says: *existing* debt is frozen, *new* debt must be zero. That is the difference between a policy people follow and one they route around.
2. **A Security Hotspot is not a Vulnerability.** A hotspot is code that is *security-sensitive* and needs a human to decide whether it is safe (`Random()` for a token, a permissive CORS header, a deserialisation call). A vulnerability is a proven defect. ⛔ Treating hotspots as vulnerabilities produces hundreds of false-positive pages and destroys trust in the tool.
3. **The scanner analyses; the server decides.** They are separate processes with separate version constraints. A scanner that is too old silently omits analyses; a server that is too old rejects the report. Pin both, and check the **Background Tasks** page when an analysis "succeeds" but nothing changes.
4. **Coverage is imported, not measured.** SonarQube does not run your tests. Your build produces a JaCoCo/lcov/cobertura report; SonarQube reads it. ⭐ If coverage shows 0%, the report path is wrong — it is almost never a SonarQube bug.
5. **The database is the product.** Everything valuable — trends, history, the ratchet, the debt record — lives in PostgreSQL and in the Elasticsearch index. The embedded H2 is a demo. File `06` treats backup and migration as the primary operational skill.
6. **Editions gate features, not quality.** Branch analysis, PR analysis, taint analysis, and several language analysers are **edition-gated**. ⭐ Check the matrix *before* you design a process around a feature the Community Build does not have — the most expensive mistake in this folder.

---

## 🧭 Sibling folders

[`../trivy/`](../trivy/README.md) — artifacts & CVEs · [`../checkov/`](../checkov/README.md) — IaC policy · [`../README.md`](../README.md) — which tool for what · [`../01-PIPELINE-INTEGRATION-ALL-THREE.md`](../01-PIPELINE-INTEGRATION-ALL-THREE.md) — all three in one pipeline

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish%20Kumar%20Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn → <https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260>
🐙 GitHub → <https://github.com/3558Bhk>

*Built for engineers who learn by breaking things on purpose.*

</div>
