# 🥉 Project 3 — ConfigMaps, Secrets & the "my config change did nothing" problem

> **Time:** 2 hours · **Prereq:** [Project 2](05-PROJECT-2-deployment-service.md)
>
> **What you'll learn:** every way to get configuration into a Pod, which of them auto-update and which don't, how to handle Secrets without leaking them, and the four classic config bugs that eat an afternoon.

---

## 3.1 The 60-second theory

Your Docker instincts were: `docker run -e FOO=bar --env-file .env -v ./cfg:/etc/app`. Kubernetes splits that into two objects:

| Object | Holds | Base64? | Extra powers |
|---|---|---|---|
| **ConfigMap** | Non-sensitive config: strings, numbers, whole files | No | Can be mounted as files, auto-updates when mounted |
| **Secret** | Passwords, tokens, TLS certs, registry creds | Yes (**encoding ≠ encryption**) | Separate RBAC, etcd encryption-at-rest, `type: kubernetes.io/tls`, external secret stores |

Both are consumed in exactly the same four ways: single env var, all-keys-as-env, volume file, command args.

> 🔑 **The one thing that bites everyone:** config mounted as a **volume** updates automatically (~1 min). Config injected as **env vars** NEVER updates — env is read once at process start. And a `subPath` mount never updates either.

---

## 3.2 Step 1 — Create ConfigMaps five different ways

```bash
mkdir -p ~/k8s-learn/p3/config && cd ~/k8s-learn/p3
```

```bash
# 1. From literals
kubectl create configmap app-config \
  --from-literal=LOG_LEVEL=debug \
  --from-literal=MAX_CONNECTIONS=20 \
  --from-literal=FEATURES=dark_mode,new_checkout

# 2. From a single file (key defaults to the filename)
cat > config/app.conf <<'EOF'
worker_threads = 4
queue_size = 1000
timeout_ms = 5000
EOF
kubectl create configmap app-conf --from-file=config/app.conf

# 3. From a file with a CUSTOM key
kubectl create configmap app-conf2 --from-file=SETTINGS=config/app.conf

# 4. From a whole directory (each file becomes a key; subdirectories are NOT walked)
kubectl create configmap app-dir --from-file=config/

# 5. From an env-file
cat > .env <<'EOF'
# comments are fine
API_URL=https://api.example.com
RETRY_COUNT=3
EMPTY_VALUE=
EOF
kubectl create configmap app-env --from-env-file=.env
```

Inspect them:

```bash
kubectl get configmaps
kubectl describe configmap app-config
kubectl get configmap app-dir -o yaml
```

```yaml
apiVersion: v1
data:
  app.conf: |
    worker_threads = 4
    queue_size = 1000
    timeout_ms = 5000
kind: ConfigMap
metadata:
  creationTimestamp: "2026-09-09T12:00:00Z"
  name: app-dir
  namespace: default
  resourceVersion: "12345"
  uid: ...
```

Notice `data.app.conf` holds the **entire file contents** as one multi-line string. That's how file-based config works.

> ⚠️ **`kubectl create` fails if it already exists.** To update:
> ```bash
> kubectl create configmap app-config --from-literal=LOG_LEVEL=info \
>   --dry-run=client -o yaml | kubectl apply -f -
> ```
> That's the idiom. Memorise it.

### The declarative version (what goes in Git)

`configmap.yaml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: shop-config
  labels: {app: shop, env: dev}
data:
  # ── simple key/value pairs (become env vars) ──
  LOG_LEVEL: "debug"              # ⚠️ MUST be a string. Quote numbers & booleans!
  MAX_CONNECTIONS: "20"
  ENABLE_CACHE: "true"
  API_URL: "http://api:8080"

  # ── whole files ──
  nginx.conf: |
    worker_processes auto;
    events { worker_connections 1024; }
    http {
      server {
        listen 80;
        location / { return 200 "config from ConfigMap\n"; }
      }
    }

  app.properties: |
    server.port=8080
    spring.profiles.active=dev
    logging.level.root=INFO

# binaryData for non-UTF8 content (base64-encoded)
# binaryData:
#   keystore.jks: <base64>

# immutable: true        # ← optional; see §3.7
```

```bash
kubectl apply -f configmap.yaml
kubectl get cm shop-config -o jsonpath='{.data.LOG_LEVEL}'; echo
```

> ⚠️ **The #1 ConfigMap YAML bug:** writing `LOG_LEVEL: debug` is fine, but `MAX_CONNECTIONS: 20` gives you an **integer**, and Kubernetes rejects it:
> `cannot unmarshal number into Go struct field .data of type string`
> **Always quote values.** `ENABLE_CACHE: true` → string `"true"` if quoted; a real YAML boolean if not, which also fails.

---

## 3.3 Step 2 — Consume a ConfigMap as environment variables

`app-env.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata: {name: cfg-env}
spec:
  replicas: 1
  selector: {matchLabels: {app: cfg-env}}
  template:
    metadata: {labels: {app: cfg-env}}
    spec:
      containers:
        - name: app
          image: busybox:1.37
          command: ["sh", "-c", "env | grep -E '^(LOG|MAX|ENABLE|API)' | sort; echo '--- sleeping ---'; sleep 3600"]

          # ── METHOD 1: one specific key ──
          env:
            - name: LOG_LEVEL
              valueFrom:
                configMapKeyRef:
                  name: shop-config
                  key: LOG_LEVEL
            - name: MY_NODE
              valueFrom:
                fieldRef: {fieldPath: spec.nodeName}     # Downward API, not a ConfigMap
            - name: MISSING_BUT_OPTIONAL
              valueFrom:
                configMapKeyRef:
                  name: shop-config
                  key: NOT_THERE
                  optional: true                        # ← won't block the Pod

          # ── METHOD 2: every key at once ──
          envFrom:
            - configMapRef:
                name: shop-config
                optional: false
              prefix: ""                                # keys as-is
            - configMapRef: {name: app-env}
              prefix: ENVFILE_                          # ENVFILE_API_URL, ENVFILE_RETRY_COUNT
```

