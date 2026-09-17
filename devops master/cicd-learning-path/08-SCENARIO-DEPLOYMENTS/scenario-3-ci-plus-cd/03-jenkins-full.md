# 🔨 SCENARIO 3 · CI + CD END TO END WITH JENKINS
### Two jobs in **separate folders with separate permissions**, chained by `build job:` — Kaniko builds, `kubectl` deploys, and neither half can do the other's work.

> **The path:** `git push` (webhook) → multibranch CI → Kaniko build → Trivy → cosign sign → push → **digest file** → `build job:` → CD → dev → staging → (🔒 `input` *or* 🤖 `shouldPromote()`) → production → read back → record.
>
> **Tool version anchors:** Jenkins LTS **2.568.3** (Java 21 minimum) · Multibranch Pipeline · Kubernetes plugin pod agents · **Kaniko** v1.25 · `kubectl` v1.34.0 · `cosign` v2.6 · Argo Rollouts v1.8 · **Lockable Resources** · **Milestone** · **Folder-based Authorization Matrix**.

---

## 📇 Contents

| § | What |
|---|---|
| [1](#1---the-architecture-two-folders-not-just-two-jobs) | ⭐⭐ The architecture: two **folders**, not just two jobs — Jenkins' credential model |
| [2](#2--the-chaining-mechanism) | The chaining mechanism — `build job:` and why upstream triggers are worse |
| [3](#3---no-docker-socket-kaniko) | ⭐ No Docker socket: Kaniko, and why mounting `/var/run/docker.sock` is a root shell |
| [4](#4--job-1--ci-ci-shop-apijenkinsfile) | **Job 1 — CI** (`ci-shop-api.Jenkinsfile`), full file |
| [5](#5--job-2--cd-cd-shop-apijenkinsfile) | **Job 2 — CD** (`cd-shop-api.Jenkinsfile`), full file |
| [6](#6---the-shared-library-that-holds-both-halves) | ⭐ The shared library that holds both halves |
| [7](#7---the-artifact-contract--four-checks) | ⭐⭐ The artifact contract — four checks |
| [8](#8--the-permission-map) | The permission map — folders, credentials, and RBAC |
| [9](#9---case-1-or--case-2--one-boolean) | 🔒 Case 1 or 🤖 Case 2 — one boolean, and what else must change |
| [10](#10--️-run-it-end-to-end--the-full-acceptance-checks) | ▶️ Run it end to end — the full acceptance checks |
| [11](#11--troubleshooting) | Troubleshooting |
| [12](#12---tasks--answers-at-the-end) | Tasks and answers — **answers at the END** |

---

## 1 · ⭐⭐ The architecture: two **folders**, not just two jobs

```
⛔ ONE FOLDER, TWO JOBS
   shop/
   ├── ci-shop-api      ← credentials: registry-push, kubeconfig-prod
   └── cd-shop-api      ← (same folder = SAME credential scope)
   THE PROBLEM: in Jenkins, credentials are visible to every job in the
   folder that can name them. One folder = one blast radius. A malicious
   Maven dependency in CI can `withCredentials([file(credentialsId:
   'kubeconfig-production')])` and it WORKS.

✅ TWO FOLDERS, TWO PERMISSION SETS
   shop-ci/                             ← Folder-based Authorization Matrix
   │   credentials: registry-push, cosign-key
   │   ⛔ kubeconfig-production is NOT in this folder's scope
   └── ci-shop-api/
   shop-cd/
   │   credentials: kubeconfig-{dev,staging,production}, slack, pagerduty
   │   ⛔ registry-push is NOT in this folder's scope
   └── cd-shop-api/
   ⭐ the separation is enforced by CREDENTIAL SCOPE, not by a comment.
```

| Property | ⭐ How Jenkins enforces it |
|---|---|
| CI cannot deploy | `kubeconfig-production` lives in `shop-cd`'s credential store — ⛔ a job in `shop-ci` **cannot resolve it** |
| CD cannot build | `registry-push` lives in `shop-ci`'s store; and CD's pod template has **no docker/kaniko container** |
| A PR cannot deploy | the multibranch CI job builds PRs; CD is triggered **only** from `main`'s `post { success }` |
| A fork cannot publish | ⭐ the `PUSH` flag is `env.BRANCH_NAME == 'main' && env.CHANGE_ID == null` |
| ⭐ Developers cannot run CD | the **folder** Authorization Matrix: `developers` gets `Job/Read` on `shop-cd`, not `Job/Build` |

```
┌────────── shop-ci/ci-shop-api (multibranch) ──────────┐
│ mvn verify → Kaniko build → Trivy → cosign sign → push │
│                          │                             │
│   digest → /var/jenkins/digests/shop-api-main.txt ⭐ ──┼──┐
│   archiveArtifacts: digest.txt, sbom.json, cosign.pub  │  │
│   build job: '../shop-cd/cd-shop-api', wait:false ⭐ ──┼──┤
└────────────────────────────────────────────────────────┘  │ the contract
                                                            │
┌────────── shop-cd/cd-shop-api ─────────────────────────┐  │
│ parameters: IMAGE (digest) ← ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─┼──┘
│ validate shape → cosign verify → dev → staging
│   → 🔒 input | 🤖 shouldPromote() → production
│   → READ BACK → audit record → slack
└────────────────────────────────────────────────────────┘
```

---

## 2 · The chaining mechanism

### 2.1 ⭐ `build job:` with the digest as an explicit parameter

```groovy
// ── in the CI JENKINSFILE, post { success } ──────────────────────────
post {
  success {
    script {
      // ⭐⭐ only from main, and only when CI actually PUBLISHED
      if (env.BRANCH_NAME == 'main' && env.CHANGE_ID == null && env.IMAGE_REF) {
        build job: '/shop-cd/cd-shop-api',       // ⭐ ABSOLUTE path
              parameters: [
                string(name: 'IMAGE',    value: env.IMAGE_REF),
                string(name: 'GIT_SHA',  value: env.GIT_COMMIT),
                string(name: 'CI_BUILD', value: env.BUILD_URL),
                string(name: 'COSIGN_PUB', value: env.COSIGN_PUB)
              ],
              wait: false,          // ⛔ `wait: true` holds a CI executor
                                    //   for the whole CD run (incl. soaks)
              propagate: false      // ⭐ a CD failure must not fail CI
      } else {
        echo "ℹ️ not main / a PR / nothing published — not triggering CD"
      }
    }
  }
}
```

### 2.2 The four ways to get it wrong

| Mistake | Consequence | ⭐ Fix |
|---|---|---|
| `triggers { upstream(...) }` in CD | ⛔ upstream triggers pass **no parameters** — `params.IMAGE` is blank and you re-discover "the latest digest", reintroducing the race | `build job:` with explicit parameters |
| `build job: 'cd-shop-api'` (relative) | ⛔ resolves inside `shop-ci` — job not found, or worse, a *different* job | ⭐ the absolute path `/shop-cd/cd-shop-api` |
| `wait: true` | CI executors are consumed by CD's 10-minute canary soak | `wait: false` |
| ⛔ No `env.IMAGE_REF` guard | a docs-only or PR build triggers CD with nothing to deploy | the guard above |

### 2.3 Cross-system chaining (GitHub CI → Jenkins CD, or the reverse)

```groovy
// ⭐ Generic Webhook Trigger plugin — when CI is not in Jenkins
// CD job config: token = 'cd-shop-api', and parameter mappings from the JSON body
pipeline {
  agent none
  triggers {
    GenericTrigger(
      genericVariables: [
        [key: 'IMAGE',    value: '$.image',    defaultValue: '', regexpFilterText: '$IMAGE'],
        [key: 'GIT_SHA',  value: '$.commit'],
        [key: 'CI_BUILD', value: '$.runUrl']
      ],
      token: 'cd-shop-api',
      causeString: 'Triggered by CI for $IMAGE',
      // ⭐⭐ ONLY trigger for main — a webhook from a PR must not deploy
      regexpFilterExpression: '^refs/heads/main$',
      regexpFilterText: '$REF',
      printPostContent: false          // ⛔ never log the body: it may carry a token
    )
  }
}
```

---

## 3 · ⭐ No Docker socket: Kaniko

**The pod agent has no Docker daemon, and that is deliberate.**

```
⛔ MOUNTING /var/run/docker.sock INTO A CI AGENT
   = giving the build a ROOT SHELL ON THE HOST.
   Not "a risk". Root. Concretely:
     docker run -v /:/host --rm -it alpine chroot /host
   …and you are root on the node, able to read every other pod's secrets,
   every credential file, and the kubelet's own certificate.
   ⭐ Any build that runs `npm ci` or `mvn verify` with that mount can do it.

✅ KANIKO — builds an image, in a pod, with no daemon and no privileges
   gcr.io/kaniko-project/executor:v1.25.0
   ⭐ runs as a NON-ROOT user, needs NO privileged mode, and produces a
     real OCI image pushed straight to the registry.
```

```yaml
# ── the CI pod template ───────────────────────────────────────────────
apiVersion: v1
kind: Pod
metadata:
  labels: { jenkins/ci: "true" }
spec:
  serviceAccountName: jenkins-ci-agent      # ⭐ CI's SA, NOT CD's
  securityContext:
    runAsNonRoot: true                       # ⭐ enforced at the pod level
    runAsUser: 1000
    seccompProfile: { type: RuntimeDefault }
  containers:
  - name: maven
    image: maven:3.9.11-eclipse-temurin-21    # ⭐ pinned
    command: ["sleep"]
    args: ["infinity"]
    resources: { requests: { cpu: 500m, memory: 1Gi }, limits: { cpu: "2", memory: 3Gi } }
    volumeMounts:
      - { name: m2, mountPath: /home/jenkins/.m2 }     # ⭐ PVC cache
  - name: kaniko
    image: gcr.io/kaniko-project/executor:v1.25.0
    command: ["sleep"]
    args: ["infinity"]
    resources: { requests: { cpu: 500m, memory: 1Gi }, limits: { cpu: "2", memory: 4Gi } }
    volumeMounts:
      - { name: docker-config, mountPath: /kaniko/.docker }   # ⭐ registry auth
      - { name: build-cache,   mountPath: /cache }            # ⭐ layer cache
  - name: kubectl                                # ⭐ for cosign/trivy only
    image: bitnami/kubectl:1.34.0
    command: ["sleep"]
    args: ["infinity"]
  # ⛔ NO docker container. NO /var/run/docker.sock volume. EVER.
  volumes:
    - name: m2
      persistentVolumeClaim: { claimName: jenkins-m2-cache }
    - name: build-cache
      persistentVolumeClaim: { claimName: kaniko-cache }
    - name: docker-config
      secret: { secretName: regcred-kaniko, items: [{ key: .dockerconfigjson, path: config.json }] }
  nodeSelector: { pool: ci }                   # ⭐ CI nodes, separate from CD
```

```bash
# ⭐ the Kaniko invocation
/kaniko/executor \
  --context   dir://$WORKSPACE/apps/shop-api \
  --dockerfile Dockerfile \
  --destination shopacr.azurecr.io/shop-api:$TAG \
  --cache=true --cache-repo=shopacr.azurecr.io/shop-api-cache \
  --cache-copy-layers=true \
  --snapshot-mode=redo \                 # ⭐ faster than the default `full`
  --compressed-caching=false \           # ⭐ avoids OOM on large Java layers
  --use-new-run \                        # ⭐ fewer opaque-layer failures
  --label org.opencontainers.image.revision=$GIT_COMMIT \
  --reproducible \                       # ⭐⭐ strips timestamps → same input,
                                         #   same digest. Makes the contract auditable.
  --image-name-with-digest-file /tmp/digest.txt
# ⭐⭐ `--image-name-with-digest-file` is the whole point: Kaniko writes
#   `repo@sha256:…` for you. You do not resolve the digest from a tag.
```

| ⭐ Kaniko flag | Why |
|---|---|
| `--image-name-with-digest-file` | ⭐⭐ the digest, straight from the builder — no tag resolution, no race |
| `--reproducible` | same input → same digest. Makes "which build produced this?" answerable |
| `--cache=true` + `--cache-repo` | ⭐ a registry-backed layer cache — the PVC alternative |
| `--compressed-caching=false` | ⛔ the default can OOM the agent on large layers |
| `--snapshot-mode=redo` | faster snapshots; `full` for stubborn filesystems |

---

## 4 · Job 1 — CI (`ci-shop-api.Jenkinsfile`)

```groovy
// ═══════════════════════════════════════════════════════════════════════
//  WHAT : the CI HALF of Scenario 3 for shop-api (Java 21 / Spring Boot).
//         Maven → Kaniko → Trivy → cosign sign → push → ⭐ emit digest.
//  WHY  : it must PUBLISH and must NOT DEPLOY.
//         Enforced by folder credential scope: kubeconfig-* does not exist
//         in /shop-ci, so `withCredentials` for it FAILS at resolution.
//  TARGET: shopacr.azurecr.io/shop-api — and nothing else.
// ═══════════════════════════════════════════════════════════════════════
pipeline {
  agent {
    kubernetes { yaml '''
apiVersion: v1
kind: Pod
metadata: { labels: { jenkins/ci: "true" } }
spec:
  serviceAccountName: jenkins-ci-agent
  securityContext: { runAsNonRoot: true, runAsUser: 1000, seccompProfile: { type: RuntimeDefault } }
  containers:
  - { name: maven,  image: maven:3.9.11-eclipse-temurin-21, command: ["sleep"], args: ["infinity"] }
  - name: kaniko
    image: gcr.io/kaniko-project/executor:v1.25.0
    command: ["sleep"]
    args: ["infinity"]
    volumeMounts:
      - { name: docker-config, mountPath: /kaniko/.docker }
      - { name: build-cache,   mountPath: /cache }
  - { name: tools, image: alpine:3.22, command: ["sleep"], args: ["infinity"] }
  volumes:
    - { name: m2,          persistentVolumeClaim: { claimName: jenkins-m2-cache } }
    - { name: build-cache, persistentVolumeClaim: { claimName: kaniko-cache } }
    - name: docker-config
      secret: { secretName: regcred-kaniko, items: [{ key: .dockerconfigjson, path: config.json }] }
  nodeSelector: { pool: ci }
''' }
  }

  options {
    timestamps()
    buildDiscarder(logRotator(numToKeepStr: '50'))
    timeout(time: 45, unit: 'MINUTES')
    disableConcurrentBuilds()          // ⭐ one build per branch
  }

  environment {
    SERVICE  = 'shop-api'
    REGISTRY = 'shopacr.azurecr.io'
    // ⭐⭐ THE PUSH FLAG — one variable, one decision
    //   ⛔ never on a PR (CHANGE_ID is set for multibranch PR builds),
    //   ⛔ never on a fork, ✅ only on main.
    PUSH = "${env.BRANCH_NAME == 'main' && env.CHANGE_ID == null}"
    TAG  = "sha-${env.GIT_COMMIT?.take(8) ?: 'local'}"
  }

  stages {
    // ═══════════════ 1 · BUILD + TEST (no registry access) ═══════════════
    stage('1 · Build and test') {
      steps {
        container('maven') {
          dir('apps/shop-api') {
            sh '''
              set -eu
              mvn -B -ntp verify -DskipITs
            '''
            // ── ⭐ INTEGRATION TESTS: a REAL Postgres 17 ─────────────
            //   ⛔ There is no Docker daemon here. Two options:
            //   (a) a SIDECAR Postgres in the pod template (below)
            //   (b) Testcontainers Cloud / a remote Docker host
            sh '''
              set -eu
              export SPRING_DATASOURCE_URL=jdbc:postgresql://localhost:5432/shop
              export SPRING_DATASOURCE_USERNAME=shop
              export SPRING_DATASOURCE_PASSWORD=$PG_PASSWORD
              mvn -B -ntp verify -Dit.test='*IT'
            '''
          }
        }
      }
      post {
        always {
          junit testResults: 'apps/shop-api/target/*-reports/TEST-*.xml',
                allowEmptyResults: true, keepLongStdio: true
          recordCoverage(tools: [[parser: 'JACOCO']], sourceDirectories: [[path: 'apps/shop-api/src']])
        }
      }
    }

    // ═══════════════ 2 · STATIC ANALYSIS + CVE ═══════════════
    stage('2 · Analysis') {
      parallel {
        stage('spotbugs') {
          steps { container('maven') { dir('apps/shop-api') { sh 'mvn -B -ntp spotbugs:spotbugs' } } }
          post { always { spotbugs pattern: 'apps/shop-api/target/spotbugsXml.xml',
                                   qualityGates: [[threshold: 'TOTAL_HIGH', type: 'TOTAL', unstable: true]] } }
        }
        stage('dependency CVE') {
          steps {
            container('maven') { dir('apps/shop-api') { sh 'mvn -B -ntp org.owasp:dependency-check-maven:check' } }
            // ⛔ NOT a warning. A gate.
          }
          post { always { dependencyCheckPublisher pattern: 'apps/shop-api/target/dependency-check-report.json' } }
        }
      }
    }

    // ═══════════════ 3 · IMAGE (Kaniko) ═══════════════
    stage('3 · Build image') {
      steps {
        container('kaniko') {
          dir('apps/shop-api') {
            sh '''
              set -eu
              /kaniko/executor \
                --context dir://$WORKSPACE/apps/shop-api \
                --dockerfile Dockerfile \
                --destination $REGISTRY/$SERVICE:$TAG \
                --cache=true --cache-repo=$REGISTRY/$SERVICE-cache \
                --cache-copy-layers=true \
                --snapshot-mode=redo --compressed-caching=false --use-new-run \
                --label org.opencontainers.image.revision=$GIT_COMMIT \
                ${PUSH:+--reproducible} \
                --image-name-with-digest-file /tmp/digest.txt
              # ⭐⭐ Kaniko writes `repo@sha256:…` — no tag resolution needed
              cat /tmp/digest.txt
            '''
            script {
              def full = readFile('/tmp/digest.txt').trim()
              // ⭐ even when not pushing, Kaniko reports the digest it built
              env.IMAGE_REF = env.PUSH == 'true' ? full : "${REGISTRY}/${SERVICE}:${TAG}"
              env.DIGEST    = full.contains('@') ? full.split('@')[1] : ''
            }
          }
        }
      }
    }

    // ═══════════════ 4 · SCAN THE IMAGE ═══════════════
    stage('4 · Scan image') {
      when { expression { env.PUSH == 'true' } }
      steps {
        container('tools') {
          sh '''
            set -eu
            apk add --no-cache curl
            curl -fsSL https://github.com/aquasecurity/trivy/releases/download/0.66.0/trivy_0.66.0_Linux-64bit.tar.gz \
              | tar xz -C /tmp trivy
            # ⛔ --exit-code 1 makes it a GATE. ⭐ --ignore-unfixed keeps it
            #   actionable: a CVE with no fix is not a decision anyone can make.
            /tmp/trivy image --exit-code 1 --severity CRITICAL,HIGH --ignore-unfixed \
              --format table "$IMAGE_REF"
            /tmp/trivy image --format cyclonedx --output sbom.json "$IMAGE_REF"
          '''
        }
      }
    }

    // ═══════════════ 5 · ⭐⭐ SIGN ═══════════════
    stage('5 · Sign') {
      when { expression { env.PUSH == 'true' } }
      steps {
        container('tools') {
          // ⭐ the cosign key lives in /shop-ci's credential store.
          //   CD cannot read it; it reads the PUBLIC key from the artifact.
          withCredentials([file(credentialsId: 'cosign-private-key', variable: 'COSIGN_KEY')]) {
            sh '''
              set -eu
              curl -fsSL -o /tmp/cosign \
                https://github.com/sigstore/cosign/releases/download/v2.6.1/cosign-linux-amd64
              chmod +x /tmp/cosign
              COSIGN_PASSWORD="$COSIGN_KEY_PASSWORD" /tmp/cosign sign --key "$COSIGN_KEY" --yes "$IMAGE_REF"
              /tmp/cosign public-key --key "$COSIGN_KEY" > cosign.pub
              echo "✅ signed $IMAGE_REF"
            '''
          }
          script { env.COSIGN_PUB = readFile('cosign.pub').trim() }
        }
      }
    }

    // ═══════════════ 6 · ⭐⭐ THE ARTIFACT CONTRACT ═══════════════
    stage('6 · Publish the digest') {
      when { expression { env.PUSH == 'true' } }
      steps {
        script {
          // the artifact, for CD and for humans
          writeFile(file: 'digest.txt', text: "${env.IMAGE_REF}\n")
          writeFile(file: 'manifest.json', text: groovy.json.JsonOutput.prettyPrint(
            groovy.json.JsonOutput.toJson([
              service : env.SERVICE, image: env.IMAGE_REF, digest: env.DIGEST,
              commit  : env.GIT_COMMIT, branch: env.BRANCH_NAME,
              ciBuild : env.BUILD_URL, builtAt: new Date().format("yyyy-MM-dd'T'HH:mm:ss'Z'", TimeZone.getTimeZone('UTC'))
            ])))
          archiveArtifacts artifacts: 'digest.txt,manifest.json,cosign.pub,sbom.json',
                           fingerprint: true          // ⭐ fingerprint = traceable
          // ⭐ the well-known path CD falls back to
          sh 'mkdir -p /var/jenkins/digests && cp digest.txt /var/jenkins/digests/${SERVICE}-main.txt'
          currentBuild.description = "${env.DIGEST.take(19)}…"
        }
      }
    }
    // ⭐ CI STOPS HERE. There is no kubectl container with a kubeconfig,
    //   and kubeconfig-* does not exist in this folder's credential store.
  }

  post {
    success {
      script {
        // ═══════════ ⭐⭐ THE CHAIN ═══════════
        if (env.PUSH == 'true' && env.IMAGE_REF) {
          build job: '/shop-cd/cd-shop-api',
                parameters: [
                  string(name: 'IMAGE',      value: env.IMAGE_REF),
                  string(name: 'GIT_SHA',    value: env.GIT_COMMIT),
                  string(name: 'CI_BUILD',   value: env.BUILD_URL),
                  string(name: 'COSIGN_PUB', value: env.COSIGN_PUB)
                ],
                wait: false, propagate: false
          echo "⭐ triggered CD with ${env.IMAGE_REF}"
        }
      }
    }
    failure { slackSend(channel: '#ci', color: 'danger',
                message: "⛔ CI failed: ${env.SERVICE} ${env.BRANCH_NAME} — ${env.BUILD_URL}") }
  }
}
```

### 4.1 ⭐ The Testcontainers problem on a Kubernetes agent

```
⛔ Testcontainers needs a Docker daemon. A Kubernetes pod agent has none,
   and mounting the node's socket is a ROOT SHELL (§3). Three real options:

(a) ⭐ A SIDECAR Postgres in the pod template — simplest, and it is a REAL
    Postgres, so the tests are meaningful:
      containers:
      - name: postgres
        image: postgres:17.7
        env: [{name: POSTGRES_PASSWORD, value: shop}, {name: POSTGRES_DB, value: shop}]
        readinessProbe:
          exec: { command: ["pg_isready","-U","shop"] }
          initialDelaySeconds: 5
    …and the tests point SPRING_DATASOURCE_URL at localhost:5432, with
    Testcontainers DISABLED (@ActiveProfiles("ci-sidecar")).
    ⭐ TRADE-OFF: one shared DB for the whole build, so tests must not
      depend on isolation. Use @Transactional tests or truncate between.

(b) Testcontainers Cloud — a remote daemon, zero cluster risk, costs money.

(c) A VM agent with Docker installed — ⭐ only for the CI folder, and only
    if you accept that the agent is a pet.
```

---

## 5 · Job 2 — CD (`cd-shop-api.Jenkinsfile`)

```groovy
// ═══════════════════════════════════════════════════════════════════════
//  WHAT : the CD HALF of Scenario 3 for shop-api.
//         consumes CI's digest → dev → staging → 🔒/🤖 → production.
//  WHY  : it must DEPLOY and must NOT PUBLISH. Enforced by folder scope:
//         registry-push does not exist in /shop-cd, and the pod template
//         has NO kaniko container.
//  TARGET: kind `cicd` → namespaces shop-{dev,staging,production}.
// ═══════════════════════════════════════════════════════════════════════
pipeline {
  agent {
    kubernetes { yaml '''
apiVersion: v1
kind: Pod
metadata: { labels: { jenkins/cd: "true" } }
spec:
  serviceAccountName: jenkins-cd-agent      # ⭐ CD's SA, NOT CI's
  containers:
  - { name: kubectl, image: bitnami/kubectl:1.34.0, command: ["sleep"], args: ["infinity"] }
  - { name: argo,    image: quay.io/argoproj/argo-rollouts:v1.8.2, command: ["sleep"], args: ["infinity"] }
  - { name: tools,   image: alpine:3.22, command: ["sleep"], args: ["infinity"] }
  # ⛔ NO kaniko, NO maven, NO node, NO docker. This pipeline CANNOT build.
  nodeSelector: { pool: cd }                # ⭐ CD nodes, separate from CI
''' }
  }

  options {
    timestamps()
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '200'))    // ⭐ CD runs often
    timeout(time: 90, unit: 'MINUTES')
    skipDefaultCheckout()                              // ⭐ CD does not build
  }

  parameters {
    string(name: 'IMAGE',      defaultValue: '', description: '⭐ digest ref from CI')
    string(name: 'GIT_SHA',    defaultValue: '', description: 'originating commit')
    string(name: 'CI_BUILD',   defaultValue: '', description: '⭐ link back to CI')
    string(name: 'COSIGN_PUB', defaultValue: '', description: 'the CI public key')
    choice(name: 'TARGET',     choices: ['production','staging','dev'])
    string(name: 'REASON',     defaultValue: '', description: '⭐ shown to the approver')
    booleanParam(name: 'AUTO_PROMOTE', defaultValue: false,
                 description: '🤖 true = Case 2 (shouldPromote decides). false = 🔒 Case 1 (input)')
  }

  environment {
    SERVICE   = 'shop-api'
    NS_PREFIX = 'shop'
    PROBE     = '/actuator/health/readiness'
    PORT      = '8080'
  }

  stages {
    // ═══════════════ 0 · RESOLVE + PROVENANCE ═══════════════
    stage('0 · Resolve') {
      steps {
        script {
          def raw = (params.IMAGE ?: '').trim()
          if (!raw) raw = readFile('/var/jenkins/digests/shop-api-main.txt').trim()
          // ── CHECK 1 · ⛔ REFUSE A TAG ────────────────────────────
          if (!(raw ==~ /^[a-z0-9._\/-]+@sha256:[0-9a-f]{64}$/)) {
            error("⛔ CHECK 1 failed: '${raw}' is not a digest reference. CD refuses tags.")
          }
          env.IMAGE_REF = raw
          env.DIGEST    = raw.split('@')[1]
          currentBuild.displayName = "#${BUILD_NUMBER} ${env.DIGEST.take(15)}…"
          currentBuild.description = "← ${params.CI_BUILD ?: 'manual'}"

          // ── ⭐⭐ CIRCUIT BREAKER (Case 2 only) ─────────────────────
          env.HALTED = fileExists("/var/jenkins/cd-state/${SERVICE}.HALTED") ? 'true' : 'false'
          if (env.HALTED == 'true') {
            currentBuild.result = 'NOT_BUILT'      // ⭐ green-ish, NOT red
            slackSend(channel: '#releases', color: '#808080',
              message: "🛑 CD skipped — ${SERVICE} is HALTED. Clear /var/jenkins/cd-state/${SERVICE}.HALTED to resume.")
            return
          }
          // ── ⭐ FREEZE CALENDAR ────────────────────────────────────
          checkout scm                            // needed to read freezes.yaml
          env.FROZEN = inFreezeWindow(new Date()) ?: ''
          if (env.FROZEN && !params.AUTO_PROMOTE) {
            currentBuild.result = 'NOT_BUILT'
            echo "🧊 freeze in effect (${env.FROZEN}) — not promoting."
            return
          }
        }
      }
    }

    // ═══════════════ 0.5 · ⭐ CHECK 2 · PROVENANCE ═══════════════
    stage('0.5 · Verify provenance') {
      steps {
        container('tools') {
          sh '''
            set -eu
            apk add --no-cache curl >/dev/null
            curl -fsSL -o /tmp/cosign \
              https://github.com/sigstore/cosign/releases/download/v2.6.1/cosign-linux-amd64
            chmod +x /tmp/cosign
            # ⭐ the PUBLIC key came from CI as a parameter — CD never holds
            #   the private key, and cannot sign anything.
            echo "$COSIGN_PUB_PARAM" > /tmp/cosign.pub
            /tmp/cosign verify --key /tmp/cosign.pub "$IMAGE_REF" >/dev/null \
              || { echo "⛔ CHECK 2 failed: provenance verification failed"; exit 1; }
            echo "✅ CHECK 2 · signed by our CI"
          '''
          // (COSIGN_PUB_PARAM is bound from params.COSIGN_PUB via environment{})
        }
      }
    }

    // ═══════════════ 1 · DEV ═══════════════
    stage('1 · dev') {
      steps { container('kubectl') { script { deployDigest('dev') } } }
    }

    // ═══════════════ 2 · STAGING — produces the evidence ═══════════════
    stage('2 · staging') {
      steps {
        container('kubectl') {
          script {
            deployDigest('staging', runMigration: true)
            // ⭐⭐ READ BACK what staging is ACTUALLY running
            env.STAGED_DIGEST = readBack('shop-staging')
            def ready = sh(returnStdout: true, script:
              "kubectl -n shop-staging get deploy ${SERVICE} -o jsonpath='{.status.readyReplicas}/{.spec.replicas}'").trim()
            def mig = sh(returnStdout: true, script:
              "kubectl -n shop-staging get job ${SERVICE}-migrate -o jsonpath='{.status.succeeded}' 2>/dev/null || echo n/a").trim()
            def changes = sh(returnStdout: true, script: './scripts/changes-since-last-prod.sh || echo "(unknown)"').trim()
            writeFile(file: 'staging-report.html', text: """
<h2>⭐ Staging verification — ${env.DIGEST}</h2>
<table border="1" cellpadding="6">
 <tr><td>digest running in staging</td><td><code>${env.STAGED_DIGEST}</code></td></tr>
 <tr><td>ready replicas</td><td><b>${ready}</b></td></tr>
 <tr><td>migration job succeeded</td><td>${mig}</td></tr>
 <tr><td>source commit</td><td><code>${params.GIT_SHA}</code></td></tr>
 <tr><td>CI build</td><td><a href="${params.CI_BUILD}">${params.CI_BUILD}</a></td></tr>
 <tr><td>reason</td><td>${params.REASON}</td></tr>
 <tr><td>mode</td><td>${params.AUTO_PROMOTE ? '🤖 Case 2 (automatic)' : '🔒 Case 1 (human)'}</td></tr>
</table>
<h3>Changes since the last production release</h3><pre>${changes}</pre>""")
            publishHTML(target: [reportDir: '.', reportFiles: 'staging-report.html',
                                 reportName: '⭐ Staging Report', keepAll: true, alwaysLinkToLastBuild: true])
          }
        }
      }
    }

    // ═══════════════ 3 · ⛔🔒 CASE 1 — THE HUMAN GATE ═══════════════
    stage('3 · 🔒 approval') {
      when { expression { params.TARGET == 'production' && !params.AUTO_PROMOTE } }
      steps {
        script {
          slackSend(channel: '#releases', color: 'warning', message: """⛔ *Approval needed* — ${SERVICE} → production
Digest : `${env.DIGEST}`
Reason : ${params.REASON}
Staging: ✅ ${env.STAGED_DIGEST?.take(40)}…
⭐ Open the 'Staging Report' before approving: ${env.BUILD_URL}input/""")
          def decision = timeout(time: 72, unit: 'HOURS') {
            input(id: 'prod-approval',
              message: """🚢 Deploy ${SERVICE} → PRODUCTION?

digest : ${env.DIGEST}
reason : ${params.REASON}
CI     : ${params.CI_BUILD}

⭐ Open the 'Staging Report' on this build first.""",
              ok: 'Approve deployment to production',
              submitter: 'platform-leads,release-managers',
              submitterPermissionCheck: true,        // ⭐⭐ ENFORCED, not decorative
              submitterParameter: 'APPROVER',
              parameters: [
                choice(name: 'RISK', choices: ['low','medium','high']),
                string(name: 'ROLLBACK_PLAN', defaultValue: '',
                       description: '⭐ How would you roll this back? (required)')
              ])
          }
          if (!decision.ROLLBACK_PLAN?.trim()) error('⛔ a rollback plan is required')
          wrap([$class: 'BuildUser']) {
            if (decision.APPROVER == env.BUILD_USER_ID)
              error("⛔ ${env.BUILD_USER_ID} started this release and cannot approve it")
          }
          env.APPROVER = decision.APPROVER; env.RISK = decision.RISK
          env.DECISION_MADE_BY = "human:${decision.APPROVER}"
        }
      }
    }

    // ═══════════════ 3' · 🤖 CASE 2 — CANARY + shouldPromote() ═══════════════
    stage("3' · 🤖 canary") {
      when { expression { params.TARGET == 'production' && params.AUTO_PROMOTE } }
      steps {
        lock(resource: 'shop-production-deploy', inversePrecedence: true) {
          milestone(ordinal: 100)
          container('argo') {
            script {
              sh "kubectl argo rollouts set image ${SERVICE} ${SERVICE}='${env.IMAGE_REF}' -n shop-production"
              def analysis = [:]
              timeout(time: 20, unit: 'MINUTES') {
                waitUntil(initialRecurrencePeriod: 15000) {
                  sleep(time: 1, unit: 'MINUTES')
                  analysis = readJSON(text: sh(returnStdout: true,
                    script: "./scripts/canary-metrics.sh shop-production ${SERVICE} 2m").trim())
                  return analysis.requests >= 200        // ⭐ TRUE = stop waiting
                }
              }
              // ⭐⭐ THE ENCODED JUDGEMENT — replaces the human
              def verdict = shouldPromote(
                digest: "@${env.DIGEST}", service: SERVICE, env: 'production',
                smoke: [passed: true, detail: 'dev + staging green'],
                canary: analysis + [minRequests: 200],
                baseline: readJSON(text: env.BASELINE ?: '{"errRate":0,"p99":0.05}'),
                halted: env.HALTED == 'true', frozen: env.FROZEN as boolean,
                migration: [id: 'flyway', backwardCompatible: true],   // ⭐ from CI metadata
                ciBuild: params.CI_BUILD)
              env.VERDICT = verdict.approve ? 'PASS' : 'FAIL'
              env.DECISION_MADE_BY = "shouldPromote()"
              echo verdict.summary
              if (!verdict.approve) {
                sh "kubectl argo rollouts abort ${SERVICE} -n shop-production"   // ⭐ rollback FIRST
                error("⛔ canary rejected: ${verdict.reasons.join('; ')}")
              }
              sh "kubectl argo rollouts promote ${SERVICE} -n shop-production --full=true"
            }
          }
          milestone(ordinal: 101)
        }
      }
    }

    // ═══════════════ 4 · PRODUCTION ═══════════════
    stage('4 · production') {
      when { expression { params.TARGET == 'production' } }
      steps {
        lock(resource: 'shop-production-deploy', inversePrecedence: true) {
          container('kubectl') {
            script {
              // ── CHECK 3 · ⭐ NO DRIFT ACROSS THE GATE ───────────────
              if (env.STAGED_DIGEST && env.STAGED_DIGEST != env.IMAGE_REF) {
                error("⛔ CHECK 3 failed: staging ran ${env.STAGED_DIGEST}, production cleared for ${env.IMAGE_REF}")
              }
              deployDigest('production', runMigration: true)
            }
          }
        }
      }
    }
  }

  // ═══════════════ ⭐⭐ POST — VERIFY, ROLLBACK, HALT, RECORD ═══════════════
  post {
    success {
      container('kubectl') {
        script {
          // ── CHECK 4 · ⭐⭐ READ IT BACK FROM THE CLUSTER ─────────────
          def now = readBack('shop-production')
          if (now != env.IMAGE_REF) {
            error("⛔ CHECK 4 failed: cluster runs '${now}', wanted '${env.IMAGE_REF}'")
          }
          sh "echo '${env.IMAGE_REF}' > /var/jenkins/digests/${SERVICE}-production.txt"
          // ── the audit record: WHO decided, and WHY ─────────────────
          def audit = [timestamp: new Date().format("yyyy-MM-dd'T'HH:mm:ss'Z'", TimeZone.getTimeZone('UTC')),
                       service: SERVICE, environment: 'production', digest: env.DIGEST,
                       imageRef: env.IMAGE_REF, mode: params.AUTO_PROMOTE ? 'deployment' : 'delivery',
                       decidedBy: env.DECISION_MADE_BY, approver: env.APPROVER ?: null,
                       requestedBy: env.BUILD_USER_ID, reason: params.REASON,
                       risk: env.RISK ?: env.VERDICT, ciBuild: params.CI_BUILD, url: env.BUILD_URL]
          writeFile(file: 'audit.json', text: groovy.json.JsonOutput.toJson(audit) + '\n')
          sh 'cat audit.json >> /var/jenkins/audit/cd-decisions.jsonl'
          slackSend(channel: '#releases', color: 'good',
            message: "${params.AUTO_PROMOTE ? '🤖' : '🚢'} *${SERVICE} → production*\nDigest: `${env.DIGEST}`\nDecided by: ${env.DECISION_MADE_BY}\nCI: ${params.CI_BUILD}\n${env.BUILD_URL}")
        }
      }
    }
    failure {
      container('kubectl') {
        script {
          // ── ⭐⭐ ROLLBACK ──────────────────────────────────────────
          sh """
            set +e
            kubectl argo rollouts abort ${SERVICE} -n shop-production 2>/dev/null
            kubectl argo rollouts undo  ${SERVICE} -n shop-production 2>/dev/null \\
              || kubectl -n shop-production rollout undo deploy/${SERVICE}
            kubectl -n shop-production rollout status deploy/${SERVICE} --timeout=300s
          """
          if (params.AUTO_PROMOTE) {
            // ── ⭐⭐ CIRCUIT BREAKER — stop the loop ──────────────────
            sh "mkdir -p /var/jenkins/cd-state && echo 'halted by ${env.BUILD_URL}' > /var/jenkins/cd-state/${SERVICE}.HALTED"
            slackSend(channel: '#releases', color: 'danger',
              message: "🚨 *${SERVICE} auto-rolled back* — 🛑 promotions HALTED\nDigest: `${env.DIGEST}`\nCI: ${params.CI_BUILD}\n${env.BUILD_URL}")
          } else {
            slackSend(channel: '#releases', color: 'danger',
              message: "🚨 ${SERVICE} production deploy FAILED — rolled back\n${env.BUILD_URL}")
          }
        }
      }
    }
    cleanup {
      // ⭐ NEVER clear the halt flag here. Clearing your own circuit
      //   breaker defeats the entire purpose.
      echo "ℹ️ halt flags are cleared by a human or by the scheduled clearCdHalt job."
    }
  }
}
```

---

## 6 · ⭐ The shared library that holds both halves

```
jenkins-shared-library/
├── vars/
│   ├── deployDigest.groovy      ⭐ §6.1 — CD's deploy + read-back + smoke
│   ├── readBack.groovy          ⭐ §6.2 — CHECK 4, used everywhere
│   ├── shouldPromote.groovy     ⭐ §3 of the Case 2 file — the encoded judgement
│   ├── inFreezeWindow.groovy    ⭐ the freeze calendar
│   ├── buildAndPushImage.groovy ⭐ §6.3 — CI's Kaniko + sign + digest
│   └── clearCdHalt.groovy       the scheduled breaker clear
└── src/com/shop/ci/
    └── DigestRef.groovy         ⭐ a typed digest — validates on construction
```

### 6.1 `deployDigest`

```groovy
// vars/deployDigest.groovy — ⭐ ONE implementation of "deploy", for every
//   service and environment. A gate written five times is five chances to
//   get it wrong.
def call(String stageName, Map opts = [:]) {
  def runMigration = opts.get('runMigration', false)
  def svc = env.SERVICE, ns = "${env.NS_PREFIX}-${stageName}", ref = env.IMAGE_REF

  withCredentials([file(credentialsId: "kubeconfig-${stageName}", variable: 'KUBECONFIG')]) {
    // ⭐⭐ CREDENTIAL SCOPE IS THE SECURITY MODEL: `kubeconfig-production`
    //   exists only in /shop-cd. A CI job asking for it FAILS AT RESOLUTION.
    def prev = readBack(ns, svc)
    echo "📌 ${ns} previous: ${prev}"
    if (prev == ref) { echo "ℹ️ already running ${ref} — no-op"; return }   // ⭐ idempotent

    // ── ⭐⭐ MIGRATION FIRST, AS A GATED JOB ──────────────────────────
    if (runMigration) {
      sh """
        set -eu
        kubectl -n ${ns} delete job ${svc}-migrate --ignore-not-found
        kubectl -n ${ns} apply -f k8s/${svc}/migration-job.yaml
        kubectl -n ${ns} wait --for=condition=complete job/${svc}-migrate --timeout=600s \\
          || { echo '⛔ migration FAILED — not rolling out'; exit 1; }
      """
    }

    sh """
      set -eu
      kubectl -n ${ns} apply -f k8s/${svc}/
      kubectl -n ${ns} set image deploy/${svc} ${svc}=${ref}
      kubectl -n ${ns} rollout status deploy/${svc} --timeout=600s \\
        || { kubectl -n ${ns} set image deploy/${svc} ${svc}=${prev}; exit 1; }
    """

    // ── CHECK 4 · ⭐⭐ READ IT BACK ───────────────────────────────────
    def now = readBack(ns, svc)
    if (now != ref) { error("⛔ CHECK 4 failed: ${ns} runs '${now}', wanted '${ref}'") }

    // ── ⭐ SMOKE FROM INSIDE THE CLUSTER ──────────────────────────────
    sh """
      set -eu
      kubectl -n ${ns} run smoke-\$RANDOM --rm -i --restart=Never \\
        --image=curlimages/curl:8.17.0 -- \\
        curl -fsS "http://${svc}.${ns}.svc.cluster.local:${env.PORT}${env.PROBE}"
    """
    echo "✅ ${ns} verified running ${now}"
  }
}
```

### 6.2 `readBack` — the one function that matters most

```groovy
// vars/readBack.groovy
// ⭐⭐ THE SINGLE MOST VALUABLE FUNCTION IN THIS ENTIRE FOLDER.
//   A deploy tool's exit code says the tool ran. This says what is running.
def call(String ns, String svc = env.SERVICE) {
  return sh(returnStdout: true, script:
    // ⭐ the JSONPath NAME FILTER, not [0] — with an init container or a
    //   sidecar, [0] returns the WRONG container and the check silently
    //   passes or silently fails.
    "kubectl -n ${ns} get deploy ${svc} " +
    "-o jsonpath='{.spec.template.spec.containers[?(@.name==\"${svc}\")].image}'"
  ).trim()
}
```

### 6.3 `buildAndPushImage` — CI's half

```groovy
// vars/buildAndPushImage.groovy — ⭐ Kaniko + Trivy + cosign + digest, once
def call(Map o) {
  // o = [service:, context:, dockerfile:'Dockerfile', registry:, tag:, push:]
  def dest = "${o.registry}/${o.service}:${o.tag}"
  container('kaniko') {
    dir(o.context) {
      sh """
        set -eu
        /kaniko/executor --context dir://\$WORKSPACE/${o.context} \\
          --dockerfile ${o.dockerfile} --destination ${dest} \\
          --cache=true --cache-repo=${o.registry}/${o.service}-cache \\
          --cache-copy-layers=true --snapshot-mode=redo \\
          --compressed-caching=false --use-new-run \\
          --label org.opencontainers.image.revision=\$GIT_COMMIT \\
          ${o.push ? '--reproducible' : ''} \\
          --image-name-with-digest-file /tmp/digest.txt
      """
    }
  }
  def full = readFile('/tmp/digest.txt').trim()
  if (!o.push) return [ref: dest, digest: '', published: false]

  container('tools') {
    sh "/tmp/trivy image --exit-code 1 --severity CRITICAL,HIGH --ignore-unfixed '${full}'"
    withCredentials([file(credentialsId: 'cosign-private-key', variable: 'COSIGN_KEY')]) {
      sh "COSIGN_PASSWORD=\"\$COSIGN_KEY_PASSWORD\" /tmp/cosign sign --key \"\$COSIGN_KEY\" --yes '${full}'"
      sh "/tmp/cosign public-key --key \"\$COSIGN_KEY\" > cosign.pub"
    }
  }
  // ⭐⭐ return the DIGEST — this is the artifact contract, in one value
  return [ref: full, digest: full.split('@')[1], published: true,
          cosignPub: readFile('cosign.pub').trim()]
}
```

### 6.4 ⭐ Why a shared library rather than inline Groovy

| Reason | Detail |
|---|---|
| ⭐ **It runs outside the Groovy sandbox** | `JsonOutput`, `readYaml`, `readJSON` need script-security approvals inline. In a library they just work |
| ⭐ **It is unit-testable** | `shouldPromote` is the encoded judgement of a release approver — you want tests for it |
| **One implementation of every gate** | `readBack` written five times is five chances to use `[0]` instead of the name filter |
| **Versioned and reviewed** | a library change is a PR; an inline change is an edit to a job config |

---

## 7 · ⭐⭐ The artifact contract — four checks

| # | Check | Where | What it proves |
|---|---|---|---|
| **1** | ⛔ **digest, not tag** | CD stage 0 regex | the artifact is immutable |
| **2** | ⭐ **provenance** — `cosign verify` with **CI's public key passed as a parameter** | CD stage 0.5 | signed by *our* CI. ⭐ CD holds no signing key, so it cannot forge one |
| **3** | ⭐ **staging ran this exact digest** — `readBack('shop-staging')` | CD stage 4 | no drift across the gate |
| **4** | ⭐⭐ **the cluster runs this digest after deploy** — `readBack('shop-production')` in `post { success }` | the shared library | the deploy actually happened |

**Plus three structural ones, unique to Jenkins:**

| Check | ⭐ How Jenkins enforces it |
|---|---|
| CI cannot deploy | `kubeconfig-*` is in `/shop-cd`'s store → a CI job's `withCredentials` **fails at resolution** |
| CD cannot build | `registry-push` is in `/shop-ci`'s store, **and** CD's pod template has no kaniko container |
| Developers cannot run CD | the **folder** Authorization Matrix: `Job/Read` on `/shop-cd`, no `Job/Build` |

```bash
# ⭐ prove the credential isolation from the Jenkins API
curl -s -u "$U:$T" "$JENKINS_URL/job/shop-ci/credentials/store/folder/api/json?depth=2" \
  | jq '.domains._.credentials[].id'
# ⭐ must NOT contain kubeconfig-production

curl -s -u "$U:$T" "$JENKINS_URL/job/shop-cd/credentials/store/folder/api/json?depth=2" \
  | jq '.domains._.credentials[].id'
# ⭐ must NOT contain registry-push or cosign-private-key

# and prove the RBAC
curl -s -u "$DEV_USER:$T" -o /dev/null -w '%{http_code}\n' \
  "$JENKINS_URL/job/shop-cd/job/cd-shop-api/build"     # ⭐ must be 403
```

---

## 8 · The permission map

| Folder | Credentials in scope | Who can build | Pod agents |
|---|---|---|---|
| `/shop-ci` | `registry-push`, `cosign-private-key`, `trivy-db` | developers + `ci-service` | `pool: ci`, SA `jenkins-ci-agent` |
| `/shop-cd` | ⭐ `kubeconfig-{dev,staging,production}`, `cosign-public-key`, `slack`, `pagerduty`, `halt-token` | ⭐ **`platform-leads` only** | `pool: cd`, SA `jenkins-cd-agent` |
| `/shop-rollback` | `kubeconfig-production` | ⭐ `platform-leads` + `on-call` | `pool: cd` |

```
⭐ THREE KUBERNETES SERVICEACCOUNTS, THREE RBAC ROLES:
   jenkins-ci-agent  → nothing in the cluster. It builds images. That is all.
   jenkins-cd-agent  → get/patch/update on deployments, jobs, rollouts in shop-*
   jenkins-rollback  → ⭐ the same, PLUS delete — and it is a separate SA so
                       the routine deploy path cannot delete anything.
```

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: { name: jenkins-cd, namespace: shop-production }
rules:
  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["get","list","watch","patch","update"]        # ⛔ NO delete
  - apiGroups: ["batch"]
    resources: ["jobs"]
    verbs: ["get","list","watch","create","delete","patch"]
  - apiGroups: ["argoproj.io"]
    resources: ["rollouts","rollouts/scale","rollouts/status"]
    verbs: ["get","list","watch","patch","update"]
  - apiGroups: [""]
    resources: ["pods","pods/log","services","events","configmaps"]
    verbs: ["get","list","watch"]
  # ⛔ NO `delete` on deployments. Rollback uses `set image` / `rollout undo`,
  #   which are patch verbs — so a bug in the CD path cannot delete production.
```

---

## 9 · 🔒 Case 1 or 🤖 Case 2 — one boolean

```groovy
booleanParam(name: 'AUTO_PROMOTE', defaultValue: false,
             description: '🤖 true = Case 2. 🔒 false = Case 1.')
```

| | `AUTO_PROMOTE=false` 🔒 | `AUTO_PROMOTE=true` 🤖 |
|---|---|---|
| Stage `3 · 🔒 approval` | ✅ runs `input`, waits | ⛔ `when` excludes it |
| Stage `3' · 🤖 canary` | ⛔ excluded | ✅ runs Argo Rollouts + `shouldPromote()` |
| Circuit breaker | ⛔ not set (a human rolls back) | ✅ set on failure |
| Freeze check | ✅ blocks | ✅ blocks |
| Rollback | ⭐ the separate `/shop-rollback` job, ungated | ⭐ `post { failure }`, automatic |
| `DECISION_MADE_BY` | `human:<approver>` | `shouldPromote()` |
| Overall timeout | 72 h (the `input` wrapper) | ⭐ 90 min |

⭐⭐ **What the boolean cannot do — and must not:**
1. It does **not** change who may run the job. That is the **folder** Authorization Matrix (§8). A developer who can set `AUTO_PROMOTE=true` but cannot build the CD job at all is correctly excluded.
2. It does **not** remove `submitterPermissionCheck`. In Case 1 that flag is the control; leaving it off makes the `submitter` list documentation.
3. It does **not** create the prerequisites. `AUTO_PROMOTE=true` on a service with no `shouldPromote` metrics, no Argo Rollouts and no tested rollback is not Case 2 — it is **unattended deployment**.

**Per-service, which is what a real estate uses:**

```groovy
// ⭐ in a seed job / JCasC, not hardcoded per Jenkinsfile
[ [service:'shop-ui',      autoPromote: true ],     // 🤖 FE — lowest risk
  [service:'payment-mock', autoPromote: true ],     // 🤖 the pilot
  [service:'checkout',     autoPromote: true ],     // 🤖 stateless Go
  [service:'order-worker', autoPromote: false],     // 🔒 cannot be canaried
  [service:'shop-api',     autoPromote: false] ]    // 🔒 migrations
```

---

## 10 · ▶️ Run it end to end — the full acceptance checks

```bash
J=$JENKINS_URL; U=user; T=token

# ── CI HALF ────────────────────────────────────────────────────────────
# 1 · ⭐ CI's folder has NO kubeconfig credential
curl -s -u "$U:$T" "$J/job/shop-ci/credentials/store/folder/api/json?depth=2" \
  | jq -r '.domains._.credentials[].id' | grep -q kubeconfig \
  && echo "⛔ CI can deploy" || echo "✅ CI cannot deploy"

# 2 · CI's pod template has no docker socket
grep -c 'docker.sock\|privileged: true' jenkins/ci-shop-api.Jenkinsfile   # ⭐ must be 0

# 3 · CI does not push on a PR
grep -q "CHANGE_ID == null" jenkins/ci-shop-api.Jenkinsfile && echo "✅ PR-safe"

# 4 · the digest file exists after a main build
cat /var/jenkins/digests/shop-api-main.txt     # ⭐ repo@sha256:<64 hex>

# ── THE CHAIN ──────────────────────────────────────────────────────────
# 5 · ⭐⭐ THE END-TO-END TEST: push a commit and watch BOTH jobs
git commit --allow-empty -m "e2e: trigger CI+CD" && git push origin main
watch -n 10 "curl -s -u '$U:$T' '$J/job/shop-ci/job/ci-shop-api/job/main/lastBuild/api/json?tree=number,result,building' ; echo; \
             curl -s -u '$U:$T' '$J/job/shop-cd/job/cd-shop-api/lastBuild/api/json?tree=number,result,building'"
# ⭐ CI must succeed, THEN CD must appear with NO human action

# ── CD HALF ────────────────────────────────────────────────────────────
# 6 · ⭐ CD's folder has NO registry-push credential
curl -s -u "$U:$T" "$J/job/shop-cd/credentials/store/folder/api/json?depth=2" \
  | jq -r '.domains._.credentials[].id' | grep -qE 'registry-push|cosign-private' \
  && echo "⛔ CD can publish" || echo "✅ CD cannot publish"

# 7 · CD's pod template has no build toolchain
grep -cE 'kaniko|maven|node|golang' jenkins/cd-shop-api.Jenkinsfile   # ⭐ must be 0

# 8 · a developer CANNOT run CD
curl -s -u "$DEV:$T" -o /dev/null -w '%{http_code}\n' \
  "$J/job/shop-cd/job/cd-shop-api/build"        # ⭐ must be 403

# 9 · all four contract checks are present
grep -c 'CHECK 1\|CHECK 2\|CHECK 3\|CHECK 4' jenkins/cd-shop-api.Jenkinsfile vars/*.groovy

# 10 · a TAG is refused
curl -s -u "$U:$T" -X POST "$J/job/shop-cd/job/cd-shop-api/buildWithParameters" \
  --data-urlencode 'IMAGE=shopacr.azurecr.io/shop-api:latest' --data-urlencode 'REASON=neg'
sleep 30
curl -s -u "$U:$T" "$J/job/shop-cd/job/cd-shop-api/lastBuild/api/json" | jq -r '.result'
# ⭐ must be FAILURE, at stage 0

# 11 · ⭐ CHECK 4 — what is ACTUALLY running
kubectl -n shop-production get deploy shop-api \
  -o jsonpath='{.spec.template.spec.containers[?(@.name=="shop-api")].image}{"\n"}'
# ⭐ must equal the digest from check 4

# 12 · the audit record answers BOTH "who approved?" and "what decided?"
jq -r '"\(.timestamp) \(.service) mode=\(.mode) by=\(.decidedBy) \(.digest[0:19])"' \
  /var/jenkins/audit/cd-decisions.jsonl | tail -10

# 13 · ⭐⭐ rollback is ungated
grep -c 'input(' jenkins/rollback-shop-api.Jenkinsfile   # ⭐ must be 0
```

⭐⭐ **Checks 1, 5, 6 and 11 are the four that matter.** 1 and 6 prove the credential asymmetry **in Jenkins' own credential store**, not in the Jenkinsfile; 5 proves the chain fires on a real commit; 11 proves what CI published is literally what production runs.

---

## 11 · Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| ⛔ CD never triggers | `build job:` used a **relative** path | ⭐ absolute: `/shop-cd/cd-shop-api` |
| `params.IMAGE` is blank in CD | you used `triggers { upstream(...) }`, which passes **nothing** | §2.1 — `build job:` with explicit parameters |
| CI builds slow after adding the trigger | ⛔ `wait: true` | `wait: false` |
| `withCredentials` cannot find `kubeconfig-production` | ⭐ **correct behaviour** — it is in another folder | that is the security model, not a bug |
| A CI job *can* read CD's credentials | the credential is **global**, not folder-scoped | §8 — move it into `/shop-cd`'s store |
| ⛔ Kaniko fails with `permission denied` on `/var/lib/docker` | something mounted the Docker socket | remove it. Kaniko needs no daemon |
| Kaniko OOMs | `--compressed-caching` defaults to true | `--compressed-caching=false` (§3) |
| Kaniko layers never cache | no `--cache-repo`, or the PVC is not `ReadWriteMany` across nodes | §3 — a registry-backed cache avoids the PVC problem entirely |
| ⛔ Testcontainers fails on a pod agent | no Docker daemon | §4.1 — a sidecar Postgres, Testcontainers Cloud, or a VM agent |
| `digest.txt` contains a tag, not a digest | `--image-name-with-digest-file` missing | §3 |
| `cosign verify` fails in CD | `params.COSIGN_PUB` empty (manual run, or CI did not sign) | ⭐ pass it explicitly; fall back to a stored public-key credential |
| ⛔ `cosign sign` prompts and hangs | `COSIGN_PASSWORD` unset | bind it from the credential |
| `readBack` returns the sidecar's image | JSONPath `[0]` instead of the name filter | §6.2 |
| `shouldPromote` rejected by the Groovy sandbox | `JsonOutput` / `readYaml` inline | ⭐ move it into the shared library (§6.4) |
| Both the `input` and the canary stage ran | `when { expression { … } }` used `params.AUTO_PROMOTE` as a String | compare with `== true`, or `!params.AUTO_PROMOTE` |
| `waitUntil` loops forever | ⛔ no enclosing `timeout()` | §5 stage 3' |
| ⛔ Paged repeatedly | no halt flag | `post { failure }` sets it (§5) |
| Halted runs are red | `error()` instead of `currentBuild.result = 'NOT_BUILT'` + `return` | §5 stage 0 |
| Agents exhausted | soaks occupy agents; CI and CD share a pool | ⭐ separate `nodeSelector` pools + `throttle-concurrents` |

---

<a name="tasks--answers"></a>
## 12 · ⭐ TASKS — answers at the END

| # | Task |
|---|---|
| **T1** | Create `/shop-ci` and `/shop-cd` with folder-scoped credentials, and prove a CI job cannot resolve `kubeconfig-production` |
| **T2** | Replace the Docker-socket build with Kaniko and emit the digest via `--image-name-with-digest-file` |
| **T3** | Wire `build job:` chaining with all four guards, and explain why an upstream trigger is worse |
| **T4** | Solve Testcontainers on a Kubernetes pod agent, and state the trade-off of each option |
| **T5** | Implement all four artifact-contract checks in the shared library and demonstrate each failing |
| **T6** | Write `readBack` correctly and explain why `[0]` is a silent-failure bug |
| **T7** | Make `AUTO_PROMOTE` switch between Case 1 and Case 2, and list what it cannot do |
| **T8** | Give CI, CD and rollback three separate Kubernetes ServiceAccounts with three RBAC roles |
| **T9** | Chain FE after BE for shape C across the two-folder architecture |
| **T10** | ⭐⭐ A malicious Maven dependency executes during `mvn verify` in your CI pod. Describe precisely what it can and cannot do — and name the three configuration mistakes that would give it production access |

---

# ✅ ANSWERS

**T1.** Create both folders with the **Folder-based Authorization Matrix** property; add `registry-push` and `cosign-private-key` to `/shop-ci`'s credential store and `kubeconfig-{dev,staging,production}` + `slack` + `pagerduty` to `/shop-cd`'s. **The proof is a failing `withCredentials`:** add a step to the CI Jenkinsfile —
```groovy
withCredentials([file(credentialsId: 'kubeconfig-production', variable: 'KC')]) { sh 'echo hi' }
```
— and run it. ⭐ **It fails at resolution** with `No credentials found for 'kubeconfig-production'`, before any step executes. Then verify from the API (§10 checks 1 and 6): `/shop-ci`'s store lists no `kubeconfig-*`, and `/shop-cd`'s lists no `registry-push` or `cosign-private-key`. Finally check the RBAC: `curl -u $DEV:$T -X POST $J/job/shop-cd/job/cd-shop-api/build` returns **403**. ⭐ **Why folder scope rather than a YAML rule:** a credential that exists globally can be named by any job that can execute Groovy — and a malicious Maven dependency executing inside a `sh` step can read `$KUBECONFIG` from its own environment if any enclosing step bound it. Folder scope makes the credential *unresolvable*, so there is nothing to bind and nothing to leak.

**T2.** §3 and §4. Replace the docker container with `gcr.io/kaniko-project/executor:v1.25.0`, mount the registry auth as a **Secret** at `/kaniko/.docker/config.json` (items: `.dockerconfigjson` → `config.json`), and run `/kaniko/executor --context dir://$WORKSPACE/apps/shop-api --dockerfile Dockerfile --destination $REGISTRY/$SERVICE:$TAG … --image-name-with-digest-file /tmp/digest.txt`. ⭐ **That last flag is the whole point:** Kaniko writes `repo@sha256:…` directly, so you never resolve a digest *from a tag* — which would be a second registry round-trip and a race if anything re-pushed the tag. Add `--cache=true --cache-repo=…-cache --cache-copy-layers=true` for layer caching, `--compressed-caching=false` (⭐ the default can OOM the agent on large Java layers), `--snapshot-mode=redo` for speed, and `--reproducible` so the same input yields the same digest. **Why no Docker socket:** mounting `/var/run/docker.sock` gives the build **root on the node** — `docker run -v /:/host alpine chroot /host` and it can read every other pod's secrets and the kubelet certificate. Since CI runs `mvn verify` (third-party code), that mount is equivalent to handing your cluster to your dependency tree. Kaniko needs no daemon, runs as non-root, and needs no `privileged: true` — set `securityContext.runAsNonRoot: true` at the pod level so the constraint is enforced rather than assumed.

**T3.** §2.1. In CI's `post { success }`: `build job: '/shop-cd/cd-shop-api', parameters: [string(name:'IMAGE', value: env.IMAGE_REF), …], wait: false, propagate: false`, guarded by `if (env.BRANCH_NAME == 'main' && env.CHANGE_ID == null && env.IMAGE_REF)`. **The four guards:** ⭐ the **absolute path** (`/shop-cd/…`), because a relative name resolves inside `/shop-ci` and either fails or — worse — finds a *different* job; `CHANGE_ID == null`, because in a multibranch pipeline `CHANGE_ID` is set for PR builds, so this is the fork/PR guard; `env.IMAGE_REF` non-empty, so a docs-only or unpublished build does not trigger CD with nothing to deploy; and `wait: false` with `propagate: false`. ⭐ **Why an upstream trigger is worse:** `triggers { upstream(upstreamProjects: 'ci-shop-api', threshold: SUCCESS) }` is *simple* — and it passes **no parameters**. So `params.IMAGE` is blank and CD falls back to "read the latest digest file", which reintroduces exactly the race the digest contract exists to prevent: two commits in quick succession, and CD may deploy the second while recording the first. `build job:` passes the exact digest, the exact commit SHA and a link back to the CI build, so the chain is explicit and auditable. `wait: true` is a separate mistake: it holds a **CI executor** for the entire CD run including a 10-minute canary soak, so ten services' CI builds queue behind ten CD soaks.

**T4.** §4.1. Three options, each with a real trade-off:
- **(a) ⭐ A sidecar Postgres in the pod template** — `postgres:17.7` as a container with a `pg_isready` readiness probe, and tests pointed at `localhost:5432` with Testcontainers disabled (`@ActiveProfiles("ci-sidecar")`). **Cheapest, and it is a real Postgres**, so the tests are meaningful — no H2-in-compatibility-mode fiction. ⭐ **The trade-off:** one shared database for the whole build, so tests cannot rely on isolation. Use `@Transactional` tests (rolled back per test) or explicit truncation between classes; a suite with ordering dependencies will produce intermittent failures that look like flakiness and are actually shared state.
- **(b) Testcontainers Cloud** — a remote daemon. ⭐ Zero cluster risk, real per-test isolation, no Jenkinsfile changes beyond an env var. Costs money, and adds an external dependency to your build.
- **(c) A VM agent with Docker installed** — the tests run unmodified. ⛔ But the agent is now a **pet**: it accumulates images, volumes and state between builds, which is a cache-poisoning surface and a maintenance burden. If you take this option, restrict it to the `/shop-ci` folder and reprovision it on a schedule.
- ⛔ **Never:** mount the node's Docker socket into the pod (§3/T2) — that is root on the node, from a container running your dependency tree.

**The recommendation:** (a) for this estate, because the `shop-api` integration tests are `@SpringBootTest` + `@Transactional` and do not need per-test databases; (b) the moment isolation becomes a real requirement or the sidecar starts causing ordering failures.

**T5.** §6 and §7. **(1) digest shape** — the regex in CD stage 0; demonstrate with `buildWithParameters IMAGE=…:latest` → `⛔ CHECK 1 failed`. **(2) provenance** — `cosign verify --key /tmp/cosign.pub "$IMAGE_REF"` where the public key arrives as a **CI parameter**; demonstrate by pushing an image by hand with the ACR credentials and passing its digest → verification fails. ⭐ Note the design: **CD receives the public key, never the private one**, so CD cannot forge a signature even if compromised — and `cosign-private-key` lives in `/shop-ci`'s store where CD cannot resolve it. **(3) no drift** — CD stage 4 compares `env.STAGED_DIGEST` (⭐ produced by `readBack('shop-staging')`, i.e. read from the cluster, not forwarded from the input) against `env.IMAGE_REF`; demonstrate by queueing CD with a different digest than staging ran. **(4) confirmed running** — `readBack('shop-production')` inside `deployDigest` after `rollout status`, and again in `post { success }`; demonstrate by mistyping the container name in `set image`, which exits 0 and is caught only here. **Putting all four in the shared library matters:** `deployDigest` and `readBack` are used by every service, so no service can opt out. ⭐ A gate written once in a library is a gate; written five times inline, it is five chances to use `[0]` instead of the name filter.

**T6.** §6.2: `kubectl -n $ns get deploy $svc -o jsonpath='{.spec.template.spec.containers[?(@.name=="'$svc'")].image}'`. ⭐ **Why `[0]` is a silent-failure bug:** `spec.template.spec.containers[0]` is "the first container in the list", which is only the application container *by convention*. Add a sidecar — a service-mesh proxy, a log shipper, an OTel collector — and ordering is not guaranteed by anything you control. Two failure modes, both silent: if the sidecar sorts first, `readBack` returns the **sidecar's** image, which never equals your digest, so CHECK 4 fails on every deploy and someone eventually deletes the check to make the pipeline green; if you compare against the wrong container in the *other* direction, `set image deploy/x x=<ref>` may target a container that does not exist and **succeed without changing anything**, and `readBack` with `[0]` would confirm the sidecar and pass. Either way you get a green pipeline and an unverified deployment. The JSONPath **filter** `[?(@.name=="shop-api")]` selects by the name you actually set the image on, so the assertion is about the right container by construction. ⭐ **The same filter belongs in the `kubectl set image` verification, the audit record, and the "what is running in production?" one-liner** — all three are the same query, and it should exist once, in `readBack`.

**T7.** §9. `booleanParam(name: 'AUTO_PROMOTE', defaultValue: false)` with `when { expression { params.TARGET == 'production' && !params.AUTO_PROMOTE } }` on the `input` stage and `&& params.AUTO_PROMOTE` on the canary stage. Plus: the circuit breaker set only in Case 2, `DECISION_MADE_BY` recording `human:<approver>` versus `shouldPromote()`, and the overall `timeout` dropping from 72 h to 90 min.

**What it cannot do — and must not:**
1. ⭐ **It does not change who may run the job.** That is the **folder** Authorization Matrix (§8). This matters because `AUTO_PROMOTE` is a *build parameter*: anyone who can trigger the job can set it. If developers had `Job/Build` on `/shop-cd`, they could bypass the human gate by ticking a box — so the real Case 1/Case 2 control is *who can run CD at all*, and the boolean only selects the mechanism.
2. **It does not remove `submitterPermissionCheck`.** In Case 1 that flag is what turns the `submitter` list from documentation into a control.
3. ⭐⭐ **It does not create the prerequisites.** `AUTO_PROMOTE=true` on a service with no metrics for `shouldPromote`, no Argo Rollouts installed and no tested rollback is not Case 2 — it is **unattended deployment**, which is Case 1's pipeline with the safety removed. The five prerequisites in [`../scenario-2-cd-only/00-delivery-vs-deployment.md`](../scenario-2-cd-only/00-delivery-vs-deployment.md) §6 are properties of the *service*, and no boolean can confer them.
4. **It should not be per-run for a given service.** Set it in a seed job or JCasC per service (§9's table) so the policy is configuration, reviewed and versioned — not a checkbox someone flips during an incident.

**T8.** §8. Three ServiceAccounts bound to three Roles: `jenkins-ci-agent` with **no cluster RoleBinding at all** (it builds images; it never talks to the API server — the pod's SA still needs enough to exist, but no `shop-*` namespace permissions); `jenkins-cd-agent` with `get/list/watch/patch/update` on `apps/deployments` and `argoproj.io/rollouts`, `create/delete` on `batch/jobs` (the migration Job), and `get/list/watch` on pods, logs, services, events and configmaps — ⭐ **no `delete` on deployments**, because rollback is `set image` or `rollout undo`, both patch verbs, so a bug in the routine deploy path cannot delete production; `jenkins-rollback` with the same **plus** `delete`, used only by the `/shop-rollback` folder's job. Wire them via `serviceAccountName` in each pod template and `nodeSelector: {pool: ci|cd}` for separate node pools. ⭐ **Why three rather than one:** the CD path runs on every release and is the least-reviewed code in the estate (shell inside Groovy inside a YAML string). Giving the routine path no `delete` means the worst case is "the deploy fails", not "production is deleted" — and giving rollback its own SA keeps the destructive capability behind a separate folder, separate permissions and a separate audit trail. **Pair it with the folder credential map (§8):** SA identity is what the *cluster* sees; folder credentials are what *Jenkins* can bind. You need both, because a broad SA with narrow Jenkins credentials is still one leaked kubeconfig away from being broad.

**T9.** Two options, and ⭐ the second is better in Jenkins:
- **(a) `build job:` from `cd-shop-api`'s `post { success }`** → `/shop-cd/cd-shop-ui`, `wait: false`. Simple, mirrors the CI→CD chain, and each service keeps its own job, halt flag and audit record.
- **(b) ⭐ a release-train job** `/shop-cd/cd-shop-release` that reads `release-manifest.txt` and calls `deployDigest` for each service in dependency order inside **one `lock` and one `input`**.

```groovy
stage('production') {
  steps {
    lock(resource: 'shop-production-deploy', inversePrecedence: true) {
      milestone(ordinal: 100)
      container('kubectl') {
        script {
          // ⭐⭐ BACKEND FIRST
          env.SERVICE = 'shop-api'; deployDigest('production', runMigration: true)
          env.SERVICE = 'shop-ui';  deployDigest('production', runMigration: false, probe: '/')
          // then the PAIR check: curl the FE, assert config.js has the prod
          // API_URL, curl the BE through the Service, assert both 200
        }
      }
      milestone(ordinal: 101)
    }
  }
}
```
**Three decisions, each with a reason:** ⭐ **backend first**, because the backend must serve *both* the old and the new frontend at every instant — cached frontends persist for as long as browser cache dictates, a duration you do not control. ⭐ **One `input`, not two**, because the human authorised *this release* and the pair is the release; two prompts invite approving the FE after the BE failed, which produces exactly the half-promoted state. ⭐ **Roll back both on FE failure**, because new-UI-against-old-API is a state nobody tested and is worse than either consistent state — and that is only safe if the backend's migrations are expand/contract. **Choose (b) when the pair must move together** (it gives one lock, one approval, one audit record and one rollback decision); **choose (a) when the services are genuinely independent**, which is the better long-term answer and is only possible because the backend's API is backward-compatible.

**T10.** ⭐⭐ **What it CAN do:** read everything in the CI pod — the source, the `/home/jenkins/.m2` PVC cache, any credential bound by an enclosing `withCredentials` (⭐ including `cosign-private-key` during stage 5, which is why it should be bound as narrowly and as briefly as possible), and the `jenkins-ci-agent` ServiceAccount token mounted at `/var/run/secrets/kubernetes.io/serviceaccount`. With `registry-push` it can **push an image to ACR**. It can make arbitrary outbound network calls — exfiltrating source, or fetching a second stage. It can tamper with the build output, so the published artifact does not correspond to the commit. It can poison the **`.m2` PVC and the Kaniko layer cache**, persisting into every future build — ⭐ the most under-appreciated capability, because it outlives the compromised build and is invisible in any single build log. And it can sign the tampered image with the CI cosign key if it executes while that key is bound.

**What it CANNOT do:** deploy. `kubeconfig-production` is in `/shop-cd`'s credential store, so `withCredentials` **fails at resolution** — there is nothing to bind and nothing to read from the environment (§T1). The `jenkins-ci-agent` SA has **no RoleBinding in any `shop-*` namespace**, so even with a token the API server refuses. The pod runs `runAsNonRoot: true` with `seccompProfile: RuntimeDefault` and **no Docker socket**, so there is no path to the node (§T2). It cannot reach dev, staging or production clusters, cannot approve anything, and cannot run the CD job — the folder Authorization Matrix gives developers and the CI service account no `Job/Build` on `/shop-cd`. And it cannot get a bad image into production **by itself**: CD independently verifies the cosign signature, `deployDigest` asserts staging ran that exact digest, and in Case 1 a human reads the staging report first.

⭐ **The realistic damage is a poisoned-but-validly-signed artifact that CD will happily deploy** — the signature is genuine (it *was* signed by your CI), so CHECK 2 passes, and in Case 2 nobody looks. Mitigations: pin dependencies, keep `dependency-check` as a gate (not a warning), review dependency changes on PRs, diff the SBOM between releases, and ⭐ **narrow the cosign key's binding window** — sign in its own stage with `withCredentials` scoped to a single `sh`, and `shred` the key file after, rather than binding it for the whole pipeline.

**The three configuration mistakes that would give it production access:**
1. ⛔ **One folder instead of two** (§1). With CI and CD in the same folder, `kubeconfig-production` is resolvable from the CI job, and the distance from `mvn verify` to `kubectl -n shop-production set image …` is one `sh` step. This is the mistake that undoes everything else.
2. ⛔ **Mounting `/var/run/docker.sock` into the CI pod** "so Testcontainers works" (§3, §T4). That is **root on the node**: `docker run -v /:/host alpine chroot /host` reads every pod's secrets, every credential file and the kubelet certificate — including CD's kubeconfig if it is mounted anywhere on that node. It converts a folder-scoping success into a total compromise, and it is by far the most common way this happens in practice, because the error message that prompts it (`Could not find a valid Docker environment`) looks like a configuration problem rather than a security boundary.
3. ⛔ **Global credentials "to get it working"** — adding `kubeconfig-production` to Jenkins' *global* store because a folder-scoped lookup failed during setup. The credential then resolves from any job in any folder. ⭐ The symptom is subtle: everything works, and the isolation you designed silently stops existing. Check it with §10 checks 1 and 6, which query the **folder** stores specifically, and add them to a periodic audit.

Two near-misses with the same outcome: a **shared agent pool** for CI and CD (credential isolation is per-folder, but the *node* is not — a persistent agent keeps files, caches, Docker images and env between jobs, so use `nodeSelector: {pool: ci|cd}` and ephemeral pods); and **`printPostContent: true` / echoing bound credentials** in a Generic Webhook Trigger or a debug step, which writes secrets into build logs that are readable by anyone with `Job/Read`.

⭐ **The general principle: in Jenkins the security boundary is credential scope plus RBAC plus the pod spec — not the Jenkinsfile's discipline. So "one folder or two?", "socket or Kaniko?" and "global or folder-scoped?" are security questions, and the answers are two, Kaniko, and folder-scoped.**

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish_Kumar_Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn: https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260
🔗 GitHub: https://github.com/3558Bhk

*Two folders, no Docker socket, one `readBack`. Credential scope is the boundary — not your Jenkinsfile's discipline.*

</div>
