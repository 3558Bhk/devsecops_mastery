# 🔗 Project 10 — React + Java (Spring Boot) Full Stack on Kubernetes

> **Time:** 2 hours · **Prereq:** [Project 8](11-PROJECT-8-react-frontend.md) and [Project 9](12-PROJECT-9-java-backend.md)
>
> - 🔵 **CASE 1 — Simple.** Three Deployments (UI, API, Postgres), three Services, one Ingress. Running in 25 minutes.
> - 🟢 **CASE 2 — Production.** Namespaces, NetworkPolicies that actually enforce the tiering, one-origin routing (no CORS), migrations as a Job, HPA, PDBs, probes, ServiceMonitors, a `Makefile`, and a smoke test that proves the whole stack works.
>
> **What's new here vs. Projects 8 and 9:** *composition* — how the pieces find each other, who may talk to whom, and what order things must start in.

---

## 10.0 The architecture

```
                        ┌──────────────────────────┐
   Internet ──► LB ──►  │  Ingress Controller      │
                        │  shop.example.com        │
                        └───────┬──────────┬───────┘
                                │ /        │ /api/*
                     ┌──────────▼───┐  ┌───▼──────────┐
                     │ shop-ui (3)  │  │ shop-api (3) │
                     │ nginx+static │  │ Spring Boot  │
                     │  :8080       │  │  :8080       │
                     └──────────────┘  └───┬──────────┘
                                           │ 5432
                                     ┌─────▼──────┐
                                     │ db (STS 3) │
                                     │ Postgres   │
                                     └────────────┘
```

Traffic rules we will enforce with NetworkPolicy:

| From | To | Allowed? |
|---|---|---|
| ingress-nginx | shop-ui:8080 | ✅ |
| ingress-nginx | shop-api:8080 | ✅ |
| shop-ui | shop-api | ❌ (static files; the *browser* calls the API via the Ingress) |
| shop-api | db:5432 | ✅ |
| shop-ui | db | ❌ |
| monitoring | shop-api:8080 | ✅ |
| anything | anything else | ❌ |

That last row is the point. **Default-deny, then allow.**

---

# 🔵 CASE 1 — Simple (25 minutes)

## 10.1 The layout

```bash
mkdir -p ~/k8s-learn/p10/{ui,api,k8s} && cd ~/k8s-learn/p10
```

Build both images (reuse Projects 8 & 9, simplified):

```bash
# UI — the Case 2 nginx build from Project 8
docker build -t shop-ui:simple ../p8/
# API — the Case 1 jar build from Project 9
docker build -t shop-api:simple ../p9/shop-api/

kind load docker-image shop-ui:simple  --name learn
kind load docker-image shop-api:simple --name learn
```

## 10.2 One file, the whole stack

`k8s/simple.yaml`:

```yaml
# ═══════════════════ DATABASE ═══════════════════
apiVersion: v1
kind: Secret
metadata: {name: pg-creds}
stringData:
  POSTGRES_USER: shop
  POSTGRES_PASSWORD: "L3arn-K8s!"
  POSTGRES_DB: app
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: pg-data}
spec:
  accessModes: [ReadWriteOnce]
  resources: {requests: {storage: 2Gi}}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: db, labels: {app: db}}
spec:
  replicas: 1
  selector: {matchLabels: {app: db}}
  strategy: {type: Recreate}          # ⭐ RWO volume — only one pod may hold it
  template:
    metadata: {labels: {app: db}}
    spec:
      containers:
        - name: postgres
          image: postgres:17-alpine
          ports: [{containerPort: 5432, name: postgres}]
          envFrom: [{secretRef: {name: pg-creds}}]
          env: [{name: PGDATA, value: /var/lib/postgresql/data/pgdata}]
          readinessProbe:
            exec: {command: ["sh","-c","pg_isready -U $POSTGRES_USER -d $POSTGRES_DB -h 127.0.0.1"]}
            initialDelaySeconds: 5
            periodSeconds: 5
            failureThreshold: 20
          livenessProbe:
            exec: {command: ["sh","-c","pg_isready -U $POSTGRES_USER -h 127.0.0.1"]}
            initialDelaySeconds: 30
            periodSeconds: 20
          resources:
            requests: {cpu: 100m, memory: 256Mi}
            limits:   {cpu: "1",   memory: 1Gi}
          volumeMounts: [{name: data, mountPath: /var/lib/postgresql/data}]
      volumes: [{name: data, persistentVolumeClaim: {claimName: pg-data}}]
---
apiVersion: v1
kind: Service
metadata: {name: db}
spec:
  selector: {app: db}
  ports: [{name: postgres, port: 5432}]

# ═══════════════════ API ═══════════════════
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: shop-api, labels: {app: shop-api}}
spec:
  replicas: 2
  selector: {matchLabels: {app: shop-api}}
  template:
    metadata: {labels: {app: shop-api}}
    spec:
      # ⭐ wait for the DB before starting the JVM — makes startup failures obvious
      initContainers:
        - name: wait-for-db
          image: busybox:1.37
          command: ["sh","-c","until nc -z db 5432; do echo 'waiting for db'; sleep 2; done; echo 'db up'"]
      containers:
        - name: api
          image: shop-api:simple
          imagePullPolicy: IfNotPresent
          ports: [{name: http, containerPort: 8080}]
          env:
            - {name: SPRING_DATASOURCE_URL, value: "jdbc:postgresql://db:5432/app"}
            - {name: SPRING_DATASOURCE_USERNAME, valueFrom: {secretKeyRef: {name: pg-creds, key: POSTGRES_USER}}}
            - {name: SPRING_DATASOURCE_PASSWORD, valueFrom: {secretKeyRef: {name: pg-creds, key: POSTGRES_PASSWORD}}}
            - {name: SPRING_JPA_HIBERNATE_DDL_AUTO, value: "update"}
            - {name: JAVA_OPTS, value: "-XX:MaxRAMPercentage=65"}
          startupProbe:
            httpGet: {path: /actuator/health/liveness, port: http}
            periodSeconds: 5
            failureThreshold: 48
          readinessProbe:
            httpGet: {path: /actuator/health/readiness, port: http}
            periodSeconds: 10
            failureThreshold: 3
          livenessProbe:
            httpGet: {path: /actuator/health/liveness, port: http}
            periodSeconds: 20
            failureThreshold: 3
          resources:
            requests: {cpu: 250m, memory: 768Mi}
            limits:   {cpu: "1",   memory: 1Gi}
---
apiVersion: v1
kind: Service
metadata: {name: shop-api}
spec:
  selector: {app: shop-api}
  ports: [{name: http, port: 8080}]

# ═══════════════════ UI ═══════════════════
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: shop-ui, labels: {app: shop-ui}}
spec:
  replicas: 2
  selector: {matchLabels: {app: shop-ui}}
  template:
    metadata: {labels: {app: shop-ui}}
    spec:
      containers:
        - name: web
          image: shop-ui:simple
          imagePullPolicy: IfNotPresent
          ports: [{name: http, containerPort: 8080}]
          readinessProbe: {httpGet: {path: /healthz, port: http}, periodSeconds: 5}
          livenessProbe:  {httpGet: {path: /healthz, port: http}, periodSeconds: 20}
          resources:
            requests: {cpu: 25m, memory: 32Mi}
            limits:   {cpu: 200m, memory: 96Mi}
---
apiVersion: v1
kind: Service
metadata: {name: shop-ui}
spec:
  selector: {app: shop-ui}
  ports: [{name: http, port: 80, targetPort: http}]

# ═══════════════════ INGRESS ═══════════════════
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: shop
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/rewrite-target: /$2
spec:
  ingressClassName: nginx
  rules:
    - host: shop.local
      http:
        paths:
          - path: /api(/|$)(.*)
            pathType: ImplementationSpecific
            backend: {service: {name: shop-api, port: {number: 8080}}}
          - path: /
            pathType: Prefix
            backend: {service: {name: shop-ui, port: {number: 80}}}
```

