# RTIQ — Terraform Core on AWS (Real-Time Interview Questions)

> **Cloud:** AWS · **Tool:** Terraform · **Domain:** Basics, providers, state, variables, modules, workspaces/environments, CI/CD · **Target roles:** SDE-3 · Cloud Engineer · DevOps · DevSecOps · SRE · Platform Engineer · **Reading time:** ~56 min

**How this file is used live:** Terraform interviews are *state* interviews. Interviewers ask how you'd structure a repo, then push hard on state locking, drift, secrets in state, and "two engineers ran apply at the same time — what happens?". Then they put you in a pipeline failure. Being able to say "the plan file is the contract" and "state is the source of truth, not the code" wins these rounds.

**Legend:** ⚡ Rapid · 🔍 Deep dive · 🚨 War room · ⚖️ Trade-off · 🎯 Senior signal

---

## 1. Terraform Basics — `terraform-basics.md`

**⚡ Rapid**
1. **Q:** What does Terraform actually do?
**A.** Declarative desired-state provisioning: you describe resources, Terraform builds a dependency graph, calls provider APIs, and stores the mapping between your config and reality in state. `plan` = diff, `apply` = converge.
2. **Q:** `init`, `plan`, `apply`, `destroy` — what does each do?
**A.** `init` initialises providers/modules/backend; `plan` refreshes state and computes a diff; `apply` executes; `destroy` tears down (dangerous — always review the plan).
3. **Q:** What is idempotency in Terraform terms?
**A.** Applying the same config twice produces no changes ("no-op plan"). Non-idempotent-looking diffs (e.g. a resource always being replaced, a tag being force-updated) are a signal that something is managed outside Terraform.
4. **Q:** What is the dependency graph and how do you control it?
**A.** Terraform infers dependencies from references; `depends_on` adds an explicit edge when there's no data dependency (e.g. an IAM policy that must exist before an app starts). Overusing `depends_on` hides real relationships.
5. **Q:** What is drift?
**A.** Reality diverging from state (console edits, another tool, a manual hotfix). `plan` shows it as changes; the fix is either to codify the real state (config change/`import`) or revert it (apply). Drift is a process problem more than a Terraform one.
6. **Q:** `terraform import` vs `terraform state mv` vs `state rm`?
**A.** `import` brings an existing resource under management (writes state; you still need matching config — or with `import` blocks/generate-config, Terraform can write it). `state mv` renames/moves an object within state (refactor without recreating). `state rm` forgets a resource without destroying it (use with care).
7. **Q:** What is `-replace` / `taint`?
**A.** Forcing recreation of a resource (e.g. a broken VM). `-replace=x` at plan/apply time is the modern approach; `taint` mutates state and is the legacy way.

**🔍 Deep dive**
8. **Q:** How do you structure a repo for a 30-service platform with 4 environments?
**A.** Layered: reusable modules in one repo (versioned/tagged), thin environment roots (`envs/prod`, `envs/staging`) that call modules with distinct tfvars/backends, backend per root pointing at separate state keys, and a shared "platform"/"bootstrap" root for account-level primitives (IAM, state bucket, networking). Keep module code env-agnostic, pass differences as inputs, and avoid duplicated resource blocks between environments.
**↳ Follow-up:** "Why not one root for everything?"
**A.** Blast radius and plan time: one giant root means every apply touches everything, any error risks unrelated resources, plans take forever, and teams block each other on state locks. Split by lifecycle/ownership (network vs app vs data).
9. **Q:** How do you handle resource lifecycle (`create_before_destroy`, `prevent_destroy`, `ignore_changes`)?
**A.** `create_before_destroy` for zero-downtime replacements (ASGs/launch templates); `prevent_destroy` on stateful resources (databases, state buckets) so a delete is impossible without a deliberate edit; `ignore_changes` only for attributes legitimately managed elsewhere (e.g. an autoscaled desired count or an app-managed tag) — overuse hides real drift.
10. **Q:** How do you avoid the "plan says it will destroy everything" panic?
**A.** Don't apply blind: review why (changed name/attribute forcing replacement, a moved module address, or a state/backend mismatch), use `terraform state mv`/`moved` blocks for refactors so Terraform understands renames, and validate that the plan matches intentions. A `moved {}` block is the modern way to rename without destroy/create.
11. **Q:** What are `for_each` vs `count`, and which do you prefer?
**A.** `count` indexes by position (removing an item shifts indices and can recreate resources); `for_each` keys by a stable map key, so removals only affect that item. Prefer `for_each` for sets of resources — count only for simple repeat/conditional cases.
12. **Q:** How do you debug a failing apply?
**A.** Read the error (Terraform is unusually explicit), enable `TF_LOG=DEBUG` for provider issues, check the provider/API response, use `terraform state list/show` to understand what exists, and check whether the failure is a permissions/validation/quota issue. For provider bugs, isolate with a minimal config.
13. **Q:** What are provisioners, and why avoid them?
**A.** `local-exec`/`remote-exec`/`file` run scripts as part of apply — they're not tracked, not idempotent, and fail mid-apply leaving unsure state. Prefer user data, cloud-init, golden images, or configuration management; use provisioners only as a last resort and document why.
14. **Q:** What's the difference between `terraform providers`, `provider` blocks, and `required_providers`?
**A.** `required_providers` pins versions and source addresses (the lockfile records exact versions); `provider` blocks configure credentials/region/aliases; `terraform providers` shows the tree. Version pinning is the point — never float providers in production.

**🚨 War room**
15. **Q:** A teammate ran `apply` while your plan was in flight. What happened?
**A.** With a proper remote backend + locking, the second apply waits/fails on the lock (`Error acquiring the state lock`) — safe. Without locking (local state or an S3 backend without the DynamoDB lock table), you can get interleaved writes and corrupted state. Fix: remote backend with locking (S3+DynamoDB or Terraform Cloud/Enterprise), and a pipeline that owns applies for shared environments.
16. **Q:** Someone deleted a resource in the AWS console. What does the next plan show and what do you do?
**A.** Plan shows a create for the missing resource (Terraform wants to restore desired state). Recreate it if that's right; if the deletion was intentional, remove it from config/state. Either way, decide whether the environment should be code-driven — that's the real issue.
17. **Q:** `terraform apply` failed halfway through. What's the state of the world?
**A.** Partially applied: previously completed resources exist and are tracked in state; the failed resource may or may not exist. Terraform writes state as it goes, so `terraform state list` tells you what it thinks exists — then fix the root cause and re-apply (Terraform will converge the remainder). Don't hand-edit state.
18. **Q:** The lock is stuck ("Error acquiring the state lock") and nobody is running Terraform.
**A.** Confirm no real run is in flight (CI history, co-workers), then `force-unlock <id>` — and document why. Repeatedly force-unlocking instead of fixing a crashed pipeline is how corruption happens.
19. **Q:** State file got corrupted or truncated.
**A.** Restore from the backend's versioning (S3 bucket versioning + a known-good object version), then `terraform plan` to re-sync. Prevention: remote backend with versioning + MFA delete/least privilege, regular state backups, and no local state in shared environments.
20. **Q:** A plan wants to recreate a production database.
**A.** Stop and read the reason: a changed immutable attribute (name, engine version, subnet group), a module address change, or a missing state mapping. Fix with `moved`/`state mv` or by reverting the attribute — anything but applying. Add `prevent_destroy` and a lifecycle guard to make this impossible by accident.
21. **Q:** CI runs `terraform fmt`/`validate` but a bad config reached production. What gates did you miss?
**A.** Policy-as-code on the plan (checkov/OPA/Sentinel), a required human review of the plan output in the PR, `plan`-then-`apply` of the *same* plan file (not a re-plan), and environment protection/approvals for prod. Formatting checks catch nothing meaningful.

