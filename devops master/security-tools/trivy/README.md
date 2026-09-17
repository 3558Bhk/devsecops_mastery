# 🟢 Trivy Mastery — Vulnerabilities, Misconfigurations, Secrets and SBOMs

### One scanner for everything you *build*: container images, filesystems, git repositories, Kubernetes clusters, and SBOMs. Nine files from `curl` install to running `trivy-operator` across a production cluster with an admission controller.

> **WHAT Trivy is:** a single Go binary with no daemon, no server and no licence, that scans **artifacts** for known vulnerabilities (OS packages *and* language dependencies), misconfigurations, hardcoded secrets, licence issues, and produces an **SBOM** you can hand to an auditor. It is the highest value-per-minute security tool that exists, which is why it is the one to learn first.
>
> **WHY it is the first folder in [`../`](../README.md):** it finds the thing that actually gets you in the news — a known CVE in a shipped image — and it does it in about ninety seconds from a cold start.
>
> **TARGET:** you can build a Docker image. By the end you will have Trivy gating every CI build, scanning your whole cluster continuously, generating signed SBOMs, and you will be able to explain why you suppressed a CRITICAL finding.

---

## 🔒 Version anchors

| Component | Version | Notes |
|---|---|---|
| **Trivy** | **v0.74.0** (2026-08-14) | ⭐ **Pin by digest.** Releases ~every 2 weeks |
| **trivy-operator** | **v0.32.0** (2026-07-08) | in-cluster, CRD-based continuous scanning |
| **`aquasecurity/trivy-action`** | **v0.35.0** | ⛔⛔ the **only** tag not compromised in the March 2026 incident — protected by GitHub immutable releases |
| **`aquasecurity/setup-trivy`** | **v0.2.6** | |
| **Vulnerability DB** | `trivy-db` v3, updated every 6 h | ⭐ plus `trivy-java-db` for JARs without a POM/Gradle manifest |

> ⛔⛔ **Before you install anything, read [`../02-SUPPLY-CHAIN-AND-PINNING.md`](../02-SUPPLY-CHAIN-AND-PINNING.md).** On **19–20 March 2026** an attacker force-pushed **76 of 77 tags** in `trivy-action` and **all 7** in `setup-trivy`, and published a **malicious Trivy binary as `v0.69.4`**. Anything from `v0.70.0` onward is fine; `v0.69.4` is not. File `00` installs Trivy **and verifies its cosign signature**, because that incident is the reason.

---

## 📇 The 9 files — one line each

