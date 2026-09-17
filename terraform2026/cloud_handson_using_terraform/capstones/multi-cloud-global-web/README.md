# Capstone 5 — Multi-Cloud Global Web (AWS + Azure, one DNS, health failover)

## 📁 File structure (the standard Terraform layout)

| File | What it does |
|---|---|
| `providers.tf` | the `terraform` block (required_providers) + provider config — "which cloud, which provider version, how to log in" |
| `variables.tf` | input variables — the knobs (e.g. `region`) you change without touching the resources |
| `main.tf` | the resources — the actual infrastructure Terraform creates (and any `data` lookups) |
| `outputs.tf` | output values — the endpoints/ids/URLs Terraform prints after `apply` |

> Why four files? Terraform reads **every** `.tf` file in the folder as one program. Splitting by
> concern is the industry convention: reviewers find the resources in `main.tf`, you change
> settings in `variables.tf`, and you read results in `outputs.tf` — instead of one 500-line file.

**What:** a **single global web entry point** that serves from **both clouds** and **fails over** automatically:
- **AWS** (us-east-1): an **ALB** + an **EC2** web tier.
- **Azure** (eastus): an **App Service** (F1).
- **Route 53** (the global brain): a **primary + failover** record set with **health checks** on both endpoints — if the primary (AWS) goes unhealthy, DNS flips to Azure (and vice-versa).

**Why this is a capstone (the story you tell in the interview):**
- **Multi-cloud is about redundancy + leverage**: you're not locked in, and a **regional cloud outage** doesn't take you down. The **DNS layer (Route 53)** is the orchestrator.
- **Health checks** (not "is the process alive") — Route 53 **polls the actual URL** (HTTP 200 on the ALB / the App Service).
- The **failover model**: primary + secondary + a health check on each; the **failover record** returns the healthy one. (A **latency** record would route by the nearest healthy region — the "global low-latency" variant.)
- **The hard parts you can name**: the **two different LBs** (ALB vs App Service), **different auth/secret stores** (Secrets Manager vs Key Vault), and **reconciling the health-check semantics** between the clouds.

**Run it:**
```bash
cd capstones/multi-cloud-global-web
terraform init && terraform plan && terraform apply   # ⚠️ EC2, App Service, health checks cost — DESTROY after
terraform destroy
```

**Interview questions to be ready for:**
1. "Why Route 53 as the global brain and not Azure DNS?" — **Route 53** has **health checks + failover/latency/geographic** record types built in; **Azure** has **Traffic Manager** (DNS-based, similar). Either works — pick the one you already operate. (The interview loves "which, and why?")
2. "How fast is the failover?" — it's **DNS-based**, so it's bounded by **TTL** (lower = faster, more queries) + the **health-check interval**. Not instant — pair it with a **client retry** for true resilience.
3. "What if BOTH are healthy — where does traffic go?" — the **primary** (AWS). To **split** traffic by geography, use a **geographic** record set; to **split by latency**, a **latency** record set.
4. "How do you keep the two backends in sync?" — this capstone is **stateless** (a static page). For state: a **shared data layer** (e.g. a **global database** — DynamoDB global tables / Cosmos multi-region) or **cross-cloud replication** (S3 → Blob).
5. "What breaks first?" — the **health check** (a false negative flips traffic unnecessarily) or the **TLS cert** (each cloud needs its own). Keep the health-check path **lightweight** and the **certs** managed.
