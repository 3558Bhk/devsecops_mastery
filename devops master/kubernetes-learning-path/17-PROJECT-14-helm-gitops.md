# ⎈ Project 14 — Helm Charts & GitOps with Argo CD

> **Time:** 2.5 hours · **Prereq:** [Project 10](13-PROJECT-10-react-java-fullstack.md) (Kustomize) and any one runtime project
>
> - **Part A — Helm.** Turn the raw YAML from the previous projects into a reusable, versioned, parameterised chart. Learn the templating language, hooks, library charts, `helm test`, and how to publish to GHCR.
> - **Part B — GitOps with Argo CD.** One Git repository becomes the source of truth. Applications sync themselves, drift is detected and reverted, rollbacks are `git revert`, and the App-of-Apps pattern manages dozens of apps.
>
> **Why both?** Helm answers "how do I package and parameterise this?". GitOps answers "who is allowed to change it, and how do I know what's running?". You need both.

---

## 14.0 The problem this project solves

By Project 13 you have ~40 YAML files across six databases and three runtimes. Deploying means:

```bash
kubectl apply -f k8s/base/namespace.yaml
kubectl apply -f k8s/base/db.yaml
kubectl wait --for=condition=complete job/shop-migrate …
kubectl apply -k k8s/overlays/prod
kubectl annotate deploy/shop-api kubernetes.io/change-cause=… --overwrite
kubectl set image deploy/shop-api api=ghcr.io/…:1.2.3
# …and none of this is recorded anywhere.
```

Three questions you cannot answer:

| Question | With `kubectl apply` | With Helm + GitOps |
|---|---|---|
| What is running in prod right now? | `kubectl get` (a snapshot, no history) | `git log` + `argocd app get` |
| Who changed it, and why? | Nobody knows | Every change is a commit with a message |
| How do I deploy the same thing to staging? | Copy-paste and edit | `-f values-staging.yaml` |
| How do I roll back? | `kubectl rollout undo` (one workload only) | `git revert` — the whole release |
| Did someone change it by hand? | No idea | Argo CD reports **OutOfSync** and can auto-fix it |
| How do I install this on a customer's cluster? | Send them 40 files | `helm install shop ./chart` |

---

# PART A — HELM

## 14.1 What Helm actually is

**Helm is a template engine plus a release tracker.** That's it. It is not a package manager in the apt sense — there's no dependency resolution across releases, no atomic multi-release transactions.

```
   chart/            ← the templates (like a class)
   values.yaml       ← the parameters (like constructor arguments)
        │
        │  helm template / helm install
        ▼
   rendered YAML     ← plain Kubernetes manifests
        │
        │  applied to the cluster
        ▼
   RELEASE           ← a named, versioned instance tracked in a Secret
```

**The release record lives in a Secret:**

```bash
helm install shop ./chart -n shop --create-namespace
kubectl get secrets -n shop -l owner=helm
# NAME                            TYPE                 DATA   AGE
# sh.helm.release.v1.shop.v1      helm.sh/release.v1   1      2m
```

That Secret contains the *entire* rendered manifest, the values used, and the chart. It's how `helm upgrade`, `helm rollback` and `helm get manifest` work.

```bash
helm history shop -n shop
# REVISION  UPDATED                   STATUS      CHART         APP VERSION  DESCRIPTION
# 1         Mon Sep 9 18:02:11 2026   superseded  shop-0.1.0    1.0.0        Install complete
# 2         Mon Sep 9 18:14:02 2026   deployed    shop-0.2.0    1.1.0        Upgrade complete

helm get values  shop -n shop        # the values YOU passed (not the defaults)
helm get manifest shop -n shop       # the rendered YAML currently applied
helm get all     shop -n shop        # everything
```

## 14.2 Install and set up

```bash
# Helm
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version
# version.BuildInfo{Version:"v3.17.0", GitCommit:"…", GoVersion:"go1.23.4"}

# ⭐ shell completion — do this now, you'll thank yourself
helm completion bash > /etc/bash_completion.d/helm      # or ~/.bash_completion
source /etc/bash_completion.d/helm
# helm ins<TAB>  →  helm install
# helm get <TAB><TAB> → all hooks manifest notes values

# kubectl plugins that make Helm work better
kubectl krew install diff      # helm diff without Helm plugins
helm plugin install https://github.com/databus23/helm-diff
helm plugin install https://github.com/hypnoglow/helm-s3       # if you use S3 chart repos
helm plugin list
```

**kubectl skew:** Helm v3.17 supports Kubernetes 1.31–1.37. Your `kubectl` must be within ±1 minor of the cluster.

## 14.3 Scaffold the chart

```bash
mkdir -p ~/k8s-learn/p14 && cd ~/k8s-learn/p14
helm create shop
tree shop -a
```

```
shop
├── .helmignore              # patterns excluded from the packaged chart
├── Chart.yaml               # metadata: name, version, appVersion, dependencies
├── values.yaml              # ⭐ the default parameters
├── charts/                  # packaged dependency charts land here
└── templates/
    ├── NOTES.txt            # printed after install/upgrade
    ├── _helpers.tpl         # reusable template definitions
    ├── deployment.yaml
    ├── service.yaml
    ├── ingress.yaml
    ├── serviceaccount.yaml
    ├── hpa.yaml
    ├── tests/
    │   └── test-connection.yaml
    └── …
```

**Delete most of it** and build a chart that reflects the real application from the previous projects:

```bash
rm -rf shop/templates/*
mkdir -p shop/templates/{api,ui,db,jobs,monitoring,security}
```

### `Chart.yaml`

```yaml
apiVersion: v2                        # ⭐ v2 = Helm 3. v1 = Helm 2, incompatible.
name: shop
description: |
  The shop platform: React SPA frontend, Spring Boot API, PostgreSQL,
  with Ingress, NetworkPolicies, autoscaling and monitoring.
type: application                     # application | library

# ── ⭐ THE TWO VERSIONS — everyone gets this wrong ──
version: 0.4.2          # THE CHART version. Bump when you change templates OR values.
                        # SemVer. This is what `helm upgrade --version` refers to.
appVersion: "1.4.0"     # THE APPLICATION version. The default image tag.
                        # Bump when the application code changes.

kubeVersion: ">=1.31.0-0"             # refuse to install on older clusters
keywords: [shop, ecommerce, spring-boot, react, postgresql]
home: https://github.com/3558Bhk/shop
sources:
  - https://github.com/3558Bhk/shop
icon: https://raw.githubusercontent.com/3558Bhk/shop/main/docs/icon.png

maintainers:
  - name: Harish Kumar Brahmandam
    email: harish@example.com
    url: https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260

annotations:
  category: Ecommerce
  licenses: Apache-2.0
  artifacthub.io/license: Apache-2.0
  artifacthub.io/changes: |
    - kind: added
      description: Support for KEDA ScaledObject on the API
    - kind: changed
      description: Default Postgres image bumped to 17-alpine
    - kind: fixed
      description: preStop sleep now respects terminationGracePeriodSeconds
  artifacthub.io/signKey: |
    fingerprint: C8D9E0F1A2B3C4D5E6F7081920A1B2C3D4E5F607
    url: https://github.com/3558Bhk/shop/releases
```

> 🔑 **`version` vs `appVersion`.** `version` is the *chart's* release number — Helm uses it for upgrade ordering and rollback. `appVersion` is metadata and the conventional default for the image tag. If you change only a template (say, add a label), bump `version` but not `appVersion`. If you ship new application code, bump both.

### `values.yaml` — the default parameters

```yaml
# ─────────────────────────────────────────────────────────────
# Global values — shared across subcharts
# ─────────────────────────────────────────────────────────────
global:
  imageRegistry: ghcr.io
  imageRepository: 3558bhk
  imagePullSecrets: []
  storageClass: ""              # "" = the cluster default
  environment: dev              # dev | staging | prod
  domain: shop.local
  tls:
    enabled: false
    issuer: letsencrypt-staging
  labels: {}

# ─────────────────────────────────────────────────────────────
# Common defaults applied to every workload
# ─────────────────────────────────────────────────────────────
nameOverride: ""
fullnameOverride: ""

imagePullPolicy: IfNotPresent

podSecurityContext:
  runAsNonRoot: true
  seccompProfile:
    type: RuntimeDefault

containerSecurityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop: ["ALL"]
  privileged: false

# ⭐ a single place to toggle the whole security story
security:
  networkPolicies:
    enabled: true
    defaultDeny: true
  podDisruptionBudgets:
    enabled: true
  podSecurityStandards: baseline
  secrets:
    # external-secrets | sops | plaintext | existing
    provider: plaintext

# ─────────────────────────────────────────────────────────────
# API — Spring Boot backend
# ─────────────────────────────────────────────────────────────
api:
  enabled: true
  name: api
  replicaCount: 3

  image:
    repository: shop-api          # → ghcr.io/3558bhk/shop-api
    tag: ""                       # "" → .Chart.AppVersion
    digest: ""                    # ⭐ pin by digest in prod: "sha256:abc…"
    pullPolicy: ""                # "" → .Values.imagePullPolicy

  containerPort: 8080

  # ── Spring Boot config → ConfigMap ──
  config:
    SPRING_PROFILES_ACTIVE: prod
    SPRING_JPA_HIBERNATE_DDL_AUTO: validate
    SPRING_JPA_OPEN_IN_VIEW: "false"
    SPRING_FLYWAY_ENABLED: "true"
    SERVER_SHUTDOWN: graceful
    SERVER_TOMCAT_THREADS_MAX: "150"
    LOG_LEVEL_APP: INFO
    MANAGEMENT_METRICS_TAGS_APPLICATION: shop-api

  # ── JVM flags → a separate ConfigMap so they can be tuned alone ──
  jvmOpts: >-
    -XX:MaxRAMPercentage=68.0
    -XX:InitialRAMPercentage=50.0
    -XX:+UseG1GC
    -XX:MaxGCPauseMillis=100
    -XX:+ExitOnOutOfMemoryError
    -XX:+HeapDumpOnOutOfMemoryError
    -XX:HeapDumpPath=/tmp/dumps

  # ── ⭐ PROBES: a structured block, not raw YAML ──
  startupProbe:
    enabled: true
    path: /actuator/health/liveness
    periodSeconds: 5
    failureThreshold: 48          # 4 minutes for a JVM cold start
    timeoutSeconds: 3
  readinessProbe:
    enabled: true
    path: /actuator/health/readiness
    periodSeconds: 10
    failureThreshold: 3
    timeoutSeconds: 3
  livenessProbe:
    enabled: true
    path: /actuator/health/liveness
    periodSeconds: 20
    failureThreshold: 3
    timeoutSeconds: 5

  # ── graceful shutdown: three numbers that MUST add up ──
  shutdown:
    preStopSleepSeconds: 10
    terminationGracePeriodSeconds: 60
    # invariant: preStopSleep + springGracefulShutdown <= gracePeriod
    springGracefulShutdownSeconds: 25

  resources:
    requests: {cpu: 500m, memory: 1Gi, ephemeral-storage: 512Mi}
    limits:   {cpu: "2",  memory: 1536Mi, ephemeral-storage: 2Gi}

  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0           # ⭐ never drop capacity during a rollout

  autoscaling:
    enabled: true
    minReplicas: 3
    maxReplicas: 20
    targetCPUUtilizationPercentage: 70
    targetMemoryUtilizationPercentage: null
    behavior:
      scaleUp:
        stabilizationWindowSeconds: 0
        policies:
          - {type: Percent, value: 100, periodSeconds: 30}
        selectPolicy: Max
      scaleDown:
        stabilizationWindowSeconds: 600
        policies:
          - {type: Percent, value: 25, periodSeconds: 60}
        selectPolicy: Min

  pdb:
    enabled: true
    maxUnavailable: 1

  topologySpread:
    enabled: true
    maxSkew: 1
    hostnamePolicy: DoNotSchedule
    zonePolicy: ScheduleAnyway

  serviceAccount:
    create: true
    name: ""
    annotations: {}               # eks.amazonaws.com/role-arn: …
    automountToken: false

  service:
    type: ClusterIP
    port: 8080
    annotations: {}

  extraEnv: []
  extraEnvFrom: []
  extraVolumes: []
  extraVolumeMounts: []
  initContainers: []
  sidecars: []
  nodeSelector: {}
  tolerations: []
  affinity: {}
  podAnnotations: {}
  podLabels: {}
  lifecycleHooks: {}

  # ⭐ runtime config injection
  runtimeConfig:
    enabled: false                # for the /env.js pattern from Project 8

# ─────────────────────────────────────────────────────────────
# UI — React SPA on nginx
# ─────────────────────────────────────────────────────────────
ui:
  enabled: true
  name: ui
  replicaCount: 3
  image:
    repository: shop-ui
    tag: ""
    digest: ""
  containerPort: 8080
  config:
    apiUrl: /api                  # ⭐ relative → same origin → no CORS
  nginx:
    clientMaxBodySize: 5m
    gzip: true
    cacheControl:
      indexHtml: "no-store, no-cache, must-revalidate"
      assets: "public, max-age=31536000, immutable"
  readinessProbe: {enabled: true, path: /healthz, periodSeconds: 5}
  livenessProbe:  {enabled: true, path: /healthz, periodSeconds: 20}
  resources:
    requests: {cpu: 25m, memory: 32Mi}
    limits:   {cpu: 200m, memory: 96Mi}
  autoscaling:
    enabled: true
    minReplicas: 3
    maxReplicas: 20
    targetCPUUtilizationPercentage: 80
  pdb: {enabled: true, minAvailable: 2}

# ─────────────────────────────────────────────────────────────
# Database — PostgreSQL StatefulSet
# ─────────────────────────────────────────────────────────────
database:
  enabled: true
  # ⭐ in production, set this false and use an external DB or an operator
  internal: true
  name: db
  replicaCount: 1
  image:
    repository: postgres          # → docker.io/library/postgres (see the registry note)
    registry: docker.io
    repositoryPath: library/postgres
    tag: 17-alpine
  containerPort: 5432
  auth:
    # ⭐ NEVER put a real password here. Use existingSecret.
    existingSecret: ""            # name of a Secret with keys: username, password, database
    username: shop
    database: app
    password: ""                  # dev only — the template warns if this is set in prod
  persistence:
    enabled: true
    size: 10Gi
    storageClass: ""
    accessModes: [ReadWriteOnce]
    annotations: {}               # keep the PVC when the release is deleted:
                                  #   "helm.sh/resource-policy": keep
  resources:
    requests: {cpu: 500m, memory: 1Gi}
    limits:   {cpu: "2",   memory: 4Gi}
  pdb: {enabled: true, minAvailable: 1}
  backup:
    enabled: false
    schedule: "0 2 * * *"
    timeZone: Asia/Kolkata
    s3:
      bucket: ""
      prefix: postgres
    retention:
      daily: 7
      weekly: 4
      monthly: 6

# external database (when database.internal = false)
externalDatabase:
  host: ""
  port: 5432
  existingSecret: ""
  usernameKey: username
  passwordKey: password
  databaseKey: database
  sslMode: require

# ─────────────────────────────────────────────────────────────
# Migrations — a Job that runs before the API
# ─────────────────────────────────────────────────────────────
migrations:
  enabled: true
  # ⭐ pre-upgrade hook, run once, deleted before the next one
  hook:
    weight: "-5"
    deletePolicy: before-hook-creation
  backoffLimit: 0                 # ⭐ never auto-retry a half-applied migration
  timeoutSeconds: 900
  resources:
    requests: {cpu: 250m, memory: 512Mi}
    limits:   {cpu: "1",   memory: 1Gi}

# ─────────────────────────────────────────────────────────────
# Ingress
# ─────────────────────────────────────────────────────────────
ingress:
  enabled: true
  className: nginx
  # ⭐ TWO Ingress objects on one host — because annotations are per-Ingress
  ui:
    host: ""                      # "" → .Values.global.domain
    path: /
    pathType: Prefix
    annotations: {}
  api:
    host: ""
    path: /api(/|$)(.*)
    pathType: ImplementationSpecific
    rewriteTarget: /$2
    annotations:
      nginx.ingress.kubernetes.io/proxy-body-size: 10m
      nginx.ingress.kubernetes.io/limit-rps: "100"
  tls:
    enabled: false
    secretName: shop-tls
    issuer: ""                    # "" → .Values.global.tls.issuer
  extraHosts: []

# ─────────────────────────────────────────────────────────────
# Observability
# ─────────────────────────────────────────────────────────────
monitoring:
  serviceMonitor:
    enabled: false                # true requires the Prometheus Operator CRDs
    namespace: monitoring
    labels: {release: kps}
    interval: 15s
    scrapeTimeout: 10s
  rules:
    enabled: false
    namespace: monitoring
    labels: {release: kps}
  dashboards:
    enabled: false
    labels: {grafana_dashboard: "1"}

# ─────────────────────────────────────────────────────────────
# Tests — run with `helm test`
# ─────────────────────────────────────────────────────────────
tests:
  enabled: true
  image:
    repository: curlimages/curl
    registry: docker.io
    repositoryPath: library/curlimages/curl
    tag: 8.10.1

# ─────────────────────────────────────────────────────────────
# ⭐ Values schema validation — see values.schema.json
# ─────────────────────────────────────────────────────────────
```

### `values.schema.json` — reject bad values *before* they reach the cluster

```json
{
  "$schema": "https://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["api", "ui", "database"],
  "properties": {
    "global": {
      "type": "object",
      "properties": {
        "environment": {"type": "string", "enum": ["dev", "staging", "prod"]},
        "domain": {"type": "string", "minLength": 3}
      }
    },
    "api": {
      "type": "object",
      "required": ["replicaCount", "resources"],
      "properties": {
        "enabled": {"type": "boolean"},
        "replicaCount": {"type": "integer", "minimum": 0, "maximum": 200},
        "containerPort": {"type": "integer", "minimum": 1, "maximum": 65535},
        "image": {
          "type": "object",
          "properties": {
            "repository": {"type": "string", "minLength": 1},
            "tag": {"type": "string"},
            "digest": {"type": "string", "pattern": "^(sha256:[a-f0-9]{64})?$"}
          }
        },
        "resources": {"$ref": "#/definitions/resources"},
        "shutdown": {
          "type": "object",
          "properties": {
            "preStopSleepSeconds": {"type": "integer", "minimum": 0, "maximum": 120},
            "terminationGracePeriodSeconds": {"type": "integer", "minimum": 1, "maximum": 3600},
            "springGracefulShutdownSeconds": {"type": "integer", "minimum": 0}
          }
        },
        "autoscaling": {
          "type": "object",
          "properties": {
            "minReplicas": {"type": "integer", "minimum": 1},
            "maxReplicas": {"type": "integer", "minimum": 1},
            "targetCPUUtilizationPercentage": {"type": ["integer", "null"], "minimum": 1, "maximum": 100}
          }
        }
      },
      "allOf": [
        {
          "if": {"properties": {"autoscaling": {"properties": {"enabled": {"const": true}}}}},
          "then": {"properties": {"replicaCount": {"const": 0}},
                   "errorMessage": "replicaCount must be 0 when autoscaling is enabled"}
        }
      ]
    },
    "database": {
      "type": "object",
      "properties": {
        "internal": {"type": "boolean"},
        "replicaCount": {"type": "integer", "minimum": 1, "maximum": 7},
        "auth": {
          "type": "object",
          "properties": {
            "password": {"type": "string"},
            "existingSecret": {"type": "string"}
          }
        },
        "persistence": {
          "type": "object",
          "properties": {"size": {"type": "string", "pattern": "^[0-9]+(\\.[0-9]+)?(Ki|Mi|Gi|Ti)$"}}
        }
      }
    }
  },
  "definitions": {
    "resources": {
      "type": "object",
      "required": ["requests"],
      "properties": {
        "requests": {"$ref": "#/definitions/resourceList"},
        "limits": {"$ref": "#/definitions/resourceList"}
      }
    },
    "resourceList": {
      "type": "object",
      "required": ["cpu", "memory"],
      "properties": {
        "cpu": {"type": ["string", "number"]},
        "memory": {"type": "string", "pattern": "^[0-9]+(\\.[0-9]+)?(Ki|Mi|Gi|Ti)$"}
      }
    }
  }
}
```

```bash
# this now fails BEFORE anything touches the cluster
helm install shop ./shop --set api.replicaCount=-1
# Error: values don't meet the schema requirements:
#   - api.replicaCount: must be greater than or equal to 0

helm install shop ./shop --set database.persistence.size=big
# Error: … database.persistence.size: does not match pattern '^[0-9]+(\.[0-9]+)?(Ki|Mi|Gi|Ti)$'
```

> 🔑 **This is the single highest-leverage thing you can add to a chart.** A typo in `resources.limits.memory` that produces `memory: 1G` instead of `1Gi` gets silently accepted by Kubernetes (it means 1 byte × 10⁹) and your Pod OOMKills instantly. The schema catches it at `helm install` time.

## 14.4 `templates/_helpers.tpl` — the reusable functions

