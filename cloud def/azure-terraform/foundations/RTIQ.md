# RTIQ — Terraform Foundations on Azure (Real-Time Interview Questions)

> **Cloud:** Azure · **Tool:** Terraform · **Domain:** Resource groups, naming, tagging, landing-zone primitives · **Target roles:** SDE-3 · Cloud Engineer · DevOps · DevSecOps · SRE · Platform Engineer · **Reading time:** ~10 min

**How this file is used live:** this is the "do you understand Azure's structural primitives" round. It sounds basic, but senior interviewers use it to test whether you can design a landing zone that 40 teams can use without collisions — and whether you know how naming, tagging, and resource groups interact with Policy, RBAC, and cost management.

**Legend:** ⚡ Rapid · 🔍 Deep dive · 🚨 War room · ⚖️ Trade-off · 🎯 Senior signal

---

**⚡ Rapid**
1. **Q:** What is a resource group, and what's the Terraform resource?
**A.** A logical container/lifecycle boundary for resources in one subscription/region-mixed scope; RBAC and Policy are often scoped to it, and deleting it deletes everything inside. `azurerm_resource_group` with required `name` and `location`.
2. **Q:** Are resources tied to the RG's region?
**A.** No — the RG has a location (metadata), but resources inside can be in different regions. Still, the common convention is one RG per workload/env/region for clarity and lifecycle management.
3. **Q:** What does `prevent_destroy` do for an RG, and why does everyone add it?
**A.** It blocks Terraform from deleting the RG — critical because deleting an RG destroys every resource inside. Combine it with an Azure `CanNotDelete` lock for protection against out-of-band deletion.
4. **Q:** How do you manage naming in Terraform?
**A.** A central locals/`naming` module composing `rg-<app>-<env>-<region>` style names from inputs, using `lower`, `replace`, and `substr` for per-resource constraints, and a `random_string`/`random_id` suffix where global uniqueness is required (storage, Key Vault, ACR, AKS DNS prefix).
5. **Q:** What are the naming constraints to remember?
**A.** Storage accounts: 3–24 chars, lowercase alphanumerics only, globally unique. Key Vault: 3–24, alphanumerics and hyphens, globally unique, must start with a letter. AKS/ACR/VMs/NSGs have their own rules (length, allowed characters, DNS rules). Centralise this — discovering them at apply time is embarrassing.
6. **Q:** How do you tag in Terraform?
**A.** A `common_tags` local (`environment`, `owner`, `cost_centre`, `app`, `data_classification`, `managed_by = "terraform"`) merged with resource-specific tags and passed through modules; `default_tags` on the azurerm provider where supported. Enforce with Policy so untagged resources are flagged/denied.
7. **Q:** Why tag at all?
**A.** Cost allocation/showback, ownership for incident routing, compliance (data classification), and automation (shutdown schedules, backup policies, patch rings by tag). If you can't answer "who owns this and what is it", the tags are wrong.
8. **Q:** How do you create a management group hierarchy in Terraform?
**A.** `azurerm_management_group` (nestable) with subscriptions associated via `azurerm_management_group_subscription_association` — the hierarchy drives Policy inheritance and RBAC. Often bootstrapped out-of-band (a tenant-level root group) and managed thereafter.
9. **Q:** What is a landing zone, in Terraform terms?
**A.** The set of foundational resources/policies every workload inherits: management groups, subscriptions, Policy assignments, hub networking, DNS zones, Log Analytics, Key Vault/ACR, and the RBAC baseline — deployed as a platform root that workload roots build on.
10. **Q:** Should resource groups be created by the platform team or by workload teams?
**A.** Either, but with a convention: usually one RG per workload/env created by the workload's root (so it can be destroyed with the workload), while shared/platform RGs are platform-owned with locks. What matters is that ownership — and therefore delete rights — is unambiguous.

