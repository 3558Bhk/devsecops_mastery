# PROJECT 11 · ⚛️ React + 🐍 Python — Full Stack

> **Part of the Docker Learning Path.** Previous: [`13-PROJECT-10-react-java-fullstack.md`](13-PROJECT-10-react-java-fullstack.md) — Project 10 — React + Java.
>
> 🎯 **Instructions & techniques:** multi-stage · `pip wheel` + `--no-index` · pytest gate stage · gunicorn/uvicorn · non-root Python
>
> 📚 **What you learn:** Python-specific traps: `__pycache__`, `PYTHONUNBUFFERED`, wheels vs pip install, bind-mount uid mismatch
>
> 🔁 **Every project here is written TWICE:**
> - **🔵 CASE 1 — a SIMPLE Dockerfile.** Easy to read, easy to get working, usually too big for production.
> - **🟢 CASE 2 — a MULTI-STAGE Dockerfile.** The production version: smaller, faster to rebuild, more secure, tests can fail the build.
>
> **Build Case 1 first**, run it, understand it — then build Case 2 and **measure the difference**. That comparison *is* the lesson.

---

# D.4 — PROJECT 11 · ⚛️ React + 🐍 Python (Full Stack)

**🎯 What you learn:** the same full-stack wiring with a Python backend, plus the Python-specific traps: `uvicorn --reload` vs `gunicorn`, `__pycache__` pollution, `PYTHONUNBUFFERED`, wheels vs `pip install`, and bind-mount permission mismatches.

## 11.0 Structure

```
11-react-python-fullstack/
├── docker-compose.yml
├── docker-compose.dev.yml
├── .env.example
├── Makefile
├── frontend/                 ← Project 8 (Case 2)
└── backend/
    ├── Dockerfile            ← CASE 1 (simple)
    ├── Dockerfile.multistage ← CASE 2
    ├── requirements.txt
    ├── requirements-dev.txt
    ├── .dockerignore
    ├── app/
    │   ├── __init__.py
    │   ├── main.py
    │   ├── models.py
    │   ├── store.py
    │   └── config.py
    └── tests/
        └── test_store.py
```

### `backend/requirements.txt`

```
fastapi==0.115.6
uvicorn[standard]==0.34.0
pydantic==2.10.4
```

### `backend/requirements-dev.txt`

```
-r requirements.txt
pytest==8.3.4
httpx==0.28.1
ruff==0.8.4
```

### `backend/app/config.py`

```python
import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    app_name: str = os.environ.get("APP_NAME", "tasknest-python")
    version: str = os.environ.get("APP_VERSION", "0.0.0-dev")
    environment: str = os.environ.get("APP_ENV", "development")
    host: str = os.environ.get("HOST", "0.0.0.0")
    port: int = int(os.environ.get("PORT", "8000"))
    log_level: str = os.environ.get("LOG_LEVEL", "INFO").upper()
    data_dir: str = os.environ.get("DATA_DIR", "/app/data")
    cors_origins: tuple[str, ...] = tuple(
        o.strip() for o in os.environ.get("CORS_ORIGINS", "").split(",") if o.strip()
    )


settings = Settings()
```

### `backend/app/models.py`

```python
from datetime import datetime, timezone
from typing import Literal

from pydantic import BaseModel, Field

Priority = Literal["low", "medium", "high"]


class TaskIn(BaseModel):
    title: str = Field(min_length=1, max_length=300)
    priority: Priority = "medium"
    tags: list[str] = Field(default_factory=list, max_length=20)


class TaskOut(TaskIn):
    id: int
    done: bool = False
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class TaskPatch(BaseModel):
    title: str | None = Field(default=None, max_length=300)
    priority: Priority | None = None
    done: bool | None = None
```

### `backend/app/store.py`

