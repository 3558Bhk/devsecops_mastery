# Terraform Resource Groups, Naming & Tags (Azure) — Interview Questions

> **Cloud:** Azure · **IaC Tool:** Terraform · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~6 min

---

## Case A — Basic

**A1. What is an Azure resource group in Terraform?**
**Answer:** `azurerm_resource_group` — a logical container for resources that share a lifecycle, with a name and a region (`location`).

**A2. How do you declare a resource group?**
**Answer:** `resource "azurerm_resource_group" "rg" { name = "prod-app-rg" ; location = "eastus" }`.

**A3. Why group resources by resource group rather than one giant group?**
**Answer:** To align lifecycles, permissions (RBAC is commonly scoped at the group), and costs — resources deleted/managed together live in one group.

**A4. What are tags in Azure?**
**Answer:** Name/value pairs attached to resources (and resource groups) for cost tracking, ownership, and organization — e.g. `environment = "prod"`.

**A5. How do you tag a resource group in Terraform?**
**Answer:** `tags = { environment = "prod" ; costcenter = "1234" }` on the resource group, or on individual resources.

**A6. Do tags inherit from resource group to resources?**
**Answer:** No — tags don't inherit automatically. Each resource must be tagged, or you use Azure Policy to inherit/apply them.

**A7. What is `default_tags` on the azurerm provider?**
**Answer:** A provider-level `default_tags` block that automatically adds tags to every resource the provider creates.

**A8. What is `ignore_tags` on the provider?**
**Answer:** Tag keys the provider ignores when comparing state, so externally added tags don't cause perpetual diffs.

**A9. How do you build consistent resource names in Terraform?**
**Answer:** With locals or a naming module combining prefix, environment, region, and resource type, e.g. `local.name = "${var.prefix}-${var.env}-${var.location_short}-web"`.

**A10. Why are Azure naming conventions important?**
**Answer:** Many resource names are globally unique (storage accounts), immutable after creation, and length/char constrained — a convention avoids collisions and rework.

**A11. What is a management lock?**
**Answer:** `azurerm_management_lock` — a read-only or delete lock preventing accidental changes/deletion of a resource or group.

**A12. How do you enforce tags with Azure Policy?**
**Answer:** Assign a policy (e.g. "Require a tag on resources") via `azurerm_policy_definition`/`azurerm_policy_assignment`, which audits/denies untagged resources.

**A13. What is the resource group's `location` used for?**
**Answer:** The region where the group's metadata lives; resources in the group can be in different regions, but group+resources usually share a region.

**A14. How do you reference an existing resource group?**
**Answer:** `data "azurerm_resource_group" "existing" { name = "prod-app-rg" }`.

**A15. What is a resource ID and how do you output it?**
**Answer:** The ARM identifier `/subscriptions/.../resourceGroups/.../providers/...`; output with `output "rg_id" { value = azurerm_resource_group.rg.id }`.

## Case B — Advanced / Senior

**B1. How do you design a naming convention module for Azure?**
**Answer:** A module/local producing names from inputs (project, environment, region short code, resource type) with validation for length/charset, exposed for every resource — keeping names consistent and predictable.

**B2. What is the CAF (Cloud Adoption Framework) naming guidance?**
**Answer:** Microsoft's recommended pattern: `resourceType-businessUnit-appName-env-region-###` (e.g. `vm-fin-pay-prod-eus-001`), with resource-type prefixes and env abbreviations documented.

**B3. How do you implement tag inheritance in Terraform when Azure doesn't do it natively?**
**Answer:** Use Azure Policy with a "modify/append" effect to copy tags, or `default_tags` on the provider, or a locals map merged into every resource — and add a policy to catch missing tags.

**B4. What is the difference between tags on the provider vs per-resource vs Azure Policy?**
**Answer:** `default_tags` applies at create time for everything Terraform creates; per-resource tags override/add; Azure Policy enforces at the platform level (including non-Terraform resources). Combine them for coverage.

**B5. How do you handle case-sensitivity and tag key collisions?**
**Answer:** Azure tag keys are case-insensitive; Terraform diffs can churn if casing varies. Normalize keys (lowercase) in a locals map and apply consistently.

**B6. When should you split resources across multiple resource groups vs one?**
**Answer:** Split by lifecycle/ownership and permission boundary (e.g. network group, app group, data group). One group per app is a common pattern; a shared group hides ownership and bloats RBAC.

**B7. How do you scope RBAC and locks to resource groups in Terraform?**
**Answer:** `azurerm_role_assignment` with `scope = azurerm_resource_group.rg.id` and `azurerm_management_lock` on the group — giving teams access/locks at the right boundary.

**B8. What are the pitfalls of `default_tags` with `ignore_tags`?**
**Answer:** `default_tags` only applies to new resources; existing ones need a plan/apply to pick them up. `ignore_tags` can mask real drift — use it deliberately for tags owned by other systems (e.g. cost automation).

**B9. How do you rename a resource group (it's immutable) — what's the migration path?**
**Answer:** Resource groups can't be renamed. Create the new group, move resources (`az resource move` or Terraform state mv/recreate), repoint dependencies, then delete the old group.

**B10. How do you enforce "no resources outside approved regions"?**
**Answer:** Azure Policy with allowed locations assigned at subscription/management-group scope, so any resource (Terraform or manual) in a disallowed region is denied/audited.

**B11. How do you structure landing zones with resource groups in Terraform?**
**Answer:** A landing-zone module creating the resource groups (network, shared, app, data) with tags, locks, and RBAC per environment — instantiated per env so every zone is consistent.

**B12. How do you reconcile portal-created resources that lack Terraform tags?**
**Answer:** Import them into Terraform (or use `-refresh-only`) so config owns them, then apply the standard tags; use Azure Policy to tag stragglers automatically.

## Case C — Scenario

**C1. Costs are hard to attribute because resources lack tags.**
**Answer:** Roll out `default_tags` + Azure Policy (require costcenter/environment), backfill tags via a remediation task, and enforce going forward so cost reports group correctly.

**C2. A storage account name collision means a deploy failed in another region.**
**Answer:** Storage account names are globally unique — regenerate with a unique suffix (e.g. random or env+region hash) via a naming module, and update references before re-applying.

**C3. You need to move several resources to a new resource group without downtime.**
**Answer:** Use `az resource move` for supported resource types, update Terraform config/state (`state mv` or re-import) to the new group, verify plan is clean, then delete the old group.

**C4. A compliance scan flags resources without a required tag.**
**Answer:** Assign the "require tag" policy with a modify/append or deny effect, fix the Terraform config (default_tags or per-resource), and let the policy catch non-Terraform resources.

**C5. Someone keeps deleting a shared resource group.**
**Answer:** Add an `azurerm_management_lock` (CanNotDelete) on the group, restrict RBAC so only the platform team can delete, and alert on delete attempts via Activity Log.

**C6. Naming is inconsistent across 3 teams; you're standardizing.**
**Answer:** Adopt a naming module (CAF-style) as the single source of truth, migrate existing resources where names are mutable, and enforce conventions for new resources via policy/linters.
