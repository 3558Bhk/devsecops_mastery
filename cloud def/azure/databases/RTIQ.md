# RTIQ — Azure SQL (Real-Time Interview Questions)

> **Cloud:** Azure · **Domain:** Azure SQL Database / Managed Instance / SQL on VM · **Target roles:** SDE-3 · Cloud Engineer · DevOps · DevSecOps · SRE · Platform Engineer · **Reading time:** ~9 min

**How this file is used live:** interviewers use Azure SQL to test whether you understand *service tiers, connection behaviour, and HA* rather than T-SQL syntax. Expect "which tier for this workload", "the app was fine and now it's timing out", "design HA/DR", and always a question about Private Endpoints and Entra ID auth.

**Legend:** ⚡ Rapid · 🔍 Deep dive + follow-ups · 🚨 War room · ⚖️ Trade-off debate · 🎯 Senior signal

---

**⚡ Rapid**
1. **Q:** Azure SQL Database vs Managed Instance vs SQL on a VM — how do you choose?
**A.** Single Database: fully managed, per-DB, best for new cloud-native apps. Elastic Pool: many DBs sharing resources (SaaS multi-tenant — cheapest per DB). Managed Instance: near-100% SQL Server compatibility, instance-level features (SQL Agent, cross-DB queries, CLR), lift-and-shift. SQL on VM: full control/patching responsibility, needed for unsupported versions/OS-level access.
2. **Q:** DTU vs vCore?
**A.** DTU is a bundled compute/IO/storage measure (Basic → Premium) for simplicity; vCore is independent compute+storage with the ability to buy reserved capacity and use Azure Hybrid Benefit (bring your SQL Server licence). For cost optimisation and Elastic Pools at scale, vCore.
3. **Q:** Which tier for a production OLTP app?
**A.** General Purpose (or Business Critical if you need low-latency local SSD + built-in read replicas), provisioned compute, zone-redundant where the region supports it. Hyperscale for very large databases (up to ~100 TB) with fast scale-out and rapid restore-from-snapshot.
4. **Q:** Serverless vs provisioned compute?
**A.** Serverless auto-scales and can auto-pause (great for intermittent/dev workloads, with cold-start delay); provisioned gives predictable performance for steady production load. Serverless for spiky/low duty-cycle, provisioned for sustained.
5. **Q:** Business Critical gives you what over General Purpose?
**A.** Local SSD storage, much lower I/O latency, and a free built-in read-only replica (plus in-memory OLTP support) — plus higher availability SLA. It costs significantly more.
6. **Q:** How do you authenticate to Azure SQL?
**A.** Entra ID (recommended — managed identity for apps, no passwords) or SQL authentication (users/passwords, needed in some cases but requires stricter secrets handling). Always allow-list the app and use least privilege (`db_datareader`+`db_datawriter` rather than `db_owner`).
7. **Q:** How do you connect privately?
**A.** Private Endpoint (private IP in your VNet) with public network access disabled + private DNS zone `privatelink.database.windows.net`. Service endpoints/allow-listed IPs are the weaker alternative.
8. **Q:** What's the failover behaviour of the built-in HA?
**A.** Each tier maintains a standby (or several) with automatic failover on infrastructure failure — typically 30–120 s with connection retries needed. Business Critical/Hyperscale use Always On availability groups under the hood; your app must have retry logic and short connection timeouts.
9. **Q:** Where do backups come from?
**A.** Automatic full differential/log backups with point-in-time restore (default 7 days, configurable up to 35 for single DB) plus long-term retention (LTR) policies to Blob for compliance. Test the restore, don't assume it.

