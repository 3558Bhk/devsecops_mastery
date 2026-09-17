# 🥈 Project 2 — Deployments, Services & Zero-Downtime Rollouts

> **Time:** 2 hours · **Prereq:** [Project 1](04-PROJECT-1-first-pod.md)
>
> **What you'll learn:** the Deployment → ReplicaSet → Pod ownership chain, how a rolling update actually proceeds step by step, the difference between the four Service types, and how to **prove** a deploy causes zero dropped requests. Plus: a deliberate broken rollout and a rollback.
>
> **This is the single most important project in the path.** Deployments + Services are 70% of daily Kubernetes work.

---

## 2.1 The 60-second theory

```
Deployment   "I want 3 replicas of template v2, updated gradually"
    │  owns
    ▼
ReplicaSet   "I want exactly 3 Pods matching this selector"     ← one per revision
    │  owns
    ▼
Pod, Pod, Pod

Service      "Give me a stable IP + DNS name that load-balances
              to whichever Pods currently match this selector"
```

Three things a Deployment gives you that a bare Pod doesn't:

1. **Self-healing** — delete a Pod, a new one appears in seconds.
2. **Scaling** — `kubectl scale`, or automatically with an HPA.
3. **Rolling updates + rollback** — change the image, Kubernetes swaps Pods gradually, and `rollout undo` undoes it.

A Service exists because **Pod IPs are ephemeral**. Every reschedule means a new IP. The Service is the stable address.

---

## 2.2 Step 1 — A Deployment, imperatively

```bash
mkdir -p ~/k8s-learn/p2 && cd ~/k8s-learn/p2

kubectl create deployment web --image=nginx:1.29-alpine --replicas=3
kubectl get deployment web
kubectl get rs
kubectl get pods -l app=web -o wide
```

```
NAME   READY   UP-TO-DATE   AVAILABLE   AGE
web    3/3     3            3           30s

NAME              DESIRED   CURRENT   READY   AGE
web-6d4f7c8b9d    3         3         3       30s

NAME                        READY   STATUS    IP            NODE
web-6d4f7c8b9d-abcde        1/1     Running   10.244.1.7    learn-worker
web-6d4f7c8b9d-fghij        1/1     Running   10.244.2.11   learn-worker2
web-6d4f7c8b9d-klmno        1/1     Running   10.244.1.8    learn-worker
```

**Read the naming.** `web-6d4f7c8b9d-abcde` = `<deployment>-<replicaset-hash>-<pod-hash>`. The middle part changes on every template change; that's how you can see which revision a Pod belongs to.

Confirm the ownership chain:

```bash
kubectl get pod -l app=web -o jsonpath='{.items[0].metadata.ownerReferences[0].kind}/{.items[0].metadata.ownerReferences[0].name}'; echo
# ReplicaSet/web-6d4f7c8b9d
kubectl get rs web-6d4f7c8b9d -o jsonpath='{.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}'; echo
# Deployment/web
kubectl tree deploy web            # if you installed krew's `tree` plugin — beautiful
```

### Self-healing, live

```bash
kubectl get pods -l app=web -w &      # watch in the background
WATCH=$!
kubectl delete pod -l app=web --field-selector metadata.name=$(kubectl get pod -l app=web -o jsonpath='{.items[0].metadata.name}')
sleep 10
kill $WATCH
```

A new Pod with a **new name** appeared within ~2 seconds, and the ReplicaSet count never went below 3 for long. Now do it to all of them:

```bash
kubectl delete pods -l app=web
kubectl get pods -l app=web -w        # three new ones come up
```

> 🔑 This is the reconciliation loop. The ReplicaSet controller sees `actual(0) != desired(3)` and creates three Pods. It doesn't care *why* they vanished.

---

## 2.3 Step 2 — The same thing in YAML (what production looks like)

`deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  labels:
    app: web
    app.kubernetes.io/name: web
    app.kubernetes.io/part-of: shop
spec:
  replicas: 3
  revisionHistoryLimit: 5            # keep 5 old ReplicaSets for rollback
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1                    # at most 1 EXTRA pod during the update (3→4)
      maxUnavailable: 0              # ⭐ never fewer than 3 available = zero downtime
  selector:
    matchLabels:
      app: web                       # ⚠️ IMMUTABLE after creation
  template:
    metadata:
      labels:
        app: web                     # ⚠️ must satisfy spec.selector
        version: v1
      annotations:
        prometheus.io/scrape: "true"
    spec:
      terminationGracePeriodSeconds: 40
      containers:
        - name: web
          image: nginx:1.29-alpine
          imagePullPolicy: IfNotPresent
          ports:
            - {name: http, containerPort: 80}
          resources:
            requests: {cpu: 50m,  memory: 64Mi}
            limits:   {cpu: 250m, memory: 128Mi}
          readinessProbe:
            httpGet: {path: /, port: http}
            initialDelaySeconds: 2
            periodSeconds: 5
            failureThreshold: 3
            timeoutSeconds: 2
          livenessProbe:
            httpGet: {path: /, port: http}
            initialDelaySeconds: 10
            periodSeconds: 20
            failureThreshold: 3
          lifecycle:
            preStop:
              exec: {command: ["/bin/sh", "-c", "sleep 5"]}   # drain before dying (§9.7 guide)
```

