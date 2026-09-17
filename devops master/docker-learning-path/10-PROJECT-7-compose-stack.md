# 🦉 PROJECT 7 — Multi-container Stack with Docker Compose

> **Part of the Docker Learning Path.** Do Projects 1–6 first.
>
> ⏱️ **Time:** 60–75 minutes · 🎓 **Level:** intermediate
> 🎯 **New tool:** `docker compose` · **Concepts:** services, DNS-by-service-name, networks, named volumes, `depends_on` + healthchecks, profiles, scaling

---

## 1. The idea

Every project so far was **one** container. Real applications are **many**: a web server, an API, a database, a cache. Running them with five separate `docker run` commands — each with its own network, volume and env flags — is unmaintainable.

**Docker Compose** describes the whole stack in one YAML file, then:

```bash
docker compose up -d      # build + create network + create volumes + start everything, in dependency order
docker compose down       # stop and remove it all
```

---

## 2. Files to create

```
07-compose-stack/
├── docker-compose.yml
├── .env
├── .gitignore
├── Makefile
├── api/
│   ├── Dockerfile
│   ├── .dockerignore
│   ├── requirements.txt
│   └── app.py
├── web/
│   ├── Dockerfile
│   ├── nginx.conf
│   └── site/
│       ├── index.html
│       └── style.css
└── db-init/
    └── 01-schema.sql
```

### `api/app.py`

