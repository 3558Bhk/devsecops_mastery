# Terraform Basics (Azure) — Interview Questions

> **Cloud:** Azure · **IaC Tool:** Terraform · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~6 min

---

## Case A — Basic

**A1. What is Terraform and how does it manage Azure?**
**Answer:** Terraform is HashiCorp's Infrastructure-as-Code tool. You declare Azure resources in HCL, and the `azurerm` provider translates that into Azure Resource Manager (ARM) API calls, tracking everything in state.

**A2. What is the `azurerm` provider?**
**Answer:** The official Azure provider for Terraform, mapping resources like `azurerm_resource_group`, `azurerm_virtual_network`, and `azurerm_virtual_machine` to Azure services.

**A3. What is the core Terraform workflow?**
**Answer:** `terraform init` (install providers/backend), `terraform plan` (preview changes), `terraform apply` (apply changes), and `terraform destroy` (tear down), supported by `validate` and `fmt`.

**A4. What does `terraform init` do in an Azure project?**
**Answer:** Downloads the `azurerm` provider, configures the backend (e.g. Azure Storage for state), and creates `.terraform/` plus the dependency lock file.

**A5. How does Terraform authenticate to Azure?**
**Answer:** Via the Azure CLI (`az login`), a service principal (client ID/secret/certificate), managed identity, or OIDC federation — set through provider arguments or env vars.

**A6. What is a resource group in Terraform?**
**Answer:** `azurerm_resource_group` — Azure's logical container for resources (location + name). Almost every resource lives in one.

**A7. What is an Azure resource provider / namespace?**
**Answer:** Each Azure service is exposed via a namespace like `Microsoft.Compute`; Terraform's `azurerm` resources map to these, and subscriptions must register the providers.

**A8. What is the `features {}` block?**
**Answer:** A required block in the `azurerm` provider configuring provider behaviors (e.g. `key_vault { purge_soft_delete_on_destroy = true }`, `resource_group { prevent_deletion_if_contains_resources = true }`).

**A9. What is a data source?**
**Answer:** A read-only query of existing Azure resources, e.g. `data "azurerm_resource_group" "existing"` or `data "azurerm_subscription" "current"`.

**A10. What does `terraform plan` show for Azure resources?**
**Answer:** The ARM-level changes Terraform will make — create/update/delete of resources and their properties, without touching Azure.

**A11. What is the state file?**
**Answer:** `terraform.tfstate` maps config resources to real Azure resource IDs (e.g. `/subscriptions/.../resourceGroups/rg/providers/...`).

**A12. What are `.tf` vs `.tfvars` files?**
**Answer:** `.tf` holds configuration; `.tfvars` supplies variable values per environment (e.g. `prod.tfvars`), loaded with `-var-file`.

**A13. What is `terraform fmt` and `terraform validate`?**
**Answer:** `fmt` reformats HCL; `validate` checks syntax and references locally before any Azure API call.

**A14. What is the `azurerm` provider version constraint?**
**Answer:** e.g. `required_providers { azurerm = { source = "hashicorp/azurerm", version = "~> 4.0" } }` — pins the major/minor for reproducibility.

**A15. What is `.terraform.lock.hcl`?**
**Answer:** Locks exact provider versions and hashes so every machine/CI uses identical `azurerm` binaries.

## Case B — Advanced / Senior

**B1. How does the `features {}` block change provider behavior, and why is it required?**
**Answer:** It opts into behaviors that were previously implicit (soft-delete purging, resource group deletion safety, VM encryption-at-host defaults). Explicitly declaring it makes behavior deterministic across upgrades.

**B2. What are the main Azure authentication methods and their Terraform precedence?**
**Answer:** Provider arguments (`client_id`/`client_secret`/`tenant_id`), env vars (`ARM_CLIENT_ID`, etc.), Azure CLI login, managed identity, and OIDC (`use_oidc = true`). Explicit provider arguments win; the CLI path is convenient for local dev.

**B3. What is a service principal and how do you create one for Terraform?**
**Answer:** An app registration with credentials used for automation. Create via `az ad sp create-for-rbac` and grant it Contributor/Owner (or scoped roles) on the target subscription/resource groups.

