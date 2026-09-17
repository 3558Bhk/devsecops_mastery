# 08 · CI/CD & GitOps

Expected in every DevOps/Platform loop. The differentiator is not tool trivia — it's **pipeline architecture, deployment strategy, security of the pipeline itself, and the pull-vs-push debate.**

*Versions referenced: Argo CD 3.x (3.5 adds internal mTLS, Git commit signature verification/"Source Integrity", Helm 4 support, ApplicationSets in any namespace), GitHub Actions, GitLab CI, Tekton, Jenkins.*

---

## 🟢 Basic

### 1. CI vs CD vs CD — get the vocabulary exact
| Stage | What it means | Automatable? |
|---|---|---|
| **CI** — Continuous Integration | Merge to trunk frequently; every commit builds + tests | Always |
| **CD** — Continuous **Delivery** | Every change is *deployable* to production; a human presses the button | Build/deploy automated, **release decision manual** |
| **CD** — Continuous **Deployment** | Every change that passes goes to production automatically | **Fully automated, including release** |
| **Continuous Release** | Sometimes used to mean feature-flag-controlled release decoupled from deploy | — |

**The distinction that scores:** "Continuous Delivery means production-ready at all times with a manual gate; Continuous Deployment removes the gate. You can only safely do the latter with automated rollback, canary analysis, strong test coverage, and **feature flags decoupling deploy from release**. Most teams say 'CD' and mean Delivery. I'd argue most teams should aim for Delivery first, earn Deployment, and use flags so the deploy isn't the risky event."

**Also know:** trunk-based development (short-lived branches, integrate daily, feature-flag incomplete work) vs GitFlow (long-lived release branches — slows feedback, causes merge hell). Modern CI practice is trunk-based; **GitFlow is a smell in a high-performing team**, and saying so with reasoning is fine.

### 2. What belongs in a good CI pipeline?
```
1. Lint/format         (seconds)      golangci-lint, ruff, eslint, shellcheck, yamllint
2. Unit tests          (seconds)      with coverage gate (trend, not absolute %)
3. Security            (parallel)     SAST (semgrep/CodeQL), secrets (gitleaks/trufflehog), deps (SCA: trivy/grype/dependabot), licence check
4. Build               (parallel)     compile, multi-arch if needed
5. Container build     (parallel)     BuildKit, layer cache, --sbom --provenance
6. Image scan          (parallel)     trivy/grype; fail on NEW fixable criticals
7. Integration tests   (minutes)      against real dependencies via containers/services
8. Contract tests      (minutes)      consumer-driven (Pact) for API boundaries
9. E2E / smoke         (minutes)      a small, curated set — NOT the whole suite
10. Push + sign        (seconds)      push by digest, cosign sign, attach SBOM/attestations
11. Deploy to dev/stg  (GitOps commit or push)
```
**Principles:**
- **Fail fast, run cheap things first.** A 40-second lint failure shouldn't cost 12 minutes of compute.
- **Parallelise independent stages**; keep the critical path short.
- **Deterministic and hermetic**: pinned tool versions, locked dependencies, no reliance on ambient credentials, no network access except to a controlled mirror. Same commit → same result.
- **Every stage produces an artifact**, and the *same artifact* is promoted through environments. **Never rebuild per environment** — if staging and prod are built separately, you tested something you didn't ship.
- **Pipeline as code, versioned with the app**, reviewed in PRs.
- **Flaky tests are an emergency**, not an annoyance: quarantine, alert on flake rate, fix or delete. A pipeline people don't trust gets bypassed, and then you have no pipeline.
- **Metrics**: DORA four keys (lead time for changes, deployment frequency, change failure rate, MTTR/failed-deployment recovery time) plus cycle-time breakdown to find the bottleneck stage.

### 3. Deployment strategies compared
| Strategy | Downtime | Rollback speed | Cost | Risk control | Use when |
|---|---|---|---|---|---|
| **Rolling update** | None | Medium (redeploy old version) | 1× + surge | Low | Default; backwards-compatible changes |
| **Recreate** | **Yes** | Medium | 1× | None | Single-instance stateful apps; incompatible old/new |
| **Blue/green** | None | **Instant** (switch back) | **2×** | High (full env validation) | Big changes, need instant abort |
| **Canary** | None | Fast | 1× + small | **Highest** (real traffic, small blast radius, metric-gated) | Anything customer-facing at scale |
| **A/B** | None | Fast | 1× + | High | Product experiments, route by user attribute |
| **Shadow/mirror** | None | N/A (no user impact) | 2× | Extreme | Validating with real traffic, zero risk |
| **Ring deployment** | None | Fast | 1× | Extreme | Internal → 1% → 10% → 50% → 100% (Microsoft model) |
| **Feature flags** | None | **Instant** (toggle) | 1× | Extreme | **Decouples deploy from release** — the highest-leverage practice |

**How to actually split traffic in Kubernetes:**
- Two Deployments + Service selector switch (blue/green, atomic but coarse).
- **Ingress/Gateway API weights** (`HTTPRoute` `backendRefs[].weight`) — 95/5 canary.
- **Argo Rollouts** — `Rollout` CRD with `canary.steps`, `analysis` templates (Prometheus queries) and automatic `promote`/`abort`. The standard answer.
- **Flagger** — mesh-aware progressive delivery with metric analysis.
- **Service mesh** (Istio/Linkerd) — `VirtualService` weights, header-based routing, mirroring.

