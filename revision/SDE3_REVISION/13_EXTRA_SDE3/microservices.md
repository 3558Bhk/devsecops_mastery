# Microservices Extra - SDE3 Deep

## Characteristics
- Single responsibility per service
- Own DB (Database per service)
- Independent deployment
- Decentralized (each team owns)
- Communication: Sync (REST/gRPC) + Async (events)

## Decomposition Strategies (DDD)
- **By Business Capability**: User management, Order management
- **By Subdomain**: DDD bounded contexts
- **By Transactions**: Avoid distributed transactions where possible

## Communication

### Synchronous
- REST: Simple, human readable, but blocking
- gRPC: Fast, binary, streaming, contract-first - preferred internal
- GraphQL: Aggregation layer

Problems with sync:
- Temporal coupling (both must be up)
- Latency accumulates
- Cascade failure

Mitigation: Circuit breaker, timeout, retry, bulkhead

### Asynchronous
- Message Broker: RabbitMQ, Kafka, SQS, SNS
- Event-driven: Loose coupling, resilient, scalable
- Patterns: Pub/Sub, Event Sourcing

## Data Management

### Database per Service
- Pros: Loose coupling, choose DB per need, independent scale
- Cons: Cross-service queries hard, distributed transactions

### SAGA Pattern for Transactions
- **Choreography**: Each service listens event and does its part, publishes next event. No central coordinator. Simple but hard to track.
- **Orchestration**: Orchestrator service tells each participant what to do, tracks state. More complex but visible.

Example Order SAGA:
1. Order Service creates PENDING order, publishes OrderCreated
2. Payment Service listens, charges, publishes PaymentCompleted
3. Inventory Service listens, reserves, publishes InventoryReserved
4. Order Service listens, marks CONFIRMED
If any fails, compensating transactions: Payment refund, Inventory release, Order CANCELLED

### CQRS
- Command (write) model separate from Query (read) model
- Write to PG normalized, read from ES denormalized materialized view
- Sync via events (CDC - Change Data Capture with Debezium)

### Event Sourcing + Outbox
- Store events not state, rebuild state by replay
- Outbox pattern ensures event published atomically with DB transaction

## Cross-Cutting Concerns

### API Gateway
- Routing, auth, rate limiting, aggregation, SSL termination
- BFF pattern: Different gateways for web/mobile

### Service Discovery
- Client side: Eureka, Consul client
- Server side: K8s Service, AWS ALB
- DNS: CoreDNS in K8s

### Config Management
- Centralized config: Spring Cloud Config, Consul, AWS Parameter Store
- 12-factor: Config in env, not code
- Feature flags: LaunchDarkly, Unleash

### Distributed Tracing
- RequestId passed via headers (X-Request-ID, X-Correlation-ID)
- TraceId, SpanId
- Tools: OpenTelemetry + Jaeger/Zipkin/X-Ray
- Log aggregation with traceId

### Centralized Logging
- ELK/EFK/PLG stack, Fluentd/Fluent Bit sidecar collects logs to Elasticsearch/Loki

## Resilience Patterns (Recap)
- Circuit Breaker, Retry, Timeout, Bulkhead, Fallback, Hedging (send same request to multiple instances take first)

## Deployment Patterns
- **Blue-Green**: Two envs blue (old) green (new), switch router, zero downtime, instant rollback but double infra
- **Canary**: Release to small subset (5% users), monitor, gradually increase to 100%. Tools: Argo Rollouts, Flagger
- **Rolling**: K8s default, gradually replace pods
- **Feature Flag**: Deploy code dark, enable via flag

## Observability - 3 Pillars
- **Metrics**: Numbers (Prometheus) - RED (Rate, Errors, Duration) + USE (Utilization, Saturation, Errors)
- **Logs**: Events (ELK)
- **Traces**: Request flow (Jaeger)

+ **Profiles**: Continuous profiling (Pyroscope)

## Service Mesh
- Istio, Linkerd
- Features: mTLS, traffic management (canary, retry), observability, security without code change
- Data plane: Envoy sidecars, Control plane: Istiod
- Cons: Complexity, latency overhead, resource

## Challenges & Solutions

| Challenge | Solution |
|-----------|----------|
| Distributed transactions | SAGA, eventual consistency |
| Testing | Contract testing (Pact), Testcontainers, consumer-driven |
| Debugging | Distributed tracing, correlation ID |
| Data consistency | Eventual consistency, CQRS, compensating |
| Network latency | gRPC, caching, async, batch |
| Service dependencies | Circuit breaker, bulkhead, fallback |
| Versioning | API versioning, backward compatibility, consumer-driven |

## Interview Q: How to break monolith?
1. Identify bounded contexts (DDD)
2. Start with least coupled module (e.g. notification service)
3. Strangler Fig: Proxy via API gateway, route new to microservice, old to monolith
4. Database: First shared DB, then split with sync via CDC or dual write + verification
5. Incremental, not big bang

## Example E-commerce Microservices
- User Service (PG)
- Product Catalog Service (Mongo)
- Inventory Service (Redis + PG)
- Order Service (PG)
- Payment Service (PG + external gateway)
- Notification Service (SES/SNS)
- Search Service (Elasticsearch)
- Recommendation Service (Python + Vector DB)
- API Gateway (Kong) + Frontend
