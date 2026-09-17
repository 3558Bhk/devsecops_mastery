# 💾 Project 5 — Storage, PVCs & StatefulSets

> **Time:** 2.5 hours · **Prereq:** [Project 4](07-PROJECT-4-jobs-cronjobs-cli.md)
>
> **What you'll learn:** the PV / PVC / StorageClass triangle, why a PVC sits in `Pending`, access modes and what they really mean, StatefulSets with stable identity and per-Pod storage, and how to back up and restore state.
>
> **This is the project where people get stuck.** Everything below has the exact error message you'll see and the exact fix.

---

## 5.1 The 60-second theory

```
StorageClass    "here's HOW to make storage"     (written by the cluster admin)
     │  dynamic provisioning
     ▼
PersistentVolume (PV)   "here IS a real disk"    (created by the provisioner, or by hand)
     ▲
     │  bound 1:1
     │
PersistentVolumeClaim (PVC)  "I want 10Gi RWO"   (written by the app developer)
     ▲
     │  mounted
     │
Pod
```

**Why the indirection?** So an app developer never needs to know whether they're on AWS, GCP, or bare metal. They ask for "10Gi, ReadWriteOnce, fast class" and the cluster figures out the rest. That's the whole design goal.

Docker equivalent:

| Docker | Kubernetes |
|---|---|
| `docker volume create data` | PV (usually created automatically) |
| `-v data:/var/lib/x` | PVC + `volumeMounts` |
| the local volume driver | StorageClass + CSI driver |
| `-v $(pwd)/x:/x` (bind mount) | `hostPath` — **dev only** |
| `--tmpfs /tmp` | `emptyDir: {medium: Memory}` |
| nothing | `emptyDir` — scratch space that dies with the Pod |

---

## 5.2 Step 1 — Volume types you'll use every week

### `emptyDir` — scratch space

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata: {name: emptydir-demo}
spec:
  volumes:
    - name: scratch
      emptyDir:
        sizeLimit: 500Mi          # ⭐ protects the node's disk
        # medium: Memory          # tmpfs — fast, but counts against the memory limit
  containers:
    - name: writer
      image: busybox:1.37
      command: ["sh","-c","echo hello > /scratch/msg.txt; sleep 3600"]
      volumeMounts: [{name: scratch, mountPath: /scratch}]
    - name: reader
      image: busybox:1.37
      command: ["sh","-c","sleep 5; cat /scratch/msg.txt; sleep 3600"]
      volumeMounts: [{name: scratch, mountPath: /scratch}]
EOF
kubectl logs emptydir-demo -c reader
# hello
```

**Lifetime rules (memorise these):**

| Event | emptyDir data |
|---|---|
| Container crashes and restarts (same Pod) | ✅ survives |
| Pod is deleted | ❌ gone |
| Pod is evicted | ❌ gone |
| Pod is rescheduled to another node | ❌ gone |
| Node reboots | ❌ gone |

Use for: caches, temp files, sharing between containers in a Pod, sort/merge scratch. **Never for anything you care about.**

### `hostPath` — the node's own disk

```yaml
volumes:
  - name: host-data
    hostPath:
      path: /var/log
      type: Directory          # "" | DirectoryOrCreate | File | FileOrCreate | Socket | CharDevice | BlockDevice
```

Dev/debug only. It pins you to a node, it's a security hole (`hostPath: /` = root on the node), and `baseline` Pod Security Admission blocks most of it. Legitimate uses: DaemonSets that read node-level paths (`/var/log/containers` for log shippers, `/var/lib/containerd` for GC tools, `/run/containerd/containerd.sock` for build agents).

### tmpfs

```yaml
volumes:
  - name: ram
    emptyDir: {medium: Memory, sizeLimit: 128Mi}
```

Real RAM-backed filesystem. Great for secrets-in-memory and fast scratch. ⚠️ **Counts toward the container's memory limit** — writing 128 Mi into it can OOMKill you.

---

## 5.3 Step 2 — Your first PVC

First, see what your cluster offers:

```bash
kubectl get storageclass
```

```
NAME                 PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION
standard (default)   rancher.io/local-path   Delete          WaitForFirstConsumer   false
```

| Cluster | Default StorageClass | Provisioner |
|---|---|---|
| kind | `standard` | `rancher.io/local-path` (hostPath under the hood) |
| minikube | `standard` | `k8s.io/minikube-hostpath` |
| Docker Desktop | `hostpath` | `docker.io/hostpath` |
| k3d/k3s | `local-path` | `rancher.io/local-path` |
| EKS | *(none by default)* | `ebs.csi.aws.com` — you must install it |
| GKE | `standard` / `premium-rwo` | `pd.csi.storage.gke.io` |
| AKS | `default` (managed-premium) | `disk.csi.azure.com` |
| kubeadm (bare metal) | *(none)* | install Longhorn / OpenEBS / NFS / Rook-Ceph |

`pvc.yaml`:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: app-data
  labels: {app: shop}
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: standard         # omit to use the cluster default
  volumeMode: Filesystem             # or Block (raw device, rare)
  resources:
    requests:
      storage: 1Gi
```

```bash
kubectl apply -f pvc.yaml
kubectl get pvc
```

```
NAME       STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   AGE
app-data   Pending                                     standard       3s
```

**`Pending` is expected here** — the binding mode is `WaitForFirstConsumer`, so nothing is provisioned until a Pod actually asks for it.

```bash
kubectl describe pvc app-data | sed -n '/Events:/,$p'
# Normal  WaitForFirstConsumer  ...  persistentvolume-controller
#   waiting for first consumer to be created before binding
```

Now use it:

`pvc-pod.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata: {name: writer}
spec:
  replicas: 1
  selector: {matchLabels: {app: writer}}
  strategy:
    type: Recreate                # ⭐ RWO volume: only ONE pod may hold it
  template:
    metadata: {labels: {app: writer}}
    spec:
      containers:
        - name: app
          image: busybox:1.37
          command:
            - sh
            - -c
            - |
              touch /data/counter
              N=$(cat /data/counter)
              while true; do
                N=$((N+1))
                echo $N > /data/counter
                echo "$(date -u +%T) tick $N"
                echo "$(date -u +%T) tick $N" >> /data/history.log
                sleep 5
              done
          volumeMounts: [{name: data, mountPath: /data}]
          resources: {requests: {cpu: 20m, memory: 16Mi}, limits: {cpu: 100m, memory: 32Mi}}
      volumes:
        - name: data
          persistentVolumeClaim: {claimName: app-data}
```

```bash
kubectl apply -f pvc-pod.yaml
kubectl rollout status deploy/writer
kubectl get pvc
```

```
NAME       STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS
app-data   Bound    pvc-8f3a2b1c-4d5e-6f70-8192-a3b4c5d6e7f8   1Gi        RWO            standard
```

```bash
kubectl get pv
kubectl describe pv pvc-8f3a2b1c     # shows the Claim, Reclaim Policy, the backing path
kubectl logs deploy/writer --tail=5
```

### Prove the data survives a Pod replacement

```bash
kubectl logs deploy/writer --tail=2       # tick 47, tick 48
kubectl delete pod -l app=writer
kubectl rollout status deploy/writer
kubectl logs deploy/writer --tail=3
# tick 49, tick 50, tick 51     ← CONTINUED, not restarted from 1
kubectl exec deploy/writer -- cat /data/counter
kubectl exec deploy/writer -- head -3 /data/history.log
```

**That's the point of a PVC.** The Pod was destroyed and recreated (possibly on another node) and the counter carried on. Try the same with `emptyDir` and it resets to 1.