```python
"""In-memory + JSON-file store so the project has no database dependency.
Swap for SQLAlchemy/asyncpg in the extension task."""
import json
import os
import threading
from datetime import datetime, timezone

from .config import settings
from .models import TaskOut

_lock = threading.Lock()
_tasks: dict[int, TaskOut] = {}
_seq = 0
_FILE = os.path.join(settings.data_dir, "tasks.json")


def _persist() -> None:
    try:
        os.makedirs(settings.data_dir, exist_ok=True)
        tmp = _FILE + ".tmp"
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump([t.model_dump(mode="json") for t in _tasks.values()], fh, indent=2)
        os.replace(tmp, _FILE)
    except OSError:
        pass  # best-effort: a read-only volume must not break the API


def _load() -> None:
    global _seq
    if not os.path.exists(_FILE):
        return
    try:
        with open(_FILE, encoding="utf-8") as fh:
            for row in json.load(fh):
                task = TaskOut(**row)
                _tasks[task.id] = task
                _seq = max(_seq, task.id)
    except (OSError, json.JSONDecodeError, ValueError):
        pass


def seed() -> None:
    for title, priority, tags in [
        ("Learn FROM, RUN and CMD", "high", ["docker", "basics"]),
        ("Master COPY and .dockerignore", "high", ["docker"]),
        ("Wire React to a Python API", "medium", ["fullstack"]),
    ]:
        create(title, priority, tags)


def create(title: str, priority: str = "medium", tags: list[str] | None = None) -> TaskOut:
    global _seq
    with _lock:
        _seq += 1
        task = TaskOut(id=_seq, title=title, priority=priority, tags=tags or [],
                       done=False, created_at=datetime.now(timezone.utc))
        _tasks[task.id] = task
        _persist()
        return task


def list_tasks(status: str | None = None, priority: str | None = None, limit: int = 100) -> list[TaskOut]:
    with _lock:
        items = list(_tasks.values())
    if status == "done":
        items = [t for t in items if t.done]
    elif status == "todo":
        items = [t for t in items if not t.done]
    if priority:
        items = [t for t in items if t.priority == priority]
    return sorted(items, key=lambda t: (t.done, -t.id))[:limit]


def get(task_id: int) -> TaskOut | None:
    with _lock:
        return _tasks.get(task_id)


def update(task_id: int, **fields) -> TaskOut | None:
    with _lock:
        current = _tasks.get(task_id)
        if current is None:
            return None
        data = current.model_dump()
        data.update({k: v for k, v in fields.items() if v is not None})
        updated = TaskOut(**data)
        _tasks[task_id] = updated
        _persist()
        return updated


def toggle(task_id: int) -> TaskOut | None:
    current = get(task_id)
    return update(task_id, done=not current.done) if current else None


def delete(task_id: int) -> bool:
    with _lock:
        removed = _tasks.pop(task_id, None) is not None
        if removed:
            _persist()
        return removed


def stats() -> dict:
    with _lock:
        items = list(_tasks.values())
    total, done = len(items), sum(1 for t in items if t.done)
    return {
        "total": total, "done": done, "todo": total - done,
        "urgent_high": sum(1 for t in items if not t.done and t.priority == "high"),
        "completion_pct": round(done / total * 100, 1) if total else 0.0,
    }


_load()
```

### `backend/app/main.py`

```python
import socket
import time
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Response
from fastapi.middleware.cors import CORSMiddleware

from . import store
from .config import settings
from .models import TaskIn, TaskPatch

START = time.time()


@asynccontextmanager
async def lifespan(app: FastAPI):
    store.seed()
    app.state.started = time.time()
    yield


app = FastAPI(title=settings.app_name, version=settings.version, lifespan=lifespan)

if settings.cors_origins:
    app.add_middleware(CORSMiddleware, allow_origins=list(settings.cors_origins),
                       allow_methods=["*"], allow_headers=["*"])


@app.get("/api/info")
@app.get("/")
def info():
    return {
        "service": settings.app_name, "version": settings.version,
        "environment": settings.environment, "server": "uvicorn+fastapi",
        "hostname": socket.gethostname(),
        "uptime_seconds": round(time.time() - START, 1),
        "routes": ["/api/health", "/api/ready", "/api/tasks", "/api/tasks/{id}",
                   "/api/tasks/{id}/toggle", "/api/stats", "/docs"],
    }


@app.get("/api/health")
def health():
    """LIVENESS — never touches a dependency."""
    return {"status": "ok", "uptime_seconds": round(time.time() - START, 1)}


@app.get("/api/ready")
def ready(response: Response):
    """READINESS — data dir must be writable."""
    writable = store._persist() is None and True
    ok = True
    if not ok:
        response.status_code = 503
    return {"ready": ok, "checks": {"storage": writable}}


@app.get("/api/tasks")
def list_tasks(status: str | None = None, priority: str | None = None, limit: int = 100):
    return {"source": "database", "tasks": store.list_tasks(status, priority, limit)}


@app.post("/api/tasks", status_code=201)
def create_task(payload: TaskIn):
    return store.create(payload.title.strip(), payload.priority, payload.tags)


@app.get("/api/tasks/{task_id}")
def get_task(task_id: int):
    task = store.get(task_id)
    if not task:
        raise HTTPException(404, f"task {task_id} not found")
    return task


@app.post("/api/tasks/{task_id}/toggle")
def toggle_task(task_id: int):
    task = store.toggle(task_id)
    if not task:
        raise HTTPException(404, f"task {task_id} not found")
    return task


@app.patch("/api/tasks/{task_id}")
def patch_task(task_id: int, payload: TaskPatch):
    task = store.update(task_id, **payload.model_dump(exclude_unset=True))
    if not task:
        raise HTTPException(404, f"task {task_id} not found")
    return task


@app.delete("/api/tasks/{task_id}")
def delete_task(task_id: int):
    if not store.delete(task_id):
        raise HTTPException(404, f"task {task_id} not found")
    return {"deleted": task_id}


@app.get("/api/stats")
def stats():
    return store.stats()
```

