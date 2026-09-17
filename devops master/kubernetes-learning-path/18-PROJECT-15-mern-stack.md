# 🟣 Project 15 — MERN Stack on Kubernetes

> **Time:** 4–5 hours · **Prereq:** [Project 5 — Storage & StatefulSet](08-PROJECT-5-storage-statefulset.md), [Project 13.2 — MongoDB](16-PROJECT-13-databases.md), and [Docker Project 14 — MERN](../docker-learning-path/17-PROJECT-14-mern-stack.md)
>
> React 19 + Node 24 + Express 5 + MongoDB 8, deployed as **two Deployments and one replica-set StatefulSet** — with the migration as a **gated Job**, the backup as a **CronJob**, and the schema enforced by nothing but your own code.
>
> **Why this project is last:** every earlier project treated the database as infrastructure that already exists. Here the database ships **inside** the release. That changes the ordering, the rollback, the probes and the risk — and it is the shape most teams actually run.

---

## 15.0 Why MERN is the hardest shape on Kubernetes

```
Projects 8–12 taught you to deploy an application.
Project 13 taught you to deploy a database.
⭐ This project teaches you what happens when they are the SAME RELEASE.
```

| | Projects 8–12 (app only) | Project 13 (db only) | ⭐ Project 15 (MERN) |
|---|---|---|---|
| What ships | a Deployment | a StatefulSet | **both, together, in order** |
| The schema | someone else's problem | the database enforces it | ⛔ **your code enforces it** |
| Rollback | `rollout undo` | ⛔ a restore | ⛔ **`rollout undo` + a decision about the data** |
| Migrations | Flyway/Alembic, ledgered | n/a | ⭐⭐ **you build the ledger** |
| Probe complexity | one readiness path | `mongosh` exec | ⭐ **three endpoints with different meanings** |
| Transactions | SQL, always | n/a | ⛔ **require a replica set, silently skip without one** |

⭐⭐ **The sentence that defines this project:**

> *Kubernetes is excellent at making stateless things converge, and MongoDB is a stateful thing whose schema nobody enforces. MERN puts those two facts in the same release.*

### What can go wrong that cannot go wrong in Project 12

```
⛔ 1. A rolling update runs TWO VERSIONS OF YOUR API against the SAME
      collection. Postgres would reject the invalid row. MongoDB accepts
      both, so your data becomes a MIX — and nothing alerts.

⛔ 2. `autoIndex: true` builds indexes on every new pod, simultaneously,
      during the rollout.

⛔ 3. The connection string is pinned to mern-mongo-0. A failover makes
      pod 0 a secondary and every write fails.

⛔ 4. `livenessProbe` points at the endpoint that queries mongo. A 5-second
      election restart-loops your ENTIRE fleet.

⛔ 5. The migration Job succeeds, the Deployment rolls out, and then the
      rollback restores the OLD code against the NEW data.

⛔ 6. Someone deletes the StatefulSet "to redeploy it" and the PVCs go
      with it, because volumeClaimTemplates are not obviously separate
      objects.
```

Every section below exists to close one of those six.

---

## 15.1 The app and the target architecture

```
                       ┌──────────────────────────────────────┐
   browser ──────────▶ │ Ingress  shop.example.com            │
                       └───────┬──────────────────────┬───────┘
                               │ /                    │ /api
                               ▼                      ▼
                     ┌──────────────────┐   ┌──────────────────────┐
                     │  mern-web        │   │  mern-api            │
                     │  Deployment ×2   │   │  Deployment ×3       │
                     │  nginx :80       │   │  node :4000          │
                     │  /config.js      │   │  /healthz /readyz    │
                     └──────────────────┘   └───────┬──────────────┘
                                                    │ 27017
                          ⭐ ordered: migrate → api → web
                                                    ▼
                                    ┌────────────────────────────────┐
                                    │ mern-mongo  StatefulSet ×3     │
                                    │  rs0 · headless Service        │
                                    │  mern-mongo-{0,1,2}.mern-mongo │
                                    │  PVC per pod: data + configdb  │
                                    └────────────────────────────────┘

   Plus, as Jobs (not Deployments):
     • mern-api-migrate     ← ⭐ gated, backoffLimit: 0, SAME digest as the api
     • mern-mongo-initiate  ← ⭐ rs.initiate(), idempotent, PostSync
     • mern-mongo-backup    ← CronJob, mongodump --oplog + restore verify
```

| Resource | Kind | Replicas | ⭐ Why this kind |
|---|---|---|---|
| `mern-web` | Deployment | 2 | stateless; `maxUnavailable: 0` |
| `mern-api` | Deployment | 3 | stateless; needs a real drain |
| `mern-mongo` | **StatefulSet** | 3 | ⭐ stable network identity + a PVC **per pod** |
| `mern-mongo` (svc) | Service, ⭐ **headless** | — | `clusterIP: None` gives each pod stable DNS |
| `mern-mongo-initiate` | Job | 1 | runs once, idempotently |
| `mern-api-migrate` | Job | 1 | ⛔ `backoffLimit: 0` |
| `mern-mongo-backup` | CronJob | 1 | nightly, verified |
| `mern-api-config` | ConfigMap | — | non-secret config |
| `mern-mongo` | Secret | — | credentials + the connection string |
| `mern-web-config` | ConfigMap | — | ⭐ `apiUrl` — injected at container start |

### The namespace and the images

```bash
NS=shop                      # or shop-dev / shop-staging / shop-production
kubectl create namespace $NS --dry-run=client -o yaml | kubectl apply -f -

# ⭐⭐ DIGESTS, never tags — the contract from the CI/CD path
WEB=ghcr.io/3558bhk/mern-web@sha256:REPLACE
API=ghcr.io/3558bhk/mern-api@sha256:REPLACE
MONGO=mongo@sha256:REPLACE          # ⭐ the official image, PINNED BY DIGEST
```

---

## 15.2 The images (built in Docker Project 14)

Both images come from [`../docker-learning-path/17-PROJECT-14-mern-stack.md`](../docker-learning-path/17-PROJECT-14-mern-stack.md) §14.5 — the 🟢 CASE 2 multi-stage versions. **Three properties from there are load-bearing here:**

| Property | ⭐ Why Kubernetes depends on it |
|---|---|
| `mern-web` writes `/config.js` at **container start** | one image serves dev, staging and production — so the *digest* can be promoted unchanged |
| `mern-api` has `/healthz` **and** `/readyz` with different meanings | ⭐⭐ the three probes below are only correct because the two endpoints differ |
| `mern-api` ships `migrations/` and `migrate-mongo` | the migration Job uses the **same digest** as the app |

```bash
# ⭐ verify before you deploy — a wrong image is the most common cause of
#   a "successful" rollout that serves nothing
docker buildx imagetools inspect "$API"  | head -5
docker buildx imagetools inspect "$WEB"  | head -5
docker buildx imagetools inspect "$MONGO" | head -5
```

---

## 15.3 MongoDB — the replica-set StatefulSet

### 15.3.1 ⭐ Why a StatefulSet and not a Deployment

| A Deployment would… | A StatefulSet gives you |
|---|---|
| ⛔ give pods random names (`mern-mongo-7d9f-x2k`) | ⭐ **stable ordinal names**: `mern-mongo-0/1/2` |
| ⛔ share ONE PVC between replicas (or none) | ⭐ **`volumeClaimTemplates`** — a PVC **per pod**, surviving the pod |
| ⛔ replace all pods at once | ⭐ `OrderedReady`: one at a time, highest ordinal first |
| ⛔ have no stable DNS | ⭐ `mern-mongo-0.mern-mongo.$NS.svc.cluster.local` |

⭐ **A replica set member must be addressable by a name that survives its restart.** That is the entire reason StatefulSets exist, and MongoDB is the canonical use case.

### 15.3.2 The headless Service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: mern-mongo
  namespace: shop
  labels: { app: mern-mongo }
spec:
  clusterIP: None                 # ⭐⭐ HEADLESS — this is what creates the
                                  #   per-pod DNS records. A normal ClusterIP
                                  #   would load-balance you to a SECONDARY
                                  #   and every write would fail.
  selector: { app: mern-mongo }
  ports: [{ name: mongo, port: 27017, targetPort: 27017 }]
  publishNotReadyAddresses: true   # ⭐ during an election a member may not be
                                   #   Ready, but peers still need to reach it
