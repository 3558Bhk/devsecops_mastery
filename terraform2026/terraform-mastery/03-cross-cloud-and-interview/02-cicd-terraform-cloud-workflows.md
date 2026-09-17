# Cross-Cloud 2 — CI/CD, Terraform Cloud & Production Workflows

> **⏱️ Time to complete: ~75 min** (read + wire a plan/apply GitHub Actions workflow)

## 2.1 The Golden CI/CD Pattern

```
git push (PR)
   → CI: fmt + validate + tflint/checkov + terraform plan
   → (optional) Infracost cost estimate
   → human review of the plan (PR comment)
   → merge / approve
   → CI: terraform apply (auto for non-prod; gated/approved for prod)
   → (scheduled) drift detection: plan -refresh-only → alert
```

**Principles:**
- **Plan is a PR gate** (machine-generated diff + human review).
- **Apply only after merge** (or explicit approval for prod).
- **One state per environment/service** (locked remote backend).
- **OIDC** auth (no long-lived secrets in the pipeline).
- **Drift detection** on a schedule.

## 2.2 GitHub Actions: AWS (OIDC)

```yaml
name: terraform-aws            # the workflow name
on:                             # the triggers
  pull_request:                 # on PRs
    paths: ["environments/**"]  # only when env files change
  push:                         # on pushes
    branches: [main]            # to main
    paths: ["environments/**"]  # only when env files change

jobs:                           # the jobs
  plan:                         # the plan job
    if: github.event_name == 'pull_request'   # only on PRs
    runs-on: ubuntu-latest      # the runner
    steps:                      # the steps
      - uses: actions/checkout@v4   # check out the code
      - uses: hashicorp/setup-terraform@v3   # install Terraform
        with: { terraform_version: "~> 1.9" }   # the version
      - uses: aws-actions/configure-aws-credentials@v4   # AWS OIDC auth
        with:
          role-to-assume: arn:aws:iam::111111111111:role/github-tf   # the role
          aws-region: ap-south-1   # the region
      - working-directory: environments/prod   # the prod root module
        run: |
          terraform init -backend=false   # init without the backend (for validate)
          terraform fmt -check -recursive # check formatting
          terraform validate              # validate the config
      - uses: devops-infra/tflint-action@v3     # (or checkov/tfsec) lint
      - working-directory: environments/prod   # the prod root module
        run: terraform plan -out=tfplan -lock=true   # save the plan
      - uses: actions/github-script@v7           # (post plan as a PR comment)
        if: always()                       # always run
        with:
          script: |
            const fs = require('fs');
            github.rest.issues.createComment({   # create a PR comment
              owner: context.repo.owner, repo: context.repo.repo,
              issue_number: context.issue.number,
              body: "Terraform plan:\n```\n" + fs.readFileSync('environments/prod/tfplan','utf8') + "\n```"
            })
```

> (In practice, use a plan-annotation action like `julianvirdin/terraform-plan-output` or `tarkovcosta/terraform-plan-annotated-output`; the sketch shows the shape.)

## 2.3 GitHub Actions: Azure (OIDC)

```yaml
jobs:                           # the jobs
  plan:                         # the plan job
    if: github.event_name == 'pull_request'   # only on PRs
    runs-on: ubuntu-latest      # the runner
    steps:                      # the steps
      - uses: actions/checkout@v4   # check out the code
      - uses: hashicorp/setup-terraform@v3   # install Terraform
        with: { terraform_version: "~> 1.9" }   # the version
      - uses: azure/login@v2               # Azure OIDC login
        with:
          client-id: ${{ vars.AZURE_CLIENT_ID }}         # the SP's app id
          tenant-id: ${{ vars.AZURE_TENANT_ID }}         # the tenant
          subscription-id: ${{ vars.AZURE_SUBSCRIPTION_ID }}   # the subscription
      - working-directory: environments/prod   # the prod root module
        run: |
          terraform init -backend=false   # init without the backend
          terraform fmt -check -recursive # check formatting
          terraform validate              # validate the config
          terraform plan -out=tfplan      # save the plan
      # (post plan as PR comment)
```

**The provider picks up OIDC automatically** (the `azure/login` action sets `AZURE_FEDERATED_TOKEN_FILE` + `AZURE_CLIENT_ID`/`AZURE_TENANT_ID`; the azurerm provider reads them).

## 2.4 Apply Job (after merge)

```yaml
  apply:                        # the apply job
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'   # only on push to main
    needs: plan            # (plan passed / approved)
    environment: production   # (GitHub "environment" = human approval gate)
    runs-on: ubuntu-latest    # the runner
    concurrency:              # serialize runs
      group: tf-${{ github.ref }}-prod   # per-state group
      cancel-in-progress: false   # NEVER cancel an in-flight apply (state lock!)
    steps:                    # the steps
      - uses: actions/checkout@v4   # check out the code
      - uses: hashicorp/setup-terraform@v3   # install Terraform
      - uses: aws-actions/configure-aws-credentials@v4   # (or azure/login)
        with: { role-to-assume: arn:aws:iam::111111111111:role/github-tf-apply, aws-region: ap-south-1 }   # the apply role
      - working-directory: environments/prod   # the prod root module
        run: |
          terraform init                # init (with the backend)
          terraform apply -auto-approve -lock-timeout=10m   # apply, wait for the lock
```

