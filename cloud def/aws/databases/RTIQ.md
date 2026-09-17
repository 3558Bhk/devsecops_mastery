# RTIQ — AWS Databases (Real-Time Interview Questions)

> **Cloud:** AWS · **Domain:** Databases (DynamoDB, MySQL/RDS) · **Target roles:** SDE-3 · Cloud Engineer · DevOps · DevSecOps · SRE · Platform Engineer · **Reading time:** ~9 min

**How this file is used live:** database rounds for senior roles are almost always *design + incident*, not trivia. Expect "design a schema for X", then "now it's slow/throttling, debug it". Interviewers are testing whether you can reason from access patterns, and whether you understand the difference between what the DB does for you and what your application must handle.

**Legend:** ⚡ Rapid · 🔍 Deep dive + follow-ups · 🚨 War room (production incident) · ⚖️ Trade-off debate · 🎯 Senior signal

---

## 1. DynamoDB — `dynamodb.md`

**⚡ Rapid**
1. **Q:** How do you choose a partition key?
**A.** From the query pattern, not the entity. High cardinality, even access distribution, and never a monotonically increasing value (date/timestamp/sequence ⇒ hot partition). Composite keys (`PK` + `SK`) let one table answer multiple access patterns.
2. **Q:** Query vs Scan — why is Scan the wrong answer?
**A.** Query seeks directly by key = cost proportional to items returned. Scan reads the whole table and filters after, consuming RCUs for everything read. At scale it's both slow and expensive; if you "need" a Scan, your key design is wrong.
3. **Q:** On-demand vs provisioned + autoscaling?
**A.** On-demand for spiky/unknown or dev workloads; provisioned for predictable, steady, high volume where you want cost control. On-demand costs more per request but scales instantly; provisioned needs capacity planning and reacts in minutes.
4. **Q:** What does one RCU/WCU buy you?
**A.** 1 RCU = 1 strongly consistent read/s of ≤4 KB (2 for eventually consistent); 1 WCU = 1 write/s of ≤1 KB. Items are rounded up to the next unit — a 4.1 KB read costs 2 RCUs, which is where surprise bills come from.

