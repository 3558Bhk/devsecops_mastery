# 🔵 Checkov Mastery — Policy as Code for Your Infrastructure

### 1,000+ built-in policies and **graph-based** analysis across Terraform, CloudFormation, Kubernetes, **Helm**, Kustomize, Dockerfile, Bicep, ARM, Ansible and OpenTofu — plus custom policies you write yourself in Python or declarative YAML.

> **WHAT Checkov is:** a **static analysis tool for infrastructure as code**. It reads your manifests *before* anything is deployed and tells you that your Deployment runs as root, your Service has no NetworkPolicy in front of it, your S3 bucket is public, or your Terraform security group allows `0.0.0.0/0` on port 22. It was built by **Bridgecrew**, acquired by **Palo Alto Networks** in 2021 and folded into Prisma Cloud — the open-source CLI stayed free and Apache-2.0.
>
> **WHY "graph-based" is the whole differentiator.** A single-resource scanner can ask *"does this EC2 instance have encryption enabled?"* Checkov 3.x builds an internal **graph of adjacent resources** and can ask *"is this EC2 instance reachable from the internet, and does it have any unencrypted snapshots?"* — questions that require reasoning about a security group, a route table, a subnet and a snapshot policy **at the same time**. That is 800+ of its policies, and it is what a regex-based linter can never do.
>
> **TARGET:** you can write a Kubernetes manifest or a Terraform file. By the end you will have Checkov gating every infrastructure PR, with a versioned policy set, custom checks written in YAML, compliance reports mapped to CIS/SOC 2/PCI DSS, and a suppression process that survives an audit.

---

## 🔒 Version anchors

| Component | Version | Notes |
|---|---|---|
| **Checkov** | **3.3.17** (2026-09-10) | releases roughly weekly |
| **Checkov GitHub Action** | **v12.1347.0** | `bridgecrewio/checkov-action` — ⭐ pin to a **commit SHA**, not `v3` or `master` |
| **Python** | **3.9 – 3.12** | ⚠️ for `pip install checkov`. Use `pipx` or the Docker image to avoid polluting your environment |
| **Docker image** | `bridgecrew/checkov:<version>` | ⭐ pin by digest |
| **Built-in policies** | **1,000+** | attribute checks (`CKV_*`) **and** graph checks (`CKV2_*`) |
| **Graph operators** | **36** (Checkov 3.0) | including `SUBSET` and `jsonpath_` prefixed JSON-path matching |
| **Compliance mappings** | CIS Benchmarks · SOC 2 · HIPAA · PCI DSS · AWS Foundations | out of the box, `--compliance` |
| **Licence** | **Apache 2.0** | |

> ⭐ **Note on the version history worth knowing:** Checkov **3.2.526** (2026-04-30) updated the **Helm parser to accept chart versions greater than v3** — so if you are scanning charts published with **Helm v4** and your Checkov is older than that, it silently fails to parse them. And **3.2.528** (2026-05-10) fixed the secrets scanner to report **every** multiline-regex match per file rather than only the first. Both are the kind of thing that makes "we've always pinned 3.2.4xx" expensive.

---

## 📇 The 9 files — one line each

| # | File | What you learn | Time |
|---|---|---|---|
| — | `README.md` | 👈 this index | — |
| `00` | [`00-INSTALL-AND-FUNDAMENTALS.md`](00-INSTALL-AND-FUNDAMENTALS.md) | Install (`pipx` · `pip` · Docker · brew), ⭐ **why `pipx` and not `pip`**, the framework model, `CKV_*` vs `CKV2_*` vs `CKV_AWS_*` / `CKV_K8S_*` / `CKV_DOCKER_*` ID families, and the policy-evaluation lifecycle | 3 h |
| `01` | [`01-FIRST-SCAN-AND-READING-OUTPUT.md`](01-FIRST-SCAN-AND-READING-OUTPUT.md) | ⭐ Your first `checkov -d .`, and **how to read it**: passed / failed / **skipped**, the resource path in the output, how to look up a `CKV_K8S_21`, the twelve output formats, and why the summary counts are not the number you act on | 3 h |
| `02` | [`02-CONFIGURATION-AND-BASELINES.md`](02-CONFIGURATION-AND-BASELINES.md) | ⭐⭐ `.checkov.yaml`, every flag that matters, **inline `#checkov:skip=` comments done properly** (owner + reason + expiry), `--skip-framework`, `--framework`, baselining an existing repo without disabling the gate, and `--compact` | 3 h |
| `03` | [`03-CI-CD-INTEGRATION.md`](03-CI-CD-INTEGRATION.md) | **GitHub Actions** (`bridgecrewio/checkov-action`, ⭐ pinned by SHA) · **Jenkins** · **Azure DevOps**, exit codes, **SARIF → GitHub code scanning**, JUnit XML, CycloneDX SBOM, and scanning **rendered** Helm output rather than the chart source | 4 h |
| `04` | [`04-KUBERNETES-AND-INFRA.md`](04-KUBERNETES-AND-INFRA.md) | ⭐⭐ **Helm charts** (the interesting one — how Checkov resolves templates and values), **Kustomize**, live **cluster scanning** (`--framework kubernetes` against a kubeconfig), **Terraform** graph checks including module and variable resolution, and CloudFormation | 5 h |
| `05` | [`05-CUSTOM-RULES-AND-POLICIES.md`](05-CUSTOM-RULES-AND-POLICIES.md) | ⭐⭐ **Custom checks in Python** (the `BaseCheck` class) **and in declarative YAML** (the graph framework), the **36 operators**, `jsonpath_` matching, connected-resource queries, and how to version and distribute your policy set as its own repo | 5 h |
| `06` | [`06-PRODUCTION-OPERATION.md`](06-PRODUCTION-OPERATION.md) | Governing a policy set at scale: which policies you enforce vs warn, per-repo thresholds, **compliance reporting** (`--compliance cis_level_1`), upgrading Checkov without breaking CI, suppressing false positives centrally, and measuring whether any of it is working | 3 h |
| `07` | [`07-TASKS-AND-INTERVIEW.md`](07-TASKS-AND-INTERVIEW.md) | **20 hands-on tasks with full answers at the END**, plus 15 interview questions with the answers a 3+ YOE candidate gives | 5 h |
| `08` | [`08-COMPLETE-CLI-REFERENCE.md`](08-COMPLETE-CLI-REFERENCE.md) | ⭐ **One single reference file.** Every flag, every output format, the `CKV_*` ID families, the 36 YAML operators, and the copy-paste custom-policy templates | reference |

