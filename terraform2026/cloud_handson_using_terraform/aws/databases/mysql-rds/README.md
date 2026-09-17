# MySQL (RDS) — Terraform how-to

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

**What:** a managed MySQL instance in private subnets, with a DB-specific security group and a generated password.

**Interview angle (SDE3):**
- RDS = managed (patching, backups, failover) vs EC2+MySQL (DIY). Multi-AZ = synchronous standby (HA), Read Replicas = scale reads (a different mechanism!).
- The DB subnet group = **the private subnets RDS may use** (one per AZ).
- `deletion_protection` + snapshot on delete = the data-safety pair you mention in any DB discussion.

## Run it
```bash
terraform init && terraform plan && terraform apply   # ~10 min to become available
# verify: aws rds describe-db-instances
# connect: mysql -h <endpoint> -u labadmin -p   (password: terraform output -raw db_password)
```

## Clean up
```bash
terraform destroy   # (it costs ~$10/mo on db.t4g.micro — don't leave it)
```

## Common mistakes
| Mistake | Fix |
|---|---|
| `InvalidDBSubnetGroup` | the subnet group needs subnets in **≥2 AZs** |
| App can't reach the DB | the DB SG's ingress must allow 3306 **from the app's SG** (and the app must be able to route to the private subnet — NAT/private subnet design) |
| Password in your shell history | `terraform output -raw db_password` prints it once; prefer storing it in Secrets Manager (see project-11 in terraform-hands-on) |
