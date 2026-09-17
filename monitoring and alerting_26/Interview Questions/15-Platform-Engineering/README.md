# 15 · Platform Engineering

The fastest-growing role family in this space, and the one where **product thinking matters as much as technical depth**. Expect questions on internal developer platforms (IDPs), golden paths, self-service, Backstage, developer experience, and organisational design.

---

## 🟢 Basic

### 1. What is platform engineering, and how is it different from DevOps / SRE / Ops?
**Definition (Team Topologies / CNCF framing):** a discipline where a dedicated team builds and operates a **self-service internal platform** — a curated set of capabilities, tools and paved roads — that lets product teams deliver software faster with less cognitive load, while the platform team owns the underlying complexity.

| | **Ops** | **DevOps** | **SRE** | **Platform Engineering** |
|---|---|---|---|---|
| Primary output | Running systems | A culture + practices for dev/ops collaboration | Reliability of specific services | **A product used by internal developers** |
| Who they serve | The business | Everyone | Users of the service + the dev team | **Other engineering teams (internal customers)** |
| Unit of work | Tickets, incidents | Pipelines, shared ownership | SLOs, error budgets, toil reduction | **Capabilities, golden paths, APIs, self-service** |
| Success metric | Uptime | Delivery throughput | SLO attainment, MTTR | **Adoption, developer productivity, time-to-first-deploy, toil avoided** |
| Failure mode | Bottleneck, ticket queue | "Everyone is responsible" = nobody is | Reliability theatre without velocity | **Building a platform nobody uses** |

**The distinction that scores:** "DevOps is a *culture and a set of practices*; platform engineering is an *organisational and product response* to DevOps failing at scale. When you tell 60 teams 'you build it, you run it', most of them don't have the skills, time or inclination to run Kubernetes, Terraform, observability and security well — so they do it badly, inconsistently, and slowly. A platform team takes that undifferentiated heavy lifting, does it once, does it well, and exposes it as a self-service product. **DevOps is the goal; platform engineering is one of the ways to achieve it at scale.**"

**Also worth naming:** platform engineering is **not** a rebranded ops team. The difference is the operating model: **a platform team has users, a roadmap, a product owner, adoption metrics and a support model** — an ops team has tickets. If your "platform team" is measured on tickets closed, it's an ops team.

### 2. Team Topologies — the vocabulary interviewers expect
Four team types:
| Type | Purpose | Example |
|---|---|---|
| **Stream-aligned** | Delivers value to a single stream (a product/feature); owns it end-to-end | Checkout team, Search team |
| **Platform** | Provides self-service capabilities that reduce stream-aligned teams' cognitive load | The IDP, CI/CD, Kubernetes, observability |
| **Enabling** | Helps stream-aligned teams acquire missing capability; **teaches, doesn't own** | A security guild, a performance specialist, an SRE embed |
| **Complicated-subsystem** | Owns a genuinely hard component needing deep specialism | A video-transcoding engine, a payments ledger, an ML inference stack |

