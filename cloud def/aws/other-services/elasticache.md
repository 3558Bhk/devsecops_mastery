# Amazon ElastiCache — Interview Questions

> **Cloud:** AWS (Other Services) · **Category:** Database / Caching · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~8 min

---

## JSON File Format

ElastiCache clusters are declared in JSON via CloudFormation (`AWS::ElastiCache::CacheCluster`, `::ReplicationGroup`).

```json
{
  "Type": "AWS::ElastiCache::CacheCluster",
  "Properties": {
    "Engine": "redis",
    "CacheNodeType": "cache.r6g.large",
    "NumCacheNodes": 1,
    "VpcSecurityGroupIds": ["sg-0abc123"],
    "CacheSubnetGroupName": "cache-subnets"
  }
}
```

**Key fields:** `Engine` (redis / memcached) · `CacheNodeType` · `NumCacheNodes` · `CacheSubnetGroupName` (subnets across AZs) · `VpcSecurityGroupIds`. Redis **cluster mode** uses `AWS::ElastiCache::ReplicationGroup` with `NumNodeGroups` (shards) + `ReplicasPerNodeGroup`.


## Case A — Basic

**A1. What is Amazon ElastiCache?**
**Answer:** A managed **in-memory caching** service supporting **Redis** and **Memcached** — used to speed up applications by caching frequently accessed data with microsecond latency.

**A2. What are the two engines and when do you choose each?**
**Answer:** **Redis** = rich data structures (strings, hashes, lists, sets, sorted sets), persistence, replication, pub/sub — for most needs. **Memcached** = simple key-value, multi-threaded, horizontal scale — for simple caching with many nodes.

**A3. What is a cache hit vs cache miss?**
**Answer:** A **hit** serves data from the cache (fast); a **miss** means the data isn't cached, so the app fetches from the database and (optionally) populates the cache.

**A4. What is a common ElastiCache use case?**
**Answer:** Caching database query results and **session state** (user sessions) to reduce DB load and latency for read-heavy web apps.

**A5. How does ElastiCache provide high availability?**
**Answer:** Redis: **Multi-AZ with automatic failover** (primary + replicas across AZs). Memcached: horizontal scaling across nodes (no replication — data is lost if a node fails).

**A6. What is a node and a cluster?**
**Answer:** A **node** is a unit of cache compute/memory. A **cluster** is a group of nodes (one or more) acting as one cache.

**A7. What is a Redis replica?**
**Answer:** A read-only copy of the primary node — used for read scaling and failover (promoted on primary failure with Multi-AZ).

**A8. What is a subnet group?**
**Answer:** The subnets where ElastiCache nodes are placed (across AZs for Multi-AZ).

**A9. What is the difference between ElastiCache and DynamoDB/DAX?**
**Answer:** ElastiCache = general in-memory cache (Redis/Memcached) for any data. **DAX** = a purpose-built cache **specifically for DynamoDB** (microsecond reads, transparent to the app).

**A10. How do you connect to ElastiCache?**
**Answer:** Via the cluster's **endpoint** (primary/replica endpoints or a configuration endpoint for Memcached), over private VPC networking (no public access by default).

**A11. What is the pricing model?**
**Answer:** Per node-hour (by instance type/size) + data transfer — no per-request cost.

**A12. What is cache eviction?**
**Answer:** When the cache is full, Redis/Memcached evict least-recently-used (or policy-defined) keys to make room — requiring the app to handle misses gracefully.

**A13. What is TTL in caching?**
**Answer:** Setting an expiry (seconds) on cached keys so stale data is automatically removed — balancing freshness vs hit rate.

**A14. What is lazy loading vs write-through caching?**
**Answer:** **Lazy loading** = cache on miss (data cached when first read; stale until TTL). **Write-through** = write to cache and DB together (cache always fresh, but writes are slower). Many apps combine both.

**A15. How do you secure ElastiCache?**
**Answer:** VPC-only (private subnets + security groups), **encryption at rest (KMS)** and **in-transit (TLS)**, Redis **AUTH token**, and IAM for management APIs.

---

## Case B — Advanced (Senior)

**B1. Explain cache strategies: lazy loading, write-through, write-behind, and their tradeoffs.**
**Answer:** **Lazy loading**: read-miss populates cache (simple, resilient to cache loss, but stale + cache-miss latency). **Write-through**: update cache + DB on write (always fresh, but write latency and unused data). **Write-behind**: write to cache, async flush to DB (fastest writes, risk of data loss). Most production systems use lazy loading with TTLs, plus write-through for critical hot data.

**B2. What is the cache stampede (thundering herd) problem and how do you prevent it?**
**Answer:** When a hot key expires, many requests simultaneously miss and hit the DB at once. Prevent with **lock/refresh-on-miss** (single process recomputes), **early refresh** (recompute before expiry), or **jittered TTLs**. Redis can use a distributed lock (e.g., Redlock) or SET NX.

**B3. How does Redis Multi-AZ failover work, and what happens to data on failover?**
**Answer:** A primary replicates asynchronously to replicas in other AZs. On primary failure, ElastiCache promotes a replica (automatic failover, DNS endpoint stays the same). Because replication is **asynchronous**, a small window of writes can be lost on failover. Mitigate with client-side retries and app-level reconciliation.

**B4. When do you choose Redis vs Memcached in detail?**
**Answer:** Redis: persistence (snapshots/AOF), replication + failover, rich data types, pub/sub, Lua scripting, geospatial, TTLs, AUTH — for most workloads. Memcached: pure key-value, multi-threaded (uses multiple cores on one node), simple horizontal scale — when you need maximum simplicity/throughput and can tolerate node loss. If you need HA/data structures, pick Redis.

