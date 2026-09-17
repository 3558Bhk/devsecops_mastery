# Amazon EBS (Elastic Block Store) — Interview Questions

> **Cloud:** AWS · **Category:** Storage · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~9 min

---

## JSON File Format

EBS volumes are declared in JSON via CloudFormation `AWS::EC2::Volume` (or inside `BlockDeviceMappings` of an instance/AMI).

```json
{
  "Type": "AWS::EC2::Volume",
  "Properties": {
    "AvailabilityZone": "us-east-1a",
    "Size": 100,
    "VolumeType": "gp3",
    "Iops": 3000,
    "Throughput": 250,
    "Encrypted": true,
    "KmsKeyId": "arn:aws:kms:us-east-1:111122223333:key/abcd-1234"
  }
}
```

**Key fields:** `VolumeType` (gp2/gp3/io2/st1/sc1) · `Size` (GiB) · `Iops` / `Throughput` (gp3/io2 are provisionable) · `Encrypted` + `KmsKeyId` · `AvailabilityZone` (volumes are AZ-scoped).


## Case A — Basic

**A1. What is Amazon EBS?**
**Answer:** Block-level storage volumes that attach to EC2 instances as network drives (like a virtual hard disk). You can format them with a filesystem and use them for OS disks, databases, and application data.

**A2. What are the main EBS volume types?**
**Answer:** **gp3/gp2** (general-purpose SSD), **io1/io2** (provisioned IOPS SSD for high-performance DBs), **st1** (throughput-optimized HDD), **sc1** (cold HDD). gp3 is the current default recommendation.

**A3. What is the difference between SSD and HDD EBS volumes?**
**Answer:** SSD (gp3, io2) = low-latency, IOPS-sensitive workloads (boot, DBs). HDD (st1, sc1) = high-throughput, large sequential workloads (big data, logs, archives) and are not bootable.

**A4. Can you attach an EBS volume to multiple instances at once?**
**Answer:** Standard EBS = **no** (single instance, single AZ, though detachable/re-attachable). The exception is **io2/io1 Multi-Attach** (same AZ only, cluster filesystems).

**A5. Is EBS zonal or regional?**
**Answer:** An EBS volume lives in a **single Availability Zone**. Snapshots, however, are **regional** and can be copied across regions.