```

### 15.3.3 The StatefulSet

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mern-mongo
  namespace: shop
  labels: { app: mern-mongo }
spec:
  serviceName: mern-mongo          # ⭐ MUST match the headless Service
  replicas: 3                      # ⭐ 3 for a real replica set; 1 is enough for dev
  # ⭐ OrderedReady: pods come up 0→1→2 and are updated 2→1→0, each waiting
  #   for the previous to be Ready. For a database this is the only safe order.
  podManagementPolicy: OrderedReady
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      partition: 0                 # ⭐ raise this to update ONLY ordinals >= N,
                                   #   which is how you upgrade secondaries first (§15.9)
  revisionHistoryLimit: 5
  selector: { matchLabels: { app: mern-mongo } }
  template:
    metadata: { labels: { app: mern-mongo } }
    spec:
      securityContext:
        fsGroup: 999               # ⭐ mongod's group in the official image —
                                   #   without it /data/db is not writable
        runAsUser: 999
        runAsGroup: 999
      terminationGracePeriodSeconds: 120   # ⭐ flush, step down, close cleanly
      affinity:
        # ⭐⭐ do NOT put all three members on one node
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              podAffinityTerm:
                topologyKey: kubernetes.io/hostname
                labelSelector: { matchLabels: { app: mern-mongo } }
      containers:
        - name: mongod
          image: mongo@sha256:REPLACE        # ⭐⭐ official image, PINNED BY DIGEST
          imagePullPolicy: IfNotPresent
          args:
            - --replSet=rs0                  # ⭐⭐ the whole point
            - --bind_ip_all
            # ⭐⭐ SET THE WIREDTIGER CACHE EXPLICITLY.
            #   Default = 50% of (RAM − 1GB) as mongod SEES it. In a container
            #   it may size from the NODE's RAM → exceeds the limit →
            #   OOMKilled with exit 137 and NO mongod error at all.
            - --wiredTigerCacheSizeGB=1.5
            - --setParameter
            - diagnosticDataCollectionEnabled=true
          ports: [{ name: mongo, containerPort: 27017 }]
          env:
            - name: MONGO_INITDB_ROOT_USERNAME
              valueFrom: { secretKeyRef: { name: mern-mongo, key: username } }
            - name: MONGO_INITDB_ROOT_PASSWORD
              valueFrom: { secretKeyRef: { name: mern-mongo, key: password } }
          # ⭐ READINESS: can this member serve? Must know its replica-set state.
          readinessProbe:
            exec:
              command:
                - /bin/sh
                - -c
                - >
                  mongosh --quiet --norc
                  -u "$MONGO_INITDB_ROOT_USERNAME"
                  -p "$MONGO_INITDB_ROOT_PASSWORD"
                  --authenticationDatabase admin
                  --eval 'const h = db.hello();
                          if (!h.ok) throw new Error("not ok");
                          if (!h.isWritablePrimary && !h.secondary) throw new Error("recovering");
                          print("ok")' | grep -q ok
            initialDelaySeconds: 15
            periodSeconds: 10
            timeoutSeconds: 5
            failureThreshold: 3
          # ⭐ LIVENESS: is the PROCESS alive? ⛔ must NOT check replica-set
          #   state — an election would restart every mongod simultaneously,
          #   which is exactly how you turn a 10-second election into an outage.
          livenessProbe:
            exec:
              command: ["/bin/sh", "-c", "pgrep -x mongod"]
            initialDelaySeconds: 30
            periodSeconds: 20
            timeoutSeconds: 5
            failureThreshold: 6        # ⭐ tolerant — restarting mongod is expensive
          startupProbe:
            exec:
              command: ["/bin/sh", "-c", "pgrep -x mongod"]
            failureThreshold: 30
            periodSeconds: 5           # ⭐ 150 s to recover a large wiredTiger
          resources:
            requests: { cpu: 500m, memory: 2Gi }
            limits:   { cpu: "2",  memory: 3Gi }   # ⭐ cache 1.5GB + connections
          volumeMounts:
            - { name: data,     mountPath: /data/db }
            - { name: configdb, mountPath: /data/configdb }
            - { name: tmp,      mountPath: /tmp }
      volumes:
        - { name: tmp, emptyDir: {} }   # ⭐ so readOnlyRootFilesystem is possible
  # ⭐⭐ A PVC PER POD. These SURVIVE the pod, and survive a StatefulSet
  #   rollout — but NOT `kubectl delete sts` with the default cascade,
  #   and NOT a `helm uninstall` unless you are careful.
  volumeClaimTemplates:
    - metadata: { name: data }
      spec:
        accessModes: [ReadWriteOnce]
        resources: { requests: { storage: 20Gi } }
        # storageClassName: <set explicitly on a real cluster; omit on kind>
    - metadata: { name: configdb }
      spec:
        accessModes: [ReadWriteOnce]
        resources: { requests: { storage: 1Gi } }
```

### 15.3.4 ⭐ `rs.initiate()` — the step everyone misses

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: mern-mongo-initiate
  namespace: shop
  labels: { app: mern-mongo, component: initiate }
  annotations:
    argocd.argoproj.io/hook: PostSync          # ⭐ if you use Argo CD
    argocd.argoproj.io/hook-delete-policy: BeforeHookCreation
