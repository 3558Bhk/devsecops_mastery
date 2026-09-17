# Azure SQL Database — Interview Questions

> **Cloud:** Azure · **Category:** Databases · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~9 min

---

## JSON File Format

Azure SQL servers and databases are ARM JSON (`Microsoft.Sql/servers`, `Microsoft.Sql/servers/databases`) with the service tier in `sku`.

```json
{
  "type": "Microsoft.Sql/servers/databases",
  "apiVersion": "2022-05-01-preview",
  "name": "sqlsrv/ordersdb",
  "sku": { "name": "GP_Gen5", "tier": "GeneralPurpose" },
  "properties": {
    "maxSizeBytes": 268435456000,
    "zoneRedundant": false,
    "minCapacity": 0.5,
    "readScaleOut": "Enabled"
  }
}
```

**Key fields:** `sku.name/tier` (GP_Gen5, BC_Gen5, HS_Gen5; or DTU tiers Basic/S0/P1…) · `maxSizeBytes` · `zoneRedundant` (HA) · `minCapacity` (serverless auto-pause) · `readScaleOut` (readable replicas). Firewall rules and failover groups are also JSON.


## Case A — Basic

**A1. What is Azure SQL Database?**
**Answer:** A fully managed, **PaaS** relational database service based on the SQL Server engine — Microsoft handles patching, backups, and HA, while you manage the database and schema.

**A2. What are the Azure SQL deployment options?**
**Answer:** **Azure SQL Database** (single DB or elastic pool, PaaS), **Azure SQL Managed Instance** (near-100% SQL Server compat, PaaS, VNet-native), and **SQL Server on Azure VM** (IaaS, full control).

**A3. What is the difference between SQL Database, Managed Instance, and SQL on a VM?**
**Answer:** **SQL DB** = fully managed, no OS access, some feature limits. **Managed Instance** = managed but with instance-level features (SQL Agent, CLR, cross-DB queries) + VNet integration. **SQL on VM** = you manage everything (OS, patching) with full SQL Server features.

**A4. What are the purchasing models?**
**Answer:** **DTU-based** (bundled compute+storage units, simple) and **vCore-based** (independent CPU/memory scaling, with **Provisioned** or **Serverless** compute tiers).

**A5. What are the service tiers?**
**Answer:** **General Purpose** (budget, standard latency), **Business Critical** (in-memory, low latency, local SSD + readable replicas), and **Hyperscale** (massive scale, fast scaling, up to 100 TB).

**A6. What is a DTU vs a vCore?**
**Answer:** A **DTU** is a bundled measure of CPU/IO/memory (simplified, less control). A **vCore** is an actual CPU core with separate memory/IO configuration (more control, Azure Hybrid Benefit eligible).

**A7. What is the Serverless compute tier?**
**Answer:** vCore-based, **auto-scales compute** and **pauses** when idle (billing pauses) — for intermittent, unpredictable workloads; resumes automatically.

**A8. What is an elastic pool?**
**Answer:** A shared pool of resources for **many databases** with unpredictable usage — cost-effective multi-tenant SaaS (databases share DTUs/vCores).

**A9. How does Azure SQL provide high availability?**
**Answer:** Built-in **availability groups**-like replication: General Purpose uses remote storage + failover; Business Critical uses **Always On AG** with local replicas; automatic failover with ~99.99% SLA (higher for zone-redundant).

**A10. What are automated backups?**
**Answer:** Azure SQL automatically takes **full (weekly), differential (~12h), and transaction-log (~5–10 min) backups** retained 1–35 days — enabling point-in-time restore (PITR).

**A11. What is point-in-time restore (PITR)?**
**Answer:** Restoring a database to any point within the retention window by replaying backups/logs — the primary recovery tool for accidental data loss.

**A12. What is geo-replication?**
**Answer:** **Active geo-replication** maintains readable secondaries in other regions (async) for DR/read scale-out; **failover groups** automate DNS + failover for a set of databases.

**A13. What is the difference between failover groups and active geo-replication?**
**Answer:** **Active geo-replication** = per-database secondaries (manual/scripted failover). **Failover groups** = a managed abstraction over geo-replication with a **read-write/read-only listener** and coordinated failover across multiple DBs — simpler DR.

