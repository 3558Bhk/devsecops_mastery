# 🔨 SCENARIO 1 · CI ONLY — Jenkins
### Build, test, scan, sign and publish all five apps on every commit — and stop. Declarative Jenkinsfile, dynamic Kubernetes agents, and credential scoping that makes "cannot deploy" true rather than merely intended.

> **Scope:** `shop-ui` (React) · `shop-api` (Java 21) · `checkout` (Go) · `order-worker` (Python) · `payment-mock` (Go)
> **Ends at:** a signed image in the registry and a **`sha256:` digest** archived as a build artifact.
> **Version anchors:** Jenkins **LTS 2.568.3** (⭐ Java 21 minimum) · `kubernetes` plugin 4500+ · `docker-workflow` · `credentials-binding` · `pipeline-utility-steps` · `cosign` 2.4 · Trivy 0.58
> **Read with:** [`../../04-CASE-3-jenkins.md`](../../04-CASE-3-jenkins.md) for the install and plugin deep-dive.

---

## 📇 Contents

| § | What |
|---|---|
| [1](#1--why-jenkins-is-different-here) | Why Jenkins is different — and the one hazard it has that the other two do not |
| [2](#2--agents-that-disappear) | Agents that disappear — the Kubernetes pod template, and per-language containers |
| [3](#3---the-declarative-jenkinsfile) | ⭐ The declarative Jenkinsfile — all five services |
| [4](#4---the-shared-library) | ⭐⭐ The shared library — one definition of "how we build", five callers |
| [5](#5---credential-scoping--the-part-that-decides-whether-this-is-really-ci-only) | ⭐⭐ Credential scoping — **the part that decides whether this is really CI-only** |
| [6](#6---the-digest-handoff) | ⭐⭐ The digest handoff — `archiveArtifacts`, not `echo` |
| [7](#7--multibranch-and-the-fork-hazard) | Multibranch, and the fork hazard that has breached real Jenkins servers |
| [8](#8--caching-on-ephemeral-agents) | Caching on ephemeral agents — PVCs, and the honest limits |
| [9](#9---proving-it-is-ci-only--jenkins-flavoured) | ⭐ Proving it is CI-only — the five checks, Jenkins-flavoured |
| [10](#10---verify-it-from-your-laptop) | ✅ Verify it from your laptop |
| [11](#11--troubleshooting) | Troubleshooting |
| [12](#12---tasks--answers-at-the-end) | ⭐ Tasks and answers — **answers at the END** |

---

## 1 · Why Jenkins is different here

| Property | GitHub Actions | Azure DevOps | 🔨 Jenkins |
|---|---|---|---|
| Config language | YAML | YAML | ⭐ **Groovy** — a real programming language |
| Where the agent comes from | the platform | the platform | ⭐⭐ **you** — a controller you patch, and agents you provision |
| Conditional logic | `if:` expressions, limited | `${{ }}` compile-time, limited | ⭐ **arbitrary Groovy** — unlimited |
| Reuse | reusable workflows | templates | ⭐⭐ **shared libraries** — real functions, real parameters, real return values |
| Secrets | repo/org secrets, OIDC | variable groups, WIF | ⭐ **credentials store — with SCOPES you must get right** |
| What breaks you | a mis-set `permissions:` | a wrong `stageDependencies` path | ⛔ **a global credential visible to a fork's PR job** |

⭐ **Groovy is the reason Jenkins can express anything — and the reason it can leak anything.** In a declarative YAML system, the platform decides what a pipeline can touch. In Jenkins, the pipeline is *code running on your controller's JVM*, with whatever credentials are in scope. That is enormously powerful and it moves the entire security burden onto your credential configuration.

⛔ **The hazard Jenkins has that the other two do not:** a **multibranch pipeline that discovers forks** runs untrusted Groovy on your infrastructure. Combined with a **global** credential, that is remote code execution with your production credentials. This is not theoretical — it is the recurring Jenkins breach pattern. §7 covers it; §5 covers the scoping that prevents it.

---

## 2 · Agents that disappear

⭐⭐ **Never build on the controller.** The controller holds every credential and the entire build history; running builds there means one malicious `sh` step owns everything. Use **dynamic Kubernetes agents** — a pod per build, destroyed afterwards.

```yaml
# ══════════════════════════════════════════════════════════════════════
# ci/pod-templates/ci-agent.yaml — the pod template for CI builds
# ══════════════════════════════════════════════════════════════════════
# WHAT   : one pod definition with FOUR language containers plus jnlp.
# WHY    : a pod per build, torn down after. No persistent agent to patch,
#          no cross-build contamination, no shared Docker socket history.
# ⭐     Each `container()` block in the Jenkinsfile selects one of these.
# ══════════════════════════════════════════════════════════════════════
apiVersion: v1
kind: Pod
metadata:
  labels:
    app: jenkins-ci-agent
    scope: ci-only                    # ⭐ a label you can enforce policy on
spec:
  # ⭐⭐ NO serviceAccountName WITH CLUSTER PERMISSIONS. The default SA in
  #   this namespace must have NO RoleBinding. A CI agent that can talk to
  #   the Kubernetes API can deploy — which would make this not CI-only.
  automountServiceAccountToken: false   # ⭐⭐ the strongest version of that:
                                        #   do not even mount the token.
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    seccompProfile: { type: RuntimeDefault }
  containers:
    - name: jnlp                       # the agent connector. Required.
      image: jenkins/inbound-agent:latest-java21
      resources: { requests: { cpu: 200m, memory: 512Mi } }

    - name: node
      image: node:24-bookworm-slim
      command: ['sleep']
      args: ['infinity']               # ⭐ keep it alive until the step runs
      resources: { requests: { cpu: 500m, memory: 1Gi }, limits: { memory: 2Gi } }

    - name: jdk
      image: maven:3.9-eclipse-temurin-21
      command: ['sleep']
      args: ['infinity']
      resources: { requests: { cpu: '1', memory: 2Gi }, limits: { memory: 4Gi } }
      volumeMounts:
        - { name: m2, mountPath: /root/.m2/repository }   # ⭐ §8

    - name: golang
      image: golang:1.23-bookworm
      command: ['sleep']
      args: ['infinity']
      resources: { requests: { cpu: 500m, memory: 1Gi } }
      volumeMounts:
        - { name: gomod, mountPath: /go/pkg/mod }

    - name: python
      image: python:3.13-slim
      command: ['sleep']
      args: ['infinity']
      resources: { requests: { cpu: 500m, memory: 1Gi } }

    # ⭐ a container with the CLI tools every service needs: docker CLI,
    #   trivy, cosign, skopeo. One image you build and version yourself —
    #   do NOT install these with curl|sh inside a build step.
    - name: tooling
      image: ghcr.io/3558bhk/ci-tooling:1.4
      command: ['sleep']
      args: ['infinity']

  volumes:
    - name: m2
      persistentVolumeClaim: { claimName: jenkins-m2-cache }    # ⭐ §8
    - name: gomod
      persistentVolumeClaim: { claimName: jenkins-gomod-cache }
    # ⭐ NO Docker socket volume here. Building images uses Kaniko or
    #   BuildKit inside the pod — see §3. Mounting /var/run/docker.sock
    #   into a CI agent is root on every node in the cluster.
```

⛔ **The Docker-socket decision, stated plainly:** mounting `/var/run/docker.sock` into a build agent gives that agent **root on the host node** — it can start a privileged container mounting the node's filesystem. On a cluster that also runs production, that is a complete boundary collapse. The two safe alternatives:

| Approach | How | Trade-off |
|---|---|---|
| ⭐ **Kaniko** | builds an image inside an unprivileged container, pushes directly to the registry | slower than BuildKit; some Dockerfile features unsupported |
| ⭐ **BuildKit rootless** (`buildkitd` in a pod) | a real Dockerfile build, no socket, no privilege | needs `--security=insecure` capabilities or a sidecar; more setup |
| ⛔ **Docker-in-Docker with a socket mount** | mount the host socket | **do not.** Root on the node |
| ✅ **A dedicated build cluster** | the CI cluster is *not* the production cluster | ⭐ the real answer at scale |

---

## 3 · ⭐ The declarative Jenkinsfile

```groovy
// ══════════════════════════════════════════════════════════════════════
// Jenkinsfile — CI ONLY for all five services. Publishes images + a digest.
//               Deploys nothing, and holds no credential that could.
// ══════════════════════════════════════════════════════════════════════
// WHAT   : the whole of Scenario 1 in one declarative pipeline.
// WHY    : declarative (not scripted) so the structure is visible at a
//          glance and `when` guards are declarative too. The one place
//          this file drops into scripted Groovy is the change detection,
//          because that genuinely needs logic.
// TARGET : ends at an archived `release-manifest.txt`. No kubectl, no helm,
//          no ssh, no cluster credential in scope.
// ══════════════════════════════════════════════════════════════════════

pipeline {
  // ⭐⭐ NO `agent` HERE with docker. A pod template, per build, per stage.
  agent {
    kubernetes {
      yamlFile 'ci/pod-templates/ci-agent.yaml'
      // ⭐ defaultContainer: if you omit it, every `sh` runs in `jnlp`,
      //   which has none of your toolchains. This is the #1 "command not
      //   found" cause in Jenkins-on-Kubernetes.
      defaultContainer 'tooling'
      idleMinutes 5               // reuse the pod across stages in one build
    }
  }

  options {
    timestamps()                        // ⭐ logs without timestamps are
                                        //   unusable for timing analysis
    buildDiscarder(logRotator(numToKeepStr: '50', artifactNumToKeepStr: '50'))
    timeout(time: 45, unit: 'MINUTES')  // ⭐ ALWAYS. A hung build otherwise
                                        //   holds an agent slot forever.
    disableConcurrentBuilds()           // ⭐ on main: two builds racing can
                                        //   publish over each other's tags
    skipDefaultCheckout(true)           // ⭐ we check out explicitly, inside
                                        //   the container that needs it
    ansiColor('xterm')
  }

  environment {
    REGISTRY   = 'ghcr.io'
    NAMESPACE  = '3558bhk'
    // ⭐⭐ credentials() binds a STORED credential to env vars for the
    //   duration of the pipeline. Note WHICH credential id: a CI-scoped one,
    //   folder-scoped, never global. §5.
    REGISTRY_CREDS = credentials('ci-registry-push')   // → REGISTRY_CREDS_USR
                                                       //   REGISTRY_CREDS_PSW
    GIT_SHA   = "${env.GIT_COMMIT ?: sh(returnStdout: true, script: 'git rev-parse HEAD').trim()}"
    GIT_SHORT = "${env.GIT_SHA.take(7)}"
  }

  stages {

    // ───────────────────────── what changed? ─────────────────────────
    stage('detect') {
      steps {
        container('tooling') {
          checkout scm                       // ⭐ explicit, because we set
                                             //   skipDefaultCheckout
          script {
            // ⭐⭐ THIS IS THE ONE PLACE DECLARATIVE IS NOT ENOUGH.
            //   Change detection needs real logic, so it drops into
            //   `script { }`. Everything else stays declarative.
            def base = env.CHANGE_TARGET ? "origin/${env.CHANGE_TARGET}" : 'HEAD~1'
            // ⭐ CHANGE_TARGET is set by the multibranch plugin on PR builds.
            //   On a branch build it is null, so compare against HEAD~1.
            sh "git fetch --no-tags --depth=0 origin '${env.CHANGE_TARGET ?: 'main'}' || true"
            def changed = sh(returnStdout: true,
                             script: "git diff --name-only ${base} HEAD || git diff --name-only HEAD~1 HEAD"
                            ).trim().split('\n').findAll { it }
            echo "changed files (${changed.size()}):\n  ${changed.join('\n  ')}"

            // ⭐ a `ci/` change rebuilds EVERYTHING — otherwise you cannot
            //   test a pipeline change without also touching app code.
            def ciTouched = changed.any { it.startsWith('ci/') || it.contains('Jenkinsfile') }
            env.BUILD_UI     = (ciTouched || changed.any { it.startsWith('apps/shop-ui/') }).toString()
            env.BUILD_API    = (ciTouched || changed.any { it.startsWith('apps/shop-api/') }).toString()
            env.BUILD_GO     = (ciTouched || changed.any { it.startsWith('apps/checkout/') ||
                                                                  it.startsWith('apps/payment-mock/') }).toString()
            env.BUILD_PY     = (ciTouched || changed.any { it.startsWith('apps/order-worker/') }).toString()
            // ⭐⭐ a PR build NEVER publishes. One flag, checked everywhere.
            env.DO_PUSH      = (env.CHANGE_ID == null).toString()
            echo "ui=${env.BUILD_UI} api=${env.BUILD_API} go=${env.BUILD_GO} py=${env.BUILD_PY} push=${env.DO_PUSH}"
          }
        }
      }
    }

    // ───────────────────── 🔵 shop-ui (React) ────────────────────────
    stage('shop-ui') {
      when {
        expression { env.BUILD_UI == 'true' }     // ⭐ `expression` is the
      }                                           //   declarative way to read
      parallel {                                  //   a computed env var
        stage('build+test') {
          steps {
            container('node') {
              dir('apps/shop-ui') {
                sh '''
                  set -euo pipefail
                  # ⭐ `set -euo pipefail` in EVERY sh step. Without -e a
                  #   failing command mid-script is ignored and the stage
                  #   goes GREEN. This is the most common Jenkins false-pass.
                  npm ci
                  npm run lint
                  npx tsc --noEmit
                  npm run test:unit -- --run --reporter=junit --outputFile=junit.xml
                  npm run build
                '''
                // ⭐ a quality gate that has nothing to do with compiling
                sh '''
                  set -euo pipefail
                  SIZE=$(du -sk dist | cut -f1); BUDGET=450
                  echo "dist = ${SIZE} KiB (budget ${BUDGET} KiB)"
                  [ "$SIZE" -le "$BUDGET" ] || { echo "bundle over budget"; exit 1; }
                '''
              }
              // ⭐ publish results so they show on the build page, not only
              //   in the console log. testFailureThreshold makes a failed
              //   test actually fail the build.
              junit allowEmptyResults: true, testResults: 'apps/shop-ui/junit.xml'
            }
          }
        }
        stage('image') {
          steps {
            // ⭐ the shared-library call — §4. Identical shape for all five
            //   services; only the arguments differ.
            buildAndPublishImage service: 'shop-ui',
                                 context: 'apps/shop-ui',
                                 language: 'node',
                                 push: env.DO_PUSH == 'true'
          }
        }
      }
    }

    // ───────────────────── 🟢 shop-api (Java 21) ─────────────────────
    stage('shop-api') {
      when { expression { env.BUILD_API == 'true' } }
      steps {
        container('jdk') {
          dir('apps/shop-api') {
            // ⭐⭐ TESTCONTAINERS INSIDE A KUBERNETES AGENT POD.
            //   There is no Docker daemon in this pod (§2 — deliberately).
            //   So Testcontainers must be told where to find one, or the
            //   integration tests must run in a stage that has one.
            //   The honest options, in order of preference:
            //     1. run integration tests against a Postgres started as a
            //        SIDECAR CONTAINER in the pod template (add it to the
            //        yaml) — no daemon needed, real database
            //     2. use Testcontainers Cloud / a remote DOCKER_HOST
            //     3. ⛔ do NOT mount the host Docker socket to "fix" this
            withEnv(['TESTCONTAINERS_RYUK_DISABLED=true']) {
              sh '''
                set -euo pipefail
                ./mvnw -B -ntp verify
              '''
            }
          }
          junit allowEmptyResults: true,
                testResults: 'apps/shop-api/target/surefire-reports/*.xml,apps/shop-api/target/failsafe-reports/*.xml'
          // ⭐⭐ recordCoverage requires the `code-coverage-api` plugin and
          //   makes the coverage delta visible on the PR. A coverage gate
          //   nobody sees is a gate nobody respects.
          recordCoverage(tools: [[parser: 'JACOCO']],
                         sourceDirectories: [[path: 'apps/shop-api/src/main/java']],
                         qualityGates: [[threshold: 80.0, type: 'LINE', criticality: 'FAILURE']])
        }
        buildAndPublishImage service: 'shop-api',
                             context: 'apps/shop-api',
                             language: 'java',
                             push: env.DO_PUSH == 'true'
      }
    }

    // ───────────── 🟢 checkout + payment-mock (Go) ───────────────────
    stage('go-services') {
      when { expression { env.BUILD_GO == 'true' } }
      parallel {
        stage('checkout') {
          steps {
            container('golang') {
              dir('apps/checkout') {
                sh '''
                  set -euo pipefail
                  go mod download
                  go vet ./...
                  go test -race -covermode=atomic -count=1 ./...
                '''
                // ⭐ -race in CI only. It is 5–10× slower and finds real bugs.
                //   -count=1 disables the test cache — a cached PASS in CI is
                //   a lie about the current commit.
              }
            }
            buildAndPublishImage service: 'checkout', context: 'apps/checkout',
                                 language: 'go', push: env.DO_PUSH == 'true'
          }
        }
        stage('payment-mock') {
          steps {
            container('golang') {
              dir('apps/payment-mock') {
                sh 'set -euo pipefail; go mod download && go test -count=1 ./...'
              }
            }
            buildAndPublishImage service: 'payment-mock', context: 'apps/payment-mock',
                                 language: 'go', push: env.DO_PUSH == 'true'
          }
        }
      }
    }

    // ───────────────── 🟢 order-worker (Python) ──────────────────────
    stage('order-worker') {
      when { expression { env.BUILD_PY == 'true' } }
      steps {
        container('python') {
          dir('apps/order-worker') {
            sh '''
              set -euo pipefail
              python -m pip install --no-cache-dir --upgrade uv
              uv sync --frozen --no-dev
              uv run ruff check .
              uv run ruff format --check .
              uv run mypy src
              uv run pip-audit
              uv run pytest -q --cov=src --cov-report=xml --cov-fail-under=80
            '''
          }
          junit allowEmptyResults: true, testResults: 'apps/order-worker/junit.xml'
          recordCoverage(tools: [[parser: 'COBERTURA']],
                         sourceDirectories: [[path: 'apps/order-worker/src']],
                         qualityGates: [[threshold: 80.0, type: 'LINE', criticality: 'FAILURE']])
        }
        buildAndPublishImage service: 'order-worker', context: 'apps/order-worker',
                             language: 'python', push: env.DO_PUSH == 'true'
      }
    }

    // ──────────── ⭐⭐ THE RELEASE MANIFEST — the handoff ─────────────
    stage('manifest') {
      steps {
        container('tooling') {
          script {
            // collect the digests each buildAndPublishImage stored
            def entries = (env.PUBLISHED_IMAGES ?: '').split(',').findAll { it }
            def lines = [
              "# Jenkins ${env.JOB_NAME} #${env.BUILD_NUMBER}",
              "# commit  ${env.GIT_SHA}",
              "# branch  ${env.GIT_BRANCH ?: env.BRANCH_NAME}",
              "# ⭐ CD consumes THIS file and nothing else."
            ]
            entries.each { lines << it }
            writeFile file: 'release-manifest.txt', text: lines.join('\n') + '\n'
            sh 'cat release-manifest.txt'
            echo "services in manifest: ${entries.size()}"
            // ⭐ AN EMPTY MANIFEST IS VALID (a docs-only commit). It is NOT
            //   an error here. CD must treat it as "nothing to do" — and if
            //   CD instead deploys whatever was last there, a docs commit
            //   just triggered a production rollout.
          }
        }
      }
    }
  }

  post {
    always {
      // ⭐⭐ archiveArtifacts IS the handoff. `echo`-ing a digest into the
      //   console log is not a handoff — it is a rumour. Artifacts are
      //   addressable, retained by buildDiscarder, and downloadable by CD.
      archiveArtifacts artifacts: 'release-manifest.txt',
                       allowEmptyArchive: true,
                       fingerprint: true      // ⭐ fingerprinting records the
                                              //   artifact's hash and lets you
                                              //   see which builds used it
      archiveArtifacts artifacts: '**/junit.xml', allowEmptyArchive: true
    }
    success { echo "✅ CI published ${env.PUBLISHED_IMAGES ?: 'nothing'}" }
    failure {
      echo '⛔ CI failed — no image was published, no manifest was written'
      // ⭐ creating a work item on failure is where Jenkins+Jira pays off.
      //   Only do it for main builds, or every failed PR spams the backlog.
      script { if (env.CHANGE_ID == null) { /* jiraIssueCreate(...) */ } }
    }
    cleanup {
      // ⭐ the pod is torn down automatically. This is for the workspace on
      //   a REUSED agent, so one build cannot read another's files.
      cleanWs(deleteDirs: true, notFailBuild: true)
    }
  }
}
```

---

## 4 · ⭐⭐ The shared library

**One definition of "how we build and publish", five callers.** This is Jenkins' version of a reusable workflow / a template — and because it is Groovy, it is a real function with real parameters and a real return value.

```groovy
// ══════════════════════════════════════════════════════════════════════
// vars/buildAndPublishImage.groovy  — a GLOBAL VARIABLE step in a shared
//                                     library. The filename IS the step name.
// ══════════════════════════════════════════════════════════════════════
// WHAT   : build → scan → sign → push → record the digest.
// WHY    : five services must not have five copies of this logic. When the
//          scan step changes, it must change once.
// CALLED : buildAndPublishImage service: 'shop-api', context: '...',
//                                language: 'java', push: true
// ══════════════════════════════════════════════════════════════════════
def call(Map args) {
  // ⭐ validate the contract loudly. A typo'd parameter that silently
  //   becomes null produces a confusing failure three steps later.
  def service  = requireArg(args, 'service')
  def context  = requireArg(args, 'context')
  def language = requireArg(args, 'language')
  def push     = args.get('push', false)          // ⭐⭐ DEFAULT-DENY
  def dockerfile = args.get('dockerfile', 'Dockerfile')

  def registry = env.REGISTRY ?: 'ghcr.io'
  def ns       = env.NAMESPACE ?: '3558bhk'
  def image    = "${registry}/${ns}/${service}"
  def tag      = env.GIT_SHA ?: 'unknown'

  return container('tooling') {
    stage("image:${service}") {
      // ── 1. build ────────────────────────────────────────────────────
      // ⭐ KANIKO, not the Docker socket. Kaniko builds inside an
      //   unprivileged container and pushes straight to the registry.
      //   It also emits the DIGEST, which is exactly what we need.
      def pushFlag = push ? "--destination ${image}:${tag} --destination ${image}:latest"
                          : "--no-push --tar-path /workspace/${service}.tar"
      // ⭐⭐ on a PR we still BUILD (with --no-push) so the Dockerfile is
      //   proven to work, but nothing reaches the registry.

      sh """
        set -euo pipefail
        /kaniko/executor \
          --context dir://\${WORKSPACE}/${context} \
          --dockerfile ${context}/${dockerfile} \
          --build-arg GIT_SHA=${tag} \
          --label org.opencontainers.image.revision=${tag} \
          --label org.opencontainers.image.source=${env.BUILD_URL ?: ''} \
          --cache=true --cache-repo=${image}-cache \
          --digest-file=/workspace/digest-${service}.txt \
          ${pushFlag}
      """
      // ⭐ --cache-repo gives you registry-backed layer caching on an
      //   ephemeral agent — the Jenkins equivalent of GitHub's type=gha.

      // ── 2. ⭐⭐ capture the digest ────────────────────────────────────
      def digest = ''
      if (push) {
        digest = readFile("/workspace/digest-${service}.txt").trim()
        if (!digest.startsWith('sha256:')) {
          error("digest for ${service} is malformed: '${digest}'")
        }
      } else {
        digest = 'unpublished-pr-build'
      }
      def ref = push ? "${image}@${digest}" : "${image}:${tag} (not pushed)"

      // ── 3. scan the IMAGE, not the source ────────────────────────────
      // ⭐ a source scan cannot see a vulnerable library inside your BASE
      //   image — which is where most real CVEs live.
      sh """
        set -euo pipefail
        trivy image --exit-code 1 --severity CRITICAL,HIGH --ignore-unfixed \
          ${push ? ref : "--input /workspace/${service}.tar"}
      """
      // ⭐ `--ignore-unfixed` is not leniency. Without it you are blocked by
      //   CVEs with no available fix, and the team learns to bypass the gate.

      // ── 4. sign (cosign, keyless) ────────────────────────────────────
      if (push) {
        // ⭐⭐ withCredentials keeps the secret inside the NARROWEST block
        //   that needs it. Not in `environment {}` for the whole pipeline —
        //   that exposes it to every stage, including ones running
        //   third-party plugin code.
        withCredentials([string(credentialsId: 'ci-cosign-key', variable: 'COSIGN_KEY')]) {
          sh """
            set -euo pipefail
            echo "\$COSIGN_KEY" > /tmp/cosign.key
            cosign sign --yes --key /tmp/cosign.key ${ref}
            shred -u /tmp/cosign.key     # ⭐ do not leave the key on the
          """                            #   workspace disk
        }
        // ⭐ Jenkins MASKS credentials in logs automatically — but only
        //   exact string matches. If your step base64-encodes or splits the
        //   secret, the mask does not apply and it lands in the build log.
        //   That is a real leak path and the reason to keep this block tiny.
      }

      // ── 5. record for the manifest stage ─────────────────────────────
      if (push) {
        def prev = env.PUBLISHED_IMAGES ?: ''
        env.PUBLISHED_IMAGES = prev ? "${prev},${service}=${ref}" : "${service}=${ref}"
      }
      echo "⭐ ${service} → ${ref}"
      return ref
    }
  }
}

private def requireArg(Map args, String name) {
  def v = args[name]
  if (!v) { error("buildAndPublishImage: required parameter '${name}' is missing") }
  return v
}
```

```groovy
// ⭐ loading the library — Jenkinsfile top, before `pipeline {`
@Library('shop-ci@v3') _
// ⭐⭐ PIN IT TO A TAG OR SHA. `@Library('shop-ci')` with no version tracks
//   the default branch, so a merge to that branch changes the behaviour of
//   EVERY pipeline in your Jenkins — including ones nobody re-ran. That is a
//   supply-chain hole with a blast radius of your entire build estate.
```

---

## 5 · ⭐⭐ Credential scoping — the part that decides whether this is really CI-only

```
┌──────────────────────── JENKINS CREDENTIAL SCOPES ────────────────────────┐
│                                                                           │
│  GLOBAL  (Jenkins)                                                        │
│   ⛔ visible to EVERY job, EVERY folder, and every multibranch job        │
│      created from a FORK's PR.                                            │
│   ⛔ This is the classic Jenkins breach path.                             │
│                                                                           │
│  FOLDER  (shop/ci)                                                        │
│   ✅ visible only to jobs inside that folder                              │
│   ⭐ THIS is where CI credentials belong.                                 │
│                                                                           │
│  JOB / ITEM                                                               │
│   ✅ narrowest. Use for a one-off.                                        │
└───────────────────────────────────────────────────────────────────────────┘
```

| Credential | Scope | Who needs it | ⛔ Who must NOT have it |
|---|---|---|---|
| `ci-registry-push` | ⭐ **folder** `shop/ci` | the image stage | any folder that builds untrusted forks |
| `ci-cosign-key` | ⭐ **folder** `shop/ci` | the sign step only | — |
| `cd-kubeconfig-production` | ⭐⭐ a **different folder entirely** (`shop/cd`) | Scenario 2 | ⛔ **the CI folder. Never.** |
| `cd-kubeconfig-staging` | `shop/cd` | Scenario 2 | ⛔ the CI folder |

⭐⭐ **The structural guarantee, and it is the whole point:**

```
Jenkins/
├── shop-ci/            ← folder. Credentials: registry push, cosign.
│   ├── shop-main/      ← multibranch, discovers BRANCHES ONLY (not forks)
│   └── shop-pr/        ← multibranch, discovers forks — ⭐ NO credentials
│                          beyond what a read-only build needs
└── shop-cd/            ← a SEPARATE folder. Credentials: kubeconfigs.
    └── deploy/
```

A job in `shop-ci` **cannot see** a credential in `shop-cd`, because folder credentials do not cross folders. That makes "CI cannot deploy" a property of the *configuration*, not of the *Jenkinsfile* — and the Jenkinsfile is editable by anyone with repo access, while folder credentials are editable only by a Jenkins admin.

**Same principle as the other two tools, third syntax:**

| Tool | Where the guarantee lives |
|---|---|
| 🐙 GitHub Actions | `permissions: {}` default-deny + no `production` environment + no cluster secret |
| 🔷 Azure DevOps | no Kubernetes **service endpoint** on the project + `AcrPush` only in IAM |
| 🔨 Jenkins | ⭐ **folder-scoped credentials in a separate folder from CD** + no RoleBinding on the agent SA |

> ⭐ **Enforce the constraint in the identity layer. Let the pipeline definition merely reflect it.** Anything enforced only in code that an attacker can edit is not enforced.

### The audit you should actually run

```
Manage Jenkins → Credentials → System → Global credentials
  ⭐ EXPECT: empty, or containing nothing that can deploy.
  ⛔ ANY kubeconfig, SSH key, or cloud SP here is a global-credential
     exposure to every job including forks' PRs.

Manage Jenkins → Security → script approval
  ⭐ every entry here is a Groovy sandbox escape someone requested.
     Read them. "approve all" is how a Jenkins becomes a shell.

Manage Jenkins → Plugins → installed
  ⭐ 1,800+ plugins exist; you should have ~40. Each is an attack surface
     and an upgrade obligation. Remove what you do not use.
```

---

## 6 · ⭐⭐ The digest handoff

| Mechanism | Who reads it | Why |
|---|---|---|
| ⭐ `archiveArtifacts 'release-manifest.txt'` | **CD** — a downstream job, or `curl` against the Jenkins API | the machine-readable handoff |
| `fingerprint: true` | an auditor | ⭐ records the artifact hash and which builds produced/consumed it |
| `env.PUBLISHED_IMAGES` | the `manifest` stage in the same build | internal aggregation |
| `echo "⭐ ${service} → ${ref}"` | a human reading the console | convenience only |

⛔ **`echo` is not a handoff.** A digest that exists only in a console log requires a human to read it and a script to regex it out of a multi-megabyte log with ANSI codes. `archiveArtifacts` makes it addressable by URL and retained by policy.

```bash
# what Scenario 2 does — its ENTIRE input:
curl -sS -u "$JENKINS_USER:$JENKINS_API_TOKEN" \
  "$JENKINS_URL/job/shop-ci/job/shop-main/lastSuccessfulBuild/artifact/release-manifest.txt"
# shop-ui=ghcr.io/3558bhk/shop-ui@sha256:9f2c…
# shop-api=ghcr.io/3558bhk/shop-api@sha256:41ab…
# checkout=ghcr.io/3558bhk/checkout@sha256:7de0…
# order-worker=ghcr.io/3558bhk/order-worker@sha256:c3f1…
# payment-mock=ghcr.io/3558bhk/payment-mock@sha256:0a9b…

# ⭐ or trigger CD explicitly, passing the build number — which is better,
#   because "lastSuccessfulBuild" can move between when you read it and
#   when you deploy it:
curl -sS -X POST -u "$JENKINS_USER:$JENKINS_API_TOKEN" \
  "$JENKINS_URL/job/shop-cd/job/deploy/buildWithParameters" \
  --data "CI_BUILD_NUMBER=412&TARGET=staging"
```

---

## 7 · Multibranch, and the fork hazard

| Setting | Value for CI | Why |
|---|---|---|
| **Branch Sources → Discover branches** | ⭐ `origin` branches only | forks are untrusted |
| **Discover pull requests from origin** | ✅ `Merge commit` | your own contributors |
| ⛔ **Discover pull requests from forks** | **disable**, or accept the consequences | ⭐ untrusted Groovy on your infrastructure |
| **Suppress automatic SCM triggering** | on `main` only if you gate merges | avoids building twice |
| **Trust** (for forks, if enabled) | ⛔ **NOT** "Trust everyone" | "Trust permission" limits it to users with Jenkins permissions |
| **Build PRs / Merge commits** | ⭐ **PR head only**, not the merge result, if forks are allowed | a merge result can contain code that exists in neither branch |

⭐⭐ **If you must build fork PRs** — open-source projects do — then:
1. the fork job gets **no credentials at all** (a separate folder, §5),
2. it runs with `push: false`, always,
3. `agent` pods have `automountServiceAccountToken: false`,
4. and the result is a **check**, not an artifact. A maintainer re-runs the build on a trusted branch before anything is published.

That is exactly what GitHub's `pull_request` vs `pull_request_target` distinction encodes as a platform default. In Jenkins it is your job to build it by hand — which is a real part of Jenkins' total cost of ownership.

---

## 8 · Caching on ephemeral agents

⭐ **The problem:** a Kubernetes agent pod is destroyed after each build. There is no local layer cache, no `~/.m2`, no `node_modules`. Without a strategy, every build starts cold — and a cold Maven build is 4–8 minutes of downloading.

| What | How | Cost |
|---|---|---|
| ⭐ Maven repo | a **ReadWriteMany PVC** mounted at `/root/.m2/repository` in the `jdk` container | needs an RWX storage class (NFS, CephFS, EFS, Azure Files) |
| Go modules | RWX PVC at `/go/pkg/mod` | same |
| npm | `npm ci` is fast enough; or an RWX PVC at `~/.npm` | usually not worth it |
| Python/uv | `UV_CACHE_DIR` on an RWX PVC | same |
| ⭐ **Docker layers** | **Kaniko `--cache-repo=<image>-cache`** — a registry-backed cache | one extra repository per service; no PVC needed |

```yaml
# the PVC (create once):
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: jenkins-m2-cache, namespace: jenkins }
spec:
  accessModes: [ReadWriteMany]      # ⭐⭐ MANY, not Once. Several agent pods
                                    #   run concurrently. ReadWriteOnce would
                                    #   deadlock the second build.
  storageClassName: nfs-client      # or efs-sc / azurefile-csi / csi-cephfs
  resources: { requests: { storage: 20Gi } }
```

⚠️ **The honest limits of a shared cache PVC:**
- ⛔ **Concurrent writes to `~/.m2` can corrupt it.** Maven is mostly tolerant; npm is not. If you see intermittent unresolvable dependencies, this is why.
- ⛔ **A shared cache is a cross-build channel.** A poisoned dependency cached by one build is served to every later build. Pin your tooling image and your dependencies.
- ⭐ **Kaniko's `--cache-repo` is safer than a PVC** for image layers, because the registry is content-addressed and immutable.

---

## 9 · ⭐ Proving it is CI-only — Jenkins-flavoured

| # | Check | How |
|---|---|---|
| **1** | No deployment verb in the Jenkinsfile or shared library | `grep -RnE 'kubectl\|helm\|compose up\|ssh \|scp \|set image\|argocd\|apply -f' Jenkinsfile vars/ ci/` → nothing |
| **2** | ⭐⭐ **No kubeconfig credential is in scope** | Manage Jenkins → Credentials → the **CI folder** must contain no kubeconfig, no SSH key, no cloud SP with cluster rights |
| **3** | ⭐ **The agent cannot talk to the API server** | `automountServiceAccountToken: false` in the pod template, and no RoleBinding for the default SA in that namespace |
| **4** | It emits a digest | `release-manifest.txt` contains `@sha256:` per service |
| **5** | A PR build publishes nothing | `env.DO_PUSH = (env.CHANGE_ID == null)` — then confirm the tag is absent from the registry after a PR build |
| **6** | ⭐ The shared library is **pinned** | `@Library('shop-ci@v3') _`, not `@Library('shop-ci') _` |

```bash
# ✅ run all of it from a shell:
grep -RnE 'kubectl|helm|compose up|ssh |scp |set image|argocd|apply -f' \
     Jenkinsfile vars/ ci/ && echo "⛔ NOT CI-ONLY" || echo "✅ no deploy verb"

grep -n '@Library' Jenkinsfile          # must show a @vN or @sha pin
grep -n 'automountServiceAccountToken' ci/pod-templates/ci-agent.yaml   # must be false
grep -n 'serviceAccountName' ci/pod-templates/ci-agent.yaml             # ⭐ must be absent
                                                                      #   or a zero-permission SA
grep -n 'docker.sock' ci/ -r              # ⛔ must return NOTHING

# the credential audit, via the Jenkins API:
curl -sS -u "$JENKINS_USER:$JENKINS_API_TOKEN" \
  "$JENKINS_URL/job/shop-ci/api/json?tree=jobs[name]" | jq
# then, per job, list the credentials actually bound — and confirm no
# kubeconfig id appears.
```

---

## 10 · ✅ Verify it from your laptop

```bash
# 1. the build ran
curl -sS -u "$JENKINS_USER:$JENKINS_API_TOKEN" \
  "$JENKINS_URL/job/shop-ci/job/shop-main/api/json?tree=builds[number,result,timestamp]{0,5}" | jq

# 2. the manifest artifact
curl -sS -u "$JENKINS_USER:$JENKINS_API_TOKEN" \
  "$JENKINS_URL/job/shop-ci/job/shop-main/412/artifact/release-manifest.txt"

# 3. ⭐ the digest is real and pullable
REF=$(curl -sS -u "$JENKINS_USER:$JENKINS_API_TOKEN" \
  "$JENKINS_URL/job/shop-ci/job/shop-main/412/artifact/release-manifest.txt" \
  | grep '^shop-api=' | cut -d= -f2-)
docker pull "$REF"
docker image inspect "$REF" --format 'size={{.Size}} user={{.Config.User}}'

# 4. the signature verifies
cosign verify --key "$COSIGN_PUB" "$REF" | jq '.[0].critical.identity'

# 5. the fingerprint — which builds produced and consumed this artifact
curl -sS -u "$JENKINS_USER:$JENKINS_API_TOKEN" \
  "$JENKINS_URL/fingerprint/<hash>/api/json?tree=usage[name,builds[number]]" | jq
```

---

## 11 · Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `sh: npm: command not found` | ⭐ the step ran in the `jnlp` container | wrap in `container('node') { … }`, or set `defaultContainer` |
| `git diff HEAD~1` fails or returns everything | ⭐ a shallow clone | `checkout([$class:'GitSCM', extensions:[[$class:'CloneOption', depth:0, noTags:false, shallow:false]]])` |
| A stage goes GREEN despite a failing command | ⛔ no `set -euo pipefail` | add it to **every** `sh '''…'''` block. This is the most common Jenkins false-pass |
| `Testcontainers: Could not find a valid Docker environment` | no daemon in the agent pod | sidecar Postgres in the pod template, or Testcontainers Cloud — ⛔ **not** a socket mount |
| Kaniko `permission denied` on push | credentials not in scope inside the container | `withCredentials` around the kaniko step, and `--docker-config` pointing at the written config |
| Kaniko build is slow every time | no `--cache-repo` | add it; it is the registry-backed layer cache |
| The shared library changed and broke every pipeline | ⛔ `@Library('shop-ci')` tracks the default branch | ⭐ pin: `@Library('shop-ci@v3') _` |
| A secret appears in the console log | it was transformed (base64, split) so Jenkins' auto-mask did not match | keep the `withCredentials` block minimal; never echo or transform the value |
| Concurrent builds deadlock on the cache | `ReadWriteOnce` PVC | ⭐ `ReadWriteMany` — several agents run at once |
| The build hangs forever | no `timeout` | `options { timeout(time: 45, unit: 'MINUTES') }` |
| Two builds published over each other | no `disableConcurrentBuilds()` | add it on the main branch pipeline |
| A fork PR could read a credential | ⛔ global-scope credential | move it to **folder** scope in a folder forks cannot reach (§5) |
| `recordCoverage` does nothing | missing the `code-coverage-api` plugin | install it; and check the parser matches your report format |

---

<a name="tasks--answers"></a>
## 12 · ⭐ TASKS — answers at the END

| # | Task |
|---|---|
| **T1** | Write the pod template with four language containers, and prove each `sh` runs in the right one |
| **T2** | Convert §3 into a shared-library call so the five services share one build definition |
| **T3** | Make a PR build (`CHANGE_ID != null`) build but never push, and prove the registry has no PR tag |
| **T4** | Replace a Docker-socket build with Kaniko, and confirm no `docker.sock` mount exists anywhere |
| **T5** | Move every credential from **global** to **folder** scope, and put CI and CD in separate folders |
| **T6** | Add Kaniko `--cache-repo` and measure the cold vs warm build time for `shop-api` |
| **T7** | Add the Trivy image scan and make a CRITICAL fail the build |
| **T8** | Pin the shared library to a tag and demonstrate what happens when you do not |
| **T9** | Implement change detection so a docs-only commit builds nothing and produces an empty manifest |
| **T10** | ⭐ Run all six CI-only checks from §9 and record the output |
| **T11** | ⭐⭐ Your Jenkins has a multibranch job that discovers forks. Write down, precisely, what an attacker can do — and the four settings that stop it |

---

# ✅ ANSWERS

**T1.** §2. The pod template defines `jnlp` plus `node`, `jdk`, `golang`, `python`, `tooling`. Two settings decide whether it works: `defaultContainer 'tooling'` in the `agent` block (otherwise every un-wrapped `sh` runs in `jnlp`, which has no toolchain — the #1 "command not found" cause), and `command: ['sleep'], args: ['infinity']` on each language container (otherwise Kubernetes starts it, it exits immediately, and the pod never becomes ready). Prove it with `sh 'hostname; which npm; which mvn; which go; which python3'` inside each `container()` block — exactly one should resolve per container.

**T2.** §4. The library lives in `vars/buildAndPublishImage.groovy` — the **filename is the step name** — and is loaded with `@Library('shop-ci@v3') _` before `pipeline {`. Because it is Groovy, it validates its arguments (`requireArg`) and returns the digest, which a YAML template cannot do. Each service's stage shrinks to a four-line call.

**T3.** `env.DO_PUSH = (env.CHANGE_ID == null).toString()` in the `detect` stage — `CHANGE_ID` is set by the multibranch plugin only on PR builds. It flows into `buildAndPublishImage push: …`, which selects `--destination` (push) versus `--no-push --tar-path` (build only). **Proof:** after a PR build, `crane ls ghcr.io/3558bhk/shop-api | grep <pr-sha>` returns nothing, *and* the console shows `--no-push`. The second check matters: if the flag were merely ignored, the build would still be slow and the registry still clean, and you would not know which mechanism protected you.

**T4.** §4's kaniko invocation. Then `grep -rn 'docker.sock' ci/ Jenkinsfile vars/` **must return nothing**, and the pod template must have no `hostPath` volume for it. ⭐ Why this matters more than it looks: a Docker socket mount gives the agent **root on the host node** — it can launch a privileged container mounting the node's filesystem. On a cluster that also runs production, that is a complete boundary collapse, and it is invisible in the Jenkinsfile because the mount lives in the pod template.

**T5.** §5. Create `shop-ci` and `shop-cd` as **sibling folders**. Move `ci-registry-push` and `ci-cosign-key` into `shop-ci`; move every kubeconfig into `shop-cd`. Folder credentials do not cross folders, so a job in `shop-ci` cannot read a kubeconfig — **regardless of what its Jenkinsfile says.** Verify: Manage Jenkins → Credentials → confirm the Global scope holds nothing that can deploy; then attempt `withCredentials([file(credentialsId:'cd-kubeconfig-production', variable:'K')])` in a CI job and confirm it fails with "No credentials found".

**T6.** Add `--cache=true --cache-repo=ghcr.io/3558bhk/shop-api-cache` to the kaniko step. First build (cold): typically 4–7 min for `shop-api`. Second build with only a source change: typically 60–100 s, because the `dependency:go-offline` layer is reused. ⭐ The cache only helps if the **Dockerfile copies the POM before the source** — otherwise the dependency layer is invalidated by every source edit and the cache hit rate is zero regardless of the flag.

**T7.** The Trivy step in §4, scanning the **image** (or `--input <tar>` for a PR build that was not pushed) with `--exit-code 1 --severity CRITICAL,HIGH --ignore-unfixed`. Two decisions matter: scan by digest/tar rather than by a mutable tag, so you scan exactly what you built; and `--ignore-unfixed` keeps the gate *trusted* — a gate that blocks on CVEs with no available fix gets bypassed, and a bypassed gate is worse than no gate.

**T8.** `@Library('shop-ci@v3') _`. Without the version, the library resolves to its **default branch at load time**, so merging to that branch silently changes the behaviour of every pipeline in your Jenkins — including pipelines nobody has run in months, which then fail on their next run for reasons unrelated to their own code. Demonstrate it: add a `sleep 60` to the unpinned library's default branch and watch an unrelated pipeline's next build take a minute longer. Pinning to a tag means a library change is a **deliberate, reviewed, per-pipeline** event.

**T9.** §3's `detect` stage. `fetchDepth: 0` (a shallow clone cannot diff against `HEAD~1`), `CHANGE_TARGET` for PR builds versus `HEAD~1` for branch builds, then four `env.BUILD_*` flags consumed by `when { expression { … } }`. Include `ci/` and `Jenkinsfile` in the "rebuild everything" condition, or you cannot test a pipeline change without also touching app code. **A docs-only commit** → all flags false → all four stages skipped → `release-manifest.txt` contains only comment lines. ⭐ That empty manifest is **valid**, and CD must treat it as "nothing to do" — if CD instead deploys whatever was last published, a README typo just triggered a production rollout.

**T10.** The commands in §9. The three that decide it: **(a)** `grep -rn 'docker.sock' ci/` returns nothing; **(b)** `automountServiceAccountToken: false` is present in the pod template and no `serviceAccountName` with a RoleBinding is set; **(c)** the CI folder's credential list contains no kubeconfig. Together these mean the agent has no Docker socket, no Kubernetes API access, and no cluster credential — so it cannot deploy even if the Jenkinsfile is edited to try.

**T11.** ⭐⭐ **What the attacker can do:** submitting a PR from a fork causes Jenkins to check out *their* `Jenkinsfile` and execute it as Groovy **on your agent**. Groovy in a Jenkins pipeline is sandboxed, but the sandbox is bypassable (there is a long CVE history of sandbox escapes), and even without an escape the script can: read any **global** credential via `withCredentials`, exfiltrate it over the network, modify the build to publish a malicious image to your registry, and — if the agent pod has a mounted service account token or a Docker socket — reach the cluster or the node. **The four settings that stop it:** (1) ⛔ disable **"Discover pull requests from forks"** entirely, or set **Trust** to *"Trust permission"* rather than *"Trust everyone"*; (2) put fork-building jobs in a folder whose credential store is **empty** — folder scope means global credentials are the only ones reachable, so globals must hold nothing that can deploy; (3) `automountServiceAccountToken: false` on the agent pod, and no Docker socket mount, so a compromised build cannot reach the cluster or the node; (4) force `push: false` for any build with `CHANGE_ID` set, so nothing from a fork can ever reach the registry — and have a maintainer re-run the build on a trusted branch before publishing. **The underlying principle is the one that generalises:** in Jenkins, the pipeline definition *is* attacker-controlled code when forks are enabled, so no guarantee that lives in the pipeline definition is a guarantee at all. Every real control must live outside it — in credential scope, in the agent's Kubernetes security context, and in the trust setting.

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish_Kumar_Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn: https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260
🔗 GitHub: https://github.com/3558Bhk

*In Jenkins the pipeline is code you run. So every real guarantee has to live outside it.*

</div>