> ⚠️ **One Ingress, one `rewrite-target`.** Annotations apply to the *whole* Ingress object, so if you put `rewrite-target: /$2` on an Ingress that also has the `/` path, the `/` rule breaks (it has no capture group 2). Either:
> - put both rules under one `path` with a shared regex (as above — `/` and `/api(/|$)(.*)` work because `Prefix /` ignores rewrite when there's no capture), or
> - **split into two Ingress objects on the same host** (the Case 2 approach, and clearer).

```bash
kubectl apply -f k8s/simple.yaml
kubectl rollout status deploy/db
kubectl rollout status deploy/shop-api --timeout=240s
kubectl rollout status deploy/shop-ui
kubectl get all
```

## 10.3 Verify the whole chain

```bash
LB_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# 1. UI
curl -s -H "Host: shop.local" http://$LB_IP/ | head -3

# 2. API directly through the Ingress
curl -s -H "Host: shop.local" http://$LB_IP/api/products | jq .

# 3. Create something
curl -s -XPOST -H "Host: shop.local" http://$LB_IP/api/products \
  -H 'Content-Type: application/json' \
  -d '{"name":"Widget","price":9.99,"description":"A widget"}' | jq .

# 4. Read it back
curl -s -H "Host: shop.local" http://$LB_IP/api/products | jq .

# 5. Prove it hit the DATABASE, not memory
kubectl exec deploy/db -- psql -U shop -d app -c 'SELECT id, name, price FROM products;'
```

```bash
# 6. Prove the rewrite worked — the API saw /products, not /api/products
kubectl logs deploy/shop-api --tail=20 | grep -i 'products'

# 7. Internal DNS works between tiers
kubectl run dns --rm -it --image=nicolaka/netshoot --restart=Never -- bash
  dig +short shop-ui
  dig +short shop-api
  dig +short db
  curl -s http://shop-api:8080/actuator/health/readiness | jq .status
  psql "postgresql://shop:L3arn-K8s!@db:5432/app" -c '\dt'
  exit
```

**If step 2 returns the HTML page instead of JSON**, your Ingress path ordering or rewrite is wrong. Check:

```bash
kubectl describe ingress shop
kubectl -n ingress-nginx exec deploy/ingress-nginx-controller -- nginx -T | grep -A40 'server_name shop.local'
```

## 10.4 What Case 1 gets wrong

| Problem | Consequence |
|---|---|
| Everything in `default` | No isolation, no quotas, hard to delete cleanly |
| No NetworkPolicy | Any Pod can reach the database directly |
| `ddl-auto: update` | Hibernate mutates your schema on every boot |
| Single-replica DB with `strategy: Recreate` | Downtime on every DB deploy |
| No TLS | Everything in clear text |
| No HPA / PDB | Can't absorb load; a node drain takes the app down |
| One Ingress with a rewrite that applies to both paths | Fragile routing |
| No metrics scraped | Invisible |
| `imagePullPolicy: IfNotPresent` + local images | Won't work outside your laptop |

```bash
kubectl delete -f k8s/simple.yaml
```

---

# 🟢 CASE 2 — Production (90 minutes)

## 10.5 The directory layout

```
p10/
├── ui/                          # React app (Project 8)
│   ├── Dockerfile
│   └── nginx/…
├── api/                         # Spring Boot app (Project 9)
│   ├── Dockerfile
│   └── src/main/resources/db/migration/V1__…sql
├── k8s/
│   ├── base/
│   │   ├── kustomization.yaml
│   │   ├── namespace.yaml
│   │   ├── db.yaml
│   │   ├── api.yaml
│   │   ├── ui.yaml
│   │   ├── ingress.yaml
│   │   ├── networkpolicy.yaml
│   │   ├── hpa.yaml
│   │   ├── pdb.yaml
│   │   ├── servicemonitor.yaml
│   │   └── migrate-job.yaml
│   └── overlays/
│       ├── dev/kustomization.yaml
│       └── prod/kustomization.yaml
├── scripts/
│   ├── deploy.sh
│   ├── smoke-test.sh
│   └── rollback.sh
└── Makefile
```

## 10.6 `k8s/base/namespace.yaml`

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: shop
  labels:
    team: shop
    environment: dev
    pod-security.kubernetes.io/enforce: baseline
    pod-security.kubernetes.io/warn: restricted
    pod-security.kubernetes.io/warn-version: latest
```

## 10.7 `k8s/base/db.yaml` — the database as a StatefulSet

```yaml
apiVersion: v1
kind: Secret
metadata: {name: pg-creds, namespace: shop}
stringData:
  username: shop
  password: "L3arn-K8s-pr0d!"
  database: app
  url: "jdbc:postgresql://db.shop.svc.cluster.local:5432/app"
---
# Headless Service → stable per-Pod DNS for the StatefulSet
apiVersion: v1
kind: Service
metadata: {name: db, namespace: shop, labels: {app: db}}
spec:
  clusterIP: None
  selector: {app: db}
  ports: [{name: postgres, port: 5432}]
---
# Regular Service → what the API connects to (load-balances across replicas)
apiVersion: v1
kind: Service
metadata: {name: db-rw, namespace: shop, labels: {app: db}}
spec:
  selector: {app: db, role: primary}     # only the primary accepts writes
  ports: [{name: postgres, port: 5432}]
---
apiVersion: apps/v1
kind: StatefulSet
metadata: {name: db, namespace: shop, labels: {app: db}}
spec:
  serviceName: db
  replicas: 1                        # 3 with real streaming replication — see Project 13
  podManagementPolicy: OrderedReady
  updateStrategy:
    type: RollingUpdate
  selector: {matchLabels: {app: db}}
  template:
    metadata: {labels: {app: db, role: primary}}
    spec:
      securityContext:
        fsGroup: 70                   # postgres group in the official image
        runAsNonRoot: true
        runAsUser: 70
        seccompProfile: {type: RuntimeDefault}
      terminationGracePeriodSeconds: 90
      containers:
        - name: postgres
          image: postgres:17-alpine
          ports: [{name: postgres, containerPort: 5432}]
          env:
            - {name: POSTGRES_USER,     valueFrom: {secretKeyRef: {name: pg-creds, key: username}}}
            - {name: POSTGRES_PASSWORD, valueFrom: {secretKeyRef: {name: pg-creds, key: password}}}
            - {name: POSTGRES_DB,       valueFrom: {secretKeyRef: {name: pg-creds, key: database}}}
            - {name: PGDATA,            value: /var/lib/postgresql/data/pgdata}
          readinessProbe:
            exec: {command: ["sh","-c","pg_isready -U $POSTGRES_USER -d $POSTGRES_DB -h 127.0.0.1"]}
            initialDelaySeconds: 10
            periodSeconds: 10
            failureThreshold: 12
            timeoutSeconds: 5
          livenessProbe:
            exec: {command: ["sh","-c","pg_isready -U $POSTGRES_USER -h 127.0.0.1"]}
            initialDelaySeconds: 60
            periodSeconds: 30
            failureThreshold: 6
          lifecycle:
            preStop:
              exec: {command: ["sh","-c","pg_ctl -D $PGDATA stop -m fast -t 60 || true"]}
          resources:
            requests: {cpu: 500m, memory: 1Gi, ephemeral-storage: 1Gi}
            limits:   {cpu: "2",   memory: 4Gi}
          volumeMounts:
            - {name: data, mountPath: /var/lib/postgresql/data}
  volumeClaimTemplates:
    - metadata: {name: data, labels: {app: db}}
      spec:
        accessModes: [ReadWriteOnce]
        resources: {requests: {storage: 10Gi}}
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata: {name: db, namespace: shop}
spec:
  minAvailable: 1
  selector: {matchLabels: {app: db}}
```

## 10.8 `k8s/base/api.yaml`

```yaml
apiVersion: v1
kind: ServiceAccount
metadata: {name: shop-api, namespace: shop}
automountServiceAccountToken: false
---
apiVersion: v1
kind: ConfigMap
metadata: {name: shop-api-config, namespace: shop}
data:
  SPRING_PROFILES_ACTIVE: "prod"
  SPRING_DATASOURCE_URL: "jdbc:postgresql://db.shop.svc.cluster.local:5432/app"
  SPRING_JPA_HIBERNATE_DDL_AUTO: "validate"
  SPRING_JPA_OPEN_IN_VIEW: "false"
  SPRING_FLYWAY_ENABLED: "true"
  SERVER_SHUTDOWN: "graceful"
  SERVER_TOMCAT_THREADS_MAX: "150"
  DB_POOL_SIZE: "15"
  LOG_LEVEL_APP: "INFO"
  MANAGEMENT_METRICS_TAGS_APPLICATION: "shop-api"
---
apiVersion: v1
kind: ConfigMap
metadata: {name: shop-api-jvm, namespace: shop}
data:
  JAVA_OPTS: >-
    -XX:MaxRAMPercentage=68.0
    -XX:InitialRAMPercentage=50.0
    -XX:+UseG1GC
    -XX:MaxGCPauseMillis=100
    -XX:MaxMetaspaceSize=256m
    -XX:ReservedCodeCacheSize=128m
    -Xss512k
    -XX:+ExitOnOutOfMemoryError
    -XX:+HeapDumpOnOutOfMemoryError
    -XX:HeapDumpPath=/tmp/dumps
    -Djava.io.tmpdir=/tmp
    -Djava.security.egd=file:/dev/./urandom
    -Duser.timezone=UTC
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: shop-api
  namespace: shop
  labels:
    app: shop-api
    app.kubernetes.io/name: shop-api
    app.kubernetes.io/component: backend
    app.kubernetes.io/part-of: shop
spec:
  replicas: 3
  revisionHistoryLimit: 8
  strategy:
    type: RollingUpdate
    rollingUpdate: {maxSurge: 1, maxUnavailable: 0}
  selector: {matchLabels: {app: shop-api}}
  template:
    metadata:
      labels: {app: shop-api, version: v1}
      annotations:
        checksum/config: REPLACE_WITH_SHA
    spec:
      serviceAccountName: shop-api
      terminationGracePeriodSeconds: 60
      securityContext:
        runAsNonRoot: true
        runAsUser: 10001
        runAsGroup: 10001
        fsGroup: 10001
        seccompProfile: {type: RuntimeDefault}
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: ScheduleAnyway
          labelSelector: {matchLabels: {app: shop-api}}
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: DoNotSchedule
          minDomains: 3
          labelSelector: {matchLabels: {app: shop-api}}
      initContainers:
        - name: wait-for-db
          image: busybox:1.37
          command:
            - sh
            - -c
            - |
              i=0
              until nc -z db.shop.svc.cluster.local 5432; do
                i=$((i+1)); [ $i -gt 60 ] && { echo "db never came up"; exit 1; }
                echo "waiting for db ($i)"; sleep 2
              done
              echo "db is reachable"
          resources: {requests: {cpu: 10m, memory: 8Mi}, limits: {cpu: 100m, memory: 32Mi}}
          securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: ["ALL"]}}
      containers:
        - name: api
          image: ghcr.io/3558bhk/shop-api:1.0.0
          imagePullPolicy: IfNotPresent
          ports: [{name: http, containerPort: 8080}]
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities: {drop: ["ALL"]}
          envFrom: [{configMapRef: {name: shop-api-config}}]
          env:
            - {name: JAVA_OPTS, valueFrom: {configMapKeyRef: {name: shop-api-jvm, key: JAVA_OPTS}}}
            - {name: SPRING_DATASOURCE_USERNAME, valueFrom: {secretKeyRef: {name: pg-creds, key: username}}}
            - {name: SPRING_DATASOURCE_PASSWORD, valueFrom: {secretKeyRef: {name: pg-creds, key: password}}}
            - {name: POD_NAME,      valueFrom: {fieldRef: {fieldPath: metadata.name}}}
            - {name: POD_NAMESPACE, valueFrom: {fieldRef: {fieldPath: metadata.namespace}}}
            - {name: POD_IP,        valueFrom: {fieldRef: {fieldPath: status.podIP}}}
            - {name: NODE_NAME,     valueFrom: {fieldRef: {fieldPath: spec.nodeName}}}
            - {name: APP_VERSION,   value: "1.0.0"}
          resources:
            requests: {cpu: 500m, memory: 1Gi, ephemeral-storage: 512Mi}
            limits:   {cpu: "2",  memory: 1536Mi, ephemeral-storage: 2Gi}
          startupProbe:
            httpGet: {path: /actuator/health/liveness, port: http}
            periodSeconds: 5
            failureThreshold: 48
            timeoutSeconds: 3
          readinessProbe:
            httpGet: {path: /actuator/health/readiness, port: http}
            periodSeconds: 10
            failureThreshold: 3
            timeoutSeconds: 3
          livenessProbe:
            httpGet: {path: /actuator/health/liveness, port: http}
            periodSeconds: 20
            failureThreshold: 3
            timeoutSeconds: 5
          lifecycle:
            preStop: {exec: {command: ["/bin/sh","-c","sleep 10"]}}
          volumeMounts:
            - {name: tmp,   mountPath: /tmp}
            - {name: dumps, mountPath: /tmp/dumps}
      volumes:
        - {name: tmp,   emptyDir: {sizeLimit: 512Mi}}
        - {name: dumps, emptyDir: {sizeLimit: 1Gi}}