**B4. How do you manage Terraform across multiple Azure subscriptions?**
**Answer:** Use provider aliases with `subscription_id` set per alias, or `data "azurerm_subscriptions"` to enumerate. Route resources to the right alias with `provider = azurerm.prod`.

**B5. What is OIDC federation for Azure and why prefer it over secrets?**
**Answer:** It lets CI (GitHub Actions) exchange a token for an Azure AD credential via a federated credential — no long-lived client secrets to rotate or leak.

**B6. How do you find the current subscription and tenant in config?**
**Answer:** `data "azurerm_subscription" "current" {}` gives `subscription_id`, `tenant_id`; `data "azurerm_client_config" "current" {}` gives the authenticated client/object IDs — useful for Key Vault policies.

**B7. How do ARM resource IDs relate to Terraform state and imports?**
**Answer:** Each Azure resource has an ID like `/subscriptions/SUB/resourceGroups/RG/providers/Microsoft.Network/virtualNetworks/VNET`; `terraform import` maps that ID into state so Terraform can manage the existing resource.

**B8. What are the tradeoffs of Terraform vs ARM/Bicep for Azure?**
**Answer:** Terraform is multi-cloud, stateful, and has a huge ecosystem; Bicep is Azure-native, declarative, and state-free (ARM tracks state). Many teams standardize on Terraform for a single IaC across clouds.

**B9. How do you pin Azure provider + Terraform core versions in a team?**
**Answer:** Commit `.terraform.lock.hcl`, set a version constraint on `azurerm`, use a version-manager (tfenv/mise) or Docker image for the CLI, and document the matrix in the repo README.

**B10. What is the difference between `azurerm` and `azuread` providers?**
**Answer:** `azurerm` manages Azure resources; `azuread` manages Azure AD/Entra ID objects (users, groups, applications, service principals, role assignments) that sit outside a subscription.

**B11. How does Terraform handle eventual consistency in Azure APIs?**
**Answer:** The `azurerm` provider retries with backoff for known async operations (create/update). For races between resources, use explicit `depends_on` or `time_sleep` to sequence.

**B12. How do you debug a failing `azurerm` apply?**
**Answer:** Enable `TF_LOG=DEBUG` (or `ARM_*` debug), check the resource provider is registered (`az provider register`), verify RBAC on the service principal, and read the ARM error in the apply output.

## Case C — Scenario

**C1. `terraform plan` fails with "the subscription is not registered to use namespace 'Microsoft.X'".**
**Answer:** Register the resource provider (`az provider register -n Microsoft.X`) or add a `null_resource`/CLI step, wait for registration, then re-plan. Provider registration is a one-time per-subscription action.

**C2. A new team member can't run `terraform plan` against the shared subscription.**
**Answer:** Check their Azure CLI login (correct tenant/subscription), service principal/role assignment, and whether they're using the right backend state. Grant scoped RBAC (Contributor on the resource group) rather than full Owner.

**C3. You must move from client-secret auth to OIDC in CI.**
**Answer:** Create a federated credential on the app registration for the repo/branch, set `ARM_CLIENT_ID`/`ARM_TENANT_ID`/`ARM_USE_OIDC=true` (or `use_oidc`), and remove the old secret. Update the pipeline and rotate/delete the client secret.

**C4. Resources were created in the wrong Azure region. How do you fix it without downtime?**
**Answer:** Most Azure resources can't change region in place. For stateless resources, recreate in the correct region and repoint. For stateful, use geo-redundancy/failover or restore. Prevent recurrence by centralizing `location` as a variable.

**C5. `terraform init` is slow in CI and occasionally fails to download the provider.**
**Answer:** Cache the `.terraform` directory/provider cache (or use a private registry/mirror), pin versions to reduce churn, and add retries. Alternatively vendor the provider into a base CI image.

**C6. You're standardizing on Terraform across an Azure estate managed partly by portal/Bicep.**
**Answer:** Import existing resources group by group, adopt them into state with `-refresh-only`, define ownership rules (Terraform owns infra, portal read-only), and roll out with a naming/tagging standard + CI gates.
