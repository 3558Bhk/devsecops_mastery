# SDE3 One-Pager Cheatsheets - Last Minute Revision

## 1. System Design 6 Steps (Write on board first)

1. Requirements (Functional + Non-functional)
2. Estimation (QPS, storage, bandwidth)
3. HLD (Client -> CDN -> LB -> API Gateway -> Services -> Cache -> DB -> Queue)
4. Deep Dive (DB schema, sharding, caching, APIs)
5. Bottlenecks & Tradeoffs (CAP, consistency, SPOF)
6. Monitoring (Metrics, logs, traces, alerting)

## 2. API Decision

- Public CRUD simple -> REST
- Flexible frontend needs -> GraphQL
- Internal microservices high perf -> gRPC
- Legacy bank -> SOAP

## 3. DB Decision

- ACID transactions -> PostgreSQL
- Flexible schema catalog -> MongoDB
- Cache/session/leaderboard -> Redis
- High write time-series -> Cassandra
- Search -> Elasticsearch
- Relationships -> Neo4j
- AI vector search -> Pinecone/Qdrant

## 4. Cache Patterns

- Cache-Aside: App checks cache, if miss loads DB and puts cache (most common)
- Write-Through: Write cache + DB sync, consistent but slow
- Write-Behind: Write cache async to DB, fast but risk loss
- Eviction: LRU most common
- Problems: Stampede (lock + early refresh), Penetration (cache null + Bloom), Avalanche (TTL + jitter)

## 5. Messaging

- Need routing low latency -> RabbitMQ
- Need high throughput replay streaming -> Kafka
- AWS simple no ops -> SQS/SNS
- Ensure exactly-once via idempotent consumer (messageId dedup table)

## 6. Consistency

- Strong: Read after write sees write (CP)
- Eventual: Will be consistent after time (AP)
- Solutions for eventual: Read-your-writes (read from primary for critical), versioning, SAGA compensating

## 7. Scaling

- Stateless + horizontal + LB + auto scaling HPA
- DB: Read replicas for read heavy, sharding for write heavy, caching 80%
- Async via queue for heavy tasks
- CDN for static

## 8. CAP & PACELC

- CAP: In partition choose A or C
- PACELC: If P choose A/C else choose L/C
- CP: Mongo primary, HBase, Zookeeper
- AP: Cassandra, DynamoDB
- CA: Single node (not distributed)

## 9. Jenkins Ports & Common Ports

- Jenkins 8080 web, 50000 agent
- MySQL 3306, PG 5432, Mongo 27017, Redis 6379, Kafka 9092, ZK 2181, ES 9200, HTTP 80, HTTPS 443, SSH 22

## 10. Status Codes Must Memorize

- 200 OK, 201 Created, 204 No Content
- 301 Permanent redirect, 302 Temporary, 304 Not Modified
- 400 Bad Request, 401 Unauthorized, 403 Forbidden, 404 Not Found, 409 Conflict, 429 Too Many
- 500 Internal, 502 Bad Gateway (upstream bad response), 503 Unavailable (overload), 504 Timeout (upstream timeout)

## 11. SOLID One Line

- S: One responsibility
- O: Open extension closed modification
- L: Subtype substitutable for parent
- I: No fat interface, split
- D: Depend on abstraction not concrete

## 12. Design Patterns Top 8

- Singleton: One instance
- Factory: Create without exposing logic
- Builder: Complex object step by step
- Adapter: Convert interface
- Decorator: Add behavior dynamically wrapping
- Proxy: Control access (lazy, logging)
- Observer: One-to-many notify (pub/sub)
- Strategy: Family of algorithms interchangeable

## 13. K8s Debugging

- ImagePullBackOff: Wrong image/tag or private registry no secret
- CrashLoopBackOff: App crash on start, logs --previous
- OOMKilled: Memory limit low, increase or fix leak
- Pending: No resources or PVC not bound
- Liveness fail: App hung restart, Readiness fail: Not ready remove from LB

## 14. Rate Limiter Algorithms

- Fixed Window: Simple counter per window, burst at boundary
- Sliding Log: Store timestamps accurate but memory heavy
- Sliding Counter: Hybrid 2 windows weighted, balanced
- Token Bucket: Allows burst up to capacity, refill rate
- Leaky Bucket: Smooth fixed rate no burst

## 15. SRE

- SLI: Measurement (99.96% uptime)
- SLO: Target (99.95%)
- SLA: Contract (99.9% with penalty)
- Error Budget = 100% - SLO, if exhausted freeze features
- MTTR low good, MTBF high good
- Toil <50%

## 16. Git Workflows

- GitFlow: Complex many branches for scheduled releases
- GitHub Flow: Main + feature PR -> deploy, simple
- Trunk Based: Main + very short branches <2 days + feature flags, elite teams

## 17. Java Versions Story (4 YOE)

- Started Java 8/11 (streams, var), Spring Boot 2.5-2.7
- Migrated to Java 17 LTS (records, pattern matching), Spring Boot 3.x (jakarta namespace)
- Now exploring Java 21 virtual threads, Spring Boot 3.2+ virtual threads enabled
- Node 16->20, React 17->18, K8s 1.24->1.30, Jenkins 2.387->2.479 requiring Java 17

## 18. Observability

- Metrics: Prometheus + Grafana, RED (Rate Errors Duration), USE (Utilization Saturation Errors)
- Logs: ELK/EFK/PLG, structured JSON, correlation ID
- Traces: OpenTelemetry + Jaeger, traceId across services
- Profiling: Pyroscope, JFR

## 19. Security Checklist

- HTTPS/TLS, JWT short lived 15min + refresh rotation HttpOnly, OAuth2 Auth Code + PKCE, RBAC, input validation, prepared statements (no SQL injection), output encoding (no XSS), CSRF token, rate limiting, security headers (HSTS, CSP), no secrets in code (Vault), bcrypt for passwords

## 20. Performance Quick Wins

- Add index, fix N+1, add Redis cache 80% hit, pagination, compression gzip, CDN, HTTP/2, connection pooling, async via queue, batching

## 21. Behavioral STAR

- Situation Task Action Result, quantify: Reduced latency 70%, saved $50k, handled 10k RPS, mentored 3 juniors

## 22. Load Balancing Algorithms

- Round Robin, Weighted RR, Least Connections, IP Hash, Consistent Hashing (minimal rehash when node added)

## 23. Consistent Hashing

- Normal hash % N -> when N changes most keys remap -> storm. Consistent hashing ring -> only K/N keys remap, use virtual nodes to balance.

## 24. How to Answer "Design X" in 35 min

- 5 min requirements + estimation
- 10 min HLD diagram
- 15 min deep dive (DB, cache, queue, API)
- 5 min bottlenecks + monitoring + tradeoffs

## 25. Final Night Before Interview

- Read this cheatsheet 3 times
- Practice 2 HLDs aloud (URL shortener + Notification)
- Practice 1 LLD (Parking Lot or LRU)
- Review your project architecture end-to-end with numbers
- Sleep well, interview is conversation not interrogation