```bash
kubectl apply -f app-env.yaml
kubectl rollout status deploy/cfg-env
kubectl logs deploy/cfg-env
```

```
API_URL=http://api:8080
ENABLE_CACHE=true
ENVFILE_API_URL=https://api.example.com
ENVFILE_RETRY_COUNT=3
LOG_LEVEL=debug
MAX_CONNECTIONS=20
MY_NODE=learn-worker
nginx.conf=worker_processes auto;...      # ← ⚠️ WHOLE FILES became env vars too!
--- sleeping ---
```

> 🔑 **`envFrom` dumps EVERY key**, including your multi-line files, into the environment. That's messy and can break apps that iterate `os.environ`. If a ConfigMap mixes scalars and files, **split it into two ConfigMaps** — one for env, one for files. That's the professional habit.

### What happens when the ConfigMap doesn't exist?

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata: {name: cfg-missing}
spec:
  containers:
    - name: app
      image: busybox:1.37
      command: ["sh","-c","sleep 3600"]
      env:
        - name: X
          valueFrom: {configMapKeyRef: {name: nope, key: nope}}
EOF
kubectl get pod cfg-missing
# STATUS: CreateContainerConfigError
kubectl describe pod cfg-missing | sed -n '/Events:/,$p'
# Warning  Failed  ...  Error: configmap "nope" not found
kubectl delete pod cfg-missing
```

The container never starts. Add `optional: true` to make the Pod start anyway.

---

## 3.4 Step 3 — Consume a ConfigMap as files (the good way)

`app-files.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata: {name: cfg-files}
spec:
  replicas: 1
  selector: {matchLabels: {app: cfg-files}}
  template:
    metadata: {labels: {app: cfg-files}}
    spec:
      containers:
        - name: web
          image: nginx:1.29-alpine
          ports: [{containerPort: 80}]
          volumeMounts:
            # mount ONE key as ONE file, leaving the rest of the dir intact
            - name: nginx-conf
              mountPath: /etc/nginx/nginx.conf
              subPath: nginx.conf            # ← subPath = single file, doesn't shadow the dir
              readOnly: true
            # mount the WHOLE ConfigMap as a directory
            - name: app-files
              mountPath: /etc/app
              readOnly: true
      volumes:
        - name: nginx-conf
          configMap:
            name: shop-config
            items:                            # cherry-pick keys → filenames
              - key: nginx.conf               # the ConfigMap key
                path: nginx.conf              # the filename inside the volume
            defaultMode: 0444                 # octal, no leading 0 in YAML 1.1 — use 0444 carefully
        - name: app-files
          configMap:
            name: shop-config
            items:
              - {key: app.properties, path: app.properties}
              - {key: LOG_LEVEL, path: log_level.txt}   # scalars can be files too!
```

```bash
kubectl apply -f app-files.yaml
kubectl rollout status deploy/cfg-files
POD=$(kubectl get pod -l app=cfg-files -o jsonpath='{.items[0].metadata.name}')

kubectl exec $POD -- ls -la /etc/app/
kubectl exec $POD -- cat /etc/app/app.properties
kubectl exec $POD -- cat /etc/app/log_level.txt
kubectl exec $POD -- head -5 /etc/nginx/nginx.conf
kubectl exec $POD -- nginx -t                 # config is valid → nginx loaded it
```

Look at the mount mechanics — this explains the auto-update behaviour:

```bash
kubectl exec $POD -- ls -la /etc/app/
```

```
total 12
drwxrwxrwx    3 root     root           100 ... .
drwxr-xr-x    1 root     root            22 ... ..
drwx..r-xr-x    2 root     root            60 ... ..2026_09_09_12_00_00.123456789
lrwx..rwxrwx    1 root     root            31 ... ..data -> ..2026_09_09_12_00_00.123456789
lrwx..rwxrwx    1 root     root            17 ... LOG_LEVEL -> ..data/LOG_LEVEL
lrwx..rwxrwx    1 root     root            21 ... app.properties -> ..data/app.properties
```

**Symlinks into a timestamped directory.** When the ConfigMap changes, Kubernetes writes a *new* timestamped directory and atomically flips the `..data` symlink. That's why:
- updates are atomic (no half-written files)
- **`subPath` mounts don't get updates** — a subPath mount copies the file directly, bypassing the symlink structure

### Watch an auto-update happen

Terminal A:

```bash
kubectl exec -it $POD -- sh -c 'while true; do echo "$(date +%T) $(cat /etc/app/LOG_LEVEL)"; sleep 2; done'
```

Terminal B:

```bash
kubectl patch configmap shop-config --type=merge -p '{"data":{"LOG_LEVEL":"warn"}}'
```

Terminal A flips from `debug` to `warn` — usually within 5–60 seconds (kubelet sync period + ConfigMap cache TTL).

**But nginx did not reload.** Verify:

```bash
kubectl exec $POD -- ps aux | grep nginx     # same PIDs as before
```

> 🔑 **Kubernetes updates the file. It is YOUR APP's job to notice.** Three ways to handle it:
> 1. **Reload on a signal / watch the file** — best (nginx `nginx -s reload`, Spring Cloud Kubernetes config reload, Viper's `WatchConfig`).
> 2. **Sidecar reloader** — e.g. `configmap-reload`, `nginx-config-reloader`, Reloader (stakater/Reloader) watches ConfigMaps and triggers `rollout restart`.
> 3. **Just restart** — `kubectl rollout restart deploy/cfg-files`. Boring, reliable, what most teams do.

---

## 3.5 Step 4 — Secrets

### Create them

```bash
# generic secret from literals
kubectl create secret generic db-creds \
  --from-literal=username=shop_app \
  --from-literal=password='S3cr3t!Pa$$'

