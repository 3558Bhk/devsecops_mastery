# Identity Management in Azure Storage — Interview Questions

> **Cloud:** Azure · **Category:** Storage · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~9 min

---

## JSON File Format

Storage identity management uses **RBAC role assignments** (JSON) on the storage account, referencing Entra ID identities and data-plane role definitions.

```json
{
  "properties": {
    "roleDefinitionId": "/subscriptions/<sub>/providers/Microsoft.Authorization/roleDefinitions/ba92f5b4-2d11-453d-a403-e96b0029c9fe",
    "principalId": "6f2b...-managed-identity-objectId",
    "principalType": "ServicePrincipal",
    "scope": "/subscriptions/<sub>/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/mystoreacct"
  }
}
```

**Key fields:** `roleDefinitionId` (e.g. **Storage Blob Data Contributor** = `ba92f5b4-2d11-453d-a403-e96b0029c9fe`) · `principalId`/`principalType` (User/Group/ServicePrincipal) · `scope`. Role **definitions** themselves are JSON (`Microsoft.Authorization/roleDefinitions` with `permissions[].actions`).


## Case A — Basic

**A1. What is identity management in Azure Storage?**
**Answer:** Controlling **who/what can access** storage accounts and data using **Microsoft Entra ID (Azure AD) identities** and RBAC — instead of (or in addition to) storage account keys and SAS tokens.

**A2. What are the main ways to authorize storage access?**
**Answer:** **Entra ID + RBAC** (identity-based, recommended), **Shared Key** (account key — discouraged), **SAS tokens** (scoped, time-limited), and **anonymous/public access** (should be disabled).

**A3. What is the difference between the management plane and the data plane?**
**Answer:** **Management plane** = account administration (create/delete accounts, keys) via RBAC roles like `Storage Account Contributor`. **Data plane** = reading/writing blobs/files/queues via roles like `Storage Blob Data Contributor`. They are separate permission sets.

**A4. What are the key data-plane RBAC roles?**
**Answer:** **Storage Blob Data Reader** (read), **Storage Blob Data Contributor** (read/write/delete), **Storage Blob Data Owner** (data + POSIX/ownership), plus equivalents for Files and Queues.

**A5. What is a managed identity?**
**Answer:** An Entra ID identity automatically managed by Azure for a resource (VM, App Service, Function) — used to authenticate to storage (and other services) **without credentials in code**.

**A6. How does a VM access blob storage with a managed identity?**
**Answer:** Enable the VM's **system-assigned managed identity**, grant it a **data-plane RBAC role** (e.g., Storage Blob Data Contributor) on the storage account, and use the Azure SDK (DefaultAzureCredential) — the VM gets tokens automatically.

**A7. What is shared key access and why is it risky?**
**Answer:** Using the **account key** grants full access to the entire account. Risk: keys are long-lived, can leak, and can't be scoped/audited per-user. Best practice: **disable shared key access** and use Entra ID.

**A8. What is Azure AD (Entra ID) authentication for Azure Files?**
**Answer:** File shares can authenticate via **Entra ID (Kerberos)** or **AD DS** — letting you apply **NTFS-style ACLs** to SMB shares instead of a single shared key.

**A9. What is the difference between RBAC and ACLs (POSIX) for Data Lake?**
**Answer:** **RBAC** = role assignments (coarse, account/container level). **ACLs** = fine-grained per-file/per-directory POSIX permissions (in hierarchical namespace / ADLS Gen2). Effective access = both are evaluated (RBAC + ACL).

**A10. What is a SAS token?**
**Answer:** A signed URL granting scoped, time-limited access (permissions, expiry, IP) to storage resources — without exposing the account key.

**A11. What is a stored access policy?**
**Answer:** A named policy on a container/share that SAS tokens reference — letting you **revoke or change** access centrally without reissuing SAS URLs.

**A12. What is anonymous (public) access and how do you prevent it?**
**Answer:** Allowing unauthenticated read of containers/blobs. Prevent by setting **"Allow Blob public access" = Disabled** at the account level and enforcing via **Azure Policy**.

