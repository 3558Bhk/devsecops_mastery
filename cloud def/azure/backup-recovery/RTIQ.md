# RTIQ — Azure Backup & Recovery (Real-Time Interview Questions)

> **Cloud:** Azure · **Domain:** Recovery Services Vault (Backup), Recovery Services Vault (Restore) · **Target roles:** SDE-3 · Cloud Engineer · DevOps · DevSecOps · SRE · Platform Engineer · **Reading time:** ~20 min

**How this file is used live:** this is the *responsibility* round. Interviewers want to know whether you've actually restored something under pressure, whether you know the difference between backup and DR, and whether you could hand an auditor evidence. Expect "restore this VM from before a ransomware event" and "your RPO is 15 minutes — prove it".

**Legend:** ⚡ Rapid · 🔍 Deep dive · 🚨 War room · ⚖️ Trade-off · 🎯 Senior signal

---

## 1. Recovery Services Vault — Backup — `recovery-services-vault-backup.md`

**⚡ Rapid**
1. **Q:** What is a Recovery Services vault?
**A.** The management/storage boundary for Azure Backup (and Site Recovery) — it holds backup policies, backup items, and recovery points, with its own region, redundancy (LRS/GRS/ZRS), security settings (soft delete, MUA, immutability), and RBAC.
2. **Q:** What can you back up?
**A.** Azure VMs (full VM/subset of disks), Azure Files shares, SQL Server in VMs and Azure SQL (via Azure SQL backup), SAP HANA, PostgreSQL, Blob (operational/vaulted backup), AKS (via Velero or backup extension), on-prem (MARS agent/MABS/DPM), and disk/snapshot-level backups.
3. **Q:** What's the difference between a snapshot and a vaulted backup?
**A.** Snapshot (enhanced/instant restore) is fast and sits in the storage account/resource tier with limited retention; the vault copy is the durable, policy-retained backup that survives resource deletion. Good policies use both: snapshots for fast recovery, vault for retention/compliance.
4. **Q:** What does a backup policy define?
**A.** Schedule (frequency — daily/weekly, multiple times a day for VMs), retention (daily/weekly/monthly/yearly), instant-restore retention, and (for some workloads) archive/long-term tiers. Policy + vault settings = your RPO/RTO contract.
5. **Q:** Is soft delete on by default?
**A.** Yes (14 days by default, extendable) — deleted backup items/points are recoverable. Enhance it with immutable vaults and Multi-User Authorization (MUA) so an attacker can't purge backups even with admin credentials.
6. **Q:** What is Multi-User Authorization (MUA)?
**A.** A Resource Guard requiring a *second* privileged identity to approve destructive operations (disable soft delete, stop backup, delete data) — the control that stops a compromised admin from destroying backups. This is the answer auditors look for regarding ransomware resilience.
7. **Q:** Does Azure Backup protect against an entire-region failure?
**A.** Only if the vault uses geo-redundant storage (GRS) with cross-region restore enabled (now the default for new vaults) — otherwise backups are regional. Say the redundancy out loud; "we have backups" without GRS and a restored-from-secondary test isn't regional DR.
8. **Q:** How do you scope backup policy across an estate?
**A.** Policy assignment by tag/resource group with IaC (Terraform/Bicep/Policy), tiers of service (gold/silver/bronze workloads with different schedules/retention), and a compliance dashboard showing unbacked-up resources. Policy-driven onboarding via `deployIfNotExists` catches new resources automatically.

