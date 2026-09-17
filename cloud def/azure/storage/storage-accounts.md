# Azure Storage Accounts — Interview Questions

> **Cloud:** Azure · **Category:** Storage · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~9 min

---

## JSON File Format

Storage accounts are ARM JSON (`Microsoft.Storage/storageAccounts`) — SKU (redundancy), kind, and security flags.

```json
{
  "type": "Microsoft.Storage/storageAccounts",
  "apiVersion": "2023-01-01",
  "name": "mystoreacct",
  "sku": { "name": "Standard_LRS" },
  "kind": "StorageV2",
  "properties": {
    "allowBlobPublicAccess": false,
    "minimumTlsVersion": "TLS1_2",
    "accessTier": "Hot",
    "encryption": { "keySource": "Microsoft.Storage", "services": { "blob": { "enabled": true } } }
  }
}
```

**Key fields:** `sku.name` (Standard_LRS/ZRS/GRS/GZRS or Premium_*) · `kind` (StorageV2) · `allowBlobPublicAccess` · `minimumTlsVersion` · `accessTier` (Hot/Cool). Containers are `Microsoft.Storage/storageAccounts/blobServices/containers`.


## Case A — Basic

**A1. What is an Azure Storage Account?**
**Answer:** A container that provides a unique namespace for Azure Storage services: **Blob** (objects), **File** (SMB shares), **Queue** (messages), **Table** (NoSQL), and **Disk** (managed disks) — with one billing/management unit.

**A2. What are the main storage services within a storage account?**
**Answer:** **Blob storage** (unstructured objects), **Azure Files** (SMB/NFS file shares), **Queue storage** (messaging), and **Table storage** (NoSQL key-value). (Managed disks use their own storage accounts.)

**A3. What is a blob and what are the blob types?**
**Answer:** A blob is an unstructured object (file/data). Types: **Block blobs** (text/binary, up to ~190.7 TiB), **Append blobs** (append-only, logs), and **Page blobs** (random read/write, used by VM disks).

**A4. What are the redundancy options (LRS, ZRS, GRS, GZRS)?**
**Answer:** **LRS** (3 copies, one datacenter), **ZRS** (copies across 3 availability zones), **GRS** (LRS + async copy to a secondary region), **GZRS** (ZRS + async secondary region). Higher redundancy = higher durability/cost.

**A5. What is the difference between LRS and GRS?**
**Answer:** LRS keeps 3 copies in **one** datacenter (survives drive/rack failure). GRS replicates to a **secondary region** (survives a regional outage) — for DR/compliance.

**A6. What are the access tiers?**
**Answer:** **Hot** (frequent access, higher storage cost, lower access cost), **Cool** (infrequent, 30-day min), **Cold** (rare, 90-day min), and **Archive** (very rare, offline, hours to rehydrate).

**A7. What is a container in blob storage?**
**Answer:** A logical grouping of blobs (like a folder/S3 bucket) that organizes objects and sets access policies.

**A8. What is a SAS (Shared Access Signature)?**
**Answer:** A signed URL granting **limited, time-bound access** to a storage resource (blob/container/share) without sharing the account key.

**A9. What is the account key and why should you avoid using it?**
**Answer:** The full-access credential for the storage account. Avoid sharing it; prefer **Microsoft Entra ID + RBAC**, **SAS tokens**, or **managed identities**.

**A10. How do you secure a storage account?**
**Answer:** **Private endpoints** (no public exposure), **firewall/network rules**, **RBAC** (Entra ID), **SAS** for limited access, **encryption at rest (default)** and in transit (TLS), and **shared key access disabled** where possible.

**A11. What is the maximum size of a single block blob?**
**Answer:** Up to **~190.7 TiB** (4,000 MiB max per block, 50,000 blocks), with smaller default limits for some operations.

**A12. What is Azure Files and what protocol does it use?**
**Answer:** Fully managed **file shares** accessible via **SMB** (and **NFS**) — mountable from Windows/Linux/macOS VMs and on-prem, like a network drive.

**A13. What is the difference between blob, file, queue, and table storage?**
**Answer:** Blob = objects (HTTP/REST). File = SMB/NFS shares. Queue = message queue. Table = NoSQL key-value (now largely superseded by Cosmos DB). Choose per workload.

