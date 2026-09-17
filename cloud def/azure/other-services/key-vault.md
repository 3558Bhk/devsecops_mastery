# Azure Key Vault — Interview Questions

> **Cloud:** Azure (Other Services) · **Category:** Security / Secrets · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~8 min

---

## JSON File Format

Key Vaults are ARM JSON (`Microsoft.KeyVault/vaults`), and secret **values** are stored as JSON strings (key-value pairs), like Secrets Manager.

```json
{
  "type": "Microsoft.KeyVault/vaults",
  "apiVersion": "2022-07-01",
  "name": "myVault",
  "properties": {
    "tenantId": "00000000-0000-0000-0000-000000000000",
    "sku": { "family": "A", "name": "standard" },
    "enableSoftDelete": true,
    "enablePurgeProtection": true,
    "networkAcls": { "defaultAction": "Deny", "bypass": "AzureServices" }
  }
}
```

**Key fields:** `tenantId` · `sku` (standard / premium) · `enableSoftDelete` / `enablePurgeProtection` · `networkAcls` (private access). Secret value example: `{ "username": "appuser", "password": "S3cr3t!" }` — retrieved as `value` via REST/SDK.


## Case A — Basic

**A1. What is Azure Key Vault?**
**Answer:** A managed service for securely storing and accessing **secrets, keys, and certificates** — with encryption, access control, and audit logging — so applications never hardcode credentials.

**A2. What are the three object types?**
**Answer:** **Secrets** (passwords, connection strings), **Keys** (cryptographic keys for encryption/signing), and **Certificates** (TLS certs with auto-renewal).

**A3. How is data protected in Key Vault?**
**Answer:** **Encrypted at rest** (HSM- or software-backed keys), **in transit** (TLS), and each object has **versions** and metadata.

**A4. What are the two access models?**
**Answer:** **Vault access policies** (legacy, per-vault) and **Azure RBAC** (modern, role-based, recommended) — both control who can read/write secrets/keys/certs.

**A5. What is the difference between a secret, a key, and a certificate in Key Vault?**
**Answer:** Secret = arbitrary string (password). Key = cryptographic key material (never exported if HSM). Certificate = X.509 cert with **auto-renewal** + private key — often used for TLS.

**A6. What is a managed identity's role with Key Vault?**
**Answer:** Apps (VMs, App Services) use **managed identities** to authenticate to Key Vault and retrieve secrets **without credentials in code** — the standard secret-access pattern.

