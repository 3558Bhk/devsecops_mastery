# Amazon RDS for MySQL — Interview Questions

> **Cloud:** AWS · **Category:** Databases · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~10 min

---

## JSON File Format

RDS instances are declared in JSON via CloudFormation `AWS::RDS::DBInstance` (and `AWS::RDS::DBParameterGroup` / `DBSubnetGroup`).

```json
{
  "Type": "AWS::RDS::DBInstance",
  "Properties": {
    "Engine": "mysql",
    "EngineVersion": "8.0",
    "DBInstanceClass": "db.t3.medium",
    "AllocatedStorage": 100,
    "MultiAZ": true,
    "StorageEncrypted": true,
    "DBParameterGroupName": "my-param-group",
    "DBSubnetGroupName": "my-subnet-group"
  }
}
```

**Key fields:** `Engine` / `EngineVersion` · `DBInstanceClass` · `MultiAZ` (synchronous standby = HA) · `StorageEncrypted` · `DBParameterGroupName` / `DBSubnetGroupName`. Parameter-group values themselves are name/value JSON.


## Case A — Basic

**A1. What is Amazon RDS and why use it for MySQL?**
**Answer:** RDS is a managed relational database service. It automates provisioning, patching, backups, snapshots, failover, and scaling for engines like MySQL, so you focus on the application instead of database administration.

**A2. What does RDS manage for you vs. what you still manage?**
**Answer:** AWS manages the engine install, OS/DB patching, backups, replication, failover, and monitoring infrastructure. You manage schema, query tuning, users/privileges (mostly), and application connections.

**A3. What is a DB instance and a DB instance class?**
**Answer:** A DB instance is your isolated database environment (the "server"). The **instance class** defines CPU/memory/network (e.g., `db.t3`, `db.r6g`, `db.m5`).

**A4. What is Multi-AZ deployment?**
**Answer:** RDS maintains a synchronous standby replica in a **different Availability Zone**. On failure/planned maintenance, RDS automatically fails over to the standby with no manual intervention — it's for **high availability**, not read scaling.

**A5. What is a Read Replica?**
**Answer:** An asynchronously replicated copy of the database used to offload **read traffic**. You can have up to 15 read replicas, cross-region, and promote one to primary. It's for **read scaling**, not HA.

**A6. What is the difference between Multi-AZ and Read Replicas?**
**Answer:** Multi-AZ = synchronous standby for automatic failover (HA). Read Replicas = asynchronous copies for read scaling (and can serve as DR targets when promoted). You can combine both.

**A7. What are automated backups in RDS?**
**Answer:** Daily full snapshots + continuous transaction logs enabling **point-in-time recovery (PITR)** to any second within the retention window (1–35 days, default 7).

**A8. What is a DB snapshot?**
**Answer:** A manual, user-initiated point-in-time backup stored in S3 that persists until you delete it (survives instance deletion, unlike automated backups).

**A9. What is the difference between RDS and running MySQL on EC2?**
**Answer:** RDS = managed (patching, backups, failover automated, no OS access). EC2 = full control (custom configs, plugins, OS-level tuning) but you own all administration. Choose RDS unless you need control RDS doesn't offer.

**A10. What is a parameter group?**
**Answer:** A set of engine configuration parameters (e.g., `max_connections`, `innodb_buffer_pool_size`, time zones) applied to the DB instance — the RDS way to tune MySQL without editing my.cnf directly.

**A11. What is an option group?**
**Answer:** Enables optional features for the engine (e.g., audit logging, MEMCACHED, or backups to S3) attached to the DB instance.

**A12. What is a subnet group?**
**Answer:** The list of subnets (across AZs) where RDS can place its instances and ENIs — required for Multi-AZ and VPC networking.

**A13. How do you connect to RDS privately, and how is security controlled?**
**Answer:** RDS lives in private subnets; apps connect via the **endpoint DNS name**. Security is controlled by **security groups** (inbound port 3306 from the app SG), and the master username/password (stored in **Secrets Manager** is best practice).

