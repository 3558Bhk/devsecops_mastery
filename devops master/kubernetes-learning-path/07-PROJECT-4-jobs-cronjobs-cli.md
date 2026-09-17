# 🏅 Project 4 — Jobs, CronJobs, Init Containers & One-Shot Tasks

> **Time:** 2 hours · **Prereq:** [Project 3](06-PROJECT-3-config-secrets.md)
>
> **What you'll learn:** how to run things that are *supposed to stop* — database migrations, nightly backups, batch processing, warm-up tasks — and how to structure a Pod that has to prepare itself before the main app starts.
>
> **Why it matters:** every real deployment has at least one Job (migrations) and one CronJob (backups). Interviewers ask about `restartPolicy` in Jobs constantly, and most people get it wrong.

---

## 4.1 The 60-second theory

Deployments want Pods that **never stop**. Jobs want Pods that **finish**.

| Object | Runs | Restarts on failure | Terminates when |
|---|---|---|---|
| Deployment | forever | always (new Pod) | never — you delete it |
| **Job** | to completion | `backoffLimit` times | `completions` successes reached |
| **CronJob** | on a schedule | creates a Job per run | per-run, same as a Job |
| **init container** | before main containers, in order | with the Pod's restartPolicy | the Pod proceeds to main containers |

The critical rule: **inside a Job, `restartPolicy` may only be `Never` or `OnFailure`.** `Always` is rejected:

```
spec.template.spec.restartPolicy: Unsupported value: "Always": supported values: "OnFailure", "Never"
```

| Choice | Behaviour when a container exits non-zero |
|---|---|
| `Never` | The Pod fails; the **Job controller creates a brand-new Pod** |
| `OnFailure` | The **container restarts inside the same Pod** |

Both count against `backoffLimit`. `OnFailure` is cheaper (no reschedule, image stays cached); `Never` gives you a clean Pod per attempt, which is easier to debug with `kubectl logs --previous` vs. separate Pods.

---

## 4.2 Step 1 — Your first Job

### Imperatively

```bash
mkdir -p ~/k8s-learn/p4 && cd ~/k8s-learn/p4

kubectl create job hello-job --image=busybox:1.37 -- echo "hello from a job"
kubectl get jobs
kubectl get pods -l job-name=hello-job
kubectl logs job/hello-job
```

```
NAME        READY   STATUS      RESTARTS   AGE
hello-job-x7k2p   0/1   Completed   0          15s
```

Note the Pod **stays around** in `Completed` state so you can read its logs. Delete the Job and the Pod goes with it (owner references).

```bash
kubectl delete job hello-job
```

### Declaratively — every knob labelled

`job.yaml`:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: migrate
  labels: {app: shop, task: migrate}
spec:
  completions: 1                  # how many successful Pod runs are required
  parallelism: 1                  # how many Pods run at once
  backoffLimit: 3                 # failures tolerated before the Job is marked Failed
  backoffLimitPerIndex: 2         # (Indexed mode) per-index retry cap
  activeDeadlineSeconds: 600      # hard timeout — Job fails if still running after this
  ttlSecondsAfterFinished: 300    # ⭐ auto-delete Job+Pods 5 min after finishing
  podReplacementPolicy: Failed    # TerminationPolicy: when to replace a pod
  template:
    metadata:
      labels: {app: shop, task: migrate}
    spec:
      restartPolicy: Never        # ⚠️ ONLY Never or OnFailure
      backoffLimit: 3
      containers:
        - name: migrate
          image: python:3.13-alpine
          command: ["python", "-c"]
          args:
            - |
              import os, random, sys, time
              print(f"migration starting on {os.uname().nodename}", flush=True)
              time.sleep(2)
              if random.random() < 0.0:      # flip to 0.7 to watch retries happen
                  print("ERROR: could not acquire migration lock", flush=True)
                  sys.exit(1)
              print("applied 14 migrations", flush=True)
              print("migration complete", flush=True)
          resources:
            requests: {cpu: 100m, memory: 64Mi}
            limits:   {cpu: 500m, memory: 128Mi}
          env:
            - name: DATABASE_URL
              valueFrom: {secretKeyRef: {name: db-creds, key: url, optional: true}}
```

```bash
kubectl apply -f job.yaml
kubectl get jobs -w
```

```
NAME      READY   STATUS     COMPLETIONS   DURATION   AGE
migrate   0/1     Running    0/1           2s         2s
migrate   0/1     Running    0/1           4s         4s
migrate   -       Complete   1/1           4s         6s
```

**Wait for it programmatically** — this is what CI does:

```bash
kubectl wait --for=condition=complete job/migrate --timeout=300s
echo "exit=$?"        # 0 = complete, non-zero = timeout/failure

# or the failure-aware version:
kubectl wait --for=condition=failed --timeout=300s job/migrate && {
  echo "JOB FAILED"; kubectl logs job/migrate; exit 1;
}
```

Inspect:

```bash
kubectl describe job migrate
kubectl get pods -l job-name=migrate
kubectl logs job/migrate
kubectl logs job/migrate --tail=20
kubectl get job migrate -o jsonpath='{.status}'; echo | jq .
```

```json
{
  "completionTime": "2026-09-09T12:05:11Z",
  "conditions": [{"type": "Complete", "status": "True", "reason": "CompletionsReached"}],
  "startTime": "2026-09-09T12:05:07Z",
  "succeeded": 1,
  "uncountedTerminatedPods": {}
}
```

```bash
kubectl delete job migrate
```

---

## 4.3 Step 2 — Watch retries and backoff

Make it fail on purpose:

```bash
sed -i 's/random.random() < 0.0/random.random() < 1.0/' job.yaml    # always fail
kubectl delete job migrate --ignore-not-found
kubectl apply -f job.yaml
kubectl get jobs -w
```

```
migrate   0/1   Running   0/1   2s    2s
migrate   0/1   Running   0/1   4s    4s     ← pod fails
migrate   0/1   Running   0/1   6s    10s    ← retry 1 after backoff
migrate   0/1   Running   0/1   8s    30s    ← retry 2
migrate   0/1   Running   0/1   10s   70s    ← retry 3
migrate   -     Failed    0/1   12s   130s   ← backoffLimit=3 exhausted
```

```bash
kubectl describe job migrate | sed -n '/Events:/,$p'
```

```
Warning  BackoffLimitExceeded   ...   Job has reached the specified backoff limit
Normal   Failed                 ...   ...
```

```bash
kubectl get pods -l job-name=migrate          # 4 pods: 3 Failed + 1
kubectl get pods -l job-name=migrate -o custom-columns='NAME:.metadata.name,PHASE:.status.phase,EXIT:.status.containerStatuses[0].state.terminated.exitCode'
kubectl logs migrate-x7k2p
```

**The retry delay is exponential** (10s, 20s, 40s … capped at 256s) and jittered. Set `backoffLimit: 0` for "fail fast, don't retry" — right for migrations, where a retry after a partial apply can be worse than stopping.

Restore:

```bash
sed -i 's/random.random() < 1.0/random.random() < 0.0/' job.yaml
kubectl delete job migrate
```

---

## 4.4 Step 3 — Parallel Jobs (the work-queue pattern)

Three flavours. Know all three.

### Flavour A — one Job, N parallel Pods, single completion

```yaml
apiVersion: batch/v1
kind: Job
metadata: {name: process-batch}
spec:
  parallelism: 5          # 5 pods at a time
  completions: 20         # need 20 successes total
  backoffLimit: 10
  template:
    spec:
      restartPolicy: OnFailure
      containers:
        - name: worker
          image: busybox:1.37
          command: ["sh","-c","echo work item; sleep 5; echo done"]
          resources: {requests: {cpu: 20m, memory: 16Mi}, limits: {cpu: 100m, memory: 32Mi}}