```python
"""A tiny stdlib API that talks to PostgreSQL and Redis over a Docker network.

It uses ONLY the standard library (raw sockets for Redis, a subprocess for psql)
so the project has no dependencies and always builds. In a real app you would use
psycopg / redis-py — the Docker lessons are identical.

Routes:
  GET  /            service info
  GET  /health      liveness  (process up)
  GET  /ready       readiness (DB + cache reachable)
  GET  /items       list items (Redis cache in front of Postgres)
  POST /items       {"name": "..."} create an item
  GET  /db          run a SQL query straight against postgres
"""
import json
import os
import socket
import subprocess
import sys
import time
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

PORT = int(os.environ.get("PORT", "8000"))
HOST = os.environ.get("HOST", "0.0.0.0")
DATABASE_URL = os.environ.get("DATABASE_URL", "postgresql://appuser:apppass@db:5432/appdb")
REDIS_URL = os.environ.get("REDIS_URL", "redis://cache:6379/0")
SERVICE_NAME = os.environ.get("SERVICE_NAME", "api")
APP_VERSION = os.environ.get("APP_VERSION", "1.0.0")

_u = urlparse(DATABASE_URL)
DB = {
    "user": _u.username or "appuser",
    "password": _u.password or "",
    "host": _u.hostname or "db",
    "port": str(_u.port or 5432),
    "name": (_u.path or "/appdb").lstrip("/"),
}
_r = urlparse(REDIS_URL)
REDIS_HOST, REDIS_PORT = _r.hostname or "cache", _r.port or 6379


def log(msg: str) -> None:
    print(f"[{SERVICE_NAME}] {msg}", flush=True)


# ---------------------------------------------------------------- Postgres
def sql(query: str, timeout: int = 5):
    """Run SQL via the psql client. Returns (ok, rows_or_error)."""
    env = {**os.environ, "PGPASSWORD": DB["password"], "PGCONNECT_TIMEOUT": str(timeout)}
    try:
        proc = subprocess.run(
            ["psql", "-h", DB["host"], "-p", DB["port"], "-U", DB["user"], "-d", DB["name"],
             "-t", "-A", "-F", "|", "-c", query],
            capture_output=True, text=True, timeout=timeout + 3, env=env,
        )
    except FileNotFoundError:
        return False, "psql client not installed in this image"
    except subprocess.TimeoutExpired:
        return False, "query timed out"
    if proc.returncode != 0:
        return False, proc.stderr.strip()
    rows = [line.split("|") for line in proc.stdout.strip().splitlines() if line.strip()]
    return True, rows


# ---------------------------------------------------------------- Redis (minimal RESP client)
def redis_cmd(*args, timeout: float = 2.0):
    try:
        with socket.create_connection((REDIS_HOST, REDIS_PORT), timeout=timeout) as s:
            s.settimeout(timeout)
            cmd = f"*{len(args)}\r\n" + "".join(f"${len(str(a))}\r\n{a}\r\n" for a in args)
            s.sendall(cmd.encode())
            return s.recv(65536).decode(errors="replace").strip()
    except OSError as exc:
        return f"-ERR {exc}"


def cache_get(key): 
    reply = redis_cmd("GET", key)
    return reply.splitlines()[-1] if reply.startswith("$") and not reply.startswith("$-1") else None

def cache_set(key, value, ttl=10): 
    redis_cmd("SETEX", key, ttl, value)

def cache_del(key): 
    redis_cmd("DEL", key)


# ---------------------------------------------------------------- checks
def db_ok() -> bool:
    ok, _ = sql("SELECT 1", timeout=3)
    return ok

def cache_ok() -> bool:
    return redis_cmd("PING", timeout=2).endswith("PONG")

START_TIME = time.time()


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body):
        if not isinstance(body, bytes):
            body = json.dumps(body, indent=2, default=str).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("X-Served-By", f"{SERVICE_NAME}@{socket.gethostname()}")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?")[0]

        if path == "/":
            return self._send(200, {
                "service": SERVICE_NAME, "version": APP_VERSION,
                "hostname": socket.gethostname(),
                "uptime_seconds": round(time.time() - START_TIME, 1),
                "database": f"{DB['user']}@{DB['host']}:{DB['port']}/{DB['name']}",
                "cache": f"{REDIS_HOST}:{REDIS_PORT}",
                "routes": ["/", "/health", "/ready", "/items", "/db", "/net"],
                "note": "Reach postgres at hostname 'db' and redis at 'cache' — DNS by SERVICE NAME.",
            })

        if path == "/health":                       # liveness: no dependencies
            return self._send(200, {"status": "ok"})

        if path == "/ready":                        # readiness: dependencies must work
            d, c = db_ok(), cache_ok()
            return self._send(200 if (d and c) else 503,
                              {"ready": d and c, "database": d, "cache": c})

        if path == "/items":
            cached = cache_get("items")
            if cached:
                log("cache HIT")
                return self._send(200, {"source": "redis-cache", "items": json.loads(cached)})
            log("cache MISS -> querying postgres")
            ok, res = sql("SELECT id, name, created_at FROM items ORDER BY id")
            if not ok:
                return self._send(503, {"error": "database unavailable", "detail": res})
            items = [{"id": int(r[0]), "name": r[1], "created_at": r[2]} for r in res if len(r) >= 3]
            cache_set("items", json.dumps(items), ttl=10)
            return self._send(200, {"source": "postgres", "items": items})

        if path == "/db":
            ok, res = sql("SELECT version()")
            return self._send(200 if ok else 503, {"ok": ok, "result": res})

        if path == "/net":                          # demonstrate service DNS
            out = {}
            for host in ("db", "cache", "web", "api", "google.com"):
                try:
                    out[host] = socket.gethostbyname(host)
                except OSError as exc:
                    out[host] = f"unresolvable ({exc.__class__.__name__})"
            return self._send(200, out)

        return self._send(404, {"error": "no such route"})

    def do_POST(self):
        if self.path != "/items":
            return self._send(404, {"error": "no such route"})
        length = int(self.headers.get("Content-Length", 0))
        try:
            name = str(json.loads(self.rfile.read(length) or b"{}").get("name", "")).strip()
        except json.JSONDecodeError:
            return self._send(400, {"error": "invalid JSON"})
        if not name:
            return self._send(400, {"error": "'name' is required"})
        safe = name.replace("'", "''")[:200]
        ok, res = sql(f"INSERT INTO items (name) VALUES ('{safe}') RETURNING id")
        if not ok:
            return self._send(503, {"error": "database unavailable", "detail": res})
        cache_del("items")                          # invalidate the cache on write
        log(f"inserted item {res}")
        return self._send(201, {"created": name, "id": res[0][0] if res else None})

    def log_message(self, fmt, *args):
        log(f"{self.command} {self.path} {fmt % args}")


if __name__ == "__main__":
    log(f"starting on {HOST}:{PORT}")
    log(f"database={DB['host']}:{DB['port']}/{DB['name']}  cache={REDIS_HOST}:{REDIS_PORT}")
    for attempt in range(1, 31):                    # wait for dependencies at startup
        if db_ok() and cache_ok():
            log("database and cache are reachable ✅")
            break
        log(f"dependencies not ready (attempt {attempt}/30), retrying in 2s...")
        time.sleep(2)
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
```

### `api/Dockerfile`

```dockerfile
# syntax=docker/dockerfile:1
FROM python:3.13-alpine AS base

ARG APP_VERSION=1.0.0
ENV APP_VERSION=${APP_VERSION} \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PORT=8000 \
    HOST=0.0.0.0 \
    SERVICE_NAME=api

WORKDIR /app

# postgresql-client gives us `psql`, which app.py shells out to
RUN apk add --no-cache postgresql-client

RUN addgroup -S app && adduser -S app -G app

COPY --chown=app:app requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY --chown=app:app app.py ./

USER app
EXPOSE 8000
STOPSIGNAL SIGTERM

HEALTHCHECK --interval=10s --timeout=3s --start-period=15s --retries=5 \
  CMD python -c "import urllib.request,sys;sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health',timeout=2).status==200 else 1)"

CMD ["python", "app.py"]
```