### `backend/app/__init__.py`

```python
"""TaskNest Python API."""
```

### `backend/tests/test_store.py`

```python
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from app import store
from app.models import TaskIn


def test_create_increments_ids():
    a = store.create("first")
    b = store.create("second")
    assert b.id == a.id + 1


def test_toggle_flips_done():
    t = store.create("toggle me")
    assert t.done is False
    assert store.toggle(t.id).done is True
    assert store.toggle(t.id).done is False


def test_filter_by_status():
    t = store.create("filter me")
    store.update(t.id, done=True)
    assert all(x.done for x in store.list_tasks(status="done"))
    assert all(not x.done for x in store.list_tasks(status="todo"))


def test_delete():
    t = store.create("delete me")
    assert store.delete(t.id) is True
    assert store.delete(t.id) is False
    assert store.get(t.id) is None


def test_stats_shape():
    s = store.stats()
    assert set(s) == {"total", "done", "todo", "urgent_high", "completion_pct"}


def test_pydantic_validation():
    import pytest
    with pytest.raises(Exception):
        TaskIn(title="", priority="medium")
    with pytest.raises(Exception):
        TaskIn(title="x", priority="urgent")
```

### `backend/.dockerignore`

```gitignore
__pycache__
**/__pycache__
*.py[cod]
.pytest_cache
.ruff_cache
.venv
venv
env
.git
.env
*.env
*.log
data
htmlcov
.coverage
Dockerfile*
docker-compose*.yml
.dockerignore
tests
.mypy_cache
```

---

## 🔵 CASE 1 — SIMPLE Dockerfile

```dockerfile
# CASE 1: one stage, dev-friendly, runs uvicorn with --reload.
FROM python:3.13-alpine

WORKDIR /app

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PORT=8000

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8000

# --reload is for DEVELOPMENT ONLY: it watches files and restarts workers.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--reload"]
```

```bash
cd 11-react-python-fullstack/backend
docker build -t py-simple:v1 .
docker run -d --name py -p 8000:8000 py-simple:v1
docker logs -f py
curl -s localhost:8000/api/tasks | python3 -m json.tool
open http://localhost:8000/docs           # ← FastAPI's automatic Swagger UI 🎉
docker images py-simple:v1                # ~190 MB
docker exec py sh -c 'ls /app; python -c "import pytest" 2>&1 | tail -1'
docker rm -f py
```

**Problems with Case 1:** runs as **root**, ships `tests/` and dev files, `--reload` in production wastes CPU and is a security risk, single worker (no concurrency), no healthcheck, ~190 MB.

---

## 🟢 CASE 2 — MULTI-STAGE Dockerfile