spec:
  backoffLimit: 2              # ⭐ retry IS safe here — initiate is idempotent,
                               #   unlike the migration Job (§15.7) where it is not
  ttlSecondsAfterFinished: 86400
  template:
    metadata: { labels: { app: mern-mongo, component: initiate } }
    spec:
      restartPolicy: OnFailure
      containers:
        - name: initiate
          image: mongo@sha256:REPLACE
          env:
            - name: MONGO_USER
              valueFrom: { secretKeyRef: { name: mern-mongo, key: username } }
            - name: MONGO_PASS
              valueFrom: { secretKeyRef: { name: mern-mongo, key: password } }
          command: ["/bin/sh","-c"]
          args:
            - |
              set -eu
              HOST0="mern-mongo-0.mern-mongo.${POD_NS}.svc.cluster.local"
              HOST1="mern-mongo-1.mern-mongo.${POD_NS}.svc.cluster.local"
              HOST2="mern-mongo-2.mern-mongo.${POD_NS}.svc.cluster.local"

              echo "⏳ waiting for $HOST0 to accept connections…"
              for i in $(seq 1 60); do
                if mongosh --host "$HOST0" --quiet -u "$MONGO_USER" -p "$MONGO_PASS" \
                     --authenticationDatabase admin --eval 'db.adminCommand({ping:1}).ok' \
                     >/dev/null 2>&1; then break; fi
                sleep 5
              done

              # ⭐⭐ IDEMPOTENT: "AlreadyInitialized" is SUCCESS, not failure.
              #   A Job that fails on the second run will be retried forever.
              OUT=$(mongosh --host "$HOST0" --quiet -u "$MONGO_USER" -p "$MONGO_PASS" \
                    --authenticationDatabase admin --eval '
                try {
                  rs.initiate({_id:"rs0", members:[
                    {_id:0, host:"'"$HOST0"'", priority:2},
                    {_id:1, host:"'"$HOST1"'", priority:1},
                    {_id:2, host:"'"$HOST2"'", priority:1}]});
                  "ok"
                } catch (e) {
                  e.codeName === "AlreadyInitialized" ? "ok" : "fail:" + e.message
                }')
              echo "$OUT"
              echo "$OUT" | grep -q '^ok$' || { echo "⛔ initiate failed"; exit 1; }

              echo "⏳ waiting for a PRIMARY…"
              for i in $(seq 1 60); do
                S=$(mongosh --host "$HOST0" --quiet -u "$MONGO_USER" -p "$MONGO_PASS" \
                    --authenticationDatabase admin \
                    --eval 'rs.status().members.filter(m=>m.stateStr==="PRIMARY").length')
                [ "$S" = "1" ] && { echo "✅ rs0 has a PRIMARY"; exit 0; }
                sleep 5
              done
              echo "⛔ no PRIMARY after 5 minutes"; exit 1
          envFrom: []
          env:
            - name: POD_NS
              valueFrom: { fieldRef: { fieldPath: metadata.namespace } }
```

```bash
kubectl -n $NS apply -f mongo-initiate-job.yaml
kubectl -n $NS wait --for=condition=complete job/mern-mongo-initiate --timeout=420s
kubectl -n $NS logs job/mern-mongo-initiate --tail=20
# ✅ EXPECT: "✅ rs0 has a PRIMARY"
```

```
⛔ THE FAILURE MODE IF YOU SKIP THIS:
   mongod starts with --replSet rs0 and then WAITS to be initiated. It is not
   a replica set yet. Your api connects, reads may work, and:
      • transactions throw "Transaction numbers are only allowed on a
        replica set member or mongos"
      • or, worse, code guarded by `if (session)` SILENTLY skips the
        transaction — so your "atomic" order creation is not atomic, your
        tests pass, and you find out during an incident.
```

### 15.3.5 ⭐⭐ The connection string — list every member

```yaml
apiVersion: v1
kind: Secret
metadata: { name: mern-mongo, namespace: shop }
type: Opaque
stringData:
  username: shop
  password: REPLACE_FROM_A_SECRET_MANAGER
  # ⭐⭐ LIST ALL THREE MEMBERS.
  url: >-
    mongodb://shop:REPLACE@mern-mongo-0.mern-mongo.shop.svc.cluster.local:27017,mern-mongo-1.mern-mongo.shop.svc.cluster.local:27017,mern-mongo-2.mern-mongo.shop.svc.cluster.local:27017/shop?replicaSet=rs0&authSource=admin&retryWrites=true&w=majority&readPreference=primaryPreferred&serverSelectionTimeoutMS=10000
```

```
⛔ THE MOST COMMON MERN-ON-KUBERNETES MISTAKE:
     mongodb://mern-mongo-0.mern-mongo:27017/shop?replicaSet=rs0
   pinned to pod 0. The moment pod 0 is NOT the primary — after a failover,
   a rolling update, a node drain — every write fails or blocks.

⭐ THE FOUR PARAMETERS THAT MATTER:
   replicaSet=rs0        → topology discovery; without it the driver treats
                           it as standalone and transactions fail
   retryWrites=true      → a write retried once across a primary election
   ⭐⭐ w=majority        → without it, a write acknowledged by a primary that
                           then steps down is LOST. This is a DATA-LOSS
                           setting and it is the thing people leave at w:1.
   serverSelectionTimeoutMS → fail in 10 s, not the 30 s default that hangs
                           your request handlers and exhausts the pool
```

---

## 15.4 `mern-api` — the Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mern-api
  namespace: shop
  labels: { app: mern-api }
spec:
  replicas: 3
  revisionHistoryLimit: 10         # ⭐ 10 rollbacks available
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0            # ⭐⭐ NEVER drop a replica before a new one
                                   #   is Ready. With a database behind you,
                                   #   a capacity dip becomes an error spike.
      maxSurge: 1
  selector: { matchLabels: { app: mern-api } }
  template:
    metadata:
      labels: { app: mern-api }
      annotations:
        # ⭐⭐ force a rollout when the ConfigMap changes. Env vars are read at
        #   PROCESS START, so `kubectl apply` on a ConfigMap alone changes
        #   NOTHING about running pods. A checksum makes the pod template
        #   differ, which triggers the rollout.
        checksum/config: REPLACE_WITH_SHA256_OF_THE_CONFIGMAP
    spec:
      serviceAccountName: mern-api
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        seccompProfile: { type: RuntimeDefault }
      terminationGracePeriodSeconds: 45   # ⭐ > preStop + drain time
      containers:
        - name: mern-api
          image: ghcr.io/3558bhk/mern-api@sha256:REPLACE   # ⭐⭐ a DIGEST
          imagePullPolicy: IfNotPresent
          ports: [{ name: http, containerPort: 4000 }]
          envFrom:
            - configMapRef: { name: mern-api-config }
          env:
            - name: MONGODB_URL
              valueFrom: { secretKeyRef: { name: mern-mongo, key: url } }
            - name: APP_DIGEST
              # ⭐ so /readyz can report exactly what is running
              value: "sha256:REPLACE"

          # ⭐⭐ STARTUP — node starts in ~1s but the MONGO connection and the
          #   replica-set topology discovery take longer. While this probe runs,
          #   the other two are DISABLED — which is what stops a slow start
          #   from being read as a hang and restart-looping the pod.
          startupProbe:
            httpGet: { path: /healthz, port: http }
            failureThreshold: 15
            periodSeconds: 2
          # ⭐⭐ READINESS — GATES TRAFFIC. Points at /readyz, which QUERIES
          #   MONGO. A pod that cannot reach the database must not receive
          #   requests, but must NOT be restarted.
          readinessProbe:
            httpGet: { path: /readyz, port: http }
            periodSeconds: 10
            timeoutSeconds: 3
            failureThreshold: 3
          # ⭐⭐ LIVENESS — RESTARTS A STUCK PROCESS. Points at /healthz, which
          #   ⛔ MUST NOT TOUCH MONGO. If it did, a 10-second election would
          #   fail liveness on every pod at once and Kubernetes would
          #   restart-loop your entire fleet — turning a blip into an outage.
          livenessProbe:
            httpGet: { path: /healthz, port: http }
            periodSeconds: 20
            timeoutSeconds: 3
            failureThreshold: 3

          lifecycle:
            preStop:
              exec:
                # ⭐⭐ endpoint removal is ASYNCHRONOUS. The API server marks the
                #   pod Terminating; only THEN do kube-proxy and the ingress
                #   converge. Meanwhile your process has already had SIGTERM.
                #   Sleeping first means requests arriving in that window still
                #   get served instead of connection-refused.
                command: ["/bin/sh","-c","sleep 10"]
          resources:
            requests: { cpu: 100m, memory: 128Mi }
            limits:   { cpu: "1",  memory: 512Mi }
          # ⭐ NODE_OPTIONS must be ~75% of the memory LIMIT. A heap that grows
          #   into the container limit is OOMKilled with NO JavaScript error —
          #   only "Last State: Terminated, Reason: OOMKilled, Exit Code: 137".
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities: { drop: ["ALL"] }
          volumeMounts:
            - { name: tmp, mountPath: /tmp }
      volumes:
        - { name: tmp, emptyDir: {} }
      topologySpreadConstraints:
        # ⭐ do not put all three replicas on one node
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: ScheduleAnyway
          labelSelector: { matchLabels: { app: mern-api } }
```

```yaml
apiVersion: v1
kind: ConfigMap
metadata: { name: mern-api-config, namespace: shop }
data:
  NODE_ENV: production
  PORT: "4000"
  REQUIRE_REPLICA_SET: "true"          # ⭐ fail to boot on a standalone mongod
  MONGO_POOL_SIZE: "20"                # ⭐ 3 pods × 20 = 60 connections
  LOG_LEVEL: info
  CONTRACT_VERSION: "2"
---
apiVersion: v1
kind: Service
metadata: { name: mern-api, namespace: shop }
spec:
  selector: { app: mern-api }
  ports: [{ name: http, port: 4000, targetPort: http }]
  # ⭐ ClusterIP, not NodePort: reachable from mern-web and the ingress only
```

### ⭐⭐ The three probes are three different questions

| Probe | Endpoint | Question | On failure Kubernetes… | ⛔ Wrong version |
|---|---|---|---|---|
| `startupProbe` | `/healthz` | "has it finished starting?" | **disables the other two** until it passes | absent → a slow boot trips liveness → **restart-loop forever** |
| `readinessProbe` | ⭐ `/readyz` (queries mongo) | "can it serve a real request?" | removes it from Endpoints — **restarts nothing** | pointed at `/healthz` → a pod with no database connection **receives traffic** |
| `livenessProbe` | ⭐ `/healthz` (never queries mongo) | "is the process stuck?" | **restarts the pod** | pointed at `/readyz` → a mongo blip **restart-loops the whole fleet** |

```
⭐ THE RULE: readiness includes your dependencies; liveness includes as
   little as possible. Every production restart-loop I have seen in a Node
   service was liveness pointed at an endpoint that queries a database.
```

---

## 15.5 `mern-web` — the Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata: { name: mern-web, namespace: shop, labels: { app: mern-web } }
spec:
  replicas: 2
  strategy: { rollingUpdate: { maxUnavailable: 0, maxSurge: 1 } }
  selector: { matchLabels: { app: mern-web } }
  template:
    metadata: { labels: { app: mern-web } }
    spec:
      securityContext: { runAsNonRoot: true, seccompProfile: { type: RuntimeDefault } }
      containers:
        - name: mern-web
          image: ghcr.io/3558bhk/mern-web@sha256:REPLACE   # ⭐⭐ a DIGEST
          ports: [{ name: http, containerPort: 80 }]
          # ⭐⭐ RUNTIME CONFIG. The SAME image serves every environment;
          #   only these values differ. ⛔ Never VITE_API_URL at build time.
          envFrom:
            - configMapRef: { name: mern-web-config }
          env:
            - { name: APP_DIGEST, value: "sha256:REPLACE" }
          readinessProbe:
            httpGet: { path: /healthz, port: http }
            periodSeconds: 5
            failureThreshold: 3
          livenessProbe:
            httpGet: { path: /healthz, port: http }
            periodSeconds: 20
            failureThreshold: 3
          resources:
            requests: { cpu: 20m,  memory: 32Mi }
            limits:   { cpu: 200m, memory: 128Mi }
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true      # ⭐ nginx needs tmpfs for the
            capabilities: { drop: ["ALL"] }   #   cache + the injected config.js
            runAsUser: 101                    # ⭐ the `nginx` user in nginx:alpine
          volumeMounts:
            - { name: cache,   mountPath: /var/cache/nginx }
            - { name: run,     mountPath: /var/run }
            - { name: config,  mountPath: /usr/share/nginx/html/config.js, subPath: config.js }
      volumes:
        - { name: cache, emptyDir: {} }
        - { name: run,   emptyDir: {} }
        # ⭐ alternative to the entrypoint script: render config.js from a
        #   ConfigMap. Simpler, but it needs a rollout to change (env vars do not).
        - name: config
          emptyDir: {}
---
apiVersion: v1
kind: ConfigMap
metadata: { name: mern-web-config, namespace: shop }
data:
  MERN_API_URL: "http://mern-api:4000"   # ⭐ in-cluster; the browser never sees it
  MERN_ENV: "production"
```

```
⭐⭐ WHY THE BROWSER'S API URL IS *NOT* `http://mern-api:4000`:
   That is the CLUSTER-INTERNAL address, used by nginx's `proxy_pass`.
   The browser talks to ONE origin — the ingress — and nginx proxies /api/
   internally. Consequences:
     ✅ no CORS configuration anywhere
     ✅ the api Service is never exposed outside the cluster
     ✅ cookies are same-origin, so SameSite=Lax works
     ✅ the frontend image is identical in every environment
   ⛔ If you inject the browser-facing URL instead, you need CORS, an
     externally reachable api, and a per-environment build.
```

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: mern
  namespace: shop
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "1m"      # ⭐ cap uploads
    nginx.ingress.kubernetes.io/proxy-read-timeout: "30"
    nginx.ingress.kubernetes.io/configuration-snippet: |
      add_header X-App-Digest $upstream_http_x_app_digest always;
spec:
  ingressClassName: nginx
  tls: [{ hosts: [shop.example.com], secretName: mern-tls }]
  rules:
    - host: shop.example.com
      http:
        paths:
          # ⭐⭐ ORDER MATTERS: the more specific path first
          - path: /api
            pathType: Prefix
            backend: { service: { name: mern-api, port: { number: 4000 } } }
          - path: /
            pathType: Prefix
            backend: { service: { name: mern-web, port: { number: 80 } } }
```

---

## 15.6 🔵 CASE 1 — Simple manifests

Everything above is 🟢 CASE 2. Here is the 🔵 CASE 1 you should write **first**, so the comparison is the lesson:

```yaml
# ⛔ CASE 1 — "just make it run"
apiVersion: apps/v1
kind: Deployment
metadata: { name: mern-api }
spec:
  replicas: 1
  selector: { matchLabels: { app: mern-api } }
  template:
    metadata: { labels: { app: mern-api } }
    spec:
      containers:
        - name: mern-api
          image: ghcr.io/3558bhk/mern-api:latest      # ⛔ a TAG
          ports: [{ containerPort: 4000 }]
          env:
            - { name: MONGODB_URL, value: "mongodb://mern-mongo:27017/shop" }
              # ⛔ no replicaSet · ⛔ no w=majority · ⛔ plaintext credentials
          readinessProbe:                             # ⛔ ONE probe, pointed at
            httpGet: { path: /readyz }                #   the endpoint that
            periodSeconds: 10                         #   queries mongo
          livenessProbe:                              # ⛔ and so is liveness
            httpGet: { path: /readyz }
            periodSeconds: 10
---
apiVersion: apps/v1
kind: Deployment                                     # ⛔ a DEPLOYMENT for mongo
metadata: { name: mern-mongo }
spec:
  replicas: 1
  selector: { matchLabels: { app: mern-mongo } }
  template:
    metadata: { labels: { app: mern-mongo } }
    spec:
      containers:
        - name: mongod
          image: mongo:latest                         # ⛔ :latest
          # ⛔ no --replSet · ⛔ no args · ⛔ no resources
          volumeMounts: [{ name: data, mountPath: /data/db }]
      volumes:
        - name: data
          hostPath: { path: /data/mongo }             # ⛔⛔ A HOSTPATH.
          # Tied to ONE node, lost if the pod lands elsewhere, unwritable on
          # a managed cluster, and a privilege-escalation path.
```

| | 🔵 Case 1 | 🟢 Case 2 | ⛔ What Case 1 costs you |
|---|---|---|---|
| Image reference | `:latest` | ⭐ `@sha256:…` | a rollout deploys whatever `latest` means *now* |
| MongoDB | Deployment + hostPath | ⭐ StatefulSet + PVC ×2 | data loss on reschedule; no stable identity |
| Replica set | ⛔ none | ⭐ `rs0` ×3 | **transactions silently do not work** |
| Connection string | `w` default | ⭐ `w=majority` | **writes lost on a primary step-down** |
| Probes | one, on `/readyz` | ⭐ three, correctly split | a mongo blip **restart-loops the fleet** |
| `preStop` | ⛔ none | ⭐ `sleep 10` | a burst of 502s on **every** deploy |
| `maxUnavailable` | default 25% | ⭐ `0` | capacity dips during every rollout |
| Resources | ⛔ none | ⭐ requests + limits | mongod sizes WiredTiger from the node and is OOMKilled |
| Security | ⛔ root, plaintext | ⭐ non-root, Secret, `readOnlyRootFilesystem` | |
| Migration | ⛔ at app startup | ⭐ a gated Job | 3 replicas race; two fail |
| Backup | ⛔ none | ⭐ a verified CronJob | **no rollback exists** |

---

## 15.7 ⭐⭐ Migrations as a gated Job

```
⛔ THE FOUR WRONG WAYS:
   1. `migrate-mongo up` on APPLICATION STARTUP
      → with 3 replicas, THREE processes race. There is no advisory lock in
        migrate-mongo, so two apply the same migration concurrently.
   2. An INIT CONTAINER on every pod
      → the same race, per pod, on every rollout, forever.
   3. Migrating AFTER the rollout
      → new data shape, old code — or old data shape, new code. Errors for
        the whole rollout window.
   4. Letting the rollout continue when the migration fails
      → ⛔ a fleet half on the new shape and half on the old, with no signal.
```

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: mern-api-migrate
  namespace: shop
  labels: { app: mern-api, component: migrate }
spec:
  backoffLimit: 0            # ⭐⭐ DO NOT RETRY. A failed DATA migration needs
                             #   a HUMAN — a second attempt may have half-applied
                             #   the first, and there is no schema to reject it.
  ttlSecondsAfterFinished: 86400   # ⭐ keep 24h so the logs exist during triage
  template:
    metadata: { labels: { app: mern-api, component: migrate } }
    spec:
      restartPolicy: Never   # ⭐ pairs with backoffLimit: 0
      serviceAccountName: mern-migrator
      securityContext: { runAsNonRoot: true, runAsUser: 1000 }
      containers:
        - name: migrate
          image: ghcr.io/3558bhk/mern-api@sha256:REPLACE
          # ⭐⭐ THE SAME DIGEST AS THE APP. A different image can carry a
          #   different migrate-mongo version and DIFFERENT migration files —
          #   so the migration you validated is not the one you ran.
          command: ["npx", "migrate-mongo", "up"]
          envFrom: [{ configMapRef: { name: mern-api-config } }]
          env:
            - name: MONGODB_URL
              valueFrom: { secretKeyRef: { name: mern-mongo, key: url } }
            - name: MONGO_REPLICA_SET
              value: rs0
          resources:
            requests: { cpu: 100m, memory: 256Mi }
            limits:   { cpu: "1",  memory: 1Gi }
```

```bash
# ⭐⭐ THE SEQUENCE — the whole of MERN deployment, in order
set -euo pipefail
NS=shop

# 0 · ⭐⭐ BACK UP AND *VERIFY* THE BACKUP FIRST (§15.8)
kubectl -n $NS create job --from=cronjob/mern-mongo-backup "backup-pre-$(date +%s)"
kubectl -n $NS wait --for=condition=complete job/$(kubectl -n $NS get jobs -o name | tail -1 | cut -d/ -f2) --timeout=900s

# 1 · MIGRATE, GATED
kubectl -n $NS delete job mern-api-migrate --ignore-not-found
kubectl -n $NS apply -f migrate-job.yaml
kubectl -n $NS wait --for=condition=complete job/mern-api-migrate --timeout=900s \
  || { echo "⛔ MIGRATION FAILED — NOT rolling out"
       kubectl -n $NS logs job/mern-api-migrate --tail=200
       echo "⭐ the data may be partially migrated. Do NOT roll out. Do NOT retry
             blindly. Read the ledger: db.schema_migrations"
       exit 1; }

# 2 · ⭐ BACKEND FIRST — it must serve both the old and the new frontend
kubectl -n $NS set image deploy/mern-api mern-api="$API"
kubectl -n $NS rollout status deploy/mern-api --timeout=600s

# 3 · ⭐ smoke the API — a BUSINESS endpoint, not just /readyz
kubectl -n $NS run smoke-$RANDOM --rm -i --restart=Never \
  --image=curlimages/curl:8.17.0 -- sh -c '
    set -e
    curl -fsS http://mern-api:4000/readyz
    curl -fsS http://mern-api:4000/api/v2/orders
    curl -fsS http://mern-api:4000/api/contract-version'

# 4 · THEN the frontend
kubectl -n $NS set image deploy/mern-web mern-web="$WEB"
kubectl -n $NS rollout status deploy/mern-web --timeout=300s

# 5 · ⭐⭐ READ IT BACK — with the NAME FILTER, never [0]
for pair in "mern-api $API" "mern-web $WEB"; do
  set -- $pair
  NOW=$(kubectl -n $NS get deploy "$1" \
        -o jsonpath="{.spec.template.spec.containers[?(@.name=='$1')].image}")
  [ "$NOW" = "$2" ] || { echo "⛔ $1 is running $NOW, wanted $2"; exit 1; }
  echo "✅ $1 = $NOW"
done

# 6 · ⭐ prove the ledger advanced
kubectl -n $NS exec mern-mongo-0 -- mongosh --quiet -u shop -p "$PASS" \
  --authenticationDatabase admin shop \
  --eval 'db.schema_migrations.find({},{_id:0,fileName:1,appliedAt:1}).sort({appliedAt:-1}).limit(3).toArray()'
```

⭐ **`kubectl set image` with a mistyped container name SUCCEEDS and changes nothing.** Step 5 is not ceremony — it is the only check that catches it, and it must filter by **name**, because `[0]` returns whichever container the API server listed first (add a sidecar and `[0]` is the sidecar).

---

## 15.8 ⭐ Backups as a CronJob — the only rollback MongoDB has

```yaml
apiVersion: batch/v1
kind: CronJob
metadata: { name: mern-mongo-backup, namespace: shop }
spec:
  schedule: "23 2 * * *"              # ⭐ NOT on the hour — every cron job in
                                      #   the company runs at 0 3 * * *
  timeZone: UTC
  concurrencyPolicy: Forbid           # ⛔ two dumps at once lag the primary
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 7           # ⭐ keep FAILURES visible. A backup job
                                      #   that has been failing for six weeks
                                      #   with history=1 is how you discover
                                      #   you have no backup during the incident.
  startingDeadlineSeconds: 3600
  jobTemplate:
    spec:
      backoffLimit: 1
      activeDeadlineSeconds: 3600
      template:
        spec:
          restartPolicy: OnFailure
          serviceAccountName: mern-backup
          containers:
            - name: backup
              image: mongo@sha256:REPLACE
              env:
                - name: MONGO_USER
                  valueFrom: { secretKeyRef: { name: mern-mongo, key: username } }
                - name: MONGO_PASS
                  valueFrom: { secretKeyRef: { name: mern-mongo, key: password } }
                - name: MONGODB_URL
                  valueFrom: { secretKeyRef: { name: mern-mongo, key: url } }
              command: ["/bin/sh","-c"]
              args:
                - |
                  set -euo pipefail
                  STAMP=$(date -u +%Y%m%dT%H%M%SZ)
                  OUT=/backup/mern-$STAMP.archive.gz

                  # ── 1 · TAKE IT ─────────────────────────────────────────
                  # ⭐ --oplog = a POINT-IN-TIME-CONSISTENT dump of a LIVE
                  #   database. ⛔ without it, a write landing mid-dump
                  #   produces a TORN backup that restores to a state that
                  #   never existed.
                  # ⭐ --readPreference=secondary → do not add load to the primary
                  mongodump --uri="$MONGODB_URL" \
                            --gzip --archive="$OUT" --oplog \
                            --readPreference=secondaryPreferred
                  echo "✅ dumped: $(du -h "$OUT" | cut -f1)"

                  # ── 2 · ⛔ REFUSE A SUSPICIOUSLY SMALL ARCHIVE ───────────
                  SIZE=$(stat -c %s "$OUT")
                  [ "$SIZE" -gt 10000 ] || { echo "⛔ archive is ${SIZE} bytes"; exit 1; }

                  # ── 3 · ⭐⭐ PROVE IT RESTORES — into a THROWAWAY mongod ──
                  #   A BACKUP YOU HAVE NEVER RESTORED IS A HYPOTHESIS.
                  mongod --dbpath /tmp/verify --replSet verify --port 27099 \
                         --bind_ip 127.0.0.1 --fork --logpath /tmp/verify.log
                  sleep 8
                  mongosh --quiet --port 27099 --eval 'rs.initiate()' >/dev/null
                  sleep 6
                  mongorestore --port 27099 --gzip --archive="$OUT" \
                               --nsFrom='shop.*' --nsTo='verify.*' \
                               --numInsertionWorkers 4

                  # ── 4 · ⭐ COMPARE COUNTS — the check an empty archive
                  #      and a successful exit code both pass ──────────────
                  FAIL=0
                  for c in orders users products; do
                    SRC=$(mongosh --quiet "$MONGODB_URL" --eval "db.getSiblingDB('shop').$c.countDocuments()")
                    DST=$(mongosh --quiet --port 27099 --eval "db.getSiblingDB('verify').$c.countDocuments()")
                    if [ "$SRC" = "$DST" ]; then echo "✅ $c: $SRC documents verified"
                    else echo "⛔ $c: source=$SRC restored=$DST"; FAIL=1; fi
                  done

                  mongod --port 27099 --shutdown || true
                  rm -rf /tmp/verify
                  [ "$FAIL" = 0 ] || exit 1
                  echo "✅ backup $STAMP VERIFIED"
              volumeMounts: [{ name: backup, mountPath: /backup }]
              resources:
                requests: { cpu: 250m, memory: 512Mi }
                limits:   { cpu: "1",  memory: 2Gi }
          volumes:
            - name: backup
              persistentVolumeClaim: { claimName: mern-backup }
```

```bash
# ⭐ run it NOW, on purpose, rather than discovering it at 03:00
kubectl -n $NS create job --from=cronjob/mern-mongo-backup "manual-$(date +%s)"
kubectl -n $NS wait --for=condition=complete job/manual-… --timeout=900s
kubectl -n $NS logs job/manual-… --tail=30
# ✅ EXPECT: "✅ orders: N documents verified" for every collection, then
#            "✅ backup <stamp> VERIFIED"
```

```
⭐⭐ THE CONSEQUENCE FOR ROLLBACK — read this before your first incident:

   `kubectl rollout undo deploy/mern-api` restores your CODE.
   It does NOT restore your DATA.

   If the migration reshaped documents, the rolled-back code is now reading
   data the NEW code wrote. That is frequently WORSE than not rolling back,
   and the pipeline reports "rollback succeeded".

   The only data rollback is mongorestore from a verified backup — which
   discards every write since the backup. ⛔ That is a decision a human
   must make, with a business owner in the room.

   ⭐ This is the deepest reason MERN is 🔒 Continuous Delivery and not
     🤖 Continuous Deployment, until every migration is provably
     expand/contract, idempotent and batched.
```

---

## 15.9 Upgrading MongoDB itself — never in the app's release train

```
⛔ NEVER bump mongo 8.0 → 8.2 in the same change as an app deploy.

✅ THE SEQUENCE — and MongoDB's rule is strict: you may NOT skip a
   feature-compatibility version.
   1. ⭐ take and VERIFY a backup (§15.8)
   2. confirm the current fCV:
        db.adminCommand({ getParameter: 1, featureCompatibilityVersion: 1 })
   3. read the release notes for the exact jump
   4. ⭐ UPGRADE SECONDARIES FIRST using the StatefulSet `partition`:
        kubectl -n $NS patch sts mern-mongo --type=merge \
          -p '{"spec":{"updateStrategy":{"rollingUpdate":{"partition":1}}}}'
        kubectl -n $NS set image sts/mern-mongo mongod=mongo@sha256:<8.2>
      → only ordinals >= 1 (pods 1 and 2) are updated. Pod 0 stays on 8.0
        and remains PRIMARY.
   5. ⭐ between EACH pod, check replication has caught up:
        rs.printSecondaryReplicationInfo()      → lag must be 0
        rs.status().members[].stateStr          → one PRIMARY, two SECONDARY
   6. step the primary down so an upgraded node takes over:
        rs.stepDown(60)
   7. now lower the partition to 0 and let pod 0 update
   8. ⭐ ONLY THEN raise the fCV:
        db.adminCommand({ setFeatureCompatibilityVersion: "8.2" })
   9. ⛔ LOWERING fCV BACK IS A ONE-WAY DOOR in some versions — which is why
      step 8 is LAST, and why the backup in step 1 is the real rollback
  10. watch for 24 hours
```

⭐ **The consequence for your pipeline:** the MongoDB image reference must **not** live in the same manifest as `mern-api` and `mern-web`. Give it its own file (or its own Helm values key and its own approval), so an ordinary app deploy can never move the database.

---

## 15.10 Debugging

```bash
# ── ⭐ the first four commands, in order ───────────────────────────────
kubectl -n $NS get pods -l 'app in (mern-web,mern-api,mern-mongo)' -o wide
kubectl -n $NS describe pod -l app=mern-api | sed -n '/Events/,$p'
kubectl -n $NS logs deploy/mern-api --tail=200
kubectl -n $NS get events --sort-by=.lastTimestamp | tail -20

# ── is the replica set actually healthy? ──────────────────────────────
kubectl -n $NS exec mern-mongo-0 -- mongosh --quiet -u shop -p "$PASS" \
  --authenticationDatabase admin --eval '
    rs.status().members.map(m => `${m.name} ${m.stateStr} health=${m.health}`)'
# ✅ one PRIMARY, two SECONDARY, all health=1
kubectl -n $NS exec mern-mongo-0 -- mongosh --quiet -u shop -p "$PASS" \
  --authenticationDatabase admin --eval 'rs.printSecondaryReplicationInfo()'
# ⭐ lag must be 0. Persistent lag = your writes are not durable at w=majority

# ── what does the API think? ──────────────────────────────────────────
kubectl -n $NS run d-$RANDOM --rm -it --restart=Never --image=curlimages/curl:8.17.0 -- sh
  curl -s  http://mern-api:4000/readyz | jq
  # ⭐ {ok:true, replicaSet:"rs0", contract:2, digest:"sha256:…"}
  # ⛔ {ok:false, reason:"not-a-replica-set"}  → §15.3.4 never ran
  curl -sI http://mern-web/config.js    # ✅ Cache-Control: no-store
  curl -s  http://mern-web/config.js    # ✅ apiUrl is THIS environment's

# ── ⭐ the read-back, which catches the silent no-op ──────────────────
kubectl -n $NS get deploy mern-api \
  -o jsonpath="{.spec.template.spec.containers[?(@.name=='mern-api')].image}"; echo
# ⛔ `{.spec.template.spec.containers[0].image}` is WRONG once a sidecar exists

# ── did the migration actually run? ───────────────────────────────────
kubectl -n $NS get jobs -l component=migrate
kubectl -n $NS logs job/mern-api-migrate --tail=100
kubectl -n $NS exec mern-mongo-0 -- mongosh --quiet -u shop -p "$PASS" \
  --authenticationDatabase admin shop --eval '
    db.schema_migrations.find({},{_id:0,fileName:1,appliedAt:1}).sort({appliedAt:-1}).limit(5).toArray()'

# ── which indexes exist, and are they used? ───────────────────────────
kubectl -n $NS exec mern-mongo-0 -- mongosh --quiet -u shop -p "$PASS" \
  --authenticationDatabase admin shop --eval 'db.orders.getIndexes()'
kubectl -n $NS exec mern-mongo-0 -- mongosh --quiet -u shop -p "$PASS" \
  --authenticationDatabase admin shop --eval '
    db.orders.find({status:"PAID"}).sort({createdAt:-1}).limit(1).explain("executionStats")
      .queryPlanner.winningPlan'
# ⛔ a COLLSCAN here means your index migration did not run or is not used

# ── ⭐ are documents MIXED? the MERN-specific check ───────────────────
kubectl -n $NS exec mern-mongo-0 -- mongosh --quiet -u shop -p "$PASS" \
  --authenticationDatabase admin shop --eval '({
     withQty:      db.orders.countDocuments({qty:      {$exists:true}}),
     withQuantity: db.orders.countDocuments({quantity: {$exists:true}}),
     withNeither:  db.orders.countDocuments({qty:{$exists:false},quantity:{$exists:false}})
   })'