```yaml
# Argo Rollouts canary, abridged
strategy:
  canary:
    steps:
    - setWeight: 5
    - pause: { duration: 5m }
    - analysis:
        templates: [{ templateName: success-rate }]
        args: [{ name: service-name, value: api }]
    - setWeight: 25
    - pause: {}                       # manual approval gate
    - setWeight: 50
    - pause: { duration: 10m }
    - analysis: { templates: [{ templateName: p99-latency }] }
---
# AnalysisTemplate: automated rollback trigger
metrics:
- name: success-rate
  interval: 60s
  count: 5
  successCondition: result[0] >= 0.995
  failureLimit: 2
  provider:
    prometheus:
      query: |
        sum(rate(http_requests_total{app="{{args.service-name}}",code!~"5.."}[5m]))
        / sum(rate(http_requests_total{app="{{args.service-name}}"}[5m]))
```
**Say this:** "The value of a canary isn't the 5% — it's the **automated analysis and rollback**. A canary with a human watching a dashboard is a rolling update with extra steps and a slower reaction time. Argo Rollouts + Prometheus analysis gives you a rollback in under a minute, at 3am, with nobody awake."

### 4. GitOps — the four principles and why they matter
OpenGitOps principles:
1. **Declarative** — the entire system state is described declaratively (Kubernetes manifests/Helm/Kustomize).
2. **Versioned and immutable** — state lives in Git; every change is a commit, so you get history, diff, blame, and revert for free.
3. **Pulled automatically** — an agent **inside** the cluster pulls desired state from Git and applies it.
4. **Continuously reconciled** — the agent detects drift between Git and the cluster and corrects it (or alerts).

**Why it's better than push-based CI/CD:**
- **No external credentials into the cluster.** The agent runs inside with a scoped ServiceAccount; CI never holds a cluster-admin kubeconfig. **This is the biggest security win** — a compromised CI system can't directly modify your cluster.
- **Drift detection is built in.** `kubectl edit` in production shows up as OutOfSync immediately.
- **Rollback = `git revert`.** One mechanism for every change, with review and audit.
- **Disaster recovery = point Argo CD at the repo.** Rebuilding a cluster from Git is a tested, routine operation rather than an archaeology project.
- **Uniform audit**: who changed prod, when, why (the PR description), approved by whom.