```gotemplate
{{/*
─────────────────────────────────────────────────────────────
NAMING
─────────────────────────────────────────────────────────────
*/}}

{{/* Expand the chart name, respecting nameOverride (63 char limit). */}}
{{- define "shop.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
The fully qualified release name. Prepend the release name unless
fullnameOverride is set, or the release name already contains the chart name.
*/}}
{{- define "shop.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/* Chart name + version, for the helm.sh/chart label. */}}
{{- define "shop.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Per-component names: shop.api.fullname → "shop-api" */}}
{{- define "shop.api.fullname" -}}
{{- printf "%s-%s" (include "shop.fullname" .) .Values.api.name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- define "shop.ui.fullname" -}}
{{- printf "%s-%s" (include "shop.fullname" .) .Values.ui.name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- define "shop.db.fullname" -}}
{{- printf "%s-%s" (include "shop.fullname" .Values.database.name) | trunc 63 | trimSuffix "-" }}
{{- end }}


{{/*
─────────────────────────────────────────────────────────────
LABELS  — the recommended Kubernetes set
https://kubernetes.io/docs/concepts/overview/working-with-objects/common-labels/
─────────────────────────────────────────────────────────────
*/}}
{{- define "shop.labels" -}}
helm.sh/chart: {{ include "shop.chart" . }}
{{ include "shop.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: {{ include "shop.fullname" . }}
{{- with .Values.global.environment }}
app.kubernetes.io/environment: {{ . }}
{{- end }}
{{- with .Values.global.labels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Selector labels — a SUBSET of the above, and they must NEVER change.
⚠️ Adding a label here after a release exists makes every Deployment's
   spec.selector immutable-change → the upgrade FAILS. Keep this minimal.
*/}}
{{- define "shop.selectorLabels" -}}
app.kubernetes.io/name: {{ include "shop.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/* Per-component selector labels. */}}
{{- define "shop.api.selectorLabels" -}}
{{ include "shop.selectorLabels" . }}
app.kubernetes.io/component: api
{{- end }}
{{- define "shop.api.labels" -}}
{{ include "shop.labels" . }}
app.kubernetes.io/component: api
{{- end }}

{{- define "shop.ui.selectorLabels" -}}
{{ include "shop.selectorLabels" . }}
app.kubernetes.io/component: ui
{{- end }}
{{- define "shop.ui.labels" -}}
{{ include "shop.labels" . }}
app.kubernetes.io/component: ui
{{- end }}

{{- define "shop.db.selectorLabels" -}}
{{ include "shop.selectorLabels" . }}
app.kubernetes.io/component: database
{{- end }}


{{/*
─────────────────────────────────────────────────────────────
IMAGES — one function so digest pinning works everywhere
─────────────────────────────────────────────────────────────
Usage:  image: {{ include "shop.image" (dict "ctx" $ "component" .Values.api.image "global" .Values.global) }}
*/}}
{{- define "shop.image" -}}
{{- $ctx       := .ctx -}}
{{- $img       := .component -}}
{{- $global    := .global | default dict -}}
{{- $registry  := $img.registry | default $global.imageRegistry | default "ghcr.io" -}}
{{- $repo      := $img.repository -}}
{{- $path      := $img.repositoryPath | default "" -}}
{{- $full      := ternary (printf "%s/%s/%s" $registry $repo $path) (printf "%s/%s" $registry $repo) (ne $path "") -}}
{{- if $img.digest -}}
{{- printf "%s@%s" $full $img.digest -}}
{{- else -}}
{{- $tag := $img.tag | default $ctx.Chart.AppVersion -}}
{{- printf "%s:%s" $full $tag -}}
{{- end -}}
{{- end -}}

{{/* The imagePullPolicy: default to Always for :latest, IfNotPresent otherwise. */}}
{{- define "shop.imagePullPolicy" -}}
{{- $img := .component -}}
{{- if $img.pullPolicy -}}
{{- $img.pullPolicy -}}
{{- else if or (eq ($img.tag | default .ctx.Chart.AppVersion) "latest") (ne ($img.digest | default "") "") -}}
{{- "Always" -}}
{{- else -}}
{{- .ctx.Values.imagePullPolicy | default "IfNotPresent" -}}
{{- end -}}
{{- end -}}


{{/*
─────────────────────────────────────────────────────────────
SERVICE ACCOUNT
─────────────────────────────────────────────────────────────
*/}}
{{- define "shop.api.serviceAccountName" -}}
{{- if .Values.api.serviceAccount.create }}
{{- default (include "shop.api.fullname" .) .Values.api.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.api.serviceAccount.name }}
{{- end }}
{{- end }}


{{/*
─────────────────────────────────────────────────────────────
DATABASE — resolve internal vs external into one set of env vars
─────────────────────────────────────────────────────────────
*/}}
{{- define "shop.db.host" -}}
{{- if .Values.database.internal }}
{{- printf "%s.%s.svc.cluster.local" (include "shop.fullname" .) .Release.Namespace }}
{{- else }}
{{- required "externalDatabase.host is required when database.internal=false" .Values.externalDatabase.host }}
{{- end }}
{{- end }}

{{- define "shop.db.port" -}}
{{- if .Values.database.internal }}{{ .Values.database.containerPort }}
{{- else }}{{ .Values.externalDatabase.port | default 5432 }}{{- end }}
{{- end }}

{{- define "shop.db.secretName" -}}
{{- if .Values.database.internal }}
{{- .Values.database.auth.existingSecret | default (printf "%s-creds" (include "shop.fullname" .)) }}
{{- else }}
{{- required "externalDatabase.existingSecret is required when database.internal=false" .Values.externalDatabase.existingSecret }}
{{- end }}
{{- end }}

{{- define "shop.db.jdbcUrl" -}}
{{- printf "jdbc:postgresql://%s:%v/%s" (include "shop.db.host" .) (include "shop.db.port" .) (.Values.database.auth.database | default "app") }}
{{- end }}


{{/*
─────────────────────────────────────────────────────────────
CHECKSUMS — ⭐ config changes must trigger a rollout
A Deployment's Pod template only changes if the template changes.
Editing a ConfigMap does NOT roll the Pods. This annotation makes it.
─────────────────────────────────────────────────────────────
*/}}
{{- define "shop.api.configChecksums" -}}
checksum/config: {{ include (print $.Template.BasePath "/api/configmap.yaml") . | sha256sum }}
checksum/secret: {{ include (print $.Template.BasePath "/db/secret.yaml") . | sha256sum }}
{{- end }}


{{/*
─────────────────────────────────────────────────────────────
VALIDATION — fail the install with a useful message
─────────────────────────────────────────────────────────────
*/}}
{{- define "shop.validate" -}}

{{- if eq (toString .Values.global.environment) "prod" -}}

  {{- if .Values.database.internal }}
    {{- fail "database.internal=true is not allowed when global.environment=prod. Use an operator (CloudNativePG) or externalDatabase." }}
  {{- end }}

  {{- if and .Values.database.auth.password (not .Values.database.auth.existingSecret) }}
    {{- fail "database.auth.password must not be set in prod. Use database.auth.existingSecret." }}
  {{- end }}

  {{- if not .Values.ingress.tls.enabled }}
    {{- fail "ingress.tls.enabled must be true when global.environment=prod." }}
  {{- end }}

  {{- range $name, $img := dict "api" .Values.api.image "ui" .Values.ui.image }}
    {{- if and (eq (toString $img.tag) "latest") (eq (toString $img.digest) "") }}
      {{- fail (printf "%s.image.tag=latest is not allowed in prod. Pin a version or a digest." $name) }}
    {{- end }}
  {{- end }}

  {{- if lt (int .Values.api.replicaCount) 2 }}
    {{- fail "api.replicaCount must be >= 2 in prod." }}
  {{- end }}

  {{- if not (hasKey .Values.api.resources "limits") }}
    {{- fail "api.resources.limits is required in prod." }}
  {{- end }}

{{- end -}}

{{/* the shutdown invariant, in every environment */}}
{{- with .Values.api.shutdown }}
  {{- $needed := add (int .preStopSleepSeconds) (int .springGracefulShutdownSeconds) }}
  {{- if lt (int .terminationGracePeriodSeconds) $needed }}
    {{- fail (printf "api.shutdown: preStopSleep (%d) + springGracefulShutdown (%d) = %d exceeds terminationGracePeriodSeconds (%d). The Pod will be SIGKILLed mid-drain."
        (int .preStopSleepSeconds) (int .springGracefulShutdownSeconds) $needed (int .terminationGracePeriodSeconds)) }}
  {{- end }}
{{- end }}

{{- end -}}
```

**Invoke the validation once, from the top of every template:**

```gotemplate
{{- include "shop.validate" . -}}
```

```bash
helm install shop ./shop --set global.environment=prod
# Error: execution error at (shop/templates/api/deployment.yaml:2:4):
#   database.internal=true is not allowed when global.environment=prod.
#   Use an operator (CloudNativePG) or externalDatabase.
```

**That error message saves someone a 3 a.m. incident.** Compare it to what you get without validation: a Pod that starts, connects to an empty in-cluster database, and silently serves no data.

## 14.5 `templates/api/deployment.yaml` — the real thing

```gotemplate
{{- include "shop.validate" . -}}
{{- if .Values.api.enabled -}}
{{- $img := include "shop.image" (dict "ctx" $ "component" .Values.api.image "global" .Values.global) -}}
{{- $pull := include "shop.imagePullPolicy" (dict "ctx" $ "component" .Values.api.image) -}}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "shop.api.fullname" . }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "shop.api.labels" . | nindent 4 }}
  {{- with .Values.api.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  {{- /* ⭐ when the HPA owns replicas, the Deployment must NOT set them —
         otherwise every `helm upgrade` resets the scale back down. */ -}}
  {{- if not .Values.api.autoscaling.enabled }}
  replicas: {{ .Values.api.replicaCount }}
  {{- end }}
  revisionHistoryLimit: {{ .Values.api.revisionHistoryLimit | default 8 }}
  strategy:
    {{- toYaml .Values.api.strategy | nindent 4 }}
  selector:
    matchLabels:
      {{- include "shop.api.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "shop.api.selectorLabels" . | nindent 8 }}
        {{- with .Values.api.podLabels }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
      annotations:
        {{- /* ⭐ config changes roll the pods */ -}}
        {{- include "shop.api.configChecksums" . | nindent 8 }}
        {{- with .Values.api.podAnnotations }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
    spec:
      serviceAccountName: {{ include "shop.api.serviceAccountName" . }}
      terminationGracePeriodSeconds: {{ .Values.api.shutdown.terminationGracePeriodSeconds }}
      {{- with .Values.global.imagePullSecrets }}
      imagePullSecrets:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      securityContext:
        {{- toYaml .Values.podSecurityContext | nindent 8 }}
        {{- with .Values.api.podSecurityContext }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
        fsGroup: {{ .Values.api.fsGroup | default 10001 }}

      {{- if .Values.api.topologySpread.enabled }}
      topologySpreadConstraints:
        - maxSkew: {{ .Values.api.topologySpread.maxSkew }}
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: {{ .Values.api.topologySpread.hostnamePolicy }}
          {{- if eq .Values.api.topologySpread.hostnamePolicy "DoNotSchedule" }}
          minDomains: {{ .Values.api.topologySpread.minDomains | default 3 }}
          {{- end }}
          labelSelector:
            matchLabels:
              {{- include "shop.api.selectorLabels" . | nindent 14 }}
        - maxSkew: {{ .Values.api.topologySpread.maxSkew }}
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: {{ .Values.api.topologySpread.zonePolicy }}
          labelSelector:
            matchLabels:
              {{- include "shop.api.selectorLabels" . | nindent 14 }}
      {{- end }}

      initContainers:
        {{- if and .Values.database.enabled .Values.database.internal }}
        - name: wait-for-db
          image: {{ include "shop.image" (dict "ctx" $ "component" (dict "repository" "busybox" "registry" "docker.io" "repositoryPath" "library/busybox" "tag" "1.37")) }}
          command:
            - sh
            - -c
            - |
              set -eu
              HOST={{ include "shop.db.host" . }}
              PORT={{ include "shop.db.port" . }}
              i=0
              until nc -z "$HOST" "$PORT"; do
                i=$((i+1))
                [ $i -gt 60 ] && { echo "FATAL: $HOST:$PORT unreachable after 120s"; nslookup "$HOST" || true; exit 1; }
                echo "waiting for $HOST:$PORT ($i)"
                sleep 2
              done
              echo "$HOST:$PORT is reachable"
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities: {drop: ["ALL"]}
          resources:
            requests: {cpu: 10m, memory: 8Mi}
            limits:   {cpu: 100m, memory: 32Mi}
        {{- end }}
        {{- with .Values.api.initContainers }}
        {{- toYaml . | nindent 8 }}
        {{- end }}

      containers:
        - name: api
          image: {{ $img }}
          imagePullPolicy: {{ $pull }}
          ports:
            - name: http
              containerPort: {{ .Values.api.containerPort }}
              protocol: TCP
          securityContext:
            {{- toYaml .Values.containerSecurityContext | nindent 12 }}
            runAsUser: {{ .Values.api.runAsUser | default 10001 }}
            runAsGroup: {{ .Values.api.runAsGroup | default 10001 }}

          envFrom:
            - configMapRef:
                name: {{ include "shop.api.fullname" . }}-config
            {{- with .Values.api.extraEnvFrom }}
            {{- toYaml . | nindent 12 }}
            {{- end }}

          env:
            - name: JAVA_OPTS
              valueFrom:
                configMapKeyRef:
                  name: {{ include "shop.api.fullname" . }}-jvm
                  key: JAVA_OPTS
            - name: SPRING_DATASOURCE_URL
              value: {{ include "shop.db.jdbcUrl" . | quote }}
            - name: SPRING_DATASOURCE_USERNAME
              valueFrom:
                secretKeyRef:
                  name: {{ include "shop.db.secretName" . }}
                  key: {{ .Values.externalDatabase.usernameKey | default "username" }}
            - name: SPRING_DATASOURCE_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: {{ include "shop.db.secretName" . }}
                  key: {{ .Values.externalDatabase.passwordKey | default "password" }}
            - name: POD_NAME
              valueFrom: {fieldRef: {fieldPath: metadata.name}}
            - name: POD_NAMESPACE
              valueFrom: {fieldRef: {fieldPath: metadata.namespace}}
            - name: POD_IP
              valueFrom: {fieldRef: {fieldPath: status.podIP}}
            - name: NODE_NAME
              valueFrom: {fieldRef: {fieldPath: spec.nodeName}}
            - name: APP_VERSION
              value: {{ .Chart.AppVersion | quote }}
            - name: CHART_VERSION
              value: {{ .Chart.Version | quote }}
            - name: RELEASE_NAME
              value: {{ .Release.Name | quote }}
            - name: ENVIRONMENT
              value: {{ .Values.global.environment | quote }}
            {{- with .Values.api.extraEnv }}
            {{- toYaml . | nindent 12 }}
            {{- end }}

          {{- if .Values.api.startupProbe.enabled }}
          startupProbe:
            httpGet:
              path: {{ .Values.api.startupProbe.path }}
              port: http
            periodSeconds: {{ .Values.api.startupProbe.periodSeconds }}
            failureThreshold: {{ .Values.api.startupProbe.failureThreshold }}
            timeoutSeconds: {{ .Values.api.startupProbe.timeoutSeconds }}
          {{- end }}

          {{- if .Values.api.readinessProbe.enabled }}
          readinessProbe:
            httpGet:
              path: {{ .Values.api.readinessProbe.path }}
              port: http
            periodSeconds: {{ .Values.api.readinessProbe.periodSeconds }}
            failureThreshold: {{ .Values.api.readinessProbe.failureThreshold }}
            successThreshold: {{ .Values.api.readinessProbe.successThreshold | default 1 }}
            timeoutSeconds: {{ .Values.api.readinessProbe.timeoutSeconds }}
          {{- end }}

          {{- if .Values.api.livenessProbe.enabled }}
          livenessProbe:
            httpGet:
              path: {{ .Values.api.livenessProbe.path }}
              port: http
            periodSeconds: {{ .Values.api.livenessProbe.periodSeconds }}
            failureThreshold: {{ .Values.api.livenessProbe.failureThreshold }}
            timeoutSeconds: {{ .Values.api.livenessProbe.timeoutSeconds }}
          {{- end }}

          lifecycle:
            preStop:
              exec:
                command: ["/bin/sh", "-c", "sleep {{ .Values.api.shutdown.preStopSleepSeconds }}"]
            {{- with .Values.api.lifecycleHooks }}
            {{- toYaml . | nindent 12 }}
            {{- end }}

          resources:
            {{- toYaml .Values.api.resources | nindent 12 }}

          volumeMounts:
            - {name: tmp,   mountPath: /tmp}
            - {name: dumps, mountPath: /tmp/dumps}
            {{- with .Values.api.extraVolumeMounts }}
            {{- toYaml . | nindent 12 }}
            {{- end }}

        {{- with .Values.api.sidecars }}
        {{- toYaml . | nindent 8 }}
        {{- end }}

      volumes:
        - {name: tmp,   emptyDir: {sizeLimit: 512Mi}}
        - {name: dumps, emptyDir: {sizeLimit: 1Gi}}
        {{- with .Values.api.extraVolumes }}
        {{- toYaml . | nindent 8 }}
        {{- end }}

      {{- with .Values.api.nodeSelector }}
      nodeSelector:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.api.tolerations }}
      tolerations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- if and (not .Values.api.topologySpread.enabled) .Values.api.affinity }}
      affinity:
        {{- toYaml .Values.api.affinity | nindent 8 }}
      {{- end }}
{{- end }}
```

**The five Helm patterns in that file worth memorising:**

| Pattern | Why |
|---|---|
| `{{- if not .Values.api.autoscaling.enabled }} replicas: …` | Setting `replicas` while an HPA is active makes every upgrade **reset the scale**. This is the #1 Helm/HPA bug. |
| `checksum/config` in the Pod annotations | Changing a ConfigMap doesn't roll Pods. This makes it. |
| `nindent N` after every `toYaml` | Indentation is the #1 cause of Helm template errors. `nindent` = newline + indent. |
| `required "msg" .Values.x` | Fail with your own message instead of a nil-pointer panic. |
| `include "shop.image" (dict …)` | One place to resolve registry/tag/digest, so pinning by digest works everywhere. |

## 14.6 The rest of the templates

`templates/api/configmap.yaml`:

```gotemplate
{{- if .Values.api.enabled }}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "shop.api.fullname" . }}-config
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "shop.api.labels" . | nindent 4 }}
data:
  {{- range $k, $v := .Values.api.config }}
  {{ $k }}: {{ $v | quote }}        {{/* ⭐ ALWAYS quote. Unquoted "true"/"150" become booleans/ints */}}
  {{- end }}
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "shop.api.fullname" . }}-jvm
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "shop.api.labels" . | nindent 4 }}
data:
  JAVA_OPTS: {{ .Values.api.jvmOpts | quote }}
{{- end }}
```

`templates/api/service.yaml`:

```gotemplate
{{- if .Values.api.enabled }}
apiVersion: v1
kind: Service
metadata:
  name: {{ include "shop.api.fullname" . }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "shop.api.labels" . | nindent 4 }}
  {{- with .Values.api.service.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  type: {{ .Values.api.service.type }}
  selector:
    {{- include "shop.api.selectorLabels" . | nindent 4 }}
  ports:
    - name: http
      port: {{ .Values.api.service.port }}
      targetPort: http
      protocol: TCP
{{- end }}
```

`templates/api/hpa.yaml`:

```gotemplate
{{- if and .Values.api.enabled .Values.api.autoscaling.enabled }}
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {{ include "shop.api.fullname" . }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "shop.api.labels" . | nindent 4 }}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: {{ include "shop.api.fullname" . }}
  minReplicas: {{ .Values.api.autoscaling.minReplicas }}
  maxReplicas: {{ .Values.api.autoscaling.maxReplicas }}
  metrics:
    {{- if .Values.api.autoscaling.targetCPUUtilizationPercentage }}
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: {{ .Values.api.autoscaling.targetCPUUtilizationPercentage }}
    {{- end }}
    {{- if .Values.api.autoscaling.targetMemoryUtilizationPercentage }}
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: {{ .Values.api.autoscaling.targetMemoryUtilizationPercentage }}
    {{- end }}
    {{- with .Values.api.autoscaling.customMetrics }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  {{- with .Values.api.autoscaling.behavior }}
  behavior:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end }}
```

`templates/api/pdb.yaml`:

```gotemplate
{{- if and .Values.api.enabled .Values.security.podDisruptionBudgets.enabled .Values.api.pdb.enabled }}
{{- if gt (int .Values.api.replicaCount) 1 }}     {{/* ⭐ a PDB on 1 replica blocks all drains */}}
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: {{ include "shop.api.fullname" . }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "shop.api.labels" . | nindent 4 }}
spec:
  {{- with .Values.api.pdb.minAvailable }}
  minAvailable: {{ . }}
  {{- end }}
  {{- with .Values.api.pdb.maxUnavailable }}
  maxUnavailable: {{ . }}
  {{- end }}
  selector:
    matchLabels:
      {{- include "shop.api.selectorLabels" . | nindent 6 }}
{{- end }}
{{- end }}
```

`templates/ingress.yaml` — **two Ingress objects, because annotations are per-Ingress**:

```gotemplate
{{- if .Values.ingress.enabled }}
{{- $uiHost  := .Values.ingress.ui.host  | default .Values.global.domain }}
{{- $apiHost := .Values.ingress.api.host | default .Values.global.domain }}
{{- $tlsSecret := .Values.ingress.tls.secretName | default (printf "%s-tls" (include "shop.fullname" .)) }}
{{- $issuer := .Values.ingress.tls.issuer | default .Values.global.tls.issuer }}

# ═══════════ UI: everything not matched below ═══════════
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ include "shop.ui.fullname" . }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "shop.ui.labels" . | nindent 4 }}
  annotations:
    {{- if $issuer }}
    cert-manager.io/cluster-issuer: {{ $issuer }}
    {{- end }}
    {{- if .Values.ingress.tls.enabled }}
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    {{- else }}
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    {{- end }}
    nginx.ingress.kubernetes.io/proxy-body-size: {{ .Values.ui.nginx.clientMaxBodySize | quote }}
    {{- with .Values.ingress.ui.annotations }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
spec:
  ingressClassName: {{ .Values.ingress.className }}
  {{- if .Values.ingress.tls.enabled }}
  tls:
    - hosts: [{{ $uiHost | quote }}]
      secretName: {{ $tlsSecret }}
  {{- end }}
  rules:
    - host: {{ $uiHost | quote }}
      http:
        paths:
          - path: {{ .Values.ingress.ui.path }}
            pathType: {{ .Values.ingress.ui.pathType }}
            backend:
              service:
                name: {{ include "shop.ui.fullname" . }}
                port: {number: {{ .Values.ui.service.port | default 80 }}}
{{- with .Values.ingress.extraHosts }}
          {{- toYaml . | nindent 10 }}
{{- end }}

---
# ═══════════ API: /api/* with the prefix stripped ═══════════
{{- if .Values.api.enabled }}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ include "shop.api.fullname" . }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "shop.api.labels" . | nindent 4 }}
  annotations:
    {{- if $issuer }}
    cert-manager.io/cluster-issuer: {{ $issuer }}
    {{- end }}
    nginx.ingress.kubernetes.io/ssl-redirect: {{ .Values.ingress.tls.enabled | quote }}
    nginx.ingress.kubernetes.io/rewrite-target: {{ .Values.ingress.api.rewriteTarget | quote }}
    {{- with .Values.ingress.api.annotations }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
spec:
  ingressClassName: {{ .Values.ingress.className }}
  {{- if .Values.ingress.tls.enabled }}
  tls:
    - hosts: [{{ $apiHost | quote }}]
      secretName: {{ $tlsSecret }}
  {{- end }}
  rules:
    - host: {{ $apiHost | quote }}
      http:
        paths:
          - path: {{ .Values.ingress.api.path }}
            pathType: {{ .Values.ingress.api.pathType }}
            backend:
              service:
                name: {{ include "shop.api.fullname" . }}
                port: {number: {{ .Values.api.service.port }}}
{{- end }}
{{- end }}
```

`templates/db/statefulset.yaml`, `templates/db/secret.yaml`, `templates/db/service.yaml` — the StatefulSet from [Project 10 §10.7](13-PROJECT-10-react-java-fullstack.md#107-k8sbasedbyaml--the-database-as-a-statefulset), templated the same way. The Secret:

```gotemplate
{{- if and .Values.database.enabled .Values.database.internal (not .Values.database.auth.existingSecret) }}
apiVersion: v1
kind: Secret
metadata:
  name: {{ include "shop.fullname" . }}-creds
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "shop.labels" . | nindent 4 }}
  annotations:
    {{- /* ⭐ so `helm uninstall` does NOT delete the database credentials */ -}}
    "helm.sh/resource-policy": keep
type: Opaque
stringData:
  username: {{ .Values.database.auth.username | quote }}
  database: {{ .Values.database.auth.database | quote }}
  {{- if .Values.database.auth.password }}
  {{- if eq (toString .Values.global.environment) "prod" }}
    {{- fail "database.auth.password must not be set when global.environment=prod" }}
  {{- end }}
  password: {{ .Values.database.auth.password | quote }}
  {{- else }}
  {{- /* ⭐ generate once, keep it stable across upgrades */ -}}
  password: {{ (lookup "v1" "Secret" .Release.Namespace (printf "%s-creds" (include "shop.fullname" .))).data.password | default (randAlphaNum 32 | b64enc) | b64dec | quote }}
  {{- end }}
{{- end }}
```

> 🔑 **The `lookup` trick.** Without it, `randAlphaNum 32` generates a *new* password on every `helm upgrade` — and your database keeps the old one. `lookup` reads the existing Secret first, and only generates if there isn't one. **`lookup` returns nothing during `helm template`** (there's no cluster), so `helm template` output will differ from `helm install` output for generated values. That's expected.

`templates/jobs/migrate.yaml` — **a Helm hook**:

```gotemplate
{{- if and .Values.migrations.enabled .Values.api.enabled }}
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ include "shop.api.fullname" . }}-migrate-{{ .Release.Revision }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "shop.api.labels" . | nindent 4 }}
    app.kubernetes.io/task: migrate
  annotations:
    "helm.sh/hook": pre-install,pre-upgrade
    "helm.sh/hook-weight": {{ .Values.migrations.hook.weight | quote }}
    "helm.sh/hook-delete-policy": {{ .Values.migrations.hook.deletePolicy | quote }}
spec:
  backoffLimit: {{ .Values.migrations.backoffLimit }}
  activeDeadlineSeconds: {{ .Values.migrations.timeoutSeconds }}
  ttlSecondsAfterFinished: 604800
  template:
    metadata:
      labels:
        {{- include "shop.api.selectorLabels" . | nindent 8 }}
        app.kubernetes.io/task: migrate
    spec:
      restartPolicy: Never
      serviceAccountName: {{ include "shop.api.serviceAccountName" . }}
      securityContext:
        {{- toYaml .Values.podSecurityContext | nindent 8 }}
      containers:
        - name: migrate
          image: {{ include "shop.image" (dict "ctx" $ "component" .Values.api.image "global" .Values.global) }}
          command: ["sh","-c","exec java $JAVA_OPTS -Dspring.main.web-application-type=none org.springframework.boot.loader.launch.JarLauncher"]
          env:
            - name: JAVA_OPTS
              value: "-XX:MaxRAMPercentage=60 -Dspring.flyway.enabled=true"
            - name: SPRING_PROFILES_ACTIVE
              value: {{ printf "%s,migrate" .Values.global.environment | quote }}
            - name: SPRING_DATASOURCE_URL
              value: {{ include "shop.db.jdbcUrl" . | quote }}
            - name: SPRING_DATASOURCE_USERNAME
              valueFrom: {secretKeyRef: {name: {{ include "shop.db.secretName" . }}, key: username}}
            - name: SPRING_DATASOURCE_PASSWORD
              valueFrom: {secretKeyRef: {name: {{ include "shop.db.secretName" . }}, key: password}}
          resources:
            {{- toYaml .Values.migrations.resources | nindent 12 }}
          securityContext:
            {{- toYaml .Values.containerSecurityContext | nindent 12 }}
          volumeMounts: [{name: tmp, mountPath: /tmp}]
      volumes: [{name: tmp, emptyDir: {sizeLimit: 256Mi}}]
{{- end }}
```

**Helm hooks — the ordering mechanism:**

| Annotation | Effect |
|---|---|
| `helm.sh/hook: pre-install` | Runs before the first install |
| `helm.sh/hook: pre-upgrade` | Runs before every upgrade, **and Helm waits for it to complete** |
| `helm.sh/hook: post-install,post-upgrade` | Runs after the resources are applied |
| `helm.sh/hook: pre-delete` | Runs before uninstall |
| `helm.sh/hook: test` | Runs on `helm test` |
| `helm.sh/hook-weight: "-5"` | Lower weights run first within the same hook |
| `helm.sh/hook-delete-policy: before-hook-creation` | Delete the previous hook resource before creating this one |
| `helm.sh/hook-delete-policy: hook-succeeded` | Delete it if it succeeded |
| `helm.sh/hook-delete-policy: hook-failed` | Keep it if it failed (so you can read the logs) |

⚠️ **Hooks are NOT part of the release.** `helm get manifest` doesn't show them. `helm rollback` doesn't roll them back. A failed `pre-upgrade` hook **fails the whole upgrade** and leaves the release in `pending-upgrade` — which then blocks every subsequent upgrade until you `helm rollback` or delete the stuck release. This is the most common Helm operational problem.

```bash
helm history shop -n shop
# 4   …   pending-upgrade   shop-0.4.2   1.4.0   Preparing upgrade
helm rollback shop 3 -n shop          # unsticks it
# or, if that fails:
kubectl delete secret -n shop -l owner=helm,name=shop,version=4
```

## 14.7 `templates/security/networkpolicy.yaml`

```gotemplate
{{- if .Values.security.networkPolicies.enabled }}
{{- $fullName := include "shop.fullname" . }}

{{- if .Values.security.networkPolicies.defaultDeny }}
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ $fullName }}-default-deny
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "shop.labels" . | nindent 4 }}
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
---
{{- end }}

# DNS for everything — without this, nothing resolves
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ $fullName }}-allow-dns
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "shop.labels" . | nindent 4 }}
spec:
  podSelector: {}
  policyTypes: [Egress]
  egress:
    - to:
        - namespaceSelector:
            matchLabels: {kubernetes.io/metadata.name: kube-system}
          podSelector:
            matchLabels: {k8s-app: kube-dns}
      ports:
        - {protocol: UDP, port: 53}
        - {protocol: TCP, port: 53}

{{- if .Values.ui.enabled }}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "shop.ui.fullname" . }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "shop.ui.labels" . | nindent 4 }}
spec:
  podSelector:
    matchLabels:
      {{- include "shop.ui.selectorLabels" . | nindent 6 }}
  policyTypes: [Ingress]
  ingress:
    - from:
        {{- toYaml .Values.security.networkPolicies.ingressFrom | nindent 8 }}
      ports:
        - {protocol: TCP, port: {{ .Values.ui.containerPort }}}
{{- end }}

{{- if .Values.api.enabled }}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "shop.api.fullname" . }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "shop.api.labels" . | nindent 4 }}
spec:
  podSelector:
    matchLabels:
      {{- include "shop.api.selectorLabels" . | nindent 6 }}
  policyTypes: [Ingress, Egress]
  ingress:
    - from:
        {{- toYaml .Values.security.networkPolicies.ingressFrom | nindent 8 }}
      ports:
        - {protocol: TCP, port: {{ .Values.api.containerPort }}}
    {{- if .Values.monitoring.serviceMonitor.enabled }}
    - from:
        - namespaceSelector:
            matchLabels: {kubernetes.io/metadata.name: {{ .Values.monitoring.serviceMonitor.namespace }}}
      ports:
        - {protocol: TCP, port: {{ .Values.api.containerPort }}}
    {{- end }}
  egress:
    {{- if and .Values.database.enabled .Values.database.internal }}
    - to:
        - podSelector:
            matchLabels:
              {{- include "shop.db.selectorLabels" . | nindent 14 }}
      ports:
        - {protocol: TCP, port: {{ .Values.database.containerPort }}}
    {{- end }}
    {{- with .Values.security.networkPolicies.apiEgressExtra }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
{{- end }}
{{- end }}
```

## 14.8 `templates/tests/test-api.yaml` — `helm test`

```gotemplate
{{- if .Values.tests.enabled }}
apiVersion: v1
kind: Pod
metadata:
  name: {{ include "shop.fullname" . }}-test-api
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "shop.labels" . | nindent 4 }}
    app.kubernetes.io/task: test
  annotations:
    "helm.sh/hook": test
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
spec:
  restartPolicy: Never
  containers:
    - name: curl
      image: {{ include "shop.image" (dict "ctx" $ "component" .Values.tests.image "global" .Values.global) }}
      command: ["/bin/sh", "-c"]
      args:
        - |
          set -eu
          API=http://{{ include "shop.api.fullname" . }}:{{ .Values.api.service.port }}
          UI=http://{{ include "shop.ui.fullname" . }}:{{ .Values.ui.service.port | default 80 }}
          FAIL=0

          t() { # t <desc> <expected> <actual>
            if [ "$2" = "$3" ]; then echo "  ✅ $1 ($3)"; else echo "  ❌ $1: expected $2, got $3"; FAIL=$((FAIL+1)); fi
          }

          echo "▸ waiting for the API"
          for i in $(seq 1 60); do
            curl -sf --max-time 2 "$API/actuator/health/liveness" >/dev/null && break
            sleep 2
            [ $i -eq 60 ] && { echo "⛔ API never became reachable"; exit 1; }
          done

          t "liveness"  "200" "$(curl -s -o /dev/null -w '%{http_code}' $API/actuator/health/liveness)"
          t "readiness" "200" "$(curl -s -o /dev/null -w '%{http_code}' $API/actuator/health/readiness)"
          t "metrics"   "200" "$(curl -s -o /dev/null -w '%{http_code}' $API/actuator/prometheus)"

          echo "▸ end-to-end write/read"
          NEW=$(curl -sf -XPOST "$API/api/products" -H 'Content-Type: application/json' \
                 -d '{"name":"helm-test-'$(date +%s)'","price":1.23}')
          ID=$(echo "$NEW" | sed -n 's/.*"id":\([0-9]*\).*/\1/p')
          [ -n "$ID" ] && echo "  ✅ created id=$ID" || { echo "  ❌ create failed: $NEW"; FAIL=$((FAIL+1)); }
          if [ -n "$ID" ]; then
            t "read back"  "200" "$(curl -s -o /dev/null -w '%{http_code}' $API/api/products/$ID)"
            t "delete"     "204" "$(curl -s -o /dev/null -w '%{http_code}' -XDELETE $API/api/products/$ID)"
          fi

          echo "▸ UI"
          t "ui index"   "200" "$(curl -s -o /dev/null -w '%{http_code}' $UI/)"
          t "ui healthz" "200" "$(curl -s -o /dev/null -w '%{http_code}' $UI/healthz)"
          t "ui spa fallback" "200" "$(curl -s -o /dev/null -w '%{http_code}' $UI/products/42)"

          echo "▸ database connectivity (via the API)"
          t "products list" "200" "$(curl -s -o /dev/null -w '%{http_code}' $API/api/products)"

          echo
          if [ $FAIL -eq 0 ]; then echo "🎉 ALL TESTS PASSED"; else echo "💥 $FAIL FAILED"; exit 1; fi
      resources:
        requests: {cpu: 20m, memory: 32Mi}
        limits:   {cpu: 200m, memory: 64Mi}
{{- end }}
```

```bash
helm test shop -n shop
# NAME: shop
# LAST DEPLOYED: Mon Sep 9 18:20:14 2026
# STATUS: deployed
# TEST SUITE: shop-test-api
# Last Started:   Mon Sep 9 18:22:01 2026
# Last Completed: Mon Sep 9 18:22:19 2026
# Phase:          Succeeded
# NOTES:
# ▸ waiting for the API
#   ✅ liveness (200)
#   ✅ readiness (200)
#   ✅ metrics (200)
# ▸ end-to-end write/read
#   ✅ created id=42
#   ✅ read back (200)
#   ✅ delete (204)
# ▸ UI
#   ✅ ui index (200)
#   ✅ ui healthz (200)
#   ✅ ui spa fallback (200)
# 🎉 ALL TESTS PASSED
```

⚠️ **`helm test` does NOT fail `helm install`.** It's a separate command. Put it in your pipeline explicitly:

```bash
helm upgrade --install shop ./shop -n shop -f values-prod.yaml --wait --timeout 10m --atomic
helm test shop -n shop --timeout 5m || { helm rollback shop -n shop; exit 1; }
```

## 14.9 `templates/NOTES.txt` — what the user sees after install

```gotemplate
{{- $fullName := include "shop.fullname" . }}
╔══════════════════════════════════════════════════════════════╗
║  🛍️  {{ $fullName }} {{ .Chart.AppVersion }} (chart {{ .Chart.Version }})          ║
╚══════════════════════════════════════════════════════════════╝

  Environment : {{ .Values.global.environment }}
  Namespace   : {{ .Release.Namespace }}
  Revision    : {{ .Release.Revision }}

▸ COMPONENTS
{{- if .Values.api.enabled }}
  API         {{ .Values.api.replicaCount }} replicas  {{ include "shop.image" (dict "ctx" $ "component" .Values.api.image "global" .Values.global) }}
{{- end }}
{{- if .Values.ui.enabled }}
  UI          {{ .Values.ui.replicaCount }} replicas  {{ include "shop.image" (dict "ctx" $ "component" .Values.ui.image "global" .Values.global) }}
{{- end }}
{{- if .Values.database.enabled }}
  {{- if .Values.database.internal }}
  Database    INTERNAL postgres:{{ .Values.database.image.tag }} — {{ .Values.database.replicaCount }} replica(s), {{ .Values.database.persistence.size }}
  {{- else }}
  Database    EXTERNAL {{ include "shop.db.host" . }}:{{ include "shop.db.port" . }}
  {{- end }}
{{- end }}

▸ ACCESS
{{- if .Values.ingress.enabled }}
  {{- $scheme := ternary "https" "http" .Values.ingress.tls.enabled }}
  {{- $host := .Values.ingress.ui.host | default .Values.global.domain }}
  UI   →  {{ $scheme }}://{{ $host }}/
  API  →  {{ $scheme }}://{{ $host }}/api/products
{{- else }}
  kubectl port-forward -n {{ .Release.Namespace }} svc/{{ include "shop.ui.fullname" . }} 8080:80
  kubectl port-forward -n {{ .Release.Namespace }} svc/{{ include "shop.api.fullname" . }} 8081:{{ .Values.api.service.port }}
  UI   →  http://localhost:8080/
  API  →  http://localhost:8081/api/products
{{- end }}

{{- if and .Values.database.internal (not .Values.database.auth.existingSecret) }}

▸ DATABASE CREDENTIALS
  kubectl get secret -n {{ .Release.Namespace }} {{ $fullName }}-creds \
    -o jsonpath='{.data.password}' | base64 -d; echo

  kubectl run psql -n {{ .Release.Namespace }} --rm -it --restart=Never \
    --image=postgres:{{ .Values.database.image.tag }} -- \
    psql "postgresql://{{ .Values.database.auth.username }}:$(kubectl get secret -n {{ .Release.Namespace }} {{ $fullName }}-creds -o jsonpath='{.data.password}' | base64 -d)@{{ include "shop.db.host" . }}:{{ include "shop.db.port" . }}/{{ .Values.database.auth.database }}"
{{- end }}

▸ VERIFY
  kubectl get pods,svc,ingress,hpa,pdb -n {{ .Release.Namespace }}
  helm test {{ .Release.Name }} -n {{ .Release.Namespace }}
  helm history {{ .Release.Name }} -n {{ .Release.Namespace }}
  kubectl rollout status deploy/{{ include "shop.api.fullname" . }} -n {{ .Release.Namespace }}

▸ UPGRADE
  helm upgrade {{ .Release.Name }} ./shop -n {{ .Release.Namespace }} -f values.yaml --atomic

▸ ROLLBACK
  helm history {{ .Release.Name }} -n {{ .Release.Namespace }}
  helm rollback {{ .Release.Name }} <REVISION> -n {{ .Release.Namespace }}

{{- if eq (toString .Values.global.environment) "dev" }}

⚠️  WARNINGS
  {{- if .Values.database.internal }}
  - database.internal=true: a single-replica in-cluster Postgres. NOT for production.
  {{- end }}
  {{- if not .Values.ingress.tls.enabled }}
  - ingress.tls.enabled=false: traffic is unencrypted.
  {{- end }}
  {{- if not .Values.monitoring.serviceMonitor.enabled }}
  - monitoring.serviceMonitor.enabled=false: no metrics are being scraped.
  {{- end }}
{{- end }}
```

## 14.10 The developer workflow

```bash
cd ~/k8s-learn/p14

# ── 1. LINT: catches template errors, missing fields, deprecated APIs ──
helm lint ./shop
# ==> Linting ./shop
# [INFO] Chart.yaml: icon is recommended
# 1 chart(s) linted, 0 chart(s) failed

helm lint ./shop --strict --with-subcharts
# [ERROR] templates/: required value api.resources.limits is empty

# ── 2. RENDER: read the YAML before it touches a cluster ──
helm template shop ./shop > /tmp/rendered.yaml
kubectl apply --dry-run=client -f /tmp/rendered.yaml       # client-side syntax check
kubectl apply --dry-run=server -f /tmp/rendered.yaml       # ⭐ server-side: the API validates it

# render one file, with values
helm template shop ./shop -s templates/api/deployment.yaml \
  --set api.replicaCount=5 --set global.environment=staging

# ── 3. DIFF: what will actually change? (install the plugin first) ──
helm install shop ./shop -n shop --create-namespace --dry-run
# then edit values and:
helm diff upgrade shop ./shop -n shop
# shop, api (apps/v1 / Deployment, shop) has changed:
#   spec:
# -   replicas: 3
# +   replicas: 5

# ── 4. INSTALL ──
helm install shop ./shop -n shop --create-namespace \
  --set-string database.auth.password='L3arn-K8s!' \
  --wait --timeout 10m

# ── 5. UPGRADE ──
helm upgrade shop ./shop -n shop \
  --set api.image.tag=1.5.0 \
  --atomic --timeout 10m
# --atomic = wait, and ROLL BACK automatically if anything fails or times out

# ── 6. VERIFY ──
helm status shop -n shop
helm history shop -n shop
helm test shop -n shop

# ── 7. ROLLBACK ──
helm rollback shop 3 -n shop --wait
helm get manifest shop -n shop --revision 4 > rev4.yaml    # compare revisions

# ── 8. UNINSTALL ──
helm uninstall shop -n shop --wait
kubectl get pvc -n shop          # ⚠️ PVCs from volumeClaimTemplates SURVIVE. Delete manually.
kubectl delete pvc -n shop --all
```

**The `--atomic` flag is non-negotiable in CI:**

```bash
helm upgrade --install shop ./shop -n shop -f values-prod.yaml \
  --atomic --timeout 10m --wait --wait-for-jobs
```

| Flag | Effect |
|---|---|
| `--install` | Install if it doesn't exist, upgrade if it does — idempotent |
| `--wait` | Block until every resource is Ready |
| `--wait-for-jobs` | Also wait for Jobs/CronJobs to complete |
| `--timeout 10m` | How long `--wait` tries |
| `--atomic` | **On failure or timeout, roll back to the previous revision automatically** |
| `--force` | ⚠️ Force updates via a replace. Can delete and recreate PVC-bound Pods. **Avoid.** |
| `--dry-run` | Render + validate, don't apply |
| `--debug` | Print the rendered templates even on failure |
| `--no-hooks` | Skip hooks (useful to re-run without re-migrating) |
| `--reset-values` | Ignore the previous release's values; use only the chart defaults + `-f` |