Three interaction modes:
- **Collaboration** — two teams working closely on something new/uncertain (temporary, deliberately).
- **X-as-a-Service** — a clean, self-service consumption model (the platform team's steady state).
- **Facilitating** — the enabling team teaching/coaching (one-way knowledge transfer).

**Key concepts:**
- **Cognitive load** — the total mental effort a team carries. There are three kinds: *intrinsic* (the domain — unavoidable and the reason the team exists), *extraneous* (the environment — tooling, deploy complexity, infra; **this is what a platform removes**), *germane* (learning/growth). **A platform's job is to minimise extraneous load so teams can spend their capacity on intrinsic load.**
- **Team API** — the interface a team presents to others: docs, code, contracts, support channels, SLAs, onboarding. **A platform team with a poor Team API has a bad platform, regardless of the technology.**
- **Thinnest viable platform (TVP)** — "**a platform should be as small as possible while still reducing cognitive load**." A great platform might be: a well-documented Helm chart library, a Terraform module registry, a CI template, a runbook, and a Slack channel. **Over-building is the #1 platform failure.** The litmus test: "if the platform team disappeared for a month, would the product teams notice a *reduction in capability* or just a *reduction in meetings*?"
- **The platform trap / "platform as a product"** — a platform team that builds for itself, adds features nobody asked for, requires teams to migrate without helping, and measures its success by lines of code or components shipped. The antidote: user research, adoption metrics, a roadmap driven by internal customer requests, and a support SLO.

### 3. Golden paths (paved roads) — the central design pattern
**A golden path is a supported, opinionated, end-to-end way to accomplish a common task — the fastest route to production that is also the compliant, secure, observable route.**

**The rules that make it work:**
1. **It must be the easiest path, not just the approved path.** If the golden path is slower or more restrictive than doing it yourself, teams will route around it, and you'll have shadow IT plus no governance. **Adoption is earned by being faster.**
2. **It's opt-in, with an escape hatch.** Teams can go off-path, but they inherit the burden (security review, on-call, compliance evidence) and it's visible. **No escape hatch → resentment and shadow IT; no friction → chaos.**
3. **It's complete end to end.** "Create a service" should produce: a repo with CI, a Dockerfile, IaC for the cloud resources, Kubernetes manifests, service discovery, TLS, observability (dashboards, SLOs, alerts), a runbook, on-call registration, docs, and a cost tag. **A half path is worse than no path** — teams finish the second half differently every time, and you get 60 variants.
4. **It encodes policy as defaults, not as documentation.** Encryption on, least-privilege IAM, non-root containers, resource requests set, backups enabled, retention configured. **The secure/compliant configuration should be what you get by doing nothing.**
5. **It's versioned and upgradeable.** Breaking changes to a golden path affect every team, so: semver, a changelog, automated upgrade PRs (Renovate-style), a deprecation policy, and progressive rollout. **Treat the path like a library with 60 dependents.**
6. **It's measurable.** Adoption %, deviation %, time-to-first-deploy, support ticket volume per path, and NPS/developer satisfaction.

**Example golden paths a mature platform offers:**
- "Create a new web service" / "Create a new batch job" / "Create a new data pipeline" / "Create a new ML inference endpoint"
- "Add a database" / "Add an object store bucket" / "Add a queue"
- "Expose a service publicly" / "Add a third-party integration"
- "Deploy a change" / "Roll back" / "Run a one-off job" / "Debug a production pod"
- "Add an alert" / "Create a dashboard" / "Declare an SLO"
- "Provision a new environment" / "Onboard a new team"

### 4. Internal Developer Platform (IDP) — what it actually contains
An IDP is the **integration of the platform's capabilities into a coherent, discoverable, self-service experience**. It is *not* a product you buy, and it is *not* just Kubernetes.

**The capability layers:**
| Layer | Capabilities | Typical tooling |
|---|---|---|
| **Service catalogue & discovery** | "What services exist, who owns them, what do they depend on, where's the runbook, what's the on-call?" | **Backstage** (Spotify), Port, Cortex, OpsLevel, Roadie |
| **Scaffolding & templating** | Create a compliant new service/repo/pipeline in minutes | Backstage **software templates**, cookiecutter/copier, `gh repo create` + templates |
| **CI/CD & GitOps** | Build/test/scan/sign/publish + progressive delivery | GitHub Actions/GitLab/Tekton + Argo CD/Flux + Argo Rollouts/Flagger |
| **Infrastructure self-service** | Provision cloud resources and environments within guardrails | Terraform/OpenTofu modules, **Crossplane**, Atlantis, env0/Spacelift, Backstage + IaC |
| **Runtime platform** | Where workloads run, abstracted | Kubernetes (EKS/GKE/AKS), ECS, Cloud Run; Helm/Kustomize; operators |
| **Observability as a service** | Auto-provisioned dashboards, SLOs, alerts, logging, tracing, profiling | Prometheus/Grafana/Loki/Tempo stack, OTel, Grafana Cloud/Datadog |
| **Security & compliance by default** | Hardened base images, admission policies, secret management, scanning, audit | Distroless/Wolfi, Kyverno/OPA/VAP, Vault/ESO, Trivy, Falco |
| **Secrets & identity** | No static credentials; workload identity; secret injection | Vault, External Secrets Operator, SPIFFE/SPIRE, cloud workload identity |
| **Environments** | Ephemeral preview envs per PR, long-lived dev/staging/prod, data seeding | Argo CD ApplicationSets (PR generator), Okteto, Garden, vCluster |
| **Cost & capacity** | Per-team showback, budgets, right-sizing recommendations, quotas | Infracost, OpenCost/kubecost, cloud cost tools |
| **Support & docs** | Searchable, in-context, with a support SLO and a real channel | Backstage TechDocs, internal docs, a staffed channel |

**Backstage specifically (expect this question):**
- An **open-source developer portal** (CNCF incubating/graduated-track, created by Spotify) built on a **software catalogue** of entities (`Component`, `API`, `System`, `Domain`, `Resource`, `Group`, `User`) described in **`catalog-info.yaml`** files that live *with the code*.
- **Plugins** (React front-end + optional back-end) extend it: Kubernetes, GitHub/GitLab, Jenkins, Argo CD, Terraform, Grafana, PagerDuty, SonarQube, Vault, TechDocs, Scaffolder, Search, Cost Insights, plus hundreds of community plugins.
- **Software Templates** = the scaffolding engine (parameterised, multi-step: create repo, apply skeleton, register in the catalogue, create CI, create infra).
- **TechDocs** = docs-as-code rendered in the portal (MkDocs, stored with the repo).
- **The honest assessment:** "Backstage's value is the **catalogue and the ownership model** — knowing what exists, who owns it, and how things relate is the prerequisite for every other capability, and it's genuinely hard to build yourself. Its cost is that it's a **React/TypeScript application you must operate, upgrade, secure and plugin-maintain**, with a real learning curve and a plugin ecosystem of uneven quality. **A Backstage instance nobody maintains is worse than a spreadsheet**, because it silently rots and erodes trust. My rule: start with the catalogue + TechDocs + one or two high-value plugins (Kubernetes, CI) and add templates once you have a stable golden path to encode. Don't deploy 40 plugins on day one."
- **Alternatives**: commercial portals (Port, Cortex, OpsLevel, Roadie, Humanitec) when you don't want to run it; or **just a well-structured Git repo + CLI + docs** for small orgs — which is a legitimate TVP.

### 5. Developer experience (DevEx) — the three core dimensions
From the widely-cited DevEx research (Abi Noda et al.):
1. **Flow state** — uninterrupted, appropriately-challenged work with fast feedback. Broken by: slow builds/pipelines, context switching, waiting for approvals, noisy environments, unclear requirements.
2. **Feedback loops** — the speed and quality of response to your actions. Broken by: 45-minute CI, "it works locally", unclear error messages, delayed test results, no local environment.
3. **Cognitive load** — the mental effort required to do the work. Broken by: undocumented systems, excessive tooling sprawl, tribal knowledge, complex setup, having to know 12 systems to ship one change.

**How a platform team measures and improves DevEx:**
- **Quantitative**: DORA four keys (lead time for changes, deploy frequency, change failure rate, failed-deployment recovery time), **SPACE** framework dimensions (Satisfaction, Performance, Activity, Communication/collaboration, Efficiency/flow), pipeline duration p50/p95, time-to-first-commit for a new hire, build/test times, flake rate, support-ticket volume, self-service success rate, adoption of golden paths.
- **Qualitative**: **quarterly developer surveys** (the DX Core 4 / DevEx survey), interviews, "day in the life" shadowing, and reading the internal chat channels for recurring complaints. **Surveys catch what metrics can't — resentment, distrust, and workarounds.**
- **The trap to name:** "Activity metrics (commits, PRs, tickets, deploys) measure motion, not value, and they incentivise gaming. I'd use **outcome** metrics (lead time, change failure rate, time-to-recover, self-service success) plus **developer-reported** satisfaction, and I'd never rank individuals or teams by them — the moment a DevEx metric becomes a performance-review input, it stops being honest."

---

## 🔵 Advanced

### 6. Build vs buy vs assemble — the platform sourcing decision
| Option | When it's right | Risk |
|---|---|---|
| **Buy (SaaS)**: GitHub/GitLab, Datadog, CircleCI, Humanitec, Port, Spacelift | Small/medium org, no platform headcount, commodity capability, speed matters more than control | Cost growth, lock-in, less customisation, data/egress concerns |
| **Assemble (OSS + glue)**: Kubernetes + Argo + Prometheus + Backstage + Terraform | Most mid-to-large orgs; the capability is commodity but the *integration* is your differentiator | **You operate it**; upgrade burden; integration work is real engineering |
| **Build bespoke** | The capability *is* your competitive advantage, or you have a genuinely unique constraint (scale, regulation, hardware) | Enormous cost, a second product to maintain forever, opportunity cost |

**My decision framework (state it as a framework):**
1. **Is this a differentiator?** If not, don't build it. Nobody's competitive advantage is their CI system or their Kubernetes.
2. **What's the total cost of ownership, including upgrades, security patching, on-call and the plugin/integration tax?** OSS is free to download and expensive to operate. **Add 1–2 engineers of ongoing cost for any self-hosted critical system**, and be honest about it.
3. **Can we operate it well?** A tool your team can't run reliably at 3am is worse than a worse tool they can.
4. **How reversible is the decision?** Prefer reversible ones; for irreversible ones (data formats, identity model, artifact registry), invest more in standards and exit plans.
5. **What's the escape velocity?** If the vendor triples the price, can you leave in a quarter? **Open formats (OCI images, OTel, Terraform/HCL, GitOps manifests, Prometheus metrics) are how you keep options open** — that's the real argument for standards-based assembly over proprietary platforms.

**The line that scores:** "I assemble from open-source components with open data formats, buy the commodity SaaS where operating it isn't worth the headcount, and build only the thin integration layer that encodes *our* golden paths and policies. **The integration layer is the platform; the components are plumbing.** Teams that build their own Kubernetes or their own CI end up maintaining a second company's product."

### 7. Self-service infrastructure — the design that actually works
**The failure modes to avoid:**
- **The ticket portal** — a UI that creates a Jira ticket. Not self-service; it's a queue with a form.
- **The unguarded console** — full cloud console access for everyone. Fast, but no governance, no cost control, no consistency, and drift everywhere.
- **The over-engineered platform** — 18 months of building, no users, and a backlog of teams doing it themselves.
- **The "you must migrate" mandate** — a platform imposed without a benefit, generating resentment and a shadow platform.

**The design that works:**
1. **Curated modules/claims, not raw resources.** Teams request "a Postgres database" (with size, environment and backup parameters) — not "an `aws_db_instance` with 47 arguments". The module encodes encryption, HA, backups, monitoring, IAM, networking, tagging and cost limits. **The abstraction is the guardrail.**
2. **Guardrails at three layers**: (a) module defaults (can't be wrong), (b) **CI policy on the plan** (tflint/checkov/OPA/Infracost with a cost threshold), (c) **cloud-level SCPs/Org Policy/Azure Policy** (hold even if CI is bypassed). **Layer (c) is the one that actually holds.**
3. **Auto-approval for the boring majority.** Within policy, under a cost threshold, non-destructive, non-prod → merge and apply automatically. Prod, destructive, new resource types, or over-threshold → human review. **Automating the 90% is what makes the 10% reviewable.**
4. **Everything through Git.** The request is a PR against a repo (or a portal action that produces a PR) → CI validates and plans → apply from a controlled runner with OIDC-federated credentials → GitOps reconciles. **This gives you review, audit, rollback and drift detection for free.**
5. **Feedback is immediate and legible.** The plan (not just "success"), the cost delta, the resources created, the access instructions, and the dashboards/alerts that were provisioned. **A self-service action that doesn't tell you how to use the result isn't finished.**
6. **Idempotent, resumable, and reversible.** Provisioning fails sometimes; retries must be safe, and teardown must be a supported first-class action (with data-protection guardrails).
7. **Quotas and budgets per team** so self-service doesn't become unbounded spend: ResourceQuotas in Kubernetes, cloud quotas, cost budgets with alerts, and automatic teardown of expired non-prod resources.
8. **A documented support model**: a channel, an SLA, an escalation path, office hours, and a "how do I do X" index. **Self-service without support generates tickets anyway.**
9. **Measure it**: time-to-provision, self-service success rate (actions completed without human help), % of resources created via the platform vs the console, escape-hatch usage, cost per team, and support volume.

**Crossplane deserves a specific mention** for platform roles: it exposes cloud infrastructure as **Kubernetes CRDs** with **Compositions** (platform-team-authored bundles) and **Claims** (team-facing simplified requests), reconciled by controllers, with state stored in the cluster. **Advantages:** one control plane (Kubernetes) for app + infra, GitOps-native, RBAC/policy reuse, and a genuinely nice XRD/Claim abstraction for self-service. **Trade-offs:** infra lifecycle coupled to cluster lifecycle, reconciliation-based (slower, eventually-consistent, harder to reason about than a plan/apply), less mature provider ecosystem than Terraform, and debugging is controller-debugging. **The balanced view:** "Terraform for the foundation and things that change rarely; Crossplane for the self-service claims layer and app-adjacent infra — or Terraform with an Atlantis/internal-portal front end. Both are legitimate; the deciding factor is whether your platform's centre of gravity is already Kubernetes."

### 8. Environments, preview environments, and data
**Environment strategy:**
| Environment | Purpose | Fidelity | Lifetime |
|---|---|---|---|
| **Local** | Fast iteration, offline-capable | Low (compose/kind/testcontainers) | Per developer |
| **Ephemeral preview** | Validate a specific PR/change end-to-end | Medium-high (real dependencies, synthetic data) | Hours–days, auto-torn-down |
| **Dev / integration** | Continuous integration across services | Medium | Long-lived |
| **Staging / pre-prod** | Production-like validation, load tests, DR drills | **High — same topology, fractional scale, anonymised prod-shaped data** | Long-lived |
| **Prod** | Reality | — | — |

**Preview environments — the high-value, high-cost capability:**
- **Value:** catch integration and config bugs before merge; let product/design/QA see the change; enable parallel development; dramatically reduce "works in staging" surprises.
- **Implementation:** Argo CD **ApplicationSet with a pull-request generator**, or Flux + a controller, or a commercial tool (Okteto, Garden, Northflank, Uber/Netflix internal). Each PR gets a namespace (or a vCluster) with the app + dependencies, a unique ingress hostname, TLS via cert-manager + DNS wildcard, seeded data, and automatic teardown on merge/close with a TTL cap.
- **The hard parts:** **cost** (hundreds of concurrent environments — needs aggressive TTLs, scale-to-zero, shared dependencies, and a cap), **data** (a shared or seeded dataset; prod data is usually prohibited), **shared dependencies** (do you spin up a Postgres per preview, or share one with per-PR schemas? Sharing is cheaper and less realistic), **secrets** (scoped, non-prod credentials only), and **DNS/TLS** (wildcard DNS + a wildcard cert is the pragmatic answer).
- **The pragmatic tiering:** full per-PR environments for the 5 services that change most and break most; shared, resettable environments for everything else. **Don't build a per-PR environment for every service — the cost curve is brutal and the value is uneven.**

**Test data — the unsolved problem everyone has:**
- **Options:** synthetic/generated (safe, cheap, unrealistic distributions), **anonymised/pseudonymised prod copies** (realistic, expensive, and a compliance minefield — anonymisation is hard and often reversible), **subset sampling** (a representative slice, referentially intact — hard to compute), production traffic **replay/mirroring** (excellent for validation, needs write isolation), or **shared mutable staging data** (cheap, and the reason staging tests are unreliable).
- **The realistic answer:** "Generated data for unit/integration; a referentially-intact prod subset, refreshed on a schedule and pseudonymised, for staging; traffic mirroring for pre-release validation of read paths; and strict write-isolation so a test can never mutate real data. **And I'd accept that no test data strategy fully reproduces production — which is why progressive delivery with production traffic and automated rollback matters more than a perfect staging environment.**"

### 9. Platform as a product — operating model, roadmap, and metrics
**The operating model:**
- **Roles:** a **product owner/manager for the platform** (owns the roadmap, does user research, says no), platform engineers (build), an **SRE/on-call for the platform itself** (it's a production system with users — it needs SLOs and paging), and **security/enablement embeds**.
- **Funding:** a stable, headcount-based budget — **not** chargeback-driven project funding. A platform team that must justify itself per-project builds projects, not platforms. (Showback for visibility, yes; chargeback for funding, usually harmful at this stage.)
- **Intake:** feature requests as issues/PRs from teams, triaged by frequency × impact × strategic fit; **a public roadmap**; and a documented "we won't do this" list with reasons.
- **Support:** tiered — docs → community channel → on-call escalation, with an SLO for response and a metric for ticket volume (which should *fall* as the platform matures; rising tickets means the platform isn't self-service).
- **Contribution model:** teams can contribute (a golden-path PR, a module, a plugin). **Accepting contributions is how you scale beyond the platform team's headcount** — and rejecting them all is how you become a bottleneck.

**Metrics that matter (and the ones that mislead):**
| Good | Misleading |
|---|---|
| **Adoption**: % of services on the golden path; % of infra provisioned via self-service | Lines of code / components shipped |
| **Time-to-first-deploy** for a new service; **time-to-provision** a resource | Number of features released |
| **Lead time for changes** (DORA), **deploy frequency**, **change failure rate**, **time to restore** | Uptime of the platform alone (necessary, not sufficient) |
| **Self-service success rate** (actions completed without human help) | Ticket *volume* (unless falling) |
| **Support load per platform engineer** | "Developer happiness" as a single unmeasured vibe |
| **Escape-hatch/deviation rate** (and whether it's rising) | Number of teams "onboarded" |
| **Cost per team/service** and cost-efficiency trends | |
| **Developer survey** (satisfaction, cognitive load, flow) quarterly | |
| **Reliability of the platform itself**: SLO attainment, incident count, MTTR | |

**The framing:** "A platform is a product with internal customers, so it needs product discipline: research, a roadmap, a support model, adoption metrics, and the willingness to deprecate. The most common failure isn't bad technology — it's a platform team that builds what's interesting rather than what's blocking, measures its own activity instead of its users' outcomes, and treats adoption as something that happens automatically. **Adoption is earned by being faster than the alternative, every time.**"

### 10. Standardisation vs autonomy — the eternal platform tension
**The spectrum:**
1. **Anarchy** — every team chooses everything. Fast locally, slow globally: 14 CI systems, 9 databases, no shared tooling, no security consistency, impossible to move people between teams, enormous aggregate cost.
2. **Mandate** — one stack, enforced. Consistent, but teams whose needs don't fit are blocked or route around it, innovation stalls, and the platform team becomes the bottleneck.
3. **Paved road with escape hatches** — a supported default that's genuinely the fastest option, with a documented, low-friction way to deviate (which carries extra responsibility: your own on-call, your own security review, your own compliance evidence).
4. **Federation** — a common *contract* (observability format, identity model, deployment interface, security baseline) with freedom in *implementation*. Best for large, diverse orgs.

**My position (and the reasoning to give):**
> "Standardise the **interface**, not the **implementation**. What must be uniform: identity and workload authentication, observability formats and minimum telemetry, deployment/rollback mechanics, secret management, security baselines, cost attribution, and incident process — because those are the things that break cross-team collaboration and make incidents unresolvable. What should be free: language, framework, database engine (within a supported list), internal architecture, and library choices — because those are where teams have domain knowledge the platform team doesn't.
> The mechanism is a **paved road with a visible escape hatch**: the default path is the fastest and gets the most investment; deviating is allowed but costs the deviating team support, and deviations are tracked so the platform team can see whether a deviation is a one-off or a signal that the path is wrong. **When three teams independently deviate the same way, that's a roadmap input, not a compliance violation.**"

**Handling the hard cases:**
- **A team refuses to migrate**: find out why (usually a real gap). Fix the gap, or grant a documented exception with an expiry, or accept the deviation and support it minimally. **Forced migration without a benefit destroys platform credibility.**
- **A team needs something the platform doesn't support**: enable them to build it *on* the platform (contribute the module/plugin), rather than around it.
- **The platform is genuinely worse than the alternative**: admit it, fix it, or stop offering it. **A platform team that defends a bad path loses the argument permanently.**

---

## 🔴 Scenario

### 11. "Design an internal developer platform for a 200-engineer company with 40 services."
**Start by eliciting, not by drawing boxes:**
- What's blocking delivery today? (Interview 10 engineers across teams — **this is the actual first step**, and saying it distinguishes a product-minded answer.)
- What's the current stack diversity, cloud, and compliance regime?
- How many platform engineers do you have? (**This determines everything.** 3 engineers cannot run 12 systems.)
- What are the top 5 repeated tasks teams do manually?
- What breaks most often, and what has the worst on-call load?

**Assume:** 200 engineers, 8 product teams, 40 services, mostly Go/TypeScript/Python on AWS + EKS, 4 platform engineers, SOC 2 in scope, no standard observability, deploy takes 2 hours and involves three systems, onboarding a new service takes 3 weeks.

**The design — sequenced by value per engineer-month:**

**Phase 0 (weeks 1–4): Stop the bleeding, establish the contract.**
- **Service catalogue**: every service gets a `catalog-info.yaml` (owner, tier, repo, runbook, on-call, dependencies). Even without Backstage, this is a Git convention that pays off immediately. **You cannot operate 40 services you cannot enumerate.**
- **Standard labels/tags** on everything (`service`, `team`, `env`, `tier`, `cost-centre`) — the prerequisite for cost attribution, observability filtering, and policy.
- **One deploy path**: pick GitOps (Argo CD) and make it the only way to prod. Kill the three-system deploy.
- **A shared Helm/Kustomize base** with sane defaults (probes, resources, securityContext, PDB, network policy, service account).

**Phase 1 (months 2–3): The golden path v1 — "create and ship a service".**
- **Scaffolding**: one template → repo + CI + Dockerfile + Helm chart + IaC for baseline cloud resources + dashboards + alerts + on-call registration + docs. **Target: a new service in production in under a day, from 3 weeks.**
- **CI template** (reusable workflow): lint, test, scan (SAST/SCA/secrets/image), build with BuildKit + cache, sign, SBOM, push by digest.
- **Deploy template**: GitOps commit-back of the digest, canary with automated analysis and auto-rollback, `preStop`/probes/PDB defaults baked in.
- **Observability by default**: the template creates the RED dashboard, the SLO, the burn-rate alerts, and the log/trace wiring. **A service deployed without observability isn't deployable** — enforce it with a policy, not a reminder.
- **Secrets**: External Secrets Operator + workload identity; no static keys anywhere.
- **Environments**: dev + staging per team, with a documented reset procedure.

**Phase 2 (months 4–6): Self-service infrastructure and the portal.**
- **Terraform/OpenTofu module library** for the 8 things teams actually need (VPC attachment, S3, RDS Postgres, SQS/SNS, ALB/ingress, IAM role, DNS record, ElastiCache) — secure defaults, validated inputs, complete outputs, versioned, with examples.
- **A provisioning path**: PR against the infra repo (or a portal form that creates the PR) → CI plan + policy + Infracost → auto-apply within policy, human review above a threshold.
- **Backstage** (or a commercial portal) **now, not earlier**: catalogue + TechDocs + the Kubernetes/CI/Argo plugins + the scaffolder wired to the templates. **The portal is packaging for capabilities that already exist — deploying it first gives you a pretty UI over nothing.**
- **Ephemeral preview environments** for the top 5 highest-churn services, with TTLs and a cost cap.
- **Cost showback** per team, and Infracost on infra PRs.

**Phase 3 (months 6–12): Depth, hardening, and the long tail.**
- **Data platform paths** (a database, a pipeline), **ML paths** if relevant, **batch/job paths**.
- **Compliance automation**: SOC 2 evidence generated from GitOps history, admission policies, CSPM/KSPM continuous scanning, access reviews automated from cloud audit logs.
- **Runtime security**: PSA `restricted`, signed-image verification at admission, Falco/Tetragon, default-deny NetworkPolicy in the module defaults.
- **Reliability engineering as a service**: SLO templates, incident automation (auto-created channel with context), game days, chaos experiments available to teams.
- **Deprecation and upgrade machinery**: automated module/chart upgrade PRs, a deprecation policy, and a migration helper for breaking changes.
- **Second-wave measurement and pruning**: kill what isn't used; consolidate duplicates; document the escape hatches.

**Cross-cutting decisions to state explicitly:**
- **Staffing reality:** 4 platform engineers can run this *if* they buy rather than build the commodity layers (GitHub Actions, Datadog or a managed Prometheus, AWS managed services, Backstage with few plugins) and spend their time on **integration and golden paths**. **If they try to self-host everything, they'll spend all their time on operations and ship no capabilities.**
- **The 80/20:** 5 capabilities (scaffolding, CI template, GitOps deploy, observability defaults, infra modules) deliver ~80% of the value. Everything else is a refinement. **Resist building the long tail first.**
- **Adoption plan:** pilot with 2 enthusiastic teams, iterate for 6 weeks, then launch with their testimonials and a migration guide. **Mandate nothing until the path is demonstrably faster.** Then make it the default for *new* services (cheap) and offer migration help for existing ones (expensive, so schedule it).
- **Failure modes I'd guard against:** building a portal before capabilities; requiring migration without benefit; a platform that only works for one team's stack; no support model; measuring components shipped instead of adoption; and letting the platform's own reliability slip (**a platform outage blocks 200 engineers — it needs SLOs, on-call and change management like any production system**).

**Success criteria to quote:** new service to production in < 1 day (from 3 weeks); deploy lead time < 30 min (from 2 hours); 100% of services with an owner, a dashboard, an SLO and a runbook; 90% of infra provisioned via self-service; change failure rate < 15%; platform support tickets falling quarter over quarter; and developer survey satisfaction > 4/5.

### 12. "Teams are routing around your platform. What's going wrong and what do you do?"
**First, treat it as data, not defiance.** Teams route around a platform for exactly four reasons, and you must determine which:

| Cause | Diagnosis | Fix |
|---|---|---|
| **1. The platform is slower** | Measure time-to-deploy and time-to-provision via the platform vs the workaround. Interview the deviators. Usually: an approval queue, a slow pipeline, a missing capability forcing manual steps, or a support SLA of "next week" | Remove the bottleneck: auto-approve within policy, cache/parallelise the pipeline, add the missing capability, staff support. **If the platform can't beat the workaround on speed, the platform is wrong** |
| **2. The platform can't do what they need** | Look at the deviations: are they clustered? Three teams independently building the same workaround = a roadmap input | Add the capability, or provide a supported extension mechanism (contribute a module/plugin, an escape hatch with a documented contract) |
| **3. The platform is unreliable or painful** | Check platform SLOs, incident history, breaking-change frequency, error-message quality, docs accuracy | Fix reliability first — **an unreliable platform loses trust faster than a limited one**, and trust takes quarters to rebuild |
| **4. The platform is mandated without benefit** | Was it imposed top-down? Do teams understand what it does for them? | Stop mandating; demonstrate value; get a pilot team to succeed loudly; make the path genuinely easier |

**The actions, in order:**
1. **Talk to the deviators.** Not to enforce — to learn. Ask: "what were you trying to do, what did the platform give you, and what did you do instead?" **Five of these conversations will tell you more than any adoption dashboard.**
2. **Quantify the deviation.** Which teams, which capabilities, how much infra/services are off-platform, and what risk that creates (security, compliance, cost, incident response). **You need to know whether this is a nuisance or a material risk.**
3. **Separate the deviations into "should support", "should fix", and "must not allow":**
   - **Should support** — a legitimate need the platform doesn't meet → roadmap, with a date.
   - **Should fix** — the platform *can* do it but the experience is bad → fix the experience (docs, error messages, speed).
   - **Must not allow** — a security/compliance violation → **enforce at the layer that holds** (admission policy, SCP/Org Policy, CI gate), not by asking nicely. And when you enforce, **provide the compliant alternative in the same change**, or you've just blocked people.
4. **Fix the top 3 causes and publish what you changed.** Visible responsiveness is what rebuilds trust — teams route around platforms they believe don't listen.
5. **Re-earn adoption**: pilot with a team that has a real problem, make them successful, publish the before/after numbers, and offer migration help. **Adoption is a sales job, and platform teams consistently underinvest in it.**
6. **Set the boundary honestly**: what the platform *will* do, what it *won't*, and what the escape hatch looks like (with its costs). **Publish it.** Ambiguity generates both resentment and shadow IT.
7. **Instrument it**: deviation rate as a tracked metric with a trend, reviewed monthly alongside adoption and satisfaction.

**The framing that scores:** "A platform people route around is a product that lost its customers, and the response is the same as for any churned customer: find out why, fix it, and win them back — not escalate. The exception is genuine security or compliance violations, where I enforce at the admission/cloud-policy layer while simultaneously providing the compliant path, because enforcement without an alternative is just a block. **And the metric I'd watch is not 'deviation rate' but 'deviation rate trend' — a falling trend means the platform is learning.**"

### 13. "How would you migrate 40 services onto a new platform without stopping feature delivery?"
**This is a change-management problem more than a technical one.**

**Principles:**
1. **Never require a big-bang migration.** It freezes delivery, concentrates risk, and if it fails you have 40 broken services and no platform credibility.
2. **Migrate by value, not by count.** Order by: services with the worst reliability/on-call load, services about to be touched anyway (opportunistic migration), high-churn services (they benefit most), and low-risk services first (to learn). **Leave the riskiest, most complex service until the process is proven.**
3. **New services on the platform from day one.** This is the cheapest, highest-leverage rule: the backlog stops growing. **A migration without this rule is a treadmill.**
4. **Strangler-fig per service**: run the old and new paths in parallel, shift traffic progressively, verify, then decommission. **Dual-running costs money and time — budget for it explicitly** (typically 2–4 weeks per service of parallel operation).
5. **Make migration a product**: a documented, mostly-automated path with a migration tool/script, an estimated effort per service type, a checklist, and platform-team pairing for the first N services. **If migrating takes a team two weeks of their own time, they won't do it; if it takes two hours with help, they will.**
6. **Fund it.** Migration work must be resourced — either a platform-team "migration squad" that does it *for* teams, or an agreed % of each team's capacity. **Unfunded migration mandates are how platforms die.** My preference: the platform team does the first 10 (learning + building the tooling), then teams self-serve with support for the rest.

**The mechanics per service:**
```
1. Assess: tier, dependencies, config, data, special requirements → effort estimate + a migration plan
2. Prepare: adopt the standard labels/ownership metadata; containerise if needed; externalise config;
   make the app 12-factor-compliant (stateless, env-driven, graceful shutdown, health endpoints)
3. Platformise: apply the golden-path chart/module; wire CI; wire observability; provision infra via the module
4. Validate in a non-prod environment: functional tests, load test, chaos/failure test, security scan,
   dashboards and alerts verified by *causing* a failure
5. Dual-run in prod: deploy to the platform alongside the old environment; mirror or split traffic;
   compare error rates, latency, cost, and behaviour for a defined soak period
6. Shift traffic progressively (5% → 25% → 50% → 100%) with automated rollback on SLO breach
7. Decommission: turn off the old path, delete the old infra, update DNS/docs/on-call, verify cost dropped
8. Retro: what was hard? Feed it back into the tooling and the docs before the next service
```
**The risks and mitigations:**
| Risk | Mitigation |
|---|---|
| Data migration (the hard 20%) | Dual-write or CDC-based sync with verification, a cutover plan, a rollback plan, and a **reconciliation job** to prove parity before switching reads |
| Hidden dependencies | Discovery from traces, service mesh telemetry, DNS logs and cloud flow logs **before** planning — not during |
| Config/secrets drift | Externalise config, compare rendered config old vs new, use a config-diff tool |
| Performance regressions | Load-test both paths; the new platform may have different networking (sidecar overhead!), different instance types, different caching |
| On-call knowledge gaps | The team must own the new path *before* cutover: run a game day, update the runbook, shadow an on-call shift |
| Platform capacity | Migrate in waves; capacity-plan the platform for the incoming load (a platform that falls over at service 25 is worse than no migration) |
| Feature freeze pressure | Timebox each migration; if it exceeds the estimate, stop and re-plan rather than holding the team hostage |
| Silent partial migrations | Track migration state per service in the catalogue; a "half-migrated" service is the worst state (both paths, neither owned) |

**Communicating it:** a public migration dashboard (services migrated, in progress, planned, blocked, with owners and dates), a weekly update, celebrated wins with before/after numbers ("deploy time 2h → 12min, on-call pages −70%"), and **honest reporting of the ones that went badly** — which builds far more credibility than a highlight reel.

**The framing:** "I'd treat migration as a product with a funnel: assess → prepare → platformise → validate → dual-run → shift → decommission → retro, with tooling and pairing to make each step cheap, a hard rule that new services start on the platform, and a funded plan. The measure of success isn't '40 services migrated' — it's **the aggregate improvement in lead time, change failure rate, on-call load and cost**, because that's what the migration was for. If migrating 40 services doesn't move those numbers, the platform was the wrong thing to build."

### 14. "Your platform (Kubernetes + CI/CD) has an outage that blocks all 200 engineers. Handle it."
**This is a SEV1 with an unusual property: the customer impact is internal, but the *business* impact is the velocity of the entire engineering org.**

**Immediate (0–15 min):**
1. **Declare it, with the right severity and the right framing.** "Platform SEV1: deployments and self-service unavailable for all teams." **Explicitly state that no customer-facing service is down** (if true) — otherwise leadership will assume production is out, and you'll spend the incident on communications instead of fixing it.
2. **Assign roles**: IC (not debugging), ops lead, comms lead, scribe. **The comms role is disproportionately important here** because 200 people will each individually ask "is it down?" — one channel, one pinned status, updates every 15 minutes, and it stops 200 interruptions.
3. **Stop the bleeding on the *change* side**: freeze all platform changes, pause GitOps auto-sync if it's amplifying (a broken sync can cascade), and prevent teams from "helping" by restarting things (which destroys evidence and can make it worse).
4. **Determine the blast radius precisely**: is it the cluster, the apiserver, Argo CD, the CI runners, the registry, DNS, cloud IAM, or the observability stack? **A platform outage is usually one component, and the diagnosis is "which one".**
5. **Announce the workaround immediately**, if one exists — this is the single most valuable thing you can do for 200 engineers: "deploys are down; if you have a production emergency, use break-glass procedure X (link), and platform team member Y is the approver." **Without a stated workaround, every team invents its own, and several will make it worse.**

**Diagnose (15–60 min) — the common platform-outage causes:**
| Cause | Signature | Fix |
|---|---|---|
| **etcd/apiserver degradation** | `kubectl` timeouts, 429s, APF rejections, high `etcd_disk_wal_fsync_duration` | Reduce load (a runaway controller/list loop — find it by `user-agent` in `apiserver_request_total`), scale apiserver, check etcd health/disk |
| **Certificate expiry** | Everything suddenly unauthorised/connection refused; kubelet, apiserver, webhook, or ingress cert | Rotate; **this is a famously total and famously preventable outage** — monitor all cert expiry |
| **Argo CD repo-server OOM / Redis down** | Apps stuck Syncing/Unknown, no deploys | Scale/limit repo-server, restart Redis, reduce app count per instance, shard |
| **CI runner exhaustion** | Jobs queued indefinitely | Scale runners (ARC), check for a runaway workflow, kill stuck jobs, raise concurrency |
| **Container registry down or rate-limited** | `ImagePullBackOff` everywhere, pushes failing | Registry mirror/cache, check Docker Hub rate limits, fail over to a replica |
| **CNI/network plugin failure** | New pods stuck `ContainerCreating`, DNS broken | Restart the CNI DaemonSet, check IP exhaustion (a classic: the VPC subnet ran out of IPs) |
| **Node pool exhaustion / autoscaler failure** | Pods `Pending`, no new nodes | Check cloud quotas, IAM for the autoscaler, node group health, Karpenter/CA logs |
| **Cloud IAM/federation outage** | Nothing can authenticate | Break-glass role, check OIDC provider, cloud status page |
| **A platform deploy** | Correlated with a change timestamp | **Roll it back first.** Platform teams skip their own progressive-delivery rules — don't |
| **Cloud provider incident** | Multiple unrelated symptoms, status page confirms | Follow the provider incident; fail over if you can; communicate the dependency |
| **Ingress/DNS failure** | Everything unreachable but pods healthy | Check the ingress controller Deployment (is it multi-replica, multi-AZ, with a PDB?), DNS records and TTLs, the LB |
| **Disk pressure on nodes/control plane** | Evictions, `DiskPressure`, etcd slow | Free space (logs, images, old revisions), expand, add `containerLogMaxSize` |

**Mitigate and recover:**
6. **Prefer rollback and failover over forward-fixing** under time pressure. The platform is a production system: it should have a previous known-good version, a spare control plane, or a documented rebuild path.
7. **Restore in dependency order**: identity/network → control plane → registry/CI → GitOps → workload platform → self-service portal. Restoring the portal first while the cluster is broken wastes everyone's time.
8. **Verify with evidence**: a canary deploy through the full path (build → scan → sign → GitOps → canary → healthy), not just "the pods are running". **Define the resolution criterion before you start.**
9. **Communicate resolution and the "what now"**: is it safe to deploy, is there a backlog to drain (200 queued deploys arriving at once is a second incident — **stagger it**), and what should teams do first.
10. **Watch for the second-order incident**: the recovery flood. When CI and GitOps come back, hundreds of queued pipelines and syncs fire simultaneously → registry throttling, apiserver load, DB connection storms, node scale-up beyond quota. **Throttle the recovery deliberately.**

**After:**
11. **Blameless post-incident review** with the timeline, the detection gap (did monitoring catch it, or did an engineer Slack you?), the mitigation speed, and the contributing factors.
12. **The systemic fixes that almost always come out of this:**
    - **The platform needs SLOs and paging like any production service** — including an SLO for "time to deploy a change" and "self-service availability", which are user-facing metrics, not component uptime.
    - **Certificate expiry monitoring on every cert, with alerts at 30/14/7 days.**
    - **The platform's own change management must follow the platform's rules**: canary, automated analysis, rollback. Platform teams are the worst offenders here.
    - **Reduce single points of failure**: multi-replica, multi-AZ, PDBs, sharded Argo CD, HA etcd, registry replication, CI runner pools with headroom.
    - **A tested break-glass deploy path** for production emergencies during a platform outage — documented, drilled, and independent of the platform (this is the control that turns "all 200 engineers blocked" into "feature work paused, emergencies still shippable").
    - **A documented, tested platform rebuild procedure** — because the worst version of this incident is "the cluster is unrecoverable".
    - **Load/capacity headroom** and quota monitoring, so growth doesn't cause the next one.
    - **Status communication automation**: a platform status page/channel that teams can check instead of asking.
13. **Report the business impact honestly**: engineer-hours lost × loaded cost, plus delayed releases. **This is how platform reliability gets funded** — an outage that cost 200 engineers × 4 hours is a compelling argument for HA investment that component-uptime metrics never make.

**The framing:** "The two things that make a platform outage different from a service outage are the *audience* (200 internal customers who will each interrupt you) and the *recovery flood* (everything queued fires at once). So the response prioritises a single communication channel with a published workaround, restores in dependency order, verifies with an end-to-end canary deploy, and deliberately throttles the recovery. And the durable lesson is that the platform is a production system that deserves the same SLOs, progressive delivery, HA design and rehearsed recovery as the services it runs — which platform teams, of all teams, tend to skip for themselves."

---

## Red flags

| Saying / doing this | Costs you |
|---|---|
| Building a portal before the capabilities exist | A pretty UI over nothing |
| Mandating migration without a faster path | Teams route around you; credibility gone |
| No escape hatch | Shadow IT and resentment |
| Escape hatch with no friction | Chaos and no governance |
| A platform team measured on tickets closed or components shipped | It's an ops team / activity theatre |
| Building your own CI or your own Kubernetes | Maintaining a second company's product |
| Deploying 40 Backstage plugins on day one | An unmaintained, rotting portal |
| No product owner and no roadmap | Builds what's interesting, not what blocks |
| No support model or SLO for the platform | Self-service generates tickets anyway |
| Ignoring the platform's own reliability/SLOs | A platform outage blocks everyone |
| Standardising implementation instead of interface | Blocks legitimate diversity; teams deviate |
| A ticket portal presented as self-service | A queue with a form |
| No cost/quota controls on self-service | Unbounded spend |
| Raw-resource self-service instead of curated modules | No guardrails, 60 variants |
| Per-PR environments for every service | A brutal cost curve for uneven value |
| Unfunded migration mandates | The migration never happens |
| Half-migrated services left in both paths | Neither owned, both risky |
| Activity metrics used to rank teams | The metric stops being honest |
| Not talking to the teams that deviated | You'll fix the wrong thing |
| No "new services start on the platform" rule | The backlog grows forever |

## Rapid recall

1. Platform engineering = a **product** (with users, a roadmap, adoption metrics, a support SLO) that removes **extraneous cognitive load** so stream-aligned teams can focus on their domain. DevOps is the goal; platform engineering is how it scales.
2. **Team Topologies**: stream-aligned / platform / enabling / complicated-subsystem; interaction modes = collaboration, X-as-a-Service, facilitating. **Team API** = how you're consumed. **Thinnest viable platform** = as small as possible while reducing cognitive load.
3. **Golden paths**: must be the *easiest* path, opt-in with a visible escape hatch, complete end-to-end, secure-by-default, versioned like a library with 60 dependents, and measured (adoption, deviation, time-to-first-deploy).
4. **IDP layers**: catalogue/discovery → scaffolding → CI/CD + GitOps → infra self-service → runtime → observability-as-a-service → security-by-default → secrets/identity → environments → cost → support/docs.
5. **Backstage**: value = the **catalogue + ownership model**; cost = it's a React app you must operate and plugin-maintain. Start with catalogue + TechDocs + 2–3 plugins + templates once a golden path is stable.
6. **DevEx**: flow, feedback loops, cognitive load. Measure with DORA + SPACE + pipeline p95 + time-to-first-commit + flake rate + **quarterly surveys**. Never rank individuals by DevEx metrics.
7. **Build vs buy vs assemble**: don't build commodity; assemble OSS with **open formats** (OCI, OTel, HCL, Prometheus, GitOps) to keep exit options; buy where operating isn't worth the headcount; build only the **integration layer** — that's the platform.
8. **Self-service that works**: curated modules (not raw resources), guardrails at module + CI + **cloud-policy** layers, auto-approve the boring 90%, everything through Git, legible feedback (plan + cost + access instructions), idempotent and reversible, quotas per team, a real support model.
9. **Crossplane** = infra as Kubernetes CRDs with Compositions/Claims; great for a Kubernetes-centric self-service layer, coupled to cluster lifecycle and eventually-consistent. Terraform for foundations; Crossplane or Atlantis/portal for the claims layer.
10. **Environments**: local → ephemeral preview (per-PR, TTL'd, capped, top-churn services only) → dev → **staging with prod-shaped topology and pseudonymised subset data** → prod. **No test-data strategy fully reproduces prod → progressive delivery + auto-rollback matters more than a perfect staging.**
11. **Platform as a product**: product owner, stable headcount funding (not project funding), requests-as-PRs, public roadmap, tiered support with an SLO, contribution model, and metrics on **adoption / time-to-first-deploy / self-service success / DORA / deviation trend / survey** — not components shipped.
12. **Standardise the interface, not the implementation**: uniform identity, observability, deploy mechanics, secrets, security baseline, cost attribution, incident process; free choice of language, framework, and DB engine within a supported list. **Three teams deviating the same way = a roadmap input.**
13. **Platform outage**: state clearly whether production is affected → IC/comms/scribe → freeze platform changes → publish a **workaround + break-glass path** → identify the single failing component (cert expiry, etcd/apiserver, Argo repo-server, runners, registry, CNI/IP exhaustion, autoscaler quota, a platform deploy) → rollback/failover → restore in dependency order → verify with an end-to-end canary deploy → **throttle the recovery flood** → post-mortem: platform SLOs, cert monitoring, HA, tested break-glass, tested rebuild.
14. **Teams routing around you**: it's churn data — slower? can't do it? unreliable? mandated without benefit? Talk to five deviators, quantify, then split into support / fix / enforce (enforce only at the layer that holds, and ship the compliant alternative in the same change). Watch the **deviation trend**, not the rate.
15. **Migration**: never big-bang; new services on-platform from day one; strangler-fig with dual-run and progressive traffic shift; migrate by value not count; make migration a *product* with tooling and pairing; fund it; track half-migrated services as the worst state; measure success as aggregate DORA/on-call/cost improvement.

→ Next: [`16-Databases-and-Storage`](../16-Databases-and-Storage/README.md)
