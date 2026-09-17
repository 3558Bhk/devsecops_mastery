# RTIQ — AWS Storage (Real-Time Interview Questions)

> **Cloud:** AWS · **Domain:** EBS Volumes, S3 Buckets · **Target roles:** SDE-3 · Cloud Engineer · DevOps · DevSecOps · SRE · Platform Engineer · **Reading time:** ~13 min

**How this file is used live:** storage questions are where interviewers test *data durability thinking* — what happens when a disk fills, a bucket is made public, a volume can't attach, or an object is deleted by an attacker. Expect real numbers (IOPS, throughput, sizes) and incident drills.

**Legend:** ⚡ Rapid · 🔍 Deep dive + follow-ups · 🚨 War room · ⚖️ Trade-off debate · 🎯 Senior signal

---

## 1. EBS Volumes — `ebs-volumes.md`

**⚡ Rapid**
1. **Q:** gp2 vs gp3 vs io2 — how do you pick?
**A.** gp3: baseline 3,000 IOPS/125 MB/s with independent provisioning up to 16,000 IOPS/1,000 MB/s, cheaper — the default. gp2: IOPS tied to size (3 IOPS/GB) — only if you're stuck on it. io2/io2 Block Express: high and consistent IOPS/durability for databases and latency-critical workloads (up to 256k IOPS). st1/sc1 for throughput/HC workloads.
2. **Q:** Can you attach an EBS volume to more than one instance?
**A.** Only `io1/io2` in multi-attach mode, and only in a cluster-aware filesystem — otherwise no. Standard volumes are single-AZ, single-instance. EFS/FSx exist for shared access.
3. **Q:** What is an EBS snapshot, and is it a backup?
**A.** Point-in-time, incremental-to-S3, region-scoped copy of the volume; copying to another region is a manual/automated step. It's a backup only if it's automated, retained, and restore-tested — say that out loud.
4. **Q:** Is EBS encrypted by default, and what about snapshots of encrypted volumes?
**A.** You should enable account-level default encryption (KMS) — it applies to new volumes and snapshots, and snapshots inherit the volume's encryption. Unencrypted snapshots can be copied with encryption on.
5. **Q:** What happens when an EBS volume fills up?
**A.** The instance hangs/misbehaves (writes fail, filesystems go read-only, databases corrupt). You can grow gp2/gp3/io volumes online and then extend the filesystem, but you cannot shrink them — plan headroom and alarms at 80%.
6. **Q:** Can you move a volume between AZs?
**A.** Not directly — snapshot it, then create a new volume in the target AZ from the snapshot. Instance store and EBS are both AZ-bound; this is why AZ-aware design matters in ASGs and K8s PVCs.

