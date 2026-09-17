# 03 · System Design (HLD)

The round that decides SDE III. Not because the designs are hard, but because **structure, quantification and trade-off narration** are being scored continuously.

---

## 🟢 Basic — the vocabulary you must own

### 1. The scaling ladder (know what each step buys and costs)
| Step | Buys | Costs |
|---|---|---|
| **Vertical scaling** | Simplest; no code change; more cache/RAM per process | Ceiling; single point of failure; cost grows superlinearly; requires restart |
| **Horizontal + LB** | Near-unlimited capacity; fault tolerance | Needs statelessness; session affinity problems; more moving parts |
| **Caching** | 10–100× read throughput, lower latency | Invalidation, staleness, memory cost, thundering herd on miss |
| **Async / queues** | Decoupling, peak shaving, failure isolation, retry | Eventual consistency, ordering, duplicate delivery, harder debugging |
| **Database read replicas** | Read scale-out | Replication lag → stale reads; write still single-primary |
| **Sharding / partitioning** | Write scale-out, storage scale-out | Cross-shard queries/transactions, rebalancing, hot shards |
| **CDN / edge** | Latency + origin offload for static & cacheable | Cache invalidation, cost, less control |
| **Polyglot storage** | Right store per access pattern | Multiple systems to operate, sync/consistency problems |

**Senior framing:** "I scale the *bottleneck*, not the system. Adding a cache to a write-bound workload or sharding a read-bound one is expensive and useless. So I find the constraint first."

### 2. CAP and PACELC — say it precisely
**CAP**: in a **network partition (P)**, a distributed system must choose **consistency (C)** or **availability (A)**. P is not optional in a real distributed system — so the choice is C vs A *during a partition*.

Common misuse to avoid: "CAP says pick 2 of 3." Wrong. Say: "Absent a partition you can have both C and A; CAP only bites during a partition."

**PACELC** is the more useful model: **if Partitioned → A or C; Else → Latency or Consistency.** So DynamoDB/Cassandra are PA/EL (available in partition, low-latency normally, tunable consistency), while a strongly consistent datastore is PC/EC.

| System | Behaviour in partition |
|---|---|
| **ZooKeeper, etcd** | CP — majority (quorum) required; loses availability if quorum is lost |
| **Cassandra, DynamoDB** | AP — keeps serving, resolves conflicts (LWW, vector clocks, CRDTs) |
| **Postgres single primary** | Neither cleanly — primary unavailable = unavailable (unless you fail over, then you trade C) |
| **Spanner/CockroachDB** | CP with external/Paxos-backed consistency; PA within a region |

**Why it matters practically:** choose CP for correctness-critical coordination (locks, leader election, config, balances) and AP for user-facing availability (feeds, carts, session state). And note: **quorum systems need odd node counts ≥3 and lose availability when they can't reach majority** — which is why a 2-node etcd cluster is worse than 1 (any single failure kills quorum).

### 3. Consistency models — the spectrum
| Model | Meaning | Example |
|---|---|---|
| **Strong / linearisable** | Every read sees the most recent write; operations appear atomic in real time | etcd, Spanner, single-Postgres |
| **Sequential** | All processes agree on a total order, but it may not match real time | Some CP systems |
| **Causal** | Reads respect cause-effect (you never see a reply before the post) | Riak with dot-separated clocks |
| **Read-your-writes** | You always see your own writes (often per-session) | Sticky sessions, primary reads after write |
| **Monotonic reads** | Once you see a value you never see an older one | Session-pinned replicas |
| **Monotonic writes** | Your writes apply in order | Single-writer sessions |
| **Eventual** | Without new writes, replicas converge… eventually | DNS, S3 (now strong for new objects), Cassandra default |
| **Bounded staleness** | Reads may lag by at most X | Replica reads with a max-lag check |

**The senior answer:** "Most apps need strong consistency for a *small subset* of operations and can tolerate staleness elsewhere. So I keep the strongly consistent path narrow — the balance deduction is linearisable; the profile read can be 5 seconds stale — rather than paying strong-consistency cost globally."

