# 🗄️ Project 13 — Databases on Kubernetes (six mini-projects)

> **Time:** 3–4 hours (or one database at a time) · **Prereq:** [Project 5](08-PROJECT-5-storage-statefulset.md)
>
> Six databases, each a self-contained mini-project:
>
> | # | Database | Kind | The Kubernetes lesson it teaches |
> |---|---|---|---|
> | 13.1 | **MySQL 8.4** | Relational | StatefulSet + headless Service + `Recreate` vs rolling + mysqldump/Velero |
> | 13.2 | **MongoDB 7** | Document | Replica-set StatefulSet, per-Pod DNS, `podManagementPolicy: Parallel` |
> | 13.3 | **Redis 7** | In-memory KV | Primary/replica split, two Services, `emptyDir` vs PVC, eviction policies |
> | 13.4 | **DynamoDB Local** | Emulator | Why an emulator is the right local choice, and why it's never right in prod |
> | 13.5 | **Cassandra 4.1** | Wide-column | True peer-to-peer StatefulSet, seed nodes, rack awareness, `OrderedReady` |
> | 13.6 | **Neo4j 5.26** | Graph | Bolt + HTTP dual ports, CAUSAL cluster, licensing limits |
>
> Each has **🔵 Case 1 (simple, one Pod)** and **🟢 Case 2 (production, StatefulSet + storage + backup + HA)**, plus tasks and answers.

---

## 13.0 First — should you run a database on Kubernetes at all?

**The honest answer: it depends on which database and how much you value your weekends.**

| Database | Run on K8s? | Why |
|---|---|---|
| Postgres / MySQL | ✅ Yes, **with an operator** | CloudNativePG / Zalando / Crunchy handle failover, backups, replication correctly. Hand-rolled = pain. |
| Redis | ✅ Yes | Stateless-ish, fast restart, easy replication. Very common on K8s. |
| MongoDB | ✅ Yes, with the official operator | The operator handles replica-set election and sharding. |
| Cassandra | ✅ Yes — it's designed for it | Peer-to-peer, no leader, tolerates node loss by design. **This is the best fit on the list.** |
| Elasticsearch/OpenSearch | ✅ Yes, with ECK | Operators exist for a reason. |
| Kafka | ✅ Yes, with Strimzi | Standard practice now. |
| Neo4j | ⚠️ Careful | Community edition is single-instance. Clustering needs Enterprise. |
| DynamoDB Local | ⚠️ Dev only | It's an emulator. Production = the real AWS service. |
| Your one irreplaceable 5 TB OLTP database | ❌ Probably not | Managed RDS/Cloud SQL with a real SLA beats your StatefulSet. |

**The three reasons databases are hard on Kubernetes:**

1. **Storage is not portable.** A PVC bound to a zoned EBS volume in `us-east-1a` cannot move to a node in `us-east-1b`. Your StatefulSet is pinned.
2. **Pod identity matters.** `db-0` must always be `db-0`, with the same data. A Deployment gives you a random name and no storage guarantee.
3. **Split-brain kills data.** If Kubernetes thinks a Pod is dead but it's still running and writing, you can corrupt everything. StatefulSets deliberately wait (the 300 s `unreachable` toleration) for exactly this reason.

**What Kubernetes gives you in return:** declarative config, one tool for everything, automatic restarts, rolling upgrades, self-healing, resource limits, and no more "the DB is on that one server nobody understands."

**The rule I'd give a beginner:**
- **Learn** on Kubernetes (this project) — with `kind`, throwaway data.
- **Develop/staging** on Kubernetes — real value, low risk.
- **Production** — an operator, or a managed service. Never hand-rolled YAML.

```bash
mkdir -p ~/k8s-learn/p13 && cd ~/k8s-learn/p13
kubectl get nodes && kubectl get sc
```

---
---

# 13.1 — MySQL 8.4

## 🔵 Case 1 — one Deployment, one PVC (10 minutes)

```bash
mkdir -p ~/k8s-learn/p13/mysql && cd ~/k8s-learn/p13/mysql
```

`mysql/simple.yaml`:

```yaml
apiVersion: v1
kind: Secret
metadata: {name: mysql-creds}
stringData:
  MYSQL_ROOT_PASSWORD: "R00t-Learn-K8s!"
  MYSQL_DATABASE: app
  MYSQL_USER: appuser
  MYSQL_PASSWORD: "App-Learn-K8s!"
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: mysql-data}
spec:
  accessModes: [ReadWriteOnce]
  resources: {requests: {storage: 5Gi}}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: mysql, labels: {app: mysql}}
spec:
  replicas: 1
  selector: {matchLabels: {app: mysql}}
  strategy:
    type: Recreate        # ⭐ CRITICAL. A rolling update would start mysql-2 while
                          # mysql-1 still holds the RWO volume → both crash.
  template:
    metadata: {labels: {app: mysql}}
    spec:
      terminationGracePeriodSeconds: 60
      containers:
        - name: mysql
          image: mysql:8.4
          ports: [{name: mysql, containerPort: 3306}]
          envFrom: [{secretRef: {name: mysql-creds}}]
          args:
            - --character-set-server=utf8mb4
            - --collation-server=utf8mb4_0900_ai_ci
            - --default-authentication-plugin=caching_sha2_password
          readinessProbe:
            exec:
              # ⭐ mysqladmin ping returns 0 even during recovery in some versions.
              # A real query is a better readiness signal.
              command: ["sh","-c","mysql -h 127.0.0.1 -u root -p\"$MYSQL_ROOT_PASSWORD\" -e 'SELECT 1'"]
            initialDelaySeconds: 20
            periodSeconds: 10
            timeoutSeconds: 5
            failureThreshold: 30
          livenessProbe:
            exec: {command: ["mysqladmin","ping","-h","127.0.0.1","-uroot","-p$(MYSQL_ROOT_PASSWORD)"]}
            initialDelaySeconds: 60
            periodSeconds: 30
            timeoutSeconds: 10
            failureThreshold: 5
          resources:
            requests: {cpu: 250m, memory: 512Mi}
            limits:   {cpu: "1",   memory: 1Gi}
          volumeMounts:
            - {name: data, mountPath: /var/lib/mysql}
      volumes:
        - name: data
          persistentVolumeClaim: {claimName: mysql-data}
---
apiVersion: v1
kind: Service
metadata: {name: mysql}
spec:
  selector: {app: mysql}
  ports: [{name: mysql, port: 3306}]
```

```bash
kubectl apply -f mysql/simple.yaml
kubectl rollout status deploy/mysql --timeout=180s
kubectl get pods,svc,pvc -l app=mysql
kubectl describe pod -l app=mysql | grep -A5 Events

# connect
kubectl exec -it deploy/mysql -- mysql -u root -p'R00t-Learn-K8s!' -e '
  SHOW DATABASES;
  USE app;
  CREATE TABLE IF NOT EXISTS products (id INT AUTO_INCREMENT PRIMARY KEY, name VARCHAR(120), price DECIMAL(10,2));
  INSERT INTO products (name, price) VALUES ("Widget", 9.99), ("Gadget", 19.99);
  SELECT * FROM products;
  SHOW VARIABLES LIKE "character_set_server";
  SHOW VARIABLES LIKE "innodb_buffer_pool_size";'
```

**Prove the data survives:**

```bash
kubectl delete pod -l app=mysql
kubectl rollout status deploy/mysql
kubectl exec -it deploy/mysql -- mysql -u root -p'R00t-Learn-K8s!' -D app -e 'SELECT * FROM products;'
# id | name   | price
#  1 | Widget |  9.99     ← ✅ the PVC held
#  2 | Gadget | 19.99
```

**Prove `strategy: Recreate` matters** (do this deliberately):

```bash
kubectl patch deploy mysql --type=merge -p '{"spec":{"strategy":{"type":"RollingUpdate","rollingUpdate":{"maxSurge":1,"maxUnavailable":0}}}}'
kubectl rollout restart deploy/mysql
kubectl get pods -l app=mysql -w
```

```
mysql-7d4f-abcde   0/1   ContainerCreating   0   5s
mysql-7d4f-xyz12   1/1   Running             0   2m
```

Then:

```bash
kubectl describe pod -l app=mysql | grep -A3 Warning
# Warning  FailedMount  Multi-Attach error for volume "pvc-…" Volume is already used by pod(s) mysql-7d4f-xyz12
```

The new Pod can never start, because the RWO volume is still attached to the old one. **RollingUpdate + a single RWO PVC = permanent deadlock.** Revert:

```bash
kubectl patch deploy mysql --type=merge -p '{"spec":{"strategy":{"type":"Recreate"}}}'
kubectl rollout status deploy/mysql
```

> 🔑 This is the exact reason **StatefulSets exist**: they delete the old Pod *before* creating the new one, and they give each Pod a stable identity.

## 🟢 Case 2 — StatefulSet with primary + replica, backups, and tested restore (45 minutes)

### Architecture

```
                    ┌─────────────────────┐
   writes  ───────► │ mysql-rw (Service)  │──► mysql-0  (primary)
                    └─────────────────────┘         │
                    ┌─────────────────────┐         │ async replication
   reads   ───────► │ mysql-ro (Service)  │──► mysql-1  (replica)
                    └─────────────────────┘         │
                    ┌─────────────────────┐         │
   all      ──────► │ mysql (headless)    │──► mysql-0.mysql, mysql-1.mysql
                    └─────────────────────┘
                             ▲
                    backup CronJob → S3/MinIO
```

**Why three Services?**

| Service | Type | Selects | Use |
|---|---|---|---|
| `mysql` | Headless (`clusterIP: None`) | all pods | Stable per-Pod DNS for the StatefulSet (`mysql-0.mysql.shop.svc`) |
| `mysql-rw` | ClusterIP | `role: primary` | Writes. The label moves when the primary changes |
| `mysql-ro` | ClusterIP | `role: replica` | Reads. Load-balanced across replicas |

### `mysql/prod/00-config.yaml`

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: db
  labels:
    pod-security.kubernetes.io/enforce: baseline
    team: data
---
apiVersion: v1
kind: Secret
metadata: {name: mysql-creds, namespace: db}
stringData:
  root-password: "R00t-Pr0d-K8s!-X9"
  app-password:  "App-Pr0d-K8s!-Y2"
  repl-password: "R3pl-Pr0d-K8s!-Z5"
  backup-password: "Bkp-Pr0d-K8s!-W1"
---
apiVersion: v1
kind: ConfigMap
metadata: {name: mysql-config, namespace: db}
data:
  # ⭐ ONE file, but server-id is injected per-Pod by an init container (§ below)
  my.cnf: |
    [mysqld]
    # ── identity & replication ──
    server-id                = ${SERVER_ID}
    gtid_mode                = ON
    enforce_gtid_consistency = ON
    log_bin                  = /var/lib/mysql/binlog/mysql-bin
    binlog_format            = ROW
    binlog_expire_logs_seconds = 604800
    sync_binlog              = 1
    relay_log                = /var/lib/mysql/relaylog/relay-bin
    log_replica_updates      = ON
    read_only                = ${READ_ONLY}
    super_read_only          = ${READ_ONLY}

    # ── character set (MySQL 8 defaults are already utf8mb4) ──
    character-set-server     = utf8mb4
    collation-server         = utf8mb4_0900_ai_ci

    # ── InnoDB — size from the container memory limit ──
    # buffer pool ≈ 60-70% of available RAM. Do NOT guess.
    innodb_buffer_pool_size  = 512M
    innodb_buffer_pool_instances = 4
    innodb_log_file_size     = 256M
    innodb_flush_log_at_trx_commit = 1     # 1 = safest (fsync every commit)
    innodb_flush_method      = O_DIRECT    # avoid double buffering with the page cache
    innodb_file_per_table    = ON

    # ── connections ──
    max_connections          = 300
    max_connect_errors       = 100000
    wait_timeout             = 600
    interactive_timeout      = 600
    thread_cache_size        = 32

    # ── safety ──
    skip_name_resolve        = ON          # ⭐ DNS lookups on every connection = latency spikes
    local_infile             = OFF
    mysqlx                   = OFF

    # ── slow query log → stdout for Loki ──
    slow_query_log           = ON
    slow_query_log_file      = /dev/stderr
    long_query_time          = 0.5
    log_queries_not_using_indexes = OFF

    [client]
    default-character-set    = utf8mb4
---
# init SQL: create the app + replication + backup users
apiVersion: v1
kind: ConfigMap
metadata: {name: mysql-initdb, namespace: db}
data:
  01-users.sql: |
    -- ⭐ Runs once, on first initialisation of the data directory only.
    CREATE DATABASE IF NOT EXISTS app CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    CREATE USER IF NOT EXISTS 'app'@'%'         IDENTIFIED BY '__APP_PASSWORD__';
    CREATE USER IF NOT EXISTS 'repl'@'%'        IDENTIFIED BY '__REPL_PASSWORD__';
    CREATE USER IF NOT EXISTS 'backup'@'%'      IDENTIFIED BY '__BACKUP_PASSWORD__';
    CREATE USER IF NOT EXISTS 'exporter'@'%'    IDENTIFIED BY '__EXPORTER_PASSWORD__';

    GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, INDEX, ALTER,
          CREATE TEMPORARY TABLES, LOCK TABLES, EXECUTE, CREATE VIEW,
          SHOW VIEW, CREATE ROUTINE, ALTER ROUTINE, TRIGGER, REFERENCES
      ON app.* TO 'app'@'%';

    GRANT REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'repl'@'%';

    GRANT SELECT, LOCK TABLES, SHOW VIEW, EVENT, TRIGGER,
          PROCESS, RELOAD, REPLICATION CLIENT, BACKUP_ADMIN
      ON *.* TO 'backup'@'%';

    GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'exporter'@'%';

    FLUSH PRIVILEGES;
```

### `mysql/prod/01-statefulset.yaml`

```yaml
# ── headless Service: stable per-Pod DNS ──
apiVersion: v1
kind: Service
metadata: {name: mysql, namespace: db, labels: {app: mysql}}
spec:
  clusterIP: None                       # ⭐ headless
  selector: {app: mysql}
  ports: [{name: mysql, port: 3306}]
  publishNotReadyAddresses: false
---
# ── read/write Service: only the primary ──
apiVersion: v1
kind: Service
metadata: {name: mysql-rw, namespace: db, labels: {app: mysql}}
spec:
  selector: {app: mysql, role: primary}
  ports: [{name: mysql, port: 3306}]
---
# ── read-only Service: only replicas ──
apiVersion: v1
kind: Service
metadata: {name: mysql-ro, namespace: db, labels: {app: mysql}}
spec:
  selector: {app: mysql, role: replica}
  ports: [{name: mysql, port: 3306}]
---
apiVersion: v1
kind: ServiceAccount
metadata: {name: mysql, namespace: db}
automountServiceAccountToken: false
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mysql
  namespace: db
  labels: {app: mysql, app.kubernetes.io/name: mysql}
spec:
  serviceName: mysql                    # ⭐ the headless Service above
  replicas: 2
  podManagementPolicy: OrderedReady     # ⭐ mysql-0 (primary) must exist before mysql-1
  updateStrategy:
    type: RollingUpdate
    rollingUpdate: {partition: 0}
  revisionHistoryLimit: 5
  selector: {matchLabels: {app: mysql}}
  template:
    metadata:
      labels: {app: mysql}
      annotations:
        checksum/config: REPLACE_WITH_SHA
    spec:
      serviceAccountName: mysql
      terminationGracePeriodSeconds: 120   # ⭐ InnoDB needs time to flush dirty pages
      securityContext:
        fsGroup: 999                        # the mysql group in the official image
        runAsUser: 999
        runAsGroup: 999
        runAsNonRoot: true
        seccompProfile: {type: RuntimeDefault}

      # ── the primary must be scheduled first, and they must not share a node ──
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            - labelSelector: {matchLabels: {app: mysql}}
              topologyKey: kubernetes.io/hostname
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: ScheduleAnyway
          labelSelector: {matchLabels: {app: mysql}}

      initContainers:
        # ── 1. derive this Pod's identity from its ordinal ──
        #    mysql-0 → server-id=1, read_only=OFF (primary)
        #    mysql-1 → server-id=2, read_only=ON  (replica)
        - name: init-config
          image: busybox:1.37
          command:
            - sh
            - -c
            - |
              set -eu
              ORDINAL="${HOSTNAME##*-}"                       # mysql-1 → 1
              SERVER_ID=$((ORDINAL + 1))
              if [ "$ORDINAL" = "0" ]; then READ_ONLY=OFF; else READ_ONLY=ON; fi

              mkdir -p /mnt/config /var/lib/mysql/binlog /var/lib/mysql/relaylog
              sed -e "s/\${SERVER_ID}/$SERVER_ID/" \
                  -e "s/\${READ_ONLY}/$READ_ONLY/" \
                  /config/my.cnf > /mnt/config/my.cnf

              # substitute passwords into the init SQL (avoids env-var secrets in the DB)
              sed -e "s|__APP_PASSWORD__|$(cat /creds/app-password)|" \
                  -e "s|__REPL_PASSWORD__|$(cat /creds/repl-password)|" \
                  -e "s|__BACKUP_PASSWORD__|$(cat /creds/backup-password)|" \
                  -e "s|__EXPORTER_PASSWORD__|$(cat /creds/app-password)|" \
                  /initdb/01-users.sql > /mnt/initdb/01-users.sql

              chmod 640 /mnt/config/my.cnf /mnt/initdb/01-users.sql
              echo "ordinal=$ORDINAL server-id=$SERVER_ID read_only=$READ_ONLY"
          securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: ["ALL"]}}
          resources: {requests: {cpu: 10m, memory: 16Mi}, limits: {cpu: 100m, memory: 64Mi}}
          volumeMounts:
            - {name: config-src, mountPath: /config, readOnly: true}
            - {name: initdb-src, mountPath: /initdb, readOnly: true}
            - {name: creds,      mountPath: /creds,  readOnly: true}
            - {name: config,     mountPath: /mnt/config}
            - {name: initdb,     mountPath: /mnt/initdb}
            - {name: data,       mountPath: /var/lib/mysql}

        # ── 2. wait for the primary before a replica starts ──
        - name: wait-for-primary
          image: mysql:8.4
          command:
            - sh
            - -c
            - |
              set -eu
              ORDINAL="${HOSTNAME##*-}"
              [ "$ORDINAL" = "0" ] && { echo "I am the primary; nothing to wait for"; exit 0; }
              echo "waiting for mysql-0.mysql.db.svc.cluster.local:3306"
              i=0
              until mysqladmin ping -h mysql-0.mysql.db.svc.cluster.local -P 3306 \
                      -u root -p"$(cat /creds/root-password)" --silent 2>/dev/null; do
                i=$((i+1)); [ $i -gt 150 ] && { echo "primary never came up"; exit 1; }
                sleep 2
              done
              echo "primary is up"
          securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: ["ALL"]}}
          resources: {requests: {cpu: 20m, memory: 64Mi}, limits: {cpu: 200m, memory: 128Mi}}
          volumeMounts: [{name: creds, mountPath: /creds, readOnly: true}]

      containers:
        - name: mysql
          image: mysql:8.4
          ports:
            - {name: mysql,   containerPort: 3306}
            - {name: metrics, containerPort: 9104}
          securityContext:
            allowPrivilegeEscalation: false
            capabilities: {drop: ["ALL"]}
          env:
            - {name: MYSQL_ROOT_PASSWORD, valueFrom: {secretKeyRef: {name: mysql-creds, key: root-password}}}
            - {name: MYSQL_DATABASE,      value: app}
          args:
            - --defaults-extra-file=/etc/mysql/conf.d/my.cnf
          readinessProbe:
            exec:
              command:
                - sh
                - -c
                - |
                  mysql -h 127.0.0.1 -u root -p"$MYSQL_ROOT_PASSWORD" -e "SELECT 1" >/dev/null 2>&1 || exit 1
                  # ⭐ a replica that is behind must NOT take read traffic
                  if [ "${HOSTNAME##*-}" != "0" ]; then
                    LAG=$(mysql -h 127.0.0.1 -u root -p"$MYSQL_ROOT_PASSWORD" -N -B -e \
                      "SELECT COALESCE(MAX(UNIX_TIMESTAMP()-UNIX_TIMESTAMP(APPLY_TIME)),0)
                       FROM performance_schema.replication_applier_status_by_worker" 2>/dev/null || echo 0)
                    [ "${LAG%.*}" -lt 30 ] || { echo "replication lag ${LAG}s"; exit 1; }
                  fi
            initialDelaySeconds: 30
            periodSeconds: 10
            timeoutSeconds: 8
            failureThreshold: 12
          livenessProbe:
            exec: {command: ["mysqladmin","ping","-h","127.0.0.1","-uroot","-p$(MYSQL_ROOT_PASSWORD)"]}
            initialDelaySeconds: 120
            periodSeconds: 30
            timeoutSeconds: 10
            failureThreshold: 5
          startupProbe:
            exec: {command: ["mysqladmin","ping","-h","127.0.0.1","-uroot","-p$(MYSQL_ROOT_PASSWORD)"]}
            periodSeconds: 10
            failureThreshold: 60          # 10 minutes for crash recovery
            timeoutSeconds: 5
          lifecycle:
            preStop:
              exec:
                # ⭐ stop accepting connections, let in-flight finish, THEN shut down.
                # A SIGKILL mid-transaction = crash recovery on the next boot (minutes).
                command:
                  - sh
                  - -c
                  - |
                    mysql -h 127.0.0.1 -u root -p"$MYSQL_ROOT_PASSWORD" \
                      -e "SET GLOBAL innodb_fast_shutdown=0; SHUTDOWN;" 2>/dev/null || true
                    sleep 15
          resources:
            requests: {cpu: 500m, memory: 1Gi, ephemeral-storage: 1Gi}
            limits:   {cpu: "2",   memory: 2Gi}
          volumeMounts:
            - {name: data,    mountPath: /var/lib/mysql}
            - {name: config,  mountPath: /etc/mysql/conf.d, readOnly: true}
            - {name: initdb,  mountPath: /docker-entrypoint-initdb.d, readOnly: true}

        # ── sidecar: Prometheus exporter ──
        - name: exporter
          image: prom/mysqld-exporter:v0.15.1
          args:
            - --collect.info_schema.innodb_metrics
            - --collect.info_schema.query_response_time
            - --collect.slave_status
            - --collect.binlog_size
          env:
            - name: MYSQLD_EXPORTER_PASSWORD
              valueFrom: {secretKeyRef: {name: mysql-creds, key: app-password}}
            - name: DATA_SOURCE_NAME
              value: "exporter:$(MYSQLD_EXPORTER_PASSWORD)@(127.0.0.1:3306)/"
          ports: [{name: metrics, containerPort: 9104}]
          readinessProbe: {httpGet: {path: /, port: metrics}, periodSeconds: 30}
          resources:
            requests: {cpu: 20m, memory: 32Mi}
            limits:   {cpu: 200m, memory: 128Mi}
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities: {drop: ["ALL"]}

      volumes:
        - {name: config-src, configMap: {name: mysql-config}}
        - {name: initdb-src, configMap: {name: mysql-initdb}}
        - {name: config,     emptyDir: {}}
        - {name: initdb,     emptyDir: {}}
        - name: creds
          secret: {secretName: mysql-creds, defaultMode: 0400}

  volumeClaimTemplates:
    - metadata: {name: data, labels: {app: mysql}}
      spec:
        accessModes: [ReadWriteOnce]
        # storageClassName: ebs-gp3       # ← an SSD class. NEVER run MySQL on HDD.
        resources: {requests: {storage: 20Gi}}
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata: {name: mysql, namespace: db}
spec:
  minAvailable: 1
  selector: {matchLabels: {app: mysql}}
```

### Configure replication

The StatefulSet gives you a primary and a replica, but **replication isn't automatic**. Two options:

**Option A — manual (learn it once):**

```bash
kubectl exec -n db mysql-0 -c mysql -- mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "
  SELECT @@server_id, @@read_only, @@gtid_mode, @@log_bin;"
# 1   0   ON   1        ← primary

kubectl exec -n db mysql-1 -c mysql -- mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "
  SELECT @@server_id, @@read_only, @@gtid_mode, @@log_bin;"
# 2   1   ON   1        ← replica

# point the replica at the primary using GTID auto-positioning
kubectl exec -n db mysql-1 -c mysql -- mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "
  CHANGE REPLICATION SOURCE TO
    SOURCE_HOST='mysql-0.mysql.db.svc.cluster.local',
    SOURCE_PORT=3306,
    SOURCE_USER='repl',
    SOURCE_PASSWORD='R3pl-Pr0d-K8s!-Z5',
    SOURCE_AUTO_POSITION=1,
    SOURCE_CONNECT_RETRY=10,
    SOURCE_RETRY_COUNT=86400,
    GET_SOURCE_PUBLIC_KEY=1;
  START REPLICA;"

sleep 5
kubectl exec -n db mysql-1 -c mysql -- mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "
  SHOW REPLICA STATUS\G" | grep -E 'Replica_IO_Running|Replica_SQL_Running|Seconds_Behind|Last_.*Error|Retrieved_Gtid|Executed_Gtid'
```

```
             Replica_IO_Running: Yes
            Replica_SQL_Running: Yes
                Seconds_Behind_Source: 0
           Retrieved_Gtid_Set: 3e11fa47-…:1-5
            Executed_Gtid_Set: 3e11fa47-…:1-5
```

**Verify end to end:**

```bash
kubectl exec -n db mysql-0 -c mysql -- mysql -u root -p"$MYSQL_ROOT_PASSWORD" -D app -e \
  'INSERT INTO products (name, price) VALUES ("from-primary", 42.00);'
sleep 2
kubectl exec -n db mysql-1 -c mysql -- mysql -u root -p"$MYSQL_ROOT_PASSWORD" -D app -e \
  'SELECT * FROM products WHERE name="from-primary";'
# ✅ replicated

# the replica must REJECT writes
kubectl exec -n db mysql-1 -c mysql -- mysql -u root -p"$MYSQL_ROOT_PASSWORD" -D app -e \
  'INSERT INTO products (name, price) VALUES ("should-fail", 1.00);' 2>&1 | head -2
# ERROR 1290 (HY000): The MySQL server is running with the --super-read-only option
#                     so it cannot execute this statement        ✅
```

**Option B — an operator (what you'd actually do in production):**

| Operator | Notes |
|---|---|
| **Oracle MySQL Operator for Kubernetes** | Official. `InnoDBCluster` CRD, MySQL Router, Group Replication, automatic failover |
| **Percona Operator for MySQL** | Mature, Percona XtraDB Cluster or replication, integrated backups to S3 |
| **Vitess Operator** | Sharding at scale (YouTube's answer). Complex, powerful |

```bash
# Oracle's official operator
kubectl apply -f https://raw.githubusercontent.com/mysql/mysql-operator/trunk/deploy/deploy-crds.yaml
kubectl apply -f https://raw.githubusercontent.com/mysql/mysql-operator/trunk/deploy/deploy-operator.yaml
kubectl get pods -n mysql-operator
```

```yaml
apiVersion: mysql.oracle.com/v2
kind: InnoDBCluster
metadata: {name: shopdb, namespace: db}
spec:
  instances: 3
  router:
    instances: 2
    podSpec:
      containers: [{name: router, resources: {requests: {cpu: 100m, memory: 128Mi}}}]
  secretName: shopdb-cluster-secret
  tlsUseSelfSigned: true
  datadirVolumeClaimTemplate:
    accessModes: [ReadWriteOnce]
    resources: {requests: {storage: 20Gi}}
  mycnf: |
    [mysqld]
    innodb_buffer_pool_size=1G
    max_connections=300
  backupProfiles:
    - name: nightly
      podAnnotations: {}
      podSpec:
        containers:
          - name: xtrabackup
            image: percona/percona-xtrabackup:8.4
            command: ["xtrabackup"]
            args: ["--backup", "--target-dir=/backup"]
            volumeMounts: [{name: backup, mountPath: /backup}]
            env:
              - name: S3_BUCKET
                value: my-mysql-backups
  backupSchedules:
    - name: nightly
      schedule: "0 2 * * *"
      backupProfileName: nightly
      enabled: true
```

That's **automatic failover, Group Replication, backups on a schedule, and a MySQL Router for read/write splitting** — all declarative. Compare it to the ~400 lines above.

### Backups — and the only test that matters

```yaml
# mysql/prod/02-backup-cronjob.yaml
apiVersion: v1
kind: Secret
metadata: {name: s3-creds, namespace: db}
stringData:
  AWS_ACCESS_KEY_ID: "minioadmin"
  AWS_SECRET_ACCESS_KEY: "minioadmin"
---
apiVersion: batch/v1
kind: CronJob
metadata: {name: mysql-backup, namespace: db}
spec:
  schedule: "0 2 * * *"                       # 02:00 daily
  timeZone: "Asia/Kolkata"
  concurrencyPolicy: Forbid                   # ⭐ never two backups at once
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 7
  startingDeadlineSeconds: 3600
  jobTemplate:
    spec:
      backoffLimit: 2
      activeDeadlineSeconds: 7200
      ttlSecondsAfterFinished: 604800
      template:
        metadata: {labels: {app: mysql-backup, task: backup}}
        spec:
          restartPolicy: OnFailure
          serviceAccountName: mysql
          containers:
            - name: backup
              image: mysql:8.4
              command:
                - bash
                - -c
                - |
                  set -euo pipefail
                  STAMP=$(date -u +%Y%m%d-%H%M%S)
                  DEST="/backup/mysql-${STAMP}"
                  mkdir -p "$DEST"

                  echo "▸ 1. logical dump (consistent snapshot, single transaction)"
                  # --single-transaction: consistent without locking InnoDB
                  # --source-data=2:      records the binlog position for point-in-time recovery
                  # --routines --triggers --events: everything, not just tables
                  mysqldump \
                    --host=mysql-rw.db.svc.cluster.local \
                    --user=backup --password="$BACKUP_PASSWORD" \
                    --single-transaction --quick --lock-tables=false \
                    --source-data=2 --routines --triggers --events \
                    --set-gtid-purged=ON \
                    --default-character-set=utf8mb4 \
                    --all-databases \
                    | gzip -6 > "$DEST/full.sql.gz"

                  SIZE=$(du -h "$DEST/full.sql.gz" | cut -f1)
                  echo "▸ 2. dump complete: $SIZE"

                  echo "▸ 3. VERIFY the dump — an unverified backup is not a backup"
                  gunzip -t "$DEST/full.sql.gz"
                  gunzip -c "$DEST/full.sql.gz" | head -50 | grep -q 'MySQL dump' \
                    || { echo "⛔ dump header missing"; exit 1; }
                  gunzip -c "$DEST/full.sql.gz" | tail -5 | grep -q 'Dump completed' \
                    || { echo "⛔ dump truncated — the backup is CORRUPT"; exit 1; }
                  TABLES=$(gunzip -c "$DEST/full.sql.gz" | grep -c '^CREATE TABLE' || true)
                  echo "   ✅ valid gzip, complete, $TABLES CREATE TABLE statements"

                  echo "▸ 4. record metadata"
                  kubectl exec -n db mysql-0 -c mysql -- \
                    mysql -u backup -p"$BACKUP_PASSWORD" -h 127.0.0.1 -N -B -e \
                    "SHOW MASTER STATUS" > "$DEST/binlog-position.txt" 2>/dev/null || true
                  cat > "$DEST/metadata.json" <<META
                  {"timestamp":"$STAMP","size":"$SIZE","tables":$TABLES,
                   "source":"mysql-rw.db.svc.cluster.local","tool":"mysqldump 8.4"}
                  META

                  echo "▸ 5. upload to object storage"
                  aws s3 cp --recursive "$DEST" "s3://$S3_BUCKET/mysql/$STAMP/" \
                    --storage-class STANDARD_IA --only-show-errors
                  rm -rf "$DEST"

                  echo "▸ 6. prune: keep 7 daily, 4 weekly, 6 monthly"
                  aws s3 ls "s3://$S3_BUCKET/mysql/" | awk '{print $2}' | sort -r | tail -n +8 \
                    | while read -r old; do
                        aws s3 rm --recursive "s3://$S3_BUCKET/mysql/$old" --only-show-errors
                        echo "   pruned $old"
                      done

                  echo "✅ backup $STAMP complete"
              env:
                - {name: BACKUP_PASSWORD, valueFrom: {secretKeyRef: {name: mysql-creds, key: backup-password}}}
                - {name: S3_BUCKET, value: mysql-backups}
                - {name: AWS_ACCESS_KEY_ID,     valueFrom: {secretKeyRef: {name: s3-creds, key: AWS_ACCESS_KEY_ID}}}
                - {name: AWS_SECRET_ACCESS_KEY, valueFrom: {secretKeyRef: {name: s3-creds, key: AWS_SECRET_ACCESS_KEY}}}
                - {name: AWS_ENDPOINT_URL, value: "http://minio.minio.svc.cluster.local:9000"}
              resources:
                requests: {cpu: 200m, memory: 256Mi}
                limits:   {cpu: "1",   memory: 1Gi}
              volumeMounts: [{name: scratch, mountPath: /backup}]
          volumes:
            - {name: scratch, emptyDir: {sizeLimit: 20Gi}}
```

**Now the restore test — do this or your backups are theatre:**

```bash
# restore into a THROWAWAY instance and verify the data
kubectl run mysql-restore-test -n db --rm -it --restart=Never \
  --image=mysql:8.4 --overrides='{"spec":{"containers":[{"name":"m","image":"mysql:8.4",
  "command":["bash","-c","
    set -eu
    mysqld --initialize-insecure --user=mysql --datadir=/tmp/data &
    sleep 25
    LATEST=$(aws s3 ls s3://mysql-backups/mysql/ | awk \"{print \\$2}\" | sort -r | head -1)
    echo restoring $LATEST
    aws s3 cp s3://mysql-backups/mysql/$LATEST/full.sql.gz /tmp/
    gunzip -c /tmp/full.sql.gz | mysql -u root --socket=/tmp/mysql.sock
    mysql -u root --socket=/tmp/mysql.sock -D app -e \"SELECT COUNT(*) AS products FROM products;\"
    mysqladmin -u root --socket=/tmp/mysql.sock shutdown
  "],"env":[{"name":"AWS_ENDPOINT_URL","value":"http://minio.minio.svc.cluster.local:9000"}],
  "volumeMounts":[{"name":"t","mountPath":"/tmp"}]}],"volumes":[{"name":"t","emptyDir":{}}]}}'
```

Expected: `products: 3`. **If this fails, you have no backups.** Fix it before anything else.

### Failover drill

```bash
echo "▸ before"
kubectl get pods -n db -l app=mysql -L role
kubectl exec -n db mysql-0 -c mysql -- mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e 'SELECT @@hostname, @@read_only;'

# kill the primary
kubectl delete pod -n db mysql-0
kubectl get pods -n db -l app=mysql -w
```

**What you'll discover — and this is the whole lesson:**

```
mysql-0   0/2   Terminating   …
mysql-0   0/2   Pending       …
mysql-0   0/2   Init:0/2      …
mysql-0   1/2   Running       …
mysql-0   2/2   Running       …
```

`mysql-1` **did not become the primary.** A StatefulSet gives you stable identity and storage — **it does not give you failover.** For 60 seconds your writes are down.

Manual promotion:

```bash
# 1. confirm the replica has caught up
kubectl exec -n db mysql-1 -c mysql -- mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e \
  "SHOW REPLICA STATUS\G" | grep -E 'Seconds_Behind|Replica_IO_Running|Replica_SQL_Running'

# 2. make it writable
kubectl exec -n db mysql-1 -c mysql -- mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "
  STOP REPLICA; RESET REPLICA ALL;
  SET GLOBAL read_only=OFF; SET GLOBAL super_read_only=OFF;"

# 3. move the label so mysql-rw points at it
kubectl label pod -n db mysql-1 role=primary --overwrite
kubectl label pod -n db mysql-1 role=replica --overwrite 2>/dev/null || true
kubectl get endpointslices -n db -l kubernetes.io/service-name=mysql-rw

# 4. when mysql-0 comes back, re-point it as a replica of mysql-1
kubectl exec -n db mysql-0 -c mysql -- mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "
  SET GLOBAL super_read_only=OFF;
  CHANGE REPLICATION SOURCE TO
    SOURCE_HOST='mysql-1.mysql.db.svc.cluster.local', SOURCE_PORT=3306,
    SOURCE_USER='repl', SOURCE_PASSWORD='R3pl-Pr0d-K8s!-Z5',
    SOURCE_AUTO_POSITION=1, GET_SOURCE_PUBLIC_KEY=1;
  START REPLICA;
  SET GLOBAL read_only=ON; SET GLOBAL super_read_only=ON;"
kubectl label pod -n db mysql-0 role=replica --overwrite
```

**That took 4 minutes by hand. That's exactly what an operator automates.** With the Oracle operator, Group Replication elects a new primary in ~10 s and MySQL Router follows automatically.

### MySQL tasks

<details>
<summary>Task 13.1.1 — Size `innodb_buffer_pool_size` correctly and prove it</summary>

**The single most important MySQL setting, and the most commonly wrong.**

The rule: **60–70% of the memory available to mysqld**, and mysqld must fit inside the container limit with room for everything else.

```
container limit           2048 Mi
innodb_buffer_pool_size   1200 Mi   (58%)
+ per-connection buffers  ~300 Mi   (300 conns × ~1 MiB)
+ InnoDB logs, adaptive hash, data dictionary, temp tables  ~250 Mi
+ OS/page-cache overhead  ~200 Mi
─────────────────────────────────
                          ~1950 Mi  ✅ under 2048