```

Pods keep being created until 20 succeed, never more than 5 at once.

### Flavour B — Indexed Job (each Pod knows its index)

```yaml
apiVersion: batch/v1
kind: Job
metadata: {name: shard-processor}
spec:
  completions: 6
  parallelism: 3
  completionMode: Indexed            # ⭐ each pod gets a unique index
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: worker
          image: busybox:1.37
          command:
            - sh
            - -c
            - |
              echo "I am shard $JOB_COMPLETION_INDEX of $JOB_COMPLETIONS"
              echo "processing partition $JOB_COMPLETION_INDEX"
              sleep 5
          resources: {requests: {cpu: 20m, memory: 16Mi}}
```

```bash
kubectl apply -f indexed-job.yaml
kubectl get pods -l job-name=shard-processor \
  -o custom-columns='NAME:.metadata.name,INDEX:.spec.containers[0].env' 
kubectl logs -l job-name=shard-processor --prefix --tail=3
```

```
[pod/shard-processor-0-xk2p] I am shard 0 of 6
[pod/shard-processor-3-mn4q] I am shard 3 of 6
[pod/shard-processor-1-ab12] I am shard 1 of 6
```

Pod names become `shard-processor-<index>-<hash>` — stable, ordered, readable. Automatic env vars: `JOB_COMPLETION_INDEX`, plus `JOB_COMPLETIONS` / `JOB_PARALLELISM` in newer versions.

**This is how you shard a big job:** each Pod computes its own slice from the index. Perfect for "process 1000 files with 10 workers".

### Flavour C — one Job per item (generate them)

```bash
for region in ap-south-1 us-east-1 eu-west-1; do
  cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: warm-$region
  labels: {task: warm-cache, region: $region}
spec:
  backoffLimit: 2
  ttlSecondsAfterFinished: 600
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: warm
          image: curlimages/curl:8.10.1
          command: ["sh","-c","curl -sf http://api.$region.svc.cluster.local/warm || exit 1"]
          env: [{name: REGION, value: "$region"}]
          resources: {requests: {cpu: 10m, memory: 16Mi}}
EOF
done

kubectl get jobs -l task=warm-cache
kubectl wait --for=condition=complete --timeout=120s job -l task=warm-cache
kubectl logs -l task=warm-cache --prefix
kubectl delete jobs -l task=warm-cache
```

---

## 4.5 Step 4 — CronJob

`cronjob.yaml`:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: report
  labels: {task: nightly-report}
spec:
  schedule: "*/2 * * * *"             # every 2 minutes (for demo; use "30 2 * * *" in prod)
  timeZone: "Asia/Kolkata"            # ⭐ supported since v1.27 — otherwise UTC
  concurrencyPolicy: Forbid           # Allow | Forbid | Replace
  successfulJobsHistoryLimit: 3       # keep 3 completed Jobs
  failedJobsHistoryLimit: 3
  startingDeadlineSeconds: 200        # if we missed the window by more than this, skip it
  suspend: false                      # true = pause without deleting
  jobTemplate:
    spec:
      backoffLimit: 2
      activeDeadlineSeconds: 900      # 15 min hard cap per run
      ttlSecondsAfterFinished: 3600
      template:
        metadata: {labels: {task: nightly-report}}
        spec:
          restartPolicy: OnFailure
          containers:
            - name: report
              image: busybox:1.37
              command:
                - sh
                - -c
                - |
                  echo "=== report run at $(date -u +%FT%TZ) ==="
                  echo "hostname: $(hostname)"
                  echo "scheduled for: $TZ_HINT"
                  df -h / 2>/dev/null | head -3
                  echo "done"
              env: [{name: TZ_HINT, value: "Asia/Kolkata"}]
              resources:
                requests: {cpu: 20m, memory: 16Mi}
                limits:   {cpu: 100m, memory: 32Mi}
```

```bash
kubectl apply -f cronjob.yaml
kubectl get cronjobs
```

```
NAME     SCHEDULE      SUSPEND   ACTIVE   LAST SCHEDULE   AGE
report   */2 * * * *   False     0        <none>          10s
```

Wait ~2 minutes:

```bash
kubectl get cronjobs -w
# LAST SCHEDULE becomes 30s, then jobs appear:
kubectl get jobs -l task=nightly-report
# report-29271440   1/1   Complete   0   90s
kubectl logs job/report-29271440
```

The Job name is `<cronjob>-<unix-minutes-since-epoch/... >`-ish — a numeric suffix derived from the scheduled time.

### Cron schedule syntax

```
 ┌───────── minute        (0 - 59)
 │ ┌─────── hour          (0 - 23)
 │ │ ┌───── day of month  (1 - 31)
 │ │ │ ┌─── month         (1 - 12)
 │ │ │ │ ┌─ day of week   (0 - 6, Sunday = 0; also MON-SUN)
 │ │ │ │ │
 * * * * *
```

| Schedule | Meaning |
|---|---|
| `*/5 * * * *` | every 5 minutes |
| `0 * * * *` | every hour on the hour |
| `15 */6 * * *` | 00:15, 06:15, 12:15, 18:15 |
| `30 2 * * *` | 02:30 daily |
| `0 9 * * 1-5` | 09:00 Monday–Friday |
| `0 0 1 * *` | midnight on the 1st |
| `0 4 * * 0` | 04:00 Sundays |
| `@hourly` / `@daily` / `@weekly` / `@monthly` / `@yearly` | supported shortcuts |
| `@every 90s` / `@every 5m` | interval form (robfig/cron syntax — supported by K8s) |