### 4. Idempotency and exactly-once — get this right
- **At-most-once**: no retries; may lose messages. Simple, lossy.
- **At-least-once**: retries until ack; **duplicates possible**. This is what almost every real system provides (SQS, Kafka with retries, HTTP with retry).
- **Exactly-once**: impossible in general across a network (the Two Generals Problem — you can't know whether your ack was received). What systems *call* "exactly-once" is **at-least-once delivery + idempotent processing** (or transactional state changes with dedup): Kafka's EOS gives exactly-once *within Kafka's own read-process-write loop* via transactions and an idempotent producer; it does **not** make your external side effects exactly-once.

**Design rule:** make the consumer idempotent. Either a natural key + upsert (`INSERT ... ON CONFLICT DO NOTHING`), or a deduplication table of processed `event_id`s with a TTL, or make the operation itself idempotent (set absolute value, not increment).

Say this sentence and you've passed the sub-question: **"I don't design for exactly-once delivery; I design for at-least-once delivery with idempotent handling, because the former isn't achievable end-to-end."**

### 5. Hashing, consistent hashing, and hot shards
**Naive sharding** `shard = hash(key) % N` is simple but **re-shards almost everything when N changes** — a migration of the whole dataset.

**Consistent hashing**: map nodes and keys onto a ring; a key belongs to the next node clockwise. Adding/removing a node moves only ~K/N keys. **Virtual nodes** (each physical node owns many ring positions) fix load skew and make removal spread across survivors rather than dumping on one neighbour.

**Hot shards** are the real problem: hashing distributes *keys* evenly, not *load*. One celebrity user, one viral post, one big tenant → one shard melts. Fixes:
- **Salting**: split hot key into `key#0..key#7`, write to random shard, read all 8 and merge. Trades read amplification for write distribution.
- **Two-level routing**: keep a hot-key registry that routes known hot keys to dedicated capacity.
- **Separate the hot path**: celebrity timelines served from cache/precomputed aggregates, not from the general store.
- **Shard by the right dimension**: sometimes tenant > user > entity, depending on access patterns and query shapes.

**Also mention range-based sharding** (Bigtable/HBase/DynamoDB style): good for scans and time-ordered data, but prone to hotspots at the tail (all writes land on the last range) — mitigated by splitting ranges dynamically.

### 6. Caching strategies and where caches live
| Location | What | Notes |
|---|---|---|
| **Client/browser** | HTTP cache headers, service worker | Free; hardest to invalidate |
| **CDN edge** | Static + cacheable dynamic | Massive offload; TTL + purge API |
| **LB / gateway** | Response cache, micro-caching | Great for anonymous hot endpoints |
| **App-local (in-process)** | Hot objects | Fastest, but N copies, inconsistent, lost on restart |
| **Distributed (Redis/Memcached)** | Shared hot data | Extra hop + serialisation, but coherent and survives deploys |
| **DB buffer pool** | Pages | Already there; tune it before adding Redis |
| **Materialised views / read models** | Precomputed aggregates | Trade write cost + staleness for cheap reads |

**Invalidation patterns:**
- **Cache-aside (lazy)**: app reads cache, on miss reads DB and populates. Most common. Race: two misses → two DB reads (mitigate with **request coalescing / singleflight**).
- **Write-through**: write cache and DB together. Consistent, higher write latency.
- **Write-behind (write-back)**: write cache, flush to DB async. Fast writes, **data loss risk** on cache failure.
- **Refresh-ahead**: proactively refresh before expiry. Avoids stampedes, wastes work on cold keys.
- **TTL only**: simplest; staleness bounded by TTL.

**Failure modes you must name:**
- **Cache stampede / thundering herd**: a hot key expires and 10k requests hit the DB simultaneously. Fixes: jitter the TTL, singleflight/request coalescing, never-expire + async refresh, **serve stale on error**.
- **Cache avalanche**: many keys expire at once → same problem, bigger. Jitter.
- **Cache penetration**: queries for non-existent keys always miss → DB hammering. Fixes: cache negatives with a short TTL, bloom filter.
- **Big key / hot key**: one key saturating a Redis shard. Fixes: split, local cache in front, read replicas.

**Senior line:** "My default is cache-aside with a jittered TTL, singleflight on miss, and serve-stale-on-backend-error — because the failure mode that takes systems down isn't a slow cache, it's a *missing* cache under load."

### 7. Queues, topics, streams — pick correctly
| | **Queue (SQS, RabbitMQ)** | **Topic/pub-sub (SNS, Pub/Sub)** | **Log/stream (Kafka, Kinesis, Pulsar)** |
|---|---|---|---|
| Consumption | One consumer per message (competing) | Fan-out to subscribers | Each consumer group has its own offset |
| Replay | No | No | **Yes** — the killer feature |
| Ordering | FIFO variants only, per queue/partition | No | Per partition |
| Retention | Until consumed | Transient | Time/size-based (days→forever) |
| Use | Work distribution, task queues, level the load | Notifications, fan-out, decoupling many consumers | Event sourcing, CDC, audit, ML feature pipelines, multi-team consumption |
| Ops cost | Low | Low | High (stateful cluster, partitions, rebalances, disk) |

**Poison messages & DLQs**: a message that always fails will block a FIFO queue or spin forever. Route to a **dead-letter queue** after N receives (`maxReceiveCount`), alert on DLQ depth > 0, and keep the original metadata for replay. **Alerting on DLQ depth is non-optional** — a silently growing DLQ is silent data loss.

**Backpressure**: what happens when the producer outruns the consumer? Bounded queue + block, drop (lossy), drop-oldest, or signal the producer to slow down (TCP-style / reactive streams). **Say which you choose and why** — it's a product decision: for payments you block; for telemetry you drop-oldest; for user actions you never drop silently.

**Ordering**: true global ordering requires a single partition = a single consumer = no horizontal scale. Practical answer: **per-key ordering** (partition by user/order ID) which preserves what matters and still parallelises.

### 8. Replication topologies
| Topology | Pros | Cons |
|---|---|---|
| **Single primary (async)** | Simple, fast writes, no write conflicts | Primary loss = failover + possible data loss (unflushed WAL) |
| **Single primary (semi-sync)** | At least one replica has the write before commit | Higher write latency; can stall if replica dies |
| **Multi-primary** | Writes near users, no single write bottleneck | **Write conflicts** (need LWW, CRDTs, or app-level resolution), replication loops, uniqueness constraints break |
| **Leaderless (Dynamo)** | High availability, no leader election | Conflicts resolved at read (read-repair, anti-entropy), quorum math |
| **Quorum (W+R>N)** | Strong consistency without a single leader | Availability drops when nodes are down; W=R=N/2+1 is the usual setting |

**Failover**: automatic is convenient and dangerous — **split-brain** (two primaries, both accepting writes) causes unrecoverable divergence. Guards: fencing tokens (monotonic version that the storage rejects if stale), STONITH (kill the old node), quorum-based election, and a lease with a clock-safe expiry. **Manual failover for databases is a legitimate senior choice**; say why: "I'd automate detection and *page*, but keep promotion human-approved until the failover is boring and well-tested."

### 9. Load shedding, circuit breaking, graceful degradation
- **Load shedding**: reject work early rather than dying slowly. Priority classes (shed telemetry before user writes), admission control, 429 with `Retry-After`, adaptive concurrency limits.
- **Circuit breaker**: closed → open after N failures → half-open after a cooldown → probe with limited traffic. Prevents a failing dependency from consuming all your threads.
- **Bulkheads**: separate pools per dependency so one slow downstream can't exhaust everything.
- **Graceful degradation**: define what "still working" means without each dependency. Search results from a cached snapshot, recommendations off, checkout still functional. **Write these down in advance** — deciding during an incident is too late.
- **Timeouts and deadlines**: every remote call has one, and they must be **nested-aware** (caller's deadline > sum of callees'), and **propagated** (gRPC context) so downstream stops work nobody will read. Missing timeouts is the #1 cause of cascading failure.

### 10. Numbers to have memorised (back-of-envelope)
| Thing | Order of magnitude |
|---|---|
| L1 cache reference | 0.5 ns |
| Branch mispredict | 5 ns |
| L2 cache | 7 ns |
| Mutex lock/unlock | 25 ns |
| Main memory reference | 100 ns |
| Compress 1 KB with zippy | 3 µs |
| Send 1 KB over 1 Gbps | 10 µs |
| SSD random read | 150 µs |
| Read 1 MB sequentially from memory | 250 µs |
| Round trip within same datacentre | 500 µs |
| Read 1 MB from SSD | 1 ms |
| Disk seek | 10 ms |
| Read 1 MB sequentially from disk | 20–30 ms |
| Send packet CA→NL→CA | **150 ms** |

**The two that matter most in interviews:** ~100 ns to memory vs ~10 ms to disk (100,000×) — this is why caching and sequential I/O dominate everything; and **cross-region is ~100–150 ms**, which is why "just call the DB in the other region" destroys latency.

Sizing math to be fluent in:
```
QPS: 10M requests/day ≈ 116 avg/s ≈ ~250-500 peak/s (2-5x)
Storage: 1M users × 1 KB profile = 1 GB; 100M events/day × 1 KB = 100 GB/day = 36 TB/yr
Bandwidth: 500 req/s × 10 KB response = 5 MB/s = 40 Mbps
Memory: 1M hot objects × 500 B = 500 MB
```
Always state your assumptions and round aggressively — the interviewer cares about the reasoning, not the third digit.

---

## 🔵 Advanced

### 11. How do you choose between SQL and NoSQL?
Not a religion — a mapping of access patterns to storage engines.

**Choose relational when:** you need transactions across entities, joins are central, the schema is stable and known, data integrity matters (FK constraints, uniqueness), or you don't yet know your access patterns (SQL's flexibility is underrated for early-stage).