```bash
kubectl delete deployment web                       # remove the imperative one
kubectl apply -f deployment.yaml
kubectl rollout status deployment/web               # blocks until complete — USE THIS IN CI
kubectl get deploy,rs,pods -l app=web
```

`kubectl rollout status` output:

```
Waiting for deployment "web" rollout to finish: 0 of 3 updated replicas are available...
deployment "web" successfully rolled out
```

### What `kubectl describe deployment` tells you

```bash
kubectl describe deployment web
```

```
Name:                   web
Namespace:              default
CreationTimestamp:      ...
Labels:                 app=web
Selector:               app=web
Replicas:               3 desired | 3 updated | 3 total | 3 available | 0 unavailable
StrategyType:           RollingUpdate
MinReadySeconds:        0
RollingUpdateStrategy:  0 max unavailable, 1 max surge
Pod Template:
  Labels:  app=web
           version=v1
  Containers:
   web:
    Image:      nginx:1.29-alpine
    Port:       80/TCP
    Limits:     cpu: 250m  memory: 128Mi
    Requests:   cpu: 50m   memory: 64Mi
    Liveness:   http-get http://:http/ delay=10s timeout=2s period=20s #success=1 #failure=3
    Readiness:  http-get http://:http/ delay=2s timeout=2s period=5s #success=1 #failure=3
Conditions:
  Type           Status  Reason
  ----           ------  ------
  Progressing    True    NewReplicaSetAvailable
  Available      True    MinimumReplicasAvailable
OldReplicaSets:  <none>
NewReplicaSet:   web-6d4f7c8b9d (3/3 replicas created)
Events:
  Type    Reason             Age   From                   Message
  Normal  ScalingReplicaSet  60s   deployment-controller  Scaled up replica set web-6d4f7c8b9d to 3
```

`Conditions` is where you look first: `Available=True` + `Progressing=True` = healthy.

---

## 2.4 Step 3 — Expose it with a Service

`service.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: web
  labels: {app: web}
spec:
  type: ClusterIP                 # default; internal only
  selector:
    app: web                      # ← matches POD labels, not Deployment labels
  ports:
    - name: http
      port: 80                    # what clients dial
      targetPort: http            # the container's port (name is safer than number)
      protocol: TCP
```

```bash
kubectl apply -f service.yaml
kubectl get svc web
```

```
NAME   TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)   AGE
web    ClusterIP   10.96.142.31   <none>        80/TCP    5s
```

**Prove the Service finds the Pods:**

```bash
kubectl describe svc web | grep -i endpoints
# Endpoints:  10.244.1.9:80,10.244.2.12:80,10.244.1.10:80

kubectl get endpointslices -l kubernetes.io/service-name=web
kubectl get endpointslices -l kubernetes.io/service-name=web \
  -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]} ready={.conditions.ready}{"\n"}{end}'
```

> 🔑 **If Endpoints is empty, your selector doesn't match any *Ready* Pod.** That is the #1 Kubernetes networking bug. Compare:
> ```bash
> kubectl get svc web -o jsonpath='{.spec.selector}' ; echo
> kubectl get pods --show-labels
> ```

**Test it from inside the cluster:**

```bash
kubectl run client --rm -it --image=nicolaka/netshoot --restart=Never -- bash
```

```bash
# inside the debug pod:
dig +short web                       # → 10.96.142.31  (the ClusterIP)
dig +short web.default.svc.cluster.local
curl -s http://web/ | grep -i title
for i in $(seq 1 10); do curl -s http://web/ | grep -o 'nginx'; done
nc -zv web 80
exit
```

**Test from your laptop:**

```bash
kubectl port-forward svc/web 8080:80 &
sleep 2
curl -s localhost:8080/ | grep -i title
kill %1
```

### The four Service types, side by side

Make a NodePort version and see the difference:

```bash
kubectl patch svc web -p '{"spec":{"type":"NodePort"}}'
kubectl get svc web
```

```
NAME   TYPE       CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE
web    NodePort   10.96.142.31   <none>        80:31234/TCP   5m
```

```bash
# from your laptop (kind/minikube):
NODE_IP=$(kubectl get node -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
curl -s http://$NODE_IP:31234/ | grep -i title

# minikube users:
minikube service web --url

# kind users: NodePort isn't reachable unless you added extraPortMappings for that range
#   → use port-forward, or map 30000-32767 in kind-config.yaml
```

| Type | Who can reach it | `EXTERNAL-IP` shows |
|---|---|---|
| `ClusterIP` | Only inside the cluster | `<none>` |
| `NodePort` | Anyone who can reach a node IP, on 30000–32767 | `<none>` (still no external IP!) |
| `LoadBalancer` | The internet (via a cloud LB) | a real public IP — `<pending>` locally |
| `ExternalName` | It's just a CNAME to something external | the DNS name |
| headless (`clusterIP: None`) | DNS returns **Pod IPs**, no VIP | `None` |