> ⚠️ **No seconds field.** `0 0 * * * *` (6 fields) is invalid: `cron spec must contain exactly 5 fields`. That's a Quartz habit leaking in.

> ⚠️ **CronJob names must be ≤52 characters** — generated Job names append an 11-character suffix, and Job names must be ≤63.

### `concurrencyPolicy` — what to do when a run overlaps

| Policy | Behaviour | Use when |
|---|---|---|
| `Allow` (default) | Runs pile up concurrently | Idempotent, cheap jobs |
| `Forbid` | Skips the new run if the old one is still going | **Most backups, most reports.** Safe default. |
| `Replace` | Kills the running Job and starts a new one | Freshness matters more than completion (e.g. a cache refresh) |

Demo `Forbid`:

```bash
kubectl apply -f - <<'EOF'
apiVersion: batch/v1
kind: CronJob
metadata: {name: slow}
spec:
  schedule: "* * * * *"
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 5
  jobTemplate:
    spec:
      activeDeadlineSeconds: 300
      template:
        spec:
          restartPolicy: Never
          containers:
            - name: slow
              image: busybox:1.37
              command: ["sh","-c","echo start; sleep 150; echo end"]
EOF
kubectl get jobs -l job-name -w       # you'll see at most ONE active
kubectl get cronjob slow -o jsonpath='{.status.lastScheduleTime}{"\n"}'
kubectl describe cronjob slow | tail -10
# Events: "Not starting job because previous job is still running" / concurrencyPolicy blocked
kubectl delete cronjob slow
```

### `startingDeadlineSeconds` — the "missed schedule" behaviour

If the CronJob controller was down (or the cluster was suspended) and comes back at 03:00 for a 02:30 job:
- **Without** `startingDeadlineSeconds`: if the miss is under ~1 minute it still runs; if the controller missed more than 100 scheduled slots, the CronJob is marked `NeedsStartingDeadlineSeconds` and **stops running entirely** until you fix it. That's a real production incident.
- **With** `startingDeadlineSeconds: 300`: runs if it's within 5 minutes of the scheduled time, otherwise skips cleanly.

**Always set it.**

### Useful CronJob operations

```bash
kubectl get cronjobs -A
kubectl describe cronjob report

# run it NOW without waiting for the schedule ⭐
kubectl create job --from=cronjob/report manual-report-$(date +%s)
kubectl logs job/manual-report-1757000000 -f

# pause / resume
kubectl patch cronjob report -p '{"spec":{"suspend":true}}'
kubectl patch cronjob report -p '{"spec":{"suspend":false}}'

# change the schedule live
kubectl patch cronjob report -p '{"spec":{"schedule":"0 3 * * *"}}'

# clean up finished Jobs
kubectl delete jobs --field-selector status.successful=1
kubectl get jobs -o json | jq -r '.items[] | select(.status.completionTime != null) | .metadata.name' | xargs -r kubectl delete job

# see when it will next run
kubectl get cronjob report -o jsonpath='{.status.lastScheduleTime}{"\n"}{.status.lastSuccessfulTime}{"\n"}'
```

---

## 4.6 Step 5 — The real one: a database migration in a deployment pipeline

This is the pattern you'll actually use at work.

### 5.1 The migration Job as a Helm hook

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ .Release.Name }}-migrate-{{ .Release.Revision }}
  annotations:
    "helm.sh/hook": pre-install,pre-upgrade
    "helm.sh/hook-weight": "-5"                 # lower runs first
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
spec:
  backoffLimit: 0                               # ⭐ DO NOT retry migrations blindly
  activeDeadlineSeconds: 600
  ttlSecondsAfterFinished: 86400
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: migrate
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          command: ["python", "manage.py", "migrate", "--noinput"]
          env:
            - {name: DATABASE_URL_FILE, value: /run/secrets/db/url}
          volumeMounts:
            - {name: db, mountPath: /run/secrets/db, readOnly: true}
          resources: {requests: {cpu: 200m, memory: 256Mi}, limits: {cpu: "1", memory: 512Mi}}
      volumes:
        - name: db
          secret: {secretName: db-creds}
```

Why `backoffLimit: 0`? A migration that failed halfway may have partially applied. Retrying automatically can corrupt state. **Fail loudly, let a human decide.**

### 5.2 Migration as a plain Job in CI (no Helm)

```bash
#!/usr/bin/env bash
set -euo pipefail
NS=${1:-prod}
TAG=${2:-$(git rev-parse --short HEAD)}
JOB=migrate-$TAG

echo "▸ deleting any previous job with this name"
kubectl delete job $JOB -n $NS --ignore-not-found

echo "▸ creating migration job for image myapp:$TAG"
cat <<EOF | kubectl apply -n $NS -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: $JOB
  labels: {app: myapp, task: migrate, tag: "$TAG"}
spec:
  backoffLimit: 0
  activeDeadlineSeconds: 900
  ttlSecondsAfterFinished: 604800     # keep 7 days for audit
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: migrate
          image: ghcr.io/3558bhk/myapp:$TAG
          command: ["python", "manage.py", "migrate", "--noinput"]
          envFrom: [{secretRef: {name: db-creds}}]
          resources: {requests: {cpu: 200m, memory: 256Mi}}
EOF

echo "▸ streaming logs"
kubectl wait -n $NS --for=condition=Ready pod -l job-name=$JOB --timeout=120s || true
kubectl logs -n $NS -f job/$JOB || true

echo "▸ waiting for completion"
if kubectl wait -n $NS --for=condition=complete job/$JOB --timeout=900s; then
  echo "✅ migration succeeded"
else
  echo "❌ migration FAILED — not deploying"
  kubectl describe job $JOB -n $NS | sed -n '/Events:/,$p'
  exit 1
fi