**A13. How do you audit who accessed storage?**
**Answer:** **Storage Analytics logs / Azure Monitor diagnostics** (data-plane requests with the caller identity), **Activity Log** (management-plane), and **Microsoft Defender for Storage** (security alerts). Entra ID sign-in logs for identity events.

**A14. What is Azure Key Vault's role in storage access?**
**Answer:** Key Vault can store **account keys** (with rotation) or **customer-managed encryption keys**, and secrets/SAS — centralizing secret management for storage.

**A15. What is a service principal?**
**Answer:** An **application identity** in Entra ID (client ID + secret/certificate) used by non-Azure apps/CI pipelines to authenticate to storage via RBAC.

---

## Case B — Advanced (Senior)

**B1. Explain the full identity-based access model: Entra ID → RBAC (management + data plane) → resource.**
**Answer:** A principal (user, group, managed identity, service principal) authenticates to Entra ID and gets a token. **Management-plane RBAC** controls account administration; **data-plane RBAC** controls blob/file/queue operations. Both are evaluated independently — you can have full account admin but zero data access, or vice versa. This separation is core to least privilege.

**B2. How do you migrate from shared key/SAS to Entra ID + managed identities (a secure-access project)?**
**Answer:** (1) Inventory key/SAS usage (logs). (2) Create managed identities/service principals for apps. (3) Assign least-privilege **data-plane roles**. (4) Update code to use **DefaultAzureCredential**. (5) Replace remaining SAS with short-lived, policy-backed SAS. (6) **Disable shared key access** and monitor for breakage. (7) Enforce with Azure Policy.

**B3. How does RBAC + ACL composition work in ADLS Gen2 (hierarchical namespace)?**
**Answer:** In ADLS Gen2, **RBAC** grants broad access (container/folder-level, or all), while **ACLs** grant fine-grained per-path access. A request is allowed if it passes RBAC **and** ACL evaluation. Best practice: coarse RBAC (e.g., execute/read on container) + fine ACLs per directory/file; use `Storage Blob Data Owner` for ACL management.

**B4. What is the "Storage Blob Data Owner" vs "Contributor" vs "Reader" distinction, and when does Owner matter?**
**Answer:** Reader = read only. Contributor = read/write/delete. **Owner** adds the ability to **manage POSIX ACLs** (set ownership/permissions) in hierarchical namespaces. Use Owner for the data-engineering identity that manages folder ACLs; Contributor for app data access; Reader for auditors/consumers.

**B5. How does Azure AD (Entra ID) authentication work for Azure Files SMB shares (and the limitations)?**
**Answer:** Entra ID Kerberos (or AD DS) lets users mount shares and be authorized by **NTFS ACLs** — enabling per-user permissions and auditing. Limitations: Entra ID Kerberos historically requires Entra ID hybrid/joined devices and specific OS support; AD DS (on-prem/domain services) is the other path. Check current support matrix.

**B6. What are SAS best practices (scoping, expiry, revocation, and risks)?**
**Answer:** Use **service SAS** over account SAS, **short expiry**, **least privileges** (read-only where possible), **IP restrictions**, **HTTPS-only**, and always reference a **stored access policy** so you can revoke. Risks: SAS leak = time-bomb access; hard to revoke without stored policies. Prefer Entra ID when the caller can authenticate.

**B7. How do you prevent anonymous access and enforce secure transfer/encryption at org scale?**
**Answer:** Set **"Allow Blob public access" = Disabled** on all accounts, **deny public network access** (private endpoints only) where possible, require **TLS 1.2+** (secure transfer), **disable shared key**, and enforce all via **Azure Policy** (built-in policies: `storageAccounts/disablePublicAccess`, require secure transfer, etc.) across subscriptions.

**B8. How does Defender for Storage protect and audit identity-related threats?**
**Answer:** Defender for Storage monitors the **data plane** for anomalies: unusual access patterns, **malware scans on uploads**, suspicious SAS usage, sensitive-data exposure detection, and generates **security alerts** (with the caller identity) — feeding Microsoft Sentinel. It complements RBAC by detecting abuse of legitimate identities.

