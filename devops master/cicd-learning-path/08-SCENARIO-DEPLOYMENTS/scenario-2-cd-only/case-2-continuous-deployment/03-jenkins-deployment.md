# 🔨 CASE 2 · CONTINUOUS DEPLOYMENT WITH JENKINS
### Upstream triggers, `waitUntil` smoke loops, a promotion-decision **function** instead of an approver, and a circuit breaker that stops the loop.

> **Scenario:** CI ran ([Scenario 1 · Jenkins](../../scenario-1-ci-only/03-jenkins-ci.md)) and pushed `ghcr.io/3558bhk/<svc>@sha256:…` with the digest written to a known location. **This pipeline never builds, never asks, and can undo itself.**
>
> **Tool version anchors:** Jenkins LTS **2.568.3** (Java 21 minimum) · Pipeline: Declarative · **Lockable Resources** · **Milestone** · Kubernetes plugin pod agents · `kubectl` v1.34.0 · Argo Rollouts v1.8 · `cosign` v2.4.

---

## 📇 Contents

| § | What |
|---|---|
| [1](#1---what-changes-from-case-1) | ⭐ What changes from Case 1 — the `input` becomes a function |
| [2](#2--the-trigger-upstream-builds-and-webhooks) | The trigger: upstream builds, webhooks, and the four ways to get it wrong |
| [3](#3---the-decision-function) | ⭐⭐ The decision function — how you encode a human's judgement in Groovy |
| [4](#4---the-cd-jenkinsfile--checkout-go-full-file) | ⭐ The CD Jenkinsfile — `checkout` (Go), full file |
| [5](#5---waituntil--the-right-way-to-poll) | ⭐ `waitUntil` — the right way to poll, and why `sleep` loops are wrong |
| [6](#6--the-canary-stage) | The canary stage — Argo Rollouts from Groovy |
| [7](#7---automatic-rollback-and-the-circuit-breaker) | ⭐⭐ Automatic rollback and the circuit breaker |
| [8](#8--the-freeze-calendar) | The freeze calendar — in Groovy |
| [9](#9---executors--the-case-2-specific-capacity-problem) | ⭐ Executors — the Case 2-specific capacity problem |
| [10](#10--per-app-shape) | Per app shape |
| [11](#11--️-run-it-and-prove-it--the-case-2-acceptance-checks) | ▶️ Run it and prove it — the Case 2 acceptance checks |
| [12](#12--troubleshooting) | Troubleshooting |
| [13](#13---tasks--answers-at-the-end) | Tasks and answers — **answers at the END** |

---

## 1 · ⭐ What changes from Case 1

Compare with [`../case-1-continuous-delivery/03-jenkins-delivery.md`](../case-1-continuous-delivery/03-jenkins-delivery.md).

| # | Case 1 (Delivery) | Case 2 (Deployment) |
|---|---|---|
| 1 | Manual build / `workflow_dispatch` equivalent | ⭐ **upstream trigger** from the CI job |
| 2 | `input(submitter: 'platform-leads', submitterPermissionCheck: true)` | ⛔ **no `input` anywhere** — a `shouldPromote()` function decides |
| 3 | Staging verification publishes an HTML **report** | ⭐ Staging verification **fails the build** |
| 4 | No canary | ⭐ canary stage with `argo rollouts` + `waitUntil` analysis |
| 5 | Rollback is a **separate job** a human runs | ⭐⭐ Rollback is a `post { failure { … } }` block, automatic |
| 6 | Nothing stops the next release | ⭐⭐ A halt flag checked in stage 0 |
| 7 | `timeout(time: 72, unit: 'HOURS')` around `input` | ⭐ a much shorter overall timeout — nothing waits for a human |

```groovy
// ⭐⭐ THE ENTIRE DIFFERENCE, IN TWO LINES
// Case 1:  def decision = input(message: 'Approve?', submitter: 'platform-leads')
// Case 2:  def decision = shouldPromote(digest: env.IMAGE_REF)     // a FUNCTION
//          if (!decision.approve) { error("⛔ ${decision.reason}") }
```

**What the function has to know** — i.e. what the human knew:

| The human's judgement | The function's input |
|---|---|
| "does it work?" | smoke-test results from dev and staging |
| "are the metrics normal?" | ⭐ canary vs stable error rate and p99, baseline-aware |
| "is anyone else shipping?" | `lock()` |
| "is now a good time?" | the freeze calendar (§8) |
| "can we get back?" | ⭐ a recorded previous digest + a tested rollback path |
| "did this just fail?" | ⭐⭐ the halt flag (§7.2) |

---

## 2 · The trigger: upstream builds and webhooks

### 2.1 Four options

| Option | Mechanism | ⭐ Verdict |
|---|---|---|
| **`build job:` from CI** | the CI job's `post { success { build job: 'cd-checkout', parameters: [...] } }` | ✅ **the clearest.** Explicit, parameterised, visible in both logs |
| **`upstream()` trigger** | `triggers { upstream(upstreamProjects: 'ci-checkout', threshold: hudson.model.Result.SUCCESS) }` | ✅ good, but ⛔ **cannot pass parameters** — you must re-resolve the digest |
| **Generic Webhook Trigger** | CI POSTs to Jenkins with a token | ✅ best for cross-system (GitHub CI → Jenkins CD) |
| ⛔ **Polling SCM** | `pollSCM('H/2 * * * *')` | the wrong tool. Latency plus load |

### 2.2 ⭐ The recommended one — explicit `build job:` with the digest as a parameter

```groovy
// ── in the CI JENKINSFILE (Scenario 1), post-publish ─────────────────
post {
  success {
    script {
      if (env.BRANCH_NAME == 'main') {
        // ⭐⭐ PASS THE DIGEST EXPLICITLY. This is the digest contract:
        //   the exact artifact CI built is named, not re-discovered.
        build job: '../shop-cd/cd-checkout',
              parameters: [
                string(name: 'IMAGE',  value: env.IMAGE_REF),
                string(name: 'GIT_SHA', value: env.GIT_COMMIT),
                string(name: 'CI_BUILD', value: env.BUILD_URL)
              ],
              wait: false,               // ⭐ do not hold a CI executor
              propagate: false
      }
    }
  }
}
```

| Detail | ⭐ Why |
|---|---|
| `wait: false` | ⛔ `wait: true` holds a **CI executor** for the entire CD run, including a 10-minute canary soak |
| `propagate: false` | a CD failure should not mark the CI build failed — they are different concerns |
| ⭐ the digest is passed as a **parameter** | no "find the latest" race, no re-resolution, no ambiguity |
| `CI_BUILD` is passed too | the audit record links CD back to the CI run that produced the artifact |

### 2.3 The four ways to get it wrong

| Mistake | Consequence |
|---|---|
| ⛔ `triggers { upstream(...) }` **and** expecting parameters | upstream triggers pass **nothing** — `params.IMAGE` is blank and you fall back to "latest", reintroducing the race |
| ⛔ `wait: true` | CI executors are consumed by CD soaks |
| ⛔ Triggering on **any** branch | feature branches promote to production |
| ⛔ Triggering when CI **published nothing** (a docs-only change) | a CD run with no artifact. ⭐ Guard it: `if (env.IMAGE_REF)` |

---

## 3 · ⭐⭐ The decision function

**This is the heart of Case 2 in Jenkins.** Everything else is plumbing.

```groovy
// ═══════════════════════════════════════════════════════════════════════
//  vars/shouldPromote.groovy  — shared library
//  WHAT : the encoded judgement of a release approver.
//  WHY  : in Case 1 a HUMAN answered "should this go to production?".
//         In Case 2 this function answers it. Every rule the human applied
//         must appear here, or the automation is not a replacement — it is
//         an omission.
// ═══════════════════════════════════════════════════════════════════════
def call(Map ctx) {
  // ctx = [digest:, service:, env:, smoke:, canary:, baseline:, halted:, frozen:]

  def reasons = []          // ⭐ collect ALL reasons, do not short-circuit.
                            //   "why was this blocked?" needs a full answer.

  // ── R1 · IS CD HALTED?  (the circuit breaker, §7.2) ────────────────
  if (ctx.halted) {
    reasons << "🛑 CD is HALTED for ${ctx.service} (a previous promotion failed)"
  }

  // ── R2 · IS IT FROZEN?  (§8) ───────────────────────────────────────
  if (ctx.frozen) {
    reasons << "🧊 a freeze window is in effect: ${ctx.frozen}"
  }

  // ── R3 · IS IT EVEN A DIGEST? ──────────────────────────────────────
  if (!(ctx.digest ==~ /@[a-z0-9]+:[0-9a-f]{64}$/)) {
    reasons << "⛔ '${ctx.digest}' is not a digest reference"
  }

  // ── R4 · DID THE SMOKE TESTS PASS? ─────────────────────────────────
  if (!ctx.smoke?.passed) {
    reasons << "⛔ smoke tests failed: ${ctx.smoke?.detail}"
  }

  // ── R5 · ⭐ IS THERE ENOUGH SIGNAL TO DECIDE? ──────────────────────
  if (ctx.canary?.requests < (ctx.canary?.minRequests ?: 200)) {
    // ⭐⭐ THE POLICY DECISION. Fail CLOSED for a service that can be
    //   canaried; the alternative means low-traffic services are promoted
    //   without ever being analysed — Case 2 in name only.
    reasons << "⚠️  INCONCLUSIVE: only ${ctx.canary?.requests} requests in the window " +
               "(need ${ctx.canary?.minRequests ?: 200}) — failing closed"
  }

  // ── R6 · ⭐ ARE THE METRICS WORSE THAN THE BASELINE? ───────────────
  if (ctx.canary) {
    def errDelta = ctx.canary.errRate - ctx.baseline.errRate
    def p99Ratio = ctx.canary.p99 / (ctx.baseline.p99 ?: 0.001)
    if (errDelta > 0.005) reasons << "⛔ error-rate delta ${errDelta} > 0.005"
    if (p99Ratio  > 1.5)  reasons << "⛔ p99 ratio ${p99Ratio} > 1.5"
    // ⭐ RATIOS, not absolutes — see §3.1
  }

  // ── R7 · DID A MIGRATION RUN THAT IS NOT BACKWARD-COMPATIBLE? ──────
  if (ctx.migration && !ctx.migration.backwardCompatible) {
    reasons << "⛔ migration '${ctx.migration.id}' is not backward-compatible — " +
               "rollback would be impossible. This release cannot be auto-promoted."
  }

  // ── R8 · ⭐ IS ANYONE ELSE MID-RELEASE?  (handled by lock(), but
  //         record it so the reason is visible) ────────────────────────
  if (ctx.concurrentRelease) reasons << "⚠️  another release is in flight"

  // ── THE VERDICT ────────────────────────────────────────────────────
  def approve = reasons.isEmpty()
  def verdict = [approve: approve, reasons: reasons,
                 summary: approve ? "✅ PROMOTE ${ctx.digest}"
                                  : "⛔ DO NOT PROMOTE — ${reasons.size()} reason(s)"]

  // ⭐⭐ WRITE THE DECISION DOWN, EVERY TIME. In Case 1 the approval record
  //   was the artifact of the gate. In Case 2 THIS is that artifact, and it
  //   is the only thing that lets you answer "why did the pipeline ship this?"
  writeDecision(verdict, ctx)
  return verdict
}

def writeDecision(Map verdict, Map ctx) {
  def rec = [
    timestamp  : new Date().format("yyyy-MM-dd'T'HH:mm:ss'Z'", TimeZone.getTimeZone('UTC')),
    service    : ctx.service,
    environment: ctx.env,
    digest     : ctx.digest,
    approve    : verdict.approve,
    reasons    : verdict.reasons,
    metrics    : [canary: ctx.canary, baseline: ctx.baseline, smoke: ctx.smoke],
    triggeredBy: ctx.ciBuild ?: env.BUILD_URL
  ]
  writeFile(file: 'decision.json', text: groovy.json.JsonOutput.prettyPrint(
              groovy.json.JsonOutput.toJson(rec)))
  // ⭐ append to the SAME audit file Case 1 used — a machine decision and a
  //   human decision are the same KIND of record and belong in one place
  sh 'cat decision.json >> /var/jenkins/audit/cd-decisions.jsonl 2>/dev/null || true'
  archiveArtifacts artifacts: 'decision.json', allowEmptyArchive: true
}
```

### 3.1 ⭐ Why ratios, not absolutes

```
⛔ ABSOLUTE:  if (canary.errRate > 0.01) reject
   Mon 09:00  traffic ×8  → 1% of 8× traffic = 8× the errors   → rejects good code
   Tue 03:00  traffic ÷20 → a full outage of one endpoint = 0.2% → accepts bad code

✅ DELTA vs the STABLE COHORT:  canary.errRate - stable.errRate > 0.005
   ⭐ same hour, same day, same traffic mix, same dependencies.
      The ONLY difference is the code. This is the strongest signal available.

✅ RATIO for latency:  canary.p99 / stable.p99 > 1.5
   ⭐ ratios survive load changes; absolutes do not.
```

---

## 4 · ⭐ The CD Jenkinsfile — `checkout` (Go), full file

`jenkins/cd-checkout.Jenkinsfile`

```groovy
// ═══════════════════════════════════════════════════════════════════════
//  WHAT : CD ONLY, Case 2 — CONTINUOUS DEPLOYMENT for `checkout` (Go).
//         upstream CI → dev → staging → ⭐ canary → production.
//         NO `input` ANYWHERE. shouldPromote() decides. Auto-rollback.
//  WHY  : stateless Go, /readyz, enough traffic → all five prerequisites hold.
//  TARGET: kind `cicd` → namespaces shop-{dev,staging,production}.
// ═══════════════════════════════════════════════════════════════════════
pipeline {
  agent {
    kubernetes {
      yaml '''
apiVersion: v1
kind: Pod
metadata:
  labels: { jenkins/cd: "true" }        # ⭐ scheduled onto the CD node pool (§9)
spec:
  serviceAccountName: jenkins-agent
  terminationGracePeriodSeconds: 30
  containers:
  - name: kubectl
    image: bitnami/kubectl:1.34.0       # ⭐ pinned
    command: ["sleep"]
    args: ["infinity"]
    resources: { requests: { cpu: 100m, memory: 256Mi }, limits: { cpu: 500m, memory: 512Mi } }
  - name: argo                          # ⭐ the canary driver
    image: quay.io/argoproj/argo-rollouts:v1.8.2
    command: ["sleep"]
    args: ["infinity"]
  # ⛔ NO docker, NO go, NO build toolchain. This pipeline CANNOT build.
  nodeSelector: { pool: cd }            # ⭐ CD agents live on their own nodes
'''
    }
  }

  options {
    timestamps()
    disableConcurrentBuilds()             // ⭐ one CD run per job
    buildDiscarder(logRotator(numToKeepStr: '200'))   // ⭐ Case 2 runs often
    timeout(time: 90, unit: 'MINUTES')    // ⭐⭐ SHORT. Nothing waits for a human.
    skipDefaultCheckout()
  }

  parameters {
    string(name: 'IMAGE',    defaultValue: '', description: '⭐ digest ref from CI')
    string(name: 'GIT_SHA',  defaultValue: '', description: 'originating commit')
    string(name: 'CI_BUILD', defaultValue: '', description: '⭐ link back to the CI run')
    booleanParam(name: 'FORCE', defaultValue: false,
                 description: '⛔ ignore the freeze (NOT the halt flag, NOT the metrics)')
  }

  environment {
    SERVICE   = 'checkout'
    NS        = 'shop-production'
    PORT      = '9091'
    PROBE     = '/readyz'
    CANARY_PCT    = '10'
    CANARY_WINDOW = '10m'
    MIN_REQUESTS  = '200'
  }

  stages {

    // ═════════════════════════════════════════════════════════════════
    //  STAGE 0 · THE PRE-FLIGHT GATES
    // ═════════════════════════════════════════════════════════════════
    stage('0 · Pre-flight') {
      steps {
        script {
          // ── 0a · the digest ────────────────────────────────────────
          def raw = (params.IMAGE ?: '').trim()
          if (!raw) {
            raw = readFile('/var/jenkins/digests/checkout-main.txt').trim()
          }
          if (!(raw ==~ /^[a-z0-9._\/-]+@sha256:[0-9a-f]{64}$/)) {
            error("⛔ '${raw}' is not a digest. CD refuses tags.")
          }
          env.IMAGE_REF = raw
          env.DIGEST    = raw.split('@')[1]
          currentBuild.displayName = "#${BUILD_NUMBER} ${env.DIGEST.take(15)}…"
          currentBuild.description = "CD · ${params.CI_BUILD ?: 'manual'}"

          // ── 0b · ⭐⭐ THE CIRCUIT BREAKER ──────────────────────────
          env.HALTED = fileExists('/var/jenkins/cd-state/checkout.HALTED') ? 'true' : 'false'
          if (env.HALTED == 'true') {
            // ⭐⭐ exit SUCCESS. A halt is a policy outcome, not a failure.
            //   A stream of red builds trains everyone to ignore red builds.
            currentBuild.result = 'NOT_BUILT'
            slackSend(channel: '#releases', color: '#808080',
              message: "🛑 CD skipped — ${SERVICE} is HALTED. Clear /var/jenkins/cd-state/checkout.HALTED to resume.")
            return                                     // ⭐ leaves the stages
          }

          // ── 0c · ⭐ THE FREEZE CALENDAR (§8) ───────────────────────
          env.FROZEN = inFreezeWindow(new Date()) ? 'true' : 'false'
          if (env.FROZEN == 'true' && !params.FORCE) {
            currentBuild.result = 'NOT_BUILT'
            echo "🧊 freeze in effect — not promoting. (FORCE=true overrides the freeze, never the metrics.)"
            return
          }

          // ── 0d · G1 · PROVENANCE ───────────────────────────────────
          container('kubectl') {
            withCredentials([file(credentialsId: 'cosign-public-key', variable: 'COSIGN_KEY')]) {
              sh '''
                set -eu
                echo "$COSIGN_KEY" > /tmp/cosign.pub
                cosign verify --key /tmp/cosign.pub "$IMAGE_REF" >/dev/null \
                  || { echo "⛔ provenance verification failed"; exit 1; }
                echo "✅ G1 provenance OK"
              '''
            }
          }
        }
      }
    }

    // ═════════════════════════════════════════════════════════════════
    //  STAGE 1 · DEV — GATE, not report
    // ═════════════════════════════════════════════════════════════════
    stage('1 · dev') {
      steps {
        container('kubectl') { script { deployAndVerify('shop-dev') } }
      }
    }

    // ═════════════════════════════════════════════════════════════════
    //  STAGE 2 · STAGING — GATE, and it records the BASELINE
    // ═════════════════════════════════════════════════════════════════
    stage('2 · staging') {
      steps {
        container('kubectl') {
          script {
            deployAndVerify('shop-staging')
            // ── ⭐ the baseline the canary will be compared against ──
            def b = sh(returnStdout: true,
                       script: "./scripts/metrics.sh shop-staging 15m ${SERVICE} ${PORT}").trim()
            env.BASELINE = b
            echo "📊 baseline: ${b}"
          }
        }
      }
    }

    // ═════════════════════════════════════════════════════════════════
    //  STAGE 3 · ⭐ CANARY + ANALYSIS
    // ═════════════════════════════════════════════════════════════════
    stage('3 · canary') {
      steps {
        // ⭐⭐ THE LOCK replaces "is anyone else shipping?"
        lock(resource: 'shop-production-deploy', inversePrecedence: true) {
          milestone(ordinal: 100)
          container('argo') {
            script {
              // ── start the canary ───────────────────────────────────
              sh """
                set -eu
                kubectl argo rollouts set image ${SERVICE} ${SERVICE}="${env.IMAGE_REF}" -n ${NS}
                kubectl argo rollouts get rollout ${SERVICE} -n ${NS} --watch --timeout 180 || true
                kubectl argo rollouts get rollout ${SERVICE} -n ${NS} -o json \\
                  | jq '{phase:.status.phase, canary:.status.canary}'
              """
              // ── ⭐ SOAK, using waitUntil (§5) ──────────────────────
              def analysis = [:]
              waitUntil(initialRecurrencePeriod: 15000) {
                sleep(time: 1, unit: 'MINUTES')       // sample every minute
                def m = readJSON(text: sh(returnStdout: true,
                        script: "./scripts/canary-metrics.sh ${NS} ${SERVICE} 2m").trim())
                analysis = m
                // ⭐ return TRUE to stop waiting once we have enough signal
                return m.requests >= env.MIN_REQUESTS.toInteger()
              }
              // ── ⭐⭐ THE DECISION ─────────────────────────────────
              def baseline = readJSON(text: env.BASELINE)
              def verdict = shouldPromote(
                digest   : "@${env.DIGEST}",
                service  : env.SERVICE,
                env      : 'production',
                smoke    : [passed: true, detail: 'dev + staging green'],
                canary   : analysis + [minRequests: env.MIN_REQUESTS.toInteger()],
                baseline : baseline,
                halted   : env.HALTED == 'true',
                frozen   : env.FROZEN == 'true',
                ciBuild  : params.CI_BUILD
              )
              env.VERDICT = verdict.approve ? 'PASS' : 'FAIL'
              echo verdict.summary
              verdict.reasons.each { echo "   · ${it}" }

              if (!verdict.approve) {
                // ── ⛔ ABORT THE CANARY. This is the rollback. ───────
                sh "kubectl argo rollouts abort ${SERVICE} -n ${NS}"
                error("⛔ canary rejected: ${verdict.reasons.join('; ')}")
              }
              // ── promote to 100% ────────────────────────────────────
              sh """
                set -eu
                kubectl argo rollouts promote ${SERVICE} -n ${NS} --full=true
                kubectl argo rollouts get rollout ${SERVICE} -n ${NS} --watch --timeout 600
              """
            }
          }
          milestone(ordinal: 101)
        }
      }
    }

    // ═════════════════════════════════════════════════════════════════
    //  STAGE 4 · PRODUCTION — post-deploy watch
    // ═════════════════════════════════════════════════════════════════
    stage('4 · production verify') {
      steps {
        container('kubectl') {
          script {
            def fails = 0
            // ⭐ G5 · watch for 10 minutes. `waitUntil` with a max wait.
            timeout(time: 12, unit: 'MINUTES') {
              waitUntil(initialRecurrencePeriod: 60000) {
                def err = sh(returnStdout: true,
                  script: "./scripts/err-ratio.sh ${NS} ${SERVICE} 5m").trim().toDouble()
                def ok  = sh(returnStdout: true,
                  script: "./scripts/smoke.sh ${NS} ${SERVICE} ${PORT} ${PROBE} && echo y || echo n").trim()
                if (err > 0.01 || ok != 'y') { fails++; echo "⚠️  check failed (err=${err}, smoke=${ok}) — ${fails}/3" }
                else { fails = 0 }
                return fails >= 3                  // ⭐ TRUE = stop waiting
              }
            }
            if (fails >= 3) { error("⛔ 3 consecutive production check failures") }
            // ── ⭐⭐ READ THE IMAGE BACK FROM THE CLUSTER ────────────
            def now = sh(returnStdout: true, script:
              "kubectl -n ${NS} get rollout ${SERVICE} " +
              "-o jsonpath='{.spec.template.spec.containers[?(@.name==\"${SERVICE}\")].image}'").trim()
            if (now != env.IMAGE_REF) { error("⛔ cluster runs '${now}', wanted '${env.IMAGE_REF}'") }
            echo "✅ production confirmed running ${now}"
          }
        }
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  //  ⭐⭐ POST — ROLLBACK, HALT, NOTIFY, RECORD
  // ═══════════════════════════════════════════════════════════════════
  post {
    failure {
      container('argo') {
        script {
          // ── ROLLBACK ───────────────────────────────────────────────
          sh """
            set +e
            kubectl argo rollouts abort ${SERVICE} -n ${NS} 2>/dev/null
            kubectl argo rollouts undo  ${SERVICE} -n ${NS} 2>/dev/null \\
              || kubectl -n ${NS} rollout undo deploy/${SERVICE}
            kubectl -n ${NS} rollout status deploy/${SERVICE} --timeout=300s
          """
          // ── ⭐⭐ SET THE CIRCUIT BREAKER ───────────────────────────
          sh """
            mkdir -p /var/jenkins/cd-state
            echo "halted by build ${env.BUILD_URL} at \$(date -u +%FT%TZ)" \\
              > /var/jenkins/cd-state/${SERVICE}.HALTED
          """
          slackSend(channel: '#releases', color: 'danger', message: """🚨 *${SERVICE} CD auto-rolled back*
Digest : `${env.DIGEST}`
Verdict: ${env.VERDICT ?: 'unknown'}
🛑 further promotions HALTED — clear /var/jenkins/cd-state/${SERVICE}.HALTED to resume
CI     : ${params.CI_BUILD}
Build  : ${env.BUILD_URL}""")
          // ⭐ page ONCE. The halt flag is what makes it once.
          withCredentials([string(credentialsId: 'pagerduty-key', variable: 'PD')]) {
            sh '''curl -fsS -X POST https://events.pagerduty.com/v2/enqueue \
                  -H 'content-type: application/json' -d "{\\"routing_key\\":\\"$PD\\",
                  \\"event_action\\":\\"trigger\\",
                  \\"payload\\":{\\"summary\\":\\"''' + "${SERVICE} CD auto-rolled back — HALTED" + '''\\",
                                 \\"severity\\":\\"critical\\",\\"source\\":\\"jenkins\\",
                                 \\"custom_details\\":{\\"build\\":\\"''' + "${env.BUILD_URL}" + '''\\"}}}"'''
          }
        }
      }
    }
    success {
      script {
        slackSend(channel: '#releases', color: 'good',
          message: "🤖 *${SERVICE} → production* (automatic)\nDigest: `${env.DIGEST}`\nCanary: ${env.VERDICT}\nCI: ${params.CI_BUILD}\n${env.BUILD_URL}")
        // ⭐ the audit record: WHO decided = "shouldPromote()", and WHY
        sh "cat decision.json >> /var/jenkins/audit/cd-decisions.jsonl 2>/dev/null || true"
        sh "echo '${env.IMAGE_REF}' > /var/jenkins/digests/${SERVICE}-production.txt"
      }
    }
    cleanup {
      // ⭐ NEVER clear the halt flag here. Clearing your own circuit
      //   breaker defeats the entire purpose.
      echo "ℹ️ halt flags are cleared by a human or by the scheduled clear job."
    }
  }
}
```

### 4.1 `deployAndVerify` — the shared step

```groovy
// vars/deployAndVerify.groovy — ⭐ one implementation of "deploy", for every
//   service and every environment. In Case 2 a failed verify FAILS THE BUILD.
def call(String ns) {
  def svc = env.SERVICE, ref = env.IMAGE_REF
  def prev = sh(returnStdout: true, script:
    "kubectl -n ${ns} get deploy ${svc} -o jsonpath='{.spec.template.spec.containers[?(@.name==\"${svc}\")].image}'").trim()
  echo "📌 ${ns} previous: ${prev}"

  if (prev == ref) { echo "ℹ️ already running ${ref} — no-op"; return }   // ⭐ idempotent

  sh """
    set -eu
    kubectl -n ${ns} set image deploy/${svc} ${svc}=${ref}
    kubectl -n ${ns} rollout status deploy/${svc} --timeout=300s \\
      || { kubectl -n ${ns} set image deploy/${svc} ${svc}=${prev}; exit 1; }
  """
  // ⭐⭐ READ IT BACK — a deploy tool's exit code is not proof of what runs
  def now = sh(returnStdout: true, script:
    "kubectl -n ${ns} get deploy ${svc} -o jsonpath='{.spec.template.spec.containers[?(@.name==\"${svc}\")].image}'").trim()
  if (now != ref) { error("⛔ ${ns} runs '${now}', wanted '${ref}'") }

  // ⭐ G2 · smoke from INSIDE the cluster
  sh """
    set -eu
    kubectl -n ${ns} run smoke-\$RANDOM --rm -i --restart=Never \\
      --image=curlimages/curl:8.17.0 -- \\
      curl -fsS "http://${svc}.${ns}.svc.cluster.local:${env.PORT}${env.PROBE}"
  """
  echo "✅ ${ns} verified running ${now}"
}
```

---

## 5 · ⭐ `waitUntil` — the right way to poll

```groovy
// ⛔ WRONG — a hand-rolled sleep loop
def deadline = System.currentTimeMillis() + 600000
while (System.currentTimeMillis() < deadline) {
  if (check()) break
  sleep(time: 30, unit: 'SECONDS')
}
// problems: no backoff, no logging of WHY it is waiting, no way to see the
//   attempt count in the UI, and it silently exits the loop on timeout with
//   no distinction between "succeeded" and "gave up".

// ✅ RIGHT
waitUntil(initialRecurrencePeriod: 15000) {   // ⭐ ms — starts at 15s, backs off
  def m = collect()
  echo "attempt: ${m}"                        // ⭐ visible in the log
  return m.requests >= 200                    // ⭐ TRUE stops the wait
}
```

| Property | ⭐ Why |
|---|---|
| `initialRecurrencePeriod` | ⭐ the period **grows** on each false return, up to 15 s by default — automatic backoff |
| the closure returns **`true` to STOP** | ⛔ inverted from what most people expect. `true` = "the condition is met, stop waiting" |
| ⛔ `waitUntil` has **no built-in timeout** | wrap it in `timeout(time: …) { … }` or it waits forever |
| it logs each attempt | the UI shows the wait, which a `sleep` loop does not |

```groovy
// ⭐⭐ THE CORRECT COMBINATION — a bounded, backed-off wait
def fails = 0
timeout(time: 12, unit: 'MINUTES') {
  waitUntil(initialRecurrencePeriod: 60000) {
    def bad = check()
    if (bad) fails++ else fails = 0
    return fails >= 3        // ⭐ stop when the condition we are waiting FOR happens
  }
}
if (fails >= 3) { error("⛔ condition met — this is a FAILURE") }
// ⭐ NOTE THE INVERSION: `waitUntil` returns normally when the closure
//   returns true. If `true` means "three failures in a row", then a NORMAL
//   RETURN IS THE BAD CASE. This trips up almost everyone.
```

---

## 6 · The canary stage

| Concern | Jenkins answer |
|---|---|
| Traffic splitting | ⛔ Jenkins does not do it. **Argo Rollouts** does — Jenkins just drives it |
| Starting the canary | `kubectl argo rollouts set image <svc> <container>=<digest>` |
| Watching | `kubectl argo rollouts get rollout <svc> --watch --timeout 180` |
| Analysing | ⭐ your own `scripts/canary-metrics.sh` + `shouldPromote()` |
| Aborting | `kubectl argo rollouts abort <svc>` — ⭐ **seconds**, the stable pods never left |
| Promoting | `kubectl argo rollouts promote <svc> --full=true` |
| Undoing | `kubectl argo rollouts undo <svc>` |

⭐ **Alternative: let Argo Rollouts do the analysis itself** with an `AnalysisTemplate` and `--watch` on the Rollout's `status.phase` reaching `Healthy` or `Degraded`. That is the cleaner design and it is covered in [`04-docker-and-k8s-targets.md`](./04-docker-and-k8s-targets.md). **Jenkins-side analysis is better when:** you want the decision logic in Groovy where you can unit-test it, you need to combine signals from outside the cluster (a freeze calendar, a halt flag, a change record), or you are driving more than one cluster.

```groovy
// ⭐ letting Argo Rollouts own the analysis — the shorter version
sh """
  set -eu
  kubectl argo rollouts set image ${SERVICE} ${SERVICE}="${env.IMAGE_REF}" -n ${NS}
  # the Rollout spec has an `analysis:` block with an AnalysisTemplate.
  # Argo runs it, and the phase becomes Healthy or Degraded.
  kubectl argo rollouts get rollout ${SERVICE} -n ${NS} --watch --timeout 900
  PHASE=\$(kubectl argo rollouts get rollout ${SERVICE} -n ${NS} -o jsonpath='{.status.phase}')
  echo "phase=\$PHASE"
  [ "\$PHASE" = "Healthy" ] || { echo "⛔ \$PHASE"; exit 1; }
"""
// ⭐⭐ with an AnalysisTemplate, Argo Rollouts ABORTS ITSELF on a failed
//   analysis. Jenkins then only has to detect it — the rollback is already done.
```

---

## 7 · ⭐⭐ Automatic rollback and the circuit breaker

### 7.1 Rollback

| Placement | ⭐ Why |
|---|---|
| `post { failure { … } }` | ⭐ catches failures from **any** stage, including the canary |
| Inside the canary stage, on a bad verdict | ⭐ `argo rollouts abort` **before** `error()`, so traffic is restored even if the notification step then fails |
| ⛔ A separate rollback job triggered by CD | slower, needs its own agent, and can itself fail to trigger |

```
⭐ THE ROLLBACK LADDER — fastest first
   1. argo rollouts abort   ← SECONDS. During a canary the stable pods never
                               went away; abort just moves the traffic weight.
                               No scheduling, no pull, no start-up, no warm-up.
   2. argo rollouts undo    ← ~30 s
   3. set image to $PREV    ← ~60 s, and UNAMBIGUOUS (deployAndVerify records it)
   4. rollout undo          ← ⛔ ambiguous after two failures: "previous" is
                               then the FIRST bad revision, not the last good one
```

### 7.2 ⭐⭐ The circuit breaker

```
⛔ WITHOUT:  commit A → canary fails → rollback → PAGE 🔔
             commit B → canary fails → rollback → PAGE 🔔
             commit C → canary fails → rollback → PAGE 🔔
             you are paged every 20 minutes and nothing is fixed.

✅ WITH:     commit A → canary fails → rollback → PAGE 🔔 + touch HALTED
             commit B → stage 0 sees HALTED → NOT_BUILT, promotes nothing
             commit C → same
             ⭐ ONE page. The queue drains when a human clears the flag.
```

| Rule | Implementation |
|---|---|
| ⭐ The flag is a **file**, not a variable | `/var/jenkins/cd-state/<service>.HALTED` — survives restarts, is `ls`-able, and can be on a shared volume |
| ⭐ A halted run is **`NOT_BUILT`**, not `FAILURE` | a stream of red builds trains people to ignore red builds |
| ⭐⭐ **Never cleared by the job that set it** | the `post { cleanup }` block says so explicitly |
| Cleared by a human, or a scheduled job | a `clearCdHalt` job with a "no failures in 4h" condition |
| ⭐ **Per service** | one bad service must not freeze the estate |

```groovy
// jenkins/clearCdHalt.Jenkinsfile — scheduled, and CONDITIONAL
pipeline {
  agent none
  triggers { cron('H */4 * * *') }          // every 4 hours
  stages {
    stage('Clear stale halts') {
      steps {
        script {
          // ⭐⭐ only clear if there have been NO CD failures in 4 hours.
          //   Clearing unconditionally re-arms the loop that paged you.
          def recent = sh(returnStdout: true, script: '''
            find /var/jenkins/audit/cd-decisions.jsonl -mmin -240 2>/dev/null \\
              | wc -l''').trim()
          def failures = sh(returnStdout: true, script: '''
            awk -F'"approve":' 'NR>0 {print $2}' /var/jenkins/audit/cd-decisions.jsonl \\
              | grep -c false || true''').trim()
          if (failures == '0') {
            sh 'rm -f /var/jenkins/cd-state/*.HALTED && echo "✅ halts cleared"'
            slackSend(channel: '#releases', color: 'good', message: '✅ CD halts auto-cleared (no failures in 4h)')
          } else {
            echo "🛑 ${failures} recorded failures — halts REMAIN"
          }
        }
      }
    }
  }
}
```

---

## 8 · The freeze calendar

```groovy
// vars/inFreezeWindow.groovy — ⭐ reads a COMMITTED calendar, so changing it
//   is a reviewed PR rather than a Jenkins config nobody remembers.
def call(Date now = new Date()) {
  def cal = readYaml(file: 'freezes.yaml')     // from the repo checkout
  def iso = now.format("yyyy-MM-dd'T'HH:mm:ss'Z'", TimeZone.getTimeZone('UTC'))

  // absolute windows
  for (w in (cal.windows ?: [])) {
    if (iso > w.from && iso < w.to) return w.name
  }
  // weekend
  def dow = now.format('EEE', Locale.ENGLISH).toLowerCase()
  for (r in (cal.recurring ?: [])) {
    if (r.days && r.days.contains(dow)) return r.name
  }
  // daily quiet hours
  def hm  = now.format('HH:mm')
  for (r in (cal.recurring ?: [])) {
    if (r.daily_from && r.daily_to && hm >= r.daily_from && hm < r.daily_to) return r.name
  }
  return null        // ⭐ null = not frozen
}
```

| Rule | ⭐ Why |
|---|---|
| The calendar is in **git** | changing it is a reviewed PR with an author and a `reason:` |
| A frozen run is **`NOT_BUILT`**, not `FAILURE` | three weeks of red builds makes red meaningless |
| ⭐ `FORCE=true` overrides the **freeze only** | never the metrics, never the halt flag, never provenance |
| Weekend/quiet-hours rules are **recurring** | you do not want to edit YAML every Friday |

```
⭐ THE FORCE PARAMETER — WHAT IT MAY AND MAY NOT OVERRIDE

   ✅ MAY override  : the freeze calendar, business hours
   ⛔ MUST NOT      : the halt flag (a human set it deliberately)
   ⛔ MUST NOT      : the metric analysis (that IS the gate)
   ⛔ MUST NOT      : provenance verification (that IS the contract)

   WHY: FORCE exists so a hotfix can ship during a freeze. It must not
   become the way to ship something the pipeline correctly rejected.
```

---

## 9 · ⭐ Executors — the Case 2-specific capacity problem

**In Case 1, waiting for a human consumed an executor.** In Case 2 there is no human wait — but there are **soaks**, and Case 2 runs **far more often**.

| Case 2 pressure | Numbers |
|---|---|
| A 10-minute canary soak per release | the agent is occupied for the whole soak |
| Releases triggered by **every** main build | ⭐ 10–50× more runs than Case 1 |
| A `postRouteTraffic` watch of 10 more minutes | 20+ minutes of agent time per release |
| Multiple services in parallel | × N services |

**Four fixes, in order of value:**

| # | Fix | ⭐ Why |
|---|---|---|
| 1 | ⭐⭐ **Kubernetes pod agents on a dedicated `pool: cd` node group** | agents are created per build and destroyed after — capacity scales with releases instead of being fixed |
| 2 | ⭐ **Set the controller's executor count to 0** | no build ever runs on the controller, so a CD surge cannot starve the UI or the queue |
| 3 | ⭐ **`throttle-concurrents`** with a per-job and a global cap | bounds how many soaks run at once, so a burst does not exhaust the node pool |
| 4 | **Shorten the soak where the data allows** | a 5-minute soak with 400 requests beats a 10-minute soak with 200 |

```groovy
// ⭐ the pod template already carries the node selector (§4)
//    nodeSelector: { pool: cd }
// and the CONTROLLER has 0 executors:
//    Manage Jenkins → Nodes → built-in → # of executors = 0
```

⭐ **The lesson worth stating:** *a paused or soaking pipeline is not free.* Any wait — Jenkins `input`, a canary soak, a `postRouteTraffic` watch, a held GitHub runner — occupies a worker for its full duration. Case 2 replaces a 72-hour human wait with a 20-minute machine soak, which is better, but it replaces **5 runs a week** with **50**. Capacity planning is part of adopting Case 2, not an afterthought.

---

## 10 · Per app shape

| Shape | What changes |
|---|---|
| 🔵 **FE only** (`shop-ui`) | ⭐ **the best Case 2 candidate.** No migration, `PROBE='/'`, `argo rollouts` may be overkill — a plain rolling update with a fast rollback is fine. Add the `config.js` `API_URL` assertion to `deployAndVerify` |
| 🟢 **BE stateless** (`checkout`, `payment-mock`) | ⭐ this file. `payment-mock` is the **pilot** — lowest consequence |
| 🟢 **BE stateful** (`shop-api`) | 🔒 **Case 1.** Rule R7 in `shouldPromote` rejects any release carrying a non-backward-compatible migration |
| 🟢 **BE worker** (`order-worker`) | 🔒 Case 1. ⛔ Cannot canary by traffic weight — a queue consumer either consumes or does not. `shouldPromote` would always return `INCONCLUSIVE` |
| 🟡 **FE + BE** (P10) | ⭐ **split into two jobs**, each with its own halt flag; the UI job triggers `upstream` on the API job |
| 🟠 **Polyglot** (P11/P12) | one CD job per service + a release-train job that halts if **any** member is halted |

```groovy
// 🟡 FE after BE, as an upstream chain — ⭐ backend first
// in cd-shop-api's post { success { … } }
build job: 'cd-shop-ui',
      parameters: [string(name: 'IMAGE', value: env.UI_IMAGE_REF),
                   string(name: 'AFTER', value: env.BUILD_URL)],
      wait: false
// ⭐ WHY backend first: the backend must serve BOTH the old and the new
//   frontend at every instant. The reverse order guarantees a window where
//   cached frontends call endpoints that do not exist — and that window's
//   length is set by browser cache, not by you.
```

---

## 11 · ▶️ Run it and prove it — the Case 2 acceptance checks

```bash
J=jenkins/cd-checkout.Jenkinsfile

# 1 · ⛔ NO input ANYWHERE — this is the defining check
grep -n 'input(' $J && echo "⛔ a human gate exists — this is Case 1" || echo "✅ no human gate"

# 2 · NO build step
grep -nE 'docker build|go build|mvn|npm ci|kaniko' $J && echo "⛔ CD builds" || echo "✅ no build"

# 3 · a decision function exists and is used
grep -n 'shouldPromote(' $J && echo "✅ judgement is encoded"

# 4 · automatic rollback in post { failure }
grep -n 'argo rollouts abort\|rollout undo' $J && echo "✅ auto-rollback"

# 5 · ⭐⭐ the circuit breaker — set AND checked
grep -n 'HALTED' $J | wc -l          # ⭐ must be >= 2 (set + check)

# 6 · the freeze calendar is read
grep -n 'inFreezeWindow' $J && test -f freezes.yaml && echo "✅ freeze-aware"

# 7 · the overall timeout is SHORT (nothing waits for a human)
grep -n "timeout(time: 90, unit: 'MINUTES')" $J && echo "✅ bounded"

# 8 · a halted run is NOT_BUILT, not FAILURE
grep -n "currentBuild.result = 'NOT_BUILT'" $J && echo "✅ policy outcomes are not red"

# 9 · ⭐⭐ THE DRILL — a deliberately bad digest, end to end
#    (a) /readyz returns 500 → dev fails at rollout status, undoes itself
#    (b) ready OK but 20% of requests 500 → canary analysis → FAIL → abort
#        → ONE Slack + ONE page → HALTED file exists
ls -l /var/jenkins/cd-state/checkout.HALTED
kubectl -n shop-production get rollout checkout -o jsonpath='{.status.abort}{"\n"}'

# 10 · five more bad commits produce NO further pages
for i in 1 2 3 4 5; do
  curl -s -u "$U:$T" -X POST "$JENKINS_URL/job/shop-cd/job/cd-checkout/buildWithParameters" \
    --data-urlencode "IMAGE=$BAD_DIGEST" --data-urlencode "CI_BUILD=drill-$i"
done
sleep 120
# ⭐ every one of those builds must be NOT_BUILT
curl -s -u "$U:$T" "$JENKINS_URL/job/shop-cd/job/cd-checkout/api/json?tree=builds[number,result]{0,5}" | jq

# 11 · clear the breaker and confirm CD resumes
rm /var/jenkins/cd-state/checkout.HALTED

# 12 · ⭐ what is running, one command
kubectl -n shop-production get rollout checkout \
  -o jsonpath='{.spec.template.spec.containers[?(@.name=="checkout")].image}{"\n"}'

# 13 · ⭐ the decision log answers "why did the pipeline ship this?"
jq -r 'select(.service=="checkout") | "\(.timestamp) approve=\(.approve) \(.reasons|length) reason(s)"' \
  /var/jenkins/audit/cd-decisions.jsonl | tail -10
```

⭐⭐ **Checks 1, 5, 9 and 10 are the four that define Case 2.** No `input`, a breaker that is both set and checked, a real self-heal, and **one page rather than five**. Everything else is hygiene.

---

## 12 · Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| CD never triggers | `build job:` path wrong (folder-qualified), or CI did not reach `post { success }` | use the **full path** `'../shop-cd/cd-checkout'`; check the CI log |
| ⛔ `params.IMAGE` is blank | you used `triggers { upstream(...) }`, which passes **no** parameters | §2.1 — use `build job:` with explicit parameters |
| CI builds slow down after adding the trigger | ⛔ `wait: true` | §2.2 — `wait: false` |
| `waitUntil` loops forever | ⛔ no enclosing `timeout()` | §5 — always pair them |
| `waitUntil` returns and the build is green, but the condition was the *bad* case | ⭐ the closure returns `true` to **stop**; if `true` means "3 failures", a normal return is a failure | §5 — `if (fails >= 3) error(...)` after the wait |
| The canary gets no traffic | the Rollout's `trafficRouting` is unset, or the Service selector matches both ReplicaSets | [`04-docker-and-k8s-targets.md`](./04-docker-and-k8s-targets.md) §3 |
| Analysis is always `INCONCLUSIVE` | traffic too low for the window | ⭐ extend the window, or **move the service to Case 1** |
| ⛔ Paged five times in an hour | no halt flag, or the check is after the deploy | §7.2 — check in stage 0 |
| Halted runs are red | `error()` instead of `currentBuild.result = 'NOT_BUILT'` + `return` | §7.2 |
| The breaker never clears | no `clearCdHalt` job, and nobody knows the file path | §7.2 — scheduled, **conditional** on 4h without failures |
| `FORCE` shipped a rejected release | ⛔ FORCE bypassed the metric analysis | §8 — FORCE may override the freeze **only** |
| Groovy sandbox rejection in `shouldPromote` | script security on `JsonOutput` / `readYaml` | ⭐ move it into the **shared library** (runs unsandboxed) — preferred over approving signatures |
| Agents exhausted during a release burst | soaks occupy agents; controller executors in use | §9 — pod agents on `pool: cd`, controller executors = 0, `throttle-concurrents` |
| ⛔ Rollback fails — the old image is gone | registry retention deleted the digest | retain the last N digests; ⭐ digests survive untagging only if the retention policy is digest-aware |

---

<a name="tasks--answers"></a>
## 13 · ⭐ TASKS — answers at the END

| # | Task |
|---|---|
| **T1** | Convert the Case 1 Jenkinsfile into Case 2 — list what you delete and what you add |
| **T2** | Wire the trigger with `build job:` so the digest is passed explicitly, and prove `wait: false` matters |
| **T3** | Write `shouldPromote()` with all eight rules, collecting **every** reason rather than short-circuiting |
| **T4** | Implement the `INCONCLUSIVE` policy and justify failing closed |
| **T5** | Use `waitUntil` + `timeout` correctly for both the canary soak and the post-deploy watch — including the inversion |
| **T6** | Implement automatic rollback in `post { failure }` and in the canary stage, and explain the two placements |
| **T7** | Implement the circuit breaker end to end: set, check, `NOT_BUILT`, and a **conditional** scheduled clear |
| **T8** | Write the freeze calendar in Groovy and make `FORCE` override the freeze but nothing else |
| **T9** | Fix the executor capacity problem for an estate running 40 CD builds a day with 20-minute soaks |
| **T10** | ⭐⭐ Run the drill: a bad digest that passes `/readyz` but 500s on 20% of requests. Report what happens at each of the six checkpoints, and name the gate that caught it |

---

# ✅ ANSWERS

**T1.** **Delete:** the entire `input` step, `submitter`, `submitterPermissionCheck`, `submitterParameter`, the `timeout(time: 72, unit: 'HOURS')` wrapper, the `publishHTML` staging *report* (keep the data, drop the "for a human to read" framing), and the manual `parameters.TARGET` choice. **Add:** an upstream `build job:` trigger passing the digest (§2.2); `shouldPromote()` and the shared library (§3); the canary stage with `argo rollouts` (§6); `post { failure }` automatic rollback plus the halt flag (§7); the freeze calendar (§8); `currentBuild.result = 'NOT_BUILT'` for policy outcomes; and a **short** overall `timeout(time: 90, unit: 'MINUTES')`. **Keep:** `lock` + `milestone`, `disableConcurrentBuilds`, the read-back assertion in `deployAndVerify`, the audit file (⭐ now recording *machine* decisions), and the separate rollback job — as a **manual override**, not the primary path. ⭐ The one-line summary: *Case 1 asks a person; Case 2 asks a function, and the function has to be written down.*

**T2.** §2.2. In the **CI** job's `post { success }`, `build job: '../shop-cd/cd-checkout', parameters: [string(name:'IMAGE', value: env.IMAGE_REF), …], wait: false, propagate: false`. ⭐ **The folder-qualified path matters** — `'../shop-cd/cd-checkout'` from a job inside `shop-ci`; a bare name resolves relative to the current folder and silently fails. **Proving `wait: false` matters:** run a CD build with a 10-minute canary soak while `wait: true`, and watch the CI job's own agent stay allocated for the whole soak — with ten services, ten CI builds are blocked by ten CD soaks. With `wait: false` the CI job finishes the moment CD is queued. `propagate: false` is separate and also required: a CD failure should not mark the CI build failed, because they answer different questions ("did this build?" vs "is this safe to run?"). ⛔ The alternative — `triggers { upstream(...) }` — looks simpler and **cannot pass parameters**, so `params.IMAGE` is blank and you fall back to "find the latest digest", reintroducing exactly the race the digest contract exists to prevent.

**T3.** §3. Eight rules: halt flag, freeze, digest shape, smoke results, **minimum sample size**, **baseline-aware metric comparison**, migration backward-compatibility, concurrent release. ⭐ **Collect every reason rather than short-circuiting** (`reasons << …` then `approve = reasons.isEmpty()`), because "why was this blocked?" needs a complete answer — a gate that reports only the first failing check sends you to fix it, re-run, and discover the second. **Write the decision down every time** (`writeDecision` → `decision.json` → appended to `cd-decisions.jsonl` → archived), including on approval. ⭐⭐ **That record is Case 2's version of Case 1's approval log**, and it is the only thing that lets you answer "why did the pipeline ship this?" six months later. Put `shouldPromote` in the **shared library** so it runs outside the Groovy sandbox — otherwise `JsonOutput` and `readYaml` need per-signature script-security approvals, and a library function you can unit-test is worth more than an inline closure you cannot.

**T4.** §3, rule R5. If `canary.requests < minRequests` (200), push an `INCONCLUSIVE` reason — which makes `approve` false, since reasons are not empty. ⭐ **Fail closed, and then move the service to Case 1.** With 40 requests in the window, one failure is 2.5% and two is 5%: the analysis cannot distinguish a regression from noise, so it is not a gate. Failing *open* would mean low-traffic services are promoted without ever being analysed — Case 2 in name only, and worse than Case 1 because nobody is looking at all. **The nuance worth stating:** fail-closed is right for a *canary analysis* gate but wrong for a *pre-deploy health* gate (a quiet production system should not block a release — see the Azure DevOps file's T10). Knowing which gate you are writing is the actual skill. **Before giving up on the service,** try a 60-minute window (~240 requests) with a **count**-based rule ("any 5xx in the canary halts") rather than a rate — that is a real gate at low volume, just a slower one.

**T5.** §5. `timeout(time: 12, unit: 'MINUTES') { waitUntil(initialRecurrencePeriod: 60000) { … } }` for the post-deploy watch, and `waitUntil(initialRecurrencePeriod: 15000)` with a one-minute `sleep` inside for the canary soak. **Three things to get right:** (a) ⛔ `waitUntil` has **no built-in timeout** — without the enclosing `timeout()` it waits forever and consumes an agent; (b) `initialRecurrencePeriod` is in **milliseconds** and the period **grows** on each false return, which is free backoff that a hand-rolled `sleep` loop does not have; (c) ⭐⭐ **the inversion** — the closure returns `true` to *stop waiting*. So if `true` means "three consecutive failures", then a **normal return from `waitUntil` is the bad case**, and you must follow it with `if (fails >= 3) { error(...) }`. Conversely, for the canary soak, `true` means "we have enough samples" and a normal return is good — but the enclosing `timeout` firing means we never got enough signal, which must be treated as `INCONCLUSIVE` → fail closed (T4). Getting those two directions right in the same file is the whole difficulty.

**T6.** §7.1, **both** placements:
- **In the canary stage**, immediately before `error(...)`: `kubectl argo rollouts abort`. ⭐ Why here: `error()` aborts the stage, and the `post { failure }` block then runs — but if anything between the verdict and the `error()` throws (a Slack call, a `readJSON`), the traffic would still be on the bad canary. Restoring traffic **first**, then reporting, means the user-facing damage stops before the notification is even attempted.
- **In `post { failure { … } }`**: `abort` (idempotent, `2>/dev/null`), then `undo`, then `rollout status`, then set the halt flag, then notify. ⭐ Why here too: it catches failures from **any** stage — a dev rollout that never converged, a staging smoke failure, a production watch that breached — with one implementation.

**The rollback ladder, fastest first:** `argo rollouts abort` (**seconds** — during a canary the stable pods never went away; abort is a traffic-weight change, with no scheduling, no image pull, no start-up and no warm-up) → `argo rollouts undo` (~30 s) → `set image` to the recorded `$PREV` (~60 s and unambiguous, because `deployAndVerify` captured it before switching) → `rollout undo` (⛔ ambiguous after two failures: "the previous revision" is then the *first* bad one, not the last good one). ⭐ That seconds-versus-minutes difference is the real operational argument for progressive delivery, and it is what makes prerequisite 1 ("reversible in < 15 min") trivially true rather than aspirational.

**T7.** §7.2. **Set:** in `post { failure }`, `echo "halted by build $BUILD_URL at $(date -u +%FT%TZ)" > /var/jenkins/cd-state/checkout.HALTED`. **Check:** stage 0, `env.HALTED = fileExists(...)`, and if true set `currentBuild.result = 'NOT_BUILT'`, send one grey Slack message, and `return`. **Clear:** a scheduled `clearCdHalt` job, `cron('H */4 * * *')`, which ⭐ **counts recorded failures in the last 4 hours from the decision log and only clears when that count is zero**. Five rules make it correct: the flag is a **file** on a shared volume (survives restarts, is `ls`-able, and `git`-able if you prefer); a halted run is **`NOT_BUILT`** not `FAILURE` (three weeks of red builds makes red meaningless); it is **never cleared by the job that set it** — the `post { cleanup }` block says so in a comment, because that is the mistake people make; the scheduled clear is **conditional** (clearing unconditionally re-arms the loop that paged you); and it is **per service**, so one bad service does not freeze the estate. **Proving it:** fire five bad builds after a halt and assert every one is `NOT_BUILT` (§11 check 10) — one page, not five.

**T8.** §8. `vars/inFreezeWindow.grovy` reads `freezes.yaml` **from the repo checkout** and returns the matching window's `name` or `null`; three rule types — absolute `windows`, weekend `days`, daily `daily_from`/`daily_to`. In stage 0, a frozen result sets `currentBuild.result = 'NOT_BUILT'` and returns — **green, not red**, because a freeze is a policy outcome and three weeks of red builds makes red meaningless. ⭐ **`FORCE` may override the freeze only.** Implement that structurally rather than by convention: the `FORCE` check appears **only** in the freeze branch (`if (env.FROZEN == 'true' && !params.FORCE)`), while the halt check, the `cosign verify` provenance check and the `shouldPromote()` verdict have **no reference to `params.FORCE` at all**. That way, bypassing them is not a matter of setting a flag — it requires editing the pipeline, which is a reviewed change. **Why:** FORCE exists so a hotfix can ship during a freeze. If it can also ship something the pipeline correctly rejected, it becomes the standard way to ignore the pipeline, and you have built a Case 1 gate with extra steps.

**T9.** §9. The arithmetic: 40 builds/day × 20 minutes of agent time = **~13 agent-hours/day**, concentrated in working hours — so 3–4 concurrent agents at peak, against a controller that probably has 2–5 executors total. Four fixes in order of value: **(1)** ⭐⭐ **Kubernetes pod agents with `nodeSelector: { pool: cd }`** on a dedicated node group, so capacity scales with releases instead of being fixed — a pod is created per build and destroyed after; **(2)** ⭐ **set the controller's executor count to 0** (Manage Jenkins → Nodes → built-in), so no build ever runs on the controller and a CD surge cannot starve the UI or the queue; **(3)** ⭐ **`throttle-concurrents`** with a per-job cap (one CD run per service) and a global cap (say 8), so a burst does not exhaust the node pool; **(4)** shorten soaks where the data allows — a 5-minute soak with 400 requests beats a 10-minute soak with 200, and `waitUntil` returning on `requests >= MIN_REQUESTS` already does this adaptively. ⭐ **The lesson:** *a soaking pipeline is not free.* Case 2 replaces a 72-hour human wait with a 20-minute machine soak — better — but replaces 5 runs a week with 50. Capacity planning is part of adopting Case 2, not an afterthought, and the symptom of skipping it is CI builds queueing behind CD soaks, which looks like "CI got slow" and gets misdiagnosed.

**T10.** ⭐⭐ The bad digest passes `/readyz` but returns 500 on 20% of real requests. Six checkpoints:

1. **Stage 0** — passes. Digest shape valid, not halted, not frozen, `cosign verify` succeeds. ⭐ Correct: provenance is about *where the artifact came from*, not whether it behaves.
2. **Stage 1 (dev)** — ⭐ **passes**, and this is the first finding. `deployAndVerify` waits for `rollout status` (pods become Ready, because `/readyz` lies) and smokes `/readyz` from inside the cluster — which also returns 200. **A readiness probe that does not exercise the real code path is not a gate.** Fix: smoke a *business* endpoint, not just the probe path.
3. **Stage 2 (staging)** — passes for the same reason, and records the baseline. ⭐ Second finding: the baseline is captured from **stable staging**, so if staging has the same blind spot, the baseline is also blind — but the canary comparison is *within production*, canary vs stable, so this does not poison the analysis.
4. **Stage 3 (canary)** — ⭐⭐ **this is where it is caught.** `waitUntil` samples every minute until `requests >= 200`. `canary-metrics.sh` compares the canary cohort (`rollouts-pod-template-hash != stable`) against the stable cohort in the **same window**: `canaryErrRate ≈ 0.20`, `stableErrRate ≈ 0.00`, delta `0.20 > 0.005` → R6 fires. `shouldPromote` returns `approve: false` with the reason recorded in `decision.json`.
5. **Rollback** — `kubectl argo rollouts abort` runs **before** `error(...)`, so traffic returns to the stable pods in **under 10 seconds** (they never went away — abort is a traffic-weight change). `post { failure }` then runs `undo`, sets `checkout.HALTED`, posts **one** Slack message and fires **one** PagerDuty event.
6. **Aftermath** — the next five builds hit stage 0, see the halt file, and finish as **`NOT_BUILT`** in seconds, with no canary, no rollback and no page. A human reads `decision.json` (archived and in the JSONL log), which contains the exact metrics and the reason string, clears the flag, and CD resumes.

⭐ **The gate that caught it: R6, the baseline-aware canary-vs-stable error-rate delta** — and the reason it caught it is that the comparison is *cohort-vs-cohort in the same window*, not against a fixed threshold. **The gate that should have caught it earlier: a business-endpoint smoke test in CI or in `deployAndVerify`.** Every failure caught in stage 1 costs seconds; caught in stage 3 it costs a canary window, a page and a halt. ⭐ **The general lesson: Case 2's analysis is a safety net, not a substitute for a smoke test that exercises real code. A canary that rarely fires is a canary nobody has tested.**

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish_Kumar_Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn: https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260
🔗 GitHub: https://github.com/3558Bhk

*Delete the `input`, write the function — and never clear your own circuit breaker.*

</div>
