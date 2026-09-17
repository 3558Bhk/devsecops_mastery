# 🔵 Checkov 00 · Install and Fundamentals
### Install Checkov without wrecking your Python environment, learn the policy-ID families, understand what "graph-based" actually buys you, and run your first scans across Kubernetes, Helm and Terraform.

> **WHAT this file is:** the foundation for the Checkov course. Install, the policy model, the framework model, and your first scans — with the *why* behind every flag.
>
> **WHY Checkov and not Trivy for IaC:** Trivy has a misconfiguration scanner too, and it is convenient. But Checkov's rules are **policy** — 1,000+ of them, mapped to CIS / SOC 2 / HIPAA / PCI DSS, evaluated over a **graph of connected resources**, and extensible in Python *or* declarative YAML. Trivy's are opinionated defaults bundled next to its CVE engine. ⭐ If you must pick one for infrastructure, pick Checkov. Full comparison in [`../00-WHICH-TOOL-FOR-WHAT.md`](../00-WHICH-TOOL-FOR-WHAT.md).
>
> **TARGET:** Checkov installed cleanly, pinned, and scanning a real directory — and you can read a `CKV_K8S_21` and know exactly where to look up what it means.
>
> **Time:** 3 hours.

---

## 📇 Contents

| § | What |
|---|---|
| [1](#1--version-anchors) | Version anchors |
| [2](#2---what-checkov-actually-is--and-what-it-cannot-see) | ⭐ What Checkov actually is — **and what it cannot see** |
| [3](#3---attribute-checks-vs-graph-checks--the-real-differentiator) | ⭐⭐ Attribute checks vs **graph** checks — the real differentiator |
| [4](#4--install) | Install — `pipx`, Docker, brew, and why ⛔ not plain `pip` |
| [5](#5--the-policy-id-families) | The policy-ID families — how to read a `CKV_*` |
| [6](#6--the-framework-model-and-how-auto-detection-works) | The framework model, and how auto-detection works |
| [7](#7--your-first-scans) | Your first scans — Kubernetes, Helm, Terraform, Dockerfile |
| [8](#8---exit-codes---soft-fail-and-building-the-gate) | ⭐ Exit codes, `--soft-fail`, and building the gate |
| [9](#9--the-twelve-output-formats) | The twelve output formats and when each one is right |
| [10](#10---tasks) | 🔨 Tasks — **answers at the END** |

---

## 1 · Version anchors

| Component | Version | Verified | Notes |
|---|---|---|---|
| **Checkov** | **3.3.17** | 2026-09-10 | releases ~weekly |
| **Checkov GitHub Action** | **v12.1347.0** | — | ⭐ pin by **commit SHA**, not `v3`/`master` |
| **Python** | **3.9 – 3.12** | — | ⚠️ required for `pip`/`pipx` installs |
| **Docker image** | `bridgecrew/checkov:3.3.17` | — | ⭐ pin by digest |
| **Built-in policies** | **1,000+** | — | `CKV_*` attribute + `CKV2_*` graph |
| **Graph operators** | **36** (Checkov 3.0) | — | incl. `SUBSET`, `jsonpath_` JSON-path matching |
| **Compliance frameworks** | CIS · SOC 2 · HIPAA · PCI DSS · AWS Foundations | — | `--compliance` |
| **Licence** | **Apache 2.0** | — | |

**Two dated fixes worth knowing, because they show what a stale pin costs:**

| Version | Date | What changed | What breaks if you are older |
|---|---|---|---|
| **3.2.526** | 2026-04-30 | **Helm parser accepts chart versions > v3** | ⛔ Charts published with **Helm v4** silently fail to parse — you scan nothing and get a green result |
| **3.2.528** | 2026-05-10 | secrets scanner reports **every** multiline-regex match per file | only the first occurrence per file was reported — you under-count |

⭐ **Read those two together.** Both are cases where an old Checkov produces a **false PASS**, not a false FAIL. A scanner that quietly stops scanning is worse than one that is noisy, because noise gets investigated and silence does not.

---

## 2 · ⭐ What Checkov actually is — **and what it cannot see**

**Checkov is a static analyser for infrastructure-as-code.** It parses your files into an internal representation, runs policies over that representation, and prints pass/fail per resource. Nothing runs, nothing deploys, nothing connects to your cloud.

That "nothing connects" is the source of both its speed and its blindness:

### ✅ What Checkov can see

- A `Deployment` with `privileged: true`
- A `Pod` in the `default` namespace
- A container with no `resources.limits`
- An S3 bucket without a `aws_s3_bucket_public_access_block` **attached to it** ← ⭐ graph
- A Terraform security group with `0.0.0.0/0` on port 22
- A Dockerfile with no `USER` instruction
- A hardcoded secret, by known format or by entropy

### ⛔ What Checkov **cannot** see — memorise this list

| Blind spot | Why | What catches it instead |
|---|---|---|
| **A NetworkPolicy defined in another repo** | Checkov scans files you point it at. It has no cluster view | ⭐ **trivy-operator** scanning the **live cluster** ([`../trivy/04-KUBERNETES-AND-INFRA.md`](../trivy/04-KUBERNETES-AND-INFRA.md)) |
| **An admission controller that mutates your manifest** (OPA Gatekeeper, Kyverno, Pod Security Admission) | Mutation happens at the API server, after your file | live-cluster scan, or `kubectl get pod -o yaml` diffed against source |
| **A cloud-account-level control** (SCP, org policy, "block public ACLs" at the account root) | Not in your IaC | cloud posture tool (`trivy aws`, Prisma, cloud-native config) |
| **Anything rendered from values you did not pass** | ⭐ For Helm: the *default* values are scanned unless you tell it otherwise | `--var-file` / scan each environment's values — §7.2 |
| **Runtime behaviour** | It is static analysis | trivy-operator, Falco, eBPF runtime tools |
| **Whether the vulnerability is reachable** | Not its job at all | [`../trivy/`](../trivy/README.md) |

> ⭐⭐ **The one-sentence version to carry into an interview:** *"Checkov audits intent; it cannot audit reality. It tells me what my manifests say, which is the earliest and cheapest place to catch a problem — but the cluster is the source of truth, so I pair it with an in-cluster scanner."*
>
> That sentence is also the argument for running Checkov **and** trivy-operator: they are not redundant, they are two different observation points on the same system, and each covers the other's blind spot.

### Where Checkov sits in the pipeline

```
   developer writes manifest
            │
   ┌────────▼─────────┐
   │  PRE-COMMIT       │  ⭐ cheapest place to fail. `checkov -d .` locally,
   │  (local hook)     │     or a git pre-commit hook. Seconds.
   └────────┬─────────┘
            │  push / PR
   ┌────────▼─────────┐
   │  PR GATE          │  ⭐ SARIF → GitHub code scanning, findings ON THE DIFF.
   │  (CI, blocking)   │     This is where the ratchet lives: new failures block,
   └────────┬─────────┘     baseline failures do not.
            │  merge
   ┌────────▼─────────┐
   │  RENDER + SCAN    │  ⭐⭐ For Helm/Kustomize: `helm template` FIRST, then
   │  (CI, blocking)   │     scan the RENDERED output. Scanning chart source
   └────────┬─────────┘     alone misses everything a values file changes.
            │  deploy
   ┌────────▼─────────┐
   │  LIVE CLUSTER     │  trivy-operator, continuous, catches drift and the
   │  (continuous)     │  things Checkov structurally cannot see.
   └──────────────────┘
```

---

## 3 · ⭐⭐ Attribute checks vs **graph** checks — the real differentiator

This is the section that explains why Checkov exists as a separate tool from a YAML linter.

### Attribute checks — `CKV_*`

One resource, one question:

```yaml
# CKV_K8S_16 — "Container should not be privileged"
containers:
  - name: shop-api
    securityContext:
      privileged: true        # ⛔ FAIL — the check looks at ONE field on ONE resource
```

A regex-based linter can do this. It is table stakes.

### Graph checks — `CKV2_*`

**Connected** resources, requiring the tool to build a graph and reason across it:

```yaml
# CKV2_AWS_6 — "Ensure that S3 bucket has a Public Access Block"
#
# ⛔ This CANNOT be answered by looking at the bucket.
# The bucket resource has no field that says "I am blocked from being public".
# The answer lives in a DIFFERENT resource that must be ATTACHED to it.

resource "aws_s3_bucket" "assets" {
  bucket = "shop-assets"
}

resource "aws_s3_bucket_public_access_block" "assets" {   # ← must exist…
  bucket = aws_s3_bucket.assets.id                        # ← …and must REFERENCE the bucket
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
```

Checkov builds the adjacency (`bucket` ← `public_access_block`) and asks: *does this bucket have a connected public-access-block with all four flags true?* A linter scanning one resource at a time cannot express that question, and neither can a human reviewing a 900-file Terraform plan.

**The Kubernetes equivalent** — *"is this workload protected by a NetworkPolicy?"*:

```yaml
# CKV2_K8S_6 — "Minimize the admission of pods which lack an associated NetworkPolicy"
#
# The Pod/Deployment has NO field for this. You must find a NetworkPolicy whose
# podSelector MATCHES this pod's labels, in the same namespace.
apiVersion: apps/v1
kind: Deployment
metadata:
  name: checkout
  namespace: shop-production
spec:
  template:
    metadata:
      labels: { app: checkout }        # ← the selector target
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: checkout-allow-mesh
  namespace: shop-production           # ← must be the SAME namespace
spec:
  podSelector:
    matchLabels: { app: checkout }     # ← must MATCH the pod's labels
  policyTypes: [Ingress]
```

⭐ **Four things must line up** — namespace, selector, labels, policy type — across two resources in two files. That is a graph query, and it is precisely the class of misconfiguration that causes real breaches and that no single-resource check can ever find.

### Why this matters to how you use Checkov

| | Attribute (`CKV_*`) | Graph (`CKV2_*`) |
|---|---|---|
| Question | "is field X set correctly?" | "is resource A correctly connected to resource B?" |
| Can a linter do it? | yes | ⛔ no |
| Can you suppress it inline? | yes | ⚠️ often not meaningfully — the *absence* of a second resource has nowhere to put a comment |
| False positives | low | ⭐ higher — variable resolution, module boundaries and generated code confuse the graph |
| **Where your custom policies should live** | rarely | ⭐⭐ **almost always here** — this is the value you cannot get elsewhere |

> ⛔ **The graph-check false-positive trap.** Graph checks depend on **resolving variables and references**. In Terraform that means module inputs, `terraform.tfvars`, remote state references, and `count`/`for_each`. If Checkov cannot resolve a variable, the edge is missing and the check fails. **Before you suppress a `CKV2_*`, prove the graph is wrong** with `--download-external-modules true --evaluate-variables true --var-file terraform.tfvars`. Suppressing an unresolved-graph failure hides the real problem.

---

## 4 · Install

### 4.1 ⭐ `pipx` — the correct way

```bash
# pipx installs Checkov in its OWN isolated virtualenv but puts the CLI on your PATH
python3 -m pip install --user pipx        # or: brew install pipx / apt install pipx
python3 -m pipx ensurepath
exec "$SHELL"                              # reload PATH

pipx install checkov==3.3.17               # ⭐ PIN THE VERSION
pipx list                                  # confirm: package checkov 3.3.17
checkov --version
```

```
3.3.17
```

> ⭐⭐ **Why `pipx` and not `pip`.** Checkov pulls in **a very large dependency tree** — Terraform parsers, graph libraries, `boto3`, `aiohttp`, YAML/JSON processors, dozens of transitive packages. Installing that with plain `pip install checkov` into your system or project Python **will** conflict with something you already depend on, and the failure will appear as a broken unrelated tool three days later.
>
> `pipx` gives each CLI its own virtualenv: Checkov gets whatever it wants, your project keeps its own pinned dependencies, and nothing collides. **This is the general rule for every Python-based CLI tool** — `pipx` for applications, `pip`/`uv` for libraries your code imports.

Upgrading and pinning:

```bash
pipx upgrade checkov                       # to latest — ⛔ do not do this in CI
pipx install checkov==3.3.17 --force       # back to the pinned version
pipx uninstall checkov
```

### 4.2 ⭐ Docker — the way CI should run it

```bash
# ⭐ pin by DIGEST, not by tag — same rule as every other tool in this folder
docker pull bridgecrew/checkov:3.3.17
docker inspect --format='{{index .RepoDigests 0}}' bridgecrew/checkov:3.3.17

# Scan a directory. The mount MUST be read-only and the path must match.
docker run --rm \
  -v "$(pwd)/k8s:/iac:ro" \
  bridgecrew/checkov@sha256:<PINNED_DIGEST> \
  --directory /iac --framework kubernetes --output json
```

| Detail | Why |
|---|---|
| `:ro` on the mount | ⭐ Checkov only reads. A read-write mount of your repo into a third-party container is an unnecessary risk |
| `--directory /iac` | the **container's** path, not yours — the #1 confusion with Dockerised Checkov |
| pinned digest | same reasoning as Trivy §1 — tags are mutable |

### 4.3 Homebrew / apt / other

```bash
brew install checkov
brew pin checkov                 # ⭐ stop brew upgrade from moving you

# Checkov also ships in some distro repos and as a standalone binary —
# but ⭐ prefer pipx or Docker so the version is explicit and reproducible.
```

### 4.4 Verify the install

```bash
checkov --version
checkov --list | wc -l                       # how many policies you have
checkov --list --framework kubernetes | head
python3 -c "import sys; print(sys.version)"  # must be 3.9–3.12
```

⭐ **`checkov --list` is the command most people never discover and should use constantly.** It prints every policy ID with its name, and it is filterable by framework. It is the authoritative answer to "what does `CKV_K8S_21` mean *in the version I have*" — better than any blog post, including this file.

---

## 5 · The policy-ID families

Every finding has an ID. The prefix tells you which world it came from:

| Family | Scope | Examples |
|---|---|---|
| `CKV_AWS_*` | Terraform **and** CloudFormation — AWS | `CKV_AWS_18` (S3 access logging), `CKV_AWS_21` (S3 versioning), `CKV_AWS_24` (SG on 0.0.0.0/0:22) |
| `CKV_AZ_*` | Terraform — Azure | `CKV_AZ_1` (PG SSL enforcement) |
| `CKV_GCP_*` | Terraform — GCP | `CKV_GCP_24` |
| `CKV_OCI_*` | Terraform — OCI | |
| `CKV_K8S_*` | ⭐ **Kubernetes manifests** (and rendered Helm) | `CKV_K8S_16` (privileged), `CKV_K8S_21` (default namespace), `CKV_K8S_22` (readOnlyRootFilesystem) |
| `CKV_DOCKER_*` | **Dockerfile** | `CKV_DOCKER_3` (no `USER`), `CKV_DOCKER_7` (base image tag not fixed) |
| `CKV_GHA_*` | **GitHub Actions workflows** | ⭐ yes, it scans your CI too |
| `CKV_TF_*` | Terraform-specific (module pins, provider versions) | `CKV_TF_1` (module from git refs a commit, not a branch) |
| `CKV_CFN_*` | CloudFormation-specific | |
| `CKV_BICEP_*` / `CKV_ARM_*` / `CKV_ANSIBLE_*` / `CKV_OPENAPI_*` | other frameworks | |
| `CKV_SECRET_*` | hardcoded secrets | |
| `CKV_LIC_*` | licence policy | |
| **`CKV2_*`** | ⭐⭐ **GRAPH checks** — connected resources | `CKV2_AWS_6` (S3 public access block), `CKV2_K8S_6` (NetworkPolicy) |
| `CKV_CUSTOM_*` / your own prefix | **your** policies | files [`05`](05-CUSTOM-RULES-AND-POLICIES.md) |

### ⭐ Representative Kubernetes checks — and how to look them up properly

> ⚠️ **Policy IDs and their exact wording shift between versions.** The table below is representative, not authoritative. **The authoritative lookup is always your own installed version:**

```bash
checkov --list --framework kubernetes | grep -i 'CKV_K8S_21'
checkov --list --framework kubernetes | grep -iE 'privileged|runAsNonRoot|readOnlyRoot'
```

| ID | Check | Why it matters |
|---|---|---|
| `CKV_K8S_1` | `allowPrivilegeEscalation` should be false | a container process gaining more privileges than its parent |
| `CKV_K8S_8` / `9` | liveness / readiness probe configured | no probe = no rollout safety and no self-healing |
| `CKV_K8S_10`–`13` | CPU/memory **requests and limits** set | no requests = no scheduling signal; no limits = one pod starves the node |
| `CKV_K8S_14` | image tag is fixed (not `latest`) | ⛔ `latest` makes rollbacks impossible and defeats digest pinning |
| `CKV_K8S_15` | `imagePullPolicy` appropriate | |
| `CKV_K8S_16` | no `privileged: true` | privileged ≈ root on the node |
| `CKV_K8S_17` / `19` / `18` | no `hostNetwork` / `hostPID` / `hostIPC` | escapes the pod's isolation |
| `CKV_K8S_20` | `runAsNonRoot` | |
| **`CKV_K8S_21`** | ⭐ **not in the `default` namespace** | the `default` ns usually has no NetworkPolicy and no ResourceQuota, and RBAC there is often permissive |
| `CKV_K8S_22` | `readOnlyRootFilesystem` | forces you to declare writable paths explicitly |
| `CKV_K8S_25` / `28` | `NET_RAW` capability dropped | packet forgery, ARP spoofing inside the cluster network |
| `CKV_K8S_29` / `30` / `31` | `securityContext` applied, seccomp profile set | |
| `CKV_K8S_35` | ⭐ **no secrets in env vars** | env is visible in `/proc/<pid>/environ`, in crash dumps, and in `kubectl describe pod` output |
| `CKV_K8S_37` | no capabilities **added** | |
| `CKV_K8S_38` | `automountServiceAccountToken: false` unless needed | ⭐ a mounted SA token is the first thing an attacker uses to move laterally |
| `CKV_K8S_40` | `runAsUser` is high (≥ 10000) | low UIDs collide with host users |
| `CKV_K8S_43` | image reference is fixed (digest) | |

⭐ **Notice how many of these are the same disciplines taught in [`../../kubernetes-learning-path/`](../../kubernetes-learning-path/README.md) and enforced in [`../../helm-charts-mastery/08-BUILD-A-REAL-CHART-FROM-SCRATCH.md`](../../helm-charts-mastery/08-BUILD-A-REAL-CHART-FROM-SCRATCH.md).** A well-built chart passes Checkov by construction; if yours does not, the fix belongs in the chart's `_helpers.tpl`, not in 40 inline skips.

---

## 6 · The framework model, and how auto-detection works

```bash
checkov --list-frameworks
```

```
terraform  terraform_plan  cloudformation  kubernetes  serverless  arm  bicep
dockerfile  secrets  json  yaml  github_configuration  gitlab_configuration
bitbucket_pipelines  circleci_pipelines  ansible  helm  kustomize  openapi
3d_policy  github_actions  azure_pipelines  tofu  cdk  ...
```

**Auto-detection:** `checkov -d .` inspects every file and runs whichever frameworks match. That is convenient and ⛔ usually wrong in CI:

```bash
checkov -d .                          # runs EVERYTHING — Terraform, K8s, Dockerfile,
                                      # secrets, GitHub Actions, JSON, YAML…
```

Three problems with leaving it on auto:

1. **Runtime.** Scanning a monorepo with all frameworks can take minutes instead of seconds.
2. **Unrelated failures.** A `CKV_GHA_*` finding in your workflows blocks a PR that only touched Terraform.
3. **You cannot reason about the result.** "Checkov failed" is not actionable; "the Kubernetes framework found 3 new failures in `k8s/production/`" is.

⭐ **Always scope explicitly in CI:**

```bash
checkov -d k8s/ --framework kubernetes
checkov -d helm-charts/ --framework helm
checkov -d infra/ --framework terraform
checkov -d . --framework secrets --framework dockerfile
```

`--framework` is **repeatable** — pass several to scan several, and only those.

---

## 7 · Your first scans

Point these at the real artifacts in this workspace. If you have built the [`../../helm-charts-mastery/`](../../helm-charts-mastery/README.md) chart or the [`../../kubernetes-learning-path/`](../../kubernetes-learning-path/README.md) manifests, use them — scanning your own work is what makes the findings stick.

### 7.1 Kubernetes manifests

```bash
checkov -d k8s/ --framework kubernetes --compact
```

```
       _               _
   ___| |__   ___  ___| | _______   __
  / __| '_ \ / _ \/ __| |/ / _ \ \ / /
 | (__| | | |  __/ (__|   < (_) \ V /
  \___|_| |_|\___|\___|_|\_\___/ \_/

By Prisma Cloud | version: 3.3.17

kubernetes scan results:

Passed checks: 142, Failed checks: 11, Skipped checks: 2

Check: CKV_K8S_21: "The default namespace should not be used"
	FAILED for resource: Deployment.default.checkout
	File: /checkout-deployment.yaml:1-42

Check: CKV_K8S_16: "Container should not be privileged"
	FAILED for resource: Deployment.shop-production.debug-tool
	File: /debug.yaml:1-18
	...
```

**How to read one finding — the three things you need:**

| Part | What it gives you |
|---|---|
| `CKV_K8S_21` | the policy ID → `checkov --list --framework kubernetes \| grep CKV_K8S_21` for the exact wording in *your* version |
| `Deployment.default.checkout` | ⭐ **resource kind . namespace . name** — the precise object |
| `File: /checkout-deployment.yaml:1-42` | ⭐ the file and the **line range** — jump straight there |

`--compact` removes the full resource dump from each finding. ⭐ Use it in CI logs; drop it locally when you need to see the offending block inline.

### 7.2 ⭐⭐ Helm charts — the one everybody gets wrong

```bash
# ⛔ WRONG — scans the chart with DEFAULT values only
checkov -d helm-charts/shop-api --framework helm

# ✅ RIGHT — render with EACH environment's values, then scan the result
helm template shop-api helm-charts/shop-api -f helm-charts/shop-api/values.yaml \
  > /tmp/rendered-default.yaml
checkov -f /tmp/rendered-default.yaml --framework kubernetes

helm template shop-api helm-charts/shop-api \
  -f helm-charts/shop-api/values.yaml \
  -f helm-charts/shop-api/values-production.yaml \
  > /tmp/rendered-prod.yaml
checkov -f /tmp/rendered-prod.yaml --framework kubernetes
```

> ⭐⭐ **Why this matters — and it is a real hole, not a pedantic one.**
>
> Checkov's Helm framework resolves templates, but **which values it uses determines the verdict**. A chart can be perfectly secure with `values.yaml` and dangerously insecure with `values-production.yaml` — for example if production sets `image.tag: latest`, or `replicaCount: 3` with a `podSecurityContext` that is only applied when `security.enabled` is true and dev leaves it false.
>
> **Scanning only the defaults is scanning a fiction.** The environment you actually run in production is the one you must scan, and you must scan *every* environment you deploy to — because they can diverge in either direction.
>
> ⭐ **The stronger pattern, and the one to adopt:** render and scan in CI as a **separate, explicit step**, using the exact same `helm template` invocation your CD pipeline uses to deploy. Then you are provably auditing the bytes that will be applied, not a close approximation. That also catches the case where the chart is fine but the **values file committed to the config repo** is not — which is where GitOps misconfigurations actually live.

### 7.3 Terraform — with the graph fully resolved

```bash
# ⛔ naive — unresolved variables cause spurious CKV2_* graph failures
checkov -d infra/

# ✅ full resolution
checkov -d infra/ \
  --framework terraform \
  --download-external-modules true \
  --evaluate-variables true \
  --var-file infra/terraform.tfvars \
  --compact
```

| Flag | Why |
|---|---|
| `--download-external-modules true` | ⭐ without it, checks inside **modules from a registry/git** are skipped, and graph edges into them are missing |
| `--evaluate-variables true` | resolves variables so `CKV2_*` graph checks can follow references |
| `--var-file` | the actual values — otherwise every variable is unknown |
| `--repo-root-for-plan-enrichment` | enriches results with resource metadata from the repo |

### 7.4 Dockerfile, secrets, and your own CI

```bash
checkov -d docker/ --framework dockerfile --compact
checkov -d . --framework secrets --skip-path node_modules --skip-path .git
checkov -d .github/workflows/ --framework github_actions
```

⭐ **Scanning `.github/workflows/` is the most under-used Checkov capability.** Your CI workflows hold credentials, run third-party actions, and often have `pull_request_target` or script-injection exposures. `CKV_GHA_*` finds them — and given the March 2026 Trivy incident ([`../02-SUPPLY-CHAIN-AND-PINNING.md`](../02-SUPPLY-CHAIN-AND-PINNING.md)), *"which actions are pinned to mutable tags?"* is now a question with a very concrete answer.

### 7.5 Compliance mapping — for when an auditor asks

```bash
checkov --list --compliance            # which frameworks are available
checkov -d infra/ --framework terraform --compliance cis_level_1
checkov -d k8s/ --framework kubernetes --compliance cis_level_2 --output json > cis.json
```

⭐ This produces findings **organised by control** rather than by policy — which is the format an auditor reads. Same scan, different lens, and it is the difference between "we run Checkov" and "here is our CIS Level 1 coverage evidence". File [`../03-COMPLIANCE-REPORTING-AND-AUDIT.md`](../03-COMPLIANCE-REPORTING-AND-AUDIT.md).

---

## 8 · ⭐ Exit codes, `--soft-fail`, and building the gate

**Checkov DOES exit non-zero on failure** — unlike Trivy, which defaults to `0`. So the gate works out of the box. That makes the *tuning* the hard part.

```bash
checkov -d k8s/ --framework kubernetes
echo $?
# 1        ← any failed check fails the run
```

### The flags that shape the gate

| Flag | Effect | Use when |
|---|---|---|
| `--soft-fail` | ⭐ always exit `0`, even with failures | rollout period; the INFORM half of a two-report pattern |
| `--soft-fail-on CKV_K8S_21` | this specific check never fails the build | a known, accepted, documented exception |
| `--hard-fail-on CKV_AWS_24` | ⭐ this check **always** fails, even under `--soft-fail` | your non-negotiables (open SSH to the world) |
| `--skip-check CKV_K8S_21` | do not evaluate at all | ⛔ **avoid** — you lose the finding entirely, not just the failure. Prefer an inline skip with a reason |
| `--skip-framework helm` | skip a whole framework | scoping |
| `--skip-path node_modules` | skip a path | generated/vendored code |
| `--quiet` | only failures, no summary | parsing output |

### ⭐⭐ The gate you actually want — `--soft-fail` plus `--hard-fail-on`

This combination is the pattern that makes Checkov survivable on a legacy codebase:

```bash
checkov -d . \
  --framework kubernetes --framework helm --framework dockerfile --framework secrets \
  --soft-fail \
  --hard-fail-on CKV_K8S_16 \      # privileged containers        — never allowed
  --hard-fail-on CKV_K8S_20 \      # runAsNonRoot                 — never allowed
  --hard-fail-on CKV_K8S_35 \      # secrets in env vars          — never allowed
  --hard-fail-on CKV_K8S_38 \      # automount SA token           — never allowed
  --hard-fail-on CKV_AWS_24 \      # SG open to 0.0.0.0/0:22      — never allowed
  --hard-fail-on CKV_DOCKER_3 \    # Dockerfile runs as root      — never allowed
  --output sarif --output-file-path ./reports \
  --compact
```

**What this achieves:**

- **Everything is scanned and reported** — you get full visibility, the SARIF lands in code scanning, the trend line exists.
- **Six non-negotiables block the build immediately** — the ones that are genuinely never acceptable and are cheap to fix.
- **Everything else is a ratchet** — visible, tracked, burn-down-able, but not blocking on day one.

⭐ **This is the same shape as the answer in every other tool in this folder:** Trivy's gate-on-fixable ([`../trivy/00-INSTALL-AND-FUNDAMENTALS.md`](../trivy/00-INSTALL-AND-FUNDAMENTALS.md) §8), SonarQube's "Clean as You Code" ([`../sonarqube/02-CONFIGURATION-AND-BASELINES.md`](../sonarqube/02-CONFIGURATION-AND-BASELINES.md)). **Gate on the small set that is unarguable; report on the rest; shrink the rest on a schedule.** Any other shape gets disabled within a month.

Then, as the baseline burns down, you promote checks from report-only to `--hard-fail-on` — one or two per quarter, in a committed file, so the ratchet is visible in git history.

---

## 9 · The twelve output formats

```bash
checkov -d . --output cli          # default, human-readable
checkov -d . --output json         # ⭐ machine processing, the workhorse
checkov -d . --output sarif        # ⭐⭐ GitHub code scanning / Azure DevOps
checkov -d . --output junitxml     # CI test reports (Jenkins, GitLab)
checkov -d . --output cyclonedx    # SBOM-style, for the auditor
checkov -d . --output csv
checkov -d . --output github_failed_only
checkov -d . --output baseline
```

⭐ **`--output` is repeatable** — emit several at once, to different files:

```bash
checkov -d . --framework kubernetes \
  --output json     --output-file-path ./reports/checkov.json \
  --output sarif    --output-file-path ./reports/checkov.sarif \
  --output junitxml --output-file-path ./reports/checkov.xml
```

| Format | Use it for |
|---|---|
| **`sarif`** | ⭐⭐ **PR review.** Uploads to GitHub code scanning → findings appear **on the diff lines**, assigned to the author. The only format that reliably gets a finding fixed, because it lands where the code is being read |
| **`json`** | scripting, custom gates, the baseline comparison, dashboards |
| **`junitxml`** | Jenkins/GitLab native test-report rendering |
| **`baseline`** | ⭐ captures the current failures so you can gate on *new* ones only — the mechanical basis of the ratchet |
| **`cli`** | humans, locally |

---

## 10 · 🔨 Tasks

> **0.1** Install Checkov 3.3.17 with `pipx`, pinned, and record `checkov --version` and the total policy count from `checkov --list | wc -l`. Explain in two sentences why `pipx` rather than `pip`, and name the failure mode `pip` produces that will not appear for three days.

> **0.2** Look up `CKV_K8S_21`, `CKV_K8S_35` and `CKV2_K8S_6` using **only** your installed Checkov — no browser. Report the exact wording for your version and note whether it differs from the table in §5.

> **0.3** Scan a Kubernetes directory and, for one failing check, extract all three identifying pieces (policy ID, `kind.namespace.name`, file + line range) and fix it in the manifest. Confirm the fix.

> **0.4** Build a Helm chart whose `values.yaml` is secure and whose `values-production.yaml` is **not** (for example: production sets `image.tag: latest`, or enables a debug sidecar that is privileged). Prove that scanning the chart with the default framework gives a PASS and scanning the rendered production output gives a FAIL. Explain what this proves about scanning Helm charts.

> **0.5** Take a Terraform directory and run Checkov twice: once naively, once with full variable and module resolution (§7.3). Report the difference in `CKV2_*` results and explain mechanically why the naive run produced failures that were not real.

> **0.6** Implement the `--soft-fail` + `--hard-fail-on` gate from §8 against a directory with several failures. Prove that: (a) the run exits 0, (b) a `CKV_K8S_16` violation still fails it, and (c) the SARIF still contains every finding including the ones that did not gate.

> **0.7** Emit three output formats from a single scan, and for each, name the human or system that consumes it.

> **0.8** ⭐⭐ Your team adds `--skip-check CKV_K8S_21` to the CI command to make the pipeline green. Two months later a new service is deployed into the `default` namespace with a permissive ServiceAccount and no NetworkPolicy, and there is a lateral-movement incident. Explain why `--skip-check` was the wrong tool, what should have been used instead, and the three properties a suppression must have to have prevented this.

> **0.9** ⭐⭐ You must roll Checkov out to 30 repositories with 4,000 existing failures between them, no security team, and a hard deadline of one quarter before it blocks any merge. Write the rollout plan: sequencing, the gate shape, how the baseline burns down, who owns a suppression, and the two numbers you would report weekly to prove it is working.

<details>
<summary>👉 Answers</summary>

**0.1**

```bash
python3 -m pip install --user pipx && python3 -m pipx ensurepath && exec "$SHELL"
pipx install checkov==3.3.17
checkov --version          # → 3.3.17
checkov --list | wc -l     # → 1000+ (exact count varies by version)
pipx list                  # → package checkov 3.3.17, in its own venv
```

**Why `pipx`:** Checkov is an *application*, not a library your code imports, and it drags in a very large dependency tree (Terraform parsers, graph libraries, `boto3`, `aiohttp`, dozens of transitive pins). `pipx` gives it an **isolated virtualenv** while still putting `checkov` on your `PATH` — so Checkov's pins and your project's pins never meet.

**The delayed failure mode `pip` produces:** a **transitive dependency conflict**. `pip install checkov` into a shared environment resolves Checkov's requirements against what is already installed and quietly upgrades or downgrades something else's pin — say `pyyaml`, `requests`, `urllib3` or `boto3`. `pip` prints a `WARNING: You have … incompatible` line that scrolls past, the install "succeeds", Checkov works. **Three days later a completely unrelated tool breaks** — your Terraform wrapper fails to parse YAML, your AWS CLI script gets a signature error, a test fixture raises an import error — and nothing in that stack trace mentions Checkov. You debug the wrong tool for an afternoon, then `pip install` the *other* tool, which re-breaks Checkov. ⛔ This is the classic shared-environment whack-a-mole, and the fix is structural: one virtualenv per CLI application.

**0.2** ⭐ Using only the installed binary:

```bash
checkov --list --framework kubernetes | grep -E '^CKV_K8S_(21|35):'
checkov --list --framework kubernetes | grep -E '^CKV2_K8S_6:'

# if the grep is too narrow, widen it — wording changes between versions
checkov --list --framework kubernetes | grep -iE 'default namespace'
checkov --list --framework kubernetes | grep -iE 'secret|env'
checkov --list --framework kubernetes | grep -iE 'networkpolicy|network policy'

# and dump the whole thing to search properly
checkov --list --framework kubernetes > /tmp/checkov-k8s-policies.txt
wc -l /tmp/checkov-k8s-policies.txt
```

Expected wording (verify against your own output — **it does differ between versions**, which is the point of the exercise):

| ID | Wording in recent 3.3.x |
|---|---|
| `CKV_K8S_21` | *"The default namespace should not be used"* |
| `CKV_K8S_35` | *"Prefer using secrets as files over secrets as environment variables"* |
| `CKV2_K8S_6` | *"Minimize the admission of pods which lack an associated NetworkPolicy"* |

⭐ **Two things this task is really teaching.**
1. **`checkov --list` is the authoritative source**, not documentation and not a blog. Docs describe the latest version; your CI runs a pinned one. When a finding surprises you, `--list` tells you what *your* check actually asserts.
2. **Wording drifts between versions**, so a suppression recorded as *"skip CKV_K8S_21 because default namespace"* becomes meaningless after an upgrade renames the policy's intent. ⭐ Record the **ID plus the wording plus the version** in your suppression rationale — that is what makes it auditable two years later.

**0.3**

```bash
checkov -d k8s/ --framework kubernetes --output json --output-file-path ./reports \
  --compact
```
```bash
# extract the three identifying pieces for the first failure
jq -r '.check_type as $t
       | .results.failed_checks[0]
       | "ID:      \(.check_id)\nNAME:    \(.check_name)\nRES:     \(.resource)\nFILE:    \(.file_path):\(.file_line_range[0])-\(.file_line_range[1])"' \
  reports/results_json.json
```
```
ID:      CKV_K8S_21
NAME:    The default namespace should not be used
RES:     Deployment.default.checkout
FILE:    /checkout-deployment.yaml:1-42
```

- **Policy ID** → `CKV_K8S_21`
- **`kind.namespace.name`** → `Deployment.default.checkout` ⭐ tells you the object has **no** `metadata.namespace`, so it lands in `default`
- **File + line range** → `/checkout-deployment.yaml:1-42`

The fix:

```yaml
 apiVersion: apps/v1
 kind: Deployment
 metadata:
   name: checkout
+  namespace: shop-production
 spec:
```

Confirm:

```bash
checkov -f k8s/checkout-deployment.yaml --framework kubernetes --compact | grep -c CKV_K8S_21
# 0
```

⭐ **The general lesson:** `resource` is rendered `kind.namespace.name`, so a failure that reads `.default.<name>` means the manifest *omitted* the namespace — which is a different bug from "it is in the wrong namespace", and a different fix (add the field vs change it). Read the resource string, not just the check name.

**0.4** Build the divergence deliberately:

```yaml
# helm-charts/demo/values.yaml  — SECURE
image:
  repository: ghcr.io/3558bhk/shop-api
  tag: "1.4.2"                 # fixed
  digest: "sha256:abc…"
security:
  enabled: true
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 10001
  seccompProfile: { type: RuntimeDefault }
debug:
  enabled: false
```

```yaml
# helm-charts/demo/values-production.yaml  — ⛔ INSECURE, and nobody noticed
image:
  tag: "latest"                # ⛔ CKV_K8S_14 / CKV_K8S_43
security:
  enabled: false               # ⛔ the podSecurityContext block is gated on this
debug:
  enabled: true                # ⛔ adds a privileged debug sidecar → CKV_K8S_16
```

```yaml
# templates/deployment.yaml — the conditional that makes it diverge
      {{- if .Values.security.enabled }}
      securityContext:
        {{- toYaml .Values.podSecurityContext | nindent 8 }}
      {{- end }}
```

```bash
# SCAN A — the chart, with defaults only
checkov -d helm-charts/demo --framework helm --compact | tail -3
#   Passed checks: 38, Failed checks: 0, Skipped checks: 0     ✅ PASS

# SCAN B — rendered with production values
helm template shop-api helm-charts/demo \
  -f helm-charts/demo/values.yaml \
  -f helm-charts/demo/values-production.yaml > /tmp/rendered-prod.yaml
checkov -f /tmp/rendered-prod.yaml --framework kubernetes --compact
#   FAILED for resource: Deployment.shop-production.shop-api
#     CKV_K8S_14  image tag is not fixed
#     CKV_K8S_16  privileged container "debug"
#     CKV_K8S_20  runAsNonRoot not set
#     CKV_K8S_29  securityContext not applied
```

**What this proves — four things:**

1. ⭐⭐ **The security of a Helm chart is a property of the chart *plus a values file*, not of the chart.** "Our chart passes Checkov" is not a statement with a truth value until you say *with which values*. Production runs production values, so production values are what must be scanned.
2. **Conditionals are where chart security hides.** `{{- if .Values.security.enabled }}` means the `securityContext` **does not exist in the rendered output** when the flag is false — and a check on an absent field fails differently (and more quietly) than a check on a wrong one. Templated security controls must be scanned *after* rendering, or not scanned at all.
3. **`latest` in an override file defeats every other control.** A digest-pinned base image, a signed build, a hardened Dockerfile — all nullified by one line in an override. This is why the digest-pin discipline in [`../../cicd-learning-path/`](../../cicd-learning-path/README.md) is asserted with a regex gate (`@[0-9a-f]{64}`) on the *rendered* artifact rather than trusted in the chart.
4. **The fix belongs in the chart, not in the values.** `security.enabled: false` should not be representable — make `podSecurityContext` unconditional, or default `security.enabled` to `true` and add a custom check that fails when it is false in a production-tagged values file. ⭐ A control that can be switched off by a config file is not a control; it is a suggestion. Full treatment in [`05-CUSTOM-RULES-AND-POLICIES.md`](05-CUSTOM-RULES-AND-POLICIES.md) and [`../../helm-charts-mastery/08-BUILD-A-REAL-CHART-FROM-SCRATCH.md`](../../helm-charts-mastery/08-BUILD-A-REAL-CHART-FROM-SCRATCH.md).

**0.5**

```bash
# RUN A — naive
checkov -d infra/ --framework terraform --output json --output-file-path ./a --compact
# RUN B — resolved
checkov -d infra/ --framework terraform \
  --download-external-modules true --evaluate-variables true \
  --var-file infra/terraform.tfvars --output json --output-file-path ./b --compact

for r in a b; do
  printf '%s  ' "$r"
  jq -r '[.results.failed_checks[] | select(.check_id|startswith("CKV2_"))] | length' \
    $r/results_json.json
done
```

Realistic outcome: **RUN A reports, say, 14 `CKV2_*` failures; RUN B reports 3.** The 11 that disappeared were not real.

**Mechanically, why the naive run fails:**

`CKV2_*` checks are **graph** checks (§3). They need edges between resources — *this* bucket has *that* public-access-block attached; *this* EC2 instance is reachable from *that* internet gateway. Building those edges requires **resolving references**, and references in Terraform come from four places the naive run cannot reach:

1. **Variables.** `bucket = var.assets_bucket_name` is an unresolved symbol. Without `--evaluate-variables true` **and** `--var-file`, Checkov cannot substitute a value, so any edge that runs *through* that variable is missing → the connected-resource check fails, reporting "no public access block attached" when in fact the attachment exists but is expressed via a variable.
2. **External modules.** `source = "terraform-aws-modules/s3-bucket/aws"` — the module's *internal* resources are where the encryption/logging/block resources live. Without `--download-external-modules true`, Checkov never downloads the module, so those resources are absent from the graph entirely and every check against them fails. ⭐ This is the single biggest source of phantom `CKV2_*` failures, because module-based Terraform is the norm.
3. **Module inputs and outputs.** A value passed into a module and out again (`module.x.bucket_id`) is a two-hop reference. Unresolved hops break the chain.
4. **`count` / `for_each`.** These generate resources dynamically. Without evaluation, the *number* of instances is unknown, so checks that reason about "each bucket" cannot bind.

⭐ **The operational rule that follows:** ⛔ **never suppress a `CKV2_*` failure until you have proven the graph is wrong, not just incomplete.** Run with full resolution first. If it still fails, it is a real finding. If it stops failing, your naive run was producing noise — and suppressing that noise would have permanently hidden a check that is now correctly evaluating.

This is also why the naive run is dangerous in the *other* direction: teams that see 14 graph failures and cannot make them go away conclude "Checkov's graph checks are broken" and add `--skip-check CKV2_*` globally — disabling the exact class of check that is Checkov's unique value.

**0.6**

```bash
mkdir -p reports
checkov -d k8s/ \
  --framework kubernetes \
  --soft-fail \
  --hard-fail-on CKV_K8S_16 \
  --hard-fail-on CKV_K8S_35 \
  --output sarif    --output-file-path ./reports \
  --output json     --output-file-path ./reports \
  --compact
echo "exit=$?"
```

**(a) Exits 0 despite failures** — the directory contains, say, 11 failures including `CKV_K8S_21` and `CKV_K8S_14`, none of which are in the hard-fail list. `--soft-fail` forces exit 0.

```
exit=0
```

**(b) A `CKV_K8S_16` violation still fails it:**

```bash
cat > /tmp/bad.yaml <<'EOF'
apiVersion: v1
kind: Pod
metadata: { name: priv-pod, namespace: shop-production }
spec:
  containers:
    - name: c
      image: ghcr.io/3558bhk/shop-api@sha256:abc
      securityContext: { privileged: true }        # ⛔ CKV_K8S_16
EOF
checkov -f /tmp/bad.yaml --framework kubernetes --soft-fail \
  --hard-fail-on CKV_K8S_16 --compact
echo "exit=$?"
#   exit=1     ✅ --hard-fail-on overrides --soft-fail for exactly this check
```

⭐ **That is the whole point of the flag pair:** `--soft-fail` sets the *default* disposition to non-blocking, and `--hard-fail-on` carves out an explicit, named, committed exception list. Your non-negotiables are visible in the command line, in git, and in review — not buried in a config file nobody reads.

**(c) The SARIF still contains everything:**

```bash
jq '.runs[0].results | length' reports/results_sarif.sarif
jq -r '.runs[0].results[].ruleId' reports/results_sarif.sarif | sort | uniq -c | sort -rn
```

All 11 (or 12, with the privileged pod) appear — including the ones that did **not** gate. ⭐ **This is the property that makes the pattern safe:** soft-failing does not mean *not reporting*. Visibility is total; enforcement is selective and explicit. Compare `--skip-check`, which removes the finding from the report entirely (§0.8).

**0.7** One scan, three formats:

```bash
checkov -d . --framework kubernetes --framework helm \
  --output cli      \
  --output sarif    --output-file-path ./reports \
  --output json     --output-file-path ./reports \
  --output junitxml --output-file-path ./reports
```

| Format | Consumed by | What they do with it |
|---|---|---|
| **`sarif`** | ⭐⭐ **GitHub code scanning / Azure DevOps** → **the pull-request author** | Uploaded via `github/codeql-action/upload-sarif`. Findings render **on the diff, on the line, assigned to the author**, with the check name and a remediation link. This is the only format where a finding reliably gets fixed, because it arrives at the moment and place the code is being read — not in a build log nobody opens |
| **`json`** | **your own scripts** → the gate logic, the baseline diff, the dashboard | `jq` to count new failures against the recorded baseline, to compute trend, to promote checks from report-only to hard-fail. Also what you feed a custom "did anything get worse?" step |
| **`junitxml`** | **Jenkins / GitLab CI native test reporting** → the CI UI | Renders as a test suite with pass/fail counts, so infrastructure policy appears in the same place developers already look for test failures. Zero custom tooling |
| *(bonus)* `cli` | **a human, locally** | the developer's own loop before they push |

⭐ **The principle:** the *finding* is one thing; the *delivery mechanism* determines whether it becomes a fix. Emitting only `cli` into a CI log is the most common way to have a working scanner and a non-working programme — the output exists and reaches nobody. Match the format to the consumer, and emit several.

**0.8** ⭐⭐ **Why `--skip-check CKV_K8S_21` was the wrong tool — four compounding reasons:**

1. **It deletes the finding, not just the failure.** `--skip-check` means the policy is **not evaluated at all**. It does not appear in the SARIF, not in the JSON, not on any dashboard, not in the compliance report. There is no record that the check ran and was accepted — the check simply ceased to exist for that repo. Two months later, nobody could have told you the new service was in `default`, because nothing was looking.
2. **It is repo-wide and time-unbounded.** One flag on one CI command disabled the control for every current and *future* manifest in that directory, forever, with no expiry and no re-review trigger.
3. **It is invisible to the person who needs it.** A flag in a pipeline command is read by nobody writing a Deployment. The developer who deployed into `default` never saw a warning, because there was none.
4. **It has no owner and no reason.** "We added `--skip-check` to make the build green" is not a decision record. There was no statement of *why* `default` was acceptable, no compensating control, nobody accountable for revisiting it.

⭐ **The meta-failure:** the pipeline being green became the goal, and the check was an obstacle to it. That is what happens when a gate cannot be satisfied — the team optimises the gate rather than the code. Same dynamic as the Trivy `.trivyignore` pile-up in [`../trivy/00-INSTALL-AND-FUNDAMENTALS.md`](../trivy/00-INSTALL-AND-FUNDAMENTALS.md) task 0.8.

**What should have been used instead — in preference order:**

```yaml
# ① BEST: fix the manifest. The check is correct; the code was wrong.
metadata:
  name: checkout
  namespace: shop-production        # ← the actual fix, and it was one line
```

```yaml
# ② If a SPECIFIC resource genuinely must live in default — inline skip, in the manifest,
#    where the next reader will see it:
metadata:
  name: kube-root-ca-probe
  namespace: default
  annotations:
    checkov.io/skip1: >-
      CKV_K8S_21=Bootstrap probe pod must run in default before the namespace
      controller exists. Owner: platform@. NetworkPolicy n/a (no ingress).
      Reviewed 2026-09-01. Expires 2027-03-01. Ticket #4412.
```
⭐ Note this is a **Kubernetes annotation**, not a comment — for K8s YAML Checkov reads `checkov.io/skipN`. Terraform uses the comment form `#checkov:skip=CKV_AWS_18:reason`. Getting this wrong produces a skip that silently does nothing.

```bash
# ③ If it is a repo-wide accepted exception: --soft-fail-on, NOT --skip-check
checkov -d k8s/ --soft-fail-on CKV_K8S_21
#   → the check STILL RUNS and STILL APPEARS in every report;
#     it just does not fail the build. Visibility retained.
```

**The three properties any suppression must have to have prevented this:**

| # | Property | What it would have changed |
|---|---|---|
| **1** | **An owner** — a named person or team, recorded | Someone is accountable for the exception. The platform team would have been asked "is `default` acceptable for this workload?" at review time, and the answer would have been no |
| **2** | **A reason and a compensating control** — *why* it is acceptable, and what makes it safe | Forces the question "does `default` have a NetworkPolicy and a ResourceQuota?" If the honest answer is no, the suppression cannot be written. The incident required the absence of both — a reason field would have surfaced that |
| **3** | **An expiry** — a date after which the suppression fails the build | ⭐ The single most important one. An expiry converts a permanent exemption into a **scheduled decision**. Even a badly-reasoned suppression gets re-examined on its expiry date, and "we forgot" is not survivable when forgetting breaks the build |

Plus a fourth, structural property: **it must remain in the report.** A suppression that removes the finding from the SARIF, the dashboard and the compliance output is not a suppression — it is a blind spot with paperwork. `--soft-fail-on` and inline skips keep the finding visible; `--skip-check` does not. That distinction alone would have left a trail on the dashboard that someone would eventually have followed.

**The auditable form** — [`../03-COMPLIANCE-REPORTING-AND-AUDIT.md`](../03-COMPLIANCE-REPORTING-AND-AUDIT.md):
```
policy:    CKV_K8S_21
resource:  Deployment.default.kube-root-ca-probe
owner:     platform-team@
reason:    must precede namespace controller bootstrap
control:   no ingress; no ServiceAccount automount
reviewed:  2026-09-01
expires:   2027-03-01
ticket:    #4412
```

**0.9** ⭐⭐ 30 repos · 4,000 existing failures · no security team · one quarter to blocking.

---

### Checkov rollout plan

**The governing constraint.** With no security team there is **no triage capacity**. Every design decision below follows from that: findings must land on an owner automatically, exceptions must expire automatically, and the platform team must never become a queue. Anything requiring a human to review a finding that is not its author will fail by week three.

#### Phase 0 — weeks 1–2 · Platform, not policy

One week of platform work saves thirty repos of copy-paste:

- **Pin** Checkov **3.3.17** by digest (Docker) / exact version (pipx). Renovate bumps it; a digest-only change auto-approves. ⛔ No `latest`, no `master`, no `v3` on the Action — pin the **commit SHA**. (`../02-SUPPLY-CHAIN-AND-PINNING.md`)
- **One shared definition** — a reusable workflow / shared-library job / pipeline template. Repos *inherit*; they do not copy. ⭐ This is the single most important deliverable: it is the only reason a future threshold change is one PR instead of thirty.
- **`.checkov.yaml` in each repo**, committed, reviewed like code: framework list, skip paths, the hard-fail set, the baseline reference.
- **Report-only everywhere.** `--soft-fail`, all formats emitted (§9). Nothing blocks. The quarter's credibility depends on phase 0 blocking nobody.

#### Phase 1 — weeks 2–4 · Measure, then sort the 4,000

```bash
# per repo: capture the baseline
checkov -d . --framework kubernetes --framework helm --framework dockerfile \
             --framework secrets --framework terraform \
             --soft-fail --output json --output baseline --output-file-path ./reports --compact
```

Then **classify the 4,000 by check ID, not by repo** — because the distribution is always the same, and it dictates the whole plan:

| Bucket | Typical share | Action |
|---|---|---|
| **The same 5–8 checks, everywhere** (`CKV_K8S_10`–`13` resource limits, `CKV_K8S_21` default ns, `CKV_K8S_8`/`9` probes) | ⭐ **60–75%** | **Fix once, in the shared Helm chart / base manifest**, not 30 times. This is the highest-leverage move in the entire plan |
| **Genuinely dangerous, few** (`CKV_K8S_16` privileged, `CKV_K8S_35` secrets in env, `CKV_AWS_24` open SSH, `CKV_SECRET_*`) | 2–5% | **Fix immediately**, out of sequence, before any gate exists. These are incidents, not debt |
| **Framework noise / graph artefacts** (unresolved `CKV2_*`, vendored code, generated manifests) | 10–20% | Fix the *scan* (`--evaluate-variables`, `--download-external-modules`, `--skip-path`), not the code. §0.5 |
| **Real, hard, expensive** (readOnlyRootFilesystem on stateful apps, seccomp on legacy) | 10–15% | Baseline it. Quarterly burn-down. Each gets an owner |

⭐ **That first row is the plan.** If 70% of 4,000 failures are eight checks about missing resource limits and probes, you do not need thirty teams to change behaviour — you need **one chart PR** adding `resources` and probe defaults to the shared `_helpers.tpl` ([`../../helm-charts-mastery/07-HELPERS-NAMED-TEMPLATES.md`](../../helm-charts-mastery/07-HELPERS-NAMED-TEMPLATES.md)). 2,800 failures disappear in an afternoon, and the remaining 1,200 are the ones that actually need decisions. **Do this before you set any gate** — gating first, then discovering the fix was centralised, wastes the quarter's goodwill.

#### Phase 2 — weeks 4–6 · The gate shape

Identical in all 30 repos, in the shared definition:

```bash
checkov -d . \
  --framework kubernetes --framework helm --framework dockerfile --framework secrets \
  --soft-fail \
  --hard-fail-on CKV_K8S_16 --hard-fail-on CKV_K8S_20 \
  --hard-fail-on CKV_K8S_35 --hard-fail-on CKV_K8S_38 \
  --hard-fail-on CKV_AWS_24 --hard-fail-on CKV_DOCKER_3 \
  --hard-fail-on CKV_SECRET_1 \
  --output sarif --output json --output junitxml --output-file-path ./reports --compact
```

- **Six or seven non-negotiables block from day one** — the unarguable, cheap-to-fix set. Everything else reports.
- **Plus a new-findings gate:** compare today's JSON against the committed baseline; **any failure not in the baseline blocks.** ⭐ This is the actual ratchet, and it is what makes "4,000 existing failures" survivable — you never ask anyone to fix history, you only refuse to let it grow.

```bash
jq -r '.results.failed_checks[] | "\(.check_id)|\(.resource)"' reports/results_json.json | sort > today.txt
comm -13 baseline.txt today.txt        # lines only in today = NEW failures
[ -s new.txt ] && { echo "⛔ new Checkov failures:"; cat new.txt; exit 1; }
```

#### Phase 3 — weeks 6–12 · Burn-down and promotion

- **Baseline is committed, dated, visible**, and shrinks on a schedule: **10% per quarter per repo**, tracked on one dashboard. ⛔ A baseline that never shrinks is a permanent exemption wearing a date.
- **Promote checks from report-only to `--hard-fail-on` one or two per quarter**, in a PR to the shared definition, so the ratchet's history is in git. Order: whichever check has the fewest remaining baseline failures first — cheap wins, and each promotion is defensible because the number is already near zero.
- **SARIF on every PR** from week 4 — findings on the diff, assigned to the author. ⭐ This is the mechanism that makes the burn-down happen without a security team: the fix arrives as part of normal work, not as a mandate.

#### Ownership and suppression

- ⭐ **The team that owns the repo owns its findings.** There is no central queue. The platform team owns the *tool, the pinned version, the shared gate and the shared chart* — never a triage backlog.
- **Suppressions**: only inline (`checkov.io/skipN:` for K8s, `#checkov:skip=` for Terraform) or `--soft-fail-on` — ⛔ **never `--skip-check`**, because it deletes the finding from every report (§0.8). Every suppression carries **owner · reason · compensating control · review date · expiry**, and **an expired suppression fails the build**. That is what makes the expiry real rather than decorative.
- Suppression changes require a CODEOWNERS reviewer, so a suppression is a reviewed decision rather than a lone commit.

#### The two numbers reported weekly

⭐ Not "total failures". That number only ever rises with new code and teaches everyone to ignore the report.

| # | Metric | Why it is the right one |
|---|---|---|
| **1** | **New failures introduced this week, per repo** | The ratchet itself. It should be **≈ 0** and stay there. If it is not, the gate is not working — that is a *process* signal you can act on in the same week. It is also the number that never grows with repo count or codebase size, so it stays meaningful at 30 repos and at 300 |
| **2** | **Oldest age of an open finding in the six non-negotiables** | Measures whether the *dangerous* class is being fixed, not just counted. Target: **< 7 days**, always. One number that says whether the programme is protecting anything |

Three supporting numbers on the same dashboard, reviewed monthly rather than weekly: **baseline remaining (absolute + % of starting)**, **suppressions open vs expiring in 30 days**, and **hard-fail checks promoted to date**. The last one is the only evidence that the ratchet is actually tightening rather than holding still.

**The one rule that holds it together:** ⭐ **every finding has exactly one owner, and every exception has an expiry.** With no security team, those two properties *are* the control environment. The pinned version, the shared definition, the baseline, the SARIF-on-PR and the two weekly numbers all exist to make those two things true at 30-repo scale without anyone having to remember.

**What "done at one quarter" looks like:** all 30 repos on the shared gate; six non-negotiables blocking; new-findings blocking; baseline reduced by ~25% (most of it from the phase-1 centralised chart fix); SARIF on every PR; suppressions structured and expiring; two numbers on a dashboard someone looks at. ⭐ And one check promoted from report-only to hard-fail — the proof that the ratchet can move.

</details>

---

## ➡️ Next

**[`01-FIRST-SCAN-AND-READING-OUTPUT.md`](01-FIRST-SCAN-AND-READING-OUTPUT.md)** — reading output in depth: the pass/fail/skipped model, how Checkov locates a resource, how to read a graph-check failure, and turning 300 findings into a work list.

**Then:** [`02-CONFIGURATION-AND-BASELINES.md`](02-CONFIGURATION-AND-BASELINES.md) — `.checkov.yaml`, inline skips done properly, and baselining a legacy repo without disabling the gate.

**Read alongside:** [`../00-WHICH-TOOL-FOR-WHAT.md`](../00-WHICH-TOOL-FOR-WHAT.md) · [`../trivy/00-INSTALL-AND-FUNDAMENTALS.md`](../trivy/00-INSTALL-AND-FUNDAMENTALS.md) · [`../../helm-charts-mastery/`](../../helm-charts-mastery/README.md)

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish%20Kumar%20Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn → <https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260>
🐙 GitHub → <https://github.com/3558Bhk>

*Built for engineers who learn by breaking things on purpose.*

</div>
