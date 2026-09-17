# 🛠️ kubectl — Complete Reference

> **One file. Everything.** Syntax, configuration, every resource type, every output format, every flag that matters, debugging playbooks, production scenarios, and interview answers.
>
> **Written for:** Kubernetes **v1.31 – v1.37** · kubectl v1.33+ · DevOps / SRE / Platform Engineering / 3+ YOE interviews.
>
> **How to use it:** read §1–§8 once, then use the rest as a lookup. Every section is self-contained.

---

## Table of Contents

| # | Section | What's in it |
|---|---|---|
| [1](#1-anatomy-of-a-kubectl-command) | Anatomy of a kubectl command | The grammar every command follows |
| [2](#2-installation--version-skew) | Installation & version skew | Installing, the ±1 rule, why it matters |
| [3](#3-kubeconfig-contexts--clusters) | kubeconfig, contexts & clusters | Multi-cluster life, kubectx/kubens |
| [4](#4-cluster-discovery--api-resources) | Cluster discovery & API resources | `api-resources`, `explain`, `api-versions` |
| [5](#5-get-and-describe) | `get` and `describe` | The two commands you'll use 90% of the time |
| [6](#6-output-formats) | Output formats | yaml, json, wide, custom-columns, jsonpath, go-template, kyaml |
| [7](#7-filtering-labels--field-selectors) | Filtering: labels & field selectors | `-l`, `--field-selector`, and their hard limits |
| [8](#8-creating--modifying-resources) | Creating & modifying resources | imperative, `apply`, `patch`, `edit`, `replace` |
| [9](#9-deleting-resources) | Deleting resources | grace periods, finalizers, cascade modes, stuck namespaces |
| [10](#10-logs) | Logs | `--previous`, `-f`, multi-container, stern |
| [11](#11-exec-attach-cp--port-forward) | exec, attach, cp & port-forward | Getting inside, and out |
| [12](#12-debugging-tools) | Debugging tools | `debug`, ephemeral containers, events, node-shell |
| [13](#13-workloads) | Workloads | Pod, Deployment, StatefulSet, DaemonSet, Job, CronJob, ReplicaSet |
| [14](#14-services--networking) | Services & networking | Service types, EndpointSlices, Ingress, Gateway API, DNS, NetworkPolicy |
| [15](#15-configuration-configmaps--secrets) | Configuration: ConfigMaps & Secrets | Creating, mounting, rotating, the `_FILE` convention |
| [16](#16-storage) | Storage | PV, PVC, StorageClass, expansion, snapshots, CSI |
| [17](#17-scheduling) | Scheduling | nodeSelector, affinity, taints/tolerations, topology spread, priority |
| [18](#18-autoscaling) | Autoscaling | HPA, VPA, KEDA, cluster autoscaler |
| [19](#19-rbac--authentication) | RBAC & authentication | Roles, bindings, impersonation, `auth can-i` |
| [20](#20-namespaces-quotas--limitranges) | Namespaces, quotas & LimitRanges | Multi-tenancy |
| [21](#21-security-contexts--pod-security) | Security contexts & Pod Security | Hardening, PSA labels, what actually blocks a Pod |
| [22](#22-admission-control--policy-engines) | Admission control & policy engines | Webhooks, Kyverno, Gatekeeper |
| [23](#23-crds--operators) | CRDs & operators | Custom resources, conversion, aggregation |
| [24](#24-monitoring--resource-usage) | Monitoring & resource usage | `top`, metrics-server, the metrics API |
| [25](#25-cluster-maintenance) | Cluster maintenance | cordon, drain, uncordon, upgrades, certificates |
| [26](#26-node-management) | Node management | Labels, taints, conditions, capacity vs allocatable |
| [27](#27-the-troubleshooting-playbook) | **The troubleshooting playbook** | Every failure mode, symptom → cause → fix |
| [28](#28-events--the-api-server) | Events & the API server | Reading events, `--raw`, proxying |
| [29](#29-scripting--automation) | Scripting & automation | jsonpath recipes, jq, exit codes, idempotent bash |
| [30](#30-shell-completion-aliases--productivity) | Shell completion, aliases & productivity | Making kubectl fast to type |
| [31](#31-plugins--the-krew-ecosystem) | Plugins & the krew ecosystem | krew, and the 20 plugins worth installing |
| [32](#32-tools-that-replace-kubectl) | Tools that replace kubectl | k9s, Lens, kubectx, stern, kubectl-tree, krew list |
| [33](#33-production--sre-scenarios) | **Production & SRE scenarios** | 20 real incidents, start to finish |
| [34](#34-interview-questions--answers) | **Interview questions & answers** | 60 questions, with the answers interviewers want |
| [35](#35-api-versions-reference) | API versions reference | What's stable, beta, alpha in v1.37 |
| [36](#36-common-errors--what-they-mean) | Common errors & what they mean | 60 error strings, decoded |
| [37](#37-global-flags-reference) | Global flags reference | Every flag, what it does |
| [38](#38-command-index) | Command index | Every kubectl subcommand, one line each |
| [39](#39-cheat-cards) | Cheat cards | Printable one-pagers |
| [40](#40-the-ten-minute-daily-checklist) | The ten-minute daily checklist | What to look at every morning |

---

<a name="1-anatomy-of-a-kubectl-command"></a>
## 1. Anatomy of a kubectl command

Every kubectl command is the same shape:

```
kubectl <verb> <resource-type>/<name> [flags]

  │        │              │              │
  │        │              │              └── how (output format, namespace, selectors)
  │        │              └── what (the object)
  │        └── the action (an HTTP verb against the API server)
  └── the client
```

### 1.1 The verbs map to HTTP

| kubectl verb | HTTP method | Endpoint |
|---|---|---|
| `get` | GET | `/api/v1/namespaces/{ns}/pods/{name}` |
| `create` | POST | `/api/v1/namespaces/{ns}/pods` |
| `apply` | PATCH (server-side) or PUT | same as get |
| `patch` | PATCH | same as get |
| `edit` | GET then PUT | same as get |
| `replace` | PUT | same as get |
| `delete` | DELETE | same as get |
| `logs` | GET (streaming) | `/api/v1/namespaces/{ns}/pods/{name}/log` |
| `exec` | POST (SPDY/WebSocket upgrade) | `/api/v1/namespaces/{ns}/pods/{name}/exec` |
| `port-forward` | POST (upgrade) | `/api/v1/namespaces/{ns}/pods/{name}/portforward` |

**Everything kubectl does, you can do with curl.** That's the key to understanding it — and to debugging it:

```bash
# what kubectl actually sends
kubectl get pods -v=8 2>&1 | grep -E 'GET|Response' | head -5
# GET https://127.0.0.1:6443/api/v1/namespaces/default/pods?limit=500 200 OK in 42 milliseconds

# do it yourself
TOKEN=$(kubectl create token default -n kube-system --duration=1h)
curl -sk -H "Authorization: Bearer $TOKEN" \
  https://$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' | sed 's|https://||')/api/v1/namespaces/default/pods \
  | jq '.items | length'

# or through the kubectl proxy (no auth needed)
kubectl proxy --port=8001 &
curl -s localhost:8001/api/v1/namespaces/default/pods | jq '.items[].metadata.name'
```

### 1.2 Resource naming — six forms, all equivalent

```bash
kubectl get pods nginx                     # type + name
kubectl get pod nginx                      # singular
kubectl get pod/nginx                      # slash form ⭐ best for scripting
kubectl get po nginx                       # short name
kubectl get pods.apps nginx                # fully qualified (group-qualified)
kubectl get -f pod.yaml                    # from a file
```

**Why the slash form matters:** `pod/nginx` is unambiguous when you pass it to another command:

```bash
kubectl describe $(kubectl get pods -l app=web -o name | head -1)
# pod/web-7d4f8c9b6-abcde                    ← -o name returns the slash form
kubectl logs pod/web-7d4f8c9b6-abcde
kubectl delete pod/web-7d4f8c9b6-abcde
```

### 1.3 Group-qualified names — when you need them

Two resource types can share a name across API groups:

```bash
kubectl api-resources | grep -w deployment
# deployments   deploy   apps/v1   true   Deployment

kubectl api-resources | grep -w cronjob
# cronjobs      cj       batch/v1  true   CronJob
```

If two CRDs collide (`widgets.example.com` and `widgets.other.com`):

```bash
kubectl get widgets                    # ambiguous — errors or picks one
kubectl get widgets.example.com        # ⭐ explicit
kubectl get widgets.v1.example.com     # ⭐ explicit, version too
```

### 1.4 The namespace flag

```bash
kubectl get pods                           # the current context's namespace (usually "default")
kubectl get pods -n kube-system            # a specific namespace
kubectl get pods -A                        # ⭐ ALL namespaces (--all-namespaces)
kubectl get pods --all-namespaces          # the long form
kubectl config set-context --current --namespace=shop   # ⭐ change the default permanently
kubens shop                                # the short way (kubectx package)
```

⚠️ **Cluster-scoped resources ignore `-n`:**

```bash
kubectl get nodes -n kube-system      # works, but -n is meaningless
kubectl get pv -n shop                # same
kubectl get clusterrole -n shop       # same
kubectl api-resources --namespaced=false     # ← the full list of cluster-scoped types
```

### 1.5 Verbosity — the most underused debugging tool

```bash
kubectl get pods -v=0     # default, nothing extra
kubectl get pods -v=6     # the HTTP request and response code
kubectl get pods -v=7     # + request headers
kubectl get pods -v=8     # + request AND response body ⭐ the useful one
kubectl get pods -v=9     # + the body, not truncated
kubectl get pods -v=10    # everything, including the client's own internals
```

```bash
# what does kubectl ACTUALLY send?
kubectl apply -f deploy.yaml -v=8 2>&1 | head -40
# POST https://127.0.0.1:6443/apis/apps/v1/namespaces/shop/deployments?fieldManager=kubectl-client-side-apply 409 Conflict
# PATCH https://127.0.0.1:6443/apis/apps/v1/namespaces/shop/deployments/shop-api?fieldManager=kubectl-client-side-apply 200 OK
# Request Headers:
#     Accept: application/json
#     Content-Type: application/strategic-merge-patch+json
# Request Body: {"metadata":{"annotations":{"kubectl.kubernetes.io/last-applied-configuration":"…"}},"spec":{…}}
```

That output tells you:
- the exact API path (so you know the group/version)
- that `apply` tried POST, got 409 (already exists), then PATCHed
- **whether it's client-side or server-side apply** (look at `fieldManager`)
- the exact body sent (so you can see what kubectl computed)

**Use `-v=8` whenever kubectl does something you don't expect.** It's never wrong.

### 1.6 Getting help

```bash
kubectl --help                        # the command list
kubectl get --help                    # flags for one command
kubectl explain deployment            # ⭐ the FIELDS of a resource, from the live cluster
kubectl explain deployment.spec.strategy
kubectl explain --recursive pod.spec.containers    # everything, nested
kubectl api-resources                 # every resource type in this cluster
kubectl api-versions                  # every API group/version
kubectl cluster-info                  # is the cluster reachable?
kubectl version                       # client + server versions
```

`kubectl explain` reads **your cluster's** OpenAPI schema, so it shows the CRDs you've installed too:

```bash
kubectl explain clusterissuer         # cert-manager's CRD
kubectl explain servicemonitor.spec.endpoints
kubectl explain --recursive scaledobject.spec | head -40
```

---

<a name="2-installation-and-version-skew"></a>
## 2. Installation & version skew

### 2.1 Install

```bash
# Linux (the official way)
curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl && sudo mv kubectl /usr/local/bin/

# pinned to your cluster version ±1 (do this in production)
curl -LO "https://dl.k8s.io/release/v1.37.0/bin/linux/amd64/kubectl"

# macOS
brew install kubectl
# or: brew install kubernetes-cli

# verify
kubectl version --client
# Client Version: v1.37.0
# Kustomize Version: v5.6.0

kubectl version
# Client Version: v1.37.0
# Server Version: v1.36.3         ← ⭐ skew check
```

### 2.2 The skew policy — and why it bites

**kubectl must be within ±1 minor version of the API server.** That's an official Kubernetes support rule, not a suggestion.

| kubectl | API server | Supported? | What breaks |
|---|---|---|---|
| 1.37 | 1.36 | ✅ | — |
| 1.37 | 1.37 | ✅ | — |
| 1.37 | 1.35 | ⚠️ **No** | New flags unknown to the server; removed APIs |
| 1.35 | 1.37 | ⚠️ **No** | Server returns fields kubectl can't render; `error: unknown object type` |
| 1.33 | 1.37 | ⛔ | Frequent failures |

**Real symptoms of a skew problem:**

```bash
kubectl get pods
# error: unknown object type *v1.PodList in apps/v1, kind=Deployment

kubectl apply -f x.yaml
# error: failed to create patch: converting apps/v1.Deployment to v1.Deployment:
#   unknown field "spec.template.spec.os"

kubectl describe pod nginx
# (a section is silently missing)
```

**Check it before blaming anything else:**

```bash
kubectl version -o json | jq '{client: .clientVersion.gitVersion, server: .serverVersion.gitVersion}'
# {"client": "v1.37.0", "server": "v1.34.2"}     ← ⛔ three versions apart
```

### 2.3 Other version rules

| Component | Skew vs API server |
|---|---|
| **kubelet** | −2 to 0 (kubelet may be up to 2 minors OLDER, never newer) |
| **kube-proxy** | same as kubelet |
| **kube-controller-manager / scheduler** | −1 to 0 |
| **kubectl** | ±1 |
| **Client libraries (client-go)** | ±1 |
| **CRI (containerd/CRI-O)** | Follows the CRI version |

**The upgrade order is therefore always:** control plane first, then kubelets, then kubectl.

```bash
# a real cluster mid-upgrade
kubectl get nodes -o custom-columns='NAME:.metadata.name,VERSION:.status.nodeInfo.kubeletVersion'
# learn-control-plane   v1.37.0
# learn-worker          v1.36.3      ← kubelet one behind: FINE
# learn-worker2         v1.35.1      ← two behind: the limit, upgrade soon
```

### 2.4 Kubernetes release cadence (as of 2026)

| Version | Codename | Released | Notes |
|---|---|---|---|
| v1.34 | — | Aug 2025 | |
| v1.35 | — | Dec 2025 | |
| v1.36 | — | Apr 2026 | |
| **v1.37** | **Garhwal** | **26 Aug 2026** | KYAML output, `metrics.k8s.io` GA, DRA GA features, Pod certificates GA |

Three minor versions are supported at a time (roughly 14 months of patch releases per minor). Managed services lag: EKS typically supports the latest three plus extended support for older ones.

### 2.5 The tools you should install alongside kubectl

```bash
# krew — the kubectl plugin manager
( set -x; cd "$(mktemp -d)" && \
  OS="$(uname | tr '[:upper:]' '[:lower:]')" && ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/aarch64/arm64/')" && \
  KREW="krew-${OS}_${ARCH}" && \
  curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/${KREW}.tar.gz" && \
  tar zxvf "${KREW}.tar.gz" && "./${KREW}" install krew )
echo 'export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"' >> ~/.bashrc && source ~/.bashrc
kubectl krew version

# the essentials
kubectl krew install ctx ns tree lineage stern neat resource-capacity rbac-view \
                       df-pv explore view-secret tail who-can access-matrix \
                       deprecations get-all node-shell evict-pod cost nsdep

# the standalone tools (not plugins)
brew install kubectx kubens k9s stern jq yq go-task helm kustomize
# kubectx  → switch contexts
# kubens   → switch namespaces
# k9s      → the terminal UI
# stern    → multi-pod log tailing
```

---

<a name="3-kubeconfig-contexts-and-clusters"></a>
## 3. kubeconfig, contexts & clusters

### 3.1 The file

```bash
echo $KUBECONFIG
# (empty → ~/.kube/config)

ls -la ~/.kube/
# config            ← the main one
# config-prod
# config-staging

cat ~/.kube/config
```

```yaml
apiVersion: v1
kind: Config
preferences: {}

# ── WHERE the clusters are ──
clusters:
  - name: learn
    cluster:
      server: https://127.0.0.1:6443
      certificate-authority-data: LS0tLS1CRUdJTi…     # base64 CA cert
  - name: prod-eks
    cluster:
      server: https://ABC123.gr7.ap-south-1.eks.amazonaws.com
      certificate-authority-data: LS0tLS1CRUdJTi…

# ── WHO you are ──
users:
  - name: learn-admin
    user:
      client-certificate-data: LS0tLS1CRUdJTi…
      client-key-data: LS0tLS1CRUdJTi…
  - name: prod-sso
    user:
      exec:                                            # ⭐ an external credential plugin
        apiVersion: client.authentication.k8s.io/v1beta1
        command: aws
        args: [eks, get-token, --cluster-name, prod, --region, ap-south-1]
        env: [{name: AWS_PROFILE, value: prod}]
        installHint: "Install the AWS CLI: https://aws.amazon.com/cli/"

# ── the PAIRING of a cluster + a user + a namespace ──
contexts:
  - name: learn
    context: {cluster: learn, user: learn-admin, namespace: default}
  - name: prod
    context: {cluster: prod-eks, user: prod-sso, namespace: shop-prod}
  - name: staging
    context: {cluster: staging-eks, user: prod-sso, namespace: shop-staging}

current-context: learn
```

**Three lists, and a context is a triple:**

```
cluster  ─┐
           ├──► context ──► current-context
user     ─┘
           + namespace (optional)
```

### 3.2 Reading and switching

```bash
kubectl config view                            # the merged view (all KUBECONFIG files)
kubectl config view --minify                   # ⭐ only the CURRENT context
kubectl config view --minify --flatten         # ⭐ inline the cert data → portable
kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}'; echo
kubectl config view --raw                      # with secrets un-redacted

kubectl config get-contexts
# CURRENT   NAME       CLUSTER     AUTHINFO      NAMESPACE
# *         learn      learn       learn-admin
#           prod       prod-eks    prod-sso      shop-prod
#           staging    staging-eks prod-sso      shop-staging

kubectl config current-context
# learn

kubectl config use-context prod                # ⭐ switch
kubectl config use-context -                   # switch back to the previous one

kubectl config set-context --current --namespace=shop-prod    # change the default namespace
kubectl config set-context prod --namespace=monitoring        # for a named context
kubens shop-prod                                              # the short way
kubens -                                                      # back to the previous

kubectl config get-clusters
kubectl config get-users

# modify the file
kubectl config set-cluster dev --server=https://1.2.3.4:6443 --insecure-skip-tls-verify
kubectl config set-credentials dev-user --token=eyJhbGci…
kubectl config set-context dev --cluster=dev --user=dev-user --namespace=default
kubectl config delete-context old
kubectl config delete-cluster old
kubectl config delete-user old
kubectl config unset contexts.dev.namespace
kubectl config rename-context learn kind-learn
```

### 3.3 Multiple kubeconfig files

```bash
# ⭐ merge them at runtime — the cleanest multi-cluster setup
export KUBECONFIG=~/.kube/config:~/.kube/config-prod:~/.kube/config-staging
kubectl config get-contexts        # all three appear

# merge them into one file permanently
KUBECONFIG=~/.kube/config:~/.kube/config-prod kubectl config view --flatten > ~/.kube/merged
mv ~/.kube/merged ~/.kube/config

# per-command override, no env change
kubectl --kubeconfig ~/.kube/config-prod get pods
KUBECONFIG=~/.kube/config-prod kubectl get pods
```

**Precedence:** `--kubeconfig` flag > `$KUBECONFIG` > `~/.kube/config`.

⚠️ **`KUBECONFIG` is colon-separated on Linux/macOS and semicolon-separated on Windows.**

### 3.4 Credential plugins — how managed Kubernetes really works

You almost never have a client certificate in production. Instead, kubectl runs a command to get a short-lived token:

```yaml
users:
  - name: prod-sso
    user:
      exec:
        apiVersion: client.authentication.k8s.io/v1beta1
        command: aws
        args: [eks, get-token, --cluster-name, prod, --region, ap-south-1]
        interactiveMode: IfAvailable        # allows browser-based SSO
```

| Cloud | Command | Tool |
|---|---|---|
| AWS EKS | `aws eks get-token --cluster-name X` | awscli v2 |
| GCP GKE | `gke-gcloud-auth-plugin` | gcloud + the plugin |
| Azure AKS | `kubelogin` | kubelogin |
| OIDC (Dex/Keycloak) | `oidc-login` / `kubelogin` | krew plugin |

```bash
# generate the config for a managed cluster
aws eks update-kubeconfig --name prod --region ap-south-1
gcloud container clusters get-credentials prod --region us-central1 --project my-project
az aks get-credentials --resource-group rg --name prod

# force re-auth when the token expires
aws eks get-token --cluster-name prod | jq .
kubectl get pods -v=8 2>&1 | grep -i 'exec\|token\|401'
```

**When you get `Unauthorized` or `error: You must be logged in`:**

```bash
kubectl config view --minify | grep -A5 exec     # is the plugin configured?
aws sts get-caller-identity                      # are the cloud creds valid?
kubectl get --raw /healthz                       # is the API server even reachable?
rm -rf ~/.kube/cache/exec                        # clear the cached (expired) token
```

### 3.5 Safety — never operate on the wrong cluster

```bash
# 1. kube-ps1 — shows the context in your prompt
git clone https://github.com/jonmosco/kube-ps1 && echo 'source ~/kube-ps1/kube-ps1.sh' >> ~/.bashrc
echo 'PS1="[\u@\h \W $(kube_ps1)]\$ "' >> ~/.bashrc
# [user@host ~ (learn:default)]$        ← you always know where you are

# 2. colour-code by environment
kubectl config set-context prod --cluster=prod-eks --user=prod-sso
cat >> ~/.kube/config <<'EOF'
# (in the context) extensions:
#   - name: client.authentication.k8s.io/exec
#     extension:
#       client.authentication.k8s.io/exec:
#         interactiveMode: IfAvailable
EOF
# simpler: use kubectx's colour support, or a wrapper:
kprod() { KUBECONFIG=~/.kube/config-prod kubectl "$@"; }

# 3. ⭐ the destructive-command guard
kubectl() {
  local ctx=$(command kubectl config current-context 2>/dev/null)
  case "$ctx" in
    *prod*|*production*)
      case "$*" in
        *delete*|*drain*|*scale*|*patch*|*edit*|*apply*)
          printf '\033[1;31m⚠️  You are about to run on PRODUCTION (%s):\033[0m\n' "$ctx"
          printf '    kubectl %s\n' "$*"
          read -rp "Type 'yes' to proceed: " ans
          [ "$ans" = "yes" ] || { echo "aborted"; return 1; }
          ;;
      esac
      ;;
  esac
  command kubectl "$@"
}

# 4. a canary check in scripts
[[ "$(kubectl config current-context)" == *"prod"* ]] && { echo "refusing to run against prod"; exit 1; }

# 5. RBAC — the real answer. Give yourself read-only in prod.
kubectl auth can-i delete pods -n shop-prod
# no       ← ✅ you literally cannot
```

### 3.6 kubectx / kubens

```bash
kubectx                       # list, highlight the current
kubectx prod                  # switch
kubectx -                     # previous (like `cd -`)
kubectx prod=production       # rename a context
kubectx -d staging            # delete
kubens                        # list namespaces
kubens shop-prod              # switch
kubens -                      # previous

# fuzzy search with fzf (install fzf first)
kubectx                       # ← with fzf, this is interactive
```

```bash
# ~/.bashrc — make it faster
alias k='kubectl'
alias kx='kubectx'
alias kn='kubens'
complete -F __start_kubectl k
```

---

<a name="4-cluster-discovery-and-api-resources"></a>
## 4. Cluster discovery & API resources

### 4.1 `api-resources` — what exists in this cluster

```bash
kubectl api-resources
# NAME                SHORTNAMES   APIVERSION                NAMESPACED   KIND
# bindings                         v1                        true         Binding
# configmaps          cm           v1                        true         ConfigMap
# endpoints           ep           v1                        true         Endpoints
# events              ev           v1                        true         Event
# namespaces          ns           v1                        false        Namespace
# nodes               no           v1                        false        Node
# persistentvolumeclaims  pvc      v1                        true         PersistentVolumeClaim
# pods                po           v1                        true         Pod
# secrets                          v1                        true         Secret
# services            svc          v1                        true         Service
# daemonsets          ds           apps/v1                   true         DaemonSet
# deployments         deploy       apps/v1                   true         Deployment
# replicasets         rs           apps/v1                   true         ReplicaSet
# statefulsets        sts          apps/v1                   true         StatefulSet
# cronjobs            cj           batch/v1                  true         CronJob
# jobs                             batch/v1                  true         Job
# ingressclasses                   networking.k8s.io/v1      false        IngressClass
# ingresses           ing          networking.k8s.io/v1      true         Ingress
# networkpolicies     netpol       networking.k8s.io/v1      true         NetworkPolicy
# horizontalpodautoscalers  hpa    autoscaling/v2            true         HorizontalPodAutoscaler
# poddisruptionbudgets      pdb    policy/v1                 true         PodDisruptionBudget
# clusterroles                     rbac.authorization.k8s.io/v1  false    ClusterRole
# …and every CRD you've installed
```

```bash
kubectl api-resources --namespaced=true        # only namespaced
kubectl api-resources --namespaced=false       # ⭐ only cluster-scoped (pv, nodes, ns, clusterroles, CRDs, SCs…)
kubectl api-resources --api-group=apps
kubectl api-resources --api-group=monitoring.coreos.com
kubectl api-resources --verbs=list,get         # ⭐ only the ones you can actually read
kubectl api-resources -o wide                  # + the verbs each supports
kubectl api-resources --sort-by=name | grep -i secret
```

**The verbs column is what most people miss:**

```bash
kubectl api-resources -o wide | grep -E '^NAME|pods'
# NAME   SHORTNAMES  APIVERSION  NAMESPACED  KIND  VERBS
# pods   po          v1          true        Pod   [create delete get list patch update watch]
# pods/exec           v1          true        PodExecOptions   [create get]     ← ⭐ no list/delete
```

If a resource has no `list` verb, `kubectl get <type>` fails. Common with sub-resources (`pods/exec`, `pods/attach`, `pods/log`).

### 4.2 `explain` — the schema, from your live cluster

```bash
kubectl explain pod
# KIND:       Pod
# VERSION:    v1
# DESCRIPTION:
#     Pod is a collection of containers that can run on a host…
# FIELDS:
#   apiVersion	<string>
#   kind	<string>
#   metadata	<ObjectMeta>
#   spec	<PodSpec>
#   status	<PodStatus>

kubectl explain pod.spec.containers                    # drill down
kubectl explain deployment.spec.strategy.rollingUpdate
kubectl explain --recursive pod.spec | less            # ⭐ the whole tree
kubectl explain --recursive pod.spec.containers.resources
kubectl explain pod.spec --recursive | grep -A3 affinity
kubectl explain hpa.spec.metrics --recursive

# ⭐ CRDs too — this is how you learn an operator's API
kubectl explain clusterissuer.spec
kubectl explain --recursive servicemonitor.spec
kubectl explain application.spec.syncPolicy
kubectl explain scaledobject.spec.triggers --recursive

# ask the API server for a specific version
kubectl explain deployment --api-version=apps/v1
kubectl explain pod.spec.os --api-version=v1             # a v1.25+ field
```

`explain` reads `/openapi/v3` from the API server, so it always matches **your** cluster — including its CRDs. **This is the fastest way to learn any Kubernetes resource without leaving the terminal.**

### 4.3 `api-versions` and discovery

```bash
kubectl api-versions | sort
# admissionregistration.k8s.io/v1
# apiextensions.k8s.io/v1
# apiregistration.k8s.io/v1
# apps/v1
# autoscaling/v2
# batch/v1
# certificates.k8s.io/v1
# coordination.k8s.io/v1
# discovery.k8s.io/v1
# events.k8s.io/v1
# flowcontrol.apiserver.k8s.io/v1
# metrics.k8s.io/v1beta1              ← ⭐ GA as an API in v1.37, still /v1beta1
# networking.k8s.io/v1
# node.k8s.io/v1
# policy/v1
# rbac.authorization.k8s.io/v1
# scheduling.k8s.io/v1
# storage.k8s.io/v1
# v1
# gateway.networking.k8s.io/v1        ← if Gateway API is installed
# monitoring.coreos.com/v1            ← if kube-prometheus-stack is installed

# raw discovery
kubectl get --raw /api
kubectl get --raw /apis
kubectl get --raw /apis/apps/v1 | jq '.resources[].name'
kubectl get --raw /openapi/v3 | jq '.paths | keys'
kubectl get --raw /healthz
kubectl get --raw /readyz?verbose
kubectl get --raw /livez?verbose
kubectl get --raw /metrics | head -30          # ⭐ the API server's own Prometheus metrics
kubectl get --raw /version | jq .
```

**`/healthz` vs `/readyz` vs `/livez`:**

| Endpoint | Means | Used by |
|---|---|---|
| `/healthz` | Deprecated alias for `/livez` | Old tooling |
| `/livez` | "Don't restart me" | The load balancer in front of a HA control plane |
| `/readyz` | "Send me traffic" | The load balancer; **fails during startup and shutdown** |

```bash
kubectl get --raw '/readyz?verbose' | grep -v 'ok$'
# [+]poststarthook/apiservice-openapi-controller failed: reason withheld
# ⛔ the API server is NOT ready
```

### 4.4 What's deprecated or removed in your version

```bash
kubectl krew install deprecations
kubectl deprecations --k8s-version v1.38 ./k8s/
# ⚠️  apps/v1beta1 Deployment is removed in v1.16
# ⚠️  policy/v1beta1 PodDisruptionBudget is removed in v1.25
# ⚠️  autoscaling/v2beta2 HPA is removed in v1.26
# ⚠️  flowcontrol.apiserver.k8s.io/v1beta1 is removed in v1.32
```

**The removal history you must know:**

| Removed in | API | Replacement |
|---|---|---|
| v1.16 | `apps/v1beta1`, `apps/v1beta2` Deployment/StatefulSet | `apps/v1` |
| v1.16 | `extensions/v1beta1` Deployment, DaemonSet, ReplicaSet, Ingress, NetworkPolicy, PSP | `apps/v1`, `networking.k8s.io/v1`, `policy/v1` |
| v1.22 | `admissionregistration.k8s.io/v1beta1`, `apiregistration.k8s.io/v1beta1`, `certificates.k8s.io/v1beta1`, `coordination.k8s.io/v1beta1`, `networking.k8s.io/v1beta1` Ingress, `rbac.authorization.k8s.io/v1beta1`, `scheduling.k8s.io/v1beta1` | Their `/v1` equivalents |
| v1.25 | `policy/v1beta1` **PodDisruptionBudget** and **PodSecurityPolicy** | `policy/v1` PDB; **PSA labels** for PSP |
| v1.26 | `autoscaling/v2beta2` HPA, `flowcontrol/v1beta1`, `batch/v1beta1` CronJob | `autoscaling/v2`, `flowcontrol/v1`, `batch/v1` |
| v1.27 | `storage.k8s.io/v1beta1` CSIStorageCapacity | `storage.k8s.io/v1` |
| v1.29 | `flowcontrol.apiserver.k8s.io/v1beta2` | `v1beta3` → `v1` |
| v1.32 | `flowcontrol.apiserver.k8s.io/v1beta3` | `v1` |

```bash
# find deprecated APIs actually IN USE in your cluster
kubectl get all -A -o json | jq -r '.items[].apiVersion' | sort -u
for kind in deployment statefulset daemonset cronjob hpa pdb ingress; do
  printf '%-14s %s\n' "$kind" "$(kubectl get $kind -A -o jsonpath='{.items[0].apiVersion}' 2>/dev/null)"
done
# and scan your Git repos, not just the cluster:
pluto detect-files -d ./k8s/          # Fairwinds Pluto
pluto detect-all-in-cluster
kube-no-trouble (kubent)               # another good one
```

---

<a name="5-get-and-describe"></a>
## 5. `get` and `describe`

### 5.1 `get` — the workhorse

```bash
kubectl get pods
kubectl get pods -n shop
kubectl get pods -A
kubectl get pods -w                       # ⭐ watch
kubectl get pods -o wide                  # + IP and node
kubectl get pods --show-labels
kubectl get pods --show-kind              # prefix each name with its kind
kubectl get pods,svc,deploy               # several types at once
kubectl get all                           # ⚠️ NOT actually everything (see below)
kubectl get pods --sort-by=.metadata.creationTimestamp
kubectl get pods --sort-by=.status.phase
kubectl get pods --sort-by='{.status.containerStatuses[0].restartCount}'
kubectl get pods --chunk-size=500         # paginate big lists (default 500)
kubectl get pods --server-print=false -o name   # names only, no headers
kubectl get pods --ignore-not-found       # exit 0 if there are none
kubectl get pods --raw='/api/v1/namespaces/default/pods?labelSelector=app%3Dweb'
```

**⚠️ `kubectl get all` does NOT return everything.** It returns a hard-coded list:

```bash
kubectl get all -o name | sed 's|/.*||' | sort -u
# pod
# service
# daemonset
# deployment
# replicaset
# statefulset
# horizontalpodautoscaler
# cronjob
# job
```

**Missing:** ConfigMaps, Secrets, PVCs, PVs, Ingresses, NetworkPolicies, PDBs, ServiceAccounts, Roles, RoleBindings, LimitRanges, ResourceQuotas, Endpoints/EndpointSlices, Nodes, Namespaces, and **every CRD**.

```bash
# what you actually want
kubectl get all,cm,secret,pvc,ingress,netpol,pdb,sa,role,rolebinding,limits,quota -n shop

# or generate the list dynamically
NS=shop
TYPES=$(kubectl api-resources --namespaced=true --verbs=list -o name | tr '\n' ',' | sed 's/,$//')
kubectl get $TYPES -n $NS

# or use the krew plugin
kubectl krew install get-all && kubectl get-all -n shop
```

### 5.2 Sorting, counting, and the `-o name` trick

```bash
kubectl get pods --sort-by=.metadata.name
kubectl get pods --sort-by=.spec.nodeName
kubectl get pods --sort-by=.status.startTime
kubectl get pods --sort-by='{.status.containerStatuses[0].restartCount}'

kubectl get pods --no-headers | wc -l                 # count
kubectl get pods -o name | wc -l
kubectl get pods -o name | sed 's|pod/||'             # strip the prefix
kubectl get pods -o name | xargs -I{} kubectl describe {}
kubectl get pods -o name | while read p; do kubectl logs $p --tail=5; done
```

### 5.3 `-o wide` — the extra columns

```bash
kubectl get pods -o wide
# NAME                     READY   STATUS    RESTARTS   AGE   IP           NODE           NOMINATED NODE   READINESS GATES
# shop-api-7d4f8c9b6-abc   1/1     Running   0          42m   10.244.2.19  learn-worker   <none>           <none>

kubectl get nodes -o wide
# NAME                 STATUS   ROLES           AGE   VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION      CONTAINER-RUNTIME
# learn-control-plane  Ready    control-plane   12d   v1.37.0   172.18.0.2    <none>        Debian GNU/Linux 12  6.1.0-27-amd64      containerd://1.7.x
# learn-worker         Ready    <none>          12d   v1.37.0   172.18.0.3    <none>        Debian GNU/Linux 12  6.1.0-27-amd64      containerd://1.7.x

kubectl get svc -o wide
kubectl get events -o wide --sort-by=.lastTimestamp
```

### 5.4 `describe` — the human-readable dump

```bash
kubectl describe pod shop-api-7d4f8c9b6-abc
kubectl describe deploy shop-api
kubectl describe node learn-worker
kubectl describe pvc data-db-0
kubectl describe ingress shop-api
kubectl describe hpa shop-api
kubectl describe -f pod.yaml
```

**The four sections that matter, in every `describe pod`:**

```
Name:             shop-api-7d4f8c9b6-abcde
Namespace:        shop
Node:             learn-worker/172.18.0.3
Start Time:       Tue, 09 Sep 2026 14:20:11 +0530
Labels:           app=shop-api
                  pod-template-hash=7d4f8c9b6
Annotations:      checksum/config: 4a1f8c2e…
Status:           Running
IP:               10.244.2.19
IPs:
  IP:  10.244.2.19
Controlled By:    ReplicaSet/shop-api-7d4f8c9b6      ← ⭐ who owns it
Init Containers:
  wait-for-db:
    Image:      busybox:1.37
    State:      Terminated
      Reason:   Completed
      Exit Code: 0
Containers:
  api:
    Image:      ghcr.io/3558bhk/shop-api@sha256:9f2a…
    State:      Running
      Started:  Tue, 09 Sep 2026 14:20:41 +0530
    Last State: Terminated                            ← ⭐ WHY it restarted last time
      Reason:   OOMKilled
      Exit Code: 137
      Started:  Tue, 09 Sep 2026 13:02:11 +0530
      Finished: Tue, 09 Sep 2026 14:19:58 +0530
    Ready:      True
    Restart Count: 3                                  ← ⭐ the number to watch
    Limits:
      cpu:     2
      memory:  1536Mi
    Requests:
      cpu:     500m
      memory:  1Gi
    Liveness:   http-get http://:http/actuator/health/liveness delay=0s timeout=5s period=20s #success=1 #failure=3
    Readiness:  http-get http://:http/actuator/health/readiness delay=0s timeout=3s period=10s #success=1 #failure=3
    Environment:
      POD_NAME:   shop-api-7d4f8c9b6-abcde (v1:metadata.name)
    Mounts:
      /tmp from tmp (rw)
      /var/run/secrets/kubernetes.io/serviceaccount from kube-api-access-xyz (ro)
Conditions:                                           ← ⭐ THE most important section
  Type              Status
  Initialized       True
  Ready             True
  ContainersReady   True
  PodScheduled      True
Volumes:
  tmp:  Type: EmptyDir
QoS Class:  Burstable                                 ← ⭐ eviction priority
Node-Selectors:  <none>
Tolerations:     node.kubernetes.io/not-ready:NoExecute op=Exists for 300s
                 node.kubernetes.io/unreachable:NoExecute op=Exists for 300s
Events:                                               ← ⭐ what just happened
  Type     Reason     Age   From               Message
  ----     ------     ----  ----               -------
  Normal   Scheduled  42m   default-scheduler  Successfully assigned shop/shop-api-… to learn-worker
  Normal   Pulling    42m   kubelet            Pulling image "ghcr.io/…"
  Normal   Pulled     41m   kubelet            Successfully pulled image in 1.2s
  Warning  Unhealthy  12m   kubelet            Readiness probe failed: connection refused
  Normal   Killing    11m   kubelet            Container api failed liveness probe, will be restarted
```

**Read `describe` in this order: Conditions → Events → Last State → QoS → Mounts.**

`describe node` has its own critical sections:

```bash
kubectl describe node learn-worker
```

```
Conditions:                          ← ⭐ is the node healthy?
  Type             Status  LastHeartbeatTime                 Reason                       Message
  MemoryPressure   False   Tue, 09 Sep 2026 15:02:11 +0530   KubeletHasSufficientMemory
  DiskPressure     False   Tue, 09 Sep 2026 15:02:11 +0530   KubeletHasNoDiskPressure
  PIDPressure      False   Tue, 09 Sep 2026 15:02:11 +0530   KubeletHasSufficientPID
  Ready            True    Tue, 09 Sep 2026 15:02:11 +0530   KubeletReady                 kubelet is posting ready status

Addresses:  InternalIP: 172.18.0.3, Hostname: learn-worker
Capacity:                        ← ⭐ what the NODE has
  cpu:                8
  ephemeral-storage:  102Gi
  memory:             16302432Ki
  pods:               110
Allocatable:                     ← ⭐ what PODS can use (minus system reserved)
  cpu:                7800m
  ephemeral-storage:  94Gi
  memory:             15474400Ki
  pods:               110
System Info:
  Kernel Version:           6.1.0-27-amd64
  OS Image:                 Debian GNU/Linux 12
  Container Runtime:        containerd://1.7.24
  Kubelet Version:          v1.37.0
  Kube-Proxy Version:       v1.37.0
Taints:  <none>              ← ⭐ what keeps pods OFF this node
Allocated resources:         ← ⭐⭐ THE section everyone needs
  Resource           Requests      Limits
  cpu                3250m (41%)   9200m (117%)
  memory             4812Mi (31%)  12480Mi (80%)
  ephemeral-storage  0 (0%)        2Gi (2%)
Non-terminated Pods:          (12 in total)
  Namespace                   Name                        CPU Requests  Memory Requests
  kube-system                 coredns-5d78c9869d-abcde    100m (1%)     70Mi (0%)
  shop                        shop-api-7d4f8c9b6-abcde    500m (6%)     1Gi (6%)
```

> 🔑 **Requests vs Limits on a node.** `cpu Requests 41%` is what the **scheduler** uses — you can only schedule 59% more. `cpu Limits 117%` is oversubscription, which is normal and fine for CPU. But `memory Limits 80%` means an OOM storm is possible: memory limits are enforced, and if the node runs out, the kernel starts OOM-killing.

---

<a name="6-output-formats"></a>
## 6. Output formats

`-o` (or `--output`) is how you turn kubectl into a data tool.

| Format | Use for |
|---|---|
| `yaml` | Reading, editing, saving |
| `json` | Piping to `jq` |
| `wide` | A quick human-readable extra column |
| `name` | Feeding other kubectl commands |
| `custom-columns=…` | A quick table of specific fields |
| `custom-columns-file=…` | The same, from a file |
| `jsonpath=…` | Extracting one or two values |
| `jsonpath-file=…` | A long jsonpath from a file |
| `go-template=…` | Full Go template power |
| `go-template-file=…` | The same, from a file |
| **`kyaml`** | ⭐ **New in v1.37** — Kubernetes-native YAML selection |
| `jsonpath-as-json=…` | jsonpath output wrapped in JSON |

### 6.1 yaml / json

```bash
kubectl get deploy shop-api -o yaml
kubectl get deploy shop-api -o yaml | grep -A20 strategy

# ⭐ strip the runtime noise so you can re-apply it
kubectl get deploy shop-api -o yaml \
  | kubectl neat \
  > shop-api.clean.yaml
# (the `neat` plugin removes status, managedFields, uid, resourceVersion,
#  creationTimestamp, selfLink, and the last-applied-configuration annotation)

# without the plugin:
kubectl get deploy shop-api -o json | jq '
  del(.status, .metadata.uid, .metadata.resourceVersion, .metadata.creationTimestamp,
      .metadata.generation, .metadata.managedFields,
      .metadata.annotations["kubectl.kubernetes.io/last-applied-configuration"],
      .spec.selector.matchLabels["pod-template-hash"])
  | .spec.template.metadata.annotations |= with_entries(select(.key|startswith("kubectl.kubernetes.io")|not))' \
  > shop-api.clean.yaml

kubectl get pods -o json | jq '.items[].metadata.name'
kubectl get pods -o json | jq -r '.items[] | "\(.metadata.name) \(.status.phase) \(.spec.nodeName)"'
kubectl get pods -o json | jq '[.items[] | select(.status.phase=="Running")] | length'
kubectl get events -o json | jq -r '.items[] | select(.type=="Warning") | "\(.lastTimestamp) \(.reason): \(.message)"'
```

### 6.2 `custom-columns` — quick tables

```bash
kubectl get pods -o custom-columns='NAME:.metadata.name,STATUS:.status.phase,NODE:.spec.nodeName,IP:.status.podIP'
# NAME                       STATUS    NODE            IP
# shop-api-7d4f8c9b6-abcde   Running   learn-worker    10.244.2.19

kubectl get pods -o custom-columns=\
'NAME:.metadata.name,\
RESTARTS:.status.containerStatuses[0].restartCount,\
READY:.status.containerStatuses[0].ready,\
IMAGE:.spec.containers[0].image,\
QOS:.status.qosClass,\
START:.status.startTime'

kubectl get nodes -o custom-columns=\
'NAME:.metadata.name,\
STATUS:.status.conditions[-1].type,\
VERSION:.status.nodeInfo.kubeletVersion,\
CPU:.status.allocatable.cpu,\
MEM:.status.allocatable.memory,\
PODS:.status.allocatable.pods,\
ZONE:.metadata.labels.topology\.kubernetes\.io/zone'
```

⚠️ **Two gotchas:**
1. **Escape dots in label keys**: `topology\.kubernetes\.io/zone`
2. **Quote the whole thing** in single quotes, or the shell eats the commas.

From a file (much more readable for long ones):

```bash
cat > cols.txt <<'EOF'
NAME          NAMESPACE   PHASE     RESTARTS   NODE            IP           QOS
metadata.name metadata.ns status.phase status.containerStatuses[0].restartCount spec.nodeName status.podIP status.qosClass
EOF
kubectl get pods -A -o custom-columns-file=cols.txt
```

### 6.3 `jsonpath` — extracting values

```bash
# the basics
kubectl get pod nginx -o jsonpath='{.metadata.name}'; echo
kubectl get pod nginx -o jsonpath='{.spec.containers[0].image}'; echo
kubectl get pod nginx -o jsonpath='{.spec.containers[*].name}'; echo       # all container names
kubectl get pod nginx -o jsonpath='{.status.containerStatuses[0].restartCount}'; echo
kubectl get pod nginx -o jsonpath='{.metadata.labels.app}'; echo

# ranges — the loop construct
kubectl get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.phase}{"\n"}{end}'
kubectl get pods -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.containers[*].image}{"\n"}{end}'

# filters — select a subset
kubectl get pods -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}'; echo
kubectl get pods -o jsonpath='{.items[?(@.metadata.namespace=="kube-system")].metadata.name}'; echo

# the one everyone needs: find a Pod by label
kubectl get pods -o jsonpath='{.items[?(@.metadata.labels.app=="shop-api")].metadata.name}'; echo

# a specific container's state
kubectl get pod nginx -o jsonpath='{.status.containerStatuses[?(@.name=="api")].state.running.startedAt}'; echo

# last termination reason (why did it restart?)
kubectl get pod nginx -o jsonpath='{.status.containerStatuses[?(@.name=="api")].lastState.terminated.reason}'; echo
# OOMKilled

# negative index — the last element
kubectl get node learn-worker -o jsonpath='{.status.conditions[-1].type}'; echo
# Ready

# sort within jsonpath (kubectl sorts, jsonpath just formats)
kubectl get pods --sort-by=.metadata.name -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'
```

**jsonpath limitations that will frustrate you:**

| You want | jsonpath | Use instead |
|---|---|---|
| Arithmetic / conditionals | ❌ impossible | `jq` or `go-template` |
| Sorting | ❌ (only via `--sort-by`) | `jq` |
| Default values | ❌ | `go-template` with `default` |
| Nested iteration | ⚠️ awkward | `jq` |
| Complex filters (`and`, `or`) | ❌ | `jq` |

```bash
# the same thing in jq, which is strictly better
kubectl get pods -o json | jq -r '.items[]
  | [.metadata.name, .status.phase, (.status.containerStatuses[0].restartCount|tostring), .spec.nodeName]
  | @tsv' | column -t
```

### 6.4 `go-template` — when jsonpath isn't enough

```bash
kubectl get pods -o go-template='{{range .items}}{{.metadata.name}} {{.status.phase}}{{"\n"}}{{end}}'

# conditionals and defaults
kubectl get deploy shop-api -o go-template='
{{- if .spec.replicas }}replicas: {{ .spec.replicas }}{{ else }}replicas: (managed by an HPA){{ end }}
{{- with .spec.strategy.rollingUpdate }}
strategy: maxSurge={{ .maxSurge }} maxUnavailable={{ .maxUnavailable }}
{{- end }}
{{- range .spec.template.spec.containers }}
container {{ .name }}: {{ .image }}
  cpu  req={{ if .resources.requests }}{{ .resources.requests.cpu }}{{ else }}none{{ end }}
         lim={{ if .resources.limits }}{{ .resources.limits.cpu }}{{ else }}none{{ end }}
{{- end }}'

# a table
kubectl get pods -A -o go-template='
{{- printf "%-45s %-15s %-10s %-8s %s\n" "NAME" "NAMESPACE" "STATUS" "RESTARTS" "NODE" -}}
{{- range .items }}
{{- printf "%-45s %-15s %-10s %-8d %s\n" .metadata.name .metadata.namespace .status.phase
     (index .status.containerStatuses 0).restartCount .spec.nodeName }}
{{- end }}'
```

### 6.5 ⭐ `kyaml` — new in Kubernetes v1.37

`kyaml` is a Kubernetes-native YAML query language that went **stable in v1.37**. It works on the *YAML structure* rather than JSON paths, so it's far more readable for nested selections.

```bash
# the whole object as YAML, filtered
kubectl get deploy shop-api -o kyaml

# select nested fields
kubectl get deploy shop-api -o kyaml='{.spec.template.spec.containers[*].image}'

# filter a list by a field value
kubectl get pods -o kyaml='{.items[?(@.status.phase=="Running")]}'

# project only what you want
kubectl get pods -o kyaml='{.items[*].{name: .metadata.name, node: .spec.nodeName, ip: .status.podIP}}'

# a list of container images across every Pod in the cluster
kubectl get pods -A -o kyaml='{.items[*].spec.containers[*].image}' | sort -u
```

Compare with the jsonpath equivalent:

```bash
# jsonpath — dense, easy to get the brackets wrong
kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].image}{"\n"}{end}'

# kyaml — reads like the YAML it produces
kubectl get pods -A -o kyaml='{.items[*].{name: .metadata.name, images: .spec.containers[*].image}}'
```

**When to use which:**

| Task | Best tool |
|---|---|
| One scalar value into a shell variable | `jsonpath` (still the shortest) |
| A quick table of 3–4 columns | `custom-columns` |
| Nested selection, projection, or filtering of lists | **`kyaml`** |
| Arithmetic, sorting, joining, complex logic | `jq` |
| Human-readable conditional output | `go-template` |

```bash
kubectl get pods -o kyaml --help 2>&1 | head -20    # check availability on your version
kubectl version --client | grep -q 'v1.3[7-9]' && echo "kyaml available" || echo "need v1.37+"
```

### 6.6 `-o name` and feeding commands

```bash
kubectl get pods -o name
# pod/shop-api-7d4f8c9b6-abcde
# pod/shop-api-7d4f8c9b6-fghij

kubectl delete $(kubectl get pods -l app=shop-api -o name)
kubectl logs $(kubectl get pods -l app=shop-api -o name --sort-by=.metadata.creationTimestamp | tail -1)
kubectl describe $(kubectl get pods -l app=shop-api -o name | head -1)

# ⚠️ with many pods, the argument list overflows. Use xargs:
kubectl get pods -A -o name | xargs -n1 -P4 kubectl describe

# ⚠️ and -o name across namespaces loses the namespace. Include it:
kubectl get pods -A -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name' --no-headers \
  | while read ns name; do kubectl -n $ns delete pod $name; done
```

### 6.7 Saving and round-tripping

```bash
# export a live object, clean it, and re-apply it elsewhere
kubectl get deploy shop-api -n shop-prod -o yaml | kubectl neat > api.yaml
kubectl apply -f api.yaml -n shop-staging --dry-run=server

# export a whole namespace
kubectl get all,cm,secret,pvc,ingress,netpol,pdb,sa -n shop -o yaml > shop-backup.yaml

# ⭐ export EVERYTHING in a namespace, one file per resource
NS=shop; OUT=./export-$NS; mkdir -p $OUT
for t in $(kubectl api-resources --namespaced=true --verbs=list -o name); do
  short=$(echo $t | sed 's|.*/||')
  kubectl get $t -n $NS -o yaml 2>/dev/null | kubectl neat > $OUT/$short.yaml
  [ -s $OUT/$short.yaml ] && echo "  ✅ $short" || rm -f $OUT/$short.yaml
done
ls -la $OUT

# the reverse: recreate a namespace from an export
kubectl create namespace shop-new
kubectl apply -f ./export-shop -n shop-new
```

⚠️ **`kubectl get -o yaml` includes `.status`, `.metadata.uid`, `.metadata.resourceVersion`, `.metadata.managedFields` and `creationTimestamp`.** Re-applying that causes conflicts or errors. Always clean it (`kubectl neat`, or the `jq` filter in §6.1).

---

<a name="7-filtering-labels-and-field-selectors"></a>
## 7. Filtering: labels & field selectors

### 7.1 Label selectors (`-l` / `--selector`)

```bash
kubectl get pods -l app=shop-api                       # equality
kubectl get pods -l app!=shop-api                      # inequality
kubectl get pods -l 'app in (shop-api,shop-ui)'        # set-based IN
kubectl get pods -l 'app notin (shop-api)'             # set-based NOTIN
kubectl get pods -l app                                # label EXISTS
kubectl get pods -l '!app'                             # label does NOT exist
kubectl get pods -l 'app=shop-api,tier=backend'        # AND (comma)
kubectl get pods -l 'app=shop-api' -l 'tier=backend'   # AND (repeated flag)
kubectl get pods -l 'app in (a,b),env!=prod,!debug'    # combined
```

**Set-based selectors are the powerful ones:**

| Operator | Meaning | Example |
|---|---|---|
| `=` or `==` | Equal | `app=web` |
| `!=` | Not equal | `app!=web` |
| `in` | Value is in the set | `tier in (frontend,backend)` |
| `notin` | Value is not in the set | `tier notin (test)` |
| *(bare key)* | Key exists | `release` |
| `!key` | Key does not exist | `!deprecated` |

```bash
# ⭐ quote anything with spaces, parens, or commas
kubectl get pods -l 'env in (prod, staging)'          # ← the space is fine inside quotes
kubectl get pods -l env in (prod,staging)             # ⛔ shell parses the parens
```

**The selectors Kubernetes uses for you:**

```bash
# a Deployment's selector — find its pods
kubectl get deploy shop-api -o jsonpath='{.spec.selector}'; echo
# {"matchLabels":{"app":"shop-api"}}
kubectl get pods -l app=shop-api

# the ReplicaSet adds pod-template-hash
kubectl get rs -l app=shop-api -o custom-columns='NAME:.metadata.name,DESIRED:.spec.replicas,READY:.status.readyReplicas'
kubectl get pods -l 'app=shop-api,pod-template-hash=7d4f8c9b6'

# ⭐ the single most useful pattern: pods of the CURRENT ReplicaSet
HASH=$(kubectl get rs -l app=shop-api --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.labels.pod-template-hash}')
kubectl get pods -l "app=shop-api,pod-template-hash=$HASH"

# a Service's selector → the endpoints it balances across
kubectl get svc shop-api -o jsonpath='{.spec.selector}'; echo
# {"app":"shop-api"}
kubectl get endpointslices -l kubernetes.io/service-name=shop-api
```

### 7.2 Field selectors (`--field-selector`)

Field selectors filter on **object fields**, not labels — but only a small, hard-coded set of fields is supported.

```bash
kubectl get pods --field-selector=status.phase=Running
kubectl get pods --field-selector=status.phase!=Running
kubectl get pods --field-selector=spec.nodeName=learn-worker
kubectl get pods --field-selector=metadata.namespace=shop
kubectl get pods --field-selector=metadata.name=nginx
kubectl get events --field-selector=involvedObject.kind=Pod,involvedObject.name=nginx
kubectl get events --field-selector=type=Warning
kubectl get events --field-selector=reason=FailedMount
kubectl get pods -A --field-selector=status.phase=Failed
```

**The complete supported list:**

| Resource | Supported fields |
|---|---|
| **All** | `metadata.name`, `metadata.namespace` |
| `pods` | `spec.nodeName`, `spec.restartPolicy`, `spec.schedulerName`, `status.phase`, `status.podIP`, `status.nominatedNodeName` |
| `secrets` | `type` |
| `events` | `involvedObject.kind`, `involvedObject.namespace`, `involvedObject.name`, `involvedObject.uid`, `involvedObject.apiVersion`, `involvedObject.resourceVersion`, `involvedObject.fieldPath`, `reason`, `reportingComponent`, `reportingInstance`, `source`, `type` |
| `namespaces` | `status.phase` |
| `replicasets` | `status.replicas` |
| `jobs` | `status.successful` |
| `cronjobs` | `status.active`, `schedule` |
| `nodes` | `spec.unschedulable`, `spec.taints` (limited) |

⚠️ **`--field-selector` does NOT support:**
- `in` / `notin` (equality only)
- `spec.containers[*].image`
- most of `.spec` or `.status`
- arbitrary fields

```bash
kubectl get pods --field-selector=spec.containers[0].image=nginx:1.29-alpine
# Error from server (BadRequest): Unable to find "v1.Pod" that match label selector "",
#   field selector "spec.containers[0].image=nginx:1.29-alpine": field label not supported: spec.containers[0].image
```

**The workaround — filter client-side with jq:**

```bash
kubectl get pods -A -o json | jq -r '.items[]
  | select(.spec.containers[].image | startswith("nginx"))
  | "\(.metadata.namespace)/\(.metadata.name)"'

kubectl get pods -A -o json | jq -r '.items[]
  | select(any(.spec.containers[]; .resources.limits == null))
  | "\(.metadata.namespace)/\(.metadata.name)  ⚠️ no limits"'

kubectl get deploy -A -o json | jq -r '.items[]
  | select(.spec.template.spec.containers[].image | test(":latest$"))
  | "\(.metadata.namespace)/\(.metadata.name)  ⚠️ :latest tag"'
```

### 7.3 Combining selectors

```bash
kubectl get pods -l app=shop-api --field-selector=status.phase=Running,spec.nodeName=learn-worker
kubectl get events -A --field-selector type=Warning -l '!kubernetes.io/hostname'
```

⚠️ **Both selectors are ANDed**, and label selectors are applied server-side but field selectors are limited to the indexed fields. A query the API server can't index falls back to a **full list + client-side filter**, which is expensive at scale.

### 7.4 Server-side vs client-side filtering — why it matters at scale

```bash
# ⛔ this pulls EVERY pod in the cluster to your laptop, then greps
kubectl get pods -A -o json | jq '.items[] | select(.metadata.labels.app=="shop-api")'

# ✅ this asks the API server to return only the matches
kubectl get pods -A -l app=shop-api
```

On a 5,000-Pod cluster the first one can take 30 seconds and load the API server. **Always push filtering into `-l` or `--field-selector` when you can.**

```bash
# and paginate large lists
kubectl get pods -A --chunk-size=1000        # 1000 per request instead of the 500 default
kubectl get pods -A --chunk-size=0           # ⛔ disable chunking — one huge request. Never do this.
```

### 7.5 Sorting + filtering together

```bash
kubectl get pods -l app=shop-api --sort-by=.metadata.creationTimestamp
kubectl get pods -l app=shop-api --sort-by=.status.startTime -o wide
kubectl get pods -A --sort-by=.metadata.creationTimestamp | tail -10    # the newest pods
kubectl get pods -A --field-selector=status.phase!=Running --sort-by=.metadata.creationTimestamp
kubectl get events -A --sort-by=.lastTimestamp | tail -30               # ⭐ the most recent events
```

⚠️ **`--sort-by` is client-side.** kubectl fetches everything, then sorts locally. It's fine for hundreds of objects, slow for tens of thousands.

---

<a name="8-creating-and-modifying-resources"></a>
## 8. Creating & modifying resources

### 8.1 Imperative — great for learning, bad for production

```bash
# Pods
kubectl run nginx --image=nginx:1.29-alpine
kubectl run nginx --image=nginx:1.29-alpine --port=80
kubectl run nginx --image=nginx:1.29-alpine --restart=Never          # a bare Pod, not a Deployment
kubectl run nginx --image=nginx:1.29-alpine --restart=OnFailure      # a Job
kubectl run busybox --image=busybox:1.37 --restart=Never -- sleep 3600
kubectl run curl --image=curlimages/curl:8.10.1 --rm -it --restart=Never -- sh
kubectl run netshoot --image=nicolaka/netshoot --rm -it --restart=Never -- bash
kubectl run debug --image=busybox:1.37 --rm -it --restart=Never --overrides='
{
  "spec": {
    "nodeName": "learn-worker",
    "hostNetwork": true,
    "containers": [{"name":"debug","image":"busybox:1.37","command":["sleep","3600"],
                    "securityContext":{"privileged":true}}]
  }
}'

# Deployments
kubectl create deployment shop-api --image=ghcr.io/3558bhk/shop-api:1.0.0
kubectl create deployment shop-api --image=ghcr.io/3558bhk/shop-api:1.0.0 --replicas=3 --port=8080
kubectl create deployment nginx --image=nginx:1.29-alpine --dry-run=client -o yaml > deploy.yaml   # ⭐ scaffold

# Services
kubectl expose deployment shop-api --port=80 --target-port=8080
kubectl expose deployment shop-api --port=80 --target-port=8080 --type=ClusterIP --name=shop-api-internal
kubectl expose pod nginx --port=80 --type=NodePort
kubectl create service clusterip shop-api --tcp=80:8080
kubectl create service nodeport  shop-api --tcp=80:8080 --node-port=30080
kubectl create service loadbalancer shop-api --tcp=80:8080

# Config & secrets
kubectl create configmap app-config --from-literal=LOG_LEVEL=debug --from-literal=FEATURE_X=true
kubectl create configmap app-config --from-file=application.properties
kubectl create configmap app-config --from-file=config/=./config/
kubectl create configmap app-config --from-env-file=.env
kubectl create secret generic db-creds --from-literal=username=shop --from-literal=password='S3cret!'
kubectl create secret generic tls-secret --from-file=tls.crt=./fullchain.pem --from-file=tls.key=./privkey.pem
kubectl create secret docker-registry ghcr-creds --docker-server=ghcr.io --docker-username=3558Bhk --docker-password=$GHCR_TOKEN --docker-email=me@example.com
kubectl create secret generic ssh-key --from-file=id_rsa=~/.ssh/id_ed25519
kubectl create secret tls shop-tls --cert=./fullchain.pem --key=./privkey.pem

# Namespaces, ServiceAccounts, RBAC, Jobs, CronJobs
kubectl create namespace shop
kubectl create serviceaccount deployer -n shop
kubectl create role pod-reader --verb=get,list,watch --resource=pods -n shop
kubectl create rolebinding read-pods --role=pod-reader --serviceaccount=shop:deployer -n shop
kubectl create clusterrole node-reader --verb=get,list --resource=nodes
kubectl create job one-shot --image=busybox:1.37 -- echo hello
kubectl create cronjob nightly --image=busybox:1.37 --schedule='0 2 * * *' -- echo backup
kubectl create cronjob nightly --image=busybox:1.37 --schedule='0 2 * * *' --dry-run=client -o yaml > cron.yaml

# Storage
kubectl create -f pvc.yaml

# ⭐ the dry-run scaffolding pattern — memorise this
kubectl create deployment x --image=nginx --dry-run=client -o yaml > x.yaml
kubectl create configmap x --from-literal=a=b --dry-run=client -o yaml > x-cm.yaml
kubectl create secret generic x --from-literal=a=b --dry-run=client -o yaml > x-secret.yaml
kubectl create service clusterip x --tcp=80:80 --dry-run=client -o yaml > x-svc.yaml
kubectl run x --image=nginx --restart=Never --dry-run=client -o yaml > x-pod.yaml
kubectl create role x --verb=get --resource=pods --dry-run=client -o yaml > x-role.yaml
```

**`create` fails if the object exists:**

```bash
kubectl create configmap app-config --from-literal=A=1
kubectl create configmap app-config --from-literal=A=2
# Error from server (AlreadyExists): error when creating "STDIN": configmaps "app-config" already exists

kubectl create configmap app-config --from-literal=A=2 --dry-run=client -o yaml | kubectl apply -f -   # ⭐ the idiom
```

### 8.2 Declarative — `apply`

```bash
kubectl apply -f deploy.yaml
kubectl apply -f ./k8s/                       # every YAML in a directory
kubectl apply -f ./k8s/ -R                    # recursive
kubectl apply -f https://example.com/x.yaml   # from a URL
kubectl apply -f -                            # from stdin
kubectl apply -f deploy.yaml -n shop          # override the namespace in the file
kubectl apply -f deploy.yaml --validate=strict
kubectl apply -f deploy.yaml --server-side --force-conflicts
kubectl apply -f deploy.yaml --dry-run=server
kubectl apply -f deploy.yaml --prune -l app.kubernetes.io/part-of=shop
```

**What `apply` actually does:**

1. Reads your file.
2. Computes a **3-way merge**: your file ↔ the last-applied annotation ↔ the live object.
3. PATCHes only the differences.

```bash
# see the patch before it's sent
kubectl apply -f deploy.yaml -v=8 2>&1 | grep -A20 'Request Body'

# ⭐ see the diff without applying
kubectl diff -f deploy.yaml
# diff -u -N /tmp/LIVE-1234/v1.ConfigMap.shop.app-config /tmp/MERGED-1234/v1.ConfigMap.shop.app-config
# --- /tmp/LIVE-…
# +++ /tmp/MERGED-…
# @@ -5,3 +5,3 @@
#    data:
# -  LOG_LEVEL: info
# +  LOG_LEVEL: debug

kubectl diff -f ./k8s/ -R          # diff a whole directory
kubectl diff -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata: {name: test, namespace: default}
data: {a: b}
EOF
```

### 8.3 Client-side vs server-side apply ⭐

This is the single most important `apply` concept, and a favourite interview topic.

| | **Client-side apply (CSA)** — the default | **Server-side apply (SSA)** — `--server-side` |
|---|---|---|
| Who computes the merge | **kubectl**, on your laptop | **the API server** |
| How it tracks state | The `kubectl.kubernetes.io/last-applied-configuration` annotation (a full copy of your YAML) | `metadata.managedFields` (a per-field owner map) |
| Object size | Inflated — the annotation duplicates the whole spec | Compact |
| Conflicts | Silently overwritten; last writer wins | **Detected and reported** — you must `--force-conflicts` or fix it |
| Multi-manager | Broken — two controllers fight | ✅ Designed for it |
| Removes fields you deleted | ⚠️ Only if they were in the last-applied annotation | ✅ Precisely, by ownership |
| Used by | `kubectl apply` by default | GitOps controllers, operators, `kubectl apply --server-side` |

```bash
# see the ownership map
kubectl get deploy shop-api -o jsonpath='{.metadata.managedFields}' | jq '.[] | {manager, operation, time}'
# [{"manager":"kubectl-client-side-apply","operation":"Update","time":"2026-09-09T08:20:11Z"},
#  {"manager":"deployment-controller","operation":"Update","time":"2026-09-09T08:20:13Z"}]

kubectl get deploy shop-api -o yaml --show-managed-fields | head -60   # the full field-level detail

# server-side apply
kubectl apply -f deploy.yaml --server-side
kubectl apply -f deploy.yaml --server-side --force-conflicts
kubectl apply -f deploy.yaml --server-side --field-manager=ci-pipeline   # ⭐ name your manager

# migrate an existing CSA object to SSA
kubectl apply -f deploy.yaml --server-side --force-conflicts --field-manager=kubectl
```

**The conflict error, and what to do about it:**

```bash
kubectl apply -f hpa-deploy.yaml --server-side
# error: Apply failed with 1 conflict: conflict with "kubectl" using apps/v1: .spec.replicas

# who owns that field?
kubectl get deploy shop-api -o yaml --show-managed-fields | grep -B10 'f:replicas'
#   - apiVersion: apps/v1
#     fieldsType: FieldsV1
#     fieldsV1:
#       f:spec:
#         f:replicas: {}
#     manager: argocd-application-controller     ← ⭐ Argo CD owns it
#     operation: Update

# the right fix: REMOVE replicas from your file (the HPA owns it)
# the quick fix: --force-conflicts  (⛔ in GitOps — it just comes back)
```

> 🔑 **The rule:** if an HPA manages `spec.replicas`, **delete `replicas` from your Deployment manifest.** Then there's no conflict, because nobody declares it. This is the #1 cause of "my Deployment keeps resetting to 1 replica" — see [Project 2](./05-PROJECT-2-deployment-service.md).

### 8.4 `patch` — surgical changes

Four patch types:

```bash
# 1. strategic merge patch (the default for native types)
kubectl patch deploy shop-api -p '{"spec":{"replicas":5}}'
kubectl patch deploy shop-api --type=strategic -p '{"spec":{"template":{"spec":{"containers":[{"name":"api","image":"ghcr.io/3558bhk/shop-api:1.1.0"}]}}}}'

# 2. JSON merge patch (RFC 7386) — required for CRDs
kubectl patch deploy shop-api --type=merge -p '{"spec":{"replicas":5}}'

# 3. JSON patch (RFC 6902) — precise, array-index-aware ⭐
kubectl patch deploy shop-api --type=json -p='[
  {"op":"replace","path":"/spec/replicas","value":5},
  {"op":"add","path":"/spec/template/spec/containers/0/env/-","value":{"name":"FEATURE_X","value":"true"}},
  {"op":"remove","path":"/spec/template/spec/nodeSelector"}
]'

# 4. server-side apply patch
kubectl patch deploy shop-api --type=apply --server-side --field-manager=hotfix \
  -p '{"apiVersion":"apps/v1","kind":"Deployment","metadata":{"name":"shop-api"},"spec":{"replicas":5}}'

# from a file
kubectl patch deploy shop-api --patch-file=patch.yaml
kubectl patch deploy shop-api --type=json --patch-file=patch.json

# subresources
kubectl patch deploy shop-api --subresource=status -p '{"status":{"replicas":3}}'
```

**strategic vs merge — the difference that bites:**

```yaml
# the live object
spec:
  template:
    spec:
      containers:
        - name: api
          image: v1
        - name: sidecar
          image: busybox
```

```bash
# strategic merge: lists with a merge key (name) are MERGED
kubectl patch deploy shop-api -p '{"spec":{"template":{"spec":{"containers":[{"name":"api","image":"v2"}]}}}}'
# → containers: [{name: api, image: v2}, {name: sidecar, image: busybox}]   ✅ sidecar survives

# json merge: lists are REPLACED wholesale
kubectl patch deploy shop-api --type=merge -p '{"spec":{"template":{"spec":{"containers":[{"name":"api","image":"v2"}]}}}}'
# → containers: [{name: api, image: v2}]   ⛔ SIDECAR DELETED
```

> 🔑 **Never use `--type=merge` on a list unless you mean to replace the whole list.** Use `strategic` (the default) or `--type=json` with explicit indices.

**JSON patch operation reference:**

| op | Meaning | Example |
|---|---|---|
| `add` | Create, or append to a list with `/-` | `{"op":"add","path":"/spec/replicas","value":3}` |
| `remove` | Delete | `{"op":"remove","path":"/spec/nodeSelector"}` |
| `replace` | Must already exist | `{"op":"replace","path":"/spec/replicas","value":5}` |
| `move` | Remove from one path, add to another | `{"op":"move","from":"/a","path":"/b"}` |
| `copy` | Duplicate | `{"op":"copy","from":"/a","path":"/b"}` |
| `test` | Fail the whole patch if the value differs | `{"op":"test","path":"/spec/replicas","value":3}` |

```bash
# ⭐ test = optimistic concurrency. The patch only applies if nothing changed.
kubectl patch deploy shop-api --type=json -p='[
  {"op":"test","path":"/spec/replicas","value":3},
  {"op":"replace","path":"/spec/replicas","value":5}
]'
# if someone else already scaled it to 4, you get:
# error: unable to patch: the server rejected our request due to an error in our request
```

**Patch recipes you'll actually use:**

```bash
# add an env var
kubectl patch deploy shop-api --type=json -p='[{"op":"add","path":"/spec/template/spec/containers/0/env/-","value":{"name":"LOG_LEVEL","value":"debug"}}]'

# change a container image (by name, safely)
kubectl set image deploy/shop-api api=ghcr.io/3558bhk/shop-api:1.1.0    # ⭐ better than patch

# add a label / annotation
kubectl patch deploy shop-api --type=merge -p '{"metadata":{"labels":{"team":"platform"}}}'
kubectl annotate deploy shop-api kubernetes.io/change-cause="release 1.1.0" --overwrite
kubectl label deploy shop-api team=platform --overwrite
kubectl label nodes learn-worker disktype=ssd

# add a toleration
kubectl patch deploy shop-api --type=json -p='[{"op":"add","path":"/spec/template/spec/tolerations/-","value":{"key":"dedicated","operator":"Equal","value":"shop","effect":"NoSchedule"}}]'

# add a volume + mount
kubectl patch deploy shop-api --type=json -p='[
  {"op":"add","path":"/spec/template/spec/volumes/-","value":{"name":"tmp","emptyDir":{}}},
  {"op":"add","path":"/spec/template/spec/containers/0/volumeMounts/-","value":{"name":"tmp","mountPath":"/tmp"}}
]'

# change a probe
kubectl patch deploy shop-api --type=json -p='[{"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/initialDelaySeconds","value":30}]'

# add an init container
kubectl patch deploy shop-api --type=json -p='[{"op":"add","path":"/spec/template/spec/initContainers/-","value":{"name":"wait","image":"busybox:1.37","command":["sh","-c","until nc -z db 5432; do sleep 2; done"]}}]'

# add a finalizer (⚠️ then you must remove it — see §9.3)
kubectl patch ns shop --type=merge -p '{"metadata":{"finalizers":["kubernetes"]}}'

# set the HPA min/max
kubectl patch hpa shop-api --type=merge -p '{"spec":{"minReplicas":3,"maxReplicas":20}}'

# scale a StatefulSet's PVC template (⛔ immutable — you must delete & recreate the STS)
kubectl patch sts db -p '{"spec":{"volumeClaimTemplates":[{"metadata":{"name":"data"},"spec":{"resources":{"requests":{"storage":"20Gi"}}}}]}}'
# error: StatefulSet.apps "db" is invalid: spec: Forbidden: updates to statefulset spec for fields other than
#   'replicas', 'ordinals', 'template', 'updateStrategy', 'persistentVolumeClaimRetentionPolicy' and 'minReadySeconds' are forbidden
kubectl delete sts db --cascade=orphan && kubectl apply -f db.yaml   # ✅ the workaround
```

### 8.5 `edit` — the interactive way

```bash
kubectl edit deploy shop-api
kubectl edit deploy shop-api -n shop
kubectl edit pod nginx                        # ⚠️ most Pod fields are immutable
KUBE_EDITOR=nano kubectl edit deploy shop-api
KUBE_EDITOR='code --wait' kubectl edit deploy shop-api     # VS Code (must block until closed)
kubectl edit deploy shop-api --validate=strict
```

`edit` does: `GET` → open `$KUBE_EDITOR` (default `vi`) on a temp file → `PUT` the result. It writes the temp file to `/tmp/kubectl-edit-XXXX.yaml`, and on error leaves it there:

```bash
kubectl edit deploy shop-api
# error: Deployment.apps "shop-api" is invalid: spec.template.spec.containers[0].image: Required value
# A copy of your changes has been stored to "/tmp/kubectl-edit-1234567.yaml"
# error: Edit cancelled, no valid changes were saved.

cat /tmp/kubectl-edit-1234567.yaml      # ⭐ recover your work
kubectl apply -f /tmp/kubectl-edit-1234567.yaml
```

⚠️ **`edit` is not GitOps.** It's fine for a 2am hotfix; commit the change afterwards. `edit` also fails on immutable fields with no way around it.

### 8.6 `replace` — full overwrite

```bash
kubectl replace -f deploy.yaml
kubectl replace -f deploy.yaml --force          # ⛔ DELETE then CREATE — downtime, new UID
kubectl replace --raw='/api/v1/namespaces/shop/pods/nginx' -f pod.json
```

| | `apply` | `replace` |
|---|---|---|
| Object must exist? | No | **Yes** |
| Fields you omit | Kept (if someone else owns them) | **Deleted** |
| Downtime | None | None (unless `--force`) |
| Use for | Day-to-day | Fixing a badly drifted object |

`replace --force` is dangerous: it deletes the object (losing its UID, its PVC bindings if any, its history) and recreates it.

### 8.7 `set` — the typed imperative helpers

```bash
# images ⭐ the most common deployment change
kubectl set image deploy/shop-api api=ghcr.io/3558bhk/shop-api:1.1.0
kubectl set image deploy/shop-api *=ghcr.io/3558bhk/shop-api:1.1.0     # all containers
kubectl set image deploy/shop-api api=ghcr.io/3558bhk/shop-api:1.1.0 --record
kubectl set image sts/db postgres=postgres:17.4-alpine
kubectl set image ds/log-agent fluentbit=fluent/fluent-bit:3.2
kubectl set image pod/nginx nginx=nginx:1.29-alpine                    # ⛔ pods are mostly immutable
kubectl set image -f deploy.yaml api=x:1 --local -o yaml               # ⭐ edit the FILE, not the cluster

# env vars
kubectl set env deploy/shop-api LOG_LEVEL=debug
kubectl set env deploy/shop-api LOG_LEVEL-                              # remove
kubectl set env deploy/shop-api --from=configmap/app-config
kubectl set env deploy/shop-api --from=secret/db-creds
kubectl set env deploy/shop-api --from=secret/db-creds --prefix=DB_
kubectl set env deploy/shop-api DB_PASSWORD=s3cret --containers=api     # one container only
kubectl set env deploy/shop-api POD_NAME --field-ref=metadata.name
kubectl set env deploy/shop-api NODE_IP --field-ref=status.hostIP
kubectl set env deploy/shop-api LIST --list                             # show the current env
kubectl set env deploy/shop-api --keys=PASSWORD --from=secret/db-creds
kubectl set env deploy/shop-api --overwrite LOG_LEVEL=trace             # required if it exists

# volumes
kubectl set volume deploy/shop-api --add --name=tmp --type=emptyDir --mount-path=/tmp
kubectl set volume deploy/shop-api --add --name=config --configmap-name=app-config --mount-path=/etc/app
kubectl set volume deploy/shop-api --add --name=secret --secret-name=db-creds --mount-path=/etc/secrets --read-only
kubectl set volume deploy/shop-api --add --name=data --claim-name=data-pvc --mount-path=/data
kubectl set volume deploy/shop-api --add --name=data --type=pvc --claim-size=5Gi --mount-path=/data
kubectl set volume deploy/shop-api --remove --name=tmp
kubectl set volume deploy/shop-api --remove --name=config --containers=api    # unmount, keep the volume
kubectl set volume deploy/shop-api --list

# serviceaccounts, resources, selectors, subjects
kubectl set serviceaccount deploy/shop-api restricted-sa
kubectl set resources deploy/shop-api --limits=cpu=1,memory=1Gi --requests=cpu=250m,memory=512Mi
kubectl set resources deploy/shop-api -c api --limits=cpu=2
kubectl set selector deploy/shop-api 'app=shop-api,tier=backend' --resource-version=3   # ⚠️ immutable in practice
kubectl set subject clusterrole admin --user=jane@example.com
kubectl set subject rolebinding read-pods --serviceaccount=shop:deployer
```

### 8.8 Validation

```bash
kubectl apply -f deploy.yaml --validate=strict      # ⭐ the default in modern kubectl
kubectl apply -f deploy.yaml --validate=warn        # warn but apply
kubectl apply -f deploy.yaml --validate=false       # ⛔ skip — never in CI
kubectl apply -f deploy.yaml --dry-run=client       # client-side schema check only
kubectl apply -f deploy.yaml --dry-run=server       # ⭐ full server validation, no write
```

| | `--dry-run=client` | `--dry-run=server` |
|---|---|---|
| Sends to the API server? | No | **Yes** |
| Runs admission webhooks? | No | **Yes** |
| Catches RBAC denials? | No | **Yes** |
| Catches quota/quota/webhook rejections? | No | **Yes** |
| Catches typos in field names? | ✅ | ✅ |
| Mutates anything? | No | No |
| Speed | Instant | A network round-trip |

> 🔑 **Use `--dry-run=server` in CI.** It catches everything a real `apply` would catch, without changing anything. `--dry-run=client` gives false confidence — it never sees your webhooks or quotas.

```bash
# the CI pre-flight
kubectl apply -f ./k8s/ -R --dry-run=server --validate=strict
kubectl diff -f ./k8s/ -R || true          # diff exits 1 when there ARE differences — that's normal
```

### 8.9 Prune — deleting what's no longer in Git

```bash
kubectl apply -f ./k8s/ -R -l app.kubernetes.io/part-of=shop --prune
# configmap/app-config configured
# deployment.apps/shop-api configured
# secret/db-creds unchanged
# service/shop-api unchanged
# ⭐ ingress.apps/old-ingress pruned          ← deleted because it's not in ./k8s/ anymore
```

`--prune` deletes objects in the cluster that (a) carry the given label and (b) aren't in the applied set. **Without the `-l` filter it would consider every object in the namespace.**

```bash
kubectl apply -f ./k8s/ -R -l app.kubernetes.io/part-of=shop --prune --dry-run=server    # ⭐ always preview
kubectl apply -f ./k8s/ -R --prune --all     # ⛔⛔ never — prunes across every label
```

---

<a name="9-deleting-resources"></a>
## 9. Deleting resources

### 9.1 The basics

```bash
kubectl delete pod nginx
kubectl delete pod nginx -n shop
kubectl delete pods -l app=shop-api
kubectl delete pods --all -n shop
kubectl delete -f deploy.yaml
kubectl delete -f ./k8s/ -R
kubectl delete deploy,svc -l app=shop-api
kubectl delete pod nginx --grace-period=0 --force
kubectl delete pod nginx --wait=false
kubectl delete ns shop
kubectl delete ns shop --wait=false
```

### 9.2 Grace periods — what actually happens

```bash
kubectl delete pod nginx --grace-period=30      # the default: use the Pod's terminationGracePeriodSeconds
kubectl delete pod nginx --grace-period=10      # override to 10s
kubectl delete pod nginx --grace-period=0       # ⛔ immediate removal from etcd (needs --force)
kubectl delete pod nginx --grace-period=0 --force
kubectl delete pod nginx --grace-period=0 --force --wait=false
```

**The deletion sequence:**

```
1. DELETE arrives → the API server sets metadata.deletionTimestamp
                   and metadata.deletionGracePeriodSeconds = 30
2. The Pod is REMOVED from its Service's endpoints immediately
   (EndpointSlice controller) → no new traffic
3. The kubelet runs preStop hooks, then SIGTERM to PID 1
4. The app drains in-flight requests (you have terminationGracePeriodSeconds)
5. At the deadline, the kubelet sends SIGKILL
6. The kubelet reports the container is gone → the API server
   removes the Pod object from etcd
7. The Deployment/ReplicaSet controller sees a missing replica → schedules a new one
```

⚠️ **`--grace-period=0 --force` skips steps 3–6.** The Pod vanishes from the API immediately, but **the container may still be running on the node.** For a StatefulSet this is catastrophic: the replacement Pod can't start because the old one still holds the PVC, and you can end up with two writers to one volume.

```bash
# ⛔ NEVER force-delete a StatefulSet pod with a ReadWriteOnce volume
kubectl delete pod db-0 --grace-period=0 --force
# → Pod gone from the API, but the container is still running
# → db-0 recreated, but the PVC is still "in use" by the orphan
# → multi-attach error, data corruption risk

# ✅ the correct way: make sure the node is really dead first
kubectl get node learn-worker                 # is it NotReady?
crictl ps | grep db-0                         # on the node: is the container gone?
kubectl delete pod db-0 --grace-period=0 --force   # only NOW
```

### 9.3 Finalizers — why deletion hangs

A finalizer is a string in `metadata.finalizers`. **The API server will not remove an object until the list is empty.** Controllers add finalizers to do cleanup (detach volumes, delete cloud LBs, remove DNS records).

```bash
kubectl get pvc data-db-0 -o jsonpath='{.metadata.finalizers}'; echo
# ["kubernetes.io/pvc-protection"]

kubectl get ns shop -o jsonpath='{.metadata.finalizers}'; echo
# ["kubernetes"]

kubectl get ns shop -o jsonpath='{.spec.finalizers}'; echo
# ["kubernetes"]
```

**The stuck-namespace scenario:**

```bash
kubectl delete ns shop
# (hangs for 10 minutes)
kubectl get ns shop
# NAME   STATUS        AGE
# shop   Terminating   3d

kubectl get ns shop -o json | jq '.status.conditions'
# [{"type":"NamespaceDeletionDiscoveryFailure","status":"True",
#   "message":"Failed to delete all resource types, 2 remaining:
#             mycrd.example.com is forbidden: User \"system:serviceaccount:kube-system:namespace-controller\"
#             cannot list resource \"mycrd\" in API group \"example.com\" at the cluster scope"}]
```

**Cause:** an APIService is down, or a CRD's controller is gone, so the namespace controller can't list the resources inside it.

```bash
# 1. find the broken APIService
kubectl get apiservices | grep -v True
# v1beta1.metrics.k8s.io        kube-system/metrics-server   False   10m   service/metrics-server not found

# 2. fix or remove it
kubectl delete apiservice v1beta1.metrics.k8s.io

# 3. what's left in the namespace?
kubectl get all -n shop
kubectl api-resources --verbs=list --namespaced -o name | xargs -n1 kubectl get -n shop --show-kind --ignore-not-found

# 4. the last resort — clear the finalizer (⚠️ leaks the underlying resources)
kubectl get ns shop -o json | jq '.spec.finalizers = []' > ns.json
kubectl replace --raw "/api/v1/namespaces/shop/finalize" -f ns.json
```

**The stuck-object scenario:**

```bash
kubectl delete pvc data-db-0
# (hangs)
kubectl get pvc data-db-0 -o jsonpath='{.metadata.finalizers}'; echo
# ["kubernetes.io/pvc-protection"]        ← because a Pod still uses it
kubectl get pods -A -o json | jq -r '.items[] | select(.spec.volumes[]?.persistentVolumeClaim.claimName=="data-db-0") | .metadata.name'
kubectl delete pod db-0                   # ← remove the user first
# the PVC then deletes itself

# the last resort (⚠️ orphans the cloud volume — you'll keep paying for it)
kubectl patch pvc data-db-0 --type=merge -p '{"metadata":{"finalizers":null}}'
```

**Finalizer troubleshooting order:**

| Step | Command |
|---|---|
| 1. Is something still using it? | `kubectl get pods -A -o json \| jq` (above) |
| 2. Is an APIService down? | `kubectl get apiservices \| grep -v True` |
| 3. Is the owning controller running? | `kubectl get deploy -n <operator-ns>` |
| 4. Read the status conditions | `kubectl get <obj> -o json \| jq '.status'` |
| 5. Check events | `kubectl get events -n <ns> --field-selector involvedObject.name=<name>` |
| 6. Last resort: clear the finalizer | `kubectl patch … -p '{"metadata":{"finalizers":null}}'` |

### 9.4 Cascade modes — what happens to the children

```bash
kubectl delete deploy shop-api                                    # default: background cascade
kubectl delete deploy shop-api --cascade=background               # delete children AFTER the parent (default)
kubectl delete deploy shop-api --cascade=foreground                # delete children FIRST, then the parent
kubectl delete deploy shop-api --cascade=orphan                   # ⭐ delete only the parent; children survive
```

| Mode | Behaviour | When to use |
|---|---|---|
| `background` (default) | Parent removed immediately; the GC controller deletes children asynchronously | Normal |
| `foreground` | Parent enters `deletionInProgress`; children are deleted first; then the parent | When you must be sure the children are gone before continuing |
| `orphan` | Only the parent is removed; children get their `ownerReferences` stripped | **StatefulSet PVC-preserving upgrades**, adopting existing resources |

```bash
# ⭐ the classic: change a StatefulSet's volumeClaimTemplates without deleting the data
kubectl delete sts db --cascade=orphan         # the Pods and PVCs survive
kubectl apply -f db-new.yaml                   # recreate with the new template
kubectl rollout status sts/db
# the Pods are adopted back (their ownerReferences are re-created)
```

⚠️ `--cascade=orphan` on a Deployment leaves orphan ReplicaSets and Pods running with no controller. Clean them up:

```bash
kubectl delete rs -l app=shop-api              # ⛔ this deletes the pods too
kubectl get rs -o json | jq -r '.items[] | select(.metadata.ownerReferences==null) | .metadata.name'
```

### 9.5 Deleting safely at scale

```bash
# ⛔ never do this
kubectl delete pods --all -A

# ✅ the guarded version
kubectl delete pods -l app=shop-api -n shop --wait=false
kubectl get pods -l app=shop-api -n shop -o name | wc -l    # count first
kubectl get pods -l app=shop-api -n shop --dry-run=server   # preview (for apply; for delete, use -o name)
kubectl get pods -l app=shop-api -n shop -o name            # preview the list

# ✅ drain a namespace's Deployments by scaling to zero, not deleting
for d in $(kubectl get deploy -n shop -o name); do kubectl scale $d -n shop --replicas=0; done

# ✅ delete completed Jobs
kubectl delete jobs -n shop --field-selector=status.successful=1
kubectl get jobs -A -o json | jq -r '.items[] | select(.status.succeeded>0) | "\(.metadata.namespace) \(.metadata.name)"' \
  | while read ns j; do kubectl delete job $j -n $ns; done

# ✅ the krew plugin for controlled eviction (respects PDBs)
kubectl krew install evict-pod
kubectl evict-pod nginx -n shop --dry-run

# ✅ restart every Deployment in a namespace WITHOUT deleting anything
kubectl rollout restart deploy -n shop
kubectl get deploy -n shop -o name | xargs -n1 kubectl rollout restart -n shop
```

---

<a name="10-logs"></a>
## 10. Logs

### 10.1 The flags

```bash
kubectl logs nginx
kubectl logs nginx -n shop
kubectl logs nginx -c sidecar                    # a specific container (required if >1)
kubectl logs -f nginx                            # ⭐ follow
kubectl logs -f nginx -c api
kubectl logs --tail=100 nginx                    # ⭐ the last 100 lines
kubectl logs --tail=-1 nginx                     # all lines (no limit)
kubectl logs --since=10m nginx                   # the last 10 minutes
kubectl logs --since-time=2026-09-09T14:00:00Z nginx
kubectl logs --timestamps nginx                  # ⭐ prefix RFC3339 timestamps
kubectl logs --limit-bytes=1048576 nginx         # cap at 1 MiB
kubectl logs --previous nginx                    # ⭐⭐ the CRASHED container's logs
kubectl logs --previous nginx -c api
kubectl logs -l app=shop-api                     # ⭐ all pods matching a label
kubectl logs -l app=shop-api --all-containers
kubectl logs -l app=shop-api --max-log-requests=20   # raise the 5-pod default
kubectl logs -l app=shop-api --prefix            # prefix each line with the pod
kubectl logs -f -l app=shop-api --max-log-requests=20
kubectl logs deploy/shop-api                     # ⭐ one pod from the deployment
kubectl logs sts/db                              # one pod from the statefulset
kubectl logs job/backup --follow
kubectl logs cronjob/nightly                     # ⚠️ only the most recent run
kubectl logs nginx --pod-running-timeout=2m      # wait for a starting pod
kubectl logs nginx -o jsonpath='{.}' > app.log
```

### 10.2 `--previous` — the most valuable flag in kubectl

When a container crashes, its logs are **replaced** by the new container's logs. `--previous` (`-p`) reads the terminated container's log:

```bash
kubectl get pods -l app=shop-api
# NAME                       READY   STATUS             RESTARTS      AGE
# shop-api-7d4f8c9b6-abcde   0/1     CrashLoopBackOff   5 (30s ago)   10m

kubectl logs shop-api-7d4f8c9b6-abcde
# (empty, or the new container's first lines)

kubectl logs shop-api-7d4f8c9b6-abcde --previous
# ⭐ Exception in thread "main" java.lang.IllegalStateException:
#    Failed to load ApplicationContext …
#    Caused by: org.postgresql.util.PSQLException: FATAL: password authentication failed for user "shop"
```

```bash
# the crash-loop investigation loop
POD=$(kubectl get pods -l app=shop-api -o name --sort-by=.metadata.creationTimestamp | tail -1)
kubectl describe $POD | grep -A6 'Last State'
kubectl logs $POD --previous --tail=100
kubectl get events --field-selector involvedObject.name=${POD#pod/}
```

⚠️ **`--previous` only works if the container has restarted at least once** (RESTARTS ≥ 1). If the Pod itself was deleted and recreated, the old logs are gone — which is exactly why you need a cluster log aggregator (see [Project 7](./10-PROJECT-7-observability.md)).

### 10.3 Multi-container Pods

```bash
kubectl logs nginx                              # error: a container name must be specified for pod nginx,
                                                # choose one of: [app sidecar init]
kubectl logs nginx -c sidecar
kubectl logs nginx --all-containers             # ⭐ interleave everything
kubectl logs nginx --all-containers --prefix
kubectl logs nginx --all-containers=true -f
kubectl logs -l app=shop-api --all-containers --max-log-requests=20 -f
```

### 10.4 Init container logs

```bash
kubectl describe pod shop-api-7d4f8c9b6-abcde | grep -A10 'Init Containers'
kubectl logs shop-api-7d4f8c9b6-abcde -c wait-for-db            # ← the init container's name
kubectl logs shop-api-7d4f8c9b6-abcde -c wait-for-db --previous
kubectl logs shop-api-7d4f8c9b6-abcde --all-containers          # includes init containers
```

Init container stuck? That's `PodInitializing` or `Init:0/1`:

```bash
kubectl get pods -o custom-columns='NAME:.metadata.name,STATUS:.status.phase,INIT:.status.initContainerStatuses[*].state'
kubectl logs <pod> -c <init-container> --tail=50
```

### 10.5 Logs for a whole workload, and the right tool

`kubectl logs -l` has real limits: **5 concurrent streams by default**, it doesn't follow newly created Pods well, and it can't deduplicate. Use **stern**:

```bash
# install
kubectl krew install stern          # or: brew install stern

stern .                                        # everything in the current namespace
stern -n shop .                                # everything in shop
stern shop-api                                 # pods matching the regex "shop-api"
stern 'shop-(api|ui)'                          # ⭐ regex
stern -l app=shop-api                          # by label
stern -l app=shop-api -c api                   # one container
stern -l app=shop-api --exclude-container istio-proxy
stern -A -l app.kubernetes.io/part-of=shop     # across namespaces
stern shop-api --since=10m
stern shop-api --tail=200
stern shop-api -o json | jq -r '.message'
stern shop-api --template '{{.Message}} ({{.PodName}}/{{.ContainerName}})'
stern shop-api -i Error -i Exception           # ⭐ case-insensitive filter
stern shop-api -e 'health check'               # exclude
stern --color always shop-api | grep --color=auto -i error
stern shop-api > app.log 2>&1 &                # background capture
stern -n kube-system coredns --tail=100
```

```bash
# and for the cluster-wide view: Loki
kubectl logs -n loki -l app=loki --tail=100
# query via Grafana Explore:
#   {namespace="shop", app="shop-api"} |= "error"
#   {namespace="shop"} | json | level="ERROR" | line_format "{{.msg}}"
```

### 10.6 Where the logs actually live

```bash
# on the node, the container runtime writes them here
NODE=$(kubectl get pod nginx -o jsonpath='{.spec.nodeName}')
kubectl debug node/$NODE -it --image=busybox:1.37 -- chroot /host \
  ls -la /var/log/pods/
# /var/log/pods/shop_nginx-7d4f8c9b6-abcde_9f2a…/api/0.log
# /var/log/pods/shop_nginx-7d4f8c9b6-abcde_9f2a…/api/0.log.20260909-140211   ← rotated

# the symlink the kubelet exposes
ls -la /var/log/containers/
# nginx-7d4f8c9b6-abcde_shop_api-9f2a….log -> /var/log/pods/shop_nginx-…/api/0.log

# ⭐ the log format is JSON Lines, one entry per line:
head -2 /var/log/pods/shop_nginx-…/api/0.log
# {"log":"2026-09-09T14:20:41.123Z  INFO 1 --- [main] c.s.ShopApiApplication : Starting…\n",
#  "stream":"stdout","time":"2026-09-09T14:20:41.123456789Z"}

# rotation settings (kubelet)
kubectl get --raw /api/v1/nodes/learn-worker/proxy/configz | jq '.kubeletconfig | {containerLogMaxSize, containerLogMaxFiles}'
# {"containerLogMaxSize":"10Mi","containerLogMaxFiles":5}
# → 50 MiB of logs per container, then the oldest is deleted
```

> 🔑 **`kubectl logs` only shows what's currently on disk on that node.** After ~50 MiB or a Pod deletion, it's gone. **This is the single strongest argument for Loki/ELK** — see [Project 7](./10-PROJECT-7-observability.md).

### 10.7 Logs when the Pod won't start

```bash
# ImagePullBackOff → no logs at all; read the event
kubectl describe pod nginx | grep -A5 Events
# Warning  Failed  2m  kubelet  Failed to pull image "…": rpc error: … not found

# CreateContainerConfigError → no logs; the ConfigMap/Secret is missing
kubectl describe pod nginx | tail -5
# Warning  Failed  10s  kubelet  Error: configmap "app-config" not found

# CrashLoopBackOff → --previous
kubectl logs nginx --previous

# Init:Error / Init:CrashLoopBackOff → the INIT container's logs
kubectl logs nginx -c wait-for-db --previous

# PodScheduled=false → no logs, no container; it's a scheduling problem
kubectl describe pod nginx | grep -A5 Events
# Warning  FailedScheduling  3m  default-scheduler  0/3 nodes are available: 3 Insufficient cpu

# Terminating forever → the container isn't responding to SIGTERM
kubectl logs nginx -f          # watch what it's doing during the grace period
kubectl get pod nginx -o jsonpath='{.metadata.deletionTimestamp}'; echo
```

---

<a name="11-exec-attach-cp-and-port-forward"></a>
## 11. exec, attach, cp & port-forward

### 11.1 `exec`

```bash
kubectl exec -it nginx -- sh                     # ⭐ the one you'll type 10,000 times
kubectl exec -it nginx -- bash                   # only if bash exists (not in alpine/distroless)
kubectl exec -it nginx -c sidecar -- sh
kubectl exec -it nginx -n shop -- sh
kubectl exec nginx -- ls /                       # non-interactive, single command
kubectl exec nginx -- cat /etc/nginx/nginx.conf
kubectl exec nginx -- env | sort
kubectl exec nginx -- sh -c 'ls -la /app && du -sh /app'
kubectl exec deploy/shop-api -- sh               # ⭐ one pod from the deployment
kubectl exec -it db-0 -- psql -U shop            # StatefulSet pods are named db-0, db-1…
kubectl exec -it nginx --stdin --tty -- sh       # the long form of -it
kubectl exec nginx --container=api -- /bin/sh -c 'echo hi'
```

| Flag | Meaning |
|---|---|
| `-i` / `--stdin` | Keep STDIN open (pipe data in) |
| `-t` / `--tty` | Allocate a TTY (interactive shell, colour, line editing) |
| `-c` / `--container` | Which container (required if >1) |
| `--pod-running-timeout` | How long to wait for the Pod to be Running (default 1m) |

⚠️ **`--` is mandatory before the command** or kubectl treats your flags as its own:

```bash
kubectl exec nginx ls -la /
# error: unknown shorthand flag: 'l' in -la
kubectl exec nginx -- ls -la /          # ✅
```

**Piping data in and out:**

```bash
cat local.sql | kubectl exec -i db-0 -- psql -U shop -d shopdb          # ⭐ -i, NOT -it
kubectl exec db-0 -- pg_dump -U shop shopdb > dump.sql
kubectl exec nginx -- tar czf - /etc/nginx | tar xzf - -C ./extracted   # a directory out
tar czf - ./config | kubectl exec -i nginx -- tar xzf - -C /etc/nginx   # a directory in
echo 'hello' | kubectl exec -i nginx -- sh -c 'cat > /tmp/x'
kubectl exec -i nginx -- sh < script.sh                                 # run a whole script
kubectl cp dump.sql db-0:/tmp/dump.sql && kubectl exec -it db-0 -- psql -U shop -f /tmp/dump.sql
```

**⚠️ `-it` breaks stdin piping.** With a TTY allocated, the remote process gets terminal control characters and your piped bytes get mangled (psql sees `\r`, tar corrupts). **Use `-i` alone when piping.**

### 11.2 When there's no shell — distroless and scratch

```bash
kubectl exec -it shop-api-7d4f8c9b6-abcde -- sh
# OCI runtime exec failed: exec: "sh": executable file not found in $PATH: unknown

kubectl exec -it shop-api-7d4f8c9b6-abcde -- ls /
# OCI runtime exec failed: exec: "ls": executable file not found in $PATH: unknown
```

**This is by design** — distroless and scratch images have no shell and no coreutils. Four ways in:

```bash
# 1. ⭐ an ephemeral debug container sharing the target's namespaces
kubectl debug -it shop-api-7d4f8c9b6-abcde --image=nicolaka/netshoot --target=api -- bash
# inside: ps aux, ls /proc/1/root/app, curl localhost:8080/health

# 2. a debug container sharing the PID namespace only
kubectl debug -it shop-api-7d4f8c9b6-abcde --image=busybox:1.37 --target=api --share-processes -- sh
# inside: ps aux  → you see the Java process as PID 2

# 3. an ephemeral node-level shell
kubectl debug node/learn-worker -it --image=nicolaka/netshoot
# inside: chroot /host, crictl ps, journalctl -u kubelet

# 4. a copy of the Pod with a different image
kubectl debug -it shop-api-7d4f8c9b6-abcde --image=busybox:1.37 --copy-to=debug-copy --container=debug -- sh
```

### 11.3 `cp`

```bash
kubectl cp shop/app.jar nginx:/tmp/app.jar                 # local → pod
kubectl cp nginx:/tmp/app.jar ./app.jar                    # pod → local
kubectl cp nginx:/etc/nginx ./nginx-conf                   # a directory
kubectl cp ./nginx-conf nginx:/etc/nginx                   # a directory in
kubectl cp shop/app.jar nginx:/tmp/app.jar -c sidecar      # a specific container
kubectl cp nginx:/var/log/app.log ./app.log -n shop

# ⚠️ the remote path must NOT start with /
kubectl cp nginx:/tmp/app.jar ./          # ✅
kubectl cp nginx://tmp/app.jar ./         # ⛔
kubectl cp ./app.jar nginx:/tmp/app.jar   # ✅ (the local path may be absolute)
```

**`kubectl cp` is literally `tar` over `exec`. No tar in the image → no cp.**

```bash
kubectl cp ./app.jar nginx:/tmp/app.jar
# tar: removing leading '/' from member names       ← a warning, harmless
# tar: not found                                    ← ⛔ distroless/scratch has no tar

# the tarless workaround
cat ./app.jar | kubectl exec -i nginx -- sh -c 'cat > /tmp/app.jar'
kubectl exec nginx -- cat /tmp/app.jar > ./app.jar

# ⭐ permissions: cp runs as the container's user
kubectl exec nginx -- id
# uid=101(nginx) gid=101(nginx)
kubectl cp ./app.jar nginx:/app.jar
# tar: /app.jar: Permission denied
kubectl cp ./app.jar nginx:/tmp/app.jar          # ✅ /tmp is world-writable
```

### 11.4 `attach`

```bash
kubectl attach -it nginx                         # attach to PID 1's stdout/stdin
kubectl attach -it nginx -c api
kubectl attach nginx                             # non-interactive: just stream output
```

`attach` connects to an **already-running** container's stdio. It's rarely useful compared to `logs -f`: you get no history, and `Ctrl-C` may kill the process (there's no Docker-style detach sequence).

```bash
# the one real use: a long-running bare Pod you started without -it
kubectl run job --image=busybox:1.37 --restart=Never -- sh -c 'while true; do date; sleep 5; done'
kubectl attach -it job
```

### 11.5 `port-forward`

```bash
kubectl port-forward pod/nginx 8080:80                        # local 8080 → pod 80
kubectl port-forward pod/nginx 8080                           # local 8080 → pod 8080
kubectl port-forward svc/shop-api 8080:80                     # ⭐ via the Service (picks one endpoint)
kubectl port-forward deploy/shop-api 8080:8080                # ⭐ via the Deployment
kubectl port-forward sts/db 5432:5432
kubectl port-forward db-0 5432:5432                           # a specific StatefulSet pod
kubectl port-forward -n shop svc/grafana 3000:3000
kubectl port-forward -n monitoring svc/prometheus 9090:9090
kubectl port-forward -n loki svc/loki 3100:3100
kubectl port-forward -n argocd svc/argocd-server 8080:443
kubectl port-forward svc/shop-api 8080:80 9090:9090           # ⭐ several ports at once
kubectl port-forward pod/nginx 8080:80 --address=0.0.0.0      # ⭐ listen on all interfaces
kubectl port-forward pod/nginx 0:80                           # a random local port
```

**What port-forward actually is:**

```
your laptop ──► kubectl ──HTTPS/SPDY tunnel──► API server ──► kubelet ──► container netns ──► container port
```

It is **not** a Service, **not** a load balancer, and **not** durable.

| Property | Reality |
|---|---|
| Load balancing | ❌ One Pod, chosen at connect time |
| Survives Pod restart | ❌ Dies; you must reconnect |
| Survives node failure | ❌ |
| Multiple simultaneous connections | ✅ |
| UDP | ❌ **TCP only** |
| HTTP keep-alive | ⚠️ Often breaks — the tunnel resets idle connections |
| Reachable from other machines | Only with `--address=0.0.0.0` |
| Bandwidth | Limited by the API server |
| Authentication | Uses your kubeconfig identity |

**The keep-alive problem — the #1 port-forward complaint:**

```bash
curl http://localhost:8080/api/items      # works
sleep 60
curl http://localhost:8080/api/items      # curl: (56) Recv failure: Connection reset by peer
```

Fixes:

```bash
# 1. ⭐ an auto-restarting wrapper
while true; do kubectl port-forward -n shop svc/shop-api 8080:8080; echo "restarting…"; sleep 2; done

# 2. a socat relay
kubectl port-forward svc/shop-api 18080:8080 &
socat TCP-LISTEN:8080,fork,reuseaddr TCP:127.0.0.1:18080

# 3. disable client-side keepalive
curl -H 'Connection: close' http://localhost:8080/api/items

# 4. for anything real, use an Ingress (see Project 6)
```

```bash
# debug it
kubectl port-forward pod/nginx 8080:80 -v=8 2>&1 | head -20
# Forwarding from 127.0.0.1:8080 -> 80
# Handling connection for 8080
# error: lost connection to pod          ← ⭐ the Pod died or was evicted

lsof -i :8080                            # what's using the port
ss -ltnp | grep 8080
```

### 11.6 `proxy`

```bash
kubectl proxy --port=8001                       # ⭐ an unauthenticated local proxy to the API
kubectl proxy --address=0.0.0.0 --accept-hosts='^.*$' --port=8001
kubectl proxy --www=./static/                   # serve a static UI too

# then curl without any auth
curl -s localhost:8001/api/v1/namespaces/default/pods | jq '.items[].metadata.name'
curl -s localhost:8001/api/v1/nodes | jq '.items[].status.conditions[] | select(.type=="Ready")'
curl -s localhost:8001/version
curl -s localhost:8001/metrics | grep apiserver_request_total | head -5
curl -s localhost:8001/api/v1/namespaces/kube-system/pods/etcd-learn-control-plane/log | tail -20
curl -s localhost:8001/openapi/v3 | jq 'keys'
```

⚠️ **`kubectl proxy` exposes the API with YOUR credentials.** Never bind it to `0.0.0.0` on a shared machine. Never leave it running.

| | `kubectl proxy` | `kubectl port-forward` |
|---|---|---|
| Target | The **API server** | A **Pod or Service** |
| Multiplexing | Many resources | One target |
| Use for | Raw API exploration, the Dashboard | Reaching an app |

---

<a name="12-debugging-tools"></a>
## 12. Debugging tools

### 12.1 `kubectl debug` — four modes

```bash
# MODE 1: an ephemeral container in an existing Pod ⭐
kubectl debug -it nginx --image=nicolaka/netshoot --target=app -- bash
kubectl debug -it nginx --image=busybox:1.37 --target=app --share-processes -- sh
kubectl debug -it nginx --image=alpine:3.22 -c debugger -- sh          # name the container
kubectl debug nginx --image=busybox:1.37 -- sleep 3600                 # non-interactive

# MODE 2: a COPY of the Pod (when the original has no shell and you need its env/args)
kubectl debug nginx --image=busybox:1.37 --copy-to=nginx-debug --container=debug -it -- sh
kubectl debug nginx --copy-to=nginx-debug --set-image='*=busybox:1.37' -it -- sh
kubectl debug nginx --copy-to=nginx-debug --share-processes --container=debug --image=nicolaka/netshoot -it -- bash
kubectl debug nginx --copy-to=nginx-debug --replace                      # ⛔ deletes the original first

# MODE 3: a node-level shell ⭐⭐
kubectl debug node/learn-worker -it --image=nicolaka/netshoot
kubectl debug node/learn-worker -it --image=alpine:3.22 -- chroot /host sh
kubectl debug node/learn-worker -it --image=busybox:1.37 -- nsenter -t 1 -m -u -i -n -p sh

# MODE 4: with extra privileges
kubectl debug -it nginx --image=busybox:1.37 --target=app --profile=sysadmin
kubectl debug -it nginx --image=busybox:1.37 --target=app --profile=netadmin
```

**The debug profiles (stable since v1.30):**

| Profile | Grants | Use for |
|---|---|---|
| `general` (default) | Nothing special | Reading files, running CLI tools |
| `baseline` | The Pod's existing security context | Matching the app's privileges |
| `netadmin` | `NET_ADMIN`, `NET_RAW` | tcpdump, iptables, packet capture |
| `sysadmin` | `privileged: true` | Everything — strace, nsenter, the node's namespaces |

```bash
kubectl debug -it nginx --image=nicolaka/netshoot --target=app --profile=netadmin -- tcpdump -i any -n port 80
```

**⚠️ Ephemeral containers cannot be removed** — they exist until the Pod is deleted:

```bash
kubectl get pod nginx -o jsonpath='{.spec.ephemeralContainers[*].name}'; echo
# debugger
kubectl delete pod nginx                 # the only way to get rid of it
```

They also can't have probes, don't restart, and aren't rescheduled. They're for one-shot inspection.

### 12.2 The debugger images worth knowing

| Image | Size | Has | Best for |
|---|---|---|---|
| `busybox:1.37` | ~1.5 MB | sh, wget, nc, nslookup, top, ps | The universal fallback |
| `alpine:3.22` | ~8 MB | apk, sh, wget | When you need to `apk add` something |
| `nicolaka/netshoot` | ~400 MB | curl, dig, tcpdump, mtr, iperf3, socat, nmap, tshark, drill, httpie, jq, vim, stress-ng | ⭐ **All network debugging** |
| `curlimages/curl:8.10.1` | ~20 MB | curl, runs as uid 100 | HTTP checks in a non-root context |
| `praqma/network-multitool` | ~200 MB | Network tools + a webserver | Network labs |
| `bitnami/kubectl:1.33` | ~150 MB | kubectl | In-cluster automation, CI jobs |
| `willwill/dns-utils` | small | dig, host, nslookup | DNS-only debugging |

```bash
# the netshoot cookbook (inside the container)
kubectl debug -it <pod> --image=nicolaka/netshoot --target=app --profile=netadmin -- bash

cat /etc/resolv.conf                                  # nameserver 10.96.0.10, search shop.svc… ndots:5
dig +short shop-api.shop.svc.cluster.local            # ⭐ DNS resolution
dig shop-api.shop.svc.cluster.local SRV               # ⭐ the port too
dig @10.96.0.10 kubernetes.default.svc.cluster.local
curl -sv http://shop-api/health                       # in-cluster HTTP
curl -s http://localhost:8080/health                  # the local app
tcpdump -i any -n port 5432 -c 20                     # ⭐ packet capture
tcpdump -i eth0 -w /tmp/capture.pcap                  # then kubectl cp it out
ss -ltnp                                              # what's listening
ip route; ip addr                                     # routing
iptables -t nat -L -n                                 # DNAT rules (needs netadmin)
mtr -n -c 10 10.96.0.1                                # latency + loss per hop
iperf3 -c shop-api -p 5201                            # throughput
nmap -sT -p 80,443,8080 shop-api
openssl s_client -connect shop-api:443 -servername shop.example.com </dev/null 2>/dev/null | openssl x509 -noout -dates
stress-ng --cpu 2 --timeout 30s                       # load the container
```

### 12.3 Events — the first place to look

```bash
kubectl get events
kubectl get events -n shop
kubectl get events -A
kubectl get events --sort-by=.lastTimestamp            # ⭐ chronological
kubectl get events -A --sort-by=.lastTimestamp | tail -30
kubectl get events --field-selector type=Warning       # ⭐ problems only
kubectl get events -A --field-selector type=Warning --sort-by=.lastTimestamp
kubectl get events --field-selector involvedObject.kind=Pod
kubectl get events --field-selector involvedObject.name=shop-api-7d4f8c9b6-abcde
kubectl get events --field-selector reason=FailedMount
kubectl get events --field-selector reason=BackOff
kubectl get events --field-selector reportingComponent=kubelet
kubectl get events -o wide
kubectl get events -o custom-columns='TIME:.lastTimestamp,TYPE:.type,REASON:.reason,OBJECT:.involvedObject.name,MSG:.message'
kubectl describe pod nginx | grep -A20 Events          # ⭐ events scoped to one object
kubectl get events -A -w                               # watch live
kubectl get events -A -o json | jq -r '.items[] | select(.type=="Warning") | [.lastTimestamp,.reason,.involvedObject.name,.message] | @tsv' | column -t -s$'\t'
```

⚠️ **Events expire after 1 hour by default** (`--event-ttl` on the API server). If the problem started 3 hours ago, the events are gone — which is exactly what a log aggregator is for.

**The event reasons you must recognise on sight:**

| Reason | Type | Means | First check |
|---|---|---|---|
| `Scheduled` | Normal | The scheduler placed it | — |
| `Pulling` / `Pulled` | Normal | Image download | — |
| `Created` / `Started` | Normal | Container lifecycle | — |
| `SuccessfulCreate` | Normal | The RS made a Pod | — |
| `FailedScheduling` | Warning | No node fits | `describe pod` → the message says why |
| `FailedMount` | Warning | Volume problem | PVC status, StorageClass, CSI driver |
| `FailedAttachVolume` | Warning | Volume attached elsewhere | The orphan Pod on another node |
| `FailedCreatePodSandBox` | Warning | CNI / runtime failure | The node's kubelet + CNI logs |
| `BackOff` | Warning | CrashLoopBackOff backoff | `logs --previous` |
| `Unhealthy` | Warning | A probe failed | The probe config + the app's startup time |
| `Killing` | Normal | Termination started | — |
| `OOMKilling` | Warning | The kernel killed it | `dmesg` on the node, the memory limit |
| `Evicted` | Warning | Node pressure | `describe node` → DiskPressure/MemoryPressure |
| `Preempted` | Warning | A higher-priority Pod took its slot | PriorityClasses |
| `NodeNotReady` | Warning | The node stopped heartbeating | `describe node`, kubelet logs |
| `FailedCreate` | Warning | The controller couldn't make a Pod | Quotas, RBAC, admission webhooks |
| `ProbeError` | Warning | The probe itself errored | Timeouts, wrong port |
| `NetworkNotReady` | Warning | The CNI isn't up | The CNI DaemonSet |
| `DNSConfigForming` | Warning | Bad dnsConfig | `/etc/resolv.conf` in the Pod |
| `InvalidImageFormat` | Warning | Malformed image reference | The `image:` string |
| `ExceededGracePeriod` | Warning | Didn't terminate in time | `preStop`, SIGTERM handling |
| `SyncLoop` | Warning | The kubelet couldn't sync | The kubelet logs |

### 12.4 Getting onto a node

```bash
kubectl krew install node-shell
kubectl node-shell learn-worker
# (you're now root on the node, in the host namespaces)

# without the plugin
kubectl debug node/learn-worker -it --image=alpine:3.22 -- chroot /host sh
```

**Once you're on the node:**

```bash
# the container runtime
crictl version
crictl ps                                  # ⭐ running containers
crictl ps -a                               # including exited
crictl pods                                # the sandboxes
crictl images
crictl logs <container-id>
crictl inspect <container-id> | jq .info.runtimeSpec.process.env
crictl stats
crictl exec -it <container-id> sh
ctr -n k8s.io images ls | head
nerdctl -n k8s.io ps

# the kubelet
journalctl -u kubelet -f --since "10 min ago"
journalctl -u kubelet --grep=oom
journalctl -u containerd -f
systemctl status kubelet containerd
dmesg -T | grep -iE 'oom|killed process' | tail -20
dmesg -T | tail -50

# disk and memory
df -h / /var/lib/kubelet /var/lib/containerd
du -sh /var/lib/containerd/* | sort -h | tail
du -sh /var/log/pods/* | sort -h | tail -10
free -h
ps aux --sort=-%mem | head -10

# networking
ip addr; ip route
iptables -t nat -L -n | head -40
ss -ltnp
```

### 12.5 The kubectl-side diagnostics

```bash
kubectl cluster-info
kubectl cluster-info dump                             # ⭐ EVERYTHING, into a directory
kubectl cluster-info dump --namespaces shop --output-directory=./dump
kubectl cluster-info dump --all-namespaces --output-directory=./full-dump

kubectl get --raw='/readyz?verbose'                   # ⭐ the real health check
kubectl get --raw='/livez?verbose'
kubectl get --raw='/healthz?verbose'
kubectl get apiservices | grep -v True                # ⭐ broken aggregation layers

kubectl get nodes -o wide
kubectl top nodes                                     # needs metrics-server
kubectl top pods -A --sort-by=memory
kubectl top pods -A --containers --sort-by=cpu

kubectl get lease -n kube-node-lease                  # ⭐ node heartbeats
kubectl get lease -n kube-node-lease learn-worker -o jsonpath='{.spec.renewTime}'; echo
# 2026-09-09T15:02:11.123456Z    ← >40s old = the node is going NotReady

kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded
```

⚠️ `kubectl get componentstatuses` is **deprecated** and often returns nothing useful on managed clusters. Use `--raw='/readyz?verbose'`.

### 12.6 Ownership and inspection plugins

```bash
kubectl krew install tree lineage neat explore rbac-view who-can access-matrix \
                       resource-capacity df-pv view-secret

kubectl tree deploy shop-api
# NAMESPACE  NAME                              READY  REASON  AGE
# shop       Deployment/shop-api               True           3d
# shop       ├─ReplicaSet/shop-api-7d4f8c9b6   True           3d
# shop       │ └─Pod/shop-api-7d4f8c9b6-abcde  True           3d
# shop       │   ├─EndpointSlice/shop-api-a1b  -              3d
# shop       │   └─Lease/shop-api-abcde        -              3d
# shop       └─ReplicaSet/shop-api-5c8f9a1b2   True           1h
# shop         └─Pod/shop-api-5c8f9a1b2-fghij  True           1h

kubectl tree sts db
kubectl tree node learn-worker                        # what's running on it
kubectl tree ns shop
kubectl tree hpa shop-api
kubectl lineage -n shop                               # a text tree of everything

kubectl get deploy shop-api -o yaml | kubectl neat     # strip status/managedFields/uid

kubectl explore pods                                  # an interactive tree browser
kubectl rbac-view                                     # an HTML RBAC visualisation
kubectl who-can delete pods -n shop                   # ⭐ who has this permission?
kubectl who-can get secrets -A
kubectl access-matrix -n shop                         # ⭐ subjects × resources
kubectl access-matrix for sa:deployer -n shop
kubectl resource-capacity -n shop                     # ⭐ room left per node
kubectl resource-capacity --utilization --pods 20
kubectl df-pv -n shop                                 # ⭐ disk usage per PVC
kubectl view-secret db-creds -n shop --all            # ⭐ decode a secret
```

---

<a name="13-workloads"></a>
## 13. Workloads

### 13.1 Which workload controller?

| You're running… | Use | Why |
|---|---|---|
| A stateless web app, API, worker | **Deployment** | Rolling updates, rollback, scale |
| A database, Kafka, anything with an identity | **StatefulSet** | Stable names, stable storage, ordered ops |
| A node agent: logging, monitoring, CNI | **DaemonSet** | Exactly one Pod per node, automatically |
| A one-shot task: migration, backup, report | **Job** | Runs to completion, retries, parallelism |
| A scheduled task: nightly backup, cleanup | **CronJob** | Cron syntax, concurrency policies |
| A one-off debug Pod | `kubectl run --restart=Never` | No controller at all |
| An event-driven worker | Deployment + **KEDA ScaledObject** | Scale from 0 on queue depth |
| *(a bare Pod)* | ⛔ Never in production | No self-healing, no updates |

### 13.2 Pods

| `status.phase` | Means |
|---|---|
| `Pending` | Accepted by the API, but ≥1 container isn't running yet (scheduling, pulling, PVC binding) |
| `Running` | Bound to a node, **all** containers created; ≥1 is running or starting |
| `Succeeded` | All containers exited **0**, will not restart |
| `Failed` | All containers terminated, ≥1 exited non-zero |
| `Unknown` | The kubelet can't be reached (node NotReady) |

**But `phase` is not what you look at.** The `kubectl get` STATUS column is richer:

| STATUS | Means | Where to look |
|---|---|---|
| `ContainerCreating` | Sandbox being made: CNI, volumes, image | `describe pod` → Events |
| `PodInitializing` | Init containers running | `logs -c <init>` |
| `Init:0/1`, `Init:1/2` | Init container N of M | same |
| `Init:Error`, `Init:CrashLoopBackOff` | An init container failed | `logs -c <init> --previous` |
| `Running` | ✅ | — |
| `Terminating` | Deletion in progress | `deletionTimestamp`, `preStop` |
| `Completed` | Exit 0 (Jobs) | — |
| `Error` | Non-zero exit | `logs --previous` |
| `CrashLoopBackOff` | Repeated failures, exponential backoff (10s→20s→…→5m) | `logs --previous` |
| `ImagePullBackOff` / `ErrImagePull` | The image can't be fetched | `describe pod` → the exact error |
| `CreateContainerConfigError` | A referenced ConfigMap/Secret is missing | `describe pod` |
| `CreateContainerError` / `RunContainerError` | The runtime refused / it failed to start | `describe pod` |
| `OOMKilled` | Exceeded the memory limit | Exit code 137, `dmesg` on the node |
| `Evicted` | The node ran out of a resource | `describe pod` → the eviction message |
| `FailedScheduling` | No node fits | `describe pod` → the scheduler message |
| `NodeLost` / `Unknown` | The node disappeared | `kubectl get nodes` |
| `InvalidImageName` | Malformed `image:` | The manifest |
| `ExceededGracePeriod` | Didn't terminate in time | `terminationGracePeriodSeconds`, `preStop` |
| `UnexpectedAdmissionError` | An admission webhook rejected it after scheduling | The webhook |

```bash
kubectl get pods -o wide
kubectl describe pod nginx
kubectl get pod nginx -o yaml | kubectl neat

# the containers inside
kubectl get pod nginx -o json | jq '.status.containerStatuses[] | {name, ready, restartCount, state, lastState}'
kubectl get pod nginx -o jsonpath='{range .status.containerStatuses[*]}{.name}{"\t"}{.ready}{"\t"}{.restartCount}{"\t"}{.state}{"\n"}{end}'

# the conditions
kubectl get pod nginx -o json | jq '.status.conditions'
```

| Condition | Meaning |
|---|---|
| `PodScheduled` | A node has been assigned |
| `Initialized` | All init containers succeeded |
| `ContainersReady` | All containers pass their readiness probes |
| `Ready` | ContainersReady **AND** all readiness gates pass → it gets Service traffic |

**Restart policy:**

| `restartPolicy` | Supported by | Behaviour |
|---|---|---|
| `Always` (default) | Pod, Deployment, StatefulSet, DaemonSet | Restart on any exit, including 0 |
| `OnFailure` | Pod, **Job** | Restart only on non-zero exit |
| `Never` | Pod, Job | Don't restart; the Pod becomes Failed/Succeeded |

```bash
kubectl run x --image=busybox --restart=Never -- false       # a Pod that goes to Failed
kubectl run x --image=busybox --restart=OnFailure -- false   # a JOB that retries
kubectl run x --image=busybox -- true                        # a Deployment
```

**v1.28+ native sidecars** — an init container with `restartPolicy: Always`:

```yaml
initContainers:
  - name: istio-proxy
    image: istio/proxyv2:1.22
    restartPolicy: Always       # ⭐ starts first, runs for the Pod's whole life, stops last
```

### 13.3 Deployments

```bash
kubectl get deploy -o wide
# NAME       READY   UP-TO-DATE   AVAILABLE   AGE   CONTAINERS   IMAGES                           SELECTOR
# shop-api   3/3     3            3           3d    api          ghcr.io/3558bhk/shop-api:1.1.0   app=shop-api

kubectl describe deploy shop-api
kubectl rollout status deploy/shop-api
kubectl rollout history deploy/shop-api
kubectl rollout undo deploy/shop-api
kubectl rollout restart deploy/shop-api
kubectl scale deploy/shop-api --replicas=5
kubectl autoscale deploy/shop-api --min=2 --max=10 --cpu-percent=70
kubectl set image deploy/shop-api api=ghcr.io/3558bhk/shop-api:1.2.0
kubectl get rs -l app=shop-api
```

**The ownership chain:**

```
Deployment  shop-api
   │ owns (manages the ReplicaSets, performs the rolling update)
   ├── ReplicaSet  shop-api-7d4f8c9b6      (OLD — kept for rollback)
   │       └── Pod shop-api-7d4f8c9b6-abcde
   └── ReplicaSet  shop-api-5c8f9a1b2      (NEW — scaled up)
           ├── Pod shop-api-5c8f9a1b2-fghij
           └── Pod shop-api-5c8f9a1b2-klmno
```

**Never edit a ReplicaSet directly** — the Deployment controller undoes it.

| Field | Default | Meaning |
|---|---|---|
| `strategy.type` | `RollingUpdate` | or `Recreate` (kill all, then start all — downtime) |
| `maxSurge` | 25% | How many EXTRA Pods above `replicas` during the update |
| `maxUnavailable` | 25% | How many Pods may be unavailable during the update |
| `minReadySeconds` | 0 | How long a new Pod must stay Ready before counting as Available |
| `progressDeadlineSeconds` | 600 | After this, the Deployment is marked `Progressing=False` |
| `revisionHistoryLimit` | 10 | How many old ReplicaSets to keep for rollback |

```bash
kubectl get deploy shop-api -o jsonpath='{.spec.strategy}'; echo
# {"type":"RollingUpdate","rollingUpdate":{"maxSurge":"25%","maxUnavailable":"25%"}}

# ⭐ the zero-downtime settings
kubectl patch deploy shop-api --type=merge -p '{
  "spec":{"strategy":{"type":"RollingUpdate","rollingUpdate":{"maxSurge":1,"maxUnavailable":0}},
           "minReadySeconds":30,"progressDeadlineSeconds":600,"revisionHistoryLimit":10}}'
```

**An orphan ReplicaSet is a symptom:**

```bash
kubectl get rs -A -o json | jq -r '.items[]
  | select(.metadata.ownerReferences == null)
  | "\(.metadata.namespace)/\(.metadata.name)  replicas=\(.status.replicas // 0)"'
```

### 13.4 StatefulSets

```bash
kubectl get sts -o wide
kubectl describe sts db
kubectl rollout status sts/db
kubectl rollout undo sts/db
kubectl scale sts/db --replicas=5
kubectl delete pod db-2                        # recreated with the SAME name and SAME PVC
kubectl exec -it db-0 -- psql -U postgres -c 'select 1'
```

| Guarantee | What it gives you |
|---|---|
| **Stable network identity** | `db-0`, `db-1`, `db-2` — always the same names, via a headless Service |
| **Stable storage** | `data-db-0` PVC is bound to Pod `db-0` forever |
| **Ordered deployment** | `db-0` → Running+Ready → `db-1` → … |
| **Ordered scaling** | 3→5 creates `db-3` then `db-4`; 5→3 deletes `db-4` then `db-3` |
| **Ordered rolling update** | Highest ordinal first: `db-2` → `db-1` → `db-0` |

```yaml
spec:
  serviceName: db-headless          # ⭐ REQUIRED — must be a headless Service
  podManagementPolicy: OrderedReady # or Parallel (all at once — faster, less safe)
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      partition: 0                  # ⭐ only ordinals ≥ partition are updated → canary
      maxUnavailable: 1             # v1.24+
  persistentVolumeClaimRetentionPolicy:      # ⭐ v1.27+ stable
    whenDeleted: Delete                      # or Retain (the default)
    whenScaled: Retain                       # or Delete
```

```bash
# ⭐ partition-based canary: update only ordinal 2
kubectl patch sts db --type=merge -p '{"spec":{"updateStrategy":{"rollingUpdate":{"partition":2}}}}'
kubectl set image sts/db postgres=postgres:17.4-alpine
kubectl get pods -l app=db -o custom-columns='NAME:.metadata.name,IMAGE:.spec.containers[0].image'
# db-0   postgres:17-alpine       ← unchanged
# db-1   postgres:17-alpine       ← unchanged
# db-2   postgres:17.4-alpine     ← ⭐ canary
kubectl patch sts db --type=merge -p '{"spec":{"updateStrategy":{"rollingUpdate":{"partition":0}}}}'

# ⭐ the immutable-fields workaround
kubectl patch sts db -p '{"spec":{"volumeClaimTemplates":[{"metadata":{"name":"data"},"spec":{"resources":{"requests":{"storage":"20Gi"}}}}]}}'
# ⛔ Forbidden: updates to statefulset spec for fields other than 'replicas', 'ordinals',
#    'template', 'updateStrategy', 'persistentVolumeClaimRetentionPolicy' and 'minReadySeconds' are forbidden
kubectl delete sts db --cascade=orphan          # Pods + PVCs survive
kubectl apply -f db-new.yaml                    # recreate with the new template
kubectl rollout status sts/db
```

### 13.5 DaemonSets

```bash
kubectl get ds -A
kubectl describe ds log-agent
# Desired Number of Nodes Scheduled: 3
# Current Number of Nodes Scheduled: 3
# Number of Nodes Misscheduled:      0
# Number of Ready Nodes:             3
# Updated Number of Nodes Scheduled: 3
# Number of Unavailable Nodes:       0

kubectl rollout status ds/log-agent
kubectl rollout undo ds/log-agent
kubectl set image ds/log-agent fluentbit=fluent/fluent-bit:3.3
kubectl get pods -l app=log-agent -o wide            # one per node
kubectl get ds -A -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,DESIRED:.status.desiredNumberScheduled,READY:.status.numberReady,MISSCHEDULED:.status.numberMisscheduled'
```

**DaemonSets bypass the scheduler** (the controller sets `nodeName` directly), which is why:
- They need the `node.kubernetes.io/unschedulable:NoSchedule` toleration to run on cordoned nodes.
- `kubectl cordon` doesn't stop them.
- They ignore most affinity rules.

```yaml
spec:
  template:
    spec:
      tolerations:
        - {key: node-role.kubernetes.io/control-plane, operator: Exists, effect: NoSchedule}
      hostNetwork: true                         # ⭐ common for CNI/monitoring agents
      dnsPolicy: ClusterFirstWithHostNet        # ⭐ REQUIRED when hostNetwork: true
      priorityClassName: system-node-critical   # ⭐ never evicted
      volumes:
        - {name: varlog, hostPath: {path: /var/log}}
        - {name: containers, hostPath: {path: /var/lib/docker/containers}}
```

`numberMisscheduled > 0` means a Pod is running on a node that shouldn't have one (a selector changed, or the node's labels did).

### 13.6 Jobs

```bash
kubectl get jobs
kubectl describe job db-migrate
kubectl logs job/db-migrate -f
kubectl logs job/db-migrate --all-containers
kubectl get pods -l job-name=db-migrate
kubectl delete job db-migrate
```

| Field | Meaning | Gotcha |
|---|---|---|
| `completions` | How many successful Pods are needed | `null` = any single success completes the Job |
| `parallelism` | How many Pods run concurrently | Must be ≤ `completions` in Indexed mode |
| `backoffLimit` | Retries before the Job fails | Counts **Pod** failures, not container restarts |
| `activeDeadlineSeconds` | Timeout for the whole Job | The Pod gets the `DisruptionTarget` condition |
| `ttlSecondsAfterFinished` | Auto-delete after completion | Needs the TTL controller (on by default) |
| `completionMode: Indexed` | Each Pod gets `JOB_COMPLETION_INDEX` | For sharded work |
| `suspend: true` | Created but not started | ⭐ used by Kueue and staged rollouts |
| `podFailurePolicy` | Retry/fail on specific exit codes | ⭐ v1.31+ stable |

```yaml
spec:
  backoffLimit: 3
  activeDeadlineSeconds: 600
  ttlSecondsAfterFinished: 300
  parallelism: 1
  completions: 1
  completionMode: NonIndexed
  podFailurePolicy:
    rules:
      - action: FailJob
        onExitCodes: {containerName: migrate, operator: NotIn, values: [0, 3]}
      - action: Ignore                                  # don't count against backoffLimit
        onPodConditions: [{type: DisruptionTarget}]
  template:
    spec:
      restartPolicy: Never           # ⭐ MUST be Never or OnFailure — NOT Always
      containers:
        - name: migrate
          image: ghcr.io/3558bhk/shop-api:1.2.0
          command: ["./migrate","-path","file:///migrations","-database","$(DB_URL)","up"]
```

```bash
# ⭐ the indexed / sharded pattern
cat <<'EOF' | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata: {name: reindex}
spec:
  completions: 10
  parallelism: 3
  completionMode: Indexed
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: worker
          image: busybox:1.37
          command: ["sh","-c","echo processing shard $JOB_COMPLETION_INDEX; sleep 10"]
EOF
kubectl get pods -l job-name=reindex -o custom-columns='NAME:.metadata.name,INDEX:.metadata.labels.batch\.kubernetes\.io/job-completion-index,STATUS:.status.phase'

# suspend / resume
kubectl patch job reindex -p '{"spec":{"suspend":true}}'
kubectl patch job reindex -p '{"spec":{"suspend":false}}'

# ⭐ run a Job and WAIT for it in a script
JOB=smoke-$(date +%s)
kubectl create job $JOB --image=curlimages/curl:8.10.1 -- curl -sf http://shop-api/health
kubectl wait --for=condition=complete job/$JOB --timeout=120s && kubectl logs job/$JOB
kubectl wait --for=condition=failed   job/$JOB --timeout=120s && { kubectl logs job/$JOB; exit 1; }
```

### 13.7 CronJobs

```bash
kubectl get cronjobs
kubectl describe cronjob nightly-backup
kubectl patch cronjob nightly-backup -p '{"spec":{"suspend":true}}'      # ⭐ pause it
kubectl patch cronjob nightly-backup -p '{"spec":{"suspend":false}}'     # resume
kubectl create job manual-$(date +%s) --from=cronjob/nightly-backup      # ⭐ trigger it NOW
kubectl get cronjob nightly-backup -o jsonpath='{.spec.schedule}'; echo
kubectl get cronjob nightly-backup -o jsonpath='{.status.lastScheduleTime}'; echo
kubectl get cronjob nightly-backup -o jsonpath='{.status.lastSuccessfulTime}'; echo
kubectl get cronjob nightly-backup -o jsonpath='{.status.active}'; echo
```

```yaml
spec:
  schedule: "30 2 * * *"              # standard 5-field cron
  timeZone: "Asia/Kolkata"            # ⭐ stable since v1.27
  concurrencyPolicy: Forbid           # Allow | Forbid | Replace
  startingDeadlineSeconds: 300
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      backoffLimit: 2
      activeDeadlineSeconds: 3600     # ⭐ ALWAYS set this on a CronJob
      ttlSecondsAfterFinished: 86400
      template:
        spec:
          restartPolicy: OnFailure
          containers: [{name: backup, image: ghcr.io/3558bhk/db-backup:1.0.0}]
```

| `concurrencyPolicy` | Behaviour | Use for |
|---|---|---|
| `Allow` (default) | Multiple Jobs run concurrently | Idempotent, parallel-safe tasks |
| **`Forbid`** | Skip the new run if the old one is still going | ⭐ Backups, DB maintenance |
| `Replace` | Kill the running Job, start the new one | "Latest wins" (a metrics scrape) |

**⭐ The timezone question — the #1 CronJob gotcha:**

```bash
kubectl get cronjob nightly-backup -o jsonpath='{.spec.timeZone}'; echo
# (empty) → the schedule runs in the KUBE-CONTROLLER-MANAGER's timezone = UTC

kubectl run tz --image=busybox:1.37 --rm -it --restart=Never -- date -u
# Tue Sep  9 09:32:11 UTC 2026                ← the cluster clock
TZ=Asia/Kolkata date
# Tue Sep 09 15:02:11 IST 2026                ← your clock, 5:30 ahead

# so "30 2 * * *" means 02:30 UTC = 08:00 IST. Fix it explicitly:
kubectl patch cronjob nightly-backup --type=merge -p '{"spec":{"timeZone":"Asia/Kolkata"}}'
```

⚠️ Kubernetes cron does **not** support `@hourly`, `@daily`, `@reboot`, or 6-field (seconds) syntax. Standard 5-field Vixie cron only.

⚠️ `startingDeadlineSeconds: nil` (the default) means the controller **skips** any run more than 100 schedules behind — e.g. after a long control-plane outage, your daily backup silently never runs again. Set it explicitly.

**Cron syntax:**

```
┌───────── minute        (0-59)
│ ┌─────── hour          (0-23)
│ │ ┌───── day of month  (1-31)
│ │ │ ┌─── month         (1-12 or JAN-DEC)
│ │ │ │ ┌─ day of week   (0-6 or SUN-SAT, 0=Sunday)
│ │ │ │ │
* * * * *

*/5 * * * *        every 5 minutes       0 9 * * 1-5      09:00 Monday–Friday
0 * * * *          every hour            0 0 1 * *        midnight on the 1st
30 2 * * *         02:30 daily           0 0 * * 0        midnight every Sunday
```

### 13.8 Rollouts — the complete command set

```bash
# status
kubectl rollout status deploy/shop-api
kubectl rollout status deploy/shop-api --timeout=300s
kubectl rollout status sts/db
kubectl rollout status ds/log-agent -w

# history
kubectl rollout history deploy/shop-api
# deployment.apps/shop-api
# REVISION  CHANGE-CAUSE
# 1         <none>
# 2         release 1.1.0
# 3         release 1.2.0
kubectl rollout history deploy/shop-api --revision=2      # ⭐ the full YAML of that revision
kubectl rollout history sts/db
kubectl rollout history ds/log-agent

# undo
kubectl rollout undo deploy/shop-api                      # back to the previous revision
kubectl rollout undo deploy/shop-api --to-revision=1
kubectl rollout undo sts/db --to-revision=2
kubectl rollout undo ds/log-agent --dry-run=server

# restart ⭐ the safe way to recycle every Pod
kubectl rollout restart deploy/shop-api
kubectl rollout restart deploy -n shop                    # everything in a namespace
kubectl rollout restart sts/db
kubectl rollout restart ds/log-agent
kubectl get deploy -n shop -o name | xargs -n1 kubectl rollout restart -n shop

# pause / resume — batch several changes into ONE rollout
kubectl rollout pause deploy/shop-api
kubectl set image deploy/shop-api api=x:2
kubectl set resources deploy/shop-api --limits=cpu=2
kubectl annotate deploy/shop-api kubernetes.io/change-cause="release 2.0" --overwrite
kubectl rollout resume deploy/shop-api                    # ⭐ one rollout for all three

# CHANGE-CAUSE — make history readable
kubectl annotate deploy/shop-api kubernetes.io/change-cause="v1.2.0 — fix N+1 query" --overwrite
kubectl set image deploy/shop-api api=x:2 --record        # ⚠️ --record is DEPRECATED
```

**How `rollout history` works:** each revision is stored as a **ReplicaSet with `.spec.replicas: 0`**, annotated `deployment.kubernetes.io/revision`. `undo` copies that RS's `spec.template` back into the Deployment.

```bash
kubectl get rs -l app=shop-api -o custom-columns=\
'REV:.metadata.annotations.deployment\.kubernetes\.io/revision,NAME:.metadata.name,REPLICAS:.spec.replicas,IMAGE:.spec.template.spec.containers[0].image' \
--sort-by='{.metadata.annotations.deployment\.kubernetes\.io/revision}'
# REV  NAME                    REPLICAS  IMAGE
# 1    shop-api-5c8f9a1b2      0         ghcr.io/3558bhk/shop-api:1.0.0
# 2    shop-api-7d4f8c9b6      0         ghcr.io/3558bhk/shop-api:1.1.0
# 3    shop-api-9a2b3c4d5      3         ghcr.io/3558bhk/shop-api:1.2.0    ← current
```

⚠️ `revisionHistoryLimit: 0` destroys your ability to roll back. Never set it below 3.

### 13.9 Scaling

```bash
kubectl scale deploy/shop-api --replicas=5
kubectl scale deploy/shop-api --replicas=0              # ⭐ stop it without deleting
kubectl scale sts/db --replicas=5
kubectl scale rs/shop-api-7d4f8c9b6 --replicas=3        # ⚠️ the Deployment undoes this
kubectl scale -f deploy.yaml --replicas=5
kubectl scale deploy/shop-api --replicas=5 --current-replicas=3   # ⭐ compare-and-swap
kubectl scale deploy --all --replicas=1 -n shop         # ⛔ careful
```

⚠️ **An HPA and `kubectl scale` fight each other.** The HPA reconciles every 15s and undoes your manual scale.

```bash
# ✅ the right way to pin a Deployment under an HPA
kubectl patch hpa shop-api --type=merge -p '{"spec":{"minReplicas":5,"maxReplicas":5}}'

# ✅ slow the scale-down so it can't flap
kubectl patch hpa shop-api --type=merge -p '{"spec":{"behavior":{"scaleDown":{
  "stabilizationWindowSeconds":3600,
  "policies":[{"type":"Percent","value":10,"periodSeconds":60}]}}}}'
```

⚠️ **`replicas` in your manifest + an HPA = the value snaps back on every `apply`.** Delete `replicas` from the manifest. See [Project 2](./05-PROJECT-2-deployment-service.md).

```bash
# wait for a scale to settle
kubectl scale deploy/shop-api --replicas=5
kubectl rollout status deploy/shop-api --timeout=180s
kubectl wait --for=condition=Available deploy/shop-api --timeout=180s
```

---

<a name="14-services-and-networking"></a>
## 14. Services & networking

### 14.1 Service types

```bash
kubectl get svc -A
kubectl describe svc shop-api
kubectl get endpointslices -l kubernetes.io/service-name=shop-api
kubectl get endpoints shop-api          # the legacy object, still populated
```

| Type | Reachable from | Mechanism |
|---|---|---|
| `ClusterIP` (default) | Inside the cluster only | A virtual IP, DNAT'd by kube-proxy / the CNI / IPVS |
| `NodePort` | Anything that can reach a node | A port in **30000–32767** on every node |
| `LoadBalancer` | The internet | NodePort + a cloud LB provisioned by the CCM |
| `ExternalName` | Inside the cluster | **A CNAME**, no proxying, no endpoints |

```yaml
apiVersion: v1
kind: Service
metadata: {name: shop-api, namespace: shop}
spec:
  type: ClusterIP
  selector: {app: shop-api}
  ports:
    - name: http           # ⭐ ALWAYS name your ports — required for multi-port and Gateway API
      port: 80             # what clients connect to
      targetPort: 8080     # what the container listens on
      protocol: TCP
    - name: metrics
      port: 9090
      targetPort: 9090
  sessionAffinity: None          # or ClientIP
  sessionAffinityConfig: {clientIP: {timeoutSeconds: 3600}}
```

```bash
# NodePort
kubectl expose deploy shop-api --type=NodePort --port=80 --target-port=8080
kubectl get svc shop-api -o jsonpath='{.spec.ports[0].nodePort}'; echo        # 31234
kubectl patch svc shop-api -p '{"spec":{"ports":[{"port":80,"targetPort":8080,"nodePort":30080}]}}'
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
curl http://$NODE_IP:30080/health
docker exec learn-control-plane curl -s http://localhost:30080/health          # on kind

# LoadBalancer
kubectl expose deploy shop-api --type=LoadBalancer --port=80 --target-port=8080
kubectl get svc shop-api -w
# shop-api   LoadBalancer   10.96.123.45   <pending>     80:31234/TCP   5s
# shop-api   LoadBalancer   10.96.123.45   20.40.60.80   80:31234/TCP   45s
# ⚠️ <pending> forever = no cloud controller manager (kind/minikube without a tunnel)
```

**MetalLB for a local cluster:**

```bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.8/config/manifests/metallb-native.yaml
cat <<'EOF' | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata: {name: pool, namespace: metallb-system}
spec: {addresses: ["172.18.255.200-172.18.255.250"]}   # ⭐ inside the kind docker network
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata: {name: l2, namespace: metallb-system}
spec: {ipAddressPools: ["pool"]}
EOF
```

**ExternalName — a CNAME to something outside the cluster:**

```yaml
apiVersion: v1
kind: Service
metadata: {name: rds, namespace: shop}
spec:
  type: ExternalName
  externalName: shopdb.c9akciqx.ap-south-1.rds.amazonaws.com
```

```bash
kubectl run dns --image=busybox:1.37 --rm -it --restart=Never -- nslookup rds.shop.svc.cluster.local
# rds.shop.svc.cluster.local  canonical name = shopdb.c9akciqx.ap-south-1.rds.amazonaws.com
# ⚠️ no selector, no endpoints, no port mapping, no TLS SNI rewriting
```

### 14.2 Headless Services — `clusterIP: None`

| | Normal Service | Headless Service |
|---|---|---|
| `clusterIP` | A virtual IP | `None` |
| kube-proxy rules | Created | **Not created** |
| DNS `A` record for the name | The virtual IP | **All the Pod IPs** |
| DNS for individual Pods | ❌ | ✅ `pod-0.svc.ns.svc.cluster.local` |
| Load balancing | By kube-proxy | **By the client** |
| Use for | Normal apps | StatefulSets, client-side LB (gRPC!), discovery |

```bash
kubectl get svc db-headless -o jsonpath='{.spec.clusterIP}'; echo     # None
kubectl run dns --image=busybox:1.37 --rm -it --restart=Never -- nslookup db-headless.db.svc.cluster.local
# Address 1: 10.244.1.15 db-0.db-headless.db.svc.cluster.local
# Address 2: 10.244.2.21 db-1.db-headless.db.svc.cluster.local
# Address 3: 10.244.3.18 db-2.db-headless.db.svc.cluster.local
```

> 🔑 **gRPC needs a headless Service.** gRPC multiplexes many requests over ONE HTTP/2 connection. A ClusterIP Service balances per-connection, so all your gRPC calls hit one Pod. Headless + client-side LB fixes it.

### 14.3 Endpoints and EndpointSlices

```bash
kubectl get endpoints shop-api
# NAME       ENDPOINTS                                          AGE
# shop-api   10.244.1.9:8080,10.244.2.19:8080,10.244.3.7:8080   3d

kubectl get endpointslices -l kubernetes.io/service-name=shop-api
kubectl get endpointslices -l kubernetes.io/service-name=shop-api -o json | jq '
  .items[].endpoints[] | {ip: .addresses[0], ready: .conditions.ready,
                          serving: .conditions.serving, terminating: .conditions.terminating,
                          node: .nodeName, zone: .zone, pod: .targetRef.name}'
```

**⛔ Empty endpoints = the Service is broken.** The #1 networking bug in Kubernetes:

```bash
kubectl get endpoints shop-api
# NAME       ENDPOINTS   AGE
# shop-api   <none>      3d          ← ⚠️ NOTHING to route to
```

Four causes, in order of likelihood:

```bash
# 1. The selector doesn't match any Pod's labels
kubectl get svc shop-api -o jsonpath='{.spec.selector}'; echo       # {"app":"shop-api"}
kubectl get pods -l app=shop-api                                    # nothing?
kubectl get pods --show-labels
# shop-api-7d4f8c9b6-abcde   1/1   Running   app=shopapi,tier=backend   ← ⛔ "shopapi" not "shop-api"

# 2. The Pods aren't Ready (readiness probe failing)
kubectl get pods -l app=shop-api
# shop-api-7d4f8c9b6-abcde   0/1   Running   0   5m     ← Ready 0/1 → excluded from endpoints

# 3. targetPort doesn't match what the container listens on
kubectl get svc shop-api -o jsonpath='{.spec.ports[0].targetPort}'; echo       # 8080
kubectl exec deploy/shop-api -- sh -c 'netstat -ltn 2>/dev/null || ss -ltn'
# LISTEN  0  128  *:80        ← ⛔ it listens on 80

# 4. The Pod is in a different namespace (Services and Pods must be co-located)
kubectl get pods -A -l app=shop-api
```

### 14.4 DNS

```bash
kubectl get svc -n kube-system kube-dns -o jsonpath='{.spec.clusterIP}'; echo    # 10.96.0.10
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl get cm -n kube-system coredns -o jsonpath='{.data.Corefile}'
```

| Thing | FQDN | Example |
|---|---|---|
| A Service | `<svc>.<ns>.svc.cluster.local` | `shop-api.shop.svc.cluster.local` |
| A headless Service's Pod | `<pod>.<svc>.<ns>.svc.cluster.local` | `db-0.db-headless.db.svc.cluster.local` |
| A StatefulSet Pod | `<sts>-<n>.<headless-svc>.<ns>.svc.cluster.local` | `db-0.db-headless.db.svc.cluster.local` |
| An Ingress host | Public DNS (Route53, Cloudflare), **not** cluster DNS | `shop.example.com` |

```bash
kubectl exec deploy/shop-api -- cat /etc/resolv.conf
# nameserver 10.96.0.10
# search shop.svc.cluster.local svc.cluster.local cluster.local
# options ndots:5

# from a Pod in "shop", these are equivalent:
#   shop-api   |   shop-api.shop   |   shop-api.shop.svc   |   shop-api.shop.svc.cluster.local
# from a Pod in "db", you MUST qualify:
#   shop-api.shop  ✅        shop-api  ⛔ → shop-api.db.svc.cluster.local (doesn't exist)
```

⚠️ **`ndots:5` is a performance trap.** A name with fewer than 5 dots is tried against **every search domain first**:

```bash
# curl https://api.stripe.com/ from a Pod makes FOUR DNS queries:
# 1. api.stripe.com.shop.svc.cluster.local   → NXDOMAIN
# 2. api.stripe.com.svc.cluster.local        → NXDOMAIN
# 3. api.stripe.com.cluster.local            → NXDOMAIN
# 4. api.stripe.com.                         → ✅ finally
```

```yaml
# fix 1: lower ndots
spec:
  dnsConfig:
    options:
      - {name: ndots, value: "2"}                 # ⭐
      - {name: timeout, value: "2"}
      - {name: attempts, value: "2"}
      - {name: single-request-reopen}             # fixes the glibc parallel A/AAAA bug
```

```bash
# fix 2: the trailing dot skips search entirely
curl https://api.stripe.com./v1/charges            # ⭐ 1 query
```

| `dnsPolicy` | Behaviour |
|---|---|
| `ClusterFirst` (default) | Use CoreDNS |
| `ClusterFirstWithHostNet` | ⭐ **REQUIRED** when `hostNetwork: true` |
| `Default` | Inherit the NODE's `/etc/resolv.conf` |
| `None` | Use only `dnsConfig` |

```bash
# DNS debugging
kubectl run dns --image=nicolaka/netshoot --rm -it --restart=Never -- bash
#   dig +short shop-api.shop.svc.cluster.local
#   dig shop-api.shop.svc.cluster.local SRV
#   dig @10.96.0.10 kubernetes.default.svc.cluster.local

kubectl logs -n kube-system -l k8s-app=kube-dns --tail=50
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=50 | grep -ic 'SERVFAIL\|NXDOMAIN'
kubectl port-forward -n kube-system svc/kube-dns 9153:9153 &
curl -s localhost:9153/metrics | grep coredns_dns_request
```

### 14.5 Ingress

```bash
kubectl get ingress -A
kubectl describe ingress shop
kubectl get ingressclass
kubectl get ingressclass -o custom-columns='NAME:.metadata.name,CONTROLLER:.spec.controller,DEFAULT:.metadata.annotations.ingressclass\.kubernetes\.io/is-default-class'
```

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: shop
  namespace: shop
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "60"
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: nginx             # ⭐ ALWAYS set this explicitly
  tls:
    - hosts: [shop.example.com, api.shop.example.com]
      secretName: shop-tls            # ⭐ created by cert-manager
  rules:
    - host: shop.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend: {service: {name: shop-ui, port: {number: 80}}}
    - host: api.shop.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend: {service: {name: shop-api, port: {number: 80}}}
```

| `pathType` | Meaning |
|---|---|
| `Exact` | Must match the URL path exactly |
| `Prefix` | ⭐ Matches on `/`-separated elements. `/api` matches `/api`, `/api/`, `/api/v1`, but **not** `/apix` |
| `ImplementationSpecific` | Whatever the IngressClass decides |

```bash
# install ingress-nginx on kind
cat <<'EOF' > kind-ingress.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
    extraPortMappings:
      - {containerPort: 80,  hostPort: 80,  protocol: TCP}
      - {containerPort: 443, hostPort: 443, protocol: TCP}
  - role: worker
  - role: worker
EOF
kind create cluster --name learn --config kind-ingress.yaml

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx -n ingress-nginx --create-namespace \
  --set controller.publishService.enabled=true \
  --set controller.nodeSelector."ingress-ready"=true \
  --set controller.kind=DaemonSet \
  --set controller.service.type=NodePort \
  --set controller.service.nodePorts.http=30080 \
  --set controller.service.nodePorts.https=30443

kubectl get pods,svc -n ingress-nginx
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=50

# ⭐ test without DNS
curl -sk https://localhost:30443/ -H 'Host: shop.example.com'
curl -s  http://localhost:30080/health -H 'Host: api.shop.example.com'

# inspect the generated nginx config
kubectl exec -n ingress-nginx deploy/ingress-nginx-controller -- nginx -T 2>/dev/null \
  | grep -A5 'server_name shop.example.com'
```

### 14.6 Gateway API — the successor

```bash
kubectl get gateways.gateway.networking.k8s.io -A     # ⭐ group-qualified: "gateway" is ambiguous
kubectl get gatewayclasses
kubectl get httproutes -A
kubectl get grpcroutes -A
kubectl describe httproute shop-api
```

| Ingress | Gateway API |
|---|---|
| One resource kind | `GatewayClass`, `Gateway`, `HTTPRoute`, `GRPCRoute`, `TCPRoute`, `TLSRoute`, `ReferenceGrant`, `BackendTLSPolicy` |
| Annotations for everything | **Typed, portable fields** |
| L7 HTTP only (officially) | L4 + L7 |
| No cross-namespace delegation | ✅ `ReferenceGrant` + route attachment |
| No traffic splitting | ✅ `weight` per backend |
| No portable header rewriting | ✅ `HTTPRouteFilter` |

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: {name: shop-gw, namespace: shop}
spec:
  gatewayClassName: cilium        # or istio, envoy-gateway, nginx
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      allowedRoutes:
        namespaces: {from: Selector, selector: {matchLabels: {gateway: shop}}}
    - name: https
      protocol: HTTPS
      port: 443
      hostname: "*.shop.example.com"
      tls: {mode: Terminate, certificateRefs: [{kind: Secret, name: shop-tls}]}
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: shop-api, namespace: shop, labels: {gateway: shop}}
spec:
  parentRefs: [{name: shop-gw}]
  hostnames: ["api.shop.example.com"]
  rules:
    - matches: [{path: {type: PathPrefix, value: /api}}]
      filters:
        - type: RequestHeaderModifier
          requestHeaderModifier: {set: [{name: X-Env, value: prod}]}
        - type: URLRewrite
          urlRewrite: {path: {type: ReplacePrefixMatch, replacePrefixMatch: /}}
      backendRefs:
        - {name: shop-api, port: 8080, weight: 90}          # ⭐ canary!
        - {name: shop-api-canary, port: 8080, weight: 10}
```

```bash
kubectl get httproute shop-api -o jsonpath='{.status.parents[0].conditions}' | jq .
# [{"type":"Accepted","status":"True"},{"type":"ResolvedRefs","status":"True"}]
# ⭐ ResolvedRefs=False → a referenced Service or Secret wasn't found or isn't permitted
```

### 14.7 NetworkPolicy

⚠️ **A NetworkPolicy does nothing unless a CNI that enforces it is installed.** `kind`'s default `kindnet` **does not** enforce NetworkPolicies. You need Calico, Cilium, or Antrea.

```bash
kubectl get pods -n kube-system | grep -E 'calico|cilium|antrea'
kubectl get netpol -A
kubectl describe netpol default-deny -n shop
```

```yaml
# ⭐ the default-deny baseline everyone should have
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: default-deny-ingress, namespace: shop}
spec:
  podSelector: {}              # ⭐ EMPTY selector = ALL pods in this namespace
  policyTypes: [Ingress]       # Ingress only; egress is still allowed
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: allow-ui-and-prometheus, namespace: shop}
spec:
  podSelector: {matchLabels: {app: shop-api}}
  policyTypes: [Ingress]
  ingress:
    - from:
        - podSelector: {matchLabels: {app: shop-ui}}       # same namespace
        - namespaceSelector:                                # another namespace (OR)
            matchLabels: {kubernetes.io/metadata.name: monitoring}
          podSelector:                                      # …AND within this item
            matchLabels: {app.kubernetes.io/name: prometheus}
      ports:
        - {protocol: TCP, port: 8080}
```

**Selector semantics — the part everyone gets wrong:**

| Selector field | Scope |
|---|---|
| `spec.podSelector` | Which pods **this policy applies to** (empty `{}` = all in the namespace) |
| `ingress[].from[].podSelector` | Pods **in the same namespace** as the policy |
| `ingress[].from[].namespaceSelector` | **All pods** in the matching namespaces |
| `podSelector` + `namespaceSelector` as **separate list items** | **OR** (union) |
| `podSelector` + `namespaceSelector` in the **same item** | **AND** (intersection) |
| `ipBlock` | CIDR ranges, with `except` |

```yaml
# ⛔ OR — allows ALL pods in monitoring AND ALL shop-ui pods here
from:
  - podSelector: {matchLabels: {app: shop-ui}}
  - namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: monitoring}}

# ✅ AND — only the prometheus pods in the monitoring namespace
from:
  - namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: monitoring}}
    podSelector: {matchLabels: {app.kubernetes.io/name: prometheus}}
```

⚠️ **NetworkPolicy has NO concept of "deny".** It's allow-list only: once any policy selects a Pod for a direction, all traffic in that direction is denied **except** what's explicitly allowed.

```bash
# ⭐ test a policy from a real Pod
kubectl run test --image=nicolaka/netshoot --rm -it --restart=Never -n shop -- \
  curl -sv --max-time 5 http://shop-api/health
# ✅ allowed → 200
# ⛔ blocked → curl: (28) Connection timed out after 5001 milliseconds
```

> 🔑 **"Connection refused" vs "timeout".** Refused = something answered with a RST (the Service exists but has no endpoints, or the app isn't listening). Timeout = packets are being **dropped** (a NetworkPolicy, a firewall, or a wrong route). This one distinction will save you hours.

---

<a name="15-configuration-configmaps-and-secrets"></a>
## 15. Configuration: ConfigMaps & Secrets

### 15.1 Creating ConfigMaps — all five ways

```bash
# 1. literals
kubectl create configmap app-config \
  --from-literal=LOG_LEVEL=debug \
  --from-literal=FEATURE_X=true \
  --from-literal=MAX_CONNECTIONS=100

# 2. a single file (the KEY is the filename)
kubectl create configmap app-props --from-file=application.properties
kubectl create configmap app-props --from-file=app.properties=./config/application.properties   # ⭐ rename the key
kubectl create configmap nginx-conf --from-file=nginx.conf

# 3. a directory (each file becomes a key)
kubectl create configmap app-config --from-file=./config/

# 4. an env file
printf 'LOG_LEVEL=debug\nDB_HOST=postgres.db.svc.cluster.local\nDB_PORT=5432\n' > .env
kubectl create configmap app-config --from-env-file=.env

# 5. ⭐ declaratively — the only way for GitOps
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata: {name: app-config, namespace: shop}
data:
  LOG_LEVEL: "debug"                     # ⭐ quote numbers and booleans!
  FEATURE_X: "true"
  application.properties: |
    server.port=8080
    spring.datasource.url=jdbc:postgresql://postgres:5432/shop
  nginx.conf: |
    server { listen 80; location / { proxy_pass http://api:8080; } }
immutable: false
EOF

# ⭐ the idempotent create-or-update
kubectl create configmap app-config --from-literal=LOG_LEVEL=debug \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl get cm app-config -o yaml
kubectl describe cm app-config
kubectl edit cm app-config
kubectl patch cm app-config --type=merge -p '{"data":{"LOG_LEVEL":"trace"}}'
kubectl delete cm app-config
```

⚠️ **Every ConfigMap value is a STRING:**

```yaml
data:
  PORT: 8080          # ⛔ cannot unmarshal number into Go struct field of type string
  ENABLED: true       # ⛔ same
  PORT: "8080"        # ✅
  ENABLED: "true"     # ✅
```

### 15.2 Consuming ConfigMaps — three ways

```yaml
spec:
  containers:
    - name: api
      # WAY 1: individual env vars
      env:
        - name: LOG_LEVEL
          valueFrom:
            configMapKeyRef: {name: app-config, key: LOG_LEVEL, optional: false}
        - name: FEATURE_X
          valueFrom:
            configMapKeyRef: {name: app-config, key: FEATURE_X, optional: true}

      # WAY 2: every key as an env var
      envFrom:
        - configMapRef: {name: app-config}
        - secretRef: {name: db-creds}
        - prefix: SHOP_                       # ⭐ prefix every key
          configMapRef: {name: app-config}

      # WAY 3: ⭐ as files in a volume
      volumeMounts:
        - {name: config, mountPath: /etc/app, readOnly: true}      # the WHOLE directory is replaced
        - {name: nginx-conf, mountPath: /etc/nginx/nginx.conf, subPath: nginx.conf}   # ONE file
  volumes:
    - name: config
      configMap:
        name: app-config
        defaultMode: 0444                     # ⭐ octal; 0644 in YAML needs quotes: "0644"
        optional: false
        items:                                # ⭐ cherry-pick which keys become files
          - {key: application.properties, path: application.properties}
          - {key: nginx.conf, path: nginx.conf, mode: 0400}
    - name: nginx-conf
      configMap: {name: app-config}
```

| Way | Auto-updates when the ConfigMap changes? |
|---|---|
| `env` / `envFrom` | ⛔ **Never** — the Pod must be restarted |
| `volumeMounts` (whole dir) | ✅ Yes, in **~60s** (kubelet sync period + cache TTL) |
| `volumeMounts` with `subPath` | ⛔ **Never** — subPath mounts are static |
| `immutable: true` ConfigMap | ⛔ Never (and it can't be changed at all) |

**⭐ The canonical way to roll Pods on a config change — a checksum annotation:**

```yaml
spec:
  template:
    metadata:
      annotations:
        checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
# (in Helm — see Project 14)
```

```bash
# plain YAML: do it in your CI
HASH=$(kubectl get cm app-config -n shop -o jsonpath='{.data}' | sha256sum | cut -c1-16)
kubectl patch deploy shop-api -n shop --type=merge \
  -p "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"checksum/config\":\"$HASH\"}}}}}"
# → the pod template changed → a rolling update starts

# or the blunt instrument
kubectl rollout restart deploy/shop-api -n shop
```

### 15.3 Secrets

```bash
kubectl create secret generic db-creds --from-literal=username=shop --from-literal=password='S3cret!'
kubectl create secret generic tls-cert --from-file=tls.crt=./fullchain.pem --from-file=tls.key=./privkey.pem
kubectl create secret tls shop-tls --cert=./fullchain.pem --key=./privkey.pem    # ⭐ typed helper
kubectl create secret docker-registry ghcr-creds \
  --docker-server=ghcr.io --docker-username=3558Bhk \
  --docker-password=$GHCR_TOKEN --docker-email=me@example.com
kubectl create secret generic ssh-key --from-file=id_rsa=~/.ssh/id_ed25519 --from-file=known_hosts
kubectl create secret generic app-config --from-file=./secrets/
kubectl create secret generic env-secrets --from-env-file=.env.secret

kubectl get secrets -o custom-columns='NAME:.metadata.name,TYPE:.type,DATA:.data,AGE:.metadata.creationTimestamp'
kubectl describe secret db-creds                 # shows sizes, NOT values
```

**Decoding:**

```bash
kubectl get secret db-creds -o yaml
# data:
#   password: UzNjcmV0IQ==
#   username: c2hvcA==

kubectl get secret db-creds -o jsonpath='{.data.password}' | base64 -d; echo
kubectl get secret db-creds -o go-template='{{range $k,$v := .data}}{{$k}}={{$v | base64decode}}{{"\n"}}{{end}}'
kubectl view-secret db-creds --all                        # the plugin, nicer

# ⭐ decode EVERY secret in a namespace
kubectl get secrets -n shop -o json | jq -r '.items[] | .metadata.name as $n |
  (.data // {}) | to_entries[] | "\($n)\t\(.key)\t\(.value|@base64d)"' | column -t -s$'\t'
```

**Secret types:**

| `type` | Used for | Required keys |
|---|---|---|
| `Opaque` (default) | Anything | — |
| `kubernetes.io/service-account-token` | SA tokens (auto-created) | `token`, `ca.crt`, `namespace` |
| `kubernetes.io/dockerconfigjson` | **`imagePullSecrets`** | `.dockerconfigjson` |
| `kubernetes.io/dockercfg` | Legacy registry auth | `.dockercfg` |
| `kubernetes.io/basic-auth` | Username/password | `username`, `password` |
| `kubernetes.io/ssh-auth` | SSH keys | `ssh-privatekey` |
| `kubernetes.io/tls` | TLS certs | `tls.crt`, `tls.key` |
| `bootstrap.kubernetes.io/token` | Node bootstrap tokens | `token-id`, `token-secret` |

```bash
# ⭐ the registry pull secret
kubectl create secret docker-registry ghcr-creds \
  --docker-server=ghcr.io --docker-username=3558Bhk --docker-password=$GHCR_TOKEN
kubectl patch serviceaccount default -n shop -p '{"imagePullSecrets":[{"name":"ghcr-creds"}]}'
# or per-Pod:  spec: { imagePullSecrets: [{name: ghcr-creds}] }

kubectl get secret ghcr-creds -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d | jq .
# {"auths":{"ghcr.io":{"username":"3558Bhk","password":"ghp_…","auth":"MzU1OEJoazpnaHBf…"}}}
```

### 15.4 Secrets are NOT encrypted by default

```bash
kubectl get secret db-creds -o jsonpath='{.data.password}' | base64 -d
# S3cret!      ← base64 is ENCODING, not ENCRYPTION. Anyone with `get secrets` RBAC can read it.
```

**Three layers of protection:**

```bash
# 1. RBAC — the practical one
kubectl create role secret-reader --verb=get,list --resource=secrets -n shop
kubectl auth can-i get secrets -n shop
kubectl who-can get secrets -n shop

# 2. Encryption at rest in etcd — the real one (an API server flag)
#    --encryption-provider-config=/etc/kubernetes/enc/enc.yaml
```
```yaml
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources: ["secrets"]
    providers:
      - aescbc: {keys: [{name: key1, secret: <base64-32-bytes>}]}
      - identity: {}                # ⭐ fallback so existing plaintext secrets still read
```
```bash
# then RE-WRITE every secret to encrypt it:
kubectl get secrets -A -o json | kubectl replace -f -
# verify:
ETCDCTL_API=3 etcdctl --cacert=… --cert=… --key=… get /registry/secrets/shop/db-creds | hexdump -C | head
# k8s:enc:aescbc:v1:key1:…        ← ✅ encrypted on disk

# 3. ⭐ Don't put them in Kubernetes at all
#    → External Secrets Operator + AWS Secrets Manager / Vault / GCP Secret Manager
#    → SOPS + age, sealed at rest in Git
#    see Project 14, Task 14.6
```

### 15.5 The `_FILE` convention — the Docker-to-Kubernetes bridge

Many official images (Postgres, Redis, MySQL, RabbitMQ, GitLab) support `<VAR>_FILE`:

```yaml
env:
  - name: POSTGRES_PASSWORD_FILE          # ⭐ not POSTGRES_PASSWORD
    value: /etc/secrets/password
volumeMounts:
  - {name: db-creds, mountPath: /etc/secrets, readOnly: true}
volumes:
  - name: db-creds
    secret:
      secretName: db-creds
      items: [{key: password, path: password}]   # ⭐ the key becomes the filename
```

The password then never appears in `kubectl describe pod`, `/proc/<pid>/environ`, `crictl inspect`, `ps e`, or a crash dump.

```bash
kubectl exec db-0 -- cat /etc/secrets/password      # ✅
kubectl exec db-0 -- env | grep -i password         # ⭐ should show NOTHING
```

### 15.6 `immutable` — the performance and safety win

```bash
kubectl patch cm app-config --type=merge -p '{"immutable":true}'
kubectl patch cm app-config --type=merge -p '{"data":{"A":"2"}}'
# ⛔ configmaps "app-config" is invalid: data: Forbidden: field is immutable when `immutable` is set
kubectl delete cm app-config && kubectl create cm app-config --from-literal=A=2   # ✅ replace it
```

**Why it matters at scale:** the kubelet watches every ConfigMap mounted by Pods on its node. With 1,000 ConfigMaps × 100 Pods that's enormous watch traffic. `immutable: true` ConfigMaps are **excluded from the watch** — a documented reduction in watch load of up to ~90% for config-heavy clusters.

### 15.7 Limits and gotchas

| Gotcha | Detail |
|---|---|
| **1 MiB limit** per ConfigMap/Secret | etcd's max request size |
| base64 inflates by ~33% | The limit applies to the stored (encoded) form |
| Mounting a ConfigMap **replaces the whole directory** | Use `subPath` for one file — but then it won't auto-update |
| `subPath` mounts never update | By design |
| Env vars never update | Restart the Pod |
| The symlink swap is atomic | `..data` → `..2026_09_09_14_20_11.123/` — read files, don't cache inodes |
| A ConfigMap in use can't always be deleted | `configmap "x" is forbidden: … in use` |

```bash
kubectl create configmap big --from-file=huge.txt      # huge.txt is 2 MB
# ⛔ ConfigMap "big" is invalid: data: Too long: must have at most 1048576 bytes

kubectl get cm app-config -o json | wc -c              # how big is it?
kubectl get secret db-creds -o json | jq '.data | to_entries | map({key, len: (.value|length)})'

# ⭐ the symlink mechanism — why "cat in a loop" sees updates but "open once" doesn't
kubectl exec deploy/shop-api -- ls -la /etc/app
# lrwxrwxrwx  ..data -> ..2026_09_09_14_20_11.123456789
# lrwxrwxrwx  application.properties -> ..data/application.properties
```

---

<a name="16-storage"></a>
## 16. Storage

### 16.1 The object model

```
StorageClass  "fast-ssd"        ← the MENU of storage types (cluster-scoped)
      │
      │ dynamically provisions (or you create PVs by hand)
      ▼
PersistentVolume  "pvc-9f2a…"   ← an ACTUAL piece of storage (cluster-scoped)
      ▲
      │ binds 1:1
      │
PersistentVolumeClaim "data-db-0" ← a REQUEST for storage (namespaced)
      ▲
      │ mounted by
      │
Pod  db-0                        ← volumeMounts → volumes → claimName
```

```bash
kubectl get sc
kubectl get sc -o custom-columns='NAME:.metadata.name,PROVISIONER:.provisioner,RECLAIM:.reclaimPolicy,BINDING:.volumeBindingMode,EXPAND:.allowVolumeExpansion,DEFAULT:.metadata.annotations.storageclass\.kubernetes\.io/is-default-class'
# NAME                 PROVISIONER             RECLAIM   BINDING           EXPAND   DEFAULT
# standard (default)   rancher.io/local-path   Delete    Immediate         false    true
# fast-ssd             ebs.csi.aws.com         Retain    WaitForFirstCons  true     <none>

kubectl get pv
kubectl get pv -o custom-columns='NAME:.metadata.name,CAP:.spec.capacity.storage,ACCESS:.spec.accessModes,RECLAIM:.reclaimPolicy,STATUS:.status.phase,SC:.spec.storageClassName'
kubectl get pvc -n db
kubectl describe pvc data-db-0 -n db
kubectl describe pv pvc-9f2a1b3c
kubectl get csidrivers
kubectl get csinodes -o json | jq '.items[] | {node: .metadata.name, drivers: [.spec.drivers[].name]}'
kubectl get volumeattachment
```

| PV `status.phase` | Means |
|---|---|
| `Available` | Free, not yet bound |
| `Bound` | Bound to a PVC |
| `Released` | The PVC was deleted; the PV can't be re-bound automatically |
| `Failed` | Automatic reclamation failed |

| PVC `status.phase` | Means |
|---|---|
| `Pending` | No matching PV, or provisioning hasn't finished |
| `Bound` | ✅ |
| `Lost` | The underlying PV is gone |

### 16.2 Access modes

| Mode | Abbr | Meaning | Typical |
|---|---|---|---|
| `ReadWriteOnce` | RWO | One **node**, read-write | EBS, GCE PD, most block storage |
| `ReadOnlyMany` | ROX | Many nodes, read-only | Shared config, static content |
| `ReadWriteMany` | RWX | Many nodes, read-write | **NFS, CephFS, EFS, Azure Files** |
| `ReadWriteOncePod` | RWOP | One **Pod** (v1.29+ stable) | Databases — stronger than RWO |

⚠️ **RWO is per-NODE, not per-Pod.** Two Pods on the same node can both mount an RWO volume — exactly the corruption scenario RWOP was created to prevent.

```bash
# ⛔ the classic Multi-Attach error
kubectl describe pod db-0 | grep -A5 Events
# Warning  FailedAttachVolume  2m  attachdetach-controller
#   Multi-Attach error for volume "pvc-9f2a…" Volume is already used by pod(s) db-0-old (on node learn-worker)

kubectl get pods -A -o wide | grep db-0
kubectl get volumeattachment | grep pvc-9f2a
kubectl delete pod db-0-old --grace-period=0 --force     # ⚠️ ONLY after verifying the node is really dead
```

### 16.3 A complete storage example

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: uploads, namespace: shop}
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: fast-ssd          # ⭐ omit to use the default SC
  resources: {requests: {storage: 10Gi}}
  volumeMode: Filesystem              # or Block (a raw device)
  selector:                           # ⭐ only for STATIC provisioning
    matchLabels: {tier: ssd}
---
apiVersion: v1
kind: PersistentVolume
metadata: {name: manual-pv, labels: {tier: ssd}}
spec:
  capacity: {storage: 10Gi}
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: fast-ssd
  claimRef:                           # ⭐ pre-bind to a specific PVC
    namespace: shop
    name: uploads
  nfs: {server: 10.0.0.5, path: /exports/uploads}
  mountOptions: [nfsvers=4.1, hard, noatime]
  nodeAffinity:                       # ⭐ required for local volumes
    required:
      nodeSelectorTerms:
        - matchExpressions: [{key: kubernetes.io/hostname, operator: In, values: [learn-worker]}]
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-ssd
  annotations: {storageclass.kubernetes.io/is-default-class: "false"}
provisioner: ebs.csi.aws.com
parameters: {type: gp3, iopsPerGB: "50", encrypted: "true"}
reclaimPolicy: Retain                 # Delete | Retain
allowVolumeExpansion: true            # ⭐ required to grow PVCs later
volumeBindingMode: WaitForFirstConsumer   # ⭐ delayed binding = topology-aware
mountOptions: [noatime]
```

| `volumeBindingMode` | Behaviour | Use for |
|---|---|---|
| `Immediate` | Provision as soon as the PVC is created | Non-topology-aware storage (NFS) |
| **`WaitForFirstConsumer`** | Wait until a Pod using the PVC is scheduled, then provision **in that Pod's zone** | ⭐ Everything zonal (EBS, PD, local disks) |

> 🔑 **`WaitForFirstConsumer` prevents the classic bug:** a PVC created in `ap-south-1a`, a Pod scheduled to a node in `ap-south-1b`, a volume that can't attach. With delayed binding, the volume is created where the Pod lands.

### 16.4 Reclaim policies

| Policy | When the PVC is deleted | Use for |
|---|---|---|
| `Delete` (default for dynamic) | The PV **and the underlying volume** are destroyed | Ephemeral data, dev |
| `Retain` | The PV goes to `Released`; **the data survives**; you clean up manually | ⭐ Databases, anything valuable |
| `Recycle` | ⛔ Deprecated & removed | Never |

```bash
kubectl patch pv pvc-9f2a1b3c -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
# after a Retain'd PV is Released, to reuse it:
kubectl patch pv pvc-9f2a1b3c -p '{"spec":{"claimRef":null}}'
kubectl get pv pvc-9f2a1b3c        # → Available
```

⚠️ `reclaimPolicy` on the StorageClass only affects **new** PVs. Existing PVs keep whatever they were created with.

### 16.5 Expanding a PVC

```bash
kubectl get sc fast-ssd -o jsonpath='{.allowVolumeExpansion}'; echo     # true ← ⭐ REQUIRED
kubectl patch pvc uploads -n shop -p '{"spec":{"resources":{"requests":{"storage":"20Gi"}}}}'
kubectl get pvc uploads -n shop -w
# uploads  Bound  pvc-9f2a  10Gi  RWO  fast-ssd  3d
# uploads  Bound  pvc-9f2a  20Gi  RWO  fast-ssd  3d

# some filesystems need a Pod restart to resize online
kubectl get pvc uploads -n shop -o jsonpath='{.status.conditions}'; echo
# [{"type":"FileSystemResizePending","message":"Waiting for user to (re-)start a Pod to finish file system resize"}]
kubectl rollout restart deploy/shop-api -n shop
kubectl exec deploy/shop-api -- df -h /uploads
```

⚠️ **You can only GROW a PVC, never shrink it.** And `accessModes`, `storageClassName`, and `volumeMode` are immutable.

```bash
kubectl patch pvc uploads -p '{"spec":{"accessModes":["ReadWriteMany"]}}'
# ⛔ spec is immutable after creation except resources.requests for bound claims

# to "change" the StorageClass: create a new PVC and copy the data
kubectl create -f uploads-ssd.yaml
kubectl run copy --image=alpine:3.22 --restart=Never --overrides='{
  "spec":{"containers":[{"name":"copy","image":"alpine:3.22","command":["sleep","3600"],
    "volumeMounts":[{"name":"old","mountPath":"/old"},{"name":"new","mountPath":"/new"}]}],
    "volumes":[{"name":"old","persistentVolumeClaim":{"claimName":"uploads"}},
               {"name":"new","persistentVolumeClaim":{"claimName":"uploads-ssd"}}]}}'
kubectl exec copy -- sh -c 'cp -a /old/. /new/ && sync'
kubectl delete pod copy
# then repoint your Deployment at uploads-ssd
```

### 16.6 StatefulSet volumeClaimTemplates

```bash
kubectl get pvc -n db
# data-db-0   Bound   pvc-9f2a1b   10Gi   RWO   fast-ssd   3d
# data-db-1   Bound   pvc-3c4d5e   10Gi   RWO   fast-ssd   3d
# ⭐ naming: <volumeClaimTemplate name>-<sts name>-<ordinal>

kubectl get sts db -o jsonpath='{.spec.persistentVolumeClaimRetentionPolicy}'; echo
# {"whenDeleted":"Retain","whenScaled":"Retain"}

# grow every replica's volume
for i in 0 1 2; do kubectl patch pvc data-db-$i -n db -p '{"spec":{"resources":{"requests":{"storage":"20Gi"}}}}'; done
kubectl get pvc -n db -o custom-columns='NAME:.metadata.name,REQUESTED:.spec.resources.requests.storage,ACTUAL:.status.capacity.storage'
```

| Behaviour | Default | Control |
|---|---|---|
| Delete the StatefulSet | **PVCs survive** | `persistentVolumeClaimRetentionPolicy.whenDeleted: Delete` |
| Scale down | **PVCs survive** | `persistentVolumeClaimRetentionPolicy.whenScaled: Delete` |
| Change `volumeClaimTemplates` | ⛔ Immutable | Delete with `--cascade=orphan`, re-apply |
| Grow an existing PVC | ✅ | Patch each PVC individually |

### 16.7 Volume types

| Type | Persistent? | Use for |
|---|---|---|
| `emptyDir` | ❌ Dies with the Pod | Scratch space, sidecar handoff, cache |
| `emptyDir: {medium: Memory}` | ❌ | **tmpfs** — RAM-backed, counts against the memory limit |
| `hostPath` | ⚠️ Dies with the node | DaemonSets reading `/var/log`; **never for app data** |
| `configMap` / `secret` / `serviceAccountToken` | — | Configuration |
| `persistentVolumeClaim` | ✅ | Everything real |
| `csi` | ✅ | Via a CSI driver |
| `downwardAPI` | — | Pod metadata as files |
| `projected` | — | Combine several sources into one mount |
| `local` | ✅ (node-bound) | Local NVMe/SSD — needs `nodeAffinity` |
| `nfs`, `iscsi`, `fc` | ✅ | Legacy in-tree drivers (mostly superseded by CSI) |

```yaml
volumes:
  - name: scratch
    emptyDir: {sizeLimit: 1Gi}          # ⭐ evict the Pod if it exceeds this
  - name: tmpfs
    emptyDir: {medium: Memory, sizeLimit: 256Mi}   # ⚠️ counts against the memory limit
  - name: podinfo
    downwardAPI:
      items:
        - {path: "labels", fieldRef: {fieldPath: metadata.labels}}
        - {path: "annotations", fieldRef: {fieldPath: metadata.annotations}}
        - {path: "cpu_limit", resourceFieldRef: {containerName: api, resource: limits.cpu}}
  - name: projected
    projected:
      sources:
        - configMap: {name: app-config}
        - secret: {name: db-creds}
        - serviceAccountToken: {path: token, audience: api, expirationSeconds: 3600}
  - name: host-logs
    hostPath: {path: /var/log, type: Directory}
```

```bash
# ⭐ emptyDir sizeLimit and the eviction it triggers
kubectl get pods -A -o json | jq -r '.items[] | select(.status.reason=="Evicted")
  | "\(.metadata.namespace)/\(.metadata.name): \(.status.message)"'
# shop/cache-warmer-abc: Pod ephemeral local storage usage exceeds the total limit of containers 1Gi.

# who's filling the node disk?
kubectl debug node/learn-worker -it --image=alpine:3.22 -- chroot /host sh -c \
  'du -sh /var/lib/kubelet/pods/* 2>/dev/null | sort -h | tail -10'
```

`hostPath.type` values: `""` (no checks), `DirectoryOrCreate`, `Directory`, `FileOrCreate`, `File`, `Socket`, `CharDevice`, `BlockDevice`.

### 16.8 Snapshots and restores (CSI)

```bash
kubectl get volumesnapshotclasses
kubectl get volumesnapshots -A
kubectl get volumesnapshotcontents
```

```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata: {name: csi-snapclass}
driver: ebs.csi.aws.com
deletionPolicy: Delete
---
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata: {name: db-snap-20260909, namespace: db}
spec:
  volumeSnapshotClassName: csi-snapclass
  source: {persistentVolumeClaimName: data-db-0}
---
# ⭐ restore into a NEW PVC
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: data-db-0-restored, namespace: db}
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: fast-ssd
  resources: {requests: {storage: 10Gi}}    # must be ≥ the snapshot's size
  dataSource:
    name: db-snap-20260909
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
```

```bash
kubectl get volumesnapshot db-snap-20260909 -n db -o jsonpath='{.status.readyToUse}'; echo      # true
kubectl get volumesnapshot db-snap-20260909 -n db -o jsonpath='{.status.restoreSize}'; echo     # 10Gi
```

### 16.9 The storage troubleshooting sequence

```bash
# 1. PVC Pending?
kubectl describe pvc uploads -n shop | grep -A10 Events
# "waiting for first consumer to be created before binding"   ← WaitForFirstConsumer, NORMAL
# "no persistent volumes available for this claim"            ← static provisioning mismatch
# "storageclass not found"                                    ← typo
# "exceeded quota"                                            ← ResourceQuota
# "provisioning failed: … Insufficient capacity"              ← the cloud AZ is full

# 2. Is the provisioner running?
kubectl get pods -A | grep -E 'csi|provisioner|local-path'
kubectl logs -n kube-system -l app=csi-provisioner --tail=50

# 3. Is the driver registered?
kubectl get csidrivers
kubectl get csinodes

# 4. VolumeAttachment stuck?
kubectl get volumeattachment
kubectl describe volumeattachment csi-abc123

# 5. Mount failing inside the Pod?
kubectl describe pod shop-api-… | grep -A5 Events
# FailedMount: MountVolume.SetUp failed for volume "config" : configmap "app-config" not found
# FailedMount: Unable to attach or mount volumes: unmounted volumes=[data], unattached volumes=[…]

# 6. Disk actually full?
kubectl exec deploy/shop-api -- df -h
kubectl df-pv
kubectl debug node/learn-worker -it --image=alpine:3.22 -- chroot /host df -h

# 7. Permissions?
kubectl exec deploy/shop-api -- id
kubectl exec deploy/shop-api -- ls -la /data
# a new PV is root-owned → set spec.securityContext.fsGroup, or chown in an initContainer
```

| Error | Cause | Fix |
|---|---|---|
| `storageclass "x" not found` | Typo | `kubectl get sc` |
| `no persistent volumes available` | Static provisioning: no PV matches size/accessMode/selector | Create a PV, or use a StorageClass |
| `waiting for first consumer` | `WaitForFirstConsumer` + no Pod yet | **Normal** — deploy the Pod |
| `exceeded quota: … requests.storage` | ResourceQuota | Raise the quota or shrink the PVC |
| `Multi-Attach error` | An RWO volume used by 2 Pods/nodes | Remove the orphan, or use RWOP |
| `MountVolume.SetUp failed … not found` | The ConfigMap/Secret is missing | Create it |
| `FileSystemResizePending` | The FS needs a Pod restart | `kubectl rollout restart` |
| `permission denied` writing to the volume | Root-owned PV | `fsGroup`, or `chown` in an initContainer |
| `rpc error: … AccessDenied` | The CSI driver's IAM role lacks permission | Fix the cloud IAM |

---

<a name="17-scheduling"></a>
## 17. Scheduling

### 17.1 The five mechanisms

| Mechanism | Direction | Strength | Use for |
|---|---|---|---|
| `nodeSelector` | Pod → Node | Hard | Simple label matching |
| `nodeAffinity` | Pod → Node | Hard **or** soft | Complex node matching |
| `podAffinity` / `podAntiAffinity` | Pod → Pod | Hard **or** soft | Co-locate / spread replicas |
| `taints` + `tolerations` | Node → Pod | Hard (repel) | Dedicated nodes, GPU, control plane |
| `topologySpreadConstraints` | Pod → topology | Hard **or** soft | Even distribution across zones/nodes |

> 🔑 **Affinity attracts. Taints repel.** A toleration *permits* a Pod to land on a tainted node — it does **not** make it land there. For dedicated nodes you need a toleration **AND** an affinity/nodeSelector.

### 17.2 nodeSelector and labels

```bash
kubectl label nodes learn-worker disktype=ssd
kubectl label nodes learn-worker disktype-                # the trailing dash REMOVES it
kubectl label nodes learn-worker disktype=nvme --overwrite
kubectl get nodes -l disktype=ssd
kubectl get nodes --show-labels
kubectl get nodes -L disktype -L topology.kubernetes.io/zone    # ⭐ labels as columns
```

```yaml
spec:
  nodeSelector:
    disktype: ssd
    kubernetes.io/arch: amd64
    topology.kubernetes.io/zone: ap-south-1a
```

### 17.3 nodeAffinity

```yaml
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:      # ⭐ HARD
        nodeSelectorTerms:                                  # terms are ORed
          - matchExpressions:                               # expressions within a term are ANDed
              - {key: disktype, operator: In, values: [ssd, nvme]}
              - {key: topology.kubernetes.io/zone, operator: In, values: [ap-south-1a, ap-south-1b]}
              - {key: node-role.kubernetes.io/control-plane, operator: DoesNotExist}
          - matchExpressions:
              - {key: dedicated, operator: In, values: [shop]}
      preferredDuringSchedulingIgnoredDuringExecution:      # ⭐ SOFT — scored, not required
        - weight: 100                                       # 1–100
          preference:
            matchExpressions: [{key: disktype, operator: In, values: [nvme]}]
        - weight: 50
          preference:
            matchFields: [{key: metadata.name, operator: In, values: [learn-worker]}]
```

**Operators:** `In`, `NotIn`, `Exists`, `DoesNotExist`, `Gt`, `Lt` (the last two only for numeric node labels, and only in `requiredDuring…`).

**"IgnoredDuringExecution" means:** if the node's labels change after scheduling, **the Pod is NOT evicted.** (`requiredDuringSchedulingRequiredDuringExecution` was never implemented.)

### 17.4 podAffinity / podAntiAffinity

```yaml
spec:
  affinity:
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:      # ⭐ HARD: never 2 replicas on one node
        - labelSelector: {matchLabels: {app: shop-api}}
          topologyKey: kubernetes.io/hostname
      preferredDuringSchedulingIgnoredDuringExecution:     # ⭐ SOFT: prefer different zones
        - weight: 100
          podAffinityTerm:
            labelSelector: {matchLabels: {app: shop-api}}
            topologyKey: topology.kubernetes.io/zone
    podAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:      # ⭐ co-locate with the cache
        - labelSelector: {matchLabels: {app: redis}}
          topologyKey: kubernetes.io/hostname
          namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: cache}}
```

| `topologyKey` | Spread unit |
|---|---|
| `kubernetes.io/hostname` | Per node |
| `topology.kubernetes.io/zone` | Per availability zone |
| `topology.kubernetes.io/region` | Per region |
| A custom label, e.g. `rack` | Per whatever you labelled |

⚠️ **Hard podAntiAffinity with `replicas > number of nodes` = permanently Pending:**

```bash
kubectl describe pod shop-api-… | grep -A3 Events
# FailedScheduling: 0/3 nodes are available: 3 node(s) didn't match pod anti-affinity rules.
#   preemption: 0/3 nodes are available: 3 No preemption victims found for incoming pod.
kubectl get nodes --no-headers | wc -l                              # 3
kubectl get deploy shop-api -o jsonpath='{.spec.replicas}'; echo    # 5 → ⛔ impossible
```

⚠️ **podAntiAffinity is expensive** — O(pods × nodes) in the scheduler. On large clusters prefer `topologySpreadConstraints`.

### 17.5 topologySpreadConstraints — the modern answer

```yaml
spec:
  topologySpreadConstraints:
    - maxSkew: 1                                     # ⭐ the allowed imbalance
      topologyKey: topology.kubernetes.io/zone       # spread across zones
      whenUnsatisfiable: DoNotSchedule               # ⭐ hard (ScheduleAnyway = soft)
      labelSelector: {matchLabels: {app: shop-api}}
      minDomains: 3                                  # treat the cluster as having ≥3 domains
      nodeAffinityPolicy: Honor                      # ⭐ respect nodeAffinity when counting
      nodeTaintsPolicy: Honor                        # ⭐ respect taints when counting
    - maxSkew: 1
      topologyKey: kubernetes.io/hostname            # …and across nodes within each zone
      whenUnsatisfiable: ScheduleAnyway
      labelSelector: {matchLabels: {app: shop-api}}
```

```bash
# ⭐ see the actual distribution
kubectl get nodes -L topology.kubernetes.io/zone -L kubernetes.io/hostname
for p in $(kubectl get pods -l app=shop-api -o name); do
  n=$(kubectl get $p -o jsonpath='{.spec.nodeName}')
  z=$(kubectl get node $n -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}')
  printf '%-45s %-18s %s\n' "$p" "$n" "$z"
done
```

**The arithmetic of `maxSkew` with `DoNotSchedule`:**

| Replicas | Domains | Possible? |
|---|---|---|
| 4 | 2 zones | ✅ 2/2 (skew 0) |
| 3 | 2 zones, `maxSkew: 1` | ⛔ 2/1 is skew 1 ✅ but the 3rd Pod can't go anywhere without exceeding it → use `maxSkew: 2` or `ScheduleAnyway` |
| 5 | 3 zones, `maxSkew: 1` | ✅ 2/2/1 |
| 6 | 3 zones, `maxSkew: 1` | ✅ 2/2/2 |

```bash
kubectl describe pod shop-api-… | grep -A3 Events
# FailedScheduling: 0/3 nodes are available:
#   1 node(s) didn't match pod topology spread constraints,
#   2 node(s) had untolerated taint {node-role.kubernetes.io/control-plane: }
```

### 17.6 Taints and tolerations

```bash
kubectl taint nodes learn-worker dedicated=shop:NoSchedule
kubectl taint nodes learn-worker dedicated=shop:NoSchedule-     # ⭐ the trailing dash REMOVES it
kubectl taint nodes learn-worker node.kubernetes.io/disk-pressure:NoSchedule-
kubectl describe node learn-worker | grep -A5 Taints
kubectl get nodes -o json | jq -r '.items[] | "\(.metadata.name): \(.spec.taints // [])"'
```

| Effect | Meaning |
|---|---|
| `NoSchedule` | New Pods without a toleration won't schedule here; **existing Pods stay** |
| `PreferNoSchedule` | The scheduler tries to avoid it, but will use it if it must |
| `NoExecute` | ⭐ New Pods won't schedule **AND existing non-tolerating Pods are EVICTED** |

```yaml
spec:
  tolerations:
    - {key: dedicated, operator: Equal, value: shop, effect: NoSchedule}   # value must match exactly
    - {key: dedicated, operator: Exists, effect: NoSchedule}               # ⭐ any value
    - key: node.kubernetes.io/not-ready
      operator: Exists
      effect: NoExecute
      tolerationSeconds: 300        # ⭐ how long to tolerate before eviction (NoExecute only)
    - operator: Exists              # ⛔⛔ the "universal toleration" — tolerates EVERYTHING
```

**Taints Kubernetes adds automatically:**

| Taint | When | Default toleration on every Pod |
|---|---|---|
| `node.kubernetes.io/not-ready` | The kubelet isn't ready | 300s |
| `node.kubernetes.io/unreachable` | The API server can't reach the kubelet | 300s |
| `node.kubernetes.io/memory-pressure` | Memory pressure | DaemonSets only |
| `node.kubernetes.io/disk-pressure` | Disk pressure | DaemonSets only |
| `node.kubernetes.io/pid-pressure` | PID pressure | DaemonSets only |
| `node.kubernetes.io/network-unavailable` | The CNI isn't up | — |
| `node.kubernetes.io/unschedulable` | `kubectl cordon` | — |
| `node.cloudprovider.kubernetes.io/uninitialized` | A CCM is pending | — |
| `node-role.kubernetes.io/control-plane:NoSchedule` | Applied by kubeadm/kind | — |

```bash
# ⭐ the dedicated-node pattern (taint AND label AND affinity)
kubectl taint nodes learn-worker2 dedicated=shop:NoSchedule
kubectl label nodes learn-worker2 dedicated=shop
```
```yaml
spec:
  tolerations: [{key: dedicated, operator: Equal, value: shop, effect: NoSchedule}]
  nodeSelector: {dedicated: shop}          # ⭐ WITHOUT THIS the pod may land elsewhere
```

```bash
# NoExecute eviction in action
kubectl taint nodes learn-worker test=evict:NoExecute
kubectl get pods -o wide -w
# shop-api-…   1/1   Terminating   learn-worker     ← evicted within seconds
# shop-api-…   1/1   Pending       <none>
kubectl taint nodes learn-worker test=evict:NoExecute-
```

### 17.7 Priority and preemption

```bash
kubectl get priorityclasses
# system-cluster-critical   2000000000
# system-node-critical      2000001000
```

```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata: {name: shop-critical}
value: 100000                 # ⭐ must be < 1e9 unless it's a system class
globalDefault: false
description: "Customer-facing shop services"
preemptionPolicy: PreemptLowerPriority    # or Never
---
spec:
  priorityClassName: shop-critical
```

```bash
kubectl get pods -A -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,PRIO:.spec.priorityClassName,VALUE:.spec.priority' | sort -k4 -rn | head
kubectl describe pod high-priority-pod | grep -A3 Events
# Normal  Preempted  10s  default-scheduler  shop/high preempted shop/low
kubectl get events -A --field-selector reason=Preempted
```

### 17.8 QoS classes — what gets evicted first

| Class | Requirements | Eviction order | OOM score |
|---|---|---|---|
| **Guaranteed** | Every container: `requests == limits` for **both** cpu and memory | **Last** | −997 |
| **Burstable** | ≥1 container has a request or limit, but not Guaranteed | Middle | 2–999 |
| **BestEffort** | No requests and no limits at all | **First** | 1000 |

```bash
kubectl get pods -A -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,QOS:.status.qosClass' | sort -k3
kubectl describe pod nginx | grep 'QoS Class'
```

```yaml
# ⭐ the Guaranteed recipe
resources:
  requests: {cpu: "1", memory: 1Gi}
  limits:   {cpu: "1", memory: 1Gi}     # identical
```

⚠️ **CPU limits ≠ memory limits.** A CPU limit causes **throttling** (the container slows down); a memory limit causes **OOMKill** (the container dies). Many teams set memory requests == limits and **no CPU limit at all**.

```bash
# check whether you're being throttled
kubectl exec deploy/shop-api -- cat /sys/fs/cgroup/cpu.stat
# nr_throttled 4821
# throttled_usec 18234012          ← ⭐ >0 means your CPU limit is too low
```

### 17.9 Why a Pod is Pending — the decision tree

```bash
kubectl describe pod <pending-pod> | grep -A5 Events
```

| The scheduler message | Cause | Fix |
|---|---|---|
| `Insufficient cpu` / `Insufficient memory` | Requests exceed allocatable | Lower requests, add nodes, see what's already scheduled |
| `node(s) had untolerated taint {…}` | A taint | Add a toleration |
| `node(s) didn't match Pod's node affinity/selector` | nodeSelector/affinity | Fix the labels or the selector |
| `node(s) didn't match pod anti-affinity rules` | podAntiAffinity | Fewer replicas, more nodes, or soft anti-affinity |
| `node(s) didn't match pod topology spread constraints` | topologySpread | Adjust `maxSkew` or `whenUnsatisfiable` |
| `node(s) had volume node affinity conflict` | PV zone ≠ node zone | `WaitForFirstConsumer` |
| `node(s) didn't find available persistent volumes to bind` | No matching PV | Fix the StorageClass / create PVs |
| `Too many pods` | `status.allocatable.pods` reached | The node's `--max-pods` (default 110) |
| `node(s) were unschedulable` | Cordoned | `kubectl uncordon` |
| `Insufficient ephemeral-storage` | emptyDir/sizeLimit | Reduce, or add disk |
| `… (missing required label)` | A node lacks the topologyKey label | Label the nodes |
| `untolerated taint {node-role.kubernetes.io/control-plane: }` | Single control-plane-only cluster | Add workers, or tolerate it (dev only) |

```bash
# ⭐ the fastest capacity checks
kubectl describe nodes | grep -A6 'Allocated resources'
kubectl resource-capacity --utilization --pods 20
kubectl get nodes -o json | jq -r '.items[] | .metadata.name as $n |
  "\($n)  cpu=\(.status.allocatable.cpu)  mem=\(.status.allocatable.memory)  pods=\(.status.allocatable.pods)"'
```

---

<a name="18-autoscaling"></a>
## 18. Autoscaling

### 18.1 The four layers

| Layer | Scales | Controller | Trigger |
|---|---|---|---|
| **HPA** (Horizontal Pod Autoscaler) | The number of **Pods** | `kube-controller-manager` | CPU / memory / **custom metrics** |
| **VPA** (Vertical Pod Autoscaler) | The **requests/limits** of Pods | A separate operator | Historical usage |
| **Cluster Autoscaler / Karpenter** | The number of **Nodes** | Cloud-specific | Pending Pods |
| **KEDA** | Pods, **including from zero** | A separate operator | Queue depth, cron, Kafka lag, Prometheus |

### 18.2 HPA

```bash
kubectl get hpa
kubectl get hpa -A
kubectl describe hpa shop-api
kubectl autoscale deploy/shop-api --min=2 --max=10 --cpu-percent=70
kubectl delete hpa shop-api
kubectl edit hpa shop-api
```

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata: {name: shop-api, namespace: shop}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: shop-api
  minReplicas: 2
  maxReplicas: 20
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70              # ⭐ % of the REQUEST, not the limit
    - type: Resource
      resource:
        name: memory
        target:
          type: AverageValue
          averageValue: 800Mi
    - type: Pods
      pods:
        metric: {name: http_requests_per_second}
        target: {type: AverageValue, averageValue: "100"}
    - type: Object
      object:
        metric: {name: requests-per-second}
        describedObject: {apiVersion: networking.k8s.io/v1, kind: Ingress, name: shop-api}
        target: {type: Value, value: "10000"}
    - type: External
      external:
        metric: {name: sqs_queue_length, selector: {matchLabels: {queue: orders}}}
        target: {type: AverageValue, averageValue: "30"}
  behavior:                                    # ⭐ the part everyone forgets
    scaleUp:
      stabilizationWindowSeconds: 0            # react immediately
      policies:
        - {type: Percent, value: 100, periodSeconds: 15}    # double every 15s
        - {type: Pods, value: 4, periodSeconds: 15}         # or add 4, whichever is MORE
      selectPolicy: Max
    scaleDown:
      stabilizationWindowSeconds: 300          # ⭐ wait 5 min — the highest value in the window wins
      policies:
        - {type: Percent, value: 10, periodSeconds: 60}     # at most 10% per minute
      selectPolicy: Min
```

```bash
kubectl get hpa shop-api
# NAME       REFERENCE             TARGETS         MINPODS   MAXPODS   REPLICAS   AGE
# shop-api   Deployment/shop-api   42%/70%         2         20        3          3d
# ⚠️ TARGETS = <unknown>/70%   → metrics-server is broken or there are no requests
# ⚠️ TARGETS = <unknown>/70% (avg)  → the custom metric adapter isn't installed

kubectl describe hpa shop-api
# Events:
#   Type    Reason             Age   From                       Message
#   Normal  SuccessfulRescale  5m    horizontal-pod-autoscaler  New size: 5; reason: cpu resource utilization (percentage of request) above target
```

**The HPA formula:**

```
desiredReplicas = ceil( currentReplicas × ( currentMetricValue / desiredMetricValue ) )

# 3 replicas at 140% CPU with a 70% target:
#   ceil(3 × 140/70) = ceil(6) = 6 replicas
```

> 🔑 **Utilization is a percentage of the REQUEST, not the limit.** A container with `requests.cpu: 100m` running at 200m is at **200%**. If you set **no requests at all, the HPA cannot compute utilization** — this is the #1 reason for `<unknown>`.

```bash
# ⭐ the <unknown> debugging sequence
kubectl top pods -l app=shop-api
# error: Metrics API not available                     ← metrics-server is missing/broken
kubectl get deploy -n kube-system metrics-server
kubectl logs -n kube-system deploy/metrics-server --tail=50
# x509: cannot validate certificate for 10.244.1.5 because it doesn't contain any IP SANs
#   ← the classic kind/minikube self-signed-cert failure:
helm upgrade metrics-server metrics-server/metrics-server -n kube-system \
  --set args={"--cert-dir=/tmp","--secure-port=10250","--kubelet-insecure-tls","--kubelet-preferred-address-types=InternalIP"}

kubectl get apiservices | grep metrics
# v1beta1.metrics.k8s.io   kube-system/metrics-server   False   ← ⛔ broken
kubectl get --raw "/apis/metrics.k8s.io/v1beta1/namespaces/shop/pods" | jq '.items[0]'

kubectl get deploy shop-api -o jsonpath='{.spec.template.spec.containers[0].resources.requests.cpu}'; echo
# (empty)   ← ⛔ NO REQUESTS → the HPA can never compute a percentage
```

**HPA vs a Deployment's `replicas` field:**

```bash
# ⛔ the fight
kubectl get deploy shop-api -o jsonpath='{.spec.replicas}'; echo   # 3
kubectl scale deploy shop-api --replicas=10
sleep 20
kubectl get deploy shop-api -o jsonpath='{.spec.replicas}'; echo   # 3 again — the HPA won

# ✅ remove replicas from the manifest entirely
kubectl get deploy shop-api -o yaml | kubectl neat | grep -n 'replicas'
```

### 18.3 metrics-server

```bash
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm install metrics-server metrics-server/metrics-server -n kube-system \
  --set args={"--cert-dir=/tmp","--secure-port=10250","--kubelet-insecure-tls","--kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname","--metric-resolution=15s"}

kubectl top nodes
kubectl top pods -A
kubectl top pods -A --containers --sort-by=cpu
kubectl top pods -n shop --sort-by=memory
kubectl get --raw /apis/metrics.k8s.io/v1beta1/nodes | jq '.items[] | {node: .metadata.name, cpu: .usage.cpu, mem: .usage.memory}'
```

⚠️ **`kubectl top` is NOT real-time.** metrics-server keeps a short window (default 15s resolution, ~60s of history) and `top` reports the last scrape. **It never shows a spike that already passed.** For that you need Prometheus.

### 18.4 Custom metrics — the adapters

| Adapter | Serves | Use for |
|---|---|---|
| **metrics-server** | `metrics.k8s.io/v1beta1` | CPU + memory only |
| **prometheus-adapter** | `custom.metrics.k8s.io/v1beta1` + `external.metrics.k8s.io/v1beta1` | Anything in Prometheus |
| **KEDA** | `external.metrics.k8s.io/v1beta1` | 60+ scalers, **scale to zero** |
| **Kubernetes Event-driven / cloud adapters** | `external.metrics…` | SQS, Pub/Sub, Azure queues |

```bash
kubectl get apiservices | grep -E 'metrics'
# v1beta1.metrics.k8s.io          kube-system/metrics-server            True
# v1beta1.custom.metrics.k8s.io   kube-system/adapter                   True
# v1beta1.external.metrics.k8s.io kube-system/keda-metrics-apiserver    True

# what metrics are available?
kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1" | jq -r '.resources[].name' | head -30
# pods/http_requests_per_second
# pods/jvm_memory_used_bytes
# namespaces/ingress_nginx_requests
kubectl get --raw "/apis/external.metrics.k8s.io/v1beta1" | jq -r '.resources[].name'
# s0-rabbitmq_queue_messages
# s0-kafka_lag

# query one directly
kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1/namespaces/shop/pods/*/http_requests_per_second" | jq .
```

### 18.5 KEDA — scale from zero and event-driven scaling

```bash
helm repo add kedacore https://kedacore.github.io/charts
helm install keda kedacore/keda -n keda --create-namespace --version 2.16.1
```

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata: {name: order-worker, namespace: shop}
spec:
  scaleTargetRef: {name: order-worker}          # a Deployment (or StatefulSet via advanced)
  minReplicaCount: 0                            # ⭐⭐ SCALE TO ZERO
  maxReplicaCount: 100
  cooldownPeriod: 300
  pollingInterval: 30
  idleReplicaCount: 1                           # optional: keep 1 warm
  advanced:
    horizontalPodAutoscalerConfig:
      behavior:
        scaleDown: {stabilizationWindowSeconds: 600, policies: [{type: Percent, value: 20, periodSeconds: 60}]}
  triggers:
    - type: rabbitmq
      metadata:
        protocol: amqp
        queueName: orders
        queueLength: "10"                       # ⭐ 10 messages per replica
        hostFromEnv: RABBITMQ_HOST
        usernameFromEnv: RABBITMQ_USER
        passwordFromEnv: RABBITMQ_PASS
    - type: prometheus
      metadata:
        serverAddress: http://prometheus.monitoring:9090
        metricName: http_requests_per_second
        query: sum(rate(http_requests_total{app="order-worker"}[2m]))
        threshold: "100"
---
apiVersion: keda.sh/v1alpha1
kind: CronScaledObject                          # or a ScaledObject with a cron trigger
metadata: {name: nightly}
```

```bash
kubectl get scaledobjects -A
kubectl describe scaledobject order-worker -n shop
# Conditions:
#   Ready            True    ScaledObjectReady
#   Active           True    The scaler is active
#   Fallback         False   Not in fallback mode
#   HPAReady         True

kubectl get hpa -n shop                          # ⭐ KEDA creates a real HPA under the hood
# keda-hpa-order-worker   Deployment/order-worker   0/10 (avg)   0   100   3   1h
kubectl logs -n keda deploy/keda-operator --tail=50
kubectl logs -n keda deploy/keda-metrics-apiserver --tail=50
```

⚠️ **A Pod with `replicas: 0` has no warm capacity.** The first request after scale-from-zero pays the full cold start: schedule + pull + init + app startup. For a JVM that's 30–90 seconds. Use `idleReplicaCount` or `minReplicaCount: 1` for latency-sensitive services.

### 18.6 VPA

```bash
kubectl get vpa -A
```

```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata: {name: shop-api, namespace: shop}
spec:
  targetRef: {apiVersion: apps/v1, kind: Deployment, name: shop-api}
  updatePolicy:
    updateMode: "Off"          # ⭐ "Off" = recommend only, "Auto" = recreate Pods, "Initial" = at admission
    minReplicas: 2
  resourcePolicy:
    containerPolicies:
      - containerName: api
        minAllowed: {cpu: 100m, memory: 256Mi}
        maxAllowed: {cpu: "4",  memory: 8Gi}
        controlledResources: [cpu, memory]
        controlledValues: RequestsOnly      # ⭐ don't touch limits
```

```bash
kubectl describe vpa shop-api -n shop
# Recommendation:
#   Container Name: api
#   Target:    cpu 450m  memory 1200Mi
#   Lower:     cpu 320m  memory 900Mi
#   Upper:     cpu 600m  memory 1600Mi
```

⚠️ **VPA and HPA on the same metric conflict.** Never run a CPU/memory-based HPA and a VPA in `Auto` mode on the same Deployment. The safe combinations:

| Combination | Safe? |
|---|---|
| HPA on CPU + VPA `Off` (recommendations only) | ✅ Recommended |
| HPA on **custom** metrics + VPA `Auto` | ✅ Safe |
| HPA on CPU + VPA `Auto` | ⛔ They fight |

### 18.7 Cluster Autoscaler / Karpenter

```bash
# Cluster Autoscaler
kubectl get deploy -n kube-system cluster-autoscaler
kubectl logs -n kube-system deploy/cluster-autoscaler --tail=100
kubectl logs -n kube-system deploy/cluster-autoscaler --tail=500 | grep -iE 'scale (up|down)|not trigger'
kubectl describe configmap -n kube-system cluster-autoscaler-status | sed -n '1,80p'

# Karpenter (AWS)
kubectl get nodepools
kubectl get nodeclaims
kubectl describe nodepool default
kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter --tail=100
```

```yaml
# Karpenter NodePool
apiVersion: karpenter.sh/v1
kind: NodePool
metadata: {name: default}
spec:
  template:
    spec:
      requirements:
        - {key: kubernetes.io/arch, operator: In, values: [amd64, arm64]}
        - {key: karpenter.sh/capacity-type, operator: In, values: [spot, on-demand]}
        - {key: karpenter.k8s.aws/instance-category, operator: In, values: [m, c, r]}
      nodeClassRef: {group: karpenter.k8s.aws, kind: EC2NodeClass, name: default}
      expireAfter: 168h                 # ⭐ recycle nodes weekly
      drain: {consolidationPolicy: WhenEmptyOrUnderutilized, consolidateAfter: 5m}
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidationDelay: 60s
    budgets: [{nodes: "10%"}]           # ⭐ never disrupt more than 10% at once
  limits: {cpu: "1000", memory: 4000Gi}
```

| | Cluster Autoscaler | Karpenter |
|---|---|---|
| Chooses from | Pre-defined **node groups** (ASGs) | The **whole instance catalogue**, just-in-time |
| Trigger | Pending Pods | Pending Pods |
| Bin-packing | Whatever the ASG gives | Right-sized per workload |
| Consolidation | Limited | ✅ Aggressive |
| Spot interruption handling | Via the ASG | ✅ Native, 2-minute notice |

```bash
# ⭐ why isn't the cluster scaling up?
kubectl describe nodepool default | grep -A10 Status
kubectl get pods -A --field-selector=status.phase=Pending
kubectl describe pod <pending> | grep -A5 Events
# 0/3 nodes are available: 3 Insufficient cpu   ← the CA should fire
kubectl logs -n kube-system deploy/cluster-autoscaler --tail=200 | grep -i 'pod didn.t trigger scale-up'
# "Pod didn't trigger scale-up: 1 max node group size reached"       ← you hit the CA's max
# "Pod didn't trigger scale-up: 3 node(s) had untolerated taint"     ← the new node wouldn't help
# "Pod didn't trigger scale-up: 1 Insufficient cpu … exceeds limit"  ← the Limits field on the NodePool
```

---

<a name="19-rbac-and-authentication"></a>
## 19. RBAC & authentication

### 19.1 Authentication vs authorization

```
kubectl get pods
    │
    ├── 1. AUTHENTICATION  — who are you?           → a User, Group, or ServiceAccount
    │      (certificates, tokens, OIDC, webhooks, exec plugins)
    │
    ├── 2. ADMISSION         — is this allowed?      → mutating then validating webhooks, PSA, quotas
    │
    └── 3. AUTHORIZATION     — can you do this?      → RBAC, ABAC, Node, Webhook
```

```bash
kubectl get pod nginx
# Error from server (Forbidden): pods "nginx" is forbidden:
#   User "jane@example.com" cannot get resource "pods" in API group "" in the namespace "default"
#        ↑ AUTHORIZATION failed (you were authenticated fine)

kubectl get pods
# error: You must be logged in to the server (Unauthorized)
#        ↑ AUTHENTICATION failed
```

### 19.2 The RBAC objects

| Object | Scope | Grants |
|---|---|---|
| `Role` | Namespaced | Permissions **in one namespace** |
| `ClusterRole` | Cluster | Permissions cluster-wide, OR to be namespaced via a RoleBinding, OR to non-namespaced resources |
| `RoleBinding` | Namespaced | Binds a Role **or ClusterRole** to subjects in one namespace |
| `ClusterRoleBinding` | Cluster | Binds a ClusterRole to subjects **everywhere** |

```bash
kubectl get roles -n shop
kubectl get clusterroles
kubectl get rolebindings -n shop
kubectl get clusterrolebindings
kubectl describe clusterrole admin
kubectl describe clusterrole view
kubectl describe clusterrole edit
```

**The four default ClusterRoles (plus their `*-aggregated-to-*` companions):**

| ClusterRole | Can | Cannot |
|---|---|---|
| `view` | Read almost everything in a namespace | Write anything; read Secrets; read RBAC |
| `edit` | Read + write most things in a namespace | Change RBAC, ResourceQuotas, LimitRanges |
| `admin` | Everything in a namespace, including RBAC | Change the namespace itself or ResourceQuotas |
| `cluster-admin` | **Everything, everywhere** | — |

⚠️ **`view` deliberately excludes Secrets.** A `view` binding does NOT let you read Secrets — that's by design.

```bash
# ⭐ create a read-only Role for one namespace
kubectl create role pod-reader --verb=get,list,watch --resource=pods,services,deployments -n shop
kubectl create rolebinding jane-reads --role=pod-reader --user=jane@example.com -n shop

# ⭐ bind the built-in view ClusterRole to a namespace
kubectl create rolebinding shop-viewers --clusterrole=view --user=jane@example.com -n shop

# a ServiceAccount subject
kubectl create serviceaccount ci-deployer -n shop
kubectl create role deployer --verb=get,list,watch,create,update,patch,delete \
  --resource=deployments,services,configmaps,secrets -n shop
kubectl create rolebinding ci-can-deploy --role=deployer --serviceaccount=shop:ci-deployer -n shop

# cluster-wide
kubectl create clusterrole node-reader --verb=get,list,watch --resource=nodes
kubectl create clusterrolebinding monitoring-nodes --clusterrole=node-reader \
  --serviceaccount=monitoring:prometheus

kubectl get role deployer -n shop -o yaml
kubectl get rolebinding ci-can-deploy -n shop -o yaml
```

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata: {name: pod-log-reader}
rules:
  - apiGroups: [""]                        # ⭐ "" means the CORE group
    resources: ["pods", "pods/log"]        # ⭐ "pods/log" is a SUBRESOURCE
    verbs: ["get", "list", "watch"]
  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["get", "list"]
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: []                              # ⭐ explicitly nothing
  - nonResourceURLs: ["/healthz", "/readyz", "/metrics"]   # ⭐ non-resource paths
    verbs: ["get"]
  - apiGroups: [""]
    resources: ["pods"]
    resourceNames: ["specific-pod"]        # ⭐ restrict to NAMED objects (no list/watch/create!)
    verbs: ["get", "update"]
```

**Verbs:** `get`, `list`, `watch`, `create`, `update`, `patch`, `delete`, `deletecollection`, `impersonate`, `bind`, `escalate`, `use` (for PodSecurityPolicies/PriorityClasses).

⚠️ **`resourceNames` doesn't work with `create`, `list`, `watch`, or `deletecollection`** — those don't have a name yet or operate on many.

### 19.3 `auth can-i` — the single most useful RBAC command

```bash
kubectl auth can-i get pods
# yes
kubectl auth can-i delete pods -n shop
# no
kubectl auth can-i '*' '*'
# yes                                   ← ⛔ you are cluster-admin. Be careful.
kubectl auth can-i list secrets --all-namespaces
# no

# ⭐ as someone else (impersonation)
kubectl auth can-i get pods -n shop --as=jane@example.com
kubectl auth can-i delete deploy -n shop --as=system:serviceaccount:shop:ci-deployer
kubectl auth can-i get secrets -n shop --as-group=system:serviceaccounts --as=system:serviceaccount:shop:default

# ⭐ list everything YOU can do
kubectl auth can-i --list
# Resources                                       Non-Resource URLs   Resource Names   Verbs
# pods.apps                                       []                  []               [get list watch]
# deployments.apps                                []                  []               [get list watch]
# selfsubjectaccessreviews.authorization.k8s.io   []                  []               [create]
# selfsubjectrulesreviews.authorization.k8s.io    []                  []               [create]
#                                                 [/api/*]            []               [get]
# …

kubectl auth can-i --list -n shop
kubectl auth can-i --list --as=jane@example.com -n shop
kubectl auth can-i --list -o wide
kubectl auth can-i --list --namespaced=false

# the exhaustive check
kubectl auth can-i --list --as=system:serviceaccount:shop:ci-deployer -n shop -o json | jq '.status'
```

```bash
# ⭐ the plugins that make RBAC reviewable
kubectl who-can delete pods -n shop
# Subjects          Resource Alias   Namespace   Verbs   Name
# RoleBinding:      ci-can-deploy    shop        [*]     deployments
#   ServiceAccount: shop/ci-deployer
# ClusterRoleBinding: cluster-admin-binding
#   User:           admin@example.com

kubectl access-matrix -n shop
kubectl access-matrix for sa:ci-deployer -n shop
kubectl rbac-view                                 # an HTML visualisation
```

### 19.4 Impersonation — the debugging superpower

```bash
kubectl get pods --as=jane@example.com
kubectl get pods --as=jane --as-group=developers
kubectl get pods --as=system:serviceaccount:shop:ci-deployer
kubectl get pods --as-uid=1234
kubectl create ns test --as=jane@example.com       # does jane have this permission?
kubectl auth can-i --list --as=jane@example.com
```

Requires the `impersonate` verb on `users`, `groups`, `serviceaccounts`, or `uid`. This is how you **reproduce a user's exact permissions** without their credentials.

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata: {name: impersonator}
rules:
  - apiGroups: [""]
    resources: ["users", "groups", "serviceaccounts"]
    verbs: ["impersonate"]
  - apiGroups: ["authentication.k8s.io"]
    resources: ["userextras/scopes"]
    verbs: ["impersonate"]
```

### 19.5 ServiceAccounts

```bash
kubectl get sa -n shop
kubectl describe sa ci-deployer -n shop
kubectl create sa ci-deployer -n shop
```

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ci-deployer
  namespace: shop
automountServiceAccountToken: false     # ⭐ only mount a token if the app needs one
imagePullSecrets:
  - name: ghcr-creds                    # ⭐ every Pod using this SA can pull from GHCR
secrets: []                             # legacy auto-created tokens (v1.24+: none by default)
---
spec:
  serviceAccountName: ci-deployer       # on the Pod
  automountServiceAccountToken: true    # per-Pod override
```

**v1.24+ changed everything:** ServiceAccounts no longer get an auto-created, never-expiring Secret token. Instead the kubelet projects a **short-lived, audience-bound** token:

```bash
kubectl exec deploy/shop-api -- ls -la /var/run/secrets/kubernetes.io/serviceaccount/
# ca.crt      namespace   token
kubectl exec deploy/shop-api -- cat /var/run/secrets/kubernetes.io/serviceaccount/token | cut -d. -f2 | base64 -d 2>/dev/null | jq .
# {
#   "aud": ["https://kubernetes.default.svc"],
#   "exp": 1757420000,                          ← ⭐ expires in 1 hour (default)
#   "iat": 1757416400,
#   "iss": "https://kubernetes.default.svc",
#   "kubernetes.io": {"namespace":"shop","pod":{"name":"shop-api-…","uid":"…"}},
#   "nbf": 1757416400,
#   "sub": "system:serviceaccount:shop:ci-deployer"
# }
```

```bash
# a scoped, short-lived token for CI ⭐⭐ — the modern replacement for SA secrets
kubectl create token ci-deployer -n shop --duration=1h
kubectl create token ci-deployer -n shop --duration=15m --audience=https://ci.example.com
kubectl create token ci-deployer -n shop --bound-object-ref=v1:Pod:some-pod    # dies with the Pod

# a long-lived token (⚠️ prefer create token)
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: ci-deployer-token
  namespace: shop
  annotations: {kubernetes.io/service-account.name: ci-deployer}
type: kubernetes.io/service-account-token
EOF
sleep 3
kubectl get secret ci-deployer-token -n shop -o jsonpath='{.data.token}' | base64 -d; echo
```

> 🔑 **In GitHub Actions / GitLab CI, use OIDC federation to mint a short-lived token** (`aws eks get-token`, GCP Workload Identity, or `kubectl create token` with a bound audience) rather than storing a static kubeconfig secret.

### 19.6 The RBAC troubleshooting sequence

```bash
# 1. Who am I, according to the cluster?
kubectl auth whoami                       # ⭐ v1.28+ (SelfSubjectReview)
# ATTRIBUTE   VALUE
# Username    jane@example.com
# Groups      [system:authenticated]
kubectl auth whoami -o json | jq .status.userInfo

# 2. What can I do?
kubectl auth can-i --list -n shop

# 3. What bindings apply to me?
kubectl get rolebindings -n shop -o json | jq -r '.items[] |
  select(.subjects[]? | (.kind=="User" and .name=="jane@example.com") or (.kind=="Group" and .name=="system:authenticated"))
  | "\(.metadata.name) → \(.roleRef.kind)/\(.roleRef.name)"'
kubectl get clusterrolebindings -o json | jq -r '.items[] |
  select(.subjects[]? | .name=="jane@example.com")
  | "\(.metadata.name) → \(.roleRef.name)"'

# 4. Does the role actually grant the verb?
kubectl describe role deployer -n shop

# 5. Is a webhook also denying it?
kubectl get validatingwebhookconfigurations -o json | jq -r '.items[].webhooks[].name'
kubectl logs -n <webhook-ns> deploy/<webhook> --tail=50

# 6. Turn on API server audit logging (control-plane access required)
kubectl get --raw /metrics | grep apiserver_request_total | grep -c 'code="403"'
```

**The classic RBAC mistakes:**

| Mistake | Symptom | Fix |
|---|---|---|
| A `Role` in namespace A bound in namespace B | Nothing works | Roles and RoleBindings must be in the **same** namespace |
| A `ClusterRole` bound with a `RoleBinding` | Only works in that namespace | That's correct for scoping; use `ClusterRoleBinding` for cluster-wide |
| `apiGroups: ["apps"]` for Pods | Forbidden | Pods are in the **core** group: `apiGroups: [""]` |
| Forgetting `pods/log` | Can't read logs | Subresources need explicit grants |
| `resourceNames` + `create` | Silently never matches | `create` has no name to match |
| Binding to a Group you're not in | Forbidden | Check `kubectl auth whoami` |
| The SA is in the wrong namespace | Forbidden | SAs are namespaced: `system:serviceaccount:<ns>:<name>` |
| `automountServiceAccountToken: false` | The app can't reach the API | Set it to true, or mount a projected token |

---

<a name="20-namespaces-quotas-and-limitranges"></a>
## 20. Namespaces, quotas & LimitRanges

### 20.1 Namespaces

```bash
kubectl get namespaces
kubectl get ns
kubectl describe ns shop
kubectl create namespace shop
kubectl delete namespace shop
kubectl delete ns shop --wait=false
kubectl label ns shop team=platform env=prod
kubectl annotate ns shop owner=platform@example.com
kubectl get ns -L team -L env
```

**What Kubernetes does automatically:**

```bash
kubectl get ns shop -o jsonpath='{.metadata.labels}'; echo
# {"kubernetes.io/metadata.name":"shop"}      ← ⭐ added by the NamespaceDefaultLabelName feature
kubectl get ns kube-system -o jsonpath='{.metadata.labels}' | jq .
# {"kubernetes.io/metadata.name":"kube-system"}
```

> 🔑 That auto-added `kubernetes.io/metadata.name` label is what makes `namespaceSelector` usable for matching a namespace **by name** — the pattern every NetworkPolicy needs.

**Cluster-scoped things that ignore namespaces:** Nodes, PersistentVolumes, StorageClasses, PriorityClasses, ClusterRoles, ClusterRoleBindings, IngressClasses, CustomResourceDefinitions, Namespaces themselves, APIServices, RuntimeClasses, ValidatingWebhookConfigurations.

```bash
kubectl api-resources --namespaced=false
```

**Which namespaces exist by default:**

| Namespace | Contains |
|---|---|
| `default` | Where things land if you don't specify |
| `kube-system` | The control-plane components and CNI |
| `kube-public` | Publicly readable; the `cluster-info` ConfigMap |
| `kube-node-lease` | Node heartbeat Leases |

⚠️ **Don't delete `kube-system`.** And avoid `default` for real workloads — you can't apply a ResourceQuota per-team and it makes RBAC sloppier.

```bash
# ⭐ copy a workload between namespaces
kubectl get deploy shop-api -n shop-prod -o yaml | kubectl neat \
  | sed 's/namespace: shop-prod/namespace: shop-staging/' \
  | kubectl apply -f - -n shop-staging --dry-run=server

# ⭐ move a namespace's worth of workloads out of the way
for d in $(kubectl get deploy -n shop -o name); do kubectl scale $d -n shop --replicas=0; done
```

### 20.2 ResourceQuota

```bash
kubectl get resourcequotas -n shop
kubectl describe resourcequota shop-quota -n shop
kubectl get resourcequota shop-quota -n shop -o yaml
```

```yaml
apiVersion: v1
kind: ResourceQuota
metadata: {name: shop-quota, namespace: shop}
spec:
  hard:
    # compute
    requests.cpu: "20"
    requests.memory: 40Gi
    limits.cpu: "40"
    limits.memory: 80Gi
    pods: "50"
    # ⭐ per-Pod minimums (stops BestEffort pods sneaking in)
    requests.cpu: "20"
    limits.cpu: "40"
    # storage
    requests.storage: 100Gi
    persistentvolumeclaims: "20"
    fast-ssd.storageclass.storage.k8s.io/requests.storage: 50Gi
    fast-ssd.storageclass.storage.k8s.io/persistentvolumeclaims: "10"
    count/persistentvolumeclaims: "20"
    # object counts
    services: "20"
    services.loadbalancers: "2"
    services.nodeports: "5"
    secrets: "50"
    configmaps: "100"
    replicationcontrollers: "20"
    apps/deployments: "20"
    apps/statefulsets: "5"
    batch/jobs: "50"
    batch/cronjobs: "20"
    networking.k8s.io/ingresses: "10"
  scopes: ["NotTerminating"]              # ⭐ ignore pods with activeDeadlineSeconds/RestartNever
  scopeSelector:
    matchExpressions:
      - {scopeName: PriorityClass, operator: In, values: ["high"]}
```

```bash
kubectl describe resourcequota shop-quota -n shop
# Name:            shop-quota
# Namespace:       shop
# Resource         Used    Hard
# --------         ----    ----
# configmaps       3       100
# limits.cpu       12      40
# limits.memory    18Gi    80Gi
# pods             14      50
# requests.cpu     6500m   20
# requests.memory  11Gi    40Gi
# services         4       20
```

⚠️ **A quota on `requests.cpu` means EVERY new Pod must declare CPU requests,** or it's rejected:

```bash
kubectl create deploy test --image=nginx -n shop
# Error from server (Forbidden): error when creating "STDIN":
#   pods "test-abc" is forbidden: failed quota: shop-quota: must specify limits.cpu, limits.memory, requests.cpu, requests.memory
```

⚠️ **Existing objects are NOT retroactively rejected** — only new creates/updates. So a quota can show `Used > Hard` right after you add it.

⚠️ **Quotas do not evict.** They only block admission. If you need to enforce limits on running Pods, that's a LimitRange + PDB + the eviction manager.

### 20.3 LimitRange

```bash
kubectl get limitranges -n shop
kubectl describe limitrange shop-limits -n shop
```

```yaml
apiVersion: v1
kind: LimitRange
metadata: {name: shop-limits, namespace: shop}
spec:
  limits:
    - type: Container
      default:                 {cpu: 500m, memory: 512Mi}     # ⭐ the LIMIT if unspecified
      defaultRequest:          {cpu: 100m, memory: 128Mi}     # ⭐ the REQUEST if unspecified
      min:                     {cpu: 50m,  memory: 64Mi}
      max:                     {cpu: "4",  memory: 8Gi}
      maxLimitRequestRatio:
        cpu: "10"                                             # ⭐ limits ≤ 10× requests
        memory: "2"
    - type: Pod
      max: {cpu: "8", memory: 16Gi}
    - type: PersistentVolumeClaim
      min: {storage: 1Gi}
      max: {storage: 100Gi}
```

**LimitRange is what makes "I forgot to set requests" impossible:**

```bash
kubectl create deploy test --image=nginx -n shop --dry-run=server -o yaml | grep -A5 resources
# resources:
#   limits:   {cpu: 500m, memory: 512Mi}       ← the LimitRange default
#   requests: {cpu: 100m, memory: 128Mi}       ← the LimitRange defaultRequest
```

| | ResourceQuota | LimitRange |
|---|---|---|
| Scope | The **sum** across the namespace | **Each** object individually |
| Enforces | Total capacity | Defaults, min, max, ratios |
| Rejects | Creates that would exceed the total | Creates outside the per-object bounds |
| Sets defaults | ❌ | ✅ `default` / `defaultRequest` |

### 20.4 PodDisruptionBudget

```bash
kubectl get pdb -n shop
kubectl describe pdb shop-api -n shop
```

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata: {name: shop-api, namespace: shop}
spec:
  minAvailable: 2              # ⭐ OR maxUnavailable — never both
  # maxUnavailable: 1
  # maxUnavailable: 25%
  selector: {matchLabels: {app: shop-api}}
  unhealthyPodEvictionPolicy: IfHealthyBudget    # ⭐ v1.31+ stable
                                                 # AlwaysAllow | IfHealthyBudget
```

```bash
kubectl get pdb shop-api -n shop
# NAME       MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
# shop-api   2               N/A               1                     3d
# ⚠️ ALLOWED DISRUPTIONS = 0  → a drain will BLOCK
```

**A PDB only affects VOLUNTARY disruption** — `kubectl drain`, `kubectl evict`, node upgrades, autoscaler consolidation. It does **nothing** for:
- A node running out of memory/disk (**involuntary** eviction)
- The OOM killer
- `kubectl delete pod`
- Application crashes

```bash
# ⭐ the drain that blocks
kubectl drain learn-worker --ignore-daemonsets --delete-emptydir-data
# evicting pod shop/shop-api-7d4f8c9b6-abcde
# error when evicting pods/"shop-api-7d4f8c9b6-abcde" -n "shop"
#   (will not affect your application): Cannot evict pod as it would violate the pod's disruption budget
# (it retries forever — Ctrl-C, or use --timeout)

kubectl drain learn-worker --ignore-daemonsets --delete-emptydir-data --timeout=120s
# error: drain did not complete within 2m0s

# ⛔ the escape hatch — bypasses PDBs. Only in an emergency.
kubectl drain learn-worker --ignore-daemonsets --delete-emptydir-data --disable-eviction
# (this DELETEs the pods instead of evicting them — no PDB check)

# the right fix: scale up first
kubectl scale deploy/shop-api --replicas=5 -n shop
kubectl rollout status deploy/shop-api -n shop
kubectl drain learn-worker --ignore-daemonsets --delete-emptydir-data
```

⚠️ **`minAvailable: N` where N == replicas = an un-drainable node.** Always leave headroom: with 3 replicas use `maxUnavailable: 1` or `minAvailable: 2`.

⚠️ **A single-replica Deployment with any PDB is un-drainable.** Either scale to ≥2 or don't use a PDB.

### 20.5 The eviction API

```bash
# manual eviction (respects PDBs)
kubectl evict pod nginx -n shop                        # v1.30+ (a krew plugin before that)
kubectl krew install evict-pod && kubectl evict-pod nginx -n shop --dry-run

# the raw API call
kubectl create --raw "/api/v1/namespaces/shop/pods/nginx/eviction" -f - <<'EOF'
{"apiVersion":"policy/v1","kind":"Eviction","metadata":{"name":"nginx","namespace":"shop"}}
EOF
# 429 Too Many Requests: Cannot evict pod as it would violate the pod's disruption budget
```

| Response | Meaning |
|---|---|
| `201 Created` | Eviction accepted |
| `429 Too Many Requests` | ⭐ The PDB blocked it — retry later |
| `404 Not Found` | The Pod is gone |

---

<a name="21-security-contexts-and-pod-security-standards"></a>
## 21. Security contexts & Pod Security

### 21.1 securityContext — every field that matters

```yaml
spec:
  # POD level
  securityContext:
    runAsUser: 10001                 # ⭐ the UID
    runAsGroup: 10001
    runAsNonRoot: true               # ⭐ REJECT the image if it would run as root
    fsGroup: 10001                   # ⭐ chown+chmod volumes to this GID
    fsGroupChangePolicy: OnRootMismatch   # ⭐ only re-chown if the root doesn't match (fast for big volumes)
    supplementalGroups: [10002]
    seccompProfile: {type: RuntimeDefault}   # ⭐ RuntimeDefault | Localhost | Unconfined
    sysctls:
      - {name: net.core.somaxconn, value: "4096"}     # ⚠️ only "safe" sysctls by default
    windowsOptions: {hostProcess: false}

  containers:
    - name: api
      # CONTAINER level (overrides the pod level)
      securityContext:
        runAsUser: 10001
        runAsNonRoot: true
        allowPrivilegeEscalation: false    # ⭐⭐ no setuid binaries can gain privileges
        readOnlyRootFilesystem: true       # ⭐⭐ the single biggest hardening win
        privileged: false                  # ⛔ never true in production
        capabilities:
          drop: ["ALL"]                    # ⭐⭐ drop everything
          add: ["NET_BIND_SERVICE"]        # …then add back only what you need
        seccompProfile: {type: RuntimeDefault}
        procMount: Default                 # or Unmasked (requires privileged)
      volumeMounts:
        - {name: tmp, mountPath: /tmp}          # ⭐ writable dirs when the rootfs is read-only
        - {name: cache, mountPath: /app/cache}
  volumes:
    - {name: tmp, emptyDir: {}}
    - {name: cache, emptyDir: {}}
```

| Field | Effect | The gotcha |
|---|---|---|
| `runAsNonRoot: true` | The kubelet refuses to start a container whose image runs as UID 0 | ⛔ Fails if the image has no `USER` directive and no `runAsUser` |
| `readOnlyRootFilesystem: true` | The container's `/` is read-only | ⚠️ Needs `emptyDir` mounts for `/tmp`, caches, PID files |
| `allowPrivilegeEscalation: false` | Sets `no_new_privs` | ⛔ Breaks `sudo`, `ping` (setuid), and some agent installers |
| `capabilities.drop: [ALL]` | Drops all Linux capabilities | Add back only what you need |
| `privileged: true` | All capabilities, all devices, no seccomp/AppArmor | ⛔ Effectively root on the node |
| `fsGroup` | Volumes are chowned to this GID | ⚠️ Slow on huge volumes → use `fsGroupChangePolicy: OnRootMismatch` |
| `seccompProfile: RuntimeDefault` | The runtime's default syscall filter | ⛔ `Unconfined` allows every syscall |

```bash
# what's actually running?
kubectl get pods -A -o json | jq -r '.items[] | . as $p |
  ($p.spec.containers[] | select(.securityContext.privileged == true) |
   "⛔ PRIVILEGED  \($p.metadata.namespace)/\($p.metadata.name)/\(.name)")'

kubectl get pods -A -o json | jq -r '.items[] | . as $p |
  ($p.spec.containers[] | select(.securityContext.runAsNonRoot != true) |
   "⚠️ runAsNonRoot not set  \($p.metadata.namespace)/\($p.metadata.name)/\(.name)")'

kubectl get pods -A -o json | jq -r '.items[] | . as $p |
  ($p.spec.containers[] | select(.securityContext.readOnlyRootFilesystem != true) |
   "⚠️ writable rootfs  \($p.metadata.namespace)/\($p.metadata.name)/\(.name)")'

# verify from inside
kubectl exec deploy/shop-api -- id
# uid=10001(app) gid=10001(app) groups=10001(app),10002
kubectl exec deploy/shop-api -- cat /proc/1/status | grep -E 'CapEff|CapBnd|Seccomp|NoNewPrivs'
# NoNewPrivs:	1                        ← ⭐ allowPrivilegeEscalation: false worked
# Seccomp:	2                          ← ⭐ 2 = a seccomp profile is active (RuntimeDefault)
# CapEff:	0000000000000000           ← ⭐ all capabilities dropped
# CapBnd:	0000000000000000
kubectl exec deploy/shop-api -- touch /test
# touch: /test: Read-only file system    ← ⭐ readOnlyRootFilesystem worked
```

**Decoding `CapEff`:**

```bash
# CapEff is a hex bitmask. Decode it:
capsh --decode=00000000a80425fb          # docker's default
# 0x00000000a80425fb=cap_chown,cap_dac_override,cap_fowner,cap_fsetid,cap_kill,
#   cap_setgid,cap_setuid,cap_setpcap,cap_net_bind_service,cap_net_raw,cap_sys_chroot,
#   cap_mknod,cap_audit_write,cap_setfcap

capsh --decode=0000000000000000          # ✅ everything dropped
capsh --decode=0000003fffffffff          # ⛔ privileged — everything granted
```

### 21.2 Pod Security Standards & Admission

**PSP (PodSecurityPolicy) was removed in v1.25.** Its replacement is **Pod Security Admission (PSA)** — three standards, enforced by namespace labels.

| Standard | What it forbids |
|---|---|
| **`privileged`** | Nothing. Unrestricted. |
| **`baseline`** | Known privilege escalation: `privileged`, `hostPID/IPC/Network`, host ports, most capabilities, `/proc/mounts` writes, unsafe AppArmor/seccomp, `hostPath` |
| **`restricted`** | ⭐ The hardened standard: `runAsNonRoot: true`, `seccompProfile: RuntimeDefault`, `capabilities.drop: [ALL]`, `allowPrivilegeEscalation: false` |

```bash
# ⭐ enforce per-namespace with labels
kubectl label ns shop \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/enforce-version=latest \
  pod-security.kubernetes.io/warn=restricted \
  pod-security.kubernetes.io/warn-version=latest \
  pod-security.kubernetes.io/audit=restricted \
  pod-security.kubernetes.io/audit-version=latest \
  --overwrite

kubectl get ns shop -o jsonpath='{.metadata.labels}' | jq 'with_entries(select(.key|startswith("pod-security")))'
# {"pod-security.kubernetes.io/audit":"restricted",
#  "pod-security.kubernetes.io/enforce":"restricted",
#  "pod-security.kubernetes.io/warn":"restricted"}
```

| Label mode | Behaviour |
|---|---|
| `enforce` | ⛔ **Rejects** the Pod at admission |
| `warn` | ⚠️ Rejects **and** shows the violation to the user |
| `audit` | 📝 Records the violation in the API server audit log |

```bash
# what it looks like when you're blocked
kubectl run nginx --image=nginx -n shop
# Error from server (BadRequest): error when creating "STDIN":
#   pods "nginx" is forbidden: violates PodSecurity "restricted:latest":
#     allowPrivilegeEscalation != false (container "nginx" must set securityContext.allowPrivilegeEscalation=false),
#     unrestricted capabilities (container "nginx" must set securityContext.capabilities.drop=["ALL"]),
#     runAsNonRoot != true (pod or container "nginx" must set securityContext.runAsNonRoot=true),
#     seccompProfile (pod or container "nginx" must set securityContext.seccompProfile.type to "RuntimeDefault" or "Localhost")
# ⭐ READ THE ERROR — it tells you EXACTLY which four fields to add.
```

**The `restricted`-compliant container block — memorise it:**

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 10001
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  seccompProfile: {type: RuntimeDefault}
  capabilities: {drop: ["ALL"]}
```

**Exemptions** (in the PSA configuration file, not per-namespace):

```yaml
apiVersion: apiserver.config.k8s.io/v1
kind: PodSecurityConfiguration
exemptions:
  usernames: ["system:serviceaccount:kube-system:replicaset-controller"]
  runtimeClasses: ["kata"]
  namespaces: ["kube-system", "ingress-nginx", "monitoring"]    # ⚠️ be careful
```

```bash
# ⭐ audit your whole cluster against restricted
kubectl get ns -o json | jq -r '.items[] |
  "\(.metadata.name)\tenforce=\(.metadata.labels["pod-security.kubernetes.io/enforce"] // "none")"'

# what would fail?
kubectl get pods -A -o json | jq -r '.items[] | . as $p |
  ($p.spec.containers[] | select(
      (.securityContext.runAsNonRoot != true) or
      (.securityContext.allowPrivilegeEscalation != false) or
      ((.securityContext.capabilities.drop // []) | index("ALL") | not))
   | "\($p.metadata.namespace)/\($p.metadata.name)/\(.name)  ⚠️ not restricted-compliant")'

# the tool that does this properly
kubectl krew install pss-checker      # or use kubescape / kube-bench
kubescape scan framework nsa --format pretty-printer
popeye --sections pod
```

### 21.3 Other hardening knobs

```yaml
spec:
  automountServiceAccountToken: false    # ⭐ don't give the app an API token it doesn't need
  hostNetwork: false                     # ⛔ true = it can sniff the node's traffic
  hostPID: false                         # ⛔ true = it can see every process on the node
  hostIPC: false
  shareProcessNamespace: false           # ⚠️ true lets containers see each other's processes
  enableServiceLinks: false              # ⭐ stops Docker-era env-var leakage of every service
  terminationGracePeriodSeconds: 30
  activeDeadlineSeconds: 600
  containers:
    - image: ghcr.io/3558bhk/shop-api@sha256:9f2a1b…    # ⭐⭐ PIN BY DIGEST
      imagePullPolicy: IfNotPresent
```

```bash
# ⭐ find images NOT pinned by digest
kubectl get pods -A -o json | jq -r '.items[] | . as $p |
  ($p.spec.containers[].image | select(test("@sha256:") | not) |
   "\($p.metadata.namespace)/\($p.metadata.name)  ⚠️ \(.)")' | head -20

# find :latest
kubectl get pods -A -o json | jq -r '.items[] | . as $p |
  ($p.spec.containers[].image | select(endswith(":latest") or (test(":") | not)) |
   "\($p.metadata.namespace)/\($p.metadata.name)  ⛔ \(.)")'

# find hostNetwork / privileged
kubectl get pods -A -o json | jq -r '.items[] | select(.spec.hostNetwork==true) | "\(.metadata.namespace)/\(.metadata.name)  ⛔ hostNetwork"'
kubectl get pods -A -o json | jq -r '.items[] | select(.spec.hostPID==true) | "\(.metadata.namespace)/\(.metadata.name)  ⛔ hostPID"'

# find SA tokens mounted where they aren't needed
kubectl get pods -A -o json | jq -r '.items[] | select(.spec.automountServiceAccountToken != false)
  | "\(.metadata.namespace)/\(.metadata.name)  ⚠️ token auto-mounted"' | head
```

---

<a name="22-admission-control-and-policy-engines"></a>
## 22. Admission control & policy engines

### 22.1 Where admission happens

```
kubectl apply -f x.yaml
   │
   ├── 1. AUTHENTICATION
   ├── 2. AUTHORIZATION (RBAC)
   │
   ├── 3. MUTATING ADMISSION  ← in order:
   │      a. built-in controllers (Namespace lifecycle, ServiceAccount token,
   │         default StorageClass, default tolerations, PSA in "warn"/"audit")
   │      b. MutatingWebhookConfigurations   (alphabetical, then by reinvocation)
   │
   ├── 4. OBJECT SCHEMA VALIDATION (types, required fields)
   │
   ├── 5. VALIDATING ADMISSION  ← in PARALLEL, any "deny" wins:
   │      a. ValidatingWebhookConfigurations
   │      b. ValidatingAdmissionPolicy (CEL) — v1.30+ stable, in-tree
   │      c. Pod Security Admission in "enforce" mode
   │      d. ResourceQuota admission
   │
   └── 6. PERSISTED TO ETCD
```

```bash
kubectl get mutatingwebhookconfigurations
kubectl get validatingwebhookconfigurations
kubectl get validatingadmissionpolicies
kubectl get validatingadmissionpolicybindings

kubectl describe mutatingwebhookconfiguration cert-manager-webhook
kubectl get validatingwebhookconfigurations -o json | jq -r '.items[] |
  .webhooks[] | "\(.name)  failurePolicy=\(.failurePolicy)  rules=\(.rules)"'
```

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingWebhookConfiguration
metadata: {name: shop-policies}
webhooks:
  - name: no-latest.shop.example.com
    admissionReviewVersions: [v1]
    sideEffects: None                 # ⭐ REQUIRED to declare
    failurePolicy: Fail               # ⭐ Fail = reject if the webhook is down | Ignore = allow
    timeoutSeconds: 5                 # ⭐ keep it low — this blocks EVERY matching request
    namespaceSelector:
      matchExpressions:
        - {key: kubernetes.io/metadata.name, operator: NotIn, values: [kube-system]}
    objectSelector:
      matchLabels: {policy-check: enabled}
    rules:
      - apiGroups: ["apps"]
        apiVersions: ["v1"]
        operations: ["CREATE", "UPDATE"]
        resources: ["deployments", "statefulsets"]
        scope: "Namespaced"
    clientConfig:
      service: {name: policy-webhook, namespace: policy, port: 443, path: /validate}
      # or: url: https://policy.example.com/validate
```

| `failurePolicy` | When the webhook is unreachable | Risk |
|---|---|---|
| `Fail` | **Reject** the request | ⛔ A down webhook = nothing can be deployed cluster-wide |
| `Ignore` | **Allow** the request | ⚠️ A down webhook = policies silently stop applying |

> 🔑 **`failurePolicy: Fail` on a cluster-wide webhook is a self-inflicted outage.** Always scope it with `namespaceSelector` (excluding `kube-system`), keep `timeoutSeconds` low, and give the webhook a PDB + multiple replicas.

```bash
# ⭐ the webhook-is-down incident
kubectl apply -f deploy.yaml
# Error from server: error when creating "deploy.yaml":
#   admission webhook "no-latest.shop.example.com" denied the request:
#   connection refused
# OR
#   failed calling webhook "…": Post "https://…": context deadline exceeded

kubectl get pods -n policy
kubectl get validatingwebhookconfiguration shop-policies -o jsonpath='{.webhooks[0].failurePolicy}'; echo

# the emergency escape hatch (⚠️ policies are now unenforced)
kubectl delete validatingwebhookconfiguration shop-policies
# or scope it away from your namespace:
kubectl patch validatingwebhookconfiguration shop-policies --type=json \
  -p='[{"op":"add","path":"/webhooks/0/namespaceSelector/matchExpressions/-",
        "value":{"key":"kubernetes.io/metadata.name","operator":"NotIn","values":["shop"]}}]'
```

### 22.2 ValidatingAdmissionPolicy — CEL, in-tree (v1.30+ stable)

No webhook, no external service, no availability risk:

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata: {name: no-latest-tag}
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
      - apiGroups: ["apps"]
        apiVersions: ["v1"]
        operations: ["CREATE", "UPDATE"]
        resources: ["deployments", "statefulsets", "daemonsets"]
  validations:
    - expression: |
        object.spec.template.spec.containers.all(c, !c.image.endsWith(":latest"))
      messageExpression: "'image ' + object.spec.template.spec.containers[0].image + ' uses :latest'"
      message: "the :latest tag is not allowed"
    - expression: |
        object.spec.template.spec.containers.all(c, has(c.resources.limits.memory))
      message: "every container must set a memory limit"
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata: {name: no-latest-binding}
spec:
  policyName: no-latest-tag
  validationActions: [Deny]
  matchResources:
    namespaceSelector:
      matchExpressions:
        - {key: kubernetes.io/metadata.name, operator: NotIn, values: [kube-system]}
```

```bash
kubectl get validatingadmissionpolicies
kubectl describe validatingadmissionpolicy no-latest-tag
kubectl apply -f deploy.yaml
# admission webhook / ValidatingAdmissionPolicy "no-latest-tag" denied the request:
#   the :latest tag is not allowed
```

### 22.3 Kyverno — YAML-native policies

```bash
helm repo add kyverno https://kyverno.github.io/kyverno/
helm install kyverno kyverno/kyverno -n kyverno --create-namespace --set replicaCount=3
```

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-resources
  annotations:
    policies.kyverno.io/title: Require resource requests and limits
spec:
  validationFailureAction: Enforce          # ⭐ Enforce | Audit
  background: true                          # ⭐ also check EXISTING resources
  rules:
    - name: check-resources
      match:
        any:
          - resources: {kinds: ["Pod"]}
      exclude:
        any:
          - resources: {namespaces: ["kube-system"]}
      validate:
        message: "CPU and memory requests and limits are required."
        pattern:
          spec:
            containers:
              - resources:
                  requests: {memory: "?*", cpu: "?*"}
                  limits:   {memory: "?*"}
    - name: disallow-latest
      match: {any: [{resources: {kinds: ["Pod"]}}]}
      validate:
        message: "Using a mutable image tag is not allowed."
        pattern:
          spec:
            containers:
              - image: "*:*"
              - =(image): "!*:latest"
---
# ⭐ MUTATE — add the labels everyone forgets
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata: {name: add-default-labels}
spec:
  rules:
    - name: add-team-label
      match: {any: [{resources: {kinds: ["Pod"]}}]}
      mutate:
        patchStrategicMerge:
          metadata:
            labels:
              +(team): platform
---
# ⭐ GENERATE — auto-create a NetworkPolicy in every new namespace
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata: {name: default-netpol}
spec:
  rules:
    - name: generate-deny
      match: {any: [{resources: {kinds: ["Namespace"]}}]}
      generate:
        kind: NetworkPolicy
        apiVersion: networking.k8s.io/v1
        name: default-deny
        namespace: "{{request.object.metadata.name}}"
        synchronize: true
        data:
          spec:
            podSelector: {}
            policyTypes: [Ingress]
```

```bash
kubectl get clusterpolicies
kubectl get policies -A
kubectl get policyreport -A                          # ⭐ violations on EXISTING resources
kubectl get policyreport -A -o json | jq -r '.items[].results[]
  | select(.result=="fail") | "\(.source)  \(.message)"' | head -20
kubectl describe clusterpolicy require-resources
kubectl logs -n kyverno -l app.kubernetes.io/name=kyverno --tail=50
```

### 22.4 Gatekeeper / OPA

```bash
helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts
helm install gatekeeper gatekeeper/gatekeeper -n gatekeeper-system --create-namespace
```

```yaml
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata: {name: k8srequiredlabels}
spec:
  crd:
    spec:
      names: {kind: K8sRequiredLabels}
      validation: {openAPIV3Schema: {type: object, properties: {labels: {type: array, items: {type: string}}}}}
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8srequiredlabels
        violation[{"msg": msg}] {
          required := input.parameters.labels[_]
          not input.review.object.metadata.labels[required]
          msg := sprintf("missing required label: %v", [required])
        }
---
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredLabels
metadata: {name: require-team}
spec:
  enforcementAction: deny            # deny | dryrun | warn
  match: {kinds: [{apiGroups: [""], kinds: ["Pod"]}]}
  parameters: {labels: ["team", "app"]}
```

```bash
kubectl get constrainttemplates
kubectl get k8srequiredlabels
kubectl get constraints
kubectl describe k8srequiredlabels require-team
kubectl gatekeeper status                       # the krew plugin
```

### 22.5 Kyverno vs Gatekeeper vs ValidatingAdmissionPolicy

| | Kyverno | Gatekeeper | ValidatingAdmissionPolicy |
|---|---|---|---|
| Policy language | **YAML** (patterns) | **Rego** (a logic language) | **CEL** (expression language) |
| Learning curve | Low | High | Medium |
| Mutating policies | ✅ | ✅ (limited) | ❌ |
| Generating resources | ✅ | ❌ | ❌ |
| Cleaning up existing | ✅ (`background: true`) | ✅ (audit mode) | ❌ (admission only) |
| Needs a webhook service | ✅ | ✅ | ❌ **in-tree** |
| Availability risk | A down webhook can block admission | Same | **None** |
| Reporting | `PolicyReport` CRD | Constraint `status` | `kubectl describe` |
| Best for | Teams that want YAML | Complex logic, existing OPA investment | Simple, always-on guardrails |

> 🔑 **The practical answer for most teams:** use **ValidatingAdmissionPolicy** for a small set of hard, always-on rules (no `:latest`, memory limits required, `runAsNonRoot`), and **Kyverno** for everything else including mutation and generation.

### 22.6 Image scanning and signing in the admission path

```bash
# Trivy operator — continuous scanning of what's RUNNING
helm repo add aqua https://aquasecurity.github.io/helm-charts/
helm install trivy-operator aqua/trivy-operator -n trivy-system --create-namespace \
  --set trivy.ignoreUnfixed=true \
  --set operator.scanJobsConcurrentLimit=3

kubectl get vulnerabilityreports -A
kubectl get vulnerabilityreports -A -o json | jq -r '.items[] |
  .report.artifact.repository as $img | .report.vulnerabilities[]
  | select(.severity=="CRITICAL") | "\($img):\(.severity) \(.vulnerabilityID) \(.title)"' | head -20
kubectl get configauditreports -A
kubectl get rbacassessmentreports -A
kubectl get exposurereports -A

# cosign — verify image signatures at admission (Kyverno policy)
cosign verify --certificate-identity-regexp='https://github.com/3558Bhk/.*' \
              --certificate-oidc-issuer=https://token.actions.githubusercontent.com \
              ghcr.io/3558bhk/shop-api:1.2.0
```

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata: {name: verify-image}
spec:
  validationFailureAction: Enforce
  rules:
    - name: verify-signature
      match:
        any:
          - resources: {kinds: ["Pod"], namespaces: ["shop-prod"]}
      verifyImages:
        - imageReferences: ["ghcr.io/3558bhk/*"]
          key: |-
            -----BEGIN PUBLIC KEY-----
            …
            -----END PUBLIC KEY-----
```

---

<a name="23-crds-and-operators"></a>
## 23. CRDs & operators

### 23.1 The object model

```
CustomResourceDefinition (CRD)      ← defines a NEW TYPE (cluster-scoped)
        │
        │ instances of
        ▼
Custom Resource (CR)                ← an actual object of that type
        │
        │ reconciled by
        ▼
Operator (a Deployment)             ← the controller that makes reality match the CR
```

```bash
kubectl get crds | head -30
kubectl get crds -o custom-columns='NAME:.metadata.name,GROUP:.spec.group,SCOPE:.spec.scope,KIND:.spec.names.kind,VERSIONS:.spec.versions[*].name'
kubectl describe crd clusters.postgresql.cnpg.io
kubectl api-resources | grep -v 'k8s.io'                 # ⭐ only the CRDs

# use them exactly like built-in resources
kubectl get cluster -n db                                # CloudNativePG
kubectl get cluster db -n db -o yaml
kubectl describe cluster db -n db
kubectl get servicemonitor -A                            # Prometheus operator
kubectl get certificaterequests -A                       # cert-manager
kubectl get issuer,clusterissuer -A
kubectl get applications -n argocd                       # Argo CD
kubectl get rollouts -A                                  # Argo Rollouts
kubectl get scaledobjects -A                             # KEDA
kubectl get policyreports -A                             # Kyverno
kubectl get vulnerabilityreports -A                      # Trivy
```

**CRDs you'll meet constantly:**

| Operator | CRDs |
|---|---|
| Prometheus Operator | `ServiceMonitor`, `PodMonitor`, `PrometheusRule`, `AlertmanagerConfig`, `Probe`, `Prometheus`, `Alertmanager`, `ThanosRuler` |
| cert-manager | `Certificate`, `CertificateRequest`, `Issuer`, `ClusterIssuer`, `Order`, `Challenge` |
| Argo CD | `Application`, `AppProject`, `ApplicationSet` |
| Argo Rollouts | `Rollout`, `Experiment`, `AnalysisTemplate`, `AnalysisRun` |
| Istio | `VirtualService`, `DestinationRule`, `Gateway`, `ServiceEntry`, `PeerAuthentication`, `AuthorizationPolicy` |
| Gateway API | `Gateway`, `HTTPRoute`, `GRPCRoute`, `GatewayClass`, `ReferenceGrant` |
| KEDA | `ScaledObject`, `ScaledJob`, `TriggerAuthentication` |
| Kyverno | `Policy`, `ClusterPolicy`, `PolicyReport`, `AdmissionReport` |
| CloudNativePG | `Cluster`, `Pooler`, `Backup`, `ScheduledBackup`, `Subscription`, `Publication` |
| Strimzi | `Kafka`, `KafkaTopic`, `KafkaUser`, `KafkaConnect`, `KafkaBridge` |
| External Secrets | `ExternalSecret`, `SecretStore`, `ClusterSecretStore`, `PushSecret` |
| Velero | `Backup`, `Restore`, `Schedule`, `BackupStorageLocation` |
| Crossplane | `CompositeResourceDefinition`, `Composition`, and every cloud provider's `X*` types |
| Flux | `GitRepository`, `Kustomization`, `HelmRelease`, `HelmRepository` |

### 23.2 Reading a CRD

```bash
kubectl explain cluster.spec --recursive | head -60      # ⭐ the operator's API, from the live cluster
kubectl get crd clusters.postgresql.cnpg.io -o json | jq '.spec.versions[] | {name, served, storage}'
kubectl get crd clusters.postgresql.cnpg.io -o json | jq '.spec.scope'
kubectl get crd clusters.postgresql.cnpg.io -o json | jq '.spec.versions[0].schema.openAPIV3Schema.properties.spec.properties | keys'
kubectl get crd clusters.postgresql.cnpg.io -o json | jq '.status.conditions'
```

| CRD field | Meaning |
|---|---|
| `spec.scope` | `Namespaced` or `Cluster` |
| `spec.versions[].served` | Is this version usable in requests? |
| `spec.versions[].storage` | ⭐ Exactly one must be true — the version etcd stores |
| `spec.versions[].schema` | The OpenAPI v3 validation |
| `spec.versions[].subresources.status` | Enables `/status` (so `spec` and `status` have separate RBAC) |
| `spec.versions[].subresources.scale` | ⭐ Enables `kubectl scale` and HPA on the CR |
| `spec.conversion.strategy` | `None` or `Webhook` (for multi-version conversion) |
| `spec.preserveUnknownFields` | ⛔ Must be false in v1 — unknown fields are pruned |
| `metadata.annotations.controller-gen.kubebuilder.io/version` | Who generated it |

```bash
# ⭐ a CRD with a scale subresource → an HPA can target it
kubectl get crd rollouts.argoproj.io -o json | jq '.spec.versions[0].subresources'
# {"scale":{"labelSelectorPath":".status.selector","specReplicasPath":".spec.replicas","statusReplicasPath":".status.replicas"},
#  "status":{}}
kubectl scale rollout/shop-api --replicas=5
kubectl autoscale rollout/shop-api --min=2 --max=10 --cpu-percent=70
```

### 23.3 The Operator pattern

```
       ┌────────────────────────────────────────────┐
       │  reconcile loop (runs forever)             │
       │                                            │
       │  1. WATCH the CR (and its children)        │
       │  2. Compute DESIRED state from .spec       │
       │  3. Observe ACTUAL state from the cluster  │
       │  4. DIFF them                              │
       │  5. ACT to close the gap                   │
       │  6. Write .status                          │
       │  7. Requeue (immediately, or after N sec)  │
       └────────────────────────────────────────────┘
```

**The golden rule: an operator is level-triggered, not edge-triggered.** It doesn't care *what* changed — it re-derives the desired state from scratch every time. That's why deleting a managed resource just makes the operator recreate it.

```bash
# ⭐ demonstrate it
kubectl delete svc db-rw -n db            # CloudNativePG's service
kubectl get svc db-rw -n db -w            # …back within seconds

# read the operator's logs
kubectl logs -n db -l cnpg.io/cluster=db --tail=50
kubectl logs -n cnpg-system deploy/cnpg-controller-manager --tail=100 -f
kubectl logs -n cnpg-system deploy/cnpg-controller-manager --tail=500 | grep -iE 'error|reconcil'

# read the CR's status — the operator's own report card
kubectl get cluster db -n db -o json | jq '.status'
# {"phase":"Cluster in healthy state",
#  "readyInstances":3,
#  "conditions":[{"type":"Ready","status":"True","reason":"ClusterIsReady"},
#                {"type":"ContinuousArchiving","status":"True"},
#                {"type":"LastBackupSucceeded","status":"True"}],
#  "topology":{"successfullyExtracted":true,"instances":3,"nodesUsed":3}}

kubectl describe cluster db -n db | tail -30
```

### 23.4 CRD lifecycle and versioning

```bash
# install order matters: the CRD must exist BEFORE the CRs
kubectl apply --server-side -f crd.yaml
kubectl wait --for condition=Established --timeout=60s crd/clusters.postgresql.cnpg.io   # ⭐
kubectl apply -f cluster.yaml

# a CRD is Established when the API server has registered it
kubectl get crd clusters.postgresql.cnpg.io -o jsonpath='{.status.conditions}'; echo
# [{"type":"NamesAccepted","status":"True"},{"type":"Established","status":"True"}]

# delete a CRD → ⛔ EVERY CR of that type is deleted, immediately, in all namespaces
kubectl get crd clusters.postgresql.cnpg.io -o json | jq '.metadata.finalizers'
kubectl delete crd clusters.postgresql.cnpg.io
```

⚠️ **Deleting a CRD is the single most destructive one-liner in Kubernetes.** All custom resources of that kind are garbage-collected instantly. Helm deletes CRDs on uninstall **only** if you tell it to (it normally leaves them, printing a warning) — and that's the right default.

**Multi-version conversion:**

```yaml
spec:
  group: example.com
  versions:
    - name: v1
      served: true
      storage: true                 # ⭐ the canonical stored version
      schema: {openAPIV3Schema: …}
    - name: v1alpha1
      served: true
      storage: false
      schema: {openAPIV3Schema: …}
      deprecated: true              # ⭐ warn on use
      deprecationWarning: "example.com/v1alpha1 Widget is deprecated; use v1"
  conversion:
    strategy: Webhook               # or None (same schema shape)
    webhook:
      conversionReviewVersions: [v1]
      clientConfig:
        service: {name: widget-conversion, namespace: widget-system, path: /convert}
```

```bash
kubectl apply -f widget.yaml --validate=strict
# Warning: example.com/v1alpha1 Widget is deprecated; use v1
kubectl get widgets.v1alpha1 -o yaml        # converted on read
kubectl get widgets.v1 -o yaml              # the stored version
```

### 23.5 Aggregated API servers (APIServices)

```bash
kubectl get apiservices
kubectl get apiservices | grep -v True        # ⭐ broken ones
# v1beta1.metrics.k8s.io   kube-system/metrics-server   False   10m   service/metrics-server not found
# v1.external.metrics.k8s.io  keda/keda-metrics-apiserver  False  5m   …

kubectl describe apiservice v1beta1.metrics.k8s.io
# Status:
#   Conditions:
#     Type            Status  Reason              Message
#     Available       False   ServiceNotFound     service/metrics-server not found
#     FailedDiscoveryCheck  True  …
```

⚠️ **A broken APIService blocks namespace deletion** (see §9.3) and makes `kubectl get all` hang. Fix or delete it first.

---

<a name="24-monitoring-and-resource-usage"></a>
## 24. Monitoring & resource usage

### 24.1 `kubectl top`

```bash
kubectl top nodes
kubectl top nodes --sort-by=cpu
kubectl top nodes --sort-by=memory
kubectl top pods -A
kubectl top pods -A --sort-by=memory
kubectl top pods -n shop --containers
kubectl top pods -n shop --containers --sort-by=cpu
kubectl top pod nginx -n shop --containers
```

```bash
kubectl top nodes
# NAME                 CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%
# learn-control-plane  312m         3%     1834Mi          11%
# learn-worker         2841m        36%    9214Mi          59%
# learn-worker2        1203m        15%    5512Mi          35%

kubectl top pods -n shop --containers
# POD                       NAME        CPU(cores)   MEMORY(bytes)
# shop-api-7d4f8c9b6-abcde  api         87m          812Mi
# shop-api-7d4f8c9b6-abcde  sidecar     3m           24Mi
```

⚠️ **`kubectl top` is a snapshot, not a history.** It's metrics-server's last scrape (default 15s resolution, ~1 minute of window). A spike that happened 5 minutes ago is invisible.

### 24.2 The raw metrics API

```bash
kubectl get --raw "/apis/metrics.k8s.io/v1beta1/nodes" | jq '.items[] | {node: .metadata.name, cpu: .usage.cpu, mem: .usage.memory}'
kubectl get --raw "/apis/metrics.k8s.io/v1beta1/namespaces/shop/pods" | jq '.items[] |
  {pod: .metadata.name, containers: [.containers[] | {name, cpu: .usage.cpu, mem: .usage.memory}]}'
kubectl get --raw "/apis/metrics.k8s.io/v1beta1/namespaces/shop/nodes/learn-worker" 2>/dev/null | jq .
```

**Units you'll see:**

| Value | Meaning |
|---|---|
| `1` CPU | 1 core = 1000m = 1 vCPU |
| `500m` | Half a core |
| `12345678n` | **nano**-cores (1e-9) — what the metrics API returns: `87345612n` ≈ 87m |
| `1Gi` | 1024³ bytes |
| `1G` | 1000³ bytes |
| `1234Ki` / `Mi` / `Gi` / `Ti` | Binary |
| `1234k` / `M` / `G` / `T` | Decimal |

### 24.3 Prometheus — the real monitoring

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install kps prometheus-community/kube-prometheus-stack -n monitoring --create-namespace \
  -f kps-values.yaml
kubectl get pods -n monitoring
kubectl port-forward -n monitoring svc/kps-grafana 3000:80 &
kubectl port-forward -n monitoring svc/kps-kube-prometheus-stack-prometheus 9090:9090 &
kubectl port-forward -n monitoring svc/kps-kube-prometheus-stack-alertmanager 9093:9093 &
```

```bash
# ⭐ the queries that matter
kubectl get servicemonitors -A
kubectl get podmonitors -A
kubectl get prometheusrules -A
kubectl get prometheusrules -A -o json | jq -r '.items[] | .metadata.name as $n |
  .spec.groups[].rules[] | select(.alert) | "\($n)  \(.alert)  \(.expr)"' | head -20

# query Prometheus directly
curl -s 'http://localhost:9090/api/v1/query' --data-urlencode \
  'query=sum(rate(container_cpu_usage_seconds_total{namespace="shop"}[5m])) by (pod)' | jq -r '.data.result[] | "\(.metric.pod)  \(.value[1])"'

curl -s 'http://localhost:9090/api/v1/query' --data-urlencode \
  'query=container_memory_working_set_bytes{namespace="shop"} / 1024 / 1024' | jq -r '.data.result[] | "\(.metric.pod)  \(.value[1]|tonumber|floor) MiB"'

curl -s 'http://localhost:9090/api/v1/query' --data-urlencode \
  'query=kube_pod_container_status_restarts_total > 0' | jq -r '.data.result[] | "\(.metric.namespace)/\(.metric.pod)  \(.value[1])"'

curl -s 'http://localhost:9090/api/v1/query' --data-urlencode \
  'query=sum(kube_node_status_allocatable{resource="cpu"}) - sum(kube_pod_container_resource_requests{resource="cpu"})' | jq .

# the CPU throttling query — the one that finds hidden latency
curl -s 'http://localhost:9090/api/v1/query' --data-urlencode 'query=
  sum(rate(container_cpu_cfs_throttled_periods_total{namespace="shop"}[5m]))
  / sum(rate(container_cpu_cfs_periods_total{namespace="shop"}[5m]))' | jq .
# > 0.25 = ⛔ you're throttled a quarter of the time; raise or remove the CPU limit
```

**The essential metrics:**

| Metric | What it tells you |
|---|---|
| `container_cpu_usage_seconds_total` | CPU actually used |
| `container_cpu_cfs_throttled_periods_total` / `container_cpu_cfs_periods_total` | ⭐ **CPU throttling ratio** |
| `container_memory_working_set_bytes` | ⭐ What the OOM killer compares against your limit |
| `container_memory_rss` | Resident set (excludes page cache) |
| `kube_pod_container_status_restarts_total` | Restart counts |
| `kube_pod_container_status_last_terminated_reason` | ⭐ `OOMKilled`, `Error`, `Completed` |
| `kube_pod_status_phase` | Pending/Running/Failed |
| `kube_deployment_status_replicas_available` | Ready replicas |
| `kube_node_status_condition{condition="Ready"}` | Node health |
| `kubelet_pod_start_duration_seconds` | How slow Pod startup is |
| `apiserver_request_duration_seconds` | API server latency |
| `etcd_disk_wal_fsync_duration_seconds` | ⭐ etcd disk health |
| `workqueue_depth` | Controller backlogs |

### 24.4 Alerts

```bash
kubectl get prometheusrules -A
kubectl get alertmanagerconfigs -A
kubectl port-forward -n monitoring svc/kps-…-alertmanager 9093:9093 &
curl -s localhost:9093/api/v2/alerts | jq '.[] | {labels: .labels.alertname, status: .status.state, startsAt}'
curl -s localhost:9093/api/v2/alerts | jq -r '.[] | "\(.labels.severity)  \(.labels.alertname)  \(.labels.namespace)/\(.labels.pod)"'
```

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata: {name: shop-alerts, namespace: monitoring, labels: {release: kps}}
spec:
  groups:
    - name: shop.rules
      rules:
        - alert: ShopApiHighRestartRate
          expr: increase(kube_pod_container_status_restarts_total{namespace="shop"}[15m]) > 3
          for: 2m
          labels: {severity: warning, team: platform}
          annotations:
            summary: "{{ $labels.pod }} restarted {{ $value }} times in 15m"
            description: "Check `kubectl logs {{ $labels.pod }} -n {{ $labels.namespace }} --previous`"
            runbook: https://wiki.example.com/runbooks/high-restarts
        - alert: ShopApiOOMKilled
          expr: kube_pod_container_status_last_terminated_reason{namespace="shop", reason="OOMKilled"} > 0
          for: 0m
          labels: {severity: critical}
        - alert: ShopApiHighLatency
          expr: histogram_quantile(0.99, sum(rate(http_server_duration_seconds_bucket{namespace="shop"}[5m])) by (le, route)) > 0.5
          for: 5m
          labels: {severity: warning}
        - alert: ShopApiReplicasBelowMin
          expr: kube_deployment_status_replicas_available{namespace="shop", deployment="shop-api"} < 2
          for: 3m
          labels: {severity: critical}
```

### 24.5 Health endpoints and probes

```bash
kubectl get --raw='/healthz'          # deprecated alias for /livez
kubectl get --raw='/livez?verbose'
kubectl get --raw='/readyz?verbose'
kubectl get --raw='/livez?verbose' | grep -v '\[+\]'
```

```yaml
containers:
  - name: api
    startupProbe:                          # ⭐ run FIRST, until it succeeds
      httpGet: {path: /actuator/health/liveness, port: 8080}
      failureThreshold: 30                 # 30 × 10s = up to 5 minutes to start
      periodSeconds: 10
    livenessProbe:                         # ⭐ "restart me if I'm stuck"
      httpGet: {path: /actuator/health/liveness, port: 8080}
      initialDelaySeconds: 0               # (the startupProbe covers this)
      periodSeconds: 20
      timeoutSeconds: 5
      failureThreshold: 3
    readinessProbe:                        # ⭐ "remove me from the Service if I can't serve"
      httpGet: {path: /actuator/health/readiness, port: 8080}
      periodSeconds: 10
      timeoutSeconds: 3
      failureThreshold: 3
      successThreshold: 1
    lifecycle:
      preStop:                             # ⭐ run BEFORE SIGTERM
        exec: {command: ["sh","-c","sleep 10"]}     # let endpoints propagate
      postStart:
        exec: {command: ["sh","-c","echo started"]}
```

| Probe | Fails → | Use for |
|---|---|---|
| `startupProbe` | Keeps trying until `failureThreshold × periodSeconds`, then kills | Slow starters (JVMs) |
| `livenessProbe` | **Restarts the container** | Deadlocks, unrecoverable states |
| `readinessProbe` | **Removes it from the Service endpoints** | Dependencies down, warming up |

> 🔑 **The #1 probe mistake: a livenessProbe that checks a dependency.** If your liveness probe calls the database, a DB outage restarts every Pod in a storm — turning a partial outage into a total one. **Liveness = "am I alive?" (no external checks). Readiness = "can I serve?" (check dependencies).**

```bash
# see the probe configuration
kubectl get deploy shop-api -o json | jq '.spec.template.spec.containers[0] | {startupProbe, livenessProbe, readinessProbe}'
kubectl describe pod shop-api-… | grep -E 'Liveness|Readiness|Startup'
# Liveness:  http-get http://:8080/actuator/health/liveness delay=0s timeout=5s period=20s #success=1 #failure=3

# see the failures
kubectl get events -n shop --field-selector reason=Unhealthy --sort-by=.lastTimestamp
kubectl describe pod shop-api-… | grep -A15 Events
# Warning  Unhealthy  2m (x5)  kubelet  Readiness probe failed: Get "http://10.244.2.19:8080/…": context deadline exceeded
# Warning  Unhealthy  1m (x3)  kubelet  Liveness probe failed: HTTP probe failed with statuscode: 503
# Normal   Killing    1m       kubelet  Container api failed liveness probe, will be restarted

# test the probe manually
kubectl exec deploy/shop-api -- wget -qO- http://localhost:8080/actuator/health/readiness
kubectl exec deploy/shop-api -- curl -sv http://localhost:8080/actuator/health/liveness
kubectl run probe-test --image=curlimages/curl:8.10.1 --rm -it --restart=Never -- \
  curl -sv -m 3 http://shop-api.shop.svc.cluster.local/actuator/health/readiness
```

---

<a name="25-cluster-maintenance"></a>
## 25. Cluster maintenance

### 25.1 cordon / drain / uncordon

```bash
kubectl cordon learn-worker                     # ⭐ mark unschedulable; existing pods STAY
kubectl uncordon learn-worker
kubectl get nodes
# NAME                 STATUS                     ROLES           AGE   VERSION
# learn-worker         Ready,SchedulingDisabled   <none>          12d   v1.37.0

kubectl drain learn-worker --ignore-daemonsets --delete-emptydir-data
kubectl drain learn-worker --ignore-daemonsets --delete-emptydir-data --force
kubectl drain learn-worker --ignore-daemonsets --delete-emptydir-data --grace-period=60
kubectl drain learn-worker --ignore-daemonsets --delete-emptydir-data --timeout=10m
kubectl drain learn-worker --ignore-daemonsets --delete-emptydir-data --disable-eviction    # ⛔ bypasses PDBs
kubectl drain learn-worker --ignore-daemonsets --delete-emptydir-data --pod-selector='app!=critical'
kubectl drain learn-worker --ignore-daemonsets --delete-emptydir-data --dry-run=server      # ⭐ preview
```

| Flag | Why you need it |
|---|---|
| `--ignore-daemonsets` | ⭐ **Always.** DaemonSet Pods can't be evicted (they'd be recreated instantly) |
| `--delete-emptydir-data` | Pods using `emptyDir` would lose data |
| `--force` | Evict **bare Pods** (not managed by a controller) — they're deleted permanently |
| `--grace-period=N` | Override `terminationGracePeriodSeconds` |
| `--timeout=Ns` | Stop retrying after N seconds |
| `--disable-eviction` | ⛔ Use DELETE instead of the eviction API — **bypasses PDBs** |
| `--pod-selector` | Only drain matching Pods |
| `--skip-wait-for-delete-timeout` | Don't wait for graceful termination |

**The correct node-maintenance sequence:**

```bash
NODE=learn-worker

# 1. cordon first — stop new pods landing
kubectl cordon $NODE

# 2. check what's there and whether anything can be moved
kubectl get pods -A --field-selector spec.nodeName=$NODE -o wide
kubectl get pdb -A -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,ALLOWED:.status.disruptionsAllowed'

# 3. scale up the critical workloads so the drain can proceed
kubectl scale deploy/shop-api -n shop --replicas=5

# 4. dry-run
kubectl drain $NODE --ignore-daemonsets --delete-emptydir-data --dry-run=server

# 5. drain (with a timeout so you don't hang forever)
kubectl drain $NODE --ignore-daemonsets --delete-emptydir-data --timeout=10m

# 6. verify nothing user-facing is left
kubectl get pods -A --field-selector spec.nodeName=$NODE
# only kube-system DaemonSet pods should remain

# 7. do the maintenance (reboot, kernel upgrade, hardware)
ssh $NODE sudo reboot

# 8. wait for it to come back
kubectl wait --for=condition=Ready node/$NODE --timeout=10m

# 9. uncordon
kubectl uncordon $NODE

# 10. scale back down
kubectl scale deploy/shop-api -n shop --replicas=3
```

### 25.2 Upgrades

**The order is non-negotiable:**

```
1. etcd (back it up first!)
2. kube-apiserver, kube-controller-manager, kube-scheduler   ← the control plane
3. cloud-controller-manager, cluster addons (CNI, CoreDNS, kube-proxy)
4. kubelet on each node                                       ← one at a time: cordon → drain → upgrade → uncordon
5. kubectl                                                      ← to within ±1 of the server
```

```bash
# kubeadm
kubectl get nodes -o wide                             # current versions
sudo kubeadm version
sudo kubeadm upgrade plan                             # ⭐ what it would do
sudo kubeadm upgrade apply v1.37.0
kubectl get pods -n kube-system -w                    # the control-plane pods restart

# the nodes, one at a time
NODE=learn-worker
kubectl drain $NODE --ignore-daemonsets --delete-emptydir-data
sudo apt-get update && sudo apt-get install -y kubelet=1.37.0-1.1 kubeadm=1.37.0-1.1 kubectl=1.37.0-1.1
sudo systemctl daemon-reload && sudo systemctl restart kubelet
kubectl uncordon $NODE
kubectl get node $NODE -o jsonpath='{.status.nodeInfo.kubeletVersion}'; echo

# managed services
aws eks update-cluster-version --name prod --kubernetes-version 1.37
aws eks update-nodegroup-version --cluster-name prod --nodegroup-name default
gcloud container clusters upgrade prod --cluster-version=1.37.0-gke.100 --region=us-central1
az aks upgrade --resource-group rg --name prod --kubernetes-version 1.37.0

# kind — you can't upgrade; recreate
kind delete cluster --name learn
KIND_CLUSTER_VERSION=v1.37.0 kind create cluster --name learn --config kind.yaml
```

**The pre-upgrade checklist:**

```bash
# 1. version skew — is anything already out of policy?
kubectl get nodes -o custom-columns='NAME:.metadata.name,KUBELET:.status.nodeInfo.kubeletVersion,PROXY:.status.nodeInfo.kubeProxyVersion,RUNTIME:.status.nodeInfo.containerRuntimeVersion'

# 2. deprecated APIs in use ⭐⭐ the #1 cause of a failed upgrade
kubectl krew install deprecations
kubectl deprecations --k8s-version v1.37 ./k8s/
pluto detect-all-in-cluster
kubent                                # kube-no-trouble
kubectl get all,cm,secret,ingress,hpa,pdb,cronjob,job,netpol,sa,role,rolebinding,clusterrole,clusterrolebinding -A -o json \
  | jq -r '.items[].apiVersion' | sort | uniq -c | sort -rn

# 3. back up etcd
ETCDCTL_API=3 etcdctl snapshot save /backup/etcd-$(date +%F).db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key
ETCDCTL_API=3 etcdctl snapshot status /backup/etcd-$(date +%F).db --write-table
velero backup create pre-upgrade-$(date +%F) --wait

# 4. the control plane's health
kubectl get --raw='/readyz?verbose' | grep -v '\[+\]'
kubectl get componentstatuses 2>/dev/null
kubectl get apiservices | grep -v True

# 5. addon compatibility (CNI, ingress, cert-manager, service mesh, operators)
helm list -A
kubectl get pods -A | grep -vE 'Running|Completed'
```

### 25.3 etcd — backup and restore

```bash
# where it lives
kubectl get pods -n kube-system | grep etcd
kubectl describe pod -n kube-system etcd-learn-control-plane | grep -E 'Image:|--data-dir|Host Path'
#   --data-dir=/var/lib/etcd
#   Host Path: /var/lib/etcd

# health
kubectl exec -n kube-system etcd-learn-control-plane -- etcdctl \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint health
# https://127.0.0.1:2379 is healthy: successfully committed proposal: took = 2.1ms

kubectl exec -n kube-system etcd-learn-control-plane -- etcdctl \
  --cacert=… --cert=… --key=… endpoint status --write-table
# +----------------+------------------+---------+---------+-----------+------------+
# |    ENDPOINT    |       ID         | VERSION | DB SIZE | IS LEADER | RAFT INDEX |
# +----------------+------------------+---------+---------+-----------+------------+
# | 127.0.0.1:2379 | 8e9e05c52164694d |  3.5.x  |  58 MB  |   true    |     123456 |

# ⭐ the 8 GB default quota — running out of it is a cluster-wide outage
kubectl exec -n kube-system etcd-learn-control-plane -- etcdctl --cacert=… --cert=… --key=… alarm list
# memberID:… alarm:NOSPACE

# backup
kubectl exec -n kube-system etcd-learn-control-plane -- etcdctl \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save /var/lib/etcd-backup/snapshot-$(date +%F).db

# restore (⚠️ stop the API servers first, and this replaces EVERYTHING)
ETCDCTL_API=3 etcdctl snapshot restore /backup/snapshot-2026-09-09.db \
  --data-dir=/var/lib/etcd-restore \
  --name=learn-control-plane \
  --initial-cluster=learn-control-plane=https://172.18.0.2:2380 \
  --initial-advertise-peer-urls=https://172.18.0.2:2380

# what's in etcd? (the raw key space)
kubectl exec -n kube-system etcd-learn-control-plane -- etcdctl --cacert=… --cert=… --key=… \
  get / --prefix --keys-only | sed 's|/registry/||' | cut -d/ -f1-3 | sort -u | head -40

# the biggest objects (etcd bloat usually = huge Secrets or Events)
kubectl get --raw /metrics | grep -E 'etcd_db_total_size_in_bytes|apiserver_storage_objects' | head -20
```

**The etcd problems that actually happen:**

| Symptom | Cause | Fix |
|---|---|---|
| `etcdserver: mvcc: database space exceeded` | Hit the 8 GB quota | Defragment, compact, raise `--quota-backend-bytes` |
| `apply request took too long` in the logs | Slow disk (fsync > 10ms) | Move etcd to SSD/NVMe; check `etcd_disk_wal_fsync_duration_seconds` |
| `leader changed` repeatedly | Network latency between members | Check inter-node RTT (< 10ms for same-region) |
| The API server is slow, etcd is fine | Too many LIST requests | Enable the watch cache; find the offending controller |
| DB size grows forever | No compaction | `--auto-compaction-mode=periodic --auto-compaction-retention=1h` |

```bash
# compaction + defragmentation (the standard maintenance)
REV=$(kubectl exec -n kube-system etcd-learn-control-plane -- etcdctl --cacert=… --cert=… --key=… \
      endpoint status --write-out=json | jq '.[0].Status.header.revision')
kubectl exec -n kube-system etcd-learn-control-plane -- etcdctl --cacert=… --cert=… --key=… compact $REV
kubectl exec -n kube-system etcd-learn-control-plane -- etcdctl --cacert=… --cert=… --key=… \
  --command-timeout=300s defrag --cluster
kubectl exec -n kube-system etcd-learn-control-plane -- etcdctl --cacert=… --cert=… --key=… alarm disarm
```

### 25.4 Certificates

```bash
# kubeadm-managed
sudo kubeadm certs check-expiration
# CERTIFICATE                EXPIRES                  RESIDUAL TIME   CERTIFICATE AUTHORITY   EXTERNALLY MANAGED
# admin                      Sep 09, 2027 09:32 UTC   364d            ca                      no
# apiserver                  Sep 09, 2027 09:32 UTC   364d            ca                      no
# apiserver-etcd-client      Sep 09, 2027 09:32 UTC   364d            etcd-ca                 no
# apiserver-kubelet-client   Sep 09, 2027 09:32 UTC   364d            ca                      no
# controller-manager.conf    Sep 09, 2027 09:32 UTC   364d            ca                      no
# etcd-server                Sep 09, 2027 09:32 UTC   364d            etcd-ca                 no
# front-proxy-client         Sep 09, 2027 09:32 UTC   364d            front-proxy-ca          no
# scheduler.conf             Sep 09, 2027 09:32 UTC   364d            ca                      no
# CERTIFICATE AUTHORITY   EXPIRES                  RESIDUAL TIME
# ca                      Sep 07, 2036 09:32 UTC   9y
# etcd-ca                 Sep 07, 2036 09:32 UTC   9y
# front-proxy-ca          Sep 07, 2036 09:32 UTC   9y

sudo kubeadm certs renew all
sudo systemctl restart kubelet
kubectl get --raw='/readyz?verbose' | head

# inspect any certificate
openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -text | grep -A2 'Validity\|Subject:\|DNS:'
openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -dates
openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -subject -issuer
openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -ext subjectAltName

# the API server's serving cert, from outside
echo | openssl s_client -connect 127.0.0.1:6443 -servername kubernetes 2>/dev/null \
  | openssl x509 -noout -dates -subject -ext subjectAltName

# a kubeconfig's embedded cert
kubectl config view --raw --minify -o jsonpath='{.users[0].user.client-certificate-data}' \
  | base64 -d | openssl x509 -noout -dates -subject
# notBefore=Sep  9 09:32:11 2025 GMT
# notAfter=Sep  9 09:32:11 2026 GMT        ← ⭐ expires in a year
# subject=O = system:masters, CN = kubernetes-admin

# ⚠️ O=system:masters is cluster-admin and CANNOT be revoked without rotating the CA
```

**In-cluster TLS (cert-manager):**

```bash
kubectl get certificates -A
kubectl get certificaterequests -A
kubectl get orders -A
kubectl get challenges -A                       # ⭐ ACME challenges — stuck ones block issuance
kubectl describe certificate shop-tls -n shop
kubectl get certificate shop-tls -n shop -o jsonpath='{.status.conditions}' | jq .
# [{"type":"Ready","status":"False","reason":"Pending","message":"Waiting for CertificateRequest to complete"}]

kubectl logs -n cert-manager deploy/cert-manager --tail=100
kubectl logs -n cert-manager deploy/cert-manager-webhook --tail=50
kubectl logs -n cert-manager deploy/cert-manager-cainjector --tail=50

kubectl get clusterissuer letsencrypt-prod -o jsonpath='{.status.conditions}' | jq .
kubectl describe clusterissuer letsencrypt-prod
```

---

<a name="26-node-management"></a>
## 26. Node management

### 26.1 Reading a Node

```bash
kubectl get nodes
kubectl get nodes -o wide
kubectl get nodes --show-labels
kubectl get nodes -L topology.kubernetes.io/zone -L kubernetes.io/hostname -L node.kubernetes.io/instance-type
kubectl describe node learn-worker
kubectl get node learn-worker -o yaml | kubectl neat
kubectl get nodes -o custom-columns=\
'NAME:.metadata.name,STATUS:.status.conditions[-1].type,VERSION:.status.nodeInfo.kubeletVersion,OS:.status.nodeInfo.osImage,KERNEL:.status.nodeInfo.kernelVersion,RUNTIME:.status.nodeInfo.containerRuntimeVersion,CPU:.status.capacity.cpu,MEM:.status.capacity.memory,PODS:.status.capacity.pods'
```

**Node conditions:**

| Condition | `True` means |
|---|---|
| `Ready` | ✅ The kubelet is healthy and accepting Pods |
| `MemoryPressure` | The kubelet's eviction threshold for memory is crossed |
| `DiskPressure` | Disk (imagefs or nodefs) is low |
| `PIDPressure` | PIDs are running out |
| `NetworkUnavailable` | The node's network isn't configured (CNI failure) |

```bash
kubectl get nodes -o json | jq -r '.items[] | .metadata.name as $n |
  (.status.conditions[] | select(.status=="True" and .type!="Ready") | "\($n)  ⛔ \(.type): \(.message)")'
kubectl get nodes -o json | jq -r '.items[] | .metadata.name as $n |
  (.status.conditions[] | select(.type=="Ready") | "\($n)  Ready=\(.status)  since \(.lastTransitionTime)")'
```

### 26.2 Capacity vs Allocatable

```bash
kubectl describe node learn-worker | sed -n '/Capacity/,/System Info/p'
```

```
Capacity:                          ← what the HARDWARE has
  cpu:                8
  ephemeral-storage:  105546736Ki
  hugepages-1Gi:      0
  hugepages-2Mi:      0
  memory:             16302432Ki
  pods:               110
Allocatable:                       ← what PODS may request
  cpu:                7800m        ← minus kube-reserved (150m) and system-reserved (50m)
  ephemeral-storage:  97270889932
  memory:             15474400Ki   ← minus ~800Mi reserved
  pods:               110
```

```
Allocatable = Capacity − kube-reserved − system-reserved − eviction-hard
```

```bash
# see the reservation config
kubectl get --raw /api/v1/nodes/learn-worker/proxy/configz | jq '.kubeletconfig |
  {kubeReserved, systemReserved, evictionHard, evictionSoft, maxPods, containerLogMaxSize, containerLogMaxFiles}'
# {"kubeReserved":{"cpu":"100m","memory":"100Mi"},
#  "systemReserved":{"cpu":"50m","memory":"50Mi"},
#  "evictionHard":{"imagefs.available":"15%","memory.available":"100Mi","nodefs.available":"10%","nodefs.inodesFree":"5%"},
#  "maxPods":110,
#  "containerLogMaxSize":"10Mi",
#  "containerLogMaxFiles":5}
```

| `evictionHard` threshold | Default | Effect when crossed |
|---|---|---|
| `memory.available` | 100Mi | `MemoryPressure` → evict BestEffort, then Burstable |
| `nodefs.available` | 10% | `DiskPressure` → evict, then garbage-collect images |
| `nodefs.inodesFree` | 5% | `DiskPressure` |
| `imagefs.available` | 15% | `DiskPressure` → garbage-collect unused images |

### 26.3 Allocated resources — the number that matters

```bash
kubectl describe node learn-worker | sed -n '/Allocated resources/,/Events/p'
```

```
Allocated resources:
  (Total limits may be over 100 percent, i.e., overcommitted.)
  Resource           Requests      Limits
  --------           --------      ------
  cpu                3250m (41%)   9200m (117%)
  memory             4812Mi (31%)  12480Mi (80%)
  ephemeral-storage  0 (0%)        2Gi (2%)
  pods               12            (10%)
Non-terminated Pods:          (12 in total)
  Namespace    Name                         CPU Requests  CPU Limits  Memory Requests  Memory Limits
  kube-system  coredns-5d78c9869d-abcde     100m (1%)     0 (0%)      70Mi (0%)        170Mi (1%)
  shop         shop-api-7d4f8c9b6-abcde     500m (6%)     2 (25%)     1Gi (6%)         1536Mi (9%)
```

> 🔑 **Requests drive scheduling. Limits drive enforcement.**
> - `cpu 41% requested` → the scheduler can only place 59% more CPU here.
> - `cpu 117% limited` → **normal and desirable** (CPU is compressible; overcommit is fine).
> - `memory 80% limited` → ⚠️ **dangerous.** Memory is incompressible; if all Pods hit their limits the kernel OOM-kills.

```bash
# ⭐ compute the whole cluster's headroom
kubectl describe nodes | grep -A5 'Allocated resources' | grep -E 'cpu|memory'

# the plugin version, much nicer
kubectl resource-capacity --utilization
kubectl resource-capacity --utilization --sort-by cpu
kubectl resource-capacity -n shop --pods 20          # "can I fit 20 more pods here?"
```

### 26.4 Node labels, taints, and roles

```bash
kubectl label node learn-worker node-role.kubernetes.io/worker=
kubectl label node learn-worker disktype=nvme topology=internal
kubectl label node learn-worker disktype-                     # remove
kubectl taint node learn-worker dedicated=shop:NoSchedule
kubectl taint node learn-worker dedicated=shop:NoSchedule-    # remove

# the standard labels (set automatically)
kubectl get nodes -o json | jq -r '.items[0].metadata.labels'
# {"beta.kubernetes.io/arch":"amd64",
#  "beta.kubernetes.io/os":"linux",
#  "kubernetes.io/arch":"amd64",
#  "kubernetes.io/hostname":"learn-worker",
#  "kubernetes.io/os":"linux",
#  "node-role.kubernetes.io/worker":"",
#  "node.kubernetes.io/exclude-from-external-load-balancers":"",
#  "topology.kubernetes.io/region":"ap-south-1",
#  "topology.kubernetes.io/zone":"ap-south-1a"}
```

⚠️ **`node-role.kubernetes.io/*` labels are cosmetic.** The scheduler ignores them entirely — only taints and your own labels matter. A node with the `worker` role label is not treated differently from one without.

### 26.5 Adding and removing nodes

```bash
# kubeadm: generate a join token
sudo kubeadm token create --print-join-command
# kubeadm join 172.18.0.2:6443 --token abc123.xyz --discovery-token-ca-cert-hash sha256:9f2a…
# (run that on the new node as root)
kubectl get nodes -w

# remove a node
NODE=learn-worker3
kubectl drain $NODE --ignore-daemonsets --delete-emptydir-data --timeout=10m
kubectl delete node $NODE                       # removes it from the API
# on the node itself:
sudo kubeadm reset -f && sudo rm -rf /etc/cni/net.d /var/lib/cni /var/lib/etcd
# on a control-plane node, clean up the RBAC:
sudo kubeadm reset remove-node $NODE

# a node that went NotReady
kubectl describe node learn-worker | grep -A8 Conditions
kubectl get lease -n kube-node-lease learn-worker -o jsonpath='{.spec.renewTime}'; echo
# 2026-09-09T14:12:11Z     ← 50 minutes stale → the kubelet stopped heartbeating

# the automatic timeline after a node stops heartbeating:
#   t+0s     the kubelet misses its lease renewal (every 10s by default)
#   t+40s    the node controller marks it NotReady (node-monitor-grace-period)
#   t+40s    the taint node.kubernetes.io/unreachable:NoExecute is added
#   t+340s   every Pod's default 300s toleration expires → Pods are marked for eviction
#   t+~5m    the Pods are DELETED from the API (but may still be running on the node!)
kubectl get pods -A -o wide | grep learn-worker
```

⚠️ **The 5-minute window is where StatefulSet data corruption happens.** The API says the Pod is gone, but the container may still be running on an unreachable node, still holding the volume. That's why RWO + a partitioned node is dangerous, and why `ReadWriteOncePod` and fencing exist.

```bash
# ⭐ safe recovery for a StatefulSet on a dead node
kubectl get node learn-worker                       # NotReady for > 5 min
# 1. Is the node really dead, or just partitioned?
ssh learn-worker echo alive 2>/dev/null || echo "unreachable"
# 2. Force it out of the cluster (cloud provider will terminate it)
kubectl delete node learn-worker
# 3. Now the STS can reschedule db-0 elsewhere — but ONLY if the volume is detached
kubectl get volumeattachment | grep learn-worker
kubectl delete volumeattachment <name>              # ⚠️ only if the node is truly gone
# 4. Verify
kubectl get pods -n db -o wide
```

---

<a name="27-the-troubleshooting-playbook"></a>
## 27. The troubleshooting playbook

> **The universal sequence. Learn this order and you'll fix 90% of incidents faster than anyone else on the team.**

### 27.0 The five-question triage

```bash
# Q1: Is the CLUSTER reachable and healthy?
kubectl version && kubectl get --raw='/readyz?verbose' | grep -v '\[+\]' && kubectl get nodes
kubectl get apiservices | grep -v True

# Q2: Which PODS are unhealthy, anywhere?
kubectl get pods -A | grep -vE 'Running|Completed'
kubectl get pods -A --field-selector=status.phase=Failed
kubectl get events -A --field-selector type=Warning --sort-by=.lastTimestamp | tail -30

# Q3: What does the OWNER think?
kubectl get deploy,sts,ds,job,cronjob -A | grep -vE '([0-9]+)/\1'      # desired != ready

# Q4: Is it a NODE problem?
kubectl top nodes; kubectl describe node <node> | sed -n '/Conditions/,/Addresses/p'
kubectl get pods -A --field-selector spec.nodeName=<node>

# Q5: Is it a NETWORK problem?
kubectl get svc,endpointslices -n <ns>; kubectl exec -it <pod> -- wget -qO- http://<svc>/health
```

### 27.1 The per-Pod sequence — memorise it

```bash
POD=shop-api-7d4f8c9b6-abcde
NS=shop

# STEP 1 — the STATUS column tells you which branch to take
kubectl get pod $POD -n $NS

# STEP 2 — describe. Read, IN ORDER: Conditions → Events → Last State → Mounts → QoS
kubectl describe pod $POD -n $NS

# STEP 3 — events only (in case describe is long)
kubectl get events -n $NS --field-selector involvedObject.name=$POD --sort-by=.lastTimestamp

# STEP 4 — logs
kubectl logs $POD -n $NS --tail=200
kubectl logs $POD -n $NS --previous --tail=200          # ⭐ if RESTARTS > 0
kubectl logs $POD -n $NS --all-containers --prefix

# STEP 5 — get inside (if it's running)
kubectl exec -it $POD -n $NS -- sh
kubectl debug -it $POD -n $NS --image=nicolaka/netshoot --target=api -- bash

# STEP 6 — the owner's view
kubectl describe deploy ${POD%-*-*} -n $NS | tail -30
kubectl rollout status deploy/shop-api -n $NS
kubectl get rs -n $NS -l app=shop-api --sort-by=.metadata.creationTimestamp
```

### 27.2 The status → action table

| STATUS | Root cause branch | The three commands |
|---|---|---|
| `Pending` | Scheduling or volume binding | `describe pod` → Events; `describe nodes \| grep -A6 Allocated`; `get pvc` |
| `ContainerCreating` | CNI, volume mount, image pull | `describe pod` → Events; `logs -n kube-system <cni-pod>`; `describe pvc` |
| `PodInitializing` / `Init:N/M` | An init container is slow or stuck | `logs <pod> -c <init>`; `describe pod` |
| `Init:CrashLoopBackOff` | An init container keeps failing | `logs <pod> -c <init> --previous` |
| `ImagePullBackOff` / `ErrImagePull` | The image reference or registry auth | `describe pod` → the exact error; check `imagePullSecrets` |
| `CreateContainerConfigError` | A ConfigMap/Secret key is missing | `describe pod`; `get cm,secret -n $NS` |
| `CrashLoopBackOff` | The app exits | `logs --previous`; `describe pod` → Last State → Exit Code |
| `OOMKilled` | Memory limit too low, or a leak | `describe pod` → Exit Code 137; `top pod --containers`; the node's `dmesg` |
| `Error` | Non-zero exit | `logs --previous` |
| `Running` but `0/1` Ready | Readiness probe failing | `describe pod` → Events (`Unhealthy`); test the probe manually |
| `Terminating` forever | Finalizers, a hung `preStop`, or an unresponsive container | `get pod -o json \| jq .metadata.deletionTimestamp`; `logs -f` |
| `Evicted` | Node pressure | `describe pod` → the message; `describe node` → Conditions |
| `FailedScheduling` | No node fits | `describe pod` → the scheduler message (see §17.9) |
| `Unknown` / `NodeLost` | The node disappeared | `get nodes`; `get lease -n kube-node-lease` |
| `Completed` | Normal for a Job | `logs job/<name>` |

### 27.3 Exit codes — the Rosetta Stone

| Code | Name | Meaning | The usual cause |
|---|---|---|---|
| **0** | — | Success | ✅ |
| **1** | `SIGHUP`/generic | Application error | An uncaught exception; read the logs |
| **2** | — | Shell misuse of a builtin | A bad command in a shell script |
| **126** | — | Command found but not executable | Wrong permissions on the entrypoint (`chmod +x`) |
| **127** | — | Command not found | A typo in `command:`/`args:`, or a missing binary in the image |
| **128** | — | Invalid exit argument | `exit` with a non-numeric arg |
| **130** | SIGINT (128+2) | Ctrl-C | Manual interrupt |
| **137** | SIGKILL (128+9) | **OOMKilled**, or the grace period expired | ⭐ The memory limit, or a slow shutdown |
| **139** | SIGSEGV (128+11) | Segfault | A native crash (JNI, cgo, a bad C library) |
| **143** | SIGTERM (128+15) | Graceful termination | **Normal** — this is a healthy shutdown |
| **159** | SIGSYS | A seccomp-profile violation | ⭐ `seccompProfile: RuntimeDefault` blocked a syscall |
| **162** | — | Suspended (SIGTSTP) | Rare |
| **255** | — | Out of range | An `exit 300` in your code |

```bash
# read the exit code
kubectl get pod $POD -n $NS -o jsonpath='{.status.containerStatuses[0].lastState.terminated.exitCode}'; echo
# 137
kubectl get pod $POD -n $NS -o json | jq '.status.containerStatuses[] |
  {name, restartCount, lastState: .lastState.terminated, state: .state}'

# was it OOMKilled or SIGKILL from the grace period?
kubectl get pod $POD -n $NS -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}'; echo
# OOMKilled      → memory limit
# Error          → the app exited 137 itself, or was SIGKILLed after the grace period
```

**Exit 137: the two causes, told apart:**

```bash
# CAUSE A: the memory limit
kubectl describe pod $POD -n $NS | grep -A4 'Last State'
# Last State:  Terminated
#   Reason:    OOMKilled            ← ⭐ explicit
#   Exit Code: 137
kubectl get events -n $NS --field-selector reason=OOMKilling
kubectl top pod $POD -n $NS --containers
kubectl get pod $POD -n $NS -o jsonpath='{.spec.containers[0].resources.limits.memory}'; echo
# 1Gi → raise it, or fix the leak

# CAUSE B: the grace period expired (it ignored SIGTERM)
kubectl get pod $POD -n $NS -o jsonpath='{.spec.terminationGracePeriodSeconds}'; echo
# 30
kubectl describe pod $POD -n $NS | grep -A3 Events
# Normal  Killing  30s  kubelet  Container api failed to stop within 30 seconds — sending SIGKILL
# → the app doesn't handle SIGTERM. Fix the app, or raise the grace period.
```

### 27.4 CrashLoopBackOff — the full procedure

```bash
POD=shop-api-7d4f8c9b6-abcde; NS=shop

# 1. THE LOGS OF THE DEAD CONTAINER — always first
kubectl logs $POD -n $NS --previous --tail=200
# ⭐ if this is empty, the container died before writing anything (see step 4)

# 2. the exit code and reason
kubectl get pod $POD -n $NS -o json | jq '.status.containerStatuses[0].lastState.terminated'
# {"exitCode":1,"reason":"Error","startedAt":"…","finishedAt":"…","message":"…"}

# 3. the events
kubectl get events -n $NS --field-selector involvedObject.name=$POD --sort-by=.lastTimestamp
# Warning  BackOff  2m (x8)  kubelet  Back-off restarting failed container api in pod shop-api-…

# 4. if the logs are EMPTY, the process never started
kubectl describe pod $POD -n $NS | grep -E 'Command:|Args:|Image:|Working Dir:'
#   Command:  ["./start.sh"]
#   Exit Code 127 → start.sh doesn't exist or has no shebang
kubectl get pod $POD -n $NS -o jsonpath='{.spec.containers[0].command}'; echo
kubectl get pod $POD -n $NS -o jsonpath='{.spec.containers[0].args}'; echo

# ⭐ override the command to get a shell into the same image
kubectl debug -it $POD -n $NS --image=busybox:1.37 --copy-to=$POD-debug \
  --container=debug --share-processes -- sh
# or run the image locally
docker run --rm -it --entrypoint sh ghcr.io/3558bhk/shop-api:1.2.0

# 5. the backoff schedule
# 10s → 20s → 40s → 80s → 160s → 300s (capped at 5 min)
# restart the pod to reset it:
kubectl delete pod $POD -n $NS

# 6. is it a config problem?
kubectl exec -it $POD -n $NS -- env | sort          # (if it stays up long enough)
kubectl get cm,secret -n $NS
kubectl describe cm app-config -n $NS
```

**The CrashLoopBackOff causes, in order of frequency:**

| # | Cause | How you spot it |
|---|---|---|
| 1 | The app can't reach a dependency (DB, cache) | `logs --previous` shows a connection error |
| 2 | A missing/renamed env var or config key | `logs --previous` shows `NullPointerException`, `KeyError`, `IllegalStateException` |
| 3 | The entrypoint/command is wrong | Exit 126/127, empty logs |
| 4 | OOM at startup (the heap is bigger than the limit) | Exit 137, `reason: OOMKilled`, JVM `Cannot allocate memory` |
| 5 | A read-only root filesystem and the app writes to `/` | `Read-only file system` in the logs |
| 6 | Wrong permissions (non-root, no write access) | `Permission denied` |
| 7 | A livenessProbe that's too aggressive | `describe pod` → `Killing … failed liveness probe`, then BackOff |
| 8 | A port already in use | `Address already in use` |
| 9 | A bad migration | The migration tool exits non-zero |
| 10 | The image is for the wrong architecture | `exec format error` |

```bash
# ⭐ cause 7 in detail — a liveness probe killing a healthy app
kubectl describe pod $POD -n $NS | grep -A20 Events | grep -E 'Unhealthy|Killing'
# Warning  Unhealthy  3m (x3)  kubelet  Liveness probe failed: Get "http://10.244.2.19:8080/health": context deadline exceeded (Client.Timeout exceeded while awaiting headers)
# Normal   Killing    3m       kubelet  Container api failed liveness probe, will be restarted
kubectl get deploy shop-api -n $NS -o json | jq '.spec.template.spec.containers[0] | {startupProbe, livenessProbe}'
# livenessProbe.timeoutSeconds: 1   ← ⛔ too short for a busy JVM under GC
# FIX: add a startupProbe, raise timeoutSeconds to 5, raise failureThreshold to 5
```

### 27.5 ImagePullBackOff

```bash
kubectl describe pod $POD -n $NS | grep -A5 Events
```

| The event message | Cause | Fix |
|---|---|---|
| `manifest unknown` / `not found` | A typo in the tag, or it was never pushed | `docker manifest inspect <image>`; check your registry |
| `unauthorized: authentication required` | No/bad `imagePullSecrets` | Create the secret; attach it to the SA |
| `pull access denied` | Wrong repo name or no read permission | Check the org/repo spelling |
| `dial tcp: lookup ghcr.io: no such host` | DNS on the node | Check the node's resolver, or a NetworkPolicy blocking egress |
| `i/o timeout` | The registry is unreachable from the node | Firewall, NAT gateway, or an air-gapped cluster |
| `exec format error` | ⭐ The image is for the wrong CPU architecture | Build multi-arch (`--platform linux/amd64,linux/arm64`) |
| `no matching manifest for linux/arm64/v8` | Same | Same |
| `x509: certificate signed by unknown authority` | A private registry with a self-signed cert | Add the CA to the node's `/etc/containerd/certs.d/` |
| `toomanyrequests: You have reached your pull rate limit` | Docker Hub anonymous limits (100 pulls/6h/IP) | Authenticate, use a mirror, or a pull-through cache |
| `Back-off pulling image` | Retrying | Fix the underlying error |

```bash
# the exact image reference being used
kubectl get pod $POD -n $NS -o jsonpath='{.spec.containers[0].image}'; echo
# ghcr.io/3558bhk/shop-api:1.2.0
kubectl get pod $POD -n $NS -o jsonpath='{.spec.containers[0].imagePullPolicy}'; echo
# IfNotPresent

# the pull secret
kubectl get pod $POD -n $NS -o jsonpath='{.spec.imagePullSecrets}'; echo
# [{"name":"ghcr-creds"}]
kubectl get secret ghcr-creds -n $NS -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d | jq '.auths | keys'
kubectl get sa $(kubectl get pod $POD -n $NS -o jsonpath='{.spec.serviceAccountName}') -n $NS \
  -o jsonpath='{.imagePullSecrets}'; echo

# verify the image exists and what architectures it has
docker manifest inspect ghcr.io/3558bhk/shop-api:1.2.0 | jq '.manifests[]?.platform'
crane manifest ghcr.io/3558bhk/shop-api:1.2.0 | jq '.manifests[]?.platform'
skopeo inspect --raw docker://ghcr.io/3558bhk/shop-api:1.2.0 | jq .

# on the node
kubectl debug node/$(kubectl get pod $POD -n $NS -o jsonpath='{.spec.nodeName}') -it --image=alpine:3.22 -- chroot /host sh
crictl pull ghcr.io/3558bhk/shop-api:1.2.0         # ⭐ reproduces the exact error
crictl images | grep shop-api
```

**`imagePullPolicy` semantics:**

| Value | Behaviour |
|---|---|
| `Never` | Only use a locally-present image; fail otherwise |
| `IfNotPresent` (default when a tag is given, or when `:latest` is absent) | Pull only if the image isn't on the node |
| `Always` (default for `:latest`) | Always check the registry for the digest — and **always needs pull credentials** |

> 🔑 **`:latest` + `IfNotPresent` = you never know which build is running.** Pin a digest (`@sha256:…`) or use immutable tags. See [Project 12](./15-PROJECT-12-react-go-fullstack.md).

### 27.6 Networking — the layered test

```bash
NS=shop; APP=shop-api

# LAYER 1 — is the app listening, from inside its own container?
kubectl exec deploy/$APP -n $NS -- wget -qO- http://localhost:8080/health
kubectl exec deploy/$APP -n $NS -- sh -c 'netstat -ltn 2>/dev/null || ss -ltn'
# ⛔ nothing on 8080 → the app isn't listening (or listens on 127.0.0.1 only!)

# LAYER 2 — pod-to-pod by IP
IP=$(kubectl get pod -n $NS -l app=$APP -o jsonpath='{.items[0].status.podIP}')
kubectl run t1 --image=nicolaka/netshoot -n $NS --rm -it --restart=Never -- curl -sv --max-time 5 http://$IP:8080/health

# LAYER 3 — DNS resolution
kubectl run t2 --image=nicolaka/netshoot -n $NS --rm -it --restart=Never -- \
  dig +short $APP.$NS.svc.cluster.local
# ⛔ empty → CoreDNS or the Service is broken

# LAYER 4 — the Service, by name
kubectl run t3 --image=nicolaka/netshoot -n $NS --rm -it --restart=Never -- \
  curl -sv --max-time 5 http://$APP/health
kubectl get endpointslices -n $NS -l kubernetes.io/service-name=$APP
# ⛔ no endpoints → selector mismatch or Pods not Ready (see §14.3)

# LAYER 5 — cross-namespace
kubectl run t4 --image=nicolaka/netshoot -n other --rm -it --restart=Never -- \
  curl -sv --max-time 5 http://$APP.$NS.svc.cluster.local/health
# ⛔ timeout → a NetworkPolicy (see §14.7)

# LAYER 6 — egress to the internet
kubectl run t5 --image=nicolaka/netshoot -n $NS --rm -it --restart=Never -- \
  curl -sv --max-time 5 https://api.github.com/
# ⛔ timeout → an egress NetworkPolicy, no NAT gateway, or DNS

# LAYER 7 — ingress from outside
curl -sk -H "Host: api.shop.example.com" https://localhost/health
kubectl get ingress -n $NS
kubectl describe ingress -n $NS
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=50
kubectl exec -n ingress-nginx deploy/ingress-nginx-controller -- nginx -T 2>/dev/null | grep -B2 -A8 'server_name api.shop.example.com'

# LAYER 8 — node-level
kubectl debug node/learn-worker -it --image=nicolaka/netshoot -- bash
#   iptables -t nat -L KUBE-SERVICES -n | grep <clusterIP>
#   ip route
#   ss -ltnp | grep 30080
#   tcpdump -i any -n port 8080 -c 20
```

**Interpreting the failure mode:**

| Result | Meaning |
|---|---|
| `Connection refused` | Something **answered** with a RST — the IP is reachable but nothing is listening on that port |
| `Connection timed out` | Packets are being **dropped** — a NetworkPolicy, a firewall, or a wrong route |
| `No route to host` | An ARP/routing failure |
| `could not resolve host` | DNS |
| `502 Bad Gateway` | The Ingress/proxy reached the Service but the **backend refused or errored** |
| `503 Service Unavailable` | The proxy has **no healthy backends** |
| `504 Gateway Timeout` | The backend accepted the connection but didn't respond in time |
| `404` from the Ingress with `nginx` in the body | The `Host` header didn't match any rule |

### 27.7 A rolling update that won't finish

```bash
kubectl rollout status deploy/shop-api -n shop --timeout=60s
# Waiting for deployment "shop-api" rollout to finish: 1 out of 3 new replicas have been updated...
# error: timed out waiting for the condition

kubectl describe deploy shop-api -n shop | grep -A10 Conditions
#   Type           Status  Reason
#   Available      True    MinimumReplicasAvailable
#   Progressing    False   ProgressDeadlineExceeded      ← ⭐

# what's stuck?
kubectl get pods -n shop -l app=shop-api
# shop-api-9a2b3c4d5-xyz   0/1   ImagePullBackOff      0   5m     ← ⭐ the NEW pod
# shop-api-7d4f8c9b6-abc   1/1   Running               0   3d
# shop-api-7d4f8c9b6-def   1/1   Running               0   3d
# shop-api-7d4f8c9b6-ghi   1/1   Running               0   3d

kubectl get rs -n shop -l app=shop-api
# shop-api-9a2b3c4d5   1   0   0   5m      ← DESIRED 1, READY 0
# shop-api-7d4f8c9b6   3   3   3   3d

# ⭐ the old pods are STILL SERVING. This is Kubernetes working correctly.
#    maxUnavailable: 25% of 3 = 0.75 → 0, so it never drops below 3 ready pods.

# fix the new pod (see §27.5), or roll back
kubectl rollout undo deploy/shop-api -n shop
kubectl rollout status deploy/shop-api -n shop
kubectl set image deploy/shop-api api=ghcr.io/3558bhk/shop-api:1.1.0 -n shop   # the last known good
```

**The five reasons a rollout stalls:**

| Reason | Where you see it |
|---|---|
| The new Pod won't start | `kubectl get pods -l app=X` — a non-Running STATUS |
| The new Pod starts but never becomes Ready | `describe pod` → `Unhealthy` readiness probe events |
| Not enough capacity for `maxSurge` | `describe pod` → `FailedScheduling: Insufficient cpu` |
| A PDB blocks the old Pods from terminating | `kubectl get pdb`; the drain/evict logs |
| A quota blocks the new Pod | `describe rs` → `FailedCreate: exceeded quota` |

```bash
kubectl describe rs -n shop shop-api-9a2b3c4d5 | grep -A10 Events
# Warning  FailedCreate  2m (x3)  replicaset-controller
#   Error creating: pods "shop-api-9a2b3c4d5-" is forbidden:
#   failed quota: shop-quota: must specify limits.cpu, limits.memory
```

### 27.8 A node that won't come back

```bash
kubectl get nodes
# learn-worker2   NotReady   <none>   12d   v1.37.0

# 1. how long has it been down?
kubectl get lease -n kube-node-lease learn-worker2 -o jsonpath='{.spec.renewTime}'; echo
kubectl describe node learn-worker2 | grep -A8 Conditions
#   Ready   Unknown   2026-09-09T14:12:11Z   NodeStatusUnknown   Kubelet stopped posting node status

# 2. what's the automatic taint?
kubectl get node learn-worker2 -o json | jq '.spec.taints'
# [{"key":"node.kubernetes.io/unreachable","effect":"NoExecute","timeAdded":"2026-09-09T14:12:51Z"}]

# 3. what pods are still nominally on it?
kubectl get pods -A -o wide --field-selector spec.nodeName=learn-worker2
kubectl get pods -A -o wide | grep learn-worker2

# 4. reach the node
ssh learn-worker2 'systemctl status kubelet containerd; journalctl -u kubelet -n 50 --no-pager'
kubectl debug node/learn-worker2 -it --image=alpine:3.22 -- chroot /host sh 2>/dev/null

# 5. common node causes
#    - the kubelet crashed / OOMed:      journalctl -u kubelet | grep -i 'killed\|oom'
#    - the disk is full:                 df -h /  → DiskPressure
#    - containerd died:                  systemctl status containerd
#    - the CNI crashed:                  kubectl get pods -n kube-system -o wide | grep <node>
#    - clock skew:                       timedatectl status  (cert auth fails if >5min off)
#    - the node ran out of PIDs:         cat /proc/sys/kernel/pid_max; ps -e | wc -l
#    - network partition to the API:     curl -sk https://<apiserver>:6443/healthz

# 6. after 5 min the pods are marked for eviction — verify they rescheduled
kubectl get pods -A -o wide | grep -c learn-worker2

# 7. if the node is truly gone, remove it
kubectl delete node learn-worker2
kubectl get volumeattachment | grep learn-worker2      # ⭐ detach the volumes
```

### 27.9 The complete one-liner diagnostic scripts

```bash
# ⭐ 1. "What's broken, right now, everywhere?"
kubectl get pods -A | grep -vE 'Running|Completed' ; \
kubectl get nodes | grep -v ' Ready' ; \
kubectl get events -A --field-selector type=Warning --sort-by=.lastTimestamp | tail -15

# ⭐ 2. restart-count leaderboard
kubectl get pods -A -o json | jq -r '.items[] | .metadata.namespace as $ns |
  (.status.containerStatuses // [])[] | select(.restartCount > 0) |
  [(.restartCount|tostring), "\($ns)/\(.name // "?")", .lastState.terminated.reason // "-"] | @tsv' 2>/dev/null \
  | sort -rn | head -20

# ⭐ 3. every OOMKilled container in the cluster
kubectl get pods -A -o json | jq -r '.items[] | .metadata.namespace as $ns | .metadata.name as $p |
  (.status.containerStatuses // [])[] | select(.lastState.terminated.reason=="OOMKilled") |
  "\($ns)/\($p)  \(.name)  limit=?  restarts=\(.restartCount)"'

# ⭐ 4. pods with no resource requests
kubectl get pods -A -o json | jq -r '.items[] | .metadata.namespace as $ns | .metadata.name as $p |
  (.spec.containers[] | select((.resources.requests // {}) == {}) | "\($ns)/\($p)  \(.name)  ⚠️ no requests")'

# ⭐ 5. pods with no limits (BestEffort risk)
kubectl get pods -A -o json | jq -r '.items[] | .metadata.namespace as $ns | .metadata.name as $p |
  (.spec.containers[] | select((.resources.limits // {}) == {}) | "\($ns)/\($p)  \(.name)  ⚠️ no limits")'

# ⭐ 6. images not pinned by digest
kubectl get pods -A -o json | jq -r '.items[] | .metadata.namespace as $ns | .metadata.name as $p |
  (.spec.containers[].image | select(test("@sha256:")|not) | "\($ns)/\($p)  \(.)")' | sort -u

# ⭐ 7. privileged containers
kubectl get pods -A -o json | jq -r '.items[] | .metadata.namespace as $ns | .metadata.name as $p |
  (.spec.containers[] | select(.securityContext.privileged==true) | "\($ns)/\($p)  \(.name)  ⛔ privileged")'

# ⭐ 8. Services with no endpoints
for ns in $(kubectl get ns -o name | sed 's|namespace/||'); do
  for svc in $(kubectl get svc -n $ns -o name 2>/dev/null | sed 's|service/||'); do
    ct=$(kubectl get svc $svc -n $ns -o jsonpath='{.spec.type}')
    [ "$ct" = "ExternalName" ] && continue
    n=$(kubectl get endpointslices -n $ns -l kubernetes.io/service-name=$svc -o json | jq '[.items[].endpoints[]? | select(.conditions.ready==true)] | length')
    [ "$n" -eq 0 ] && echo "⛔ $ns/$svc has 0 ready endpoints"
  done
done

# ⭐ 9. node capacity vs requests
kubectl describe nodes | awk '/^Name:/{n=$2} /cpu +[0-9]+m? \(/{print n, "cpu", $0} /memory +[0-9]+/{print n, "mem", $0}'

# ⭐ 10. pending PVCs
kubectl get pvc -A --field-selector=status.phase=Pending

# ⭐ 11. everything older than N days that's still Pending/Failed
kubectl get pods -A --field-selector=status.phase=Failed
kubectl get jobs -A -o json | jq -r '.items[] | select(.status.failed>0 and .status.succeeded==null) | "\(.metadata.namespace)/\(.metadata.name)"'

# ⭐ 12. the full cluster snapshot into one file
{ echo "=== $(date) $(kubectl config current-context) ==="
  kubectl version
  kubectl cluster-info
  kubectl get nodes -o wide
  kubectl top nodes
  kubectl get pods -A -o wide | grep -vE 'Running|Completed'
  kubectl get events -A --field-selector type=Warning --sort-by=.lastTimestamp | tail -50
  kubectl get deploy,sts,ds,job,cj,hpa,pdb -A
  kubectl get pv,pvc -A
  kubectl get apiservices | grep -v True
} > cluster-snapshot-$(date +%F-%H%M).txt
```

### 27.10 Tools that make this faster

```bash
# ⭐ k9s — the terminal UI you should live in
k9s
#   :pods  :deploy  :svc  :nodes  :events  :ns  :helm  :crds  :all
#   0 = all namespaces     / = filter     l = logs     s = shell     d = describe
#   e = events     k = kill     c = copy name     y = YAML     ctrl-k = delete
#   :pulse = a dashboard    :rbac = permissions    :xray deploy shop = ownership tree
#   :popeye = a cluster lint   :plugin = krew plugins

# stern — multi-pod logs
stern -n shop . --since=10m
stern -l app=shop-api --exclude-container istio-proxy -i error
stern -A 'shop-(api|ui)' --tail=100

# kubectx / kubens
kubectx; kubens

# ⭐ a "cluster health" dashboard in the browser
kubectl krew install view-utilization
kubectl view-utilization                     # an HTML view of requests vs limits per node
```

---

<a name="28-events-and-the-api-server"></a>
## 28. Events & the API server

### 28.1 The two Event APIs

```bash
kubectl get events -A -o jsonpath='{.items[0].apiVersion}'; echo
# v1                     ← the core Event
kubectl api-resources | grep -i event
# events           ev      v1              true    Event
# events           ev      events.k8s.io/v1 true   Event       ← the newer, richer one
```

| | `v1.Event` (core) | `events.k8s.io/v1.Event` |
|---|---|---|
| Fields | `reason`, `message`, `count`, `firstTimestamp`, `lastTimestamp` | + `action`, `related`, `series`, `reportingController`, `reportingInstance`, `deprecatedCount` |
| Used by | Older components | The scheduler, most modern controllers |

`kubectl get events` merges both transparently.

### 28.2 Reading events at scale

```bash
kubectl get events -A --sort-by=.lastTimestamp | tail -50
kubectl get events -A --field-selector type=Warning --sort-by=.lastTimestamp | tail -50

# a histogram of reasons — what's your cluster actually complaining about?
kubectl get events -A -o json | jq -r '.items[].reason' | sort | uniq -c | sort -rn | head -20
#   142 Unhealthy
#    38 BackOff
#    21 FailedScheduling
#     9 FailedMount
#     4 OOMKilling

# per namespace
kubectl get events -A -o json | jq -r '.items[] | select(.type=="Warning") |
  "\(.metadata.namespace)\t\(.reason)"' | sort | uniq -c | sort -rn | head -20

# ⭐ timeline of one incident
kubectl get events -A --sort-by=.lastTimestamp -o custom-columns=\
'TIME:.lastTimestamp,COUNT:.count,TYPE:.type,NS:.metadata.namespace,REASON:.reason,OBJ:.involvedObject.name,MSG:.message' \
| grep -E '14:1[0-9]|14:2[0-9]'

# stream them live
kubectl get events -A -w
kubectl get events -A -w --field-selector type=Warning
```

⚠️ **Event TTL is 1 hour by default.** Set `--event-ttl` on the API server to change it (don't set it too high — events are a major source of etcd churn).

```bash
kubectl get --raw /api/v1/namespaces/kube-system/pods/kube-apiserver-learn-control-plane/log 2>/dev/null \
  | grep -o 'event-ttl=[^ ]*'
```

### 28.3 The API server itself

```bash
kubectl get pods -n kube-system | grep -E 'apiserver|controller-manager|scheduler|etcd'
kubectl logs -n kube-system kube-apiserver-learn-control-plane --tail=100
kubectl logs -n kube-system kube-controller-manager-learn-control-plane --tail=100
kubectl logs -n kube-system kube-scheduler-learn-control-plane --tail=100

kubectl get --raw /metrics > apiserver-metrics.txt
wc -l apiserver-metrics.txt
```

**The API server metrics that matter:**

| Metric | Healthy | What a bad value means |
|---|---|---|
| `apiserver_request_duration_seconds_bucket{verb="LIST"}` | p99 < 1s | Slow etcd or huge list requests |
| `apiserver_request_total{code=~"5.."}` | ~0 | The API server is failing |
| `apiserver_request_total{code="429"}` | 0 | **APF throttling** — a client is hammering it |
| `apiserver_current_inflight_requests` | < 400 | Approaching the limit |
| `apiserver_longrunning_requests` | Stable | Watch leaks |
| `etcd_request_duration_seconds` | p99 < 25ms | Disk latency |
| `etcd_db_total_size_in_bytes` | < 8 GB | Approaching the quota |
| `workqueue_depth{name="…"}` | Near 0 | A controller is falling behind |
| `apiserver_storage_objects` | Stable | Which resource type is bloating etcd |
| `apiserver_watch_events_sizes` | Small | A client is re-listing instead of watching |

```bash
# ⭐ who is hammering the API server?
kubectl get --raw /metrics | grep '^apiserver_request_total' \
  | sed 's/.*client="\([^"]*\)".*resource="\([^"]*\)".*verb="\([^"]*\)".*/\1 \3 \2/' \
  | sort | uniq -c | sort -rn | head -20
# 184320 system:serviceaccount:monitoring:prometheus LIST pods
#  42110 kubectl GET pods
#   9812 system:node:learn-worker LIST configmaps

# throttled requests (APF)
kubectl get --raw /metrics | grep 'apiserver_flowcontrol_rejected_requests_total'
kubectl get flowschemas
kubectl get prioritylevelconfigurations
kubectl describe prioritylevelconfiguration workload-high

# etcd size
kubectl get --raw /metrics | grep -E 'etcd_db_total_size_in_bytes|apiserver_storage_objects' | head -20

# the watch cache
kubectl get --raw /metrics | grep apiserver_watch_cache_capacity_increase_total
```

### 28.4 API Priority and Fairness (APF)

The mechanism that stops one bad client from taking down the API server.

```bash
kubectl get flowschemas
# NAME                        PRIORITYLEVEL     MATCHING PRECEDENCE
# exempt                      exempt            1
# system-leader-election      workload-leader   100
# workload-leader-election    workload-leader   200
# global-default              global-default    9900
# catch-all                   none              10000

kubectl get prioritylevelconfigurations
# NAME                TYPE    ASSURED SHARES   QUEUED   HAND SIZE
# exempt              Exempt  0                0        0
# system-nodes        Limited 30               6        …
# workload-high       Limited 40               6        …
# workload-low        Limited 100              6        …
# global-default      Limited 20               6        …
# catch-all           Limited 5                6        …

kubectl describe flowschema workload-leader-election
kubectl get --raw /metrics | grep apiserver_flowcontrol_current_inqueue_requests
kubectl get --raw /metrics | grep apiserver_flowcontrol_rejected_requests_total
# apiserver_flowcontrol_rejected_requests_total{flow_schema="catch-all",priority_level="catch-all",reason="time-out"} 412
```

If you see `429 Too Many Requests`, either raise the client's rate limit (`--kube-api-qps`, `--kube-api-burst`) or give it a better FlowSchema/PriorityLevel.

---

<a name="29-scripting-and-automation"></a>
## 29. Scripting & automation

### 29.1 `kubectl wait` — the synchronisation primitive

```bash
# for a CONDITION
kubectl wait --for=condition=Ready pod -l app=shop-api -n shop --timeout=120s
kubectl wait --for=condition=Available deploy/shop-api -n shop --timeout=300s
kubectl wait --for=condition=complete job/db-migrate --timeout=600s
kubectl wait --for=condition=failed job/db-migrate --timeout=600s
kubectl wait --for=condition=Ready node/learn-worker --timeout=10m
kubectl wait --for=condition=Established crd/clusters.postgresql.cnpg.io --timeout=60s
kubectl wait --for=condition=Ready certificate/shop-tls -n shop --timeout=120s
kubectl wait --for=condition=Synced application/shop -n argocd --timeout=300s
kubectl wait --for=condition=Healthy cluster/db -n db --timeout=300s

# ⭐ for DELETION
kubectl wait --for=delete pod -l app=shop-api -n shop --timeout=120s
kubectl wait --for=delete ns/shop --timeout=300s
kubectl delete pod -l app=shop-api -n shop && kubectl wait --for=condition=Ready pod -l app=shop-api -n shop --timeout=180s

# ⭐ for a JSONPATH EXPRESSION (the most flexible)
kubectl wait --for=jsonpath='{.status.phase}'=Running pod/nginx --timeout=60s
kubectl wait --for=jsonpath='{.status.readyReplicas}'=3 deploy/shop-api --timeout=180s
kubectl wait --for=jsonpath='{.spec.replicas}'=5 deploy/shop-api
kubectl wait --for=jsonpath='{.status.conditions[?(@.type=="Ready")].status}'=True pod -l app=shop-api

# several objects
kubectl wait --for=condition=Ready pod --all -n shop --timeout=300s
kubectl wait --for=condition=Ready pod -l 'app in (shop-api,shop-ui)' -n shop

# ⚠️ exit codes
kubectl wait --for=condition=Ready pod/x --timeout=10s && echo OK || echo FAILED
# error: timed out waiting for the condition on pods/x       → exit 1
```

⚠️ **`wait` has a race:** if the object doesn't exist yet, it fails immediately rather than waiting for it to appear.

```bash
kubectl wait --for=condition=Ready pod/x           # ⛔ pod "x" not found → exit 1
# ✅ the retry wrapper
until kubectl get pod/x >/dev/null 2>&1; do sleep 1; done
kubectl wait --for=condition=Ready pod/x --timeout=120s
```

### 29.2 The `kubectl get -o name | xargs` patterns

```bash
# delete all pods with a label
kubectl get pods -n shop -l app=shop-api -o name | xargs kubectl delete -n shop

# restart all deployments
kubectl get deploy -n shop -o name | xargs -n1 kubectl rollout restart -n shop

# describe everything
kubectl get all -n shop -o name | xargs -n1 kubectl describe -n shop

# parallel, with a limit
kubectl get pods -A -o name | xargs -n1 -P4 -I{} kubectl get {} -o jsonpath='{.metadata.name}{"\n"}'

# ⚠️ argument list too long
kubectl get pods -A -o name | wc -l          # 4000
kubectl get pods -A -o name | xargs kubectl delete    # ⛔ Argument list too long
kubectl get pods -A -o name | xargs -n50 kubectl delete   # ✅ batched
```

### 29.3 Idempotent bash helpers

```bash
#!/usr/bin/env bash
# k8s-helpers.sh — source this
set -euo pipefail

# ── wait for a namespace to be fully gone ─────────────────────────────
wait_ns_gone() {
  local ns=$1 timeout=${2:-300} t=0
  while kubectl get ns "$ns" >/dev/null 2>&1; do
    sleep 2; t=$((t+2))
    [ $t -ge "$timeout" ] && { echo "⛔ namespace $ns still terminating after ${timeout}s"; return 1; }
  done
  echo "✅ namespace $ns deleted"
}

# ── wait for every Deployment in a namespace to be Available ──────────
wait_rollouts() {
  local ns=$1 timeout=${2:-300}
  for d in $(kubectl get deploy -n "$ns" -o name); do
    kubectl rollout status "$d" -n "$ns" --timeout="${timeout}s" || return 1
  done
  echo "✅ all rollouts in $ns complete"
}

# ── create a namespace only if it doesn't exist ───────────────────────
ensure_ns() {
  kubectl get ns "$1" >/dev/null 2>&1 || kubectl create namespace "$1"
}

# ── apply, then wait, then verify ─────────────────────────────────────
deploy_and_wait() {
  local file=$1 ns=$2
  kubectl apply -f "$file" -n "$ns"
  wait_rollouts "$ns" 300
  kubectl get pods -n "$ns" | grep -vE 'Running|Completed' && { echo "⛔ unhealthy pods"; return 1; }
  echo "✅ $file deployed to $ns"
}

# ── run a smoke test as an in-cluster Job ─────────────────────────────
smoke_test() {
  local url=$1 ns=${2:-shop} job=smoke-$(date +%s)
  kubectl create job "$job" -n "$ns" --image=curlimages/curl:8.10.1 -- \
    curl -sf --max-time 10 "$url" >/dev/null
  if kubectl wait --for=condition=complete "job/$job" -n "$ns" --timeout=60s >/dev/null 2>&1; then
    echo "✅ $url reachable"
  else
    echo "⛔ $url FAILED"; kubectl logs "job/$job" -n "$ns" || true; return 1
  fi
  kubectl delete job "$job" -n "$ns" --wait=false >/dev/null
}

# ── the full "is the cluster OK?" gate ────────────────────────────────
cluster_health_gate() {
  local fail=0
  kubectl get --raw='/readyz' >/dev/null 2>&1 || { echo "⛔ API server not ready"; fail=1; }
  local notready
  notready=$(kubectl get nodes --no-headers | grep -vc ' Ready' || true)
  [ "$notready" -gt 0 ] && { echo "⛔ $notready node(s) NotReady"; fail=1; }
  local badpods
  badpods=$(kubectl get pods -A --no-headers | grep -vcE 'Running|Completed' || true)
  [ "$badpods" -gt 0 ] && { echo "⚠️ $badpods pod(s) not Running"; }
  local brokenapi
  brokenapi=$(kubectl get apiservices --no-headers | grep -vc ' True' || true)
  [ "$brokenapi" -gt 0 ] && { echo "⛔ $brokenapi APIService(s) unavailable"; fail=1; }
  [ $fail -eq 0 ] && echo "✅ cluster healthy" || return 1
}
```

### 29.4 jsonpath + jq recipes

```bash
# every container image in the cluster, deduplicated
kubectl get pods -A -o json | jq -r '.items[].spec.containers[].image' | sort -u

# every image with its pod count
kubectl get pods -A -o json | jq -r '.items[].spec.containers[].image' | sort | uniq -c | sort -rn | head -20

# pods sorted by memory usage
kubectl top pods -A --no-headers | sort -k5 -h -r | head -20

# the newest 10 pods
kubectl get pods -A --sort-by=.metadata.creationTimestamp -o custom-columns=\
'NS:.metadata.namespace,NAME:.metadata.name,CREATED:.metadata.creationTimestamp' | tail -10

# who owns what
kubectl get pods -A -o json | jq -r '.items[] |
  "\(.metadata.namespace)/\(.metadata.name)  ← \(.metadata.ownerReferences[0].kind // "none")/\(.metadata.ownerReferences[0].name // "-")"'

# nodes and their kubelet versions
kubectl get nodes -o json | jq -r '.items[] | "\(.metadata.name)\t\(.status.nodeInfo.kubeletVersion)\t\(.status.nodeInfo.containerRuntimeVersion)"' | column -t

# all Secrets and their sizes
kubectl get secrets -A -o json | jq -r '.items[] |
  [(.data // {} | tostring | length | tostring), "\(.metadata.namespace)/\(.metadata.name)", .type] | @tsv' | sort -rn | head

# ConfigMaps over 500 KB
kubectl get cm -A -o json | jq -r '.items[] |
  select((.data // {} | tostring | length) > 500000) |
  "\(.metadata.namespace)/\(.metadata.name)  \((.data|tostring|length)/1024) KB"'

# the readiness of every Deployment
kubectl get deploy -A -o json | jq -r '.items[] |
  [(.status.readyReplicas // 0 | tostring) + "/" + (.spec.replicas // 0 | tostring),
   "\(.metadata.namespace)/\(.metadata.name)"] | @tsv' | column -t | grep -vE '^([0-9]+)/\1'

# HPA status
kubectl get hpa -A -o json | jq -r '.items[] |
  "\(.metadata.namespace)/\(.metadata.name)  \(.status.currentMetrics // [] | map(.resource.current.averageUtilization // "?") | join(","))%  replicas=\(.status.currentReplicas)/\(.spec.maxReplicas)"'

# PDBs that would block a drain
kubectl get pdb -A -o json | jq -r '.items[] |
  select(.status.disruptionsAllowed == 0) |
  "⛔ \(.metadata.namespace)/\(.metadata.name)  allowedDisruptions=0"'

# PVCs not bound
kubectl get pvc -A -o json | jq -r '.items[] | select(.status.phase!="Bound") |
  "\(.metadata.namespace)/\(.metadata.name)  \(.status.phase)"'

# ⭐ the "what would a drain of node X do?" report
NODE=learn-worker
kubectl get pods -A --field-selector spec.nodeName=$NODE -o json | jq -r '.items[] |
  "\(.metadata.namespace)/\(.metadata.name)  owner=\(.metadata.ownerReferences[0].kind // "BARE⛔")"'

# ⭐ the "which pods are on which node" matrix
kubectl get pods -A -o json | jq -r '.items[] | "\(.spec.nodeName // "unscheduled")\t\(.metadata.namespace)/\(.metadata.name)"' \
  | sort | awk -F'\t' '{a[$1]=a[$1] "\n  " $2; c[$1]++} END {for (n in a) printf "%s (%d pods)%s\n\n", n, c[n], a[n]}'
```

### 29.5 kubectl in CI

```yaml
# .github/workflows/deploy.yaml
name: deploy
on:
  push: {branches: [main]}
permissions: {contents: read, id-token: write}      # ⭐ OIDC, no long-lived secrets
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      # ⭐ OIDC federation → a short-lived cluster credential
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::123456789012:role/github-deployer
          aws-region: ap-south-1
      - run: aws eks update-kubeconfig --name prod --region ap-south-1

      # 1. validate WITHOUT touching the cluster
      - run: kubectl apply -f ./k8s/ -R --dry-run=server --validate=strict

      # 2. show the diff in the PR
      - run: kubectl diff -f ./k8s/ -R || true

      # 3. apply
      - run: kubectl apply -f ./k8s/ -R --server-side --force-conflicts --field-manager=github-actions

      # 4. ⭐ wait for the rollout — fail the build if it doesn't settle
      - run: kubectl rollout status deploy/shop-api -n shop-prod --timeout=300s

      # 5. smoke test
      - run: |
          JOB=smoke-${{ github.run_id }}
          kubectl create job $JOB -n shop-prod --image=curlimages/curl:8.10.1 -- \
            curl -sf https://api.shop.example.com/health
          kubectl wait --for=condition=complete job/$JOB -n shop-prod --timeout=60s

      # 6. ⭐ automatic rollback on failure
      - if: failure()
        run: |
          kubectl rollout undo deploy/shop-api -n shop-prod
          kubectl rollout status deploy/shop-api -n shop-prod --timeout=300s
```

**The CI rules:**

| Rule | Why |
|---|---|
| Always `--dry-run=server` first | Catches webhook/quota rejections without risk |
| Always `rollout status --timeout=N` | Otherwise a failed deploy silently passes |
| Pin the kubectl version to the cluster ±1 | Skew failures are silent and maddening |
| Use `--server-side --force-conflicts --field-manager=X` | Clean ownership, no CSA annotation bloat |
| Never `kubectl edit` or `patch` in CI | Non-reproducible |
| Never store a long-lived kubeconfig secret | Use OIDC federation |
| Have an automatic rollback step | The build must leave the cluster in a good state |

### 29.6 Exit codes

```bash
kubectl get pods; echo $?          # 0
kubectl get pods nonexistent; echo $?
# Error from server (NotFound): pods "nonexistent" not found
# 1
kubectl get nonexistentresource; echo $?
# error: the server doesn't have a resource type "nonexistentresource"
# 1
kubectl delete --help >/dev/null; echo $?     # 0

kubectl auth can-i delete pods; echo $?
# no
# 1                                   ← ⭐ non-zero means "no". Perfect for scripting.
kubectl auth can-i get pods; echo $?
# yes
# 0

kubectl diff -f x.yaml; echo $?
# 0 = no differences, 1 = there ARE differences, >1 = an error
kubectl rollout status deploy/x --timeout=5s; echo $?
# 0 = complete, 1 = timed out or failed

# ⭐ the ignore-not-found pattern
kubectl get pod x --ignore-not-found; echo $?     # 0, prints nothing
kubectl delete pod x --ignore-not-found; echo $?  # 0

# ⭐ using can-i as a guard
if kubectl auth can-i create deployments -n shop-prod >/dev/null; then
  kubectl apply -f ./k8s/ -n shop-prod
else
  echo "⛔ no permission to deploy to prod"; exit 1
fi
```

---

<a name="30-shell-completion-aliases-and-productivity"></a>
## 30. Shell completion, aliases & productivity

### 30.1 Completion

```bash
# bash
echo 'source <(kubectl completion bash)' >> ~/.bashrc
echo 'alias k=kubectl' >> ~/.bashrc
echo 'complete -o default -F __start_kubectl k' >> ~/.bashrc
source ~/.bashrc

# zsh
echo 'source <(kubectl completion zsh)' >> ~/.zshrc
echo 'compdef __start_kubectl k' >> ~/.zshrc
# or:
autoload -Uz compinit && compinit
kubectl completion zsh > "${fpath[1]}/_kubectl"

# fish
kubectl completion fish | source
kubectl completion fish > ~/.config/fish/completions/kubectl.fish

# ⭐ resource-name completion after typing "get pod <TAB>"
#    and namespace completion with "get pods -n <TAB>"
```

### 30.2 The alias set worth having

```bash
# ~/.bashrc — the kubectl productivity kit
alias k='kubectl'
complete -o default -F __start_kubectl k

# read
alias kg='kubectl get'
alias kgp='kubectl get pods'
alias kgpa='kubectl get pods -A'
alias kgpw='kubectl get pods -o wide'
alias kgs='kubectl get svc'
alias kgd='kubectl get deploy'
alias kgn='kubectl get nodes'
alias kgns='kubectl get namespaces'
alias kd='kubectl describe'
alias kdp='kubectl describe pod'
alias kdd='kubectl describe deploy'
alias kdn='kubectl describe node'
alias kl='kubectl logs'
alias klf='kubectl logs -f'
alias klp='kubectl logs --previous'
alias ke='kubectl exec -it'
alias kep='kubectl explain pod'
alias kev='kubectl get events -A --field-selector type=Warning --sort-by=.lastTimestamp'
alias kt='kubectl top'
alias ktx='kubectl tree'

# write
alias ka='kubectl apply -f'
alias kaf='kubectl apply -f'
alias kda_() { kubectl delete -f "$@"; }
alias kdr='kubectl rollout restart deploy'
alias kdrn='kubectl rollout restart deploy -n'
alias krs='kubectl rollout status'
alias kru='kubectl rollout undo'
alias krh='kubectl rollout history'
alias ksc='kubectl scale'
alias kpf='kubectl port-forward'

# context
alias kx='kubectx'
alias kn='kubens'
alias kctx='kubectl config current-context'
alias kccc='kubectl config current-context'

# dry-run scaffolding ⭐
kgen-deploy() { kubectl create deploy "$1" --image="$2" --dry-run=client -o yaml; }
kgen-cm()     { kubectl create configmap "$1" --from-literal="$2" --dry-run=client -o yaml; }
kgen-secret() { kubectl create secret generic "$1" --from-literal="$2" --dry-run=client -o yaml; }
kgen-svc()    { kubectl create service clusterip "$1" --tcp="$2" --dry-run=client -o yaml; }
kgen-job()    { kubectl create job "$1" --image="$2" --dry-run=client -o yaml; }
kgen-cron()   { kubectl create cronjob "$1" --image="$2" --schedule="$3" --dry-run=client -o yaml; }
kgen-ns()     { kubectl create namespace "$1" --dry-run=client -o yaml; }
kgen-sa()     { kubectl create serviceaccount "$1" --dry-run=client -o yaml; }

# a scratch pod ⭐
kscratch() { kubectl run scratch-${RANDOM} --image=nicolaka/netshoot --rm -it --restart=Never -- "${@:-bash}"; }
kbusy()    { kubectl run busy-${RANDOM} --image=busybox:1.37 --rm -it --restart=Never -- "${@:-sh}"; }

# health
khealth() {
  echo "── nodes ──";   kubectl get nodes | grep -v ' Ready'  || echo "  all Ready"
  echo "── bad pods ──";kubectl get pods -A | grep -vE 'Running|Completed|NAME' || echo "  none"
  echo "── apisvc ──";  kubectl get apiservices | grep -v True || echo "  all available"
  echo "── warnings ──";kubectl get events -A --field-selector type=Warning --sort-by=.lastTimestamp | tail -5
}

# restart counts
krestarts() {
  kubectl get pods -A -o json | jq -r '.items[] | .metadata.namespace as $ns |
    (.status.containerStatuses // [])[] | select(.restartCount>0) |
    [(.restartCount|tostring), "\($ns)/\(.name)"] | @tsv' | sort -rn | head -20
}

# which node is a pod on?
kwhere() { kubectl get pods -A -o wide | grep -F "$1"; }

# logs of the newest pod of a deployment
klogs-new() {
  local p; p=$(kubectl get pods -l "app=$1" -o name --sort-by=.metadata.creationTimestamp | tail -1)
  kubectl logs "$p" -f "${@:2}"
}
```

### 30.3 kubens/kubectx safety

```bash
# a per-shell namespace override, so you can't affect another terminal
kubectl --namespace=shop-prod get pods

# or export a scoped kubeconfig
kubectl config view --minify --flatten > /tmp/scoped.kubeconfig
kubectl config set-context --current --namespace=shop-prod --kubeconfig=/tmp/scoped.kubeconfig
KUBECONFIG=/tmp/scoped.kubeconfig kubectl get pods
```

---

<a name="31-plugins-and-the-krew-ecosystem"></a>
## 31. Plugins & the krew ecosystem

```bash
kubectl krew search                    # ⭐ browse the index (~100 plugins)
kubectl krew install <name>
kubectl krew list
kubectl krew upgrade
kubectl krew remove <name>
kubectl krew index list
kubectl krew index add danielfm https://github.com/danielfm/krew-plugins.git
ls ~/.krew/bin
```

**How kubectl finds plugins:** any executable named `kubectl-<name>` on your `$PATH` becomes `kubectl <name>`. No krew required:

```bash
cat > /usr/local/bin/kubectl-hello <<'EOF'
#!/usr/bin/env bash
echo "hello from a custom plugin, args: $*"
EOF
chmod +x /usr/local/bin/kubectl-hello
kubectl hello world
# hello from a custom plugin, args: world
kubectl plugin list                     # ⭐ what's installed, and any name collisions
```

### The 30 plugins worth knowing

| Plugin | Command | What it does |
|---|---|---|
| **ctx / ns** | `kubectl ctx`, `kubectl ns` | Switch context/namespace (the kubectx tools, as plugins) |
| **tree** | `kubectl tree deploy x` | ⭐ Ownership tree with readiness |
| **lineage** | `kubectl lineage -n shop` | A text ownership graph |
| **neat** | `kubectl get x -o yaml \| kubectl neat` | ⭐ Strip status/managedFields/uid |
| **stern** | `kubectl stern -l app=x` | Multi-pod log tailing |
| **tail** | `kubectl tail -f deploy/x` | Another log tailer |
| **node-shell** | `kubectl node-shell worker-1` | ⭐ Root shell on a node |
| **debug** (built-in) | `kubectl debug` | Ephemeral containers |
| **who-can** | `kubectl who-can delete pods` | ⭐ Reverse RBAC lookup |
| **access-matrix** | `kubectl access-matrix -n shop` | Subjects × resources |
| **rbac-view** | `kubectl rbac-view` | An HTML RBAC graph |
| **rbac-lookup** | `kubectl rbac-lookup` | Find RBAC by subject |
| **rbac-tool** (krew) | `kubectl rbac-tool lookup jane` | Summarise a subject's access |
| **resource-capacity** | `kubectl resource-capacity` | ⭐ Per-node headroom |
| **view-utilization** | `kubectl view-utilization` | An HTML requests-vs-limits view |
| **df-pv** | `kubectl df-pv` | ⭐ Disk usage per PVC |
| **view-secret** | `kubectl view-secret x` | ⭐ Decode a secret |
| **get-all** | `kubectl get-all -n shop` | Actually all namespaced resources |
| **explore** | `kubectl explore` | An interactive object browser |
| **evict-pod** | `kubectl evict-pod x` | Eviction that respects PDBs |
| **deprecations** | `kubectl deprecations --k8s-version v1.38 ./k8s` | ⭐ Find removed APIs in your manifests |
| **nsdep** | `kubectl nsdep copy -f a -t b` | Copy/move workloads between namespaces |
| **kubectl-migrate** | | Migrate manifests between API versions |
| **sniff** | `kubectl sniff svc/x -p tcp` | ⭐ Wireshark on a Pod (needs tcpdump) |
| **exec-as** | `kubectl exec-as x --user root` | Exec as another UID |
| **cost** | `kubectl cost` | OpenCost integration |
| **ice** | `kubectl ice` | Delete pods to force a rolling restart |
| **restart** | `kubectl restart deploy/x` | A clearer rollout restart |
| **prompt** | `kubectl prompt` | A git-style prompt with cluster context |
| **kubectl-gadget** | | eBPF-powered tracing/observability |
| **krew itself** | | The plugin manager |

```bash
# ⭐ install the "production debugging starter pack" in one line
kubectl krew install ctx ns tree lineage neat stern node-shell who-can \
                       access-matrix resource-capacity df-pv view-secret \
                       get-all explore evict-pod deprecations sniff cost nsdep
```

---

<a name="32-tools-that-replace-kubectl"></a>
## 32. Tools that replace kubectl

| Tool | Type | Replaces | Why you'd use it |
|---|---|---|---|
| **k9s** | TUI | `get`, `describe`, `logs`, `exec`, `delete` | ⭐ The single biggest productivity gain. Keyboard-driven, live-updating |
| **Lens / OpenLens** | Desktop GUI | Everything | Visual, good for people who hate terminals |
| **kubectx / kubens** | CLI | `config use-context` | Fast switching with `-` for previous |
| **stern** | CLI | `logs -l` | Multi-pod, colour-coded, follows new pods |
| **kubetail** | Shell script | `logs -f` | Simple multi-pod tailing |
| **kubectl-tree** | Plugin | Reading `ownerReferences` | Ownership at a glance |
| **kube-ps1** | Shell | Guessing your context | ⭐ Shows `cluster:namespace` in your prompt |
| **kubectl-aliases** (ahmetb) | Shell | Typing | 800 generated aliases |
| **kubecolor** | Wrapper | Reading YAML | Colourised kubectl output |
| **kube-capacity** | CLI | `describe nodes` | A cluster-wide requests-vs-limits table |
| **kubens-namespace-tools** | | | |
| **kubectl-lineage** | Plugin | Ownership | Reverse: what owns this pod? |
| **kubescape** | TUI | k9s | A lighter k9s alternative |
| **k8sgpt** | CLI/AI | Diagnosing | ⭐ Runs ~40 analysers and explains failures in plain English |
| **Holmes (Robusta)** | CLI/AI | Diagnosing | LLM-assisted root-cause analysis |
| **Popeye** | CLI | Linting | Scores your cluster's hygiene |
| **kubescape** | CLI | Security | NSA/CISA + CIS benchmarks |
| **kube-bench** | CLI | Security | CIS Kubernetes Benchmark |
| **Trivy / kubeaudit** | CLI | Security | Vulnerability + misconfiguration scanning |
| **kubent / pluto** | CLI | Upgrades | ⭐ Find deprecated APIs |
| **kustomize / helm** | CLI | Raw `apply` | Templating and overlays |
| **Argo CD / Flux** | GitOps | `kubectl apply` in CI | Declarative, audited, self-healing |
| **krew** | CLI | Manual plugin installs | The plugin manager |
| **kubectl-debug** | CLI | Manual ephemeral containers | One-command debug pods |
| **kd** (kubectl-interactive-delete) | CLI | | |
| **kubectl-view-utilization** | Plugin | Capacity maths | An HTML view |

```bash
# k9s in 60 seconds
brew install k9s && k9s
#   :pods            the pod list (0 = all namespaces, / = filter)
#   :deploy :sts :ds :svc :ing :ns :nodes :events :crds :helm :pv :pvc :hpa :pdb
#   :pulse           a cluster dashboard
#   :xray deploy shop-prod    ⭐ the ownership X-ray
#   :rbac            permissions
#   :popeye          a lint
#   :plugin          krew plugins as k9s hotkeys
#   :ctx             switch cluster
#   hotkeys: l logs · d describe · s shell · e events · y YAML · ctrl-k delete
#            0 all-ns · 1 last-ns · / filter · fzf fuzzy · g top · esc back
#   ~/.config/k9s/config.yaml       — skins, refresh rates, aliases
#   ~/.config/k9s/aliases.yaml      — :dp → deployments
#   ~/.config/k9s/hotkeys.yaml      — custom hotkeys
#   ~/.config/k9s/skins/            — themes
#   ~/.config/k9s/plugins.yaml      — kubectl plugins as menu items

# k8sgpt — AI diagnosis
brew install k8sgpt
k8sgpt analyze
# 0 default/pod(shop-api-7d4f8c9b6-abcde): ImagePullBackOff
#   > The image ghcr.io/3558bhk/shop-api:1.2.0 cannot be pulled: unauthorized.
#     Check that the imagePullSecret "ghcr-creds" exists in namespace "shop".
k8sgpt analyze --explain --filter=Pod --backend=openai
k8sgpt analyze -o json | jq '.results[] | {namespace, name, problem: .details}'

# kubecolor
brew install kubecolor
alias kubectl=kubecolor

# kube-capacity
kubectl krew install resource-capacity
kubectl resource-capacity --pods --utilization --sort-by cpu
```

---

<a name="33-production-and-sre-scenarios"></a>
## 33. Production & SRE scenarios

> Twenty real incidents. Each one: **symptom → investigation → root cause → fix → prevention.** This is the format interviewers ask for, and the format your 3am brain needs.

### Scenario 1 — The site is down: 502s from the Ingress

**Symptom:** The load balancer returns 502 for `api.shop.example.com`. It worked an hour ago.

```bash
# 1. Where does the 502 come from?
curl -sv https://api.shop.example.com/health 2>&1 | grep -E 'server:|< HTTP'
# < HTTP/2 502
# < server: nginx            ← the ingress controller. So the LB is fine; the backend is not.

# 2. Is the Ingress controller healthy?
kubectl get pods -n ingress-nginx -o wide
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=50 | grep -E '502|upstream'
# 2026/09/09 14:20:11 [error] upstream prematurely closed connection while reading response header
#   from upstream, client: 1.2.3.4, server: api.shop.example.com,
#   request: "GET /health HTTP/2.0", upstream: "http://10.244.2.19:8080/health"

# ⭐ the upstream IP is the smoking gun. Is that pod alive?
kubectl get pods -A -o wide | grep 10.244.2.19
# (nothing — the pod is gone)

# 3. The Service and its endpoints
kubectl get endpointslices -n shop -l kubernetes.io/service-name=shop-api
# NAME          ADDRESSTYPE   PORTS   ENDPOINTS   AGE
# shop-api-a1b  IPv4          8080    <none>      3d       ← ⛔ NO ENDPOINTS

# 4. Why?
kubectl get pods -n shop -l app=shop-api
# NAME                        READY   STATUS             RESTARTS      AGE
# shop-api-9a2b3c4d5-abc      0/1     CrashLoopBackOff   7 (30s ago)   12m
# shop-api-9a2b3c4d5-def      0/1     CrashLoopBackOff   7 (45s ago)   12m

# 5. What happened 12 minutes ago?
kubectl rollout history deploy/shop-api -n shop
# REVISION  CHANGE-CAUSE
# 4         <none>                       ← ⭐ someone deployed 12 minutes ago
kubectl get rs -n shop -l app=shop-api --sort-by=.metadata.creationTimestamp \
  -o custom-columns='REV:.metadata.annotations.deployment\.kubernetes\.io/revision,NAME:.metadata.name,IMAGE:.spec.template.spec.containers[0].image,REPLICAS:.status.replicas'

# 6. The actual error
kubectl logs -n shop shop-api-9a2b3c4d5-abc --previous --tail=50
# Caused by: org.postgresql.util.PSQLException: FATAL: database "shop_v2" does not exist

# ROOT CAUSE: a deploy pointed at a database that was never created.
# The old pods were terminated (maxUnavailable was 1 of 2), so the Service has no endpoints.
```

**Fix:**

```bash
kubectl rollout undo deploy/shop-api -n shop
kubectl rollout status deploy/shop-api -n shop --timeout=180s
kubectl get endpointslices -n shop -l kubernetes.io/service-name=shop-api    # endpoints return
curl -s https://api.shop.example.com/health                                  # 200
```

**Prevention:**

```yaml
# 1. maxUnavailable: 0 → the rollout NEVER removes healthy pods until new ones are Ready
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate: {maxSurge: 1, maxUnavailable: 0}
  minReadySeconds: 30
  progressDeadlineSeconds: 600
# 2. A readinessProbe that actually exercises the dependency
# 3. A pre-deploy migration Job with backoffLimit: 0 that fails the pipeline
# 4. A PodDisruptionBudget
# 5. Argo Rollouts canary with an AnalysisTemplate that checks the error rate
```

---

### Scenario 2 — Pods randomly restart every few hours (OOMKilled)

**Symptom:** `RESTARTS` climbs steadily; users see occasional 500s.

```bash
kubectl get pods -n shop -l app=shop-api -o custom-columns=\
'NAME:.metadata.name,RESTARTS:.status.containerStatuses[0].restartCount,REASON:.status.containerStatuses[0].lastState.terminated.reason'
# shop-api-7d4f8c9b6-abc   14   OOMKilled
# shop-api-7d4f8c9b6-def   11   OOMKilled

kubectl describe pod shop-api-7d4f8c9b6-abc -n shop | grep -B2 -A6 'Last State'
#   Limits:    memory: 1536Mi
#   Requests:  memory: 1Gi
#   Last State: Terminated
#     Reason:   OOMKilled
#     Exit Code: 137

# how close is it running to the limit RIGHT NOW?
kubectl top pod shop-api-7d4f8c9b6-abc -n shop --containers
# shop-api-7d4f8c9b6-abc   api   142m   1489Mi       ← ⛔ 1489/1536 = 97%

# the history (Prometheus)
curl -s 'http://localhost:9090/api/v1/query' --data-urlencode 'query=
  max_over_time(container_memory_working_set_bytes{namespace="shop",pod=~"shop-api.*"}[6h]) / 1024 / 1024' \
  | jq -r '.data.result[] | "\(.metric.pod)  peak=\(.value[1]|tonumber|floor) MiB"'

# is it a leak, or just an undersized limit? A leak grows monotonically:
curl -s 'http://localhost:9090/api/v1/query_range' --data-urlencode \
  'query=container_memory_working_set_bytes{namespace="shop",pod="shop-api-7d4f8c9b6-abc"}' \
  --data-urlencode 'start='$(date -d '6 hours ago' +%s) --data-urlencode 'end='$(date +%s) \
  --data-urlencode 'step=300' | jq -r '.data.result[0].values[] | "\(.[0]|todate)  \((.[1]|tonumber/1048576)|floor) MiB"'
# 09:00  412 MiB      ← after a restart
# 09:30  688 MiB
# 10:00  901 MiB
# …
# 14:00  1522 MiB     ← monotonically increasing = ⛔ A LEAK, not just a small limit

# for a JVM, is it heap or off-heap?
kubectl exec -n shop shop-api-7d4f8c9b6-abc -- sh -c 'jcmd 1 VM.native_memory summary 2>/dev/null || jmap -histo 1 | head -20'
kubectl exec -n shop shop-api-7d4f8c9b6-abc -- sh -c 'echo $JAVA_OPTS'
# -Xmx1400m     ← ⛔ heap 1400m + metaspace + threads + direct buffers > the 1536Mi limit
```

**Root cause:** the JVM heap was sized at ~91% of the container memory limit, leaving nothing for metaspace, thread stacks, direct buffers, or the page cache. **Any JVM with `-Xmx` ≈ container limit will OOMKill.**

**Fix:**

```yaml
resources:
  requests: {memory: 2Gi}
  limits:   {memory: 2Gi}      # ⭐ Guaranteed QoS → evicted last
env:
  # ⭐ let the JVM compute its own heap from the cgroup limit
  - {name: JAVA_TOOL_OPTIONS, value: "-XX:MaxRAMPercentage=65.0 -XX:InitialRAMPercentage=50.0"}
  # or set it explicitly and leave headroom:
  # -Xmx1300m for a 2Gi container
```

**Prevention:** an alert on `container_memory_working_set_bytes / limit > 0.85`, a VPA in `Off` mode for recommendations, and a heap-vs-container-limit rule in your Dockerfile standard (see [Project 9](./12-PROJECT-9-java-backend.md)).

---

### Scenario 3 — A node goes NotReady during a deploy

**Symptom:** Two pods are `Terminating` and won't go away; new pods are `Pending`.

```bash
kubectl get nodes
# learn-worker2   NotReady   <none>   12d   v1.37.0

kubectl describe node learn-worker2 | grep -A8 Conditions
# Ready   Unknown   2026-09-09T14:12:11Z   NodeStatusUnknown   Kubelet stopped posting node status

kubectl get lease -n kube-node-lease learn-worker2 -o jsonpath='{.spec.renewTime}'; echo
# 2026-09-09T14:12:01Z         ← 40 minutes stale

kubectl get pods -A -o wide --field-selector spec.nodeName=learn-worker2 | head
# shop   shop-api-7d4f8c9b6-abc   1/1   Terminating   0   3d
# shop   shop-api-9a2b3c4d5-def   0/1   Pending       0   5m

kubectl describe pod shop-api-9a2b3c4d5-def -n shop | grep -A5 Events
# FailedScheduling: 0/3 nodes are available:
#   1 node(s) were unschedulable, 2 node(s) didn't match pod anti-affinity rules

# ⭐ the anti-affinity is blocking the replacement because the OLD pod
#    is still nominally "on" learn-worker2 in the API's view
kubectl get deploy shop-api -n shop -o json | jq '.spec.template.spec.affinity'
```

**Root cause:** hard pod anti-affinity + a stuck Terminating pod on an unreachable node = no place for the replacement.

**Fix — the decision depends on whether the node is really dead:**

```bash
# is it a network partition or a dead machine?
ssh -o ConnectTimeout=5 learn-worker2 'uptime' 2>&1
# ⛔ unreachable → check the cloud console / IPMI

# IF THE NODE IS TRULY DEAD (terminated in the cloud, powered off):
kubectl delete node learn-worker2                      # removes it from the API
kubectl get pods -A -o wide --field-selector spec.nodeName=learn-worker2   # should be empty
# force-remove any pod still stuck Terminating
kubectl delete pod shop-api-7d4f8c9b6-abc -n shop --grace-period=0 --force
kubectl get volumeattachment | grep learn-worker2      # detach the volumes
kubectl delete volumeattachment <name>

# IF IT MIGHT COME BACK (a partition, not a death) — ⚠️ DANGER for stateful workloads:
# do NOT force-delete StatefulSet pods. Two writers to one RWO volume = corruption.
# Instead: fix the partition, or fence the node at the storage layer.
kubectl get pods -n db -o wide | grep learn-worker2
```

**Prevention:**
- Soft (`preferred`) anti-affinity for most stateless apps; hard only when you truly can't tolerate co-location.
- `topologySpreadConstraints` with `whenUnsatisfiable: ScheduleAnyway` instead of hard anti-affinity.
- A node-problem-detector DaemonSet + the cloud provider's automatic node repair.
- For stateful workloads: `ReadWriteOncePod` + a fencing controller.

---

### Scenario 4 — The disk fills up: `DiskPressure` evictions

```bash
kubectl get nodes
# learn-worker   Ready,SchedulingDisabled   <none>   12d   v1.37.0
kubectl describe node learn-worker | grep -A8 Conditions
# DiskPressure   True   2026-09-09T14:30:11Z   KubeletHasDiskPressure   kubelet has disk pressure
kubectl get events -A --field-selector reason=Evicted --sort-by=.lastTimestamp | tail -20
# shop   cache-warmer-abc   Evicted   The node was low on resource: ephemeral-storage

# on the node
kubectl node-shell learn-worker
df -h /
# /dev/nvme0n1p1   100G   98G   2.0G  98% /          ← ⛔
du -sh /var/lib/containerd /var/lib/kubelet /var/log 2>/dev/null | sort -h
# 62G  /var/lib/containerd
# 24G  /var/lib/kubelet
#  8G  /var/log

# who's using it?
crictl images | awk '{print $3, $4}' | sort -h | tail -20
du -sh /var/lib/containerd/io.containerd.content.v1.content 2>/dev/null
du -sh /var/log/pods/* | sort -h | tail -10
du -sh /var/lib/kubelet/pods/*/volumes/kubernetes.io~empty-dir/* 2>/dev/null | sort -h | tail -10
# ⭐ 18G in one pod's emptyDir
```

**Root cause candidates, in order:**
1. **An `emptyDir` with no `sizeLimit`** filled by a cache or a large download.
2. **Images never garbage-collected** (containerd keeps them until the `imagefs.available` threshold).
3. **Container logs never rotated** (a misconfigured `containerLogMaxSize`).
4. **A PVC's underlying filesystem** full (not the node — check `kubectl df-pv`).

**Fix:**

```bash
# immediate relief
kubectl node-shell learn-worker -- crictl rmi --prune          # remove unused images
kubectl node-shell learn-worker -- journalctl --vacuum-size=500M
kubectl node-shell learn-worker -- find /var/log/pods -name '*.log.*' -mtime +3 -delete
kubectl get pods -A --field-selector=status.phase=Failed -o name | xargs -r kubectl delete
kubectl get pods -A -o json | jq -r '.items[] | select(.status.reason=="Evicted")
  | "\(.metadata.namespace) \(.metadata.name)"' | while read ns p; do kubectl delete pod $p -n $ns; done

# then fix the offender
kubectl get pods -A -o json | jq -r '.items[] | .metadata.namespace as $ns | .metadata.name as $p |
  (.spec.volumes[]? | select(.emptyDir) | select(.emptyDir.sizeLimit == null) |
   "\($ns)/\($p)  volume \(.name)  ⚠️ emptyDir with no sizeLimit")'
kubectl uncordon learn-worker
```

**Prevention:**

```yaml
volumes:
  - name: cache
    emptyDir: {sizeLimit: 2Gi}          # ⭐ ALWAYS set this
```
```bash
# kubelet GC thresholds (raise them so GC happens BEFORE eviction)
#   imageGCHighThresholdPercent: 85   imageGCLowThresholdPercent: 80
#   containerLogMaxSize: 50Mi         containerLogMaxFiles: 5
#   evictionHard: {nodefs.available: 15%, imagefs.available: 20%}
```

---

### Scenario 5 — A CronJob silently stopped running

```bash
kubectl get cronjob nightly-backup -n db
# NAME              SCHEDULE     SUSPEND   ACTIVE   LAST SCHEDULE   AGE
# nightly-backup    30 2 * * *   False     0        <none>          30d     ← ⛔ never scheduled?

kubectl describe cronjob nightly-backup -n db | tail -15
# Events:
#   Warning  MissingSchedule   ...   cronjob-controller   Cannot determine if time needs to be run:
#     failed to get timezone: "Asia/Kolkata" is not a valid timezone
#   Normal   SawCompletedJob   12d   cronjob-controller   Saw completed job: nightly-backup-18123456
# ⭐ it last ran 12 days ago

kubectl get jobs -n db --sort-by=.metadata.creationTimestamp | tail -5
kubectl get cronjob nightly-backup -n db -o jsonpath='{.status.lastScheduleTime}'; echo
# 2026-08-28T21:00:11Z
kubectl logs -n kube-system kube-controller-manager-learn-control-plane --tail=200 | grep -i cron
```

**The four causes of a silently dead CronJob:**

| Cause | How to spot it |
|---|---|
| **`startingDeadlineSeconds` is nil** and the controller was down for >100 schedules | It skips all missed runs and never catches up |
| **A stuck Job from a previous run + `concurrencyPolicy: Forbid`** | `kubectl get jobs -n db` shows one still Running/Active |
| **An invalid `timeZone`** (no tzdata in the controller-manager image) | `describe cronjob` → the event |
| **The Job keeps failing and `backoffLimit` is hit** | `kubectl get jobs` → Completions 0/1, `describe job` |

```bash
# the stuck-Job case — by far the most common
kubectl get jobs -n db -l cronjob-name=nightly-backup
# nightly-backup-18123456   0/1   1      3       12d      ← ACTIVE 1, stuck for 12 days
kubectl describe job nightly-backup-18123456 -n db | tail -10
kubectl get pods -n db -l job-name=nightly-backup-18123456
# nightly-backup-18123456-x7k   1/1   Running   0   12d    ← the backup has been "running" for 12 days

# FIX: kill the stuck job; the next schedule fires normally
kubectl delete job nightly-backup-18123456 -n db
kubectl create job manual-$(date +%s) -n db --from=cronjob/nightly-backup
kubectl wait --for=condition=complete job/manual-1757412345 -n db --timeout=3600s
```

**Prevention:** always set `activeDeadlineSeconds` on the `jobTemplate.spec`, `ttlSecondsAfterFinished`, `startingDeadlineSeconds`, and an alert on `kube_cronjob_status_last_schedule_time` being older than 2× the schedule interval.

---

### Scenario 6 — A Deployment keeps scaling back to 1 replica

```bash
kubectl scale deploy/shop-api -n shop --replicas=5
kubectl get deploy shop-api -n shop
# shop-api   5/5   5   5   3d
sleep 60
kubectl get deploy shop-api -n shop
# shop-api   1/1   1   1   3d        ← ⛔ back to 1
```

**Three possible owners of `spec.replicas`:**

```bash
# 1. an HPA?
kubectl get hpa -n shop
kubectl get deploy shop-api -n shop -o jsonpath='{.metadata.annotations}'; echo | jq .

# 2. ⭐ a GitOps controller re-applying a manifest that has replicas: 1?
kubectl get deploy shop-api -n shop -o yaml --show-managed-fields | grep -B8 'f:replicas'
#   - apiVersion: apps/v1
#     manager: argocd-application-controller     ← ⭐ ARGO CD OWNS IT
#     operation: Update
#     time: "2026-09-09T14:41:02Z"
#     fieldsV1: {"f:spec":{"f:replicas":{}}}
kubectl get applications -n argocd
kubectl describe application shop -n argocd | grep -E 'Sync Status|Health|Operation'
# Sync Status:  Synced
# (it re-synced at 14:41 and set replicas back to the value in Git)

# 3. a client-side-apply last-applied annotation?
kubectl get deploy shop-api -n shop -o jsonpath='{.metadata.annotations.kubectl\.kubernetes\.io/last-applied-configuration}' | jq .spec.replicas
```

**Root cause:** Git is the source of truth and says `replicas: 1`. Argo CD re-synced and undid your manual change. **This is GitOps working correctly.**

**Fix (three options, in order of preference):**

```yaml
# OPTION 1 ⭐⭐ — remove `replicas` from the manifest entirely and let an HPA own it
spec:
  # replicas: 1        ← DELETE THIS LINE
```
```yaml
# OPTION 2 — tell Argo CD to ignore the field
apiVersion: argoproj.io/v1alpha1
kind: Application
spec:
  ignoreDifferences:
    - group: apps
      kind: Deployment
      jsonPointers: ["/spec/replicas"]
```
```bash
# OPTION 3 — change it in Git (the ONLY right answer for a permanent change)
# edit k8s/overlays/prod/deployment.yaml, commit, push
# then:
argocd app sync shop
```

⚠️ **Never `argocd app rollback` for this.** In GitOps, rollback = `git revert` + sync. See [Project 14](./17-PROJECT-14-helm-gitops.md).

---

### Scenario 7 — `Pending` forever: not enough CPU

```bash
kubectl get pods -n shop
# shop-api-9a2b3c4d5-xyz   0/1   Pending   0   15m
kubectl describe pod shop-api-9a2b3c4d5-xyz -n shop | grep -A6 Events
# FailedScheduling: 0/3 nodes are available:
#   1 node(s) had untolerated taint {node-role.kubernetes.io/control-plane: },
#   2 Insufficient cpu.
#   preemption: 0/2 nodes are available: 2 No preemption victims found for incoming pod.

# how much is actually free?
kubectl describe nodes | grep -A5 'Allocated resources' | grep cpu
# cpu   3850m (49%)   ...   ← learn-worker
# cpu   7600m (97%)   ...   ← learn-worker2

kubectl resource-capacity --utilization
kubectl get pods -n shop -o json | jq -r '.items[] | . as $p |
  (.spec.containers[].resources.requests.cpu // "none") as $r | "\($r)\t\($p.metadata.name)"' | sort -rh | head

# ⭐ who is asking for the most?
kubectl get pods -A -o json | jq -r '.items[] | .metadata.namespace as $ns | .metadata.name as $p |
  (.spec.containers[] | select(.resources.requests.cpu) |
   "\(.resources.requests.cpu)\t\($ns)/\($p)/\(.name)")' | sort -rh | head -20
```

**The four fixes, cheapest first:**

```bash
# 1. ⭐ Right-size the requests. Most teams over-request by 3–10×.
kubectl get --raw "/apis/metrics.k8s.io/v1beta1/namespaces/shop/pods" | jq -r '.items[] |
  "\(.metadata.name)\t\(.containers[0].usage.cpu)"'
# shop-api-…   87345612n    = 87m     ← it's USING 87m and REQUESTING 1000m
kubectl patch deploy shop-api -n shop --type=json -p='[
  {"op":"replace","path":"/spec/template/spec/containers/0/resources/requests/cpu","value":"250m"}]'

# 2. Scale the cluster up (CA/Karpenter should have done this — find out why not)
kubectl logs -n kube-system deploy/cluster-autoscaler --tail=200 | grep -i 'didn.t trigger'
# "Pod didn't trigger scale-up: 1 max node group size reached"
aws autoscaling update-auto-scaling-group --auto-scaling-group-name prod-nodes --max-size 10

# 3. Add a PriorityClass so critical pods can preempt batch work
kubectl get pods -A -o json | jq -r '.items[] | select(.spec.priorityClassName==null) | "\(.metadata.namespace)/\(.metadata.name)"' | head

# 4. Evict/stop what isn't needed
kubectl get deploy -n dev -o name | xargs -n1 kubectl scale -n dev --replicas=0
```

---

### Scenario 8 — A Secret rotation broke everything

**Symptom:** After rotating the DB password, every pod crashes with authentication failures.

```bash
kubectl logs -n shop deploy/shop-api --previous --tail=20
# FATAL: password authentication failed for user "shop"

# the secret IS updated…
kubectl get secret db-creds -n shop -o jsonpath='{.data.password}' | base64 -d; echo
# N3VwZDhLcUwx     ← the new password

# …but the POD still has the old one
kubectl exec -n shop deploy/shop-api -- printenv DB_PASSWORD
# S3jcmV0IQ==          ← ⛔ the OLD password
```

**Root cause:** the Secret is consumed via `env`, and **env vars never update without a Pod restart**. (If it were a volume mount, it would update in ~60s — but the app caches the connection pool at startup anyway.)

**Fix:**

```bash
kubectl rollout restart deploy/shop-api -n shop
kubectl rollout status deploy/shop-api -n shop --timeout=180s
kubectl exec -n shop deploy/shop-api -- printenv DB_PASSWORD    # the new one
```

**Prevention — ⭐ the checksum annotation:**

```yaml
spec:
  template:
    metadata:
      annotations:
        checksum/secret: {{ include (print $.Template.BasePath "/secret.yaml") . | sha256sum }}
```

Then any Secret change alters the pod template → an automatic rolling update. In plain YAML, compute it in CI:

```bash
HASH=$(kubectl get secret db-creds -n shop -o jsonpath='{.data}' | sha256sum | cut -c1-16)
kubectl patch deploy shop-api -n shop --type=merge \
  -p "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"checksum/secret\":\"$HASH\"}}}}}"
```

**And for the database itself:** the real answer is **dual-credential rotation** — create the new user, deploy it, then drop the old one. Never a hard cutover.

---

### Scenario 9 — CPU throttling: the app is slow but not busy

**Symptom:** p99 latency tripled. CPU utilization shows only 40%. No errors.

```bash
kubectl top pods -n shop -l app=shop-api --containers
# shop-api-…   api   402m   812Mi       ← using 402m of a 500m limit = 80%

# ⭐ the throttling metric — the one that reveals it
kubectl exec -n shop deploy/shop-api -- cat /sys/fs/cgroup/cpu.stat
# nr_periods 184320
# nr_throttled 92160              ← ⛔ throttled in HALF the periods
# throttled_usec 41234567890

curl -s 'http://localhost:9090/api/v1/query' --data-urlencode 'query=
  sum(rate(container_cpu_cfs_throttled_periods_total{namespace="shop",pod=~"shop-api.*"}[5m]))
  / sum(rate(container_cpu_cfs_periods_total{namespace="shop",pod=~"shop-api.*"}[5m]))' \
  | jq '.data.result[0].value[1]'
# "0.5123"        ← ⛔ throttled 51% of the time
```

**Root cause:** a CPU **limit** of 500m. The CFS quota refills every 100ms period; a JVM doing GC or a Go runtime with many goroutines easily burns 500ms of CPU *within a single 100ms period across multiple threads*, then sits idle for the rest of the period. The average looks fine; the latency is terrible.

**Fix:**

```bash
# OPTION 1 ⭐⭐ — remove the CPU limit entirely (the modern consensus for JVMs and Go)
kubectl patch deploy shop-api -n shop --type=json -p='[
  {"op":"remove","path":"/spec/template/spec/containers/0/resources/limits/cpu"}]'
# requests.cpu stays → the scheduler still packs correctly, and Burstable QoS is preserved

# OPTION 2 — raise the limit to 4× the request
kubectl patch deploy shop-api -n shop --type=json -p='[
  {"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/cpu","value":"2"}]'
```

**The rule:** **CPU is compressible — throttle, never kill. Memory is incompressible — kill, never throttle.** So: **always set memory requests AND limits; set CPU requests; be very careful about CPU limits.**

⚠️ Removing CPU limits moves you from `Guaranteed` to `Burstable` QoS, which means the pod is evicted sooner under node memory pressure. Set `memory requests == limits` to keep the important part of Guaranteed behaviour.

---

### Scenario 10 — A namespace is stuck in `Terminating`

```bash
kubectl get ns shop-old
# NAME       STATUS        AGE
# shop-old   Terminating   30d
# (it's been Terminating for 4 hours)

kubectl get ns shop-old -o json | jq '.status.conditions'
# [{"type":"NamespaceDeletionContentFailure","status":"True",
#   "message":"Failed to delete all resource types, 1 remaining:
#     the server could not find the requested resource"}]

kubectl get ns shop-old -o json | jq '.spec.finalizers, .metadata.finalizers'
# ["kubernetes"]
# []

# ⭐ 1. is an APIService down? (the most common cause)
kubectl get apiservices | grep -v True
# v1beta1.custom.example.com   old-system/old-webhook   False   4h   service/old-webhook not found

# 2. what's actually still in there?
kubectl api-resources --verbs=list --namespaced -o name \
  | xargs -n1 -I{} sh -c 'kubectl get {} -n shop-old --ignore-not-found 2>/dev/null' | grep -v '^$'

# 3. the orphan CRs whose CRD is gone
kubectl get all -n shop-old
kubectl get $(kubectl api-resources --verbs=list --namespaced -o name | tr '\n' ',' | sed 's/,$//') -n shop-old 2>&1 | grep -i 'error\|not found'
```

**Root cause:** the namespace controller can't LIST some resource type — usually because an aggregated APIService is `False`, or a CRD was deleted while instances remained.

**Fix, in order:**

```bash
# A. repair the APIService (the right fix)
kubectl delete apiservice v1beta1.custom.example.com
kubectl get ns shop-old        # → gone within seconds

# B. if the operator is dead but its CRDs remain, delete the CRs first
kubectl get mycrds.example.com -n shop-old -o name | xargs -r kubectl delete -n shop-old --wait=false
# stuck on a finalizer?
kubectl get mycrds.example.com -n shop-old -o name | xargs -r -I{} \
  kubectl patch {} -n shop-old --type=merge -p '{"metadata":{"finalizers":null}}'

# C. ⚠️ the last resort — clear the namespace finalizer
kubectl get ns shop-old -o json | jq '.spec.finalizers = []' > /tmp/ns.json
kubectl replace --raw "/api/v1/namespaces/shop-old/finalize" -f /tmp/ns.json
# ⛔ this leaves the underlying cloud resources (LBs, disks, DNS) orphaned. Clean them up manually.
```

---

### Scenario 11 — A PVC is stuck: `Multi-Attach error`

```bash
kubectl get pods -n db
# db-0   0/1   ContainerCreating   0   8m
kubectl describe pod db-0 -n db | grep -A6 Events
# Warning  FailedAttachVolume  8m (x4)  attachdetach-controller
#   Multi-Attach error for volume "pvc-9f2a1b3c" Volume is already used by pod(s) db-0-previous
# Warning  FailedMount  2m (x6)  kubelet
#   Unable to attach or mount volumes: unmounted volumes=[data], unattached volumes=[data kube-api-access]

kubectl get pods -A -o wide | grep db-0
# db   db-0-previous   1/1   Terminating   0   3d   10.244.3.9   learn-worker3   ← ⛔
kubectl get nodes learn-worker3
# learn-worker3   NotReady   <none>   12d   v1.37.0
kubectl get volumeattachment | grep pvc-9f2a1b3c
# csi-abc123   ebs.csi.aws.com   pv-9f2a1b3c   learn-worker3   true   3d
```

**Root cause:** the RWO volume is still attached to `learn-worker3`, which is NotReady. The old pod is Terminating but the kubelet can't confirm the container stopped, so the volume is never detached.

**Fix:**

```bash
# 1. is learn-worker3 REALLY dead? (the critical question)
aws ec2 describe-instance-status --instance-ids $(kubectl get node learn-worker3 -o jsonpath='{.spec.providerID}' | sed 's|.*:||')
# State: terminated          ← ✅ it's gone

# 2. remove the node → the AD controller detaches the volume after 6 minutes
kubectl delete node learn-worker3
kubectl get volumeattachment -w | grep pvc-9f2a1b3c      # waits for detachment
# (or force it, if the cloud has already released it)
kubectl delete volumeattachment csi-abc123

# 3. remove the zombie pod
kubectl delete pod db-0-previous -n db --grace-period=0 --force

# 4. the new pod attaches and starts
kubectl get pod db-0 -n db -w
```

⚠️ **If the node is merely partitioned (still running), force-detaching the volume and starting `db-0` elsewhere means TWO Postgres processes writing to one disk.** That's unrecoverable corruption. Fence the node first (cut its network/STONITH), or don't proceed.

**Prevention:** `accessModes: [ReadWriteOncePod]` (v1.29+) — the API server itself refuses a second attach.

---

### Scenario 12 — Latency doubled and nobody changed anything

```bash
# 1. Is it the app or the platform?
curl -s 'http://localhost:9090/api/v1/query' --data-urlencode 'query=
  histogram_quantile(0.99, sum(rate(http_server_duration_seconds_bucket{namespace="shop"}[5m])) by (le))' | jq .

# 2. ⭐ Did the node get busier? (a NOISY NEIGHBOUR)
kubectl top nodes
kubectl describe node learn-worker | grep -A5 'Allocated resources'
# cpu  7600m (97%)   ← ⛔ the node is packed

kubectl get pods -A -o wide --field-selector spec.nodeName=learn-worker | wc -l
# 68

# 3. Who moved in?
kubectl get pods -A --field-selector spec.nodeName=learn-worker --sort-by=.metadata.creationTimestamp -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,CPU:.spec.containers[0].resources.requests.cpu,START:.status.startTime' | tail -15

# 4. Is OUR app being throttled because of it?
kubectl exec -n shop deploy/shop-api -- cat /sys/fs/cgroup/cpu.stat

# 5. Did the HPA fail to scale?
kubectl describe hpa shop-api -n shop | tail -15
kubectl get hpa shop-api -n shop
# shop-api   Deployment/shop-api   <unknown>/70%   ← ⛔ metrics-server is down

# 6. Is it DNS? (the ndots:5 trap under load)
kubectl exec -n shop deploy/shop-api -- sh -c 'time wget -qO- http://api.stripe.com/ 2>&1 | head -1'
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=100 | grep -c 'i/o timeout'
curl -s 'http://localhost:9090/api/v1/query' --data-urlencode \
  'query=sum(rate(coredns_dns_request_duration_seconds_sum[5m])) / sum(rate(coredns_dns_request_duration_seconds_count[5m]))'
```

**Root cause candidates ranked by frequency:**
1. A **noisy neighbour** — someone else's workload landed on the same node and there are no CPU limits.
2. **metrics-server down** → the HPA reports `<unknown>` → no scale-out.
3. **CPU throttling** (scenario 9).
4. **CoreDNS saturation** — 2 replicas, `ndots:5`, thousands of external calls.
5. **A connection pool exhausted** by a slow dependency.
6. **Node-level TCP/IPVS conntrack table full** (`nf_conntrack: table full, dropping packet` in `dmesg`).

```bash
# conntrack — the silent killer at scale
kubectl node-shell learn-worker -- dmesg -T | grep -i conntrack
# nf_conntrack: table full, dropping packet
kubectl node-shell learn-worker -- sysctl net.netfilter.nf_conntrack_count net.netfilter.nf_conntrack_max
# net.netfilter.nf_conntrack_count = 262144
# net.netfilter.nf_conntrack_max = 262144          ← ⛔ FULL
# fix: raise nf_conntrack_max, or switch kube-proxy to IPVS/Cilium eBPF
```

**Prevention:** PriorityClasses for critical workloads, `topologySpreadConstraints`, HPA on a custom metric, a DaemonSet-level `node-local-dns` cache, and alerts on `nr_throttled` and `conntrack` saturation.

---

### Scenario 13 — An admission webhook is blocking all deploys

```bash
kubectl apply -f deploy.yaml -n shop
# Error from server: error when creating "deploy.yaml":
#   admission webhook "validate.policy.example.com" denied the request:
#   Post "https://policy-webhook.policy.svc:443/validate?timeout=10s": context deadline exceeded

kubectl get validatingwebhookconfigurations
kubectl get pods -n policy
# policy-webhook-abc   0/1   CrashLoopBackOff   9 (30s ago)   20m     ← ⛔

kubectl get validatingwebhookconfiguration policy-webhook -o json | jq '.webhooks[] |
  {name, failurePolicy, timeoutSeconds, namespaceSelector, rules: [.rules[].resources]}'
# {"name":"validate.policy.example.com","failurePolicy":"Fail","timeoutSeconds":10,
#  "namespaceSelector":null,                    ← ⛔ applies to EVERY namespace including kube-system
#  "rules":["pods","deployments","statefulsets","configmaps","secrets","services"]}

# ⚠️ THIS IS NOW A CLUSTER-WIDE OUTAGE. Nothing can be created or updated anywhere,
#    including the webhook's own namespace. The cluster cannot self-heal.
```

**Fix — you need a break-glass path:**

```bash
# 1. Can you still delete? DELETE is often not in the webhook's rules.
kubectl delete validatingwebhookconfiguration policy-webhook
# ✅ works if the webhook only intercepts CREATE/UPDATE on those resources

# 2. If delete is also intercepted, scope the webhook away from your namespace
kubectl patch validatingwebhookconfiguration policy-webhook --type=json -p='[
  {"op":"replace","path":"/webhooks/0/failurePolicy","value":"Ignore"}]'

# 3. If even patch is blocked, go straight to etcd via the API with a cluster-admin cert
kubectl --kubeconfig=/etc/kubernetes/admin.conf delete validatingwebhookconfiguration policy-webhook

# 4. If ALL kubectl is blocked (a mutating webhook on everything), you need
#    control-plane access: stop the API server, remove the webhook from etcd, restart.
sudo systemctl stop kube-apiserver
ETCDCTL_API=3 etcdctl --cacert=… --cert=… --key=… \
  del /registry/mutatingwebhookconfigurations/policy-webhook
sudo systemctl start kube-apiserver
```

**Prevention — the four rules for any webhook:**

```yaml
webhooks:
  - name: validate.policy.example.com
    failurePolicy: Fail               # acceptable ONLY with a narrow scope
    timeoutSeconds: 3                 # ⭐ 10s is far too long
    namespaceSelector:                # ⭐⭐ ALWAYS exclude the control plane
      matchExpressions:
        - {key: kubernetes.io/metadata.name, operator: NotIn,
           values: [kube-system, kube-public, kube-node-lease, policy]}
    objectSelector:
      matchLabels: {policy-check: enabled}    # ⭐ opt-in, not opt-out
    rules:
      - apiGroups: ["apps"]
        operations: ["CREATE","UPDATE"]       # ⭐ never DELETE, never "*/*"
        resources: ["deployments"]
    sideEffects: None
```

Plus: **3 webhook replicas, a PDB, topology spread, and a startupProbe** — the webhook must be more available than anything it guards.

---

### Scenario 14 — A rollout is stuck at 50% for 20 minutes

```bash
kubectl rollout status deploy/shop-api -n shop
# Waiting for deployment "shop-api" rollout to finish: 2 out of 4 new replicas have been updated...

kubectl get pods -n shop -l app=shop-api -o wide
# shop-api-9a2b3c4d5-abc   1/1   Running   0   18m   ← new, READY
# shop-api-9a2b3c4d5-def   1/1   Running   0   18m   ← new, READY
# shop-api-9a2b3c4d5-ghi   0/1   Pending   0   18m   ← ⛔ new, stuck
# shop-api-7d4f8c9b6-jkl   1/1   Running   0   3d    ← old, still serving

kubectl describe pod shop-api-9a2b3c4d5-ghi -n shop | grep -A6 Events
# FailedScheduling: 0/3 nodes are available: 3 Insufficient cpu
```

**Root cause:** `maxSurge: 25%` of 4 = 1 extra pod, and there's no CPU for it. The old pods can't be removed because `maxUnavailable: 25%` = 1 and one is already… actually, the Deployment is waiting for a surge slot that never comes.

```bash
# the immediate unblock
kubectl get nodes -o json | jq -r '.items[] | "\(.metadata.name) \(.status.allocatable.cpu)"'
kubectl resource-capacity --utilization

# OPTION A: free up CPU
kubectl get pods -A -o json | jq -r '.items[] | . as $p |
  (.spec.containers[] | select(.resources.requests.cpu) | "\(.resources.requests.cpu)\t\($p.metadata.namespace)/\($p.metadata.name)")' \
  | sort -rh | head
kubectl scale deploy/batch-worker -n jobs --replicas=0

# OPTION B: switch to maxUnavailable so it doesn't need a surge slot
kubectl patch deploy shop-api -n shop --type=merge -p '{
  "spec":{"strategy":{"rollingUpdate":{"maxSurge":0,"maxUnavailable":1}}}}'
# ⚠️ this means one pod DOWN during the update — only for non-critical services

# OPTION C: scale the cluster
kubectl logs -n kube-system deploy/cluster-autoscaler --tail=100 | grep -i 'scale-up'

# OPTION D: give up and roll back
kubectl rollout undo deploy/shop-api -n shop
```

**Prevention:** `kubectl resource-capacity --pods N` in CI to check the cluster can absorb the surge before you deploy; and set `progressDeadlineSeconds` so the Deployment reports `Progressing=False` instead of hanging silently.

---

### Scenario 15 — The cluster can't reach the internet (egress broken)

```bash
kubectl run t --image=nicolaka/netshoot -n shop --rm -it --restart=Never -- bash
# dig +short api.stripe.com
# ;; connection timed out; no servers could be reached          ← ⛔ DNS is broken too

# 1. Can we resolve at all?
dig @10.96.0.10 kubernetes.default.svc.cluster.local     # ← internal DNS
# ;; communications error … timed out
kubectl get pods -n kube-system -l k8s-app=kube-dns
# coredns-5d78c9869d-abc   0/1   CrashLoopBackOff   12 (30s ago)   20m     ← ⛔

# 2. Why is CoreDNS crashing?
kubectl logs -n kube-system coredns-5d78c9869d-abc --previous --tail=30
# [FATAL] plugin/loop: Loop 127.0.0.53:53 detected for zone ".", sending SIGTERM
# ⭐ the classic: the node's /etc/resolv.conf points at a local systemd-resolved
#   stub listener, and CoreDNS forwards to itself → an infinite loop → it kills itself

kubectl node-shell learn-worker -- cat /etc/resolv.conf
# nameserver 127.0.0.53        ← ⛔ the systemd-resolved stub

# FIX A: point CoreDNS at real upstream servers
kubectl edit configmap coredns -n kube-system
```
```
.:53 {
    errors
    health
    ready
    kubernetes cluster.local in-addr.arpa ip6.arpa { pods insecure fallthrough in-addr.arpa ip6.arpa }
    prometheus :9153
    forward . 1.1.1.1 8.8.8.8 {        # ⭐ explicit upstreams, not /etc/resolv.conf
        max_concurrent 1000
    }
    cache 30
    loop
    reload
    loadbalance
}
```
```bash
kubectl rollout restart deploy/coredns -n kube-system
kubectl get pods -n kube-system -l k8s-app=kube-dns -w

# FIX B: remove the `loop` plugin so it doesn't self-terminate (⚠️ hides the problem)
# FIX C: disable the systemd-resolved stub on the nodes

# 3. Now DNS works but egress still fails?
kubectl run t --image=nicolaka/netshoot -n shop --rm -it --restart=Never -- bash
# dig +short api.stripe.com         → 104.16.x.x   ✅
# curl -sv https://api.stripe.com/  → curl: (28) Connection timed out   ⛔

# a NetworkPolicy blocking egress?
kubectl get netpol -n shop
kubectl describe netpol default-deny -n shop
# Spec:  PodSelector:  <all>       Policy Types: Egress        ← ⛔ ALL EGRESS DENIED

# FIX: add an explicit egress allow
```
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: allow-egress, namespace: shop}
spec:
  podSelector: {}
  policyTypes: [Egress]
  egress:
    - to: [{namespaceSelector: {}}]              # anything in the cluster
      ports: [{protocol: TCP}, {protocol: UDP}]
    - to: [{ipBlock: {cidr: 0.0.0.0/0, except: [10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16]}}]
      ports: [{protocol: TCP, port: 443}, {protocol: TCP, port: 80}]
    - to: [{namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: kube-system}}},
           {ipBlock: {cidr: 0.0.0.0/0}}]
      ports: [{protocol: UDP, port: 53}, {protocol: TCP, port: 53}]
```
```bash
# 4. Or it's the cloud: no NAT gateway, no route to 0.0.0.0/0, a security group,
#    or an egress-only internet gateway missing. Check outside Kubernetes.
```

---

### Scenario 16 — A Helm upgrade left the release in a broken state

```bash
helm list -n shop -a
# NAME      NAMESPACE   REVISION   UPDATED                    STATUS        APP VERSION
# shop      shop        7          2026-09-09 14:50:11        failed        1.2.0
#                                          ↑ ⛔ "failed", not "deployed"

helm history shop -n shop
# REVISION  UPDATED                    STATUS      DESCRIPTION
# 5         2026-09-08 09:11:02        superseded  Upgrade complete
# 6         2026-09-09 14:20:11        superseded  Upgrade complete
# 7         2026-09-09 14:50:11        failed      Upgrade "shop" failed:
#   timed out waiting for the condition

# ⚠️ while a release is in "pending-upgrade"/"failed", every new helm command errors:
helm upgrade shop ./chart -n shop
# Error: UPGRADE FAILED: another operation (install/upgrade/rollback) is in progress
```

**Fix:**

```bash
# 1. ⭐ roll back to the last GOOD revision (this also clears the failed state)
helm rollback shop 6 -n shop --wait --timeout=5m
helm list -n shop
# shop   shop   8   2026-09-09 15:02:11   deployed   1.1.0     ← ✅

# 2. if rollback also fails, clear the stuck release secret manually
kubectl get secrets -n shop -l owner=helm,name=shop --sort-by=.metadata.creationTimestamp
# sh.helm.release.v1.shop.v7   helm.sh/release.v1   1   15m
kubectl get secret sh.helm.release.v1.shop.v7 -n shop -o jsonpath='{.data.release}' \
  | base64 -d | base64 -d | gunzip | jq .info.status
# "pending-upgrade"           ← ⛔ stuck mid-upgrade
kubectl delete secret sh.helm.release.v1.shop.v7 -n shop
helm list -n shop             # back to revision 6 as deployed

# 3. then investigate WHY the upgrade timed out
helm get manifest shop -n shop --revision=7 | kubectl diff -f - || true
kubectl get pods -n shop -l app.kubernetes.io/instance=shop
kubectl describe pod <pending-pod> -n shop
```

**Prevention:**

```bash
# ⭐ always in CI:
helm upgrade --install shop ./chart -n shop \
  --atomic \                     # auto-rollback on failure
  --timeout 10m \
  --wait \                       # wait for resources to be Ready
  --wait-for-jobs \
  --cleanup-on-fail \
  --reset-then-reuse-values=false \
  --version 1.2.0

# ⛔ never use --reuse-values in CI: it merges the PREVIOUS release's values
#    with your file, so removed keys silently persist
helm get values shop -n shop          # what's actually in effect
helm get values shop -n shop -a       # all values including chart defaults
```

---

### Scenario 17 — DNS is intermittently slow (the 5-second timeout)

**Symptom:** Random 5-second stalls on external HTTP calls from inside pods.

```bash
kubectl exec -n shop deploy/shop-api -- sh -c 'for i in 1 2 3 4 5; do time wget -qO- https://api.stripe.com/ >/dev/null; done' 2>&1
# real 0m0.281s
# real 0m5.284s        ← ⛔ exactly 5 seconds
# real 0m0.279s
```

**Root cause:** the classic **glibc parallel A/AAAA race**. glibc sends the A and AAAA queries from the *same* socket; conntrack sees two packets with the same 5-tuple and drops one as `INVALID`. The resolver waits for the 5-second default timeout.

```bash
kubectl node-shell learn-worker -- dmesg -T | grep -i 'conntrack table full\|INVALID'
kubectl node-shell learn-worker -- conntrack -S | grep -i invalid
# cpu=0 insert=0 insert_failed=0 drop=0 early_drop=0 error=0 search_restart=…
kubectl node-shell learn-worker -- iptables -L -t raw -n | grep -i notrack
```

**Fix — three levels:**

```yaml
# 1. ⭐ single-request-reopen — use a separate socket for A and AAAA
spec:
  dnsConfig:
    options:
      - {name: single-request-reopen}
      - {name: timeout, value: "1"}
      - {name: attempts, value: "2"}
      - {name: ndots, value: "2"}
```

```bash
# 2. ⭐⭐ node-local DNSCache — a DaemonSet caching resolver on every node
kubectl apply -f https://raw.githubusercontent.com/kubernetes/kubernetes/master/cluster/addons/dns/nodelocaldns/nodelocaldns.yaml
# pods then talk to 169.254.20.10 over TCP (no conntrack race) and hit the local cache

# 3. drop the conntrack INVALID rule (a hack, but effective)
kubectl node-shell learn-worker -- iptables -I INPUT -m conntrack --ctstate INVALID -j DROP
```

---

### Scenario 18 — An application can't write to its volume (permissions)

```bash
kubectl logs -n shop deploy/shop-api --tail=20
# java.io.IOException: Permission denied
#   at java.base/java.io.File.createTempFile(File.java:2189)

kubectl exec -n shop deploy/shop-api -- id
# uid=10001(app) gid=10001(app) groups=10001(app)
kubectl exec -n shop deploy/shop-api -- ls -lan /data
# drwxr-xr-x  3  0  0   4096 Sep  9 14:20 .      ← ⛔ owned by root, app is uid 10001
kubectl exec -n shop deploy/shop-api -- touch /data/x
# touch: /data/x: Permission denied
```

**Root cause:** a newly provisioned PV is owned by `root:root` with mode 0755. The container runs as uid 10001 (correctly hardened!) and can't write.

**Fix — `fsGroup`:**

```yaml
spec:
  securityContext:
    runAsUser: 10001
    runAsGroup: 10001
    fsGroup: 10001                      # ⭐ the kubelet chowns/chmods the volume to this GID
    fsGroupChangePolicy: OnRootMismatch # ⭐ skip the recursive chown if it already matches
  containers:
    - name: api
      securityContext: {runAsNonRoot: true, readOnlyRootFilesystem: true}
      volumeMounts:
        - {name: data, mountPath: /data}
        - {name: tmp, mountPath: /tmp}          # ⭐ readOnlyRootFilesystem needs writable dirs
        - {name: cache, mountPath: /app/cache}
  volumes:
    - {name: data, persistentVolumeClaim: {claimName: uploads}}
    - {name: tmp, emptyDir: {}}
    - {name: cache, emptyDir: {}}
```

```bash
kubectl apply -f deploy.yaml && kubectl rollout status deploy/shop-api -n shop
kubectl exec -n shop deploy/shop-api -- ls -lan /data
# drwxrwsr-x  3  0  10001  4096 Sep  9 15:10 .   ← ⭐ group is now 10001 with setgid

# ⚠️ fsGroup on a huge volume (millions of files) makes the pod take MINUTES to start.
#    fsGroupChangePolicy: OnRootMismatch fixes that (v1.23+).
# alternative: an initContainer that fixes it once
#   initContainers:
#     - name: fix-perms
#       image: busybox:1.37
#       command: ["sh","-c","chown -R 10001:10001 /data || true"]
#       securityContext: {runAsUser: 0}
#       volumeMounts: [{name: data, mountPath: /data}]
```

---

### Scenario 19 — etcd is slow; the whole cluster is sluggish

```bash
# 1. confirm it's etcd
kubectl get --raw /metrics | grep -E '^etcd_disk_(wal_fsync|backend_commit)_duration_seconds_bucket' | head
# etcd_disk_wal_fsync_duration_seconds_bucket{le="0.016"}  1842
# etcd_disk_wal_fsync_duration_seconds_bucket{le="0.032"}  2103
# etcd_disk_wal_fsync_duration_seconds_bucket{le="0.064"}  2198
# etcd_disk_wal_fsync_duration_seconds_bucket{le="0.128"}  4821   ← ⛔ a huge jump: fsyncs > 64ms

curl -s 'http://localhost:9090/api/v1/query' --data-urlencode 'query=
  histogram_quantile(0.99, sum(rate(etcd_disk_wal_fsync_duration_seconds_bucket[5m])) by (le))' | jq .
# "0.128"      ← ⛔ p99 WAL fsync of 128ms. Healthy is < 10ms.

# 2. is etcd out of space?
kubectl exec -n kube-system etcd-learn-control-plane -- etcdctl --cacert=… --cert=… --key=… \
  endpoint status --write-table
# DB SIZE: 7.6 GB        ← ⛔ approaching the 8 GB quota
kubectl exec -n kube-system etcd-learn-control-plane -- etcdctl --cacert=… --cert=… --key=… alarm list
# memberID:8e9e… alarm:NOSPACE

# 3. what's eating it?
kubectl get --raw /metrics | grep '^apiserver_storage_objects' | sort -t' ' -k2 -rn | head -10
# apiserver_storage_objects{resource="events"}                       842103    ← ⛔ 842k events
# apiserver_storage_objects{resource="pods"}                          12480
# apiserver_storage_objects{resource="leases.coordination.k8s.io"}     4821
# apiserver_storage_objects{resource="endpointslices.discovery.k8s.io"} 3921

# 4. is a controller hammering it?
kubectl get --raw /metrics | grep '^apiserver_request_total' | grep 'resource="events"' | head
kubectl logs -n kube-system kube-apiserver-learn-control-plane --tail=200 | grep -iE 'took too long|slow'
# "Slow List" … "took 4.2s"
```

**Fix:**

```bash
# A. compact + defragment (the standard maintenance — recovers most of the space)
REV=$(kubectl exec -n kube-system etcd-learn-control-plane -- etcdctl --cacert=… --cert=… --key=… \
      endpoint status --write-out=json | jq '.[0].Status.header.revision')
kubectl exec -n kube-system etcd-learn-control-plane -- etcdctl --cacert=… --cert=… --key=… compact $REV
kubectl exec -n kube-system etcd-learn-control-plane -- etcdctl --cacert=… --cert=… --key=… \
  --command-timeout=600s defrag --cluster
kubectl exec -n kube-system etcd-learn-control-plane -- etcdctl --cacert=… --cert=… --key=… alarm disarm

# B. reduce the event churn
kubectl patch validatingadmissionpolicy …        # (or fix whatever is spamming events)
# lower the event TTL: --event-ttl=30m on the API server
# delete old events now:
kubectl get events -A -o json | jq -r '.items[] | select(.lastTimestamp < (now - 1800 | todate))
  | "\(.metadata.namespace) \(.metadata.name)"' | while read ns e; do kubectl delete event $e -n $ns; done

# C. fix the disk. etcd NEEDS local SSD/NVMe with fsync < 10ms.
#    Never on network storage, never shared with anything else.
fio --rw=write --ioengine=sync --fdatasync=1 --directory=/var/lib/etcd-test \
    --size=22m --bs=2300 --name=etcd-fsync-test
# fdatasync percentiles: 99.00th=[8], 99.90th=[12]     ← ✅ under 10ms
```

**Prevention:** alert on `etcd_disk_wal_fsync_duration_seconds` p99 > 25ms and `etcd_db_total_size_in_bytes` > 6 GB; enable auto-compaction (`--auto-compaction-mode=periodic --auto-compaction-retention=1h`); raise `--quota-backend-bytes` to 8 GB only after fixing the disk.

---

### Scenario 20 — Someone deleted a production Deployment

```bash
kubectl get deploy -n shop-prod
# No resources found in shop-prod namespace.        ← ⛔

# 1. WHO and WHEN — the audit log (this is why you have one)
# AWS CloudTrail / GCP Cloud Audit / your audit webhook
aws cloudtrail lookup-events --lookup-attributes AttributeKey=ResourceName,AttributeValue=shop-api \
  --query 'Events[].CloudTrailEvent' --output text | jq -r '{time:.eventTime, user:.userIdentity.arn, event:.eventName}'
# {"time":"2026-09-09T14:58:12Z","user":"arn:aws:iam::…:user/intern","event":"DeleteDeployment"}

# if you have API server audit logging:
grep '"verb":"delete"' /var/log/kubernetes/audit.log | grep shop-api | jq .

# 2. is the ReplicaSet still there? (⛔ no — the Deployment owned it and it was cascade-deleted)
kubectl get rs -n shop-prod

# 3. ⭐ RECOVERY PATH A — GitOps (this is why GitOps exists)
kubectl get applications -n argocd
argocd app get shop-prod
# Sync Status:  OutOfSync        ← Argo CD sees it immediately
argocd app sync shop-prod --prune
# ✅ restored in ~30 seconds, exactly as declared in Git

# 4. RECOVERY PATH B — from the last-applied annotation of a surviving object
kubectl get rs -n shop-prod -o json | jq -r '.items[]?.metadata.annotations["kubectl.kubernetes.io/last-applied-configuration"]'

# 5. RECOVERY PATH C — from a backup
velero backup get
velero restore create --from-backup shop-prod-2026-09-09 --include-namespaces shop-prod --wait
kubectl get deploy -n shop-prod

# 6. RECOVERY PATH D — from etcd (the nuclear option)
# restore the snapshot taken before 14:58 into a scratch cluster, export the object, re-apply

# 7. RECOVERY PATH E — reconstruct from a live pod (if any survived)
kubectl get pods -n shop-prod -o yaml | kubectl neat   # the pod template is still there
```

**Prevention:**
1. **GitOps** — the cluster is a projection of Git; deletion is self-healing within one sync interval.
2. **RBAC** — `kubectl auth can-i delete deployments -n shop-prod` should be `no` for humans.
3. **Velero** — scheduled backups of the cluster state and the PVs.
4. **A `ValidatingAdmissionPolicy`** blocking DELETE on resources labelled `tier: production` for human users.
5. **Audit logging** shipped off-cluster and immutable.

---

<a name="34-interview-questions-and-answers"></a>
## 34. Interview questions & answers

> 60 questions, grouped. The answers are written the way a senior engineer would say them out loud — with the *why*, not just the *what*.

### Fundamentals

**1. What happens, step by step, when you run `kubectl apply -f deployment.yaml`?**

kubectl reads the file, authenticates to the API server (cert/token/exec plugin), and POSTs to `/apis/apps/v1/namespaces/{ns}/deployments`. If it gets a 409 AlreadyExists, it PATCHes instead. The API server then runs: authentication → authorization (RBAC) → mutating admission (defaults are set, webhooks fire) → schema validation → validating admission (webhooks, ValidatingAdmissionPolicy, PSA, ResourceQuota) → persist to etcd. At that point kubectl returns "created". The Deployment controller, watching via the informer cache, sees the new object and creates a ReplicaSet. The ReplicaSet controller creates Pod objects (no node assigned). The scheduler watches for unscheduled Pods, filters nodes (predicates) and scores the survivors (priorities), then PATCHes `spec.nodeName`. The kubelet on that node, watching for Pods assigned to it, calls the CRI (containerd) to pull the image and create the container, calls the CNI for networking, and the CSI for volumes. It then starts the container and reports status back.

**2. What is the difference between `kubectl apply` and `kubectl create`?**

`create` is imperative: POST, and it fails with AlreadyExists if the object is there. `apply` is declarative: it computes a 3-way merge between your file, the last-applied annotation, and the live object, then PATCHes. `apply` can add, change, or remove fields; `create` can only make something new. There's also `replace`, which PUTs a complete object and requires it to exist — and drops any field you omit.

**3. Client-side vs server-side apply — when does it matter?**

Client-side apply (the default) computes the merge in kubectl and stores the entire manifest in the `kubectl.kubernetes.io/last-applied-configuration` annotation. It inflates object size, can't detect conflicts between managers, and only removes fields that were in the annotation. Server-side apply computes the merge in the API server, tracks per-field ownership in `metadata.managedFields`, and returns a **409 conflict** when two managers claim the same field. SSA matters as soon as more than one thing writes to an object — which in GitOps is always: Argo CD owns the spec, the HPA owns `replicas`, cert-manager owns the certificate annotations. With SSA each owns its fields cleanly.

**4. What is a Pod, and why isn't it just a container?**

A Pod is the smallest schedulable unit: one or more containers that share a **network namespace** (same IP, same localhost, same ports) and can share **volumes** and optionally the **PID namespace**. Containers in a Pod always land on the same node and are created and destroyed together. That's what makes the sidecar pattern possible — a log shipper reading `/var/log/app` from a shared `emptyDir`, or a proxy on `localhost:15001`.

**5. What are the Pod phases, and which one do you actually look at?**

`Pending`, `Running`, `Succeeded`, `Failed`, `Unknown`. But in practice you look at the **STATUS column** of `kubectl get pods`, which is derived from the container states and conditions: `ContainerCreating`, `Init:0/1`, `CrashLoopBackOff`, `ImagePullBackOff`, `CreateContainerConfigError`, `OOMKilled`, `Evicted`, `Terminating`. And you look at **Conditions** (`PodScheduled`, `Initialized`, `ContainersReady`, `Ready`) in `describe`.

**6. What's the difference between `Ready` and `Running`?**

`Running` means the containers were created and at least one is executing. `Ready` means all containers pass their **readiness probes** and all readiness gates are satisfied — and only Ready Pods appear in the Service's EndpointSlice and receive traffic. A Pod can be `Running` with `0/1` Ready for a long time: it's up, but it isn't serving.

**7. Deployment vs StatefulSet vs DaemonSet?**

A **Deployment** manages stateless replicas through ReplicaSets: interchangeable Pods, random names, rolling updates, no stable storage. A **StatefulSet** gives each Pod a stable ordinal name (`db-0`), a stable DNS record via a headless Service, its own PVC from a `volumeClaimTemplate`, and ordered create/scale/update/delete. A **DaemonSet** runs exactly one Pod per node (or per matching node), bypasses the scheduler by setting `nodeName` directly, and is used for node agents: log shippers, metrics exporters, CNI, storage daemons.

**8. What is a ReplicaSet, and should you ever touch one?**

It's the object that maintains a number of identical Pod replicas, created and owned by a Deployment. Its name is `<deployment>-<pod-template-hash>`. You should never edit one directly — the Deployment controller reverts it. But you *read* them constantly: `kubectl get rs -l app=X --sort-by=.metadata.creationTimestamp` shows you the rollout history, because each Deployment revision is a ReplicaSet scaled to zero.

**9. What does `kubectl rollout undo` actually do?**

It finds the previous ReplicaSet (or the one at `--to-revision`), reads its `spec.template`, and PATCHes that template back into the Deployment. That creates a *new* ReplicaSet with the *old* pod template — so revision numbers increase; they don't rewind. It only works within `revisionHistoryLimit` (default 10) because beyond that the old ReplicaSets are garbage-collected.

**10. What is `kubectl rollout restart` and why is it better than deleting pods?**

It PATCHes an annotation `kubectl.kubernetes.io/restartedAt: <now>` into the pod template. That changes the template hash → a new ReplicaSet → a normal rolling update. It respects `maxSurge`/`maxUnavailable`, PDBs, and readiness probes, so there's no downtime. Deleting all the Pods at once removes every endpoint simultaneously.

### Networking

**11. What are the four Service types and how do they work?**

`ClusterIP` allocates a virtual IP from the Service CIDR; kube-proxy (iptables/IPVS) or the CNI's eBPF programs DNAT that IP to one of the Pod IPs. `NodePort` opens the same port on **every** node in 30000–32767 and forwards to the ClusterIP. `LoadBalancer` asks the cloud controller manager to provision an external LB pointing at the NodePorts. `ExternalName` isn't a proxy at all — it's a CNAME record returned by CoreDNS, with no ClusterIP, no endpoints, and no port mapping.

**12. What is a headless Service and when do you need one?**

`clusterIP: None`. No virtual IP is allocated and no proxy rules are created. DNS for the Service name returns **all the Pod IPs**, and if it's the `serviceName` of a StatefulSet, each Pod also gets a stable per-Pod DNS record. You need one for: StatefulSets (stable identity), gRPC (HTTP/2 multiplexes many requests on one connection, so connection-level load balancing pins everything to one Pod — you need client-side balancing), and any client-side service discovery.

**13. A Service returns nothing. Walk me through your debugging.**

First `kubectl get endpointslices -l kubernetes.io/service-name=X`. If it's empty, there are four causes, in order: (1) the Service's `selector` doesn't match any Pod's labels — compare `kubectl get svc X -o jsonpath='{.spec.selector}'` with `kubectl get pods --show-labels`; (2) the Pods exist but aren't **Ready** — a failing readiness probe excludes them; (3) `targetPort` doesn't match the port the container actually listens on — check with `ss -ltn` inside; (4) the Pods are in a different namespace. If the endpoints *are* populated, then it's the network: test pod-to-pod by IP, then by Service name, then cross-namespace, then check NetworkPolicies (a dropped packet **times out**; a refused connection means something answered).

**14. How does DNS work in Kubernetes?**

CoreDNS runs as a Deployment with a `kube-dns` Service at a fixed ClusterIP (usually `10.96.0.10`). Every Pod gets `/etc/resolv.conf` pointing at it with search domains `<ns>.svc.cluster.local`, `svc.cluster.local`, `cluster.local` and `options ndots:5`. A Service is reachable as `<svc>.<ns>.svc.cluster.local`; a StatefulSet Pod as `<pod>.<headless-svc>.<ns>.svc.cluster.local`. The `ndots:5` default is a performance trap: any name with fewer than 5 dots is tried against all three search domains first, so an external call like `api.stripe.com` costs 4 DNS queries. Fix it with `dnsConfig.options.ndots: "2"`, a trailing dot, or node-local DNSCache.

**15. `hostNetwork: true` — what changes?**

The Pod uses the node's network namespace directly: no Pod IP, no CNI, it binds real node ports. Two consequences people forget: you must set `dnsPolicy: ClusterFirstWithHostNet` or it inherits the node's resolver instead of CoreDNS, and you can only run one such Pod per node per port.

**16. Ingress vs Gateway API?**

Ingress is a single, L7-HTTP-only resource where almost all functionality lives in untyped, controller-specific annotations. The Gateway API splits responsibility across `GatewayClass` (the vendor), `Gateway` (the platform team: listeners, ports, TLS, which namespaces may attach) and `HTTPRoute`/`GRPCRoute`/`TCPRoute` (the app team: paths, headers, backends, weights). Features like traffic splitting, header rewriting, and cross-namespace delegation are typed fields rather than annotations. Gateway API is where all the innovation is; Ingress is in maintenance mode.

**17. Why do I get "connection refused" sometimes and "connection timed out" other times?**

Refused means a TCP RST came back — something is reachable but nothing is listening, or the Service exists with zero endpoints. Timed out means packets are being silently **dropped** — a NetworkPolicy, a cloud security group, or a missing route. That single distinction tells you whether to look at the application or at the network policy.

**18. What is a NetworkPolicy and what does it *not* do?**

It's an L3/L4 firewall for Pods, enforced by the CNI. It has **no deny rules** — it's allow-list only: as soon as any policy selects a Pod for a direction (Ingress or Egress), all traffic in that direction is denied except what's explicitly allowed. And critically, it does nothing at all unless your CNI enforces it — `kindnet` and some cloud CNIs don't, so a policy can be applied and completely inert.

### Configuration & secrets

**19. ConfigMap vs Secret — what's the real difference?**

Functionally almost none: both are key-value maps, both mount as files or env vars, both are limited to 1 MiB, both are base64-encoded in the API (a Secret's `data`; a ConfigMap's `data` is plain). The differences are: Secrets get a `type` field with special handling (`kubernetes.io/tls`, `kubernetes.io/dockerconfigjson`), RBAC treats them separately, they can be encrypted at rest with an `EncryptionConfiguration`, they're excluded from `kubectl get all`, and audit logging can redact them. **Neither is encrypted by default.**

**20. I changed a ConfigMap. Why didn't my app see it?**

It depends how it's consumed. `env` and `envFrom` are injected at container start and **never** update. A volume mount of the whole directory updates automatically, but only after the kubelet's sync period plus the cache TTL — typically up to ~60 seconds. A volume mount with `subPath` never updates. And an `immutable: true` ConfigMap can't change at all. Even when the file does update, most apps read config once at startup — so the real answer is to roll the Pods.

**21. How do you make a Deployment restart when a ConfigMap changes?**

Put a checksum of the ConfigMap into the pod template's annotations. In Helm: `checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}`. When the ConfigMap's content changes the hash changes, the pod template changes, and the Deployment does a normal rolling update. Without it, the Deployment sees no change and nothing happens.

**22. How do you actually secure Secrets in Kubernetes?**

Four layers. RBAC: restrict `get secrets`, and remember `view` deliberately excludes Secrets. Encryption at rest: an `EncryptionConfiguration` with `aescbc` or `secretbox`, then rewrite every Secret so it gets re-encrypted — verify by reading the raw etcd key. Better: don't store them in Kubernetes at all — use the External Secrets Operator to sync from AWS Secrets Manager / Vault / GCP Secret Manager, or SOPS+age to encrypt them in Git. And in the app: use the `_FILE` convention so the value never appears in env vars, `describe pod`, or `/proc/<pid>/environ`.

**23. What is `automountServiceAccountToken` and why would you set it to false?**

By default every Pod gets a projected, short-lived, audience-bound ServiceAccount token at `/var/run/secrets/kubernetes.io/serviceaccount/token`. If your app doesn't talk to the Kubernetes API, that token is pure attack surface — an RCE in your app becomes cluster access. Set `automountServiceAccountToken: false` on the ServiceAccount (or per-Pod) and mount a scoped projected token only where it's needed, with a specific `audience` and `expirationSeconds`.

### Scheduling & scaling

**24. Requests vs limits — what does each actually do?**

**Requests** are used by the **scheduler** to decide placement: it sums the requests of everything on a node and compares against `allocatable`. They also determine your QoS class. **Limits** are enforced at **runtime** by the kernel: a CPU limit causes CFS throttling (the container is slowed), a memory limit causes an OOMKill (exit 137). Requests have no runtime enforcement — a container can burst above its CPU request if the node has spare capacity.

**25. Should you set CPU limits? What's the current thinking?**

Increasingly, no. CPU is compressible: exceeding it just throttles you, and throttling is invisible and brutal for latency — a JVM's GC or a Go runtime with many goroutines can burn a whole 100ms CFS quota in a burst and then sit idle, so your *average* looks fine while your p99 triples. Set CPU **requests** (for scheduling and QoS) and no CPU **limit**, or set the limit at 3–4× the request. Memory is different: it's incompressible, so always set both memory requests and limits, ideally equal, which also gives you Guaranteed QoS.

**26. What are the three QoS classes and why do they matter?**

**Guaranteed** — every container has `requests == limits` for both CPU and memory; evicted last, OOM score −997. **Burstable** — at least one request or limit, but not Guaranteed; evicted in the middle. **BestEffort** — nothing set; evicted first, OOM score 1000. When a node hits its eviction thresholds, the kubelet evicts in that order, and within a class by how far each Pod exceeds its memory request.

**27. nodeSelector vs affinity vs taints — when each?**

`nodeSelector` is the simplest hard constraint: label equality. `nodeAffinity` gives you `In/NotIn/Exists/DoesNotExist/Gt/Lt`, hard (`requiredDuringScheduling…`) or soft (`preferredDuring…` with weights). Taints are the opposite direction — the **node repels** Pods, and a toleration only *permits* a Pod to land there; it doesn't attract it. So dedicated nodes need both a taint and a nodeSelector. `podAntiAffinity` spreads replicas relative to each other, and `topologySpreadConstraints` is the modern, cheaper replacement with an explicit `maxSkew`.

**28. A Pod is Pending. How do you diagnose it?**

`kubectl describe pod` and read the `FailedScheduling` event — it tells you exactly which nodes were rejected and why: `Insufficient cpu`, `Insufficient memory`, `didn't match Pod's node affinity/selector`, `had untolerated taint`, `didn't match pod anti-affinity rules`, `didn't match pod topology spread constraints`, `volume node affinity conflict`, `Too many pods`, `were unschedulable` (cordoned). Then cross-check with `kubectl describe node | grep -A6 'Allocated resources'` or `kubectl resource-capacity`. If it's a volume problem the Pod may be Pending for a different reason — check the PVC.

**29. How does an HPA decide how many replicas to run?**

`desiredReplicas = ceil(currentReplicas × currentMetric / targetMetric)`. Three replicas at 140% CPU with a 70% target → `ceil(3 × 2)` = 6. Crucially, **utilization is a percentage of the request, not the limit** — so a container with no CPU request at all can never be autoscaled, which is why you see `<unknown>` in `kubectl get hpa`. The `behavior` block then rate-limits the change: `scaleUp` and `scaleDown` policies with `stabilizationWindowSeconds` prevent flapping.

**30. My HPA shows `<unknown>/70%`. Why?**

Three causes. (1) metrics-server isn't running or is broken — `kubectl top pods` fails, or `kubectl get apiservices | grep metrics` shows `False`. On kind/minikube the classic failure is the kubelet's self-signed cert, fixed with `--kubelet-insecure-tls`. (2) The Deployment has no CPU/memory **requests**, so there's no denominator. (3) You're using a custom metric and the adapter (prometheus-adapter or KEDA) isn't installed or the metric name doesn't exist — check `kubectl get --raw /apis/custom.metrics.k8s.io/v1beta1`.

**31. Can HPA and VPA work together?**

Not on the same metric. An HPA on CPU and a VPA in `Auto` mode will fight: the VPA raises the requests, which lowers the utilization percentage, which makes the HPA scale down. The safe patterns are VPA in `Off` mode (recommendations only) alongside a CPU HPA, or an HPA on a **custom** metric alongside a VPA managing CPU/memory.

**32. What is KEDA and what does it give you that an HPA doesn't?**

Scale to **zero** and 60+ event sources. An HPA needs metrics from running Pods, so it can't scale below `minReplicas: 1`. KEDA polls an external source — RabbitMQ depth, Kafka lag, SQS, Prometheus, a cron schedule — and creates a real HPA under the hood, but it can hold the Deployment at zero replicas and wake it on the first message. The cost is cold start: scheduling, image pull, and app startup, which for a JVM is 30–90 seconds.

**33. What is a PodDisruptionBudget and what does it not protect against?**

It limits **voluntary** disruption: `kubectl drain`, `kubectl evict`, node upgrades, and cluster-autoscaler consolidation. `minAvailable: 2` means the eviction API returns 429 rather than removing a third Pod. It does **nothing** for involuntary disruption — the OOM killer, node resource-pressure eviction, `kubectl delete pod`, or your app crashing. And a PDB where `minAvailable == replicas` makes a node permanently un-drainable.

### Storage

**34. PV vs PVC vs StorageClass?**

A **PersistentVolume** is a real piece of storage, cluster-scoped, either created statically by an admin or dynamically by a provisioner. A **PersistentVolumeClaim** is a namespaced *request* — "10Gi, ReadWriteOnce" — that binds 1:1 to a PV. A **StorageClass** is the menu: it names a provisioner and its parameters, a reclaim policy, a binding mode, and whether expansion is allowed. A PVC that names a StorageClass gets a PV created for it automatically.

**35. What does `volumeBindingMode: WaitForFirstConsumer` do and why does it matter?**

`Immediate` provisions the volume as soon as the PVC is created — before any Pod exists, so the provisioner has to guess the zone. `WaitForFirstConsumer` delays provisioning until a Pod referencing the PVC is actually scheduled, then creates the volume in that Pod's zone. Without it you get the classic failure: the volume lands in `ap-south-1a`, the Pod schedules to a node in `ap-south-1b`, and you see `volume node affinity conflict` forever.

**36. What is the Multi-Attach error?**

A `ReadWriteOnce` volume is already attached to one node and a Pod on another node tries to mount it. It happens when a node goes NotReady and the StatefulSet Pod is rescheduled before the old volume attachment is released. The safe recovery: confirm the node is genuinely dead (not partitioned), `kubectl delete node`, wait for the `VolumeAttachment` to disappear, then let the Pod attach. If the node might still be alive, force-attaching elsewhere means two database processes writing to one disk — unrecoverable corruption. `ReadWriteOncePod` (v1.29+) prevents this at the API level.

**37. RWO means one Pod, right?**

No — **one node**. Two Pods on the same node can both mount a ReadWriteOnce volume, which is exactly the corruption scenario `ReadWriteOncePod` was added to prevent. And RWO doesn't mean single-writer at the filesystem level; it's an attach-level guarantee from the CSI driver.

**38. Can I change a PVC's size or StorageClass?**

You can **grow** it if the StorageClass has `allowVolumeExpansion: true` — patch `spec.resources.requests.storage`. Some filesystems then need a Pod restart (`FileSystemResizePending`). You can never shrink it. `accessModes`, `storageClassName`, and `volumeMode` are immutable — to "change" them you create a new PVC and copy the data with a temporary Pod that mounts both.

**39. What happens to a StatefulSet's PVCs when you delete it or scale it down?**

By default, **nothing** — they're retained, which is how you can delete and recreate a StatefulSet without losing data. Since v1.27 you can control this with `persistentVolumeClaimRetentionPolicy: {whenDeleted: Delete, whenScaled: Delete}`. Note that `volumeClaimTemplates` themselves are immutable — to change them you delete the StatefulSet with `--cascade=orphan` (Pods and PVCs survive) and re-apply.

### Operations

**40. Walk me through draining a node.**

`kubectl cordon <node>` first so nothing new schedules there. Check what's on it and whether PDBs will allow eviction — `kubectl get pdb -A` and look for `ALLOWED DISRUPTIONS: 0`. Scale up critical workloads if needed. Then `kubectl drain <node> --ignore-daemonsets --delete-emptydir-data --timeout=10m`. `--ignore-daemonsets` is mandatory because DaemonSet Pods would be recreated instantly. `--delete-emptydir-data` accepts the loss of scratch data. If it hangs on a PDB, fix the PDB or scale up — don't reach for `--disable-eviction` (which bypasses PDBs) unless it's a genuine emergency. Afterwards, do the maintenance, `kubectl wait --for=condition=Ready node/<node>`, and `kubectl uncordon`.

**41. What's the order for upgrading a cluster?**

etcd backup → control plane (API server, controller-manager, scheduler) → cluster addons (CNI, CoreDNS, kube-proxy, ingress) → kubelets, one node at a time with cordon/drain/upgrade/uncordon → kubectl to within ±1. The skew rules that drive this: kubelets may be up to 2 minor versions **older** than the API server but never newer, and kubectl must be within ±1. Before any of it, scan for deprecated APIs with `pluto`, `kubent`, or `kubectl deprecations` — that's the number one cause of a broken upgrade.

**42. A Pod is in CrashLoopBackOff. What do you do?**

`kubectl logs <pod> --previous` — always first, because the current container may not have written anything yet. Then `kubectl describe pod` for the Last State's exit code and reason, and the Events. Exit 1 tells you to read the stack trace; 137 with reason `OOMKilled` is the memory limit; 126/127 with **empty logs** means the entrypoint doesn't exist or isn't executable; 139 is a segfault in native code. If the logs are empty and the exit code doesn't explain it, override the command with an ephemeral debug container or run the image locally with `docker run --entrypoint sh`. Also check whether a too-aggressive liveness probe is killing a healthy app — `describe pod` will show `Unhealthy` then `Killing` then `BackOff`.

**43. What does exit code 137 mean, and how do you tell the two causes apart?**

137 = 128 + 9 = SIGKILL. Cause one: the container exceeded its memory limit — `lastState.terminated.reason` says `OOMKilled`. Cause two: the graceful shutdown period expired and the kubelet SIGKILLed it — the reason is `Error` and the Events show `Container failed to stop within N seconds`. The first is a sizing or leak problem; the second means your app ignores SIGTERM.

**44. Exit 143?**

128 + 15 = SIGTERM. That's a **normal, graceful** shutdown. Seeing it as a `lastState` reason is usually fine — it means the container received SIGTERM and exited. If it's accompanied by unexpected restarts, look for what's sending SIGTERM: a liveness probe, a rollout, an eviction, or a node drain.

**45. A Pod is stuck in Terminating. Why?**

Three causes. A **finalizer** that nothing is clearing — check `metadata.finalizers` and whether the controller responsible is running. A container that **ignores SIGTERM** and is waiting out `terminationGracePeriodSeconds` — watch `kubectl logs -f` during the grace period. Or a `preStop` hook that's slow or hanging. If the node is NotReady the kubelet can't confirm termination at all, and the Pod stays Terminating until you force-delete it — which for a StatefulSet with an RWO volume is dangerous.

**46. How do you delete a namespace that's stuck Terminating?**

Find what the namespace controller can't list: `kubectl get ns X -o json | jq .status.conditions` will name it, and `kubectl get apiservices | grep -v True` usually reveals a dead aggregated API server. Fix or delete that APIService and the namespace completes on its own. If it's orphan CRs whose controller is gone, delete them, clearing finalizers if needed. The last resort is `kubectl get ns X -o json | jq '.spec.finalizers=[]' | kubectl replace --raw /api/v1/namespaces/X/finalize -f -` — which works but leaks whatever cloud resources the finalizers were meant to clean up.

**47. `kubectl get all` — does it get everything?**

No. It's a hard-coded list: pods, services, daemonsets, deployments, replicasets, statefulsets, HPAs, cronjobs, jobs. It misses ConfigMaps, Secrets, PVCs, Ingresses, NetworkPolicies, PDBs, ServiceAccounts, RBAC, quotas, LimitRanges, EndpointSlices, nodes, namespaces, and every CRD. For a real export, enumerate `kubectl api-resources --namespaced=true --verbs=list -o name` and loop.

**48. How do you debug a distroless or scratch container with no shell?**

`kubectl debug -it <pod> --image=nicolaka/netshoot --target=<container>` adds an **ephemeral container** that shares the target's namespaces — you can reach its `localhost`, read `/proc/1/root/`, and use your own tools. Add `--share-processes` to see its processes, `--profile=netadmin` for tcpdump, `--profile=sysadmin` for privileged. Or `--copy-to=<new-pod>` to make a copy of the Pod with a different image. For node-level work, `kubectl debug node/<node> -it --image=alpine -- chroot /host sh`.

**49. How do you read logs from a container that already crashed and restarted?**

`kubectl logs <pod> --previous`. The current container's logs replaced the old ones in `/var/log/pods/`, but the kubelet keeps the previous terminated container's log until the next restart. It only works if `RESTARTS ≥ 1` and the Pod itself still exists. Beyond that you need a cluster log aggregator, because `kubectl logs` only shows what's currently on that node's disk — about 50 MiB per container with the default rotation.

**50. What is `kubectl explain` and why is it better than the docs?**

It reads the OpenAPI schema from **your live cluster**, so it shows the exact fields your version supports plus every CRD you've installed. `kubectl explain --recursive deployment.spec` is faster and more accurate than any web page, and `kubectl explain scaledobject.spec.triggers` works for KEDA's CRD just as well as for core types.

### Production / architecture

**51. Why does Kubernetes need three probes, and what goes wrong if you only have one?**

`startupProbe` covers slow initialization — until it succeeds, the other two are disabled, so a JVM that takes 4 minutes can't be killed by a 30-second liveness deadline. `livenessProbe` restarts a container that's alive but wedged (a deadlock, a leaked thread pool) — it must check **only the process itself**, never a dependency. `readinessProbe` removes a Pod from the Service endpoints when it can't serve — this one *should* check dependencies. The classic disaster is a liveness probe that pings the database: the DB has a 30-second blip, every Pod fails liveness, every Pod restarts simultaneously, and you turn a partial outage into a full one with a thundering herd on startup.

**52. Why do you need `preStop: sleep 10` for zero-downtime deploys?**

Pod termination and endpoint removal are **asynchronous**. When you delete a Pod, the API server sets `deletionTimestamp` and the EndpointSlice controller updates the endpoints — but kube-proxy on every node, the ingress controller, and any service mesh sidecar each have their own caches and update on their own schedule, typically 1–10 seconds. Meanwhile the kubelet has already sent SIGTERM. A `preStop` sleep gives the endpoint propagation time to finish before the app starts shutting down, so no new requests are routed to a dying Pod. Without it you get a small trickle of 502s on every deploy.

**53. What makes a rolling update zero-downtime?**

Five things together: `maxUnavailable: 0` so you never drop below the desired Ready count; a **readiness probe** that actually reflects the ability to serve; `minReadySeconds` so a Pod that becomes Ready and immediately crashes isn't counted as progress; `preStop` + graceful SIGTERM handling + a `terminationGracePeriodSeconds` longer than your longest request; and enough cluster capacity for `maxSurge`. Miss any one and you get a blip.

**54. GitOps — what is it and what problem does it solve?**

Git is the single source of truth for the desired state, and a controller in the cluster (Argo CD or Flux) continuously reconciles the live state toward it. Four properties: the desired state is **versioned and immutable**, changes go through **pull requests** (so review and audit are automatic), the cluster **pulls** rather than being pushed to (so no CI system ever holds cluster-admin credentials), and **drift is detected and reverted** (so `kubectl edit` at 2am doesn't survive). The operational consequence is that rollback is `git revert` plus a sync — not `argocd app rollback` or `kubectl rollout undo`.

**55. Your Deployment keeps going back to 1 replica. What's happening?**

Something else owns `spec.replicas`. Check `kubectl get deploy X -o yaml --show-managed-fields | grep -B8 f:replicas` — the `manager` field tells you who: `argocd-application-controller` means Git says 1, `kubectl` means someone applied a manifest with `replicas: 1`, an HPA shows up as its own manager. The fix is almost always to **delete `replicas` from the manifest entirely** so the HPA owns it exclusively, or add `ignoreDifferences` for `/spec/replicas` in the Argo CD Application.

**56. How do you do a canary deployment in Kubernetes?**

Natively, with two Deployments behind one Service and label-weighted replicas — crude and manual. Properly, with **Argo Rollouts**: a `Rollout` resource with a `canary` strategy, `steps` that set weights (5% → 20% → 50% → 100%), `pause` durations, and `analysis` templates that query Prometheus for error rate and latency and **automatically abort** if the thresholds are breached. Or with a service mesh / Gateway API `HTTPRoute` `backendRefs` weights, which can route on headers and cookies as well as percentages.

**57. Blue-green vs canary vs rolling?**

**Rolling** gradually replaces Pods — cheapest, but old and new versions serve simultaneously, so your schema and API must be backward-compatible. **Blue-green** runs two complete environments and flips a Service selector — instant rollback, zero version mixing, but 2× the resources and a big-bang cutover. **Canary** sends a small percentage of *real* traffic to the new version, measures it, and proceeds or aborts — the safest for user-facing risk, but it needs traffic-splitting infrastructure and good metrics.

**58. How would you design multi-tenancy in Kubernetes?**

Namespaces per team, with a **ResourceQuota** (total CPU/memory/pods/storage) and a **LimitRange** (per-container defaults and max) in each. RBAC with `RoleBinding`s to the built-in `view`/`edit` ClusterRoles scoped to the namespace — never `ClusterRoleBinding` unless the team genuinely needs cluster scope. A **default-deny NetworkPolicy** plus explicit allows. **Pod Security Admission** `enforce=restricted` on the namespace label. Separate node pools with taints and tolerations for noisy or regulated tenants. And an `AppProject` in Argo CD restricting which repositories and destinations a team may deploy to. For hard isolation, don't share a cluster at all — or use virtual clusters / Kata Containers.

**59. What would you monitor, and what would you alert on?**

Alert on **symptoms, not causes**. The four golden signals at the service level: latency (p99 from a histogram), traffic, errors, saturation. At the platform level: node `Ready`, `kube_pod_container_status_restarts_total` rate, `kube_pod_container_status_last_terminated_reason == "OOMKilled"`, `kube_deployment_status_replicas_available < desired`, `ALLOWED DISRUPTIONS == 0` on PDBs, PVC usage over 80%, the CPU throttling ratio, `etcd_disk_wal_fsync_duration_seconds` p99, API server 5xx and 429 rates, certificate expiry under 21 days, and `kube_cronjob_status_last_schedule_time` older than 2× the interval. Don't alert on CPU utilization — that's a capacity question, not an incident.

**60. A junior engineer ran `kubectl delete pods --all -A`. What happens, and what's your response?**

Every Pod in every namespace gets a `deletionTimestamp`. Anything owned by a controller — Deployments, StatefulSets, DaemonSets — is immediately recreated, so the cluster self-heals within a minute or two, with a brief availability blip and cold caches. Bare Pods and Job Pods are gone for good. StatefulSet Pods with RWO volumes may hit Multi-Attach errors on rescheduling. The response: don't panic — check `kubectl get pods -A -w` and confirm the controllers are recreating; look for anything not coming back (Jobs, bare Pods, PVC binding issues); verify the critical services' endpoints; and afterwards, fix the **root cause**, which is that a human had cluster-admin. The real answers are RBAC (read-only by default, break-glass elevation with audit), GitOps (so state is restorable), and a shell guard on prod contexts.

---

<a name="35-api-versions-reference"></a>
## 35. API versions reference

### 35.1 What's stable in v1.37

| API group/version | Resources | Since |
|---|---|---|
| `v1` (core) | Pod, Service, ConfigMap, Secret, Namespace, Node, PersistentVolume, PersistentVolumeClaim, ServiceAccount, Endpoints, Event, ReplicationController, LimitRange, ResourceQuota | forever |
| `apps/v1` | Deployment, StatefulSet, DaemonSet, ReplicaSet | v1.9 |
| `batch/v1` | Job, CronJob | Job v1.2, CronJob v1.21 |
| `networking.k8s.io/v1` | Ingress, IngressClass, NetworkPolicy | v1.19 |
| `autoscaling/v2` | HorizontalPodAutoscaler | v1.23 |
| `policy/v1` | PodDisruptionBudget, Eviction | v1.21 |
| `rbac.authorization.k8s.io/v1` | Role, ClusterRole, RoleBinding, ClusterRoleBinding | v1.8 |
| `storage.k8s.io/v1` | StorageClass, VolumeAttachment, CSIDriver, CSINode, CSIStorageCapacity | v1.19+ |
| `admissionregistration.k8s.io/v1` | MutatingWebhookConfiguration, ValidatingWebhookConfiguration | v1.16 |
| `apiextensions.k8s.io/v1` | CustomResourceDefinition | v1.16 |
| `apiregistration.k8s.io/v1` | APIService | v1.18 |
| `certificates.k8s.io/v1` | CertificateSigningRequest | v1.19 |
| `coordination.k8s.io/v1` | Lease | v1.14 |
| `discovery.k8s.io/v1` | EndpointSlice | v1.21 |
| `events.k8s.io/v1` | Event | v1.19 |
| `node.k8s.io/v1` | RuntimeClass | v1.20 |
| `scheduling.k8s.io/v1` | PriorityClass | v1.14 |
| `flowcontrol.apiserver.k8s.io/v1` | FlowSchema, PriorityLevelConfiguration | v1.29 |
| `authentication.k8s.io/v1` | TokenReview | v1.6 |
| `authorization.k8s.io/v1` | SubjectAccessReview, SelfSubjectAccessReview, SelfSubjectRulesReview, LocalSubjectAccessReview | v1.6 |
| **`metrics.k8s.io/v1beta1`** | NodeMetrics, PodMetrics | ⭐ **promoted to a first-class API in v1.37** (still `/v1beta1`) |
| `snapshot.storage.k8s.io/v1` | VolumeSnapshot, VolumeSnapshotContent, VolumeSnapshotClass | external-snapshotter v4 |
| `gateway.networking.k8s.io/v1` | Gateway, HTTPRoute, GRPCRoute, GatewayClass, ReferenceGrant, BackendTLSPolicy | Gateway API v1.0 (external) |
| `autoscaling.k8s.io/v1` | VerticalPodAutoscaler | external |
| `keda.sh/v1alpha1` | ScaledObject, ScaledJob | external |
| `argoproj.io/v1alpha1` | Application, Rollout, Workflow, AnalysisTemplate | external |

### 35.2 What's new in v1.35 – v1.37

| Version | Highlight | What it changes for you |
|---|---|---|
| **v1.35** (Dec 2025) | Resilient watch-cache initialization | Faster API server restarts on big clusters |
| **v1.36** (Apr 2026) | Continued DRA maturation | Better GPU/device scheduling |
| **v1.37 "Garhwal"** (26 Aug 2026) | ⭐ **`kubectl get -o kyaml`** | A Kubernetes-native YAML query language — see §6.5 |
| | ⭐ `metrics.k8s.io` promoted | `kubectl top` and the HPA are on a first-class API |
| | DRA device status, taints, NUMA — GA | Fine-grained GPU/device claims |
| | Node declared features — GA | Nodes advertise capabilities as structured fields |
| | **Pod certificates** + ClusterTrustBundles — GA | Short-lived per-Pod X.509 identities |
| | Resilient watch-cache init — GA | |
| | Watch-based route controller reconciliation — beta | Faster networking convergence |

```bash
# check what's enabled on YOUR cluster
kubectl get --raw /apis | jq -r '.groups[] | .name' | sort
kubectl api-versions | sort
kubectl get --raw /metrics | grep '^kubernetes_feature_enabled' | head -40
# kubernetes_feature_enabled{name="KubernetesKYAML",stage="GA"} 1
```

### 35.3 Feature gates you might meet

| Gate | Stage | Effect |
|---|---|---|
| `SidecarContainers` | GA (v1.33) | `restartPolicy: Always` on init containers |
| `ReadWriteOncePod` | GA (v1.29) | The RWOP access mode |
| `PodSchedulingReadiness` | GA (v1.30) | `schedulingGates` — hold a Pod unschedulable until a controller removes the gate |
| `InPlacePodVerticalScaling` | Beta | ⭐ Change CPU/memory **without restarting** the Pod |
| `StatefulSetStartOrdinal` | GA (v1.31) | `spec.ordinals.start` — number from N, not 0 |
| `PodDisruptionBudget` unhealthyPodEvictionPolicy | GA (v1.31) | Evict already-broken Pods |
| `VolumeAttributesClass` | Beta | Modify volume parameters (IOPS) in place |
| `MultipleServiceCIDRs` | GA (v1.31) | Migrate to a new Service CIDR |
| `KubernetesKYAML` | GA (v1.37) | `-o kyaml` |
| `PodCertificateRequest` | GA (v1.37) | Per-Pod certificates |

```bash
# in-place resize — the one people ask about most
kubectl get --raw /metrics | grep InPlacePodVerticalScaling
kubectl patch pod nginx --subresource=resize -p '{"spec":{"containers":[{"name":"nginx","resources":{"requests":{"cpu":"200m"},"limits":{"cpu":"500m"}}}]}}'
kubectl get pod nginx -o jsonpath='{.status.containerStatuses[0].resources}'; echo
```

### 35.4 The API group cheat

```bash
# which group is a resource in? (the #1 cause of RBAC "Forbidden")
kubectl api-resources | grep -wE 'pods|deployments|ingresses|cronjobs|hpa|pdb|netpol|sc|pvc'
# pods                    v1                                  ← the CORE group, written as ""
# deployments    deploy   apps/v1
# cronjobs       cj       batch/v1
# ingresses      ing      networking.k8s.io/v1
# networkpolicies netpol  networking.k8s.io/v1
# horizontalpodautoscalers hpa  autoscaling/v2
# poddisruptionbudgets pdb     policy/v1
# storageclasses sc       storage.k8s.io/v1
# persistentvolumeclaims pvc   v1                              ← also core!

# in a Role, the core group is ""
rules:
  - apiGroups: [""]
    resources: ["pods", "pods/log", "services", "configmaps", "secrets", "persistentvolumeclaims"]
    verbs: ["get","list","watch"]
  - apiGroups: ["apps"]
    resources: ["deployments", "statefulsets", "daemonsets", "replicasets"]
    verbs: ["get","list","watch","update","patch"]
  - apiGroups: ["batch"]
    resources: ["jobs", "cronjobs"]
    verbs: ["*"]
```

---

<a name="36-common-errors-and-what-they-mean"></a>
## 36. Common errors & what they mean

### 36.1 Client-side errors (kubectl never reached the server)

| Error | Cause | Fix |
|---|---|---|
| `The connection to the server localhost:8080 was refused` | **No kubeconfig at all** — kubectl fell back to the default | `export KUBECONFIG=…` or `kubectl config use-context` |
| `The connection to the server 1.2.3.4:6443 was refused` | The API server is down or unreachable | `curl -sk https://…:6443/healthz`; check the control plane |
| `error: You must be logged in to the server (Unauthorized)` | Auth failed: expired token, bad cert, dead exec plugin | Re-run `aws eks update-kubeconfig` / `az aks get-credentials`; `rm -rf ~/.kube/cache/exec` |
| `error: unable to load root certificates: …` | A missing/corrupt CA in the kubeconfig | `kubectl config view --raw \| grep certificate-authority` |
| `x509: certificate has expired or is not yet valid` | Your client cert expired | Re-issue; `openssl x509 -noout -dates` to check |
| `x509: certificate signed by unknown authority` | The CA doesn't match the server's cert | Wrong kubeconfig, or the cluster's CA was rotated |
| `error: no configuration has been provided` | No kubeconfig found | `ls ~/.kube/config`; check `$KUBECONFIG` |
| `error: current-context must be set` | Contexts exist but none is current | `kubectl config use-context <name>` |
| `error: the server doesn't have a resource type "xyz"` | Typo, or the CRD isn't installed | `kubectl api-resources \| grep xyz` |
| `error: unknown shorthand flag: 'l' in -la` | Missing `--` before an exec command | `kubectl exec pod -- ls -la` |
| `error: a container name must be specified` | The Pod has >1 container | `-c <name>` or `--all-containers` |
| `error: expected 'pod', got 'pods'` (in some subcommands) | A singular is required | `kubectl logs pod/x` |
| `Unable to connect to the server: net/http: TLS handshake timeout` | Network/firewall | Check the route to :6443 |
| `Unable to connect to the server: dial tcp: lookup … no such host` | DNS for the API server hostname | `/etc/hosts`, or a private DNS zone |
| `error: resource(s) were provided, but no name was given` | A missing argument | Check the command |
| `error: cannot set a port-forward on the resource type X` | port-forward needs a Pod/Service/Deployment | Use one of those |

### 36.2 Server-side 4xx

| Error | HTTP | Cause | Fix |
|---|---|---|---|
| `Error from server (NotFound)` | 404 | The object doesn't exist | Check the name and the namespace |
| `Error from server (Forbidden)` | 403 | ⭐ **RBAC denied** | `kubectl auth can-i …`; check the Role |
| `Error from server (Unauthorized)` | 401 | Authentication failed | Token/cert |
| `Error from server (AlreadyExists)` | 409 | `create` on an existing object | Use `apply`, or `create … --dry-run=client -o yaml \| kubectl apply -f -` |
| `Error from server (Conflict)` | 409 | ⭐ A `resourceVersion` mismatch, or an SSA field conflict | Re-read and retry; for SSA, `--force-conflicts` or remove the field |
| `Error from server (Invalid)` | 422 | Schema validation failed | Read the message — it names the exact field |
| `Error from server (BadRequest)` | 400 | A malformed request, or an unsupported field selector | Fix the selector/JSON |
| `Error from server (Timeout)` | 504 | The API server or a webhook timed out | Check the webhook; `timeoutSeconds` |
| `Error from server (TooManyRequests)` | 429 | ⭐ **APF throttling**, or a PDB blocked an eviction | Find the hammering client; for evictions, wait or fix the PDB |
| `Error from server (MethodNotSupported)` | 405 | The resource doesn't support that verb | `kubectl api-resources -o wide` |
| `Error from server (InternalError)` | 500 | A bug or an etcd problem | The API server logs |

### 36.3 The messages you must recognise instantly

```bash
# RBAC
# pods is forbidden: User "system:serviceaccount:shop:default" cannot list resource "pods"
#   in API group "" in the namespace "shop"
kubectl auth can-i list pods -n shop --as=system:serviceaccount:shop:default    # no
kubectl create role pod-reader --verb=get,list,watch --resource=pods -n shop
kubectl create rolebinding x --role=pod-reader --serviceaccount=shop:default -n shop

# immutable field
# Deployment.apps "x" is invalid: spec.selector: Invalid value: …: field is immutable
# ⛔ you cannot change a Deployment's selector. Delete and recreate (with downtime),
#    or create a second Deployment with the new selector and shift traffic.
kubectl get deploy x -o jsonpath='{.spec.selector}'; echo
kubectl delete deploy x && kubectl apply -f x-new.yaml

# spec.template.spec.containers[0].image: Required value
kubectl get deploy x -o yaml | grep -A3 containers:

# quota
# pods "x-abc" is forbidden: failed quota: shop-quota: must specify limits.cpu, limits.memory
kubectl describe resourcequota shop-quota -n shop
kubectl get limitrange -n shop

# webhook
# admission webhook "validate.x.com" denied the request: <message>
kubectl get validatingwebhookconfigurations
kubectl logs -n <ns> deploy/<webhook> --tail=50

# PSA
# pods "x" is forbidden: violates PodSecurity "restricted:latest":
#   allowPrivilegeEscalation != false, unrestricted capabilities, runAsNonRoot != true, seccompProfile
kubectl get ns shop -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}'; echo

# the API server is fine but etcd is not
# etcdserver: request timed out
# etcdserver: mvcc: database space exceeded
kubectl exec -n kube-system etcd-… -- etcdctl … alarm list

# scheduling
# 0/3 nodes are available: 3 Insufficient cpu. preemption: …
kubectl describe nodes | grep -A5 'Allocated resources'

# the object changed underneath you
# Operation cannot be fulfilled on deployments.apps "x": the object has been modified;
#   please apply your changes to the latest version and try again
# ✅ just re-run; kubectl re-reads and retries. In a script, wrap in a retry loop.

# SSA conflict
# error: Apply failed with 1 conflict: conflict with "argocd-application-controller" using apps/v1: .spec.replicas
kubectl get deploy x -o yaml --show-managed-fields | grep -B8 'f:replicas'

# too long
# ConfigMap "x" is invalid: data: Too long: must have at most 1048576 bytes

# an annotation is too big
# metadata.annotations: Too long: must have at most 262144 bytes
# ⭐ usually the last-applied-configuration annotation on a huge object → use --server-side
kubectl apply -f x.yaml --server-side --force-conflicts

# the request is too large
# request did not complete: request entity too large
# ⭐ a LIST of a huge collection; use --chunk-size or a label selector
kubectl get pods -A --chunk-size=500 -l app=x
```

### 36.4 Error-handling patterns for scripts

```bash
#!/usr/bin/env bash
set -euo pipefail

# retry a kubectl call (conflicts are transient)
kretry() {
  local n=0 max=${KRETRY_MAX:-5} delay=2
  until "$@"; do
    n=$((n+1)); [ $n -ge $max ] && { echo "⛔ failed after $max attempts: $*"; return 1; }
    echo "⚠️  attempt $n failed, retrying in ${delay}s: $*" >&2
    sleep $delay; delay=$((delay*2))
  done
}
kretry kubectl apply -f deploy.yaml --server-side --force-conflicts

# tolerate "not found"
kubectl get pod x 2>/dev/null || echo "pod x does not exist"
kubectl get pod x --ignore-not-found
kubectl delete pod x --ignore-not-found

# distinguish a permission error from a missing object
if out=$(kubectl get deploy x -n shop 2>&1); then
  echo "found: $out"
elif echo "$out" | grep -q Forbidden; then
  echo "⛔ RBAC: you cannot read deployments in shop"; exit 2
elif echo "$out" | grep -q NotFound; then
  echo "⚠️ not found"; exit 3
else
  echo "⛔ unexpected: $out"; exit 1
fi

# fail loudly if you're on the wrong cluster
CTX=$(kubectl config current-context)
case "$CTX" in *prod*) echo "⛔ refusing to run against $CTX"; exit 1;; esac

# verify the version skew before doing anything
CLIENT=$(kubectl version -o json | jq -r '.clientVersion.minor')
SERVER=$(kubectl version -o json | jq -r '.serverVersion.minor')
if [ $((CLIENT - SERVER)) -gt 1 ] || [ $((SERVER - CLIENT)) -gt 1 ]; then
  echo "⛔ kubectl $CLIENT vs server $SERVER — outside the ±1 skew policy"; exit 1
fi
```

---

<a name="37-global-flags-reference"></a>
## 37. Global flags reference

```bash
kubectl options          # ⭐ prints the global flags
```

| Flag | Short | Default | Meaning |
|---|---|---|---|
| `--namespace` | `-n` | the context's, else `default` | Target namespace |
| `--all-namespaces` | `-A` | false | Every namespace |
| `--output` | `-o` | (table) | yaml/json/wide/name/custom-columns/jsonpath/go-template/kyaml |
| `--selector` | `-l` | | Label selector |
| `--field-selector` | | | Field selector |
| `--show-labels` | | false | Add a LABELS column |
| `--show-kind` | | false | Prefix names with the kind |
| `--sort-by` | | | A jsonpath to sort by (client-side) |
| `--watch` | `-w` | false | Stream changes |
| `--watch-only` | | false | Watch without the initial list |
| `--chunk-size` | | 500 | Paginate list requests; `0` disables |
| `--context` | | the current one | Use a specific context |
| `--cluster` | | | Use a specific cluster entry |
| `--user` | | | Use a specific user entry |
| `--kubeconfig` | | `$KUBECONFIG` / `~/.kube/config` | Path to the config |
| `--server` | `-s` | from the kubeconfig | The API server URL |
| `--token` | | | A bearer token (overrides the kubeconfig) |
| `--certificate-authority` | | | A CA bundle |
| `--client-certificate` | | | A client cert |
| `--client-key` | | | A client key |
| `--insecure-skip-tls-verify` | | false | ⛔ Skip TLS verification |
| `--tls-server-name` | | | Override the SNI name |
| `--as` | | | ⭐ Impersonate a user |
| `--as-group` | | | Impersonate a group |
| `--as-uid` | | | Impersonate a UID |
| `--username` / `--password` | | | Basic auth (deprecated) |
| `--request-timeout` | | `0` (no timeout) | Per-request timeout, e.g. `30s` |
| `--timeout` | | `0` | Command-level timeout (for `wait`, `rollout status`) |
| `--v` | | 0 | Verbosity, 0–10 |
| `--vmodule` | | | Per-file verbosity, e.g. `deployment=8` |
| `--log-flush-frequency` | | 5s | |
| `--match-server-version` | | false | Require the client and server versions to match |
| `--cache-dir` | | `~/.kube/cache` | Where discovery and exec-plugin results are cached |
| `--profile` | | none | `none`/`cpu`/`heap`/`goroutine`/`threadcreate`/`block`/`mutex` |
| `--profile-output` | | `profile.pprof` | Where to write the profile |
| `--warnings-as-errors` | | false | Treat API warnings as failures (great for CI) |
| `--disable-compression` | | false | Don't gzip responses |
| `--validate` | | `strict` | `strict` / `warn` / `false` |
| `--dry-run` | | none | `none` / `client` / `server` |
| `--server-side` | | false | Use server-side apply |
| `--force-conflicts` | | false | Take over conflicting fields in SSA |
| `--field-manager` | | `kubectl` | Name the SSA field manager |
| `--wait` | | true | Wait for the operation to complete |
| `--ignore-not-found` | | false | Treat NotFound as success |
| `--grace-period` | | −1 | Override the deletion grace period |
| `--force` | | false | Immediate deletion (with `--grace-period=0`) |
| `--cascade` | | background | `background`/`foreground`/`orphan` |
| `--raw` | | | Send a raw request to a path |
| `--subresource` | | | Target `status`, `scale`, or `resize` |
| `--no-headers` | | false | Suppress the header row |
| `--server-print` | | true | Include the server's default columns |
| `--show-managed-fields` | | false | Include `managedFields` in the output |
| `--allow-missing-template-keys` | | true | Ignore missing keys in go-template/jsonpath |
| `--template` | | | A template file |

```bash
# the ones that will save you the most time
kubectl get pods -A -o wide --show-labels --sort-by=.metadata.creationTimestamp | tail
kubectl apply -f x.yaml --dry-run=server --validate=strict --warnings-as-errors
kubectl get deploy x -o yaml --show-managed-fields
kubectl wait --for=condition=Ready pod -l app=x --timeout=120s
kubectl get pods -v=8 2>&1 | head -30
kubectl delete pod x --grace-period=0 --force --wait=false
kubectl patch deploy x --subresource=scale -p '{"spec":{"replicas":5}}'
kubectl get --raw /healthz
kubectl auth can-i --list --as=jane@example.com
```

---

<a name="38-command-index"></a>
## 38. Command index

```bash
kubectl --help | sed -n '/Basic Commands/,/^Flags/p'
```

### Basic (beginner)

| Command | What it does |
|---|---|
| `create` | Create a resource from a file or stdin |
| `expose` | Create a Service for an existing resource |
| `run` | Run a Pod (or a Deployment/Job via `--restart`) |
| `set` | Set a feature on an object (`image`, `env`, `volume`, `resources`, `sa`, `selector`, `subject`) |

### Deploy

| Command | What it does |
|---|---|
| `apply` | Apply a configuration (create or update) |
| `patch` | Update fields of a resource |
| `replace` | Replace a resource by filename or stdin |
| `wait` | ⭐ Wait for a condition |
| `kustomize` | Build kustomize output (without applying) |
| `edit` | Edit a resource in `$EDITOR` |
| `scale` | Set a new replica count |
| `autoscale` | Create an HPA |
| `apply view-last-applied` / `diff` | Compare desired vs live |

### Management

| Command | What it does |
|---|---|
| `annotate` | Add/update/remove annotations |
| `api-resources` | List the resource types |
| `api-versions` | List the API group/versions |
| `cordon` / `uncordon` | Mark a node unschedulable / schedulable |
| `drain` | Evict everything from a node |
| `taint` | Add/remove node taints |
| `label` | Add/update/remove labels |
| `cluster-info` | Cluster endpoint info; `dump` for everything |
| `describe` | Show details of a resource |
| `get` | List resources |
| `delete` | Delete resources |
| `logs` | Print container logs |
| `explain` | ⭐ The resource schema |
| `rollout` | Manage rollouts (`status`, `history`, `undo`, `restart`, `pause`, `resume`) |
| `top` | Resource usage (`nodes`, `pods`) |

### Debugging

| Command | What it does |
|---|---|
| `debug` | ⭐ Ephemeral containers, Pod copies, node shells |
| `exec` | Run a command in a container |
| `attach` | Attach to a running container's stdio |
| `port-forward` | Forward local ports to a Pod/Service |
| `proxy` | Run a local proxy to the API server |
| `cp` | Copy files to/from a container |
| `auth` | `can-i`, `reconcile`, `whoami` |
| `events` | ⭐ A dedicated events command (`kubectl events -A --for pod/x`) |
| `diff` | Compare a file to the live object |

### Advanced

| Command | What it does |
|---|---|
| `alpha` / `beta` | Preview commands |
| `certificate` | Approve/deny/renew CSRs |
| `completion` | Shell completion scripts |
| `config` | Modify the kubeconfig |
| `cp` | Copy files |
| `create` | Create resources |
| `drain` | Drain a node |
| `get --raw` | A raw API request |
| `kustomize` | Build kustomize |
| `options` | Print global flags |
| `plugin` | List plugins, flag collisions |
| `version` | Client and server versions |

### Subcommands worth knowing

```bash
kubectl config …
#   view · get-contexts · current-context · use-context · set-context ·
#   set-cluster · set-credentials · set · unset · delete-context ·
#   delete-cluster · delete-user · rename-context · get-clusters · get-users

kubectl rollout …
#   status · history · undo · restart · pause · resume

kubectl set …
#   image · env · volume · resources · serviceaccount · selector · subject

kubectl auth …
#   can-i [--list] · whoami · reconcile

kubectl certificate …
#   approve · deny · renew

kubectl events …                    # ⭐ newer than `get events`
#   -A · --for pod/x · --types Warning · --watch

kubectl explain …
#   <resource> · <resource>.<field> · --recursive · --api-version=

kubectl api-resources …
#   --namespaced=false · --api-group=apps · --verbs=list · -o wide · --cached

kubectl plugin …
#   list

kubectl kustomize ./overlays/prod > rendered.yaml
kubectl diff -f rendered.yaml
kubectl apply -f rendered.yaml --server-side --prune -l app.kubernetes.io/part-of=shop
```

---

<a name="39-cheat-cards"></a>
## 39. Cheat cards

### Card 1 — "The app is broken"

```bash
NS=shop; APP=shop-api
kubectl get pods -n $NS -l app=$APP -o wide                          # STATUS + READY
kubectl describe pod -n $NS -l app=$APP | grep -A15 Events           # what happened
kubectl logs -n $NS -l app=$APP --tail=100 --previous                # the crash
kubectl get events -n $NS --field-selector type=Warning --sort-by=.lastTimestamp | tail
kubectl get endpointslices -n $NS -l kubernetes.io/service-name=$APP  # is it routable?
kubectl rollout status deploy/$APP -n $NS
kubectl rollout undo deploy/$APP -n $NS                              # put out the fire first
```

### Card 2 — "The cluster is broken"

```bash
kubectl get --raw='/readyz?verbose' | grep -v '\[+\]'
kubectl get nodes -o wide
kubectl get pods -A | grep -vE 'Running|Completed'
kubectl get apiservices | grep -v True
kubectl top nodes
kubectl get events -A --field-selector type=Warning --sort-by=.lastTimestamp | tail -30
kubectl describe nodes | grep -A5 'Allocated resources'
kubectl get lease -n kube-node-lease -o custom-columns='NODE:.metadata.name,RENEWED:.spec.renewTime'
```

### Card 3 — "I need to deploy"

```bash
kubectl diff -f ./k8s/ -R                                            # what will change?
kubectl apply -f ./k8s/ -R --dry-run=server --validate=strict        # will it be accepted?
kubectl apply -f ./k8s/ -R --server-side --force-conflicts --field-manager=me
kubectl rollout status deploy/shop-api -n shop --timeout=300s        # did it work?
kubectl get endpointslices -n shop -l kubernetes.io/service-name=shop-api
curl -s https://api.shop.example.com/health                          # is it healthy?
kubectl annotate deploy/shop-api -n shop kubernetes.io/change-cause="v1.2.0 fix N+1" --overwrite
# it broke?
kubectl rollout undo deploy/shop-api -n shop
```

### Card 4 — "I need one value out of the cluster"

```bash
kubectl get pods -o name                                             # pod/x, pod/y
kubectl get pods -o jsonpath='{.items[0].status.podIP}'; echo
kubectl get pods -o jsonpath='{.items[?(@.metadata.labels.app=="x")].metadata.name}'; echo
kubectl get pods -o custom-columns='NAME:.metadata.name,NODE:.spec.nodeName'
kubectl get pods -o json | jq -r '.items[].metadata.name'
kubectl get pods -o kyaml='{.items[*].{name: .metadata.name, node: .spec.nodeName}}'   # v1.37+
kubectl get deploy x -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
kubectl get secret x -o jsonpath='{.data.password}' | base64 -d; echo
kubectl get svc x -o jsonpath='{.spec.ports[0].nodePort}'; echo
kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}'; echo
kubectl get ns x -o jsonpath='{.metadata.labels}'; echo
kubectl get pod x -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}'; echo
kubectl get pod x -o jsonpath='{.status.containerStatuses[0].lastState.terminated.exitCode}'; echo
kubectl config current-context
kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}'; echo
```

### Card 5 — "I need to get inside"

```bash
kubectl exec -it <pod> -n <ns> -- sh
kubectl exec -it <pod> -n <ns> -c <container> -- bash
kubectl debug -it <pod> --image=nicolaka/netshoot --target=<c> --profile=netadmin -- bash
kubectl debug node/<node> -it --image=alpine:3.22 -- chroot /host sh
kubectl port-forward -n <ns> svc/<svc> 8080:80
kubectl proxy --port=8001
kubectl cp <ns>/<pod>:/path ./local
kubectl cp ./local <ns>/<pod>:/path
kubectl run tmp --image=nicolaka/netshoot --rm -it --restart=Never -n <ns> -- bash
cat x.sql | kubectl exec -i <pod> -n <ns> -- psql -U u -d d        # ⭐ -i, not -it
```

### Card 6 — "I need to change one thing, fast"

```bash
kubectl set image deploy/<d> <c>=<image>
kubectl scale deploy/<d> --replicas=N
kubectl rollout restart deploy/<d>
kubectl rollout undo deploy/<d>
kubectl label <resource> <name> k=v --overwrite
kubectl annotate <resource> <name> k=v --overwrite
kubectl taint nodes <node> k=v:NoSchedule
kubectl taint nodes <node> k=v:NoSchedule-
kubectl cordon <node> / kubectl uncordon <node>
kubectl patch <resource> <name> --type=merge -p '{"spec":{…}}'
kubectl patch <resource> <name> --type=json -p='[{"op":"replace","path":"/spec/x","value":y}]'
kubectl create cm x --from-literal=k=v --dry-run=client -o yaml | kubectl apply -f -
kubectl create job run-$(date +%s) --from=cronjob/<cj>
kubectl delete pod <pod>                       # the controller recreates it
kubectl exec -it <pod> -- sh -c 'kill -HUP 1'  # reload without restarting
```

### Card 7 — YAML snippets you'll paste constantly

```yaml
# ⭐ the production Deployment skeleton
apiVersion: apps/v1
kind: Deployment
metadata:
  name: shop-api
  namespace: shop
  labels: {app: shop-api}
spec:
  # replicas: 3            ← OMIT if an HPA manages this
  revisionHistoryLimit: 5
  strategy:
    type: RollingUpdate
    rollingUpdate: {maxSurge: 1, maxUnavailable: 0}
  minReadySeconds: 15
  progressDeadlineSeconds: 600
  selector: {matchLabels: {app: shop-api}}      # ⭐ minimal & immutable
  template:
    metadata:
      labels: {app: shop-api}
      annotations:
        checksum/config: "<sha256 of the configmap>"
        prometheus.io/scrape: "true"
        prometheus.io/port: "9090"
    spec:
      serviceAccountName: shop-api
      automountServiceAccountToken: false
      securityContext:
        runAsNonRoot: true
        runAsUser: 10001
        fsGroup: 10001
        fsGroupChangePolicy: OnRootMismatch
        seccompProfile: {type: RuntimeDefault}
      terminationGracePeriodSeconds: 45
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: ScheduleAnyway
          labelSelector: {matchLabels: {app: shop-api}}
      containers:
        - name: api
          image: ghcr.io/3558bhk/shop-api@sha256:9f2a1b3c…    # ⭐ pinned by digest
          imagePullPolicy: IfNotPresent
          ports:
            - {name: http, containerPort: 8080}
            - {name: metrics, containerPort: 9090}
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities: {drop: ["ALL"]}
          resources:
            requests: {cpu: 250m, memory: 1Gi}
            limits:   {memory: 1Gi}              # ⭐ memory only; no CPU limit
          envFrom: [{configMapRef: {name: app-config}}, {secretRef: {name: db-creds}}]
          env:
            - name: POD_NAME
              valueFrom: {fieldRef: {fieldPath: metadata.name}}
            - name: NODE_NAME
              valueFrom: {fieldRef: {fieldPath: spec.nodeName}}
          startupProbe:
            httpGet: {path: /actuator/health/liveness, port: http}
            failureThreshold: 30
            periodSeconds: 5
          readinessProbe:
            httpGet: {path: /actuator/health/readiness, port: http}
            periodSeconds: 10
            timeoutSeconds: 3
            failureThreshold: 3
          livenessProbe:
            httpGet: {path: /actuator/health/liveness, port: http}
            periodSeconds: 20
            timeoutSeconds: 5
            failureThreshold: 3
          lifecycle:
            preStop: {exec: {command: ["sh","-c","sleep 10"]}}
          volumeMounts:
            - {name: tmp, mountPath: /tmp}
      volumes:
        - {name: tmp, emptyDir: {sizeLimit: 256Mi}}
---
apiVersion: v1
kind: Service
metadata: {name: shop-api, namespace: shop, labels: {app: shop-api}}
spec:
  selector: {app: shop-api}
  ports:
    - {name: http, port: 80, targetPort: http}
    - {name: metrics, port: 9090, targetPort: metrics}
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata: {name: shop-api, namespace: shop}
spec:
  scaleTargetRef: {apiVersion: apps/v1, kind: Deployment, name: shop-api}
  minReplicas: 3
  maxReplicas: 20
  metrics:
    - type: Resource
      resource: {name: cpu, target: {type: Utilization, averageUtilization: 70}}
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 0
      policies: [{type: Percent, value: 100, periodSeconds: 15}]
    scaleDown:
      stabilizationWindowSeconds: 300
      policies: [{type: Percent, value: 10, periodSeconds: 60}]
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata: {name: shop-api, namespace: shop}
spec:
  minAvailable: 2
  selector: {matchLabels: {app: shop-api}}
  unhealthyPodEvictionPolicy: IfHealthyBudget
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: default-deny-ingress, namespace: shop}
spec:
  podSelector: {}
  policyTypes: [Ingress]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: allow-shop-api, namespace: shop}
spec:
  podSelector: {matchLabels: {app: shop-api}}
  policyTypes: [Ingress]
  ingress:
    - from: [{namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: ingress-nginx}}}]
      ports: [{protocol: TCP, port: 8080}]
    - from: [{namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: monitoring}},
              podSelector: {matchLabels: {app.kubernetes.io/name: prometheus}}}]
      ports: [{protocol: TCP, port: 9090}]
```

### Card 8 — The label conventions

```yaml
# ⭐ the recommended labels (kubernetes.io/docs/concepts/overview/working-with-objects/common-labels)
metadata:
  labels:
    app.kubernetes.io/name: shop-api             # the application name
    app.kubernetes.io/instance: shop-api-prod    # a unique instance
    app.kubernetes.io/version: "1.2.0"           # the current version
    app.kubernetes.io/component: api             # api | web | worker | database | cache
    app.kubernetes.io/part-of: shop              # the parent application
    app.kubernetes.io/managed-by: helm           # helm | kustomize | argocd | kubectl
    # and your own
    team: platform
    env: prod
    tier: backend
    cost-center: cc-1234
```

```bash
# ⚠️ label rules
# - 63 characters max, alphanumeric with - _ .
# - must start and end alphanumeric
# - prefix optional: example.com/my-label
# - reserved prefixes: kubernetes.io/ and k8s.io/
# - kubernetes.io/metadata.name is AUTO-ADDED to every namespace (v1.21+)
# - ⭐ labels are the ONLY thing selectors can use; annotations can hold anything
kubectl label ns shop kubernetes.io/metadata.name=shop   # already there
kubectl get ns shop -o jsonpath='{.metadata.labels}'; echo
```

---

<a name="40-the-ten-minute-daily-checklist"></a>
## 40. The ten-minute daily checklist

Run this every morning. Save it as `~/bin/k-morning` and `chmod +x` it.

```bash
#!/usr/bin/env bash
# k-morning — the daily cluster check
set -uo pipefail
CYAN=$'\033[36m'; RED=$'\033[31m'; GRN=$'\033[32m'; YLW=$'\033[33m'; RST=$'\033[0m'
warn() { printf '%s%s%s\n' "$YLW" "$*" "$RST"; }
bad()  { printf '%s%s%s\n' "$RED" "$*" "$RST"; }
ok()   { printf '%s%s%s\n' "$GRN" "$*" "$RST"; }
hdr()  { printf '\n%s── %s ──%s\n' "$CYAN" "$*" "$RST"; }

hdr "CONTEXT"
echo "cluster : $(kubectl config current-context)"
echo "user    : $(kubectl auth whoami -o jsonpath='{.status.userInfo.username}' 2>/dev/null || echo unknown)"
kubectl version -o json 2>/dev/null | jq -r '"client  : \(.clientVersion.gitVersion)\nserver  : \(.serverVersion.gitVersion)"'

hdr "CONTROL PLANE"
kubectl get --raw='/readyz' >/dev/null 2>&1 && ok "  API server ready" || bad "  ⛔ API server NOT ready"
BROKEN=$(kubectl get apiservices --no-headers 2>/dev/null | grep -vc ' True' || true)
[ "$BROKEN" -gt 0 ] && bad "  ⛔ $BROKEN APIService(s) unavailable:" && kubectl get apiservices | grep -v True || ok "  all APIServices available"

hdr "NODES"
kubectl get nodes -o custom-columns=\
'NAME:.metadata.name,STATUS:.status.conditions[-1].type,VERSION:.status.nodeInfo.kubeletVersion,CPU:.status.allocatable.cpu,MEM:.status.allocatable.memory,AGE:.metadata.creationTimestamp'
NOTREADY=$(kubectl get nodes --no-headers | grep -vc ' Ready' || true)
[ "$NOTREADY" -gt 0 ] && bad "  ⛔ $NOTREADY node(s) not Ready" || ok "  all nodes Ready"
kubectl top nodes 2>/dev/null || warn "  (metrics-server unavailable)"

hdr "UNHEALTHY PODS"
BADPODS=$(kubectl get pods -A --no-headers | grep -vE 'Running|Completed' | wc -l)
if [ "$BADPODS" -gt 0 ]; then
  bad "  ⛔ $BADPODS pod(s) not Running/Completed:"
  kubectl get pods -A --no-headers | grep -vE 'Running|Completed' | head -20
else ok "  all pods healthy"; fi

hdr "RESTART LEADERBOARD (last 24h)"
kubectl get pods -A -o json | jq -r '.items[] | .metadata.namespace as $ns | .metadata.name as $p |
  (.status.containerStatuses // [])[] | select(.restartCount>0) |
  [(.restartCount|tostring), "\($ns)/\($p)", (.lastState.terminated.reason // "-")] | @tsv' 2>/dev/null \
  | sort -rn | head -10 || echo "  none"

hdr "OOMKILLED"
kubectl get pods -A -o json | jq -r '.items[] | .metadata.namespace as $ns | .metadata.name as $p |
  (.status.containerStatuses // [])[] | select(.lastState.terminated.reason=="OOMKilled") |
  "  ⛔ \($ns)/\($p) container=\(.name) restarts=\(.restartCount)"' 2>/dev/null || echo "  none"

hdr "RECENT WARNINGS (last 1h)"
kubectl get events -A --field-selector type=Warning --sort-by=.lastTimestamp \
  -o custom-columns='TIME:.lastTimestamp,NS:.metadata.namespace,REASON:.reason,OBJ:.involvedObject.name,COUNT:.count' 2>/dev/null | tail -15

hdr "WORKLOAD READINESS"
kubectl get deploy -A -o json | jq -r '.items[] |
  select((.status.readyReplicas // 0) < (.spec.replicas // 0)) |
  "  ⛔ \(.metadata.namespace)/\(.metadata.name)  \(.status.readyReplicas // 0)/\(.spec.replicas)"' 2>/dev/null || echo "  all deployments ready"
kubectl get sts -A -o json | jq -r '.items[] |
  select((.status.readyReplicas // 0) < (.spec.replicas // 0)) |
  "  ⛔ \(.metadata.namespace)/\(.metadata.name)  \(.status.readyReplicas // 0)/\(.spec.replicas)"' 2>/dev/null
kubectl get ds -A -o json | jq -r '.items[] |
  select((.status.numberReady // 0) < (.status.desiredNumberScheduled // 0)) |
  "  ⛔ \(.metadata.namespace)/\(.metadata.name)  \(.status.numberReady // 0)/\(.status.desiredNumberScheduled)"' 2>/dev/null

hdr "STUCK ROLLOUTS"
kubectl get deploy -A -o json | jq -r '.items[] |
  (.status.conditions[]? | select(.type=="Progressing" and .status=="False") |
   "  ⛔ \(.reason): \(.message)")' 2>/dev/null || echo "  none"

hdr "PDBs THAT WOULD BLOCK A DRAIN"
kubectl get pdb -A -o json | jq -r '.items[] | select(.status.disruptionsAllowed==0) |
  "  ⚠️ \(.metadata.namespace)/\(.metadata.name)  allowedDisruptions=0"' 2>/dev/null || echo "  none"

hdr "PENDING PVCs / FAILED JOBS"
kubectl get pvc -A --field-selector=status.phase=Pending 2>/dev/null || true
kubectl get jobs -A -o json | jq -r '.items[] | select((.status.failed // 0) > 0 and (.status.succeeded == null)) |
  "  ⛔ \(.metadata.namespace)/\(.metadata.name)  failed=\(.status.failed)"' 2>/dev/null || echo "  none"

hdr "MISSED CRONJOBS"
kubectl get cronjobs -A -o json | jq -r '.items[] | select(.spec.suspend != true) |
  [.metadata.namespace + "/" + .metadata.name, .spec.schedule, (.status.lastScheduleTime // "NEVER")] | @tsv' 2>/dev/null \
  | while IFS=$'\t' read -r name sched last; do
      [ "$last" = "NEVER" ] && bad "  ⛔ $name  $sched  NEVER RAN" && continue
      age=$(( ($(date +%s) - $(date -d "$last" +%s 2>/dev/null || echo 0)) / 3600 ))
      [ "$age" -gt 36 ] && warn "  ⚠️ $name  $sched  last ran ${age}h ago"
    done

hdr "CAPACITY (requests vs allocatable)"
kubectl describe nodes | awk '
  /^Name:/ {node=$2}
  /^  cpu /  {printf "  %-24s cpu     %s\n", node, $2 " " $3}
  /^  memory / {printf "  %-24s memory  %s\n", node, $2 " " $3}'

hdr "DISK (top PVCs)"
kubectl df-pv 2>/dev/null | head -12 || kubectl get pvc -A -o custom-columns=\
'NS:.metadata.namespace,NAME:.metadata.name,SIZE:.spec.resources.requests.storage,STATUS:.status.phase'

hdr "SECURITY QUICK SCAN"
PRIV=$(kubectl get pods -A -o json | jq -r '[.items[] | select(.spec.containers[].securityContext.privileged==true)] | length')
[ "$PRIV" -gt 0 ] && warn "  ⚠️ $PRIV privileged pod(s)"
LATEST=$(kubectl get pods -A -o json | jq -r '[.items[] | .spec.containers[].image | select(endswith(":latest"))] | length')
[ "$LATEST" -gt 0 ] && warn "  ⚠️ $LATEST container(s) using :latest"
NOLIMIT=$(kubectl get pods -A -o json | jq -r '[.items[] | .spec.containers[] | select((.resources.limits // {}) == {})] | length')
[ "$NOLIMIT" -gt 0 ] && warn "  ⚠️ $NOLIMIT container(s) with no limits"
NOREQ=$(kubectl get pods -A -o json | jq -r '[.items[] | .spec.containers[] | select((.resources.requests // {}) == {})] | length')
[ "$NOREQ" -gt 0 ] && warn "  ⚠️ $NOREQ container(s) with no requests"

hdr "CERTIFICATES EXPIRING < 30 DAYS"
kubectl get certificates -A -o json 2>/dev/null | jq -r '.items[] |
  . as $c | (.status.conditions[]? | select(.type=="Ready") |
  "\($c.metadata.namespace)/\($c.metadata.name)  ready=\(.status)")' || echo "  (cert-manager not installed)"
kubectl get secret -A --field-selector type=kubernetes.io/tls -o json 2>/dev/null | jq -r '.items[] |
  "\(.metadata.namespace)/\(.metadata.name)"' | head -5 | while read s; do
    ns=${s%%/*}; n=${s##*/}
    exp=$(kubectl get secret "$n" -n "$ns" -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
    [ -n "$exp" ] && echo "  $s  expires $exp"
  done

hdr "GITOPS DRIFT"
if command -v argocd >/dev/null 2>&1; then
  argocd app list -o wide 2>/dev/null | awk 'NR==1 || $4!="Synced" || $5!="Healthy"' | head -15
else
  kubectl get applications -n argocd -o custom-columns=\
'NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status' 2>/dev/null \
    | awk 'NR==1 || $2!="Synced" || $3!="Healthy"' || echo "  (Argo CD not installed)"
fi

hdr "DONE"
echo "  snapshot saved to ~/cluster-snapshots/$(date +%F).txt"
mkdir -p ~/cluster-snapshots
```

```bash
mkdir -p ~/bin && cp k-morning.sh ~/bin/k-morning && chmod +x ~/bin/k-morning
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc && source ~/.bashrc
k-morning | tee ~/cluster-snapshots/$(date +%F).txt
```

### The weekly checklist (15 minutes)

```bash
# 1. deprecated APIs in your repos and in the cluster
kubectl deprecations --k8s-version v1.38 ./k8s/
pluto detect-all-in-cluster

# 2. image vulnerabilities
kubectl get vulnerabilityreports -A -o json 2>/dev/null | jq -r '.items[] |
  .report.vulnerabilities[]? | select(.severity=="CRITICAL") |
  "\(.vulnerabilityID)  \(.title)"' | sort -u | head -20

# 3. resource waste (OpenCost)
kubectl cost -n shop --show-all
kubectl cost --by-namespace --show-efficiency

# 4. RBAC creep
kubectl get clusterrolebindings -o json | jq -r '.items[] |
  select(.roleRef.name=="cluster-admin") | .subjects[]? | "\(.kind)/\(.name)"'

# 5. orphaned objects
kubectl get rs -A -o json | jq -r '.items[] | select(.metadata.ownerReferences==null and (.spec.replicas // 0) > 0) | "\(.metadata.namespace)/\(.metadata.name)"'
kubectl get pv -o json | jq -r '.items[] | select(.status.phase=="Released") | "\(.metadata.name)  \(.spec.capacity.storage)"'
kubectl get pvc -A -o json | jq -r '.items[] | select(.status.phase=="Lost") | "\(.metadata.namespace)/\(.metadata.name)"'
kubectl get ns -o json | jq -r '.items[] | select(.status.phase=="Terminating") | .metadata.name'

# 6. etcd health
kubectl exec -n kube-system etcd-learn-control-plane -- etcdctl --cacert=… --cert=… --key=… endpoint status --write-table

# 7. node rotation (Karpenter/CA)
kubectl get nodepools -o custom-columns='NAME:.metadata.name,NODES:.status.resources.cpu' 2>/dev/null
kubectl get nodes -o custom-columns='NAME:.metadata.name,AGE:.metadata.creationTimestamp' | sort -k2

# 8. backup verification
velero backup get
velero schedule get
velero restore create --from-backup <latest> --dry-run 2>/dev/null || true
```

---

## Where to go next

| You want | Read |
|---|---|
| The conceptual foundation | [01-KUBERNETES-GUIDE.md](./01-KUBERNETES-GUIDE.md) |
| Your first Pod | [Project 1](./04-PROJECT-1-first-pod.md) |
| Deployments, Services, rollouts | [Project 2](./05-PROJECT-2-deployment-service.md) |
| ConfigMaps and Secrets | [Project 3](./06-PROJECT-3-config-secrets.md) |
| Jobs and CronJobs | [Project 4](./07-PROJECT-4-jobs-cronjobs-cli.md) |
| Storage and StatefulSets | [Project 5](./08-PROJECT-5-storage-statefulset.md) |
| Ingress, TLS, Gateway API | [Project 6](./09-PROJECT-6-ingress-tls.md) |
| Prometheus, Grafana, Loki, tracing | [Project 7](./10-PROJECT-7-observability.md) |
| Real applications (React, Java, Python, Go) | [Projects 8–12](./11-PROJECT-8-react-frontend.md) |
| Databases on Kubernetes | [Project 13](./16-PROJECT-13-databases.md) |
| Helm and GitOps | [Project 14](./17-PROJECT-14-helm-gitops.md) |
| The whole thing end to end | [02-CAPSTONE-END-TO-END.md](./02-CAPSTONE-END-TO-END.md) |
| Everything on one page | [03-CHEATSHEET.md](./03-CHEATSHEET.md) |
| An hour-by-hour plan | [00-ONE-DAY-MASTER-PLAN.md](./00-ONE-DAY-MASTER-PLAN.md) |

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish_Kumar_Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn: https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260
🔗 GitHub: https://github.com/3558Bhk

*Built for engineers who learn by breaking things on purpose.*

</div>
