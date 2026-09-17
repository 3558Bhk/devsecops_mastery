# 16 · Databases & Storage

Asked of SDE III candidates heavily (query planning, transactions, replication) and of infra candidates operationally (backups, failover, connection pooling, capacity). Both halves are here.

---

## 🟢 Basic

### 1. SQL vs NoSQL — the real decision criteria
| Dimension | **Relational (SQL)** | **NoSQL** |
|---|---|---|
| Schema | Fixed, enforced, migrations required | Flexible/dynamic, enforced in app code (or not at all) |
| Consistency | Strong (ACID), tunable in some | Eventual by default, tunable (Dynamo-style R/W/W-quorum) |
| Scaling | **Vertical first**, then sharding (hard) | **Horizontal by design** (partition key) |
| Joins | ✅ First-class, optimised | ❌ Usually absent → denormalise, or N queries |
| Transactions | ✅ Multi-row, multi-table ACID | Limited (single-partition, or scoped like DynamoDB `TransactWriteItems`) |
| Query flexibility | **Ad-hoc queries on any column** — the killer feature | Query by key/index you designed for; anything else is a scan |
| Data model | Relations, normalised | Key-value, document, wide-column, graph, time-series |
| Best for | Money, orders, inventory, anything needing invariants and ad-hoc reporting | Sessions, catalogue, feeds, IoT/time-series, graphs, huge-scale simple access patterns |

**The senior answer:**
> "I default to Postgres. It handles relational integrity, JSON documents (`jsonb` with GIN indexes), full-text search, geospatial (PostGIS), time-series (TimescaleDB), vectors (pgvector), and queues (`SELECT ... FOR UPDATE SKIP LOCKED`) — and it does all of them *well enough* that you avoid operating four extra systems. I move off Postgres when a **specific, measured** requirement appears: single-digit-millisecond latency at 100k+ writes/sec with a stable access pattern (DynamoDB/Cassandra), graph traversal at depth (Neo4j), massive time-series ingest (InfluxDB/Timescale/VictoriaMetrics), or global strong consistency at scale (Spanner/CockroachDB/Yugabyte). **Choosing a database because your access pattern is genuinely different is engineering; choosing one because Postgres isn't fashionable is a mistake you'll pay for in operational complexity.**"

**NoSQL families (be precise):**
- **Key-value** (Redis, DynamoDB, etcd): fastest, simplest, no query flexibility.
- **Document** (MongoDB, Couchbase, Firestore): nested JSON, flexible schema, secondary indexes; **joins still hurt**.
- **Wide-column** (Cassandra, ScyllaDB, HBase, Bigtable): partition key + clustering columns, huge scale, tunable consistency, **schema-per-query-pattern** (you design tables around queries, not entities).
- **Graph** (Neo4j, Neptune, TigerGraph): relationships as first-class; traversal queries that would be 8 joins in SQL.
- **Time-series** (InfluxDB, TimescaleDB, Prometheus TSDB, VictoriaMetrics, QuestDB): append-heavy, time-partitioned, downsampling, retention policies.
- **Search** (Elasticsearch/OpenSearch): inverted index, full-text and aggregations; **not a system of record** (use it as a derived view).
- **Ledger/immutable** (QLDB-style, event stores): append-only, cryptographically verifiable.

### 2. Indexes — B-tree, hash, GIN/GiST, BRIN, and when each is right
**B-tree (the default):** balanced tree keeping keys sorted → equality and **range** queries, `ORDER BY`, `MIN/MAX`, prefix matching (`LIKE 'abc%'`). O(log n). PostgreSQL's `btree` handles most cases.

