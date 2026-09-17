# PROJECT 13 · 🗄️ Databases — 6 Separate Mini-Projects

> **Part of the Docker Learning Path.** Previous: [`15-PROJECT-12-react-go-fullstack.md`](15-PROJECT-12-react-go-fullstack.md) — Project 12 — React + Go.
>
> 🎯 **Instructions & techniques:** MySQL · MongoDB · Redis · DynamoDB Local · Cassandra · Neo4j — each with Case 1 + Case 2, volumes, healthchecks, backups
>
> 📚 **What you learn:** How to containerise a database properly: volumes, init-once semantics, per-engine healthchecks, memory floors
>
> 🔁 **Every project here is written TWICE:**
> - **🔵 CASE 1 — a SIMPLE Dockerfile.** Easy to read, easy to get working, usually too big for production.
> - **🟢 CASE 2 — a MULTI-STAGE Dockerfile.** The production version: smaller, faster to rebuild, more secure, tests can fail the build.
>
> **Build Case 1 first**, run it, understand it — then build Case 2 and **measure the difference**. That comparison *is* the lesson.

---

# D.6 — PROJECT 13 · 🗄️ Databases (6 separate mini-projects)

**🎯 What you learn:** how to containerise a database *properly* — volumes, init scripts, healthchecks, credentials, backups, GUI tools, and the two patterns that matter:

- **CASE 1** — a simple Dockerfile: extend the official image with your schema, seed data and config.
- **CASE 2** — a multi-stage Dockerfile: **generate/compile/validate** your data in a builder stage, then ship a clean runtime stage.

> 📌 **Six completely separate mini-projects.** Do them one at a time, each in its own folder. Each is independent — you don't need the others.

| # | Mini-project | Image | Default port | GUI tool | Data path |
|---|---|---|---|---|---|
| 13.1 | **MySQL** | `mysql:8.4` | 3306 | Adminer | `/var/lib/mysql` |
| 13.2 | **MongoDB** | `mongo:7` | 27017 | Mongo Express | `/data/db` |
| 13.3 | **Redis** | `redis:7-alpine` | 6379 | Redis Insight | `/data` |
| 13.4 | **DynamoDB Local** | `amazon/dynamodb-local` | 8000 | DynamoDB Admin (npm) | `/home/dynamodblocal/data` |
| 13.5 | **Cassandra** | `cassandra:4.1` | 9042 | none built in | `/var/lib/cassandra` |
| 13.6 | **Neo4j** (graph) | `neo4j:5.26-community` | 7474 / 7687 | **Neo4j Browser** (built in) | `/data` |

### The universal database-in-Docker checklist

Apply this to **every** database, forever:

- [ ] Data lives on a **named volume**, never the container filesystem
- [ ] Credentials come from **env vars**, never hard-coded in the Dockerfile
- [ ] A **healthcheck** using the database's *own* tool (`mysqladmin ping`, `mongosh --eval`, `redis-cli ping`, …)
- [ ] Init/seed scripts mounted **read-only** into the image's designated init directory
- [ ] The port is **not published** to the internet in production (`127.0.0.1:` at most)
- [ ] Memory limits are set — databases get OOM-killed silently otherwise
- [ ] A **backup** command exists and has been *tested by restoring*
- [ ] The engine version is **pinned** (`postgres:17.2`, not `postgres:latest`) — a surprise major-version upgrade will corrupt your data directory
- [ ] You know how to run the client CLI inside the container

---
---

## 13.1 · 🐬 MySQL

```
13a-mysql/
├── Dockerfile               ← CASE 1
├── Dockerfile.multistage    ← CASE 2
├── docker-compose.yml
├── init/
│   ├── 01-schema.sql
│   ├── 02-seed.sql
│   └── 03-views.sql
├── conf/
│   └── my-custom.cnf
└── scripts/
    ├── backup.sh
    └── restore.sh
```

### `init/01-schema.sql`

```sql
CREATE DATABASE IF NOT EXISTS tasknest CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE tasknest;

CREATE TABLE IF NOT EXISTS tasks (
    id         BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    title      VARCHAR(300)  NOT NULL,
    priority   ENUM('low','medium','high') NOT NULL DEFAULT 'medium',
    done       BOOLEAN       NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP     NULL ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_done (done),
    INDEX idx_priority (priority),
    FULLTEXT INDEX ft_title (title)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS tags (
    id      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    name    VARCHAR(50) NOT NULL UNIQUE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS task_tags (
    task_id BIGINT UNSIGNED NOT NULL,
    tag_id  BIGINT UNSIGNED NOT NULL,
    PRIMARY KEY (task_id, tag_id),
    FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE,
    FOREIGN KEY (tag_id)  REFERENCES tags(id)  ON DELETE CASCADE
) ENGINE=InnoDB;
```

### `init/02-seed.sql`

```sql
USE tasknest;

INSERT INTO tasks (title, priority) VALUES
  ('Learn FROM, RUN and CMD',           'high'),
  ('Master COPY and .dockerignore',     'high'),
  ('Understand ENTRYPOINT vs CMD',      'medium'),
  ('Build a multi-stage image',         'medium'),
  ('Containerise MySQL',                'low');

INSERT INTO tags (name) VALUES ('docker'), ('basics'), ('database'), ('devops');

INSERT INTO task_tags (task_id, tag_id) VALUES
  (1,1),(1,2),(2,1),(3,1),(4,1),(5,1),(5,3);
```

### `init/03-views.sql`

```sql
USE tasknest;

CREATE OR REPLACE VIEW v_task_summary AS
SELECT t.id, t.title, t.priority, t.done, t.created_at,
       GROUP_CONCAT(g.name ORDER BY g.name SEPARATOR ',') AS tags
FROM tasks t
LEFT JOIN task_tags tt ON tt.task_id = t.id
LEFT JOIN tags g       ON g.id = tt.tag_id
GROUP BY t.id;

CREATE OR REPLACE VIEW v_stats AS
SELECT COUNT(*)                                   AS total,
       SUM(done)                                  AS done,
       SUM(NOT done)                              AS todo,
       SUM(priority='high' AND NOT done)          AS urgent_high,
       ROUND(100 * SUM(done) / NULLIF(COUNT(*),0), 1) AS completion_pct
FROM tasks;
```

### `conf/my-custom.cnf`

```ini
[mysqld]
# ---- container-friendly settings ----
bind-address            = 0.0.0.0
port                    = 3306
max_connections         = 100
character-set-server    = utf8mb4
collation-server        = utf8mb4_unicode_ci
default-time-zone       = '+00:00'

# ---- memory: keep it inside a 512 MB container limit ----
innodb_buffer_pool_size = 128M
innodb_log_file_size    = 48M
key_buffer_size         = 16M
tmp_table_size          = 16M
max_heap_table_size     = 16M

# ---- durability ----
innodb_flush_log_at_trx_commit = 1
sync_binlog                    = 1

# ---- slow query log to STDOUT so `docker logs` shows it ----
slow_query_log      = 1
long_query_time     = 1
log_slow_verbosity  = query_plan,explain
log_error_verbosity = 2

[client]
default-character-set = utf8mb4
```

### 🔵 CASE 1 — SIMPLE Dockerfile

```dockerfile
# Bake the schema + seed + config straight into the image.
FROM mysql:8.4

LABEL org.opencontainers.image.title="tasknest-mysql"

# MySQL runs *.sh / *.sql / *.sql.gz in this dir ONCE, on first init of an EMPTY data dir
COPY init/  /docker-entrypoint-initdb.d/
COPY conf/my-custom.cnf /etc/mysql/conf.d/custom.cnf

ENV MYSQL_DATABASE=tasknest \
    MYSQL_USER=app \
    MYSQL_PASSWORD=app_password \
    TZ=UTC

EXPOSE 3306

HEALTHCHECK --interval=10s --timeout=5s --start-period=40s --retries=10 \
  CMD mysqladmin ping -h 127.0.0.1 -u root -p"${MYSQL_ROOT_PASSWORD:-root}" --silent || exit 1
```

```bash
cd 13a-mysql
docker build -t mysql-simple:v1 .

docker run -d --name mysql1 -p 3306:3306 \
  -e MYSQL_ROOT_PASSWORD=root \
  -e MYSQL_DATABASE=tasknest -e MYSQL_USER=app -e MYSQL_PASSWORD=app_password \
  -v mysql1-data:/var/lib/mysql \
  mysql-simple:v1

# first init takes 20-40 s — watch it
docker logs -f mysql1 | grep -iE 'init|ready|entrypoint'

docker exec -it mysql1 mysql -uapp -papp_password tasknest -e 'SELECT * FROM v_task_summary;'
docker exec -it mysql1 mysql -uapp -papp_password tasknest -e 'SELECT * FROM v_stats\G'
docker ps --filter name=mysql1          # (healthy) after start_period
```

### 🟢 CASE 2 — MULTI-STAGE Dockerfile

Here the builder stage **generates and validates** the SQL, so a syntax error or a missing table fails the *build* rather than your first deploy.

```dockerfile
# syntax=docker/dockerfile:1

# ══════════════ STAGE 1: generate & validate the schema ══════════════
FROM mysql:8.4 AS builder

WORKDIR /build
COPY init/ ./sql/

# 1) concatenate in a deterministic order
RUN set -eux; \
    : > /build/schema-all.sql; \
    for f in $(ls /build/sql/*.sql | sort); do \
        echo "-- ===== $f ====="; cat "$f"; echo; \
    done >> /build/schema-all.sql

# 2) validate the syntax by starting a THROWAWAY server and loading it
RUN set -eux; \
    mkdir -p /tmp/validate && chown -R mysql:mysql /tmp/validate; \
    (mysqld --datadir=/tmp/validate --initialize-insecure --user=mysql >/tmp/init.log 2>&1); \
    (mysqld --datadir=/tmp/validate --user=mysql --skip-networking --socket=/tmp/v.sock >/tmp/v.log 2>&1 &) ; \
    for i in $(seq 1 60); do mysqladmin --socket=/tmp/v.sock ping >/dev/null 2>&1 && break; sleep 1; done; \
    mysql --socket=/tmp/v.sock -u root < /build/schema-all.sql; \
    mysql --socket=/tmp/v.sock -u root -e \
      "SELECT COUNT(*) AS tables_created FROM information_schema.tables WHERE table_schema='tasknest';" ; \
    mysqladmin --socket=/tmp/v.sock -u root shutdown; \
    rm -rf /tmp/validate
# ↑ if the SQL is invalid, the RUN exits non-zero and THE BUILD FAILS. 🎯

# 3) emit a fingerprint so you can detect schema drift at runtime
RUN sha256sum /build/schema-all.sql | cut -d' ' -f1 > /build/schema.sha256


# ══════════════ STAGE 2: runtime ══════════════
FROM mysql:8.4 AS runtime

ARG SCHEMA_VERSION=1.0.0
LABEL org.opencontainers.image.title="tasknest-mysql" \
      org.opencontainers.image.version="${SCHEMA_VERSION}"

# copy ONLY the validated artefacts — the throwaway datadir is discarded with stage 1
COPY --from=builder /build/schema-all.sql /docker-entrypoint-initdb.d/00-schema.sql
COPY --from=builder /build/schema.sha256  /usr/local/share/schema.sha256

COPY conf/my-custom.cnf /etc/mysql/conf.d/custom.cnf

ENV MYSQL_DATABASE=tasknest \
    TZ=UTC \
    SCHEMA_VERSION=${SCHEMA_VERSION}

EXPOSE 3306

HEALTHCHECK --interval=10s --timeout=5s --start-period=40s --retries=10 \
  CMD mysqladmin ping -h 127.0.0.1 -u root -p"${MYSQL_ROOT_PASSWORD}" --silent || exit 1
```