**Choose document (Mongo/DynamoDB) when:** the access pattern is "get this entity by key" and the entity is naturally hierarchical, schema varies per record, you need single-digit-ms at any scale, and you can **denormalise** happily.

**Choose wide-column (Cassandra/Bigtable/ScyllaDB) when:** massive write throughput, time-series or append-heavy, queries are by partition key + clustering key, and you can accept a query-driven schema (you design tables per query, not per entity).

**Choose key-value/Redis when:** sub-millisecond reads of small hot values, counters, leaderboards, sessions, locks, rate limits.

**Choose graph (Neo4j) when:** relationships *are* the query (multi-hop traversal, fraud rings, social graphs) and joins would explode.

**Choose search (Elasticsearch/OpenSearch) when:** full-text, faceted, fuzzy — as a **secondary index** fed from your primary store, never as the source of truth.

**Senior answer:** "I start from the queries, not the entities. Write down the top 5 reads and top 3 writes with their cardinality and latency budget; the store falls out of that. And most real systems are polyglot: Postgres as the source of truth, Redis for hot paths, S3 for blobs, a search index for discovery, and Kafka to keep them in sync — with the sync being the hardest part, because now you have a consistency problem between systems instead of inside one."

### 12. Sharding a database with zero downtime — walk me through it
1. **Choose the shard key first, and be willing to be wrong about it later.** It must be high-cardinality, present in nearly every query, and stable (immutable). Common choices: `tenant_id`, `user_id`, `order_id`. **Never** shard on something that changes (email, status) or something you frequently query *without* (else every query becomes a scatter-gather).
2. **Make the app shard-aware behind an abstraction** so the routing logic is in one place (a shard map / directory service, not hardcoded `% N`).
3. **Dual-write phase**: write to both old and new stores; read from old. Validate with a **shadow read** comparison (read both, log mismatches, serve old). This catches correctness bugs before users see them.
4. **Backfill** historical data with a throttled, resumable, idempotent job. Track progress; expect it to take much longer than you think. Re-run the shadow comparison until divergence is ~0.
5. **Cut over reads** by cohort (1% → 10% → 50% → 100%) with a **feature flag** and instant rollback. Watch error rates and latency per cohort.
6. **Stop writing to the old store** only after the new path has been stable for longer than your rollback window.
7. **Decommission** the old store, but keep a backup beyond the usual retention.