**🔍 Deep dive**
9. **Q:** Design backup for a regulated app: RPO 1 hour, RTO 4 hours, 7-year retention, ransomware resilience.
**A.** Enhanced policy on the VMs: hourly snapshots (instant restore) + daily vaulted backups for 30–90 days + monthly/yearly retention to archive (7 years) within the vault; vault with GRS + cross-region restore; immutable vault + MUA (Resource Guard with a separate identity/team); separate-account/secondary-region copies for the database tier (Azure SQL LTR, storage immutability); nightly backup health alerts and job-failure alerts; a quarterly restore test into an isolated VNet/account with documented results; and evidence packs for auditors (job history, restore records, policy config from IaC).
**↳ Follow-up:** "The whole region fails. Walk me through recovery."
**A.** Restore from the secondary region with cross-region restore (VMs/disks can be restored in a paired/other region), recreate infrastructure from IaC (network, identity, PaaS) in the DR region, restore data tiers in the right order (identity → secrets → DB → app), repoint DNS/Front Door, and validate with smoke tests. Be honest that RTO here is dominated by the IaC/infrastructure recreate time, not the restore itself — and that's what a DR drill measures.
10. **Q:** How do you know your backups are actually working?
**A.** Backup job alerts (failures/warnings) to a central channel, Backup Reports/Backup Center dashboards for coverage and success rate, alerts on resources with no successful backup in N days, RPO monitoring (last recovery point age), and periodic *restore* tests. "Backup succeeded" ≠ "restore works" — the test is the control.
11. **Q:** How do you handle exclusions and consistency for application backups?
**A.** For VMs: application-consistent snapshots (VSS pre/post scripts) for SQL/AD, exclude temp/pagefile/cache disks from backup to save cost, and be explicit that crash-consistent backups may need application-level recovery steps. For databases, prefer native/PaaS backups (Azure SQL LTR, Cosmos continuous) because they're transactionally consistent.
12. **Q:** How do you control backup cost?
**A.** Right-size retention (the biggest lever), use snapshots where fast recovery matters and vault/archive tiers for long-term, exclude irrelevant disks/data, consolidate policies, delete backups for decommissioned resources, and monitor the "storage consumed by backup" report per vault. Also watch that a GRS vault costs more than LRS — justify per workload class.
13. **Q:** How do you move/consolidate backups between vaults or subscriptions?
**A.** Vaults are regional and backups can't be moved between vaults directly — you re-protect resources in the target vault and let old recovery points expire, using the source vault's data until retention ends. Plan for cost overlap during the transition, and use Recovery Services vault move (subscription/resource group moves are supported with caveats) rather than rebuilding.
14. **Q:** How does Azure Backup integrate with Policy and IaC?
**A.** Policy definitions that audit/deny unbacked resources and `deployIfNotExists` to enroll new VMs into the standard policy, backup config as code (vault, policy, protection containers per environment), and a compliance report that exports "resources without backup" for the security review. This is the difference between a documented standard and an enforced one.
15. **Q:** What is Backup Center?
**A.** A single pane across subscriptions/vaults for coverage, jobs, alerts, and compliance (plus policy management and restore initiation) — the operational dashboard for "are we protected and are restores feasible". Use it for the weekly backup health review rather than opening vaults one by one.