**🔍 Deep dive**
11. **Q:** Design the resource-group and tagging strategy for a 40-team enterprise on Azure.
**A.** Structure: management groups (platform/landing-zone/decommissioned, prod/non-prod), one subscription per environment tier (or per team in large orgs), and RGs per workload+environment (e.g. `rg-orders-prod-weu`) plus a shared `rg-platform-prod-weu` for hub services. Convention: `rg-<workload>-<env>-<region>`; tags include owner (team), cost centre, app, env, data classification, and backup/patch ring. RBAC granted at the RG for team Contributor (PIM for prod), with all prod RGs carrying `CanNotDelete` locks and `prevent_destroy`. Policy assigns tag inheritance, allowed locations, and required tags. Cost management uses tags + budgets per RG, so the naming/tagging standard is what makes showback possible.
**↳ Follow-up:** "How do you stop a team from creating resources outside its RGs?"
**A.** Deny Policy at the subscription/management-group level requiring a tag or naming pattern (e.g. `Microsoft.Resources/subscriptions/resourceGroups` must match the convention), plus RBAC scoped to RGs only (no subscription-level Contributor) so creation elsewhere fails authorisation. Guardrails, not reminders.
12. **Q:** How do you handle resource groups across regions for a multi-region app?
**A.** One RG per region (per workload/env) so regional teardown/redeploy is clean and failures are isolated, with global resources (Front Door, Traffic Manager, DNS) in a dedicated global RG. Avoid cramming multi-region resources into one RG — it makes lifecycle and RBAC muddy.
13. **Q:** What does an RG-level lock do to Terraform?
**A.** `CanNotDelete` (or `ReadOnly`) blocks Terraform's delete/update operations too, so a `terraform destroy`/replace fails with a clear error. That's the point — but it means the pipeline must be able to remove the lock deliberately (a two-step, reviewable action) when a genuine teardown is required.
14. **Q:** How do you implement tag inheritance?
**A.** Azure Policy with `modify` (append/inherit tags from the RG/subscription) and `deny` for missing required tags; Terraform sets tags explicitly in modules so the code is the source of truth, and Policy catches out-of-band creations. Note the interaction: Policy `modify` writes tags that Terraform may then see as drift — pick one owner per tag.
15. **Q:** How do you manage subscriptions with Terraform?
**A.** `azurerm_subscription` (for creating subscriptions via an EA/MCA billing scope) + management group association + baseline Policy assignment + budget (`azurerm_consumption_budget_subscription`) and a `Subscription Creator`-style role for the platform team's automation. Many orgs keep subscription creation semi-manual and codify everything else — say which and why.
16. **Q:** How do you structure modules for foundations?
**A.** `resource_group` (with locks/tags), `naming`, `tags`, `policy-assignment` (wrapping assignments at a scope), `role-assignment`, and `management-group`. They're small but shared by every root — keep them stable, versioned, and tested because a change ripples everywhere.
17. **Q:** How do you handle the bootstrap problem (management groups, state, policies)?
**A.** A documented bootstrap phase outside the normal pipeline: tenant-level management groups and the initial subscription, the state storage account/container, the pipeline identities and federated credentials, and the baseline Policy assignments — applied by a privileged human/break-glass process and then managed (or at least referenced) by code. Document it because you'll need it in a disaster.
18. **Q:** How do you prevent drift in foundation resources?
**A.** Scheduled plans on the foundation roots with alerts, Policy `deny` effects for the settings that matter (allowed locations, required tags, no public IPs), Activity Log alerts on changes to management groups/Policy/RBAC, and restricted human write access. Foundation drift is the most dangerous kind because it affects everything downstream.