# from files
echo -n 'S3cr3t!Pa$$' > /tmp/db-password
kubectl create secret generic db-creds-file --from-file=password=/tmp/db-password
shred -u /tmp/db-password 2>/dev/null || rm -f /tmp/db-password

# docker registry credentials
kubectl create secret docker-registry regcred \
  --docker-server=ghcr.io \
  --docker-username=harish \
  --docker-password=ghp_xxxxxxxxxxxx \
  --docker-email=you@example.com

# TLS
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout tls.key -out tls.crt -subj "/CN=shop.local/O=Learn"
kubectl create secret tls shop-tls --cert=tls.crt --key=tls.key

# SSH
kubectl create secret generic ssh-key --from-file=id_rsa=$HOME/.ssh/id_ed25519

# from an env-file (same as ConfigMap)
kubectl create secret generic app-secrets --from-env-file=.env.secret
```

### Inspect them

```bash
kubectl get secrets
kubectl describe secret db-creds          # shows keys and BYTE sizes, NOT values
kubectl get secret db-creds -o yaml       # base64 — trivially decodable
```

```yaml
apiVersion: v1
data:
  password: UzNjcjN0IVBhJCQ=
  username: c2hvcF9hcHA=
kind: Secret
type: Opaque
```

```bash
# decode one key
kubectl get secret db-creds -o jsonpath='{.data.password}' | base64 -d; echo

# decode all keys
kubectl get secret db-creds -o go-template='{{range $k,$v := .data}}{{$k}}={{$v | base64decode}}{{"\n"}}{{end}}'

# or jq
kubectl get secret db-creds -o json | jq -r '.data | to_entries[] | "\(.key)=\(.value|@base64d)"'
```

> ⚠️ **base64 is an encoding, not encryption.** Anyone with `get secret` permission can read every value. Real protection is a stack:
> 1. **RBAC** — most people shouldn't have `get secret`
> 2. **Encryption at rest** — `EncryptionConfiguration` on the API server encrypts Secret data in etcd
> 3. **External store** — Vault / AWS Secrets Manager / GCP Secret Manager, synced by External Secrets Operator
> 4. **Never in Git** — use Sealed Secrets, SOPS, or ESO

### The declarative form

```yaml
apiVersion: v1
kind: Secret
metadata: {name: db-creds-2}
type: Opaque
stringData:                       # ← plain text; Kubernetes base64-encodes it for you
  username: shop_app
  password: "S3cr3t!Pa$$"
```

**Use `stringData`, not `data`** — no manual base64, no `echo -n` mistakes (a trailing newline in `echo 'x' | base64` is a classic auth failure).

```bash
# if you must base64 manually:
echo -n 'S3cr3t!Pa$$' | base64       # -n is CRITICAL
```

### Secret types

| `type` | Keys expected | Used for |
|---|---|---|
| `Opaque` | anything | The default — 95% of cases |
| `kubernetes.io/tls` | `tls.crt`, `tls.key` | Ingress TLS |
| `kubernetes.io/dockerconfigjson` | `.dockerconfigjson` | Private registry auth |
| `kubernetes.io/dockercfg` | `.dockercfg` | Legacy registry auth |
| `kubernetes.io/basic-auth` | `username`, `password` | Basic auth |
| `kubernetes.io/ssh-auth` | `ssh-privatekey` | SSH |
| `kubernetes.io/service-account-token` | `token`, `ca.crt`, `namespace` | Legacy SA tokens (avoid) |
| `bootstrap.kubernetes.io/token` | `token-id`, `token-secret` | Node bootstrap |

Using the right `type` matters: tooling validates the keys (e.g. Ingress requires `tls.crt`/`tls.key`).

---

## 3.6 Step 5 — Consume Secrets (and why files beat env)

`app-secret.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata: {name: cfg-secret}
spec:
  replicas: 1
  selector: {matchLabels: {app: cfg-secret}}
  template:
    metadata: {labels: {app: cfg-secret}}
    spec:
      imagePullSecrets:                     # ← registry auth for the Pod's images
        - name: regcred
      containers:
        - name: app
          image: postgres:17-alpine
          command: ["sh", "-c"]
          args:
            - |
              echo "env method:   DB_PASSWORD=$DB_PASSWORD"
              echo "file method:  $(cat /run/secrets/db/password)"
              echo "--- sleeping ---"; sleep 3600
          env:
            # METHOD 1: env var (convenient, but leaks — see below)
            - name: DB_PASSWORD
              valueFrom:
                secretKeyRef: {name: db-creds, key: password}
            # METHOD 2: the *_FILE convention (what postgres/mysql/redis images expect)
            - name: POSTGRES_PASSWORD_FILE
              value: /run/secrets/db/password
          volumeMounts:
            # METHOD 3: as files — the recommended way
            - name: db-secret
              mountPath: /run/secrets/db
              readOnly: true
      volumes:
        - name: db-secret
          secret:
            secretName: db-creds
            items:
              - {key: password, path: password}
              - {key: username, path: username}
            defaultMode: 0400               # owner-read only
