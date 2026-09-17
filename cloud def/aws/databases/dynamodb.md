# Amazon DynamoDB — Interview Questions

> **Cloud:** AWS · **Category:** Databases · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~9 min

---

## JSON File Format

DynamoDB uses JSON for **items** (documents) and for **table definitions** (`CreateTable`). Attribute values are typed with single-letter tags (S/N/B/M/L/SS/NS/BOOL).

```json
{
  "UserID": { "S": "u-123" },
  "OrderID": { "N": "1001" },
  "Total": { "N": "42.50" },
  "Tags": { "SS": ["new", "priority"] },
  "Metadata": { "M": { "region": { "S": "ap-south-1" } } }
}
```

**Key fields:** attribute type tags — `S` string · `N` number · `B` binary · `BOOL` · `M` map · `L` list · `SS/NS/BS` sets. Table JSON carries `KeySchema` (partition + optional sort key), `AttributeDefinitions`, `ProvisionedThroughput` (RCU/WCU) or `BillingMode: PAY_PER_REQUEST`.


## Case A — Basic

**A1. What is DynamoDB?**
**Answer:** A fully managed, serverless **NoSQL key-value and document database** that provides single-digit-millisecond latency at any scale, with automatic scaling, replication, and no servers to manage.

**A2. What are the core components of DynamoDB?**
**Answer:** **Tables**, **items** (rows), **attributes** (columns), a **partition key** (required), an optional **sort key**, and optional **secondary indexes**.

**A3. What is a partition key and a sort key?**
**Answer:** The **partition key** determines how data is distributed across partitions (used to find the right storage node). The **sort key** orders items with the same partition key, enabling range queries. Together they form the primary key (composite when both are used).

**A4. What is a secondary index?**
**Answer:** An alternate key structure for querying: **GSI** (global secondary index — different partition/sort key, own capacity, eventual or strong consistency options) and **LSI** (local secondary index — same partition key, different sort key, must be defined at table creation, shares table capacity).

**A5. What are the two capacity modes?**
**Answer:** **On-demand** (pay per request, auto-scales instantly, no capacity planning) and **Provisioned** (set RCU/WCU, cheaper for predictable workloads, supports auto-scaling and reserved capacity).

**A6. What are RCUs and WCUs?**
**Answer:** **Read Capacity Units** and **Write Capacity Units** — provisioned throughput units. 1 RCU = 1 strongly-consistent read (or 2 eventually-consistent reads) of up to 4 KB per second; 1 WCU = 1 write of up to 1 KB per second.

**A7. What is the difference between strong and eventual consistency reads?**
**Answer:** **Strongly consistent** reads return the latest write (consume more RCU). **Eventually consistent** reads may return stale data briefly (consume half RCU). DynamoDB also supports **transactions** for atomic multi-item reads/writes.

**A8. What is DynamoDB Streams?**
**Answer:** An ordered, time-sequenced log of item changes (24-hour retention) that can trigger Lambda or be read by Kinesis adapter — the basis for replication, audit, and event-driven pipelines.

**A9. What is TTL in DynamoDB?**
**Answer:** Time-to-Live: set an attribute with an epoch timestamp; DynamoDB automatically deletes expired items (within ~48 hours, no cost) — great for sessions, caches, and logs.

**A10. What are DynamoDB Accelerator (DAX) and when to use it?**
**Answer:** DAX is an in-memory cache cluster in front of DynamoDB delivering **microsecond** read latency. Use it for read-heavy, latency-critical workloads; it doesn't help write-heavy or cost-sensitive workloads.

**A11. What is DynamoDB's consistency/availability model (CAP)?**
**Answer:** DynamoDB is an AP-style (available + partition-tolerant) eventually-consistent-by-default system with optional strong consistency and transactions — choose per-read consistency based on your needs.

**A12. What are the main operations/APIs?**
**Answer:** **PutItem, GetItem, UpdateItem, DeleteItem, Query** (by partition key, with sort-key conditions), **Scan** (full table, inefficient), **BatchGetItem/BatchWriteItem**, and **TransactWriteItems/TransactGetItems**.