```

**Set it wrong in either direction:**

| Mistake | Result |
|---|---|
| Too small (256 Mi with a 10 GiB dataset) | Every query hits disk. 10–100× slower |
| Too large (1.8 Gi of a 2 Gi limit) | **OOMKilled.** mysqld uses buffer pool + connection buffers + overhead |

**Measure what you have:**

```bash
kubectl exec -n db mysql-0 -c mysql -- mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "
  SELECT @@innodb_buffer_pool_size/1024/1024 AS pool_mb,
         @@innodb_buffer_pool_instances AS instances,
         @@max_connections AS max_conn,
         @@innodb_log_file_size/1024/1024 AS redo_log_mb,
         @@innodb_flush_log_at_trx_commit AS flush_trx,
         @@innodb_flush_method AS flush_method;"
```

**Measure whether it's the right size:**

```bash
kubectl exec -n db mysql-0 -c mysql -- mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "
  SHOW GLOBAL STATUS LIKE 'Innodb_buffer_pool_%';" | grep -E 'read_requests|reads|pages_data|pages_free|pages_total|wait'
```

```
Innodb_buffer_pool_read_requests   48210394    ← logical reads (from the pool)
Innodb_buffer_pool_reads              12048    ← physical reads (from DISK)
Innodb_buffer_pool_pages_data          8192
Innodb_buffer_pool_pages_free           512
Innodb_buffer_pool_pages_total         8704
```

**Hit ratio:**

```
hit ratio = 1 - (reads / read_requests)
          = 1 - (12048 / 48210394)
          = 99.97%      ✅ excellent. Target: > 99% for OLTP
```

If it's below 99%, your working set doesn't fit. Options: raise the pool, add replicas for reads, or fix the queries.

**Is the pool full?**

```
pages_free / pages_total = 512 / 8704 = 5.9% free
```

Under 10% free means you're at capacity — more data would evict hot pages.

**Prometheus version (the right way):**

```promql
# hit ratio
1 - (rate(mysql_global_status_innodb_buffer_pool_reads[5m])
     / rate(mysql_global_status_innodb_buffer_pool_read_requests[5m]))

# % of the pool that's dirty (flush pressure)
mysql_global_status_innodb_buffer_pool_pages_dirty
  / mysql_global_status_innodb_buffer_pool_pages_total * 100
```

```yaml
- alert: MySQLBufferPoolHitRatioLow
  expr: |
    1 - (rate(mysql_global_status_innodb_buffer_pool_reads[5m])
         / rate(mysql_global_status_innodb_buffer_pool_read_requests[5m])) < 0.99
  for: 15m
  labels: {severity: warning}
  annotations:
    summary: "InnoDB buffer pool hit ratio is {{ $value | humanizePercentage }}"
    description: "The working set doesn't fit in innodb_buffer_pool_size. Raise it or fix the queries."
```

**Now the container side — is mysqld actually inside its limit?**

```bash
kubectl top pod -n db mysql-0 --containers
# POD      CONTAINER   CPU     MEMORY
# mysql-0  mysql       312m    1418Mi      ← 69% of the 2 Gi limit ✅
# mysql-0  exporter     12m      34Mi

kubectl exec -n db mysql-0 -c mysql -- cat /sys/fs/cgroup/memory.current
kubectl exec -n db mysql-0 -c mysql -- cat /sys/fs/cgroup/memory.max
kubectl exec -n db mysql-0 -c mysql -- cat /sys/fs/cgroup/memory.stat | head -20
```

**Per-connection memory — the part everyone forgets:**

```bash
kubectl exec -n db mysql-0 -c mysql -- mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "
  SELECT
    (@@sort_buffer_size + @@read_buffer_size + @@read_rnd_buffer_size
     + @@join_buffer_size + @@thread_stack + @@binlog_cache_size) / 1024 AS per_conn_kb,
    @@max_connections AS max_conn,
    ((@@sort_buffer_size + @@read_buffer_size + @@read_rnd_buffer_size
      + @@join_buffer_size + @@thread_stack + @@binlog_cache_size)
     * @@max_connections) / 1024 / 1024 AS worst_case_conn_mb;"
```

```
per_conn_kb  max_conn  worst_case_conn_mb
       1024        300                 300
```

So: `buffer_pool (1200) + connections (300) + overhead (250) = 1750 Mi` → a **2 Gi** limit is right, and **1.5 Gi would OOMKill you under a connection spike.**

```yaml
resources:
  requests: {memory: 2Gi}
  limits:   {memory: 2Gi}     # ⭐ Guaranteed QoS for a database. Burstable = eviction risk.
```

> 🔑 **Databases should have `requests == limits` for memory.** A Burstable Pod is evicted first when a node runs low — and evicting MySQL means crash recovery on restart.

**Iterate:**

```bash
# raise the pool and re-measure the hit ratio
kubectl exec -n db mysql-0 -c mysql -- mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e \
  "SET GLOBAL innodb_buffer_pool_size = 1610612736;"   # 1.5 GiB — resizable online in MySQL 8
kubectl exec -n db mysql-0 -c mysql -- mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e \
  "SHOW STATUS LIKE 'Innodb_buffer_pool_resize_status';"
# then update the ConfigMap so it survives a restart
```

</details>

<details>
<summary>Task 13.1.2 — Do a point-in-time recovery (restore to 14:37, not 02:00)</summary>

The nightly backup is from 02:00. Someone dropped a table at 14:37. Recover to 14:36.

```bash
# ── 1. Establish the timeline ──
kubectl exec -n db mysql-0 -c mysql -- mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "
  SHOW BINARY LOGS;
  SHOW MASTER STATUS;"
```

```
+------------------+-----------+
| Log_name         | File_size |
+------------------+-----------+
| mysql-bin.000012 |  10485921 |
| mysql-bin.000013 |   8391022 |
+------------------+-----------+
File: mysql-bin.000013  Position: 8391022  GTID: 3e11fa47-…:1-8412
```

The 02:00 backup recorded its GTID set:

```bash
aws s3 cp s3://mysql-backups/mysql/20260909-020000/full.sql.gz - | gunzip -c | head -30 \
  | grep -i 'GTID\|CHANGE'
# SET @@GLOBAL.GTID_PURGED='3e11fa47-771a-11ef-…:1-6201';
```

So you must replay GTIDs **6202 → 8410** (8411 is the `DROP TABLE`).

```bash
# ── 2. Find the exact GTID/position of the DROP ──
kubectl exec -n db mysql-0 -c mysql -- mysqlbinlog \
  --read-from-remote-server -h 127.0.0.1 -u backup -p"$BACKUP_PASSWORD" \
  --raw --to-last-log mysql-bin.000013
kubectl exec -n db mysql-0 -c mysql -- sh -c '
  mysqlbinlog --base64-output=DECODE-ROWS -vv mysql-bin.000013 \
    | grep -n -B8 "DROP TABLE.*products"'
```

```
# at 7842110
#260909 14:37:02 server id 1  end_log_pos 7842188  GTID  last_committed=8410  sequence_number=8411
# SET @@SESSION.GTID_NEXT= '3e11fa47-…:8411'/*!*/;
# DROP TABLE `app`.`products`
```

**Stop before position 7842110 / before GTID 8411.**

```bash
# ── 3. Restore into a scratch instance (NEVER into production first) ──
kubectl run pitr -n db --rm -it --restart=Never --image=mysql:8.4 -- bash
# inside:
set -eu
mkdir -p /tmp/pitr && cd /tmp/pitr

# 3a. the base dump
aws s3 cp s3://mysql-backups/mysql/20260909-020000/full.sql.gz .
mysqld --initialize-insecure --user=mysql --datadir=/tmp/pitr/data \
       --socket=/tmp/pitr/mysql.sock --port=3307 --pid-file=/tmp/pitr/mysql.pid &
for i in $(seq 1 60); do mysqladmin --socket=/tmp/pitr/mysql.sock ping 2>/dev/null && break; sleep 2; done

gunzip -c full.sql.gz | mysql --socket=/tmp/pitr/mysql.sock -u root

# 3b. fetch the binlogs
mysqlbinlog --read-from-remote-server \
  -h mysql-rw.db.svc.cluster.local -u backup -p"$BACKUP_PASSWORD" \
  --raw --to-last-log mysql-bin.000012

# 3c. replay up to (not including) the DROP
mysqlbinlog --stop-before-gtids='3e11fa47-771a-11ef-…:8411' \
  mysql-bin.000012 mysql-bin.000013 \
  | mysql --socket=/tmp/pitr/mysql.sock -u root

# 3d. VERIFY
mysql --socket=/tmp/pitr/mysql.sock -u root -D app -e "
  SELECT COUNT(*) AS products FROM products;
  SELECT MAX(created_at) AS newest FROM products;
  SHOW TABLES;"
```

```
products: 8410
newest: 2026-09-09 14:36:58        ← ✅ one second before the DROP
```

```bash
# ── 4. Promote the recovered data ──
# Option A: rename and swap (fast, seconds of downtime)
mysqldump --socket=/tmp/pitr/mysql.sock -u root --single-transaction --databases app \
  | mysql -h mysql-rw.db.svc.cluster.local -u root -p"$MYSQL_ROOT_PASSWORD"

# Option B: rename the broken table first, so you can compare
kubectl exec -n db mysql-0 -c mysql -- mysql -u root -p"$MYSQL_ROOT_PASSWORD" -D app -e "
  CREATE TABLE products_recovered LIKE products;"
```

```bash
# ── 5. Sanity-check the replica didn't apply the DROP too ──
kubectl exec -n db mysql-1 -c mysql -- mysql -u root -p"$MYSQL_ROOT_PASSWORD" -D app -e "SHOW TABLES;"
# ⛔ the DROP replicated. Both are broken. That's why you recovered from binlogs.
```

**Prevention — make this a 30-second recovery instead of a 30-minute one:**

```sql
-- 1. never grant DROP to the application user
REVOKE DROP ON app.* FROM 'app'@'%';

-- 2. require a WHERE on UPDATE/DELETE for interactive sessions
SET GLOBAL sql_require_primary_key = ON;

-- 3. keep binlogs long enough (7 days above; 14 is safer)
SET PERSIST binlog_expire_logs_seconds = 1209600;
```

```yaml
# 4. alert on DDL in production
- alert: MySQLUnexpectedDDL
  expr: increase(mysql_global_status_com_drop_table[5m]) > 0
  for: 0m
  labels: {severity: critical}
  annotations:
    summary: "A table was dropped in production in the last 5 minutes"
```

</details>

<details>
<summary>Task 13.1.3 — Make MySQL survive a node drain with zero data loss</summary>

```bash
# ── the drain ──
NODE=$(kubectl get pod -n db mysql-0 -o jsonpath='{.spec.nodeName}')
kubectl get pods -n db -o wide | grep $NODE
kubectl drain $NODE --ignore-daemonsets --delete-emptydir-data --timeout=300s
```

**What happens without preparation:**

```
evicting pod db/mysql-0
error when evicting pods/"mysql-0" -n "db" (will retry after 5s):
  Cannot evict pod as it would violate the pod's disruption budget.
  The pod disruption budget specifies minAvailable: 1
```

The PDB blocks it. That's *correct* behaviour, but it means your drain hangs forever. Fix the ordering:

```bash
# 1. promote the replica FIRST (so minAvailable is still satisfied afterwards)
kubectl exec -n db mysql-1 -c mysql -- mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "
  SHOW REPLICA STATUS\G" | grep 'Seconds_Behind_Source'      # must be 0
kubectl exec -n db mysql-1 -c mysql -- mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "
  STOP REPLICA; RESET REPLICA ALL;
  SET GLOBAL read_only=OFF; SET GLOBAL super_read_only=OFF;"
kubectl label pod -n db mysql-1 role=primary --overwrite
kubectl label pod -n db mysql-0 role=replica --overwrite

# 2. flush everything to disk before eviction
kubectl exec -n db mysql-0 -c mysql -- mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "
  SET GLOBAL innodb_fast_shutdown=0;
  SET GLOBAL innodb_max_dirty_pages_pct=0;"
kubectl exec -n db mysql-0 -c mysql -- mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "
  SHOW GLOBAL STATUS LIKE 'Innodb_buffer_pool_pages_dirty';"    # wait until ~0

# 3. now drain
kubectl drain $NODE --ignore-daemonsets --delete-emptydir-data --timeout=600s
```

**Verify zero data loss:**

```bash
# before the drain: write a canary every second
kubectl run canary -n db --rm -it --restart=Never --image=mysql:8.4 -- sh -c '
  i=0
  while true; do
    i=$((i+1))
    mysql -h mysql-rw.db.svc.cluster.local -u app -p"App-Pr0d-K8s!-Y2" -D app \
      -e "INSERT INTO canary (seq, note) VALUES ($i, NOW())" 2>&1 || echo "$i FAILED"
    sleep 1
  done' &
CANARY=$!

kubectl drain $NODE --ignore-daemonsets --delete-emptydir-data --timeout=600s
sleep 60
kill $CANARY

kubectl exec -n db mysql-1 -c mysql -- mysql -u root -p"$MYSQL_ROOT_PASSWORD" -D app -e \
  "SELECT COUNT(*) AS written, MAX(seq) AS highest, MIN(seq) AS lowest FROM canary;"
```

```
written  highest  lowest
    118      121      1     ← 3 gaps. Those are the failed writes during promotion.
```

**Which gaps are acceptable?**
- With `innodb_flush_log_at_trx_commit = 1` and `sync_binlog = 1` (both set above), **every acknowledged commit is durable.** A failed INSERT that returned an error was never committed. That's zero data loss.
- With `trx_commit = 2` or `sync_binlog = 0`, you lose up to a second of *acknowledged* writes on a crash. Faster, but not zero-loss.

```bash
kubectl exec -n db mysql-1 -c mysql -- mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "
  SELECT @@innodb_flush_log_at_trx_commit AS trx_commit,
         @@sync_binlog AS sync_binlog,
         @@innodb_flush_method AS flush_method;"
# 1   1   O_DIRECT     ← the only zero-loss combination
```

**The PV must follow the Pod.** Check the StorageClass:

```bash
kubectl get pvc -n db -l app=mysql
kubectl get pv $(kubectl get pvc -n db data-mysql-0 -o jsonpath='{.spec.volumeName}') -o yaml \
  | grep -A6 nodeAffinity
```

```yaml
  nodeAffinity:
    required:
      nodeSelectorTerms:
        - matchExpressions:
            - {key: topology.kubernetes.io/zone, operator: In, values: [us-east-1a]}
```

⛔ **The PV is zoned.** If the drained node was the only one in `us-east-1a`, `mysql-0` will be **Pending forever**:

```bash
kubectl describe pod -n db mysql-0 | grep -A5 Events
# 0/3 nodes are available: 1 node(s) had untolerated taint {node.kubernetes.io/unreachable: },
# 2 node(s) didn't match PersistentVolume's node affinity/selector.
```

**Fixes, in order of preference:**
1. **Keep a node in every zone** the PV is bound to (usually automatic)
2. **Use a storage class without zone pinning** (network storage: Ceph, Longhorn, NFS)
3. **Detach and re-attach** — cloud providers do this automatically for EBS/PD, but it takes 1–6 min
4. **Snapshot + restore into the new zone** — the last resort, and slow

```bash
# un-drain when done
kubectl uncordon $NODE
```

**The full pre-drain checklist for any database:**

- [ ] Replication lag is 0
- [ ] A replica has been promoted (or you accept the downtime)
- [ ] `innodb_fast_shutdown=0` and dirty pages flushed
- [ ] A backup ran successfully in the last N hours — **verify it restores**
- [ ] The PDB is `minAvailable: 1` with ≥2 replicas (not `maxUnavailable: 1` with 1 replica)
- [ ] The PV's zone has a schedulable node
- [ ] You know how long re-attachment takes for your storage class
- [ ] Alerts are silenced, and un-silenced afterwards

</details>

---
---

# 13.2 — MongoDB 7

## 🔵 Case 1 — single-node replica set (10 minutes)

> 🔑 **MongoDB on Kubernetes always needs a replica set — even with one node.** Transactions, change streams, and the modern drivers all require it. A standalone `mongod` is a dead end.

```bash
mkdir -p ~/k8s-learn/p13/mongo && cd ~/k8s-learn/p13
```

`mongo/simple.yaml`:

```yaml
apiVersion: v1
kind: Secret
metadata: {name: mongo-creds}
stringData:
  MONGO_INITDB_ROOT_USERNAME: admin
  MONGO_INITDB_ROOT_PASSWORD: "Adm1n-Learn-K8s!"
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: mongo-data}
spec:
  accessModes: [ReadWriteOnce]
  resources: {requests: {storage: 5Gi}}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: mongo, labels: {app: mongo}}
spec:
  replicas: 1
  selector: {matchLabels: {app: mongo}}
  strategy: {type: Recreate}
  template:
    metadata: {labels: {app: mongo}}
    spec:
      containers:
        - name: mongo
          image: mongo:7
          ports: [{name: mongo, containerPort: 27017}]
          envFrom: [{secretRef: {name: mongo-creds}}]
          # ⭐ --replSet from day one
          args: ["--replSet", "rs0", "--bind_ip_all", "--keyFile", "/etc/mongo-keyfile/mongo-key"]
          readinessProbe:
            exec:
              command:
                - sh
                - -c
                - |
                  mongosh --quiet -u "$MONGO_INITDB_ROOT_USERNAME" -p "$MONGO_INITDB_ROOT_PASSWORD" \
                    --authenticationDatabase admin --eval '
                      const s = rs.status();
                      if (s.myState !== 1 && s.myState !== 2) { quit(1); }   // PRIMARY or SECONDARY
                      db.adminCommand({ping: 1}).ok' | grep -q '^1$'
            initialDelaySeconds: 20
            periodSeconds: 10
            failureThreshold: 30
          livenessProbe:
            exec: {command: ["mongosh","--quiet","--eval","db.adminCommand({ping:1}).ok","||","quit(1)"]}
            initialDelaySeconds: 45
            periodSeconds: 30
          resources:
            requests: {cpu: 250m, memory: 512Mi}
            limits:   {cpu: "1",   memory: 1Gi}
          volumeMounts:
            - {name: data,    mountPath: /data/db}
            - {name: keyfile, mountPath: /etc/mongo-keyfile, readOnly: true}
      volumes:
        - {name: data, persistentVolumeClaim: {claimName: mongo-data}}
        - name: keyfile
          secret:
            secretName: mongo-keyfile
            defaultMode: 0400          # ⭐ mongod REFUSES to start if this isn't 0400/0600
---
apiVersion: v1
kind: Service
metadata: {name: mongo}
spec:
  selector: {app: mongo}
  ports: [{name: mongo, port: 27017}]
```

The keyfile (internal cluster auth — required for any replica set):

```bash
# base64, 6-1024 chars, no whitespace issues
openssl rand -base64 756 | tr -d '\n' | head -c 900 > /tmp/mongo-key
kubectl create secret generic mongo-keyfile --from-file=mongo-key=/tmp/mongo-key
shred -u /tmp/mongo-key
```

```bash
kubectl apply -f mongo/simple.yaml
kubectl rollout status deploy/mongo --timeout=180s
kubectl logs deploy/mongo --tail=30 | grep -iE 'repl|election|waiting'
```

**Initialize the replica set** (one-time):

```bash
kubectl exec -it deploy/mongo -- mongosh -u admin -p'Adm1n-Learn-K8s!' --authenticationDatabase admin --eval '
  rs.initiate({
    _id: "rs0",
    members: [{ _id: 0, host: "mongo:27017" }]
  });'
```

```json
{ "ok" : 1 }
```

```bash
sleep 10
kubectl exec -it deploy/mongo -- mongosh -u admin -p'Adm1n-Learn-K8s!' --authenticationDatabase admin --eval '
  rs.status().members.map(m => ({name: m.name, state: m.stateStr, health: m.health}));
  rs.conf().members.length;
  db.hello().isWritablePrimary;'
```

```
[ { name: 'mongo:27017', state: 'PRIMARY', health: 1 } ]
1
true
```

**Use it:**

```bash
kubectl exec -it deploy/mongo -- mongosh -u admin -p'Adm1n-Learn-K8s!' --authenticationDatabase admin app --eval '
  db.products.insertMany([
    {name: "Widget", price: 9.99, tags: ["blue","small"], created: new Date()},
    {name: "Gadget", price: 19.99, tags: ["red"], nested: {specs: {weight: 250}}}
  ]);
  db.products.find().pretty();
  db.products.createIndex({name: "text"});
  db.products.createIndex({price: -1});
  db.products.aggregate([{$group: {_id: null, avg: {$avg: "$price"}, n: {$sum: 1}}}]);
  db.getCollectionInfos().map(c => c.name);'
```

## 🟢 Case 2 — three-member replica set StatefulSet with per-Pod DNS (45 minutes)

**The Kubernetes-specific problem:** a MongoDB replica set needs **stable, resolvable hostnames** for each member. `mongo-abc123.default.svc` changes on every restart, and then the replica set can't find its own members — permanently. This is *the* reason StatefulSets exist.

```
        ┌──────────────────────────────────────────────┐
        │  Service: mongo (headless)                   │
        │  mongo-0.mongo.db.svc.cluster.local:27017    │  PRIMARY
        │  mongo-1.mongo.db.svc.cluster.local:27017    │  SECONDARY
        │  mongo-2.mongo.db.svc.cluster.local:27017    │  SECONDARY
        └──────────────────────────────────────────────┘
                            ▲
              readPreference=secondaryPreferred
                    from the app
```

`mongo/prod/01-statefulset.yaml`:

```yaml
apiVersion: v1
kind: Namespace
metadata: {name: db, labels: {team: data}}
---
apiVersion: v1
kind: Secret
metadata: {name: mongo-creds, namespace: db}
stringData:
  username: admin
  password: "Adm1n-Pr0d-K8s!-Q7"
  app-username: shop
  app-password: "Sh0p-Pr0d-K8s!-R3"
---
# ⭐ HEADLESS — this is what gives each Pod a stable DNS name
apiVersion: v1
kind: Service
metadata:
  name: mongo
  namespace: db
  labels: {app: mongo}
spec:
  clusterIP: None
  selector: {app: mongo}
  ports: [{name: mongo, port: 27017}]
  publishNotReadyAddresses: true    # ⭐ members must resolve each other during init
---
# A normal Service that follows the PRIMARY (relabel on failover)
apiVersion: v1
kind: Service
metadata: {name: mongo-primary, namespace: db}
spec:
  selector: {app: mongo, role: primary}
  ports: [{name: mongo, port: 27017}]
---
apiVersion: v1
kind: ServiceAccount
metadata: {name: mongo, namespace: db}
automountServiceAccountToken: false
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mongo
  namespace: db
  labels: {app: mongo}
spec:
  serviceName: mongo                # ⭐ must match the headless Service
  replicas: 3
  # ⭐ Parallel: all three start at once. Mongo elects its own primary —
  # Kubernetes has no opinion about which member should be first.
  podManagementPolicy: Parallel
  updateStrategy:
    type: RollingUpdate
  selector: {matchLabels: {app: mongo}}
  template:
    metadata: {labels: {app: mongo}}
    spec:
      serviceAccountName: mongo
      terminationGracePeriodSeconds: 120
      securityContext:
        fsGroup: 999
        runAsUser: 999
        runAsGroup: 999
        runAsNonRoot: true
        seccompProfile: {type: RuntimeDefault}
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            - labelSelector: {matchLabels: {app: mongo}}
              topologyKey: kubernetes.io/hostname
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: ScheduleAnyway
          labelSelector: {matchLabels: {app: mongo}}

      initContainers:
        # fix permissions on a freshly provisioned volume
        - name: init-perms
          image: busybox:1.37
          command: ["sh","-c","mkdir -p /data/db /data/configdb && chown -R 999:999 /data && chmod 750 /data/db"]
          securityContext: {runAsUser: 0}        # needs root to chown
          volumeMounts: [{name: data, mountPath: /data}]
          resources: {requests: {cpu: 10m, memory: 16Mi}, limits: {cpu: 100m, memory: 64Mi}}

        # ⭐ the replica-set bootstrap: mongo-0 initiates, others join
        - name: init-replset
          image: mongo:7
          command:
            - bash
            - -c
            - |
              set -euo pipefail
              ORDINAL="${HOSTNAME##*-}"
              SVC="mongo.db.svc.cluster.local"
              AUTH=(-u "$MONGO_USERNAME" -p "$MONGO_PASSWORD" --authenticationDatabase admin)

              echo "I am mongo-$ORDINAL"

              # wait for MY OWN DNS to resolve (StatefulSet publishes it)
              for i in $(seq 1 60); do
                if getent hosts "$HOSTNAME.$SVC" >/dev/null 2>&1; then break; fi
                echo "waiting for my DNS ($i)"; sleep 2
              done

              if [ "$ORDINAL" = "0" ]; then
                # Am I already initialised? (restart case)
                if mongosh --quiet "${AUTH[@]}" --eval 'rs.status().ok' 2>/dev/null | grep -q '^1$'; then
                  echo "replica set already initialised"
                else
                  # wait for the other two to be reachable
                  for n in 1 2; do
                    for i in $(seq 1 90); do
                      if mongosh --quiet "mongodb://mongo-$n.$SVC:27017" --eval 'db.adminCommand({ping:1}).ok' 2>/dev/null | grep -q '^1$'; then
                        echo "mongo-$n reachable"; break
                      fi
                      [ $i -eq 90 ] && echo "mongo-$n not reachable yet — initiating with 1 member"
                      sleep 2
                    done
                  done
                  mongosh --quiet --eval "
                    rs.initiate({
                      _id: 'rs0',
                      members: [
                        {_id: 0, host: 'mongo-0.$SVC:27017', priority: 2},
                        {_id: 1, host: 'mongo-1.$SVC:27017', priority: 1},
                        {_id: 2, host: 'mongo-2.$SVC:27017', priority: 1}
                      ]
                    });"
                  echo "replica set initiated"
                fi
              else
                # secondaries just wait for the set to exist
                for i in $(seq 1 150); do
                  if mongosh --quiet "${AUTH[@]}" --host "mongo-0.$SVC:27017" \
                       --eval 'rs.status().ok' 2>/dev/null | grep -q '^1$'; then
                    echo "replica set is up"; break
                  fi
                  sleep 2
                done
              fi
          env:
            - {name: MONGO_USERNAME, valueFrom: {secretKeyRef: {name: mongo-creds, key: username}}}
            - {name: MONGO_PASSWORD, valueFrom: {secretKeyRef: {name: mongo-creds, key: password}}}
          securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: ["ALL"]}}
          resources: {requests: {cpu: 50m, memory: 128Mi}, limits: {cpu: 500m, memory: 256Mi}}

      containers:
        - name: mongo
          image: mongo:7
          ports: [{name: mongo, containerPort: 27017}]
          securityContext:
            allowPrivilegeEscalation: false
            capabilities: {drop: ["ALL"]}
          env:
            - {name: MONGO_USERNAME, valueFrom: {secretKeyRef: {name: mongo-creds, key: username}}}
            - {name: MONGO_PASSWORD, valueFrom: {secretKeyRef: {name: mongo-creds, key: password}}}
          args:
            - --replSet=rs0
            - --bind_ip_all
            - --keyFile=/etc/mongo-keyfile/mongo-key
            - --wiredTigerCacheSizeGB=0.5          # ⭐ see the memory note below
            - --setParameter=diagnosticDataCollectionEnabled=true
            - --slowms=100                           # log queries slower than 100ms
            - --profile=1
            - --oplogSize=2048                       # MB of oplog; bigger = longer resync window
          readinessProbe:
            exec:
              command:
                - mongosh
                - --quiet
                - -u
                - $(MONGO_USERNAME)
                - -p
                - $(MONGO_PASSWORD)
                - --authenticationDatabase=admin
                - --eval
                - |
                  const s = rs.status();
                  if (!s.ok) quit(1);
                  const me = s.members.find(m => m.self);
                  if (!me || (me.stateStr !== 'PRIMARY' && me.stateStr !== 'SECONDARY')) quit(1);
                  if (me.stateStr === 'SECONDARY' && me.optimeDate < new Date(Date.now() - 30000)) quit(1);
                  db.adminCommand({ping: 1}).ok ? print('1') : quit(1);
            initialDelaySeconds: 30
            periodSeconds: 10
            timeoutSeconds: 8
            failureThreshold: 12
          livenessProbe:
            exec:
              command: ["mongosh","--quiet","--eval","db.adminCommand({ping:1}).ok ? print('1') : quit(1)"]
            initialDelaySeconds: 90
            periodSeconds: 30
            timeoutSeconds: 10
            failureThreshold: 5
          lifecycle:
            preStop:
              exec:
                # ⭐ step down BEFORE terminating, so a new primary is elected first
                command:
                  - mongosh
                  - --quiet
                  - -u
                  - $(MONGO_USERNAME)
                  - -p
                  - $(MONGO_PASSWORD)
                  - --authenticationDatabase=admin
                  - --eval
                  - |
                    try {
                      if (db.hello().isWritablePrimary) {
                        print('stepping down');
                        db.adminCommand({replSetStepDown: 30, force: true});
                      }
                    } catch (e) { print('stepdown: ' + e); }
                    db.adminCommand({fsync: 1});      // flush to disk
          resources:
            requests: {cpu: 500m, memory: 1Gi, ephemeral-storage: 2Gi}
            limits:   {cpu: "2",   memory: 2Gi}
          volumeMounts:
            - {name: data,    mountPath: /data/db}
            - {name: keyfile, mountPath: /etc/mongo-keyfile, readOnly: true}
            - {name: tmp,     mountPath: /tmp}

      volumes:
        - name: keyfile
          secret: {secretName: mongo-keyfile, defaultMode: 0400}
        - {name: tmp, emptyDir: {sizeLimit: 256Mi}}

  volumeClaimTemplates:
    - metadata: {name: data, labels: {app: mongo}}
      spec:
        accessModes: [ReadWriteOnce]
        resources: {requests: {storage: 20Gi}}
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata: {name: mongo, namespace: db}
spec:
  minAvailable: 2               # ⭐ 3 members → a majority of 2 must survive
  selector: {matchLabels: {app: mongo}}
```

```bash
kubectl apply -f mongo/prod/01-statefulset.yaml
kubectl get pods -n db -l app=mongo -w
```

```
mongo-0   0/1   Init:0/2   …
mongo-1   0/1   Init:0/2   …      ← Parallel: all three at once
mongo-2   0/1   Init:0/2   …
mongo-0   0/1   Init:1/2   …
mongo-1   1/1   Running    …
mongo-2   1/1   Running    …
mongo-0   1/1   Running    …
```

```bash
kubectl exec -n db mongo-0 -- mongosh --quiet -u admin -p'Adm1n-Pr0d-K8s!-Q7' --authenticationDatabase admin --eval '
  rs.status().members.map(m => `${m.name}  ${m.stateStr}  health=${m.health}`);
  rs.conf().settings;
  db.hello();'
```

```
mongo-0.mongo.db.svc.cluster.local:27017  PRIMARY    health=1
mongo-1.mongo.db.svc.cluster.local:27017  SECONDARY  health=1
mongo-2.mongo.db.svc.cluster.local:27017  SECONDARY  health=1
{ electionTimeoutMillis: 10000, … }
{ isWritablePrimary: true, setName: 'rs0', hosts: [ … 3 … ], me: 'mongo-0.mongo…:27017' }
```

**⭐ Create the app user and the `role: primary` label:**

```bash
kubectl exec -n db mongo-0 -- mongosh --quiet -u admin -p'Adm1n-Pr0d-K8s!-Q7' --authenticationDatabase admin --eval '
  db.getSiblingDB("shop").createUser({
    user: "shop",
    pwd:  "Sh0p-Pr0d-K8s!-R3",
    roles: [{role: "readWrite", db: "shop"}]
  });
  db.getSiblingDB("admin").createUser({
    user: "backup",
    pwd:  "Bkp-Pr0d-K8s!-T8",
    roles: [{role: "backup", db: "admin"}, {role: "clusterMonitor", db: "admin"}]
  });'

# label the primary so mongo-primary Service works
kubectl label pod -n db mongo-0 role=primary
kubectl get endpointslices -n db -l kubernetes.io/service-name=mongo-primary
```

**Test failover — automatic, no manual steps:**

```bash
kubectl exec -n db mongo-0 -- mongosh --quiet -u admin -p'Adm1n-Pr0d-K8s!-Q7' --authenticationDatabase admin shop --eval '
  db.products.insertMany([{name:"Widget",price:9.99},{name:"Gadget",price:19.99}]);
  db.products.countDocuments();'
# 2

# kill the primary
kubectl delete pod -n db mongo-0
kubectl get pods -n db -l app=mongo -w
```

```
mongo-0   1/1   Terminating   …
mongo-1   1/1   Running       …      ← elected PRIMARY within ~10s
mongo-2   1/1   Running       …
mongo-0   0/1   Pending       …
mongo-0   0/1   Init:0/2      …
mongo-0   1/1   Running       …      ← rejoins as SECONDARY
```

```bash
kubectl exec -n db mongo-1 -- mongosh --quiet -u admin -p'Adm1n-Pr0d-K8s!-Q7' --authenticationDatabase admin --eval '
  rs.status().members.map(m => `${m.name}  ${m.stateStr}`);'
# mongo-1  PRIMARY          ← ✅ automatic election, no human involved
# mongo-2  SECONDARY
# mongo-0  SECONDARY

kubectl exec -n db mongo-1 -- mongosh --quiet -u admin -p'…' --authenticationDatabase admin shop --eval '
  db.products.countDocuments();'
# 2                          ← ✅ no data lost

# re-point the primary label (an operator does this for you)
kubectl label pod -n db mongo-0 role- --overwrite
kubectl label pod -n db mongo-1 role=primary --overwrite
```

**This is the key difference from MySQL:** MongoDB does leader election *itself*. Kubernetes only has to keep the Pods alive and the DNS stable. That's why MongoDB on Kubernetes is genuinely comfortable.

**⭐ Memory: `wiredTigerCacheSizeGB` must be set explicitly.**

MongoDB's default is `max(50% of (RAM - 1GB), 256MB)` — computed from **the node's RAM**, not the container limit. On a 64 GB node with a 2 Gi limit, mongod would try to cache 31 GB and get OOMKilled instantly.

```
container limit            2048 Mi
wiredTigerCacheSizeGB      0.5    (512 Mi)   ← explicit
+ connections (~1 MiB each × 100)  100 Mi
+ sorting/aggregation memory         200 Mi
+ oplog, journaling, metadata        300 Mi
+ OS/page cache                      500 Mi
──────────────────────────────────────────
                            ~1600 Mi   ✅ under 2048
```

Rule of thumb: **`wiredTigerCacheSizeGB` ≈ 25–40% of the container limit.**

```bash
kubectl exec -n db mongo-0 -- mongosh --quiet -u admin -p'…' --authenticationDatabase admin --eval '
  const s = db.serverStatus();
  ({ cacheGB: (s.wiredTiger.cache["maximum bytes configured"]/1024/1024/1024).toFixed(2),
     bytesInCache: (s.wiredTiger.cache["bytes currently in the cache"]/1024/1024).toFixed(0)+" MB",
     dirtyBytes: (s.wiredTiger.cache["tracked dirty bytes in the cache"]/1024/1024).toFixed(0)+" MB",
     connections: s.connections.current,
     available: s.connections.available,
     evictions: s.wiredTiger.cache["unmodified pages evicted"] })'
```

**The connection string for your app** — this is the part that trips people up:

```bash
# ❌ WRONG: single host. If mongo-0 isn't primary, every write fails.
mongodb://shop:pass@mongo-0.mongo.db.svc.cluster.local:27017/shop

# ✅ RIGHT: all three members, replicaSet, readPreference
mongodb://shop:Sh0p-Pr0d-K8s!-R3@mongo-0.mongo.db.svc.cluster.local:27017,mongo-1.mongo.db.svc.cluster.local:27017,mongo-2.mongo.db.svc.cluster.local:27017/shop?replicaSet=rs0&readPreference=secondaryPreferred&w=majority&retryWrites=true&retryReads=true&maxPoolSize=50&serverSelectionTimeoutMS=5000
```

| Parameter | Why |
|---|---|
| All 3 hosts | The driver discovers the topology; it needs seeds |
| `replicaSet=rs0` | Enables topology monitoring and automatic failover |
| `readPreference=secondaryPreferred` | Reads spread to secondaries; writes always go to the primary |
| `w=majority` | A write is acknowledged only after 2 of 3 members have it → survives a node loss |
| `retryWrites=true` | The driver retries idempotent writes on a failover |
| `serverSelectionTimeoutMS=5000` | Fail fast during an election instead of hanging 30 s |

```yaml
# in your app's ConfigMap
MONGODB_URI: "mongodb://shop:pass@mongo-0.mongo.db.svc.cluster.local:27017,mongo-1.mongo.db.svc.cluster.local:27017,mongo-2.mongo.db.svc.cluster.local:27017/shop?replicaSet=rs0&readPreference=secondaryPreferred&w=majority&retryWrites=true"
```

**Backups:**

```bash
# logical (mongodump) — small databases
kubectl exec -n db mongo-1 -- mongodump \
  --uri="mongodb://backup:Bkp-Pr0d-K8s!-T8@mongo-1.mongo.db.svc.cluster.local:27017/?replicaSet=rs0&readPreference=secondary" \
  --archive --gzip > shop-$(date +%Y%m%d).archive.gz

# restore
mongorestore --uri="mongodb://admin:…@mongo-0…:27017/?replicaSet=rs0" \
  --archive=shop-20260909.archive.gz --gzip

