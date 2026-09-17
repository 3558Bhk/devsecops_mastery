# 🔷 CASE 2 · CONTINUOUS DEPLOYMENT WITH AZURE DEVOPS
### Chained pipelines via `resources: pipelines`, **deployment gates** instead of approvals, a canary stage, and `on: failure` rollback.

> **Scenario:** CI ran ([Scenario 1 · Azure DevOps](../../scenario-1-ci-only/02-azure-devops-ci.md)) and published `shopacr.azurecr.io/<svc>@sha256:…` with the digest in an artifact. **This pipeline never builds and never waits for a human.**
>
> **Tool version anchors:** Azure DevOps multi-stage YAML · `resources.pipelines` **trigger** · Environments **deployment gates** (Azure Monitor, REST, Query Work Items) · `KubernetesManifest@2` / `Kubernetes@1` · `AzureCLI@2` with Workload Identity Federation · ⭐ AKS-native **Deployment Strategy** task · Argo Rollouts for progressive delivery.

---

## 📇 Contents

| § | What |
|---|---|
| [1](#1---what-changes-from-case-1) | ⭐ What changes from Case 1 — approvals out, gates in |
| [2](#2---the-trigger-resources-pipelines) | ⭐ The trigger: `resources: pipelines` — and why it beats `workflow_run`-style hacks |
| [3](#3---deployment-gates--the-six-checks-that-replace-the-human) | ⭐⭐ Deployment gates — the six checks that replace the human |
| [4](#4---the-cd-pipeline--checkout-go-full-yaml) | ⭐ The CD pipeline — `checkout` (Go), full YAML |
| [5](#5---aks-native-deployment-strategies) | ⭐ AKS-native deployment strategies — the `AzureDevOps` rollout task |
| [6](#6---automatic-rollback-and-halting-further-releases) | ⭐⭐ Automatic rollback (`on: failure`) and halting further releases |
| [7](#7--the-freeze-check-as-a-rest-gate) | The freeze check as a REST gate |
| [8](#8--credentials) | Credentials — AcrPull-only, per-environment service connections |
| [9](#9--classic-release-pipelines-in-case-2) | Classic release pipelines in Case 2 — deployment gates |
| [10](#10--per-app-shape) | Per app shape |
| [11](#11--️-run-it-and-prove-it) | ▶️ Run it and prove it |
| [12](#12--troubleshooting) | Troubleshooting |
| [13](#13---tasks--answers-at-the-end) | Tasks and answers — **answers at the END** |

---

## 1 · ⭐ What changes from Case 1

Compare with [`../case-1-continuous-delivery/02-azure-devops-delivery.md`](../case-1-continuous-delivery/02-azure-devops-delivery.md).

| # | Case 1 (Delivery) | Case 2 (Deployment) |
|---|---|---|
| 1 | `trigger: none` — manual only | ⭐ `resources.pipelines.trigger` — **automatic** on CI success |
| 2 | **Approval** check on `shop-production` | ⛔ **no Approval**; ⭐ **Azure Monitor / REST / Query Work Items** gates instead |
| 3 | Staging verification is a **published report** | ⭐ Staging verification is a **gate** — a failed step fails the stage |
| 4 | No canary | ⭐ canary stage, or the AKS-native `deployK8s` **strategy: canary** |
| 5 | Rollback is a separate pipeline | ⭐ Rollback is `on: failure:` steps **in this pipeline** |
| 6 | Nothing stops the next release | ⭐⭐ a REST gate reads a **halt flag** and blocks further runs |

```yaml
# ⭐ THE WHOLE DIFFERENCE IN FOUR LINES
resources:
  pipelines:
    - pipeline: ci-checkout          # the source
      source: CI · checkout          # ⭐ the CI pipeline's NAME
      trigger:
        branches: [main]
        # ⭐ fires only on SUCCESS — `trigger` implies succeeded builds
```

---

## 2 · ⭐ The trigger: `resources: pipelines`

```yaml
trigger: none            # ⛔ no git trigger — this pipeline consumes an ARTIFACT
pr: none

resources:
  pipelines:
    - pipeline: ci-checkout                 # ⭐ the alias used downstream
      source: CI · checkout                 # ⭐ the CI pipeline's NAME in the project
      project: shop                         # if it lives in another project
      trigger:
        branches:
          include: [main]                   # ⭐ only main
        stages:                             # ⭐ optional: only certain CI stages
          - Publish
```

**Then read the artifact from the triggering run:**

```yaml
steps:
  - download: ci-checkout                    # ⭐ the ALIAS, not the name
    artifact: image-digest
    displayName: '⭐ Download the digest CI published'

  - bash: |
      set -euo pipefail
      RAW=$(cat '$(Pipeline.Workspace)/ci-checkout/image-digest/digest.txt')
      [[ "$RAW" =~ ^[a-z0-9._/-]+@sha256:[0-9a-f]{64}$ ]] \
        || { echo "##vso[task.logissue type=error]not a digest: $RAW"; exit 1; }
      echo "##vso[task.setvariable variable=imageRef;isOutput=true]$RAW"
      echo "##vso[build.addbuildtag]${RAW#*@}"
      # ⭐ the triggering build's id, for provenance
      echo "CI build: $(resources.pipeline.ci-checkout.runID)"
      echo "CI commit: $(resources.pipeline.ci-checkout.sourceCommit)"
    name: parsed
```

| Property | ⭐ Why it matters |
|---|---|
| `trigger` fires only on **succeeded** builds | no `conclusion == 'success'` check needed — unlike GitHub's `workflow_run` |
| `download: <alias>` gets **exactly** that run's artifact | ⭐ no "find the latest build" race |
| `resources.pipeline.<alias>.runID` / `.sourceCommit` | provenance, for free |
| ⭐ `trigger.stages` | promote only when the CI stage that publishes actually ran |

---

## 3 · ⭐⭐ Deployment gates — the six checks that replace the human

Azure DevOps' **Approvals and checks** panel holds both approvals (Case 1) and automated checks (Case 2). **Remove the Approval, keep and add the rest.**

| Gate | Replaces the human's… | Configuration |
|---|---|---|
| ⭐ **Azure Monitor** | *"are the metrics normal?"* | an Application Insights / Log Analytics query + a threshold. **Runs before AND after** if you configure two |
| ⭐ **REST** | *"is now a good time?"* | any HTTP endpoint + a JSON-path success condition. ⭐ your freeze calendar, your halt flag, your change window |
| **Query Work Items** | *"is this authorised?"* | requires a linked work item in a given state |
| ⭐ **Exclusive Lock** | *"is anyone else shipping?"* | one deployment per environment at a time |
| **Branch Control** | *"is this from main?"* | only `refs/heads/main` may deploy |
| **Business Hours** | *"is anyone awake?"* | ⭐ in Case 2 this is a **policy**, not a convenience |
| ⛔ **Approval** | — | **REMOVE IT.** Leaving it makes this Case 1 |

```bash
# ⭐ add an Azure Monitor gate to shop-production
ENV_ID=$(az pipelines environment show --organization $ORG --project shop \
         --name shop-production --query id -o tsv)

az rest --method POST --url \
 "$ORG/shop/_apis/distributedtask/environments/$ENV_ID/providers/checks?api-version=7.1" \
 --headers "Content-Type=application/json" --in-file - <<'EOF'
{
  "type": {"name": "AzureMonitor"},
  "timeout": 30,
  "settings": {
    "executionOrder": 1,
    "inputs": {
      "connectionType": "azureMonitor",
      "query": "requests | where name startswith 'POST /checkout' | where timestamp > ago(15m) | summarize err=countif(resultCode>=500)*1.0/count()",
      "threshold": "0.01",
      "alertState": "Fired"
    },
    "retryInterval": 300,
    "maxRetryCount": 6
  }
}
EOF
```

⭐⭐ **The retry semantics are the powerful part:** `retryInterval: 300, maxRetryCount: 6` means the gate **re-evaluates every 5 minutes for 30 minutes** before failing. That turns a momentary metric spike into a wait rather than a false alarm — the automated equivalent of the human who says "let me watch it for a bit".

```bash
# ⭐⭐ REMOVE the approval — this is what makes it Case 2
az rest --method GET --url \
 "$ORG/shop/_apis/distributedtask/environments/$ENV_ID/providers/checks?api-version=7.1" \
 --query 'value[] | {id, type: type.name}' -o table
az rest --method DELETE --url \
 "$ORG/shop/_apis/distributedtask/environments/$ENV_ID/providers/checks/<APPROVAL_CHECK_ID>?api-version=7.1"
```

---

## 4 · ⭐ The CD pipeline — `checkout` (Go), full YAML

`pipelines/cd-checkout.yml`

```yaml
# ═══════════════════════════════════════════════════════════════════════
#  WHAT : CD ONLY, Case 2 — CONTINUOUS DEPLOYMENT for `checkout` (Go).
#         CI success → dev → staging → ⭐ canary → production.
#         NO approval anywhere. Automatic rollback. Halts on failure.
#  WHY  : stateless Go service with /readyz and enough traffic for a
#         10-minute canary to be statistically meaningful → all five
#         prerequisites hold.
#  TARGET: AKS shop-aks · namespaces shop-{dev,staging,production}.
# ═══════════════════════════════════════════════════════════════════════
trigger: none
pr: none

resources:
  pipelines:
    - pipeline: ci-checkout
      source: CI · checkout
      trigger:
        branches: { include: [main] }     # ⭐ only on a SUCCESSFUL main build

pool: { vmImage: ubuntu-latest }

variables:
  service:        checkout
  acr:            shopacr.azurecr.io
  aksName:        shop-aks
  aksRg:          rg-shop
  canaryWeight:   10
  canaryMinutes:  10
  kubectlVersion: '1.34.0'
  # ⭐⭐ the halt flag, read by the REST gate (§6.2)
  haltUrl:        'https://cd-state.shop.internal/halted/checkout'

stages:
  # ═══════════════════════════════════════════════════════════════════
  #  STAGE 0 · RESOLVE + PROVENANCE
  # ═══════════════════════════════════════════════════════════════════
  - stage: Resolve
    displayName: '0 · Resolve digest'
    jobs:
      - job: resolve
        steps:
          - download: ci-checkout
            artifact: image-digest
            displayName: '⭐ Download the digest CI published'
          - bash: |
              set -euo pipefail
              RAW=$(cat '$(Pipeline.Workspace)/ci-checkout/image-digest/digest.txt')
              [[ "$RAW" =~ ^[a-z0-9._/-]+@sha256:[0-9a-f]{64}$ ]] \
                || { echo "##vso[task.logissue type=error]⛔ not a digest: $RAW"; exit 1; }
              echo "✅ $RAW  (CI build $(resources.pipeline.ci-checkout.runID), commit $(resources.pipeline.ci-checkout.sourceCommit))"
              echo "##vso[task.setvariable variable=imageRef;isOutput=true]$RAW"
              echo "##vso[task.setvariable variable=digest;isOutput=true]${RAW#*@}"
              echo "##vso[build.addbuildtag]${RAW#*@}"
            name: parsed
          - task: AzureCLI@2
            displayName: 'G1 · Verify provenance (cosign)'
            inputs:
              azureSubscription: 'sc-shop-readonly'
              scriptType: bash
              scriptLocation: inlineScript
              inlineScript: |
                set -euo pipefail
                az acr login --name $(acr)
                cosign verify --key /tmp/cosign.pub "$(parsed.digest)" >/dev/null \
                  || { echo "##vso[task.logissue type=error]⛔ provenance failed"; exit 1; }

  # ═══════════════════════════════════════════════════════════════════
  #  STAGE 1 · DEV — automatic, GATE
  # ═══════════════════════════════════════════════════════════════════
  - stage: Dev
    displayName: '1 · dev + verify'
    dependsOn: Resolve
    jobs:
      - deployment: dev
        environment: shop-dev                  # ⭐ no checks → automatic
        pool: { vmImage: ubuntu-latest }
        strategy:
          runOnce:
            deploy:
              steps:
                - checkout: self
                - template: templates/deploy-and-verify.yml
                  parameters:
                    namespace: shop-dev
                    imageRef: $[ stageDependencies.Resolve.resolve.outputs['parsed.imageRef'] ]
                    probe: '/readyz'
                    port: 9091
                    timeout: 300

  # ═══════════════════════════════════════════════════════════════════
  #  STAGE 2 · STAGING — automatic, GATE, and it records the baseline
  # ═══════════════════════════════════════════════════════════════════
  - stage: Staging
    displayName: '2 · staging + verify'
    dependsOn: Dev
    jobs:
      - deployment: staging
        environment: shop-staging
        pool: { vmImage: ubuntu-latest }
        strategy:
          runOnce:
            deploy:
              steps:
                - checkout: self
                - template: templates/deploy-and-verify.yml
                  parameters:
                    namespace: shop-staging
                    imageRef: $[ stageDependencies.Resolve.resolve.outputs['parsed.imageRef'] ]
                    probe: '/readyz'
                    port: 9091
                    timeout: 300
                # ── ⭐ CAPTURE THE BASELINE FOR THE CANARY ANALYSIS ────
                - task: AzureCLI@2
                  displayName: 'Record the pre-deploy baseline'
                  inputs:
                    azureSubscription: 'sc-shop-staging'
                    scriptType: bash
                    scriptLocation: inlineScript
                    inlineScript: |
                      set -euo pipefail
                      az aks get-credentials -n $(aksName) -g $(aksRg) --overwrite-existing
                      ./scripts/metrics.sh shop-staging 15m > baseline.json
                      BASE=$(base64 -w0 baseline.json)
                      echo "##vso[task.setvariable variable=baseline;isOutput=true]$BASE"
            on:
              failure:
                steps:
                  - bash: |
                      echo "##vso[task.logissue type=error]⛔ staging verification FAILED — stopping"
                      kubectl -n shop-staging rollout undo deploy/$(service)
                    displayName: '🚨 undo staging'

  # ═══════════════════════════════════════════════════════════════════
  #  STAGE 3 · ⭐ CANARY
  # ═══════════════════════════════════════════════════════════════════
  - stage: Canary
    displayName: '3 · canary $(canaryWeight)% + analyse'
    dependsOn: Staging
    jobs:
      - deployment: canary
        environment: shop-canary          # ⭐ Azure Monitor + REST gates (§3)
        pool: { vmImage: ubuntu-latest }
        strategy:
          # ⭐⭐ THE AKS-NATIVE CANARY STRATEGY — Azure DevOps drives
          #   Argo Rollouts / SMI for you (§5)
          canary:
            canaryDeploymentId: canary-checkout
            iterations: 5                 # ⭐ 5 iterations = 5 analysis rounds
            increment: [ $(canaryWeight) ]
            routeTraffic:
              steps:
                - task: AzureCLI@2
                  displayName: 'Start the canary'
                  inputs:
                    azureSubscription: 'sc-shop-production'
                    scriptType: bash
                    scriptLocation: inlineScript
                    inlineScript: |
                      set -euo pipefail
                      az aks get-credentials -n $(aksName) -g $(aksRg) --overwrite-existing
                      REF='$[ stageDependencies.Resolve.resolve.outputs["parsed.imageRef"] ]'
                      kubectl argo rollouts set image $(service) $(service)="$REF" \
                        -n shop-production
                      kubectl argo rollouts get rollout $(service) -n shop-production --watch --timeout 180 || true
            postRouteTraffic:
              steps: []
            # ── ⭐ G3 · THE ANALYSIS, REPEATED `iterations` TIMES ──────
            on:
              success:
                steps:
                  - task: AzureCLI@2
                    displayName: '⭐ Analyse canary vs stable (baseline-aware)'
                    inputs:
                      azureSubscription: 'sc-shop-production'
                      scriptType: bash
                      scriptLocation: inlineScript
                      inlineScript: |
                        set -euo pipefail
                        az aks get-credentials -n $(aksName) -g $(aksRg) --overwrite-existing
                        echo '$[ stageDependencies.Staging.staging.outputs["deploy.baseline"] ]' \
                          | base64 -d > baseline.json
                        ./scripts/analyse-canary.sh \
                          --namespace shop-production \
                          --window 2m \
                          --baseline baseline.json \
                          --max-err-ratio-delta 0.005 \
                          --max-p99-ratio 1.5 \
                          --min-requests 40 \
                          | tee analysis.json
                        V=$(jq -r .verdict analysis.json)
                        echo "##vso[task.setvariable variable=verdict]$V"
                        # ⭐⭐ FAIL CLOSED: INCONCLUSIVE is treated as FAIL
                        [ "$V" = "PASS" ] || {
                          echo "##vso[task.logissue type=error]⛔ canary verdict: $V"; exit 1; }
              failure:
                steps:
                  - bash: |
                      echo "##vso[task.logissue type=error]⛔ canary FAILED — aborting"
                      kubectl argo rollouts abort $(service) -n shop-production
                      curl -fsS -X POST "$(SLACK_WEBHOOK)" -H 'content-type: application/json' \
                        -d "{\"text\":\"🚨 $(service) canary ABORTED — verdict $(verdict)\"}"
                    displayName: '🚨 abort the canary'
            # ── promote to 100% after all iterations pass ─────────────
            promote:
              steps:
                - bash: |
                    kubectl argo rollouts promote $(service) -n shop-production --full=true
                    kubectl argo rollouts get rollout $(service) -n shop-production --watch --timeout 600
                  displayName: '⭐ Promote the canary to 100%'

  # ═══════════════════════════════════════════════════════════════════
  #  STAGE 4 · PRODUCTION — automatic, post-verify
  # ═══════════════════════════════════════════════════════════════════
  - stage: Production
    displayName: '4 · production + verify'
    dependsOn: Canary
    jobs:
      - deployment: prod
        environment: shop-production      # ⭐⭐ NO APPROVAL — gates only (§3)
        pool: { vmImage: ubuntu-latest }
        strategy:
          runOnce:
            deploy:
              steps:
                - checkout: self
                - template: templates/deploy-and-verify.yml
                  parameters:
                    namespace: shop-production
                    imageRef: $[ stageDependencies.Resolve.resolve.outputs['parsed.imageRef'] ]
                    probe: '/readyz'
                    port: 9091
                    timeout: 600
                    postVerifyMinutes: 10      # ⭐ G5 · watch after promotion
            on:
              failure:
                steps:
                  - task: AzureCLI@2
                    displayName: '🚨 AUTOMATIC ROLLBACK'
                    inputs:
                      azureSubscription: 'sc-shop-production'
                      scriptType: bash
                      scriptLocation: inlineScript
                      inlineScript: |
                        set -euo pipefail
                        az aks get-credentials -n $(aksName) -g $(aksRg) --overwrite-existing
                        kubectl argo rollouts undo $(service) -n shop-production \
                          || kubectl -n shop-production rollout undo deploy/$(service)
                        kubectl -n shop-production rollout status deploy/$(service) --timeout=300s || true
                        # ⭐⭐ SET THE HALT FLAG — stop the next release
                        curl -fsS -X PUT "$(haltUrl)" -H "authorization: Bearer $(HALT_TOKEN)" \
                          -d '{"service":"$(service)","build":"$(Build.BuildId)","reason":"auto-rollback"}'
                        curl -fsS -X POST "$(PAGERDUTY_URL)" -H 'content-type: application/json' -d @- <<EOF
                        {"routing_key":"$(PD_ROUTING_KEY)","event_action":"trigger",
                         "payload":{"summary":"🚨 $(service) CD auto-rolled back — promotions HALTED",
                                    "severity":"critical","source":"azure-devops",
                                    "custom_details":{"build":"$(System.CollectionUri)$(System.TeamProject)/_build/results?buildId=$(Build.BuildId)"}}}
                        EOF
                    env:
                      HALT_TOKEN: $(halt-token)

### ── the template both cases share ──────────────────────────────────
# templates/deploy-and-verify.yml
```

### 4.1 `templates/deploy-and-verify.yml`

```yaml
parameters:
  - { name: namespace, type: string }
  - { name: imageRef,  type: string }
  - { name: probe,     type: string, default: '/readyz' }
  - { name: port,      type: number, default: 8080 }
  - { name: timeout,   type: number, default: 300 }
  - { name: postVerifyMinutes, type: number, default: 0 }

steps:
  - task: KubectlInstaller@1
    inputs: { kubectlVersion: $(kubectlVersion) }

  - task: AzureCLI@2
    displayName: 'Authenticate to AKS (Workload Identity Federation)'
    inputs:
      azureSubscription: 'sc-shop-${{ parameters.namespace }}'
      scriptType: bash
      scriptLocation: inlineScript
      inlineScript: az aks get-credentials -n $(aksName) -g $(aksRg) --overwrite-existing

  # ── ⭐ DEPLOY + READ BACK ───────────────────────────────────────────
  - bash: |
      set -euo pipefail
      NS='${{ parameters.namespace }}'; SVC=$(service); REF='${{ parameters.imageRef }}'
      PREV=$(kubectl -n $NS get deploy $SVC \
             -o jsonpath="{.spec.template.spec.containers[?(@.name=='$SVC')].image}")
      echo "📌 previous: $PREV"
      echo "##vso[task.setvariable variable=prevImage]$PREV"
      if [ "$PREV" = "$REF" ]; then echo "ℹ️ already running $REF — no-op"; exit 0; fi
      kubectl -n $NS set image deploy/$SVC $SVC="$REF"
      if ! kubectl -n $NS rollout status deploy/$SVC --timeout=${{ parameters.timeout }}s; then
        echo "##vso[task.logissue type=error]⛔ rollout did not converge — undoing"
        kubectl -n $NS set image deploy/$SVC $SVC="$PREV"
        kubectl -n $NS rollout status deploy/$SVC --timeout=300s || true
        exit 1
      fi
      # ⭐⭐ READ IT BACK. A deploy tool's exit code is not proof of what runs.
      NOW=$(kubectl -n $NS get deploy $SVC \
            -o jsonpath="{.spec.template.spec.containers[?(@.name=='$SVC')].image}")
      [ "$NOW" = "$REF" ] || { echo "##vso[task.logissue type=error]⛔ running $NOW, wanted $REF"; exit 1; }
      echo "✅ confirmed: $NOW"
    displayName: '⭐ Deploy the digest and read it back'

  # ── ⭐ G2 · SMOKE FROM INSIDE THE CLUSTER ───────────────────────────
  - bash: |
      set -euo pipefail
      NS='${{ parameters.namespace }}'; SVC=$(service)
      kubectl -n $NS run smoke-$RANDOM --rm -i --restart=Never \
        --image=curlimages/curl:8.17.0 -- \
        curl -fsS "http://$SVC.$NS.svc.cluster.local:${{ parameters.port }}${{ parameters.probe }}"
      # ⭐ from INSIDE: tests the Service selector and endpoints, which an
      #   external curl through the ingress cannot isolate.
    displayName: '⭐ Smoke from inside the cluster'

  # ── ⭐ G5 · POST-DEPLOY WATCH (production only) ─────────────────────
  - ${{ if gt(parameters.postVerifyMinutes, 0) }}:
    - bash: |
        set -euo pipefail
        END=$(( $(date +%s) + ${{ parameters.postVerifyMinutes }} * 60 ))
        FAILS=0
        while [ "$(date +%s)" -lt "$END" ]; do
          ERR=$(./scripts/err-ratio.sh shop-production $(service) 5m)
          if (( $(echo "$ERR > 0.01" | bc -l) )); then FAILS=$((FAILS+1)); fi
          [ "$FAILS" -ge 3 ] && { echo "##vso[task.logissue type=error]⛔ regression detected"; exit 1; }
          sleep 60
        done
        echo "✅ stable for ${{ parameters.postVerifyMinutes }} minutes"
      displayName: '⭐ Watch production metrics'
```

---

## 5 · ⭐ AKS-native deployment strategies

Azure DevOps has **built-in** progressive delivery — the `canary` / `rolling` / `blueGreen` strategies on a `deployment:` job.

```yaml
strategy:
  canary:
    increments: [10, 25, 50]        # ⭐ traffic percentages, in order
    preDeploy:
      steps: [ ... ]                # runs once, before the first increment
    deploy:
      steps: [ ... ]                # runs once per increment
    routeTraffic:
      steps: [ ... ]                # ⭐ shift traffic to this increment
    postRouteTraffic:
      steps: [ ... ]                # ⭐⭐ runs after EACH increment — the soak
    on:
      success: { steps: [ ... ] }   # promote
      failure: { steps: [ ... ] }   # ⭐ rollback
```

| Strategy | Mechanism | ⭐ Use when |
|---|---|---|
| `rolling` | `kubectl rollout` — pods replaced gradually | ⭐ the default; no traffic-splitting infrastructure needed |
| `canary` | ⭐ **Argo Rollouts** or **SMI** TrafficSplit | you have Argo Rollouts installed and want metric-driven analysis |
| `blueGreen` | two full Deployments + a Service/SMI switch | ⭐ for stateful-ish services where a partial fleet is dangerous |

| Requirement | Detail |
|---|---|
| ⭐ Argo Rollouts installed for `canary` | `kubectl argo rollouts version` — otherwise the strategy fails |
| The `deployment:` job must target an **environment of type Kubernetes** | ⛔ a generic environment will not do |
| A **Kubernetes service connection** authorised to that environment | §8 |
| `postRouteTraffic` is where the soak goes | ⭐ this is the Case 2 analysis point |

⭐ **Honest recommendation:** for a learning or small estate, drive **Argo Rollouts directly** with `kubectl argo rollouts` in plain `bash:` steps (§4 stage 3). You get full control, you can read the analysis yourself, and it is portable to any other CI tool. The native strategy is nicer when you want Azure DevOps to own the sequencing.

---

## 6 · ⭐⭐ Automatic rollback and halting further releases

### 6.1 Rollback — `on: failure:` is the mechanism

| Placement | ⭐ Why |
|---|---|
| `strategy.runOnce.deploy.on.failure.steps` | ⭐ runs **with the deployment's context and credentials** — a separate stage would need to re-authenticate |
| `strategy.canary.on.failure.steps` | the canary equivalent — `argo rollouts abort` |
| A separate `Rollback` stage with `condition: failed()` | ⛔ weaker: it may not inherit the environment's service connection |

```
⭐ THE ROLLBACK LADDER — fastest first
   1. argo rollouts abort      ← seconds. Stable pods never went away.
   2. argo rollouts undo       ← ~30 s
   3. set image to prevImage   ← ~60 s, and UNAMBIGUOUS (§4.1 records it)
   4. rollout undo             ← ⛔ ambiguous after two failures
```

### 6.2 ⭐⭐ Halting further releases — a REST gate

Case 2's worst failure is a **loop**: bad commit → canary fails → rollback → page → next commit → repeat.

```bash
# ── the halt flag is a tiny HTTP endpoint, and the GATE reads it ───────
az rest --method POST --url \
 "$ORG/shop/_apis/distributedtask/environments/$ENV_ID/providers/checks?api-version=7.1" \
 --headers "Content-Type=application/json" --in-file - <<'EOF'
{
  "type": {"name": "REST"},
  "timeout": 10,
  "settings": {
    "executionOrder": 0,
    "inputs": {
      "connectionType": "connectedServiceName",
      "serviceConnection": "sc-shop-readonly",
      "method": "GET",
      "url": "https://cd-state.shop.internal/halted/checkout",
      "headers": "{}",
      "waitForCompletion": "false",
      "successCriteria": "$.halted == false",
      "retryInterval": 60,
      "maxRetryCount": 1
    }
  }
}
EOF
```

| Rule | Why |
|---|---|
| ⭐ `executionOrder: 0` | the halt check runs **before** everything else |
| ⭐ `successCriteria: "$.halted == false"` | the gate passes only when NOT halted |
| `maxRetryCount: 1` | ⛔ do not retry a halt — it is a decision, not a transient |
| The flag is **set by the rollback**, cleared by a **human or a scheduled job** | ⭐⭐ never cleared by the job that set it |
| The halt produces a **gate failure**, not a red build storm | ⭐ and the gate message says exactly why |

```
⭐ WITHOUT A BREAKER:  5 commits → 5 canaries → 5 rollbacks → 5 pages 🔔🔔🔔🔔🔔
⭐ WITH A BREAKER:     1 commit → 1 canary → 1 rollback → 1 page 🔔
                       the next 4 runs are blocked at the REST gate
```

---

## 7 · The freeze check as a REST gate

⭐ **The same REST gate mechanism, pointed at a calendar service.** Two implementations:

| Option | How | ⭐ Verdict |
|---|---|---|
| A tiny HTTP service reading `freezes.yaml` from the repo | `GET /frozen?at=<now>` → `{"frozen": false}` | ✅ testable, versioned, one implementation for all three tools |
| A **Business Hours** check | built in, no code | ✅ for the simple "09:00–17:00 weekdays" case |
| `condition:` in the YAML | `and(succeeded(), not(frozen()))` | ⛔ you have to implement `frozen()` yourself, and it is per-pipeline |

```yaml
# ⭐ Business Hours check — the 5-minute version of a freeze calendar
#    (REST API, same shape as §6.2)
{ "type": {"name": "BusinessHours"},
  "timeout": 1440,
  "settings": {
    "executionOrder": 0,
    "inputs": {
      "startDays": "Monday,Tuesday,Wednesday,Thursday,Friday",
      "startTime": "09:00",
      "endDays":   "Monday,Tuesday,Wednesday,Thursday,Friday",
      "endTime":   "17:00",
      "timezone":  "India Standard Time"
    }
  } }
```

⭐⭐ **The Case 2 nuance:** a Business Hours check with `timeout: 1440` **waits** rather than fails — the deployment queues until the window opens. That is exactly right for Case 2: a commit merged at 21:00 deploys at 09:00 the next morning, automatically, with no human. In Case 1 the human would simply not have approved it yet.

---

## 8 · Credentials

| Need | ⭐ Mechanism |
|---|---|
| Pull the image | `AcrPull` on the CD service principal — **no push role** |
| Reach the cluster | ⭐ a **Kubernetes service connection** per environment, authorised to that environment |
| Read metrics | an Azure Monitor / Log Analytics connection, **read-only** |
| Set the halt flag | a `Secret text`-style variable group scoped to production |
| Notify | Slack/Teams webhook in a **production-only** variable group |

```
sc-shop-readonly      → AcrPull + metrics read   → Resolve, gates
sc-shop-shop-dev      → dev AKS                  → environment shop-dev
sc-shop-staging       → staging AKS              → environment shop-staging
sc-shop-production    → ⭐ production AKS, authorised ONLY to shop-production
sc-shop-canary        → ⭐ production AKS, authorised ONLY to shop-canary
```

⭐ **Why a separate connection for `shop-canary`:** the canary stage runs in the production cluster but should not be able to touch the stable Deployment. Give it a **Kubernetes service connection backed by a ServiceAccount with a narrow RBAC role** — `get/patch` on `rollouts` only, no `delete` on `deployments`. Then a bug in the canary stage cannot delete production.

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: { name: cd-canary, namespace: shop-production }
rules:
  - apiGroups: ["argoproj.io"]
    resources: ["rollouts", "rollouts/scale", "rollouts/status"]
    verbs: ["get","list","watch","patch","update"]
  - apiGroups: [""]
    resources: ["pods","pods/log","events"]
    verbs: ["get","list","watch"]
  # ⛔ NO deployments, NO delete. The canary stage cannot destroy production.
```

---

## 9 · Classic release pipelines in Case 2

| Concept | Classic equivalent |
|---|---|
| `resources.pipelines.trigger` | ⭐ **"Enable continuous deployment"** on the artifact source — the flag Case 1 leaves **off** |
| Deployment gates | **Gates** on the stage (before/after) — Azure Monitor, Azure Function, REST, Query Work Items |
| Canary | ⛔ not built in — use a separate "Canary" stage with a small deployment, or move to YAML |
| Automatic rollback | ⛔ **weak** — "redeploy a previous release" is manual. ⭐ This is the main reason to leave classic for Case 2 |
| Halt flag | a gate with a REST check |

```
BUILD (CI) ──continuous deployment──▶ RELEASE (CD)
   ┌─ Dev ──────┐   ┌─ Staging ──┐   ┌─ Production ──────────────────┐
   │ automatic  │──▶│ automatic  │──▶│ GATES (before):               │
   └────────────┘   └────────────┘   │   REST · halt flag            │
                                     │   Business Hours              │
                                     │   Azure Monitor (err < 1%)    │
                                     │ ⛔ NO APPROVAL                │
                                     │ → deploy → GATES (after) →    │
                                     │   ⛔ no automatic rollback    │
                                     └───────────────────────────────┘
```

⭐ **The honest verdict:** classic release pipelines can do Case 2's *gates* well, but **not** its *rollback*. Since automatic rollback is mandatory for Case 2 ([`../00-delivery-vs-deployment.md`](../00-delivery-vs-deployment.md) prerequisite 1), **classic is not a suitable platform for Case 2.** Move to multi-stage YAML — or keep classic for Case 1, where a human is the rollback mechanism.

---

## 10 · Per app shape

| Shape | What changes |
|---|---|
| 🔵 **FE only** (`shop-ui`) | ⭐ **the best Case 2 candidate.** No migration, probe `/`, rollback trivial. Consider `strategy: rolling` rather than canary — a frontend has no per-request traffic split without an ingress that does it |
| 🟢 **BE stateless** (`checkout`, `payment-mock`) | ⭐ this file. Canary works because traffic can be split by request |
| 🟢 **BE stateful** (`shop-api`) | 🔒 **Case 1.** The migration Job is the irreversible step |
| 🟢 **BE worker** (`order-worker`) | 🔒 Case 1. ⛔ Cannot canary by traffic weight — a queue consumer either consumes or does not |
| 🟡 **FE + BE** (P10) | ⭐ **split**: FE → Case 2, BE → Case 1, two pipelines, two environments |
| 🟠 **Polyglot** (P11/P12) | one CD pipeline per service, each with its own halt flag; a release-train pipeline that halts if **any** member is halted |

```yaml
# 🟠 per-service halt flags — one bad service must not freeze the estate
variables:
  haltUrl: 'https://cd-state.shop.internal/halted/$(service)'
# ⭐ and the release-train pipeline checks ALL of them:
#   GET /halted/any → {"halted": true, "services": ["order-worker"]}
```

---

## 11 · ▶️ Run it and prove it

```bash
ORG=https://dev.azure.com/yourorg

# 1 · ⛔ there is NO Approval check on production
ENV_ID=$(az pipelines environment show --organization $ORG --project shop \
         --name shop-production --query id -o tsv)
az rest --method GET --url \
 "$ORG/shop/_apis/distributedtask/environments/$ENV_ID/providers/checks?api-version=7.1" \
 --query 'value[].type.name' -o table
# ⭐ expect: REST, BusinessHours, AzureMonitor, ExclusiveLock — and NO Approval

# 2 · the trigger is automatic
grep -A5 'resources:' pipelines/cd-checkout.yml | grep -q 'trigger:' && echo "✅ auto"

# 3 · NO build step
grep -nE 'Go@|go build|Maven@|npm ci' pipelines/cd-checkout.yml && echo "⛔ builds" || echo "✅ no build"

# 4 · automatic rollback exists in THIS pipeline
grep -n 'on:' -A3 pipelines/cd-checkout.yml | grep -q 'failure:' && echo "✅ rollback"

# 5 · the halt flag is set on rollback
grep -n 'haltUrl' pipelines/cd-checkout.yml && echo "✅ circuit breaker"

# 6 · ⭐⭐ THE DRILL — a deliberately bad digest, end to end
#    build checkout with /readyz returning 500, push to main, and confirm:
#      Resolve ✅ → Dev ⛔ fails at rollout status, undoes itself
#    then make it SUBTLE (ready OK, 20% of requests 500) and confirm:
#      Canary analysis → verdict FAIL → `argo rollouts abort` → ONE page
#      → the REST gate blocks the next run
az pipelines run list --name "CD · checkout" --top 5 \
  --query '[].{id:id,result:result}' -o table

# 7 · the breaker really blocks
curl -fsS https://cd-state.shop.internal/halted/checkout | jq
# ⭐ {"halted": true, ...}  → the next run must be BLOCKED at the gate

# 8 · clear it and confirm CD resumes
curl -fsS -X DELETE https://cd-state.shop.internal/halted/checkout -H "authorization: Bearer $T"

# 9 · what is running, one command
az aks get-credentials -n shop-aks -g rg-shop --overwrite-existing
kubectl -n shop-production get rollout checkout -o jsonpath='{.status.stableRS}{"\n"}'
```

---

## 12 · Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| CD never triggers | the CI pipeline's **name** in `source:` does not match exactly (spaces, `·`) | `az pipelines list --query '[].name'` |
| ⛔ CD triggers on failed CI | a `trigger:` **git** trigger is present alongside `resources` | `trigger: none` |
| `download: ci-checkout` finds nothing | the alias differs from the artifact name, or CI did not `publish:` | print `$(Pipeline.Workspace)` and `ls -R` |
| `stageDependencies` output empty | the producing step lacks `name:` | add `name:` — the ref is `outputs['name.var']` |
| ⛔ The stage still waits for approval | an **Approval** check was left on the environment | §3 — delete it |
| The Azure Monitor gate always fails | the query returns no rows, or the threshold comparison direction is wrong | test the query in Log Analytics first; ⭐ a gate on an empty result set is a gate that never passes |
| The REST gate times out | `waitForCompletion` mismatched, or the endpoint needs auth the connection does not carry | `waitForCompletion: "false"` for a synchronous call |
| `strategy: canary` errors immediately | ⛔ Argo Rollouts is not installed, or the environment is not of type **Kubernetes** | §5 |
| Business Hours blocks everything | the timezone name must be a **Windows** timezone id (`India Standard Time`), not an IANA one | §7 |
| ⛔ Paged repeatedly | no halt flag, or the REST gate has `executionOrder` after the deploy | §6.2 — `executionOrder: 0` |
| Rollback fails — old image gone | ACR **retention policy** untagged/deleted it | ⭐ retain the last N digests; pin by digest so untagging does not delete |
| `on: failure` did not run | it was placed on a `job:` instead of a `deployment:` strategy | §6.1 |

---

<a name="tasks--answers"></a>
## 13 · ⭐ TASKS — answers at the END

| # | Task |
|---|---|
| **T1** | Convert the Case 1 Azure DevOps pipeline into Case 2 — list exactly what you add and what you **delete** |
| **T2** | Wire `resources.pipelines.trigger` and download the digest artifact from the triggering run |
| **T3** | Replace the Approval check with an Azure Monitor gate and a Business Hours gate via the REST API |
| **T4** | Implement the canary with the native `strategy: canary` and `iterations`, and put the analysis in `postRouteTraffic` |
| **T5** | Put automatic rollback in `on: failure:` and explain why that placement beats a separate `Rollback` stage |
| **T6** | Implement the halt flag as a REST gate with `executionOrder: 0`, and prove five bad commits produce one page |
| **T7** | Create the narrow `cd-canary` RBAC Role so the canary stage cannot delete production Deployments |
| **T8** | Explain why classic release pipelines are unsuitable for Case 2, and what specifically is missing |
| **T9** | Decide Case 1 vs Case 2 per service for P10 (React+Java) and write the two pipeline/environment pairs |
| **T10** | ⭐⭐ Your Azure Monitor gate passes during the day and fails every night, with no code changes. Diagnose, and give the two fixes |

---

# ✅ ANSWERS

**T1.** **Delete:** the **Approval** check on `shop-production` (§3 — via `az rest --method DELETE` on the check id); `trigger: none` stays but is no longer the *only* trigger. **Add:** `resources.pipelines.trigger` on the CI pipeline (§2); a **canary** stage with `strategy: canary` and the analysis in `postRouteTraffic`/`on: success` (§4); `on: failure:` rollback steps inside each deployment strategy (§6.1); the **halt-flag REST gate** with `executionOrder: 0` (§6.2); **Azure Monitor** and **Business Hours** gates (§3, §7); and `postVerifyMinutes` on the production template so G5 watches after promotion. ⭐ **Change (easy to miss):** the staging verification stops being a *published report* and becomes a *gate* — remove any `continueOnError` and let a failure fail the stage, because in Case 2 there is no human downstream to interpret a warning. **Keep:** Exclusive Lock, Branch Control, AcrPull-only credentials, and the read-back assertion.

**T2.** §2. `trigger: none`, then `resources.pipelines` with `pipeline: ci-checkout` (the **alias**), `source: CI · checkout` (the CI pipeline's exact **name**, including the middle dot — ⭐ a rename silently breaks the trigger and nothing errors), and `trigger.branches.include: [main]`. Download with `download: ci-checkout` + `artifact: image-digest`, read from `$(Pipeline.Workspace)/ci-checkout/image-digest/digest.txt`, validate the digest shape with the regex, and emit `##vso[task.setvariable variable=imageRef;isOutput=true]`. ⭐ **Two properties make this better than GitHub's `workflow_run`:** `trigger` fires only on **succeeded** builds (no `conclusion == 'success'` check needed), and `download:` fetches **exactly that run's** artifact rather than "the latest", which removes the race. `resources.pipeline.ci-checkout.runID` and `.sourceCommit` give you provenance for free, for the audit record.

**T3.** §3. Resolve the environment's numeric `id`, then `az rest --method POST` to `…/providers/checks?api-version=7.1` twice: an **AzureMonitor** check with the Log Analytics query, `threshold`, `retryInterval: 300` and `maxRetryCount: 6`; and a **BusinessHours** check with `startDays`/`startTime`/`endDays`/`endTime` and a **Windows** timezone id (`India Standard Time`, not `Asia/Kolkata`). Then `DELETE` the existing Approval check by id. ⭐ **The retry semantics are the powerful part:** `retryInterval: 300, maxRetryCount: 6` makes the gate re-evaluate every five minutes for half an hour before failing — a momentary metric spike becomes a *wait* rather than a false alarm, which is the automated equivalent of the human who says "let me watch it for a bit". **Verify** with the GET in §11 check 1: the list must contain REST, BusinessHours, AzureMonitor, ExclusiveLock — and **no Approval**.

**T4.** §4 stage 3. `strategy: canary:` with `iterations: 5`, `increment: [10]`, `routeTraffic.steps` starting the canary via `kubectl argo rollouts set image`, and the analysis in **`on: success`** of each iteration. ⭐ **Why `postRouteTraffic`/`on: success` and not `deploy`:** `deploy` runs once per increment and is where you *apply* the change; the analysis must run **after traffic has actually been routed and has had time to produce data**, which is what `postRouteTraffic` is for. Two requirements that are easy to miss: **Argo Rollouts must be installed** in the cluster, and the environment must be of **type Kubernetes** with an authorised Kubernetes service connection — a generic environment makes `strategy: canary` fail immediately. **Fail closed:** treat `INCONCLUSIVE` as `FAIL` (`[ "$V" = "PASS" ] || exit 1`), because a canary that promotes on insufficient data is a canary in name only.

**T5.** §6.1. Place rollback in `strategy.runOnce.deploy.on.failure.steps` (and `strategy.canary.on.failure.steps` for the canary, where it runs `argo rollouts abort`). ⭐ **Why this beats a separate `Rollback` stage with `condition: failed()`:** the `on:` hooks execute **inside the deployment job**, so they inherit the deployment's **environment** and therefore its **service connection** and scoped variable groups. A separate stage must re-declare the environment, re-authenticate, and re-resolve `stageDependencies` outputs — three more chances to be wrong at exactly the moment you are least able to debug. It also runs regardless of which step failed, whereas a stage-level `condition:` can be defeated by a `dependsOn` that itself was skipped. **The rollback ladder, fastest first:** `argo rollouts abort` (seconds — the stable pods never went away, so this is just a traffic-weight change) → `argo rollouts undo` (~30 s) → `set image` to the recorded `prevImage` (~60 s, and unambiguous) → `rollout undo` (⛔ ambiguous after two failures, because "previous" is then the *first* bad revision).

**T6.** §6.2. Set: in the rollback's `on: failure` steps, `curl -X PUT $haltUrl -d '{"service":"checkout","build":"$(Build.BuildId)","reason":"auto-rollback"}'`. Read: a **REST** check on `shop-production` with `method: GET`, `url: $haltUrl`, `successCriteria: "$.halted == false"`, ⭐ `executionOrder: 0` so it evaluates before every other gate, and `maxRetryCount: 1` (⛔ do not retry a halt — it is a decision, not a transient). **Proving one page rather than five:** push five bad commits. Run 1 fails the canary, aborts, sets the halt flag, and fires one PagerDuty event. Runs 2–5 are **blocked at the REST gate** — the deployment never starts, so no canary, no rollback, no page. ⭐ Four rules: the flag is **never cleared by the job that set it**; it is cleared by a human or a scheduled job conditioned on "no failures in 4h"; a gate block produces a **clear gate message** rather than a build failure, so nobody mistakes policy for breakage; and the flag endpoint is per-service (`/halted/$(service)`) so one bad service does not freeze the whole estate (§10).

**T7.** §8. A `Role` in `shop-production` granting `get/list/watch/patch/update` on `argoproj.io/rollouts` (plus `rollouts/scale` and `rollouts/status`), and `get/list/watch` on `pods`, `pods/log`, `events` — with **no** `deployments` and **no** `delete` verb. Bind it to a ServiceAccount, and back the `sc-shop-canary` service connection with that account's token. ⭐ **Why it matters specifically for Case 2:** the canary stage is the part of the pipeline that runs *most often* and is *least reviewed* — it contains analysis scripts, `jq` expressions and shell arithmetic. A bug there (a malformed `kubectl delete`, a variable that expands empty into `kubectl -n shop-production delete deploy/`) should be **impossible**, not merely unlikely. Give the stage the minimum RBAC and the worst case becomes "the canary fails", not "production is deleted". The stable Deployment is then only reachable from `sc-shop-production`, which is authorised to `shop-production` and used only by the promotion stage.

**T8.** ⛔ **Classic release pipelines cannot do Case 2, for one specific reason: they have no automatic rollback.** §9. What classic *can* do well: **continuous deployment triggering** on the artifact source (the exact flag Case 1 leaves off), and **deployment gates** before and after a stage — Azure Monitor, Azure Function, REST, Query Work Items. So the *gates* half of Case 2 is available. What is missing is the *recovery* half: the only rollback mechanism is **"redeploy a previous release"**, which is a **manual** action in the UI. Canary is also not built in — you would hand-roll a small "Canary" stage, which means you own the traffic splitting, the analysis and the abort yourself. ⭐ **Since automatic rollback is a mandatory prerequisite for Case 2** ([`../00-delivery-vs-deployment.md`](../00-delivery-vs-deployment.md) §6, prerequisite 1 — and the reason Case 2 without it is *strictly worse* than Case 1), classic is unsuitable. **The correct recommendation:** move to multi-stage YAML for any service you want in Case 2; keep classic for Case 1, where a human *is* the rollback mechanism and its weaker automation is acceptable.

**T9.** ⭐ **Split P10 into two pipelines and two environments** — the single most valuable decision in this file:
- **`shop-ui` → 🤖 Case 2.** Pipeline `cd-shop-ui`, environment `shop-production-ui` with REST (halt) + Business Hours gates, **no Approval**. Strategy: **`rolling`**, not `canary` — ⭐ a frontend serves static files, so splitting traffic by request gives you no per-user signal unless the ingress does session-affinity splitting; `rolling` with a fast rollback is the right shape. Verify: `GET /` == 200, `config.js` contains the production `API_URL`, and `index.html` is served `no-cache`.
- **`shop-api` → 🔒 Case 1.** Pipeline `cd-shop-api`, environment `shop-production-api` with **Approval** retained, because prerequisite 5 (expand/contract migrations) is not yet true and the schema is the irreversible part.
- **Ordering between them:** `cd-shop-ui` triggers on `resources.pipelines` pointing at **`cd-shop-api`** rather than at CI, so the frontend only promotes after the backend is healthy in production. ⭐ **Backend first** — the backend must serve both the old and the new frontend at every instant, and the reverse order guarantees a window where cached frontends call endpoints that do not exist.
- **Why split rather than one pipeline:** a single policy for both forces the frontend to inherit the backend's risk, which is how a static-file app ends up needing a change-approval board — and it forces the backend to wait on frontend cadence. Two pipelines, two environments, two halt flags.

**T10.** ⭐⭐ **Diagnosis:** the gate is comparing against something that varies diurnally, and the two most likely causes are **(a)** a **fixed threshold on a rate that has a daily shape**, and **(b)** **low overnight traffic making the denominator tiny**.

Concretely: a query like `summarize err=countif(resultCode>=500)*1.0/count()` over `ago(15m)` is stable in the day because `count()` is large. At night `count()` may be a handful of requests, so **one** background 500 — a health-check probe hitting a retired endpoint, a scanner, a cron job with a stale URL — produces a 5% or 20% error rate and breaches a 1% threshold. The code did not change; the **statistics** did. A second contributor: if the threshold is on an *absolute count* rather than a ratio, the day breaches and the night passes, which is the mirror image — so check which direction your gate uses.

**Fix 1 — ⭐ make the gate sample-aware (the real fix).** Add a minimum-volume condition so the gate only evaluates when there is signal:

```
let r = requests
  | where timestamp > ago(15m)
  | summarize total=count(), errs=countif(resultCode >= 500);
r | extend ratio = iff(total >= 200, todouble(errs)/total, 0.0)
  | project ratio
```

⭐ `iff(total >= 200, …, 0.0)` means: **below 200 requests the gate reports 0 and passes.** That is *fail-open on insufficient data*, which is the right policy for a **pre-deploy** health gate (do not block a release because it is quiet) and the wrong policy for a **canary** analysis gate (where §5 of the GitHub file fails *closed*). Knowing which is which is the actual skill.

**Fix 2 — compare against a baseline, not a constant.** Query the same 15-minute window over the **previous 7 days at the same hour**, and alert on the *ratio to baseline* rather than an absolute. This handles both directions: Monday-morning volume and 3 a.m. quiet both compare correctly against their own historical equivalent. In Azure DevOps this is either a more sophisticated Log Analytics query in the Azure Monitor gate, or ⭐ a **REST gate** pointing at your own `analyse-canary.sh`-style service — which is the more maintainable option, because the comparison logic then lives in git with tests rather than in a query string inside a check configuration.

**The third thing to check, because it is the embarrassing one:** `retryInterval` and `maxRetryCount`. If the gate is configured with `maxRetryCount: 0`, a single transient spike fails it immediately; with retries it waits and re-evaluates, which absorbs most overnight noise without any query change at all.

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish_Kumar_Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn: https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260
🔗 GitHub: https://github.com/3558Bhk

*Delete the Approval, keep the lock — and put the rollback where the credentials already are.*

</div>
