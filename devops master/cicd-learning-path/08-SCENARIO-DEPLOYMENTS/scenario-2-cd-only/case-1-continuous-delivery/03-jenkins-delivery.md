# 🔨 CASE 1 · CONTINUOUS DELIVERY WITH JENKINS
### The `input` step as a real approval gate — `submitter`, `submitterParameter`, `timeout` — plus `lock`, `milestone`, and an audit trail you can actually query.

> **Scenario:** CI ran elsewhere ([Scenario 1 · Jenkins](../../scenario-1-ci-only/03-jenkins-ci.md)) and pushed `ghcr.io/3558bhk/<svc>@sha256:…` with the digest recorded. **This pipeline never builds.**
>
> **Tool version anchors:** Jenkins LTS **2.568.3** (Java 21 minimum) · Pipeline: Declarative · **Lockable Resources** · **Milestone** · **Authorization Matrix** · **Build User Vars** · Kubernetes plugin pod agents · `kubectl` v1.34.0 · `helm` v3.17.3.

---

## 📇 Contents

| § | What |
|---|---|
| [1](#1---the-mechanism-the-input-step) | ⭐ The mechanism: the `input` step — and its four settings that decide whether it is a real gate |
| [2](#2---who-is-allowed-to-approve) | ⭐⭐ Who is allowed to approve — Authorization Matrix, and the trap that makes gates decorative |
| [3](#3--the-plugins-you-need) | The plugins you need, and what each one buys |
| [4](#4---the-cd-jenkinsfile--shop-api-full-file) | ⭐ The CD Jenkinsfile — `shop-api`, full file |
| [5](#5--the-shared-library--promotestage) | The shared library — `promoteStage`, so every service gets the same gate |
| [6](#6---what-the-approver-sees) | ⭐ What the approver sees — `message`, `parameters`, and a rich notification |
| [7](#7---the-audit-trail) | ⭐⭐ The audit trail — who approved, when, and how to query it |
| [8](#8---rollback-as-a-first-class-job) | ⭐ Rollback as a first-class job — ungated |
| [9](#9--concurrency-lock-and-milestone) | Concurrency: `lock` and `milestone` — the two problems they solve |
| [10](#10--credentials) | Credentials — folder-scoped, and why CD needs different ones than CI |
| [11](#11--per-app-shape) | Per app shape: FE-only, BE-only, FE+BE, polyglot |
| [12](#12--️-run-it-and-prove-it--the-case-1-acceptance-checks) | ▶️ Run it and prove it — the Case 1 acceptance checks |
| [13](#13--troubleshooting) | Troubleshooting |
| [14](#14---tasks--answers-at-the-end) | Tasks and answers — **answers at the END** |

---

## 1 · ⭐ The mechanism: the `input` step

Jenkins' approval gate is the **`input`** step. It pauses the pipeline until a human responds.

```groovy
def decision = input(
  id:          'prod-approval',                       // stable id for the API
  message:     '🚢 Deploy shop-api to PRODUCTION?',   // ⭐ what the approver reads
  ok:          'Approve deployment',                  // the button label
  submitter:   'platform-leads,release-managers',     // ⭐⭐ WHO may approve
  submitterParameter: 'APPROVER',                     // ⭐ captures the identity
  parameters: [
    string(name: 'ROLLBACK_PLAN', defaultValue: '',
           description: '⭐ How would you roll this back? (required)'),
    choice(name: 'RISK', choices: ['low','medium','high'],
           description: 'Assessed risk')
  ]
)
// ⭐ decision is a MAP when there are parameters, a String when there are not
echo "approved by ${decision.APPROVER}, risk=${decision.RISK}"
```

### The four settings that decide whether it is a real gate

| Setting | Default | ⭐ Why it matters |
|---|---|---|
| **`submitter`** | ⛔ **anyone with Job/Build permission** | without it, the gate is a speed bump, not a control |
| **`submitterParameter`** | not captured | ⭐ without it you cannot answer "who approved?" from the pipeline |
| **`timeout`** | ⛔ **waits forever** | an unattended pipeline holds an executor indefinitely |
| **`parameters`** | none | ⭐ an empty prompt gets an empty decision — see §6 |

```groovy
// ⭐ ALWAYS wrap input in a timeout — forever is not a policy
timeout(time: 72, unit: 'HOURS') {
  def decision = input(id: 'prod-approval', message: '…', submitter: 'platform-leads')
}
// on timeout, `input` throws FlowInterruptedException → the stage fails
// ⭐ and that is correct: an unapproved release should NOT deploy.
```

⭐⭐ **The `input` step and executors:** while a pipeline waits at `input`, it **holds an executor** on the agent. On a controller with 5 executors, five waiting approvals block all builds. Two fixes: run the waiting job on a **dedicated low-cost agent** (a pod with tiny resources), or use the **`throttle-concurrents`** plugin to cap how many CD jobs can be waiting. ⛔ Do not fix it by removing the timeout.

---

## 2 · ⭐⭐ Who is allowed to approve

**The trap:** in a default Jenkins, *anyone who can build the job can approve the `input`*. That includes the person who pushed the code. The gate exists, and it is decorative.

**Two mechanisms, use both:**

| Mechanism | What it does |
|---|---|
| ⭐ **`submitter: 'group-a,group-b,user-x'`** on the `input` step | restricts *this* approval to those principals |
| ⭐ **Authorization Matrix / Role-based Strategy** at the folder level | restricts who can **run** the CD job at all |

```
FOLDER: shop-cd
  ├── Permissions (Authorization Matrix):
  │     platform-leads      → Job/Build, Job/Cancel, Run/Update
  │     developers          → Job/Read            ⛔ NO Job/Build
  │     ci-service-account  → Job/Build           (for the automated stages)
  │
  └── cd-shop-api/Jenkinsfile
        input(submitter: 'platform-leads')        ⭐ the gate
```

### `submitterPermissionCheck` — the flag most people miss

```groovy
input(
  message: 'Approve?',
  submitter: 'platform-leads',
  submitterPermissionCheck: true,   // ⭐⭐ default is FALSE
  submitterParameter: 'APPROVER'
)
```

| Value | Behaviour |
|---|---|
| `false` (default) | Jenkins records the submitter **but does not verify** they are authorised. ⛔ The list is documentation |
| ⭐ `true` | Jenkins **enforces** the submitter list against the authenticated user |

⭐ **Set `submitterPermissionCheck: true` or your `submitter` list is a comment, not a control.**

### The self-approval question

Jenkins has no built-in "requestor cannot approve". Implement it explicitly:

```groovy
// ⭐ the Build User Vars plugin gives you the person who STARTED the build
wrap([$class: 'BuildUser']) {
  def requester = env.BUILD_USER_ID ?: 'unknown'
  def decision = timeout(time: 72, unit: 'HOURS') {
    input(id: 'prod-approval', message: "🚢 Deploy to PRODUCTION?",
          submitter: 'platform-leads', submitterPermissionCheck: true,
          submitterParameter: 'APPROVER', parameters: [/* … */])
  }
  // ⭐⭐ ENFORCE SEPARATION OF DUTIES YOURSELF
  if (decision.APPROVER == requester) {
    error("⛔ ${requester} started this release and cannot also approve it.")
  }
  env.APPROVER  = decision.APPROVER
  env.REQUESTER = requester
}
```

---

## 3 · The plugins you need

| Plugin | ⭐ Why | Without it |
|---|---|---|
| **Pipeline: Basic Steps** | the `input` step | no gate |
| **Lockable Resources** | `lock('prod-deploy')` — one deployment at a time | two releases interleave |
| **Milestone** | `milestone()` — cancels superseded runs | three queued releases all deploy |
| **Authorization Matrix** (or Role-based Strategy) | folder-scoped permissions | anyone can run CD |
| **Build User Vars** | `BUILD_USER_ID` — who started it | you cannot enforce separation of duties |
| **Kubernetes** | pod agents per deployment | no scalable agents |
| **Credentials Binding** | `withCredentials` | secrets in plain text |
| ⭐ **Audit Trail** | logs approvals to a separate file | the record lives only in build logs |
| **Slack / Teams** notification | the approver gets pinged | nobody knows a release is waiting |
| **HTML Publisher** | the staging report as a browsable page | the approver reads raw logs |

---

## 4 · ⭐ The CD Jenkinsfile — `shop-api`, full file

`jenkins/cd-shop-api.Jenkinsfile`

```groovy
// ═══════════════════════════════════════════════════════════════════════
//  WHAT : CD ONLY for shop-api. Takes a DIGEST, deploys
//         dev → staging → ⛔ human gate → production.
//  WHY  : Case 1 Continuous Delivery — Scenario 2.
//         ⭐ NO build, NO mvn, NO docker build, NO image push.
//            The CD credentials are pull-only, so building would fail anyway.
//  TARGET: kind cluster `cicd` · namespaces shop-{dev,staging,production}.
// ═══════════════════════════════════════════════════════════════════════
pipeline {
  agent {
    kubernetes {
      yaml '''
apiVersion: v1
kind: Pod
spec:
  serviceAccountName: jenkins-agent
  containers:
  - name: kubectl
    image: bitnami/kubectl:1.34.0        # ⭐ pinned
    command: ["sleep"]
    args: ["infinity"]
    resources: { requests: { cpu: 100m, memory: 256Mi }, limits: { cpu: 500m, memory: 512Mi } }
  - name: helm
    image: alpine/helm:3.17.3            # ⭐ pinned
    command: ["sleep"]
    args: ["infinity"]
  # ⭐ NO docker, NO maven, NO node container. This pipeline cannot build.
'''
    }
  }

  options {
    timestamps()
    disableConcurrentBuilds()          // ⭐ one CD run per job at a time
    buildDiscarder(logRotator(numToKeepStr: '100'))
    timeout(time: 6, unit: 'HOURS')    // ⭐ outer bound — `input` has its own
    skipDefaultCheckout()              // ⭐ CD does not need the source to build
  }

  parameters {
    string(name: 'IMAGE',   defaultValue: '',
           description: '⭐ Full image ref WITH digest: ghcr.io/3558bhk/shop-api@sha256:…')
    choice(name: 'TARGET',  choices: ['staging', 'production', 'dev'],
           description: 'How far to promote')
    string(name: 'REASON',  defaultValue: '',
           description: '⭐ Why are we shipping this? (shown to the approver)')
    booleanParam(name: 'SKIP_STAGING', defaultValue: false,
           description: '⛔ Only for a hotfix reverting a known-bad release')
  }

  environment {
    SERVICE  = 'shop-api'
    REGISTRY = 'ghcr.io/3558bhk'
    NS_PREFIX = 'shop'
  }

  stages {

    // ═════════════════════════════════════════════════════════════════
    //  STAGE 0 · RESOLVE + VALIDATE THE DIGEST
    // ═════════════════════════════════════════════════════════════════
    stage('0 · Resolve digest') {
      steps {
        script {
          // ⭐⭐ REFUSE TO RUN AT ALL WITHOUT A DIGEST
          def raw = (params.IMAGE ?: '').trim()
          if (!raw) {
            // fall back to the digest CI recorded
            raw = readFile(file: '/var/jenkins/digests/shop-api-latest.txt').trim()
          }
          if (!(raw ==~ /^[a-z0-9._\/-]+@sha256:[0-9a-f]{64}$/)) {
            error("⛔ '${raw}' is not a digest reference. CD refuses tags.")
          }
          env.IMAGE_REF = raw
          env.DIGEST    = raw.split('@')[1]
          currentBuild.displayName  = "#${BUILD_NUMBER} ${env.DIGEST.take(19)}…"
          currentBuild.description  = "→ ${params.TARGET} · ${params.REASON}"
          echo "✅ resolved ${env.IMAGE_REF}"
        }
      }
    }

    // ═════════════════════════════════════════════════════════════════
    //  STAGE 0.5 · PROVENANCE — did OUR CI make this?
    // ═════════════════════════════════════════════════════════════════
    stage('0.5 · Verify provenance') {
      steps {
        container('kubectl') {
          withCredentials([string(credentialsId: 'cosign-public-key', variable: 'COSIGN_KEY')]) {
            sh '''
              set -eu
              echo "$COSIGN_KEY" > /tmp/cosign.pub
              cosign verify --key /tmp/cosign.pub "$IMAGE_REF" >/dev/null \
                || { echo "⛔ signature verification failed"; exit 1; }
              echo "✅ signature verified"
            '''
          }
        }
      }
    }

    // ═════════════════════════════════════════════════════════════════
    //  STAGE 1 · DEV — automatic
    // ═════════════════════════════════════════════════════════════════
    stage('1 · Deploy dev') {
      when { anyOf { expression { params.TARGET in ['dev','staging','production'] } } }
      steps {
        container('kubectl') {
          script { promoteStage('dev') }
        }
      }
    }

    // ═════════════════════════════════════════════════════════════════
    //  STAGE 2 · STAGING — automatic, and it PRODUCES THE EVIDENCE
    // ═════════════════════════════════════════════════════════════════
    stage('2 · Deploy staging') {
      when { expression { params.TARGET in ['staging','production'] } }
      steps {
        container('kubectl') {
          script { promoteStage('staging') }
        }
      }
      post {
        success {
          script {
            // ── ⭐⭐ THE APPROVER'S EVIDENCE ─────────────────────────
            container('kubectl') {
              def ns = 'shop-staging'
              def ready = sh(returnStdout: true, script:
                "kubectl -n ${ns} get deploy ${SERVICE} -o jsonpath='{.status.readyReplicas}/{.spec.replicas}'").trim()
              def stagedDigest = sh(returnStdout: true, script:
                "kubectl -n ${ns} get deploy ${SERVICE} -o jsonpath='{.spec.template.spec.containers[?(@.name==\"${SERVICE}\")].image}'").trim()
              def mig = sh(returnStdout: true, script:
                "kubectl -n ${ns} get job ${SERVICE}-migrate -o jsonpath='{.status.succeeded}' 2>/dev/null || echo n/a").trim()

              env.STAGED_DIGEST = stagedDigest
              def report = """
<h2>⭐ Staging verification — ${env.DIGEST}</h2>
<table border="1" cellpadding="6">
  <tr><td>ready replicas</td><td><b>${ready}</b></td></tr>
  <tr><td>digest running in staging</td><td><code>${stagedDigest}</code></td></tr>
  <tr><td>migration job succeeded</td><td>${mig}</td></tr>
  <tr><td>reason</td><td>${params.REASON}</td></tr>
  <tr><td>requested by</td><td>${env.BUILD_USER_ID ?: 'unknown'}</td></tr>
</table>
<h3>Changes since the last production release</h3>
<pre>${sh(returnStdout: true, script: './scripts/changes-since-last-prod.sh').trim()}</pre>
"""
              writeFile(file: 'staging-report.html', text: report)
              publishHTML(target: [
                reportDir: '.', reportFiles: 'staging-report.html',
                reportName: '⭐ Staging Report', keepAll: true, alwaysLinkToLastBuild: true
              ])
            }
          }
        }
      }
    }

    // ═════════════════════════════════════════════════════════════════
    //  STAGE 3 · ⛔ THE GATE
    // ═════════════════════════════════════════════════════════════════
    stage('3 · ⛔ Production approval') {
      when { expression { params.TARGET == 'production' } }
      steps {
        script {
          // ⭐⭐ the gate. Note submitterPermissionCheck: true —
          //   without it the submitter list is documentation, not a control.
          def decision = timeout(time: 72, unit: 'HOURS') {
            input(
              id: 'prod-approval',
              message: """🚢 Deploy ${SERVICE} → PRODUCTION

digest : ${env.DIGEST}
reason : ${params.REASON}
staging: ${env.STAGED_DIGEST ?: 'NOT VERIFIED'}

⭐ Open the 'Staging Report' on this build before approving.""",
              ok: 'Approve deployment to production',
              submitter: 'platform-leads,release-managers',
              submitterPermissionCheck: true,        // ⭐⭐ ENFORCED
              submitterParameter: 'APPROVER',
              parameters: [
                choice(name: 'RISK', choices: ['low','medium','high'],
                       description: 'Assessed risk of this release'),
                string(name: 'ROLLBACK_PLAN', defaultValue: '',
                       description: '⭐ How would you roll this back? (required)')
              ]
            )
          }

          // ── enforce the required answer ───────────────────────────
          if (!decision.ROLLBACK_PLAN?.trim()) {
            error('⛔ A rollback plan is required to approve a production release.')
          }
          // ── ⭐ enforce separation of duties ───────────────────────
          wrap([$class: 'BuildUser']) {
            if (decision.APPROVER == env.BUILD_USER_ID) {
              error("⛔ ${env.BUILD_USER_ID} started this release and cannot approve it.")
            }
          }
          env.APPROVER       = decision.APPROVER
          env.RELEASE_RISK   = decision.RISK
          env.ROLLBACK_PLAN  = decision.ROLLBACK_PLAN
          currentBuild.description += " · approved by ${decision.APPROVER}"
        }
      }
    }

    // ═════════════════════════════════════════════════════════════════
    //  STAGE 3.5 · ⭐ ASSERT NOTHING DRIFTED WHILE WE WAITED
    // ═════════════════════════════════════════════════════════════════
    stage('3.5 · Assert staging ran THIS digest') {
      when { expression { params.TARGET == 'production' } }
      steps {
        script {
          // ⭐⭐ the gate can sit for days. If staging ran something else,
          //   the approval the human just gave does not describe this artifact.
          if (env.STAGED_DIGEST && env.STAGED_DIGEST != env.IMAGE_REF) {
            error("⛔ staging ran ${env.STAGED_DIGEST} but production was approved for ${env.IMAGE_REF}")
          }
        }
      }
    }

    // ═════════════════════════════════════════════════════════════════
    //  STAGE 4 · PRODUCTION
    // ═════════════════════════════════════════════════════════════════
    stage('4 · Deploy production') {
      when { expression { params.TARGET == 'production' } }
      steps {
        // ⭐ the LOCK replaces "the human was the lock"
        lock(resource: 'shop-production-deploy', inversePrecedence: true) {
          // ⭐ MILESTONE cancels older queued releases of the SAME job
          milestone(ordinal: 100)
          container('kubectl') {
            script { promoteStage('production', runMigration: true) }
          }
          milestone(ordinal: 101)
        }
      }
    }
  }

  post {
    success {
      script {
        if (params.TARGET == 'production') {
          container('kubectl') {
            def running = sh(returnStdout: true, script:
              "kubectl -n shop-production get deploy ${SERVICE} " +
              "-o jsonpath='{.spec.template.spec.containers[?(@.name==\"${SERVICE}\")].image}'").trim()
            // ⭐⭐ READ IT BACK FROM THE CLUSTER. Never trust the deploy step's
            //   exit code as proof of what is running.
            if (running != env.IMAGE_REF) {
              error("⛔ cluster is running ${running}, expected ${env.IMAGE_REF}")
            }
            writeFile(file: '/var/jenkins/digests/shop-api-production.txt', text: running)
            slackSend(channel: '#releases', color: 'good',
              message: "🚢 *${SERVICE} → production*\nDigest: `${env.DIGEST}`\nRequested: ${env.BUILD_USER_ID}\n" +
                       "Approved: ${env.APPROVER} (risk: ${env.RELEASE_RISK})\nReason: ${params.REASON}\n" +
                       "Running: `${running}`\n${env.BUILD_URL}")
          }
        }
      }
    }
    aborted { slackSend(channel: '#releases', color: 'warning',
              message: "⏸️ ${SERVICE} release ${env.BUILD_NUMBER} was not approved (timed out or rejected)") }
    failure { slackSend(channel: '#releases', color: 'danger',
              message: "🚨 ${SERVICE} CD build ${env.BUILD_NUMBER} FAILED → ${env.BUILD_URL}") }
  }
}
```

---

## 5 · The shared library — `promoteStage`

`vars/promoteStage.groovy` — ⭐ so every service gets an **identical** gate and an identical deploy.

```groovy
// ═══════════════════════════════════════════════════════════════════════
//  WHAT : deploy ONE service to ONE namespace, from a DIGEST.
//  WHY  : one implementation of "what deploying means", shared by every
//         CD job. A gate written five times is five chances to get it wrong.
// ═══════════════════════════════════════════════════════════════════════
def call(String stageName, Map opts = [:]) {
  def runMigration = opts.get('runMigration', false)
  def service   = env.SERVICE
  def ns        = "${env.NS_PREFIX}-${stageName}"
  def imageRef  = env.IMAGE_REF
  def timeout_s = opts.get('timeout', '300s')

  // ── ⭐⭐ MIGRATION FIRST, AS A GATED JOB ─────────────────────────────
  if (runMigration) {
    sh """
      set -eu
      kubectl -n ${ns} delete job ${service}-migrate --ignore-not-found
      kubectl -n ${ns} apply -f k8s/${service}/migration-job.yaml
      kubectl -n ${ns} wait --for=condition=complete job/${service}-migrate \\
        --timeout=600s \\
        || { echo '⛔ migration FAILED — not rolling out'; exit 1; }
    """
    // ⭐ failing here STOPS the pipeline. Rolling out anyway is how you get
    //   a fleet half on a new schema.
  }

  // ── THE DEPLOY ─────────────────────────────────────────────────────
  sh """
    set -eu
    kubectl -n ${ns} apply -f k8s/${service}/
    kubectl -n ${ns} set image deploy/${service} ${service}=${imageRef}
    kubectl -n ${ns} rollout status deploy/${service} --timeout=${timeout_s} \\
      || { kubectl -n ${ns} rollout undo deploy/${service}; exit 1; }
  """

  // ── ⭐⭐ VERIFY BY READING THE CLUSTER BACK ─────────────────────────
  def running = sh(returnStdout: true, script:
    "kubectl -n ${ns} get deploy ${service} " +
    "-o jsonpath='{.spec.template.spec.containers[?(@.name==\"${service}\")].image}'").trim()
  if (running != imageRef) {
    error("⛔ ${ns} is running '${running}' but we asked for '${imageRef}'")
  }
  echo "✅ ${ns} confirmed running ${running}"

  // ── SMOKE ──────────────────────────────────────────────────────────
  def probe = opts.get('probe', '/actuator/health/readiness')
  sh """
    set -eu
    kubectl -n ${ns} port-forward deploy/${service} 18080:8080 &
    PF=\$!; sleep 5; trap 'kill \$PF 2>/dev/null || true' EXIT
    for i in \$(seq 1 20); do
      curl -fsS "http://127.0.0.1:18080${probe}" && exit 0
      sleep 3
    done
    echo "⛔ readiness never came up"; exit 1
  """
}
```

---

## 6 · ⭐ What the approver sees

**An `input` with a bare `message: 'Approve?'` gets approved in four seconds.** The prompt *is* the control.

| Element | Where | ⭐ Why |
|---|---|---|
| The digest | `message` | what exactly is being shipped |
| The reason | `message` (from `params.REASON`) | the *why* — required, so it is always present |
| The staging verification | `publishHTML` → "⭐ Staging Report" on the build page | proof it works somewhere production-like |
| What changed | a `git log` range in the report | the blast radius |
| ⭐ A **required** rollback plan | `parameters: [string(name:'ROLLBACK_PLAN')]` + `error()` if blank | forces the approver to think about recovery |
| ⭐ A **risk** choice | `parameters: [choice(name:'RISK')]` | gives you data: are "high" releases actually riskier? |
| A notification with a deep link | `slackSend` at the end of the staging stage | ⭐ the approver must be *told*; Jenkins does not ping by default |

```groovy
// ⭐ notify when the gate OPENS, not when the build starts
stage('2 · Deploy staging') {
  post {
    success {
      slackSend(channel: '#releases', color: 'warning',
        message: """⛔ *Approval needed* — ${SERVICE} → production
Digest : \`${env.DIGEST}\`
Reason : ${params.REASON}
Staging: ✅ ready ${ready} · migration ${mig}
Approve: ${env.BUILD_URL}input/""")
      // ⭐⭐ ${BUILD_URL}input/ is a DIRECT LINK to the approval prompt.
      //   One click from Slack to the decision. That is the whole fix for
      //   "nobody noticed the release was waiting".
    }
  }
}
```

⭐ **`${BUILD_URL}input/` is the detail that makes the gate usable.** Without a deep link, an approver has to find the job, find the build, and find the prompt — three navigations, and in practice they do not happen.

---

## 7 · ⭐⭐ The audit trail

| Question | Where the answer lives |
|---|---|
| Who **started** the release? | `BUILD_USER_ID` (Build User Vars plugin) — ⭐ only inside `wrap([$class:'BuildUser'])` |
| Who **approved** it? | `submitterParameter` → `decision.APPROVER`, echoed to the log |
| When? | `timestamps()` in `options`, plus the input's own timestamp in the build XML |
| What was approved? | `env.IMAGE_REF` / `env.DIGEST` in the log and the build description |
| Why? | `params.REASON` |
| With what risk assessment and rollback plan? | `decision.RISK`, `decision.ROLLBACK_PLAN` |
| ⭐ Durable, queryable record? | **you have to build it** — Jenkins logs rotate |

```groovy
// ⭐⭐ WRITE THE RECORD SOMEWHERE THAT OUTLIVES THE BUILD LOG
def audit = [
  timestamp   : new Date().format("yyyy-MM-dd'T'HH:mm:ss'Z'", TimeZone.getTimeZone('UTC')),
  job         : env.JOB_NAME,
  build       : env.BUILD_NUMBER.toInteger(),
  service     : env.SERVICE,
  environment : 'production',
  digest      : env.DIGEST,
  imageRef    : env.IMAGE_REF,
  requestedBy : env.BUILD_USER_ID,
  approvedBy  : env.APPROVER,
  risk        : env.RELEASE_RISK,
  reason      : params.REASON,
  rollbackPlan: env.ROLLBACK_PLAN,
  url         : env.BUILD_URL,
  outcome     : currentBuild.currentResult
]
// option A — append to a JSON-lines file on a mounted volume
writeFile(file: 'audit.json', text: groovy.json.JsonOutput.toJson(audit) + '\n')
sh 'cat audit.json >> /var/jenkins/audit/shop-production.jsonl'
// option B — ⭐ commit it to a manifests repo, so `git log` IS the audit trail
// option C — send it to your SIEM / a Slack channel with retention
```

```bash
# ⭐ query it: who deployed to production in the last 30 days?
jq -r 'select(.environment=="production") | "\(.timestamp) \(.service) \(.approvedBy) \(.digest[0:19])"' \
  /var/jenkins/audit/shop-production.jsonl | tail -30

# ⭐ and: separation of duties — any release approved by its own requester?
jq -r 'select(.approvedBy==.requestedBy) | .url' /var/jenkins/audit/shop-production.jsonl
```

⭐ **The `input` API, if you would rather query Jenkins itself:**

```bash
# is a build waiting for input right now?
curl -s -u user:token "$JENKINS_URL/job/shop-cd/job/cd-shop-api/123/wfapi/describe" | jq '.stages[]|select(.name|contains("approval"))'

# approve it programmatically (⛔ do NOT wire this into automation — that
#   defeats the entire point of Case 1; use it for testing the gate only)
curl -s -u user:token -X POST "$JENKINS_URL/job/.../123/input/prod-approval/submit" \
  --data 'json={"parameter":[{"name":"RISK","value":"low"},{"name":"ROLLBACK_PLAN","value":"set image to previous digest"}]}'

# list every build currently paused at an input
curl -s -u user:token "$JENKINS_URL/queue/api/json?depth=2" | jq '.items[]|select(.why|contains("Waiting for next available executor"))'
```

---

## 8 · ⭐ Rollback as a first-class job

`jenkins/rollback-shop-api.Jenkinsfile` — a **separate job**, and ⭐ **with no `input`**.

```groovy
pipeline {
  agent { kubernetes { yaml '''
apiVersion: v1
kind: Pod
spec:
  containers:
  - { name: kubectl, image: bitnami/kubectl:1.34.0, command: ["sleep"], args: ["infinity"] }
''' } }

  options {
    timestamps()
    disableConcurrentBuilds()
    timeout(time: 30, unit: 'MINUTES')     // ⭐ short — a rollback is urgent
  }

  parameters {
    choice(name: 'ENVIRONMENT', choices: ['production','staging','dev'])
    string(name: 'TO_DIGEST', defaultValue: '',
           description: '⭐ Roll back TO this digest (blank = previous revision)')
  }

  environment { SERVICE = 'shop-api' }

  stages {
    stage('Roll back') {
      steps {
        // ⭐⭐ the SAME lock as the deploy — a rollback must not race a deploy,
        //   but it must NOT wait for an approval.
        lock(resource: 'shop-production-deploy') {
          container('kubectl') {
            script {
              def ns = "shop-${params.ENVIRONMENT}"
              def to = params.TO_DIGEST?.trim()
              if (to) {
                // ⭐ to a KNOWN GOOD digest — the preferred path, because you
                //   know exactly where you are going
                def ref = to.contains('@') ? to : "${env.REGISTRY}/${SERVICE}@${to}"
                sh "kubectl -n ${ns} set image deploy/${SERVICE} ${SERVICE}=${ref}"
              } else {
                sh "kubectl -n ${ns} rollout history deploy/${SERVICE}"
                sh "kubectl -n ${ns} rollout undo deploy/${SERVICE}"
                // ⛔ after two failed deploys "previous" is the FIRST bad one,
                //   not the last good one. Prefer the explicit digest.
              }
              sh "kubectl -n ${ns} rollout status deploy/${SERVICE} --timeout=300s"
              env.NOW = sh(returnStdout: true, script:
                "kubectl -n ${ns} get deploy ${SERVICE} -o jsonpath='{.spec.template.spec.containers[?(@.name==\"${SERVICE}\")].image}'").trim()
            }
          }
        }
      }
    }
  }

  post {
    always {
      script {
        slackSend(channel: '#releases', color: 'danger',
          message: "🚨 *ROLLBACK* ${SERVICE}/${params.ENVIRONMENT} by ${env.BUILD_USER_ID}\nNow running: `${env.NOW}`\n${env.BUILD_URL}")
        // ⭐⭐ write the rollback to the SAME audit file — a rollback is a
        //   production change and must appear in the same record.
        def audit = [timestamp: new Date().format("yyyy-MM-dd'T'HH:mm:ss'Z'", TimeZone.getTimeZone('UTC')),
                     job: env.JOB_NAME, build: env.BUILD_NUMBER.toInteger(),
                     service: SERVICE, environment: params.ENVIRONMENT,
                     type: 'ROLLBACK', digest: env.NOW,
                     requestedBy: env.BUILD_USER_ID, url: env.BUILD_URL]
        writeFile(file: 'audit.json', text: groovy.json.JsonOutput.toJson(audit) + '\n')
        sh 'cat audit.json >> /var/jenkins/audit/shop-production.jsonl'
      }
    }
  }
}
```

| Rule | Why |
|---|---|
| ⭐⭐ **No `input`** | a gate on the way back is a gate on your own recovery |
| ⭐ **Same `lock` resource as the deploy** | a rollback must not race an in-flight deploy |
| Short outer `timeout` | urgency, and it cannot hang |
| Separate job, separate permissions | ⭐ who may roll back is a different question from who may deploy |
| Writes to the **same** audit file | a rollback is a production change |

---

## 9 · Concurrency: `lock` and `milestone`

Two distinct problems, two distinct tools:

| Problem | ⭐ Tool | What it does |
|---|---|---|
| **Two deployments at once** | `lock(resource: 'shop-production-deploy')` | serialises. The second waits |
| **Three queued releases all deploy** | `milestone(ordinal: N)` | ⭐ **cancels** older queued runs when a newer one reaches the milestone |
| Two runs of the same job at once | `disableConcurrentBuilds()` | the second **queues** (does not cancel) |

```groovy
// ⭐ the canonical combination
stage('4 · Deploy production') {
  steps {
    lock(resource: 'shop-production-deploy', inversePrecedence: true) {
      // ⭐ inversePrecedence: newer builds get the lock FIRST.
      //   Without it, an old queued release can win the lock after you have
      //   already shipped a newer one — deploying the older digest on top.
      milestone(ordinal: 100)     // cancels older queued builds of THIS job
      script { promoteStage('production', runMigration: true) }
      milestone(ordinal: 101)     // anything that reached 100 but not 101 is dead
    }
  }
}
```

⭐ **Why Case 1 needs this at all:** in Case 2, concurrency is a correctness requirement. In Case 1 it is subtler — *the human is the lock*, and humans forget. Two approvers approving two releases five minutes apart is exactly the scenario `lock` + `inversePrecedence` prevents.

---

## 10 · Credentials

| Need | ⭐ Mechanism |
|---|---|
| Pull the image | an `imagePullSecret` in the namespace — CD needs no registry **push** credential at all |
| Reach the cluster | a **kubeconfig** credential, `withKubeConfig` or a mounted file |
| Verify signatures | `cosign-public-key` as a **Secret file** credential |
| Notify | `slack-webhook` as a **Secret text** credential |
| ⭐ Scope | all of the above in the **`shop-cd` folder**, not globally |

```groovy
// ⭐ folder-scoped: a job in another folder cannot use these
withCredentials([file(credentialsId: 'kubeconfig-production', variable: 'KUBECONFIG'),
                 string(credentialsId: 'slack-webhook', variable: 'SLACK_WEBHOOK')]) {
  sh 'kubectl -n shop-production get deploy'
}
```

| | CI (Scenario 1) | CD (this file) |
|---|---|---|
| Registry **push** | ✅ needed | ⛔ **not present** — that is the enforcement |
| Cluster access | ⛔ **absent** | ✅ needed |
| Folder | `shop-ci` | ⭐ `shop-cd`, separate permissions |

⭐⭐ **The asymmetry is the design.** Put CI and CD in **different folders with different permission sets**, and neither can accidentally acquire the other's power. A CD job that cannot push an image cannot drift into being CI+CD, no matter what someone adds to the Jenkinsfile on a Friday evening.

---

## 11 · Per app shape

| Shape | What changes |
|---|---|
| 🔵 **FE only** (`shop-ui`) | `promoteStage('production', probe: '/')`; no migration; ⭐ verify the served `config.js` has the right `API_URL`. Rollback is trivial → consider **no gate** (Case 2 for the FE) |
| 🟢 **BE only** (`shop-api`) | ⭐ this file, as written |
| 🟢 **BE, worker** (`order-worker`) | ⛔ no HTTP probe. Smoke = a broker metric: consumer connected, queue depth not growing. Check via `curl` on the RabbitMQ management API |
| 🟡 **FE + BE** (P10) | ⭐⭐ one pipeline, **two sequential stages** sharing one `lock` and one `input` |
| 🟠 **Polyglot** (P11/P12) | one CD job per service + a **release-train** job that reads the manifest and calls each in dependency order |

```groovy
// 🟡 FE after BE, ONE approval, ONE lock — the ordering is explicit
stage('4 · Deploy production') {
  when { expression { params.TARGET == 'production' } }
  steps {
    lock(resource: 'shop-production-deploy', inversePrecedence: true) {
      milestone(ordinal: 100)
      container('kubectl') {
        script {
          // ⭐⭐ BACKEND FIRST. The backend must serve BOTH the old and the
          //   new frontend at every instant. The reverse order guarantees a
          //   window where cached frontends call endpoints that do not exist.
          env.SERVICE = 'shop-api'
          promoteStage('production', runMigration: true)

          env.SERVICE = 'shop-ui'
          promoteStage('production', probe: '/')

          // ⭐ if the FE fails, roll BOTH back — a half-promoted pair is
          //   worse than either alone
        }
      }
      milestone(ordinal: 101)
    }
  }
}
```

---

## 12 · ▶️ Run it and prove it — the Case 1 acceptance checks

```bash
J=https://jenkins.shop.internal ; T=shop-cd/cd-shop-api

# 1 · NO build step anywhere
grep -nE 'docker build|mvn |npm (ci|install|run build)|go build|pip install|kaniko' \
  jenkins/cd-shop-api.Jenkinsfile && echo "⛔ CD builds" || echo "✅ CD does not build"

# 2 · the gate has submitterPermissionCheck
grep -n 'submitterPermissionCheck: true' jenkins/cd-shop-api.Jenkinsfile \
  && echo "✅ enforced" || echo "⛔ submitter list is documentation only"

# 3 · the gate has a timeout
grep -n "timeout(time: 72, unit: 'HOURS')" jenkins/cd-shop-api.Jenkinsfile && echo "✅ bounded"

# 4 · trigger a run and watch it STOP at the input
curl -s -u "$USER:$TOKEN" -X POST "$J/job/$T/buildWithParameters" \
  --data-urlencode 'IMAGE=ghcr.io/3558bhk/shop-api@sha256:41ab…' \
  --data-urlencode 'TARGET=production' --data-urlencode 'REASON=gate test'
sleep 45
curl -s -u "$USER:$TOKEN" "$J/job/$T/lastBuild/wfapi/describe" \
  | jq '.stages[] | select(.name|test("approval")) | {name,status}'
# ⭐ expect status "PAUSED"

# 5 · a TAG is refused
curl -s -u "$USER:$TOKEN" -X POST "$J/job/$T/buildWithParameters" \
  --data-urlencode 'IMAGE=ghcr.io/3558bhk/shop-api:latest' \
  --data-urlencode 'TARGET=dev' --data-urlencode 'REASON=negative test'
sleep 30
curl -s -u "$USER:$TOKEN" "$J/job/$T/lastBuild/api/json" | jq -r '.result'
# ⭐ expect: FAILURE, at stage 0

# 6 · a non-approver cannot approve
curl -s -u "$NON_APPROVER:$TOKEN" -X POST "$J/job/$T/<N>/input/prod-approval/submit" -w '%{http_code}\n'
# ⭐ expect 403 (because submitterPermissionCheck: true)

# 7 · rollback has NO input
grep -c 'input(' jenkins/rollback-shop-api.Jenkinsfile    # ⭐ must be 0

# 8 · the audit file answers "who deployed to production?"
jq -r 'select(.environment=="production") | "\(.timestamp) \(.approvedBy) \(.digest[0:19])"' \
  /var/jenkins/audit/shop-production.jsonl | tail -5

# 9 · ⭐ what is running in production, one command
kubectl -n shop-production get deploy shop-api \
  -o jsonpath='{.spec.template.spec.containers[?(@.name=="shop-api")].image}{"\n"}'
```

---

## 13 · Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| ⭐ **Anybody can approve** | `submitterPermissionCheck` defaults to `false` | set it to `true` (§1) |
| `decision.APPROVER` is null | `submitterParameter` not set | add it (§1) |
| `decision` is a String, not a Map | ⭐ `input` returns a **String** when there are **no** parameters, a **Map** when there are | either always pass parameters, or handle both |
| `BUILD_USER_ID` is empty | not wrapped in `wrap([$class: 'BuildUser'])` | wrap it (§2) |
| The build hangs forever at `input` | no `timeout` | wrap the `input` (§1) |
| ⛔ All executors consumed by waiting approvals | `input` holds an executor | dedicated cheap agents for CD; `throttle-concurrents` |
| Two releases deploy at once | no `lock` | §9 |
| An **old** digest deploys after a new one | `lock` without `inversePrecedence: true` | §9 |
| Three queued builds all deploy | no `milestone` | §9 |
| `milestone()` cancels builds you wanted | ordinals are per-job and global — a milestone in one stage cancels everything older that has not passed it | use two ordinals bracketing the deploy, as in §4 |
| The report is not visible | `publishHTML` needs the HTML Publisher plugin and a `reportDir` that exists | §3, §4 |
| `promoteStage` not found | the shared library is not configured for the folder | Global Pipeline Libraries / folder-level library |
| Groovy sandbox rejection on `JsonOutput` | script security | approve the signature, or move the code into a **shared library** (which runs un-sandboxed) ⭐ preferred |

---

<a name="tasks--answers"></a>
## 14 · ⭐ TASKS — answers at the END

| # | Task |
|---|---|
| **T1** | Prove that without `submitterPermissionCheck: true` your `submitter` list does nothing |
| **T2** | Add a required `ROLLBACK_PLAN` parameter and make the pipeline fail if the approver leaves it blank |
| **T3** | Enforce separation of duties — the requester cannot approve their own release |
| **T4** | Publish the staging report as HTML and send a Slack notification with a `${BUILD_URL}input/` deep link |
| **T5** | Add the audit record (JSON-lines) and write two queries against it |
| **T6** | Add `lock` with `inversePrecedence: true` plus `milestone`, and explain what each prevents |
| **T7** | Build the ungated rollback job, sharing the deploy's lock resource |
| **T8** | Add the "read the image back from the cluster" assertion to `promoteStage` |
| **T9** | Order FE after BE for shape C, inside one lock and one approval |
| **T10** | ⭐⭐ Your CD pipeline holds all five controller executors because five releases are waiting for approval. Nobody will approve them. Diagnose fully and give three fixes ranked by how much you would recommend them |

---

# ✅ ANSWERS

**T1.** Configure the job in a folder where a **developer** account has `Job/Build`. Run the pipeline with `input(message:'Approve?', submitter:'platform-leads')` — **no** `submitterPermissionCheck`. Sign in as the developer, open `${BUILD_URL}input/`, and click **Proceed**. ⭐ **It succeeds.** Jenkins records the developer as the submitter but does not verify them against the list; the list is documentation. Add `submitterPermissionCheck: true`, repeat, and the same click returns **403**. That single experiment is why the flag matters: without it you have an audit entry claiming a controlled approval, and no control.

**T2.** §4 stage 3: include `string(name:'ROLLBACK_PLAN', defaultValue:'', description:'⭐ How would you roll this back? (required)')` in `parameters`, then immediately after the `input` returns: `if (!decision.ROLLBACK_PLAN?.trim()) { error('⛔ A rollback plan is required…') }`. ⭐ Two details: `decision` is a **Map** only because parameters were supplied (with no parameters `input` returns a String, and `.ROLLBACK_PLAN` would be a `MissingPropertyException`); and the `error()` must come **before** the production stage, so a blank answer aborts rather than deploying. The point is not the string — it is that the approver had to *formulate a recovery plan* before the release proceeds, which is the difference between an approval and a rubber stamp.

**T3.** §2. `wrap([$class: 'BuildUser']) { … }` to capture `BUILD_USER_ID` (⭐ the plugin only populates it inside the wrap, and only for builds started by a person — a timer or upstream trigger yields nothing, which is why the code falls back to `'unknown'`), then compare with `decision.APPROVER` and `error()` on a match. ⭐ **The subtlety worth knowing:** `decision.APPROVER` comes from `submitterParameter`, which is the *authenticated Jenkins user who clicked*, while `BUILD_USER_ID` is the user who *queued* it. They are the same field type, so the comparison is valid — but for a build triggered by `workflow_run`/upstream/timer, `BUILD_USER_ID` is empty and the check passes vacuously. For those, compare against the **commit author** instead, or refuse to run the production path without a human requester at all.

**T4.** §4 stage 2 `post.success`: build the HTML table, `writeFile`, then `publishHTML(target:[reportDir:'.', reportFiles:'staging-report.html', reportName:'⭐ Staging Report', keepAll:true, alwaysLinkToLastBuild:true])` — which puts a link on the build's sidebar. Then `slackSend` with `${env.BUILD_URL}input/`. ⭐ **The deep link is the whole fix.** Jenkins does not notify approvers by default; without a link they must navigate job → build → prompt, and in practice they do not. `keepAll: true` matters for Case 1 specifically: an approval may be reviewed weeks later during an incident, and the report must still be there.

**T5.** §7. Build a map (timestamp in UTC ISO-8601, job, build, service, environment, digest, imageRef, requestedBy, approvedBy, risk, reason, rollbackPlan, url, outcome), serialise with `groovy.json.JsonOutput.toJson`, append to `/var/jenkins/audit/shop-production.jsonl` on a **mounted volume**. Two queries: `jq -r 'select(.environment=="production") | "\(.timestamp) \(.service) \(.approvedBy) \(.digest[0:19])"' … | tail -30` for the release history, and `jq -r 'select(.approvedBy==.requestedBy) | .url'` to find separation-of-duties violations. ⭐ **Why a file rather than the build log:** Jenkins build logs rotate (the `buildDiscarder` in §4 keeps 100), so the log is not a record. And a JSONL file is queryable, exportable to a SIEM, and survives a controller rebuild if the volume is backed up. Better still, **commit the digest to a manifests repo** so `git log` *is* the audit trail — that is the GitOps end-state ([`../../scenario-3-ci-plus-cd/08-gitops-argocd.md`](../../scenario-3-ci-plus-cd/08-gitops-argocd.md)).

**T6.** §9. `lock(resource: 'shop-production-deploy', inversePrecedence: true) { milestone(ordinal: 100); deploy; milestone(ordinal: 101) }`.
- ⭐ **`lock` prevents two concurrent deployments** to the same environment. Without it, two approvers approving five minutes apart produce two interleaved rollouts — the cluster ends up on whichever `set image` landed last, and neither release's verification means anything.
- ⭐ **`inversePrecedence: true` prevents the older release from winning.** Without it the lock is FIFO, so a release queued *before* your hotfix can acquire the lock *after* it and deploy an **older digest on top of a newer one**. This is a genuinely surprising failure and the flag is easy to miss.
- ⭐ **`milestone` prevents a queue of stale releases from all deploying.** Three queued builds reaching the production stage would otherwise each deploy in turn; `milestone(100)` cancels any older build of the same job that has not yet passed ordinal 100.
- `disableConcurrentBuilds()` is different again: it **queues** the second build rather than cancelling it. You want all three, each solving a different problem.

**T7.** §8. A separate job with **no `input`**, a short `timeout(time: 30, unit: 'MINUTES')`, and — critically — `lock(resource: 'shop-production-deploy')`, the **same** resource as the deploy. ⭐ The lock is what makes an ungated rollback safe: it cannot race an in-flight deployment. Prefer the explicit `TO_DIGEST` over `rollout undo`, because after two failed deploys "the previous revision" is the *first* bad one. Write the rollback into the **same** audit file with `type: 'ROLLBACK'` — a rollback is a production change and an audit trail that omits it cannot explain what happened. Drill it: deploy a known-bad digest, roll back, time it. If it exceeds ~15 minutes, prerequisite 1 in [`../00-delivery-vs-deployment.md`](../00-delivery-vs-deployment.md) fails.

**T8.** §5, at the end of `promoteStage`: read the image back with `kubectl get deploy -o jsonpath='{.spec.template.spec.containers[?(@.name=="<service>")].image}'` and `error()` if it differs from `IMAGE_REF`. ⭐ Two details decide whether it works: use the **JSONPath name filter** `[?(@.name=="…")]`, not `[0]` — with an init container or a sidecar, `[0]` returns the wrong container and the check silently passes or silently fails; and run the check **after** `rollout status`, so you are asserting on the state that actually settled. **Why this matters:** `kubectl set image` succeeds if the deployment exists, even when the container name you named does not — a typo produces a green pipeline, a recorded approval, and **production still on the old digest**. Verifying by reading desired state back from the cluster is the only reliable proof, and it is tool-independent: the same assertion belongs in the GitHub Actions and Azure DevOps versions.

**T9.** §11. One `stage('4 · Deploy production')`, one `lock`, one `milestone` pair, and inside it two sequential `promoteStage` calls — `shop-api` with `runMigration: true` first, then `shop-ui` with `probe: '/'`, reassigning `env.SERVICE` between them. ⭐ **Backend first** because the backend must be able to serve *both* the old and the new frontend at every instant; the reverse order guarantees a window where cached frontends call endpoints that do not exist, and that window's length is set by browser cache, not by you. **One approval, not two:** the human authorised "this release", and the pair is the release — two prompts invite approving the FE while the BE failed. Wrap the FE call so that a FE failure rolls back **both**, because a half-promoted pair (new UI, old API) is worse than either alone.

**T10.** ⭐⭐ **Diagnosis:** this is the `input`-holds-an-executor behaviour (§1). A paused `input` is not a cheap wait — the pipeline's thread occupies a numbered executor on its agent for the entire duration. Five waiting releases consume five executors, so *every other job in Jenkins* — CI included — queues behind releases nobody is approving. Two compounding problems: an **architectural** one (waiting costs an executor) and a **process** one (releases are waiting at all).

**Fixes, ranked:**

1. ⭐⭐ **Move CD to its own agents with a label, and give CI a separate pool.** CD pod agents run on nodes labelled `cd`, CI on `ci`; the controller's own executors are set to **0**. Now a hundred waiting approvals cannot starve a single build. This is the correct fix, it is configuration rather than code, and it is what mature Jenkins estates do. Pair it with `throttle-concurrents` to cap *waiting* CD jobs, so the queue itself stays legible.

2. ⭐ **Add the `timeout` you are missing, and shorten it.** 72 hours is generous to the point of harmful — a release nobody has approved in a day is stale, because CI has published newer digests and the staging evidence no longer describes what would ship. `timeout(time: 24, unit: 'HOURS')` fails the build, frees the executor, and sends the "not approved" Slack message from `post { aborted }`. ⛔ The wrong fix here is removing the timeout — that converts a capacity problem into a permanent one.

3. ⭐ **Fix the process, which is why they are waiting.** Five unapproved releases means either the approvers were never notified (add the `${BUILD_URL}input/` deep link — §6), or the team ships more releases than it reviews (add `milestone` so a newer release cancels older queued ones — §9), or the gate is being used for changes that do not need it (move low-risk services to Case 2 — [`../case-2-continuous-deployment/README.md`](../case-2-continuous-deployment/README.md)). ⭐ `milestone` alone typically removes most of the pile-up: stale queued releases stop being worth approving, so they stop being queued.

**What not to do:** raise the executor count. That treats a design problem with capacity, and it fails again the first week somebody ships ten releases. ⭐ **The general lesson worth stating in an interview:** *a paused pipeline is not free.* Any approval mechanism that occupies a worker — Jenkins `input`, a long-running Argo CD sync wave, a held GitHub runner — needs its own capacity budget, or it will eventually starve the system that feeds it.

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish_Kumar_Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn: https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260
🔗 GitHub: https://github.com/3558Bhk

*`submitterPermissionCheck: true` turns a comment into a control — and a paused `input` is never free.*

</div>