# physical (Percona Hot Backup / Enterprise) — large databases, near-instant restore
# or: Velero + volume snapshots — the Kubernetes-native way
velero backup create mongo-$(date +%F) --include-namespaces db --snapshot-volumes
```

> 🔑 **Dump from a SECONDARY**, never the primary. `mongodump` holds a read lock that hurts the primary's latency.

**Or use the official operator:**

```bash
kubectl apply -f https://raw.githubusercontent.com/mongodb/mongodb-kubernetes-operator/master/config/crd/bases/mongodbcommunity.mongodb.com_mongodbcommunity.yaml
helm install mongodb-community-operator mongodb/community-operator -n mongodb --create-namespace
```

```yaml
apiVersion: mongodbcommunity.mongodb.com/v1
kind: MongoDBCommunity
metadata: {name: shop-mongo, namespace: db}
spec:
  members: 3
  type: ReplicaSet
  version: "7.0.14"
  security:
    authentication: {modes: [SCRAM]}
  users:
    - name: shop
      db: shop
      passwordSecretRef: {name: shop-mongo-password}
      roles: [{name: readWrite, db: shop}]
      scramCredentialsSecretNames: {scram: shop-mongo-scram}
  statefulSet:
    spec:
      template:
        spec:
          containers:
            - name: mongod
              resources: {requests: {cpu: 500m, memory: 1Gi}, limits: {cpu: "2", memory: 2Gi}}
      volumeClaimTemplates:
        - metadata: {name: data-volume}
          spec: {accessModes: [ReadWriteOnce], resources: {requests: {storage: 20Gi}}}
```

The operator handles: replica-set init, user creation, SCRAM credentials as Secrets, rolling upgrades, the `role: primary` label, and connection-string Secrets. **~40 lines instead of ~350.**

## MongoDB tasks

<details>
<summary>Task 13.2.1 — The Pod restarts and the replica set can't find itself. Fix it permanently.</summary>

**The symptom:**

```bash
kubectl delete pod -n db mongo-1
kubectl logs -n db mongo-1 --tail=50
```

```
{"t":{"$date":"2026-09-09T15:02:11.842Z"},"s":"E","c":"REPL","msg":"Member mongo-1.mongo.db.svc.cluster.local:27017 is now in state UNKNOWN","attr":{"error":"HostUnreachable"}}
{"t":{"$date":"…"},"s":"W","c":"NETWORK","msg":"Failed to connect to mongo-1.mongo.db.svc.cluster.local:27017"}
```

**Four causes, in order of likelihood:**

### 1. The Service isn't headless

```bash
kubectl get svc mongo -n db -o jsonpath='{.spec.clusterIP}'; echo
# None        ← ✅ headless, returns Pod IPs
# 10.96.42.7  ← ⛔ a ClusterIP. mongo-0.mongo.db.svc doesn't resolve AT ALL
```

A ClusterIP Service gives you `mongo.db.svc` → one virtual IP. It gives you **nothing** for `mongo-0.mongo.db.svc`. Per-Pod DNS only exists on a headless Service.

```bash
kubectl run dns -n db --rm -it --image=nicolaka/netshoot --restart=Never -- bash
  dig +short mongo.db.svc.cluster.local           # → Pod IPs (headless) or one ClusterIP
  dig +short mongo-0.mongo.db.svc.cluster.local   # → the Pod IP ✅
  dig +short mongo-1.mongo.db.svc.cluster.local
  nslookup mongo-2.mongo.db.svc.cluster.local
```

If per-Pod names don't resolve: `clusterIP: None` **and** `serviceName: mongo` on the StatefulSet must match the headless Service's name exactly.

### 2. `publishNotReadyAddresses: false`

```bash
kubectl get svc mongo -n db -o jsonpath='{.spec.publishNotReadyAddresses}'; echo
# true    ← ✅
# <empty> ← ⛔ false by default
```

Without it, a NotReady Pod has **no DNS record**. During a rolling restart, `mongo-1` can't resolve `mongo-2` because `mongo-2` is also restarting → the replica set loses quorum → nothing becomes Ready → deadlock.

### 3. The member was registered with the wrong hostname

The most common *real* cause. Someone ran `rs.initiate()` with a bare hostname:

```bash
kubectl exec -n db mongo-0 -- mongosh --quiet -u admin -p'…' --authenticationDatabase admin --eval '
  rs.conf().members.map(m => m._id + " → " + m.host)'
```

```
0 → mongo-0:27017                 ← ⛔ a bare name. Resolves ONLY inside the db namespace.
```

An app in the `shop` namespace resolving `mongo-0` gets nothing. It must be the FQDN:

```
0 → mongo-0.mongo.db.svc.cluster.local:27017   ← ✅
```

**Fix it live, without a full re-init:**

```bash
kubectl exec -n db mongo-0 -- mongosh -u admin -p'…' --authenticationDatabase admin --eval '
  cfg = rs.conf();
  cfg.members.forEach(m => {
    if (!m.host.includes(".")) {
      m.host = m.host.replace(":27017", ".mongo.db.svc.cluster.local:27017");
    }
  });
  cfg.settings = cfg.settings || {};
  rs.reconfig(cfg, {force: false});
  rs.conf().members.map(m => m.host);'
```

```
[ 'mongo-0.mongo.db.svc.cluster.local:27017',
  'mongo-1.mongo.db.svc.cluster.local:27017',
  'mongo-2.mongo.db.svc.cluster.local:27017' ]
```

⚠️ **Never change `_id`** — it's the member's permanent identity. Change only `host`. And if you must rebuild from scratch:

```bash
# LAST RESORT: wipe and re-initiate (destroys cluster config, not data)
kubectl exec -n db mongo-0 -- mongosh -u admin -p'…' --authenticationDatabase admin --eval '
  cfg = {_id: "rs0", members: [
    {_id:0, host:"mongo-0.mongo.db.svc.cluster.local:27017", priority:2},
    {_id:1, host:"mongo-1.mongo.db.svc.cluster.local:27017", priority:1},
    {_id:2, host:"mongo-2.mongo.db.svc.cluster.local:27017", priority:1}]};
  rs.reconfig(cfg, {force: true});'
```

### 4. The keyfile changed

```bash
kubectl logs -n db mongo-1 | grep -i 'keyfile\|unauthorized\|auth'
# "Auth failed" / "No key found" → the members can't authenticate to each other
```

Every member must have the **identical** keyfile. If you regenerated the Secret, roll all Pods:

```bash
kubectl get secret mongo-keyfile -n db -o jsonpath='{.data.mongo-key}' | base64 -d | sha256sum
# compare against each pod
for i in 0 1 2; do
  echo -n "mongo-$i: "
  kubectl exec -n db mongo-$i -- sha256sum /etc/mongo-keyfile/mongo-key
done
```

Also: `defaultMode: 0400`. mongod refuses a world-readable keyfile with no useful error at first glance — check `kubectl describe pod` for a `CreateContainerConfigError`.

### The permanent fix — make it declarative and idempotent

```yaml
# the init container from §13.2 Case 2 already does this. The key lines:
- |
  SVC="mongo.db.svc.cluster.local"          # ← namespace-qualified, not bare
  rs.initiate({ _id: 'rs0', members: [
    {_id: 0, host: "mongo-0.$SVC:27017", priority: 2}, …]})
```

Plus:

```yaml
spec:
  serviceName: mongo                       # matches the headless Service
  podManagementPolicy: Parallel            # no artificial ordering dependency
---
# the headless Service
spec:
  clusterIP: None
  publishNotReadyAddresses: true           # ⭐ the deadlock-breaker
```

### Verify the whole thing

```bash
# 1. DNS works for every member, from every namespace
for ns in db shop default; do
  for i in 0 1 2; do
    printf '%-8s mongo-%d → ' "$ns" "$i"
    kubectl run d-$RANDOM -n $ns --rm -i --restart=Never --image=nicolaka/netshoot \
      -- dig +short mongo-$i.mongo.db.svc.cluster.local | tr '\n' ' '
    echo
  done
done

# 2. every member agrees on the config
for i in 0 1 2; do
  echo -n "mongo-$i sees: "
  kubectl exec -n db mongo-$i -- mongosh --quiet -u admin -p'…' --authenticationDatabase admin \
    --eval 'rs.status().members.map(m=>m.name+"="+m.stateStr).join(" ")'
done
# all three must print the SAME three hostnames

# 3. restart chaos — nothing should break
for round in 1 2 3; do
  kubectl delete pod -n db mongo-$((RANDOM % 3))
  kubectl rollout status sts/mongo -n db --timeout=300s
  kubectl exec -n db mongo-0 -- mongosh --quiet -u admin -p'…' --authenticationDatabase admin \
    --eval 'print(rs.status().members.filter(m=>m.health===1).length + "/3 healthy")'
done
```

```
3/3 healthy
3/3 healthy
3/3 healthy      ← ✅ survives arbitrary restarts
```

</details>

<details>
<summary>Task 13.2.2 — Reads are hitting the primary. Make `readPreference=secondaryPreferred` actually work, and measure the difference.</summary>

**First, prove the problem.**

```bash
kubectl exec -n db mongo-0 -- mongosh --quiet -u admin -p'…' --authenticationDatabase admin --eval '
  db.getSiblingDB("shop").serverStatus().opcounters'
# { insert: 48210, query: 1284021, update: 12044, delete: 210, … }

for i in 0 1 2; do
  echo -n "mongo-$i queries: "
  kubectl exec -n db mongo-$i -- mongosh --quiet -u admin -p'…' --authenticationDatabase admin \
    --eval 'db.getSiblingDB("shop").serverStatus().opcounters.query'
done
```

```
mongo-0 queries: 1284021       ← PRIMARY taking ALL the reads
mongo-1 queries: 3
mongo-2 queries: 2
```

The secondaries are idle. You're paying for 3 nodes and using 1.

### Fix 1 — the connection string

```bash
# ❌ what most people write
MONGODB_URI=mongodb://shop:pass@mongo-0.mongo.db.svc.cluster.local:27017/shop

# ⚠️ better but still wrong: pointing at the mongo-primary Service
MONGODB_URI=mongodb://shop:pass@mongo-primary.db.svc.cluster.local:27017/shop
#    The driver sees ONE host, thinks it's standalone, and ignores readPreference entirely.

# ✅ correct: all members + replicaSet + readPreference
MONGODB_URI=mongodb://shop:pass@mongo-0.mongo.db.svc.cluster.local:27017,mongo-1.mongo.db.svc.cluster.local:27017,mongo-2.mongo.db.svc.cluster.local:27017/shop?replicaSet=rs0&readPreference=secondaryPreferred&maxStalenessSeconds=10
```

> 🔑 **`readPreference` is silently ignored if `replicaSet` is absent.** No warning, no error — the driver just talks to the one host you gave it. This is the #1 cause of "my secondaries do nothing."

Verify the driver agrees:

```bash
kubectl exec -n shop deploy/shop-api -- sh -c 'cat /proc/1/environ | tr "\0" "\n" | grep MONGO'
# and in your app, log the topology once at startup:
#   MongoClient.description → ServerDescription list with types
```

### Fix 2 — per-operation read preference (the right way for mixed workloads)

Not all reads should go to secondaries. **A read-your-own-write must go to the primary.**

```javascript
// Node.js driver
const coll = db.collection('products');

// stale-tolerant: catalog listing → a secondary is fine
await coll.find({}).setReadPreference('secondaryPreferred').toArray();

// must be fresh: "show me the order I just placed"
await coll.findOne({_id}, {readPreference: 'primary'});

// bounded staleness: never read from a secondary more than 10s behind
await coll.find({}).setReadPreference(
  new ReadPreference('secondaryPreferred', {maxStalenessSeconds: 10})
).toArray();
```

```python
# PyMongo
from pymongo import ReadPreference
products = db.get_collection("products", read_preference=ReadPreference.SECONDARY_PREFERRED)
fresh    = db.get_collection("products", read_preference=ReadPreference.PRIMARY)
```

```java
// MongoDB Java driver
MongoCollection<Document> stale = db.getCollection("products")
    .withReadPreference(ReadPreference.secondaryPreferred());
MongoCollection<Document> fresh = db.getCollection("products")
    .withReadPreference(ReadPreference.primary());
```

```go
// mongo-go-driver
opts := options.Collection().SetReadPreference(readpref.SecondaryPreferred())
stale := db.Collection("products", opts)
```

**The decision table:**

| Read | Preference | Why |
|---|---|---|
| Product catalog, search, listings | `secondaryPreferred` | Staleness of 100 ms is invisible |
| Analytics, reports, exports | `secondary` | Heavy; keep it off the primary entirely |
| "The thing I just wrote" | `primary` | Read-your-own-write |
| Session/cart after an update | `primary` | Consistency matters |
| Login / auth checks | `primaryPreferred` | Freshness, but survive a primary loss |
| Anything with a causal session | automatic | The driver pins to the primary |

### Fix 3 — tag sets for locality

```javascript
// prefer secondaries in the same zone as the app
rs.reconfig({
  _id: "rs0",
  members: [
    {_id: 0, host: "mongo-0.mongo.db.svc…:27017", tags: {zone: "us-east-1a", use: "write"}},
    {_id: 1, host: "mongo-1.mongo.db.svc…:27017", tags: {zone: "us-east-1a", use: "read"}},
    {_id: 2, host: "mongo-2.mongo.db.svc…:27017", tags: {zone: "us-east-1b", use: "read"}}
  ],
  settings: {getLastErrorModes: {majorityZone: {w: 2}}}
});
```

```
?readPreference=secondaryPreferred&readPreferenceTags=zone:us-east-1a,use:read&readPreferenceTags=use:read
```

The driver tries the tag sets **in order**, falling back to the next.

### Measure the improvement

```bash
# before
for i in 0 1 2; do
  printf 'mongo-%d: ' $i
  kubectl exec -n db mongo-$i -- mongosh --quiet -u admin -p'…' --authenticationDatabase admin \
    --eval 'printjson(db.getSiblingDB("shop").serverStatus().opcounters)' | tr '\n' ' '
  echo
done
# reset the counters by restarting the mongod processes is messy — snapshot deltas instead:

sample() {
  for i in 0 1 2; do
    echo -n "mongo-$i "
    kubectl exec -n db mongo-$i -- mongosh --quiet -u admin -p'…' --authenticationDatabase admin \
      --eval 'db.getSiblingDB("shop").serverStatus().opcounters.query'
  done
}
A=($(sample)); sleep 60; B=($(sample))
for i in 0 1 2; do echo "mongo-$i delta: $(( ${B[$i]} - ${A[$i]} ))"; done
```

```
BEFORE   mongo-0 delta: 12041     mongo-1 delta: 0      mongo-2 delta: 0
AFTER    mongo-0 delta:   842     mongo-1 delta: 5610   mongo-2 delta: 5588
```

Read load moved from 100% on the primary to **7% primary / 46% / 46% secondaries.**

**And the latency:**

```bash
hey -z 60s -c 50 -m GET -H "Host: shop.example.com" "http://$LB_IP/api/products" > mongo-read.txt
grep -E 'Requests/sec|Latency distribution' -A5 mongo-read.txt
```

```
BEFORE  Requests/sec: 812    p99: 0.0840
AFTER   Requests/sec: 1940   p99: 0.0210    ← 2.4× throughput, 4× better p99
```

### Watch out for replication lag

```javascript
// how far behind is each secondary?
rs.printSecondaryReplicationInfo();
```

```
source: mongo-0.mongo.db.svc.cluster.local:27017
syncedTo: Thu Sep 09 2026 15:42:11 GMT+0000
0 secs (0 hrs) behind the primary
```

```promql
# alert if a secondary falls behind
mongodb_mongod_replset_member_replication_lag > 10
```

```javascript
// and if you need a hard bound, use maxStalenessSeconds
// (the driver will skip a secondary that's too far behind and use the primary)
?readPreference=secondaryPreferred&maxStalenessSeconds=10
```

⚠️ `maxStalenessSeconds` has a minimum of 90 s in MongoDB's implementation for *some* drivers — check your driver's docs. Below that, it's ignored or errors.

### The Kubernetes-side gotcha

Your `mongo-primary` Service selects `role=primary`. **Nobody updates that label on failover** unless you run an operator or a sidecar. So:

```bash
# after a failover, mongo-primary still points at the OLD primary
kubectl get endpointslices -n db -l kubernetes.io/service-name=mongo-primary -o jsonpath='{.items[*].endpoints[*].addresses}'; echo
```

**Don't use a `mongo-primary` Service at all.** Give the driver all three hosts and let it do topology discovery — that's what the driver is for. Delete the Service and the label machinery. The operator approach is better still: it maintains a `*-svc` that always points at the primary.

</details>

<details>
<summary>Task 13.2.3 — A MongoDB Pod is OOMKilled. Diagnose and fix it.</summary>

```bash
kubectl describe pod -n db mongo-1 | grep -A10 "Last State"
# Reason: OOMKilled  Exit Code: 137
kubectl get pod -n db mongo-1 -o jsonpath='{.status.containerStatuses[0].restartCount}'; echo
```

### Cause 1 — WiredTiger cache sized from the NODE, not the container (90% of cases)

```bash
kubectl exec -n db mongo-0 -- mongosh --quiet -u admin -p'…' --authenticationDatabase admin --eval '
  const wt = db.serverStatus().wiredTiger.cache;
  ({ configuredMaxGB: (wt["maximum bytes configured"]/1024**3).toFixed(2),
     inCacheMB:       (wt["bytes currently in the cache"]/1024**2).toFixed(0),
     dirtyMB:         (wt["tracked dirty bytes in the cache"]/1024**2).toFixed(0),
     evictedUnmod:    wt["unmodified pages evicted"],
     appThreadsBlocked: wt["application threads page write from cache to disk"] })'
```

```
configuredMaxGB: '15.50'      ← ⛔⛔ 15.5 GB cache in a container limited to 2 GB
inCacheMB: '1980'
```

MongoDB computed `max(50% × (nodeRAM - 1GB), 256MB)` = `0.5 × (32 - 1)` = **15.5 GB**. It filled toward that target and the kernel killed it at 2 GB.

**Fix — always set it explicitly:**

```yaml
args:
  - --wiredTigerCacheSizeGB=0.5      # 25% of a 2Gi limit
```

Or from the ConfigMap so it can be tuned without editing the StatefulSet:

```yaml
args: ["--config=/etc/mongod.conf"]
---
apiVersion: v1
kind: ConfigMap
metadata: {name: mongod-conf, namespace: db}
data:
  mongod.conf: |
    storage:
      dbPath: /data/db
      wiredTiger:
        engineConfig:
          cacheSizeGB: 0.5              # ⭐ explicit
          journalCompressor: snappy
        collectionConfig:
          blockCompressor: snappy
      journal:
        enabled: true
        commitIntervalMs: 100
    systemLog:
      destination: file
      path: /dev/stdout                   # → collected by Kubernetes
      logAppend: true
      verbosity: 0
      component:
        replication: {verbosity: 1}
    replication:
      replSetName: rs0
      oplogSizeMB: 2048
      enableMajorityReadConcern: true
    net:
      port: 27017
      bindIp: 0.0.0.0
      maxIncomingConnections: 500
    security:
      keyFile: /etc/mongo-keyfile/mongo-key
      authorization: enabled
    setParameter:
      maxTransactionLockRequestTimeoutMillis: 5000
    operationProfiling:
      slowOpThresholdMs: 100
      mode: slowOp
```

**The sizing table:**

| Container limit | `cacheSizeGB` | Rationale |
|---|---|---|
| 1 Gi | 0.25 | 25% — small workloads |
| 2 Gi | 0.5 | 25% |
| 4 Gi | 1.25 | ~31% |
| 8 Gi | 3 | ~38% |
| 16 Gi | 6 | ~38% |
| 64 Gi | 24 | ~38% |

Everything else goes to: connections (~1 MiB each), aggregation/sort memory, the oplog in memory, journal buffers, and the page cache.

### Cause 2 — unbounded aggregation / sort

```bash
kubectl exec -n db mongo-0 -- mongosh --quiet -u admin -p'…' --authenticationDatabase admin --eval '
  db.getSiblingDB("shop").serverStatus().metrics.queryExecutor'
# { scanned: { … }, collectionScans: 48210 }       ← ⛔ COLLSCANs

kubectl exec -n db mongo-0 -- mongosh --quiet -u admin -p'…' --authenticationDatabase admin --eval '
  db.getSiblingDB("shop").setProfilingLevel(2, {slowms: 50});
  db.getSiblingDB("shop").system.profile.find({millis: {$gt: 200}})
    .sort({ts: -1}).limit(5)
    .forEach(d => printjson({op: d.op, ns: d.ns, millis: d.millis, plan: d.planSummary, keys: d.keysExamined, docs: d.docsExamined}))'
```

```
{ op: "query", ns: "shop.orders", millis: 4821,
  plan: "COLLSCAN",                    ← ⛔ full collection scan
  keys: 0, docs: 2841033 }             ← ⛔ 2.8M documents into memory
```

A `$sort` or `$group` on 2.8 M documents exceeds the 100 MB per-stage limit and spills to disk — or, with `allowDiskUse`, consumes enormous memory.

**Fixes:**

```javascript
// 1. the index that removes the COLLSCAN
db.orders.createIndex({userId: 1, createdAt: -1});

// 2. cap aggregation memory per stage (default 100MB) — it's a SAFETY NET, not a fix
db.orders.aggregate([...], {allowDiskUse: true});   // spills to disk instead of OOMing

// 3. paginate properly
db.orders.find({userId}).sort({createdAt: -1}).limit(50).skip(0);   // ⛔ skip is O(n)
// ✅ range pagination
db.orders.find({userId, createdAt: {$lt: lastSeen}}).sort({createdAt: -1}).limit(50);

// 4. never .toArray() an unbounded cursor in application code
```

```yaml
# 5. limit the sort memory server-wide
setParameter:
  internalDocumentSourceGroupMaxMemoryBytes: 104857600   # 100 MB
```

### Cause 3 — too many connections

```bash
kubectl exec -n db mongo-0 -- mongosh --quiet -u admin -p'…' --authenticationDatabase admin --eval '
  const c = db.serverStatus().connections;
  ({current: c.current, available: c.available, totalCreated: c.totalCreated,
    threaded: c.threaded})'
# { current: 842, available: 158, totalCreated: 48210, threaded: 842 }
```

At ~1 MiB per connection, 842 connections = ~842 MiB — nearly half your 2 Gi limit.

```yaml
# cap it server-side
net:
  maxIncomingConnections: 300

# and client-side (the real fix) — connection POOLING
# MONGODB_URI=…&maxPoolSize=20&minPoolSize=5&maxIdleTimeMS=30000
```

```
app pods × maxPoolSize  must be <  maxIncomingConnections × 0.8
10 pods × 20            =  200     <  300 × 0.8 = 240   ✅
```

Find the offenders:

```javascript
db.currentOp(true).length
db.currentOp({app: true}).map(o => o.client).reduce((acc, c) => {
  const ip = c.split(":")[0]; acc[ip] = (acc[ip]||0)+1; return acc; }, {})
// { '10.244.2.19': 240, '10.244.3.8': 22, … }   ← one Pod is hogging
```

### Cause 4 — the oplog is too big for the container

```bash
kubectl exec -n db mongo-0 -- mongosh --quiet -u admin -p'…' --authenticationDatabase admin --eval '
  const l = db.getSiblingDB("local").oplog.rs.stats();
  ({maxSizeMB: l.maxSize/1024**2, usedMB: l.storageSize/1024**2, countMB: l.count})'
# { maxSizeMB: 10240, usedMB: 8410 }      ← ⛔ a 10 GB oplog in a 2 Gi container
```

MongoDB defaults `oplogSizeMB` to **5% of the free space on the volume** — a 200 GiB PVC gets a 10 GiB oplog, and it lives in the WiredTiger cache.

```yaml
replication:
  oplogSizeMB: 2048          # ⭐ explicit. Bigger = a longer window for a secondary to catch up.
```

Rule of thumb: the oplog should cover **24 hours of writes** so a secondary that's down for a day can resync without a full copy.

```javascript
rs.printReplicationInfo();
// configured oplog size:   2048MB
// log length start to end: 26hrs 12mins (94320secs)      ✅
// oplog first event time:  …
```

### Cause 5 — the container limit is just too small

```bash
kubectl top pod -n db --containers | grep mongo
kubectl exec -n db mongo-0 -- cat /sys/fs/cgroup/memory.current
kubectl exec -n db mongo-0 -- cat /sys/fs/cgroup/memory.stat | grep -E '^(anon|file|slab) '
```

```
anon 1842108416       ← 1.7 GiB of actual application memory
file  128410624       ← page cache (reclaimable, doesn't count against you as harshly)
```

**The full budget for a 2 Gi container:**

```
wiredTigerCacheSizeGB 0.5          =  512 Mi
connections 300 × 1 MiB            =  300 Mi
oplog (resident portion)           =  200 Mi
aggregation/sort working sets      =  200 Mi
journal buffers, metadata, indexes =  200 Mi
mongod overhead + glibc arenas     =  150 Mi
headroom                           =  486 Mi
─────────────────────────────────────────────
container limit                    = 2048 Mi
```

```yaml
resources:
  requests: {memory: 2Gi}
  limits:   {memory: 2Gi}      # ⭐ Guaranteed — a Burstable mongod gets evicted first
```

### The verification run

```bash
# apply the fixes
kubectl edit cm mongod-conf -n db      # set cacheSizeGB, oplogSizeMB, maxIncomingConnections
kubectl rollout restart sts/mongo -n db
kubectl rollout status sts/mongo -n db --timeout=600s

# confirm
kubectl exec -n db mongo-0 -- mongosh --quiet -u admin -p'…' --authenticationDatabase admin --eval '
  const wt = db.serverStatus().wiredTiger.cache;
  print("cache configured:", (wt["maximum bytes configured"]/1024**3).toFixed(2), "GB");
  print("oplog window:", rs.printReplicationInfo ? "see below" : "?");'
kubectl exec -n db mongo-0 -- mongosh --quiet -u admin -p'…' --authenticationDatabase admin --eval 'rs.printReplicationInfo()'
kubectl get pod -n db mongo-0 -o jsonpath='{.status.containerStatuses[0].restartCount}'; echo

# soak it and watch
for i in $(seq 1 20); do
  printf '%s  ' "$(date +%T)"
  kubectl top pod -n db mongo-0 --containers --no-headers | awk '{printf "mongo %s  ", $4}'
  kubectl exec -n db mongo-0 -- cat /sys/fs/cgroup/memory.current | awk '{printf "cgroup %.0f MB\n", $1/1048576}'
  sleep 30
done
```

```
15:52:01  mongo 1418Mi  cgroup 1489 MB
15:53:01  mongo 1421Mi  cgroup 1492 MB     ← ✅ flat, well under 2048
```

### The alert that catches it next time

```yaml
- alert: MongoDBMemoryNearLimit
  expr: |
    container_memory_working_set_bytes{pod=~"mongo-.*", container="mongo"}
      / on(pod) kube_pod_container_resource_limits{resource="memory", pod=~"mongo-.*"} > 0.85
  for: 10m
  labels: {severity: warning}
  annotations:
    summary: "{{ $labels.pod }} at {{ $value | humanizePercentage }} of its memory limit"
    description: "Check wiredTiger cacheSizeGB, connection count, and oplogSizeMB."

- alert: MongoDBWiredTigerCacheFull
  expr: mongodb_ss_wt_cache_bytes_currently_in_the_cache
        / mongodb_ss_wt_cache_maximum_bytes_configured > 0.95
  for: 5m
  labels: {severity: critical}
  annotations: {summary: "{{ $labels.pod }} WiredTiger cache is above 95% — evictions and latency are imminent"}
```

</details>

---
---

# 13.3 — Redis 7

## 🔵 Case 1 — one Pod, in-memory, `emptyDir` (8 minutes)

```bash
mkdir -p ~/k8s-learn/p13/redis && cd ~/k8s-learn/p13
```

`redis/simple.yaml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata: {name: redis-config}
data:
  redis.conf: |
    # ── network ──
    bind 0.0.0.0
    protected-mode no            # ⭐ ok ONLY because a NetworkPolicy guards it.
                                 #   Never do this on an exposed Redis.
    port 6379
    tcp-backlog 511
    timeout 300                  # close idle client connections after 5 min
    tcp-keepalive 60

    # ── memory — THE most important setting ──
    maxmemory 400mb              # ⭐ explicit. Default = unlimited = OOMKill.
    maxmemory-policy allkeys-lru # evict least-recently-used when full
    maxmemory-samples 5

    # ── persistence — OFF for a pure cache ──
    save ""                      # ⭐ no RDB snapshots
    appendonly no

    # ── performance ──
    maxclients 1000
    io-threads 2                 # Redis 7 threaded I/O — set to min(cores, 4)
    io-threads-do-reads yes
    lazyfree-lazy-eviction yes
    lazyfree-lazy-expire yes
    lazyfree-lazy-server-del yes
    activedefrag yes

    # ── logging to stdout ──
    loglevel notice
    logfile ""
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: redis, labels: {app: redis}}
spec:
  replicas: 1
  selector: {matchLabels: {app: redis}}
  template:
    metadata: {labels: {app: redis}}
    spec:
      terminationGracePeriodSeconds: 30
      containers:
        - name: redis
          image: redis:7-alpine
          command: ["redis-server", "/etc/redis/redis.conf"]
          ports: [{name: redis, containerPort: 6379}]
          readinessProbe:
            exec: {command: ["redis-cli", "ping"]}
            initialDelaySeconds: 3
            periodSeconds: 5
          livenessProbe:
            exec: {command: ["redis-cli", "ping"]}
            initialDelaySeconds: 15
            periodSeconds: 20
          resources:
            requests: {cpu: 100m, memory: 512Mi}
            limits:   {cpu: "1",   memory: 512Mi}   # ⭐ == maxmemory + headroom
          volumeMounts:
            - {name: config, mountPath: /etc/redis, readOnly: true}
            - {name: data,   mountPath: /data}
      volumes:
        - {name: config, configMap: {name: redis-config}}
        # ⭐ emptyDir, NOT a PVC. This is a CACHE — losing it on restart is fine,
        #   and a PVC would pin the Pod to a zone for no benefit.
        - {name: data, emptyDir: {sizeLimit: 256Mi}}
---
apiVersion: v1
kind: Service
metadata: {name: redis}
spec:
  selector: {app: redis}
  ports: [{name: redis, port: 6379}]
```

```bash
kubectl apply -f redis/simple.yaml
kubectl rollout status deploy/redis --timeout=60s
kubectl exec -it deploy/redis -- redis-cli INFO server | head -12
kubectl exec -it deploy/redis -- redis-cli SET hello world
kubectl exec -it deploy/redis -- redis-cli GET hello
kubectl exec -it deploy/redis -- redis-cli INFO memory | grep -E 'used_memory_human|maxmemory_human|maxmemory_policy'
```

```
used_memory_human:1.02M
maxmemory_human:400.00M
maxmemory_policy:allkeys-lru
```

**⭐ `maxmemory` is the difference between a cache and a Pod-killer.** Without it, Redis grows until the container limit and gets OOMKilled — losing everything *and* taking 20 seconds to restart. With it, Redis evicts and stays up.

## 🟢 Case 2 — primary/replica with password auth, persistence, and two Services (40 minutes)

```
   writes ──► redis-primary (Service) ──► redis-0   (PRIMARY)
                                              │ replication
   reads  ──► redis-replicas (Service) ──► redis-1  (REPLICA)
                                        ──► redis-2  (REPLICA)
                redis (headless) ──► redis-0.redis.db.svc, redis-1…, redis-2…
```

`redis/prod/redis.yaml`:

```yaml
apiVersion: v1
kind: Secret
metadata: {name: redis-creds, namespace: db}
stringData:
  password: "R3d1s-Pr0d-K8s!-M4"
---
apiVersion: v1
kind: ConfigMap
metadata: {name: redis-config, namespace: db}
data:
  redis-common.conf: |
    # ── security ──
    requirepass __REDIS_PASSWORD__
    masterauth  __REDIS_PASSWORD__          # ⭐ replicas authenticate to the primary
    rename-command FLUSHALL ""              # ⭐ disable destructive commands entirely
    rename-command FLUSHDB  ""
    rename-command CONFIG   "CONFIG_b8f2e1a9"   # obscure, not disable (we need it for INFO)
    rename-command SHUTDOWN "SHUTDOWN_c4d7a2"
    rename-command DEBUG    ""
    rename-command KEYS     ""              # ⭐ KEYS on a big keyspace blocks Redis for seconds
    rename-command SAVE     ""
    rename-command BGSAVE   "BGSAVE_e91c"

    # ── network ──
    bind 0.0.0.0
    protected-mode yes
    port 6379
    tcp-backlog 2048
    timeout 0
    tcp-keepalive 60

    # ── memory ──
    maxmemory 1gb
    maxmemory-policy allkeys-lru
    maxmemory-samples 10
    activedefrag yes
    active-defrag-ignore-bytes 100mb
    active-defrag-threshold-lower 10
    active-defrag-threshold-upper 100
    active-defrag-cycle-min 5
    active-defrag-cycle-max 25

    # ── persistence: AOF every second (durability) + RDB snapshots (fast restart) ──
    appendonly yes
    appendfilename "appendonly.aof"
    appendfsync everysec                    # ⭐ at most 1s of writes lost on a crash
    no-appendfsync-on-rewrite yes
    auto-aof-rewrite-percentage 100
    auto-aof-rewrite-min-size 256mb
    aof-use-rdb-preamble yes                # hybrid: fast loads, AOF durability

    save 900 1                              # RDB: snapshot if ≥1 key changed in 900s
    save 300 10
    save 60 10000
    rdbcompression yes
    rdbchecksum yes
    dbfilename dump.rdb
    dir /data

    # ── replication ──
    repl-diskless-sync yes                  # ⭐ stream the RDB over the socket, not the disk
    repl-diskless-sync-delay 5
    repl-timeout 300
    repl-backlog-size 256mb                 # bigger = replicas survive longer disconnects
    repl-backlog-ttl 3600
    min-replicas-to-write 1                 # ⭐ the primary REFUSES writes if <1 replica is up
    min-replicas-max-lag 10                 #    …or if the replica is >10s behind. Split-brain guard.

    # ── performance ──
    maxclients 5000
    io-threads 4
    io-threads-do-reads yes
    lazyfree-lazy-eviction yes
    lazyfree-lazy-expire yes
    lazyfree-lazy-server-del yes
    lazyfree-lazy-user-del yes
    hz 10
    dynamic-hz yes

    # ── logging ──
    loglevel notice
    logfile ""

    # ── slow log → find your bad queries ──
    slowlog-log-slower-than 10000           # microseconds
    slowlog-max-len 1024

    # ── client output buffers (protect against a slow consumer) ──
    client-output-buffer-limit normal 0 0 0
    client-output-buffer-limit replica 256mb 64mb 60
    client-output-buffer-limit pubsub 32mb 8mb 60
---
apiVersion: v1
kind: Service
metadata: {name: redis, namespace: db, labels: {app: redis}}
spec:
  clusterIP: None
  selector: {app: redis}
  ports:
    - {name: redis,   port: 6379}
    - {name: bus,     port: 16379}
    - {name: metrics, port: 9121}
  publishNotReadyAddresses: true
---
apiVersion: v1
kind: Service
metadata: {name: redis-primary, namespace: db, labels: {app: redis}}
spec:
  selector: {app: redis, role: primary}
  ports: [{name: redis, port: 6379}]
---
apiVersion: v1
kind: Service
metadata: {name: redis-replicas, namespace: db, labels: {app: redis}}
spec:
  selector: {app: redis, role: replica}
  ports: [{name: redis, port: 6379}]
---
apiVersion: v1
kind: ServiceAccount
metadata: {name: redis, namespace: db}
automountServiceAccountToken: true      # ⭐ the sentinel/role-manager sidecar needs the API
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: redis
  namespace: db
  labels: {app: redis}