```bash
docker build -f Dockerfile.multistage --build-arg SCHEMA_VERSION=1.0.0 -t mysql-multi:v1 .
docker run -d --name mysql2 -p 3307:3306 \
  -e MYSQL_ROOT_PASSWORD=root -e MYSQL_DATABASE=tasknest \
  -e MYSQL_USER=app -e MYSQL_PASSWORD=app_password \
  -v mysql2-data:/var/lib/mysql mysql-multi:v1
sleep 40
docker exec mysql2 sha256sum -c /usr/local/share/schema.sha256 2>/dev/null || \
docker exec mysql2 cat /usr/local/share/schema.sha256
docker exec -it mysql2 mysql -uapp -papp_password tasknest -e 'SELECT * FROM v_stats\G'
```

> 🧪 **Prove the validation works:** add `THIS IS NOT SQL;` to `init/02-seed.sql` and rebuild Case 2 → **the build fails** at the validation step. Case 1 would have built happily and then failed at *runtime*, possibly leaving a half-initialised volume behind.

### `docker-compose.yml`

```yaml
name: mysql-learn

services:
  db:
    build:
      context: .
      dockerfile: Dockerfile.multistage
    image: tasknest-mysql:1.0.0
    container_name: mysql-db
    restart: unless-stopped
    command: ["mysqld", "--default-authentication-plugin=caching_sha2_password"]
    environment:
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD:?set in .env}
      MYSQL_DATABASE: ${MYSQL_DATABASE:-tasknest}
      MYSQL_USER: ${MYSQL_USER:-app}
      MYSQL_PASSWORD: ${MYSQL_PASSWORD:?set in .env}
    volumes:
      - mysql-data:/var/lib/mysql
      - ./conf:/etc/mysql/conf.d:ro          # live config edits without a rebuild
      - ./scripts:/scripts:ro
    ports:
      - "127.0.0.1:3306:3306"                # local only — NOT the internet
    healthcheck:
      test: ["CMD-SHELL", "mysqladmin ping -h 127.0.0.1 -u root -p\"$$MYSQL_ROOT_PASSWORD\" --silent"]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 45s
    deploy:
      resources:
        limits: { cpus: "1.0", memory: 768M }
    stop_grace_period: 60s                   # InnoDB needs time to flush
    networks: [dbnet]

  adminer:                                    # web UI for browsing the data
    image: adminer:4
    container_name: mysql-adminer
    restart: unless-stopped
    depends_on:
      db: { condition: service_healthy }
    ports: ["8081:8080"]
    environment:
      ADMINER_DEFAULT_SERVER: db
      ADMINER_DESIGN: pepa-linha
    networks: [dbnet]

volumes:
  mysql-data:
    name: mysql-learn-data

networks:
  dbnet:
```

### `scripts/backup.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
OUT="${1:-backups/mysql-$(date -u +%Y%m%d-%H%M%S).sql.gz}"
mkdir -p "$(dirname "$OUT")"
docker exec mysql-db sh -c \
  'exec mysqldump -u root -p"$MYSQL_ROOT_PASSWORD" --single-transaction --quick \
   --routines --triggers --events --databases tasknest' | gzip > "$OUT"
echo "✅ $(du -h "$OUT" | cut -f1) → $OUT"
```

### `scripts/restore.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
FILE="${1:?usage: restore.sh <file.sql.gz>}"
gunzip -c "$FILE" | docker exec -i mysql-db sh -c \
  'exec mysql -u root -p"$MYSQL_ROOT_PASSWORD"'
echo "✅ restored $FILE"
docker exec mysql-db mysql -u root -p"$MYSQL_ROOT_PASSWORD" tasknest \
  -e 'SELECT COUNT(*) AS tasks FROM tasks;'
```

### Verify & explore

```bash
docker compose up -d --build --wait
docker compose ps

# CLI inside the container
docker compose exec db mysql -uapp -p"$MYSQL_PASSWORD" tasknest -e 'SHOW TABLES;'
docker compose exec db mysql -uapp -p"$MYSQL_PASSWORD" tasknest -e 'SELECT * FROM v_task_summary\G'

# from your host (needs a mysql client)
mysql -h 127.0.0.1 -P 3306 -uapp -papp_password tasknest -e 'SELECT * FROM v_stats;'

# 🌐 http://localhost:8081  → Adminer (server: db, user: app, pass: app_password, db: tasknest)

# persistence
docker compose down && docker compose up -d --wait
docker compose exec db mysql -uapp -p"$MYSQL_PASSWORD" tasknest -e 'SELECT COUNT(*) FROM tasks;'