> 🔑 **`--reuse-values` is a trap.** It merges the *previous release's* values with your new ones. That sounds helpful, and it is — until it silently resurrects an old image tag you explicitly changed, or keeps a value you deleted from `values.yaml`. **Always pass your full values file with `-f` and never use `--reuse-values`.**

## 14.11 Environment values files

`values-dev.yaml`:

```yaml
global:
  environment: dev
  domain: shop.local
  tls:
    enabled: false

api:
  replicaCount: 1
  autoscaling: {enabled: false}
  pdb: {enabled: false}
  topologySpread: {enabled: false}
  config:
    SPRING_PROFILES_ACTIVE: dev
    SPRING_JPA_HIBERNATE_DDL_AUTO: update       # dev convenience
    LOG_LEVEL_APP: DEBUG
  resources:
    requests: {cpu: 250m, memory: 768Mi}
    limits:   {cpu: "1",   memory: 1Gi}
  shutdown:
    preStopSleepSeconds: 2                       # fast iteration
    terminationGracePeriodSeconds: 30
    springGracefulShutdownSeconds: 20

ui:
  replicaCount: 1
  autoscaling: {enabled: false}

database:
  internal: true
  replicaCount: 1
  auth:
    username: shop
    password: "L3arn-K8s!"                       # ⚠️ dev only — the chart FAILS this in prod
  persistence:
    size: 2Gi

ingress:
  enabled: true
  className: nginx
  tls: {enabled: false}

security:
  networkPolicies: {enabled: false}              # off in dev, so you can debug freely
  podDisruptionBudgets: {enabled: false}

tests: {enabled: true}
```

`values-prod.yaml`:

```yaml
global:
  environment: prod
  domain: shop.example.com
  imageRegistry: ghcr.io
  imageRepository: 3558bhk
  imagePullSecrets: [ghcr-pull]
  storageClass: gp3
  tls:
    enabled: true
    issuer: letsencrypt-prod

api:
  replicaCount: 0                                # ⭐ HPA owns it — must be 0 or omitted
  image:
    digest: "sha256:9f2a4c1e…"                   # ⭐ PINNED BY DIGEST — immutable
  autoscaling:
    enabled: true
    minReplicas: 6
    maxReplicas: 40
    targetCPUUtilizationPercentage: 65
  pdb: {enabled: true, maxUnavailable: 1}
  topologySpread:
    enabled: true
    hostnamePolicy: DoNotSchedule
    minDomains: 3
  resources:
    requests: {cpu: "1",   memory: 1536Mi}
    limits:   {cpu: "2",   memory: 2Gi}
  shutdown:
    preStopSleepSeconds: 15
    terminationGracePeriodSeconds: 90
    springGracefulShutdownSeconds: 45
  config:
    SPRING_PROFILES_ACTIVE: prod
    SPRING_JPA_HIBERNATE_DDL_AUTO: validate
    LOG_LEVEL_APP: INFO

ui:
  replicaCount: 0
  image:
    digest: "sha256:1a2b3c4d…"
  autoscaling: {enabled: true, minReplicas: 4, maxReplicas: 30}

database:
  internal: false                                # ⭐ REQUIRED by the validation in prod
externalDatabase:
  host: shop-prod.cluster-abc123.ap-south-1.rds.amazonaws.com
  port: 5432
  existingSecret: rds-shop-creds                 # created by External Secrets Operator
  sslMode: require

ingress:
  enabled: true
  className: nginx
  tls:
    enabled: true
    issuer: letsencrypt-prod
    secretName: shop-example-com-tls
  api:
    annotations:
      nginx.ingress.kubernetes.io/limit-rps: "500"
      nginx.ingress.kubernetes.io/limit-connections: "200"
      nginx.ingress.kubernetes.io/enable-modsecurity: "true"
      nginx.ingress.kubernetes.io/modsecurity-snippet: |
        SecRuleEngine On
        SecRequestBodyAccess On

security:
  networkPolicies:
    enabled: true
    defaultDeny: true
    ingressFrom:
      - namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: ingress-nginx}}
        podSelector: {matchLabels: {app.kubernetes.io/name: ingress-nginx}}
  podDisruptionBudgets: {enabled: true}
  secrets: {provider: external-secrets}

monitoring:
  serviceMonitor: {enabled: true, namespace: monitoring, labels: {release: kps}}
  rules:          {enabled: true, namespace: monitoring, labels: {release: kps}}
  dashboards:     {enabled: true}

migrations: {enabled: true, backoffLimit: 0, timeoutSeconds: 1800}
tests:      {enabled: true}
```

```bash
# the validation catches a bad prod deploy before it happens
helm template shop ./shop -f values-prod.yaml --set database.internal=true
# Error: execution error at (shop/templates/_helpers.tpl:…):
#   database.internal=true is not allowed when global.environment=prod.

helm template shop ./shop -f values-prod.yaml --set api.image.digest="" --set api.image.tag=latest
# Error: api.image.tag=latest is not allowed in prod. Pin a version or a digest.

helm template shop ./shop -f values-prod.yaml \
  --set api.shutdown.preStopSleepSeconds=60 --set api.shutdown.terminationGracePeriodSeconds=30
# Error: api.shutdown: preStopSleep (60) + springGracefulShutdown (45) = 105
#        exceeds terminationGracePeriodSeconds (30). The Pod will be SIGKILLed mid-drain.
```

## 14.12 Subcharts and dependencies

```yaml
# Chart.yaml
dependencies:
  - name: postgresql
    version: "16.4.1"
    repository: "oci://registry-1.docker.io/bitnamicharts"
    condition: database.internal            # ⭐ enabled by this value
    tags: [database]

  - name: redis
    version: "20.5.0"
    repository: "oci://registry-1.docker.io/bitnamicharts"
    condition: cache.enabled

  - name: common
    version: "2.29.0"
    repository: "oci://registry-1.docker.io/bitnamicharts"
    tags: [library]                          # ⭐ a LIBRARY chart: templates only, no resources
```

```bash
helm dependency update ./shop
# Hang tight while we grab the latest from your chart repositories…
# …Successfully got an update from the "oci://registry-1.docker.io/bitnamicharts" chart repository
# Update Complete. ⎈Happy Helming!⎈
# Saving 3 charts
# Deleting outdated charts
ls shop/charts/
# common-2.29.0.tgz  postgresql-16.4.1.tgz  redis-20.5.0.tgz
```

**Pass values to a subchart by nesting under its name:**

```yaml
# values.yaml
postgresql:
  auth:
    username: shop
    existingSecret: shop-db-creds
    secretKeys: {adminPasswordKey: password, userPasswordKey: password}
  primary:
    persistence: {size: 10Gi, storageClass: gp3}
    resources:
      requests: {cpu: 500m, memory: 1Gi}
      limits:   {cpu: "2",   memory: 4Gi}
    podSecurityContext: {fsGroup: 1001, runAsUser: 1001}
  readReplicas:
    replicaCount: 2
```

**Share values across subcharts with `global`:**

```yaml
global:
  imageRegistry: ghcr.io          # every Bitnami subchart honours this
  storageClass: gp3
  postgresql:
    auth:
      password: "…"               # ← the Bitnami postgresql chart reads global.postgresql.auth.password
```

**A library chart** — templates other charts import:

```
common/
├── Chart.yaml          # type: library  ⭐ renders to NOTHING on its own
└── templates/
    ├── _probes.tpl
    ├── _resources.tpl
    └── _security.tpl
```

```gotemplate
{{/* common/templates/_probes.tpl */}}
{{- define "common.probes.http" -}}
{{- $p := .probe -}}
{{- if $p.enabled }}
{{ $p.kind | default "httpGet" }}:
  path: {{ $p.path }}
  port: {{ $p.port | default "http" }}
periodSeconds: {{ $p.periodSeconds | default 10 }}
failureThreshold: {{ $p.failureThreshold | default 3 }}
timeoutSeconds: {{ $p.timeoutSeconds | default 3 }}
{{- with $p.initialDelaySeconds }}
initialDelaySeconds: {{ . }}
{{- end }}
{{- end }}
{{- end -}}
```

```gotemplate
{{/* in the consuming chart */}}
readinessProbe:
  {{- include "common.probes.http" (dict "probe" .Values.api.readinessProbe) | nindent 12 }}
```

## 14.13 Publish the chart to GHCR

```bash
# OCI registries are now the standard. No more chartmuseum/index.yaml.
export CR_PAT=$(gh auth token)
echo "$CR_PAT" | helm registry login ghcr.io -u 3558Bhk --password-stdin

helm package ./shop
# Successfully packaged chart and saved it to: /home/user/k8s-learn/p14/shop-0.4.2.tgz

helm push shop-0.4.2.tgz oci://ghcr.io/3558bhk/charts
# Pushed: ghcr.io/3558bhk/charts/shop:0.4.2
# Digest: sha256:4a1f…

# install it from the registry, anywhere
helm pull oci://ghcr.io/3558bhk/charts/shop --version 0.4.2 --untar
helm install shop oci://ghcr.io/3558bhk/charts/shop --version 0.4.2 -n shop --create-namespace

# list what's there
crane ls ghcr.io/3558bhk/charts/shop
# 0.1.0  0.2.0  0.3.0  0.4.0  0.4.1  0.4.2  latest
```

**Sign it with cosign:**

```bash
cosign sign --yes ghcr.io/3558bhk/charts/shop@$(crane digest ghcr.io/3558bhk/charts/shop:0.4.2)
cosign verify ghcr.io/3558bhk/charts/shop@sha256:4a1f… \
  --certificate-identity-regexp="https://github.com/3558Bhk/.*" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com"
```

**CI:**

```yaml
# .github/workflows/chart.yaml
name: chart
on:
  push:
    paths: ['chart/**']
    branches: [main]

jobs:
  release:
    runs-on: ubuntu-24.04
    permissions: {contents: read, packages: write, id-token: write}
    steps:
      - uses: actions/checkout@v4
        with: {fetch-depth: 0}

      - uses: azure/setup-helm@v4
        with: {version: v3.17.0}

      - name: Lint
        run: helm lint ./chart --strict

      - name: Template + server-side dry run
        run: |
          helm template shop ./chart -f chart/values-dev.yaml > /tmp/out.yaml
          # spin up kind so we can do a REAL server-side validation
          kind create cluster --name lint --wait 5m
          kubectl apply --dry-run=server -f /tmp/out.yaml

      - name: Unit tests (helm-unittest)
        run: |
          helm plugin install https://github.com/helm-unittest/helm-unittest
          helm unittest ./chart

      - name: Bump the chart version if it changed
        id: bump
        run: |
          helm plugin install https://github.com/databus23/helm-git
          OLD=$(yq '.version' chart/Chart.yaml)
          # ct (chart-testing) detects whether the version needs a bump
          docker run --rm -v $PWD:/charts quay.io/helmpack/chart-testing:v3.11.0 \
            ct lint --chart-dirs chart --validate-chart-schema --validate-maintainers
          echo "version=$(yq '.version' chart/Chart.yaml)" >> "$GITHUB_OUTPUT"

      - name: Login & push
        run: |
          echo "${{ secrets.GITHUB_TOKEN }}" | helm registry login ghcr.io -u ${{ github.actor }} --password-stdin
          helm package ./chart -d /tmp
          helm push /tmp/shop-${{ steps.bump.outputs.version }}.tgz oci://ghcr.io/3558bhk/charts

      - uses: sigstore/cosign-installer@v3
      - name: Sign
        run: |
          DIGEST=$(crane digest ghcr.io/3558bhk/charts/shop:${{ steps.bump.outputs.version }})
          cosign sign --yes ghcr.io/3558bhk/charts/shop@$DIGEST
```

**Chart unit tests** (`chart/tests/deployment_test.yaml`):

```yaml
suite: api deployment
templates: [api/deployment.yaml]
release: {name: shop, namespace: shop}
tests:
  - it: should omit replicas when autoscaling is enabled
    set: {api.autoscaling.enabled: true, api.replicaCount: 3}
    asserts:
      - notExists: {path: spec.replicas}

  - it: should set replicas when autoscaling is disabled
    set: {api.autoscaling.enabled: false, api.replicaCount: 5}
    asserts:
      - equal: {path: spec.replicas, value: 5}

  - it: should have maxUnavailable 0 by default
    asserts:
      - equal: {path: spec.strategy.rollingUpdate.maxUnavailable, value: 0}

  - it: should include the config checksum annotation
    asserts:
      - isNotEmpty: {path: spec.template.metadata.annotations.checksum/config}

  - it: should drop all capabilities
    asserts:
      - contains:
          path: spec.template.spec.containers[0].securityContext.capabilities.drop
          content: ALL

  - it: should pin the image by digest when one is given
    set: {api.image.digest: "sha256:abc123"}
    asserts:
      - matchRegex: {path: spec.template.spec.containers[0].image, pattern: '@sha256:abc123$'}

  - it: should fail in prod with an internal database
    set: {global.environment: prod, database.internal: true}
    asserts:
      - failedTemplate:
          errorMessage: "database.internal=true is not allowed when global.environment=prod"
```

```bash
helm unittest ./chart
# ### Chart [ shop ] chart/
# PASS  api deployment      templates/api/deployment.yaml
# Tests:    7 passed, 0 failed
```

## 14.14 Helm vs Kustomize — and how to use both

| | Helm | Kustomize |
|---|---|---|
| Model | Templates + values | Base + patches (overlay) |
| Language | Go templates (a real language) | YAML only |
| Packaging/versioning | ✅ OCI registry, semver | ❌ just a directory |
| Distribution to others | ✅ `helm install mychart` | ⚠️ they need your repo |
| Hooks / ordering | ✅ pre-upgrade Jobs | ❌ |
| Tests | ✅ `helm test` | ❌ |
| Release tracking / rollback | ✅ revisions in Secrets | ❌ (Git does it) |
| Readability of the output | ⚠️ templates are hard to read | ✅ **what you see is what you get** |
| Debugging | `helm template --debug` | `kubectl kustomize` |
| Learning curve | Steeper | Gentler |
| Built into kubectl | ❌ (plugin) | ✅ `kubectl -k` |
| Best for | **Distributing** something to many users | **Your own** app across environments |

**The best answer: use both.** Helm for packaging, Kustomize for the final environment-specific overlay:

```bash
# render the chart, then apply a Kustomize overlay on top
helm template shop ./shop -f values-prod.yaml > base/rendered.yaml
kubectl apply -k overlays/prod/
```

`overlays/prod/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources: [../../base]
namespace: shop-prod
namePrefix: ""
labels:
  - pairs: {audit.example.com/tier: "1"}
    includeSelectors: false
patches:
  - target: {kind: Deployment, name: shop-api}
    patch: |-
      - op: add
        path: /spec/template/metadata/annotations/argocd.argoproj.io~1sync-wave
        value: "10"
```

**Argo CD does this natively** — see §14.20.

## 14.15 Helm debugging — the toolkit

```bash
# 1. render locally, no cluster needed
helm template shop ./shop --debug

# 2. render ONE template
helm template shop ./shop -s templates/api/deployment.yaml

# 3. render with a specific values file + overrides
helm template shop ./shop -f values-prod.yaml --set api.replicaCount=5

# 4. server-side validation (the real API checks it)
helm template shop ./shop | kubectl apply --dry-run=server -f -

# 5. see the exact error line
helm install shop ./shop --debug --dry-run 2>&1 | head -40
# Error: parse error at (shop/templates/api/deployment.yaml:47): unclosed action

# 6. dump the computed values (defaults + your file + --set, merged)
helm get values shop -n shop            # only what you passed
helm get values shop -n shop --all      # ⭐ EVERYTHING, including defaults

# 7. what's actually in the cluster
helm get manifest shop -n shop
helm get hooks    shop -n shop
helm get notes    shop -n shop
helm get all      shop -n shop

# 8. compare two revisions
helm get manifest shop -n shop --revision 3 > r3.yaml
helm get manifest shop -n shop --revision 4 > r4.yaml
diff -u r3.yaml r4.yaml

# 9. what did the last release change?
helm diff release shop -n shop

# 10. is the chart valid?
helm lint ./shop --strict
helm show values   ./shop      # print the default values
helm show chart    ./shop      # print Chart.yaml
helm show all      ./shop
helm show readme   ./shop

# 11. inspect a packaged chart
helm show values oci://ghcr.io/3558bhk/charts/shop --version 0.4.2
tar -tzf shop-0.4.2.tgz

# 12. template debugging inside a template
{{- printf "DEBUG api=%v img=%s" .Values.api.replicaCount $img | fail }}
# → Error: DEBUG api=3 img=ghcr.io/3558bhk/shop-api:1.4.0
{{- $_ := set . "debug" (printf "%v" .Values.api) -}}
{{- .debug | fail }}
```

**The five errors you'll hit most:**

| Error | Cause | Fix |
|---|---|---|
| `unclosed action` / `unexpected "}"` | A `{{-` without its `}}`, or a quote inside a quote | Look at the reported line **and the one before it** |
| `error converting YAML to JSON: yaml: line N: did not find expected key` | **Indentation.** `toYaml` without `nindent` | Always `{{- toYaml . | nindent 8 }}` |
| `nil pointer evaluating interface {}.foo` | A missing value | `{{- with .Values.x }}` or `{{ .Values.x.y | default "z" }}` or `required` |
| `cannot patch "x" … field is immutable` | You changed `spec.selector` on a Deployment | Delete the Deployment, or change the selector labels |
| `UPGRADE FAILED: "x" in version "v1" cannot be handled as a Deployment` | A resource changed `kind` | Delete the old resource first |

**The indentation rule, memorised:**

```gotemplate
{{- /* WRONG — toYaml starts on the current line, so the first key has no indent */}}
labels:
{{ toYaml .Values.labels }}

{{- /* RIGHT — nindent = newline, then N spaces */}}
labels:
  {{- toYaml .Values.labels | nindent 2 }}

{{- /* ALSO RIGHT — indent, but you must add the newline yourself */}}
labels:
{{ toYaml .Values.labels | indent 2 }}
```

`nindent 2` ≡ `"\n" + indent 2`. Use `nindent` — always.

**The `{{-` and `-}}` whitespace rule:**

```
{{-   trim whitespace BEFORE the action
 -}}  trim whitespace AFTER the action
```

```gotemplate
{{- if .Values.x }}
hello
{{- end }}
```
renders as `hello` with no blank lines. Without the dashes you get two newlines. **Always use `{{-` at the start of a line.**

## 14.16 Helm tasks

<details>
<summary>Task 14.1 — A ConfigMap change doesn't roll the Pods. Fix it, and explain the three ways to do it.</summary>

```bash
helm upgrade shop ./shop -n shop --set api.config.LOG_LEVEL_APP=DEBUG
kubectl get cm shop-api-config -n shop -o jsonpath='{.data.LOG_LEVEL_APP}'; echo
# DEBUG                                        ← the ConfigMap changed
kubectl get pods -n shop -l app.kubernetes.io/component=api \
  -o jsonpath='{.items[0].status.startTime}'; echo
# 2026-09-09T18:02:11Z                          ← ⛔ the Pod did NOT restart
kubectl exec -n shop deploy/shop-api -- env | grep LOG_LEVEL
# LOG_LEVEL_APP=INFO                            ← still the OLD value
```

**Why:** a Deployment's Pod template is unchanged, so Kubernetes sees nothing to do. Environment variables are read **once, at container start**. Mounted ConfigMap *files* do update (after up to ~1 minute), but env vars never do.

### Fix 1 — the checksum annotation (the standard answer)

```gotemplate
spec:
  template:
    metadata:
      annotations:
        checksum/config: {{ include (print $.Template.BasePath "/api/configmap.yaml") . | sha256sum }}
        checksum/secret: {{ include (print $.Template.BasePath "/db/secret.yaml") . | sha256sum }}
```

The Pod template now changes whenever the ConfigMap content changes → Kubernetes rolls the Deployment.

```bash
helm upgrade shop ./shop -n shop --set api.config.LOG_LEVEL_APP=DEBUG
kubectl get pods -n shop -l app.kubernetes.io/component=api \
  -o jsonpath='{.items[0].metadata.annotations.checksum/config}'; echo
# 4a1f8c2e…                                      ← a new hash
kubectl rollout status deploy/shop-api -n shop   ← ✅ it rolls
kubectl exec -n shop deploy/shop-api -- env | grep LOG_LEVEL
# LOG_LEVEL_APP=DEBUG                             ← ✅
```

⚠️ **Three gotchas:**
1. `include (print $.Template.BasePath "/api/configmap.yaml")` uses the **template path**, not the resource name. Get it wrong and Helm errors with `could not find template`.
2. It hashes the *rendered template output*, including metadata. A label change on the ConfigMap also triggers a rollout. Usually harmless.
3. It doesn't work for ConfigMaps from **subcharts** unless you reference their path: `include (print $.Template.BasePath "/charts/postgresql/templates/primary/configmap.yaml")`.

### Fix 2 — mount as files and watch them (no restart at all)

```yaml
envFrom: []                            # ⛔ env vars don't hot-reload
volumeMounts:
  - name: config
    mountPath: /app/config
    readOnly: true
volumes:
  - name: config
    configMap:
      name: shop-api-config
      items: [{key: application.yaml, path: application.yaml}]
```

Kubernetes updates the mounted file within ~1 minute (`syncFrequency` + cache TTL). Then the app must notice:

```java
// Spring Boot — @RefreshScope + actuator
@RefreshScope
@ConfigurationProperties("shop")
public class ShopProperties { … }

// trigger
curl -XPOST localhost:8080/actuator/refresh
```

```python
# Python — watch the file
import watchdog.observers, watchdog.events
class Reload(watchdog.events.FileSystemEventHandler):
    def on_modified(self, e): config.reload()
```