spec:
  serviceName: redis
  replicas: 3
  podManagementPolicy: Parallel
  updateStrategy: {type: RollingUpdate}
  selector: {matchLabels: {app: redis}}
  template:
    metadata:
      labels: {app: redis}
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "9121"
    spec:
      serviceAccountName: redis
      terminationGracePeriodSeconds: 60
      securityContext:
        runAsNonRoot: true
        runAsUser: 999
        runAsGroup: 1000
        fsGroup: 1000
        seccompProfile: {type: RuntimeDefault}
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              podAffinityTerm:
                labelSelector: {matchLabels: {app: redis}}
                topologyKey: kubernetes.io/hostname

      initContainers:
        # ── render the config with the password substituted ──
        - name: render-config
          image: busybox:1.37
          command:
            - sh
            - -c
            - |
              set -eu
              PW=$(cat /creds/password)
              sed "s|__REDIS_PASSWORD__|$PW|" /src/redis-common.conf > /out/redis.conf
              chmod 640 /out/redis.conf
              echo "config rendered for $HOSTNAME"
          securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: ["ALL"]}}
          resources: {requests: {cpu: 10m, memory: 8Mi}, limits: {cpu: 100m, memory: 32Mi}}
          volumeMounts:
            - {name: config-src, mountPath: /src, readOnly: true}
            - {name: creds,      mountPath: /creds, readOnly: true}
            - {name: config,     mountPath: /out}

      containers:
        - name: redis
          image: redis:7-alpine
          command: ["redis-server", "/etc/redis/redis.conf"]
          ports:
            - {name: redis, containerPort: 6379}
            - {name: bus,   containerPort: 16379}
          securityContext:
            allowPrivilegeEscalation: false
            capabilities: {drop: ["ALL"]}
            readOnlyRootFilesystem: true
          env:
            - {name: REDIS_PASSWORD, valueFrom: {secretKeyRef: {name: redis-creds, key: password}}}
            - {name: POD_NAME,       valueFrom: {fieldRef: {fieldPath: metadata.name}}}
          readinessProbe:
            exec:
              command: ["sh","-c","redis-cli -a \"$REDIS_PASSWORD\" --no-auth-warning ping | grep -q PONG"]
            initialDelaySeconds: 5
            periodSeconds: 5
            timeoutSeconds: 3
            failureThreshold: 6
          livenessProbe:
            exec:
              command: ["sh","-c","redis-cli -a \"$REDIS_PASSWORD\" --no-auth-warning ping | grep -q PONG"]
            initialDelaySeconds: 30
            periodSeconds: 20
            timeoutSeconds: 5
            failureThreshold: 3
          lifecycle:
            preStop:
              exec:
                # ⭐ persist before dying, so a restart doesn't replay the whole AOF
                command: ["sh","-c","redis-cli -a \"$REDIS_PASSWORD\" --no-auth-warning BGSAVE_e91c; sleep 5"]
          resources:
            requests: {cpu: 250m, memory: 1Gi}
            limits:   {cpu: "2",   memory: 1536Mi}   # ⭐ maxmemory 1gb + 50% for overhead
          volumeMounts:
            - {name: config, mountPath: /etc/redis, readOnly: true}
            - {name: data,   mountPath: /data}
            - {name: tmp,    mountPath: /tmp}

        # ── ⭐ the role manager: keeps `role: primary`/`replica` labels correct ──
        #    Without this, the redis-primary Service points at the wrong Pod after a failover.
        - name: role-manager
          image: bitnami/kubectl:1.33
          command:
            - /bin/sh
            - -c
            - |
              set -eu
              NS=db; POD=$POD_NAME
              while true; do
                ROLE=$(redis-cli -h "$POD.redis.$NS.svc.cluster.local" -a "$REDIS_PASSWORD" \
                         --no-auth-warning INFO replication 2>/dev/null \
                       | tr -d '\r' | awk -F: '/^role:/{print $2}' || echo unknown)
                case "$ROLE" in
                  master)   WANT=primary ;;
                  slave)    WANT=replica ;;
                  *)        WANT=unknown ;;
                esac
                CUR=$(kubectl get pod -n $NS $POD -o jsonpath='{.metadata.labels.role}' 2>/dev/null || echo "")
                if [ "$CUR" != "$WANT" ]; then
                  echo "$(date +%T) $POD: $CUR → $WANT"
                  kubectl label pod -n $NS $POD role=$WANT --overwrite
                fi
                sleep 5
              done
          env:
            - {name: POD_NAME,       valueFrom: {fieldRef: {fieldPath: metadata.name}}}
            - {name: REDIS_PASSWORD, valueFrom: {secretKeyRef: {name: redis-creds, key: password}}}
          resources: {requests: {cpu: 10m, memory: 32Mi}, limits: {cpu: 100m, memory: 96Mi}}
          securityContext: {allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: {drop: ["ALL"]}}

        # ── metrics ──
        - name: exporter
          image: oliver006/redis_exporter:v1.66.0-alpine
          env:
            - {name: REDIS_ADDR,     value: "redis://localhost:6379"}
            - {name: REDIS_PASSWORD, valueFrom: {secretKeyRef: {name: redis-creds, key: password}}}
          ports: [{name: metrics, containerPort: 9121}]
          resources: {requests: {cpu: 20m, memory: 32Mi}, limits: {cpu: 200m, memory: 96Mi}}
          securityContext: {allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: {drop: ["ALL"]}}

      volumes:
        - {name: config-src, configMap: {name: redis-config}}
        - {name: config,     emptyDir: {}}
        - {name: tmp,        emptyDir: {sizeLimit: 64Mi}}
        - name: creds
          secret: {secretName: redis-creds, defaultMode: 0400}

  volumeClaimTemplates:
    - metadata: {name: data, labels: {app: redis}}
      spec:
        accessModes: [ReadWriteOnce]
        resources: {requests: {storage: 10Gi}}   # AOF + RDB need ~2× maxmemory
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata: {name: redis, namespace: db}
spec:
  minAvailable: 2
  selector: {matchLabels: {app: redis}}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: {name: redis-role-manager, namespace: db}
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "patch"]      # ⭐ patch, not update — least privilege
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: {name: redis-role-manager, namespace: db}
subjects: [{kind: ServiceAccount, name: redis, namespace: db}]
roleRef: {kind: Role, name: redis-role-manager, apiGroup: rbac.authorization.k8s.io}
```

```bash
kubectl apply -f redis/prod/redis.yaml
kubectl get pods -n db -l app=redis -w
```

```
redis-0   0/3   Init:0/1   …
redis-1   0/3   Init:0/1   …
redis-2   0/3   Init:0/1   …
redis-0   3/3   Running    …
```

**Configure replication** (redis-1 and redis-2 follow redis-0):

```bash
for i in 1 2; do
  kubectl exec -n db redis-$i -c redis -- sh -c \
    "redis-cli -a \"\$REDIS_PASSWORD\" --no-auth-warning REPLICAOF redis-0.redis.db.svc.cluster.local 6379"
done
# OK
# OK

sleep 5
for i in 0 1 2; do
  echo "── redis-$i ──"
  kubectl exec -n db redis-$i -c redis -- sh -c \
    "redis-cli -a \"\$REDIS_PASSWORD\" --no-auth-warning INFO replication" \
    | tr -d '\r' | grep -E '^role|^connected_slaves|^slave[0-9]|^master_link_status|^master_last_io'
done
```

```
── redis-0 ──
role:master
connected_slaves:2
slave0:ip=10.244.2.21,port=6379,state=online,offset=1284,lag=0
slave1:ip=10.244.3.18,port=6379,state=online,offset=1284,lag=1
── redis-1 ──
role:slave
master_link_status:up
master_last_io_seconds_ago:0
```

```bash
# the role-manager sidecar should have labelled them
kubectl get pods -n db -l app=redis -L role
# redis-0   3/3   Running   …   primary
# redis-1   3/3   Running   …   replica
# redis-2   3/3   Running   …   replica

kubectl get endpointslices -n db -l kubernetes.io/service-name=redis-primary \
  -o jsonpath='{.items[*].endpoints[*].addresses}'; echo
# ["10.244.1.14"]     ← ✅ only redis-0
```

**Verify read/write splitting:**

```bash
kubectl exec -n db redis-0 -c redis -- sh -c \
  'redis-cli -a "$REDIS_PASSWORD" --no-auth-warning SET product:1 "{\"name\":\"Widget\"}"'
# OK
sleep 1
kubectl exec -n db redis-2 -c redis -- sh -c \
  'redis-cli -a "$REDIS_PASSWORD" --no-auth-warning GET product:1'
# "{\"name\":\"Widget\"}"     ← ✅ replicated

# replicas must reject writes
kubectl exec -n db redis-1 -c redis -- sh -c \
  'redis-cli -a "$REDIS_PASSWORD" --no-auth-warning SET x y' 2>&1
# (error) READONLY You can't write against a read only replica.   ✅
```

### ⭐ The `maxmemory` sizing math — get this wrong and Redis dies

```
container limits.memory   1536 Mi
maxmemory                 1024 Mi   (66%)
+ AOF rewrite buffer       ~256 Mi  (a rewrite can double the RSS briefly)
+ client output buffers    ~100 Mi
+ replication backlog      ~128 Mi  (repl-backlog-size 256mb, partly resident)
+ Redis overhead            ~64 Mi
────────────────────────────────────
peak                      ~1572 Mi   ← ⚠️ very close to 1536!
```

**AOF rewrite is the trap.** During `BGREWRITEAOF`, Redis keeps a buffer of writes that arrive during the rewrite. Under load that buffer can be huge. `no-appendfsync-on-rewrite yes` (set above) helps.

**Rules:**

| `maxmemory` | `limits.memory` | Ratio |
|---|---|---|
| 256 MB | 512 Mi | 2.0× |
| 1 GB | 1.5 Gi | 1.5× |
| 4 GB | 6 Gi | 1.5× |
| 16 GB | 24 Gi | 1.5× |
| AOF disabled (pure cache) | 1.25× is enough | |

```bash
# measure it
kubectl exec -n db redis-0 -c redis -- sh -c \
  'redis-cli -a "$REDIS_PASSWORD" --no-auth-warning INFO memory' \
  | tr -d '\r' | grep -E 'used_memory_human|used_memory_peak_human|used_memory_rss_human|maxmemory_human|maxmemory_policy|mem_fragmentation_ratio|mem_clients'
```

```
used_memory_human:412.38M
used_memory_peak_human:438.21M
used_memory_rss_human:485.10M           ← what the OOM killer sees
maxmemory_human:1.00G
maxmemory_policy:allkeys-lru
mem_fragmentation_ratio:1.18            ← ✅ <1.5 is healthy
mem_clients_normal:12.4M
mem_clients_slaves:0B
```

`mem_fragmentation_ratio` above 1.5 means fragmentation — `activedefrag yes` (already set) handles it.

### The eviction-policy decision

| Policy | Behaviour | Use for |
|---|---|---|
| `noeviction` | **Errors** on writes when full | A real datastore. Never for a cache |
| `allkeys-lru` | Evict the least-recently-used of *any* key | **General-purpose cache** ← the default choice |
| `volatile-lru` | Evict LRU among keys *with a TTL* | Cache + persistent keys mixed |
| `allkeys-lfu` | Evict the least-*frequently*-used | Skewed access patterns (Redis 4+) |
| `volatile-lfu` | LFU among TTL keys | Same, mixed |
| `allkeys-random` | Random | Uniform access |
| `volatile-ttl` | Evict the key closest to expiring | Session stores |

⚠️ **`noeviction` + `maxmemory` set = your app gets `OOM command not allowed` errors.** That's usually *correct* for a datastore and *catastrophic* for a cache. Decide which Redis is, and set the policy deliberately.

### Failover — Redis replication is NOT automatic failover

Killing `redis-0` gives you:

```bash
kubectl delete pod -n db redis-0
sleep 20
kubectl exec -n db redis-1 -c redis -- sh -c 'redis-cli -a "$REDIS_PASSWORD" --no-auth-warning INFO replication' | grep '^role'
# role:slave        ← ⛔ still a replica. NOBODY was promoted. Writes are DOWN.
```

And `min-replicas-to-write 1` now means **the surviving primary (none) refuses writes**. This is where you need one of:

**Option A — Redis Sentinel** (3 more Pods that vote on a new primary):

```yaml
apiVersion: apps/v1
kind: Deployment
metadata: {name: redis-sentinel, namespace: db}
spec:
  replicas: 3
  selector: {matchLabels: {app: redis-sentinel}}
  template:
    metadata: {labels: {app: redis-sentinel}}
    spec:
      containers:
        - name: sentinel
          image: redis:7-alpine
          command: ["redis-sentinel", "/etc/sentinel/sentinel.conf"]
          ports: [{containerPort: 26379}]
          volumeMounts: [{name: conf, mountPath: /etc/sentinel}]
      volumes:
        - name: conf
          configMap:
            name: redis-sentinel-config
```

```yaml
apiVersion: v1
kind: ConfigMap
metadata: {name: redis-sentinel-config, namespace: db}
data:
  sentinel.conf: |
    port 26379
    sentinel monitor mymaster redis-0.redis.db.svc.cluster.local 6379 2
    sentinel auth-pass mymaster __REDIS_PASSWORD__
    sentinel down-after-milliseconds mymaster 5000
    sentinel failover-timeout mymaster 30000
    sentinel parallel-syncs mymaster 1
```

⚠️ Sentinel **rewrites its own config file** at runtime, so it needs a writable volume (`emptyDir` seeded from the ConfigMap by an init container), and the ConfigMap mount is read-only. This is a classic footgun.

**Option B — the operator** (what you should actually use):

```bash
# Spotahome's Redis Operator — Sentinel-based, well maintained
helm repo add spotahome https://spotahome.github.io/redis-operator
helm install redis-operator spotahome/redis-operator -n redis-operator --create-namespace
```

```yaml
apiVersion: databases.spotahome.com/v1
kind: RedisFailover
metadata: {name: shop-redis, namespace: db}
spec:
  sentinel:
    replicas: 3
    resources: {requests: {cpu: 100m, memory: 128Mi}, limits: {cpu: 300m, memory: 256Mi}}
    affinity:
      podAntiAffinity:
        preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm: {labelSelector: {matchLabels: {app.kubernetes.io/name: sentinel}}, topologyKey: kubernetes.io/hostname}
  redis:
    replicas: 3
    resources: {requests: {cpu: 250m, memory: 1Gi}, limits: {cpu: "2", memory: 1536Mi}}
    storage:
      persistentVolumeClaim:
        metadata: {name: redis-data}
        spec: {accessModes: [ReadWriteOnce], resources: {requests: {storage: 10Gi}}}
    exporter: {enabled: true}
    customCommandRenames:
      - {from: FLUSHALL, to: ""}
      - {from: FLUSHDB,  to: ""}
    shutdownConfigMap:
      name: redis-shutdown
  auth:
    secretPath: redis-creds
```

That gives you: Sentinel quorum, **automatic failover in ~10 s**, the role labels maintained, an exporter, and `rename-command` — in ~30 lines.

**Option C — Redis Cluster** (sharding, for >16 GB or >100k ops/s). Different topology, needs `cluster-enabled yes` and 6+ nodes. Out of scope for a learning project; use the operator if you need it.

**Test the operator's failover:**

```bash
kubectl get pods -n db -l app.kubernetes.io/name=redis -o wide
kubectl delete pod -n db <the primary>
watch -n1 'kubectl get pods -n db -l app.kubernetes.io/name=redis; \
           kubectl get svc redisfailover-shop-redis -n db -o jsonpath="{.spec.selector}"; echo'
```

~10 s later, the primary Service points at the newly elected node, writes resume. **That's the difference between hand-rolled and operator-managed.**

## Redis tasks

<details>
<summary>Task 13.3.1 — A single `KEYS *` command froze your whole application for 40 seconds. Explain and prevent it.</summary>

### What happened

```bash
kubectl exec -n db redis-0 -c redis -- sh -c \
  'redis-cli -a "$REDIS_PASSWORD" --no-auth-warning --latency-history -i 1' &
kubectl exec -n db redis-0 -c redis -- sh -c \
  'redis-cli -a "$REDIS_PASSWORD" --no-auth-warning DEBUG SLEEP 0; redis-cli -a "$REDIS_PASSWORD" --no-auth-warning SET k1 v1'
# now the bad command:
kubectl exec -n db redis-0 -c redis -- sh -c \
  'redis-cli -a "$REDIS_PASSWORD" --no-auth-warning CONFIG_b8f2e1a9 SET rename-command-foo bar' 2>/dev/null || true
```

**Redis is single-threaded for command execution.** One command blocks *everything* — every client, every replica, the AOF fsync, health checks. `KEYS *` on 20 million keys does an O(N) scan of the entire keyspace:

| Keyspace | `KEYS *` time | Impact |
|---|---|---|
| 1,000 | 1 ms | Unnoticeable |
| 100,000 | 25 ms | Visible p99 spike |
| 1,000,000 | 250 ms | Failed health checks |
| 20,000,000 | **~40 s** | ⛔ Total outage |

And it doesn't just block — it **builds a 20-million-element array in memory** before returning. That's another OOMKill vector.

### Prove it in a controlled way

```bash
# seed 1M keys
kubectl exec -n db redis-0 -c redis -- sh -c '
  PW="$REDIS_PASSWORD"
  for i in $(seq 1 2000); do
    printf "%s\n" $(seq 1 500 | sed "s/^/SET key:{i}:/;s/$/ value/") | redis-cli -a "$PW" --no-auth-warning --pipe
  done'
kubectl exec -n db redis-0 -c redis -- sh -c \
  'redis-cli -a "$REDIS_PASSWORD" --no-auth-warning DBSIZE'
# (integer) 1000000

# watch the latency from another shell
kubectl exec -n db redis-1 -c redis -- sh -c \
  'redis-cli -a "$REDIS_PASSWORD" --no-auth-warning --latency-history -i 1 -h redis-0.redis.db.svc.cluster.local' &

# now the offender
time kubectl exec -n db redis-0 -c redis -- sh -c \
  'redis-cli -a "$REDIS_PASSWORD" --no-auth-warning KEYS "*" | wc -l'
```

```
min: 0, max: 1, avg: 0.12 (1204 samples) -- 1.00 seconds range
min: 0, max: 42810, avg: 1284.20 (18 samples)   ← ⛔ 42-SECOND max latency
1000000
real    0m43.812s
```

Every client blocked for 43 seconds. Your app's readiness probes timed out. Kubernetes may have restarted the Pod.

### The prevention — five layers

**1. Disable the command entirely (already done in the ConfigMap above):**

```
rename-command KEYS ""
rename-command FLUSHALL ""
rename-command FLUSHDB ""
rename-command DEBUG ""
rename-command SAVE ""
rename-command SMEMBERS ""        # O(N) on large sets — consider it
rename-command HGETALL ""         # O(N) on large hashes — consider it
```

```bash
kubectl exec -n db redis-0 -c redis -- sh -c 'redis-cli -a "$REDIS_PASSWORD" --no-auth-warning KEYS "*"'
# (error) ERR unknown command 'KEYS', with args beginning with: '*',
```

⚠️ **`CONFIG` is special.** Some clients and monitoring tools need `CONFIG GET`. Obscure it rather than disabling:

```
rename-command CONFIG "CONFIG_b8f2e1a9"
```

⚠️ **Renaming in `redis.conf` doesn't affect `ACL`s.** In Redis 6+, prefer ACLs — they're per-user and don't break tooling that connects as a different user:

```bash
redis-cli -a "$PW" ACL SETUSER app on ">$PW" ~shop:* +get +set +del +expire +incr \
                                          -keys -flushall -flushdb -debug -config
redis-cli -a "$PW" ACL SETUSER readonly on ">$RO_PW" ~shop:* +get +mget +hget +hlen -@write -@dangerous
redis-cli -a "$PW" ACL SETUSER admin on ">$ADMIN_PW" ~* +@all
redis-cli -a "$PW" ACL LIST
redis-cli -a "$PW" ACL WHOAMI
```

```
1) "user app on sanitize-payload ~shop:* +get +set +del +expire +incr -keys -flushall …"
2) "user readonly on sanitize-payload ~shop:* +get +mget +hget +hlen -@write -@dangerous"
3) "user admin on sanitize-payload ~* +@all"
```

Persist the ACLs:

```
aclfile /data/users.acl
```

```bash
redis-cli -a "$PW" ACL SAVE       # writes the file
redis-cli -a "$PW" ACL LOAD       # reloads it
```

**2. Use `SCAN` instead — the correct answer.**

```bash
# ❌ KEYS — O(N), blocks, returns everything at once
redis-cli KEYS "user:*"

# ✅ SCAN — cursor-based, O(1) per call, never blocks meaningfully
redis-cli --scan --pattern "user:*" --count 100 | head
```

```bash
# in code (Node.js)
const stream = redis.scanStream({match: 'user:*', count: 100});
stream.on('data', keys => { stream.pause(); process(keys); stream.resume(); });

# Python
for key in r.scan_iter(match='user:*', count=100):
    process(key)

# Go
var cursor uint64
for {
    keys, cursor, err := rdb.Scan(ctx, cursor, "user:*", 100).Result()
    ...
    if cursor == 0 { break }
}
```

`SCAN` guarantees a *complete* iteration only if keys present the whole time aren't deleted — it may return duplicates. Handle that (idempotent processing).

**3. Avoid needing to scan at all — design the keyspace.**

```bash
# ❌ "find all a user's orders" by scanning
redis-cli --scan --pattern "order:*" | grep "user:42"

# ✅ keep a SET index per user
redis-cli SADD user:42:orders order:1001 order:1002 order:1003
redis-cli SMEMBERS user:42:orders          # O(M) where M is small

# ✅ or a sorted set for time-ordered access
redis-cli ZADD user:42:orders 1725888000 order:1001
redis-cli ZREVRANGEBYSCORE user:42:orders +inf -inf LIMIT 0 20

# ✅ hash tags to keep related keys in the same slot (Cluster)
SET {user:42}:profile …
SET {user:42}:cart …
```

**4. Block the other O(N) commands too.**

| Command | Complexity | Safer alternative |
|---|---|---|
| `KEYS` | O(N) | `SCAN` |
| `SMEMBERS` on a big set | O(N) | `SSCAN` |
| `HGETALL` on a big hash | O(N) | `HSCAN`, or `HMGET` with known fields |
| `LRANGE 0 -1` on a big list | O(N) | `LRANGE 0 99`, or `LPOP`/`RPOP` with a count |
| `ZUNIONSTORE` of big sets | O(N×M) | Do it in the app, or on a replica |
| `SORT` | O(N+M log M) | `ZSET` + `ZRANGE` |
| `DEL` of a huge key | O(N) | `UNLINK` (async, background thread) |
| `FLUSHALL` | O(N) | Disabled |

```
lazyfree-lazy-user-del yes      # makes DEL behave like UNLINK
lazyfree-lazy-expire yes        # expired keys freed in the background
lazyfree-lazy-eviction yes      # evictions freed in the background
```

Already in the ConfigMap above. This is Redis 4+ and it removes most of the "big key" stalls.

**5. Find the big keys before they find you.**

```bash
# the built-in scanner (safe — it uses SCAN internally)
kubectl exec -n db redis-0 -c redis -- sh -c \
  'redis-cli -a "$REDIS_PASSWORD" --no-auth-warning --bigkeys -i 0.1'
```

```
[00.00%] Biggest string found so far '"session:abc"' with 42 bytes
[12.40%] Biggest hash   found so far '"user:42:profile"' with 38 fields
[48.21%] Biggest set    found so far '"tag:electronics"' with 284103 members   ← ⛔
[91.02%] Biggest zset   found so far '"leaderboard"' with 1204821 members      ← ⛔

Sampled 1204821 keys in the keyspace.
Biggest set found 'tag:electronics' has 284103 members
Biggest zset found 'leaderboard' has 1204821 members
```

```bash
# memory usage of a specific key
redis-cli MEMORY USAGE leaderboard SAMPLES 0
# (integer) 84210334        ← 84 MB in ONE key

redis-cli OBJECT ENCODING leaderboard
# "skiplist"                ← big zsets become skiplists (more memory, better range ops)

redis-cli OBJECT FREQ / OBJECT IDLETIME
```

**Fix the big keys:**

```bash
# split the leaderboard into shards by score band
for band in 0 1 2 3 4 5 6 7 8 9; do
  redis-cli ZREMRANGEBYSCORE leaderboard "$((band*100000))" "$(((band+1)*100000-1))"
done
# or move it out of Redis entirely — a 1.2M-member zset belongs in a database
```

**Alert on it:**

```promql
# keyspace size growing unboundedly
rate(redis_keyspace_keys_total[1h]) > 100000

# a single command taking too long
redis_slowlog_length > 100

# blocked clients
redis_blocked_clients > 10

# the real canary: latency spikes
redis_latest_fork_usec > 500000        # forking for BGSAVE takes >0.5s = a big keyspace
```

```bash
redis-cli -a "$PW" SLOWLOG GET 10
```

```
1) 1) (integer) 4821
   2) (integer) 1725888421
   3) (integer) 43812044          ← ⛔ 43.8 SECONDS
   4) 1) "keys"
      2) "*"
   5) "10.244.2.19:41228"
   6) "shop-api-7d4f-abcde"       ← ✅ you know exactly which Pod did it
```

`slowlog-log-slower-than 10000` (10 ms) plus the client address/name makes this a 30-second investigation instead of a 3-hour one. **Set client names in your app:**

```javascript
redis.client('SETNAME', `shop-api-${process.env.POD_NAME}`);
```

</details>

<details>
<summary>Task 13.3.2 — Make Redis the session store for a horizontally scaled app, and prove sessions survive a Pod restart.</summary>

The goal: kill any app Pod and any Redis Pod, and no user is logged out.

### The architecture

```
   browser ──► Ingress ──► shop-api (5 replicas, stateless)
                              │ session read/write
                              ▼
                        redis-primary  ──► redis-1, redis-2 (replicas)
                              │
                              └── AOF everysec → PVC → survives restarts
```

### 1. Spring Boot + Redis sessions

```xml
<dependency>
  <groupId>org.springframework.session</groupId>
  <artifactId>spring-session-data-redis</artifactId>
</dependency>
<dependency>
  <groupId>org.springframework.boot</groupId>
  <artifactId>spring-boot-starter-data-redis</artifactId>
</dependency>
```

```java
@Configuration
@EnableRedisHttpSession(
    redisNamespace = "shop:session",
    maxInactiveIntervalInSeconds = 1800,       // 30 min
    flushMode = FlushMode.ON_SAVE              // ⭐ batch writes; IMMEDIATE costs 1 round trip per change
)
public class SessionConfig {

    @Bean
    public LettuceConnectionFactory redisConnectionFactory(RedisProperties p) {
        RedisStandaloneConfiguration primary = new RedisStandaloneConfiguration();
        primary.setHostName("redis-primary.db.svc.cluster.local");
        primary.setPort(6379);
        primary.setPassword(RedisPassword.of(p.getPassword()));

        // replicas for reads
        RedisStaticMasterReplicaConfiguration mr = new RedisStaticMasterReplicaConfiguration(
            "redis-primary.db.svc.cluster.local", 6379);
        mr.addNode("redis-1.redis.db.svc.cluster.local", 6379);
        mr.addNode("redis-2.redis.db.svc.cluster.local", 6379);

        LettuceClientConfiguration cc = LettuceClientConfiguration.builder()
            .commandTimeout(Duration.ofMillis(500))          // ⭐ fail fast
            .shutdownTimeout(Duration.ofMillis(200))
            .clientOptions(ClientOptions.builder()
                .autoReconnect(true)
                .disconnectedBehavior(DisconnectedBehavior.REJECT_COMMANDS)  // ⭐ don't queue forever
                .timeoutOptions(TimeoutOptions.enabled(Duration.ofMillis(500)))
                .build())
            .build();

        return new LettuceConnectionFactory(mr, cc);
    }

    @Bean
    public CookieSerializer cookieSerializer() {
        DefaultCookieSerializer s = new DefaultCookieSerializer();
        s.setCookieName("SHOPSESSION");
        s.setCookiePath("/");
        s.setUseSecureCookie(true);            // ⭐ HTTPS only
        s.setUseHttpOnlyCookie(true);          // ⭐ not readable by JS
        s.setSameSite("Lax");                  // ⭐ CSRF defence
        s.setDomainName("shop.example.com");
        s.setCookieMaxAge(1800);
        return s;
    }
}
```

```yaml
# application.yml
spring:
  data:
    redis:
      password: ${REDIS_PASSWORD}
      timeout: 500ms
      lettuce:
        pool:
          max-active: 32        # ⭐ 5 app pods × 32 = 160 < Redis maxclients 5000
          max-idle: 8
          min-idle: 2
          max-wait: 200ms
        shutdown-timeout: 200ms
  session:
    store-type: redis
    timeout: 30m
    redis:
      namespace: shop:session
      flush-mode: on_save
```

### 2. FastAPI + Redis sessions

```python
# pip install redis[hiredis] starlette-session-redis  (or roll it yourself)
import redis.asyncio as redis
from starlette.middleware.sessions import SessionMiddleware   # signed-cookie variant

# for a real server-side session store:
class RedisSessionStore:
    def __init__(self, url: str, ttl: int = 1800, prefix: str = "shop:session:"):
        self.r = redis.from_url(
            url,
            max_connections=32,
            socket_timeout=0.5,           # ⭐ fail fast
            socket_connect_timeout=0.5,
            socket_keepalive=True,
            health_check_interval=30,
            retry_on_timeout=True,
            decode_responses=False,
            protocol=2,                   # RESP3 if your server supports it
        )
        self.ttl = ttl
        self.prefix = prefix

    async def get(self, sid: str) -> dict:
        raw = await self.r.get(self.prefix + sid)
        return msgpack.unpackb(raw) if raw else {}

    async def set(self, sid: str, data: dict) -> None:
        # ⭐ pipeline: SET + EXPIRE in ONE round trip
        async with self.r.pipeline(transaction=True) as pipe:
            pipe.set(self.prefix + sid, msgpack.packb(data), ex=self.ttl)
            await pipe.execute()

    async def delete(self, sid: str) -> None:
        await self.r.delete(self.prefix + sid)

    async def touch(self, sid: str) -> None:
        await self.r.expire(self.prefix + sid, self.ttl)
```

```python
SESSIONS = RedisSessionStore(os.environ["REDIS_URL"])

@app.middleware("http")
async def session_middleware(request: Request, call_next):
    sid = request.cookies.get("SHOPSESSION")
    if not sid:
        sid = secrets.token_urlsafe(32)
    request.state.session_id = sid
    request.state.session = await SESSIONS.get(sid)
    response = await call_next(request)
    if request.state.session_changed:
        await SESSIONS.set(sid, request.state.session)
    else:
        await SESSIONS.touch(sid)
    response.set_cookie(
        "SHOPSESSION", sid,
        max_age=1800, httponly=True, secure=True, samesite="lax", path="/",
    )
    return response
```

### 3. The Kubernetes manifests for the app

```yaml
apiVersion: v1
kind: Secret
metadata: {name: redis-app-creds, namespace: shop}
stringData:
  password: "R3d1s-Pr0d-K8s!-M4"
---
apiVersion: v1
kind: ConfigMap
metadata: {name: shop-api-config, namespace: shop}
data:
  # ⭐ ALL members, so the driver can fail over. Not just the primary.
  SPRING_DATA_REDIS_HOST: "redis-primary.db.svc.cluster.local"
  SPRING_SESSION_REDIS_NAMESPACE: "shop:session"
  REDIS_URL: "redis://:__PW__@redis-primary.db.svc.cluster.local:6379/0?socket_timeout=500"
---
# and in the Deployment env:
env:
  - name: REDIS_PASSWORD
    valueFrom: {secretKeyRef: {name: redis-app-creds, key: password}}
  - name: SPRING_DATA_REDIS_PASSWORD
    valueFrom: {secretKeyRef: {name: redis-app-creds, key: password}}
```

**NetworkPolicy** — only the app may reach Redis:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: redis, namespace: db}
spec:
  podSelector: {matchLabels: {app: redis}}
  policyTypes: [Ingress]
  ingress:
    - from:
        - namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: shop}}
          podSelector: {matchLabels: {app: shop-api}}
      ports: [{protocol: TCP, port: 6379}]
    - from: [{podSelector: {matchLabels: {app: redis}}}]     # replication between members
      ports: [{protocol: TCP, port: 6379}, {protocol: TCP, port: 16379}]
    - from: [{namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: monitoring}}}]
      ports: [{protocol: TCP, port: 9121}]
```

⛔ **An unauthenticated Redis reachable from outside the cluster is a crypto-miner in 20 minutes.** Password + NetworkPolicy + no LoadBalancer Service, always.

### 4. Prove sessions survive an app Pod restart

```bash
# log in and capture the cookie
curl -sk -c /tmp/cookies.txt -XPOST https://shop.example.com/login \
  --resolve shop.example.com:443:$LB_IP \
  -d 'username=demo&password=demo123'
cat /tmp/cookies.txt
# shop.example.com  FALSE  /  TRUE  1725890221  SHOPSESSION  NzQ2Y2…

# use the session
curl -sk -b /tmp/cookies.txt --resolve shop.example.com:443:$LB_IP \
  https://shop.example.com/api/me | jq .
# {"username":"demo","cart":["Widget"]}

# it's in Redis
SID=$(awk '/SHOPSESSION/{print $7}' /tmp/cookies.txt)
kubectl exec -n db redis-0 -c redis -- sh -c \
  "redis-cli -a \"\$REDIS_PASSWORD\" --no-auth-warning --scan --pattern 'shop:session:*$SID*' | head -3" 2>/dev/null || \
kubectl exec -n db redis-0 -c redis -- sh -c \
  "redis-cli -a \"\$REDIS_PASSWORD\" --no-auth-warning --scan --pattern 'shop:session:*' | head -3"
kubectl exec -n db redis-0 -c redis -- sh -c \
  "redis-cli -a \"\$REDIS_PASSWORD\" --no-auth-warning HGETALL 'spring:session:sessions:$SID'"
```

```
1) "creationTime"       2) "1725888421000"
3) "maxInactiveInterval" 4) "1800"
5) "lastAccessedTime"   6) "1725888512000"
7) "sessionAttr:userId" 8) "\xac\xed\x00\x05t\x00\x04demo"
```

**Now kill every app Pod:**

```bash
kubectl delete pods -n shop -l app=shop-api --wait=false
kubectl rollout status deploy/shop-api -n shop --timeout=180s
kubectl get pods -n shop -l app=shop-api          # all new names

# the SAME cookie still works
curl -sk -b /tmp/cookies.txt --resolve shop.example.com:443:$LB_IP \
  https://shop.example.com/api/me | jq .
# {"username":"demo","cart":["Widget"]}      ← ✅ session survived
```

### 5. Prove sessions survive a Redis Pod restart

```bash
# which Pod is primary?
PRIMARY=$(kubectl get pods -n db -l app=redis,role=primary -o jsonpath='{.items[0].metadata.name}')
echo "killing $PRIMARY"

# continuous session check
( while true; do
    code=$(curl -sk -b /tmp/cookies.txt -o /dev/null -w '%{http_code}' --max-time 3 \
             --resolve shop.example.com:443:$LB_IP https://shop.example.com/api/me)
    echo "$(date +%T) $code"; sleep 0.5
  done ) > /tmp/sessions.txt &
CHECK=$!

kubectl delete pod -n db $PRIMARY
sleep 60
kill $CHECK
awk '{print $2}' /tmp/sessions.txt | sort | uniq -c
```

```
     98 200
      6 500      ← ⛔ the gap
```

**Six failures. Why, and how to fix each:**

```bash
kubectl logs -n shop deploy/shop-api --tail=100 | grep -iE 'redis|connection' | head
```

```
org.springframework.data.redis.RedisConnectionFailureException:
  Unable to connect to Redis server: redis-primary.db.svc.cluster.local/10.96.42.7:6379
```

**Problem A — the `redis-primary` Service had no endpoints during the switch.**

```bash
kubectl get endpointslices -n db -l kubernetes.io/service-name=redis-primary
# (empty during the ~10s the role-manager hasn't relabelled yet)
```

Fix: run the role-manager sidecar (already in the manifest) so the label flips in <5 s, **or** let the driver do topology discovery instead of relying on a Service:

```yaml
SPRING_DATA_REDIS_SENTINEL_MASTER: mymaster
SPRING_DATA_REDIS_SENTINEL_NODES: "sentinel-0:26379,sentinel-1:26379,sentinel-2:26379"
```

**Problem B — no retry.** One failed command = one 500.

```java
@Bean
public RedisTemplate<String, Object> redisTemplate(RedisConnectionFactory cf) {
    RedisTemplate<String, Object> t = new RedisTemplate<>();
    t.setConnectionFactory(cf);
    t.setEnableTransactionSupport(false);
    return t;
}

// and retry at the service layer
@Retryable(
    retryFor = {RedisConnectionFailureException.class, RedisSystemException.class},
    maxAttempts = 3,
    backoff = @Backoff(delay = 100, multiplier = 2, maxDelay = 1000)
)
public UserSession loadSession(String id) { return sessionRepo.findById(id).orElseThrow(); }
```

**Problem C — the session should degrade, not fail.** A user browsing the catalog doesn't need their session:

```java
@GetMapping("/api/me")
public ResponseEntity<?> me(@CookieValue(value = "SHOPSESSION", required = false) String sid) {
    if (sid == null) return ResponseEntity.status(401).body(Map.of("error", "not authenticated"));
    try {
        return ResponseEntity.ok(sessionService.load(sid));
    } catch (RedisConnectionFailureException e) {
        log.warn("session store unavailable", e);
        // ⭐ 503 with Retry-After, not a 500. The client can retry.
        return ResponseEntity.status(503)
            .header("Retry-After", "2")
            .body(Map.of("error", "session_unavailable"));
    }
}
```

**Problem D — the data itself.** Was the session lost, or just unreachable?

```bash
# the AOF is on a PVC, so a restart of the SAME Pod keeps everything
kubectl exec -n db redis-0 -c redis -- sh -c \
  'redis-cli -a "$REDIS_PASSWORD" --no-auth-warning DBSIZE'
# (integer) 4821

kubectl exec -n db redis-0 -c redis -- ls -lh /data
# -rw-r--r-- 1 redis redis  84M appendonly.aof.1.base.rdb
# -rw-r--r-- 1 redis redis 2.1M appendonly.aof.1.incr.aof
# -rw-r--r-- 1 redis redis  12M dump.rdb
```

With `appendfsync everysec`, at most **1 second** of sessions written just before the kill are lost. Verify:

```bash
# write a session, immediately kill, check it survived
SID=test-$(date +%s)
kubectl exec -n db redis-0 -c redis -- sh -c \
  "redis-cli -a \"\$REDIS_PASSWORD\" --no-auth-warning SET shop:session:$SID alive EX 300"
kubectl delete pod -n db redis-0 --wait=false
kubectl rollout status sts/redis -n db --timeout=180s
kubectl exec -n db redis-0 -c redis -- sh -c \
  "redis-cli -a \"\$REDIS_PASSWORD\" --no-auth-warning GET shop:session:$SID"
# "alive"        ← ✅ the AOF replayed
```

### 6. The full acceptance test