echo "▸ now rolling out the app"
kubectl set image deployment/myapp -n $NS myapp=ghcr.io/3558bhk/myapp:$TAG
kubectl rollout status deployment/myapp -n $NS --timeout=300s
```

**Order matters:** migrate *before* the rollout, and make migrations **backward compatible** (expand → migrate → contract) so the old Pods keep working while the new ones come up.

### 5.3 The nightly backup CronJob

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: pg-backups, namespace: prod}
spec:
  accessModes: [ReadWriteOnce]
  resources: {requests: {storage: 50Gi}}
---
apiVersion: batch/v1
kind: CronJob
metadata: {name: pg-backup, namespace: prod}
spec:
  schedule: "0 2 * * *"
  timeZone: "Asia/Kolkata"
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 5
  startingDeadlineSeconds: 1800
  jobTemplate:
    spec:
      backoffLimit: 1
      activeDeadlineSeconds: 3600
      template:
        spec:
          restartPolicy: OnFailure
          containers:
            - name: backup
              image: postgres:17-alpine
              command: ["/bin/sh","-c"]
              args:
                - |
                  set -eu
                  STAMP=$(date -u +%Y%m%d-%H%M%S)
                  OUT=/backups/app-$STAMP.sql.gz
                  echo "▸ starting dump → $OUT"
                  pg_dump -h db -U "$PGUSER" -d "$PGDATABASE" --format=custom --file="$OUT.tmp"
                  mv "$OUT.tmp" "$OUT"
                  ls -lh "$OUT"
                  echo "▸ verifying"
                  pg_restore --list "$OUT" > /dev/null && echo "✅ archive is valid"
                  echo "▸ pruning backups older than 14 days"
                  find /backups -name 'app-*.sql.gz' -mtime +14 -print -delete
                  echo "▸ current backups:"
                  ls -lh /backups | tail -20
              env:
                - {name: PGUSER,     valueFrom: {secretKeyRef: {name: pg-creds, key: username}}}
                - {name: PGPASSWORD, valueFrom: {secretKeyRef: {name: pg-creds, key: password}}}
                - {name: PGDATABASE, value: "app"}
              volumeMounts:
                - {name: backups, mountPath: /backups}
              resources:
                requests: {cpu: 200m, memory: 256Mi}
                limits:   {cpu: "1",  memory: 1Gi}
          volumes:
            - name: backups
              persistentVolumeClaim: {claimName: pg-backups}
```

```bash
kubectl apply -f backup-cronjob.yaml
kubectl create job --from=cronjob/pg-backup backup-manual-1 -n prod    # test it NOW
kubectl logs -n prod job/backup-manual-1 -f
```