> ⚠️ **Why `strategy: Recreate` above?** With `ReadWriteOnce` and a rolling update, the new Pod starts while the old one still holds the volume → `Multi-Attach error for volume … Volume is already exclusively attached to one node`. `Recreate` avoids it at the cost of downtime. The *real* fix is a StatefulSet with per-Pod PVCs (§5.6).

---

## 5.4 Step 3 — Access modes, in depth

| Mode | Abbr | Really means | Typical backing |
|---|---|---|---|
| ReadWriteOnce | **RWO** | Read-write by **one NODE** | EBS, GCE PD, Azure Disk, local-path |
| ReadOnlyMany | **ROX** | Read-only by many nodes | NFS, CephFS, EFS, Azure Files |
| ReadWriteMany | **RWX** | Read-write by many nodes | NFS, CephFS, EFS, Azure Files, Longhorn, GlusterFS |
| ReadWriteOncePod | **RWOP** | Read-write by **one POD** (strict; GA in v1.29) | CSI drivers that opt in |

> 🔑 **RWO = one node, not one Pod.** Two Pods on the *same* node can both mount an RWO PVC (on most CSI drivers). Kubernetes does not stop them. If you truly need single-Pod exclusivity, use `ReadWriteOncePod`.

### Demonstrate the Multi-Attach failure

```bash
kubectl scale deploy/writer --replicas=3
kubectl get pods -l app=writer -w
```

```
writer-abc   1/1   Running            0   5m
writer-def   0/1   ContainerCreating  0   10s     ← stuck forever
writer-ghi   0/1   ContainerCreating  0   10s     ← stuck forever
```

```bash
kubectl describe pod -l app=writer | grep -A3 "Multi-Attach"
# Warning  FailedAttachVolume  ...  Multi-Attach error for volume "pvc-8f3a…"
#                                  Volume is already exclusively attached to one node and can't be attached to another
```

Three fixes:

```bash
# Fix 1: don't share — go back to one replica
kubectl scale deploy/writer --replicas=1

# Fix 2: RWX storage (if your cluster has it)
kubectl patch pvc app-data -p '{"spec":{"accessModes":["ReadWriteMany"]}}'   # ⚠️ usually immutable;
                                                                            #    you must recreate the PVC

# Fix 3 (the right one): StatefulSet with volumeClaimTemplates → §5.6
```

### Which mode do I need?

| Scenario | Mode |
|---|---|
| Single-instance database | RWO (or RWOP) |
| Replicated database, one PVC per replica | RWO × N (StatefulSet) |
| Shared uploads directory across 5 app replicas | **RWX** (NFS/EFS/CephFS) |
| Read-only reference data / ML model weights | ROX |
| App scratch that must survive container restarts | `emptyDir` |
| Log aggregation DaemonSet reading `/var/log` | `hostPath` |

---

## 5.5 Step 4 — Reclaim policy, expansion, and the dangers of `Delete`

`storageclass.yaml`:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: app-data
provisioner: rancher.io/local-path       # ← must match your cluster's CSI driver
reclaimPolicy: Retain                    # ⭐ Delete (default) destroys the data
allowVolumeExpansion: true               # lets you grow PVCs later
volumeBindingMode: WaitForFirstConsumer  # provision in the Pod's zone
mountOptions: []
parameters: {}
# EBS example:
# provisioner: ebs.csi.aws.com
# parameters: {type: gp3, encrypted: "true", fsType: ext4}
# GCE PD example:
# provisioner: pd.csi.storage.gke.io
# parameters: {type: pd-ssd}
```

```bash
kubectl apply -f storageclass.yaml
kubectl get sc
```

| `reclaimPolicy` | When the PVC is deleted |
|---|---|
| **`Delete`** (default) | The PV **and the underlying disk are destroyed**. Data gone, no undo, no confirmation. |
| **`Retain`** | PV becomes `Released`. Data intact. You must manually clean it up and can re-bind it. |

```bash
# change the policy of an existing StorageClass (only affects NEWLY created PVs)
kubectl patch storageclass standard -p '{"reclaimPolicy":"Retain"}'
kubectl get sc standard -o jsonpath='{.reclaimPolicy}{"\n"}'
```

**The `Retain` recovery dance** (you deleted a PVC and want the data back):

```bash
kubectl get pv
# pvc-8f3a…   1Gi   RWO   Retain   Released   default/app-data   app-data   10m

kubectl get pv pvc-8f3a… -o yaml > pv-backup.yaml    # save it!

# clear the claim reference so it can be re-bound
kubectl patch pv pvc-8f3a… -p '{"spec":{"claimRef":{"resourceVersion":null,"uid":null}}}'
kubectl get pv pvc-8f3a…      # STATUS: Available

# recreate the PVC pointing at that exact PV
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: app-data-restored}
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: app-data
  volumeName: pvc-8f3a2b1c-…       # ⭐ bind to THIS pv
  resources: {requests: {storage: 1Gi}}
EOF
kubectl get pvc app-data-restored   # Bound
```

### Expanding a volume

```bash
kubectl get sc app-data -o jsonpath='{.allowVolumeExpansion}'; echo    # must be true
kubectl patch pvc app-data -p '{"spec":{"resources":{"requests":{"storage":"5Gi"}}}}'
kubectl get pvc app-data -w
# 1Gi → 5Gi. Most CSI drivers also need the FILESYSTEM grown, which may require a Pod restart:
kubectl rollout restart deploy/writer
kubectl exec deploy/writer -- df -h /data
```

Rules:
- **Grow only, never shrink.** Shrinking = create a new smaller PVC, `rsync`, swap the reference.
- The *StorageClass* must allow expansion.
- Some drivers require the Pod to restart for the filesystem resize (`FileSystemResizePending` condition on the PVC).
- You edit the **PVC**, not the PV.

```bash
kubectl describe pvc app-data | sed -n '/Conditions:/,/Events:/p'
```

---

## 5.6 Step 5 — StatefulSet: the right way to run state

A StatefulSet gives you three guarantees a Deployment cannot:

| Guarantee | What it means |
|---|---|
| **Stable identity** | Pods are `db-0`, `db-1`, `db-2` — deterministic names, recreated with the same name |
| **Stable storage** | Each Pod gets its **own** PVC from `volumeClaimTemplates`; it keeps it across reschedules |
| **Ordered lifecycle** | Scaled up `0→1→2`, scaled down `2→1→0`, updated in reverse ordinal order |

Plus **stable DNS**: `db-0.db.<ns>.svc.cluster.local` always resolves to that specific Pod.

### A complete, correct StatefulSet

`statefulset.yaml`:

```yaml
apiVersion: v1
kind: Secret
metadata: {name: pg-creds}
stringData:
  username: postgres
  password: "L3arn-K8s!"
---
# ── HEADLESS service: gives each Pod a stable DNS name ──
apiVersion: v1
kind: Service
metadata:
  name: db
  labels: {app: db}
spec:
  clusterIP: None              # ⭐ headless — DNS returns POD IPs, no load balancing
  selector: {app: db}
  ports: [{name: postgres, port: 5432, targetPort: 5432}]
---
# ── Regular service for clients that don't care which replica ──
apiVersion: v1
kind: Service
metadata:
  name: db-read
  labels: {app: db}
spec:
  type: ClusterIP
  selector: {app: db}
  ports: [{name: postgres, port: 5432}]
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: db
  labels: {app: db}