# backup / destroy / restore
bash scripts/backup.sh
docker compose down -v                 # ☠️ data gone
docker compose up -d --wait            # re-seeds from the init scripts
bash scripts/restore.sh backups/<file>.sql.gz
```

### MySQL gotchas

| Gotcha | Explanation |
|---|---|
| Init scripts run **only once** | `/docker-entrypoint-initdb.d/*` executes only when `/var/lib/mysql` is **empty**. Change the SQL and nothing happens until `docker compose down -v`. |
| `MYSQL_ROOT_PASSWORD` is required | The image refuses to start without it (or `MYSQL_ALLOW_EMPTY_PASSWORD=yes` / `MYSQL_RANDOM_ROOT_PASSWORD=yes`). |
| `caching_sha2_password` vs old clients | MySQL 8's default auth plugin. Older drivers fail with *"Authentication plugin cannot be loaded"* → use `mysql_native_password` or update the driver. |
| Port 3306 published = public database | Use `127.0.0.1:3306:3306`, or don't publish at all and let other services use the network name. |
| `docker stop` too fast → corruption | InnoDB needs to flush. Set `stop_grace_period: 60s` and `STOPSIGNAL SIGTERM`. |
| macOS/Windows volume performance | Bind-mounting the data dir across the VM boundary is **very** slow. Always use a **named volume** for the database. |

---
---

## 13.2 · 🍃 MongoDB

```
13b-mongodb/
├── Dockerfile
├── Dockerfile.multistage
├── docker-compose.yml
├── init/
│   ├── 01-create-user.js
│   └── 02-seed.js
└── mongo.conf
```

### `init/01-create-user.js`

```javascript
// Runs inside mongosh during the image's first-init entrypoint.
db = db.getSiblingDB('tasknest');

db.createUser({
  user: 'app',
  pwd:  'app_password',
  roles: [{ role: 'readWrite', db: 'tasknest' }]
});

db.createCollection('tasks');
db.createCollection('tags');
```

### `init/02-seed.js`

```javascript
db = db.getSiblingDB('tasknest');

db.tasks.insertMany([
  { title: 'Learn FROM, RUN and CMD',       priority: 'high',   tags: ['docker','basics'], done: false, created_at: new Date() },
  { title: 'Master COPY and .dockerignore', priority: 'high',   tags: ['docker'],          done: false, created_at: new Date() },
  { title: 'Understand ENTRYPOINT vs CMD',  priority: 'medium', tags: ['docker'],          done: true,  created_at: new Date() },
  { title: 'Model documents in MongoDB',    priority: 'medium', tags: ['database','nosql'],done: false, created_at: new Date() },
]);

db.tasks.createIndex({ done: 1, priority: 1 });
db.tasks.createIndex({ title: 'text' });
db.tasks.createIndex({ created_at: -1 });

print('✅ seeded ' + db.tasks.countDocuments({}) + ' tasks');
```

### `mongo.conf`

```yaml
storage:
  dbPath: /data/db
  journal:
    enabled: true
  wiredTiger:
    engineConfig:
      cacheSizeGB: 0.25          # keep inside a 512 MB container limit

systemLog:
  destination: file
  logAppend: true
  path: /dev/stdout              # 🔑 logs to stdout so `docker logs` works

net:
  port: 27017
  bindIp: 0.0.0.0

security:
  authorization: enabled         # 🔑 require authentication

processManagement:
  fork: false                    # must stay in the FOREGROUND in a container
```

### 🔵 CASE 1 — SIMPLE

```dockerfile
FROM mongo:7

LABEL org.opencontainers.image.title="tasknest-mongo"

COPY init/ /docker-entrypoint-initdb.d/
COPY mongo.conf /etc/mongo.conf

ENV MONGO_INITDB_ROOT_USERNAME=root \
    MONGO_INITDB_ROOT_PASSWORD=root_password \
    MONGO_INITDB_DATABASE=tasknest

EXPOSE 27017

CMD ["mongod", "--config", "/etc/mongo.conf"]

HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=6 \
  CMD mongosh --quiet --eval "db.adminCommand('ping').ok" || exit 1
```

```bash
docker build -t mongo-simple:v1 .
docker run -d --name mongo1 -p 27017:27017 \
  -e MONGO_INITDB_ROOT_USERNAME=root -e MONGO_INITDB_ROOT_PASSWORD=root_password \
  -v mongo1-data:/data/db mongo-simple:v1

docker logs -f mongo1 | grep -iE 'init|seed|waiting for connections'

docker exec -it mongo1 mongosh -u root -p root_password --authenticationDatabase admin tasknest \
  --eval 'db.tasks.find({}, {title:1, priority:1, _id:0}).toArray()'
docker exec -it mongo1 mongosh -u app -p app_password --authenticationDatabase tasknest tasknest \
  --eval 'db.tasks.countDocuments()'
```

### 🟢 CASE 2 — MULTI-STAGE

The builder stage **validates the seed scripts and produces a binary archive** of the initial dataset, so the runtime image starts with data already imported (no JS execution at boot) and any syntax error fails the build.

```dockerfile
# syntax=docker/dockerfile:1

# ══════════════ STAGE 1: validate & pre-bake the dataset ══════════════
FROM mongo:7 AS builder

ENV MONGO_INITDB_ROOT_USERNAME=builder \
    MONGO_INITDB_ROOT_PASSWORD=builder

WORKDIR /build
COPY init/ ./init/
COPY mongo.conf ./mongo.conf

# start a THROWAWAY mongod on a temporary dbpath, load the seed, export it, shut down
RUN set -eux; \
    mkdir -p /tmp/build-data /tmp/dump; \
    mongod --dbpath /tmp/build-data --bind_ip 127.0.0.1 --port 27099 \
           --logpath /tmp/mongod.log --fork; \
    for i in $(seq 1 30); do mongosh --quiet --port 27099 --eval 'db.adminCommand("ping")' >/dev/null 2>&1 && break; sleep 1; done; \
    mongosh --quiet --port 27099 tasknest --file /build/init/02-seed.js; \
    COUNT=$(mongosh --quiet --port 27099 tasknest --eval 'print(db.tasks.countDocuments({}))'); \
    echo "validated: ${COUNT} documents"; \
    test "$COUNT" -ge 1; \
    mongodump --port 27099 --db tasknest --out /tmp/dump; \
    mongosh --quiet --port 27099 --eval 'db.adminCommand({shutdown:1})' || true; \
    rm -rf /tmp/build-data

# record a fingerprint of the schema/seed for drift detection
RUN find /build/init -type f -exec sha256sum {} + | sort > /build/seed.sha256


# ══════════════ STAGE 2: runtime ══════════════
FROM mongo:7 AS runtime

ARG SCHEMA_VERSION=1.0.0
LABEL org.opencontainers.image.title="tasknest-mongo" \
      org.opencontainers.image.version="${SCHEMA_VERSION}"

# bring ONLY the validated dump + fingerprint (the throwaway dbpath is discarded)
COPY --from=builder /tmp/dump            /docker-entrypoint-initdb.d/dump
COPY --from=builder /build/seed.sha256   /usr/local/share/seed.sha256
COPY --from=builder /build/init/01-create-user.js /docker-entrypoint-initdb.d/01-create-user.js

# a tiny restore script the official entrypoint will run on first init
RUN printf '%s\n' '#!/bin/bash' 'set -e' \
      'mongorestore --drop /docker-entrypoint-initdb.d/dump' \
      'echo "✅ restored pre-baked dataset"' \
      > /docker-entrypoint-initdb.d/03-restore.sh \
 && chmod +x /docker-entrypoint-initdb.d/03-restore.sh

COPY mongo.conf /etc/mongo.conf

ENV MONGO_INITDB_DATABASE=tasknest

EXPOSE 27017
STOPSIGNAL SIGTERM

HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=6 \
  CMD mongosh --quiet --eval "db.adminCommand('ping').ok" || exit 1

CMD ["mongod", "--config", "/etc/mongo.conf"]
```

### `docker-compose.yml`

```yaml
name: mongo-learn

services:
  db:
    build: { context: ., dockerfile: Dockerfile.multistage }
    image: tasknest-mongo:1.0.0
    container_name: mongo-db
    restart: unless-stopped
    environment:
      MONGO_INITDB_ROOT_USERNAME: ${MONGO_USER:-root}
      MONGO_INITDB_ROOT_PASSWORD: ${MONGO_PASSWORD:?set in .env}
    volumes:
      - mongo-data:/data/db
      - ./scripts:/scripts:ro
    ports: ["127.0.0.1:27017:27017"]
    healthcheck:
      test: ["CMD-SHELL", "mongosh --quiet -u $$MONGO_INITDB_ROOT_USERNAME -p $$MONGO_INITDB_ROOT_PASSWORD --authenticationDatabase admin --eval 'db.adminCommand(\"ping\").ok' || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 8
      start_period: 30s
    deploy:
      resources: { limits: { cpus: "1.0", memory: 768M } }
    stop_grace_period: 30s
    networks: [dbnet]

  mongo-express:
    image: mongo-express:1
    container_name: mongo-ui
    restart: unless-stopped
    depends_on:
      db: { condition: service_healthy }
    environment:
      ME_CONFIG_MONGODB_ADMINUSERNAME: ${MONGO_USER:-root}
      ME_CONFIG_MONGODB_ADMINPASSWORD: ${MONGO_PASSWORD:?set in .env}
      ME_CONFIG_MONGODB_URL: mongodb://${MONGO_USER:-root}:${MONGO_PASSWORD:?set in .env}@db:27017/
      ME_CONFIG_BASICAUTH: "false"
    ports: ["8082:8081"]
    networks: [dbnet]

volumes:
  mongo-data: { name: mongo-learn-data }
networks:
  dbnet:
```

### Verify

```bash
docker compose up -d --build --wait
docker compose ps

docker compose exec db mongosh -u root -p "$MONGO_PASSWORD" --authenticationDatabase admin tasknest \
  --eval 'db.tasks.find({}, {title:1,priority:1,done:1,_id:0}).toArray()'

docker compose exec db mongosh -u root -p "$MONGO_PASSWORD" --authenticationDatabase admin tasknest \
  --eval 'db.tasks.aggregate([{$group:{_id:"$priority", n:{$sum:1}}}]).toArray()'

# 🌐 http://localhost:8082 → Mongo Express

# backups
docker compose exec db mongodump -u root -p "$MONGO_PASSWORD" --authenticationDatabase admin \
  --db tasknest --archive=/tmp/dump.archive
docker compose cp db:/tmp/dump.archive ./backups/dump-$(date +%s).archive
docker compose exec db mongorestore -u root -p "$MONGO_PASSWORD" --authenticationDatabase admin \
  --archive=/tmp/dump.archive --drop
```

### MongoDB gotchas

| Gotcha | Explanation |
|---|---|
| Auth is **off by default** | The official image starts with no authentication unless `MONGO_INITDB_ROOT_USERNAME` is set or your config has `security.authorization: enabled`. An open 27017 on the internet gets mined within hours. |
| `--authenticationDatabase admin` | The root user lives in `admin`, not in your app database. Forgetting this is the #1 "Authentication failed" cause. |
| WiredTiger cache | Defaults to ~50% of **host** RAM (min 256 MB) — it will blow past your container limit and get OOM-killed. Set `cacheSizeGB` explicitly. |
| `fork: true` kills the container | The main process must stay in the **foreground**. |
| Logs go to a file by default | Point `systemLog.path` at `/dev/stdout` so `docker logs` works. |
| Init scripts run once | Same as MySQL — only on an empty `/data/db`. |
| Replica set for transactions | Multi-document transactions require a replica set, even a single-node one: `--replSet rs0` then `rs.initiate()`. |

---
---

## 13.3 · 🔴 Redis

```
13c-redis/
├── Dockerfile
├── Dockerfile.multistage
├── docker-compose.yml
├── redis.conf
└── module/            ← CASE 2 only (an example Redis module)
    └── hello.c
```

### `redis.conf`

```conf
# ---- network ----
bind 0.0.0.0
port 6379
protected-mode yes
requirepass changeme-strong-password
tcp-keepalive 60
timeout 300

# ---- persistence: AOF (durable) + RDB snapshots ----
appendonly yes
appendfsync everysec
appendfilename "appendonly.aof"
save 900 1
save 300 10
save 60 10000
dir /data

# ---- memory: MUST fit inside the container limit ----
maxmemory 128mb
maxmemory-policy allkeys-lru
maxmemory-samples 5

# ---- performance ----
maxclients 200
hz 10
dynamic-hz yes

# ---- security hardening ----
rename-command FLUSHALL ""
rename-command FLUSHDB  ""
rename-command CONFIG   "CONFIG_b8f2a91c"
rename-command KEYS     ""

# ---- logging to stdout ----
loglevel notice
logfile ""
```

### 🔵 CASE 1 — SIMPLE

```dockerfile
FROM redis:7-alpine

LABEL org.opencontainers.image.title="tasknest-redis"

COPY redis.conf /usr/local/etc/redis/redis.conf

# preload some keys on first start
COPY <<'EOF' /data-init.sh
#!/bin/sh
set -e
sleep 2
redis-cli -a "$REDIS_PASSWORD" SET app:name  "TaskNest"   >/dev/null
redis-cli -a "$REDIS_PASSWORD" SET app:version "1.0.0"    >/dev/null
redis-cli -a "$REDIS_PASSWORD" LPUSH app:boot "container started" >/dev/null
echo "✅ seed keys written"
EOF
RUN chmod +x /data-init.sh

EXPOSE 6379

HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=5 \
  CMD redis-cli -a "$REDIS_PASSWORD" --no-auth-warning ping | grep -q PONG || exit 1

CMD ["sh", "-c", "/data-init.sh & exec redis-server /usr/local/etc/redis/redis.conf"]
```

```bash
docker build -t redis-simple:v1 .
docker run -d --name redis1 -p 6379:6379 \
  -e REDIS_PASSWORD=changeme-strong-password \
  -v redis1-data:/data redis-simple:v1

docker exec -it redis1 redis-cli -a changeme-strong-password --no-auth-warning
  127.0.0.1:6379> INFO server | head -8
  127.0.0.1:6379> GET app:name
  127.0.0.1:6379> SET counter 1
  127.0.0.1:6379> INCR counter
  127.0.0.1:6379> CONFIG GET maxmemory        # ← renamed! will fail
  127.0.0.1:6379> FLUSHALL                     # ← disabled! will fail
  127.0.0.1:6379> exit
```

### 🟢 CASE 2 — MULTI-STAGE (compile a Redis module)

A realistic multi-stage use for Redis: **build a C module** in a toolchain stage, then ship only the `.so`.

### `module/hello.c`

```c
/* A minimal Redis module: HELLO.WORLD <name> -> "Hello, <name>!" */
#include "../../redismodule.h"   /* or download it in the Dockerfile */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int Hello_World(RedisModuleCtx *ctx, RedisModuleString **argv, int argc) {
    if (argc != 2) return RedisModule_WrongArity(ctx);
    const char *name = RedisModule_StringPtrLen(argv[1], NULL);
    char buf[256];
    snprintf(buf, sizeof buf, "Hello, %s!", name);
    return RedisModule_ReplyWithSimpleString(ctx, buf);
}

int RedisModule_OnLoad(RedisModuleCtx *ctx, RedisModuleString **argv, int argc) {
    if (RedisModule_Init(ctx, "helloworld", 1, REDISMODULE_APIVER_1) == REDISMODULE_ERR)
        return REDISMODULE_ERR;
    if (RedisModule_CreateCommand(ctx, "hello.world", Hello_World, "readonly", 0, 0, 0)
        == REDISMODULE_ERR)
        return REDISMODULE_ERR;
    (void)argv; (void)argc;
    return REDISMODULE_OK;
}
```

```dockerfile
# syntax=docker/dockerfile:1

# ══════════════ STAGE 1: compile the module ══════════════
FROM alpine:3.22 AS module-build

RUN apk add --no-cache build-base curl
WORKDIR /build

# the official module API header
RUN curl -fsSL -o redismodule.h \
      https://raw.githubusercontent.com/redis/redis/7.4/src/redismodule.h

COPY module/hello.c ./hello.c
RUN sed -i 's#"../../redismodule.h"#"redismodule.h"#' hello.c \
 && cc -shared -fPIC -O2 -std=c11 -o /build/helloworld.so hello.c \
 && ls -lh /build/helloworld.so


