# 🔷 SCENARIO 3 · CI + CD END TO END WITH AZURE DEVOPS
### A CI pipeline and a CD pipeline linked by `resources.pipelines.trigger`, Workload Identity Federation to ACR *and* AKS, and gates at every boundary.

> **The path:** `git push` → build → test → sign → push to ACR → **digest artifact** → dev → staging → (🔒 Approval *or* 🤖 Azure Monitor gates) → production → verify → record.
>
> **Tool version anchors:** Azure DevOps multi-stage YAML · `Maven@4` · `Docker@2` · `KubernetesManifest@1` · `AzureCLI@2` · `KubectlInstaller@1` · **Workload Identity Federation** · Environments **Approvals and checks** · `resources.pipelines` trigger.

---

## 📇 Contents

| § | What |
|---|---|
| [1](#1---the-architecture-two-pipelines-two-service-connections) | ⭐⭐ The architecture: two pipelines, two service connections |
| [2](#2--the-chaining-mechanism) | The chaining mechanism — and why it beats GitHub's `workflow_run` |
| [3](#3---workload-identity-federation-everywhere) | ⭐ Workload Identity Federation everywhere — no client secret exists |
| [4](#4--pipeline-1--ci-ci-shop-apiyml) | **Pipeline 1 — CI** (`ci-shop-api.yml`), full YAML |
| [5](#5--pipeline-2--cd-cd-shop-apiyml) | **Pipeline 2 — CD** (`cd-shop-api.yml`), full YAML |
| [6](#6---the-artifact-contract--four-checks) | ⭐⭐ The artifact contract — four checks |
| [7](#7--the-permission-map) | The permission map — service connections, environments, and RBAC |
| [8](#8---case-1-or--case-2--which-checks-are-on-the-environment) | 🔒 Case 1 or 🤖 Case 2 — which checks are on the environment |
| [9](#9--templates--the-scale-answer) | Templates — the scale answer, and their one hard limitation |
| [10](#10--️-run-it-end-to-end--the-full-acceptance-checks) | ▶️ Run it end to end — the full acceptance checks |
| [11](#11--troubleshooting) | Troubleshooting |
| [12](#12---tasks--answers-at-the-end) | Tasks and answers — **answers at the END** |

---

## 1 · ⭐⭐ The architecture: two pipelines, two service connections

```
⛔ ONE PIPELINE
   stages: Build → Test → Push → DeployDev → DeployStaging → DeployProd
   THE PROBLEM: one service connection holds
      • AcrPush  (can publish an image)
      • AKS contributor on production (can change production)
   ⭐ `mvn verify` and `npm ci` execute third-party code with BOTH in scope.

✅ TWO PIPELINES
   ci-shop-api  → sc-shop-ci   : AcrPush,           NO cluster role
   cd-shop-api  → sc-shop-prod : AcrPull + AKS,     NO push role
   ⭐ enforced in Azure RBAC — not in a YAML comment.
```

| Property | ⭐ How it is enforced |
|---|---|
| CI cannot deploy | its service connection has **no AKS role assignment at all** |
| CD cannot publish | its service connection has **`AcrPull`, not `AcrPush`** |
| A PR cannot deploy | `pr:` triggers only the CI pipeline; CD has no `pr:` and no git `trigger:` |
| CD deploys only what CI made | ⭐ `resources.pipelines` + `download:` of **that run's** artifact |

```
┌──────────── ci-shop-api (CI) ────────────┐
│ Maven@4 → Docker@2 build → Trivy →        │
│ cosign sign → Docker@2 push               │
│            │                              │
│   publish: image-digest/digest.txt  ⭐ ───┼──┐
│   publish: sbom, test-results             │  │
└───────────────────────────────────────────┘  │ the contract
                                               │
┌──────────── cd-shop-api (CD) ─────────────┐  │
│ resources.pipelines.trigger ← ─ ─ ─ ─ ─ ─ ┼──┘
│   ↓ download: ci-shop-api / image-digest
│ validate → cosign verify → dev → staging
│   → 🔒 Approval | 🤖 Azure Monitor gates
│   → production → READ BACK → record
└───────────────────────────────────────────┘
```

---

## 2 · The chaining mechanism

```yaml
# cd-shop-api.yml
trigger: none          # ⛔ NO git trigger — CD consumes an ARTIFACT, not a commit
pr: none

resources:
  pipelines:
    - pipeline: ci-shop-api          # ⭐ the ALIAS used by `download:`
      source: CI · shop-api          # ⭐ the CI pipeline's exact NAME
      trigger:
        branches: { include: [main] }
        # ⭐ fires only on SUCCEEDED builds — no conclusion check needed
```

### ⭐ Why this is better than GitHub's `workflow_run`

| Concern | 🐙 `workflow_run` | 🔷 `resources.pipelines` |
|---|---|---|
| Fires on failed CI? | ⛔ **yes** — needs `conclusion == 'success'` | ✅ **no** — `trigger` implies success |
| Getting the right artifact | `gh run download <id>` — a CLI call | ⭐ `download: <alias>` — a first-class step |
| Which commit triggered it | `github.event.workflow_run.head_sha` | ⭐ `resources.pipeline.<alias>.sourceCommit` |
| Which build | `github.event.workflow_run.id` | ⭐ `resources.pipeline.<alias>.runID` |
| Branch confusion | ⛔ `github.ref` is the *default* branch | ✅ no ambiguity |

```yaml
steps:
  - download: ci-shop-api                 # ⭐ the ALIAS
    artifact: image-digest
    displayName: '⭐ Download the digest CI published'

  - bash: |
      set -euo pipefail
      RAW=$(cat '$(Pipeline.Workspace)/ci-shop-api/image-digest/digest.txt')
      [[ "$RAW" =~ ^[a-z0-9._/-]+@sha256:[0-9a-f]{64}$ ]] \
        || { echo "##vso[task.logissue type=error]⛔ not a digest: $RAW"; exit 1; }
      echo "##vso[task.setvariable variable=imageRef;isOutput=true]$RAW"
      echo "##vso[task.setvariable variable=digest;isOutput=true]${RAW#*@}"
      echo "##vso[build.addbuildtag]${RAW#*@}"       # ⭐ searchable in the UI
      # ⭐ provenance metadata, for free:
      echo "CI build : $(resources.pipeline.ci-shop-api.runID)"
      echo "CI commit: $(resources.pipeline.ci-shop-api.sourceCommit)"
    name: parsed
```

---

## 3 · ⭐ Workload Identity Federation everywhere

**No client secret exists anywhere in this architecture.**

```bash
# ── ONE-TIME SETUP ─────────────────────────────────────────────────────
# 1 · the CI service connection (AcrPush, no cluster role)
az devops service-endpoint azurerm create \
  --name sc-shop-ci --azure-rm-service-principal-id "$CI_SP_APP_ID" \
  --azure-rm-subscription-id "$SUB" --azure-rm-subscription-name "shop" \
  --azure-rm-tenant-id "$TENANT"
# ⭐ in the portal: "Workload identity federation (automatic)" — Azure DevOps
#   creates the federated credential on the SP for you.

# 2 · ⭐ the SUBJECT CLAIM is what makes this precise
az ad app federated-credential create --id "$CI_SP_APP_ID" --parameters '{
  "name": "ado-shop-ci",
  "issuer": "https://vstoken.actions.azure.com",
  "subject": "sc://ORG/shop/CI · shop-api",
  "audiences": ["api://AzureADTokenExchange"],
  "description": "ADO pipeline CI · shop-api"
}'
# ⭐⭐ the subject is the PIPELINE. A different pipeline in the same project
#   CANNOT mint a token for this principal. That is per-pipeline identity —
#   stronger than a shared secret, and revocable per pipeline.

# 3 · RBAC — the asymmetry that IS the security model
az role assignment create --assignee-object-id "$CI_SP_OBJ_ID" \
  --assignee-principal-type ServicePrincipal --role AcrPush --scope "$ACR_ID"
# ⛔ NO role assignment for the CI principal on the AKS cluster. At all.

az role assignment create --assignee-object-id "$CD_SP_OBJ_ID" \
  --assignee-principal-type ServicePrincipal --role AcrPull --scope "$ACR_ID"
az role assignment create --assignee-object-id "$CD_SP_OBJ_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Azure Kubernetes Service RBAC Cluster Admin" --scope "$AKS_ID"
```

```yaml
# ── IN THE PIPELINE ────────────────────────────────────────────────────
- task: AzureCLI@2
  inputs:
    azureSubscription: 'sc-shop-production'    # ⭐ federation, no secret
    addSpnToEnvironment: false                  # ⭐ there is no SPN to add
    scriptType: bash
    scriptLocation: inlineScript
    inlineScript: |
      az acr login --name shopacr               # ⭐ works via the federated token
      az aks get-credentials -n shop-aks -g rg-shop --overwrite-existing
```

| | ⛔ Service principal + secret | ⭐ Workload Identity Federation |
|---|---|---|
| Stored credential | a client secret, expiring in ≤ 2 years | **none** |
| Rotation | manual, and it breaks pipelines | nothing to rotate |
| Blast radius if leaked | everything the SP can do | ⛔ nothing — there is nothing to leak |
| Per-pipeline identity | ⛔ no — one secret, any pipeline | ⭐ **yes** — the subject claim is the pipeline |

---

## 4 · Pipeline 1 — CI (`ci-shop-api.yml`)

```yaml
# ═══════════════════════════════════════════════════════════════════════
#  WHAT : the CI HALF of Scenario 3 for shop-api (Java 21 / Spring Boot).
#         Maven → Docker build → Trivy → cosign sign → ACR push → digest.
#  WHY  : it must be able to PUBLISH and must NOT be able to DEPLOY.
#         Enforced in Azure RBAC: sc-shop-ci has AcrPush and NO AKS role.
#  TARGET: shopacr.azurecr.io/shop-api — and nothing else.
# ═══════════════════════════════════════════════════════════════════════
trigger:
  branches: { include: [main] }
  paths:    { include: ['apps/shop-api/*', 'pipelines/ci-shop-api.yml'] }
pr:
  branches: { include: [main] }
  paths:    { include: ['apps/shop-api/*'] }

pool: { vmImage: ubuntu-latest }

variables:
  service:      shop-api
  acr:          shopacr
  acrLogin:     shopacr.azurecr.io
  imageName:    $(acrLogin)/$(service)
  # ⭐⭐ THE PUSH FLAG — one variable, one decision
  ${{ if eq(variables['Build.Reason'], 'PullRequest') }}:
    doPush: 'false'
  ${{ else }}:
    doPush: 'true'
  javaVersion:  '21'
  mvnOpts:      '-B -ntp -Dmaven.repo.local=$(Pipeline.Workspace)/.m2'

stages:
  # ═══════════════════════════════════════════════════════════════════
  #  STAGE 1 · BUILD + TEST  (no registry access)
  # ═══════════════════════════════════════════════════════════════════
  - stage: Test
    displayName: '1 · Build and test'
    jobs:
      - job: test
        steps:
          - checkout: self
            fetchDepth: 0                    # ⭐ cosign/ SBOM want real history

          # ── ⭐ MAVEN CACHE — the difference between 6 min and 90 s ────
          - task: Cache@2
            displayName: 'Cache ~/.m2'
            inputs:
              key: 'maven | "$(Agent.OS)" | $(Build.SourcesDirectory)/apps/shop-api/pom.xml'
              path: $(Pipeline.Workspace)/.m2
              restoreKeys: maven | "$(Agent.OS)"

          - task: JavaToolInstaller@0
            inputs: { versionSpec: $(javaVersion), jdkArchitectureOption: x64,
                      jdkSourceOption: PreInstalled }

          - task: Maven@4
            displayName: 'Unit tests'
            inputs:
              mavenPomFile: apps/shop-api/pom.xml
              goals: verify
              options: '$(mvnOpts) -DskipITs'
              javaHomeOption: JDKVersion
              jdkVersionOption: $(javaVersion)
              codeCoverageToolOption: JaCoCo
              publishJUnitResults: true
              testResultsFiles: '**/surefire-reports/TEST-*.xml'

          # ── ⭐ INTEGRATION TESTS: a REAL Postgres 17, not H2 ─────────
          - task: Maven@4
            displayName: '⭐ Integration tests (Testcontainers)'
            inputs:
              mavenPomFile: apps/shop-api/pom.xml
              goals: verify
              options: '$(mvnOpts) -Dit.test=*IT'
            env:
              TESTCONTAINERS_RYUK_DISABLED: 'true'
              # ⭐ Microsoft-hosted agents HAVE a Docker daemon, so
              #   Testcontainers works with no sidecar and no socket mount.

          - task: Maven@4
            displayName: 'Static analysis + dependency CVE'
            inputs:
              mavenPomFile: apps/shop-api/pom.xml
              goals: 'spotbugs:check checkstyle:check org.owasp:dependency-check-maven:check'
              options: '$(mvnOpts)'
            # ⛔ NOT continueOnError — a gate, not a report

          - publish: $(System.DefaultWorkingDirectory)/apps/shop-api/target/site
            artifact: owasp-report
            condition: succeededOrFailed()
            displayName: 'Publish the CVE report'

  # ═══════════════════════════════════════════════════════════════════
  #  STAGE 2 · IMAGE · SCAN · SIGN · PUSH · ⭐ EMIT THE DIGEST
  # ═══════════════════════════════════════════════════════════════════
  - stage: Image
    displayName: '2 · Build, sign and publish'
    dependsOn: Test
    jobs:
      - job: image
        steps:
          - checkout: self

          # ── ⭐ LOGIN VIA FEDERATION — no password variable exists ─────
          - task: AzureCLI@2
            displayName: 'Login to ACR (Workload Identity Federation)'
            condition: eq(variables.doPush, 'true')
            inputs:
              azureSubscription: 'sc-shop-ci'      # ⭐ AcrPush, no AKS role
              scriptType: bash
              scriptLocation: inlineScript
              inlineScript: az acr login --name $(acr)

          # ── BUILD WITH A DIGEST OUTPUT ───────────────────────────────
          - task: Docker@2
            displayName: '⭐ Build and push (multi-stage)'
            condition: eq(variables.doPush, 'true')
            inputs:
              command: buildAndPush
              repository: $(service)
              containerRegistry: 'sc-shop-ci-docker'   # a Docker-registry SC
              Dockerfile: apps/shop-api/Dockerfile
              buildContext: apps/shop-api
              tags: |
                sha-$(Build.SourceVersion)
                latest
              arguments: >
                --provenance=mode=max --sbom=true
                --cache-from type=registry,ref=$(imageName):buildcache
                --cache-to   type=registry,ref=$(imageName):buildcache,mode=max
                --label org.opencontainers.image.revision=$(Build.SourceVersion)

          # ── ⭐⭐ CAPTURE THE DIGEST, NOT THE TAG ─────────────────────
          - bash: |
              set -euo pipefail
              # ⭐ `docker buildx imagetools inspect` resolves the tag to its
              #   digest FROM THE REGISTRY — the only trustworthy source.
              DIGEST=$(docker buildx imagetools inspect \
                        "$(imageName):sha-$(Build.SourceVersion)" \
                        --format '{{json .Manifest}}' | jq -r '.digest')
              [ -n "$DIGEST" ] && [ "$DIGEST" != "null" ] \
                || { echo "##vso[task.logissue type=error]⛔ could not resolve the digest"; exit 1; }
              REF="$(imageName)@${DIGEST}"
              echo "⭐ $REF"
              echo "##vso[task.setvariable variable=imageRef]$REF"
              echo "##vso[task.setvariable variable=digest]$DIGEST"
              echo "##vso[build.addbuildtag]$DIGEST"
              mkdir -p out
              printf '%s\n' "$REF" > out/digest.txt
              cat > out/manifest.json <<EOF
              {"service":"$(service)","image":"$REF","digest":"$DIGEST",
               "commit":"$(Build.SourceVersion)","build":"$(Build.BuildId)",
               "buildUri":"$(System.TeamFoundationCollectionUri)$(System.TeamProject)/_build/results?buildId=$(Build.BuildId)",
               "builtAt":"$(date -u +%FT%TZ)"}
              EOF
            displayName: '⭐⭐ Resolve and emit the digest'

          # ── ⭐ SCAN THE IMAGE, NOT THE SOURCE ────────────────────────
          - bash: |
              set -euo pipefail
              docker run --rm aquasec/trivy:0.66.0 image \
                --exit-code 1 --severity CRITICAL,HIGH --ignore-unfixed \
                --format table "$(imageRef)"
              # ⛔ --exit-code 1 makes it a GATE. ⭐ --ignore-unfixed keeps it
              #   actionable: a CVE with no available fix is not a decision.
            displayName: 'Trivy scan the image'
            condition: eq(variables.doPush, 'true')

          # ── ⭐⭐ KEYLESS SIGNING ─────────────────────────────────────
          - bash: |
              set -euo pipefail
              curl -fsSL https://github.com/sigstore/cosign/releases/download/v2.6.1/cosign-linux-amd64 \
                -o /usr/local/bin/cosign && chmod +x /usr/local/bin/cosign
              # ⭐ a KEY-BASED signature here (not keyless): Azure DevOps has
              #   no OIDC issuer that Rekor trusts for Fulcio, so use a KMS or
              #   a key in Key Vault. This is a REAL difference from GitHub.
              az keyvault secret show --vault-name kv-shop --name cosign-key \
                --query value -o tsv > /tmp/cosign.key
              COSIGN_PASSWORD='' cosign sign --key /tmp/cosign.key --yes "$(imageRef)"
              # ⭐ publish the PUBLIC key so CD can verify it
              cosign public-key --key /tmp/cosign.key > out/cosign.pub
              shred -u /tmp/cosign.key               # ⭐ do not leave it on the agent
            displayName: '⭐ Sign the image (Key Vault key)'
            condition: eq(variables.doPush, 'true')

          # ── ⭐⭐ THE ARTIFACT CONTRACT ───────────────────────────────
          - publish: $(System.DefaultWorkingDirectory)/out
            artifact: image-digest
            displayName: '⭐⭐ Publish the digest artifact (the contract)'
            condition: eq(variables.doPush, 'true')
          # ⭐ CI STOPS HERE. sc-shop-ci has NO AKS role — it cannot deploy.
```

---

## 5 · Pipeline 2 — CD (`cd-shop-api.yml`)

```yaml
# ═══════════════════════════════════════════════════════════════════════
#  WHAT : the CD HALF of Scenario 3 for shop-api.
#         consumes CI's digest → dev → staging → 🔒/🤖 → production.
#  WHY  : it must DEPLOY and must NOT PUBLISH. Enforced in Azure RBAC:
#         sc-shop-* has AcrPull + AKS RBAC, and NO AcrPush.
#  TARGET: AKS shop-aks · namespaces shop-{dev,staging,production}.
# ═══════════════════════════════════════════════════════════════════════
trigger: none            # ⛔ no git trigger — CD consumes an ARTIFACT
pr: none

resources:
  pipelines:
    - pipeline: ci-shop-api
      source: CI · shop-api
      trigger: { branches: { include: [main] } }    # ⭐ succeeded builds only

parameters:
  - name: target
    displayName: 'How far to promote'
    type: string
    default: production
    values: [dev, staging, production]
  - name: reason
    displayName: '⭐ Why are we shipping this? (shown to the approver)'
    type: string
    default: ''
  - name: mode
    displayName: '🔒 delivery (human gate) or 🤖 deployment (automated gates)'
    type: string
    default: delivery
    values: [delivery, deployment]

pool: { vmImage: ubuntu-latest }

variables:
  service:        shop-api
  aksName:        shop-aks
  aksRg:          rg-shop
  kubectlVersion: '1.34.0'
  # ⭐ the environment name follows the mode, so the CHECKS differ (§8)
  ${{ if eq(parameters.mode, 'delivery') }}:
    prodEnv: shop-production            # 🔒 has an Approval check
  ${{ else }}:
    prodEnv: shop-production-auto       # 🤖 has Azure Monitor gates, NO approval

stages:
  # ═══════════════ 0 · RESOLVE + PROVENANCE ═══════════════
  - stage: Resolve
    displayName: '0 · Resolve digest'
    jobs:
      - job: resolve
        steps:
          - download: ci-shop-api
            artifact: image-digest
            displayName: '⭐ Download the digest CI published'
          - bash: |
              set -euo pipefail
              RAW=$(cat '$(Pipeline.Workspace)/ci-shop-api/image-digest/digest.txt')
              # ── CHECK 1 · ⛔ REFUSE A TAG ───────────────────────────
              [[ "$RAW" =~ ^[a-z0-9._/-]+@sha256:[0-9a-f]{64}$ ]] \
                || { echo "##vso[task.logissue type=error]⛔ not a digest: $RAW"; exit 1; }
              echo "##vso[task.setvariable variable=imageRef;isOutput=true]$RAW"
              echo "##vso[task.setvariable variable=digest;isOutput=true]${RAW#*@}"
              echo "##vso[build.addbuildtag]${RAW#*@}"
              echo "⭐ CI build $(resources.pipeline.ci-shop-api.runID), commit $(resources.pipeline.ci-shop-api.sourceCommit)"
            name: parsed
            displayName: 'CHECK 1 · validate the digest shape'
          - bash: |
              set -euo pipefail
              # ── CHECK 2 · ⭐ PROVENANCE ─────────────────────────────
              PUB=$(cat '$(Pipeline.Workspace)/ci-shop-api/image-digest/cosign.pub')
              echo "$PUB" > /tmp/cosign.pub
              cosign verify --key /tmp/cosign.pub "$(parsed.imageRef)" >/dev/null \
                || { echo "##vso[task.logissue type=error]⛔ provenance failed"; exit 1; }
              echo "✅ CHECK 2 · signed by our CI key"
            displayName: 'CHECK 2 · verify provenance'

  # ═══════════════ 1 · DEV ═══════════════
  - stage: Dev
    displayName: '1 · dev'
    dependsOn: Resolve
    condition: in('${{ parameters.target }}', 'dev','staging','production')
    jobs:
      - deployment: dev
        environment: shop-dev                  # ⭐ no checks → automatic
        pool: { vmImage: ubuntu-latest }
        strategy:
          runOnce:
            deploy:
              steps:
                - checkout: self
                - template: templates/deploy-digest.yml
                  parameters:
                    namespace: shop-dev
                    serviceConnection: sc-shop-dev
                    imageRef: $[ stageDependencies.Resolve.resolve.outputs['parsed.imageRef'] ]
                    runMigration: false

  # ═══════════════ 2 · STAGING ═══════════════
  - stage: Staging
    displayName: '2 · staging'
    dependsOn: Dev
    condition: in('${{ parameters.target }}', 'staging','production')
    jobs:
      - deployment: staging
        environment: shop-staging
        pool: { vmImage: ubuntu-latest }
        strategy:
          runOnce:
            deploy:
              steps:
                - checkout: self
                - template: templates/deploy-digest.yml
                  parameters:
                    namespace: shop-staging
                    serviceConnection: sc-shop-staging
                    imageRef: $[ stageDependencies.Resolve.resolve.outputs['parsed.imageRef'] ]
                    runMigration: true
                # ── ⭐ READ THE DEPLOYED DIGEST BACK FROM THE CLUSTER ──
                - bash: |
                    set -euo pipefail
                    D=$(kubectl -n shop-staging get deploy $(service) \
                        -o jsonpath="{.spec.template.spec.containers[?(@.name=='$(service)')].image}")
                    echo "##vso[task.setvariable variable=deployedDigest;isOutput=true]$D"
                    {
                      echo '##[section]⭐ Staging verification — the approver reads this'
                      echo "| check | result |"
                      echo "|---|---|"
                      echo "| digest running | \`$D\` |"
                      echo "| ready replicas | \`$(kubectl -n shop-staging get deploy $(service) -o jsonpath='{.status.readyReplicas}/{.spec.replicas}')\` |"
                      echo "| migration job | \`$(kubectl -n shop-staging get job $(service)-migrate -o jsonpath='{.status.succeeded}')\` |"
                      echo "| CI commit | \`$(resources.pipeline.ci-shop-api.sourceCommit)\` |"
                      echo "| reason | ${{ parameters.reason }} |"
                    } | tee report.md
                  name: verify
                  displayName: '⭐ Verify staging and build the evidence'
                - publish: report.md
                  artifact: staging-report
            on:
              success:
                steps:
                  - bash: |
                      curl -fsS -X POST "$(TEAMS_WEBHOOK)" -H 'content-type: application/json' -d @- <<EOF
                      {"title":"⛔ Approval needed — $(service) → production (${{ parameters.mode }})",
                       "text":"**Digest:** $(verify.deployedDigest)\n\n**Reason:** ${{ parameters.reason }}\n\n**CI:** $(resources.pipeline.ci-shop-api.sourceCommit)\n\n[Open the run]($(System.CollectionUri)$(System.TeamProject)/_build/results?buildId=$(Build.BuildId))"}
                      EOF
                    displayName: '🔔 Notify'

  # ═══════════════ 3 · PRODUCTION ═══════════════
  - stage: Production
    displayName: '3 · production'
    dependsOn: Staging
    condition: eq('${{ parameters.target }}', 'production')
    jobs:
      - deployment: prod
        environment: $(prodEnv)      # ⭐⭐ THE MODE SELECTS THE ENVIRONMENT,
                                     #    AND THE ENVIRONMENT HOLDS THE GATES (§8)
        pool: { vmImage: ubuntu-latest }
        strategy:
          runOnce:
            preDeploy:
              steps:
                # ── CHECK 3 · ⭐ NO DRIFT ACROSS THE GATE ────────────────
                - bash: |
                    set -euo pipefail
                    STAGED='${{ stageDependencies.Staging.staging.outputs.verify.deployedDigest }}'
                    WANT='${{ stageDependencies.Resolve.resolve.outputs.parsed.imageRef }}'
                    [ "$STAGED" = "$WANT" ] || {
                      echo "##vso[task.logissue type=error]⛔ staging ran $STAGED, production cleared for $WANT"
                      exit 1; }
                    echo "✅ CHECK 3 · staging and production agree on $WANT"
                  displayName: 'CHECK 3 · assert staging ran this exact digest'
            deploy:
              steps:
                - checkout: self
                - template: templates/deploy-digest.yml
                  parameters:
                    namespace: shop-production
                    serviceConnection: sc-shop-production
                    imageRef: $[ stageDependencies.Resolve.resolve.outputs['parsed.imageRef'] ]
                    runMigration: true
                    postVerifyMinutes: 10          # ⭐ G5 · watch after promotion
            on:
              failure:
                steps:
                  - bash: |
                      echo "##vso[task.logissue type=error]🚨 production deploy FAILED — rolling back"
                      kubectl -n shop-production rollout undo deploy/$(service)
                      kubectl -n shop-production rollout status deploy/$(service) --timeout=300s || true
                      # ⭐⭐ CIRCUIT BREAKER — stop the next release
                      az storage blob upload --container-name cd-state \
                        --name HALTED-$(service) --file /dev/null --overwrite
                      curl -fsS -X POST "$(PAGERDUTY_URL)" -H 'content-type: application/json' -d @- <<EOF
                      {"routing_key":"$(PD_KEY)","event_action":"trigger",
                       "payload":{"summary":"🚨 $(service) auto-rolled back — promotions HALTED",
                                  "severity":"critical","source":"azure-devops",
                                  "custom_details":{"build":"$(System.CollectionUri)$(System.TeamProject)/_build/results?buildId=$(Build.BuildId)"}}}
                      EOF
                    displayName: '🚨 Roll back, halt, page'
```

### 5.1 `templates/deploy-digest.yml` — shared by both cases

```yaml
parameters:
  - { name: namespace,         type: string }
  - { name: serviceConnection, type: string }
  - { name: imageRef,          type: string }
  - { name: runMigration,      type: boolean, default: false }
  - { name: probe,             type: string,  default: '/actuator/health/readiness' }
  - { name: port,              type: number,  default: 8080 }
  - { name: timeout,           type: number,  default: 600 }
  - { name: postVerifyMinutes, type: number,  default: 0 }

steps:
  - task: KubectlInstaller@1
    inputs: { kubectlVersion: $(kubectlVersion) }        # ⭐ pinned

  - task: AzureCLI@2
    displayName: 'Authenticate (Workload Identity Federation)'
    inputs:
      azureSubscription: '${{ parameters.serviceConnection }}'
      scriptType: bash
      scriptLocation: inlineScript
      inlineScript: az aks get-credentials -n $(aksName) -g $(aksRg) --overwrite-existing

  # ── ⭐⭐ MIGRATION FIRST, AS A GATED JOB ──────────────────────────────
  - ${{ if eq(parameters.runMigration, true) }}:
    - bash: |
        set -euo pipefail
        NS='${{ parameters.namespace }}'; SVC=$(service)
        kubectl -n $NS delete job "$SVC-migrate" --ignore-not-found
        kubectl -n $NS apply -f "k8s/$SVC/migration-job.yaml"
        kubectl -n $NS wait --for=condition=complete "job/$SVC-migrate" --timeout=600s \
          || { echo "##vso[task.logissue type=error]⛔ migration FAILED — not rolling out"; exit 1; }
      displayName: 'Run the migration Job and wait for it'

  # ── VALIDATE · RECORD · DEPLOY · ⭐ READ BACK ────────────────────────
  - bash: |
      set -euo pipefail
      NS='${{ parameters.namespace }}'; SVC=$(service); REF='${{ parameters.imageRef }}'
      [[ "$REF" =~ @[a-z0-9]+:[0-9a-f]{64}$ ]] \
        || { echo "##vso[task.logissue type=error]⛔ not a digest"; exit 1; }

      PREV=$(kubectl -n $NS get deploy $SVC \
             -o jsonpath="{.spec.template.spec.containers[?(@.name=='$SVC')].image}")
      echo "📌 previous: $PREV"
      echo "##vso[task.setvariable variable=prevImage]$PREV"
      if [ "$PREV" = "$REF" ]; then echo "ℹ️ already running $REF — no-op"; exit 0; fi

      kubectl -n $NS apply -f "k8s/$SVC/"
      kubectl -n $NS set image "deploy/$SVC" "$SVC=$REF"
      if ! kubectl -n $NS rollout status "deploy/$SVC" --timeout=${{ parameters.timeout }}s; then
        echo "##vso[task.logissue type=error]⛔ rollout did not converge — undoing"
        kubectl -n $NS set image "deploy/$SVC" "$SVC=$PREV"
        kubectl -n $NS rollout status "deploy/$SVC" --timeout=300s || true
        exit 1
      fi
      # ── CHECK 4 · ⭐⭐ READ IT BACK FROM THE CLUSTER ──────────────────
      NOW=$(kubectl -n $NS get deploy $SVC \
            -o jsonpath="{.spec.template.spec.containers[?(@.name=='$SVC')].image}")
      [ "$NOW" = "$REF" ] \
        || { echo "##vso[task.logissue type=error]⛔ CHECK 4 failed: running $NOW, wanted $REF"; exit 1; }
      echo "✅ CHECK 4 · $NS confirmed running $NOW"
    displayName: '⭐ Deploy the digest and read it back'

  # ── ⭐ SMOKE FROM INSIDE THE CLUSTER ─────────────────────────────────
  - bash: |
      set -euo pipefail
      NS='${{ parameters.namespace }}'; SVC=$(service)
      kubectl -n $NS run smoke-$RANDOM --rm -i --restart=Never \
        --image=curlimages/curl:8.17.0 -- \
        curl -fsS "http://$SVC.$NS.svc.cluster.local:${{ parameters.port }}${{ parameters.probe }}"
      # ⭐ from INSIDE: tests the Service selector and the endpoints, which
      #   an external curl through the ingress cannot isolate.
    displayName: '⭐ Smoke from inside the cluster'

  # ── ⭐ G5 · POST-DEPLOY WATCH (production only) ──────────────────────
  - ${{ if gt(parameters.postVerifyMinutes, 0) }}:
    - bash: |
        set -euo pipefail
        FAILS=0; END=$(( $(date +%s) + ${{ parameters.postVerifyMinutes }} * 60 ))
        while [ "$(date +%s)" -lt "$END" ]; do
          ERR=$(./scripts/err-ratio.sh shop-production $(service) 5m)
          if (( $(echo "$ERR > 0.01" | bc -l) )); then FAILS=$((FAILS+1)); else FAILS=0; fi
          [ "$FAILS" -ge 3 ] && { echo "##vso[task.logissue type=error]⛔ regression detected"; exit 1; }
          sleep 60
        done
        echo "✅ stable for ${{ parameters.postVerifyMinutes }} minutes"
      displayName: '⭐ Watch production metrics'
```

---

## 6 · ⭐⭐ The artifact contract — four checks

| # | Check | Where | What it proves |
|---|---|---|---|
| **1** | ⛔ **digest, not tag** | CD `Resolve` — the regex | the artifact is immutable |
| **2** | ⭐ **provenance** (`cosign verify` with the CI key) | CD `Resolve` | it was signed by *our* CI, not pushed by hand |
| **3** | ⭐ **staging ran this exact digest** | CD `Production.preDeploy` | no drift across the gate |
| **4** | ⭐⭐ **the cluster runs this digest after deploy** | the template, post-`rollout status` | the deploy actually happened |

**Plus two structural ones:**

| Check | ⭐ How Azure DevOps enforces it |
|---|---|
| CI cannot deploy | ⭐ **RBAC** — `sc-shop-ci` has **no** role assignment on the AKS cluster |
| CD cannot publish | ⭐ **RBAC** — `sc-shop-*` has **`AcrPull`**, not `AcrPush` |

```bash
# ⭐ prove both, from Azure rather than from the YAML
CI_SP=$(az devops service-endpoint show --id "$CI_SC_ID" --query 'servicePrincipalId' -o tsv)
az role assignment list --assignee "$CI_SP" --query '[].{role:roleDefinitionName,scope:scope}' -o table
# ⭐ must show AcrPush on the ACR and NOTHING on the AKS cluster

CD_SP=$(az devops service-endpoint show --id "$PROD_SC_ID" --query 'servicePrincipalId' -o tsv)
az role assignment list --assignee "$CD_SP" --query '[].roleDefinitionName' -o tsv
# ⭐ must show AcrPull + AKS RBAC, and NOT AcrPush
```

---

## 7 · The permission map

| Service connection | RBAC | Used by | Authorised to environment |
|---|---|---|---|
| `sc-shop-ci` | ⭐ `AcrPush` **only** | CI `Image` stage | — |
| `sc-shop-ci-docker` | Docker registry SC for `Docker@2` | CI `Image` stage | — |
| `sc-shop-readonly` | `AcrPull` + metrics read | CD `Resolve` (cosign, gates) | all |
| `sc-shop-dev` | AKS RBAC on dev | CD `Dev` | ⭐ `shop-dev` only |
| `sc-shop-staging` | AKS RBAC on staging | CD `Staging` | ⭐ `shop-staging` only |
| `sc-shop-canary` | ⭐ narrow: `argoproj.io/rollouts` patch, no `delete` | CD canary | `shop-canary` only |
| `sc-shop-production` | AKS RBAC on prod | CD `Production` | ⭐⭐ `shop-production` only |

```hcl
# ⭐ the authorisation that makes the map real
resource "azuredevops_environment_resource_authorization" "prod" {
  project_id  = azuredevops_project.shop.id
  resource_id = azuredevops_serviceendpoint_azurerm.production.id
  type        = "serviceendpoint"
  environment = azuredevops_environment.production.name
}
# ⭐⭐ without this, ANY job in the project can name the production service
#   connection. With it, only a job declaring `environment: shop-production`
#   can — which is the Azure DevOps equivalent of GitHub's environment secrets.
```

⭐ **Plus Key Vault** for `cosign.key`, `TEAMS_WEBHOOK` and `PD_KEY`, referenced via a variable group with a **service connection** — never as pipeline variables in the YAML.

---

## 8 · 🔒 Case 1 or 🤖 Case 2 — which checks are on the environment

⭐ **In Azure DevOps the switch is not a YAML flag — it is *which environment the stage targets*, and therefore which checks apply.**

```yaml
variables:
  ${{ if eq(parameters.mode, 'delivery') }}:
    prodEnv: shop-production         # 🔒 Approval + ExclusiveLock + BranchControl
  ${{ else }}:
    prodEnv: shop-production-auto    # 🤖 AzureMonitor + REST(halt) + ExclusiveLock
```

| Check | `shop-production` 🔒 | `shop-production-auto` 🤖 |
|---|---|---|
| **Approval** (group, `requestorCannotBeApprover`) | ✅ | ⛔ **absent** |
| **Exclusive Lock** | ✅ | ✅ |
| **Branch Control** (`refs/heads/main`) | ✅ | ✅ |
| ⭐ **Azure Monitor** (err rate < 1%, retry 6× / 5 min) | ✅ advisory | ✅ **decisive** |
| ⭐ **REST** (halt flag + freeze calendar) | ✅ | ✅ |
| **Business Hours** | optional | ✅ |
| Canary stage in the YAML | ⛔ | ✅ `strategy: canary` |
| `on: failure` rollback | ✅ | ✅ |

```bash
# ⭐ create the Case 2 environment — the same cluster, different checks
az pipelines environment create --organization $ORG --project shop \
  --name shop-production-auto --description "Production · automated gates, no human"
# then add AzureMonitor + REST + ExclusiveLock + BusinessHours, and NO Approval.
# ⭐⭐ authorise sc-shop-production to BOTH environments — one connection,
#   two policies.
```

⭐⭐ **Why two environments rather than one flag:** in Azure DevOps the gates are **properties of the environment**, not of the pipeline. Two environments means the Case 1 and Case 2 policies coexist, are independently auditable ("who can approve `shop-production`?"), and switching a service is a one-line `variables:` change. It also means a **canary** environment can hold a *narrower* service connection (§7) than full production — which a single-environment design cannot express.

---

## 9 · Templates — the scale answer

```
pipelines/
├── ci-shop-api.yml
├── cd-shop-api.yml
└── templates/
    ├── deploy-digest.yml        ⭐ §5.1 — used by BOTH cases
    ├── java-build.yml           Maven + cache + Testcontainers
    ├── node-build.yml           npm ci + build + bundle gate + Lighthouse
    ├── go-build.yml             go test -race + govulncheck
    ├── python-build.yml         uv sync + pytest + pip-audit
    └── scan-and-sign.yml        Trivy + cosign
```

```yaml
# ⭐ the caller — a per-language CI in ~15 lines
stages:
  - stage: Build
    jobs:
      - job: build
        steps:
          - template: templates/go-build.yml
            parameters: { projectDir: apps/checkout, port: 9091 }
          - template: templates/scan-and-sign.yml
            parameters: { imageName: $(imageName), doPush: $(doPush) }
```

### ⭐ The one hard limitation

```
⛔ TEMPLATES CANNOT LOOP OVER A RUNTIME LIST.
   `${{ each }}` is a COMPILE-TIME construct — it expands before the
   pipeline runs, over a `parameters` array. It CANNOT iterate over a
   variable, an artifact's contents, or a query result.

✅ SO FOR A POLYGLOT RELEASE TRAIN:
   - a compile-time `parameters: services: [...]` array  ← works, but the
     list is hardcoded in the YAML
   - or one pipeline per service + a coordinator          ← ⭐ the usual answer
   - or a `bash:` loop inside ONE job                     ← works, but you lose
     per-service parallelism and per-service reporting
```

| ⭐ Rule | Why |
|---|---|
| Templates hold the **gates** | so a service cannot opt out of the read-back assertion |
| `parameters`, never `variables`, for template control flow | templates are expanded at compile time |
| One template per **language**, one per **action** | `java-build.yml` (language) vs `scan-and-sign.yml` (action) |
| ⭐ Version templates in the same repo as the callers | a template in a separate repo needs `resources.repositories` and a ref pin |

---

## 10 · ▶️ Run it end to end — the full acceptance checks

```bash
ORG=https://dev.azure.com/yourorg

# ── CI HALF ────────────────────────────────────────────────────────────
# 1 · ⭐ CI's service connection has AcrPush and NO AKS role
CI_SP=$(az devops service-endpoint show --id "$CI_SC" --query servicePrincipalId -o tsv)
az role assignment list --assignee "$CI_SP" --query '[].roleDefinitionName' -o tsv
# ⭐ must print exactly: AcrPush   (and nothing AKS-related)

# 2 · CI does not deploy
grep -nE 'KubernetesManifest|kubectl|aks get-credentials' pipelines/ci-shop-api.yml \
  && echo "⛔ CI deploys" || echo "✅ CI does not deploy"

# 3 · CI does not push on a PR
grep -A3 'Build.Reason' pipelines/ci-shop-api.yml | grep -q 'PullRequest' && echo "✅ PR-safe"

# 4 · the digest artifact exists
BID=$(az pipelines runs list --pipeline-ids "$CI_ID" --branches main \
      --status completed --result succeeded --top 1 --query '[0].id' -o tsv)
az pipelines runs artifact download --pipeline-id "$CI_ID" --run-id "$BID" \
  --artifact-name image-digest --path /tmp/dl
cat /tmp/dl/image-digest/digest.txt      # ⭐ shopacr.azurecr.io/shop-api@sha256:…

# ── THE CHAIN ──────────────────────────────────────────────────────────
# 5 · ⭐⭐ THE END-TO-END TEST
git commit --allow-empty -m "e2e: trigger CI+CD" && git push origin main
watch -n 10 'az pipelines runs list --pipeline-ids "'"$CI_ID,$CD_ID"'" --top 4 \
  --query "[].{p:pipeline.name,id:id,status:status,result:result}" -o table'
# ⭐ CI must succeed, THEN CD must start automatically with no human action

# ── CD HALF ────────────────────────────────────────────────────────────
# 6 · ⭐ CD's service connection has NO AcrPush
CD_SP=$(az devops service-endpoint show --id "$PROD_SC" --query servicePrincipalId -o tsv)
az role assignment list --assignee "$CD_SP" --query '[].roleDefinitionName' -o tsv \
  | grep -q AcrPush && echo "⛔ CD can publish" || echo "✅ CD cannot publish"

# 7 · CD has no git trigger
grep -q '^trigger: none' pipelines/cd-shop-api.yml && echo "✅ artifact-driven"

# 8 · all four contract checks are present
grep -c 'CHECK 1\|CHECK 2\|CHECK 3\|CHECK 4' pipelines/cd-shop-api.yml pipelines/templates/deploy-digest.yml

# 9 · the environment has an Approval check IFF mode=delivery
for E in shop-production shop-production-auto; do
  ID=$(az pipelines environment show --organization $ORG --project shop --name $E --query id -o tsv)
  echo "── $E"; az rest --method GET --url \
   "$ORG/shop/_apis/distributedtask/environments/$ID/providers/checks?api-version=7.1" \
   --query 'value[].type.name' -o tsv
done
# ⭐ shop-production      → Approval, ExclusiveLock, BranchControl, …
# ⭐ shop-production-auto → ExclusiveLock, AzureMonitor, REST, BusinessHours (NO Approval)

# 10 · ⭐ CHECK 4 — what is ACTUALLY running
az aks get-credentials -n shop-aks -g rg-shop --overwrite-existing
kubectl -n shop-production get deploy shop-api \
  -o jsonpath='{.spec.template.spec.containers[?(@.name=="shop-api")].image}{"\n"}'
# ⭐ must equal the digest from check 4

# 11 · the service connection is authorised ONLY to its environment
az rest --method GET --url \
 "$ORG/shop/_apis/distributedtask/environments/$PROD_ENV_ID/providers/resourceref?api-version=7.1"

# 12 · ⭐⭐ rollback is ungated
az pipelines runs list --pipeline-ids "$ROLLBACK_ID" --top 1 --query '[].result' -o tsv
```

⭐⭐ **Checks 1, 5, 6 and 10 are the four that matter.** 1 and 6 prove the credential asymmetry **in Azure RBAC rather than in YAML**; 5 proves the chain fires on a real commit; 10 proves that what CI published is literally what production runs.

---

## 11 · Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| ⛔ CD never triggers | `source:` does not match the CI pipeline's exact **name** (spaces, `·`) | `az pipelines list --query '[].name'` |
| CD triggers on failed CI | a git `trigger:` is present alongside `resources` | `trigger: none` |
| `download: ci-shop-api` finds nothing | the **alias** differs, or CI did not `publish:` (a PR) | check `doPush` was `true`; `ls $(Pipeline.Workspace)` |
| ⛔ `$(parsed.imageRef)` is empty | the producing step lacks `name:` | add `name: parsed` — refs are `outputs['name.var']` |
| `stageDependencies` empty across stages | the job (not just the step) lacks a name, or the stage `dependsOn` is wrong | §5 |
| ⛔ `Docker@2` cannot resolve the digest | `buildx imagetools inspect` needs registry access **after** login | run it in a step after `az acr login`, or use `--format '{{json .Manifest}}'` |
| `az acr login` fails with a federated SC | `addSpnToEnvironment: true` and code expecting `$servicePrincipalId` | ⭐ there is no SPN — remove the flag and the env var use |
| ⛔ The federated token is rejected | the **subject claim** does not match the pipeline | `sc://ORG/project/PIPELINE_NAME` — exact, including spaces and `·` |
| Trivy passes but a CVE ships | ⛔ no `--exit-code 1` | §4 — it must be a gate |
| `cosign verify` fails in CD | the **public** key was not published as an artifact | §4 — `cosign public-key > out/cosign.pub` |
| ⛔ A stage still waits for approval in `deployment` mode | the stage targets `shop-production`, not `shop-production-auto` | §8 — the `prodEnv` variable is mode-selected |
| `${{ each }}` over a variable does nothing | ⛔ templates expand at **compile** time | §9 — use a `parameters` array or a runtime `bash:` loop |
| `KubernetesManifest@1` deploys the old image | ⛔ the container **name** in `containers:` does not match | CHECK 4 reads it back (§5.1) |
| The migration Job is skipped | `runMigration` defaults to `false` | pass `true` (§5) |
| ⛔ Paged repeatedly after a failure | no halt flag | the `on: failure` steps set `HALTED-$(service)` (§5) |
| Testcontainers fails on a self-hosted Linux agent | no Docker daemon, or the agent user is not in `docker` | ⛔ never mount the socket; use a sidecar or a VM agent |

---

<a name="tasks--answers"></a>
## 12 · ⭐ TASKS — answers at the END

| # | Task |
|---|---|
| **T1** | Build the two-pipeline chain for `shop-api` and prove the credential asymmetry **in Azure RBAC** |
| **T2** | Wire `resources.pipelines.trigger` and download the triggering run's artifact with provenance metadata |
| **T3** | Set up Workload Identity Federation for both service connections and explain what the subject claim buys you |
| **T4** | Resolve the pushed digest with `docker buildx imagetools inspect` and explain why you cannot trust the tag |
| **T5** | Implement all four artifact-contract checks and demonstrate each one failing |
| **T6** | Create `shop-production` and `shop-production-auto` and make `parameters.mode` select between them |
| **T7** | Extract `templates/deploy-digest.yml` and migrate three services (Java, Go, React) onto it |
| **T8** | Add the migration Job to the template so it gates the rollout, and prove a bad migration stops the pipeline |
| **T9** | Chain FE after BE for shape C, with one approval and roll-back-both on FE failure |
| **T10** | ⭐⭐ A malicious Maven dependency executes during `mvn verify` in your CI job. Describe precisely what it can and cannot do here — and name the two configuration mistakes that would give it production access |

---

# ✅ ANSWERS

**T1.** §4 and §5. **The proof must come from Azure, not from the YAML** — that is the whole point of enforcing it in RBAC:
```bash
CI_SP=$(az devops service-endpoint show --id "$CI_SC" --query servicePrincipalId -o tsv)
az role assignment list --assignee "$CI_SP" --query '[].{role:roleDefinitionName,scope:scope}' -o table
# ⭐ AcrPush on the ACR scope, and NOTHING on the AKS cluster scope
CD_SP=$(az devops service-endpoint show --id "$PROD_SC" --query servicePrincipalId -o tsv)
az role assignment list --assignee "$CD_SP" --query '[].roleDefinitionName' -o tsv
# ⭐ AcrPull + AKS RBAC Cluster Admin, and NOT AcrPush
```
Then demonstrate both failures: add `az aks get-credentials` to a CI step → **it fails**, because the CI principal has no AKS role. Add `docker push` to a CD step → **`denied: requested access to the resource is denied`**. ⭐ **Why RBAC rather than YAML:** a YAML rule ("don't add deploy steps to CI") is a convention that survives exactly one urgent Friday fix. A missing role assignment is a hard failure that no pipeline edit can bypass. Also verify the **environment resource authorisation** (§7) — without it, any job in the project can name `sc-shop-production`, and the whole map is decorative.

**T2.** §2. `trigger: none`, `pr: none`, then `resources.pipelines` with `pipeline: ci-shop-api` (the **alias**), `source: CI · shop-api` (the CI pipeline's exact **name**, including the middle dot — ⭐ a rename silently breaks the chain and nothing errors), and `trigger.branches.include: [main]`. Download with `download: ci-shop-api` + `artifact: image-digest`, read `$(Pipeline.Workspace)/ci-shop-api/image-digest/digest.txt`, validate the shape with the regex, and emit `##vso[task.setvariable variable=imageRef;isOutput=true]` plus `##vso[build.addbuildtag]${RAW#*@}`. **Provenance metadata is free:** `$(resources.pipeline.ci-shop-api.runID)` and `.sourceCommit` — put both in the staging report and in the audit record. ⭐ **Two properties make this better than GitHub's `workflow_run`:** `trigger` fires only on **succeeded** builds (no `conclusion == 'success'` condition needed), and `download:` fetches **exactly that run's** artifact rather than "the latest", which removes the race where two quick commits let CD pick up the wrong digest.

**T3.** §3. Create both service connections with **"Workload identity federation (automatic)"**, then a federated credential per pipeline: `issuer: https://vstoken.actions.azure.com`, `subject: sc://ORG/shop/CI · shop-api`, `audiences: ["api://AzureADTokenExchange"]`. In the pipeline, `AzureCLI@2` with `azureSubscription: <the SC>` — and ⛔ `addSpnToEnvironment: false`, because there is no SPN to add (code expecting `$servicePrincipalId` will find it empty). **What the subject claim buys you:** ⭐ **per-pipeline identity.** The subject names the *pipeline*, so a different pipeline in the same project **cannot mint a token for this principal** — even one whose YAML names the same service connection. Combined with `azuredevops_environment_resource_authorization`, you get two independent boundaries: which *pipeline* can assume the identity, and which *environment* a job must declare to use the connection. Compare with a client secret: one secret, readable by any job that can name the connection, exfiltratable, expiring, and needing rotation that breaks pipelines. **There is nothing to leak** with federation — which is why the answer to "what happens if the secret is stolen?" is "there is no secret".

**T4.** §4, the "Resolve and emit the digest" step: `docker buildx imagetools inspect "$(imageName):sha-$(Build.SourceVersion)" --format '{{json .Manifest}}' | jq -r '.digest'`, then compose `$(imageName)@${DIGEST}`. ⭐ **Why the tag cannot be trusted:** `Docker@2` reports success based on the *push*, and the tag it pushed is a **mutable pointer** — the value you need for the artifact contract is the digest the *registry* assigned, which only the registry knows. Reading it back with `imagetools inspect` also proves the image is actually retrievable, which a local `docker inspect` does not (it would report the local build's digest, and a failed push would go unnoticed). **Guard the null case** — `[ -n "$DIGEST" ] && [ "$DIGEST" != "null" ]` — because a `jq -r` on an unexpected shape yields the literal string `null`, which would otherwise be published as `image@null` and fail confusingly in CD. ⭐ Also emit `--provenance=mode=max --sbom=true` on the build so the attestation is attached to that digest, and publish `cosign.pub` as part of the same artifact so CD can verify without a Key Vault round-trip.

**T5.** §6. **(1) digest shape** — the regex in CD `Resolve`; demonstrate with a manually-queued run pointed at `…:latest` → fails at stage 0. **(2) provenance** — `cosign verify --key /tmp/cosign.pub "$(parsed.imageRef)"` using the `cosign.pub` published by CI; demonstrate by `docker push`ing an image by hand and passing its digest → `⛔ provenance failed`. ⭐ Note the Azure DevOps-specific difference: **keyless signing is not available**, because Azure DevOps has no OIDC issuer that Fulcio/Rekor trusts — so CI signs with a Key Vault key and publishes the public key. That is a real portability difference from the GitHub version, not an oversight. **(3) no drift** — `Production`'s `preDeploy` step compares `stageDependencies.Staging.staging.outputs.verify.deployedDigest` (⭐ **read back from the cluster**, not forwarded) against the resolved ref; demonstrate by approving a run whose digest differs from staging's. **(4) confirmed running** — the template's post-`rollout status` read-back using the JSONPath **name filter** `[?(@.name=='$(service)')]`; demonstrate by mistyping the container name in `set image`, which exits 0 and is caught only here. ⭐ **Check 4 catches the most dangerous failure**, because `KubernetesManifest@1` and `kubectl set image` both succeed when the deployment exists even if the container name does not match — a green pipeline, a recorded approval, and production still on the old digest.

**T6.** §8. `az pipelines environment create --name shop-production-auto`, then add **AzureMonitor** (error-rate query, `retryInterval: 300`, `maxRetryCount: 6`), **REST** (halt flag + freeze calendar, `executionOrder: 0`), **ExclusiveLock** and **BusinessHours** — and **no Approval**. Authorise `sc-shop-production` to **both** environments. In the YAML: `${{ if eq(parameters.mode,'delivery') }}: prodEnv: shop-production ${{ else }}: prodEnv: shop-production-auto`, referenced as `environment: $(prodEnv)`. ⭐ **Why two environments rather than one flag in the YAML:** in Azure DevOps the gates are **properties of the environment**, not of the pipeline — so two environments means both policies coexist, are independently auditable ("who can approve `shop-production`?" has an answer, and "what gates `shop-production-auto`?" has a different one), and switching a service is a one-line variable change rather than a settings migration. It also lets the **canary** environment hold a *narrower* service connection than full production (§7) — which a single-environment design cannot express. ⭐ **The `${{ }}` vs `$()` distinction matters here:** `${{ if }}` is compile-time, so `prodEnv` is fixed when the run is queued — correct, because the environment must be known before the job starts. `$(prodEnv)` at the `environment:` key is a runtime variable reference, which Azure DevOps does support for environment selection.

**T7.** §5.1 plus §9. Extract the shared template with parameters `namespace`, `serviceConnection`, `imageRef`, `runMigration`, `probe`, `port`, `timeout`, `postVerifyMinutes`. Then one **CI** template per language (`java-build.yml` with `Maven@4` + `Cache@2` + Testcontainers; `go-build.yml` with `go test -race` + `govulncheck`; `node-build.yml` with `npm ci` + the bundle gate + Lighthouse) and one per **action** (`scan-and-sign.yml`), so a service's CI is ~15 lines. Migrate `shop-api` (Java, `runMigration: true`, `probe: /actuator/health/readiness`, port 8080), `checkout` (Go, `runMigration: false`, `probe: /readyz`, port 9091) and `shop-ui` (React, `probe: /`, port 80, plus the `config.js` `API_URL` assertion). ⭐ **Four rules:** templates hold the **gates**, so no service can opt out of the read-back assertion or the inside-the-cluster smoke test; **`parameters`, never `variables`**, for template control flow, because `${{ }}` expands at compile time; `postVerifyMinutes: 0` as the default means dev/staging skip the watch while production opts in; and ⛔ **templates cannot loop over a runtime list** — `${{ each }}` iterates a compile-time `parameters` array only, so a polyglot release train needs either a hardcoded array, one pipeline per service plus a coordinator, or a `bash:` loop inside one job (which loses per-service parallelism and reporting).

**T8.** §5.1. In the template, gated by `${{ if eq(parameters.runMigration, true) }}`: `kubectl delete job "$SVC-migrate" --ignore-not-found`, `kubectl apply -f "k8s/$SVC/migration-job.yaml"`, then `kubectl wait --for=condition=complete "job/$SVC-migrate" --timeout=600s || exit 1` **before** `set image`. ⭐ Three details make it correct: the Job's container image must be **the same digest** as the app (a different image carries a different Flyway version and possibly different SQL on the classpath); the Job spec needs `backoffLimit: 0` with `restartPolicy: Never` (a failed migration needs a human, not a second attempt that may have half-applied the first); and the `wait` must **fail the step**, so the rollout never starts. **Prove it** with `V999__bad.sql` containing `ALTER TABLE orders ADD COLUMN qty INT NOT NULL;` — which fails on existing rows — and confirm: the pipeline stops at the migration step, `kubectl get deploy shop-api` still shows the **previous** digest, and no new ReplicaSet was created. Note the Spring Boot 3.2+ launcher class is `org.springframework.boot.loader.launch.JarLauncher`; pre-3.2 it has no `.launch` segment, and getting it wrong produces a `ClassNotFoundException` that looks like a migration bug. ⭐ **Also add the shadow-schema check** ([Case 1 · targets §5.3](../scenario-2-cd-only/case-1-continuous-delivery/04-docker-and-k8s-targets.md)): a migration that applies to an empty database can still fail against a 40-million-row production table, and neither `flyway validate` nor a clean-DB test can see that.

**T9.** ⭐ **One pipeline, two ordered stages, one approval:**
```yaml
- stage: ProductionApi
  dependsOn: Staging
  jobs:
    - deployment: api
      environment: $(prodEnv)
      strategy:
        runOnce:
          deploy:
            steps:
              - template: templates/deploy-digest.yml
                parameters: { namespace: shop-production, service: shop-api,
                              serviceConnection: sc-shop-production,
                              imageRef: $[ ...apiRef ], runMigration: true }
- stage: ProductionUi
  dependsOn: ProductionApi          # ⭐⭐ backend FIRST, enforced by the graph
  jobs:
    - deployment: ui
      environment: $(prodEnv)       # ⭐ SAME environment → ONE approval
      strategy:
        runOnce:
          deploy:
            steps:
              - template: templates/deploy-digest.yml
                parameters: { namespace: shop-production, service: shop-ui,
                              serviceConnection: sc-shop-production,
                              imageRef: $[ ...uiRef ], runMigration: false,
                              probe: '/', port: 80 }
          on:
            failure:
              steps:
                - bash: |
                    echo "##vso[task.logissue type=error]🚨 FE failed — rolling back BOTH"
                    kubectl -n shop-production set image deploy/shop-ui shop-ui="$(prevUi)"
                    kubectl -n shop-production set image deploy/shop-api shop-api="$(prevApi)"
                  displayName: '🚨 roll back the PAIR'
```
**Three decisions, and each has a reason:** ⭐ **backend first**, because the backend must serve *both* the old and the new frontend at every instant — cached frontends persist for as long as browser cache dictates, a duration you do not control, so the reverse order guarantees a window where old frontends call endpoints the new backend removed. ⭐ **One approval, not two**, because the human authorised *this release* and the pair is the release; two prompts invite approving the FE after the BE failed, which produces exactly the half-promoted state. ⭐ **Roll back both on FE failure**, because new-UI-against-old-API is a state nobody tested and is worse than either consistent state — and this is only safe if the backend's migrations are expand/contract, which is prerequisite 5 in [`../scenario-2-cd-only/00-delivery-vs-deployment.md`](../scenario-2-cd-only/00-delivery-vs-deployment.md). **Verify the pair, not each half:** add a step that curls the FE, asserts `config.js` contains the production `API_URL`, and curls the BE through the Service — the end-to-end path neither half's smoke test covers.

**T10.** ⭐⭐ **What it CAN do:** read everything in the CI job's scope — source, the `$(Pipeline.Workspace)` caches, any secret in a variable group linked to the pipeline, and the federated token for `sc-shop-ci`. With that token it can **push an image to ACR** (`AcrPush` is necessarily present in CI). It can make arbitrary outbound calls — exfiltrating source, or fetching a second stage. It can tamper with the build output, so the published artifact does not correspond to the commit. It can poison the `Cache@2` Maven cache at `$(Pipeline.Workspace)/.m2`, **persisting into future runs** — the most under-appreciated capability, because it outlives the single compromised build. And it can sign with the CI cosign key if that key is fetched from Key Vault during the build (§4 does exactly that, and then `shred`s it).

**What it CANNOT do:** deploy. `sc-shop-ci` has **no role assignment on the AKS cluster** (§6/T1), so `az aks get-credentials` fails. It cannot reach dev, staging or production clusters, cannot approve anything, and cannot read the production environment's variable groups. And — the check that matters most — **it cannot get a bad image into production by itself**: CD independently runs `cosign verify` against the published public key, `preDeploy` asserts staging ran that exact digest, and in `delivery` mode a human reviews the staging report before promotion.

⭐ **The realistic damage is a poisoned-but-validly-signed artifact that CD will happily deploy** — because the signature is genuine (it *was* signed by your CI) and in `deployment` mode no human looks. The mitigations are dependency pinning, `dependency-check` as a gate (already present), Dependabot/PR review, SBOM diffing, and ⭐ **shortening the window during which the cosign key is on the agent** — fetch it immediately before signing and `shred` it immediately after, as §4 does.

**The two configuration mistakes that would give it production access:**
1. ⛔ **Merging CI and CD into one pipeline.** The moment the job that runs `mvn verify` can name `sc-shop-production`, the Maven dependency has AKS cluster-admin in its environment and `kubectl` on the agent. The distance from `mvn verify` to `kubectl set image` is one HTTP call.
2. ⛔ **Granting `sc-shop-ci` an AKS role "so CI can run smoke tests".** This is the *plausible* mistake — it looks like a reasonable request, and it collapses the entire asymmetry. The correct answer is to smoke-test in **CD** against dev, or to give CI a **separate, dev-only, read-mostly** connection whose scope is the dev namespace and nothing else.

Two near-misses with the same outcome: **missing `azuredevops_environment_resource_authorization`** (§7) — without it any job in the project can name the production connection, so the environment boundary is decorative; and a **self-hosted agent shared between CI and CD** — the credential isolation is per-connection, but the *machine* is not, and a persistent agent keeps files, caches, Docker images and env between jobs. ⭐ **The general principle: the security boundary in Azure DevOps is RBAC plus environment authorisation, not YAML discipline — so "one pipeline or two?" is a security question, and the answer is two.**

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish_Kumar_Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn: https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260
🔗 GitHub: https://github.com/3558Bhk

*The boundary is RBAC and environment authorisation — not a comment in your YAML.*

</div>