Try LoadBalancer and see it hang (this is *expected* without a cloud provider):

```bash
kubectl patch svc web -p '{"spec":{"type":"LoadBalancer"}}'
kubectl get svc web -w
# EXTERNAL-IP: <pending> forever  ← no cloud-controller-manager locally
kubectl patch svc web -p '{"spec":{"type":"ClusterIP"}}'    # put it back
```

On minikube, `minikube tunnel` (in a separate terminal) makes LoadBalancer work. On kind, use an Ingress controller ([Project 6](09-PROJECT-6-ingress-tls.md)).

### Headless Service — when you need Pod IPs

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Service
metadata: {name: web-headless}
spec:
  clusterIP: None
  selector: {app: web}
  ports: [{name: http, port: 80}]
EOF

kubectl run client --rm -it --image=nicolaka/netshoot --restart=Never -- \
  dig +short web-headless.default.svc.cluster.local
# 10.244.1.9
# 10.244.2.12
# 10.244.1.10      ← all three POD IPs, no virtual IP
```

Used for StatefulSets and client-side load balancing (gRPC, Kafka clients, Cassandra).

---

## 2.5 Step 4 — Scale it

```bash
kubectl scale deployment/web --replicas=6
kubectl get pods -l app=web -w                 # three new Pods appear

kubectl get endpointslices -l kubernetes.io/service-name=web \
  -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]}{"\n"}{end}' | wc -l   # 6

kubectl scale deployment/web --replicas=0      # everything gone, Service still exists
kubectl scale deployment/web --replicas=3
```

Notice: scaling to 0 then back up is a **complete Pod replacement** — new names, new IPs. The Service ClusterIP never changes. That's the point.

Also patch the manifest so Git stays truthful:

```bash
kubectl patch deployment web --type=merge -p '{"spec":{"replicas":5}}'
kubectl get deploy web -o jsonpath='{.spec.replicas}'; echo
```

> ⚠️ **`kubectl scale` and `kubectl patch` change the cluster but NOT your YAML file.** In GitOps the cluster change gets reverted within minutes. Always mirror manual changes into Git.

---

## 2.6 Step 5 — The rolling update, watched frame by frame

First, build something you can *see* change. We'll use nginx with a version marker via a config file — but the simplest visible trick is to serve the Pod's own name.

`app/` — a tiny app that prints its hostname and version:

```bash
mkdir -p app && cd app
cat > index.html <<'EOF'
<!doctype html><meta charset=utf-8>
<title>v1</title>
<h1 style="font:700 3rem system-ui">VERSION 1</h1>
EOF
cat > Dockerfile <<'EOF'
FROM nginx:1.29-alpine
COPY index.html /usr/share/nginx/html/index.html
EOF
docker build -t web:v1 .
docker tag web:v1 localhost:5001/web:v1 2>/dev/null || true
cd ..
```

```bash
# put the image where the cluster can see it
kind load docker-image web:v1 --name learn       # kind
# eval $(minikube docker-env) && docker build -t web:v1 app/   # minikube (build INSIDE)
# minikube image load web:v1                     # minikube alternative
```

Update the Deployment to use it (and set `imagePullPolicy: Never` for local images):

```bash
kubectl patch deployment web --type=json -p='[
  {"op":"replace","path":"/spec/template/spec/containers/0/image","value":"web:v1"},
  {"op":"replace","path":"/spec/template/spec/containers/0/imagePullPolicy","value":"IfNotPresent"}
]'
kubectl rollout status deployment/web
```

Now make v2:

```bash
cd app
cat > index.html <<'EOF'
<!doctype html><meta charset=utf-8>
<title>v2</title>
<h1 style="font:700 3rem system-ui">VERSION 2 🎉</h1>
EOF
docker build -t web:v2 .
kind load docker-image web:v2 --name learn
cd ..
```

**Open a third terminal and start hammering the app** — this is how we'll *prove* zero downtime:

```bash
kubectl port-forward svc/web 8080:80 &
sleep 2
# log every response with a timestamp; count failures
( while true; do
    ts=$(date +%H:%M:%S.%N | cut -c1-12)
    body=$(curl -s -m 2 localhost:8080/ | grep -o 'VERSION [0-9]' || echo "❌ FAIL")
    echo "$ts $body"
    sleep 0.2
  done ) | tee rollout.log