# ══════════════ STAGE 2: validate it loads ══════════════
FROM redis:7-alpine AS module-test
COPY --from=module-build /build/helloworld.so /usr/local/lib/redis/modules/
RUN redis-server --loadmodule /usr/local/lib/redis/modules/helloworld.so \
      --daemonize yes --port 6399 \
 && sleep 2 \
 && redis-cli -p 6399 hello.world Docker | grep -q "Hello, Docker!" \
 && echo "✅ module validated" \
 && redis-cli -p 6399 shutdown nosave || true


# ══════════════ STAGE 3: runtime ══════════════
FROM redis:7-alpine AS runtime

ARG VERSION=1.0.0
LABEL org.opencontainers.image.title="tasknest-redis" \
      org.opencontainers.image.version="${VERSION}"

# only the compiled artefact survives — no gcc, no source, no headers
COPY --from=module-build /build/helloworld.so /usr/local/lib/redis/modules/helloworld.so
COPY redis.conf /usr/local/etc/redis/redis.conf

RUN addgroup -S -g 101 redis-app 2>/dev/null || true \
 && chown -R redis:redis /data /usr/local/etc/redis

EXPOSE 6379
STOPSIGNAL SIGTERM
VOLUME ["/data"]
USER redis

HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=5 \
  CMD redis-cli -a "$REDIS_PASSWORD" --no-auth-warning ping | grep -q PONG || exit 1

CMD ["redis-server", "/usr/local/etc/redis/redis.conf", \
     "--loadmodule", "/usr/local/lib/redis/modules/helloworld.so"]
```

> 📌 If you don't want to write C, Case 2 still applies — use the builder stage to **pre-generate an RDB/AOF dataset**, or to download and checksum a vetted third-party module (RedisBloom, RediSearch). The pattern is identical: *produce and validate an artefact, then ship only the artefact.*

### `docker-compose.yml`

```yaml
name: redis-learn

services:
  cache:
    build: { context: ., dockerfile: Dockerfile.multistage, target: runtime }
    image: tasknest-redis:1.0.0
    container_name: redis-cache
    restart: unless-stopped
    command: ["redis-server", "/usr/local/etc/redis/redis.conf"]
    environment:
      REDIS_PASSWORD: ${REDIS_PASSWORD:?set in .env}
    volumes:
      - redis-data:/data
    ports: ["127.0.0.1:6379:6379"]
    healthcheck:
      test: ["CMD-SHELL", "redis-cli -a \"$$REDIS_PASSWORD\" --no-auth-warning ping | grep -q PONG"]
      interval: 10s
      timeout: 3s
      retries: 5
    deploy:
      resources: { limits: { cpus: "0.5", memory: 192M } }   # > maxmemory in redis.conf!
    read_only: true
    tmpfs: [/tmp:size=8M]
    cap_drop: [ALL]
    security_opt: ["no-new-privileges:true"]
    stop_grace_period: 20s
    networks: [cachenet]

volumes:
  redis-data: { name: redis-learn-data }
networks:
  cachenet:
```

### Verify

```bash
docker compose up -d --build --wait
docker compose ps
docker compose exec cache redis-cli -a "$REDIS_PASSWORD" --no-auth-warning INFO memory | grep -E 'used_memory_human|maxmemory_human|maxmemory_policy'
docker compose exec cache redis-cli -a "$REDIS_PASSWORD" --no-auth-warning hello.world Vijayawada
docker compose exec cache redis-cli -a "$REDIS_PASSWORD" --no-auth-warning CONFIG GET maxmemory   # fails — renamed ✅

# persistence: write, restart, read
docker compose exec cache redis-cli -a "$REDIS_PASSWORD" --no-auth-warning SET survive "yes"
docker compose restart cache && sleep 5
docker compose exec cache redis-cli -a "$REDIS_PASSWORD" --no-auth-warning GET survive     # "yes" ✅

# backup = just copy the AOF/RDB out of the volume
docker compose exec cache redis-cli -a "$REDIS_PASSWORD" --no-auth-warning BGREWRITEAOF
docker run --rm -v redis-learn-data:/data -v "$(pwd)/backups:/backup" alpine \
  sh -c 'cp /data/appendonly.aof.* /backup/ 2>/dev/null; cp /data/dump.rdb /backup/ 2>/dev/null; ls -lh /backup'
```

### Redis gotchas

| Gotcha | Explanation |
|---|---|
| `maxmemory` vs container limit | Redis's `maxmemory` must be **lower** than the container's `--memory`, or the kernel OOM-kills it (exit 137) before Redis can evict. Leave ~40% headroom for replication buffers and fragmentation. |
| No auth by default | `protected-mode yes` only helps when no `bind` is configured. Set `requirepass`. |
| Dangerous commands | `FLUSHALL`, `CONFIG`, `KEYS`, `DEBUG` — disable with `rename-command X ""`. `KEYS *` on a big DB **blocks the single-threaded server**. Use `SCAN`. |
| AOF vs RDB | AOF (`appendonly yes`) = durable, bigger, slower. RDB (`save ...`) = compact snapshots, can lose recent writes. Use both. |
| Data dir must be a volume | Without `-v ...:/data`, a restart loses everything. |
| Transparent Huge Pages | Redis warns at startup. Disable on the host: `echo never > /sys/kernel/mm/transparent_hugepage/enabled`. |
| Single-threaded | One slow command blocks everything. Never `O(N)` on a big keyspace in production. |

---
---

## 13.4 · ⚡ DynamoDB Local

> DynamoDB is an AWS managed service — you can't run the real thing in Docker. AWS publishes **DynamoDB Local**, a Java-based emulator with the same API. Perfect for development and CI.

```
13d-dynamodb/
├── Dockerfile
├── Dockerfile.multistage
├── docker-compose.yml
└── init/
    ├── 01-create-tables.sh
    └── 02-seed.sh
```

### `init/01-create-tables.sh`

```bash
#!/bin/sh
set -eu
ENDPOINT="${ENDPOINT:-http://localhost:8000}"
REGION="${AWS_REGION:-local}"

echo "▶ creating tables at $ENDPOINT"

aws dynamodb create-table \
  --endpoint-url "$ENDPOINT" --region "$REGION" \
  --table-name tasks \
  --attribute-definitions \
      AttributeName=pk,AttributeType=S \
      AttributeName=sk,AttributeType=S \
      AttributeName=gsi1pk,AttributeType=S \
  --key-schema \
      AttributeName=pk,KeyType=HASH \
      AttributeName=sk,KeyType=RANGE \
  --global-secondary-indexes '[
      {"IndexName":"gsi1","KeySchema":[
          {"AttributeName":"gsi1pk","KeyType":"HASH"},
          {"AttributeName":"sk","KeyType":"RANGE"}],
       "Projection":{"ProjectionType":"ALL"}}]' \
  --billing-mode PAY_PER_REQUEST \
  || echo "  (table 'tasks' may already exist)"

aws dynamodb create-table \
  --endpoint-url "$ENDPOINT" --region "$REGION" \
  --table-name users \
  --attribute-definitions AttributeName=userId,AttributeType=S \
  --key-schema AttributeName=userId,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  || echo "  (table 'users' may already exist)"

aws dynamodb list-tables --endpoint-url "$ENDPOINT" --region "$REGION"
echo "✅ tables ready"
```

### `init/02-seed.sh`

```bash
#!/bin/sh
set -eu
ENDPOINT="${ENDPOINT:-http://localhost:8000}"
REGION="${AWS_REGION:-local}"

aws dynamodb batch-write-item --endpoint-url "$ENDPOINT" --region "$REGION" \
  --request-items '{
    "tasks": [
      {"PutRequest":{"Item":{
        "pk":{"S":"USER#1"},"sk":{"S":"TASK#1"},
        "title":{"S":"Learn FROM, RUN and CMD"},"priority":{"S":"high"},
        "done":{"BOOL":false},"gsi1pk":{"S":"STATUS#open"}}}},
      {"PutRequest":{"Item":{
        "pk":{"S":"USER#1"},"sk":{"S":"TASK#2"},
        "title":{"S":"Master single-table design"},"priority":{"S":"medium"},
        "done":{"BOOL":false},"gsi1pk":{"S":"STATUS#open"}}}},
      {"PutRequest":{"Item":{
        "pk":{"S":"USER#1"},"sk":{"S":"TASK#3"},
        "title":{"S":"Containerise DynamoDB Local"},"priority":{"S":"low"},
        "done":{"BOOL":true},"gsi1pk":{"S":"STATUS#done"}}}}
    ]}'

aws dynamodb scan --endpoint-url "$ENDPOINT" --region "$REGION" \
  --table-name tasks --select COUNT
echo "✅ seeded"
```

### 🔵 CASE 1 — SIMPLE

```dockerfile
# The official image is a JVM app. We add the AWS CLI so init scripts can run.
FROM amazon/dynamodb-local:2.5.2

USER root
# the base image is Amazon Linux-based; python3 + pip give us the AWS CLI
RUN yum install -y python3 python3-pip which \
 && pip3 install --no-cache-dir awscli \
 && yum clean all && rm -rf /var/cache/yum

WORKDIR /home/dynamodblocal

