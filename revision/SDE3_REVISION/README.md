# SDE3 Interview Revision Pack - 2026 - COMPLETE EDITION

> Created: 2026-09-13 | Updated: Added 8 More Critical Folders | 4+ YOE | 58 Files | Quick Revision

## 📁 Complete Folder Structure (22 Folders - 58 Files)

### Original 13 Folders (Your List)

**01_JENKINS** - Jenkins Complete (4 files)
- `01_plugins.md` - Top 30 plugins, pipeline example
- `02_installation_steps.md` - Ubuntu, Docker, K8s Helm, WAR
- `03_port_number.md` - Jenkins ports + ALL important ports (MySQL 3306, PG 5432, Redis 6379, Kafka 9092 etc)
- `04_common_commands.md` - CLI, DSL

**02_STATUS_CODES** (1 file)
- `status_codes.md` - 1xx-5xx, 401 vs 403, 301 vs 302, 502 vs 504

**03_COMMANDS** (4 files)
- `linux_commands.md`, `git_commands.md`, `docker_commands.md`, `kubernetes_commands.md`

**04_API** (5 files)
- `rest_api.md`, `soap_api.md`, `graphql_api.md`, `grpc_api.md`, `api_comparison.md` - Decision matrix

**05_SECURITY** (3 files)
- `security_basics.md`, `authentication_authorization.md` (JWT, OAuth2, RBAC vs ABAC), `owasp_jwt_oauth.md`

**06_NETWORKING** (2 files)
- `networking_fundamentals.md` (OSI, TCP 3-way, HTTP/1.1 vs 2 vs 3, what happens when google.com)
- `frontend_backend_connections.md` (REST, WebSocket, SSE, Nginx reverse proxy, CORS)

**07_CLOUD_SERVICES** (2 files)
- `common_cloud_services.md` (AWS vs Azure vs GCP mapping), `aws_core.md` (EC2, S3, RDS, Lambda, SQS, EKS deep)

**08_SIMILAR_TOOLS** (1 file)
- `similar_tools_alternatives.md` - Jenkins vs GitHub Actions, Docker vs Podman, Kafka vs RabbitMQ vs SQS, Terraform vs CloudFormation

**09_TOOL_VERSIONS** (1 file)
- `tools_versions_4yoe.md` - Java 8->21, Node 14->22, Spring Boot 2.5->3.4, React 17->19, Jenkins 2.3xx->2.5xx, K8s 1.24->1.33, Valkey fork, OpenTofu

**10_ARCHITECTURES** (2 files)
- `types_architectures.md` (Monolith, Microservices, Event-Driven, Serverless, Hexagonal, CAP)
- `system_design_patterns.md` (API Gateway, Circuit Breaker, SAGA, CQRS, Outbox, BFF, 6-step method)

**11_DATABASES** (2 files)
- `types_databases.md` (SQL vs NoSQL Document/Key-Value/Wide-Column/Graph, Vector DB, NewSQL)
- `sql_vs_nosql_details.md` (ACID vs BASE, isolation levels, indexing B-Tree vs Hash, N+1, sharding)

**12_ERRORS** (1 file)
- `types_of_possible_errors.md` - Frontend, backend, DB, infra, HTTP, K8s (ImagePullBackOff, CrashLoopBackOff, OOMKilled), Jenkins, debugging checklist

**13_EXTRA_SDE3** (6 files)
- `microservices.md`, `caching_strategies.md`, `scalability_availability.md`, `messaging_queues.md`, `ci_cd_concepts.md`, `interview_questions.md`

---

### NEW - 9 Additional Critical Folders (Most Important Missing)

**14_SOLID_OOPS_PATTERNS** (3 files) - *MOST ASKED IN LLD*
- `solid_principles.md` - SRP, OCP, LSP, ISP, DIP with Java examples + interview story
- `oops_concepts.md` - 4 pillars, abstract vs interface, composition vs inheritance, immutable class
- `design_patterns.md` - Top 13 patterns: Singleton, Factory, Builder, Adapter, Decorator, Proxy, Facade, Observer, Strategy, Chain of Responsibility with real project examples

**15_OS_CONCURRENCY** (3 files) - *OS + Multithreading asked in every SDE3*
- `os_concepts.md` - Process vs Thread, scheduling, deadlock 4 conditions, paging, zombie vs orphan, C10K problem
- `multithreading_concurrency.md` - Thread lifecycle, ExecutorService, synchronized vs Lock, CountDownLatch vs CyclicBarrier vs Semaphore, ConcurrentHashMap, CompletableFuture, **Virtual Threads Java 21**
- `jvm_gc.md` - JVM memory (Heap Young/Old, Stack, Metaspace), GC types Serial/Parallel/G1/ZGC/Shenandoah, OOM types, tuning flags, memory leak detection