```go
// Go — fsnotify
w, _ := fsnotify.NewWatcher()
w.Add("/app/config/application.yaml")
for e := range w.Events { if e.Op&fsnotify.Write != 0 { cfg.Reload() } }
```

⚠️ Mounted ConfigMaps use **symlink indirection** (`..data` → `..2026_09_09/`). Watch the *directory*, not the file, or you'll miss updates.

### Fix 3 — `kubectl rollout restart` (the blunt instrument)

```bash
kubectl rollout restart deploy/shop-api -n shop
kubectl rollout status  deploy/shop-api -n shop
```

It works, but:
- It's manual, so it gets forgotten
- It restarts **everything**, not just the affected workload
- It doesn't compose with GitOps (Argo CD would immediately revert the annotation)

### Which to use

| Situation | Fix |
|---|---|
| Env-var config from a ConfigMap/Secret | **Checksum annotation** |
| Secrets (rotating a DB password) | **Checksum annotation** + the app must reconnect |
| Config the app can hot-reload | Mount as a file + a file watcher |
| A one-off during debugging | `kubectl rollout restart` |

**The Secret case is worse** — and it's where the checksum really earns its keep:

```bash
kubectl create secret generic rds-shop-creds -n shop \
  --from-literal=password='new-password' --dry-run=client -o yaml | kubectl apply -f -
# nothing happens. The Pods keep using the OLD password.
# Then the DB password rotates, and every Pod starts failing auth on its next reconnect.
```

With `checksum/secret` in the Pod annotations, the upgrade rolls the Pods and they pick up the new credential. **Without it, this is a silent, delayed, hard-to-diagnose outage.**

For automated rotation, use External Secrets Operator + Reloader:

```bash
helm install reloader stakater/reloader -n kube-system
```

```yaml
metadata:
  annotations:
    reloader.stakater.com/auto: "true"        # watches ConfigMaps AND Secrets
    secret.reloader.stakater.com/reload: "rds-shop-creds"
```

Reloader does the checksum trick for you, automatically, for any Deployment/StatefulSet/DaemonSet.

</details>

<details>
<summary>Task 14.2 — Package the chart so a colleague can install it in one command, with sane defaults and no surprises.</summary>

The acceptance test: **`helm install shop oci://ghcr.io/3558bhk/charts/shop` on a fresh kind cluster works, with zero `--set` flags.**

### 1. Make every default work out of the box

```bash
# on a clean cluster, with NO values file:
kind create cluster --name charttest --wait 5m
helm install shop ./shop --namespace shop --create-namespace --wait --timeout 10m
```

Everything that fails here is a defaulting bug. The common ones:

| Failure | Cause | Fix |
|---|---|---|
| `PersistentVolumeClaim "data-db-0" is not bound` | No default StorageClass | Document it, or use `emptyDir` when `persistence.enabled=false` |
| Ingress never gets an ADDRESS | No ingress controller installed | Make `ingress.enabled` default to **false** |
| `ServiceMonitor` CRD not found | No Prometheus Operator | `monitoring.serviceMonitor.enabled: false` by default |
| Image pull fails | `imagePullPolicy: Always` on a locally loaded image | Default to `IfNotPresent`; `Always` only for `:latest` |
| Pod stuck `Init:0/1` | `wait-for-db` waiting on a database that isn't enabled | Guard the init container with `{{- if .Values.database.enabled }}` |
| CrashLoopBackOff | A `required` value with no default | Provide a dev-friendly default, and `required` only in prod (via `shop.validate`) |

```bash
# install the prerequisites your chart assumes, and say so in the README
helm install ingress-nginx ingress-nginx/ingress-nginx -n ingress-nginx --create-namespace
```

### 2. Document every value

`chart/README.md`, generated so it never drifts:

```bash
helm plugin install https://github.com/norwoodj/helm-docs
helm-docs --chart-search-root ./chart --output-file README.md
```

```yaml
# values.yaml — helm-docs reads these comments
api:
  # -- Number of API replicas. **Must be 0 when `autoscaling.enabled=true`.**
  replicaCount: 3

  image:
    # -- Image repository, relative to `global.imageRegistry`/`global.imageRepository`
    repository: shop-api
    # -- Image tag. Defaults to `.Chart.AppVersion`. **Never `latest` in prod.**
    tag: ""
    # -- Image digest, e.g. `sha256:abc…`. When set, it overrides `tag`.
    digest: ""

  shutdown:
    # -- Seconds to sleep in `preStop`, letting endpoints propagate
    preStopSleepSeconds: 10
    # -- Total grace period. **Must exceed `preStopSleepSeconds + springGracefulShutdownSeconds`.**
    terminationGracePeriodSeconds: 60
```

Generated output:

```markdown
| Key | Type | Default | Description |
|-----|------|---------|-------------|
| api.replicaCount | int | `3` | Number of API replicas. **Must be 0 when `autoscaling.enabled=true`.** |
| api.image.tag | string | `""` | Image tag. Defaults to `.Chart.AppVersion`. **Never `latest` in prod.** |
| api.shutdown.terminationGracePeriodSeconds | int | `60` | Total grace period. **Must exceed…** |
```

### 3. Add a `crds/` directory (or refuse gracefully)

If your chart creates `ServiceMonitor`, `PrometheusRule`, `ScaledObject`, or `Application` resources, the CRDs must exist. Two options:

**Option A — `crds/` directory** (Helm installs them first, never upgrades or deletes them):

```
chart/
└── crds/
    └── monitoring.coreos.com-servicemonitors.yaml
```

⚠️ **Helm never upgrades files in `crds/`.** If you bump the CRD version, existing installs keep the old one. That's why most charts *don't* do this.

**Option B — a capability check** (the better answer):

```gotemplate
{{- if .Values.monitoring.serviceMonitor.enabled }}
{{- if not (.Capabilities.APIVersions.Has "monitoring.coreos.com/v1") }}
  {{- fail "monitoring.serviceMonitor.enabled=true but the Prometheus Operator CRDs are not installed. Install kube-prometheus-stack first, or set monitoring.serviceMonitor.enabled=false." }}
{{- end }}
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
…
{{- end }}
```

```bash
helm install shop ./shop --set monitoring.serviceMonitor.enabled=true
# Error: monitoring.serviceMonitor.enabled=true but the Prometheus Operator CRDs
#        are not installed. Install kube-prometheus-stack first, or set
#        monitoring.serviceMonitor.enabled=false.
```

Also check the Kubernetes version:

```gotemplate
{{- if semverCompare ">=1.25" .Capabilities.KubeVersion.Version }}
apiVersion: autoscaling/v2
{{- else }}
apiVersion: autoscaling/v2beta2
{{- end }}
```

### 4. Publish it

```bash
# version check — refuse to overwrite
helm show chart oci://ghcr.io/3558bhk/charts/shop --version 0.4.2 2>/dev/null \
  && { echo "0.4.2 already exists — bump Chart.yaml"; exit 1; }

helm lint ./chart --strict
helm unittest ./chart
helm package ./chart
helm push shop-0.4.2.tgz oci://ghcr.io/3558bhk/charts
cosign sign --yes ghcr.io/3558bhk/charts/shop@$(crane digest ghcr.io/3558bhk/charts/shop:0.4.2)
```

### 5. The README that makes it one command

````markdown
# shop

A Helm chart for the shop platform: React SPA + Spring Boot API + PostgreSQL.

## Quick start

```bash
# 1. prerequisites
kind create cluster --name shop
helm install ingress-nginx ingress-nginx/ingress-nginx \
  -n ingress-nginx --create-namespace --wait

# 2. install — no flags needed
helm install shop oci://ghcr.io/3558bhk/charts/shop \
  -n shop --create-namespace --wait --timeout 10m

# 3. see what you got
kubectl get pods,svc,ingress -n shop
helm test shop -n shop
```

Then add `127.0.0.1 shop.local` to `/etc/hosts` and open http://shop.local.

## Production

```bash
helm install shop oci://ghcr.io/3558bhk/charts/shop \
  -n shop-prod --create-namespace -f values-prod.yaml --atomic --timeout 15m
```

Production requires: an ingress controller, cert-manager, a Prometheus Operator,
an external database, and pinned image digests. The chart **fails fast** with a
clear message if any of these are missing.

## Values

See [README-values.md](./README-values.md) for the full, generated reference.

## Upgrading

```bash
helm upgrade shop oci://ghcr.io/3558bhk/charts/shop --version 0.5.0 -n shop -f values.yaml --atomic
helm history shop -n shop
helm rollback shop <REVISION> -n shop
```

## Uninstalling

```bash
helm uninstall shop -n shop --wait
kubectl delete pvc -n shop --all        # ⚠️ PVCs survive by design
```

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `pending-upgrade` forever | A pre-upgrade hook failed | `helm rollback shop -n shop` |
| Pods not restarting after a config change | No checksum annotation | See the docs on `checksum/config` |
| `field is immutable` | Selector labels changed | Delete the Deployment |
````

### 6. Prove it works for a stranger

```bash
# the acceptance test, in a throwaway container with no local state
docker run --rm -v $PWD:/work -w /work alpine/helm:3.17.0 sh -c '
  helm lint ./chart --strict &&
  helm template shop ./chart > /tmp/r.yaml &&
  echo "rendered $(grep -c "^kind:" /tmp/r.yaml) resources" &&
  helm show values ./chart | head -5'

# and on a truly fresh cluster
kind delete cluster --name charttest; kind create cluster --name charttest --wait 5m
helm install ingress-nginx ingress-nginx/ingress-nginx -n ingress-nginx --create-namespace --wait
helm install shop oci://ghcr.io/3558bhk/charts/shop -n shop --create-namespace --wait --timeout 10m
helm test shop -n shop
kubectl get pods -n shop
```

If that works with **zero `--set` flags**, the chart is done.

</details>

<details>
<summary>Task 14.3 — `helm upgrade` fails with "field is immutable". Diagnose and fix it without data loss.</summary>

```bash
helm upgrade shop ./shop -n shop -f values-prod.yaml
# Error: UPGRADE FAILED: cannot patch "shop-api" with kind Deployment:
#   Deployment.apps "shop-api" is invalid: spec.selector: Invalid value:
#   v1.LabelSelector{MatchLabels:map[string]string{
#     "app.kubernetes.io/component":"api",
#     "app.kubernetes.io/instance":"shop",
#     "app.kubernetes.io/name":"shop"},
#   MatchExpressions:[]v1.LabelSelectorRequirement(nil)}:
#   field is immutable
```

### Why

`spec.selector` on a Deployment, StatefulSet, ReplicaSet, and DaemonSet is **immutable after creation**. Kubernetes refuses to change it because it would orphan every existing Pod — the controller could no longer tell which Pods it owns.

You changed the labels in `shop.api.selectorLabels`. Usually by adding one:

```gotemplate
{{- define "shop.api.selectorLabels" -}}
app.kubernetes.io/name: {{ include "shop.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: api
app.kubernetes.io/version: {{ .Chart.AppVersion }}    ← ⛔ ADDED. Now immutable-changed.
{{- end }}
```

### Step 1 — confirm exactly what changed

```bash
helm get manifest shop -n shop --revision 3 > r3.yaml
helm template shop ./shop -f values-prod.yaml > r4.yaml
diff -u r3.yaml r4.yaml | grep -B4 -A8 'matchLabels'
```

```diff
   selector:
     matchLabels:
       app.kubernetes.io/component: api
       app.kubernetes.io/instance: shop
       app.kubernetes.io/name: shop
+      app.kubernetes.io/version: 1.5.0
```

Also check the live object:

```bash
kubectl get deploy shop-api -n shop -o jsonpath='{.spec.selector.matchLabels}' | jq .
kubectl get pods -n shop -l app.kubernetes.io/component=api --show-labels
```

### Step 2 — the rule, permanently

> **Selector labels must be the smallest possible stable set.** Version, chart, environment, team — none of those belong in a selector. They belong in `metadata.labels` only.

```gotemplate
{{- /* ⭐ SELECTOR labels: minimal, immutable forever */}}
{{- define "shop.api.selectorLabels" -}}
app.kubernetes.io/name: {{ include "shop.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: api
{{- end }}

{{- /* METADATA labels: everything else. Change these freely. */}}
{{- define "shop.api.labels" -}}
{{ include "shop.selectorLabels" . }}
helm.sh/chart: {{ include "shop.chart" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: {{ include "shop.fullname" . }}
app.kubernetes.io/environment: {{ .Values.global.environment }}
{{- end }}
```

⚠️ **`app.kubernetes.io/version` in a selector is a time bomb.** Every app upgrade changes it → every upgrade fails. Same for `helm.sh/chart` (changes with the chart version).

### Step 3 — fix the current breakage

**Option A — revert the label (best, no downtime).** Just remove the added line and re-run:

```bash
git revert <the commit that added it>
helm upgrade shop ./shop -n shop -f values-prod.yaml
# ✅ succeeds, because the rendered selector now matches the live one
```

**Option B — recreate the Deployment (brief downtime).** If you *must* change the selector:

```bash
# 1. record the current state so you can roll back
kubectl get deploy shop-api -n shop -o yaml > shop-api-backup.yaml
kubectl get rs -n shop -l app.kubernetes.io/component=api

# 2. check you have capacity for both to run at once
kubectl describe nodes | grep -A6 "Allocated resources"

# 3. orphan the Pods instead of deleting them (zero downtime!)
kubectl delete deploy shop-api -n shop --cascade=orphan
# The Pods KEEP RUNNING. They're just unmanaged now.

# 4. apply the new Deployment. It adopts Pods that match its NEW selector.
#    Old Pods don't match → they stay orphaned.
helm upgrade shop ./shop -n shop -f values-prod.yaml

# 5. new Pods come up, pass readiness, join the Service
kubectl get pods -n shop -l app.kubernetes.io/component=api -w

# 6. once the new Pods are Ready and serving, delete the orphans
kubectl get pods -n shop -o json | jq -r '
  .items[] | select(.metadata.ownerReferences == null) | .metadata.name'
kubectl delete pod -n shop <the orphaned ones>
```

`--cascade=orphan` is the key: the Deployment object goes away, the Pods and ReplicaSets stay, and traffic keeps flowing through the Service (which selects on labels, not ownership).

**Option C — a StatefulSet.** Worse. You can't orphan-and-adopt a StatefulSet safely, because the Pods have ordinal identities tied to PVCs:

```bash
# ⛔ do NOT do this without a full backup
kubectl delete sts shop-db -n shop --cascade=orphan
# the PVCs are named data-shop-db-0, data-shop-db-1…
# the new StatefulSet will try to CREATE them and find they already exist
# → it adopts them only if the labels match exactly
kubectl get pvc -n shop -l app.kubernetes.io/component=database --show-labels
# patch the labels FIRST so the new STS adopts them
kubectl label pvc -n shop data-shop-db-0 app.kubernetes.io/name=shop --overwrite
kubectl delete sts shop-db -n shop --cascade=orphan
helm upgrade …
```

Verify nothing was recreated empty:

```bash
kubectl exec -n shop shop-db-0 -- psql -U shop -d app -c 'SELECT count(*) FROM products;'
```

### Step 4 — prevent it in CI

```yaml
# chart/tests/selector_stability_test.yaml
suite: selector immutability
templates: [api/deployment.yaml, ui/deployment.yaml, db/statefulset.yaml]
tests:
  - it: api selector must contain exactly the three stable labels
    template: api/deployment.yaml
    asserts:
      - equal:
          path: spec.selector.matchLabels
          value:
            app.kubernetes.io/name: shop
            app.kubernetes.io/instance: RELEASE-NAME
            app.kubernetes.io/component: api

  - it: selector must NOT contain a version, chart, or environment label
    templates: [api/deployment.yaml, ui/deployment.yaml]
    asserts:
      - notExists: {path: spec.selector.matchLabels.app\.kubernetes\.io/version}
      - notExists: {path: spec.selector.matchLabels.helm\.sh/chart}
      - notExists: {path: spec.selector.matchLabels.app\.kubernetes\.io/environment}
```

```bash
# and in the pipeline, an explicit selector diff
helm template shop ./chart -f values-prod.yaml \
  | yq -r 'select(.kind=="Deployment" or .kind=="StatefulSet")
           | "\(.metadata.name) \(.spec.selector.matchLabels | tojson)"' > new-selectors.txt
kubectl get deploy,sts -n shop-prod -o json \
  | jq -r '.items[] | "\(.metadata.name) \(.spec.selector.matchLabels | tojson)"' > live-selectors.txt
diff live-selectors.txt new-selectors.txt \
  && echo "✅ selectors unchanged" \
  || { echo "⛔ a selector changed — this upgrade WILL fail"; exit 1; }
```

### Step 5 — the other immutable fields

