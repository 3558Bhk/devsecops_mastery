# Complete List of All Software Architectures - SDE3 Master List (Expanded Edition - 35+ Architectures)

## 1. By Structure / Deployment

### 1.1 Monolithic Architecture
- Single deployable unit, all modules in one codebase, one DB, one process
- Pros: Simple dev (one repo), testing (one test suite), deployment (one artifact) initially, performance (in-process method calls no network), transactions easy (ACID via @Transactional), debugging easy (single process)
- Cons: Scaling hard (scale whole app even if only one module needs scaling), tight coupling (change in one module affects others), slow deployments (whole app redeploy even small change), tech lock (one language/framework), single point failure (one bug crashes whole app), long build times, team conflicts (many devs same codebase)
- Use: Small team <10, MVP, low complexity, startup early stage, proof of concept, internal tools
- Example: Traditional Spring Boot WAR with all features (user, order, payment, inventory) in one app, one MySQL DB
- Scaling: Vertical only initially (bigger machine), then horizontal via multiple instances behind LB but still whole app scaled
- Evolution: Modular Monolith (monolith but with strict module boundaries, each module like microservice but deployed as one, can later split to microservices easily) - gaining popularity 2024-25 as over-engineering microservices early is anti-pattern

### 1.2 Modular Monolith Architecture (Trending 2024-25)
- Monolith but with strict module boundaries (like microservices but deployed as one), each module own package, own DB schema (or shared DB but separate schemas), communicates via internal APIs (not REST, but method calls or events), can later split to microservices easily by extracting module
- Pros: Simple like monolith (one deployment) but scalable like microservices (modules independent), no distributed complexity, transactions easy (can use @Transactional across modules if same DB), easy to split later, team autonomy per module
- Cons: Still single deployment (but modules can be deployed together), need discipline to keep boundaries
- Use: Startup that may need microservices later but not now, medium team, want to avoid microservices complexity early
- Tools: Spring Modulith (Spring Boot extension for modular monolith), Service Weaver (Go)
- Example: E-commerce modular monolith: User module, Order module, Payment module each own package `com.example.user`, `com.example.order`, communicate via events (Spring ApplicationEvent) not direct calls, own DB schemas, deployed as one JAR but can split to microservices later

### 1.3 Microservices Architecture
- Small independent services, each own DB, own team, own repo, communicate via REST/gRPC/Queue, independently deployable, polyglot (different languages per service)
- Pros: Independent deploy (one service deploy doesn't affect others), scale independently (only scale order service if need), tech diversity (polyglot - user service Java, notification service Node, ML service Python), fault isolation (one service down doesn't crash others), team autonomy (each team owns service end-to-end), faster deployments (small services), easier to understand (small codebase)
- Cons: Distributed complexity (network latency, retries, circuit breaker, distributed tracing), data consistency (eventual consistency, SAGA), debugging hard (need distributed tracing, logs aggregation), DevOps maturity needed (K8s, CI/CD, monitoring), inter-service communication overhead (REST/gRPC vs in-process), distributed transactions hard, testing hard (contract testing, E2E)
- Patterns: API Gateway, Service Discovery, Circuit Breaker, SAGA, CQRS, Event Sourcing, Sidecar, Service Mesh, Strangler Fig, Database per Service, API Composition, BFF
- Use: Large team 20+, complex domain, need independent scaling, enterprise, long-lived products
- Example: Amazon: user-service (PG), order-service (PG), payment-service (PG + Stripe), inventory-service (Redis+PG), product-service (Mongo), search-service (ES), notification-service (Node) each separate repo, own DB, communicate via REST/gRPC/Kafka, deployed on EKS
- Scaling: Horizontal per service, auto scaling HPA per service based on CPU/QPS

### 1.4 Service-Oriented Architecture (SOA)
- Predecessor to microservices (2000s), coarse-grained services (bigger than microservices, e.g. entire Order Management service vs microservices order-service, inventory-service separate), ESB (Enterprise Service Bus) smart pipes for communication (routing, transformation, orchestration), often SOAP, shared DB sometimes, reuse focus
- Difference vs Microservices:
  - SOA: Coarse-grained, ESB smart pipes (routing, transformation in ESB), dumb endpoints, SOAP often, shared DB sometimes, reuse focus, governance heavy
  - Microservices: Fine-grained, dumb pipes (HTTP) smart endpoints (logic in service), REST/gRPC, database per service, autonomy focus, decentralized governance
- Use: Enterprise legacy, banking, telecom, large enterprises 2000s
- Example: Old banking system with ESB (MuleSoft, WSO2) routing between account service, loan service, customer service via SOAP, ESB does transformation XML to JSON, routing
- Evolution: SOA -> Microservices (microservices is evolution of SOA with modern practices)

### 1.5 Serverless Architecture
- No server management, FaaS (Function as a Service - AWS Lambda, Azure Functions, GCP Cloud Functions, Cloudflare Workers) + BaaS (Backend as a Service - S3, DynamoDB, Auth0, Firebase, Supabase)
- Pros: Auto scale to zero (no cost when not used), pay per use (100ms billing, cheap for spiky), no ops (no servers to manage), fast deploy (zip upload), built-in HA (AWS manages), focus on business logic
- Cons: Cold start (100ms Node/Python/Go, 1-2 sec Java, 500ms .NET - need SnapStart or provisioned concurrency or GraalVM native for Java), vendor lock-in (AWS Lambda API vs Azure Functions different), timeout limits (Lambda 15 min max, not for long running), debugging hard (local testing hard, logs via CloudWatch), not for long running or stateful (stateless), limited runtime (memory, CPU, disk), state management hard (need external DB/cache)
- Use: Event processing (S3 upload -> Lambda resize image), cron jobs (EventBridge -> Lambda), APIs with spiky traffic (e.g. once a day report), MVPs, glue code, image processing, ETL
- Example: S3 upload image -> Lambda triggers -> resize to 3 sizes (thumb, medium, large) -> save to S3 -> DynamoDB update + CloudFront invalidation + SNS notification
- Cost: Cheap for low/spiky traffic, expensive for high constant traffic (EC2 cheaper for constant high traffic)

### 1.6 Micro Frontends Architecture
- Frontend divided into independent micro apps, each team owns a UI slice, different frameworks possible (React, Vue, Angular in same page), independently deployed, composed into shell app
- Techniques:
  - Module Federation (Webpack 5 - share dependencies, load remote apps at runtime, most popular 2023-25)
  - Single-SPA (framework agnostic, registers micro apps, lifecycle)
  - Web Components (framework agnostic, custom elements)
  - iFrames (old, isolated but perf bad, SEO bad, communication via postMessage)
