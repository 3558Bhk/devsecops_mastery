# RTIQ — Terraform Core on Azure (Real-Time Interview Questions)

> **Cloud:** Azure · **Tool:** Terraform · **Domain:** Basics, azurerm provider, state, variables, modules, workspaces, Azure DevOps CI/CD · **Target roles:** SDE-3 · Cloud Engineer · DevOps · DevSecOps · SRE · Platform Engineer · **Reading time:** ~34 min

**How this file is used live:** Azure-focused Terraform rounds blend HCL questions with Azure-specific mechanics — the `features {}` block, subscription/provider aliases, remote state in Azure Storage, `azurerm` resource IDs, and Azure DevOps pipeline plumbing. Expect to be asked how you'd structure a landing-zone deployment and how you'd recover from a half-applied state.

**Legend:** ⚡ Rapid · 🔍 Deep dive · 🚨 War room · ⚖️ Trade-off · 🎯 Senior signal

---

## 1. Terraform Basics — `terraform-basics.md`

**⚡ Rapid**
1. **Q:** What does Terraform do, and how does it differ from ARM/Bicep on Azure?
**A.** Declarative desired-state provisioning that records real resources in state and computes a plan; Bicep/ARM is Azure-only and deployment-scoped (no state file — ARM tracks deployments). Terraform gives multi-cloud and an explicit state lifecycle; Bicep gives simpler native integration and no state to manage.
2. **Q:** Walk me through the core workflow.
**A.** `terraform init` (providers, modules, backend) → `validate`/`fmt` → `plan` (refresh + diff) → review → `apply` → `destroy` when retiring. In CI, plan is an artifact and apply uses that artifact.
3. **Q:** What is state, and why does it exist in Terraform?
**A.** A mapping of config resources to real Azure resource IDs plus attributes and dependencies; Terraform needs it to plan, detect drift, and destroy correctly. Without state, Terraform can't know what it manages.
4. **Q:** Where should Azure state live?
**A.** An Azure Storage account (blob container) configured as the `azurerm` backend, with versioning, soft delete, private endpoint or firewall, and a **state lock file** (Terraform's native blob leasing) — plus RBAC restricting access to the pipeline identities. State contains secrets, so treat it as sensitive data.
5. **Q:** What is the `subscription_id`/tenant pattern in azurerm?
**A.** `provider "azurerm" { features {} }` plus `subscription_id`/`tenant_id` (via variables or env/`ARM_*`), and aliased providers per subscription/tenant for multi-subscription deployments. Never hardcode IDs — parameterise per environment.
6. **Q:** How do you keep secrets out of Terraform on Azure?
**A.** Reference Key Vault (`data "azurerm_key_vault_secret"` or managed identity at runtime), use `sensitive = true` on variables/outputs, and prefer identity-based flows (Key Vault references, managed identity) where the value never enters state. State exposure is still a risk — protect the backend.
7. **Q:** What are resource IDs and why do they matter?
**A.** Azure IDs are long, case-sensitive-ish paths (`/subscriptions/.../resourceGroups/.../providers/Microsoft.X/...`); Terraform uses them as the state key and for cross-resource references. Changing to a different resource group/subscription path can force recreation — read the plan.
8. **Q:** How do you handle dependencies in Azure resources?
**A.** References create implicit dependencies (`resource_group_name = azurerm_resource_group.rg.name`), `depends_on` for cases without a data dependency (e.g. a private endpoint that must exist before an app starts), and `module` outputs for cross-module ordering.

**🔍 Deep dive**
9. **Q:** Structure a repo for a 3-environment Azure landing zone with 4 workload teams.
**A.** `landing-zone/` roots (management groups, policy, hub networking, logging) owned by the platform team; `platform/` roots (shared Key Vault, ACR, DNS zones, private endpoints); workload roots per team/environment that consume modules and read platform outputs via data sources/remote state (or a shared `terraform_remote_state`/outputs in Key Vault-adjacent storage); backend per root with its own state blob and pipeline; consistent naming/tagging from a `naming` module; and CI with plan-on-PR/apply-on-merge plus policy gates (e.g. deny public IPs, require tags).
**↳ Follow-up:** "How do workload roots get the hub VNet/subnet IDs?"
**A.** Prefer published outputs: the platform root writes IDs to Key Vault/Storage/App Configuration (or the team's root reads them via `azurerm_subnet` data sources). `terraform_remote_state` works but couples roots and requires state read access — usually you don't want workload teams reading the platform state.
10. **Q:** How do you deal with Azure resource provider registration and API versions?
**A.** Register providers (`azurerm_resource_provider_registration`) as part of the platform bootstrap; be aware that `azurerm` pins API versions per resource internally, and provider upgrades can change behaviour/IDs. New features require provider upgrades — plan them like dependency changes.
11. **Q:** What are the Azure-specific gotchas in Terraform plans?
**A.** Long-running operations (plans/applies take minutes for AKS/App Gateway), eventual consistency (a resource exists but a follow-up read fails — `depends_on`/retries help), `name` uniqueness constraints (Key Vault/storage accounts are globally unique), and resources that need sequential creation (private endpoints + DNS zones before consumers). Say these; they're real operational pain.
12. **Q:** How do you import existing Azure resources?
**A.** `import` blocks (Terraform 1.5+) or `terraform import azurerm_... <resource_id>`, then align config so `plan` is empty; note that some Azure resources require specific ID formats (e.g. nested resources) and that imported resources often show differences in tags/settings. Do imports in a dedicated PR with a plan review.
13. **Q:** How do you use `moved` blocks when refactoring Azure resources?
**A.** Rename resources/module paths with `moved { from = ..., to = ... }` so Terraform re-addresses in state instead of destroying and recreating — critical for stateful resources (databases, storage, Key Vaults). Keep `moved` blocks for one release cycle, then remove after all environments have applied.
14. **Q:** How do you test Azure Terraform changes cheaply?
**A.** Per-PR plans (no apply) with a real subscription for validation, a dedicated sandbox subscription for apply tests, `terraform validate`/`fmt`/tflint/checkov in CI, and (for modules) `terraform test` or Terratest. For expensive resources (AKS/App Gateway), consider an ephemeral environment created/destroyed per PR.

**🚨 War room**
15. **Q:** An apply failed halfway through a landing-zone change. What do you do?
**A.** Read the error and determine what was created vs what exists (`terraform state list`, Azure portal/CLI), fix the root cause (quota, policy denial, name collision, RBAC), and re-run `plan` to converge the rest. Don't hand-edit state; if the failure was a policy/RBAC issue, that's a signal your pipeline identity is missing a permission or the environment has a guardrail you didn't account for.
16. **Q:** State is locked and no pipeline is running.
**A.** Confirm (check CI history, other operators), then break the lease (`terraform force-unlock <lock-id>`, or release the blob lease directly) and document why. Root-cause it if it recurs: a crashed runner, a killed job, or someone running Terraform locally against the shared backend.
17. **Q:** Someone changed a resource in the portal and now plans show unexpected diffs.
**A.** Decide: codify the change (update config/import) or revert it (apply). Then reduce future drift: read-only access for humans in production, Policy with deny effects for key settings, and alerts on activity-log changes outside the pipeline (e.g. a scheduled plan job reporting diffs).
18. **Q:** A plan wants to replace a Key Vault/storage account. Stop.
**A.** Find the forcing attribute (usually `name`/`location`/`resource_group_name` changes, or `prevent_destroy` being triggered). If replacement is unavoidable, plan a migration: create the new resource, copy data/secrets, update consumers, then remove the old one — never let a single apply destroy a data-bearing resource. Add `lifecycle { prevent_destroy = true }` to stateful resources.
19. **Q:** The pipeline applied to the wrong subscription.
**A.** Assess (what changed, in which subscription), revert from state/backup, then prevent: derive the subscription from the backend/role rather than a variable, assert `az account show`'s subscription in the pipeline before apply, and require environment approvals for production. Say "assert the target subscription" — that's the control.
20. **Q:** A provider upgrade broke several resources in one apply.
**A.** Halt further applies (pin back the previous provider version in `required_providers`/lockfile), assess damage, and fix forward or roll back per resource. Upgrade providers in a dedicated PR per environment with plan diffs reviewed — never bundled with functional changes.

**⚖️ Trade-off**
21. **Q:** Terraform vs Bicep on Azure?
**A.** Bicep: native, no state to manage, day-one support for new Azure features, first-class Azure DevOps integration, no drift between ARM and tooling. Terraform: multi-cloud, mature module ecosystem, an explicit state/plan workflow, and one tool across AWS/Azure. Choose by multi-cloud reality and team skills — then be consistent per platform rather than mixing per environment.
22. **Q:** Remote state in Azure Storage vs Terraform Cloud?
**A.** Azure Storage is cheap, native, and easy to lock down (private endpoint, RBAC); Terraform Cloud/workload-identity setups add managed runs, policy, and approvals at a cost and with a dependency. Many Azure shops stay in Storage + their existing CI.
23. **Q:** Monorepo vs repo-per-team for Terraform?
**A.** Monorepo gives atomic module+consumer changes and consistent CI but needs CODEOWNERS and path filters; repo-per-team gives ownership/isolation but version skew and duplicated pipeline setup. Common: shared module repo + environment roots per team.
24. **Q:** Plan-on-PR only vs continuous apply on merge?
**A.** Continuous apply (with approvals for prod) shortens lead time and reduces drift; plan-only gates are safer but slow and invite out-of-band changes. Mature teams apply automatically to dev/test and require an approval gate for prod, with rollback being a revert-and-apply.
25. **Q:** Terraform-managed or Azure Policy-managed guardrails?
**A.** Both: Policy enforces *what must be true* (deny public IPs, require tags/encryption, allowed locations) even for out-of-band changes; Terraform defines the resources. Policy is the backstop for what Terraform (or a human) gets wrong — don't rely on code review alone.
26. **Q:** Should Terraform manage the landing zone, or should it be a one-time Azure-native deployment (portal/Blueprints/Bicep)?
**A.** Manage it with Terraform (or Bicep) so it's versioned and reproducible — but treat it as a distinct root/lifecycle with its own approvals, because a mistake there affects every workload. "Landing zone as code" is the expected answer; portal click-ops is an audit finding.

**🎯 Senior**
27. **Q:** What does mature Azure Terraform practice look like to you?
**A.** Landing-zone and platform roots owned by the platform team with their own pipelines; per-team/environment workload roots using versioned modules; remote state in Azure Storage with locking, versioning, RBAC, and private access; provider versions pinned with the lockfile committed; OIDC/workload-identity federation for pipelines (no stored credentials); plan-on-PR with policy gates, approvals for prod, and apply of the reviewed plan; drift detection jobs; naming/tagging standards enforced by modules and validated by Policy; and documented runbooks for the classic failures (stuck lock, half-applied, accidental destroy, wrong subscription).

**🎯 Senior signal:** "assert the target subscription before apply", "state contains secrets, so protect the backend", and treating the landing zone as a separate high-risk lifecycle. Those three mark real Azure Terraform ownership.

---

## 2. Providers — `providers.md`

**⚡ Rapid**
1. **Q:** What must every `azurerm` provider block have?
**A.** The `features {}` block (required, even empty), plus credentials/subscription configuration. Forgetting `features {}` is the classic first error for newcomers.
2. **Q:** How do you authenticate the azurerm provider?
**A.** In pipelines: workload identity federation/OIDC (service principal with federated credentials) or a managed identity on the runner — no client secrets. Locally: `az login` (CLI auth) or `ARM_*` environment variables for a service principal. Static client secrets are the legacy path you should be replacing.
3. **Q:** How do you work across multiple subscriptions?
**A.** `provider "azurerm" { alias = "prod" ... }` blocks per subscription, with `providers = { azurerm = azurerm.prod }` when calling modules. Explicit aliases beat implicit defaults — the default provider should be the environment you're deploying to, and nothing else.
4. **Q:** Which other providers do Azure stacks commonly need?
**A.** `azurerm` (resources), `azuread` (Entra ID apps/groups/roles), `azapi` (resources/features not yet in azurerm, or ARM-property precision), `random` (unique suffixes), `time`/`null` occasionally, `helm`/`kubernetes` (AKS workloads), and `tls` (certificates).
5. **Q:** When would you use `azapi` instead of `azurerm`?
**A.** When a resource/property isn't supported yet in azurerm, when you need exact ARM API control (API version, nested properties), or to manage recently released features. Trade-off: less abstraction/validation, and its schema follows ARM rather than Terraform idioms.
6. **Q:** How do you pin provider versions?
**A.** `required_providers { azurerm = { source = "hashicorp/azurerm", version = "~> 4.0" } }` plus a committed `.terraform.lock.hcl` with hashes for all platforms used in CI. Floating versions in production is asking for a surprise plan.
7. **Q:** How does the azuread provider differ in scope?
**A.** It manages Entra ID objects (applications, service principals, groups, app role assignments) as opposed to Azure resources — with its own tenant-level permissions and a different (often slower/permission-sensitive) API surface. Keep Entra ID management in a dedicated root with tight RBAC.
8. **Q:** What is `client_id`/`object_id` confusion in azuread?
**A.** `application_id` (client ID) vs `object_id` (the service principal's directory object ID) — role assignments and some references need the object ID, while app configuration uses the client ID. Mixing them produces "principal not found" errors.

**🔍 Deep dive**
9. **Q:** Design provider configuration for a multi-tenant, multi-subscription Azure platform.
**A.** Central provider definitions in each root: for Terraform-driven landing zones, aliases per subscription (management/hub/workload) with `subscription_id` from variables/data sources; per-tenant aliases only where a genuine cross-tenant need exists (typically avoided); workload-identity auth so no secrets are stored; and OIDC/`ARM_*` only as a fallback. Modules receive providers explicitly rather than declaring their own — so callers control the target and nothing deploys "somewhere else" by accident.
**↳ Follow-up:** "How do you prevent a module from deploying to the wrong subscription?"
**A.** Modules never declare provider blocks; roots pass aliases explicitly, CI asserts the subscription ID from `az account show` against the expected environment, and the pipeline's federated identity is scoped to specific subscriptions (so the wrong target fails authorisation rather than succeeding quietly). Also keep one root per environment so the target isn't a runtime variable at all.
10. **Q:** How do you handle provider upgrades on Azure?
**A.** Read the azurerm changelog for breaking changes (major versions often rename/remove arguments), upgrade in a dev root first with a plan review (watch for replacements), pin/roll forward per environment, and avoid bundling with functional changes. Keep the lockfile in version control and use `terraform init -upgrade` deliberately.
11. **Q:** How do you manage `features {}` variations across environments?
**A.** `features {}` controls global provider behaviours (e.g. resource group deletion prevention, Key Vault purge behaviour, virtual machine settings). Be explicit rather than relying on defaults — and document the non-defaults, because they change destroy behaviour (e.g. `purge_soft_delete_on_destroy` for Key Vault).
12. **Q:** How do you handle Azure API throttling in large deployments?
**A.** Reduce call volume (fewer/larger operations, `-parallelism` tuning), stagger applies by root, and use retries/backoff (azurerm builds in retries but can still be overwhelmed by huge single applies). Very large estates should split roots — throttling is a symptom of putting too much in one apply.
13. **Q:** What's the pattern for `azapi` in a mixed stack?
**A.** Use azurerm for the vast majority (better ergonomics/validation) and azapi for gaps or precise ARM control, keeping azapi usage in dedicated modules with documented reasons and pinned API versions. Isolate it so an azapi schema change doesn't ripple through the estate.
14. **Q:** How do you manage the Terraform provider's own prerequisites (resource providers, quotas)?
**A.** Register resource providers (`azurerm_resource_provider_registration`) in a bootstrap/platform root, request quota increases ahead of deployments (documented per region/SKU), and add preconditions/checks in the pipeline so failures are clear rather than cryptic. Quota surprises during an apply are a very common real-world Azure pain.

**🚨 War room**
15. **Q:** `init` fails with "Failed to query available provider packages" in CI.
**A.** Registry/network access blocked (private runners without egress to the Terraform registry), a missing provider cache, or a lockfile missing the CI platform's hashes. Fix by allowing egress to the registry (or mirroring providers internally), caching `~/.terraform.d`, and generating the lockfile with `terraform providers lock -platform=linux_amd64` (plus other platforms used).
16. **Q:** After a provider upgrade, resources show "inconsistent state" or unexpected diffs.
**A.** Check the changelog for that resource's schema change; often it's a new attribute Azure now returns or a renamed argument. Fix with a config change, `ignore_changes` where the platform manages the field, or pinning back if it's a provider bug — then roll out per environment.
17. **Q:** A provider-level setting (e.g. Key Vault purge protection behaviour) caused a destroy to fail or unexpectedly purge.
**A.** Review the `features {}` block — those flags change destroy semantics. Fix the configuration (e.g. set `purge_soft_delete_on_destroy = false`), restore protection on the resource, and audit whether anything was actually purged. Document provider feature flags in the repo README because they're invisible until they bite.
18. **Q:** The pipeline service principal lost a permission and half the plan fails.
**A.** Compare the failing resource types to the role assignments at the correct scope (subscription vs resource group vs resource-level), remembering that many Azure operations need a role at a parent scope (e.g. `Contributor` on the RG to create resources inside; role assignments need `User Access Administrator`/Owner). Fix the role, and record the required permission set in the platform docs.
19. **Q:** A new Azure feature isn't supported by the pinned azurerm version.
**A.** Upgrade the provider in a controlled PR (or temporarily use `azapi_resource` for that gap), then plan to consolidate once azurerm supports it. Don't stay on an ancient provider version to avoid upgrades — that accrues risk (and blocks security fixes).

**⚖️ Trade-off**
20. **Q:** azurerm vs azapi?
**A.** azurerm: idiomatic, validated, easier for teams, but lags new features. azapi: complete ARM coverage with precise control, but closer to the metal (less validation, more verbose, provider-schema churn). Default azurerm; use azapi surgically.
21. **Q:** azuread vs managing Entra ID outside Terraform (portal/Graph scripts)?
**A.** Entra ID in Terraform gives review/versioning and ties app registrations to infrastructure (federated credentials for CI, role assignments), but the azuread provider has known performance/permission quirks and some objects are better managed natively. Common split: apps/service principals/federated credentials in Terraform; users/groups from HR/Identity governance systems (not Terraform).
22. **Q:** Service principal with client secret vs workload identity federation vs managed identity?
**A.** Managed identity for Azure-hosted runners (no credentials at all); workload identity federation for external CI (GitHub/ADO/GitLab) — no stored secret and scoped by subject claim; client secret only as a legacy fallback with short expiry and rotation automation. Say the ranking explicitly; it's a DevSecOps signal.
23. **Q:** Pin provider versions tightly (`= 4.1.0`) vs loosely (`~> 4.0`)?
**A.** Tighter pins are reproducible but require deliberate upgrade PRs; looser ranges let patch/minor updates in (and can introduce behaviour changes silently). The lockfile is the real determinism mechanism — pin the range sensibly (`~>`), commit the lockfile, and upgrade via reviewed PRs.
24. **Q:** One provider config per root vs many aliases in one root?
**A.** Many aliases in one root create wide permissions and cross-subscription blast radius; one (or a few) per root with explicit aliases only where needed is safer. If you need cross-subscription resources, consider separate roots with published outputs instead of a single omnipotent provider set.
25. **Q:** Use the `azurerm` provider's built-in retries vs wrapping applies in retry logic?
**A.** Prefer the provider's retries and fix the root cause (throttling, eventual consistency, quota); retrying a whole apply masks issues and can create duplicates/partial states. Only retry at the pipeline level for genuinely transient errors, and log it.

**🎯 Senior**
26. **Q:** What's your provider/Auth standard for Azure pipelines?
**A.** Workload identity federation (or a runner managed identity) with least-privilege RBAC scoped per subscription/environment; no stored client secrets; providers declared only in roots with explicit aliases; `features {}` documented; `required_providers` pinned with a committed lockfile including all CI platforms; provider upgrades as separate reviewed PRs per environment; and a bootstrap root that registers resource providers and establishes the CI identities — applied out-of-band once and documented.

**🎯 Senior signal:** "assert the subscription, and scope the pipeline identity so the wrong target fails", the `features {}` destroy semantics, and azapi as a surgical escape hatch. Those three are Azure Terraform practitioner markers.

---

## 3. State Management — `state-management.md`

**⚡ Rapid**
1. **Q:** How is the Azure remote backend configured?
**A.** `backend "azurerm" { resource_group_name, storage_account_name, container_name, key }` (with `use_azuread_auth = true` to avoid storage keys) — state per root in a blob, with native blob-lease locking. Use a dedicated state storage account, not a workload one.
2. **Q:** What protects the state account?
**A.** Versioning + soft delete on blobs, encryption (CMK if required), RBAC limited to pipeline identities (`Storage Blob Data Contributor` on the specific container), and network restrictions — ideally a private endpoint (with the CI runner in the VNet or able to reach it) and no public access. Remember: `use_azuread_auth` requires the right data-plane role.
3. **Q:** Why does locking matter in Azure?
**A.** Terraform takes a blob lease; concurrent applies would interleave state writes and corrupt it. If a run dies, the lease can persist — hence `force-unlock` and the need to verify nothing else is running.
4. **Q:** What's in state that you must protect?
**A.** Secrets (SQL admin passwords, connection strings, keys), plus full resource attributes — everything Terraform set. Treat state as a secrets store: restrict read/write, log access, and prefer identity-based flows that never put values in state (Key Vault references, managed identity, `ignore_changes` on secrets managed elsewhere).
5. **Q:** How do you structure state keys?
**A.** One blob per root with a naming convention encoding environment/region/component (e.g. `prod/network/hub.tfstate`, `prod/apps/orders.tfstate`), so it's obvious what a state file covers and who owns it. Document the map in the repo.
6. **Q:** How do you move resources between states on Azure?
**A.** `terraform state mv` (or `moved` blocks) plus the matching config move, verified by empty plans in both roots. For cross-state moves with Azure resources, IDs must match exactly; do it in a change window with locks held by a single operator.
7. **Q:** How do you import an existing Azure resource?
**A.** `import` blocks (preferred, reviewable) or `terraform import azurerm_<type> <resource_id>` with matching config; some resources need composite IDs (e.g. nested resources, role assignments with GUIDs) — get the ID format right or the import fails.
8. **Q:** Can two roots share data?
**A.** Yes via `terraform_remote_state` (requires read access to the producer's state — often undesirable) or via published outputs (Key Vault/Storage/App Config, or `azurerm` data sources reading the real resource). Prefer data sources/published outputs to state coupling.

**🔍 Deep dive**
9. **Q:** Design state management for a 4-subscription Azure estate with 30 roots.
**A.** One dedicated state subscription/resource group (separate from workloads) holding a storage account per environment (or one with containers per environment), versioning + soft delete + CMK, private endpoint, and RBAC granting only the specific pipeline identities `Storage Blob Data Contributor` on their containers; one blob per root with an encoded key naming convention; `use_azuread_auth = true`; no human write access (read for break-glass via PIM with logging); scheduled drift-detection plans per root with alerts; and a documented break-glass runbook (force-unlock, restore a previous blob version, disaster recovery plan).
**↳ Follow-up:** "How do you recover if state is deleted?"
**A.** Restore the blob from versioning (or from soft-deleted blobs) and validate with `plan`; if truly lost, you must import every resource into a fresh state — a multi-day exercise, which is why versioning, soft delete, and a replicated backup of the state account are non-negotiable. Say the time cost out loud; it justifies the controls.
10. **Q:** How do you handle state for resources that must exist in multiple regions?
**A.** Separate roots/state per region (or per region+component) so a regional failure or change doesn't couple regions, with shared global resources (Front Door, DNS, global policies) in a dedicated root. Avoid giant multi-region states where one region's failure blocks the other's applies.
11. **Q:** How do you avoid state bloat from Azure resources like role assignments?
**A.** `for_each` over maps (so state entries are keyed and stable), avoid creating a resource per user/object where a group assignment suffices, and keep in-cluster workloads (helm/k8s resources) in separate roots — applying dozens of Kubernetes objects through the same state as your networking makes plans slow and risky.
12. **Q:** How do you protect against accidental destroys on Azure?
**A.** `lifecycle { prevent_destroy = true }` on stateful resources (Key Vault, storage, SQL, state account itself), Azure resource locks (`azurerm_management_lock` with `CanNotDelete` — note they block Terraform too, so remove them deliberately before destroy), `deletion_protection` where the resource supports it (some azurerm resources), and a CI policy gate that blocks plans with destroy actions on protected resource types.
13. **Q:** How do you do state backup/DR?
**A.** Blob versioning + soft delete, storage account replication (GRS/RAZ-GRS) or a scheduled copy of the container to a second account, plus IaC-configured resource-lock protection. Practice restoring a state blob and running a plan in a sandbox — a documented but untested recovery isn't a control.
14. **Q:** What about state access via PIM/break-glass?
**A.** Humans should have no standing write; read access via PIM with justification and approval, all access logged, and a documented emergency path (elevate, force-unlock, fix). Capture the audit trail — an auditor will ask who could have modified production state and when.
15. **Q:** How do you handle provider/backend authentication for the state account in CI?
**A.** The pipeline identity (federated service principal or runner managed identity) needs `Storage Blob Data Contributor` on the state container and `use_azuread_auth = true`, plus network access (private endpoint with the runner in the VNet, or a firewall allow-list for the runner's egress IPs). Both pieces — RBAC and network — are common failure points; check them in order.

**🚨 War room**
16. **Q:** State is locked; the pipeline died mid-apply. What now?
**A.** Verify nothing is running, then `terraform force-unlock <id>` (or break the blob lease), run `plan` to see if the previous apply left partial changes, and reconcile. Then prevent recurrence: job timeouts, cancellation handling, and no local applies against shared backends.
17. **Q:** Two applies ran against the same state.
**A.** Assess the actual infrastructure vs state (`plan` may show many phantom changes); the fix is usually refresh + `state rm`/`import` for objects Terraform no longer tracks correctly. Then enforce single-writer: pipeline-only applies, with a concurrency group per root in the CI.
18. **Q:** A `terraform apply` deleted a production resource group.
**A.** Restore service (redeploy from IaC, restore data from backups — Azure resource deletion is often irreversible for data), preserve logs for the review, and prevent: `CanNotDelete` locks on production resource groups, `prevent_destroy` in code, denying `Microsoft.Resources/subscriptions/resourceGroups/delete` for pipeline identities in production, and requiring approval for plans containing RG deletions.
19. **Q:** State file is corrupt or partially written.
**A.** Restore a previous blob version (versioning/soft delete) and validate with `plan`; do not attempt to repair JSON by hand (lineage/serial metadata matters). If older versions are unreadable, rebuilding state via imports is the fallback.
20. **Q:** A secret appeared in a plan/apply output in CI logs.
**A.** Rotate the secret immediately, mark the variable/output `sensitive` (which redacts CLI output but not state), and redesign so the value isn't in Terraform at all (Key Vault reference + managed identity, or `ignore_changes` on the secret). Then restrict and purge CI logs where possible.
21. **Q:** Drift: someone added a rule to an NSG in the portal and Terraform reverted it during an unrelated apply.
**A.** Confirm the revert was correct/intended (it probably was — the portal change was out-of-band), then close the loop: investigate why the change happened (a hotfix? a missing feature?), codify it if needed, and add drift detection (scheduled plans) plus reduced human write access so it's caught in hours rather than during an unrelated apply.
22. **Q:** State was moved to a new storage account and pipelines started failing.
**A.** Update the backend config in every root (a `backend` block change requires `terraform init -migrate-state`), verify the new account's permissions/network for the pipeline identity, and do it during a quiet window with `plan` verification after migration. Missing the `init -migrate-state` step is the usual cause of confusion.

**⚖️ Trade-off**
23. **Q:** One state for a subscription vs one per environment+component?
**A.** One state per environment+component (root) is the standard: bounded blast radius, faster plans, clear ownership, and parallel teams. One big state is simpler to set up and reason about but couples everything and multiplies risk.
24. **Q:** `terraform_remote_state` vs published outputs (Key Vault/Storage/App Config)?
**A.** Published outputs (or data sources reading real resources) limit exposure to exactly the values needed and don't grant state access; `terraform_remote_state` is convenient but means consumers can read the producer's entire state — including secrets. Prefer narrow interfaces.
25. **Q:** Locking via blob lease vs relying on process discipline?
**A.** Use the lock (native, zero cost). Discipline fails: someone runs an apply locally, a job is cancelled, or two pipelines overlap. Then add CI concurrency controls per root as a second layer.
26. **Q:** Human read access to state vs no access at all?
**A.** No standing write, and read only via PIM with logging — engineers occasionally need to inspect state during an incident, and blocking that entirely pushes people to worse workarounds. Make it auditable rather than impossible.
27. **Q:** `prevent_destroy` vs Azure resource locks?
**A.** `prevent_destroy` is a Terraform-level guard (fails the plan/apply) — it doesn't stop a portal or CLI deletion. Azure locks (`CanNotDelete`) protect at the platform level (but also block Terraform from deleting, so they must be removed deliberately). Use both for critical resources: code guard against accidents, platform lock against out-of-band deletion.
28. **Q:** Managing the state account itself in Terraform?
**A.** It's a bootstrap problem: you can't provision your state backend from the same state. Solution: a documented bootstrap root applied manually/out-of-band once (creating the account, container, locks, RBAC), and — if you want it under code — a separate lifecycled root whose destruction is forbidden (`prevent_destroy`, locks, denied delete permissions). Be explicit that it's a special case.

**🎯 Senior**
29. **Q:** What's your state governance standard on Azure?
**A.** A dedicated state subscription/resource group with a private, encrypted, versioned, soft-delete-enabled storage account (`use_azuread_auth = true`); one blob per root with an encoded naming convention and a documented owner; RBAC limited to pipeline identities with PIM-only human read (logged); locks and `prevent_destroy` on the state account and all stateful resources; scheduled plan-based drift detection with alerts; CI concurrency control per root; and a rehearsed recovery runbook covering lock stuck, corruption, accidental destroy, and total loss (import rebuild).

**🎯 Senior signal:** "the state account is a bootstrap that can't manage itself", "restore the blob version rather than hand-editing JSON", and the cost of rebuilding state by import. Those three are marks of someone who has owned state.

---

## 4. Variables, Outputs & Locals — `variables-outputs-locals.md`

**⚡ Rapid**
1. **Q:** How do Azure Terraform roots typically receive variables?
**A.** Per-environment `*.tfvars` (committed, reviewed), pipeline-injected variables (`TF_VAR_*` or a `-var-file` per environment), and defaults in `variables.tf`. The environment's differences should be data, not code branches.
2. **Q:** What's the standard set of variables for an Azure landing-zone module?
**A.** `location`, `environment`, `subscription_id`, `tags`/`common_tags`, `name_prefix`, `address_space`/subnet definitions, `log_analytics_workspace_id`, `key_vault_id`, and feature flags (`enable_ddos`, `enable_private_dns`). Typed objects (e.g. a `subnets` map) beat flat variables for grouping.
3. **Q:** How do you enforce naming standards?
**A.** A locals/`naming` module composing names from inputs (org/app/env/region + resource-type abbreviation, e.g. `rg-orders-prod-weu`), used everywhere instead of string concatenation per resource; add `validation` for allowed environments/regions and a `random_string`/`random_id` suffix where global uniqueness is needed (storage, Key Vault, ACR, AKS DNS prefix).
4. **Q:** How do you handle Azure naming constraints?
**A.** Different resources have different rules (storage: 3–24 lowercase alphanumerics, no dashes; Key Vault: 3–24 alphanumeric + dashes, globally unique; AKS: alphanumeric with DNS rules). Centralise helpers in locals/a module with `substr`/`replace`/`lower` so nobody discovers constraints at apply time.
5. **Q:** What are outputs used for in Azure stacks?
**A.** Exposing IDs/names for other roots and pipelines (resource group name, subnet IDs, Key Vault URI, AKS cluster name, role assignment IDs), documenting the module interface, and feeding post-apply steps (e.g. `az aks get-credentials`). Mark anything sensitive (`sensitive = true`) and export only what's needed.
6. **Q:** How do you manage tags?
**A.** A `common_tags` (or provider `default_tags` on azurerm where supported) applied via modules, with per-resource additions; include owner, environment, cost-centre, data classification, and a `managed-by = terraform` marker. Enforce with Azure Policy (inherit from the resource group / require tags) so untagged resources can't slip through.
7. **Q:** How do you pass a list of subnets into a module?
**A.** A `map(object({...}))` (e.g. `subnets = { "web" = { cidr = "...", delegations = [...] }, ... }`) with validation, iterated by `for_each` — stable keys, readable tfvars, no positional mistakes.
8. **Q:** `sensitive = true` on an Azure output — what does it actually do?
**A.** Redacts the value in CLI output/plan and flags it in state; the value is still stored in state, so backend security is the real control. For secrets, prefer not to output them at all (consumers read from Key Vault with their own identity).

**🔍 Deep dive**
9. **Q:** Design the variable interface for a reusable Azure workload module (web app + SQL + Key Vault + diagnostics).
**A.** One typed `object` (or a handful of grouped objects): `naming` (app/env/region), `networking` (subnet IDs, private endpoint flags), `compute` (SKU/size/count, always-on, slots), `data` (SQL tier/storage/backup retention, admin auth mode), `security` (Key Vault ID, CMK, allowed IPs/ranges), `observability` (Log Analytics ID, retention, alert thresholds), plus `tags`. Defaults chosen so the secure/standard configuration is the easy path; validation blocks reject dev-sized prod or public exposure flags in prod.
**↳ Follow-up:** "How do you prevent a team from deploying prod with dev SKUs?"
**A.** Validation on the tier inputs combined with an environment-in-name check (e.g. prod names must include `prod`), Policy that denies non-approved SKUs in the production subscription, and a separate prod tfvars file behind an approval gate. Code-level validation catches the honest mistakes; Policy catches the rest.
10. **Q:** How do you avoid huge tfvars duplication across environments?
**A.** A `defaults` locals map merged with per-environment overrides (`merge(local.common, var.overrides)` or per-env `*.auto.tfvars`), with only genuine differences declared. Keep it shallow — deep overrides across environments become unreadable and error-prone.
11. **Q:** How do you parameterise Azure regions and allow multi-region deployments?
**A.** `location` as a variable with validation against an allow-list (often driven by Policy's allowed locations), region-specific settings (paired region for DR, availability zone support) as a `regions` map, and one root per region where the lifecycle differs. Region changes on existing resources usually force recreation — call that out.
12. **Q:** Where do you get shared platform values (Log Analytics workspace ID, hub subnet IDs, Key Vault URI)?
**A.** Data sources reading the real resource (`azurerm_log_analytics_workspace`, `azurerm_subnet`, `azurerm_key_vault` by name/RG) or published outputs (in Key Vault/App Config/Storage) — with variables as a fallback. Data sources validate existence at plan time and avoid hardcoding IDs across teams.
13. **Q:** How do you handle secrets in variables on Azure?
**A.** Don't: use Key Vault references (data source or `azurerm_key_vault_secret`) and identity-based access so values are fetched by the app at runtime, not passed through Terraform. Where Terraform must set a secret (initial bootstrap), mark sensitive, generate with `random_password`, store in Key Vault with a lifecycle-managed secret, and rotate.
14. **Q:** How do you test variable contracts?
**A.** `terraform validate` + plan in sandbox with valid/invalid inputs, `terraform test` (`.tftest.hcl`) for module validation blocks, and example roots (documented) that CI applies. If a module takes objects, negative tests for validation rules are the difference between a documented interface and an enforced one.
15. **Q:** What's your approach to output sensitivity for pipelines?
**A.** Outputs used by pipelines (AKS credentials, connection strings, keys) should be `sensitive` and consumed through secure channels (Key Vault references in the pipeline, not echoed), with the pipeline masking variables and restricting log access. Better still, have the *app* fetch its own credentials, so the pipeline never handles them.

**🚨 War room**
16. **Q:** A production tfvars change flipped a flag that exposed a service publicly. Response?
**A.** Revert immediately (apply the previous config), verify exposure window via activity logs and any access logs, rotate credentials if data could have been reached, then add guardrails: Policy denying public network access for those resource types, validation blocks on the flag, and a required reviewer for that file path (CODEOWNERS). Configuration files that alter security posture need the same review rigour as code.
17. **Q:** Variables are silently different between dev and prod, and nobody can explain why.
**A.** Diff the environments' tfvars and the module defaults being used (a default change can silently alter prod if it isn't overridden), then make differences explicit and reviewed — one file per environment, plus a CI diff that reports non-structural differences. Implicit defaults are how environments diverge.
18. **Q:** A module upgrade changed a variable's type and broke three roots.
**A.** Pin the module version until each root is updated, provide a migration note, and treat module interfaces as APIs (semver + changelog). Then add `terraform test`/example roots to module CI so interface changes are caught before consumers do.
19. **Q:** Outputs are being consumed by another root and the resource was renamed, breaking that pipeline.
**A.** Output names are a contract: keep them stable or add the new output alongside the old (deprecated) one, update consumers, then remove after a defined window. Communicate through the module README/changelog rather than in chat.
20. **Q:** Tags were added to tfvars but half the resources didn't get them.
**A.** Some resources don't support certain tags or need them applied explicitly; also check for resources created before the change or by a different module path. Fix by using `common_tags` consistently in the module, verify with a Resource Graph query, and enforce via Policy (inherit/append tags) so gaps surface automatically.
21. **Q:** A `random_string` suffix regenerated and the resource was recreated with a new name.
**A.** Ensure the random resource is defined once per root and stored in state (never computed in a `local`), and avoid `keepers` that change unexpectedly. If it did regenerate, you're in a migration situation (create new, move data, update consumers) — with `prevent_destroy` to stop the old resource disappearing.

**⚖️ Trade-off**
22. **Q:** One tfvars file per environment vs a single file with conditionals?
**A.** Per-environment files with a shared module: differences are explicit, reviewable, and diff-able across environments; conditionals inside modules hide environment behaviour in code and multiply as environments grow. Explicit files, boring modules.
23. **Q:** Typed object variables vs many flat variables?
**A.** Objects group related settings, make the interface readable, and allow nested defaults/validation; flat variables get unwieldy and encourage positional mistakes. Use objects with optional attributes (`optional()`), and keep the top-level count small.
24. **Q:** `default_tags` at the provider level vs `common_tags` per resource?
**A.** `default_tags` is convenient and consistent but has version-dependent behaviour and per-resource override semantics, and tag changes can churn; `common_tags` merged into each resource is explicit and predictable. Many teams use a `common_tags` local merged with resource tags — say which and why.
25. **Q:** Data sources vs passed-in variables for platform values (Log Analytics ID, subnet ID)?
**A.** Data sources stay current and reduce coupling (the platform team can change things without touching every root) at the cost of plan-time dependencies and slower plans; variables are explicit and fast but need updating. Prefer data sources for stable, well-named platform resources, and variables for values the module owner controls.
26. **Q:** Exposing sensitive outputs to pipelines vs Key Vault references?
**A.** Outputs put values in state, plan artifacts, and CI logs (risk); Key Vault references keep the value out of Terraform entirely and give you rotation/auditing. If the app can read Key Vault with its own identity, never pass the secret through Terraform.
27. **Q:** Region-specific roots vs one root with a region variable?
**A.** One root per region where lifecycles differ (DR, data residency, per-region quotas) for isolation and clarity; a single root with a region variable when the resource set is identical and you want one pipeline. Changing a region variable in a single root forces recreation of regional resources — a strong argument for per-region roots.
28. **Q:** Validation in code vs Policy for guardrails?
**A.** Code validation gives fast, local feedback and prevents obviously bad values; Policy is the enforcement layer that also catches out-of-band changes and other tools. Use both — validation for developer experience, Policy for assurance.

**🎯 Senior**
29. **Q:** What's your Azure module interface standard?
**A.** A small number of typed object variables grouped by concern with `optional()` attributes and sensible secure defaults; naming computed centrally from inputs (handling per-resource constraints); tags from a `common_tags` local layered with resource-specific tags; validation blocks for environment/SKU/region rules plus preconditions for cross-resource assertions; outputs limited to IDs/names/URIs that consumers actually need (nothing sensitive by default); and example roots + `terraform test` in the module repo so the interface is documented and enforced.

**🎯 Senior signal:** "secrets never pass through Terraform if the app can use its own identity", naming constraints handled centrally, and module interfaces treated as versioned APIs. Those three are the difference between writing modules and maintaining them for 20 teams.