**🔍 Deep dive**
7. **Q:** A database VM has 12,000 IOPS provisioned and still shows high queue depth/latency. What do you check?
**A.** Instance-level limits: the EBS-optimized bandwidth and max IOPS/throughput per instance type (a small instance can't use the volume's full capability). Then burst-credit depletion (gp2), queue depth (`avgqu-sz`), I/O size (small random = IOPS-bound, large sequential = throughput-bound), and whether snapshots or a competing volume on the same instance are stealing bandwidth. Right-size *both* the volume and the instance.
8. **Q:** How do you design backups and actually test them?
**A.** AWS Backup or DLM policies per tag (daily/weekly/monthly retention), snapshots copied cross-region, and a scheduled restore drill into an isolated account that boots the instance/volume and validates data. Track RPO/RTO from the drill results and publish them — untested backups aren't backups.
9. **Q:** How do you reduce EBS cost without risking reliability?
**A.** Find unattached volumes and old snapshots (a big, easy win), migrate gp2 → gp3 (usually cheaper *and* faster), right-size provisioned IOPS (find the p95 actual usage), delete snapshots beyond retention, use snapshots lifecycle policies, and move infrequently accessed data to S3/EFS IA instead of keeping oversized volumes.
10. **Q:** What is an EBS direct API / fast snapshot restore, and when do you need them?
**A.** Fast Snapshot Restore pre-initialises snapshots so volumes created from them deliver full performance immediately (otherwise they're lazy-loaded and slow at first). Critical for DR/failover where a cold restore would blow your RTO. Costs per-AZ per-snapshot, so scope it to the volumes that matter.
11. **Q:** How do you handle EBS performance for K8s persistent volumes?
**A.** Use the EBS CSI driver with gp3 storage classes, provision IOPS/throughput per class by workload tier, set `volumeBindingMode: WaitForFirstConsumer` for AZ-aware scheduling, snapshot via the CSI snapshotter/VolumeSnapshots, and be aware that a pod rescheduled to another AZ will need a new PV unless you use StatefulSet + AZ-aware placement.
12. **Q:** Instance store vs EBS — when is instance store correct?
**A.** Ephemeral, high-throughput scratch data (caches, temp processing, replicas with their own durability), where losing data on stop/terminate is acceptable. Never for anything you can't rebuild.

**🚨 War room**
13. **Q:** A production volume hit 100% and the database is down. First 10 minutes?
**A.** Stop writes (take the app out of rotation / stop the DB gracefully if possible) so the filesystem doesn't corrupt; then extend the volume (modify) and `growpart` + filesystem resize — usually possible online for gp3 without downtime. Investigate what filled it (logs? temp files? binlogs? a runaway job?) and add an alarm at 80% plus log rotation before restoring writes.
14. **Q:** The instance won't boot after an OS-level change; the volume has data you need. Recovery path?
**A.** Snapshot the volume first (preserve evidence), attach both volumes to a "rescue" instance, mount the filesystem read-only, fix config/keys (`/etc/fstab`, authorized keys, kernel params), then reattach to the original instance. If it's virtualisation/driver damage, boot from a known-good AMI with the data volume attached.
15. **Q:** Someone deleted an EBS snapshot from production. What now?
**A.** Check whether it's recoverable (snapshots aren't recoverable once deleted — no recycle bin unless AWS Backup vault lock retained the copy). Look at AWS Backup vaults with compliance/retention for a retained copy, then treat as data-loss: rebuild from the newest usable backup/replica. Prevent by locking backups (`vault lock` in compliance mode), restricting `DeleteSnapshot` via IAM/SCP, and alarming on deletes.
16. **Q:** IOPS are provisioned correctly but latency is 40 ms. Diagnose.
**A.** Instance bandwidth ceiling, burst balance exhausted (gp2/gp3), concurrent snapshot creation consuming bandwidth, NIC/queue saturation from another workload, or a filesystem/application-level issue (small block sizes, synchronous writes, journal pressure). Pull `VolumeQueueLength`, `VolumeThroughputPercentage`, `BurstBalance`, and app-side iostat to separate volume from instance from app.
17. **Q:** DR failover to another region took 45 minutes instead of the promised 15. Why?
**A.** Snapshots copied on a schedule (RPO gap), no fast snapshot restore (slow cold start), AMIs not replicated so instances had to be rebuilt, and DNS/IAM/KMS dependencies not pre-created. Fix by pre-copying snapshots+AMIs, enabling FSR for critical volumes, launching the standby infrastructure (pilot light), and rehearsing quarterly with a timer.

**⚖️ Trade-off**
18. **Q:** EBS vs EFS vs FSx vs S3 for shared data?
**A.** EBS: single-instance block, fast, AZ-bound. EFS: shared POSIX NFS, elastic, multi-AZ, higher latency and cost per GB. FSx: Windows/Lustre/NetApp/OpenZFS for specific protocols/performance. S3: object storage, cheapest at scale, not a filesystem (mounting it via gateways has limits). Choose by protocol and sharing, not by price alone.
19. **Q:** Delete-on-termination: always on?
**A.** Set `DeleteOnTermination=true` for stateless ASG instances (avoids orphan volumes), `false` for instances holding data you must preserve. Orphan volumes are a classic cost leak; mistakenly deleting a data volume is a classic outage. Make it a deliberate, IaC-reviewed choice.
20. **Q:** Snapshots vs AWS Backup vs third-party?
**A.** DLM/snapshots are simple and cheap for EBS/RDS basics; AWS Backup adds centralised policies, cross-account/cross-region copies, vault lock, and compliance reporting. Third-party when you need app-consistent backups, long-term archive economics, or multi-cloud. For regulated orgs, AWS Backup + vault lock is the low-friction answer.

**🎯 Senior**
21. **Q:** Give me your storage capacity and performance standard for a new service.
**A.** gp3 by default with IOPS/throughput sized from measured p95 (not peak assumptions), 80% capacity alarms, snapshots via AWS Backup with cross-region copies and a tested restore, encryption by default with a CMK, no orphan volumes (tag + cleanup job), instance types sized so EBS bandwidth isn't the ceiling, and a documented RPO/RTO per data class.

**🎯 Senior signal:** "the instance's EBS bandwidth is the real ceiling, not the volume's IOPS" and "undeleted snapshots/volumes are the storage cost leak" — plus an actual restore drill story.

