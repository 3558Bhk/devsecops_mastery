# Tools Versions - 4 Years Experience to Recent (2022-2026)

This is what to say in interview when asked "What versions have you used?"

## Languages

### Java
- **Java 8 (2014)** - Lambdas, Streams - Still many legacy projects
- **Java 11 (2018 LTS)** - Most common in 2022-2023 projects, var, HttpClient
- **Java 17 (2021 LTS)** - Current standard 2024-2025, records, sealed classes, pattern matching
- **Java 21 (2023 LTS)** - Latest 2025-2026, virtual threads (Project Loom), huge for concurrency
- **Say**: "Migrated from Java 8 to 11 to 17, now using 17 and exploring 21 virtual threads for high throughput services"

### Node.js
- **14 (2020 LTS)** - Common in 2021-22
- **16 (2021 LTS)** - Used in 2022-23
- **18 (2022 LTS)** - Used 2023-24, fetch native, Node test runner
- **20 (2023 LTS)** - Used 2024-25, permission model
- **22 (2024 LTS)** - Current 2025-26
- **Say**: "Used Node 16, 18, 20. Latest project on Node 20 with ESM"

### Python
- **3.8, 3.9** - 2020-22
- **3.10 (2021)** - match statement - 2022-23
- **3.11 (2022)** - 10-60% faster - 2023-24
- **3.12 (2023)** - Improved f-strings - 2024-25
- **3.13 (2024)** - Free-threaded experimental

## Frameworks

### Spring Boot
- **2.5.x, 2.6.x, 2.7.x** - 2021-2023, Java 8/11 baseline
- **3.0.x (Nov 2022)** - Jakarta EE, Java 17 baseline - major migration 2023-24
- **3.1.x, 3.2.x, 3.3.x, 3.4.x (2024-2025)** - Java 17/21, virtual threads, GraalVM native
- **Say**: "Migrated Spring Boot 2.7 to 3.2, handled javax->jakarta namespace change"

### React
- **17 (2020)** - No major changes
- **18 (2022)** - Concurrent features, Suspense, useId, automatic batching - major
- **19 (2024 Dec)** - Server Components stable, Actions
- **Say**: "Used React 17, 18 with hooks, now React 19 with Server Components"

### Angular
- **12,13,14 (2021-22)** - Ivy
- **15,16,17 (2022-24)** - Standalone components (big), signals
- **18,19 (2024-25)** - Signals stable, SSR improvements

## DevOps Tools

### Jenkins
- **2.300+ to 2.440** - 2022-2024
- **2.479+ (2024-2025)** - Requires Java 17+, major
- **2.500+ LTS (2025-26)** - Java 21 support
- **Say**: "Used Jenkins 2.387 LTS with Java 11, upgraded to 2.479 LTS requiring Java 17"

### Docker
- **20.10.x** - 2021-22 common
- **23.0, 24.0, 25.0, 26.0, 27.0** - 2023-2025
- **28.0 (2025)** - Latest
- BuildKit stable

### Kubernetes
- **1.24, 1.25, 1.26** - 2022-23 (dockershim removed in 1.24)
- **1.27, 1.28, 1.29, 1.30, 1.31** - 2023-2025
- **1.32, 1.33 (2025-26)** - Current
- **Say**: "Used K8s 1.26 to 1.30 on EKS, managed upgrades, handled dockershim removal migrating to containerd"

### Terraform
- **0.15, 1.0, 1.1, 1.2, 1.3, 1.4, 1.5** - 2021-2023
- **1.6, 1.7, 1.8, 1.9 (2024-25)** - Import blocks, test framework
- **OpenTofu fork after HashiCorp BSL license change (2023)**

## Databases

### MySQL
- **5.7** - Still legacy till 2023 EOL Oct 2023
- **8.0 (2018) to 8.4 LTS (2024)** - Current standard

### PostgreSQL
- **12,13,14** - 2020-22
- **15,16,17 (2022-2024)** - Performance improvements
- **Say**: "Used PG 14 to 16, used JSONB, partitioning"

### MongoDB
- **4.4, 5.0, 6.0, 7.0, 8.0 (2024)**
- Atlas versions

### Redis
- **6.2, 7.0, 7.2, 7.4**
- License change to RSALv2/SSPL in 2024, Valkey fork created - mention in interview shows awareness

### Kafka
- **2.8, 3.0 (ZooKeeper), 3.3, 3.6, 3.8, 4.0 (2024) KRaft no ZooKeeper**
- **Say**: "Migrated Kafka from ZooKeeper to KRaft in 3.7"

## Cloud
- **AWS**: Always latest but mention EKS 1.30, Lambda Node18/20 runtime, RDS PG 16
- **Tools**: Helm 3.12-3.16, ArgoCD 2.10-2.13

## How to Answer in Interview
Don't just list versions. Say:
"I have 4 years experience, started with Java 8/Spring Boot 2.5/Node 14/K8s 1.24/Jenkins 2.3xx. Over time migrated to Java 17/Spring Boot 3.2/Node 20/K8s 1.30/Jenkins 2.479 requiring Java 17. Aware of latest Java 21 virtual threads, React 19, K8s 1.32. I follow LTS versions for production stability."

This shows growth, migration experience, and awareness of breaking changes.
