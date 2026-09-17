# Interview Questions — SDE III · DevOps · DevSecOps · Platform · SRE · Cloud

**Every topic = one folder = one `README.md`, split into three tiers:**

| Tier | Marked | What it tests |
|---|---|---|
| **Basic** | 🟢 | Definitions, "do you actually know this" — must be instant, no hesitation |
| **Advanced** | 🔵 | Trade-offs, internals, "why not the other option" — this is where SDE III is decided |
| **Scenario** | 🔴 | War-room problems, design-from-scratch, "walk me through it" — tests judgement |

> SDE III / Senior interviews are **not** won by knowing more facts. They're won by: naming the trade-off, quantifying it, and saying what you'd do with the information you have. Every answer below is written in that shape.

---

## Index

### Core engineering (SDE III)
| # | Folder | Covers |
|---|---|---|
| 00 | [`00-How-To-Use`](00-How-To-Use/README.md) | Answering frameworks, what the level actually means, scoring yourself |
| 01 | [`01-CS-Fundamentals`](01-CS-Fundamentals/README.md) | OS, Linux internals, processes/threads, DNS, HTTP, TLS, TCP |
| 02 | [`02-DSA-and-Coding`](02-DSA-and-Coding/README.md) | Patterns, complexity, 20 worked problems with solutions |
| 03 | [`03-System-Design-HLD`](03-System-Design-HLD/README.md) | Scale, CAP, caching, queues, sharding + 6 full designs |
| 04 | [`04-Low-Level-Design`](04-Low-Level-Design/README.md) | OOP, patterns, LLD problems (rate limiter, parking lot, cache) |
| 05 | [`05-Programming-Languages`](05-Programming-Languages/README.md) | Go, Python, Java — concurrency, memory, idioms, gotchas |

### Platform / infra
| # | Folder | Covers |
|---|---|---|
| 06 | [`06-Docker-and-Containers`](06-Docker-and-Containers/README.md) | Images, layers, runtimes, isolation, security, debugging |
| 07 | [`07-Kubernetes`](07-Kubernetes/README.md) | Control plane, controllers, networking, storage, operators, security |
| 08 | [`08-CI-CD-and-GitOps`](08-CI-CD-and-GitOps/README.md) | Pipelines, Argo CD/Flux, progressive delivery, supply chain |
| 09 | [`09-IaC-Terraform`](09-IaC-Terraform/README.md) | State, modules, drift, import, testing, Crossplane/Pulumi |
| 10 | [`10-Observability`](10-Observability/README.md) | Metrics/logs/traces, Prometheus, SLO alerting → pairs with your *Monitoring and Alerting* folder |
| 11 | [`11-SRE-and-Reliability`](11-SRE-and-Reliability/README.md) | SLO/error budgets, incident command, toil, capacity, postmortems |

### Cloud & security
| # | Folder | Covers |
|---|---|---|
| 12 | [`12-Cloud-AWS`](12-Cloud-AWS/README.md) | EC2/ECS/EKS, VPC, IAM, S3, RDS, Lambda, cost, well-architected |
| 13 | [`13-Cloud-Multi-Azure-GCP`](13-Cloud-Multi-Azure-GCP/README.md) | Azure & GCP equivalents, multi-cloud strategy, portability |
| 14 | [`14-DevSecOps-and-Security`](14-DevSecOps-and-Security/README.md) | Shift-left, SAST/DAST/SCA, secrets, supply chain, OWASP, compliance |
| 15 | [`15-Platform-Engineering`](15-Platform-Engineering/README.md) | IDP, golden paths, Backstage, self-service, multi-tenancy, platform-as-product |

### Data, network, people
| # | Folder | Covers |
|---|---|---|
| 16 | [`16-Databases-and-Storage`](16-Databases-and-Storage/README.md) | SQL internals, indexes, replication, NoSQL, caching, object storage |
| 17 | [`17-Networking-and-Service-Mesh`](17-Networking-and-Service-Mesh/README.md) | LBs, ingress, DNS, mesh, mTLS, egress, CDNs |
| 18 | [`18-Behavioral-and-Leadership`](18-Behavioral-and-Leadership/README.md) | SDE III behavioural: influence, ambiguity, conflict, mentoring |
| 19 | [`19-Scenario-War-Rooms`](19-Scenario-War-Rooms/README.md) | 7 long cross-domain war rooms with full model answers + follow-ups |
| 20 | [`20-Rapid-Fire-One-Liners`](20-Rapid-Fire-One-Liners/README.md) | 320 one-line Q&A across every topic, for the last 24 hours |
| 21 | [`21-Questions-To-Ask-Them`](21-Questions-To-Ask-Them/README.md) | Questions that make you look senior + red-flag detectors |