spec:
  serviceName: db              # ⭐ MUST reference the headless Service above
  replicas: 3
  podManagementPolicy: OrderedReady   # OrderedReady (default) | Parallel
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      partition: 0             # only Pods with ordinal >= partition are updated (canary!)
      maxUnavailable: 1        # v1.31+ for StatefulSets
  revisionHistoryLimit: 5
  selector:
    matchLabels: {app: db}
  template:
    metadata:
      labels: {app: db}
    spec:
      terminationGracePeriodSeconds: 60
      securityContext:
        fsGroup: 999           # ⭐ postgres group — makes the PVC writable by the container
      containers:
        - name: postgres
          image: postgres:17-alpine
          ports:
            - {name: postgres, containerPort: 5432}
          env:
            - name: POSTGRES_USER
              valueFrom: {secretKeyRef: {name: pg-creds, key: username}}
            - name: POSTGRES_PASSWORD
              valueFrom: {secretKeyRef: {name: pg-creds, key: password}}
            - name: POSTGRES_DB
              value: app
            - name: PGDATA
              value: /var/lib/postgresql/data/pgdata   # ⭐ subdirectory! see the warning below
            - name: POD_NAME
              valueFrom: {fieldRef: {fieldPath: metadata.name}}
          readinessProbe:
            exec:
              command: ["sh","-c","pg_isready -U $POSTGRES_USER -d $POSTGRES_DB -h 127.0.0.1"]
            initialDelaySeconds: 10
            periodSeconds: 10
            failureThreshold: 6
          livenessProbe:
            exec:
              command: ["sh","-c","pg_isready -U $POSTGRES_USER -h 127.0.0.1"]
            initialDelaySeconds: 45
            periodSeconds: 20
            failureThreshold: 6
          lifecycle:
            preStop:
              exec:
                command: ["sh","-c","pg_ctl -D $PGDATA stop -m fast || true"]
          resources:
            requests: {cpu: 250m, memory: 512Mi}
            limits:   {cpu: "1",   memory: 1Gi}
          volumeMounts:
            - name: data
              mountPath: /var/lib/postgresql/data
  volumeClaimTemplates:            # ⭐ ONE PVC PER POD, created automatically
    - metadata:
        name: data
        labels: {app: db}
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: standard
        resources:
          requests: {storage: 5Gi}
```

> 🔑 **`PGDATA` must be a subdirectory of the mount.** Postgres refuses to initialise in a directory containing `lost+found`, which every freshly-formatted ext4 volume has. Hence `PGDATA=/var/lib/postgresql/data/pgdata`. This is *the* most common Postgres-on-Kubernetes failure, and the error is:
> `initdb: directory "/var/lib/postgresql/data" exists but is not empty … "lost+found"`

```bash
kubectl apply -f statefulset.yaml
kubectl get pods -l app=db -w
```

```
db-0   0/1   Pending             0   0s
db-0   0/1   Pending             0   0s
db-0   0/1   ContainerCreating   0   0s
db-0   0/1   Running             0   5s
db-0   1/1   Running             0   15s
db-1   0/1   Pending             0   0s      ← ONLY starts after db-0 is Ready
db-1   0/1   ContainerCreating   0   0s
db-1   1/1   Running             0   20s
db-2   0/1   Pending             0   0s
db-2   1/1   Running             0   45s
```

**Ordered.** `db-1` did not start until `db-0` was Ready. That's `podManagementPolicy: OrderedReady`.

```bash
kubectl get statefulset,pvc,pv,pods -l app=db
```

```
NAME                   READY   AGE
statefulset.apps/db    3/3     2m

NAME                                     STATUS   VOLUME     CAPACITY   ACCESS MODES   STORAGECLASS
persistentvolumeclaim/data-db-0          Bound    pvc-aaa…   5Gi        RWO            standard
persistentvolumeclaim/data-db-1          Bound    pvc-bbb…   5Gi        RWO            standard
persistentvolumeclaim/data-db-2          Bound    pvc-ccc…   5Gi        RWO            standard

NAME        READY   STATUS    RESTARTS   AGE
pod/db-0    1/1     Running   0          2m
pod/db-1    1/1     Running   0          100s
pod/db-2    1/1     Running   0          60s
```

**PVC names are deterministic:** `<volumeClaimTemplate name>-<statefulset name>-<ordinal>`. Delete `db-1` and the replacement re-attaches `data-db-1` with all its data.

### The stable DNS in action

```bash
kubectl run dns --rm -it --image=nicolaka/netshoot --restart=Never -- bash
```

```bash
# inside:
dig +short db.default.svc.cluster.local          # headless → all three POD IPs
dig +short db-0.db.default.svc.cluster.local     # just db-0
dig +short db-1.db.default.svc.cluster.local
dig +short db-read.default.svc.cluster.local     # ClusterIP → one virtual IP

psql "host=db-0.db.default.svc.cluster.local user=postgres dbname=app" -c 'select 1'
psql "host=db-read.default user=postgres dbname=app" -c 'select inet_server_addr()'
```

### Prove identity and storage survive

```bash
# write distinct data to each replica
for i in 0 1 2; do
  kubectl exec db-$i -- psql -U postgres -d app \
    -c "CREATE TABLE IF NOT EXISTS whoami(id serial primary key, pod text, at timestamptz default now());" \
    -c "INSERT INTO whoami(pod) VALUES ('$i');"
done

for i in 0 1 2; do
  echo "── db-$i ──"
  kubectl exec db-$i -- psql -U postgres -d app -tAc 'select pod, count(*) from whoami group by pod;'
done

# delete db-1 and watch it come back with its data
kubectl delete pod db-1
kubectl get pods -l app=db -w
kubectl exec db-1 -- psql -U postgres -d app -tAc 'select pod, count(*) from whoami group by pod;'
# → 1 | 1        ← DATA SURVIVED, because the PVC data-db-1 was never deleted
```

### Scale it

```bash
kubectl scale statefulset db --replicas=5
kubectl get pods -l app=db -w        # db-3 then db-4, in order
kubectl scale statefulset db --replicas=3
kubectl get pods -l app=db -w        # db-4 then db-3, in REVERSE order
kubectl get pvc -l app=db            # ⚠️ data-db-3 and data-db-4 STILL EXIST
```

> ⚠️ **Scaling down a StatefulSet does NOT delete the PVCs.** This is deliberate (data safety) and it's why teams accumulate orphaned cloud disks. Clean up explicitly when you mean it:
> ```bash
> kubectl delete pvc data-db-3 data-db-4
> ```
> Scaling back up to 5 re-uses those PVCs and their data — which is either a feature (rejoin with history) or a disaster (stale data rejoins a cluster). Know which you're doing.

### Ordered vs parallel pod management

```bash
kubectl patch statefulset db --type=merge -p '{"spec":{"podManagementPolicy":"Parallel"}}'
# → error! podManagementPolicy is IMMUTABLE. You must delete and recreate the StatefulSet
#   (with --cascade=orphan to keep the Pods running during the swap)
kubectl delete statefulset db --cascade=orphan     # pods survive
kubectl apply -f statefulset.yaml                  # re-adopted
```

`Parallel` is right for: stateless-ish sharded workers, Kafka brokers that bootstrap together, anything where ordinal order doesn't matter. `OrderedReady` is right for: primary/replica databases, anything doing sequential cluster formation.

### Canary a StatefulSet with `partition`

```bash
# update only db-2 (the highest ordinal) to a new image
kubectl patch statefulset db --type=merge -p '
spec:
  updateStrategy:
    rollingUpdate:
      partition: 2
'
kubectl set image statefulset/db postgres=postgres:17-alpine   # or a different tag
kubectl get pods -l app=db -o custom-columns='NAME:.metadata.name,IMAGE:.spec.containers[0].image'
# only db-2 changes; db-0 and db-1 stay on the old revision