# ⭐ both non-zero = you are mid-expand/contract (expected) OR you deployed a
#   breaking change during a rollout (⛔ incident — see Task 15.8)

# ── Node heap / OOM diagnosis ─────────────────────────────────────────
kubectl -n $NS get pods -l app=mern-api -o jsonpath='{range .items[*]}{.metadata.name}{" restarts="}{.status.containerStatuses[0].restartCount}{" last="}{.status.containerStatuses[0].lastState.terminated.reason}{"\n"}{end}'
# ⛔ last=OOMKilled → NODE_OPTIONS=--max-old-space-size is above the limit
```

| Symptom | Cause | Fix |
|---|---|---|
| ⛔ `Transaction numbers are only allowed on a replica set member or mongos` | standalone mongod | §15.3.3 `--replSet rs0` + §15.3.4 `rs.initiate()` |
| Transactions silently do nothing | code guarded by `if (session)` | ⭐ `REQUIRE_REPLICA_SET=true` + the `hello.setName` check in `db.ts` |
| ⛔ Writes fail after a pod restart | the URL is pinned to `mern-mongo-0` | §15.3.5 — list **all** members |
| A write disappears after a failover | `w:1` | ⭐ `w=majority` + `retryWrites=true` |
| Requests hang 30 s then fail | `serverSelectionTimeoutMS` default | set it to 10000 |
| ⛔ Every pod restart-loops during a mongo election | `livenessProbe` on `/readyz` | ⭐ liveness → `/healthz` (never touches mongo) |
| `/readyz` is UP but queries fail | readiness does not ping mongo | a real `adminCommand({ping:1})` |
| ⛔ OOMKilled mongod, exit 137, no error | WiredTiger sized from the node's RAM | ⭐ `--wiredTigerCacheSizeGB` explicitly |
| OOMKilled api, no JS error | `NODE_OPTIONS` above the memory limit | ⭐ ~75% of the limit |
| `CrashLoopBackOff` on the api at startup | it connects before mongo is Ready | `startupProbe` + a longer `serverSelectionTimeoutMS` |
| ⛔ A burst of 502s on every deploy | no `preStop` — endpoint removal is async | ⭐ `preStop: sleep 10` + `maxUnavailable: 0` |
| Index build takes 10 minutes on every rollout | `autoIndex: true` | ⭐ `autoIndex: false`; indexes via migration |
| Query plans change mid-rollout | `syncIndexes()` on a rolling fleet | ⛔ never call it |
| ⛔ The migration ran three times | `migrate-mongo up` at app startup | §15.7 — a separate Job |
| The migration Job retries and half-applies | `backoffLimit` > 0 | ⭐ `backoffLimit: 0` |
| ConfigMap changed, nothing happened | env vars are read at process start | ⭐ the `checksum/config` annotation, or `rollout restart` |
| ⛔ The PVC vanished with the StatefulSet | `kubectl delete sts` cascades | `--cascade=orphan`, or delete pods not the STS |
| Blank page, no error | `config.js` missing or a syntax error | ⭐ `cfg()` throws; check `curl /config.js` |
| Deep links 404 | no SPA fallback | `try_files $uri $uri/ /index.html` |
| Users see the old bundle for hours | `index.html` cached | ⭐ `no-cache` index.html / `immutable` assets / `no-store` config.js |

---

## 15.11 Extra Tasks

### Task 15.1 — Deploy the three-member replica set and prove it survives a node loss

Bring up `mern-mongo` as a 3-member StatefulSet, initiate `rs0`, then delete the primary pod and the node it runs on. Writes must not fail.

<details>
<summary>Show answer</summary>

```bash
NS=shop
kubectl -n $NS apply -f mongo-statefulset.yaml -f mongo-headless-svc.yaml
kubectl -n $NS rollout status sts/mern-mongo --timeout=300s
kubectl -n $NS apply -f mongo-initiate-job.yaml
kubectl -n $NS wait --for=condition=complete job/mern-mongo-initiate --timeout=420s

