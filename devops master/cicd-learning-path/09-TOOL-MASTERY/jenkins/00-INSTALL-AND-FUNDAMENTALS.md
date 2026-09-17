# 🔨 JENKINS `00` — INSTALL AND FUNDAMENTALS
### Jenkins LTS 2.568.3 on Kubernetes, configured entirely from git (JCasC), dynamic pod agents that disappear, and folder-scoped credentials. **Everything in files `01`–`06` assumes this file.**

> **TARGET:** a Jenkins you can rebuild from a git repo in 20 minutes, whose agents appear per build and vanish after, that has **no Docker socket anywhere**, and whose CI jobs physically cannot see the deploy credential.
> **TIME:** 4–5 hours. **DO NOT SKIP §7** — credential scoping is what makes "CI cannot deploy" a fact instead of a comment.

---

## 📇 Contents

| § | What |
|---|---|
| [1](#1---the-eight-concepts-and-how-they-nest) | ⭐ The eight concepts, and how they nest |
| [2](#2--install-on-kubernetes-with-helm) | Install on Kubernetes with Helm |
| [3](#3---jcasc--configuration-as-code) | ⭐⭐ JCasC — configuration as code, so the UI is never the source of truth |
| [4](#4--the-plugins-that-matter-and-the-ones-that-hurt) | The plugins that matter, and the ones that hurt |
| [5](#5---dynamic-pod-agents) | ⭐⭐ Dynamic pod agents — the thing that makes Jenkins scale on Kubernetes |
| [6](#6---kaniko--building-images-without-a-docker-daemon) | ⭐ Kaniko — building images without a Docker daemon |
| [7](#7---credentials-and-folder-scoping--the-security-model) | ⭐⭐ Credentials and folder scoping — the security model |
| [8](#8---the-two-folder-layout) | ⭐⭐ The two-folder layout: `/shop-ci` and `/shop-cd` |
| [9](#9--the-shared-library-scaffold) | The shared library scaffold |
| [10](#10--backups-upgrades-and-the-ops-you-own) | Backups, upgrades, and the ops you own |
| [11](#11--️-verify-it--the-acceptance-checks) | ▶️ Verify it — the acceptance checks |
| [12](#12--troubleshooting) | Troubleshooting |
| [13](#13---tasks--answers-at-the-end) | Tasks and answers — **answers at the END** |

---

## 1 · ⭐ The eight concepts, and how they nest

```
CONTROLLER  ──── the Jenkins process. It schedules, it stores, it serves the UI.
   │             ⛔ IT SHOULD RUN NO BUILDS. An executor on the controller means
   │                your build shares a JVM and a filesystem with your config.
   │
   ├── NODE / AGENT ──── a machine (or a POD) that runs builds.
   │      │              ⭐ on Kubernetes, agents are EPHEMERAL: created per
   │      │                 build from a pod template, destroyed after.
   │      │
   │      └── EXECUTOR ──── a slot on an agent. #executors = how many builds
   │                        that agent runs CONCURRENTLY.
   │                        ⭐ 1 executor per pod is the right default: pods are
   │                           cheap, isolation is not.
   │
   ├── ITEM ──── anything in the sidebar: a folder, a job, a view.
   │    │
   │    ├── FOLDER ──── ⭐⭐ a container with its OWN credential scope, its own
   │    │               permissions, its own views. In Jenkins this is your
   │    │               ENVIRONMENT BOUNDARY (§7, §8).
   │    │
   │    └── JOB ──── the unit a human triggers.
   │         │
   │         ├── FREESTYLE ──── configured by clicking. ⛔ do not use it for
   │         │                   anything you care about: it is not in git,
   │         │                   not reviewable, not diffable.
   │         │
   │         └── PIPELINE ──── configured by a Jenkinsfile, in git.
   │              │            ⭐ MULTIBRANCH: one job per branch/PR, automatic.
   │              │
   │              └── STAGE ──── a named group, shown in the UI as a column.
   │                   │         ⭐ `parallel { }` nests stages side by side.
   │                   │
   │                   └── STEP ──── the atomic action: `sh`, `checkout`,
   │                                 `kubectl`, `build job:`.
   │
   └── CREDENTIAL ──── a secret, stored encrypted at rest, SCOPED to
                      global / folder / job. ⭐⭐ §7.
```

| Concept | ⭐ The one sentence |
|---|---|
| **Controller** | schedules and stores; ⛔ runs no builds |
| **Agent / node** | runs builds; on Kubernetes it is a **pod that did not exist a minute ago** |
| **Executor** | a concurrency slot; ⭐ 1 per pod |
| **Folder** | ⭐⭐ a credential and permission boundary — the closest Jenkins gets to "environment" |
| **Job** | what a human or a webhook triggers |
| **Pipeline** | a job defined by a **Jenkinsfile in git** |
| **Stage** | a labelled group of steps; the unit the UI shows |
| **Step** | one action |
| **Credential** | a secret with a **scope** — and the scope is the security model |

### 1.1 ⭐ Declarative versus scripted — pick declarative

```groovy
// ✅ DECLARATIVE — a fixed structure: pipeline { agent {} stages { stage { steps {} } } }
//    • validated BEFORE it runs (a typo fails fast, not at 2am on the prod branch)
//    • has `post { }`, `options { }`, `environment { }`, `when { }`, `parallel { }`
//    • readable by someone who does not know Groovy
pipeline {
  agent { label 'shop-go' }
  options { timestamps(); buildDiscarder(logRotator(numToKeepStr: '100')) }
  stages { stage('test') { steps { sh 'go test ./...' } } }
  post   { always { junit 'test.xml' } }
}

// ⛔ SCRIPTED — arbitrary Groovy inside node { }
//    • more powerful, and ⛔ the power is mostly the ability to be unreadable
//    • nothing is validated until it executes
//    → use it ONLY for the escape hatch: `script { }` INSIDE a declarative stage
```

⭐ **The interview answer:** "Declarative for everything, with `script { }` blocks where I need real Groovy. Scripted pipelines are a Turing-tar-pit — the flexibility is genuine, but the cost is that nothing is checked until runtime and nobody but the author can read it."

---

## 2 · Install on Kubernetes with Helm

### 2.1 The cluster

```bash
# ⭐ a dedicated cluster; 16GB/8CPU is the real floor once Maven agents run
kind create cluster --name cicd --wait 5m
kubectl cluster-info --context kind-cicd
kubectl create namespace jenkins
kubectl create namespace shop-dev shop-staging shop-production 2>/dev/null || \
  for ns in shop-dev shop-staging shop-production shop-canary shop-config; do
    kubectl create namespace "$ns"
  done
kubectl get ns
```

### 2.2 ⭐ The RBAC Jenkins needs — least privilege, spelled out

```yaml
# jenkins-rbac.yaml — ⭐⭐ THREE service accounts, not one
---
# (a) the CONTROLLER: manages agent pods. Nothing else.
apiVersion: v1
kind: ServiceAccount
metadata: { name: jenkins-controller, namespace: jenkins }
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: { name: jenkins-agent-manager, namespace: jenkins }
rules:
  - apiGroups: [""]
    resources: ["pods", "pods/exec", "pods/log"]
    verbs: ["get", "list", "watch", "create", "delete", "patch"]
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get", "list", "watch"]          # ⭐ read the agent JNLP secret only
  # ⛔ NO deployments, NO services, NO configmaps, NO namespaces.
  #   The controller's job is to run BUILDS, not to deploy anything.
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: { name: jenkins-agent-manager, namespace: jenkins }
roleRef: { apiGroup: rbac.authorization.k8s.io, kind: Role, name: jenkins-agent-manager }
subjects: [{ kind: ServiceAccount, name: jenkins-controller, namespace: jenkins }]
---
# (b) the CI AGENT: may push images. ⛔ has NO Kubernetes access at all.
apiVersion: v1
kind: ServiceAccount
metadata: { name: jenkins-agent-ci, namespace: jenkins }
# ⭐ deliberately bound to NOTHING. A CI agent that can `kubectl get pods`
#   in shop-production has already lost the asymmetry.
---
# (c) the CD AGENT: may deploy. ⛔ cannot push an image.
apiVersion: v1
kind: ServiceAccount
metadata: { name: jenkins-agent-cd, namespace: jenkins }
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: { name: shop-deployer, namespace: shop-production }
rules:
  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["get", "list", "watch", "patch", "update"]   # ⭐ patch = set image
    # ⛔ NO "delete". A CD pipeline that can delete a Deployment can delete
    #   production. Rollback is `set image` to the previous digest.
  - apiGroups: [""]
    resources: ["pods", "pods/log"]
    verbs: ["get", "list", "watch"]                       # read-back + logs
  - apiGroups: ["batch"]
    resources: ["jobs"]
    verbs: ["get", "list", "watch", "create", "delete", "patch"]   # migrations
  - apiGroups: [""]
    resources: ["events"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: { name: shop-deployer, namespace: shop-production }
roleRef: { apiGroup: rbac.authorization.k8s.io, kind: Role, name: shop-deployer }
subjects: [{ kind: ServiceAccount, name: jenkins-agent-cd, namespace: jenkins }]
# ⭐ repeat the Role+RoleBinding for shop-dev, shop-staging, shop-canary
```

```bash
kubectl apply -f jenkins-rbac.yaml
# ⭐⭐ PROVE the asymmetry NOW, before Jenkins exists
kubectl auth can-i create deployments -n shop-production \
  --as=system:serviceaccount:jenkins:jenkins-agent-ci
# ✅ EXPECT: no
kubectl auth can-i patch deployments -n shop-production \
  --as=system:serviceaccount:jenkins:jenkins-agent-cd
# ✅ EXPECT: yes
kubectl auth can-i delete deployments -n shop-production \
  --as=system:serviceaccount:jenkins:jenkins-agent-cd
# ✅ EXPECT: no        ← ⭐ the CD agent cannot delete production either
```

### 2.3 The Helm install

```bash
helm repo add jenkinsci https://charts.jenkins.io
helm repo update
helm search repo jenkinsci/jenkins --versions | head -5   # ⭐ pick the chart whose
                                                          #   appVersion is 2.568.3

cat > jenkins-values.yaml <<'EOF'
controller:
  # ⭐⭐ PINNED. `latest` means your CI changes behaviour on a Tuesday.
  image:
    tag: "2.568.3-lts-jdk21"
  serviceAccount:
    name: jenkins-controller          # ⭐ the SA from §2.2
    create: false
  resources:
    requests: { cpu: "1",  memory: 2Gi }
    limits:   { cpu: "2",  memory: 4Gi }
  # ⛔ NO EXECUTORS ON THE CONTROLLER — the single most important line here
  numExecutors: 0
  # ⭐ configuration-as-code, loaded from a ConfigMap (§3)
  JCasC:
    defaultConfig: true
    configScripts:
      jenkins-config:
        name: jenkins-casc
  installPlugins:                     # ⭐ explicit list = reproducible controller
    - kubernetes:4333.v2b_1a_1a_8a_5b_c0     # dynamic pod agents
    - workflow-aggregator:600.vb_57cdd26fdd7 # pipeline
    - git:5.7.0
    - github:1.40.0
    - configuration-as-code:1932.v7dcb_20a_b_2a_44
    - job-dsl:1.87                     # ⭐ create jobs FROM code (§3.4)
    - credentials-binding:687.v619cb_15e923f
    - docker-workflow:583.vf7f8c1a_5b_9c8
    - blueocean:1.27.14                # optional UI
    - lockable-resources:132.v3a_1e2a_1e0a_1a_
    - rebuild:332.va_1fb_4762d08d
    - timestamper:1.27
  # ⭐ the admin password comes from a Secret, not from the chart's random one
  admin:
    existingSecret: jenkins-admin
    userKey: user
    passwordKey: password

agent:
  enabled: true
  defaultsProviderTemplate: ""         # ⭐ NO default agent — every job must
                                       #   name a pod template explicitly
  podName: "default"

persistence:
  enabled: true                        # ⭐⭐ /var/jenkins_home MUST persist
  size: 20Gi
  # ⛔ without a PVC, a controller restart loses every job, every credential
  #   and every build record. This is the #1 self-inflicted Jenkins outage.

# ⭐⭐ INGRESS — TLS terminated, because agents talk JNLP/websocket
controller.ingress:
  enabled: true
  hostName: jenkins.local
  tls:
    - secretName: jenkins-tls
      hosts: [jenkins.local]
EOF

kubectl -n jenkins create secret generic jenkins-admin \
  --from-literal=user=admin \
  --from-literal=password="$(openssl rand -base64 18 | tr -d '/+=' | head -c 20)"

helm install jenkins jenkinsci/jenkins -n jenkins -f jenkins-values.yaml --version 5.8.20
kubectl -n jenkins rollout status statefulset/jenkins --timeout=300s
```

```bash
# ⭐ the admin password, if you let the chart generate it
kubectl -n jenkins get secret jenkins -o jsonpath='{.data.jenkins-admin-password}' | base64 -d; echo

# local access without an ingress
kubectl -n jenkins port-forward svc/jenkins 8080:8080 &
sleep 5 && curl -fsS -o /dev/null -w '%{http_code}\n' http://localhost:8080/login   # ✅ 200
```

| Line in that values file | ⭐ Why |
|---|---|
| `numExecutors: 0` | ⭐⭐ builds never run on the controller — so a malicious build cannot read `/var/jenkins_home/credentials.xml` |
| `image.tag: 2.568.3-lts-jdk21` | ⛔ never `latest`; LTS 2.568.3 requires Java 21 |
| `installPlugins:` explicit | a reproducible controller; ⛔ clicking "install" in the UI is not in git |
| `persistence.enabled: true` | the #1 self-inflicted outage |
| `defaultsProviderTemplate: ""` | forces every job to name its pod template — no accidental builds on a default agent |
| `serviceAccount.name: jenkins-controller` | ⭐ the least-privilege SA, not a cluster-admin one |

⛔ **The chart's default is `cluster-admin`-ish in older versions.** Always check: `kubectl get clusterrolebinding -o yaml | grep -B5 jenkins`. If Jenkins is bound to `cluster-admin`, an agent pod compromise is a cluster compromise.

---

## 3 · ⭐⭐ JCasC — configuration as code

**The problem JCasC solves:** every setting you click in the Jenkins UI lives in `$JENKINS_HOME` XML files that nobody reviews, nobody diffs, and nobody can rebuild. Your Jenkins becomes a **pet**.

```
⛔ WITHOUT JCasC
   200 clicks over 6 months. The controller dies. You rebuild it in a week,
   from memory, and discover three jobs nobody documented.

✅ WITH JCasC
   jenkins-casc.yaml in git. Rebuild = helm install. 20 minutes.
   ⭐ And a change to the security realm is a REVIEWED PULL REQUEST.
```

### 3.1 A complete JCasC for this curriculum

```yaml
# jenkins-casc.yaml
jenkins:
  systemMessage: "shop CI/CD — configured from git. ⛔ Do not edit in the UI."
  numExecutors: 0                     # ⭐⭐ the controller runs NO builds
  mode: EXCLUSIVE
  quietPeriod: 2
  scmCheckoutRetryCount: 2
  disableRememberMe: false
  projectNamingStrategy: standard

  securityRealm:
    local:
      allowsSignup: false             # ⛔ never allow self-signup
      users:
        - id: "${jenkins-admin-user}"
          password: "${jenkins-admin-password}"

  authorizationStrategy:
    globalMatrix:
      entries:
        - user:  { name: "admin",       permissions: ["Overall/Administer"] }
        - group: { name: "shop-devs",   permissions:
                     ["Overall/Read", "Job/Read", "Job/Build", "Job/Cancel",
                      "View/Read"] }
        # ⭐ NO Job/Configure and NO Job/Delete for developers: they may RUN
        #   a pipeline, not change what it does. Changing it is a git commit.
        - group: { name: "shop-release-managers", permissions:
                     ["Overall/Read", "Job/Read", "Job/Build", "Job/Cancel",
                      "Job/Configure", "Credentials/View"] }

  remotingSecurity:
    enabled: true                     # ⭐⭐ agent→controller channel is authenticated

  # ── ⭐ THE POD TEMPLATES (§5) ─────────────────────────────────────────
  clouds:
    - kubernetes:
        name: kubernetes
        serverUrl: "https://kubernetes.default"
        namespace: jenkins
        jenkinsUrl: "http://jenkins.jenkins.svc.cluster.local:8080"
        jenkinsTunnel: "jenkins-agent.jenkins.svc.cluster.local:50000"
        containerCapStr: "20"          # ⭐ hard ceiling on concurrent agent pods
        maxRequestsPerHostStr: "32"
        retentionTimeout: 300
        waitForPodSec: 600
        templates:                     # ← see §5.2 for the full definitions
          - name: shop-java
            label: shop-java
            nodeUsageMode: EXCLUSIVE
            serviceAccount: jenkins-agent-ci
            containers: [{ name: maven, image: "maven:3.9.11-eclipse-temurin-21",
                           command: "sleep", args: "infinity",
                           resourceRequestCpu: "2", resourceRequestMemory: "6Gi",
                           resourceLimitCpu: "4", resourceLimitMemory: "8Gi" }]
            yamlMergeStrategy: override
            podRetention: never        # ⭐⭐ the pod is DELETED after the build

unclassified:
  location:
    url: "https://jenkins.local/"      # ⭐ REQUIRED or webhook/redirect breaks
    adminAddress: "platform@shop.local"

  timestamper:
    allPipelines: true                 # ⭐ timestamps on every log line

  globalLibraries:
    libraries:
      - name: shop-pipeline            # ⭐ the shared library (§9)
        defaultVersion: main
        retriever:
          modernSCM:
            scm:
              github:
                repoOwner: 3558Bhk
                repository: jenkins-shared-library
                credentialsId: github-readonly

security:
  globalJobDslSecurityConfiguration:
    useScriptSecurity: false           # ⭐ job-dsl runs from a TRUSTED repo
  scriptApproval:
    approvedSignatures: []             # ⭐⭐ keep this EMPTY. Every entry here is
                                       #   a Groovy method someone approved to
                                       #   run with controller privileges. Move
                                       #   the code into the shared library
                                       #   instead (§9).

jobs:
  - script: >
      folder('shop-ci') {
        displayName('shop · CI')
        description('Builds and publishes images. ⛔ holds NO cluster credential.')
      }
  - script: >
      folder('shop-cd') {
        displayName('shop · CD')
        description('Deploys published digests. ⛔ holds NO registry-push credential.')
      }
```

```bash
kubectl -n jenkins create configmap jenkins-casc --from-file=jenkins-casc.yaml \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n jenkins rollout restart statefulset/jenkins
# ⭐ verify it loaded
curl -fsS -u admin:"$PASS" http://localhost:8080/configuration-as-code/ | head -20
```

### 3.2 ⭐ The JCasC rules that keep you honest

| Rule | ⭐ Why |
|---|---|
| **Everything in git, nothing in the UI** | a UI change is invisible, unreviewed and lost on rebuild |
| ⭐ `numExecutors: 0` **and** `mode: EXCLUSIVE` | two independent guarantees that builds never run on the controller |
| ⛔ `approvedSignatures: []` stays empty | each entry is a Groovy method granted controller-level execution. **Move the code to the shared library instead** |
| `allowsSignup: false` | self-signup on a CI controller is how you get an anonymous admin |
| `remotingSecurity.enabled: true` | the agent→controller channel is otherwise an unauthenticated RCE vector |
| ⭐ `location.url` set correctly | webhooks, PR statuses and redirects all break silently without it |
| `podRetention: never` | ⭐⭐ a lingering agent pod is a lingering copy of your source, your secrets and your build cache |

### 3.3 ⭐⭐ The "two sources of truth" trap

```
JCasC configures the CONTROLLER. It does NOT configure your JOBS.
Your jobs come from Jenkinsfiles in git.

⛔ THE FAILURE: you define a job's behaviour in JCasC (or in the UI) AND in
   a Jenkinsfile. Now which one wins depends on load order, and a change to
   one silently does nothing.

✅ THE RULE:
   • JCasC  → the controller, the clouds/pod templates, the security realm,
              the FOLDERS, the global libraries.  ⭐ INFRASTRUCTURE.
   • job-dsl → which jobs exist and where their Jenkinsfile is. ⭐ TOPOLOGY.
   • Jenkinsfile → what a build DOES.                         ⭐ BEHAVIOUR.
   Three layers, three places, no overlap.
```

### 3.4 job-dsl — creating the jobs from code

```groovy
// jobs.groovy — ⭐ the TOPOLOGY layer: which jobs exist, nothing more
['shop-ui', 'shop-api', 'checkout', 'order-worker', 'payment-mock'].each { svc ->
  multibranchPipelineJob("shop-ci/ci-${svc}") {
    branchSources {
      github {
        id("ci-${svc}")
        repoOwner('3558Bhk'); repository('shop')
        credentialsId('github-readonly')
        // ⭐⭐ path filters: only build when THIS service changed
        //    (a monorepo with 5 services and no filter = 5 × wasted builds)
      }
    }
    orphanedItemStrategy { discardOldItems { numToKeep(20) } }
    sources {
      docker {
        dockerfile {
          // ⭐ the Jenkinsfile lives in the repo; nothing is defined here
          scriptPath("ci/jenkins/ci-${svc}.Jenkinsfile")
        }
      }
    }
  }
}

// ⭐ and the CD side, in the OTHER folder
['shop-ui', 'shop-api', 'checkout', 'order-worker', 'payment-mock'].each { svc ->
  pipelineJob("shop-cd/cd-${svc}") {
    definition {
      cpsScm {
        scm { git { remote { url('https://github.com/3558Bhk/shop.git')
                             credentials('github-readonly') }
                    branches('main') } }
        scriptPath("ci/jenkins/cd-${svc}.Jenkinsfile")
        lightweight(true)               // ⭐ fetch ONLY the Jenkinsfile, not
                                        //   the whole repo, to decide whether
                                        //   to run. Matters on a monorepo.
      }
    }
    logRotator { numToKeep(200) }       # ⭐ the audit trail (§ file 02)
  }
}
```

---

## 4 · The plugins that matter, and the ones that hurt

### 4.1 ⭐ Required

| Plugin | What it gives you | ⚠️ |
|---|---|---|
| **kubernetes** | ⭐⭐ dynamic pod agents — the reason to run Jenkins on K8s at all | pin the version; it changes pod-template semantics |
| **workflow-aggregator** | Pipeline (declarative + scripted) | the meta-plugin; pulls ~30 others |
| **git** / **github** | SCM + PR status + webhooks | |
| **configuration-as-code** | ⭐ JCasC | §3 |
| **job-dsl** | ⭐ jobs defined in code | §3.4 |
| **credentials-binding** | `withCredentials { }` | ⭐ the ONLY way to touch a secret in a build |
| **lockable-resources** | ⭐ `lock('shop-production')` — mutual exclusion between deploys | file `02` |
| **pipeline-utility-steps** | `readFile`, `writeJSON`, `readYaml` | the manifest handling |
| **timestamper** | timestamps in logs | incident timelines are unreadable without it |
| **rebuild** | re-run a build with the same parameters | the fastest rollback in Jenkins |
| **junit** / **htmlpublisher** | test reports | |
| **warnings-ng** | static-analysis trend graphs | pairs with SpotBugs/ruff/golangci |
| **blueocean** (optional) | a readable pipeline UI | ⛔ heavy; skip on a small controller |

### 4.2 ⛔ The ones that hurt

| Plugin / practice | ⛔ Why |
|---|---|
| **`docker-workflow` + a mounted Docker socket** | ⭐⭐ root on the node. Use **Kaniko** (§6) |
| **`groovy` (the "execute Groovy script" build step)** | runs arbitrary code **on the controller**, as the Jenkins user, unrestricted. ⛔ Remove it. Groovy belongs in a **shared library**, where it is versioned and reviewed |
| **A long `approvedSignatures` list** | each entry is a sandbox escape someone granted. ⭐ The fix is always "move it to the library", never "approve the signature" |
| **`email-ext` pointed at a personal inbox** | alerts nobody reads. Send to a channel with an on-call rotation |
| **⛔ 200 plugins** | every plugin is (a) attack surface, (b) an upgrade blocker, (c) a memory leak candidate. ⭐ Audit quarterly: *which plugin did we use this month?* |
| **A plugin you cannot name the maintainer of** | unmaintained plugins are how Jenkins CVEs happen |

```bash
# ⭐ the quarterly plugin audit, as a script not a promise
curl -fsS -u admin:"$PASS" http://localhost:8080/pluginManager/api/json?depth=1 \
  | jq -r '.plugins[] | select(.active) | "\(.shortName) \(.version) \(.hasUpdate)"' \
  | sort | tee plugins.txt
wc -l plugins.txt          # ⛔ over ~60 and you have a maintenance problem
grep -c 'true$' plugins.txt # ⭐ pending updates — schedule them, do not ignore
```

---

## 5 · ⭐⭐ Dynamic pod agents

### 5.1 Why this is the whole point of Jenkins-on-Kubernetes

```
⛔ STATIC AGENTS (the 2015 model)
   Three VMs, always on, each with a workspace directory that accumulates
   source, images, node_modules and secrets from EVERY build for months.
   • ⛔ cache poisoning: build N inherits build N-1's filesystem
   • ⛔ a "clean" build is not clean, so failures are not reproducible
   • ⛔ you pay for idle capacity, and you run out at the worst moment
   • ⛔ the agent is a PET: patch it by hand, or lose it

✅ DYNAMIC POD AGENTS
   A pod is created FROM A TEMPLATE when a build starts, runs ONE build,
   and is DELETED. `podRetention: never`.
   • ⭐ every build starts from a known image — reproducible by construction
   • ⭐ capacity is elastic: 20 builds at once = 20 pods, then zero
   • ⭐ per-language images: Maven gets 8Gi, Go gets 2Gi
   • ⭐ the agent is CATTLE: a bad image is a bad template, fixed in git
```

### 5.2 The four pod templates for this estate

```yaml
# ⭐ in JCasC (§3.1) under jenkins.clouds[0].kubernetes.templates
- name: shop-java
  label: shop-java
  nodeUsageMode: EXCLUSIVE          # ⭐ only jobs that ask for 'shop-java'
  serviceAccount: jenkins-agent-ci  # ⭐ the CI SA — cannot deploy
  containers:
    - name: maven
      image: maven:3.9.11-eclipse-temurin-21
      command: sleep
      args: infinity
      resourceRequestCpu: "2";  resourceRequestMemory: 6Gi
      resourceLimitCpu:   "4";  resourceLimitMemory:   8Gi   # ⭐⭐ §6 of shape D
      alwaysPullImage: true       # ⭐ never trust a cached agent image
      workingDir: /home/jenkins/agent
  - name: postgres                # ⭐⭐ a SIDECAR — Testcontainers has no daemon
    image: postgres:17.7
    envVars: [{ key: POSTGRES_PASSWORD, value: shop }, { key: POSTGRES_DB, value: shop }]
    resourceRequestMemory: 1Gi
  volumes:
    - persistentVolumeClaim: { claimName: jenkins-m2-cache, mountPath: /root/.m2 }
  podRetention: never             # ⭐⭐ DELETE the pod after the build
  activeDeadlineSeconds: 900
  yamlMergeStrategy: override

- name: shop-node
  label: shop-node
  serviceAccount: jenkins-agent-ci
  containers:
    - name: node
      image: node:24-alpine
      command: "cat"; ttyEnabled: true
      envVars: [{ key: NODE_OPTIONS, value: "--max-old-space-size=6144" }]  # ⭐ Vite
      resourceRequestCpu: "1";  resourceRequestMemory: 4Gi
      resourceLimitCpu:   "2";  resourceLimitMemory:   6Gi
  - name: kaniko                    # ⭐ the image builder (§6)
    image: gcr.io/kaniko-project/executor:v1.23.2-debug
    command: "sleep"; args: "infinity"
  volumes:
    - emptyDir: { mountPath: /workspace }
  podRetention: never

- name: shop-go
  label: shop-go
  serviceAccount: jenkins-agent-ci
  containers:
    - name: golang
      image: golang:1.25-alpine
      command: "cat"; ttyEnabled: true
      resourceRequestCpu: "1";  resourceRequestMemory: 1Gi
      resourceLimitCpu:   "2";  resourceLimitMemory:   2Gi   # ⭐ Go needs little
  - name: kaniko
    image: gcr.io/kaniko-project/executor:v1.23.2-debug
    command: "sleep"; args: "infinity"
  podRetention: never

- name: shop-cd                     # ⭐⭐ THE ONLY TEMPLATE WITH DEPLOY RIGHTS
  label: shop-cd
  serviceAccount: jenkins-agent-cd  # ← may patch deployments, ⛔ cannot push
  containers:
    - name: kubectl
      image: bitnami/kubectl:1.37
      command: "cat"; ttyEnabled: true
      resourceRequestCpu: 250m; resourceRequestMemory: 256Mi
    - name: cosign
      image: ghcr.io/sigstore/cosign:v3.0.2
      command: "sleep"; args: "infinity"
  podRetention: never
```

| Detail | ⭐ Why |
|---|---|
| `nodeUsageMode: EXCLUSIVE` | a job that asks for `shop-go` gets a Go pod, never a leftover Java one |
| ⭐ **a different `serviceAccount` per template** | `jenkins-agent-ci` for builds, `jenkins-agent-cd` for deploys. **The pod template is where the credential asymmetry becomes real** |
| `alwaysPullImage: true` | ⛔ a cached agent image is an unpinned, unscanned dependency |
| `podRetention: never` | no lingering copy of your source and secrets |
| ⭐ a `postgres`/`mongod` **sidecar** | there is no Docker daemon in a pod agent, so Testcontainers cannot start one (§6 of shape B / MERN §7.2) |
| ⭐ `ttyEnabled: true` + `command: cat` | keeps the container alive so `sh` steps have something to exec into. ⛔ Without it the container exits instantly and the pod never becomes Ready |
| resource **requests AND limits** | ⛔ limits without requests → the pod is scheduled onto a node that cannot hold it → OOMKilled |

### 5.3 Using a template in a Jenkinsfile

```groovy
pipeline {
  // ⭐⭐ OPTION A — a pre-defined template by label (simplest, preferred)
  agent { label 'shop-java' }

  stages {
    stage('test') {
      steps {
        container('maven') {                 // ⭐ name the CONTAINER in the pod
          sh './mvnw -B -ntp verify'
        }
        container('postgres') {              // ⭐ the sidecar is reachable at localhost
          sh 'pg_isready -U shop'
        }
      }
    }
  }
}
```

```groovy
pipeline {
  // ⭐ OPTION B — an INLINE pod template, when a build needs something special
  agent {
    kubernetes {
      yaml '''
apiVersion: v1
kind: Pod
metadata:
  labels: { jenkins/label: shop-mern }
spec:
  serviceAccountName: jenkins-agent-ci
  containers:
    - name: node
      image: node:24-alpine
      command: ["cat"]
      tty: true
      env: [{ name: NODE_OPTIONS, value: "--max-old-space-size=6144" }]
      resources: { requests: { cpu: "1", memory: 4Gi }, limits: { cpu: "2", memory: 6Gi } }
    - name: mongod                            # ⭐⭐ MERN: a real replica set
      image: mongo:8.0
      args: ["--replSet", "rs0", "--bind_ip_all"]
      readinessProbe:
        exec: { command: ["mongosh","--quiet","--eval","db.hello().ok"] }
        initialDelaySeconds: 5
      resources: { requests: { memory: 2Gi }, limits: { memory: 3Gi } }
  volumes:
    - name: workspace
      emptyDir: {}
'''
    }
  }
  stages {
    stage('initiate the replica set') {
      steps {
        // ⭐⭐ REQUIRED — a bare `--replSet rs0` mongod is NOT a replica set
        //   until someone initiates it, and Mongoose transactions need one.
        container('mongod') {
          retry(5) {
            sh 'sleep 3; mongosh --quiet --eval \'rs.initiate()\' || true'
          }
          sh 'sleep 5; mongosh --quiet --eval \'rs.status().ok\' | grep -q 1'
        }
      }
    }
    stage('test') {
      steps {
        container('node') {
          // ⭐ the sidecar is reachable at localhost:27017 — no Testcontainers needed
          sh '''
            export MONGODB_URL="mongodb://localhost:27017/shop_test?replicaSet=rs0"
            npm ci
            npm run build -w @shop-mern/shared
            npm run typecheck
            npx vitest run --coverage
          '''
        }
      }
    }
  }
}
```

⭐ **Option A versus B:** use **A** (a JCasC template) for anything used by more than one job — it is versioned, reviewed and consistent. Use **B** (inline `yaml`) for the one-off, and accept that it lives in a Jenkinsfile where it is harder to review. ⛔ The anti-pattern is twenty jobs each carrying a slightly different inline copy of "the Java pod".

---

## 6 · ⭐ Kaniko — building images without a Docker daemon

### 6.1 ⛔ Why not just mount the socket

```
The obvious fix for "my pod agent has no Docker" is:
   volumes:
     - hostPath: { path: /var/run/docker.sock }

⛔⛔ THAT IS A ROOT SHELL ON THE NODE.
   The Docker socket has no authentication and no authorisation model.
   Anyone who can talk to it can start a privileged container mounting
   the node's filesystem at /. Your build runs `npm install`, which runs
   arbitrary postinstall scripts, which now run as root on the node,
   which runs every other pod on that node.

   ⭐ One line in a pod template = cluster compromise. And it is the line
     every "Jenkins on Kubernetes" tutorial written before 2019 has.
```

### 6.2 ✅ Kaniko

```groovy
// vars/buildAndPushImage.groovy — ⭐ in the shared library (§9)
def call(Map cfg) {
  // cfg: [context: 'apps/shop-api', image: 'ghcr.io/3558bhk/shop-api',
  //       tag: "sha-${env.GIT_COMMIT}", digestFile: 'digest.txt']
  def digestOut = "/workspace/${cfg.digestFile}"
  container('kaniko') {
    sh """
      set -euo pipefail
      /kaniko/executor \\
        --context=dir://\${WORKSPACE}/${cfg.context} \\
        --dockerfile=\${WORKSPACE}/${cfg.context}/Dockerfile \\
        --destination=${cfg.image}:${cfg.tag} \\
        --cache=true \\
        --cache-repo=${cfg.image}-cache \\
        --cache-ttl=168h \\
        --reproducible \\
        --snapshot-mode=redo \\
        --compressed-caching=false \\
        --image-name-with-digest-file=${digestOut} \\
        --verbosity=info
    """
  }
  // ⭐⭐ the digest leaves the build as a FILE, not as a parsed log line
  def ref = readFile(digestOut).trim()
  if (!(ref ==~ /.*@[a-z0-9]+:[0-9a-f]{64}/)) error("⛔ not a digest: ${ref}")
  return ref
}
```

| Flag | ⭐ What it does |
|---|---|
| `--context=dir://…` | ⭐ build from a **directory**, not a Docker daemon. This is the whole point |
| `--destination=repo:tag` | where to push |
| ⭐ `--image-name-with-digest-file=` | writes `repo@sha256:…` to a file. **The digest leaves the build without parsing a log** |
| `--cache=true` + `--cache-repo=` | layer cache in the **registry**, so an ephemeral pod still gets warm builds |
| `--cache-ttl=168h` | a week; ⛔ an unbounded cache serves stale base layers forever |
| `--reproducible` | ⭐ strips timestamps and orders filesystem entries → the same inputs give the same digest |
| `--snapshot-mode=redo` | ⭐ 5–10× faster layer snapshotting than the default `full` |
| ⭐ `--compressed-caching=false` | **required when the pod's memory limit is small.** Kaniko caches compressed layers in memory by default and will OOMKill on a large image. This is the #1 Kaniko failure and the flag nobody knows |
| ⛔ missing | `--build-arg` — pass build args explicitly; ⛔ never pass a secret as a build arg (it lands in the image config) |

```bash
# ⭐ the alternative, if you have BuildKit available: a buildkitd sidecar
#   Same property (no Docker socket), better cache, more setup.
#   Kaniko is the right default; BuildKit is the upgrade when cache speed matters.
```

---

## 7 · ⭐⭐ Credentials and folder scoping — the security model

### 7.1 The five credential types you will actually use

| Kind | Use for | ⭐ Note |
|---|---|---|
| **Username with password** | a registry login (GHCR: username + PAT) | the PAT needs `write:packages` and **nothing else** |
| **Secret text** | a single token or key | ⭐ the cosign key, a webhook secret |
| **Secret file** | a kubeconfig, a JSON key | ⭐⭐ the kubeconfig for `/shop-cd` |
| **SSH username with private key** | git over SSH | prefer a **deploy key** scoped to one repo |
| **Certificate** | mTLS | rare |

### 7.2 ⭐⭐ Scope is everything

```
A credential in Jenkins has a SCOPE:

   GLOBAL          visible to EVERY job on the controller
      ⛔ a CI job in /shop-ci can use the production kubeconfig.
         "CI cannot deploy" is now false, and nothing tells you.

   FOLDER          visible to jobs in that folder AND ITS CHILDREN
      ✅ /shop-cd's kubeconfig is invisible to /shop-ci. Not by policy —
         by lookup. A job in /shop-ci asking for that credential ID gets
         nothing, and the build FAILS LOUDLY.

   JOB             visible to one job
      ✅ the tightest, and the hardest to maintain across 5 services

⭐⭐ THE RULE FOR THIS CURRICULUM:
   • registry-push credential  → FOLDER scope on /shop-ci
   • kubeconfig(s)             → FOLDER scope on /shop-cd
   • ⛔ NOTHING deploy-related is ever GLOBAL
   • a github-readonly token   → GLOBAL is acceptable (it can only read)
```

### 7.3 Defining them

```bash
# ⭐ via the CLI/API so they are reproducible, not clicked
# GHCR push — scoped to /shop-ci
curl -fsS -u admin:"$PASS" -X POST http://localhost:8080/job/shop-ci/createCredentials \
  --data-urlencode 'json={
    "scope":"GLOBAL",
    "id":"ghcr-push",
    "username":"3558Bhk",
    "password":"ghp_xxxxxxxxxxxxxxxxxxxx",
    "description":"GHCR write:packages. ⛔ Scoped to /shop-ci by folder."
  , "_":{"$class":"com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl"}}'

# the production kubeconfig — scoped to /shop-cd
kubectl -n jenkins create secret generic cd-kubeconfig-prod \
  --from-file=kubeconfig=$HOME/.kube/config --dry-run=client -o yaml | kubectl apply -f -
# then register it as a SecretFileCredential with id `kubeconfig-shop-production`
# ⭐⭐ and restrict the kubeconfig ITSELF to the CD service account — a
#   kubeconfig with cluster-admin defeats every folder scope you set.
```

### 7.4 Using them — the only correct way

```groovy
// ✅ withCredentials BINDS the secret to an env var for the duration of the
//    block, and MASKS it in the log.
withCredentials([usernamePassword(credentialsId: 'ghcr-push',
                                  usernameVariable: 'REG_USER',
                                  passwordVariable: 'REG_PASS')]) {
  sh 'echo "$REG_PASS" | kaniko … '      // ⭐ masked as **** in the console
}

// ⛔ NEVER:
//   • env.PASS = credentials('x')      → lands in the build's environment dump
//   • sh "docker login -u u -p ${PASS}"→ the ARGUMENT LIST is visible in `ps`
//                                        to every other process in the pod
//   • echo "$PASS"                     → unmasked if you interpolate it yourself
//   • storing it in a build parameter  → parameters are stored in PLAINTEXT
//                                        in the build metadata and shown in the UI
```

```bash
# ⭐⭐ PROVE masking works — the check most people skip
BUILD=$(curl -fsS -u admin:"$PASS" \
  "http://localhost:8080/job/shop-ci/job/ci-shop-api/lastBuild/consoleText")
echo "$BUILD" | grep -c 'ghp_'          # ✅ EXPECT: 0
# ⛔ if this is non-zero, your secret is in the build log, which is retained
#   for 200 builds, is readable by anyone with Job/Read, and is exported by
#   every backup you have ever taken.
```

---

## 8 · ⭐⭐ The two-folder layout

```
Jenkins
├── shop-ci/                              ← 🔨 CAN PUSH, ⛔ CANNOT DEPLOY
│   ├── credentials: ghcr-push            (folder-scoped)
│   ├── service account: jenkins-agent-ci (NO Kubernetes RBAC at all)
│   ├── ci-shop-ui          (multibranch)
│   ├── ci-shop-api         (multibranch)
│   ├── ci-checkout         (multibranch)
│   ├── ci-order-worker     (multibranch)
│   ├── ci-payment-mock     (multibranch)
│   └── ci-shop-mern        (multibranch)   ⭐ web + api + the mongod sidecar
│
├── shop-cd/                              ← 🚀 CAN DEPLOY, ⛔ CANNOT PUBLISH
│   ├── credentials: kubeconfig-shop-{dev,staging,production}, cosign-key
│   ├── service account: jenkins-agent-cd (patch/get deployments, ⛔ no delete)
│   ├── cd-shop-ui
│   ├── cd-shop-api
│   ├── cd-checkout
│   ├── cd-order-worker
│   ├── cd-payment-mock
│   ├── cd-shop-mern                       ⭐ backup → migrate → api → web
│   └── cd-estate                          ⭐ the polyglot release train
│
└── shop-platform/                        ← 🔧 the machinery, not the app
    ├── jenkins-shared-library            (the vars/*.groovy of §9)
    ├── backup-jenkins-home               (a nightly job, §10)
    └── plugin-audit                      (§4.2)
```

| Property | ⭐ Why it matters |
|---|---|
| **Disjoint credentials** | a job in `/shop-ci` cannot resolve `kubeconfig-shop-production`. Not a policy — a lookup failure |
| **Disjoint service accounts** | even if a job escaped its credential scope, the *pod* has no RBAC to deploy |
| ⭐ **Two independent compromises** | stealing the CI credential lets you publish a bad image — which check 2 (`cosign verify`) catches. Stealing the CD credential lets you deploy — but only images CI already signed |
| **A third folder for machinery** | the shared library and the backup job are not application pipelines and should not share their credential scope |

⛔ **The anti-pattern, and why it is so common:** one folder, one job with both a registry credential and a kubeconfig. It is simpler, it works, and it means the boundary between CI and CD is a **comment in a Jenkinsfile** that any developer with write access can delete — which is exactly the person who would, at 17:55 on a Friday.

---

## 9 · The shared library scaffold

```
jenkins-shared-library/
├── vars/                          ⭐ global variables — callable as functions
│   ├── buildAndPushImage.groovy   ← §6.2, the Kaniko wrapper
│   ├── deployDigest.groovy        ← ⭐⭐ the four-check contract (file 04)
│   ├── readBack.groovy            ← ⭐ the JSONPath name filter
│   ├── verifyProvenance.groovy    ← cosign verify, pinned identity
│   ├── stagingRanThisDigest.groovy← check 3
│   ├── smokeTest.groovy           ← per-service smoke (a business endpoint)
│   ├── notify.groovy              ← Slack/Teams on failure
│   └── auditRecord.groovy         ← ⭐ the JSONL audit trail (file 02)
├── src/com/shop/pipeline/         ⭐ classes, when you need real abstraction
│   └── Release.groovy
├── resources/                     ⭐ non-Groovy files, loaded with libraryResource
│   ├── pod-templates/mern.yaml
│   └── k8s/migration-job.yaml
└── README.md
```

```groovy
// vars/readBack.groovy — ⭐ the smallest and most important function here
def call(String ns, String svc, String container = null) {
  def c = container ?: svc
  // ⭐⭐ NAME FILTER, never [0]. A sidecar makes [0] the wrong container.
  def jp = "{.spec.template.spec.containers[?(@.name=='${c}')].image}"
  def out = sh(returnStdout: true,
               script: "kubectl -n ${ns} get deploy ${svc} -o jsonpath='${jp}'").trim()
  if (!out) error("⛔ readBack: no image for container '${c}' in ${ns}/${svc}")
  return out
}
```

```groovy
// ⭐ using it — ONE line in a Jenkinsfile, after @Library
@Library('shop-pipeline') _
pipeline {
  agent { label 'shop-cd' }
  stages {
    stage('read back') {
      steps {
        script {
          def now = readBack('shop-production', 'shop-api')
          if (now != env.IMAGE_REF) error("⛔ running ${now}, wanted ${env.IMAGE_REF}")
          echo "✅ CHECK 4 passed: ${now}"
        }
      }
    }
  }
}
```

| Why a library, not inline Groovy | ⭐ |
|---|---|
| **The script-security sandbox** | inline Groovy in a Jenkinsfile is sandboxed; calling most JDK/collection methods throws `RejectedAccessException`. ⭐ A **library is trusted and unrestricted** — so "move it to the library" is the *correct* fix, and "approve the signature" is the wrong one |
| **One implementation, forty jobs** | a bug in `readBack` is fixed once |
| **Versioned and reviewed** | `defaultVersion: main`, pinned per job when it matters |
| **Testable** | a library can have unit tests (`test/…groovy` with JenkinsPipelineUnit) |

---

## 10 · Backups, upgrades, and the ops you own

⭐⭐ **This is the section that GitHub Actions and Azure DevOps do not need — and it is the real cost of Jenkins.**

### 10.1 What must be backed up

```
/var/jenkins_home/
├── config.xml                ⭐ global config (mostly JCasC-generated)
├── credentials.xml           ⭐⭐ THE SECRETS — encrypted with a key from…
├── secrets/                  ⭐⭐ …here. ⛔ credentials.xml WITHOUT secrets/
│                                is useless, and secrets/ WITHOUT it is too.
│                                THEY MUST BE BACKED UP TOGETHER, ATOMICALLY.
├── jobs/<job>/config.xml     ⭐ job definitions (mostly job-dsl-generated)
├── users/                    who can log in
└── ⛔ builds/, workspace/, caches/  — large, regenerable, DO NOT back up
```

```yaml
# ⭐ a nightly Job that does it, in the platform folder
apiVersion: batch/v1
kind: CronJob
metadata: { name: jenkins-backup, namespace: jenkins }
spec:
  schedule: "17 2 * * *"            # ⭐ not on the hour — every cron job is
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 7         # ⭐ keep failures visible
  jobTemplate:
    spec:
      backoffLimit: 1
      template:
        spec:
          restartPolicy: OnFailure
          containers:
            - name: backup
              image: bitnami/kubectl:1.37
              command: ["/bin/sh","-c"]
              args:
                - |
                  set -euo pipefail
                  STAMP=$(date -u +%Y%m%dT%H%M%SZ)
                  # ⭐ quietDown first: a hot copy of credentials.xml while the
                  #   controller rewrites it can produce a torn file.
                  kubectl -n jenkins exec jenkins-0 -c jenkins -- \
                    curl -fsS -X POST -u "admin:$ADMIN_PASS" \
                    "http://localhost:8080/quietDown?block=all" || true
                  sleep 15
                  kubectl -n jenkins exec jenkins-0 -c jenkins -- \
                    tar czf - --exclude=jobs/*/builds --exclude=workspace \
                        /var/jenkins_home/secrets /var/jenkins_home/credentials.xml \
                        /var/jenkins_home/config.xml /var/jenkins_home/users \
                        /var/jenkins_home/jobs > "/tmp/jenkins-$STAMP.tar.gz"
                  kubectl -n jenkins cp "jenkins-0:/tmp/jenkins-$STAMP.tar.gz" \
                        "/backup/jenkins-$STAMP.tar.gz" -c jenkins
                  kubectl -n jenkins exec jenkins-0 -c jenkins -- \
                    curl -fsS -X POST -u "admin:$ADMIN_PASS" \
                    "http://localhost:8080/cancelQuietDown" || true
                  # ⭐⭐ AND PROVE IT: a backup you have never restored is a hypothesis
                  tar tzf "/backup/jenkins-$STAMP.tar.gz" | grep -q 'secrets/master.key'
                  tar tzf "/backup/jenkins-$STAMP.tar.gz" | grep -q 'credentials.xml'
                  echo "✅ backup verified: $(du -h /backup/jenkins-$STAMP.tar.gz)"
              volumeMounts: [{ name: backup, mountPath: /backup }]
          volumes:
            - name: backup
              persistentVolumeClaim: { claimName: jenkins-backup }
```

### 10.2 Upgrading — the discipline

```
⭐ JENKINS UPGRADE RULES
   1. LTS only. ⛔ Never weekly in production.
   2. Read the upgrade guide for EVERY version you are skipping — Jenkins
      does not publish "cumulative" notes, and 2.5xx → 2.5yy may cross a
      plugin-compatibility break.
   3. ⭐ UPGRADE PLUGINS FIRST, THEN THE CONTROLLER. A new controller with
      old plugins is the common failure; the reverse usually works.
   4. Test on a STAGING Jenkins restored from last night's backup.
      ⭐ If you do not have a staging Jenkins, your backup is untested, and
         an untested backup is a hypothesis (§10.1).
   5. Announce it. A controller restart kills running builds.
   6. Keep the previous image tag in git so the rollback is one line.
```

### 10.3 ⭐ The ops you own — the honest list

| Task | Frequency | ⛔ If you skip it |
|---|---|---|
| Back up `/var/jenkins_home` (secrets + credentials together) | nightly | a controller loss is a total rebuild |
| ⭐ **Restore-test the backup** | monthly | you have a hypothesis, not a backup |
| Plugin updates | monthly | a CVE with a public exploit. Jenkins is a favourite target |
| Plugin audit — remove unused | quarterly | 200 plugins, each attack surface |
| Controller image bump (LTS) | per LTS release | Java/plugin compatibility drift |
| Disk usage on the PVC | weekly | ⛔ a full `/var/jenkins_home` corrupts the config XML on write |
| Rotate the GHCR PAT / the CD kubeconfig | per policy | a leaked token that never expires |
| Review `approvedSignatures` | quarterly | each entry is a sandbox escape someone granted |
| Review global credentials | quarterly | ⛔ anything deploy-related that is GLOBAL |
| Check the agent pod count / `containerCapStr` | weekly | builds queue silently when the cap is hit |

⭐ **This table is the actual answer to "why not Jenkins?"** — not the Groovy, not the UI. It is that every row is a thing your team must do forever, and GitHub Actions and Azure DevOps do zero of them for you.

---

## 11 · ▶️ Verify it — the acceptance checks

```bash
# ── 1 · the controller runs NO builds ─────────────────────────────────
kubectl -n jenkins exec jenkins-0 -c jenkins -- \
  curl -fsS -u admin:"$PASS" 'http://localhost:8080/computer/api/json?depth=1' \
  | jq -r '.computer[] | select(.displayName=="Built-In Node") | .numExecutors'
# ✅ EXPECT: 0

# ── 2 · JCasC is the source of truth ──────────────────────────────────
kubectl -n jenkins get configmap jenkins-casc -o jsonpath='{.data.jenkins-casc\.yaml}' \
  | grep -c 'numExecutors: 0'                    # ✅ 1
curl -fsS -u admin:"$PASS" http://localhost:8080/configuration-as-code/view | head -5

# ── 3 · ⭐⭐ the credential asymmetry, at the Kubernetes level ─────────
kubectl auth can-i patch  deployments -n shop-production \
  --as=system:serviceaccount:jenkins:jenkins-agent-ci      # ✅ no
kubectl auth can-i patch  deployments -n shop-production \
  --as=system:serviceaccount:jenkins:jenkins-agent-cd      # ✅ yes
kubectl auth can-i delete deployments -n shop-production \
  --as=system:serviceaccount:jenkins:jenkins-agent-cd      # ✅ no
kubectl auth can-i '*' '*' --as=system:serviceaccount:jenkins:jenkins-controller
# ✅ EXPECT: no     ← ⛔ if this is yes, Jenkins is cluster-admin

# ── 4 · ⛔ no Docker socket anywhere ──────────────────────────────────
kubectl -n jenkins get configmap jenkins-casc -o yaml | grep -c 'docker.sock'   # ✅ 0
kubectl get pods -A -o json | jq -r '.items[].spec.volumes[]? |
  select(.hostPath?.path == "/var/run/docker.sock") | "⛔ docker.sock mounted"' | sort -u
# ✅ EXPECT: no output

# ── 5 · the two folders exist, with no credentials in common ──────────
for f in shop-ci shop-cd; do
  echo "── /$f"
  curl -fsS -u admin:"$PASS" "http://localhost:8080/job/$f/credentials/store/folder/api/json?depth=1" \
    | jq -r '.credentials[]?.id'
done
# ✅ EXPECT: /shop-ci → ghcr-push only · /shop-cd → kubeconfig-*, cosign-key only
# ⛔ if `kubeconfig-shop-production` appears under /shop-ci, §7 is broken

# ── 6 · a dynamic agent pod appears and DISAPPEARS ────────────────────
kubectl -n jenkins get pods -w &   # then trigger any build
# ✅ EXPECT: a pod named jenkins-<something> appears, runs, and is DELETED
kubectl -n jenkins get pods -l jenkins/label --no-headers | wc -l   # ✅ 0 when idle

# ── 7 · Kaniko produces a digest, not a parse ─────────────────────────
kubectl -n jenkins run kaniko-test --rm -i --restart=Never \
  --image=gcr.io/kaniko-project/executor:v1.23.2-debug -- \
  /kaniko/executor --context=dir:///workspace --dockerfile=/workspace/Dockerfile \
  --no-push --image-name-with-digest-file=/tmp/d.txt --verbosity=warn || true
# ⭐ the flag exists and writes a file — that is the whole mechanism

# ── 8 · ⭐ secrets are masked in the console log ──────────────────────
curl -fsS -u admin:"$PASS" \
  "http://localhost:8080/job/shop-ci/job/ci-shop-api/lastBuild/consoleText" | grep -c 'ghp_'
# ✅ EXPECT: 0    ⛔ non-zero means the secret is in 200 retained build logs

# ── 9 · the shared library resolves ───────────────────────────────────
curl -fsS -u admin:"$PASS" \
  'http://localhost:8080/descriptorByName/org.jenkinsci.plugins.workflow.libs.GlobalLibraries/config.xml' \
  | grep -o 'shop-pipeline' | head -1     # ✅ present

# ── 10 · the backup contains BOTH halves of the secret ────────────────
LATEST=$(ls -1t /backup/jenkins-*.tar.gz 2>/dev/null | head -1)
tar tzf "$LATEST" | grep -q 'secrets/master.key' && \
tar tzf "$LATEST" | grep -q 'credentials.xml' && echo "✅ backup is restorable"
# ⛔ credentials.xml WITHOUT secrets/ decrypts to nothing

# ── 11 · plugin count and pending updates ─────────────────────────────
curl -fsS -u admin:"$PASS" 'http://localhost:8080/pluginManager/api/json?depth=1' \
  | jq '{active: [.plugins[]|select(.active)]|length,
         updates: [.plugins[]|select(.hasUpdate)]|length}'
# ⭐ record both numbers. ⛔ over ~60 active is a maintenance problem.

# ── 12 · version anchor ───────────────────────────────────────────────
curl -fsS -u admin:"$PASS" http://localhost:8080/api/json | jq -r '.nodeName' 
kubectl -n jenkins get statefulset jenkins \
  -o jsonpath='{.spec.template.spec.containers[?(@.name=="jenkins")].image}'
# ✅ EXPECT: jenkins/jenkins:2.568.3-lts-jdk21   ⛔ never :latest
```

---

## 12 · Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| ⛔ The agent pod never becomes Ready | the container's `command` exits — no `sleep infinity` / `cat` + `ttyEnabled: true` | §5.2 |
| `JNLP agent connection failed` | `jenkinsUrl` or `jenkinsTunnel` wrong, or `location.url` unset | ⭐ set `unclassified.location.url` correctly (§3.2) |
| The pod is Pending forever | `containerCapStr` reached, or insufficient node capacity | raise the cap; check `kubectl describe pod` events |
| ⛔ OOMKilled agent | `resources.limits.memory` below what the toolchain needs | Maven 8Gi, Node 6Gi, Go 2Gi (§5.2) |
| OOMKilled **Kaniko** specifically | ⭐ compressed-layer caching in memory | `--compressed-caching=false` (§6.2) |
| `RejectedAccessException: … not permitted` | the script-security sandbox blocking inline Groovy | ⭐ **move it into the shared library** — ⛔ do not approve the signature |
| A credential resolves to nothing | ⛔ wrong scope, or the job is in the wrong folder | §7.2 — folder scope means a job in `/shop-ci` cannot see `/shop-cd`'s |
| The secret appears in the build log | interpolated into a `sh` string, or bound to `env` outside `withCredentials` | ⭐ §7.4 — and re-run check 8 |
| `docker.sock` permission denied | ⛔ you mounted it and it is still wrong — good. Keep it that way | use Kaniko (§6) |
| Testcontainers: "Could not find a valid Docker environment" | ⛔ a pod agent has no daemon | a **sidecar** database (§5.3), Testcontainers Cloud, or a VM agent |
| Mongoose: "Transaction numbers are only allowed on a replica set" | the mongod sidecar was started without `rs.initiate()` | ⭐ §5.3 — `--replSet rs0` **and** initiate it |
| Builds are slow and the cache never hits | `podRetention: never` + no registry cache | ⭐ Kaniko `--cache-repo` (§6.2), or a PVC-backed `.m2`/`.npm` |
| ⛔ A controller restart lost all the jobs | no PVC | `persistence.enabled: true` (§2.3) |
| JCasC changes do not apply | the ConfigMap was updated but the pod was not | `kubectl rollout restart statefulset/jenkins` |
| Webhooks fire but nothing builds | `location.url` wrong, or the GitHub plugin lacks a token | §3.2 |
| ⛔ Two CD runs per commit | both `build job:` **and** an upstream trigger are configured | pick one — `build job:` with `wait`/`propagate` (§ README point 3) |
| `lightweight checkout` fetches the whole repo | not set on the CD job's `cpsScm` | `lightweight(true)` (§3.4) |
| The disk fills and config XML corrupts | `builds/` retained forever | `logRotator { numToKeep(200) }` + a PVC size alert (§10.3) |

---

<a name="tasks--answers"></a>
## 13 · ⭐ TASKS — answers at the END

| # | Task |
|---|---|
| **T1** | Install Jenkins 2.568.3 on kind with a PVC, `numExecutors: 0`, and JCasC loaded from a ConfigMap |
| **T2** | Create the three service accounts and **prove** the credential asymmetry at the RBAC level |
| **T3** | Define four pod templates in JCasC, each with the right image, resources and service account |
| **T4** | Build an image with Kaniko and get the digest out **without parsing a log** |
| **T5** | Create `/shop-ci` and `/shop-cd` with folder-scoped credentials, and prove a CI job cannot see the kubeconfig |
| **T6** | Scaffold the shared library and implement `readBack` with the name filter |
| **T7** | Run a MERN build with a mongod **replica-set** sidecar and prove transactions work |
| **T8** | Set up the nightly backup CronJob and prove the archive is restorable |
| **T9** | Prove secrets are masked in every console log you have produced so far |
| **T10** | ⭐⭐ Your controller dies and the PVC is gone. Write the recovery runbook, then state the one thing that, if you skipped it, makes recovery impossible |

---

# ✅ ANSWERS

**T1.** §2. `kind create cluster --name cicd`, `kubectl create namespace jenkins`, then `helm install jenkins jenkinsci/jenkins -n jenkins -f jenkins-values.yaml --version 5.8.20` with a values file that pins ⭐ `controller.image.tag: "2.568.3-lts-jdk21"` (⛔ never `latest` — an unpinned controller changes behaviour mid-sprint), sets ⭐⭐ `controller.numExecutors: 0` and `jenkins.mode: EXCLUSIVE` so **no build ever runs on the controller**, sets `persistence.enabled: true` with `size: 20Gi`, points `serviceAccount.name` at the least-privilege SA from T2, lists `installPlugins:` explicitly, and sets `agent.defaultsProviderTemplate: ""` so every job must name a pod template. Load JCasC by creating `configmap/jenkins-casc` from `jenkins-casc.yaml` and referencing it under `controller.JCasC.configScripts`, then `kubectl rollout restart statefulset/jenkins`. **Verify (§11 checks 1, 2, 12):** the Built-In Node reports `numExecutors: 0`, `/configuration-as-code/view` renders, and the StatefulSet image is exactly `2.568.3-lts-jdk21`. ⭐ **Why `numExecutors: 0` is the single most important line:** a build running on the controller shares a JVM and a filesystem with `/var/jenkins_home` — including `credentials.xml` and `secrets/master.key`. Every other control in this file is weakened if that one is missing.

**T2.** §2.2. Three service accounts, not one: **`jenkins-controller`** bound to a Role allowing only `pods`, `pods/exec`, `pods/log` (create/delete/patch) and `secrets` read **in the `jenkins` namespace** — ⛔ no deployments, services, configmaps or namespaces, because the controller's job is to run builds, not to deploy. **`jenkins-agent-ci`** bound to **nothing at all** — a CI agent that can `kubectl get pods` in `shop-production` has already lost the asymmetry. **`jenkins-agent-cd`** bound to a `shop-deployer` Role in each `shop-*` namespace allowing `get/list/watch/patch/update` on `deployments`, `get/list/watch` on `pods` and `pods/log`, `create/delete/patch` on `batch/jobs` (for migrations), and ⛔ **no `delete` on deployments** — a CD pipeline that can delete a Deployment can delete production, and rollback is `set image` to a previous digest, never a delete. **Proving it (§11 check 3):** `kubectl auth can-i patch deployments -n shop-production --as=system:serviceaccount:jenkins:jenkins-agent-ci` → **no**; the same for `jenkins-agent-cd` → **yes**; `can-i delete deployments … --as=…jenkins-agent-cd` → **no**; and `kubectl auth can-i '*' '*' --as=…jenkins-controller` → **no**. ⭐ **That last one is the check people skip:** older versions of the Jenkins chart bind the controller to something close to `cluster-admin`, which means a compromised agent pod is a compromised cluster — and it passes every other test while doing it.

**T3.** §5.2. Four templates in JCasC under `jenkins.clouds[0].kubernetes.templates`: **`shop-java`** (`maven:3.9.11-eclipse-temurin-21`, requests 2 CPU/6Gi, limits 4 CPU/**8Gi**, a `postgres:17.7` **sidecar**, and a PVC-backed `/root/.m2`); **`shop-node`** (`node:24-alpine` with ⭐ `NODE_OPTIONS=--max-old-space-size=6144`, limits 6Gi, plus a `kaniko` container); **`shop-go`** (`golang:1.25-alpine`, limits only **2Gi** — Go needs little, and over-requesting wastes scheduler capacity); **`shop-cd`** (`bitnami/kubectl:1.37` + `cosign`, ⭐ **`serviceAccount: jenkins-agent-cd`**). Every template sets `nodeUsageMode: EXCLUSIVE`, `alwaysPullImage: true`, ⭐⭐ `podRetention: never`, and for long-running containers `command: sleep`/`args: infinity` or `command: cat` + `ttyEnabled: true`. **The four details that decide whether this works:** ⭐ **a different `serviceAccount` per template** — this is where the credential asymmetry becomes physically real, because the *pod*, not just the job, lacks deploy RBAC; ⭐ `ttyEnabled: true` with `command: cat` — without it the container exits immediately and the pod never becomes Ready, which presents as a mysterious agent timeout; ⭐ both `requests` **and** `limits` — limits without requests means the scheduler places the pod on a node that cannot hold it, and it is OOMKilled; and `alwaysPullImage: true`, because a cached agent image is an unpinned, unscanned dependency that you will not notice drifting.

**T4.** §6.2. A `kaniko` container in the pod template (`gcr.io/kaniko-project/executor:v1.23.2-debug`), then `/kaniko/executor --context=dir://$WORKSPACE/apps/shop-api --dockerfile=… --destination=repo:tag --cache=true --cache-repo=repo-cache --cache-ttl=168h --reproducible --snapshot-mode=redo --compressed-caching=false --image-name-with-digest-file=/workspace/digest.txt`. ⭐ **The digest comes out as a file**, then `readFile('digest.txt').trim()` and a regex assertion `==~ /.*@[a-z0-9]+:[0-9a-f]{64}/` — never a `grep` of the log, which breaks when Kaniko changes its output format. **Three flags worth explaining:** `--image-name-with-digest-file` is the mechanism that makes check 1 (is it a digest?) trivially enforceable; `--cache-repo` puts the layer cache in the **registry**, which is what makes an *ephemeral* pod still get warm builds — without it `podRetention: never` means every build is cold; and ⭐ `--compressed-caching=false` is **required when the pod's memory limit is small**, because Kaniko otherwise caches compressed layers *in memory* and is OOMKilled on a large image. That is the single most common Kaniko failure and the flag almost nobody knows. **And the thing you must not do (§6.1):** mount `/var/run/docker.sock` to "fix" the missing daemon. The socket has no authentication or authorisation model, so anyone who can talk to it can start a privileged container mounting the node's root filesystem — and your build runs `npm install`, which executes arbitrary postinstall scripts. ⭐ One line in a pod template equals cluster compromise.

**T5.** §8 and §7. Create both folders from JCasC's `jobs:` block (job-dsl `folder('shop-ci') { … }`), then register credentials **into each folder's own store**: `ghcr-push` (username + a PAT with `write:packages` and nothing else) under `/shop-ci`, and `kubeconfig-shop-{dev,staging,production}` (secret **file**) plus `cosign-key` under `/shop-cd`. ⛔ **Nothing deploy-related is ever GLOBAL** — a global kubeconfig is visible to every job on the controller, which makes "CI cannot deploy" false while every check still appears to pass. **Proving it (§11 check 5):** query each folder's credential store API and confirm the two lists are disjoint; then, more convincingly, add a temporary job in `/shop-ci` containing `withCredentials([file(credentialsId:'kubeconfig-shop-production', variable:'K')]) { sh 'echo ok' }` and confirm it **fails** with a credential-not-found error. ⭐ **That failure is the feature:** folder scope is not a policy someone can widen by mistake, it is a lookup fact — the job asks for an ID that does not exist in its scope and gets nothing. **Two supporting details:** the kubeconfig itself must be restricted to the CD service account, because a kubeconfig carrying cluster-admin defeats every folder scope you set; and the pod templates must use the matching `serviceAccount`, so that even a job that somehow escaped its credential scope still runs in a pod with no RBAC to deploy.

**T6.** §9. A repo `jenkins-shared-library` with `vars/`, `src/`, `resources/`, registered in JCasC under `unclassified.globalLibraries` as `shop-pipeline` with `defaultVersion: main` and a `modernSCM` GitHub retriever using a **read-only** credential. `vars/readBack.groovy`:
```groovy
def call(String ns, String svc, String container = null) {
  def c = container ?: svc
  def jp = "{.spec.template.spec.containers[?(@.name=='${c}')].image}"
  def out = sh(returnStdout: true,
               script: "kubectl -n ${ns} get deploy ${svc} -o jsonpath='${jp}'").trim()
  if (!out) error("⛔ readBack: no image for container '${c}' in ${ns}/${svc}")
  return out
}
```
⭐ **The name filter is the whole content of this task.** `{.spec.template.spec.containers[0].image}` returns whichever container the API server listed first — add an Istio, Vault or logging sidecar and index `0` becomes the **sidecar**, so check 4 verifies the wrong container and passes. `[?(@.name=='svc')]` is correct with zero, one or five containers. **Why a library rather than inline Groovy, and the reason is security not style:** inline Groovy in a Jenkinsfile runs in the script-security **sandbox**, so most JDK and collection calls throw `RejectedAccessException`; the two exits are approving signatures one by one — ⛔ an admin action per pipeline, and each approval is a permanent widening of what untrusted Jenkinsfiles can do — or moving the code into a **shared library, which is trusted and unrestricted**. So "put it in the library" is the correct fix and "approve the signature" is the wrong one. The secondary benefits are real but smaller: one implementation for forty jobs, versioned and reviewed, and unit-testable with JenkinsPipelineUnit. ⭐ Keep `security.scriptApproval.approvedSignatures: []` empty in JCasC and treat any entry appearing there as a code smell to fix, not a setting to maintain.

**T7.** §5.3 Option B. An inline (or better, a JCasC) pod template with a `node:24-alpine` container (`tty: true`, `NODE_OPTIONS=--max-old-space-size=6144`) and a `mongo:8.0` sidecar started with `args: ["--replSet","rs0","--bind_ip_all"]` plus a `mongosh --eval 'db.hello().ok'` readiness probe. Then a stage that **initiates the replica set**: `retry(5) { sh 'sleep 3; mongosh --quiet --eval \'rs.initiate()\' || true' }` followed by `sh 'sleep 5; mongosh --quiet --eval \'rs.status().ok\' | grep -q 1'`. Then `export MONGODB_URL="mongodb://localhost:27017/shop_test?replicaSet=rs0"`, `npm ci`, `npm run build -w @shop-mern/shared`, `npm run typecheck`, `npx vitest run --coverage`. **Proving transactions work:** in a test, `const s = await mongoose.startSession(); await s.withTransaction(async () => { … })` — against a standalone mongod this throws `MongoServerError: Transaction numbers are only allowed on a replica set member or mongos`; against the initiated sidecar it succeeds. ⭐ **The step everyone misses is `rs.initiate()`**: a mongod started with `--replSet rs0` is *not* a replica set until someone initiates it, and the failure is confusing because the connection succeeds and only transactions fail — or, worse, code guarded by `if (session)` silently skips the transaction and your tests pass while asserting nothing. **Why a sidecar at all:** a Kubernetes pod agent has **no Docker daemon**, so `@testcontainers/mongodb` cannot start one (§6 of shape B, and MERN §7.2) — the choices are a sidecar, Testcontainers Cloud, or a VM agent, and ⛔ never mounting the Docker socket. **Also grep for `mongodb-memory-server` and remove it**: it downloads a mongod binary at test time (non-hermetic), resolves to whatever version it likes (not your 8.0), and runs standalone (no transactions).

**T8.** §10.1. A `CronJob` at `"17 2 * * *"` (⭐ off the hour, because every cron job in the company runs at `0 3 * * *`) with `concurrencyPolicy: Forbid`, `failedJobsHistoryLimit: 7` so failures stay visible, that: enters quiet-down (`curl -X POST …/quietDown?block=all`) and sleeps 15 s so the controller is not rewriting `credentials.xml` mid-copy; `tar czf` of ⭐ **`secrets/` and `credentials.xml` together**, plus `config.xml`, `users/` and `jobs/*/config.xml`, while **excluding** `jobs/*/builds` and `workspace` (large and regenerable); copies the archive to a `jenkins-backup` PVC; cancels quiet-down; and then **proves the archive** with `tar tzf … | grep -q 'secrets/master.key'` and `grep -q 'credentials.xml'`. ⭐⭐ **The reason those two paths must be captured atomically:** `credentials.xml` is encrypted with a key that lives in `secrets/`. Backing up one without the other gives you an archive that restores perfectly and decrypts to **nothing** — a failure you discover during the incident, not before it. **The monthly restore test (§10.3):** restore last night's archive onto a throwaway Jenkins and confirm you can log in and that a job's credentials resolve. That is what converts a backup from a hypothesis into a backup, and it is also the prerequisite for T10's runbook and for testing upgrades (§10.2 rule 4).

**T9.** §7.4 and §11 check 8. For every build you have run, fetch the console text and grep for your secret's literal prefix: `curl -fsS -u admin:"$PASS" ".../lastBuild/consoleText" | grep -c 'ghp_'` — ⭐ **expect 0**. Repeat for the kubeconfig (grep a distinctive cluster hostname) and the cosign key. **The four ways a secret escapes masking, all of which pass a casual read of the Jenkinsfile:** binding it to `env.PASS = credentials('x')` at pipeline scope, which lands in the build's environment dump; interpolating it into a `sh` **argument** (`sh "docker login -u u -p ${PASS}"`), where it is visible in `ps` to every other process in the pod *and* the command line is logged before masking applies; echoing it yourself with string interpolation; and ⛔ passing it as a **build parameter**, because parameters are stored in plaintext in the build metadata and rendered in the UI. **The correct form is always** `withCredentials([...]) { sh '… "$REG_PASS" …' }` — single-quoted `sh` so the *shell* expands it, which is what lets Jenkins mask it. ⭐ **Why this check matters more in Jenkins than in the hosted tools:** build logs are retained (`logRotator numToKeep 200`), are readable by anyone with `Job/Read` — which in the JCasC above is the whole `shop-devs` group — and are included in every backup you have ever taken. A leaked secret in a Jenkins console log is therefore replicated into your backup archive, and rotating the secret does not remove it from either.

**T10.** ⭐⭐ **The runbook.** (1) **Confirm the loss** — `kubectl -n jenkins get pvc`; if the PVC is gone, `/var/jenkins_home` is gone, so *everything* in it is gone: global config, job definitions, users, build history, and — critically — `credentials.xml` **and** `secrets/master.key`. (2) **Stop the bleeding:** scale the StatefulSet to 0 so a fresh empty volume is not written over by a half-started controller. (3) **Restore the most recent verified backup** from T8's PVC (or off-cluster copy) onto the new volume — untar so that `secrets/` and `credentials.xml` land **together**, because one without the other decrypts to nothing. (4) **Re-apply JCasC and job-dsl** from git: `kubectl apply` the ConfigMap, `helm upgrade`, then let the seed job re-create the folders and jobs. ⭐ This is the payoff of §3: controller configuration and job *topology* were never in `$JENKINS_HOME` as hand-made state, so they rebuild from git in minutes. (5) **Rotate every credential anyway** — the PAT, the kubeconfigs, the cosign key. A restored `credentials.xml` works, but you cannot prove the old secrets were not exposed during the failure. (6) **Verify with §11's twelve checks**, especially check 3 (RBAC asymmetry) and check 8 (masking). (7) **Re-run one build per service** before declaring recovery.

⭐ **The one thing that makes recovery impossible if you skipped it: a backup of `secrets/` taken *together with* `credentials.xml`, and a restore test that proved it works.** Everything else is recoverable from git — JCasC is the controller config, job-dsl is the job topology, Jenkinsfiles are the behaviour, and images are in the registry. But Jenkins' credential encryption key exists **only** in `/var/jenkins_home/secrets/master.key`, it is not derivable, not in git, and not in the registry. Without it, `credentials.xml` is ciphertext: every job that needs a secret fails, and the fix is to re-enter all of them by hand — which requires knowing what they were, which requires a rotation procedure you probably also never wrote. **And the second-order point:** an untested backup is a hypothesis (§10.1, §10.3). The most common real-world version of this incident is not "we had no backup" — it is "we had a nightly job that had been failing for six weeks and nobody looked, because `failedJobsHistoryLimit` was set to 1 and the alert went to an inbox". That is why T8 keeps seven failed jobs visible and why the monthly restore test is a scheduled task rather than a good intention.

**The meta-lesson for this file:** ⭐ Jenkins has no built-in concept of "an environment you may not deploy to". GitHub Actions has environments; Azure DevOps has Environments + Approvals + Checks. Jenkins has **folders and service accounts** — and if you use them as a boundary rather than as an organising convenience, "CI cannot deploy" becomes a *fact about the system* (a credential lookup that fails, an RBAC check that returns no) instead of a *comment in a Jenkinsfile* that any developer with write access can delete at 17:55 on a Friday. Files `01`–`06` are all variations on making that fact hold.

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish_Kumar_Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn: https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260
🔗 GitHub: https://github.com/3558Bhk

*Jenkins has no built-in idea of an environment you may not deploy to. So you build one out of folders and service accounts — and then it is a fact, not a comment.*

</div>