**A13. What is a Scan and why is it discouraged?**
**Answer:** Scan reads every item in the table (or index), consuming lots of capacity. It's inefficient and expensive — prefer Query with keys, use parallel scans sparingly, or export to S3 for analytics.

**A14. Is DynamoDB schema-less?**
**Answer:** Yes for attributes — each item can have different attributes. But you must define the **primary key** (and LSIs) upfront; you cannot change the primary key later (create a new table/migrate).

**A15. What is DynamoDB's pricing based on?**
**Answer:** Capacity (RCU/WCU or on-demand requests), storage (per GB), and features (DAX, streams, global tables replication, backups/PITR, reserved capacity). No fixed server cost.

---

## Case B — Advanced (Senior)

**B1. Explain DynamoDB's partitioning and why key design determines performance.**
**Answer:** DynamoDB hashes the partition key to assign items to partitions (physical storage units). Each partition can serve ~3,000 RCU / 1,000 WCU. If a single partition key is extremely "hot" (huge traffic to one key), that partition throttles even if the table has capacity — this is the **hot partition** problem, solved by high-cardinality keys and good distribution.

**B2. What is a hot partition, and how do you avoid it?**
**Answer:** A hot partition receives disproportionate traffic (e.g., a popular product ID, or a timestamp-based key during peak writes). Avoid by choosing high-cardinality partition keys, adding randomness/salting or sharding suffixes for write-heavy keys, and designing queries to spread load. Monitor via CloudWatch and Contributor Insights.

**B3. When do you use a GSI vs an LSI, and what are their tradeoffs?**
**Answer:** GSI: different partition **and** sort key, can be added anytime, has **independent** capacity, and is eventually consistent by default. LSI: same partition key, **different sort key**, must be created **with the table**, shares table capacity, supports strong consistency. Use LSI for alternate sort orders within the same partition; GSI for entirely different access patterns.

**B4. Explain DynamoDB transactions and their limits.**
**Answer:** **TransactWriteItems/TransactGetItems** give ACID (atomic, serializable) operations across up to 100 items (or 4 MB). Two-phase commit with idempotency tokens. Use for money movements, order+inventory updates, etc. They consume 2x normal capacity per operation.

**B5. How does DynamoDB Streams + Lambda enable event-driven architectures and cross-region replication?**
**Answer:** Streams emit ordered change records (24h retention). Lambda consumes them for real-time reactions (indexing, notifications, CDC pipelines). **Global Tables** use streams under the hood to replicate items across regions. Use Kinesis Data Streams for >24h retention or fan-out to multiple consumers.

**B6. What are Global Tables and how do conflict resolution and RPO/RTO work?**
**Answer:** Global Tables replicate a table across multiple regions with **last-writer-wins** conflict resolution and typically **sub-second** replication lag. They give multi-region active-active with low RPO/RTO. Requirements: versioning/streams enabled, no LSI (GSIs allowed), and IAM role for replication.

**B7. How do you model relational-style data (one-to-many, many-to-many) in DynamoDB?**
**Answer:** Use a **single-table design**: composite keys where partition key = parent entity and sort key = child entity (e.g., `PK=USER#123, SK=ORDER#456`), plus GSIs to invert access patterns (get all orders by status, etc.). Denormalize aggressively; design keys around **access patterns first** (this is the core DynamoDB skill).

**B8. Explain the single-table design pattern and its benefits/costs.**
**Answer:** Store multiple entity types in one table using generic PK/SK (e.g., `USER#`, `ORDER#`, `ORDER#...#ITEM#`) and GSIs to support different queries. Benefits: fewer tables to manage, consistent scaling, one place for related data (no joins needed). Costs: harder to reason about, needs strong naming conventions and tooling, and can complicate access control.

**B9. How do you handle pagination, limits, and efficiently returning large result sets?**
**Answer:** Use **Query** with KeyConditionExpression, set a **Limit**, and page using **LastEvaluatedKey** (returned when results exceed 1 MB or limit). Avoid Scan; if Scan is unavoidable, use parallel scans with segments and only fetch projected attributes.

