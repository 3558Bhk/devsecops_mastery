# RTIQ — Terraform Storage & Databases on AWS (Real-Time Interview Questions)

> **Cloud:** AWS · **Tool:** Terraform · **Domain:** S3, RDS/DynamoDB · **Target roles:** SDE-3 · Cloud Engineer · DevOps · DevSecOps · SRE · Platform Engineer · **Reading time:** ~19 min

**How this file is used live:** data-layer Terraform questions are where interviewers check whether you understand *irreversibility*. Buckets and databases hold state: a wrong `force_destroy`, a changed identifier, or a missing `prevent_destroy` is a data-loss incident. Expect "what would you protect, and how?", plus cost and lifecycle questions.

**Legend:** ⚡ Rapid · 🔍 Deep dive · 🚨 War room · ⚖️ Trade-off · 🎯 Senior signal

---

## 1. S3 — `s3.md`

**⚡ Rapid**
1. **Q:** Minimum secure S3 bucket in Terraform?
**A.** `aws_s3_bucket` with `aws_s3_bucket_public_access_block` (all four true), `aws_s3_bucket_server_side_encryption_configuration` (SSE-KMS or at least AES256), `aws_s3_bucket_versioning` (Enabled), `aws_s3_bucket_ownership_controls` (BucketOwnerEnforced — required before disabling ACLs), and an `aws_s3_bucket_policy` to deny insecure transport (`aws:SecureTransport: false`).
2. **Q:** Why so many separate resources for one bucket?
**A.** AWS deprecated the inline bucket configuration (ACLs, versioning, encryption, lifecycle as arguments on `aws_s3_bucket`) in favour of separate resources — they change independently and don't force replacing the bucket. That's why modern modules have 8–12 resources per bucket.
3. **Q:** What is `force_destroy` and when do you use it?
**A.** It allows `terraform destroy` to delete a non-empty bucket. Use it only for clearly disposable buckets (ephemeral PR environments). For anything with data: `force_destroy = false` plus `lifecycle { prevent_destroy = true }`.
4. **Q:** How do you do lifecycle rules?
**A.** `aws_s3_bucket_lifecycle_configuration` with `rule` blocks: transitions (IA/Glacier), expiration, `noncurrent_version_expiration`, and `abort_incomplete_multipart_upload`. Always include the abort rule — incomplete multipart uploads are a hidden cost.
5. **Q:** How do you host a static site?
**A.** Private bucket + CloudFront with OAC + `aws_cloudfront_distribution`; or `aws_s3_bucket_website_configuration` for a public website endpoint (dev only, no TLS/custom domain). Production is always CloudFront with the bucket private.
6. **Q:** Where should the bucket live in the module structure?
**A.** A `s3_bucket` module that takes policy statements, lifecycle rules, and tags as inputs, with secure defaults baked in (encryption, versioning, public-access block, ownership controls) so the common case is the safe case.
7. **Q:** How do you handle S3 notifications in Terraform?
**A.** `aws_s3_bucket_notification` with a Lambda/SQS/SNS target plus the required `aws_lambda_permission` and a bucket policy allowing the service to publish. Missing the permission is the usual apply-time failure.
8. **Q:** How do you do cross-account access?
**A.** Bucket policy granting the specific account/role (with `aws:PrincipalOrgID`), plus KMS key policy allowing `Decrypt` for that principal. The bucket policy alone is insufficient for SSE-KMS objects — the classic gotcha.

