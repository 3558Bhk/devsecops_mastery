# Performance Tuning - SDE3

## Performance Metrics Recap
- Latency: P50, P95, P99
- Throughput: QPS/TPS
- Utilization: CPU, memory, disk, network
- Saturation: Queue length
- Errors: Error rate

## Where is Bottleneck? (Methodical)

1. **Measure**: Don't guess, profile
   - APM: Datadog, New Relic, AppDynamics
   - Logs: Slow query log, GC log
   - Metrics: CPU high? Memory high? Disk IO wait? Network?
   - Tracing: Which span slow?

2. **Common Bottlenecks**:
   - CPU: Complex computation, inefficient algorithm O(n^2), too many threads context switching
   - Memory: Leak, large heap causing GC pauses, OOM
   - Disk: Slow queries, no index, too much logging, not enough IOPS
   - Network: Chatty API (N+1), large payloads, no compression, no keep-alive
   - Lock Contention: Synchronized blocks, DB locks, thread pool exhausted

## Application Level Tuning

### Java

- **JVM Tuning**:
  - Heap size: -Xms = -Xmx to avoid resizing pauses, set to 50-70% of container memory (leave for off-heap)
  - GC: Use G1 for balanced, ZGC for low latency, tune MaxGCPauseMillis
  - Thread pool: Right size, CPU-bound N+1, IO-bound 2N or virtual threads
  - Use async-profiler to find hot methods

- **Code**:
  - Avoid N+1 queries (use JOIN FETCH, batch)
  - Use caching (Redis) for repeated DB queries
  - Use pagination not `SELECT *` large table
  - Use StringBuilder for concatenation in loop
  - Avoid boxing/unboxing in hot path
  - Use primitive collections if needed
  - Reuse objects via object pool for expensive objects (but careful)
  - Use appropriate data structure: HashMap O(1) vs TreeMap O(log n) vs List O(n) search

- **Spring Boot**:
  - Lazy init `spring.main.lazy-initialization=true` for faster startup (but first request slower)
  - Exclude unnecessary auto-config
  - Use @Async for non-critical tasks
  - Connection pool: HikariCP size = (core_count*2)+effective_spindle_count, default 10 often enough, monitor active connections

### Node.js

- **Event Loop**: Don't block event loop with sync CPU heavy task, offload to worker threads or child process
- **Clustering**: Use PM2 or cluster module to use all CPU cores (Node single threaded)
- **Caching**: In-memory or Redis
- **Compression**: gzip/br via `compression` middleware
- **Keep-Alive**: HTTP agent keep-alive
- **Streaming**: Stream large files not buffer

### Database Tuning

- **Indexing**: Add index for WHERE, JOIN, ORDER BY, but not too many (slows write)
  - Composite index order matters: Equality first, then range, then sort
  - Covering index: Index includes all columns needed, avoids table lookup
  - EXPLAIN ANALYZE to check index usage
- **Query Optimization**:
  - Avoid SELECT *, select only needed columns
  - Avoid function on indexed column `WHERE YEAR(date)=2023` -> `WHERE date >= '2023-01-01'`
  - Avoid leading wildcard LIKE '%abc' no index, use full-text search or trigram
  - Use JOIN instead of subquery often faster
  - Batch inserts: Insert 1000 rows at once not 1000 separate inserts
  - Pagination: OFFSET large is slow (scans and discards), use keyset pagination `WHERE id > lastId LIMIT 20`
- **Connection Pooling**: PgBouncer for PG, ProxySQL for MySQL
- **Read Replicas**: Offload reads to replicas
- **Partitioning/Sharding**: For large tables
- **Vacuum/Analyze**: PG needs vacuum to reclaim dead tuples, auto-vacuum tune

### Caching Tuning

- Hit ratio >80% good, monitor via Redis INFO
- Eviction policy: allkeys-lru for cache, volatile-lru if some keys persistent
- TTL + jitter to avoid avalanche
- Multi-level: Local Caffeine L1 + Redis L2
- Cache warming on startup

### Network Tuning

- **HTTP/2 or HTTP/3**: Multiplexing, header compression, faster
- **Keep-Alive**: Reuse TCP connections, reduce handshake
- **Compression**: gzip/br for JSON, images already compressed
- **CDN**: For static assets
- **Connection Pooling**: For HTTP clients (e.g. RestTemplate with PoolingHttpClientConnectionManager)
- **Batching**: Instead of 100 API calls, batch into 1 call with 100 items
- **Pagination**: Limit response size

### Frontend Performance

- **Bundle Size**: Code splitting, lazy loading, tree shaking, remove unused deps
- **Images**: WebP, lazy loading, responsive images srcset, compress
- **Caching**: Browser cache, service worker
- **CDN**: Static assets
- **Minify**: JS/CSS
- **Critical Rendering Path**: Inline critical CSS, defer non-critical JS
- **Lighthouse Score**: Aim >90

## Infrastructure Tuning

### Linux

```bash
# Check bottleneck
top # CPU
free -h # memory
iostat -x 1 # disk IO
vmstat 1 # CPU, memory, IO
sar -u 1 # CPU history
netstat -tulpn # connections
ss -s # socket stats
dmesg # kernel messages OOM killer

# Tune
ulimit -n 65535 # increase open files
sysctl -w net.core.somaxconn=4096 # socket backlog
sysctl -w vm.swappiness=10 # less swapping
```

### Docker/K8s

- Set resource requests/limits: requests for scheduling, limits for max, if no limits one pod can starve others
- Use HPA based on CPU/memory/custom metrics (QPS)
- Use VPA for right sizing
- Use node affinity to spread pods across AZs
- Use PDB (Pod Disruption Budget) to ensure minimum available during voluntary disruption

## Load Testing

- Tools: k6 (modern JS), JMeter (old but powerful), Gatling (Scala), Locust (Python), Artillery
- Types: Load (expected), Stress (beyond), Soak (long duration), Spike (sudden)
- Example k6:
```js
import http from 'k6/http';
import { sleep } from 'k6';
export const options = {
  stages: [
    { duration: '1m', target: 100 }, // ramp up to 100 users
    { duration: '3m', target: 100 }, // stay 100
    { duration: '1m', target: 0 }, // ramp down
  ],
  thresholds: {
    http_req_failed: ['rate<0.01'], // error rate <1%
    http_req_duration: ['p(95)<200'], // P95 <200ms
  },
};
export default function() {
  http.get('https://api.example.com/users');
  sleep(1);
}
```

## Performance Checklist for SDE3

- [ ] Caching at multiple levels?
- [ ] DB indexes for queries?
- [ ] N+1 fixed?
- [ ] Pagination?
- [ ] Connection pooling configured?
- [ ] Async for heavy tasks via queue?
- [ ] Compression enabled?
- [ ] CDN for static?
- [ ] HTTP/2?
- [ ] Monitoring P95 latency and error rate?
- [ ] Load tested before prod?
- [ ] Right sized thread pools and DB pools?
- [ ] GC tuned?
- [ ] No blocking calls in event loop (Node) or synchronized hot path (Java)?

## Interview Q: How to optimize slow API P95 2 sec to 200ms?

- Trace: Find slow span - DB query 1.5 sec
- DB: EXPLAIN - missing index, full table scan, add composite index -> 100ms
- Still 500ms: N+1 query, 10 queries sequential, fix to 1 JOIN -> 150ms
- Add Redis cache for user data 80% hit -> 50ms for cached
- Enable HTTP keep-alive and connection pooling -> reduce connection overhead
- Add pagination limit 20 not 1000
- Compress response gzip
- Result: P95 200ms, P99 400ms

Show systematic approach not random guessing.