```

```bash
kubectl apply -f app-secret.yaml
kubectl rollout status deploy/cfg-secret
kubectl logs deploy/cfg-secret
```

```
env method:   DB_PASSWORD=S3cr3t!Pa$$
file method:  S3cr3t!Pa$$
```

Check the file permissions:

```bash
kubectl exec deploy/cfg-secret -- ls -la /run/secrets/db/
# -r--------    1 root  root  11  password
```

### Why files are safer than env vars

| Risk | env var | mounted file |
|---|---|---|
| Visible in `kubectl describe pod` | ❌ Only the *reference*, not the value ✅ | ✅ |
| Leaks into child processes | ❌ Yes, all of them inherit it | ✅ No |
| Visible via `/proc/<pid>/environ` | ❌ Yes, to anyone who can exec in | ✅ No |
| In a crash dump / core file | ❌ Often | ✅ Rarely |
| Printed by `env` in a debug session | ❌ Yes | ✅ No |
| Can be rotated without restarting | ❌ No | ✅ Yes (volume update) |
| Works with the `*_FILE` convention | — | ✅ |

**Official images that support `*_FILE`:** `postgres`, `mysql`, `mariadb`, `redis`, `mongo`, `rabbitmq`, `zookeeper`. Example: `POSTGRES_PASSWORD_FILE=/run/secrets/db/password` — the entrypoint reads the file instead of the env var. Use this.

> ⚠️ Note that `kubectl describe pod` **does not** show env values from `secretKeyRef` — it shows `<set to the key 'password' in secret 'db-creds'>`. But `kubectl get pod -o yaml` shows the *reference* too, not the value. The real leak is `/proc/<pid>/environ` and process inheritance.

### Verify what the Pod actually got

```bash
kubectl exec deploy/cfg-secret -- env | grep -i pass
kubectl exec deploy/cfg-secret -- sh -c 'cat /proc/1/environ | tr "\0" "\n" | grep -i pass'
```

---

## 3.7 Step 6 — Immutable ConfigMaps & Secrets

```yaml
apiVersion: v1
kind: ConfigMap
metadata: {name: shop-config-v1.4.2}
immutable: true
data:
  LOG_LEVEL: "warn"
```

Benefits:
- **Accidental edits are impossible** — `kubectl edit` and `apply` both fail with `field is immutable`.
- **Cluster performance:** kubelets stop watching immutable ConfigMaps. On a 1000-node cluster with 500 ConfigMaps, that's a massive reduction in API server watch traffic.

```bash
kubectl patch cm shop-config-v1.4.2 --type=merge -p '{"data":{"LOG_LEVEL":"debug"}}'
# The ConfigMap "shop-config-v1.4.2" is invalid: data: Forbidden: field is immutable
```

The pattern: **version-suffix your config objects** and let the Deployment reference the version. Changing config = creating a new ConfigMap + updating the reference = a real, tracked, rollable change.

```bash
kubectl create configmap shop-config-v1.4.3 --from-literal=LOG_LEVEL=debug \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl set env deploy/cfg-files --from=configmap/shop-config-v1.4.3   # triggers a rollout
```

Helm does this automatically: `configMapGenerator` in Kustomize appends a **content hash** to the name (`shop-config-7d9f8b6c5d`), so any content change creates a new object and rolls the Deployment. See [Guide §14.2](01-KUBERNETES-GUIDE.md#142-kustomize-in-5-minutes).

---

## 3.8 Step 7 — The four classic config bugs

### Bug 1: "I changed the ConfigMap but nothing happened"

```bash
kubectl patch cm shop-config --type=merge -p '{"data":{"LOG_LEVEL":"error"}}'
kubectl exec deploy/cfg-env -- env | grep LOG_LEVEL      # still "debug"!
```

**Cause:** consumed via `env`/`envFrom`. Env is read **once**, at process start.

**Fixes:**
```bash
kubectl rollout restart deploy/cfg-env       # the normal answer
```
or use the annotation-hash trick so a ConfigMap change automatically rolls the Deployment:

```yaml
spec:
  template:
    metadata:
      annotations:
        checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
```
(Helm) — or in Kustomize, use `configMapGenerator` (hash suffix), or install [stakater/Reloader](https://github.com/stakater/Reloader):
```bash
kubectl apply -f https://raw.githubusercontent.com/stakater/Reloader/master/deployments/kubernetes/reloader.yaml
# then annotate the Deployment:
kubectl annotate deploy/cfg-env secret.reloader.stakater.com/reload=shop-config
```

### Bug 2: "The mounted file updated but the app didn't"

**Cause:** the file changed on disk; the app cached it at startup.

**Fix:** make the app watch/reload, add a reloader sidecar, or `rollout restart`. For nginx specifically:

```yaml
lifecycle:
  postStart:
    exec: {command: ["/bin/sh","-c","(while true; do sleep 30; nginx -s reload; done) &"]}