```

Now, in your main terminal, roll out v2:

```bash
kubectl set image deployment/web web=web:v2
kubectl rollout status deployment/web
```

Watch `rollout.log`. You should see a smooth `VERSION 1 … VERSION 2` transition with **zero `❌ FAIL` lines**. Also watch the Pods in a fourth terminal:

```bash
kubectl get pods -l app=web -w
```

```
web-aaa-11111   1/1   Running         0   5m     ← v1
web-aaa-22222   1/1   Running         0   5m
web-aaa-33333   1/1   Running         0   5m
web-bbb-44444   0/1   Pending         0   0s     ← v2 starts (maxSurge=1 → 4 pods)
web-bbb-44444   0/1   ContainerCreating 0  0s
web-bbb-44444   0/1   Running         0   1s
web-bbb-44444   1/1   Running         0   3s     ← readiness passed → joins Service
web-aaa-11111   1/1   Terminating     0   5m     ← only NOW does an old pod die
web-bbb-55555   0/1   Pending         0   0s
...
```

**That's the algorithm** (`maxSurge: 1`, `maxUnavailable: 0`, 3 replicas):

| Step | old RS | new RS | available |
|---|---|---|---|
| 0 | 3 | 0 | 3 |
| 1 | 3 | 1 (starting) | 3 |
| 2 | 3 | 1 (ready) | **4** ← surge |
| 3 | 2 | 1 | 3 |
| 4 | 2 | 2 | 3→4 |
| … | … | … | never below 3 |
| end | 0 | 3 | 3 |

`available` never drops below `replicas` because `maxUnavailable: 0`.

```bash
grep -c '❌ FAIL' rollout.log        # should be 0
kill %1
```

### Now break it: no readiness probe

This is the experiment that makes the concept permanent.

```bash
kubectl patch deployment web --type=json \
  -p='[{"op":"remove","path":"/spec/template/spec/containers/0/readinessProbe"}]'
kubectl rollout status deployment/web
```

Restart the load generator, then roll out v1 again:

```bash
kubectl port-forward svc/web 8080:80 & sleep 2
( while true; do echo "$(date +%H:%M:%S) $(curl -s -m 2 localhost:8080/ | grep -o 'VERSION [0-9]' || echo ❌FAIL)"; sleep 0.15; done ) | tee rollout-noprobe.log &
LOAD=$!

kubectl set image deployment/web web=web:v1
kubectl rollout status deployment/web
sleep 3
kill $LOAD %1 2>/dev/null

grep -c '❌ FAIL' rollout-noprobe.log
```

You'll likely see failures now. **Why:** without a readiness probe, Kubernetes marks a Pod `Ready` the moment the container *process* starts — before nginx has bound port 80. The Pod is added to the Service's endpoints immediately, gets traffic, and returns `connection refused`. Meanwhile an old healthy Pod was already terminated.

> 🔑 **A rolling update is only zero-downtime if the readiness probe is correct.** Everything else is theatre. This is the most common cause of "our deploys drop a few requests".

Put the probe back:

```bash
kubectl apply -f deployment.yaml
kubectl rollout status deployment/web
```

---

## 2.7 Step 6 — Rollout history and rollback

```bash
kubectl rollout history deployment/web
```

```
deployment.apps/web
REVISION  CHANGE-CAUSE
1         <none>
2         <none>
3         <none>
```

`CHANGE-CAUSE` is empty because nobody annotated it. Fix that habit:

```bash
kubectl annotate deployment/web kubernetes.io/change-cause="bump to web:v2 (feature X)" --overwrite
kubectl rollout history deployment/web
```

Inspect a specific revision:

```bash
kubectl rollout history deployment/web --revision=2
```

```
deployment.apps/web with revision #2
Pod Template:
  Labels:       app=web
                pod-template-hash=6d4f7c8b9d
                version=v1
  Annotations:  prometheus.io/scrape: true
  Containers:
   web:
    Image:      web:v2
    ...
```

**Roll back:**

```bash
kubectl rollout undo deployment/web                    # → previous revision
kubectl rollout status deployment/web
kubectl get pods -l app=web -o jsonpath='{.items[*].spec.containers[0].image}'; echo
```

**Roll back to a specific revision:**

```bash
kubectl rollout history deployment/web
kubectl rollout undo deployment/web --to-revision=1
kubectl rollout status deployment/web
```

> 🔑 Rollback works by **re-using an old ReplicaSet** — it scales the old RS back up and the new one down. That's why `revisionHistoryLimit` matters: if you set it to 1, there's nothing to roll back to. Default is 10.

Other rollout controls:

```bash
kubectl rollout restart deployment/web        # recycle all Pods without changing the spec
                                             # (great after a ConfigMap change)
kubectl rollout pause deployment/web          # batch several changes into one rollout
kubectl set image deployment/web web=web:v2
kubectl set resources deployment/web -c web --limits=cpu=300m,memory=256Mi
kubectl rollout resume deployment/web         # ← one single rollout for all the above
```

---

## 2.8 Step 7 — A broken rollout, and how Kubernetes protects you

Deliberately deploy a bad image:

```bash
kubectl set image deployment/web web=web:v999-does-not-exist
kubectl rollout status deployment/web --timeout=45s
```

```
Waiting for deployment "web" rollout to finish: 1 out of 3 new replicas have been updated...
Waiting for deployment "web" rollout to finish: 1 out of 3 new replicas have been updated...
error: timed out waiting for the condition
```

```bash
kubectl get pods -l app=web -o wide
```

```
web-OLD-111   1/1   Running            0   10m     ← still serving!
web-OLD-222   1/1   Running            0   10m
web-OLD-333   1/1   Running            0   10m
web-NEW-444   0/1   ImagePullBackOff   0   30s     ← stuck
```

**Notice what Kubernetes did:** it created ONE new Pod, that Pod never became Ready, so the rollout **stalled** — and the three old Pods kept serving traffic. Your app is still up. This is `maxUnavailable: 0` doing its job.

```bash
kubectl describe deployment web | grep -A5 Conditions
# Progressing   False   ProgressDeadlineExceeded   → after 600s (spec.progressDeadlineSeconds)
kubectl get events --field-selector type=Warning --sort-by=.lastTimestamp | tail -5

