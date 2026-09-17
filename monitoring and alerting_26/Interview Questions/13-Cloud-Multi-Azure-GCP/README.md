# 13 · Cloud — Azure, GCP & Multi-Cloud

Ask yourself which cloud the role actually uses, and go deep there. But **every** cloud interview includes the comparison question, and platform/SRE roles increasingly span two or three. This file gives you: the Azure and GCP essentials, a **service-mapping table**, the multi-cloud/hybrid debate, and the cross-cloud questions.

*(AWS depth lives in [`12-Cloud-AWS`](../12-Cloud-AWS/README.md).)*

---

## 🟢 The service map — learn this first

Being able to translate between clouds is the single most useful cross-cloud skill, and it's an easy interview win.

| Capability | **AWS** | **Azure** | **GCP** |
|---|---|---|---|
| VM | EC2 | Virtual Machines | Compute Engine |
| Container orchestrator (managed K8s) | EKS | **AKS** | **GKE** (the original) |
| Container service (non-K8s) | ECS / Fargate | **Container Apps** / Container Instances (ACI) | **Cloud Run** |
| Serverless functions | Lambda | **Azure Functions** | **Cloud Functions** / Cloud Run jobs |
| Object storage | S3 | **Blob Storage** | **Cloud Storage** |
| Block storage | EBS | **Managed Disks** | **Persistent Disk / Hyperdisk** |
| File storage | EFS / FSx | **Azure Files / NetApp** | **Filestore** |
| Relational DB | RDS / Aurora | **Azure SQL / Database for PostgreSQL Flexible Server** | **Cloud SQL / AlloyDB / Cloud Spanner** |
| NoSQL (document/KV) | DynamoDB | **Cosmos DB** | **Datastore/Firestore / Bigtable** |
| Cache | ElastiCache (Redis/Valkey) / MemoryDB | **Azure Cache for Redis** | **Memorystore** |
| Queue | SQS | **Service Bus Queues** / Storage Queues | **Pub/Sub** (pull) / Cloud Tasks |
| Pub/sub & event bus | SNS / EventBridge | **Service Bus Topics** / **Event Grid** | **Pub/Sub** / **Eventarc** |
| Stream processing | Kinesis / MSK | **Event Hubs** / **Stream Analytics** | **Dataflow** (Beam) / Pub/Sub |
| Data warehouse | Redshift | **Synapse Analytics** / **Fabric** | **BigQuery** |
| Data lake | S3 + Lake Formation + Glue | **Data Lake Storage Gen2** + **Data Factory** | BigQuery + Dataproc + **Dataflow** |
| ETL/orchestration | Glue / Step Functions | **Data Factory** / **Logic Apps** | **Dataflow** / **Composer** (Airflow) / **Workflows** |
| CDN | CloudFront | **Azure Front Door / CDN** | **Cloud CDN / Media CDN** |
| DNS | Route 53 | **Azure DNS / Traffic Manager** | **Cloud DNS** |
| Load balancer | ALB / NLB / GLB | **Application Gateway** (L7) / **Load Balancer** (L4) / **Front Door** (global) | **Cloud Load Balancing** (global/regional, internal/external) |
| API gateway | API Gateway | **API Management (APIM)** | **Apigee** / API Gateway |
| VPC | VPC | **VNet** | **VPC** |
| Interconnect | Direct Connect | **ExpressRoute** | **Cloud Interconnect** |
| Transit/routing hub | **Transit Gateway** | **Virtual WAN / Hub VNet peering** | **Network Connectivity Center** |
| Private endpoints | VPC Endpoints / PrivateLink | **Private Endpoints / Private Link** | **Private Service Connect (PSC)** |
| Firewall | AWS Network Firewall / GWLB | **Azure Firewall** | **Cloud Firewall** |
| WAF | AWS WAF | **Front Door WAF / AppGW WAF** | **Cloud Armor** |
| DDoS | Shield (Std/Adv) | **Azure DDoS Protection** | **Cloud Armor** |
| Secrets | Secrets Manager / SSM Parameter Store | **Key Vault** | **Secret Manager** |
| KMS | KMS / CloudHSM | **Key Vault (keys/HSM)** | **Cloud KMS / Cloud HSM** |
| IAM | IAM / Organizations / SCPs / SSO | **Entra ID** (formerly Azure AD) / **Management Groups** / **Azure Policy** / **RBAC** | **Cloud IAM** / **Org–Folders–Projects** / **Org Policy** |
| Workload identity | IRSA / EKS Pod Identity | **Workload Identity Federation / AKS Workload Identity** | **Workload Identity Federation / GKE Workload Identity** |
| IaC-native | CloudFormation / CDK | **ARM / Bicep** | **Deployment Manager** (legacy) / **Config Controller** |
| Monitoring | CloudWatch / X-Ray | **Azure Monitor / App Insights / Log Analytics** | **Cloud Monitoring / Cloud Trace / Cloud Logging** |
| Policy/compliance | Config / Audit Manager / Control Tower | **Azure Policy** (+ Initiatives) | **Assured Workloads / Security Command Center** |
| Threat detection | GuardDuty / Security Hub / Inspector | **Microsoft Defender for Cloud** | **Security Command Center** |
| Service mesh | App Mesh (deprecated direction) / use Istio | **Istio-based AKS add-on** | **Anthos Service Mesh / Cloud Service Mesh** |
| CI/CD | CodePipeline/CodeBuild (legacy) → GitHub Actions | **Azure DevOps / GitHub Actions** | **Cloud Build / Cloud Deploy** |
| Artifact registry | ECR | **Azure Container Registry (ACR)** | **Artifact Registry** |
| Marketplace/SaaS | AWS Marketplace | Azure Marketplace | Google Cloud Marketplace |
| AI/ML platform | SageMaker / Bedrock | **Azure ML / Azure OpenAI** | **Vertex AI** |