COPY init/ /init/
RUN chmod +x /init/*.sh

ENV AWS_REGION=local \
    AWS_ACCESS_KEY_ID=local \
    AWS_SECRET_ACCESS_KEY=local \
    ENDPOINT=http://localhost:8000

EXPOSE 8000

HEALTHCHECK --interval=15s --timeout=5s --start-period=20s --retries=5 \
  CMD aws dynamodb list-tables --endpoint-url http://localhost:8000 --region local >/dev/null || exit 1

# -sharedDb = one database file for all credentials (essential for dev)
# -dbPath   = persist to a volume
CMD ["-jar", "DynamoDBLocal.jar", "-sharedDb", "-dbPath", "/home/dynamodblocal/data", "-port", "8000"]
```

```bash
docker build -t ddb-simple:v1 .
docker run -d --name ddb1 -p 8000:8000 -v ddb1-data:/home/dynamodblocal/data ddb-simple:v1
sleep 10

# run the init scripts from your host (needs the aws cli) OR inside the container:
docker exec ddb1 /init/01-create-tables.sh
docker exec ddb1 /init/02-seed.sh

docker exec ddb1 aws dynamodb list-tables --endpoint-url http://localhost:8000 --region local
docker exec ddb1 aws dynamodb scan --table-name tasks --endpoint-url http://localhost:8000 --region local
```

### 🟢 CASE 2 — MULTI-STAGE

```dockerfile
# syntax=docker/dockerfile:1

# ══════════════ STAGE 1: build a small CLI toolkit ══════════════
FROM python:3.13-alpine AS toolchain
RUN pip install --no-cache-dir --prefix=/install awscli==1.36.27
# → /install now holds a self-contained AWS CLI we can drop into any image


# ══════════════ STAGE 2: validate the schema scripts ══════════════
FROM amazon/dynamodb-local:2.5.2 AS validate
USER root
COPY --from=toolchain /install /usr/local
COPY init/ /init/
RUN chmod +x /init/*.sh

# boot a throwaway DynamoDB, run the real scripts against it, assert the result
RUN set -eux; \
    mkdir -p /tmp/ddb; \
    (java -jar DynamoDBLocal.jar -inMemory -port 8001 &) ; \
    for i in $(seq 1 40); do \
      aws dynamodb list-tables --endpoint-url http://localhost:8001 --region local >/dev/null 2>&1 && break; \
      sleep 1; done; \
    ENDPOINT=http://localhost:8001 /init/01-create-tables.sh; \
    ENDPOINT=http://localhost:8001 /init/02-seed.sh; \
    COUNT=$(aws dynamodb scan --table-name tasks --endpoint-url http://localhost:8001 \
              --region local --select COUNT --query Count --output text); \
    echo "validated: ${COUNT} items"; \
    test "${COUNT}" -ge 3; \
    pkill -f DynamoDBLocal.jar || true


# ══════════════ STAGE 3: runtime ══════════════
FROM amazon/dynamodb-local:2.5.2 AS runtime

ARG VERSION=1.0.0
LABEL org.opencontainers.image.title="tasknest-dynamodb-local" \
      org.opencontainers.image.version="${VERSION}"

USER root
# bring in ONLY the validated CLI + scripts — no pip cache, no build deps
COPY --from=toolchain /install /usr/local
COPY --from=validate  /init    /init
RUN chmod +x /init/*.sh \
 && mkdir -p /home/dynamodblocal/data \
 && chown -R dynamodblocal:dynamodblocal /home/dynamodblocal/data

USER dynamodblocal
WORKDIR /home/dynamodblocal

ENV AWS_REGION=local \
    AWS_ACCESS_KEY_ID=local \
    AWS_SECRET_ACCESS_KEY=local \
    ENDPOINT=http://localhost:8000

EXPOSE 8000
STOPSIGNAL SIGTERM
VOLUME ["/home/dynamodblocal/data"]

HEALTHCHECK --interval=15s --timeout=5s --start-period=25s --retries=5 \
  CMD aws dynamodb list-tables --endpoint-url http://localhost:8000 --region local >/dev/null || exit 1

CMD ["-jar", "DynamoDBLocal.jar", "-sharedDb", "-dbPath", "/home/dynamodblocal/data", "-port", "8000"]
```

### `docker-compose.yml` (with the NoSQL Workbench-friendly admin UI)

```yaml
name: ddb-learn

services:
  dynamodb:
    build: { context: ., dockerfile: Dockerfile.multistage, target: runtime }
    image: tasknest-dynamodb:1.0.0
    container_name: ddb
    restart: unless-stopped
    volumes:
      - ddb-data:/home/dynamodblocal/data
    ports: ["127.0.0.1:8000:8000"]
    environment:
      AWS_REGION: local
      AWS_ACCESS_KEY_ID: local
      AWS_SECRET_ACCESS_KEY: local
    healthcheck:
      test: ["CMD-SHELL", "aws dynamodb list-tables --endpoint-url http://localhost:8000 --region local >/dev/null"]
      interval: 15s
      timeout: 5s
      retries: 5
      start_period: 25s
    deploy:
      resources: { limits: { cpus: "1.0", memory: 512M } }
    networks: [ddbnet]

  # one-shot: creates tables + seeds, then exits
  init:
    image: tasknest-dynamodb:1.0.0
    container_name: ddb-init
    depends_on:
      dynamodb: { condition: service_healthy }
    entrypoint: ["/bin/sh", "-c"]
    command:
      - |
        ENDPOINT=http://dynamodb:8000 /init/01-create-tables.sh
        ENDPOINT=http://dynamodb:8000 /init/02-seed.sh
    environment:
      AWS_REGION: local
      AWS_ACCESS_KEY_ID: local
      AWS_SECRET_ACCESS_KEY: local
    restart: "no"
    networks: [ddbnet]

  admin:                       # 🌐 web UI for DynamoDB Local
    image: aaronshaf/dynamodb-admin:4
    container_name: ddb-admin
    restart: unless-stopped
    depends_on:
      init: { condition: service_completed_successfully }
    environment:
      DYNAMO_ENDPOINT: http://dynamodb:8000
      AWS_REGION: local
      AWS_ACCESS_KEY_ID: local
      AWS_SECRET_ACCESS_KEY: local
    ports: ["8083:8001"]
    networks: [ddbnet]

volumes:
  ddb-data: { name: ddb-learn-data }
networks:
  ddbnet:
```

```bash
docker compose up -d --build --wait
docker compose logs init                    # ✅ tables ready / ✅ seeded
docker compose ps                           # init shows Exited (0) — that's CORRECT
# 🌐 http://localhost:8083 → DynamoDB Admin UI
docker compose exec dynamodb aws dynamodb scan --table-name tasks \
  --endpoint-url http://localhost:8000 --region local
```

> 🔑 Note `depends_on: { init: { condition: service_completed_successfully } }` — Compose waits for a **one-shot job to finish successfully** before starting the next service. This is how you run migrations/init jobs in order.

### DynamoDB Local gotchas

| Gotcha | Explanation |
|---|---|
| `-sharedDb` | Without it, tables are scoped per (access key, region) pair and your app won't see what your init script created. **Always use `-sharedDb` in dev.** |
| `-inMemory` vs `-dbPath` | `-inMemory` loses everything on restart (great for CI); `-dbPath` persists to a volume. |
| It's a JVM | Idle ~250–400 MB. Give it ≥512 MB or it gets OOM-killed. |
| Fake credentials are fine | Any non-empty access key/secret works. But your SDK **requires** something — set `AWS_ACCESS_KEY_ID=local`. |
| `endpoint_url` everywhere | Every SDK call must point at `http://dynamodb:8000`, or it hits **real AWS** and bills you. Make it an env var and assert it in tests. |
| Feature gaps | No IAM policies, no streams retention guarantees, no global tables, no transactions across regions, and some limits differ. Never treat "works locally" as "works on AWS". |
| File ownership | The base image runs as `dynamodblocal` (uid 1000); the data dir must be writable by it. |

---
---

## 13.5 · 👁️ Cassandra

```
13e-cassandra/
├── Dockerfile
├── Dockerfile.multistage
├── docker-compose.yml
└── init/
    ├── 01-schema.cql
    └── 02-seed.cql
```

### `init/01-schema.cql`

```cql
-- 🔑 Cassandra is designed around QUERIES, not entities. One table per query pattern.
CREATE KEYSPACE IF NOT EXISTS tasknest
  WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1}
  AND durable_writes = true;

USE tasknest;

-- query: "give me all tasks for a user, newest first"
CREATE TABLE IF NOT EXISTS tasks_by_user (
    user_id    text,
    created_at timestamp,
    task_id    timeuuid,
    title      text,
    priority   text,
    done       boolean,
    PRIMARY KEY ((user_id), created_at, task_id)
) WITH CLUSTERING ORDER BY (created_at DESC, task_id ASC);

-- query: "give me one task by id"
CREATE TABLE IF NOT EXISTS task_by_id (
    task_id    timeuuid PRIMARY KEY,
    user_id    text,
    title      text,
    priority   text,
    done       boolean,
    created_at timestamp
);

-- query: "give me all OPEN high-priority tasks" (denormalised on purpose)
CREATE TABLE IF NOT EXISTS open_tasks_by_priority (
    priority   text,
    task_id    timeuuid,
    user_id    text,
    title      text,
    created_at timestamp,
    PRIMARY KEY ((priority), task_id)
);
```

### `init/02-seed.cql`

```cql
USE tasknest;

INSERT INTO tasks_by_user (user_id, created_at, task_id, title, priority, done)
VALUES ('u1', toTimestamp(now()), now(), 'Learn FROM, RUN and CMD', 'high', false);
INSERT INTO tasks_by_user (user_id, created_at, task_id, title, priority, done)
VALUES ('u1', toTimestamp(now()), now(), 'Model queries in Cassandra', 'medium', false);
INSERT INTO tasks_by_user (user_id, created_at, task_id, title, priority, done)
VALUES ('u1', toTimestamp(now()), now(), 'Understand the partition key', 'high', true);

INSERT INTO open_tasks_by_priority (priority, task_id, user_id, title, created_at)
VALUES ('high', now(), 'u1', 'Learn FROM, RUN and CMD', toTimestamp(now()));
INSERT INTO open_tasks_by_priority (priority, task_id, user_id, title, created_at)
VALUES ('high', now(), 'u1', 'Understand the partition key', toTimestamp(now()));
```

### 🔵 CASE 1 — SIMPLE

```dockerfile
FROM cassandra:4.1

LABEL org.opencontainers.image.title="tasknest-cassandra"

COPY init/ /init/

# a tiny script that waits for the node, then applies the CQL
COPY <<'EOF' /init/apply-schema.sh
#!/bin/bash
set -e
echo "▶ waiting for Cassandra to accept CQL…"
until cqlsh -u cassandra -p "$CASSANDRA_PASSWORD" --no-color -e "SHOW VERSION" localhost >/dev/null 2>&1; do
  sleep 3
done
echo "▶ applying schema"
cqlsh -u cassandra -p "$CASSANDRA_PASSWORD" --no-color -f /init/01-schema.cql localhost
echo "▶ seeding data"
cqlsh -u cassandra -p "$CASSANDRA_PASSWORD" --no-color -f /init/02-seed.cql   localhost
echo "✅ schema ready"
EOF
RUN chmod +x /init/apply-schema.sh

ENV CASSANDRA_USER=cassandra \
    CASSANDRA_PASSWORD=cassandra_password \
    CASSANDRA_CLUSTER_NAME=tasknest-cluster \
    CASSANDRA_DC=dc1 \
    CASSANDRA_RACK=rack1 \
    MAX_HEAP_SIZE=512M \
    HEAP_NEWSIZE=128M

EXPOSE 7000 7001 7199 9042 9160

HEALTHCHECK --interval=20s --timeout=10s --start-period=90s --retries=10 \
  CMD cqlsh -u cassandra -p "$CASSANDRA_PASSWORD" --no-color -e "SELECT now() FROM system.local" localhost >/dev/null || exit 1
```

```bash
docker build -t cass-simple:v1 .
docker run -d --name cass1 -p 9042:9042 \
  -e CASSANDRA_PASSWORD=cassandra_password \
  -v cass1-data:/var/lib/cassandra \
  cass-simple:v1

# Cassandra takes 60-120 s to boot — be patient
docker logs -f cass1 | grep -iE 'startup complete|Starting listening'
docker exec cass1 /init/apply-schema.sh

docker exec -it cass1 cqlsh -u cassandra -p cassandra_password localhost
  cqlsh> DESCRIBE KEYSPACES;
  cqlsh> USE tasknest;
  cqlsh> DESCRIBE TABLES;
  cqlsh> SELECT user_id, title, priority, done FROM tasks_by_user WHERE user_id='u1';
  cqlsh> SELECT * FROM open_tasks_by_priority WHERE priority='high';
  cqlsh> exit
```

> ⚠️ Notice the last two queries: **both must specify the full partition key.** Try `SELECT * FROM tasks_by_user;` without a `WHERE` — Cassandra allows it but warns, and on a large cluster it will time out. That's the Cassandra mental model: *design the table for the query*.

### 🟢 CASE 2 — MULTI-STAGE

Validate the CQL against a **disposable cluster** during the build, and ship a versioned, idempotent migration set.

```dockerfile
# syntax=docker/dockerfile:1

# ══════════════ STAGE 1: validate the schema against a real node ══════════════
FROM cassandra:4.1 AS validate

ENV MAX_HEAP_SIZE=512M HEAP_NEWSIZE=128M
WORKDIR /build
COPY init/ ./init/

RUN set -eux; \
    mkdir -p /tmp/cass; \
    (cassandra -R -f -Dcassandra.start_rpc=false \
        -Dcassandra.load_ring_state=false >/tmp/cass.log 2>&1 &) ; \
    for i in $(seq 1 90); do \
      cqlsh --no-color -e "SHOW VERSION" localhost >/dev/null 2>&1 && break; sleep 2; done; \
    cqlsh --no-color -f /build/init/01-schema.cql localhost; \
    cqlsh --no-color -f /build/init/02-seed.cql   localhost; \
    ROWS=$(cqlsh --no-color -e \
      "SELECT COUNT(*) FROM tasknest.tasks_by_user WHERE user_id='u1';" localhost \
      | grep -oE '^\s+[0-9]+' | tr -d ' ' | head -1); \
    echo "validated rows: ${ROWS}"; \
    test "${ROWS:-0}" -ge 1; \
    nodetool drain || true

# produce a single, ordered, idempotent migration bundle
RUN set -eux; \
    { echo "-- generated $(date -u +%FT%TZ)"; \
      for f in $(ls /build/init/*.cql | sort); do \
        echo "-- ===== $f ====="; cat "$f"; echo; done; } > /build/schema-all.cql; \
    sha256sum /build/schema-all.cql | cut -d' ' -f1 > /build/schema.sha256


# ══════════════ STAGE 2: runtime ══════════════
FROM cassandra:4.1 AS runtime

ARG SCHEMA_VERSION=1.0.0
LABEL org.opencontainers.image.title="tasknest-cassandra" \
      org.opencontainers.image.version="${SCHEMA_VERSION}"

# only the validated bundle survives; the /tmp/cass data dir dies with stage 1
COPY --from=validate /build/schema-all.cql /init/schema-all.cql
COPY --from=validate /build/schema.sha256  /usr/local/share/schema.sha256
COPY init/ /init/

COPY <<'EOF' /init/apply-schema.sh
#!/bin/bash
set -e
until cqlsh -u cassandra -p "$CASSANDRA_PASSWORD" --no-color -e "SHOW VERSION" localhost >/dev/null 2>&1; do sleep 3; done
cqlsh -u cassandra -p "$CASSANDRA_PASSWORD" --no-color -f /init/schema-all.cql localhost
echo "✅ schema applied: $(cat /usr/local/share/schema.sha256)"
EOF
RUN chmod +x /init/apply-schema.sh

ENV CASSANDRA_CLUSTER_NAME=tasknest-cluster \
    CASSANDRA_DC=dc1 CASSANDRA_RACK=rack1 \
    MAX_HEAP_SIZE=512M HEAP_NEWSIZE=128M \
    SCHEMA_VERSION=${SCHEMA_VERSION}

EXPOSE 7000 7001 7199 9042 9160
STOPSIGNAL SIGTERM
VOLUME ["/var/lib/cassandra"]

HEALTHCHECK --interval=20s --timeout=10s --start-period=120s --retries=12 \
  CMD cqlsh -u cassandra -p "$CASSANDRA_PASSWORD" --no-color \
      -e "SELECT now() FROM system.local" localhost >/dev/null || exit 1
```

### `docker-compose.yml`

```yaml
name: cassandra-learn

services:
  cassandra:
    build: { context: ., dockerfile: Dockerfile.multistage, target: runtime }
    image: tasknest-cassandra:1.0.0
    container_name: cassandra
    restart: unless-stopped
    environment:
      CASSANDRA_PASSWORD: ${CASSANDRA_PASSWORD:?set in .env}
      CASSANDRA_USER: cassandra
      MAX_HEAP_SIZE: 512M
      HEAP_NEWSIZE: 128M
    volumes:
      - cassandra-data:/var/lib/cassandra
    ports: ["127.0.0.1:9042:9042"]
    ulimits:                      # 🔑 Cassandra REQUIRES these
      memlock: -1
      nproc:  32768
      nofile: 100000
    healthcheck:
      test: ["CMD-SHELL", "cqlsh -u cassandra -p \"$$CASSANDRA_PASSWORD\" --no-color -e 'SELECT now() FROM system.local' localhost"]
      interval: 20s
      timeout: 10s
      retries: 12
      start_period: 120s          # ← Cassandra is SLOW to boot; don't skimp here
    deploy:
      resources: { limits: { cpus: "2.0", memory: 1536M } }
    stop_grace_period: 90s        # `nodetool drain` needs time
    networks: [cassnet]

  # one-shot: waits for health, applies the schema, exits 0
  schema:
    image: tasknest-cassandra:1.0.0
    container_name: cassandra-schema
    depends_on:
      cassandra: { condition: service_healthy }
    entrypoint: ["/init/apply-schema.sh"]
    environment:
      CASSANDRA_PASSWORD: ${CASSANDRA_PASSWORD:?set in .env}
    restart: "no"
    networks: [cassnet]

volumes:
  cassandra-data: { name: cassandra-learn-data }
networks:
  cassnet:
```

```bash
docker compose up -d --build
docker compose logs -f cassandra | grep -iE 'startup complete|listening'
docker compose up -d --wait --timeout 300     # can take 2-3 minutes
docker compose logs schema                    # ✅ schema applied: <sha>
docker compose exec cassandra cqlsh -u cassandra -p "$CASSANDRA_PASSWORD" localhost \
  -e "SELECT user_id,title,priority,done FROM tasknest.tasks_by_user WHERE user_id='u1';"
docker compose exec cassandra nodetool status
docker compose exec cassandra nodetool info
```

### Cassandra gotchas

| Gotcha | Explanation |
|---|---|
| **Slow boot** — 60–180 s | A JVM plus gossip and ring state. Your `start_period` must be generous or the healthcheck marks it unhealthy and Compose gives up. |
| `ulimits` are mandatory | Cassandra needs `nofile` ≥ 100 000 and `memlock -1`, or it crashes with *"Cassandra is unable to lock JVM memory"*. |
| Heap sizing | `MAX_HEAP_SIZE` should be ~25–50% of the container limit, capped around 8 GB. The rest is for the OS page cache — Cassandra depends on it. |
| Queries need the partition key | No `JOIN`, no arbitrary `WHERE`. If you need a new query pattern, you create a **new table**. Denormalisation is the design, not a smell. |
| `ALLOW FILTERING` | Means "scan the whole cluster". Fine in dev, fatal in production. |
| Data dir must be a volume | `/var/lib/cassandra` is the entire database. |
| Single-node replication factor | `SimpleStrategy` + `replication_factor: 1` is dev-only. Production uses `NetworkTopologyStrategy` with RF=3. |
| `nodetool drain` before stop | Flushes memtables to SSTables. That's why `stop_grace_period` is long. |

---
---

## 13.6 · 🕸️ Neo4j (Graph Database)

```
13f-neo4j/
├── Dockerfile
├── Dockerfile.multistage
├── docker-compose.yml
└── init/
    ├── 01-constraints.cypher
    └── 02-seed.cypher
```

### `init/01-constraints.cypher`

```cypher
// Constraints double as indexes in Neo4j.
CREATE CONSTRAINT task_id_unique IF NOT EXISTS
FOR (t:Task) REQUIRE t.id IS UNIQUE;

CREATE CONSTRAINT user_email_unique IF NOT EXISTS
FOR (u:User) REQUIRE u.email IS UNIQUE;

CREATE INDEX task_priority IF NOT EXISTS
FOR (t:Task) ON (t.priority);

CREATE INDEX task_done IF NOT EXISTS
FOR (t:Task) ON (t.done);
```

### `init/02-seed.cypher`

```cypher
// A graph: Users OWN Tasks, Tasks are TAGGED, Users COLLABORATE with Users.
CREATE (alice:User {id:'u1', name:'Alice',   email:'alice@example.com'})
CREATE (bob:User   {id:'u2', name:'Bob',     email:'bob@example.com'})
CREATE (carol:User {id:'u3', name:'Carol',   email:'carol@example.com'})

CREATE (t1:Task {id:'t1', title:'Learn FROM, RUN and CMD',        priority:'high',   done:false, created: datetime()})
CREATE (t2:Task {id:'t2', title:'Master COPY and .dockerignore',  priority:'high',   done:false, created: datetime()})
CREATE (t3:Task {id:'t3', title:'Understand ENTRYPOINT vs CMD',   priority:'medium', done:true,  created: datetime()})
CREATE (t4:Task {id:'t4', title:'Model a graph in Neo4j',         priority:'medium', done:false, created: datetime()})
CREATE (t5:Task {id:'t5', title:'Write a Cypher traversal',       priority:'low',    done:false, created: datetime()})

CREATE (docker:Tag {name:'docker'})
CREATE (basics:Tag {name:'basics'})
CREATE (graph:Tag  {name:'graph'})
CREATE (database:Tag {name:'database'})

CREATE (alice)-[:OWNS]->(t1)
CREATE (alice)-[:OWNS]->(t2)
CREATE (bob)-[:OWNS]->(t3)
CREATE (bob)-[:OWNS]->(t4)
CREATE (carol)-[:OWNS]->(t5)

CREATE (alice)-[:ASSIGNED_TO {since: datetime()}]->(t4)
CREATE (carol)-[:ASSIGNED_TO {since: datetime()}]->(t1)

CREATE (t1)-[:TAGGED]->(docker)
CREATE (t1)-[:TAGGED]->(basics)
CREATE (t2)-[:TAGGED]->(docker)
CREATE (t3)-[:TAGGED]->(docker)
CREATE (t4)-[:TAGGED]->(graph)
CREATE (t4)-[:TAGGED]->(database)
CREATE (t5)-[:TAGGED]->(graph)

CREATE (alice)-[:COLLABORATES_WITH {since: 2024}]->(bob)
CREATE (bob)-[:COLLABORATES_WITH {since: 2025}]->(carol)
CREATE (alice)-[:COLLABORATES_WITH {since: 2025}]->(carol);
```

### 🔵 CASE 1 — SIMPLE

```dockerfile
FROM neo4j:5.26-community

LABEL org.opencontainers.image.title="tasknest-neo4j"

# The community image runs /var/lib/neo4j/import/*.cypher via plugins,
# but the reliable approach is to copy the scripts and apply them on demand.
COPY init/ /init/

# APOC core is the standard extension library — install it into the plugins dir
ENV NEO4J_PLUGINS='["apoc"]' \
    NEO4J_AUTH=neo4j/neo4j_secret_password \
    NEO4J_dbms_security_procedures_unrestricted=apoc.* \
    NEO4J_dbms_memory_heap_initial__size=256m \
    NEO4J_dbms_memory_heap_max__size=512m \
    NEO4J_dbms_memory_pagecache_size=128m \
    NEO4J_server_default__listen__address=0.0.0.0

EXPOSE 7474 7473 7687

HEALTHCHECK --interval=20s --timeout=10s --start-period=60s --retries=8 \
  CMD cypher-shell -u neo4j -p "$NEO4J_PASSWORD" "RETURN 1" || exit 1
```

```bash
docker build -t neo4j-simple:v1 .
docker run -d --name neo1 -p 7474:7474 -p 7687:7687 \
  -e NEO4J_AUTH=neo4j/neo4j_secret_password \
  -v neo1-data:/data \
  neo4j-simple:v1

docker logs -f neo1 | grep -iE 'started|remote interface'
docker exec neo1 cypher-shell -u neo4j -p neo4j_secret_password -f /init/01-constraints.cypher
docker exec neo1 cypher-shell -u neo4j -p neo4j_secret_password -f /init/02-seed.cypher
```

🌐 **http://localhost:7474** → the **Neo4j Browser** (a built-in graphical query console). Connect with `neo4j://localhost:7687`, user `neo4j`, password `neo4j_secret_password`, then run:

```cypher
MATCH (n) RETURN n LIMIT 100;

// who owns an open high-priority task?
MATCH (u:User)-[:OWNS]->(t:Task {priority:'high', done:false})
RETURN u.name, collect(t.title) AS open_high_priority;

// tasks two degrees away from Alice through collaboration
MATCH path = (a:User {name:'Alice'})-[:COLLABORATES_WITH*1..2]-(other:User)-[:OWNS]->(t:Task)
RETURN other.name, t.title, length(path) AS hops;

// the most-connected tag
MATCH (t:Task)-[:TAGGED]->(tag:Tag)
RETURN tag.name, count(t) AS n ORDER BY n DESC;
```

### 🟢 CASE 2 — MULTI-STAGE

Validate every Cypher script against a **disposable graph** at build time, and export a validated dump.

```dockerfile
# syntax=docker/dockerfile:1

# ══════════════ STAGE 1: validate the graph model ══════════════
FROM neo4j:5.26-community AS validate

ENV NEO4J_AUTH=neo4j/builderpassword \
    NEO4J_dbms_memory_heap_max__size=512m \
    NEO4J_server_default__listen__address=127.0.0.1

COPY init/ /build/init/

RUN set -eux; \
    # start a throwaway database on an ephemeral data dir
    (/var/lib/neo4j/bin/neo4j-admin dbms start >/tmp/neo.log 2>&1 &) ; \
    for i in $(seq 1 60); do \
      cypher-shell -a bolt://localhost:7687 -u neo4j -p builderpassword "RETURN 1" >/dev/null 2>&1 && break; \
      sleep 2; done; \
    cypher-shell -a bolt://localhost:7687 -u neo4j -p builderpassword -f /build/init/01-constraints.cypher; \
    cypher-shell -a bolt://localhost:7687 -u neo4j -p builderpassword -f /build/init/02-seed.cypher; \
    NODES=$(cypher-shell -a bolt://localhost:7687 -u neo4j -p builderpassword \
              --format plain "MATCH (n) RETURN count(n) AS c" | tail -1 | tr -d '"'); \
    RELS=$(cypher-shell -a bolt://localhost:7687 -u neo4j -p builderpassword \
              --format plain "MATCH ()-[r]->() RETURN count(r) AS c" | tail -1 | tr -d '"'); \
    echo "validated graph: ${NODES} nodes, ${RELS} relationships"; \
    test "${NODES:-0}" -ge 10; \
    test "${RELS:-0}"  -ge 10; \
    # export a compact, reproducible dump of the validated model
    cypher-shell -a bolt://localhost:7687 -u neo4j -p builderpassword --format plain \
      "CALL apoc.export.cypher.all(null, {stream:true}) YIELD cypher RETURN cypher" \
      > /build/model-export.cypher 2>/dev/null || true; \
    /var/lib/neo4j/bin/neo4j-admin dbms stop || true

RUN set -eux; \
    { echo "// validated $(date -u +%FT%TZ)"; \
      for f in $(ls /build/init/*.cypher | sort); do echo "// == $f =="; cat "$f"; echo; done; \
    } > /build/model-all.cypher; \
    sha256sum /build/model-all.cypher | cut -d' ' -f1 > /build/model.sha256


# ══════════════ STAGE 2: runtime ══════════════
FROM neo4j:5.26-community AS runtime

ARG MODEL_VERSION=1.0.0
LABEL org.opencontainers.image.title="tasknest-neo4j" \
      org.opencontainers.image.version="${MODEL_VERSION}"

# only the validated bundle survives — the throwaway graph data dies with stage 1
COPY --from=validate /build/model-all.cypher /init/model-all.cypher
COPY --from=validate /build/model.sha256     /usr/local/share/model.sha256
COPY init/ /init/

COPY <<'EOF' /init/apply-model.sh
#!/bin/bash
set -e
PASS="${NEO4J_PASSWORD:-neo4j_secret_password}"
until cypher-shell -u neo4j -p "$PASS" "RETURN 1" >/dev/null 2>&1; do sleep 3; done
cypher-shell -u neo4j -p "$PASS" -f /init/model-all.cypher
echo "✅ graph model applied: $(cat /usr/local/share/model.sha256)"
EOF
RUN chmod +x /init/apply-model.sh

ENV NEO4J_PLUGINS='["apoc"]' \
    NEO4J_dbms_security_procedures_unrestricted=apoc.* \
    NEO4J_dbms_memory_heap_initial__size=256m \
    NEO4J_dbms_memory_heap_max__size=512m \
    NEO4J_dbms_memory_pagecache_size=128m \
    NEO4J_server_default__listen__address=0.0.0.0 \
    MODEL_VERSION=${MODEL_VERSION}

EXPOSE 7474 7473 7687
STOPSIGNAL SIGTERM
VOLUME ["/data"]

HEALTHCHECK --interval=20s --timeout=10s --start-period=60s --retries=8 \
  CMD cypher-shell -u neo4j -p "$NEO4J_PASSWORD" "RETURN 1" || exit 1
```

### `docker-compose.yml`

```yaml
name: neo4j-learn

services:
  graph:
    build: { context: ., dockerfile: Dockerfile.multistage, target: runtime }
    image: tasknest-neo4j:1.0.0
    container_name: neo4j
    restart: unless-stopped
    environment:
      NEO4J_AUTH: neo4j/${NEO4J_PASSWORD:?set in .env}
      NEO4J_PASSWORD: ${NEO4J_PASSWORD:?set in .env}
      NEO4J_PLUGINS: '["apoc"]'
      NEO4J_dbms_security_procedures_unrestricted: apoc.*
      NEO4J_dbms_memory_heap_initial__size: 256m
      NEO4J_dbms_memory_heap_max__size: 512m
      NEO4J_dbms_memory_pagecache_size: 128m
    volumes:
      - neo4j-data:/data
      - neo4j-logs:/logs
      - neo4j-plugins:/plugins
      - ./init:/init:ro
    ports:
      - "127.0.0.1:7474:7474"     # HTTP + Neo4j Browser
      - "127.0.0.1:7687:7687"     # Bolt protocol
    healthcheck:
      test: ["CMD-SHELL", "cypher-shell -u neo4j -p \"$$NEO4J_PASSWORD\" 'RETURN 1' || exit 1"]
      interval: 20s
      timeout: 10s
      retries: 8
      start_period: 60s
    deploy:
      resources: { limits: { cpus: "1.0", memory: 1G } }
    stop_grace_period: 60s
    networks: [graphnet]

  model:                            # one-shot: apply the validated graph model
    image: tasknest-neo4j:1.0.0
    container_name: neo4j-model
    depends_on:
      graph: { condition: service_healthy }
    entrypoint: ["/init/apply-model.sh"]
    environment:
      NEO4J_PASSWORD: ${NEO4J_PASSWORD:?set in .env}
    restart: "no"
    networks: [graphnet]

volumes:
  neo4j-data:    { name: neo4j-learn-data }
  neo4j-logs:    { name: neo4j-learn-logs }
  neo4j-plugins: { name: neo4j-learn-plugins }
networks:
  graphnet:
```

```bash
docker compose up -d --build --wait
docker compose logs model                    # ✅ graph model applied: <sha>
# 🌐 http://localhost:7474 → Neo4j Browser → run the queries above
docker compose exec graph cypher-shell -u neo4j -p "$NEO4J_PASSWORD" \
  "MATCH (u:User)-[:OWNS]->(t:Task) RETURN u.name, count(t) AS tasks ORDER BY tasks DESC;"

# backup
docker compose exec graph cypher-shell -u neo4j -p "$NEO4J_PASSWORD" \
  "CALL apoc.export.cypher.all('backup.cypher', {stream:true}) YIELD cypher RETURN cypher" > backups/model.cypher
docker compose exec graph neo4j-admin database dump neo4j --to-path=/data
docker compose cp graph:/data/neo4j.dump ./backups/
```

### Neo4j gotchas

| Gotcha | Explanation |
|---|---|
| `NEO4J_AUTH` format | Must be `user/password` in **one** variable. Setting `NEO4J_PASSWORD` alone does nothing on first init. Use `NEO4J_AUTH=none` to disable auth (dev only!). |
| Password change on first boot | The image forces a password change from the default `neo4j`. Supplying `NEO4J_AUTH` skips that interactive prompt — otherwise the container hangs. |
| Three volumes, not one | `/data` (the graph), `/logs`, and `/plugins` (APOC downloads). Mounting only `/data` means APOC re-downloads on every start. |
| `NEO4J_dbms_memory_heap_max__size` | **Double underscores** — that's how Compose/env-var syntax encodes the `.` in `dbms.memory.heap.max_size`. A very common typo. |
| Community vs Enterprise | Community = one database, no clustering, no role-based security. Fine for learning. |
| Plugin downloads need internet | `NEO4J_PLUGINS='["apoc"]'` fetches from the internet at startup. In air-gapped environments, `COPY` the jar into `/plugins` in the Dockerfile instead. |
| Bolt vs HTTP | Applications use **Bolt (7687)**; the browser uses **HTTP (7474)** but connects over Bolt. Publish both, or the Browser UI shows "connection failed". |
| Slow first start | Plugin download + store creation. `start_period: 60s` minimum. |

---
---

## D.7 — 🔨 Tasks for Project 13 (apply to ALL six databases)

> **13.T1 — Persistence proof (do this for every database).**
> Start it, write a record through the client, `docker compose down`, `docker compose up -d --wait`, and read the record back. Then `docker compose down -v`, restart, and confirm it's **gone**. Write down, for each database, the exact path that must be a volume.

> **13.T2 — Break the healthcheck, deliberately.**
> For each database, change the healthcheck to probe the wrong port or use wrong credentials. Restart and observe how long it takes to go `(unhealthy)`. Then answer: what is the minimum `start_period` each one actually needs? (Measure with `docker logs --timestamps`.)

> **13.T3 — Find each database's real memory floor.**
> Start each with `--memory 128m`, then 256m, 512m, 1g. Record the lowest limit at which each one boots successfully. Which one dies first, and what is its exit code?

> **13.T4 — Init scripts run only once. Prove it.**
> Add a new row to each database's seed script, then `docker compose up -d` **without** `-v`. Is the new row there? Now do it with `down -v`. Explain why, and describe the *correct* production mechanism for schema changes (hint: migrations).

> **13.T5 — Write a real backup/restore pair for two of them.**
> Implement `scripts/backup.sh` and `scripts/restore.sh` for MySQL and Mongo (or any two). Then **destroy** the data with `down -v`, restore, and verify row/document counts match exactly. A backup you have never restored is not a backup.

> **13.T6 — Never publish the port.**
> Remove `ports:` from one database, then try to connect from your host — it must fail. Then connect from another container on the same network using the **service name** — it must succeed. Explain what this proves about Docker networks.

> **13.T7 — One compose file, all six databases.**
> Merge all six into a single `docker-compose.yml` with distinct host ports (3306, 27017, 6379, 8000, 9042, 7474/7687), separate named volumes, and one `docker compose up -d --wait`. Measure total RAM with `docker compose stats --no-stream`. Then put each behind its own network and verify the MySQL container cannot reach the Neo4j container.

> **13.T8 — Add a GUI for each and connect them all.**
> Adminer (MySQL), Mongo Express (Mongo), Redis Insight (Redis), dynamodb-admin (DynamoDB), Neo4j Browser (Neo4j). For Cassandra there's no standard web UI — use `cqlsh` and explain why. Put every GUI behind a Compose `profiles: ["tools"]` key so production never starts them.

<details>
<summary>👉 Answers & measured expectations</summary>

**13.T1 — the volume paths (memorise this table):**

| Database | Volume path | Client inside the container |
|---|---|---|
| MySQL | `/var/lib/mysql` | `mysql -uapp -p tasknest` |
| MongoDB | `/data/db` | `mongosh -u root -p --authenticationDatabase admin` |
| Redis | `/data` | `redis-cli -a $REDIS_PASSWORD --no-auth-warning` |
| DynamoDB Local | `/home/dynamodblocal/data` | `aws dynamodb ... --endpoint-url http://localhost:8000` |
| Cassandra | `/var/lib/cassandra` | `cqlsh -u cassandra -p $CASSANDRA_PASSWORD` |
| Neo4j | `/data` (+ `/logs`, `/plugins`) | `cypher-shell -u neo4j -p $NEO4J_PASSWORD` |

`down` keeps named volumes; `down -v` deletes them permanently — there is no undo.

**13.T2 — realistic `start_period` values (measure, don't guess):**
Redis ≈ **5 s** · DynamoDB Local ≈ **20 s** · MySQL ≈ **30–45 s** · MongoDB ≈ **20–30 s** · Neo4j ≈ **45–90 s** (longer if APOC must download) · Cassandra ≈ **90–180 s**.
Set `start_period` to roughly 2× the observed boot time. During `start_period`, failed checks don't count toward `--retries`, so an overly small value causes false `unhealthy` states that block `depends_on: service_healthy` forever.

**13.T3 — memory floors (approximate, on a normal laptop):**
| | Fails at 128 MB | Boots at 256 MB | Comfortable |
|---|---|---|---|
| Redis | ✅ works even at 32 MB | ✅ | 192 MB |
| DynamoDB Local | ❌ 137 (JVM) | ⚠️ marginal | 512 MB |
| MongoDB | ❌ | ⚠️ marginal (WiredTiger wants 256 MB cache) | 768 MB |
| MySQL | ❌ | ⚠️ needs a small `innodb_buffer_pool_size` | 768 MB |
| Neo4j | ❌ | ❌ | 1 GB |
| Cassandra | ❌ | ❌ (heap 512 MB + page cache) | 1.5–2 GB |

Exit code **137** = SIGKILL from the cgroup OOM killer. `docker inspect --format '{{.State.OOMKilled}}'` returns `true`. The lesson: **database memory limits are the #1 cause of mystery restarts**, and every engine has its own cache setting (`innodb_buffer_pool_size`, `cacheSizeGB`, `maxmemory`, `MAX_HEAP_SIZE`, `heap_max_size`, `pagecache_size`) that must be **smaller** than the container limit.

**13.T4** The new row is **not** there without `-v`. Every one of these images runs its init directory **only when the data directory is empty** — MySQL's `/docker-entrypoint-initdb.d`, Mongo's equivalent, Neo4j's first-start. Once data exists, the entrypoint skips initialisation entirely. This is deliberate: re-running seed scripts on every start would wipe or duplicate production data.
**The correct production mechanism is migrations**: versioned, idempotent, forward-only scripts (`V1__create.sql`, `V2__add_index.sql`) applied by a tool — Flyway/Liquibase (Java), Alembic (Python), golang-migrate (Go), `mongock`, or a small one-shot Compose service with `restart: "no"` and `depends_on: db: service_healthy`. Track applied versions in a table inside the database itself.

**13.T5 — backup commands per engine:**
| | Backup | Restore |
|---|---|---|
| MySQL | `mysqldump --single-transaction --routines --triggers --databases tasknest \| gzip` | `gunzip -c f.sql.gz \| mysql -u root -p` |
| MongoDB | `mongodump --db tasknest --archive=/tmp/d.archive` | `mongorestore --archive=/tmp/d.archive --drop` |
| Redis | `BGREWRITEAOF` then copy `/data/appendonly.aof.*` + `dump.rdb` | put the files back in the volume, restart |
| DynamoDB | per-table `aws dynamodb scan` → JSON, or a table-level backup tool | `batch-write-item` from the JSON |
| Cassandra | `nodetool snapshot` then copy `/var/lib/cassandra/data/**/snapshots/` | `sstableloader` into a fresh node |
| Neo4j | `neo4j-admin database dump neo4j --to-path=/data` | `neo4j-admin database load --from-path=/data` |

**13.T6** With no `ports:` mapping the database is reachable **only** inside the Docker network — proof that publishing a port is a deliberate act, and that the default is isolation. Another container on the same network connects via the **service name** (`mysql://user:pass@db:3306/app`), because Compose runs an embedded DNS server at `127.0.0.11` for every user-defined network. This is why `localhost` in your app config is always wrong in Compose.

