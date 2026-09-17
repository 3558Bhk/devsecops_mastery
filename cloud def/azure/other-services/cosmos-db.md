# Azure Cosmos DB — Interview Questions

> **Cloud:** Azure (Other Services) · **Category:** Databases · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~8 min

---

## JSON File Format

Cosmos DB stores **items as JSON documents** — schema-less, with system properties added by the engine. Account/container config is ARM JSON (`Microsoft.DocumentDB/databaseAccounts`).

```json
{
  "id": "order-1001",
  "userId": "user-123",
  "items": [ { "sku": "A-1", "qty": 2, "price": 9.99 } ],
  "total": 19.98,
  "status": "placed",
  "_rid": "AAAAAA==",
  "_etag": "0000abcd-0000-0000-0000-000000000000",
  "_ts": 1750000000
}
```

**Key fields:** `id` (unique **within a partition**) · the **partition key** property (e.g. `userId`) · system fields `_rid`/`_etag`/`_ts` · any JSON structure (arrays, nested objects). Indexing and throughput (RU/s) live in the container JSON.


## Case A — Basic

**A1. What is Azure Cosmos DB?**
**Answer:** A globally distributed, multi-model **NoSQL** database service with turnkey **global replication**, single-digit-millisecond latency, and elastic scale — supporting multiple APIs.

**A2. What are the data models/APIs?**
**Answer:** **NoSQL (document)**, **MongoDB API**, **Cassandra API**, **Gremlin (graph)**, **Table API**, and **PostgreSQL** (Citus) — one service, multiple models.

**A3. What are the core components (account, database, container)?**
**Answer:** **Account** (the resource, with regions), **database** (namespace), and **container** (the unit of scale, holding **items/rows**) with a **partition key**.

**A4. What is a partition key and why is it critical?**
**Answer:** The property used to **distribute data across physical partitions** — it determines scalability and query efficiency. Choosing a high-cardinality, evenly-distributed key is the most important design decision.

**A5. What is a Request Unit (RU)?**
**Answer:** Cosmos DB's currency for throughput — a normalized measure of the cost of a read/write/query. You provision **RU/s** (or use autoscale/serverless).

**A6. What are the throughput modes?**
**Answer:** **Provisioned** (set RU/s, manual or autoscale), **Serverless** (pay per operation, no provisioned RU), and **free tier**. Autoscale adjusts RU/s within a range.

**A7. What is global distribution?**
**Answer:** You can **add/remove regions** to a Cosmos account; data replicates to all regions with **multi-region writes** or single-write + read replicas.

**A8. What are the consistency levels?**
**Answer:** **Strong**, **Bounded staleness**, **Session** (default), **Consistent prefix**, and **Eventual** — a spectrum trading consistency vs latency/availability.

**A9. What is the difference between strong and eventual consistency?**
**Answer:** **Strong** = reads always see the latest write (highest latency, lower availability). **Eventual** = reads may lag (lowest latency, highest availability). Cosmos DB lets you pick per-request.

**A10. What is the change feed?**
**Answer:** A persistent, ordered log of **inserts/updates** in a container — used to build event-driven pipelines (Functions triggers, CDC).

**A11. What is TTL in Cosmos DB?**
**Answer:** Time-to-live — automatically expires/deletes items after N seconds (at container or item level).

**A12. What is a composite/secondary index?**
**Answer:** Cosmos DB **indexes all properties by default**; you can add **composite indexes** for multi-property ORDER BY/WHERE optimization.

**A13. What is the difference between Cosmos DB and Azure SQL?**
**Answer:** Cosmos DB = NoSQL, schema-flexible, globally distributed, RU-based, horizontal scale. Azure SQL = relational, SQL Server, ACID transactions, vertical/scale-out via tiers. Choose per data model/scale needs.

**A14. How is data encrypted?**
**Answer:** **Encrypted at rest** (always on) and **in transit** (TLS); optionally **customer-managed keys**.