# happy? roll the rest
kubectl patch statefulset db --type=merge -p '{"spec":{"updateStrategy":{"rollingUpdate":{"partition":0}}}}'
```

This is a genuinely useful pattern: test a database upgrade on one replica before touching the primary.

---

## 5.7 Step 6 — Replication (making it a real cluster)

Three independent Postgres instances is not a database cluster. Let's wire up streaming replication so the StatefulSet's stable DNS actually earns its keep.

`pg-cluster.yaml` (the interesting parts — extends the StatefulSet above):

```yaml
apiVersion: v1
kind: ConfigMap
metadata: {name: pg-bootstrap}
data:
  bootstrap.sh: |
    #!/bin/sh
    set -eu
    HOSTNAME=$(hostname)                       # db-0, db-1, db-2
    ORDINAL=${HOSTNAME##*-}

    # ── every node: replication user + pg_hba ──
    if [ "$ORDINAL" = "0" ]; then
      echo "▸ db-0: starting as PRIMARY"
      # postgres image runs initdb itself on first start
      cat >> "$PGDATA/pg_hba.conf" 2>/dev/null <<HBA || true
    host replication replicator 0.0.0.0/0 scram-sha-256
    HBA
      cat >> "$PGDATA/postgresql.conf" 2>/dev/null <<CONF || true
    wal_level = replica
    max_wal_senders = 10
    max_replication_slots = 10
    hot_standby = on
    listen_addresses = '*'
    CONF
    else
      echo "▸ $HOSTNAME: waiting for the primary to accept connections"
      until pg_isready -h db-0.db -U postgres; do sleep 2; done
      if [ ! -s "$PGDATA/PG_VERSION" ]; then
        echo "▸ $HOSTNAME: base backup from db-0"
        rm -rf "$PGDATA"/*
        PGPASSWORD="$POSTGRES_PASSWORD" pg_basebackup \
          -h db-0.db -U replicator -D "$PGDATA" -Fp -Xs -P -R
      fi
      echo "standby_mode = on" >> "$PGDATA/postgresql.auto.conf" 2>/dev/null || true
    fi
```

In production you would **not** hand-roll this. Use an operator:

| Operator | Databases | Notes |
|---|---|---|
| **CloudNativePG** | PostgreSQL | CNCF, excellent, does replication/failover/backups/PITR |
| **Zalando postgres-operator** | PostgreSQL | Battle-tested, Spilo images |
| **Crunchy PGO** | PostgreSQL | Enterprise features |
| **Strimzi** | Kafka | The de-facto standard |
| **MongoDB Community Operator** | MongoDB | Replica sets |
| **Oracle MySQL Operator** | MySQL/InnoDB Cluster | Group Replication |
| **KubeBlocks** | Many | Multi-engine, rising fast |
| **Vitess Operator** | MySQL at scale | YouTube's sharding layer |

```bash
helm repo add cnpg https://cloudnative-pg.github.io/charts
helm install cnpg cnpg/cloudnative-pg -n cnpg-system --create-namespace
```

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata: {name: shop-db, namespace: prod}
spec:
  instances: 3
  imageName: ghcr.io/cloudnative-pg/postgresql:17.4
  primaryUpdateStrategy: unsupervised
  storage:
    size: 20Gi
    storageClass: app-data
  bootstrap:
    initdb: {database: app, owner: app, secret: {name: pg-creds}}
  replicationSlots: {highAvailability: {enabled: true}}
  backup:
    barmanObjectStore:
      destinationPath: s3://my-bucket/shop-db
      wal: {compression: gzip}
    retentionPolicy: "30d"
  monitoring: {enablePodMonitor: true}
  resources:
    requests: {cpu: 500m, memory: 1Gi}
    limits:   {memory: 4Gi}
```

```bash
kubectl get cluster -n prod
# NAME      AGE   INSTANCES   READY   STATUS                     PRIMARY
# shop-db   5m    3           3       Cluster in healthy state   shop-db-1
kubectl get pods -n prod -l cnpg.io/cluster=shop-db
kubectl cnpg status shop-db -n prod      # plugin: krew install cnpg
```

That single object gives you streaming replication, automatic failover, continuous WAL archiving to S3, point-in-time recovery, rolling upgrades, and Pod monitors. **This is what running Postgres on Kubernetes looks like in 2026.** See [Project 13](16-PROJECT-13-databases.md) for all six database engines.

---

## 5.8 Step 7 — Backup and restore

### 5.8.1 Logical backup (pg_dump) — portable, slow, partial

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: pg-backups}
spec:
  accessModes: [ReadWriteOnce]
  resources: {requests: {storage: 10Gi}}
EOF
```

Backup Job:

```yaml
apiVersion: batch/v1
kind: Job
metadata: {name: pg-backup-manual}
spec:
  backoffLimit: 1
  activeDeadlineSeconds: 1800
  ttlSecondsAfterFinished: 86400
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
              OUT=/backups/app-$STAMP.dump
              echo "▸ dumping from db-0.db"
              pg_dump -h db-0.db -U "$POSTGRES_USER" -d app \
                      --format=custom --compress=6 --file="$OUT.tmp"
              mv "$OUT.tmp" "$OUT"
              ls -lh "$OUT"
              echo "▸ verifying archive integrity"
              pg_restore --list "$OUT" > /dev/null && echo "✅ valid"
              echo "▸ pruning >14d"
              find /backups -name 'app-*.dump' -mtime +14 -print -delete
          env:
            - {name: POSTGRES_USER,     valueFrom: {secretKeyRef: {name: pg-creds, key: username}}}
            - {name: PGPASSWORD,        valueFrom: {secretKeyRef: {name: pg-creds, key: password}}}
          volumeMounts: [{name: backups, mountPath: /backups}]
          resources: {requests: {cpu: 200m, memory: 256Mi}, limits: {cpu: "1", memory: 1Gi}}
      volumes:
        - name: backups
          persistentVolumeClaim: {claimName: pg-backups}
```

```bash
kubectl apply -f backup-job.yaml
kubectl wait --for=condition=complete job/pg-backup-manual --timeout=600s
kubectl logs job/pg-backup-manual
```

Restore:

```bash
kubectl run restore --rm -it --restart=Never --image=postgres:17-alpine \
  --overrides='{"spec":{"containers":[{"name":"restore","image":"postgres:17-alpine","stdin":true,"tty":true,
     "command":["sh"],"env":[
       {"name":"POSTGRES_USER","value":"postgres"},
       {"name":"PGPASSWORD","valueFrom":{"secretKeyRef":{"name":"pg-creds","key":"password"}}}],
     "volumeMounts":[{"name":"b","mountPath":"/backups"}]}],
     "volumes":[{"name":"b","persistentVolumeClaim":{"claimName":"pg-backups"}}]}}'
```

```sh
# inside:
ls -lh /backups
pg_restore -h db-0.db -U postgres -d app --clean --if-exists --no-owner /backups/app-20260909-120000.dump
pg_restore -l /backups/app-20260909-120000.dump | head -20    # inspect first
psql -h db-0.db -U postgres -d app -c 'select count(*) from whoami;'
```

### 5.8.2 Physical backup — snapshot the volume

```bash
# AWS: snapshot the EBS volume behind the PV
PV=$(kubectl get pvc data-db-0 -o jsonpath='{.spec.volumeName}')
VOL=$(kubectl get pv $PV -o jsonpath='{.spec.csi.volumeHandle}')
aws ec2 create-snapshot --volume-id $VOL --description "db-0 $(date -u +%F)" --tag-specifications \
  'ResourceType=snapshot,Tags=[{Key=cluster,Value=learn}]'

# GCP
kubectl get pv $PV -o jsonpath='{.spec.csi.volumeHandle}'
gcloud compute disks snapshot <disk> --snapshot-names=backup-$(date +%s)
```

⚠️ **A raw volume snapshot of a running database can be inconsistent.** Quiesce first:

```bash
kubectl exec db-0 -- psql -U postgres -c 'SELECT pg_backup_start($$manual$$, true);'
# ... snapshot ...
kubectl exec db-0 -- psql -U postgres -c 'SELECT pg_backup_stop();'
```

Or use filesystem-level snapshots via the CSI driver (`VolumeSnapshot` CRD):

```bash
kubectl get volumesnapshotclasses
```

```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata: {name: db-0-snap}
spec:
  volumeSnapshotClassName: csi-hostpath-snapclass     # ← from your CSI driver
  source:
    persistentVolumeClaimName: data-db-0
```

```bash
kubectl apply -f snapshot.yaml
kubectl get volumesnapshot
kubectl describe volumesnapshot db-0-snap | grep -i -E 'ready|error'
```

Restore into a **new** PVC:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: data-db-0-restored}
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: standard
  resources: {requests: {storage: 5Gi}}
  dataSource:
    name: db-0-snap
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
```

### 5.8.3 Velero — cluster-wide objects + volumes

```bash
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm repo update
helm install velero vmware-tanzu/velero -n velero --create-namespace -f velero-values.yaml
```

```bash
velero install \
  --provider aws --plugins velero/velero-plugin-for-aws:v1.10.0 \
  --bucket my-k8s-backups --backup-location-config region=ap-south-1 \
  --secret-file ./credentials-velero \
  --snapshot-volumes=true \
  --use-volume-snapshots=true

velero backup create shop-prod --include-namespaces prod --ttl 720h --wait
velero backup get
velero backup describe shop-prod --details
velero backup logs shop-prod

velero schedule create nightly --schedule "0 2 * * *" --include-namespaces prod --ttl 720h
velero schedule get

velero restore create --from-backup shop-prod --include-namespaces prod
velero restore get
```

> 🔑 **Velero backs up Kubernetes objects + PV snapshots.** It does **not** back up: your Git repo (which should hold your manifests), secrets in an external manager, or anything outside the cluster. And **an untested restore is a rumour** — schedule a quarterly restore drill into a scratch namespace.

---

## 5.9 Step 8 — Debugging storage, end to end

### PVC stuck in `Pending`

```bash
kubectl describe pvc app-data | sed -n '/Events:/,$p'
```

| Message | Cause | Fix |
|---|---|---|
| `waiting for first consumer to be created before binding` | `WaitForFirstConsumer` — **normal, not an error** | Create the Pod that uses it |
| `no persistent volumes available for this claim and no storage class is set` | No default StorageClass, no static PVs | `kubectl get sc`; install a provisioner |
| `storageclass.storage.k8s.io "fast" not found` | Typo in `storageClassName` | `kubectl get sc` — match exactly |
| `field label not supported: spec.selector` | `selector` used with dynamic provisioning | Drop the selector, or create a static PV |
| `failed to provision volume with StorageClass "x": …` | Cloud creds, quota, AZ, IAM | `kubectl logs -n kube-system <csi-provisioner-pod>` |
| `Only dynamically provisioned pvc can be resized…` | Trying to expand a static PV | Recreate with a bigger capacity |
| `waiting for a volume to be created, either by external provisioner … or manually` | Provisioner not running | Check the CSI controller Deployment |

```bash
# find the provisioner pods
kubectl get pods -A -o wide | grep -iE 'csi|provisioner|local-path|ebs|gce-pd'
kubectl logs -n kube-system deploy/csi-provisioner --tail=50
kubectl get sc -o yaml | grep -E 'name:|provisioner:|reclaimPolicy:|volumeBindingMode:|allowVolumeExpansion:'
```

### Pod stuck in `ContainerCreating` with a volume error

```bash
kubectl describe pod db-0 | sed -n '/Events:/,$p'
```

| Message | Cause | Fix |
|---|---|---|
| `Multi-Attach error for volume …` | RWO volume claimed by 2 Pods on 2 nodes | `strategy: Recreate`, or StatefulSet per-Pod PVCs, or RWX |
| `Unable to attach or mount volumes: unmounted volumes=[data]` | Attach/mount still in progress, or the previous node hasn't released it | Wait; check `kubectl get volumeattachment`; force-detach if the node is truly dead |
| `mount failed: exit status 32 … wrong fs type, bad option` | Filesystem mismatch, or a `Block` volume mounted as `Filesystem` | Check `volumeMode`, `fsType` in the StorageClass |
| `failed to set up sandbox container … permission denied` | `fsGroup` missing, or the image's user can't write | Set `securityContext.fsGroup`, or `chown` in an init container |
| `context deadline exceeded` on attach | CSI driver unhealthy | Driver pod logs |

```bash
kubectl get volumeattachment
# NAME                     ATTACHER         PV           NODE            ATTACHED   AGE
# csi-abc123…              ebs.csi.aws.com  pvc-8f3a…    ip-10-0-1-42    true       5m

# force-detach a volume orphaned by a dead node (DANGEROUS — only if the node is truly gone)
kubectl delete volumeattachment csi-abc123…
```

### Permission problems on a mounted volume

```bash
kubectl exec db-0 -- id
# uid=999(postgres) gid=999(postgres) groups=999(postgres)
kubectl exec db-0 -- ls -ld /var/lib/postgresql/data
# drwxrwsr-x  3 postgres postgres …      ← note the 's' — setgid from fsGroup
kubectl exec db-0 -- touch /var/lib/postgresql/data/testfile && echo OK
```

Three ways to fix:

```yaml
# 1. fsGroup — Kubernetes chowns/chmods the volume to this GID at mount time
securityContext:
  fsGroup: 999

# 2. fsGroupChangePolicy — skip the chown when it's already right (fast for huge volumes)
securityContext:
  fsGroup: 999
  fsGroupChangePolicy: OnRootMismatch      # Always | OnRootMismatch

# 3. init container that fixes permissions as root
initContainers:
  - name: fix-perms
    image: busybox:1.37
    command: ["sh","-c","chown -R 1000:1000 /data && chmod 750 /data"]
    securityContext: {runAsUser: 0}
    volumeMounts: [{name: data, mountPath: /data}]
```

> ⚠️ `fsGroup` on a **huge** volume (TB-scale NFS with millions of files) can take *many minutes* at mount and looks like a hang. Use `fsGroupChangePolicy: OnRootMismatch`, or RWX volumes without fsGroup.

### Disk full inside a Pod

```bash
kubectl exec db-0 -- df -h
kubectl exec db-0 -- du -sh /var/lib/postgresql/data/*
kubectl top pods --sort-by=memory
kubectl describe node learn-worker | grep -A5 Conditions       # DiskPressure?
```

If the *node* has DiskPressure:

```bash
kubectl describe node learn-worker | sed -n '/Conditions:/,/Addresses:/p'
# DiskPressure   True   KubeletHasDiskPressure   kubelet is posting disk pressure
```

Pods get **evicted** (status `Evicted`). Fix by expanding the disk, cleaning images (`crictl rmi --prune` on the node), or moving log volumes off the root filesystem.

```bash
# clean up Evicted pod shells
kubectl delete pods -A --field-selector status.phase=Failed
```

---

## 5.10 Extra Tasks

### Task 5.1 — Share files between two Deployments

Two apps need to read/write the same directory. `ReadWriteOnce` won't do it. Build a working RWX setup.

<details>
<summary>Show answer</summary>

**Option A — NFS (works on any cluster, including kind/minikube):**

```bash
# On kind/minikube the easiest path is the nfs-subdir-external-provisioner
helm repo add nfs-subdir https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
helm install nfs nfs-subdir/nfs-subdir-external-provisioner \
  --set nfs.server=192.168.1.50 --set nfs.path=/srv/nfs \
  --set storageClass.name=nfs --set storageClass.defaultClass=false \
  --set storageClass.accessModes=ReadWriteMany
kubectl get sc
# nfs   cluster.local/nfs-nfs-subdir-external-provisioner   Delete   Immediate   true
```

On minikube you can run an in-cluster NFS server for practice:

```bash
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: nfs-server}
spec:
  replicas: 1
  selector: {matchLabels: {app: nfs-server}}
  template:
    metadata: {labels: {app: nfs-server}}
    spec:
      containers:
        - name: nfs
          image: k8s.gcr.io/volume-nfs:0.8
          ports: [{containerPort: 2049},{containerPort: 20048},{containerPort: 111}]
          securityContext: {privileged: true}     # ← needed for NFS in a container
          volumeMounts: [{name: exports, mountPath: /exports}]
      volumes: [{name: exports, emptyDir: {}}]
---
apiVersion: v1
kind: Service
metadata: {name: nfs-server}
spec:
  selector: {app: nfs-server}
  ports:
    - {name: nfs, port: 2049}
    - {name: mountd, port: 20048}
    - {name: rpcbind, port: 111}
EOF
NFS_IP=$(kubectl get svc nfs-server -o jsonpath='{.spec.clusterIP}')
helm install nfs nfs-subdir/nfs-subdir-external-provisioner \
  --set nfs.server=$NFS_IP --set nfs.path=/exports \
  --set storageClass.name=nfs --set storageClass.accessModes=ReadWriteMany
```

Now the RWX claim and two consumers:

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: shared}
spec:
  accessModes: [ReadWriteMany]
  storageClassName: nfs
  resources: {requests: {storage: 5Gi}}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: producer}
spec:
  replicas: 2
  selector: {matchLabels: {app: producer}}
  template:
    metadata: {labels: {app: producer}}
    spec:
      containers:
        - name: w
          image: busybox:1.37
          command: ["sh","-c","while true; do echo \"$(hostname) $(date -u +%T)\" >> /shared/log.txt; sleep 3; done"]
          volumeMounts: [{name: s, mountPath: /shared}]
          resources: {requests: {cpu: 10m, memory: 8Mi}}
      volumes: [{name: s, persistentVolumeClaim: {claimName: shared}}]
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: consumer}
spec:
  replicas: 3
  selector: {matchLabels: {app: consumer}}
  template:
    metadata: {labels: {app: consumer}}
    spec:
      containers:
        - name: r
          image: busybox:1.37
          command: ["sh","-c","sleep 10; echo '--- lines written by ALL producers ---'; wc -l /shared/log.txt; tail -5 /shared/log.txt; sleep 3600"]
          volumeMounts: [{name: s, mountPath: /shared, readOnly: true}]
          resources: {requests: {cpu: 10m, memory: 8Mi}}
      volumes: [{name: s, persistentVolumeClaim: {claimName: shared}}]
EOF

kubectl get pvc shared                     # Bound
kubectl get pods -l app=producer -o wide   # 2 pods, possibly on DIFFERENT nodes
kubectl logs -l app=consumer --prefix --tail=8
```

You should see lines from `producer-xxx` and `producer-yyy` interleaved — proof both wrote to the same filesystem from different nodes.

**Option B — the modern answer for shared app data: don't use a shared volume.**

| Need | Better solution |
|---|---|
| Shared uploads | Object storage (S3/GCS/Azure Blob) + a CDN |
| Shared config | ConfigMap |
| Shared cache | Redis |
| Shared session state | Redis / a database |
| Shared ML models | ROX volume, or an init container that downloads from object storage |
| Shared logs | stdout + a log aggregator (Loki) |

Shared RWX filesystems are a source of locking bugs, hot spots, and cross-AZ latency. Reach for object storage first.

**Option C — CephFS / Longhorn / OpenEBS Mayastor** for real RWX with block-like performance. Longhorn is the easiest self-hosted choice:

```bash
helm repo add longhorn https://charts.longhorn.io
helm install longhorn longhorn/longhorn -n longhorn-system --create-namespace \
  --set defaultSettings.defaultReplicaCount=2
kubectl get sc longhorn         # supports RWX via its share-manager
```

```bash
kubectl delete deploy producer consumer && kubectl delete pvc shared
```

</details>

---

### Task 5.2 — Survive a node failure with state intact

Kill the node running `db-0` and get the StatefulSet healthy again.

<details>
<summary>Show answer</summary>

```bash
kubectl get pods -l app=db -o wide
# db-0   1/1   Running   0   10m   10.244.2.15   learn-worker2   ← note the node
```

**Kill the node** (kind: stop the container; real cluster: power it off / detach it):

```bash
docker stop learn-worker2
kubectl get nodes -w
```

```
learn-worker2   NotReady   0s      ← after ~40s of missed heartbeats
```

```bash
kubectl get pods -l app=db -o wide -w
```

```
db-0   1/1   Running       0   12m   ← still "Running": kubelet isn't reporting, status is STALE
db-0   1/1   Terminating   0   12m   ← node controller adds the unreachable:NoExecute taint,
                                       ← after tolerationSeconds (300s default) pods are evicted
db-0   0/1   Terminating   0   12m
db-0   0/1   Pending       0   0s    ← StatefulSet tries to reschedule
db-0   0/1   Pending       0   30s
```

**Here's the interesting part.** `kubectl describe pod db-0`:

```
Warning  FailedScheduling  ...  0/3 nodes are available:
  1 node(s) had volume node affinity conflict,
  2 node(s) didn't match PersistentVolume's node affinity.
```

or:

```
Warning  FailedAttachVolume  ...  AttachVolume.Attach failed for volume "pvc-aaa":
  rpc error: ... The volume is already attached to node "learn-worker2"
```

**Why:** with `local-path` (and with real zoned cloud disks), the PV is *physically on that node / in that zone*. Kubernetes refuses to run `db-0` anywhere else, because the data isn't there.

> 🔑 **This is a StatefulSet safety feature, not a bug.** Kubernetes will not start `db-0` on another node while it cannot be *certain* the old node is dead — otherwise you'd get **split-brain**: two `db-0`s writing to two copies of the data.

**Recovery paths:**

```bash
# 1. BEST: bring the node back
docker start learn-worker2
kubectl wait --for=condition=Ready node/learn-worker2 --timeout=180s
kubectl get pods -l app=db -w     # db-0 reschedules onto learn-worker2, reattaches its PVC, data intact

# 2. Node is gone forever → delete the node object, then let the StatefulSet reschedule
kubectl get nodes
kubectl delete node learn-worker2
# ⚠️ For a zoned cloud disk you must ALSO move/restore the volume; for local-path the data is LOST.
#    Force-delete the stuck pod so the controller can create a new one:
kubectl delete pod db-0 --grace-period=0 --force
kubectl get pods -l app=db -w
# With local-path, db-0 comes up with an EMPTY volume → this is where your backup matters.

# 3. VolumeSnapshot-based recovery (cloud CSI)
#    Provision a new PVC from the last snapshot in a healthy zone, then re-point db-0 at it.
```

**Then verify:**

```bash
kubectl exec db-0 -- psql -U postgres -d app -tAc 'select pod, count(*) from whoami group by pod;' 
```

**Lessons to write down:**

1. **Local storage (`local-path`, `hostPath`) does not survive node loss.** Fine for learning; never for production state.
2. **Cloud block storage survives node loss but is zoned** — the node must come back in the same AZ, or you restore from a snapshot.
3. **RWX/network storage survives node loss cleanly** — that's what you pay for.
4. **Never `--force` delete a StatefulSet Pod on a still-live node.** You can get two Pods with the same identity writing to the same data. Force-delete only after the node object is confirmed gone.
5. **A PodDisruptionBudget does not protect against node crashes** — only voluntary disruption. For node loss you need real HA: multiple replicas + an operator that promotes a new primary.

```bash
kubectl scale statefulset db --replicas=0 && kubectl delete pvc -l app=db
kubectl delete -f statefulset.yaml
```

</details>

---

### Task 5.3 — Find and clean up orphaned PVCs and PVs

Your cloud bill shows 40 disks. The cluster has 12. Find the rest.

<details>
<summary>Show answer</summary>

```bash
# ── 1. All PVs, with their state and claim ──
kubectl get pv -o custom-columns=\
'NAME:.metadata.name,CAP:.spec.capacity.storage,MODE:.spec.accessModes[0],POLICY:.spec.persistentVolumeReclaimPolicy,STATUS:.status.phase,CLAIM:.spec.claimRef.namespace/.spec.claimRef.name,SC:.spec.storageClassName,AGE:.metadata.creationTimestamp'
```

| `STATUS` | Meaning | Action |
|---|---|---|
| `Bound` | In use | Leave it |
| `Available` | Provisioned, no claim | Investigate — usually a leftover static PV |
| **`Released`** | The PVC was deleted; `Retain` policy kept the PV | ⭐ **These are your orphans.** Reclaim or delete |
| `Failed` | Automatic reclaim failed | Manual cleanup |

```bash
# ── 2. Released PVs specifically ──
kubectl get pv --field-selector status.phase=Released

# ── 3. PVCs whose namespace no longer exists ──
kubectl get pv -o json | jq -r '
  .items[] | select(.spec.claimRef != null) |
  "\(.spec.claimRef.namespace)/\(.spec.claimRef.name)\t\(.spec.capacity.storage)\t\(.status.phase)"' \
  | while IFS=$'\t' read -r claim size status; do
      ns=${claim%%/*}
      kubectl get namespace "$ns" >/dev/null 2>&1 || echo "ORPHAN (namespace gone): $claim  $size  $status"
    done

# ── 4. StatefulSet PVCs whose ordinal no longer exists ──
for sts in $(kubectl get sts -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}'); do
  ns=${sts%%/*}; name=${sts##*/}
  replicas=$(kubectl get sts $name -n $ns -o jsonpath='{.spec.replicas}')
  kubectl get pvc -n $ns -l app=$name -o json | jq -r --argjson r "$replicas" '
    .items[] | .metadata.name as $n |
    ($n | capture("(?<i>[0-9]+)$").i | tonumber) as $i |
    select($i >= $r) | "SCALE-DOWN ORPHAN: \($n) (replicas=\($r))"'
