# SQS — Terraform how-to

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

**What:** a standard queue + a **dead-letter queue** + a redrive policy — the work-queue pattern.

**Interview angle (SDE3):**
- SQS = the decoupling primitive: producer → queue → consumer (different speed, different lifetime, retries built in).
- **Visibility timeout** = "hide a message while it's being processed"; the consumer must delete it (or it reappears).
- **DLQ + redrive** = poison-message handling: after N failed deliveries, the message parks in the DLQ for inspection.
- Standard (at-least-once, best-effort order) vs FIFO (strict order, 300 msg/s base) — know the trade.

## Run it
```bash
terraform init && terraform plan && terraform apply
# send:  aws sqs send-message --queue-url $(aws sqs get-queue-url --queue-name lab-work \
#         --query QueueUrl --output text) --message-body "hello"
# receive: aws sqs receive-message --queue-url <same> --wait-time-seconds 5
```

## Clean up
```bash
terraform destroy
```

## Common mistakes
| Mistake | Fix |
|---|---|
| Messages "duplicated" after processing | at-least-once delivery: you must **delete** the message (or use a visibility timeout longer than processing) — design idempotent consumers |
| DLQ never fills | `maxReceiveCount` counts *receive* failures — a consumer that never receives doesn't increment it |
| `AWS.SimpleQueueService.NonExistentQueue` | the queue name is per-region — check `--region` |