---
apiVersion: v1
kind: Service
metadata: {name: shop-api, namespace: shop, labels: {app: shop-api}}
spec:
  selector: {app: shop-api}
  ports: [{name: http, port: 8080, targetPort: http}]
```

## 10.9 `k8s/base/ui.yaml`

Identical to [Project 8 §8.6](11-PROJECT-8-react-frontend.md#86-the-production-manifests) with `namespace: shop`. The only meaningful change is the runtime config:

```yaml
apiVersion: v1
kind: ConfigMap
metadata: {name: shop-ui-runtime, namespace: shop}
data:
  env.js: |
    window.__APP_CONFIG__ = {
      apiUrl: "/api",                       // ⭐ relative → same origin → no CORS
      version: "__VERSION__",
      features: { newCheckout: false }
    };
```

## 10.10 `k8s/base/networkpolicy.yaml` — the security story

```yaml
# ══ 1. DEFAULT DENY: nothing in this namespace talks to anything ══
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: default-deny-all, namespace: shop}
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]

# ══ 2. DNS for everyone (without this, nothing resolves) ══
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: allow-dns, namespace: shop}
spec:
  podSelector: {}
  policyTypes: [Egress]
  egress:
    - to:
        - namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: kube-system}}
          podSelector: {matchLabels: {k8s-app: kube-dns}}
      ports:
        - {protocol: UDP, port: 53}
        - {protocol: TCP, port: 53}

# ══ 3. UI: ingress from the Ingress controller only ══
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: shop-ui, namespace: shop}
spec:
  podSelector: {matchLabels: {app: shop-ui}}
  policyTypes: [Ingress]
  ingress:
    - from:
        - namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: ingress-nginx}}
          podSelector: {matchLabels: {app.kubernetes.io/name: ingress-nginx}}
      ports: [{protocol: TCP, port: 8080}]

# ══ 4. API: ingress from the Ingress controller + Prometheus ══
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: shop-api, namespace: shop}
spec:
  podSelector: {matchLabels: {app: shop-api}}
  policyTypes: [Ingress]
  ingress:
    - from:
        - namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: ingress-nginx}}
          podSelector: {matchLabels: {app.kubernetes.io/name: ingress-nginx}}
      ports: [{protocol: TCP, port: 8080}]
    - from:
        - namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: monitoring}}
      ports: [{protocol: TCP, port: 8080}]

# ══ 5. API egress: database + tracing collector ══
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: shop-api-egress, namespace: shop}
spec:
  podSelector: {matchLabels: {app: shop-api}}
  policyTypes: [Egress]
  egress:
    - to: [{podSelector: {matchLabels: {app: db}}}]
      ports: [{protocol: TCP, port: 5432}]
    - to:
        - namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: tracing}}
      ports: [{protocol: TCP, port: 4317}, {protocol: TCP, port: 4318}]
    # outbound HTTPS for third-party APIs (payment gateway, etc.)
    - to: [{ipBlock: {cidr: 0.0.0.0/0, except: ["10.0.0.0/8","172.16.0.0/12","192.168.0.0/16"]}}]
      ports: [{protocol: TCP, port: 443}]

# ══ 6. DB: ingress from the API only ══
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: db, namespace: shop}
spec:
  podSelector: {matchLabels: {app: db}}
  policyTypes: [Ingress]
  ingress:
    - from: [{podSelector: {matchLabels: {app: shop-api}}}]
      ports: [{protocol: TCP, port: 5432}]
    # migration Jobs carry this label too
    - from: [{podSelector: {matchLabels: {task: migrate}}}]
      ports: [{protocol: TCP, port: 5432}]
    # backups
    - from: [{podSelector: {matchLabels: {task: backup}}}]
      ports: [{protocol: TCP, port: 5432}]
```

> ⚠️ **NetworkPolicy requires an enforcing CNI.** Calico, Cilium and Antrea enforce it. **Flannel alone does not** — your policies will be accepted by the API server and silently ignored. Verify:
> ```bash
> kubectl get pods -n kube-system -o wide | grep -iE 'calico|cilium|antrea|flannel'
> # kind installs kindnet, which also does NOT enforce NetworkPolicy.
> # To practice for real:  kind create cluster --config kind-calico.yaml
> #   (https://kind.sigs.k8s.io/docs/user/network-policies/)
> # or install Cilium:  helm install cilium cilium/cilium -n kube-system
> ```

**Verify enforcement:**

```bash
# ✅ allowed: API → DB
kubectl exec -n shop deploy/shop-api -- sh -c 'nc -zv db 5432' 2>&1 | tail -1

# ⛔ denied: UI → DB
kubectl exec -n shop deploy/shop-ui -- sh -c 'nc -zv -w 3 db 5432' 2>&1 | tail -1
# nc: db (10.244.x.x:5432): Operation timed out

# ⛔ denied: a random pod in the namespace → API
kubectl run hacker -n shop --rm -it --image=nicolaka/netshoot --restart=Never -- \
  curl -s -m 3 http://shop-api:8080/actuator/health || echo "BLOCKED ✅"

# ⛔ denied: a pod in ANOTHER namespace → DB
kubectl run hacker2 -n default --rm -it --image=nicolaka/netshoot --restart=Never -- \
  curl -s -m 3 http://db.shop.svc.cluster.local:5432 || echo "BLOCKED ✅"

# ✅ allowed: ingress-nginx → API
kubectl -n ingress-nginx exec deploy/ingress-nginx-controller -- \
  curl -s -m 3 http://shop-api.shop.svc.cluster.local:8080/actuator/health/liveness
```

## 10.11 `k8s/base/ingress.yaml` — two Ingresses, same host

```yaml
# ── UI: everything not matched below ──
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: shop-ui
  namespace: shop
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/proxy-body-size: "5m"
    nginx.ingress.kubernetes.io/configuration-snippet: |
      more_set_headers "Strict-Transport-Security: max-age=31536000; includeSubDomains";
      more_set_headers "X-Content-Type-Options: nosniff";
      more_set_headers "X-Frame-Options: SAMEORIGIN";
spec:
  ingressClassName: nginx
  tls: [{hosts: [shop.example.com], secretName: shop-tls}]
  rules:
    - host: shop.example.com
      http:
        paths:
          - {path: /, pathType: Prefix, backend: {service: {name: shop-ui, port: {number: 80}}}}
---
# ── API: /api/* → strip the prefix ──
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: shop-api
  namespace: shop
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/rewrite-target: /$2
    nginx.ingress.kubernetes.io/proxy-read-timeout: "60"
    nginx.ingress.kubernetes.io/proxy-body-size: "10m"
    nginx.ingress.kubernetes.io/limit-rps: "100"
    nginx.ingress.kubernetes.io/limit-connections: "50"
spec:
  ingressClassName: nginx
  tls: [{hosts: [shop.example.com], secretName: shop-tls}]
  rules:
    - host: shop.example.com
      http:
        paths:
          - path: /api(/|$)(.*)
            pathType: ImplementationSpecific
            backend: {service: {name: shop-api, port: {number: 8080}}}
```

> 🔑 **Why two Ingress objects?** Because annotations are per-Ingress, not per-path. `rewrite-target: /$2` would corrupt the UI's `/` rule if they shared one object.

## 10.12 `k8s/base/migrate-job.yaml`

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: shop-api-migrate
  namespace: shop
  labels: {app: shop-api, task: migrate}
  annotations:
    "helm.sh/hook": pre-install,pre-upgrade
    "helm.sh/hook-weight": "-5"
    "helm.sh/hook-delete-policy": before-hook-creation
spec:
  backoffLimit: 0                       # ⭐ never auto-retry a half-applied migration
  activeDeadlineSeconds: 900
  ttlSecondsAfterFinished: 604800
  template:
    metadata: {labels: {app: shop-api, task: migrate}}
    spec:
      restartPolicy: Never
      serviceAccountName: shop-api
      securityContext:
        runAsNonRoot: true
        runAsUser: 10001
        seccompProfile: {type: RuntimeDefault}
      initContainers:
        - name: wait-for-db
          image: busybox:1.37
          command: ["sh","-c","until nc -z db.shop.svc.cluster.local 5432; do sleep 2; done"]
      containers:
        - name: migrate
          image: ghcr.io/3558bhk/shop-api:1.0.0
          command: ["sh","-c","exec java $JAVA_OPTS -Dspring.main.web-application-type=none org.springframework.boot.loader.launch.JarLauncher"]
          envFrom: [{configMapRef: {name: shop-api-config}}]
          env:
            - {name: JAVA_OPTS, value: "-XX:MaxRAMPercentage=60 -Dspring.flyway.enabled=true"}
            - {name: SPRING_PROFILES_ACTIVE, value: "prod,migrate"}
            - {name: SPRING_DATASOURCE_USERNAME, valueFrom: {secretKeyRef: {name: pg-creds, key: username}}}
            - {name: SPRING_DATASOURCE_PASSWORD, valueFrom: {secretKeyRef: {name: pg-creds, key: password}}}
          resources:
            requests: {cpu: 250m, memory: 512Mi}
            limits:   {cpu: "1",   memory: 1Gi}
          volumeMounts: [{name: tmp, mountPath: /tmp}]
          securityContext: {allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: {drop: ["ALL"]}}
      volumes: [{name: tmp, emptyDir: {sizeLimit: 256Mi}}]
```