**16_JAVA_SPRINGBOOT** (3 files) - *Core for Java SDE3*
- `java_core.md` - Java 8 (streams, lambda, optional), 11 (var, HttpClient), 17 (records, sealed), 21 (virtual threads, pattern matching), HashMap internal, String pool
- `springboot_annotations.md` - All annotations @SpringBootApplication, @RestController, @Transactional, @Cacheable, AOP, Security, profiles, auto-configuration how it works, Boot 2->3 migration javax->jakarta
- `hibernate_jpa.md` - Entity lifecycle, Fetch LAZY vs EAGER, N+1 fix (JOIN FETCH, EntityGraph), caching L1/L2, dirty checking, optimistic locking @Version

**17_DSA** (2 files) - *Coding round*
- `dsa_patterns.md` - 15 patterns: Two Pointers, Sliding Window, Fast/Slow, Merge Intervals, Cyclic Sort, BFS, DFS, Two Heaps, Backtracking, Binary Search, Top K, K-way Merge, DP patterns + complexities + top 15 questions (LRU, etc)
- `algorithms.md` - Binary search variants, Quick/Merge sort, Dijkstra, Bellman-Ford, Topological Sort, Union-Find, LCA, DP examples, bit manipulation

**18_LLD_HLD** (3 files) - *Design rounds*
- `lld_questions.md` - LLD process, Parking Lot, Elevator, BookMyShow (concurrency seat locking), LRU Cache, Rate Limiter, Splitwise, etc with class diagrams + patterns
- `hld_designs.md` - HLD template 6 steps + 6 detailed designs: URL Shortener (Base62), Rate Limiter, Notification System, News Feed (Push vs Pull vs Hybrid for celebrity), Chat System (WebSocket + Redis pub/sub for cross-server), YouTube (HLS transcoding)
- `rate_limiter.md` - Deep dive: Fixed Window, Sliding Log, Sliding Counter, Token Bucket, Leaky Bucket + Redis Lua distributed implementation + Nginx + headers

**19_TESTING** (1 file)
- `testing_types.md` - Pyramid, Unit (JUnit+Mockito), Integration (Testcontainers), E2E (RestAssured), Contract (Pact), Performance (k6), TDD vs BDD, mock vs spy, FIRST principles, flaky tests

**20_OBSERVABILITY_SRE** (3 files) - *SDE3 must know*
- `monitoring_logging.md` - Metrics (Counter/Gauge/Histogram), RED/USE/Golden Signals, Prometheus + Grafana + PromQL, structured logging JSON + correlation ID, ELK/EFK/PLG, tracing OpenTelemetry + Jaeger, profiling
- `sre_concepts.md` - SLA vs SLO vs SLI, Error Budget + Burn Rate, Toil, MTTR/MTBF, incident lifecycle + blameless post-mortem, DORA metrics, chaos engineering
- `load_balancing_cdn.md` - L4 vs L7, algorithms (Round Robin, Least Connections, Consistent Hashing), Nginx, ALB vs NLB, Forward vs Reverse proxy, CDN pull vs push, invalidation, CloudFront

**21_PERFORMANCE_EXTRA** (3 files)
- `performance_tuning.md` - Where bottleneck? Java/Node/DB/Caching/Network tuning, Linux commands top/iostat, K8s requests/limits/HPA, load testing k6, checklist
- `git_workflows.md` - GitFlow vs GitHub Flow vs Trunk Based Development, conventional commits, PR best practices, rebase vs merge vs squash, monorepo vs polyrepo
- `behavioral.md` - STAR method, 9 common Q with sample answers (challenging bug, conflict, mentoring, failure, why SDE3), Amazon LP, questions to ask interviewer

**22_CHEATSHEETS** (2 files) - *Last night revision*
- `cheatsheet_one_pager.md` - 25 one-pagers: System design steps, API/DB decision, cache patterns, CAP, ports, status codes, SOLID, patterns, K8s debugging, SRE, etc
- `interview_day_checklist.md` - Before interview checklist, how to explain projects, design round structure (35 min), LLD structure, coding structure, behavioral, mistakes to avoid, numbers to memorize

---

## 🚀 How to Use (Updated)

### 3-Day Plan

**Day 1 - Core Backend (4 hours)**
- 01_JENKINS + 02_STATUS_CODES + 03_PORTS (1h)
- 04_API + 05_SECURITY (1h)
- 16_JAVA_SPRINGBOOT (1h)
- 14_SOLID_OOPS_PATTERNS (1h)