---

## 2. S3 Buckets — `s3-bucket.md`

**⚡ Rapid**
1. **Q:** Storage classes — when do you use what?
**A.** Standard (hot), Intelligent-Tiering (unknown/changing patterns — no retrieval fees, small monitoring charge), Standard-IA/One Zone-IA (infrequent, One Zone for reproducible data), Glacier Instant Retrieval (archive but ms access), Glacier Flexible (minutes-hours), Glacier Deep Archive (cheapest, 12h+). Lifecycle policies should move data automatically.
2. **Q:** How do you make a bucket private, and how do you prove it?
**A.** Block Public Access (account + bucket), no public bucket policies/ACLs, ACLs disabled (BucketOwnerEnforced), and proof via Config rules + Access Analyzer findings + `s3:GetBucketPolicyStatus`. Also check that CloudFront access uses OAC, not a public website endpoint.
3. **Q:** Versioning — always?
**A.** For anything with data value, yes: it protects against overwrite/ransomware and enables recovery. Combine with lifecycle rules to expire old versions, or your storage grows forever. Add MFA delete for high-value buckets.
4. **Q:** What is a lifecycle policy you'd set by default?
**A.** Transition to Standard-IA at 30–60 days, Glacier IR/Flexible at 90–180 days, expire noncurrent versions at 30–90 days, abort incomplete multipart uploads at 7 days (a silent cost killer), and expire objects per retention rules. Log/access buckets age faster (30 days).
5. **Q:** How do you encrypt objects, and what's the audit difference?
**A.** SSE-S3 (AWS-managed, no decrypt audit), SSE-KMS (your CMK, CloudTrail-auditable, per-request KMS cost — enable Bucket Keys), DSSE-KMS (double-layer for stricter compliance), or client-side. Regulated = SSE-KMS with a CMK.
6. **Q:** What are the consistency guarantees today?
**A.** Strong read-after-write for PUT/DELETE/LIST across all classes, including overwrite and delete. No eventual-consistency workarounds needed (list-after-write is immediately consistent) — but a cross-region replication lag still exists.
7. **Q:** What's the largest object size and how do you upload big files?
**A.** Single PUT up to 5 GB; multipart up to 5 TB (parts 5 MB–5 GB). Always multipart for large files, with parallelism and resume, plus a lifecycle rule to abort incomplete uploads. Presigned URLs or Transfer Acceleration for long-distance clients.

