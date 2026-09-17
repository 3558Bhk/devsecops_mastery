# Types of Architectures - SDE3

## 1. Monolithic Architecture
- Single deployable unit, all modules in one codebase
- Pros: Simple dev, testing, deployment initially, performance (in-process)
- Cons: Scaling hard (scale whole app), tight coupling, slow deployments, tech lock
- Use: Small team, MVP, low complexity
- Example: Traditional Spring Boot WAR with all features

## 2. Microservices Architecture
- Small independent services, each own DB, communicate via REST/gRPC/Queue
- Pros: Independent deploy, scale, tech diversity, fault isolation, team autonomy
- Cons: Distributed complexity, network latency, data consistency (eventual), debugging hard, need DevOps maturity
- Patterns: API Gateway, Service Discovery, Circuit Breaker, SAGA, CQRS
- Use: Large team, complex domain, need scale
- Example: Amazon: user-service, order-service, payment-service

## 3. Service-Oriented Architecture (SOA)
- Predecessor to microservices, coarse-grained services, ESB (Enterprise Service Bus) for communication, often SOAP
- Difference: SOA uses ESB smart pipes, microservices dumb pipes smart endpoints
- Use: Enterprise legacy

## 4. Event-Driven Architecture (EDA)
- Services communicate via events (async)
- Components: Event producers, Event bus (Kafka, RabbitMQ, SNS), Consumers
- Pros: Loose coupling, highly scalable, resilient, real-time
- Cons: Eventual consistency, debugging, event ordering
- Patterns: Event Sourcing, Pub/Sub
- Example: Order placed event -> Inventory service reduces stock -> Email service sends mail

## 5. Serverless Architecture
- No server management, FaaS (Lambda) + BaaS (S3, DynamoDB, Auth0)
- Pros: Auto scale to zero, pay per use, no ops, fast deploy
- Cons: Cold start, vendor lock, timeout limits, debugging hard, not for long running
- Use: Event processing, cron, APIs with spiky traffic, MVPs
- Example: S3 upload -> Lambda resize image -> Save to S3

## 6. Layered (N-Tier) Architecture
- Layers: Presentation (UI), Business Logic, Data Access, DB
- Pros: Separation of concerns, easy to understand
- Cons: Can become monolithic, performance due to layers
- Use: Traditional enterprise apps
- Example: MVC: Controller -> Service -> Repository -> DB

## 7. Hexagonal / Clean / Onion Architecture
- Core domain independent of external (DB, UI, frameworks)
- Ports and Adapters
- Pros: Testable, decoupled, business logic isolated
- Cons: More boilerplate
- Use: Complex domain (DDD), long-lived apps
- Interview: "We used hexagonal to make domain testable without DB"

## 8. Micro Frontends
- Frontend divided into independent apps (like microservices but for UI)
- Each team owns a UI slice, different frameworks possible
- Pros: Team autonomy, independent deploy
- Cons: Bundle size, consistency
- Use: Large org with many frontend teams

## 9. Peer-to-Peer
- Nodes equal, no central server (BitTorrent, blockchain)
- Pros: Decentralized, fault tolerant
- Cons: Security, consistency

## 10. Client-Server
- Basic: Client requests server
- Thick vs thin client

## 11. Cloud Native / 12 Factor
- Principles: Codebase, dependencies, config, backing services, build release run, processes, port binding, concurrency, disposability, dev/prod parity, logs, admin processes
- Use: SaaS apps

## Architecture Decision - How SDE3 Chooses?

| Factor | Monolith | Microservices | Serverless |
|--------|----------|---------------|------------|
| Team size | <10 | 20+ | Small |
| Domain complexity | Low | High | Variable |
| Scaling need | Low | High independent | Spiky |
| Deployment frequency | Low | High per team | High |
| Experience | Low | High DevOps | Medium |

## Scalability Types
- **Vertical**: Bigger machine (more CPU/RAM) - limit hardware, downtime
- **Horizontal**: More machines - preferred, stateless needed, load balancer

## High Availability & Fault Tolerance
- HA: 99.9% (8.76h downtime/year), 99.99% (52min), 99.999% (5min)
- Strategies: Redundancy, failover, multi-AZ, multi-region, circuit breaker, retry with exponential backoff, bulkhead

## CAP Theorem (Must Know)
- Consistency, Availability, Partition Tolerance - pick 2
- In partition, choose C or A
- CP: MongoDB, HBase, Redis (when configured) - consistent but may be unavailable during partition
- AP: Cassandra, DynamoDB, CouchDB - available but eventual consistency
- CA: Single node RDBMS (but partition will happen in distributed, so not practical)
- Modern: PACELC: If Partition, choose A/C else choose Latency/Consistency

## Interview Questions
**Q: Monolith to microservices migration?**
- Strangler Fig pattern: Gradually replace monolith features with services, proxy via API gateway
- Identify bounded contexts (DDD)
- Start with non-critical service

**Q: How to handle transactions in microservices?**
- SAGA pattern: Choreography (events) or Orchestration (coordinator)
- Compensating transactions for rollback

**Q: What is service mesh?**
- Infrastructure layer for service-to-service communication (Istio, Linkerd)
- Handles mTLS, traffic management, observability, retries, without code changes