**A14. How do you secure Azure SQL?**
**Answer:** **Microsoft Entra ID authentication** (over SQL logins), **firewall rules** (server/database level), **private endpoints/VNet**, **Always Encrypted**, **Transparent Data Encryption (TDE)**, and **Advanced Threat Protection** (Defender for SQL).

**A15. What is TDE and is it on by default?**
**Answer:** Transparent Data Encryption encrypts data **at rest** (pages, backups, logs) automatically — **on by default** for new databases, using a service-managed or customer-managed key.

---

## Case B — Advanced (Senior)

**B1. Explain the HA architecture difference between General Purpose and Business Critical.**
**Answer:** **General Purpose**: primary writes to **remote Azure storage** (locally redundant or zone-redundant); failover to another node re-attaches storage (seconds). **Business Critical**: an **Always On availability group** with synchronous local SSD replicas (1 primary + secondaries) — sub-second failover, readable replicas, higher SLA and cost. Choose BC for low-latency/mission-critical; GP for general workloads.

**B2. How does Hyperscale differ architecturally, and when do you choose it?**
**Answer:** Hyperscale separates **compute from storage** with a distributed storage layer — enabling **instant scaling**, up to **100 TB**, fast backups (snapshot-based), and horizontal **read scale-out** replicas. Choose for very large databases, rapid scaling, or heavy read workloads where GP/BC size limits don't fit.

**B3. How does the Serverless tier work (auto-pause, auto-scale) and what are its caveats?**
**Answer:** Serverless auto-scales vCores within min/max and **auto-pauses** after inactivity (no compute billing while paused). Caveats: **resume latency** (seconds) on first connection (mitigate with a "keep-alive" or choose non-paused), not ideal for steady high-throughput (provisioned is cheaper), and some features (geo-replication config) differ. Great for dev/test/bursty workloads.

**B4. What is a failover group and how do you fail over (planned vs forced)?**
**Answer:** A failover group links a primary + secondary server/region with a **listener** (read-write + read-only endpoints). **Planned failover** (graceful) syncs and switches with no data loss; **forced failover** (disaster) switches immediately, accepting potential data loss (async lag). Apps connect via the listener, so failover requires no connection-string change.

**B5. How do you tune performance (indexing, Query Store, automatic tuning, Intelligent Insights)?**
**Answer:** Use **Query Store** to find regressions/top queries; **Automatic tuning** (force last-good plan, create/drop indexes) fixes plan regressions automatically; **Intelligent Insights** + **Query Performance Insight** show slow queries/waits; **index tuning** + **wait statistics** (sys.dm_os_wait_stats) guide manual fixes; monitor DTU/vCore + IO metrics.