done

# ── 5. Volumes nobody mounts ──
USED=$(kubectl get pods -A -o json | jq -r '[.items[].spec.volumes[]? | select(.persistentVolumeClaim) | .persistentVolumeClaim.claimName] | unique | .[]')
kubectl get pvc -A --no-headers | awk '{print $1"/"$2}' | while read -r p; do
  echo "$USED" | grep -qx "${p##*/}" || echo "UNUSED PVC: $p"
done

# ── 6. Snapshot leftovers ──
kubectl get volumesnapshot -A
```

**Clean up safely:**

```bash
# Released PVs — DELETE means the cloud disk is destroyed
kubectl get pv pvc-aaa… -o yaml > /tmp/pvc-aaa.yaml      # ⭐ SAVE IT FIRST (data recovery possible)
kubectl delete pv pvc-aaa…

# Orphaned PVCs from a scaled-down StatefulSet
kubectl delete pvc data-db-3 data-db-4 -n prod

# Bulk: all Released PVs older than 30 days (DRY RUN FIRST)
kubectl get pv --field-selector status.phase=Released -o json \
  | jq -r --arg cutoff "$(date -u -d '-30 days' +%FT%TZ 2>/dev/null || date -u -v-30d +%FT%TZ)" \
    '.items[] | select(.metadata.creationTimestamp < $cutoff) | .metadata.name'
