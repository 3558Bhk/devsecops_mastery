# Caching Strategies - SDE3 Must Know

## Why Cache?
- Reduce latency (ms vs 100ms DB)
- Reduce DB load
- Reduce cost
- Improve throughput

## Where to Cache?

### 1. Browser Cache
- Cache-Control header: `max-age=3600, public`
- ETag, Last-Modified -> 304 Not Modified
- Service Worker cache API

### 2. CDN Cache
- CloudFront, Cloudflare caches static assets at edge near user
- TTL, invalidation

### 3. Reverse Proxy / API Gateway Cache
- Nginx `proxy_cache`, API Gateway caching
- Cache entire responses

### 4. Application Cache (Local)
- In-memory: Guava, Caffeine (Java), Node-cache
- Fastest but per instance, not shared, memory limited
- Use for config, small reference data

### 5. Distributed Cache (Remote)
- Redis, Memcached shared across instances
- Most common for SDE3
- Use for sessions, DB query results, API responses

### 6. Database Cache
- DB query cache (MySQL QC deprecated), buffer pool, PG shared_buffers
- Materialized views

## Caching Patterns

### Cache-Aside (Lazy Loading) - Most Used
```
App -> Check cache
If hit -> return
If miss -> Load from DB -> Put in cache -> Return
```
- Pros: Only requested data cached, cache failures don't break DB
- Cons: Cache miss penalty (3 trips), stale data
- Use: General purpose

### Read-Through
- App asks cache, cache loads from DB if miss (cache provider does DB call)
- App doesn't know DB
- Similar to cache-aside but logic in cache layer

### Write-Through
```
App writes to cache -> Cache writes to DB synchronously -> Success
```
- Pros: Cache always consistent with DB
- Cons: Write latency high (2 writes), cache may have unused data
- Use: When consistency important, read heavy

### Write-Behind (Write-Back)
```
App writes to cache -> Cache ack immediately -> Cache async writes to DB later
```
- Pros: Very fast writes
- Cons: Risk data loss if cache crashes before DB write, complex
- Use: Write heavy, can tolerate small loss (e.g. logs, analytics)

### Write-Around
- Write directly to DB, bypass cache (cache only on read)
- Avoids cache pollution with write-once data

## Eviction Policies

- **LRU**: Least Recently Used - evict oldest not used (most common)
- **LFU**: Least Frequently Used - evict least accessed
- **FIFO**: First In First Out
- **TTL**: Time To Live - expire after time (e.g. 5 min)
- **Random**

Redis supports: allkeys-lru, volatile-lru (only keys with expire), allkeys-lfu, etc.

## Cache Invalidation - Hardest Problem

Strategies:
1. **TTL**: Expire after time, simple but stale till expiry
2. **Event-based**: On DB update, publish event to invalidate/delete cache key
3. **Write-through**: Keeps consistent but slower
4. **Versioning**: Key includes version `user:123:v2`, new version new key
5. **Manual**: Admin invalidation API

### Cache Stampede / Thundering Herd
- Many requests miss cache same time, all hit DB -> DB overload
- Solutions:
  - Lock: Only first request loads DB, others wait
  - Early recomputation: Refresh before expiry
  - Request coalescing / single flight (Go)
  - Add jitter to TTL so not all expire same time

### Cache Penetration
- Query for non-existent data (e.g. user id -1) -> always miss -> hits DB
- Solutions:
  - Cache null/empty with short TTL (e.g. 1 min)
  - Bloom Filter: Check existence before DB
  - Validate input

### Cache Avalanche
- Many keys expire at same time -> DB spike
- Solutions:
  - TTL + random jitter (e.g. 5 min + random 0-60 sec)
  - Multi-level cache
  - Circuit breaker

## Redis vs Memcached

| Feature | Redis | Memcached |
|---------|-------|-----------|
| Data types | String, List, Set, Sorted Set, Hash, Stream, etc | String only |
| Persistence | Yes RDB/AOF | No |
| Replication | Yes | No |
| Multi-thread | Single thread IO (6 multi-thread IO) | Multi-thread |
| Use | Cache + DB + Queue + Leaderboard | Simple cache |
| Memory | More overhead | Less overhead, slab allocator |

## Redis Data Structures Use Cases
- **String**: Cache, counters `INCR`
- **Hash**: User profile `HSET user:123 name John`
- **List**: Queue, recent items `LPUSH`, `LRANGE`
- **Set**: Unique visitors, tags `SADD`, `SISMEMBER`
- **Sorted Set**: Leaderboard, ranking `ZADD leaderboard 100 user1`
- **Bitmap, HyperLogLog**: Analytics approximate unique counts

## Caching Best Practices SDE3
- Cache only idempotent GETs, not POST
- Use meaningful keys: `service:entity:id:version` e.g. `user-service:user:123`
- Compress large values
- Set max memory + eviction policy in Redis: `maxmemory 2gb`, `maxmemory-policy allkeys-lru`
- Monitor hit ratio: `hits/(hits+misses)` should be >80% ideally
- Don't cache too large (1MB+), use pagination
- Local cache + distributed cache multi-level: Caffeine L1 + Redis L2

## Interview Q: How to design cache for product catalog?
- Product detail: Cache-Aside with TTL 5 min + event invalidation on product update via Kafka
- Key: `product:{id}`, value JSON
- Redis cluster, 3 replicas
- Hit ratio monitoring, if miss storm use lock
- Bloom filter for non-existent products to prevent penetration
- CDN for product images

## Tools Commands
```bash
redis-cli
SET user:123 '{"name":"John"}' EX 300
GET user:123
DEL user:123
TTL user:123
INFO stats # hit/miss
```
