# Secrets Manager — Terraform how-to

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

**What:** a secret in Secrets Manager + rotation config + a Lambda with a role that can read it.

**Interview angle (SDE3):**
- Secrets Manager vs SSM Parameter Store: Secrets Manager = **secrets** (rotation, replication, cost per secret); SSM = **parameters** (cheaper, no built-in rotation for non-RDS).
- **Rotation** = a Lambda the service runs on a schedule to generate a new secret version (works out-of-the-box for RDS/DocumentDB/cluster).
- The app reads via `GetSecretValue` — the role needs `secretsmanager:GetSecretValue` scoped to the ARN.

## Run it
```bash
terraform init && terraform plan && terraform apply
# read:  aws secretsmanager get-secret-value --secret-id lab/db-password \
#           --query SecretString --output text
```

## Clean up
```bash
terraform destroy
```

## Common mistakes
| Mistake | Fix |
|---|---|
| App `AccessDenied` | the role is missing `secretsmanager:GetSecretValue` on that secret ARN (don't use `*`) |
| Rotation "works" but app still uses old password | the app must **refresh** the secret (or the RDS rotation updates the DB in place and the app reconnects) |
| `ResourceNotFoundException` | secret id is a name, but you need the **ARN** if it was created in another region/account |