# fix:
kubectl rollout undo deployment/web
kubectl rollout status deployment/web
```

> 🔑 **`progressDeadlineSeconds` (default 600)** is how long a Deployment may be stuck before it's marked `Progressing=False`. CI pipelines should use `kubectl rollout status --timeout=300s` and fail the build, then `rollout undo`.

A subtler broken rollout: the image is fine but the app crashes.

```bash
kubectl set image deployment/web web=busybox:1.37
kubectl get pods -l app=web -w
```

```
web-NEW-xxx   0/1   CrashLoopBackOff   3   60s
```

busybox exits immediately (no long-running command), so readiness never passes, so the rollout stalls with the old Pods still serving. Same protection, different symptom.

```bash
kubectl rollout undo deployment/web && kubectl rollout status deployment/web
```

---

## 2.9 Step 8 — Graceful shutdown, proven

This is where the `preStop` sleep and SIGTERM handling pay off.

```bash
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: graceful}
spec:
  replicas: 2
  selector: {matchLabels: {app: graceful}}
  template:
    metadata: {labels: {app: graceful}}
    spec:
      terminationGracePeriodSeconds: 45
      containers:
        - name: app
          image: python:3.13-alpine
          command: ["python", "-c"]
          args:
            - |
              import http.server, signal, socket, sys, threading, time
              stop = False
              def bye(*a):
                  global stop
                  print("SIGTERM received — draining", flush=True)
                  stop = True
                  time.sleep(3)                      # finish in-flight work
                  print("drained, exiting 0", flush=True)
                  sys.exit(0)
              signal.signal(signal.SIGTERM, bye)
              class H(http.server.BaseHTTPRequestHandler):
                  def do_GET(self):
                      self.send_response(200); self.end_headers()
                      self.wfile.write(f"hello from {socket.gethostname()}\n".encode())
                  def log_message(self, *a): pass
              s = http.server.HTTPServer(("0.0.0.0", 8080), H)
              print("listening on 8080", flush=True)
              threading.Thread(target=s.serve_forever, daemon=True).start()
              while not stop: time.sleep(0.5)
          ports: [{containerPort: 8080, name: http}]
          readinessProbe: {httpGet: {path: /, port: 8080}, periodSeconds: 2}
          lifecycle:
            preStop: {exec: {command: ["/bin/sh","-c","sleep 8"]}}
EOF

kubectl rollout status deploy/graceful
kubectl get pods -l app=graceful
```

Now watch the shutdown sequence in one terminal while deleting a Pod in another:

```bash
# terminal A
POD=$(kubectl get pod -l app=graceful -o jsonpath='{.items[0].metadata.name}')
kubectl logs -f $POD
```

```bash
# terminal B
kubectl delete pod $POD
kubectl get pod $POD -o jsonpath='{.metadata.deletionTimestamp}{"\n"}{.metadata.deletionGracePeriodSeconds}{"\n"}'
```

Terminal A shows:

```
listening on 8080
SIGTERM received — draining        ← ~8s after delete (preStop sleep finished first)
drained, exiting 0
```

**The sequence:** delete → Pod enters `Terminating` → endpoints removed **and** `preStop` sleep runs (concurrently) → after 8 s, SIGTERM → app drains 3 s → exit 0 → Pod gone. Total ~11 s, well within the 45 s grace period. No SIGKILL.

Now remove the preStop and see the difference:

```bash
kubectl patch deploy graceful --type=json \
  -p='[{"op":"remove","path":"/spec/template/spec/containers/0/lifecycle"}]'
kubectl rollout status deploy/graceful
kubectl logs -f $(kubectl get pod -l app=graceful -o jsonpath='{.items[0].metadata.name}') &
kubectl delete pod $(kubectl get pod -l app=graceful -o jsonpath='{.items[0].metadata.name}')
```

SIGTERM arrives immediately, often *before* the endpoints have propagated — so a request in flight at that instant can fail. With a Service in front and a load generator running, you'd see the occasional `❌ FAIL`.

> 🔑 **The preStop sleep isn't a hack; it's the standard pattern.** It buys the kube-proxy/ingress-controller time to stop routing to a Pod that's about to die. 5–15 s is typical.

Clean up:

```bash
kubectl delete deploy graceful
```

---

## 2.10 Extra Tasks

### Task 2.1 — Convert a Docker Compose file to Kubernetes

Take a two-service compose file and get it running in the cluster.

`docker-compose.yaml`:

```yaml
services:
  api:
    image: nginx:1.29-alpine
    ports: ["8080:80"]
    environment:
      - LOG_LEVEL=debug
  worker:
    image: busybox:1.37
    command: ["sh","-c","while true; do echo working; sleep 5; done"]
    depends_on: [api]