**🚨 War room**
16. **Q:** Ransomware encrypted production file servers. Backups are the recovery path — walk through it.
**A.** Do not restore into the live environment before containing the threat (isolate network, identify the entry point and whether backups were targeted). Verify the latest *clean* recovery point (check the infection window and job history), restore into an isolated VNet/account first, scan/validate, then restore into production in order and only once the attack vector is closed. Document the timeline and preserve evidence for IR. If immutability/MUA are in place, the attacker couldn't have deleted the points — which is the whole point of those controls.
17. **Q:** Backup jobs have been failing for 3 weeks and nobody noticed.
**A.** Fix the immediate failure (agent health, network/private endpoint to the vault, storage account firewall, credential/permission changes, or VM-level issues), then backfill: run on-demand backups for all affected resources ASAP. Then add the missing monitoring: alerts on job failure, an RPO-age alert ("no recovery point in > N hours"), and a weekly Backup Center review with an owner. Silent backup failure is the most common real-world cause of total data loss.
18. **Q:** A vault was deleted (or its data purged).
**A.** Soft delete protects items for 14+ days; if a malicious actor disabled soft delete first (or MUA wasn't configured), data may be unrecoverable — check Resource Guard activity logs, Azure activity logs for who made the changes, and any cross-region/GRS copies. Then treat it as a security incident: restore from any surviving copies, and implement immutable vault + MUA + alerts on vault configuration changes.
19. **Q:** You need to restore a single file from a VM backup from 3 weeks ago.
**A.** Mount the recovery point as a disk (instant restore) and copy the file — or do a files/folders restore via the Recovery Services extension/IaR. Note that older recovery points may need to be pulled from the vault (slower) and that a replaced/moved VM requires reattaching the disk. Restoration granularity (file-level vs full VM) is the trade between speed and blast radius.
20. **Q:** Restore testing revealed an RTO of 9 hours vs a promised 4.
**A.** Break down where time went: recovery point retrieval (vault vs snapshot), disk creation/attach times, network/VNet recreation, DNS, application validation, and human detection/decision time. Then fix the dominant term: use instant restore points for speed, pre-create network/identity infrastructure (or IaC-automate it), pre-stage a DR environment, and script the restore so it isn't manual. Renegotiate or fix the RTO claim — an untested RTO is marketing.
21. **Q:** Azure SQL database corrupted; the app is writing to it right now.
**A.** Stop writes (take the app read-only/out of rotation) to prevent further damage and to define a clean point in time, then restore to a point in time into a *new* database, validate, and cut over (rename/point connection strings via the failover group or config). The copy-and-validate step is what makes this safe — never restore over the live database as the first move.
22. **Q:** The vault has GRS but cross-region restore isn't enabled/tested; the primary region is down.
**A.** GRS alone doesn't guarantee you can restore in the secondary — enable cross-region restore *before* you need it and confirm the recovery points are available (there's a lag for secondary replication). If it's not enabled, you wait for the region to recover: painful and honest. This is why DR readiness checks include the backup plane, not just the runtime.

**⚖️ Trade-off**
23. **Q:** Snapshot/instant restore vs vaulted backup?
**A.** Snapshots: fast (minutes), short retention, stored with the resource — good for operational recovery and high RPO. Vault: durable, policy-driven retention, survives resource deletion, slower to restore — good for compliance/DR. Use both; a snapshot-only strategy fails exactly when the account/resource is deleted or compromised.
24. **Q:** Azure Backup vs Site Recovery (ASR) vs native PaaS backups?
**A.** Azure Backup: point-in-time recovery of data. ASR: replication and orchestrated failover for VMs (RPO seconds/minutes) — that's DR, not backup. Native PaaS backups (Azure SQL LTR, Cosmos continuous, storage versioning/immutability) are usually the best protection for those services. A complete strategy uses all three by workload type.
25. **Q:** Azure-native backup vs third-party (Veeam/Commvault/rubrik-style)?
**A.** Azure Backup is native, cheap to start, integrates with Policy, and covers the common cases; third-party tools give cross-cloud consistency, application-aware depth, and richer reporting/policy at a licence cost. Choose by estate complexity and whether you're multi-cloud.
26. **Q:** LRS vs GRS vs ZRS vaults?
**A.** LRS: cheapest, same-region (datacentre-level resilience); ZRS: zone resilience in-region; GRS: paired-region copies with cross-region restore capability (higher cost, and restore-from-secondary has cost/latency implications). Match to the RPO/RTO commitment per workload class, and say that not every workload needs GRS.
27. **Q:** Policy-driven onboarding vs opt-in backup?
**A.** Policy-driven (deployIfNotExists by tag) guarantees coverage and catches new resources — the only approach that scales. Opt-in leaves gaps discovered during incidents. The trade is policy exceptions for workloads with special needs — allow them explicitly, with owners.
28. **Q:** How often should you test restores?
**A.** At least quarterly for critical systems, plus after any major architectural change, and always before a compliance audit. Test at two levels: a scripted automated restore of a sample resource (cheap, frequent) and a full DR exercise for tier-1 systems (expensive, scheduled). Record RTO/RPO achieved — that's the metric.