**A14. How is data in a storage account encrypted?**
**Answer:** **Encrypted at rest by default** (Microsoft-managed keys, or customer-managed keys via Key Vault) and **in transit** via TLS/HTTPS.

**A15. What is the storage account name uniqueness requirement?**
**Answer:** The account name must be **globally unique** across all Azure (3–24 chars, lowercase letters/numbers) — it forms part of the public endpoint URL.

---

## Case B — Advanced (Senior)

**B1. Explain the redundancy matrix and how to choose LRS/ZRS/GRS/GZRS + read access.**
**Answer:** Choose by durability vs cost vs region support: **LRS** = 11 nines, cheapest, single datacenter. **ZRS** = 12 nines, zone-resilient (good for VMs/HA within a region). **GRS/GZRS** = add **regional** durability (16 nines) with async secondary; **RA-GRS** adds **read access** to the secondary (read-only during an outage). Most production data uses GRS/GZRS; transient/scratch data uses LRS.

**B2. How does GRS failover work (customer-initiated vs Microsoft-managed)?**
**Answer:** Microsoft may fail over to the secondary region for **severe regional disasters** (managed failover, RTO hours). You can also do **customer-initiated (unplanned) failover** to the secondary for DR testing/fast recovery — note: the secondary becomes primary, and the old primary's unsynced data may be lost; a **planned failover** variant avoids data loss for storage accounts without recent geo-replication lag.

**B3. What are the access tier tradeoffs, and how do lifecycle management policies move data?**
**Answer:** Hot = low access cost, high storage cost. Cool/Cold = cheaper storage, higher access costs + minimum retention + early-deletion penalties. Archive = cheapest storage but offline (rehydrate = hours + rehydration charge). **Lifecycle management policies** automatically tier/cool/delete blobs by rules (e.g., 30 days → Cool, 180 days → Archive, 365 days → delete).

**B4. How does SAS work (service vs account SAS, stored access policies), and what are its security risks?**
**Answer:** A **service SAS** scopes to one service/resource with permissions + expiry; an **account SAS** spans multiple services. **Stored access policies** let you revoke/rotate SAS without reissuing (the SAS references the policy). Risks: SAS URLs leak in logs/code and are hard to revoke (unless a stored policy) — prefer **Entra ID + RBAC** or **managed identities** where possible, and use short expiries.

**B5. What are private endpoints vs service endpoints vs public access for storage, and when each?**
**Answer:** **Public + firewall** = simplest, internet-facing (least secure). **Service endpoints** = subnet-level private routing to the service's public endpoint (simpler, but still a public endpoint). **Private endpoints** = a **private IP in your VNet** per service instance — the strongest (no public endpoint, works from on-prem via VPN/ER). Choose private endpoints for security-sensitive data.

**B6. How do you configure a private endpoint for a storage account and disable public access?**
**Answer:** Create a **private endpoint** (NIC in a subnet) targeting the storage account's `blob` (or `file`) sub-resource, register a **private DNS zone** (`privatelink.blob.core.windows.net`) so the account name resolves to the private IP, then set the storage account's **public network access = Disabled** (or firewall to deny). Verify connectivity and DNS from the VNet.

**B7. What is Azure Blob versioning, soft delete, and blob snapshots (data protection)?**
**Answer:** **Versioning** keeps prior versions of overwritten blobs (restore old versions). **Soft delete** retains deleted blobs/containers for a retention period (recover accidental deletes). **Snapshots** are point-in-time read-only copies of a blob. Together with **point-in-time restore** (block blobs) and **immutability/legal hold**, they form the data-protection toolbox.

**B8. What is immutability (WORM) and legal hold in blob storage?**
**Answer:** **Time-based retention** and **legal hold** policies make blobs **write-once, read-many** (WORM) for a period — preventing modification/deletion for compliance (e.g., SEC 17a-4, HIPAA). Legal hold is indefinite until released. These are stronger than soft delete (no recovery override during the hold).

**B9. How does Azure Files integrate with on-prem (Azure File Sync), and what is AD authentication for shares?**
**Answer:** **Azure File Sync** syncs Azure file shares to on-prem Windows servers (cloud tiering, caching). **SMB shares** can use **Entra ID / AD DS** authentication (Kerberos) with **NTFS-style permissions**, or storage-account key/SAS. Use private endpoints for secure mounting.