**B6. What is Azure SQL's built-in connection handling, and why do you need retry logic (transient faults)?**
**Answer:** Azure SQL is a multi-tenant PaaS — it may briefly **reconfigure/failover**, causing **transient errors** (40613, 40197, connection drops). Apps must implement **retry with exponential backoff** (e.g., SqlClient's built-in retry or Polly) and be **idempotent**. This is a fundamental difference vs self-managed SQL Server.

**B7. How do you secure Azure SQL end-to-end (network, identity, data)?**
**Answer:** **Network**: private endpoint/VNet + firewall rules (no public), **deny public access**. **Identity**: Entra ID auth (managed identities for apps), least-privilege DB roles. **Data**: TDE (at rest), **Always Encrypted** (sensitive columns, even the DB can't read them), **Dynamic Data Masking** (partial masking for non-privileged users), TLS (in transit), and **Defender for SQL** (threat detection + vulnerability assessment).

**B8. What is Always Encrypted vs Dynamic Data Masking vs TDE (when each)?**
**Answer:** **TDE** = transparent at-rest encryption (whole DB — protects media theft, not from DBAs). **Always Encrypted** = client-side encryption of specific columns (the database never sees plaintext — protects from DBAs/cloud admins). **Dynamic Data Masking** = obfuscates query results for unauthorized users (UX protection, not strong crypto). Choose per threat model.

**B9. What is the difference between DTU and vCore models for cost/scale decisions?**
**Answer:** DTU = bundled, simpler, no Azure Hybrid Benefit (AHB) flexibility, good for small/unknown workloads. vCore = granular CPU/memory control, **AHB** (reuse on-prem SQL licenses for big savings), **Serverless** option, and **reserved capacity** discounts. Prefer vCore for enterprise/licensing-aware deployments; DTU for simplicity.

**B10. How does connection pooling and "connection limit" affect scale-out, and how do you architect for many clients?**
**Answer:** Azure SQL has connection/DTU limits per tier; too many open connections exhaust them. Use **connection pooling** (reuse), **retry logic**, and for massive multi-tenant scale use **elastic pools** or **Hyperscale** read replicas. Proxy redirect policy (default) + pool sizing tuned to the tier avoids throttling (error 10928/40501).

**B11. What is the role of read replicas / read scale-out in Azure SQL?**
**Answer:** **Business Critical** and **Hyperscale** provide built-in **readable replicas** (read-only routing via `ApplicationIntent=ReadOnly`) to offload reporting/read workloads from the primary. **Active geo-replication** secondaries also serve reads in other regions. This scales reads without scaling the primary's cost.

**B12. How do you do zero/near-zero downtime migrations to Azure SQL (DMS, online migrations)?**
**Answer:** **Azure Database Migration Service** (or SQL Data Sync) replicates on-prem → Azure SQL **continuously**; when in sync, cut over the app's connection string. For schema-heavy migrations, use the **Data Migration Assistant** for compatibility assessment, fix blockers, then migrate with minimal downtime. Test rollback paths.

---

## Case C — Scenario

**C1. Scenario:** A multi-tenant SaaS has 200 small databases with spiky, unpredictable usage.
**Question:** Which Azure SQL option?
**Answer:** **Elastic pools** — databases share a pool of DTUs/vCores, so spikes in one tenant are absorbed by the pool's headroom, and you pay one pool price instead of 200 individual tiers. This is the classic cost-optimal multi-tenant pattern.

**C2. Scenario:** Users report intermittent "connection timeout / error 40613" during a database failover.
**Question:** Explain and fix in the app.
**Answer:** Azure SQL performs automatic failover/reconfiguration causing **transient errors** (40613 = database unavailable during reconfiguration). Fix: implement **retry with exponential backoff** (and idempotency) in the client; use the SQL client's built-in retry policy or Polly. This is expected behavior — the app must tolerate brief reconnects.

**C3. Scenario:** A table of PII must be encrypted so that **even DBAs** can't see the plaintext, but the app reads/writes it normally.
**Question:** Which feature?
**Answer:** **Always Encrypted** — encrypt sensitive columns **client-side** (the app holds the key in a key store/Key Vault); the database stores only ciphertext, so DBAs (and the SQL service) never see plaintext. Queries on encrypted columns are limited (no range/wildcard search on encrypted text without deterministic encryption), so design carefully.

**C4. Scenario:** You need DR to another region with automatic failover and no connection-string changes for the app.
**Question:** Which feature?
**Answer:** **Failover groups** with **active geo-replication**: configure a secondary in the DR region, and the app connects via the **listener** endpoints. On a regional outage, trigger **forced failover** — the listener re-points to the secondary, so the app keeps working without config changes (accept async lag data loss).

**C5. Scenario:** A database grew to 60 TB and nightly jobs + scaling operations are painfully slow.
**Question:** Which tier solves this?
**Answer:** **Hyperscale** — it separates compute/storage, supports **up to 100 TB**, **instant scaling** (no data movement), **snapshot-based fast backups**, and **read replicas** for scale-out. Migrate to Hyperscale for very large DBs and rapid elasticity.

**C6. Scenario:** A security review found the SQL server's firewall open to `0.0.0.0/0` and SQL authentication enabled.
**Question:** Remediate.
**Answer:** (1) Remove the broad firewall rule and use **private endpoints/VNet** (set **deny public network access**), (2) switch to **Entra ID authentication** and disable SQL logins where possible (apps use **managed identities**), (3) enable **Defender for SQL** (vulnerability assessment + threat detection), (4) enforce **TDE** + TLS, and (5) alert on firewall/rule changes via Azure Policy + Activity Log.
