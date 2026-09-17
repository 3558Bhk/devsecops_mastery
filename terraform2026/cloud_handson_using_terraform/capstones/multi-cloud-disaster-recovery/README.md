# Capstone 6 — Multi-Cloud Disaster Recovery (AWS primary → Azure DR)

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

**What:** a **primary stack on AWS** (web EC2 + **RDS** + **S3**) with a **warm standby on Azure** (**App Service** + **Azure SQL** + **Blob**), and **Route 53** doing **health-based failover** between the two clouds.

**Why this is a capstone (the story you tell in the interview):**
- **DR = a pre-built secondary + a failover mechanism.** The secondary isn't "a backup you restore" — it's **already running** (warm standby), so failover is **DNS**, not a multi-hour restore.
- **The data story** (the hard part, and what the interviewer probes): **AWS → Azure data sync** is not native. The patterns are: **RDS → Azure SQL** via **export/import** (a scheduled SQL dump → Blob → import), **S3 → Blob** via **cross-cloud replication** (a Lambda + the Azure Storage SDK, or an ETL tool), or a **shared global database** (DynamoDB global tables / Cosmos multi-region) when you can standardize.
- **The failover mechanism**: Route 53 **health checks** on the **primary (AWS)**; when it goes down, DNS flips to the **secondary (Azure)** (a **CNAME** to the App Service — the health check **follows the CNAME**).
- **Runbook**: failover (DNS + verify) → **fix the primary** → **re-sync data** → **fail back** (flip the DNS back, after confirming the primary is healthy and data is current).

**Run it:**
```bash
cd capstones/multi-cloud-disaster-recovery
terraform init && terraform plan && terraform apply   # ⚠️ EC2, RDS, App Service, SQL cost — DESTROY after
terraform destroy
```

**Interview questions to be ready for:**
1. "What's your RPO/RTO?" — **RPO** (data loss) = the **sync interval** (e.g. 15-min dumps); **RTO** (time to recover) = the **DNS TTL** + health-check interval (minutes, not hours). State both, and say what it costs to make them smaller.
2. "How do you keep the standby warm?" — a **scheduled sync** (RDS → Blob → Azure SQL; S3 → Blob) + a **health check** on the standby. "Warm" = running but not taking live writes.
3. "Why not active-active?" — **active-active** (both taking writes) is **much harder**: **conflict resolution**, **replication lag**, **data consistency**. It's the gold standard, but for most teams a **primary + warm standby** is the right trade-off.
4. "How do you test the failover?" — a **game day** (chaos drill): kill the primary, confirm the DNS flips, confirm the app serves from Azure, **then fail back**. You **test the runbook**, not just the infra.
5. "What's the cost of a warm standby?" — you pay for the **Azure** side 24/7 (App Service + SQL). The trade-off: **cheaper = slower RTO** (cold standby), **pricier = faster RTO** (warm/active-active).
