# Terraform Providers (Azure) — Interview Questions

> **Cloud:** Azure · **IaC Tool:** Terraform · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~6 min

---

## Case A — Basic

**A1. What is the `azurerm` provider?**
**Answer:** The official provider that lets Terraform manage Azure resources, translating HCL into Azure Resource Manager (ARM) API calls.

**A2. How do you declare the azurerm provider?**
**Answer:** `provider "azurerm" { features {} }` — the `features {}` block is required. Credentials come from arguments, env vars, or Azure CLI login.

**A3. What is the `features {}` block for?**
**Answer:** It configures provider behaviors such as soft-delete purging, resource group deletion protection, and default tags, and is mandatory in the current provider versions.

**A4. How do you set the subscription in the provider?**
**Answer:** Via `subscription_id`, or the `ARM_SUBSCRIPTION_ID` env var. Multiple subscriptions use provider aliases.

**A5. What is a provider alias?**
**Answer:** A named secondary provider config, e.g. `provider "azurerm" { alias = "prod" ; subscription_id = "..." ; features {} }`, referenced as `provider = azurerm.prod`.

**A6. What is the `azuread` provider?**
**Answer:** It manages Entra ID (Azure AD) objects — users, groups, applications, service principals — outside the ARM subscription scope.

**A7. What is the `random` and `azapi` provider used for?**
**Answer:** `random` generates names/IDs; `azapi` calls ARM APIs directly for resources or properties the `azurerm` provider doesn't yet support.

**A8. How do you pin the azurerm provider version?**
**Answer:** `required_providers { azurerm = { source = "hashicorp/azurerm", version = "~> 4.0" } }` and commit `.terraform.lock.hcl`.

**A9. What environment variables configure Azure auth?**
**Answer:** `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, `ARM_TENANT_ID`, `ARM_SUBSCRIPTION_ID`, plus `ARM_USE_OIDC`/`ARM_OIDC_TOKEN` for OIDC.

**A10. What is `data "azurerm_client_config"`?**
**Answer:** A data source returning the current authenticated client's object_id, tenant_id, and subscription_id — often needed for Key Vault access policies.

**A11. How do you authenticate locally during development?**
**Answer:** `az login`, then run Terraform with no explicit credentials — the provider uses the CLI's session (with a warning that it's not recommended for production).

**A12. What is a service principal in Azure terms?**
**Answer:** An application identity (client ID + secret/cert) used for automation, granted RBAC roles on subscriptions/resource groups.

**A13. What is the `azurerm` provider's `partner_id` argument?**
**Answer:** A GUID identifying the partner/tool deploying resources — used for attribution in Azure support/telemetry.

**A14. What is `skip_provider_registration`?**
**Answer:** A provider argument to skip auto-registering resource providers — useful when the identity lacks permission to register providers.

**A15. What is `use_oidc = true`?**
**Answer:** Enables OIDC (token-based) authentication instead of a client secret — the recommended CI approach.

## Case B — Advanced / Senior

**B1. Compare authentication options and when to use each.**
**Answer:** Azure CLI (interactive dev), service principal + secret (legacy automation), service principal + certificate (longer-lived, needs management), managed identity (from Azure-hosted runners), OIDC federation (CI, no secrets). Prefer OIDC/managed identity where possible.

**B2. How do you structure a multi-subscription Terraform codebase?**
**Answer:** One provider alias per subscription with explicit `subscription_id`, route resources by alias, keep separate state per subscription, and share modules. Document which alias maps to which environment.

**B3. What is the difference between the `azurerm` and `azuread` providers for role assignments?**
**Answer:** `azurerm_role_assignment` assigns roles at ARM scope (subscription/RG/resource); `azuread` manages directory-level roles and the objects themselves (app registrations, groups). They're frequently used together.

**B4. How does the `features {}` block affect upgrades between provider major versions?**
**Answer:** New major versions often move previously implicit behaviors into `features {}` (or change defaults), so upgrading without reviewing the changelog can change how resources are deleted/updated. Pin and review before bumping majors.

**B5. What is `azapi` and when would you reach for it?**
**Answer:** A provider that sends raw ARM JSON. Use it for brand-new Azure features or properties the `azurerm` provider hasn't implemented yet, as a bridge until native support lands.

**B6. How do you make provider configuration DRY across environments?**
**Answer:** Put the provider + backend in a shared partial config (Terragrunt `generate` blocks, or a base module/`providers.tf` per environment directory) so each environment only varies by subscription/state key.

**B7. What is the risk of broad Contributor role for the Terraform service principal?**
**Answer:** Compromised credentials can change/delete anything. Use least privilege: scoped resource groups, custom roles limited to the resource types Terraform manages, and separate plan/apply identities.

**B8. How do you handle a provider API that's eventually consistent?**
**Answer:** The `azurerm` provider retries async operations, but cross-resource races may need `depends_on` or a `time_sleep`/`azapi` wait. Test for known races (e.g. role assignment propagation) in your pipeline.

**B9. How do you deploy Terraform from inside Azure (e.g. a DevOps agent or VM)?**
**Answer:** Use a user-assigned managed identity on the agent/VM, grant it roles, and configure the provider to use managed identity (via `ARM_USE_MSI=true` or environment defaults).

**B10. What is the `metadata_host`/endpoint override for?**
**Answer:** Pointing the provider at Azure Government or sovereign clouds (e.g. `environment = "usgovernment"`), which use different endpoints than public Azure.

**B11. How do you pin a specific provider release in a module vs a root?**
**Answer:** Version constraints belong in each root module's `required_providers` (child modules inherit the root's provider). Pinning at the root keeps the whole tree consistent.

**B12. How do you test provider upgrades safely?**
**Answer:** Run `terraform plan` in a sandbox subscription with the new provider version, review the changelog for `features {}`/default changes, use policy-as-code to catch risky diffs, and promote through environments.

## Case C — Scenario

**C1. Your pipeline's client secret expired and all applies failed overnight.**
**Answer:** Generate a new secret (or better, switch to OIDC/certificate), update the credential store, and add expiry monitoring/rotation. Prefer OIDC so this class of failure disappears.

**C2. A teammate's apply created resources in the wrong subscription.**
**Answer:** They used the default provider/subscription instead of the right alias. Add validation (locals/`precondition`) asserting subscription, restrict RBAC so only intended subscriptions are writable, and document aliases.

**C3. You need to deploy a brand-new Azure feature the `azurerm` provider doesn't support yet.**
**Answer:** Use `azapi_resource`/`azapi_update_resource` with the ARM JSON for that resource type until the `azurerm` provider adds native support, then migrate with import/state mv.

**C4. A security review wants no long-lived secrets for Terraform in CI.**
**Answer:** Move to OIDC federation (GitHub Actions/Azure DevOps) with a federated credential on the service principal, remove client secrets, and use short-lived tokens with least-privilege roles.

**C5. Two teams manage different Azure subscriptions but want shared modules.**
**Answer:** Publish shared modules in a Git repo (tagged releases) or a private registry, keep provider config per environment (aliases/partial configs), and keep state separate per subscription.

**C6. A provider major upgrade is released; how do you plan the rollout?**
**Answer:** Read the upgrade guide, run plan-only against a sandbox, adapt `features {}`/renamed resources, use `moved` blocks where resources were renamed, then roll out environment by environment with the version pinned per env.