```dockerfile
# syntax=docker/dockerfile:1

ARG PYTHON_IMAGE=python:3.13-alpine

# ══════════════ STAGE 1: wheels (runtime deps) ══════════════
FROM ${PYTHON_IMAGE} AS wheels
WORKDIR /build
# compilers needed only if a dependency has no prebuilt wheel for musl
RUN apk add --no-cache gcc musl-dev linux-headers
COPY backend/requirements.txt .
RUN --mount=type=cache,target=/root/.cache/pip \
    pip wheel --no-cache-dir --wheel-dir /wheels -r requirements.txt


# ══════════════ STAGE 2: test ══════════════
FROM ${PYTHON_IMAGE} AS test
WORKDIR /build
COPY backend/requirements-dev.txt .
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-cache-dir -r requirements-dev.txt
COPY backend/ .
# 🔑 A failure here ABORTS the build → no image is produced
RUN python -m pytest tests/ -q --tb=short
RUN python -m ruff check . || true


# ══════════════ STAGE 3: runtime ══════════════
FROM ${PYTHON_IMAGE} AS runtime

ARG APP_VERSION=1.0.0
ARG GIT_COMMIT=unknown

ENV APP_VERSION=${APP_VERSION} \
    GIT_COMMIT=${GIT_COMMIT} \
    APP_NAME=tasknest-python \
    APP_ENV=production \
    HOST=0.0.0.0 \
    PORT=8000 \
    DATA_DIR=/app/data \
    LOG_LEVEL=INFO \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

LABEL org.opencontainers.image.title="tasknest-python" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.revision="${GIT_COMMIT}"

WORKDIR /app

# libpq only if you later use psycopg with a real Postgres
RUN apk add --no-cache curl \
 && addgroup -S -g 101 app && adduser -S -u 100 -G app -g 101 app \
 && mkdir -p /app/data && chown -R app:app /app

# install from prebuilt wheels: no compiler, no network in this stage
COPY --from=wheels /wheels /wheels
RUN pip install --no-cache-dir --no-index --find-links=/wheels /wheels/* \
 && rm -rf /wheels /root/.cache

# copy ONLY the application package from the TEST stage (where it was validated)
COPY --from=test --chown=app:app /build/app ./app

USER app
EXPOSE 8000
STOPSIGNAL SIGTERM
VOLUME ["/app/data"]

HEALTHCHECK --interval=20s --timeout=3s --start-period=15s --retries=3 \
  CMD curl -fsS http://127.0.0.1:8000/api/health || exit 1

# 🔑 PRODUCTION server command:
#   gunicorn manages the process; uvicorn workers speak ASGI.
#   --workers 1 is deliberate for the demo; scale with `docker compose up --scale`.
CMD ["gunicorn", "app.main:app", \
     "--worker-class", "uvicorn.workers.UvicornWorker", \
     "--bind", "0.0.0.0:8000", \
     "--workers", "2", \
     "--threads", "4", \
     "--timeout", "60", \
     "--graceful-timeout", "25", \
     "--access-logfile", "-", \
     "--error-logfile", "-"]
```

```bash
cd 11-react-python-fullstack
docker build -f backend/Dockerfile.multistage \
  --build-arg APP_VERSION=1.0.0 -t py-multi:v1 .

docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" | grep py-
#   py-simple   v1   ~190 MB
#   py-multi    v1   ~155 MB

docker run -d --name pym -p 8000:8000 py-multi:v1
curl -s localhost:8000/api/health
curl -s localhost:8000/api/tasks | python3 -m json.tool
docker exec pym whoami                       # app ✅
docker exec pym sh -c 'ls /app'              # app/  (no tests/) ✅
docker exec pym python -c "import pytest"    # ModuleNotFoundError ✅
docker history py-multi:v1 --human --format "table {{.Size}}\t{{.CreatedBy}}" | head -10
docker rm -f pym
```

### `docker-compose.yml` (full stack, Case 2)

```yaml
name: tasknest-py

x-logging: &logging
  driver: json-file
  options: { max-size: "10m", max-file: "3" }

services:
  api:
    build:
      context: .                              # repo root → can see backend/ and frontend/
      dockerfile: backend/Dockerfile.multistage
      target: runtime
      args: { APP_VERSION: "${APP_VERSION:-1.0.0}" }
    image: tasknest-py-api:${APP_VERSION:-1.0.0}
    restart: unless-stopped
    logging: *logging
    environment:
      APP_ENV: production
      PORT: "8000"
      LOG_LEVEL: ${LOG_LEVEL:-INFO}
      DATA_DIR: /app/data
    volumes:
      - api-data:/app/data
    read_only: true
    tmpfs: [/tmp:size=32M]
    cap_drop: [ALL]
    security_opt: ["no-new-privileges:true"]
    deploy:
      resources: { limits: { cpus: "0.75", memory: 256M } }
    networks: [backend]
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://127.0.0.1:8000/api/health || exit 1"]
      interval: 15s
      timeout: 3s
      retries: 4
      start_period: 20s
    stop_grace_period: 30s

  web:
    build:
      context: ./frontend
      dockerfile: Dockerfile                  # Project 8 Case 2
      args: { VITE_API_URL: /api }
    image: tasknest-py-web:${APP_VERSION:-1.0.0}
    restart: unless-stopped
    logging: *logging
    depends_on:
      api: { condition: service_healthy }
    ports: ["${WEB_PORT:-8080}:8080"]
    read_only: true
    tmpfs: [/var/cache/nginx:size=16M, /var/run:size=1M, /tmp:size=8M]
    cap_drop: [ALL]
    security_opt: ["no-new-privileges:true"]
    networks: [frontend, backend]
    healthcheck:
      test: ["CMD-SHELL", "wget -q --spider http://127.0.0.1:8080/healthz || exit 1"]
      interval: 20s
      timeout: 3s
      retries: 3

volumes:
  api-data:

networks:
  frontend:
  backend:
```