## 10.13 `k8s/base/hpa.yaml` + `pdb.yaml` + `servicemonitor.yaml`

```yaml
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
    scaleUp:   {stabilizationWindowSeconds: 0,   policies: [{type: Percent, value: 100, periodSeconds: 30}], selectPolicy: Max}
    scaleDown: {stabilizationWindowSeconds: 600, policies: [{type: Percent, value: 25,  periodSeconds: 60}], selectPolicy: Min}
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata: {name: shop-ui, namespace: shop}
spec:
  scaleTargetRef: {apiVersion: apps/v1, kind: Deployment, name: shop-ui}
  minReplicas: 3
  maxReplicas: 20
  metrics:
    - type: Resource
      resource: {name: cpu, target: {type: Utilization, averageUtilization: 80}}
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata: {name: shop-api, namespace: shop}
spec:
  maxUnavailable: 1
  selector: {matchLabels: {app: shop-api}}
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata: {name: shop-ui, namespace: shop}
spec:
  minAvailable: 2
  selector: {matchLabels: {app: shop-ui}}
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata: {name: shop-api, namespace: monitoring, labels: {release: kps}}
spec:
  namespaceSelector: {matchNames: [shop]}
  selector: {matchLabels: {app: shop-api}}
  endpoints: [{port: http, path: /actuator/prometheus, interval: 15s}]
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata: {name: shop-ui, namespace: monitoring, labels: {release: kps}}
spec:
  namespaceSelector: {matchNames: [shop]}
  selector: {matchLabels: {app: shop-ui}}
  endpoints: [{port: http, path: /nginx_status, interval: 30s}]
---
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata: {name: shop-rules, namespace: monitoring, labels: {release: kps}}
spec:
  groups:
    - name: shop.rules
      rules:
        - alert: ShopApiHighErrorRate
          expr: |
            sum(rate(http_server_requests_seconds_count{application="shop-api",status=~"5.."}[5m]))
            /
            sum(rate(http_server_requests_seconds_count{application="shop-api"}[5m])) > 0.05
          for: 5m
          labels: {severity: critical, team: shop}
          annotations:
            summary: "shop-api 5xx rate above 5%"
            runbook_url: "https://wiki.internal/runbooks/shop-api-errors"
        - alert: ShopApiHighLatency
          expr: |
            histogram_quantile(0.99,
              sum by (le) (rate(http_server_requests_seconds_bucket{application="shop-api"}[5m]))) > 1
          for: 10m
          labels: {severity: warning, team: shop}
          annotations: {summary: "shop-api p99 latency above 1s"}
        - alert: ShopDbPoolExhausted
          expr: hikaricp_connections_pending{application="shop-api"} > 0
          for: 2m
          labels: {severity: warning, team: shop}
          annotations:
            summary: "{{ $labels.pod }} has threads waiting for a DB connection"
            description: "Pool size {{ with query \"hikaricp_connections_max\" }}{{ . | first | value }}{{ end }} is saturated."
        - alert: ShopDbReplicationLag
          expr: pg_replication_lag_seconds > 30
          for: 5m
          labels: {severity: critical, team: shop}
          annotations: {summary: "Postgres replication lag {{ $value }}s"}
```

## 10.14 `k8s/base/kustomization.yaml` + overlays

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: shop
commonLabels:
  app.kubernetes.io/part-of: shop
  app.kubernetes.io/managed-by: kustomize
resources:
  - namespace.yaml
  - db.yaml
  - api.yaml
  - ui.yaml
  - ingress.yaml
  - networkpolicy.yaml
  - hpa.yaml
  - pdb.yaml
  - servicemonitor.yaml
images:
  - {name: ghcr.io/3558bhk/shop-api, newTag: "1.0.0"}
  - {name: ghcr.io/3558bhk/shop-ui,  newTag: "1.0.0"}
```

`k8s/overlays/dev/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: shop-dev
nameSuffix: ""
resources: [../../base]
replicas:
  - {name: shop-api, count: 1}
  - {name: shop-ui,  count: 1}
images:
  - {name: ghcr.io/3558bhk/shop-api, newTag: "1.1.0-rc1"}
  - {name: ghcr.io/3558bhk/shop-ui,  newTag: "1.1.0-rc1"}
patches:
  - target: {kind: HorizontalPodAutoscaler}
    patch: |-
      - op: remove
        path: /spec            # no HPA in dev
  - target: {kind: Ingress, name: shop-ui}
    patch: |-
      - op: replace
        path: /spec/rules/0/host
        value: shop-dev.local
  - target: {kind: ConfigMap, name: shop-api-config}
    patch: |-
      - op: replace
        path: /data/LOG_LEVEL_APP
        value: DEBUG
      - op: replace
        path: /data/SPRING_JPA_HIBERNATE_DDL_AUTO
        value: update            # convenience in dev only
```

`k8s/overlays/prod/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: shop-prod
resources: [../../base, backup-cronjob.yaml]
replicas:
  - {name: shop-api, count: 6}
  - {name: shop-ui,  count: 4}
  - {name: db,       count: 3}
images:
  - {name: ghcr.io/3558bhk/shop-api, newTag: "1.0.0"}
  - {name: ghcr.io/3558bhk/shop-ui,  newTag: "1.0.0"}
patches:
  - target: {kind: ConfigMap, name: shop-api-config}
    patch: |-
      - op: replace
        path: /data/SPRING_DATASOURCE_URL
        value: "jdbc:postgresql://db.shop-prod.svc.cluster.local:5432/app"
      - op: replace
        path: /data/DB_POOL_SIZE
        value: "20"
  - target: {kind: Deployment, name: shop-api}
    patch: |-
      - op: replace
        path: /spec/template/spec/containers/0/resources/limits/memory
        value: 2Gi
```

```bash
kubectl kustomize k8s/overlays/prod | less      # ⭐ ALWAYS render and read first
kubectl diff  -k k8s/overlays/prod
kubectl apply -k k8s/overlays/prod
```

## 10.15 `scripts/smoke-test.sh` — the acceptance test

```bash
#!/usr/bin/env bash
# Verifies the whole stack end to end. Exit non-zero on any failure.
set -uo pipefail

NS=${1:-shop}
HOST=${2:-shop.example.com}
FAIL=0
pass() { printf '  ✅ %s\n' "$1"; }
fail() { printf '  ❌ %s\n' "$1"; FAIL=$((FAIL+1)); }
check() { # check <description> <actual> <expected>
  if [ "$2" = "$3" ]; then pass "$1 ($2)"; else fail "$1: expected '$3', got '$2'"; fi
}

LB_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo 127.0.0.1)
CURL="curl -sk --max-time 10 --resolve ${HOST}:443:${LB_IP} --resolve ${HOST}:80:${LB_IP}"

echo "▸ 1. Cluster objects"
for kind in namespace/db-statefulset/api-deployment/ui-deployment; do :; done
kubectl get ns "$NS" >/dev/null 2>&1 && pass "namespace $NS exists" || fail "namespace $NS missing"
check "db replicas ready"       "$(kubectl get sts  db       -n $NS -o jsonpath='{.status.readyReplicas}' 2>/dev/null)" "1"
check "api replicas ready"      "$(kubectl get deploy shop-api -n $NS -o jsonpath='{.status.readyReplicas}')" "3"
check "ui replicas ready"       "$(kubectl get deploy shop-ui  -n $NS -o jsonpath='{.status.readyReplicas}')" "3"
check "api PDB allowed disruptions" "$(kubectl get pdb shop-api -n $NS -o jsonpath='{.status.disruptionsAllowed}')" "1"

echo "▸ 2. No pods unhealthy"
BAD=$(kubectl get pods -n $NS --no-headers | grep -Ev '([0-9]+)/\1\s+(Running|Completed)' | wc -l | tr -d ' ')
check "unhealthy pod count" "$BAD" "0"

echo "▸ 3. HTTP paths"
for p in / /healthz /api/products /api/actuator/health; do
  code=$($CURL -o /dev/null -w '%{http_code}' "https://${HOST}${p}")
  case "$p" in
    /healthz) check "GET $p" "$code" "404" ;;     # only exists on the UI's internal port
    *)        check "GET $p" "$code" "200" ;;
  esac
done

echo "▸ 4. SPA fallback (deep link must return the HTML shell, not 404)"
code=$($CURL -o /dev/null -w '%{http_code}' "https://${HOST}/products/42")
check "GET /products/42" "$code" "200"
$CURL "https://${HOST}/products/42" | grep -q '<div id="root">' \
  && pass "deep link returns index.html" || fail "deep link did not return index.html"

echo "▸ 5. End-to-end write/read"
NEW=$($CURL -XPOST "https://${HOST}/api/products" \
  -H 'Content-Type: application/json' \
  -d "{\"name\":\"smoke-$(date +%s)\",\"price\":1.23,\"description\":\"smoke test\"}")
ID=$(echo "$NEW" | jq -r '.id // empty')
[ -n "$ID" ] && pass "created product id=$ID" || fail "create failed: $NEW"
if [ -n "$ID" ]; then
  $CURL "https://${HOST}/api/products/$ID" | jq -e '.price == 1.23' >/dev/null \
    && pass "read back product $ID" || fail "read-back mismatch"
  kubectl exec -n $NS db-0 -- psql -U shop -d app -tAc "SELECT count(*) FROM products WHERE id=$ID" \
    | grep -q '^1$' && pass "row is in the database" || fail "row not in database"
  $CURL -XDELETE -o /dev/null "https://${HOST}/api/products/$ID" && pass "delete succeeded"
fi

echo "▸ 6. Caching headers"
$CURL -I "https://${HOST}/index.html" | grep -qi 'cache-control:.*no-store' \
  && pass "index.html is not cached" || fail "index.html IS cached — deploy will break clients"