**The hard parts to volunteer:** cross-shard transactions (avoid by design; use saga/outbox patterns), cross-shard queries and aggregations (precompute into a separate read model or push to a warehouse), global uniqueness (can't use a DB unique constraint across shards — use a dedicated allocator or encode uniqueness into the key), **rebalancing later** (this is where consistent hashing or a shard-map with range moves pays off), and hot shards.

**Also:** "I'd rather start with a single big primary and good indexes, and shard only when I've proven the write ceiling. Premature sharding costs more engineering than almost any other early decision and it's very hard to undo."

### 13. How would you design for multi-region active-active?
**First, challenge the requirement.** Active-active is expensive and most teams actually need *multi-region disaster recovery* (active-passive, warm standby) which is much simpler. Ask: what's the RTO/RPO? If RTO of 30 minutes is acceptable, warm standby is a tenth of the complexity.

If genuinely active-active:
1. **Data placement is the crux.** Three models:
   - **Partition by user geography** (each user has a home region; writes go home, reads anywhere). Avoids write conflicts entirely — this is the pragmatic winner and what most "active-active" systems really do. Requires sticky routing at the edge (DNS/anycast + a lookup) and a plan for users who move.
   - **Full replication with conflict resolution** (CRDTs for counters/sets, LWW elsewhere). Truly write-anywhere, but LWW silently loses data and CRDTs constrain your data model.
   - **Single global write region, read replicas everywhere.** Simplest and often mislabelled "active-active". Reads are local and fast; writes cross regions (add 100–150 ms).
2. **Statelessness at the app tier** so traffic can move instantly.
3. **Global routing**: Route53/Cloud DNS with health checks, latency-based or geo-based policy, anycast for the edge. Beware DNS TTLs and client/OS caching — failover takes longer than you think; use low TTLs *pre-planned* and accept that some clients ignore them.
4. **Cross-region dependencies are latency traps**: a service in region A synchronously calling a DB in region B adds 100–150 ms *per hop*. Keep call graphs regional; make cross-region calls async or cached.
5. **Quorum systems and region count**: a 3-region etcd/Spanner quorum tolerates one region loss; a 2-region quorum tolerates neither (a partition between them kills majority). This is why "two-region active-active with strong consistency" is fundamentally hard.
6. **Failover must be tested.** Untested DR is not DR. Run game days: kill a region in staging, measure actual RTO, find the hardcoded endpoints and the manual steps you forgot.
7. **Cost**: you're paying for 2–3× capacity plus data transfer (cross-region egress is a real line item).

### 14. Event-driven architecture: outbox, saga, CDC
**The dual-write problem:** updating your DB and publishing an event are two separate systems with no shared transaction. Crash between them → DB says one thing, event stream says another. This is *the* classic EDA bug.

**Outbox pattern** (the correct default):
1. In the **same DB transaction** as your state change, insert a row into an `outbox` table.
2. A separate process (poller, or **CDC** via Debezium reading the WAL/binlog) reads outbox rows and publishes to Kafka.
3. On successful publish, mark/delete the row. Publishing is **at-least-once** → consumers must be idempotent.

Why CDC over a poller: no polling latency/DB load, and it captures changes even from code paths that forgot to write the outbox. Cost: you now operate Debezium + Kafka Connect.

**Saga** for distributed transactions: a sequence of local transactions, each with a **compensating action**. Orchestration (a central coordinator — easier to reason about, single point of logic) vs choreography (services react to events — looser coupling, but the flow is invisible and hard to debug). **Senior opinion:** "I default to orchestration for anything with more than three steps, because 'where is this stuck?' must be answerable in one query. Choreography is elegant right up until the first 3 a.m. incident."

Also: sagas give you **eventual consistency, not isolation** — you must handle intermediate states being visible (semantic locks, versioned records, reread-before-compensate).

### 15. Rate limiting — designs and where to put it
**Algorithms:**
| Algorithm | Behaviour | Pros | Cons |
|---|---|---|---|
| **Fixed window counter** | Reset count each minute | Trivial | 2× burst at window boundaries |
| **Sliding window log** | Store each request timestamp | Precise | Memory per request — expensive at scale |
| **Sliding window counter** | Weighted blend of current + previous window | Precise enough, cheap | Slight approximation |
| **Token bucket** | Tokens refill at rate r, capacity b | Allows controlled bursts, simple | Needs per-key state |
| **Leaky bucket** | Queue drains at fixed rate | Smooth output, no bursts | Adds latency, rejects bursts users may legitimately need |
| **Concurrency limit** | Cap in-flight requests, not rate | Protects the resource directly (adaptive) | Doesn't map to "N requests/min" |

**Where to enforce:** edge/CDN (cheapest, blocks the most), gateway/ingress (per-tenant policy, sees identity), service (last line, protects itself), and **client-side** (be polite). Layered is right.

**Distributed state:** Redis with a **Lua script** so check-and-decrement is atomic (two round trips otherwise → race). Alternatives: local approximate limiting with periodic sync (envoy global rate limit service), or consistent-hash routing so a key always hits the same limiter node (no shared state, but rebalancing causes bursts).

**The details that show seniority:**
- Key on **identity**, not IP (NAT/CGNAT means 10k users behind one IP; conversely one abuser rotates IPs).
- Return **429 with `Retry-After`** and include `X-RateLimit-Remaining` headers so clients can back off cooperatively.
- **Fail open or fail closed?** If Redis dies: failing closed takes your API down because of a cache outage (bad); failing open removes all protection (risky). Usually **fail open with aggressive alerting and a local fallback limiter**. Say the trade-off explicitly — there's no free answer.
- Different limits per tier, per endpoint class, per auth state (authenticated > anonymous).
- Your own retries count against your budget → include a retry budget.

### 16. What are the failure modes of the design you just gave me?
**This is the follow-up that separates levels.** Always be ready to enumerate, unprompted:

| Layer | Failure | Detection | Mitigation |
|---|---|---|---|
| DNS | Stale record, TTL too long, provider outage | External probes from multiple regions | Multi-provider DNS, low TTL pre-planned, health-checked records |
| CDN/edge | Cache poisoning, origin shield failure, purge stuck | Cache hit ratio, origin load | Cache keys include auth-relevant dimensions, origin fallback, staged purges |
| LB | Unhealthy target still receiving, conntrack exhaustion, TLS cert expiry | Target health metrics, 5xx by target | Passive+active health checks, connection draining, cert expiry alerts |
| App | Deploy regression, pool exhaustion, GC pause, fd leak | Deploy annotations, saturation metrics | Progressive delivery, bulkheads, auto-rollback |
| Cache | Cold start after failure → stampede, hot key, eviction storm | Hit ratio, DB load correlation | Singleflight, serve-stale, jittered TTL, warm-up |
| Queue | Consumer lag, poison message, DLQ overflow, rebalance storm | Lag, DLQ depth | Autoscale consumers, DLQ alerts, retry budgets |
| DB | Primary failure, replication lag, lock contention, connection exhaustion, disk full | Lag, connections, slow queries | Failover runbook, read-your-writes routing, poolers (PgBouncer), disk forecasting |
| Dependency | Third-party slow/down, degraded, rate-limiting you | Per-dependency latency/error budgets | Timeouts, circuit breakers, cached fallbacks, contract tests |
| Cross-cutting | Retry storm, cascading failure, split-brain, thundering herd after recovery | Request multiplication factor | Jitter, budgets, load shedding, slow ramp after recovery |

**And the meta-failure:** "the monitoring that would tell me about all of the above is itself down" → hence the Watchdog/dead-man's switch.

---

## 🔴 Scenario — six designs, structured

> For each, the *shape* of a good answer is the point. In the interview, spend 3 minutes on requirements and numbers before drawing anything.

### 17. Design a URL shortener (TinyURL)
**Requirements:** create short URL from long URL; redirect short → long; custom aliases; expiry; click analytics; abuse prevention. **Non-functional:** very high read:write (100:1), p99 redirect < 50 ms, high availability (it's on printed material — a broken link is permanent).

**Numbers:** 100M new URLs/day ≈ 1,200 writes/s peak ~5k/s. Reads 100× ≈ 120k/s peak ~500k/s. Storage: 100M/day × 500 B × 5 years ≈ 90 TB metadata — plus analytics dominating everything (billions of events/day → object storage + a columnar store).

**ID generation** (the interesting part): need short, unique, unguessable-ish, no collision retry loop.
- **Base62 of a counter**: `a-zA-Z0-9` = 62 chars; 7 chars = 3.5 trillion IDs. Allocate from a **sharded counter** (each app node leases a range, e.g. 1000 IDs at a time, from a central allocator) → no per-write coordination.
- **Hash of the URL (MD5/SHA truncated)**: no allocator needed, but collisions require detection + retry, and it leaks structure.
- **Snowflake-style** (timestamp + machine + sequence): sortable, no coordination, but IDs are guessable and longer.
- Choose base62 counter with leased ranges. Mention: **don't use sequential IDs exposed raw** if you care about enumeration/privacy — obfuscate with a keyed permutation or use a longer random suffix.

**Data model:** `urls(id, long_url, owner, created_at, expires_at, status)` keyed by `id`; plus a **unique index on (long_url_hash)** to dedupe identical submissions (decide: is that desirable? It leaks that a URL was submitted before — a real privacy trade-off worth raising).

**Read path:** DNS/anycast → CDN (cache the redirect! TTL per URL, most hot URLs served entirely from edge) → LB → redirect service → Redis (hot IDs) → DB. Return **301** (permanent, cacheable, but you lose analytics and can't change the target) vs **302** (not cached by browsers, keeps control and analytics). **Choose 302 for analytics, 301 for hot/static links** — naming this trade-off is a strong signal.

**Write path:** validate + normalise URL (reject private/internal ranges — **SSRF protection**: a shortener that redirects to `http://169.254.169.254/` is an attack vector on your own cloud metadata), allocate ID, write DB, warm cache, return.

**Analytics:** never write to the redirect path synchronously. Emit an event (Kafka/Kinesis) → stream into a columnar store (ClickHouse/BigQuery). Redirect latency stays ~5 ms.

**Abuse:** rate limit by account + IP, block known-malicious destinations (threat intel feeds), scan targets, require auth for bulk creation, honeypot unused ID space to detect enumeration.

**Failure modes:** hot URL → single cache key saturation (local app cache in front of Redis); ID allocator down → fail over to a pre-allocated local range and alert; DB down → serve reads from cache, **stop accepting writes** (degrade gracefully rather than accept-and-lose).

### 18. Design a rate limiter as a service (used by 200 internal teams)
**Requirements:** declarative limits per (tenant, endpoint, identity), enforced with < 5 ms added latency, must survive its own partial failure, self-service config, observable.

**Architecture:** SDK/sidecar in the data path + a central config store + a distributed counter store.
- **Local-first with global reconciliation**: enforce locally against a token bucket seeded from the global limit ÷ N instances, periodically sync actual usage to a global store. Fast (no network hop), approximately correct, degrades gracefully. Error: up to N× overshoot during partition — **acceptable for abuse prevention, not for billing.**
- **Fully global**: every check hits Redis (Lua for atomicity). Exact, but adds a network hop on every request and makes Redis a hard dependency and a scaling bottleneck.
- **Hybrid (what I'd build)**: local buckets for the common case, global checks only when a local bucket is near exhaustion or the key is flagged hot. Exactness where it matters, speed where it doesn't.

**Data model:** config as data (declarative, versioned, in Git → CRDs/ConfigMaps), keyed by `limit_id`. Counters in Redis with a short TTL, or in the local process with periodic flush.

**Failure behaviour — the crux:** decide **fail open vs fail closed per limit class**. Abuse limits fail open (availability > strictness); quota/billing limits fail closed (correctness > availability). Make it a **per-rule property**, not a global setting. Alert loudly either way.

**Multi-tenancy:** noisy-neighbour protection — one team's misconfigured limit must not exhaust shared Redis. Per-tenant quotas on the limiter itself, and per-tenant circuit breaking.

**API/observability:** `GET /limits` for introspection, headers `X-RateLimit-Limit/Remaining/Reset`, 429 + `Retry-After`. Metrics per limit rule: allowed, denied, current utilisation. **A dashboard showing limits that are always at 100% or never hit is how you find wrong config.**

**Platform-engineering angle:** adoption matters more than elegance — a self-service config UI, sane defaults, a dry-run/shadow mode ("what would this limit have blocked last week?"), and a graduated rollout. Shadow mode is the feature that makes teams trust it.

### 19. Design a CI/CD platform for 500 services
See also [`08-CI-CD-and-GitOps`](../08-CI-CD-and-GitOps/README.md).

**Requirements:** build/test/deploy any service; artefact registry; progressive delivery; auditability; self-service; multi-team isolation; secrets handling.

**Architecture:** Git (source of truth for code) → CI (build, test, scan, publish artefact + SBOM, sign) → artefact registry (immutable, versioned, content-addressed) → CD (GitOps: CI writes the new image tag to a deploy repo; Argo CD/Flux reconciles the cluster) → progressive delivery (Argo Rollouts/Flagger: canary → analysis → promote/rollback) → observability feeding the analysis.

**Key design decisions to articulate:**
- **Artefacts are immutable and promoted, not rebuilt.** Build once, test that artefact, promote the same bytes through dev→staging→prod. Rebuilding per environment means you never tested what you ship.
- **GitOps: the cluster converges to Git, nobody `kubectl apply`s.** Gives audit trail, rollback = `git revert`, drift detection, and disaster recovery = point a new cluster at the repo. Cost: Git becomes a bottleneck and a target; you need repo hygiene, CODEOWNERS, and signing.
- **Separation of duties:** who can merge ≠ who can deploy to prod; automated promotion with human gates only at the risky boundaries.
- **Golden paths over enforced paths:** a paved road (templates, defaults, `helm create`-style scaffolding) that 80% of teams use happily, with an escape hatch for the 20% — because a platform teams route around is a failed platform.
- **Multi-tenancy:** namespaces + RBAC + network policies + resource quotas per team; separate clusters for security boundaries (prod vs non-prod, regulated vs not).
- **Secrets:** never in Git, never in images. External Secrets Operator → Vault/cloud KMS; short-lived credentials (IRSA/workload identity) instead of long-lived keys.

**Metrics (say these — DORA):** deployment frequency, lead time for changes, change failure rate, MTTR. Plus platform-specific: build queue wait, cache hit rate, time-to-first-deploy for a new service.

**Scale concerns:** build concurrency vs runner capacity; layer/artefact caching to keep builds < 10 min; a registry that can serve 500 services' image pulls at deploy time without melting (P2P distribution like Dragonfly/Kraken, or pre-pulling).

### 20. Design a metrics/monitoring system for 10k services
This is your *Monitoring and Alerting* folder as a design question — use it.

**Requirements:** collect metrics/logs/traces, query in < 2 s over 24 h, alert within 1 min of a symptom, retain 15 d raw + 1 y downsampled, multi-tenant, bounded cost.

**Numbers:** 10k services × ~2k series each = **20M active series**. At 15 s scrape → 1.3M samples/s. At ~1.5 B/sample → ~170 GB/day raw → 5 TB/month. That immediately rules out a single Prometheus (~1–2M series ceiling) → **shard and remote-write to a central store**.

**Architecture:** exporters/SDKs (or OTel Collector agents per node) → Prometheus agents / VMagent on each cluster (scrape locally, no long-term storage) → **remote write** → central store (Mimir / VictoriaMetrics / Thanos Receive) with object storage behind it → query frontend (splitting + caching) → Grafana. Rules evaluated by a **ruler** component against the global store so cross-cluster SLOs work. Alertmanager cluster (3 replicas) for dedup/routing.

**Key decisions:**
- **Pull at the edge, push to the centre.** Local scraping keeps failure domains small and avoids cross-region scrape latency; remote write centralises querying.
- **Cardinality governance is the design**, not an afterthought: per-tenant series limits at ingest, `write_relabel_configs` drops, a monthly top-N cardinality report to each team, and a documented label policy. At 20M series, a single team adding a `request_id` label can double your bill.
- **Deduplication** on the replica label (2 Prometheus per cluster for HA).
- **Downsampling** tiers: raw 15 d → 5 m → 1 h, so a 1-year dashboard costs seconds not minutes.
- **Alerting philosophy:** symptom-based SLO burn-rate alerts page; cause alerts become tickets. One authority (not Grafana *and* Prometheus *and* cloud alarms).
- **The system monitors itself:** Watchdog dead-man's switch, remote-write drop/lag metrics, notification failure metrics, cardinality metrics.

**Cost levers:** cardinality (dominant), scrape interval, retention tiers, and — usually bigger than metrics — logs and traces (tail sampling, level control).

### 21. Design WhatsApp / a chat system
**Requirements:** 1:1 and group messaging, delivery + read receipts, offline queue, presence, end-to-end encryption, media, multi-device, billions of messages/day.

**Numbers:** 100M messages/min ≈ 1.7M msg/s peak. Storage: 100 B/msg × 10B/day = 1 TB/day for metadata (media dwarfs this). Connections: hundreds of millions of concurrent long-lived sockets.

**Core design:**
- **Persistent connections** (WebSocket/custom binary over TCP, or QUIC) held by stateless-ish **gateway/connection servers** that own the socket and route to logic servers. One machine can hold ~100k–1M connections if it does nothing but multiplex (C10M problem) — so gateways are specialised and horizontally scaled.
- **Routing**: a presence/routing store maps `user → gateway` so a message to Alice knows which gateway holds her socket. This is a huge, hot, write-heavy key-value workload (Cassandra/HBase/Spanner-class).
- **Offline delivery**: if the recipient isn't connected, persist to their **inbox queue** (per-user partitioned log), and drain it on reconnect. Ordering per conversation via a per-conversation sequence number.
- **Group messaging**: fan-out on write (store a copy per member — fast reads, expensive for large groups) vs fan-out on read (store once, each member reads — cheap writes, expensive reads, needs a per-member read pointer). **WhatsApp-scale answer: fan-out on write for small groups, hybrid/read-fan-out for very large groups and channels.** Naming that crossover is the senior signal.
- **Message IDs and ordering**: per-conversation monotonic sequence (not a global clock — impossible at scale). Use a hybrid logical clock or per-partition counters. Global ordering across conversations is unnecessary; causal ordering within one is essential.
- **E2EE**: Signal protocol — X3DH for initial key agreement, **double ratchet** for per-message forward secrecy and post-compromise security. Server stores only ciphertext + metadata. Multi-device requires per-device key material (that's the hard part, and why "linked devices" took years).
- **Receipts**: sent → delivered → read as separate events, each an async ack. Never block the send path on them.
- **Media**: upload to object storage first (with a signed URL), send a message referencing it, download lazily. Don't put bytes in the message path.
- **Presence**: deliberately lossy and rate-limited — exact presence for a billion users is unaffordable, so it's approximate and cached.

**Failure modes:** a gateway dies → its sockets drop, clients reconnect (with jittered backoff, or you DDoS yourself during recovery), routing entries must expire via lease/TTL. Partition between regions → prefer availability for messaging (deliver locally, reconcile later) over strict ordering.

### 22. Design a distributed job scheduler (cron at scale)
**Requirements:** schedule jobs by cron expression or delay; exactly-once-ish execution; retries; per-tenant quotas; observable; scales to millions of jobs.

**Core problem: don't run a job twice, and don't miss it.**
- **Central scheduler with leader election** (etcd/ZooKeeper lease, or a DB advisory lock): one scheduler decides what's due and dispatches. Simple, correct, but the leader is a bottleneck and failover must be safe (fencing tokens so a zombie leader can't dispatch).
- **Distributed with locking**: every scheduler instance evaluates the whole schedule and claims due jobs via an atomic conditional update (`UPDATE jobs SET owner=?, lease_expires=? WHERE id=? AND (owner IS NULL OR lease_expires < now())`). Scales horizontally, no single leader. **This is what I'd build** — the atomic claim is the correctness core, and the lease handles crash recovery.
- **Shard by hash**: each scheduler owns a key range. Efficient, but rebalancing needs care.

**Execution vs scheduling:** separate them. The scheduler only dispatches; **workers** (a queue consumer pool) execute. That way a slow job can't block scheduling, and you scale each independently.

**Timing accuracy:** don't poll a DB every second for millions of rows. Use a **time-bucketed index** (`next_run_at` indexed, fetch the next minute's bucket), or a delay queue (SQS delay, Redis ZSET scored by run time, or a timing wheel in memory).

**Missed jobs (the subtle requirement):** if the scheduler was down for 10 minutes, do you run the missed jobs? **Misfire policy** must be explicit per job: fire once now, fire all, or skip. Quartz/Spring have exactly this concept. Raise it unprompted — it's a great signal.

**Idempotency & exactly-once:** you cannot guarantee exactly-once execution (a worker may finish the job and die before acking). Guarantee **at-least-once with idempotent jobs**, using a **run ID** so a job can dedupe its own side effects, plus a `job_runs` table as the audit trail.

**Also:** concurrency limits per job (don't start a new run while the previous is going — or do, if that's the policy: `allow_concurrent` / `queue` / `skip`), timeouts and kill semantics, dead-letter for permanently failing jobs, tenant quotas and priority classes so one team can't starve others, and **clock skew** awareness (use a monotonic source of truth for "now" or accept NTP drift; never trust the worker's clock for scheduling decisions).

---

## Red flags

| Saying this | Costs you |
|---|---|
| Starting to draw boxes before asking about scale | You'll design the wrong system |
| "Add Redis" with no invalidation story | Caching is 10% storage, 90% invalidation |
| "We'll use Kafka" for a two-service, 100 msg/s problem | Operational cost blindness |
| Claiming exactly-once delivery | It's not achievable end-to-end; say at-least-once + idempotent |
| Sharding before proving the write ceiling | Hardest decision to undo, made with least information |
| Ignoring cross-region latency (150 ms) | Breaks every "just call it remotely" design |
| No failure modes section | You designed for the happy path only |
| No numbers, ever | Can't be evaluated → can't be hired at this level |
| "CAP says pick two of three" | Textbook-misremembered; P isn't a choice |
| Single global ordering requirement accepted without pushback | Costs you all horizontal scale for nothing |

## Rapid recall

1. Requirements → numbers → API → data → boxes → one request end-to-end → bottleneck → scale it → failures → ops.
2. CAP bites **only during a partition**; PACELC adds the latency/consistency trade-off otherwise.
3. At-least-once + idempotent consumers. Never "exactly-once".
4. Consistent hashing + virtual nodes; hot shards need salting or a separate hot path.
5. Cache-aside + jittered TTL + singleflight + serve-stale. Stampede/avalanche/penetration are three different bugs.
6. Queue = one consumer, no replay. Stream = replay + consumer groups, high ops cost.
7. Outbox/CDC solves the dual-write problem; sagas solve distributed transactions (orchestration > choreography for debuggability).
8. Timeouts must be nested-aware and propagated; missing timeouts cause cascades.
9. Shard key: high cardinality, in every query, immutable.
10. Multi-region: partition by user geography beats conflict resolution.
11. 100 ns memory, 10 ms disk, 150 ms cross-region.
12. Always volunteer failure modes before being asked.

→ Next: [`04-Low-Level-Design`](../04-Low-Level-Design/README.md)