### `api/requirements.txt`

```
# stdlib only — keeps the build fast and offline-friendly
```

### `api/.dockerignore`

```gitignore
__pycache__
*.pyc
.env
*.env
.git
*.log
Dockerfile
.dockerignore
```

### `web/site/index.html`

```html
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Compose Stack</title><link rel="stylesheet" href="style.css"></head>
<body>
<h1>🐳 Compose Stack</h1>
<p>Four containers, one command: <code>docker compose up -d</code></p>

<section class="grid">
  <div class="card"><h2>Services</h2><ul>
    <li><b>web</b> — nginx, this page (port 8080)</li>
    <li><b>api</b> — Python, built from <code>./api</code> (port 8000)</li>
    <li><b>db</b> — PostgreSQL 17 (internal + 5432)</li>
    <li><b>cache</b> — Redis 7 (internal only)</li>
  </ul></div>
  <div class="card"><h2>Try the API</h2><ul>
    <li><a href="http://localhost:8000/" target="_blank">/ — service info</a></li>
    <li><a href="http://localhost:8000/health" target="_blank">/health — liveness</a></li>
    <li><a href="http://localhost:8000/ready" target="_blank">/ready — DB + cache</a></li>
    <li><a href="http://localhost:8000/items" target="_blank">/items — Postgres via Redis</a></li>
    <li><a href="http://localhost:8000/net" target="_blank">/net — service DNS</a></li>
  </ul></div>
</section>

<section class="card">
  <h2>Add an item</h2>
  <form id="f"><input id="n" placeholder="e.g. Learned docker compose" autofocus>
  <button>Add</button></form>
  <pre id="out">click an item link above, or add one here</pre>
</section>

<script>
const out = document.getElementById('out');
const API = 'http://localhost:8000';
async function load(){
  try { out.textContent = JSON.stringify(await (await fetch(API + '/items')).json(), null, 2); }
  catch(e){ out.textContent = 'API unreachable: ' + e + '\n(is `docker compose up -d` running?)'; }
}
document.getElementById('f').onsubmit = async e => {
  e.preventDefault();
  const n = document.getElementById('n');
  if(!n.value.trim()) return;
  await fetch(API + '/items', {method:'POST', headers:{'Content-Type':'application/json'},
                               body: JSON.stringify({name:n.value})});
  n.value=''; load();
};
load();
</script>
</body>
</html>
```

### `web/site/style.css`

```css
:root{color-scheme:light dark}
body{font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif;max-width:900px;margin:2rem auto;padding:0 1.25rem;line-height:1.6}
h1{color:#2496ed}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:1rem}
.card{border:1px solid rgba(127,127,127,.35);border-radius:10px;padding:1rem 1.25rem}
code{background:rgba(127,127,127,.18);padding:.12em .4em;border-radius:4px}
input{padding:.5rem;width:65%}button{padding:.5rem 1rem}
pre{background:rgba(127,127,127,.12);padding:.8rem;border-radius:8px;overflow:auto;font-size:.85rem}
a{color:#2496ed}
```

### `web/nginx.conf`

```nginx
server {
    listen 80;
    server_name _;
    root /usr/share/nginx/html;
    index index.html;

    gzip on;
    gzip_types text/css application/javascript application/json image/svg+xml;

    location / { try_files $uri $uri/ =404; }

    location /healthz { return 200 "ok\n"; add_header Content-Type text/plain; }

    # Reverse-proxy the API so the browser can use ONE origin (no CORS problems).
    location /api/ {
        proxy_pass         http://api:8000/;     # ← "api" is the SERVICE NAME, resolved by Docker DNS
        proxy_set_header   Host $host;
        proxy_set_header   X-Real-IP $remote_addr;
        proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_connect_timeout 5s;
        proxy_read_timeout    10s;
    }
}
```

### `web/Dockerfile`

```dockerfile
# syntax=docker/dockerfile:1
FROM nginx:1.29-alpine

LABEL org.opencontainers.image.title="compose-stack-web"

WORKDIR /usr/share/nginx/html
COPY site/ ./
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80
STOPSIGNAL SIGQUIT

HEALTHCHECK --interval=15s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -q --spider http://localhost/healthz || exit 1
```

### `db-init/01-schema.sql`

```sql
-- Every .sql/.sh file in /docker-entrypoint-initdb.d runs ONCE,
-- the first time the postgres volume is initialised (empty data dir).
CREATE TABLE IF NOT EXISTS items (
    id         SERIAL PRIMARY KEY,
    name       TEXT        NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO items (name) VALUES
    ('Learned FROM, RUN, CMD'),
    ('Learned COPY and .dockerignore'),
    ('Learned ENV vs ARG'),
    ('Learned ENTRYPOINT vs CMD'),
    ('Learned VOLUME, USER, HEALTHCHECK'),
    ('Learned multi-stage builds');

CREATE INDEX IF NOT EXISTS items_created_at_idx ON items (created_at DESC);
```

