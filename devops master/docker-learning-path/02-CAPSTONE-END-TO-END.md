# 🏆 CAPSTONE — Complete End-to-End Docker Project

# **TaskNest**: a task-management platform, fully containerised

> **Part of the Docker Learning Path.** Do this **after** Projects 1–7.
>
> ⏱️ **Time:** 3–5 hours (or one focused weekend) · 🎓 **Level:** intermediate → job-ready
> 🎯 **Everything at once:** multi-stage builds, `docker compose`, PostgreSQL, Redis, nginx reverse proxy, non-root users, healthchecks, volumes, backups, tests, CI/CD, registry publishing.

---

## 🧭 Table of contents

**Sections A–C — the capstone project**

| | Section | Contents |
|---|---|---|
| 📌 | **A — THE TASK** | The assignment: background, target architecture, **10 requirements**, Definition of Done, suggested order of work |
| 📦 | **B — THE STARTING CODE** | The application you're given (pure Python stdlib): `config.py`, `store.py`, `cache.py`, `handlers.py`, `server.py`, tests, SQL schema, web UI |
| ✅ | **C — THE ANSWERS** | Complete solutions: multi-stage `api/Dockerfile` · `web/Dockerfile` + `nginx.conf` · the full `docker-compose.yml` · `Makefile` · `backup.sh` / `restore.sh` / `smoke-test.sh` · requirement-by-requirement proof · GitHub Actions CI · runbook · extension ideas |

**Projects 8 → 13 — now in their own files** (each with **CASE 1: simple Dockerfile** and **CASE 2: multi-stage Dockerfile**)

| Project | File | Stack |
|---|---|---|
| **8** | [`11-PROJECT-8-react-frontend.md`](11-PROJECT-8-react-frontend.md) | ⚛️ React (Vite) — node dev server → nginx + static build |
| **9** | [`12-PROJECT-9-java-backend.md`](12-PROJECT-9-java-backend.md) | ☕ Java / Spring Boot — prebuilt jar → JDK build stage + layered jar |
| **10** | [`13-PROJECT-10-react-java-fullstack.md`](13-PROJECT-10-react-java-fullstack.md) | ⚛️ + ☕ — two ports + CORS → one origin behind nginx |
| **11** | [`14-PROJECT-11-react-python-fullstack.md`](14-PROJECT-11-react-python-fullstack.md) | ⚛️ + 🐍 — uvicorn `--reload` as root → wheels + tests + gunicorn non-root |
| **12** | [`15-PROJECT-12-react-go-fullstack.md`](15-PROJECT-12-react-go-fullstack.md) | ⚛️ + 🐹 — full Go SDK → static binary → `FROM scratch` |
| **13** | [`16-PROJECT-13-databases.md`](16-PROJECT-13-databases.md) | 🗄️ MySQL · MongoDB · Redis · DynamoDB Local · Cassandra · Neo4j |

---
---

# 📌 SECTION A — THE TASK (the assignment)

Read this section first. It is written like a **real ticket from a real team lead**. Try to build it yourself before opening Section C (the answers).

## A.1 Background

Your team has a Python task-management API that currently only runs on one developer's laptop. Nobody else can reproduce it. The ops team wants it containerised so it can run identically in dev, staging, CI and production.

You are given the application code (Section B). Your job is **everything around it**: the Dockerfiles, the compose stack, the operational tooling.

## A.2 The target architecture

```
                          ┌──────────────────────────────────────────┐
   your browser           │            docker network: backend        │
        │                 │                                          │
        ▼                 │   ┌───────────┐        ┌──────────────┐  │
  http://localhost:8080 ──┼──▶│   nginx   │───────▶│   api        │  │
                          │   │  (web)    │  /api  │  (FastHTTP)  │  │
                          │   │  port 80  │        │  port 8000   │  │
                          │   └───────────┘        └──┬───────┬───┘  │
                          │      static UI            │       │      │
                          │                     ┌─────▼──┐ ┌──▼────┐ │
                          │                     │ postgres│ │ redis │ │
                          │                     │  :5432  │ │ :6379 │ │
                          │                     └────┬────┘ └───┬───┘ │
                          └──────────────────────────┼──────────┼─────┘
                                                     ▼          ▼
                                              volume:       volume:
                                              db-data      cache-data
```

**Four services:** `web` (nginx) · `api` (Python) · `db` (PostgreSQL 17) · `cache` (Redis 7)

## A.3 The 10 requirements

### 🔹 Requirement 1 — Build a multi-stage `api` image
- Stage 1 `builder`: install build tooling, compile wheels, **run the test suite** — the build must fail if tests fail.
- Stage 2 `runtime`: alpine-based, **no compiler, no pytest**, only the code that actually runs.
- Final image must be **under 80 MB**.
- Prove it: `docker images tasknest-api` and `docker history tasknest-api`.

### 🔹 Requirement 2 — Never run as root
- Create a system user `app` (uid 100) inside the image.
- All app files and the data directory must be owned by it.
- `docker run --rm tasknest-api whoami` must print `app`.
- The container must still be able to write to its data volume.

### 🔹 Requirement 3 — Configuration only through environment variables
- Zero hard-coded hosts, ports, passwords or paths in the application.
- `DATABASE_URL`, `REDIS_URL`, `PORT`, `APP_ENV`, `LOG_LEVEL` must all come from the environment.
- The **same image** must run as `development`, `staging` and `production` without a rebuild.
- No secret may appear in `docker history`.

### 🔹 Requirement 4 — Health: liveness *and* readiness
- `GET /health` → 200 if the process is alive (**no dependency checks**).
- `GET /ready` → 200 only if PostgreSQL **and** Redis are reachable, else 503.
- A Dockerfile `HEALTHCHECK` and a Compose `healthcheck` must both exist.
- `docker compose up -d --wait` must block until every service is healthy.

### 🔹 Requirement 5 — Persistence that survives everything
- Tasks must survive `docker compose down` **and** container deletion.
- Use **named volumes** for PostgreSQL data, Redis AOF and the API's own storage.
- `docker compose down -v` must be the only thing that destroys data.
- Demonstrate it with a script.

### 🔹 Requirement 6 — nginx as a single entry point
- One published port for the whole platform (**8080**).
- nginx serves the static UI at `/` and **reverse-proxies** `/api/*` to the api service.
- The browser must never talk to port 8000 directly (no CORS anywhere).
- gzip enabled, a `/healthz` endpoint, and a custom 404 page.
- Only `web` is on the frontend network; `db` and `cache` must **not** be reachable from outside.

### 🔹 Requirement 7 — Security hardening
- No secrets in images, layers, or committed files.
- Drop all capabilities, enable `no-new-privileges`, read-only root filesystem where possible.
- Memory and CPU limits on every service.
- Log rotation configured so a chatty container can't fill the disk.
- A secret must be injected at runtime only, and you must prove it isn't in the image.

### 🔹 Requirement 8 — Operational tooling
- A `Makefile` (or `start.sh`/`stop.sh`) with: `up`, `down`, `logs`, `ps`, `test`, `backup`, `restore`, `nuke`, `help`.
- A **backup** command that dumps PostgreSQL to a timestamped `.sql` file on the host.
- A **restore** command that rebuilds the database from that dump.
- A `smoke-test.sh` that verifies the whole platform end to end and exits non-zero on any failure.

### 🔹 Requirement 9 — A debuggable developer experience
- A `dev` Compose profile with hot reload via bind mounts.
- A `debug` build target so you can get a shell into the *builder* stage.
- Documented one-liners for the 5 most common debugging situations.

### 🔹 Requirement 10 — Ship it
- Tag images with a version derived from a build argument.
- Push to a registry (Docker Hub or GHCR).
- A GitHub Actions workflow that builds, tests, scans and pushes the image.
- A written **runbook**: how to deploy, how to roll back, how to diagnose the top 5 incidents.

## A.4 Definition of Done — the acceptance test

Your project passes when **all** of these succeed from a clean machine with only Docker installed:

```bash
git clone <your-repo> && cd <your-repo>
make up                       # everything builds and becomes healthy
make smoke                    # all assertions pass, exit code 0
curl -s localhost:8080/api/health      # {"status":"ok"}
curl -s localhost:8080/api/ready       # {"ready":true,...}
curl -s localhost:8080/                # the HTML UI, served by nginx
docker compose ps                      # 4 services, all (healthy)
docker compose exec api whoami         # app
docker history tasknest-api:1.0.0 --no-trunc | grep -iE 'password|secret'   # NO output
make backup && make nuke && make restore    # data comes back
make down
```

## A.5 Suggested order of work

| Phase | What | Time |
|---|---|---|
| 1 | Get `api` running in a **single-stage** Dockerfile. Ugly but working. | 30 min |
| 2 | Add `db` + `cache` in `docker-compose.yml`. Make the API talk to them. | 45 min |
| 3 | Convert to **multi-stage**, add tests, add non-root `USER`. | 45 min |
| 4 | Add `HEALTHCHECK`, `/ready`, `depends_on: service_healthy`. | 20 min |
| 5 | Add `web` (nginx), reverse proxy, move everything behind port 8080. | 40 min |
| 6 | Hardening: limits, capabilities, read-only, log rotation, secrets. | 30 min |
| 7 | `Makefile`, backups, smoke tests. | 40 min |
| 8 | CI/CD, registry push, runbook. | 40 min |

---
---

# 📦 SECTION B — THE STARTING CODE

Create this exact structure. These are the **application** files — they are *given* to you, and deliberately contain **no Docker knowledge**. Everything Docker-related is your job (Section C).

```
tasknest/
├── Makefile
├── README.md
├── docker-compose.yml
├── .env.example
├── .gitignore
├── .dockerignore
├── scripts/
│   ├── smoke-test.sh
│   ├── backup.sh
│   └── restore.sh
├── api/
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── src/
│   │   ├── __init__.py
│   │   ├── config.py
│   │   ├── store.py
│   │   ├── cache.py
│   │   ├── handlers.py
│   │   └── server.py
│   └── tests/
│       └── test_store.py
├── web/
│   ├── Dockerfile
│   ├── nginx.conf
│   └── site/
│       ├── index.html
│       ├── style.css
│       └── 404.html
└── db/
    └── init/
        └── 01-schema.sql
```

## B.1 `api/src/config.py`