**Day 2 - System Design (5 hours)**
- 06_NETWORKING + 10_ARCHITECTURES + 11_DATABASES (1.5h)
- 18_LLD_HLD (2h) - Practice 2 HLDs aloud
- 15_OS_CONCURRENCY + 20_OBSERVABILITY_SRE (1.5h)

**Day 3 - DevOps + Coding + Behavioral (4 hours)**
- 03_COMMANDS + 07_CLOUD + 08_TOOLS + 09_VERSIONS (1h)
- 17_DSA (1h) - Practice LRU, Two Sum, etc
- 19_TESTING + 21_PERFORMANCE_EXTRA (1h)
- 22_CHEATSHEETS + 12_ERRORS + 13_EXTRA (1h)

### Last Night - Only Cheatsheets
- Read `22_CHEATSHEETS/cheatsheet_one_pager.md` 3 times
- Read `22_CHEATSHEETS/interview_day_checklist.md`
- Practice 1 HLD + 1 LLD aloud 30 min each

---

## 💡 What Was Missing & Now Added (Why Important)

| Missing Topic | Why Critical for SDE3 | File |
|---------------|----------------------|------|
| SOLID + OOPS + Design Patterns | LLD round 100% asks, shows clean code | 14_* |
| OS + Concurrency + Virtual Threads | SDE3 threading Q, Java 21 virtual threads hot topic 2025-26 | 15_* |
| JVM GC | Java SDE3 must know heap tuning, OOM debugging | 15_jvm_gc.md |
| Java 8/11/17/21 + Spring Boot | Core for Java roles, migration javax->jakarta asked | 16_* |
| DSA Patterns | Coding round still exists for SDE3, 15 patterns enough | 17_* |
| LLD Questions (Parking Lot etc) | LLD round separate from HLD, need class diagrams | 18_lld_questions.md |
| HLD Detailed (News Feed, Chat) | System design deep dive, celebrity problem, WebSocket scaling | 18_hld_designs.md |
| Rate Limiter Deep Dive | Most asked HLD + implementation | 18_rate_limiter.md |
| Testing (Testcontainers, Pact) | SDE3 owns quality, contract testing for microservices | 19_* |
| Observability (Prometheus, ELK, Jaeger) | SDE3 must mention monitoring in every design | 20_monitoring_logging.md |
| SRE (SLO/SLI/Error Budget) | SDE3 on-call, error budget policy, blameless post-mortem | 20_sre_concepts.md |
| Load Balancing + CDN | How to scale, consistent hashing asked | 20_load_balancing_cdn.md |
| Performance Tuning | How to reduce P95 from 2s to 200ms - systematic | 21_performance_tuning.md |
| Git Workflows (Trunk Based) | Elite teams use trunk based + feature flags | 21_git_workflows.md |
| Behavioral STAR | SDE3 leadership round 50% weightage | 21_behavioral.md |
| One-Pager Cheatsheets | Last minute quick recall | 22_* |

---

## 📌 Quick References (Memorize)

**Ports**: Jenkins 8080/50000, MySQL 3306, PG 5432, Mongo 27017, Redis 6379, Kafka 9092, ZK 2181, ES 9200, HTTP 80, HTTPS 443, SSH 22

**Status**: 200 OK, 201 Created, 204 No Content, 301 Permanent, 302 Temp, 304 Not Modified, 400 Bad, 401 Unauthorized, 403 Forbidden, 404 Not Found, 409 Conflict, 429 Too Many, 500 Internal, 502 Bad Gateway, 503 Unavailable, 504 Timeout

**Java Story**: Started Java 8/11 (streams, var), Spring Boot 2.5-2.7 -> Migrated to Java 17 LTS (records) + Spring Boot 3.x (jakarta) -> Now exploring Java 21 virtual threads + Spring Boot 3.2 virtual threads enabled

**System Design Steps**: Requirements -> Estimation -> HLD -> Deep Dive -> Bottlenecks -> Monitoring

---

## 📊 Stats

- **Total Folders**: 22
- **Total Files**: 58
- **Size**: ~400KB text = ~2-3 hours reading, but designed for quick lookup
- **Coverage**: Backend + DevOps + Cloud + System Design + LLD + DSA + Behavioral = 100% SDE3

Good luck from Vijayawada! 🚀

> Tip: Don't try to memorize all 58 files. Use README plan, focus on your weak areas, and keep cheatsheet one-pager open during interview prep.