```

Do it **by hand first**, then compare with Kompose.

<details>
<summary>Show answer</summary>

**By hand** — `k8s/api.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata: {name: api, labels: {app: api}}
spec:
  replicas: 2
  selector: {matchLabels: {app: api}}
  template:
    metadata: {labels: {app: api}}
    spec:
      containers:
        - name: api
          image: nginx:1.29-alpine
          ports: [{containerPort: 80, name: http}]
          env: [{name: LOG_LEVEL, value: debug}]
          resources: {requests: {cpu: 50m, memory: 64Mi}, limits: {cpu: 250m, memory: 128Mi}}
          readinessProbe: {httpGet: {path: /, port: http}, periodSeconds: 5}
---
apiVersion: v1
kind: Service
metadata: {name: api}
spec:
  selector: {app: api}
  ports: [{name: http, port: 8080, targetPort: http}]
```

`k8s/worker.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata: {name: worker, labels: {app: worker}}
spec:
  replicas: 1
  selector: {matchLabels: {app: worker}}
  template:
    metadata: {labels: {app: worker}}
    spec:
      containers:
        - name: worker
          image: busybox:1.37
          command: ["sh","-c","while true; do echo working; sleep 5; done"]
          resources: {requests: {cpu: 20m, memory: 16Mi}, limits: {cpu: 100m, memory: 32Mi}}
```

```bash
kubectl apply -f k8s/
kubectl get deploy,svc,pods
kubectl port-forward svc/api 8080:8080 & sleep 2 && curl -sI localhost:8080 && kill %1
```

**Then Kompose:**

```bash
brew install kompose          # or download from github.com/kubernetes/kompose/releases
kompose convert -f docker-compose.yaml --out k8s-generated/
ls k8s-generated/
kubectl diff -f k8s-generated/ || true
kubectl apply -f k8s-generated/ --dry-run=server
```

What Kompose does well: generates Deployments + Services + PVCs from volumes.
What it gets wrong (always review):
- `ports: ["8080:80"]` becomes a **LoadBalancer** Service on 8080 → change to ClusterIP + Ingress
- no resource requests/limits → add them
- no probes → add them
- `depends_on` is dropped (Kubernetes has no startup ordering for Deployments — use an init container or a readiness gate)
- `command:` in compose → `args:`/`command:` mapping is sometimes off
- no `imagePullPolicy`, no `securityContext`, no namespace

**Rule:** Kompose is a *starting point generator*, never a final answer.

</details>

---

### Task 2.2 — Prove traffic is actually load-balanced

Show that requests are distributed across all Pods, and that a Pod removed from readiness stops getting traffic.

<details>
<summary>Show answer</summary>

Make the app identify itself. Patch the Deployment to serve the hostname:

```bash
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: lb-demo}
spec:
  replicas: 3
  selector: {matchLabels: {app: lb-demo}}
  template:
    metadata: {labels: {app: lb-demo}}
    spec:
      containers:
        - name: web
          image: nginx:1.29-alpine
          ports: [{containerPort: 80}]
          readinessProbe:
            httpGet: {path: /, port: 80}
            periodSeconds: 3
          lifecycle:
            postStart:
              exec:
                command: ["/bin/sh","-c","hostname > /usr/share/nginx/html/index.html"]
EOF
kubectl rollout status deploy/lb-demo
```

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Service
metadata: {name: lb-demo}
spec:
  selector: {app: lb-demo}
  ports: [{port: 80}]
EOF
```

```bash
kubectl port-forward svc/lb-demo 8080:80 & sleep 2
for i in $(seq 1 30); do curl -s localhost:8080/; done | sort | uniq -c | sort -rn
kill %1
```

```
     11 lb-demo-7d9f8-x2k4j
     10 lb-demo-7d9f8-mn3p8
      9 lb-demo-7d9f8-qw7rt
```

⚠️ **Caveat:** `port-forward` pins you to ONE Pod, so this test can look skewed or entirely one-sided. The correct way is to test **from inside the cluster**:

```bash
kubectl run lb-test --rm -it --image=nicolaka/netshoot --restart=Never -- bash
# inside:
for i in $(seq 1 60); do curl -s http://lb-demo/; done | sort | uniq -c | sort -rn
```

Now prove readiness controls traffic:

```bash
POD=$(kubectl get pod -l app=lb-demo -o jsonpath='{.items[0].metadata.name}')
echo $POD

# make its readiness probe fail by breaking the file it serves
kubectl exec $POD -- rm /usr/share/nginx/html/index.html

kubectl get pods -l app=lb-demo -w
# lb-demo-xxxx   0/1   Running   0   5m     ← Running but NOT Ready

kubectl get endpointslices -l kubernetes.io/service-name=lb-demo \
  -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]} ready={.conditions.ready}{"\n"}{end}'
# 10.244.1.20 ready=false      ← removed from rotation
# 10.244.2.31 ready=true
# 10.244.1.21 ready=true
```