# who is primary?
kubectl -n $NS exec mern-mongo-0 -- mongosh --quiet -u shop -p "$PASS" \
  --authenticationDatabase admin --eval 'rs.hello().primary'

# continuous writes through the chaos
kubectl -n $NS run writer-$RANDOM --rm -i --restart=Never --image=curlimages/curl:8.17.0 -- sh -c '
  for i in $(seq 1 60); do
    printf "%s %s\n" "$(date +%T)" \
      "$(curl -s -o /dev/null -w "%{http_code}" -X POST http://mern-api:4000/api/v2/orders \
         -H "content-type: application/json" -d "{\"sku\":\"s$i\",\"quantity\":1}")"
    sleep 1
  done' > /tmp/writes.txt &
sleep 5

# ⭐ kill the PRIMARY
PRIM=$(kubectl -n $NS exec mern-mongo-0 -- mongosh --quiet -u shop -p "$PASS" \
       --authenticationDatabase admin --eval 'rs.hello().primary' | cut -d. -f1)
kubectl -n $NS delete pod "$PRIM"
wait
sort /tmp/writes.txt | awk '{print $2}' | uniq -c
```

**Expected:** a handful of `500`s or retried writes during the ~5–10 s election, then all `201`. **With `retryWrites=true` and `w=majority`, most clients see zero failures** because the driver retries the write once against the new primary.

**Why each piece is required:**
- ⭐ **`w=majority`** — with `w:1`, a write acknowledged by a primary that then dies is **gone**. The client got a 201. That is silent data loss, and it is the default people leave in place.
- ⭐ **`retryWrites=true`** — turns the election window into a transparent retry instead of an error.
- **`OrderedReady` + `podAntiAffinity`** — the replacement pod rejoins as a secondary and catches up before the next one is touched; and the three members are on different nodes, so losing a node loses one member, not a majority.
- ⛔ **Deleting the node without anti-affinity** can take two of three members, which loses the majority and the replica set becomes **read-only** — writes fail until a member returns.

**The thing to verify afterwards:** `rs.printSecondaryReplicationInfo()` must show lag returning to 0, and `rs.status()` must show one PRIMARY and two SECONDARY. A member stuck in `RECOVERING` means the oplog window was exceeded while it was down — the fix is an initial sync, not a restart.

</details>

### Task 15.2 — Prove the probe split is correct by breaking it

Point `livenessProbe` at `/readyz`, then cause a 10-second mongo election. Record what happens to the fleet.

<details>
<summary>Show answer</summary>

```bash
# ⛔ break it on purpose
kubectl -n $NS patch deploy mern-api --type=json -p '[
  {"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/httpGet/path","value":"/readyz"}]'
