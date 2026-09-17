# Capstone 1 — AWS Production Web App (full 3-tier)

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

**What:** a complete, "interview-ready" production stack in one `terraform apply`:
VPC (public/private subnets) + NAT Gateway + **NACL** + **VPC Endpoints** + **ALB** + **ASG** (auto-scaling) + **RDS MySQL** + **ElastiCache Redis** + **KMS** + **Secrets Manager** + **CloudTrail** + **AWS Config** + **Route 53** + **CloudFront**.

**Why this is a capstone (the story you tell in the interview):**
- **Security**: private subnets for app/db/cache (no public IPs), **NACL** as a second, stateless layer, **VPC endpoints** (S3/DynamoDB traffic stays on the AWS backbone, not the Internet), **KMS**-encrypted EBS + **Secrets Manager** for the DB password.
- **Resilience**: ALB + ASG across **2 AZs**, RDS in a **DB subnet group** (multi-AZ off in the lab, on in prod), ElastiCache for the hot path.
- **Observability/governance**: **CloudTrail** (API audit) + **AWS Config** (compliance rules) — "I don't just build it, I audit it and govern it".
- **Global delivery**: **CloudFront** in front of the ALB + a **Route 53** alias record.

**Run it:**
```bash
cd capstones/aws-production-web-app
terraform init && terraform plan && terraform apply   # ⚠️ NAT GW, ALB, RDS, cache, CF all cost — DESTROY after
terraform destroy
```

**Interview questions to be ready for:**
1. "Why a NAT Gateway and not a public subnet for the DB?" — the DB must never be Internet-reachable; the NAT lets *outbound* (patching) happen.
2. "What does the NACL add that the security group doesn't?" — a **stateless, subnet-level** allow/deny with explicit rule numbers (100–32766); SGs are stateful instance-level. Defense in depth.
3. "Why VPC endpoints?" — S3/DynamoDB calls from private subnets go over the **AWS private backbone** (cheaper, faster, never on the public Internet).
4. "Where does the DB password live, and how does the app get it?" — **Secrets Manager** (not a plain-text env var); the app's role is granted `secretsmanager:GetSecretValue` scoped to the secret ARN; rotation is a schedule.
5. "How does it scale?" — an **ASG** with a **target-tracking policy** (CPU 40%); the **launch template** holds the AMI/SG/user_data, so scale-out is just "more of the same".
6. "How do you detect drift/misconfig?" — **AWS Config** (rule: volumes must be encrypted) + **CloudTrail** (who called what API) + **CloudWatch** alarms (not in this file — add a 5xx alarm to the ALB).
7. "What's the cost of this, and how would you make it cheaper?" — NAT GW + RDS + cache are the big ones; for a dev env: single AZ, no NAT (or a cheaper NAT), RDS `db.t4g.micro`, cache `cache.t4g.micro`, or run the app **serverless** (the event-driven capstone).