**B10. What is the 400 KB item size limit, and how do you handle larger data?**
**Answer:** An item (with attribute names) can be up to **400 KB**. For larger payloads, store the blob in **S3** and keep the S3 key + metadata in DynamoDB (the "S3 pointer" pattern), or compress/chunk the data.

**B11. How does capacity auto-scaling work, and why might you still throttle?**
**Answer:** Auto-scaling adjusts provisioned RCU/WCU based on utilization (target %), but it reacts over minutes and has a max cap you set. Sudden bursts, hot partitions, or exceeding the max can still cause **ProvisionedThroughputExceededException** (throttling). Mitigate with on-demand mode, good key design, exponential backoff, and DAX/caching.

**B12. Compare DynamoDB vs RDS/Aurora vs ElastiCache for a given workload.**
**Answer:** DynamoDB = serverless NoSQL, predictable ms latency at any scale, key-value/document, great for high-traffic web/mobile/session/shopping-cart. RDS/Aurora = relational SQL with joins/transactions/analytics. ElastiCache = in-memory cache (Redis/Memcached) for microsecond access to hot data. They compose: cache in front, DynamoDB/RDS as source of truth.

---

## Case C — Scenario

**C1. Scenario:** A social app's feed query scans the whole table and costs are exploding.
**Question:** Redesign the data model.
**Expected answer:** Model around access patterns: partition key = `USER#id`, sort key = `POST#timestamp` (descending) so "get my recent posts" is a single efficient **Query**. Add a GSI `GSI1PK = FOLLOWED_USER#id` / `SK = timestamp` to fan out posts to followers' feeds. No more Scans; use Limit + pagination.

**C2. Scenario:** A shopping-cart service: users add items frequently; carts must always be fast and never lost during peak holiday traffic.
**Question:** Choose capacity mode and key design.
**Expected answer:** Use **on-demand** mode (or provisioned with auto-scaling + high max) to absorb spikes, partition key = `USER#id` with item per product (or a cart item collection). Enable **PITR** for accidental-delete recovery, TTL for abandoned carts, and possibly DAX if reads dominate. Monitor throttling with CloudWatch alarms.

**C3. Scenario:** You need your DynamoDB table available in 3 regions with sub-second cross-region sync and automatic conflict handling.
**Question:** What feature do you use and what are the prerequisites?
**Expected answer:** **Global Tables**: enable DynamoDB Streams (new-and-old-images), create the table in 3 regions, add replicas via the console/CLI. Conflicts resolve by **last-writer-wins**. Prerequisites: no LSIs, versioning on, IAM role for replication. Verify sub-second RPO and test regional failover.

**C4. Scenario:** Order processing must decrement inventory and insert an order atomically — never allow negative stock.
**Question:** How do you guarantee this in DynamoDB?
**Expected answer:** Use **TransactWriteItems** with a **ConditionExpression** (`#stock > :qty`) on the inventory UpdateItem and the PutItem for the order in the same transaction — it's atomic and all-or-nothing. Handle `TransactionCanceledException` with retry (client-side) when the condition fails.

**C5. Scenario:** A table throttles at peak even though total provisioned capacity looks adequate.
**Question:** Diagnose and fix.
**Expected answer:** Likely a **hot partition** (one key receiving most traffic) — the table-level capacity is fine but that partition's ~3,000 RCU/1,000 WCU limit is hit. Diagnose with Contributor Insights/CloudWatch. Fix: redesign the partition key for higher cardinality, salt/shard the hot key, add DAX for reads, or move to on-demand. Also verify auto-scaling's max cap isn't too low.

**C6. Scenario:** You're migrating a MySQL table with joins to DynamoDB for scale, but the team keeps writing relational-style queries.
**Question:** How do you lead the migration/redesign?
**Expected answer:** First **enumerate all access patterns** (the queries the app actually runs). Design a single-table (or few-table) model with composite keys + GSIs to serve each pattern with a single Query — denormalize and duplicate data rather than join. Rewrite the data layer accordingly, migrate with DMS (to DynamoDB) or custom scripts, and load-test each access pattern. Educate the team that DynamoDB optimizes for predictable, per-pattern queries, not ad-hoc SQL.
