# Terraform Key Vault (Azure) — Interview Questions

> **Cloud:** Azure · **IaC Tool:** Terraform · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~6 min

---

## Case A — Basic

**A1. What is Azure Key Vault in Terraform?**
**Answer:** `azurerm_key_vault` — a managed store for secrets, keys, and certificates, with access control and auditing.

**A2. How do you declare a Key Vault?**
**Answer:** `resource "azurerm_key_vault" "kv" { name = ... ; resource_group_name = ... ; location = ... ; tenant_id = ... ; sku_name = "standard" }`.

**A3. What is `tenant_id` on a Key Vault?**
**Answer:** The Azure AD tenant the vault belongs to — usually `data "azurerm_client_config"`'s tenant_id.

**A4. How do you store a secret in Terraform?**
**Answer:** `azurerm_key_vault_secret` with `name` and `value`, e.g. a database password or connection string.

**A5. What is `azurerm_key_vault_key`?**
**Answer:** A cryptographic key in the vault (for encryption/disk encryption sets/customer-managed keys).

**A6. What is `azurerm_key_vault_certificate`?**
**Answer:** A TLS certificate stored in the vault, referenced by App Gateway/App Service listeners.

**A7. What is an access policy?**
**Answer:** A per-vault permission grant (`azurerm_key_vault_access_policy`) to a principal (user/SP/managed identity) — the legacy access model.

**A8. What is `enable_rbac_authorization`?**
**Answer:** Switches the vault to Azure RBAC roles instead of access policies — the modern, consistent model.

**A9. What is soft delete and purge protection?**
**Answer:** `soft_delete_retention_days` and `purge_protection_enabled` — retain deleted secrets/keys/vaults for recovery and prevent permanent purging (required for production).

**A10. How do you reference a secret in another resource?**
**Answer:** `data "azurerm_key_vault_secret" "s" { ... }` or a Key Vault reference string (`@Microsoft.KeyVault(SecretUri=...)`) in app settings.

**A11. What is `azurerm_key_vault_access_policy` for the current client?**
**Answer:** Granting the deploying Terraform identity access (often `data.azurerm_client_config`), so it can manage secrets in the vault it creates.

**A12. What is network ACL on a Key Vault?**
**Answer:** `network_acls` restricting which networks/IPs can reach the vault — or use private endpoints for full isolation.

**A13. What is a key version and secret version?**
**Answer:** Keys/secrets are versioned; each update creates a new version (`versionless_id`/`versionless_secret_id` reference the latest).

**A14. What is `azurerm_key_vault_managed_hardware_security_module`?**
**Answer:** A managed HSM (dedicated hardware) for higher-assurance key storage — versus the standard shared Key Vault.

**A15. How do you output a secret's ID without exposing its value?**
**Answer:** Output the secret's `id` or `versionless_id` (not `value`), and mark any value outputs `sensitive`.

## Case B — Advanced / Senior

**B1. Access policies vs RBAC for Key Vault — how do you choose and migrate?**
**Answer:** RBAC is the Azure-wide standard (roles like `Key Vault Secrets User`), easier to audit and scope; access policies are vault-specific. New vaults should use `enable_rbac_authorization = true`; migrate existing ones by mapping policies to roles.

**B2. How do you rotate secrets managed in Terraform?**
**Answer:** For values Terraform owns, update the secret (new version) and restart/redeploy consumers. For automated rotation, use Key Vault's built-in rotation policies (`azurerm_key_vault_certificate`/key rotation) or a function, and have apps fetch latest via `versionless` references.

**B3. How do you avoid secrets leaking into Terraform state?**
**Answer:** State stores secret values — protect the state backend (encryption, access control, no public access). Mark values `sensitive` so logs/plans redact them, and consider managing only references (not values) where possible.

**B4. What is the Key Vault reference syntax in app settings and how does auth work?**
**Answer:** `@Microsoft.KeyVault(SecretUri=https://vault.vault.azure.net/secrets/name/version)` — the app's managed identity resolves it at runtime, so the actual value never sits in app settings.

**B5. How do you use customer-managed keys with a disk encryption set?**
**Answer:** Create `azurerm_key_vault_key` (RSA), grant the Disk Encryption Set's identity access, create `azurerm_disk_encryption_set`, and reference it on disks — enabling CMK encryption for VMs.

**B6. How do you configure private access to Key Vault?**
**Answer:** `azurerm_private_endpoint` for the vault + a private DNS zone (`privatelink.vaultcore.azure.net`), and set `public_network_access_enabled = false` so only VNet/private traffic reaches it.

**B7. What is the difference between keys, secrets, and certificates in the vault?**
**Answer:** Keys = crypto keys (encrypt/decrypt/sign, e.g. CMK); secrets = arbitrary values (passwords, connection strings); certificates = TLS certs with renewal metadata. They have different permissions and lifecycles.

**B8. How do you grant a specific principal access to only one secret?**
**Answer:** With RBAC, scope the role assignment to the secret's scope (or use fine-grained data-plane roles with conditions); with access policies, per-secret policies aren't supported (vault-level only) — RBAC is the finer-grained path.

**B9. How do you handle the "vault access for the deployer" problem cleanly?**
**Answer:** Grant the deploying principal the minimal role (e.g. `Key Vault Secrets Officer`) at the vault scope via `azurerm_role_assignment`, or an access policy — and keep that grant separate from app principals.

**B10. What is `azurerm_key_vault_certificate` lifecycle and renewal?**
**Answer:** Certificates can auto-renew (with `certificate_policy` + auto-renewal on) when integrated with a CA; renewals create new versions, and App Gateway/App Service pick up the latest via `versionless` references.

**B11. How do you structure secrets across environments?**
**Answer:** A vault per environment (or per app+env), managed by a module that takes a secrets map input and creates `azurerm_key_vault_secret`s, with values injected from a secure store (not committed to Git).

**B12. What are the recovery/backup considerations for Key Vault?**
**Answer:** Soft delete (default) + purge protection (recommended) retain deleted items; vaults can also be backed up/restored for DR. Recreate-from-config is possible but restores real values only if you have them stored elsewhere.

## Case C — Scenario

**C1. A secret was accidentally deleted; how do you recover it?**
**Answer:** With soft delete enabled, recover the deleted secret (via portal/CLI/Terraform `azurerm_key_vault_secret` re-import) within the retention window. With purge protection, permanent deletion is blocked entirely.

**C2. An app can't read a secret after you switched the vault to RBAC.**
**Answer:** The old access policy doesn't map automatically — grant the app's identity the `Key Vault Secrets User` role at the vault (or secret) scope, then verify. Check the app uses the identity and the reference resolves.

**C3. Compliance requires secrets encrypted with your own key and vault purge-protected.**
**Answer:** Enable purge protection + soft delete, and use a customer-managed key (managed HSM or Key Vault key) where required — document and enforce via policy-as-code.

**C4. A certificate is about to expire and auto-renewal isn't working.**
**Answer:** Check the certificate policy's renewal settings and the CA/issuer integration; if renewal is managed elsewhere, update the cert in Terraform. Alert on upcoming expirations via `azurerm_monitor_metric_alert`/scheduled check.

**C5. You must share one secret with two apps in different resource groups.**
**Answer:** Keep the secret in one vault, grant both apps' managed identities the secret read role (RBAC) at the vault/secret scope, and have each app reference it via Key Vault reference or SDK.

**C6. State contains a plaintext secret and an auditor flagged it.**
**Answer:** Protect the state backend (private endpoint/encryption/least-privilege), mark the variable/output `sensitive`, and consider storing only the Key Vault reference in config while keeping the value solely in the vault.