**A7. What is soft delete and purge protection?**
**Answer:** **Soft delete** = deleted objects/vaults are recoverable for a retention period. **Purge protection** = prevents permanent deletion during retention (even admins can't purge). Both are security best practices (on by default for new vaults).

**A8. How does Key Vault integrate with App Service?**
**Answer:** App Service supports **Key Vault references** (`@Microsoft.KeyVault(SecretUri=...)`) in app settings — the app reads the secret value via its managed identity.

**A9. What is the difference between Key Vault and App Configuration?**
**Answer:** Key Vault = **secrets/keys/certs** (sensitive). App Configuration = **non-secret config** (feature flags, settings) — often used together (App Config references Key Vault for secrets).

**A10. What are Key Vault certificates used for?**
**Answer:** **TLS/SSL certs** (with auto-renewal and notifications), client auth certs, and signing — integrated with App Service/App Gateway/Front Door.

**A11. How do you audit Key Vault access?**
**Answer:** **Key Vault logging/diagnostics** (to Log Analytics/Storage/Event Hubs) records every operation (who, what, when) — plus **Activity Log** for management-plane changes.

**A12. What is a key vault URI?**
**Answer:** `https://<vault-name>.vault.azure.net/` — the endpoint for accessing secrets/keys/certs via SDK/CLI/REST.

**A13. What is HSM-backed vs software-protected keys?**
**Answer:** **HSM-backed** (Premium tier / Managed HSM) = keys stored in FIPS 140-2/3 hardware modules, never exported. **Software-protected** = keys in software. HSM for highest compliance/security.

**A14. How does Key Vault help with secrets rotation?**
**Answer:** Secrets are **versioned** — you add a new version and apps fetch the latest; **Key Vault-managed storage account keys** and **certificate auto-renewal** automate rotation for specific types.

**A15. What is Managed HSM?**
**Answer:** A fully managed, single-tenant **FIPS 140-2 Level 3** HSM service — for the most stringent key-protection/compliance requirements (vs multi-tenant Key Vault Premium).

---

## Case B — Advanced (Senior)

**B1. Explain the two access models (vault access policies vs RBAC) and how to choose.**
**Answer:** **Vault access policies** = per-vault, per-principal permission lists (legacy, fine-grained but not role-based). **Azure RBAC** = standard roles (`Key Vault Secrets Officer`, `Key Vault Reader`) integrated with Azure's role model + PIM + Conditions. **RBAC is recommended** (unified governance); use access policies only if migrating legacy. You must pick one model per vault (not both).

**B2. What are the data-plane vs management-plane permissions in Key Vault?**
**Answer:** **Management plane** (Azure RBAC) = create/delete vault, set policies (e.g., Contributor). **Data plane** (RBAC/access policies) = operate on **secrets/keys/certs** (get/set/list). They're independent — you can admin a vault without reading its secrets, which is the security-critical separation.

**B3. How does Key Vault integrate with managed identities end-to-end (app → token → secret)?**
**Answer:** The app's **managed identity** requests an Entra ID token, then calls Key Vault with it; Key Vault validates the token and checks the **data-plane role** (e.g., Secrets User). No credentials are stored in the app — just the vault URI. This is the canonical secret-retrieval pattern.

**B4. What are the throttling limits and how do you design around them (caching)?**
**Answer:** Key Vault has **per-vault operation limits** (e.g., 2,000 requests/10s per vault for secrets, lower for some ops). High-volume apps must **cache secrets** (in memory, refresh on TTL/expiry) instead of calling per-request. This avoids throttling (HTTP 429) and reduces cost/latency.

**B5. How does certificate auto-renewal work, and what are the notification/rotation patterns?**
**Answer:** Key Vault can **auto-renew** certificates with a supported issuer (DigiCert/GlobalSign or an integrated CA) before expiry and notify via the configured **contacts**. App Service/App Gateway can pull renewed certs. For secrets, use **Event Grid events** (SecretNearExpiry) to trigger automated rotation.

**B6. What is Key Vault's role in CMK (customer-managed keys) for storage/DBs/encryption?**
**Answer:** Services (Storage, SQL, VMs) can encrypt their data with a **customer-managed key** stored in Key Vault; the service's **managed identity** uses the key via Key Vault. **Revoking the key (or access) effectively locks the data** — a powerful security control, but risky if misconfigured.

**B7. How do you share a vault across subscriptions/regions and replicate for DR?**
**Answer:** Vaults are **region-scoped** — for DR, replicate secrets to a **secondary vault** (scripted/Azure Backup for Key Vault, or replicate at the app level). Cross-subscription access via **RBAC** (grant identities in other subscriptions). **Backup** vaults (secrets/keys/certs) to restore elsewhere.

**B8. How do you monitor and alert on Key Vault (diagnostics, Event Grid, anomalies)?**
**Answer:** Send **diagnostics** to Log Analytics; alert on **failed access attempts**, **secret near-expiry** (Event Grid `SecretNearExpiry`), **certificate near-expiry**, **purge attempts**, and **unusual access** (Defender for Key Vault — detects suspicious/anomalous patterns). Route to Sentinel for correlation.

**B9. What is "Defender for Key Vault" and what does it detect?**
**Answer:** **Microsoft Defender for Key Vault** provides threat detection: unusual access patterns, high-volume secret reads (possible exfiltration), access from suspicious IPs, and unusual service principals — generating security alerts (Sentinel-integrated). Adds a detection layer on top of RBAC.

**B10. How do you design secret rotation for databases (e.g., SQL) using Key Vault?**
**Answer:** Store DB creds as a versioned **secret**; use **Event Grid `SecretNearExpiry`** (or a schedule) to trigger a **rotation function/runbook** that generates a new password, updates the DB, and adds a new secret version; apps read the latest version (cached with TTL). Key Vault's versioning + events make this automatable.

**B11. What are the compliance considerations (HSM, FIPS, purge protection, regionality)?**
**Answer:** For regulated data: **HSM-backed keys** (Premium/Managed HSM, FIPS 140-2/3), **purge protection + soft delete** (immutability), **private endpoints** (no public access), **RBAC + PIM** for access, and **region residency** (keys don't leave the region). Document via diagnostics/Activity Logs for audit.

**B12. How does Key Vault support private access (private endpoints) and why disable public access?**
**Answer:** Deploy a **private endpoint** so the vault has a **private IP in your VNet** (reachable via private link from VMs/on-prem via VPN/ER); set **public network access = Disabled** so the vault is unreachable from the internet. This is the recommended hardening for production vaults.

---

## Case C — Scenario

**C1. Scenario:** An app hardcodes a DB connection string in its config; it leaked in a repo.
**Question:** Remediate with Key Vault.
**Answer:** Rotate the DB password; store the connection string as a **Key Vault secret**; grant the app's **managed identity** the `Key Vault Secrets User` role; have the app read the secret via SDK/Key Vault reference (App Service) with **caching**; add **secret scanning** in CI and remove secrets from the repo. Enable purge protection + soft delete.

**C2. Scenario:** A VM must read a secret, but you must ensure only that VM (not others) can access it.
**Question:** Configure least privilege.
**Answer:** Enable the VM's **system-assigned managed identity**, grant **only that identity** the data-plane role (`Key Vault Secrets User`) on the vault (RBAC model), and restrict the vault's **network** to a **private endpoint** in the VM's VNet. No shared service principals, no public access.

**C3. Scenario:** An app gets HTTP 429 (throttled) from Key Vault during traffic spikes.
**Question:** Diagnose and fix.
**Answer:** Key Vault throttles at ~2,000 ops/10s per vault — the app is calling it per request. Fix: **cache the secret in memory** at startup, refresh on TTL/expiry (or on 403/exception), and share the vault across fewer high-frequency readers (or use multiple vaults for extreme scale). This eliminates per-request calls.

**C4. Scenario:** A certificate for your public site expires next week and no one noticed.
**Question:** Prevent recurrence.
**Answer:** Use **Key Vault certificates with auto-renewal** (supported issuer) + **Event Grid `CertificateNearExpiry`** alerts and **contact notifications**; integrate the cert with App Service/App Gateway so renewal propagates automatically. Set up **alerts** 30/14/7 days before expiry and a runbook fallback.

**C5. Scenario:** You must prove to an auditor who accessed which secrets and when.
**Question:** How?
**Answer:** Enable **Key Vault diagnostics** → Log Analytics; every data-plane operation is logged (principal, operation, secret name, time). Query/export the logs for the audit period. Combine with **Activity Log** for management-plane changes and RBAC assignments. Retain logs per compliance policy.

**C6. Scenario:** A multi-region app needs the same secrets in two regions with failover capability.
**Question:** Design secret replication/DR.
**Answer:** Keep a **primary vault** in each region (or replicate via **Azure Backup for Key Vault** to a secondary vault, or a scripted sync). Apps read their **regional vault**; on regional failure, the app fails over to the secondary region's vault. Document the replication lag and test failover. (Key Vault itself isn't geo-replicated — you design the replication.)