ASSET=$($CURL "https://${HOST}/" | grep -o '/assets/[^"]*\.js' | head -1)
if [ -n "$ASSET" ]; then
  $CURL -I "https://${HOST}${ASSET}" | grep -qi 'max-age=31536000' \
    && pass "hashed asset is immutable-cached" || fail "asset cache header wrong"
fi

echo "▸ 7. TLS"
$CURL -I "https://${HOST}/" | grep -qi '^HTTP/2' && pass "HTTP/2 negotiated" || pass "HTTP/1.1 (ok)"
DAYS=$(echo | openssl s_client -connect "${LB_IP}:443" -servername "$HOST" 2>/dev/null \
  | openssl x509 -noout -enddate | cut -d= -f2 | xargs -I{} sh -c 'echo $(( ( $(date -d "{}" +%s) - $(date +%s) ) / 86400 ))')
[ "${DAYS:-0}" -gt 14 ] && pass "cert valid for ${DAYS} days" || fail "cert expires in ${DAYS:-?} days"

echo "▸ 8. HTTP → HTTPS redirect"
code=$(curl -sk --max-time 10 --resolve "${HOST}:80:${LB_IP}" -o /dev/null -w '%{http_code}' "http://${HOST}/")
case "$code" in 301|308) pass "redirect $code" ;; *) fail "no redirect (got $code)" ;; esac

echo "▸ 9. Security"
kubectl get pod -n $NS -l app=shop-api -o jsonpath='{.items[0].status.qosClass}' | grep -q 'Guaranteed\|Burstable' \
  && pass "api QoS $(kubectl get pod -n $NS -l app=shop-api -o jsonpath='{.items[0].status.qosClass}')" \
  || fail "api has no resource requests"
kubectl get netpol -n $NS --no-headers | grep -q default-deny \
  && pass "default-deny NetworkPolicy present" || fail "no default-deny policy"

echo "▸ 10. Observability"
kubectl get servicemonitor -n monitoring -l release=kps --no-headers | grep -q shop-api \
  && pass "ServiceMonitor exists" || fail "no ServiceMonitor"
PROM=$(kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1" 2>/dev/null | grep -c http_server || echo 0)
[ "$PROM" -gt 0 ] && pass "custom metrics API serving app metrics" || echo "  ⚠️  custom metrics not available (HPA on CPU only)"

echo
if [ "$FAIL" -eq 0 ]; then echo "🎉 ALL SMOKE TESTS PASSED"; else echo "💥 $FAIL CHECK(S) FAILED"; exit 1; fi
```

```bash
chmod +x scripts/smoke-test.sh
./scripts/smoke-test.sh shop shop.local
```

## 10.16 `Makefile`

```makefile
SHELL := /bin/bash
NS        ?= shop
HOST      ?= shop.local
ENV       ?= dev
REGISTRY  ?= ghcr.io/3558bhk
GIT_SHA   := $(shell git rev-parse --short HEAD 2>/dev/null || echo dev)
TAG       ?= $(GIT_SHA)
KIND      ?= learn

.PHONY: help
help: ## show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'

## ── build ────────────────────────────────────────────────
.PHONY: build build-ui build-api push load
build: build-ui build-api ## build both images
build-ui:
	docker build --build-arg VITE_VERSION=$(TAG) -t $(REGISTRY)/shop-ui:$(TAG) ui/
	docker tag $(REGISTRY)/shop-ui:$(TAG) shop-ui:$(TAG)
build-api:
	docker build --build-arg GIT_SHA=$(GIT_SHA) -t $(REGISTRY)/shop-api:$(TAG) api/
	docker tag $(REGISTRY)/shop-api:$(TAG) shop-api:$(TAG)
push:
	docker push $(REGISTRY)/shop-ui:$(TAG)
	docker push $(REGISTRY)/shop-api:$(TAG)
load: ## load images into kind (no registry needed)
	kind load docker-image shop-ui:$(TAG) shop-api:$(TAG) --name $(KIND)

## ── deploy ───────────────────────────────────────────────
.PHONY: plan diff deploy migrate rollout status undo
plan: ## render the manifests without applying
	kubectl kustomize k8s/overlays/$(ENV)
diff: ## show what would change
	kubectl diff -k k8s/overlays/$(ENV) || true
migrate: ## run DB migrations as a Job and wait
	kubectl delete job shop-api-migrate -n $(NS) --ignore-not-found
	kubectl create -f k8s/base/migrate-job.yaml -n $(NS)
	kubectl wait --for=condition=complete job/shop-api-migrate -n $(NS) --timeout=900s
	kubectl logs -n $(NS) job/shop-api-migrate --tail=50
deploy: ## apply everything
	kubectl apply -k k8s/overlays/$(ENV)
	kubectl rollout status deploy/shop-ui  -n $(NS) --timeout=180s
	kubectl rollout status deploy/shop-api -n $(NS) --timeout=300s
	kubectl rollout status sts/db          -n $(NS) --timeout=300s
rollout: ## set images by digest/tag and roll
	kubectl set image deploy/shop-api -n $(NS) api=$(REGISTRY)/shop-api:$(TAG)
	kubectl set image deploy/shop-ui  -n $(NS) web=$(REGISTRY)/shop-ui:$(TAG)
	kubectl annotate deploy/shop-api deploy/shop-ui -n $(NS) kubernetes.io/change-cause="tag $(TAG)" --overwrite
	kubectl rollout status deploy/shop-api -n $(NS) --timeout=300s
	kubectl rollout status deploy/shop-ui  -n $(NS) --timeout=180s
status:
	kubectl get deploy,sts,svc,ingress,hpa,pdb,netpol,pods -n $(NS)
undo: ## roll back both deployments
	kubectl rollout undo deploy/shop-api -n $(NS)
	kubectl rollout undo deploy/shop-ui  -n $(NS)
	kubectl rollout status deploy/shop-api -n $(NS)

## ── verify ───────────────────────────────────────────────
.PHONY: test smoke logs port-forward
smoke: ## run the end-to-end smoke test
	./scripts/smoke-test.sh $(NS) $(HOST)
test: build deploy migrate smoke ## the full loop
logs:
	stern -n $(NS) . --tail 20
port-forward:
	kubectl port-forward -n $(NS) svc/shop-ui 8080:80 & \
	kubectl port-forward -n $(NS) svc/shop-api 8081:8080 & \
	echo "UI  → http://localhost:8080" && echo "API → http://localhost:8081" && wait

## ── teardown ─────────────────────────────────────────────
.PHONY: clean nuke
clean:
	kubectl delete -k k8s/overlays/$(ENV) --ignore-not-found
nuke: ## delete the namespace and all PVCs — DATA IS DESTROYED
	kubectl delete namespace $(NS) --ignore-not-found --wait=false
	kubectl delete pvc -n $(NS) --all --ignore-not-found
```

```bash
make help
make build TAG=1.0.0
make load TAG=1.0.0
make deploy ENV=dev
make migrate
make smoke
make logs
```

---

## 10.17 Extra Tasks

### Task 10.1 — Enforce startup ordering without a mess of init containers

The API needs the DB. The UI needs nothing. Migrations must run before the API. Express all three correctly.

<details>
<summary>Show answer</summary>

**The three ordering problems and three different tools:**

| Problem | Wrong tool | Right tool |
|---|---|---|
| API starts before the DB is reachable | `sleep 60` in the entrypoint | **init container** that probes the port |
| Migrations must run before the API serves traffic | hope the timing works out | **a Job + `kubectl wait`** in the pipeline, or a Helm `pre-upgrade` hook |
| UI should wait for the API | init container on the UI | ❌ **Don't.** A static SPA has no server-side dependency; let it 503 gracefully and retry in JS |

**1. Dependency readiness → init container with a timeout.**

```yaml
initContainers:
  - name: wait-for-db
    image: busybox:1.37
    command:
      - sh
      - -c
      - |
        set -eu
        HOST=db.shop.svc.cluster.local; PORT=5432; TIMEOUT=120
        i=0
        until nc -z "$HOST" "$PORT" 2>/dev/null; do
          i=$((i+1))
          if [ $i -ge $((TIMEOUT/2)) ]; then
            echo "FATAL: $HOST:$PORT not reachable after ${TIMEOUT}s"
            # show WHY, so you're not guessing
            nslookup "$HOST" || echo "  → DNS failure"
            exit 1
          fi
          echo "waiting for $HOST:$PORT ($i)"
          sleep 2
        done
        echo "$HOST:$PORT is reachable"
    resources: {requests: {cpu: 10m, memory: 8Mi}, limits: {cpu: 100m, memory: 32Mi}}
```

⚠️ **Always add a timeout.** An init container that waits forever leaves the Pod in `Init:0/1` and nobody notices until the deploy is 3 hours late.

> 🔑 Port-open ≠ ready-to-serve. Postgres accepts TCP connections during crash recovery but rejects queries. For a real readiness check, use the app's own probe:
> ```yaml
> command: ["sh","-c","until pg_isready -h db -U shop -d app; do sleep 2; done"]
> ```

**2. Migrations before serving → Job + wait, in the pipeline.**

```makefile
deploy:
	kubectl apply -f k8s/base/db.yaml
	kubectl rollout status sts/db -n $(NS) --timeout=300s
	kubectl delete job shop-api-migrate -n $(NS) --ignore-not-found
	kubectl apply -f k8s/base/migrate-job.yaml
	kubectl wait --for=condition=complete job/shop-api-migrate -n $(NS) --timeout=900s
	kubectl apply -k k8s/overlays/$(ENV)
	kubectl rollout status deploy/shop-api -n $(NS) --timeout=300s
```

With Helm, the same thing is declarative:

```yaml
metadata:
  annotations:
    "helm.sh/hook": pre-upgrade
    "helm.sh/hook-weight": "-5"
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
```

Helm runs hooks to completion *before* applying the rest of the release. If the Job fails, the release fails and nothing rolls out.

**3. Migrations must be backward compatible.** While the rollout runs, v1 and v2 Pods serve simultaneously. So:
- ✅ Add a nullable column → both versions work
- ✅ Add a table → both versions work
- ❌ Rename/drop a column → v1 breaks instantly
- Use **expand → migrate → contract** across three releases (see [Project 9 §9.10](12-PROJECT-9-java-backend.md#910-database-migrations-flyway-not-ddl-auto))

**4. What about a real startup-order DAG?**

Kubernetes deliberately has **no** `depends_on`. If you find yourself needing one across services, you probably want:
- **Argo CD Sync Waves** — `argocd.argoproj.io/sync-wave: "-1"` on the DB, `"0"` on migrations, `"1"` on the API, `"2"` on the UI. Argo applies them in order and waits for health between waves.
  ```yaml
  metadata:
    annotations:
      argocd.argoproj.io/sync-wave: "-1"
      argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource=true
  ```
- **Helm hook weights** (as above)
- **App-level resilience** — retries with backoff, circuit breakers (Resilience4j), and a readiness gate. This is the *real* answer for a distributed system: assume dependencies come and go.

```java
// Resilience4j — retry with backoff so a slow DB doesn't crash boot
@Retry(name = "db", fallbackMethod = "cachedProducts")
public List<Product> products() { return repo.findAll(); }
```

**5. Verify your ordering works by breaking it:**

```bash
# scale the DB to zero, then roll the API — the init container should block, then succeed
kubectl scale sts/db -n shop --replicas=0
kubectl rollout restart deploy/shop-api -n shop &
sleep 15
kubectl get pods -n shop -l app=shop-api
# shop-api-xxx   0/1   Init:0/1   0   15s      ← correctly waiting, not crashing
kubectl logs -n shop -l app=shop-api -c wait-for-db --tail=3
# waiting for db.shop.svc.cluster.local:5432 (7)

kubectl scale sts/db -n shop --replicas=1
sleep 30
kubectl get pods -n shop -l app=shop-api
# shop-api-yyy   1/1   Running   0   20s       ← proceeded on its own ✅
```

</details>

---

### Task 10.2 — Debug "works from my laptop, fails in the cluster"

`kubectl port-forward svc/shop-api 8080:8080` and `curl localhost:8080/api/products` works. Through the Ingress it returns 502. Find it.

<details>
<summary>Show answer</summary>

`port-forward` bypasses the Service **and** kube-proxy — it tunnels straight to one Pod. So "port-forward works, Ingress doesn't" narrows the problem to exactly three places: **the Service, the endpoints, or the Ingress config.**

**Step 1 — Do the endpoints exist?** (This is the answer 70% of the time.)

```bash
kubectl get endpointslices -n shop -l kubernetes.io/service-name=shop-api
kubectl get endpointslices -n shop -l kubernetes.io/service-name=shop-api \
  -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]}:{endpoints[*].ports[*].port} ready={.conditions.ready}{"\n"}{end}'
