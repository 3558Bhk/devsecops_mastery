# Lambda — Terraform how-to

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

**What:** the minimal-but-real function: role + zipped code + the function + a test invoke.

**Interview angle (SDE3):**
- Lambda = compute without servers; you pay per-request (GB-s) + duration; the cold start is the trade-off.
- The role's **trust policy** (lambda.amazonaws.com) + **permissions** (logs, and whatever it touches) — the two-document pattern.
- Triggers: API Gateway, S3, SQS, EventBridge, CloudWatch Events, another Lambda — the function is the hub of serverless.

## Run it
```bash
terraform init && terraform plan && terraform apply
# invoke it:  aws lambda invoke --function-name lab-hello /tmp/out.json
#             cat /tmp/out.json
# logs:       aws logs tail /aws/lambda/lab-hello --follow
```

## Clean up
```bash
terraform destroy
```

## Common mistakes
| Mistake | Fix |
|---|---|
| `Resource not found` on invoke | the function name vs ARN mix-up — check `aws lambda list-functions` |
| Timeouts | the default timeout is 3s — raise `timeout` for anything that does I/O |
| `Execution failed: module not found` | the zip must contain the file at the **root** of the zip (not inside a folder) — check how `archive_file` was built |
