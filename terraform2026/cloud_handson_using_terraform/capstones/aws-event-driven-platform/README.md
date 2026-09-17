# Capstone 2 — AWS Event-Driven (Serverless) Platform

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

**What:** a fully **decoupled, event-driven** data pipeline + API in one apply:
**S3** (upload) → **Lambda** (process) → **DynamoDB** (store) + **API Gateway** (query) + **SNS** (announce) → **SQS** (buffer) → **Lambda worker** (consume).

**Why this is a capstone (the story you tell in the interview):**
- **Decoupling**: no service calls another directly — they exchange **events** (S3 notification, SNS, SQS). The interview: "what happens when one piece goes down?" → the **SQS buffer** absorbs it; the producer keeps going.
- **The queue pattern**: **SNS** (fan-out, 1→N) + **SQS** (buffer, durable, retries, DLQ). The "SNS→SQS" combination is the canonical answer to "how do you decouple and add a buffer?".
- **Serverless**: no servers to patch; Lambda scales to zero; the API is fronted by **API Gateway**.
- **Data**: **DynamoDB** (on-demand, GSI for alternate queries, TTL for cleanup).

**Run it:**
```bash
cd capstones/aws-event-driven-platform
terraform init && terraform plan && terraform apply
# test:  aws s3 cp payload.json s3://$(aws s3 ls --query 'Contents[?starts_with(Prefix, `evt-`)].Bucket | [0]' --output text)/uploads/payload.json
#   then watch DynamoDB + the worker queue.
terraform destroy
```

**Interview questions to be ready for:**
1. "Why Lambda and not a container/VM?" — **no servers**, scales per-request, pay-per-use; the cost is trivial for spiky work. (Trade-off: cold starts + a 15-min ceiling.)
2. "What if the worker is down when a message arrives?" — the **SQS** holds it (up to 14 days); the worker picks it up when it's back. That's the **buffer**.
3. "How do you handle a message that keeps failing?" — **retries** (maxReceiveCount) → **dead-letter queue** (the `DLQ` here); you alert on the DLQ, not on the main queue.
4. "Why DynamoDB?" — single-digit ms, on-demand (no capacity to tune), a **GSI** (`StatusIndex`) for "list by status" without a second table, **TTL** for auto-expiry.
5. "How is this secure?" — each Lambda has its **own role** (least privilege), the API can add **Cognito/IAM** auth, S3 is **private**, DynamoDB is **SSE + on-demand**.
6. "How would you make this multi-region?" — a **global DynamoDB** table + a **SNS** topic in the second region + **S3 replication** (the same pattern, mirrored).