kubectl describe svc shop-api -n shop | grep -iE 'selector|endpoints|port'
```

| Result | Meaning | Fix |
|---|---|---|
| No EndpointSlice at all | Service selector matches nothing | Compare `svc.spec.selector` with `pod.metadata.labels` |
| EndpointSlice exists, `ready=false` | Readiness probe failing | `kubectl describe pod` → probe errors |
| EndpointSlice empty | Same as above | Same |
| Endpoints present and ready | Not a Service problem → go to Step 3 | |

```bash
kubectl get svc shop-api -n shop -o jsonpath='{.spec.selector}'; echo
kubectl get pods -n shop -l app=shop-api --show-labels
```

**Step 2 — Is `targetPort` right?**

```bash
kubectl get svc shop-api -n shop -o yaml | grep -A4 ports
#   port: 8080
#   targetPort: http        ← a NAME. Does the container declare it?
kubectl get pod -n shop -l app=shop-api -o jsonpath='{.items[0].spec.containers[0].ports}'; echo
# [{"containerPort":8080,"name":"http","protocol":"TCP"}]   ✅
```

A named `targetPort` that doesn't match any `containerPort.name` produces an **empty EndpointSlice with no error message anywhere**. Very sneaky.

Verify the Pod actually listens on that port:

```bash
kubectl exec -n shop deploy/shop-api -- sh -c 'netstat -tln 2>/dev/null || ss -tln'
# LISTEN 0 100 :::8080 :::*
kubectl exec -n shop deploy/shop-api -- curl -s localhost:8080/actuator/health/readiness
# {"status":"UP"}     ✅ so the app is fine; the problem is routing
```

**Step 3 — Test the Service from inside the cluster, bypassing the Ingress.**

```bash
kubectl run t -n shop --rm -it --image=nicolaka/netshoot --restart=Never -- bash
# inside:
dig +short shop-api.shop.svc.cluster.local          # → the ClusterIP
curl -sv http://shop-api:8080/actuator/health/readiness
nc -zv shop-api 8080
for i in $(seq 1 10); do curl -s -o /dev/null -w '%{http_code} ' http://shop-api:8080/api/products; done; echo
exit
```

| Result | Meaning |
|---|---|
| Works | Service is fine → the problem is the **Ingress** (Step 4) |
| `connection refused` | Pods aren't listening on that port, or endpoints are wrong |
| Hangs / timeout | **NetworkPolicy** blocking you, or kube-proxy rules broken |
| Intermittent 502 | One Pod of several is broken |

**NetworkPolicy is the sneaky one here.** If you applied default-deny and forgot to allow the Ingress controller:

```bash
kubectl get netpol -n shop
kubectl describe netpol -n shop shop-api

# test from the ingress controller's perspective specifically:
kubectl -n ingress-nginx exec deploy/ingress-nginx-controller -- \
  curl -sv -m 5 http://shop-api.shop.svc.cluster.local:8080/actuator/health/readiness
# hangs → BLOCKED by NetworkPolicy ✅ found it
```

Fix:

```yaml
ingress:
  - from:
      - namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: ingress-nginx}}
        podSelector: {matchLabels: {app.kubernetes.io/name: ingress-nginx}}
    ports: [{protocol: TCP, port: 8080}]
```

⚠️ **Check the controller's actual labels** — they vary by install method:

```bash
kubectl get pods -n ingress-nginx --show-labels
# app.kubernetes.io/component=controller,app.kubernetes.io/instance=ingress,
# app.kubernetes.io/name=ingress-nginx,…
```

**Step 4 — The Ingress itself.**

```bash
kubectl describe ingress shop-api -n shop
kubectl get ingress -n shop -o custom-columns='NAME:.metadata.name,CLASS:.spec.ingressClassName,HOSTS:.spec.rules[*].host,PATHS:.spec.rules[*].http.paths[*].path,ADDRESS:.status.loadBalancer.ingress[0].ip'

# what did the controller actually generate?
kubectl -n ingress-nginx exec deploy/ingress-nginx-controller -- nginx -T \
  | grep -B5 -A40 'server_name shop.example.com'

# the controller's own error log — the exact upstream it tried
kubectl -n ingress-nginx logs deploy/ingress-nginx-controller --tail=200 \
  | grep -E 'shop-api|502' | tail -20
```

Look for the log line:

```
2026/09/09 14:22:01 [error] 31#31: *42 connect() failed (111: Connection refused)
  while connecting to upstream, client: 10.244.0.1, server: shop.example.com,
  request: "GET /api/products HTTP/1.1",
  upstream: "http://10.244.2.19:8080/api/products", host: "shop.example.com"
```

| Upstream shown | Diagnosis |
|---|---|
| `http://10.244.2.19:8080/api/products` | The rewrite didn't apply — the API got `/api/products`, not `/products` → 404 from Spring, surfaced as 502/404 |
| `http://10.244.2.19:80/api/products` | **`targetPort` wrong** — the Ingress is dialling the Service port on the Pod |
| `no resolver defined` / `shop-api could not be resolved` | DNS from the controller's namespace |
| upstream absent, `default backend` | No Ingress rule matched → 404 |

**Step 5 — The rewrite trap.**

```bash
# what path does the backend ACTUALLY receive?
kubectl logs -n shop deploy/shop-api --tail=50 | grep -i 'products'
```

If Spring logs `/api/products` but your controller is `@RequestMapping("/api/products")` — fine. If it's `@RequestMapping("/products")` and the rewrite didn't apply — 404.

```bash
kubectl get ingress shop-api -n shop -o jsonpath='{.metadata.annotations}'; echo | jq .
# must contain: "nginx.ingress.kubernetes.io/rewrite-target": "/$2"
kubectl get ingress shop-api -n shop -o jsonpath='{.spec.rules[0].http.paths[0].path}'; echo
# must be: /api(/|$)(.*)
kubectl get ingress shop-api -n shop -o jsonpath='{.spec.rules[0].http.paths[0].pathType}'; echo
# must be: ImplementationSpecific   ← Prefix will NOT do regex captures
```

**All three must be right, together.** Miss any one and you get a 404 or 502.

**Step 6 — Reproduce with a controlled request.**

```bash
LB_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl -skv --resolve shop.example.com:443:$LB_IP https://shop.example.com/api/products 2>&1 \
  | grep -E '^< HTTP|^> Host|^< server|upstream'
```

**The 90-second version of this whole investigation:**

```bash
NS=shop; SVC=shop-api; ING=shop-api
echo "── endpoints ──"; kubectl get endpointslices -n $NS -l kubernetes.io/service-name=$SVC
echo "── selector  ──"; kubectl get svc $SVC -n $NS -o jsonpath='{.spec.selector}'; echo
echo "── pod labels──"; kubectl get pods -n $NS -l app=$SVC --show-labels
echo "── ingress    ──"; kubectl describe ingress $ING -n $NS | sed -n '/Rules:/,/Annotations:/p'
echo "── controller ──"; kubectl -n ingress-nginx logs deploy/ingress-nginx-controller --tail=50 | grep -E "$SVC|502"
echo "── netpol     ──"; kubectl -n ingress-nginx exec deploy/ingress-nginx-controller -- \
                        curl -s -m 3 -o /dev/null -w '%{http_code}\n' http://$SVC.$NS.svc.cluster.local:8080/actuator/health/liveness
```

