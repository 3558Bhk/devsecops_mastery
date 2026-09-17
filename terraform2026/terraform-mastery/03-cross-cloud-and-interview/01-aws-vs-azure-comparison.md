# Cross-Cloud 1 — AWS vs Azure (Terraform Perspective)

> **⏱️ Time to complete: ~35 min** (read the mapping tables + do the translation drills)

The single most valuable skill: **translating** between the two clouds. Everything below is from the *Terraform provider* angle.

## 1.1 Core Concept Mapping

| Concept | AWS (terraform) | Azure (terraform) |
|---|---|---|
| Provider | `hashicorp/aws` | `hashicorp/azurerm` |
| Auth (CI, modern) | **OIDC** (GHA → STS web identity) | **OIDC** (GHA → federated credential) |
| Auth (dev) | SSO / profile / env vars | SP (secret/cert) / device login |
| "Account" | **AWS Account** | **Subscription** |
| "Container" | (none — resources live in an account) | **Resource Group** |
| Region | `region` | `location` |
| Identity dir | IAM | **Entra ID** (Azure AD) |
| Roles | IAM Role | RBAC Role + **Service Principal** / **Managed Identity** |
| VPC | `aws_vpc` | `azurerm_virtual_network` |
| Subnet | `aws_subnet` (**AZ-tied**) | `azurerm_subnet` (**not** AZ-tied) |
| Firewall | `aws_security_group` (ENI) + NACL | `azurerm_network_security_group` (subnet/NIC) |
| Internet egress | IGW + **NAT GW** | (public IP + routing; no "NAT GW" equivalent) |
| VM | `aws_instance` | `azurerm_linux_virtual_machine` |
| VM pool / ASG | `aws_autoscaling_group` + launch template | `azurerm_linux_virtual_machine_scale_set` |
| Object store | `aws_s3_bucket` | `azurerm_storage_account` + blob container |
| Block store | `aws_ebs_volume` | `azurerm_managed_disk` |
| File share | `aws_efs_file_system` | `azurerm_storage_share` (Azure Files) |
| Relational DB | `aws_db_instance` (RDS) | `azurerm_mssql_database` (Azure SQL) |
| NoSQL | `aws_dynamodb_table` | `azurerm_cosmosdb_account` |
| L4 LB | `aws_lb` (type `network`) | `azurerm_load_balancer` |
| L7 LB | `aws_lb` (type `application`) | `azurerm_application_gateway` |
| WAF | `aws_wafv2_web_acl` | App Gateway **WAF** / **Front Door** |
| CDN | `aws_cloudfront_distribution` | **Front Door** / CDN Profile |
| Serverless fn | `aws_lambda_function` | `azurerm_linux_function_app` |
| API gateway | `aws_api_gateway_*` | (Function App HTTP trigger) |
| Queue | `aws_sqs_queue` | `azurerm_storage_queue` / Service Bus |
| Pub/sub | `aws_sns_topic` | Service Bus / Event Grid |
| Event bus | `aws_cloudwatch_event_rule` | Event Grid |
| Secrets | `aws_secretsmanager_secret` | `azurerm_key_vault_secret` |
| KMS | `aws_kms_key` | Key Vault keys / **Azure Key Vault** |
| DNS | `aws_route53_zone` | `azurerm_dns_zone` |
| Monitoring | CloudWatch (`aws_cloudwatch_*`) | **Log Analytics** (`azurerm_monitor_*`) |
| Cost tagging | `default_tags` (provider) | `tags` per resource |

## 1.2 Authentication — Side by Side

| | AWS | Azure |
|---|---|---|
| CI (modern) | OIDC: `aws-actions/configure-aws-credentials` → STS `AssumeRoleWithWebIdentity` | OIDC: `azure/login` → federated credential (GHA issuer) |
| Dev | SSO (`aws sso login`) / profile | SP (secret/cert) / device login |
| On-cloud | Instance profile / IRSA (EKS) | **Managed Identity** |
| Provider block | `assume_role { role_arn }`, `profile`, env chain | `client_id`/`client_secret`/`client_certificate`, `use_msi`, OIDC env |
| Verify | `data.aws_caller_identity` | `data.azurerm_client_config` |
| Cross-"account" | provider **alias** + `assume_role` | provider **alias** + different `subscription_id` |

**The pattern is identical:** OIDC in CI, identity on the compute, provider aliases for multiple accounts/subscriptions, a data source to *verify which one you're in*.

## 1.3 Provider Quirks You'll Hit

