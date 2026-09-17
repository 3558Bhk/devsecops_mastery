# Azure Recovery Services Vault — Restore — Interview Questions

> **Cloud:** Azure · **Category:** Backup & Recovery · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~9 min

---

## JSON File Format

Restore operations are triggered with a **REST request JSON** (`IaasVMRestoreRequest` and variants) against the recovery point.

```json
{
  "properties": {
    "objectType": "IaasVMRestoreRequest",
    "recoveryPointId": "1234567890",
    "recoveryType": "OriginalLocation",
    "sourceResourceId": "/subscriptions/<sub>/resourceGroups/rg/providers/Microsoft.Compute/virtualMachines/myVM",
    "createNewCloudService": false,
    "restoreDiskLunList": [0]
  }
}
```

**Key fields:** `objectType` (IaasVMRestoreRequest) · `recoveryPointId` · `recoveryType` (OriginalLocation / AlternateLocation / RestoreDisks) · `sourceResourceId`. Alternate-location restores add `targetVirtualNetworkId`, `targetSubnetId`, and `targetResourceGroupId`.


## Case A — Basic

**A1. What is a restore in Azure Backup?**
**Answer:** Recovering data from a **recovery point** back to its original location, a new location, or an alternate region — for VMs, files, SQL databases, or file shares.

**A2. What are the main restore options for an Azure VM?**
**Answer:** **Create new VM** (from a recovery point), **restore disks** (to a storage account/resource group, then build a VM), **replace existing** (restore over the current VM — requires special config), and **file recovery** (mount and browse individual files).

**A3. What is file recovery (item-level restore)?**
**Answer:** Restoring **individual files/folders** from a VM backup by mounting the recovery point as a browsable disk (via a script) — without restoring the whole VM.

**A4. What is the difference between restoring a VM vs restoring disks?**
**Answer:** **Restore VM** = Azure creates a new VM (with NIC, config) directly. **Restore disks** = Azure restores just the disks, and you manually create/attach a VM — more control over the target VM config.

**A5. What is "Instant Restore"?**
**Answer:** Restoring from the **snapshot** (local, fast) rather than the vault copy — quick VM restore (minutes) for recent recovery points.

**A6. What is a recovery point's age and how does it affect restore time?**
**Answer:** Recent points restore from **snapshots** (fast); older points restore from the **vault** (data is rehydrated/copied back — slower). Restore time generally grows with point age.

**A7. What is Cross-Region Restore?**
**Answer:** Restoring backup data in the **secondary (paired) region** — used when the primary region is unavailable (requires GRS vault + CRR enabled).

**A8. What is restore-as-files for SQL or files?**
**Answer:** Restoring data to a **network file location/UNC path** instead of the original location (e.g., restore SQL `.bak`/`.mdf` files to a share).

**A9. What is "replace existing" VM restore?**
**Answer:** Restoring backup data over an **existing** VM (overwriting its disks) — requires the VM's backup to have been taken with the right config, and it's destructive (overwrites current data).

**A10. What is point-in-time restore for SQL?**
**Answer:** Restoring a SQL database to **any point in time** within the log-backup window (thanks to transaction log backups) — finer granularity than VM restore.

**A11. What is the difference between original location restore and alternate location restore (ALR)?**
**Answer:** **OLR** = restore to the same source (overwrites/updates in place). **ALR** = restore to a **different location** (another VM/DB/server) — safer for testing and avoids overwriting live data.

**A12. What do you need to restore a VM with encrypted disks?**
**Answer:** The **Key Vault + key** used to encrypt the disks must be accessible, and you restore with the same encryption settings (or choose re-encryption). RBAC on the Key Vault is required.

**A13. Can you restore a VM to a different subscription/region?**
**Answer:** **Cross-subscription restore** is supported in some configurations; **cross-region** requires **CRR** (GRS vault). Otherwise, restore within the same region/subscription.

**A14. What is the first thing to check before a production restore?**
**Answer:** The **recovery point exists** and is intact, the **restore permissions** (RBAC), and the **target capacity/quota** (vCPUs, disks, subnet) in the destination region.

**A15. What is a restore job and how do you track it?**
**Answer:** Every restore runs as a **job** visible in the vault's **Backup jobs** (and Backup Center) with status/progress — track and alert on completion/failure.

---

## Case B — Advanced (Senior)

**B1. Explain the full VM restore flow (snapshot vs vault restore, and the "restore disks then create VM" pattern).**
**Answer:** Restore reads the recovery point (snapshot for recent/instant, vault for older). For **restore as VM**, Azure provisions a new VM with restored disks + config. For **restore disks**, Azure writes the disks to your chosen storage/resource group; you then create a VM from those disks (useful for troubleshooting/custom config). The flow includes validation, staging, and a job that tracks progress.

**B2. What is the difference between crash-consistent and application-consistent restore, and why does it matter?**
**Answer:** Restoring an **application-consistent** point gives a DB/app that was quiesced — it comes up clean (or with minimal replay). A **crash-consistent** restore is like power-loss recovery — the DB must run **crash recovery/replay logs**, risking longer startup or (rarely) data loss. Always prefer app-consistent points for transactional workloads.

**B3. How do you do item-level (file) recovery from a VM backup step by step?**
**Answer:** In the vault, select the backup item → **File Recovery** → choose the recovery point → download/run the **mount script** (PowerShell/Bash) on a VM in the same region → the recovery point mounts as local drives → copy the needed files → **unmount**. This restores files without recreating the whole VM — ideal for single-file accidents.

**B4. How does Cross-Region Restore work and what are its RTO characteristics?**
**Answer:** With **GRS + CRR**, backup data replicates to the paired region. During a primary-region outage, you initiate a **restore in the secondary region** (to a new VM/storage there). RTO depends on data size and the restore type (instant snapshot may not be available cross-region — vault restore is slower). It's a DR capability, not a live-replica failover (that's ASR).