**🎯 Senior**
29. **Q:** How do you present backup/DR posture to an auditor and to leadership?
**A.** Auditors: policy definitions, coverage reports (resources without backup), job success rates, immutability/MUA configuration, restore test records with timestamps and outcomes, and retention/immutability settings — all exportable from Backup Center/dashboards. Leadership: business-critical coverage %, RPO/RTO achieved vs promised, cost per workload class, and the top three gaps with owners and dates. One dataset, two audiences.

**🎯 Senior signal:** "immutable vault + MUA so a compromised admin can't delete backups", "backup succeeded ≠ restore works", and a tested RTO number. That's someone who's been accountable for recovery.

---

## 2. Recovery Services Vault — Restore — `recovery-services-vault-restore.md`

> **RTIQ note:** this file is the *execution* side — restore options, order of operations, and drills. Interviewers love pushing here because it exposes who has actually done it.

**⚡ Rapid**
1. **Q:** What are the restore options for an Azure VM?
**A.** Create new VM (from the recovery point, in a chosen VNet/subnet), restore disks only (attach to an existing VM), replace existing disks (in-place), cross-region restore (from a GRS vault), and file/folder-level restore (mount the recovery point). Choosing the least destructive option is part of the answer.
2. **Q:** What's the fastest path for a recent mistake?
**A.** Instant restore (snapshot tier): mount/attach the recovery point directly — minutes. Vault-tier restores involve copying data back to storage and take longer.
3. **Q:** How do you restore a single file without a full VM restore?
**A.** Mount the recovery point as a disk (IaR) and copy the file off, or use file recovery from the portal/CLI — leaving the running VM untouched. It's the standard answer for accidental deletions within the retention window.
4. **Q:** In-place replace of OS/data disks — when?
**A.** When you must preserve the VM's identity (hostname, IP, domain join extensions) and can accept downtime. It's destructive: take a snapshot/backup of the current state first, stop the VM, replace, start, validate. Preferred only when recreating the VM would break identity/dependencies.
5. **Q:** How do you verify a restore before putting it into production?
**A.** Restore into an isolated VNet/account, verify data integrity (application-level checks, not just "the VM booted"), run smoke tests, scan for malware if the restore is post-incident, then cut over. "Booted successfully" is not validation.
6. **Q:** What's the difference between RPO and RTO again, and which does backup affect?
**A.** RPO = how much data you can afford to lose (determined by backup/replication frequency); RTO = how long until service is restored (determined by restore method + infrastructure rebuild time). Backups set your RPO and heavily influence RTO; ASR/replication improves RTO. Answer precisely, because the question is a trap for vague answers.
7. **Q:** Can you restore to a different subscription/region?
**A.** Yes with the right configuration (cross-region restore for GRS vaults; restoring into another subscription requires appropriate permissions and target resources). Plan the target network/identity availability — a VM restored without its dependencies is a stranded disk.