**A6. What is an EBS Snapshot?**
**Answer:** A point-in-time, incremental backup of a volume stored in S3 (you don't see the S3 bucket). Only changed blocks are stored after the first full snapshot, so later snapshots are fast and cheap.

**A7. How do you create an AMI from an EBS volume?**
**Answer:** Snapshot the volume, then register the snapshot as an **AMI** (Amazon Machine Image) that can launch new instances across the region.

**A8. What happens to an EBS volume when its instance is terminated?**
**Answer:** By default, the **root volume is deleted** with the instance; **additional (non-root) volumes persist** unless you set delete-on-termination. You can change this flag.

**A9. What is EBS encryption?**
**Answer:** Volumes can be encrypted at rest (AES-256, via KMS), in flight between the instance and volume, and snapshots inherit encryption. Encryption is free and now default-enabled in most regions.

**A10. What is the difference between EBS and instance store?**
**Answer:** EBS persists independently of the instance and survives reboots/stop-start. **Instance store** is ephemeral, physically attached storage that is lost on stop/terminate/failure — but faster and free with the instance.

**A11. What are IOPS and throughput in EBS terms?**
**Answer:** **IOPS** = input/output operations per second (random I/O capability, matters for DBs). **Throughput** = MB/s of sequential data transfer. Each volume type has baseline and burstable limits.

**A12. Can you resize an EBS volume?**
**Answer:** Yes — you can grow the size, increase IOPS/throughput, or change the type **online** (with a short optimization period), then extend the filesystem/partition in the OS.

**A13. What is a "warm-up" period for EBS volumes?**
**Answer:** New volumes restored from snapshots may have higher first-access latency until blocks are lazily loaded; you can pre-warm by reading all blocks (or use Fast Snapshot Restore) before production use.

**A14. What is Fast Snapshot Restore (FSR)?**
**Answer:** Pre-loads a snapshot into AZs so volumes created from it are instantly at full performance (no lazy-load penalty), at an extra cost per AZ-hour.

**A15. How do you back up EBS volumes automatically?**
**Answer:** Use **AWS Backup** (or Data Lifecycle Manager — DLM) policies to create scheduled snapshots with retention, plus copy snapshots to another region for DR.

---

## Case B — Advanced (Senior)

**B1. Compare gp2 vs gp3 in detail, and why migrate to gp3?**
**Answer:** gp2 performance scales with volume size (3 IOPS/GB up to 16k IOPS, burst to 3k). gp3 decouples IOPS from size: baseline 3,000 IOPS and 125 MB/s for any size, with independently provisionable IOPS (up to 16k) and throughput (up to 1,000 MB/s) — and gp3 is ~20% cheaper. Migrate for predictable performance and lower cost.

**B2. Explain EBS snapshots' incremental nature and how deletion works.**
**Answer:** The first snapshot is a full copy; subsequent ones store only changed blocks, and a snapshot references blocks from prior snapshots. Deleting an intermediate snapshot is safe — AWS consolidates only the blocks no longer referenced, so later snapshots remain restorable. This is why snapshots stay cost-effective over time.

**B3. How do you design EBS for a high-performance database (io2 vs gp3, RAID, block sizes)?**
**Answer:** For latency/IOPS-critical DBs use **io2 Block Express** (sub-ms latency, up to 256k IOPS) or provisioned IOPS io2; for most workloads gp3 with sufficient provisioned IOPS. Tune filesystem/DB block size to match, use EBS-optimized instances with enough bandwidth, consider RAID-0 across volumes for aggregate throughput, and place volumes in the same AZ as the instance.

**B4. What are EBS-optimized instances and why do they matter?**
**Answer:** Instances with dedicated network capacity for EBS traffic, isolating storage I/O from regular network traffic. Choose the right instance type so EBS throughput isn't throttled by instance-level bandwidth limits.

**B5. Explain Multi-Attach: use cases, limitations, and requirements.**
**Answer:** io1/io2 volumes can attach to up to 16 Nitro instances in the **same AZ** for shared-block storage (e.g., clustered filesystems like GFS2/OCFS2 or active-active HA databases). Limitations: same AZ, not bootable with multi-attach, requires a cluster-aware filesystem, and consistent snapshots need care.

**B6. How does EBS encryption work under the hood, and what are its considerations?**
**Answer:** Volumes are encrypted with a KMS data key; the instance's Nitro hypervisor encrypts/decrypts in flight transparently. Snapshots inherit the key. Considerations: you can't change the KMS key after creation, cross-account snapshot sharing requires sharing the KMS key, and there's a small first-use KMS API cost (now largely mitigated).

**B7. How do you measure EBS performance, and what do VolumeQueueLength / BurstBalance mean?**
**Answer:** CloudWatch metrics: VolumeRead/WriteOps, VolumeRead/WriteBytes, **VolumeQueueLength** (pending I/O — consistently high means the volume is a bottleneck), **BurstBalance** (gp2/st1 burst credits — hitting 0 means throttled to baseline), VolumeThroughputPercentage, and VolumeIdleTime. Alarm on queue length and burst balance.

**B8. What causes EBS performance degradation and how do you fix it?**
**Answer:** Lazy loading from a fresh snapshot restore (use FSR/pre-warm), burst credit exhaustion (gp2/st1), hitting instance-level EBS bandwidth caps (use EBS-optimized/larger instance), small I/O sizes with low queue depth, or a noisy neighbor on shared infrastructure (rare with Nitro). Diagnose via metrics and adjust volume type/provisioning.

**B9. How do you migrate EBS data across AZs, regions, and accounts?**
**Answer:** Across AZ: snapshot → create volume in new AZ (or copy snapshot). Across region: snapshot → **copy snapshot** to target region → create volume. Across account: share the snapshot (and KMS key if encrypted) → copy in target account → create volume. Use AWS Backup or DLM for automation.

**B10. What is the difference between a crash-consistent and application-consistent snapshot, and how do you get the latter?**
**Answer:** Crash-consistent = point-in-time as if the machine lost power (filesystem-consistent via EBS's mechanism but not app-aware). Application-consistent = app quiesced (DB flushed/checkpointed) before the snapshot. Get it via AWS Backup's application-consistent backups (VSS on Windows / DB agents) or by quiescing the app before a manual snapshot.

**B11. When would you choose instance store over EBS, and what are the risks?**
**Answer:** Instance store gives very high local IOPS/throughput at no extra cost — good for scratch space, caches, buffers, and replicated (multi-node) data stores. Risks: data is lost on stop/terminate/underlying failure, and it can't be snapshotted directly — you must handle replication/backups yourself.

**B12. How do you plan EBS capacity and cost at fleet scale?**
**Answer:** Right-size volumes (avoid over-provisioning), use gp3 with provisioned IOPS only as needed, leverage lifecycle/snapshot archival (move old snapshots to archive tier), delete stale snapshots via DLM retention, use Cost Explorer/Compute Optimizer for recommendations, and monitor BurstBalance/queue metrics to avoid paying for performance you don't use.

---

## Case C — Scenario

**C1. Scenario:** A production DB's EBS volume is running at 100% burst balance depletion and queries are slow during peak hours.
**Question:** Diagnose and remediate.
**Expected answer:** The volume is likely a gp2 sized too small (IOPS tied to size) or an st1/gp2 exhausting burst credits. Remediate: migrate to **gp3** (or io2) with sufficient provisioned IOPS/throughput, verify instance-level EBS bandwidth isn't the cap, and set CloudWatch alarms on BurstBalance/VolumeQueueLength. Migration via snapshot or online volume modification (gp2→gp3 is an online change).

**C2. Scenario:** You need to restore a 2 TB volume from snapshot for an urgent DR test, but the restored volume is slow for the first hour.
**Question:** Why, and how do you avoid this in a real DR run?
**Expected answer:** Volumes restored from snapshots lazily load blocks from S3, so first-access latency is high until warm. Avoid by enabling **Fast Snapshot Restore (FSR)** on the snapshot in the target AZs (costs extra), or pre-warming (read all blocks, e.g., `dd`/`fio`) before failing over. For DR, pre-provision warm volumes in advance.

**C3. Scenario:** Compliance requires: volumes encrypted, backups kept 30 days, and a copy in another region for DR.
**Question:** Design the backup/encryption solution.
**Expected answer:** Enable **EBS encryption by default** (account setting) with a KMS key. Use **AWS Backup** (or DLM) with a daily snapshot policy, 30-day retention, and a **copy-to-region** rule (DR region) with its own retention. Verify snapshot encryption (inherits volume key) and test restore quarterly.

**C4. Scenario:** An app writes a 5 GB file to a newly attached volume but the OS reports disk full at 5 GB even though the volume is 100 GB.
**Question:** Diagnose.
**Expected answer:** The volume was resized/attached but the **filesystem/partition wasn't extended** (or the volume was never formatted to full size). Check `df -h` vs the volume size (`lsblk`), then grow the partition and filesystem (e.g., `growpart` + `resize2fs`/`xfs_growfs`). EBS size changes are not auto-propagated to the OS filesystem.

**C5. Scenario:** Two application servers need shared read/write storage with sub-millisecond latency in the same AZ for an active-active cluster.
**Question:** Which EBS feature fits, and what else is required?
**Expected answer:** **io2 Multi-Attach** (attach one volume to up to 16 Nitro instances in the same AZ). Also required: a **cluster-aware filesystem** (e.g., GFS2/OCFS2) to coordinate concurrent writes, and careful application support for shared storage. Note Multi-Attach can't be used for boot volumes.

**C6. Scenario:** A snapshot from Account A (encrypted with KMS key K-A) must be used to create a volume in Account B.
**Question:** List the exact steps including encryption/key handling.
**Expected answer:** (1) In Account A, **modify the KMS key policy** to grant Account B (or its role) `kms:CreateGrant`/`kms:DescribeKey`/`kms:Decrypt`/`kms:ReEncrypt*`/`kms:GenerateDataKey*`. (2) Share the snapshot with Account B (`ModifySnapshotAttribute`). (3) In Account B, **copy** the shared snapshot (optionally re-encrypt with Account B's own KMS key). (4) Create the volume from the copied snapshot. Account B cannot use Account A's snapshot directly without a copy.
