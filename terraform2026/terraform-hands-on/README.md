# Terraform Hands-On — AWS & Azure (28 Projects, Basic → Mastery)

Small, runnable projects that practice the theory in `../terraform-mastery/`.
Each project = **one folder** with fully commented `.tf` files (line by line).
You run them, break them, and destroy them.

## Structure

```
terraform-hands-on/
├── aws/                  ← AWS track (14 projects)
│   ├── project-01-first-s3-bucket/
│   ├── project-02-variables-outputs/
│   ├── project-03-ec2-web-server/
│   ├── project-04-for-each-and-count/
│   ├── project-05-your-first-module/
│   ├── project-06-remote-backend-state/
│   ├── project-07-iam-lambda-serverless/
│   ├── project-08-capstone-3-tier-app/
│   ├── project-09-cloudwatch-alarms-autoscaling/
│   ├── project-10-sns-sqs-decoupled-architecture/
│   ├── project-11-dynamodb-secrets-and-iam/
│   ├── project-12-apigw-lambda-dynamodb/
│   ├── project-13-step-functions-order-workflow/
│   └── project-14-kinesis-eventbridge-realtime/
└── azure/                ← Azure track (14 projects)
    ├── project-01-first-storage/
    ├── project-02-variables-outputs/
    ├── project-03-first-vm-ssh/
    ├── project-04-for-each-and-count/
    ├── project-05-your-first-module/
    ├── project-06-remote-backend-state/
    ├── project-07-key-vault-serverless/
    ├── project-08-capstone-3-tier-app/
    ├── project-09-observability-app-insights/
    ├── project-10-service-bus-and-queues/
    ├── project-11-cosmos-key-vault-managed-identity/
    ├── project-12-functions-service-bus-blob/
    ├── project-13-event-hubs-stream-analytics/
    └── project-14-api-management-gateway/
```

## The ladder — same skill on both clouds

| # | Skill you're learning | AWS project | Azure project | ⏱️ Time |
|---|---|---|---|---|
| 1 | The `init` → `plan` → `apply` → `destroy` loop | project-01-first-s3-bucket | project-01-first-storage | ~30 min |
| 2 | Variables, outputs, `tfvars`, validation | project-02-variables-outputs | project-02-variables-outputs | ~40 min |
| 3 | Your first web server (compute + firewall + image lookup) | project-03-ec2-web-server | project-03-first-vm-ssh | ~60 min |
| 4 | Looping: `for_each` and `count` | project-04-for-each-and-count | project-04-for-each-and-count | ~45 min |
| 5 | Your first module (reusable code) | project-05-your-first-module | project-05-your-first-module | ~60 min |
| 6 | Remote backend, state surgery, `import` | project-06-remote-backend-state | project-06-remote-backend-state | ~60 min |
| 7 | Identity + serverless | project-07-iam-lambda-serverless | project-07-key-vault-serverless | ~75 min |
| 8 | **Capstone: 3-tier web app (mastery)** | project-08-capstone-3-tier-app | project-08-capstone-3-tier-app | ~2.5 hrs |
| 9 | Observability: alarms + auto-scaling / app telemetry | project-09-cloudwatch-alarms-autoscaling | project-09-observability-app-insights | ~50 min |
| 10 | Real-time messaging: decouple producers & consumers | project-10-sns-sqs-decoupled-architecture | project-10-service-bus-and-queues | ~60 min |
| 11 | Data + secrets + identity (DynamoDB / Cosmos + Key Vault) | project-11-dynamodb-secrets-and-iam | project-11-cosmos-key-vault-managed-identity | ~60 min |
| 12 | Real-time API / Functions pipeline (API Gateway / Service Bus) | project-12-apigw-lambda-dynamodb | project-12-functions-service-bus-blob | ~60 min |
| 13 | Orchestration + real-time streaming (Step Functions / Event Hubs + Stream Analytics) | project-13-step-functions-order-workflow | project-13-event-hubs-stream-analytics | ~60 min |
| 14 | Continuous streams + public APIs (Kinesis / API Management) | project-14-kinesis-eventbridge-realtime | project-14-api-management-gateway | ~60 min |

**Total: ~15 hours** of hands-on (≈ 2–3 weeks at 1 hr/day).

## One-time setup (do this once, before Project 1)

**1. Terraform (any OS):**