**A15. What is a "document/JSON item"?**
**Answer:** The unit of data — a JSON document stored in a container, identified by an `id` + partition key.

---

## Case B — Advanced (Senior)

**B1. Explain partitioning in depth: logical vs physical partitions, hot partitions, and key design.**
**Answer:** Items are placed in **logical partitions** (by partition key value); logical partitions map to **physical partitions** (the actual storage/throughput units). A **hot partition** = one key value receiving disproportionate traffic, exhausting its RU/s even if the container has headroom. Design **high-cardinality, evenly-distributed** keys (e.g., user ID, not a fixed "type" value) to spread load.

**B2. What are the consistency levels in detail, and how do you choose (tradeoffs)?**
**Answer:** **Strong** (linearizable, ~2x latency, reads from primary), **Bounded staleness** (lag bounded by time/ops), **Session** (read-your-writes within a session — good default), **Consistent prefix** (no out-of-order reads), **Eventual** (cheapest/fastest). Choose Strong for correctness-critical; Session for most apps; Eventual for caches/analytics. You can **relax per-request** (override at the SDK level).

**B3. How does multi-region replication work (single vs multi-master) and how do you handle conflicts?**
**Answer:** Data replicates to all regions (~sub-second RPO). **Single-write** = one write region (no conflicts, simpler). **Multi-region writes** = write anywhere (lowest write latency) with **conflict resolution**: **last-writer-wins (LWW)** or a **custom merge procedure**. Choose multi-master only when writes must be local everywhere; else single-write + read replicas.

**B4. How do you model data in Cosmos DB (denormalization, embedding vs referencing)?**
**Answer:** Model around **queries**: **embed** related data in one document when read together (no joins, single read); **reference** when data is large/updated independently/shared. Denormalize aggressively; partition by the primary query pattern. This is the opposite of relational normalization.

**B5. How does RU provisioning work (autoscale vs manual vs serverless) and how do you right-size?**
**Answer:** **Manual** = fixed RU/s (predictable cost, risk of throttling). **Autoscale** = scales 10x within a max (absorbs bursts, cost varies). **Serverless** = pay-per-operation (spiky/unknown). Right-size: measure **RU consumption** per operation, estimate peak, set autoscale with a max ~1.5x peak, and monitor **429 throttling**.

**B6. What are the common causes of 429 (throttling) and how do you fix them?**
**Answer:** 429 = provisioned RU/s exceeded — from hot partitions, sudden bursts, or oversized queries. Fix: **autoscale**, **higher RU/s**, **better partition key** (spread load), **optimize queries** (indexes, cross-partition vs point reads), and **client retry with backoff** (SDK handles 429s). Monitor via Azure Monitor + the SDK diagnostics.

**B7. What is the change feed and how do you build event-driven pipelines with it?**
**Answer:** The change feed streams **insert/update events** in order per partition — consumed by **Azure Functions (Cosmos trigger)**, **Change Feed Processor**, or **Synapse Link**. Use for CDC, cache invalidation, materialized views, and cross-service sync. It's the backbone of serverless Cosmos pipelines.

**B8. What is Azure Synapse Link for Cosmos DB, and when do you use it?**
**Answer:** **Synapse Link** provides an **analytical store** (columnar) auto-synced from the transactional store — enabling **no-ETL analytics** (Spark/SQL) on live Cosmos data **without consuming provisioned RU/s**. Use for real-time analytics over operational data.

**B9. How do you implement transactions in Cosmos DB (stored procedures, transactional batch)?**
**Answer:** Cosmos DB gives **ACID transactions within a logical partition**: **transactional batch** (SDK) or **stored procedures** (server-side JS) operate atomically on items sharing a partition key. Cross-partition transactions aren't supported — design the partition key so related entities live together (single-partition writes).

