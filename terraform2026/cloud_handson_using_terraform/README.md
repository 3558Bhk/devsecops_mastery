# Cloud Hands-On Using Terraform

A **from-scratch** Terraform course: every service below is its **own folder** following the
**standard Terraform file layout** — `providers.tf` (provider config) + `variables.tf` (the knobs,
e.g. `region`) + `main.tf` (line-by-line commented resources) + `outputs.tf` (the results) —
validated against **AWS provider 5.100** and **azurerm 5.5** — plus a compact README
(what it is / the **file structure** / the **SDE-3 interview angle** / run it / clean up /
common mistakes). At the end: **6 capstone projects** (4 single-cloud + 2
**multi-cloud AWS+Azure**).

> ⚠️ **Cost warning** — anything with a running resource (VM, RDS, AKS, NAT GW,
> App Service, Cosmos, LB, VPN gateway, Flow Logs, Defender…) **costs money by the
> hour/second**. The rule for every folder: `terraform apply` → learn → `terraform destroy`
> **immediately**.

## 📘 AWS (`aws/`)

| Group | Folder | Services |
|---|---|---|
| Networking | `aws/networking/` | VPC Peering, Transit Gateway, Security Groups, NACL, NAT Gateway, VPC Endpoints |
| Load Balancing & Traffic Routing | `aws/load-balancing-traffic-routing/` | ALB, NLB, Global Accelerator |
| Storage | `aws/storage/` | S3 Bucket, EBS Volumes |
| Databases | `aws/databases/` | MySQL (RDS), DynamoDB |
| IAM | `aws/iam/` | IAM Policies, Inline Policies |
| Compute | `aws/compute/` | AMI, Auto Scaling |
| Monitoring & Governance | `aws/monitoring-governance/` | CloudWatch, CloudTrail, AWS Config |
| Other (interview favourites) | `aws/other-services/` | Route 53, CloudFront, Lambda, SQS, SNS, API Gateway, ECS, EKS, KMS, Secrets Manager, Systems Manager, ElastiCache |

## 📗 Azure (`azure/`)

| Group | Folder | Services |
|---|---|---|
| Networking | `azure/networking/` | Basic Networking, NSG Intro, NSG Inbound, NSG Outbound, ASG, Hub & Spoke, VPN |
| Load Balancing & Traffic Management | `azure/load-balancing-traffic-management/` | Load Balancer, Application Gateway, Traffic Manager, Front Door |
| Compute | `azure/compute/` | Virtual Machines, Image Creation |
| Storage | `azure/storage/` | Storage Accounts, Identity Mgmt in Storage |
| Backup & Recovery | `azure/backup-recovery/` | RSV Backup, RSV Restore |
| Identity | `azure/identity/` | Active Directory (Entra ID) |
| Databases | `azure/databases/` | Azure SQL |
| Monitoring | `azure/monitoring/` | Azure Monitor, Log Analytics, NSG Flow Logs |
| PaaS & Integration | `azure/paas-integration/` | App Service, Azure API Services |
| Other (interview favourites) | `azure/other-services/` | Azure Functions, Logic Apps, Key Vault, Cosmos DB, AKS, Service Bus, Azure DevOps, Defender for Cloud |

## 🏆 Capstones (`capstones/`)

| # | Folder | What it builds |
|---|---|---|
| 1 | `capstones/aws-production-web-app/` | AWS 3-tier: VPC + NAT + NACL + VPC endpoints + ALB + ASG + RDS + ElastiCache + KMS + Secrets Manager + CloudTrail + AWS Config + Route 53 + CloudFront |
| 2 | `capstones/aws-event-driven-platform/` | AWS serverless pipeline: S3 → Lambda → DynamoDB + API Gateway + SNS → SQS → Lambda worker (DLQ) |
| 3 | `capstones/azure-landing-zone/` | Azure landing zone: hub & spoke + NSG flow logs + Log Analytics + Monitor alerts + Key Vault (RBAC) + App Service + Azure SQL + RSV backup |
| 4 | `capstones/azure-serverless-order-platform/` | Azure serverless: Front Door → App Service → Service Bus → Functions → Cosmos DB + Key Vault (RBAC) |
| 5 | `capstones/multi-cloud-global-web/` | **AWS + Azure**: one Route 53 name, health-based **failover** between an AWS ALB+EC2 and an Azure App Service |
| 6 | `capstones/multi-cloud-disaster-recovery/` | **AWS primary → Azure warm standby**: EC2+RDS+S3 ⇄ App Service+Azure SQL+Blob, Route 53 health failover |

## How to use it

```bash
cd aws/networking/vpc-peering        # any folder
terraform init
terraform plan                        # read every line of the diff
terraform apply
# ...test it in the console/CLI...
terraform destroy                     # the part beginners forget
```

**Suggested order for SDE-3 prep:** each group's folders in table order → the two
single-cloud capstones for your primary cloud → the two **multi-cloud** capstones last
(they combine everything and give you the interview *stories*: "here's how I would run a
production app", "here's how I would do DR across clouds").

## Conventions used everywhere
- `main.tf` is **the** how-to: every line carries a one-line comment (beginner level).
- Cheapest possible SKUs (`t4g.micro` / `db.t4g.micro` / `B1s` / `F1` / `Y1` / `GP_S_G5`) so the labs are near-free.
- Dummy values (passwords, IPs, emails, domains) are flagged with **CHANGE** — swap them before any real run.
- Provider pins: `~> 5.0` for both `hashicorp/aws` and `hashicorp/azurerm` (validated on aws 5.100.0 / azurerm 5.5.0).
