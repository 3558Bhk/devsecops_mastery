# dummy_jenkins.md — Run the Hands-On Projects in Jenkins (exact steps + dummy values)

> Same goal as `dummy_azuredevops.md`, but with Jenkins:
> a **pipeline job** that checks out this repo, runs `terraform init → plan`,
> and lets you click **Approve** before `apply` (or run `destroy`).
> Worked example: `aws/project-09-cloudwatch-alarms-autoscaling` — swap `PROJECT` for any other project.
>
> 🟡 = dummy value you must replace with your real value

---

## Step 0 — What you need (and the dummy values)

| # | Thing | Dummy value (what you type now) | What to push (real value) |
|---|-------|--------------------------------|---------------------------|
| 1 | A running Jenkins | (see Step 1) | your Jenkins URL, e.g. `http://localhost:8080` |
| 2 | Jenkins admin password | `jenkins-admin-123` | set at first login |
| 3 | AWS Access Key ID | `AKIAIOSFODNN7EXAMPLE` | from `~/.aws/credentials` |
| 4 | AWS Secret Access Key | `wJalrXUtnFEMI/K7MDENG/bPxRfiCyEXAMPLEKEY` | from `~/.aws/credentials` |
| 5 | AWS Region | `us-east-1` | your project's region |
| 6 | (Azure projects) Tenant ID | `11111111-1111-1111-1111-111111111111` | `az account show -o table \| grep TenantId` |
| 7 | (Azure) Client ID | `22222222-2222-2222-2222-222222222222` | Entra ID app registration (see Step 1 note) |
| 8 | (Azure) Client Secret | `3333-SECRET-3333` | app registration → Certificates & secrets |
| 9 | (Azure) Subscription ID | `44444444-4444-4444-4444-444444444444` | `az account show -o table \| grep Id` |
| 10 | Git repo URL | `https://github.com/yourname/terraform-hands-on.git` | where you pushed this folder (Step 2) |

---

## Step 1 — Get Jenkins running (pick one)

**Option A — Docker (fastest, recommended for a lab):**

```bash
docker run -d --name jenkins -p 8080:8080 -v jenkins_home:/var/jenkins_home \
  jenkins/jenkins:lts      # start Jenkins on http://localhost:8080
docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword   # your first-login password
```

Open `http://localhost:8080` → paste the initial admin password → **"Install suggested plugins"** (wait a few minutes).

**Option B — War file:** download `jenkins.war` from get.jenkins.io → `java -jar jenkins.war` → same first-login flow.

> **Azure service principal (only for Azure projects):** same as in `dummy_azuredevops.md` Step 1 note — app registration + **Contributor** role on the subscription; copy the four `AZURE_*` values.

---

## Step 2 — Install the plugins you need

Jenkins Dashboard → **Manage Jenkins → Plugins → Available** → search & install (reboot if asked):

| Plugin | Why |
|---|---|
| **Terraform** (by Junade Ali) | provides the `Terraform` tool type + step |
| **Pipeline** (usually already there) | declarative pipeline in a `Jenkinsfile` |
| **Pipeline Stage View / Pipeline Graph** (optional) | prettier build pages |

**Register the Terraform binary** (one time):

1. **Manage Jenkins → Tools** (Global Tool Configuration).
2. Under *Terraform* → `Add Terraform`:
   - Name: `terraform-198`
   - **Automatically install** → Terraform Version: `1.9.8`
3. Save. (The Jenkinsfile below references this name.)

---

## Step 3 — Store your credentials (so they never touch the Jenkinsfile)

1. **Manage Jenkins → Credentials → System → Global JENKINS credentials → Add Credentials**.
2. Add these (dummy values → push real ones):

| Kind | ID | Name | Value (dummy) |
|---|---|---|---|
| Secret text | `aws_access_key_id` | AWS Access Key | `AKIAIOSFODNN7EXAMPLE` |
| Secret text | `aws_secret_access_key` | AWS Secret Key | `wJalrXUtnFEMI/K7MDENG/bPxRfiCyEXAMPLEKEY` |
| Secret text | `aws_region` | AWS Region | `us-east-1` |
| (Azure) Secret text | `azure_tenant_id` | Tenant ID | `11111111-…` |
| (Azure) Secret text | `azure_client_id` | Client ID | `22222222-…` |
| (Azure) Secret text | `azure_client_secret` | Client Secret | `3333-SECRET-3333` |
| (Azure) Secret text | `azure_subscription_id` | Subscription ID | `44444444-…` |

> For a Git repo that needs auth, add one more: **Username with password**, ID `git-credentials`, username + personal access token.

---