```bash
#!/usr/bin/env bash
set -uo pipefail
NS=shop; DBNS=db; HOST=shop.example.com
LB_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
C="curl -sk --resolve $HOST:443:$LB_IP"

echo "▸ 1. login"
$C -c /tmp/ck.txt -XPOST "https://$HOST/login" -d 'username=demo&password=demo123' -o /dev/null -w '%{http_code}\n'

check() { $C -b /tmp/ck.txt -o /dev/null -w '%{http_code}' --max-time 3 "https://$HOST/api/me"; }
watch() { local n=${1:-40}; local ok=0 bad=0
  for i in $(seq 1 $n); do
    c=$(check); [ "$c" = 200 ] && ok=$((ok+1)) || { bad=$((bad+1)); echo "   $(date +%T) $c"; }
    sleep 0.5
  done
  echo "   → ok=$ok failed=$bad"; }

echo "▸ 2. baseline"; watch 20

echo "▸ 3. kill ALL app pods"
kubectl delete pods -n $NS -l app=shop-api --wait=false >/dev/null
kubectl rollout status deploy/shop-api -n $NS --timeout=180s >/dev/null
watch 40

echo "▸ 4. kill the Redis primary"
P=$(kubectl get pods -n $DBNS -l app=redis,role=primary -o jsonpath='{.items[0].metadata.name}')
echo "   killing $P"
kubectl delete pod -n $DBNS $P --wait=false >/dev/null
kubectl rollout status sts/redis -n $DBNS --timeout=300s >/dev/null
watch 60

echo "▸ 5. scale the app to 1 and back to 5"
kubectl scale deploy/shop-api -n $NS --replicas=1
kubectl rollout status deploy/shop-api -n $NS --timeout=120s >/dev/null
watch 20
kubectl scale deploy/shop-api -n $NS --replicas=5
kubectl rollout status deploy/shop-api -n $NS --timeout=180s >/dev/null
watch 20

echo "▸ 6. final session read"
$C -b /tmp/ck.txt "https://$HOST/api/me" | jq .
```

Expected output when everything is right:

```
▸ 2. baseline        → ok=20 failed=0
▸ 3. kill ALL app pods
                     → ok=40 failed=0
▸ 4. kill the Redis primary
   killing redis-0
   15:42:11 503      ← ~2s while Sentinel/role-manager promotes
   15:42:12 503
                     → ok=58 failed=2
▸ 5. scale the app to 1 and back to 5
                     → ok=20 failed=0
                     → ok=20 failed=0
▸ 6. final session read
{"username":"demo","cart":["Widget"]}      ← ✅ session survived EVERYTHING
```

**2 failures out of 60 requests during a Redis primary kill, with automatic recovery.** That's the target. Getting to 0 requires Sentinel + driver-side topology discovery + retries.

</details>

---
---

# 13.4 — DynamoDB Local

## Why this one is different

**DynamoDB Local is an emulator.** It's a Java process that mimics the DynamoDB HTTP API and stores data in SQLite. It exists so you can develop and test without an AWS account or network calls.

**Running it in production is always wrong.** Run the real DynamoDB (a managed service — nothing to operate) or use a genuine local alternative. So this mini-project teaches something different: **how to run a dev-only dependency in Kubernetes cleanly, and how to keep it out of production.**

## 🔵 Case 1 — one Pod, in-memory SQLite (5 minutes)

```bash
mkdir -p ~/k8s-learn/p13/dynamodb && cd ~/k8s-learn/p13
```

`dynamodb/simple.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata: {name: dynamodb-local, labels: {app: dynamodb-local}}
spec:
  replicas: 1
  selector: {matchLabels: {app: dynamodb-local}}
  template:
    metadata: {labels: {app: dynamodb-local}}
    spec:
      containers:
        - name: dynamodb
          image: amazon/dynamodb-local:2.5.2
          # ⭐ -inMemory: SQLite in RAM. Data is LOST on restart — which is what you want in dev.
          args: ["-jar", "DynamoDBLocal.jar", "-inMemory", "-sharedDb"]
          ports: [{name: http, containerPort: 8000}]
          readinessProbe:
            # ⭐ DynamoDB Local has no /health. Use a real API call.
            httpGet: {path: /, port: http}
            initialDelaySeconds: 10
            periodSeconds: 10
            failureThreshold: 20
          resources:
            requests: {cpu: 250m, memory: 512Mi}
            limits:   {cpu: "1",   memory: 1Gi}     # ⭐ it's a JVM — needs room
---
apiVersion: v1
kind: Service
metadata: {name: dynamodb-local}
spec:
  selector: {app: dynamodb-local}
  ports: [{name: http, port: 8000}]
```

> ⚠️ **The default entrypoint is wrong for `args`.** `amazon/dynamodb-local` has `ENTRYPOINT ["java","-jar","DynamoDBLocal.jar"]`, so `args` appends. Use either:
> ```yaml
> args: ["-inMemory", "-sharedDb"]                       # ✅ appends to the entrypoint
> ```
> or override both:
> ```yaml
> command: ["java","-jar","DynamoDBLocal.jar"]
> args: ["-inMemory","-sharedDb"]
> ```
> Writing `args: ["-jar","DynamoDBLocal.jar",…]` produces `java -jar DynamoDBLocal.jar -jar DynamoDBLocal.jar …` and fails.

```bash
kubectl apply -f dynamodb/simple.yaml
kubectl rollout status deploy/dynamodb-local --timeout=120s
kubectl logs deploy/dynamodb-local --tail=10
# Initializing DynamoDB Local with the following settings:
# SharedDb:     true
# InMemory:     true
# DbPath:       null
# …
# Started server on port 8000
```

**Use it — DynamoDB Local requires *some* AWS credentials, any values work:**

```bash
kubectl port-forward svc/dynamodb-local 8000:8000 &
sleep 2

export AWS_ACCESS_KEY_ID=local AWS_SECRET_ACCESS_KEY=local AWS_DEFAULT_REGION=us-east-1
export AWS_ENDPOINT_URL=http://localhost:8000

aws dynamodb list-tables
# {"TableNames": []}

aws dynamodb create-table \
  --table-name products \
  --attribute-definitions AttributeName=pk,AttributeType=S AttributeName=sk,AttributeType=S \
  --key-schema AttributeName=pk,KeyType=HASH AttributeName=sk,KeyType=RANGE \
  --billing-mode PAY_PER_REQUEST
# {"TableDescription":{"TableStatus":"ACTIVE", …}}

aws dynamodb put-item --table-name products --item '{
  "pk":{"S":"PRODUCT#1"},"sk":{"S":"META"},
  "name":{"S":"Widget"},"price":{"N":"9.99"}}'

aws dynamodb query --table-name products \
  --key-condition-expression "pk = :pk" \
  --expression-attribute-values '{":pk":{"S":"PRODUCT#1"}}'
# {"Items":[{…}], "Count":1}
```

**Why `-sharedDb` matters:** without it, DynamoDB Local partitions data **by AWS account+region**, so a CLI call with one credential set can't see data written by your app with another. `-sharedDb` puts everything in one SQLite file. Always use it in dev.

## 🟢 Case 2 — persistent, multi-environment, and guaranteed absent from production (20 minutes)

`dynamodb/prod/dev-only.yaml`:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: dev-deps
  labels:
    purpose: development-only
    # ⭐ Kyverno / OPA can enforce "nothing here in prod"
    environment: dev
---
# A PVC so tables survive a restart — useful for long-lived dev environments,
# but you should be able to throw it away at any time.
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: dynamodb-local-data, namespace: dev-deps}
spec:
  accessModes: [ReadWriteOnce]
  resources: {requests: {storage: 5Gi}}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dynamodb-local
  namespace: dev-deps
  labels: {app: dynamodb-local, environment: dev}
spec:
  replicas: 1
  selector: {matchLabels: {app: dynamodb-local}}
  strategy: {type: Recreate}
  template:
    metadata: {labels: {app: dynamodb-local, environment: dev}}
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        seccompProfile: {type: RuntimeDefault}
      containers:
        - name: dynamodb
          image: amazon/dynamodb-local:2.5.2
          args:
            - -dbPath
            - /home/dynamodblocal/data          # ⭐ persistent, NOT -inMemory
            - -sharedDb
            - -optimizeDbBeforeStartup
            - -disableTelemetry
          ports: [{name: http, containerPort: 8000}]
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: false       # ⭐ it writes SQLite journal files everywhere
            capabilities: {drop: ["ALL"]}
          env:
            - {name: JAVA_OPTS, value: "-XX:MaxRAMPercentage=60 -XX:+UseSerialGC"}
          readinessProbe:
            httpGet: {path: /, port: http}
            initialDelaySeconds: 15
            periodSeconds: 10
            failureThreshold: 30
          livenessProbe:
            httpGet: {path: /, port: http}
            initialDelaySeconds: 60
            periodSeconds: 30
          resources:
            requests: {cpu: 250m, memory: 768Mi}
            limits:   {cpu: "1",   memory: 1Gi}
          volumeMounts:
            - {name: data, mountPath: /home/dynamodblocal/data}
      volumes:
        - {name: data, persistentVolumeClaim: {claimName: dynamodb-local-data}}
---
apiVersion: v1
kind: Service
metadata: {name: dynamodb-local, namespace: dev-deps}
spec:
  selector: {app: dynamodb-local}
  ports: [{name: http, port: 8000}]
---
# ⭐ seed the tables automatically on startup
apiVersion: batch/v1
kind: Job
metadata:
  name: dynamodb-seed
  namespace: dev-deps
  annotations:
    "helm.sh/hook": post-install,post-upgrade
    "helm.sh/hook-delete-policy": before-hook-creation
spec:
  backoffLimit: 3
  ttlSecondsAfterFinished: 3600
  template:
    spec:
      restartPolicy: OnFailure
      containers:
        - name: seed
          image: amazon/aws-cli:2.22.0
          command: ["/bin/sh","-c"]
          args:
            - |
              set -eu
              export AWS_ACCESS_KEY_ID=local AWS_SECRET_ACCESS_KEY=local AWS_DEFAULT_REGION=us-east-1
              EP=http://dynamodb-local.dev-deps.svc.cluster.local:8000

              echo "▸ waiting for dynamodb-local"
              for i in $(seq 1 60); do
                aws dynamodb list-tables --endpoint-url $EP >/dev/null 2>&1 && break
                sleep 2
              done

              echo "▸ creating tables (idempotent)"
              create() {
                aws dynamodb create-table --endpoint-url $EP \
                  --table-name "$1" \
                  --attribute-definitions "$2" \
                  --key-schema "$3" \
                  --billing-mode PAY_PER_REQUEST 2>&1 \
                  | grep -q 'ResourceInUseException' && echo "   $1 already exists" || echo "   ✅ $1 created"
              }

              create products \
                'AttributeName=pk,AttributeType=S AttributeName=sk,AttributeType=S' \
                'AttributeName=pk,KeyType=HASH AttributeName=sk,KeyType=RANGE'

              create orders \
                'AttributeName=userId,AttributeType=S AttributeName=orderId,AttributeType=S' \
                'AttributeName=userId,KeyType=HASH AttributeName=orderId,KeyType=RANGE'

              create sessions \
                'AttributeName=sid,AttributeType=S' \
                'AttributeName=sid,KeyType=HASH'

              echo "▸ global secondary indexes"
              aws dynamodb update-table --endpoint-url $EP --table-name products \
                --attribute-definitions AttributeName=GSI1PK,AttributeType=S AttributeName=GSI1SK,AttributeType=S \
                --global-secondary-index-updates '[{"Create":{"IndexName":"byCategory",
                    "KeySchema":[{"AttributeName":"GSI1PK","KeyType":"HASH"},{"AttributeName":"GSI1SK","KeyType":"RANGE"}],
                    "Projection":{"ProjectionType":"ALL"}}}]' 2>/dev/null || echo "   GSI already exists"

              echo "▸ seeding data"
              for i in $(seq 1 20); do
                aws dynamodb put-item --endpoint-url $EP --table-name products --item "{
                  \"pk\":{\"S\":\"PRODUCT#$i\"},\"sk\":{\"S\":\"META\"},
                  \"name\":{\"S\":\"Product $i\"},\"price\":{\"N\":\"$((i*10)).99\"},
                  \"GSI1PK\":{\"S\":\"CATEGORY#widgets\"},\"GSI1SK\":{\"S\":\"$i\"}}" >/dev/null
              done

              echo "▸ verify"
              aws dynamodb list-tables --endpoint-url $EP
              for t in products orders sessions; do
                echo -n "   $t: "
                aws dynamodb scan --endpoint-url $EP --table-name $t --select COUNT --query 'Count' --output text
              done
          resources: {requests: {cpu: 100m, memory: 128Mi}, limits: {cpu: 500m, memory: 256Mi}}
---
# ⭐ THE GUARDRAIL: a Kyverno policy that REFUSES dynamodb-local in prod
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: no-dev-emulators-in-prod
  annotations:
    policies.kyverno.io/title: Block development-only emulators in production
spec:
  validationFailureAction: Enforce
  background: true
  rules:
    - name: block-dynamodb-local
      match:
        any:
          - resources:
              kinds: [Pod]
              namespaces: ["prod", "production", "shop-prod"]
      validate:
        message: >-
          amazon/dynamodb-local is a development emulator and must never run in a
          production namespace. Use the real DynamoDB service endpoint instead.
        pattern:
          spec:
            =(containers):
              - =(image): "!amazon/dynamodb-local*"
    - name: block-by-label
      match:
        any:
          - resources:
              kinds: [Pod]
              selector:
                matchLabels: {environment: prod}
      validate:
        message: "Pods labelled environment=prod may not use dev-only images."
        deny:
          conditions:
            any:
              - key: "{{ request.object.spec.containers[].image }}"
                operator: AnyIn
                value: ["amazon/dynamodb-local*", "*localstack*", "*mailhog*", "*mongo-express*"]
```

**Test the guardrail:**

```bash
kubectl apply -f dynamodb/prod/dev-only.yaml
kubectl get pods,jobs -n dev-deps

# now try to put it in prod
kubectl create namespace prod --dry-run=client -o yaml | kubectl apply -f -
sed 's/namespace: dev-deps/namespace: prod/' dynamodb/prod/dev-only.yaml | kubectl apply -f - 2>&1 | head
```

```
Error from server: error when creating "STDIN": admission webhook "validate.kyverno.svc-fail" denied the request:

resource Deployment/prod/dynamodb-local was blocked due to the following policies

no-dev-emulators-in-prod:
  block-dynamodb-local: amazon/dynamodb-local is a development emulator and must never
  run in a production namespace. Use the real DynamoDB service endpoint instead.
```

✅ **Blocked by policy, not by convention.**

### The app config — switching between local and real

```yaml
# ConfigMap for dev
apiVersion: v1
kind: ConfigMap
metadata: {name: shop-api-config, namespace: shop-dev}
data:
  AWS_REGION: "us-east-1"
  AWS_ENDPOINT_URL_DYNAMODB: "http://dynamodb-local.dev-deps.svc.cluster.local:8000"
  AWS_ACCESS_KEY_ID: "local"          # ⭐ any value; DynamoDB Local doesn't check
  DYNAMODB_TABLE_PRODUCTS: "products"
---
# ConfigMap for prod — NO endpoint override, real IAM
apiVersion: v1
kind: ConfigMap
metadata: {name: shop-api-config, namespace: shop-prod}
data:
  AWS_REGION: "ap-south-1"
  # AWS_ENDPOINT_URL_DYNAMODB deliberately ABSENT → the SDK uses the real service
  DYNAMODB_TABLE_PRODUCTS: "shop-products-prod"
```

```java
// The SDK v2 picks up AWS_ENDPOINT_URL_DYNAMODB automatically. No code change.
@Bean
public DynamoDbClient dynamoDb() {
    return DynamoDbClient.builder()
        .region(Region.of(System.getenv().getOrDefault("AWS_REGION", "us-east-1")))
        .build();
}
```

```python
# boto3
import os
client = boto3.client(
    "dynamodb",
    region_name=os.environ.get("AWS_REGION", "us-east-1"),
    endpoint_url=os.environ.get("AWS_ENDPOINT_URL_DYNAMODB"),   # None → the real service
)
```

**For production auth, use IRSA / Workload Identity — never static keys:**

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: shop-api
  namespace: shop-prod
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/shop-api-dynamodb
```

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["dynamodb:GetItem","dynamodb:PutItem","dynamodb:Query","dynamodb:UpdateItem","dynamodb:DeleteItem"],
    "Resource": ["arn:aws:dynamodb:ap-south-1:123456789012:table/shop-products-prod",
                 "arn:aws:dynamodb:ap-south-1:123456789012:table/shop-products-prod/index/*"]
  }]
}
```

### The honest comparison — and what to use instead

| | DynamoDB Local | Real DynamoDB | Alternativa | LocalStack |
|---|---|---|---|---|
| Fidelity | ~85% | 100% | ~90% | ~70% |
| Transactions | Partial | ✅ | ✅ | Partial |
| Streams | ❌ | ✅ | ✅ | Partial |
| TTL | ❌ | ✅ | ✅ | Partial |
| Global tables | ❌ | ✅ | ❌ | ❌ |
| DAX | ❌ | ✅ | ❌ | ❌ |
| On-demand capacity behaviour | Approximated | ✅ | ✅ | Approximated |
| Cost | Free | Pay-per-use | Free (open source) | Free / Pro |
| Runs in K8s | ✅ | n/a (managed) | ✅ | ✅ |
| Licence | AWS, dev/test only | AWS | Apache 2.0 | Apache 2.0 (community) |

**Where DynamoDB Local bites you:**
- **No TTL** — items that expire in production never expire locally. Your "cleanup" logic goes untested.
- **No Streams** — anything triggered by a change is untestable.
- **Different error semantics** — throttling (`ProvisionedThroughputExceededException`) doesn't happen locally, so your retry/backoff code never runs.
- **No PartiQL nuances, no adaptive capacity.**
- **It's a JVM** — 1 GB of RAM for a dev dependency.

**Better choices:**
- **DynamoDB Local On-Demand** (a newer AWS offering) — closer fidelity
- **Alternativa** — an open-source DynamoDB-compatible server with streams and TTL, designed to run in Kubernetes
- **Testcontainers with DynamoDB Local** for integration tests (throwaway per test run)
- **A real AWS account with a dev table** — for anything involving streams, TTL, or throughput testing

```bash
# Alternativa, as a drop-in
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: alternativa, namespace: dev-deps}
spec:
  replicas: 1
  selector: {matchLabels: {app: alternativa}}
  template:
    metadata: {labels: {app: alternativa}}
    spec:
      containers:
        - name: alternativa
          image: alternativa/alternativa:latest
          ports: [{containerPort: 8000}]
          readinessProbe: {httpGet: {path: /health, port: 8000}, periodSeconds: 5}
          resources: {requests: {cpu: 250m, memory: 512Mi}, limits: {cpu: "1", memory: 1Gi}}
EOF
```

## DynamoDB Local tasks

<details>
<summary>Task 13.4.1 — Make the seed Job idempotent and re-runnable, and wire it into the dev workflow.</summary>

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: dynamodb-seed
  namespace: dev-deps
  labels: {app: dynamodb-seed, task: seed}
spec:
  backoffLimit: 3
  activeDeadlineSeconds: 600
  ttlSecondsAfterFinished: 86400
  template:
    metadata: {labels: {app: dynamodb-seed, task: seed}}
    spec:
      restartPolicy: OnFailure
      initContainers:
        # ⭐ wait for the endpoint to actually serve, not just for the Pod to be Ready
        - name: wait
          image: curlimages/curl:8.10.1
          command:
            - sh
            - -c
            - |
              EP=http://dynamodb-local.dev-deps.svc.cluster.local:8000
              for i in $(seq 1 60); do
                code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 -XPOST "$EP" \
                  -H 'Content-Type: application/x-amz-json-1.0' \
                  -H 'X-Amz-Target: DynamoDB_20120810.ListTables' -d '{}')
                [ "$code" = 200 ] && { echo "dynamodb-local is serving"; exit 0; }
                echo "waiting ($i) — got $code"; sleep 3
              done
              echo "never came up"; exit 1
      containers:
        - name: seed
          image: amazon/aws-cli:2.22.0
          env:
            - {name: AWS_ACCESS_KEY_ID,     value: "local"}
            - {name: AWS_SECRET_ACCESS_KEY, value: "local"}
            - {name: AWS_DEFAULT_REGION,    value: "us-east-1"}
            - {name: EP, value: "http://dynamodb-local.dev-deps.svc.cluster.local:8000"}
            - {name: RESET, value: "false"}          # ⭐ set true to wipe first
          command: ["/bin/sh","-c"]
          args:
            - |
              set -euo pipefail

              # ── helper: create a table only if it doesn't exist ──
              ensure_table() {
                local name=$1 attrs=$2 keys=$3
                if aws dynamodb describe-table --endpoint-url $EP --table-name "$name" >/dev/null 2>&1; then
                  echo "   ⏭  $name already exists"
                  return 0
                fi
                aws dynamodb create-table --endpoint-url $EP \
                  --table-name "$name" --attribute-definitions $attrs \
                  --key-schema $keys --billing-mode PAY_PER_REQUEST >/dev/null
                aws dynamodb wait table-exists --endpoint-url $EP --table-name "$name" 2>/dev/null || true
                echo "   ✅ $name created"
              }

              # ── helper: idempotent put (a put with the same PK/SK is already idempotent) ──
              ensure_item() {
                local table=$1 pk=$2 sk=$3 rest=$4
                local existing
                existing=$(aws dynamodb get-item --endpoint-url $EP --table-name "$table" \
                  --key "{\"pk\":{\"S\":\"$pk\"},\"sk\":{\"S\":\"$sk\"}}" \
                  --query 'Item.name.S' --output text 2>/dev/null || echo "None")
                if [ "$existing" = "$rest" ]; then
                  echo "   ⏭  $table/$pk/$sk unchanged"
                else
                  aws dynamodb put-item --endpoint-url $EP --table-name "$table" --item "{
                    \"pk\":{\"S\":\"$pk\"},\"sk\":{\"S\":\"$sk\"},\"name\":{\"S\":\"$rest\"}}" >/dev/null
                  echo "   ✅ $table/$pk/$sk written"
                fi
              }

              if [ "$RESET" = "true" ]; then
                echo "▸ RESET=true — deleting all tables first"
                for t in $(aws dynamodb list-tables --endpoint-url $EP --query 'TableNames[]' --output text); do
                  aws dynamodb delete-table --endpoint-url $EP --table-name "$t" >/dev/null
                  echo "   🗑  deleted $t"
                done
                sleep 3
              fi

              echo "▸ tables"
              ensure_table products \
                'AttributeName=pk,AttributeType=S AttributeName=sk,AttributeType=S AttributeName=GSI1PK,AttributeType=S AttributeName=GSI1SK,AttributeType=S' \
                'AttributeName=pk,KeyType=HASH AttributeName=sk,KeyType=RANGE'
              ensure_table orders \
                'AttributeName=userId,AttributeType=S AttributeName=orderId,AttributeType=S' \
                'AttributeName=userId,KeyType=HASH AttributeName=orderId,KeyType=RANGE'
              ensure_table sessions \
                'AttributeName=sid,AttributeType=S' \
                'AttributeName=sid,KeyType=HASH'

              echo "▸ GSI on products"
              GSIS=$(aws dynamodb describe-table --endpoint-url $EP --table-name products \
                     --query 'Table.GlobalSecondaryIndexes[].IndexName' --output text 2>/dev/null || echo "")
              if echo "$GSIS" | grep -q byCategory; then
                echo "   ⏭  byCategory already exists"
              else
                aws dynamodb update-table --endpoint-url $EP --table-name products \
                  --attribute-definitions AttributeName=GSI1PK,AttributeType=S AttributeName=GSI1SK,AttributeType=S \
                  --global-secondary-index-updates '[{"Create":{"IndexName":"byCategory",
                     "KeySchema":[{"AttributeName":"GSI1PK","KeyType":"HASH"},{"AttributeName":"GSI1SK","KeyType":"RANGE"}],
                     "Projection":{"ProjectionType":"ALL"}}}]' >/dev/null
                echo "   ✅ byCategory created"
              fi

              echo "▸ seed data (idempotent)"
              for i in $(seq 1 20); do
                aws dynamodb put-item --endpoint-url $EP --table-name products --item "{
                  \"pk\":{\"S\":\"PRODUCT#$i\"},\"sk\":{\"S\":\"META\"},
                  \"name\":{\"S\":\"Product $i\"},\"price\":{\"N\":\"$((i*10)).99\"},
                  \"GSI1PK\":{\"S\":\"CATEGORY#widgets\"},\"GSI1SK\":{\"S\":\"$(printf '%03d' $i)\"}}" >/dev/null
              done
              echo "   ✅ 20 products"

              echo "▸ verify"
              aws dynamodb list-tables --endpoint-url $EP --output table
              for t in products orders sessions; do
                printf '   %-10s %s items\n' "$t" \
                  "$(aws dynamodb scan --endpoint-url $EP --table-name $t --select COUNT --query Count --output text)"
              done
              printf '   %-10s %s items via GSI\n' "byCategory" \
                "$(aws dynamodb query --endpoint-url $EP --table-name products --index-name byCategory \
                    --key-condition-expression 'GSI1PK = :c' \
                    --expression-attribute-values '{":c":{"S":"CATEGORY#widgets"}}' \
                    --select COUNT --query Count --output text)"
              echo "✅ seed complete"
          resources: {requests: {cpu: 100m, memory: 128Mi}, limits: {cpu: 500m, memory: 256Mi}}
```

**Make it re-runnable** — a Job name is immutable, so you must delete first:

```makefile
# Makefile
NS ?= dev-deps
EP  = http://dynamodb-local.$(NS).svc.cluster.local:8000

.PHONY: seed reset seed-logs
seed: ## (re-)create tables and seed data — idempotent
	kubectl delete job dynamodb-seed -n $(NS) --ignore-not-found --wait=true
	kubectl apply -f dynamodb/prod/dev-only.yaml
	kubectl wait --for=condition=complete job/dynamodb-seed -n $(NS) --timeout=300s
	kubectl logs -n $(NS) job/dynamodb-seed --tail=40

reset: ## wipe everything and re-seed
	kubectl delete job dynamodb-seed -n $(NS) --ignore-not-found --wait=true
	sed 's/{name: RESET, value: "false"}/{name: RESET, value: "true"}/' \
	    dynamodb/prod/dev-only.yaml | kubectl apply -f -
	kubectl wait --for=condition=complete job/dynamodb-seed -n $(NS) --timeout=300s
	kubectl logs -n $(NS) job/dynamodb-seed --tail=40

seed-logs:
	kubectl logs -n $(NS) job/dynamodb-seed --tail=100 -f
```

```bash
make seed     # first run → creates everything
make seed     # second run → every step reports "⏭ already exists"
make reset    # wipes and rebuilds
```

Second-run output — the proof of idempotence:

```
▸ tables
   ⏭  products already exists
   ⏭  orders already exists
   ⏭  sessions already exists
▸ GSI on products
   ⏭  byCategory already exists
▸ seed data (idempotent)
   ✅ 20 products
▸ verify
   products   20 items
   orders     0 items
   sessions   0 items
   byCategory 20 items via GSI
✅ seed complete
```

**Wire it into the dev workflow** — a `postStart` on the Deployment would re-seed on every restart (bad: it races with readiness). Use the Job + a `make` target, or a Helm hook:

```yaml
metadata:
  annotations:
    "helm.sh/hook": post-install,post-upgrade
    "helm.sh/hook-weight": "5"
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
```

Now `helm upgrade dev-deps ./chart` seeds automatically after every deploy.

**Or better: seed from your integration tests,** so the data always matches what the code expects:

```python
# tests/conftest.py
import boto3, os, pytest

@pytest.fixture(scope="session")
def ddb():
    return boto3.resource("dynamodb",
        endpoint_url=os.environ["AWS_ENDPOINT_URL_DYNAMODB"],
        region_name="us-east-1",
        aws_access_key_id="local", aws_secret_access_key="local")

@pytest.fixture(scope="session", autouse=True)
def seeded(ddb):
    for name, schema in TABLES.items():
        try: ddb.create_table(TableName=name, **schema)
        except ddb.meta.client.exceptions.ResourceInUseException: pass
    ddb.Table("products").put_item(Item={"pk":"PRODUCT#1","sk":"META","name":"Widget"})
    yield
    # no teardown — the data is useful for the next run
```

</details>

<details>
<summary>Task 13.4.2 — Your tests pass against DynamoDB Local but fail in production. Find the six things the emulator doesn't do.</summary>

### 1. TTL doesn't work

```bash
aws dynamodb update-time-to-live --endpoint-url http://localhost:8000 \
  --table-name sessions --time-to-live-specification Enabled=true,AttributeName=expiresAt
# An error occurred (ValidationException) when calling the UpdateTimeToLive operation:
#   TTL is not supported by DynamoDB Local
```

Or it silently "succeeds" and never expires anything. Your test asserts the item disappears after 60 s — locally it never does, and in production your test *would* fail because TTL deletion takes **up to 48 hours** (usually minutes, but not guaranteed).

**Fix:** never test TTL by waiting. Test that the attribute is *set*:

```python
item = table.get_item(Key={"sid": "abc"})["Item"]
assert item["expiresAt"] == expected_epoch      # ✅ tests YOUR code
# assert "abc" not in table.scan()["Items"]     # ⛔ tests AWS's behaviour, slowly and flakily
```

And design so TTL is a *cleanup*, not correctness — always filter on `expiresAt` in your queries too:

```python
table.query(KeyConditionExpression=Key("pk").eq(pk) & Key("sk").begins_with("SESSION#"),
            FilterExpression=Attr("expiresAt").gt(int(time.time())))
```

### 2. Streams don't exist

```bash
aws dynamodb describe-stream --endpoint-url http://localhost:8000 --stream-arn …
# ResourceNotFoundException
```

Anything triggered by a DynamoDB Stream (a Lambda, a consumer Pod, a CDC pipeline) is **completely untested**.

**Fix:** unit-test the stream *handler* with hand-built records:

```python
def make_stream_record(event_name, new_image, old_image=None):
    return {"Records": [{
        "eventID": "1", "eventName": event_name,
        "dynamodb": {"Keys": {"pk": {"S": "P#1"}},
                     "NewImage": new_image, "OldImage": old_image,
                     "SequenceNumber": "111", "SizeBytes": 42,
                     "StreamViewType": "NEW_AND_OLD_IMAGES"},
        "eventSourceARN": "arn:aws:dynamodb:…:stream/…",
        "eventSource": "aws:dynamodb"}]}

def test_handler_on_insert():
    handler(make_stream_record("INSERT", {"pk": {"S": "P#1"}, "name": {"S": "W"}}), None)
    assert side_effect_happened()
```

### 3. Throttling never happens

DynamoDB Local has no capacity model. `ProvisionedThroughputExceededException` and `RequestLimitExceeded` **never occur**, so your retry/backoff code has zero coverage.

```python
# ⛔ never exercised locally
@retry(retry=retry_if_exception_type(client.exceptions.ProvisionedThroughputExceededException),
       stop=stop_after_attempt(5), wait=wait_exponential_jitter(initial=0.1, max=5))
def put(item): table.put_item(Item=item)
```

**Fix:** inject the exception in tests:

```python
def test_put_retries_on_throttle(mocker):
    exc = client.exceptions.ProvisionedThroughputExceededException(
        {"Error": {"Code": "ProvisionedThroughputExceededException"}}, "throttled")
    mock = mocker.patch.object(table, "put_item", side_effect=[exc, exc, {"ResponseMetadata": {}}])
    put({"pk": "1"})
    assert mock.call_count == 3       # ✅ retried twice then succeeded
```

Also test the *on-demand* burst behaviour: new tables start at ~50% of the previous peak capacity. A cold table under a traffic spike throttles hard in production.

### 4. Consistency semantics differ

```python
# ⛔ eventually-consistent read right after a write
table.put_item(Item={"pk": "1", "v": "new"})
assert table.get_item(Key={"pk": "1"})["Item"]["v"] == "new"   # passes locally, flaky in prod
```

DynamoDB Local is effectively strongly consistent (single SQLite). Real DynamoDB's default `GetItem` is **eventually consistent** and can return stale data for a few hundred milliseconds.

**Fix:** always specify:

```python
table.get_item(Key={"pk": "1"}, ConsistentRead=True)     # ✅ explicit, works in both
```

And **write tests that expect staleness** where you don't use `ConsistentRead`:

```python
def test_list_may_be_stale():
    # documents the tradeoff: this endpoint is eventually consistent by design
    resp = api.list_products()          # no ConsistentRead
    assert resp.status_code == 200      # we assert availability, not freshness
```

### 5. Index and item limits aren't enforced

| Limit | Real DynamoDB | Local |
|---|---|---|
| Item size | 400 KB | Not enforced |
| GSI count per table | 20 | Not enforced |
| LSI count | 5 | Not enforced |
| Expression length | 4 KB | Not enforced |
| `BatchWriteItem` | 25 items / 16 MB | Not enforced |
| `TransactWriteItems` | 100 items | Partial |
| `Query` page size | 1 MB | Not enforced |

```python
# ⛔ passes locally, fails in production
table.put_item(Item={"pk": "1", "blob": "x" * 500_000})
# ValidationException: Item size has exceeded the maximum allowed size of 400KB
```

**Fix:** enforce it yourself, in code and in tests:

```python
MAX_ITEM_BYTES = 400 * 1024

def size_of(item: dict) -> int:
    return len(dynamodb_json.dumps(item).encode())

def put(item):
    n = size_of(item)
    if n > MAX_ITEM_BYTES:
        raise ItemTooLargeError(f"{n} bytes > {MAX_ITEM_BYTES}")
    table.put_item(Item=item)

def test_rejects_oversized_item():
    with pytest.raises(ItemTooLargeError):
        put({"pk": "1", "blob": "x" * 500_000})
```

**Pagination is the classic one.** `Query` returns at most 1 MB per page and sets `LastEvaluatedKey`. Locally your 50-item test fits in one page; in production a 5,000-item result needs 20 pages.

```python
# ⛔ silently truncates in production
def list_products(pk): return table.query(KeyConditionExpression=Key("pk").eq(pk))["Items"]

# ✅ handles pagination
def list_products(pk):
    items, kwargs = [], {"KeyConditionExpression": Key("pk").eq(pk)}
    while True:
        resp = table.query(**kwargs)
        items.extend(resp["Items"])
        lek = resp.get("LastEvaluatedKey")
        if not lek: return items
        kwargs["ExclusiveStartKey"] = lek
```

Write a test with **more than 1 MB of data** so pagination is actually exercised.

### 6. Transactions are partial and semantics differ

```python
table.meta.client.transact_write_items(TransactItems=[…])
# DynamoDB Local supports basic transact_write_items, but:
#   - idempotency tokens behave differently
#   - TransactionCanceledException reasons are less specific
#   - conflict detection is weaker (single-writer SQLite)
```

The real service can cancel with reasons like `ConditionalCheckFailed`, `ItemCollectionSizeLimitExceeded`, `ProvisionedThroughputExceeded`, `TransactionConflict`, `ValidationError`. Locally you'll mostly see only the first.

**Fix:** test every cancellation reason explicitly:

```python
@pytest.mark.parametrize("reason", [
    "ConditionalCheckFailed", "TransactionConflict",
    "ProvisionedThroughputExceeded", "ValidationError"])
def test_handles_cancel_reason(reason, mocker):
    exc = client.exceptions.TransactionCanceledException(
        {"Error": {"Code": "TransactionCanceledException"},
         "CancellationReasons": [{"Code": reason}]}, "canceled")
    mocker.patch.object(client, "transact_write_items", side_effect=exc)
    with pytest.raises(DomainError) as e: transfer(a, b, 10)
    assert e.value.retryable is (reason == "TransactionConflict")
```

### Bonus divergences

| Behaviour | Local | Real |
|---|---|---|
| Empty-string attribute values | Allowed inconsistently | Allowed since 2020, but check |
| `Number` precision | Float-ish in some paths | Arbitrary precision decimal |
| Binary set ordering | Varies | Varies |
| Error message text | Different | Don't assert on message text — assert on **code** |
| `ConsumedCapacity` | Often absent | Present when requested |
| Tagging / PITR / encryption | Absent | Present |
| Latency | Sub-millisecond | 5–30 ms typical |

### The mitigation strategy

```
┌────────────────────────────────────────────────────────┐
│ 1. Unit tests           — no DynamoDB at all. Mocks.    │
│ 2. Integration tests    — DynamoDB Local or Alternativa │
│    (logic, keys, expressions, pagination)               │
│ 3. Contract tests       — assert on error CODES, never  │
│    messages; assert on YOUR limits (400 KB) not AWS's   │
│ 4. E2E in a dev account — REAL DynamoDB, a dev table.   │
│    Run nightly. This is where TTL/streams/throttling    │
│    get caught.                                          │
│ 5. Production           — real DynamoDB + canary        │
└────────────────────────────────────────────────────────┘
```

```yaml
# the nightly real-DynamoDB job
- name: integration-real-dynamodb
  runs-on: ubuntu-24.04
  if: github.event_name == 'schedule'
  permissions: {id-token: write, contents: read}
  steps:
    - uses: actions/checkout@v4
    - uses: aws-actions/configure-aws-credentials@v4
      with:
        role-to-assume: arn:aws:iam::123456789012:role/gha-ci-dynamodb-dev
        aws-region: ap-south-1
    - run: |
        export TABLE_PREFIX="ci-${GITHUB_RUN_ID}"
        pytest tests/real_dynamodb -m "realaws" -v --tb=short
      env: {AWS_REGION: ap-south-1}
    - if: always()
      run: |
        for t in $(aws dynamodb list-tables --query "TableNames[?starts_with(@,'ci-${GITHUB_RUN_ID}')]" --output text); do
          aws dynamodb delete-table --table-name $t
        done
```

**And a canary in production:**

```python
# a CronJob every 5 minutes that does a real write+read+delete
def canary():
    key = {"pk": "CANARY", "sk": str(int(time.time()))}
    table.put_item(Item={**key, "v": "ok", "expiresAt": int(time.time()) + 600})
    got = table.get_item(Key=key, ConsistentRead=True)["Item"]
    assert got["v"] == "ok"
    table.delete_item(Key=key)
    metrics.incr("dynamodb.canary.success")
```

```yaml
- alert: DynamoDBCanaryFailing
  expr: increase(dynamodb_canary_success_total[15m]) < 2
  for: 5m
  labels: {severity: critical}
  annotations: {summary: "The DynamoDB canary has not succeeded 2+ times in 15m"}
```