```python
"""All configuration comes from the environment. Nothing is hard-coded."""
import os
from dataclasses import dataclass, field
from urllib.parse import urlparse


def _bool(name: str, default: bool = False) -> bool:
    return os.environ.get(name, str(default)).strip().lower() in ("1", "true", "yes", "on")


@dataclass(frozen=True)
class Postgres:
    host: str
    port: int
    user: str
    password: str
    database: str

    @classmethod
    def from_url(cls, url: str) -> "Postgres":
        u = urlparse(url)
        return cls(
            host=u.hostname or "db",
            port=u.port or 5432,
            user=u.username or "tasknest",
            password=u.password or "",
            database=(u.path or "/tasknest").lstrip("/"),
        )

    @property
    def dsn(self) -> str:
        return f"postgresql://{self.user}:{self.password}@{self.host}:{self.port}/{self.database}"


@dataclass(frozen=True)
class Settings:
    app_name: str = field(default_factory=lambda: os.environ.get("APP_NAME", "TaskNest"))
    version: str = field(default_factory=lambda: os.environ.get("APP_VERSION", "0.0.0-dev"))
    commit: str = field(default_factory=lambda: os.environ.get("GIT_COMMIT", "unknown"))
    environment: str = field(default_factory=lambda: os.environ.get("APP_ENV", "development"))
    host: str = field(default_factory=lambda: os.environ.get("HOST", "0.0.0.0"))
    port: int = field(default_factory=lambda: int(os.environ.get("PORT", "8000")))
    log_level: str = field(default_factory=lambda: os.environ.get("LOG_LEVEL", "INFO").upper())
    data_dir: str = field(default_factory=lambda: os.environ.get("DATA_DIR", "/app/data"))
    cache_enabled: bool = field(default_factory=lambda: _bool("CACHE_ENABLED", True))
    cache_ttl: int = field(default_factory=lambda: int(os.environ.get("CACHE_TTL", "15")))
    startup_retries: int = field(default_factory=lambda: int(os.environ.get("STARTUP_RETRIES", "30")))
    startup_delay: float = field(default_factory=lambda: float(os.environ.get("STARTUP_DELAY", "2")))

    @property
    def db(self) -> Postgres:
        return Postgres.from_url(
            os.environ.get("DATABASE_URL", "postgresql://tasknest:tasknest@db:5432/tasknest")
        )

    @property
    def redis(self):
        u = urlparse(os.environ.get("REDIS_URL", "redis://cache:6379/0"))
        return (u.hostname or "cache", u.port or 6379, (u.path or "/0").lstrip("/") or "0")


settings = Settings()
```

## B.2 `api/src/store.py`

```python
"""PostgreSQL-backed task store. Shells out to `psql` so there are ZERO
third-party dependencies — the image stays tiny and the build stays offline-friendly.
(In production you would use psycopg[binary]; the Docker lessons are identical.)"""
import json
import os
import subprocess
from datetime import datetime, timezone
from typing import Any

from .config import settings


class StoreError(RuntimeError):
    pass


def _run(sql: str, timeout: int = 5) -> list[list[str]]:
    db = settings.db
    env = {**os.environ, "PGPASSWORD": db.password, "PGCONNECT_TIMEOUT": str(timeout)}
    try:
        proc = subprocess.run(
            ["psql", "-h", db.host, "-p", str(db.port), "-U", db.user, "-d", db.database,
             "-v", "ON_ERROR_STOP=1", "-t", "-A", "-F", "\x1f", "-c", sql],
            capture_output=True, text=True, timeout=timeout + 3, env=env,
        )
    except FileNotFoundError as exc:
        raise StoreError("psql client is not installed in this image") from exc
    except subprocess.TimeoutExpired as exc:
        raise StoreError(f"query timed out after {timeout}s") from exc
    if proc.returncode != 0:
        raise StoreError(proc.stderr.strip() or f"psql exited {proc.returncode}")
    return [line.split("\x1f") for line in proc.stdout.strip().splitlines() if line.strip()]


def _q(value: Any) -> str:
    """Minimal SQL literal quoting."""
    if value is None:
        return "NULL"
    if isinstance(value, bool):
        return "TRUE" if value else "FALSE"
    if isinstance(value, (int, float)):
        return str(value)
    return "'" + str(value).replace("'", "''") + "'"


def ping() -> bool:
    try:
        _run("SELECT 1", timeout=3)
        return True
    except StoreError:
        return False


def version() -> str:
    rows = _run("SELECT version()")
    return rows[0][0] if rows else "unknown"


def create_task(title: str, priority: str = "medium", tags: str = "") -> dict:
    rows = _run(
        "INSERT INTO tasks (title, priority, tags) "
        f"VALUES ({_q(title)}, {_q(priority)}, {_q(tags)}) "
        "RETURNING id, title, priority, tags, done, "
        "to_char(created_at AT TIME ZONE 'UTC','YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"')"
    )
    return _row_to_task(rows[0])


def list_tasks(status: str | None = None, priority: str | None = None, limit: int = 100) -> list[dict]:
    where, clauses = [], []
    if status == "done":
        clauses.append("done = TRUE")
    elif status == "todo":
        clauses.append("done = FALSE")
    if priority:
        clauses.append(f"priority = {_q(priority)}")
    if clauses:
        where.append("WHERE " + " AND ".join(clauses))
    sql = (
        "SELECT id, title, priority, tags, done, "
        "to_char(created_at AT TIME ZONE 'UTC','YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"') "
        f"FROM tasks {' '.join(where)} ORDER BY done ASC, id DESC LIMIT {int(limit)}"
    )
    return [_row_to_task(r) for r in _run(sql)]


def get_task(task_id: int) -> dict | None:
    rows = _run(
        "SELECT id, title, priority, tags, done, "
        "to_char(created_at AT TIME ZONE 'UTC','YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"') "
        f"FROM tasks WHERE id = {int(task_id)}"
    )
    return _row_to_task(rows[0]) if rows else None


def update_task(task_id: int, done: bool | None = None, title: str | None = None,
                priority: str | None = None) -> dict | None:
    sets = []
    if done is not None:
        sets.append(f"done = {_q(done)}")
    if title is not None:
        sets.append(f"title = {_q(title)}")
    if priority is not None:
        sets.append(f"priority = {_q(priority)}")
    if not sets:
        return get_task(task_id)
    sets.append("updated_at = now()")
    rows = _run(
        f"UPDATE tasks SET {', '.join(sets)} WHERE id = {int(task_id)} "
        "RETURNING id, title, priority, tags, done, "
        "to_char(created_at AT TIME ZONE 'UTC','YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"')"
    )
    return _row_to_task(rows[0]) if rows else None


def delete_task(task_id: int) -> bool:
    rows = _run(f"DELETE FROM tasks WHERE id = {int(task_id)} RETURNING id")
    return bool(rows)


def stats() -> dict:
    rows = _run(
        "SELECT count(*), count(*) FILTER (WHERE done), count(*) FILTER (WHERE NOT done), "
        "count(*) FILTER (WHERE priority='high' AND NOT done) FROM tasks"
    )
    total, done, todo, urgent = (int(x) for x in rows[0]) if rows else (0, 0, 0, 0)
    return {"total": total, "done": done, "todo": todo, "urgent_high": urgent,
            "completion_pct": round(done / total * 100, 1) if total else 0.0}


def _row_to_task(row: list[str]) -> dict:
    return {
        "id": int(row[0]),
        "title": row[1],
        "priority": row[2],
        "tags": [t for t in row[3].split(",") if t],
        "done": row[4] in ("t", "true", "TRUE"),
        "created_at": row[5],
    }
```

## B.3 `api/src/cache.py`

```python
"""A minimal Redis client (RESP protocol) written with the stdlib only.
Caching is BEST-EFFORT: if Redis is down the app must keep working."""
import json
import socket
from typing import Any

from .config import settings


def _send(*args: Any, timeout: float = 1.5) -> str:
    host, port, _db = settings.redis
    try:
        with socket.create_connection((host, int(port)), timeout=timeout) as sock:
            sock.settimeout(timeout)
            payload = f"*{len(args)}\r\n" + "".join(
                f"${len(str(a))}\r\n{a}\r\n" for a in args
            )
            sock.sendall(payload.encode())
            return sock.recv(1 << 16).decode(errors="replace").strip()
    except OSError:
        return "-ERR unreachable"


def ping() -> bool:
    return _send("PING").endswith("PONG")


def get(key: str) -> Any | None:
    if not settings.cache_enabled:
        return None
    reply = _send("GET", key)
    lines = reply.splitlines()
    if not lines or lines[0].startswith("$-1"):
        return None
    try:
        return json.loads(lines[-1])
    except (json.JSONDecodeError, IndexError):
        return None


def set(key: str, value: Any, ttl: int | None = None) -> None:
    if not settings.cache_enabled:
        return
    blob = json.dumps(value)
    _send("SETEX", key, ttl or settings.cache_ttl, blob)


def delete(*keys: str) -> None:
    if settings.cache_enabled and keys:
        _send("DEL", *keys)


def invalidate_lists() -> None:
    delete("tasks:list", "tasks:stats")
```

## B.4 `api/src/handlers.py`

