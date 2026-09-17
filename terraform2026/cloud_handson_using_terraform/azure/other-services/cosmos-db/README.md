# Cosmos DB — Terraform how-to

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

**What:** a **Cosmos DB** account (MongoDB API, autoscale off) + a **SQL database** + a **container** (with a partition key).

**Interview angle (SDE3):**
- **Cosmos DB** = a **globally distributed, multi-model, NoSQL** database with **SLA** (99.99%) + **auto-scaling throughput**.
- **APIs**: **Core (SQL)**, **MongoDB**, **Table**, **Gremlin**, **Cassandra** — the interview: "which API for a document app?" → **Core (SQL)** (or Mongo for a Mongo team).
- **Consistency levels** (strong→weak): **Strong**, **Bounded Staleness**, **Session**, **Consistent Prefix**, **Eventual** — the trade-off: **stronger = lower throughput / higher latency**.
- **Partition key** = the sharding key (affects cost + query) — pick it carefully (high cardinality, even distribution).
- **Throughput**: **Provisioned** (RU/s) vs **Autoscale** (scales up/down) vs **On-demand** (pay-per-request).

## Run it
```bash
terraform init && terraform plan && terraform apply   # ⚠️ throughput costs — destroy when done
# verify: az cosmosdb list -g rg-lab-cosmos
#   az cosmosdb sql database list -g rg-lab-cosmos -n cosmos-lab
#   az cosmosdb sql container list -g rg-lab-cosmos -a cosmos-lab -d db-lab
```

## Clean up
```bash
terraform destroy   # do this the moment you're done
```

## Common mistakes
| Mistake | Fix |
|---|---|
| "AccessDenied" / connection refused | the account's **firewall** blocks the client IP (or you need a **connection string** with the right key) — check the network ACLs |
| Slow queries / high cost | the **partition key** is wrong (low cardinality or uneven) — re-shard with a better key |
| Consistency "too strong" | **Strong** consistency is the **slowest/most expensive** — drop to **Session** (the default) unless you need Strong |