Key details:
- **`concurrency`** (no `cancel-in-progress`) = serialize applies per state (avoid double-apply races).
- **Separate plan/apply roles** (least privilege): the plan role can be read-heavy; the apply role can write.
- **GitHub `environment`** = the human-approval gate for prod.

## 2.5 Terraform Cloud / HCP (the hosted option)

- **Remote execution** (you don't run `plan`/`apply` on your machine).
- **VCS integration**: a PR → an automatic plan; merge → apply.
- **Workspaces** (one per service+environment) with **settings** (auto-approve for dev, manual for prod).
- **Policy-as-code** (Sentinel) + **cost estimation** + **audit logs** + **SSO/teams**.
- **Private module registry** (share modules across the org).
- Backend:
```hcl
terraform {                          # the terraform config block
  cloud {                            # connect to Terraform Cloud (HCP)
    organization = "myorg"           # your HCP organization
    workspaces {                     # which workspace to bind to
      name = "prod-network"           # by name (or tags = { env: "prod" })
    }
  }
}
```

**When to use TFC vs self-hosted CI:**
- **TFC**: small/medium teams, want VCS+plan+policy+cost out of the box, multi-team governance.
- **Self-hosted (GitHub Actions + S3/blob backend)**: full control, no per-workspace cost, custom gates.

## 2.6 Drift Detection (scheduled)

```yaml
  drift:                      # the drift job
    if: github.event_name == 'schedule'   # (cron)
    runs-on: ubuntu-latest    # the runner
    steps:                    # the steps
      - uses: actions/checkout@v4   # check out the code
      - uses: hashicorp/setup-terraform@v3   # install Terraform
      - uses: aws-actions/configure-aws-credentials@v4   # AWS OIDC auth
        with: { role-to-assume: arn:aws:iam::111111111111:role/github-tf-read, aws-region: ap-south-1 }   # a read-only role
      - working-directory: environments/prod   # the prod root module
        run: |
          terraform init                # init
          terraform plan -refresh-only -detailed-exitcode   # detect drift
          # exit 2 → open a PR / alert "drift detected"
```

- **`-refresh-only`** = detect out-of-band changes without proposing fixes.
- Alert (Slack/Teams) when exit != 0 → a human decides (fix the code or `state rm`).

## 2.7 Multi-Environment Promotion

```
dev (auto-apply on merge to `dev` branch)
   → staging (auto-apply on merge to `main`, or tag)
   → prod (manual approval / change window)
```

- Each environment = **its own root module + state** (not workspaces).
- **Variables** per env (`terraform.tfvars`); **modules** shared.
- **Version the modules** (semver) so prod pins a known-good module version.

## 2.8 Policy & Security Gates

| Gate | Tool | What it checks |
|---|---|---|
| Lint | `terraform fmt -check`, `tflint` | Formatting, style, common mistakes |
| IaC security | **Checkov** / **tfsec** / **Prisma** | Public S3, unencrypted disk, open SG, no MFA, etc. |
| Plan policy | **OPA/Conftest** (on plan JSON) / **Sentinel** (TFC) | Custom org rules (e.g. "no t3.nano in prod", "must have a tag") |
| Cost | **Infracost** / TFC estimate | Budget guardrail per PR |

```bash
# A CI snippet
terraform fmt -check -recursive   # check formatting
terraform validate              # validate the config
tflint -f compact                 # lint (compact output)
checkov -d environments/prod --compact   # IaC security scan
infracost break-down --path environments/prod --show-skipped   # cost per resource
```

## 2.9 Rollback Strategy

Terraform has **no "undo"** (it's not a package manager). Rollback = **re-apply a previous config**:

1. **Keep config in Git** → the "rollback" is `git revert`/`checkout` the previous commit → `terraform apply` (Terraform converges to the old desired state).
2. **State versioning** (S3 versioning / TFC) = a safety net to restore state if a run corrupts it.
3. **`prevent_destroy` / `create_before_destroy`** = reduce the blast radius of a bad change.
4. **Blue/green or canary** (app level) for high-risk changes.

> **Rule:** never `terraform apply` from a "scratch" config — always from a **Git commit** (so the rollback path is a commit, not a memory).

## 2.10 The Production Checklist

- [ ] Remote **locked** state, one per env/service.
- [ ] **OIDC** auth (CI) + **SSO/SP** (dev) — no long-lived keys.
- [ ] **PR-gated plans** + **apply on merge** (prod = approval).
- [ ] **`concurrency`** (serialize applies per state).
- [ ] **Separate plan/apply roles** (least privilege).
- [ ] **fmt/validate/tflint/checkov** in CI.
- [ ] **Infracost** cost guardrail.
- [ ] **Drift detection** on a schedule → alert.
- [ ] **`prevent_destroy`** on data-bearing resources (prod).
- [ ] **`terraform test`** (unit) + **policy** (plan JSON).
- [ ] **State backup** (versioning) + a **rollback runbook** (git-based).

## 2.11 Interview Quick Facts

- **Plan = PR gate**; **apply on merge** (prod = approval).
- **OIDC** = the CI auth (AWS STS web identity / Azure federated credential).
- **`concurrency`** (no cancel) = serialize applies per state.
- **Separate plan/apply roles** = least privilege.
- **TFC** = hosted (VCS + plan + policy + cost + registry); self-hosted = full control.
- **Drift** = scheduled `plan -refresh-only` → alert.
- **Rollback** = re-apply a previous Git commit (no "undo" button).
- **One state per env/service** (not workspaces).