**B10. How do you migrate large data into Azure Storage (AzCopy, Data Box, Data Factory)?**
**Answer:** **AzCopy** = CLI for fast copy (S3/GCS/local → Azure). **Data Box** = physical appliances for huge/offline transfers (TB–PB). **Azure Data Factory/Synapse** = orchestrated pipelines. **Azure Import/Export** = ship your own drives. Choose by data size and network constraints.

**B11. What are the performance options (standard vs premium, and premium tiers)?**
**Answer:** **Standard** = HDD/SSD-based, general purpose (GPv2). **Premium** = SSD-backed for low-latency/high-IOPS: **Premium block blobs** (high transactions), **Premium file shares** (high-performance SMB/NFS), **Premium page blobs** (VM disks). Choose premium for latency-sensitive/IO-heavy workloads.

**B12. How do you monitor and audit a storage account (metrics, logs, Defender)?**
**Answer:** Enable **diagnostics** (Storage Analytics logs + metrics) to Log Analytics; **Azure Monitor** for capacity/transaction/latency metrics; **Microsoft Defender for Storage** for threat detection (malware scans, anomalous access); and **Activity Log** for management-plane changes. Alert on unusual access, throttling, and capacity.

---

## Case C — Scenario

**C1. Scenario:** A backup service writes daily backups that are rarely read, kept 7 years for compliance, and must be immutable.
**Question:** Design the storage + protection.
**Answer:** **Blob storage** with **lifecycle management**: Hot → Cool (30d) → **Archive** (90d+) for the 7-year retention; enable **immutability (time-based retention)** so backups can't be modified/deleted during the window; use **GRS/GZRS** for regional durability, and **versioning/soft delete** as extra protection.

**C2. Scenario:** A storage account was publicly accessible and leaked data.
**Question:** Remediate + prevent recurrence.
**Answer:** Immediately set **public network access = Disabled** (or restrict firewall), rotate **account keys**, revoke any **SAS** tokens, and review access logs (Defender for Storage/Storage Analytics) for exposure. Prevent: **Azure Policy** (deny public blob/container access), **Defender for Storage**, **private endpoints** for all access, and disable shared-key where possible. Alert on public-access changes.

**C3. Scenario:** An app needs to upload/download blobs without storing credentials in code.
**Question:** Implement identity-based access.
**Answer:** Use a **managed identity** (or Entra ID service principal) with **RBAC roles** (`Storage Blob Data Contributor`) on the storage account — the app authenticates via Entra ID (no keys/SAS in code). Disable **shared key access** to enforce this. For temporary external access, issue a short-lived **SAS** with a stored access policy.

**C4. Scenario:** On-prem servers must mount the same file share as Azure VMs with AD permissions.
**Question:** Which service and configuration?
**Answer:** **Azure Files** with **AD DS/Entra ID authentication** (Kerberos) so NTFS-style ACLs apply to both on-prem and Azure VMs over SMB. Use **Azure File Sync** to cache/replicate to on-prem, connect via **private endpoint** (no public exposure), and mount from VMs + on-prem servers.

**C5. Scenario:** A multi-region app needs to read data even if the primary region fails.
**Question:** Which redundancy and failover approach?
**Answer:** **RA-GRS / RA-GZRS** — geo-redundant with **read access to the secondary**. During a primary-region outage, read from the secondary endpoint (data may be slightly behind due to async replication). For full failover (writes), perform a **customer-initiated failover** to the secondary (accepting RPO = replication lag). Document the RPO/RTO.

**C6. Scenario:** Storage costs are high; lots of old data is in Hot tier and many blobs are small but frequently listed.
**Question:** Optimize costs.
**Answer:** Apply **lifecycle management** to move old data Hot→Cool→Archive automatically; review **tier minimums** (avoid churn penalties); consolidate/reduce **small-file churn** (transaction costs — consider batching or ADLS Gen2 for analytics); enable **capacity alerts**; and use **Cost Management** to find the largest accounts/tiers. Consider ZRS vs GRS downgrades for non-critical data.