**⚖️ Trade-off**
22. **Q:** Monorepo vs per-service repos for Terraform?
**A.** Monorepo gives atomic changes across shared modules and one CI pipeline (easier consistency, harder access control and blast radius); per-service repos give ownership and isolation with more duplication/version-skew. Common: module library repo + environment roots in a platform repo, with app teams calling versioned modules.
23. **Q:** One state per environment vs per service?
**A.** Per environment is the minimum; per service/domain further reduces blast radius and lock contention, at the cost of more roots/backends and some cross-root coordination (data sources/remote state). Rule of thumb: split by ownership and change frequency.
24. **Q:** CLI-driven vs pipeline-only applies?
**A.** Pipeline-only for shared/production environments (auditability, consistency, no local credential sprawl); CLI for experiments and isolated dev with non-production credentials. Humans applying to prod from laptops is how shadow infrastructure happens.
25. **Q:** Terraform vs Bicep/CDK/Pulumi for AWS?
**A.** Terraform's multi-cloud ecosystem and maturity vs AWS-native CloudFormation/CDK (deep integration, no state management to run) vs Pulumi (general-purpose languages). Pick by team skills and whether you're multi-cloud — but stay consistent; mixing IaC tools per environment creates drift nobody owns.

**🎯 Senior**
26. **Q:** What does "mature Terraform practice" look like to you?
**A.** Remote backends with locking and versioning per environment, pinned provider versions with a lockfile committed, a module library with semantic versions and tests, plan-as-contract in CI with policy gates and approvals, state access restricted (state contains secrets), drift detection on a schedule, documented ownership per root module, and a runbook for the classic incidents (lock stuck, half-applied, state corruption, accidental destroy).

**🎯 Senior signal:** "state is the source of truth, not the code", `moved` blocks for refactors, and "the same plan file must be applied" — those three mark real ownership of a Terraform estate.

---

## 2. Providers — `providers.md`

**⚡ Rapid**
1. **Q:** What is a provider, and how does Terraform communicate with it?
**A.** A plugin that maps resource types to an API (AWS, Azure, Kubernetes, random…). Terraform talks gRPC to the provider process; the provider handles auth, retries, and API translation. `init` downloads them from the registry.
2. **Q:** How do you pin provider versions?
**A.** `required_providers` with version constraints (e.g. `~> 5.60`) and a committed `.terraform.lock.hcl` so every machine/CI uses identical versions/platform hashes. Floating versions = surprise breakages.
3. **Q:** How do you configure multiple AWS accounts/regions in one root?
**A.** `provider "aws"` blocks with `alias` (e.g. `aws.us_east_1`, `aws.audit`) and then `provider = aws.audit` in the resource/module. Also `assume_role` for cross-account access.
4. **Q:** How do modules inherit providers?
**A.** Implicitly from the caller (pass `providers = { aws = aws.eu }` for aliases); a module should not define its own provider config — that breaks reusability and creates hidden configuration.
5. **Q:** How does authentication usually work in AWS for Terraform?
**A.** Prefer short-lived credentials: OIDC role assumption in CI (GitHub/GitLab → `AssumeRoleWithWebIdentity`), SSO/`aws configure sso` locally, or instance/workload identity on a runner. Static access keys in CI variables are the anti-pattern.
6. **Q:** What is `data "aws_..."` and how is it different from a resource?
**A.** A read-only lookup of existing infrastructure (AMI IDs, VPC IDs, account info) — nothing is created. Prefer data sources or explicit variables over hardcoding IDs.
7. **Q:** What's the difference between `terraform init -upgrade` and a normal init?
**A.** `-upgrade` re-evaluates constraints and updates to newer allowed provider/module versions (updating the lockfile); a normal init keeps the locked versions. Upgrades should be a reviewed PR.