```python
"""HTTP routing — pure stdlib."""
import json
import socket
import time
from datetime import datetime, timezone

from . import cache, store
from .config import settings

START_TIME = time.time()
PRIORITIES = {"low", "medium", "high"}


def info() -> dict:
    return {
        "service": settings.app_name,
        "version": settings.version,
        "commit": settings.commit,
        "environment": settings.environment,
        "hostname": socket.gethostname(),
        "pid": __import__("os").getpid(),
        "uptime_seconds": round(time.time() - START_TIME, 1),
        "server_time_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "database": f"{settings.db.user}@{settings.db.host}:{settings.db.port}/{settings.db.database}",
        "redis": f"{settings.redis[0]}:{settings.redis[1]}",
        "routes": ["/", "/api/health", "/api/ready", "/api/info", "/api/tasks",
                   "/api/tasks/<id>", "/api/tasks/<id>/toggle", "/api/stats"],
    }


def health() -> tuple[int, dict]:
    """LIVENESS — must never touch a dependency."""
    return 200, {"status": "ok", "uptime_seconds": round(time.time() - START_TIME, 1)}


def ready() -> tuple[int, dict]:
    """READINESS — all dependencies must work."""
    db_ok, cache_ok = store.ping(), cache.ping()
    ok = db_ok and (cache_ok or not settings.cache_enabled)
    return (200 if ok else 503), {
        "ready": ok,
        "checks": {"database": db_ok, "cache": cache_ok,
                   "data_dir_writable": _writable(settings.data_dir)},
    }


def list_tasks(query: dict) -> tuple[int, dict]:
    cached = cache.get("tasks:list")
    if cached is not None and query.get("status") is None and query.get("priority") is None:
        return 200, {"source": "cache", "tasks": cached}
    try:
        tasks = store.list_tasks(status=query.get("status"), priority=query.get("priority"),
                                 limit=int(query.get("limit", 100)))
    except store.StoreError as exc:
        return 503, {"error": "database unavailable", "detail": str(exc)}
    if not query.get("status") and not query.get("priority"):
        cache.set("tasks:list", tasks)
    return 200, {"source": "database", "tasks": tasks}


def create_task(body: dict) -> tuple[int, dict]:
    title = str(body.get("title", "")).strip()
    if not title:
        return 400, {"error": "'title' is required"}
    if len(title) > 300:
        return 400, {"error": "'title' must be 300 characters or fewer"}
    priority = str(body.get("priority", "medium")).lower()
    if priority not in PRIORITIES:
        return 400, {"error": f"'priority' must be one of {sorted(PRIORITIES)}"}
    tags = ",".join(t.strip() for t in body.get("tags", []) if str(t).strip())[:200]
    try:
        task = store.create_task(title, priority, tags)
    except store.StoreError as exc:
        return 503, {"error": "database unavailable", "detail": str(exc)}
    cache.invalidate_lists()
    return 201, task


def get_task(task_id: int) -> tuple[int, dict]:
    try:
        task = store.get_task(task_id)
    except store.StoreError as exc:
        return 503, {"error": "database unavailable", "detail": str(exc)}
    return (200, task) if task else (404, {"error": f"task {task_id} not found"})


def toggle_task(task_id: int) -> tuple[int, dict]:
    try:
        current = store.get_task(task_id)
        if not current:
            return 404, {"error": f"task {task_id} not found"}
        task = store.update_task(task_id, done=not current["done"])
    except store.StoreError as exc:
        return 503, {"error": "database unavailable", "detail": str(exc)}
    cache.invalidate_lists()
    return 200, task


def delete_task(task_id: int) -> tuple[int, dict]:
    try:
        removed = store.delete_task(task_id)
    except store.StoreError as exc:
        return 503, {"error": "database unavailable", "detail": str(exc)}
    if not removed:
        return 404, {"error": f"task {task_id} not found"}
    cache.invalidate_lists()
    return 200, {"deleted": task_id}


def stats() -> tuple[int, dict]:
    cached = cache.get("tasks:stats")
    if cached is not None:
        return 200, {"source": "cache", **cached}
    try:
        data = store.stats()
    except store.StoreError as exc:
        return 503, {"error": "database unavailable", "detail": str(exc)}
    cache.set("tasks:stats", data)
    return 200, {"source": "database", **data}


def _writable(path: str) -> bool:
    probe = f"{path}/.probe"
    try:
        with open(probe, "w") as fh:
            fh.write("ok")
        __import__("os").remove(probe)
        return True
    except OSError:
        return False
```

## B.5 `api/src/server.py`

```python
"""Entrypoint: waits for dependencies, then serves forever."""
import json
import logging
import os
import signal
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

from . import cache, handlers, store
from .config import settings

logging.basicConfig(
    level=getattr(logging, settings.log_level, logging.INFO),
    format="%(asctime)s %(levelname)s [%(name)s] %(message)s",
    stream=sys.stdout,                      # logs go to STDOUT — never to files
)
log = logging.getLogger("tasknest")


def wait_for_dependencies() -> None:
    for attempt in range(1, settings.startup_retries + 1):
        db_ok, cache_ok = store.ping(), cache.ping()
        if db_ok and (cache_ok or not settings.cache_enabled):
            log.info("dependencies ready (database ✅ cache %s)", "✅" if cache_ok else "disabled")
            return
        log.warning("waiting for dependencies (%d/%d): database=%s cache=%s",
                    attempt, settings.startup_retries, db_ok, cache_ok)
        time.sleep(settings.startup_delay)
    log.error("dependencies never became ready — starting anyway so /health can report failure")


class Handler(BaseHTTPRequestHandler):
    server_version = f"{settings.app_name}/{settings.version}"
    protocol_version = "HTTP/1.1"

    # ---------- helpers ----------
    def _send(self, code: int, body, ctype: str = "application/json") -> None:
        if not isinstance(body, bytes):
            body = json.dumps(body, indent=2, default=str).encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("X-Served-By", f"{socket_hostname()}:{settings.port}")
        self.send_header("X-App-Version", settings.version)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def _body(self) -> dict:
        length = int(self.headers.get("Content-Length") or 0)
        if not length:
            return {}
        try:
            return json.loads(self.rfile.read(length))
        except json.JSONDecodeError:
            return {}

    # ---------- routes ----------
    def do_GET(self) -> None:      # noqa: N802
        url = urlparse(self.path)
        path = url.path.rstrip("/") or "/"
        query = {k: v[0] for k, v in parse_qs(url.query).items()}

        if path in ("/", "/api", "/api/"):
            return self._send(200, handlers.info())
        if path in ("/health", "/api/health"):
            return self._send(*handlers.health())
        if path in ("/ready", "/api/ready"):
            return self._send(*handlers.ready())
        if path in ("/info", "/api/info"):
            return self._send(200, handlers.info())
        if path in ("/tasks", "/api/tasks"):
            return self._send(*handlers.list_tasks(query))
        if path in ("/stats", "/api/stats"):
            return self._send(*handlers.stats())
        task_id = _task_id(path)
        if task_id is not None:
            return self._send(*handlers.get_task(task_id))
        return self._send(404, {"error": "no such route", "path": path})

    def do_POST(self) -> None:     # noqa: N802
        path = urlparse(self.path).path.rstrip("/")
        if path in ("/tasks", "/api/tasks"):
            return self._send(*handlers.create_task(self._body()))
        task_id = _task_id(path, suffix="/toggle")
        if task_id is not None:
            return self._send(*handlers.toggle_task(task_id))
        return self._send(404, {"error": "no such route", "path": path})

    def do_DELETE(self) -> None:   # noqa: N802
        path = urlparse(self.path).path.rstrip("/")
        task_id = _task_id(path)
        if task_id is not None:
            return self._send(*handlers.delete_task(task_id))
        return self._send(404, {"error": "no such route", "path": path})

    def do_HEAD(self) -> None:     # noqa: N802
        self.do_GET()

    def log_message(self, fmt, *args) -> None:
        log.info("%s %s %s", self.command, self.path, fmt % args)


def _task_id(path: str, suffix: str = "") -> int | None:
    target = f"/api/tasks/" + "{id}" + suffix
    for prefix in ("/api/tasks/", "/tasks/"):
        if path.startswith(prefix) and path.endswith(suffix):
            chunk = path[len(prefix): len(path) - len(suffix)].strip("/")
            if chunk.isdigit():
                return int(chunk)
    return None


def socket_hostname() -> str:
    import socket
    return socket.gethostname()


def _shutdown(signum, _frame) -> None:
    log.info("received signal %s — draining and exiting cleanly", signum)
    sys.exit(0)


def main() -> int:
    signal.signal(signal.SIGTERM, _shutdown)
    signal.signal(signal.SIGINT, _shutdown)

    os.makedirs(settings.data_dir, exist_ok=True)
    log.info("%s v%s (%s) starting as uid=%d on %s:%d",
             settings.app_name, settings.version, settings.environment,
             os.getuid(), settings.host, settings.port)
    wait_for_dependencies()

    httpd = ThreadingHTTPServer((settings.host, settings.port), Handler)
    httpd.daemon_threads = True
    log.info("ready — accepting connections")
    try:
        httpd.serve_forever()
    except (KeyboardInterrupt, SystemExit):
        log.info("shutting down HTTP server")
        httpd.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

## B.6 `api/src/__init__.py`

```python
"""TaskNest API — standard library only."""
```

## B.7 `api/tests/test_store.py`

```python
"""Unit tests that run INSIDE the builder stage.
They test pure logic only — no database needed, so they always run."""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from src.config import Postgres, Settings          # noqa: E402
from src.store import _q, _row_to_task              # noqa: E402


def test_postgres_from_url():
    db = Postgres.from_url("postgresql://u:p@dbhost:6543/mydb")
    assert (db.host, db.port, db.user, db.password, db.database) == ("dbhost", 6543, "u", "p", "mydb")


def test_postgres_defaults():
    db = Postgres.from_url("")
    assert db.host == "db" and db.port == 5432


def test_settings_reads_env(monkeypatch):
    monkeypatch.setenv("PORT", "9999")
    monkeypatch.setenv("APP_ENV", "staging")
    s = Settings()
    assert s.port == 9999 and s.environment == "staging"


def test_sql_quoting():
    assert _q("O'Brien") == "'O''Brien'"
    assert _q(42) == "42"
    assert _q(None) == "NULL"
    assert _q(True) == "TRUE"


def test_row_to_task():
    row = ["7", "Ship it", "high", "docker,ci", "f", "2026-09-08T10:00:00Z"]
    task = _row_to_task(row)
    assert task["id"] == 7 and task["done"] is False
    assert task["tags"] == ["docker", "ci"]


def test_row_to_task_done():
    assert _row_to_task(["1", "x", "low", "", "t", "2026-09-08T10:00:00Z"])["done"] is True