| # | File | What you learn | Time |
|---|---|---|---|
| — | `README.md` | 👈 this index | — |
| `00` | [`00-INSTALL-AND-FUNDAMENTALS.md`](00-INSTALL-AND-FUNDAMENTALS.md) | Install on macOS/Linux/Windows (binary · Docker · brew · apt · pip-free), ⭐ **verify the cosign signature**, the artifact/target model, how `trivy-db` is built and updated, and offline/air-gapped installs | 3 h |
| `01` | [`01-FIRST-SCAN-AND-READING-OUTPUT.md`](01-FIRST-SCAN-AND-READING-OUTPUT.md) | ⭐ Your first `trivy image`, and **how to read it**: the OS-package vs language-package split, severity vs **fixability** vs **reachability**, why `node:24-alpine` beats `node:24`, and the ten output formats | 3 h |
| `02` | [`02-CONFIGURATION-AND-BASELINES.md`](02-CONFIGURATION-AND-BASELINES.md) | `trivy.yaml`, environment variables vs flags (and the precedence), ⭐ **`.trivyignore` done properly** (with expiry and owner), `--ignore-unfixed`, severity thresholds, private registries, DB mirrors, and caching | 3 h |
| `03` | [`03-CI-CD-INTEGRATION.md`](03-CI-CD-INTEGRATION.md) | ⭐⭐ **GitHub Actions · Jenkins · Azure DevOps** — pinned by digest, exit codes as gates, caching `trivy-db` between runs, SARIF to GitHub code scanning, PR comments, and how to keep the step under 90 seconds | 4 h |
| `04` | [`04-KUBERNETES-AND-INFRA.md`](04-KUBERNETES-AND-INFRA.md) | ⭐⭐ `trivy k8s` (whole-cluster, one command) and **`trivy-operator`**: the CRDs (`VulnerabilityReport`, `ConfigAuditReport`, `ExposedSecretReport`, `SBOMReport`), scan scheduling, and **admission-controller mode** that refuses to admit vulnerable pods | 5 h |
| `05` | [`05-CUSTOM-RULES-AND-POLICIES.md`](05-CUSTOM-RULES-AND-POLICIES.md) | **Rego** custom misconfiguration policies, custom secret patterns, licence allow/deny lists, and scanning your own SBOM as an input (SBOM → vulnerability, without the image) | 4 h |
| `06` | [`06-PRODUCTION-OPERATION.md`](06-PRODUCTION-OPERATION.md) | Running at scale: **Trivy Server mode** (one DB, many clients), DB update cadence and `--skip-db-update`, air-gapped operation, tuning out the noise without turning the gate off, and metrics on your own scanning | 3 h |
| `07` | [`07-TASKS-AND-INTERVIEW.md`](07-TASKS-AND-INTERVIEW.md) | **20 hands-on tasks with full answers at the END**, plus 15 interview questions with the answers a 3+ YOE candidate gives | 5 h |
| `08` | [`08-COMPLETE-CLI-REFERENCE.md`](08-COMPLETE-CLI-REFERENCE.md) | ⭐ **One single reference file.** Every subcommand (`image` · `fs` · `repo` · `k8s` · `sbom` · `config` · `rootfs` · `vm` · `aws` · `azure`) and every flag that matters, organised by job | reference |

**Total: ~33 hours.**

---

## 🚦 Reading orders

**⏱️ "Gate my CI today"** → `00` → `01` → `02` → `03`  *(~13 h)*
**🎯 "Interview this week"** → `00` → `01` → `04` → `07`  *(~16 h)*
**🏗️ "Cluster-wide programme"** → all 9 in order, with `04` and `06` as the deliverable  *(~33 h)*

---

## ⭐ The five ideas this folder keeps returning to

1. **`trivy image` scans two different worlds at once.** OS packages (via the distro's own advisories — Alpine, Debian, Red Hat) *and* language packages (via GHSA/NVD language DBs). They have different fix cadences, different severity meanings, and different `.trivyignore` entries. Conflating them is why people give up on the output.
2. **Severity is a property of the CVE; risk is a property of your deployment.** A CRITICAL in a build tool that never runs, in a layer your final stage discards, is not a CRITICAL for you. ⭐ **`--ignore-unfixed` and reachability analysis are the two flags that turn noise into signal.**
3. **Multi-stage builds are a security control, not just a size optimisation.** The `shop-api` Java image in [`../../docker-learning-path/`](../../docker-learning-path/README.md) goes from ~800 MB to ~250 MB — and every CVE in the JDK, Maven and the build toolchain disappears from the scan because those layers are not in the final image.
4. **An SBOM is an input, not just an output.** `trivy sbom cyclone.json` finds vulnerabilities from a bill of materials with no image present — which is how you scan a *dependency* you never built, and how you answer "are we affected?" in minutes instead of days during a log4j-class event.
5. **The scanner is the most privileged thing in your pipeline.** It pulls every image, reads every file, and runs on every commit. Pin it by digest, verify its signature, and watch what it talks to. [`../02-SUPPLY-CHAIN-AND-PINNING.md`](../02-SUPPLY-CHAIN-AND-PINNING.md)

---

## 🧭 Sibling folders

[`../sonarqube/`](../sonarqube/README.md) — source-code quality · [`../checkov/`](../checkov/README.md) — IaC policy · [`../README.md`](../README.md) — which tool for what · [`../../cicd-learning-path/09-TOOL-MASTERY/`](../../cicd-learning-path/09-TOOL-MASTERY/README.md) — the pipelines these plug into

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish%20Kumar%20Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn → <https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260>
🐙 GitHub → <https://github.com/3558Bhk>

*Built for engineers who learn by breaking things on purpose.*

</div>