</details>

---
---

# 13.5 — Cassandra 4.1

**Cassandra is the best-fit database on this list for Kubernetes.** It's peer-to-peer (no leader to elect), designed to lose nodes, and its StatefulSet mapping is almost perfect: ordinal → node identity, headless Service → gossip address, one PVC → one data directory.

## 🔵 Case 1 — single node (8 minutes)

```bash
mkdir -p ~/k8s-learn/p13/cassandra && cd ~/k8s-learn/p13
```

`cassandra/simple.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata: {name: cassandra, labels: {app: cassandra}}
spec:
  replicas: 1
  selector: {matchLabels: {app: cassandra}}
  strategy: {type: Recreate}
  template:
    metadata: {labels: {app: cassandra}}
    spec:
      terminationGracePeriodSeconds: 1800     # ⭐ nodetool drain can take a long time
      containers:
        - name: cassandra
          image: cassandra:4.1
          ports:
            - {name: intra,     containerPort: 7000}
            - {name: tls,       containerPort: 7001}
            - {name: jmx,       containerPort: 7199}
            - {name: cql,       containerPort: 9042}
          env:
            - {name: CASSANDRA_CLUSTER_NAME,   value: "learn"}
            - {name: CASSANDRA_DC,             value: "dc1"}
            - {name: CASSANDRA_RACK,           value: "rack1"}
            - {name: CASSANDRA_SEEDS,          value: "cassandra.default.svc.cluster.local"}
            - {name: CASSANDRA_ENDPOINT_SNITCH, value: "GossipingPropertyFileSnitch"}
            - {name: MAX_HEAP_SIZE,            value: "512M"}     # ⭐ explicit — see below
            - {name: HEAP_NEWSIZE,             value: "128M"}
            - {name: CASSANDRA_AUTO_BOOTSTRAP, value: "false"}    # ⭐ single node only
            - {name: POD_IP, valueFrom: {fieldRef: {fieldPath: status.podIP}}}
          readinessProbe:
            exec:
              # ⭐ `nodetool status` says UP even while bootstrapping/joining.
              #    A real CQL query is the only trustworthy readiness signal.
              command: ["cqlsh","-e","SELECT now() FROM system.local"]
            initialDelaySeconds: 60
            periodSeconds: 20
            timeoutSeconds: 15
            failureThreshold: 30           # Cassandra takes 2-5 minutes to start
          livenessProbe:
            exec: {command: ["nodetool","status"]}
            initialDelaySeconds: 240
            periodSeconds: 60
            timeoutSeconds: 20
            failureThreshold: 5
          resources:
            requests: {cpu: 500m, memory: 1536Mi}
            limits:   {cpu: "2",   memory: 2Gi}
          volumeMounts:
            - {name: data, mountPath: /var/lib/cassandra}
      volumes:
        - {name: data, emptyDir: {sizeLimit: 5Gi}}
---
apiVersion: v1
kind: Service
metadata: {name: cassandra}
spec:
  selector: {app: cassandra}
  ports:
    - {name: cql,   port: 9042}
    - {name: intra, port: 7000}
```

```bash
kubectl apply -f cassandra/simple.yaml
kubectl get pods -l app=cassandra -w          # ⏳ 2-5 minutes. Be patient.
kubectl logs deploy/cassandra --tail=30 | grep -iE 'starting|listening|bootstrap'
```

```
INFO  [main] CassandraDaemon.java:708 - Startup complete
INFO  [main] CassandraDaemon.java:724 - Node localhost/10.244.1.12 state jump to NORMAL
```

```bash
kubectl exec -it deploy/cassandra -- cqlsh -e "
  DESCRIBE CLUSTER;
  SELECT release_version FROM system.local;
  DESCRIBE KEYSPACES;"

kubectl exec -it deploy/cassandra -- nodetool status
```

```
Datacenter: dc1
=======================
Status=Up/Down
|/ State=Normal/Leaving/Joining/Moving
--  Address      Load       Tokens  Owns    Host ID                               Rack
UN  10.244.1.12  104.21 KiB  16     100.0%  8f1a…                                 rack1
```

```bash
kubectl exec -it deploy/cassandra -- cqlsh -e "
  CREATE KEYSPACE shop WITH replication = {
    'class': 'NetworkTopologyStrategy', 'dc1': 1};

  CREATE TABLE shop.products (
    category text,
    product_id timeuuid,
    name text,
    price decimal,
    created_at timestamp,
    PRIMARY KEY ((category), product_id)
  ) WITH CLUSTERING ORDER BY (product_id DESC);

  INSERT INTO shop.products (category, product_id, name, price, created_at)
  VALUES ('widgets', now(), 'Widget', 9.99, toTimestamp(now()));

  SELECT * FROM shop.products;
  DESCRIBE shop.products;"
```

## 🟢 Case 2 — a 3-node cluster StatefulSet with rack awareness (45 minutes)

**The Kubernetes↔Cassandra mapping:**

| Cassandra concept | Kubernetes primitive |
|---|---|
| Node identity (host_id) | StatefulSet ordinal + stable DNS |
| Seed nodes | `cassandra-0.cassandra.db.svc` (+ 1 more) |
| Gossip address | The Pod's own DNS name (`publishNotReadyAddresses`) |
| Rack / DC | `topology.kubernetes.io/zone` → `cassandra-rackdc.properties` |
| Data directory | `volumeClaimTemplates` |
| Snitch | `GossipingPropertyFileSnitch` (always, in K8s) |
| Rolling restart | StatefulSet `RollingUpdate` + a readiness gate |

`cassandra/prod/01-statefulset.yaml`:

```yaml
apiVersion: v1
kind: Namespace
metadata: {name: db}
---
apiVersion: v1
kind: ConfigMap
metadata: {name: cassandra-config, namespace: db}
data:
  # ── cassandra.yaml overrides ──
  cassandra.yaml: |
    cluster_name: 'shop-cluster'
    num_tokens: 16                    # ⭐ vnodes. 16 is the 4.x recommendation (was 256)
    hinted_handoff_enabled: true
    max_hint_window_in_ms: 10800000
    hinted_handoff_throttle_in_kb: 1024
    max_hints_delivery_threads: 2
    batchlog_replay_throttle_in_kb: 1024
    authenticator: PasswordAuthenticator        # ⭐ not AllowAllAuthenticator
    authorizer: CassandraAuthorizer
    role_manager: CassandraRoleManager
    partitioner: org.apache.cassandra.dht.Murmur3Partitioner
    disk_optimization_strategy: ssd             # ⭐ if your StorageClass is SSD
    concurrent_reads: 32
    concurrent_writes: 32
    concurrent_counter_writes: 32
    memtable_allocation_type: heap_buffers
    index_summary_resize_interval_in_minutes: 60
    storage_port: 7000
    ssl_storage_port: 7001
    listen_on_broadcast_address: false
    start_native_transport: true
    native_transport_port: 9042
    native_transport_max_threads: 128
    native_transport_max_frame_size_in_mb: 256
    rpc_server_type: sync
    endpoint_snitch: GossipingPropertyFileSnitch   # ⭐ ALWAYS this in Kubernetes
    server_encryption_options:
      internode_encryption: all                 # ⭐ encrypt node-to-node
      keystore: /etc/cassandra/keystore
      keystore_password: __KEYSTORE_PASSWORD__
      truststore: /etc/cassandra/truststore
      truststore_password: __TRUSTSTORE_PASSWORD__
      require_client_auth: true
      protocol: TLS
      algorithm: SunX509
      store_type: JKS
    client_encryption_options:
      enabled: true                             # ⭐ encrypt client→node
      optional: false
      keystore: /etc/cassandra/keystore
      keystore_password: __KEYSTORE_PASSWORD__
      require_client_auth: true
    commitlog_sync: periodic
    commitlog_sync_period_in_ms: 10000
    commitlog_segment_size_in_mb: 32
    seed_provider:
      - class_name: org.apache.cassandra.locator.SimpleSeedProvider
        parameters:
          # ⭐ DNS names of the FIRST TWO ordinals. Not all three — see the note.
          - seeds: "cassandra-0.cassandra.db.svc.cluster.local,cassandra-1.cassandra.db.svc.cluster.local"
    auto_bootstrap: true                        # ⭐ true for a real cluster
    enable_user_defined_functions: false
    enable_scripted_user_defined_functions: false
    windows_timer_interval: 1
    transparent_data_encryption_options:
      enabled: false
    audit_logging_options:
      enabled: true
      logger: BinAuditLogger
      included_categories: AUTH, DML, DCL
    compaction_throughput_mb_per_sec: 64
    sstable_preemptive_open_interval_in_mb: 50
    read_request_timeout_in_ms: 10000
    range_request_timeout_in_ms: 20000
    write_request_timeout_in_ms: 5000
    counter_write_request_timeout_in_ms: 10000
    cas_contention_timeout_in_ms: 2000
    truncate_request_timeout_in_ms: 60000
    request_timeout_in_ms: 20000
    cross_node_timeout: true
    phi_convict_threshold: 12                   # ⭐ raise for container networks (default 8 is too twitchy)
    gc_warn_threshold_in_ms: 1000
    back_pressure_enabled: false
    prepared_statements_cache_size_mb: 64
    counter_cache_size_in_mb: 50
    slow_query_log_timeout_in_ms: 500
    otc_coalescing_strategy: DISABLED
  # ── the snitch config, generated per-Pod by an init container ──
  cassandra-rackdc.properties.template: |
    dc=${CASSANDRA_DC}
    rack=${CASSANDRA_RACK}
    prefer_local=true
    # dc_suffix=
  ---
  jvm.options: |
    # ── heap: NEVER more than 50% of the container limit, and never > 8-16 GB ──
    # ⭐ Cassandra 4 supports -XX:MaxRAMPercentage and reads the cgroup.
    -XX:+UseContainerSupport
    -XX:MaxRAMPercentage=50.0
    -XX:InitialRAMPercentage=50.0
    -XX:+UseG1GC
    -XX:G1RSetUpdatingPauseTimePercent=5
    -XX:MaxGCPauseMillis=500
    -XX:InitiatingHeapOccupancyPercent=70
    -XX:ParallelGCThreads=4                     # ⭐ match the CPU limit, not the node's cores
    -XX:ConcGCThreads=1
    -XX:+ExplicitGCInvokesConcurrent
    -XX:+AlwaysPreTouch
    -XX:-UseBiasedLocking
    -XX:+UseTLAB
    -XX:+ResizeTLAB
    -XX:+UseNUMA
    -Djava.net.preferIPv4Stack=true
    -XX:+HeapDumpOnOutOfMemoryError
    -XX:HeapDumpPath=/var/lib/cassandra/heapdump.hprof
    -XX:ErrorFile=/var/lib/cassandra/hs_err_%p.log
    -Djdk.attach.allowAttachSelf=true
---
apiVersion: v1
kind: Secret
metadata: {name: cassandra-creds, namespace: db}
stringData:
  superuser: cassandra
  superuser-password: "Cass-Pr0d-Super!-K8"
  app-user: shop
  app-password: "Cass-Pr0d-App!-K8x"
  KEYSTORE_PASSWORD: "kspw1"
  TRUSTSTORE_PASSWORD: "tspw1"
---
# ⭐ HEADLESS with publishNotReadyAddresses — gossip needs to reach bootstrapping nodes
apiVersion: v1
kind: Service
metadata:
  name: cassandra
  namespace: db
  labels: {app: cassandra}
spec:
  clusterIP: None
  publishNotReadyAddresses: true       # ⭐ CRITICAL for Cassandra
  selector: {app: cassandra}
  ports:
    - {name: cql,   port: 9042}
    - {name: intra, port: 7000}
    - {name: tls,   port: 7001}
    - {name: jmx,   port: 7199}
---
apiVersion: v1
kind: ServiceAccount
metadata: {name: cassandra, namespace: db}
automountServiceAccountToken: false
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: cassandra
  namespace: db
  labels: {app: cassandra}
spec:
  serviceName: cassandra
  replicas: 3
  # ⭐ OrderedReady: cassandra-0 must be UP and NORMAL before cassandra-1
  #    bootstraps. Parallel bootstrapping multiple nodes causes token conflicts.
  podManagementPolicy: OrderedReady
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      partition: 0
      # ⭐ maxUnavailable is always 1 for StatefulSets — Kubernetes will not
      #    restart the next Pod until this one is Ready. That's exactly right
      #    for Cassandra: never take down two nodes at once.
  selector: {matchLabels: {app: cassandra}}
  template:
    metadata:
      labels: {app: cassandra}
      annotations:
        checksum/config: REPLACE_WITH_SHA
    spec:
      serviceAccountName: cassandra
      terminationGracePeriodSeconds: 1800   # ⭐ 30 minutes. `nodetool drain` + flush is slow.
      securityContext:
        fsGroup: 999
        runAsUser: 999
        runAsGroup: 999
        runAsNonRoot: true
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            - labelSelector: {matchLabels: {app: cassandra}}
              topologyKey: kubernetes.io/hostname
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: DoNotSchedule     # ⭐ strict: one node per zone
          labelSelector: {matchLabels: {app: cassandra}}

      initContainers:
        # ── 1. generate the rack config from the NODE's zone label ──
        - name: init-rack
          image: busybox:1.37
          command:
            - sh
            - -c
            - |
              set -eu
              # ⭐ the rack = the Kubernetes zone. This is what makes Cassandra
              #    spread replicas across failure domains automatically.
              ZONE=$(cat /node-info/zone 2>/dev/null || echo "rack1")
              DC=${CASSANDRA_DC:-dc1}
              # sanitise: Cassandra racks can't contain some characters
              RACK=$(echo "$ZONE" | tr '/.' '--' | cut -c1-32)

              sed -e "s/\${CASSANDRA_DC}/$DC/" -e "s/\${CASSANDRA_RACK}/$RACK/" \
                  /tmpl/cassandra-rackdc.properties.template \
                  > /out/cassandra-rackdc.properties

              echo "pod=$HOSTNAME dc=$DC rack=$RACK (zone=$ZONE)"
          env:
            - {name: CASSANDRA_DC, value: "dc1"}
            # ⭐ the Downward API can't read NODE labels directly — use a mounted
            #    fieldRef for the node name, then look it up. Simpler: use the
            #    topology label via a projected volume from the node (not possible),
            #    so we read it from the Pod's own env set by a mutating webhook,
            #    OR just derive it from the node name pattern.
            - name: NODE_NAME
              valueFrom: {fieldRef: {fieldPath: spec.nodeName}}
          securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: ["ALL"]}}
          resources: {requests: {cpu: 10m, memory: 16Mi}, limits: {cpu: 100m, memory: 64Mi}}
          volumeMounts:
            - {name: rack-tmpl, mountPath: /tmpl, readOnly: true}
            - {name: config,    mountPath: /out}
            - {name: node-info, mountPath: /node-info, readOnly: true}

        # ── 2. fetch the node's zone label (needs API access) ──
        - name: fetch-node-zone
          image: bitnami/kubectl:1.33
          command:
            - sh
            - -c
            - |
              NODE=$(cat /etc/podinfo/nodename)
              ZONE=$(kubectl get node "$NODE" -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}' 2>/dev/null || echo "")
              [ -z "$ZONE" ] && ZONE=$(kubectl get node "$NODE" -o jsonpath='{.metadata.labels.failure-domain\.beta\.kubernetes\.io/zone}' 2>/dev/null || echo "rack1")
              echo -n "$ZONE" > /node-info/zone
              echo "node=$NODE zone=$ZONE"
          env:
            - name: NODE_NAME
              valueFrom: {fieldRef: {fieldPath: spec.nodeName}}
          volumeMounts:
            - {name: podinfo,   mountPath: /etc/podinfo, readOnly: true}
            - {name: node-info, mountPath: /node-info}
          resources: {requests: {cpu: 20m, memory: 32Mi}, limits: {cpu: 200m, memory: 128Mi}}

        # ── 3. verify the data directory is sane ──
        - name: check-data
          image: busybox:1.37
          command:
            - sh
            - -c
            - |
              set -eu
              mkdir -p /var/lib/cassandra/data /var/lib/cassandra/commitlog \
                       /var/lib/cassandra/saved_caches /var/lib/cassandra/hints
              chown -R 999:999 /var/lib/cassandra || true
              df -h /var/lib/cassandra
              # ⭐ if the volume is >85% full, Cassandra will refuse writes.
              #    Fail loudly HERE, not at 3am.
              USE=$(df -P /var/lib/cassandra | awk 'NR==2 {gsub("%","",$5); print $5}')
              if [ "$USE" -gt 85 ]; then
                echo "⛔ data volume is ${USE}% full — Cassandra needs compaction headroom"
                exit 1
              fi
              echo "data dir ok (${USE}% used)"
          securityContext: {runAsUser: 0}
          volumeMounts: [{name: data, mountPath: /var/lib/cassandra}]
          resources: {requests: {cpu: 10m, memory: 16Mi}, limits: {cpu: 100m, memory: 64Mi}}

        # ── 4. wait for the seeds before bootstrapping (ordinals > 0) ──
        - name: wait-for-seeds
          image: cassandra:4.1
          command:
            - bash
            - -c
            - |
              set -eu
              ORDINAL="${HOSTNAME##*-}"
              [ "$ORDINAL" = "0" ] && { echo "I am seed cassandra-0; nothing to wait for"; exit 0; }
              SVC="cassandra.db.svc.cluster.local"
              for seed in cassandra-0.$SVC cassandra-1.$SVC; do
                echo "waiting for seed $seed"
                for i in $(seq 1 300); do
                  if cqlsh "$seed" -u cassandra -p "$CASSANDRA_SUPER_PW" \
                       -e "SELECT release_version FROM system.local" >/dev/null 2>&1; then
                    echo "  ✅ $seed is serving CQL"
                    # also confirm it's NORMAL, not bootstrapping
                    STATE=$(nodetool -h "$seed" -u cassandra -pw "$CASSANDRA_SUPER_PW" status \
                            | awk -v s="$seed" '$0 ~ s {print substr($1,2)}' | head -1)
                    echo "  state: $STATE"
                    break
                  fi
                  [ $i -eq 300 ] && { echo "⛔ seed $seed never came up"; exit 1; }
                  sleep 3
                done
              done
          env:
            - {name: CASSANDRA_SUPER_PW, valueFrom: {secretKeyRef: {name: cassandra-creds, key: superuser-password}}}
          securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: ["ALL"]}}
          resources: {requests: {cpu: 100m, memory: 256Mi}, limits: {cpu: 500m, memory: 512Mi}}
          volumeMounts: [{name: config, mountPath: /etc/cassandra-extra, readOnly: true}]

      containers:
        - name: cassandra
          image: cassandra:4.1
          ports:
            - {name: cql,   containerPort: 9042}
            - {name: intra, containerPort: 7000}
            - {name: tls,   containerPort: 7001}
            - {name: jmx,   containerPort: 7199}
          securityContext:
            allowPrivilegeEscalation: false
            capabilities: {drop: ["ALL"]}
          env:
            - {name: CASSANDRA_CLUSTER_NAME,     value: "shop-cluster"}
            - {name: CASSANDRA_DC,               value: "dc1"}
            - {name: CASSANDRA_SEEDS,            value: "cassandra-0.cassandra.db.svc.cluster.local,cassandra-1.cassandra.db.svc.cluster.local"}
            - {name: CASSANDRA_ENDPOINT_SNITCH,  value: "GossipingPropertyFileSnitch"}
            - {name: CASSANDRA_AUTO_BOOTSTRAP,   value: "true"}
            # ⭐ advertise MY OWN stable DNS name, not the Pod IP.
            #    Pod IPs change on restart; DNS names don't. Without this,
            #    Cassandra stores the IP in system.local and the cluster
            #    loses the node permanently after a reschedule.
            - name: CASSANDRA_BROADCAST_ADDRESS
              valueFrom: {fieldRef: {fieldPath: metadata.name}}
            - {name: POD_IP,       valueFrom: {fieldRef: {fieldPath: status.podIP}}}
            - {name: POD_NAME,     valueFrom: {fieldRef: {fieldPath: metadata.name}}}
            - {name: NODE_NAME,    valueFrom: {fieldRef: {fieldPath: spec.nodeName}}}
            - {name: CASSANDRA_SUPER_USER, valueFrom: {secretKeyRef: {name: cassandra-creds, key: superuser}}}
            - {name: CASSANDRA_SUPER_PW,   valueFrom: {secretKeyRef: {name: cassandra-creds, key: superuser-password}}}
            - {name: JVM_EXTRA_OPTS, value: >-
                -Dcassandra.broadcast_address=$(POD_NAME).cassandra.db.svc.cluster.local
                -Dcassandra.listen_address=$(POD_IP)
                -Dcassandra.ring_delay_ms=30000
                -Dcassandra.consistent_range_movement=true
                -Dcom.sun.management.jmxremote.port=7199
                -Dcom.sun.management.jmxremote.rmi.port=7199
                -Dcom.sun.management.jmxremote.authenticate=false
                -Dcom.sun.management.jmxremote.ssl=false
                -Djava.rmi.server.hostname=$(POD_IP)}
          readinessProbe:
            exec:
              command:
                - bash
                - -c
                - |
                  set -eu
                  # 1. CQL actually answers
                  cqlsh -u "$CASSANDRA_SUPER_USER" -p "$CASSANDRA_SUPER_PW" \
                    -e "SELECT now() FROM system.local" >/dev/null || exit 1
                  # 2. this node is NORMAL (not bootstrapping/leaving/moving)
                  STATE=$(nodetool status | awk -v ip="$POD_IP" '$0 ~ ip {print substr($1,2)}')
                  [ "$STATE" = "N" ] || { echo "state=$STATE (not Normal)"; exit 1; }
                  # 3. no ongoing compaction backlog beyond the threshold
                  PENDING=$(nodetool compactionstats -H 2>/dev/null | awk '/pending tasks/{print $NF}' || echo 0)
                  [ "${PENDING:-0}" -lt 20 ] || { echo "compaction backlog $PENDING"; exit 1; }
                  # 4. gossip sees the whole ring
                  UP=$(nodetool status | grep -c '^UN' || true)
                  [ "$UP" -ge 2 ] || { echo "only $UP nodes UN"; exit 1; }
            initialDelaySeconds: 120
            periodSeconds: 30
            timeoutSeconds: 25          # ⭐ nodetool is SLOW. 5s will always fail.
            failureThreshold: 6
            successThreshold: 1
          livenessProbe:
            exec:
              command: ["bash","-c","nodetool status | grep -q \"$POD_IP\" || exit 1"]
            initialDelaySeconds: 600     # ⭐ 10 minutes. Cassandra bootstrapping can take a while.
            periodSeconds: 120
            timeoutSeconds: 30
            failureThreshold: 5
          lifecycle:
            preStop:
              exec:
                command:
                  - bash
                  - -c
                  - |
                    set -x
                    # ⭐ THE most important part of Cassandra on Kubernetes.
                    # drain = flush memtables to SSTables, stop accepting writes,
                    #         close the native transport, and leave gossip cleanly.
                    # Without it, the next boot replays the commit log (minutes)
                    # and other nodes see a hard failure (hinted handoff storm).
                    nodetool disablebinary || true
                    nodetool disablethrift 2>/dev/null || true
                    sleep 10                       # let clients notice
                    nodetool drain || true
                    sleep 5
          resources:
            requests: {cpu: "1",   memory: 4Gi, ephemeral-storage: 10Gi}
            limits:   {cpu: "4",   memory: 8Gi}      # ⭐ heap = 50% = 4 Gi
          volumeMounts:
            - {name: data,   mountPath: /var/lib/cassandra}
            - {name: config, mountPath: /etc/cassandra-extra, readOnly: true}
            - {name: tmp,    mountPath: /tmp}

      volumes:
        - {name: config,    emptyDir: {}}
        - {name: tmp,       emptyDir: {sizeLimit: 1Gi}}
        - {name: node-info, emptyDir: {}}
        - {name: rack-tmpl, configMap: {name: cassandra-config, items: [{key: cassandra-rackdc.properties.template, path: cassandra-rackdc.properties.template}]}}
        - name: podinfo
          downwardAPI:
            items:
              - {path: "nodename", fieldRef: {fieldPath: spec.nodeName}}
              - {path: "labels",   fieldRef: {fieldPath: metadata.labels}}

  volumeClaimTemplates:
    - metadata: {name: data, labels: {app: cassandra}}
      spec:
        accessModes: [ReadWriteOnce]
        # ⭐ Cassandra needs 50% free for compaction. Size for 2× your data.
        resources: {requests: {storage: 100Gi}}
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata: {name: cassandra, namespace: db}
spec:
  # ⭐ With RF=3, losing 2 nodes means losing quorum for QUORUM reads/writes.
  #    minAvailable: 2 keeps a majority.
  minAvailable: 2
  selector: {matchLabels: {app: cassandra}}
```

```bash
kubectl apply -f cassandra/prod/01-statefulset.yaml
kubectl get pods -n db -l app=cassandra -w
```

```
cassandra-0   0/1   Init:0/4        …
cassandra-0   0/1   Init:3/4        …
cassandra-0   0/1   PodInitializing …
cassandra-0   0/1   Running         …      ← ⏳ 3-6 minutes to NORMAL
cassandra-0   1/1   Running         …
cassandra-1   0/1   Init:0/4        …      ← only starts AFTER cassandra-0 is Ready
cassandra-1   1/1   Running         …
cassandra-2   1/1   Running         …
```

**`OrderedReady` is doing real work here.** With `Parallel`, all three would bootstrap simultaneously, race for tokens, and you'd get an inconsistent ring.

```bash
kubectl exec -n db cassandra-0 -- nodetool status
```

```
Datacenter: dc1
=======================
Status=Up/Down
|/ State=Normal/Leaving/Joining/Moving
--  Address       Load        Tokens  Owns (effective)  Host ID                               Rack
UN  10.244.1.21   284.12 KiB  16      66.2%             a1b2…                                 us-east-1a
UN  10.244.2.18   271.44 KiB  16      67.1%             c3d4…                                 us-east-1b
UN  10.244.3.14   268.91 KiB  16      66.7%             e5f6…                                 us-east-1c
```

**Three zones, one node each — that's the rack awareness working.**

```bash
kubectl exec -n db cassandra-0 -- nodetool describering system_auth
kubectl exec -n db cassandra-0 -- cqlsh -u cassandra -p'Cass-Pr0d-Super!-K8' -e "
  -- ⭐ system keyspaces default to RF=1. Fix that FIRST, or you have no HA for auth.
  ALTER KEYSPACE system_auth WITH replication = {'class':'NetworkTopologyStrategy','dc1':3};
  ALTER KEYSPACE system_distributed WITH replication = {'class':'NetworkTopologyStrategy','dc1':3};
  ALTER KEYSPACE system_traces WITH replication = {'class':'NetworkTopologyStrategy','dc1':3};

  CREATE KEYSPACE IF NOT EXISTS shop WITH replication =
    {'class':'NetworkTopologyStrategy','dc1':3} AND durable_writes = true;

  CREATE ROLE IF NOT EXISTS shop WITH PASSWORD = 'Cass-Pr0d-App!-K8x'
    AND LOGIN = true AND OPTIONS = {'custom_options':{}};
  GRANT SELECT, MODIFY ON KEYSPACE shop TO shop;

  CREATE TABLE IF NOT EXISTS shop.events (
    partition_key text,
    event_time    timeuuid,
    event_type    text,
    payload       text,
    PRIMARY KEY ((partition_key), event_time)
  ) WITH CLUSTERING ORDER BY (event_time DESC)
    AND compaction = {'class':'TimeWindowCompactionStrategy',
                      'compaction_window_interval':1,'compaction_window_unit':'DAYS'}
    AND default_time_to_live = 2592000
    AND gc_grace_seconds = 864000;

  DESCRIBE KEYSPACE shop;"
```

**Verify replication across zones:**

```bash
kubectl exec -n db cassandra-0 -- cqlsh -u shop -p'Cass-Pr0d-App!-K8x' -k shop -e "
  INSERT INTO events (partition_key, event_time, event_type, payload)
  VALUES ('user:42', now(), 'login', '{\"ip\":\"1.2.3.4\"}');
  INSERT INTO events (partition_key, event_time, event_type, payload)
  VALUES ('user:42', now(), 'purchase', '{\"amount\":9.99}');"

# read from EACH node — all three must have it
for i in 0 1 2; do
  echo -n "cassandra-$i: "
  kubectl exec -n db cassandra-$i -- cqlsh -u shop -p'Cass-Pr0d-App!-K8x' -k shop \
    -e "SELECT count(*) FROM events WHERE partition_key='user:42';" 2>/dev/null | grep -A1 count | tail -1
done
# cassandra-0:  2
# cassandra-1:  2
# cassandra-2:  2      ← ✅ RF=3 replicated
```

**Kill a node and watch Cassandra do what it was designed to do:**

```bash
kubectl delete pod -n db cassandra-1 --wait=false
kubectl exec -n db cassandra-0 -- nodetool status
```

```
UN  10.244.1.21   284.12 KiB  16   66.2%   a1b2…   us-east-1a
DN  10.244.2.18   271.44 KiB  16   67.1%   c3d4…   us-east-1b     ← ⛔ DOWN
UN  10.244.3.14   268.91 KiB  16   66.7%   e5f6…   us-east-1c
```

```bash
# reads and writes at CL=QUORUM still work — 2 of 3 is a majority
kubectl exec -n db cassandra-0 -- cqlsh -u shop -p'…' -k shop -e "
  INSERT INTO events (partition_key, event_time, event_type, payload)
  VALUES ('user:43', now(), 'during-outage', '{}') USING CONSISTENCY QUORUM;
  SELECT * FROM events WHERE partition_key='user:42' LIMIT 10 CONSISTENCY QUORUM;"
# ✅ both succeed

# at CL=ALL they fail
kubectl exec -n db cassandra-0 -- cqlsh -u shop -p'…' -k shop -e "
  SELECT * FROM events WHERE partition_key='user:42' CONSISTENCY ALL;" 2>&1 | head -3
# CassandraUnavailableException: Cannot achieve consistency level ALL
```

**That's the whole point of Cassandra.** Two of three nodes → quorum reads and writes keep working with zero intervention. Compare MySQL (manual promotion) and MongoDB (10 s election).

```bash
kubectl get pods -n db -l app=cassandra -w     # cassandra-1 comes back
kubectl exec -n db cassandra-0 -- nodetool status    # all UN again
kubectl exec -n db cassandra-1 -- nodetool status    # it rejoined with the SAME host_id
```

### ⭐ The `broadcast_address` problem — and why it's the #1 Cassandra-on-K8s bug

Cassandra stores each node's address in `system.local` and `system.peers`. If it stores the **Pod IP**, then when the Pod restarts with a new IP, the cluster has a permanent ghost node that never comes back:

```bash
kubectl exec -n db cassandra-0 -- nodetool status
UN  10.244.1.21   …   us-east-1a
DN  10.244.2.99   …   us-east-1b     ← ⛔ this IP no longer exists. The real Pod is 10.244.2.201.
UN  10.244.3.14   …   us-east-1c
```

`nodetool removenode` fixes it, but it triggers a full data stream to the remaining nodes — hours on a big cluster.

**The fix** (already in the manifest above):

```yaml
- name: CASSANDRA_BROADCAST_ADDRESS
  valueFrom: {fieldRef: {fieldPath: metadata.name}}
- {name: JVM_EXTRA_OPTS, value: >-
    -Dcassandra.broadcast_address=$(POD_NAME).cassandra.db.svc.cluster.local
    -Dcassandra.listen_address=$(POD_IP)}
```

| Setting | Value | Why |
|---|---|---|
| `listen_address` | The **Pod IP** | The actual socket to bind. DNS names don't bind. |
| `broadcast_address` | The **stable DNS name** | What other nodes gossip about. Survives restarts. |
| `rpc_address` | `0.0.0.0` | Accept CQL from anywhere in the Pod network |
| `broadcast_rpc_address` | The **DNS name** | What clients are told to connect to |

```bash
kubectl exec -n db cassandra-0 -- cqlsh -u cassandra -p'…' -e "
  SELECT broadcast_address, listen_address, rpc_address FROM system.local;"
```

```
broadcast_address | listen_address | rpc_address
cassandra-0.cassandra.db.svc.cluster.local | 10.244.1.21 | 0.0.0.0
```

✅ DNS name in `broadcast_address`, IP in `listen_address`. That's correct.

## Cassandra tasks

<details>
<summary>Task 13.5.1 — Size the Cassandra heap correctly and prove GC isn't hurting you.</summary>

### The heap rule

**Cassandra's heap must be ~50% of the container limit, and never more than 8–16 GB.**

Why not more? Because Cassandra relies heavily on the **OS page cache** for SSTable reads. Give the JVM everything and the page cache gets nothing — reads go to disk instead of RAM.

```
container limits.memory   8 Gi
JVM heap (50%)            4 Gi     ← MaxRAMPercentage=50
OS page cache             ~3.5 Gi  ← SSTable reads served from RAM
JVM off-heap + overhead   ~0.5 Gi  ← direct buffers, thread stacks, metaspace
```

```bash
# verify what's actually configured
kubectl exec -n db cassandra-0 -- bash -c '
  echo "── container limit ──"; cat /sys/fs/cgroup/memory.max 2>/dev/null || cat /sys/fs/cgroup/memory/memory.limit_in_bytes
  echo "── JVM flags ──";      ps -ef | grep -o "\-Xmx[^ ]*\|\-Xms[^ ]*\|MaxRAMPercentage=[^ ]*" | sort -u
  echo "── actual heap ──";    nodetool info | grep -i heap
  echo "── off-heap ──";       nodetool netstats -H | head -5'
```

```
── container limit ──
8589934592                                  (8 Gi)
── JVM flags ──
-XX:MaxRAMPercentage=50.0
-XX:InitialRAMPercentage=50.0
── actual heap ──
Heap Memory (MB)       : 4096.00 / 4096.00
Off Heap Memory (MB)   : 1024.00
```

✅ 4 Gi heap in an 8 Gi container.

### Measure GC

```bash
kubectl exec -n db cassandra-0 -- nodetool tpstats
kubectl exec -n db cassandra-0 -- bash -c 'jstat -gcutil $(pgrep -f CassandraDaemon) 2000 10'
```

```
  S0     S1     E      O      M     CCS    YGC     YGCT     FGC    FGCT     CGC    CGCT      GCT
  0.00  42.11  68.44  41.20  96.12  93.88  12841   84.212     2    1.842     412    8.214   94.268
  0.00  42.11  88.10  41.25  96.12  93.88  12842   84.218     2    1.842     412    8.214   94.274
  0.00  42.11  12.88  41.31  96.12  93.88  12843   84.224     2    1.842     412    8.214   94.280
```

| Column | Meaning | Healthy |
|---|---|---|
| `E` | Eden usage % | Fluctuates 0→100 rapidly — that's normal |
| `O` | **Old gen usage %** | ⭐ Should stay **below 70–80%**. Climbing toward 100% = a leak or too-small heap |
| `YGC/YGCT` | Young GC count / total seconds | **YGCT/YGC < 50 ms** average |
| `FGC/FGCT` | **Full GC count / seconds** | ⭐ **FGC should be 0 or near-0.** Each is a multi-second stop-the-world |
| `CGC/CGCT` | Concurrent GC (G1) | Should be frequent but short |

```bash
# the average pause per GC
kubectl exec -n db cassandra-0 -- bash -c '
  jstat -gc $(pgrep -f CassandraDaemon) | awk "NR==2 {printf \"YGC=%d YGCT=%.2fs avg=%.1fms  FGC=%d FGCT=%.2fs\n\", \$13, \$14, \$14/\$13*1000, \$15, \$16}"'
# YGC=12843 YGCT=84.22s avg=6.6ms  FGC=2 FGCT=1.84s       ← ✅ excellent
```

**From Prometheus** (via `jmx_exporter` or `cassandra-exporter`):

```promql
# GC pause rate
rate(jvm_gc_collection_seconds_sum{quantile="0.99"}[5m])

# the alert that matters
jvm_gc_pause_seconds_max{gc="G1 Old Generation"} > 1
```

```yaml
- alert: CassandraFullGC
  expr: increase(jvm_gc_collection_seconds_count{gc=~".*Old.*|.*MarkSweep.*"}[10m]) > 0
  for: 0m
  labels: {severity: critical}
  annotations:
    summary: "{{ $labels.pod }} did a Full GC in the last 10m"
    description: "Full GCs are stop-the-world pauses of seconds. Check heap size, large partitions, and tombstones."

- alert: CassandraHeapPressure
  expr: jvm_memory_bytes_used{area="heap"} / jvm_memory_bytes_max{area="heap"} > 0.85
  for: 10m
  labels: {severity: warning}
  annotations: {summary: "{{ $labels.pod }} heap above 85% for 10m"}
```

### What to do about it

**Full GCs happening → in order of likelihood:**

1. **Large partitions.** A single partition with 100k+ rows must be fully materialised in memory for some queries.
   ```sql
   -- find them
   SELECT * FROM system.size_estimates WHERE keyspace_name='shop';
   -- or use the built-in big-partition warning
   ```
   ```bash
   kubectl exec -n db cassandra-0 -- bash -c \
     'grep -i "large partition\|big partition" /var/log/cassandra/*.log | tail'
   # WARN  [ReadRepairStage] BigPartitionLogger.java:78 - Big partition detected
   #   (shop.events:partition_key=user:9999) size=128410221 bytes
   ```
   **Fix:** redesign the schema. Split the partition key. This is a *schema* problem, not a heap problem.

