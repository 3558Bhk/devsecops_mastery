# Azure Recovery Services Vault — Backup — Interview Questions

> **Cloud:** Azure · **Category:** Backup & Recovery · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~9 min

---

## JSON File Format

Recovery Services Vaults and backup policies are ARM JSON: `Microsoft.RecoveryServices/vaults` and `.../backupPolicies` (schedule + retention).

```json
{
  "type": "Microsoft.RecoveryServices/vaults",
  "apiVersion": "2023-01-01",
  "name": "backupVault",
  "sku": { "name": "RS0", "tier": "Standard" },
  "properties": {}
}
```

Policy:
```json
{
  "name": "dailyPolicy",
  "properties": {
    "backupManagementType": "AzureIaasVM",
    "schedulePolicy": {
      "schedulePolicyType": "SimpleSchedulePolicy",
      "scheduleRunFrequency": "Daily",
      "scheduleRunTimes": ["2026-09-13T02:00:00Z"]
    },
    "retentionPolicy": {
      "retentionPolicyType": "LongTermRetentionPolicy",
      "dailySchedule": { "retentionDuration": { "count": 30, "durationType": "Days" } }
    }
  }
}
```

**Key fields:** `backupManagementType` (AzureIaasVM / AzureWorkload / AzureFileShare) · `schedulePolicy` (frequency + run times) · `retentionPolicy` (daily/weekly/monthly/yearly durations). Protected items register via `backupProtectedItems` JSON.


## Case A — Basic

**A1. What is a Recovery Services Vault?**
**Answer:** A management entity in Azure that stores **backup data** and **recovery points** for protected workloads (VMs, SQL, files, SAP HANA) and manages backup/replication policies, plus Azure Site Recovery for DR.

**A2. What can Azure Backup protect?**
**Answer:** **Azure VMs**, **SQL databases in VMs**, **SAP HANA**, **Azure Files**, **on-premises workloads** (via MARS agent/DPM/MABS), **blobs** (operational backup), and **Kubernetes** (via extensions).

**A3. What is a backup policy?**
**Answer:** The schedule + retention rules: when backups run (daily/weekly), how long recovery points are kept (daily/weekly/monthly/yearly retention), and for VMs, the consistency type.

**A4. What is the difference between Azure Backup and Azure Site Recovery?**
**Answer:** **Backup** = point-in-time copies for **restore** (accidental deletion/corruption). **Site Recovery** = continuous **replication** for disaster-recovery failover to another region. Complementary: Backup for data protection; ASR for RTO/RPO-driven DR.

**A5. What is a recovery point?**
**Answer:** A point-in-time snapshot/backup from which you can restore. Multiple recovery points (daily/weekly) are retained per the policy.

**A6. What is a snapshot vs a vault backup for Azure VMs?**
**Answer:** **Snapshots** (instant restore) are local, fast, kept a few days. **Vault backups** are the durable copies transferred to the Recovery Services Vault for long-term retention.

**A7. What are the consistency types for VM backup?**
**Answer:** **Application-consistent** (VSS on Windows / pre-post scripts on Linux — quiesces apps for transactional consistency), **crash-consistent** (as if power was cut — no app quiescing), and **file-system consistent** (Linux, flushes filesystem buffers).

**A8. What is the MARS agent?**
**Answer:** The **Microsoft Azure Recovery Services agent** installed on **on-premises** Windows servers to back up files/folders/system state to Azure.

**A9. What is soft delete for backups?**
**Answer:** Deleted backup data is retained for **14 days** (default, configurable) before permanent deletion — protecting against accidental or malicious deletion of backups.

**A10. What is encryption in Azure Backup?**
**Answer:** Backup data is **encrypted at rest** (platform-managed keys, or **customer-managed keys** via Key Vault for the vault) and **in transit** (TLS).

**A11. What is the difference between LRS and GRS storage for a vault?**
**Answer:** The vault's storage **redundancy**: **GRS** replicates backup data to a secondary region (protects against regional outage); **LRS** keeps it in one region. GRS can't be changed to LRS after protection starts without careful planning.

**A12. What is backup item and backup instance?**
**Answer:** A **backup item** is a protected resource (a VM, a SQL DB); a **backup instance** is the entity tracking its backup data/recovery points in the vault.