Run the in-cluster loop again → the broken Pod gets **zero** requests. It was never restarted (liveness still passes — the process is fine). That's the exact distinction between readiness and liveness.

```bash
kubectl delete pod $POD      # let it be replaced cleanly
kubectl delete deploy,svc lb-demo
```

</details>

---

### Task 2.3 — Canary deployment by ReplicaSet ratio

Ship v2 to ~20% of traffic without an Ingress or a service mesh.

<details>
<summary>Show answer</summary>

The trick: **two Deployments, one Service**, with a shared label. The Service's selector matches both, so traffic splits by Pod count.

```bash
# v1 — stable, 8 replicas
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: canary-stable, labels: {app: canary, track: stable}}
spec:
  replicas: 8
  selector: {matchLabels: {app: canary, track: stable}}
  template:
    metadata: {labels: {app: canary, track: stable}}
    spec:
      containers:
        - name: web
          image: nginx:1.29-alpine
          ports: [{containerPort: 80}]
          readinessProbe: {httpGet: {path: /, port: 80}, periodSeconds: 3}
          lifecycle: {postStart: {exec: {command: ["/bin/sh","-c","echo STABLE > /usr/share/nginx/html/index.html"]}}}
          resources: {requests: {cpu: 10m, memory: 16Mi}, limits: {cpu: 100m, memory: 64Mi}}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: canary-new, labels: {app: canary, track: canary}}
spec:
  replicas: 2                                   # 2 of 10 = 20%
  selector: {matchLabels: {app: canary, track: canary}}
  template:
    metadata: {labels: {app: canary, track: canary}}
    spec:
      containers:
        - name: web
          image: nginx:1.29-alpine
          ports: [{containerPort: 80}]
          readinessProbe: {httpGet: {path: /, port: 80}, periodSeconds: 3}
          lifecycle: {postStart: {exec: {command: ["/bin/sh","-c","echo CANARY > /usr/share/nginx/html/index.html"]}}}
          resources: {requests: {cpu: 10m, memory: 16Mi}, limits: {cpu: 100m, memory: 64Mi}}
---
apiVersion: v1
kind: Service
metadata: {name: canary}
spec:
  selector: {app: canary}        # ← NOTE: no `track` label → matches BOTH deployments
  ports: [{port: 80}]
EOF

kubectl rollout status deploy/canary-stable && kubectl rollout status deploy/canary-new
kubectl get endpointslices -l kubernetes.io/service-name=canary \
  -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]}{"\n"}{end}' | wc -l    # 10
```

Measure the split from inside the cluster:

```bash
kubectl run measure --rm -it --image=nicolaka/netshoot --restart=Never -- bash
# inside:
for i in $(seq 1 500); do curl -s http://canary/; done | sort | uniq -c
#    402 STABLE
#     98 CANARY      ≈ 20%
```

