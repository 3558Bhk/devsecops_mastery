# Terraform Storage Accounts (Azure) — Interview Questions

> **Cloud:** Azure · **IaC Tool:** Terraform · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~5 min

---

## Case A — Basic

**A1. What is an Azure Storage Account in Terraform?**
**Answer:** `azurerm_storage_account` — the top-level container for blobs, files, queues, and tables, with a globally unique name and a region.

**A2. Why must storage account names be globally unique and lowercase?**
**Answer:** The name forms part of the public endpoint (`name.blob.core.windows.net`), so it must be globally unique, 3–24 chars, lowercase letters/numbers only.

**A3. What is `account_tier` and `account_replication_type`?**
**Answer:** Tier = `Standard` or `Premium` (SSD-backed); replication = `LRS`, `ZRS`, `GRS`, `GZRS`, `RAGRS` (redundancy level).

**A4. What is a blob container?**
**Answer:** `azurerm_storage_container` — a named group of blobs with an access level (`private`, `blob`, `container`).

**A5. What is `azurerm_storage_blob`?**
**Answer:** Uploads a file/object into a container — used for static assets/config, not runtime app data.

**A6. How do you enable the static website feature?**
**Answer:** `azurerm_storage_account` `static_website { index_document, error_404_document }` for hosting SPA/static sites.

**A7. What is `min_tls_version` and why set it?**
**Answer:** The minimum TLS version for the account — set `TLS1_2` for security compliance.

**A8. What is `allow_nested_items_to_be_public`?**
**Answer:** A toggle controlling whether blobs/containers can be public when the account allows public access — keep false for private-by-default.

**A9. What is a shared access signature (SAS)?**
**Answer:** A time-limited, scoped token granting access to storage without the account key — often used for uploads/downloads.

**A10. How do you get the account's access key in Terraform?**
**Answer:** `data "azurerm_storage_account" "sa" { ... }` exposes `primary_access_key`/`primary_connection_string`.

**A11. What is `azure_files_authentication`?**
**Answer:** Configures Active Directory/Entra ID authentication for Azure Files shares (instead of storage key).

**A12. What is a file share?**
**Answer:** `azurerm_storage_share` — an SMB file share for Azure Files.

**A13. What is a queue?**
**Answer:** `azurerm_storage_queue` — a message queue inside the storage account.

**A14. What is a table?**
**Answer:** `azurerm_storage_table` — a NoSQL table in the account.

**A15. How do you enable soft delete and versioning?**
**Answer:** `blob_properties { delete_retention_policy, versioning_enabled, container_delete_retention_policy }` on the account.

## Case B — Advanced / Senior

**B1. How do you choose a replication type (LRS/ZRS/GRS/GZRS/RAGRS)?**
**Answer:** LRS: 3 copies in one datacenter; ZRS: across zones in a region; GRS: LRS + async copy to a secondary region; RA-GRS adds read access to the secondary; GZRS combines zone + geo. Balance durability, cost, and RTO requirements.

**B2. What is the difference between hot/cool/archive access tiers?**
**Answer:** Hot: highest storage cost, lowest access cost (frequent data). Cool: cheaper storage, higher access (infrequent, 30-day min). Archive: cheapest storage, hours to rehydrate (long-term retention). Set per-blob or via lifecycle rules.

**B3. How do you implement lifecycle management with Terraform?**
**Answer:** `azurerm_storage_management_policy` with rules that transition blobs to cooler tiers and delete them after N days, with filters on prefix/blob type.

**B4. How do you make storage private and reachable only from your VNet?**
**Answer:** Disable public access (`allow_nested_items_to_be_public = false`, `public_network_access_enabled = false`), then add a private endpoint + private DNS zone for private access.

**B5. What is `network_rules` on a storage account?**
**Answer:** Firewall rules restricting which networks/IPs/subnets (via service endpoints) can reach the account — a first line of defense before private endpoints.

**B6. How do you use customer-managed keys (CMK) for storage encryption?**
**Answer:** Create a Key Vault key, grant the storage account's identity access, and set `identity` + `customer_managed_key` on the account (or `encryption` block) referencing the key.

**B7. How do you use the storage account as the Terraform state backend?**
**Answer:** A dedicated storage account/container with the `azurerm` backend (blob leasing for locking, versioning/soft-delete for recovery) — usually bootstrapped outside the config it serves.

**B8. How do you enable hierarchical namespace (ADLS Gen2) and when?**
**Answer:** `is_hns_enabled = true` (set at creation) turns the account into Data Lake Storage Gen2 for analytics/Spark workloads — it can't be toggled later.

**B9. How do you share files with Entra ID instead of storage keys?**
**Answer:** `azure_files_authentication { directory_type = "AADKERB" }` (or Entra Kerberos) and assign share-level RBAC so users authenticate with their identity.

**B10. What is `azurerm_storage_account_network_rules` (separate resource)?**
**Answer:** A dedicated resource for network rules — useful when rules are managed separately from the account (e.g. by a networking module).

**B11. How do you handle the globally-unique name constraint in reusable modules?**
**Answer:** Generate the name with a unique suffix (`random_string`/`random_id`, or env+region hash) and use `name = lower(...)` with validation — so each environment's account name is unique but predictable.

**B12. How do you replicate blobs across regions for DR?**
**Answer:** `azurerm_storage_object_replication` (object replication) pairs two accounts and copies specific containers, or rely on GRS/GZRS account-level geo-replication.

## Case C — Scenario

**C1. A security scan flags a storage account with public blob access.**
**Answer:** Set `allow_nested_items_to_be_public = false` (and `public_network_access_enabled = false` where possible), change container access to private, and add a policy check to keep new accounts locked down.

**C2. You need to retire old logs automatically to save cost.**
**Answer:** Add a `azurerm_storage_management_policy` rule: transition to cool after 30 days, archive after 90, delete after 365 — filtered to the logs container/prefix.

**C3. A storage account name is already taken in the target region.**
**Answer:** Regenerate the name with a unique suffix (env/region/random), update references, and re-apply — remember the name is immutable once created.

**C4. You must serve a static website over HTTPS with a custom domain.**
**Answer:** Enable `static_website` on the account, put the site in `$web`, front it with Front Door/CDN (for TLS + custom domain) or use the account's HTTPS endpoint — since custom domains aren't supported directly on storage.

**C5. An application can't reach storage after you disabled public access.**
**Answer:** Add a private endpoint + private DNS zone for the account (blob subresource) and ensure the app resolves to the private IP via the linked DNS zone, then update NSG/routing as needed.

**C6. Compliance requires all data encrypted with your own key and TLS 1.2+.**
**Answer:** Set `min_tls_version = "TLS1_2"`, configure `customer_managed_key` (with the account's identity granted Key Vault access), and add policy-as-code to enforce both on new accounts.