**🔍 Deep dive**
8. **Q:** A bucket with 400 TB must cost less without losing accessibility. Plan?
**A.** Analyse access with S3 Storage Lens/CloudWatch `BucketSizeBytes` + access patterns → apply Intelligent-Tiering for unpredictable data or explicit lifecycle transitions for predictable ones → enable Bucket Keys to cut KMS cost → check versioning/noncurrent buildup → use S3 Inventory to find cold/large objects → compress what's compressible → verify retrieval costs before archiving anything that's read often. Report the projected saving with the access assumption stated.
9. **Q:** How do you protect a bucket against ransomware or a malicious admin?
**A.** Object Lock (WORM) in compliance mode with retention, versioning + MFA delete, replication to a separate account with its own retention (so the primary admin can't delete the copy), least-privilege bucket policies with `s3:DeleteObject` denied by default, CloudTrail data events + GuardDuty S3 protection alarms on deletes, and an immutable access-log bucket. Say "a separate account with locked retention" — that's the answer that matters.
10. **Q:** How do you give a third party temporary access to one object?
**A.** Presigned URL with a short expiry (minutes-hours) generated by a role that has just `s3:GetObject` on that key; log the access; never hand out keys. For longer relationships, cross-account IAM role with `s3:prefix` conditions and `aws:PrincipalOrgID`/external-ID conditions.
11. **Q:** Cross-region replication vs multi-region access points vs backup copies?
**A.** CRR (replication rules) for low-latency regional reads, DR, or compliance copies — it's asynchronous and only replicates new/changed objects (existing data needs Batch Operations). MRAP for a single global endpoint routing to the nearest bucket (active-active reads). Note: replication is not a backup by itself (deletes can propagate — enable delete-marker replication control).
12. **Q:** How do you handle access logging and analytics?
**A.** Server access logging to a *separate* bucket (avoid loops), CloudTrail data events for sensitive buckets (who read what), S3 Storage Lens for usage/cost dashboards, and Inventory for object-level audits. Alarms on unusual `GetObject` volumes or `DeleteBucket`/policy changes.
13. **Q:** What are the requests-cost traps?
**A.** Lifecycle transitions and Glacier restores cost per request, `LIST` operations at scale (Inventory is cheaper), small-object workloads on IA classes (per-object overhead + 30/90-day minimum durations), KMS per-request costs without Bucket Keys, and incomplete multipart uploads. Model the *per-1000-requests* price for your access pattern before choosing a class.

**🚨 War room**
14. **Q:** A bucket was publicly exposed for 6 hours. Response order?
**A.** Contain (re-apply Block Public Access / fix policy now), then assess: what was in it, who accessed it (server access logs/CloudTrail data events), whether credentials or PII were exposed, then rotate any exposed secrets immediately and notify per incident/compliance policy. Afterwards: SCP guardrails, auto-remediation Config rule, Access Analyzer alerts, and a quarterly access review.
15. **Q:** You accidentally `aws s3 rm --recursive` a production prefix. Recovery?
**A.** If versioning was on: delete markers can be removed and versions restored (script/Batch Operations per prefix). If not: only backups/replication copies help. Time matters — do not run more writes that could compound the damage, and record the exact prefix. Then implement versioning + Object Lock + `s3:DeleteObject` restrictions and a dry-run/approval step in destructive tooling.
16. **Q:** Uploads fail with 403 for some clients but work for others. Debug.
**A.** Common causes: multipart upload parts below 5 MB (except the last), KMS permissions missing for a cross-account uploader, bucket policy with `aws:SourceVpce`/`SourceIp` conditions failing from a different network path, presigned URL expiry/mismatched signature (clock skew), or an ACL/ownership change (`BucketOwnerEnforced` breaks ACL-based clients). Check the exact error XML code (`SignatureDoesNotMatch` vs `AccessDenied`).
17. **Q:** S3 costs doubled. Where does the money go?
**A.** Storage class choice vs actual access (IA minimum durations + retrieval fees), versioning/noncurrent buildup, incomplete multipart uploads, request counts (small-object churn, LIST-heavy apps), data transfer out (especially via NAT — use gateway endpoints), KMS requests, and replication. Use Storage Lens + Cost Explorer by usage type; the top offenders are almost always class misuse and unexpired versions.
18. **Q:** Performance: a single prefix can't exceed ~3,500 PUT/5,500 GET per second. Your app is hitting it — fix?
**A.** S3 scales per-prefix; increase prefix parallelism by hashing the key (e.g. date + random hex prefix) or restructure the key layout, use multipart uploads with parallel parts, retry 503 SlowDown with exponential backoff, and consider S3 access points/MRAP or CloudFront for read-heavy distribution. State the per-prefix numbers — it shows real experience.

**⚖️ Trade-off**
19. **Q:** S3 vs EFS vs DynamoDB vs a filesystem for app data?
**A.** S3 for objects/large blobs/static assets, EFS when POSIX semantics are required, DynamoDB for structured key-based access at scale, and a real filesystem/DB when you need locking/transactions. People over-use S3 as a database (list-based queries) and EFS as cheap storage (it isn't).
20. **Q:** IA or Intelligent-Tiering?
**A.** Predictable access patterns → explicit lifecycle to IA/Glacier (cheapest). Unpredictable or mixed → Intelligent-Tiering with no retrieval penalties and automatic tiering (slight monitoring cost per object). Default to Intelligent-Tiering when you can't justify the pattern with data.
21. **Q:** Replication vs backup — is CRR a backup?
**A.** No. Replication is continuous mirroring (deletes and corruption propagate unless you control them), with asynchronous lag. A backup is a point-in-time, isolated, restorable copy (same-account versioning + cross-account locked copies/AWS Backup). Say it plainly — this is a common interview trap.

**🎯 Senior**
22. **Q:** Design the storage layer for a data platform: raw zone, processed zone, analytics, archives, and audit logs.
**A.** Separate accounts/buckets per zone with distinct retention and access: raw with Object Lock + KMS CMK, processed with lifecycle to IA, analytics exposed via Lake Formation/Athena with least-privilege roles, archives to Deep Archive with documented restore SLAs, access logs to an immutable bucket in a separate account, and Storage Lens dashboards with cost alarms. Every zone has an owner, a retention rule, and a tested restore.

**🎯 Senior signal:** "3,500 PUT/5,500 GET per prefix", "replication isn't backup", "abort incomplete multipart uploads", and Object Lock in a separate account. Those details mark S3 depth beyond tutorials.