**Total: ~34 hours.**

---

## 🚦 Reading orders

**⏱️ "Gate my manifests today"** → `00` → `01` → `02` → `03`  *(~13 h)*
**🎯 "Interview this week"** → `00` → `01` → `04` (Helm + graph) → `07`  *(~16 h)*
**🏗️ "Platform-team policy standard"** → all 9 in order, with `05` and `06` as the deliverable  *(~34 h)*

---

## ⭐ The six ideas this folder keeps returning to

1. **Checkov scans *intent*, not *reality*.** It reads files. It cannot tell you that a NetworkPolicy exists in another repo, or that a controller mutates your manifest at admission time, or that your cloud account already enforces encryption. ⭐ That is exactly why **`trivy-operator`** ([`../trivy/04-KUBERNETES-AND-INFRA.md`](../trivy/04-KUBERNETES-AND-INFRA.md)) scanning the **live cluster** is the complement, not the duplicate.
2. **`CKV_*` and `CKV2_*` are different kinds of check.** `CKV_` is an **attribute** check on one resource. `CKV2_` is a **graph** check across connected resources. When you write your own, you choose which — and the graph version is where the value is, because it is the one a linter cannot replicate.
3. **Scanning a Helm chart means resolving it first.** Checkov renders your templates with your values and checks the *result*. ⭐ So a chart that is secure with `values.yaml` and insecure with `values-production.yaml` produces two different verdicts — and scanning only the defaults is scanning a fiction. File `04` shows how to scan every environment's values.
4. **An inline skip without a reason is a hole with a comment on it.** ⛔ `#checkov:skip=CKV_K8S_21` alone tells an auditor nothing. `#checkov:skip=CKV_K8S_21:namespace is kube-system, owned by platform@, reviewed 2026-09-01, expires 2027-03-01` is a decision. [`../03-COMPLIANCE-REPORTING-AND-AUDIT.md`](../03-COMPLIANCE-REPORTING-AND-AUDIT.md) gives the format.
5. **Baseline, don't disable.** A repo with 300 existing failures cannot pass a gate, so people turn the gate off — and then no new failure is ever caught. ⭐ The fix: record the current failures as a **baseline**, gate only on *new* ones, and burn the baseline down at a fixed rate. Same ratchet as SonarQube's "Clean as You Code", different mechanism.
6. **Your policy set is a product with users.** Custom checks in a shared repo, versioned, with tests, and a documented severity per policy — otherwise every team writes its own `.checkov.yaml` and you have forty security standards. File `06`.

---

## 🧭 Sibling folders

[`../trivy/`](../trivy/README.md) — artifacts & CVEs · [`../sonarqube/`](../sonarqube/README.md) — source-code quality · [`../README.md`](../README.md) — which tool for what · [`../../helm-charts-mastery/08-BUILD-A-REAL-CHART-FROM-SCRATCH.md`](../../helm-charts-mastery/08-BUILD-A-REAL-CHART-FROM-SCRATCH.md) — ⭐ build the chart, then scan it here

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish%20Kumar%20Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn → <https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260>
🐙 GitHub → <https://github.com/3558Bhk>

*Built for engineers who learn by breaking things on purpose.*

</div>