```
(crude — use a proper reloader image in production.)

### Bug 3: "`subPath` mount never updates"

**Cause:** `subPath` copies the file, bypassing the symlink-swap mechanism.

**Fix:** either drop `subPath` (mount the whole ConfigMap into a dedicated directory), or accept that you must `rollout restart`.

```bash
# whole-configmap mount → updates
volumeMounts: [{name: cfg, mountPath: /etc/app}]
# subPath mount → frozen forever
volumeMounts: [{name: cfg, mountPath: /etc/app/nginx.conf, subPath: nginx.conf}]
```

If you need to place a file inside a directory the image already populates (like `/etc/nginx/nginx.conf`), `subPath` is unavoidable — so plan on restarts.

### Bug 4: "`CreateContainerConfigError` after a namespace move"

```bash
kubectl create namespace staging
kubectl apply -f app-env.yaml -n staging
kubectl get pods -n staging
# CreateContainerConfigError
```

**Cause:** ConfigMaps and Secrets are **namespaced**. Your Deployment is in `staging`, but `shop-config` only exists in `default`.

**Fix:** create the config objects in every namespace, or use a tool that syncs them (Helm/Kustomize per-environment overlays, or `kubed`/`Reflector` to mirror Secrets across namespaces).

```bash
kubectl get cm,secret -n staging        # empty
kubectl apply -f configmap.yaml -n staging
kubectl rollout restart deploy/cfg-env -n staging
```

---

## 3.9 Step 8 — A realistic full setup

This is what a production app's config layer looks like. Build it and run it.

`config/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: shop-dev

resources:
  - namespace.yaml
  - configmap.yaml
  - deployment.yaml
  - service.yaml

# generates a hashed name → automatic rollout on content change
configMapGenerator:
  - name: shop-config
    literals:
      - LOG_LEVEL=info
      - API_URL=http://api.shop-dev.svc.cluster.local:8080
    files:
      - nginx.conf=config/nginx.conf

secretGenerator:
  - name: db-creds
    envs: [.env.secret]        # ⚠️ MUST be in .gitignore
```

`config/namespace.yaml`:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: shop-dev
  labels:
    pod-security.kubernetes.io/enforce: baseline
    pod-security.kubernetes.io/warn: restricted
```

`config/nginx.conf`:

```nginx
worker_processes auto;
events { worker_connections 1024; }
http {
  access_log /dev/stdout;
  server {
    listen 8080;
    location /healthz { return 200 "ok\n"; }
    location /config  { return 200 "LOG_LEVEL was injected\n"; }
    location /        { return 200 "shop-dev frontend\n"; }
  }
}
```

`config/deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata: {name: shop}
spec:
  replicas: 2
  selector: {matchLabels: {app: shop}}
  template:
    metadata: {labels: {app: shop}}
    spec:
      containers:
        - name: web
          image: nginx:1.29-alpine
          ports: [{name: http, containerPort: 8080}]
          envFrom:
            - configMapRef: {name: shop-config}
          env:
            - name: DB_PASSWORD_FILE
              value: /run/secrets/db/password
          volumeMounts:
            - {name: nginx-conf, mountPath: /etc/nginx/nginx.conf, subPath: nginx.conf, readOnly: true}
            - {name: db, mountPath: /run/secrets/db, readOnly: true}
          resources:
            requests: {cpu: 50m, memory: 64Mi}
            limits: {cpu: 250m, memory: 128Mi}
          readinessProbe: {httpGet: {path: /healthz, port: http}, periodSeconds: 5}
          livenessProbe: {httpGet: {path: /healthz, port: http}, initialDelaySeconds: 10, periodSeconds: 20}
      volumes:
        - name: nginx-conf
          configMap: {name: shop-config}
        - name: db
          secret: {secretName: db-creds, defaultMode: 0400}
---
apiVersion: v1
kind: Service
metadata: {name: shop}
spec:
  selector: {app: shop}
  ports: [{name: http, port: 8080}]
```

```bash
echo 'DB_PASSWORD=S3cr3t!Pa$$' > config/.env.secret
echo '.env*' >> .gitignore

kubectl kustomize config/ | less          # ⭐ RENDER FIRST — inspect the generated names
kubectl apply -k config/
kubectl get all,cm,secret -n shop-dev
kubectl port-forward -n shop-dev svc/shop 8080:8080 &
sleep 2 && curl -s localhost:8080/healthz && curl -s localhost:8080/
kill %1
```

Note the generated ConfigMap name will be `shop-config-<hash>`, and the Deployment's references were rewritten automatically. Change `LOG_LEVEL` and re-apply → new hash → **automatic rollout**. That's the clean way to do config deploys.

```bash
kubectl delete -k config/
kubectl delete namespace shop-dev
```

---

## 3.10 Extra Tasks

### Task 3.1 — Inject the Pod's own metadata into the app

An app needs to log its Pod name, namespace, node, IP and resource limits. Do it without hardcoding anything.

<details>
<summary>Show answer</summary>

The **Downward API**. Two forms: env vars and a volume.

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: downward
  labels: {app: demo, tier: backend}
  annotations: {build: "1423", team: "platform"}