# …review the list, then:
#   | xargs -r kubectl delete pv
```

**Prevent it in the first place:**

1. Set `reclaimPolicy: Delete` for ephemeral environments, `Retain` only where you truly want recovery.
2. Use `ttlSecondsAfterFinished` on Jobs that create temporary PVCs.
3. Automate the audit as a CronJob that reports (not deletes) weekly — a human decides.
4. Tag cloud volumes with the cluster/namespace so Finance can attribute them:
   ```yaml
   parameters:
     tags: "cluster=learn,team=platform,managed-by=kubernetes"
   ```
5. Use `kube-cost` / OpenCost to see storage spend per namespace:
   ```bash
   helm install opencost opencost/opencost -n opencost --create-namespace
   ```

</details>

---

### Task 5.4 — Grow a PVC online and prove the filesystem grew too

<details>
<summary>Show answer</summary>

```bash
kubectl get sc standard -o jsonpath='{.allowVolumeExpansion}'; echo
# false → you must enable it (or use a different StorageClass)
kubectl patch storageclass standard -p '{"allowVolumeExpansion":true}'
kubectl get sc standard -o jsonpath='{.allowVolumeExpansion}'; echo    # true
```

```bash
kubectl exec db-0 -- df -h /var/lib/postgresql/data
# Filesystem   Size  Used Avail Use%  Mounted on
# /dev/sdb     5.0G  150M  4.9G   3%  /var/lib/postgresql/data