**B5. How do you design for cache failures (cache-aside resilience, circuit breakers)?**
**Answer:** Treat the cache as **best-effort**: on cache failure, fall back to the DB (with **circuit breaker** to avoid hammering a failing cache), use timeouts, and ensure the DB can absorb the load (or degrade gracefully). Never make cache availability a hard dependency for correctness.

**B6. What is Redis persistence (RDB vs AOF) in ElastiCache and its role?**
**Answer:** ElastiCache Redis supports **snapshots (RDB)** for backup/restore and replication; **AOF** (append-only file) for durability is supported in some configurations. Persistence enables backup/restore and seeding replicas, but Redis is primarily a cache — data is expected to be recreatable from the source of truth.

**B7. How do you scale ElastiCache Redis (scale up, scale out with sharding)?**
**Answer:** **Scale up**: change node type (vertical). **Scale out**: use **Redis Cluster Mode enabled** with **shards** — data is partitioned across shards (each with its own primary + replicas) for higher capacity. Online scaling adds shards and rebalances; non-clustered mode is limited to one primary + read replicas.

**B8. What is the difference between cluster mode enabled vs disabled (Redis)?**
**Answer:** **Disabled**: one primary + up to 5 read replicas (single shard) — simpler, read scaling only. **Enabled**: multiple shards (partitioned data), each shard with replicas — write + read scaling, up to hundreds of shards. Choose enabled for large datasets/high write throughput.

**B9. How do you implement session management with ElastiCache and make it resilient?**
**Answer:** Store sessions in Redis (key = session ID, TTL = session timeout) with **Multi-AZ** for HA. Apps read/write session data instead of local memory — enabling stateless, horizontally-scalable web tiers. On cache failure, sessions are lost (users re-login) unless you persist sessions to a DB as a fallback (or accept the tradeoff).

**B10. How do you monitor ElastiCache (metrics and what they tell you)?**
**Answer:** CloudWatch metrics: **CPUUtilization**, **SwapUsage** (high swap = memory pressure — bad for Redis), **Evictions** (cache too small), **CacheHits/CacheMisses** (hit ratio), **CurrConnections**, **ReplicationLag**, **DatabaseMemoryUsagePercentage**. Alarm on swap, evictions, replication lag, and hit-ratio drops.

**B11. What is ElastiCache Global Datastore and when do you use it?**
**Answer:** For Redis, a **Global Datastore** replicates a cluster across **two regions** (primary + secondary) for cross-region DR and low-latency local reads — failover by promoting the secondary. Use it for multi-region active-passive caching and disaster recovery.

**B12. How do you choose cache size and node type (capacity planning)?**
**Answer:** Estimate the **working set** (hot data size) + headroom (aim <80% memory, <75% CPU), account for eviction policy behavior, measure **hit ratio** (target ~90%+), and use **Redis-specific instance families** (e.g., r6g/m6g memory-optimized). Monitor evictions/swap and right-size iteratively; enable cluster mode for scale.

---

## Case C — Scenario

**C1. Scenario:** Your DB is overloaded by a read-heavy product-catalog query; response time is 500 ms+.
**Question:** Design a caching layer.
**Expected answer:** Add **ElastiCache Redis** in front of the DB: cache catalog items by key (`product:{id}`) with a TTL, use **lazy loading** (fetch DB on miss, populate cache), and route reads to cache first. Use Redis read replicas if needed, and monitor **hit ratio** (target high) and **evictions**. Fall back to the DB if the cache is down.

**C2. Scenario:** After a popular item's cache key expired, the database was flooded with thousands of simultaneous queries.
**Question:** What happened and how do you fix it?
**Expected answer:** **Cache stampede/thundering herd**. Fix: implement **request coalescing** (first request recomputes while others wait — Redis SET NX lock), **early/background refresh** before expiry, or **jittered TTLs** so keys don't expire simultaneously. Add a lock so only one request hits the DB.

**C3. Scenario:** A Redis cache ran out of memory and started evicting — but it evicted important session data causing users to be logged out.
**Question:** Diagnose and fix.
**Expected answer:** The cache was too small (or had no TTLs) and the **eviction policy** removed live data. Fix: right-size the cluster (add memory/sharding), set **TTLs** on cacheable data, use a **separate Redis for sessions vs data** (isolate eviction domains), and monitor **Evictions** + **DatabaseMemoryUsagePercentage**. Choose an eviction policy (`volatile-lru`/`allkeys-lru`) appropriate to the data.

**C4. Scenario:** You need session state shared across 50 web servers with high availability (survive a node failure).
**Question:** Which engine/config?
**Answer:** **Redis with Multi-AZ + automatic failover** (primary + replicas across AZs). Sessions are stored centrally, so any web server can serve any user. On primary failure, a replica is promoted automatically (small async-loss window — acceptable for sessions). Optionally enable **persistence** (snapshots) for faster recovery.

**C5. Scenario:** An app requires sub-millisecond reads from DynamoDB and must not change its DynamoDB API calls.
**Question:** Which service, and why not Redis?
**Answer:** **DynamoDB Accelerator (DAX)** — an in-memory cache that transparently sits in front of DynamoDB, giving microsecond reads with **no application changes** (same DynamoDB API). ElastiCache Redis would require the app to be rewritten to check the cache first, and you'd manage cache invalidation yourself.

**C6. Scenario:** A global app needs its Redis cache in two regions with failover capability for DR.
**Question:** Design it.
**Answer:** Use **ElastiCache Global Datastore** (Redis): a primary cluster in Region A replicated to a secondary cluster in Region B. On Region A failure, **promote** the secondary and repoint the app. Note it's asynchronous replication (small RPO); keep app logic able to repopulate cache from the source DB after failover.