**B10. How does Cosmos DB compare to DynamoDB, MongoDB, and SQL (positioning)?**
**Answer:** Cosmos DB vs **DynamoDB**: both global NoSQL; Cosmos offers **multiple APIs, tunable consistency (incl. strong), and RU/s autoscale/serverless**; DynamoDB has strong consistency option + on-demand. vs **MongoDB**: Cosmos's MongoDB API is managed/global with SLA. vs **SQL**: schema-less, horizontal scale, no joins. Choose by model/consistency/global needs.

**B11. What are the cost levers for Cosmos DB (RUs, storage, regions)?**
**Answer:** Costs = **provisioned RU/s** (or serverless ops) + **storage** + **extra regions**. Optimize: **autoscale** (pay for what you use), **right-size RUs**, use **serverless** for spiky, **indexing policy** (exclude unnecessary paths), **TTL** to expire data, **dedicated gateway** for read-heavy, and **fewer regions** (each region costs).

**B12. How do you secure Cosmos DB (network, identity, data)?**
**Answer:** **Private endpoints/VNet** (no public), **firewall rules**, **Entra ID (RBAC)** + resource tokens for fine-grained access, **master key rotation**, **encryption at rest (CMK optional)** + TLS, and **Defender for Cosmos DB** (threat detection). Grant least-privilege data-plane roles via Entra ID.

---

## Case C — Scenario

**C1. Scenario:** A globally used social app needs low-latency reads everywhere and writes near users.
**Question:** Design the Cosmos DB setup.
**Answer:** **Multi-region writes** (write anywhere = lowest local write latency) or single-write + read replicas (simpler). Use **Session consistency** (or bounded staleness) for low latency with read-your-writes. Choose a **partition key** (e.g., user ID) that distributes globally. Handle **conflicts** (LWW or custom) if multi-master. This is the canonical global-scale Cosmos pattern.

**C2. Scenario:** A container is throttling (429s) even though total RU/s looks fine.
**Question:** Diagnose.
**Answer:** Likely a **hot partition** — one partition key value (e.g., a popular user or a fixed key) consumes all its partition's RUs. Diagnose via **Azure Monitor partition metrics** (`NormalizedRUConsumption` per partition); fix by **changing the partition key** to a high-cardinality value (or adding a sharding suffix), or redistribute/archive hot data.

**C3. Scenario:** A query that filters on a non-partition-key field is slow and expensive.
**Question:** How do you optimize?
**Answer:** Cosmos queries are cheapest as **point reads** (partition key + id) or **in-partition queries**. For cross-partition filters: add the field to the **partition key** (or a **composite/secondary index** if only ORDER BY), **restructure the data model** around the query, or create a **materialized view** (change feed → another container). Review the **indexing policy** to avoid over-indexing.

**C4. Scenario:** An e-commerce cart must be strongly consistent (no lost/duplicate items).
**Question:** Which consistency and transaction design?
**Answer:** Use **Strong consistency** (or **Session** with read-your-writes per user) and keep the cart items **in one logical partition** (partition key = user ID) so updates use **transactional batches** (atomic multi-item writes). This guarantees the cart is consistent per user without cross-partition transactions.

**C5. Scenario:** You need real-time analytics on operational Cosmos data without impacting the app's RU/s.
**Question:** Which feature?
**Answer:** **Azure Synapse Link for Cosmos DB** — it maintains an **analytical store** (columnar) synced from the transactional store, so Spark/SQL analytics run **without consuming the app's RUs**. Enable analytical store on the container and query via Synapse/Power BI.

**C6. Scenario:** A CDC pipeline must react to every insert/update in a container (e.g., trigger order processing).
**Question:** Implement it.
**Answer:** Use the **change feed** with an **Azure Functions Cosmos DB trigger** (or Change Feed Processor): each insert/update invokes the function (partition-ordered), which processes the item idempotently. Use **leases** (the processor manages state) so the pipeline resumes after failures and scales across partitions.