kubectl patch pvc data-db-0 -p '{"spec":{"resources":{"requests":{"storage":"10Gi"}}}}'
kubectl get pvc data-db-0 -w
```

Three possible outcomes:

**A. Immediate resize (most cloud CSI drivers):**
```
data-db-0   Bound   pvc-aaa…   10Gi   RWO   standard   ← done, no restart
```

**B. Needs a Pod restart to grow the filesystem:**
```bash
kubectl describe pvc data-db-0 | grep -A5 Conditions
#   Type                      Status
#   FileSystemResizePending   True      ← waiting for a pod to use this claim
kubectl rollout restart statefulset db          # or delete pod db-0
kubectl describe pvc data-db-0 | grep -A5 Conditions   # condition cleared
kubectl exec db-0 -- df -h /var/lib/postgresql/data
# /dev/sdb    10G  …
```

**C. Local provisioners that can't expand at all:**
```
Warning  ExternalExpanding  ...  Ignoring the PVC: didn't find a plugin capable of expanding the volume;
                                  waiting for an external controller to expand this PVC
```
→ Recreate the PVC larger and copy the data (see below).

**Verify from inside:**

```bash
kubectl exec db-0 -- df -h /var/lib/postgresql/data
kubectl exec db-0 -- sh -c 'dd if=/dev/zero of=/var/lib/postgresql/data/testfile bs=1M count=500 && ls -lh /var/lib/postgresql/data/testfile && rm /var/lib/postgresql/data/testfile'
```

**Manual "grow by copying" (when expansion isn't supported):**

```bash
# 1. new, bigger PVC
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: data-db-0-new}
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: standard
  resources: {requests: {storage: 20Gi}}
EOF

# 2. copy job that mounts both (same node → both RWO mounts work)
kubectl apply -f - <<'EOF'
apiVersion: batch/v1
kind: Job
metadata: {name: pv-copy}
spec:
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: copy
          image: alpine:3.22
          command: ["sh","-c","apk add --no-cache rsync && rsync -aHAX --info=progress2 /old/ /new/ && echo DONE && du -sh /new"]
          volumeMounts: [{name: old, mountPath: /old}, {name: new, mountPath: /new}]
      volumes:
        - {name: old, persistentVolumeClaim: {claimName: data-db-0}}
        - {name: new, persistentVolumeClaim: {claimName: data-db-0-new}}
