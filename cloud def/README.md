# Cloud Interview Question Bank — AWS & Azure

A structured interview question bank covering **AWS** and **Azure**, organized by topic group. Every service has its own Markdown file with:

- **Case A — Basic** (15 questions): fundamentals, definitions, defaults.
- **Case B — Advanced / Senior** (12 questions): architecture, tradeoffs, internals.
- **Case C — Scenario** (6 questions): real-world situations with expected answers.
- A **JSON File Format** section: the JSON used by that service, with an example + key fields.
- A **reading-time estimate** in the header.

Every question includes a **full model answer**.

---

## Structure

```
├── aws/              → 32 AWS service files (15/12/6 Q&A each)
├── azure/            → 32 Azure service files (15/12/6 Q&A each)
├── aws-terraform/    → 20 Terraform-on-AWS topic files (15/12/6 Q&A each)
└── azure-terraform/  → 20 Terraform-on-Azure topic files (15/12/6 Q&A each)
```

## 🟠 Terraform — AWS & Azure

Terraform interview prep split into small topic files, in two folders:

- **[aws-terraform/ →](./aws-terraform/README.md)** — HCL, providers, state, variables, modules, workspaces, CI/CD, VPC, SGs, load balancers, Route 53/CloudFront, EC2/ASG, Lambda, ECS, EKS, S3, RDS/DynamoDB, IAM, messaging, monitoring.
- **[azure-terraform/ →](./azure-terraform/README.md)** — HCL, providers, state, variables, modules, workspaces, Azure DevOps CI/CD, resource groups/tags, VNet/subnets, NSGs, load balancing, VMs, App Service, Functions, AKS, Storage, SQL/Cosmos DB, Entra ID + RBAC, Key Vault, monitoring + messaging.

Each topic file follows the same format as the service files (Case A Basic / Case B Advanced / Case C Scenario, full answers, reading-time estimate) — no JSON section, since Terraform is HCL.

## 📘 AWS — [Index →](./aws/README.md)

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

## 📗 Azure — [Index →](./azure/README.md)

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

---

## How to use

1. **Prep by topic** — open the folder for the group you're weakest in.
2. **Practice the three levels** — Case A builds fundamentals; Case B tests senior depth; Case C tests design/decision-making.
3. **Mock interviews** — have someone read Case B/C questions and compare your answer to the model answer.
4. **Track gaps** — the Scenario answers are written as "expected answers" an interviewer would look for.
