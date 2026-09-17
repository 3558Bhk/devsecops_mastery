# App Service — Terraform how-to

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

**What:** a **Linux web app** on a **Consumption** plan (Y1) — the fastest way to deploy a PaaS web app.

**Interview angle (SDE3):**
- **App Service** = a fully **managed PaaS** (scale, TLS, CI/CD) for web apps, APIs, and **Functions**.
- **Plans**: **Consumption** (Y1, pay-per-execution, no scale-out, always-on off) vs **Basic/Standard/Premium** (a dedicated pool, scale-out, **always-on**). The interview: "why can't I scale out on Consumption?" → it's a shared, serverless plan.
- The **runtime** is set by `site_config` (or `linux_fx_version` for Linux) — e.g. `NODE|20`, `python3.11`, `DOTNETCORE|8.0`.
- **App settings** = environment variables (connection strings, config) — they're **encrypted at rest** and not shown in the API.

## Run it
```bash
terraform init && terraform plan && terraform apply
# verify: az webapp list -g rg-lab-appsvc
#   az webapp show -g rg-lab-appsvc -n webapp-lab --query defaultHostname
# deploy: az webapp deploy --name webapp-lab --resource-group rg-lab-appsvc --src-path ./code
```

## Clean up
```bash
terraform destroy
```

## Common mistakes
| Mistake | Fix |
|---|---|
| App "sleeps" after a few minutes | the **Consumption** plan is **not** always-on — set `always_on = true` (requires a **dedicated** plan, not Consumption) |
| Can't scale out | **Consumption** has **no** scale-out — use a **Basic/Standard** plan to scale out |
| "Runtime not found" | the `linux_fx_version` / `app_settings` runtime (e.g. `NODE|20`) must be a valid **SKU** — check the supported runtimes |
