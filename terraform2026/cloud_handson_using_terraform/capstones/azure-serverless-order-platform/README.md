# Capstone 4 — Azure Serverless Order Platform

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

**What:** a **serverless, event-driven** order-processing platform in one apply:
**Front Door** (global L7 + CDN) → **App Service** (the order API) → **Service Bus** (topic + subscription) → **Functions** (the worker) → **Cosmos DB** (the store) + **Key Vault** (the secrets, RBAC).

**Why this is a capstone (the story you tell in the interview):**
- **Global edge**: **Front Door** (any-pop, L7, CDN, WAF) in front of the **App Service** — the modern "one URL, global delivery" pattern.
- **Decoupling**: the API **publishes to a Service Bus topic**; a **Function** (triggered by the **subscription**) consumes it and writes to **Cosmos** — the producer and consumer never call each other.
- **The messaging model**: **topic** (fan-out, N subscribers) vs **queue** (1 consumer) — this is the **pub/sub** side; add a **queue** for work distribution.
- **Data**: **Cosmos DB** (Core/SQL, Session consistency, partition key `/customer`) — the "globally distributed, multi-model NoSQL with an SLA" answer.
- **Secrets**: **Key Vault** (RBAC) + a **managed identity** + **Key Vault Secrets Officer** — no keys in code.

**Run it:**
```bash
cd capstones/azure-serverless-order-platform
terraform init && terraform plan && terraform apply   # ⚠️ App Service, Cosmos, Functions cost — DESTROY after
terraform destroy
```

**Interview questions to be ready for:**
1. "Front Door vs Application Gateway?" — **Front Door** = **global** (any-pop, single VIP, CDN + WAF, works across regions); **App Gateway** = **per-region** L7 (closer to the VNet, per-region routing). Global + CDN → Front Door.
2. "Why Service Bus and not a plain queue?" — the **topic** lets **N independent consumers** each get the order (billing, shipping, notifications) — **fan-out**. A **queue** is 1-consumer (work distribution).
3. "What if the Function is down when an order arrives?" — the **Service Bus** holds the message (durable, up to 14 days) + **dead-letter** after `max_delivery_count` retries.
4. "Why Cosmos and not SQL?" — **global distribution + auto-scaling + multi-model + an SLA**; the trade-off: no ACID across partitions (use **transactions** within a partition).
5. "How do you secure the secrets?" — **Key Vault** (RBAC) + **managed identity** (the Function's identity gets **Secrets Officer**) — no connection string in the code.
6. "How would you scale this?" — **Front Door** scales globally; the **App Service** scales out (on a dedicated plan); **Cosmos** auto-scales **throughput** (or autoscale); the **Function** is **serverless** (per-execution).