**How a B+tree index actually works (the detail they want):** internal nodes hold keys + pointers for navigation; **all values live in leaf pages**, and leaves are linked for efficient range scans. The **clustered index** (InnoDB's primary key) stores the *actual rows* in leaf pages — so the primary key choice determines physical layout, and secondary indexes store the PK as the row pointer (**which is why a wide/long PK bloats every secondary index in MySQL**). Postgres is heap-organised: indexes point to `(page, offset)` TIDs, and updating a row creates a new version → hence **VACUUM**.

**Other index types:**
| Type | For | Notes |
|---|---|---|
| **Hash** | Equality only | Faster for pure `=`, useless for ranges; Postgres hash indexes are WAL-logged now but rarely better than btree |
| **GIN** (Generalized Inverted Index) | Composite values: `jsonb`, arrays, full-text (`tsvector`) | Inverted index: value → list of rows. **Slow writes, fast reads** — `fastupdate`/pending list mitigates |
| **GiST** | Geometry, ranges, full-text, nearest-neighbour | Extensible framework; KNN queries (`ORDER BY <->`) |
| **SP-GiST** | Non-balanced partitioned trees (IP ranges, phone prefixes, quadtrees) | |
| **BRIN** (Block Range Index) | Very large tables with **physically correlated** columns (timestamps in an append-only table) | **Tiny index** (stores min/max per block range) → excellent for time-series; useless if data isn't correlated |
| **Partial** | `CREATE INDEX ... WHERE status='pending'` | Small, fast, only covers relevant rows — great for hot subsets |
| **Expression / functional** | `CREATE INDEX ON t (lower(email))` | Required when the query uses the expression; **without it the index isn't used** |
| **Covering / INCLUDE** | `CREATE INDEX ... INCLUDE (a,b)` | Index-only scans: no heap fetch. Big win for read-heavy narrow queries |
| **Bitmap** (Oracle) / **columnar** | Low-cardinality analytics | |
| **LSM-tree** (RocksDB/Cassandra/HBase/ScyllaDB) | Write-optimised | See Q3 |
| **Vector (HNSW/IVFFlat)** | Similarity search on embeddings | pgvector, purpose-built vector DBs |

**Composite index rules (frequently tested):**
- **Column order matters**: `(a, b, c)` serves queries on `(a)`, `(a,b)`, `(a,b,c)` — **but not `(b)` or `(b,c)` alone** (the leftmost-prefix rule).
- Put **equality columns first, range columns last** (`WHERE tenant_id = ? AND created_at > ?` → index `(tenant_id, created_at)`). A range column in the middle stops further columns being used for filtering.
- **Selectivity matters**: an index on a boolean column is nearly useless alone (the planner will seq-scan); as the leading column of a composite it can be very useful.
- **Indexes cost writes and storage**: every INSERT/UPDATE/DELETE maintains every index. **A table with 12 indexes has a write amplification problem**, and unused indexes are pure cost — find them with `pg_stat_user_indexes.idx_scan = 0` and drop them.

### 3. B+tree vs LSM-tree — the write-optimisation trade-off
| | **B+tree** (Postgres, MySQL/InnoDB, Oracle) | **LSM-tree** (RocksDB, Cassandra, HBase, ScyllaDB, DynamoDB internals, LevelDB, ClickHouse-ish) |
|---|---|---|
| Writes | **In-place**, random I/O; may split pages; WAL + page writes | **Append-only**: write to a WAL + an in-memory **memtable**, flush to sorted **SSTables** on disk |
| Write amplification | Moderate (page-sized writes for small changes) | Low at write time, **but compaction rewrites data repeatedly** |
| Reads | O(log n), usually 1–4 page reads, **predictable** | May check memtable + several SSTable levels → **read amplification**; mitigated by **bloom filters**, block caches, compaction |
| Space | Fragmentation; needs vacuum/defrag | **Compaction** reclaims space; temporary 2× during compaction |
| Latency profile | Even | **Compaction spikes** and **flush stalls** are a real operational concern |
| Best for | Mixed read/write, transactions, point + range queries, ad-hoc | **Write-heavy**, sequential/append workloads, huge datasets, log/time-series, key-value at scale |
| Range queries | Excellent (leaves linked) | Good within an SSTable, worse across levels |

**The summary sentence:** "B+trees optimise reads and give predictable latency at the cost of random-write amplification; LSM-trees turn random writes into sequential ones — which is why every write-optimised store uses them — and pay for it with read amplification and compaction, which is why bloom filters and compaction tuning are the two things you must understand to operate Cassandra or RocksDB well."

### 4. ACID, isolation levels, and the anomalies
**ACID:**
- **Atomicity** — all or nothing (via WAL/undo logs).
- **Consistency** — invariants hold before and after (enforced by constraints + the application).
- **Isolation** — concurrent transactions don't interfere (the tunable part).
- **Durability** — committed data survives crash (WAL flushed with `fsync` — see topic 01 on `fsync` cost).

**Isolation levels and the anomalies they permit:**
| Level | Dirty read | Non-repeatable read | Phantom read | Serialization anomaly | Notes |
|---|---|---|---|---|---|
| **Read Uncommitted** | ✅ possible | ✅ | ✅ | ✅ | Almost never used |
| **Read Committed** (Postgres/Oracle default) | ❌ | ✅ | ✅ | ✅ | Each statement sees a snapshot |
| **Repeatable Read** (MySQL InnoDB default) | ❌ | ❌ | ✅ (in standard SQL; **InnoDB mostly prevents via gap locks**) | ✅ | |
| **Serializable** | ❌ | ❌ | ❌ | ❌ | Postgres: **SSI** (snapshot isolation + conflict detection → serialization failures you must retry). SQL Server: locks. Highest correctness, lowest throughput |

**The anomaly definitions (be precise):**
- **Dirty read**: reading data written by a transaction that later rolls back.
- **Non-repeatable read**: reading the same row twice in one transaction and getting different values (someone else committed an update).
- **Phantom read**: running the same *predicate* query twice and getting a different **set of rows** (someone inserted/deleted matching rows).
- **Write skew**: two transactions each read a set, and each writes based on what it read, violating a constraint that spans both (e.g. two doctors each check "is another doctor on call?" → both say yes → both go off call). **Snapshot Isolation does NOT prevent write skew** — this is the classic gotcha, and the reason Postgres offers true `SERIALIZABLE` (SSI).
- **Lost update**: two transactions read-modify-write the same row and one overwrites the other. Prevented by `SELECT ... FOR UPDATE`, atomic updates (`SET x = x + 1`), or optimistic version columns.

**MVCC (Multi-Version Concurrency Control):** readers don't block writers and writers don't block readers — each transaction sees a **snapshot** of committed data as of its start (or statement start, in Read Committed). Old row versions are retained and later reclaimed:
- **Postgres**: old versions stay **in the table (heap)** → **table bloat** → **autovacuum** must reclaim them. Long-running transactions (and abandoned `PREPARE TRANSACTION`s, and stuck replication slots) **hold back the xmin horizon and prevent vacuum** → bloat → performance collapse. **This is a very common Postgres production incident and knowing the mechanism is a strong signal.**
- **MySQL/InnoDB**: undo logs hold old versions; the **purge** thread cleans them. Long transactions still cause undo growth and history-list-length problems.
- **Oracle**: undo tablespace, ORA-01555 "snapshot too old" if a query runs longer than undo retention.

### 5. Normalisation and its limits
**Normal forms:**
- **1NF**: atomic values, no repeating groups (no `phone1, phone2, phone3` columns; no comma-separated lists).
- **2NF**: 1NF + no **partial dependency** on a composite key (every non-key attribute depends on the *whole* key).
- **3NF**: 2NF + no **transitive dependency** (non-key attributes depend only on the key, not on other non-key attributes — e.g. `zip_code → city → state` means `city`/`state` belong in their own table).
- **BCNF**: every determinant is a candidate key (a stricter 3NF).
- **4NF**: no **multi-valued dependencies**. 5NF: no join dependencies. (Rarely relevant in practice.)

**Why denormalise anyway (and say it clearly):**
- **Joins cost**, especially across shards or in NoSQL where joins don't exist.
- **Read-heavy workloads** benefit from pre-joined, pre-aggregated shapes (a `order_summary` table, a materialised view, a read model).
- **Distributed systems**: keeping related data co-located in one partition is often mandatory (a shopping cart with its items).
- **CQRS**: separate write model (normalised, invariant-preserving) from read model (denormalised, query-optimised), synced via events/CDC. **The clean way to have both.**
- **The discipline**: denormalise *deliberately*, with a documented invariant and a mechanism to keep the copies consistent (triggers, CDC, application-level dual write with reconciliation, or a single writer). **Undocumented denormalisation is how you get two sources of truth that disagree.**

### 6. Replication topologies
| Topology | Description | Failover | Write scaling | Conflict risk |
|---|---|---|---|---|
| **Single-primary (async)** | One writer, N readers, async copy | Manual/automated promote; **RPO > 0** (lost writes) | ❌ | None |
| **Single-primary (semi-sync)** | At least one replica acks before commit | **RPO ≈ 0** | ❌ | None; **latency cost** |
| **Single-primary (sync)** | All/specified replicas ack | RPO = 0 | ❌ | None; high latency, availability coupled to replicas |
| **Multi-primary / active-active** | Any node accepts writes | Excellent | ✅ | **✅ High** — needs conflict resolution |
| **Cascading** | Replica of a replica | — | Reduces primary load | Lag compounds |
| **Quorum-based (Raft/Paxos)** | Majority must agree (etcd, CockroachDB, Spanner, Consul, ZooKeeper-ish ZAB) | Automatic, RPO = 0 | Limited (one leader) | None (linearisable) |

**Replication lag — the operational reality:**
- Async replication **always** lags under write load, and the lag is unbounded.
- **Read-your-writes** breaks: a user writes, then reads from a replica and doesn't see it. Fixes: read from the primary for the user's own recent writes (sticky sessions / a "read primary for N seconds after write" rule), wait for a specific LSN/GTID on the replica (`pg_last_wal_replay_lsn()`, MySQL `WAIT_FOR_EXECUTED_GTID_SET`), or use semi-sync/causal consistency.
- **Monitor lag** (`pg_stat_replication.replay_lag`, `Seconds_Behind_Source`, `AuroraReplicaLag`) and **alert** — silent lag breaks reporting and read-your-writes.
- **Causes of lag**: a big transaction/bulk load, DDL, replica resource constraints (undersized replicas are common), network, and **long-running read queries on the replica** (which hold back replay in Postgres).
- **Failover with async replication loses data** — the promoted replica may be behind. This is why RPO matters and why semi-sync/quorum exists.

---

## 🔵 Advanced

### 7. Sharding / partitioning — strategies and the pain
**Partitioning (within one DB engine)** vs **sharding (across multiple nodes)** — the terms overlap; Postgres calls declarative partitioning "partitioning", Citus/Vitess/CockroachDB call it sharding.

**Strategies:**
| Strategy | How | Pros | Cons |
|---|---|---|---|
| **Range** (by date/ID) | `[2026-01, 2026-02)` | Simple, efficient pruning, easy archival/drop-old-partition | **Hot spot at the end** (all writes to the newest partition) |
| **List** (by region/tenant) | Explicit value lists | Predictable, good for tenant isolation | Manual maintenance, unbalanced |
| **Hash** | `hash(key) % N` | Even distribution | **Resharding is painful** (N changes → nearly everything moves); no range queries |
| **Consistent hashing** | Ring with virtual nodes | Adding/removing a node moves only ~1/N of keys | Uneven without enough vnodes; more complex |
| **Directory/lookup** | A routing table maps key → shard | Flexible, supports any scheme | The directory is a SPOF and a hot path (cache it) |
| **Composite / hierarchical** | `tenant_id` then date | Tenant isolation + time pruning | Complexity |

**What breaks when you shard (the real answer):**
1. **Cross-shard joins** — impossible or expensive. Denormalise, or use a scatter-gather query layer, or accept N queries.
2. **Cross-shard transactions** — need 2PC/XA (slow, blocking, coordinator failure modes) or **sagas** with compensation. Most systems give up distributed transactions and design around them.
3. **Cross-shard aggregations and pagination** — `ORDER BY x LIMIT 10 OFFSET 10000` across 64 shards means fetching a lot and merging. Global secondary indexes are hard.
4. **Resharding** — the operation everyone underestimates (see Q11 in [`03-System-Design-HLD`](../03-System-Design-HLD/README.md)).
5. **Hot shards** — a celebrity tenant, a viral item, a monotonic key. Fixes: better key design, write sharding (suffix the key and fan out reads), caching, or per-key rate limiting.
6. **Uniqueness constraints** across shards (a globally unique email) require either the shard key to include it, a separate global index/table, or an application-level check (racy).
7. **Operational complexity**: N databases to back up, migrate, upgrade, monitor. **Schema migrations across 64 shards with zero downtime is a project.**

**Choosing a shard key — the criteria:**
- **High cardinality** (avoid hot spots), **evenly distributed**, **stable** (never changes — a changing key means moving data), and **present in most queries** (so you can route without scatter-gather).
- **`tenant_id`** is the natural choice for multi-tenant SaaS (isolation, routing, per-tenant operations) — with the caveat that a huge tenant becomes a hot shard, so you may need to sub-shard large tenants.
- **Never shard on a timestamp alone** (all writes to one shard), and be careful with auto-increment IDs (same problem, plus it leaks volume).
- **Distributed SQL (CockroachDB, YugabyteDB, Spanner, TiDB)** does sharding for you with SQL semantics and distributed transactions — **the honest recommendation when you need to shard and can afford the operational/latency cost**, versus hand-rolling sharding with Vitess/Citus (cheaper, more control, more work).

### 8. Connection pooling — the thing that takes down databases
**Why it's necessary:** each Postgres connection is a **process** (~5–10 MB plus work_mem allocations), and `max_connections` is typically 100–500. **50 pods × 20 connections = 1,000 → the database is down or thrashing.** MySQL threads are lighter but still bounded and still cost memory.

**Options:**
| Approach | Where | Notes |
|---|---|---|
| **Application pool** (HikariCP, pgxpool, SQLAlchemy pool) | In-process | Fast, no extra hop; **but N instances × pool size connections**. Right-size: often `pool_size ≈ (cores × 2) + effective_spindle_count` per instance — **smaller than you think** |
| **External pooler — PgBouncer / pgcat / ProxySQL** | Separate service | **Transaction mode** multiplexes many clients onto few server connections (1000:10) — the standard answer. **Statement mode** is more aggressive (breaks multi-statement transactions). **Session mode** = 1:1 (no multiplexing benefit) |
| **Managed** (RDS Proxy, Cloud SQL Auth Proxy, Aurora Limitless) | Cloud | Handles failover connection draining, IAM auth, and pooling |
| **Built-in pooler** (Postgres 17+ has a native connection pooler arriving; Supabase/Neon/Crunchy offer it) | Server-side | Reduces the extra hop |

**PgBouncer transaction-mode caveats (know these — they're the interview detail):**
- **No prepared statements** (they're session-scoped) — breaks some ORMs/drivers unless you use `pgcat` or protocol-level query mode, or Postgres 17+/PgBouncer 1.21+ improvements.
- **No session-level state**: `SET` (session GUCs), advisory locks, `LISTEN/NOTIFY`, temp tables, `SET ROLE`, cursors — all break, because the next statement may land on a different server connection.
- **`search_path` and `timezone` surprises.**
- **Fixes**: use `SET LOCAL` inside transactions, avoid session state, or use session-pooling for the workloads that need it (and accept the lower multiplexing).

**Pool sizing insight (frequently quoted, worth knowing):**
> "HikariCP's guidance — and Postgres's own benchmarking — is that **smaller pools are faster**. A pool of 100 connections against 8 cores doesn't give you 100× throughput; it gives you context switching, lock contention and cache thrashing. The right size is roughly `2–4× cores` for the *database*, and the application pool should be sized so the total across all instances is in that range. When an app can't get enough connections, the fix is usually **faster queries or a pooler**, not a bigger pool."

**Related failure modes:** connection storms after a failover or a deploy (all pods reconnect at once — mitigate with **connection jitter/backoff on the client** and **PgBouncer/RDS Proxy to absorb it**), leaked connections (an ORM not releasing — set idle timeouts: `idle_in_transaction_session_timeout`, `statement_timeout`, and pooler-level `server_idle_timeout`), and **`idle in transaction`** sessions holding locks and blocking vacuum.

### 9. Query performance — how to diagnose a slow query
**The method:**
```sql
EXPLAIN (ANALYZE, BUFFERS, VERBOSE) <query>;
```
- `EXPLAIN` = the plan (estimated). `ANALYZE` = **actually executes it** and shows real timings/rows (**never run on a destructive or very expensive query in prod without care**). `BUFFERS` = shared/local block hits and reads (tells you if it's I/O-bound).
- **Compare estimated rows vs actual rows.** A large discrepancy means **stale statistics** → `ANALYZE table` (and check autovacuum's `analyze` settings). **Wrong estimates cause wrong plans** — this is the single most common cause of a suddenly-slow query.

**What to look for in a plan:**
| Node | Meaning | Bad when |
|---|---|---|
| **Seq Scan** | Full table scan | On a large table with a selective predicate → **missing index**. Legitimate for small tables or low-selectivity queries |
| **Index Scan / Index Only Scan** | Uses an index (Only = no heap fetch, best) | — |
| **Bitmap Heap Scan** | Bitmap index scan then heap fetch | Good for many rows; watch recheck |
| **Nested Loop** | Join row by row | Fine for small inner sets; **catastrophic if the inner side is large and unindexed** |
| **Hash Join** | Build a hash table on one side | Good for large equi-joins; **spills to disk if `work_mem` is too small** → very slow |
| **Merge Join** | Both sides sorted | Good when data is already sorted |
| **Sort → external merge (disk)** | Sorting spilled to disk | Increase `work_mem` (carefully — it's **per operation per connection**) or add an index for the sort order |
| **Gather / Gather Merge** | Parallel workers | Good; check `max_parallel_workers_per_gather` |
| **Rows Removed by Filter: 1000000** | Filtering after fetching | Predicate not indexable → expression index, partial index, or a rewrite |

**The common causes and fixes, in order of frequency:**
1. **Missing or unusable index** — add it; or the query uses an expression/function on the column (`WHERE lower(email)=...`, `WHERE date(created_at)=...`) → **expression index** or rewrite to be sargable (`WHERE created_at >= '...' AND created_at < '...'`).
2. **Stale statistics** → `ANALYZE`; tune autovacuum (`autovacuum_analyze_scale_factor`), and note that a bulk load should be followed by an explicit `ANALYZE`.
3. **N+1 queries** — 1 query for the list + N for the children. **The #1 ORM performance bug.** Fix with a JOIN, `IN (...)` batching, eager loading (`includes`/`select_related`), or a dataloader.
4. **`SELECT *`** — fetches TOASTed columns unnecessarily, prevents index-only scans, wastes network and memory.
5. **Large `OFFSET` pagination** — `LIMIT 20 OFFSET 100000` scans and discards 100k rows. Fix with **keyset/seek pagination**: `WHERE (created_at, id) < ($1, $2) ORDER BY created_at DESC, id DESC LIMIT 20`. **Mention keyset pagination by name — it's a well-known test.**
6. **Bad join order / missing join index** — the planner chose poorly; check `join_collapse_limit`, consider hints (pg_hint_plan) or restructuring.
7. **Lock contention** — `pg_locks` + `pg_stat_activity` to find blockers; long `idle in transaction`; a DDL taking an `ACCESS EXCLUSIVE` lock behind a long query (the classic: an `ALTER TABLE` queued behind a long select blocks *everything* behind it).
8. **Bloat** — vacuum not keeping up (long transactions, high update rate, disabled autovacuum). Check `pg_stat_user_tables.n_dead_tup`, run `VACUUM (ANALYZE)`, and for severe cases `pg_repack` (online, no long lock) rather than `VACUUM FULL` (which takes an exclusive lock).
9. **Resource limits** — insufficient `shared_buffers`/`work_mem`/`effective_cache_size`, IOPS saturation, CPU saturation, or **an undersized replica serving reads**.
10. **The query is fine and the data grew** — a plan that was optimal at 1M rows is terrible at 500M. **Re-examine plans as data grows**; consider partitioning.

**Beyond the query:** `pg_stat_statements` (the top-N queries by total time — **always start here for a database-level slowdown, not with one query**), `pg_stat_user_tables` (seq scans vs index scans per table), `pg_stat_activity` (what's running now), **Performance Insights** (RDS/Aurora DB load by wait event), `auto_explain` for catching the occasional bad plan, and slow-query logs.

### 10. Locking, deadlocks, and concurrency control
**Lock types (Postgres):** `ACCESS SHARE` (plain SELECT) < `ROW SHARE` (`SELECT FOR UPDATE`) < `ROW EXCLUSIVE` (INSERT/UPDATE/DELETE) < `SHARE UPDATE EXCLUSIVE` (VACUUM, ANALYZE, CREATE INDEX CONCURRENTLY) < `SHARE` (CREATE INDEX) < `SHARE ROW EXCLUSIVE` < **`ACCESS EXCLUSIVE`** (DROP, TRUNCATE, most ALTER TABLE, REINDEX, VACUUM FULL) — **conflicts with everything, including plain SELECTs.**

**The DDL trap (a very common production incident):** an `ALTER TABLE` needs `ACCESS EXCLUSIVE`. If a long-running query holds `ACCESS SHARE`, the DDL **waits** — and every query behind it also waits, including reads. **A 5-second migration can take down a service.** Mitigations: set a short `lock_timeout` for the DDL session and retry; run migrations in low-traffic windows; split DDL into safe steps; and **always set `lock_timeout` before DDL in production**.

**Row-level:** InnoDB uses **record locks, gap locks, and next-key locks** (gap locking is how REPEATABLE READ mostly prevents phantoms — and why it causes surprises and deadlocks under concurrency). Postgres uses row locks + **SSI** predicate conflict detection for SERIALIZABLE.

**Deadlocks:** two transactions each waiting for a lock the other holds. Databases detect them (Postgres after `deadlock_timeout`, default 1s) and **abort one** with an error. Prevention strategies:
- **Acquire locks in a consistent order** across all code paths (the classic fix — e.g. always update accounts in ID order).
- **Keep transactions short** and avoid user think-time inside a transaction.
- Avoid `SELECT FOR UPDATE` when an atomic conditional update works (`UPDATE ... SET qty = qty - 1 WHERE qty >= 1`).
- Reduce contention: smaller transactions, better indexes (a seq scan locks more than it needs to), partitioning hot rows.
- **Handle the retry**: deadlock and serialization failures (`40001`, `40P01`) are **expected, retryable errors** — the application must retry with backoff. **Not handling them is a bug.**
- **Optimistic concurrency** (a `version` column: `UPDATE ... WHERE id=? AND version=?`, check rows-affected) avoids locking entirely for low-contention cases.

### 11. Backups, PITR, and restore — the operational core
**Types:**
| Type | What | RPO | Cost |
|---|---|---|---|
| **Logical dump** (`pg_dump`, `mysqldump`) | SQL/CSV of the data | As of dump time | Portable, slow to restore, no PITR, version-flexible |
| **Physical/base backup** (`pg_basebackup`, RDS snapshots, XtraBackup) | A copy of the data directory | As of backup time | Fast restore, must match major version |
| **WAL/binlog archiving** | Continuous transaction logs | **Seconds** | Enables **PITR** |
| **PITR** | Base backup + replay WAL to any timestamp | **Any point in the retention window** | The standard for production |
| **Continuous replication to a standby/another region** | A live copy | Near-zero | Fast failover; **not a backup** (a `DROP TABLE` replicates instantly) |
| **Application-level / CDC to a lake** | Derived copy | Varies | Analytics, not recovery |

**The critical distinction to state:** "**A replica is not a backup.** Replication protects against instance failure; it faithfully and instantly replicates `DROP TABLE`, a bad migration, ransomware, and application bugs. You need point-in-time recovery with **immutable, access-controlled, cross-account/cross-region copies** and — the part everyone skips — **tested restores with measured RTO.**"

**Backup discipline:**
- **The 3-2-1 rule**: 3 copies, 2 media, 1 offsite (and increasingly **1 immutable/offline** for ransomware).
- **Cross-account/cross-region** copies with a **separate IAM boundary** — a compromised primary account shouldn't be able to delete the backups. **Object lock / WORM / retention locks.**
- **Encryption** of backups with keys whose recovery doesn't depend on the primary account.
- **Retention**: automated (RDS 1–35 days) + long-term manual snapshots (monthly/yearly for compliance).
- **Restore drills**: quarterly, timed, and documented. **Measure RTO** — if restoring a 2 TB database takes 14 hours and your RTO is 1 hour, you don't have DR, you have files.
- **Test integrity**: `pg_verifybackup`, checksums, and actually *starting* the restored instance and running validation queries.
- **Include the schema and the code versions**: a database restored without the matching migration state is a mess. **Back up the migration history/versions alongside.**
- **RDS/Aurora specifics**: automated backups + PITR within the retention window, final snapshot on deletion (`skip_final_snapshot = false`), **Aurora Backtrack** (rewind in place, seconds), **cross-region automated backup replication**, and **Fast Snapshot Restore / lazy EBS loading** awareness for large restores.
- **The `DELETE`-heavy workload caveat**: in Postgres, a mass delete doesn't free space until vacuum, and a PITR replay of millions of WAL records is slow — so **restoring to a point before a mass deletion is often faster than undoing it**, and having the WAL volume to replay is a real RTO factor.

### 12. Distributed databases — Spanner, CockroachDB, YugabyteDB, Cassandra
| | **Spanner (GCP)** | **CockroachDB** | **YugabyteDB** | **Cassandra / ScyllaDB** | **DynamoDB** |
|---|---|---|---|---|---|
| Model | Relational SQL | Relational SQL (Postgres wire) | Relational SQL (Postgres wire) | Wide-column, CQL | Key-value/document |
| Consensus | **Paxos** per split | **Raft** per range | **Raft** per tablet | **Gossip + hinted handoff + read repair**, tunable quorum (no consensus for writes by default) | Managed (multi-paxos-ish internally) |
| Consistency | **External consistency (linearisable) globally**, via **TrueTime** | **Serializable** by default | Serializable | Tunable (ONE/QUORUM/ALL); **eventual by default** | Strongly consistent reads/writes on the leader region |
| Clocks | **TrueTime** (GPS + atomic clocks; bounded uncertainty ε; commit waits ε) | **HLC** (hybrid logical clocks; no commit wait) | **HLC** | Last-write-wins timestamps | Managed |
| Transactions | Distributed ACID | Distributed ACID (2PC over Raft) | Distributed ACID | Lightweight transactions (single-row CAS) only; no multi-row ACID (except batches, which aren't atomic in the SQL sense) | 25-item `TransactWriteItems` (single region) |
| Geo-distribution | Native, multi-region strong | Native, **locality-aware** (pin ranges to regions) | Native | Native, multi-master | **Global Tables** (multi-active, LWW) |
| Scaling | Automatic splits | Automatic rebalancing | Automatic | Manual-ish token management; **adds nodes linearly** | Automatic (watch hot partitions) |
| Ops burden | None (managed) | High (self-managed) or managed | High or managed | **High** (compaction, repairs, tombstones) | None |
| Latency | Cross-region writes pay the consensus round trip | Same; **route to the leaseholder region** to avoid it | Same | Local reads/writes are fast; cross-DC quorum is slower | Single-digit ms in-region |

**The key insights:**
- **TrueTime is the interesting idea**: Google bounds clock uncertainty with GPS + atomic clocks, and a commit **waits out the uncertainty interval** so that transaction ordering is globally consistent with real time (**external consistency**). CockroachDB/YugabyteDB use **hybrid logical clocks** instead and get **serializability without external consistency** — a subtle but real difference (no commit-wait, but transaction timestamps aren't guaranteed to match physical time ordering across regions).
- **The latency cost of strong consistency across regions is physics**: a cross-region consensus write pays at least one inter-region round trip (~70–150 ms). So **place the leader near the writers** (CockroachDB/YugabyteDB locality, Spanner's leader regions), or accept eventual consistency for that data.
- **Cassandra's model**: no master, tunable consistency with `R + W > N` for strong-ish reads, **gossip** for membership, **hinted handoff** and **read repair** for consistency recovery, **anti-entropy repair** (Merkle trees) to fix divergence. **Tombstones** (delete markers) are the operational nightmare: a mass delete creates millions of tombstones that must be read and filtered until compaction clears them → **query latency collapses**. **Knowing the tombstone problem is the Cassandra shibboleth.**
- **When to choose distributed SQL**: you need SQL + transactions + horizontal scale + strong consistency, and you'd otherwise hand-roll sharding. **When not to**: you can meet your needs with a single primary + read replicas (most systems can, to surprisingly large scale), or your access pattern is simple key-value at extreme scale (DynamoDB/Cassandra are cheaper and simpler).
- **The honest cost:** distributed SQL adds operational complexity (or vendor cost), cross-region latency, and a new failure-mode vocabulary (leaseholder transfers, range unavailability, clock skew). **Most teams underestimate it and adopt it for scale they don't have.**

---

## 🔴 Scenario

### 13. "A query that took 50ms last week takes 8s today. Nothing was deployed. Investigate."
**The framing: "nothing was deployed" means the change is in the data, the statistics, the plan, the load, or the environment — not the code.**

**Step 1 — Confirm and scope.**
- Is it *this* query or all queries? One endpoint or everything? One tenant or all?
- Since exactly when? (Correlate with: data growth, a batch job, a migration, a vacuum, a config change, an infra event, a traffic change, a replica promotion.)
- Is it slow on the primary and the replicas? If only one node → node-specific (resource, bloat, replication).

**Step 2 — Look at the database, not just the query.**
```sql
SELECT * FROM pg_stat_activity WHERE state <> 'idle' ORDER BY query_start;   -- what's running now
SELECT wait_event_type, wait_event, count(*) FROM pg_stat_activity GROUP BY 1,2 ORDER BY 3 DESC;
SELECT * FROM pg_locks l JOIN pg_stat_activity a USING (pid) WHERE NOT l.granted;  -- blocked
SELECT query, calls, mean_exec_time, total_exec_time FROM pg_stat_statements ORDER BY mean_exec_time DESC LIMIT 20;
```
**Wait events tell you the category immediately:** `Lock` (contention), `IO:DataFileRead` (I/O-bound, maybe a plan change or cache loss), `CPU` (compute), `Client:ClientRead` (app-side, not the DB), `LWLock:buffer_mapping` (buffer contention), `Activity:WalWrite` (WAL pressure).

**Step 3 — The ranked hypotheses:**
1. **The plan changed** — most common. Compare `EXPLAIN (ANALYZE, BUFFERS)` now vs a known-good plan. Causes:
   - **Statistics went stale or were refreshed into a worse estimate.** Autovacuum ran `ANALYZE` and new statistics led the planner to a different (worse) plan — **"nothing was deployed" and the plan changed anyway.** Check `pg_stat_user_tables.last_analyze`, and `n_distinct` estimates vs reality.
   - **Data distribution changed**: a value became common (skew), a partition filled up, a "rare" status is now 40% of rows → an index scan became a seq scan (correctly!).
   - **Data volume crossed a threshold**: at 1M rows a nested loop was fine; at 20M it isn't.
   - **Parameter/config change**: `work_mem`, `random_page_cost`, `default_statistics_target`, `join_collapse_limit`, a new extension, or **a Postgres minor-version upgrade that changed the planner** (this happens, and it's a real incident class).
   - **A new index changed the planner's options** (someone added an index for another query, and this query's plan flipped).
   - **Fix**: `ANALYZE`, extended statistics (`CREATE STATISTICS` on correlated columns), a partial/expression index, rewrite the query to be sargable, or (as a last resort) `pg_hint_plan`.
2. **Lock contention** — a long transaction, an `idle in transaction` session, or a DDL waiting behind a long read (and blocking everything behind it). `pg_locks` + `pg_stat_activity` shows the blocker chain. **Fix**: kill the blocker (`pg_terminate_backend`), set `idle_in_transaction_session_timeout` and `lock_timeout`, and fix the app that leaves transactions open.
3. **Bloat / vacuum falling behind** — a high-update workload with a long-running transaction holding back `xmin` → dead tuples accumulate → seq scans read far more pages → **a query gets progressively slower over days**. Check `n_dead_tup`, `last_autovacuum`, and `pg_stat_replication`/long transactions. **Fix**: kill the long transaction, tune autovacuum (more workers, lower scale factors for hot tables), `pg_repack` if severe.
4. **Resource saturation** — CPU, IOPS, memory, connections. Check CloudWatch/monitoring: `ReadIOPS`, `CPUUtilization`, `FreeableMemory`, `SwapUsage` (**swapping = death**), connection count. **A noisy neighbour query or a new batch job can starve this one.** Fix: kill/throttle the offender, scale up, separate workloads (read replicas, a separate analytics instance).
5. **Cache eviction** — the working set no longer fits in `shared_buffers`/the buffer cache (because data grew, or a big scan evicted everything). Symptom: `BUFFERS` shows `read` instead of `hit`. Fix: more memory, or stop the big scan (a nightly report on the primary is a classic cause).
6. **Replica lag / routing change** — reads were moved to a lagging or undersized replica; or a failover happened and the new primary is smaller. Check which node the query is hitting and its specs/lag.
7. **Network/storage** — an EBS volume hitting its IOPS/throughput burst credit exhaustion (**gp2 credit depletion is a genuine, sneaky cause**), a storage-level incident, or MTU/network degradation.
8. **The application changed behaviour, not code** — a feature flag enabled, a client sending different parameters (a date range that now spans 10× more data), a tenant whose data grew, or a cache miss (Redis down → every request hits the DB). **A Redis outage presenting as "the database got slow" is extremely common** — check the cache hit rate first.
9. **Parameter sniffing / bind variables** (more a SQL Server/Oracle thing, but Postgres has generic-vs-custom plan switching with prepared statements): a plan optimised for one parameter value is terrible for another. **Postgres switches to a generic plan after 5 executions of a prepared statement** — which can cause exactly this symptom: fine for a while, then suddenly slow. Fix: `plan_cache_mode = force_custom_plan`, or restructure.

**Step 4 — Mitigate, then fix properly.** Kill the blocking session, add the missing index `CONCURRENTLY`, scale up, throttle the offender, or roll back the config change. Then: capture the plan and the metrics for the post-mortem, add the alert that would have caught it (plan-change detection, slow-query alerting, bloat monitoring, cache-hit-rate alerting), and add the regression test.

**The framing:** "'Nothing was deployed' is the interesting part — it means the change is in the data or the environment. So I look at four things in order: **the plan** (did estimates or statistics change?), **the locks** (is it waiting rather than working?), **the resources** (is the node saturated or swapped?), and **the callers** (did a cache fail or a parameter change?). `pg_stat_statements` plus `EXPLAIN (ANALYZE, BUFFERS)` plus the wait-event breakdown answers it in five minutes about 80% of the time."

### 14. "Design the storage for a system ingesting 1M events/sec, kept 7 years, queried ad hoc."
**Clarify first:** event size, cardinality of query patterns (dashboards vs arbitrary exploration vs full-text), latency requirements, whether mutations/deletes are needed (GDPR erasure changes everything), and the budget. **Assume: ~1 KB events, 1M/s = ~86 TB/day raw, dashboards in < 5s, ad-hoc queries in < 60s, append-only with per-user erasure required.**

**The architecture (layered, because no single store does all of this):**
```
Producers ──► Kafka (buffer, replay, decoupling; partitioned by key, 7-day retention)
                 │
      ┌──────────┼─────────────────────┬──────────────────────┐
      ▼          ▼                     ▼                      ▼
  Hot path   Warm path             Cold path              Derived
  Stream     Columnar OLAP         Object storage         Aggregates/
  processing (ClickHouse /         (Parquet + Iceberg     rollups for
  (Flink)     BigQuery /           on S3/GCS)             dashboards
      │       Doris / Athena)         │                   (materialised
      ▼                               ▼                    views, rollups)
  Serving   Ad-hoc + analytics    Archive + compliance
  (last 7d) (last 90d)            (7y, Glacier/Archive)
```
**Layer decisions and reasoning:**
1. **Kafka (or Pub/Sub/MSK) as the ingest buffer.** 1M/s = you need a decoupling layer so a slow consumer doesn't lose data, and so you can replay. Partition by a key that balances load and preserves needed ordering; size partitions for the parallelism you'll ever need (**partition count is hard to increase cleanly later**). Replication factor 3, `min.insync.replicas=2`, `acks=all` for durability.
2. **Raw landing in object storage as Parquet + an open table format (Iceberg/Delta/Hudi).** **This is the single most important decision:** Parquet is columnar (fast scans, cheap compression — typically 5–10× on event data), and Iceberg gives you **schema evolution, partition evolution, ACID commits, time travel, and engine independence** (Spark, Flink, Trino, BigQuery, Athena, Snowflake can all read it). **Without an open format you're welded to one engine.**
3. **Partitioning strategy — the make-or-break detail.** Partition by **time (day or hour)** for pruning, and consider a second level by a high-cardinality-but-commonly-filtered dimension (tenant, event type, region). **Beware: too-fine partitioning creates millions of small files → metadata explosion and slow planning.** Target 100 MB–1 GB per file; use **compaction jobs** to merge small files; and use **hidden partitioning** (Iceberg) so the query doesn't need to know the partition scheme.
4. **A columnar OLAP engine for interactive queries.** **ClickHouse** (self-managed, blistering fast, great compression, `MergeTree` with primary-key sparse indexes, materialised views for rollups — **the standard answer for high-cardinality event analytics**), or **BigQuery** (serverless, per-byte billing, no cluster to operate, BigLake over Iceberg), or **Snowflake/Redshift/Doris/StarRocks**. **Choice driver:** do you want to operate a cluster (ClickHouse: cheapest at scale, most control, real ops burden) or pay for serverless (BigQuery: zero ops, cost scales with query volume, **must control bytes scanned**)?
5. **Pre-aggregate aggressively.** Dashboards should never scan raw events. Build **rollups/materialised views** at minute/hour granularity for the known queries (ClickHouse materialised views, or a scheduled job writing aggregate tables). **This is where 90% of the cost saving is** — a dashboard query over a pre-aggregated table is milliseconds instead of minutes.
6. **Tiered retention driven by cost:**
   | Tier | Store | Retention | Cost |
   |---|---|---|---|
   | Hot | OLAP engine local/NVMe storage | 7–30 days | $$$ |
   | Warm | Object storage + query engine (Iceberg external tables) | 30–365 days | $$ |
   | Cold | Object storage archive class (Glacier Deep Archive / GCS Archive) | 1–7 years | $ |
   Lifecycle policies automate transitions; **verify the retrieval cost/time of the archive tier before you commit to it** (retrieving 86 TB from Deep Archive takes 12–48h and costs real money — fine for compliance, useless for an investigation).
7. **GDPR/erasure in an append-only lake — the hard requirement.** Options: **crypto-shredding** (encrypt each user's data with a per-user key, delete the key → data is unrecoverable and you keep the files intact), **Iceberg row-level deletes** (merge-on-read delete files, then compact), or a **partition-by-user-hash** scheme so erasure drops partitions. **Crypto-shredding is usually the pragmatic winner** for a 7-year archive because it's O(1) per request and doesn't require rewriting petabytes. **Name this problem — most candidates forget erasure in an archive design.**
8. **Idempotent, exactly-once-ish ingestion.** Producers retry → duplicates. Use an event ID and dedupe at write (Iceberg MERGE, ClickHouse `ReplacingMergeTree` with a version column and query-time `FINAL`/argMax), and **accept that "exactly once" means "effectively once after dedup"** (see [`03-System-Design-HLD`](../03-System-Design-HLD/README.md) on exactly-once).
9. **Backpressure and load shedding**: if consumers fall behind, Kafka buffers — but buffers fill. Decide the policy: drop lowest-priority events, sample, or scale. **Never let ingest fail silently.**
10. **Observability and cost governance**: lag per consumer group, ingest rate, file count and size distribution, compaction backlog, query cost per user/team, bytes scanned per query, storage by tier. **Cost alerts, because a `SELECT *` over an unpartitioned table can cost thousands of dollars in one query** — enforce partition filters, set per-query byte limits, and attribute cost per team.

**Scale arithmetic to show (interviewers like this):**
- 1M events/s × 1 KB = **1 GB/s** = **86 TB/day** raw.
- Parquet + compression (say 8×) → **~11 TB/day** stored → **~4 PB/year** → **~28 PB over 7 years** before tiering.
- At archive-class pricing (~$1/TB/month), 28 PB ≈ **$28k/month** for storage alone; the query engine and ingest compute will dominate.
- Kafka at 1 GB/s needs ~30–50 brokers with NVMe at RF=3 (3 GB/s of write throughput across the cluster) — **so the ingest tier is a real cluster, not a detail.**
- **Conclusion to state:** "The storage cost is manageable; the **compute and query cost is the design driver**, which is why pre-aggregation, partition pruning, and tiering matter far more than choosing a cheap storage class."

### 15. "You must add a column to a 2-billion-row table with zero downtime."
**The golden rule: never take an `ACCESS EXCLUSIVE` lock on a hot table, and never rewrite it.**

**Safe patterns by change type:**

| Change | Safe approach | Danger |
|---|---|---|
| **Add a nullable column, no default** | `ALTER TABLE t ADD COLUMN x int NULL;` — **metadata-only in Postgres and MySQL 8+, instant** | None (in modern versions) |
| **Add a column with a default** | **Postgres 11+**: `ADD COLUMN x int NOT NULL DEFAULT 0` is a **fast metadata-only operation** (the default is stored in the catalog, not written to every row). **MySQL 8.0.12+**: `ALGORITHM=INSTANT` for many cases. **Older versions rewrite the whole table** → hours of lock | Assuming all versions are fast — **check the version first** |
| **Add `NOT NULL` to an existing nullable column** | **Three steps**: (1) add a `CHECK (x IS NOT NULL) NOT VALID` — takes a brief lock, no scan; (2) `VALIDATE CONSTRAINT` — scans but takes only `SHARE UPDATE EXCLUSIVE`, doesn't block reads/writes; (3) `SET NOT NULL` — in Postgres 12+, this uses the validated check constraint and is fast | A single `SET NOT NULL` scans the table under a lock that blocks writes |
| **Add an index** | `CREATE INDEX CONCURRENTLY` (Postgres) / `ALGORITHM=INPLACE, LOCK=NONE` (MySQL 8) | Plain `CREATE INDEX` takes `SHARE` → **blocks all writes** for the duration. Note `CONCURRENTLY` **cannot run inside a transaction**, takes longer, and can leave an `INVALID` index if it fails (drop and retry) |
| **Rename a column** | Metadata-only, instant — **but breaks every query using the old name** | Not a lock problem, a **compatibility** problem: expand-contract (add new, dual-write, migrate, drop old) |
| **Change a column type** | Usually a **full table rewrite** under an exclusive lock → **never do this directly**. Instead: add a new column of the target type, dual-write, backfill in batches, switch reads, drop the old | The most dangerous "simple" change |
| **Drop a column** | Metadata-only (the data is reclaimed by vacuum) — **but old code selecting it breaks** | Expand-contract: stop reading it, deploy, then drop |
| **Add a foreign key** | `ADD CONSTRAINT ... NOT VALID` then `VALIDATE CONSTRAINT` | Direct add scans and locks |
| **Backfill data** | **Batched**: `UPDATE ... WHERE id BETWEEN ? AND ?` in chunks of 1k–10k, with sleeps, monitoring replication lag, and resumability | One giant `UPDATE` → a huge transaction, massive WAL, lock contention, **replica lag**, vacuum bloat, and an unrecoverable-if-it-fails operation |

**The process (this is the actual answer):**
```
1. Check the engine version and confirm which operations are metadata-only vs rewriting.
2. Set guardrails in the migration session:
      SET lock_timeout = '3s';          -- fail fast rather than queue behind a long query
      SET statement_timeout = '30s';
   Retry the DDL if it fails on lock_timeout (it's a normal outcome, not an error).
3. Run the DDL in a low-traffic window, monitoring: lock waits, replication lag, CPU, IOPS.
4. Expand → migrate → contract across MULTIPLE releases (never one):
      Release N:   add the new column/index (compatible with old code)
      Release N+1: deploy code that dual-writes and reads the new column
      Backfill job: batched, rate-limited, resumable, lag-aware, idempotent
      Release N+2: switch reads to the new column, verify parity
      Release N+3: drop dual-write and the old column (after a soak period)
5. Verify: row counts, parity checks, index validity (pg_index.indisvalid), query plans, replication lag caught up.
6. Have a rollback for each step, and know which steps are irreversible (a drop is).
```
**Additional production realities to mention:**
- **Run migrations as a separate, single-instance job** before the app rollout — never inside app startup with N replicas racing. Use advisory locks if it must be in-process, and make migrations **idempotent** (`IF NOT EXISTS`).
- **Tools**: `gh-ost` / `pt-online-schema-change` for MySQL (they build a shadow table, copy in chunks with triggers/binlog capture, and cut over atomically — the standard answer for MySQL type changes on huge tables); `pg_repack` for Postgres table rewrites/index rebuilds online; **Atlas / Skeema / sqldef** for declarative, reviewed schema change planning; **Flyway/Liquibase/Alembic** for versioned migrations.
- **Watch replication lag during backfills** — a backfill that saturates the primary's WAL generation can lag replicas by minutes, breaking read-your-writes and reporting. Throttle on lag.
- **Long-running transactions block vacuum** — a backfill in one giant transaction will bloat the table.
- **Disk space**: a shadow-table approach needs ~2× the table size; `CREATE INDEX CONCURRENTLY` needs space for the index. **Running out of disk mid-migration is a bad day.**
- **The 2-billion-row reality:** even "instant" DDL requires a brief exclusive lock to update the catalog, and **acquiring that lock means waiting for all in-flight queries on that table to finish** — so `lock_timeout` + retry is not optional, it's the whole trick.

**The framing:** "Zero-downtime schema change on a huge table is a sequence of small, individually-safe, reversible steps across several releases — expand, migrate, contract — plus two mechanical rules: never take a long exclusive lock (`lock_timeout` + retry, `CONCURRENTLY`, `NOT VALID` + `VALIDATE`), and never run one big transaction (batch, rate-limit, monitor lag). The failure mode I'm avoiding isn't the DDL itself; it's the DDL queuing behind a long read and blocking every query behind it."

### 16. "Design a globally distributed, strongly consistent counter (e.g. inventory or a like count)."
**This is a physics problem, so start by naming the constraint:** a strongly consistent global counter requires agreement between regions, and agreement costs a round trip (~70–150 ms inter-continent). **So the first question is: do you actually need global strong consistency, or do you need it *somewhere*?**

**The options, from most to least consistent:**

1. **Single-writer region (the pragmatic default).** All writes to one region's database (or one partition's leader); reads can be global from replicas if staleness is acceptable.
   - ✅ Simple, strongly consistent, no conflict resolution.
   - ❌ Write latency for distant users (~150 ms extra); **the writer region is an availability dependency** (failover = a promotion event with a data-loss window unless you use quorum replication).
   - Use when: correctness matters more than write latency (money, inventory), and writes are a minority of operations.

2. **Distributed consensus per key (Spanner/CockroachDB/YugabyteDB).** Each key's range has a Raft/Paxos group; writes need a majority.
   - ✅ Strong consistency with automatic failover and no single writer region.
   - ❌ Write latency = the consensus round trip within the group; **place the leader near the writers** (locality config) or you pay inter-region latency on every write. Cost and operational complexity.
   - Use when: you need SQL semantics + global strong consistency and can afford it.

3. **Sharded/partitioned counter (the scalability answer).** Split the counter into N independent sub-counters (e.g. 64 shards, each in a different region/partition), each accepting atomic local increments; **the total is the sum, read on demand**.
   - ✅ Writes are local and fast; scales linearly with N; no hot spot.
   - ❌ **The total is not strongly consistent at read time** — you get a value that's correct as of the reads you just did, and concurrent increments can be missed. It's "eventually consistent total with strongly consistent parts".
   - **This is exactly how Redis `INCR` sharding, DynamoDB write-sharded counters, and Google's counter designs work.** Use when: high write throughput and an *approximately* correct total is acceptable (like counts, view counts, rate-limit buckets).
   - **Critical detail:** for **inventory**, an approximate total is *not* acceptable (you oversell). So partition **by resource**, not by counter: allocate stock to regions (region A gets 100 units, region B gets 100), decrement locally, and **rebalance** when a region runs low. That converts a global counter into N local counters with an allocation protocol. **This is the real-world answer for global inventory.**

4. **CRDTs (conflict-free replicated data types)** — a **G-Counter** (grow-only, per-node counts, merge by max/sum) or **PN-Counter** (positive + negative G-Counters) gives multi-master writes with guaranteed convergence and no coordination.
   - ✅ No coordination, offline-tolerant, multi-active, mathematically convergent.
   - ❌ **Convergence is not linearisability**: a read may not reflect a concurrent write elsewhere; you can't do "check-then-decrement" atomically across replicas (so **you can oversell inventory** — a CRDT tells you the final count, it doesn't prevent going below zero). Metadata size grows with the number of nodes.
   - Use when: multi-active with eventual convergence is fine — analytics counters, presence, likes, telemetry aggregation, offline-first apps. **Redis CRDT / Riak / Automerge / Yjs are the implementations.**

5. **Lease/token-based single-writer with failover** — a coordinator (etcd/Consul/ZooKeeper) grants a lease to one writer; the lease has a TTL and fencing tokens prevent a stale writer from committing.
   - ✅ Strong consistency with fast local writes for the lease holder; controlled failover.
   - ❌ Lease expiry creates an availability gap; **fencing tokens are mandatory** (a paused writer whose lease expired must be rejected by the store — otherwise you get split-brain corruption). **Naming fencing tokens is the strong signal here.**

**The answer I'd give:**
> "First I'd separate **correctness** from **consistency latency**. For money or inventory, correctness is non-negotiable, so I'd use a **single logical writer with quorum replication** — a distributed-SQL database with the leader placed near the writers, or a single-primary region with semi-sync replication — and accept ~50–150 ms on writes while serving reads locally from replicas where staleness is tolerable.
> For a high-throughput counter where an exact instantaneous total isn't required (likes, views, metrics), I'd **shard the counter** and sum on read — writes stay local and it scales linearly.
> For **global inventory specifically**, the right design isn't a global counter at all: it's **regional allocation** — partition stock across regions, decrement locally with an atomic conditional update, and rebalance when a region is low or when demand shifts. That gives local write latency, no overselling, and graceful regional failure (a region can only oversell its own allocation).
> And whichever I choose, the implementation detail that prevents corruption is an **atomic conditional update** (`UPDATE ... SET qty = qty - 1 WHERE id = ? AND qty >= 1`, checking rows-affected) or a CAS with a version — **never read-check-write in application code**, and never without a fencing token if there's a lease involved."

---

## Red flags

| Saying / doing this | Costs you |
|---|---|
| "A replica is my backup" | `DROP TABLE` replicates instantly |
| Backups never restore-tested | Your RTO is a guess |
| Backups in the same account/region as the primary | A compromised account loses both |
| No `lock_timeout` before DDL | A 5-second migration takes down the service |
| `CREATE INDEX` (not CONCURRENTLY) on a hot table | Blocks all writes for the duration |
| One giant `UPDATE` for a backfill | Locks, WAL flood, replica lag, bloat, unrecoverable failure |
| Rename/type-change in a single release | Old code breaks during the rollout |
| Read-check-write for concurrent counters | Lost updates / overselling |
| 50 pods × 20 connections, no pooler | You took down your own database |
| PgBouncer transaction mode with prepared statements / session state | Silent breakage |
| `SELECT *` and `LIMIT/OFFSET` pagination on large tables | Slow scans; use keyset pagination |
| N+1 queries from an ORM | The #1 ORM performance bug |
| An index on a column wrapped in a function, without an expression index | Index not used |
| Long-running transactions in Postgres | Vacuum blocked → bloat → progressive slowdown |
| Never running `ANALYZE` after a bulk load | Wrong estimates → wrong plans |
| `EXPLAIN` without `ANALYZE`/`BUFFERS` | Estimates, not reality |
| Ignoring `pg_stat_statements` when the whole DB is slow | You're debugging one query while ten are the problem |
| Not handling deadlock/serialization-failure retries | A bug that surfaces only under load |
| Sharding on a timestamp or auto-increment ID | One hot shard forever |
| Assuming distributed SQL removes latency | Consensus costs a round trip; place the leader |
| Cassandra mass deletes without a tombstone plan | Query latency collapses |
| A CRDT for inventory | Converges, but oversells |
| Millions of tiny Parquet files | Metadata explosion; compact them |
| No partition filters / byte-scan limits on a lakehouse | A $5,000 query |
| Forgetting GDPR erasure in a 7-year archive | Use crypto-shredding |
| Choosing a database because it's fashionable | You'll pay in operational complexity |

## Rapid recall

1. **Default to Postgres** (relational + `jsonb` + PostGIS + Timescale + pgvector + `SKIP LOCKED` queues); move only on a **measured** requirement.
2. **B+tree**: in-place writes, predictable reads, range-friendly; clustered index = physical order (so keep PKs small in MySQL). **LSM**: sequential writes, memtable → SSTables, bloom filters, **compaction** — write-optimised, read-amplified.
3. Indexes: btree (default), **GIN** (jsonb/array/tsvector), **GiST** (geo/KNN), **BRIN** (huge time-correlated tables), **partial**, **expression**, **covering (INCLUDE)**. Composite: leftmost prefix; **equality columns first, range last**. Unused indexes are pure cost.
4. **ACID + isolation levels**; anomalies: dirty / non-repeatable / **phantom** / **write skew** (SI does *not* prevent it — Postgres `SERIALIZABLE`/SSI does) / lost update.
5. **MVCC**: readers don't block writers; old versions in the heap (Postgres) → **autovacuum**; **long transactions hold back xmin → bloat → progressive slowdown**.
6. Replication: single-primary async (**RPO > 0**), semi-sync (**RPO ≈ 0**), quorum/Raft (RPO = 0, automatic failover), multi-primary (**conflicts**). **Lag is unbounded**; fix read-your-writes with primary reads, LSN/GTID waits, or sticky sessions. **Monitor lag.**
7. Sharding breaks: joins, transactions, aggregations, resharding, hot shards, global uniqueness. Shard key = **high cardinality, even, stable, in most queries**. Distributed SQL when you'd otherwise hand-roll it.
8. **Connection pooling**: Postgres connections are processes; total across instances ≈ 2–4× DB cores; **PgBouncer transaction mode** for multiplexing — but **no prepared statements, no session state (`SET`, advisory locks, LISTEN/NOTIFY, temp tables)**. Connection storms need jitter; set idle-in-transaction timeouts.
9. Slow query: `EXPLAIN (ANALYZE, BUFFERS)` + **compare estimated vs actual rows** (stale stats); `pg_stat_statements` for DB-wide; wait events to classify (Lock / IO / CPU / Client).
10. Top causes: missing/unusable index, stale statistics, **N+1**, `SELECT *`, **large OFFSET** (→ keyset pagination), lock contention (**DDL queued behind a long read**), bloat, resource saturation, cache eviction, **a failed cache making the DB look slow**.
11. Locks: `ACCESS EXCLUSIVE` conflicts with everything; **`SET lock_timeout` + retry before DDL**; consistent lock ordering to avoid deadlocks; **retry `40001`/`40P01`**; optimistic version columns for low contention.
12. Backups: logical vs physical + **WAL/binlog archiving = PITR**; **3-2-1 + immutable + cross-account/region**; **restore drills with measured RTO**; keep migration/schema versions alongside.
13. Distributed SQL: **Spanner TrueTime** (commit waits out clock uncertainty → external consistency) vs **Cockroach/Yugabyte HLC** (serializable, no commit wait). Cassandra: gossip, hinted handoff, read repair, tunable quorum, **tombstones**. Cross-region strong writes pay a consensus round trip → **place the leader**.
14. 1M events/s: Kafka buffer → **Parquet + Iceberg in object storage** (open format = engine independence) → **ClickHouse/BigQuery** for interactive → **pre-aggregated rollups for dashboards** → tiered retention (hot/warm/archive). Partition by time (+ a second dimension), target 100 MB–1 GB files, **compact small files**, dedupe by event ID, **crypto-shredding for erasure**, and control **bytes scanned** (cost).
15. Zero-downtime schema change: **expand → migrate → contract across multiple releases**; metadata-only DDL where the version allows; `CREATE INDEX CONCURRENTLY`; `NOT VALID` + `VALIDATE CONSTRAINT`; `gh-ost`/`pt-osc` for MySQL rewrites; `pg_repack` for Postgres; **batched, lag-aware, resumable backfills**; migrations as a single-instance idempotent job, never in app startup.
16. Global counter: single-writer region or quorum consensus for correctness; **shard + sum** for throughput; **regional stock allocation** for global inventory; **CRDT (PN-Counter)** only where convergence beats linearisability; **atomic conditional update or CAS, plus fencing tokens with any lease**.

→ Next: [`17-Networking-and-Service-Mesh`](../17-Networking-and-Service-Mesh/README.md)