**🔍 Deep dive**
8. **Q:** Walk me through a full tier-1 application recovery after region loss (RTO 4 h, RPO 15 min).
**A.** Detect/declare (monitoring + decision), switch traffic (Front Door/Traffic Manager to DR), rebuild infrastructure from IaC (networking, identity, Key Vault, PaaS) in the DR region, restore data in dependency order (identity/secrets → databases via LTR/PITR or replica promotion → object storage → app VMs from backup or replicated image), validate with automated smoke tests and synthetic transactions, then open traffic. Run it as a scripted runbook with named owners and a time log — and measure RPO achieved (last recovery point vs incident time) honestly.
**↳ Follow-up:** "Where does the 4 hours actually go?"
**A.** Usually not the data restore: it's detection/decision time, infrastructure recreate (where IaC isn't complete), DNS/TLS, and validation. That insight — and the automation you add because of it — is what the interviewer is fishing for.
9. **Q:** How do you restore an entire file share with millions of files?
**A.** Use full share restore (or item-level restore for a subset) into the same or another storage account; large restores take time and are throttled, so plan for parallelism/priority rather than expecting instant completion. For critical shares, keep a second copy in a separate account/region with immutability — that's faster than a bulk restore from a vault.
10. **Q:** How do you handle application-consistent restores for databases on VMs?
**A.** Restore the VM/disks, then recover the database (bring it online, apply logs if needed) using the application's own recovery process; prefer native database backups for transactional integrity. Document the order and the validation queries (row counts, latest transaction) — "the disk is attached" isn't recovery.
11. **Q:** How do you test recovery without touching production?
**A.** Restore into an isolated VNet with no production connectivity (or a separate subscription), use sanitised data where possible, run the application's validation suite, and time the whole exercise. For DR tests, use a "pilot light" or a scaled-down environment and measure both RTO and the effort required.
12. **Q:** What can break a restore you only discover under pressure?
**A.** Missing target infrastructure (subnets, NSGs, Key Vault keys, identities), no permission model for the restore operator (RBAC required for recovery — plan a dedicated role), quota/capacity limits in the DR region, expired/incomplete backup chains (a single failed job in a chain), and immutability/retention that blocks deleting the current (infected) data when you want to restore over it. Enumerate these in the runbook.
13. **Q:** How do you do restore for AKS/containers?
**A.** Use the AKS backup extension or Velero for cluster resources + persistent volumes into the target cluster/region, restore namespaces/PVCs in dependency order, and validate by running the workloads. Note that images/registries, secrets (Key Vault), and external DNS are also part of "the app" — a PVC restore alone isn't a recovery.
14. **Q:** How do you prove a restore — evidence for audit?
**A.** Restore records from Backup Center/job history (who, what, when, source recovery point, target, result), the validation checklist with screenshots/queries, the RTO/RPO measured, and the incident/test report. Keep the evidence in the same retention class as the regulatory requirement.
15. **Q:** What is Azure Site Recovery and how does it change your restore story?
**A.** ASR replicates VMs continuously (or near-continuously) to another region and orchestrates failover with recovery plans (ordered start, scripts, DNS updates) — giving RPO in seconds/minutes and a much shorter RTO than restoring from backup. It's the tool for tier-1 DR; Azure Backup remains for point-in-time/operational recovery and compliance retention. Several stacks run ASR for DR plus Backup for data protection.

