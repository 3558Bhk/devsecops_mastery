# dummy_azuredevops.md — Run the Hands-On Projects in Azure DevOps Pipelines (exact steps + dummy values)

> Goal: a pipeline that checks out this repo, runs `terraform init → plan` on every push,
> and `apply` (with your approval) on merge — using **project-09 (AWS, alarms + auto-scaling)** as the worked example.
> Everything below works for any project: just change the `working-directory` line.
>
> 🟡 = dummy value you must replace with your real value (marked in tables below)

---

## Step 0 — What you need (and the dummy values for each)

| # | Thing | Dummy value (what you type now) | What to push (real value) |
|---|-------|--------------------------------|---------------------------|
| 1 | Azure DevOps account | free: sign in at `https://dev.azure.com` | your email |
| 2 | A **Project** in DevOps | `terraform-lab` | any name |
| 3 | AWS Access Key ID | `AKIAIOSFODNN7EXAMPLE` | from your `~/.aws/credentials` (`aws_access_key_id`) |
| 4 | AWS Secret Access Key | `wJalrXUtnFEMI/K7MDENG/bPxRfiCyEXAMPLEKEY` | from `~/.aws/credentials` (`aws_secret_access_key`) |
| 5 | AWS Region | `us-east-1` | whatever your project uses |
| 6 | (Azure projects only) Tenant ID | `11111111-1111-1111-1111-111111111111` | `az account show -o table \| grep TenantId` |
| 7 | (Azure) Client (App) ID | `22222222-2222-2222-2222-222222222222` | create app in Entra ID (Step 1 note below) |
| 8 | (Azure) Client Secret | `3333-SECRET-3333` | from the app registration → Certificates & secrets |
| 9 | (Azure) Subscription ID | `44444444-4444-4444-4444-444444444444` | `az account show -o table \| grep Id` |

> **For the AWS example below, only #3–#5 matter.** For Azure projects (p09–p11 azure etc.), you also need #6–#9.

---

## Step 1 — Get the code into an Azure DevOps repo

**Option A (Git CLI — recommended):**

```bash
cd ~/terraform-hands-on            # 1. the folder you want to CI (this repo)
git init                            # 2. start a git repo (skip if you already have one)
git add -A                          # 3. stage everything
git commit -m "hands-on projects"   # 4. commit
# in Azure DevOps: Project → Repos → New repository → copy its clone URL, then:
git remote add origin https://dev.azure.com/<org>/<project>/_git/terraform-lab   # 5. the repo URL
git push -u origin master           # 6. push (use your DevOps account + a personal access token as password)
```

**Option B (web upload):** DevOps → Repos → `+` → *Upload files* → drag the project folder. (Fine for a single project.)

> **Azure service principal (only for Azure projects):** Entra ID → App registrations → `+ New registration` → name `tf-pipeline` → *Allow only this app's access* → add API permission **Azure Service Management → Application (client) credentials** → assign role **Contributor** on your subscription (IAM → role assignments). Then copy Tenant/Client/Subscription IDs into the table above.

---

## Step 2 — Create the secret variables in Azure DevOps

1. DevOps project → **Pipelines** (left menu) → **Library** (bottom).
2. `+ Variable group` → name: `tf-aws-secrets` → *Scope to pipelines*: all.
3. Add these variables — tick **🔒 (secret)** on the keys:

| Name | Value (dummy) | Secret? |
|---|---|---|
| `AWS_ACCESS_KEY_ID` | `AKIAIOSFODNN7EXAMPLE` | ✅ |
| `AWS_SECRET_ACCESS_KEY` | `wJalrXUtnFEMI/K7MDENG/bPxRfiCyEXAMPLEKEY` | ✅ |
| `AWS_REGION` | `us-east-1` | ❌ |
| `PROJECT_DIR` | `aws/project-09-cloudwatch-alarms-autoscaling` | ❌ |

> For Azure projects instead add: `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET` (secret), `AZURE_SUBSCRIPTION_ID` — same pattern, values from the table in Step 0.
> The azurerm provider reads `AZURE_*` env vars directly — **no `az login` step needed.**

---

## Step 3 — Create the pipeline (with the complete YAML)

1. **Pipelines → New pipeline** → *YAML in the repository* (the repo you pushed in Step 1).
2. Delete the generated contents and paste this (every line commented):

