# Auto Scaling — Terraform how-to

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

**What:** a launch template + ASG + a **target-tracking** policy that scales the fleet to hold CPU at a set percentage.

**Interview angle (SDE3):**
- Target tracking ("keep CPU at 40%") vs scheduled scaling ("5 instances at 9am") vs predictive (ML on history) — know when each fits.
- ASG + Launch **template** (not config) is the modern pair; the template also carries tags/user_data/SGs.
- Scale-in cooldown and "instance refresh" (rolling a new AMI across the fleet with zero downtime) are the follow-up questions.

## Run it
```bash
terraform init && terraform plan && terraform apply
# verify: aws autoscaling describe-auto-scaling-groups
#         aws autoscaling describe-scaling-activities   # watch it react
# stress: aws autoscaling set-desired-capacity --auto-scaling-group-name <name> --desired-capacity 2
```

## Clean up
```bash
terraform destroy
```

## Common mistakes
| Mistake | Fix |
|---|---|
| ASG stuck at `Pending` | instances failing health checks — check the SG + the user_data (is the port actually open?) |
| It never scales in | target tracking has scale-in protection by default; also check `min_size`/cooldowns |
| New instances have no public IP | the launch template's subnet must be public (or map_public_ip in the template) |
