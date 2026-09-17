# 🔄 SCENARIO 3 · THE GITOPS HANDOFF — ARGO CD
### Where Scenario 3 ends and K8s P14 begins: the pipeline writes a **digest into git**, and Argo CD makes the cluster match. Push vs pull, the three repo topologies, self-heal, drift, and why this is the strongest form of the artifact contract.

> **Apps:** all five — `shop-ui`, `shop-api`, `checkout`, `order-worker`, `payment-mock` — plus the P13 data tier, deployed by Helm (K8s P14).
> **Argo CD:** 3.x · **Helm:** 3.19 · **Kubernetes:** v1.37 "Garhwal"

---

## 📇 Contents

| § | What |
|---|---|
| [1](#1---why-gitops--push-versus-pull) | ⭐⭐ Why GitOps — push versus pull, and the credential argument again |
| [2](#2--what-changes-from-scenario-3-and-what-does-not) | What changes from Scenario 3, and what does not |
| [3](#3---the-three-repo-topologies) | ⭐ The three repo topologies — app repo, config repo, one repo |
| [4](#4--the-helm-chart-and-the-per-environment-values-files) | The Helm chart and the per-environment values files |
| [5](#5---the-image-updater-question) | ⭐⭐ The image-updater question — and the write-back pattern |
| [6](#6--ci-writes-the-digest-to-git--all-three-tools) | CI writes the digest to git — all three tools |
| [7](#7---cd-becomes-an-argo-cd-sync--the-four-checks-restated) | ⭐ CD becomes an Argo CD sync — the four checks, restated |
| [8](#8---self-heal-drift-and-the-gotcha-that-makes-it-dangerous) | ⭐⭐ Self-heal, drift, and the gotcha that makes it dangerous |
| [9](#9--the-application-manifests-and-the-applicationset) | The Application manifests and the ApplicationSet |
| [10](#10--️-run-it-end-to-end-on-kind) | ▶️ Run it end to end on kind — the acceptance checks |
| [11](#11--troubleshooting) | Troubleshooting |
| [12](#12---tasks--answers-at-the-end) | Tasks and answers — **answers at the END** |

---

## 1 · ⭐⭐ Why GitOps — push versus pull

```
PUSH (everything in Scenarios 1–3 so far)
   CD pipeline ──holds cluster-admin──▶ kubectl set image ──▶ cluster
   ⭐ The credential lives IN THE CI/CD SYSTEM.
   ⛔ Compromise the CI/CD system  → you have the cluster.
   ⛔ Compromise a runner/agent     → you have the cluster.
   ⛔ Anyone who can edit the pipeline can deploy ANYTHING, including an
      image that was never built by CI.
   ⛔ "What is running?" is answered by asking the cluster, and the cluster
      does not know WHY.

PULL (GitOps)
   CI ──writes a digest──▶ GIT ──(Argo CD polls/watches)──▶ cluster
   ⭐ The cluster reaches OUT. Nothing outside can reach IN.
   ✅ The credential that deploys lives INSIDE the cluster.
   ✅ Git is the audit log: who, what, when, why — with a diff and a review.
   ✅ "What should be running?" is a file. It is diffable, revertible and
      reviewable, and `git revert` IS the rollback.
   ✅ ⭐⭐ THE ARTIFACT CONTRACT BECOMES STRUCTURAL: the only way to change
      production is to change a file that says `@sha256:…`. A tag cannot
      slip in, because the file is the deployment.
```

### 1.1 ⭐ The same credential argument, one level up

Scenario 3's whole architecture rests on **credential asymmetry**: CI can push images but not deploy; CD can deploy but not publish. GitOps applies the *same* idea to the CD half:

| | Push model | ⭐ Pull model |
|---|---|---|
| Who holds cluster credentials? | the CD system (GitHub / Azure DevOps / Jenkins) | ⭐ **Argo CD, inside the cluster** |
| What can CI do? | build + push + publish a digest | build + push + publish a digest |
| What can the CD *pipeline* do now? | deploy anything | ⭐ **write a file to git** — and git write is scoped to a branch and a path |
| Blast radius of a compromised runner | ⛔ the whole cluster | ⭐ one commit to a config repo, which is **reviewable, revertible, and visible in the audit log** |
| Can someone deploy an unbuilt image? | ⛔ yes, if they can run the pipeline | ⛔ only by committing a digest that has no provenance — which the `preSync` check (§7.3) refuses |

⭐ **This is the strongest form of the four-check artifact contract**, because check 4 (read back from the cluster) becomes **continuous** rather than a one-shot assertion at the end of a pipeline. Argo CD compares desired-to-actual forever, and reports drift the moment it appears.

### 1.2 What GitOps costs you

| Cost | ⭐ Honest assessment |
|---|---|
| **A new component to run** | Argo CD is a Deployment with a database (Redis) and an API server. It needs upgrading, monitoring and RBAC like anything else |
| ⭐ **The write-back step is a new failure mode** | CI must commit to git. That needs a git credential in CI, retry logic, and a conflict strategy |
| **Slower for hotfixes** | a `kubectl` hotfix is instant; a GitOps hotfix is a commit, a merge, a sync. ⭐ **That friction is the point** — but you need an escape hatch (§8.4) |
| **Learning curve** | sync waves, hooks, health checks, self-heal semantics |
| ⛔ **Not a replacement for CD policy** | Argo CD syncs what git says. If git says a bad digest, it deploys a bad digest. The approval gate must move to **the git merge**, not disappear |

---

## 2 · What changes from Scenario 3, and what does not

| Stage | Push model (files 01–07) | ⭐ GitOps model |
|---|---|---|
| CI builds | unchanged | **unchanged** |
| CI tests / scans / signs | unchanged | **unchanged** |
| CI emits `digest.txt` | artifact | ⭐ **a commit to the config repo** |
| CD resolves + verifies provenance | pipeline step | ⭐ an Argo CD **`preSync` Job** (or CI does it before committing) |
| CD deploys dev/staging | `kubectl set image` | ⭐ Argo CD auto-syncs those Applications |
| 🔒 production approval | environment gate / `input` | ⭐⭐ **a Pull Request** — reviewers, diff, required checks |
| CD promotes to production | `kubectl set image` | ⭐ merge the PR → Argo CD syncs (auto) or a human clicks Sync |
| CD reads back | one `jsonpath` at the end | ⭐ **continuous** — `Synced` + `Healthy` |
| Rollback | record the previous digest, `set image` | ⭐⭐ **`git revert`** |
| Audit | pipeline logs (90-day retention) | ⭐ **git history (forever)** |

**What does not change at all — and this matters:**

```
✅ the artifact is still a DIGEST, never a tag
✅ CI still cannot deploy (it can only write a file)
✅ the migration Job still gates the rollout — as a `preSync` hook
✅ expand/contract still governs the API and the queue contracts
✅ per-service Case 1 / Case 2 decisions still apply — they become
   `syncPolicy.automated` present or absent on each Application
```

---

## 3 · ⭐ The three repo topologies

```
TOPOLOGY A — ⭐⭐ TWO REPOS (app repo + config repo)          ← RECOMMENDED
  github.com/3558bhk/shop            github.com/3558bhk/shop-config
  ├─ apps/shop-api/                  ├─ base/
  ├─ apps/shop-ui/                   │   └─ shop/values.yaml   (chart defaults)
  ├─ apps/checkout/                  ├─ environments/
  ├─ apps/order-worker/              │   ├─ dev/values.yaml     image.digest: …
  ├─ apps/payment-mock/              │   ├─ staging/values.yaml image.digest: …
  ├─ contracts/                      │   └─ production/values.yaml
  └─ charts/shop/    (the Helm chart) └─ ⭐ only DIGESTS and env-specific values

TOPOLOGY B — ONE REPO (config in a directory of the app repo)
  github.com/3558bhk/shop
  ├─ apps/…          contracts/…      charts/…
  └─ deploy/{dev,staging,production}/values.yaml
  ✅ simplest; one PR changes code AND config together
  ⛔ ⭐⭐ CI's git-write token can now reach the SOURCE CODE too.
     A compromised runner can commit a backdoor, not just a digest.

TOPOLOGY C — TWO CONFIG REPOS (one per environment tier)
  shop-config-staging     shop-config-production
  ⭐⭐ production's write token exists only in the CD pipeline;
     staging's can live in CI.
  ⛔ most repos, most duplication, most drift risk
```

| Property | A · two repos | B · one repo | C · split config |
|---|---|---|---|
| CI's git credential scope | ⭐ **config repo only** | ⛔ the source repo | ⭐ staging config repo only |
| Code + config in one PR | ⛔ two PRs | ✅ one | ⛔ two |
| Config reviewability | ⭐ dedicated reviewers | mixed with code | ⭐ per tier |
| Audit clarity | ⭐ the config repo's history *is* the deploy log | deploy commits interleaved with code | ⭐⭐ best |
| Setup effort | low | ⭐ lowest | medium |
| **Verdict** | ⭐⭐ **use this** | fine for a solo project | for regulated estates |

⭐ **Why topology A:** it preserves Scenario 3's credential asymmetry *inside* the GitOps step. CI gets a token that can write **only** `environments/*/values.yaml` in **only** the config repo. Compromising a runner lets an attacker change a digest — which CI's own provenance check and the PR review will catch — rather than change the code that produces the digest. **Topology B collapses that asymmetry**, and it is the most common mistake in a first GitOps adoption.

```yaml
# ⭐ a scoped token, not a PAT with repo:write
# GitHub: a FINE-GRAINED token
#   Repository access : shop-config only
#   Permissions       : Contents = Read and write   ⛔ NOT Administration
#                       Pull requests = Read and write
#                       ⛔ nothing else
# Azure DevOps: a PAT scoped to the config project, "Code (Read & write)"
# Jenkins: a GitHub App installation token scoped to the config repo,
#          rotated per build (never a long-lived PAT in a credential store)
```

---

## 4 · The Helm chart and the per-environment values files

### 4.1 ⭐ The chart takes a digest, not a tag

```yaml
# charts/shop/values.yaml — the DEFAULTS
image:
  repository: ghcr.io/3558bhk/shop-api
  # ⭐⭐ NO `tag:` FIELD AT ALL. The chart refuses to render without a digest.
  digest: ""                      # set per environment — REQUIRED
  pullPolicy: IfNotPresent

replicaCount: 2
resources:
  requests: { cpu: 250m, memory: 512Mi }
  limits:   { cpu: "1",   memory: 1Gi }

probes:
  startup:   { path: /actuator/health/liveness,  failureThreshold: 30, periodSeconds: 5 }
  readiness: { path: /actuator/health/readiness, failureThreshold: 3,  periodSeconds: 10 }
  liveness:  { path: /actuator/health/liveness,  failureThreshold: 3,  periodSeconds: 20 }

lifecycle:
  preStopSleepSeconds: 10          # ⭐ §05 file §6.3 — the 502 fix

migration:
  enabled: false                   # ⭐ only production/staging turn this on
  backoffLimit: 0
```

```yaml
# charts/shop/templates/deployment.yaml — ⭐ the digest discipline
spec:
  template:
    spec:
      terminationGracePeriodSeconds: 60
      containers:
        - name: {{ .Values.name }}
          # ⭐⭐ THIS LINE IS THE WHOLE POINT OF GITOPS
          image: "{{ .Values.image.repository }}@{{ required "image.digest is REQUIRED — never a tag" .Values.image.digest }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
```

```yaml
# charts/shop/templates/migration-job.yaml — ⭐ a preSync HOOK
{{- if .Values.migration.enabled }}
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ .Values.name }}-migrate-{{ .Release.Revision }}
  annotations:
    # ⭐⭐ runs BEFORE the Deployment is applied, and Argo CD waits for it
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/hook-delete-policy: BeforeHookCreation
    # ⭐ BeforeHookCreation keeps the finished Job around for inspection
    #   until the NEXT sync creates a new one. `HookSucceeded` deletes it
    #   immediately, which is exactly when you most want the logs.
spec:
  backoffLimit: {{ .Values.migration.backoffLimit }}   # ⭐ 0 — no retry
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: migrate
          image: "{{ .Values.image.repository }}@{{ .Values.image.digest }}"
          # ⭐⭐ the SAME digest as the app — a different image can carry a
          #   different Flyway version and different SQL on the classpath
          command: ["java","-cp","/app/app.jar","org.springframework.boot.loader.launch.JarLauncher"]
          args: ["--spring.flyway.enabled=true","--spring.main.web-application-type=none"]
{{- end }}
```

⭐ **The `hook-delete-policy` choice is a real decision.** `HookSucceeded` deletes the Job the instant it completes — so when the *next* stage fails you have no migration logs. `BeforeHookCreation` keeps it until the following sync, which is what you want during an incident. `HookFailed` keeps it only on failure. Use `BeforeHookCreation` and let `ttlSecondsAfterFinished` handle cleanup.

### 4.2 The per-environment values — the only files CI writes

```yaml
# environments/dev/values.yaml
name: shop-api
image:
  repository: ghcr.io/3558bhk/shop-api
  digest: "sha256:1a2b3c4d5e6f…"        # ⭐⭐ THE ONLY LINE CI CHANGES
replicaCount: 1
migration: { enabled: false }
```

```yaml
# environments/staging/values.yaml
name: shop-api
image:
  repository: ghcr.io/3558bhk/shop-api
  digest: "sha256:9f8e7d6c5b4a…"
replicaCount: 2
migration: { enabled: true, backoffLimit: 0 }
```

```yaml
# environments/production/values.yaml
name: shop-api
image:
  repository: shopacr.azurecr.io/shop-api
  digest: "sha256:41ab7c9e…"             # ⭐ a different registry in prod
replicaCount: 3
resources: { requests: { cpu: 500m, memory: 1Gi }, limits: { cpu: "2", memory: 2Gi } }
migration: { enabled: true, backoffLimit: 0 }
probes:
  startup:   { path: /actuator/health/liveness,  failureThreshold: 40, periodSeconds: 5 }
  readiness: { path: /actuator/health/readiness, failureThreshold: 3,  periodSeconds: 10 }
  liveness:  { path: /actuator/health/liveness,  failureThreshold: 3,  periodSeconds: 20 }
lifecycle: { preStopSleepSeconds: 10 }
```

⭐ **The promotion is now a copy of one line between three files.** That is the entire GitOps diff for a release — which is exactly why it is reviewable.

```diff
--- a/environments/production/values.yaml
+++ b/environments/production/values.yaml
@@ -3,7 +3,7 @@ name: shop-api
 image:
   repository: shopacr.azurecr.io/shop-api
-  digest: "sha256:9f8e7d6c5b4a…"
+  digest: "sha256:41ab7c9e…"
```

---

## 5 · ⭐⭐ The image-updater question

**Argo CD Image Updater exists. Should you use it? ⛔ No — not with Scenario 3's contract.**

| | Argo CD Image Updater | ⭐ CI writes the digest (write-back) |
|---|---|---|
| Who decides what to deploy? | ⛔ **Argo CD**, by matching a tag pattern or a registry's newest digest | ⭐ **CI**, after tests, scan, sign and provenance |
| Can it check the four-check contract? | ⛔ it has no idea whether staging ran this digest | ⭐ CI knows exactly what it validated |
| Can it honour 🔒 Case 1 approval? | ⛔ it writes straight to the branch | ⭐ CI opens a **PR**; humans merge |
| Can it run the migration-shadow check first? | ⛔ no | ⭐ yes |
| Does it fit expand/contract ordering? | ⛔ it updates one Application at a time, with no ordering | ⭐ CI commits all five digests atomically (§07 file §8) |
| Registry credentials inside the cluster | ⛔ **yes** — the cluster can now pull *and* enumerate | ⭐ none needed |
| **Verdict** | ⛔ for this estate | ⭐⭐ **use write-back** |

```
⭐ WHEN IMAGE UPDATER IS THE RIGHT ANSWER
   Base-image patching: "track nginx:1.29-alpine and update when a new
   PATCH appears." That is a maintenance task with no application contract,
   no migration and no canary — and Image Updater does it well, on a
   schedule, with a PR (write-back method) rather than a direct write.
   ⛔ It is the WRONG tool for promoting YOUR artifacts through YOUR
     environments, because it cannot express your gates.
```

### 5.1 ⭐ The write-back pattern — what CI actually does

```
CI (already built, tested, scanned, signed, published digest D)
   │
   ├─▶ 1. dev      : commit D to environments/dev/values.yaml      (direct)
   │        → Argo CD auto-syncs → smoke → mark "dev validated"
   │
   ├─▶ 2. staging  : commit D to environments/staging/values.yaml  (direct)
   │        → Argo CD auto-syncs → smoke + soak → mark "staging ran D"
   │
   └─▶ 3. production: ⭐⭐ OPEN A PULL REQUEST with D
            → reviewers see a ONE-LINE diff
            → required checks re-verify provenance + "staging ran D"
            → 🔒 Case 1 : a human merges
            → 🤖 Case 2 : a bot merges once the gates pass
            → Argo CD syncs → continuous read-back
```

⭐ **Note where the Case 1 / Case 2 decision moved.** It is no longer an environment gate or a Jenkins `input` — it is **"does a human merge this PR?"** That is a *better* place for it: the diff is one line, the reviewers are the config repo's CODEOWNERS, the decision is recorded in git forever, and `git revert` is the rollback.

---

## 6 · CI writes the digest to git — all three tools

### 6.1 🐙 GitHub Actions

```yaml
# .github/workflows/cd-gitops-writeback.yml
name: CD · GitOps write-back
on:
  workflow_run:
    workflows: ['CI · polyglot']
    types: [completed]
permissions: { contents: read }          # ⭐ read on the APP repo
env:
  CONFIG_REPO: 3558bhk/shop-config
  # ⭐⭐ the token below is scoped to shop-config ONLY (§3)

jobs:
  writeback:
    if: github.event.workflow_run.conclusion == 'success'
    runs-on: ubuntu-latest
    permissions:
      contents: read                      # ⛔ NOT write — we use the scoped token
      pull-requests: write                # ⭐ for the production PR (via the API)
      id-token: write                     # ⭐ for cosign verify
    steps:
      - uses: actions/checkout@v7
        with: { repository: '${{ env.CONFIG_REPO }}',
                token: '${{ secrets.CONFIG_REPO_TOKEN }}',   # ⭐ scoped
                path: config, fetch-depth: 0 }

      - name: Resolve the digest(s) from the CI run
        id: d
        env: { GH_TOKEN: '${{ secrets.GITHUB_TOKEN }}' }
        run: |
          set -euo pipefail
          gh run download "${{ github.event.workflow_run.id }}" -n release-manifest -D /tmp/m
          cp /tmp/m/release-manifest.txt config/.tmp-manifest.txt
          grep -v '^#' config/.tmp-manifest.txt > config/.tmp-pairs.txt
          wc -l config/.tmp-pairs.txt

      # ── ⭐⭐ CHECKS 1 & 2 — provenance, BEFORE anything touches git ──
      - uses: sigstore/cosign-installer@v4
      - name: Verify every digest
        run: |
          set -euo pipefail
          while IFS='=' read -r svc ref; do
            [[ "$ref" =~ @sha256:[0-9a-f]{64}$ ]] || { echo "⛔ $svc is not a digest: $ref"; exit 1; }
            cosign verify \
              --certificate-oidc-issuer=https://token.actions.githubusercontent.com \
              --certificate-identity-regexp="https://github.com/3558bhk/shop/\.github/workflows/ci-polyglot\.yml@refs/heads/main" \
              "$ref" >/dev/null
            echo "✅ $svc provenance verified"
          done < config/.tmp-pairs.txt

      # ── ⭐⭐ CHECK 3 — did STAGING run this digest? ──────────────────
      - name: Staging gate
        run: |
          set -euo pipefail
          while IFS='=' read -r svc ref; do
            STG=$(yq -r '.image.digest' "config/environments/staging/values-${svc}.yaml")
            [ "sha256:${STG#sha256:}" = "${ref#*@}" ] \
              || { echo "⛔ staging ran $STG, not $ref"; exit 1; }
            echo "✅ $svc validated in staging"
          done < config/.tmp-pairs.txt

      # ── DEV + STAGING : direct commits, auto-synced ─────────────────
      - name: Write dev and staging
        run: |
          set -euo pipefail
          git -C config config user.name  "shop-ci[bot]"
          git -C config config user.email "shop-ci[bot]@users.noreply.github.com"
          while IFS='=' read -r svc ref; do
            DIGEST="${ref#*@}"
            for env in dev staging; do
              F="config/environments/$env/values-${svc}.yaml"
              yq -i ".image.digest = \"$DIGEST\"" "$F"
            done
          done < config/.tmp-pairs.txt
          git -C config add environments/
          git -C config diff --cached --quiet \
            || git -C config commit -m "chore(${{ github.event.workflow_run.head_sha }}): promote to dev+staging"
          # ⭐⭐ RETRY ON CONFLICT — two CI runs can write the same file
          for i in 1 2 3 4 5; do
            git -C config pull --rebase origin main && git -C config push origin main && break
            echo "↻ push rejected, retry $i"; sleep $((i * 5))
          done

      # ── ⭐⭐ PRODUCTION : a PULL REQUEST, never a direct push ───────
      - name: Open the production PR
        env: { GH_TOKEN: '${{ secrets.CONFIG_REPO_TOKEN }}' }
        run: |
          set -euo pipefail
          BR="promote/${{ github.event.workflow_run.head_sha }}"
          git -C config checkout -b "$BR"
          while IFS='=' read -r svc ref; do
            yq -i ".image.digest = \"${ref#*@}\"" "config/environments/production/values-${svc}.yaml"
          done < config/.tmp-pairs.txt
          git -C config add environments/production/
          git -C config commit -m "release: promote ${{ github.event.workflow_run.head_sha }} to production"
          git -C config push -u origin "$BR"
          gh pr create -R "$CONFIG_REPO" --base main --head "$BR" \
            --title "🚀 Promote ${SHORT_SHA} to production" \
            --body "$(cat <<EOF
          ## Release ${{ github.event.workflow_run.head_sha }}
          | service | digest | provenance | staging |
          |---|---|---|---|
          $(while IFS='=' read -r s r; do echo "| \`$s\` | \`${r#*@sha256:}\` | ✅ | ✅ |"; done < .tmp-pairs.txt)

          **CI run:** ${{ github.event.workflow_run.html_url }}
          ⭐ One-line diff per service. \`git revert\` is the rollback.
          EOF
          )"
```

### 6.2 🔷 Azure DevOps — the differences

| Concern | ⭐ Azure DevOps answer |
|---|---|
| Trigger | `resources.pipelines` on the CI pipeline |
| The git credential | ⭐ **Workload Identity Federation is not a git credential.** Use `System.AccessToken` for the *same* project, or a scoped PAT / a GitHub App token for a GitHub-hosted config repo |
| `System.AccessToken` scope | ⛔ it is scoped to the **build's own project** and requires the build service to be granted **"Contribute"** on the repo — check *Project Settings → Repositories → Security*, or the push fails with 403 |
| Committing | `git -c http.extraHeader="AUTHORIZATION: bearer $(System.AccessToken)" push …` |
| The production PR | `az repos pr create` or the REST API |

```yaml
steps:
  - checkout: self
    persistCredentials: true          # ⭐ makes System.AccessToken usable by git
  - bash: |
      set -euo pipefail
      git config user.email "$(Build.RequestedForEmail)"
      git config user.name  "$(Build.RequestedFor)"
      # ⭐ the extraHeader form, because persistCredentials alone does not
      #   always survive a `pull --rebase` + `push` cycle
      git -c http.extraHeader="AUTHORIZATION: bearer $(System.AccessToken)" \
          push origin HEAD:refs/heads/main
    displayName: 'write back dev+staging'
```

### 6.3 🔨 Jenkins — the differences

| Concern | ⭐ Jenkins answer |
|---|---|
| The credential | a **GitHub App** installation token (rotated per build), or a scoped PAT in the `/shop-cd` folder's credential store |
| ⛔ Never | a long-lived PAT with `repo` scope — it can write to *every* repo in the org |
| Committing | `withCredentials([githubApp(id:'config-repo-app')])` + `git push` |
| The PR | `hub`/`gh` CLI, or the GitHub API via `httpRequest` |
| ⭐ Concurrency | `lock('config-repo-write')` around the commit-push block — Jenkins' `parallel` stages will otherwise produce interleaved pushes |

```groovy
stage('write back') {
  steps {
    lock('config-repo-write') {                     // ⭐ serialise the writes
      withCredentials([githubApp(credentialsId: 'shop-config-app',
                                 variable: 'GH_APP')]) {
        sh '''
          set -euo pipefail
          TOKEN=$(curl -fsS -X POST -H "Authorization: Bearer $GH_APP" \
            -H "Accept: application/vnd.github+json" \
            https://api.github.com/app/installations/$INSTALL_ID/access_tokens \
            | jq -r .token)                          # ⭐ short-lived, per build
          git -C config remote set-url origin \
            "https://x-access-token:${TOKEN}@github.com/3558bhk/shop-config.git"
          git -C config config user.name  "jenkins-cd[bot]"
          git -C config config user.email "jenkins-cd[bot]@shop.local"
          for i in 1 2 3 4 5; do
            git -C config pull --rebase origin main && \
            git -C config push origin main && break
            sleep $((i * 5))
          done
        '''
      }
    }
  }
}
```

---

## 7 · ⭐ CD becomes an Argo CD sync — the four checks, restated

```
CHECK 1 · is it a digest?          → ⭐ STRUCTURAL. The chart has no `tag:`
                                       field and `required` fails the render.
CHECK 2 · provenance / signature   → a `preSync` Job, OR CI before committing
CHECK 3 · did staging run this?    → CI, before writing production (§6.1)
CHECK 4 · read back from cluster   → ⭐⭐ CONTINUOUS. Argo CD compares
                                       desired-to-actual forever and reports
                                       `OutOfSync` the instant they differ.
```

### 7.1 ⭐ Check 4 becomes continuous — what that actually buys

```
PUSH MODEL:  kubectl set image → rollout status → jsonpath read-back → DONE
             ⭐ the assertion holds for the 0.5 s it runs.
             ⛔ if someone runs `kubectl edit` five minutes later, NOTHING
                notices until the next deploy or the next incident.

PULL MODEL:  Argo CD compares git to the cluster every 3 minutes (or on a
             webhook) and marks the Application `OutOfSync`.
             ✅ the assertion holds FOREVER.
             ✅ with selfHeal: true, the drift is CORRECTED automatically.
             ✅ `argocd app get` answers "is production what git says?" —
                a question the push model cannot answer at all.
```

### 7.2 The sync strategies per environment

| Environment | ⭐ `syncPolicy` | Why |
|---|---|---|
| **dev** | `automated: { prune: true, selfHeal: true }` | ⭐ full automation; breakage costs nothing |
| **staging** | `automated: { prune: true, selfHeal: true }` | ⭐ this is where check 3 gets its answer — it must reflect git exactly |
| **production** (🤖 Case 2) | `automated: { prune: false, selfHeal: true }` | ⭐ `prune: false` — a resource accidentally deleted from git should NOT be deleted from production automatically |
| **production** (🔒 Case 1) | ⛔ **no `automated`** | a human clicks **Sync** after the PR merges |

⭐⭐ **`prune` and `selfHeal` are different and are commonly conflated:**
- **`selfHeal: true`** — if someone changes the **live cluster** away from git, revert the cluster to git. ⭐ Protects against `kubectl edit`.
- **`prune: true`** — if a resource is **deleted from git**, delete it from the cluster. ⭐ Protects against orphans, and ⛔ **destroys production** if a bad merge removes a file.

```
⭐ THE RULE: selfHeal on everywhere; prune on dev/staging, OFF on production.
   In production, a resource missing from git should raise an ALERT and a
   human decision — not a silent deletion at 03:00.
```

### 7.3 ⭐ Check 2 as a `preSync` Job — belt and braces

```yaml
# charts/shop/templates/verify-provenance-job.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ .Values.name }}-verify-{{ .Release.Revision }}
  annotations:
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/hook-delete-policy: BeforeHookCreation
spec:
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      serviceAccountName: provenance-verifier     # ⭐ least privilege
      containers:
        - name: verify
          image: ghcr.io/sigstore/cosign:v3.0.2
          args:
            - verify
            - --certificate-oidc-issuer=https://token.actions.githubusercontent.com
            - --certificate-identity-regexp=https://github.com/3558bhk/shop/.github/workflows/ci-polyglot.yml@refs/heads/main
            - "{{ .Values.image.repository }}@{{ .Values.image.digest }}"
          # ⭐⭐ if this fails, the sync FAILS and the Deployment is never
          #   applied. An unsigned or wrongly-signed image cannot reach the
          #   cluster even if someone commits its digest by hand.
```

⭐ **This is worth having even though CI already verified.** It closes the last gap in the push model: in GitOps, *anyone with a git write* can change what deploys — including a human hotfixing at 02:00. The `preSync` verification means the cluster will refuse an image that CI did not sign, regardless of who committed it. ⛔ Without it, git write == deploy anything.

---

## 8 · ⭐⭐ Self-heal, drift, and the gotcha that makes it dangerous

### 8.1 What drift looks like

```bash
# someone ran `kubectl scale deploy/shop-api --replicas=9` in production
argocd app get shop-api-production
# NAME                SYNC STATUS   HEALTH STATUS
# shop-api-production OutOfSync     Healthy        ⭐ note: HEALTHY, not broken
#
# ⭐⭐ THE KEY INSIGHT: `Healthy` means the pods are running.
#   `Synced` means the cluster matches git.
#   They are INDEPENDENT. A cluster can be perfectly healthy and completely
#   wrong. Monitoring that watches only pod health will never see this.
```

```bash
argocd app diff shop-api-production
# ⭐ the exact difference, as a diff — this is the GitOps answer to
#   "what is running and why?"
kubectl -n shop-production get deploy shop-api -o jsonpath='{.spec.replicas}'
# 9          ← live
git show HEAD:environments/production/values-shop-api.yaml | yq .replicaCount
# 3          ← desired
```

### 8.2 ⭐⭐ The gotcha — self-heal fights the operator, and the operator wins by accident

```
SCENARIO: production is on fire. An operator scales shop-api to 9 replicas
          to absorb load. selfHeal is ON.

t0    kubectl scale --replicas=9        → live=9, git=3 → OutOfSync
t+3m  Argo CD notices                   → sets live back to 3
t+3m  ⛔ THE MITIGATION IS GONE, and the incident gets worse.
      And the operator has no idea why: nothing told them.
```

| Mitigation | ⭐ What it does |
|---|---|
| ⭐⭐ **`ignoreDifferences`** | tells Argo CD to stop comparing specified fields — e.g. `spec.replicas` when an HPA manages them |
| ⭐ **An HPA instead of a manual scale** | the HPA owns `spec.replicas`; Argo CD must ignore it, or the two fight **forever** |
| **`argocd app suspend`** | ⭐ pauses syncing for one Application — the correct emergency escape hatch |
| **A `sync-window`** | restricts syncing to a time window (e.g. production syncs only 10:00–16:00 weekdays) |
| ⛔ Turning `selfHeal` off in an incident | loses the drift protection you built it for |

```yaml
# ⭐⭐ THE HPA CONFLICT — the single most common Argo CD production incident
spec:
  ignoreDifferences:
    - group: apps
      kind: Deployment
      # ⭐ Argo CD must NOT manage replicas when an HPA does.
      jsonPointers:
        - /spec/replicas
    - group: apps
      kind: Deployment
      # ⭐ and Kubernetes MUTATES these fields; comparing them causes a
      #   permanent, meaningless OutOfSync:
      jqPathExpressions:
        - .spec.template.spec.containers[]?.resources.limits
```

```
⭐ WHY THIS HAPPENS AT ALL
   Kubernetes is a CONTROL LOOP: it defaults and mutates what you apply
   (`resources.limits` gets `cpu: "1"` normalised, `imagePullPolicy` gets
   inferred, `replicas` gets defaulted to 1, an HPA writes `spec.replicas`).
   Argo CD is ALSO a control loop, comparing your git manifest to the live
   object. When Kubernetes' normalisation differs textually from your git
   file, Argo CD reports OutOfSync forever — and with selfHeal on, it
   re-applies forever, and the HPA scales up, and Argo CD scales down,
   ⛔ IN AN OSCILLATION THAT LOOKS LIKE A MYSTERY POD FLAP.
```

### 8.3 ⭐ Sync waves — the dependency order, in GitOps

§07 file's deploy order (`payment-mock` → `shop-api` → `checkout` → `order-worker` → `shop-ui`) must survive the move to GitOps. Argo CD does not know your dependency graph — **you tell it with waves.**

```yaml
# ⭐ wave -1 : things that must exist first (a ConfigMap, a Secret, an SA)
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "-1"

# ⭐ wave 0 : the migration Job (a PreSync hook runs before ALL waves,
#             but a wave keeps ordering explicit if you use a non-hook Job)
# ⭐ wave 1 : payment-mock   (the leaf callee)
# ⭐ wave 2 : shop-api       (the schema owner)
# ⭐ wave 3 : checkout       (the caller)
# ⭐ wave 4 : order-worker   (the consumer)
# ⭐ wave 5 : shop-ui        (the browser-facing tier, ALWAYS LAST)
```

| Rule | ⭐ Detail |
|---|---|
| Waves are **numbers**, and lower runs first | negatives are allowed and idiomatic for prerequisites |
| ⭐ Argo CD waits for each wave to be **Healthy** before starting the next | which is why `readinessProbe` correctness (§05 file §6.3) now gates your whole release |
| ⭐⭐ One Application per wave, **or** waves inside one Application | five Applications with `sync-wave` on their root resources is clearer than one Application with twenty annotated objects |
| Hooks run **before** waves unless they have their own wave | a `PreSync` hook with `sync-wave: "0"` runs before wave 0 |

### 8.4 ⭐ The escape hatch — and why you must have one

```
GitOps friction is a FEATURE, until it is 03:00 and production is down.

✅ THE PREPARED ESCAPE HATCHES, IN ORDER OF PREFERENCE
   1. `argocd app sync shop-api-production --force`
      ⭐ still GitOps — git is unchanged, you are just applying it NOW
      (Argo CD polls; `--force` skips the wait and the health checks)
   2. `git revert <sha> && git push`
      ⭐⭐ THE ROLLBACK. One command, reviewable, and the cluster follows.
   3. `argocd app rollback shop-api-production <HISTORY_ID>`
      ⭐ deploys a PREVIOUS git commit without a new commit — fast, but
      ⛔ it leaves git AHEAD of the cluster, so the next sync undoes it.
      Use it to buy time, then `git revert` for real.
   4. `argocd app suspend` + `kubectl` directly
      ⛔ LAST RESORT. Suspend first, or self-heal will undo you in 3 minutes.
      ⭐ and the suspend must be visible — an unsuspended cluster that someone
      edited by hand is drift waiting to be "fixed".

⛔ THE ANTI-PATTERN: `kubectl edit` during an incident, no suspend, no
   follow-up commit. You fixed it for three minutes, Argo CD undid it,
   and the incident report says the deploy "reverted itself".
```

---

## 9 · The Application manifests and the ApplicationSet

### 9.1 One Application — the shape

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: shop-api-production
  namespace: argocd                       # ⭐ Applications live in argocd
  finalizers: [resources-finalizer.argocd.argoproj.io]
  # ⭐⭐ the finalizer makes DELETING the Application delete its resources.
  #   ⛔ Omit it and `argocd app delete` leaves the Deployment running with
  #     nothing managing it — an orphan that no git revert can reach.
spec:
  project: shop-production                # ⭐ an AppProject, not `default`
  source:
    repoURL: https://github.com/3558bhk/shop-config
    targetRevision: main                  # ⭐⭐ `main`, NEVER `HEAD`
    path: environments/production
    helm:
      valueFiles:
        - values-shop-api.yaml
      # ⭐ parameters can override, but ⛔ do NOT set image.digest here —
      #   then git is no longer the source of truth.
  destination:
    server: https://kubernetes.default.svc
    namespace: shop-production
  syncPolicy:
    # ⭐ 🔒 Case 1: NO `automated` block at all. A human clicks Sync.
    syncOptions:
      - CreateNamespace=true
      - ApplyOutOfSyncOnly=true           # ⭐ do not re-apply unchanged objects
      - RespectIgnoreDifferences=true
    retry:
      limit: 3
      backoff: { duration: 10s, factor: 2, maxDuration: 3m }
  # ⭐⭐ so `Healthy` means something, Argo CD needs to know when YOUR
  #   custom resources are healthy. For plain Deployments it already does.
  ignoreDifferences:
    - group: apps
      kind: Deployment
      jsonPointers: [ /spec/replicas ]    # ⭐ an HPA owns this (§8.2)
```

```yaml
# ⭐ the AppProject — least privilege, expressed as a GitOps policy
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata: { name: shop-production, namespace: argocd }
spec:
  description: The shop estate in production
  sourceRepos:
    - https://github.com/3558bhk/shop-config     # ⭐ ONE repo, not '*'
  destinations:
    - { server: https://kubernetes.default.svc, namespace: shop-production }
    # ⛔ NOT namespace: '*' — that would let a config-repo commit deploy
    #   into kube-system
  clusterResourceWhitelist: []                   # ⭐⭐ NO cluster-scoped resources
  namespaceResourceBlacklist:
    - { group: '', kind: ResourceQuota }
    - { group: '', kind: LimitRange }
  roles:
    - name: developer
      description: read-only
      policies: [p, proj:shop-production:developer, allow, *]
      groups: [shop-engineering]
    - name: release-manager
      description: may sync production
      policies:
        - p, proj:shop-production:release-manager, allow, *
        - p, proj:shop-production:release-manager, allow, applications,sync,*
      groups: [shop-release-managers]
```

⭐ **`clusterResourceWhitelist: []` is the most important line.** With an empty whitelist, a commit to the config repo **cannot** create a ClusterRole, a ClusterRoleBinding, a Namespace, a CRD or a StorageClass. ⛔ With the default (`*`), anyone who can write to the config repo can grant themselves cluster-admin — which converts "a scoped git token" into "cluster root".

### 9.2 ⭐ The ApplicationSet — five services × three environments without fifteen files

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata: { name: shop, namespace: argocd }
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]     # ⭐ a missing key FAILS, not ""
  generators:
    # ⭐⭐ MATRIX: every (service, environment) pair that EXISTS as a file
    - matrix:
        generators:
          - list:
              elements:
                - { service: payment-mock, wave: 1, project: shop }
                - { service: shop-api,     wave: 2, project: shop }
                - { service: checkout,     wave: 3, project: shop }
                - { service: order-worker, wave: 4, project: shop }
                - { service: shop-ui,      wave: 5, project: shop }
          - list:
              elements:
                - { env: dev,       ns: shop-dev,       auto: "true",  prune: "true",  heal: "true" }
                - { env: staging,   ns: shop-staging,   auto: "true",  prune: "true",  heal: "true" }
                - { env: production,ns: shop-production,auto: "false", prune: "false", heal: "true" }
  template:
    metadata:
      name: '{{.service}}-{{.env}}'
    spec:
      # ⭐ the project differs by environment so the AppProject's
      #   destination whitelist is enforced per tier
      project: 'shop-{{.env}}'
      source:
        repoURL: https://github.com/3558bhk/shop-config
        targetRevision: main
        path: 'environments/{{.env}}'
        helm: { valueFiles: ['values-{{.service}}.yaml'] }
      destination:
        server: https://kubernetes.default.svc
        namespace: '{{.ns}}'
      syncPolicy:
        syncOptions: [CreateNamespace=true, ApplyOutOfSyncOnly=true, RespectIgnoreDifferences=true]
        retry: { limit: 3, backoff: { duration: 10s, factor: 2, maxDuration: 3m } }
      ignoreDifferences:
        - { group: apps, kind: Deployment, jsonPointers: [/spec/replicas] }
  templatePatch: |
    # ⭐⭐ THE POLICY SPLIT — Case 2 for dev/staging, Case 1 for production.
    #   `templatePatch` lets one template express fifteen different policies.
    spec:
      {{- if eq .env "production" }}
      syncPolicy: {}          # 🔒 Case 1 — no automated block: a human syncs
      {{- else }}
      syncPolicy:
        automated: { prune: true, selfHeal: true }   # 🤖 Case 2
      {{- end }}
```

| Property | ⭐ Why it matters |
|---|---|
| One file describes fifteen Applications | adding a service is one list element, not five manifests |
| ⭐ The `wave` lives next to the service | the dependency order (§8.3) is data, not tribal knowledge |
| ⭐⭐ `templatePatch` expresses the policy split | dev/staging auto-sync; production waits for a human — the Case 1/Case 2 decision, in GitOps terms |
| `goTemplateOptions: ["missingkey=error"]` | ⛔ without it, a typo in a generator produces `name: "-"` and an Application pointing at `environments/` |
| ⭐ **`preserveResourcesOnDeletion` is NOT set** | so removing a list element **deletes** the Applications — which with the finalizer deletes the workloads. ⭐ Decide that deliberately; for production set `preserveResourcesOnDeletion: true` |

---

## 10 · ▶️ Run it end to end on kind

```bash
# ── 0 · the cluster and Argo CD ───────────────────────────────────────
kind create cluster --name cicd --wait 5m
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd -n argocd --create-namespace --version 8.4.2 \
  --set server.service.type=NodePort \
  --set configs.params.server.insecure=true      # ⭐ local only, behind the port-forward
kubectl -n argocd wait --for=condition=Available deploy/argocd-server --timeout=180s

# ⭐ the initial admin password
PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret \
       -o jsonpath='{.data.password}' | base64 -d)
kubectl -n argocd port-forward svc/argocd-server 8080:80 &
sleep 3
argocd login localhost:8080 --username admin --password "$PASS" --insecure

# ── 1 · the AppProjects (least privilege FIRST) ───────────────────────
kubectl apply -f k8s/argocd/appprojects.yaml
argocd proj list
# ⭐ EXPECT: shop-dev, shop-staging, shop-production — and NOT `default`
#   being used by anything

# ── 2 · the ApplicationSet ────────────────────────────────────────────
kubectl apply -f k8s/argocd/applicationset.yaml
argocd app list -o name | sort
# ⭐ EXPECT 15: {payment-mock,shop-api,checkout,order-worker,shop-ui} × {dev,staging,production}

# ── 3 · ⭐⭐ CHECK 1 IS STRUCTURAL — the chart cannot render a tag ─────
helm template charts/shop -f environments/production/values-shop-api.yaml
# ⛔ EXPECT: error: image.digest is REQUIRED — never a tag
#    (because `required` fires on an empty value)
helm template charts/shop -f environments/production/values-shop-api.yaml \
  --set image.digest=sha256:1a2b3c… | grep 'image:'
# ✅ EXPECT: image: "shopacr.azurecr.io/shop-api@sha256:1a2b3c…"
# ⭐ there is NO WAY to produce `image: …:latest` from this chart.

# ── 4 · dev and staging auto-sync ─────────────────────────────────────
argocd app wait shop-api-dev --sync --health --timeout 300
argocd app get shop-api-dev -o wide
# ⭐ EXPECT: Synced + Healthy
argocd app wait shop-api-staging --sync --health --timeout 300

# ── 5 · ⭐⭐ CHECK 3 — staging ran THIS digest ─────────────────────────
DIGEST=$(yq -r '.image.digest' environments/staging/values-shop-api.yaml)
RUNNING=$(kubectl -n shop-staging get deploy shop-api \
  -o jsonpath="{.spec.template.spec.containers[?(@.name=='shop-api')].image}")
[ "$RUNNING" = "ghcr.io/3558bhk/shop-api@${DIGEST}" ] && echo "✅ staging ran $DIGEST"

# ── 6 · 🔒 production does NOT auto-sync ──────────────────────────────
argocd app get shop-api-production -o json | jq -r '.spec.syncPolicy.automated // "none"'
# ⭐ EXPECT: none   ← Case 1. A human must sync.
argocd app get shop-api-production | head -3
# ⭐ EXPECT: OutOfSync  (git has the new digest; the cluster does not)

# ── 7 · the migration hook runs BEFORE the Deployment ─────────────────
argocd app sync shop-api-production --timeout 300
argocd app resources shop-api-production
# ⭐ EXPECT a Job `shop-api-migrate-N` with hook PreSync, SUCCEEDED,
#   and the Deployment Synced + Healthy AFTER it
kubectl -n shop-production get jobs -l component=migrate
kubectl -n shop-production logs job/shop-api-migrate-2 | tail -20
# ⭐ "Successfully applied N migrations"

# ── 8 · ⭐ CHECK 2 as a preSync Job — prove it refuses an unsigned image
kubectl -n shop-production patch application shop-api-production --type=merge -p \
  '{"spec":{"source":{"helm":{"parameters":[{"name":"image.digest","value":"sha256:deadbeef…"}]}}}}'
argocd app sync shop-api-production || echo "✅ refused"
# ⛔ EXPECT: the cosign PreSync Job FAILS → the sync fails → the Deployment
#   is NOT updated. `kubectl get deploy` still shows the previous digest.

# ── 9 · ⭐⭐ CHECK 4 IS CONTINUOUS — the drift drill ───────────────────
kubectl -n shop-production scale deploy/shop-api --replicas=9
sleep 200                                    # ⭐ Argo CD's refresh interval
argocd app get shop-api-production | head -3
# ⭐ WITHOUT selfHeal: OutOfSync + Healthy  ← healthy AND wrong
argocd app diff shop-api-production | head -20
# ⭐ the exact difference, as a diff
# WITH selfHeal:
kubectl -n shop-production get deploy shop-api -o jsonpath='{.spec.replicas}'
# ⭐ EXPECT: back to 3 — corrected automatically, no human

# ── 10 · ⭐⭐ the HPA conflict — reproduce it, then fix it ────────────
kubectl -n shop-production autoscale deploy/shop-api --min=3 --max=10 --cpu-percent=50
# ⭐ without ignoreDifferences this now oscillates forever:
for i in 1 2 3 4 5 6; do
  sleep 30
  printf 'replicas=%s  sync=%s\n' \
    "$(kubectl -n shop-production get deploy shop-api -o jsonpath='{.spec.replicas}')" \
    "$(argocd app get shop-api-production -o json | jq -r .status.sync.status)"
done
# ⛔ EXPECT oscillation + permanent OutOfSync until you add:
#    ignoreDifferences: [{group: apps, kind: Deployment, jsonPointers: [/spec/replicas]}]

# ── 11 · ⭐⭐ ROLLBACK = git revert ───────────────────────────────────
cd ../shop-config
git log --oneline -5
git revert --no-edit <the-promotion-sha>
git push
argocd app wait shop-api-production --sync --health --timeout 300
kubectl -n shop-production get deploy shop-api \
  -o jsonpath="{.spec.template.spec.containers[?(@.name=='shop-api')].image}"
# ⭐ EXPECT: the PREVIOUS digest — and the rollback is a COMMIT, with an
#   author, a timestamp, a diff and a review.

# ── 12 · the whole estate, one command ────────────────────────────────
argocd app list -o wide | grep production
for s in payment-mock shop-api checkout order-worker shop-ui; do
  printf '%-14s ' "$s"
  kubectl -n shop-production get deploy "$s" 2>/dev/null \
    -o jsonpath="{.spec.template.spec.containers[?(@.name=='$s')].image}" || printf '(missing)'
  echo
done
```

### 10.1 ⭐ The twelve acceptance checks

| # | Check | Command |
|---|---|---|
| 1 | ⭐ The chart **cannot** render a tag | `helm template` with an empty `image.digest` → error |
| 2 | CI's git token cannot reach the app repo | ⭐ the token is scoped to `shop-config` only (§3) |
| 3 | Production does **not** auto-sync | `.spec.syncPolicy.automated` is absent |
| 4 | ⭐ The migration runs **before** the Deployment | a `PreSync` Job, SUCCEEDED, in `argocd app resources` |
| 5 | An unsigned digest is **refused by the cluster** | the cosign `PreSync` Job fails the sync |
| 6 | ⭐⭐ Drift is detected, and reported as `OutOfSync` **while `Healthy`** | `argocd app get` after a `kubectl scale` |
| 7 | ⭐ `selfHeal` corrects it without a human | replicas return to git's value |
| 8 | ⭐ `prune: false` in production | deleting a file from git does **not** delete the workload |
| 9 | The HPA does not fight Argo CD | `ignoreDifferences` on `/spec/replicas` |
| 10 | ⭐⭐ Rollback is `git revert` | one commit, and the cluster follows |
| 11 | `AppProject` allows **no** cluster-scoped resources | `clusterResourceWhitelist: []` |
| 12 | The deploy order survives | `sync-wave` 1→5 matches §07's dependency graph |

---

## 11 · Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| ⛔ `OutOfSync` forever, no visible difference | Kubernetes normalised a field (`resources.limits`, `imagePullPolicy`) | `ignoreDifferences` with `jqPathExpressions` (§8.2) |
| ⛔ Pods flap between two replica counts | ⭐ an HPA and Argo CD both own `spec.replicas` | `ignoreDifferences: jsonPointers: [/spec/replicas]` |
| A manual scale is undone in 3 minutes | ⭐ `selfHeal: true` — working as designed | `argocd app suspend`, or change **git** (§8.4) |
| ⛔ A resource vanished from production | `prune: true` plus a bad merge that deleted a file | ⭐ `prune: false` in production (§7.2) |
| `argocd app delete` left the Deployment running | no `resources-finalizer.argocd.argoproj.io` | ⭐ add the finalizer (§9.1) |
| ⛔ The migration ran three times | Flyway enabled in the app *and* a hook Job | one Job, `spring.flyway.enabled=false` in the Deployment |
| The migration Job is gone and you need its logs | `hook-delete-policy: HookSucceeded` | ⭐ `BeforeHookCreation` (§4.1) |
| `Synced` but the pods are old | ⭐ `ApplyOutOfSyncOnly` plus a stale comparison, or the sync is still in progress | `argocd app get --refresh --hard` |
| ⛔ `comparison error: rpc error … manifest generation error` | the Helm chart failed to render | `helm template` locally — ⭐ often the `required` digest check, which is the chart working correctly |
| The ApplicationSet created `name: "-"` | a generator key typo with the default `missingkey` | ⭐ `goTemplateOptions: ["missingkey=error"]` |
| Removing a list element deleted production | `preserveResourcesOnDeletion` not set | ⭐ set it for production, deliberately (§9.2) |
| ⛔ A config-repo commit created a ClusterRoleBinding | the AppProject's default `clusterResourceWhitelist: ['*']` | ⭐ `clusterResourceWhitelist: []` (§9.1) |
| The write-back push fails with 403 | ⭐ Azure DevOps: the build service lacks **Contribute** on the repo | Project Settings → Repositories → Security (§6.2) |
| Two CI runs clobber each other's commit | concurrent pushes to one branch | ⭐ `pull --rebase` + retry (all three tools), or a Jenkins `lock` |
| Argo CD does not notice a commit for minutes | the default 3-minute poll | ⭐ a **repository webhook** — configure it in the repo settings and point it at `/api/webhook` |
| The webhook is ignored | ⛔ the repository has no webhook secret configured | `argocd repo add --upsert --webhook-secret …` or set it in the UI |
| `cosign verify` fails in the PreSync Job | the certificate identity regexp does not match the workflow path | ⭐ match the **full** workflow URL including `@refs/heads/main` |
| ⛔ Production deployed from a feature branch | `targetRevision: HEAD` | ⭐ `targetRevision: main` — always (§9.1) |

---

<a name="tasks--answers"></a>
## 12 · ⭐ TASKS — answers at the END

| # | Task |
|---|---|
| **T1** | Choose a repo topology and justify it in terms of the credential asymmetry |
| **T2** | Write the Helm chart so a tag is structurally impossible |
| **T3** | Implement the migration as an Argo CD `PreSync` hook with the right delete policy |
| **T4** | Implement CI's git write-back for one tool, including the conflict-retry and the production PR |
| **T5** | Add the cosign `PreSync` verification Job and prove the cluster refuses an unsigned digest |
| **T6** | Write the `AppProject` with least privilege, and explain the most important line |
| **T7** | Write the ApplicationSet for five services × three environments with the Case 1 / Case 2 split |
| **T8** | Set `sync-wave` so the dependency order survives the move to GitOps |
| **T9** | Run the drift drill: detect it, diff it, and let self-heal correct it |
| **T10** | ⭐ Reproduce the HPA/Argo CD oscillation and fix it |
| **T11** | ⭐⭐ Roll back production with `git revert` and explain why `argocd app rollback` alone is not enough |
| **T12** | ⭐⭐ At 03:00 production is overloaded. You scale to 9 replicas and it silently returns to 3 four minutes later. Diagnose, give the immediate fix, the correct fix, and the process fix |

---

# ✅ ANSWERS

**T1.** §3. ⭐ **Topology A — two repos: `shop` (source) and `shop-config` (digests and per-environment values).** The justification is credential asymmetry, the same principle that shaped Scenario 3. CI needs a git credential to write digests back. In topology A that credential is scoped to the **config repo only** — a fine-grained GitHub token with `Contents: read/write` on `shop-config` and nothing else — so a compromised runner can change *which digest* is deployed, a change that CI's own provenance verification and the production PR review will both catch. ⛔ **In topology B (config inside the app repo) the same token can write source code**: a compromised runner can commit a backdoor to `apps/shop-api`, which then builds, passes tests, gets signed by CI, and deploys — with a valid provenance chain. That is a strictly worse failure mode, and it is invisible to every check in this folder. **Topology C (a config repo per tier)** is the strongest — production's write token exists only in the CD pipeline — at the cost of more repos and more drift between them; use it for regulated estates. **Two supporting controls regardless of topology:** ⭐ production is written by a **pull request**, never a direct push (so the merge is the 🔒 Case 1 approval gate, with a one-line diff and CODEOWNERS reviewers), and ⭐ the config repo's history *is* the deployment audit log — durable, diffable and reviewable, where pipeline logs expire after 90 days.

**T2.** §4.1. Three things together. **(a) The `values.yaml` has no `tag:` field at all** — only `image.repository` and `image.digest: ""`. ⭐ Removing the field entirely is stronger than deprecating it: there is nothing to set by mistake. **(b) The template uses `required`:** `image: "{{ .Values.image.repository }}@{{ required "image.digest is REQUIRED — never a tag" .Values.image.digest }}"`. An empty digest fails the render with that message, so `helm template` and `argocd app get` both surface it before anything reaches the cluster. **(c) Prove it structurally:** `helm template charts/shop -f environments/production/values-shop-api.yaml` with an empty digest → ⛔ error; with `--set image.digest=sha256:1a2b3c…` → ✅ `image: "shopacr.azurecr.io/shop-api@sha256:1a2b3c…"`. ⭐ **The property worth stating:** there is **no input** to this chart that produces `image: …:latest` or `image: …:v1.2.3`. That converts check 1 of the artifact contract from a pipeline assertion ("did CD receive a digest?") into a **structural impossibility** — which is why GitOps is the strongest form of the contract. **Two extras that follow:** never override `image.digest` via `spec.source.helm.parameters` in the Application (then git is no longer the source of truth), and never use `targetRevision: HEAD` (then a feature branch can deploy).

**T3.** §4.1. A `batch/v1 Job` in `templates/migration-job.yaml`, gated by `{{- if .Values.migration.enabled }}`, annotated ⭐ `argocd.argoproj.io/hook: PreSync` and ⭐ `argocd.argoproj.io/hook-delete-policy: BeforeHookCreation`, with `backoffLimit: 0` and `restartPolicy: Never`, and the **same `{{ .Values.image.digest }}`** as the Deployment. **Why `PreSync`:** it runs before *any* wave of the sync, and ⭐ **Argo CD waits for it to succeed** — a failed migration fails the sync and the Deployment is never applied. That is the migration gate, expressed declaratively instead of as a `kubectl wait || exit 1` in a shell script. **Why the delete policy matters:** `HookSucceeded` deletes the Job the instant it completes, so when a *later* stage fails you have no migration logs at exactly the moment you need them; `BeforeHookCreation` keeps the finished Job until the next sync creates a replacement, which is what you want during an incident. Let `ttlSecondsAfterFinished` handle eventual cleanup. **Two details:** name the Job with `{{ .Release.Revision }}` so each sync produces a distinct Job (otherwise `BeforeHookCreation` deletes the previous one and you lose the history), and ⛔ ensure `spring.flyway.enabled=false` in the Deployment — otherwise Flyway runs on every pod *and* in the hook, and three replicas race.

**T4.** §6.1. The sequence: `actions/checkout@v7` with `repository: shop-config`, `token: secrets.CONFIG_REPO_TOKEN` (⭐ scoped to the config repo) and `fetch-depth: 0`; download the `release-manifest` artifact from the CI run; **verify checks 1–3 before touching git** (every value matches `@sha256:[0-9a-f]{64}$`, `cosign verify` with the issuer and identity-regexp pinned to the CI workflow on `main`, and staging's `values-*.yaml` already holds that digest); then `yq -i '.image.digest = "…"'` for **dev and staging**, commit, and push; then create a branch, write **production**'s values, and `gh pr create` with a table of service → digest → provenance → staging. ⭐ **The conflict-retry is required, not optional:** two CI runs can write the same file concurrently, and the second push is rejected. The pattern is `for i in 1 2 3 4 5; do git pull --rebase origin main && git push origin main && break; sleep $((i*5)); done`. In Jenkins wrap the whole block in `lock('config-repo-write')`, because `parallel` stages will otherwise interleave pushes. ⭐ **Why production is a PR and not a push:** the merge *is* the 🔒 Case 1 approval gate — a one-line diff per service, reviewed by the config repo's CODEOWNERS, recorded in git forever, and revertible with `git revert`. For 🤖 Case 2 services, a bot merges once the required checks pass; the mechanism is identical and only the merger changes. **And why checks 1–3 run in CI rather than in the cluster:** they are *promotion* decisions and belong with the evidence (staging's soak, the scan results); the cluster's `preSync` cosign Job (T5) is a *second*, independent enforcement of check 2, so that git write alone never equals deploy-anything.

**T5.** §7.3. A Job in `templates/verify-provenance-job.yaml` using `ghcr.io/sigstore/cosign:v3.0.2`, annotated `hook: PreSync` and `hook-delete-policy: BeforeHookCreation`, `backoffLimit: 0`, `restartPolicy: Never`, running `cosign verify --certificate-oidc-issuer=https://token.actions.githubusercontent.com --certificate-identity-regexp=<the CI workflow URL>@refs/heads/main "<repo>@<digest>"`, under a least-privilege `provenance-verifier` ServiceAccount. ⭐ **Proving it:** patch the Application to point at a digest that was never signed (`sha256:deadbeef…`), sync, and observe the PreSync Job **fail** → the sync fails → `kubectl get deploy` still shows the **previous** digest. **Why this is worth having even though CI already verified:** in GitOps, *anyone with a git write* can change what deploys — including a human hotfixing at 02:00, including a compromised token, including a well-meaning revert to an old digest. CI's verification happens **before** the commit; the cluster's happens **at** the sync. ⛔ Without the PreSync Job, "git write" is equivalent to "deploy anything", and the scoped token from T1 protects less than it appears to. **One detail:** the identity regexp must match the **full** workflow URL including `@refs/heads/main`, or `cosign verify` fails on legitimately-signed images and blocks every deploy — which is why T5's proof step must include a positive control (a real digest syncs successfully).

**T6.** §9.1. An `AppProject` per environment tier with: `sourceRepos` listing **only** the config repo (⛔ not `*`); `destinations` restricted to the tier's namespace (⛔ not `namespace: '*'`, which would let a config commit deploy into `kube-system`); ⭐⭐ **`clusterResourceWhitelist: []`**; a `namespaceResourceBlacklist` for `ResourceQuota` and `LimitRange`; and `roles` mapping a read-only `developer` group and a sync-capable `release-manager` group. ⭐ **The most important line is `clusterResourceWhitelist: []`, and the reason is privilege escalation.** Argo CD's default is `*`, meaning an Application may create **cluster-scoped** resources. With that default, anyone who can write to the config repo can commit a `ClusterRoleBinding` granting `cluster-admin` to a ServiceAccount they also committed, sync it, and own the cluster — turning a scoped git token into cluster root, silently, with a legitimate-looking diff. An **empty** whitelist forbids all cluster-scoped kinds (ClusterRole, ClusterRoleBinding, Namespace, CRD, StorageClass, PV), so the config repo's blast radius is confined to the namespaces its AppProject lists. **Two supporting points:** namespaces should be created by `syncOptions: CreateNamespace=true` rather than by a committed `Namespace` manifest, precisely because that keeps cluster-scoped creation out of git; and the tier split into three AppProjects is what lets production deny cluster-scoped resources while dev permits them for experimentation.

**T7.** §9.2. An `ApplicationSet` with `goTemplate: true`, ⭐ `goTemplateOptions: ["missingkey=error"]`, and a **matrix** generator: a `list` of the five services (each carrying its `wave`) crossed with a `list` of the three environments (each carrying its namespace and its policy flags). The template renders `name: '{{.service}}-{{.env}}'`, `project: 'shop-{{.env}}'`, `source.path: 'environments/{{.env}}'` with `helm.valueFiles: ['values-{{.service}}.yaml']`, `destination.namespace: '{{.ns}}'`, shared `syncOptions` (`CreateNamespace`, `ApplyOutOfSyncOnly`, `RespectIgnoreDifferences`), a `retry` backoff, and `ignoreDifferences` on `/spec/replicas`. ⭐ **The policy split lives in `templatePatch`**: `{{- if eq .env "production" }}syncPolicy: {}{{- else }}syncPolicy: { automated: { prune: true, selfHeal: true } }{{- end }}` — so dev and staging are 🤖 Case 2 (auto-sync, prune, self-heal) and production is 🔒 Case 1 (**no** `automated` block: a human clicks Sync after the PR merges). **Three details that decide whether this is safe:** `missingkey=error`, because the default silently renders a typo'd key as empty and produces an Application named `-` pointing at `environments/`; ⭐ `preserveResourcesOnDeletion` must be set **deliberately** for production — without it, removing a list element deletes the Application, and with the `resources-finalizer` that deletes the workload; and the per-tier `project` is what enforces the destination whitelist, so one shared project would undo T6.

**T8.** §8.3 and §9.2. Put the wave in the ApplicationSet's service generator as **data** — `payment-mock: 1`, `shop-api: 2`, `checkout: 3`, `order-worker: 4`, `shop-ui: 5` — and annotate each Application's root resources with `argocd.argoproj.io/sync-wave: "{{.wave}}"`, using negatives (e.g. `-1`) for prerequisites such as ConfigMaps, Secrets and ServiceAccounts. ⭐ **The order is derived from §07's dependency graph, and the two rules still apply:** callee before caller (so the leaf `payment-mock` first, then `shop-api`, then its callers), and the browser-facing tier **last** because the browser is the least-recallable client. **Three mechanics worth stating:** waves are plain numbers and lower runs first; ⭐ **Argo CD waits for each wave to be `Healthy` before starting the next**, which promotes `readinessProbe` correctness (§05 file §6.3) from a per-service concern into the thing that gates your entire release — a pod that reports Ready while broken will let the next wave proceed into a broken dependency; and `PreSync` hooks run before *all* waves unless they carry their own wave, so the migration Job and the cosign Job are ordered ahead of everything by construction. ⭐ **Why waves are better than a shell loop here:** the order is declarative, visible in one file, survives a change of CD tool, and is enforced by the same control loop that enforces the digests.

**T9.** §8.1 and §10 step 9. `kubectl -n shop-production scale deploy/shop-api --replicas=9`, wait past Argo CD's refresh interval (~3 min; ⭐ configure a **repository webhook** to make it near-instant), then `argocd app get shop-api-production`. ⭐ **The observation that matters:** the Application reports **`OutOfSync` + `Healthy`**. The two statuses are independent — `Healthy` means the pods are running and their probes pass; `Synced` means the cluster matches git. **A cluster can be perfectly healthy and completely wrong**, and monitoring that watches only pod health will never see this. Then `argocd app diff shop-api-production` prints the exact difference as a diff — GitOps' answer to "what is running and why?", a question the push model cannot answer at all. **With `selfHeal: true`,** `kubectl get deploy shop-api -o jsonpath='{.spec.replicas}'` returns to **3** with no human involved: Argo CD re-applies git over the live object. ⭐ **That is the feature working correctly — and it is also the hazard** that T12 turns into an incident, which is why the escape hatch (`argocd app suspend`, then change git) must be documented *before* it is needed rather than discovered at 03:00.

**T10.** §8.2 and §10 step 10. **Reproduce it:** `kubectl autoscale deploy/shop-api --min=3 --max=10 --cpu-percent=50`, then sample `spec.replicas` and `argocd app get -o json | jq -r .status.sync.status` every 30 s for a few minutes. ⛔ Expect **oscillation** — load rises, the HPA scales to 6, Argo CD sees `spec.replicas` differ from git's `3` and re-applies `3`, the HPA scales back up — with a **permanent `OutOfSync`**. **Why it happens:** Kubernetes and Argo CD are both control loops writing the same field. The HPA owns `spec.replicas` at runtime; git owns it at declaration time; with `selfHeal` on, neither yields. **The fix:** ⭐ `ignoreDifferences: [{ group: apps, kind: Deployment, jsonPointers: [/spec/replicas] }]` plus `syncOptions: [RespectIgnoreDifferences=true]`, so Argo CD stops comparing a field another controller legitimately owns. **The general lesson, which covers more than HPAs:** Kubernetes **normalises and mutates** what you apply — `resources.limits` gets canonicalised, `imagePullPolicy` is inferred, defaults are filled in — so a textual comparison against git produces spurious `OutOfSync` for fields nobody edited. Use `jqPathExpressions` for those (e.g. `.spec.template.spec.containers[]?.resources.limits`). ⭐ **The rule:** Argo CD should own *what you declared*, and ignore *what another controller or the API server owns*. Every `ignoreDifferences` entry should be answerable to "who else legitimately writes this field?" — if the answer is nobody, the drift is real and should be healed, not ignored.

**T11.** §8.4 and §10 step 11. **`git revert`:** `git revert --no-edit <the-promotion-sha> && git push`, then `argocd app wait shop-api-production --sync --health`, and confirm with the read-back `jsonpath` (⭐ using the **name filter** `[?(@.name=='shop-api')]`) that the previous digest is running. ⭐ **Why this is the real rollback:** it produces a **commit** — with an author, a timestamp, a diff, a review and a permanent place in the audit log — and git remains the single source of truth, so every subsequent sync reinforces the reverted state. **Why `argocd app rollback <HISTORY_ID>` alone is not enough:** it deploys a **previous git commit's manifests** without creating a new commit, so ⛔ **git is left AHEAD of the cluster**. The Application immediately shows `OutOfSync` again, and the **next** sync — automatic on dev/staging, or the next human Sync on production — silently **re-applies the bad version**. It is a way to buy minutes, not a rollback. ⭐ **The correct combination:** `argocd app rollback` to stop the bleeding now, then `git revert` within the same incident to make it durable — and say so in the incident notes, because "I rolled back" is false until the revert lands. **Two related details:** with `retry` configured and `selfHeal: true` on dev/staging, an un-reverted rollback is undone in minutes with no error anywhere; and for the polyglot estate (§07 file §8) the revert must cover **all** changed services, since a half-reverted estate is a half-promoted pair — a state nobody tested.

**T12.** ⭐⭐ **Diagnosis:** `selfHeal: true` on the production Application. The scale to 9 made the live object differ from git's `replicaCount: 3`; at the next refresh Argo CD re-applied git and undid the mitigation. **The tell is that the Application was `OutOfSync` + `Healthy`** — nothing was broken, the cluster was simply not what git said, and GitOps treated that as a defect to correct. **Nothing alerted you**, because pod health, error rate and the sync status were all, individually, unremarkable. **Immediate fix (minutes):** `argocd app suspend shop-api-production` — ⭐ suspend **first**, then scale, or self-heal undoes you again within one refresh interval. Confirm with `argocd app get` that the sync policy shows suspended. **Correct fix (same incident):** change **git**, not the cluster — commit `replicaCount: 9` to `environments/production/values-shop-api.yaml`, push, `argocd app resume`, and let Argo CD apply it. Now the mitigation is durable, reviewable and revertible, and the cluster and git agree. **Process fix (so it does not recur):**
1. ⭐⭐ **An HPA should own `spec.replicas` in production, not a value in git.** Then the correct emergency action is raising the HPA's `--max` (or committing that change), autoscaling handles the load, and `ignoreDifferences: [/spec/replicas]` (T10) keeps Argo CD out of the field entirely. Manual scaling of a GitOps-managed Deployment is always a losing race.
2. **Document the escape hatch in the runbook** — `suspend` → change git → `resume` — and drill it, because an escape hatch nobody has used is a hypothesis (§08 file's "a backup you have never restored").
3. **Alert on `OutOfSync` lasting more than N minutes**, so a human edit is surfaced as an event rather than silently reverted. ⭐ This is the alert that would have told the operator *why* their scale disappeared.
4. **Post-incident:** the report should not say "the deploy reverted itself". It should say a control loop did exactly what it was configured to do, and the configuration assumed a human would never need to change replicas by hand — which is the assumption to fix, via the HPA.

**The meta-lesson, and it generalises beyond this scenario:** ⭐ GitOps makes the cluster **converge on git**, and convergence is indifferent to whether git is right. Every property you relied on in the push model — "an operator can intervene", "a hotfix is instant", "the cluster reflects the last decision someone made" — is now mediated by a file. That is what makes GitOps auditable, revertible and structurally safe against an unproven image. It is also what makes it unforgiving of an undocumented escape hatch. **The investment is in the configuration (HPA ownership, `ignoreDifferences`, `prune: false` in production, the AppProject whitelist) and in the runbook — not in the sync mechanism, which is the part that works.**

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish_Kumar_Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn: https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260
🔗 GitHub: https://github.com/3558Bhk

*`Healthy` means the pods run. `Synced` means they match git. A cluster can be perfectly healthy and completely wrong.*

</div>