**B5. How do you restore a SQL database to a point in time, and what are the options (OLR vs ALR vs files)?**
**Answer:** Select the SQL backup item → **Restore → Point-in-time** (pick a timestamp within the log range) → choose **overwrite (OLR)**, **alternate location (ALR)** (restore to another SQL instance), or **restore as files** (`.bak` to a share). ALR is safest for testing. The restore replays full/diff/log backups to the chosen time.

**B6. What is the relationship between restore and networking/NSGs (why restores fail after networking changes)?**
**Answer:** Restore to a new VM needs a valid **VNet/subnet**; the restored VM's NSG rules must allow your access (the old NSG config is restored but may reference old IPs/subnets). Also, **Azure Backup's service endpoints** must be reachable for the restore job. Common failure: restoring into a subnet whose NSG blocks RDP/SSH, or a deleted VNet.

**B7. How do you test restores without impacting production (restore drills)?**
**Answer:** Perform **alternate-location restores** (restore to a separate resource group/VNet/subscription), validate the app/DB comes up, then delete the test resources. Schedule regular **recovery drills** (quarterly) and document RTO/RPO metrics. Use **restore as files** for lightweight validation of DB/file backups.

**B8. What is the "restore as new VM with a different name/size" and why would you resize during restore?**
**Answer:** When restoring, you can change the VM **name, size, VNet/subnet, and disk type** — useful for testing (smaller size), avoiding name conflicts (the old VM may still exist), and placing the restored VM in a different network. Note: size must be available in the region and compatible with the restored disks.

**B9. How does restore work with Azure Files, and what is "restore to original vs new location"?**
**Answer:** For Azure Files backup, you can restore **individual files/folders** or the **entire share** to the **original** share (overwrite) or a **new/alternate** share. Item-level file restore is the most common (recover deleted files). Snapshots underpin the quick file-level restores.

**B10. What are the RBAC requirements for restore, and how do you separate backup vs restore permissions?**
**Answer:** Restore requires the **`Backup Operator`** (or Contributor on the vault) role plus permissions on the **target** (create VM/disks in the target RG, and Key Vault access for encrypted disks). Best practice: give operators **restore-only** roles and keep **backup-admin** (policy/delete) separate — least privilege and protection against a compromised operator deleting backups.

**B11. How do you restore when the original VNet/NSG is gone (deleted) or the region is down?**
**Answer:** If the VNet is deleted, restore **disks** and attach to a new VM in a valid network (or restore to a different VNet). If the **region** is down, use **Cross-Region Restore** (requires GRS + CRR) to restore in the secondary region. This is why CRR and testing the "region gone" scenario matter.

**B12. How do you monitor and validate restores (jobs, alerts, post-restore checks)?**
**Answer:** Track **restore jobs** in Backup Center; alert on failures. After restore: verify the VM **boots** (boot diagnostics), **app health** (probe/endpoint), **data integrity** (checksums/DB validation), and **security** (NSG/identity re-config). Document each drill's RTO and fix gaps.

---

## Case C — Scenario

**C1. Scenario:** A user accidentally deleted a critical file from a VM yesterday; the VM is otherwise fine.
**Question:** What's the fastest recovery?
**Answer:** **File Recovery (item-level restore)** — select the VM's backup item, run file recovery from yesterday's recovery point, mount it on the VM (or a recovery VM), copy the single file back, and unmount. No full VM restore needed.

**C2. Scenario:** A production VM is corrupted (won't boot), and you must restore it as a new VM with minimal downtime.
**Question:** Design the restore.
**Answer:** Restore **as a new VM** from the latest healthy recovery point (choose instant-restore if available for speed), give it a new name/size, place it in the same VNet/subnet, then **cut over** (repoint the load balancer/DNS to the new VM). Keep the old VM for forensics. Verify app health before decommissioning the old one.

**C3. Scenario:** You must validate that backups are actually restorable, but you can't touch production.
**Question:** How do you test?
**Answer:** Do an **alternate-location restore**: restore to a **separate resource group/VNet** (and optionally a different subscription), bring up the VM/DB there, run validation (app smoke test, DB integrity check), then delete the test resources. Automate quarterly drills and record RTO/RPO evidence for compliance.

**C4. Scenario:** The primary region is down; the business needs the app running in the secondary region.
**Question:** Which restore capability, and what are the caveats?
**Answer:** **Cross-Region Restore (CRR)** — if the vault is **GRS and CRR enabled**, restore VMs in the secondary region. Caveats: restore is from the **replicated vault copy** (slower than local snapshots), RPO = last replication, and you must rebuild/repoint DNS, load balancers, and dependencies. For faster RTO, use **Azure Site Recovery** for live replication instead.

**C5. Scenario:** A SQL database was corrupted by a bad script at 2:30 PM; you need it back to 2:15 PM.
**Question:** Which restore type?
**Answer:** **SQL point-in-time restore** to **2:15 PM** using transaction-log backups (available because SQL backups run logs every ~15 min). Restore to an **alternate location** first (to verify), then cut over — avoiding overwriting the live DB until you're sure.

**C6. Scenario:** After restoring a VM, you can't RDP/SSH into it, though the restore job succeeded.
**Question:** Diagnose.
**Answer:** Check the restored VM's **NSG** (rules may reference old source IPs or lack 22/3389 from your IP), the **public IP** (restored VMs may get a new/no public IP), the **VNet/subnet** (restored into a different subnet with different rules), and the **OS firewall**. Also confirm the VM **booted** (boot diagnostics). Adjust NSG/network settings accordingly.
