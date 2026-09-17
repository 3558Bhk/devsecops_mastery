# SQL vs NoSQL Deep + Indexing + Transactions

## ACID vs BASE

### ACID (SQL)
- **Atomicity**: All or nothing (transaction)
- **Consistency**: DB from one valid state to another, constraints
- **Isolation**: Concurrent transactions don't interfere (levels: Read Uncommitted, Read Committed, Repeatable Read, Serializable)
- **Durability**: Committed data survives crash (WAL)

### BASE (NoSQL)
- **Basically Available**: System available despite failures
- **Soft state**: State may change without input (eventual consistency)
- **Eventually consistent**: Will be consistent given time, no guarantees immediate

## Isolation Levels (Important)

| Level | Dirty Read | Non-Repeatable Read | Phantom Read | Use |
|-------|------------|---------------------|--------------|-----|
| Read Uncommitted | Yes | Yes | Yes | Rare, fast but dirty |
| Read Committed | No | Yes | Yes | Default PG, Oracle |
| Repeatable Read | No | No | Yes | Default MySQL InnoDB |
| Serializable | No | No | No | Strict, locking, slow |

- **Dirty Read**: Read uncommitted change that later rollback
- **Non-Repeatable**: Same row read twice gets different values due to update
- **Phantom**: Same query twice gets different rows due to insert/delete

## Indexing Deep

### Types
- **Primary**: Clustered (data sorted by PK), one per table
- **Secondary**: Non-clustered, separate structure pointing to row
- **Composite**: (col1, col2) order matters! Query must use leftmost prefix
- **Unique**: No duplicates
- **Full-text**: For text search
- **Partial**: Index on subset `WHERE status='active'`

### B-Tree Index (Default)
- Balanced tree, O(log n) lookup, supports range queries (<, >, ORDER BY)
- Good for: Equality, range

### Hash Index
- O(1) equality only, no range
- Use: Memory tables, exact match

### How Index Works?
Without index: Full table scan O(n)
With index: B-tree search O(log n) + few disk I/Os

### When Index Not Used?
- Function on column: `WHERE YEAR(created_at)=2024` -> use `WHERE created_at >= '2024-01-01'`
- Leading wildcard: `LIKE '%abc'` no index, `LIKE 'abc%'` uses index
- OR condition without index on both
- Small table full scan faster

### EXPLAIN
```sql
EXPLAIN ANALYZE SELECT * FROM users WHERE email = 'a@b.com';
-- Check: Seq Scan vs Index Scan, cost, rows
```

### Write Amplification
- Each index slows INSERT/UPDATE/DELETE because index also updated

## Transactions

```sql
BEGIN;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
COMMIT; -- or ROLLBACK
```

### Distributed Transactions
- **2PC**: Two Phase Commit - coordinator asks prepare, then commit. Blocking, not fault tolerant.
- **3PC**: Non-blocking but more messages
- **SAGA**: Preferred in microservices (compensating transactions)

## N+1 Problem
```js
// Bad: 1 query for users + N queries for posts
users = db.query("SELECT * FROM users");
for (user in users) {
  posts = db.query("SELECT * FROM posts WHERE user_id = ?", user.id); // N queries
}

// Good: 1 join or 2 queries
users = db.query("SELECT * FROM users");
posts = db.query("SELECT * FROM posts WHERE user_id IN (?)", userIds); // group
// Or JOIN
```

Solution: DataLoader, eager loading, JOIN

## Connection Pooling
- Don't create new DB connection per request (expensive TCP + auth)
- Pool: HikariCP (Java best), PgBouncer for PG, built-in for Node
- Size: (core_count * 2) + effective_spindle_count (formula)

## Caching Strategies with DB
1. Cache-Aside (app manages)
2. Read-Through (cache loads from DB)
3. Write-Through (write to cache then DB sync)
4. Write-Behind (write to cache, async to DB)

## Polyglot Persistence (SDE3 Term)
- Use multiple DB types in same app, each for its strength
- Example: PG for transactional, Redis for cache, ES for search, S3 for blobs

## Interview Q: How to choose shard key?
- High cardinality, evenly distributed, query pattern includes shard key
- Bad: timestamp (hot shard for latest), low cardinality like gender
- Good: user_id, tenant_id

## Backup & Recovery
- Full + incremental + WAL archiving
- Point in Time Recovery (PITR)
- Test restores regularly