2. **Tombstone storms.** Millions of deleted/expired cells held in memory during a read.
   ```bash
   kubectl exec -n db cassandra-0 -- bash -c \
     'grep -c "tombstone" /var/log/cassandra/*.log'
   # Read 1284102 live rows and 4821033 tombstone cells for query …
   ```
   **Fix:** shorter `gc_grace_seconds` where safe, more frequent compaction (TWCS helps), and stop deleting by writing tombstones — use TTL instead.

3. **Heap genuinely too small.** Raise `MaxRAMPercentage` to 60% and the container limit accordingly. Never above ~16 Gi heap — GC pause times grow with heap size.

4. **`AlwaysPreTouch` is off.** Without it the JVM commits pages lazily and takes page faults under load.

5. **Unbounded queries.** `SELECT * FROM shop.events` with no partition key loads the entire table.
   ```bash
   kubectl exec -n db cassandra-0 -- cqlsh -u cassandra -p'…' -e \
     "SELECT * FROM system_traces.sessions LIMIT 1;"   # and check for ALLOW FILTERING abuse
   ```

### The tuning checklist

```yaml
# jvm.options
-XX:+UseContainerSupport          # read the cgroup, not the node
-XX:MaxRAMPercentage=50.0         # 50% of the container limit
-XX:InitialRAMPercentage=50.0     # Xms == Xmx: never resize the heap at runtime
-XX:+UseG1GC                      # the 4.x default; better pause behaviour
-XX:MaxGCPauseMillis=500
-XX:InitiatingHeapOccupancyPercent=70
-XX:ParallelGCThreads=4           # ⭐ == the CPU LIMIT, not the node's cores
-XX:ConcGCThreads=1
-XX:+AlwaysPreTouch               # commit the heap up front
-XX:+HeapDumpOnOutOfMemoryError
-XX:HeapDumpPath=/var/lib/cassandra/heapdump.hprof
```

⚠️ **`ParallelGCThreads` defaults to the node's core count.** On a 64-core node with a 4-CPU limit, the JVM spawns 64 GC threads competing for 4 CPUs — GC pauses get *worse*, not better. Set it explicitly.

```bash
kubectl exec -n db cassandra-0 -- bash -c \
  'java -XX:+PrintFlagsFinal -version 2>/dev/null | grep -E "ParallelGCThreads|ConcGCThreads|MaxHeapSize|UseG1GC"'
#      uintx ParallelGCThreads                       = 4                 {product}
#      uintx ConcGCThreads                           = 1                 {product}
#     uint64 MaxHeapSize                            = 4294967296         {product}
#       bool UseG1GC                                 = true              {product}
```

**And the memory limit itself:**

```bash
kubectl top pod -n db cassandra-0
# cassandra-0   2841m   5412Mi      ← heap 4 Gi + page cache + off-heap

kubectl exec -n db cassandra-0 -- cat /sys/fs/cgroup/memory.stat | grep -E '^(anon|file|slab|sock) '
# anon 4512841216      ← the JVM heap + off-heap
# file  842103296      ← page cache (reclaimable)
# slab   41203712
```

`limits.memory: 8Gi` with 5.4 Gi actual → comfortable. If `anon` alone approaches the limit, you'll be OOMKilled regardless of what the heap is set to.

</details>

<details>
<summary>Task 13.5.2 — Replace a failed Cassandra node whose PV is gone, without losing data.</summary>

The scenario: `cassandra-1` is `DN`, its node was deleted, and the PVC can't reattach (zoned volume, node gone). The data is on 2 of 3 replicas, so nothing is lost — but you need a new node to join and stream.

### Step 1 — confirm the state

```bash
kubectl get pods -n db -l app=cassandra -o wide
# cassandra-0   1/1   Running   …   learn-worker
# cassandra-1   0/1   Pending   …   <none>          ← ⛔ unschedulable
# cassandra-2   1/1   Running   …   learn-worker2

kubectl describe pod -n db cassandra-1 | grep -A6 Events
# 0/3 nodes are available: 2 node(s) didn't match PersistentVolume's node affinity,
#   1 node(s) had untolerated taint {node.kubernetes.io/unreachable: }.

kubectl exec -n db cassandra-0 -- nodetool status
# UN  10.244.1.21   284.12 KiB  16  66.2%  a1b2…  us-east-1a
# DN  10.244.2.18   271.44 KiB  16  67.1%  c3d4…  us-east-1b    ← the dead one
# UN  10.244.3.14   268.91 KiB  16  66.7%  e5f6…  us-east-1c

kubectl exec -n db cassandra-0 -- nodetool describecluster
# Schema versions:
#   a7b2…: [cassandra-0.cassandra…, cassandra-2.cassandra…]
#   UNREACHABLE: [cassandra-1.cassandra…]

# is quorum still available?
kubectl exec -n db cassandra-0 -- cqlsh -u shop -p'…' -k shop -e \
  "SELECT count(*) FROM events WHERE partition_key='user:42' CONSISTENCY QUORUM;"
# ✅ works — 2 of 3 is a majority
```

### Step 2 — decide: repair-and-rejoin, or replace?

| Situation | Action |
|---|---|
| The PV can reattach (node comes back, same zone) | Just let the Pod start; it rejoins with the same `host_id` and streams the delta |
| The PV is gone but the node can be recreated in the same zone | **`-Dcassandra.replace_address_first_boot`** — the fast path |
| The zone is gone entirely | Remove the node, add a new one in another zone, and re-tune rack awareness |
| Data is critically inconsistent | Repair first, then replace |

We'll do the standard **replace** flow.

### Step 3 — remove the dead node from the ring (if it won't come back)

```bash
# find the host_id of the dead node
kubectl exec -n db cassandra-0 -- nodetool status | grep '^DN'
# DN  10.244.2.18   271.44 KiB  16  67.1%  c3d4e5f6-…  us-east-1b

HOST_ID=c3d4e5f6-…

kubectl exec -n db cassandra-0 -- nodetool removenode $HOST_ID
kubectl exec -n db cassandra-0 -- nodetool removenode status
# c3d4e5f6-… : 42.1% complete
```

⚠️ **`removenode` streams the dead node's token ranges to the survivors.** That's real I/O — on a 100 GiB node it takes 30–60 minutes and can saturate disk. **Do it during low traffic.** Monitor:

```bash
watch -n5 'kubectl exec -n db cassandra-0 -- nodetool removenode status; \
           kubectl exec -n db cassandra-0 -- nodetool netstats'
```

If it stalls:

```bash
kubectl exec -n db cassandra-0 -- nodetool removenode force    # last resort; leaves the ring inconsistent until you repair
```

### Step 4 — clean up the Kubernetes objects

```bash
# delete the orphaned PVC and Pod
kubectl delete pvc -n db data-cassandra-1 --wait=false
kubectl delete pod -n db cassandra-1 --force --grace-period=0
kubectl get pv | grep cassandra-1
kubectl delete pv <the Released one>
```

### Step 5 — bring up the replacement

**Option A — same ordinal, fresh PVC (simplest with a StatefulSet):**

```bash
# the StatefulSet controller recreates cassandra-1 and its PVC automatically.
# But a fresh node will BOOTSTRAP (stream all its data from the ring),
# which is correct and safe — just slow.
kubectl get pods -n db -l app=cassandra -w
# cassandra-1   0/1   Init:0/4 → … → 1/1 Running      (5-40 min depending on data size)

kubectl exec -n db cassandra-0 -- nodetool status
# UN  10.244.1.21   …   us-east-1a
# UJ  10.244.2.201  …   us-east-1b     ← Joining, streaming
# UN  10.244.3.14   …   us-east-1c

kubectl exec -n db cassandra-1 -- nodetool netstats
# Bootstrap 42.1%  streaming from cassandra-0 …
```

**Option B — replace a specific host_id (faster when the old node was DN and already removed):**

```yaml
# add to the StatefulSet for ordinal 1 only, via a one-off Pod override
env:
  - name: JVM_EXTRA_OPTS
    value: >-
      -Dcassandra.replace_address_first_boot=10.244.2.18
      -Dcassandra.broadcast_address=cassandra-1.cassandra.db.svc.cluster.local
```

`replace_address_first_boot` tells Cassandra: "I am the node that used to be at this address — take over its tokens and stream its data, don't allocate new ones." **It must be removed after the first successful boot** or the node will try to replace itself on every restart.

With a StatefulSet you can't set per-ordinal env vars directly, so:

```bash
# scale down to 0, patch, scale back up — or run a one-off Pod with the same identity
kubectl scale sts/cassandra -n db --replicas=1        # keeps cassandra-0 only
# … then run the replacement as a manual Pod with the StatefulSet's DNS name …
```

**In practice, Option A (plain bootstrap) is almost always right.** It's simpler, self-healing, and the streaming cost is the same.

### Step 6 — repair

New nodes join with the data they streamed, but **hinted handoff and any inconsistency from the outage needs a repair**:

```bash
# ⭐ NEVER run a full-cluster repair casually. It's the most expensive operation
#    Cassandra has. Do it per-keyspace, per-table, and staggered.

# what's overdue?
kubectl exec -n db cassandra-0 -- cqlsh -u cassandra -p'…' -e \
  "SELECT keyspace_name, columnfamily_name, last_repaired_at FROM system_distributed.repair_history
   ORDER BY last_repaired_at ASC LIMIT 20;"

# repair one keyspace, in parallel, with intensity control
kubectl exec -n db cassandra-0 -- nodetool repair -par -jmx shop -full
```

Better: **Reaper** — the standard tool for scheduled, segmented repairs:

```bash
helm repo add datastax https://datastax.github.io/public-charts
helm install reaper datastax/reaper-operator -n reaper --create-namespace
```

```yaml
apiVersion: reaper.cassandra.io/v1alpha1
kind: CassandraReaper
metadata: {name: shop-reaper, namespace: db}
spec:
  image: thelastpickle/cassandra-reaper:3.7.0
  serverConfig:
    storageType: cassandra
    cassandraKeyspace: reaper_db
    autoScheduling:
      enabled: true
      initialDelayPeriod: PT2M
      periodBetweenPolls: PT10M
      timeBeforeFirstSchedule: PT5M
      scheduleSpreadPeriod: PT6H
      excludedKeyspaces: [system, system_auth, system_distributed, system_traces]
  cassandraService:
    name: cassandra
    port: 9042
```

Reaper splits the repair into small segments, runs them continuously, tracks history, and never lets `gc_grace_seconds` expire on unrepaired data. **This is what you use in production.**

### Step 7 — verify

```bash
kubectl exec -n db cassandra-0 -- nodetool status
# UN  …  us-east-1a
# UN  …  us-east-1b        ← ✅ back, NORMAL
# UN  …  us-east-1c

kubectl exec -n db cassandra-0 -- nodetool describecluster | grep -A4 'Schema versions'
# a7b2…: [cassandra-0…, cassandra-1…, cassandra-2…]    ← ✅ all three on the same schema

kubectl exec -n db cassandra-0 -- nodetool gossipinfo | grep -c 'generation'
# 3

# CL=ALL works again
kubectl exec -n db cassandra-0 -- cqlsh -u shop -p'…' -k shop -e \
  "SELECT count(*) FROM events WHERE partition_key='user:42' CONSISTENCY ALL;"
# ✅

# data integrity
for i in 0 1 2; do
  printf 'cassandra-%d: ' $i
  kubectl exec -n db cassandra-$i -- cqlsh -u shop -p'…' -k shop \
    -e "SELECT count(*) FROM events;" 2>/dev/null | grep -A1 count | tail -1
done
# all three must agree
```

### Step 8 — the post-mortem checklist

- [ ] Why did the node die? (OOMKilled? node failure? PV detach? `kubectl describe` + `kubectl get events`)
- [ ] Was `gc_grace_seconds` at risk? (If a node is down longer than `gc_grace_seconds` — default 10 days — tombstones resurrect and you get deleted data back. **Replace within that window.**)
- [ ] Did any client see `UNAVAILABLE` errors? (Check your app logs for consistency-level failures)
- [ ] Is the PDB right? (`minAvailable: 2` with RF=3 → only one node can be down)
- [ ] Is rack awareness actually spreading across zones? (`nodetool status` rack column)
- [ ] Are `system_auth`/`system_distributed`/`system_traces` at RF=3? (They default to RF=1 — **this is the most-missed Cassandra config**, and it means losing one node can break authentication cluster-wide)
- [ ] Is Reaper running repairs on schedule?
- [ ] Do your alerts fire on `DN` nodes? (`cassandra_endpoint_active{}` or a `nodetool status` sidecar)

```yaml
- alert: CassandraNodeDown
  expr: cassandra_endpoint_active == 0
  for: 2m
  labels: {severity: critical}
  annotations: {summary: "Cassandra node {{ $labels.address }} is DOWN"}

- alert: CassandraSchemaDisagreement
  expr: count(count by (schema_version) (cassandra_gossip_schema_versions)) > 1
  for: 10m
  labels: {severity: warning}
  annotations: {summary: "The Cassandra cluster has more than one schema version — a migration is stuck"}

- alert: CassandraRepairOverdue
  expr: time() - cassandra_table_last_repaired_timestamp > (10 * 86400)
  for: 1h
  labels: {severity: critical}
  annotations:
    summary: "{{ $labels.keyspace }}.{{ $labels.table }} has not been repaired in 10 days"
    description: "gc_grace_seconds is about to expire. Unrepaired tombstones WILL resurrect deleted data."

- alert: CassandraDiskNearFull
  expr: kubelet_volume_stats_used_bytes{persistentvolumeclaim=~"data-cassandra.*"}
        / kubelet_volume_stats_capacity_bytes > 0.75
  for: 15m
  labels: {severity: warning}
  annotations:
    summary: "{{ $labels.persistentvolumeclaim }} is {{ $value | humanizePercentage }} full"
    description: "Cassandra refuses writes above ~90% (disk_failure_policy). Compaction needs 50% headroom."
```

</details>

---
---

# 13.6 — Neo4j 5.26 (Community)

## 🔵 Case 1 — one Pod with a PVC (8 minutes)

```bash
mkdir -p ~/k8s-learn/p13/neo4j && cd ~/k8s-learn/p13
```

`neo4j/simple.yaml`:

```yaml
apiVersion: v1
kind: Secret
metadata: {name: neo4j-creds}
stringData:
  NEO4J_AUTH: "neo4j/N304j-Learn-K8s!"      # ⭐ the format is user/password, literally with a slash
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: neo4j-data}
spec:
  accessModes: [ReadWriteOnce]
  resources: {requests: {storage: 10Gi}}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: neo4j, labels: {app: neo4j}}
spec:
  replicas: 1
  selector: {matchLabels: {app: neo4j}}
  strategy: {type: Recreate}
  template:
    metadata: {labels: {app: neo4j}}
    spec:
      terminationGracePeriodSeconds: 120
      containers:
        - name: neo4j
          image: neo4j:5.26-community
          ports:
            - {name: http,  containerPort: 7474}
            - {name: bolt,  containerPort: 7687}
            - {name: https, containerPort: 7473}
            - {name: backup, containerPort: 6362}
          envFrom: [{secretRef: {name: neo4j-creds}}]
          env:
            # ⭐ Neo4j's image translates NEO4J_<setting> env vars into neo4j.conf entries.
            #    Underscores become dots; double underscores become dashes.
            - {name: NEO4J_server_memory_heap_initial__size, value: "512m"}
            - {name: NEO4J_server_memory_heap_max__size,     value: "1g"}
            - {name: NEO4J_server_memory_pagecache_size,     value: "512m"}
            - {name: NEO4J_dbms_connector_bolt_advertised__address, value: "localhost:7687"}
            - {name: NEO4J_server_default__listen__address,  value: "0.0.0.0"}
            - {name: NEO4J_db_tx__log_rotation_retention__policy, value: "size"}
            - {name: NEO4J_db_tx__log_rotation_size,         value: "128M"}
            - {name: NEO4J_dbms_security_procedures_unrestricted, value: "apoc.*"}
            - {name: NEO4J_server_logs_query_enabled,        value: "true"}
            - {name: NEO4J_server_logs_query_threshold,      value: "1s"}
          readinessProbe:
            httpGet: {path: /, port: http}         # ⭐ 200 once the web server is up
            initialDelaySeconds: 30
            periodSeconds: 10
            failureThreshold: 30
          livenessProbe:
            tcpSocket: {port: bolt}                 # ⭐ the Bolt port is the real service
            initialDelaySeconds: 90
            periodSeconds: 30
            failureThreshold: 5
          resources:
            requests: {cpu: 500m, memory: 2Gi}
            limits:   {cpu: "2",   memory: 3Gi}     # ⭐ heap 1g + pagecache 512m + overhead
          volumeMounts:
            - {name: data,   mountPath: /data}
            - {name: logs,   mountPath: /logs}
            - {name: plugins, mountPath: /plugins}
            - {name: import, mountPath: /var/lib/neo4j/import}
      volumes:
        - {name: data,   persistentVolumeClaim: {claimName: neo4j-data}}
        - {name: logs,   emptyDir: {}}
        - {name: plugins, emptyDir: {}}
        - {name: import, emptyDir: {}}
---
apiVersion: v1
kind: Service
metadata: {name: neo4j}
spec:
  selector: {app: neo4j}
  ports:
    - {name: http, port: 7474}
    - {name: bolt, port: 7687}
```

> ⚠️ **`NEO4J_dbms_connector_bolt_advertised__address: localhost:7687`** is what makes `kubectl port-forward` work with the browser. Without it, Neo4j advertises its Pod IP and the browser can't reach it. In Case 2 you advertise the Service DNS name instead.

```bash
kubectl apply -f neo4j/simple.yaml
kubectl rollout status deploy/neo4j --timeout=300s      # Neo4j is slow to boot
kubectl logs deploy/neo4j --tail=20 | grep -iE 'started|remote interface|bolt'
```

```
2026-09-09 16:02:14.842+0000 INFO  Started.
2026-09-09 16:02:15.104+0000 INFO  Remote interface available at http://localhost:7474/
2026-09-09 16:02:15.106+0000 INFO  id: …
```

```bash
kubectl port-forward svc/neo4j 7474:7474 7687:7687 &
sleep 3
# browser → http://localhost:7474   (neo4j / N304j-Learn-K8s!)

# or via cypher-shell
kubectl exec -it deploy/neo4j -- cypher-shell -u neo4j -p'N304j-Learn-K8s!' "
  CREATE (a:Product {name:'Widget', price:9.99})-[:BELONGS_TO]->(c:Category {name:'Tools'});
  MATCH (p:Product)-[:BELONGS_TO]->(c:Category) RETURN p.name, c.name;
  CALL db.labels() YIELD label RETURN collect(label);
  CALL db.schema.visualization();"
```

```
╒══════════╤══════════╕
│"p.name"  │"c.name"  │
╞══════════╪══════════╡
│"Widget"  │"Tools"   │
└──────────┴──────────┘
```

## 🟢 Case 2 — the honest production story (35 minutes)

**Read this first: Neo4j Community Edition cannot be clustered.**

| | Community | Enterprise |
|---|---|---|
| Instances | **1** | Unlimited |
| Causal Clustering (read replicas) | ❌ | ✅ |
| Fabric / multi-DB sharding | ❌ | ✅ |
| Online backup | ❌ (`neo4j-admin database dump` only, offline-ish) | ✅ (`neo4j-admin backup`, online) |
| Role-based security | Basic | Full |
| Hot config reload | ❌ | ✅ |
| Licence | GPLv3 | Commercial |

So the "production" Case 2 for Community is really: **a single, well-tuned, well-backed-up, carefully-upgraded instance** — plus the Enterprise clustering config for reference.

### `neo4j/prod/01-standalone.yaml` — Community done properly

```yaml
apiVersion: v1
kind: Namespace
metadata: {name: db}
---
apiVersion: v1
kind: Secret
metadata: {name: neo4j-creds, namespace: db}
stringData:
  NEO4J_AUTH: "neo4j/N304j-Pr0d-K8s!-Zx"
---
apiVersion: v1
kind: ConfigMap
metadata: {name: neo4j-config, namespace: db}
data:
  neo4j.conf: |
    # ══════════════ MEMORY — the three numbers that matter ══════════════
    # heap: transaction state, query execution, object graph
    server.memory.heap.initial_size=2g
    server.memory.heap.max_size=2g                 # ⭐ initial == max. Never resize at runtime.

    # pagecache: graph data (nodes, relationships, properties) held in RAM.
    # THIS is what makes Neo4j fast. Size it to your graph.
    server.memory.pagecache.size=2g

    # ⚠️ heap + pagecache + JVM overhead MUST fit in the container limit.
    #    2g + 2g + ~1g overhead = 5g → limits.memory must be >= 6Gi

    server.memory.off_heap.max_cacheable_headroom=512m

    # ══════════════ NETWORK ══════════════
    server.default_listen_address=0.0.0.0
    server.bolt.listen_address=:7687
    server.http.listen_address=:7474
    server.https.listen_address=:7473
    server.backup.listen_address=:6362

    # ⭐ what the server TELLS clients to connect to. In Kubernetes this must be
    #    a name clients can resolve — the Service DNS name, not the Pod IP.
    server.bolt.advertised_address=neo4j.db.svc.cluster.local:7687
    server.http.advertised_address=neo4j.db.svc.cluster.local:7474

    server.bolt.tls_level=OPTIONAL
    server.https.enabled=false

    # ══════════════ SECURITY ══════════════
    dbms.security.auth_enabled=true
    dbms.security.allow_csv_import_from_file_urls=false
    server.directories.import=/var/lib/neo4j/import
    dbms.security.procedures.unrestricted=apoc.*
    dbms.security.procedures.allowlist=apoc.*
    # ⭐ disable the browser in production, or expose it behind auth + a VPN only
    server.http.enabled=true

    # ══════════════ DURABILITY ══════════════
    db.tx_log.rotation.retention_policy=7 days
    db.tx_log.rotation.size=256M
    db.tx_log.preallocate=true
    db.record_transaction.log.flush.threshold=10000

    # ══════════════ QUERY LOG — find your slow Cypher ══════════════
    server.logs.query.enabled=true
    server.logs.query.threshold=1s
    server.logs.query.runtime=PLAIN
    server.logs.query.parameter_logging_enabled=true
    server.logs.query.tracing=OFF

    # ══════════════ PERFORMANCE ══════════════
    db.tx_state.memory_allocation=ON_HEAP
    db.lock.acquisition.timeout=60s
    db.transaction.timeout=300s
    db.transaction.total.max=200
    dbms.threads.worker_count=8                    # ⭐ == CPU limit, not the node's cores
    server.threads.worker_count=8
    db.index.fulltext.eventually_consistent=true
    db.index_sampling.background_sample_size=1048576

    # ══════════════ GC ══════════════
    server.jvm.additional=-XX:+UseG1GC
    server.jvm.additional=-XX:MaxGCPauseMillis=200
    server.jvm.additional=-XX:InitiatingHeapOccupancyPercent=70
    server.jvm.additional=-XX:+AlwaysPreTouch
    server.jvm.additional=-XX:+HeapDumpOnOutOfMemoryError
    server.jvm.additional=-XX:HeapDumpPath=/logs/heapdump.hprof
    server.jvm.additional=-XX:ParallelGCThreads=8
    server.jvm.additional=-Dio.netty.tryReflectionSetAccessible=true
---
apiVersion: v1
kind: Service
metadata: {name: neo4j, namespace: db, labels: {app: neo4j}}
spec:
  clusterIP: None                    # ⭐ headless for stable DNS if you ever cluster
  selector: {app: neo4j}
  ports:
    - {name: bolt,   port: 7687}
    - {name: http,   port: 7474}
    - {name: backup, port: 6362}
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: neo4j
  namespace: db
  labels: {app: neo4j}
spec:
  serviceName: neo4j
  replicas: 1                        # ⭐ Community = 1. Full stop.
  updateStrategy: {type: OnDelete}   # ⭐ YOU control when Neo4j restarts. Never automatic.
  selector: {matchLabels: {app: neo4j}}
  template:
    metadata:
      labels: {app: neo4j}
      annotations:
        checksum/config: REPLACE_WITH_SHA
    spec:
      terminationGracePeriodSeconds: 300
      securityContext:
        fsGroup: 7474
        runAsUser: 7474
        runAsGroup: 7474
        runAsNonRoot: true
      initContainers:
        - name: init-perms
          image: busybox:1.37
          command: ["sh","-c","chown -R 7474:7474 /data /logs /plugins /import 2>/dev/null || true; mkdir -p /data /logs"]
          securityContext: {runAsUser: 0}
          volumeMounts:
            - {name: data,    mountPath: /data}
            - {name: logs,    mountPath: /logs}
            - {name: plugins, mountPath: /plugins}
            - {name: import,  mountPath: /import}
          resources: {requests: {cpu: 10m, memory: 16Mi}, limits: {cpu: 100m, memory: 64Mi}}

        # ⭐ download APOC at startup (the image has no network tools to bake it in)
        - name: fetch-plugins
          image: curlimages/curl:8.10.1
          command:
            - sh
            - -c
            - |
              set -eu
              APOC_VERSION=5.26.0
              URL="https://github.com/neo4j/apoc/releases/download/${APOC_VERSION}/apoc-${APOC_VERSION}-core.jar"
              if [ -f /plugins/apoc-core.jar ]; then
                echo "apoc already present"; exit 0
              fi
              echo "downloading apoc ${APOC_VERSION}"
              curl -fsSL --retry 3 --retry-delay 5 -o /plugins/apoc-core.jar "$URL" \
                || { echo "⚠️ apoc download failed — starting without it"; exit 0; }
              ls -lh /plugins/
          volumeMounts: [{name: plugins, mountPath: /plugins}]
          resources: {requests: {cpu: 50m, memory: 64Mi}, limits: {cpu: 500m, memory: 128Mi}}

        # ⭐ verify the last shutdown was clean. A dirty store needs recovery.
        - name: check-store
          image: neo4j:5.26-community
          command:
            - bash
            - -c
            - |
              set -eu
              if [ ! -d /data/databases/neo4j ]; then
                echo "fresh data directory"; exit 0
              fi
              echo "existing store found — checking integrity"
              neo4j-admin database check neo4j --expand-commands 2>&1 | tail -20 || {
                echo "⛔ store check FAILED. Do not start. Restore from backup."
                exit 1
              }
          securityContext: {runAsUser: 7474}
          volumeMounts:
            - {name: data,   mountPath: /data}
            - {name: config, mountPath: /var/lib/neo4j/conf-extra, readOnly: true}
          resources: {requests: {cpu: 200m, memory: 512Mi}, limits: {cpu: "1", memory: 2Gi}}

      containers:
        - name: neo4j
          image: neo4j:5.26-community
          ports:
            - {name: bolt,   containerPort: 7687}
            - {name: http,   containerPort: 7474}
            - {name: backup, containerPort: 6362}
          securityContext:
            allowPrivilegeEscalation: false
            capabilities: {drop: ["ALL"]}
          env:
            - {name: NEO4J_AUTH, valueFrom: {secretKeyRef: {name: neo4j-creds, key: NEO4J_AUTH}}}
            - {name: EXTENDED_CONF, value: "true"}    # ⭐ use the mounted neo4j.conf
            - {name: NEO4J_server_directories_logs, value: "/logs"}
            - {name: POD_NAME, valueFrom: {fieldRef: {fieldPath: metadata.name}}}
          readinessProbe:
            httpGet: {path: /, port: http}
            initialDelaySeconds: 60
            periodSeconds: 15
            timeoutSeconds: 10
            failureThreshold: 30           # ⭐ Neo4j can take 5+ minutes with a big pagecache
          livenessProbe:
            tcpSocket: {port: bolt}
            initialDelaySeconds: 300
            periodSeconds: 60
            timeoutSeconds: 10
            failureThreshold: 5
          lifecycle:
            preStop:
              exec:
                # ⭐ checkpoint on shutdown = a clean store = fast restart, no recovery
                command:
                  - bash
                  - -c
                  - |
                    cypher-shell -u neo4j -p "${NEO4J_AUTH#neo4j/}" \
                      "CALL db.checkpoint() YIELD success, message RETURN success, message;" 2>/dev/null || true
                    sleep 10
          resources:
            requests: {cpu: "1", memory: 5Gi, ephemeral-storage: 5Gi}
            limits:   {cpu: "4", memory: 6Gi}    # ⭐ heap 2g + pagecache 2g + ~1.5g overhead
          volumeMounts:
            - {name: data,    mountPath: /data}
            - {name: logs,    mountPath: /logs}
            - {name: plugins, mountPath: /plugins}
            - {name: import,  mountPath: /var/lib/neo4j/import}
            - {name: config,  mountPath: /var/lib/neo4j/conf/neo4j.conf, subPath: neo4j.conf, readOnly: true}

      volumes:
        - {name: config,  configMap: {name: neo4j-config}}
        - {name: logs,    emptyDir: {sizeLimit: 2Gi}}
        - {name: plugins, emptyDir: {sizeLimit: 512Mi}}
        - {name: import,  emptyDir: {sizeLimit: 5Gi}}

  volumeClaimTemplates:
    - metadata: {name: data, labels: {app: neo4j}}
      spec:
        accessModes: [ReadWriteOnce]
        resources: {requests: {storage: 50Gi}}
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata: {name: neo4j, namespace: db}
spec:
  minAvailable: 1                 # with 1 replica this blocks drains — deliberately
  selector: {matchLabels: {app: neo4j}}
```

**`updateStrategy: OnDelete` is a deliberate choice.** With `RollingUpdate`, a config change or an image bump restarts Neo4j automatically — during business hours, without a checkpoint, possibly mid-transaction. With `OnDelete`, *you* decide when:

```bash
kubectl set image sts/neo4j -n db neo4j=neo4j:5.27-community
# nothing happens. The Pod keeps running the old version.
kubectl get sts neo4j -n db -o jsonpath='{.status.updateRevision} vs {.status.currentRevision}'; echo

# when YOU are ready:
kubectl exec -n db neo4j-0 -- cypher-shell -u neo4j -p'…' "CALL db.checkpoint();"
kubectl delete pod -n db neo4j-0            # now it restarts with the new image
kubectl rollout status sts/neo4j -n db --timeout=600s
```

### Backups — Community's limitation and the workaround

```bash
# ⛔ `neo4j-admin backup` is ENTERPRISE ONLY
kubectl exec -n db neo4j-0 -- neo4j-admin backup --to-path=/tmp 2>&1 | head -3
# Unknown command: backup. See `neo4j-admin --help` for a list of available commands.

# ✅ Community: `neo4j-admin database dump` — requires the database to be STOPPED
```

```yaml
# neo4j/prod/02-backup-cronjob.yaml
apiVersion: batch/v1
kind: CronJob
metadata: {name: neo4j-backup, namespace: db}
spec:
  schedule: "0 3 * * *"
  timeZone: "Asia/Kolkata"
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 7
  jobTemplate:
    spec:
      backoffLimit: 1
      activeDeadlineSeconds: 7200
      ttlSecondsAfterFinished: 604800
      template:
        metadata: {labels: {app: neo4j-backup, task: backup}}
        spec:
          restartPolicy: Never
          containers:
            - name: backup
              image: neo4j:5.26-community
              command:
                - bash
                - -c
                - |
                  set -euo pipefail
                  STAMP=$(date -u +%Y%m%d-%H%M%S)
                  PW="${NEO4J_AUTH#neo4j/}"

                  echo "▸ 1. checkpoint so the dump is consistent"
                  cypher-shell -a bolt://neo4j.db.svc.cluster.local:7687 -u neo4j -p "$PW" \
                    "CALL db.checkpoint() YIELD success, message RETURN success, message;"

                  echo "▸ 2. ⚠️ stop the database (Community dump requires it)"
                  cypher-shell -a bolt://neo4j.db.svc.cluster.local:7687 -u neo4j -p "$PW" \
                    "STOP DATABASE neo4j;" || {
                      echo "STOP DATABASE needs Enterprise. Falling back to a cold dump."
                      echo "This means downtime — schedule it in a maintenance window."
                    }

                  echo "▸ 3. dump"
                  neo4j-admin database dump neo4j \
                    --to-path=/backup \
                    --overwrite-destination \
                    --expand-commands
                  ls -lh /backup/

                  echo "▸ 4. restart the database"
                  cypher-shell -a bolt://neo4j.db.svc.cluster.local:7687 -u neo4j -p "$PW" \
                    "START DATABASE neo4j;" || true

                  echo "▸ 5. verify the dump"
                  mkdir -p /verify
                  neo4j-admin database load neo4j --from-path=/backup --to-path=/verify --overwrite-destination
                  ls -lh /verify/neo4j/
                  du -sh /verify/neo4j/

                  echo "▸ 6. upload"
                  gzip -6 /backup/neo4j.dump
                  aws s3 cp /backup/neo4j.dump.gz "s3://$S3_BUCKET/neo4j/$STAMP/" --only-show-errors
                  echo "{\"stamp\":\"$STAMP\",\"size\":\"$(du -h /backup/neo4j.dump.gz | cut -f1)\"}" \
                    > /tmp/metadata.json
                  aws s3 cp /tmp/metadata.json "s3://$S3_BUCKET/neo4j/$STAMP/metadata.json"

                  echo "▸ 7. prune to 7 days"
                  aws s3 ls "s3://$S3_BUCKET/neo4j/" | awk '{print $2}' | sort -r | tail -n +8 \
                    | while read -r old; do aws s3 rm --recursive "s3://$S3_BUCKET/neo4j/$old"; echo "pruned $old"; done

                  echo "✅ backup $STAMP complete"
              env:
                - {name: NEO4J_AUTH, valueFrom: {secretKeyRef: {name: neo4j-creds, key: NEO4J_AUTH}}}
                - {name: S3_BUCKET, value: neo4j-backups}
              resources:
                requests: {cpu: 500m, memory: 2Gi}
                limits:   {cpu: "2",   memory: 4Gi}
              volumeMounts:
                - {name: data,    mountPath: /data, readOnly: true}     # ⭐ needs the store
                - {name: backup,  mountPath: /backup}
                - {name: verify,  mountPath: /verify}
          volumes:
            - {name: data,   persistentVolumeClaim: {claimName: data-neo4j-0}}
            - {name: backup, emptyDir: {sizeLimit: 100Gi}}
            - {name: verify, emptyDir: {sizeLimit: 100Gi}}
```

⚠️ **The volume conflict.** A `ReadWriteOnce` PVC can only be mounted by one Pod. The backup Job needs `/data`, but `neo4j-0` already has it. Three ways out:

1. **Run the backup as an `exec` inside the Neo4j Pod** — no volume contention:
   ```bash
   kubectl exec -n db neo4j-0 -- bash -c '
     neo4j-admin database dump neo4j --to-path=/tmp &&
     gzip /tmp/neo4j.dump &&
     aws s3 cp /tmp/neo4j.dump.gz s3://neo4j-backups/$(date +%F)/'
   ```
2. **Volume snapshots** (the Kubernetes-native answer):
   ```yaml
   apiVersion: snapshot.storage.k8s.io/v1
   kind: VolumeSnapshot
   metadata: {name: neo4j-snap-20260909, namespace: db}
   spec:
     volumeSnapshotClassName: csi-hostpath-snapclass
     source: {persistentVolumeClaimName: data-neo4j-0}
   ```
   ```bash
   kubectl apply -f snapshot.yaml
   kubectl get volumesnapshot -n db
   # ⚠️ Neo4j MUST be checkpointed first, or the snapshot is inconsistent.
   ```
3. **Upgrade to Enterprise** and use online backups.

**Method 2 (snapshots) is the right one for Community on Kubernetes:**

```yaml
apiVersion: batch/v1
kind: CronJob
metadata: {name: neo4j-snapshot, namespace: db}
spec:
  schedule: "0 3 * * *"
  concurrencyPolicy: Forbid
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: Never
          serviceAccountName: neo4j-backup
          containers:
            - name: snapshot
              image: bitnami/kubectl:1.33
              command:
                - bash
                - -c
                - |
                  set -euo pipefail
                  STAMP=$(date -u +%Y%m%d-%H%M%S)
                  PW="${NEO4J_AUTH#neo4j/}"

                  echo "▸ checkpoint"
                  kubectl exec -n db neo4j-0 -- cypher-shell -u neo4j -p "$PW" \
                    "CALL db.checkpoint() YIELD success RETURN success;"

                  echo "▸ create the snapshot"
                  cat <<YAML | kubectl apply -f -
                  apiVersion: snapshot.storage.k8s.io/v1
                  kind: VolumeSnapshot
                  metadata: {name: neo4j-$STAMP, namespace: db}
                  spec:
                    volumeSnapshotClassName: ebs-csi-snapclass
                    source: {persistentVolumeClaimName: data-neo4j-0}
                  YAML

                  kubectl wait -n db --for=jsonpath='{.status.readyToUse}'=true \
                    volumesnapshot/neo4j-$STAMP --timeout=600s

                  echo "▸ tag it for retention"
                  aws ec2 create-tags --resources \
                    "$(kubectl get volumesnapshot -n db neo4j-$STAMP \
                        -o jsonpath='{.status.boundVolumeSnapshotContentName}')" \
                    --tags Key=Backup,Value=neo4j Key=Date,Value=$STAMP

                  echo "✅ snapshot neo4j-$STAMP ready"
              env:
                - {name: NEO4J_AUTH, valueFrom: {secretKeyRef: {name: neo4j-creds, key: NEO4J_AUTH}}}
```

### Enterprise clustering — for reference