---

## The 6-week plan

| Week | Focus | Daily |
|---|---|---|
| **1** | `00`, `01`, `02` | 1 h reading aloud + 2 coding problems |
| **2** | `03`, `04`, `05` | 1 full system design out loud per day (whiteboard, timed 40 min) |
| **3** | `06`, `07`, `16` | Read + run every command in a kind/minikube cluster |
| **4** | `08`, `09`, `10`, `11` | Run the labs in your *Monitoring and Alerting* folder |
| **5** | `12`, `13`, `14`, `15`, `17` | Cloud + security + platform |
| **6** | `18`, `19`, `20`, `21` | Behavioural stories written down; mock interviews; rapid fire |

> **Short on time?** The 2-week version: `00`, `03`, `07`, `11`, `19`, `20` plus `18` (write your 10 STAR-L stories). Those six carry most of the weight for a DevOps/SRE/platform senior loop — then add `12` or `14` depending on the role.

**Non-negotiable habit:** say every answer **out loud**. Reading an answer and producing it under pressure are different skills. Record yourself on your phone for the system-design and behavioural ones — it is uncomfortable and it works.

---

## How each topic file is structured

```
# Topic
## 🟢 Basic          — 8-15 questions, short answers
## 🔵 Advanced       — 8-15 questions, trade-offs and internals
## 🔴 Scenario       — 3-8 questions, full worked answers
## Red flags         — answers that will cost you the level
## Rapid recall      — the 10 things to re-read the morning of
```

---

## The four answer frameworks (learn these first)

**1. Trade-off answer** (for "why X not Y?")
> "X gives you A, at the cost of B. I'd choose X when [condition], and Y when [other condition]. At my last place we picked X because [evidence], and revisited it when [trigger]."

**2. Design answer** (for "design a system")
> Requirements → scale numbers → API → data model → high-level boxes → walk one request end-to-end → find the bottleneck → scale that component → failure modes → ops/observability. **Always start by asking about scale.**

**3. Incident answer** (for "production is broken")
> Stabilise first (mitigate, don't root-cause) → measure → hypothesise → test the cheapest hypothesis → communicate → resolve → postmortem → systemic fix. **Say "I'd mitigate before I debug" explicitly — it's the senior signal.**

**4. Behavioural answer** (STAR-L)
> Situation (2 sentences) → Task → Action (**the most detail; use "I", not "we"**) → Result (numbers) → Learning (what you'd do differently).

---

## What actually separates SDE III from SDE II

| SDE II says | SDE III says |
|---|---|
| "We'd use Kafka for that." | "We'd use Kafka if we need replay and multiple consumers with independent offsets; if it's just decoupling two services, SQS is a tenth of the operational cost. What's the message volume?" |
| "Add caching." | "Cache at the CDN for anonymous reads, in Redis for shared hot keys with a 30s TTL, and accept stale-on-error. The hard part is invalidation — I'd use write-through for this entity because reads dominate 100:1." |
| "It's a Kubernetes problem." | "Let me check the layers: is it the app, the pod, the node, the network, or the control plane? Here's how I'd narrow it in five commands." |
| "I fixed the bug." | "I fixed the bug, then asked why three layers of defence all missed it, and added the check that makes this class of bug impossible." |
| "We should do X." | "Here's X, its cost, what it blocks, and who needs to agree. I'd pilot it with one team for two weeks and measure Y before asking anyone to adopt it." |

**Scope, ambiguity, and influence are the actual axes.** Technical depth is table stakes.

---

## Companion material

This folder pairs with **`Monitoring and Alerting/`** in your workspace. Topics `10-Observability` and `11-SRE-and-Reliability` assume you've read it, and its runnable docker-compose labs (Prometheus 3.14, Alertmanager 0.34, Grafana 13) are the fastest way to turn the PromQL, alerting-rule and SLO burn-rate answers from *recognition* into *recall*. War Rooms 1 and 4 in `19-Scenario-War-Rooms` lean on the same material. **Do the labs — "I built it and broke it on purpose" is a better answer than any definition.**

---

*Versions referenced and checked while writing: Kubernetes 1.37 (supported 1.35–1.37), Docker Engine 29.x / containerd 2.2.x, Terraform 1.15.x vs OpenTofu 1.12.2, Argo CD 3.3–3.5, Prometheus 3.14 / Alertmanager 0.34 / Grafana 13, Go 1.2x, Python 3.12+, AWS/Azure/GCP service names as of mid-2026. Product versions and cloud service names change; the mechanisms and trade-offs don't.*