**Notes that show real understanding:**
- **GKE and BigQuery are GCP's genuine differentiators** — GKE is the reference Kubernetes (Google invented Borg, then Kubernetes), with **Autopilot** (fully managed node-less operation) and **Multi-Cluster Ingress/Fleet**. BigQuery's **serverless separation of storage and compute** with per-query billing and no cluster to size remains architecturally distinctive; **BigLake/Iceberg support** makes it a lakehouse engine too.
- **Azure's differentiator is enterprise integration**: Entra ID (identity you already have), Azure Arc (manage on-prem/other-cloud resources with Azure control plane), hybrid identity, and the Microsoft stack (SQL Server, Windows, M365, Dynamics). **Azure OpenAI** was a major enterprise on-ramp.
- **AWS's differentiator is breadth and maturity** — more services, deeper features, larger ecosystem, and the most battle-tested operational tooling. **The "boring technology" argument is real.**
- **Azure Cosmos DB** is the most genuinely multi-model/multi-region-native database of the three (five consistency levels, multi-master writes, per-region throughput) — and the **five consistency levels** (Strong, Bounded Staleness, Session, Consistent Prefix, Eventual) are a favourite interview topic.
- **Cloud Run** occupies a space the others approximate but don't match cleanly: scale-to-zero containers with request-based billing and no cluster to manage.

---

## 🟢 Azure essentials

### 1. Azure resource hierarchy and governance
```
Tenant (Entra ID)  ← identity boundary
  └─ Management Groups   ← policy/RBAC applied in bulk (nest up to 6 deep)
       └─ Subscriptions  ← billing + quota boundary
            └─ Resource Groups  ← lifecycle boundary: delete the RG, delete everything in it
                 └─ Resources
```
**The distinctions that matter:**
- **Tenant** = the identity/Entra ID boundary. One tenant per organisation is normal; multiple for M&A, isolation, or regulated environments.
- **Management Groups** are where you apply governance at scale (Azure Policy, RBAC) across many subscriptions — the analogue of AWS OUs.
- **Subscription** = the **billing and quota boundary**, and a hard scale limit (e.g. vCPUs per region per subscription). **Large organisations use many subscriptions** (per environment, per BU, per workload) — the "subscription factory" pattern via **Azure Landing Zones / Bicep / Terraform**.
- **Resource Group** = the **lifecycle unit**. Everything in an RG shares a region metadata scope and is deleted together. **The design rule: put resources with the same lifecycle in the same RG** (an app + its App Service plan + its storage; not "all databases in one RG"). Note: a resource lives in one RG but can *reference* resources in other RGs/subscriptions.
- **Tags** for cost attribution and automation (mandatory-tag policies via Azure Policy).

