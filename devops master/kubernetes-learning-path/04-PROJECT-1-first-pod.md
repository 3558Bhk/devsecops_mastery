# 🥇 Project 1 — Your First Pod (and your first outage)

> **Time:** 90 minutes · **Prereq:** a working `kubectl` and a local cluster ([Guide §0](01-KUBERNETES-GUIDE.md#0--set-up-your-cluster-30-min))
>
> **What you'll learn:** what a Pod really is, the four commands you'll type 100× a day, how to read `describe` output, how Kubernetes restart policy works, and how to *deliberately* create and diagnose the four most common Pod failures.
>
> **Rule for this project:** type every command. Copy-pasting teaches your clipboard, not you.

---

## 1.1 The 60-second theory

A **Pod** is the smallest thing Kubernetes can schedule. It is one or more containers sharing:

- **one IP address** (so containers talk to each other on `localhost`)
- **one set of port numbers** (so two containers can't both use 8080)
- **optionally, volumes**

Kubernetes doesn't run containers — it tells a **kubelet** on some node to run them, via **containerd**. You never pick the node (usually); the **scheduler** does.

> 🔑 **A bare Pod has no keeper.** Delete it and it's gone. A Pod owned by a Deployment gets replaced instantly. That difference *is* Kubernetes.

---

## 1.2 Warm-up: confirm your cluster is alive

```bash
kubectl version --client --short 2>/dev/null || kubectl version --client
kubectl cluster-info
kubectl get nodes -o wide
kubectl get pods -A
```

You should see your node(s) `Ready` and a bunch of `kube-system` pods `Running`. If not → [Guide §0.3](01-KUBERNETES-GUIDE.md#03-verify-everything-works).

Learn these three flags now; you'll use them every single day:

```bash
kubectl get pods -o wide            # adds POD IP and NODE
kubectl get pods --show-labels
kubectl get pods -o yaml            # the full truth, including status
kubectl get pods -w                 # watch, live updates (Ctrl-C to stop)
```

---

## 1.3 Step 1 — Run a Pod imperatively (the fastest way)

```bash
kubectl run hello --image=nginx:1.29-alpine
```

That's it. Watch it:

```bash
kubectl get pods -w
```

```
NAME    READY   STATUS              RESTARTS   AGE
hello   0/1     Pending             0          0s
hello   0/1     Pending             0          0s
hello   0/1     ContainerCreating   0          0s
hello   1/1     Running             0          3s
```

**Read those four states.** They are the entire Pod birth sequence: scheduled → image pulled + volumes mounted → container started → readiness passed.

Now clean up and do it properly with YAML.

```bash
kubectl delete pod hello
```

> `kubectl run` creates a **Pod** by default (it used to create a Deployment in old versions — many stale tutorials are wrong about this). Add `--restart=Never` for a Pod that won't restart, or `--restart=OnFailure` for Job-like behaviour.

---

## 1.4 Step 2 — The same thing, declaratively

Create a working folder:

```bash
mkdir -p ~/k8s-learn/p1 && cd ~/k8s-learn/p1
```

`pod.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: hello
  labels:
    app: hello
    env: dev
    tier: frontend
  annotations:
    owner: "harish"
    purpose: "learning project 1"
spec:
  containers:
    - name: web
      image: nginx:1.29-alpine
      ports:
        - name: http
          containerPort: 80
```

```bash
kubectl apply -f pod.yaml
kubectl get pods -o wide --show-labels
```

Expected:

```
NAME    READY   STATUS    RESTARTS   AGE   IP           NODE          LABELS
hello   1/1     Running   0          45s   10.244.2.5   learn-worker  app=hello,env=dev,tier=frontend
```

**Now the important experiment.** Change something and re-apply:

```bash
sed -i 's/env: dev/env: staging/' pod.yaml
kubectl apply -f pod.yaml
kubectl get pod hello -o jsonpath='{.metadata.labels.env}'; echo
```

`apply` *updated* the object instead of failing. Try `kubectl create -f pod.yaml` and see it refuse:

```bash
kubectl create -f pod.yaml
# Error from server (AlreadyExists): error when creating "pod.yaml": pods "hello" already exists
```

> 🔑 **`apply` = idempotent, use it always. `create` = one-shot, use it to learn.**

### Labels are how you find things

```bash
kubectl get pods -l app=hello
kubectl get pods -l 'env in (dev,staging)'
kubectl get pods -l 'app=hello,tier=frontend'          # AND
kubectl get pods -l 'env!=prod'
kubectl get pods -l app                                 # key exists
kubectl get pods -l '!app'                              # key does NOT exist
kubectl label pod hello version=v1 --overwrite
kubectl annotate pod hello checked-by=harish
```

Label selectors are the backbone of Kubernetes. Services, Deployments, HPA, PDB and NetworkPolicy **all** find their Pods by label. Get comfortable with the syntax now.

---

## 1.5 Step 3 — The four daily commands

### `kubectl describe` — read the story

```bash
kubectl describe pod hello
```

Scroll the output. Know these sections:

| Section | What it tells you |
|---|---|
| `Name / Namespace / Node` | Where it landed |
| `Labels / Annotations` | Identity |
| `Status` | Pod phase (`Running`) |
| `IP / IPs / Controlled By` | Pod IP; `Controlled By` is empty for a bare Pod |
| `Containers: web:` | Image, port, **State**, **Last State**, mounts, **Limits/Requests**, **Liveness/Readiness**, Environment |
| `Conditions` | `PodScheduled`, `Initialized`, `ContainersReady`, `Ready` |
| `Volumes` | Including the auto-mounted ServiceAccount token |
| `QoS Class` | BestEffort / Burstable / Guaranteed |
| `Tolerations` | Defaults injected automatically |
| **`Events`** | ⭐ **The timeline. 80% of debugging happens here.** |

Events look like:

```
Events:
  Type    Reason     Age   From               Message
  ----    ------     ----  ----               -------
  Normal  Scheduled  2m    default-scheduler  Successfully assigned default/hello to learn-worker2
  Normal  Pulling    2m    kubelet            Pulling image "nginx:1.29-alpine"
  Normal  Pulled     2m    kubelet            Successfully pulled image ... in 1.2s
  Normal  Created    2m    kubelet            Created container: web
  Normal  Started    2m    kubelet            Started container web
```

Only look at events:

```bash
kubectl describe pod hello | sed -n '/Events:/,$p'
kubectl get events --field-selector involvedObject.name=hello
```

### `kubectl logs` — read the app

```bash
kubectl logs hello                        # stdout of the (only) container
kubectl logs hello -c web                 # explicit container
kubectl logs hello -f                     # follow
kubectl logs hello --tail=20              # last 20 lines
kubectl logs hello --timestamps
kubectl logs hello --since=5m
kubectl logs hello --previous             # the PREVIOUS (crashed) instance ⭐
```

`nginx:alpine` logs to stdout, so you'll see access lines. Generate some:

```bash
kubectl exec hello -- wget -qO- localhost/ > /dev/null
kubectl logs hello --tail=3
```

### `kubectl exec` — get inside

```bash
kubectl exec -it hello -- sh           # alpine has sh, NOT bash
```

Inside, explore:

```sh
hostname                 # = the pod name
ip addr                  # or: cat /proc/net/fib_trie | head
cat /etc/resolv.conf     # cluster DNS + search domains
nslookup kubernetes.default
ps aux                   # PID 1 is nginx
wget -qO- localhost/     # talk to yourself
exit
```

One-shot commands without a shell:

```bash
kubectl exec hello -- cat /etc/nginx/nginx.conf
kubectl exec hello -- nginx -v
kubectl exec hello -- ls -la /usr/share/nginx/html
```

> ⚠️ **Distroless/scratch images have no shell.** Then use an *ephemeral debug container*:
> ```bash
> kubectl debug -it hello --image=nicolaka/netshoot --target=web --share-processes
> ```

### `kubectl get -o` — see the machine's view

```bash
kubectl get pod hello -o yaml                     # everything
kubectl get pod hello -o json | jq '.status.phase'
kubectl get pod hello -o wide
kubectl get pod hello -o name                     # pod/hello
kubectl get pod hello -o jsonpath='{.status.podIP}'
kubectl get pod hello -o jsonpath='{range .status.conditions[*]}{.type}={.status}{"\n"}{end}'
kubectl get pod hello -o custom-columns='NAME:.metadata.name,IP:.status.podIP,NODE:.spec.nodeName,READY:.status.containerStatuses[0].ready'
kubectl get pods -o go-template='{{range .items}}{{.metadata.name}} {{.status.phase}}{{"\n"}}{{end}}'
kubectl get pod hello --show-managed-fields -o yaml   # usually hidden; shows field ownership
```

`jsonpath` + `custom-columns` are how you script Kubernetes. Learn them now.

---

## 1.6 Step 4 — Reach the app from your laptop

```bash
kubectl port-forward pod/hello 8080:80
```

Leave that running, open a **second terminal**:

```bash
curl -s http://localhost:8080/ | head -5
```

You should get nginx's welcome page. Stop the port-forward with `Ctrl-C`.

**Understand what just happened:** `port-forward` opens a TCP tunnel from your machine → API server → kubelet → the Pod. It is:

- ❌ not a load balancer (one tunnel to one Pod)
- ❌ not durable (dies with your terminal)
- ❌ not for production
- ✅ perfect for debugging

Also try the random-port form and the "no port specified" form:

```bash
kubectl port-forward pod/hello 8080            # both sides 8080 (fails here — nginx is on 80)
kubectl port-forward pod/hello :80             # random local port
kubectl port-forward pod/hello 8080:80 &       # background it (kill with %1)
```

---

## 1.7 Step 5 — Restart policy, live

Make a Pod that exits immediately:

`exit-pod.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: exiter
spec:
  restartPolicy: Never            # ← try changing this
  containers:
    - name: once
      image: busybox:1.37
      command: ["sh", "-c", "echo starting; sleep 3; echo done; exit 0"]
```

```bash
kubectl apply -f exit-pod.yaml
kubectl get pod exiter -w
```

With `restartPolicy: Never`:

```
exiter   0/1   Pending     0   0s
exiter   0/1   Running     0   1s
exiter   0/1   Completed   0   4s     ← stays Completed forever
```

```bash
kubectl logs exiter
kubectl get pod exiter -o jsonpath='{.status.phase}'; echo      # Succeeded
```

Now change it to `Always` (the default) and watch Kubernetes restart a container that keeps succeeding:

```bash
kubectl delete pod exiter
sed -i 's/restartPolicy: Never/restartPolicy: Always/' exit-pod.yaml
kubectl apply -f exit-pod.yaml
kubectl get pod exiter -w
```

```
exiter   0/1   Completed   1   5s
exiter   0/1   Running     2   15s
exiter   0/1   Completed   2   19s
exiter   0/1   Running     3   39s     ← RESTARTS keeps climbing
```

That's `CrashLoopBackOff` mechanics without a crash: **`Always` restarts on any exit, including 0**, with exponential backoff (10s → 20s → 40s → … → 5 min cap).

Try `OnFailure` with a failing command:

```bash
kubectl delete pod exiter
cat > exit-pod.yaml <<'EOF'
apiVersion: v1
kind: Pod
metadata: {name: exiter}
spec:
  restartPolicy: OnFailure
  containers:
    - name: once
      image: busybox:1.37
      command: ["sh", "-c", "echo boom; exit 1"]
EOF
kubectl apply -f exit-pod.yaml
kubectl get pod exiter -w
kubectl describe pod exiter | grep -A3 "Last State"
```

```
Last State:     Terminated
  Reason:       Error
  Exit Code:    1
```

> 🔑 **Exit codes are your fastest triage.**
> | Code | Meaning |
> |---|---|
> | 0 | Success (but `Always` still restarts it) |
> | 1 | Generic app error — read the logs |
> | 2 | Shell misuse / bad args |
> | 126 | Found but not executable → permission bit or wrong path |
> | 127 | Command not found → typo in `command:` |
> | 137 | 128+9 = SIGKILL → **OOMKilled** or grace period expired |
> | 139 | 128+11 = SIGSEGV → crash in native code |
> | 143 | 128+15 = SIGTERM → someone terminated it (normal on shutdown) |

---

## 1.8 Step 6 — Break it on purpose (the core of this project)

Create four broken Pods. For each: **guess the cause first, then verify with `describe` + `logs`.**

### Break #1 — a bad image

`broken-image.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata: {name: broken-image}
spec:
  containers:
    - name: app
      image: nginx:1.29-alpine-TYPO     # does not exist
```

```bash
kubectl apply -f broken-image.yaml
kubectl get pod broken-image -w
```

Expected: `ErrImagePull` → `ImagePullBackOff`.

```bash
kubectl describe pod broken-image | sed -n '/Events:/,$p'
```

```
Warning  Failed     ...  kubelet  Failed to pull image "nginx:1.29-alpine-TYPO":
  failed to resolve reference "docker.io/library/nginx:1.29-alpine-TYPO":
  docker.io/library/nginx:1.29-alpine-TYPO: not found
Warning  BackOff    ...  kubelet  Back-off pulling image "nginx:1.29-alpine-TYPO"
```

Notice: the Pod object **exists** and is `Pending`. Kubernetes doesn't roll back your `apply` — it keeps trying forever. That's the reconciliation loop.

Fix it live:

```bash
kubectl patch pod broken-image --type=json \
  -p='[{"op":"replace","path":"/spec/containers/0/image","value":"nginx:1.29-alpine"}]'
# → error! Pod container images are immutable-ish; you usually must delete + recreate
kubectl delete pod broken-image && sed -i 's/-TYPO//' broken-image.yaml && kubectl apply -f broken-image.yaml
```

> 🔑 **You cannot change most of a running Pod's spec.** Only `image` (per container), `activeDeadlineSeconds`, `tolerations` (additions only), and `terminationGracePeriodSeconds` are mutable. Everything else → delete and recreate. This is *why* Deployments exist.

### Break #2 — a bad command

`broken-cmd.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata: {name: broken-cmd}
spec:
  containers:
    - name: app
      image: busybox:1.37
      command: ["/bin/definitely-not-here"]
```

```bash
kubectl apply -f broken-cmd.yaml
sleep 20
kubectl get pod broken-cmd
kubectl describe pod broken-cmd | sed -n '/Events:/,$p'
```

```
Warning  BackOff  ...  kubelet  Back-off restarting failed container app in pod broken-cmd
```

Exit code 127 → command not found. `CrashLoopBackOff`.

### Break #3 — a crashing app

`crasher.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata: {name: crasher}
spec:
  containers:
    - name: app
      image: python:3.13-alpine
      command: ["python", "-c"]
      args:
        - |
          import sys, time
          print("starting up", flush=True)
          time.sleep(2)
          raise RuntimeError("database connection refused")
```

```bash
kubectl apply -f crasher.yaml
sleep 15
kubectl get pod crasher                     # CrashLoopBackOff
kubectl logs crasher                        # current (maybe empty)
kubectl logs crasher --previous             # ⭐ the crash
```

```
starting up
Traceback (most recent call last):
  File "<string>", line 5, in <module>
RuntimeError: database connection refused
```

**`--previous` is the single most valuable flag in `kubectl logs`.** Without it you often see nothing, because the current container hasn't crashed *yet*.

### Break #4 — missing config

`broken-config.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata: {name: broken-config}
spec:
  containers:
    - name: app
      image: busybox:1.37
      command: ["sh", "-c", "echo $SECRET_TOKEN; sleep 3600"]
      env:
        - name: SECRET_TOKEN
          valueFrom:
            secretKeyRef: {name: does-not-exist, key: token}
```

```bash
kubectl apply -f broken-config.yaml
kubectl get pod broken-config               # CreateContainerConfigError
kubectl describe pod broken-config | sed -n '/Events:/,$p'
```

```
Warning  Failed  ...  kubelet  Error: secret "does-not-exist" not found
```

Note the container never even starts — the kubelet can't build the environment. `kubectl logs` returns nothing.

### Clean up

```bash
kubectl delete pod broken-image broken-cmd crasher broken-config
# or, the blunt version:
kubectl delete pods -l '!app.kubernetes.io/name'   # careful — check with --dry-run first
kubectl delete pod --all                            # in the current namespace only
```

---

## 1.9 Step 7 — A real two-container Pod (sidecar)

`two-containers.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app-with-sidecar
  labels: {app: demo}
spec:
  restartPolicy: Never
  volumes:
    - name: logs
      emptyDir: {}
  initContainers:
    - name: wait-for-nothing          # init containers run to completion FIRST, in order
      image: busybox:1.37
      command: ["sh", "-c", "echo 'init: preparing'; sleep 2; echo 'init: done'"]
      volumeMounts:
        - {name: logs, mountPath: /var/log/app}
  containers:
    - name: app
      image: busybox:1.37
      command:
        - sh
        - -c
        - |
          i=0
          while true; do
            i=$((i+1))
            echo "$(date -u +%FT%TZ) INFO  request $i handled" >> /var/log/app/app.log
            echo "app: request $i"
            sleep 2
          done
      volumeMounts:
        - {name: logs, mountPath: /var/log/app}
    - name: log-tailer                # SIDECAR: shares the volume
      image: busybox:1.37
      command: ["sh", "-c", "touch /var/log/app/app.log; tail -f /var/log/app/app.log"]
      volumeMounts:
        - {name: logs, mountPath: /var/log/app}
```

```bash
kubectl apply -f two-containers.yaml
kubectl get pod app-with-sidecar -w
```

```
app-with-sidecar   0/2   Init:0/1            0   0s
app-with-sidecar   0/2   Init:Completed      0   3s
app-with-sidecar   0/2   PodInitializing     0   3s
app-with-sidecar   1/2   Running             0   4s
app-with-sidecar   2/2   Running             0   5s
```

**`READY 2/2`** — now you know what that number means.

```bash
kubectl logs app-with-sidecar                  # ❌ Error: a container name must be specified
kubectl logs app-with-sidecar -c app
kubectl logs app-with-sidecar -c log-tailer    # sees the file the app writes
kubectl logs app-with-sidecar --all-containers --prefix
kubectl exec -it app-with-sidecar -c app -- sh
kubectl exec app-with-sidecar -c log-tailer -- cat /var/log/app/app.log
```

Both containers see the same file because they share the `emptyDir` volume. **That's the whole sidecar pattern**: a second container doing auxiliary work with access to the same data.

> ⚠️ With `restartPolicy: Never`, if the *sidecar* dies the Pod never completes and stays `Running` with `READY 1/2`. This is the classic sidecar problem, solved by **native sidecars** (init container + `restartPolicy: Always`, stable since v1.33):
> ```yaml
> initContainers:
>   - name: log-tailer
>     image: busybox:1.37
>     restartPolicy: Always        # ← makes it a sidecar that starts first and stops last
>     command: ["sh","-c","tail -f /var/log/app/app.log"]
> ```

Clean up:

```bash
kubectl delete pod app-with-sidecar
```

---

## 1.10 Step 8 — Resource limits and an OOMKill, live

`limits.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata: {name: hog}
spec:
  restartPolicy: Never
  containers:
    - name: hog
      image: python:3.13-alpine
      resources:
        requests: {cpu: "100m", memory: "64Mi"}
        limits:   {cpu: "500m", memory: "64Mi"}     # ← deliberately tiny
      command: ["python", "-c"]
      args:
        - |
          data = []
          for i in range(100):
              data.append(b"x" * (10 * 1024 * 1024))   # 10 MiB per iteration
              print(f"allocated {(i+1)*10} MiB", flush=True)
          print("done — you should never see this")
```

```bash
kubectl apply -f limits.yaml
kubectl get pod hog -w
```

```
hog   0/1   Running     0   2s
hog   0/1   OOMKilled   0   6s
hog   0/1   Error       0   6s
```

```bash
kubectl describe pod hog | grep -A6 "Last State"
```

```
    Last State:     Terminated
      Reason:       OOMKilled
      Exit Code:    137
      Started:      ...
      Finished:     ...
```

```bash
kubectl logs hog          # shows the allocations until the kernel killed it
kubectl get pod hog -o jsonpath='{.status.qosClass}'; echo    # Burstable
```

Fix it and observe the QoS class change:

```bash
kubectl delete pod hog
sed -i 's/memory: "64Mi"}/memory: "512Mi"}/g' limits.yaml     # requests AND limits equal
kubectl apply -f limits.yaml
kubectl get pod hog -o jsonpath='{.status.qosClass}'; echo    # Guaranteed
```

> 🔑 **OOMKilled (exit 137) is not a Kubernetes bug — it's the Linux cgroup doing exactly what you asked.** The fix is either more memory or a smaller heap. `kubectl top pod` samples every ~60 s, so a fast spike won't show; check `container_memory_working_set_bytes` in Prometheus for the real peak.

---

## 1.11 Extra Tasks (do all of them — this is where the learning happens)

### Task 1.1 — Generate YAML instead of writing it

Produce a valid Pod manifest **without writing YAML by hand**, using only imperative commands.

<details>
<summary>Show answer</summary>

```bash
kubectl run gen --image=nginx:1.29-alpine --restart=Never \
  --dry-run=client -o yaml > gen.yaml
cat gen.yaml
```

Add labels, ports and resources without opening an editor:

```bash
kubectl run gen --image=nginx:1.29-alpine --restart=Never \
  --labels="app=gen,tier=web" \
  --port=80 \
  --requests="cpu=50m,memory=64Mi" \
  --limits="cpu=200m,memory=128Mi" \
  --dry-run=client -o yaml > gen.yaml

kubectl apply -f gen.yaml
kubectl get pod gen --show-labels
kubectl get pod gen -o jsonpath='{.status.qosClass}'; echo    # Burstable
```

`--dry-run=client -o yaml` is the single most useful kubectl trick: it generates valid YAML locally without touching the cluster. `--dry-run=server` actually sends it to the API server for full validation (RBAC, admission, defaults applied) without persisting.

</details>

---

### Task 1.2 — Copy files in and out

Put a custom `index.html` into a running nginx Pod and serve it, then copy a file back out.

<details>
<summary>Show answer</summary>

```bash
kubectl apply -f pod.yaml      # the "hello" pod from §1.4
echo '<h1>Hello from Harish</h1>' > index.html

# host → pod
kubectl cp index.html hello:/usr/share/nginx/html/index.html
kubectl exec hello -- cat /usr/share/nginx/html/index.html

# verify it's served
kubectl port-forward pod/hello 8080:80 &
sleep 2 && curl -s localhost:8080/          # <h1>Hello from Harish</h1>
kill %1

# pod → host
kubectl exec hello -- sh -c 'uname -a > /tmp/info.txt'
kubectl cp hello:/tmp/info.txt ./info.txt
cat info.txt
```

Gotchas:
- `kubectl cp` requires **`tar`** inside the container. Distroless/scratch images don't have it → use `kubectl exec cat` + shell redirection instead:
  ```bash
  kubectl exec hello -- cat /tmp/info.txt > info.txt
  kubectl exec -i hello -- sh -c 'cat > /tmp/in.txt' < index.html
  ```
- Don't put a leading `/` on the pod path: `kubectl cp hello:/tmp/x ./x` works; `kubectl cp hello://tmp/x ./x` behaves oddly.
- For multi-container Pods add `-c <container>`.
- **Changes made with `cp`/`exec` are lost** when the Pod is replaced. Config belongs in ConfigMaps (§7 of the guide), not in a running container.

</details>

---

### Task 1.3 — Watch a Pod move between nodes (and survive)

Prove that a bare Pod is fragile and a controller-managed Pod isn't.

<details>
<summary>Show answer</summary>

You need a multi-node cluster (kind config from [Guide §0.2](01-KUBERNETES-GUIDE.md#02-pick-one-local-cluster-tool) gives you 3).

```bash
kubectl get nodes
# learn-control-plane   learn-worker   learn-worker2

# 1. Bare pod — find where it is
kubectl apply -f pod.yaml
kubectl get pod hello -o wide          # NODE = learn-worker2 (say)

# 2. Kill the node (in kind, delete the node's container)
docker stop learn-worker2

# 3. Watch what happens
kubectl get nodes
kubectl get pod hello -w
```

```
learn-worker2   NotReady   ...
hello   1/1   Running     0   5m    <- still shows Running for ~40s (stale status)
hello   1/1   Terminating 0   5m    <- node controller gives up, marks for deletion
hello   0/1   Terminating 0   6m
```

The bare Pod is **gone forever**. Nothing recreates it.

```bash
docker start learn-worker2
kubectl wait --for=condition=Ready node/learn-worker2 --timeout=120s
```

Now the same experiment with a Deployment:

```bash
kubectl create deployment web --image=nginx:1.29-alpine --replicas=3
kubectl get pods -o wide -l app=web
docker stop learn-worker2
kubectl get pods -o wide -l app=web -w
```

Within ~40 s the Pod on the dead node is marked `Terminating`, and a replacement is **scheduled onto a live node** automatically. That is self-healing, and it's the entire reason Kubernetes exists.

```bash
docker start learn-worker2
kubectl wait --for=condition=Ready node/learn-worker2 --timeout=120s
kubectl delete deployment web
```

Note: `docker stop` on a kind node container is the equivalent of `kubectl drain` + power off. On a real cluster the sequence is node lease expiry (~40 s) → `NotReady` → taints `unreachable:NoExecute` → Pod eviction after `tolerationSeconds` (default 300 s).

</details>

---

### Task 1.4 — Run a one-off debug Pod that cleans up after itself

You need `dig`, `curl` and `tcpdump` to test something. Do it without leaving junk behind.

<details>
<summary>Show answer</summary>

```bash
# --rm deletes the pod when the container exits; -it attaches a terminal
kubectl run debug --rm -it --image=nicolaka/netshoot --restart=Never -- bash

# inside:
dig +short kubernetes.default.svc.cluster.local
curl -sI https://kubernetes.io
cat /etc/resolv.conf
exit          # pod is deleted automatically
```

Verify it's gone:

```bash
kubectl get pod debug
# Error from server (NotFound): pods "debug" not found
```

Variants:

```bash
# attach to a specific namespace
kubectl run debug -n kube-system --rm -it --image=nicolaka/netshoot --restart=Never -- bash

# run a command and capture output, no interaction
kubectl run check --rm -i --restart=Never --image=busybox:1.37 -- \
  wget -qO- http://kubernetes.default.svc.cluster.local/version

# sleep-pod you keep around and exec into repeatedly
kubectl run tools --image=nicolaka/netshoot --restart=Never --command -- sleep infinity
kubectl exec -it tools -- bash
kubectl delete pod tools

# debug a NODE (host namespaces) — needs the node to be reachable
kubectl debug node/learn-worker -it --image=busybox:1.37
# you land in a chroot of the host: /host is the node's filesystem
```

Why `--restart=Never` matters with `--rm`: with the default `restartPolicy: Always`, the container exits → Kubernetes restarts it → the Pod never terminates → `--rm` never fires and your terminal hangs.

</details>

---

### Task 1.5 — Extract a file from an image without running it

You need to see the default `nginx.conf` shipped in an image, but you don't want to start a server.

<details>
<summary>Show answer</summary>

**Method 1 — override the command (easiest):**

```bash
kubectl run peek --rm -i --restart=Never --image=nginx:1.29-alpine -- \
  cat /etc/nginx/nginx.conf
```

**Method 2 — a Pod with `command: ["sleep"]` and `kubectl cp`:**

```bash
kubectl run peek --image=nginx:1.29-alpine --restart=Never --command -- sleep 300
kubectl wait --for=condition=Ready pod/peek --timeout=60s
kubectl cp peek:/etc/nginx/nginx.conf ./nginx.conf
kubectl delete pod peek
```

**Method 3 — no cluster at all (often the right answer):**

```bash
docker create --name tmp nginx:1.29-alpine
docker cp tmp:/etc/nginx/nginx.conf ./nginx.conf
docker rm tmp

# or fully without Docker:
skopeo copy docker://nginx:1.29-alpine oci:/tmp/oci:latest
crane export nginx:1.29-alpine - | tar -xO etc/nginx/nginx.conf
```

Method 1 is what you'll actually use in a cluster — `--rm -i --restart=Never -- <cmd>` is the "run this once and show me" idiom.

</details>

---

## 1.12 What you should be able to do now

Tick these without looking anything up:

- [ ] Create a cluster and confirm it with `kubectl get nodes`
- [ ] Run a Pod both imperatively and from YAML
- [ ] Explain the difference between `kubectl create` and `kubectl apply`
- [ ] Name the four Pod birth states in order
- [ ] Find a Pod's IP, node, labels, and container exit code
- [ ] Select Pods with `-l` using `=`, `!=`, `in`, and key-exists
- [ ] Read `Events` in `describe` output and identify the failure stage
- [ ] Get logs from a crashed container (`--previous`)
- [ ] Exec into a container and run a one-shot command
- [ ] Port-forward and curl a Pod from your laptop
- [ ] Explain what exit codes 127, 137 and 143 mean
- [ ] Explain why `restartPolicy: Always` restarts a container that exits 0
- [ ] Explain why a bare Pod is never the production answer

**Next → [`05-PROJECT-2-deployment-service.md`](05-PROJECT-2-deployment-service.md)** — Deployments, Services, rolling updates, and how to prove zero downtime.

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish%20Kumar%20Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn → <https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260>
🐙 GitHub → <https://github.com/3558Bhk>

*Built for engineers who learn by breaking things on purpose.*

</div>