**🔍 Deep dive**
9. **Q:** Design a compliant data-lake bucket layer in Terraform (raw/processed/archive + audit).
**A.** Separate buckets/accounts per zone: raw with Object Lock (WORM) + KMS CMK + versioning + access logging to an immutable log bucket in a different account; processed with lifecycle to IA/Glacier and a tighter IAM policy; archive with Deep Archive + documented restore procedure; logs bucket with Object Lock and no delete permissions for anyone. Terraform sets public-access blocks, policies with `aws:SecureTransport` and `aws:SourceVpce` conditions, replication (with RTC and delete-marker replication control) where DR is required, and bucket keys to cut KMS costs. Outputs expose bucket ARNs/names only — not credentials.
**↳ Follow-up:** "How do you prevent someone deleting the audit logs?"
**A.** Object Lock in compliance mode + a bucket policy denying `s3:DeleteObject` (even to admins) + no `s3:PutBucketPolicy` rights for humans + the bucket in a separate account with its own KMS key. And test that your own pipeline can still write to it — an over-locked audit bucket breaks logging.
10. **Q:** How do you do cross-region replication in Terraform?
**A.** `aws_s3_bucket_replication_configuration` with a role, source/destination versioning enabled, and per-rule options (KMS-encrypted objects need the destination key + role permissions, and replication of SSE-KMS requires explicitly enabling it). Add replication metrics/alarms and a `delete_marker_replication` decision — this is a common source of silent DR gaps.
11. **Q:** How do you manage hundreds of buckets across accounts?
**A.** A module with a typed input (purpose, lifecycle profile, policy template) called per bucket, naming/tagging standards enforced by validation, and policy-as-code in CI (no public access, encryption required, versioning required). Track ownership in tags and review with S3 Storage Lens rather than opening each bucket.
12. **Q:** How do you handle S3 at scale in state?
**A.** One resource set per bucket (or `for_each` over a bucket map in a purpose-specific root) so the state doesn't grow unbounded; keep object management out of Terraform entirely (content is deployed by the app pipeline with `aws s3 sync`, not by `aws_s3_object` for every file). Managing every object in Terraform is an anti-pattern — say it.
13. **Q:** How do you enforce "no public buckets" beyond the resource settings?
**A.** Account-level `aws_s3_account_public_access_block`, org-level SCP denying `s3:PutBucketPublicAccessBlock` changes that disable it, Config rules (`s3-bucket-public-read-prohibited`) with auto-remediation, Access Analyzer, and CI policy checks on plans. Layers, because one misconfigured resource shouldn't be able to expose data.
14. **Q:** How do you do bucket notifications plus event-driven processing safely?
**A.** Event notifications → SQS (buffer + DLQ) rather than straight to Lambda for high volume, with idempotent consumers and a DLQ alarm; for cross-account events use EventBridge (`aws_s3_bucket_notification` with EventBridge enabled) so you can route without bucket-policy changes per consumer. Also watch event loops (a function writing to the bucket it consumes from).
15. **Q:** How do you handle bucket naming and global uniqueness?
**A.** A `name_prefix`/name composed from org/app/env/region plus a short random suffix (`random_id`/`random_string` with 4–6 chars) where collisions are possible; keep the random suffix in state so it's stable, and never rename a bucket (rename = new bucket = data migration).