**Production note:** a PVC in the cluster is a fine *staging* area, but your real backup belongs in object storage. Add `aws s3 cp` / `gsutil cp` / `mc cp` at the end of the script, then the PVC only needs to be a few GB of scratch. Or better — use **Velero** ([Guide §8.8](01-KUBERNETES-GUIDE.md#88-backup--restore-what-production-actually-does)).

---

## 4.7 Step 6 — Init containers

Init containers run **to completion, in order, before any main container starts**. If one fails, it's retried per the Pod's `restartPolicy`.

`init-demo.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata: {name: init-demo}
spec:
  restartPolicy: Never
  volumes:
    - name: shared
      emptyDir: {}
    - name: config
      configMap: {name: shop-config, optional: true}
  initContainers:
    # 1. Wait for a dependency (the single most common init container)
    - name: wait-for-db
      image: busybox:1.37
      command:
        - sh
        - -c
        - |
          echo "waiting for db:5432..."
          until nc -z db 5432 2>/dev/null; do
            echo "  not ready, retrying in 2s"
            sleep 2
          done
          echo "db is up"
      # ⚠️ in a real cluster give this a timeout, or it waits forever:
      #   i=0; until nc -z db 5432 || [ $i -gt 60 ]; do sleep 2; i=$((i+1)); done; [ $i -le 60 ] || exit 1

    # 2. Fix permissions / prepare a directory
    - name: prepare-dirs
      image: busybox:1.37
      command: ["sh","-c","mkdir -p /shared/cache /shared/tmp && chmod 775 /shared/cache && echo prepared"]
      securityContext: {runAsUser: 0}          # needs root to chmod, then the app runs as non-root
      volumeMounts: [{name: shared, mountPath: /shared}]

    # 3. Copy/transform config
    - name: render-config
      image: busybox:1.37
      command: ["sh","-c","sed \"s/__HOST__/$(hostname)/g\" /config-src/app.conf > /shared/app.conf && cat /shared/app.conf"]
      volumeMounts:
        - {name: config, mountPath: /config-src, readOnly: true}
        - {name: shared, mountPath: /shared}

    # 4. One-time data fetch
    - name: fetch-seed
      image: curlimages/curl:8.10.1
      command: ["sh","-c","curl -sfL https://raw.githubusercontent.com/kubernetes/examples/master/README.md -o /shared/seed.txt && wc -l /shared/seed.txt"]
      volumeMounts: [{name: shared, mountPath: /shared}]

  containers:
    - name: app
      image: busybox:1.37
      command: ["sh","-c","echo '=== main container ==='; ls -la /shared; head -3 /shared/seed.txt; sleep 60"]
      volumeMounts: [{name: shared, mountPath: /shared}]
```

```bash
kubectl apply -f init-demo.yaml
kubectl get pod init-demo -w
```

```
init-demo   0/1   Init:0/4          0   0s
init-demo   0/1   Init:1/4          0   3s
init-demo   0/1   Init:2/4          0   5s
init-demo   0/1   Init:3/4          0   7s
init-demo   0/1   Init:4/4          0   9s
init-demo   0/1   PodInitializing   0   10s
init-demo   1/1   Running           0   11s
```

**`Init:2/4` is a gift** — it tells you exactly which init container is running/stuck.

```bash
kubectl logs init-demo -c wait-for-db
kubectl logs init-demo -c render-config
kubectl logs init-demo -c app
kubectl describe pod init-demo | sed -n '/Init Containers:/,/Conditions:/p'
kubectl delete pod init-demo
```

### Init containers vs main containers

| | Init container | Main container |
|---|---|---|
| Runs | Sequentially, to completion | Concurrently, indefinitely |
| May have probes? | ❌ No (they must complete) | ✅ |
| Restart on failure | Yes, per Pod restartPolicy | Yes |
| Can it be a sidecar? | ✅ with `restartPolicy: Always` | — |
| Resource requests | The Pod's effective request = **max(sum(main), max(init))** | summed |

> 🔑 That resource rule matters for scheduling: a Pod with a 2 GB init container and 100 Mi app containers needs 2 GB of allocatable memory on the node.

### The classic init container: "wait for X"

Don't hand-roll it — use a purpose-built image:

```yaml
initContainers:
  - name: wait-for-db
    image: groundnutt/k8s-wait-for:v2.0
    command: ["wait-for", "job", "migrate", "-n", "prod"]
  # or
  - name: wait
    image: busybox:1.37
    command: ['sh','-c','until wget -qO- http://api:8080/healthz; do sleep 2; done']
```

Or, better in modern Kubernetes, use **native sidecars** so ordering is handled by the platform.

---

## 4.8 Step 7 — Native sidecars (the modern pattern)

Stable since v1.33. An init container with `restartPolicy: Always`:
- starts **before** main containers
- keeps running alongside them
- terminates **after** them (so it can flush logs on shutdown)

This fixes the classic bug where a log shipper gets SIGKILLed before the app finishes writing.

```yaml
apiVersion: v1
kind: Pod
metadata: {name: sidecar-demo}
spec:
  restartPolicy: Never
  volumes: [{name: logs, emptyDir: {}}]
  initContainers:
    - name: shipper                 # ← NATIVE SIDECAR
      image: busybox:1.37
      restartPolicy: Always         # ⭐ THIS is the magic line
      command:
        - sh
        - -c
        - |
          echo "shipper started"
          touch /logs/app.log
          tail -F /logs/app.log | while read -r line; do
            echo "[shipped] $line"
          done
          echo "shipper terminating cleanly"
      volumeMounts: [{name: logs, mountPath: /logs}]
  containers:
    - name: app
      image: busybox:1.37
      command: ["sh","-c","for i in $(seq 1 5); do echo \"app line $i\" >> /logs/app.log; sleep 1; done; echo app exiting"]
      volumeMounts: [{name: logs, mountPath: /logs}]
```

```bash
kubectl apply -f sidecar-demo.yaml
kubectl get pod sidecar-demo -w
```

```
sidecar-demo   0/1   Init:0/1        0   0s
sidecar-demo   1/2   PodInitializing 0   1s     ← the sidecar counts as "ready"
sidecar-demo   2/2   Running         0   2s
sidecar-demo   1/2   NotReady        0   8s     ← app finished, sidecar still running
```

Note **`READY 2/2`** — native sidecars count toward readiness once started. And the Pod stays alive because the sidecar is still running (that's expected: it's a container that never exits). In a **Job**, Kubernetes treats native sidecars specially and lets the Job complete when the main containers finish.

```bash
kubectl logs sidecar-demo -c shipper
kubectl logs sidecar-demo -c app
kubectl delete pod sidecar-demo
```

---

## 4.9 Step 8 — Real-world one-shot tasks

```bash
# Interactive shell in a specific namespace with the app's config
kubectl run shell -n prod --rm -it --restart=Never \
  --image=ghcr.io/3558bhk/myapp:1.4.2 \
  --overrides='{"spec":{"serviceAccountName":"app-sa","containers":[{"name":"shell","image":"ghcr.io/3558bhk/myapp:1.4.2","stdin":true,"tty":true,"command":["sh"],"envFrom":[{"secretRef":{"name":"db-creds"}}]}]}}' \
  -- sh

# Run a Django shell
kubectl run dj --rm -it --restart=Never --image=myapp:1.4.2 \
  --env-from=db-creds -- python manage.py shell

# One-off SQL against a cluster DB
kubectl run psql --rm -it --restart=Never --image=postgres:17-alpine \
  --env=PGPASSWORD=... -- psql -h db -U postgres -d app -c '\dt'

# Port-forward-free API test using the cluster's own DNS
kubectl run curltest --rm -i --restart=Never --image=curlimages/curl:8.10.1 -- \
  curl -s http://api.prod.svc.cluster.local:8080/health

# Copy a directory into a running cluster for a test
kubectl cp ./fixtures prod/test-pod:/tmp/fixtures

# A long-lived toolbox pod (not --rm)
kubectl run toolbox -n prod --image=nicolaka/netshoot --restart=Never \
  --command -- sleep infinity
kubectl exec -it toolbox -n prod -- bash
kubectl delete pod toolbox -n prod
```

The `--overrides` JSON is ugly but powerful — it's how you attach ServiceAccounts, Secrets and volume mounts to a throwaway Pod without writing a file.

---

## 4.10 Extra Tasks

### Task 4.1 — A Job that processes a work queue with parallel workers

10 workers pull items from a Redis list until it's empty. Handle the "no more work" case correctly.

<details>
<summary>Show answer</summary>

```yaml
apiVersion: v1
kind: ConfigMap
metadata: {name: worker-script}
data:
  work.py: |
    import os, redis, time, sys, socket
    r = redis.Redis(host=os.environ["REDIS_HOST"], port=6379, db=0,
                    socket_timeout=5, socket_connect_timeout=5)
    me = socket.gethostname()
    # BRPOP with a timeout: if the queue is empty for 10s, assume we're done
    while True:
        item = r.brpop("work:queue", timeout=10)
        if item is None:
            print(f"{me}: queue empty for 10s — exiting 0", flush=True)
            sys.exit(0)
        _, payload = item
        payload = payload.decode()
        print(f"{me}: processing {payload}", flush=True)
        try:
            time.sleep(0.5)                       # pretend to work
            r.lpush("work:done", payload)
        except Exception as e:
            print(f"{me}: FAILED {payload}: {e}", flush=True)
            r.lpush("work:failed", payload)
            # do NOT exit(1) — one bad item shouldn't kill the worker
---
apiVersion: batch/v1
kind: Job
metadata: {name: queue-drain}
spec:
  parallelism: 10
  completions: 10              # 10 pods, each must succeed once
  backoffLimit: 10
  activeDeadlineSeconds: 1800
  ttlSecondsAfterFinished: 3600
  template:
    spec:
      restartPolicy: OnFailure   # keep the pod, restart the container — cheaper
      containers:
        - name: worker
          image: python:3.13-alpine
          command: ["sh","-c","pip install --quiet redis && python /scripts/work.py"]
          env:
            - {name: REDIS_HOST, value: "redis"}
          volumeMounts: [{name: script, mountPath: /scripts}]
          resources:
            requests: {cpu: 100m, memory: 128Mi}
            limits:   {cpu: 500m, memory: 256Mi}
      volumes:
        - name: script
          configMap: {name: worker-script}
```

Seed the queue and run:

```bash
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: redis}
spec:
  replicas: 1
  selector: {matchLabels: {app: redis}}
  template:
    metadata: {labels: {app: redis}}
    spec:
      containers: [{name: redis, image: redis:7-alpine, ports: [{containerPort: 6379}]}]
---
apiVersion: v1
kind: Service
metadata: {name: redis}
spec: {selector: {app: redis}, ports: [{port: 6379}]}
EOF
kubectl rollout status deploy/redis

kubectl run seed --rm -i --restart=Never --image=redis:7-alpine -- sh -c '
  for i in $(seq 1 200); do redis-cli -h redis lpush work:queue "item-$i" > /dev/null; done
  redis-cli -h redis llen work:queue'
# → (integer) 200

kubectl apply -f queue-job.yaml
kubectl get pods -l job-name=queue-drain -w
kubectl logs -l job-name=queue-drain --prefix --tail=5 -f
kubectl wait --for=condition=complete job/queue-drain --timeout=1800s
kubectl run check --rm -i --restart=Never --image=redis:7-alpine -- sh -c \
  'echo done=$(redis-cli -h redis llen work:done) failed=$(redis-cli -h redis llen work:failed)'
```

**Design points that matter:**
- `BRPOP` is atomic → no two workers get the same item. This is why you use a real queue instead of an Indexed Job when work is uneven.
- Exiting `0` on an empty queue (with a timeout, not instantly) is what makes `completions` meaningful.
- **Don't `exit(1)` on a bad item** — push it to a dead-letter list and keep going, or one poison message burns your whole `backoffLimit`.
- `restartPolicy: OnFailure` keeps the pip-installed packages in the container filesystem between retries (faster). With `Never` you get a fresh Pod and reinstall every time.
- Real production version: bake `redis` into the image instead of `pip install` at runtime (slow, needs egress, non-reproducible).

```bash
kubectl delete job queue-drain && kubectl delete deploy redis && kubectl delete svc redis
```

</details>

---

### Task 4.2 — A CronJob that cleans up Completed Pods and old Jobs

Your namespace fills with hundreds of `Completed` Pods. Automate the cleanup.

<details>
<summary>Show answer</summary>

First, the *right* fix is to not create the mess: set `ttlSecondsAfterFinished` on every Job and `successfulJobsHistoryLimit` / `failedJobsHistoryLimit` on every CronJob.

```yaml
spec:
  ttlSecondsAfterFinished: 86400     # Job + its Pods deleted 24h after finishing
```

For the existing mess, a cleanup CronJob:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata: {name: janitor, namespace: prod}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: {name: janitor, namespace: prod}
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "delete"]
  - apiGroups: ["batch"]
    resources: ["jobs"]
    verbs: ["get", "list", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: {name: janitor, namespace: prod}
subjects: [{kind: ServiceAccount, name: janitor, namespace: prod}]
roleRef: {kind: Role, name: janitor, apiGroup: rbac.authorization.k8s.io}
---
apiVersion: batch/v1
kind: CronJob
metadata: {name: janitor, namespace: prod}
spec:
  schedule: "0 * * * *"
  timeZone: "Asia/Kolkata"
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 1
  failedJobsHistoryLimit: 1
  startingDeadlineSeconds: 600
  jobTemplate:
    spec:
      backoffLimit: 1
      activeDeadlineSeconds: 600
      ttlSecondsAfterFinished: 3600
      template:
        spec:
          serviceAccountName: janitor
          restartPolicy: OnFailure
          containers:
            - name: janitor
              image: bitnami/kubectl:1.33
              command: ["/bin/sh","-c"]
              args:
                - |
                  set -eu
                  NS=prod
                  AGE="${MAX_AGE_HOURS:-24}"
                  echo "▸ deleting Succeeded/Failed pods older than ${AGE}h"
                  kubectl get pods -n $NS --field-selector 'status.phase==Succeeded' \
                    -o json | jq -r --arg cutoff "$(date -u -d "-${AGE} hours" +%FT%TZ 2>/dev/null || date -u -v-${AGE}H +%FT%TZ)" \
                    '.items[] | select(.metadata.creationTimestamp < $cutoff) | .metadata.name' \
                    | xargs -r -n20 kubectl delete pod -n $NS --ignore-not-found
                  kubectl get pods -n $NS --field-selector 'status.phase==Failed' \
                    -o json | jq -r '.items[] | select(.status.reason=="Evicted") | .metadata.name' \
                    | xargs -r -n20 kubectl delete pod -n $NS --ignore-not-found
                  echo "▸ deleting completed Jobs older than 7 days"
                  kubectl get jobs -n $NS -o json \
                    | jq -r --arg cutoff "$(date -u -d "-7 days" +%FT%TZ 2>/dev/null || date -u -v-7d +%FT%TZ)" \
                      '.items[] | select(.status.completionTime != null and .status.completionTime < $cutoff) | .metadata.name' \
                    | xargs -r -n10 kubectl delete job -n $NS --ignore-not-found
                  echo "✅ cleanup done"
              env: [{name: MAX_AGE_HOURS, value: "24"}]
              resources: {requests: {cpu: 50m, memory: 64Mi}, limits: {cpu: 200m, memory: 128Mi}}
```

**The zero-RBAC alternative — do it from your laptop or CI:**

```bash
kubectl delete pods -A --field-selector status.phase==Succeeded
kubectl delete pods -A --field-selector status.phase==Failed
kubectl get jobs -A -o json \
  | jq -r '.items[] | select(.status.completionTime != null) | "\(.metadata.namespace) \(.metadata.name)"' \
  | while read -r ns name; do
      age=$(( ($(date +%s) - $(date -d "$(kubectl get job -n $ns $name -o jsonpath='{.status.completionTime}')" +%s)) / 86400 ))
      [ "$age" -gt 7 ] && kubectl delete job -n "$ns" "$name"
    done
```

**Third option — a battle-tested tool:** [descheduler](https://github.com/kubernetes-sigs/descheduler) or `kube-janitor`. Don't reinvent this if you have many namespaces.

**Careful:** never delete `Completed` Pods belonging to a running **StatefulSet** or a Job whose logs you still need for an audit. Filter by label, not blanket-wide, in regulated environments.

</details>

---

### Task 4.3 — Make a Job that must not run twice (idempotency + locking)

Two CronJob runs overlap, or a Job is retried after a partial success. Prevent double-execution.

<details>
<summary>Show answer</summary>

Four layers of defence, in order of preference.

**Layer 1 — `concurrencyPolicy: Forbid` (CronJob only):**

```yaml
spec:
  concurrencyPolicy: Forbid
```

Prevents *scheduled* overlap. Does **not** prevent a retry of the same Job from re-running work.

**Layer 2 — deterministic Job names:**

```bash
JOB=billing-$(date -u +%Y%m%d)
kubectl create job $JOB --image=billing:1.0 --dry-run=client -o yaml | kubectl apply -f -
# second apply the same day → "AlreadyExists" if the job still exists → the apply is a no-op
```

Even better, make the name part of the *contract* and let creation fail loudly:

```bash
kubectl create job billing-20260909 --image=billing:1.0
# Error from server (AlreadyExists) → today's run already exists. Correct behaviour!
```

**Layer 3 — a Kubernetes Lease as a distributed lock (the elegant answer):**

```yaml
apiVersion: batch/v1
kind: Job
metadata: {name: billing-daily}
spec:
  backoffLimit: 2
  template:
    spec:
      serviceAccountName: billing       # needs create/get on coordination.k8s.io/leases
      restartPolicy: OnFailure
      containers:
        - name: billing
          image: bitnami/kubectl:1.33
          command: ["/bin/sh","-c"]
          args:
            - |
              set -eu
              LOCK="billing-$(date -u +%Y%m%d)"
              NOW=$(date -u +%FT%TZ)
              echo "▸ attempting to acquire lease $LOCK"
              if kubectl create -f - <<EOF
              apiVersion: coordination.k8s.io/v1
              kind: Lease
              metadata:
                name: $LOCK
                namespace: prod
                annotations:
                  holder: "$(hostname)"
                  acquired: "$NOW"
              spec:
                holderIdentity: "$(hostname)"
                leaseDurationSeconds: 86400
              EOF
              then
                echo "✅ lock acquired — running billing"
                # ... real work here ...
                echo "billing complete"
              else
                echo "⛔ lease $LOCK already exists — another run holds it. Exiting 0 (nothing to do)."
                exit 0
              fi
```

A `Lease` object is exactly designed for this (it's how kubelet heartbeats and leader election work). Creating it is **atomic**: only one caller wins, the rest get `AlreadyExists`. Exiting `0` means the Job counts as successful — correct, because the work *was* done, just not by this Pod.

**Layer 4 — application-level idempotency (always do this too):**

```python
# every operation carries an idempotency key
cursor.execute("""
  INSERT INTO billing_runs (run_key, started_at)
  VALUES (%s, now())
  ON CONFLICT (run_key) DO NOTHING
  RETURNING id
""", (f"billing-{date}",))
if cursor.rowcount == 0:
    print("already ran, skipping"); sys.exit(0)
```

**Layer 5 — leader election for long-running controllers** (not Jobs, but same family):

```bash
# in Go with client-go: leaderelection.LeaderElector on a Lease/ConfigMap
# in Python: kubernetes.leaderelection
```

```bash
# give the SA the minimum rights
kubectl create role lease-lock --verb=create,get,update --resource=leases -n prod
kubectl create rolebinding billing-lease --role=lease-lock --serviceaccount=prod:billing -n prod
```

</details>

---

### Task 4.4 — Debug a CronJob that silently stopped running

`LAST SCHEDULE` is 3 days old. Nothing is failing. Nothing is logged. Diagnose it.

<details>
<summary>Show answer</summary>

The diagnostic ladder, in order:

```bash
CJ=report; NS=prod

# 1. Is it suspended?
kubectl get cronjob $CJ -n $NS -o jsonpath='{.spec.suspend}{"\n"}'
# true → someone paused it: kubectl patch cronjob $CJ -n $NS -p '{"spec":{"suspend":false}}'

# 2. What does the controller say?
kubectl describe cronjob $CJ -n $NS | sed -n '/Events:/,$p'
# "Cannot determine if job needs to be started: too many missed start time (> 100).
#  Set or decrease .spec.startingDeadlineSeconds in seconds."   ← ⭐ THE CLASSIC

# 3. Check the status fields
kubectl get cronjob $CJ -n $NS -o json | jq '.status, .spec.startingDeadlineSeconds, .spec.concurrencyPolicy'

# 4. Is a previous Job still running (concurrencyPolicy: Forbid)?
kubectl get jobs -n $NS -l cronjob-name=$CJ
kubectl get jobs -n $NS -o custom-columns='NAME:.metadata.name,ACTIVE:.status.active,COMPLETE:.status.succeeded,FAILED:.status.failed,AGE:.metadata.creationTimestamp'

# 5. Is the Job failing instantly and being cleaned by ttlSecondsAfterFinished?
kubectl get events -n $NS --sort-by=.lastTimestamp | grep -i -E "$CJ|job" | tail -20

# 6. Is the cronjob-controller itself healthy?
kubectl -n kube-system logs kube-controller-manager-<node> | grep -i cronjob | tail -30
kubectl get leases -n kube-system | grep controller
# (on managed clusters — EKS/GKE — you can't see controller-manager logs; use events instead)

# 7. Is the namespace / quota blocking Job creation?
kubectl get resourcequota -n $NS -o yaml | grep -A20 status
kubectl get events -n $NS --field-selector reason=FailedCreate

# 8. Was the schedule silently changed?
kubectl get cronjob $CJ -n $NS -o jsonpath='{.spec.schedule}{"  tz="}{.spec.timeZone}{"\n"}'
```

**The most common root causes, ranked:**

| # | Cause | Signature | Fix |
|---|---|---|---|
| 1 | **Missed too many starts** | `describe` shows "too many missed start time (> 100)" | Set `startingDeadlineSeconds`. Then delete + recreate the CronJob to clear the condition |
| 2 | **Stuck Job + `concurrencyPolicy: Forbid`** | One Job `ACTIVE=1` for days | `activeDeadlineSeconds` on the Job; delete the stuck Job |
| 3 | **`suspend: true`** | `spec.suspend` is true | Un-suspend |
| 4 | **ResourceQuota full** | `FailedCreate` events: "exceeded quota" | Raise the quota |
| 5 | **Job fails instantly + short `ttl`** | No Jobs visible, but `failedJobsHistoryLimit` reached | Set `ttlSecondsAfterFinished` higher; check logs before they vanish |
| 6 | **RBAC** (if the Job needs API access) | `Forbidden` in Job logs | Fix the Role |
| 7 | **Wrong `timeZone`** | Runs at the wrong hour, not "not at all" | `spec.timeZone` |
| 8 | **Clock skew on the control plane** | Erratic scheduling | NTP on nodes |

**Fixing cause #1 properly:**

```bash
kubectl patch cronjob $CJ -n $NS --type=merge \
  -p '{"spec":{"startingDeadlineSeconds":900,"concurrencyPolicy":"Forbid"}}'

# if the CronJob is wedged, recreate it (safe — Jobs are separate objects)
kubectl get cronjob $CJ -n $NS -o yaml | grep -v resourceVersion | grep -v uid: > cj.yaml
kubectl delete cronjob $CJ -n $NS
kubectl apply -f cj.yaml

# then prove it works without waiting for the schedule
kubectl create job --from=cronjob/$CJ ${CJ}-manual-$(date +%s) -n $NS
kubectl logs -n $NS -f job/${CJ}-manual-$(date +%s)
```

**Prevention checklist for every CronJob you ever write:**
- [ ] `startingDeadlineSeconds` set (e.g. 900)
- [ ] `concurrencyPolicy` explicit (`Forbid` unless you know otherwise)
- [ ] `activeDeadlineSeconds` on the Job template
- [ ] `backoffLimit` explicit
- [ ] `successfulJobsHistoryLimit` + `failedJobsHistoryLimit` set
- [ ] `ttlSecondsAfterFinished` set (but long enough to read logs)
- [ ] `timeZone` set if the schedule is human-meaningful
- [ ] An **alert** on "CronJob last successful run > 2× period ago" — this is the only thing that catches silent stops

Prometheus alert rule for that last point:

```yaml
- alert: CronJobNotRunning
  expr: |
    time() - (kube_cronjob_next_schedule_time > 0) > 3600
    and on(cronjob) (kube_cronjob_status_last_successful_time == 0
      or (time() - kube_cronjob_status_last_successful_time) > 172800)
  for: 1h
  labels: {severity: warning}
  annotations:
    summary: "CronJob {{ $labels.cronjob }} hasn't succeeded in 48h"
```

Better and simpler with kube-state-metrics:

```yaml
- alert: CronJobStale
  expr: time() - max by (namespace, cronjob) (kube_cronjob_status_last_successful_time) > 90000
  for: 15m
  labels: {severity: warning}
```

</details>

---

### Task 4.5 — Run a Job that needs a Pod's data (shared volume) and clean up after itself

A report job must read the app's log volume, produce a CSV, and upload it — then leave no trace.

<details>
<summary>Show answer</summary>

The catch: a PVC with `ReadWriteOnce` **cannot be mounted by two Pods on different nodes**. So either:
- (a) force the Job onto the same node as the app Pod, or
- (b) use RWX storage, or
- (c) **stream the data instead of sharing the disk** (usually the best answer), or
- (d) run the Job *as a sidecar-free* copy step from inside the app Pod.

**Option (a) — node pinning:**

```bash
NODE=$(kubectl get pod -l app=shop -o jsonpath='{.items[0].spec.nodeName}')
cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata: {name: report-on-$NODE}
spec:
  backoffLimit: 1
  ttlSecondsAfterFinished: 600
  template:
    spec:
      restartPolicy: Never
      nodeName: $NODE                  # ⭐ bypasses the scheduler entirely
      containers:
        - name: report
          image: python:3.13-alpine
          command: ["sh","-c","wc -l /data/app.log && cp /data/app.log /tmp && echo uploaded"]
          volumeMounts: [{name: data, mountPath: /data, readOnly: true}]
          resources: {requests: {cpu: 100m, memory: 128Mi}}
      volumes:
        - name: data
          persistentVolumeClaim: {claimName: shop-data}
EOF
kubectl wait --for=condition=complete job/report-on-$NODE --timeout=300s
kubectl logs job/report-on-$NODE
```

⚠️ `nodeName` skips the scheduler — no resource checks, no admission-based placement. Use `nodeSelector: {kubernetes.io/hostname: $NODE}` instead if you want the scheduler to still validate capacity.

**Option (c) — stream, don't share (the production answer):**

```yaml
apiVersion: batch/v1
kind: Job
metadata: {name: log-report}
spec:
  backoffLimit: 1
  ttlSecondsAfterFinished: 300
  template:
    spec:
      restartPolicy: Never
      serviceAccountName: log-reader           # RBAC: get/list pods, get pods/log
      containers:
        - name: report
          image: bitnami/kubectl:1.33
          command: ["/bin/sh","-c"]
          args:
            - |
              set -eu
              OUT=/tmp/report-$(date -u +%F).csv
              echo "pod,lines,errors" > $OUT
              for p in $(kubectl get pods -n prod -l app=shop -o name); do
                L=$(kubectl logs -n prod $p --since=24h 2>/dev/null | wc -l)
                E=$(kubectl logs -n prod $p --since=24h 2>/dev/null | grep -ci error || true)
                echo "$p,$L,$E" >> $OUT
              done
              cat $OUT
              # upload, then shred
              curl -sf -X POST -F "file=@$OUT" https://reports.internal/upload && echo "✅ uploaded"
              shred -u $OUT 2>/dev/null || rm -f $OUT
          resources: {requests: {cpu: 100m, memory: 128Mi}, limits: {cpu: 500m, memory: 256Mi}}
```

No shared volume at all → no RWO conflict, no node pinning, works with 50 replicas.

**Cleanup that's guaranteed even on failure** — `ttlSecondsAfterFinished` handles the Job and its Pods. For anything else (temp files, cloud resources), use a `preStop` hook plus `trap`:

```yaml
command: ["/bin/sh","-c"]
args:
  - |
    cleanup() { echo "cleaning up"; rm -rf /tmp/work; }
    trap cleanup EXIT INT TERM
    mkdir -p /tmp/work
    # ... work ...
```

`trap … EXIT` fires on normal exit, on error (with `set -e`), and on SIGTERM — which is exactly what Kubernetes sends when `activeDeadlineSeconds` expires or you delete the Job.

</details>

---

## 4.11 Checklist

- [ ] Explain why `restartPolicy: Always` is invalid in a Job, and the practical difference between `Never` and `OnFailure`
- [ ] Write a Job with `completions`, `parallelism`, `backoffLimit`, `activeDeadlineSeconds`, `ttlSecondsAfterFinished`
- [ ] Use `completionMode: Indexed` and read `JOB_COMPLETION_INDEX`
- [ ] Wait for a Job in CI with `kubectl wait --for=condition=complete`
- [ ] Write a CronJob with `timeZone`, `concurrencyPolicy`, `startingDeadlineSeconds`
- [ ] Trigger a CronJob manually with `kubectl create job --from=cronjob/…`
- [ ] Explain the "too many missed start times (>100)" failure and how to prevent it
- [ ] Use init containers for wait-for-dependency, permission fixing, and config rendering
- [ ] Explain the Pod resource-request rule `max(sum(main), max(init))`
- [ ] Write a native sidecar with `restartPolicy: Always` on an init container
- [ ] Run a database migration as a pre-upgrade Helm hook with `backoffLimit: 0`
- [ ] Implement a distributed lock with a `Lease` object

**Next → [`08-PROJECT-5-storage-statefulset.md`](08-PROJECT-5-storage-statefulset.md)** — PVCs, StatefulSets, and why your database needs both.

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish%20Kumar%20Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn → <https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260>
🐙 GitHub → <https://github.com/3558Bhk>

*Built for engineers who learn by breaking things on purpose.*

</div>
