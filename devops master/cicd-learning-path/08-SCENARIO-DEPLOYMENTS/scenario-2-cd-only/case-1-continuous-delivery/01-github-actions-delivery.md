# 🐙 CASE 1 · CONTINUOUS DELIVERY WITH GITHUB ACTIONS
### A `workflow_dispatch` CD pipeline that takes a digest, deploys dev → staging, stops at a **required-reviewer** environment gate, and records who approved.

> **Scenario:** CI ran elsewhere ([Scenario 1 · GitHub Actions](../../scenario-1-ci-only/01-github-actions-ci.md)) and published `ghcr.io/3558bhk/<svc>@sha256:…`. **This pipeline never builds.**
>
> **Tool version anchors:** `actions/checkout@v7` · `azure/setup-kubectl@v4` · `azure/k8s-set-context@v4` · GitHub **Environments** (protection rules: required reviewers, wait timer, deployment branches).

---

## 📇 Contents

| § | What |
|---|---|
| [1](#1---the-mechanism-environments) | ⭐ The mechanism: **Environments** — the only real approval gate GitHub has |
| [2](#2--setting-up-the-environment) | Setting up the environment (UI + API + IaC) |
| [3](#3---the-cd-workflow--shop-api-full-file) | ⭐ The CD workflow — `shop-api`, full file |
| [4](#4---what-the-approver-sees--the-part-that-stops-rubber-stamping) | ⭐⭐ What the approver sees — the part that stops rubber-stamping |
| [5](#5--the-digest-input-and-validating-it) | The digest input, and validating it |
| [6](#6---credentials--why-cd-needs-different-ones-than-ci) | ⭐ Credentials — why CD needs different ones than CI |
| [7](#7---rollback-as-a-first-class-action) | ⭐ Rollback as a first-class action |
| [8](#8--the-audit-record) | The audit record — deployment history and how to query it |
| [9](#9--per-app-shape) | Per app shape: FE-only, BE-only, FE+BE, polyglot |
| [10](#10--️-run-it-and-prove-it--the-case-1-acceptance-checks) | ▶️ Run it and prove it — the Case 1 acceptance checks |
| [11](#11--troubleshooting) | Troubleshooting |
| [12](#12---tasks--answers-at-the-end) | Tasks and answers — **answers at the END** |

---

## 1 · ⭐ The mechanism: Environments

GitHub Actions has exactly one native approval mechanism, and it is **Environments**. Everything else is a hack.

```yaml
jobs:
  deploy-production:
    environment: production     # ⭐⭐ THIS LINE IS THE GATE
    runs-on: ubuntu-latest
    steps: [ ... ]
```

**What `environment: production` does:**

| Effect | Detail |
|---|---|
| ⭐ **Pauses the job** until a configured reviewer approves | the job shows as *Waiting* — the runner is **not** consumed while waiting |
| **Records the approver** | visible in the run's deployment log and via the API |
| **Scopes secrets** | `secrets.KUBECONFIG_PROD` can exist *only* in `production` — ⭐ dev jobs cannot read it |
| **Restricts branches** | "Deployment branches" can limit which refs may deploy |
| **Creates a deployment** | appears under **Deployments** on the repo front page, with history |
| **Can add a wait timer** | e.g. 30 min — useful for a "canary soak" without a real canary |

⭐⭐ **The secret-scoping effect is the security story.** In Scenario 1 you proved CI has *no* cluster credential. Here, the production kubeconfig exists **only** inside the `production` environment, so a job that does not declare `environment: production` **cannot read it** — even with `secrets` context access, even from a compromised dependency.

---

## 2 · Setting up the environment

### 2.1 UI

**Repo → Settings → Environments → New environment → `production`**

| Setting | ⭐ Recommended value | Why |
|---|---|---|
| **Required reviewers** | a **team** with ≥ 3 members | one person = a bottleneck and a single point of bypass |
| **Wait timer** | `0` | a timer is not a gate; do not confuse the two |
| **Deployment branches** | `main` + `refs/tags/v*` | stops a feature branch deploying to production |
| **Environment secrets** | `KUBECONFIG_PROD`, `ACR_SP_PASSWORD`, `SLACK_WEBHOOK` | ⭐ production-only secrets live here |
| **Environment variables** | `NAMESPACE=shop-production`, `CLUSTER=prod-eu` | non-secret config |

Repeat for `staging` (no reviewers) and `dev` (no reviewers).

### 2.2 ⭐ API / scriptable — because "click it in the UI" does not survive a repo rebuild

```bash
# get the team's numeric id first
TEAM_ID=$(gh api orgs/ORG/teams/platform-eng --jq .id)

gh api -X PUT repos/ORG/shop/environments/production \
  -f wait_timer=0 \
  -F "preventive_branch_rules[]"=refs/heads/main \
  -f 'reviewers[][type]=Team' -F "reviewers[][id]=$TEAM_ID"

# ⭐ environment secrets — production-scoped
gh secret set KUBECONFIG_PROD --env production --body "$(base64 -w0 prod-kubeconfig.yaml)"

# verify what you created
gh api repos/ORG/shop/environments/production --jq '{name,protection_rules}'
```

### 2.3 Terraform (if the org is IaC)

```hcl
resource "github_repository_environment" "production" {
  environment = "production"
  repository  = "shop"

  prevent_deployment_branch_rules { branch_pattern = ["refs/heads/main"] }

  reviewers {
    teams = [var.platform_team_id]     # ⭐ a TEAM, not a user
  }
  # ⭐ `wait_timer` deliberately omitted — a timer is not an approval.
}
```

---

## 3 · ⭐ The CD workflow — `shop-api`, full file

`.github/workflows/cd-shop-api.yml`

```yaml
# ═══════════════════════════════════════════════════════════════════════
#  WHAT : CD ONLY for shop-api. Takes an image DIGEST, deploys
#         dev → staging → ⛔ human gate → production.
#  WHY  : Case 1 Continuous Delivery — Scenario 2.
#         ⭐ NO build, NO test, NO image publish. If it can build, it is
#            not CD, and the digest contract from Scenario 1 is gone.
#  TARGET: Kubernetes namespace shop-{dev,staging,production}.
# ═══════════════════════════════════════════════════════════════════════
name: CD · shop-api (delivery)

# ── TRIGGER ────────────────────────────────────────────────────────────
# ⭐ workflow_dispatch ONLY. There is deliberately no `push:` trigger —
#   an automatic trigger on main would make this Case 2 without Case 2's
#   safety machinery (see ../00-delivery-vs-deployment.md).
on:
  workflow_dispatch:
    inputs:
      image:
        description: 'Full image reference WITH digest, e.g. ghcr.io/3558bhk/shop-api@sha256:41ab…'
        required: true
        type: string
      target:
        description: 'How far to promote'
        required: true
        type: choice
        default: staging
        options: [dev, staging, production]
      reason:
        description: 'Why are we shipping this? (goes in the approval prompt)'
        required: true
        type: string
  # ⭐ OPTIONAL: auto-deploy dev+staging when CI publishes.
  #   Production is NEVER in this path — the human gate is only reachable
  #   via workflow_dispatch. This is "pattern 1" from ../00 §7.
  workflow_run:
    workflows: ['CI · shop-api']
    types: [completed]
    branches: [main]

concurrency:
  # ⭐⭐ one CD run per environment at a time. Two people approving two
  #   releases simultaneously is how you ship a digest nobody reviewed.
  group: cd-shop-api-${{ inputs.target || 'auto' }}
  cancel-in-progress: false          # ⛔ NEVER cancel a deployment mid-flight

permissions:
  contents: read                     # ⭐ least privilege. CD needs no write.

env:
  SERVICE: shop-api
  NAMESPACE_PREFIX: shop

jobs:
  # ═════════════════════════════════════════════════════════════════════
  #  JOB 0 · RESOLVE THE ARTIFACT
  # ═════════════════════════════════════════════════════════════════════
  resolve:
    name: 0 · Resolve and validate the digest
    runs-on: ubuntu-latest
    outputs:
      image:   ${{ steps.resolve.outputs.image }}
      digest:  ${{ steps.resolve.outputs.digest }}
      source:  ${{ steps.resolve.outputs.source }}
      scanned: ${{ steps.resolve.outputs.scanned }}
    steps:
      - uses: actions/checkout@v7

      - name: Resolve the digest
        id: resolve
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          set -euo pipefail
          RAW="${{ inputs.image }}"

          # ── auto path: pull the digest CI published as an artifact ─────
          if [ -z "$RAW" ]; then
            RUN_ID=$(gh run list --workflow ci-shop-api.yml --branch main \
                     --status success --limit 1 --json databaseId --jq '.[0].databaseId')
            gh run download "$RUN_ID" -n image-digest -D /tmp/dl
            RAW=$(cat /tmp/dl/digest.txt)
            echo "ℹ️  auto-resolved from CI run $RUN_ID"
          fi

          # ── ⭐ VALIDATE THE SHAPE. Never deploy what you did not verify. ─
          if ! echo "$RAW" | grep -Eq '^[a-z0-9._/-]+@sha256:[0-9a-f]{64}$'; then
            echo "::error::'$RAW' is not a digest reference. CD refuses tags."
            exit 1
          fi
          IMAGE="${RAW%@*}"
          DIGEST="${RAW#*@}"

          # ── ⭐ PROVE THE ARTIFACT EXISTS AND IS SIGNED ──────────────────
          # CD's job is not to build; it IS to refuse to deploy something
          # that did not come out of a green CI run.
          cosign verify \
            --certificate-oidc-issuer=https://token.actions.githubusercontent.com \
            --certificate-identity-regexp="^https://github.com/${{ github.repository }}/\.github/workflows/ci-shop-api\.yml@" \
            "${IMAGE}:${DIGEST#sha256:}" >/dev/null \
            || { echo "::error::signature verification failed"; exit 1; }

          echo "✅ verified: $IMAGE@$DIGEST"
          echo "image=$IMAGE"   >> "$GITHUB_OUTPUT"
          echo "digest=$DIGEST" >> "$GITHUB_OUTPUT"

          # the originating commit, for the approval prompt
          SRC=$(gh api "repos/${{ github.repository }}/commits?per_page=1" --jq '.[0].sha' || echo unknown)
          echo "source=$SRC" >> "$GITHUB_OUTPUT"
          echo "scanned=true" >> "$GITHUB_OUTPUT"

  # ═════════════════════════════════════════════════════════════════════
  #  JOB 1 · DEV — automatic, no gate
  # ═════════════════════════════════════════════════════════════════════
  deploy-dev:
    name: 1 · Deploy → dev
    needs: resolve
    if: contains(fromJSON('["dev","staging","production"]'), inputs.target) || inputs.target == ''
    runs-on: ubuntu-latest
    environment: dev                       # ⭐ scopes DEV secrets only
    steps:
      - uses: actions/checkout@v7

      - uses: azure/setup-kubectl@v4
        with: { version: 'v1.34.0' }       # ⭐ pin. kubectl skew costs bugs.

      - name: Point at the dev cluster
        run: |
          mkdir -p ~/.kube
          echo "${{ secrets.KUBECONFIG_DEV }}" | base64 -d > ~/.kube/config
          chmod 600 ~/.kube/config
          kubectl config use-context kind-cicd

      # ── ⭐⭐ THE DEPLOY: a digest, applied to the manifest ────────────
      - name: Deploy
        run: |
          set -euo pipefail
          REF="${{ needs.resolve.outputs.image }}@${{ needs.resolve.outputs.digest }}"
          kubectl -n shop-dev apply -f k8s/shop-api/
          kubectl -n shop-dev set image deploy/shop-api shop-api="$REF" \
                  --record=false
          # ⭐ --record=false: the change-cause annotation is deprecated and
          #   leaks the command line (which may contain secrets) into the object.

      - name: Wait for the rollout — with a deadline
        run: |
          kubectl -n shop-dev rollout status deploy/shop-api --timeout=180s \
            || { echo "::error::dev rollout failed"; \
                 kubectl -n shop-dev rollout undo deploy/shop-api; exit 1; }

      - name: Smoke
        run: |
          kubectl -n shop-dev port-forward deploy/shop-api 18080:8080 &
          PF=$!; sleep 5
          trap 'kill $PF 2>/dev/null || true' EXIT
          for i in $(seq 1 20); do
            curl -fsS http://127.0.0.1:18080/actuator/health/readiness && exit 0
            sleep 3
          done
          echo "::error::readiness never came up"; exit 1

  # ═════════════════════════════════════════════════════════════════════
  #  JOB 2 · STAGING — automatic, no gate
  # ═════════════════════════════════════════════════════════════════════
  deploy-staging:
    name: 2 · Deploy → staging
    needs: [resolve, deploy-dev]
    if: contains(fromJSON('["staging","production"]'), inputs.target) || inputs.target == ''
    runs-on: ubuntu-latest
    environment: staging
    steps:
      - uses: actions/checkout@v7
      - uses: azure/setup-kubectl@v4
        with: { version: 'v1.34.0' }
      - name: Point at staging
        run: |
          mkdir -p ~/.kube
          echo "${{ secrets.KUBECONFIG_STAGING }}" | base64 -d > ~/.kube/config
          chmod 600 ~/.kube/config
      - name: Deploy
        run: |
          set -euo pipefail
          REF="${{ needs.resolve.outputs.image }}@${{ needs.resolve.outputs.digest }}"
          kubectl -n shop-staging apply -f k8s/shop-api/
          kubectl -n shop-staging set image deploy/shop-api shop-api="$REF"
      - name: Wait
        run: kubectl -n shop-staging rollout status deploy/shop-api --timeout=300s
      # ── ⭐ THIS IS THE EVIDENCE THE APPROVER READS ──────────────────
      - name: Verify staging and publish the report
        id: verify
        run: |
          set -euo pipefail
          {
            echo "## ✅ Staging verification — ${{ needs.resolve.outputs.digest }}"
            echo ""
            echo "| check | result |"
            echo "|---|---|"
            echo "| readiness | \`$(kubectl -n shop-staging get deploy shop-api \
                   -o jsonpath='{.status.readyReplicas}/{.spec.replicas}')\` |"
            echo "| smoke /orders | \`$(curl -fsS -o /dev/null -w '%{http_code}' \
                   https://staging.shop.internal/api/v2/orders || echo FAIL)\` |"
            echo "| p99 (5m) | \`$(./scripts/p99.sh shop-staging 5m)\` |"
            echo "| 5xx ratio | \`$(./scripts/errratio.sh shop-staging 5m)\` |"
            echo "| migration | \`$(kubectl -n shop-staging get job shop-api-migrate \
                   -o jsonpath='{.status.succeeded}')\` succeeded |"
          } > staging-report.md
          echo 'report<<EOF' >> "$GITHUB_OUTPUT"
          cat staging-report.md >> "$GITHUB_OUTPUT"
          echo 'EOF' >> "$GITHUB_OUTPUT"
          cat staging-report.md >> "$GITHUB_STEP_SUMMARY"

  # ═════════════════════════════════════════════════════════════════════
  #  JOB 3 · ⛔ THE GATE — this job DOES NOTHING BUT WAIT
  # ═════════════════════════════════════════════════════════════════════
  approval:
    name: 3 · ⛔ Production approval
    needs: [resolve, deploy-staging]
    if: inputs.target == 'production'
    runs-on: ubuntu-latest
    environment: production        # ⭐⭐ THIS IS THE ENTIRE GATE
    steps:
      # ⭐ The job body is deliberately empty. `environment: production`
      #   pauses the run until a required reviewer approves. The runner is
      #   NOT held while waiting.
      - name: Record the decision
        run: |
          echo "Approved by: ${{ github.actor }} (triggering user)"
          # ⭐ the APPROVER identity is in the deployment API, not in
          #   github.actor. See §8 for how to fetch it.
          echo "Digest: ${{ needs.resolve.outputs.digest }}"
          echo "Reason: ${{ inputs.reason }}"

  # ═════════════════════════════════════════════════════════════════════
  #  JOB 4 · PRODUCTION — runs only after the gate
  # ═════════════════════════════════════════════════════════════════════
  deploy-production:
    name: 4 · Deploy → production
    needs: [resolve, approval]
    if: inputs.target == 'production'
    runs-on: ubuntu-latest
    environment: production        # ⭐ same env → same scoped secrets
    steps:
      - uses: actions/checkout@v7
      - uses: azure/setup-kubectl@v4
        with: { version: 'v1.34.0' }
      - name: Point at production
        run: |
          mkdir -p ~/.kube
          echo "${{ secrets.KUBECONFIG_PROD }}" | base64 -d > ~/.kube/config
          chmod 600 ~/.kube/config
      # ── ⭐ MIGRATION FIRST, AS A GATED JOB ───────────────────────────
      - name: Run the migration Job and wait for it
        run: |
          set -euo pipefail
          kubectl -n shop-production delete job shop-api-migrate --ignore-not-found
          kubectl -n shop-production apply -f k8s/shop-api/migration-job.yaml
          kubectl -n shop-production wait --for=condition=complete \
            job/shop-api-migrate --timeout=600s \
            || { echo "::error::migration failed — NOT rolling out"; exit 1; }
          # ⭐⭐ failing here STOPS the pipeline. The alternative — rolling
          #   out anyway — is how you get a fleet half on a new schema.
      - name: Roll out progressively
        run: |
          set -euo pipefail
          REF="${{ needs.resolve.outputs.image }}@${{ needs.resolve.outputs.digest }}"
          kubectl -n shop-production set image deploy/shop-api shop-api="$REF"
          # ⭐ watch it; do not fire and forget
          kubectl -n shop-production rollout status deploy/shop-api --timeout=600s \
            || { kubectl -n shop-production rollout undo deploy/shop-api; exit 1; }
      - name: Verify production
        run: |
          for i in $(seq 1 30); do
            CODE=$(curl -fsS -o /dev/null -w '%{http_code}' https://api.shop/actuator/health/readiness || echo 000)
            [ "$CODE" = "200" ] && { echo "✅ production healthy"; exit 0; }
            sleep 5
          done
          echo "::error::production unhealthy — rolling back"
          kubectl -n shop-production rollout undo deploy/shop-api
          exit 1
      - name: Record what is now running
        run: |
          kubectl -n shop-production get deploy shop-api \
            -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}' \
            | tee running-image.txt
          # ⭐ answers "what is in production?" in one command, forever

  # ═════════════════════════════════════════════════════════════════════
  #  JOB 5 · NOTIFY + AUDIT
  # ═════════════════════════════════════════════════════════════════════
  record:
    name: 5 · Record the release
    needs: [resolve, deploy-production]
    if: always() && inputs.target == 'production'
    runs-on: ubuntu-latest
    environment: production
    steps:
      - name: Fetch the approver and post the record
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          set -euo pipefail
          # ⭐⭐ github.actor is the person who STARTED the run.
          #   The APPROVER is in the deployment's review history.
          DEP_ID=$(gh api "repos/${{ github.repository }}/deployments?environment=production&per_page=1" --jq '.[0].id')
          APPROVER=$(gh api "repos/${{ github.repository }}/deployments/$DEP_ID/statuses?per_page=100" \
                     --jq '[.[] | select(.state=="approved")][0].creator.login // "unknown"')
          echo "🔒 Approved by: $APPROVER"
          curl -fsS -X POST "${{ secrets.SLACK_WEBHOOK }}" -H 'content-type: application/json' -d @- <<EOF
          {"text":"🚢 *shop-api → production*\nDigest: \`${{ needs.resolve.outputs.digest }}\`\nRequested: ${{ github.actor }}\nApproved: ${APPROVER}\nReason: ${{ inputs.reason }}\nRun: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}"}
          EOF
```

---

## 4 · ⭐⭐ What the approver sees — the part that stops rubber-stamping

**The problem:** GitHub's approval prompt shows the **workflow name and the run**. That is not enough to make a decision, so people click through — and the gate becomes latency with a good story.

**Three ways to fix it, in increasing order of effort:**

### 4.1 Make the run name carry the information

```yaml
# ⭐ the run title is what appears in the notification and the approval UI
run-name: >-
  🚢 shop-api → ${{ inputs.target }} ·
  ${{ inputs.reason }} ·
  by ${{ github.actor }}
```

`inputs.reason` is **required** in this workflow (§3) for exactly this reason: the approver sees *why* without opening anything.

### 4.2 Put the report in the job summary

`deploy-staging` writes a Markdown table to `$GITHUB_STEP_SUMMARY` (§3). It renders on the run page **above** the approval button. ⭐ Cost: 20 lines. Benefit: the approver sees readiness, smoke result, p99, 5xx ratio and migration status on one screen.

### 4.3 ⭐ Notify with a deep link, and make the message self-contained

```bash
curl -fsS -X POST "$SLACK_WEBHOOK" -H 'content-type: application/json' -d @- <<EOF
{"text":"⛔ *Approval needed* — shop-api → production",
 "blocks":[
  {"type":"section","fields":[
    {"type":"mrkdwn","text":"*Digest*\n\`${DIGEST:0:19}…\`"},
    {"type":"mrkdwn","text":"*Reason*\n${REASON}"},
    {"type":"mrkdwn","text":"*Changes*\n${COMMIT_RANGE}"},
    {"type":"mrkdwn","text":"*Staging*\n✅ ready 3/3 · p99 120ms · 5xx 0.00%"}]},
  {"type":"actions","elements":[
    {"type":"button","text":{"type":"plain_text","text":"Approve / Reject"},
     "url":"${RUN_URL}","style":"primary"}]}]}
EOF
```

⭐ **The rule to apply:** *the approver should be able to decide from the notification.* Digest, reason, what changed, and whether staging is healthy — all four, on the screen where they got pinged. Everything else is a detail they can dig into if something looks wrong.

---

## 5 · The digest input, and validating it

| Rule | Implementation |
|---|---|
| ⭐ Must be a digest, never a tag | `grep -Eq '^[a-z0-9._/-]+@sha256:[0-9a-f]{64}$'` then `exit 1` |
| ⭐ Must exist in the registry | `cosign verify` (or `crane digest "$IMAGE"`) — fails if absent |
| ⭐⭐ Must have come from **our** CI | `cosign verify --certificate-identity-regexp` pins the workflow path, so a hand-pushed image is rejected |
| Must not be older than the policy window | compare the signature's timestamp |
| ⭐ Must be the digest that ran in staging | record staging's digest as an output and assert equality before production |

```yaml
- name: Assert staging ran THIS digest
  run: |
    STAGED="${{ needs.deploy-staging.outputs.deployed_digest }}"
    WANT="${{ needs.resolve.outputs.digest }}"
    [ "$STAGED" = "$WANT" ] \
      || { echo "::error::staging ran $STAGED but production was asked for $WANT"; exit 1; }
    # ⭐⭐ without this check, a long wait at the gate can let someone deploy
    #   a digest that was never verified in staging. The gate's duration is
    #   the window; this assertion closes it.
```

---

## 6 · ⭐ Credentials — why CD needs different ones than CI

| | CI (Scenario 1) | CD (this file) |
|---|---|---|
| Needs to **push** images | ✅ | ❌ |
| Needs **cluster** access | ⛔ **no — that is the point** | ✅ |
| Where the secret lives | repo secrets / OIDC | ⭐ **environment** secrets |
| Blast radius if leaked | an image in your registry | ⭐ **your production cluster** |

**Three escalating options for cluster auth:**

| Option | Mechanism | Verdict |
|---|---|---|
| ⛔ A long-lived admin kubeconfig in a repo secret | base64 in `secrets.KUBECONFIG` | works, and is the most common leak in GitHub Actions. **Not acceptable for production** |
| ⭐ Environment-scoped kubeconfig | the same content, but in `environment: production` | ✅ the minimum acceptable. A dev job literally cannot read it |
| ⭐⭐ **OIDC federation** to the cloud provider | `azure/login@v2` with `client-id`/`tenant-id`/`subscription-id`, then `aks get-credentials` | ✅ **the right answer** — no stored credential at all, short-lived tokens, and the trust is expressed in the cloud provider |

```yaml
# ⭐⭐ OIDC — no kubeconfig secret exists anywhere
- uses: azure/login@v2
  with:
    client-id:      ${{ secrets.AZURE_CLIENT_ID }}       # in the ENVIRONMENT
    tenant-id:      ${{ secrets.AZURE_TENANT_ID }}
    subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
- run: az aks get-credentials -n shop-prod -g rg-shop --overwrite-existing
```

⭐ **The one-line rule:** *CI proves the artifact; CD holds the keys.* Never both in one pipeline, and never the production key outside an environment.

---

## 7 · ⭐ Rollback as a first-class action

`.github/workflows/rollback-shop-api.yml`

```yaml
name: 🚨 Rollback · shop-api
on:
  workflow_dispatch:
    inputs:
      environment:
        description: 'Which environment to roll back'
        required: true
        type: choice
        options: [dev, staging, production]
        default: production
      to:
        description: 'Digest to roll back TO (blank = the previous rollout revision)'
        required: false
        type: string

permissions: { contents: read }
concurrency:
  group: rollback-shop-api-${{ inputs.environment }}
  cancel-in-progress: false          # ⛔ never cancel a rollback

jobs:
  rollback:
    runs-on: ubuntu-latest
    # ⭐⭐ NO ENVIRONMENT GATE. A rollback must not wait for an approval.
    #   The gate is on going FORWARD, never on going BACK.
    steps:
      - uses: actions/checkout@v7
      - uses: azure/setup-kubectl@v4
        with: { version: 'v1.34.0' }
      - name: Authenticate
        run: |
          mkdir -p ~/.kube
          echo "${{ secrets[format('KUBECONFIG_{0}', inputs.environment)] }}" | base64 -d > ~/.kube/config
      - name: Roll back
        run: |
          set -euo pipefail
          NS=shop-${{ inputs.environment }}
          if [ -n "${{ inputs.to }}" ]; then
            # ⭐ to a KNOWN GOOD DIGEST — the preferred path, because you
            #   know exactly what you are going back to
            kubectl -n "$NS" set image deploy/shop-api shop-api="${{ inputs.to }}"
          else
            # ⭐ to the PREVIOUS REVISION — faster, but verify it first
            kubectl -n "$NS" rollout history deploy/shop-api
            kubectl -n "$NS" rollout undo deploy/shop-api
          fi
          kubectl -n "$NS" rollout status deploy/shop-api --timeout=300s
      - name: Confirm and shout
        run: |
          NS=shop-${{ inputs.environment }}
          kubectl -n "$NS" get deploy shop-api \
            -o jsonpath='ROLLBACK COMPLETE → {.spec.template.spec.containers[0].image}{"\n"}'
```

| Rule | Why |
|---|---|
| ⭐⭐ **No approval gate on rollback** | waiting for a human during an incident is the definition of a slow rollback |
| ⭐ Prefer an **explicit digest** over `rollout undo` | `undo` goes to "the previous revision", which after two failed deploys is not what you think |
| `concurrency.cancel-in-progress: false` | ⛔ cancelling a rollback mid-flight is the worst possible outcome |
| Keep the last N revisions | `revisionHistoryLimit: 10` in the Deployment — the default is 10, but say it explicitly |
| ⭐ Test it | a rollback you have never executed is a hypothesis |

---

## 8 · The audit record

| Question | Answer |
|---|---|
| Who **started** the release? | `github.actor` |
| ⭐ Who **approved** it? | `GET /repos/{o}/{r}/deployments/{id}/statuses` → entries with `state: approved`, `.creator.login` |
| What was deployed? | the digest, from the `resolve` job output and from `kubectl get deploy -o jsonpath` |
| When? | the deployment status `created_at` |
| Why? | `inputs.reason` — ⭐ required, so it is always present |
| Did it work? | the verify step's result, and the run conclusion |

```bash
# ⭐ the whole production release history, one command
gh api "repos/ORG/shop/deployments?environment=production&per_page=50" \
  --jq '.[] | "\(.created_at)  \(.sha[0:7])  \(.creator.login)"'

# and who approved each one
for id in $(gh api "repos/ORG/shop/deployments?environment=production&per_page=20" --jq '.[].id'); do
  gh api "repos/ORG/shop/deployments/$id/statuses" \
     --jq '[.[]|select(.state=="approved")][0] | "deploy \(.deployment_id): approved by \(.creator.login) at \(.created_at)"'
done
```

⭐ **The durable option:** have `deploy-production` commit the digest to a **manifests repo** (`k8s/production/shop-api.yaml`). Then `git log` *is* the audit trail, `git revert` *is* the rollback, and the record outlives GitHub's retention policy (90 days for logs on private repos). That is the GitOps pattern — [`../../scenario-3-ci-plus-cd/08-gitops-argocd.md`](../../scenario-3-ci-plus-cd/08-gitops-argocd.md).

---

## 9 · Per app shape

| Shape | What changes in this file |
|---|---|
| 🔵 **FE only** (`shop-ui`) | ⭐ Simpler: no migration Job, no readiness probe beyond HTTP 200. Rollback is trivial. **Consider dropping the gate entirely** → Case 2 for the frontend only |
| 🟢 **BE only** (`shop-api`) | ⭐ This file, as written — migration Job gates the rollout |
| 🟢 **BE, worker** (`order-worker`) | No HTTP smoke. Verify "connected to broker + consuming" via a metric or a heartbeat. ⭐ Drain consideration: in-flight messages |
| 🟡 **FE + BE** (P10) | ⭐⭐ **Two CD workflows, ordered:** `cd-shop-api` must succeed **before** `cd-shop-ui` starts (`workflow_run` on the API's completion). Backend first — [Scenario 1 · §4.2](../../scenario-1-ci-only/04-app-shapes-fe-be-fullstack.md) |
| 🟠 **Polyglot** (P11/P12) | One CD workflow **per service**, each with its own environment and gate; a single manifest as the input |

```yaml
# 🟡 the FE-after-BE ordering, in two lines
on:
  workflow_run:
    workflows: ['CD · shop-api (delivery)']
    types: [completed]                    # ⭐ only on SUCCESS below
jobs:
  deploy-ui:
    if: ${{ github.event.workflow_run.conclusion == 'success' }}
```

---

## 10 · ▶️ Run it and prove it — the Case 1 acceptance checks

```bash
# 1 · there is NO build step anywhere in the file
grep -nE 'docker build|mvn|npm (ci|run build)|go build|pip install' \
  .github/workflows/cd-shop-api.yml && echo "⛔ CD builds — fix it" || echo "✅ CD does not build"

# 2 · it refuses a tag
gh workflow run cd-shop-api.yml -f image=ghcr.io/3558bhk/shop-api:latest -f reason=test
sleep 10
gh run list --workflow cd-shop-api.yml --limit 1     # ⭐ must be FAILED, at `resolve`

# 3 · the gate actually stops
gh workflow run cd-shop-api.yml -f target=production \
  -f image='ghcr.io/3558bhk/shop-api@sha256:41ab…' -f reason='gate test'
gh run watch <RUN_ID>       # ⭐ must sit at "Waiting" on the approval job

# 4 · only a reviewer can approve
gh api repos/ORG/shop/environments/production --jq '.protection_rules'
# ⭐ must list required_reviewers with a TEAM of >= 3

# 5 · the approver identity is retrievable
gh api "repos/ORG/shop/deployments?environment=production&per_page=1" --jq '.[0].id'

# 6 · rollback needs no approval
grep -n 'environment:' .github/workflows/rollback-shop-api.yml \
  && echo "⛔ rollback has a gate" || echo "✅ rollback is ungated"

# 7 · ⭐ what is running in production, one command
kubectl -n shop-production get deploy shop-api \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
```

---

## 11 · Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| The run does not pause | `environment:` missing, or the environment has no required reviewers | §2 — the gate is the *environment config*, not the YAML |
| "Waiting" forever, nobody notified | ⭐ GitHub does **not** notify reviewers by default in all configurations | post the deep link yourself (§4.3) |
| The approver is `github.actor`, not the real person | ⛔ `github.actor` is who **started** the run | use the deployments API (§8) |
| `secrets.KUBECONFIG_PROD` is empty | the secret is a **repo** secret, not an **environment** secret — or the job lacks `environment: production` | §2.2 `gh secret set --env production` |
| Two runs deploy at once | no `concurrency` group | §3 — one group per target |
| `workflow_run` will not trigger | ⛔ `workflow_run` only fires for workflows on the **default branch** | the CD file must be merged to `main` before it can be triggered this way |
| The gate passes but staging ran a different digest | a long wait let a new digest in | the §5 assertion |
| `rollout undo` goes somewhere unexpected | two failed deploys — "previous" is now the first bad one | ⭐ always prefer an explicit digest (§7) |

---

<a name="tasks--answers"></a>
## 12 · ⭐ TASKS — answers at the END

| # | Task |
|---|---|
| **T1** | Create the three environments and prove that a `dev` job **cannot** read `KUBECONFIG_PROD` |
| **T2** | Make the CD workflow reject a tag and reject an image that did not come from your CI workflow |
| **T3** | Add the staging-verification report so the approver can decide without opening another page |
| **T4** | Fetch the real approver identity and post it to Slack |
| **T5** | Write the ungated rollback workflow and **drill it** |
| **T6** | Add the "staging ran this exact digest" assertion |
| **T7** | Order FE after BE for shape C, using `workflow_run` |
| **T8** | Move production auth from a kubeconfig secret to OIDC |
| **T9** | ⭐ Prove all seven Case 1 acceptance checks from §10 pass |
| **T10** | ⭐⭐ Your approval gate has become a rubber stamp — approvals take 4 seconds and nothing is read. Diagnose and fix it without adding headcount |

---

# ✅ ANSWERS

**T1.** Create `dev`, `staging`, `production` (§2.2). Put `KUBECONFIG_DEV` as a secret in `dev`, and `KUBECONFIG_PROD` **only** in `production`. Then add a job with `environment: dev` that runs `echo "${{ secrets.KUBECONFIG_PROD }}" | wc -c`. **It prints `0`.** ⭐ That is the proof, and it is the security argument for environments: the secret is not merely unused by the dev job, it is **not present in its context**, so no injection, no compromised action and no `secrets` dump can reach it. The same test with `environment: production` prints a real length.

**T2.** Two checks in the `resolve` job. **Shape:** `grep -Eq '^[a-z0-9._/-]+@sha256:[0-9a-f]{64}$'` and `exit 1` otherwise — that rejects `:latest`, `:v1.2.3` and anything else mutable. **Provenance:** `cosign verify --certificate-oidc-issuer=https://token.actions.githubusercontent.com --certificate-identity-regexp="^https://github.com/<owner>/<repo>/\.github/workflows/ci-shop-api\.yml@"` — that rejects an image that exists in your registry but was pushed by hand or by a different workflow. ⭐ Both belong in CD, not CI: CI proves the artifact is good; **CD proves the artifact is the one CI made.** Without the second check, "deploy by digest" only guarantees immutability, not provenance.

**T3.** §3's `deploy-staging` verify step: build a Markdown table (readiness `readyReplicas/replicas`, smoke HTTP code, p99, 5xx ratio, migration Job status), write it to `$GITHUB_STEP_SUMMARY` **and** to a job output. ⭐ The step summary renders on the run page above the approval button, so the approver sees it in the place they already are. Then set `run-name:` from `inputs.reason` and `github.actor` so the *notification itself* carries the why (§4.1). Together those two changes are the whole fix — no new tooling, ~30 lines.

**T4.** ⛔ Not `github.actor` — that is who **started** the run. The approver is in the deployment statuses: `GET /repos/{o}/{r}/deployments?environment=production&per_page=1` for the id, then `GET /deployments/{id}/statuses`, filter `state == "approved"`, take `[0].creator.login` (§3 job 5, §8). Post digest + requester + approver + reason + a permalink to the run. ⭐ Including the **requester and the approver separately** matters: they are frequently different people, and an audit record that conflates them cannot answer "who authorised this?".

**T5.** §7. The three design decisions: **no `environment:`** on the rollback job (a gate on the way *back* is a gate on your own recovery); `concurrency.cancel-in-progress: false` (never cancel a rollback); and an **explicit digest input** preferred over `rollout undo`, because after two failed deploys "the previous revision" is the *first* bad one, not the last good one. **The drill:** in a quiet window, deploy a known-bad digest (an image whose readiness probe fails), then roll back to a known-good digest and time it. ⭐ If it takes more than 15 minutes, prerequisite 1 in [`../00-delivery-vs-deployment.md`](../00-delivery-vs-deployment.md) fails and Case 2 is off the table until it is fixed — and you would rather learn that on a Tuesday afternoon than during an incident.

**T6.** Have `deploy-staging` output the digest it actually applied (`kubectl get deploy -o jsonpath='{.spec.template.spec.containers[0].image}'` — read it back, do not trust the input), then in the production job assert `STAGED == WANT` and fail otherwise (§5). ⭐ **The window this closes:** the approval gate can sit for hours. If CI publishes a newer digest meanwhile and someone edits the input, or if two runs interleave, you would promote something that never ran in staging. Reading the digest *back from the cluster* rather than forwarding the input also catches a silently-failed `set image`.

**T7.** §9. `cd-shop-ui.yml` triggers on `workflow_run: workflows: ['CD · shop-api (delivery)'], types: [completed]`, and the job carries `if: github.event.workflow_run.conclusion == 'success'`. Two caveats worth knowing: ⛔ `workflow_run` only fires for workflow files **on the default branch**, so the CD file must be merged before it can trigger anything; and `types: [completed]` fires on **failure too**, which is why the `conclusion` check is mandatory. ⭐ **Why backend first:** the backend must be able to serve both the old and the new frontend at every instant. The reverse order guarantees a window where new frontends call endpoints that do not exist yet — and that window's length is controlled by browser cache, not by you.

**T8.** §6. Add a federated credential in the cloud provider whose subject claim matches `repo:ORG/shop:environment:production`, expose `AZURE_CLIENT_ID` / `TENANT_ID` / `SUBSCRIPTION_ID` as **environment** secrets, then `azure/login@v2` followed by `az aks get-credentials`. ⭐ Delete the kubeconfig secret afterwards — leaving it "just in case" means the leak path still exists. The gain: no long-lived credential is stored anywhere, tokens are short-lived, and the trust relationship is expressed and revocable in the provider rather than hidden in a base64 blob. The `environment:production` subject claim also means a **dev** job cannot mint a production token even by asking.

**T9.** Run §10's seven checks in order. Expected results: (1) the grep for build verbs finds **nothing**; (2) a `:latest` input **fails at `resolve`** with the shape error; (3) a `target=production` run **sits at Waiting** on the approval job — the runner is not consumed; (4) the protection rules list `required_reviewers` with a **team of ≥ 3**; (5) the deployments API returns an id whose statuses contain an `approved` entry with a `creator.login`; (6) the rollback workflow has **no** `environment:` key; (7) `kubectl get deploy -o jsonpath` prints a `@sha256:` reference. ⭐ Checks 1, 2, 3 and 6 are the four that define Case 1 — no build, digest-only, a real pause, and an ungated rollback.

**T10.** ⭐⭐ **Diagnosis first — 4-second approvals mean the prompt carries no information, not that the people are careless.** GitHub's native prompt shows a workflow name and a run number. Nobody can make a decision from that, so they click.

**Fix, in order of value:**
1. **Put the decision material in the notification.** `run-name:` built from `inputs.reason` + `github.actor` (§4.1); the staging verification table in `$GITHUB_STEP_SUMMARY` (§4.2); a Slack block message with digest, reason, change range and the four staging signals, plus a direct Approve/Reject button (§4.3). ⭐ The test: can the approver decide **without leaving the notification?** If not, they will not.
2. **Make `reason` a required input** and reject generic values ("release", "fix", ".") in the `resolve` job. A gate that requires a sentence produces a sentence.
3. **Show the blast radius**: which endpoints changed, whether a migration is included, whether the contract version moved. "This release contains a schema migration" changes an approval from routine to attentive.
4. **Rotate reviewers and require two** for releases containing migrations. ⭐ Single-approver rotation is what makes the gate feel like a formality.
5. **Measure it**: record `time(approved) - time(requested)` per release and publish the median. A 4-second median is visible, and visibility is what changes behaviour.
6. **If, after all that, the gate is still rubber-stamped** — that is evidence the releases genuinely are low-risk, and the honest response is ⭐ **move this service to Case 2** ([`../case-2-continuous-deployment/README.md`](../case-2-continuous-deployment/README.md)) rather than keep a control nobody exercises. An unused gate is not a control.

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish_Kumar_Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn: https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260
🔗 GitHub: https://github.com/3558Bhk

*`environment: production` is the whole gate — and the approver's screen is the whole design.*

</div>