**🚨 War room**
16. **Q:** You're the on-call and the instruction is "restore production from last night". What do you do first, before touching the portal?
**A.** Clarify scope and impact (which systems, what's the accepted data-loss window, was it caused by an attack?), confirm authority/approval for a destructive action, verify the latest *clean* recovery point (not just the newest), and define the restore order plus how you'll validate. Then communicate a status/ETA channel. Senior candidates ask these questions; juniors click restore immediately and make it worse.
17. **Q:** The restore you need is 30 days old and vault retention was 30 days.
**A.** Check whether archive/long-term retention exists (monthly/yearly points), whether the data is available in a secondary region, and whether an older point exists in another vault/copy (a separate backup account or export). If nothing exists, the honest answer is unrecoverable — and the post-incident fix is retention aligned with the business requirement (and the business agreeing it). Never promise recovery you can't deliver.
18. **Q:** A restore of a 2 TB VM is taking 6 hours and the business is escalating.
**A.** Communicate the constraint (data volume vs available bandwidth/snapshot availability), then accelerate: use instant restore/disk-level attach (if within the snapshot window) rather than full VM restore; parallelise (prepare the target network/resources while data copies); restore only the disks/data actually needed to bring the service up (partial restore), then the rest. Document the achieved RTO and negotiate the target for next time.
19. **Q:** After an in-place disk replace, the VM boots but the application fails.
**A.** Verify the restored disk set (OS + data consistency at the same point in time), check the app's own recovery steps (DB logs, service state, config/connection strings that may be environment-specific), and inspect event/application logs. It's usually application-level state, not the disk — which is why validation (not boot) is the completion criterion.
20. **Q:** The DR region is out of quota for the VM SKU you need.
**A.** Raise a support request for quota early (this is a known DR risk), or use a different SKU/family for the recovery, and record it in the runbook. Proactive: validate quotas in the DR region quarterly and reserve capacity for tier-1 workloads if the subscription allows. Quota surprises are one of the most common "DR failed on the day" causes.
21. **Q:** You restore into DR and discover the data is 40 minutes older than the incident (RPO breach).
**A.** Recover what you can from the backups, then use any additional sources to narrow the gap (transaction logs, CDC, a read replica, WAL shipping, or partial replay from queued messages). Report the RPO breach honestly to the business and fix the mechanism (more frequent backups/replication, ASR, or a lower-RPO architecture) — RPO was a design commitment you didn't meet.
22. **Q:** An attacker with admin credentials purges backups *and* soft delete before encrypting data.
**A.** If MUA/immutable vaults weren't configured, the deleted points may be unrecoverable — recovery then depends on offline/other copies (secondary region if GRS, an entirely separate account/subscription backup, or exported data). This is precisely why the standard is: immutable vault + MUA + separate identity/team + alerts on destructive backup operations + offline/immutable copies. Discuss it as a design failure with a specific remediation.

**⚖️ Trade-off**
23. **Q:** Full VM restore vs disk restore vs file-level restore?
**A.** Full VM: complete but slowest and heaviest (new identity/name considerations). Disk: flexible (attach to an existing VM, faster to publish a service) and preserves the environment. File-level: fastest and least invasive, ideal for accidental deletions. Choose the least destructive that satisfies the requirement — and say that out loud.
24. **Q:** Restore in place vs restore to a new resource and cut over?
**A.** In place: preserves identity, simplest cutover, but destructive and risky (you may lose the evidence/known-bad state you might need). New resource + cut over: safer, testable, allows validation and rollback, but requires DNS/config changes and resource capacity. Default to the new-resource path for anything with unclear cause; in place only when identity matters and you've validated first.
25. **Q:** Backup-based DR vs replication-based DR (ASR)?
**A.** Backup: minutes-to-hours RPO, hours RTO, cheaper, good for data protection and point-in-time recovery. Replication (ASR): seconds-to-minutes RPO, faster orchestrated failover, higher cost and complexity, but the right tool for tier-1 DR. Tier your workloads: ASR for tier-1, backup for the rest.
26. **Q:** Single recovery pattern for all workloads vs tiered?
**A.** Tiered by business impact (tier-1 = replication + tested orchestrated failover; tier-2 = backup restore with a rehearsed runbook; tier-3 = rebuild from IaC + data restore). A single pattern is either too expensive or too weak — and the tiering should come from the business's RTO/RPO requirements, not from what's convenient.
27. **Q:** Automated restore vs manual runbook?
**A.** Automate the routine (scripted restore, IaC for target infrastructure, validation tests) so drills are cheap and restores are consistent; keep humans for the decisions (declare, choose the recovery point, approve destructive steps). The best runbook is a script with checkpoints, not a wiki page nobody reads under pressure.
28. **Q:** Restore speed vs cost?
**A.** Fast recovery means snapshots/instant restore, replication, and pre-provisioned DR capacity — all of which cost money. You trade standby cost for RTO; quantify it against the cost of downtime and let the business choose the tier explicitly (with the numbers in front of them).

**🎯 Senior**
29. **Q:** What makes a restore plan credible to you?
**A.** It's been executed recently, on real infrastructure, with measured RTO/RPO results and a list of what broke; the target environment (network, identity, quotas, DNS, dependencies) is pre-validated or IaC-automated; the order of operations and validation criteria are written with named owners; the recovery points are verified clean and protected by immutability/MUA; and the plan is rehearsed at least twice a year with the same people who'd be on call.

**🎯 Senior signal:** "ask what the accepted data loss is before you click restore", "restore into isolation and validate before production", and "quota, identity, and DNS are what usually break DR — not the restore". Those three earn senior credibility instantly.
