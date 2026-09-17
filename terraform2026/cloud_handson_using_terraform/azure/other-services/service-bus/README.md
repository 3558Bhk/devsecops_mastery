# Service Bus — Terraform how-to

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

**What:** a **Service Bus** namespace + a **queue** + a **topic** + a **subscription** — the managed messaging (pub/sub + point-to-point).

**Interview angle (SDE3):**
- **Service Bus** = a fully **managed messaging** (PaaS) — **queues** (point-to-point, 1 consumer) + **topics** (pub/sub, N subscribers).
- **Queue vs Topic**: a **queue** = each message is consumed by **one** receiver (work distribution); a **topic** = each message is delivered to **all** subscribed subscribers (fan-out).
- **Dead-letter** + **max delivery count** = the "poison message" handling (a message that keeps failing goes to the DLQ).
- **Sessions** (ordered) + **Transactions** = advanced; the interview: "how do you guarantee ordering?" → **sessions** (per-session ordering).

## Run it
```bash
terraform init && terraform plan && terraform apply
# verify: az servicebus namespace list -g rg-lab-sb
#   az servicebus queue list -g rg-lab-sb -n sb-lab
#   az servicebus topic list -g rg-lab-sb -n sb-lab
#   az servicebus topic subscription list -g rg-lab-sb -n sb-lab -t topic-lab
```

## Clean up
```bash
terraform destroy
```

## Common mistakes
| Mistake | Fix |
|---|---|
| Message "not delivered" | the **subscription** is missing (a topic needs a subscription to deliver) — or the **consumer** isn't connected |
| Message keeps failing | it's being **retried** up to `max_delivery_count`, then it goes to the **dead-letter queue** — check the DLQ |
| "Namespace not found" | the queue/topic is scoped to a **namespace** — you need the **namespace name** + the entity name |