### `.env`

```bash
# docker compose reads this file automatically for ${VAR} substitution
DB_USER=appuser
DB_PASSWORD=apppass
DB_NAME=appdb
API_VERSION=1.0.0
```

### `.gitignore`

```bash
.env
*.log
__pycache__/
data/
```

### `docker-compose.yml`

```yaml
name: learn-stack

services:
  # ─────────────────────────── database ───────────────────────────
  db:
    image: postgres:17-alpine
    container_name: stack-db
    restart: unless-stopped
    environment:
      POSTGRES_USER: ${DB_USER:-appuser}
      POSTGRES_PASSWORD: ${DB_PASSWORD:-apppass}
      POSTGRES_DB: ${DB_NAME:-appdb}
    volumes:
      - db-data:/var/lib/postgresql/data
      # SQL here runs ONCE on first initialisation of an EMPTY volume
      - ./db-init:/docker-entrypoint-initdb.d:ro
    ports:
      - "5432:5432"        # remove in production — the DB should not be public
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${DB_USER:-appuser} -d ${DB_NAME:-appdb}"]
      interval: 5s
      timeout: 5s
      retries: 12
      start_period: 10s
    networks: [backend]

  # ─────────────────────────── cache ───────────────────────────
  cache:
    image: redis:7-alpine
    container_name: stack-cache
    restart: unless-stopped
    command: ["redis-server", "--appendonly", "yes"]   # persist to the volume
    volumes:
      - cache-data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5
    networks: [backend]

  # ─────────────────────────── api ───────────────────────────
  api:
    build:
      context: ./api
      dockerfile: Dockerfile
      args:
        APP_VERSION: ${API_VERSION:-1.0.0}
    image: stack-api:${API_VERSION:-1.0.0}
    restart: unless-stopped
    depends_on:
      db:
        condition: service_healthy      # ← wait until postgres is REALLY ready
      cache:
        condition: service_healthy
    environment:
      DATABASE_URL: postgresql://${DB_USER:-appuser}:${DB_PASSWORD:-apppass}@db:5432/${DB_NAME:-appdb}
      REDIS_URL: redis://cache:6379/0
      SERVICE_NAME: api
      APP_VERSION: ${API_VERSION:-1.0.0}
    ports:
      - "8000:8000"
    networks: [backend]

  # ─────────────────────────── web ───────────────────────────
  web:
    build:
      context: ./web
    image: stack-web:1.0.0
    container_name: stack-web
    restart: unless-stopped
    depends_on:
      api:
        condition: service_started
    ports:
      - "8080:80"
    networks: [frontend, backend]   # on both: serves browsers AND proxies to api

volumes:
  db-data:
  cache-data:

networks:
  frontend:
  backend:
```

### `Makefile`

```makefile
.PHONY: up down restart build logs ps test nuke clean shell-api shell-db

up:            ## start everything
	docker compose up -d

down:          ## stop and remove containers + networks (volumes kept)
	docker compose down

restart:
	docker compose restart

build:         ## rebuild images without cache
	docker compose build --no-cache

logs:          ## follow all logs
	docker compose logs -f --tail=100

ps:
	docker compose ps

test:          ## smoke-test the stack
	@curl -sf localhost:8000/health  && echo " ✅ api health"
	@curl -sf localhost:8000/ready   && echo " ✅ api ready (db+cache)"
	@curl -sf localhost:8080/healthz && echo " ✅ web health"
	@curl -sf localhost:8000/items   | head -c 200 && echo " ✅ items"

shell-api:
	docker compose exec api sh

shell-db:
	docker compose exec db psql -U $(DB_USER) -d $(DB_NAME)

nuke:          ## ☠️ destroy EVERYTHING including data
	docker compose down -v --remove-orphans
	docker compose build --no-cache

clean:
	docker system prune -f
```

---

## 3. Run the whole stack

```bash
cd 07-compose-stack

docker compose config                 # 1. validate the YAML & print the merged result
docker compose build                  # 2. build the api and web images
docker compose up -d                  # 3. start everything, in dependency order
docker compose ps                     # 4. status
```

**Expected `docker compose ps`:**

```
NAME          IMAGE                    STATUS                    PORTS
stack-db      postgres:17-alpine       Up 30 seconds (healthy)   0.0.0.0:5432->5432/tcp
stack-cache   redis:7-alpine           Up 30 seconds (healthy)   6379/tcp
stack-api     stack-api:1.0.0          Up 20 seconds (healthy)   0.0.0.0:8000->8000/tcp
stack-web     stack-web:1.0.0          Up 18 seconds (healthy)   0.0.0.0:8080->80/tcp
```

