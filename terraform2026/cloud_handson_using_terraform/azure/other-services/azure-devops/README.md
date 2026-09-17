# Azure DevOps — Terraform how-to

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

**What:** an **Azure DevOps** team project + a **git repo** + a **variable group** — the CI/CD foundation (as code).

**Interview angle (SDE3):**
- **Azure DevOps** = **Repos** (git) + **Pipelines** (CI/CD) + **Boards** (work) + **Artifacts** + **Test Plans**.
- The **`azuredevops`** provider (by Microsoft) manages the **org-level** resources (project, repo, pipeline, variable group) — it's separate from `azurerm`.
- A **pipeline** (a `build_definition`) = a YAML (or classic) definition that **builds + tests + deploys** — it references a **repo** + a **service connection** (to deploy to Azure).
- **Variable groups** = shared, optionally **secret**, key/value used across pipelines (the "don't hardcode secrets" pattern).

## Run it
```bash
terraform init && terraform plan && terraform apply
# verify: az devops project list
#   az repos list --organization <org>
#   az pipelines list --organization <org> --project <project>
```

## Clean up
```bash
terraform destroy
```

## Common mistakes
| Mistake | Fix |
|---|---|
| "401 Unauthorized" from the provider | the **`personal_access_token`** is missing/expired (or the **org URL** is wrong) — set a valid **PAT** with the right scopes |
| Pipeline "can't find the repo" | the **`repo_id`** / **`project_id`** doesn't match the repo — the pipeline must reference the **right repo** in the **right project** |
| Secret "not available" in the pipeline | the **variable group** isn't **linked** to the pipeline (or the variable isn't marked `is_secret`) — link the group to the stage/job |
