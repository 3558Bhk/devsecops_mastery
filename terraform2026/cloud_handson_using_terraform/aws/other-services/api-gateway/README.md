# API Gateway — Terraform how-to

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

**What:** a minimal REST API: one resource, one method, a proxy integration to a Lambda, a deployment, a stage.

**Interview angle (SDE3):**
- The 5-object mental model: **REST API → resource (path) → method (verb) → integration (backend) → deployment+stage (publish)**. Forgetting the deployment is the #1 beginner bug ("API returns 403/404 even though everything is created").
- AWS_PROXY integration = "forward raw, parse raw" (no mapping templates).
- Auth options: open (NONE), API key, IAM, Lambda authorizer, Cognito — know the difference between a **custom authorizer** and **Cognito**.

## Run it
```bash
terraform init && terraform plan && terraform apply
# verify: curl https://$(terraform output -raw invoke_url)
```

## Clean up
```bash
terraform destroy
```

## Common mistakes
| Mistake | Fix |
|---|---|
| `403 {"message":"Missing Authentication Token"}` | you set `authorization` to IAM but are curling without signing — set `NONE` for a lab, or sign with SigV4 |
| API "exists" but 404 | there's no **deployment** — the API is only live once deployed to a stage |
| Integration 502 | the Lambda ARN in the integration is wrong, or the role can't be invoked |