🌐 **http://localhost:8080** — the web UI
🌐 **http://localhost:8000/items** — data from **postgres**, cached in **redis**
🌐 **http://localhost:8000/net** — proves service DNS works
🌐 **http://localhost:8080/api/items** — the same data **proxied through nginx** (one origin, no CORS)

```bash
docker compose logs -f api            # follow one service (Ctrl+C)
docker compose logs --tail=50 db
docker compose exec api sh            # shell INSIDE the running api container
  wget -qO- http://db:5432 2>&1 | head -1     # it can REACH db by name
  env | grep -E 'DATABASE|REDIS'
  exit
docker compose exec db psql -U appuser -d appdb -c '\dt'
docker compose exec db psql -U appuser -d appdb -c 'SELECT * FROM items;'
docker compose exec cache redis-cli KEYS '*'
docker compose stats --no-stream      # live resource usage per service
docker compose top                    # processes inside each container
```

Add data and watch the cache work:
```bash
curl -X POST localhost:8000/items -H 'Content-Type: application/json' -d '{"name":"Learned docker compose"}'
curl -s localhost:8000/items | python3 -m json.tool     # "source": "postgres"
curl -s localhost:8000/items | python3 -m json.tool     # "source": "redis-cache"  ← 2nd call
docker compose logs --tail 5 api                        # cache MISS, then cache HIT
```

Tear down:
```bash
docker compose down            # containers + networks removed, VOLUMES KEPT
docker compose up -d           # your data is still there ✅
docker compose down -v         # ☠️ volumes deleted → all data gone
```

---

## 4. 🔍 The four concepts that make Compose work

### ① DNS by service name
Inside the network, the API reaches postgres at hostname **`db`** and Redis at **`cache`** — not `localhost`, not an IP address.

```bash
curl -s localhost:8000/net | python3 -m json.tool
# {"db":"172.21.0.2", "cache":"172.21.0.3", "web":"172.21.0.4", "api":"172.21.0.5", ...}
docker compose exec api ping -c1 db
docker network inspect learn-stack_backend --format '{{range .Containers}}{{.Name}} {{end}}'
```

> ⚠️ `localhost` inside a container means **that container itself**. The #1 Compose beginner bug is `DATABASE_URL=postgres://user:pass@localhost:5432/db` — it must be `@db:5432`.

### ② `depends_on` + `condition: service_healthy`
Plain `depends_on: [db]` only controls **start order**, not **readiness**. Postgres takes ~5 s to accept connections, so the API would crash on boot. `condition: service_healthy` makes Compose wait for the healthcheck to pass first.

Prove it:
```bash
docker compose down
docker compose up -d --wait            # blocks until ALL services are healthy
docker compose ps
```

### ③ Networks isolate
`db` and `cache` are on **`backend` only**. `web` is on both. So:

```bash
docker compose exec web wget -qO- http://api:8000/health    # ✅ web CAN reach api
docker compose exec web sh -c 'getent hosts db || echo "cannot resolve db"'   # ✅ same network here
```
Move `web` to `[frontend]` only in the YAML, `docker compose up -d`, and the nginx `/api/` proxy immediately breaks — **that's** the security value of separating networks: the public-facing tier physically cannot reach the database.

### ④ Volumes persist across `down`
`db-data` and `cache-data` are **named volumes**. `docker compose down` removes containers and networks but keeps volumes, so your data survives. `down -v` deletes them.

```bash
docker volume ls --filter name=learn-stack
docker volume inspect learn-stack_db-data --format '{{.Mountpoint}}'
```

---

## 5. ✅ Check yourself

1. Why does the API use `db` as the database hostname instead of `localhost`?
2. What breaks if I remove `condition: service_healthy`?
3. Does `docker compose down` delete my data?
4. Why does `db-init/01-schema.sql` only run the *first* time?

<details>
<summary>👉 Answers</summary>

1. Each container has its **own network namespace**; `localhost` refers to the container itself. Compose creates a user-defined bridge network with an embedded DNS server that resolves **service names** (and `container_name`, and network aliases) to container IPs. IPs change on restart — names don't.
2. Compose would start `api` as soon as the `db` **container** exists, not when Postgres accepts connections. The API's first queries fail → crash → `restart: unless-stopped` loops it until the DB is up. Our app also retries internally for 30 × 2 s, which is the belt-and-braces approach — but the healthcheck condition is the correct fix.
3. **No.** `down` removes containers, networks and (by default) *anonymous* volumes. **Named** volumes declared under `volumes:` survive. `docker compose down -v` removes them too — and that's permanent data loss.
4. The postgres image runs `/docker-entrypoint-initdb.d/*` **only when the data directory is empty** (first initialisation). On later starts the volume already has data, so the scripts are skipped — otherwise every restart would wipe and re-seed your database. To force re-initialisation: `docker compose down -v && docker compose up -d`.
</details>