**13.T7** Total RAM for all six at once is roughly **3.5–5 GB** (Cassandra and Neo4j dominate). Practical advice: don't run all six simultaneously on a laptop — use Compose **profiles** (`profiles: ["mysql"]`, etc.) and start only what you need. For network isolation, give each its own network and confirm with `docker compose exec mysql-db getent hosts neo4j` → unresolvable. Note the *default* `bridge` network has **no** DNS resolution by container name — you must define your own networks to get service discovery.

**13.T8** GUI ports used above: Adminer `8081`, Mongo Express `8082`, dynamodb-admin `8083`, Neo4j Browser `7474`, Redis Insight `8001` (image `redis/redisinsight`). Cassandra has no widely-adopted web UI because `cqlsh` ships inside the image and the query model (partition-key lookups) doesn't map well to a generic "browse all rows" UI; third-party tools exist (DataStax Studio, DBeaver) but connect as ordinary CQL clients.
Putting them behind `profiles: ["tools"]` means `docker compose up -d` never starts them, while `docker compose --profile tools up -d` does. **Never expose a database GUI in production** — each is effectively a root shell for your data.
</details>

---

## D.8 — What Projects 8–13 gave you

| Project | New skill |
|---|---|
| 8 · React | JS build pipelines in containers, nginx for SPAs, build-time vs runtime env, `.dockerignore` for `node_modules` |
| 9 · Java | JDK vs JRE, layered jars, Maven/Gradle cache mounts, JVM container memory flags |
| 10 · React+Java | Two multi-stage services behind one origin, CORS elimination, dev vs prod compose overrides |
| 11 · React+Python | wheels vs pip install, gunicorn/uvicorn, `PYTHONUNBUFFERED`, bind-mount uid mismatches |
| 12 · React+Go | static binaries, `FROM scratch`, cross-compilation, debugging a shell-less image |
| 13 · Databases | volumes, init-once semantics, per-engine healthchecks, memory floors, backup/restore, GUI tools |