</details>

---

### Task 10.3 — Deploy the full stack with zero downtime, and prove it

Both tiers at once, under sustained load, with a database migration in the middle.

<details>
<summary>Show answer</summary>

The full ceremony, in order. Every step exists because skipping it causes an outage.

```bash
#!/usr/bin/env bash
set -euo pipefail
NS=shop; ENV=prod; TAG=${1:?usage: $0 <tag>}; HOST=shop.example.com
LB_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# ── 0. PRE-FLIGHT ─────────────────────────────────────────────
echo "▸ 0. pre-flight"
kubectl get nodes | grep -c Ready
kubectl auth can-i update deployments -n $NS
kubectl auth can-i create jobs        -n $NS
[ "$(kubectl get deploy shop-api -n $NS -o jsonpath='{.status.readyReplicas}')" = \
  "$(kubectl get deploy shop-api -n $NS -o jsonpath='{.spec.replicas}')" ] \
  || { echo "❌ cluster is not healthy BEFORE we start — abort"; exit 1; }

# is there enough capacity for maxSurge?
kubectl describe nodes | grep -A6 "Allocated resources" | grep cpu

# record the current revision so we can roll back precisely
OLD_API=$(kubectl get deploy shop-api -n $NS -o jsonpath='{.spec.template.spec.containers[0].image}')
OLD_UI=$(kubectl get deploy shop-ui  -n $NS -o jsonpath='{.spec.template.spec.containers[0].image}')
echo "   current: api=$OLD_API ui=$OLD_UI"

# ── 1. VERIFY THE ARTIFACT BEFORE TOUCHING THE CLUSTER ────────
echo "▸ 1. verify image"
cosign verify \
  --certificate-identity-regexp="https://github.com/3558Bhk/.*/.github/workflows/deploy.yaml" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  $REGISTRY/shop-api:$TAG
docker manifest inspect $REGISTRY/shop-api:$TAG >/dev/null
trivy image --severity CRITICAL,HIGH --ignore-unfixed --exit-code 1 $REGISTRY/shop-api:$TAG

# ── 2. START THE LOAD ─────────────────────────────────────────
echo "▸ 2. starting load"
hey -z 600s -q 40 -c 10 -host $HOST "http://$LB_IP/api/products" > load.txt 2>&1 &
HEY=$!
( while true; do
    code=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 5 --resolve $HOST:443:$LB_IP https://$HOST/api/products)
    echo "$(date +%H:%M:%S) $code"
    sleep 0.2
  done ) > live.txt 2>&1 &
LIVE=$!
sleep 10

# ── 3. MIGRATE FIRST (backward compatible!) ───────────────────
echo "▸ 3. migrating schema"
sed "s|image: ghcr.io/3558bhk/shop-api:.*|image: $REGISTRY/shop-api:$TAG|" \
    k8s/base/migrate-job.yaml | kubectl apply -n $NS -f -
kubectl wait --for=condition=complete job/shop-api-migrate -n $NS --timeout=900s
kubectl logs -n $NS job/shop-api-migrate --tail=20

# ⚠️ old pods are STILL SERVING against the new schema. That's the point of
#    expand→migrate→contract. If this breaks the old version, STOP and roll back.
kubectl rollout status deploy/shop-api -n $NS --timeout=30s   # must still be healthy

# ── 4. ROLL THE API ───────────────────────────────────────────
echo "▸ 4. rolling api"
kubectl annotate deploy/shop-api -n $NS kubernetes.io/change-cause="deploy $TAG" --overwrite
kubectl set image deploy/shop-api -n $NS api=$REGISTRY/shop-api:$TAG
kubectl rollout status deploy/shop-api -n $NS --timeout=300s || {
  echo "❌ api rollout FAILED — rolling back"
  kubectl rollout undo deploy/shop-api -n $NS
  kubectl rollout status deploy/shop-api -n $NS --timeout=180s
  exit 1
}

# ── 5. ROLL THE UI ────────────────────────────────────────────
echo "▸ 5. rolling ui"
kubectl set image deploy/shop-ui -n $NS web=$REGISTRY/shop-ui:$TAG
kubectl rollout status deploy/shop-ui -n $NS --timeout=180s || {
  echo "❌ ui rollout FAILED — rolling back BOTH"
  kubectl rollout undo deploy/shop-ui  -n $NS
  kubectl rollout undo deploy/shop-api -n $NS
  exit 1
}

# ── 6. VERIFY ─────────────────────────────────────────────────
echo "▸ 6. verifying"
sleep 20
./scripts/smoke-test.sh $NS $HOST

# ── 7. MEASURE ────────────────────────────────────────────────
echo "▸ 7. results"
wait $HEY || true
kill $LIVE 2>/dev/null || true

echo "── live request codes during the deploy ──"
awk '{print $2}' live.txt | sort | uniq -c | sort -rn
echo "── hey summary ──"
grep -E 'Requests/sec|Latency distribution|Status code distribution|Error distribution' -A5 load.txt
```

Expected:

```
── live request codes during the deploy ──
   2998 200
── hey summary ──
Requests/sec:              39.94
Status code distribution:
  [200] 23960 responses
Error distribution:
  [Get "http://…": context deadline exceeded]   2      ← 2 timeouts out of 24k
Latency distribution:
  50% in 0.0180 secs
  95% in 0.0510 secs
  99% in 0.3100 secs
```

**Two timeouts out of 24,000 is a real result.** Investigate them (usually the moment a Pod left rotation) and decide whether it's acceptable. If not, lengthen the `preStop` sleep.

**What made this work — the checklist:**

| Requirement | Where |
|---|---|
| `maxUnavailable: 0` | Deployment strategy |
| Working readiness probe | `/actuator/health/readiness` |
| `startupProbe` with a long budget | JVM boot takes 20–40 s |
| `preStop: sleep 10` | Endpoint propagation |
| `terminationGracePeriodSeconds: 60` > preStop + drain | Spring graceful shutdown |
| `server.shutdown: graceful` | Drain in-flight requests |
| tini + `exec java` | SIGTERM actually reaches the JVM |
| PDB `maxUnavailable: 1` | Survives node drains |
| Backward-compatible migration | Old Pods work on the new schema |
| Capacity for `maxSurge` | Enough allocatable CPU/memory |
| `rollout status --timeout` in CI | A stalled deploy fails the build |
| Automatic `rollout undo` on failure | MTTR in seconds |

**Rollback plan, written down before you start:**

```bash
# fast (seconds) — undo the last rollout
kubectl rollout undo deploy/shop-api -n shop
kubectl rollout undo deploy/shop-ui  -n shop

# precise — go to a known-good revision
kubectl rollout history deploy/shop-api -n shop
kubectl rollout undo deploy/shop-api -n shop --to-revision=7

# nuclear — redeploy the previous image tag from Git
git revert <sha> && git push        # Argo CD syncs it back

# schema rollback — usually you DON'T
# expand→migrate→contract means the old schema is still valid.
# If you did contract, restore from the pre-migration backup:
velero restore create --from-backup pre-deploy-$(date +%F) --include-namespaces shop
```

</details>

---

### Task 10.4 — Split the stack into three namespaces with cross-namespace policies

`frontend`, `backend`, `data`. Enforce that only `backend` may reach `data`.

<details>
<summary>Show answer</summary>

```yaml
# ── namespaces ──
apiVersion: v1
kind: Namespace
metadata:
  name: frontend
  labels: {tier: frontend, kubernetes.io/metadata.name: frontend}
---
apiVersion: v1
kind: Namespace
metadata:
  name: backend
  labels: {tier: backend, kubernetes.io/metadata.name: backend}
---
apiVersion: v1
kind: Namespace
metadata:
  name: data
  labels: {tier: data, kubernetes.io/metadata.name: data,
           pod-security.kubernetes.io/enforce: restricted}
```

> 🔑 Every namespace automatically carries `kubernetes.io/metadata.name: <its own name>` since v1.21 — you can select on it without labelling anything. Adding your own `tier` label makes the intent explicit and lets you select *groups* of namespaces.

```yaml
# ── DATA namespace: deny everything, then allow only backend ──
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: deny-all, namespace: data}
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: allow-dns, namespace: data}
spec:
  podSelector: {}
  policyTypes: [Egress]
  egress:
    - to:
        - namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: kube-system}}
          podSelector: {matchLabels: {k8s-app: kube-dns}}
      ports: [{protocol: UDP, port: 53}, {protocol: TCP, port: 53}]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: db-from-backend-only, namespace: data}
spec:
  podSelector: {matchLabels: {app: db}}
  policyTypes: [Ingress]
  ingress:
    # ⭐ namespaceSelector AND podSelector in ONE item = AND
    - from:
        - namespaceSelector: {matchLabels: {tier: backend}}
          podSelector: {matchLabels: {app: shop-api}}
      ports: [{protocol: TCP, port: 5432}]
```

```yaml
# ── BACKEND: ingress from the Ingress controller + monitoring; egress to data ──
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: api-ingress, namespace: backend}
spec:
  podSelector: {matchLabels: {app: shop-api}}
  policyTypes: [Ingress]
  ingress:
    - from:
        - namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: ingress-nginx}}
          podSelector: {matchLabels: {app.kubernetes.io/name: ingress-nginx}}
      ports: [{protocol: TCP, port: 8080}]
    - from:
        - namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: monitoring}}
      ports: [{protocol: TCP, port: 8080}]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: api-egress, namespace: backend}
spec:
  podSelector: {matchLabels: {app: shop-api}}
  policyTypes: [Egress]
  egress:
    - to:
        - namespaceSelector: {matchLabels: {tier: data}}
          podSelector: {matchLabels: {app: db}}
      ports: [{protocol: TCP, port: 5432}]
    - to:
        - namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: kube-system}}
          podSelector: {matchLabels: {k8s-app: kube-dns}}
      ports: [{protocol: UDP, port: 53}]
```

**Now the DNS names must be fully qualified**, because short names only resolve inside your own namespace:

```yaml
# backend/shop-api ConfigMap
SPRING_DATASOURCE_URL: "jdbc:postgresql://db.data.svc.cluster.local:5432/app"
```