If you have an Enterprise licence, this is what changes:

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata: {name: neo4j, namespace: db}
spec:
  replicas: 3
  podManagementPolicy: OrderedReady
  updateStrategy: {type: RollingUpdate}      # ✅ safe now — it's a real cluster
  template:
    spec:
      containers:
        - name: neo4j
          image: neo4j:5.26-enterprise
          env:
            - {name: NEO4J_ACCEPT_LICENSE_AGREEMENT, value: "yes"}
            - {name: NEO4J_server_discovery_advertised__address, value: "$(POD_NAME).neo4j.db.svc.cluster.local:5000"}
            - {name: NEO4J_server_cluster_advertised__address,   value: "$(POD_NAME).neo4j.db.svc.cluster.local:6000"}
            - {name: NEO4J_server_cluster_raft_advertised__address, value: "$(POD_NAME).neo4j.db.svc.cluster.local:7000"}
            - {name: NEO4J_server_cluster_routing_advertised__address, value: "$(POD_NAME).neo4j.db.svc.cluster.local:7688"}
            - {name: NEO4J_server_cluster_discovery_endpoints, value: >-
                neo4j-0.neo4j.db.svc.cluster.local:5000
                neo4j-1.neo4j.db.svc.cluster.local:5000
                neo4j-2.neo4j.db.svc.cluster.local:5000}
            - {name: NEO4J_dbms_cluster_minimum__core__cluster__size__at__formation, value: "3"}
            - {name: NEO4J_initial_dbms_default__database, value: "neo4j"}
            - {name: NEO4J_dbms_mode, value: "CORE"}
            - {name: POD_NAME, valueFrom: {fieldRef: {fieldPath: metadata.name}}}
          ports:
            - {name: bolt,     containerPort: 7687}
            - {name: http,     containerPort: 7474}
            - {name: discovery, containerPort: 5000}
            - {name: cluster,  containerPort: 6000}
            - {name: raft,     containerPort: 7000}
            - {name: routing,  containerPort: 7688}
```

**The client connection string changes too:**

```
neo4j://neo4j.db.svc.cluster.local:7687          ← the routing connector handles discovery
neo4j+s://…                                       ← with TLS
bolt+ssc://…                                      ← self-signed
```

The driver asks the routing connector for the cluster topology and then talks directly to individual members. Reads go to read-replicas; writes to the primary.

**Or just use the official operator:**

```bash
helm repo add neo4j https://helm.neo4j.com/neo4j-operator
helm install neo4j-operator neo4j/neo4j-operator -n neo4j-operator --create-namespace
```

```yaml
apiVersion: demo.neo4j.com/v1
kind: Neo4jCluster
metadata: {name: shop-graph, namespace: db}
spec:
  neo4j:
    podSpec:
      image: neo4j:5.26-enterprise
      resources:
        requests: {cpu: "1", memory: 5Gi}
        limits:   {cpu: "4", memory: 6Gi}
      volumes: [{name: data, emptyDir: {}}]
    config:
      server.memory.heap.max_size: "2G"
      server.memory.pagecache.size: "2G"
  disk:
    labels: {app: shop-graph}
    capacity: "50Gi"
    storageClass: gp3
```

### The app's connection handling

```java
// Neo4j Java driver — always a POOL, never a connection per query
@Bean(destroyMethod = "close")
public Driver neo4jDriver() {
    return GraphDatabase.driver(
        System.getenv().getOrDefault("NEO4J_URI", "bolt://neo4j.db.svc.cluster.local:7687"),
        AuthTokens.basic(
            System.getenv("NEO4J_USER"),
            System.getenv("NEO4J_PASSWORD")),
        Config.builder()
            .withMaxConnectionPoolSize(50)               // ⭐ 10 app pods × 50 = 500
            .withConnectionAcquisitionTimeout(5, TimeUnit.SECONDS)
            .withMaxTransactionRetryTime(15, TimeUnit.SECONDS)   // ⭐ retries transient errors
            .withConnectionTimeout(5, TimeUnit.SECONDS)
            .withLogging(Logging.slf4j())
            .withFetchSize(1000)                          // stream big results
            .build());
}
```

```python
# Python
from neo4j import GraphDatabase
driver = GraphDatabase.driver(
    os.environ["NEO4J_URI"],
    auth=(os.environ["NEO4J_USER"], os.environ["NEO4J_PASSWORD"]),
    max_connection_pool_size=50,
    connection_acquisition_timeout=5.0,
    max_transaction_retry_time=15.0,
    connection_timeout=5.0,
)
# ⭐ use sessions as context managers, and NEVER hold one across a request
with driver.session(database="neo4j") as session:
    result = session.run("MATCH (p:Product) RETURN p LIMIT 10")
    products = [r["p"]["name"] for r in result]
```

```go
// Go
driver, err := neo4j.NewDriverWithContext(
    os.Getenv("NEO4J_URI"),
    auth.Basic(os.Getenv("NEO4J_USER"), os.Getenv("NEO4J_PASSWORD")),
    func(c *neo4j.Config) {
        c.MaxConnectionPoolSize = 50
        c.ConnectionAcquisitionTimeout = 5 * time.Second
        c.MaxTransactionRetryTime = 15 * time.Second
        c.ConnectionTimeout = 5 * time.Second
        c.SocketKeepalive = true
    })
```

## Neo4j tasks

<details>
<summary>Task 13.6.1 — Size the heap and page cache correctly, and find the queries that blow them up.</summary>

### The three memory regions

```
┌─────────────────────────────────────────────┐
│ container limits.memory            6 Gi     │
│ ┌─────────────────────────────────────────┐ │
│ │ JVM heap                       2 Gi     │ │  transaction state, query execution,
│ │                                         │ │  object graph, GC
│ ├─────────────────────────────────────────┤ │
│ │ page cache                     2 Gi     │ │  ⭐ nodes, relationships, properties,
│ │                                         │ │     indexes — THE graph, in RAM
│ ├─────────────────────────────────────────┤ │
│ │ off-heap / native              ~0.5 Gi  │ │  Netty buffers, memory-mapped files
│ ├─────────────────────────────────────────┤ │
│ │ JVM overhead (metaspace, stacks, ~1 Gi  │ │
│ │   code cache, GC structures)            │ │
│ └─────────────────────────────────────────┘ │
└─────────────────────────────────────────────┘
```

**Rule:** `limits.memory ≥ heap + pagecache + 1.5 Gi`

### Size the page cache from your actual store

```bash
kubectl exec -n db neo4j-0 -- du -sh /data/databases/neo4j/
# 4.2G    /data/databases/neo4j/

kubectl exec -n db neo4j-0 -- ls -lh /data/databases/neo4j/
# -rw-r--r-- 1 neo4j neo4j  1.2G neostore.nodestore.db
# -rw-r--r-- 1 neo4j neo4j  2.4G neostore.relationshipstore.db
# -rw-r--r-- 1 neo4j neo4j  480M neostore.propertystore.db
# -rw-r--r-- 1 neo4j neo4j  128M neostore.labelscanstore.db
```

```bash
kubectl exec -n db neo4j-0 -- cypher-shell -u neo4j -p'…' "
  CALL apoc.meta.stats() YIELD nodeCount, relCount, labelCount, relTypeCount
  RETURN nodeCount, relCount, labelCount, relTypeCount;"
```

```
╒═══════════╤══════════╤════════════╤══════════════╕
│"nodeCount"│"relCount"│"labelCount"│"relTypeCount"│
╞═══════════╪══════════╪════════════╪══════════════╡
│12841033   │48210441  │8           │5             │
└───────────┴──────────┴────────────┴──────────────┘
```

**The arithmetic:**

```
nodes:         12,841,033 × 15 bytes  =  193 MB
relationships: 48,210,441 × 34 bytes  = 1,639 MB
properties:    (est. 5 per entity)    =  600 MB
indexes:       (label scan + custom)  =  300 MB
──────────────────────────────────────────────────
store size                            ≈ 2.7 GB
```

**Three strategies:**

| Strategy | pagecache | Effect |
|---|---|---|
| **Full cache** | 3 Gi | Everything in RAM. Fastest. Costs 3 Gi you can't use for anything else |
| **Hot cache** | 1.5 Gi | ~55% cached. Reads of cold data hit disk |
| **Minimal** | 512 Mi | Mostly disk. Only viable with an SSD-backed StorageClass |

**Which to pick?** Measure your access pattern:

```bash
kubectl exec -n db neo4j-0 -- cypher-shell -u neo4j -p'…' "
  CALL db.stats.retrieve('STORE SIZES') YIELD data RETURN data;"
```

```promql
# page cache hit ratio — the number that decides everything
rate(neo4j_page_cache_hit_total[5m])
  / (rate(neo4j_page_cache_hit_total[5m]) + rate(neo4j_page_cache_miss_total[5m]))
```

| Hit ratio | Verdict |
|---|---|
| > 99% | Perfectly sized |
| 95–99% | Fine; consider raising it |
| 80–95% | ⚠️ Noticeable disk I/O on tail queries |
| < 80% | ⛔ Your graph doesn't fit. Raise the pagecache or your queries are scanning cold data |

```bash
kubectl exec -n db neo4j-0 -- cypher-shell -u neo4j -p'…' "
  CALL dbms.listConfig() YIELD name, value
  WHERE name CONTAINS 'memory' RETURN name, value;"
```

### Size the heap from your query patterns

Heap holds **transaction state and query working memory**. It blows up on:
- Large `MATCH … RETURN` result sets materialised in memory
- `apoc.periodic.iterate` with big batches
- Many concurrent transactions
- Unbounded `collect()` aggregations

```bash
kubectl exec -n db neo4j-0 -- cypher-shell -u neo4j -p'…' "
  CALL db.listTransactions() YIELD transactionId, currentQuery, elapsedTime,
    status, metadata, protocol, username
  RETURN transactionId, elapsedTime, status, currentQuery;"
```

```bash
# JVM heap from JMX
kubectl exec -n db neo4j-0 -- bash -c '
  jcmd $(pgrep -f neo4j) GC.heap_info'
```

```
garbage-first heap   total 2097152K, used 842103K
  region size 1024K, 412 young (421888K), 18 survivors (18432K)
 Metaspace       used 128410K, committed 132096K, reserved 1179648K
```

**The formula:**

```
heap = (max concurrent transactions × avg transaction state)
     + (largest query working set)
     + 512 MB baseline

Example:
  50 concurrent transactions × 20 MB = 1,000 MB
  largest aggregation                 =  500 MB
  baseline                            =  512 MB
  ─────────────────────────────────────────────
  heap                                ≈ 2 GB      ✅ matches our config
```

### Find the queries that blow it up

**The query log** (`server.logs.query.threshold=1s`):

```bash
kubectl exec -n db neo4j-0 -- sh -c 'tail -100 /logs/query.log'
```

```
2026-09-09 17:02:14.842+0000: 12841 ms: bolt  neo4j-java-driver/5.26  client/10.244.2.19
  - cypher: MATCH (p:Product)-[:BELONGS_TO]->(c:Category) RETURN p, c
  - params: {}
```

**12.8 seconds.** And it returns the *entire* graph. Sort the log:

```bash
kubectl exec -n db neo4j-0 -- sh -c \
  "grep -oE '^[^:]+: [0-9]+ ms' /logs/query.log | awk '{print \$2, \$0}' | sort -rn | head -20"
```

```
48210 ms: 2026-09-09 17:14:22 … MATCH (n) RETURN n
12841 ms: 2026-09-09 17:02:14 … MATCH (p:Product)-[:BELONGS_TO]->(c) RETURN p, c
 8421 ms: 2026-09-09 17:31:02 … MATCH (a)-[*]->(b) RETURN a, b     ← ⛔ unbounded variable-length
```

**`PROFILE` them:**

```bash
kubectl exec -n db neo4j-0 -- cypher-shell -u neo4j -p'…' "
  PROFILE MATCH (p:Product)-[:BELONGS_TO]->(c:Category) RETURN p, c;"
```

```
Plan:
+----------------+----------------+------+---------------+
| Operator       | Rows           | DB Hits| Identifiers  |
+----------------+----------------+------+---------------+
| +ProduceResults| 48210441       | 0    | c, p          |
| |              +----------------+------+---------------+
| +Filter        | 48210441       | 0    | …             |
| |              +----------------+------+---------------+
| +NodeByLabelScan| 12841033      | 12841034| p           |   ← ⛔ FULL LABEL SCAN
+----------------+----------------+------+---------------+

Total database accesses: 48210441
```

**12.8 million DB hits.** The fix:

```cypher
// ⛔ the original — returns everything
MATCH (p:Product)-[:BELONGS_TO]->(c:Category) RETURN p, c

// ✅ bounded, paginated, indexed
MATCH (c:Category {name: $category})<-[:BELONGS_TO]-(p:Product)
RETURN p.id, p.name, p.price
ORDER BY p.name
SKIP $offset LIMIT 50
```

```bash
# create the indexes that make it fast
kubectl exec -n db neo4j-0 -- cypher-shell -u neo4j -p'…' "
  CREATE INDEX category_name IF NOT EXISTS FOR (c:Category) ON (c.name);
  CREATE INDEX product_id    IF NOT EXISTS FOR (p:Product)  ON (p.id);
  CREATE CONSTRAINT product_sku IF NOT EXISTS FOR (p:Product) REQUIRE p.sku IS UNIQUE;
  SHOW INDEXES YIELD name, type, properties, state RETURN *;"
```

```bash
# re-profile
kubectl exec -n db neo4j-0 -- cypher-shell -u neo4j -p'…' "
  PROFILE MATCH (c:Category {name:'Tools'})<-[:BELONGS_TO]-(p:Product)
  RETURN p.id, p.name SKIP 0 LIMIT 50;"
```

```
Total database accesses: 142       ← from 48 MILLION to 142
```

### Guard rails so it can't happen again

```bash
# 1. transaction timeout and count limits (already in the ConfigMap)
db.transaction.timeout=300s
db.transaction.total.max=200
db.lock.acquisition.timeout=60s

# 2. reject unbounded variable-length patterns at the query-review level
#    (Neo4j can't do this natively — use a linter)
```

```yaml
# 3. alert on heap pressure
- alert: Neo4jHeapHigh
  expr: |
    neo4j_jvm_heap_used / neo4j_jvm_heap_max > 0.85
  for: 10m
  labels: {severity: warning}
  annotations:
    summary: "Neo4j heap at {{ $value | humanizePercentage }}"
    description: "Check /logs/query.log for unbounded queries. Run `CALL db.listTransactions()`."

- alert: Neo4jPageCacheMissesHigh
  expr: |
    rate(neo4j_page_cache_miss_total[5m])
      / (rate(neo4j_page_cache_hit_total[5m]) + rate(neo4j_page_cache_miss_total[5m])) > 0.05
  for: 15m
  labels: {severity: warning}
  annotations:
    summary: "Neo4j page cache miss rate above 5% — raise server.memory.pagecache.size"

- alert: Neo4jLongRunningQuery
  expr: neo4j_transaction_active_seconds > 60
  for: 1m
  labels: {severity: warning}
  annotations: {summary: "A Neo4j transaction has been running for {{ $value }}s"}
```

### The sizing table (final)

| Graph size | heap | pagecache | container limit | CPU |
|---|---|---|---|---|
| < 1 GB store | 1 Gi | 1 Gi | 4 Gi | 2 |
| 1–5 GB | 2 Gi | 3 Gi | 6 Gi | 4 |
| 5–20 GB | 4 Gi | 12 Gi | 20 Gi | 8 |
| 20–100 GB | 8 Gi | 40 Gi | 56 Gi | 16 |
| > 100 GB | 8–16 Gi | as much as you can afford | — | Cluster (Enterprise) |

⚠️ **Never let heap exceed 8–16 Gi.** GC pause times scale with heap size, and Neo4j is latency-sensitive. If you think you need a 32 Gi heap, you have a query problem.

</details>

<details>
<summary>Task 13.6.2 — Upgrade Neo4j 5.20 → 5.26 on Kubernetes without losing data.</summary>

**Neo4j upgrades are one-way.** A 5.26 store cannot be opened by 5.20. There is no downgrade except a restore from backup. Plan accordingly.

### Step 0 — read the release notes and check the path

```bash
# Neo4j supports upgrading within a minor version directly (5.x → 5.y).
# Across majors (4.4 → 5.x) you MUST go through 4.4 latest first.
kubectl exec -n db neo4j-0 -- cypher-shell -u neo4j -p'…' \
  "CALL dbms.components() YIELD name, versions, edition RETURN name, versions, edition;"
```

```
╒════════╤══════════╤═══════════╕
│"name"  │"versions"│"edition"  │
╞════════╪══════════╪═══════════╡
│"Neo4j" │["5.20.0"]│"community"│
└────────┴──────────┴───────────┘
```

5.20 → 5.26 is a minor upgrade. Direct.

### Step 1 — BACK UP. And verify the backup.

```bash
# checkpoint first so the store is consistent
kubectl exec -n db neo4j-0 -- cypher-shell -u neo4j -p'…' "
  CALL db.checkpoint() YIELD success, message RETURN success, message;"

# snapshot the volume (the Kubernetes-native way)
STAMP=$(date +%Y%m%d-%H%M%S)
cat <<EOF | kubectl apply -f -
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata: {name: neo4j-pre-upgrade-$STAMP, namespace: db}
spec:
  volumeSnapshotClassName: ebs-csi-snapclass
  source: {persistentVolumeClaimName: data-neo4j-0}
EOF
kubectl wait -n db --for=jsonpath='{.status.readyToUse}'=true \
  volumesnapshot/neo4j-pre-upgrade-$STAMP --timeout=600s

# ALSO take a logical dump (works even if the snapshot class is broken)
kubectl exec -n db neo4j-0 -- neo4j-admin database dump neo4j --to-path=/tmp
kubectl cp db/neo4j-0:/tmp/neo4j.dump ./neo4j-pre-upgrade-$STAMP.dump
ls -lh ./neo4j-pre-upgrade-$STAMP.dump
```

**Verify the dump actually loads:**

```bash
docker run --rm -v $PWD:/backup -v neo4j-verify:/data neo4j:5.26-community \
  neo4j-admin database load neo4j --from-path=/backup --to-path=/data
docker run --rm -v neo4j-verify:/data -e NEO4J_AUTH=neo4j/test12345678 -p 7475:7474 \
  neo4j:5.26-community &
sleep 40
curl -s -u neo4j:test12345678 localhost:7475/db/neo4j/tx/commit \
  -H 'Content-Type: application/json' \
  -d '{"statements":[{"statement":"MATCH (n) RETURN count(n) AS nodes"}]}' | jq .
kill %1
```

**If this doesn't work, you have no backup. Stop.**

### Step 2 — record the pre-upgrade state

```bash
kubectl exec -n db neo4j-0 -- cypher-shell -u neo4j -p'…' "
  MATCH (n) WITH labels(n)[0] AS label, count(*) AS nodes RETURN label, nodes ORDER BY nodes DESC;
  MATCH ()-[r]->() RETURN type(r) AS rel, count(*) AS n ORDER BY n DESC;
  CALL db.schema.visualization();" > pre-upgrade.txt
kubectl exec -n db neo4j-0 -- cypher-shell -u neo4j -p'…' \
  "SHOW INDEXES YIELD name, type, properties, state RETURN *;" > pre-upgrade-indexes.txt
kubectl exec -n db neo4j-0 -- cypher-shell -u neo4j -p'…' \
  "SHOW CONSTRAINTS;" > pre-upgrade-constraints.txt
kubectl exec -n db neo4j-0 -- cypher-shell -u neo4j -p'…' \
  "CALL dbms.listConfig() YIELD name, value RETURN name, value ORDER BY name;" > pre-upgrade-config.txt
```

### Step 3 — check plugin compatibility

```bash
kubectl exec -n db neo4j-0 -- ls -lh /plugins/
# -rw-r--r-- 1 neo4j neo4j 12M apoc-5.20.0-core.jar      ← ⛔ version-matched to the OLD Neo4j
```

APOC versions are **tightly coupled** to Neo4j versions. `apoc-5.20.0` will not load in 5.26. Update the fetch-plugins init container:

```yaml
- name: fetch-plugins
  env:
    - {name: APOC_VERSION, value: "5.26.0"}     # ⭐ bumped
```

Check the compatibility matrix at <https://neo4j.com/labs/apoc/versioning/> before you start.

### Step 4 — the upgrade itself

**With `updateStrategy: OnDelete` (as configured), nothing happens until you delete the Pod.**

```bash
# 1. set the new image AND the upgrade flag
kubectl set image sts/neo4j -n db neo4j=neo4j:5.26-community
kubectl set env sts/neo4j -n db neo4j NEO4J_dbms_allow__upgrade=true

# 2. confirm nothing restarted yet
kubectl get pods -n db neo4j-0 -o jsonpath='{.spec.containers[0].image}'; echo
# neo4j:5.26-community        ← the SPEC says 5.26
kubectl exec -n db neo4j-0 -- cypher-shell -u neo4j -p'…' \
  "CALL dbms.components() YIELD versions RETURN versions;"
# ["5.20.0"]                   ← the RUNNING pod is still 5.20 ✅

# 3. drain traffic
kubectl label pod -n db neo4j-0 maintenance=true --overwrite
# (assuming your app selects on !maintenance)
kubectl get endpointslices -n db -l kubernetes.io/service-name=neo4j

# 4. stop it
kubectl exec -n db neo4j-0 -- cypher-shell -u neo4j -p'…' "CALL db.checkpoint();"
kubectl delete pod -n db neo4j-0

# 5. watch the migration happen
kubectl logs -n db neo4j-0 -f | grep -iE 'upgrade|migrat|store|version'
```

```
INFO  Starting upgrade of database 'neo4j' from 5.20.0 to 5.26.0
INFO  Migrating StoreFiles for 'neo4j'
INFO  Store migration completed successfully
INFO  Database 'neo4j' is now at version 5.26.0
INFO  Started.
INFO  Remote interface available at http://neo4j.db.svc.cluster.local:7474/
```

```bash
# 6. verify
kubectl exec -n db neo4j-0 -- cypher-shell -u neo4j -p'…' \
  "CALL dbms.components() YIELD name, versions, edition RETURN *;"
# ["5.26.0"]      ✅

kubectl exec -n db neo4j-0 -- cypher-shell -u neo4j -p'…' "
  MATCH (n) WITH labels(n)[0] AS label, count(*) AS nodes RETURN label, nodes ORDER BY nodes DESC;" \
  > post-upgrade.txt
diff pre-upgrade.txt post-upgrade.txt && echo "✅ node counts identical"

kubectl exec -n db neo4j-0 -- cypher-shell -u neo4j -p'…' "SHOW INDEXES;" > post-upgrade-indexes.txt
diff pre-upgrade-indexes.txt post-upgrade-indexes.txt && echo "✅ indexes identical"

# 7. run your app's smoke tests against it
./scripts/smoke-test.sh db

# 8. remove the upgrade flag (it must NOT stay set)
kubectl set env sts/neo4j -n db neo4j NEO4J_dbms_allow__upgrade-
kubectl label pod -n db neo4j-0 maintenance- --overwrite
```

⚠️ **Leaving `dbms.allow_upgrade=true` set is a data-loss risk.** Any future restart will attempt a migration. Remove it immediately.

### Step 5 — if it goes wrong

```bash
# symptoms
kubectl get pods -n db neo4j-0
# neo4j-0   0/1   CrashLoopBackOff

kubectl logs -n db neo4j-0 --previous | tail -30
```

```
ERROR Failed to start Neo4j on dbms.connector…
ERROR The store is in an unsupported version: 5.26.0. This version of Neo4j (5.20.0)
      cannot read it. Please upgrade to at least 5.26.0.
```

**That's a downgrade attempt on an upgraded store. The only way back is the backup:**

```bash
# Option A — restore the volume snapshot (fastest)
kubectl scale sts/neo4j -n db --replicas=0
kubectl delete pvc -n db data-neo4j-0 --wait=true
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: data-neo4j-0, namespace: db}
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: ebs-csi-snapclass-restore
  resources: {requests: {storage: 50Gi}}
  dataSource:
    name: neo4j-pre-upgrade-$STAMP
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
EOF
kubectl set image sts/neo4j -n db neo4j=neo4j:5.20-community
kubectl set env sts/neo4j -n db neo4j NEO4J_dbms_allow__upgrade-
kubectl scale sts/neo4j -n db --replicas=1
kubectl rollout status sts/neo4j -n db --timeout=600s

# Option B — restore from the logical dump
kubectl scale sts/neo4j -n db --replicas=0
kubectl run neo4j-restore -n db --rm -it --restart=Never \
  --image=neo4j:5.20-community \
  --overrides='{"spec":{"containers":[{"name":"r","image":"neo4j:5.20-community",
    "command":["neo4j-admin","database","load","neo4j","--from-path=/backup","--to-path=/data","--overwrite-destination"],
    "volumeMounts":[{"name":"d","mountPath":"/data"},{"name":"b","mountPath":"/backup"}]}],
    "volumes":[{"name":"d","persistentVolumeClaim":{"claimName":"data-neo4j-0"}},
               {"name":"b","configMap":{"name":"backup-placeholder"}}]}}'
kubectl scale sts/neo4j -n db --replicas=1
```

Verify the restore:

```bash
kubectl exec -n db neo4j-0 -- cypher-shell -u neo4j -p'…' \
  "CALL dbms.components() YIELD versions RETURN versions;"
# ["5.20.0"]      ✅ back to the pre-upgrade version

diff <(kubectl exec -n db neo4j-0 -- cypher-shell -u neo4j -p'…' \
       "MATCH (n) RETURN count(n);") <(echo "…the pre-upgrade count…")
```

### The upgrade checklist

- [ ] Read the 5.21 → 5.26 release notes for deprecations and config renames
- [ ] Verify the APOC/plugin versions match the target Neo4j version
- [ ] Full backup: **both** a volume snapshot and a logical dump
- [ ] **Restore-tested** the backup into a scratch instance
- [ ] Recorded node/relationship counts, indexes, constraints, and config
- [ ] Confirmed the upgrade path is supported (minor = direct; major = via the latest previous major)
- [ ] `updateStrategy: OnDelete` so the restart is manual and timed
- [ ] Drained traffic before deleting the Pod
- [ ] Set `dbms.allow_upgrade=true`, then **removed it** after
- [ ] Diffed the post-upgrade counts against the pre-upgrade ones
- [ ] Ran the application's smoke tests
- [ ] Kept the snapshot for 30 days
- [ ] Done it in staging first, on a copy of production data

**Config renames to watch for** — Neo4j renamed a lot between 4.x and 5.x:

| 4.x | 5.x |
|---|---|
| `dbms.memory.heap.max_size` | `server.memory.heap.max_size` |
| `dbms.memory.pagecache.size` | `server.memory.pagecache.size` |
| `dbms.connector.bolt.listen_address` | `server.bolt.listen_address` |
| `dbms.connector.bolt.advertised_address` | `server.bolt.advertised_address` |
| `dbms.default_listen_address` | `server.default_listen_address` |
| `dbms.directories.logs` | `server.directories.logs` |
| `dbms.tx_log.rotation.retention_policy` | `db.tx_log.rotation.retention_policy` |
| `dbms.security.auth_enabled` | `dbms.security.auth_enabled` (unchanged) |

```bash
# find deprecated settings in your config
kubectl exec -n db neo4j-0 -- cypher-shell -u neo4j -p'…' \
  "CALL dbms.listConfig() YIELD name, description WHERE description CONTAINS 'deprecated' RETURN name;"
```

</details>

---
---

# 13.7 The cross-database summary

## The pattern that works for all six

```yaml
apiVersion: apps/v1
kind: StatefulSet
spec:
  serviceName: <headless-service>        # ⭐ stable per-Pod DNS
  podManagementPolicy: OrderedReady      # unless the DB elects its own leader (Mongo)
  updateStrategy:
    type: RollingUpdate                  # OnDelete for Neo4j Community
  volumeClaimTemplates: [...]            # ⭐ per-Pod persistent storage
---
apiVersion: v1
kind: Service
spec:
  clusterIP: None                        # ⭐ HEADLESS for the StatefulSet
  publishNotReadyAddresses: true         # ⭐ so members can find each other during init
---
apiVersion: policy/v1
kind: PodDisruptionBudget
spec:
  minAvailable: <quorum>                 # 2 of 3, never maxUnavailable: 1 of 1
```

## The comparison

| | MySQL | MongoDB | Redis | DynamoDB Local | Cassandra | Neo4j CE |
|---|---|---|---|---|---|---|
| **Image** | mysql:8.4 | mongo:7 | redis:7-alpine | amazon/dynamodb-local:2.5.2 | cassandra:4.1 | neo4j:5.26-community |
| **Workload** | StatefulSet | StatefulSet | StatefulSet | Deployment | StatefulSet | StatefulSet |
| **Replicas (min for HA)** | 2 + operator | **3** | 3 + Sentinel | 1 (dev only) | **3** | **1** ⛔ |
| **Self-elects a leader** | ❌ (Group Replication does) | ✅ | ❌ (Sentinel does) | n/a | ❌ (no leader) | ❌ |
| **podManagementPolicy** | OrderedReady | **Parallel** | Parallel | n/a | **OrderedReady** | OrderedReady |
| **Headless Service** | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ |
| **`publishNotReadyAddresses`** | helpful | **required** | helpful | no | **required** | helpful |
| **Readiness probe** | real query | `rs.status()` + lag | `PING` | HTTP GET / | CQL query + `nodetool` state | HTTP GET / |
| **Liveness probe** | `mysqladmin ping` | `ping` | `PING` | HTTP GET / | `nodetool status` | TCP :7687 |
| **Startup time** | 20–60 s | 10–30 s | 1–5 s | 10–20 s | **2–6 min** | 1–5 min |
| **`terminationGracePeriod`** | 120 s | 120 s | 60 s | 30 s | **1800 s** | 300 s |
| **preStop** | `SHUTDOWN` | `replSetStepDown` + fsync | `BGSAVE` | — | **`nodetool drain`** | `db.checkpoint()` |
| **Memory sizing** | `innodb_buffer_pool` 60% | `wiredTigerCacheSizeGB` 25–40% | `maxmemory` 66% | JVM 60% | JVM heap **50%** | heap + pagecache + 1.5 Gi |
| **CPU-limit aware?** | No | No | `io-threads` manual | No | **`ParallelGCThreads` manual** | `worker_count` manual |
| **Guaranteed QoS** | ✅ recommended | ✅ | ✅ | ❌ (dev) | ✅ | ✅ |
| **Failover time** | manual / 10 s w/ operator | **~10 s automatic** | 0 without Sentinel | n/a | **0 (quorum continues)** | **∞ (no HA)** |
| **Backup tool** | mysqldump / xtrabackup | mongodump (from a secondary) | RDB + AOF | n/a (emulator) | `nodetool snapshot` + Reaper | ⛔ `database dump` (offline) |
| **Online backup?** | ✅ xtrabackup | ✅ | ✅ BGSAVE | n/a | ✅ snapshot | ❌ Community |
| **The right operator** | Oracle / Percona / Vitess | mongodb-kubernetes-operator | Spotahome redis-operator | — | K8ssandra / cass-operator | neo4j-operator (Enterprise) |
| **Should you run it on K8s?** | ✅ with an operator | ✅ | ✅ | dev only | ✅ **best fit** | ⚠️ Community can't cluster |
| **Biggest K8s-specific trap** | RollingUpdate + RWO deadlock | Non-FQDN hosts in `rs.conf()` | `maxmemory` unset → OOMKill | Using it in prod | `broadcast_address` = Pod IP | Community ≠ clustered |

## The ten things that break every database on Kubernetes

1. **`strategy: RollingUpdate` with an RWO PVC** → Multi-Attach deadlock. Use `Recreate` or a StatefulSet.
2. **A non-headless Service for a StatefulSet** → per-Pod DNS doesn't exist → the cluster can't find itself.
3. **`publishNotReadyAddresses: false`** → bootstrapping members can't resolve each other → deadlock on first deploy.
4. **Memory settings computed from the node, not the container** → guaranteed OOMKill. Set them explicitly, always.
5. **No PDB, or `maxUnavailable: 1` on a single replica** → a node drain takes the database down.
6. **`terminationGracePeriodSeconds` shorter than the shutdown** → SIGKILL → crash recovery on every restart.
7. **A readiness probe that passes while the DB isn't ready** (`mysqladmin ping` during recovery, `nodetool status` during bootstrap) → traffic hits a broken node.
8. **A liveness probe with a 5-second timeout on a slow database** (`nodetool` can take 20 s) → restart loops.
9. **Zoned PVs + a node loss in that zone** → the Pod is Pending forever.
10. **Backups that were never restore-tested** → you have no backups.

## The universal verification script

```bash
#!/usr/bin/env bash
# db-check.sh <namespace> <statefulset-name> — works for all six
set -uo pipefail
NS=${1:?namespace}; STS=${2:?statefulset}

echo "═══ $NS/$STS ═══"

echo "▸ identity & storage"
kubectl get sts -n $NS $STS -o jsonpath='{.spec.serviceName}{"\n"}'
kubectl get svc -n $NS $(kubectl get sts -n $NS $STS -o jsonpath='{.spec.serviceName}') \
  -o jsonpath='clusterIP={.spec.clusterIP} publishNotReady={.spec.publishNotReadyAddresses}{"\n"}'
kubectl get pvc -n $NS -l app=$STS -o custom-columns='PVC:.metadata.name,STATUS:.status.phase,CAP:.status.capacity.storage,SC:.spec.storageClassName'

echo "▸ spread & disruption"
kubectl get pods -n $NS -l app=$STS -o custom-columns='POD:.metadata.name,NODE:.spec.nodeName,READY:.status.containerStatuses[0].ready,RESTARTS:.status.containerStatuses[0].restartCount'
kubectl get pdb -n $NS -l app=$STS -o custom-columns='PDB:.metadata.name,MIN:.spec.minAvailable,MAX:.spec.maxUnavailable,ALLOWED:.status.disruptionsAllowed' 2>/dev/null

echo "▸ resource guarantees"
kubectl get sts -n $NS $STS -o jsonpath='{range .spec.template.spec.containers[*]}{.name}: requests={.resources.requests} limits={.resources.limits}{"\n"}{end}'
kubectl get pods -n $NS -l app=$STS -o jsonpath='{range .items[*]}{.metadata.name}: {.status.qosClass}{"\n"}{end}'

echo "▸ probes"
kubectl get sts -n $NS $STS -o jsonpath='{range .spec.template.spec.containers[*]}{.name}: startup={.startupProbe.timeoutSeconds}s readiness={.readinessProbe.timeoutSeconds}s liveness={.livenessProbe.timeoutSeconds}s grace={..terminationGracePeriodSeconds}{"\n"}{end}'

echo "▸ live health"
kubectl top pods -n $NS -l app=$STS 2>/dev/null
kubectl get events -n $NS --field-selector involvedObject.name=$(kubectl get pod -n $NS -l app=$STS -o jsonpath='{.items[0].metadata.name}') --sort-by=.lastTimestamp | tail -5

echo "▸ cgroup memory (is the DB inside its limit?)"
for p in $(kubectl get pods -n $NS -l app=$STS -o name); do
  printf '%s  current=' "$p"
  kubectl exec -n $NS ${p#pod/} -- cat /sys/fs/cgroup/memory.current 2>/dev/null | awk '{printf "%.0f MB  ", $1/1048576}'
  printf 'max='
  kubectl exec -n $NS ${p#pod/} -- cat /sys/fs/cgroup/memory.max 2>/dev/null | awk '{if($1=="max")print "unlimited"; else printf "%.0f MB\n", $1/1048576}'
done

echo "▸ restart history"
kubectl get pods -n $NS -l app=$STS -o jsonpath='{range .items[*]}{.metadata.name}: restarts={.status.containerStatuses[0].restartCount} lastState={.status.containerStatuses[0].lastState.terminated.reason}{"\n"}{end}'
```

```bash
chmod +x db-check.sh
./db-check.sh db mysql
./db-check.sh db mongo
./db-check.sh db redis
./db-check.sh db cassandra
./db-check.sh db neo4j
```

## The final advice

**Learn with the YAML in this file.** Understand every field, break it deliberately, watch what happens.

**Run production with an operator.** The operators exist because there are hundreds of edge cases — split-brain, partial restores, rolling upgrades with schema changes, backup verification, quorum loss — that no YAML file handles. CloudNativePG, the MongoDB operator, Spotahome's redis-operator, K8ssandra, Strimzi. Pick one per database and let it do the hard parts.

**Or don't run it on Kubernetes at all.** RDS, Cloud SQL, DynamoDB, ElastiCache, DocumentDB, MemoryStore, Keyspaces. For a small team, a managed database with a real SLA is almost always the right answer. The engineering time you save is worth more than the abstraction you lose.

**The one exception:** Cassandra. Its architecture genuinely matches Kubernetes' model better than any other database, and K8ssandra is excellent.

---

## 13.8 Checklist

- [ ] Explain why a database needs a StatefulSet and not a Deployment
- [ ] Explain why `strategy: Recreate` is mandatory for a single-RWO-PVC database
- [ ] Configure a headless Service with `publishNotReadyAddresses: true` and explain why
- [ ] Set `terminationGracePeriodSeconds` longer than the DB's real shutdown time
- [ ] Write a readiness probe that verifies the DB can actually serve, not just that the process is up
- [ ] Write a liveness probe with a timeout generous enough for a slow database
- [ ] Add a `preStop` hook that does the database's own graceful shutdown
- [ ] Size the memory setting from the **container limit**, never the node's RAM
- [ ] Use Guaranteed QoS (`requests == limits`) for production databases
- [ ] Set a PDB with a quorum-aware `minAvailable`
- [ ] Spread replicas across nodes and zones with anti-affinity and topology spread
- [ ] Take a backup, **and restore it**, and prove the data is correct
- [ ] Run a failover drill and measure the actual downtime
- [ ] Name the right operator for each database and explain what it does that YAML can't
- [ ] Explain when a managed service is the better choice

**Next → [`17-PROJECT-14-helm-gitops.md`](17-PROJECT-14-helm-gitops.md)** — packaging all of this into Helm charts and driving it with Argo CD.

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish%20Kumar%20Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn → <https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260>
🐙 GitHub → <https://github.com/3558Bhk>

*Built for engineers who learn by breaking things on purpose.*

</div>