**🚨 War room**
19. **Q:** An apply is about to delete a resource group that still contains resources. What do you do?
**A.** Stop and inspect: is the RG empty of the resources Terraform knows about but full of others (untracked resources created outside code)? Then decide per resource: import into code, move out of the RG (Terraform can't move resources between RGs in place — that requires recreation or an ARM move, which Terraform handles poorly), or delete deliberately. Never let an apply delete an RG as a side effect; add `prevent_destroy`/locks to make it impossible.
20. **Q:** Half the estate is untagged after a Policy change.
**A.** Check whether the Policy uses `modify`/`append` (which requires a remediation task to fix existing resources) and whether a remediation job was created (`azurerm_management_group_policy_remediation`/`azurerm_subscription_policy_remediation`). Then verify the tags Terraform owns weren't overwritten — pick one owner per tag to prevent a fight between Policy and Terraform.
21. **Q:** A team created a resource group with a duplicate/incorrect name and now reporting is broken.
**A.** Either rename (recreate + migrate, since RG names are immutable) or accept and fix the convention going forward with Policy enforcement. Prefer the second plus a clean-up of the odd one — the value of the convention comes from consistency, so make it enforceable.
22. **Q:** Costs are unattributable because tags are missing on 30% of resources.
**A.** Remediate with a Policy remediation task for existing resources, enforce `deny` for new ones, and use Cost Management's tag inheritance view for resources that can't be tagged. Then do a one-time sweep of the biggest spenders first — cost attribution work should follow the money.
23. **Q:** Someone deleted a shared platform resource group (Log Analytics, Key Vault) from the portal.
**A.** Restore/thin-recovery: Key Vault soft delete/recover, Log Analytics is not recoverable if deleted (data loss — check retention expectations), so document the impact. Then: `CanNotDelete` locks on all platform RGs, no human delete permissions in production, Activity Log alerts on RG deletions, and (where possible) soft-delete-enabled services.
24. **Q:** Policy blocks an apply your team needs (e.g. a region not in the allowed list).
**A.** Understand the control's intent, then follow the governed exception path (Policy exemption with an expiry and justification, or an expanded allowed list if the requirement is legitimate), rather than changing the Policy ad hoc. Track exemptions as a register — unmanaged exemptions effectively delete the control.
25. **Q:** A new subscription was created and nothing works (no Policy, no diagnostics, no RBAC baseline).
**A.** The subscription wasn't associated with the management group or the baseline assignment didn't propagate — automate subscription creation + association + baseline assignment (Policy assignment at the MG with `enforce`, diagnostics via `deployIfNotExists`, budgets, and an initial role assignment for the team) so a new subscription is born compliant. Manual onboarding always leaves gaps.

**⚖️ Trade-off**
26. **Q:** One resource group per workload vs per resource type vs a shared RG?
**A.** Per workload+env (recommended): clear ownership, RBAC, cost mapping, and teardown. Per resource type (all NSGs together) makes lifecycle/RBAC confusing and couples unrelated stacks. A shared RG for platform services is fine if it's platform-owned with locks. Choose per workload and be consistent.
27. **Q:** Subscription per team vs shared subscriptions with RGs?
**A.** Subscription-per-team gives the strongest RBAC/quota/policy isolation and clean cost boundaries, at the cost of more subscriptions to govern (manageable with automation); shared subscriptions are cheaper/simpler operationally but rely on RG-level RBAC discipline and have shared quota/service limits. Regulated orgs lean subscription-per-boundary.
28. **Q:** Terraform-managed subscriptions vs Azure's native tooling (EA portal/Blueprint/landing-zone accelerator)?
**A.** The Azure Landing Zone accelerator/Blueprints can bootstrap the hierarchy quickly and consistently, but you often need Terraform for ongoing management and workload integration. Pragmatic: use the accelerator to establish the structure, then manage/reference it in Terraform — don't maintain two sources of truth for the same objects.
29. **Q:** Tag enforcement with `deny` vs `modify` (append)?
**A.** `deny` prevents creation of untagged resources (strict, but can block automation/deployments that don't set tags); `modify`/append fills missing tags automatically (smoother, but the tags may not reflect reality — e.g. a wrong owner inherited). Many orgs `deny` on the critical keys (owner, env, cost centre) and `append` the rest.
30. **Q:** Should resource groups be managed by the workload root or a platform root?
**A.** Workload root when the workload owns its lifecycle (create/destroy together, RBAC at the RG) — most common; platform root when many workloads share an RG or the RG is a governance boundary. Avoid both managing the same RG (conflict and drift); document ownership in code comments.

**🎯 Senior**
31. **Q:** What does a well-designed Azure foundation look like in Terraform?
**A.** Management-group hierarchy driving Policy and RBAC; subscription-per-environment-tier (or per team) with a baseline assignment applied automatically; a documented naming convention implemented in a shared `naming` module (handling each resource's constraints); a tag standard with `deny` for critical keys plus remediation for existing resources; one RG per workload+env with locks on platform RGs and `prevent_destroy` on stateful/structural resources; budgets and cost views driven by tags; Activity Log alerts on RG/Policy/RBAC changes; and a documented bootstrap procedure (tenant roots, state account, CI identities) that a privileged operator can execute in a disaster.

**🎯 Senior signal:** "deleting an RG deletes everything inside — lock it and make it impossible by accident", Policy-vs-Terraform tag ownership, and treating the bootstrap as a documented break-glass. Those three are foundation-level maturity.