---

## 6. 🔨 Extra Tasks (do all 5)

### ▶ Task 7.1 — Add a 5th service: Adminer (a database web UI)

Add to `docker-compose.yml`:

```yaml
  adminer:
    image: adminer:latest
    container_name: stack-adminer
    restart: unless-stopped
    depends_on:
      db:
        condition: service_healthy
    ports:
      - "8081:8080"
    environment:
      ADMINER_DEFAULT_SERVER: db
      ADMINER_DESIGN: pepa-linha
    networks: [backend]
```

```bash
docker compose up -d adminer
docker compose ps
```

🌐 **http://localhost:8081** → System: **PostgreSQL**, Server: **db**, User: `appuser`, Password: `apppass`, Database: `appdb`.

Browse `items`, insert a row through the UI, then confirm the API returns it:
```bash
curl -s localhost:8000/items | python3 -m json.tool
```

**Question:** Why is `ADMINER_DEFAULT_SERVER: db` and not `localhost`? Should this service exist in production?

<details>
<summary>👉 Answer</summary>

Because Adminer runs **in its own container** — `localhost` would be the Adminer container, where no database is listening. It must use the Docker network DNS name `db`.

**It must not be exposed in production.** Adminer is a full database console: if it's reachable from the internet, anyone who guesses credentials (or exploits an Adminer CVE — there have been several) owns your data. Options:
- Don't include it at all in the prod Compose file.
- Put it behind a **Compose profile**: `profiles: ["debug"]`, started only with `docker compose --profile debug up -d`.
- Remove its `ports:` mapping entirely and reach it through an SSH tunnel: `ssh -L 8081:localhost:8081 server`.
- If you must expose it, put it behind a VPN/auth proxy.

Also note it's on `[backend]` only — it can reach `db`, but the internet reaches *it* via the published port. Publishing a port does **not** require the service to be on a "frontend" network; `-p` maps host → container directly.
</details>

---

### ▶ Task 7.2 — Add a `dev` profile with hot reload

```yaml
  api-dev:
    profiles: ["dev"]                 # ← only starts with --profile dev
    build:
      context: ./api
    image: stack-api:dev
    restart: "no"
    depends_on:
      db:    { condition: service_healthy }
      cache: { condition: service_healthy }
    environment:
      DATABASE_URL: postgresql://${DB_USER:-appuser}:${DB_PASSWORD:-apppass}@db:5432/${DB_NAME:-appdb}
      REDIS_URL: redis://cache:6379/0
      SERVICE_NAME: api-dev
    ports:
      - "8001:8000"
    volumes:
      - ./api:/app                    # ← BIND MOUNT: your host source, live
    command: ["python", "app.py"]     # override the image's CMD
    networks: [backend]
```

```bash
docker compose ps                            # api-dev NOT running
docker compose --profile dev up -d           # now it is
docker compose --profile dev ps

# edit api/app.py on your HOST (change a string in the "/" route), then:
curl -s localhost:8001/ | python3 -m json.tool     # ← change is LIVE, no rebuild
docker compose restart api-dev                     # restart to reload the process
docker compose --profile dev down
```

**Questions:** What are profiles for? Why does `docker compose down` (without `--profile dev`) leave `api-dev` running? What's the trade-off of the bind mount?

<details>
<summary>👉 Answer</summary>

**Profiles** let one Compose file describe several *environments*. Services without a `profiles:` key always start; services with one start only when that profile is activated (`--profile dev`, or `COMPOSE_PROFILES=dev` in `.env`). Typical uses: `dev` (hot reload, debuggers, Adminer), `test` (test runners, mocks), `monitoring` (Prometheus/Grafana), `tools` (one-off migrations).

`docker compose down` without the profile **ignores** profiled services entirely — they aren't part of the "default" project view, so they're left running. Use `docker compose --profile dev down`. This surprises everyone once; `docker compose ps -a` shows what's actually there.

**Bind-mount trade-offs:**
- ✅ Edit on host → instantly visible in the container. No rebuild loop.
- ❌ The image is no longer self-contained; the service depends on your host directory layout.
- ❌ Dependencies are **not** reinstalled when `requirements.txt` changes — you still need `docker compose build`.
- ❌ On macOS/Windows the file-sharing layer is slow for I/O-heavy paths; never bind-mount `node_modules` or `.venv` — use an anonymous volume to shadow it:
  ```yaml
  volumes:
    - ./api:/app
    - /app/__pycache__        # anonymous volume masks the host's version
  ```
- ❌ Python doesn't auto-reload — you need a watcher (`watchmedo`, `uvicorn --reload`, `nodemon`). The `restart` here is manual.

**Rule:** bind mounts for development, `COPY` (immutable image) for production.
</details>