spec:
  containers:
    - name: app
      image: busybox:1.37
      command: ["sh","-c","echo '--- ENV ---'; env | grep POD_ | sort; echo '--- FILES ---'; ls -la /etc/podinfo; cat /etc/podinfo/labels; cat /etc/podinfo/annotations; cat /etc/podinfo/cpu-limit; sleep 3600"]
      resources:
        requests: {cpu: "100m", memory: "64Mi"}
        limits:   {cpu: "250m", memory: "128Mi"}
      env:
        - name: POD_NAME
          valueFrom: {fieldRef: {fieldPath: metadata.name}}
        - name: POD_NAMESPACE
          valueFrom: {fieldRef: {fieldPath: metadata.namespace}}
        - name: POD_UID
          valueFrom: {fieldRef: {fieldPath: metadata.uid}}
        - name: POD_IP
          valueFrom: {fieldRef: {fieldPath: status.podIP}}
        - name: HOST_IP
          valueFrom: {fieldRef: {fieldPath: status.hostIP}}
        - name: NODE_NAME
          valueFrom: {fieldRef: {fieldPath: spec.nodeName}}
        - name: SERVICE_ACCOUNT
          valueFrom: {fieldRef: {fieldPath: spec.serviceAccountName}}
        - name: CPU_REQUEST
          valueFrom: {resourceFieldRef: {containerName: app, resource: requests.cpu}}
        - name: CPU_LIMIT_CORES
          valueFrom: {resourceFieldRef: {containerName: app, resource: limits.cpu, divisor: "1"}}
        - name: MEM_LIMIT_MI
          valueFrom: {resourceFieldRef: {containerName: app, resource: limits.memory, divisor: 1Mi}}
      volumeMounts:
        - {name: podinfo, mountPath: /etc/podinfo, readOnly: true}
  volumes:
    - name: podinfo
      downwardAPI:
        items:
          - {path: "labels",     fieldRef: {fieldPath: metadata.labels}}
          - {path: "annotations",fieldRef: {fieldPath: metadata.annotations}}
          - {path: "cpu-limit",  resourceFieldRef: {containerName: app, resource: limits.cpu, divisor: "1m"}}
          - {path: "mem-limit",  resourceFieldRef: {containerName: app, resource: limits.memory, divisor: "1Mi"}}
EOF

kubectl logs downward
```

```
--- ENV ---
CPU_LIMIT_CORES=0.25
CPU_REQUEST=1
HOST_IP=172.18.0.3
MEM_LIMIT_MI=128
NODE_NAME=learn-worker
POD_IP=10.244.1.15
POD_NAME=downward
POD_NAMESPACE=default
POD_UID=8f3a...
SERVICE_ACCOUNT=default
--- FILES ---
-rw-r--r--  annotations    team="platform"\nbuild="1423"\n
-rw-r--r--  cpu-limit      250
-rw-r--r--  labels         app="demo"\ntier="backend"\n
-rw-r--r--  mem-limit      128
```

Notes:
- `resourceFieldRef` values are **rounded up to integers** unless you use `divisor`. With `divisor: "1"` on CPU you get cores (0.25 → rounds to 1). Use `divisor: "1m"` to get millicores as a file.
- Volume-based downward API values **do** update when labels/annotations change (unlike env).
- Common use: Prometheus `instance` labels, Jaeger service tags, structured log fields, "which pod served this request" headers.

```bash
kubectl delete pod downward
```

</details>

---

### Task 3.2 — Load a private image without leaking credentials

Pull from a private registry using a Secret, and make it work for every Pod in the namespace automatically.

<details>
<summary>Show answer</summary>

**Step 1 — create the registry Secret:**

```bash
# GitHub Container Registry
export GHCR_TOKEN=ghp_xxxxxxxxxxxx
kubectl create secret docker-registry ghcr-cred \
  --docker-server=ghcr.io \
  --docker-username=3558Bhk \
  --docker-password=$GHCR_TOKEN \
  -n shop-dev

# Docker Hub
kubectl create secret docker-registry dh-cred \
  --docker-server=https://index.docker.io/v1/ \
  --docker-username=harish --docker-password=$DH_PASSWORD -n shop-dev

# AWS ECR — the token EXPIRES every 12 hours, so use a CronJob or the ECR credential helper
TOKEN=$(aws ecr get-login-password --region ap-south-1)
kubectl create secret docker-registry ecr-cred \
  --docker-server=123456789012.dkr.ecr.ap-south-1.amazonaws.com \
  --docker-username=AWS --docker-password="$TOKEN" -n shop-dev
```

**Step 2 — reference it in the Pod:**

```yaml
spec:
  imagePullSecrets:
    - name: ghcr-cred
  containers:
    - name: app
      image: ghcr.io/3558bhk/myapp:1.4.2
      imagePullPolicy: IfNotPresent
```

**Step 3 — attach it to the ServiceAccount so you never repeat it (the pro move):**

```bash
kubectl create serviceaccount app-sa -n shop-dev
kubectl patch serviceaccount app-sa -n shop-dev \
  -p '{"imagePullSecrets":[{"name":"ghcr-cred"}]}'

