# CloudWatch — Terraform how-to

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

**What:** the observability stack: a log group, a **metric filter** (events → metrics), an **alarm** (metric → SNS), and a **dashboard**.

**Interview angle (SDE3):**
- Metric filter = "turn log lines into a number" (e.g. count `"status":500` per minute) — the bridge from logs to alarms.
- Alarm actions: alarm_actions (when ALARM), ok_actions, insufficient_data_actions — and SNS is the universal pager.
- Basic metrics (CPU per instance) are free; custom metrics + high-resolution (1s) cost.

## Run it
```bash
terraform init && terraform plan && terraform apply
# verify: aws cloudwatch describe-alarms
#         aws cloudwatch describe-log-groups
# test the filter: put a matching line into the log group via an app, or
#   aws logs put-log-events (after creating a log stream)
```

## Clean up
```bash
terraform destroy
```

## Common mistakes
| Mistake | Fix |
|---|---|
| Alarm stuck at `INSUFFICIENT_DATA` | the metric has no data yet — the metric filter needs matching log lines first (give it time/traffic) |
| Filter matches nothing | the pattern is a literal JSON match — test it in the console's "test pattern" before deploying |