**The honest limitations (say these — it's what makes the answer senior):**
- **Git doesn't hold secrets.** You need Sealed Secrets, SOPS+age, External Secrets Operator, or Vault — each with its own key-management problem.
- **Not everything is declarative.** Imperative operations (a database migration, a one-off job, a manual scaling action during an incident) don't fit neatly; you end up with hooks, sync waves, or a separate process. **Pretending otherwise is the classic GitOps failure.**
- **Emergency access**: during an incident, "open a PR, get a review, merge, wait for sync" may be too slow. You need a documented break-glass path *and* the discipline to reconcile back to Git afterwards (otherwise drift).
- **Repo sprawl and scale**: thousands of Applications → apiserver/etcd load, sync storms, and noisy reconciles. ApplicationSets, sharding, and directory-per-app patterns matter.
- **Config drift within Git**: if the manifests are generated (Helm + values per env), the *generated* output isn't what's in Git — you need to render and review the diff, or trust the templating.

### 5. Argo CD vs Flux — the real comparison
| | **Argo CD** | **Flux v2** |
|---|---|---|
| UI | ✅ Excellent, the main draw | Limited (weave-gitops/third-party) |
| Architecture | Monolithic-ish: API server, repo server, application controller | Composable controllers: **source-controller, kustomize-controller, helm-controller, image-automation-controller, notification-controller** |
| CRDs | `Application`, `ApplicationSet`, `AppProject`, `Rollout`(via Argo Rollouts) | `GitRepository`/`OCIRepository`/`HelmRepository` (Sources) + `Kustomization`/`HelmRelease` (Deployments) |
| Multi-tenancy | `AppProject` (source repos, destinations, resource whitelists, roles) | Namespace + RBAC on the CRs; `Kustomization` impersonation |
| Image update automation | Argo CD Image Updater (separate, bolt-on) | **Built-in** (`ImageUpdateAutomation` + `ImagePolicy`) — writes back to Git |
| Health/sync | Rich health heuristics per resource type, sync waves, hooks | Health via `Kustomization.status`; fewer built-in hooks |
| Progressive delivery | **Argo Rollouts** (deep integration) | Flagger (same project family, works with both) |
| Ecosystem | CNCF graduated; huge; enterprise support available | CNCF graduated; more "Kubernetes-native"/composable |
| Complexity | Higher to run well (repo-server memory, redis, notifications, SSO) | Lower per component, more components to understand |
| **Helm 4 / OCI** | 3.5 adds Helm 4 support; OCI registries as sources since 3.1 | OCIRepository as a first-class source |

**Answer:** "Argo CD when you want a UI, ApplicationSets for fleet management, AppProject multi-tenancy, and tight Argo Rollouts integration — that's most platform teams. Flux when you want a lean, composable, API-first controller set with built-in image automation and you're comfortable living in `kubectl` and Git. Both are CNCF-graduated and both are fine; the deciding factor is usually whether your developers need a UI and how much you rely on ApplicationSets."

**Argo CD specifics worth naming (3.x era):**
- **Sync waves** (`argocd.argoproj.io/sync-wave: "-1"`) for ordering: CRDs → namespaces → config → workloads → jobs. And **sync hooks** (`PreSync`, `Sync`, `PostSync`, `SyncFail`) for migrations and smoke tests — `PreSync` Job for a DB migration is the idiomatic GitOps answer to "where do migrations go?".
- **Self-heal** (`syncPolicy.automated.selfHeal: true`) reverts manual drift; **prune** deletes resources removed from Git (**dangerous** — a bad merge can delete production; scope it carefully and consider `prune: false` + alerts for critical namespaces).
- **ApplicationSet** generators: Git directory, Git files, list, cluster, matrix/merge, SCM provider, pull-request. One template → hundreds of Applications. **3.5 lets ApplicationSets live in any namespace** (long-requested for namespace-scoped GitOps).
- **AppProject** for multi-tenancy: allowed source repos, destinations, resource whitelist/blacklist, namespace-scoped roles, orphaned-resource monitoring.
- **Impersonation** (beta in 3.5): Argo CD applies resources *as* a specified ServiceAccount, so RBAC is enforced from the app's identity, not Argo's (usually cluster-admin) — a real least-privilege improvement.
- **Source Integrity / commit signature verification** (3.5): verify Git commit signatures before syncing — supply-chain control.
- **Internal mTLS** (3.5): enforced mutual TLS between Argo CD components.
- **Repo-server memory** is the classic scaling pain: large Helm charts + many apps → OOM. Fix: replicas, resource limits, shallow clones (3.3), and splitting repos.

---

## 🔵 Advanced

### 6. Push vs pull deployment — the architectural argument
**Push (Jenkins/GitHub Actions runs `kubectl apply` / `helm upgrade`):**
- ✅ Simple to start; one system; easy imperative steps; works for non-Kubernetes targets (VMs, Lambda, DB migrations).
- ❌ **CI holds cluster credentials** (usually cluster-admin) — a compromised pipeline = compromised cluster. This is the killer argument.
- ❌ No drift detection; the cluster's actual state is unknown between deploys.
- ❌ Multiple writers (CI, humans, other tools) with no single source of truth.
- ❌ Scaling to many clusters means many credential sets and many pipeline variants.

**Pull (Argo CD / Flux agent inside the cluster):**
- ✅ Credentials stay inside; the agent has scoped RBAC; **CI only needs write access to Git**.
- ✅ Continuous reconciliation = drift detection and self-healing.
- ✅ One mechanism for N clusters (register each cluster's agent to the Git repo).
- ✅ Rollback = git revert, auditable.
- ❌ Requires everything to be expressible declaratively; imperative steps need hooks.
- ❌ Another system to run, secure, upgrade and monitor (Argo CD is itself a critical, cluster-admin-ish workload — **it needs its own hardening and monitoring**, and an Argo CD outage means no deploys).
- ❌ Sync latency for urgent changes (mitigated by webhooks/notifications).

**The mature position:** "Pull for cluster state, always — the credential argument settles it. But CI still does the imperative work: build, test, scan, sign, publish the artifact, and **write the new image digest into Git** (the 'commit back' step). And some things genuinely can't be GitOps'd — database migrations against an external RDS, DNS changes at a provider without a good operator, one-off data fixes. For those I use a controlled, audited imperative path with just-in-time credentials, and I record what happened so Git stays the best-available source of truth. Pretending 100% GitOps is achievable is how teams end up with a shadow process nobody documents."

### 7. Pipeline security — because CI/CD is the highest-value target
**Threat model:** an attacker who controls your pipeline controls every environment. Real incidents: SolarWinds (build system), Codecov (CI script), ua-parser-js/npm (package takeover), Travis CI (leaked secrets across customers), the `GITHUB_TOKEN` privilege escalations.

**Controls:**
1. **Least-privilege `GITHUB_TOKEN`**: default `permissions: {}` at the workflow level, grant only what's needed per job (`contents: read`, `id-token: write`, `packages: write`). **The default `write-all` for repository-scoped tokens has caused countless supply-chain compromises.**
2. **No long-lived cloud credentials in CI secrets.** Use **OIDC federation**: GitHub Actions / GitLab → AWS `AssumeRoleWithWebIdentity` / GCP Workload Identity Federation / Azure federated credentials → **short-lived, scoped, no keys to rotate or leak**. This is the single highest-value change most teams can make. Condition the role's trust policy on the repo, branch, and environment (`sub` claim) so a PR from a fork can't assume the prod role.
3. **Fork/PR protection**: never expose secrets to `pull_request` from forks (GitHub doesn't by default — but `pull_request_target` **does**, and that's a well-known RCE-to-secrets path). Validate before running anything with credentials.
4. **Pinned actions/dependencies by commit SHA**, not tag. `uses: actions/checkout@v4` is mutable — the tag can move. `uses: actions/checkout@<40-char-sha>` isn't. Same for container base images (digest) and Terraform providers.
5. **Secret scanning + prevention**: gitleaks/trufflehog in pre-commit *and* CI; push protection; **rotate anything that ever leaked** (scanning history finds what the pre-commit hook missed). Never `echo` secrets; mask them; avoid env vars where a file works.
6. **Signed artifacts and verified builds**: cosign sign images, attach **provenance/SLSA attestations**, verify at admission (Kyverno/policy-controller). SLSA levels describe build integrity — L3 is the practical target (hardened builds, non-falsifiable provenance).
7. **SBOM generation and vulnerability gating** in CI, with policy on **new** criticals rather than the whole backlog.
8. **Isolated, ephemeral runners** — self-hosted runners on shared infra are an escape route into your network. Use ephemeral, network-restricted runners (GitHub-hosted, or ARC — Actions Runner Controller — with short-lived pods and egress policy). **Never attach a self-hosted runner to a repo that accepts public PRs.**
9. **Environment protection**: GitHub Environments / GitLab protected environments with required reviewers for `production`, so a merge to main doesn't auto-deploy without a human where you need one.
10. **Audit everything**: who triggered, from what commit, with what credentials, deploying what digest, to where. Ship pipeline logs and artifact metadata off-box.
11. **Protect the Git repo itself**: branch protection, required reviews, required status checks, signed commits (optional), CODEOWNERS for the deploy manifests, and **no force-push to main**. A GitOps cluster is only as trustworthy as its repo's write access.
12. **Beware the deploy manifest repo**: with GitOps, write access to the config repo = production access. Treat it accordingly (it often has *weaker* controls than the code repo — a real gap).

### 8. Artifact promotion and environments
**The rule:** *build once, promote the immutable artifact.*
```
commit abc123 → build → image registry/app@sha256:9f2c…  + SBOM + signature + provenance
                        │
              dev  ─────┤  (same digest)
              test ─────┤
              stg  ─────┤
              prod ─────┘  (same digest — verified signature, verified SBOM)
```
**What varies per environment is *configuration*, not the artifact.** So:
- **Config**: Helm values per env, Kustomize overlays, or (better) **environment-agnostic manifests + a config service** (ConfigMap generated from a config repo, or runtime config from a flag/config service). The 12-factor rule: config in the environment, not the build.
- **Version pinning in Git**: the promotion step is a commit that changes `image:` from `sha256:aaa` to `sha256:bbb` in the `prod/` directory. **That commit is the deploy**, it's reviewable, and `git revert` is the rollback.
- **Anti-pattern to name:** building per environment (`docker build --build-arg ENV=prod`). Now the prod artifact was never tested in staging, and you can't prove what's running.
- **Traceability both ways**: from a running pod → image digest → build → commit → PR → reviewer → tests that ran. And from a CVE → SBOM → which images contain the package → which environments run them. **That second direction is what an SBOM is actually for.**
- **Environment parity**: staging should match prod in topology, data shape (anonymised/synthetic), scale (fractional but not trivial), and configuration mechanism. "Works in staging" is meaningless if staging is a single replica with no autoscaler and an empty database.

### 9. Branching, versioning, and release strategies
| Strategy | Description | When |
|---|---|---|
| **Trunk-based** | Everyone commits to `main` daily; incomplete work behind flags; release branches cut only for patching | Modern default; enables CD |
| **GitHub Flow** | `main` + short-lived feature branches + PR | Small teams, continuous deploy |
| **GitLab Flow** | `main` + environment branches (`pre-prod`, `prod`) or release branches | Teams needing staged promotion via branches (note: with GitOps, environment *directories* usually beat environment *branches*) |
| **GitFlow** | `main`, `develop`, `feature/*`, `release/*`, `hotfix/*` | Legacy; long release cycles; regulated products with parallel supported versions. **High merge cost, slow feedback** |
| **Release trains** | Fixed cadence (weekly), whatever's ready ships | Large orgs, coordination-heavy |
| **CalVer vs SemVer** | `2026.09.1` vs `2.4.1` | CalVer for continuously deployed services (no compatibility promise); SemVer for libraries/APIs where consumers depend on compatibility |

**Versioning discipline that matters:**
- **SemVer for anything consumed by others** (libraries, SDKs, APIs, Helm charts, Terraform modules). Breaking change = major.
- **Image tags**: never `latest` in production. Use `<git-sha>` (immutable, traceable) and/or `<semver>`, and **deploy by digest** for the strongest guarantee. Keep human-readable tags for humans, digests for machines.
- **Helm chart versioning**: chart version ≠ app version; bump both deliberately; `apiVersion: v2` with `type: application` and dependencies pinned.
- **Deprecation windows** for anything public, with a communicated removal date and a loud runtime/CI warning before it.

### 10. Testing strategy in a pipeline — the pyramid and what to actually run where
```
                /\        E2E (few, curated, slow, flaky-prone)   ← staging, nightly + pre-promotion
               /  \       Integration / contract (moderate)       ← PR + main
              /    \      Unit (many, fast, deterministic)        ← every commit, seconds
             /______\     Static: lint, SAST, SCA, secrets, IaC   ← every commit, parallel
```
| Level | Speed | Confidence in | Tools |
|---|---|---|---|
| Static analysis | ms–s | Style, bug patterns, vulnerabilities, secrets, IaC correctness | golangci-lint, ruff/mypy, semgrep, CodeQL, gitleaks, trivy, **checkov/kubeconform/kubeval**, **conftest/OPA**, `tflint`, `terraform validate`, `promtool`, `helm lint`, `yamllint`, **hadolint** (Dockerfiles) |
| Unit | s | Logic in isolation | Language-native; mocks at boundaries |
| Component | s–m | One service with real deps in containers | testcontainers, docker compose, kind |
| Contract | s–m | **API compatibility between services** | Pact (consumer-driven), schema registry compatibility checks, OpenAPI diff (**oasdiff** — catches breaking API changes in PRs) |
| Integration | m | Services together | kind/k3d/minikube, Testcontainers, ephemeral environments |
| E2E | m–10m | User journeys | Playwright/Cypress, k6/Gatling for load, Postman/Newman |
| Chaos/resilience | m–h | Failure behaviour | LitmusChaos, Chaos Mesh, toxiproxy |

**Key senior points:**
- **Test the infrastructure, not just the app.** `kubeconform`/`kubeval` + `conftest` policies on manifests, `helm template | kubeconform`, `promtool check rules`, `terraform validate` + `tflint` + `checkov`, `hadolint` on Dockerfiles, **`pluto`/`kubent` for deprecated API detection before a cluster upgrade**. These catch more production incidents than most unit tests, and they run in seconds.
- **Ephemeral preview environments** per PR (namespace or cluster spun up by the pipeline, torn down on merge) — huge confidence win, real cost concern. Tools: Argo CD ApplicationSet with a PR generator, Okteto, Garden, Uber's/Netflix's internal platforms, `kubectl-slice` + kind for cheap versions.
- **E2E flakiness management**: quarantine labels, retry-with-alert (not silent retry), a flake-rate SLO, and deleting tests that don't earn their cost. **A retried-and-passed flaky test is a hidden failure.**
- **Shift-left is a slogan; the substance is fast feedback.** A 45-minute pipeline is a 45-minute feedback loop, and developers will batch changes, which makes failures harder to bisect. Optimising pipeline *duration* is a first-class engineering goal — measure it, cache aggressively, parallelise, and split by changed paths (`paths:` filters).

---

## 🔴 Scenario

### 11. "Our deploys take 45 minutes and fail 20% of the time. Fix the pipeline."
**First, measure — don't guess.** Instrument every stage with duration and outcome, and compute: total lead time (commit → prod), per-stage p50/p95, failure rate by stage and by failure class, flake rate, and cache hit rate. **You cannot fix a pipeline you haven't measured**, and the answer usually surprises people: the bottleneck is rarely the tests.

**Typical findings and fixes:**

| Symptom | Root cause | Fix |
|---|---|---|
| Dependency install is 8 min every run | No cache / cache invalidated by `COPY . .` | Cache the package manager dir keyed on the **lockfile hash**; BuildKit `--mount=type=cache`; `--cache-from type=registry/gha` for image layers |
| Build is slow | Single-arch native build on emulated QEMU for the other arch | Native cross-builders (one runner per arch) or build only the needed arch in PRs, multi-arch on merge |
| Tests run serially | No sharding | Shard by historical duration (`pytest-split`, `--shard=i/n`, JUnit timing-aware splitting); parallel jobs; `fail-fast` off so you see all failures at once |
| Every stage runs on every commit | No path filters | `paths:`/`changes:` filters, affected-project detection (Nx/Turbo/Bazel/Pants), skip docs-only changes |
| 20% failures, mostly "pass on retry" | **Flaky tests + shared state + timing** | Identify by failure history; quarantine and alert; fix the top 10 (usually: shared DB fixtures, port collisions, `sleep`-based waits, tests depending on execution order, network calls without mocking). Replace sleeps with polling/conditions. **Give each test isolated resources** |
| Random infra failures | Runner instability, network egress limits, registry rate limits | Ephemeral runners (ARC), a registry mirror/proxy, retry only *infra* steps (not tests), longer timeouts on known-slow steps |
| Queueing before execution | Runner capacity | Autoscale runners; separate pools for fast/slow jobs; prioritise main-branch builds over PRs |
| Deploy stage waits on a human nobody watches | Approval fatigue | Automate where safe (canary + analysis), make approvals *informed* (a link to the diff, the test results, the risk summary), and put approvals in the team's chat with escalation |
| Environment prep dominates | Provisioning per deploy | Pre-provisioned long-lived environments + reset scripts, or ephemeral envs from a warm pool |

**The reliability half** (20% failure is a trust problem, and distrust → bypassing → worse):
1. **Classify every failure** for two weeks: real bug / flaky test / infra / config / dependency. You'll usually find 60–70% is flaky+infra, not code.
2. **Fix the top 5 causes** rather than 50 symptoms.
3. **Make the pipeline deterministic**: pinned tool versions, locked deps, no `latest`, no reliance on wall-clock time or the public internet, isolated test resources.
4. **Add a fast pre-flight** (lint + unit + static) so most failures surface in < 3 minutes, before the expensive stages.
5. **Cache everything cacheable**, and verify cache hit rates — a silently-missing cache is a 10× slowdown nobody notices.
6. **Set an SLO for the pipeline itself** (e.g. p90 < 12 min, non-flake failure rate < 3%), track it on a dashboard, and treat breaches as bugs. **Say this: the pipeline is a product with users and an SLO.**
7. **Reduce batch size**: if the pipeline is slow, developers batch changes, which increases risk and makes bisecting failures hard. Speed and safety reinforce each other.

**Targets worth quoting:** elite performers deploy on demand, multiple times per day, with lead time < 1 hour and change failure rate < 15% (DORA). Getting from 45 min/20% to 12 min/3% is typically achievable in a quarter with caching + flake elimination + parallelisation, and it's one of the highest-ROI things a platform team can do.

### 12. "A bad config change took down production. Design a system so this can't happen again."
**Post-mortem first (blameless), then systemic fixes across five layers:**

**Layer 1 — Validation (catch it before merge)**
- **Schema validation**: JSON Schema / OpenAPI / CEL (`x-kubernetes-validations`) on CRDs; `kubeconform` against the target cluster's API versions; `helm lint` + `helm template --validate`.
- **Policy as code**: `conftest`/OPA or Kyverno policies on the *manifests* in CI: no `latest` tag, resource requests required, no privileged, replica count ≥ 2, memory limit ≤ X, image from an approved registry, **and domain-specific rules** ("the `replicas` field in prod may not decrease by more than 50%", "this ConfigMap key must be a valid URL"). **Domain-specific policies are what actually prevents the incident that happened** — generic ones prevent the generic ones.
- **Render and diff**: `helm template` / `kustomize build` the *final* manifests and diff against what's live (`kubectl diff`, Argo CD's diff view) in the PR. Reviewers must see the **effective** change, not the template change. A one-line values edit can alter 40 resources.
- **Dry-run against the real cluster**: `kubectl apply --dry-run=server` runs full admission — catches what static validation can't.

**Layer 2 — Review (catch it before merge, human layer)**
- **CODEOWNERS on the config/deploy repo** — production manifests require review by the owning team; two-person rule for `prod/`.
- **Small, focused PRs.** A 900-line manifest change cannot be reviewed meaningfully — enforce a size norm and split.
- **The PR template must answer**: what changes at runtime, what's the blast radius, how do we verify, how do we roll back. If the author can't answer, the reviewer can't either.
- **Reviewers see the rendered diff and the risk summary**, not just YAML.

**Layer 3 — Progressive rollout (limit the blast radius)**
- **Never deploy config globally at once.** Canary the change to 5%, analyse metrics automatically (Argo Rollouts + Prometheus AnalysisTemplate), then promote. **Config changes deserve the same progressive treatment as code changes — and usually don't get it. That's the gap.**
- **Sync waves** so dependencies land before dependents; **hooks** for pre-flight checks.
- **Feature flags for behaviour changes**, so the config change is inert until enabled, and can be disabled in seconds without a redeploy.
- **Rollout windows**: no prod changes Friday afternoon or during peak, enforced by pipeline policy (and overridden only with an explicit, logged exception).

**Layer 4 — Detection (find it in seconds, not hours)**
- **Deploy annotations on dashboards** (Grafana annotations from the pipeline) so a spike correlates with a change instantly. **Most "mystery" incidents are solved in seconds by this.**
- **SLO-based alerting on the golden signals** immediately post-deploy, with a tighter threshold during the rollout window.
- **Automated rollback on SLO breach** — Argo Rollouts abort, or a controller that reverts the Git commit. This is the single biggest MTTR improvement available.
- **Config drift detection** — Argo CD OutOfSync alerts, so an unreviewed `kubectl edit` is visible.
- **Change feed**: every production change (deploy, config, feature flag, infra, DNS, cloud console) into one timeline. During an incident, "what changed?" is the first question, and if the answer takes 30 minutes to assemble, that's the real failure.

**Layer 5 — Recovery (make rollback boring)**
- **`git revert` is the rollback**, and it must be **tested**. Rehearse it. If rollback requires a human to remember three commands under pressure, it will fail.
- **Backwards-compatible changes only** (expand-contract for schemas; additive config; keep the old code path working for at least one release) so rollback is *safe*, not just possible.
- **Break-glass procedure**, documented and drilled, with automatic reconciliation back to Git afterwards.
- **Immutable artifacts**: rollback means pointing at the previous digest, not rebuilding (rebuilding may not reproduce).

**The systemic point to close with:** "The incident wasn't a typo — a typo is a constant. The incident was that a typo could reach 100% of production traffic without validation, review of the rendered result, progressive rollout, or automated rollback. I'd fix all five layers, and I'd measure it: change failure rate and time-to-restore. And I'd write the policy that would have caught *this specific* mistake as a CI rule the same week — that's how a post-mortem becomes durable."

### 13. "Design a CI/CD platform for 60 teams and 300 services."
This is a platform-engineering design question (see also [`15-Platform-Engineering`](../15-Platform-Engineering/README.md) and the CI/CD platform design in [`03-System-Design-HLD`](../03-System-Design-HLD/README.md)).

**Requirements to elicit first:**
- Team autonomy vs central standardisation — where's the line? (My answer: **paved road, not gated road** — make the right way the easy way, allow escape hatches with justification.)
- Compliance regime (SOX/PCI/HIPAA/ISO 27001) → separation of duties, audit evidence, change approval records.
- Environments per team (shared staging? per-PR ephemeral?), multi-cluster/multi-region/multi-cloud?
- Languages/stacks in play (polyglot → buildpacks or per-language templates).
- Self-service level: do teams write pipelines, or consume a templated one?

**Architecture:**
```
Developer ──► Git (mono or poly repo)
                 │  PR triggers
                 ▼
        CI Platform (GitHub Actions/GitLab/Tekton)
        ├─ Reusable workflows / pipeline templates (versioned, centrally maintained)
        ├─ Ephemeral, autoscaled runners (ARC), network-restricted
        ├─ OIDC → short-lived cloud creds (no stored keys)
        ├─ Build: BuildKit + registry cache; multi-arch
        ├─ Test: sharded, cached, path-filtered
        ├─ Scan: SAST/SCA/secrets/image/IaC + policy gate
        └─ Publish: image by digest + SBOM + cosign signature + provenance
                 │
                 ▼  (writes the digest into the config repo — the only mutation)
        GitOps Config Repo (per-env directories, CODEOWNERS, policy-checked)
                 │
                 ▼
        Argo CD (sharded: one instance per cluster/tenant, ApplicationSets)
        ├─ AppProject per team (allowed repos, destinations, resources, roles)
        ├─ Sync waves + PreSync migration hooks
        ├─ Argo Rollouts: canary + automated analysis + auto-rollback
        └─ Notifications → team channels
                 │
                 ▼
        Kubernetes clusters (per env/region/tenant)
        └─ Admission: Kyverno/VAP verifying signature, SBOM presence, policy
                 │
                 ▼
        Observability: Grafana deploy annotations, SLO dashboards,
                       pipeline metrics, DORA dashboard per team
```

**The decisions that make it work at 60 teams:**
1. **Golden paths / paved road.** A versioned, centrally maintained pipeline template (reusable workflow, GitLab `include:`, or Tekton `Pipeline` + `PipelineRun` templates) that does build/test/scan/sign/publish/promote. Teams override with parameters, not by forking. **Forked templates are how you end up with 300 unmaintainable pipelines.** Provide an escape hatch: teams may opt out, but they inherit the compliance burden and it's visible on a dashboard.
2. **Self-service scaffolding**: a service template (repo + CI + IaC + manifests + dashboards + alerts + on-call + docs) generated by a tool (`cookiecutter`, Backstage software templates, `copier`). **A new service should be production-ready in 30 minutes** — that's the adoption driver.
3. **Argo CD sharding.** One Argo CD instance per cluster or per tenant group; ApplicationSets to fan out; AppProjects for tenancy. A single instance managing 300 apps × 5 envs will melt the repo-server and the cluster's apiserver.
4. **Multi-cluster fleet management**: a cluster registry (declarative list of clusters + their purpose + region), GitOps-installed platform components per cluster (Argo CD, cert-manager, ingress, monitoring, policies) via an **Argo CD "app of apps"** or Flux bootstrap, and **drift detection on the platform itself**.
5. **Policy at admission, not just in CI.** CI can be bypassed; the cluster can't. Kyverno/VAP verify image signature, approved registry, required labels/annotations, resource requests, securityContext, and no `latest`. **Defence in depth: CI is the fast feedback, admission is the enforcement.**
6. **Secrets**: no secrets in Git. External Secrets Operator / Vault with workload identity; per-team scoped paths; rotation; audit.
7. **Environments**: long-lived dev/staging/prod per team (namespaces) + **ephemeral preview environments per PR** with automatic teardown and a cost cap. Enforce parity between staging and prod.
8. **Progressive delivery by default**: canary + automated analysis + auto-rollback in the template, so teams get it without thinking.
9. **Observability as part of the pipeline**: the template creates the dashboard, the SLO, the alerts, and the deploy annotation wiring. **A service without alerts shouldn't be deployable** — make it a policy.
10. **Metrics for the platform itself**: DORA per team, pipeline duration p50/p95, failure classification, cache hit rate, deploy frequency, change failure rate, time-to-rollback, template adoption, self-service success rate, and **developer satisfaction (survey)**. Platform teams that don't measure adoption build things nobody uses.
11. **Cost & capacity**: runner autoscaling with sensible limits, spot/preemptible runners with retry handling, registry GC, artifact retention policies, preview-env TTLs, and per-team usage reporting.
12. **Governance without bottleneck**: the platform team owns the templates and policies; **feature requests come as PRs**; SLA for platform issues; an internal user group; and a documented deprecation policy for template changes (breaking template changes affect 300 services — version them, and roll out progressively like any other change).

**Anti-patterns to call out:** a central team that must approve every deploy (bottleneck, and it doesn't scale past ~10 teams); forcing one language/stack; a UI-heavy internal tool nobody asked for; "we'll build our own CI" (you won't beat GitHub Actions/GitLab on features — compete on *integration and golden paths*); and treating the platform as a project with an end date rather than a product with users.

### 14. "You must ship an emergency hotfix at 2am during an active incident. Walk me through it."
**This tests whether you understand that process must bend, not break.**

1. **Confirm the fix is the right action.** Is rollback possible and faster? **`git revert` of the offending change or `argocd app set --rollback` / `kubectl rollout undo` is usually faster and safer than a new fix.** Also consider a **feature-flag disable** (seconds, no deploy) or scaling/traffic-shifting as a mitigation while the real fix is built. **Say this first: the fastest safe action is usually to undo, not to fix forward.**
2. **If fixing forward:** make the smallest possible change. No refactoring, no drive-by improvements. One commit, one purpose.
3. **Use the expedited path, don't skip the path.** A documented break-glass procedure that:
   - Still runs the **fast validation stages** (lint, unit, static policy, manifest render/diff) — these take < 3 minutes and have caught more 2am mistakes than they've delayed.
   - Allows **skipping slow, non-blocking stages** (full E2E, performance, optional scans) with an explicit, logged override.
   - Requires **one approver** (not two), and the approver must be a human who reads the diff — not a rubber stamp.
   - Records the override reason in the PR/commit message for the post-incident review.
4. **Ship progressively even at 2am.** Canary to one pod / 5% / one zone first, watch the golden signals for 60–120 seconds, then promote. **This costs two minutes and prevents turning one outage into two.** If the service is already fully down, a full rollout is defensible — say that explicitly, because the right answer depends on the blast radius already realised.
5. **Verify the fix with evidence**, not hope: the specific error metric dropped, the specific symptom is gone, a smoke test passes. Define the verification *before* deploying.
6. **Reconcile Git.** If you used `kubectl edit`, `argocd app` overrides, or a manual scale, **write it back to Git immediately** (or as the first task in the morning) — otherwise drift means the next sync reverts your fix, possibly during the incident. **This is the most commonly forgotten step and it causes second incidents.**
7. **Communicate**: status page update, incident channel, and a note of what changed and when (for the timeline).
8. **Afterwards (non-negotiable):** a blameless post-incident review that asks **why the emergency path was needed** — was the change not testable? Was the rollback path broken? Was the gate too slow? Was there no flag? Then fix the system, and specifically: add the CI policy that would have caught the original bug, verify the rollback path works, and reduce the need for 2am deploys (progressive delivery, automated rollback, flags, better staging parity).

**The line that lands:** "I want the 2am path to be *faster*, not *lawless*. If your only options are 'follow the full 45-minute process' or 'bypass everything and hope', the process is the problem. A good platform has an expedited lane that keeps the 3-minute checks and the canary, drops the 40-minute ones, requires one human, and logs the exception — so the incident review can see exactly what was skipped and why."

---

## Red flags

| Saying / doing this | Costs you |
|---|---|
| CI holds a cluster-admin kubeconfig | The core security argument for GitOps, missed |
| `permissions: write-all` on GITHUB_TOKEN | Supply-chain compromise waiting to happen |
| Long-lived AWS keys in CI secrets | Use OIDC federation |
| `uses: actions/checkout@v4` (mutable tag) | Pin by SHA |
| Building a separate artifact per environment | You tested something you didn't ship |
| `image: latest` in prod manifests | Untraceable, silently mutable |
| Canary with a human watching a dashboard | No faster than a rolling update |
| `selfHeal: true` + `prune: true` on everything without thought | A bad merge can delete production |
| "Everything is GitOps" while migrations run manually | Undocumented shadow process |
| No drift detection | `kubectl edit` in prod, discovered next incident |
| Retrying flaky tests until green | Hidden failures, eroded trust |
| No pipeline duration/flake metrics | You're guessing |
| Approving your own emergency deploy with no record | Fails every audit and every post-mortem |
| Not writing manual changes back to Git | Next sync reverts your hotfix |

## Rapid recall

1. CI = integrate+test; CDelivery = deployable, human gate; CDeployment = automatic to prod.
2. Pipeline: cheap-first, parallel, hermetic, fail-fast; **one artifact promoted by digest**; config varies, artifact doesn't.
3. Strategies: rolling (default), blue/green (instant rollback, 2× cost), canary (**with automated analysis + auto-rollback**), shadow, **feature flags decouple deploy from release**.
4. GitOps = declarative + versioned + pulled automatically + continuously reconciled. Pull beats push because **credentials stay inside the cluster**.
5. Argo CD: UI, ApplicationSets, AppProjects, sync waves, hooks (`PreSync` = migrations), self-heal/prune, impersonation, source integrity, internal mTLS (3.5).
6. Flux: composable controllers, built-in image automation, no UI.
7. Pipeline security: least-privilege token, **OIDC not keys**, no secrets to forks, pin by SHA/digest, sign + SBOM + provenance, ephemeral isolated runners, verify at admission.
8. Test the infra too: kubeconform, conftest/Kyverno, checkov, tflint, hadolint, promtool, oasdiff, pluto/kubent for API deprecations.
9. Trunk-based + CalVer for services; SemVer for anything consumed by others.
10. Slow pipeline → cache (lockfile-keyed), shard, parallelise, path-filter, native cross-builders. 20% failure → classify, fix flake causes, isolate test resources, set a pipeline SLO.
11. Prevent bad config changes in 5 layers: validate (schema+policy+rendered diff+server dry-run) → review (CODEOWNERS, small PRs) → progressive rollout (canary config too) → detect (annotations, SLO alerts, auto-rollback) → recover (tested `git revert`, backwards-compatible changes).
12. Emergency path: prefer revert/flag-off; expedite don't bypass; keep fast checks; one approver; canary anyway; **reconcile Git afterwards**; post-mortem the process.

→ Next: [`09-IaC-Terraform`](../09-IaC-Terraform/README.md)