# then in the Pod spec:
#   serviceAccountName: app-sa
```

Every Pod using `app-sa` now pulls with those credentials — no `imagePullSecrets` block anywhere.

**Verify:**

```bash
kubectl get sa app-sa -n shop-dev -o yaml | grep -A3 imagePullSecrets
kubectl get secret ghcr-cred -n shop-dev -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d | jq .
```

**Debugging `ImagePullBackOff` on a private registry:**

```bash
kubectl describe pod <pod> | sed -n '/Events:/,$p'
# 401 Unauthorized      → wrong/expired token
# 403 Forbidden         → token valid but no read access to that repo
# repository not found  → wrong name, or the repo is private and unauthenticated
# no basic auth credentials → imagePullSecrets missing or in the WRONG NAMESPACE
```

```bash
# sanity-check the credentials locally first
docker login ghcr.io -u 3558Bhk -p $GHCR_TOKEN
docker pull ghcr.io/3558bhk/myapp:1.4.2
```

**ECR expiry fix** — a CronJob that refreshes the Secret every 8 hours:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata: {name: ecr-token-refresh, namespace: shop-dev}
spec:
  schedule: "0 */8 * * *"
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          serviceAccountName: ecr-refresher
          containers:
            - name: refresh
              image: amazon/aws-cli:2.17.0
              command: ["/bin/sh","-c"]
              args:
                - |
                  TOKEN=$(aws ecr get-login-password --region ap-south-1)
                  kubectl create secret docker-registry ecr-cred \
                    --docker-server=$ECR_HOST --docker-username=AWS --docker-password="$TOKEN" \
                    -n shop-dev --dry-run=client -o yaml | kubectl apply -f -
```

Better: use **IRSA / Workload Identity** so Pods assume an IAM role directly and no image-pull Secret is needed at all.

</details>

---

### Task 3.3 — Make a config change force a rollout automatically

Without Helm, without Kustomize generators, without a third-party reloader.

<details>
<summary>Show answer</summary>

Three approaches, from crude to clean.

**Approach 1 — checksum annotation in a shell script:**

```bash
#!/usr/bin/env bash
# deploy-with-config.sh
set -euo pipefail

HASH=$(kubectl get cm shop-config -n shop-dev -o json | jq -r '.data' | sha256sum | cut -c1-16)

kubectl patch deployment shop -n shop-dev --type=merge -p "
spec:
  template:
    metadata:
      annotations:
        config-hash: \"$HASH\"
"
kubectl rollout status deployment/shop -n shop-dev
```

Because the annotation is part of the **Pod template**, changing it changes the template hash → new ReplicaSet → rolling update. That's the whole trick, and it's exactly what Helm's `checksum/config` does.

**Approach 2 — version the ConfigMap name:**

```bash
VERSION=v1.4.3
kubectl create configmap shop-config-$VERSION --from-literal=LOG_LEVEL=info \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl set env deployment/shop -n shop-dev --from=configmap/shop-config-$VERSION
kubectl set volume deployment/shop -n shop-dev --name=nginx-conf \
  --mount-path=/etc/nginx --sub-path=nginx.conf --source=configmap/shop-config-$VERSION
kubectl rollout status deployment/shop -n shop-dev
```

Explicit, auditable, and rollback is just pointing at the previous version. Old ConfigMaps can be garbage-collected by a CronJob.

**Approach 3 — just restart (perfectly fine):**

```bash
kubectl patch cm shop-config -n shop-dev --type=merge -p '{"data":{"LOG_LEVEL":"warn"}}'
kubectl rollout restart deployment/shop -n shop-dev
kubectl rollout status deployment/shop -n shop-dev
```

Wrap it so it can't be forgotten:

```bash
kconfig() {   # kconfig <cm-name> <deployment> <namespace>
  kubectl apply -f "$1"
  kubectl rollout restart "deploy/$2" -n "${3:-default}"
  kubectl rollout status  "deploy/$2" -n "${3:-default}"
}
```

**What NOT to do:** `kubectl exec ... -- sed -i` inside the Pod. It works for 30 seconds and then the Pod is replaced and your change evaporates — and nobody knows why prod is misbehaving.

</details>

---

### Task 3.4 — Encrypt Secrets at rest and verify it