kubectl -n $NS rollout status deploy/mern-api

# cause an election
kubectl -n $NS exec mern-mongo-0 -- mongosh --quiet -u shop -p "$PASS" \
  --authenticationDatabase admin --eval 'rs.stepDown(30)'

kubectl -n $NS get pods -l app=mern-api -w
```

**What you will see:** within ~60 s (`periodSeconds: 20` × `failureThreshold: 3`) **all three pods fail liveness simultaneously and are restarted**. While they restart they are not Ready, so there is **zero capacity**, so the election that would have taken ten seconds becomes a full outage — and the restarting pods then race to reconnect, extending it.

**The mechanism, precisely:** liveness failure means *"this process is broken, replace it."* During an election, `/readyz` correctly reports *"I cannot serve"* — which is **true and temporary**. Kubernetes cannot distinguish "temporarily unable to serve" from "permanently stuck", so it does the only thing liveness can do: kill the pod. ⛔ Killing pods is never a remedy for a dependency being briefly unavailable.

**The fix:** `livenessProbe` → `/healthz`, which answers *"can the process respond at all?"* and touches nothing. `readinessProbe` → `/readyz`, which includes the dependency and only removes the pod from rotation until it recovers.

**The general rule worth memorising:** ⭐ *readiness includes your dependencies; liveness includes as little as possible.* And the corollary: if you cannot write a liveness check that does not depend on anything external, you probably should not have a liveness probe at all — an absent liveness probe is safer than a wrong one.

Restore with `kubectl -n $NS rollout undo deploy/mern-api`.

</details>

### Task 15.3 — Make the migration Job gate the rollout, and prove it stops it

<details>
<summary>Show answer</summary>

§15.7's sequence: `delete job --ignore-not-found` → `apply` → ⭐ `kubectl wait --for=condition=complete job/mern-api-migrate --timeout=900s || exit 1` → only then `set image` → `rollout status`.

**Prove it stops the rollout.** Add a migration that must fail on real data:

```javascript
// migrations/20260916000000-bad.js
module.exports = {
  async up(db) {
    // ⛔ a unique index over a field that already contains duplicates
    await db.collection('orders').createIndex({ legacyRef: 1 }, { unique: true });
  },
  async down(db) { await db.collection('orders').dropIndex('legacyRef_1'); },
};
```

Seed two orders with the same `legacyRef`, then run the sequence. **Expected:** the Job fails with `E11000 duplicate key error`, `kubectl wait` returns non-zero, the script prints `⛔ MIGRATION FAILED — NOT rolling out`, and:

```bash
kubectl -n $NS get deploy mern-api -o jsonpath='{.metadata.generation}'   # unchanged
kubectl -n $NS get rs -l app=mern-api --sort-by=.metadata.creationTimestamp -o wide
# ⭐ NO new ReplicaSet was created. The api is still running the PREVIOUS digest.
```

**Three details that make this correct rather than merely cautious:**
- ⭐ **`backoffLimit: 0`** — a failed *data* migration needs a human. An automatic second attempt may have half-applied the first, and MongoDB has no schema to reject the inconsistency, so the retry can make it worse.
- ⭐ **the same digest as the app** — a different image can carry a different `migrate-mongo` version and different migration *files*, so the migration you tested is not the one you ran.
- ⭐ **`ttlSecondsAfterFinished: 86400`** — the logs must still exist when someone triages it tomorrow. A Job that deletes itself on success (`hook-delete-policy: HookSucceeded`) removes the evidence at exactly the moment a *later* stage fails.

**And why this failure is invisible in a SQL stack but not here:** Postgres would reject the duplicate at *insert* time, so the duplicates could not exist. MongoDB let them in, so the constraint only appears when you try to index — which is the point of the shadow-data check in CI.

</details>

### Task 15.4 — Prove `preStop` + `maxUnavailable: 0` removes the 502s

<details>
<summary>Show answer</summary>

```bash
# continuous traffic through a rollout
kubectl -n $NS run hey-$RANDOM --rm -i --restart=Never --image=alpine:3.22 -- sh -c '
  apk add --no-cache curl >/dev/null
  for i in $(seq 1 120); do
    printf "%s %s\n" "$(date +%T)" \
      "$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 http://mern-api:4000/readyz)"
    sleep 0.5
  done' > /tmp/traffic.txt &
