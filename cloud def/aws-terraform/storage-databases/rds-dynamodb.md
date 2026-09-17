# Terraform RDS & DynamoDB (AWS) — Interview Questions

> **Cloud:** AWS · **IaC Tool:** Terraform · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~5 min

---

## Case A — Basic

**A1. What resources make up an RDS instance in Terraform?**
**Answer:** `aws_db_instance`, plus `aws_db_subnet_group`, `aws_db_parameter_group`, an option group (if needed), and security groups.

**A2. How do you declare a basic RDS instance?**
**Answer:** `resource "aws_db_instance" "db" { engine = "postgres" ; instance_class = "db.t3.micro" ; allocated_storage = 20 ; username = ... ; password = ... }`.

**A3. What is `aws_db_subnet_group`?**
**Answer:** A named set of subnets across ≥2 AZs where RDS places the instance/replicas, declared on the instance via `db_subnet_group_name`.

**A4. What is multi-AZ in RDS?**
**Answer:** `multi_az = true` maintains a synchronous standby in another AZ for automatic failover (different from read replicas).

**A5. What is a read replica?**
**Answer:** `aws_db_instance` with `replicate_source_db` creates an async readable copy for scaling reads; for Aurora it's `aws_rds_cluster_instance` in the cluster.

**A6. How do you enable storage encryption?**
**Answer:** `storage_encrypted = true` (and optionally `kms_key_id`) — must be set at creation; it can't be added later without restoring.

**A7. What is an `aws_db_parameter_group`?**
**Answer:** Database engine parameters (e.g. timezone, max connections) applied to instances — like a config profile.

**A8. How do you back up an RDS instance?**
**Answer:** `backup_retention_period`, `backup_window`, and `final_snapshot_identifier` (set this so destroy takes a final snapshot).

**A9. What is `skip_final_snapshot`?**
**Answer:** If true, Terraform deletes the DB without a final snapshot — dangerous in production.

**A10. How do you keep the password out of config?**
**Answer:** Reference Secrets Manager (`data "aws_secretsmanager_secret_version"`) or SSM, or use `manage_master_user_password = true` (RDS-managed secret).

**A11. What is DynamoDB in Terraform?**
**Answer:** `aws_dynamodb_table` — a NoSQL key-value table defined by `hash_key` (and optional `range_key`) plus attribute definitions.

**A12. How do you declare a DynamoDB table?**
**Answer:** `resource "aws_dynamodb_table" "t" { name = ... ; hash_key = "id" ; billing_mode = "PAY_PER_REQUEST" ; attribute { name = "id" ; type = "S" } }`.

**A13. What is `billing_mode` in DynamoDB?**
**Answer:** `PAY_PER_REQUEST` (on-demand) or `PROVISIONED` (explicit `read_capacity`/`write_capacity`).

**A14. What is a DynamoDB GSI?**
**Answer:** A global secondary index (`global_secondary_index` block) with its own key schema for querying by non-primary attributes.

**A15. What is point-in-time recovery (PITR)?**
**Answer:** `point_in_time_recovery { enabled = true }` on DynamoDB tables (and RDS via `backup_retention_period`) for restore to any second in the window.

## Case B — Advanced / Senior

**B1. RDS Multi-AZ vs read replicas — how do they differ and when do you use each?**
**Answer:** Multi-AZ is a synchronous standby for HA/failover (not read scaling); read replicas are async copies for read throughput and DR. Production databases often use both.

**B2. How do you avoid recreating an RDS instance when changing a mutable-vs-immutable setting?**
**Answer:** Know which attributes force replacement (`engine`, `storage_encrypted`, `db_name`) and which update in place (`instance_class`, `storage`). Plan changes accordingly, use `apply_immediately` carefully, and `ignore_changes` where automation owns values.

**B3. What is `apply_immediately` and why defer it?**
**Answer:** If false, changes apply in the next maintenance window (safer); if true, changes apply now (can cause brief downtime). For prod, prefer a scheduled window.

**B4. How do you implement blue-green deployments for RDS?**
**Answer:** Use RDS Blue/Green Deployments (switchover to a staging instance) or create a new instance + promote; with Aurora you can use clones. Terraform manages the resources; the switchover is often an operational step.

**B5. How does Aurora differ from standard RDS in Terraform?**
**Answer:** Aurora uses `aws_rds_cluster` (+ `aws_rds_cluster_instance`) with `engine_mode = "provisioned"` or `serverless`, cluster-level storage, and reader/writer endpoints.

**B6. How do you rotate RDS master passwords with Terraform?**
**Answer:** Use `manage_master_user_password = true` (RDS rotates via Secrets Manager) or store the secret in Secrets Manager with rotation enabled and reference it; avoid rotating by replacing the instance.

**B7. How do you design DynamoDB capacity with autoscaling?**
**Answer:** `aws_appautoscaling_target` + `aws_appautoscaling_policy` on the table/GSI read/write capacities (for PROVISIONED), or simply use `PAY_PER_REQUEST` to skip capacity planning.

**B8. What is the DynamoDB `ttl` attribute and `stream_enabled`?**
**Answer:** `ttl { attribute_name, enabled }` auto-expires items; `stream_enabled` + `stream_view_type` enables change streams consumed by Lambda (e.g. for projections).

**B9. How do you protect RDS/DynamoDB from accidental deletion?**
**Answer:** `deletion_protection = true` (RDS) and `deletion_protection_enabled = true` (DynamoDB), plus `prevent_destroy` in Terraform on production instances/tables.

**B10. How do you connect an app in private subnets to RDS securely?**
**Answer:** RDS in private subnets, app SG allowed on the DB SG port only, encryption in transit (SSL), and no public accessibility (`publicly_accessible = false`).

**B11. What is `aws_dynamodb_table_replica`?**
**Answer:** Adds a global table replica in another region, requiring the table to have streams enabled and consistent settings across regions.

**B12. How do you export/import RDS config between environments with modules?**
**Answer:** A database module with inputs (engine, class, storage, subnets, params, backup, encryption) instantiated per environment, so dev/staging/prod stay consistent but separately configurable.

## Case C — Scenario

**C1. Your RDS instance is about to be recreated because someone changed the engine version string.**
**Answer:** Engine (and major version) changes can force replacement. Pin the exact engine version, use `ignore_changes` if a patch process updates it, and if a major upgrade is needed, do it via snapshot/restore or blue-green, not a recreate.

**C2. Storage is filling up; you need more space without downtime.**
**Answer:** Increase `allocated_storage` (and `max_allocated_storage` for autoscaling) — RDS grows in place. Add storage autoscaling so it scales automatically, and clean up data/retention.

**C3. You must restore a database to a point 3 hours ago.**
**Answer:** Restore from automated backups/snapshots (`aws_db_instance` `restore_to_point_in_time` isn't direct — use snapshot restore via a new instance or CLI), then repoint the app. For DynamoDB, use PITR restore to a new table.

**C4. A compliance rule requires encryption at rest and in transit for the DB.**
**Answer:** `storage_encrypted = true` (+ KMS key), and enforce SSL connections (parameter group `rds.force_ssl = 1`). Add policy-as-code checks so new databases inherit these.

**C5. Read traffic is hammering your single RDS instance.**
**Answer:** Add read replicas (or Aurora reader instances) and split reads to them; for DynamoDB, add GSIs for different access patterns and enable DAX caching if latency-bound.

**C6. A DynamoDB table's scans are slow and costly.**
**Answer:** Design keys/GSIs to avoid scans, use `PAY_PER_REQUEST` or autoscaled provisioned capacity, enable DAX for read caching, and offload analytics to streams + a warehouse instead of scanning the live table.