**A13. Can you back up to a vault in a different region?**
**Answer:** Generally the vault should be in the **same region** as the resource (backups are regional), but **Cross-Region Restore (CRR)** allows restoring to a secondary region if the vault is GRS and CRR is enabled.

**A14. What is a backup vault (vs Recovery Services vault)?**
**Answer:** The newer **Backup vault** supports **newer workloads** (Azure Blobs operational backup, AKS, Azure Disks) with some different features (e.g., no ASR). Choose per workload support.

**A15. What is the role of the Backup extension on VMs?**
**Answer:** The **Azure Backup extension** (installed automatically) coordinates snapshotting and the **VMSnapshot/VMSnapshotLinux** extensions for app-consistent backups.

---

## Case B — Advanced (Senior)

**B1. Explain the VM backup flow: snapshot → transfer to vault → recovery points.**
**Answer:** (1) Azure Backup triggers a **snapshot** of the VM's disks (instant restore snapshot, kept ~2 days). (2) The snapshot is transferred to the **vault** (as the durable copy). (3) Both become **recovery points** governed by the policy's retention. Instant restore uses the snapshot; long-term restores use the vault copy. Understanding this explains "instant restore" speed vs vault-restore latency.

**B2. How does application-consistent backup work (VSS, pre/post scripts), and why does it matter for SQL?**
**Answer:** For Windows, Backup uses **VSS** to quiesce writers (SQL, Exchange, apps) so the snapshot captures a transactionally consistent state. For Linux, you provide **pre/post scripts** to quiesce the app (e.g., flush MySQL, or `mariabackup`). Without app-consistency, a restored DB may need crash recovery/replay — risking data loss/corruption for transactional apps.

**B3. What is Cross-Region Restore (CRR) and what are its prerequisites?**
**Answer:** CRR lets you **restore backup data in a paired/secondary region** (for regional DR). Prerequisites: vault storage redundancy = **GRS**, **CRR enabled** (opt-in), and the feature available for the workload. It provides an extra DR option beyond the primary region's backups.

**B4. How do you design backup retention (daily/weekly/monthly/yearly GFS) for compliance?**
**Answer:** Use **GFS (Grandfather-Father-Son)** retention: e.g., daily for 30 days, weekly for 12 weeks, monthly for 24 months, yearly for 7 years. Align with RPO/RTO and compliance (e.g., 7-year retention). Note **maximum retention** is 9,999 recovery points / 30 years (VM daily). Schedule weekly/monthly points on different days to satisfy both short and long requirements.

**B5. What is soft delete + "enhanced soft delete," and how does it protect against ransomware?**
**Answer:** Soft delete retains deleted backup data (14 days default; **enhanced soft delete** always-on, 14–180 days). If an attacker deletes backups (or a VM), the data remains recoverable during the window — a key ransomware defense. Enable **multi-user authorization (MUA)** with Resource Guard so a second security principal must approve critical operations (disable soft delete, delete backups).

**B6. How does Azure Backup handle VMs with multiple disks, and what is "disk exclusion"?**
**Answer:** Backups include all VM disks; you can **exclude disks** (e.g., temp/scratch disks) to reduce cost/backup size. Excluded disks are NOT restored by VM restore — restore them separately from their own backups or accept data loss for non-critical disks.

**B7. What are the common reasons backups fail, and how do you troubleshoot?**
**Answer:** Failures: (1) **extension/agent issues** (VMSnapshot extension unhealthy), (2) **snapshot limits** (too many snapshots), (3) **disk-level errors** (encrypted/resized disks mid-backup), (4) **policy/schedule overlaps**, (5) **network/NSG blocking** the backup extension's outbound access, (6) **app-consistency script failures**. Check the **backup job logs** in the vault, VM extension health, and the backup agent logs.

**B8. What is backup of SQL in Azure VMs, and how does it differ from VM-level backup?**
**Answer:** SQL backup (via the Azure Backup SQL workload) uses **VSS/backup service** to produce **log backups** (up to every 15 min) + full/differential — enabling **point-in-time restore** of databases (finer than VM-level backup). VM backup alone only gives whole-VM recovery points. Use SQL-aware backup for transactional DBs.