sleep 5
kubectl -n $NS rollout restart deploy/mern-api
kubectl -n $NS rollout status  deploy/mern-api
wait
awk '{print $2}' /tmp/traffic.txt | sort | uniq -c
```

**With `preStop: sleep 10` and `maxUnavailable: 0`:** all `200`. **Remove both** (`kubectl patch` the `lifecycle` away and set `maxUnavailable: 1`) and repeat: you get a burst of `000`/`502`/`503` clustered exactly at each old pod's termination.

**The mechanism:** Kubernetes removes a terminating pod from Service Endpoints **asynchronously**. The API server marks it `Terminating`; only then do kube-proxy's iptables/IPVS rules and the ingress controller's upstream list converge. Meanwhile the pod has *already* received SIGTERM. Without `preStop`, Node's `server.close()` starts refusing new connections immediately, so requests arriving in that convergence window get `ECONNREFUSED` — surfaced as a 502 by the proxy.

`preStop: sleep 10` costs nothing (the pod is being replaced anyway) and moves the SIGTERM to *after* convergence. `maxUnavailable: 0` means capacity never dips, so the remaining pods are not simultaneously overloaded — which is the second, subtler cause of errors during a rollout.

⭐ **If your team has learned to tolerate "a few 502s during deploys", this is why — and it is fixable in one line.**

</details>

### Task 15.5 — Verify the backup by restoring it, and compare counts

<details>
<summary>Show answer</summary>

§15.8's CronJob does this every night; run it deliberately with `kubectl create job --from=cronjob/mern-mongo-backup manual-$(date +%s)` and read the log.

**The four parts, and why each is load-bearing:**
1. ⭐ **`--oplog`** — makes the dump a consistent **point-in-time** snapshot of a *live* database. Without it, a write landing mid-dump produces a **torn** backup that restores to a state that never existed. It also requires a replica set, which is one more reason §15.3.4 is not optional.
2. ⭐⭐ **Restore it** — `mongodump` exits 0 on an archive nobody can read. Restoring into a throwaway `mongod --replSet verify` on port 27099 with `--nsFrom='shop.*' --nsTo='verify.*'` is the only proof.
3. ⭐ **Compare `countDocuments()`** per collection — catches the empty-archive, wrong-namespace and partial-restore cases that a successful `mongorestore` exit code does not. The size check (`> 10000` bytes) is a cheap first gate.
4. **`failedJobsHistoryLimit: 7`** — the most common real version of this incident is not "we had no backup", it is "the job had been failing for six weeks and nobody noticed, because history was 1 and the alert went to an inbox".

**Then state the limitation honestly:** the restore proves the archive is *readable and complete*, not that the data is *correct*. And `mongorestore` into production discards every write since the dump — which is why it is a human decision, not a pipeline step.

</details>

### Task 15.6 — Upgrade MongoDB 8.0 → 8.2 secondaries-first using `partition`

<details>
<summary>Show answer</summary>

§15.9. The mechanism worth understanding is `spec.updateStrategy.rollingUpdate.partition`: **only pods with an ordinal ≥ partition are updated.**

```bash
# 1. verify the backup exists and was VERIFIED (§15.8)
kubectl -n $NS get jobs -l component=backup --sort-by=.status.startTime | tail -3
kubectl -n $NS logs job/<latest> | grep -q 'VERIFIED' || { echo "⛔ no verified backup"; exit 1; }

# 2. confirm the current feature-compatibility version
kubectl -n $NS exec mern-mongo-0 -- mongosh --quiet -u shop -p "$PASS" \
  --authenticationDatabase admin --eval \
  'db.adminCommand({getParameter:1, featureCompatibilityVersion:1})'

# 3. ⭐ freeze pod 0 (the likely primary) and update only 1 and 2
kubectl -n $NS patch sts mern-mongo --type=merge \
  -p '{"spec":{"updateStrategy":{"rollingUpdate":{"partition":1}}}}'
kubectl -n $NS set image sts/mern-mongo mongod=mongo@sha256:<8.2-digest>

# 4. ⭐ between EACH pod, prove replication caught up
for p in mern-mongo-2 mern-mongo-1; do
  kubectl -n $NS wait --for=jsonpath='{.status.phase}'=Running pod/$p --timeout=300s
  kubectl -n $NS exec mern-mongo-0 -- mongosh --quiet -u shop -p "$PASS" \
    --authenticationDatabase admin --eval 'rs.printSecondaryReplicationInfo()'
  # ✅ lag 0 for every secondary before continuing
done

# 5. move the primary onto an upgraded node
kubectl -n $NS exec mern-mongo-0 -- mongosh --quiet -u shop -p "$PASS" \
  --authenticationDatabase admin --eval 'rs.stepDown(60)'

# 6. now update pod 0
kubectl -n $NS patch sts mern-mongo --type=merge \
  -p '{"spec":{"updateStrategy":{"rollingUpdate":{"partition":0}}}}'
kubectl -n $NS rollout status sts/mern-mongo --timeout=600s

# 7. ⭐ ONLY NOW raise the fCV — this is the one-way door
kubectl -n $NS exec mern-mongo-0 -- mongosh --quiet -u shop -p "$PASS" \
  --authenticationDatabase admin --eval \
  'db.adminCommand({setFeatureCompatibilityVersion:"8.2"})'
```

**Why the order:** an 8.2 secondary replicating from an 8.0 primary is supported; the reverse is not guaranteed. Keeping the old version as PRIMARY until every secondary is upgraded means the replica set is always in a supported configuration, and there is always a rollback path. **Why the fCV goes last:** raising it can make the data files unreadable by the previous version, so it is the point of no return — which is precisely why the verified backup comes first and the fCV change comes last.

⭐ **And the pipeline consequence:** the MongoDB image must not live in the same manifest as the app images, or an ordinary app deploy can start this sequence by accident.

</details>

### Task 15.7 — Make `mern-web` environment-agnostic and prove it

<details>
<summary>Show answer</summary>

The mechanism is in Docker Project 14 §14.5: nginx's `/docker-entrypoint.d/40-inject-config.sh` writes `/usr/share/nginx/html/config.js` from the **real environment** on every container start; `index.html` loads it before the bundle; `apps/web/src/config.ts` is the only reader and **throws** if it is missing.

```bash
# ⭐ the SAME digest, two environments
kubectl -n shop-staging   set image deploy/mern-web mern-web="$WEB"
kubectl -n shop-production set image deploy/mern-web mern-web="$WEB"
kubectl -n shop-staging    set env deploy/mern-web MERN_API_URL=http://mern-api.shop-staging.svc:4000    MERN_ENV=staging
kubectl -n shop-production set env deploy/mern-web MERN_API_URL=http://mern-api.shop-production.svc:4000 MERN_ENV=production

curl -s https://staging.shop.example.com/config.js      # ✅ staging URL
curl -s https://shop.example.com/config.js              # ✅ production URL

# ⭐⭐ prove the IMAGE is identical
kubectl -n shop-staging    get deploy mern-web -o jsonpath="{.spec.template.spec.containers[?(@.name=='mern-web')].image}"
kubectl -n shop-production get deploy mern-web -o jsonpath="{.spec.template.spec.containers[?(@.name=='mern-web')].image}"
# ✅ identical digest

# ⛔ prove nothing was baked in at build time
kubectl -n shop-production exec deploy/mern-web -- sh -c \
  'grep -rl "staging" /usr/share/nginx/html/assets/ | wc -l'
# ✅ 0

# ⭐ cache headers
curl -sI https://shop.example.com/index.html | grep -i cache-control   # ✅ no-cache
curl -sI https://shop.example.com/config.js  | grep -i cache-control   # ✅ no-store
curl -sI https://shop.example.com/assets/<hashed>.js | grep -i cache-control  # ✅ immutable
```

**Why this matters beyond tidiness:** if `VITE_API_URL` is baked in at build time, you must build **per environment**, and then the artifact you tested in staging is *not* the artifact you ship to production — which breaks the digest contract that the whole CI/CD path exists to enforce. Runtime injection is what makes "promote the same digest" possible at all.

</details>

### Task 15.8 — ⭐⭐ The mixed-data incident

During a rollout of `mern-api` v1→v2, some orders have `quantity` and some have `qty`, and the UI shows `undefined` for about forty seconds. Diagnose, fix immediately, fix permanently.

<details>
<summary>Show answer</summary>

**Diagnose — the one command that settles it:**

```bash
kubectl -n $NS exec mern-mongo-0 -- mongosh --quiet -u shop -p "$PASS" \
  --authenticationDatabase admin shop --eval '({
     withQty:      db.orders.countDocuments({qty:      {$exists:true}}),
     withQuantity: db.orders.countDocuments({quantity: {$exists:true}}),
     both:         db.orders.countDocuments({qty:{$exists:true},quantity:{$exists:true}}),
     neither:      db.orders.countDocuments({qty:{$exists:false},quantity:{$exists:false}})
   })'