**Azure Policy** (vs AWS Config+SCP):
- **Policy definitions** (rules in a JSON DSL) grouped into **Initiatives**; assigned at management group/subscription/RG scope.
- Effects: `Deny` (block the request — like an SCP), `Audit`/`AuditIfNotExists`, `Append`, `Modify` (**mutate the resource to compliance — more powerful than AWS Config's remediation**), `DeployIfNotExists` (**deploy a companion resource, e.g. diagnostics settings or a managed identity — genuinely useful and unique**), `DenyAction`.
- **Compliance state per resource** + **exemptions with expiry dates** (a nice governance feature).
- **The framing:** "Azure Policy is a stronger in-band admission-control system than AWS Config — it can deny, mutate, and deploy companion resources as part of the ARM request pipeline. AWS's equivalent power lives across SCPs (deny), Config Rules (detect/remediate), and CloudFormation hooks. If you're building guardrails, Azure's single mechanism is simpler."

**RBAC:** role assignments = **security principal + role definition + scope**. Built-in roles (`Owner`, `Contributor`, `Reader`, `Virtual Machine Contributor`, `AcrPull`, `Monitoring Reader`…) plus custom roles. **Scope hierarchy means an assignment at a management group applies everywhere below** — so scope tightly (least privilege = narrowest scope that works). **Deny assignments** exist for exclusions. **Privileged Identity Management (PIM)** for just-in-time, time-bound, approval-gated elevation — **the right answer for "how do we handle admin access"**.

**Managed Identities** — the workload identity answer (no secrets):
- **System-assigned**: tied to one resource's lifecycle (delete the VM → identity gone).
- **User-assigned**: standalone, attachable to many resources — better for shared workloads and IaC.
- The resource gets a token from the IMDS endpoint for Entra ID, and Azure services accept it. **Functionally equivalent to AWS instance profiles/IRSA, and equally mandatory.** "**No secrets in code or config; use a managed identity and grant it the minimum RBAC role at the narrowest scope**" is the correct answer to nearly every Azure security question.

### 2. Azure networking essentials
- **VNet** = VPC. **Subnets** are not typed public/private — a subnet is "public" if its VMs have public IPs and there's a route to the internet. **Network Security Groups (NSGs)** are the SG analogue: stateful, allow+deny, priority-ordered, attachable to **subnets or NICs** (more flexible than AWS SGs, which attach only to ENIs). **Application Security Groups (ASGs)** let you group NICs logically and reference the group in NSG rules — **the clean equivalent of AWS SG-to-SG references**.
- **Route tables (UDR)** for traffic steering; **forced tunneling** to send all egress on-prem or to a firewall.
- **Peering** (VNet-to-VNet, regional or global) vs **Virtual WAN** (Microsoft-managed hub, transitive routing, branch connectivity, integrated firewall/VPN) vs **Hub-spoke with Azure Firewall / NVA in the hub** (the classic enterprise pattern, equivalent to TGW + inspection VPC).
- **Peering is not transitive** — A↔B and B↔C does not give A↔C. **Virtual WAN or NVA-based transit is how you get transitivity.** A common gotcha.
- **Azure Load Balancer** (L4, standard SKU is zone-aware and required for Availability Zones) vs **Application Gateway** (L7, WAF v2 SKU, path/host routing, session affinity) vs **Front Door** (global L7, CDN+WAF, geo-failover) vs **Traffic Manager** (global DNS-based steering, no data-plane proxying). **The layered choice mirrors AWS NLB/ALB/CloudFront+Route53.**
- **Private Link / Private Endpoints**: consume a PaaS service (Blob, SQL, Key Vault, ACR) privately from your VNet — **the single most important Azure network security control**, because it removes public-endpoint exposure for managed services. **Private Link Service** is the producer side (expose your own service behind an LB to consumers).
- **Availability Zones**: physically separate datacenters within a region with independent power/cooling/networking; **not all services/regions support them, and not all SKUs do** — check per service. **Zone-redundant** deployments are the design target for anything critical.
- **Service Endpoints** (VNet-level access to a PaaS, still over the Microsoft backbone but identity-based rather than private-IP-based) are the older mechanism; **Private Endpoints supersede them** for isolation.

### 3. Azure compute, storage, and data highlights
- **App Service** (PaaS web apps, with **App Service Environment** for VNet integration), **Container Apps** (serverless containers on top of AKS with **Dapr + KEDA built in** — scale from zero on events; a genuinely nice abstraction), **AKS** (with **node pools, Virtual Nodes/ACI burst, Workload Identity, Azure Policy add-on, and a free control plane**), **Azure Arc** (project non-Azure/on-prem machines and clusters into the Azure control plane — the hybrid story).
- **Blob Storage tiers**: **Hot / Cool / Cold / Archive**, plus **access tier on individual blobs**, **lifecycle management rules**, **immutable storage (WORM) with time-based or legal-hold policies**, **soft delete**, **versioning**, **geo-redundancy options (LRS/ZRS/GRS/GZRS/RA-GRS)** — **the redundancy choice is made at account creation and is painful to change**, and GRS/GZRS give you cross-region copies with an SLA on RPO (typically ≤ 15 min for GRS).
- **Azure SQL Database** (single DB, elastic pools for many small DBs, **Hyperscale** for very large, managed instance for lift-and-shift SQL Server), **Cosmos DB** (see below), **PostgreSQL Flexible Server** (the RDS-for-Postgres analogue, with zone-redundant HA and read replicas).
- **Cosmos DB consistency levels** — the famous interview topic:
  | Level | Guarantee | Cost |
  |---|---|---|
  | **Strong** | Linearisable; reads always see the latest write | Highest latency, **only available in single-region or with a designated writer**; can't use multi-master |
  | **Bounded Staleness** | Reads lag writes by at most K versions or T time | Auto-catches up; configurable per account/request |
  | **Session** | Read-your-writes within a session (token-based) | **The default**, and usually the right one |
  | **Consistent Prefix** | Never see out-of-order writes | |
  | **Eventual** | No ordering guarantee | Lowest latency, cheapest |
  **The insight:** "Cosmos lets you trade consistency **per request**, which is more granular than any other managed database — and it's the practical embodiment of PACELC: you choose latency/availability versus consistency explicitly. The trap is assuming the default (Session) gives you global read-your-writes; it only does within a session token. And Strong consistency forfeits multi-master, so the multi-region write story and the consistency story are coupled."
  Also know: **RU/s (request units) as the capacity/cost model**, **partition keys and hot partitions** (same failure mode as DynamoDB), **multi-region writes with last-writer-wins conflict resolution** (or custom), and **the 20 GB / 20k RU-per-logical-partition limits**.
- **Key Vault** = secrets + keys + certificates in one service, with **HSM-backed options (Managed HSM, Premium)**, **soft delete + purge protection** (essential — without purge protection, a compromised principal can permanently destroy your keys), **private endpoint access**, and **RBAC vs vault-access-policy** modes (RBAC is the modern recommendation).
- **Entra ID** = identity: users, groups, **app registrations / service principals / managed identities**, **Conditional Access** (MFA, device compliance, location, risk-based — the enterprise security powerhouse), **Privileged Identity Management**, **External ID**, and **workload identity federation** for CI/CD (GitHub Actions → federated credential → no client secret). **"Use federated credentials, never a client secret, for GitHub Actions to Azure" is the correct 2026 answer.**
- **Azure Monitor / Log Analytics**: the **KQL (Kusto Query Language)** skill is genuinely differentiating — a powerful query language over a columnar log store. **Application Insights** gives APM with automatic distributed tracing (the closest thing to "observability in a box" among the three clouds). **Cost control on Log Analytics ingestion is a real discipline** — data collection rules, sampling, and retention tiers, because per-GB ingestion plus retention is where Azure observability bills explode.
- **Azure DevOps / GitHub Actions** for CI/CD; **Bicep** (a clean, declarative ARM DSL — much nicer than raw ARM JSON) or Terraform for IaC.

---

## 🟢 GCP essentials

### 4. GCP resource hierarchy and IAM
```
Organization
  └─ Folders            ← BU/env grouping; policies inherit
       └─ Projects      ← THE unit of everything: billing, APIs, quotas, IAM, resources
            └─ Resources
```
- **The Project is the fundamental boundary** — every resource belongs to exactly one, APIs are enabled per project, quotas are per project, billing is per project, and IAM is scoped per project. **The analogue is closer to an AWS account than to a resource group.** A common pattern: one project per environment per application, or one project per team with many environments.
- **Organization Policies** (the SCP analogue): constraints like `compute.vmExternalIpAccess` (deny public IPs), `constraints/compute.restrictLoadBalancerCreationForTypes`, region restrictions, domain-restricted sharing. **Enforced at organisation/folder/project level and inherited.**
- **Cloud IAM**: roles are **predefined** (`roles/compute.admin`, `roles/storage.objectViewer`) or **custom**; bindings = principal + role + resource. **Very granular** — you can grant `storage.objectViewer` on a single bucket or even a single object prefix via conditions.
- **IAM Conditions** (attribute-based: time-bound or resource-attribute-bound grants) — e.g. temporary access that expires. **A genuinely useful least-privilege feature.**
- **Service accounts** are the workload identity: **a service account is also a principal you can impersonate** (`iam.serviceAccountTokenCreator`) — and **SA impersonation is the standard break-glass/CI pattern**, but **a leaked SA key is the GCP equivalent of a leaked AWS access key**. So: **no keys**; use **Workload Identity Federation** (external identity → short-lived GCP token) for CI, and **GKE Workload Identity** (Kubernetes SA → GCP SA) for workloads.
- **Short-lived credentials everywhere**; default token lifetime 1 hour.
- **VPC Service Controls** — the differentiator: a **perimeter** around GCP projects/services that blocks access from outside the perimeter **even with valid credentials**, preventing data exfiltration via a compromised identity or a misconfigured project. **It's the strongest data-exfiltration control of the three clouds, and knowing it is a strong signal.** (Egress rules and ingress rules refine it; Access Levels from BeyondCorp/Identity-Aware Proxy integrate.)

### 5. GCP networking, compute, and data highlights
- **VPC is global** — subnets are regional, but the VPC spans all regions and you don't peer within it. **A big architectural simplification versus AWS/Azure**: one global VPC with regional subnets, and firewall rules are VPC-wide (with target tags/service accounts).
- **Cloud Load Balancing is global and anycast by default** for external HTTP(S)/SSL-proxy/TCP-proxy LBs: one IP, backend buckets in multiple regions, autoscaling backends, and CDN integration. **No per-AZ LB nodes to reason about** — a real difference from AWS ALB/NLB.
- **Cloud Armor** = WAF + DDoS + adaptive protection + rate limiting at the global LB.
- **Private Service Connect (PSC)** = the PrivateLink analogue (consume Google APIs or third-party services privately from your VPC); **Service Attachments** for producer side. **Private Google Access** lets VMs without external IPs reach Google APIs.
- **Network Connectivity Center** = the transit/hub analogue (spoke VPCs, hybrid attachments, transitive routing).
- **Cloud Interconnect** (Dedicated/Partner) for hybrid.
- **Compute Engine**: instances with **machine types** (N-series general, C-series compute, M-series memory, T-series shared-core burstable — the `t` analogue with sustained-use discount behaviour, A-series accelerators), **preemptible/Spot VMs** (Spot with no fixed 30-min cap now), **sole-tenant nodes**, **confidential computing**, **shielded VMs** (measured boot, vTPM, integrity monitoring), and **sustained-use + committed-use discounts** (**automatic discounts for running something all month — unique to GCP and a real cost story: no upfront commitment needed for the baseline saving**).
- **GKE**: the reference Kubernetes. **Autopilot** (Google manages nodes, you pay per pod request — no node capacity planning at all) vs **Standard** (you manage node pools). **Release channels** (Rapid/Regular/Extended/Stable) for cluster version management. **Multi-cluster services**: **Fleet**, **Multi-Cluster Ingress** (a single global VIP across clusters), **Multi-Cluster Gateway**, and **GKE Enterprise** for fleet policy/config. **Binary Authorization** (only signed/approved images run — supply-chain enforcement at admission), **Config Sync / Anthos Config Management** (GitOps-native, multi-cluster), **Autoscaling** (HPA, VPA, Cluster Autoscaler, and **Node Auto-Provisioning**), and **Dataplane V2** (Cilium/eBPF-based, so NetworkPolicy and observability are native).
- **Cloud Run**: request-based serverless containers, **scale to zero**, per-request billing with 1 ms granularity, concurrency control, **jobs** for batch, and **Cloud Run functions** for the FaaS shape. **The pragmatic answer for most small services that don't need a cluster.**
- **Cloud Storage**: a **single global namespace** with **location types** (region / dual-region / multi-region), **storage classes** (Standard / Nearline / Coldline / Archive) with **autoclass** (automatically moves objects based on observed access — the "don't make me think" option), **object lifecycle management**, **retention policies + bucket lock (WORM)**, **object versioning**, **uniform bucket-level access** (turn off per-object ACLs — **do this; legacy ACLs are a security mess**), **Signed URLs**, **Turbo Replication** (15-min RPO for dual-region), and **requester-pays**.
- **BigQuery**: **serverless, columnar, storage/compute-separated**, per-query (on-demand, TB scanned) or capacity (slots/reservations) pricing. **The cost control everyone must know: partitioning + clustering + avoiding `SELECT *`**, because on-demand bills by **bytes scanned**. **BigLake** and **Iceberg/Delta/Hudi support** make it a lakehouse engine; **BigQuery ML** trains models in SQL; **BI Engine** caches for dashboards; **materialised views** and **search indexes**. **Streaming inserts, Storage Write API, and Change History** for CDC.
- **Pub/Sub**: **global, at-least-once, with ordering keys, dead-letter topics, retention (up to 31 days), replay via snapshots/seek**, and **exactly-once delivery** for some subscription types. **Push vs pull subscriptions**, and **BigQuery/Storage/Cloud Run subscribers**. **The "one messaging service for everything" model is simpler than AWS's SQS/SNS/Kinesis/EventBridge split — and knowing that trade-off (simplicity vs specialisation) is a good cross-cloud answer.**
- **Cloud SQL** (MySQL/PostgreSQL/SQL Server managed) vs **AlloyDB** (Postgres-compatible, columnar accelerator, much better performance for analytical/mixed workloads) vs **Spanner** (**globally distributed, strongly consistent, horizontally scalable SQL — externally consistent via TrueTime**; the answer when you need both scale and strong consistency and can pay for it) vs **Firestore/Bigtable**.
- **Observability**: Cloud Monitoring (metrics), Cloud Logging (logs, with a powerful query language), Cloud Trace (traces, OpenTelemetry-native), Cloud Profiler (continuous profiling — **one of the earliest managed profilers**), **Application Integration / SLO dashboards built in**.

### 6. The three clouds' philosophies in one paragraph each
- **AWS**: the widest catalogue, the deepest features, the most mature operational tooling, and the most third-party ecosystem. You will find a service for everything, and you will need to assemble the architecture yourself. **Best default when you don't have a strong reason otherwise.**
- **Azure**: identity-first (Entra ID is often already your corporate directory), enterprise/hybrid-first (Arc, Azure Stack, SQL Server, Windows), strong governance primitives (Policy with Modify/DeployIfNotExists, PIM, Blueprints→Landing Zones), and the enterprise AI on-ramp. **Best default for Microsoft-centric enterprises and regulated hybrid estates.**
- **GCP**: infrastructure-first (global network, Borg→Kubernetes lineage, Spanner/BigQuery/Pub/Sub as globally-distributed primitives), data-and-AI-first, developer-experience-clean (global VPC, anycast LB, Cloud Run, no per-AZ LB reasoning), and cost-model-friendly (sustained-use discounts, per-query pricing). **Best default for data/AI-heavy platforms, Kubernetes-native teams, and greenfield services that value simplicity.**

---

## 🔵 Advanced

### 7. Multi-cloud — the honest engineering assessment
**Legitimate drivers (say these):**
1. **Best-of-breed services**: BigQuery for analytics, Bedrock/Vertex/Azure OpenAI for models, Cosmos DB for multi-region writes, Cloud Run for scale-to-zero. Real, and increasingly common.
2. **Negotiating leverage / avoiding lock-in pricing**: credible multi-cloud ability changes vendor conversations. (Note: *credible* — an unused second cloud buys nothing.)
3. **Regulatory or contractual**: a customer mandates their cloud; data residency requires a specific provider in a region; a sovereign-cloud requirement.
4. **M&A**: you inherited it. This is the most common real reason, and pretending otherwise is naive.
5. **Disaster recovery / provider-risk**: surviving a region-wide or provider-wide outage. **Real but expensive — and note that a full AWS outage and a full Azure outage share causes** (a global DNS/CDN/security incident, a common SaaS dependency, a BGP event), so multi-cloud does not protect against everything.
6. **Bargaining/talent/market reasons**: partners require it, or a team's expertise is in a specific cloud.

**The costs (be specific — vagueness here is a red flag):**
- **Duplicated engineering**: two sets of IaC modules, two CI/CD integrations, two networking models, two IAM models, two monitoring stacks, two on-call skill sets. Realistically **1.3–2× platform team effort**, not 2× (there's shared Kubernetes/GitOps/observability), but never 1×.
- **Lowest-common-denominator abstraction**: if you insist on portability, you end up using only Kubernetes + Terraform + S3-compatible storage, and you forgo VPC Service Controls, Cosmos DB multi-master, BigQuery, PrivateLink, Azure Policy's DeployIfNotExists — i.e. **you pay twice and get less**.
- **Egress costs**: cross-cloud data movement is billed (and expensive). **A multi-cloud data platform can be dominated by egress**, which also creates an architectural pressure to keep data in one cloud — undermining the multi-cloud premise.
- **Security surface doubles**: two IAM models, two sets of guardrails, two sets of detection tooling, two identity federations. **Cross-cloud identity is genuinely hard** — you end up with a central IdP federating to both, plus workload identity federation in each, plus consistent policy enforcement which no single tool does well.
- **Operational complexity in incidents**: an incident spanning two clouds has two consoles, two support contracts, two SLAs, and no single pane of truth unless you built one.
- **Testing burden**: failover, DR, and performance tests multiply.

**The mature position (this is the answer that scores):**
> "I separate **multi-cloud** from **portable**. **Portable** is cheap and worth doing: run Kubernetes, use OpenTelemetry, Terraform/OpenTofu, GitOps, S3-compatible storage APIs, Postgres, and Kafka — so that *moving* is possible and *vendor lock-in at the architecture level* is low. **Multi-cloud — actively running production in two clouds simultaneously — is expensive and I'd only do it for a specific reason**: a mandated service, a regulatory requirement, an acquired estate, or a genuine provider-risk requirement that a multi-region single-cloud design can't meet. What I'd resist is 'multi-cloud for flexibility' as an unquantified aspiration, because it usually means paying 1.5× for an abstraction layer that prevents you using the best features of either cloud, and egress costs that punish the very data movement the strategy implies. **My default recommendation: single cloud, multi-region, portable architecture, and a documented exit plan** — which gets you 90% of the leverage for 20% of the cost."

### 8. Cloud-agnostic design patterns (what "portable" concretely means)
| Layer | Portable choice | What you give up |
|---|---|---|
| Compute | **Kubernetes** (EKS/AKS/GKE) with standard workloads | Cloud-native serverless (Lambda/Cloud Run/Container Apps), spot-interruption handling differences |
| IaC | **Terraform/OpenTofu** with cloud-specific modules; **Crossplane** if you want K8s-native abstractions | Provider-native tools (CloudFormation/Bicep) get new features first |
| Identity | **OIDC federation** from your IdP; **Kubernetes RBAC** in-cluster; SPIFFE/SPIRE for workload identity | Provider-native identity niceties (PIM, IAM Conditions, Conditional Access) |
| Secrets | **External Secrets Operator** / Vault with cloud KMS backends | Native secret managers' rotation Lambdas/functions |
| Observability | **OpenTelemetry** everywhere; Prometheus/Grafana/Loki/Tempo as the store layer, or a vendor-neutral SaaS | Cloud-native APM auto-instrumentation (App Insights) |
| Data | **Postgres** (not Aurora/AlloyDB/Cloud SQL-specific features), **Kafka** (not Pub/Sub/Event Hubs), **object storage via S3 API** where possible | Spanner, BigQuery, Cosmos DB multi-master, DynamoDB streams |
| Networking | **CNI + Ingress/Gateway API**, standard CIDR planning, private endpoints via a common abstraction | Global anycast LB (GCP), Front Door, Azure Virtual WAN |
| CI/CD | **GitOps** (Argo CD/Flux) + one CI (GitHub Actions/GitLab) with per-cloud OIDC | Provider-native pipelines |
| Storage classes | Standardise on lifecycle tiers mapped per cloud | Autoclass, Intelligent-Tiering automation |

**The abstraction layer question — "do you build a cloud abstraction layer?"**
- **A thin one, yes**: internal modules (a Terraform module `platform/object-storage` that emits S3 or GCS or Blob with a consistent interface), a common labelling/tagging scheme, a common secret-management interface, and standard observability attributes. This gets you consistency without pretending the clouds are the same.
- **A thick one, no**: an internal API that hides all cloud differences becomes a distributed system of its own, lags every provider's new features, and is maintained by you forever. **This is where multi-cloud strategies go to die.**
- **Crossplane** is the interesting middle: Kubernetes-native composition, so you expose `StorageBucket` / `PostgresInstance` as CRDs backed by any cloud. **Real value for platform teams with self-service goals**; real complexity, and you own the abstractions. Worth naming with both halves.

### 9. Hybrid cloud and the on-prem question
**Patterns:**
- **Connectivity**: dedicated circuits (Direct Connect / ExpressRoute / Cloud Interconnect) with **redundancy across two locations/providers**, VPN as backup, **BGP for failover and route propagation**, and a clear routing policy (which traffic goes where). Latency to the cloud region is a hard design constraint — **a 10 ms round trip is a different application than a 1 ms one**.
- **Identity federation**: on-prem AD → Entra ID (Azure's home turf) → other clouds; or a central IdP (Okta/Ping) federating everywhere. **Single identity, per-cloud role mapping, MFA/conditional access centrally.**
- **Network extension**: stretched L2 is fragile and rarely worth it; **L3 routing with DNS-based service location** is the durable design.
- **Data**: which data must stay on-prem (regulatory, latency, volume, egress cost), what replicates, and **the direction of truth** (one writer, or conflict resolution).
- **Compute placement decision framework**: latency to users/data, egress cost, regulatory constraints, existing hardware investment, burst capacity needs, and operational skill. **A workload that reads 10 TB/day from an on-prem database should usually stay near that database.**
- **Tools**: Azure Arc (strongest hybrid control plane), Anthos/GKE on-prem, AWS Outposts / ECS Anywhere / EKS Anywhere / Local Zones, VMware Cloud.

**The honest take:** "Hybrid is usually a **migration state** or a **regulatory requirement**, not an end-state architecture. If it's a migration, the plan should have an end date and the hybrid complexity should be temporary. If it's regulatory, design the boundary explicitly — which data and which compute must stay, and make the interface between them narrow, well-monitored and well-documented, because a wide, chatty hybrid boundary is where latency and reliability go to die. And always measure the egress: many 'hybrid' designs are uneconomic once you price the data movement."

### 10. Cross-cloud reliability, DR and the support model
- **DR across clouds**: technically possible (replicate data, deploy the same containers, federate identity, DNS failover), but **you must test it, and testing costs real money**. Most teams that claim multi-cloud DR have never failed over. **My position: multi-region within one cloud gives most of the DR value at a fraction of the complexity; cross-cloud DR is justified only if you fear the provider itself.**
- **Global load balancing** as the switch: DNS-based (Route 53 / Traffic Manager / Cloud DNS with health checks) or anycast/CDN-based (CloudFront / Front Door / Cloud CDN). **TTL is a floor, not a promise** in every cloud.
- **Support plans**: AWS (Developer/Business/Enterprise On-Ramp/Enterprise), Azure (Developer/Standard/Professional Direct/Unified), GCP (Standard/Enhanced/Premium). **For production, the minimum is the tier that gives you < 15-minute response on critical issues and a TAM.** **Know that a P1 without a support contract is a queue, not an incident response.**
- **Well-architected frameworks exist in all three** (AWS WAF, Azure WAF, Google Cloud Architecture Framework) with remarkably similar pillars — reliability, security, cost, performance, operations, and (in all three now) sustainability. **Being able to say "the frameworks converge; the differences are in the tooling" is a good synthesis answer.**
- **Shared responsibility model** is identical in shape across all three: the provider secures the cloud *of* (physical, hypervisor, managed service internals); you secure the cloud *in* (your config, your identity, your data, your code). **Every major cloud breach is a customer-side misconfiguration**, and saying that plainly is correct and useful.

---

## 🔴 Scenario

### 11. "We're on AWS and leadership wants to evaluate moving to GCP/Azure. How would you run it?"
**Step 1 — Make the question precise.** "Move" is ambiguous and the answer differs enormously:
- Which workloads? All, or specific ones (a data platform to BigQuery, an AI workload to Vertex, one acquired business unit)?
- Why now: cost, a capability gap, a mandate, an expiring contract, a reliability incident, talent?
- What's the success criterion — a cheaper bill, a capability we can't get today, or an option we can exercise later?
- What's the budget for the migration *itself* (usually 1–3× the annual saving, in engineering time)?

**Step 2 — Establish the baseline you're comparing against.** You cannot evaluate a move without knowing your current state: total cost by service/team with attribution; the architecture inventory and dependency graph; the reliability record (incidents, SLO attainment); the operational load (toil, on-call); and the capability gaps that prompted the question. **Most "should we move" debates collapse here, because the current state was never measured and the complaint is anecdotal.**

**Step 3 — Quantify the target state honestly.** Not a list price comparison:
- **Direct cost**: compute, storage, egress (including **cross-cloud egress during migration and any ongoing split**), support plan, committed-use/reservation equivalents (GCP sustained-use, Azure reservations, AWS Savings Plans).
- **Migration cost**: engineering months, parallel-running costs (you pay for both during migration — often 6–18 months), dual tooling, training, consulting.
- **Ongoing cost**: duplicated platform engineering, two IAM/guardrail stacks, two on-call skill sets, or the cost of consolidating.
- **Risk cost**: migration incidents, feature freeze, delayed roadmap, and the possibility that the new environment has its own surprises.
- **Benefit**: the specific capability gained (query performance, a managed service, an AI platform, a compliance posture), quantified where possible.

**Step 4 — Run a bounded pilot, not a study.** Pick **one non-critical, representative workload**, migrate it end-to-end (IaC, CI/CD, observability, secrets, identity, networking, DR), and **measure**: time to migrate, actual vs predicted cost, performance, developer experience, and operational surprise count. **A two-week pilot produces more truth than a two-month architecture review.** Do the same pilot in the current cloud as a control (re-platform the workload on AWS with modern practices) — **because often the win is the modernisation, not the cloud.** That's a genuinely senior insight and it frequently turns out to be the answer.

**Step 5 — Decide with an explicit recommendation and an exit plan.** Options are rarely binary:
1. **Stay and optimise** (most common correct answer): commit properly, right-size, add savings plans, fix architecture, adopt the managed services you're not using. Usually finds 20–40%.
2. **Selective move**: the data/AI workload to the best-fit cloud, everything else stays. **This is the most common real outcome** — and it's a *deliberate* multi-cloud decision with a stated reason.
3. **Full migration**: only for a compelling driver (mandate, contract, existential capability gap), executed as a programme with a funded team, strangler-fig sequencing, and a rollback plan.
4. **Stay, but invest in portability**: Kubernetes, OTel, Terraform, Postgres, Kafka, S3-compatible APIs, and a documented exit plan — **buying the option to move later at low cost.** Often the best risk-adjusted answer.

**Step 6 — If migrating: the execution plan.** Strangler-fig by service, not a big bang. Order: stateless services first (cheap to move, easy to validate), then data (the expensive, risky part — with dual-write/replication and a cutover plan), then identity, then network, then decommission. **Every step needs: a rollback plan, a validation gate, parallel running with traffic comparison, and a cost check against the prediction.** And **freeze the old environment's growth** so you don't migrate a moving target.

**The framing:** "I'd refuse to answer 'should we move?' until the question is 'which workload, for what measurable benefit, at what total cost including migration and duplication?' — and I'd answer it with a pilot, not a slide deck. In my experience the honest outcome is usually: optimise where we are, move the one workload where another cloud is genuinely better, and invest in portability so the decision stays reversible. Full migrations happen, but almost always for a business reason (M&A, contract, mandate) rather than a technical one."

### 12. "Design a globally distributed data platform spanning two clouds." (Advanced multi-cloud)
**Requirements to fix first:** data volume and growth, query patterns (interactive dashboards vs ad-hoc vs streaming), latency SLO for queries, data residency/sovereignty constraints, consistency requirements, and **who owns which part** (two teams in two clouds is the real constraint, not the technology).

**A defensible design:**
```
Ingest:      event producers (both clouds) → Kafka (MSK / Event Hubs / managed Kafka)
                 │  (or Pub/Sub where GCP-native)
             MirrorMaker 2 / cross-cloud replication for the event backbone
                 │
Landing:     object storage (S3 / GCS / Blob) as the immutable raw layer — ONE canonical location,
             replicated read-only to the other cloud if needed
                 │
Format:      open table formats: Apache Iceberg (or Delta/Hudi) — cloud-neutral, engine-neutral
                 │
Processing:  Spark on Kubernetes (both clouds) / Dataflow (GCP) / Synapse-Fabric (Azure) / EMR (AWS)
                 │
Serving:     BigQuery (external tables over Iceberg / BigLake)  ←── best-in-class query engine
             + Athena/Redshift Spectrum or Synapse for in-cloud queries
             + a cache/serving layer (Redis/Bigtable/DynamoDB) for low-latency app queries
                 │
Governance:  central catalog (DataHub / Unity Catalog / Purview / Dataplex) — ONE catalog, both clouds
             + column-level access policy + lineage
                 │
Observability: OpenTelemetry for pipelines; data-quality checks (Great Expectations/Soda) as gates
```
**The decisions to articulate:**
1. **Open formats are the portability layer.** **Iceberg/Delta/Hudi in object storage** decouples the *data* from the *engine* — so you can query from BigQuery, Spark, Athena, Synapse or Flink without copying. **This is the single most important architectural choice for multi-cloud data**, and it's newer than most candidates' mental model. Without it, your data platform is welded to one engine.
2. **One canonical write location.** Multi-cloud writes to the same dataset create conflict resolution problems with no good answer. **Pick a single home for the raw/curated layers**, replicate read-only, and let each cloud serve queries locally. Multi-active only where you genuinely need it (and then per-region partitioning, not shared writes).
3. **Egress is the dominant cost and the dominant constraint.** Model it before designing: cross-cloud transfer of a 500 TB lake is six figures and months. **So: move compute to data, not data to compute.** Run the processing where the data lives; ship only results/aggregates across.
4. **Compute placement by latency and cost**: interactive dashboards near the users (or behind a cache), heavy batch where the data is, ML training where the GPUs are. **Don't distribute for distribution's sake.**
5. **Identity and governance must be unified or nothing works.** One central IdP federated to both clouds; **one data catalog** with lineage across both; one policy model for column-level access (or you'll have two inconsistent ones and an audit finding); and consistent classification/tagging. **Governance divergence is the failure mode of multi-cloud data platforms — you get two platforms and call it one.**
6. **Consistency and freshness contracts per dataset**: define the SLO ("curated layer fresh within 15 min; raw within 5 min"), measure it, and alert on it. **Cross-cloud replication lag is a real product problem** — a dashboard in cloud B showing yesterday's data is an incident.
7. **Idempotent, restartable pipelines** with **exactly-once-ish semantics** via dedup keys — because cross-cloud networks fail, and a pipeline that can't resume will be re-run and will duplicate.
8. **Data quality as a gate**, not a report: schema validation, volume/anomaly checks, freshness checks, and **fail the pipeline** (or quarantine the partition) rather than publishing bad data downstream.
9. **Cost governance**: per-query/per-job attribution, BigQuery bytes-scanned controls (partitioning, clustering, no `SELECT *`), slot reservations vs on-demand modelling, Log Analytics ingestion controls, and **egress budgets with alerts**.
10. **The push-back I'd offer:** "Before designing this, I'd ask whether two clouds are actually required for the *data*. In most cases the answer is: one cloud holds the lake, and the other cloud holds applications that query results through a serving layer or an API. That's dramatically simpler and cheaper than a genuinely distributed data platform, and it gives 90% of the benefit. **A true multi-cloud data platform is justified by data residency law or by two genuinely autonomous organisations — not by technology preference.**"

### 13. "Compare the three clouds' approaches to workload identity and least privilege."
| | **AWS** | **Azure** | **GCP** |
|---|---|---|---|
| Human identity | IAM Identity Center (SSO) + permission sets; IAM users (legacy, avoid) | **Entra ID** + RBAC role assignments + **PIM** for JIT elevation + Conditional Access | Cloud Identity/Workspace + IAM bindings (+ **IAM Conditions** for time-bound access) |
| Machine identity (VM/container) | **Instance profile** (EC2), **ECS task role**, **IRSA / EKS Pod Identity** | **Managed Identity** (system-assigned / user-assigned) | **Service Account** attached to the instance/pod; **GKE Workload Identity** |
| CI/CD federation | **OIDC → `AssumeRoleWithWebIdentity`** | **Federated credential on an app registration / managed identity** | **Workload Identity Federation** (external IdP → short-lived token) |
| Max permission cap | **Permission boundaries** + **SCPs** | **Azure Policy (Deny)** + Management Group scope + **PIM** | **Org Policy** + **VPC Service Controls** perimeter |
| Cross-account/project | Cross-account roles + resource policies (needs both to allow) | Cross-tenant/cross-subscription RBAC | Cross-project IAM bindings |
| Session revocation | `aws:TokenIssueTime` deny | Sign-in risk / token lifetime config, **revoke sessions** | SA key rotation, token lifetime, VPC-SC perimeter change |
| Unique strength | SCPs that even root can't exceed; Permission boundaries for delegation | **Conditional Access + PIM** (best human-access governance); Policy `DeployIfNotExists` | **VPC Service Controls** (data exfiltration barrier that survives valid credentials); IAM Conditions |
| Shared trap | Long-lived access keys | **Client secrets on app registrations** | **Service account JSON keys** |

**The synthesis answer:** "All three converge on the same model — **no long-lived credentials, workload identity attached to the compute resource, short-lived tokens, least privilege enforced at multiple layers, and an organisational guardrail that even an admin can't exceed**. The differences are in emphasis: AWS's SCPs are the strongest organisational deny, Azure's Conditional Access + PIM are the strongest human-access governance, and GCP's VPC Service Controls are the strongest data-exfiltration barrier. **In a multi-cloud estate I'd standardise on the common denominator — federated identity, no static keys, per-workload identity, scoped roles, org-level guardrails, and detection of new identity creation — and then use each cloud's speciality where it solves a problem I actually have.** And in all three, the same incident pattern dominates: a static credential committed to a repository with broader permissions than it needed."

---

## Red flags

| Saying / doing this | Costs you |
|---|---|
| "Multi-cloud avoids vendor lock-in" without a cost analysis | The classic unquantified aspiration |
| Designing to the lowest common denominator "for portability" | Paying twice and getting less |
| Service account JSON keys / app-registration client secrets / IAM user access keys | The universal static-credential failure |
| Putting resources with different lifecycles in one Azure Resource Group | Awkward deletions and unclear ownership |
| Assuming VNet peering is transitive | It isn't — you need Virtual WAN or an NVA hub |
| Ignoring Azure redundancy choice (LRS/ZRS/GRS) at account creation | Painful to change later |
| No **purge protection** on Key Vault | A compromised principal destroys your keys permanently |
| Assuming Cosmos DB Session consistency gives global read-your-writes | It's session-token scoped |
| GCP: leaving per-object ACLs enabled instead of uniform bucket-level access | A legacy security mess |
| GCP: no VPC Service Controls on sensitive projects | Exfiltration possible with valid credentials |
| `SELECT *` on unpartitioned BigQuery tables | Per-byte billing; an enormous surprise |
| Not modelling cross-cloud egress before a multi-cloud data design | The design is uneconomic |
| Multi-cloud writes to one dataset with no conflict strategy | Unresolvable conflicts |
| Claiming cross-cloud DR that has never been tested | A marketing claim |
| P1 incident with a basic support plan | You're in a queue |
| Comparing clouds on list price only | Commitments, egress, support and migration cost dominate |

## Rapid recall

**Mapping:** EC2/VM/Compute Engine · EKS/AKS/GKE · Lambda/Functions/Cloud Functions+Cloud Run · S3/Blob/GCS · EBS/Managed Disks/Persistent Disk · RDS+Aurora/Azure SQL+Cosmos/Cloud SQL+AlloyDB+Spanner · DynamoDB/Cosmos DB/Firestore+Bigtable · SQS+SNS+Kinesis/Service Bus+Event Grid+Event Hubs/Pub/Sub · Redshift/Synapse/BigQuery · Route 53/Azure DNS+Traffic Manager/Cloud DNS · ALB+NLB/App Gateway+Load Balancer+Front Door/Cloud Load Balancing (global anycast) · Secrets Manager/Key Vault/Secret Manager · CloudTrail+Config+GuardDuty+Security Hub/Azure Monitor+Policy+Defender for Cloud/Cloud Audit Logs+Org Policy+Security Command Center.

**Azure:** Tenant → Management Groups → Subscriptions (billing+quota) → Resource Groups (**lifecycle unit**) → Resources. **Azure Policy** can Deny/**Modify**/**DeployIfNotExists**. RBAC = principal+role+scope, narrowest scope wins; **PIM** for JIT elevation. **Managed Identities** = no secrets. NSGs (stateful, allow+deny, priority, subnet-or-NIC) + **ASGs** for logical grouping. **Peering isn't transitive**. **Private Link** removes PaaS public exposure. **Zone-redundant + Standard SKU** for LBs and zones. Blob tiers Hot/Cool/Cold/Archive + **immutability/WORM** + **LRS/ZRS/GRS/GZRS chosen at creation**. **Cosmos DB's five consistency levels** (default Session; Strong forfeits multi-master), RU/s capacity, hot partitions. **Key Vault with purge protection**. **Entra ID Conditional Access**; **federated credentials for GitHub Actions**. **KQL / Log Analytics ingestion cost**. **Bicep or Terraform**.

**GCP:** Org → Folders → **Projects (the unit of everything)** → Resources. **Org Policy** = SCP analogue. **IAM Conditions** for time-bound/attribute-bound grants. **Service accounts + Workload Identity Federation** (no keys). **VPC Service Controls** = exfiltration perimeter that survives valid credentials. **Global VPC with regional subnets**; **global anycast Cloud Load Balancing**; **PSC** for private access; **Network Connectivity Center**. **Sustained-use discounts** (no commitment needed) + committed-use + Spot. **GKE Autopilot** (no nodes to manage), release channels, **Binary Authorization**, Fleet/Multi-Cluster Ingress, Dataplane V2 (eBPF). **Cloud Run** = scale-to-zero containers. **Cloud Storage**: single namespace, storage classes + **Autoclass**, **uniform bucket-level access**, retention + bucket lock, Turbo Replication. **BigQuery**: serverless, **billed by bytes scanned** → partition + cluster + no `SELECT *`; BigLake/Iceberg; slots/reservations. **Pub/Sub**: global, at-least-once, ordering keys, DLQ topics, snapshots/seek replay, exactly-once for some subscription types. **Spanner** = globally strongly-consistent SQL (TrueTime); **AlloyDB** = Postgres-compatible with columnar acceleration.

**Multi-cloud:** distinguish **portable** (K8s + OTel + Terraform + GitOps + Postgres + Kafka + **Iceberg/Delta** open table formats — cheap, do it) from **actively multi-cloud** (expensive; needs a specific driver: best-of-breed service, regulation, M&A, provider risk). Costs: duplicated platform engineering, LCD abstraction, **egress**, doubled security surface, incident complexity. Default recommendation: **single cloud, multi-region, portable architecture, documented exit plan.**

**Hybrid:** dedicated circuits + BGP + VPN backup; central IdP federated everywhere; **L3 + DNS, not stretched L2**; decide placement by latency-to-data, egress cost, regulation, and skill; treat hybrid as a *migration state* with an end date unless regulation says otherwise.

**Cross-cloud data:** open table formats as the portability layer; **one canonical write location**, read-only replicas; **move compute to data**; unified catalog + governance or you have two platforms; freshness SLOs per dataset with alerts; idempotent restartable pipelines; data-quality gates.

**Evaluating a migration:** precise question → measured baseline → total cost (direct + migration + duplication + risk) → **bounded pilot with a control** (re-platform in the current cloud) → decide (usually: optimise + selectively move + invest in portability) → if migrating, strangler-fig with rollback and validation gates.

→ Next: [`14-DevSecOps-and-Security`](../14-DevSecOps-and-Security/README.md)