- Pros: Team autonomy (each team deploy independently), independent deploy (search team deploy without cart team), tech diversity (React + Vue in same page), scaling frontend teams (like microservices for frontend), fault isolation (one micro frontend crash doesn't crash whole page)
- Cons: Bundle size duplication (React loaded twice if not shared via Module Federation shared), consistency (UI/UX, design system needed), performance overhead (multiple frameworks, extra JS), complexity (shared state, routing, communication between micro frontends via custom events or shared store), SEO complexity
- Use: Large org with many frontend teams (e.g. Amazon, IKEA, DAZN, Spotify, Starbucks)
- Example: E-commerce: Search team owns search micro frontend (React) deployed at search.example.com/remoteEntry.js, Cart team owns cart (Vue) at cart.example.com, Product team owns product (React), Shell app (host, Next.js) loads all via Module Federation, shared design system via Storybook

### 1.7 Peer-to-Peer (P2P) Architecture
- Nodes equal, no central server, each node acts as client and server, decentralized, distributed hash table (DHT) for discovery
- Pros: Decentralized (no single point), fault tolerant (no central failure), scalable (add nodes increases capacity), no central cost, censorship resistant
- Cons: Security hard (malicious nodes), consistency hard (eventual), discovery hard (need DHT or tracker), NAT traversal (need STUN/TURN), data availability (if no peer has data, not available)
- Use: BitTorrent (file sharing), blockchain (Bitcoin, Ethereum), Skype (old P2P), IPFS (decentralized storage), WebRTC (P2P video)
- Example: BitTorrent file sharing, file split into pieces, each peer shares pieces it has, tracker or DHT finds peers, each peer downloads from many peers and uploads to many

---

## 2. By Communication / Interaction

### 2.1 Client-Server Architecture
- Most basic: Client requests, server responds, many clients one server, client-server separation
- Types: 2-tier (client + DB server directly, e.g. desktop app + DB), 3-tier (client + app server + DB server, e.g. browser + Tomcat + MySQL), N-tier (more tiers, e.g. client + CDN + LB + app server + cache + DB)
- Thick client (heavy logic in client, e.g. desktop app, mobile app) vs Thin client (logic in server, client just UI - web browser, Chromebook)
- Use: Web apps, traditional, most apps are client-server at high level
- Example: Browser (client) -> Nginx (server) -> Node.js (server) -> PG (server) - actually multiple client-servers chained

### 2.2 Event-Driven Architecture (EDA)
- Services communicate via events (async), loose coupling, producers publish events to event bus (Kafka, RabbitMQ, SNS, EventBridge), consumers subscribe and react, event is something that happened (OrderCreated, PaymentSucceeded)
- Pros: Loose coupling (producer doesn't know consumers), highly scalable (add consumers without affecting producer), resilient (if consumer down events queued, replay), real-time, extensible (add new consumer without changing producer), audit log (events log)
- Cons: Eventual consistency (consumer lag), debugging hard (event chain across services, need tracing), event ordering (need partition key), duplicate handling (idempotency needed, at-least-once), schema evolution (need schema registry), testing hard (async)
- Patterns: Event Sourcing, Pub/Sub, Event Streaming, CQRS, Outbox pattern (to ensure event published atomically with DB transaction)
- Use: E-commerce order flow: OrderCreated event -> Inventory service reserves stock -> Payment service charges -> Email service sends confirmation -> Analytics service tracks, all via events async, each service independent
- Example: Uber: Ride requested event -> Driver matching service, pricing service, notification service, ETA service, fraud detection all react to same event independently

### 2.3 Space-Based Architecture (Cloud Elasticity, Tuple Space)
- No central DB bottleneck, all processing units (PU) have in-memory data grid (e.g. Hazelcast, Apache Ignite, GigaSpaces), partitioned, replication, elastic scaling by adding PUs, data grid is primary, DB is backup for persistence
- Also called Cloud Elasticity, Tuple Space, In-Memory Data Grid
- Pros: Extreme scalability (add PUs linearly increases capacity), low latency (in-memory, no DB hit), no DB bottleneck, elastic (auto scale PUs based on load)
- Cons: Complex (data grid management), data consistency (need replication, partitioning), RAM cost (in-memory expensive), data loss risk if not persisted
- Use: High throughput trading systems (stock trading), e-commerce black Friday scaling (session, cart in-memory grid), gaming leaderboards, real-time analytics
- Example: Trading platform where order book in-memory grid across many PUs, each PU owns part of order book, trades matched in-memory, async persisted to DB, handles 100k trades/sec

### 2.4 Service Mesh Architecture
- Infrastructure layer for service-to-service communication, sidecar proxy (Envoy) alongside each service handles mTLS, traffic management (canary, retries, timeouts, circuit breaker), observability (metrics, traces, logs), security, without code changes in service
- Control plane (Istiod) manages config, distributes to data plane, Data plane (Envoy sidecars) handles traffic
- Pros: Security (mTLS auto, no code change), observability (metrics/traces/logs auto), traffic control (canary, retries, timeouts, fault injection) without code change, policy enforcement, transparent
- Cons: Complexity (another layer), latency overhead (extra hop via sidecar, ~2-5ms), resource overhead (sidecar CPU/memory 100MB per pod), debugging harder (need understand Envoy config), operational complexity
- Use: Large microservices (20+ services) needing security + observability + traffic management, zero trust security
- Tools: Istio (feature rich complex, most popular), Linkerd (lightweight fast, simpler, Rust), Consul Connect (HashiCorp), Kuma, Cilium Service Mesh (eBPF based, no sidecar, high perf)
- Example: E-commerce 30 microservices on EKS with Istio: Each pod has Envoy sidecar, all inter-service traffic mTLS auto, Prometheus metrics auto, Jaeger traces auto, canary deployments via VirtualService (5% traffic to v2), retries and circuit breaker via DestinationRule, no code change in services

### 2.5 eBPF-based Architecture (Trending 2024-25)
- eBPF (extended Berkeley Packet Filter) runs sandboxed programs in Linux kernel without changing kernel, high performance networking, observability, security
- Use for service mesh without sidecars (Cilium), replaces sidecar with eBPF programs in kernel, lower latency, lower resource
- Tools: Cilium (eBPF based networking, service mesh, security), Pixie (observability), Falco (security)
- Pros: High performance (no sidecar hop), lower resource, kernel level visibility
- Cons: Linux only, need recent kernel, new
- Example: Cilium service mesh: No sidecars, eBPF programs handle load balancing, mTLS, observability in kernel, 2x faster than Istio sidecar

---

## 3. By Pattern / Design

### 3.1 Layered (N-Tier) Architecture
- Layers stacked: Presentation (UI, Controller) -> Business Logic (Service) -> Data Access (Repository) -> Database, each layer only talks to layer below (strict) or below any (relaxed)
- Pros: Separation of concerns, easy to understand, testable (mock lower layers), maintainable, familiar, most common
- Cons: Can become monolithic, performance due to layers (data passes through all layers even if not needed), tight coupling between layers if not careful, anemic domain model (logic in service not entity), can become sinkhole (all requests pass through all layers)
- Use: Traditional enterprise apps, Spring Boot default (Controller -> Service -> Repository), most CRUD apps
- Example: MVC: Controller (handles HTTP, validation) -> Service (business logic, transactions) -> Repository (DB access) -> DB (MySQL)

### 3.2 Hexagonal / Clean / Onion Architecture (Ports and Adapters)
- **Hexagonal (Alistair Cockburn)**: Core domain at center, ports (interfaces) define how core interacts with external, adapters implement ports for external (e.g. MySQL adapter implements Database port, REST adapter implements API port), dependencies point inward (adapters depend on core, not vice versa)
- **Clean Architecture (Robert Martin)**: Layers: Entities (core business, enterprise wide) -> Use Cases (app specific business rules) -> Interface Adapters (controllers, gateways, presenters - converts data) -> Frameworks & Drivers (Spring, DB, UI, external) - dependencies rule: Inner layers don't know outer, outer depends on inner, via dependency inversion
- **Onion Architecture (Jeffrey Palermo)**: Similar to clean, Domain at center, then Domain Services, then Application Services, then Infrastructure outer (DB, UI, external), dependencies inward
- All three similar: Core domain independent of external (DB, UI, frameworks), ports and adapters, dependency inversion
- Pros: Testable (core without DB, fast unit tests, no Spring needed), decoupled (business logic isolated), framework independent (can swap Spring for Micronaut, MySQL for PG easily), long-lived apps, DDD friendly, maintainable
- Cons: More boilerplate (many interfaces, adapters), overkill for simple CRUD, learning curve, more files
- Use: Complex domains, long-lived apps (5+ years), need to swap DB/framework easily, DDD, enterprise
- Example: Order domain core has Order entity and OrderRepositoryPort interface (port), MySQLOrderRepositoryAdapter implements port using JPA (adapter), RestOrderControllerAdapter (adapter), KafkaOrderEventAdapter (adapter). Core has no Spring annotations, pure Java.

```java
// Core - no Spring dependencies
public class Order {
  private String id;
  private Money total;
  public void applyDiscount(Discount discount) { /* business logic */ }
}
public interface OrderRepositoryPort {
  void save(Order order);
  Optional<Order> findById(String id);
}
// Adapter - Spring + JPA
@Repository
public class MySQLOrderRepositoryAdapter implements OrderRepositoryPort {
  private final JpaOrderRepository jpaRepo;
  public void save(Order order) { jpaRepo.save(toEntity(order)); }
}
```

### 3.3 Model-View-Controller (MVC) Architecture
- Model: Data + business logic + rules + validation (e.g. User model with validation, Order model with total calculation)
- View: Presentation (UI - HTML template, or JSON for REST APIs)
- Controller: Handles request, calls Model, selects View, thin controllers fat models principle (business logic in Model not Controller)
- Flow: User -> Controller -> Model -> View -> User
- Variants: 
  - MVP (Model-View-Presenter, View passive, Presenter handles View logic, used in Android old)
  - MVVM (Model-View-ViewModel, ViewModel exposes data and commands for View binding, two-way binding, used in Angular/Vue/WPF)
  - MVVM-C (MVVM + Coordinator for navigation)
- Use: Web frameworks (Rails, Laravel, Spring MVC, Django MTV, ASP.NET MVC, iOS MVC)
- Example: Rails: User model (models/user.rb with validations), UsersController (controllers/users_controller.rb handles /users, calls User model), users/index.html.erb view (HTML)

### 3.4 Model-View-ViewModel (MVVM)
- Model: Data (services, API, DB)
- View: UI (declarative, e.g. SwiftUI, XML, HTML)
- ViewModel: Exposes data and commands for View, handles View logic, transforms Model data for View, two-way binding View <-> ViewModel (when ViewModel changes View auto updates, when View changes ViewModel auto updates)
- Use: Frontend frameworks (Angular, Vue, WPF, SwiftUI, Android Jetpack)
- Example: Angular component class is ViewModel (has properties and methods), template is View (binds to ViewModel via {{ property }} and (click)), service is Model

### 3.5 Component-Based Architecture
- System built from reusable components (self-contained, replaceable, with well-defined interfaces, e.g. Button component, UserService component)
- Components communicate via interfaces, not direct implementation, can be replaced
- Pros: Reusability, maintainability, independent development, testability, composability
- Use: Frontend (React components), microservices (each service component), OSGi (Java modular), micro frontends
- Example: React: Button component (props: label, onClick, variant), Card component (props: title, children), UserList component (props: users) composed into App, each reusable

### 3.6 Plugin Architecture
- Core system minimal + plugins that extend functionality, core provides extension points (hooks, APIs), plugins implement extension points, core loads plugins at runtime
- Pros: Extensibility without modifying core, ecosystem (third party plugins), customizable, small core
- Use: Jenkins (1800+ plugins), WordPress (plugins), VS Code extensions, browsers (extensions), Eclipse IDE, Webpack (plugins), Babel
- Example: Jenkins core (scheduling, UI) + Git plugin + Docker plugin + Slack plugin + K8s plugin, each plugin adds functionality, core doesn't know plugin details, only extension points

### 3.7 Microkernel Architecture (Plug-in Architecture variant)
- Minimal core (microkernel) with only essential features (scheduling, IPC, basic), all other features as plugins on top of microkernel, microkernel only essential
- Example: OS microkernel (Mach, L4 - only scheduling, IPC, memory management, everything else like file system, drivers as servers on top), Eclipse IDE (microkernel + plugins), some browsers

### 3.8 Pipe and Filter Architecture
- Data flows through pipes via filters each transforming data, chain of filters, each filter does one transformation, output of one filter is input to next via pipe
- Pros: Reusability (filters reusable), composability (chain filters), parallelism (filters can run in parallel), simplicity
- Cons: Not interactive, overhead of data copying between filters, error handling hard
- Use: Unix pipes `cat file | grep error | sort | uniq -c | sort -nr` (each command filter), compilers (lexical analysis -> parsing -> semantic analysis -> code generation each filter), ETL pipelines, image processing pipelines
- Example: Log processing pipeline: Input (read logs) -> Filter (parse JSON) -> Filter (enrich with geo IP) -> Filter (aggregate per minute) -> Filter (detect anomalies) -> Output (save to ES, alert)

### 3.9 Broker Architecture
- Broker mediates communication between clients and servers, clients don't know servers directly, clients send requests to broker, broker finds appropriate server, routes request, returns response, handles discovery, load balancing, fault tolerance
- Pros: Decoupling (client doesn't know server location), load balancing, fault tolerance (broker can retry other server), discovery
- Cons: Broker becomes bottleneck, single point failure (need HA broker), latency overhead
- Use: Message brokers (RabbitMQ, Kafka - broker), CORBA, microservices API Gateway as broker (client -> gateway -> services), service mesh (Envoy as broker)
- Example: Client -> RabbitMQ broker (exchange routes to queues) -> Consumers, client doesn't know which consumer handles

### 3.10 Interpreter Architecture
- Includes interpreter for domain-specific language (DSL), program written in DSL interpreted by interpreter, interpreter executes DSL
- Use: Programming languages (JVM interprets bytecode, Python interpreter), scripting languages, rule engines (Drools), regex engines, SQL engines
- Example: JVM: Java code (.java) -> javac -> Bytecode (.class) -> JVM interpreter/JIT -> OS, Python: .py -> Python interpreter -> OS, Excel: Formulas interpreted

---

## 4. By Data / Domain

### 4.1 Event Sourcing Architecture
- Store events (state changes) not current state, current state derived by replaying events, append-only log (event store), events immutable
- Pros: Audit log (full history of changes), time travel (state at any time by replaying until that time), debugging (replay events to reproduce bug), event replay for new features (new consumer can replay all history to build its view), temporal queries
- Cons: Complexity (need event store, replay logic), eventual consistency (read model lag), storage large (many events), schema evolution of events (need upcasting - old events to new format), need snapshots for performance (replaying 1M events slow, so snapshot every 100 events to avoid replay from beginning)
- Use: Banking ledger (transactions as events - AccountCreated, Deposited, Withdrawn), auditing, collaborative editing (Google Docs edits as events), accounting, DDD with aggregates
- Example: Bank account: Events: AccountCreated {id:123, owner:John}, MoneyDeposited {amount:100, time:T1}, MoneyWithdrawn {amount:20, time:T2} -> Current balance = replay events = $80. State not stored, derived. Can get balance at T1 = $100 by replaying until T1.

### 4.2 CQRS (Command Query Responsibility Segregation) Architecture
- Separate read and write models: Command model for writes (handles commands like CreateOrder, UpdateOrder, normalized DB, optimized for writes, handles business logic), Query model for reads (handles queries like GetOrders, denormalized optimized for queries, e.g. Elasticsearch, materialized view, read replica)
- Sync via events (CDC - Change Data Capture with Debezium capturing DB changes from WAL and publishing to Kafka, then consumers update read model) or via application events
- Pros: Optimized read and write independently (write model normalized for consistency, read model denormalized for fast queries), scalable (scale read and write separately), can use different DBs (write PG, read ES), complex queries fast on read model, separation of concerns
- Cons: Complexity (two models, need sync), eventual consistency between read and write (read model lag - user creates order then immediately queries may not see it, need read-your-writes handling), duplication (data duplicated in read and write), need sync mechanism (CDC or events)
- Use: Read heavy with complex queries (e.g. e-commerce product search with many filters, sorting, full text), reporting, analytics, collaborative apps
- Example: Write to PostgreSQL normalized (orders table, order_items table, users table), async via Kafka + Debezium to Elasticsearch denormalized (order document with user + products + shipping nested) for fast search with filters, or to materialized view for reporting

### 4.3 Domain-Driven Design (DDD) Architecture
- Focus on domain, ubiquitous language (shared language between devs and domain experts), bounded contexts, entities, value objects, aggregates, repositories, domain services, domain events
- Strategic DDD: Bounded contexts (e.g. Ordering context, Shipping context, Billing context - each context has its own model, language, team), Context mapping (how contexts relate: Shared Kernel, Customer-Supplier, Conformist, Anti-corruption Layer)
- Tactical DDD: Entities (have ID, mutable, e.g. Order), Value Objects (no ID, immutable, e.g. Money, Address, Email), Aggregates (cluster of entities with root - Aggregate Root, e.g. Order aggregate with Order root + OrderItems, only root accessed externally), Repositories (for aggregates), Domain Services (logic not fitting in entity), Domain Events (something happened in domain)
- Use: Complex domains (e.g. e-commerce, banking, insurance, logistics), large teams, microservices decomposition via bounded contexts (one microservice per bounded context)
- Example: E-commerce: Ordering bounded context (Order aggregate with Order root + OrderLineItems, User entity, Money value object, OrderRepository, OrderDomainService for discount calculation, OrderCreated domain event), Inventory bounded context (Stock aggregate), each bounded context microservice

### 4.4 Data-Centric Architecture
- Central data (DB, data lake, data warehouse) is core, other components access data, data is primary, logic around data
- Example: Traditional DB-centric apps, data warehouse (central DW with ETL from sources, BI tools access DW), data lake (central S3 with raw data)

### 4.5 Database per Service Architecture
- Each microservice owns its own DB, no shared DB, only communication via API (REST/gRPC), not direct DB access
- Pros: Loose coupling (service can change DB schema without affecting others), choose DB per need (user service PG, product catalog Mongo, search ES, cache Redis), independent scaling (scale DB per service), team autonomy
- Cons: Cross-service queries hard (need API composition - call multiple services and join in API Gateway/BFF, or CQRS with denormalized read model), distributed transactions hard (need SAGA), data duplication (same data may be in multiple services for performance, need sync)
- Use: Microservices best practice, must for microservices
- Example: User service owns users DB (PG), Order service owns orders DB (PG), Product service owns products DB (Mongo), no service accesses other's DB directly, only via API

### 4.6 Shared Database Architecture (Anti-pattern for microservices but sometimes used for transition)
- Multiple services share same DB, directly access same tables
- Pros: Simple, ACID transactions across services (via DB transactions), no data duplication, easy queries (JOIN across services)
- Cons: Tight coupling (service can't change schema without affecting others), scaling hard (DB bottleneck), team conflicts, no autonomy, single point failure
- Use: Monolith, or transition from monolith to microservices (first split code but keep shared DB, then split DB later)
- Example: Monolith with user and order tables in same DB, both user and order modules access same DB

---

## 5. By Scalability / Availability

### 5.1 Shared Nothing Architecture
- Each node independent, no shared disk/memory, only communicates via network, each node owns part of data, scales horizontally by adding nodes, no single point contention
- Pros: Scalable (add nodes linearly increases capacity), fault tolerant (node failure doesn't affect others, only its data needs replication), no contention (no shared resource)
- Cons: Data partitioning complexity (need sharding), consistency (need replication, eventual), cross-node queries hard
- Use: Cassandra (each node owns token range, no shared), MongoDB sharding, microservices (each service independent), web servers behind LB (shared nothing)
- Example: Cassandra cluster 6 nodes each owns 1/6 data, no shared disk, replication factor 3, each node independent, add node increases capacity linearly

### 5.2 Shared Disk Architecture
- Multiple nodes share same disk storage (SAN - Storage Area Network), but have own memory/CPU, all nodes see same disk, need distributed lock manager to coordinate
- Pros: Simple (all nodes see same data), strong consistency (all see same disk), easy failover (any node can take over)
- Cons: Disk becomes bottleneck (all nodes access same disk, I/O contention), scaling limited (disk I/O limit), need distributed locking (complex), cost (SAN expensive)
- Use: Oracle RAC (Real Application Clusters - multiple Oracle instances share same disk), traditional active-passive cluster with shared disk
- Example: 2 node cluster sharing SAN storage, both nodes can access same DB files, if one node fails other takes over, but disk I/O bottleneck

### 5.3 Sharded Architecture (Horizontal Partitioning)
- Split DB into shards (partitions) by key (e.g. user_id % N, or hash(user_id) % N, or range), each shard subset of data on different node, each shard own DB
- Pros: Scales write (write distributed across shards), scales storage (data distributed), large data handling
- Cons: Cross-shard queries hard (need scatter-gather or denormalize), rebalancing hard (when add shard need move data, consistent hashing helps), choose shard key carefully to avoid hot shard (e.g. sharding by timestamp causes hot shard for latest data), transactions across shards hard (2PC or SAGA), joins across shards impossible
- Strategies:
  - Range sharding: By range (e.g. user_id 1-1000 shard1, 1001-2000 shard2) - simple but can cause hot shard if range uneven
  - Hash sharding: hash(key) % N - even distribution, but range queries hard
  - Directory sharding: Lookup service knows which shard for key - flexible but lookup service bottleneck
  - Geo sharding: By geography (US users shard US, EU users shard EU) - for data locality, compliance (GDPR)
- Use: Large DBs (100GB+), write heavy, e.g. user table 100M users sharded by user_id, order table sharded by user_id
- Example: User table sharded by user_id % 4: Shard0 user_id %4==0, Shard1 %4==1, etc, each shard PG on different server, app layer knows shard via hash, query for user 123 goes to shard 123%4=3

### 5.4 Lambda Architecture (Big Data - Nathan Marz)
- Batch layer (historical data, accurate but slow, e.g. Hadoop MapReduce, Spark batch, computes all-time views from all data, hours), Speed layer (real-time data, fast but approximate, e.g. Storm, Spark Streaming, Flink, computes last hour views from recent data, seconds), Serving layer (merge batch + speed views, e.g. Cassandra, HBase, Druid, serves queries)
- Pros: Handles both batch (accurate, complete) and real-time (fast), fault tolerant (batch recomputes from raw data), scalable
- Cons: Complexity (maintain two codebases batch and speed - same logic in two systems), duplication (logic duplicated), operational complexity (two systems)
- Use: Big data analytics needing both historical accurate and real-time fast, originally by Nathan Marz for Twitter
- Example: Twitter: Batch layer (Hadoop) computes all-time tweet counts, retweet counts from all history (accurate, hours), Speed layer (Storm) computes last hour counts from recent tweets (fast, seconds), Serving layer (Cassandra) merges batch + speed to serve query "total retweets = batch count + speed count"

### 5.5 Kappa Architecture (Simplification of Lambda - Jay Kreps)
- Only streaming layer, no batch layer, all data as stream (Kafka as log), reprocess stream when logic changes by replaying stream from beginning, batch is just replay of stream
- Pros: Simpler than Lambda (one codebase streaming only), real-time, no duplication, reprocessing via replay
- Cons: Reprocessing large history via streaming can be slow (need large retention, replay 1 year data via streaming takes time), need retention (Kafka retention 1 year or infinite), not all batch use cases fit streaming
- Use: Modern streaming, Kafka-centric, when you have Kafka as central log, LinkedIn uses Kappa
- Example: LinkedIn: All events (user actions, page views) as stream in Kafka, streaming jobs (Flink, Kafka Streams) process stream to compute views, if logic changes replay Kafka from beginning to recompute

### 5.6 Cell-Based Architecture (Trending - AWS)
- Cells (isolated deployment units) for blast radius reduction, each cell handles subset of customers (e.g. 5% customers per cell), failure in one cell doesn't affect others, cells independent, no shared state between cells, control plane manages cells
- Pros: Blast radius reduction (failure isolated to cell, only 5% customers affected), scalability (add cells), fault isolation, can deploy cell by cell (canary per cell)
- Cons: Complexity (need cell routing, cell assignment), data partitioning per cell, cross-cell queries hard, operational overhead
- Use: Large scale SaaS needing high availability, AWS, Slack, Stripe use cell-based
- Example: Slack: Each cell handles subset of workspaces, if cell fails only workspaces in that cell affected, other cells fine, control plane routes workspace to cell via mapping

---

## 6. Other Important Architectures

### 6.1 N-Tier Architecture
- Presentation tier (UI - browser, mobile), Application tier (business logic - app server), Data tier (DB - MySQL, PG), separated physically (different servers), each tier can be scaled independently
- Example: 3-tier: Browser (presentation) -> App server (Tomcat with Spring Boot) -> DB server (MySQL) - each tier separate server

### 6.2 Master-Slave Architecture
- Master handles writes, slaves handle reads, replication from master to slaves (async or sync), slaves can be read replicas, master failure -> promote slave to master (failover)
- Use: DB replication (MySQL master-slave, PG primary-replica, Redis master-replica), search (Elasticsearch master data nodes)
- Pros: Read scaling (add slaves for read), HA (slave can become master), simple
- Cons: Master bottleneck for writes (all writes to master), replication lag (slave behind master, eventual consistency for reads from slave), write scaling limited
- Example: MySQL: 1 master (writes) + 3 slaves (reads), app writes to master, reads from slaves (with lag handling), if master fails promote one slave to master via orchestrator

### 6.3 Master-Master (Multi-Master) Architecture
- Both nodes handle writes, replication both ways (bidirectional), conflict resolution needed (e.g. last write wins, vector clocks, CRDTs)
- Pros: Write scaling (both nodes handle writes), HA (any node can handle writes, no failover needed for writes), low latency writes (write to nearest master)
- Cons: Conflict resolution complex (two nodes write same key concurrently, need resolution), split-brain (network partition both masters think other down, both accept writes, need quorum), eventual consistency
- Use: Multi-region active-active (US master + EU master both handle writes for local users, replication async), collaborative editing
- Example: Multi-region: US master handles US users writes, EU master handles EU users writes, replication async between US and EU, conflict if same user edited in both regions concurrently need resolution

### 6.4 Pipe and Filter Architecture
- Data flows through pipes via filters each transforming data, chain of filters, each filter does one transformation, output of one filter is input to next via pipe, filters independent
- Pros: Reusability (filters reusable in different chains), composability (chain filters in different orders), parallelism (filters can run in parallel on different data), simplicity (each filter simple)
- Cons: Not interactive (batch), overhead of data copying between filters, error handling hard (need handle per filter), not good for interactive UI
- Use: Unix pipes `cat file | grep error | sort | uniq -c | sort -nr` (each command filter), compilers (lexical analysis -> parsing -> semantic analysis -> optimization -> code generation each filter), ETL pipelines, image processing pipelines, log processing
- Example: Log processing pipeline: Input (read logs from Kafka) -> Filter (parse JSON) -> Filter (enrich with geo IP via MaxMind) -> Filter (aggregate per minute per IP) -> Filter (detect anomalies via ML) -> Output (save to Elasticsearch, alert via Slack)

### 6.5 Blackboard Architecture
- Multiple specialized modules (knowledge sources - KS) read/write to shared blackboard (common data structure), control component coordinates which KS to run next, KSs don't directly communicate, only via blackboard
- Use: AI, speech recognition, complex problem solving where multiple experts needed, e.g. speech recognition: Acoustic model KS, language model KS, syntax model KS all work on blackboard (hypotheses)
- Example: Speech recognition: Blackboard has audio waveform, phonemes, words, sentences. Acoustic KS converts waveform to phonemes writes to blackboard, Language KS converts phonemes to words, Syntax KS converts words to sentences, Control decides order.

### 6.6 Broker Architecture
- Broker mediates communication between clients and servers, clients don't know servers directly, clients send requests to broker, broker finds appropriate server (via registry), routes request, returns response, handles discovery, load balancing, fault tolerance, security
- Pros: Decoupling (client doesn't know server location, can change servers without client change), load balancing (broker can LB), fault tolerance (broker can retry other server if one fails), discovery (broker knows servers)
- Cons: Broker becomes bottleneck (all traffic via broker), single point failure (need HA broker cluster), latency overhead (extra hop), complexity
- Use: Message brokers (RabbitMQ - exchange routes to queues, Kafka - broker), CORBA, microservices API Gateway as broker (client -> gateway -> services), service mesh (Envoy as broker)
- Example: Client -> RabbitMQ broker (exchange routes based on routing key to queues) -> Consumers, client doesn't know which consumer handles, broker routes

### 6.7 Interpreter Architecture
- Includes interpreter for domain-specific language (DSL), program written in DSL interpreted by interpreter, interpreter executes DSL, often with parser + interpreter
- Use: Programming languages (JVM interprets bytecode, Python interpreter, JavaScript V8 interpreter + JIT), scripting languages, rule engines (Drools - business rules DSL), regex engines (regex DSL), SQL engines (SQL DSL)
- Example: JVM: Java code (.java) -> javac -> Bytecode (.class) -> JVM interpreter (interprets bytecode) / JIT compiler (compiles hot bytecode to native) -> OS, Python: .py -> Python interpreter (CPython) -> OS, Excel: Formulas (DSL) interpreted by Excel engine

### 6.8 Batch Sequential Architecture
- Data processed in batches sequentially, each batch processed completely then next, no interaction between batches
- Use: Batch processing, ETL, payroll, billing
- Example: Payroll: Read all employee records batch -> Calculate salary for batch -> Write payslips batch -> Next batch

### 6.9 Implicit Invocation / Event Bus Architecture
- Components communicate via event bus, components publish events to bus, other components subscribe to events, components don't know each other, only bus, similar to event-driven but with event bus as central
- Use: GUI frameworks (event bus for UI events), microservices via event bus (Kafka as event bus)
- Example: GUI: Button click publishes ClickEvent to event bus, Logger subscribes and logs, Analytics subscribes and tracks, components decoupled

---

## Architecture Decision Matrix for SDE3 Interview (Expanded)

| Factor | Monolith | Modular Monolith | Microservices | Serverless | Event-Driven | Layered | Hexagonal | Micro Frontends |
|--------|----------|------------------|---------------|------------|--------------|---------|-----------|-----------------|
| Team size | <10 | 10-20 | 20+ | Small | Medium+ | Any | Medium+ | 20+ frontend |
| Domain complexity | Low | Medium | High | Low-Medium | High | Low-Medium | High | High frontend |
| Scaling need | Low | Medium | High independent | Spiky unpredictable | High | Low | Medium | Medium |
| Deployment freq | Low (weekly) | Medium (daily) | High per team (multiple per day) | High | High | Low | Medium | High per team |
| Tech diversity | No (one stack) | Limited (one stack but modules) | Yes (polyglot) | Limited (per function) | Yes | No | Yes | Yes (React+Vue) |
| Operational complexity | Low | Low-Med | High (K8s, monitoring) | Low (managed) | Med-High (Kafka) | Low | Med | Med-High (Module Federation) |
| Fault isolation | No (one bug crashes all) | Partial (module isolation) | Yes (one service down others up) | Yes | Yes | No | Yes (core isolated) | Yes (one MF down others up) |
| Data consistency | Strong ACID easy | Strong ACID if same DB | Eventual (SAGA) | Eventual | Eventual | Strong | Strong core, eventual adapters | Eventual (via events) |
| Learning curve | Low | Low-Med | High | Med | Med-High | Low | High | High |
| Time to market | Fastest (MVP) | Fast | Slow (infra) | Fastest for event-driven | Med | Fast | Slow (boilerplate) | Slow |
| Cost | Low (one server) | Low | High (many services, K8s) | Low for spiky, High for constant | Med | Low | Med | Med-High |

## How to Choose Architecture? (Interview Answer Detailed)

```
I evaluate based on 7 factors:

1. Team size & experience:
   - Small team <10, startup early, need fast MVP -> Monolith or Modular Monolith (simple, fast, no distributed complexity)
   - Medium team 10-20, some scaling needs -> Modular Monolith (modules independent but one deployment, can split later)
   - Large team 20+, many teams, need autonomy -> Microservices (team per service, independent deploy)
   - Large frontend team -> Micro Frontends

2. Domain complexity:
   - Simple CRUD (e.g. blog, todo) -> Layered (Controller->Service->Repository)
   - Complex domain with DDD (e.g. e-commerce with ordering, inventory, pricing, shipping bounded contexts) -> Hexagonal/Clean + DDD + Microservices (one microservice per bounded context)
   - Content-heavy -> Headless CMS + SSG (Astro) or SSR (Next.js)

3. Scaling requirements:
   - Need independent scaling of features (e.g. search needs 10x more scale than user profile) -> Microservices (scale only search service)
   - Spiky unpredictable (e.g. image processing on upload, once a day report) -> Serverless (auto scale to zero, pay per use)
   - Real-time async high throughput (e.g. order flow, notifications) -> Event-Driven (Kafka)
   - High read scaling -> Cache (Redis) + Read Replicas + CDN

4. Deployment & Operational maturity:
   - No DevOps, small team -> Monolith or Serverless (managed, no K8s)
   - Mature DevOps with K8s, CI/CD, monitoring -> Microservices + Service Mesh (Istio) + Observability (Prometheus)
   - Need fast independent deploys -> Microservices + CI/CD + Feature Flags

5. Business & Time to market:
   - MVP fast (2-3 months) -> Monolith or Serverless or MERN/T3 stack (fast dev)
   - Enterprise long-lived (5+ years) -> Hexagonal + Microservices + DDD (maintainability)

6. Consistency requirements:
   - Strong ACID needed (e.g. payment, inventory) -> Monolith or Modular Monolith with shared DB + @Transactional, or Microservices with SAGA + compensating transactions (eventual)
   - Eventual okay (e.g. social feed, notifications) -> Event-Driven + Microservices

7. Cost:
   - Low cost for low traffic -> Serverless (pay per use) or Monolith (one server)
   - High constant traffic -> Monolith or Microservices on EC2/K8s cheaper than serverless
   - Low memory cost -> Go microservices (10MB vs Java 500MB)

Example from my experience:

For our e-commerce, we started with modular monolith (layered) for MVP fast (3 months, 5 devs) - modules: User, Product, Order, Payment each own package and DB schema but deployed as one JAR, communicated via Spring ApplicationEvent (in-memory events). As team grew to 20 and needed independent scaling (search needs more scale than user profile, product catalog read heavy 100:1), and independent deploys (search team deploy daily, payment team weekly), we migrated to microservices using Strangler Fig pattern: New search service extracted first (least coupled), then product, then order, etc. Each service layered internally (Controller->Service->Repository) but core domain hexagonal for testability (core no Spring dependencies, adapters for MySQL, REST, Kafka). Communication via REST for sync simple + gRPC for performance critical (7x faster, 1ms vs 7ms) + Kafka for async events (OrderCreated -> Inventory, Payment, Email). Each service own PG DB (database per service), no shared DB, eventual consistency via SAGA choreography (events). Deployed on EKS with HPA based on CPU 70% + custom QPS metric, Istio service mesh for mTLS and traffic management (canary 5% -> 50% -> 100% via Argo Rollouts), monitoring via Prometheus + Grafana + Loki + Jaeger via OpenTelemetry.

Tradeoff: No perfect architecture, monolith simple but doesn't scale team and independent deploy, microservices scalable but operational complexity high (need DevOps, monitoring, tracing, SAGA), so we chose hybrid: Started modular monolith then evolved to microservices as team and scaling needs grew, not big bang.

For frontend, we used Next.js with hybrid rendering: SSG for product listing (fast + SEO, CDN cached), ISR for product detail (revalidate every 60 sec), SSR for cart/checkout (personalized), micro frontends via Module Federation for search team independent deployment.

This shows evolutionary architecture, not just one static choice, which SDE3 should do.
```

## Trending Architectures 2025-26 (Must Mention in Interview to Show Awareness)

- **Modular Monolith**: Monolith but with strict module boundaries (like microservices but deployed as one), can later split to microservices easily, gaining popularity as over-engineering microservices early is anti-pattern, tools: Spring Modulith, Service Weaver (Go), **recommended for startups 2024-25 over microservices early**
- **Hexagonal + DDD + Clean**: For complex domains, long-term maintainability, testability, framework independence, **recommended for enterprise long-lived apps**
- **Event-Driven + Microservices + Serverless Hybrid**: Most modern systems use hybrid: Microservices for core business logic, serverless for event processing (S3 upload -> Lambda), event-driven for async (Kafka), **not one architecture but hybrid**
- **Cell-Based Architecture**: AWS new, cells (isolated deployment units) for blast radius reduction, each cell handles subset of customers (e.g. 5% per cell), failure in one cell doesn't affect others, control plane manages cells, used by AWS, Slack, Stripe for high availability
- **Service Mesh + eBPF**: eBPF for high performance networking without sidecar overhead (Cilium), replaces sidecar with eBPF programs in kernel, lower latency, lower resource, **future of service mesh**, Cilium is eBPF based service mesh no sidecars
- **Platform Engineering + IDP (Internal Developer Platform)**: Build platform on top of K8s for devs to self-service (Backstage, Humanitec), reduces cognitive load, SDE3 should mention platform thinking
- **WebAssembly (WASM) + WASI**: Run near-native performance in browser and server, use for plugins, edge, e.g. Envoy WASM filters, Cloudflare Workers uses V8 isolates + WASM
- **Edge Computing**: Compute at edge close to user (Cloudflare Workers, Vercel Edge, Deno Deploy), low latency, for auth, personalization, A/B testing at edge

---

## Quick Revision - Top 10 Architectures to Master for SDE3 (Must Know Deep)

1. **Monolithic** - Simple, single deploy, vertical scaling, when to use (MVP, small team)
2. **Modular Monolith** - Trending, modules with boundaries, can split later, avoids microservices over-engineering early
3. **Microservices** - Independent services, own DB, REST/gRPC/Kafka, patterns: API Gateway, Service Discovery, Circuit Breaker, SAGA, CQRS, Service Mesh, when to use (large team, independent scaling)
4. **Event-Driven** - Events via Kafka, loose coupling, scalable, eventual consistency, when to use (async, real-time, extensible)
5. **Serverless** - FaaS + BaaS, auto scale to zero, pay per use, cold start, when to use (spiky, event processing, MVPs)
6. **Layered (N-Tier)** - Controller->Service->Repository, separation, most common
7. **Hexagonal/Clean/Onion** - Core independent, ports and adapters, testable, DDD friendly, for complex domains
8. **Micro Frontends** - Frontend as micro apps, Module Federation, team autonomy
9. **CQRS + Event Sourcing** - Separate read/write, store events not state, audit log, time travel
10. **Sharded + Shared Nothing + Lambda/Kappa + Cell-Based** - Scaling architectures, how to scale DB and system, blast radius reduction

For interview, be able to draw diagram for each, explain pros/cons, when to use, example, and tradeoffs. Show evolutionary thinking: Start monolith/modular monolith then evolve to microservices as needed, not big bang.

This file lists 35+ architectures with details. For SDE3, master top 10 deep + know others high level + mention trending 2025-26 to show awareness.

---

## Expanded Again: More Architectures & Deep Dives

### 6.10 CQRS + Event Sourcing Combined (Advanced)

**Architecture**: CQRS + Event Sourcing together - CQRS separates read/write, Event Sourcing stores events as source of truth for write model

```
Command -> Command Handler -> Aggregate (applies event) -> Event Store (append event) -> Event Bus (Kafka) -> Read Model Projectors (update read models) -> Read DB (ES, materialized views)
Query -> Read Model (ES, PG read replica) -> Response
```

- **Flow**:
  1. Client sends Command (e.g. CreateOrder)
  2. Command Handler loads Aggregate from Event Store (replay events to get current state)
  3. Aggregate handles command, produces events (e.g. OrderCreated)
  4. Events saved to Event Store (append only)
  5. Events published to Event Bus (Kafka)
  6. Projectors consume events and update read models (e.g. update Elasticsearch order document, update materialized view for reporting)
  7. Client queries read model for fast reads

- **Pros**: Audit log (all events), time travel, scalable read/write separately, optimized read models, event replay for new read models
- **Cons**: Complexity high, eventual consistency, need event store, need projectors, schema evolution
- **Use**: Complex domains with auditing, need temporal queries, high read scaling, e.g. banking, e-commerce with reporting, collaborative apps
- **Tools**: EventStoreDB (event store), Axon Framework (Java CQRS+ES framework), Lagom (Scala)

### 6.11 Saga Pattern Deep Dive (Distributed Transactions)

**Problem**: How to handle transactions across microservices? ACID not possible distributed, need SAGA

**Choreography-based Saga** (Events, no central coordinator):

```
Order Service -> Creates PENDING order, publishes OrderCreated event
Payment Service -> Listens OrderCreated, charges payment, publishes PaymentCompleted or PaymentFailed
Inventory Service -> Listens PaymentCompleted, reserves inventory, publishes InventoryReserved or InventoryFailed
Order Service -> Listens InventoryReserved, marks order CONFIRMED, publishes OrderConfirmed
                Listens PaymentFailed or InventoryFailed, marks order CANCELLED, publishes OrderCancelled, compensating transactions: Refund payment, Release inventory
```

- Pros: Simple (no central coordinator), loose coupling
- Cons: Hard to track (no central view), cyclic dependencies possible, hard to debug

**Orchestration-based Saga** (Central orchestrator):

```
Orchestrator Service (e.g. Order Orchestrator) coordinates:
1. Orchestrator calls Order Service to create PENDING order
2. Orchestrator calls Payment Service to charge
   - If fails, orchestrator calls Order Service to cancel order (compensating)
3. Orchestrator calls Inventory Service to reserve
   - If fails, orchestrator calls Payment Service to refund (compensating) and Order Service to cancel
4. Orchestrator calls Order Service to confirm
```

- Pros: Central view, easier to track, easier to debug, no cyclic
- Cons: Central coordinator becomes complex, single point, more coupling to orchestrator

**Compensating Transactions**: For rollback, need compensating actions that undo previous steps (e.g. refund payment, release inventory, cancel order)

**Implementation**: Use state machine (e.g. Spring State Machine, Temporal.io, Cadence for orchestration), or event-driven choreography with Kafka

**When**: Microservices transactions, e.g. e-commerce order flow across Order, Payment, Inventory, Shipping services

### 6.12 Outbox Pattern (Reliable Event Publishing)

**Problem**: How to ensure event published atomically with DB transaction? If you save to DB then publish to Kafka, if DB save succeeds but Kafka publish fails (crash), event lost, inconsistency. If publish then save, if publish succeeds but DB fails, event published but not saved, inconsistency.

**Solution: Outbox Pattern**:

```
1. Within same DB transaction, save business data + event to outbox table
   BEGIN;
   INSERT INTO orders (id, status) VALUES (123, 'PENDING');
   INSERT INTO outbox (id, aggregate_id, event_type, payload, created_at) VALUES (uuid, 123, 'OrderCreated', '{...}', now());
   COMMIT; -- atomic, both saved or both not

2. Separate process (Outbox Relay) polls outbox table and publishes events to Kafka
   - Polling: SELECT * FROM outbox WHERE published=false ORDER BY created_at LIMIT 100
   - Publish to Kafka
   - Mark as published: UPDATE outbox SET published=true WHERE id=...

3. Or use CDC (Change Data Capture) via Debezium: Debezium captures outbox table changes from WAL and publishes to Kafka automatically, no polling
```

- Pros: Atomic (DB + event in same transaction), reliable (event not lost), eventual consistency
- Cons: Need outbox table, need relay process or Debezium, polling overhead, need cleanup of published events
- Use: Microservices event-driven, need reliable event publishing, e.g. OrderCreated event must be published if order saved

### 6.13 Strangler Fig Pattern (Migration from Monolith to Microservices)

**Problem**: How to migrate large monolith to microservices without big bang rewrite?

**Solution: Strangler Fig** (like strangler fig tree that grows around existing tree and eventually replaces it):

```
1. Identify bounded contexts in monolith (e.g. User, Order, Product)

2. Create new microservice for one bounded context (e.g. Product service) with its own DB

3. Put proxy (API Gateway or Facade) in front of monolith, route requests:
   - If request for Product, route to new Product microservice
   - Else route to monolith

4. Gradually move more functionality from monolith to microservices, proxy routes more to microservices

5. Data migration: Dual write or CDC or batch migration
   - Dual write: Write to both monolith DB and new service DB (risk inconsistency)
   - CDC: Debezium captures monolith DB changes and syncs to new service DB
   - Batch: Nightly batch job migrates data

6. Once all functionality migrated, monolith strangled (no traffic), decommission monolith

```

- Pros: Incremental, low risk, no big bang, can rollback via proxy, learn as you go
- Cons: Takes time (months), need proxy, dual write complexity, data migration complexity
- Use: Migration from monolith to microservices, legacy modernization
- Example: E-commerce monolith -> Extract Product service first (least coupled), then User, then Order, etc via gateway routing

### 6.14 Sidecar Pattern

**What**: Helper container alongside main container that provides supporting features (logging, proxy, monitoring, config), sidecar shares same pod (K8s) with main, same lifecycle

**Examples**:
- Istio Envoy sidecar: Handles mTLS, traffic management, observability for main service
- Fluentd/Fluent Bit sidecar: Collects logs from main and sends to Elasticsearch/Loki
- Config sidecar: Watches config and reloads main when config changes

**Pros**: Separation of concerns (main focuses on business, sidecar on infra), reusability (same sidecar for many services), language agnostic (sidecar can be Go while main is Java)

**Cons**: Resource overhead (sidecar CPU/memory), latency overhead (extra hop if proxy), complexity

**Use**: Service mesh, logging, monitoring, config

```yaml
# K8s pod with sidecar
apiVersion: v1
kind: Pod
metadata: { name: myapp }
spec:
  containers:
  - name: myapp
    image: myapp:1.0
    ports: [{ containerPort: 8080 }]
  - name: envoy-sidecar
    image: envoyproxy/envoy:v1.28
    ports: [{ containerPort: 15001 }]
  - name: fluentbit-sidecar
    image: fluent/fluent-bit:2.1
```

### 6.15 Ambassador Pattern

**What**: Helper that sends requests on behalf of main, like sidecar but for outbound, ambassador handles connection to external services (e.g. DB, cache, queue) with retries, circuit breaker, discovery

**Example**: Main app talks to localhost ambassador, ambassador talks to Redis cluster with sharding, discovery, retries, main doesn't know Redis cluster details

**Pros**: Main simple, ambassador handles complexity, language agnostic

### 6.16 Adapter Pattern (Infrastructure)

**What**: Adapter converts one interface to another, e.g. legacy system with different API, adapter translates

**Example**: New system expects REST JSON, legacy system provides SOAP XML, adapter converts REST to SOAP and SOAP to REST, new system doesn't know legacy

### 6.17 BFF (Backend for Frontend) Pattern

**What**: Separate backend per frontend (Web BFF, Mobile BFF, IoT BFF), each BFF tailored to frontend needs, aggregates microservices, returns only needed fields, handles auth, etc

**Why**: Web needs more data (large screen), Mobile needs less data (small screen, slow network), IoT needs even less, one generic API returns too much for mobile (over-fetching) or too little for web (under-fetching)

**Architecture**:
```
Web Client -> Web BFF (returns detailed data, e.g. user with orders + recommendations) -> Microservices
Mobile Client -> Mobile BFF (returns minimal data, e.g. user with only recent orders) -> Microservices
IoT Client -> IoT BFF (returns tiny data)
```

**Pros**: Optimized per frontend, avoids over/under-fetching, team autonomy (frontend team owns BFF), can use GraphQL for BFF aggregation

**Cons**: More BFFs to maintain, duplication, need coordination

**Use**: Multiple frontends (web, mobile, IoT) with different needs, e.g. e-commerce web vs mobile app

**Tools**: GraphQL Federation for BFF, or REST BFF

### 6.18 API Gateway Pattern

**What**: Single entry point for all clients, handles cross-cutting concerns: Auth, Rate Limiting, Routing, Aggregation, Transformation, Caching, Logging, Monitoring, WAF

**Pros**: Centralized cross-cutting, simplifies clients (one endpoint), can aggregate multiple microservices into one response, protocol translation (REST to gRPC)

**Cons**: Single point failure (need HA), bottleneck (need scaling), complexity, adds latency

**Tools**: Kong (open source, plugins), AWS API Gateway (managed), Apigee (enterprise), NGINX, Spring Cloud Gateway, Zuul

### 6.19 Database per Service + Shared Database + CQRS (Recap with More)

Already covered but add more on **API Composition vs CQRS**:

- **API Composition**: API Gateway calls multiple services (via REST/gRPC) and joins data in memory, e.g. GET /users/{id}/dashboard calls user-service + order-service + payment-service parallel via Promise.all and returns combined
  - Pros: Simple, no data duplication
  - Cons: Multiple calls, latency (sum of all), if one service slow whole API slow, need handle partial failures

- **CQRS**: Separate read model denormalized, e.g. Elasticsearch document contains user + orders + payments denormalized, single query fast
  - Pros: Fast single query, optimized
  - Cons: Duplication, eventual consistency, need sync via CDC/events

**When to use which**:
- API Composition for low QPS, simple joins, need fresh data
- CQRS for high QPS, complex queries, search, reporting, need fast

---

## 7. Distributed Systems Patterns Expanded

### 7.1 Consistent Hashing Deep Dive

**Problem**: Normal hashing hash(key) % N, when N changes (add/remove node) most keys remap (K keys, N nodes, when N->N+1, ~K*(N/(N+1)) keys remap, almost all), causing cache miss storm

**Solution: Consistent Hashing**:

- Hash both nodes and keys onto ring (0 to 2^32-1), e.g. hash(node IP) -> position on ring, hash(key) -> position, key assigned to next node clockwise (first node with position >= key position)
- When node added/removed, only K/N keys remap (only keys between new node and previous node), minimal

**Virtual Nodes**: To balance uneven distribution (nodes random positions may cause uneven), each physical node has many virtual nodes (e.g. 100 virtual nodes per physical), virtual nodes spread evenly, better balance

**Use**: Distributed cache (Redis Cluster, Memcached), DynamoDB, Cassandra, CDN, load balancing, sharding

**Example**: 3 nodes A,B,C on ring, keys K1,K2,K3,K4 hashed, K1 assigned to A (next clockwise), K2 to B, etc. Add node D between A and B, only keys that were assigned to B and now between A and D move to D, others stay.

### 7.2 CAP Theorem & PACELC Detailed

**CAP**: Consistency, Availability, Partition Tolerance - pick 2, in distributed system partition will happen (P), so choose A or C when partition

- **CP**: Consistent but may be unavailable during partition (e.g. MongoDB primary, HBase, Zookeeper, etcd - if partition, minority partition unavailable to keep consistency)
- **AP**: Available but eventual consistency during partition (e.g. Cassandra, DynamoDB, CouchDB - both partitions available but may have conflicting writes, need conflict resolution)
- **CA**: Single node RDBMS (MySQL single) - consistent and available but not partition tolerant (if partition, not distributed, so CA only for single node)

**PACELC**: Extension of CAP: If Partition, choose A/C, Else choose Latency/Consistency

- **PA/EL**: If Partition choose Availability, Else choose Latency (e.g. DynamoDB, Cassandra - available during partition, low latency otherwise)
- **PC/EC**: If Partition choose Consistency, Else choose Consistency (e.g. HBase, Bigtable - consistent during partition and otherwise)
- **PA/EC**: If Partition choose Availability, Else choose Consistency (e.g. MongoDB - available during partition? Actually Mongo chooses consistency during partition, so PC/EC, but some configs PA/EC)
- **PC/EL**: If Partition choose Consistency, Else choose Latency (e.g. PNUTS)

**For SDE3**: Must mention PACELC, not just CAP, shows deeper understanding

### 7.3 Consensus: Paxos & Raft

**Problem**: How to agree on value in distributed system with failures? E.g. elect leader, agree on log

**Paxos**: Old, complex, hard to understand, but proven, used in many systems (Google Chubby, etc)

**Raft**: Newer (2013), simpler to understand than Paxos, used in etcd, Consul, CockroachDB, TiDB

- Raft: Leader election, log replication, safety
- Nodes: Follower, Candidate, Leader
- Leader election: If follower doesn't hear from leader for timeout, becomes candidate, requests votes, if majority votes becomes leader
- Log replication: Leader appends log entries, replicates to followers, commits when majority ack, then applies to state machine
- Pros: Understandable, proven, used in many production systems
- Cons: Leader bottleneck, not as fast as Paxos variants

**Use**: etcd (K8s uses etcd for cluster state, Raft), Consul, CockroachDB, TiDB

### 7.4 Gossip Protocol

**What**: Nodes periodically exchange info with random nodes, like gossip, eventually all nodes know, scalable, fault tolerant, no central coordinator

**Use**: Cassandra (gossip for membership, failure detection), Consul (gossip), DynamoDB, Redis Cluster

**How**: Each node has list of nodes with heartbeat, every second picks random node and exchanges list, merges, detects failures if heartbeat not updated for time

### 7.5 Leader Election

**What**: Choose one node as leader among many, leader handles writes, coordinates, followers replicate

**Algorithms**: Raft, Paxos, Bully algorithm (highest ID wins), Ring algorithm

**Use**: K8s controller manager leader election, DB primary election, Kafka controller election

---

## 8. More Architectures List

### 8.1 Hexagonal vs Clean vs Onion - Differences

- **Hexagonal**: Focus on ports and adapters, core + ports + adapters, no layers, just core and adapters
- **Clean**: Layers with dependency rule inward, entities -> use cases -> interface adapters -> frameworks, more layered than hexagonal
- **Onion**: Similar to clean but with domain at center, domain services, application services, infrastructure outer, more emphasis on domain
- All three similar goal: Core independent, testable, framework independent, but different layering

### 8.2 Microservices vs Modular Monolith vs Monolith - When to Use Detailed

**Start with Monolith or Modular Monolith if**:
- Team <10, startup early, need fast MVP (2-3 months)
- Domain not well understood yet (need to explore, DDD not clear)
- No DevOps maturity (no K8s, CI/CD)
- Scaling needs low (100 RPS)
- Want to avoid distributed complexity early (over-engineering microservices early is anti-pattern)

**Move to Microservices when**:
- Team 20+, many teams, need autonomy, independent deploys
- Domain well understood, bounded contexts clear via DDD
- Need independent scaling (search 10x more than user)
- DevOps mature (K8s, CI/CD, monitoring, tracing)
- Pain of monolith: Long build times, deployment conflicts, scaling whole app for one module, team conflicts

**Modular Monolith as Middle Ground**:
- Team 10-20, some scaling needs, want to avoid microservices complexity but want modularity
- Modules with strict boundaries, own DB schemas, communicate via events, deployed as one but can split later easily
- Tools: Spring Modulith, Service Weaver
- **Recommended for 2024-25**: Many companies moving back from microservices to modular monolith for simplicity, or starting with modular monolith then split to microservices as needed (evolutionary)

### 8.3 Cell-Based Architecture Detailed (AWS)

- **Cell**: Isolated deployment unit handling subset of customers (e.g. 5% customers per cell), cells independent, no shared state, each cell has own DB, cache, queue, services
- **Control Plane**: Manages cells, routing, assignment, monitoring, deployment
- **Data Plane**: Cells handle customer traffic
- **Routing**: Customer -> Cell Router (based on customer ID hash) -> Cell (e.g. customer 123 -> hash -> cell 2)
- **Pros**: Blast radius reduction (failure in one cell only affects 5% customers, not 100%), scalability (add cells), fault isolation, canary per cell (deploy to one cell first), compliance (data residency per cell per region)
- **Cons**: Complexity (cell routing, assignment, cross-cell queries hard), operational overhead (many cells to manage), data partitioning per cell
- **Use**: Large SaaS needing high availability 99.99%+, AWS (many AWS services cell-based), Slack (workspaces per cell), Stripe
- **Example**: Slack: Each cell handles subset of workspaces (e.g. 10k workspaces per cell), if cell fails only those workspaces affected, other cells fine, control plane routes workspace to cell via mapping stored in DynamoDB

### 8.4 Service Mesh Detailed Comparison: Istio vs Linkerd vs Cilium

| Feature | Istio | Linkerd | Cilium (eBPF) |
|---------|-------|---------|---------------|
| **Architecture** | Sidecar Envoy per pod + Istiod control plane | Sidecar linkerd2-proxy (Rust) per pod + control plane | eBPF programs in kernel, no sidecar (or optional sidecar), Cilium agent per node |
| **Performance** | Good but sidecar overhead 2-5ms latency, 100MB memory per pod | Better than Istio (Rust proxy faster, smaller), 10MB memory | Best (no sidecar hop, eBPF in kernel, 2x faster than Istio) |
| **Features** | Most features: Traffic management (canary, retries, timeouts, fault injection, mirroring), Security (mTLS, authZ), Observability (metrics, traces, logs) | Fewer features than Istio but enough for most, simpler | Networking + Security + Observability + Service Mesh, eBPF based, high perf |
| **Complexity** | High (many CRDs: VirtualService, DestinationRule, Gateway, etc) | Low (simpler, fewer CRDs) | Medium (eBPF concepts) |
| **Maturity** | Most mature, many prod users | Mature, simpler | Newer but growing fast, used by many (e.g. Google GKE uses Cilium) |
| **Use** | Large microservices needing all features | Small-medium microservices wanting simplicity + perf | High perf needs, want no sidecar, eBPF, future |
| **Trend 2025** | Still popular but complexity concerns | Growing for simplicity | Fastest growing for perf + no sidecar |

**Recommendation 2025-26**: For new projects, consider Cilium for performance + no sidecar, or Linkerd for simplicity, Istio if need all features and team can handle complexity

---

## 9. Architecture Anti-Patterns to Avoid

- **Big Ball of Mud**: No architecture, spaghetti code, tight coupling, no separation
- **Golden Hammer**: Using same architecture for all problems (e.g. microservices for everything even simple CRUD)
- **Vendor Lock-in**: Using proprietary features that lock to one cloud/vendor
- **Shared Database for Microservices**: Tight coupling, anti-pattern
- **Distributed Monolith**: Microservices that are tightly coupled via sync calls, need to deploy together, no autonomy, worst of both monolith and microservices
- **Over-engineering**: Using microservices, event sourcing, CQRS for simple CRUD that doesn't need
- **Under-engineering**: Monolith for large team with independent scaling needs, will pain later
- **No Observability**: No metrics, logs, traces, can't debug prod
- **No Automation**: Manual deploys, manual scaling, toil high

---

This expanded file now has 35+ architectures with deep dives, decision matrices, trending 2025-26, and anti-patterns for SDE3 mastery.