> 📌 In `frontend/nginx.conf` the upstream is `http://api:8000/` — matching the service name `api` above.

```bash
cp .env.example .env
docker compose up -d --build --wait
docker compose ps
open http://localhost:8080
curl -s localhost:8080/api/stats | python3 -m json.tool
```

---

## ⚠️ Python-specific traps this project teaches

| Trap | Symptom | Fix |
|---|---|---|
| `__pycache__` from your host | Weird import errors, stale bytecode | `.dockerignore` with `**/__pycache__` + `PYTHONDONTWRITEBYTECODE=1` |
| No `PYTHONUNBUFFERED=1` | **Logs don't appear** until the buffer flushes — looks like a hang | Always set it (the official python images already do) |
| `pip install` as root then `USER app` | Files owned by root, app can't write | `COPY --chown` + create dirs before `USER` |
| `--reload` in production | High CPU, code injection risk, single worker | `gunicorn`/`uvicorn` without `--reload` |
| Bind mount owned by host uid 1000 | `PermissionError` writing `/app/data` | `--user $(id -u):$(id -g)` in dev, or `chown 100:101` |
| `pip install` in the runtime stage | gcc + build deps ship to production | Build **wheels** in stage 1, install with `--no-index` in stage 3 |
| `requirements.txt` copied with the source | Every code change reinstalls all deps | Copy the manifest **first** (Project 3, Task 3.3) |
| `alpine` + numpy/pandas/scipy | Compiles from source for 10+ minutes, or fails on musl | Use `python:3.13-slim` (glibc, prebuilt wheels) |

```bash
# demonstrate the alpine-vs-slim tradeoff (only if you use scientific packages)
echo "numpy" > /tmp/req.txt
time docker build -t t-alpine - <<'EOF'
FROM python:3.13-alpine
RUN apk add --no-cache gcc g++ musl-dev linux-headers openblas-dev
COPY req.txt .
RUN pip install --no-cache-dir numpy
EOF
time docker build -t t-slim - <<'EOF'
FROM python:3.13-slim
COPY req.txt .
RUN pip install --no-cache-dir numpy
EOF
docker images t-alpine t-slim
```

---

## 🔨 Tasks for Project 11

> **11.1** Build both cases and compare size, `docker history` layer count, and whether `pytest` is importable in each. Then run `docker exec` in Case 1 and find at least **four** things present that shouldn't be in a production image.

> **11.2** Prove `PYTHONUNBUFFERED` matters. Remove it from Case 2's `ENV`, rebuild, add a `print()` in a request handler, and hit the endpoint. Do the logs appear immediately? Restore it and compare. Explain what buffering has to do with `docker logs`.

> **11.3** Worker showdown. Run the same image three ways and benchmark with a simple loop:
> ```bash
> docker run -d -p 8001:8000 py-multi:v1 uvicorn app.main:app --host 0.0.0.0 --port 8000
> docker run -d -p 8002:8000 py-multi:v1 gunicorn app.main:app -k uvicorn.workers.UvicornWorker -w 1 -b 0.0.0.0:8000
> docker run -d -p 8003:8000 py-multi:v1     # the image's own CMD: 2 workers
> for p in 8001 8002 8003; do echo -n "port $p: "; \
>   time (for i in $(seq 1 200); do curl -s -o /dev/null localhost:$p/api/tasks & done; wait); done
> ```
> Record the times and explain the difference.

> **11.4** Swap the in-memory store for **SQLite on a volume**, then for **PostgreSQL**. For each: what changes in the Dockerfile, the compose file, and the volume setup? Prove data survives `docker compose down && up -d` in both.