**B9. How do you implement least privilege with role assignments and Azure AD groups (no per-user role sprawl)?**
**Answer:** Assign roles to **Entra ID groups** (e.g., `Group-DataReaders`, `Group-BlobContributors`), not individuals; use **scoped assignments** (subscription → resource group → storage account → container where supported); use **custom roles** for unusual combinations; and review with **Access Reviews** + **PIM** (just-in-time) for privileged data roles.

**B10. How does customer-managed key (CMK) encryption interact with identity (Key Vault access)?**
**Answer:** For **CMK**, the storage account uses a key in **Key Vault**, and the storage account's **managed identity** must be granted `get/wrap/unwrap` on that key. This ties encryption to Key Vault identity/access — revoking the key (or the identity's access) effectively locks the data. Design Key Vault access (RBAC + key permissions) carefully.

**B11. What is conditional access / identity protection for storage access?**
**Answer:** While storage data-plane RBAC is Entra ID-based, you can apply **Conditional Access** policies (MFA, device compliance, location) to the **Entra ID tokens** used for storage access (e.g., require MFA for privileged storage roles via PIM), and **Identity Protection** signals (risky user) can block/require MFA — adding identity-driven security on top of RBAC.

**B12. How do you audit and report "who accessed what" for compliance?**
**Answer:** Enable **storage diagnostics (data-plane logs)** → Log Analytics; query by **caller identity**, operation, resource, and time; retain per compliance; use **Activity Log** for management-plane changes; export to **Sentinel** for correlation and alerts. Provide read-only access to auditors via RBAC Reader roles on the logs.

---

## Case C — Scenario

**C1. Scenario:** An app stores blobs using a hardcoded account key that was leaked.
**Question:** Remediate + redesign.
**Answer:** Immediately **rotate both account keys**, investigate access logs for misuse, then **remove the key from code**: use a **managed identity** + `Storage Blob Data Contributor` role, and **disable shared key access** on the account. Enforce via Azure Policy going forward, and set up Defender for Storage alerts.

**C2. Scenario:** A VM must read/write a specific container, and nothing else in the storage account.
**Question:** Grant least privilege.
**Answer:** Enable the VM's **system-assigned managed identity**, then assign **Storage Blob Data Contributor** **scoped to that container** (role assignment at the container resource level, or use a custom role/condition on the container path). The VM then has write access only to that container — no account-wide access, no keys.

**C3. Scenario:** A CI pipeline (GitHub Actions) must deploy files to a container without storing secrets in the repo.
**Question:** Implement it.
**Answer:** Use **Workload Identity Federation** (or an Entra ID **service principal** with a certificate): federate the GitHub repo to Entra ID, grant the resulting identity **Storage Blob Data Contributor** on the container, and have the pipeline use `Azure/login` + AzCopy/Azure CLI with the federated token — no secrets stored. Alternatively, a short-lived SAS with a stored policy.

**C4. Scenario:** Two teams share one storage account; team A must never read team B's containers.
**Question:** Enforce isolation.
**Answer:** Use **separate containers** per team with **RBAC scoped to each container** (assign each team's Entra ID group its container's roles only), or use **different storage accounts** for stronger isolation. Avoid account-level roles for both teams. Optionally use **ABAC (attribute-based conditions)** on role assignments to further restrict by prefix/tags.

**C5. Scenario:** A data lake needs per-folder permissions: analysts read `/sales`, data engineers read/write `/ingest`, and no one reads `/hr`.
**Question:** Design with ADLS Gen2.
**Answer:** Enable **hierarchical namespace (ADLS Gen2)**, assign coarse RBAC (e.g., `Storage Blob Data Reader` on the container) and then **fine-grained ACLs**: grant analysts `r-x` on `/sales`, engineers `rwx` on `/ingest`, and remove/deny `/hr` for everyone except HR's group. Effective access = RBAC + ACL both allow. Manage via an ownership identity (`Storage Blob Data Owner`).

**C6. Scenario:** An auditor needs read-only access to **audit logs** of storage, but no data access at all.
**Question:** Grant it cleanly.
**Answer:** Grant the auditor's group the **`Reader` (management-plane)** role on the storage account/resource group (to view settings, metrics, and Activity Logs) and access to the **Log Analytics workspace** where storage **data-plane diagnostics** are sent (workspace Reader) — explicitly **not** any data-plane storage role. This gives audit visibility without touching data.
