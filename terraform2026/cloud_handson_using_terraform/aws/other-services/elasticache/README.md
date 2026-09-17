# ElastiCache — Terraform how-to

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

**What:** a single-node Redis (ElastiCache) in a subnet group + an app security group that allows the app to talk to it.

**Interview angle (SDE3):**
- ElastiCache = managed **Redis** (or Memcached). Redis = in-memory (cache, pub/sub, queues); Memcached = simpler, cache-only.
- **Subnet group** is required for VPC caches (in a subnet group you list subnets, typically ≥2 AZs).
- Cache nodes are **not** directly reachable from your laptop by default — the app (in the VPC) connects over the endpoint; use a bastion/Session Manager if you must.
- Redis **cluster mode** = sharding (multiple shards, each with a primary + replicas). Single node = no HA; add a **replica** for failover.

## Run it
```bash
terraform init && terraform plan && terraform apply   # ⚠️ cache nodes cost — destroy when done
# verify:  aws elasticache describe-caches --cache-cluster-id lab-redis
# connect (from an instance in the VPC):  redis-cli -h $(terraform output -raw endpoint)
```

## Clean up
```bash
terraform destroy   # do this the moment you're done
```

## Common mistakes
| Mistake | Fix |
|---|---|
| "Connection refused / timeout" from laptop | ElastiCache nodes are private (no public IP) — connect from inside the VPC or via SSM |
| "You must specify a subnet group" | VPC caches **require** a `subnet_group_name` (list ≥1, ideally ≥2 subnets) |
| Single node = no HA | add a **replica** (`replication_group_id`) so it can fail over to another AZ |