**B9. How do you monitor and alert on backup health at scale (Backup Center, alerts, reports)?**
**Answer:** **Backup Center** = unified management (backup health, jobs, policies across vaults). **Backup alerts** (classic vs Azure Monitor-based) notify on failures; **Backup reports** (Log Analytics) give compliance/trend views. Alarm on **failed backup jobs**, missed RPO (no backup in N days), and **soft-delete events**. Use **Azure Policy** to enforce "VMs must have backup."

**B10. What is customer-managed key encryption for the vault, and what are the implications?**
**Answer:** Encrypting the vault's backup data with a **CMK in Key Vault** (instead of platform keys). Implications: you control rotation/revocation (revoking the key makes backups unrecoverable), the vault's **managed identity** needs Key Vault access, and switching from PMK→CMK or rotating requires care. Needed for certain compliance regimes.

**B11. What are the security best practices for Azure Backup (Ransomware protection)?**
**Answer:** **Soft delete + enhanced soft delete**, **Multi-User Authorization / Resource Guard** (prevent disabling/deleting), **immutable vault** (WORM — once locked, backups can't be deleted before retention), **encryption (CMK)**, **RBAC least privilege** (separate backup admin from workload admin), **offsite/CRR copies**, and **recovery drills**.

**B12. How does Azure Backup integrate with Azure Policy and governance?**
**Answer:** Use built-in policies: **"Azure Backup should be enabled for Virtual Machines"**, **"VMs should use a backup policy with defined retention"**, and audit vault settings (soft delete, GRS, CRR). Assign at management-group level (Azure Landing Zones) so every new VM is auto-protected and compliant, with exemption handling for non-critical resources.

---

## Case C — Scenario

**C1. Scenario:** A company needs daily VM backups, 30-day daily retention, 12 monthly, and 7-year yearly for compliance.
**Question:** Configure the policy.
**Answer:** Create a **backup policy**: daily backups with **daily retention 30 days**, **weekly retention 12 weeks**, **monthly retention 12 months**, and **yearly retention 7 years** (GFS). Assign the policy to the VMs (or via Azure Policy auto-assignment). Verify the yearly points are actually created (schedule a specific yearly date).

**C2. Scenario:** A ransomware attack deleted the VM and tried to delete its backups.
**Question:** How do you recover, and what should have been enabled?
**Answer:** **Soft delete** keeps deleted backup data for the retention window — restore the VM from the retained recovery points. To prevent future deletion: enable **enhanced soft delete**, **Multi-User Authorization/Resource Guard** (requires a second principal to approve backup deletion), **immutable vault**, and isolate the backup admin from workload admins. Test the restore.

**C3. Scenario:** A SQL Server on an Azure VM needs restores to **any point in time** (down to ~15 minutes).
**Question:** Which backup type and why not plain VM backup?
**Answer:** **SQL Server backup in Azure VMs** (the SQL workload in Azure Backup) — it captures **transaction log backups every 15 minutes** plus full/differential, enabling **point-in-time restore** of databases. Plain VM backup only gives whole-VM snapshots at the policy schedule — not fine-grained DB PITR.

**C4. Scenario:** Backups of a Linux MySQL VM are "crash-consistent" only, and restores occasionally corrupt the DB.
**Question:** Fix it.
**Answer:** Configure **application-consistent** backups with **pre/post scripts**: the pre-script quiesces MySQL (e.g., `FLUSH TABLES WITH READ LOCK` or a `mysqldump`/snapshot-safe flush), and the post-script resumes. This ensures the snapshot captures a consistent DB state. Test restores regularly to validate.

**C5. Scenario:** A VM's backup job fails every night with "snapshot operation failed."
**Question:** Diagnose.
**Answer:** Check: (1) the **VMSnapshot extension** health (reinstall if stuck), (2) **disk configuration changes** (resized/encrypted disks mid-backup), (3) **snapshot quota** (too many snapshots — clean up), (4) the VM is **running** (needed for app-consistent; or check agent), and (5) **network/NSG** blocking the backup service. Review the **job error details** in the vault for the specific code.

**C6. Scenario:** Compliance says backups must exist in a second region and be restorable there.
**Question:** Which vault settings?
**Answer:** Set the vault's **storage redundancy to GRS**, enable **Cross-Region Restore (CRR)**, and ensure the workload supports it. Then backups replicate to the paired region and can be **restored there** during a primary-region outage. Note: enabling CRR/GRS may have cost implications and can't be downgraded trivially — plan before protecting resources.