### AWS-specific
- **`default_tags`** = provider-level tag policy (Azure has no direct equivalent — use a `local.common_tags` + `tags` on each resource).
- **Subnets are AZ-tied** (you pick `availability_zone`).
- **NAT GW** for private-subnet internet egress (Azure does public IP + routes instead).
- **S3 bucket name is global** (unique across all regions/accounts).
- **ACM certs for CloudFront must be in `us-east-1`**.
- **IAM** = the identity model (roles, policies, `assume_role`).

### Azure-specific
- **`features {}`** block is **required** (v4 `required_features`, v5 top-level).
- **v5**: resource providers **not** auto-registered by default (`resource_provider_registrations = "none"`).
- **Resources are 1:1 with a Resource Group** (can't move in place).
- **Storage / Key Vault / SQL server names are globally unique** (no hyphens for storage/KV).
- **Subnets are NOT AZ-tied** (AZs apply to VMs/scale sets).
- **RBAC** (roles + role assignments) instead of IAM policies; **granting roles needs User Access Administrator/Owner**.
- **Managed Identity** is the first-class keyless identity (AWS's equivalent is instance profiles/IRSA, but less pervasive).

## 1.4 Networking Pattern Differences

| | AWS | Azure |
|---|---|---|
| Internet egress for private subnets | **NAT Gateway** (per AZ) | Public IP + **User-Defined Routes** / (or the resource gets a public IP) |
| Firewall | **Security Group** (stateful, ENI) + NACL | **NSG** (stateful, subnet/NIC, priority, Allow/Deny) |
| Private service access | **VPC Endpoints** (gateway/interface) | **Service Endpoints** + **Private Endpoints** |
| L7 LB | ALB (path/host, TLS) | **App Gateway** (path/host, TLS, WAF, dedicated subnet) |
| Global CDN | **CloudFront** | **Front Door** |
| Many networks | **Transit Gateway** (hub-spoke) | **Virtual WAN** (hub-spoke) |
| Peering | **VPC peering** (non-transitive) | **VNet peering** (non-transitive, bidirectional) |

## 1.5 The "Translate an Architecture" Exercise

Take the **AWS capstone** (ch. AWS-11) and map it to the **Azure capstone** (ch. Azure-11):

| AWS capstone piece | Azure equivalent |
|---|---|
| `aws_vpc` + public/private subnets | `azurerm_virtual_network` + app/db subnets |
| `aws_security_group` | `azurerm_network_security_group` + rules |
| `aws_lb` (application) | `azurerm_application_gateway` |
| `aws_autoscaling_group` + launch template | `azurerm_linux_virtual_machine_scale_set` |
| `aws_db_instance` (RDS) | `azurerm_mssql_server` + `azurerm_mssql_database` |
| `aws_s3_bucket` | `azurerm_storage_account` + blob container |
| `aws_secretsmanager_secret` | `azurerm_key_vault_secret` |
| `aws_cloudfront_distribution` | **Front Door** |
| `aws_route53_record` | `azurerm_dns_a_record` |
| `aws_cloudwatch_metric_alarm` | `azurerm_monitor_metric_alert` + action group |
| `aws_iam_role` (instance profile) | `azurerm_user_assigned_identity` + `identity {}` on the VMSS |

**The mental model transfers 1:1** — only the *names, the hierarchy (RG/subscription), and a few quirks* differ.

## 1.6 What Stays the Same (the "Terraform part")

- **HCL**, **modules**, **state**, **backends**, **providers**, **plan/apply**, **idempotency** — all identical.
- **Best practices** (least privilege, remote locked state, no secrets in state, pin versions, `prevent_destroy`, tags, Infracost, `terraform test`) — identical.
- **The workflow** (init → plan → apply, PR-gated plans) — identical.

> **The skill to build:** once you know the *Terraform* part cold, a new cloud is just a **vocabulary translation** + a handful of quirks. That's why you learn core fundamentals first.

## 1.7 Quick Translation Drills (do these from memory)

1. "AWS Security Group allow 443 from the internet" → write the **Azure NSG rule**.
2. "Azure managed identity on a VM + Key Vault secret read" → write the **AWS instance profile + Secrets Manager** equivalent.
3. "AWS RDS multi-AZ Postgres" → write the **Azure SQL `zone_redundant`** equivalent.
4. "Azure App Gateway WAF" → write the **AWS ALB + WAFv2** equivalent.
5. "AWS CloudFront + private S3 (OAC)" → write the **Azure Front Door + private storage** equivalent.
