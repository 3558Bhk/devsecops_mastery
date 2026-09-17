# CloudTrail — Terraform how-to

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

**What:** the audit trail of **who did what to every API** — a multi-region trail into S3, with Insights (anomaly detection).

**Interview angle (SDE3):**
- CloudTrail = API-level audit (not network traffic); "who deleted the bucket, when, from where" is a CloudTrail question.
- **Insights** = ML anomaly detection over the API-call patterns (a spike of `DeleteBucket` calls alerts).
- Pair it with **Config** (resource state over time) — Trail = events, Config = snapshots.

## Run it
```bash
terraform init && terraform plan && terraform apply
# verify: aws cloudtrail describe-trails
# do something (e.g. aws s3 ls), then check the trail's bucket: trail-lab-2026/AWSLogs/<acct>/CloudTrail/…
```

## Clean up
```bash
terraform destroy
```

## Common mistakes
| Mistake | Fix |
|---|---|
| No events in the bucket | the trail's `enable_logging` is off, or you only recorded data events — API (management) events are the default |
| Events missing for other regions | `is_multi_region_trail = false` → only this region is recorded |