```

**Every mechanism involved, in order:**

1. A rolling update runs **two versions of `mern-api` simultaneously** — old pods draining, new pods starting, both connected to the same MongoDB, both writing to `orders`.
2. ⭐⭐ **MongoDB accepts both shapes, because the schema lives in Mongoose — in the application — not in the database.** There is no column, no constraint, no rejection. A document is whatever the writer said it was.
3. Meanwhile the browser holds **yesterday's bundle** (or, for ~40 s, the new bundle served by pods that are still old), which reads `order.quantity`. On documents written by the old pod that property is absent → `undefined`.
4. The forty-second duration is the rollout window (`maxUnavailable: 0, maxSurge: 1` across 3 replicas plus readiness delays). The **hours-long** tail would be the browser cache — which is why `index.html` must be `no-cache`.

**Immediate fix (minutes):** make the *reader* tolerant in **one place** — `const quantity = order.quantity ?? order.qty ?? 0` inside `packages/shared`, so both tiers get it from a single edit — and redeploy. Then **backfill** the documents written during the window with a batched, idempotent migration, and verify `withQty` reaches 0.

⛔ **Do not just `rollout undo`.** That stops new `quantity` documents but leaves the mixed data in place, and now the *old* code reads data the *new* code wrote. A rollback is not a data rollback (§15.8).

**Permanent fix — expand/contract, three releases:**
- **Release 1 (api):** accept **both** `qty` and `quantity` on input; emit **both**. Declared once in the shared zod schema. Revertible: nothing consumes the new field yet.
- **Release 2 (web):** read and send `quantity`. The api still emits `qty`, so a cached old bundle works. Revertible: redeploy the previous web digest.
- **Release 3 (api), later:** stop emitting `qty` — **only after telemetry shows zero `qty` traffic** — then a migration `$unset`s it.

**The three gates that would have caught it:**
- ⭐ **`CONTRACT_VERSION`** with a startup `serves` check → a mismatched pair shows a **refresh banner**, not `undefined`.
- ⭐ **`OrderOutput.parse(await r.json())`** on the client → an unexpected shape becomes a **caught, logged** error instead of a silent `undefined`.
- ⭐⭐ **An integration test that writes a document in the OLD shape and asserts the NEW code reads it.** This is the MERN-specific test that exists precisely because the database will not do it for you.

**The meta-lesson:** in a Postgres stack this incident is a `NOT NULL` violation that **fails the deploy**. In MERN it is silent mixed data plus `undefined` in the UI. *The same design decision that makes MERN fast to build makes it unforgiving to deploy* — and the compensation is discipline in the shared package, the migration ledger and the contract version, not a constraint you can add later.

</details>

### Task 15.9 — Delete the StatefulSet without deleting the data

<details>
<summary>Show answer</summary>

```bash
# ⛔ THE WRONG WAY — takes the PVCs with it in most setups
kubectl -n $NS delete statefulset mern-mongo
# and definitely not:
kubectl -n $NS delete statefulset mern-mongo --cascade=foreground  # + then the PVCs

# ⭐ THE RIGHT WAY
kubectl -n $NS delete statefulset mern-mongo --cascade=orphan
# → deletes the StatefulSet object, leaves the PODS running
kubectl -n $NS delete pods -l app=mern-mongo
# → pods go away; PVCs (data-mern-mongo-0/1/2, configdb-…) REMAIN
kubectl -n $NS get pvc -l app=mern-mongo    # ⭐ verify before you re-apply
kubectl -n $NS apply -f mongo-statefulset.yaml
# → new pods reattach the SAME PVCs, mongod recovers from the existing data
#   files, and the replica set rejoins
```

**Why this matters:** `volumeClaimTemplates` are *not* obviously separate objects — they look like part of the StatefulSpec, and the natural instinct (`delete sts` then `apply`) destroys the data on clusters where PVC deletion propagates. ⭐ **The check that makes it safe:** `kubectl get pvc` **before** and **after**, and a verified backup (§15.8) before you touch anything.

**Two related facts:**
- `persistentVolumeReclaimPolicy: Delete` (the default on many managed clusters) means deleting the **PVC** deletes the **volume**. On a database PVC, `Retain` is usually correct.
- `helm uninstall` deletes the release's resources, and whether PVCs go depends on the chart's annotations — ⭐ check before you run it, not after.

</details>

### Task 15.10 — Wire it into CI/CD

<details>
<summary>Show answer</summary>

This project becomes **shape E** in the CI/CD path: [`../cicd-learning-path/08-SCENARIO-DEPLOYMENTS/01-MERN-STACK-PROJECT.md`](../cicd-learning-path/08-SCENARIO-DEPLOYMENTS/01-MERN-STACK-PROJECT.md).

**What carries over unchanged:**
- ⭐ the artifact is a **digest**, never a tag — the chart in Project 14 of this path has no `image.tag` field at all, and `required` fails the render
- CI cannot deploy; CD cannot build
- the four-check contract: digest-shape → cosign provenance → *staging ran this digest* → **read back with the JSONPath name filter**

**What MERN adds:**
- ⭐ a **real mongod replica set in CI** — a sidecar with `--replSet rs0` + `rs.initiate()` on a Kubernetes agent (no Docker daemon), or `@testcontainers/mongodb` on a hosted runner
- ⭐ a **migration dry-run** against a throwaway database, plus a shadow check against production-shaped data
- ⭐⭐ the **backup gate inside the CD pipeline**, before the migration Job
- ⭐ **Playwright against the built images**, not `npm run dev`

**The Case verdicts:** `mern-web` → 🤖 Case 2 (static files, instant rollback, but needs RUM). `mern-api` → 🔒 Case 1 (the migration ledger). `mern-mongo` → 🔒🔒 Case 1, **always, and in its own manifest** so an app deploy can never move the database.

Full pipelines for all three tools: [`../cicd-learning-path/09-TOOL-MASTERY/`](../cicd-learning-path/09-TOOL-MASTERY/).

</details>

---

## 15.12 Checklist

- [ ] Deploy MongoDB as a **StatefulSet** with a **headless** Service and explain why a Deployment cannot work
- [ ] `volumeClaimTemplates` for `/data/db` **and** `/data/configdb`, a PVC per pod
- [ ] `fsGroup: 999` so `/data/db` is writable
- [ ] `--replSet rs0 --bind_ip_all` and an explicit `--wiredTigerCacheSizeGB`
- [ ] `podAntiAffinity` so the three members are on three nodes
- [ ] An **idempotent** `rs.initiate()` Job that waits for a PRIMARY
- [ ] A connection string listing **all** members with `replicaSet`, `retryWrites`, ⭐ `w=majority`
- [ ] Prove a Mongoose transaction actually runs
- [ ] `mern-api`: `startupProbe` `/healthz` · `readinessProbe` `/readyz` · `livenessProbe` `/healthz`
- [ ] Explain why liveness must never query the database
- [ ] `preStop: sleep 10` + `maxUnavailable: 0` and prove the 502s disappear
- [ ] `NODE_OPTIONS=--max-old-space-size` at ~75% of the memory limit
- [ ] `readOnlyRootFilesystem`, non-root, `capabilities: drop ALL`
- [ ] A `checksum/config` annotation so ConfigMap changes trigger a rollout
- [ ] `mern-web`: runtime `config.js`; prove ONE digest serves every environment
- [ ] Cache headers: `no-cache` index.html · `immutable` assets · `no-store` config.js
- [ ] Ingress with `/api` before `/`, and one origin so there is no CORS
- [ ] `autoIndex: false`, `autoCreate: false`, never `syncIndexes()`
- [ ] Indexes created in a migration with an `explain()` assertion
- [ ] A `schema_migrations` ledger with `useFileHash: true`
- [ ] The migration as a **Job**, `backoffLimit: 0`, the **same digest** as the app
- [ ] ⭐ The migration **gates** the rollout; prove a bad migration stops it
- [ ] The backup CronJob: `--oplog`, restore-verify, count-compare, `failedJobsHistoryLimit: 7`
- [ ] Run the backup manually and read "VERIFIED" in the log
- [ ] Explain why `rollout undo` is not a data rollback
- [ ] Upgrade MongoDB secondaries-first using `partition`, fCV last
- [ ] Delete the StatefulSet with `--cascade=orphan` and keep the PVCs
- [ ] Check for mixed-shape documents after every rollout
- [ ] Explain the six things that can go wrong in MERN that cannot go wrong in Project 12

---

**Next → [`19-KUBECTL-COMPLETE-REFERENCE.md`](19-KUBECTL-COMPLETE-REFERENCE.md)** — every `kubectl` command, on one page.

⭐ **Then, in CI/CD → [`../cicd-learning-path/08-SCENARIO-DEPLOYMENTS/01-MERN-STACK-PROJECT.md`](../cicd-learning-path/08-SCENARIO-DEPLOYMENTS/01-MERN-STACK-PROJECT.md)** — this stack as **shape E** through all three scenarios in all three tools, and [`../cicd-learning-path/09-TOOL-MASTERY/`](../cicd-learning-path/09-TOOL-MASTERY/) for one tool at a time, end to end.

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish%20Kumar%20Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn → <https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260>
🐙 GitHub → <https://github.com/3558Bhk>

*Built for engineers who learn by breaking things on purpose.*

</div>