Promote: scale the canary up and stable down (or just update `canary-stable`'s image and delete `canary-new`).
Roll back instantly: `kubectl scale deploy/canary-new --replicas=0`.

**Limitations of this approach:**
- Split is by **Pod count**, not by percentage — with HPA on, the ratio drifts. Turn HPA off during a canary.
- Sessions are not sticky; a user can hit both versions.
- No header/cookie-based routing.

For real canaries use **Argo Rollouts**, **Flagger**, **Istio VirtualService weights**, or **Gateway API `backendRefs[].weight`** (see [Guide §12.5](01-KUBERNETES-GUIDE.md#125-gateway-api--the-ingress-successor)).

```bash
kubectl delete deploy canary-stable canary-new && kubectl delete svc canary
```

</details>

---

### Task 2.4 — Recreate strategy, and when you'd need it

Demonstrate the difference between `RollingUpdate` and `Recreate`, and explain the trade-off.

<details>
<summary>Show answer</summary>

```bash
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: recreate-demo}
spec:
  replicas: 3
  strategy:
    type: Recreate            # ← kill ALL old pods, THEN start new ones
  selector: {matchLabels: {app: recreate-demo}}
  template:
    metadata: {labels: {app: recreate-demo}}
    spec:
      containers:
        - name: web
          image: nginx:1.29-alpine
          ports: [{containerPort: 80}]
          readinessProbe: {httpGet: {path: /, port: 80}, periodSeconds: 2}
EOF
kubectl rollout status deploy/recreate-demo
```

Watch a change:

```bash
kubectl get pods -l app=recreate-demo -w &
W=$!
kubectl set image deploy/recreate-demo web=nginx:1.29-alpine   # same image; force a rollout instead:
kubectl rollout restart deploy/recreate-demo
sleep 30; kill $W
```

```
recreate-demo-aaa-111   1/1   Terminating   0   3m     ← ALL of them die first
recreate-demo-aaa-222   1/1   Terminating   0   3m
recreate-demo-aaa-333   1/1   Terminating   0   3m
                                                            ← gap: ZERO pods available
recreate-demo-bbb-444   0/1   Pending       0   0s
recreate-demo-bbb-444   1/1   Running       0   4s
...
```

There is a window with **no running Pods at all** — guaranteed downtime of several seconds. `kubectl rollout undo` also has downtime.

**When is `Recreate` actually correct?**
- The app cannot tolerate two versions running at once (schema-incompatible migrations, single-writer locks).
- Legacy apps with a hardcoded lock file or an in-process singleton.
- Something with `ReadWriteOncePod` storage that must be detached before the new Pod can attach.
- Dev/test environments where a few seconds of downtime is free.

**When is it a mistake?** Almost everywhere else. Prefer `RollingUpdate` with `maxUnavailable: 0`, or blue/green.

Also note: `strategy.type` is **immutable-ish** — you can change it, but changing *between* `RollingUpdate` and `Recreate` triggers a full replacement.

```bash
kubectl delete deploy recreate-demo
```

</details>

---

### Task 2.5 — Build a "deployment dashboard" one-liner set

You're on call and need a full picture of a namespace in 10 seconds. Write the commands.

<details>
<summary>Show answer</summary>

```bash
NS=prod

# 1. Everything at once
kubectl get deploy,rs,sts,ds,pods,svc,ingress,hpa,pdb,cm,secret,pvc -n $NS

# 2. Anything unhealthy?
kubectl get pods -n $NS --field-selector 'status.phase!=Running,status.phase!=Succeeded'
kubectl get pods -n $NS | grep -Ev '([0-9]+)/\1\s+Running' | grep -v Completed
kubectl get deploy -n $NS -o custom-columns=\
'NAME:.metadata.name,DESIRED:.spec.replicas,READY:.status.readyReplicas,AVAILABLE:.status.availableReplicas,IMAGE:.spec.template.spec.containers[0].image' \
  | awk 'NR==1 || $3 != $2'

# 3. Recent warnings
kubectl get events -n $NS --field-selector type=Warning --sort-by=.lastTimestamp | tail -20

# 4. Restart champions (crash loops)
kubectl get pods -n $NS --sort-by='.status.containerStatuses[0].restartCount' \
  -o custom-columns='NAME:.metadata.name,RESTARTS:.status.containerStatuses[0].restartCount,STATUS:.status.phase' | tail -10

# 5. Resource hogs
kubectl top pods -n $NS --sort-by=memory | head -10
kubectl top pods -n $NS --sort-by=cpu | head -10

# 6. Pods missing requests/limits (BestEffort = eviction bait)
kubectl get pods -n $NS -o json | jq -r '
  .items[] | select(.status.qosClass=="BestEffort") | .metadata.name'

# 7. Images running :latest (unpin = unreproducible deploys)
kubectl get pods -n $NS -o json | jq -r '
  .items[].spec.containers[] | select(.image|endswith(":latest")) | .image' | sort -u

# 8. Cluster-wide snapshot for a ticket
kubectl cluster-info dump --namespaces=$NS --output-directory=/tmp/dump-$NS-$(date +%s)

# 9. k9s — the real answer
k9s -n $NS
```

Wrap it as a function:

```bash
cat >> ~/.bashrc <<'EOF'
khealth() {
  local ns=${1:-default}
  echo "── Not running ──"; kubectl get pods -n $ns --field-selector 'status.phase!=Running,status.phase!=Succeeded' --no-headers
  echo "── Under-replicated deployments ──"
  kubectl get deploy -n $ns -o custom-columns='N:.metadata.name,WANT:.spec.replicas,READY:.status.readyReplicas' --no-headers | awk '$2!=$3'
  echo "── Recent warnings ──"; kubectl get events -n $ns --field-selector type=Warning --sort-by=.lastTimestamp --no-headers | tail -10
  echo "── Restarts ──"; kubectl get pods -n $ns --sort-by='.status.containerStatuses[0].restartCount' --no-headers | tail -5
}
EOF
source ~/.bashrc
khealth prod
```

</details>

---

## 2.11 Checklist

- [ ] Explain the Deployment → ReplicaSet → Pod chain and what each layer is responsible for
- [ ] Say why `spec.selector` is immutable and what happens if you try to change it
- [ ] Explain `maxSurge` and `maxUnavailable`, including why `maxUnavailable: 0` gives zero downtime
- [ ] Prove a rollout is zero-downtime with a load generator
- [ ] Explain why removing the readiness probe causes dropped requests
- [ ] Roll back to the previous revision, and to a specific revision number
- [ ] Choose between ClusterIP, NodePort, LoadBalancer, ExternalName and headless — with a reason
- [ ] Debug an empty `Endpoints` list
- [ ] Describe the graceful-termination sequence including where `preStop` fits
- [ ] Build a canary with two Deployments behind one Service

**Next → [`06-PROJECT-3-config-secrets.md`](06-PROJECT-3-config-secrets.md)** — ConfigMaps, Secrets, and why your config change didn't take effect.

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish%20Kumar%20Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn → <https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260>
🐙 GitHub → <https://github.com/3558Bhk>

*Built for engineers who learn by breaking things on purpose.*

</div>