**🔍 Deep dive**
5. **Q:** GSI vs LSI — pick one and defend it.
**A.** GSI: new partition + sort key, its own capacity, can be added/removed anytime, eventually consistent only. LSI: same partition key, different sort key, strongly consistent option, but must exist at table creation and shares capacity. Default to GSI; use LSI only when you need strong consistency on an alternate sort order.
**↳ Follow-up:** "Why is a GSI write potentially 2× the cost?"
**A.** A write that changes indexed attributes writes to the base table *and* every affected index — and GSIs consume their own capacity (or in on-demand, add to your bill).
6. **Q:** How do you handle a hot partition in production?
**A.** First confirm with CloudWatch `ConsumedWriteCapacity` per partition (Contributor Insights / CloudWatch metrics), then fix the key: add a shard suffix / random bucket to spread writes, or use a different attribute. Adaptive capacity and on-demand help but do not fix a single-key hotspot.
7. **Q:** When do you use DynamoDB Streams, TTL, and transactions?
**A.** Streams: change data capture → Lambda for projections, search indexing, audit, or replication. TTL: cheap expiry of sessions/carts (deletes are free-ish and async — don't use it as an SLA). Transactions: `TransactWriteItems` when multiple items must be atomic (≤100 items, 2× cost).
8. **Q:** What breaks at scale that works fine in dev?
**A.** Hot partitions (single-tenant skew), bursty throttling against provisioned capacity, 400 KB item limit, 1 MB per Query page requiring pagination, sparse GSI behaviour, and eventually consistent reads on GSIs. Also connection/proxy limits from Lambda concurrency.

**🚨 War room**
9. **Q:** `ProvisionedThroughputExceededException` on a table that was fine last week. Next steps?
**A.** Check which key is hot, whether it's a GSI (often the real culprit), whether traffic grew or a bad client retry storm amplifies it, and whether capacity is provisioned on the *index*. Mitigate: temporarily raise capacity / switch to on-demand, add jittered exponential backoff on the client, then fix the access pattern.
10. **Q:** A Scan-heavy nightly report is consuming all capacity and slowing production. Fix both now and long-term?
**A.** Now: move it to a GSI or a replica read, limit pages, add backoff, or run it against an export. Long-term: DynamoDB export to S3 + Athena, or a materialised aggregate written by Streams — never query the OLTP table for analytics.
11. **Q:** A single-tenant customer's writes are being throttled while everyone else is fine. Why?
**A.** Partition-key skew: one tenant = one key = one partition's worth of throughput (historically ~1,000 WCU / 3,000 RCU per physical partition). Fix with write sharding (tenant + shard suffix) and scatter-gather reads, or isolate large tenants.

**⚖️ Trade-off**
12. **Q:** DynamoDB or Aurora/RDS for a new service?
**A.** Access patterns known and key-value/document shaped, needs single-digit-ms at any scale, no complex joins → DynamoDB. Ad-hoc queries, joins, reporting, mature SQL tooling, transactions across many rows → relational. If you can't name the queries, SQL is the safer bet.
13. **Q:** Single-table design — always?
**A.** No. It's powerful when access patterns are stable and latency matters; it costs maintainability and onboarding clarity. Use it for high-scale hot paths, separate tables per bounded context otherwise.
14. **Q:** Where does DAX actually help?
**A.** Read-heavy, hot-key, eventually-consistent-tolerant workloads where you want microsecond reads and to offload RCUs. It doesn't help write-heavy or strongly consistent reads, and it's another cluster to run — so justify it with numbers.

**🎯 Senior**
15. **Q:** Tell me about a time you fixed a data-layer scaling problem.
**A.** Name the symptom (p99 latency, throttles), how you found the partition/key, the interim mitigation, the model redesign (new key + backfill + dual write), and the guardrail you now have (capacity alarms, load tests, per-tenant dashboards).

**🎯 Senior signal:** "we just switched to on-demand" as a *first* answer to throttling marks you mid-level. Senior answers diagnose the key/hot partition and separate architecture from capacity.

---

## 2. MySQL on RDS — `mysql.md`

**⚡ Rapid**
1. **Q:** Multi-AZ vs read replica — do they solve the same problem?
**A.** No. Multi-AZ is HA: synchronous standby, automatic failover in ~60–120 s, same endpoint. Read replicas are scale: asynchronous copies for read traffic/analytics, and they can be promoted (with lag loss). One is availability, the other is throughput.
2. **Q:** Where do slow queries show up and how do you catch them?
**A.** Performance Insights + `slow_query_log` + `performance_schema`. Enable slow query log with `long_query_time` and `log_queries_not_using_indexes`, then `EXPLAIN` the top offenders.
3. **Q:** How do you patch and upgrade MySQL without a maintenance-window outage?
**A.** Blue/Green Deployments or a replica-based rollout: build a green environment on the target version, replicate, test, switch the endpoint with fast rollback available. Never upgrade the only instance in place in production.
4. **Q:** What is RDS Proxy for?
**A.** Connection pooling and multiplexing — essential with Lambda/serverless spikes that would otherwise exhaust `max_connections`, plus faster failover by holding client connections.

**🔍 Deep dive**
5. **Q:** Your app sees "Too many connections" during traffic spikes. Walk me through the fix ladder.
**A.** (1) Confirm `DatabaseConnections` vs `max_connections` (RDS caps by instance class and memory). (2) Fix the app: connection pool sizing, no pool-per-request, close leaks. (3) Add RDS Proxy for serverless/fan-out workloads. (4) Only then scale the instance class. The class is the last resort, not the first.
6. **Q:** How do you scale reads and stay consistent?
**A.** Read replicas with app-level read/write splitting and "read-your-writes" routing (send reads to primary briefly after a write, or use the session/transaction pin). Measure replica lag (`ReplicaLag`); if lag spikes, the write volume or a long transaction is the problem.
**↳ Follow-up:** "Lag is 600 s and climbing — what now?"
**A.** Look for a long-running write/DDL, a large batch, an undersized replica, or single-threaded replication replay. Kill/queue the offending job, reschedule heavy writes off-peak, and consider a bigger replica class; if the replica is unusable, remove it from the read pool — don't let it serve stale data to users.
7. **Q:** How do you migrate a 2 TB MySQL database with minutes of downtime?
**A.** Logical: snapshot/restore + ongoing replication (DMS or native) until caught up → brief write freeze → cut over DNS/endpoint → validate → keep the old primary as rollback. Rehearse it in staging and time the freeze; that freeze number is the actual SLA.
8. **Q:** How do you design backups and prove restorability?
**A.** Automated backups with PITR to a target retention, plus periodic snapshots copied cross-region for DR. Proof = scheduled restore drills into an isolated account/VPC and a documented RTO/RPO that matches what the business signed up for.

**🚨 War room**
9. **Q:** CPU on the primary is 100%, users report timeouts. First five commands/actions?
**A.** Check Performance Insights top SQL by DB load → `SHOW FULL PROCESSLIST` for stuck/locking queries → look for missing index (EXPLAIN), lock waits (`Innodb_row_lock_waits`), or a runaway batch. Kill the worst offender, then index/fix it. Also check whether a failover or replica promotion would be safer than waiting.
10. **Q:** A failover happened overnight and the app is still erroring an hour later.
**A.** Common causes: the app cached the old IP/DNS TTL, connection pool holding dead sockets, or the standby is smaller and can't take the load. Fix: short DNS TTL + reconnect-on-error in the pool, RDS Proxy, and identical instance classes between primary and standby.
11. **Q:** Disk is at 95% and autoscaling storage won't help for hours. What do you do?
**A.** Immediate: find and clean binaries/logs (`CALL mysql.rds_...` helpers, disable verbose general logs), delete/park old data or move it to S3/archive table, and confirm `StorageAutoscaling` is actually enabled with a sane maximum. Never let it hit 100% — MySQL with a full disk is effectively down.
12. **Q:** Deletes are getting slower every month on a hot table. Why?
**A.** InnoDB deletes mark rows and index entries; heavy delete churn leaves fragmented space and bloats indexes. Fix: partition by time and `DROP PARTITION` instead of `DELETE`, or archive + rebuild the table (optimise online with gh-ost/pt-osc).

**⚖️ Trade-off**
13. **Q:** Aurora vs RDS MySQL?
**A.** Aurora: faster failover, storage auto-grows, replicas share storage with low lag, better read scaling — but costs more, has its own quirks (failover is endpoint-based, I/O charges), and some MySQL features lag. RDS MySQL for cost/predictability or feature parity; Aurora when read scale and fast failover matter.
14. **Q:** gp2 → gp3 — trivial or significant?
**A.** Significant and free: gp3 decouples IOPS/throughput from size, so you often get better latency for less money. For a big fleet it's a real cost win; just validate IOPS headroom before switching.

**🎯 Senior**
15. **Q:** What database guardrails do you put in a platform so teams don't create 3 a.m. pages?
**A.** Instance sizing standards, Performance Insights on by default, CloudWatch alarms on CPU/free storage/replica lag/connections, mandatory PITR + cross-region snapshot copy, connection-pool templates, schema-migration review, and a documented restore drill that's actually run quarterly.

**🎯 Senior signal:** the panel is checking whether you reach for *the smallest correct fix first*. "Scale up the instance" as an answer to connection exhaustion tells them you've never run a real RDS fleet.