```

## B.8 `api/requirements.txt`

```
# Runtime needs NOTHING — the app is pure stdlib.
# pytest is installed only in the BUILDER stage (see the Dockerfile answer).
```

## B.9 `db/init/01-schema.sql`

```sql
-- Runs ONCE, the first time the postgres volume is initialised.
CREATE TABLE IF NOT EXISTS tasks (
    id         SERIAL PRIMARY KEY,
    title      TEXT        NOT NULL,
    priority   TEXT        NOT NULL DEFAULT 'medium'
                             CHECK (priority IN ('low','medium','high')),
    tags       TEXT        NOT NULL DEFAULT '',
    done       BOOLEAN     NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS tasks_done_idx       ON tasks (done);
CREATE INDEX IF NOT EXISTS tasks_priority_idx   ON tasks (priority);
CREATE INDEX IF NOT EXISTS tasks_created_at_idx ON tasks (created_at DESC);

INSERT INTO tasks (title, priority, tags) VALUES
    ('Learn FROM, RUN and CMD',            'high',   'docker,basics'),
    ('Learn COPY, ADD and .dockerignore',  'high',   'docker,basics'),
    ('Master ENTRYPOINT vs CMD',           'medium', 'docker'),
    ('Build a multi-stage image',          'medium', 'docker,optimisation'),
    ('Deploy with docker compose',         'low',    'docker,devops');
```

## B.10 `web/site/index.html`

```html
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>TaskNest</title><link rel="stylesheet" href="/style.css"></head>
<body>
<header><h1>🪺 TaskNest</h1>
<p class="sub">nginx → api → postgres + redis, all in containers. One port: 8080.</p></header>

<section class="card">
  <h2>Add a task</h2>
  <form id="f">
    <input id="t" placeholder="What needs doing?" autofocus required>
    <select id="p"><option value="low">low</option><option value="medium" selected>medium</option><option value="high">high</option></select>
    <button>Add</button>
  </form>
</section>

<section class="card"><h2>Statistics</h2><pre id="stats">loading…</pre></section>
<section class="card"><h2>Tasks <button id="r" class="small">↻ refresh</button></h2><ul id="l"></ul></section>
<section class="card"><h2>Platform</h2><pre id="i">loading…</pre>
  <p class="links">
    <a href="/api/health">/api/health</a> · <a href="/api/ready">/api/ready</a> ·
    <a href="/api/info">/api/info</a> · <a href="/api/stats">/api/stats</a> · <a href="/healthz">/healthz</a>
  </p></section>

<script>
const l=document.getElementById('l'), S=document.getElementById('stats'), I=document.getElementById('i');
const j = async u => (await fetch(u)).json();
async function load(){
  try{
    const d = await j('/api/tasks');
    l.innerHTML = d.tasks.length ? d.tasks.map(t=>`
      <li class="${t.done?'done':''}">
        <input type="checkbox" ${t.done?'checked':''} data-id="${t.id}" class="cb">
        <span class="pri ${t.priority}">${t.priority}</span>
        <span class="ti">${t.title.replace(/</g,'&lt;')}</span>
        <button class="del" data-id="${t.id}">✕</button>
      </li>`).join('') : '<li><i>nothing here yet</i></li>';
    l.querySelector('.src')?.remove();
    l.insertAdjacentHTML('afterbegin', `<li class="src">source: ${d.source}</li>`);
    document.querySelectorAll('.cb').forEach(c=>c.onclick=async()=>{
      await fetch(`/api/tasks/${c.dataset.id}/toggle`,{method:'POST'}); load();});
    document.querySelectorAll('.del').forEach(b=>b.onclick=async()=>{
      await fetch(`/api/tasks/${b.dataset.id}`,{method:'DELETE'}); load();});
    S.textContent = JSON.stringify(await j('/api/stats'), null, 2);
    I.textContent = JSON.stringify(await j('/api/info'),   null, 2);
  }catch(e){ l.innerHTML=`<li>⚠️ API unreachable: ${e}</li>`; }
}
document.getElementById('f').onsubmit = async e=>{
  e.preventDefault();
  await fetch('/api/tasks',{method:'POST',headers:{'Content-Type':'application/json'},
    body:JSON.stringify({title:t.value, priority:p.value})});
  t.value=''; load();
};
document.getElementById('r').onclick = load;
load(); setInterval(load, 10000);
</script>
</body></html>
```

## B.11 `web/site/style.css`

```css
:root{color-scheme:light dark;--acc:#2496ed;--bg:rgba(127,127,127,.1)}
*{box-sizing:border-box}
body{font-family:system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;max-width:860px;margin:2rem auto;padding:0 1.25rem;line-height:1.6}
header h1{color:var(--acc);margin-bottom:.2rem}
.sub{opacity:.7;margin-top:0}
.card{border:1px solid rgba(127,127,127,.3);border-radius:12px;padding:1rem 1.25rem;margin:1rem 0}
h2{margin:.2rem 0 .8rem;font-size:1.1rem;border-bottom:1px solid rgba(127,127,127,.25);padding-bottom:.35rem}
input,select,button{padding:.5rem .7rem;border-radius:8px;border:1px solid rgba(127,127,127,.4);background:transparent;color:inherit;font:inherit}
button{background:var(--acc);color:#fff;border:none;cursor:pointer}
button.small{background:var(--bg);color:inherit;font-size:.8rem;padding:.2rem .6rem;float:right}
input#t{width:60%}
ul{list-style:none;padding:0;margin:0}
li{display:flex;align-items:center;gap:.6rem;padding:.45rem 0;border-bottom:1px solid var(--bg)}
li.src{opacity:.55;font-size:.78rem;border:none}
li.done .ti{text-decoration:line-through;opacity:.55}
.ti{flex:1}
.pri{font-size:.7rem;text-transform:uppercase;letter-spacing:.05em;padding:.15rem .5rem;border-radius:999px;background:var(--bg)}
.pri.high{background:#e5484d33;color:#e5484d}.pri.medium{background:#f5a52433;color:#c47f0a}.pri.low{background:#30a46c33;color:#30a46c}
.del{background:transparent;color:#e5484d;padding:.1rem .45rem;font-size:.9rem}
pre{background:var(--bg);padding:.8rem;border-radius:8px;overflow:auto;font-size:.8rem;margin:0}
.links{font-size:.85rem;opacity:.8}a{color:var(--acc)}
```

## B.12 `web/site/404.html`

```html
<!doctype html><html lang="en"><head><meta charset="utf-8"><title>404 · TaskNest</title>
<link rel="stylesheet" href="/style.css"></head>
<body><header><h1>🧭 404</h1><p class="sub">That route doesn't exist in this image.</p></header>
<section class="card"><p><a href="/">← back to TaskNest</a></p></section></body></html>
```

## B.13 `.env.example`

```bash
# Copy to .env and adjust. NEVER commit .env — it is in .gitignore.
POSTGRES_USER=tasknest
POSTGRES_PASSWORD=change-me-in-production
POSTGRES_DB=tasknest
APP_ENV=development
APP_VERSION=1.0.0
LOG_LEVEL=INFO
CACHE_ENABLED=true
CACHE_TTL=15
```

## B.14 `.gitignore`

```gitignore
.env
*.log
__pycache__/
*.pyc
.venv/
venv/
backups/
data/
.DS_Store
.vscode/
.idea/
```

---
---

# ✅ SECTION C — THE ANSWERS

Every file that Requirement 1–10 asks you to write, complete and explained.

## C.1 `api/Dockerfile` — multi-stage, non-root, tested  → **Requirements 1, 2, 4**

```dockerfile
# syntax=docker/dockerfile:1

ARG PYTHON_IMAGE=python:3.13-alpine

# ══════════════════════════ STAGE 1: builder ══════════════════════════
FROM ${PYTHON_IMAGE} AS builder

ARG APP_VERSION=0.0.0-dev
ARG GIT_COMMIT=unknown

ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /build

# Build tooling + test tooling live ONLY here.
RUN apk add --no-cache gcc musl-dev

# Test dependencies are installed into a separate prefix so they can't leak.
RUN pip install --no-cache-dir --prefix=/testdeps pytest==8.3.4 pytest-cov==6.0

# Runtime dependencies (currently none — the app is stdlib-only).
COPY api/requirements.txt ./requirements.txt
RUN pip wheel --no-cache-dir --wheel-dir /wheels -r requirements.txt || true

# Copy the source and RUN THE TESTS. A failure here aborts the build → no image.
COPY api/src ./src
COPY api/tests ./tests
RUN PYTHONPATH=/build /testdeps/bin/pytest tests/ -q --tb=short

# Freeze the version info into a file the app can read at runtime.
RUN printf '{"version":"%s","commit":"%s","python":"%s"}\n' \
      "${APP_VERSION}" "${GIT_COMMIT}" "$(python -V 2>&1 | cut -d' ' -f2)" > /build-info.json


# ══════════════════════════ STAGE 2: debug ══════════════════════════
# Not the default target. Build with:  docker build --target debug ...
FROM builder AS debug
RUN apk add --no-cache curl bind-tools postgresql-client strace vim
CMD ["sh"]


# ══════════════════════════ STAGE 3: runtime ══════════════════════════
FROM ${PYTHON_IMAGE} AS runtime

ARG APP_VERSION=0.0.0-dev
ARG GIT_COMMIT=unknown

ENV APP_VERSION=${APP_VERSION} \
    GIT_COMMIT=${GIT_COMMIT} \
    APP_NAME=TaskNest \
    APP_ENV=production \
    HOST=0.0.0.0 \
    PORT=8000 \
    DATA_DIR=/app/data \
    LOG_LEVEL=INFO \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

LABEL org.opencontainers.image.title="tasknest-api" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.revision="${GIT_COMMIT}" \
      org.opencontainers.image.description="TaskNest task-management API" \
      org.opencontainers.image.vendor="you"

WORKDIR /app

# psql is the ONLY system package the runtime needs (store.py shells out to it).
RUN apk add --no-cache postgresql-client

# Non-root system user, fixed uid so bind mounts can be aligned on the host.
RUN addgroup -S -g 101 app && adduser -S -u 100 -G app -g 101 app \
 && mkdir -p /app/data \
 && chown -R app:app /app

# Runtime wheels only — no gcc, no pytest, no test sources.
COPY --from=builder /wheels /wheels
RUN if [ -n "$(ls -A /wheels 2>/dev/null)" ]; then \
        pip install --no-cache-dir --no-index --find-links=/wheels /wheels/*; \
    fi \
 && rm -rf /wheels /root/.cache

COPY --from=builder --chown=app:app /build/src            ./src
COPY --from=builder --chown=app:app /build/build-info.json ./build-info.json

USER app

EXPOSE 8000
STOPSIGNAL SIGTERM

# Liveness only. Cheap, dependency-free, never causes a restart storm.
HEALTHCHECK --interval=15s --timeout=3s --start-period=20s --retries=3 \
  CMD python -c "import urllib.request,sys;sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/api/health',timeout=2).status==200 else 1)"

# Read-only root filesystem: the ONLY writable path is the /tmp tmpfs and /app/data volume.
VOLUME ["/app/data"]

CMD ["python", "-m", "src.server"]
```

**Why each decision was made:**

| Decision | Reason |
|---|---|
| `ARG PYTHON_IMAGE` at the top | One place to change the base for every stage; overridable with `--build-arg` |
| pytest installed into `--prefix=/testdeps` | It physically cannot end up in the runtime stage |
| Tests run in stage 1 | A failing test **aborts the build** — broken code never becomes an image |
| `debug` stage | `docker build --target debug` gives you a shell with curl/psql/strace — Requirement 9 |
| `apk add postgresql-client` in runtime | `store.py` shells out to `psql`; it's a genuine runtime need |
| Fixed `uid 100 / gid 101` | Lets you align host bind mounts (`chown 100:101`) — Project 5, Task 5.1 |
| `HEALTHCHECK` on `/api/health` not `/api/ready` | Restarting on a DB blip causes a cascade; readiness is reported, not enforced, by Docker |
| `--start-period=20s` | The app waits for dependencies at boot; early failures shouldn't count |
| exec-form `CMD` | Python becomes PID 1 → receives `SIGTERM` → graceful shutdown (Project 4) |
| `build-info.json` | Version/commit visible at runtime without an `ENV` for each |

**Verify Requirements 1 & 2:**
```bash
cd tasknest
docker build -f api/Dockerfile \
  --build-arg APP_VERSION=1.0.0 \
  --build-arg GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo local) \
  -t tasknest-api:1.0.0 .

docker images tasknest-api                 # must be < 80 MB  ✅ (~65 MB)
docker history tasknest-api:1.0.0 --human --format "table {{.Size}}\t{{.CreatedBy}}" | head -12
docker run --rm tasknest-api:1.0.0 whoami  # → app  ✅
docker run --rm tasknest-api:1.0.0 id      # → uid=100(app) gid=101(app)
docker run --rm tasknest-api:1.0.0 python -c "import pytest"   # ModuleNotFoundError ✅
docker run --rm tasknest-api:1.0.0 ls /app                     # src/ build-info.json  (no tests/) ✅
docker build --target debug -f api/Dockerfile -t tasknest-api:debug .
docker run --rm -it tasknest-api:debug sh -c 'pytest tests -q; gcc --version | head -1'
```

---

## C.2 `web/Dockerfile` + `web/nginx.conf` → **Requirement 6**

### `web/Dockerfile`

```dockerfile
# syntax=docker/dockerfile:1
FROM nginx:1.29-alpine

ARG APP_VERSION=1.0.0
LABEL org.opencontainers.image.title="tasknest-web" \
      org.opencontainers.image.version="${APP_VERSION}"

# Remove the default site, install ours
RUN rm -f /etc/nginx/conf.d/default.conf
COPY web/nginx.conf /etc/nginx/conf.d/tasknest.conf
COPY web/site/      /usr/share/nginx/html/

# nginx:alpine ships an unprivileged 'nginx' user (uid 101) — use it.
# Port 8080 (>1024) so a non-root user can bind to it.
RUN chown -R nginx:nginx /usr/share/nginx/html \
 && chown -R nginx:nginx /var/cache/nginx \
 && touch /var/run/nginx.pid && chown nginx:nginx /var/run/nginx.pid

USER nginx

EXPOSE 8080
STOPSIGNAL SIGQUIT          # nginx's graceful shutdown signal

HEALTHCHECK --interval=15s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -q --spider http://127.0.0.1:8080/healthz || exit 1

CMD ["nginx", "-g", "daemon off;"]
```

### `web/nginx.conf`

```nginx
# ── upstream with failover: if you scale api, Docker DNS returns all replicas ──
upstream tasknest_api {
    least_conn;
    server api:8000 max_fails=3 fail_timeout=10s;
    keepalive 16;
}

server {
    listen       8080;
    server_name  _;

    root  /usr/share/nginx/html;
    index index.html;

    # ── compression ──
    gzip on;
    gzip_comp_level 5;
    gzip_min_length 512;
    gzip_vary on;
    gzip_types text/css application/javascript application/json image/svg+xml text/plain;

    # ── security headers ──
    add_header X-Content-Type-Options "nosniff"          always;
    add_header X-Frame-Options        "DENY"             always;
    add_header Referrer-Policy        "no-referrer"      always;
    add_header X-XSS-Protection       "1; mode=block"    always;

    # ── nginx's own liveness (used by HEALTHCHECK) ──
    location = /healthz {
        access_log off;
        add_header Content-Type text/plain;
        return 200 "ok\n";
    }

    # ── hide the nginx version ──
    server_tokens off;

    # ── THE reverse proxy: /api/* -> api service ──
    location /api/ {
        proxy_pass         http://tasknest_api;
        proxy_http_version 1.1;
        proxy_set_header   Connection        "";
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;

        proxy_connect_timeout 3s;
        proxy_send_timeout    10s;
        proxy_read_timeout    15s;

        # if a replica is down, try the next one instead of returning 502
        proxy_next_upstream error timeout http_502 http_503 http_504;
    }

    # also accept the un-prefixed API paths so both work
    location ~ ^/(health|ready|tasks|stats)(/|$) {
        proxy_pass http://tasknest_api;
        proxy_set_header Host $host;
    }

    # ── custom 404 ──
    error_page 404 /404.html;
    location = /404.html { internal; }

    # ── static files with caching ──
    location ~* \.(css|js|svg|png|jpg|webp|ico)$ {
        expires 7d;
        add_header Cache-Control "public, max-age=604800";
        try_files $uri =404;
    }

    location / {
        try_files $uri $uri/ /index.html;
    }
}
```

> 🔑 **Note the `listen 8080`, not `listen 80`.** Binding to port 80 requires `CAP_NET_BIND_SERVICE`, which a non-root user doesn't have. The standard modern solution is: **listen on a high port inside the container, and map it with `-p 8080:8080`.** This satisfies Requirement 7 (non-root nginx) without hacks.

---

## C.3 `docker-compose.yml` — the whole platform → **Requirements 3, 4, 5, 6, 7, 9**

```yaml
name: tasknest

# ── shared fragments ────────────────────────────────────────────────
x-logging: &default-logging
  driver: json-file
  options:
    max-size: "10m"
    max-file: "3"

x-security: &default-security
  no-new-privileges: true

x-restart: &default-restart
  restart: unless-stopped

# ── services ────────────────────────────────────────────────────────
services:

  db:
    image: postgres:17-alpine
    <<: [*default-restart]
    container_name: tasknest-db
    security_opt: *default-security
    logging: *default-logging
    environment:
      POSTGRES_USER: ${POSTGRES_USER:-tasknest}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:?set POSTGRES_PASSWORD in .env}
      POSTGRES_DB: ${POSTGRES_DB:-tasknest}
      POSTGRES_INITDB_ARGS: "--data-checksums"
    volumes:
      - db-data:/var/lib/postgresql/data
      - ./db/init:/docker-entrypoint-initdb.d:ro
    # NOT published to the host in production. Uncomment only for local debugging:
    # ports: ["127.0.0.1:5432:5432"]
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-tasknest} -d ${POSTGRES_DB:-tasknest}"]
      interval: 5s
      timeout: 5s
      retries: 12
      start_period: 15s
    deploy:
      resources:
        limits: { cpus: "1.0", memory: 512M }
        reservations: { memory: 128M }
    networks: [backend]
    read_only: false          # postgres needs to write to /var/run & /tmp
    tmpfs:
      - /tmp:size=64M

  cache:
    image: redis:7-alpine
    <<: [*default-restart]
    container_name: tasknest-cache
    security_opt: *default-security
    logging: *default-logging
    command:
      - redis-server
      - --appendonly
      - "yes"
      - --appendfsync
      - everysec
      - --maxmemory
      - 128mb
      - --maxmemory-policy
      - allkeys-lru
      - --save
      - ""
    volumes:
      - cache-data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5
      start_period: 5s
    deploy:
      resources:
        limits: { cpus: "0.50", memory: 192M }
    networks: [backend]

  api:
    build:
      context: .                      # context = repo root so it can see api/
      dockerfile: api/Dockerfile
      target: runtime
      args:
        APP_VERSION: ${APP_VERSION:-1.0.0}
        GIT_COMMIT: ${GIT_COMMIT:-local}
        PYTHON_IMAGE: python:3.13-alpine
    image: tasknest-api:${APP_VERSION:-1.0.0}
    <<: [*default-restart]
    security_opt: *default-security
    logging: *default-logging
    depends_on:
      db:    { condition: service_healthy }
      cache: { condition: service_healthy }
    environment:
      # ── Requirement 3: everything is an env var, nothing is hard-coded ──
      DATABASE_URL: postgresql://${POSTGRES_USER:-tasknest}:${POSTGRES_PASSWORD:?err}@db:5432/${POSTGRES_DB:-tasknest}
      REDIS_URL: redis://cache:6379/0
      APP_ENV: ${APP_ENV:-development}
      APP_VERSION: ${APP_VERSION:-1.0.0}
      GIT_COMMIT: ${GIT_COMMIT:-local}
      LOG_LEVEL: ${LOG_LEVEL:-INFO}
      CACHE_ENABLED: ${CACHE_ENABLED:-true}
      CACHE_TTL: ${CACHE_TTL:-15}
      PORT: "8000"
      DATA_DIR: /app/data
      # Requirement 7: a secret injected at RUNTIME, never baked into the image
      API_ADMIN_TOKEN: ${API_ADMIN_TOKEN:-dev-only-token}
    volumes:
      - api-data:/app/data
    # exposed only for direct debugging; the browser uses nginx on 8080
    ports:
      - "127.0.0.1:8000:8000"
    read_only: true                 # ✅ Requirement 7 — immutable root filesystem
    tmpfs:
      - /tmp:size=32M
    cap_drop: [ALL]                 # ✅ no Linux capabilities at all
    deploy:
      resources:
        limits: { cpus: "0.75", memory: 256M }
        reservations: { memory: 64M }
    stop_grace_period: 25s          # matches STOPSIGNAL + the app's drain time
    networks: [backend]
    # healthcheck is already in the Dockerfile; re-declared here to be explicit
    healthcheck:
      test: ["CMD-SHELL", "python -c \"import urllib.request,sys;sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/api/health',timeout=2).status==200 else 1)\""]
      interval: 15s
      timeout: 3s
      retries: 3
      start_period: 25s

  web:
    build:
      context: .
      dockerfile: web/Dockerfile
      args:
        APP_VERSION: ${APP_VERSION:-1.0.0}
    image: tasknest-web:${APP_VERSION:-1.0.0}
    <<: [*default-restart]
    security_opt: *default-security
    logging: *default-logging
    depends_on:
      api: { condition: service_healthy }
    ports:
      - "8080:8080"                 # ✅ Requirement 6 — the ONLY public port
    read_only: true
    tmpfs:
      - /var/cache/nginx:size=16M
      - /var/run:size=1M
      - /tmp:size=8M
    cap_drop: [ALL]
    deploy:
      resources:
        limits: { cpus: "0.50", memory: 128M }
    networks: [frontend, backend]

  # ── Requirement 9: hot-reload development, started ONLY with --profile dev ──
  api-dev:
    profiles: ["dev"]
    build:
      context: .
      dockerfile: api/Dockerfile
      target: debug                 # ← the debug stage: has pytest, curl, psql, vim
    image: tasknest-api:debug
    restart: "no"
    depends_on:
      db:    { condition: service_healthy }
      cache: { condition: service_healthy }
    environment:
      DATABASE_URL: postgresql://${POSTGRES_USER:-tasknest}:${POSTGRES_PASSWORD:?err}@db:5432/${POSTGRES_DB:-tasknest}
      REDIS_URL: redis://cache:6379/0
      APP_ENV: development
      LOG_LEVEL: DEBUG
      PORT: "8000"
    volumes:
      - ./api:/app                  # live source
      - /app/data                   # anonymous volume shadows the host's data dir
    ports:
      - "127.0.0.1:8001:8000"
    command: ["python", "-m", "src.server"]
    networks: [backend]

  # ── a one-shot job: runs migrations/checks then exits. Not scaled. ──
  smoke:
    profiles: ["test"]
    image: curlimages/curl:8.10.1
    depends_on:
      web: { condition: service_healthy }
    entrypoint: ["/bin/sh", "-c"]
    command:
      - |
        set -e
        echo "--- smoke test ---"
        curl -fsS http://web:8080/healthz
        curl -fsS http://api:8000/api/health
        curl -fsS http://api:8000/api/ready
        curl -fsS http://web:8080/api/tasks
        echo "✅ all good"
    networks: [frontend, backend]
    restart: "no"

volumes:
  db-data:
    name: tasknest-db-data
  cache-data:
    name: tasknest-cache-data
  api-data:
    name: tasknest-api-data

networks:
  frontend:
    name: tasknest-frontend
  backend:
    name: tasknest-backend
    internal: false     # set to `true` to cut off ALL internet access from db/cache/api
```

**Design notes:**

| Choice | Why |
|---|---|
| `build.context: .` (repo root) | So the api Dockerfile can `COPY api/src`. A common alternative is `context: ./api` — then paths inside the Dockerfile drop the `api/` prefix. Pick one and be consistent. |
| `target: runtime` | Explicitly builds the last stage even if you add more later. |
| `${POSTGRES_PASSWORD:?err}` | **Compose fails fast** if the variable is unset — no silent empty passwords. |
| `read_only: true` + `tmpfs` | Requirement 7. The app can only write to `/app/data` (a volume) and `/tmp`. |
| `cap_drop: [ALL]` | The app needs no capabilities. Add back only what breaks (`NET_BIND_SERVICE` if you must use port 80). |
| `ports: "127.0.0.1:8000:8000"` | Reachable from your machine for debugging, **not** from the network. |
| `db` publishes **no** port | Nothing outside Docker can reach PostgreSQL. Requirement 6/7. |
| `web` on both networks | It must serve browsers (published port) and proxy to `api` (backend). |
| `smoke` with `profiles: ["test"]` | Runs only via `docker compose --profile test run --rm smoke`. |
| `stop_grace_period: 25s` | Must exceed the app's drain time; interacts with `STOPSIGNAL SIGTERM`. |
| Named volumes with explicit `name:` | Predictable names for `docker volume inspect tasknest-db-data` and backups. |

---

## C.4 `Makefile` → **Requirement 8**

```makefile
SHELL := /bin/bash
.DEFAULT_GOAL := help
COMPOSE := docker compose
APP_VERSION ?= 1.0.0
GIT_COMMIT  := $(shell git rev-parse --short HEAD 2>/dev/null || echo local)
BACKUP_DIR  := backups
TS          := $(shell date -u +%Y%m%d-%H%M%S)

.PHONY: help up down restart build rebuild logs ps test smoke dev backup restore nuke clean shell-api shell-db shell-cache verify scan push

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

up: ## Build and start the whole platform, wait until healthy
	$(COMPOSE) build --build-arg APP_VERSION=$(APP_VERSION) --build-arg GIT_COMMIT=$(GIT_COMMIT)
	$(COMPOSE) up -d --wait --timeout 180
	@$(MAKE) --no-print-directory ps

down: ## Stop and remove containers + networks (DATA IS KEPT)
	$(COMPOSE) down --remove-orphans

restart: ## Restart all services
	$(COMPOSE) restart

build: ## Build images only
	$(COMPOSE) build

rebuild: ## Rebuild from scratch (no cache)
	$(COMPOSE) build --no-cache

logs: ## Follow all logs
	$(COMPOSE) logs -f --tail=100

ps: ## Show service status
	$(COMPOSE) ps

test: ## Run the unit tests inside the builder stage
	docker build -f api/Dockerfile --target builder -t tasknest-api:test .
	@echo "✅ builder stage completed → tests passed"

smoke: ## End-to-end smoke test of the running platform
	@bash scripts/smoke-test.sh

dev: ## Start with the hot-reload dev profile
	$(COMPOSE) --profile dev up -d
	@echo "dev API on http://localhost:8001  (edit api/src and 'make restart')"

backup: ## Dump PostgreSQL to backups/<timestamp>.sql
	@mkdir -p $(BACKUP_DIR)
	@bash scripts/backup.sh $(BACKUP_DIR)/tasknest-$(TS).sql
	@ls -lh $(BACKUP_DIR) | tail -3

restore: ## Restore PostgreSQL from the newest backup: make restore FILE=backups/x.sql
	@bash scripts/restore.sh $(FILE)

nuke: ## ☠️ Destroy EVERYTHING including all data volumes
	$(COMPOSE) down -v --remove-orphans
	docker volume ls --filter name=tasknest

clean: ## Remove dangling images/build cache
	docker system prune -f
	docker builder prune -f

scan: ## Scan images for CVEs and secrets
	-docker scout cves tasknest-api:$(APP_VERSION)
	-docker scout secrets tasknest-api:$(APP_VERSION)
	-docker history tasknest-api:$(APP_VERSION) --no-trunc | grep -iE 'password|secret|token' && \
	  echo "❌ SECRET FOUND IN HISTORY" || echo "✅ no secrets in image history"

verify: ## Run the full Definition-of-Done acceptance test
	@bash scripts/smoke-test.sh --full

shell-api: ## Shell into the running api container
	$(COMPOSE) exec api sh

shell-db: ## psql into the database
	$(COMPOSE) exec db psql -U $${POSTGRES_USER:-tasknest} -d $${POSTGRES_DB:-tasknest}

shell-cache: ## redis-cli into the cache
	$(COMPOSE) exec cache redis-cli

push: ## Tag and push images to a registry (set REGISTRY_USER)
	@test -n "$(REGISTRY_USER)" || { echo "usage: make push REGISTRY_USER=yourname"; exit 1; }
	docker tag  tasknest-api:$(APP_VERSION) $(REGISTRY_USER)/tasknest-api:$(APP_VERSION)
	docker tag  tasknest-web:$(APP_VERSION) $(REGISTRY_USER)/tasknest-web:$(APP_VERSION)
	docker push $(REGISTRY_USER)/tasknest-api:$(APP_VERSION)
	docker push $(REGISTRY_USER)/tasknest-web:$(APP_VERSION)
```

## C.5 `scripts/backup.sh` → **Requirement 8**

```bash
#!/usr/bin/env bash
# Dump the PostgreSQL database to a timestamped SQL file on the HOST.
set -euo pipefail

OUT="${1:-backups/tasknest-$(date -u +%Y%m%d-%H%M%S).sql}"
CONTAINER="${POSTGRES_CONTAINER:-tasknest-db}"
DB_USER="${POSTGRES_USER:-tasknest}"
DB_NAME="${POSTGRES_DB:-tasknest}"

mkdir -p "$(dirname "$OUT")"

echo "▶ backing up ${DB_NAME} from ${CONTAINER} → ${OUT}"

# pg_dump runs INSIDE the container (guaranteed version match), streams to the host.
docker exec "$CONTAINER" pg_dump \
  --username "$DB_USER" \
  --dbname   "$DB_NAME" \
  --format=plain \
  --no-owner --no-privileges \
  > "$OUT"

# also back up Redis (best effort)
docker exec tasknest-cache redis-cli BGSAVE >/dev/null 2>&1 || true
docker cp tasknest-cache:/data/dump.rdb "${OUT%.sql}-redis.rdb" 2>/dev/null || true

SIZE=$(wc -c < "$OUT")
TABLES=$(grep -c '^CREATE TABLE' "$OUT" || true)
ROWS=$(grep -c '^INSERT\|^COPY' "$OUT" || true)

echo "✅ backup complete: ${OUT} (${SIZE} bytes, ${TABLES} CREATE TABLE, ${ROWS} data statements)"
[[ "$SIZE" -gt 100 ]] || { echo "❌ backup looks empty"; exit 1; }
```

## C.6 `scripts/restore.sh` → **Requirement 8**

```bash
#!/usr/bin/env bash
# Restore PostgreSQL from a dump produced by backup.sh.
set -euo pipefail

FILE="${1:-}"
if [[ -z "$FILE" ]]; then
  FILE=$(ls -1t backups/*.sql 2>/dev/null | head -1 || true)
fi
[[ -n "$FILE" && -f "$FILE" ]] || { echo "❌ no backup file. usage: make restore FILE=backups/x.sql"; exit 1; }

CONTAINER="${POSTGRES_CONTAINER:-tasknest-db}"
DB_USER="${POSTGRES_USER:-tasknest}"
DB_NAME="${POSTGRES_DB:-tasknest}"

echo "▶ restoring ${FILE} into ${DB_NAME}"

# 1. make sure the stack is up and the DB is healthy
docker compose up -d --wait db

# 2. drop and recreate the schema (destructive — that's the point of a restore)
docker exec "$CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 \
  -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"

# 3. pipe the dump in
docker exec -i "$CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 < "$FILE"

# 4. flush the API cache so it doesn't serve stale rows
docker exec tasknest-cache redis-cli FLUSHALL >/dev/null || true
docker compose restart api

COUNT=$(docker exec "$CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT count(*) FROM tasks")
echo "✅ restore complete — ${COUNT} tasks in the database"
```

## C.7 `scripts/smoke-test.sh` → **Requirements 4, 8 + Definition of Done**

```bash
#!/usr/bin/env bash
# End-to-end verification of the whole platform. Exits non-zero on ANY failure.
set -uo pipefail

BASE="${BASE_URL:-http://localhost:8080}"
PASS=0; FAIL=0
FULL=0; [[ "${1:-}" == "--full" ]] && FULL=1

ok()   { printf "  \033[32m✔\033[0m %s\n" "$1"; PASS=$((PASS+1)); }
bad()  { printf "  \033[31m✘\033[0m %s\n" "$1"; FAIL=$((FAIL+1)); }
hdr()  { printf "\n\033[1m%s\033[0m\n" "$1"; }

check() { # check "description" expected actual
  if [[ "$3" == *"$2"* ]]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi
}

hdr "1. Stack is up and healthy"
SERVICES=$(docker compose ps --format '{{.Name}} {{.Status}}' 2>/dev/null)
echo "$SERVICES" | sed 's/^/    /'
for svc in tasknest-db tasknest-cache tasknest-web; do
  if echo "$SERVICES" | grep -q "$svc.*healthy"; then ok "$svc is healthy"; else bad "$svc not healthy"; fi
done

hdr "2. nginx serves the UI on the single public port"
check "GET / returns HTML"          "TaskNest"  "$(curl -s "$BASE/")"
check "GET /healthz returns ok"     "ok"        "$(curl -s "$BASE/healthz")"
check "gzip is enabled"             "gzip"      "$(curl -sI -H 'Accept-Encoding: gzip' "$BASE/style.css" | tr -d '\r')"
check "404 page works"              "404"       "$(curl -s -o /dev/null -w '%{http_code}' "$BASE/does-not-exist")"
check "security header present"     "nosniff"   "$(curl -sI "$BASE/" | tr -d '\r')"

hdr "3. Reverse proxy /api/* → api service"
check "GET /api/health"   '"status": "ok"' "$(curl -s "$BASE/api/health")"
check "GET /api/ready"    '"ready": true'  "$(curl -s "$BASE/api/ready")"
check "GET /api/info"     'TaskNest'       "$(curl -s "$BASE/api/info")"

hdr "4. CRUD against PostgreSQL"
TITLE="smoke-$(date +%s)"
CREATED=$(curl -s -X POST "$BASE/api/tasks" -H 'Content-Type: application/json' \
            -d "{\"title\":\"$TITLE\",\"priority\":\"high\",\"tags\":[\"smoke\"]}")
check "POST creates a task" "$TITLE" "$CREATED"
ID=$(echo "$CREATED" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("id",""))' 2>/dev/null)

check "GET /api/tasks lists it"   "$TITLE" "$(curl -s "$BASE/api/tasks")"
check "GET /api/tasks/$ID"        "$TITLE" "$(curl -s "$BASE/api/tasks/$ID")"
check "POST toggle marks done"    '"done": true' "$(curl -s -X POST "$BASE/api/tasks/$ID/toggle")"
check "GET /api/stats has counts" '"total"'      "$(curl -s "$BASE/api/stats")"
check "validation rejects empty"  'required'     "$(curl -s -X POST "$BASE/api/tasks" -H 'Content-Type: application/json' -d '{}')"
check "validation rejects bad priority" 'priority' \
      "$(curl -s -X POST "$BASE/api/tasks" -H 'Content-Type: application/json' -d '{"title":"x","priority":"urgent"}')"
check "DELETE removes it"         '"deleted"'    "$(curl -s -X DELETE "$BASE/api/tasks/$ID")"
check "GET after delete → 404"    'not found'    "$(curl -s "$BASE/api/tasks/$ID")"

hdr "5. Cache behaviour"
FIRST=$(curl -s "$BASE/api/tasks"  | grep -o '"source": "[a-z]*"' | head -1)
SECOND=$(curl -s "$BASE/api/tasks" | grep -o '"source": "[a-z]*"' | head -1)
echo "    first=$FIRST  second=$SECOND"
check "second read comes from cache" "cache" "$SECOND"

hdr "6. Security requirements"
check "api runs as non-root"  "app"  "$(docker compose exec -T api whoami 2>/dev/null | tr -d '\r')"
check "api root fs read-only" ""     "$(docker compose exec -T api sh -c 'touch /nope 2>&1 || true' | grep -v 'Read-only' || true)"
LEAK=$(docker history tasknest-api:1.0.0 --no-trunc 2>/dev/null | grep -icE 'password=|secret=|token=' || true)
if [[ "$LEAK" == "0" ]]; then ok "no secrets in image history"; else bad "$LEAK secret-looking lines in history"; fi
PUBLIC=$(docker compose ps --format '{{.Name}} {{.Ports}}' | grep -c 'tasknest-db.*0.0.0.0' || true)
if [[ "$PUBLIC" == "0" ]]; then ok "database port is NOT published"; else bad "database port is published to the host"; fi

if [[ $FULL -eq 1 ]]; then
  hdr "7. Persistence survives container deletion"
  MARKER="persist-$(date +%s)"
  curl -s -X POST "$BASE/api/tasks" -H 'Content-Type: application/json' -d "{\"title\":\"$MARKER\"}" >/dev/null
  docker compose rm -sf api >/dev/null 2>&1
  docker compose up -d --wait api >/dev/null 2>&1
  sleep 3
  check "task survived an api container replacement" "$MARKER" "$(curl -s "$BASE/api/tasks")"
  docker compose restart db >/dev/null 2>&1
  docker compose up -d --wait >/dev/null 2>&1
  sleep 3
  check "task survived a database restart" "$MARKER" "$(curl -s "$BASE/api/tasks")"
fi

printf "\n\033[1m%s\033[0m  passed=%d failed=%d\n" \
  "$( [[ $FAIL -eq 0 ]] && echo '✅ SMOKE TEST PASSED' || echo '❌ SMOKE TEST FAILED' )" "$PASS" "$FAIL"
exit $(( FAIL > 0 ? 1 : 0 ))
```

```bash
chmod +x scripts/*.sh
```

---

## C.8 Requirement-by-requirement: how it is satisfied, and how to prove it

### ✅ Requirement 1 — multi-stage, < 80 MB
```bash
docker compose build api
docker images tasknest-api --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"
docker history tasknest-api:1.0.0 --human --format "table {{.Size}}\t{{.CreatedBy}}" | head -15
docker run --rm tasknest-api:1.0.0 python -c "import pytest"   # must FAIL
docker run --rm tasknest-api:1.0.0 ls /app                     # no tests/
```
**Proof:** ~65 MB, no pytest, no gcc, no test sources. Tests ran in stage 1 (break one on purpose and watch the build fail).

### ✅ Requirement 2 — non-root
```bash
docker compose exec api whoami           # app
docker compose exec api id               # uid=100(app) gid=101(app)
docker compose exec api touch /x         # Permission denied (read-only + non-root)
docker compose exec api touch /app/data/x && echo "can write to the volume ✅"
docker inspect tasknest-api:1.0.0 --format 'Config.User={{.Config.User}}'
```

### ✅ Requirement 3 — configuration by environment only
```bash
grep -rn "localhost\|127.0.0.1\|hardcoded" api/src/ | grep -v "127.0.0.1:8000/api/health"  # none
# one image, three environments:
APP_ENV=development docker compose up -d api
curl -s localhost:8080/api/info | grep environment
APP_ENV=production APP_VERSION=2.0.0 docker compose up -d --force-recreate api
curl -s localhost:8080/api/info | grep -E 'environment|version'
```

### ✅ Requirement 4 — liveness vs readiness
```bash
curl -s localhost:8080/api/health      # 200, no dependency calls
curl -s localhost:8080/api/ready       # 200 with {"database":true,"cache":true}
docker compose stop cache
sleep 5
curl -s -o /dev/null -w '%{http_code}\n' localhost:8080/api/health   # still 200 ✅
curl -s -o /dev/null -w '%{http_code}\n' localhost:8080/api/ready    # 503 ✅
curl -s localhost:8080/api/tasks       # STILL WORKS — caching is best-effort ✅
docker compose start cache
```

### ✅ Requirement 5 — persistence
```bash
make backup
curl -s -X POST localhost:8080/api/tasks -H 'Content-Type: application/json' -d '{"title":"survivor"}'
docker compose down                    # containers gone
docker compose up -d --wait
curl -s localhost:8080/api/tasks | grep survivor      # ✅ still there
docker compose down -v && docker compose up -d --wait
curl -s localhost:8080/api/tasks | grep survivor      # ❌ gone — as designed
make restore FILE=backups/<your-file>.sql             # bring it back
```

### ✅ Requirement 6 — single entry point
```bash
curl -s localhost:8080/ | head -3                     # nginx serves the UI
curl -s localhost:8080/api/health                     # nginx proxies to api
docker compose ps --format '{{.Name}}\t{{.Ports}}'    # only web publishes 0.0.0.0
docker compose exec web wget -qO- http://api:8000/api/health    # ✅ internal DNS
nmap -p 5432,6379,8000 localhost                      # closed/filtered from outside
```

### ✅ Requirement 7 — hardening
```bash
docker inspect tasknest-api-1 --format 'ReadOnlyRootfs={{.HostConfig.ReadonlyRootfs}} Caps={{.HostConfig.CapDrop}} NoNewPrivs={{.HostConfig.SecurityOpt}} Mem={{.HostConfig.Memory}}'
docker compose exec api sh -c 'touch /x'              # Read-only file system
docker compose exec api sh -c 'cat /proc/1/status | grep CapEff'   # 0000000000000000
docker history tasknest-api:1.0.0 --no-trunc | grep -iE 'password|secret|token'   # empty
docker compose exec api env | grep API_ADMIN_TOKEN    # present at RUNTIME
docker inspect tasknest-api:1.0.0 --format '{{json .Config.Env}}' | grep -i token # only the harmless default
```

### ✅ Requirement 8 — tooling
```bash
make help && make up && make smoke && make backup && make restore && make nuke
```

### ✅ Requirement 9 — developer experience
```bash
make dev                                   # starts api-dev with bind-mounted source
docker compose --profile dev logs -f api-dev
docker build -f api/Dockerfile --target debug -t tasknest-api:debug .
docker run --rm -it tasknest-api:debug sh  # pytest, curl, psql, strace, vim available
```

**The 5 debugging one-liners (put them in `README.md`):**
```bash
docker compose logs -f --tail=200 api                                  # why did it fail?
docker compose exec api sh                                             # poke inside a RUNNING container
docker run --rm -it --entrypoint sh tasknest-api:1.0.0                 # poke inside a BROKEN image
docker build --progress=plain --no-cache -f api/Dockerfile -t x .      # see every build line
docker compose run --rm --entrypoint psql api -h db -U tasknest -d tasknest -c '\dt'
```

### ✅ Requirement 10 — ship it

**`.github/workflows/docker.yml`**
```yaml
name: build-test-push

on:
  push: { branches: [main], tags: ["v*"] }
  pull_request: { branches: [main] }

env:
  REGISTRY: ghcr.io
  IMAGE: ${{ github.repository }}/tasknest-api

jobs:
  build:
    runs-on: ubuntu-latest
    permissions: { contents: read, packages: write }
    steps:
      - uses: actions/checkout@v4

      - uses: docker/setup-buildx-action@v3

      - name: Run unit tests (builder stage only)
        uses: docker/build-push-action@v6
        with:
          context: .
          file: api/Dockerfile
          target: builder            # ← stops after pytest; nothing is pushed
          load: true
          tags: tasknest-api:test
          cache-from: type=gha
          cache-to: type=gha,mode=max

      - uses: docker/login-action@v3
        if: github.event_name != 'pull_request'
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - uses: docker/metadata-action@v5
        id: meta
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE }}
          tags: |
            type=ref,event=branch
            type=semver,pattern={{version}}
            type=sha
            type=raw,value=latest,enable={{is_default_branch}}

      - name: Build and push
        if: github.event_name != 'pull_request'
        uses: docker/build-push-action@v6
        with:
          context: .
          file: api/Dockerfile
          target: runtime
          platforms: linux/amd64,linux/arm64
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          build-args: |
            APP_VERSION=${{ steps.meta.outputs.version }}
            GIT_COMMIT=${{ github.sha }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

      - name: Scan for vulnerabilities
        if: github.event_name != 'pull_request'
        uses: aquasecurity/trivy-action@0.28.0
        with:
          image-ref: ${{ env.REGISTRY }}/${{ env.IMAGE }}:sha-${{ github.sha }}
          format: table
          exit-code: "1"
          severity: CRITICAL,HIGH
```

**`README.md` runbook (Requirement 10)**
```markdown
## Deploy
1. `cp .env.example .env` and set a strong `POSTGRES_PASSWORD`.
2. `make up` — builds and starts everything, waits for health.
3. `make smoke` — must print ✅ SMOKE TEST PASSED.
4. Only port **8080** is public. Put a TLS terminator (Caddy/Traefik/cloud LB) in front.

## Roll back
Images are versioned by `APP_VERSION`.
`APP_VERSION=1.0.0 make up` then `APP_VERSION=0.9.0 make up` — one command, instant rollback.
The database schema is forward-compatible; if a migration must be reverted, restore:
`make backup` → deploy → on failure → `make restore FILE=backups/<pre-deploy>.sql`.

## Top 5 incidents
| Symptom | First command | Usual cause |
|---|---|---|
| web 502 Bad Gateway | `docker compose ps`, `docker compose logs api` | api unhealthy or still starting |
| api `503 database unavailable` | `docker compose exec db pg_isready -U tasknest` | postgres restarting / wrong credentials / volume full |
| everything slow | `docker compose stats`, `docker compose exec cache redis-cli INFO memory` | memory limit hit, or Redis evicting |
| container restart loop | `docker inspect <c> --format '{{.State.ExitCode}} {{.State.OOMKilled}}'` | 137 = OOM → raise the memory limit |
| data missing after deploy | `docker volume ls --filter name=tasknest` | someone ran `down -v` → `make restore` |
```

---

## C.9 Full run — the complete command sequence

```bash
# ── 0. setup ────────────────────────────────────────────────────────
git clone <your-repo> tasknest && cd tasknest
cp .env.example .env
sed -i 's/change-me-in-production/Str0ng-Passw0rd!/' .env
chmod +x scripts/*.sh

# ── 1. build ────────────────────────────────────────────────────────
make build APP_VERSION=1.0.0
docker images | grep tasknest

# ── 2. unit tests (inside the builder stage) ────────────────────────
make test

# ── 3. start everything and wait for health ─────────────────────────
make up
docker compose ps                       # 4 services, all (healthy)

# ── 4. use it ───────────────────────────────────────────────────────
open http://localhost:8080
curl -s localhost:8080/api/info   | python3 -m json.tool
curl -s localhost:8080/api/ready  | python3 -m json.tool
curl -s localhost:8080/api/tasks  | python3 -m json.tool
curl -s -X POST localhost:8080/api/tasks -H 'Content-Type: application/json' \
     -d '{"title":"Ship the capstone","priority":"high","tags":["docker","capstone"]}'
curl -s -X POST localhost:8080/api/tasks/1/toggle
curl -s localhost:8080/api/stats  | python3 -m json.tool

# ── 5. verify everything ────────────────────────────────────────────
make smoke                              # 20+ assertions
make verify                             # includes the persistence test
make scan                               # CVEs + secret leak check

# ── 6. inspect the internals ────────────────────────────────────────
docker compose exec api whoami && docker compose exec api id
docker compose exec api ls -la /app
docker compose exec db  psql -U tasknest -d tasknest -c 'SELECT id,title,done FROM tasks;'
docker compose exec cache redis-cli KEYS '*'
docker network inspect tasknest-backend --format '{{range .Containers}}{{.Name}} {{end}}'
docker volume inspect tasknest-db-data --format '{{.Mountpoint}}'

# ── 7. backup / destroy / restore ───────────────────────────────────
make backup
make nuke                               # ☠️ everything gone
docker volume ls --filter name=tasknest # empty
make up
curl -s localhost:8080/api/tasks | grep -c '"id"'      # back to the seed data only
make restore                            # restores the newest backup
curl -s localhost:8080/api/tasks | python3 -m json.tool

# ── 8. ship ─────────────────────────────────────────────────────────
docker login
make push REGISTRY_USER=yourname APP_VERSION=1.0.0

# ── 9. clean up ─────────────────────────────────────────────────────
make down                               # keeps data
make nuke                               # deletes data
docker system prune -f
```

---

## C.10 Extension ideas (once the capstone passes)

| # | Extension | What it teaches |
|---|---|---|
| 1 | Add a **second API replica**: `docker compose up -d --scale api=2` and remove the fixed host port | Load balancing, statelessness |
| 2 | Add **Prometheus + Grafana** under a `monitoring` profile; expose `/metrics` from the API | Observability, Compose profiles |
| 3 | Replace the file-based healthcheck with a **static Go binary** and move the API to `FROM scratch` | Minimal images |
| 4 | Add **Traefik** with automatic Let's Encrypt TLS | Real ingress, HTTPS |
| 5 | Write a **`Dockerfile.windows`** and build with `--platform` for both | Multi-arch |
| 6 | Add a **database migration** one-shot service (`restart: "no"`, `depends_on: db healthy`) that `api` waits for | Init containers, ordering |
| 7 | Enable **rootless mode** / `userns-remap` and re-run everything | Real container security |
| 8 | Convert the Compose file to **Kubernetes** manifests with `kompose`, then hand-fix them | The natural next step |
| 9 | Add **`docker compose watch`** for automatic sync+restart on file changes | Modern dev loops |
| 10 | Publish a **signed** image (`docker buildx build --sbom --provenance`) | Supply-chain security |

---

## C.11 What you can now honestly say on a résumé / in an interview

> "I containerised a multi-service application end to end: multi-stage Dockerfiles that cut the image from ~900 MB to ~65 MB, non-root runtime users with read-only root filesystems and dropped capabilities, liveness and readiness healthchecks, Docker Compose with dependency-ordered startup, named volumes with automated backup and restore, an nginx reverse proxy as a single public entry point with isolated internal networks, secret handling via runtime injection and BuildKit secret mounts, and a GitHub Actions pipeline that tests, scans and publishes multi-architecture images."

Every clause in that sentence is something you **did** in this capstone — and you can demonstrate it live.

**Interview questions you can now answer:**
1. `ENTRYPOINT` vs `CMD`? → Project 4's six experiments.
2. Why multi-stage? → Requirement 1, with before/after sizes.
3. `EXPOSE` vs `-p`? → Project 2's experiments A & B.
4. `ARG` vs `ENV`? → Project 3, Task 3.5.
5. How do you make an image smaller? → Layers, alpine, multi-stage, `--no-cache`, one `RUN`, `.dockerignore`.
6. Why did my container exit immediately? → The PID-1/foreground process explanation.
7. How do you handle secrets? → Project 6 Task 6.5's hierarchy table.
8. Data persistence? → Project 5's big experiment, and `make backup`/`make restore`.
9. Liveness vs readiness? → Requirement 4, proved by stopping Redis.
10. How do containers talk to each other? → Project 7's DNS-by-service-name.

---

## 🎓 You're done.

You went from *"what is a Dockerfile?"* to a **hardened, multi-service, CI-ready platform**.

**Where to go next:** Kubernetes (same concepts, more nodes) → Terraform → observability (Prometheus/Grafana/OpenTelemetry) → service mesh.

Go back and re-read `03-CHEATSHEET.md` — you'll find you now understand every single line of it.


---
---

---
---

# 📚 SECTION D — Projects 8 → 13 have moved to their own files

Per your request, each of these projects is now a **separate file** in this folder (same style as Projects 1–7). Every one contains **CASE 1: a simple Dockerfile** and **CASE 2: a multi-stage Dockerfile**.

| Project | File | Stack | Case 1 → Case 2 |
|---|---|---|---|
| **8** | [`11-PROJECT-8-react-frontend.md`](11-PROJECT-8-react-frontend.md) | ⚛️ React (Vite) | node dev server **230 MB** → nginx + static build **52 MB** |
| **9** | [`12-PROJECT-9-java-backend.md`](12-PROJECT-9-java-backend.md) | ☕ Java / Spring Boot | prebuilt jar + JRE → JDK build stage + **layered jar** (60 MB rebuilds → 50 KB) |
| **10** | [`13-PROJECT-10-react-java-fullstack.md`](13-PROJECT-10-react-java-fullstack.md) | ⚛️ + ☕ React & Java | two ports + CORS → one origin behind an nginx proxy, dev/prod compose overrides |
| **11** | [`14-PROJECT-11-react-python-fullstack.md`](14-PROJECT-11-react-python-fullstack.md) | ⚛️ + 🐍 React & Python | uvicorn `--reload` as root → wheels + pytest stage + gunicorn non-root |
| **12** | [`15-PROJECT-12-react-go-fullstack.md`](15-PROJECT-12-react-go-fullstack.md) | ⚛️ + 🐹 React & Go | full Go SDK **380 MB** → static binary **18 MB** → `FROM scratch` **9 MB** |
| **13** | [`16-PROJECT-13-databases.md`](16-PROJECT-13-databases.md) | 🗄️ **6 separate DB mini-projects** | MySQL · MongoDB · Redis · DynamoDB Local · Cassandra · Neo4j — init scripts, real healthchecks, tuned configs, volumes, backup/restore, GUI tool, gotchas table |

> Sections **A** (the task), **B** (the starting code) and **C** (the answers) of this capstone remain below/above as before — they are the end-to-end project itself.


---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish%20Kumar%20Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn → <https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260>
🐙 GitHub → <https://github.com/3558Bhk>

*Built for engineers who learn by breaking things on purpose.*

</div>