Prove that Secret data is (or isn't) readable directly from etcd.

<details>
<summary>Show answer</summary>

**First, check whether your cluster encrypts Secrets.** On a kubeadm cluster:

```bash
kubectl -n kube-system get pod -l component=kube-apiserver -o yaml | grep -i encryption-provider-config
# if nothing shows → Secrets are stored as plain base64 in etcd
```

**Enable encryption** — `/etc/kubernetes/enc.yaml` on each control-plane node:

```yaml
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources: ["secrets"]
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: <base64-encoded-32-byte-key>   # openssl rand 32 | base64
      - identity: {}                                  # fallback: allows reading old data
```

Generate the key:

```bash
openssl rand 32 | base64
```

Add the flag to the API server static pod manifest (`/etc/kubernetes/manifests/kube-apiserver.yaml`):

```yaml
spec:
  containers:
    - command:
        - kube-apiserver
        - --encryption-provider-config=/etc/kubernetes/enc.yaml
      volumeMounts:
        - {name: k8s-certs, mountPath: /etc/kubernetes/pki, readOnly: true}
        - {name: enc-config, mountPath: /etc/kubernetes/enc.yaml, readOnly: true}
  volumes:
    - name: enc-config
      hostPath: {path: /etc/kubernetes/enc.yaml, type: File}
```

The kubelet restarts the API server automatically. Then **re-encrypt all existing Secrets**:

```bash
kubectl get secrets --all-namespaces -o json \
  | kubectl replace -f -        # forces a rewrite through the encrypting API server
```

**Verify from etcd directly** (on a control-plane node):

```bash
# unencrypted cluster:
ETCDCTL_API=3 etcdctl get /registry/secrets/default/db-creds \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  | strings | grep -i password
# → you can READ it. That's the problem.

# encrypted cluster: same command returns k8s:enc:aescbc:v1:key1:<binary>
```

**Verify rotation works:**

```bash
kubectl get secrets -A -o json | jq -r '.items[].metadata.name' | head
```

> 🔑 **On EKS/GKE/AKS this is a managed setting** (EKS: "secrets encryption" at cluster creation, cannot be added later; GKE: `--enable-secret-encryption` / application-layer secrets encryption; AKS: `--enable-encryption-at-host` + KMS). On kind/minikube it's off by default and rarely worth enabling for learning — but you should know it exists and how to check.
>
> **The stronger answer for production isn't etcd encryption — it's not putting long-lived secrets in the cluster at all.** Use Vault with short-lived dynamic credentials, or cloud secret managers with External Secrets Operator + automatic rotation.

</details>

---

### Task 3.5 — Manage per-environment config cleanly

Same app, three environments, different config. No copy-paste YAML.

<details>
<summary>Show answer</summary>

Kustomize overlays — the standard answer.

```
app/
├── base/
│   ├── kustomization.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   └── config/
│       └── app.conf
└── overlays/
    ├── dev/
    │   ├── kustomization.yaml
    │   └── .env.dev
    ├── staging/
    │   ├── kustomization.yaml
    │   └── .env.staging
    └── prod/
        ├── kustomization.yaml
        ├── .env.prod            # ← gitignored; sourced from your secret manager in CI
        └── hpa.yaml
```

`base/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources: [deployment.yaml, service.yaml]
commonLabels: {app.kubernetes.io/name: shop}
images:
  - {name: shop, newTag: "1.0.0"}
configMapGenerator:
  - name: shop-config
    files: [config/app.conf]
    literals: [LOG_LEVEL=info]
```

`overlays/dev/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: shop-dev
resources: [../../base]
namePrefix: dev-
replicas: [{name: shop, count: 1}]
images: [{name: shop, newName: ghcr.io/3558bhk/shop, newTag: "1.4.2-rc1"}]
configMapGenerator:
  - name: shop-config
    behavior: merge                  # ← merge into the base generator
    envs: [.env.dev]
    literals: [LOG_LEVEL=debug]
secretGenerator:
  - name: db-creds
    envs: [.env.dev]
```

`overlays/prod/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: shop-prod
resources: [../../base, hpa.yaml]
namePrefix: prod-
replicas: [{name: shop, count: 6}]
images: [{name: shop, newName: ghcr.io/3558bhk/shop, newTag: "1.4.2"}]
configMapGenerator:
  - name: shop-config
    behavior: merge
    envs: [.env.prod]
    literals: [LOG_LEVEL=warn]
    options:
      disableNameSuffixHash: false    # keep hashing → auto rollout
secretGenerator:
  - name: db-creds
    envs: [.env.prod]
patches:
  - target: {kind: Deployment, name: shop}
    patch: |-
      - op: replace
        path: /spec/template/spec/containers/0/resources/limits/memory
        value: 1Gi
      - op: add
        path: /spec/template/spec/affinity
        value:
          podAntiAffinity:
            requiredDuringSchedulingIgnoredDuringExecution:
              - labelSelector: {matchLabels: {app.kubernetes.io/name: shop}}
                topologyKey: kubernetes.io/hostname
```

Workflow:

```bash
kubectl kustomize overlays/dev        # render and READ it
kubectl diff -k overlays/dev          # what would change
kubectl apply -k overlays/dev
kubectl apply -k overlays/prod
```

**`.env.prod` must never be in Git.** In CI, generate it from your secret manager:

```bash
# GitHub Actions example
aws secretsmanager get-secret-value --secret-id prod/shop --query SecretString --output text \
  | jq -r 'to_entries[] | "\(.key)=\(.value)"' > overlays/prod/.env.prod
kubectl apply -k overlays/prod
shred -u overlays/prod/.env.prod
```

Or skip Secrets-in-Kustomize entirely and use **External Secrets Operator**:

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata: {name: db-creds, namespace: shop-prod}
spec:
  refreshInterval: 1h
  secretStoreRef: {name: aws-secrets-manager, kind: ClusterSecretStore}
  target: {name: db-creds, creationPolicy: Owner}
  data:
    - secretKey: password
      remoteRef: {key: prod/shop/db, property: password}
    - secretKey: username
      remoteRef: {key: prod/shop/db, property: username}
```

Now Git holds a *reference*, not a *value*. Rotation happens in the secret store and propagates automatically.

</details>

---

## 3.11 Checklist

- [ ] Create a ConfigMap from literals, a file, a directory, and an env-file
- [ ] Consume config as a single env var, as `envFrom`, and as mounted files
- [ ] Explain exactly which consumption methods auto-update and which don't (and why `subPath` is special)
- [ ] Explain the `..data` symlink swap that makes ConfigMap volume updates atomic
- [ ] Create all five Secret types and decode them from the CLI
- [ ] Use `stringData` instead of hand-base64-ing
- [ ] Use the `*_FILE` convention with an official image
- [ ] Argue why mounted Secrets beat env-var Secrets
- [ ] Explain what `immutable: true` buys you
- [ ] Diagnose `CreateContainerConfigError` in under 30 seconds
- [ ] Explain why base64 is not encryption, and name three real protections
- [ ] Build per-environment config with Kustomize overlays without duplicating manifests

**Next → [`07-PROJECT-4-jobs-cronjobs-cli.md`](07-PROJECT-4-jobs-cronjobs-cli.md)** — Jobs, CronJobs, init containers and one-shot tasks.

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish%20Kumar%20Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn → <https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260>
🐙 GitHub → <https://github.com/3558Bhk>

*Built for engineers who learn by breaking things on purpose.*

</div>