```yaml
# azure-pipelines.yml — Terraform plan on every push, apply on merge (worked example: aws/project-09)

trigger:                                 # WHEN to run: on every push…
  branches:                              # …to these branches
    include:
      - master                           # main branch (use "main" if that's yours)

pool:                                    # WHERE to run
  vmImage: ubuntu-latest                 # Microsoft-hosted Ubuntu agent (free for small repos)

variables:                               # variables visible in this file
  tfVersion: "1.9.8"                     # the Terraform version to install (pin it)

stages:                                  # stages run in order (a failed stage stops the rest)
  - stage: Plan                          # STAGE 1: validate + plan (safe — no cloud changes)
    jobs:
      - job: TerraformPlan
        steps:
          - task: TerraformInstaller@4   # install Terraform on the agent
            displayName: "Install Terraform"
            inputs:
              terraformVersion: "$(tfVersion)"   # which version (from the variable above)

          - task: TerraformCLI@1         # run a terraform subcommand
            displayName: "terraform validate"
            inputs:
              workingDirectory: "$(PROJECT_DIR)"  # which project folder (secret group value)
              Provider: "Terraform"               # run the terraform binary
              Command: "validate"                 # check the .tf files are well-formed
              ProviderFlags: "-no-color"          # plain output in the log

          - task: TerraformCLI@1         # same task, different command
            displayName: "terraform init"
            inputs:
              workingDirectory: "$(PROJECT_DIR)"
              Provider: "Terraform"
              Command: "init"                        # download providers + connect backend
              ProviderFlags: "-input=false -no-color"   # never prompt; plain output

          - task: TerraformCLI@1
            displayName: "terraform plan"
            inputs:
              workingDirectory: "$(PROJECT_DIR)"
              Provider: "Terraform"
              Command: "plan"
              ProviderFlags: "-input=false -no-color -out=tfplan"   # save the plan as a file

          - publish: "$(PROJECT_DIR)/tfplan"   # keep the plan file as a build artifact…
            artifact: tfplan                   # …so the apply stage can reuse the EXACT same plan

  - stage: Apply                         # STAGE 2: actually change the cloud
    dependsOn: Plan                      # runs only if the Plan stage succeeded
    # (to require a human click before this runs, add `environment: prod` here — see "Gate it")
    jobs:
      - job: TerraformApply
        steps:
          - task: DownloadBuildArtifacts@1   # fetch the tfplan file the Plan stage made
            displayName: "Download plan artifact"
            inputs:
              buildType: "current"            # from THIS build (not an older one)
              artifactName: "tfplan"

          - task: TerraformInstaller@4
            displayName: "Install Terraform"
            inputs:
              terraformVersion: "$(tfVersion)"

          - task: TerraformCLI@1             # apply the SAVED plan (what reviewers saw == what runs)
            displayName: "terraform apply"
            inputs:
              workingDirectory: "$(PROJECT_DIR)"
              Provider: "Terraform"
              Command: "apply"
              ProviderFlags: "-input=false -no-color $(Pipeline.Workspace)/tfplan/tfplan"   # path to the downloaded plan file

          - task: TerraformCLI@1             # print the outputs (URLs, names) into the log
            displayName: "terraform output"
            inputs:
              workingDirectory: "$(PROJECT_DIR)"
              Provider: "Terraform"
              Command: "output"
              ProviderFlags: "-json"
```

> **Why no `az login` / `aws configure` step?** The `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` / `AWS_REGION` (or `AZURE_TENANT_ID` / `AZURE_CLIENT_ID` / `AZURE_CLIENT_SECRET` / `AZURE_SUBSCRIPTION_ID`) values from your variable group are exported as environment variables by the agent, and both providers read credentials straight from the environment.

**Where the dummy values from Step 2 plug in:** `PROJECT_DIR` (folder to run) and the AWS/Azure credentials — all from the variable group; none of it is in this file.

---

## Step 4 — Run it and read the result

1. Push any change to `master` (e.g. `git commit --allow-empty -m "ci test"` → `git push`) → the pipeline starts automatically.
2. Open the run:
   - **Plan stage** → `terraform plan` step → the console shows the diff (`+ create...`).
   - For **aws/project-09** you'll see: launch template, ASG, autoscaling policy, SNS topic, (email subscription if you set `alarm_email` in `terraform.tfvars`), metric alarm.
3. If the plan is right → the Apply stage runs → the resources exist. Verify:
   ```bash
   aws autoscaling describe-auto-scaling-groups --region us-east-1   # the ASG is there
   aws cloudwatch describe-alarms                                     # the alarm is there
   ```
4. Cleanup run: temporarily change `Command: "apply"` → `"destroy"` in the Apply stage (or make a `destroy.yml` — pattern below), run it, put it back.

---

## Gate it (the way real teams do it)

- **Approvals before Apply**:
  1. Pipelines → **Environments** → `+ New environment` → name `prod` → *Approvals required*: your account → 1.
  2. In the YAML, add to the Apply stage:
     ```yaml
     - stage: Apply
       displayName: "Apply to PROD (needs approval)"
       dependsOn: Plan
       environment: prod        # ← this line makes a human click "Approve"
       jobs:
         ...
     ```
  3. Now every merge waits at "Waiting for approval" until you (or another approver) click **Approve** in the pipeline.

- **Dev vs prod**: two variable groups (`tf-dev-secrets` with dev creds + `PROJECT_DIR=aws/project-09-...`) and a second pipeline (or a `CLOUD` parameter) that uses the prod group + the approval gate. Same YAML, different secrets.

---

## A destroy pipeline (keep your account clean)

Duplicate the file as `azure-pipelines-destroy.yml` with one change in the apply step:

```yaml
Command: "destroy"
ProviderFlags: "-auto-approve -input=false -no-color"
```

Run it manually: Pipelines → the pipeline → **Run pipeline** (don't let it trigger on every push!).

---

## Troubleshooting (what you'll actually hit)

| Symptom | Cause | Fix |
|---|---|---|
| `Error: No valid credentials source` | AWS env vars not visible | add `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`/`AWS_REGION` to the variable group (keys marked secret) and check they're attached to the pipeline scope |
| `Error: ... lock timeout / state locked` | another apply running (or a stale lock from your laptop) | wait / delete the lock row in the DynamoDB table (see `project-06`) |
| `BucketAlreadyExists` / `already exists` | a hardcoded `...2026` name is taken | change the name in that project's `main.tf` (see `dummy.md` 🟡 rows) |
| `Missing required argument: ...admin_password` | a variable with no default (azure p03) | add a `terraform.tfvars` to that project with the value, commit it (lab-only!), or pass `-var` in ProviderFlags |
| `plan` is clean but you expected changes | out-of-band change / stale state | `plan -refresh-only` locally first; see `case-3-scenario-based.md` S2 |
| Terraform task not found | missing extension | Agents & tasks → Manage Extensions → install **Terraform** (by Microsoft) |
