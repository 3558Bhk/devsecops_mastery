# 🎯 CASE 1 · THE DEPLOYMENT TARGETS — DOCKER & KUBERNETES
### What "deploy a digest" actually means on each target, for each app shape — with the runbook you would follow at 2 a.m.

> **The three tool files in this folder answer *who approves*. This file answers *what the deploy step does*.** It is deliberately tool-independent: every command here is what your GitHub Actions / Azure DevOps / Jenkins step ultimately runs.
>
> **Targets:** 🐳 **Docker** (single host, Compose) — Docker path P8–P13 · ☸️ **Kubernetes** (kind `cicd` → AKS/EKS) — K8s path P8–P14.

---

## 📇 Contents

| § | What |
|---|---|
| [1](#1---the-one-rule-digest-everywhere) | ⭐ The one rule: digest everywhere |
| [2](#2---target-a--docker--compose-on-a-host) | 🐳 **Target A — Docker / Compose on a host** |
| [3](#3--️-target-b--kubernetes-with-kubectl) | ☸️ **Target B — Kubernetes with `kubectl`** |
| [4](#4--️-target-c--kubernetes-with-helm-k8s-p14) | ☸️ **Target C — Kubernetes with Helm** (K8s P14) |
| [5](#5---the-migration-job--the-step-everyone-gets-wrong) | ⭐⭐ The migration Job — the step everyone gets wrong |
| [6](#6---per-app-shape-runbooks) | ⭐ Per-app-shape runbooks (A / B / C / D) |
| [7](#7--️-the-data-tier-p13--why-it-is-always-case-1) | 🗄️ The data tier (P13) — why it is always Case 1 |
| [8](#8---rollback-on-each-target) | ⭐ Rollback on each target |
| [9](#9--verification--what-to-check-after-every-deploy) | Verification — what to check after every deploy |
| [10](#10---the-2-am-runbook) | ⭐⭐ The 2 a.m. runbook |
| [11](#11---tasks--answers-at-the-end) | Tasks and answers — **answers at the END** |

---

## 1 · ⭐ The one rule: digest everywhere

```
⛔ TAG       shopacr.azurecr.io/shop-api:v1.4.2
             shopacr.azurecr.io/shop-api:latest
   → mutable. "Deploy v1.4.2" does not tell you what ran.
   → two hosts can be running DIFFERENT CODE under the same tag.
   → rollback is guesswork.

✅ DIGEST    shopacr.azurecr.io/shop-api@sha256:41ab7c…
   → immutable. It IS the artifact.
   → "what is running?" has an exact answer on every host.
   → rollback = re-point at a previous digest, no rebuild.
```

**Where the digest must appear:**

| Place | Form |
|---|---|
| The CI output | `digest.txt` artifact / pipeline variable |
| The CD input | a parameter, validated by regex |
| `docker-compose.prod.yml` | ⭐ `image: …@sha256:…` |
| The K8s Deployment | ⭐ `spec.template.spec.containers[].image` |
| The Helm values | `image.digest`, with `tag: ""` |
| The audit record | the digest, the approver, the timestamp |
| ⭐ **Read back from the target after deploy** | `docker inspect` / `kubectl get -o jsonpath` |

⭐⭐ **The last row is the one that matters.** A deploy tool's exit code tells you the tool ran. Reading the desired state back from the target tells you **what is running**. Both `docker compose up -d` and `KubernetesManifest@1` will happily succeed while deploying the wrong thing.

---

## 2 · 🐳 Target A — Docker / Compose on a host

**Apps:** Docker P8 (`shop-ui`) · P9 (`shop-api`) · P10 (React+Java) · P11 (React+Python) · P12 (React+Go) · P13 (databases) · P7 (the whole stack)

### 2.1 The production Compose file

`docker-compose.prod.yml` — ⭐ committed, with the digest substituted at deploy time.

```yaml
# ═══════════════════════════════════════════════════════════════════════
#  WHAT : production Compose for the P10 stack (React FE + Java BE).
#  WHY  : ⭐ images are DIGESTS, injected by the CD pipeline. The file in
#         git holds placeholders; the file on the host holds the truth.
# ═══════════════════════════════════════════════════════════════════════
name: shop-prod

services:
  shop-ui:
    image: ${SHOP_UI_IMAGE:?⭐ SHOP_UI_IMAGE must be a digest reference}
    # ⭐ `:?message` — Compose FAILS if the variable is unset. Without it,
    #   an unset variable silently produces `image: ""` and Compose pulls
    #   whatever the service name resolves to. Loud failure beats mystery.
    restart: unless-stopped
    ports: ["80:80"]
    environment:
      # ⭐⭐ RUNTIME config, NOT build-time. One image serves every env.
      API_URL: https://api.shop
      APP_ENV: production
      GIT_SHA: ${GIT_SHA:-unknown}
    depends_on:
      shop-api:
        condition: service_healthy      # ⭐ BE before FE — the ordering rule
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:80/"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 10s
    logging: &logging
      driver: json-file
      options: { max-size: "10m", max-file: "3" }   # ⭐ or the disk fills
    deploy:
      resources:
        limits: { cpus: "0.5", memory: 256M }        # ⭐ or one service eats the host

  shop-api:
    image: ${SHOP_API_IMAGE:?⭐ SHOP_API_IMAGE must be a digest reference}
    restart: unless-stopped
    expose: ["8080"]                    # ⭐ NOT published — only via the FE/nginx
    environment:
      SPRING_PROFILES_ACTIVE: prod
      DB_URL: jdbc:postgresql://postgres:5432/shop
      DB_USER: shop
      DB_PASSWORD_FILE: /run/secrets/db_password    # ⭐ a secret, not an env var
    secrets: [db_password]
    depends_on:
      postgres:
        condition: service_healthy      # ⭐⭐ the DB must be READY, not started
      migrate:
        condition: service_completed_successfully   # ⭐⭐ MIGRATION FIRST
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:8080/actuator/health/readiness"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 60s                 # ⭐ JVM warmup — do not set this to 10s
    logging: *logging
    deploy:
      resources:
        limits: { cpus: "2", memory: 1536M }

  # ── ⭐⭐ THE MIGRATION AS A ONE-SHOT SERVICE ──────────────────────────
  migrate:
    image: ${SHOP_API_IMAGE:?}          # ⭐ SAME image — same Flyway, same SQL
    restart: "no"                        # ⛔ never restart a failed migration
    command: ["java","-cp","/app/app.jar","-Dloader.main=org.flywaydb.core.Flyway",
              "org.springframework.boot.loader.launch.PropertiesLauncher","migrate"]
    environment:
      DB_URL: jdbc:postgresql://postgres:5432/shop
      DB_USER: shop
      DB_PASSWORD_FILE: /run/secrets/db_password
    secrets: [db_password]
    depends_on:
      postgres: { condition: service_healthy }

  postgres:
    image: postgres:17.7@sha256:…       # ⭐ pin the BASE images by digest too
    restart: unless-stopped
    environment:
      POSTGRES_DB: shop
      POSTGRES_USER: shop
      POSTGRES_PASSWORD_FILE: /run/secrets/db_password
    secrets: [db_password]
    volumes:
      - pgdata:/var/lib/postgresql/data  # ⭐ a NAMED volume, never a bind mount
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U shop -d shop"]
      interval: 10s
      timeout: 5s
      retries: 5
    logging: *logging

secrets:
  db_password:
    file: /run/secrets/db_password       # ⭐ mounted by the host, never in git

volumes:
  pgdata:
```

### 2.2 ⭐ The deploy command sequence

```bash
#!/usr/bin/env bash
# deploy-docker.sh — what the CD pipeline's deploy step actually runs
# ═══════════════════════════════════════════════════════════════════════
#  WHAT : deploy digests to a Docker host, safely.
#  WHY  : `docker compose up -d` alone loses the previous version, does not
#         verify, and cannot roll back. These are the steps around it.
# ═══════════════════════════════════════════════════════════════════════
set -euo pipefail

SERVICE_UI="${SHOP_UI_IMAGE:?}"
SERVICE_API="${SHOP_API_IMAGE:?}"

# ── 0 · ⭐ REFUSE A TAG ────────────────────────────────────────────────
for ref in "$SERVICE_UI" "$SERVICE_API"; do
  [[ "$ref" =~ @[a-z0-9]+:[0-9a-f]{64}$ ]] \
    || { echo "⛔ '$ref' is not a digest reference"; exit 1; }
done

# ── 1 · ⭐⭐ RECORD WHAT IS RUNNING NOW — this IS your rollback plan ────
mkdir -p /opt/shop/releases
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
docker compose -f docker-compose.prod.yml config --images \
  > "/opt/shop/releases/${STAMP}.images.txt" || true
docker inspect --format '{{.Name}} {{.Image}} {{.Config.Image}}' \
  $(docker ps -q) > "/opt/shop/releases/${STAMP}.running.txt" || true
echo "📌 recorded current state → /opt/shop/releases/${STAMP}.*"

# ── 2 · PULL FIRST, SEPARATELY ────────────────────────────────────────
# ⭐ WHY: a pull failure during `up -d` leaves you half-migrated. Pulling
#   first means the switch is fast and either everything is local or nothing is.
docker compose -f docker-compose.prod.yml pull --quiet

# ── 3 · VERIFY THE PULLED DIGEST IS THE ONE WE ASKED FOR ──────────────
PULLED=$(docker image inspect "$SERVICE_API" --format '{{index .RepoDigests 0}}')
[ "$PULLED" = "$SERVICE_API" ] || { echo "⛔ pulled $PULLED, wanted $SERVICE_API"; exit 1; }

# ── 4 · ⭐ THE SWITCH ──────────────────────────────────────────────────
# `--remove-orphans` cleans services deleted from the file.
# ⛔ NEVER use `down` here — it stops the database and loses the network.
SHOP_UI_IMAGE="$SERVICE_UI" SHOP_API_IMAGE="$SERVICE_API" GIT_SHA="$GIT_SHA" \
  docker compose -f docker-compose.prod.yml up -d --remove-orphans --wait
# ⭐⭐ `--wait` blocks until every service reports healthy (or fails).
#   Without it, `up -d` returns immediately and the pipeline reports success
#   for a container that is crash-looping.

# ── 5 · VERIFY FROM THE OUTSIDE, NOT FROM COMPOSE ─────────────────────
for i in $(seq 1 30); do
  UI=$(curl -fsS -o /dev/null -w '%{http_code}' http://localhost/ || echo 000)
  API=$(curl -fsS -o /dev/null -w '%{http_code}' \
        http://localhost/api/v2/orders || echo 000)
  if [ "$UI" = "200" ] && [ "$API" = "200" ]; then
    echo "✅ healthy: ui=$UI api=$API"; exit 0
  fi
  sleep 3
done
echo "⛔ NOT healthy after 90s — rolling back"
# ── 6 · ⭐ ROLLBACK IS JUST THE PREVIOUS RECORDED STATE ────────────────
PREV=$(ls -1t /opt/shop/releases/*.images.txt | sed -n 2p)
SHOP_UI_IMAGE=$(grep shop-ui  "$PREV") SHOP_API_IMAGE=$(grep shop-api "$PREV") \
  docker compose -f docker-compose.prod.yml up -d --remove-orphans --wait
exit 1
```

### 2.3 ⭐ The six Docker-target rules

| # | Rule | Why |
|---|---|---|
| 1 | ⛔ **Never `docker compose down`** in a deploy | it stops the **database** and destroys the network. Use `up -d` |
| 2 | ⭐ **Always `--wait`** | otherwise `up -d` returns before health, and the pipeline reports success for a crash-looping container |
| 3 | ⭐ **Record the running state before switching** | that record *is* your rollback |
| 4 | ⭐ **`pull` separately, before `up`** | a pull failure mid-switch leaves a half-deployed stack |
| 5 | ⭐ **Named volumes, never bind mounts** for data | bind mounts inherit host permissions and break on a host swap |
| 6 | ⭐ **Pin base images by digest too** | `postgres:17.7` can be re-pushed; `postgres:17.7@sha256:…` cannot |

### 2.4 Zero-downtime on a single Docker host?

⭐ **Honest answer: Compose alone gives you a brief gap**, because `up -d` recreates the container. Three ways to reduce it:

| Approach | Gap | Complexity |
|---|---|---|
| `up -d --wait` with a good `start_period` | ⭐ ~2–10 s | low |
| ⭐ **nginx in front, two app containers, blue/green by symlink** | ~0 | medium |
| Put it on Kubernetes | ~0 (rolling update) | ⭐ the actual answer |

```bash
# ⭐ the blue/green trick on a single host, in four lines
docker compose -f docker-compose.green.yml up -d --wait   # start the NEW stack on :8081
curl -fsS http://localhost:8081/actuator/health/readiness  # verify it
sed -i 's/8080/8081/' /etc/nginx/conf.d/shop.conf && nginx -s reload   # switch
docker compose -f docker-compose.prod.yml stop shop-api    # retire the OLD
```

**When Docker is the right target anyway:** single-tenant internal tools, edge devices, dev/staging hosts, homelabs, and CI test environments. ⭐ Saying "we run Compose in production for a 3-service internal tool and it is the right choice" is a stronger interview answer than pretending everything is Kubernetes.

---

## 3 · ☸️ Target B — Kubernetes with `kubectl`

**Apps:** K8s P8–P13, mirroring the Docker apps.

### 3.1 The Deployment that makes a digest deploy work

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: shop-api
  namespace: shop-production
spec:
  replicas: 3
  revisionHistoryLimit: 10          # ⭐ keeps 10 old ReplicaSets = 10 rollbacks
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0             # ⭐⭐ NEVER drop a replica before a new one is ready
      maxSurge: 1                   # one extra pod at a time
  selector:
    matchLabels: { app: shop-api }
  template:
    metadata:
      labels: { app: shop-api, tier: backend }
    spec:
      imagePullSecrets: [{ name: acr-pull }]
      terminationGracePeriodSeconds: 60     # ⭐ time to drain in-flight requests
      containers:
        - name: shop-api                    # ⭐⭐ the name CD's `set image` must match
          image: shopacr.azurecr.io/shop-api@sha256:PLACEHOLDER
          # ⭐ imagePullPolicy is IRRELEVANT for digests — a digest is immutable,
          #   so the node either has it or it does not. It matters enormously for
          #   tags, which is one more reason not to use them.
          ports: [{ containerPort: 8080 }]
          envFrom:
            - configMapRef: { name: shop-api-config }
          env:
            - name: DB_PASSWORD
              valueFrom: { secretKeyRef: { name: shop-api-db, key: password } }
          resources:
            requests: { cpu: 250m, memory: 512Mi }
            limits:   { cpu: "1",  memory: 1Gi }
          # ⭐⭐ THE THREE PROBES — a digest deploy without these is unsafe
          startupProbe:                     # slow JVM start-up
            httpGet: { path: /actuator/health/liveness, port: 8080 }
            failureThreshold: 30            # 30 × 5s = 150s to boot
            periodSeconds: 5
          readinessProbe:                   # ⭐ GATES TRAFFIC
            httpGet: { path: /actuator/health/readiness, port: 8080 }
            periodSeconds: 10
            failureThreshold: 3
          livenessProbe:                    # ⭐ RESTARTS A STUCK POD
            httpGet: { path: /actuator/health/liveness, port: 8080 }
            periodSeconds: 20
            failureThreshold: 3
          lifecycle:
            preStop:                        # ⭐ drain before SIGTERM
              exec:
                command: ["/bin/sh","-c","sleep 10"]
                # WHY: endpoint removal is ASYNCHRONOUS. Without this, the pod
                #   gets SIGTERM while kube-proxy is still routing to it →
                #   a burst of 502s on every single deploy.
```

⭐⭐ **The `preStop: sleep 10` line is the most-skipped and most-valuable line in this file.** Kubernetes removes a terminating pod from Service endpoints *asynchronously*. A JVM that receives SIGTERM immediately starts shutting down while traffic is still arriving — producing a handful of 502s on every deploy. Ten seconds of sleep costs nothing and removes them. If you see "brief errors during deploys", this is almost always why.

### 3.2 ⭐ The deploy command sequence

```bash
#!/usr/bin/env bash
# deploy-k8s.sh — what the CD pipeline's deploy step actually runs
set -euo pipefail

NS="${NS:-shop-production}"
SVC="${SVC:-shop-api}"
REF="${REF:?⭐ REF must be set to a digest reference}"
CONTAINER="${CONTAINER:-$SVC}"

# ── 0 · REFUSE A TAG ──────────────────────────────────────────────────
[[ "$REF" =~ @[a-z0-9]+:[0-9a-f]{64}$ ]] || { echo "⛔ not a digest: $REF"; exit 1; }

# ── 1 · ⭐ RECORD THE CURRENT STATE — this IS your rollback ───────────
kubectl -n "$NS" get deploy "$SVC" -o yaml > "/tmp/${SVC}-before-$(date +%s).yaml"
PREV=$(kubectl -n "$NS" get deploy "$SVC" \
       -o jsonpath="{.spec.template.spec.containers[?(@.name=='${CONTAINER}')].image}")
echo "📌 previous: $PREV"

# ── 2 · ⭐⭐ MIGRATION FIRST, AS A GATED JOB ───────────────────────────
# (see §5 — this is the step that causes incidents when skipped)
if [ -f "k8s/${SVC}/migration-job.yaml" ]; then
  kubectl -n "$NS" delete job "${SVC}-migrate" --ignore-not-found
  kubectl -n "$NS" apply -f "k8s/${SVC}/migration-job.yaml"
  kubectl -n "$NS" wait --for=condition=complete "job/${SVC}-migrate" --timeout=600s \
    || { echo "⛔ migration failed — NOT rolling out"; exit 1; }
fi

# ── 3 · THE SWITCH ────────────────────────────────────────────────────
kubectl -n "$NS" set image "deploy/${SVC}" "${CONTAINER}=${REF}"

# ── 4 · ⭐ WATCH IT. Never fire-and-forget. ───────────────────────────
if ! kubectl -n "$NS" rollout status "deploy/${SVC}" --timeout=600s; then
  echo "⛔ rollout did not converge"
  kubectl -n "$NS" describe "deploy/${SVC}" | tail -30
  kubectl -n "$NS" get pods -l "app=${SVC}" -o wide
  kubectl -n "$NS" logs "deploy/${SVC}" --tail=100 --all-containers || true
  # ── 5 · ⭐ ROLLBACK TO THE RECORDED DIGEST, NOT TO "undo" ───────────
  kubectl -n "$NS" set image "deploy/${SVC}" "${CONTAINER}=${PREV}"
  kubectl -n "$NS" rollout status "deploy/${SVC}" --timeout=300s
  exit 1
fi

# ── 6 · ⭐⭐ READ IT BACK FROM THE CLUSTER ─────────────────────────────
NOW=$(kubectl -n "$NS" get deploy "$SVC" \
      -o jsonpath="{.spec.template.spec.containers[?(@.name=='${CONTAINER}')].image}")
[ "$NOW" = "$REF" ] || { echo "⛔ cluster runs '$NOW', wanted '$REF'"; exit 1; }
echo "✅ confirmed running: $NOW"

# ── 7 · SMOKE FROM INSIDE THE CLUSTER ─────────────────────────────────
kubectl -n "$NS" run smoke-$RANDOM --rm -i --restart=Never \
  --image=curlimages/curl:8.17.0 -- \
  curl -fsS "http://${SVC}.${NS}.svc.cluster.local:8080/actuator/health/readiness"
# ⭐ from INSIDE, so you test the Service and the pod, not your laptop's
#   route to the ingress. A green external smoke test can hide a broken
#   Service selector.
```

### 3.3 ⭐ The four `kubectl` verbs and when each is right

| Verb | What it does | ⭐ Use when |
|---|---|---|
| `set image` | changes one container's image | ⭐ **the default for CD.** Minimal diff, clean rollout, easy rollback |
| `apply -f` | reconciles the whole manifest | ⭐ when the manifest itself changed (new env var, new resource limit) |
| `rollout undo` | reverts to the previous ReplicaSet | ⭐ quick rollback — ⛔ but "previous" is ambiguous after two failures |
| `patch` | surgical JSON patch | rare; for annotations, labels |
| `rollout restart` | new ReplicaSet, **same image** | ⭐ picking up a changed ConfigMap/Secret, or forcing a re-pull |

```bash
# ⭐ the combination most CD pipelines actually need:
kubectl -n "$NS" apply -f k8s/shop-api/          # reconcile everything
kubectl -n "$NS" set image deploy/shop-api \
        shop-api="$REF"                          # ⭐ then the digest
kubectl -n "$NS" rollout status deploy/shop-api --timeout=600s
# WHY BOTH: `apply` would reset the image to the manifest's placeholder if you
#   did not `set image` afterwards. And `set image` alone would not pick up a
#   manifest change. Order matters: apply, THEN set image.
```

### 3.4 ⭐ ConfigMap/Secret changes do NOT restart pods

```bash
# ⛔ this changes the ConfigMap and NOTHING ELSE. The running pods keep the
#   OLD values, because env vars are read at process start.
kubectl -n shop-production apply -f k8s/shop-api/configmap.yaml

# ✅ pick it up — three options, in order of safety:
kubectl -n shop-production rollout restart deploy/shop-api   # ⭐ clean, rolling
# or: mount the ConfigMap as a VOLUME (auto-updates within ~60s, no restart)
# or: hash the ConfigMap content into a pod annotation (Helm does this — §4)
```

⭐ **This is the most common "the deploy succeeded but nothing changed" in Kubernetes CD.** The image digest moved, the config did not, and the pipeline reported success.

---

## 4 · ☸️ Target C — Kubernetes with Helm (K8s P14)

```bash
#!/usr/bin/env bash
# deploy-helm.sh
set -euo pipefail

NS=shop-production
RELEASE=shop-api
REF="${REF:?}"
[[ "$REF" =~ @[a-z0-9]+:[0-9a-f]{64}$ ]] || { echo "⛔ not a digest"; exit 1; }

# ── ⭐ VALUES: image by DIGEST, tag deliberately empty ────────────────
cat > /tmp/values-prod.yaml <<EOF
image:
  repository: shopacr.azurecr.io/shop-api
  tag: ""                      # ⭐⭐ EMPTY. A non-empty tag wins over digest
                               #   in most charts — and silently.
  digest: "${REF#*@}"          # sha256:41ab…
replicaCount: 3
resources:
  requests: { cpu: 250m, memory: 512Mi }
  limits:   { cpu: "1",  memory: 1Gi }
EOF

# ── 1 · RECORD WHAT IS RUNNING ───────────────────────────────────────
helm -n "$NS" get values "$RELEASE" -o yaml > "/tmp/${RELEASE}-values-before.yaml"
helm -n "$NS" history "$RELEASE" | tail -5

# ── 2 · ⭐ DRY RUN + DIFF FIRST. Never blind-upgrade production. ──────
helm -n "$NS" diff upgrade "$RELEASE" ./charts/shop-api \
  -f /tmp/values-prod.yaml --detailed-exitcode || DIFF=$?
# ⭐ exit 2 = there ARE differences (expected). Exit 1 = a real error.
[ "${DIFF:-0}" -le 2 ] || { echo "⛔ helm diff failed"; exit 1; }

# ── 3 · THE UPGRADE ──────────────────────────────────────────────────
helm -n "$NS" upgrade "$RELEASE" ./charts/shop-api \
  -f /tmp/values-prod.yaml \
  --atomic \                       # ⭐⭐ rolls back AUTOMATICALLY on failure
  --wait \                         # waits for all resources to be ready
  --timeout 10m \
  --history-max 10
# ⭐ `--atomic` implies `--wait` and adds: if the upgrade does not succeed,
#   Helm rolls back to the previous release itself. This is the single best
#   flag in Helm for CD, and the one most often missing.

# ── 4 · ⭐⭐ READ IT BACK ─────────────────────────────────────────────
NOW=$(kubectl -n "$NS" get deploy "$RELEASE" \
      -o jsonpath="{.spec.template.spec.containers[0].image}")
echo "$NOW" | grep -q "${REF#*@}" || { echo "⛔ running $NOW, wanted $REF"; exit 1; }
echo "✅ helm revision $(helm -n $NS history $RELEASE --max 1 -o json | jq '.[0].revision') running $NOW"
```

| Helm flag | ⭐ Why |
|---|---|
| `--atomic` | automatic rollback on a failed upgrade. **The best flag for CD** |
| `--wait` | blocks until resources are ready, so the exit code means something |
| `--timeout 10m` | ⛔ the default 5m is too short for a JVM with a migration |
| `--history-max 10` | bounds the stored release secrets (each is a Secret object) |
| ⭐ `helm diff upgrade` | see the change **before** applying it — the approver's evidence |
| `--install` | only if the release may not exist yet; ⛔ in CD it hides a missing release |

⭐ **The `tag: ""` detail:** most charts render `{{ .Values.image.repository }}:{{ .Values.image.tag }}` when a tag is set and `@{{ .Values.image.digest }}` when it is not. If your values file inherits a tag from `values.yaml`, **the tag wins and the digest is ignored** — a green upgrade deploying the wrong artifact. Always set `tag: ""` explicitly and **read the image back**.

---

## 5 · ⭐⭐ The migration Job — the step everyone gets wrong

### 5.1 ⛔ The four wrong ways

| Wrong | Why it breaks |
|---|---|
| Run Flyway on **application start-up** (`spring.flyway.enabled=true`) | ⭐⭐ with 3 replicas, **three** processes race to migrate. Flyway locks, so two fail — and if `fail-on-error` is off, they start anyway against a half-migrated schema |
| Run it in an **init container** on every pod | same race, once per pod, on every rollout |
| Run it **after** the rollout | the new code runs against the old schema → errors for the duration of the rollout |
| Let the rollout continue when it fails | ⛔ a fleet half on the new schema, half on the old, with no signal |

### 5.2 ✅ The right way — a separate Job that **gates** the rollout

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: shop-api-migrate
  namespace: shop-production
  labels: { app: shop-api, component: migrate }
spec:
  backoffLimit: 0               # ⭐⭐ DO NOT RETRY. A failed migration needs a
                                #   human, not a second attempt that may have
                                #   half-applied the first.
  ttlSecondsAfterFinished: 86400   # ⭐ keeps it 24h for inspection, then cleans up
  template:
    metadata:
      labels: { app: shop-api, component: migrate }
    spec:
      restartPolicy: Never      # ⭐ pairs with backoffLimit: 0
      imagePullSecrets: [{ name: acr-pull }]
      containers:
        - name: migrate
          image: shopacr.azurecr.io/shop-api@sha256:PLACEHOLDER
          # ⭐⭐ the SAME digest as the app. Different image = different Flyway
          #   version and possibly different SQL on the classpath.
          command: ["java","-cp","/app/app.jar",
                    "org.springframework.boot.loader.launch.JarLauncher"]
          args: ["--spring.flyway.enabled=true",
                 "--spring.main.web-application-type=none"]
          # ⭐ Spring Boot 3.2+ launcher class. Pre-3.2 it is
          #   org.springframework.boot.loader.JarLauncher — a real gotcha.
          envFrom: [{ configMapRef: { name: shop-api-config } }]
          env:
            - name: DB_PASSWORD
              valueFrom: { secretKeyRef: { name: shop-api-db, key: password } }
          resources:
            requests: { cpu: 250m, memory: 512Mi }
            limits:   { cpu: "1",  memory: 1Gi }
```

```bash
# ⭐ THE SEQUENCE, IN ORDER
kubectl -n shop-production delete job shop-api-migrate --ignore-not-found
kubectl -n shop-production apply  -f k8s/shop-api/migration-job.yaml
kubectl -n shop-production wait   --for=condition=complete job/shop-api-migrate \
                                  --timeout=600s \
  || { echo "⛔ migration FAILED — not rolling out"; \
       kubectl -n shop-production logs job/shop-api-migrate --tail=200; exit 1; }
kubectl -n shop-production set image deploy/shop-api shop-api="$REF"
kubectl -n shop-production rollout status deploy/shop-api --timeout=600s
```

### 5.3 ⭐ The three properties that make it safe

| Property | How |
|---|---|
| ⭐ **Backward-compatible** | expand/contract: the new schema works with the **old** code *and* the new |
| ⭐ **Runs before** the rollout | so no pod ever runs new code against an old schema |
| ⭐ **Gates** the rollout | a failure **stops the pipeline**, it does not warn |

```
✅ ROLLBACK-SAFE (expand/contract)
   release N   : ADD column `quantity`, dual-write, keep reading `qty`
                 ⭐ old code still works → rolling back the image is safe
   release N+1 : READ `quantity`, stop writing `qty`
                 ⭐ still dual-readable → rollback to N is safe
   release N+2 : DROP `qty`
                 ⛔ irreversible — which is why it goes last and ALONE

⛔ NOT ROLLBACK-SAFE
   one release: RENAME `qty` → `quantity` + update the entity
   ⭐ rolling back the image leaves code expecting `qty` against a schema
     with `quantity`. You cannot roll back. You can only roll FORWARD,
     under pressure, at 2 a.m.
```

⭐⭐ **The rule that follows:** *if the migration is not backward-compatible, the release cannot be automatically rolled back — and that alone disqualifies it from Case 2.* See [`../00-delivery-vs-deployment.md`](../00-delivery-vs-deployment.md) prerequisite 5.

---

## 6 · ⭐ Per-app-shape runbooks

### 6.1 🔵 Shape A — FE only (`shop-ui`)

| | Docker | Kubernetes |
|---|---|---|
| Switch | `SHOP_UI_IMAGE=$DIGEST docker compose up -d --wait shop-ui` | `kubectl set image deploy/shop-ui shop-ui=$DIGEST` |
| Verify | `curl -I localhost/` → 200 **and** `index.html` has `no-cache` | `kubectl rollout status` + `curl` the Service |
| ⭐ Unique check | `curl localhost/config.js` — does `API_URL` match this environment? | same, via `port-forward` |
| Rollback | re-`up -d` with the recorded digest | `kubectl rollout undo` — ⭐ trivial |
| Risk | ⭐ **lowest in the estate** | same |
| Gate? | consider **none** → Case 2 | same |

```bash
# ⭐ THE FE-SPECIFIC VERIFICATION — the one that catches the build-time trap
curl -fsS http://localhost/config.js | grep -q "API_URL: \"https://api.shop\"" \
  && echo "✅ runtime config correct for production" \
  || { echo "⛔ WRONG API_URL — the image was built for another environment"; exit 1; }
# WHY THIS EXISTS: if config were baked at build time, the image would be
#   environment-specific and the digest contract would be broken silently.
#   This one check proves it is not.
```

### 6.2 🟢 Shape B — BE only (`shop-api`)

⭐ **This file, §3.2 / §5, in full.** The migration Job gates the rollout. Order: **migrate → set image → rollout status → read back → smoke from inside the cluster**.

### 6.3 🟢 Shape B — worker (`order-worker`)

| Difference | What to do |
|---|---|
| ⛔ **No HTTP health endpoint** | readiness = "connected to the broker". Use an `exec` probe that checks a heartbeat file the worker touches |
| ⭐ **In-flight messages** | `terminationGracePeriodSeconds: 120` — long enough to finish processing, not to accept new work |
| ⛔ Do not scale to 0 during deploy | messages accumulate; the restart storm then reprocesses them |
| ⭐ **Idempotency is a deploy requirement** | a rolling update *will* redeliver some messages. If the handler is not idempotent, every deploy corrupts data |

```yaml
readinessProbe:
  exec:
    command: ["/bin/sh","-c","test -f /tmp/heartbeat && \
      [ $(( $(date +%s) - $(stat -c %Y /tmp/heartbeat) )) -lt 60 ]"]
  periodSeconds: 15
# ⭐ "the worker touched its heartbeat file in the last 60 seconds"
#   — the closest thing to a readiness probe a queue consumer can have.
```

### 6.4 🟡 Shape C — FE + BE (P10)

⭐⭐ **The ordering rule: backend first, always.**

```
1. migrate (Job, gated)              ← DB
2. deploy shop-api, wait for ready   ← BE
3. smoke the BE from inside          ← prove it
4. deploy shop-ui, wait for ready    ← FE
5. smoke the FE + the FE→BE path     ← prove the PAIR
```

| Rule | Why |
|---|---|
| ⭐ **BE before FE** | the backend must serve *both* the old and the new frontend at every instant. The reverse order guarantees a window where cached frontends call endpoints that do not exist |
| ⭐ **One approval for the pair** | the human authorised *this release*; two prompts invite approving the FE after the BE failed |
| ⭐⭐ **Roll back BOTH on FE failure** | a half-promoted pair (new UI, old API) is worse than either alone |
| Verify the **pair**, not just each half | `curl` the FE and have it call the BE — the end-to-end path |

```bash
# ⭐ the FE→BE path check, which neither half's smoke test covers
kubectl -n shop-production run e2e-$RANDOM --rm -i --restart=Never \
  --image=curlimages/curl:8.17.0 -- sh -c '
    set -e
    UI=$(curl -fsS -o /dev/null -w "%{http_code}" http://shop-ui/)
    CFG=$(curl -fsS http://shop-ui/config.js)
    echo "$CFG" | grep -q "api.shop" || { echo "⛔ FE config wrong"; exit 1; }
    API=$(curl -fsS -o /dev/null -w "%{http_code}" http://shop-api:8080/api/v2/orders)
    echo "ui=$UI api=$API"
    [ "$UI" = 200 ] && [ "$API" = 200 ]'
```

### 6.5 🟠 Shape D — polyglot (P11 React+Python, P12 React+Go)

⭐ **Deploy in dependency order, and verify each service the way *it* fails:**

| Order | Service | How it fails | ⭐ How to verify |
|---|---|---|---|
| 1 | `postgres` / `rabbitmq` (P13) | won't start, or the schema is wrong | `pg_isready` · broker management API |
| 2 | `order-worker` (Python) | import error, broker unreachable | heartbeat file, queue depth |
| 3 | `checkout` (Go) | panic at start, bad config | `/readyz` |
| 4 | `payment-mock` (Go) | — | `/healthz` |
| 5 | `shop-api` (Java) | slow start, schema mismatch | `/actuator/health/readiness` — ⭐ with a 150 s startup probe |
| 6 | `shop-ui` (React) | wrong `API_URL`, stale asset URLs | `/config.js`, `index.html` cache header |

```bash
# ⭐ one loop, one manifest — the release train
while IFS='=' read -r svc ref; do
  [ -z "$svc" ] && continue
  case "$svc" in \#*) continue ;; esac
  echo "── deploying $svc"
  REF="$ref" SVC="$svc" ./deploy-k8s.sh || { echo "⛔ $svc failed — HALT"; exit 1; }
done < release-manifest.txt
# ⭐⭐ HALT ON THE FIRST FAILURE. Continuing leaves the estate in a state
#   nobody tested and nobody can describe.
```

---

## 7 · 🗄️ The data tier (P13) — why it is always Case 1

**Apps:** Postgres 17 · Redis 7 · RabbitMQ 4 · Mongo 8 · Elasticsearch 8 · MySQL 9

| Property | Consequence |
|---|---|
| ⭐⭐ **Stateful** | a bad deploy can **destroy data**. There is no rollback |
| Upgrades are **one-way** | a newer server version writes a data directory an older one cannot read |
| Replicas exist | rolling one at a time, with replication lag checks between |
| Backups are the real rollback | ⭐ and a backup you have never restored is a hypothesis |

```
✅ THE ONLY ACCEPTABLE SEQUENCE FOR A DATA-TIER UPGRADE
   1. ⭐ TAKE AND VERIFY A BACKUP — restore it somewhere and check row counts
   2. read the release notes for the version jump (skipping versions is common
      and commonly fatal)
   3. upgrade a REPLICA first; let it catch up; check replication lag == 0
   4. fail over to the upgraded replica
   5. upgrade the old primary
   6. ⭐ leave the old version's binary available for the duration
   7. watch for 24h before calling it done

⛔ NEVER
   - `docker compose pull && up -d` on a Postgres service
   - a StatefulSet `image:` bump with `OnDelete` and a prayer
   - an upgrade with no tested restore
```

⭐ **This is why [`../00-delivery-vs-deployment.md`](../00-delivery-vs-deployment.md) §8 says the data tier is Case 1 permanently.** Not because the team is conservative — because **reversibility is the precondition for automation, and a data directory upgrade is not reversible.**

---

## 8 · ⭐ Rollback on each target

| Target | ⭐ Preferred | Fallback | Time |
|---|---|---|---|
| 🐳 Docker/Compose | re-`up -d` with the **recorded** digest from §2.2 step 1 | `docker run` the previous image manually | ~10–30 s |
| ☸️ kubectl | ⭐ `set image` back to the **recorded** digest | `rollout undo` | ~30–90 s |
| ☸️ Helm | ⭐ `helm rollback <release> <revision>` | `helm upgrade` with the previous values file | ~30–90 s |
| 🗄️ Data tier | ⛔ **restore from backup** | roll FORWARD | hours |

```bash
# ⭐⭐ why "the recorded digest" beats `rollout undo`
kubectl -n shop-production rollout history deploy/shop-api
#   REVISION  CHANGE-CAUSE
#   7         <none>        ← the second-bad deploy
#   8         <none>        ← the first-bad deploy   ⛔ "previous" = THIS
#   9         <none>        ← current
# `rollout undo` goes to 8 — another bad release.
# The recorded digest from step 1 goes to the one you KNOW was good.
```

| Rule | Why |
|---|---|
| ⭐ **Record before you switch** | the record is the rollback. Without it you are guessing |
| ⭐ **No approval gate on rollback** | a gate on the way back is a gate on your own recovery |
| ⭐ **Rollbacks are audited too** | a rollback is a production change |
| ⭐ **Drill it** | a rollback you have never executed is a hypothesis |
| ⛔ **`revisionHistoryLimit` too low** | with `3`, an old-but-good ReplicaSet may already be garbage-collected |

---

## 9 · Verification — what to check after every deploy

⭐ **In this order. Each layer can pass while the one below it is broken.**

| # | Layer | Command | What a pass means |
|---|---|---|---|
| 1 | ⭐ **The image is what you asked for** | `kubectl get deploy -o jsonpath='…containers[?(@.name=="X")].image'` | the digest matches. ⭐ catches silent substitution failures |
| 2 | The pods are ready | `kubectl get pods -l app=X` → `3/3 Running` | replicas converged |
| 3 | The rollout converged | `kubectl rollout status --timeout=600s` | no pod is crash-looping |
| 4 | ⭐ **The Service resolves** | `kubectl run curl --rm -i --image=curlimages/curl -- curl http://X:8080/health` | the selector matches, endpoints exist |
| 5 | The app answers correctly | a real endpoint, not just `/health` | ⭐ `/health` can be 200 while every business endpoint 500s |
| 6 | The **ingress** path works | `curl https://api.shop/api/v2/orders` | TLS, host rules, path rewrite |
| 7 | ⭐ **Metrics did not move** | 5xx ratio, p99 latency vs the same-hour baseline | the release is not worse than the last one |
| 8 | ⭐ **Logs have no new errors** | `kubectl logs deploy/X --since=5m \| grep -i error` | new stack traces are the earliest signal |
| 9 | For shape C/D — the **pair** works | the FE→BE end-to-end check (§6.4) | ⭐ both halves green can still be a broken pair |

```bash
# ⭐ the whole thing as one script — run it in the CD pipeline AND by hand
cat > verify-deploy.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
NS=$1; SVC=$2; WANT=$3
NOW=$(kubectl -n $NS get deploy $SVC -o jsonpath="{.spec.template.spec.containers[?(@.name=='$SVC')].image}")
[ "$NOW" = "$WANT" ] || { echo "⛔ 1 image mismatch: $NOW"; exit 1; }         ; echo "✅ 1 image"
READY=$(kubectl -n $NS get deploy $SVC -o jsonpath='{.status.readyReplicas}')
WANT_R=$(kubectl -n $NS get deploy $SVC -o jsonpath='{.spec.replicas}')
[ "$READY" = "$WANT_R" ] || { echo "⛔ 2 ready $READY/$WANT_R"; exit 1; }      ; echo "✅ 2 pods"
kubectl -n $NS rollout status deploy/$SVC --timeout=300s >/dev/null            ; echo "✅ 3 rollout"
kubectl -n $NS run v-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.17.0 -- \
  curl -fsS "http://$SVC.$NS.svc.cluster.local:8080/actuator/health/readiness" >/dev/null
                                                                                ; echo "✅ 4 service"
NEW_ERRORS=$(kubectl -n $NS logs deploy/$SVC --since=5m --all-containers 2>/dev/null \
             | grep -ciE 'error|exception' || true)
echo "ℹ️  8 new error lines in 5m: $NEW_ERRORS"
EOF
chmod +x verify-deploy.sh
```

---

## 10 · ⭐⭐ The 2 a.m. runbook

**You are the approver. Something is wrong in production. In this order:**

```
STEP 1 · WHAT IS RUNNING?                                    (10 seconds)
   kubectl -n shop-production get deploy -o custom-columns=\
   'NAME:.metadata.name,IMAGE:.spec.template.spec.containers[0].image,READY:.status.readyReplicas'
   ⭐ the digest tells you WHICH release. Cross-reference the audit record
     (§7 of the tool files) for who approved it and why.

STEP 2 · IS IT THE RELEASE, OR SOMETHING ELSE?               (60 seconds)
   - did the error rate step up AT THE DEPLOY TIMESTAMP?  → it is the release
   - did a dependency change? a config change? traffic?    → maybe not
   ⭐ if you cannot tell in 60 seconds, ASSUME IT IS THE RELEASE. Rolling
     back something that was not the cause costs minutes; not rolling back
     something that was costs an incident.

STEP 3 · ROLL BACK. DO NOT DEBUG FIRST.                      (2 minutes)
   🐳  read the previous digest from /opt/shop/releases/*.images.txt
       SHOP_API_IMAGE=<prev> docker compose -f docker-compose.prod.yml up -d --wait
   ☸️  kubectl -n shop-production set image deploy/shop-api shop-api=<prev-digest>
       kubectl -n shop-production rollout status deploy/shop-api --timeout=300s
   ☸️  helm rollback shop-api <prev-revision> -n shop-production --wait
   ⭐ use the RECORDED digest, not `rollout undo` (§8).

STEP 4 · ⛔ DID A MIGRATION RUN?                              (the trap)
   kubectl -n shop-production get jobs -l component=migrate
   - if NO migration ran → the image rollback is COMPLETE. Go to step 5.
   - if a migration DID run → ⭐⭐ the schema has moved forward and the old
     image may not understand it. Check whether the migration was
     expand/contract (§5.3):
       ✅ additive only (new nullable column, new table) → the old image is
          fine. Rollback complete.
       ⛔ destructive (drop/rename/NOT NULL) → YOU CANNOT ROLL BACK.
          Roll FORWARD with a fix. This is exactly why §5.3 exists.

STEP 5 · CONFIRM RECOVERY                                     (2 minutes)
   - the §9 verification list, layers 1–6
   - error rate returning to baseline on the dashboard
   - ⭐ a real user-facing request, not just /health

STEP 6 · WRITE IT DOWN WHILE YOU REMEMBER                     (5 minutes)
   - append to the audit file: type ROLLBACK, digest, who, why
   - ⭐ open the incident ticket NOW, not tomorrow

STEP 7 · ONLY NOW: DEBUG                                       (later)
   - reproduce in staging against the bad digest
   - find the gate that should have caught it
   - ⭐⭐ add that gate. A rollback without a new gate is how the same
     incident happens again next month.
```

| ⭐ The three sentences to remember |
|---|
| **1.** Roll back first, debug second. |
| **2.** Check whether a migration ran — it decides whether rollback is even possible. |
| **3.** Every rollback must produce a new gate, or it will repeat. |

---

<a name="tasks--answers"></a>
## 11 · ⭐ TASKS — answers at the END

| # | Task |
|---|---|
| **T1** | Write `deploy-docker.sh` for the P10 stack (FE + BE) so that a failed deploy rolls back automatically |
| **T2** | Explain precisely why `docker compose down` must never appear in a deploy script, and what to use instead |
| **T3** | Add the six Docker-target rules to a real Compose file and prove `--wait` catches a crash-looping container |
| **T4** | Write `deploy-k8s.sh` with the migration Job gating the rollout, and make a failed migration stop the pipeline |
| **T5** | Add `preStop: sleep 10` to `shop-api` and demonstrate the 502s disappearing during a rolling update |
| **T6** | Deploy a Helm release by digest and prove that a stale `image.tag` in `values.yaml` does not override it |
| **T7** | Change a ConfigMap and show that the running pods do **not** pick it up; then fix it three different ways |
| **T8** | Write the shape-C deploy sequence (BE → FE) with pair-level verification and roll-back-both on FE failure |
| **T9** | Write `verify-deploy.sh` covering layers 1–6 of §9 and wire it into all three tools' CD pipelines |
| **T10** | ⭐⭐ Walk the 2 a.m. runbook against a real bad release: an image whose readiness probe always fails, plus an additive migration. Report what you would see at each step |

---

# ✅ ANSWERS

**T1.** §2.2 verbatim, with three things that make the rollback real: **(a)** step 1 records `docker compose config --images` and `docker inspect` output into `/opt/shop/releases/<timestamp>.*` **before** switching — that record *is* the rollback, and without it you are guessing; **(b)** the health loop curls the FE and the BE from outside Compose for 90 s; **(c)** on failure, `ls -1t *.images.txt | sed -n 2p` selects the *second*-newest record — the newest is the one you just wrote — and re-runs `up -d --wait` with those digests. ⭐ Note the shape-C ordering inside the file: `shop-ui` has `depends_on: shop-api: condition: service_healthy`, and `shop-api` has `condition: service_completed_successfully` on the `migrate` service, so Compose itself enforces **migrate → BE → FE**.

**T2.** ⛔ `docker compose down` **stops every service in the project — including the database — and removes the containers and the default network.** Two consequences: the app is fully offline for the duration (no rolling anything), and any data not on a **named volume** is destroyed. Worse, `down -v` removes named volumes too, so a single wrong flag deletes production data. ✅ Use `docker compose up -d --wait [--remove-orphans]`: Compose diffs the desired state against the running state and **recreates only the services whose image or config changed**, leaving the database, the network and every other container untouched. ⭐ `--remove-orphans` is what cleans up services you deleted from the file — that is the legitimate need people reach for `down` to solve.

**T3.** Apply §2.3's six rules to the P10 file: `${VAR:?message}` on every image (loud failure instead of an empty image reference); `restart: unless-stopped`; `healthcheck` with a realistic `start_period` (⭐ **60 s for the JVM**, 10 s for nginx — a too-short `start_period` makes a healthy app look failed); `depends_on` with `condition: service_healthy` / `service_completed_successfully`; `logging` with `max-size`/`max-file`; `deploy.resources.limits`; named volumes; base images pinned by digest. **Proving `--wait` works:** set `shop-api`'s command to something that exits immediately (`["false"]`), run `up -d --wait`, and observe that it **blocks and then fails with a non-zero exit code** — whereas without `--wait` it returns 0 instantly and the pipeline reports a successful deploy of a container that never ran. ⭐ That single experiment is the argument: without `--wait`, the exit code of `up -d` means "I started the process", not "the service is healthy".

**T4.** §3.2 + §5.2. The Job needs `backoffLimit: 0` and `restartPolicy: Never` (⭐ a failed migration needs a human, not a second attempt that may have half-applied the first), `ttlSecondsAfterFinished: 86400`, and the **same digest** as the app image (a different image can carry a different Flyway version and different SQL on the classpath). The gating is `kubectl wait --for=condition=complete job/shop-api-migrate --timeout=600s || exit 1` **before** `set image`. ⭐ Prove it: add a migration `V999__bad.sql` containing `ALTER TABLE orders ADD COLUMN qty INT NOT NULL;` — which fails because existing rows have no value — and confirm the pipeline stops at the migration with the rollout never attempted, and that `kubectl get deploy` still shows the **previous** digest. Also note the Spring Boot 3.2+ launcher class (`org.springframework.boot.loader.launch.JarLauncher`) — pre-3.2 it has no `.launch` segment, and getting it wrong produces a `ClassNotFoundException` that looks like a migration bug.

**T5.** ⭐ **The mechanism:** Kubernetes removes a terminating pod from Service endpoints **asynchronously** — the API server marks it terminating, and only then do kube-proxy and the ingress controller converge on new endpoint lists. Meanwhile the container has already received SIGTERM and the JVM is shutting down its connector. Requests arriving in that window get connection-refused → the ingress returns 502. You see a small burst of 502s on *every* deploy, which everyone learns to ignore.

`preStop: exec: command: ["/bin/sh","-c","sleep 10"]` runs **before** SIGTERM, so the pod stays fully serving while endpoint removal propagates. Ten seconds is enough for kube-proxy; it costs nothing because the old pod is being replaced anyway.

**Demonstrating it:** run a load generator against the Service (`hey -z 120s -c 20 http://shop-api.shop-production.svc:8080/api/v2/orders`) and trigger `kubectl rollout restart`. Without `preStop` you will see a spike of non-200s exactly at the moment each old pod terminates; with it, zero. ⭐ Pair it with `terminationGracePeriodSeconds: 60` — the grace period must exceed `preStop` duration plus the app's own shutdown time, or Kubernetes SIGKILLs mid-drain and you get the same 502s back.

**T6.** §4. The proof is in two commands. First, deliberately leave `image.tag: v1.4.1` in `values.yaml` while passing `image.digest: sha256:41ab…` in the prod values file, upgrade, and read the image back: `kubectl get deploy shop-api -o jsonpath='{.spec.template.spec.containers[0].image}'`. With most charts it prints `…/shop-api:v1.4.1` — ⛔ **the tag won and the digest was silently ignored**, while `helm upgrade` exited 0 and reported success. Then set `tag: ""` and repeat: the image prints with `@sha256:41ab…`. ⭐ The general lesson is the same one as T10 in the Azure DevOps file: **a deploy tool's exit code is not proof of what is running.** Always set `tag: ""` explicitly *and* read the image back, and use `helm diff upgrade` before the upgrade so the substitution shows up in the approver's evidence.

**T7.** `kubectl apply -f configmap.yaml` changes the ConfigMap object and **nothing else**. Environment variables are read by the process **at start**, so running pods keep the old values; only *newly created* pods get the new ones. The pipeline reports success and the change appears not to have happened. Three fixes, in order of safety: **(1)** ⭐ `kubectl rollout restart deploy/shop-api` — a clean rolling restart, new pods pick up the new env; **(2)** mount the ConfigMap as a **volume** instead of `envFrom` — Kubernetes refreshes mounted files automatically within roughly a minute, and the app must watch the file to react (no restart, but it only works for apps that reload config); **(3)** ⭐ hash the ConfigMap content into a **pod template annotation** — `checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}` in Helm — so any config change alters the pod template and triggers a rollout by itself. Option 3 is the best long-term answer because it makes the failure impossible rather than detectable.

**T8.** §6.4. Sequence: **migrate (gated Job) → deploy `shop-api` → `rollout status` → smoke the BE from inside the cluster → deploy `shop-ui` → `rollout status` → the pair-level e2e check** (curl the FE, assert `config.js` contains the production `API_URL`, curl the BE through the Service, assert both 200). Wrap the FE deploy so a failure runs `set image` back to the **recorded** digest for *both* services. ⭐ **Why roll back both:** a half-promoted pair — new UI calling old API, or old UI against new API — is a state nobody tested and nobody can reason about; it is worse than either consistent state. **Why one approval:** the human authorised *this release*, and the pair is the release. Two prompts create the failure mode where someone approves the FE after the BE failed, producing exactly the half-promoted state. And **why BE first:** the backend must serve both the old and the new frontend at every instant, because cached frontends persist for as long as browser cache dictates — a duration you do not control.

**T9.** §9's script, covering: (1) image read back from the cluster and compared to the requested digest — using the **JSONPath name filter** `[?(@.name=='X')]`, not `[0]`, because a sidecar makes `[0]` wrong; (2) `readyReplicas == spec.replicas`; (3) `rollout status --timeout`; (4) a request to the **Service DNS name from inside the cluster** via a throwaway `curlimages/curl` pod — ⭐ this tests the selector and the endpoints, which an external curl through the ingress cannot isolate; (5) a **real business endpoint**, not just `/health`, because `/health` can be 200 while every business route 500s; (6) the ingress path over HTTPS, which adds TLS, host rules and path rewrites to the things that can be wrong. Wire it as a step *after* the deploy in all three tools (GitHub `run:`, Azure `bash:`, Jenkins `sh`), and ⭐ **fail the pipeline on any layer** — a verify step that only logs is a report, not a gate.

**T10.** ⭐⭐ Walking §10 against an image whose readiness probe always fails, with an additive migration (`ALTER TABLE orders ADD COLUMN quantity INT`):

- **Step 1 — what is running:** `kubectl get deploy` shows `READY 3/3` but `kubectl get pods` shows **6 pods**: 3 old ones `Running 1/1`, 3 new ones `Running 0/1` with `READY` false and `RESTARTS` climbing. ⭐ This is the signature of a **stuck rolling update**, not a crash: `maxUnavailable: 0` means Kubernetes will not remove an old pod until a new one is Ready, so the deployment is frozen with both ReplicaSets live. The digest column shows the new digest on the Deployment — **which is misleading**, because the Deployment's *spec* moved while the *serving pods* did not. This is exactly why §9 layer 1 must be paired with layer 2: the image check passes and the ready check fails.
- **Step 2 — is it the release:** yes, unambiguously — the timestamps of the new pods coincide with the deploy, and traffic is still being served by the *old* pods, so user-facing errors may be **zero**. ⭐ An important subtlety: this failure is *quiet*. No 502s, because no bad pod ever received traffic. The only signals are the rollout not converging and `kubectl describe deploy` showing `ProgressDeadlineExceeded`. That is why the CD pipeline's `rollout status --timeout` is the gate that catches it — a metrics-based gate would not.
- **Step 3 — roll back:** `kubectl set image deploy/shop-api shop-api=<recorded previous digest>`; the new ReplicaSet scales to the known-good image and the stuck one scales down. Fast, because the old pods were never removed.
- **Step 4 — did a migration run:** `kubectl get jobs -l component=migrate` shows it **Completed**. ⭐⭐ This is the decisive question, and the answer here is benign: the migration was **additive** (a new nullable column), so the *old* image simply ignores a column it does not know about. Rollback is safe. **If it had been `DROP COLUMN qty` or a rename, rollback would be impossible** and you would be rolling forward under pressure — which is precisely why §5.3 requires expand/contract and why [`../00-delivery-vs-deployment.md`](../00-delivery-vs-deployment.md) prerequisite 5 gates Case 2.
- **Step 5 — confirm recovery:** §9 layers 1–6, plus the error-rate panel returning to baseline, plus one real user-facing request.
- **Step 6 — write it down:** append a `ROLLBACK` record to the audit file, open the incident ticket.
- **Step 7 — the gate you add:** ⭐ two of them. First, the deploy pipeline must **fail on `rollout status` timeout and auto-undo** (§3.2 steps 4–5) — in this scenario it did, which is why the stuck state was caught by the pipeline rather than by a user. Second, and more interestingly: **the readiness probe must be verified in CI, not just in production.** A container image whose readiness endpoint never returns 200 can be caught by running the image in CI and probing it — which is a Scenario 1 concern, and the clearest example in this whole folder of *a CD incident whose real fix belongs in CI.*

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish_Kumar_Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn: https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260
🔗 GitHub: https://github.com/3558Bhk

*A deploy tool's exit code says the tool ran. Reading the cluster back says what is running.*

</div>