EOF
kubectl wait --for=condition=complete job/pv-copy --timeout=3600s
kubectl logs job/pv-copy

# 3. scale the sts to 0, swap the claim, scale back up
#    (StatefulSet volumeClaimTemplates are immutable — you must recreate the StatefulSet)
kubectl delete statefulset db --cascade=orphan
# edit statefulset.yaml: volumeClaimTemplates → claimName data-db-0-new
#   (or rename the PVCs; simplest is to delete data-db-0 and rename the new one,
#    which requires recreating the PV binding — usually easier to just re-apply with a new name)
kubectl apply -f statefulset.yaml
```

Because StatefulSet `volumeClaimTemplates` are immutable, in practice teams do this during a maintenance window or migrate to a new StatefulSet name and cut over with a Service selector change.

</details>

---

### Task 5.5 — Make an app that writes to a read-only root filesystem and still work

Hardening requires `readOnlyRootFilesystem: true`. Your app writes to `/tmp`, `/var/cache` and `/app/logs`. Fix it.

<details>
<summary>Show answer</summary>

Mount `emptyDir` volumes at exactly the paths that need to be writable.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata: {name: hardened}
spec:
  replicas: 2
  selector: {matchLabels: {app: hardened}}
  template:
    metadata: {labels: {app: hardened}}
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 10001
        runAsGroup: 10001
        fsGroup: 10001
        seccompProfile: {type: RuntimeDefault}
      containers:
        - name: app
          image: nginx:1.29-alpine
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true          # ⭐
            capabilities: {drop: ["ALL"]}
          ports: [{name: http, containerPort: 8080}]
          volumeMounts:
            # EVERY path nginx needs to write to
            - {name: tmp,       mountPath: /tmp}
            - {name: cache,     mountPath: /var/cache/nginx}
            - {name: run,       mountPath: /var/run}
            - {name: logs,      mountPath: /var/log/nginx}
            - {name: nginx-conf,mountPath: /etc/nginx/nginx.conf, subPath: nginx.conf}
            - {name: confd,     mountPath: /etc/nginx/conf.d}
          resources:
            requests: {cpu: 50m, memory: 64Mi}
            limits:   {cpu: 250m, memory: 128Mi}
          readinessProbe: {httpGet: {path: /healthz, port: http}, periodSeconds: 5}
      volumes:
        - {name: tmp,    emptyDir: {sizeLimit: 100Mi}}
        - {name: cache,  emptyDir: {sizeLimit: 200Mi}}
        - {name: run,    emptyDir: {sizeLimit: 10Mi}}
        - {name: logs,   emptyDir: {sizeLimit: 500Mi}}
        - {name: confd,  emptyDir: {}}
        - name: nginx-conf
          configMap:
            name: nginx-hardened
            items: [{key: nginx.conf, path: nginx.conf}]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: nginx-hardened}
data:
  nginx.conf: |
    # run as the non-root user from securityContext, listen on >1024
    user  nginx;
    worker_processes  auto;
    error_log  /var/log/nginx/error.log warn;
    pid        /var/run/nginx.pid;                # ← writable via the `run` emptyDir
    events { worker_connections 1024; }
    http {
      client_body_temp_path /tmp/client_body;     # ← writable via the `tmp` emptyDir
      proxy_temp_path       /tmp/proxy;
      fastcgi_temp_path     /tmp/fastcgi;
      uwsgi_temp_path       /tmp/uwsgi;
      scgi_temp_path        /tmp/scgi;
      access_log /var/log/nginx/access.log;
      server {
        listen 8080;                              # ← >1024, so no NET_BIND_SERVICE needed
        location /healthz { return 200 "ok\n"; }
        location /        { return 200 "hardened nginx\n"; }
      }
    }
```

```bash
kubectl apply -f hardened.yaml
kubectl rollout status deploy/hardened
kubectl exec deploy/hardened -- touch /etc/passwd
# touch: /etc/passwd: Read-only file system          ← ⭐ exactly what we want
kubectl exec deploy/hardened -- touch /tmp/ok && echo "tmp is writable ✅"
kubectl exec deploy/hardened -- id
kubectl port-forward deploy/hardened 8080:8080 & sleep 2 && curl -s localhost:8080/healthz && kill %1
```

**How to find every path your app writes to** (the systematic method):

```bash
# 1. Run it WITHOUT readOnlyRootFilesystem and watch
kubectl exec <pod> -- sh -c 'find / -xdev -newer /etc/hostname -type f 2>/dev/null | head -50'

# 2. strace the writes (needs a debug container + SYS_PTRACE)
kubectl debug -it <pod> --image=nicolaka/netshoot --target=app --share-processes
  strace -f -e trace=openat,write -p 1 2>&1 | grep -E 'O_WRONLY|O_CREAT'

# 3. Audit with fanotify (best, needs privileged)
  # docker run --rm -it --pid=container:<id> --cap-add SYS_ADMIN justwatch/elktide

# 4. Read the app's docs — nginx, Java (java.io.tmpdir), Python (tempfile), Node (os.tmpdir())
```

**Language-specific writable paths:**

| Runtime | Writes to | Fix |
|---|---|---|
| nginx | `/var/cache/nginx`, `/var/run`, `/var/log/nginx`, `/tmp/*_temp_path` | emptyDir each + non-1024 port |
| Java | `java.io.tmpdir` (default `/tmp`), heap dumps, JMX sockets | `-Djava.io.tmpdir=/tmp` + emptyDir; `-XX:HeapDumpPath=/tmp` |
| Python | `tempfile.gettempdir()`, `__pycache__`, `.pyc` | `PYTHONDONTWRITEBYTECODE=1` + emptyDir `/tmp` |
| Node | `os.tmpdir()`, npm cache | emptyDir `/tmp`, `npm_config_cache=/tmp/.npm` |
| Go | almost nothing if written well | usually just `/tmp` |
| Postgres | `PGDATA` | **PVC**, not emptyDir |

Then verify the whole thing passes a policy scan:

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: hardened-test
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/warn: restricted
EOF
kubectl apply -f hardened.yaml -n hardened-test --dry-run=server
# if it passes server-side dry-run in a `restricted` namespace, you're genuinely hardened
kubectl delete ns hardened-test
```

</details>

---

## 5.11 Checklist

- [ ] Draw the StorageClass → PV → PVC → Pod chain and explain who writes each
- [ ] Explain the difference between `emptyDir`, `hostPath`, and a PVC in terms of lifetime
- [ ] Explain `WaitForFirstConsumer` and why a `Pending` PVC is often not an error
- [ ] Name all four access modes and give a real backing store for each
- [ ] Diagnose and fix a `Multi-Attach error`
- [ ] Explain what `reclaimPolicy: Delete` does when a PVC is removed, and recover from `Retain`
- [ ] Expand a PVC online and verify the filesystem grew
- [ ] Explain the three StatefulSet guarantees and give one workload that needs each
- [ ] Explain why `PGDATA` must be a subdirectory of the mount
- [ ] Read stable DNS names for StatefulSet Pods from memory
- [ ] Explain why Kubernetes refuses to reschedule a StatefulSet Pod to another node
- [ ] Use `fsGroup` / `fsGroupChangePolicy` to fix volume permissions
- [ ] Back up and restore a database three ways (logical, snapshot, Velero)
- [ ] Find orphaned PVCs/PVs

**Next → [`09-PROJECT-6-ingress-tls.md`](09-PROJECT-6-ingress-tls.md)** — Ingress, host routing, and real TLS with cert-manager.

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish%20Kumar%20Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn → <https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260>
🐙 GitHub → <https://github.com/3558Bhk>

*Built for engineers who learn by breaking things on purpose.*

</div>