## Step 4 — Create the pipeline job

1. **New Item** → name `tf-aws-lab` → type **Pipeline** → OK.
2. Left sidebar → **Pipeline** → Definition: **Pipeline script** → paste the whole Jenkinsfile below.
3. (Optional) **Add to folder** / **SCM** tab: point at your repo with `Jenkinsfile` as the script path — that's the "real team" setup where the file lives in Git. For the lab, the inline script is fine.

```groovy
// Jenkinsfile — Terraform plan/apply/destroy for the hands-on projects
// Worked example: aws/project-09-cloudwatch-alarms-autoscaling

pipeline {

    agent {
        docker {                       // run the whole job inside a Docker container…
            image 'hashicorp/terraform:1.9.8'   // …that already has Terraform 1.9.8 installed
            // NOTE: if you see "java not found" errors, use `agent any` + the Tools
            //        block below instead (the Terraform binary comes from the registered tool).
        }
    }

    // agent any + tool — UNCOMMENT THIS BLOCK and comment the docker block above if needed:
    // agent {
    //     node {
    //         label ''                     // run on any node
    //         tools {                      // use the Terraform tool registered in Step 2
    //             terraform 'terraform-198'
    //         }
    //     }
    // }

    parameters {                        // the knobs you get on the "Build with Parameters" page
        choice(name: 'CLOUD',
               description: 'Which cloud track',
               choices: ['aws', 'azure'])                                  // aws | azure
        string(name: 'PROJECT',
               defaultValue: 'project-09-cloudwatch-alarms-autoscaling',
               description: 'Project folder inside aws/ or azure/')        // any project-XX-...
        choice(name: 'ACTION',
               description: 'plan = preview, apply = build, destroy = tear down',
               choices: ['plan', 'apply', 'destroy'])                       // what to do
        string(name: 'ALARM_EMAIL', defaultValue: '',
               description: 'Optional: email for project-09 alarms (empty = skip)')
    }

    environment {                       // env vars for the whole build (secret = pulled from credentials by ID)
        AWS_ACCESS_KEY_ID     = credentials('aws_access_key_id')            // from Step 3
        AWS_SECRET_ACCESS_KEY = credentials('aws_secret_access_key')
        AWS_REGION            = credentials('aws_region')
        // Azure (uncomment for azure projects):
        // AZURE_TENANT_ID        = credentials('azure_tenant_id')
        // AZURE_CLIENT_ID        = credentials('azure_client_id')
        // AZURE_CLIENT_SECRET    = credentials('azure_client_secret')
        // AZURE_SUBSCRIPTION_ID  = credentials('azure_subscription_id')
        TF_WORKDIR = "${CLOUD}/${PROJECT}"                                  // e.g. aws/project-09-...
    }

    options {
        timestamps()                    // put real timestamps on every log line
        disableConcurrentBuilds()       // never two applies of the same state at once (lock safety)
        buildDiscarder(logRotator(numToKeepStr: '20'))   // keep only the last 20 builds
    }

    stages {

        stage('Checkout') {             // get the code
            steps {
                // lab: code is already on the Jenkins machine where this file's repo lives:
                dir("${env.WORKSPACE}") { sh 'ls' }  // (sanity check only)
                // REAL setup — comment out the line above and use:
                // checkout scm        // checks out the repo from the SCM tab (Jenkinsfile lives in Git)
            }
        }

        stage('Validate') {             // cheap: catches syntax errors before spending provider time
            steps {
                dir("${TF_WORKDIR}") {                          // cd into the chosen project folder
                    sh 'terraform init -backend=false -input=false'   // download providers only (no backend yet)
                    sh 'terraform validate'                        // the .tf files are well-formed
                    sh 'terraform fmt -check -diff || true'        // show formatting drift (non-fatal)
                }
            }
        }

        stage('Init') {                 // connect the real backend (state location)
            steps {
                dir("${TF_WORKDIR}") {
                    sh 'terraform init -input=false'             // + state backend (S3 / local)
                }
            }
        }

        stage('Plan') {                 // the preview — always runs
            steps {
                dir("${TF_WORKDIR}") {
                    sh 'terraform plan -input=false -no-color -out=tfplan'   // save the plan as a file
                    archiveArtifacts 'tfplan'                        // keep it in the build (for audit)
                }
            }
            post {
                always {
                    // surface the plan in the UI (plain text of the .tfplan is binary — show a readable summary)
                    script {
                        if (params.ACTION == 'plan') {
                            dir("${TF_WORKDIR}") { sh 'terraform show tfplan' }
                        }
                    }
                }
            }
        }

        stage('Approve') {              // a human gate before anything destructive happens
            when {
                expression { params.ACTION != 'plan' }   // no gate needed for plan-only builds
            }
            steps {
                input(
                    message: "Apply to ${env.TF_WORKDIR}? Read the Plan stage output first!",
                    ok: 'Yes, proceed',
                    submitter: 'admin'                   // who may click (add more names: 'admin,john')
                )
            }
        }

        stage('Execute') {              // do the thing
            when {
                expression { params.ACTION != 'plan' }
            }
            steps {
                dir("${TF_WORKDIR}") {
                    if (params.ACTION == 'apply') {
                        sh 'terraform apply -input=false -no-color tfplan'   // apply the EXACT plan you reviewed
                    } else {
                        sh 'terraform destroy -auto-approve -input=false -no-color'   // ACTION == destroy
                    }
                }
            }
        }

        stage('Outputs') {              // show what now exists (names/URLs) — only after apply
            when {
                expression { params.ACTION == 'apply' }
            }
            steps {
                dir("${TF_WORKDIR}") {
                    sh 'terraform output'                  // the outputs.tf values (ASG name, alarm ARN, …)
                }
            }
        }
    }

    post {
        failure {
            echo '❌ Build failed — check the stage logs. If state locked, another apply may be running.'
        }
        success {
            echo "✅ ${params.ACTION} finished for ${env.TF_WORKDIR}"
        }
    }
}
```