**Every one of them used the same two-case method:** build it simply, understand it, then rebuild it multi-stage and *measure* what you gained. That comparison — not memorising syntax — is what makes you good at Docker.

### 🔚 Final exercise

Pick **one** of these six stacks and take it all the way to production:
1. Add the capstone's Postgres + Redis + nginx layer (Section C).
2. Add a GitHub Actions workflow that builds, tests, scans and pushes multi-arch images.
3. Write the runbook: deploy, rollback, and the top 5 incidents.
4. Push it to a registry and `docker compose up` it on a **different machine** — a cloud VM, a friend's laptop, anywhere.

When that works on a machine you've never touched, you're no longer a beginner. 🐳

---

## ➡️ Next

**[`17-PROJECT-14-mern-stack.md`](17-PROJECT-14-mern-stack.md)** — Project 14, the **MERN stack**.

⭐ Project 13 taught you to containerise a database as *someone else's infrastructure*. Project 14 puts **React, Express and MongoDB in the same release**, where the schema is enforced by nothing but your own code and the only rollback for the data is a backup you verified. It is the hardest project in this path and the most common stack in the real one.

---

## 🎓 After Project 14, you've finished the Docker Learning Path

Go back and re-read **[`03-CHEATSHEET.md`](03-CHEATSHEET.md)** — you'll find you now understand every single line of it.

**Final exercise:** pick one of these six stacks and take it all the way to production —
add the capstone's Postgres + Redis + nginx layer, a GitHub Actions workflow that builds/tests/scans/pushes multi-arch images, and a written runbook. Then push it to a registry and `docker compose up` it on a **machine you have never touched**.

When that works, you're no longer a beginner. 🐳

⭐ **And then, on Kubernetes:** [`../kubernetes-learning-path/18-PROJECT-15-mern-stack.md`](../kubernetes-learning-path/18-PROJECT-15-mern-stack.md) — the same MERN stack as two Deployments plus a **replica-set StatefulSet**, with the migration as a gated Job and the backup as a CronJob.

⭐ **And then, through CI/CD:** [`../cicd-learning-path/08-SCENARIO-DEPLOYMENTS/01-MERN-STACK-PROJECT.md`](../cicd-learning-path/08-SCENARIO-DEPLOYMENTS/01-MERN-STACK-PROJECT.md) — the same stack as **shape E**, in all three scenarios, in all three tools.

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish%20Kumar%20Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn → <https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260>
🐙 GitHub → <https://github.com/3558Bhk>

*Built for engineers who learn by breaking things on purpose.*

</div>
