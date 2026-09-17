# DevOps — Real Interview Questions

> ~60 questions across 5 parts. DevOps interviews grade: tool depth **plus** the *why*, production instincts, and how you'd operate a pipeline you don't fully control.
> You'll have built the Terraform track in this workspace — reference it: "I ran a full init/plan/apply/destroy loop against real AWS/Azure."

---

## Part 1 — Basic Level (phone screen / fundamentals)

**Q1. What is CI/CD? Difference between CI and CD (the D's)?**
→ CI: every commit builds + tests automatically, fast feedback. CD = **Continuous Delivery** (one command away from prod, human approves) vs **Continuous Deployment** (auto-promotes when green). Say the distinction out loud — mixing them up is the #1 basic-round tell.

**Q2. What's in a good Dockerfile?**
→ Small base image (distroless/scratch/alpine where safe), copy *dependencies before code* (layer caching), non-root user, one process per container, no secrets in image, explicit `EXPOSE`/`HEALTHCHECK`, pinned base versions. Probe: "why multi-stage?" (build stage with toolchain, final stage without — smaller image, no compiler).

**Q3. Container vs VM?**
→ VM = hardware isolation (kernel per VM, slow boot, bigger). Container = shared kernel, namespaces + cgroups (fast, lightweight, image = filesystem layers). Isolation weaker → same-host containers can be affected by kernel bugs; use runtime hardening / microVMs (gVisor, Firecracker) where you need the middle.

**Q4. What is an image layer? Why does layer order matter?**
→ Docker images are stacked read-only filesystem layers, cached by content. Order matters because a changed layer invalidates it and everything after it — put rarely-changed things (deps) first, code last.

**Q5. `git clone` vs `git fetch`? What does `--depth 1` do?**
→ clone = full repo copy (first time). fetch = update remote refs without merging. `--depth 1` = shallow clone (last commit only) — in CI it cuts checkout time from minutes to seconds. Probe: "what breaks with shallow?" (history-dependent builds, git-describe tags) — say "pin by commit, not tag."

**Q6. Linux: a process is eating 100% CPU. First commands?**
→ `top`/`htop` (find PID) → `top -H -p PID` (threads) → `strace -p PID` (what syscalls it's spinning on) or `perf top` (hot functions) → check if it's GC (Java), a busy-loop, or a regex catastrophic case. Say "identify *what it's doing* before killing it — the log might be the evidence."

**Q7. `ping`, `traceroute`, `dig`/`nslookup`, `curl -v`, `nc` — when do you use each?**
→ ping = reachability/RTT (ICMP may be blocked — don't trust it alone). traceroute = where the path breaks. dig = DNS resolution (TTL, which nameserver, record type). curl -v = TLS handshake, headers, redirects. nc = raw port check (`nc -zv host 443`). Scenario: "site down for all users" → dig first (DNS is the classic silent killer).

**Q8. What is an HTTP load balancer (L4 vs L7)?**
→ L4 (TCP): forwards by IP:port, fast, no protocol awareness (AWS NLB, Azure LB). L7 (HTTP): inspects path/host/headers, can route per path, terminate TLS, redirect (ALB, Nginx). Say when each is right: gRPC/TCP → L4; per-service routing on shared ingress → L7.

**Q9. What is DNS and what's a TTL? Why do DNS changes take minutes?**
→ Distributed hierarchy (root → TLD → authoritative). TTL = how long resolvers cache an answer. "Change takes minutes" = clients still holding cached records until TTL expires (plus local resolver caches). Say `dig +trace` to watch the chain.

**Q10. Explain TLS to a junior. What happens in a handshake (roughly)?**
→ Client says "hi, I support these ciphers" → server picks + sends cert (signed by CA) → client verifies cert chain (CA trust, hostname, expiry) → both derive shared keys (ECDHE) → symmetric encryption from then on. Purpose: confidentiality + integrity + *server identity* (client certs for mutual TLS).

**Q11. What's a reverse proxy? Nginx vs HAProxy vs Envoy?**
→ Front-end that receives external traffic and forwards to backends (TLS termination, routing, rate limits, logging). Nginx = general (web + L4/L7, config files). HAProxy = L4/L7 powerhouse, stats. Envoy = proxy for service meshes, xDS dynamic config. "Same job, different control plane and ecosystem."

**Q12. What is a monorepo? Pros/cons for CI?**
→ One repo for many services/libs. Pros: atomic cross-service changes, one set of tooling, easy dependency bumps. Cons: big checkouts, CI must be *selective* (only build/test what changed — path filtering / dependency graph), blast radius of bad tooling. Say you'd use a dependency graph (BuildBuddy/Trunk/turborepo/Bazel) to avoid testing everything on every change.

**Q13. SSH keys vs passwords. How do you rotate a deploy key?**
→ Ed25519 keypair, public on server, private never leaves the deploy agent. Rotation: add new public key → verify deploys work with it → remove old → audit log of who added it. "You're deploying from a key that 4 people know the private half of" = the smell you should be able to name.

**Q14. What is a systemd unit? `systemctl enable --now`?**
→ Unit file declares how a service starts/restarts/dependencies. `enable` = start on boot (symlink), `now` = start immediately. `Restart=always` + `RestartSec` for auto-recovery. Say: "containers don't have systemd — the entrypoint IS the process, and the orchestrator is the init."

**Q15. What's the difference between a build, a package, and an artifact?**
→ Build = compile+test from source (ephemeral). Package = the deployable unit (image/zip) with a version. Artifact = the stored, addressable, immutable output (registry, artifact repo) that deployments reference. "Never rebuild at deploy time — deploy exactly what CI tested."

**Q16. What is a health check? Liveness vs readiness?**
→ Liveness = "is the process alive" (restart if not). Readiness = "can it take traffic right now" (remove from LB until yes). Conflating them is a classic: a slow-starting app gets killed (liveness too tight) or takes traffic unready (readiness missing).

**Q17. How do you debug a failing job in a CI pipeline?**
→ Read the exact stage + retry the step (is it flaky or deterministic?) → run the same command locally with the same env vars (or a container with the same base image — "works on my machine" is usually "different image") → check the resource limits (CI runners are 2 CPU — your local is 16) → add `set -x`/verbose logs. "Reproduce in the *pipeline's* environment, not yours."

**Q18. What is a secret? List 3 places you would NOT keep one.**
→ Any sensitive credential (key, token, password). NOT in: git (even "private" repos — it's forever in history), Docker images (layers are inspectable), or CI logs (they leak to dashboards). YES in: secret manager (Vault/SSM/Key Vault) injected at deploy time, short-lived where possible.

**Q19. What does "immutable infrastructure" mean? Give the anti-pattern.**
→ Servers are replaced, never patched in place (config = code; new server from the image; old one discarded). Anti-pattern: the "snowflake" prod box someone SSH'd into and `yum upgrade`d three years ago — un-reproducible, un-rollback-able.

**Q20. Blue-green vs canary vs rolling — one sentence each + when?**
→ Blue-green: two full environments, instant switch, easy rollback (2x cost). Canary: small % of traffic to new version first, auto-abort on metrics (needs good metrics). Rolling: one instance at a time (cheap, slower, no traffic-level safety). "Canary when you have metrics to trust; blue-green when you don't."

---

## Part 2 — Real Job-Specific Questions

**Q21. Design the CI pipeline for a team with 20 services in one monorepo.**
→ Stage 1 (always, < 5 min): lint + unit tests for *changed* services (path filtering). Stage 2: build image + push to registry (immutable tag = git SHA). Stage 3: integration tests against ephemeral env (spin up real deps in a container). Stage 4: deploy to staging + smoke tests. Trunk-based: PRs merge when 1–3 green. Cache aggressively (deps, layers). "Total < 15 min or devs will merge red."

**Q22. A deploy broke production. Walk me through your response.**
→ (This is the DevOps version of SRE's scenario — use the 5-step framework.) Roll back first if the deploy is the suspect (you can investigate later on a healthy system) → confirm rollback worked via metrics, not "the page loads" → find the correlation (deploy vs metrics elbow) → postmortem with *systemic* fix: "this class of break shouldn't have shipped" → improve canary/health-check/gate that would have caught it.

**Q23. How do you manage Terraform state across 30 engineers and 5 environments?**
→ Remote backend (S3/Storage + DynamoDB/blob locking) with **one state file per environment** (`env/terraform.tfstate`), workspaces only for small variations (prefer separate dirs per env — workspaces share one config). `plan` in CI on every PR (policy check + human review of the plan), `apply` only via pipeline with approval gates. `terraform plan -out` + `apply -auto-approve <planfile>` so what was reviewed is what runs. Never `terraform apply` from a laptop in prod.

**Q24. Terraform says it will destroy a resource that must not be touched. Why, and what do you do?**
→ Causes: state drift (someone changed it in the console), a name/CIDR you changed, or the resource was never in state (import it). **Never** `terraform apply` with that plan; `terraform state show` to see what TF thinks, diff against reality, `import` or `state mv` to reconcile. Say "the state file is the truth of *what we manage* — drift means someone bypassed the process, which is the real incident."

**Q25. Terraform plan in CI passes, but apply in the pipeline fails. Debug it.**
→ Common causes: lock held by a concurrent run (DynamoDB row / blob lease — who's holding it?), provider version drift between CI and pipeline (check lock file — it's committed!), credentials with different permissions, non-determinism (a `data` source returning different values, e.g. "latest AMI" changed between plan and apply). "Re-run plan *in the pipeline* right before apply — if it changes, you have non-determinism."

**Q26. How do you do zero-downtime database migrations?**
→ Expand→migrate→contract (see SDE3 Q24): add column (nullable) → deploy app writing both → backfill in batches → switch reads → drop old. Migrations run *before* the app deploy, never with it (schema must tolerate old+new code simultaneously — "two-version overlap" rule). Never a migration that locks the table for minutes on a hot row — batch it.

**Q27. How do you handle config/secrets across dev/staging/prod in IaC?**
→ Secrets: secret manager (Vault/SSM/Key Vault) referenced at deploy time — **never in state, never in code**. Non-secret config: variables per environment (separate TF dirs or `env.tfvars` committed, reviewed). Dynamic where safe (data sources: AMI lookup, caller identity). "Anything a junior can read in the repo is a public secret."

**Q28. Design a rollout strategy for a service with 50k users.**
→ Canary: 1% → 10% → 50% → 100%, each stage gated on error rate + p99 SLO (auto-abort), with an instant rollback. Feature flags *inside* the canary for risky sub-features. Stagger by region (one region first — the failure is local). Announce the schedule; page on abort. "Rollout is a *hypothesis test*: 'version N is as healthy as N-1' — and you can reject it."

**Q29. Your build takes 40 minutes. Reduce it to 10. Prioritized plan.**
→ (1) Measure: stage timing first — find the 2 stages eating 80%. (2) Parallelize independent jobs. (3) Cache: dependency fetch, Docker layers, compiled artifacts keyed by content hash. (4) Test selection: only run tests affected by the change (coverage-based). (5) Shallow clone + skip unchanged jobs. (6) Bigger/faster runners for the critical path. "Don't optimize everything — the build is a DAG, cut the critical path."

**Q30. How do you secure a CI/CD pipeline itself?**
→ Least-privilege service accounts per stage (build can't deploy), signed commits + branch protection (no force-push to main, required reviews), secrets injected per-run and rotated, image scanning + dependency scanning (SAST/SCA) as gates, **supply chain**: build from pinned sources, sign artifacts (cosign/SLSA), verify signature before deploy, audit logs of who/what deployed what, and "who can edit the pipeline?" = the same trust as prod access.

**Q31. Kubernetes basics: Pod, Deployment, Service, Ingress — one line each.**
→ Pod = smallest schedulable unit (1+ containers, shared net). Deployment = desired state for N identical pods + rolling updates. Service = stable VIP + DNS name for a set of pods (the pod IPs change, the Service doesn't). Ingress = L7 routing rules (host/path → Service) at the cluster edge. Probe: "why does a Service exist?" (pods are ephemeral; nothing can depend on pod IPs).

**Q32. A pod is CrashLoopBackOff. Diagnose.**
→ `kubectl describe pod` (exit code! OOMKilled = 137, crash = 1, liveness failing) → `kubectl logs pod --previous` (the last run's log) → check the liveness probe config (is it probing before the app is ready?) → resource limits (CPU throttling → startup timeout) → config/secret missing (env var empty). "Exit code is the first clue, not the last."

**Q33. Pod is Pending. Diagnose.**
→ `kubectl describe pod` → events say why: no node fits (requests too big for free capacity — taints? node labels?), PVC not bound (storage class missing), node not ready, or quota limit. "Pending = the *scheduler* can't place it, the app never started."

**Q34. GitOps: what is it and why over "kubectl apply from CI"?**
→ The cluster state is *declared in git* (manifests in a repo); an agent (Argo CD/Flux) continuously reconciles cluster → matches repo. Why: audit trail (git log = change history), drift detection (someone kubectl-ed? agent notices + can revert), self-healing, and "the source of truth is reviewable." CI's job shrinks to "merge to the env branch."

**Q35. How do you observe a deployment? What signals?**
→ Before/after: error rate, p99 latency, throughput, saturation (CPU/mem), plus the *business* signal (checkout rate). Health endpoints are a *floor*, not observation. Say you'd gate the rollout on these (canary analysis) and that "logs spike" should never be the first thing you see — metrics + alerts come first, logs for the *why*.

**Q36. How do you manage certificates (issuance/renewal) at scale?**
→ ACME (Let's Encrypt) + cert-manager in K8s (auto-issue, auto-renew, store in secrets manager), or ACM/Key Vault certificates managed by IaC for non-K8s. Say: expirations must be *alerted on* (a cert that expired at 3am is a process failure, not a luck failure), and internal CAs for service-to-service mTLS where public CAs don't fit.

**Q37. Multi-region deploys: how do you keep two regions in lockstep?**
→ Same pipeline, parameterized by region: build once (immutable artifact) → deploy to region A → verify → region B (staggered). Config differences via per-region config, not forked code. DR: is B active-passive (failover) or active-active (data sync model decides)? "One artifact, many targets — never build per region."

**Q38. Your team's infra is in 200 YAML files by hand. How do you migrate to IaC without stopping the business?**
→ (1) Pick the highest-risk/most-touched infra first (the network, prod compute). (2) `terraform import` (or equivalent) to adopt *existing* resources into state — don't recreate. (3) Reconcile drift (document what import reveals). (4) Lock the old world: freeze manual changes, console access read-only via IAM, "IaC or it didn't happen." (5) Migrate the rest by priority. "Adopt before you create — the first win is *control*, not *fresh infrastructure*."

**Q39. How do you test infrastructure changes?**
→ Plan review is the first test (a plan you don't read is a change you didn't approve). Then: sentinel/tfsec/checkov (policy-as-code gates), staging environment that mirrors prod topology (smaller), integration tests that *verify* (query the deployed thing: is the route table actually routing?), and for changes to shared prod (VPCs) — change windows, break-glass runbooks, and canary deploys of the *consumers*.

**Q40. Explain "shift left" — concretely, for your stack?**
→ Move failure detection earlier: dependency scans + SAST in PR (not in nightly), infra plan/policy in PR (not in the deploy pipeline), unit + contract tests in PR, security review at design (not at pentest). Concrete: "a CVE found in CI takes 10 min to fix; the same CVE found in prod takes a page at 2am. Same bug, 1000x cost difference."

---

## Part 3 — Advanced Level (senior / architecture)

**Q41. Design a multi-account AWS (or multi-subscription Azure) strategy for 3 teams.**
→ Account/subscription per environment per team + shared accounts (network, security, logging) — "the 5-7 account landing zone." Centralized: identity (SSO/Entra ID), logging (aggregated to central account via CloudTrail/Activity Log), networking (shared Transit GW/VNet peering model), and **IaC pipeline in a dedicated platform team's account** that deploys to team accounts (cross-account roles, never shared keys). Data: each team owns its account; platform owns the rails.

**Q42. Design the networking for that landing zone.**
→ Hub-and-spoke: central Transit Gateway (AWS) / VNet peering + hub VNet (Azure), spoke VNet per account. Public subnets in a dedicated "network" account's VPC (single IGW — control egress), private spokes with route via hub. Egress control: NAT in the hub (or deny egress by default, allow-list per spoke). Security: cross-account VPC endpoints for S3/ECR (keep data on the private backbone, no NAT for internal APIs). Say the cost of doing it wrong: every spoke with its own IGW = no egress control + more IP to manage.

**Q43. You need a 99.95% SLA for a web service. Design the reliability architecture.**
→ Multi-AZ always (a single AZ is a 99.9% ceiling on most clouds). Multi-region for the full 99.95 (regional outages are the remaining risk): active-passive with RDS/SQL cross-region read replica + DNS failover (Route53/traffic manager), or active-active if the data model allows. Stateless web tier (scale across AZs, health-checked LB). Error budget math: 99.95% = ~22 min/month downtime — say it in minutes so the design is honest. DR: tested failover (not a doc), RTO/RPO written down.

**Q44. Cost optimization for a cloud bill that doubled in a quarter. Your process?**
→ (1) Attribute: cost allocation tags → who/what/which env (you can't fix what you can't attribute). (2) Find the top 5 line items (usually compute + data transfer + unattached EBS + idle dev). (3) Quick wins: rightsize, stop non-prod at night, lifecycle policies on storage, committed-use discounts (RI/savings plan) for *stable* baselines. (4) Structural: spot/preemptible for stateless batch, egress reduction (CDN, endpoints instead of NAT). (5) Ongoing: cost anomaly alerts per team, "cost per 1k requests" as a service metric. "Don't optimize the 5% — find the one item that's 40%."

**Q45. Design a disaster recovery plan. RTO/RPO for a SaaS with payments.**
→ Define *first*: RTO (time to restore) and RPO (data you can lose) *with the business* — payments: RPO near-0 (sync replication), RTO < 1h (auto-failover target). Tiers: DR for payments core (multi-region sync + automated failover), lower tier for admin tools (backup restore, RTO 4h). Test it: game day twice a year (restore from backup to a scratch account, measure actual RTO). "A DR plan you haven't executed is a rumor."

**Q46. Supply chain attack on a public dependency. Your response + prevention?**
→ Response: pin/rollback to last known good, assess where it ran (CI images? runtime?), rotate anything it could have touched (credentials in that env), audit what it exfiltrated. Prevention: lock files committed (reproducible builds), private mirror/proxy of dependencies (you control what enters), SBOM (CycloneDX/SPDX) for fast "is my artifact affected?" answers, provenance/signed artifacts, and "new dependency = PR with security review."

**Q47. How would you design a global deployment pipeline (10 regions, 3 clouds)?**
→ One pipeline definition, cloud/region as *inputs* (not forks): build → sign → scan → deploy to the target (provider-agnostic abstraction: the platform team's Terraform/Pulumi modules per cloud). Stagger: 1 region (canary region) → 3 → 10, with per-region gates. Rollback is per-region (you don't roll back 10 regions at once). Control plane (who can deploy where) centralized; execution distributed. "The pipeline is a product — it has users (30 engineers) and an SLA."

**Q48. Terraform at 500 resources and 10 engineers: what breaks and how do you design against it?**
→ Breaks: state contention (locking waits), plan time, one huge state file (blast radius), module coupling. Design: **split state by blast radius** (network / data / compute / per-service), each with its own pipeline; modules with stable interfaces (semantic versioning, changelogs); `depends_on` made explicit (implicit deps are landmines); plan-as-review (PR bot posts plan); refactors that must be state-preserving (`moved` blocks, never delete+recreate by accident). "State file = the contract between 10 engineers and one database of reality."

**Q49. A vendor SaaS (e.g., a billing system) has no API and deploys are manual by their team. How do you integrate safely?**
→ No API = no automation, so control the *boundaries*: dedicated service account with least privilege, changes only in scheduled windows with both parties, a runbook + screenshot-diff checklist, and *contract tests* (a scripted flow that must succeed after their deploy — smoke test your integration). Say the strategic answer: "manual vendor deploys are a standing incident risk — I'd put that in the risk register and price the exit."

**Q50. How do you measure DevOps effectiveness (beyond "we use Kubernetes")?**
→ DORA: deployment frequency, lead time for changes, MTTR, change failure rate — per team, trended. Plus: % of infra in code (drift rate), % of incidents with a runbook, cost per service, on-call page count. "DORA tells you if the *system* got better; tools tell you what you bought."

---

## Part 4 — Scenario-Based (real-time)

**S1. Friday 4pm: a Terraform `apply` you kicked off is halfway done and a resource failed. What now?**
→ **Stop** — no manual "fixes in the console" (that creates the drift you'll fight for a month). Read the failure: is it a transient API error (retry — TF resumes from state) or a real error (permission? quota? capacity?). If the partial apply left an inconsistent intermediate state, `terraform plan` to see the *delta*, not to re-run blindly. If it's Friday 4pm and it's not urgent: let it pause — "a failed apply at 4pm is cheaper than a half-understood one at 5pm." Communicate to the team what's applied vs pending.

**S2. Two teams' pipelines both deploy to the same staging environment and overwrite each other every week.**
→ Root cause: shared mutable environment. Fix, in order of effort: (1) Environment per pipeline *run* (ephemeral staging — spun up, tested, destroyed; costs money, ends the fights). (2) If shared: named namespaces/slots (team-A's and team-B's copies of the service coexist, routed by header). (3) If neither: a deploy scheduler (time-boxed ownership) + a contract test suite that runs against the *other* team's last-known-good. Say the trade-off out loud: ephemeral is the right answer; the scheduler is the compromise.

**S3. Prod database migration in the pipeline fails at step 2 of 3 (backfill). Deploys are frozen. What now?**
→ First: is the *schema* migration (step 1) safe to leave? (It should be — expand step is backward compatible; verify old+new code both work on the partial state.) Backfill is resumable by design (batched, idempotent, checkpointed) — say that's *why* you design it resumable. Options: re-run the backfill job (it picks up where it left) vs pause until a change window. If the backfill is *not* resumable (bad design): assess data skew (how many rows are un-migrated?), does any read path touch un-migrated data (if not, pause safely). Unfreeze only after step 3 is green + verified. Postmortem: "migrations must be pause/resume safe or they aren't production-grade."

**S4. A 3am page: "prod down." You're the first responder, and the dashboard is also down. Go.**
→ Declare the incident (channel, role: you're incident commander until someone takes it). **Dashboard-down is a clue, not a distraction**: is it *our* dashboard or the *provider's*? Check the provider status page (first! regional outage?), and a second signal source (the LB health endpoint via a different path, a synthetic monitor from outside the cloud, or `curl` from a laptop). Stabilize by *not* touching anything you can't observe — if the whole region is dark, the fix is failover or wait, not debugging. Communicate a status even when it's "investigating, dashboard impaired, checking provider status — next update 15min."

**S5. Your image registry got corrupted — every deploy is failing and nobody knows which tag is last-known-good. Reconstruct.**
→ (1) Stop deploys (no one "tests a fix" by deploying — that burns evidence). (2) Last-known-good = the last tag whose *deploy record* shows success (deploy pipeline logs / DB — the artifact may be gone but the *record* is there). (3) Verify it: pull the tag, hash-compare against the recorded digest (registries store digests), deploy to staging, smoke test. (4) Restore from the registry's backup/replica; re-push + re-verify digests. (5) Postmortem: why no pinning by digest? why no replica? "Digests are the answer to 'which one?'"

**S6. You find the prod SSH bastion has 14 engineers with keys, 3 who left, and no audit log. Fix it in 2 weeks.**
→ Week 1: inventory (who has keys, when added) → revoke the 3 leavers *first* (today, not Friday) → enable session logging/audit (tty recording or jump-host audit) → move to short-lived credentials (just-in-time: request access via ticket, auto-expire in 8h) so "key rotation" becomes "lapse by default." Week 2: document the break-glass (who can override, and it *pages everyone*), run a table-top ("the DB is on fire and your access lapsed — what do you do?"), report to security. "14 standing keys is 14 permanent incidents waiting for a reason."

**S7. The company is consolidating from 3 clouds to 1. Your team owns infra on all 3. Plan 12 months.**
→ (1) Inventory + map: what runs where, data gravity (what *must* stay — regulated data, low-latency requirements), lock-in points (proprietary services with no equivalent). (2) Triage: move (rehost — most), re-architect (some), or keep (a documented exception with a sunset). (3) Sequence: move the *cheapest and least risky* first (stateless services) to build the pipeline + landing zone muscle, then the data tier last (the hard part — plan the replication window). (4) The pipeline is built to be cloud-parameterized from month 1 (you'll use it for the moves). (5) Kill-switch criteria: what would make a service NOT move. "The migration is 20% moving, 80% deciding what 'equivalent' means per service."

**S8. A junior merges a change that disables a security control in the pipeline "just for this test." It's in main now. What do you do?**
→ Revert it *now* (a reverter is faster than a debate; the PR that reverts references the PR that broke it). Then: understand the real problem (the control was blocking *their* legitimate test — which is a pipeline bug, not a security bug). Fix the pipeline properly (a scoped exemption mechanism: a flag that's reviewed, expiring, and noisy — or an e2e env where the control is *supposed* to be off). Talk to the junior 1:1, non-punitive: "here's how we'd have gotten you the exemption," and add the lesson to onboarding. "The incident is the open door to fix the pipeline's friction — if you only revert, the next junior disables it again."

**S9. Your IaC codebase works but has 30 `# TODO: refactor this` and 4 people who "don't touch the networking file." Plan the next quarter.**
→ (1) Map the fear: read the networking file, write a 2-page "how it works" doc + a diagram — the moat is *unknown*, not code. (2) Add guardrails so the fear is justified to lower: policy tests on the network resources, a staging VPC that mirrors it (you can break it there), and `moved`/`refactor` PRs that change *nothing* in prod (rename, restructure) to prove the process is safe. (3) One small real change through the new process (fix a TODO) — the first successful "scary" change breaks the curse. (4) Refactor budget: 20% of a senior's time, tracked on the board like features. "You can't refactor what no one dares to read — the doc + the staging env *are* the refactor."

**S10. You're asked to cut infra cost 30% in 2 quarters. What do you cut, and what do you refuse to cut?**
→ Cut: committed-use on the stable baseline (biggest win, zero risk), rightsize the top 10 cost items (usually 3–5 are oversized by 4x), storage lifecycle (dev/scratch to cheaper tiers, delete unattached volumes), spot for stateless batch, egress (CDN + VPC endpoints), and *dev environments* (stop-at-night / ephemeral). Refuse to cut: prod redundancy (multi-AZ is the SLA), the DR replica (that's the insurance), and observability (you'll be blind when something goes wrong — the classic "cut the logs, then can't debug the outage"). Frame it: "30% is a *design* project, not a procurement project — I'll show the cost model per service before I touch anything."

---

## Part 5 — Questions to ask the interviewers

- "What's the current deployment frequency, and what's the most common reason a deploy gets blocked?"
- "When the last incident happened, what was the first thing on-call did — and how long to mitigate?"
- "What's in the pipeline that a new engineer would be surprised by?" (great question — reveals culture)
- "How much of the infra is actually in code, and what's the plan for the rest?"
- "What does the on-call rotation look like — and what's the most-paged service?"