---

## Step 5 — Run it

1. Job → **Build with Parameters**:
   - `CLOUD` = `aws`
   - `PROJECT` = `project-09-cloudwatch-alarms-autoscaling`
   - `ACTION` = `plan` → **Build**
2. Watch the stages: **Validate → Init → Plan** → the Plan console shows:
   ```
   Plan: 5 to add, 0 to change, 0 to destroy.
   + create aws_launch_template.web
   + create aws_autoscaling_group.web
   + create aws_autoscaling_policy.cpu_target
   + create aws_sns_topic.alerts
   + create aws_cloudwatch_metric_alarm.cpu_high
   ```
3. Happy with the diff? Re-run with `ACTION` = `apply` → the **Approve** stage appears in the build page → click **Yes, proceed** (as `admin`) → resources are created.
4. Verify from your laptop:
   ```bash
   aws autoscaling describe-auto-scaling-groups --region us-east-1
   aws cloudwatch describe-alarms
   ```
5. Tear down: re-run with `ACTION` = `destroy` → Approve → account clean.

**Azure project example** — same job, different parameters: `CLOUD` = `azure`, `PROJECT` = `project-09-observability-app-insights`, plus uncomment the four `AZURE_*` env lines and the Azure credentials from Step 3.

---

## Step 6 — Make it trigger automatically (optional, the "real" setup)

1. Move the `Jenkinsfile` into the repo (e.g. `ci/Jenkinsfile`) and keep the job's **SCM** tab pointing at the repo with script path `ci/Jenkinsfile`.
2. Install the **Gitlab/GitHub plugin** (or use a *Multibranch Pipeline* item):
   - **New Item → Multibranch Pipeline** → add the repo.
   - Jenkins scans branches: every branch gets its own job; pushes to `main` build automatically.
3. Add a **Nightly Drift Check**: Job → **Build Triggers → Build periodically** → `H 2 * * *` (2 a.m. daily) with `ACTION=plan`; configure an email/Slack notifier on "build became unstable" if the plan is non-empty.

---

## Troubleshooting (what you'll actually hit)

| Symptom | Cause | Fix |
|---|---|---|
| `java: command not found` in docker agent | the `hashicorp/terraform` image has no JVM | switch to `agent any` + the `tools { terraform 'terraform-198' }` block |
| `Error: No valid credentials source` | AWS env vars not set | check the credential IDs match exactly (`aws_access_key_id` etc.); they're case-sensitive |
| `Error: could not query registry...` (init fails) | the agent has no internet | the docker image pulls fine, but a bare Jenkins node may not — give the node outbound HTTPS, or pre-cache providers on the node |
| `Error: ... state lock` | another build/apply is running | `disableConcurrentBuilds()` is already on; also stop running applies from your laptop while CI runs |
| Plan shows a resource you already destroyed manually | drift (out-of-band change) | `plan -refresh-only` to see reality; `state rm` if it was intentional (see `case-3-scenario-based.md` S2) |
| The job can't `checkout scm` | no repo in the SCM tab / bad credentials | add the repo URL + `git-credentials` in the SCM tab (Step 3), or use the inline script for the lab |
| `Terraform` tool not found | Tools block references a name you didn't register | name must match Step 2 exactly: `terraform-198` |