**🔍 Deep dive**
8. **Q:** Plan says "provider produced inconsistent result after apply" / repeated constant diffs. How do you debug a provider issue?
**A.** Identify the attribute (it's named in the error), check whether something else modifies it after apply (an AWS service adding defaults/aliases), then handle it with `ignore_changes`/`lifecycle` or a config change; check the provider changelog for known bugs and pin a working version if needed. `TF_LOG=DEBUG` shows the raw API exchange.
**↳ Follow-up:** "How do you decide between ignoring a field and fixing it?"
**A.** If the field is genuinely managed by the platform (e.g. an Auto Scaling group's desired capacity with autoscaling on), ignore it explicitly and document. If it's your drift, fix the source. Blanket `ignore_changes = all` hides everything and defeats the purpose of IaC.
9. **Q:** How do you manage cross-account and cross-region deployments safely?
**A.** Aliased providers per account/region with least-privilege roles per target, each root scoped to one account/environment where possible, and `assume_role` with an external ID for third-party accounts. Cross-account applies in one state need careful IAM design — often it's cleaner to split into separate roots per account.
10. **Q:** How do you handle provider upgrades across a large estate?
**A.** Read the changelog for breaking changes, upgrade in a low environment first with a plan diff review, watch for resource replacements (a provider upgrade can force recreation — a major incident source), pin and roll forward per root, and keep a documented rollback (revert the lockfile). Never upgrade all roots at once.
11. **Q:** What is a provider's role in state migration?
**A.** Changing a provider (or its version) can change resource IDs in state; `terraform state replace-provider` rewrites the provider address for moved sources. Do it deliberately with a plan check, because getting it wrong looks like "everything must be recreated".
12. **Q:** How do you keep secrets out of provider config?
**A.** Use workload identity/OIDC or SSO profiles (no long-lived keys), environment variables or a credential helper for local use, and never commit credentials or put them in tfvars. Provider credentials in state is a related risk — restrict state access accordingly.
13. **Q:** `default_tags` — what does it do and what's the catch?
**A.** Applies a common tag set to all resources from that provider block (great for cost allocation/ownership). Catch: tag changes can cause churn on resources that don't support certain tags, and per-resource tags override — plus some resources ignore provider default_tags in older versions. Test on a subset first.

**🚨 War room**
14. **Q:** After a provider upgrade, `plan` wants to replace 200 resources.
**A.** Don't apply. Identify the attribute being replaced (often a subtle schema/default change like `versioning`, `force_destroy`, or an ID-format change), check the provider changelog/issue tracker, then either pin back to the previous version or make a targeted config adjustment; use `moved`/state fixes if the change is a re-addressing rather than a real replacement. Roll out in non-production first.
15. **Q:** CI fails with "no valid credential sources found" after a platform change.
**A.** Verify the OIDC trust policy (subject/audience claims, repo/branch conditions), the role ARN env var, and whether the pipeline's permissions to request an ID token are intact. Most failures are trust-policy claim mismatches after a repo rename or an environment change.
16. **Q:** `init` fails with a checksum/lock error across platforms.
**A.** The lockfile records provider hashes per platform — if a developer on macOS committed a lockfile without the Linux entries, CI fails. Fix by regenerating with `terraform providers lock -platform=linux_amd64 -platform=darwin_arm64` (include all CI/dev platforms) and commit.
17. **Q:** A provider rate-limits you mid-apply in a large estate.
**A.** Reduce API calls: fewer, larger resources; use `-parallelism=1` or a low value for fragile APIs; split the root; and add retry/backoff at the provider level where supported. Also check whether a data source is being re-read excessively — data sources on every plan can multiply calls.
18. **Q:** Someone committed a `.terraform/` directory or a provider binary to Git.
**A.** Remove from tracking (and history if it contained secrets), add `.gitignore` entries (`.terraform/`, `*.tfstate*`, `*.tfvars` with secrets, `.terraform.lock.hcl` should be *kept*, not ignored), and check whether any credentials were exposed in the process. Then add a pre-commit hook/lint to block it.
19. **Q:** Two providers (AWS + Kubernetes) create a chicken-and-egg failure: the K8s provider needs the cluster endpoint.
**A.** This is a classic: use a two-stage config (cluster first, then Kubernetes resources with the cluster output as input), or the provider's dynamic credential/exec plugins, or the module's `host`/`cluster_ca_certificate` outputs passed into a separate root. Terraform's graph can't solve it in one stage when the provider must be configured before resources are known.

**⚖️ Trade-off**
20. **Q:** One provider block with aliases vs many roots per region/account?
**A.** Aliases are convenient for a few cross-cutting resources but couple regions/accounts in one state (bigger blast radius, slower plans, harder permissions). Many roots give isolation and clearer ownership at the cost of more pipelines. Split by account/environment; use aliases within a root for genuinely coupled things.
21. **Q:** Community providers vs officially supported ones?
**A.** Prefer officially supported/maintained providers (HashiCorp, cloud vendor) for stability and security; community providers are fine for niche services but pin versions, review the repo's activity, and be prepared to vendor/fork. Check for known CVEs and support posture.
22. **Q:** Managed service (Terraform Cloud/Spacelift/Atlantis) vs DIY CI?
**A.** Managed/self-hosted runners give state management, locking, policy (Sentinel/OPA), plan approvals, and a UI — at a cost and with a new dependency. DIY CI (GitHub Actions/ADO with S3 backend) is cheaper and fully under your control but you build locking/approvals/policy yourself. Choose by team size and governance needs.

**🎯 Senior**
23. **Q:** What's your policy for provider version upgrades in production?
**A.** Monthly (or security-driven) upgrade cadence: bump in dev with a plan review, then staged rollout per environment, watch for replacements and deprecation warnings, keep a documented rollback (lockfile revert + re-init), and never combine a provider upgrade with a functional change in the same PR — that's how you lose the ability to attribute a failure.

**🎯 Senior signal:** "pin and commit the lockfile with all platform hashes", provider upgrades as a staged change with plan review, and knowing that provider changes can force replacements. Those are earned details.

---

## 3. State Management — `state-management.md`

**⚡ Rapid**
1. **Q:** What is Terraform state, and why does it exist?
**A.** A JSON mapping of config addresses to real resource IDs plus attributes/dependencies. Terraform needs it to plan, to detect drift, and to destroy correctly. Without state, Terraform can't know what it manages.
2. **Q:** Why must state be remote in a team setting?
**A.** Shared, locked, versioned, and encrypted by default — local state means no locking, no history, risk of committing secrets, and divergence between engineers. Production: S3 (versioned, encrypted, blocked public access) + DynamoDB (or `use_lockfile` in newer backends) for locking.
3. **Q:** What does state contain that's sensitive?
**A.** Everything you set, including plaintext secrets/passwords/keys, connection strings, and often full resource attributes. Treat state as a secret store: restrict access, encrypt, enable versioning, and avoid writing secrets as resource arguments where possible.
4. **Q:** How does locking prevent corruption?
**A.** A lock ensures one apply at a time modifies state; concurrent applies would otherwise interleave writes and produce incorrect state (phantom resources, duplicates, or destroys). Always configure locking in the backend.
5. **Q:** What is partial state / `terraform refresh`?
**A.** Refresh reconciles state with reality (a plan does this implicitly now). You can target a refresh (`terraform apply -refresh-only`) to reconcile drift without changing resources — useful for adopting manual changes deliberately.
6. **Q:** Can you share state between roots?
**A.** Yes via `terraform_remote_state` data sources or (better) outputs published to SSM/Parameter Store and read via data sources. It creates coupling — prefer explicit interfaces (outputs → variables/data) over reaching into another root's state.
7. **Q:** What is `terraform state rm` for?
**A.** Removing an object from state without destroying it (e.g. handing a resource over to another root, or forgetting something broken you'll re-import). Always know where it's going afterwards.
8. **Q:** What's a workspace's relationship to state?
**A.** Each workspace has its own state within the same backend (e.g. `env:/prod/terraform.tfstate` in S3), so workspaces isolate state — but they share the same config and provider setup, which is the main limitation (see workspaces/environments).

**🔍 Deep dive**
9. **Q:** Design state for an enterprise: 4 environments, 3 AWS accounts, 25 service roots.
**A.** One state object per root per environment, stored in a central (or per-account) S3 bucket with versioning + SSE-KMS + access logging + resource policy restricting to the CI roles, DynamoDB locking (or native lockfile locking), state key naming that encodes account/env/service, cross-state data exposed via SSM outputs rather than remote state where possible, and least-privilege IAM so a team can only touch its own state keys. Add scheduled drift detection per root and a documented break-glass path.
**↳ Follow-up:** "How do you stop a developer reading production state?"
**A.** The bucket policy grants read/write only to specific CI roles and platform identities (not to human roles), KMS key policy restricts decrypt to those roles, and humans get access through a PIM-style temporary elevation with logging. State read = full secret read, so treat it accordingly.
10. **Q:** How do you move resources between states without downtime?
**A.** `terraform state mv` (or `moved` blocks for config-level refactors) plus a matching config move: remove from the source root's config, add to the target root with identical resource arguments/identifiers, then move the object in state and verify with `plan` on both roots showing no changes. Do it in a change window with both roots locked by one operator.
11. **Q:** How do you handle a resource created outside Terraform that must be adopted?
**A.** `import` blocks (declarative, reviewable) or `terraform import` with matching config, then a plan that should be empty (adjusting any attributes Terraform would otherwise change — often tags/missing defaults). Confirm "no changes" before you call it adopted.
12. **Q:** How do you prevent accidental destroys via Terraform?
**A.** `prevent_destroy` on stateful resources, `prevent_destroy` on the state bucket itself, a policy gate that blocks plans containing destroy on protected resource types (OPA/Sentinel/checkov), separate prod credentials where Terraform cannot delete (e.g. deny `DeleteDB*` for the app pipeline), and MFA delete/versioning + backups for the state object. Then a documented two-person rule for planned deletions.
13. **Q:** What's your drift management process?
**A.** Scheduled `plan` (read-only) per root with notifications on non-empty plans; triage into "codify it" (update config/import) or "revert it" (apply); alerts on the console/CLI identities doing out-of-band changes (CloudTrail), and a periodic access review to remove the permissions that allow manual changes. Drift reporting without remediation is theatre.
14. **Q:** State locking fails in CI because a previous job died. How do you make this resilient?
**A.** Add job timeouts and always-run unlock/cleanup where appropriate, use the backend's lock (DynamoDB lock items can go stale and be cleared), avoid long-running applies, and (best) adopt a managed/contracted apply system (Terraform Cloud/Atlantis) that manages locks and cancellation. Include a documented force-unlock runbook with a verification step.
15. **Q:** How do you back up and recover state?
**A.** S3 versioning (recover a previous object version), replication to a second bucket/account, and periodic exports; practice restoring state and running a plan to validate. State recovery is a real DR scenario — if state is lost, you must reconstruct it by importing resources one by one, which is painful. Say that.

**🚨 War room**
16. **Q:** A `terraform apply` deleted a production database. What do you do first?
**A.** Restore service from the database's own backups/PITR (this is why DB backups exist independently of Terraform) — determine the last good point and provision a new instance/restore, then repoint the app. In parallel: stop the pipeline (revoke the credential's delete permissions), preserve the plan/logs for the review, and check `prevent_destroy`/policy gates. Then fix the mechanism: protected resources policy, deletion protection at the resource level (AWS `deletion_protection`), and IAM that can't delete production data.
17. **Q:** Two pipelines applied at once and now the plan shows 60 phantom changes.
**A.** Verify what actually exists (`state list`, console/API) before touching state; the correct fix is usually a `refresh`/`apply -refresh-only` for one root, then remove the duplicates with `state rm` (for objects Terraform no longer owns) and re-import as needed. Then enforce single-writer-per-state: pipeline serialisation, locking verified, and no human applies.
18. **Q:** State file is huge and plans take 20 minutes.
**A.** Split the root (by domain/lifecycle) — the standard answer — plus reduce data source calls, remove `terraform refresh` of unrelated resources, and consider `-target` only for emergencies (not as a routine, since it leaves state inconsistent with config). Also check for a runaway resource type generating thousands of objects that should be managed elsewhere.
19. **Q:** Someone ran `terraform destroy` in the wrong directory.
**A.** If the state was remote with `prevent_destroy`/deletion protection, damage is limited; otherwise restore state to a previous version, then re-apply to recreate resources, and restore data from backups where Terraform can't (databases, buckets with content). Then: `prevent_destroy` everywhere it matters, destroy locked behind a separate highly restricted role, and a "destroy requires a change ticket + two approvals" rule.
20. **Q:** Secrets appeared in a plan output in CI logs.
**A.** Mark the variable/output `sensitive` (Terraform still stores it in state), rotate the exposed secret, restrict who can view CI logs, and move the value out of Terraform entirely (fetch at runtime via the app's identity). Plan output is a leak surface — treat it like one.
21. **Q:** The state bucket was deleted (or made unreachable).
**A.** Restore the bucket/object from replication or versioning (ideally in a separate account that survives compromise), verify the state parses, then run plans. If truly lost, recovery means importing every resource into a fresh state — measured in days, not hours, which is the argument for state backup/replication being non-negotiable.
22. **Q:** A developer edited the state JSON by hand to "fix" an error.
**A.** Stop and assess: restore from the last good version and re-run the correct operation (`state mv`/`import`/`rm`), because hand edits break the serial/lineage metadata and can silently corrupt future applies. Then make the case in the retro: state is never edited manually, and the toolbox is `state mv`/`import`/`rm` plus `moved` blocks.

**⚖️ Trade-off**
23. **Q:** Monolithic state vs many small states?
**A.** One state is simple to reason about but has a huge blast radius, slow plans, and lock contention; many small states reduce risk and parallelise teams but require explicit data sharing (outputs/SSM) and more pipelines. Sweet spot: split by environment + lifecycle domain, not by individual resource.
24. **Q:** `terraform_remote_state` vs published outputs (SSM/Parameter Store)?
**A.** Remote state couples the consumer to the producer's entire state (and requires read access to it — a secrets risk); published, narrow outputs expose only what's needed and decouple backends. Prefer published outputs/parameter store.
25. **Q:** Workspaces vs directories for environments?
**A.** Workspaces share code but also share providers/variables/backing credentials, making "prod and dev in one config" easy to get wrong; separate directories/roots give explicit, reviewable, isolated environments. For real production/dev separation, use directories (or Terragrunt-style layering).
26. **Q:** Drift detection vs forbidding manual change?
**A.** Forbidding manual change (read-only console, no human write roles, SCPs) is the stronger control; drift detection is the safety net for what slips through (automation, break-glass, legacy processes). You need both — detection without prevention just logs the problem.
27. **Q:** Store state in the same account as the resources vs a dedicated state/management account?
**A.** A dedicated (ideally separate, locked) account reduces the blast radius: killing the wrong resource is bad, but losing the ability to manage everything is worse. Central accounts also simplify access control and audit. Most enterprises use a dedicated state/backend account with cross-account read/write restricted to specific pipeline roles.

**🎯 Senior**
28. **Q:** What's your state governance standard?
**A.** Remote backend per environment with versioning + KMS + access logging + locking; no human write access to production state (CI roles only, elevation logged); one state per root with a documented owner and purpose; state key naming convention and tagging; scheduled read-only plans with alerts; `prevent_destroy` on stateful resources and on the bucket itself; replication for DR; secrets kept out of resource arguments where possible (and state treated as a secret regardless); and a rehearsed runbook for lock/corruption/accidental-destroy scenarios.

**🎯 Senior signal:** "state contains secrets so treat it like a secret store", "the same plan file must be applied", and "recovering a lost state means importing everything — days of work". That's real ownership.

---

## 4. Variables, Outputs & Locals — `variables-outputs-locals.md`

**⚡ Rapid**
1. **Q:** Variables vs locals vs outputs?
**A.** Variables are inputs (from tfvars/env/CLI), locals are computed internal values (derived once, reused), outputs expose values to the caller/CLI/other roots. Rule: variables for what changes, locals for what's derived, outputs for what's shared.
2. **Q:** What variable types does Terraform support?
**A.** `string`, `number`, `bool`, `list(...)`, `set(...)`, `map(...)`, `object({...})`, `tuple([...])`, plus `any`. Typed variables with `validation` blocks catch errors at plan time rather than mid-apply.
3. **Q:** How do you supply values?
**A.** `terraform.tfvars`/`*.auto.tfvars`, `-var-file`, `-var`, environment variables (`TF_VAR_*`), CI-provided files, or defaults in the variable block. Precedence matters — auto-loaded files are easy to get wrong in CI.
4. **Q:** What is `sensitive = true` doing (and not doing)?
**A.** It redacts the value in CLI output/plan and marks it in state (`sensitive` metadata) — it does *not* encrypt it, and the value is still in state. Pair with protected state backends and avoid putting secrets in Terraform at all.
5. **Q:** How do you validate inputs?
**A.** `validation` blocks with conditions and error messages (e.g. instance type allow-list, CIDR format, environment ∈ {dev,staging,prod}), plus `precondition`/`postcondition` checks on resources/data sources for runtime assertions.
6. **Q:** What are output `description` and `sensitive` for?
**A.** Documentation and redaction. Outputs are the module's interface — name them meaningfully (not `output1`) and mark secret-bearing ones `sensitive`.
7. **Q:** How do you share values between modules?
**A.** Module `outputs` → consumed as inputs by other modules in the same root, or published to SSM/Parameter Store for other roots to read via data sources. Explicit interfaces beat implicit coupling.
8. **Q:** What are functions you use most?
**A.** `lookup`, `merge`, `try`, `coalesce`, `format`/`join`, `cidrsubnet`, `toset`/`tolist`, `jsonencode/decode`, `templatefile`, `for` expressions and `flatten`. HCL is a configuration language, not a programming language — heavy logic belongs in modules/automation.

**🔍 Deep dive**
9. **Q:** How do you parameterise one module for 4 environments and 3 regions without duplication?
**A.** A single module with a typed `object` variable (or a map of environment configs) and per-environment tfvars files; environment/region differences expressed as data (naming prefixes, CIDRs, instance classes, feature flags) not as code branches. Avoid `count = var.env == "prod" ? 1 : 0` sprawl — model behaviour explicitly (e.g. a `capacity` object).
**↳ Follow-up:** "How do you prevent someone deploying prod with dev sizing?"
**A.** Validation blocks on the variable (e.g. prod requires ≥3 AZs and instance class in an allow-list), policy-as-code on the plan, and a separate prod root with its own tfvars that requires a pipeline approval. Guardrails at three levels: types, policy, and process.
10. **Q:** How do you handle secrets in variables?
**A.** Don't pass secrets where avoidable: reference them at runtime (Key Vault/Secrets Manager via the app's identity, `data` sources), or inject them via a secrets manager integration/env at apply time. If Terraform must know a secret, mark it sensitive, keep it out of tfvars in Git, and know it lands in state — so the state backend is the control.
11. **Q:** What's your naming/tagging convention, and where does it live?
**A.** In locals: a `name_prefix` composed from org/env/app/region (+ a short random suffix where global uniqueness is needed), plus a `tags`/`labels` map with owner, environment, cost-centre, and data classification, applied via provider `default_tags` and per-resource overrides. Consistency comes from the module, not from discipline.
12. **Q:** How do you compose objects deeply (merging defaults with overrides)?
**A.** `merge()` for maps/shallow merges; for deep merges use a small helper module/function pattern (`deepmerge` via a module call) since HCL has no native deep merge. Keep the override surface small — complex merging is a smell that the interface is wrong.
13. **Q:** How do you avoid "for_each with unknown values" errors?
**A.** Keys must be known at plan time: derive maps directly from variables/locals (not from resource attributes created in the same apply), avoid `toset()` of values that include computed fields, and split into two stages if a resource attribute must drive iteration. This is one of the most common real-world errors.
14. **Q:** How do you test variable/module behaviour?
**A.** `terraform validate` + `fmt` in CI, `plan` against a sandbox account, and native test frameworks (`terraform test` with `.tftest.hcl`) or Terratest for module contracts; plus policy tests on sample plans. If a module takes `object` inputs, add negative tests for validation blocks.
15. **Q:** How do you handle outputs that depend on resources created later, or on flaky data sources?
**A.** `depends_on` on the data source/resource, `try()`/`coalesce()` for optional values, and restructuring so the dependency is explicit via references. Flaky data sources are usually a sign you should pass the value as a variable instead of looking it up each run.

**🚨 War room**
16. **Q:** A tfvars file with production values was committed to Git.
**A.** Rotate any secrets in it immediately, remove the file from history (rewrite or use your Git host's purge tooling), add `.gitignore` + secret scanning (including push protection), and move secret values out of tfvars into a secrets manager/CI variable store. If it was only non-secret config, still fix the pattern — the next commit could be worse.
17. **Q:** An apply failed because a variable was missing in CI but present locally.
**A.** Variable resolution differs: auto-loaded `*.auto.tfvars` may be local-only, `TF_VAR_*` env vars set in CI may be absent in a fresh shell, or the CI uses a different working directory. Make inputs explicit: pass `-var-file=envs/prod.tfvars` in the pipeline and document required variables in the README.
18. **Q:** Secret values are visible in `terraform output` for anyone with plan rights.
**A.** Mark them `sensitive` (redacts CLI output), restrict who can run plans/read state, and redesign so the secret isn't an output at all (the consumer reads it from the secrets manager using its own identity). Rotate anything that was exposed.
19. **Q:** A module upgrade changed the type of a variable, breaking three roots.
**A.** Treat modules like APIs: version them (Git tags/registry), document breaking changes, and migrate roots deliberately (the module's major version bump signals it). Then add `terraform test`/example roots to CI so a breaking interface change is caught before consumers hit it.
20. **Q:** Drift between environments because someone hand-edited a tfvars file.
**A.** Make tfvars review-only via CODEOWNERS/branch protection, store them next to the root in Git (with secret values excluded), and add a CI check that diffs non-prod/prod parameter *structure* so only values differ. Where environment config lives, it must be code-reviewed.
21. **Q:** Locals are producing a value that changes every plan.
**A.** Something non-deterministic is in the local — `timestamp()`, `uuid()`, a shuffled list from a `set`, or a data source whose output varies. Remove non-deterministic functions from anything stored in state; use a random resource (`random_id`) whose value persists, or a fixed input.

**⚖️ Trade-off**
22. **Q:** tfvars files vs a config service (Consul/SSM) for environment values?
**A.** tfvars in Git are reviewable and versioned with the code (good for infrastructure shape); a config service suits values that change independently of code (feature flags, endpoints) but introduces runtime coupling and less reviewability. Infrastructure shape → Git; runtime config → service.
23. **Q:** Deep variable objects vs many flat variables?
**A.** One object groups related settings and makes module interfaces readable and extensible; many flat variables get unwieldy past ~10–15 and invite positional mistakes. Objects with defaults for optional fields, plus validation, is the modern pattern.
24. **Q:** Outputs everywhere vs minimal interface?
**A.** Output only what consumers need; every output is a contract you must maintain (and a potential secret leak). Minimal, documented interfaces age far better.
25. **Q:** Do logic in Terraform (`for`/`count`/functions) or push it to the module/automation?
**A.** Keep it readable: conditionals for genuinely simple cases, but move complex logic into a module (typed inputs) or generate config from a higher-level tool/language. Terraform DSLs become unmaintainable fast — 200-line local expressions are a red flag in review.
26. **Q:** Sensitive vs non-sensitive variable handling for secrets the app needs?
**A.** Best: Terraform creates the placeholder/secret reference (e.g. an SSM parameter name or Key Vault secret URI) and the app resolves it with its own identity at runtime — no secret in state at all. Only fall back to passing values through Terraform when there's no other path.

**🎯 Senior**
27. **Q:** What makes a module interface good?
**A.** Typed inputs with sensible defaults and validation, a small number of well-named variables that describe intent (not implementation), outputs that expose only what callers need, no hidden provider/config assumptions, no environment branching inside the module, and examples + tests. The module should be boring and predictable — cleverness is a maintenance liability.

**🎯 Senior signal:** "typed objects with validation instead of flat variables", "no secrets in state if you can avoid it", and "modules are versioned APIs". Those three are the marks of someone who has maintained modules for other teams.

---

## 5. Modules — `modules.md`

**⚡ Rapid**
1. **Q:** What is a module?
**A.** A reusable container of resources with defined inputs/outputs, called from a root module (or other modules). It's the unit of encapsulation and reuse in Terraform.
2. **Q:** Root module vs child module?
**A.** The root is the working directory you run Terraform in; child modules are called via `module` blocks. State always belongs to the root — child modules don't have their own state.
3. **Q:** How do you source modules?
**A.** Local paths (`./modules/vpc`), the public registry, a Git repo with a ref (`?ref=v1.2.0`), or a private registry. Version pinning is mandatory for anything shared — an unpinned Git ref is a time bomb.
4. **Q:** What's the difference between a module and a resource?
**A.** A resource maps to one API object; a module expresses a *capability* (a VPC with subnets, routes, and flow logs) with a stable interface. Modules should own a coherent unit of infrastructure.
5. **Q:** How do you version modules?
**A.** Semver Git tags or registry versions (`~> 1.2` to allow patches), with breaking changes only in major versions. Release notes + examples are part of the deliverable.
6. **Q:** When should something *not* be a module?
**A.** When it's a single resource with no meaningful composition, when the interface would be as complex as the resources, or when every caller passes different flags (a config-in-a-module anti-pattern). Wrapping one resource for its own sake adds indirection without value.
7. **Q:** How do you document a module?
**A.** A README with description, inputs (name/type/default/description), outputs, and an example call — ideally auto-generated (`terraform-docs`) in CI so it can't go stale. Examples double as tests.

**🔍 Deep dive**
8. **Q:** Design a module library for a platform team serving 20 app teams.
**A.** Three layers: (1) primitives/network/data modules owned by the platform team with strong opinions and validation; (2) composition modules (e.g. "web-service": ALB + ASG + IAM + alarms + logs) that encode the organisation's standards; (3) thin app roots per environment that call composition modules with a small, typed input object. Enforce with CI (fmt/validate/tflint/checkov/`terraform test`), publish versions with docs, require `CODEOWNERS` review for module changes, and deprecate with migration guides.
**↳ Follow-up:** "How do you stop teams forking modules instead of improving them?"
**A.** Make the module easy to adopt (good defaults, examples, fast support), publish changelogs, allow a documented "escape hatch" input rather than forks, and treat fork detection as a signal that the interface is wrong. Also consider a policy that production resources must come from approved modules.
9. **Q:** How do you handle a module that must create resources in multiple AWS accounts/regions?
**A.** Pass aliased providers explicitly (`providers = { aws = aws.us_east_1 }`) and document the required configuration; alternatively split into separate modules/roots per account. A module that silently assumes the default provider is a landmine in cross-account setups.
10. **Q:** How do you refactor module boundaries without destroying resources?
**A.** `moved` blocks (declarative, PR-reviewable) to re-address resources between module paths, plus `state mv` for one-off moves; keep the resource's `address` change-only so Terraform sees a rename, not a replacement. Always verify with a plan showing zero destroy/create. Test on non-production first.
11. **Q:** What's the difference between `module` `for_each` and calling a module N times?
**A.** `for_each` on a module creates N instances keyed by a stable key (good for many similar environments/tenants); repeated explicit calls are clearer for a handful of genuinely different cases. Use `for_each`, not `count`, so removals don't cascade.
12. **Q:** How do you test modules properly?
**A.** `terraform validate`/`fmt`/tflint in CI, `terraform test` (native) or Terratest for real apply/destroy into a sandbox account, policy tests on the plan (checkov/OPA), and example roots that are applied in CI on a schedule. Contract tests catch interface breaks before consumers do.
13. **Q:** How do you deprecate a module or a variable?
**A.** Add the new path alongside the old (dual support with a deprecation warning variable/output), document the migration steps and timeline, track consumers (registry/Git searches/code grep in CI), and only remove after the announced window. Surprise removals break trust in the library.
14. **Q:** What are module anti-patterns you've seen?
**A.** Wrapping one resource; passing 40 variables; environment conditionals inside modules; provider configuration inside modules; hidden `depends_on` between modules; hardcoding account IDs/regions; and "god modules" that provision an entire environment (untestable, huge blast radius). Each one is worth mentioning with the consequence.
15. **Q:** How do you handle modules that need data from other modules/roots?
**A.** Pass values as inputs from the root (explicit) or read from a narrow shared source (SSM parameters, data sources) — never reach into another root's state directly from a module. Keep the data flow one-directional (platform → app).

**🚨 War room**
16. **Q:** A module update replaced production resources unexpectedly.
**A.** Roll back the module version first (pin back to the last known good tag and re-apply) to restore service, preserving the plan/logs for review; then determine why (a changed attribute forcing recreation, a changed default, or a new resource address), add an integration test covering that resource, and require plan diffs in the module's own CI before release. Pinning + a plan review is the preventive control.
17. **Q:** Two teams need different behaviour from the same module, and one is asking for a fork.
**A.** Understand the requirement: if it's a legitimate variation, add an explicit, documented input (feature module) rather than a boolean flag soup; if it's genuinely different infrastructure, split the module. Then communicate the change to all consumers with a version bump — forking should be the last resort and needs a maintenance owner.
18. **Q:** A module call fails with "Unsupported argument" after an upgrade.
**A.** The module's interface changed (removed/renamed variable). Check the changelog, update the call, and if it's a breaking change that wasn't semver-tagged, fix the release process (enforce conventional commits/semver in CI). Remove the temptation to "just pin to an old commit" as a long-term answer.
19. **Q:** All 20 roots use an unpinned Git ref to a shared module and someone pushed a breaking change.
**A.** Break-glass: pin every root to the last known good commit immediately as a hotfix, restore service, then move to tagged versions with a controlled upgrade plan. Post-incident: enforce tag-only refs (a CI check that fails on branch/sha refs) and protect the module's default branch.
20. **Q:** A module creates IAM roles with a wildcard policy and it slipped through review.
**A.** Fix the module and roll out a new version; audit whether the wildcard was ever used/abused (CloudTrail), then add automated policy checks (checkov/tflint rules/OPA) to the module's CI so a wildcard cannot be merged. Code review alone clearly isn't the control — say that.
21. **Q:** Consumers are on five different module versions and the support burden is exploding.
**A.** Publish a supported-version policy (e.g. support current major and previous minor), add CI in each consumer repo that reports the module version used, run a coordinated upgrade programme with migration guides and office hours, and consider a monorepo/registry that surfaces drift. Then automate the upgrade (Renovate-style PRs opening version bumps with plan diffs).

**⚖️ Trade-off**
22. **Q:** Local modules in the same repo vs a separate module repo/registry?
**A.** Same repo is simpler and atomic (change the module and its consumers in one PR) but couples every consumer's pipeline to the whole repo; a separate versioned repo/registry gives independent consumption and clean versioning but adds release overhead. Small teams/single platform: monorepo. Multi-team with independent release cadence: separate registry.
23. **Q:** Thin wrapper modules vs rich composition modules?
**A.** Thin wrappers give little value and add indirection; rich composition modules encode standards (security defaults, tagging, alarms) and are where the platform team's leverage is. Aim for "one module = one opinionated capability with good defaults and escape hatches".
24. **Q:** Opinionated modules (few inputs) vs flexible (many inputs)?
**A.** Opinionated modules are easier and safer (more secure by default, less to get wrong) but can block legitimate needs; flexible ones transfer complexity to consumers. Start opinionated with documented escape hatches, and only generalise when real requirements appear — otherwise you design for imaginary use cases.
25. **Q:** Registry vs Git refs vs private registry?
**A.** Git tags work fine for many teams (no infra) but lack discoverability/version listing; the public registry is for public modules; a private registry gives a catalogue, semantic versioning discovery, and policy hooks at the cost of running it (or paying for Terraform Cloud/Enterprise). Choose by team count and governance needs.
26. **Q:** Should modules create monitoring/alarms by default?
**A.** Yes for composition modules — health, error rate, and backup/compliance defaults should come with the capability, because teams skip them otherwise. Expose thresholds as inputs with sane defaults; "secure and observable by default" is the point of the platform layer.
27. **Q:** Who owns a shared module — platform team or consumers?
**A.** The platform team owns the interface and releases; consumers contribute via PRs and feedback. Ownership must be explicit (`CODEOWNERS`) or modules rot and no one is accountable for breaking changes.

**🎯 Senior**
28. **Q:** How do you measure whether your module library is working?
**A.** Adoption (% of production resources created from approved modules), version currency (how many consumers lag behind), change-failure rate on module releases, time-to-onboard a new service, and the ratio of module-mediated changes to bespoke ones. If teams still hand-roll infrastructure, the library isn't solving their problem — that's the finding, not a compliance failure.

**🎯 Senior signal:** "modules are versioned APIs with tests and deprecation policy", `moved` blocks for refactoring, and treating forks/version sprawl as design feedback. That's platform engineering maturity.

---

## 6. Workspaces & Environments — `workspaces-environments.md`

**⚡ Rapid**
1. **Q:** What is a Terraform workspace?
**A.** A named instance of a configuration sharing the same code but with separate state (e.g. `terraform workspace select prod`). It's *not* an environment by itself — it's state isolation within one config.
2. **Q:** When are workspaces appropriate?
**A.** Lightweight, structurally identical variations (feature branches, ephemeral test stacks, a handful of similar tenants) with the same providers and permissions. Not for prod/non-prod separation when credentials or topology differ.
3. **Q:** Why is `terraform.workspace` in resource names a trap?
**A.** Renaming/renumbering workspaces recreates resources, and `default` is an implicit workspace everyone forgets. Use explicit variables for naming rather than magic workspace names.
4. **Q:** What's the standard alternative for environments?
**A.** Separate directories/roots per environment sharing the same modules, each with its own backend key and tfvars — explicit, reviewable, and isolated (credentials, approvals, and state all differ naturally).
5. **Q:** How do environments share code without duplication?
**A.** Modules (versioned) + thin roots per environment + per-environment tfvars; or a single root used with different `-var-file`s per environment when the topology is identical (a common pragmatic middle ground).
6. **Q:** Where do environment-specific values live?
**A.** In the environment's tfvars/parameter files (in Git, reviewed), not in conditionals inside modules. Runtime secrets come from the secrets manager, not the repo.
7. **Q:** How do you promote a change from dev to prod?
**A.** The same commit/module version is applied through each environment in order; only the environment's tfvars differ. Promotion = merging/approving, not rewriting config. Any manual "make prod look like staging" step breaks the model.
8. **Q:** Can workspaces share state between environments?
**A.** No — each workspace has its own state, which is the point. Sharing data happens via outputs/parameters, and prod should never read from dev's state.

**🔍 Deep dive**
9. **Q:** Design environment strategy for a regulated company: dev, test, staging, prod, plus ephemeral PR environments.
**A.** Separate AWS accounts per environment (blast radius + IAM boundary), separate roots with their own state keys and CI pipelines, identical topology driven by one module set with environment tfvars, strict promotion order with approvals for prod, ephemeral environments created/destroyed per PR by a pipeline using a workspace *or* a dynamically named root (namespaced state key + auto-destroy), and a policy that prevents prod credentials from ever being used in a non-prod pipeline. Secrets come from each account's own secrets manager.
**↳ Follow-up:** "How do you prevent a staging pipeline from touching prod?"
**A.** Different accounts with different roles (no cross-account assumption into prod), different state backends, and a CI guard that validates the target account/role against the environment before applying — plus an alert if a non-prod pipeline ever attempts prod API calls. Technical separation beats naming conventions.
10. **Q:** How do you do per-developer/per-branch environments without exploding cost or drift?
**A.** Create on PR with a deterministic name from the branch, tag every resource with the owner and expiry, auto-destroy on merge/close plus a nightly reaper for orphans, cap the resource shapes (small instance classes), and use separate namespaces/state keys so nothing collides with shared environments. Cost control is part of the design, not an afterthought.
11. **Q:** How do you handle long-lived vs ephemeral environments in the same repo?
**A.** Same modules, different roots: persistent envs (dev/staging/prod) with protected pipelines and approvals; ephemeral envs generated by a template root with an auto-destroy policy. Keep the ephemeral root deliberately thin (only what's needed to test) so it's cheap and fast.
12. **Q:** What's the trade-off with Terraform Cloud workspaces / managed platforms?
**A.** A managed platform gives you state hosting, locks, remote runs, policy, and approvals plus environment-like workspace concepts with VCS-driven runs; you trade money and vendor dependency for less DIY plumbing. Many teams use it precisely to avoid building workspace/state/approval infrastructure.
13. **Q:** How do you handle environment-specific resource counts/topology?
**A.** Model it as data (e.g. `az_count`, `instance_class`, `enable_dr`) with validation, rather than `if env == "prod"` branching throughout. Where topology genuinely differs (prod has a DR region, dev doesn't), split the differing parts into an optional module call gated by a feature input (with a documented reason).
14. **Q:** How do you keep environments from drifting?
**A.** One module set with version pinning per environment, automated drift detection (scheduled plans) per environment, an upgrade programme so all environments catch up (avoid "prod is 3 versions behind the module"), and a rule that all changes flow dev → staging → prod through the same pipeline.
15. **Q:** What about shared services (networking, DNS, IAM) across environments?
**A.** Provision them once in a platform/shared account/root and consume via outputs/parameters (or peering/PrivateLink for network paths); never duplicate shared services per environment (drift and cost) and never let environments manage each other's resources. Make ownership explicit in the repo layout.

**🚨 War room**
16. **Q:** Someone ran `terraform apply` in the `default` workspace against production state.
**A.** Stop and assess what changed (state list/diff, CloudTrail), restore/roll back the changes, and then remove the ambiguity: rename or protect the default workspace (or don't use workspaces for environments at all), require `-var-file` and an explicit environment variable in the pipeline, and have CI refuse to run against `default` in a prod backend. Ambiguous defaults are the root cause.
17. **Q:** A merge to main applied to prod automatically and broke it.
**A.** Roll back (revert the commit + apply, or restore from the previous known-good state) to restore service, then fix the pipeline: prod applies require an environment approval/manual gate, the plan is reviewed for destructive changes, and progressive rollout/smoke tests run after apply. Continuous *plan* on main is good; continuous *apply* to prod without a gate is a choice you should defend or remove.
18. **Q:** Staging and prod use different module versions and a fix works in staging but not prod.
**A.** Align versions (upgrade prod to the tested version, or backport the fix to the pinned version), then change the process so module versions are promoted together through the environments — a version matrix per environment in CI helps expose this. Version drift between environments is a silent source of "it works in staging".
19. **Q:** An ephemeral PR environment wasn't destroyed and has been running for 3 months.
**A.** Destroy it (after confirming no one needs it), then fix: an auto-destroy job keyed to the branch/PR state, an owner+expiry tag with a nightly reaper that alerts before deleting, and a budget alert for the ephemeral account/scope. Also make the "how to destroy" path as easy as creation.
20. **Q:** A developer's local `terraform apply` used their personal admin credentials in staging.
**A.** Assess what changed, then remove the ability: no human write roles in shared accounts (SSO read-only + pipeline roles), short-lived CI credentials, and (best) pipeline-only applies for anything shared. Local applies with personal admin credentials make the audit trail useless — say that in the retro.
21. **Q:** Environment promotion applied prod before staging passed its tests.
**A.** Add a dependency between pipeline stages (staging must succeed and pass smoke tests before prod's approval becomes available), enforce with environment checks/approvals, and record the gate result in the deployment record. The lesson: promotion order is enforced by the pipeline, not by documentation.

**⚖️ Trade-off**
22. **Q:** Workspaces vs directories — settle it.
**A.** Directories (separate roots) for environments: explicit credentials/backends, independent pipelines, no magic workspace names, and prod can't be touched by accident; workspaces for ephemeral/structural duplicates. If you can't articulate why a workspace is the right tool, use a directory.
23. **Q:** One account with many environments vs an account per environment?
**A.** Account per environment is the strong isolation (IAM, quotas, guardrails, blast radius) and the standard in regulated orgs; single-account multi-environment is cheaper/simpler but relies on naming and policy discipline alone. Cost of the extra accounts is small compared to the risk reduction.
24. **Q:** Identical topology per environment vs different shapes?
**A.** Identical topology (same modules, different sizes) is the maintainable ideal — the path to production is proven in lower environments. Deviations should be explicit, justified in code with a feature input, and reviewed; "prod is special" undocumented is how outages happen.
25. **Q:** Ephemeral environments for every PR vs a shared integration environment?
**A.** Ephemeral gives isolation and no contention but costs money and pipeline time (and needs aggressive cleanup); a shared integration environment is cheaper but creates queueing and interference. Use ephemeral for the services that need real infrastructure validation, shared for the rest.
26. **Q:** Should non-prod mirror production exactly?
**A.** As much as affordable — same modules, same IAM patterns, same monitoring (at lower retention/scale), same deployment path. Full mirroring is expensive; the point is that *differences are deliberate* so staging findings transfer to prod.
27. **Q:** Terraform Cloud workspaces vs your own CI + S3 backend?
**A.** TFC: state, locking, policy (Sentinel/OPA), VCS integration, approvals, and audit out of the box — costs money and adds a dependency. DIY: full control and lower cost, more engineering. Decide on team size, security requirements (state access, policy), and how much platform engineering you can staff.

**🎯 Senior**
28. **Q:** What's your environment strategy in one paragraph?
**A.** One module library, thin per-environment roots in separate accounts with separate backends and pipelines, environment differences expressed only as reviewed tfvars data, promotion by the same pipeline with staged approvals from dev → staging → prod, ephemeral environments auto-created and auto-destroyed per PR, drift detection and version-currency reporting per environment, and no human write access to shared environments outside the pipeline. Production is not a special case in code — it's a stricter gate in the process.

**🎯 Senior signal:** "workspaces are state isolation, not environments", promotion by the same commit through the same pipeline, and account-level isolation over naming conventions. Those are the marks of someone who has run multi-environment infrastructure.

---

## 7. CI/CD for Terraform — `ci-cd.md`

**⚡ Rapid**
1. **Q:** What does a Terraform pipeline actually do?
**A.** On PR: `fmt`/`validate`/lint/security scan → `plan` against the target environment → post the plan for review → approval → apply *the saved plan file* → post-apply smoke tests. The plan artifact is the contract; applying a fresh plan means you didn't review what ran.
2. **Q:** How do you authenticate Terraform in CI to AWS?
**A.** OIDC federation from GitHub Actions/GitLab/ADO to an IAM role (`AssumeRoleWithWebIdentity`) with a trust policy scoped to the repo/branch/environment — no static keys. Short-lived credentials are the non-negotiable part.
3. **Q:** Where does state live in CI?
**A.** The remote backend configured per environment (S3 + DynamoDB locking), with the CI role holding the only write permission. No state ever lives in the pipeline workspace or the repo.
4. **Q:** How do you gate production?
**A.** An environment with required approvals (GitHub environments/ADO environments), plus policy checks on the plan (destructive-change detection), business-hours restrictions, and a change record. The gate must exist in the pipeline, not in a wiki.
5. **Q:** How do you handle multiple roots in one repo?
**A.** A matrix/path-filtered pipeline (change detection by directory), one job per root per environment, with shared steps (init/validate/scan) and independent state/approvals per root. Only plan/apply what changed to keep it fast — but always plan the whole env before promoting.
6. **Q:** What secrets does a Terraform pipeline need?
**A.** Almost none: cloud auth via OIDC, provider credentials short-lived, and any sensitive input injected from the cloud secrets manager rather than CI variables. A pipeline holding long-lived cloud keys is a finding.
7. **Q:** What do you scan for in CI?
**A.** IaC security (Checkov/tfsec/Trivy config), policy-as-code on the plan (OPA/Conftest/Sentinel: no public buckets, encryption required, no `0.0.0.0/0` admin ports, approved modules only), secret scanning (gitleaks), and formatting/validation. Scans that gate the merge, not the deploy, are what actually change behaviour.
8. **Q:** How do you detect drift in CI?
**A.** A scheduled (e.g. nightly) read-only plan per root posting results to Slack/a dashboard, plus alerts on non-empty plans. Automate the "file a ticket"/"open a PR" step so drift becomes work, not noise.

**🔍 Deep dive**
9. **Q:** Design the pipeline for a platform with 3 environments, 2 AWS accounts, and 15 roots.
**A.** Repo layout (`modules/`, `envs/{dev,staging,prod}/<root>/`), OIDC roles per account/environment with least privilege (plan roles read-only + state read; apply roles scoped to the resources they manage), path-filtered workflows with a matrix over changed roots, stages: lint → validate → security scan → plan (saved artifact, posted to PR/Slack) → policy evaluation → approval (prod only) → apply of the saved plan → smoke test → notify. Concurrency controls so only one apply per state runs at a time, state locking verified, and deployment records (who/what/when/plan link) retained for audit.
**↳ Follow-up:** "How do you stop a plan from being applied against different code?"
**A.** Generate the plan in the same job/commit that applies it, pass the artifact between stages (plan file + lockfile + config), and verify the commit SHA before apply; if the branch has moved, re-plan. Many teams apply in the same job after approval to avoid artifact drift.
10. **Q:** How do you handle a plan that contains destructive changes?
**A.** Automated detection (grep/parse plan JSON for `delete`/`replace` on protected resource types) → block or require explicit high-level approval with a justification comment; require the reviewer to acknowledge the destroy count and target. Add `prevent_destroy` at the resource level for anything that must never be deleted — automation should not be the only guard.
11. **Q:** How do you promote the exact same change across environments?
**A.** Same commit, same module versions, environment-specific tfvars; the pipeline applies dev → staging → prod in order with approvals, so the artifact under test is identical and only the inputs differ. Any hotfix goes through the same path (with an expedited approval) rather than a manual console change.
12. **Q:** How do you make Terraform CI fast?
**A.** Path filtering (only affected roots), provider/module caching (`~/.terraform.d`, plugin cache), `-refresh=false` for PR plans where safe (with a nightly full refresh), parallelism tuning, separate validate/lint jobs, and smaller roots (splitting state improves plan time more than any flag).
13. **Q:** How do you handle credentials/permissions errors in CI?
**A.** Verify the OIDC trust policy claims (repo, branch, environment), the role's permissions on the resources being changed, and any SCP/permissions boundary; remember state-backend access is separate from resource access. Make the role's policy explicit in code (it's IaC too) so failures are debuggable.
14. **Q:** What's your rollback strategy for a bad Terraform apply?
**A.** Revert the commit and apply the previous config (forward-fix by reverting), or restore from a known-good state version + apply; for resources Terraform can't restore (data), rely on service-level backups (DB PITR, snapshot restore). `terraform destroy` is not a rollback. Have the runbook and rehearse it once.
15. **Q:** How do you audit what Terraform did and who approved it?
**A.** Pipeline records (commit, actor, plan artifact, approval identity/timestamp, apply log) retained for compliance, plus CloudTrail events for the assumed role and resource changes; correlate the apply log with CloudTrail by time and role. Regulated environments often require the plan artifact itself be archived.

**🚨 War room**
16. **Q:** The nightly drift job reports 40 changes in production. Triage.
**A.** Classify: expected (autoscaling, service-managed attributes → `ignore_changes`), manual hotfixes (codify or revert, and track who did it via CloudTrail), or unauthorised (security incident). Then fix the mechanism: restrict human write access, add the missing `ignore_changes`, and get the drift count back to zero-baseline so the job's signal is meaningful again.
17. **Q:** CI applied to the wrong account because a variable was misconfigured.
**A.** Assess and revert the changes; then make the target unambiguous: derive the account from the backend/role (not a free-form variable), add a pre-apply assertion comparing the caller identity to the expected account ID (`aws sts get-caller-identity` check in the pipeline), and require environment protection on prod. This specific failure is common and fully preventable by an assertion.
18. **Q:** The pipeline is applying while someone runs a local apply. How do you stop this class of problem?
**A.** Remove human write credentials for the environment (read-only SSO + pipeline-only apply), enforce locking, and add a CI guard that detects concurrent modifications (lock errors are the signal). Long-term: a managed runner with queued runs per environment is the cleanest control.
19. **Q:** A required provider/module can't be downloaded in CI (registry outage).
**A.** Mitigate immediately by restoring from the provider plugin cache/artifacts (the lockfile plus a pre-populated cache in the runner image), or temporarily point at a vendored mirror; then treat the dependency as a supply-chain risk: cache providers in your own registry/mirror, pin versions, and commit the lockfile. Public registry availability is not something you control — plan for it.
20. **Q:** A secret leaked in CI logs during apply.
**A.** Rotate the secret immediately, restrict log access, and mark outputs/variables `sensitive`; better, remove the secret from Terraform's scope entirely (the app reads it from the secrets manager at runtime). Add a log-redaction/pre-commit check — but note that `sensitive` only redacts CLI output, not state, so state access control is still required.
21. **Q:** Approvals were given by the same person who authored the change.
**A.** Fix the policy (author ≠ approver, enforced by the platform's approval configuration where supported) and audit recent production changes for self-approvals. Then decide whether the control needs to be stronger (separate prod approver group, two-person rule for destructive plans) — reviewers hear this as whether you understand why the control exists.

**⚖️ Trade-off**
22. **Q:** Plan on PR + apply after merge vs applied in the same run?
**A.** PR-planned/merge-applied gives reviewable, auditable (and often required) approval flows but the plan can go stale between approval and apply (the code may have moved) — mitigate by verifying the commit SHA or re-planning. Same-run apply of a reviewed plan artifact is tighter technically; the choice usually comes down to governance requirements.
23. **Q:** Monolithic pipeline vs per-root pipelines?
**A.** Monolithic is simpler to reason about but serialises everyone and makes blast radius bigger; per-root pipelines parallelise teams and isolate failures but need consistent templates and shared tooling. Use reusable workflow templates so "per-root" doesn't mean "per-root drift".
24. **Q:** Managed runner (Terraform Cloud/Atlantis/Spacelift) vs your own CI?
**A.** Managed gives locking, policy, approvals, and state out of the box, with a cost and another dependency; DIY gives control and lower cost but you build and maintain the machinery. The decision often comes down to team size and how much governance you need.
25. **Q:** Auto-apply on merge for non-prod vs manual gates everywhere?
**A.** Auto-apply for dev/test speeds up feedback and reduces toil; staging/prod should be gated by approval and (ideally) smoke tests plus progressive rollout. Gating dev doesn't add safety, only friction.
26. **Q:** Policy-as-code at PR time vs on the plan?
**A.** PR-time (config scanning) is fast and catches obvious issues but can't see resolved values/plan effects; plan-time policy sees the actual changes (the real guardrail: "this plan creates a public bucket") but requires a plan and a target account. Mature shops run both: config scan for fast feedback, plan policy as the enforcement gate.
27. **Q:** Should Terraform manage the pipeline's own IAM roles?
**A.** Ideally yes for consistency and least privilege (roles, policies, and OIDC trust as code in a bootstrap/platform root), but keep a documented break-glass path so a bad apply can't lock you out of your own pipeline. Bootstrap (state bucket + CI roles) is the one thing that must be applied manually/out-of-band — and documented.

**🎯 Senior**
28. **Q:** What makes a Terraform pipeline production-grade?
**A.** OIDC-based short-lived credentials with least privilege per environment; fmt/validate/lint/security/secret scanning as merge gates; plan artifacts posted to PR/Slack with policy evaluation; destructive-change detection with explicit approval; apply of the reviewed plan artifact with concurrency control and verified commit SHA; smoke tests post-apply; deployment records retained for audit; drift detection on a schedule; and a rehearsed rollback runbook. Everything above lives in the repo, versioned, and reviewed like code.

**🎯 Senior signal:** "apply the plan you reviewed, not a fresh one", "assert the target account before apply", and "providers/modules are a supply-chain dependency — cache and pin them". Those three are where senior DevOps answers land.
