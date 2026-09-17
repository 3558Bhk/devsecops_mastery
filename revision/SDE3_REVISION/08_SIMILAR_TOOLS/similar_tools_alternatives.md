# Similar Tools & Alternatives - Must Know for SDE3

## CI/CD Tools (Jenkins Alternatives)
| Tool | Type | Pros | Cons |
|------|------|------|------|
| **Jenkins** | Self-hosted | Highly customizable, plugins 1800+, free | Maintenance heavy, old UI |
| **GitHub Actions** | SaaS | Native GitHub, YAML, marketplace, free tier | Vendor lock GitHub |
| **GitLab CI** | SaaS/Self | Integrated with GitLab, Auto DevOps | Heavy |
| **CircleCI** | SaaS | Fast, Docker native, parallelism | Costly |
| **TeamCity** | Self | JetBrains, powerful, good UI | Paid |
| **Azure DevOps** | SaaS | Microsoft stack, boards + pipelines | Complex |
| **Bamboo** | Self | Atlassian integration | Paid |
| **ArgoCD** | GitOps CD | Kubernetes native, declarative | Only CD, not CI |
| **Tekton** | K8s native CI/CD | Cloud native, CRDs | Young |

**Interview Answer**: "We migrated from Jenkins to GitHub Actions for faster builds and less maintenance, but Jenkins still best for complex on-prem with custom plugins."

## Build Tools
- **Maven vs Gradle**: Maven XML convention, Gradle Groovy/Kotlin DSL faster, caching, incremental. Gradle preferred for Android, large projects.
- **npm vs yarn vs pnpm**: pnpm fastest disk efficient, yarn berry, npm default.

## Containerization & Orchestration
- **Docker vs Podman**: Podman daemonless, rootless, more secure
- **Kubernetes vs Docker Swarm vs Nomad**: K8s de facto, Swarm simple but dying, Nomad HashiCorp multi-workload
- **EKS vs GKE vs AKS**: GKE most mature K8s, EKS AWS integrated, AKS Azure

## Monitoring & Logging (Observability)
| Category | Tools |
|----------|-------|
| Metrics | Prometheus + Grafana, Datadog, New Relic, CloudWatch |
| Logging | ELK (Elasticsearch Logstash Kibana), EFK (Fluentd), Loki + Grafana, Splunk |
| Tracing | Jaeger, Zipkin, AWS X-Ray, OpenTelemetry |
| APM | Datadog, New Relic, AppDynamics |

**ELK vs EFK vs PLG**: EFK lighter than Logstash. PLG (Promtail Loki Grafana) cheaper than ELK for logs.

## Databases Alternatives
- **MySQL vs PostgreSQL**: PG more advanced (JSONB, GIS, extensions), MySQL simpler faster for read heavy. Both RDBMS.
- **MongoDB vs DynamoDB**: Mongo self-host or Atlas rich queries, Dynamo AWS managed serverless scale.
- **Redis vs Memcached**: Redis data structures, persistence, pub/sub. Memcached simple cache multi-threaded.

## Message Queues
- **Kafka vs RabbitMQ vs SQS**:
  - Kafka: High throughput streaming, replay, retention, ordered per partition, log based
  - RabbitMQ: Traditional queue, routing (direct, fanout), low latency, AMQP
  - SQS: AWS managed, no maintenance, but limited features

## IaC Tools
- **Terraform vs CloudFormation vs Pulumi vs Ansible**:
  - Terraform: Cloud agnostic, HCL, state file, most popular
  - CloudFormation: AWS only
  - Pulumi: Code in TS/Python
  - Ansible: Config management + IaC but procedural

## Version Control
- Git vs SVN vs Mercurial: Git distributed wins. GitHub vs GitLab vs Bitbucket.

## API Gateway
- Kong vs AWS API Gateway vs Apigee vs NGINX: Kong open source plugin rich, AWS managed serverless.

## Service Mesh
- Istio vs Linkerd vs Consul Connect: Istio feature rich complex, Linkerd lightweight fast.

## How to Answer "Similar Tools"?
Use STAR: Situation Task Action Result with comparison.
Example: "We evaluated Jenkins vs GitHub Actions vs GitLab CI on criteria: cost, maintenance, ecosystem, scalability. Chose GitHub Actions because... but kept Jenkins for legacy jobs requiring custom agents."

## Tool Selection Criteria for SDE3
1. Community & support
2. Learning curve
3. Cost (license + infra + maintenance)
4. Integration with existing stack
5. Scalability & HA
6. Security