**🚨 War room**
16. **Q:** A plan wants to destroy and recreate an S3 bucket. What do you do?
**A.** Stop. Find the forcing attribute — typically a changed `bucket` name, a region/provider change, or a `force_destroy`/ownership change. If the name must change, migrate deliberately: create the new bucket, sync data, update consumers, then delete the old one after verification. Add `prevent_destroy` to make this impossible by accident.
17. **Q:** Terraform can't delete a bucket because it's not empty during a teardown.
**A.** Either set `force_destroy = true` for genuinely disposable buckets, or (better for anything with data) delete the contents deliberately as a separate, auditable step (lifecycle/CLI) after confirming it's the right bucket. In practice: ephemeral env buckets → `force_destroy = true`; production → `prevent_destroy` + never destroy.
18. **Q:** Someone flipped a bucket to public to debug, and Terraform reverted it mid-investigation.
**A.** The revert is correct behaviour (Terraform enforcing desired state). The real problems are: why a human had write access to a production bucket, and why a debug step required public access (use a presigned URL or a scoped role). Review access, add an alert on public-access changes, and document the safe way to inspect data.
19. **Q:** Apply failed halfway after adding a bucket policy and now nobody can read the bucket.
**A.** The policy may have removed the principal your own tooling uses (or added a restrictive condition like `aws:SourceVpce`/`SecureTransport` that some clients don't satisfy). Fix by applying a corrected policy with the minimal change (use the previous version from state/history), and test policies in a non-prod bucket first — bucket policies are immediate and can lock out your own pipeline.
20. **Q:** Costs spiked and the culprit is an S3 bucket.
**A.** Check: storage class vs access (IA minimum durations/retrieval fees), noncurrent versions accumulating (versioning without lifecycle), incomplete multipart uploads, request volume (small-object churn/LIST loops), data transfer out via NAT (use gateway endpoints), and KMS request costs (enable bucket keys). S3 Storage Lens + Cost Explorer by usage type names the culprit quickly.
21. **Q:** An object was deleted that shouldn't have been, and versioning was off.
**A.** Check soft-delete options (there aren't S3 object-level soft deletes without versioning), replication copies (if any), backups, and whether the data can be regenerated. If not, it's loss — then fix: versioning + lifecycle on noncurrent versions + MFA delete/Object Lock for critical prefixes + `s3:DeleteObject` removed from application roles where not needed.
22. **Q:** Cross-account access worked for small objects but fails for large ones.
**A.** Multipart uploads/`s3:ListBucket`/`s3:GetObjectVersion` permissions may be missing, or — more commonly — KMS encryption: the uploading/downloading role lacks `kms:Decrypt`/`GenerateDataKey` or the key policy doesn't allow the account. Check the error code/XML (`AccessDenied` on the KMS key vs S3) and the CloudTrail KMS events.

**⚖️ Trade-off**
23. **Q:** Terraform-managed objects vs CI-deployed content?
**A.** Terraform for bucket *configuration*; the app pipeline for object content (`aws s3 sync`, framework deploys) because content changes constantly and shouldn't be in state. Managing objects in Terraform bloats state (and the cost/history) and couples deploys to infra pipelines.
24. **Q:** SSE-S3 vs SSE-KMS vs bucket keys?
**A.** SSE-S3 is simple and free (no KMS request charges) but offers no per-key control or decrypt audit; SSE-KMS gives you control, cross-account grants, and CloudTrail audit at per-request KMS cost — enable S3 Bucket Keys to cut that cost by up to ~99%. Compliance usually decides; default to SSE-KMS with bucket keys for sensitive data.
25. **Q:** One bucket per workload vs a shared bucket with prefixes?
**A.** Per workload: clean ownership, policies, lifecycle, and blast radius — more buckets to manage (automate with a module). Shared with prefixes: fewer resources but entangled policies/lifecycles and a bigger blast radius. Default to per workload/environment, and reserve shared buckets for genuinely shared data with documented ownership.
26. **Q:** Public website hosting vs CloudFront + private bucket?
**A.** The website endpoint is HTTP-only, requires public objects, and can't do TLS/custom headers/caching controls — dev only. CloudFront + OAC gives HTTPS, caching, WAF, and keeps the bucket private; it's the production answer, and it's cheap.
27. **Q:** Object Lock (compliance) vs versioning + deny policies?
**A.** Object Lock in compliance mode is irreversible until the retention expires (even root can't delete) — the strongest anti-ransomware/anti-insider control, but it can't be undone, so scope it (specific buckets/prefixes and retention periods) and be sure. Versioning + deny policies are flexible but an admin or attacker with sufficient permissions can still destroy data — say that trade honestly.
28. **Q:** `prevent_destroy` everywhere vs only on data resources?
**A.** Applying `prevent_destroy` broadly makes legitimate cleanup painful (and people remove it in a hurry); use it deliberately on stateful resources — S3 buckets with data, databases, state buckets, KMS keys, DNS zones — and rely on policy/approvals elsewhere. Document why each one has it.

**🎯 Senior**
29. **Q:** What does your standard S3 module produce?
**A.** Private by default (public-access block, ownership controls enforced), SSE-KMS with bucket keys, versioning on, lifecycle rules (transition + noncurrent expiration + multipart abort), access logging to a separate bucket, `aws:SecureTransport` enforcement, optional Object Lock and replication inputs, KMS key + alias optional, tagging standard (owner/env/app/data-class), outputs of name/ARN only, `prevent_destroy` where the bucket holds data, and CI policy checks that fail the plan if any of the security settings are disabled.

**🎯 Senior signal:** "the bucket policy alone doesn't grant access to SSE-KMS objects — the key policy must too", versioning without lifecycle as a cost trap, and migrating rather than recreating a bucket. Those three are data-layer maturity.

---

## 2. RDS & DynamoDB — `rds-dynamodb.md`

**⚡ Rapid**
1. **Q:** Core RDS resources in Terraform?
**A.** `aws_db_instance` (or `aws_rds_cluster` + `aws_rds_cluster_instance` for Aurora), `aws_db_subnet_group` (private subnets), `aws_db_parameter_group`/`aws_rds_cluster_parameter_group`, `aws_security_group` (or SG rules) limiting access to the app tier, `aws_db_instance_automated_backups_replication`/`aws_db_snapshot_copy` for DR, and Secrets Manager for the password (`aws_secretsmanager_secret` + managed rotation).
2. **Q:** How do you handle the master password without committing it?
**A.** Prefer `manage_master_user_password = true` on `aws_db_instance` (RDS manages the secret in Secrets Manager) — the modern AWS approach. Otherwise generate with `random_password`, store in Secrets Manager, and mark the variable `sensitive`. Never in tfvars in Git.
3. **Q:** `identifier` changes — what happens?
**A.** For RDS, changing the identifier can force replacement (data loss) depending on the attribute; some changes are in-place (`instance_class`, `allocated_storage`, `backup_retention_period`). Always read the plan for "must be replaced" before applying — it's the single most dangerous RDS plan line.
4. **Q:** How do you make RDS highly available?
**A.** `multi_az = true` (synchronous standby, automatic failover), `backup_retention_period > 0` with `backup_window` aligned off-peak, `deletion_protection = true`, a maintenance window, and parameter groups sized appropriately. Aurora: multiple instances across AZs with a cluster endpoint.
5. **Q:** Where do read replicas fit?
**A.** `aws_db_instance` with `replicate_source_db` (or Aurora reader instances) for read scaling and DR; each has its own endpoint and version, and promotion is manual (`aws_db_instance` recreation as standalone) — plan that process rather than assuming it's automatic.
6. **Q:** What RDS settings do people forget in Terraform?
**A.** `storage_encrypted` (must be set at creation — can't be enabled later without a snapshot/restore dance), `performance_insights_enabled` (+ KMS key), `enabled_cloudwatch_logs_exports` (postgresql/mysql error & slow query logs), `auto_minor_version_upgrade`, `monitoring_interval`, and `deletion_protection`.
7. **Q:** Core DynamoDB resources?
**A.** `aws_dynamodb_table` (hash/range key, GSIs/LSIs, `billing_mode` + `read_capacity`/`write_capacity` or on-demand, `server_side_encryption`, point-in-time recovery, TTL attribute, streams), and `aws_appautoscaling_target`/`policy` for capacity autoscaling.
8. **Q:** What's the DynamoDB table-change danger?
**A.** Changing the hash/range key or LSIs forces replacement (data loss); GSIs can be added/removed online. Also renaming the table means a migration. Get the key schema right in review — it's the one irreversible decision.

**🔍 Deep dive**
9. **Q:** Design the RDS layer for a production app in Terraform (HA, backups, DR, security).
**A.** Private subnets in 3 AZs with a subnet group, SG allowing only the app tier's SG, `multi_az = true`, storage encrypted with a CMK, automated backups to 35 days plus a manual snapshot copy cross-region (or AWS Backup with a cross-region plan) for DR, `deletion_protection = true`, Performance Insights + log exports to CloudWatch, parameter group tuned (max_connections, log_min_duration), `manage_master_user_password = true`, and a KMS key with the right policy for cross-account restores. Add CloudWatch alarms on CPU, free storage, connections, replica lag, and failover events; document RPO/RTO (backup frequency sets RPO; restore time sets RTO).
**↳ Follow-up:** "How would you upgrade the major version?"
**A.** Use a blue/green deployment (RDS Blue/Green with a new instance on the target version) or a replica-based upgrade with a cutover window; test the app against the new version in staging first, and keep the old instance available for rollback. In Terraform, model it as a new resource/module call and cut over deliberately — in-place major upgrades are risky with no fast rollback.
10. **Q:** How do you scale a DynamoDB table in Terraform?
**A.** On-demand for spiky/unpredictable; provisioned with `aws_appautoscaling_target` + policies on `ReadCapacityUtilization`/`WriteCapacityUtilization` (scale-in more conservatively than scale-out) for predictable loads; GSIs have separate capacities (autoscale them too). Add alarms on `ConsumedReadCapacity`/`ThrottledRequests`.
11. **Q:** How do you do point-in-time recovery and backups for DynamoDB?
**A.** `point_in_time_recovery { enabled = true }` (35-day window) plus `aws_dynamodb_table` `server_side_encryption` with a CMK, and periodic `aws_dynamodb_table` backups (`aws_backup_plan` with a vault for long retention/cross-region). Exports to S3 (`aws_dynamodb_table_export`) for analytics/long-term archive. Test a restore — a table restore creates a *new* table, so the app needs a documented cutover.
12. **Q:** How do you manage schema/migrations with Terraform in the picture?
**A.** Terraform manages infrastructure and users/roles, not application schema. Use a migration tool (Flyway/Alembic/Liquibase/`atlas`) in the app pipeline with versioned, backward-compatible migrations, and keep Terraform out of DDL. Some teams allow Terraform for roles/grants — draw the boundary explicitly.
13. **Q:** How do you connect an autoscaling app tier to RDS safely?
**A.** RDS Proxy in front of RDS (multiplexes connections, faster failover), connection-pool sizing matched across the fleet (pool × tasks ≤ max_connections or proxy limits), and alarms on `DatabaseConnections`. This is the classic connection-exhaustion incident — Terraform should create the proxy with its IAM role and secrets permissions.
14. **Q:** How do you handle parameter groups and version upgrades in Terraform?
**A.** `aws_db_parameter_group` named with the family version (e.g. `postgres16`), created before the instance and referenced (`parameter_group_name`) so changing a parameter triggers a controlled reboot; apply with `apply_method` where supported to defer reboots. Never rename the group in place — create new and switch with a maintenance window.
15. **Q:** How do you protect production data in Terraform?
**A.** `deletion_protection = true`, `lifecycle { prevent_destroy = true, ignore_changes = [snapshot_identifier] }` on instances/tables, backups + cross-region copies, and an IAM policy for the pipeline that denies `rds:DeleteDBInstance`/`dynamodb:DeleteTable` in production. Then a change-review rule: any plan containing a replacement of a data resource requires a second approver and a maintenance window.

**🚨 War room**
16. **Q:** A plan says the RDS instance "must be replaced". What now?
**A.** Identify the forcing attribute (an immutable one like `identifier`, `username` changes in some engines, `engine`/`engine_version` in certain paths, `storage_encrypted` toggling, or a subnet group/VPC change). Then either restore the attribute to its previous value (no change) or plan a migration: snapshot → restore to a new instance with the desired config → test → cut over the app (via the failover group/endpoint/DNS) → decommission. Never let a single apply replace a production database.
17. **Q:** A DynamoDB table was recreated during an apply and the data is gone.
**A.** Restore from PITR (35 days, to a new table) or a backup, then repoint the app (config/env) and reconcile any writes since the restore point. Then fix: `prevent_destroy` + key-schema changes banned in review + `deletion_protection` on tables + the pipeline role denied `dynamodb:DeleteTable` in prod. This is a process failure as much as a config one.
18. **Q:** The app can't connect after a failover event.
**A.** The app is probably using the instance endpoint rather than the cluster/failover-group endpoint, or caching a connection/DNS for too long, and the connection pool doesn't retry. Fix the endpoint usage, enable RDS Proxy for faster recovery, and add retry logic with short timeouts. Then verify the Terraform config exposes the right endpoint to the app (multi-AZ failover keeps the same endpoint; Aurora writer endpoints change).
19. **Q:** Free storage on RDS is trending down and autoscaling is off.
**A.** Identify growth (tables/indexes, binary logs, temp files, bloat), enable `max_allocated_storage` (with a ceiling so it can't grow unbounded), and address the source (retention of logs, archiving, index bloat/`VACUUM`). Add an alarm at 80% — RDS hitting 100% makes the instance unusable, and recovery is a restore.
20. **Q:** Security Hub flags the RDS instance's parameter group has `rds.force_ssl` disabled.
**A.** Fix the parameter (`rds.force_ssl = 1`) in the parameter group via Terraform (a controlled reboot), then verify the app connects with TLS (update connection strings to require SSL), and add the check to CI policy so it can't regress. Also rotate the DB credentials if plaintext connections were in use on a shared network.
21. **Q:** Costs increased because of unintended read replicas.
**A.** Check for replicas created by a module default or a previous DR test that weren't torn down, provisioned capacity on idle DynamoDB tables (autoscaling/minimums), over-provisioned instance classes with low utilisation (Performance Insights), backup retention longer than needed, and unused snapshots/manual copies. Right-size and set retention deliberately; tag everything for attribution.
22. **Q:** An apply changed the DynamoDB billing mode and the bill jumped.
**A.** Switching from provisioned+autoscaling to on-demand (or vice versa) can raise cost at steady high volume; verify the actual read/write throughput pattern and either return to provisioned with autoscale or keep on-demand if the workload is spiky. Add a budget/cost-anomaly alert on the table and review billing mode as part of the design, not by accident.

**⚖️ Trade-off**
23. **Q:** RDS vs Aurora vs DynamoDB, from a Terraform perspective?
**A.** RDS: familiar relational with full engine control/parameter groups; Aurora: cluster resources (writer/reader endpoints, faster failover, storage autoscaling, better read scaling) but different abstractions and cost model; DynamoDB: key-value/scale-out with capacity modes and no schema migrations. The Terraform shapes differ (instance vs cluster vs table) — pick by access pattern and operations, then express it accordingly.
24. **Q:** Multi-AZ vs read replicas vs Aurora?
**A.** Multi-AZ is for availability (single writer, standby, failover) — not read scaling; read replicas scale reads and can aid DR but are asynchronous; Aurora gives a shared-storage cluster with fast failover and many readers. Confusing availability with scaling is a classic interview miss.
25. **Q:** DynamoDB provisioned+autoscaling vs on-demand?
**A.** Provisioned+autoscaling is cheaper at predictable, high volume with policy-tuned targets; on-demand is simpler, handles spikes instantly, and costs more per request. Start on-demand, move to provisioned when the pattern is clear (and be careful with GSIs).
26. **Q:** Terraform-managed passwords vs Secrets Manager rotation?
**A.** Prefer `manage_master_user_password`/rotation in Secrets Manager so the value never lives in Terraform state as a resource attribute the app reads; apps fetch the current secret with their identity. If Terraform sets the password itself, you must rotate it later and handle state exposure — a weaker posture.
27. **Q:** One RDS instance per service vs a shared database server?
**A.** Per service: isolation, sizing autonomy, cleaner ownership — higher cost and more instances to manage. Shared: cheaper but couples teams, creates noisy-neighbour issues, and makes upgrades/perf tuning a committee decision. Default to per service (or per bounded context) with a smaller class and scale up as needed.
28. **Q:** Blue/green upgrades vs in-place?
**A.** Blue/green (or a replica-based approach) gives a tested cutover and a rollback path, at the cost of running two environments briefly; in-place is cheaper/faster but risky, often with no quick rollback. For production databases on a major version, blue/green or replica-based — say the rollback story explicitly.

**🎯 Senior**
29. **Q:** What does a production database module look like in your Terraform repo?
**A.** Private subnets + SG restricted to the app tier; encryption with a CMK set at creation; Multi-AZ; backups (35 days) with a cross-region copy or AWS Backup plan; `deletion_protection` and `prevent_destroy`; Performance Insights + log exports + alarms (CPU/storage/connections/replica lag); Secrets Manager-managed credentials with rotation; parameter group with the security/performance settings baked in; RDS Proxy for connection management; read replica/DR inputs with documented RPO/RTO; and a plan-review rule that any replacement of a data resource requires a second approver.

**🎯 Senior signal:** "storage_encrypted can't be enabled later without a restore", multi-AZ ≠ read scaling, and `manage_master_user_password` so the secret isn't in state. Those three are the fingerprints of someone who has owned databases on AWS.