```bash
terraform -version        # must print 1.5 or newer
```

**2. AWS track** — get credentials, then configure:

```bash
aws configure             # paste your Access Key ID / Secret Key / region (us-east-1)
aws sts get-caller-identity   # sanity check: should show your account
```

**3. Azure track** — log in with Azure CLI:

```bash
az login
az account set --subscription "<your-subscription-name>"   # pick one
terraform output         # (not yet) — instead verify with: az account show -o table
```

## How to run ANY project (same 7 steps every time)

```bash
cd aws/project-01-first-s3-bucket      # 1. go into the project folder
cat README.md                          # 2. read the project plan first
terraform init                         # 3. download the providers (first time only)
terraform plan                         # 4. read what WILL happen
terraform apply                        # 5. make it happen (type yes)
# ... verify in the cloud console (each README says how) ...
terraform destroy                      # 6. ALWAYS tear it down
```

## The 3 rules

1. **Destroy what you create.** `terraform destroy` after every project — this is part of the lesson (teardown order) and it keeps your bill at ~$0.
2. **Stay on free tier.** AWS: `t4g.micro` + small S3. Azure: `Standard_B1s` + free-tier storage. Never `m5`/`Standard_D2s_v3` "just to try".
3. **Predict before you apply.** Change one line, run `plan` first, say out loud what you think will happen (in-place update? replacement?), then apply and check.

## Provider version notes (read this once)

The projects target the **current `~> 5.0` providers** (validated with `terraform validate` on
Sept 2026). A few argument/block names changed since the older docs this course is based on.
Wherever they differ, **trust the project code**:

| What | Old docs say | Current 5.x projects use |
|---|---|---|
| NSG on a NIC (Azure) | `network_security_group_id` on `azurerm_network_interface` | separate `azurerm_subnet_network_security_group_association` resource |
| NIC private IP (Azure) | `private_ip_allocation_method` | `private_ip_address_allocation` |
| VM boot script (Azure) | `custom_data = <<-EOF ... EOF` | `custom_data = base64encode(<<-EOF ... EOF)` |
| Web app settings (Azure) | `site_config { app_settings = {...} }` | top-level `app_settings = {...}` (+ an empty `site_config {}` is still required) |
| Key Vault (Azure) | optional `rbac_authorization_enabled` | **required** (`= false` for classic access policies) |
| SQL server FQDN (Azure) | `.fqdn` | `.fully_qualified_domain_name` |
| App Gateway SKU (Azure) | `sku_name = "WAF_v2"` | `sku { name = "WAF_v2", tier = "WAF_v2" }` block |
| App Gateway wiring (Azure) | `frontend_port_id = ...frontend_port[0].id` etc. | **name-based** references (`frontend_port_name = "port-80"`, `http_listener_name = ...`) — the ID blocks are sets |
| Storage container (Azure) | `storage_account_name` | `storage_account_id` |
| Assume-role policy (AWS) | `principal { }` inside `aws_iam_policy_document` | `principals { }` |
| S3 → Lambda (AWS) | `lambda_function_configuration { }` | `lambda_function { }` |
| CloudFront OAC (AWS) | `name` optional | `name` **required** |

If you ever get `Error: Unsupported argument` / `Missing required argument`, run
`terraform providers schema -json` in the project folder and read the exact schema — that's
the same trick used to write these files.

## Which course notes does each project use?

| Project # | Reads best with (in `../terraform-mastery/`) |
|---|---|
| 1 | 00-core/01, 00-core/02 |
| 2 | 00-core/03 |
| 3 | 00-core/05 + the cloud's networking/compute notes |
| 4 | 00-core/07 |
| 5 | 00-core/06 |
| 6 | 00-core/04 + 00-core/07 (import) |
| 7 | the cloud's serverless + identity notes |
| 8 | the cloud's capstone notes |
| 9 | the cloud's observability + monitoring notes |
| 10 | the cloud's messaging notes (SNS/SQS, Service Bus) |
| 11 | the cloud's database + secrets notes (DynamoDB/SSM, Cosmos/Key Vault) |
| 12 | the cloud's API/serverless notes (API Gateway, Functions + Service Bus) |
| 13 | the cloud's streaming/orchestration notes (Step Functions, Event Hubs + Stream Analytics) |
| 14 | the cloud's streaming/API notes (Kinesis, API Management) |
