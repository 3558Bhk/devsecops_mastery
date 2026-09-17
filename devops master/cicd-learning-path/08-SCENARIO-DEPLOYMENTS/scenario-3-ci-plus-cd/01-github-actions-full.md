# 🐙 SCENARIO 3 · CI + CD END TO END WITH GITHUB ACTIONS
### Two chained workflows — CI publishes a digest, CD deploys it — with OIDC to GHCR *and* to the cluster, and environments scoping every secret.

> **The path:** `git push` → build → test → sign → push → **digest** → dev → staging → (🔒 gate *or* 🤖 canary) → production → verify → record.
>
> **Tool version anchors:** `actions/checkout@v7` · `actions/setup-java@v5` · `actions/setup-node@v6` · `actions/setup-go@v6` · `actions/setup-python@v6` · `docker/build-push-action@v6` · `docker/login-action@v3` · `sigstore/cosign-installer@v4` · `azure/setup-kubectl@v4` · `azure/login@v2` (OIDC) · GitHub **Environments**.

---

## 📇 Contents

| § | What |
|---|---|
| [1](#1---the-architecture-two-workflows-not-one) | ⭐⭐ The architecture: two workflows, not one — and the credential argument |
| [2](#2--the-chaining-mechanism-workflow_run) | The chaining mechanism: `workflow_run` and its four traps |
| [3](#3---oidc-everywhere--no-long-lived-secrets) | ⭐ OIDC everywhere — no long-lived secrets at all |
| [4](#4--workflow-1--ci-ci-shop-apiyml) | **Workflow 1 — CI** (`ci-shop-api.yml`), full file |
| [5](#5--workflow-2--cd-cd-shop-apiyml) | **Workflow 2 — CD** (`cd-shop-api.yml`), full file |
| [6](#6---the-artifact-contract--four-checks) | ⭐⭐ The artifact contract — four checks that prove what is running |
| [7](#7--environments--the-permission-map) | Environments — the permission map |
| [8](#8---case-1-or--case-2--the-one-flag-that-switches) | 🔒 Case 1 or 🤖 Case 2 — the one flag that switches |
| [9](#9--reusable-workflows--the-scale-answer) | Reusable workflows — the scale answer |
| [10](#10--️-run-it-end-to-end--the-full-acceptance-checks) | ▶️ Run it end to end — the full acceptance checks |
| [11](#11--troubleshooting) | Troubleshooting |
| [12](#12---tasks--answers-at-the-end) | Tasks and answers — **answers at the END** |

---

## 1 · ⭐⭐ The architecture: two workflows, not one

```
⛔ ONE WORKFLOW
   jobs: build → test → push → deploy-dev → deploy-staging → deploy-prod
   THE PROBLEM: one runner, one environment, holds
      • GHCR push credentials           (can publish an image)
      • the production kubeconfig       (can change production)
   ⭐ `npm ci` executes third-party code with BOTH in its environment.
     A malicious postinstall script has a path to production.

✅ TWO WORKFLOWS
   ci-shop-api.yml  → can PUSH, cannot DEPLOY   (no cluster secret in scope)
   cd-shop-api.yml  → can DEPLOY, cannot PUSH   (no registry write in scope)
   ⭐ the separation is enforced by SECRET SCOPE, not by a comment.
```

| Property | ⭐ How it is enforced |
|---|---|
| CI cannot deploy | the CD's cluster secret lives in an **environment** CI never declares |
| CD cannot build | CD's OIDC role is **pull-only**; a `docker push` step fails with `denied` |
| A PR cannot deploy | CD triggers on `workflow_run` from a **successful main** CI run only |
| A fork cannot publish | ⭐ the `PUSH` flag is `github.event_name == 'push'` — never true for `pull_request` |

**The digest is the contract between them.** CI's last act is to publish it; CD's first act is to validate and verify it.

```
┌─────────────── ci-shop-api.yml ────────────────┐
│ build → test → scan → sign → push               │
│                    │                            │
│         artifact: image-digest/digest.txt  ⭐ ──┼──┐
│         (also: SBOM, test results, coverage)    │  │
└─────────────────────────────────────────────────┘  │
                                                     │ the contract
┌─────────────── cd-shop-api.yml ─────────────────┐  │
│ workflow_run ← ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─┼──┘
│   ↓ gh run download <that run id> -n image-digest
│ validate shape → cosign verify → dev → staging
│   → 🔒 gate | 🤖 canary → production → read back
└─────────────────────────────────────────────────┘
```

---

## 2 · The chaining mechanism: `workflow_run`

```yaml
# cd-shop-api.yml
on:
  workflow_run:
    workflows: ['CI · shop-api']        # ⭐ the CI workflow's `name:`, NOT its file
    types: [completed]
    branches: [main]
  workflow_dispatch:                    # ⭐ kept — manual re-promotion of a digest
    inputs:
      image: { description: 'digest ref (blank = the triggering CI run)', required: false }
      target: { description: 'dev | staging | production', default: 'production', type: choice }
      reason: { description: 'why', required: true }
```

### The four traps

| # | Trap | ⭐ Fix |
|---|---|---|
| 1 | ⛔ `types: [completed]` fires on **failure** too | `if: github.event.workflow_run.conclusion == 'success'` |
| 2 | ⛔ `workflow_run` only uses workflow files **on the default branch** | merge CD to `main` before expecting it to trigger |
| 3 | ⛔ `github.ref` / `github.sha` are the **default branch's**, not the trigger's | `github.event.workflow_run.head_sha` / `.head_branch` |
| 4 | ⛔ `GITHUB_TOKEN` is restricted in a `workflow_run` context on private repos | declare `permissions:` explicitly |

```yaml
jobs:
  resolve:
    # ⭐ traps 1 and 3 handled once, at the top
    if: >
      github.event_name == 'workflow_dispatch' ||
      (github.event.workflow_run.conclusion == 'success' &&
       github.event.workflow_run.head_branch == 'main')
    runs-on: ubuntu-latest
    steps:
      - name: Download the digest CI published
        env: { GH_TOKEN: "${{ secrets.GITHUB_TOKEN }}" }
        run: |
          set -euo pipefail
          if [ -n "${{ inputs.image }}" ]; then
            RAW="${{ inputs.image }}"; SHA="manual"
          else
            RUN_ID="${{ github.event.workflow_run.id }}"
            SHA="${{ github.event.workflow_run.head_sha }}"
            gh run download "$RUN_ID" -n image-digest -D /tmp/dl
            RAW=$(cat /tmp/dl/digest.txt)
          fi
          echo "✅ CI run ${RUN_ID:-manual} commit $SHA published $RAW"
```

⭐ **Why `workflow_run` and not `repository_dispatch`:** `workflow_run` carries the triggering run's **id**, so CD downloads *exactly that run's* artifact. `repository_dispatch` requires CI to make an API call with the digest in the payload — more moving parts, and CI needs `contents: write` to send it.

---

## 3 · ⭐ OIDC everywhere — no long-lived secrets

**Four credentials are needed across the two workflows. All four can be OIDC.**

| Need | Workflow | ⛔ The secret way | ⭐ The OIDC way |
|---|---|---|---|
| Push to GHCR | CI | a PAT in `secrets.GHCR_PAT` | `permissions: packages: write` + `docker/login-action` with `GITHUB_TOKEN` |
| Sign images | CI | a `cosign` key pair in secrets | ⭐ `sigstore/cosign-installer` + **keyless** signing via OIDC |
| Pull from ACR | CD | a service-principal password | `azure/login@v2` with federated credentials |
| Reach the cluster | CD | ⛔ a base64 kubeconfig | `azure/login@v2` → `az aks get-credentials` |

```yaml
# ⭐⭐ KEYLESS COSIGN SIGNING — there is no key to leak
- uses: sigstore/cosign-installer@v4
- name: Sign
  env:
    COSIGN_YES: "true"          # ⭐ non-interactive; without it cosign prompts
  run: |
    cosign sign --yes "$IMAGE@$DIGEST"
# The certificate is minted from the runner's OIDC token and recorded in
# Rekor (a public transparency log). It says: "this image was built by
# workflow X in repo Y at commit Z." ⭐ That is STRONGER provenance than a
#   stored key, because the identity is the pipeline itself.

# ⭐ and CD verifies against that identity
- name: Verify provenance
  run: |
    cosign verify \
      --certificate-oidc-issuer=https://token.actions.githubusercontent.com \
      --certificate-identity-regexp="^https://github.com/${{ github.repository }}/\.github/workflows/ci-shop-api\.yml@refs/heads/main$" \
      "$IMAGE@$DIGEST"
    # ⭐ pinned to the WORKFLOW PATH and the BRANCH. An image pushed by hand,
    #   or by a workflow on a feature branch, FAILS verification.
```

```yaml
# ⭐ OIDC to Azure — no client secret exists anywhere
- uses: azure/login@v2
  with:
    client-id:       ${{ secrets.AZURE_CLIENT_ID }}        # in the ENVIRONMENT
    tenant-id:       ${{ secrets.AZURE_TENANT_ID }}
    subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
- run: az aks get-credentials -n shop-prod -g rg-shop --overwrite-existing
```

| ⭐ The rule | Because |
|---|---|
| **CI** gets `packages: write` and **no** cluster credential | it can publish, it cannot deploy |
| **CD** gets an Azure federated credential scoped to `environment:production` and **no** `packages: write` | it can deploy, it cannot publish |
| Neither workflow stores a long-lived secret | there is nothing to rotate and nothing to leak |

---

## 4 · Workflow 1 — CI (`ci-shop-api.yml`)

```yaml
# ═══════════════════════════════════════════════════════════════════════
#  WHAT : the CI HALF of Scenario 3 for shop-api (Java 21 / Spring Boot).
#         build → test → scan → IMAGE → scan → sign → push → ⭐ emit digest.
#  WHY  : it must be able to PUBLISH and must NOT be able to DEPLOY.
#         Enforced by having no cluster secret in scope (§7).
#  TARGET: ghcr.io/3558bhk/shop-api — and nothing else.
# ═══════════════════════════════════════════════════════════════════════
name: CI · shop-api

on:
  push:
    paths: ['apps/shop-api/**', '.github/workflows/ci-shop-api.yml']
    branches: [main]
  pull_request:
    paths: ['apps/shop-api/**']
    branches: [main]

concurrency:
  group: ci-shop-api-${{ github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}   # ⭐ safe on PRs

permissions:
  contents: read           # ⭐ least privilege by default…
  # …escalated ONLY in the job that needs it:

env:
  SERVICE: shop-api
  IMAGE:   ghcr.io/${{ github.repository_owner }}/shop-api

jobs:
  # ═════════════════════════════════════════════════════════════════════
  #  1 · BUILD + TEST (no registry access at all)
  # ═════════════════════════════════════════════════════════════════════
  test:
    name: 1 · Build and test
    runs-on: ubuntu-latest
    permissions: { contents: read }
    defaults: { run: { working-directory: apps/shop-api } }
    steps:
      - uses: actions/checkout@v7

      - uses: actions/setup-java@v5
        with:
          distribution: temurin
          java-version: '21'                 # ⭐ pinned
          cache: maven                       # ⭐ keyed on **/pom.xml

      # ── ⭐ Testcontainers needs a Docker daemon: hosted runners have one
      - name: Unit tests
        run: ./mvnw -B -ntp verify -DskipITs

      - name: ⭐ Integration tests (real Postgres 17 via Testcontainers)
        run: ./mvnw -B -ntp verify -Dit.test='*IT'
        env:
          TESTCONTAINERS_RYUK_DISABLED: 'true'    # ⭐ cleanup by agent teardown

      - name: Static analysis
        run: ./mvnw -B -ntp spotbugs:check checkstyle:check

      - name: ⭐ Dependency CVE scan
        run: ./mvnw -B -ntp org.owasp:dependency-check-maven:check
        continue-on-error: false              # ⛔ a gate, not a report

      - uses: actions/upload-artifact@v4
        if: always()
        with: { name: test-results, path: apps/shop-api/target/surefire-reports/ }

  # ═════════════════════════════════════════════════════════════════════
  #  2 · IMAGE · SCAN · SIGN · PUSH · ⭐ EMIT THE DIGEST
  # ═════════════════════════════════════════════════════════════════════
  image:
    name: 2 · Build, sign and publish the image
    needs: test
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write        # ⭐ GHCR push — ONLY here
      id-token: write        # ⭐⭐ OIDC for keyless cosign signing
    outputs:
      digest: ${{ steps.push.outputs.digest }}
    steps:
      - uses: actions/checkout@v7

      - uses: docker/setup-buildx-action@v3

      # ── ⭐⭐ THE PUSH FLAG — one variable, one decision ───────────────
      - name: Decide whether to push
        id: flags
        run: |
          # ⭐ PUSH only on a push to main. NEVER on a pull_request:
          #   a fork's PR runs with a writable GITHUB_TOKEN in some
          #   configurations, and building an image from unreviewed code
          #   into your registry is how you get a supply-chain incident.
          if [ "${{ github.event_name }}" = "push" ] && \
             [ "${{ github.ref }}" = "refs/heads/main" ]; then
            echo "push=true"  >> "$GITHUB_OUTPUT"
          else
            echo "push=false" >> "$GITHUB_OUTPUT"
            echo "ℹ️ PR or non-main — building but NOT publishing"
          fi

      - uses: docker/login-action@v3
        if: steps.flags.outputs.push == 'true'
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}   # ⭐ not a PAT

      - uses: docker/metadata-action@v5
        id: meta
        with:
          images: ${{ env.IMAGE }}
          tags: |
            type=sha,prefix=sha-                 # ⭐ sha-<commit> — traceable
            type=ref,event=branch
            type=raw,value=latest,enable={{is_default_branch}}

      - uses: docker/build-push-action@v6
        id: push
        with:
          context: apps/shop-api
          file: apps/shop-api/Dockerfile
          push: ${{ steps.flags.outputs.push == 'true' }}
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha,scope=${{ env.SERVICE }}
          cache-to:   type=gha,scope=${{ env.SERVICE }},mode=max
          provenance: mode=max                   # ⭐ SLSA provenance attestation
          sbom: true                             # ⭐ SBOM attestation

      # ── ⭐ SCAN THE IMAGE, NOT THE SOURCE ─────────────────────────────
      - name: Trivy scan the image
        if: steps.flags.outputs.push == 'true'
        uses: aquasecurity/trivy-action@0.33.1
        with:
          image-ref: ${{ env.IMAGE }}@${{ steps.push.outputs.digest }}
          format: table
          exit-code: '1'                          # ⛔ a gate
          severity: CRITICAL,HIGH
          ignore-unfixed: true                    # ⭐ no fix = not actionable

      # ── ⭐⭐ KEYLESS SIGN ─────────────────────────────────────────────
      - uses: sigstore/cosign-installer@v4
      - name: Sign the image
        if: steps.flags.outputs.push == 'true'
        env: { COSIGN_YES: 'true' }
        run: cosign sign --yes "${{ env.IMAGE }}@${{ steps.push.outputs.digest }}"

      # ── ⭐⭐ THE ARTIFACT CONTRACT — emit the digest ──────────────────
      - name: Publish the digest as the CI artifact
        if: steps.flags.outputs.push == 'true'
        run: |
          set -euo pipefail
          mkdir -p out
          printf '%s@%s\n' "${{ env.IMAGE }}" "${{ steps.push.outputs.digest }}" \
            > out/digest.txt
          # ⭐ metadata CD needs to make a decision and to build an audit trail
          cat > out/manifest.json <<EOF
          {"service":"${{ env.SERVICE}}",
           "image":"${{ env.IMAGE }}@${{ steps.push.outputs.digest }}",
           "digest":"${{ steps.push.outputs.digest }}",
           "commit":"${{ github.sha }}",
           "run":"${{ github.run_id }}",
           "actor":"${{ github.actor }}",
           "builtAt":"$(date -u +%FT%TZ)"}
          EOF
          cat out/digest.txt
      - uses: actions/upload-artifact@v4
        if: steps.flags.outputs.push == 'true'
        with:
          name: image-digest              # ⭐⭐ the name CD downloads
          path: out/
          retention-days: 90
      # ⭐ CI STOPS HERE. It has no cluster credential and no deploy step.
```

---

## 5 · Workflow 2 — CD (`cd-shop-api.yml`)

```yaml
# ═══════════════════════════════════════════════════════════════════════
#  WHAT : the CD HALF of Scenario 3 for shop-api.
#         consumes CI's digest → dev → staging → 🔒/🤖 → production.
#  WHY  : it must be able to DEPLOY and must NOT be able to PUBLISH.
#         Enforced by OIDC scoping (§3) — there is no packages: write here.
#  TARGET: AKS shop-prod · namespaces shop-{dev,staging,production}.
# ═══════════════════════════════════════════════════════════════════════
name: CD · shop-api

on:
  workflow_run:
    workflows: ['CI · shop-api']
    types: [completed]
    branches: [main]
  workflow_dispatch:
    inputs:
      image:  { description: 'digest ref (blank = the triggering CI run)', required: false }
      target: { description: 'How far to promote', default: production,
                type: choice, options: [dev, staging, production] }
      reason: { description: '⭐ why (shown to the approver)', required: true }

concurrency:
  group: cd-shop-api-${{ inputs.target || 'auto' }}
  cancel-in-progress: false        # ⛔ NEVER cancel a deployment mid-flight

permissions:
  contents: read
  id-token: write                  # ⭐ OIDC to Azure
  deployments: write               # ⭐ the deployment API record

env:
  SERVICE:   shop-api
  # ⭐⭐ THE ONE FLAG THAT CHOOSES CASE 1 OR CASE 2 (§8)
  PROD_MODE: delivery              # delivery | deployment

jobs:
  # ═══════════════ 0 · RESOLVE + VERIFY PROVENANCE ═══════════════
  resolve:
    name: 0 · Resolve the digest
    if: >
      github.event_name == 'workflow_dispatch' ||
      (github.event.workflow_run.conclusion == 'success' &&
       github.event.workflow_run.head_branch == 'main')
    runs-on: ubuntu-latest
    outputs:
      image:  ${{ steps.r.outputs.image }}
      digest: ${{ steps.r.outputs.digest }}
      sha:    ${{ steps.r.outputs.sha }}
    steps:
      - uses: actions/checkout@v7
      - uses: sigstore/cosign-installer@v4
      - name: Download, validate, verify
        id: r
        env: { GH_TOKEN: "${{ secrets.GITHUB_TOKEN }}" }
        run: |
          set -euo pipefail
          if [ -n "${{ inputs.image }}" ]; then
            RAW="${{ inputs.image }}"; SHA="manual"; RUN="manual"
          else
            RUN="${{ github.event.workflow_run.id }}"
            SHA="${{ github.event.workflow_run.head_sha }}"
            gh run download "$RUN" -n image-digest -D /tmp/dl
            RAW=$(cat /tmp/dl/digest.txt)
          fi
          # ── CHECK 1 · ⛔ REFUSE A TAG ─────────────────────────────
          [[ "$RAW" =~ ^[a-z0-9._/-]+@sha256:[0-9a-f]{64}$ ]] \
            || { echo "::error::'$RAW' is not a digest reference"; exit 1; }
          IMAGE="${RAW%@*}"; DIGEST="${RAW#*@}"
          # ── CHECK 2 · ⭐ PROVENANCE — did OUR CI on MAIN make this? ──
          cosign verify \
            --certificate-oidc-issuer=https://token.actions.githubusercontent.com \
            --certificate-identity-regexp="^https://github.com/${{ github.repository }}/\.github/workflows/ci-shop-api\.yml@refs/heads/main$" \
            "${IMAGE}@${DIGEST}" >/dev/null \
            || { echo "::error::⛔ provenance verification failed"; exit 1; }
          echo "✅ CHECK 1 + 2 passed: $RAW (CI run $RUN, commit $SHA)"
          echo "image=$IMAGE"   >> "$GITHUB_OUTPUT"
          echo "digest=$DIGEST" >> "$GITHUB_OUTPUT"
          echo "sha=$SHA"       >> "$GITHUB_OUTPUT"

  # ═══════════════ 1 · DEV — automatic ═══════════════
  dev:
    name: 1 · dev
    needs: resolve
    runs-on: ubuntu-latest
    environment: dev                     # ⭐ scopes DEV secrets only
    steps:
      - uses: actions/checkout@v7
      - uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
      - uses: azure/setup-kubectl@v4
        with: { version: 'v1.34.0' }
      - uses: ./.github/actions/deploy-digest
        with:
          namespace: shop-dev
          service:   ${{ env.SERVICE }}
          image-ref: ${{ needs.resolve.outputs.image }}@${{ needs.resolve.outputs.digest }}

  # ═══════════════ 2 · STAGING — automatic, produces the evidence ═══════════════
  staging:
    name: 2 · staging
    needs: [resolve, dev]
    runs-on: ubuntu-latest
    environment: staging
    outputs:
      deployed: ${{ steps.back.outputs.deployed }}
      report:   ${{ steps.report.outputs.md }}
    steps:
      - uses: actions/checkout@v7
      - uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
      - uses: azure/setup-kubectl@v4
        with: { version: 'v1.34.0' }
      - uses: ./.github/actions/deploy-digest
        with:
          namespace: shop-staging
          service:   ${{ env.SERVICE }}
          image-ref: ${{ needs.resolve.outputs.image }}@${{ needs.resolve.outputs.digest }}
          run-migration: 'true'
      # ── ⭐ READ THE DEPLOYED DIGEST BACK FROM THE CLUSTER ────────────
      - name: Read back what is actually running
        id: back
        run: |
          D=$(kubectl -n shop-staging get deploy ${{ env.SERVICE }} \
              -o jsonpath="{.spec.template.spec.containers[?(@.name=='${{ env.SERVICE }}')].image}")
          echo "deployed=$D" >> "$GITHUB_OUTPUT"
          echo "✅ staging is running $D"
      - name: Build the approver's evidence
        id: report
        run: |
          set -euo pipefail
          MD="| check | result |
          |---|---|
          | digest running | \`${{ steps.back.outputs.deployed }}\` |
          | ready replicas | \`$(kubectl -n shop-staging get deploy ${{ env.SERVICE }} -o jsonpath='{.status.readyReplicas}/{.spec.replicas}')\` |
          | migration job | \`$(kubectl -n shop-staging get job ${{ env.SERVICE }}-migrate -o jsonpath='{.status.succeeded}' 2>/dev/null || echo n/a)\` |
          | source commit | \`${{ needs.resolve.outputs.sha }}\` |
          | reason | ${{ inputs.reason }} |"
          echo "$MD" >> "$GITHUB_STEP_SUMMARY"
          echo 'md<<EOF' >> "$GITHUB_OUTPUT"; echo "$MD" >> "$GITHUB_OUTPUT"; echo 'EOF' >> "$GITHUB_OUTPUT"

  # ═══════════════ 3 · ⛔ THE GATE — present ONLY in Case 1 ═══════════════
  approval:
    name: 3 · ⛔ production approval
    needs: [resolve, staging]
    # ⭐⭐ THE SWITCH: this job exists only when PROD_MODE=delivery
    if: env.PROD_MODE == 'delivery' && (inputs.target == 'production' || inputs.target == '')
    runs-on: ubuntu-latest
    environment: production        # ⭐⭐ required reviewers = the gate
    steps:
      - name: Notify the approvers with a deep link
        env: { GH_TOKEN: "${{ secrets.GITHUB_TOKEN }}" }
        run: |
          curl -fsS -X POST "${{ secrets.SLACK_WEBHOOK }}" -H 'content-type: application/json' -d @- <<EOF
          {"text":"⛔ *Approval needed* — ${{ env.SERVICE }} → production\nDigest: \`${{ needs.resolve.outputs.digest }}\`\nReason: ${{ inputs.reason }}\n\n${{ needs.staging.outputs.report }}\n\n<${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}|Approve / Reject>"}
          EOF

  # ═══════════════ 3' · 🤖 THE CANARY — present ONLY in Case 2 ═══════════════
  canary:
    name: "3' · 🤖 canary 10% + analyse"
    needs: [resolve, staging]
    if: env.PROD_MODE == 'deployment' && (inputs.target == 'production' || inputs.target == '')
    runs-on: ubuntu-latest
    environment: canary
    outputs: { verdict: ${{ steps.a.outputs.verdict }} }
    steps:
      - uses: actions/checkout@v7
      - uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
      - uses: azure/setup-kubectl@v4
        with: { version: 'v1.34.0' }
      - name: Start the canary
        run: |
          kubectl argo rollouts set image ${{ env.SERVICE }} ${{ env.SERVICE }}=\
          "${{ needs.resolve.outputs.image }}@${{ needs.resolve.outputs.digest }}" \
            -n shop-production
      - name: Analyse for 10 minutes
        id: a
        run: |
          set -euo pipefail
          sleep 600
          ./scripts/analyse-canary.sh --namespace shop-production --window 10m \
            --min-requests 200 | tee analysis.json
          V=$(jq -r .verdict analysis.json)
          echo "verdict=$V" >> "$GITHUB_OUTPUT"
      - name: Abort on a bad verdict
        if: steps.a.outputs.verdict != 'PASS'
        run: |
          kubectl argo rollouts abort ${{ env.SERVICE }} -n shop-production
          exit 1
      - name: Promote to 100%
        if: steps.a.outputs.verdict == 'PASS'
        run: kubectl argo rollouts promote ${{ env.SERVICE }} -n shop-production --full=true

  # ═══════════════ 4 · PRODUCTION ═══════════════
  production:
    name: 4 · production
    needs: [resolve, staging, approval, canary]
    if: >
      always() && needs.resolve.result == 'success' && needs.staging.result == 'success' &&
      (needs.approval.result == 'success' || needs.canary.outputs.verdict == 'PASS') &&
      (inputs.target == 'production' || inputs.target == '')
    runs-on: ubuntu-latest
    environment: production
    steps:
      - uses: actions/checkout@v7
      - uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
      - uses: azure/setup-kubectl@v4
        with: { version: 'v1.34.0' }
      # ── ⭐ CHECK 3 · DID STAGING RUN *THIS* DIGEST? ───────────────────
      - name: Assert staging ran this exact digest
        run: |
          set -euo pipefail
          STAGED="${{ needs.staging.outputs.deployed }}"
          WANT="${{ needs.resolve.outputs.image }}@${{ needs.resolve.outputs.digest }}"
          # ⭐⭐ the gate can sit for hours (Case 1) or the canary can take
          #   minutes (Case 2). Either way, drift is possible.
          [ "$STAGED" = "$WANT" ] \
            || { echo "::error::⛔ staging ran $STAGED, production was cleared for $WANT"; exit 1; }
          echo "✅ CHECK 3 passed"
      - uses: ./.github/actions/deploy-digest
        with:
          namespace: shop-production
          service:   ${{ env.SERVICE }}
          image-ref: ${{ needs.resolve.outputs.image }}@${{ needs.resolve.outputs.digest }}
          run-migration: 'true'
      - name: Watch production for 10 minutes
        run: |
          set -euo pipefail
          FAILS=0; END=$(( $(date +%s) + 600 ))
          while [ "$(date +%s)" -lt "$END" ]; do
            ERR=$(./scripts/err-ratio.sh shop-production ${{ env.SERVICE }} 5m)
            (( $(echo "$ERR > 0.01" | bc -l) )) && FAILS=$((FAILS+1)) || FAILS=0
            [ "$FAILS" -ge 3 ] && { echo "::error::⛔ regression detected"; exit 1; }
            sleep 60
          done
          echo "✅ production stable"

  # ═══════════════ 5 · ROLLBACK — automatic in Case 2 ═══════════════
  rollback:
    name: 🚨 rollback
    needs: [resolve, production]
    if: always() && needs.production.result == 'failure' && env.PROD_MODE == 'deployment'
    runs-on: ubuntu-latest
    environment: production
    steps:
      - uses: actions/checkout@v7
      - uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
      - uses: azure/setup-kubectl@v4
        with: { version: 'v1.34.0' }
      - name: Return to the last known-good digest
        run: |
          set -euo pipefail
          kubectl argo rollouts undo ${{ env.SERVICE }} -n shop-production \
            || kubectl -n shop-production rollout undo deploy/${{ env.SERVICE }}
          kubectl -n shop-production rollout status deploy/${{ env.SERVICE }} --timeout=300s || true
      - name: ⭐⭐ Set the circuit breaker
        env: { GH_TOKEN: "${{ secrets.GITHUB_TOKEN }}" }
        run: |
          gh api -X PUT "repos/${{ github.repository }}/contents/cd-state/HALTED-${{ env.SERVICE }}" \
            -f message="🚨 halt CD after a failed ${{ env.SERVICE }} promotion" \
            -f content="$(printf 'halted by %s\n' "$GITHUB_RUN_ID" | base64 -w0)" -f branch=main
          # ⭐ without this the NEXT commit re-triggers CD, fails the same way,
          #   and pages you again — forever.

  # ═══════════════ 6 · RECORD ═══════════════
  record:
    name: 6 · record
    needs: [resolve, production]
    if: always() && needs.production.result != 'skipped'
    runs-on: ubuntu-latest
    environment: production
    steps:
      - name: Write the deployment record
        env: { GH_TOKEN: "${{ secrets.GITHUB_TOKEN }}" }
        run: |
          set -euo pipefail
          STATE=$([ "${{ needs.production.result }}" = "success" ] && echo success || echo failure)
          DEP=$(gh api repos/${{ github.repository }}/deployments \
            -f ref="${{ needs.resolve.outputs.sha }}" -f environment=production \
            -f description="${{ env.SERVICE }} ${{ needs.resolve.outputs.digest }}" \
            -F auto_merge=false -F required_contexts='[]' --jq .id)
          gh api repos/${{ github.repository }}/deployments/$DEP/statuses \
            -f state="$STATE" -f environment_url="https://api.shop/" >/dev/null
          echo "✅ CHECK 4 · deployment $DEP recorded as $STATE"
```

### 5.1 The composite action both scenarios share

`.github/actions/deploy-digest/action.yml`

```yaml
name: 'Deploy a digest, verify it, and smoke it'
description: '⭐ migrate (optional) → set image → wait → READ BACK → smoke from inside'
inputs:
  namespace:     { required: true }
  service:       { required: true }
  image-ref:     { required: true }
  run-migration: { required: false, default: 'false' }
  probe:         { required: false, default: '/actuator/health/readiness' }
  port:          { required: false, default: '8080' }
  timeout:       { required: false, default: '600s' }
runs:
  using: composite
  steps:
    - name: Validate, record, migrate, deploy, read back
      shell: bash
      run: |
        set -euo pipefail
        NS='${{ inputs.namespace }}'; SVC='${{ inputs.service }}'; REF='${{ inputs.image-ref }}'
        [[ "$REF" =~ @[a-z0-9]+:[0-9a-f]{64}$ ]] || { echo "::error::⛔ not a digest"; exit 1; }

        PREV=$(kubectl -n $NS get deploy $SVC \
               -o jsonpath="{.spec.template.spec.containers[?(@.name=='$SVC')].image}")
        echo "PREV_IMAGE=$PREV" >> "$GITHUB_ENV"          # ⭐ recorded = rollback target
        if [ "$PREV" = "$REF" ]; then echo "ℹ️ already running $REF — no-op"; exit 0; fi

        # ── ⭐⭐ MIGRATION FIRST, AS A GATED JOB ──────────────────────
        if [ '${{ inputs.run-migration }}' = 'true' ] && [ -f "k8s/$SVC/migration-job.yaml" ]; then
          kubectl -n $NS delete job "$SVC-migrate" --ignore-not-found
          kubectl -n $NS apply -f "k8s/$SVC/migration-job.yaml"
          kubectl -n $NS wait --for=condition=complete "job/$SVC-migrate" --timeout=600s \
            || { echo "::error::⛔ migration FAILED — not rolling out"; exit 1; }
        fi

        kubectl -n $NS apply -f "k8s/$SVC/"
        kubectl -n $NS set image "deploy/$SVC" "$SVC=$REF"
        kubectl -n $NS rollout status "deploy/$SVC" --timeout='${{ inputs.timeout }}' \
          || { kubectl -n $NS set image "deploy/$SVC" "$SVC=$PREV_IMAGE"; exit 1; }

        # ── ⭐⭐ READ IT BACK. An exit code is not proof of what runs. ──
        NOW=$(kubectl -n $NS get deploy $SVC \
              -o jsonpath="{.spec.template.spec.containers[?(@.name=='$SVC')].image}")
        [ "$NOW" = "$REF" ] || { echo "::error::⛔ running $NOW, wanted $REF"; exit 1; }
        echo "✅ $NS confirmed running $NOW"
    - name: ⭐ Smoke from INSIDE the cluster
      shell: bash
      run: |
        set -euo pipefail
        NS='${{ inputs.namespace }}'; SVC='${{ inputs.service }}'
        kubectl -n $NS run smoke-$RANDOM --rm -i --restart=Never \
          --image=curlimages/curl:8.17.0 -- \
          curl -fsS "http://$SVC.$NS.svc.cluster.local:${{ inputs.port }}${{ inputs.probe }}"
```

---

## 6 · ⭐⭐ The artifact contract — four checks

**This is the entire content of Scenario 3.** Everything else is plumbing.

| # | Check | Where | What it proves |
|---|---|---|---|
| **1** | ⛔ **It is a digest, not a tag** | CD `resolve` | the artifact is immutable — "what ran" has an exact answer |
| **2** | ⭐ **Provenance verified** (`cosign verify` pinned to the CI workflow **and branch**) | CD `resolve` | it was built by *our* CI on *main*, not pushed by hand |
| **3** | ⭐ **Staging ran this exact digest** (read back from the cluster) | CD `production` | what was verified is what is being promoted — no drift across the gate |
| **4** | ⭐⭐ **The cluster is running this digest after deploy** (read back again) | the composite action | the deploy actually happened. ⭐ a tool's exit code is not proof |

```bash
# ⭐ the four checks as four greps against your own workflows
W=.github/workflows
grep -q 'sha256:\[0-9a-f\]{64}' $W/cd-shop-api.yml && echo "✅ 1 digest-only"
grep -q 'cosign verify'          $W/cd-shop-api.yml && echo "✅ 2 provenance"
grep -q 'staging ran'            $W/cd-shop-api.yml && echo "✅ 3 no drift"
grep -q 'READ IT BACK' .github/actions/deploy-digest/action.yml && echo "✅ 4 confirmed"
```

⭐ **Plus two that are easy to forget:**
- **CI stops after publishing.** No deploy verb, no cluster secret in scope — verifiable by `grep -c kubeconfig ci-shop-api.yml` returning `0`.
- **CD cannot publish.** No `packages: write` in its `permissions:` — a `docker push` step would fail with `denied`.

---

## 7 · Environments — the permission map

| Environment | Declared by | Secrets it holds | Reviewers |
|---|---|---|---|
| *(none)* | the CI `image` job | — (uses `GITHUB_TOKEN` + OIDC) | — |
| `dev` | CD `dev` | `AZURE_CLIENT_ID` (dev SP) | ⭐ none |
| `staging` | CD `staging` | `AZURE_CLIENT_ID` (staging SP) | ⭐ none |
| `canary` | CD `canary` | `AZURE_CLIENT_ID` (narrow RBAC) | ⭐ none |
| `production` | CD `approval` + `production` | `AZURE_CLIENT_ID` (prod SP), `SLACK_WEBHOOK` | 🔒 a team of ≥ 3 |

```bash
# ⭐ the check that proves the separation
gh api repos/ORG/shop/environments --jq '.environments[].name'
# and: CI's job list must contain NO `environment:` key
grep -n 'environment:' .github/workflows/ci-shop-api.yml \
  && echo "⛔ CI declares an environment — it can reach deploy secrets" \
  || echo "✅ CI declares no environment"
```

⭐⭐ **Why this is the security argument rather than a nicety:** GitHub evaluates `secrets` per job, and a job that does not declare `environment: production` **cannot read a production environment secret** — not through injection, not through a compromised action, not through `echo "${{ toJson(secrets) }}"`. The boundary is enforced by the platform, not by your YAML's discipline.

---

## 8 · 🔒 Case 1 or 🤖 Case 2 — the one flag that switches

```yaml
env:
  PROD_MODE: delivery      # ⭐ delivery = 🔒 human gate · deployment = 🤖 canary
```

| | `PROD_MODE: delivery` | `PROD_MODE: deployment` |
|---|---|---|
| `approval` job | ✅ runs, waits for reviewers | ⛔ skipped |
| `canary` job | ⛔ skipped | ✅ runs, analyses |
| `production` job's `if:` | passes via `approval.result == 'success'` | passes via `canary.outputs.verdict == 'PASS'` |
| `rollback` job | ⛔ skipped (a human rolls back) | ✅ automatic |
| Environment reviewers | ⭐ **required** | ⭐ **must be removed** |

⭐⭐ **The one thing the flag cannot do:** remove the environment's required reviewers. That is a **settings** change, not a YAML change — so switching a service from Case 1 to Case 2 requires two deliberate acts (edit the flag, edit the environment), which is exactly the friction you want.

**Per-service `PROD_MODE`, which is what a real estate uses:**

```yaml
# ⭐ in a matrix or a vars file, not hardcoded per workflow
strategy:
  matrix:
    include:
      - { service: shop-ui,      mode: deployment }   # 🤖 FE — lowest risk
      - { service: payment-mock, mode: deployment }   # 🤖 the pilot
      - { service: checkout,     mode: deployment }   # 🤖 stateless Go
      - { service: order-worker, mode: delivery   }   # 🔒 cannot be canaried
      - { service: shop-api,     mode: delivery   }   # 🔒 migrations
```

---

## 9 · Reusable workflows — the scale answer

At five services, five copies of the CD workflow is five chances to get the gate wrong.

```yaml
# .github/workflows/_cd-deploy.yml  — ⭐ the underscore prefix is a convention
name: _CD deploy (reusable)
on:
  workflow_call:
    inputs:
      service:   { required: true, type: string }
      image-ref: { required: true, type: string }
      mode:      { required: true, type: string }     # delivery | deployment
      namespace-prefix: { required: false, type: string, default: shop }
    secrets:
      AZURE_CLIENT_ID:       { required: true }
      AZURE_TENANT_ID:       { required: true }
      AZURE_SUBSCRIPTION_ID: { required: true }
jobs:
  # … the whole dev → staging → gate/canary → production chain …
```

```yaml
# ⭐ the caller — 12 lines per service instead of 250
name: CD · checkout
on:
  workflow_run: { workflows: ['CI · checkout'], types: [completed], branches: [main] }
jobs:
  deploy:
    if: github.event.workflow_run.conclusion == 'success'
    uses: ./.github/workflows/_cd-deploy.yml
    with:
      service:   checkout
      image-ref: ${{ needs.resolve.outputs.image-ref }}
      mode:      deployment          # 🤖 Case 2
    secrets: inherit                  # ⛔ or name them explicitly — safer
```

| ⭐ Rule | Why |
|---|---|
| `secrets: inherit` is convenient and **dangerous** | it passes *every* secret to the called workflow. Name them |
| The reusable workflow holds the **gates** | so a service cannot opt out of provenance verification |
| `mode` is an **input**, not a hardcoded value | per-service Case 1/Case 2 (§8) |
| ⭐ Version the reusable workflow with a tag | `uses: ./.github/workflows/_cd-deploy.yml@v2` — an unversioned call means a change to it changes every service at once |

---

## 10 · ▶️ Run it end to end — the full acceptance checks

```bash
ORG=ORG; REPO=shop

# ── CI HALF ────────────────────────────────────────────────────────────
# 1 · CI declares NO environment (so it cannot reach deploy secrets)
grep -c 'environment:' .github/workflows/ci-shop-api.yml     # ⭐ must be 0

# 2 · CI publishes ONLY on push to main
grep -A6 'Decide whether to push' .github/workflows/ci-shop-api.yml | grep -q 'refs/heads/main'

# 3 · CI signs keylessly
grep -q 'sigstore/cosign-installer' .github/workflows/ci-shop-api.yml && echo "✅ keyless"

# 4 · the digest artifact exists after a run
RID=$(gh run list --workflow ci-shop-api.yml --branch main --status success --limit 1 --json databaseId --jq '.[0].databaseId')
gh run download "$RID" -n image-digest -D /tmp/dl && cat /tmp/dl/digest.txt
# ⭐ must print ghcr.io/3558bhk/shop-api@sha256:<64 hex>

# ── THE CHAIN ──────────────────────────────────────────────────────────
# 5 · ⭐⭐ THE END-TO-END TEST: push a commit and watch BOTH workflows
git commit --allow-empty -m "e2e: trigger CI+CD" && git push origin main
gh run watch --exit-status            # CI
sleep 20
gh run list --workflow cd-shop-api.yml --limit 1     # ⭐ CD must have started

# ── CD HALF ────────────────────────────────────────────────────────────
# 6 · CD has NO packages: write
grep -A4 '^permissions:' .github/workflows/cd-shop-api.yml | grep -q 'packages' \
  && echo "⛔ CD can publish" || echo "✅ CD cannot publish"

# 7 · CD verifies provenance
grep -q 'cosign verify' .github/workflows/cd-shop-api.yml && echo "✅ CHECK 2"

# 8 · CD refuses a tag
gh workflow run cd-shop-api.yml -f image=ghcr.io/3558bhk/shop-api:latest -f reason=neg
sleep 15; gh run list --workflow cd-shop-api.yml --limit 1 --json conclusion --jq '.[0]'
# ⭐ must be "failure"

# 9 · the environment has reviewers IFF PROD_MODE=delivery
grep -q 'PROD_MODE: delivery' .github/workflows/cd-shop-api.yml && \
  gh api repos/$ORG/$REPO/environments/production \
     --jq '.protection_rules[].type' | grep -q required_reviewers \
     && echo "✅ Case 1 correctly gated"

# 10 · ⭐ CHECK 4 — what is ACTUALLY running
az aks get-credentials -n shop-prod -g rg-shop --overwrite-existing
kubectl -n shop-production get deploy shop-api \
  -o jsonpath='{.spec.template.spec.containers[?(@.name=="shop-api")].image}{"\n"}'
# ⭐ must equal the digest from check 4

# 11 · ⭐ the deployment record answers "what went to production?"
gh api repos/$ORG/$REPO/deployments?environment=production --jq '.[0] | {id,ref:.sha,desc:.description}'

# 12 · ⭐⭐ rollback needs no gate
grep -c 'environment:' .github/workflows/rollback-shop-api.yml   # ⭐ must be 0
```

⭐⭐ **Check 5 and check 10 are the two that matter.** Check 5 proves the chain fires on a real commit; check 10 proves that what CI published is *literally what production is running*. Everything else is a grep against your own YAML.

---

## 11 · Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| ⛔ CD never triggers | `workflow_run` only uses files on the **default branch** | merge CD to `main` |
| CD triggers on a failed CI | `types: [completed]` includes failures | the `conclusion == 'success'` condition (§2) |
| `gh run download` finds nothing | the artifact name differs, or CI did not push (a PR) | check `steps.flags.outputs.push` was `true` |
| ⛔ CI cannot push to GHCR | `packages: write` missing on that job | §4 — job-level `permissions:` |
| `cosign sign` prompts and hangs | `COSIGN_YES` not set | `env: { COSIGN_YES: 'true' }` |
| ⛔ `cosign verify` fails on a valid image | the `--certificate-identity-regexp` includes the branch, and the image was built on a PR | ⭐ pin to `@refs/heads/main` **and** only sign on main |
| CD reads `secrets.AZURE_CLIENT_ID` as empty | it is an **environment** secret and the job lacks `environment:` | §7 |
| Both `approval` and `canary` run | `PROD_MODE` is not set at the job level, or `env` is not visible in `if:` | ⭐ `env:` at workflow level *is* visible in `if:`; a job-level `env:` is **not** |
| `production` is skipped in Case 2 | the `if:` requires `approval.result == 'success'`, which is `skipped` | use the `||` form in §5 |
| ⛔ Two CD runs deploy at once | no `concurrency:` group | §5 |
| The migration Job never runs | `run-migration` defaults to `'false'` | pass `'true'` (§5.1) |
| `kubectl set image` succeeds but the image is unchanged | ⛔ the container **name** does not match | read it back (§5.1) — that check exists for exactly this |
| ⛔ Paged repeatedly after a failure | no circuit breaker | the `rollback` job sets `cd-state/HALTED-<service>` (§5) |
| Testcontainers fails on a self-hosted runner | no Docker daemon | a sidecar Postgres, or Testcontainers Cloud |

---

<a name="tasks--answers"></a>
## 12 · ⭐ TASKS — answers at the END

| # | Task |
|---|---|
| **T1** | Build the two-workflow chain for `shop-api` and prove CI cannot deploy and CD cannot publish |
| **T2** | Wire `workflow_run` correctly, handling all four traps, and download the exact CI run's artifact |
| **T3** | Replace every long-lived secret with OIDC — GHCR, cosign, ACR, AKS |
| **T4** | Implement all four artifact-contract checks and demonstrate each one failing |
| **T5** | Make `PROD_MODE` switch between Case 1 and Case 2, and list what else must change |
| **T6** | Extract `_cd-deploy.yml` as a reusable workflow and migrate three services to it |
| **T7** | Add the migration Job to the composite action so it gates the rollout |
| **T8** | Add the circuit breaker and prove five failing commits produce one page |
| **T9** | Chain FE after BE for shape C across the two-workflow architecture |
| **T10** | ⭐⭐ A malicious transitive npm dependency runs a postinstall script during `npm ci` in your CI job. Describe precisely what it can and cannot do in this architecture — and name the one configuration mistake that would give it production access |

---

# ✅ ANSWERS

**T1.** §4 and §5. **Proving CI cannot deploy:** `grep -c 'environment:' .github/workflows/ci-shop-api.yml` returns **0**, and `grep -c 'kubeconfig\|az aks\|kubectl' ci-shop-api.yml` returns **0** — there is no cluster credential in scope and no deploy verb. Then attempt it: add `echo "${{ secrets.AZURE_CLIENT_ID }}" | wc -c` to the CI `image` job. **It prints `0`** — the secret is not merely unused, it is absent from that job's context. **Proving CD cannot publish:** CD's workflow-level `permissions:` has no `packages: write`; add a `docker push` step and it fails with `denied: requested access to the resource is denied`. ⭐ **Enforce the second one in the registry too**, not just in YAML: give CD's OIDC subject a **pull-only** role. A YAML rule survives exactly one urgent Friday fix; a missing role assignment is a hard failure.

**T2.** §2. `on: workflow_run: { workflows: ['CI · shop-api'], types: [completed], branches: [main] }` — where `workflows:` matches the CI workflow's **`name:`** field, not its filename (⭐ renaming the workflow silently breaks the chain and nothing errors). The four traps: **(1)** `types: [completed]` fires on failure too, so the first job needs `if: github.event.workflow_run.conclusion == 'success'`; **(2)** `workflow_run` only evaluates workflow files **on the default branch**, so CD must be merged to `main` before it can trigger anything — which is why testing on a branch looks like nothing happens; **(3)** `github.ref`/`github.sha` are the *default branch's*, not the triggering commit's, so use `github.event.workflow_run.head_sha` and `.head_branch`; **(4)** `GITHUB_TOKEN` is restricted in this context on private repos, so declare `permissions:` explicitly. **Downloading the exact artifact:** `gh run download "${{ github.event.workflow_run.id }}" -n image-digest -D /tmp/dl`. ⭐ Using the triggering **run id** rather than searching for "the latest successful build" is what removes the race: two commits in quick succession would otherwise let CD pick up the wrong digest.

**T3.** §3, four replacements:
- **GHCR push** → `permissions: { packages: write }` on the `image` job plus `docker/login-action` using `${{ secrets.GITHUB_TOKEN }}`. No PAT.
- **Signing** → `sigstore/cosign-installer@v4` + **keyless** signing with `permissions: { id-token: write }` and `COSIGN_YES: 'true'`. ⭐ There is no key to store, rotate or leak; the certificate is minted from the runner's OIDC token and recorded in Rekor, so the identity is *the pipeline itself*.
- **ACR pull** → `azure/login@v2` with a federated credential whose subject is `repo:ORG/shop:environment:production`, and `AcrPull` on that principal.
- **AKS access** → the same `azure/login@v2`, then `az aks get-credentials`. No kubeconfig secret exists anywhere.

⭐ **The strongest property, and the one to say out loud:** because the federated credential's subject claim includes `environment:production`, a **dev** job cannot mint a production token even by asking for one — the boundary is enforced by the identity provider, not by your YAML. **Finish by deleting the old secrets**; leaving the kubeconfig "just in case" means the leak path still exists.

**T4.** §6. **(1) digest shape** — `[[ "$RAW" =~ ^[a-z0-9._/-]+@sha256:[0-9a-f]{64}$ ]]` in CD's `resolve`; demonstrate failure with `gh workflow run cd-shop-api.yml -f image=…:latest` → the run fails at `resolve`. **(2) provenance** — `cosign verify --certificate-identity-regexp="…ci-shop-api\.yml@refs/heads/main$"`; demonstrate failure by `docker push`ing an image by hand and passing its digest → `⛔ provenance verification failed`. **(3) no drift** — CD's `production` job compares `needs.staging.outputs.deployed` (⭐ **read back from the cluster**, not forwarded from the input) against the requested ref; demonstrate by approving a run with a *different* digest than staging ran. **(4) confirmed running** — the composite action reads the image back with the JSONPath **name filter** `[?(@.name=='<svc>')]` after `rollout status`; demonstrate by deliberately mistyping the container name in `set image`, which succeeds silently and is caught only here. ⭐ **Check 4 is the one that catches the most dangerous failure**, because `kubectl set image` exits 0 when the deployment exists even if the container name does not match — a green pipeline, a recorded approval, and production still on the old digest.

**T5.** §8. The flag: `env.PROD_MODE: delivery | deployment` at **workflow** level, gating `if: env.PROD_MODE == 'delivery'` on the `approval` job and `if: env.PROD_MODE == 'deployment'` on `canary` and `rollback`. **What else must change — and the important part is that the flag cannot do it:**
1. ⭐⭐ **Remove Required reviewers from the `production` environment** (Settings → Environments). This is a *settings* change, not YAML — so switching cases requires **two deliberate acts**, which is exactly the friction you want. Leaving the reviewers in place with `PROD_MODE: deployment` gives you a pipeline that *thinks* it is automatic and stops for a human anyway.
2. **`production`'s `if:`** must accept either path: `(needs.approval.result == 'success' || needs.canary.outputs.verdict == 'PASS')` with `always()` — because in each mode the other job is `skipped`, and `skipped` is not `success`.
3. **Prerequisites.** Case 2 requires all five from [`../scenario-2-cd-only/00-delivery-vs-deployment.md`](../scenario-2-cd-only/00-delivery-vs-deployment.md) §6 — Argo Rollouts installed, a baseline-aware `AnalysisTemplate`, a `minimum-volume` gate, and the circuit breaker. ⛔ Flipping the flag without those is not Case 2; it is unattended deployment.
4. ⭐ **A job-level `env:` is NOT visible in that job's own `if:`** — the flag must be at workflow level (or use `vars`). This is a real gotcha that silently skips both branches.

**T6.** §9. Extract the whole dev → staging → gate/canary → production → record chain into `.github/workflows/_cd-deploy.yml` with `on: workflow_call` and inputs `service`, `image-ref`, `mode`, `namespace-prefix`. Migrate `shop-api` (`mode: delivery`), `checkout` (`mode: deployment`) and `shop-ui` (`mode: deployment`) to ~12-line callers. ⭐ **Four rules that decide whether this is an improvement:** **name the secrets explicitly** rather than `secrets: inherit` (which passes *every* secret to the called workflow — a much larger blast radius for one compromised reusable workflow); put the **gates inside the reusable workflow** so no service can opt out of provenance verification or the read-back assertion; make `mode` an **input** so per-service Case 1/Case 2 is data, not code; and **version the call** (`@v2` or a tag) — an unversioned `uses: ./.github/workflows/…` means editing the template changes every service's deployment behaviour at once, which is how a well-intentioned refactor takes down five services.

**T7.** §5.1. In the composite action, before `set image`: `if [ '$RUN_MIGRATION' = 'true' ] && [ -f "k8s/$SVC/migration-job.yaml" ]; then kubectl delete job "$SVC-migrate" --ignore-not-found; kubectl apply -f …; kubectl wait --for=condition=complete "job/$SVC-migrate" --timeout=600s || exit 1; fi`. ⭐ Three details make it correct: the Job's container image must be **the same digest** as the app (a different image carries a different Flyway version and possibly different SQL on the classpath); `backoffLimit: 0` with `restartPolicy: Never` in the Job spec (a failed migration needs a human, not a second attempt that may have half-applied the first); and the `wait` **must** `exit 1` on failure, so the rollout never starts. **Prove it** with a `V999__bad.sql` containing `ALTER TABLE orders ADD COLUMN qty INT NOT NULL;` — which fails on existing rows — and confirm the pipeline stops at the migration with `kubectl get deploy` still showing the **previous** digest. Note the Spring Boot 3.2+ launcher class (`org.springframework.boot.loader.launch.JarLauncher`); pre-3.2 it has no `.launch` segment.

**T8.** §5's `rollback` job. **Set:** `gh api -X PUT repos/.../contents/cd-state/HALTED-${{ env.SERVICE }}` with base64 content, on `if: always() && needs.production.result == 'failure' && env.PROD_MODE == 'deployment'`. **Check:** a step at the top of `resolve` that does `gh api repos/.../contents/cd-state/HALTED-$SERVICE` and, if it exists, sets an output that makes every downstream job skip. **Prove one page rather than five:** push five commits, each producing a bad digest. Run 1 fails the canary, rolls back, pages once, and creates the file. Runs 2–5 enter `resolve`, see the file, and complete **green having promoted nothing** — no canary, no rollback, no page. ⭐ Four rules: the file is **never deleted by the job that created it** (clearing your own circuit breaker defeats the purpose); a halted run is **green**, not red, because five red builds an hour is alert fatigue and alert fatigue is how the next real failure gets missed; it is **per service** (`HALTED-shop-api`, not `HALTED`) so one bad service does not freeze the estate; and clearing is either manual or a scheduled workflow conditioned on "no failures in 4h". Living in the repo means `git log cd-state/` is the history of every halt.

**T9.** Two options, and ⭐ the second is better:
- **(a) `workflow_run` on the CD workflow:** `cd-shop-ui.yml` gets `on: workflow_run: { workflows: ['CD · shop-api'], types: [completed] }` with `if: github.event.workflow_run.conclusion == 'success'`. Simple, but CD-UI now depends on CD-API's *workflow name*, and the same four traps apply.
- **(b) ⭐ one release-train workflow** that calls the reusable `_cd-deploy.yml` twice with `needs:` between them:

```yaml
jobs:
  api:
    uses: ./.github/workflows/_cd-deploy.yml
    with: { service: shop-api, image-ref: ${{ needs.resolve.outputs.api_ref }}, mode: delivery }
  ui:
    needs: api                      # ⭐⭐ backend FIRST, enforced by the graph
    uses: ./.github/workflows/_cd-deploy.yml
    with: { service: shop-ui, image-ref: ${{ needs.resolve.outputs.ui_ref }}, mode: deployment }
```

⭐ **Why backend first:** the backend must be able to serve *both* the old and the new frontend at every instant, because cached frontends persist for as long as browser cache dictates — a duration you do not control. The reverse order guarantees a window where old frontends call endpoints the new backend removed. **Two more decisions:** give the pair **one approval** in Case 1 (the human authorised *this release*, and two prompts invite approving the FE after the BE failed); and on an FE failure **roll back both**, because a half-promoted pair — new UI against old API — is a state nobody tested and is worse than either consistent state. Both are only safe if the backend's migrations are expand/contract, which is prerequisite 5.

**T10.** ⭐⭐ **What it CAN do:** read everything in the CI job's environment — the source code, `GITHUB_TOKEN` (scoped to `contents: read`, `packages: write` on that job), the Maven/npm caches, and any secret you attached to that job. It can **push an image to your registry** (`packages: write` is present, by necessity, in the `image` job). It can make arbitrary outbound network calls — exfiltrating source, or fetching a second stage. It can tamper with the build output, so the published artifact may not correspond to the commit. And it can poison the `type=gha` cache, **persisting into future runs** — which is the most under-appreciated capability, because it survives the single compromised build.

**What it CANNOT do:** deploy. There is **no cluster credential in CI's scope at all** — `grep -c 'environment:'` on the CI file is `0`, and the production Azure federated credential lives in the `production` **environment**, whose secrets are absent from a job that does not declare it. It cannot reach the `dev`, `staging` or `canary` clusters either. It cannot approve anything. And — the check that matters most — **it cannot get a bad image into production by itself**: CD independently verifies `cosign` provenance pinned to `ci-shop-api.yml@refs/heads/main`, and (in `PROD_MODE: delivery`) a human reviews the staging report before promotion.

⭐ **The realistic damage is therefore a poisoned artifact that CD will happily deploy** — because the signature is valid (it *was* signed by your CI) and, in Case 2, no human looks. That is the residual risk, and the mitigations are dependency pinning/lockfile-only installs, `ignore-scripts` where possible, Dependabot/`dependency-review-action` on PRs, and a pinned SBOM diff.

**The one configuration mistake that gives it production access:** ⛔ **merging CI and CD into a single workflow.** The moment the job that runs `npm ci` also declares `environment: production` — or the production kubeconfig is promoted from an *environment* secret to a plain *repository* secret — every job in the repo can read it, including this one. A malicious postinstall script then has `secrets.KUBECONFIG_PROD` in its environment and `kubectl` on the runner, and the distance from `npm ci` to `kubectl -n shop-production set image …` is one HTTP call. Three near-misses produce the same outcome: `secrets: inherit` on a reusable workflow call; a **self-hosted** runner shared between CI and CD (the credential isolation is per-job, but the *machine* is not — a persistent runner keeps files, env and Docker state between jobs); and `pull_request_target`, which runs base-repo workflows **with write tokens and full secret access** against unreviewed fork code. ⭐ **The general principle: secret scoping is the security boundary in GitHub Actions, not YAML discipline — so the architecture question "one pipeline or two?" is a security question, and the answer is two.**

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish_Kumar_Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn: https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260
🔗 GitHub: https://github.com/3558Bhk

*Two workflows, one digest, four checks. Secret scope is the boundary — not your YAML's discipline.*

</div>