**🔍 Deep dive**
10. **Q:** Design a multi-tenant SaaS: 800 customer databases. Approach?
**A.** Elastic Pool (or many pools) with Pool-level metrics to size eDTUs/vCores, sharding by customer for scale-out where needed, resource governance per DB so noisy tenants don't starve others, per-tenant connection routing (a catalog DB), and automated provisioning/deployment of schema per tenant via pipelines. Add per-tenant observability — otherwise one tenant's incident is invisible until it affects the pool.
11. **Q:** How do you do zero-downtime schema migrations at scale?
**A.** Backward-compatible migrations only (expand → migrate → contract), deployed separately from app code, with the app supporting both schemas during the transition; use online index operations where supported, batch large updates, and gate with feature flags. Never a blocking `ALTER` on a hot table in one shot; roll out per shard/tenant with monitoring.
12. **Q:** The app hits "connection limit reached" during peaks. Fix properly.
**A.** Check the connection limit for the tier and actual concurrency; then (1) add/verify connection pooling in the app with sane sizes, (2) eliminate pool-per-request and connection leaks, (3) use retry logic with backoff to survive failovers, (4) scale the tier as the last resort. Azure SQL also has gateway-related limits; long-running idle connections consume the budget.
13. **Q:** Design HA and DR across regions.
**A.** Local HA: zone-redundant tier configuration (or Business Critical) for datacentre failures. DR: auto-failover groups with a secondary in another region (readable secondary, automatic/manual failover, listener endpoint that apps use instead of the server name), plus geo-backup for Hyperscale. Test failover, and remember the app connection strings must use the failover-group listener.
14. **Q:** How do you secure Azure SQL end-to-end?
**A.** Private endpoint + disabled public access, Entra ID auth with managed identities, Entra-only admin, TDE with CMK (customer-managed key in Key Vault), Auditing to Log Analytics/Storage (immutable), Defender for SQL (vulnerability assessment + threat detection), Advanced Threat Protection alerts, data classification/labels, Dynamic Data Masking for PII in lower environments, and least-privilege DB roles.
15. **Q:** How do you monitor and Alert?
**A.** Query Store for regression analysis, Azure SQL Insights/Database Watcher, metrics: DTU/vCore %, worker/CPU, IO, sessions, deadlocks, storage %, plus log alerts on errors. Alarms at 80% resource utilisation, on blocked/deadlock spikes, and on failed connections. Query Store is the one people forget — call it out.
16. **Q:** How do you optimise an expensive query without changing the app?
**A.** Query Store → find the top duration/CPU queries → review the plan and missing indexes (`sys.dm_db_missing_index_details`) → add/adjust indexes (with an eye on write overhead) → update statistics → consider parameter sniffing fixes (Query Store forced plans, `OPTION (RECOMPILE)`), and compatibility level. Then verify with before/after metrics, not intuition.
17. **Q:** What is the difference between scaling up, scaling out, and Hyperscale?
**A.** Scale up = bigger tier (downtime usually minimal for vCore changes). Scale out = read scale-out (BC gives a free readable secondary; Hyperscale gives named read replicas) or app-level sharding for writes. Hyperscale separates compute from a page-blob storage layer so you can add replicas and restore quickly at large sizes.
18. **Q:** How do you handle long-running reports without hurting OLTP?
**A.** Read replicas (read-only routing via the connection string `ApplicationIntent=ReadOnly` or the replica endpoint in Hyperscale), a separate reporting database fed by CDC/Synapse/Data Factory, or off-peak scheduling with resource governor. Never point dashboards at the primary.