**Cross-namespace RBAC for the migration Job** (it runs in `backend` but needs no `data` RBAC — only network access, which the policy above grants).

**Verify the matrix:**

```bash
test_conn() {  # test_conn <from-ns> <from-labels> <to-host> <port> <expect>
  kubectl run t-$RANDOM -n "$1" --rm -i --restart=Never --image=nicolaka/netshoot \
    ${2:+--labels="$2"} -- nc -zv -w 3 "$3" "$4" >/dev/null 2>&1 \
    && echo "✅ $1/$2 → $3:$4 ALLOWED" || echo "⛔ $1/$2 → $3:$4 BLOCKED"
}

test_conn backend  app=shop-api db.data.svc.cluster.local 5432 "allow"
test_conn frontend app=shop-ui  db.data.svc.cluster.local 5432 "deny"
test_conn default  ""           db.data.svc.cluster.local 5432 "deny"
```

Expected:
```
✅ backend/app=shop-api → db.data.svc.cluster.local:5432 ALLOWED
⛔ frontend/app=shop-ui → db.data.svc.cluster.local:5432 BLOCKED
⛔ default/ → db.data.svc.cluster.local:5432 BLOCKED
```

**Also enforce it at the API level** — a NetworkPolicy is network-layer only. Add RBAC so the frontend's ServiceAccount can't even *read* the db Secret:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: {name: api-db-reader, namespace: data}
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    resourceNames: ["pg-creds"]      # ⭐ resourceNames = only THIS secret
    verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: {name: api-reads-db-creds, namespace: data}
subjects:
  - {kind: ServiceAccount, name: shop-api, namespace: backend}
roleRef: {kind: Role, name: api-db-reader, apiGroup: rbac.authorization.k8s.io}
```

```bash
kubectl auth can-i get secret/pg-creds -n data --as=system:serviceaccount:backend:shop-api   # yes
kubectl auth can-i get secret/pg-creds -n data --as=system:serviceaccount:frontend:shop-ui   # no
```

**Caveat:** a ServiceAccount in namespace A cannot mount a Secret in namespace B via `secretKeyRef` — Secret references are always same-namespace. So either:
- mirror the Secret with **Reflector** / **kubed**: `reflector.v1.kembero.com/enabled: "true"` + `namespaces: "backend"`
- use **External Secrets Operator** to materialise it in each namespace from one source
- or (simplest) keep the Secret in `backend` where the API lives, and let `data` hold only the database

The last one is what most teams do. Cross-namespace Secret sharing is usually a design smell.

</details>

---

### Task 10.5 — Make the stack survive a full node loss

Kill a node. The app must stay up. Prove it, and find what breaks.

<details>
<summary>Show answer</summary>

**Before the test — make sure you're set up to survive:**

```bash
NS=shop
# 1. Are replicas spread across nodes?
kubectl get pods -n $NS -o custom-columns='NAME:.metadata.name,NODE:.spec.nodeName,ZONE:.metadata.labels.topology\.kubernetes\.io/zone'
# If all 3 api pods are on ONE node, you fail before you start.

# 2. Check the spread constraints
kubectl get deploy shop-api -n $NS -o jsonpath='{.spec.template.spec.topologySpreadConstraints}' | jq .
kubectl get deploy shop-api -n $NS -o jsonpath='{.spec.template.spec.affinity}' | jq .

# 3. Are PDBs in place?
kubectl get pdb -n $NS
# shop-api   3   1   3   ...      ← DISRUPTIONS ALLOWED = 1

# 4. Do requests leave room for a surge?
kubectl describe nodes | grep -A6 "Allocated resources" | grep cpu
```

If everything is on one node, fix it first:

```bash
kubectl patch deploy shop-api -n $NS --type=merge -p '
spec:
  template:
    spec:
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: DoNotSchedule
          minDomains: 3
          labelSelector: {matchLabels: {app: shop-api}}
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: ScheduleAnyway
          labelSelector: {matchLabels: {app: shop-api}}'
kubectl rollout status deploy/shop-api -n $NS
kubectl get pods -n $NS -l app=shop-api -o wide    # three different nodes ✅
```

**The test:**

```bash
LB_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
HOST=shop.example.com

# continuous health probe
( while true; do
    echo "$(date +%H:%M:%S) $(curl -sk -o /dev/null -w '%{http_code}' --max-time 3 --resolve $HOST:443:$LB_IP https://$HOST/api/products)"
    sleep 0.5
  done ) > nodeloss.txt &
PROBE=$!

# pick the node with the most shop pods
VICTIM=$(kubectl get pods -n $NS -o wide --no-headers | awk '{print $7}' | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')
echo "killing node: $VICTIM"
kubectl get pods -n $NS -o wide | grep $VICTIM

# kill it
docker stop $VICTIM

# watch
kubectl get nodes -w &  NODES=$!
kubectl get pods -n $NS -o wide -w &  PODS=$!
sleep 180
kill $NODES $PODS $PROBE
docker start $VICTIM
```

**The timeline you should see:**

| t | What happens |
|---|---|
| 0 s | `docker stop` → kubelet stops heartbeating |
| ~40 s | node-controller marks the node `NotReady`, adds `node.kubernetes.io/unreachable:NoExecute` |
| 40–340 s | Pods on that node are still "Running" in the API (stale status) but unreachable. The `unreachable` toleration defaults to **300 s** |
| ~40 s | **Endpoints are removed immediately** — this is the important part. The Service stops routing there right away |
| ~340 s | Pods are force-deleted; the Deployment creates replacements on live nodes |

```bash
grep -c ' 200$' nodeloss.txt
grep -vE ' 200$' nodeloss.txt | head -20
```

You should see **zero or a handful** of non-200s — because the endpoints were withdrawn within seconds even though the Pod object lingered for 5 minutes.

**Shorten the 300 s window** if your app can tolerate it:

```yaml
spec:
  containers:
    - name: api
      # ...
  tolerations:
    - key: node.kubernetes.io/unreachable
      operator: Exists
      effect: NoExecute
      tolerationSeconds: 30          # ← reschedule after 30s instead of 300s
    - key: node.kubernetes.io/not-ready
      operator: Exists
      effect: NoExecute
      tolerationSeconds: 30
```

⚠️ **Don't do this for StatefulSets.** With `tolerationSeconds: 30` and a *brief* network partition, Kubernetes will start a second `db-0` on another node while the first is still alive and holding the volume → potential data corruption. StatefulSet Pods deliberately wait. This is why your DB needs real replication and an operator, not just a low tolerance.

**What usually breaks — and the fixes:**

| Failure | Why | Fix |
|---|---|---|
| **DB goes down** | Single-replica StatefulSet with a local/zoned PV on the dead node | Real replication (CloudNativePG), or RWX/network storage, or accept it and rely on the backup |
| API can't reschedule | Not enough allocatable CPU on the remaining nodes | Cluster autoscaler / Karpenter; right-size requests |
| Ingress controller dies too | Only 1–2 replicas | `replicaCount: 3` + topology spread + a PDB |
| CoreDNS dies | Few replicas | `replicas: 3`, PDB, topology spread |
| PVC won't reattach | Zoned disk, node gone | Snapshot/restore, or move to network storage |
| HPA can't scale up | Nodes are full | Cluster autoscaler must be faster than the traffic |
| PDB blocks the reschedule | `minAvailable: 3` on a 3-replica Deployment | `maxUnavailable: 1` instead |
| Cert-manager webhook down | Single replica | 2+ replicas |

**Harden the platform components too:**

```bash
kubectl -n ingress-nginx patch deploy ingress-nginx-controller --type=merge -p '
spec:
  replicas: 3
  template:
    spec:
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: DoNotSchedule
          labelSelector: {matchLabels: {app.kubernetes.io/name: ingress-nginx, app.kubernetes.io/component: controller}}'

kubectl -n ingress-nginx apply -f - <<'EOF'
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata: {name: ingress-nginx-controller, namespace: ingress-nginx}
spec:
  minAvailable: 2
  selector: {matchLabels: {app.kubernetes.io/name: ingress-nginx, app.kubernetes.io/component: controller}}
EOF

kubectl -n kube-system patch deploy coredns --type=merge -p '{"spec":{"replicas":3}}'
```

**The acceptance criteria for "survives a node loss":**
- [ ] ≥3 replicas of every tier, spread with `DoNotSchedule` across nodes
- [ ] PDB on every workload
- [ ] Requests sized so N-1 nodes can hold everything
- [ ] The database replicated across nodes (or an accepted RTO with a tested restore)
- [ ] Platform components (ingress, CoreDNS, cert-manager, Prometheus) also HA
- [ ] Alerts on `kube_node_status_condition{condition="Ready"} == 0`
- [ ] **You have actually run this test.** A plan you haven't tested is a wish.

</details>

---

## 10.18 Checklist

- [ ] Draw the three-tier architecture and name every Service and port
- [ ] Explain why two Ingress objects share one hostname
- [ ] Write a default-deny NetworkPolicy set and verify each rule with a real connection test
- [ ] Explain why `namespaceSelector` + `podSelector` in one item means AND
- [ ] Check whether your CNI actually enforces NetworkPolicy
- [ ] Run migrations as a Job before the rollout, with `backoffLimit: 0`
- [ ] Use init containers with a *timeout* for dependency ordering
- [ ] Explain why Kubernetes has no `depends_on` and what to use instead
- [ ] Diagnose "port-forward works, Ingress doesn't" in under two minutes
- [ ] Deploy both tiers under load and measure the dropped-request count
- [ ] Build a smoke test that verifies the whole chain including the database row
- [ ] Survive a node loss with a replicated, spread, PDB-protected stack

**Next → [`14-PROJECT-11-react-python-fullstack.md`](14-PROJECT-11-react-python-fullstack.md)** — the same shape with FastAPI, plus what's genuinely different about Python on Kubernetes.

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish%20Kumar%20Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn → <https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260>
🐙 GitHub → <https://github.com/3558Bhk>

*Built for engineers who learn by breaking things on purpose.*

</div>