---

### ▶ Task 7.3 — Scale the API to 3 replicas behind nginx

**Step 1 — remove what prevents scaling.** Delete `container_name: stack-api` and change the port mapping (a fixed host port can only be bound once):

```yaml
  api:
    build: { context: ./api }
    # container_name: stack-api      ← REMOVED: names must be unique
    ports:
      - "8000"                       # ← no host port; reachable only inside the network
```

```bash
docker compose up -d --scale api=3
docker compose ps                    # learn-stack-api-1, -2, -3
```

**Step 2 — load balance in nginx.** In `web/nginx.conf`:

```nginx
upstream api_pool {
    least_conn;                      # or: round-robin (default), ip_hash, random
    server api:8000;                 # Docker DNS returns ALL replica IPs and rotates them
}

server {
    listen 80;
    location /api/ {
        proxy_pass http://api_pool/;
        proxy_next_upstream error timeout http_502 http_503;   # failover to another replica
        proxy_set_header Host $host;
    }
    # ... rest unchanged
}
```

```bash
docker compose up -d --build web
for i in $(seq 1 12); do
  curl -s localhost:8080/api/ | python3 -c "import sys,json;print(json.load(sys.stdin)['hostname'])"
done
docker compose logs -f api           # watch requests spread across the 3 containers
```

**Step 3 — prove failover.** Kill one replica mid-traffic:
```bash
docker compose kill api-2
curl -s localhost:8080/api/health    # still works ✅
docker compose ps
docker compose up -d --scale api=3   # bring it back
```

<details>
<summary>👉 Answer / notes</summary>

**Why `container_name` blocks scaling:** it forces a fixed name, so a second replica would collide. Same for `ports: "8000:8000"` — the host port is already taken. Removing the host-side port means the service is only reachable inside the Docker network, which is *more* secure anyway; nginx becomes the single public entry point.

**How DNS load-balancing works:** for a scaled service, Docker's embedded DNS returns multiple A records for `api` and rotates their order. nginx resolves at startup by default, so for truly dynamic behaviour you'd add `resolver 127.0.0.11 valid=10s;` and use a variable in `proxy_pass`. `least_conn` sends new requests to the replica with fewest active connections.

**What breaks when you scale — the important lesson:**
- Any **in-memory state** (sessions, caches, counters) becomes inconsistent across replicas. That's exactly why this stack has Redis: shared state lives *outside* the app.
- **SQLite or file-based storage** breaks completely — three replicas writing one bind-mounted file. Our Project 5 notes app cannot be scaled this way; Postgres can.
- Anything that must run **once** (DB migrations, cron jobs) must not be in the scaled service — use a separate one-shot `migrate` service with `restart: "no"` and `depends_on`.

**This is the "12-factor" lesson in practice:** stateless app containers + external state store = horizontal scaling for free.
</details>

---

### ▶ Task 7.4 — Resource limits, OOM kills and graceful shutdown

```yaml
  api:
    # ... existing keys ...
    stop_grace_period: 20s
    deploy:
      resources:
        limits:
          cpus: "0.50"
          memory: 256M
        reservations:
          memory: 64M
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
```

```bash
docker compose up -d
docker compose stats                 # watch the MEM LIMIT column
docker stats stack-api-1             # live view

# force an OOM kill: ask the api to allocate 500 MB
docker compose exec api python -c "x = bytearray(500*1024*1024); print(len(x))"
docker compose ps -a                 # did the container die?
docker compose logs --tail 20 api
docker inspect $(docker compose ps -q api | head -1) \
  --format 'OOMKilled={{.State.OOMKilled}} ExitCode={{.State.ExitCode}} RestartCount={{.RestartCount}}'
```

<details>
<summary>👉 Answer</summary>

`OOMKilled=true`, `ExitCode=137` (128 + 9 = SIGKILL). The kernel's OOM killer terminated the process because it exceeded the cgroup memory limit. With `restart: unless-stopped` Compose brings it back, and `RestartCount` increments.

**Key points:**
- `deploy.resources.limits` in Compose **v2** applies to plain `docker compose up` (it maps to `--memory`/`--cpus`). In old Compose v1 it was Swarm-only — a frequent source of "my limits are ignored" confusion. Verify with `docker inspect`.
- **Memory limits are hard** (OOM kill). **CPU limits are soft** — the container is throttled, not killed.
- Set limits **above** your app's real working set plus headroom, or you get random 137s under load that are miserable to diagnose. Set **reservations** to help the scheduler.
- `logging.options.max-size` prevents a chatty container from filling your disk — a very common production outage.
- `stop_grace_period: 20s` is how long Docker waits after `SIGTERM` before `SIGKILL`. It must be **≥** the time your app needs to drain in-flight requests, and it interacts with `STOPSIGNAL` in your Dockerfile (Project 5, Task 5.5) and with exec-form `CMD` (Project 4) — if signals aren't forwarded, the grace period is just wasted waiting.
- In Kubernetes the equivalents are `resources.limits/requests` and `terminationGracePeriodSeconds`.

