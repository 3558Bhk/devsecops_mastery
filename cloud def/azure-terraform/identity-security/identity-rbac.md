# Terraform Identity & RBAC (Azure) — Interview Questions

> **Cloud:** Azure · **IaC Tool:** Terraform · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~6 min

---

## Case A — Basic

**A1. What providers manage Azure identity in Terraform?**
**Answer:** `azuread` manages Entra ID objects (users, groups, apps, service principals); `azurerm` manages RBAC assignments and managed identities on Azure resources.

**A2. What is a service principal?**
**Answer:** An identity for an application/automation — created via `azuread_application` + `azuread_service_principal` — used by Terraform/CI to authenticate.

**A3. What is a role assignment in Terraform?**
**Answer:** `azurerm_role_assignment` grants a principal (user/group/service principal) a role (Contributor, Reader, custom) at a scope (subscription/RG/resource).

**A4. How do you grant a service principal Contributor on a resource group?**
**Answer:** `resource "azurerm_role_assignment" "contrib" { principal_id = azuread_service_principal.sp.object_id ; role_definition_name = "Contributor" ; scope = azurerm_resource_group.rg.id }`.

**A5. What is the difference between `object_id` and `application_id` (client_id)?**
**Answer:** `application_id` is the app's client ID; `object_id` is the service principal's unique ID in the directory — role assignments use the principal's `object_id`.

**A6. What is a managed identity?**
**Answer:** An Azure AD identity tied to an Azure resource (VM, App Service, AKS) — system-assigned (lifecycle-tied) or user-assigned (standalone) — for credential-free access.

**A7. How do you enable a system-assigned identity on a resource?**
**Answer:** An `identity { type = "SystemAssigned" }` block on the resource (VM, web app, etc.).

**A8. What is a user-assigned identity in Terraform?**
**Answer:** `azurerm_user_assigned_identity` — a standalone identity you can assign to multiple resources.

**A9. How do you grant Key Vault access to a managed identity?**
**Answer:** `azurerm_role_assignment` (Key Vault RBAC) with the identity's `principal_id` and a role like `Key Vault Secrets User`, at the vault scope.

**A10. What is a built-in role vs a custom role?**
**Answer:** Built-ins (Contributor, Reader, Owner, Storage Blob Data Reader…) are Azure-provided; custom roles (`azurerm_role_definition`) define your own permission set.

**A11. What is `data "azurerm_client_config"`?**
**Answer:** Returns the current Terraform client's object_id/tenant_id/subscription_id — often needed to grant the deploying principal access.

**A12. What is a role definition name vs ID?**
**Answer:** The name (e.g. `Contributor`) is human-readable; the ID is the GUID. Terraform accepts either via `role_definition_name`/`role_definition_id`.

**A13. What is Azure AD group in Terraform?**
**Answer:** `azuread_group` — a directory group used to grant access to many users at once.

**A14. How do you scope a role assignment to a single resource?**
**Answer:** Set `scope` to the resource's ID (e.g. a storage account ID) instead of the subscription/RG.

**A15. What is conditional access / privileged identity management in this context?**
**Answer:** Entra ID features (PIM for just-in-time roles, Conditional Access policies) that Terraform can partially manage via the `azuread` provider — outside plain role assignments.

## Case B — Advanced / Senior

**B1. How do you design a least-privilege RBAC model for Terraform deployments?**
**Answer:** Separate identities per pipeline stage (plan = Reader, apply = scoped Contributor/custom roles), scope at resource-group (not subscription) level, use custom roles limited to the resource types Terraform manages, and review with Access Reviews.

**B2. How do custom roles work in Terraform?**
**Answer:** `azurerm_role_definition` with `assignable_scopes` and `permissions { actions, not_actions, data_actions }` — define once, assign like built-ins, and version carefully (role changes affect all assignments).

**B3. How do you grant fine-grained data-plane access (e.g. blob read) vs management-plane?**
**Answer:** Data-plane roles (e.g. `Storage Blob Data Reader`) control data operations; management roles (Reader/Contributor) control resource management. Assign both only as needed — they're independent.

**B4. How do you avoid the chicken-and-egg of "who grants the first role"?**
**Answer:** The account owner/global admin bootstraps the first service principal and its role assignments (often via CLI or a small bootstrap Terraform with the deploying identity), then automation manages the rest.

**B5. What is the difference between Key Vault access policies and RBAC?**
**Answer:** Access policies are Key Vault's legacy per-vault permission model; RBAC (`enable_rbac_authorization = true`) uses Azure roles. Prefer RBAC for consistency with the rest of Azure.

**B6. How do you manage role assignments at scale across many resources?**
**Answer:** A module iterating `for_each` over principals × scopes × roles, with the assignments kept in one place — plus Azure Policy to catch drift.

**B7. What is PIM (Privileged Identity Management) and how does it relate to Terraform assignments?**
**Answer:** PIM makes role assignments eligible (just-in-time) instead of active. Terraform can assign the eligible role; activation is a user/runtime step with approval and time limits.

**B8. How do you scope managed identities correctly?**
**Answer:** Give each workload its own user-assigned identity, grant only the data-plane roles it needs at the narrowest scope (e.g. one Key Vault, one container), and avoid sharing identities across apps.

**B9. What are the risks of using `azurerm_role_assignment` at subscription scope?**
**Answer:** Broad blast radius — any resource in the subscription inherits it. Prefer resource-group or resource scope, and use custom roles to reduce permission width.

**B10. How do you handle principal deletion (service principal removed) in state?**
**Answer:** Role assignments to deleted principals fail/recreate — keep service principals managed in Terraform, and if one is deleted externally, re-create it (the `azuread` provider tracks it) to restore assignments.

**B11. How do you grant cross-tenant access?**
**Answer:** Entra B2B: invite the external user/principal, then assign roles with `azurerm_role_assignment` using their object ID in your tenant — Terraform needs the `azuread` provider in both tenants (aliased) for full management.

**B12. How do you audit "who has what" across your estate?**
**Answer:** Export role assignments (Terraform state or Azure Resource Graph) into reports, enable access reviews, and monitor with Entra ID logs — Terraform config documents intended state, Resource Graph shows actual.

## Case C — Scenario

**C1. A pipeline needs to deploy VMs but not touch networking resources.**
**Answer:** Create a custom role with only the VM-related actions (Microsoft.Compute/virtualMachines/*, plus needed dependencies), assign it at the app resource group scope, and use it for the apply stage.

**C2. A service principal's secret leaked; how do you respond?**
**Answer:** Immediately rotate/remove the secret (or better, switch the pipeline to OIDC/managed identity), audit activity logs for abuse, and re-issue with least-privilege scoping. Add expiry + monitoring for future credentials.

**C3. Multiple teams need access to their own resource groups only.**
**Answer:** Create a group per team, assign Contributor (or a custom role) scoped to each team's resource group via a module (`for_each` over teams), and let group membership govern access.

**C4. A VM needs to read secrets from Key Vault without any stored credentials.**
**Answer:** Enable a managed identity on the VM, grant it `Key Vault Secrets User` (RBAC) at the vault, and use the managed identity from the app code — no keys or connection strings.

**C5. You're migrating from Key Vault access policies to RBAC authorization.**
**Answer:** Set `enable_rbac_authorization = true` on the vault, recreate the same permissions as role assignments (map policy → role), verify apps still access, then remove the access policies.

**C6. An auditor asks for a report of all role assignments with elevated access.**
**Answer:** Query Azure Resource Graph (or Terraform state) for Owner/Contributor/User Access Administrator assignments, export to the auditor, and set up access reviews + PIM for the elevated roles found.