**A14. What is RDS encryption and how is it enabled?**
**Answer:** Encryption at rest via KMS is set **at creation time** (can't be added later to an unencrypted instance) and covers storage, snapshots, read replicas, and logs. TLS encrypts in transit.

**A15. What is the difference between a DB instance identifier and the endpoint?**
**Answer:** The identifier is the unique name you give the instance. The **endpoint** (`name.xyz.region.rds.amazonaws.com`) is the DNS address clients use to connect; it changes on failover events only if you don't use the failover-friendly CNAME (RDS proxy or custom DNS).

---

## Case B — Advanced (Senior)

**B1. Explain how Multi-AZ failover works, its RTO, and what causes a failover.**
**Answer:** The primary replicates synchronously to a standby in another AZ. Failover triggers on AZ outage, instance failure, storage failure, or during patching/instance-class changes. RDS flips the DNS (CNAME) to the standby, typically **60–120 seconds**. The endpoint name stays the same so apps reconnect. Use the **RDS failover** CloudWatch event to automate post-failover tasks.

**B2. How does RDS do automated backups and point-in-time recovery, and what are its limitations?**
**Answer:** Daily snapshot + continuous transaction log archiving to S3. PITR lets you restore to any point in the retention window by replaying logs onto a new instance. Limitations: retention max 35 days, backups pause on certain engine changes, and restore is to a **new instance** (not in-place) — plan DNS/connection cutover.

**B3. What is RDS Proxy and when should you use it?**
**Answer:** A managed connection pooler in front of RDS. It reduces the "too many connections" problem for Lambda/serverless and bursty apps, pools connections to survive failovers faster (~up to 66% faster), and supports IAM authentication. Use it for Lambda-heavy or microservice workloads; it's not a read-splitter.

**B4. How do you tune MySQL on RDS: parameter groups, storage, and instance sizing?**
**Answer:** Set key params via parameter group (buffer pool ~ 70–80% of memory for dedicated DB, max_connections based on instance class, slow_query_log on, sync_binlog/innodb_flush_log_at_trx_commit per durability needs). Choose gp3/io2 storage, monitor BurstBalance/queue depth, enable Enhanced Monitoring to see OS-level metrics, and right-size with Performance Insights.

**B5. How do read replicas work, and what are their limitations for MySQL?**
**Answer:** Binlog-based **asynchronous** replication to up to 15 replicas (same or cross-region). Limitations: replication lag (reads may be stale), replicas are read-only, and failover to a replica is manual (promote). For disaster recovery you can promote a cross-region replica. Multi-AZ + replicas give both HA and scale.

**B6. How do you achieve zero/minimal-downtime migrations and upgrades on RDS MySQL?**
**Answer:** Use a **blue-green deployment** (RDS feature) or create a new instance with the target version/size, replicate data (mysqldump/DMS/outbound replication), verify, then cut over the DNS/endpoint (or RDS Proxy). For minor version upgrades use the maintenance window or apply with Multi-AZ to minimize downtime (the standby is upgraded first, then failover).

**B7. What is Performance Insights and how do you use it for troubleshooting?**
**Answer:** A dashboard showing DB load by SQL statement, wait events, host, and user over time (7 days free, longer retention paid). Use it to find the top SQL causing load, identify wait bottlenecks (e.g., locks, IO, CPU), and correlate with app deploys — the first place to look for "database is slow."

**B8. How does RDS handle minor vs major version upgrades, and what are the risks?**
**Answer:** Minor upgrades are auto-applied in the maintenance window (or manually) with brief downtime unless Multi-AZ (near-zero via failover). **Major** upgrades (e.g., MySQL 5.7 → 8.0) are manual, can be lengthy, and can break compatibility — test with a clone, check deprecated features, and use blue-green. Always take a snapshot.

**B9. How do you secure RDS comprehensively?**
**Answer:** Private subnets, SG restricted to app SG, no public accessibility, encryption at rest (KMS) + TLS in transit, IAM database authentication (or Secrets Manager for creds + rotation), parameter/option groups for audit logs, CloudTrail for API audit, guardrails (Config/SCPs), and delete protection enabled. Defense in depth at network, auth, and data layers.

**B10. What are RDS's main limits you must design around?**
**Answer:** Max 40 DB instances (soft), storage up to 64 TiB (engine-dependent), 15 read replicas, retention 35 days, and instance-class scaling requires downtime unless Multi-AZ (brief failover). Plan for connection limits, IOPS caps by storage type, and region/engine feature availability.

**B11. How does storage autoscaling work on RDS, and when is it useful?**
**Answer:** With storage autoscaling, RDS grows the volume automatically when free space is low (up to a max threshold you set). Useful for unpredictable growth to avoid manual intervention/outages; pair with monitoring so you're not surprised by cost. Doesn't shrink — you can't scale storage back down.

**B12. Compare RDS vs Aurora (MySQL-compatible) — when to pick which?**
**Answer:** Aurora = AWS's cloud-native engine with ~3–5x throughput, up to 15 low-lag replicas, storage auto-scaling to 128 TiB, and better durability (6 copies across 3 AZs), but pricier and Aurora-specific. RDS MySQL = standard community MySQL, cheaper entry, broader version/plugin compatibility, cross-cloud familiarity. Pick Aurora for scale/HA demands; RDS for standard MySQL needs and cost.

---

## Case C — Scenario

**C1. Scenario:** Your app suddenly throws "Too many connections" during a traffic spike (Lambda → RDS).
**Question:** Diagnose and fix.
**Expected answer:** Each Lambda invocation opens a connection; the spike exhausted `max_connections`. Fix: use **RDS Proxy** to pool connections between Lambda and RDS, tune `max_connections` appropriately for the instance class, add connection reuse/limits in the app, and consider Aurora (higher connection capacity). Monitor with CloudWatch DatabaseConnections.

**C2. Scenario:** A critical query is slow at 2 PM daily. CPU is fine, but the DB feels "stuck."
**Question:** How do you find the cause?
**Expected answer:** Use **Performance Insights** to inspect DB load at 2 PM — look at top SQL, wait events (e.g., lock waits, `innodb` row locks), and hosts. Cross-check Enhanced Monitoring for CPU/IO. Likely a long-running transaction holding locks (e.g., a daily job); fix the query/index or reschedule. Verify with `SHOW PROCESSLIST`/slow query log.

**C3. Scenario:** You need zero-downtime upgrade from MySQL 5.7 to 8.0 on a production single-AZ instance.
**Question:** Design the migration.
**Expected answer:** Use a **blue-green deployment**: create a green 8.0 instance, replicate data (or use outbound replication/DMS), verify compatibility and performance, then switch the app to the green endpoint (or swap via RDS Proxy/Route 53 CNAME) and decommission the old. Alternatively, first move to Multi-AZ and upgrade the standby first for minimal downtime. Never upgrade in-place without a tested snapshot.

**C4. Scenario:** During an AZ outage, your Multi-AZ MySQL failed over. The app kept working but a few transactions near the failure were lost.
**Question:** Explain why and how to reduce data loss.
**Answer:** Multi-AZ uses synchronous replication to the standby, so normally zero data loss on failover — but in-flight **uncommitted** transactions at the moment of failure are rolled back (that's expected). To minimize loss/perceived loss: use appropriate durability settings (`sync_binlog=1`, `innodb_flush_log_at_trx_commit=1`), connection retries, and RDS Proxy for faster recovery. True "zero loss" beyond committed data isn't possible during an outage.

**C5. Scenario:** Compliance says backups must survive even if the whole RDS instance is deleted, and you must be able to restore from 40 days ago.
**Question:** What do you configure?
**Answer:** Automated backups max out at 35 days, so for 40 days use **manual snapshots** (retained on a schedule via AWS Backup, which also supports cross-region copies and vault lock) plus automated backups for PITR. Enable **deletion protection** and, ideally, an AWS Backup vault with a retention/immutability policy so backups outlive the instance.

**C6. Scenario:** You run RDS MySQL in a single region. The business wants RPO ≤ 5 min and RTO ≤ 30 min for a regional disaster.
**Question:** Design the DR architecture.
**Expected answer:** Use a **cross-region read replica** (async, near-real-time) as the DR target. On region failure, **promote the replica** to standalone primary and repoint the app (Route 53 failover + updated endpoint). RPO ≈ replication lag (typically seconds–minutes), RTO ≈ promotion + app cutover. Combine with regular cross-region snapshot copies via AWS Backup as a fallback, and document/test the runbook.
