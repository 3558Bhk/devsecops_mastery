# 🔷 CASE 1 · CONTINUOUS DELIVERY WITH AZURE DEVOPS
### Environments + **Approvals and checks**, multi-stage YAML with a gated production stage, plus the classic release pipeline for teams that still use it.

> **Scenario:** CI ran elsewhere ([Scenario 1 · Azure DevOps](../../scenario-1-ci-only/02-azure-devops-ci.md)) and published `shopacr.azurecr.io/<svc>@sha256:…` with the digest in a pipeline **artifact**. **This pipeline never builds.**
>
> **Tool version anchors:** Azure DevOps multi-stage YAML · `KubernetesManifest@1` · `AzureCLI@2` · `KubectlInstaller@1` · **Workload Identity Federation** · Environments **Approvals and checks** · classic **Release pipelines** (deployment gates).

---

## 📇 Contents

| § | What |
|---|---|
| [1](#1---the-two-mechanisms) | ⭐ The two mechanisms: Environments (YAML) vs classic release approvals |
| [2](#2--setting-up-the-environment-and-the-approval) | Setting up the environment and the approval — UI, CLI, IaC |
| [3](#3---the-six-other-checks-worth-adding) | ⭐ The six other checks worth adding while you are there |
| [4](#4---the-cd-pipeline--shop-api-full-yaml) | ⭐ The CD pipeline — `shop-api`, full YAML |
| [5](#5--reading-the-digest-from-a-ci-artifact) | Reading the digest from a CI artifact — and refusing anything else |
| [6](#6--what-the-approver-sees) | What the approver sees — pre-deployment notifications and the run summary |
| [7](#7---credentials) | ⭐ Credentials — service connections, Workload Identity Federation, and AKS auth |
| [8](#8---rollback-as-a-first-class-release) | ⭐ Rollback as a first-class release |
| [9](#9--classic-release-pipelines) | Classic release pipelines — stages, approvals, and deployment gates |
| [10](#10--per-app-shape) | Per app shape: FE-only, BE-only, FE+BE, polyglot |
| [11](#11--️-run-it-and-prove-it--the-case-1-acceptance-checks) | ▶️ Run it and prove it — the Case 1 acceptance checks |
| [12](#12--troubleshooting) | Troubleshooting |
| [13](#13---tasks--answers-at-the-end) | Tasks and answers — **answers at the END** |

---

## 1 · ⭐ The two mechanisms

Azure DevOps has **two** approval systems, and teams mix them up constantly.

| | **Environments** (modern) | **Classic release pipelines** (legacy) |
|---|---|---|
| Where | ⭐ YAML pipelines, `environment:` on a **job** | the visual designer, per **stage** |
| Gate name | **Approvals and checks** | **Pre-deployment approvals** |
| Approver | user or **group** | user or **group** |
| Extra gates | ⭐ Query Work Items, Azure Monitor, REST check, branch control, business hours, exclusive lock | ⭐ Deployment gates (same ideas, older UI) |
| Artifact | a pipeline artifact | a build artifact |
| Status | ✅ current, still developed | ⚠️ supported, **no new features** |
| ⭐ Use | new pipelines | only if you already have them |

```yaml
# MODERN — the gate is a property of the ENVIRONMENT, referenced by a job
jobs:
  - deployment: DeployProduction
    environment: shop-production        # ⭐⭐ THIS IS THE GATE
    strategy:
      runOnce:
        deploy:
          steps: [ ... ]
```

⭐⭐ **The key architectural difference from GitHub Actions:** in Azure DevOps the gate belongs to the **environment resource**, and the job that references it must be a **`deployment:` job** (not a plain `job:`). A `job:` with `environment:` gets secret scoping but **no approval gate**. That is the single most common "why didn't it stop?" in Azure DevOps CD.

---

## 2 · Setting up the environment and the approval

### 2.1 UI

**Pipelines → Environments → New environment → `shop-production`**
→ **⋯ → Approvals and checks → Approvals → `+`**

| Setting | ⭐ Recommended | Why |
|---|---|---|
| **Approvers** | an Azure DevOps **group** with ≥ 3 members | a single user is a bottleneck and a bypass |
| Instructions for approvers | *"Confirm: digest matches staging · migration validated · no freeze in effect"* | ⭐ the prompt is the control |
| Requestor should be allowed to approve | ⛔ **OFF** | otherwise the person who started the release can approve it, and the gate is self-service |
| Timeout | 30 days | after which the run fails rather than hanging forever |

### 2.2 ⭐ CLI — scriptable, survives a project rebuild

```bash
ORG=https://dev.azure.com/yourorg ; PROJ=shop

# environment
az pipelines environment create --organization $ORG --project $PROJ \
  --name shop-production --description "Production · human approval required"

# the approval check (REST — the CLI does not expose checks directly)
ENV_ID=$(az pipelines environment show --organization $ORG --project $PROJ \
         --name shop-production --query id -o tsv)
GROUP_ID=$(az devops team list --organization $ORG --project $PROJ \
           --query "[?name=='Platform Engineers'].identity.id" -o tsv)

az rest --method POST --url \
 "$ORG/$PROJ/_apis/distributedtask/environments/$ENV_ID/providers/checks?api-version=7.1" \
 --headers "Content-Type=application/json" --in-file - <<EOF
{
  "type": {"name": "Approval"},
  "timeout": 43200,
  "settings": {
    "executionOrder": 1,
    "instructions": "Confirm digest matches staging, migration validated, no freeze in effect.",
    "approvers": [{"id": "$GROUP_ID", "type": "group"}],
    "requestorCannotBeApprover": true
  }
}
EOF

# ⭐ an exclusive lock — only one deployment to production at a time
az rest --method POST --url \
 "$ORG/$PROJ/_apis/distributedtask/environments/$ENV_ID/providers/checks?api-version=7.1" \
 --headers "Content-Type=application/json" --in-file - <<EOF
{ "type": {"name": "ExclusiveLock"},
  "timeout": 120,
  "settings": {"executionOrder": 2} }
EOF

# verify
az rest --method GET --url \
 "$ORG/$PROJ/_apis/distributedtask/environments/$ENV_ID/providers/checks?api-version=7.1" \
 --query 'value[].type.name' -o table
```

### 2.3 Terraform

```hcl
resource "azuredevops_environment" "production" {
  project_id = azuredevops_project.shop.id
  name       = "shop-production"
  description = "Production · human approval required"
}

resource "azuredevops_environment_resource_authorization" "prod_sc" {
  project_id  = azuredevops_project.shop.id
  resource_id = azuredevops_serviceendpoint_azurecr.prod.id
  type        = "serviceendpoint"
  environment = azuredevops_environment.production.name
  # ⭐ the ACR service connection is authorised ONLY for this environment
}
```

---

## 3 · ⭐ The six other checks worth adding

Azure DevOps' approval system is more expressive than GitHub's. Use it:

| Check | What it does | ⭐ Why you want it |
|---|---|---|
| **Approval** | waits for a group | the Case 1 gate |
| ⭐ **Exclusive Lock** | one deployment per environment at a time | the human-was-the-lock problem, solved properly |
| **Branch Control** | only `refs/heads/main` may deploy | stops a feature branch reaching production |
| **Query Work Items** | requires a linked, correctly-stated work item | ⭐ ties the release to an approved change record — often a compliance requirement |
| **Azure Monitor** | queries Application Insights / Log Analytics and fails if the result breaches a threshold | ⭐ "is production healthy *right now*?" before adding load |
| **REST** | calls any HTTP endpoint and evaluates a JSON path | your own policy engine — freeze calendars, change windows, on-call checks |
| **Business Hours** | only deploy 09:00–17:00 local | ⭐ cheap, effective. A deploy at 3 a.m. with nobody watching is how small problems become incidents |

```
⭐ THE MINIMUM WORTH HAVING FOR CASE 1:
   Approval (group, requestorCannotBeApprover=true)
   + Exclusive Lock
   + Branch Control (main only)

⭐ WHAT TURNS CASE 1 INTO "PATTERN 3" (canary + auto-halt, ../00 §7):
   + Azure Monitor (post-deploy)
   + REST (freeze calendar)
```

---

## 4 · ⭐ The CD pipeline — `shop-api`, full YAML

`pipelines/cd-shop-api.yml`

```yaml
# ═══════════════════════════════════════════════════════════════════════
#  WHAT : CD ONLY for shop-api. Consumes a CI-published DIGEST artifact,
#         deploys dev → staging → ⛔ environment approval → production.
#  WHY  : Case 1 Continuous Delivery — Scenario 2.
#         ⭐ NO build, NO compile, NO image push. Enforced by having no
#            ACR push permission on this pipeline's service connection.
#  TARGET: AKS cluster shop-aks · namespaces shop-{dev,staging,production}.
# ═══════════════════════════════════════════════════════════════════════
trigger: none            # ⭐⭐ NEVER auto-trigger. Case 1 = a human decides.
pr: none

parameters:
  - name: runId
    displayName: 'CI run to deploy from (blank = latest successful on main)'
    type: string
    default: ''
  - name: target
    displayName: 'Promote to'
    type: string
    default: staging
    values: [dev, staging, production]
  - name: reason
    displayName: '⭐ Why are we shipping this? (shown to the approver)'
    type: string

pool:
  vmImage: ubuntu-latest

variables:
  service: shop-api
  acr:     shopacr.azurecr.io
  aksName: shop-aks
  aksRg:   rg-shop
  # ⭐ pinned tool versions — a drifting kubectl is a drifting pipeline
  kubectlVersion: '1.34.0'
  helmVersion:    'v3.17.3'

stages:
  # ═══════════════════════════════════════════════════════════════════
  #  STAGE 0 · RESOLVE THE ARTIFACT
  # ═══════════════════════════════════════════════════════════════════
  - stage: Resolve
    displayName: '0 · Resolve digest'
    jobs:
      - job: resolve
        displayName: 'Validate and resolve'
        steps:
          - task: AzureCLI@2
            displayName: 'Fetch the digest artifact from CI'
            inputs:
              azureSubscription: 'sc-shop-readonly'
              scriptType: bash
              scriptLocation: inlineScript
              inlineScript: |
                set -euo pipefail
                RID='${{ parameters.runId }}'
                if [ -z "$RID" ]; then
                  # ⭐ the LATEST successful CI build of the same pipeline definition
                  RID=$(az pipelines runs list \
                        --pipeline-ids $(System.DefinitionId) \
                        --branches main --status completed --result succeeded \
                        --top 1 --query '[0].id' -o tsv)
                fi
                echo "CI run: $RID"
                # ⭐ download the artifact CI published (the digest, not the image)
                az pipelines runs artifact download \
                  --pipeline-id $(System.DefinitionId) --run-id "$RID" \
                  --artifact-name image-digest --path '$(Agent.TempDirectory)'
                cat '$(Agent.TempDirectory)/image-digest/digest.txt'

          - bash: |
              set -euo pipefail
              RAW=$(cat '$(Agent.TempDirectory)/image-digest/digest.txt')
              # ── ⭐ REFUSE ANYTHING THAT IS NOT A DIGEST ───────────────
              if ! [[ "$RAW" =~ ^[a-z0-9._/-]+@sha256:[0-9a-f]{64}$ ]]; then
                echo "##vso[task.logissue type=error]$RAW is not a digest. CD refuses tags."
                exit 1
              fi
              IMAGE="${RAW%@*}"; DIGEST="${RAW#*@}"
              echo "✅ $IMAGE@$DIGEST"
              echo "##vso[task.setvariable variable=imageRef;isOutput=true]$RAW"
              echo "##vso[task.setvariable variable=digest;isOutput=true]$DIGEST"
              echo "##vso[build.addbuildtag]$DIGEST"   # ⭐ searchable in the UI
            name: parsed
            displayName: '⭐ Validate the digest shape'

          # ── ⭐ PROVENANCE: this digest came from OUR CI ───────────────
          - task: AzureCLI@2
            displayName: 'Verify the image signature'
            inputs:
              azureSubscription: 'sc-shop-readonly'
              scriptType: bash
              scriptLocation: inlineScript
              inlineScript: |
                set -euo pipefail
                az acr login --name $(acr)
                cosign verify \
                  --certificate-oidc-issuer=https://github.com/3558Bhk/shop \
                  --certificate-identity-regexp='.*/\.github/workflows/ci-shop-api\.yml@.*' \
                  "$(parsed.digest)" >/dev/null \
                  || { echo "##vso[task.logissue type=error]signature verification failed"; exit 1; }

  # ═══════════════════════════════════════════════════════════════════
  #  STAGE 1 · DEV — automatic
  # ═══════════════════════════════════════════════════════════════════
  - stage: Dev
    displayName: '1 · Deploy → dev'
    dependsOn: Resolve
    condition: |
      and(succeeded(),
          in('${{ parameters.target }}', 'dev', 'staging', 'production'))
    jobs:
      - deployment: deployDev
        displayName: 'Deploy to dev'
        environment: shop-dev               # ⭐ no checks → automatic
        pool: { vmImage: ubuntu-latest }
        strategy:
          runOnce:
            deploy:
              steps:
                - checkout: self
                - template: templates/k8s-deploy.yml
                  parameters:
                    namespace: shop-dev
                    imageRef: $[ stageDependencies.Resolve.resolve.outputs['parsed.imageRef'] ]
                    timeout: 180s

  # ═══════════════════════════════════════════════════════════════════
  #  STAGE 2 · STAGING — automatic, and it PRODUCES THE EVIDENCE
  # ═══════════════════════════════════════════════════════════════════
  - stage: Staging
    displayName: '2 · Deploy → staging'
    dependsOn: Dev
    condition: |
      and(succeeded(), in('${{ parameters.target }}', 'staging', 'production'))
    jobs:
      - deployment: deployStaging
        displayName: 'Deploy to staging'
        environment: shop-staging           # ⭐ no approvals here
        pool: { vmImage: ubuntu-latest }
        strategy:
          runOnce:
            deploy:
              steps:
                - checkout: self
                - template: templates/k8s-deploy.yml
                  parameters:
                    namespace: shop-staging
                    imageRef: $[ stageDependencies.Resolve.resolve.outputs['parsed.imageRef'] ]
                    timeout: 300s
                # ── ⭐⭐ THE APPROVER'S EVIDENCE ────────────────────────
                - bash: |
                    set -euo pipefail
                    NS=shop-staging
                    READY=$(kubectl -n $NS get deploy $(service) \
                      -o jsonpath='{.status.readyReplicas}/{.spec.replicas}')
                    MIG=$(kubectl -n $NS get job $(service)-migrate \
                      -o jsonpath='{.status.succeeded}')
                    SMOKE=$(curl -fsS -o /dev/null -w '%{http_code}' \
                      https://staging.shop.internal/api/v2/orders || echo FAIL)
                    {
                      echo '##[section]⭐ Staging verification'
                      echo "| check | result |"
                      echo "|---|---|"
                      echo "| ready replicas | $READY |"
                      echo "| smoke /api/v2/orders | $SMOKE |"
                      echo "| migration job succeeded | $MIG |"
                      echo "| digest deployed | $DIGEST |"
                      echo "| reason | ${{ parameters.reason }} |"
                    } | tee '$(Build.SourcesDirectory)/staging-report.md'
                    echo "##vso[task.setvariable variable=stagedDigest;isOutput=true]$DIGEST"
                    # ⭐ surfaces in the run summary — the approver reads this
                  name: verify
                  displayName: '⭐ Verify staging and write the report'
                - publish: '$(Build.SourcesDirectory)/staging-report.md'
                  artifact: staging-report
                  displayName: 'Publish the report for the approver'

  # ═══════════════════════════════════════════════════════════════════
  #  STAGE 3 · ⛔ PRODUCTION — the gate is the ENVIRONMENT
  # ═══════════════════════════════════════════════════════════════════
  - stage: Production
    displayName: '3 · ⛔ Deploy → production'
    dependsOn: Staging
    condition: and(succeeded(), eq('${{ parameters.target }}', 'production'))
    jobs:
      - deployment: deployProd
        displayName: 'Deploy to production'
        environment: shop-production     # ⭐⭐ APPROVAL + EXCLUSIVE LOCK +
                                         #    BRANCH CONTROL live HERE (§2)
        pool: { vmImage: ubuntu-latest }
        strategy:
          runOnce:
            preDeploy:
              steps:
                # ── ⭐ runs AFTER approval, BEFORE the deploy ──────────
                - bash: |
                    set -euo pipefail
                    STAGED='${{ stageDependencies.Staging.deployStaging.outputs.verify.stagedDigest }}'
                    WANT='${{ stageDependencies.Resolve.resolve.outputs.parsed.digest }}'
                    # ⭐⭐ the gate can sit for hours; assert nothing drifted
                    [ "$STAGED" = "$WANT" ] || {
                      echo "##vso[task.logissue type=error]staging ran $STAGED, production asked for $WANT"
                      exit 1; }
                    echo "✅ staging and production agree on $WANT"
                  displayName: '⭐ Assert staging ran this exact digest'
            deploy:
              steps:
                - checkout: self
                - template: templates/k8s-deploy.yml
                  parameters:
                    namespace: shop-production
                    imageRef: $[ stageDependencies.Resolve.resolve.outputs['parsed.imageRef'] ]
                    timeout: 600s
                    runMigration: true
                - bash: |
                    for i in $(seq 1 30); do
                      CODE=$(curl -fsS -o /dev/null -w '%{http_code}' \
                        https://api.shop/actuator/health/readiness || echo 000)
                      [ "$CODE" = "200" ] && { echo "✅ production healthy"; exit 0; }
                      sleep 5
                    done
                    echo "##vso[task.logissue type=error]production unhealthy — rolling back"
                    kubectl -n shop-production rollout undo deploy/$(service)
                    exit 1
                  displayName: 'Verify production (auto-rollback on failure)'
            routeTraffic: {}             # no progressive delivery in Case 1
            postRouteTraffic:
              steps:
                - bash: |
                    kubectl -n shop-production get deploy $(service) \
                      -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
                  displayName: '⭐ Record what is now running'
            on:
              failure:
                steps:
                  - bash: |
                      echo "##vso[task.logissue type=error]deployment failed — auto undo"
                      kubectl -n shop-production rollout undo deploy/$(service)
                      curl -fsS -X POST "$(SLACK_WEBHOOK)" -H 'content-type: application/json' \
                        -d '{"text":"🚨 shop-api production deploy FAILED — rolled back"}'
                    displayName: '🚨 Roll back and shout'
```

### 4.1 The reusable deployment template

`pipelines/templates/k8s-deploy.yml`

```yaml
parameters:
  - name: namespace
    type: string
  - name: imageRef
    type: string
  - name: timeout
    type: string
    default: 300s
  - name: runMigration
    type: boolean
    default: false

steps:
  - task: KubectlInstaller@1
    inputs: { kubectlVersion: $(kubectlVersion) }        # ⭐ pinned

  - task: AzureCLI@2
    displayName: 'Authenticate to AKS (Workload Identity Federation)'
    inputs:
      azureSubscription: 'sc-shop-$(namespace)'          # ⭐ per-env connection
      scriptType: bash
      scriptLocation: inlineScript
      inlineScript: |
        az aks get-credentials -n $(aksName) -g $(aksRg) --overwrite-existing
        kubectl config current-context

  # ── ⭐⭐ MIGRATION FIRST, AS A GATED JOB ─────────────────────────────
  - ${{ if eq(parameters.runMigration, true) }}:
    - bash: |
        set -euo pipefail
        NS='${{ parameters.namespace }}'
        kubectl -n $NS delete job $(service)-migrate --ignore-not-found
        kubectl -n $NS apply -f k8s/$(service)/migration-job.yaml
        kubectl -n $NS wait --for=condition=complete job/$(service)-migrate \
          --timeout=600s \
          || { echo "##vso[task.logissue type=error]migration FAILED — not rolling out"; exit 1; }
      displayName: 'Run the migration Job and wait for it'

  # ── THE ACTUAL DEPLOY: a digest, never a tag ────────────────────────
  - task: KubernetesManifest@1
    displayName: 'Deploy ${{ parameters.namespace }}'
    inputs:
      action: deploy
      namespace: ${{ parameters.namespace }}
      manifests: 'k8s/$(service)/deployment.yaml,k8s/$(service)/service.yaml'
      containers: '$(service)=${{ parameters.imageRef }}'   # ⭐ @sha256:...
      imagePullSecrets: 'acr-pull'

  - task: KubernetesManifest@1
    displayName: 'Wait for the rollout'
    inputs:
      action: checkRolloutStatus
      namespace: ${{ parameters.namespace }}
      rolloutStatusTimeoutInSeconds: 600
```

⭐ **Why `KubernetesManifest@1`'s `containers:` input is the right tool:** it substitutes the image reference into the manifest **at deploy time**, so the same committed YAML serves every environment and every digest. The manifest in git never contains an environment-specific image.

---

## 5 · Reading the digest from a CI artifact

⭐ **This is what makes the pipeline *CD only* rather than *CI+CD*.** Three rules:

| # | Rule | Enforcement |
|---|---|---|
| 1 | CD **never builds** | ⭐ the CD pipeline's service connection has **no ACR push role** — only `AcrPull` |
| 2 | CD takes a **digest** | the regex check in stage 0, `exit 1` otherwise |
| 3 | The digest came from **our CI** | `cosign verify` pinned to the CI workflow identity |

```bash
# ⭐ the permission asymmetry, set up once
az role assignment create --assignee-object-id "$CD_SP_OBJECT_ID" \
  --assignee-principal-type ServicePrincipal \
  --role AcrPull --scope "$ACR_ID"        # ← CD can ONLY pull

az role assignment create --assignee-object-id "$CI_SP_OBJECT_ID" \
  --assignee-principal-type ServicePrincipal \
  --role AcrPush --scope "$ACR_ID"        # ← CI can push
```

**Why this matters more than the YAML:** a pipeline that *cannot* push an image cannot accidentally become a CI+CD pipeline when someone adds a "quick fix" build step. ⭐ Make the wrong thing impossible rather than discouraged.

---

## 6 · What the approver sees

| Surface | What to put there |
|---|---|
| ⭐ **Instructions for approvers** (the check config) | a three-line checklist: digest matches staging · migration validated · no freeze in effect |
| **The `reason` parameter** | ⭐ required, so it appears in the approval notification |
| **Build tags** (`build.addbuildtag`) | the digest — makes releases searchable in the UI |
| **The published `staging-report` artifact** | readiness, smoke code, migration status, digest |
| ⭐ **Pre-deployment notification** | Environments can email the approver group; also post to Teams/Slack via a `postJob` step in the *staging* stage |

```yaml
# ⭐ notify at the END of staging, so the approver gets a link that works
- stage: Staging
  jobs:
    - deployment: deployStaging
      strategy:
        runOnce:
          deploy:
            steps: [ ... ]
          # ⭐ runs whether the deploy succeeded or not
          on:
            success:
              steps:
                - bash: |
                    curl -fsS -X POST "$(TEAMS_WEBHOOK)" -H 'content-type: application/json' -d @- <<EOF
                    {"title":"⛔ Approval needed — $(service) → production",
                     "text":"**Digest:** $DIGEST\n\n**Reason:** ${{ parameters.reason }}\n\n**Staging:** ready $READY · smoke $SMOKE · migration $MIG\n\n[Open the run]($(System.CollectionUri)$(System.TeamProject)/_build/results?buildId=$(Build.BuildId))"}
                    EOF
                  displayName: '🔔 Notify the approvers'
```

---

## 7 · ⭐ Credentials

| Need | ⭐ Mechanism |
|---|---|
| Pull the image | `AcrPull` on the CD service principal — **not** AcrPush (§5) |
| Reach the cluster | `AzureCLI@2` + `az aks get-credentials` with a **Workload Identity Federation** service connection — ⭐ no client secret stored |
| Per-environment isolation | ⭐ a **separate service connection per environment**, each authorised only for that environment (`azuredevops_environment_resource_authorization`) |
| Pull secrets at deploy time | Azure Key Vault via a **service connection**, or `KeyVault@2` task — never in the YAML |

```
sc-shop-readonly   → AcrPull only                → Resolve stage
sc-shop-shop-dev   → contributor on dev AKS      → environment shop-dev
sc-shop-staging    → contributor on staging AKS  → environment shop-staging
sc-shop-production → ⭐ authorised ONLY for shop-production
```

⭐⭐ **The isolation rule:** a service connection **authorised to an environment** can only be used by jobs declaring that environment. So a compromised dev job cannot use the production connection even though it lives in the same project. That is the Azure DevOps equivalent of GitHub's environment-scoped secrets — set it up or the whole scheme is decorative.

---

## 8 · ⭐ Rollback as a first-class release

`pipelines/rollback-shop-api.yml`

```yaml
trigger: none
parameters:
  - name: target
    type: string
    values: [shop-dev, shop-staging, shop-production]
    default: shop-production
  - name: toDigest
    displayName: '⭐ Roll back TO this digest (blank = previous revision)'
    type: string
    default: ''

pool: { vmImage: ubuntu-latest }

stages:
  - stage: Rollback
    jobs:
      - deployment: rollBack
        environment: ${{ parameters.target }}
        # ⭐⭐ NOTE: the PRODUCTION environment still has its approval check.
        #   For rollback you want it REMOVED. Two options:
        #   (a) a dedicated environment `shop-production-rollback` with an
        #       ExclusiveLock but NO Approval  ← ✅ recommended
        #   (b) temporarily disable the check  ← ⛔ slow, and you will forget
        pool: { vmImage: ubuntu-latest }
        strategy:
          runOnce:
            deploy:
              steps:
                - task: AzureCLI@2
                  inputs:
                    azureSubscription: 'sc-shop-$(target)'
                    scriptType: bash
                    scriptLocation: inlineScript
                    inlineScript: |
                      az aks get-credentials -n $(aksName) -g $(aksRg) --overwrite-existing
                - bash: |
                    set -euo pipefail
                    NS='${{ parameters.target }}'
                    if [ -n '${{ parameters.toDigest }}' ]; then
                      # ⭐ to a KNOWN GOOD digest — the preferred path
                      kubectl -n $NS set image deploy/$(service) \
                        $(service)='$(acr)/$(service)@${{ parameters.toDigest }}'
                    else
                      kubectl -n $NS rollout history deploy/$(service)
                      kubectl -n $NS rollout undo deploy/$(service)
                    fi
                    kubectl -n $NS rollout status deploy/$(service) --timeout=300s
                    kubectl -n $NS get deploy $(service) \
                      -o jsonpath='ROLLBACK COMPLETE → {.spec.template.spec.containers[0].image}{"\n"}'
                  displayName: '🚨 Roll back'
```

⭐⭐ **The design decision worth naming:** give rollback its **own environment** (`shop-production-rollback`) with an **Exclusive Lock but no Approval**. Two reasons: a gate on the way back is a gate on your own recovery; and a separate environment keeps the audit trail clean — "deployments to production" and "rollbacks of production" are different questions and should have different answers.

---

## 9 · Classic release pipelines

If the org still uses them, the same Case 1 shape maps as:

| Concept | Classic equivalent |
|---|---|
| CI pipeline | a **build** pipeline publishing `image-digest` |
| CD pipeline | a **release** pipeline with an artifact source |
| Environments | **Stages** (Dev, Staging, Production) |
| ⭐ Approval gate | **Pre-deployment approvals** on the Production stage |
| Exclusive lock | ⛔ none natively — use a release **deployment gate** or accept the risk |
| Branch control | **Artifact filters** (branch = `main`) |
| Azure Monitor check | a **deployment gate** with the Azure Monitor task |
| Rollback | a **release** with the previous artifact version, or "redeploy" an earlier release |

```
BUILD (CI)  ──publishes──▶  image-digest artifact
                                │
RELEASE (CD)                    ▼
   ┌─ Dev ──────┐  ┌─ Staging ──┐  ┌─ ⛔ Production ─────────────┐
   │ automatic  │─▶│ automatic  │─▶│ PRE-DEPLOYMENT APPROVAL     │
   └────────────┘  └────────────┘  │  approvers: Platform group  │
                                   │  requestor cannot approve   │
                                   │  → deploy → verify          │
                                   └─────────────────────────────┘
```

**Two classic-specific traps:**
- ⛔ **"Enable continuous deployment" on the artifact source** turns this into Case 2 by accident. Leave it **off** for Case 1.
- ⭐ **"Redeploy" of an older release** is your rollback, and it works — but only if the release used a **digest**. With a tag, redeploying re-pulls whatever the tag points at *now*, which is not what ran before.

---

## 10 · Per app shape

| Shape | What changes |
|---|---|
| 🔵 **FE only** (`shop-ui`) | drop the migration template parameter; the smoke check is `GET /` == 200 and `config.js` contains the right `API_URL`. ⭐ Consider no approval at all → Case 2 for the frontend |
| 🟢 **BE only** (`shop-api`) | ⭐ this file, as written |
| 🟢 **BE, worker** (`order-worker`) | ⛔ no HTTP smoke. Verify via a broker metric (consumer connected, queue depth not growing) in the `postRouteTraffic` step |
| 🟡 **FE + BE** (P10) | ⭐⭐ **one pipeline, two stages, ordered:** `Production-api` then `Production-ui`, with the UI stage `dependsOn: Production-api`. Backend first |
| 🟠 **Polyglot** (P11/P12) | one CD pipeline per service + a **manifest-driven** pipeline that takes the release manifest and deploys each service in dependency order |

```yaml
# 🟡 FE after BE, in one pipeline — the ordering is explicit
- stage: ProductionApi
  dependsOn: Staging
  jobs:
    - deployment: api
      environment: shop-production
      strategy: { runOnce: { deploy: { steps: [ ...api... ] } } }

- stage: ProductionUi
  dependsOn: ProductionApi          # ⭐⭐ only after the API is healthy
  jobs:
    - deployment: ui
      environment: shop-production
      strategy: { runOnce: { deploy: { steps: [ ...ui... ] } } }
```

⭐ **Note the single approval:** both stages reference the same `shop-production` environment, so with **Exclusive Lock** the approver approves once and both deploy in order. If you need two separate approvals, use two environments (`shop-production-api`, `shop-production-ui`).

---

## 11 · ▶️ Run it and prove it — the Case 1 acceptance checks

```bash
ORG=https://dev.azure.com/yourorg ; PROJ=shop

# 1 · NO build step in the CD pipeline
grep -nE 'Maven@|DotNetCoreCLI|npm (ci|install)|GoTool|UsePythonVersion.*build' \
  pipelines/cd-shop-api.yml && echo "⛔ CD builds" || echo "✅ CD does not build"

# 2 · the CD service connection can only PULL
az role assignment list --assignee "$CD_SP_OBJECT_ID" --scope "$ACR_ID" \
  --query '[].roleDefinitionName' -o tsv      # ⭐ must be exactly: AcrPull

# 3 · the environment really has an Approval check
ENV_ID=$(az pipelines environment show --organization $ORG --project $PROJ \
         --name shop-production --query id -o tsv)
az rest --method GET --url \
 "$ORG/$PROJ/_apis/distributedtask/environments/$ENV_ID/providers/checks?api-version=7.1" \
 --query 'value[].type.name' -o table
# ⭐ expect: Approval, ExclusiveLock, BranchControl

# 4 · the requestor cannot approve their own release
az rest --method GET --url \
 "$ORG/$PROJ/_apis/distributedtask/environments/$ENV_ID/providers/checks?api-version=7.1" \
 --query "value[?type.name=='Approval'].settings.requestorCannotBeApprover" -o tsv
# ⭐ must print: True

# 5 · there is no auto-trigger
grep -nE '^trigger: none' pipelines/cd-shop-api.yml && echo "✅ manual only"

# 6 · queue it and watch it STOP
az pipelines run --name "CD · shop-api" --branch main \
  --parameters '{"target":"production","reason":"gate test"}' --organization $ORG --project $PROJ
# ⭐ the run must reach "Waiting for approval" and stay there

# 7 · who approved, from the API
az rest --method GET --url \
 "$ORG/$PROJ/_apis/pipelines/runs/<RUN_ID>?api-version=7.1" \
 --query 'state' -o tsv

# 8 · ⭐ what is running in production, one command
az aks get-credentials -n shop-aks -g rg-shop --overwrite-existing
kubectl -n shop-production get deploy shop-api \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
```

---

## 12 · Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| ⭐ **The stage did not stop for approval** | the job is a `job:`, not a `deployment:` job | §1 — only `deployment:` jobs honour environment checks |
| "Job canceled" right after approval | the `condition:` excluded it, or `dependsOn` broke | check `condition` evaluates `${{ parameters.target }}` at **compile** time |
| `stageDependencies` output is empty | the producing step lacked `name:` | every output step needs a `name:` — the reference is `outputs['name.var']` |
| The approver can approve their own request | `requestorCannotBeApprover` not set | §2.2 |
| Two releases deploy simultaneously | no **Exclusive Lock** check | §2.2 |
| A feature branch deployed to production | no **Branch Control** check | §3 |
| `KubernetesManifest@1` says the image is wrong | the `containers:` value must be `name=fullRef`, and the manifest's container `name` must match exactly | ⭐ a typo'd container name fails **silently** — the deploy succeeds with the old image. Always read the image back (§4 `postRouteTraffic`) |
| `az pipelines runs artifact download` fails | the artifact name differs, or the run is not from this definition | print `--top 5` runs first and inspect |
| The gate expires | **Timeout** on the approval check (default 30 days) | requeue; or raise the timeout |
| Rollback blocked by the approval | rollback uses the production environment | ⭐ §8 — a separate `shop-production-rollback` environment with no Approval |

---

<a name="tasks--answers"></a>
## 13 · ⭐ TASKS — answers at the END

| # | Task |
|---|---|
| **T1** | Create `shop-dev` / `shop-staging` / `shop-production` environments with Approval + ExclusiveLock + BranchControl on production, via the REST API |
| **T2** | Prove that a plain `job:` with `environment: shop-production` does **not** stop for approval, and that a `deployment:` job does |
| **T3** | Make the CD pipeline's service connection `AcrPull`-only and show that a `docker push` step fails |
| **T4** | Read the digest from a CI artifact, validate its shape, verify its signature, and add it as a build tag |
| **T5** | Produce the staging report artifact and notify the approver group in Teams/Slack with a working deep link |
| **T6** | Set `requestorCannotBeApprover: true` and demonstrate that the requester is refused |
| **T7** | Add the cross-stage digest assertion so a long approval cannot let a drifted digest through |
| **T8** | Build the ungated rollback pipeline using a dedicated `shop-production-rollback` environment |
| **T9** | Add an Azure Monitor check that refuses to deploy when production's 5xx rate is already elevated |
| **T10** | ⭐⭐ Explain, precisely, why `KubernetesManifest@1` with a mistyped container name is more dangerous than a failing task — and write the check that catches it |

---

# ✅ ANSWERS

**T1.** §2.2 in full. Order matters: create the environment first (`az pipelines environment create`), resolve its numeric `id`, resolve the **group's** identity id (`az devops team list … identity.id` — ⭐ a group, not a user), then POST three checks with increasing `executionOrder`: `Approval` (with `instructions` and `requestorCannotBeApprover: true`), `ExclusiveLock`, `BranchControl` (`allowedBranches: refs/heads/main`). Verify with the GET in §11 check 3 — it must list all three. ⭐ `executionOrder` decides the sequence: the lock is acquired *after* approval, so a queued release does not hold the lock while waiting for a human.

**T2.** Write both in one pipeline: a `job: noGate` with `environment: shop-production` and a `deployment: gated` with the same environment. Run it. **`noGate` proceeds immediately; `gated` waits.** ⭐ The reason is architectural: environment **checks** are evaluated by the deployment-job orchestrator, which only exists for `deployment:` jobs. A plain `job:` gets the *secret scoping* (so `${{ secrets.X }}` resolves only in that environment) but not the *approval*. That asymmetry is why the "my gate didn't fire" incident is so common — everything looks configured correctly, and the mistake is one keyword in the YAML.

**T3.** Two service principals: CI's with `AcrPush`, CD's with **`AcrPull` only** (§5). Then add a `docker push` step to the CD pipeline and run it — it fails with `denied: requested access to the resource is denied`. ⭐ **Why enforce it in IAM rather than in the YAML:** a YAML rule ("don't add build steps") is a convention that survives exactly one urgent Friday fix. A missing role assignment is a hard failure. Make the wrong thing *impossible*, and the pipeline cannot silently drift into being CI+CD — which would break the digest contract that Scenario 2 depends on.

**T4.** Stage 0 (§4): `az pipelines runs artifact download` with `--artifact-name image-digest` into `$(Agent.TempDirectory)`; if `runId` is blank, resolve the latest successful build of the same definition with `az pipelines runs list --status completed --result succeeded --top 1`. Then the regex `^[a-z0-9._/-]+@sha256:[0-9a-f]{64}$` with `exit 1` on mismatch (this rejects `:latest` and `:v1.2.3`), then `cosign verify` pinned to the CI workflow identity, then `echo "##vso[task.setvariable variable=imageRef;isOutput=true]$RAW"` and `##vso[build.addbuildtag]$DIGEST`. ⭐ The build tag is the small detail that pays off: six months later "which release contained digest 41ab…?" is a UI search instead of an archaeology project.

**T5.** The `verify` step in the Staging stage (§4) writes the Markdown table and `publish:`es it as `staging-report`; a `on: success:` step in the same deployment posts a Teams/Slack card containing digest, `${{ parameters.reason }}`, the four staging signals, and `$(System.CollectionUri)$(System.TeamProject)/_build/results?buildId=$(Build.BuildId)`. ⭐ Two details: use the **`on: success` / `on: failure`** hooks of the deployment strategy rather than a separate job (they run with the deployment's context and cannot be skipped by a `condition:` mistake), and make `reason` a **required parameter** — the approver needs the *why* on the screen where they were pinged, or they will click without reading.

**T6.** §2.2 — `requestorCannotBeApprover: true` in the Approval settings. Demonstrate: queue the release as yourself, then open the approval link as yourself. **The Approve button is disabled**, with a message that the requestor cannot approve. ⭐ This is the cheapest real control in the whole system: without it, a single person can start and approve their own production release, which makes the gate a formality and — worse — produces an audit record that *looks* like separation of duties. If your team genuinely has one deployer, the honest answer is to add a second approver, not to relax the setting.

**T7.** `deployStaging`'s verify step emits `stagedDigest` as an output; the production stage's **`preDeploy`** steps compare it with the resolved digest and fail on mismatch (§4 stage 3). ⭐ Use `preDeploy`, not the first `deploy` step: `preDeploy` runs *after* approval and *before* anything touches the cluster, so a drift aborts without a partial rollout. **The window this closes** is real — approvals commonly sit for hours, and during that time CI publishes new digests. If someone requeues with a different digest, or if the pipeline is edited mid-wait, you would promote something staging never ran. Reading the digest **back from the cluster** in staging (rather than forwarding the input) also catches a `KubernetesManifest@1` substitution that silently did not apply.

**T8.** §8. Create `shop-production-rollback` with an **ExclusiveLock and no Approval**, give it its own service connection, and have `rollback-shop-api.yml` target `${{ parameters.target }}` where production maps to the rollback environment. Prefer an **explicit digest** over `rollout undo`: after two failed deploys, "the previous revision" is the *first* bad one, not the last good one. ⭐ **Why a separate environment rather than disabling the check:** (a) a gate on the way back is a gate on your own recovery — during an incident, waiting for an approver is the slow-rollback failure that prerequisite 1 in [`../00-delivery-vs-deployment.md`](../00-delivery-vs-deployment.md) exists to prevent; (b) the audit trail stays meaningful — "who deployed to production" and "who rolled production back" are different questions; (c) the ExclusiveLock still prevents a rollback colliding with an in-flight deploy.

**T9.** Add an **Azure Monitor** check to `shop-production` (§3): a Log Analytics / Application Insights query over the last 15 minutes, e.g. `requests | where resultCode >= 500 | summarize ratio=count()*1.0/toscalar(requests | count())`, with a threshold like `ratio < 0.01`. The check runs **before** the deployment job. ⭐ **What this buys:** it refuses to add a new variable to a system that is already unwell. Deploying into an active incident makes diagnosis vastly harder — you can no longer tell whether the error rate is the incident or the release. **The nuance to state:** this check is about *production's current state*, not about the artifact. It is a policy check, and it complements rather than replaces post-deploy verification. Pair it with a **Business Hours** check so nobody is deploying into a 02:00 quiet period where a breach would go unnoticed anyway.

**T10.** ⭐⭐ **Why it is more dangerous than a failure:** `KubernetesManifest@1`'s `containers:` input is a **substitution directive** of the form `containerName=imageRef`. If `containerName` does not match a container in the manifest, the task finds nothing to substitute — and **succeeds**, applying the manifest with whatever image was already there (or the manifest's default). The stage goes green, the approval is recorded, the run completes, and **production is still running the old digest.** Nobody is alerted, because nothing failed. This is strictly worse than a loud error: a loud error stops the pipeline, a silent success tells you that you deployed something you did not.

**The check that catches it — read the image back from the cluster and compare:**

```yaml
- bash: |
    set -euo pipefail
    WANT='${{ parameters.imageRef }}'                     # what we asked for
    GOT=$(kubectl -n '${{ parameters.namespace }}' get deploy $(service) \
          -o jsonpath='{.spec.template.spec.containers[?(@.name=="$(service)")].image}')
    echo "want=$WANT"; echo "got =$GOT"
    if [ "$GOT" != "$WANT" ]; then
      echo "##vso[task.logissue type=error]⛔ Deployed image does not match the requested digest"
      echo "##vso[task.logissue type=error]Likely cause: container name mismatch in containers: input"
      kubectl -n '${{ parameters.namespace }}' rollout undo deploy/$(service)
      exit 1
    fi
    echo "✅ confirmed running: $GOT"
  displayName: '⭐⭐ Assert the cluster is running the digest we asked for'
```

Two details make it work: query **by container name** with the JSONPath filter `[?(@.name=="…")]` rather than `[0]` (a pod with an init container or a sidecar makes `[0]` wrong), and **undo on mismatch** rather than just failing, because the pipeline may have applied other manifest changes that you do not want left half-applied. ⭐ **The general principle worth stating in an interview:** *never trust a deploy task's exit code as proof of what is running. Verify by reading the desired state back from the cluster.* The same assertion belongs in the GitHub Actions and Jenkins versions of this file — it is tool-independent, and it is the single highest-value line in any CD pipeline.

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish_Kumar_Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn: https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260
🔗 GitHub: https://github.com/3558Bhk

*A `job:` with an environment gets the secrets. Only a `deployment:` job gets the gate.*

</div>
