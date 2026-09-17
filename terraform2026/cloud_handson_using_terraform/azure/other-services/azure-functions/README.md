# Azure Functions — Terraform how-to

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

**What:** a **Linux Function App** on a Consumption plan (Y1) with a **system-assigned managed identity** for storage access (no keys).

**Interview angle (SDE3):**
- **Functions** = **serverless compute** (run a function, not a whole app) — triggered by HTTP, timer, queue, blob, etc.
- **Consumption** (Y1) = pay-per-execution, cold start, no always-on; **Premium/Plan** = dedicated. The interview: "when would you pick Consumption vs a dedicated plan?"
- The **storage account** is mandatory (for logging + triggers) — and with a **managed identity** you don't store a **connection string** (the modern, no-secret way).
- The runtime is set by the `FUNCTIONS_WORKER_RUNTIME` / `functions_extension_version` setting (python, node, dotnet).

## Run it
```bash
terraform init && terraform plan && terraform apply
# verify: az functionapp list -g rg-lab-func
#   az functionapp show -g rg-lab-func -n funcapp-lab --query defaultHostname
# deploy: az functionapp deploy --name funcapp-lab --resource-group rg-lab-func --src-path ./func
```

## Clean up
```bash
terraform destroy
```

## Common mistakes
| Mistake | Fix |
|---|---|
| "Storage account not found" | the Function App needs a **storage account** (for logs + triggers) — it's created here and wired via the **managed identity** |
| Function doesn't scale / "sleeps" | the **Consumption** plan has a **cold start** and is not always-on — use a **dedicated** plan for low-latency |
| "Runtime not found" | set the **worker runtime** (`FUNCTIONS_WORKER_RUNTIME`) to a valid value (python/node/dotnet) matching the code |