**🚨 War room**
19. **Q:** Users report timeouts; CPU is 100% on the database. First 15 minutes?
**A.** Query Store/`sys.dm_exec_requests` to find the top consumer, check blocking chains (`sys.dm_os_waiting_tasks`) and whether a runaway report/job is the culprit; kill the offender if safe, then check for a missing index or plan regression and a recent deploy. Also verify it's not a connection storm from an app restart. Report impact and ETA early.
20. **Q:** After a failover, the app is still erroring 20 minutes later.
**A.** The app is probably still using the old server name instead of the failover-group listener (or cached DNS), has no retry logic for the failover window, or the secondary was a lower tier sized for DR and can't take production load. Fix connection strings, implement `SqlClient` retry logic (`ConnectRetryCount`/`ConnectRetryInterval`), and size the secondary realistically.
21. **Q:** You need to restore one table to a point 3 hours ago without restoring the whole DB.
**A.** Restore to a new database at that point in time (PITR), extract the data, and merge into production; Azure SQL doesn't do table-level PITR natively, so this copy-and-merge is the standard approach (with care around dependencies and FKs). Mention doing it in a maintenance window with a validation step.
22. **Q:** Storage is at 95% and autogrow isn't instant. What do you do?
**A.** Identify what's growing (table sizes, indexes, log), clean/archive/compress where possible, and scale the storage cap up (a fast metadata operation on vCore tiers) before touching data deletion. Then set up capacity monitoring at 80% and a data-retention policy so it never gets there again.
23. **Q:** A certificate/cipher change breaks an old client library. Response?
**A.** You can't force the server to accept insecure protocols permanently (and shouldn't). Identify the clients by TLS version in connection logs, patch/upgrade the drivers (this is usually an old JDBC/ODBC/Node library), and use the short window of tolerance to fix fast. Add a driver version standard to your app templates so it can't recur.
24. **Q:** Defender flags a suspicious `xp_cmdshell`/brute-force pattern. What now?
**A.** Treat as attempted compromise: review Defender for SQL alerts and audit logs, check for successful logins and new users/permissions, block the source IPs (firewall/NSG), rotate the SQL admin credentials and any secrets the app used, and verify the DB isn't publicly reachable (`public_network_access_enabled`). Then remove the exposure permanently.

**⚖️ Trade-off**
25. **Q:** Azure SQL vs Cosmos DB vs PostgreSQL Flexible Server?
**A.** Azure SQL for relational/T-SQL/enterprise workloads and existing SQL Server skills. Cosmos DB for globally distributed, multi-model, low-latency key-based access at massive scale. PostgreSQL Flexible Server for open-source/PG ecosystems with more control and cheaper licensing. The data model and query patterns decide — not the brand.
26. **Q:** Single database with bigger tier vs sharding across many databases?
**A.** Vertical scaling has a ceiling (tier limits) and a single blast radius; sharding gives near-infinite scale but demands routing, distributed queries, and cross-shard transactions. Start vertical, shard only with evidence — sharding is an irreversible architectural commitment.
27. **Q:** Elastic Pool vs database per customer at scale?
**A.** Pools dramatically cut cost when many DBs have low/variable load, but introduce noisy-neighbour risk and pool-level limits; separate DBs (or servers) give isolation at higher cost. Regulated/large tenants often get dedicated resources while the tail shares a pool.
28. **Q:** Zone-redundant vs locally redundant?
**A.** Zone-redundant survives a datacentre failure within the region with a higher SLA (and higher cost/possible region limits); locally redundant is cheaper but only tolerates hardware failure. For production with an availability requirement, zone-redundant is the default answer.
29. **Q:** Use the built-in read replica vs a separate reporting DB?
**A.** Built-in replica: free, zero-latency-ish, but shared resources on BC and no isolation from production queries' impact. Separate reporting DB (Synapse/Data Factory/CDC): full isolation, better for heavy analytics, but ETL latency and cost. Reporting load characteristics decide.

**🎯 Senior**
30. **Q:** What does "production-ready Azure SQL" look like to you?
**A.** Private endpoint + no public access, Entra-only auth with managed identities, least-privilege DB roles, TDE with CMK, auditing to an immutable store, Defender for SQL on, zone-redundant (or BC) for HA, failover group to a DR region with apps using the listener, PITR + LTR verified by restore drills, Query Store enabled, resource alerts at 80%, connection pooling and retry logic baked into app templates, and schema migrations deployed via pipeline with rollback.

**🎯 Senior signal:** failover-group listener + app retry logic, read-only routing for reports, and "restore to a new DB and merge" for table-level recovery. Those three are where senior candidates separate themselves.
