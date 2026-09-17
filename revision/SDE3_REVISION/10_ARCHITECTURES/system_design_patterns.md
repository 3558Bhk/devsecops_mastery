# System Design Patterns - SDE3 Must Know

## Creational Patterns (Not main but asked)
- Singleton, Factory, Builder, Prototype

## Structural
- Adapter, Decorator, Proxy, Facade

## Behavioral
- Observer, Strategy, Chain of Responsibility

## Distributed System Patterns (Important for SDE3)

### 1. API Gateway
- Single entry, routing, auth, rate limiting, aggregation
- Tools: Kong, AWS API Gateway, Zuul, Spring Cloud Gateway

### 2. Service Discovery
- Client side (Netflix Eureka) vs Server side (AWS ALB)
- Services register, discover dynamically
- K8s uses CoreDNS

### 3. Circuit Breaker
- Prevent cascade failure
- States: Closed (normal), Open (fail fast), Half-Open (try)
- Tools: Resilience4j, Hysteria (Go), Istio
```java
@CircuitBreaker(name = "payment", fallbackMethod = "fallback")
public String callPayment() { ... }
```

### 4. Retry + Exponential Backoff + Jitter
- Retry 3 times with delays 100ms, 200ms, 400ms + random jitter to avoid thundering herd

### 5. Bulkhead
- Isolate failures (separate thread pools for services)
- Like ship compartments

### 6. CQRS - Command Query Responsibility Segregation
- Separate read and write models
- Write: Normalized DB, Read: Denormalized optimized view (e.g. Elasticsearch)
- Use: Read heavy with complex queries

### 7. Event Sourcing
- Store events not current state. State derived by replaying events.
- Pros: Audit log, time travel
- Cons: Complexity, eventual consistency
- Use: Banking ledger

### 8. SAGA Pattern
- For distributed transactions
- Choreography: Each service publishes event triggers next
- Orchestration: Central orchestrator tells each service what to do
- Compensating transaction for rollback

### 9. Sidecar
- Helper container alongside main (logging, proxy, monitoring)
- Example: Istio Envoy sidecar, Fluentd sidecar for logs

### 10. Strangler Fig
- Gradually replace old system

### 11. Backend for Frontend (BFF)
- Separate backend per frontend (Web BFF returns more data, Mobile BFF less)
- Solves over-fetching

### 12. Cache-Aside (Lazy Loading)
- App checks cache, if miss loads from DB and populates cache
- Most common

### 13. Write-Through / Write-Behind
- Write-Through: Write to cache and DB synchronously
- Write-Behind: Write to cache then async to DB (fast but risk data loss)

### 14. Outbox Pattern
- To ensure reliable event publishing with DB transaction
- Write event to outbox table in same transaction as business data, then separate process publishes event from outbox to Kafka

## Scalability Patterns
- **Sharding**: Split DB by key (user_id % N)
- **Replication**: Master-Slave, Master-Master
- **Consistent Hashing**: For distributed cache, minimal rehash when node added
- **Load Balancing**: As earlier

## Data Patterns
- **Database per Service**: Each microservice own DB
- **Shared Database**: Anti-pattern for microservices but sometimes used for transition
- **Materialized View**: Precomputed view

## Interview System Design Steps (Use for any design question)
1. Requirements: Functional + Non-Functional (scale, latency, availability)
2. Estimation: QPS, storage, bandwidth (e.g. 1M DAU, avg 10 req/user/day = ~115 QPS peak 10x = 1150)
3. High Level Design: Client -> CDN -> LB -> API Gateway -> Services -> DB/Cache/Queue
4. Deep Dive: DB schema, API design, caching, partitioning, replication
5. Bottlenecks & Tradeoffs: CAP, consistency, failure scenarios
6. Monitoring, logging, alerting

## Example: Design URL Shortener
- Req: Shorten long URL, redirect, custom alias, expiry, analytics
- Est: 100M URLs/month, 100:1 read:write, 100 bytes per URL -> 10GB/month storage
- HLD: Client -> API Gateway -> Write Service -> DB (Cassandra/ DynamoDB) + Cache (Redis) + Base62 encoder + Read Service
- DB: short_code PK, long_url, created_at, user_id, expiry
- Cache: short_code -> long_url 80% hit
- Hash: Base62 of auto-increment ID or hash of long URL + collision check
- Scale: Consistent hashing for DB sharding by short_code