| Field | Immutable on | Common cause |
|---|---|---|
| `spec.selector` | Deployment, StatefulSet, ReplicaSet, DaemonSet, Job | Adding a selector label |
| `spec.template.spec.containers[*].name` | Job | Renaming a container |
| `spec.volumeClaimTemplates` | StatefulSet | Changing size or storage class |
| `spec.clusterIP` | Service | Changing `clusterIP: None` after creation |
| `spec.type` | Service (some transitions) | ClusterIP → ExternalName |
| `spec.storageClassName` | PVC | Changing the StorageClass |
| `metadata.name` / `namespace` | Everything | A `namePrefix` change in Kustomize |
| `spec.jobTemplate.spec.template` | CronJob (in place, it's fine) | — |

```bash
# StatefulSet volumeClaimTemplates — the nastiest one
helm upgrade shop ./shop -n shop --set database.persistence.size=50Gi
# Error: StatefulSet.apps "shop-db" is invalid:
#   spec: Forbidden: updates to statefulset spec for fields other than
#   'replicas', 'ordinals', 'template', 'updateStrategy',
#   'persistentVolumeClaimRetentionPolicy' and 'minReadySeconds' are forbidden
```

You cannot resize a PVC through a StatefulSet. The path:

```bash
# 1. is the StorageClass expandable?
kubectl get sc gp3 -o jsonpath='{.allowVolumeExpansion}'; echo      # must be true

# 2. expand the PVC directly (the StatefulSet template stays at the old size)
kubectl patch pvc data-shop-db-0 -n shop -p '{"spec":{"resources":{"requests":{"storage":"50Gi"}}}}'
kubectl get pvc data-shop-db-0 -n shop -w
# the filesystem resize may need a Pod restart:
kubectl describe pvc data-shop-db-0 -n shop | grep -i condition
# FileSystemResizePending → delete the Pod, it comes back and resizes

# 3. ⚠️ now the STS template and the PVC disagree. Any Pod recreation
#    tries to make a 10Gi PVC. Fix the template WITHOUT touching the existing PVC:
#    update values.yaml, and add a `kubectl patch --subresource` workaround, or
#    accept the mismatch and document it.
```

The clean answer is to make the size a **non-templated** value the chart doesn't manage after first install, or to use `volumeClaimUpdatePolicy` (Kubernetes 1.27+, alpha/beta depending on version).

</details>

---

# PART B — GITOPS WITH ARGO CD

## 14.17 What GitOps actually means

**Four rules. That's the whole thing.**

| # | Rule | Consequence |
|---|---|---|
| 1 | **The entire desired state is in Git** | No `kubectl apply` by hand, ever |
| 2 | **Git is the only source of truth** | If it's not in Git, it shouldn't be in the cluster |
| 3 | **Changes happen by merging a PR** | Review, approval, audit trail, automatic |
| 4 | **An agent reconciles the cluster to Git** | Drift is detected and reverted |

**The push vs pull distinction:**

```
PUSH (CI/CD, e.g. Jenkins/GitHub Actions with kubectl):
  git push ──► CI builds ──► CI runs `kubectl apply` ──► cluster
                                    ▲
                       the CI system needs cluster-admin credentials

PULL (GitOps, e.g. Argo CD / Flux):
  git push ──► Git repo ◄──── argocd polls/watches ────► cluster
                                    ▲
                  the credentials live INSIDE the cluster, never in CI
```

**Why pull wins:**
- CI never holds cluster-admin credentials
- The cluster pulls from *your* Git — no inbound firewall hole
- Any change to the cluster (manual or otherwise) is detected as drift and reverted
- The reconciliation loop is continuous, not event-driven-and-hopeful

**Argo CD's model:**

```
Application (a CRD in the argocd namespace)
  ├── source:  a Git repo + path + (optionally) a Helm chart/values
  ├── destination: a cluster + namespace
  └── syncPolicy: automated? prune? selfHeal?

     ┌──────────────────────────────────────────┐
     │  Argo CD application controller          │
     │  every 3 min (or on a webhook):          │
     │    1. render the source                  │
     │    2. diff against the live cluster      │
     │    3. if different → OutOfSync           │
     │    4. if automated → apply               │
     │    5. if selfHeal → revert manual edits  │
     └──────────────────────────────────────────┘
```

Two statuses, always reported together:

| Status | Meaning |
|---|---|
| **Sync** = `Synced` / `OutOfSync` | Does the cluster match Git? |
| **Health** = `Healthy` / `Degraded` / `Progressing` | Are the resources actually working? |

`Synced + Degraded` is the important combination: **your Git is right and your cluster is broken.** Argo CD applied it correctly; the app itself is failing.

## 14.18 Install Argo CD

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
# or with Helm (better — you can configure it):
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm install argocd argo/argo-cd -n argocd --version 7.7.5 -f argocd-values.yaml
kubectl get pods -n argocd -w
```

```
argocd-application-controller-0   1/1   Running
argocd-applicationset-controller… 1/1   Running
argocd-dex-server-…               1/1   Running
argocd-notifications-controller-… 1/1   Running
argocd-redis-…                    1/1   Running
argocd-repo-server-…              1/1   Running
argocd-server-…                   1/1   Running
```

`argocd-values.yaml` — the parts that matter:

```yaml
global:
  domain: argocd.example.com

configs:
  params:
    server.insecure: true                # TLS terminates at the Ingress
  cm:
    # ⭐ the admin RBAC policy — do this FIRST, or you'll be locked out
    application.instanceLabelKey: argocd.argoproj.io/instance
    url: https://argocd.example.com
    exec.enabled: "true"                 # allows `argocd admin` actions
    statusbadge.enabled: "true"
    # timeout for slow Helm renders
    timeout.reconciliation: 180s
    resource.customizations: |
      networking.k8s.io/Ingress:
        health.lua: |
          hs = {}
          hs.status = "Progressing"
          hs.message = "Waiting for an address"
          if obj.status ~= nil then
            if obj.status.loadBalancer ~= nil then
              if obj.status.loadBalancer.ingress ~= nil then
                hs.status = "Healthy"
                hs.message = "Address assigned"
              end
            end
          end
          return hs
    resource.exclusions: |
      - apiGroups: ["cilium.io"]
        kinds: ["CiliumIdentity", "CiliumEndpoint"]
        clusters: ["*"]
  rbac:
    policy.default: role:readonly        # ⭐ deny by default
    policy.csv: |
      g, shop-developers, role:developer
      g, shop-admins, role:admin
      p, role:developer, applications, get, */*, allow
      p, role:developer, applications, sync, shop-dev/*, allow
      p, role:developer, logs, get, shop-dev/*, allow
      p, role:developer, clusters, get, *, allow
      p, role:admin, *, *, */*, allow
    scopes: "[groups, email]"

server:
  replicas: 2                            # HA
  ingress:
    enabled: true
    ingressClassName: nginx
    hostname: argocd.example.com
    tls: true
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-prod
      nginx.ingress.kubernetes.io/backend-protocol: HTTPS
      nginx.ingress.kubernetes.io/ssl-passthrough: "true"
  extraArgs: ["--insecure"]

controller:
  replicas: 2                            # HA with leader election

repoServer:
  replicas: 2
  autoscaling:
    enabled: true
    minReplicas: 2
    maxReplicas: 8
    targetCPUUtilizationPercentage: 70

applicationSet:
  replicas: 2

redis-ha:
  enabled: true                          # HA Redis for the cache

notifications:
  enabled: true
  notifiers:
    service.slack: |
      token: $slack-token
  triggers:
    trigger.on-deployed: |
      - description: Application synced
        when: app.status.operationState.phase in ['Succeeded']
        oncePer: app.status.sync.revision
        send: [app-deployed]
    trigger.on-health-degraded: |
      - description: Application degraded
        when: app.status.health.status == 'Degraded'
        send: [app-health-degraded]
  templates:
    template.app-deployed: |
      slack:
        attachments: |
          [{
            "title": "{{ .app.metadata.name }} deployed",
            "color": "#18be52",
            "fields": [
              {"title": "Sync Status", "value": "{{.app.status.sync.status}}", "short": true},
              {"title": "Repository",  "value": "{{.app.spec.source.repoURL}}", "short": true},
              {"title": "Revision",    "value": "{{.app.status.sync.revision | call .repo.RevisionMetadata .app.spec.source.repoURL}}", "short": true}
            ]
          }]
    template.app-health-degraded: |
      slack:
        attachments: |
          [{"title": "⚠️ {{ .app.metadata.name }} is DEGRADED", "color": "#E96D76"}]
  subscriptions:
    - recipients: [slack:shop-deploys]
      triggers: [on-deployed, on-health-degraded]

# ⭐ SSO via GitHub OIDC
dex:
  enabled: true
  config: |
    connectors:
      - type: github
        id: github
        name: GitHub
        config:
          clientID: $github-oauth-client-id
          clientSecret: $github-oauth-client-secret
          redirectURI: https://argocd.example.com/api/dex/callback
          orgs:
            - name: 3558Bhk-org

# high availability + PDBs
controller:
  pdb: {enabled: true, minAvailable: 1}
server:
  pdb: {enabled: true, minAvailable: 1}
repoServer:
  pdb: {enabled: true, minAvailable: 1}
```

```bash
helm install argocd argo/argo-cd -n argocd -f argocd-values.yaml --wait --timeout 10m

# initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo

# install the CLI
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x argocd && sudo mv argocd /usr/local/bin/
argocd version --client

# log in
argocd login argocd.example.com --username admin --password "$PW" --insecure
# or locally:
kubectl port-forward svc/argocd-server -n argocd 8080:443 &
argocd login localhost:8080 --username admin --password "$PW" --insecure --plaintext

argocd account get-user-info
argocd cluster list
argocd app list
```

**Delete the initial admin password Secret and set up SSO.** Leaving `argocd-initial-admin-secret` around is a real security finding.

```bash
kubectl -n argocd delete secret argocd-initial-admin-secret
argocd account update-password --current-password "$OLD" --new-password "$NEW"
```

## 14.19 The GitOps repository layout

```
shop-gitops/                                    ← the CONFIG repo (no application code)
├── bootstrap/
│   ├── root.yaml                               # the App-of-Apps — the ONLY thing you apply by hand
│   └── clusters/
│       ├── dev.yaml                            # one ApplicationSet per cluster
│       ├── staging.yaml
│       └── prod.yaml
├── platform/                                   # cluster-wide infrastructure
│   ├── ingress-nginx/
│   │   ├── application.yaml
│   │   └── values.yaml
│   ├── cert-manager/
│   ├── kube-prometheus-stack/
│   ├── loki/
│   ├── external-secrets/
│   ├── kyverno/
│   └── argo-rollouts/
├── apps/                                       # your applications
│   ├── shop/
│   │   ├── base/
│   │   │   └── application.yaml
│   │   └── overlays/
│   │       ├── dev/
│   │       │   ├── application.yaml
│   │       │   └── values.yaml
│   │       ├── staging/…
│   │       └── prod/
│   │           ├── application.yaml
│   │           └── values.yaml
│   └── shop-worker/…
├── projects/                                   # AppProject CRDs — multi-tenancy boundaries
│   ├── platform.yaml
│   ├── shop-dev.yaml
│   └── shop-prod.yaml
└── docs/
    └── runbooks/
```

**Two repos, not one:**

| Repo | Contains | Who writes to it |
|---|---|---|
| `shop` (application) | Source code, `Dockerfile`, `chart/` | Developers, via feature PRs |
| `shop-gitops` (config) | `Application` CRDs, per-environment `values.yaml`, image tags/digests | CI (image bump) + platform team |

Separating them means a developer merging a feature PR **cannot** accidentally deploy to production. Only the config repo can, and that has its own approvals.

### The App-of-Apps — `bootstrap/root.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root
  namespace: argocd
  finalizers: ["resources-finalizer.argocd.argoproj.io"]
spec:
  project: platform
  source:
    repoURL: https://github.com/3558Bhk/shop-gitops
    targetRevision: main
    path: bootstrap/clusters/prod
    directory:
      include: "*.yaml"
      recurse: false
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true          # ⭐ delete resources removed from Git
      selfHeal: true       # ⭐ revert manual `kubectl edit`
    syncOptions:
      - CreateNamespace=true
      - ApplyOutOfSyncOnly=true
      - ServerSideApply=true
      - RespectIgnoreDifferences=true
    retry:
      limit: 5
      backoff: {duration: 10s, factor: 2, maxDuration: 5m}
```

```bash
# the ONLY kubectl command you ever run by hand
kubectl apply -f bootstrap/root.yaml
```

Everything else cascades from there. **That's the whole bootstrap.**

### `bootstrap/clusters/prod.yaml`

```yaml
# ── platform components, in dependency order via sync waves ──
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: platform-ingress-nginx
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "-10"        # ⭐ first
  finalizers: ["resources-finalizer.argocd.argoproj.io"]
spec:
  project: platform
  source:
    repoURL: https://github.com/3558Bhk/shop-gitops
    targetRevision: main
    path: platform/ingress-nginx
  destination: {server: https://kubernetes.default.svc, namespace: ingress-nginx}
  syncPolicy:
    automated: {prune: true, selfHeal: true}
    syncOptions: [CreateNamespace=true, ServerSideApply=true]
    retry: {limit: 10, backoff: {duration: 30s, factor: 2, maxDuration: 10m}}
  # ⭐ don't report the whole app as degraded just because a webhook is slow
  ignoreDifferences:
    - group: admissionregistration.k8s.io
      kind: ValidatingWebhookConfiguration
      jsonPointers: ["/webhooks/0/failurePolicy"]
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: platform-cert-manager
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "-9"
spec:
  project: platform
  source: {repoURL: https://github.com/3558Bhk/shop-gitops, targetRevision: main, path: platform/cert-manager}
  destination: {server: https://kubernetes.default.svc, namespace: cert-manager}
  syncPolicy:
    automated: {prune: true, selfHeal: true}
    syncOptions: [CreateNamespace=true]
    retry: {limit: 10, backoff: {duration: 30s, factor: 2, maxDuration: 10m}}
  # ⭐ the CRDs must exist before the ClusterIssuers. Handle it with waves inside the chart,
  #   and skip the dry-run for resources whose CRD isn't installed yet.
    syncOptions: [CreateNamespace=true, SkipDryRunOnMissingResource=true]
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: platform-monitoring
  namespace: argocd
  annotations: {argocd.argoproj.io/sync-wave: "-8"}
spec:
  project: platform
  source: {repoURL: https://github.com/3558Bhk/shop-gitops, targetRevision: main, path: platform/kube-prometheus-stack}
  destination: {server: https://kubernetes.default.svc, namespace: monitoring}
  syncPolicy:
    automated: {prune: true, selfHeal: true}
    syncOptions: [CreateNamespace=true, ServerSideApply=true]
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: apps-prod
  namespace: argocd
  annotations: {argocd.argoproj.io/sync-wave: "0"}     # ⭐ after all platform components
spec:
  project: shop-prod
  source: {repoURL: https://github.com/3558Bhk/shop-gitops, targetRevision: main, path: apps/shop/overlays/prod}
  destination: {server: https://kubernetes.default.svc, namespace: shop-prod}
  syncPolicy:
    automated: {prune: true, selfHeal: true}
    syncOptions: [CreateNamespace=true, ServerSideApply=true]
```

**Sync waves** are the dependency-ordering mechanism Kubernetes doesn't have:

| Wave | What |
|---|---|
| `-10` | Namespaces, CRDs, the ingress controller |
| `-9` | cert-manager (needs its CRDs from wave -10) |
| `-8` | Monitoring, external-secrets, policy engines |
| `-5` | Secrets, ConfigMaps |
| `0` | Databases |
| `5` | Migrations |
| `10` | Application Deployments |
| `20` | Ingress, HPA, PDB |
| `100` | Tests |

Argo CD applies a wave, **waits for everything in it to become Healthy**, then moves to the next. If a wave fails, later waves never run.

### `platform/ingress-nginx/application.yaml` — Helm through Argo CD

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: platform-ingress-nginx
  namespace: argocd
  annotations: {argocd.argoproj.io/sync-wave: "-10"}
  finalizers: ["resources-finalizer.argocd.argoproj.io"]
spec:
  project: platform
  source:
    # ⭐ an upstream Helm chart, straight from the OCI registry
    repoURL: https://kubernetes.github.io/ingress-nginx
    chart: ingress-nginx
    targetRevision: 4.13.1                 # ⭐ the CHART version, pinned exactly
    helm:
      releaseName: ingress-nginx
      # values live in THIS repo, next to the Application
      valueFiles:
        - $values/platform/ingress-nginx/values.yaml
  # ⭐ the second source: your config repo, for the values file
  sources:
    - repoURL: https://kubernetes.github.io/ingress-nginx
      chart: ingress-nginx
      targetRevision: 4.13.1
      helm: {releaseName: ingress-nginx}
    - repoURL: https://github.com/3558Bhk/shop-gitops
      targetRevision: main
      ref: values                          # ⭐ referenced as $values below
  destination: {server: https://kubernetes.default.svc, namespace: ingress-nginx}
  syncPolicy:
    automated: {prune: true, selfHeal: true}
    syncOptions:
      - CreateNamespace=true
      - ApplyOutOfSyncOnly=true
      - ServerSideApply=true
    retry: {limit: 10, backoff: {duration: 30s, factor: 2, maxDuration: 10m}}
```

`platform/ingress-nginx/values.yaml`:

```yaml
controller:
  replicaCount: 3
  service:
    type: LoadBalancer
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-type: nlb
      service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing
  resources:
    requests: {cpu: 250m, memory: 256Mi}
    limits:   {cpu: "1",   memory: 1Gi}
  config:
    use-forwarded-headers: "true"
    compute-full-forwarded-for: "true"
    use-http2: "true"
    ssl-protocols: "TLSv1.2 TLSv1.3"
    upstream-keepalive-connections: "320"
    log-format-upstream: '$remote_addr - $remote_user [$time_local] "$request" $status $body_bytes_sent "$http_referer" "$http_user_agent" $request_length $request_time [$proxy_upstream_name] [$proxy_alternative_upstream_name] $upstream_addr $upstream_response_length $upstream_response_time $upstream_status $req_id'
  metrics:
    enabled: true
    serviceMonitor:
      enabled: true
      namespace: monitoring
      namespaceSelector: {any: true}
  admissionWebhooks:
    enabled: true
    patch:
      enabled: true
  autoscaling:
    enabled: true
    minReplicas: 3
    maxReplicas: 10
    targetCPUUtilizationPercentage: 70
  topologySpreadConstraints:
    - maxSkew: 1
      topologyKey: topology.kubernetes.io/zone
      whenUnsatisfiable: ScheduleAnyway
      labelSelector:
        matchLabels: {app.kubernetes.io/name: ingress-nginx, app.kubernetes.io/component: controller}
  affinity:
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
        - weight: 100
          podAffinityTerm:
            labelSelector: {matchLabels: {app.kubernetes.io/name: ingress-nginx, app.kubernetes.io/component: controller}}
            topologyKey: kubernetes.io/hostname
```

### `apps/shop/overlays/prod/application.yaml` — your own chart

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: shop-prod
  namespace: argocd
  labels: {team: shop, environment: prod}
  annotations:
    argocd.argoproj.io/sync-wave: "10"
    notifications.argoproj.io/subscribe.on-deployed.slack: shop-deploys
  finalizers: ["resources-finalizer.argocd.argoproj.io"]
spec:
  project: shop-prod

  sources:
    # 1. YOUR chart, from the OCI registry, pinned by version
    - repoURL: ghcr.io/3558bhk/charts
      chart: shop
      targetRevision: 0.4.2                  # ⭐ bump this in a PR to release
      helm:
        releaseName: shop
        valueFiles:
          - $config/apps/shop/overlays/prod/values.yaml
        parameters:
          # ⭐ the image digest is set by CI — see §14.21
          - name: api.image.digest
            value: ""
          - name: ui.image.digest
            value: ""

    # 2. the config repo, providing the values file
    - repoURL: https://github.com/3558Bhk/shop-gitops
      targetRevision: main
      ref: config

  destination:
    server: https://kubernetes.default.svc
    namespace: shop-prod

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ApplyOutOfSyncOnly=true
      - ServerSideApply=true
      - RespectIgnoreDifferences=true
      # ⭐ run the pre-upgrade migration hook and WAIT for it
      - Replace=false
    retry:
      limit: 5
      backoff: {duration: 30s, factor: 2, maxDuration: 15m}
    managedNamespaceMetadata:
      labels:
        pod-security.kubernetes.io/enforce: baseline
        team: shop
      annotations:
        owner: shop-team

  # ⭐ things that legitimately differ between Git and the cluster
  ignoreDifferences:
    # the HPA changes replicas; Git shouldn't fight it
    - group: apps
      kind: Deployment
      jsonPointers: ["/spec/replicas"]
    # cert-manager writes the issued cert into the Secret
    - group: ""
      kind: Secret
      jsonPointers: ["/data/tls.crt", "/data/tls.key", "/data/ca.crt"]
    # the admission webhook patches itself
    - group: admissionregistration.k8s.io
      kind: ValidatingWebhookConfiguration
      jqPathExpressions: [".webhooks[]?.clientConfig.caBundle"]
    # KEDA owns the HPA it creates
    - group: autoscaling
      kind: HorizontalPodAutoscaler
      jsonPointers: ["/spec/minReplicas", "/spec/maxReplicas"]

  revisionHistoryLimit: 20

  # ⭐ don't sync on every commit — sync on tags, and require an approval
  info:
    - name: Runbook
      value: https://wiki.internal/runbooks/shop-prod
    - name: Slack
      value: "#shop-oncall"
    - name: Owner
      value: Harish Kumar Brahmandam
```

> 🔑 **`ignoreDifferences` for `/spec/replicas` is essential when an HPA is active.** Without it, Argo CD keeps setting `replicas: 6` from Git while the HPA sets it to 20 — an infinite fight that shows as a permanently `OutOfSync` app and constant rollouts. Better still: omit `replicas` from the chart entirely when autoscaling is on (§14.5).

### AppProjects — the multi-tenancy boundary

```yaml
# projects/shop-prod.yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: shop-prod
  namespace: argocd
  finalizers: ["resources-finalizer.argocd.argoproj.io"]
spec:
  description: The shop platform, production environment

  # ⭐ WHERE this project may deploy
  destinations:
    - server: https://kubernetes.default.svc
      namespace: shop-prod
    - server: https://kubernetes.default.svc
      namespace: monitoring        # for ServiceMonitors

  # ⭐ WHERE the manifests may come from
  sourceRepos:
    - https://github.com/3558Bhk/shop-gitops
    - ghcr.io/3558bhk/charts
    - https://kubernetes.github.io/ingress-nginx

  # ⭐ WHAT KINDS of resources — deny the dangerous ones
  clusterResourceWhitelist:
    - group: ""
      kind: Namespace
    - group: networking.k8s.io
      kind: IngressClass
  namespaceResourceBlacklist:
    - group: ""
      kind: ResourceQuota          # managed by the platform project only
    - group: ""
      kind: LimitRange
    - group: rbac.authorization.k8s.io
      kind: "*"                    # ⭐ no RBAC from app projects
    - group: ""
      kind: Secret                 # ⭐ no raw Secrets — use External Secrets
  namespaceResourceWhitelist:
    - group: ""
      kind: "*"
    - group: apps
      kind: "*"
    - group: batch
      kind: "*"
    - group: networking.k8s.io
      kind: "*"
    - group: autoscaling
      kind: "*"
    - group: policy
      kind: "*"
    - group: monitoring.coreos.com
      kind: "*"

  # ⭐ WHO may do what
  roles:
    - name: developer
      description: Can view and sync dev/staging
      policies:
        - p, proj:shop-prod:developer, applications, get, shop-prod/*, allow
        - p, proj:shop-prod:developer, applications, sync, shop-prod/*, allow
        - p, proj:shop-prod:developer, logs, get, shop-prod/*, allow
        - p, proj:shop-prod:developer, exec, create, shop-prod/*, deny     # ⭐ no shells in prod
      groups: [shop-developers]

    - name: release-manager
      description: Full control, requires approval for destructive ops
      policies:
        - p, proj:shop-prod:release-manager, applications, *, shop-prod/*, allow
      groups: [shop-admins]

    - name: readonly
      description: Dashboard viewers
      policies:
        - p, proj:shop-prod:readonly, applications, get, shop-prod/*, allow
      groups: [shop-viewers]

  # ⭐ maintenance windows — no syncs during the freeze
  syncWindows:
    - kind: deny
      schedule: "0 0 * * 1-5"          # midnight weekdays
      duration: 6h
      applications: ["*"]
      namespaces: ["shop-prod"]
      manualSync: false                # ⭐ blocks manual syncs too
    - kind: allow
      schedule: "0 9 * * 1-4"          # Mon-Thu 09:00
      duration: 8h
      applications: ["*"]
      namespaces: ["shop-prod"]
      manualSync: true
    - kind: allow                      # emergencies, always
      schedule: "0 0 * * *"
      duration: 24h
      applications: ["shop-hotfix-*"]
      namespaces: ["shop-prod"]
      manualSync: true

  # ⭐ signature verification
  signatureKeys:
    - keyID: C8D9E0F1A2B3C4D5E6F7081920A1B2C3D4E5F607

  # orphaned resource detection — find things in the namespace Git doesn't know about
  orphanedResources:
    warn: true
    ignore:
      - group: ""
        kind: "Secret"
        name: "default-token-*"
      - group: "monitoring.coreos.com"
        kind: "*"
```

```bash
argocd proj list
argocd proj get shop-prod
argocd proj allow-cluster-resource shop-prod '*' Namespace
argocd proj add-destination shop-prod https://kubernetes.default.svc shop-prod
argocd proj add-source shop-prod https://github.com/3558Bhk/shop-gitops
argocd proj add-role shop-prod developer --policy 'p, proj:shop-prod:developer, applications, get, shop-prod/*, allow'
```

**Orphaned resources** is one of the most useful features nobody turns on:

```bash
argocd app get shop-prod --show-operation
# Orphaned resources:
#   ConfigMap/shop-prod/legacy-config     ← created by hand, Git doesn't know about it
#   Secret/shop-prod/db-creds-old         ← left over from a migration
```

`prune: true` does **not** delete orphans (they were never in Git). You must delete them manually — and now you know they exist.

## 14.20 The sync in practice

```bash
# ── status ──
argocd app list
# NAME              CLUSTER                         NAMESPACE   PROJECT    STATUS     HEALTH
# root              https://kubernetes.default.svc  argocd      platform   Synced     Healthy
# platform-ingress  https://kubernetes.default.svc  ingress-…   platform   Synced     Healthy
# shop-prod         https://kubernetes.default.svc  shop-prod   shop-prod  OutOfSync  Healthy

argocd app get shop-prod
# Name:               shop-prod
# Project:            shop-prod
# Server:             https://kubernetes.default.svc
# Namespace:          shop-prod
# URL:                https://argocd.example.com/applications/shop-prod
# Source:
#   Type:             Helm
#   Repo:             ghcr.io/3558bhk/charts
#   Chart:            shop
#   Target Revision:  0.4.3
# Sync Policy:        Automated
# Sync Status:        OutOfSync from  (0.4.3)
# Health Status:      Healthy
#
# GROUP                      KIND              NAMESPACE   NAME            STATUS     HEALTH
# apps                       Deployment        shop-prod   shop-api        OutOfSync  Healthy
# v1                         Service           shop-prod   shop-api        Synced     Healthy
# autoscaling                HorizontalPod…    shop-prod   shop-api        Synced     Healthy

# ── the diff: exactly what will change ──
argocd app diff shop-prod
# ===== Deployment/shop-prod/shop-api ======
# 65c65
# <           image: ghcr.io/3558bhk/shop-api@sha256:1a2b…
# ---
# >           image: ghcr.io/3558bhk/shop-api@sha256:9f2a…

argocd app diff shop-prod --local ./chart -f values-prod.yaml    # diff against a LOCAL render

# ── sync manually ──
argocd app sync shop-prod
argocd app sync shop-prod --revision 0.4.3 --prune --timeout 600
argocd app sync shop-prod --resource group:apps,kind:Deployment,name:shop-api   # one resource
argocd app sync shop-prod --dry-run                                             # show, don't apply
argocd app wait shop-prod --health --sync --timeout 600

# ── watch the rollout ──
argocd app logs shop-prod --kind Deployment --name shop-api --tail 50 -f
argocd app resources shop-prod
argocd app get shop-prod -o json | jq '.status.resources[] | {kind, name, status, health}'

# ── history & rollback ──
argocd app history shop-prod
# ID  DATE                           REVISION
# 0   2026-09-01 10:14:22 +0000 UTC  0.4.0 (1a2b3c4)
# 1   2026-09-05 14:02:11 +0000 UTC  0.4.1 (5d6e7f8)
# 2   2026-09-09 09:31:44 +0000 UTC  0.4.2 (9a8b7c6)

argocd app rollback shop-prod 1
# ⚠️ this is a SYNC to an old revision, NOT a Git revert.
#    With automated sync + selfHeal, Argo CD will immediately re-sync to main.
#    You MUST disable automated sync first:
argocd app set shop-prod --sync-policy none
argocd app rollback shop-prod 1
# … then fix Git, re-enable:
argocd app set shop-prod --sync-policy automated --auto-prune --self-heal
```

> 🔑 **In GitOps, the rollback is `git revert`, not `argocd app rollback`.** The CLI rollback is for emergencies only, and it *will* be undone by selfHeal. Do this:
> ```bash
> # the RIGHT rollback
> cd shop-gitops
> git revert <the bad commit>          # or revert the tag bump
> git push
> argocd app wait shop-prod --sync --health --timeout 600
> ```

## 14.21 The CI pipeline — build, sign, bump Git

**This is the whole GitOps loop. CI never touches the cluster.**

```yaml
# .github/workflows/deploy.yaml  (in the APPLICATION repo)
name: build-and-bump
on:
  push:
    tags: ['v*']

env:
  REGISTRY: ghcr.io
  IMAGE_REPO: ghcr.io/3558bhk/shop-api
  GITOPS_REPO: 3558Bhk/shop-gitops

permissions:
  contents: read
  packages: write
  id-token: write            # ⭐ for cosign keyless signing

jobs:
  build:
    runs-on: ubuntu-24.04
    outputs:
      digest: ${{ steps.push.outputs.digest }}
      version: ${{ steps.meta.outputs.version }}
    steps:
      - uses: actions/checkout@v4

      - uses: docker/setup-buildx-action@v3

      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.IMAGE_REPO }}
          tags: |
            type=semver,pattern={{version}}
            type=sha,prefix=sha-

      - id: push
        uses: docker/build-push-action@v6
        with:
          context: ./api
          platforms: linux/amd64,linux/arm64
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          build-args: GIT_SHA=${{ github.sha }}
          provenance: true
          sbom: true
          cache-from: type=gha
          cache-to: type=gha,mode=max

      # ── scan ──
      - uses: aquasecurity/trivy-action@0.28.0
        with:
          image-ref: ${{ env.IMAGE_REPO }}@${{ steps.push.outputs.digest }}
          severity: CRITICAL,HIGH
          ignore-unfixed: true
          exit-code: 1
          format: sarif
          output: trivy.sarif
      - uses: github/codeql-action/upload-sarif@v3
        with: {sarif_file: trivy.sarif}

      # ── sign (keyless, via OIDC — no long-lived secrets) ──
      - uses: sigstore/cosign-installer@v3
      - run: |
          cosign sign --yes \
            --annotation "sha=${{ github.sha }}" \
            --annotation "workflow=${{ github.workflow }}" \
            ${{ env.IMAGE_REPO }}@${{ steps.push.outputs.digest }}
          cosign attest --yes --predicate sbom.spdx.json --type spdxjson \
            ${{ env.IMAGE_REPO }}@${{ steps.push.outputs.digest }}

  # ══════════════════════════════════════════════════════════
  # ⭐ THE ONLY STEP THAT CHANGES WHAT'S DEPLOYED:
  #    a commit to the GitOps repo. No kubectl. No cluster credentials.
  # ══════════════════════════════════════════════════════════
  bump-dev:
    needs: build
    runs-on: ubuntu-24.04
    environment: development            # ⭐ a GitHub Environment = its own approvals
    steps:
      - uses: actions/checkout@v4
        with:
          repository: ${{ env.GITOPS_REPO }}
          token: ${{ secrets.GITOPS_PAT }}
          path: gitops

      - name: Update the dev digest
        working-directory: gitops
        run: |
          FILE=apps/shop/overlays/dev/values.yaml
          yq -i '.api.image.digest = "${{ needs.build.outputs.digest }}"' $FILE
          yq -i '.api.image.tag    = "${{ needs.build.outputs.version }}"' $FILE
          git diff

      - uses: stefanzweifel/git-auto-commit-action@v5
        with:
          repository: gitops
          commit_message: |
            chore(dev): shop-api → ${{ needs.build.outputs.version }}

            image: ${{ env.IMAGE_REPO }}@${{ needs.build.outputs.digest }}
            source: ${{ github.server_url }}/${{ github.repository }}/commit/${{ github.sha }}
          commit_user_name: argocd-bot
          commit_user_email: bot@3558bhk.dev
          branch: main                   # ⭐ dev auto-deploys on push to main

  open-staging-pr:
    needs: build
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v4
        with: {repository: '${{ env.GITOPS_REPO }}', token: '${{ secrets.GITOPS_PAT }}', path: gitops}

      - name: Branch + edit + PR
        working-directory: gitops
        run: |
          BR=staging/shop-api-${{ needs.build.outputs.version }}
          git checkout -b $BR
          FILE=apps/shop/overlays/staging/values.yaml
          yq -i '.api.image.digest = "${{ needs.build.outputs.digest }}"' $FILE
          yq -i '.api.image.tag    = "${{ needs.build.outputs.version }}"' $FILE
          git add -A && git commit -m "chore(staging): shop-api → ${{ needs.build.outputs.version }}"
          git push origin $BR

          gh pr create --base main --head $BR \
            --title "chore(staging): shop-api → ${{ needs.build.outputs.version }}" \
            --body "$(cat <<'BODY'
          ## What changes
          Bumps the **staging** API image.

          | | |
          |---|---|
          | Version | `${{ needs.build.outputs.version }}` |
          | Digest  | `${{ needs.build.outputs.digest }}` |
          | Source  | ${{ github.server_url }}/${{ github.repository }}/commit/${{ github.sha }}` |

          ## Pre-merge checks
          - [ ] `argocd app diff shop-staging` reviewed
          - [ ] CI green on the application repo
          - [ ] Trivy found no CRITICAL/HIGH
          - [ ] Image is cosign-signed

          ## After merge
          Argo CD syncs staging automatically. Watch:
          `argocd app wait shop-staging --health --sync --timeout 600`
          BODY
          )"
        env:
          GH_TOKEN: ${{ secrets.GITOPS_PAT }}

  promote-to-prod:
    needs: build
    runs-on: ubuntu-24.04
    environment: production             # ⭐⭐ REQUIRES A HUMAN APPROVAL
    if: startsWith(github.ref, 'refs/tags/v')
    steps:
      - uses: actions/checkout@v4
        with: {repository: '${{ env.GITOPS_REPO }}', token: '${{ secrets.GITOPS_PAT }}', path: gitops}
      - name: Branch + PR (prod needs a review)
        working-directory: gitops
        run: |
          BR=prod/shop-api-${{ needs.build.outputs.version }}
          git checkout -b $BR
          yq -i '.api.image.digest = "${{ needs.build.outputs.digest }}"
                 | .api.image.tag    = "${{ needs.build.outputs.version }}"' \
                 apps/shop/overlays/prod/values.yaml
          git add -A && git commit -m "chore(prod): shop-api → ${{ needs.build.outputs.version }}"
          git push origin $BR
          gh pr create --base main --head $BR \
            --title "🚀 chore(prod): shop-api → ${{ needs.build.outputs.version }}" \
            --label "production,release" \
            --reviewer 3558Bhk \
            --body "Digest: \`${{ needs.build.outputs.digest }}\`
          Staging soak: https://argocd.example.com/applications/shop-staging
          Runbook: https://wiki.internal/runbooks/shop-prod-deploy"
        env: {GH_TOKEN: '${{ secrets.GITOPS_PAT }}'}
```

**The promotion chain:**

```
git tag v1.5.0 && git push --tags
        │
        ▼
  ┌─────────────────┐
  │ build + scan    │  Trivy, cosign sign, SBOM attestation
  │ + sign          │
  └────────┬────────┘
           │ digest: sha256:9f2a…
           ▼
  ┌─────────────────┐
  │ bump DEV        │  direct commit to main → Argo CD syncs dev in ~3 min
  └────────┬────────┘
           │ soak for a day
           ▼
  ┌─────────────────┐
  │ open STAGING PR │  a human reviews the diff → merge → Argo CD syncs
  └────────┬────────┘
           │ soak for a day
           ▼
  ┌─────────────────┐
  │ open PROD PR    │  GitHub Environment "production" requires approval
  └────────┬────────┘  + a required reviewer + the sync window allows it
           │ merge
           ▼
     Argo CD syncs prod
```

**Why this design:**
- CI has **no cluster credentials at all**. Only a Git token.
- Every environment change is a **commit with a diff, an author, and a message**.
- Promotion is a **PR merge**, so it's reviewable and reversible.
- The image is pinned **by digest**, so the same bytes you tested are what runs.

## 14.22 Drift detection — the payoff

```bash
# someone "fixes" something by hand at 2am
kubectl scale deploy/shop-api -n shop-prod --replicas=20
kubectl set env deploy/shop-api -n shop-prod LOG_LEVEL_APP=DEBUG

# within 3 minutes (or instantly, with a webhook):
argocd app get shop-prod
# Sync Status:    OutOfSync
# Health Status:  Healthy

argocd app diff shop-prod
# ===== Deployment/shop-prod/shop-api ======
# 24c24
# <   replicas: 20
# ---
# >   replicas: 6
# 61a62
# >           - name: LOG_LEVEL_APP
# >             value: DEBUG

# selfHeal reverts it automatically — no action needed
kubectl get deploy shop-api -n shop-prod -o jsonpath='{.spec.replicas}'; echo
# 6                                  ← ✅ reverted
kubectl exec -n shop-prod deploy/shop-api -- env | grep LOG_LEVEL
# LOG_LEVEL_APP=INFO                 ← ✅ reverted
```

**Argo CD found and fixed an unreviewed production change within three minutes.** That's the entire value proposition in one demo.

**See the drift events:**

```bash
argocd app get shop-prod -o json | jq '.status.conditions'
kubectl get events -n argocd --field-selector involvedObject.name=shop-prod --sort-by=.lastTimestamp | tail
argocd admin settings rbac can I sync applications 'shop-prod/*'
```

**Turn on a webhook so it's instant instead of every 3 minutes:**

```yaml
# in the argocd-cm ConfigMap
data:
  webhook.github.secret: <a random string>
```

```yaml
# in the application repo → Settings → Webhooks
# Payload URL: https://argocd.example.com/api/webhook
# Content type: application/json
# Secret: <the same string>
```

**And alert on drift** — you want to know *why* someone changed it:

```yaml
- alert: ArgoCDAppOutOfSync
  expr: argocd_app_sync_status == 0
  for: 15m
  labels: {severity: warning}
  annotations:
    summary: "{{ $labels.name }} has been OutOfSync for 15m"
    description: "selfHeal should have fixed this. If it hasn't, someone disabled automation or a resource is failing to apply."

- alert: ArgoCDAppDegraded
  expr: argocd_app_health_status{health_status="Degraded"} == 1
  for: 5m
  labels: {severity: critical}
  annotations: {summary: "{{ $labels.name }} is Degraded"}

- alert: ArgoCDAutomatedSyncDisabled
  expr: argocd_app_spec_sync_policy_automated == 0
  for: 1h
  labels: {severity: warning}
  annotations:
    summary: "{{ $labels.name }} has automated sync DISABLED"
    description: "Someone turned it off, usually to make a manual change. Re-enable it: argocd app set <name> --sync-policy automated --auto-prune --self-heal"
```

## 14.23 ApplicationSets — one template, many apps

Instead of 40 near-identical `Application` manifests:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: shop-environments
  namespace: argocd
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]

  generators:
    # ── generate one Application per entry in this list ──
    - list:
        elements:
          - {env: dev,     cluster: https://kubernetes.default.svc, ns: shop-dev,     wave: "10", sync: auto}
          - {env: staging, cluster: https://kubernetes.default.svc, ns: shop-staging, wave: "10", sync: auto}
          - {env: prod,    cluster: https://prod-cluster.example,  ns: shop-prod,    wave: "10", sync: manual}

  template:
    metadata:
      name: 'shop-{{.env}}'
      namespace: argocd
      labels: {team: shop, environment: '{{.env}}'}
      annotations:
        argocd.argoproj.io/sync-wave: '{{.wave}}'
      finalizers: ["resources-finalizer.argocd.argoproj.io"]
    spec:
      project: 'shop-{{.env}}'
      sources:
        - repoURL: ghcr.io/3558bhk/charts
          chart: shop
          targetRevision: 0.4.2
          helm:
            releaseName: shop
            valueFiles: ['$config/apps/shop/overlays/{{.env}}/values.yaml']
        - repoURL: https://github.com/3558Bhk/shop-gitops
          targetRevision: main
          ref: config
      destination:
        server: '{{.cluster}}'
        namespace: '{{.ns}}'
      syncPolicy:
        {{- if eq .sync "auto" }}
        automated: {prune: true, selfHeal: true}
        {{- end }}
        syncOptions: [CreateNamespace=true, ApplyOutOfSyncOnly=true, ServerSideApply=true]
        retry: {limit: 5, backoff: {duration: 30s, factor: 2, maxDuration: 15m}}
```

**Git-files generator** — apps defined by the directory structure:

```yaml
  generators:
    - git:
        repoURL: https://github.com/3558Bhk/shop-gitops
        revision: main
        directories:
          - path: apps/*                 # apps/shop, apps/worker, apps/admin
          - path: apps/*/overlays/*      # apps/shop/overlays/dev, …/prod
            exclude: false
```

**Cluster generator** — deploy the platform to every registered cluster:

```yaml
  generators:
    - clusters:
        selector:
          matchLabels: {platform: "true"}
        values:
          region: '{{metadata.labels.topology.kubernetes.io.region}}'
```

```bash
kubectl apply -f applicationset.yaml
argocd appset list
argocd appset get shop-environments
argocd app list | grep shop
# shop-dev        …  Synced     Healthy
# shop-staging    …  Synced     Healthy
# shop-prod       …  Synced     Healthy
```

⚠️ **ApplicationSets with `prune: true` will delete Applications** whose generator entry you removed — which cascades to deleting all their resources. Set `preserveResourcesOnDeletion: true` while you're learning:

```yaml
spec:
  syncPolicy:
    preserveResourcesOnDeletion: true     # ⭐ removing an app from the set does NOT delete its resources
```

## 14.24 Progressive delivery with Argo Rollouts

A blue/green or canary release, driven from the same Git repo.

```bash
helm install argo-rollouts argo/argo-rollouts -n argo-rollouts --create-namespace
kubectl argo rollouts version
```

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: shop-api
  namespace: shop-prod
spec:
  replicas: 6
  selector:
    matchLabels:
      {{- include "shop.api.selectorLabels" . | nindent 6 }}
  strategy:
    canary:
      canaryService: shop-api-canary
      stableService: shop-api-stable
      trafficRouting:
        nginx:
          stableIngress: shop-api            # the existing Ingress
          additionalIngressAnnotations:
            canary-by-header: X-Canary
      analysis:
        templates:
          - templateName: success-rate
        startingStep: 2                       # start measuring after the first step
      steps:
        - setWeight: 5
        - pause: {duration: 2m}               # ⭐ automatic: wait 2 minutes
        - setWeight: 20
        - pause: {}                           # ⭐ MANUAL: requires `kubectl argo rollouts promote`
        - setWeight: 50
        - analysis:
            templates: [{templateName: latency}]
            args: [{name: service-name, value: shop-api-canary}]
        - pause: {duration: 10m}
        - setWeight: 100
      # ⭐ automatic rollback if the analysis fails
      abortScaleDownDelaySeconds: 30
---
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: success-rate
  namespace: shop-prod
spec:
  args:
    - {name: service-name}
  metrics:
    - name: success-rate
      interval: 30s
      count: 10
      successCondition: result[0] >= 0.995       # ⭐ 99.5% success
      failureLimit: 3
      provider:
        prometheus:
          address: http://kps-kube-p-prometheus.monitoring:9090
          query: |
            sum(irate(
              http_server_requests_seconds_count{application="shop-api",status!~"5.."}[2m]
            ))
            /
            sum(irate(
              http_server_requests_seconds_count{application="shop-api"}[2m]
            ))
    - name: error-rate
      interval: 30s
      count: 5
      successCondition: result[0] <= 0.001
      failureLimit: 2
      provider:
        prometheus:
          address: http://kps-kube-p-prometheus.monitoring:9090
          query: |
            sum(irate(http_server_requests_seconds_count{application="shop-api",status=~"5.."}[2m]))
---
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: latency
spec:
  metrics:
    - name: p99-latency
      interval: 60s
      count: 5
      successCondition: result[0] <= 0.5          # ⭐ p99 under 500ms
      failureLimit: 2
      provider:
        prometheus:
          address: http://kps-kube-p-prometheus.monitoring:9090
          query: |
            histogram_quantile(0.99,
              sum by (le) (rate(http_server_requests_seconds_bucket{application="shop-api"}[2m])))
```

```bash
# update the image → the canary starts automatically
kubectl argo rollouts set image shop-api api=ghcr.io/3558bhk/shop-api@sha256:9f2a… -n shop-prod

kubectl argo rollouts get rollout shop-api -n shop-prod --watch
# Name:            shop-api
# Status:          ॥ Paused
# Message:         CanaryPauseStep
# Strategy:        Canary
#   Step:          PAUSED at 2/8 (paused indefinitely)
# Images:          ghcr.io/…@sha256:1a2b… (stable)
#                  ghcr.io/…@sha256:9f2a… (canary)
# Replicas:
#   Desired:       6
#   Current:       7
#   Updated:       1
#   Ready:         7
#   Available:     7

kubectl argo rollouts dashboard      # a local web UI
kubectl argo rollouts promote shop-api -n shop-prod      # ⭐ approve the manual pause
kubectl argo rollouts abort   shop-api -n shop-prod      # ⭐ or roll back instantly
kubectl argo rollouts undo    shop-api -n shop-prod
kubectl argo rollouts history shop-api -n shop-prod
```

**With Argo CD**, the Rollout is just another resource in Git — but the *promotion* is a manual step, so GitOps and progressive delivery compose cleanly:

```yaml
# in the Argo CD Application
  ignoreDifferences:
    - group: argoproj.io
      kind: Rollout
      jsonPointers: ["/status", "/spec/paused"]     # ⭐ Argo Rollouts owns these
```

## 14.25 Extra Tasks

### Task 14.5 — Recover from a stuck `pending-upgrade` release

<details>
<summary>Show answer</summary>

```bash
helm history shop -n shop
# 4   Mon Sep 9 19:14:02 2026   pending-upgrade   shop-0.4.2   1.4.0   Preparing upgrade
helm status shop -n shop
# Error: release: not found        (or) STATUS: pending-upgrade
helm upgrade shop ./shop -n shop
# Error: UPGRADE FAILED: another operation (install/upgrade/rollback) is in progress
```

**Why it happens:** a `pre-upgrade` hook Job hung or failed, or the `helm` process was killed mid-operation (Ctrl-C, CI timeout, laptop sleep). Helm records the intent in a Secret and never clears it. Every subsequent operation refuses to proceed.

### Step 1 — find out what's stuck

```bash
# the release records live in Secrets
kubectl get secrets -n shop -l owner=helm,name=shop --sort-by=.metadata.creationTimestamp
# sh.helm.release.v1.shop.v1   helm.sh/release.v1   1   4h
# sh.helm.release.v1.shop.v2   helm.sh/release.v1   1   3h
# sh.helm.release.v1.shop.v3   helm.sh/release.v1   1   1h
# sh.helm.release.v1.shop.v4   helm.sh/release.v1   1   12m   ← ⛔ the stuck one

# what's the hook doing?
kubectl get jobs,pods -n shop -l app.kubernetes.io/task=migrate
kubectl describe job shop-api-migrate -n shop | grep -A6 Events
kubectl logs -n shop job/shop-api-migrate --tail=50
# Error: Migration V3__add_sku.sql failed
# Caused by: org.postgresql.util.PSQLException: ERROR: relation "products" already exists

# what does the cluster actually look like?
kubectl get deploy,sts,svc,ingress -n shop
kubectl get pods -n shop
```

### Step 2 — the fix, in order of preference

**Option A — roll back to the last good revision (usually correct):**

```bash
helm rollback shop 3 -n shop --wait --timeout 5m
helm history shop -n shop
# 3   …   superseded   shop-0.4.1   1.3.0   Rollback to 3
# 4   …   failed       shop-0.4.2   1.4.0   Preparing upgrade
# 5   …   deployed     shop-0.4.1   1.3.0   Rollback to 3
```

⚠️ `rollback` **re-runs the pre-rollback hooks**, which for this chart includes a migration Job. If that's what's stuck, this won't help — go to Option B.

**Option B — delete the stuck release Secret:**

```bash
# ⚠️ this removes Helm's record of revision 4. The cluster resources are untouched.
kubectl delete secret -n shop sh.helm.release.v1.shop.v4

helm history shop -n shop
# 3   …   deployed     shop-0.4.1   1.3.0   …      ← unstuck ✅

# clean up the failed hook's leftovers
kubectl delete job -n shop shop-api-migrate --ignore-not-found
```

Now you can upgrade again. But first understand *why* it failed:

```bash
# reproduce the render without touching the cluster
helm template shop ./shop -n shop -f values.yaml -s templates/jobs/migrate.yaml
# and run the migration Job manually to see the error
kubectl apply -f /tmp/migrate.yaml
kubectl logs -n shop job/shop-api-migrate -f
```

**Option C — `helm upgrade --no-hooks` to skip the failing hook:**

```bash
helm upgrade shop ./shop -n shop --no-hooks --wait
# applies everything EXCEPT the migration Job
```

Then run the migration deliberately, once you've fixed the SQL:

```bash
kubectl apply -f /tmp/migrate.yaml
kubectl wait --for=condition=complete job/shop-api-migrate -n shop --timeout=900s
```

⚠️ Your app is now running against an un-migrated schema. Only do this if the migration is genuinely optional, and never leave it that way.

**Option D — the nuclear option (only if nothing else works):**

```bash
# uninstall WITHOUT deleting the resources, then re-adopt them
helm uninstall shop -n shop --no-hooks --keep-history 2>/dev/null || true
kubectl get secrets -n shop -l owner=helm,name=shop    # should be gone

# the resources are still running. Re-install pointing at them:
helm install shop ./shop -n shop --replace --no-hooks
# --replace reuses the existing resource names
```

⚠️ `--replace` can conflict. If it does, you're in `kubectl edit` territory — export the live objects, delete them, and re-apply from the chart.

### Step 3 — with Argo CD, it's different

Argo CD doesn't use Helm's release history for its own state, but it *does* shell out to `helm` for rendering. A stuck Helm release still blocks it:

```bash
argocd app get shop-prod
# Sync Status:  Unknown
# Health:       Degraded
# Message:      rpc error: … another operation (install/upgrade/rollback) is in progress
```

```bash
# same fix — delete the stuck Secret
kubectl delete secret -n shop-prod -l owner=helm,name=shop,version=4
argocd app sync shop-prod --force
```

**Prefer this in GitOps:** make Helm releases **not tracked by Helm at all**. Argo CD renders the chart and applies the manifests itself; there's no Helm release Secret to get stuck:

```yaml
# in the Argo CD Application
spec:
  source:
    helm:
      releaseName: shop       # used only for template rendering (.Release.Name)
  syncPolicy:
    automated: {prune: true, selfHeal: true}
```

Argo CD's `helm` source type renders and applies — it never runs `helm install`. **This is the recommended GitOps pattern, and it eliminates the entire class of `pending-upgrade` failures.** The trade-off: you lose `helm history` and `helm rollback` (Git gives you both instead).

### Step 4 — prevent it

```yaml
# 1. hooks must fail loudly and quickly
spec:
  backoffLimit: 0                 # ⭐ never auto-retry a migration
  activeDeadlineSeconds: 900      # ⭐ kill it after 15 min, don't hang forever
  template:
    spec:
      restartPolicy: Never
```

```yaml
# 2. always --atomic in CI
helm upgrade --install shop ./shop -n shop -f values.yaml \
  --atomic --timeout 10m --wait --wait-for-jobs
# --atomic rolls back automatically on ANY failure, so it never gets stuck
```

```bash
# 3. pre-flight: is a release already stuck?
if helm history shop -n shop 2>/dev/null | tail -1 | grep -q 'pending'; then
  echo "⛔ release shop is in a pending state — investigate before deploying"
  helm history shop -n shop
  exit 1
fi
```

```yaml
# 4. alert on it
- alert: HelmReleasePendingUpgrade
  expr: |
    changes(kube_secret_created{secret_name=~"sh.helm.release.*"}[1h]) > 0
    unless on() vector(1)     # placeholder — see the note
  for: 30m
  labels: {severity: critical}
```

Realistically, detect it from the CI logs or with a small CronJob:

```bash
#!/bin/sh
for ns in $(kubectl get ns -o name | cut -d/ -f2); do
  helm list -n $ns -a -o json 2>/dev/null \
    | jq -r '.[] | select(.status != "deployed") | "\(.namespace)/\(.name): \(.status)"'
done
```

### The decision table

| Situation | Action |
|---|---|
| Hook Job failed with a clear error | Fix the error, then `helm rollback` + retry |
| Hook Job is hung (no logs, no progress) | `kubectl delete job`, then `helm rollback` |
| `helm` was killed mid-operation, everything looks fine | Delete the pending Secret, verify with `helm get manifest` |
| Resources are half-applied | `helm rollback` to the last good revision, then `kubectl diff` |
| Nothing works | `helm uninstall --no-hooks`, then `helm install --replace` |
| You're using Argo CD | Delete the stuck Secret and `argocd app sync --force`; or switch to render-and-apply (no Helm releases) |

</details>

---

### Task 14.6 — Implement secret management so no plaintext secret ever lands in Git

<details>
<summary>Show answer</summary>

**Four real options. Pick one; don't mix them casually.**

| | Sealed Secrets | SOPS + age | External Secrets Operator | Vault Agent Injector |
|---|---|---|---|---|
| Where the plaintext lives | Only in the cluster | Only in the cluster (decrypted by Argo CD) | Never in Git; fetched at runtime | Never in Git; injected at runtime |
| Needs a cloud KMS/Vault | ❌ | ⚠️ optional (age is enough) | ✅ (Secrets Manager, Vault, GCP SM) | ✅ Vault |
| Rotation | Manual re-seal | Manual re-encrypt | **Automatic** | **Automatic** |
| Works offline / in kind | ✅ | ✅ | ⚠️ needs a provider | ⚠️ needs Vault |
| GitOps-friendly | ✅ | ✅✅ | ✅✅ | ✅ |
| Complexity | Low | Low | Medium | High |
| Best for | Learning, small teams | Small–mid teams, no cloud | **Production on a cloud** | Vault shops |

### Option 1 — Sealed Secrets (best for learning)

```bash
helm install sealed-secrets sealed-secrets/sealed-secrets -n kube-system --wait

# the CONTROLLER holds the private key, generated on first start, in the cluster
kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key
```

```bash
# encrypt locally — you never commit the plaintext
brew install kubeseal   # or download the binary

cat > db-creds.yaml <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: shop-db-creds
  namespace: shop-prod
type: Opaque
stringData:
  username: shop
  password: "R3al-S3cret-Pa55w0rd!"
  url: "jdbc:postgresql://rds.amazonaws.com:5432/app"
EOF

kubeseal --controller-namespace kube-system \
         --format yaml < db-creds.yaml > shop-gitops/apps/shop/overlays/prod/sealed-db-creds.yaml

shred -u db-creds.yaml       # ⭐ the plaintext file is gone
```

```yaml
# what lands in Git — safe to commit
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: shop-db-creds
  namespace: shop-prod
spec:
  encryptedData:
    password: AgBv1kQ2xZ… (742 base64 chars) …
    url: AgCx9pLm2…
    username: AgDk3nR8…
  template:
    metadata:
      name: shop-db-creds
      namespace: shop-prod
      labels: {app.kubernetes.io/part-of: shop}
      annotations:
        reloader.stakater.com/auto: "true"
    type: Opaque
```

Argo CD applies the `SealedSecret`; the controller decrypts it into a real `Secret`. **The private key never leaves the cluster.**

```bash
# verify
kubectl get sealedsecret -n shop-prod
kubectl get secret -n shop-prod shop-db-creds -o jsonpath='{.data.password}' | base64 -d; echo

# ⚠️ BACK UP THE CONTROLLER KEY. Lose it and every SealedSecret is undecryptable.
kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key \
  -o yaml > sealed-secrets-key-backup.yaml
# encrypt THAT with age/SOPS and store it somewhere offline
```

**Rotate the key annually:**

```bash
kubectl -n kube-system delete pod -l name=sealed-secrets-controller
# a new key is generated; the OLD one is kept so existing SealedSecrets still work.
# Re-seal everything against the new key when convenient.
```

### Option 2 — SOPS + age (best for small teams, no cloud dependency)

```bash
brew install sops age
age-keygen -o ~/.config/sops/age/keys.txt
# Public key: age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p
```

```yaml
# shop-gitops/.sops.yaml — which key encrypts which file
creation_rules:
  - path_regex: apps/shop/overlays/prod/.*\.yaml$
    encrypted_regex: '^(password|secret|token|key|data|stringData|auth)$'
    age: >-
      age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p,
      age1backup…
  - path_regex: apps/shop/overlays/dev/.*\.yaml$
    encrypted_regex: '^(password|stringData)$'
    age: age1ql3z7…
```

```bash
# write the plaintext, then encrypt in place
cat > shop-gitops/apps/shop/overlays/prod/db-secret.yaml <<'EOF'
apiVersion: v1
kind: Secret
metadata: {name: shop-db-creds, namespace: shop-prod}
type: Opaque
stringData:
  username: shop
  password: "R3al-S3cret-Pa55w0rd!"
EOF

cd shop-gitops
sops --encrypt --in-place apps/shop/overlays/prod/db-secret.yaml
git diff    # ⭐ only the encrypted fields changed
```

```yaml
# what lands in Git
apiVersion: v1
kind: Secret
metadata: {name: shop-db-creds, namespace: shop-prod}
type: Opaque
stringData:
    username: ENC[AES256_GCM,data:c2hvcA==,iv:…,tag:…,type:str]
    password: ENC[AES256_GCM,data:UjNhbC1TM2Ny…,iv:…,tag:…,type:str]
sops:
    kms: []
    age:
        - recipient: age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p
          enc: |
            -----BEGIN AGE ENCRYPTED FILE-----
            …
    lastmodified: "2026-09-09T19:42:11Z"
    mac: ENC[AES256_GCM,…]
    version: 3.9.3
```

**Only the values are encrypted — the keys and structure stay readable**, so `git diff` still shows you *which* field changed.

**Argo CD decrypts it via a plugin:**

```bash
# install the CMP sidecar
helm upgrade argocd argo/argo-cd -n argocd --reuse-values \
  --set 'configs.cmp.plugins[0].name=sops' \
  --set-file 'configs.cmp.plugins[0].configmap.data'=./sops-cmp.yaml
```

```yaml
# sops-cmp.yaml — the Argo CD Config Management Plugin
apiVersion: v1
kind: ConfigMap
data:
  allowConcurrency: "true"
  discover:
    find:
      glob: ['**/*.yaml', '**/*.yml']
  init: |
    # import the age key from a Secret mounted into the repo-server
    mkdir -p ~/.config/sops/age
    cp /sops-age/keys.txt ~/.config/sops/age/keys.txt
    chmod 600 ~/.config/sops/age/keys.txt
  parameters:
    static:
      - name: encrypted
        value: "true"
```

```yaml
# the repo-server needs the age key as a Secret
apiVersion: v1
kind: Secret
metadata: {name: sops-age, namespace: argocd}
stringData:
  keys.txt: |
    # created: 2026-09-09T19:30:00Z
    # public key: age1ql3z7…
    AGE-SECRET-KEY-1Q…
```

```yaml
# in values.yaml for the argo-cd Helm chart
repoServer:
  volumes:
    - name: sops-age
      secret: {secretName: sops-age}
  volumeMounts:
    - name: sops-age
      mountPath: /sops-age
      readOnly: true
```

```yaml
# the Application declares the plugin
spec:
  source:
    plugin:
      name: sops
```

### Option 3 — External Secrets Operator (best for production on a cloud)

**Nothing secret is in Git. Only a reference to where it lives.**

```bash
helm install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace --wait \
  --set installCRDs=true
```

```yaml
# the cloud provider, once per cluster
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata: {name: aws-secrets-manager}
spec:
  provider:
    aws:
      service: SecretsManager
      region: ap-south-1
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets
            namespace: external-secrets
  conditions:
    - type: Ready
      status: "True"
---
# IRSA so the operator can read Secrets Manager — no static keys anywhere
apiVersion: v1
kind: ServiceAccount
metadata:
  name: external-secrets
  namespace: external-secrets
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/external-secrets-reader
```

```yaml
# ⭐ THIS is what goes in Git — safe, reviewable, and contains no secret
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: shop-db-creds
  namespace: shop-prod
  labels: {app.kubernetes.io/part-of: shop}
  annotations:
    reloader.stakater.com/auto: "true"       # ⭐ rolls the Pods on rotation
spec:
  refreshInterval: 1h                        # ⭐ how often to re-check for rotation
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: shop-db-creds
    creationPolicy: Owner
    deletionPolicy: Retain                   # ⭐ don't delete the K8s Secret if the ES is removed
    template:
      type: Opaque
      metadata:
        labels: {app.kubernetes.io/part-of: shop}
      data:
        # you can compose values here
        url: "jdbc:postgresql://{{ .host }}:{{ .port }}/{{ .database }}"
  data:
    - secretKey: username
      remoteRef: {key: shop/prod/db, property: username}
    - secretKey: password
      remoteRef: {key: shop/prod/db, property: password}
    - secretKey: host
      remoteRef: {key: shop/prod/db, property: host}
    - secretKey: port
      remoteRef: {key: shop/prod/db, property: port}
    - secretKey: database
      remoteRef: {key: shop/prod/db, property: database}
---
# ⭐ push a secret the OTHER way: K8s → the cloud (for cert-manager, etc.)
apiVersion: external-secrets.io/v1beta1
kind: PushSecret
metadata: {name: tls-to-aws, namespace: shop-prod}
spec:
  refreshInterval: 1h
  secretStoreRefs: [{name: aws-secrets-manager, kind: ClusterSecretStore}]
  selector: {secret: {name: shop-tls}}
  data:
    - match: {secretKey: tls.crt, remoteRef: {remoteKey: shop/prod/tls, property: crt}}
```

```bash
# verify
kubectl get externalsecret -n shop-prod
# NAME            STORE                  REFRESH   STATUS   CAPABILITIES   READY
# shop-db-creds   aws-secrets-manager    1h        SecretSynced  ReadWrite  True

kubectl describe externalsecret shop-db-creds -n shop-prod | grep -A6 Conditions
kubectl get secret shop-db-creds -n shop-prod -o jsonpath='{.data.password}' | base64 -d; echo
```

**The killer feature — automatic rotation:**

```bash
# rotate in AWS
aws secretsmanager put-secret-value --secret-id shop/prod/db \
  --secret-string '{"username":"shop","password":"N3w-R0tated-Pa55!","host":"…","port":"5432","database":"app"}'

# within refreshInterval (1h), ESO updates the Kubernetes Secret…
kubectl get secret shop-db-creds -n shop-prod -o jsonpath='{.metadata.annotations.external-secrets\.io/data-hash}'; echo
# …and Reloader rolls the Deployment, so the app picks it up
kubectl get pods -n shop-prod -l app.kubernetes.io/component=api -w
```

**Zero human involvement, zero Git commits, zero downtime.** That's what you're paying for.

### Option 4 — Vault (if you already have it)

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: shop-api
  namespace: shop-prod
  annotations:
    vault.hashicorp.com/agent-inject: "true"
    vault.hashicorp.com/role: "shop-api"
    vault.hashicorp.com/agent-inject-secret-db: "database/creds/shop-prod"
    vault.hashicorp.com/agent-inject-template-db: |
      {{- with secret "database/creds/shop-prod" -}}
      export DB_USER="{{ .Data.username }}"
      export DB_PASS="{{ .Data.password }}"
      {{- end -}}
    vault.hashicorp.com/agent-inject-command: "sh -c '. /vault/secrets/db && exec java -jar /app.jar'"
```

The Vault Agent Injector mutating webhook adds an init container + sidecar that write the secrets to `/vault/secrets/` as files. **Nothing in Git, nothing in env vars, automatic rotation via the agent.** The cost: a Vault cluster to run, and every Pod gets two extra containers.

### The decision

| You are… | Use |
|---|---|
| Learning, on kind | **Sealed Secrets** — five minutes, no dependencies |
| A small team, no cloud KMS | **SOPS + age** — one key file, `git diff` works |
| On AWS/GCP/Azure in production | **External Secrets Operator** — automatic rotation |
| Already running Vault | **Vault Agent Injector** |
| Regulated / zero-trust | Vault, or ESO + a hardware-backed KMS |

### And the rules that apply to all of them

```yaml
# 1. never let an app project create raw Secrets (AppProject)
namespaceResourceBlacklist:
  - {group: "", kind: Secret}
```

```bash
# 2. scan Git for accidental leaks, in CI
pip install detect-secrets
detect-secrets scan --baseline .secrets.baseline
detect-secrets-hook --baseline .secrets.baseline $(git ls-files '*.yaml' '*.yml')

# or gitleaks
gitleaks detect --source . --redact --exit-code 1
```

```bash
# 3. audit who read a secret
kubectl get events -n shop-prod --field-selector reason=Created | grep -i secret
# with the audit log enabled:
kubectl get --raw "/api/v1/namespaces/shop-prod/secrets" -v=8
```

```yaml
# 4. encrypt at rest in etcd
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources: ["secrets"]
    providers:
      - aescbc: {keys: [{name: key1, secret: <base64 32 bytes>}]}
      - identity: {}
```

```bash
# 5. RBAC: who can read secrets is the most dangerous permission in the cluster
kubectl auth can-i get secrets -n shop-prod --as=system:serviceaccount:shop-prod:shop-api
kubectl auth can-i list secrets --all-namespaces --as=system:serviceaccount:argocd:argocd-application-controller
# ⚠️ `list secrets` cluster-wide = read every credential in the cluster
```

</details>

---

## 14.26 Checklist

**Helm**
- [ ] Explain what a Helm release is and where its state lives
- [ ] Distinguish `Chart.version` from `appVersion` and say when to bump each
- [ ] Write `_helpers.tpl` with fullname, labels, selector labels, and image helpers
- [ ] Explain why selector labels must be minimal and immutable
- [ ] Add `values.schema.json` and prove it rejects a bad memory value
- [ ] Add `required` and `fail` validations with useful messages
- [ ] Use the `checksum/config` annotation so config changes roll Pods
- [ ] Omit `replicas` when an HPA owns the scale
- [ ] Write a `pre-upgrade` hook Job for migrations with `backoffLimit: 0`
- [ ] Write `helm test` tests that verify the whole stack
- [ ] Write `NOTES.txt` that tells the user how to reach and verify the app
- [ ] Publish to an OCI registry and sign with cosign
- [ ] Write chart unit tests with helm-unittest
- [ ] Recover from a stuck `pending-upgrade` release
- [ ] Name the five most common Helm template errors and their fixes

**GitOps**
- [ ] State the four GitOps rules and explain push vs pull
- [ ] Install Argo CD with HA, RBAC, SSO and Slack notifications
- [ ] Bootstrap a cluster with a single App-of-Apps manifest
- [ ] Use sync waves to order CRDs → controllers → databases → migrations → apps
- [ ] Write an AppProject that restricts destinations, sources, resource kinds, and roles
- [ ] Configure `ignoreDifferences` for HPA replicas and cert-manager Secrets
- [ ] Demonstrate drift detection and self-heal
- [ ] Build a CI pipeline that never holds cluster credentials — it only commits to Git
- [ ] Explain why the rollback is `git revert`, not `argocd app rollback`
- [ ] Generate Applications with an ApplicationSet
- [ ] Run a canary with Argo Rollouts and automatic analysis-based rollback
- [ ] Choose and implement a secret management strategy with no plaintext in Git
- [ ] Back up the Sealed Secrets controller key (or you've lost everything)

**Next → [`18-PROJECT-15-mern-stack.md`](18-PROJECT-15-mern-stack.md)** — Project 15, the **MERN stack on Kubernetes**: React + Node/Express + **MongoDB as a replica-set StatefulSet**, the migration as a gated Job, the backup as a restore-verified CronJob, and the three-probe split that stops a mongo election from restart-looping your whole fleet.

**Then → [`02-CAPSTONE-END-TO-END.md`](02-CAPSTONE-END-TO-END.md)** — the full capstone: everything from Projects 1–15, one platform, from an empty cluster to a hardened, observable, self-healing production deployment.

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish%20Kumar%20Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn → <https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260>
🐙 GitHub → <https://github.com/3558Bhk>

*Built for engineers who learn by breaking things on purpose.*

</div>