> **11.5** Fix the bind-mount permission problem in dev. Run:
> ```bash
> docker run -d -p 8000:8000 -v "$(pwd)/data:/app/data" py-multi:v1
> docker logs -f py-multi        # PermissionError on /app/data/tasks.json
> ```
> Solve it three ways (host `chown`, `--user $(id -u):$(id -g)`, named volume) and note the trade-off of each.

> **11.6** Add a `dev` compose override with hot reload using `uvicorn --reload` and a bind mount of `backend/app`. Confirm a code change takes effect in under 2 seconds with no rebuild. Why is that acceptable in dev but forbidden in production?

<details>
<summary>👉 Answers</summary>

**11.1** Case 1 contains: `tests/` and test fixtures, dev files (`.dockerignore` may exclude some but `COPY . .` grabs the rest), `pytest`/`ruff` if installed, `__pycache__` directories, and it runs as **root**. Case 2 ships only `/app/app` — no tests, no pytest, no compiler, non-root. Layer count is higher in Case 2 (more instructions) but total **bytes** are lower, and each layer is independently cacheable.

**11.2** Without `PYTHONUNBUFFERED=1`, Python buffers stdout when it is **not a TTY** — which is always the case inside a container. Your `print()` sits in a 4–8 KB buffer and only appears in `docker logs` when the buffer fills or the process exits. That looks exactly like a hang or a lost log line, and it makes production debugging miserable. `PYTHONUNBUFFERED=1` (or `python -u`) forces line-buffered/flush-per-write output. Note the official `python` images set this for you — which is why it "works" until you build `FROM alpine` directly. Same story for Node (`stdout` is async) and Java (`System.out` is auto-flushed, logback may not be).

**11.3** Rough expectations on a laptop: single `uvicorn` ≈ slowest under concurrency (one process, one event loop, blocked by any sync work); `gunicorn -w 1` ≈ similar but with a supervising master process (auto-restarts crashed workers, handles `SIGHUP` reloads); `gunicorn -w 2` ≈ up to ~2× throughput on multi-core because each worker is a separate OS process (Python's GIL means **threads don't parallelise CPU work — processes do**). Rule: `workers = (2 × CPU limit) + 1`, bounded by memory (each worker is a full copy of your app). Add `--threads` only for I/O-bound sync endpoints.

**11.4** **SQLite:** add `sqlite` (built into Python), point `DATABASE_URL=sqlite:////app/data/app.db`, and mount a **named volume** at `/app/data`. Nothing else changes. Survives `down && up`. **PostgreSQL:** add a `db` service (`postgres:17-alpine`) with its own volume + healthcheck, `depends_on: db: condition: service_healthy`, `psycopg[binary]` in requirements, and `DATABASE_URL=postgresql://u:p@db:5432/app` — note the hostname is the **service name** `db`, never `localhost`. In Case 2 you'd also drop `--no-index` for psycopg if it has no musl wheel, or switch the base to `python:3.13-slim`.

**11.5** (a) `sudo chown -R 100:101 data` — aligns the host folder with the container uid; permanent, needs root once, but now *your* user may not own the files. (b) `--user $(id -u):$(id -g)` — the container runs as you; files on the host are yours; but `/etc/passwd` has no entry for that uid, which breaks anything that resolves a username (`~`, some libraries, `git`). (c) **Named volume** — Docker owns it and copies the image's ownership on first use; the cleanest answer for real data, at the cost of not being able to `cat` the file from your host directly (`docker volume inspect` + `docker run --rm -v vol:/d alpine cat /d/f`).

**11.6** Acceptable in dev because the blast radius is your laptop and the feedback loop matters more than efficiency. Forbidden in production because: the source is mutable at runtime (no immutable deployments, no rollback, no auditability), `--reload` runs a file-watcher that burns CPU, it uses a single worker, and if an attacker can write a file they get **remote code execution**. Production = immutable image, built from a pinned commit, deployed as a new version.
</details>

---

---

## ➡️ Next

**[`15-PROJECT-12-react-go-fullstack.md`](15-PROJECT-12-react-go-fullstack.md)** — Project 12.

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish%20Kumar%20Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn → <https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260>
🐙 GitHub → <https://github.com/3558Bhk>

*Built for engineers who learn by breaking things on purpose.*

</div>
