# 🐙 CASE 2 · CONTINUOUS DEPLOYMENT WITH GITHUB ACTIONS
### Auto-promotion on CI success, smoke gates, a canary environment, baseline-aware analysis, and automatic rollback that also halts further releases.

> **Scenario:** CI ran ([Scenario 1 · GitHub Actions](../../scenario-1-ci-only/01-github-actions-ci.md)) and published `ghcr.io/3558bhk/<svc>@sha256:…`. **This pipeline never builds, never waits for a human, and can undo itself.**
>
> **Tool version anchors:** `actions/checkout@v7` · `azure/setup-kubectl@v4` · GitHub **Environments** (no reviewers — ⭐ deliberately) · `workflow_run` · `deployment_status` · Argo Rollouts for the canary itself ([`04-docker-and-k8s-targets.md`](./04-docker-and-k8s-targets.md)).

---

## 📇 Contents

| § | What |
|---|---|
| [1](#1---what-changes-from-case-1) | ⭐ What changes from Case 1 — six differences, one file |
| [2](#2---the-trigger-workflow_run--and-its-four-traps) | ⭐ The trigger: `workflow_run` — and its four traps |
| [3](#3---the-five-gates-that-replace-the-human) | ⭐⭐ The five gates that replace the human |
| [4](#4---the-cd-workflow--checkout-go-stateless-full-file) | ⭐ The CD workflow — `checkout` (Go, stateless), full file |
| [5](#5---baseline-aware-analysis--why-fixed-thresholds-fail) | ⭐⭐ Baseline-aware analysis — why fixed thresholds fail |
| [6](#6---automatic-rollback-and-halting-further-releases) | ⭐⭐ Automatic rollback **and halting further releases** |
| [7](#7--the-freeze-calendar) | The freeze calendar — the question Case 1's human also answered |
| [8](#8--deployment_status-and-the-github-deployment-api) | `deployment_status` and the GitHub deployment API |
| [9](#9--per-app-shape--which-services-should-be-case-2-at-all) | Per app shape — which services should be Case 2 at all |
| [10](#10--️-run-it-and-prove-it--the-case-2-acceptance-checks) | ▶️ Run it and prove it — the Case 2 acceptance checks |
| [11](#11--troubleshooting) | Troubleshooting |
| [12](#12---tasks--answers-at-the-end) | Tasks and answers — **answers at the END** |

---

## 1 · ⭐ What changes from Case 1

Compare with [`../case-1-continuous-delivery/01-github-actions-delivery.md`](../case-1-continuous-delivery/01-github-actions-delivery.md). **Six differences:**

| # | Case 1 (Delivery) | Case 2 (Deployment) |
|---|---|---|
| 1 | `workflow_dispatch` only | ⭐ `workflow_run` on CI success — **automatic** |
| 2 | `environment: production` **with required reviewers** | `environment: production` with **no reviewers** — the gate is the checks |
| 3 | Staging verification is a **report** | ⭐ Staging verification is a **gate** — `if: failure()` stops everything |
| 4 | No canary | ⭐ **canary stage**, 5–10% traffic, analysed for N minutes |
| 5 | Rollback is a separate manual workflow | ⭐⭐ Rollback is a **job in this workflow**, automatic |
| 6 | Nothing stops the next release | ⭐⭐ A failed release **halts further promotions** |

```
⭐ THE SINGLE STRUCTURAL INSIGHT:
   In Case 1, a FAILED verify step informs a human, who decides.
   In Case 2, a FAILED verify step must DECIDE.
   So every `run:` that only reported now has to `exit 1` — and every
   `exit 1` has to lead somewhere defined, not to a red X.
```

---

## 2 · ⭐ The trigger: `workflow_run` — and its four traps

```yaml
on:
  workflow_run:
    workflows: ['CI · checkout']       # ⭐ the CI workflow's `name:`, not its file
    types: [completed]
    branches: [main]
```

| # | Trap | ⭐ Fix |
|---|---|---|
| 1 | ⛔ `types: [completed]` fires on **failure too** | `if: github.event.workflow_run.conclusion == 'success'` on the first job |
| 2 | ⛔ `workflow_run` only uses workflow files **on the default branch** | the CD file must be merged to `main` before it can trigger anything |
| 3 | ⛔ `github.ref` is the **default branch**, not the triggering branch | use `github.event.workflow_run.head_branch` / `.head_sha` |
| 4 | ⛔ `secrets.GITHUB_TOKEN` in a `workflow_run` context has **read** permissions by default on private repos | set `permissions:` explicitly |

```yaml
jobs:
  resolve:
    # ⭐⭐ traps 1 and 3 handled in one place
    if: >
      github.event.workflow_run.conclusion == 'success' &&
      github.event.workflow_run.head_branch == 'main'
    runs-on: ubuntu-latest
    steps:
      - name: Get the digest CI published
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          set -euo pipefail
          RUN_ID="${{ github.event.workflow_run.id }}"
          SHA="${{ github.event.workflow_run.head_sha }}"
          gh run download "$RUN_ID" -n image-digest -D /tmp/dl
          RAW=$(cat /tmp/dl/digest.txt)
          echo "✅ CI run $RUN_ID ($SHA) published $RAW"
```

⭐ **Why `workflow_run` rather than `repository_dispatch` or a `push` on a manifests repo:** `workflow_run` carries the triggering run's id, so the CD pipeline can download **exactly the artifact CI produced** — no searching, no ambiguity about "the latest". That is the digest contract enforced structurally.

---

## 3 · ⭐⭐ The five gates that replace the human

| Gate | Replaces | Implementation | On failure |
|---|---|---|---|
| **G1 · Provenance** | "did this come from our CI?" | `cosign verify` pinned to the CI workflow identity | ⛔ stop |
| **G2 · Smoke (per environment)** | "does it actually work here?" | real endpoints, from **inside** the cluster | ⛔ stop + rollback |
| **G3 · Canary analysis** | ⭐ "are the metrics normal?" | baseline-aware error rate + latency, N minutes | ⛔ rollback + halt |
| **G4 · Freeze / concurrency** | "is now a good time? is anyone else shipping?" | freeze-calendar check + `concurrency:` | ⏸ defer, do not fail |
| **G5 · Post-production verify** | "did it work?" | the same smoke + a metric comparison | ⛔ rollback + halt + page |

⭐⭐ **G4's "defer, do not fail" is subtle and important.** A freeze is not an error. If the pipeline *fails* during a freeze, you get red builds, alert fatigue, and eventually someone disables the check. Instead it should **exit 0 having done nothing**, and leave the digest queued for when the freeze lifts.

---

## 4 · ⭐ The CD workflow — `checkout` (Go, stateless), full file

`.github/workflows/cd-checkout.yml`

```yaml
# ═══════════════════════════════════════════════════════════════════════
#  WHAT : CD ONLY, Case 2 — CONTINUOUS DEPLOYMENT for `checkout` (Go).
#         CI success → dev → staging → ⭐ canary → production.
#         NO human anywhere. Automatic rollback. Halts on failure.
#  WHY  : `checkout` is stateless, has no schema, and a working /readyz —
#         it satisfies all five prerequisites, so it is the correct pilot.
#  TARGET: kind `cicd` → namespaces shop-{dev,staging,canary,production}.
# ═══════════════════════════════════════════════════════════════════════
name: CD · checkout (deployment)

on:
  workflow_run:
    workflows: ['CI · checkout']
    types: [completed]
  workflow_dispatch:            # ⭐ kept for manual re-promotion of a digest
    inputs:
      image: { description: 'digest ref (blank = latest CI)', required: false, type: string }

concurrency:
  # ⭐⭐ G4a: ONE promotion at a time. Two overlapping rollouts produce a
  #   cluster state nobody analysed.
  group: cd-checkout-production
  cancel-in-progress: false       # ⛔ NEVER cancel a deployment mid-flight

permissions:
  contents: read
  deployments: write              # ⭐ needed for the deployment API (§8)

env:
  SERVICE: checkout
  CANARY_WEIGHT: '10'             # percent
  CANARY_SOAK_MINUTES: '10'

jobs:
  # ═════════════════════════════════════════════════════════════════════
  #  GATE 0 · SHOULD WE RUN AT ALL?
  # ═════════════════════════════════════════════════════════════════════
  gate:
    name: 'G0 · Trigger + freeze gate'
    if: >
      github.event_name == 'workflow_dispatch' ||
      (github.event.workflow_run.conclusion == 'success' &&
       github.event.workflow_run.head_branch == 'main')
    runs-on: ubuntu-latest
    outputs:
      proceed: ${{ steps.freeze.outputs.proceed }}
      image:   ${{ steps.digest.outputs.image }}
      digest:  ${{ steps.digest.outputs.digest }}
      sha:     ${{ steps.digest.outputs.sha }}
    steps:
      - uses: actions/checkout@v7

      # ── G4b · THE FREEZE CALENDAR ───────────────────────────────────
      - name: Check the freeze calendar
        id: freeze
        run: |
          set -euo pipefail
          # ⭐ a committed, reviewable calendar — not a config in a UI nobody reads
          NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
          if ./scripts/in-freeze-window.sh "$NOW" freezes.yaml; then
            echo "🧊 FREEZE in effect at $NOW — NOT promoting."
            echo "proceed=false" >> "$GITHUB_OUTPUT"
            # ⭐⭐ exit 0. A freeze is not a failure. A red build during a
            #   freeze trains everyone to ignore red builds.
            exit 0
          fi
          # ⭐ also refuse during an ACTIVE INCIDENT
          if curl -fsS "$PAGERDUTY_INCIDENTS_URL" | jq -e '.incidents | length > 0' >/dev/null; then
            echo "🚨 an incident is open — NOT promoting."
            echo "proceed=false" >> "$GITHUB_OUTPUT"; exit 0
          fi
          echo "proceed=true" >> "$GITHUB_OUTPUT"
        env:
          PAGERDUTY_INCIDENTS_URL: ${{ secrets.PAGERDUTY_INCIDENTS_URL }}

      # ── G1 · RESOLVE + VERIFY PROVENANCE ────────────────────────────
      - name: Resolve the digest CI published
        id: digest
        if: steps.freeze.outputs.proceed == 'true'
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          set -euo pipefail
          RAW="${{ inputs.image }}"
          if [ -z "$RAW" ]; then
            RUN_ID="${{ github.event.workflow_run.id }}"
            gh run download "$RUN_ID" -n image-digest -D /tmp/dl
            RAW=$(cat /tmp/dl/digest.txt)
            SHA="${{ github.event.workflow_run.head_sha }}"
          else
            SHA="manual"
          fi
          [[ "$RAW" =~ ^[a-z0-9._/-]+@sha256:[0-9a-f]{64}$ ]] \
            || { echo "::error::not a digest: $RAW"; exit 1; }

          cosign verify \
            --certificate-oidc-issuer=https://token.actions.githubusercontent.com \
            --certificate-identity-regexp="^https://github.com/${{ github.repository }}/\.github/workflows/ci-checkout\.yml@" \
            "${RAW/@/:}" >/dev/null \
            || { echo "::error::provenance verification failed"; exit 1; }

          echo "✅ G1 passed: $RAW"
          echo "image=${RAW%@*}"  >> "$GITHUB_OUTPUT"
          echo "digest=${RAW#*@}" >> "$GITHUB_OUTPUT"
          echo "sha=$SHA"         >> "$GITHUB_OUTPUT"

      # ── ⭐⭐ G4c · IS THIS DIGEST ALREADY IN PRODUCTION? ────────────
      - name: Skip if production already runs this digest
        if: steps.digest.outcome == 'success'
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          set -euo pipefail
          PREV=$(gh api repos/${{ github.repository }}/deployments \
                  --jq '[.[]|select(.environment=="production")][0].statuses_url' || true)
          # simpler + more reliable: read it from the cluster in the deploy job.
          # ⭐ the point is IDEMPOTENCY: re-running CD on the same digest must
          #   be a no-op, not a second rollout.
          echo "ℹ️ idempotency is enforced in the deploy step (set image is a no-op if unchanged)"

  # ═════════════════════════════════════════════════════════════════════
  #  DEV — automatic, GATE not report
  # ═════════════════════════════════════════════════════════════════════
  dev:
    name: '1 · dev + verify'
    needs: gate
    if: needs.gate.outputs.proceed == 'true'
    runs-on: ubuntu-latest
    environment: dev                    # ⭐ no reviewers — Case 2
    steps:
      - uses: actions/checkout@v7
      - uses: azure/setup-kubectl@v4
        with: { version: 'v1.34.0' }
      - name: Auth
        run: |
          mkdir -p ~/.kube
          echo "${{ secrets.KUBECONFIG_DEV }}" | base64 -d > ~/.kube/config
      - uses: ./.github/actions/k8s-deploy-and-verify
        with:
          namespace: shop-dev
          service:   ${{ env.SERVICE }}
          image-ref: ${{ needs.gate.outputs.image }}@${{ needs.gate.outputs.digest }}
          probe:     /readyz
          # ⭐ in Case 2 a failed verify FAILS THE WORKFLOW. There is no human
          #   downstream to interpret a warning.

  # ═════════════════════════════════════════════════════════════════════
  #  STAGING — automatic, GATE
  # ═════════════════════════════════════════════════════════════════════
  staging:
    name: '2 · staging + verify'
    needs: [gate, dev]
    runs-on: ubuntu-latest
    environment: staging
    outputs:
      baseline: ${{ steps.baseline.outputs.baseline }}
    steps:
      - uses: actions/checkout@v7
      - uses: azure/setup-kubectl@v4
        with: { version: 'v1.34.0' }
      - name: Auth
        run: |
          mkdir -p ~/.kube
          echo "${{ secrets.KUBECONFIG_STAGING }}" | base64 -d > ~/.kube/config
      - uses: ./.github/actions/k8s-deploy-and-verify
        with:
          namespace: shop-staging
          service:   ${{ env.SERVICE }}
          image-ref: ${{ needs.gate.outputs.image }}@${{ needs.gate.outputs.digest }}
          probe:     /readyz
      # ── ⭐ CAPTURE THE BASELINE the canary will be compared against ──
      - name: Record the pre-deploy baseline
        id: baseline
        run: |
          set -euo pipefail
          ./scripts/metrics.sh shop-staging 15m > baseline.json
          echo "baseline=$(cat baseline.json)" >> "$GITHUB_OUTPUT"
          cat baseline.json

  # ═════════════════════════════════════════════════════════════════════
  #  ⭐ CANARY — the heart of Case 2
  # ═════════════════════════════════════════════════════════════════════
  canary:
    name: '3 · canary 10% + analyse'
    needs: [gate, staging]
    runs-on: ubuntu-latest
    environment: canary                 # ⭐ its own environment → its own secrets
    outputs:
      verdict: ${{ steps.analyse.outputs.verdict }}
    steps:
      - uses: actions/checkout@v7
      - uses: azure/setup-kubectl@v4
        with: { version: 'v1.34.0' }
      - name: Auth to production (canary runs IN production)
        run: |
          mkdir -p ~/.kube
          echo "${{ secrets.KUBECONFIG_PROD }}" | base64 -d > ~/.kube/config

      # ── ⭐⭐ THE CANARY IS AN ARGO ROLLOUT, NOT A SECOND DEPLOYMENT ───
      - name: Start the canary
        run: |
          set -euo pipefail
          REF="${{ needs.gate.outputs.image }}@${{ needs.gate.outputs.digest }}"
          # Argo Rollouts does the traffic split; see 04-docker-and-k8s-targets.md
          kubectl argo rollouts set image checkout checkout="$REF" \
            -n shop-production --watch=false
          kubectl argo rollouts promote checkout -n shop-production --full=false || true
          # ⭐ the Rollout spec pauses here at 10% until we promote again
          kubectl argo rollouts get rollout checkout -n shop-production --watch \
            --timeout 180 || true

      # ── G3 · ANALYSE FOR N MINUTES ──────────────────────────────────
      - name: Analyse the canary against the baseline
        id: analyse
        run: |
          set -euo pipefail
          echo "⏱️  soaking ${CANARY_SOAK_MINUTES}m at ${CANARY_WEIGHT}% traffic"
          sleep $(( CANARY_SOAK_MINUTES * 60 ))

          # ⭐⭐ BASELINE-AWARE, not fixed thresholds — see §5
          ./scripts/analyse-canary.sh \
            --namespace shop-production \
            --canary-label  rollouts-pod-template-hash \
            --window "${CANARY_SOAK_MINUTES}m" \
            --baseline '${{ needs.staging.outputs.baseline }}' \
            --max-err-ratio-delta 0.005 \
            --max-p99-ratio      1.5 \
            --min-requests       200 \
            | tee analysis.json
          VERDICT=$(jq -r .verdict analysis.json)
          echo "verdict=$VERDICT" >> "$GITHUB_OUTPUT"
          echo "$VERDICT"

      # ── ⛔ AUTOMATIC ROLLBACK ON A BAD VERDICT ──────────────────────
      - name: Roll back the canary if the analysis failed
        if: steps.analyse.outputs.verdict != 'PASS'
        run: |
          set -euo pipefail
          echo "⛔ canary verdict: ${{ steps.analyse.outputs.verdict }} — aborting"
          kubectl argo rollouts abort checkout -n shop-production
          # ⭐ `abort` returns traffic to the stable ReplicaSet immediately
          curl -fsS -X POST "${{ secrets.SLACK_WEBHOOK }}" -H 'content-type: application/json' -d @- <<EOF
          {"text":"🚨 *checkout canary ABORTED* — digest \`${{ needs.gate.outputs.digest }}\`\nVerdict: ${{ steps.analyse.outputs.verdict }}\nAnalysis:\n\`\`\`$(cat analysis.json)\`\`\`\n${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}"}
          EOF

      - name: Promote the canary to 100%
        if: steps.analyse.outputs.verdict == 'PASS'
        run: |
          kubectl argo rollouts promote checkout -n shop-production --full=true
          kubectl argo rollouts get rollout checkout -n shop-production --watch --timeout 600

  # ═════════════════════════════════════════════════════════════════════
  #  PRODUCTION — automatic, after the canary
  # ═════════════════════════════════════════════════════════════════════
  production:
    name: '4 · production + verify'
    needs: [gate, canary]
    if: needs.canary.outputs.verdict == 'PASS'
    runs-on: ubuntu-latest
    environment: production             # ⭐⭐ NO REVIEWERS. The canary is the gate.
    steps:
      - uses: actions/checkout@v7
      - uses: azure/setup-kubectl@v4
        with: { version: 'v1.34.0' }
      - name: Auth
        run: |
          mkdir -p ~/.kube
          echo "${{ secrets.KUBECONFIG_PROD }}" | base64 -d > ~/.kube/config
      # ── G5 · POST-PRODUCTION VERIFICATION ───────────────────────────
      - name: Verify production for 10 minutes
        run: |
          set -euo pipefail
          END=$(( $(date +%s) + 600 ))
          FAILS=0
          while [ "$(date +%s)" -lt "$END" ]; do
            if ! ./scripts/smoke.sh shop-production checkout /readyz; then FAILS=$((FAILS+1)); fi
            ERR=$(./scripts/err-ratio.sh shop-production checkout 5m)
            if (( $(echo "$ERR > 0.01" | bc -l) )); then FAILS=$((FAILS+1)); fi
            [ "$FAILS" -ge 3 ] && { echo "::error::3 failed checks — rolling back"; exit 1; }
            sleep 60
          done
          echo "✅ production stable for 10 minutes"

  # ═════════════════════════════════════════════════════════════════════
  #  ⭐⭐ ROLLBACK — a JOB, not a separate workflow
  # ═════════════════════════════════════════════════════════════════════
  rollback:
    name: '🚨 automatic rollback'
    needs: [gate, dev, staging, canary, production]
    if: always() && (needs.production.result == 'failure' || needs.canary.result == 'failure')
    runs-on: ubuntu-latest
    environment: production
    steps:
      - uses: actions/checkout@v7
      - uses: azure/setup-kubectl@v4
        with: { version: 'v1.34.0' }
      - name: Auth
        run: |
          mkdir -p ~/.kube
          echo "${{ secrets.KUBECONFIG_PROD }}" | base64 -d > ~/.kube/config
      - name: Return to the last known-good digest
        run: |
          set -euo pipefail
          kubectl argo rollouts undo checkout -n shop-production || \
            kubectl -n shop-production rollout undo deploy/checkout
          kubectl -n shop-production rollout status deploy/checkout --timeout=300s || true
          NOW=$(kubectl -n shop-production get rollout checkout \
                -o jsonpath='{.status.stableRS}')
          echo "✅ rolled back to stable ReplicaSet $NOW"
      # ── ⭐⭐ HALT FURTHER RELEASES ──────────────────────────────────
      - name: Set the circuit breaker
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          set -euo pipefail
          # ⭐ a committed flag file in a `cd-state` branch/repo. The `gate`
          #   job reads it and refuses to promote while it is set.
          #   WHY: without this, the NEXT commit re-triggers CD, hits the same
          #   failure, rolls back, and pages you again — forever.
          gh api -X PUT repos/${{ github.repository }}/contents/cd-state/HALTED \
            -f message="🚨 halt CD after failed checkout promotion" \
            -f content="$(printf 'halted by run %s\n' "$GITHUB_RUN_ID" | base64 -w0)" \
            -f branch=main || true
          curl -fsS -X POST "${{ secrets.PAGERDUTY_URL }}" -H 'content-type: application/json' -d @- <<EOF
          {"routing_key":"${{ secrets.PD_ROUTING_KEY }}","event_action":"trigger",
           "payload":{"summary":"🚨 checkout CD auto-rolled back — further promotions HALTED",
                      "severity":"critical","source":"github-actions",
                      "custom_details":{"digest":"${{ needs.gate.outputs.digest }}",
                                        "run":"${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}"}}}
          EOF
      - name: Clear the breaker automatically after a soak
        run: |
          echo "ℹ️ the HALT flag is cleared by a human, or by a scheduled workflow"
          echo "   after 4h with no further failures — NEVER by this job."
          # ⭐⭐ clearing your own circuit breaker defeats the purpose.

  # ═════════════════════════════════════════════════════════════════════
  #  RECORD
  # ═════════════════════════════════════════════════════════════════════
  record:
    name: '5 · record the deployment'
    needs: [gate, production]
    if: always() && needs.gate.outputs.proceed == 'true'
    runs-on: ubuntu-latest
    environment: production
    steps:
      - name: Create a GitHub deployment record
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          set -euo pipefail
          STATE=$([ "${{ needs.production.result }}" = "success" ] && echo success || echo failure)
          DEP=$(gh api repos/${{ github.repository }}/deployments \
            -f ref="${{ needs.gate.outputs.sha }}" \
            -f environment=production \
            -f description="checkout ${{ needs.gate.outputs.digest }}" \
            -F auto_merge=false -F required_contexts='[]' --jq .id)
          gh api repos/${{ github.repository }}/deployments/$DEP/statuses \
            -f state="$STATE" \
            -f description="CD run ${{ github.run_id }}" \
            -f environment_url="https://checkout.shop/" >/dev/null
          echo "✅ deployment $DEP recorded as $STATE"
```

### 4.1 The composite action both cases share

`.github/actions/k8s-deploy-and-verify/action.yml`

```yaml
name: 'Deploy a digest and verify it'
description: '⭐ set image → wait → READ BACK → smoke from inside the cluster'
inputs:
  namespace: { required: true }
  service:   { required: true }
  image-ref: { required: true }
  probe:     { required: false, default: '/healthz' }
  timeout:   { required: false, default: '300s' }
runs:
  using: composite
  steps:
    - name: Deploy
      shell: bash
      run: |
        set -euo pipefail
        NS='${{ inputs.namespace }}'; SVC='${{ inputs.service }}'
        REF='${{ inputs.image-ref }}'
        [[ "$REF" =~ @[a-z0-9]+:[0-9a-f]{64}$ ]] || { echo "::error::not a digest"; exit 1; }
        PREV=$(kubectl -n $NS get deploy $SVC \
               -o jsonpath="{.spec.template.spec.containers[?(@.name=='$SVC')].image}")
        echo "PREV=$PREV" >> "$GITHUB_ENV"          # ⭐ recorded = rollback target
        [ "$PREV" = "$REF" ] && { echo "ℹ️ already running $REF — no-op"; exit 0; }
        kubectl -n $NS set image deploy/$SVC $SVC="$REF"
        kubectl -n $NS rollout status deploy/$SVC --timeout='${{ inputs.timeout }}' \
          || { kubectl -n $NS set image deploy/$SVC $SVC="$PREV"; exit 1; }
        # ⭐⭐ READ IT BACK — a deploy tool's exit code is not proof
        NOW=$(kubectl -n $NS get deploy $SVC \
              -o jsonpath="{.spec.template.spec.containers[?(@.name=='$SVC')].image}")
        [ "$NOW" = "$REF" ] || { echo "::error::running $NOW, wanted $REF"; exit 1; }
    - name: Smoke from INSIDE the cluster
      shell: bash
      run: |
        set -euo pipefail
        NS='${{ inputs.namespace }}'; SVC='${{ inputs.service }}'
        kubectl -n $NS run smoke-$RANDOM --rm -i --restart=Never \
          --image=curlimages/curl:8.17.0 -- \
          curl -fsS "http://$SVC.$NS.svc.cluster.local:9091${{ inputs.probe }}"
        # ⭐ from INSIDE: tests the Service selector and the endpoints, which
        #   an external curl through the ingress cannot isolate.
```

---

## 5 · ⭐⭐ Baseline-aware analysis — why fixed thresholds fail

```
⛔ FIXED THRESHOLD:  alert if 5xx ratio > 1%

   Mon 09:00  traffic ×8   → 1% of 8× traffic = 8× the errors  → PAGES
   Tue 03:00  traffic ÷20  → a 100% outage of a rarely-used endpoint
                             is 0.2% overall                    → SLEEPS

   ⭐ BOTH FAILURE MODES ARE REAL, AND THEY HAPPEN IN THE SAME WEEK.
```

### What to compare instead

| Signal | ⭐ Comparison | Why |
|---|---|---|
| Error ratio | canary vs **stable**, same window | ⭐ the best comparison available — same traffic, same hour, same day |
| p99 latency | canary ÷ stable, ratio ≤ 1.5 | ratios survive load changes; absolutes do not |
| Saturation (CPU, mem, goroutines) | canary vs stable | a memory leak shows here first |
| Business metric (orders/min) | ⭐ canary vs **the same hour last week** | there is no "stable" equivalent for a new feature |
| ⭐ **Minimum sample size** | `requests ≥ 200` | below this, ratios are noise |

```bash
#!/usr/bin/env bash
# scripts/analyse-canary.sh — ⭐ the whole Case 2 decision, in one script
set -euo pipefail
NS=shop-production; WINDOW=10m
CANARY_SEL='app=checkout,rollouts-pod-template-hash!=stable'
STABLE_SEL='app=checkout,rollouts-pod-template-hash=stable'

q() {  # $1 = pod selector, $2 = metric expression
  curl -fsS --data-urlencode "query=$2" "$PROM/prometheus/api/v1/query" \
    | jq -r '.data.result[0].value[1] // "0"'
}

C_REQ=$(q "$CANARY_SEL" "sum(rate(http_requests_total{ns=\"$NS\",pod=~\"$CANARY_SEL\"}[$WINDOW]))")
S_REQ=$(q "$STABLE_SEL" "sum(rate(http_requests_total{ns=\"$NS\",pod=~\"$STABLE_SEL\"}[$WINDOW]))")
C_ERR=$(q "$CANARY_SEL" "sum(rate(http_requests_total{ns=\"$NS\",status=~\"5..\",pod=~\"$CANARY_SEL\"}[$WINDOW]))")
S_ERR=$(q "$STABLE_SEL" "sum(rate(http_requests_total{ns=\"$NS\",status=~\"5..\",pod=~\"$STABLE_SEL\"}[$WINDOW]))")
C_P99=$(q "$CANARY_SEL" "histogram_quantile(0.99,sum(rate(http_request_duration_seconds_bucket{pod=~\"$CANARY_SEL\"}[$WINDOW])) by (le))")
S_P99=$(q "$STABLE_SEL" "histogram_quantile(0.99,sum(rate(http_request_duration_seconds_bucket{pod=~\"$STABLE_SEL\"}[$WINDOW])) by (le))")

MIN_REQ=${MIN_REQUESTS:-200}
TOTAL=$(echo "$C_REQ * ${WINDOW%s} * 60" | bc -l | cut -d. -f1)

# ── ⭐⭐ GATE 0: IS THERE ENOUGH SIGNAL? ──────────────────────────────
if [ "${TOTAL:-0}" -lt "$MIN_REQ" ]; then
  jq -n --arg v INCONCLUSIVE --arg r "only $TOTAL requests in ${WINDOW} (need $MIN_REQ)" \
        '{verdict:$v,reason:$r}'
  # ⭐⭐ THE POLICY DECISION: what does INCONCLUSIVE mean?
  #   For a stateless Go service with a canary: FAIL CLOSED → abort.
  #   The alternative (fail open) means low-traffic services are never
  #   actually analysed — which is Case 2 in name only.
  exit 0
fi

C_RATE=$(echo "scale=6; $C_ERR / ($C_REQ + 0.000001)" | bc -l)
S_RATE=$(echo "scale=6; $S_ERR / ($S_REQ + 0.000001)" | bc -l)
DELTA=$(echo "$C_RATE - $S_RATE" | bc -l)
RATIO=$(echo "scale=4; $C_P99 / ($S_P99 + 0.000001)" | bc -l)

VERDICT=PASS; REASON="err delta $DELTA <= 0.005, p99 ratio $RATIO <= 1.5"
if (( $(echo "$DELTA > 0.005" | bc -l) )); then VERDICT=FAIL; REASON="error-rate delta $DELTA > 0.005"; fi
if (( $(echo "$RATIO > 1.5"   | bc -l) )); then VERDICT=FAIL; REASON="p99 ratio $RATIO > 1.5"; fi

jq -n --arg v "$VERDICT" --arg r "$REASON" \
      --argjson canaryErr "$C_RATE" --argjson stableErr "$S_RATE" \
      --argjson p99ratio "$RATIO" --argjson requests "$TOTAL" \
      '{verdict:$v,reason:$r,canaryErrRate:$canaryErr,stableErrRate:$stableErr,
        p99Ratio:$p99ratio,requests:$requests}'
```

⭐⭐ **The `INCONCLUSIVE` branch is the most important line in this file.** For a low-traffic service, an analysis with 40 samples is not weak — it is **meaningless**. You must choose a policy: **fail closed** (abort the canary; safe but blocks low-traffic services from Case 2 entirely) or **fail open** (promote; which means those services are never really analysed). ⭐ **Fail closed, and then move low-traffic services back to Case 1** — that is the honest configuration.

---

## 6 · ⭐⭐ Automatic rollback **and halting further releases**

Two mechanisms. **Both, or Case 2 pages you in a loop.**

### 6.1 Rollback

| Layer | Mechanism | Speed |
|---|---|---|
| ⭐ Argo Rollouts `abort` | returns traffic to the stable ReplicaSet | **seconds** — the stable pods are still running |
| Argo Rollouts `undo` | creates a new step back in history | ~30 s |
| `kubectl rollout undo` | previous ReplicaSet | ~60 s |
| ⭐ `set image` to the **recorded** digest | explicit, unambiguous | ~60 s |

```
⭐ WHY `abort` IS SO MUCH BETTER THAN `undo`:
   during a canary the STABLE pods never went away. `abort` just moves the
   traffic weight back to 0% for the canary. No scheduling, no image pull,
   no start-up, no warm-up. It is the fastest rollback that exists, and it
   is the main operational argument for progressive delivery.
```

### 6.2 ⭐⭐ Halting further releases — the circuit breaker

```
WITHOUT A BREAKER:
   commit A → CD → canary fails → rollback → PAGE 🔔
   commit B → CD → canary fails → rollback → PAGE 🔔
   commit C → CD → canary fails → rollback → PAGE 🔔
   ⛔ you are paged every 20 minutes, and the failure is not fixed.

WITH A BREAKER:
   commit A → CD → canary fails → rollback → PAGE 🔔 + SET HALT
   commit B → CD → gate sees HALT → exits 0, promotes nothing
   commit C → same
   ⭐ ONE page. The queue drains when a human clears the flag.
```

```yaml
# in the `gate` job, before anything else
- name: Check the circuit breaker
  id: breaker
  run: |
    set -euo pipefail
    if gh api repos/${{ github.repository }}/contents/cd-state/HALTED >/dev/null 2>&1; then
      echo "🛑 CD is HALTED — not promoting. Clear cd-state/HALTED to resume."
      echo "proceed=false" >> "$GITHUB_OUTPUT"
    fi
  env: { GH_TOKEN: "${{ secrets.GITHUB_TOKEN }}" }
```

| Rule | Why |
|---|---|
| ⭐⭐ **The breaker is never cleared by the job that set it** | clearing your own circuit breaker defeats the purpose |
| It can be cleared by a human, or by a scheduled workflow after a soak | ⭐ a scheduled clear with a "no failures in 4h" condition is a reasonable middle ground |
| It is **visible** — a file in the repo, not a variable in a UI | `git log cd-state/HALTED` is the history of every halt |
| Halting produces **one** page, not N | that is the entire point |

---

## 7 · The freeze calendar

`freezes.yaml` — ⭐ committed, reviewed, and versioned.

```yaml
# ═══════════════════════════════════════════════════════════════════════
#  WHAT : windows during which CD must NOT promote to production.
#  WHY  : Case 1's human also decided "is now a good time?". In Case 2 that
#         judgement has to be encoded, or the pipeline deploys into an
#         incident and makes it worse.
# ═══════════════════════════════════════════════════════════════════════
windows:
  - name: year-end freeze
    from: 2026-12-18T00:00:00Z
    to:   2027-01-05T00:00:00Z
    reason: peak trading; on-call skeleton crew
  - name: sale weekend
    from: 2026-11-27T00:00:00Z
    to:   2026-11-30T23:59:59Z
    reason: Black Friday
recurring:
  - name: out of hours
    days: [sat, sun]                      # ⭐ weekends
    reason: nobody is watching a dashboard
  - name: quiet hours
    daily_from: "22:00"
    daily_to:   "07:00"
    tz: Europe/London
    reason: a regression at 02:00 is found by users, not by us
exceptions:
  - label: hotfix                        # ⭐ a manual override, applied via
    allow: true                          #   workflow_dispatch + a label
```

```bash
#!/usr/bin/env bash
# scripts/in-freeze-window.sh  ·  $1 = RFC3339 timestamp
set -euo pipefail
NOW="$1"
yq -r '.windows[] | "\(.from) \(.to) \(.name)"' freezes.yaml | while read -r F T N; do
  if [[ "$NOW" > "$F" && "$NOW" < "$T" ]]; then echo "🧊 in freeze: $N"; exit 0; fi
done
DOW=$(date -u -d "$NOW" +%a | tr 'A-Z' 'a-z')
yq -r '.recurring[] | select(.days) | .days[]' freezes.yaml | grep -qx "$DOW" \
  && { echo "🧊 weekend freeze"; exit 0; }
exit 1     # ⭐ not frozen
```

⭐ **Two design points:** the calendar lives in **git**, so changing it is a reviewed PR rather than a UI click nobody remembers; and hitting a freeze makes the workflow **exit 0 having done nothing**, so you do not accumulate red builds that train people to ignore red builds.

---

## 8 · `deployment_status` and the GitHub deployment API

| Object | What it is | ⭐ Why Case 2 needs it |
|---|---|---|
| **Environment** | a named target with scoped secrets | still used — for **secret scoping**, not for approval |
| **Deployment** | "this ref was deployed to this environment" | the durable record of *what* went where |
| **Deployment status** | `pending` / `in_progress` / `success` / `failure` | ⭐ the machine-readable state other systems can react to |
| `deployment_status` event | a webhook fired on status change | ⭐ lets a *different* workflow react — e.g. post-deploy analysis |

```yaml
# ⭐ a SEPARATE workflow that reacts to production deployments
on:
  deployment_status: {}
jobs:
  post-deploy-analysis:
    if: >
      github.event.deployment_status.environment == 'production' &&
      github.event.deployment_status.state == 'success'
    runs-on: ubuntu-latest
    steps:
      - name: Watch metrics for 30 minutes after the deployment
        run: |
          ./scripts/analyse-canary.sh --window 30m --full-rollout true \
            || { echo "::error::post-deploy regression detected"; \
                 gh workflow run rollback-checkout.yml; exit 1; }
```

⭐ **Why split it out:** the CD workflow's own verify window is bounded by how long you are willing to hold a runner. A 30-minute post-deploy watch is better as a separate, `deployment_status`-triggered workflow — it does not block promotion, and it can still trigger a rollback.

---

## 9 · Per app shape — which services should be Case 2 at all

⭐⭐ **The correct answer for most estates is a mix.** Do not apply one policy to everything.

| Service | Shape | ⭐ Case | Why |
|---|---|---|---|
| `shop-ui` | 🔵 FE | 🤖 **Case 2** | no state, no schema, instant rollback. **Highest change frequency**, so the highest payoff |
| `payment-mock` | 🟢 BE | 🤖 **Case 2 — the pilot** | lowest risk in the estate. Prove the machinery here |
| `checkout` | 🟢 BE | 🤖 **Case 2** | this file. Stateless Go, `/readyz`, enough traffic |
| `order-worker` | 🟢 BE | 🔒 **Case 1** | in-flight messages, no HTTP probe, hard to canary |
| `shop-api` | 🟢 BE | 🔒 **Case 1** until migrations are expand/contract | the schema is the irreversible part |
| P10 FE+BE | 🟡 | ⭐ **split** — FE Case 2, BE Case 1 | one policy for both forces the FE to inherit the BE's risk |
| P13 data tier | 🗄️ | 🔒 **Case 1, permanently** | a data-directory upgrade is not reversible |

```
⭐ THE POLICY, STATED AS A RULE:
   Case 2 applies to a SERVICE, not to an organisation.
   The deciding question is: "is this service's deploy REVERSIBLE, and can
   its regression be DETECTED from metrics within the canary window?"
   Both yes → Case 2. Either no → Case 1.
```

---

## 10 · ▶️ Run it and prove it — the Case 2 acceptance checks

```bash
W=.github/workflows/cd-checkout.yml

# 1 · NO human gate
grep -n 'workflow_dispatch' $W >/dev/null && echo "ℹ️ manual override exists (OK)"
gh api repos/ORG/shop/environments/production --jq '.protection_rules[].type'
# ⭐ must NOT contain required_reviewers

# 2 · it triggers automatically on CI success
grep -n 'workflow_run' $W && echo "✅ automatic"

# 3 · NO build step
grep -nE 'docker build|go build|mvn|npm ci' $W && echo "⛔ CD builds" || echo "✅ CD does not build"

# 4 · a failed smoke test FAILS the workflow (not just warns)
grep -n 'continue-on-error' $W && echo "⛔ a gate is decorative" || echo "✅ gates are real"

# 5 · automatic rollback exists IN this workflow
grep -n 'argo rollouts abort\|rollout undo' $W && echo "✅ auto-rollback"

# 6 · ⭐⭐ the circuit breaker exists
grep -n 'cd-state/HALTED' $W && echo "✅ halts further releases"

# 7 · the freeze calendar is committed and read
test -f freezes.yaml && grep -n 'in-freeze-window.sh' $W && echo "✅ freeze-aware"

# 8 · ⭐ THE DRILL: deploy a deliberately bad digest and watch it self-heal
#    build an image whose /readyz returns 500, push it, let CI publish it,
#    and confirm: canary starts → analysis returns FAIL → `abort` runs →
#    stable pods serve 100% → ONE page → cd-state/HALTED exists.
kubectl -n shop-production get rollout checkout -o jsonpath='{.status.abort}{"\n"}'
gh api repos/ORG/shop/contents/cd-state/HALTED --jq .name

# 9 · ⭐ clear the breaker and confirm CD resumes
gh api -X DELETE repos/ORG/shop/contents/cd-state/HALTED -f message='resume CD' -f sha=<SHA>

# 10 · what is running, one command
kubectl -n shop-production get rollout checkout \
  -o jsonpath='{.status.stableRS}{"\n"}'
```

⭐⭐ **Check 8 is the only one that proves anything.** Everything else is a grep. The drill — a deliberately bad digest, watched end to end — is what tells you whether your analysis actually fires, whether `abort` actually restores traffic, and whether you get **one** page or five. Do it in staging first, then in production during a quiet window. **A Case 2 pipeline that has never rolled itself back is untested.**

---

## 11 · Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| CD never triggers | ⛔ `workflow_run` only uses files on the **default branch** | merge the CD workflow to `main` |
| CD triggers on failed CI | `types: [completed]` includes failures | the `conclusion == 'success'` condition (§2) |
| `github.ref` is wrong | in `workflow_run`, `github.ref` is the default branch | `github.event.workflow_run.head_branch` (§2) |
| ⭐ The canary gets no traffic | the Rollout's `trafficRouting` is not configured, or the Service selector matches both ReplicaSets | [`04-docker-and-k8s-targets.md`](./04-docker-and-k8s-targets.md) §3 |
| Analysis always `INCONCLUSIVE` | traffic too low for the window | ⭐ extend the window, or **move the service to Case 1** (§5) |
| Analysis pages every Monday | fixed thresholds, not baseline-aware | §5 |
| ⛔ Paged five times in an hour | no circuit breaker | §6.2 |
| The breaker never clears | the clearing job is manual and nobody knows | ⭐ add a scheduled workflow with a "no failures in 4h" condition |
| Deploys during the freeze | the freeze check exits non-zero and the job is `if: failure()`-skipped | the freeze must `exit 0` with `proceed=false` (§7) |
| `abort` leaves the canary running | `abort` stops the *rollout*; the canary pods scale down on their own | verify with `kubectl argo rollouts get rollout --watch` |
| Two promotions at once | no `concurrency:` group | §4 |
| ⭐ Rollback fails because the old image was garbage-collected | registry retention policy deleted it | ⭐ keep the last N digests **and** the last N ReplicaSets (`revisionHistoryLimit`) |

---

<a name="tasks--answers"></a>
## 12 · ⭐ TASKS — answers at the END

| # | Task |
|---|---|
| **T1** | Convert the Case 1 GitHub Actions pipeline into Case 2 by making exactly the six changes in §1 — and list them |
| **T2** | Wire `workflow_run` correctly, handling all four traps |
| **T3** | Write `analyse-canary.sh` comparing canary against **stable** rather than against a fixed threshold |
| **T4** | Decide and implement the `INCONCLUSIVE` policy for a service with 40 requests per 10 minutes |
| **T5** | Add automatic rollback via `argo rollouts abort` and prove it restores traffic in seconds |
| **T6** | Implement the circuit breaker, and prove that five failing commits produce **one** page |
| **T7** | Write `freezes.yaml` + `in-freeze-window.sh` so a freeze produces a **green** run that deploys nothing |
| **T8** | Add a `deployment_status`-triggered 30-minute post-deploy watch in a separate workflow |
| **T9** | Decide the Case for each of the five `shop` services and justify each in one sentence |
| **T10** | ⭐⭐ Run the full drill: a deliberately bad digest, end to end. Write down what you observed at each of the seven steps, and name the one thing you would change |

---

# ✅ ANSWERS

**T1.** The six changes, mapped to the Case 1 file:
1. **Trigger:** `on: workflow_dispatch:` → `on: workflow_run: { workflows: ['CI · checkout'], types: [completed] }`, keeping `workflow_dispatch` as a manual override.
2. **Environment:** remove **Required reviewers** from `production` — the gate is now the checks. ⭐ Keep the environment itself: it still scopes secrets, which is the security property.
3. **Staging verify:** the report-writing step becomes a **gate** — remove `continue-on-error`, and let a failure fail the job. In Case 1 it informed a human; in Case 2 it must decide.
4. **Add a canary stage** between staging and production, with a soak and an analysis step.
5. **Rollback moves inside the workflow** as a job with `if: always() && (needs.production.result == 'failure' || needs.canary.result == 'failure')`, rather than a separate manually-triggered workflow.
6. **Add the circuit breaker** — a `cd-state/HALTED` check in `gate` and a set in `rollback`.
⭐ Plus one that is easy to miss: `permissions:` needs `deployments: write` for the deployment API, which Case 1 did not use.

**T2.** §2. `on: workflow_run: { workflows: ['CI · checkout'], types: [completed], branches: [main] }` — where `workflows:` matches the CI workflow's **`name:`**, not its filename (⭐ a rename silently breaks the trigger; matching on the file is not supported). Then the four traps: **(1)** `types: [completed]` fires on failure too, so the first job needs `if: github.event.workflow_run.conclusion == 'success'`; **(2)** `workflow_run` only evaluates workflow files **on the default branch**, so the CD file must be merged before it can trigger anything — which is why testing it on a branch appears to do nothing; **(3)** `github.ref` is the default branch, not the triggering ref, so use `github.event.workflow_run.head_branch` and `.head_sha`; **(4)** `GITHUB_TOKEN` in this context is restricted on private repos, so declare `permissions:` explicitly. ⭐ The payoff for using `workflow_run` at all: `github.event.workflow_run.id` lets you `gh run download` **exactly** the artifact CI produced, which is the digest contract enforced structurally rather than by convention.

**T3.** §5. The key decision is the **comparison**: canary pods versus **stable pods in the same namespace over the same window** — not canary versus a fixed number. That is the strongest signal available, because both cohorts see the same traffic mix, the same hour, the same day-of-week and the same dependencies; the only difference is the code. Concretely: select by `rollouts-pod-template-hash`, compute `rate(http_requests_total{status=~"5.."}[10m]) / rate(http_requests_total[10m])` for each cohort, and fail if the **delta** exceeds 0.005; for latency use the **ratio** of p99s (≤ 1.5) rather than an absolute, because ratios survive load changes while absolutes do not. ⭐ Why fixed thresholds fail in both directions at once: Monday 09:00 traffic is 8× normal, so 1% of it is 8× the errors and the threshold pages on a healthy release; Tuesday 03:00 traffic is 1/20th, so a 100% outage of one endpoint is 0.2% overall and the threshold sleeps through a real regression. Both happen in the same week.

**T4.** ⭐ **Decision: fail closed — `INCONCLUSIVE` aborts the canary.** Implementation: compute `TOTAL = rate × window_seconds`, and if `TOTAL < 200`, emit `verdict: INCONCLUSIVE` with the reason, which the workflow treats exactly like `FAIL`. **Then move the service to Case 1**, and say why: with 40 requests in the window, one failure is 2.5% and two is 5% — the gate cannot distinguish a regression from noise, so it is not a gate. Failing *open* would mean low-traffic services are promoted without analysis, which is Case 2 in name only and worse than Case 1 because nobody is looking. Failing closed is safe but means those services never promote automatically — which is the correct outcome, and the signal that they belong in [`../case-1-continuous-delivery/README.md`](../case-1-continuous-delivery/README.md). ⭐ **The third option worth considering before giving up:** extend the window to 60 minutes (~240 requests) and switch from a *rate* gate to a *count* gate ("any 5xx in the canary halts"). That is a real gate for low volume — just a slower one.

**T5.** §4's canary job + §6.1. `kubectl argo rollouts abort checkout -n shop-production` on a non-`PASS` verdict. **Why it is seconds rather than minutes:** during a canary the **stable pods never went away** — the Rollout keeps the old ReplicaSet at full size and shifts *traffic weight*, not pod count. `abort` sets the canary weight back to 0, so the stable pods that are already running, already warm and already in the endpoint list take 100% of traffic immediately. No scheduling, no image pull, no JVM warm-up, no readiness wait. ⭐ **That is the real operational argument for progressive delivery** — not "canaries are safer" in the abstract, but *recovery is measured in seconds instead of minutes*, which is what makes prerequisite 1 ("reversible in < 15 min") trivially true. **Proving it:** run the drill in T10 and time from `abort` to the first request served only by stable pods; it should be under 10 s.

**T6.** §6.2. A committed file `cd-state/HALTED` in the repo; the `gate` job checks it with `gh api repos/.../contents/cd-state/HALTED` and sets `proceed=false` if it exists; the `rollback` job creates it with `gh api -X PUT .../contents/cd-state/HALTED` **and** fires the PagerDuty event. **Proving one page rather than five:** push five commits in a row, each producing a bad digest. The first run fails the canary, rolls back, pages once, and sets HALTED. Runs two through five enter `gate`, see HALTED, and **exit 0 having promoted nothing** — green runs, no pages. ⭐ Four rules make this correct: the breaker is **never cleared by the job that set it** (clearing your own circuit breaker defeats the purpose); it is cleared by a human or by a scheduled workflow conditioned on "no failures in 4h"; it lives in **git** so `git log cd-state/HALTED` is the history of every halt; and hitting it produces a **green** run, not a red one — because five red builds an hour is alert fatigue, and alert fatigue is how the next real failure gets missed.

**T7.** §7. `freezes.yaml` with absolute `windows` (year-end, sale weekend), `recurring` rules (weekends, 22:00–07:00 in a named timezone), and an `exceptions` list for labelled hotfixes. `in-freeze-window.sh` takes an RFC3339 timestamp and exits 0 if frozen, 1 otherwise. The workflow step then writes `proceed=false` and — critically — **`exit 0`**. ⭐ **Why green rather than red:** a freeze is a policy outcome, not a failure. If frozen runs are red, then during a three-week year-end freeze you accumulate fifteen red builds, and "the CD pipeline is red" stops meaning anything. The information still reaches people because the step logs `🧊 FREEZE in effect` and the run's conclusion is visible; if you want it louder, post a single Slack message the first time a freeze blocks a release, not every time. **Why the calendar is in git:** changing it becomes a reviewed PR with an author and a reason, instead of a UI toggle nobody remembers setting — and the `reason:` field on each window means the next person knows *why*, which is what stops someone deleting it "temporarily".

**T8.** §8. A separate workflow `on: deployment_status: {}` with `if: github.event.deployment_status.environment == 'production' && github.event.deployment_status.state == 'success'`, running the analysis script with `--window 30m --full-rollout true` and calling `gh workflow run rollback-checkout.yml` on failure. **That requires the CD workflow to create the deployment record first** (§4's `record` job: `POST /deployments` then `POST /deployments/{id}/statuses`). ⭐ **Why a separate workflow rather than a longer verify step in the CD job:** a runner held for 30 minutes post-deploy is expensive and, worse, it sits inside the `concurrency: cd-checkout-production` group — so a long verify **blocks the next release** for its whole duration. Splitting it means promotion completes, the group is released, and the watch runs alongside. It also gives you a clean separation: the CD workflow answers "did this deploy?", the watch answers "did this deploy *hold*?" — and those have different failure responses.

**T9.** §9, one sentence each:
- **`shop-ui`** → 🤖 **Case 2.** No state, no schema, rollback is instant, and it changes most often — so it has the highest payoff and the lowest risk.
- **`payment-mock`** → 🤖 **Case 2, and the pilot.** The lowest-consequence service in the estate, which makes it the correct place to prove canary, analysis, rollback and the circuit breaker.
- **`checkout`** → 🤖 **Case 2.** Stateless Go with a real `/readyz` and enough traffic for a 10-minute canary to be statistically meaningful.
- **`order-worker`** → 🔒 **Case 1.** It has in-flight messages, no HTTP health endpoint (a heartbeat file instead), and cannot be canaried by traffic weight — so prerequisite 3 fails.
- **`shop-api`** → 🔒 **Case 1** until migrations are genuinely expand/contract. The schema is the irreversible part, and prerequisite 5 is the one that gates Case 2.
- ⭐ **P10 (FE+BE together)** → **split them.** One policy for both forces the frontend to inherit the backend's risk, which is how a static-file app ends up needing a change-approval board.
- ⭐ **P13 (data tier)** → 🔒 **Case 1, permanently.** A data-directory upgrade is not reversible, so no amount of gate quality makes it automatable.

**T10.** ⭐⭐ **The drill** — build `checkout` with a `/readyz` that returns 500 (or a handler that panics on the smoke path), push it, let CI publish it, and watch. What you should observe:

1. **CI** goes green and publishes the digest artifact. ⭐ Note this is *correct* — CI's job is to prove the artifact builds and its tests pass, and a readiness endpoint returning 500 is a runtime property CI may well not check. **That gap is the first finding: a container whose readiness probe fails should be caught in CI, not in production.** ([Scenario 1 · shape B](../../scenario-1-ci-only/04-app-shapes-fe-be-fullstack.md))
2. **`gate`** passes: `conclusion == 'success'`, not frozen, no HALTED flag, `cosign verify` succeeds, digest shape valid.
3. **`dev`** — ⭐ **fails here**, at `rollout status --timeout`, because the new pods never become Ready. With `maxUnavailable: 0` the deployment is frozen with both ReplicaSets live, and the composite action's `|| { set image back to $PREV; exit 1; }` restores dev. **This is the correct and best outcome: the bad digest never reached staging.**
4. If you make the failure *subtle* instead (readiness fine, but 20% of requests 500), dev and staging pass their `/readyz` smoke check, and the **canary analysis** catches it: `canaryErrRate ≈ 0.20` vs `stableErrRate ≈ 0.00`, delta `0.20 > 0.005` → `verdict: FAIL`.
5. **`abort`** runs. Traffic returns to the stable pods in **under 10 seconds** — no scheduling, no pull, no warm-up (§6.1). `kubectl argo rollouts get rollout checkout` shows `Aborted`.
6. **One** Slack message and **one** PagerDuty event, and `cd-state/HALTED` now exists. The next three commits enter `gate`, see HALTED, and exit 0 without promoting (§6.2).
7. **Recovery:** a human reads the page, inspects `analysis.json` (attached to the Slack message), deletes HALTED with `gh api -X DELETE .../contents/cd-state/HALTED`, and CD resumes.

⭐ **The one thing to change:** add a **CI-side readiness check** — run the built image and probe its health endpoint before publishing the digest. Step 3 shows the CD pipeline catching a failure that CI could have caught for free, and every failure caught in CI is one that never consumes a canary window, a page, or a halt. **The general lesson: Case 2's gates are a safety net, not a substitute for CI. The stronger CI is, the less the canary has to do — and a canary that rarely fires is a canary nobody has tested.**

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish_Kumar_Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn: https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260
🔗 GitHub: https://github.com/3558Bhk

*Compare canary to stable, not to a number — and never clear your own circuit breaker.*

</div>