**Exercise:** lower the limit to `memory: 64M`, restart, and watch the app fail to boot (Python itself needs ~30–40 MB). That teaches you to measure before you set.
</details>

---

### ▶ Task 7.5 — Fold Project 5's notes app into the stack + write a `Makefile`

**Step 1.** Copy your Project 5 folder into `notes/` inside this project, then add:

```text
# ⚠️ YAML FRAGMENT — not a complete file (so it is shown as text, not parsed YAML).
#    Add the `notes:` block under your existing `services:` key,
#    and add `notes-data:` under your existing `volumes:` key.
  notes:
    build:
      context: ./notes
    image: stack-notes:1.0.0
    restart: unless-stopped
    environment:
      DATA_DIR: /app/data
      PORT: "8000"
    volumes:
      - notes-data:/app/data          # ← its OWN volume, isolated from postgres
    ports:
      - "8002:8000"
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://127.0.0.1:8000/ready"]
      interval: 15s
      timeout: 3s
      retries: 3
      start_period: 5s
    networks: [frontend, backend]

volumes:
  db-data:
  cache-data:
  notes-data:        # ← add this too
```

```bash
docker compose up -d --build
docker compose ps                      # 5 services, all healthy
curl -s localhost:8002/ready | python3 -m json.tool
curl -X POST localhost:8002/notes -H 'Content-Type: application/json' -d '{"text":"Integrated into compose"}'
docker compose down && docker compose up -d && curl -s localhost:8002/notes   # data survived ✅
```

**Step 2.** The `Makefile` above already gives you `make up`, `make down`, `make logs`, `make test`, `make nuke`. Extend it:

```makefile
health:        ## wait for the whole stack to become healthy
	docker compose up -d --wait --timeout 120
	docker compose ps

items:
	@curl -s localhost:8000/items | python3 -m json.tool

notes:
	@curl -s localhost:8002/notes | python3 -m json.tool

rebuild:       ## rebuild one service and restart only it
	docker compose up -d --build --no-deps $(svc)

watch:         ## rebuild on file changes (needs `entr` or `watchexec`)
	find . -name '*.py' -o -name 'Dockerfile' | entr -r docker compose up -d --build
```

```bash
make up
make health
make test
make ps
make logs
make svc=api rebuild
make nuke          # ☠️ only when you really mean it
```

<details>
<summary>👉 Answer — why this is the real-world workflow</summary>

**You now have the exact developer experience used on professional teams:** one command to start an entire multi-service platform, identical on every machine, with no local Postgres, Redis or Python installation.

Key takeaways:
- **Each stateful service gets its own named volume.** Sharing one volume between Postgres and the notes app would be a disaster. `docker compose down -v` destroys all of them — which is why `make nuke` should be scary-looking.
- **`--no-deps`** with `up -d --build <svc>` rebuilds and restarts *only* that service, leaving the database untouched. Huge time-saver; without it Compose may recreate dependencies too.
- **`up -d --wait`** blocks until every healthcheck passes — perfect for CI, so your tests never race the stack startup.
- **A Makefile (or `justfile`, `taskfile`, or npm scripts) is documentation.** A new team member types `make help` and understands the project in 30 seconds. This is genuinely one of the highest-value habits in DevOps.
- Note the notes app is on `[frontend, backend]` even though it doesn't need `backend` — trim that to `[frontend]` for proper isolation. Ask yourself for every service: *what does it actually need to reach?*

**Where to go from here:** put this Compose file into CI (GitHub Actions has Docker preinstalled — `docker compose up -d --wait` then run integration tests), then learn to swap Compose for **Kubernetes** when you need multi-node scheduling. The concepts — images, healthchecks, volumes, networks, env config — transfer directly.
</details>

---

## 7. 🧹 Clean up

```bash
docker compose down -v --remove-orphans
docker rmi stack-api:1.0.0 stack-web:1.0.0 stack-notes:1.0.0 2>/dev/null
docker system prune -f
docker volume ls
docker network ls       # Compose networks are gone; `bridge`/`host`/`none` always remain
```

---

## ➡️ Next

🏆 **`02-CAPSTONE-END-TO-END.md`** — the complete end-to-end project: a full task-management platform (API + PostgreSQL + Redis + nginx reverse proxy) with multi-stage builds, non-root users, healthchecks, backups, tests and deployment — plus **10 graded tasks with complete answers**.

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish%20Kumar%20Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn → <https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260>
🐙 GitHub → <https://github.com/3558Bhk>

*Built for engineers who learn by breaking things on purpose.*

</div>
