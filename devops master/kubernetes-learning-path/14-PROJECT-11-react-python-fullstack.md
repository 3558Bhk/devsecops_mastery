# 🐍 Project 11 — React + Python (FastAPI) Full Stack on Kubernetes

> **Time:** 2 hours · **Prereq:** [Project 10](13-PROJECT-10-react-java-fullstack.md) — same architecture, different runtime
>
> - 🔵 **CASE 1 — Simple.** FastAPI + SQLite/Postgres + React, running in 20 minutes.
> - 🟢 **CASE 2 — Production.** Multi-stage slim build, Gunicorn/Uvicorn workers sized correctly, async probes, Alembic migrations as a Job, HPA on request rate, graceful SIGTERM handling in a Python process, and the Python-specific memory traps.
>
> **The point of this project isn't the stack — you've seen the Kubernetes parts.** It's the **Python-specific** decisions: worker count, signal handling, GIL vs processes, `slim` vs `alpine`, and why a Python Pod OOMKills at half its heap.

---

## 11.0 What's actually different about Python on Kubernetes

| Concern | Java | Python |
|---|---|---|
| Memory model | Heap is a fixed, declared region | No declared heap — RSS grows with allocations, **never shrinks** |
| Container awareness | JVM reads cgroups (`UseContainerSupport`) | Python doesn't care; *you* must compute the limits |
| Concurrency | Real threads | **GIL** — one thread runs bytecode at a time |
| Scaling unit | Threads inside one process | **Processes** (workers). One process per core, roughly |
| Startup | 15–40 s | 0.5–3 s |
| Signal handling | JVM handles SIGTERM | **You must register a handler**, and `sh -c` swallows it |
| Image base | JRE ~200 MB | `python:3.13-slim` ~130 MB; `alpine` ~55 MB but **compiles wheels from source** |
| Native deps | Rare | Very common (numpy, pandas, psycopg2, cryptography, pillow) |

**The three Python-on-Kubernetes mistakes that cost the most time:**

1. **`python:alpine` with numpy/pandas/psycopg2.** Alpine uses musl, not glibc. Most scientific packages ship manylinux (glibc) wheels, so `pip install` falls back to **compiling from source** — 10-minute builds, 900 MB images, and subtle runtime bugs. Use `python:3.13-slim` (Debian, glibc, wheels work).
2. **One Uvicorn process with `--workers 1` and a CPU limit of 2.** You're using half your CPU. Python's GIL means you need *processes*, not threads.
3. **`CMD gunicorn ...` in shell form** → `sh` is PID 1 → SIGTERM goes to the shell, not gunicorn → 30 s grace period → SIGKILL → dropped requests. Always exec form, or use `exec`.

---

## 11.1 The app

```bash
mkdir -p ~/k8s-learn/p11/{api,ui,k8s,scripts} && cd ~/k8s-learn/p11/api
```

`api/requirements.txt`:

```
fastapi==0.115.6
uvicorn[standard]==0.34.0
gunicorn==23.0.0
sqlalchemy==2.0.36
psycopg2-binary==2.9.10
alembic==1.14.0
pydantic==2.10.4
pydantic-settings==2.7.0
prometheus-fastapi-instrumentator==7.0.2
httpx==0.28.1
structlog==24.4.0
tenacity==9.0.0
```

`api/requirements-dev.txt`:

```
-r requirements.txt
pytest==8.3.4
pytest-asyncio==0.25.0
pytest-cov==6.0.0
ruff==0.8.4
mypy==1.14.1
```

`api/app/config.py`:

```python
"""Settings resolved from environment variables.

Supports the *_FILE convention so secrets can be mounted as files
instead of injected as env vars (see Project 3 §3.6).
"""
from functools import lru_cache
from pathlib import Path
from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


def _read_secret(value: str | None, file_var: str | None) -> str | None:
    """Prefer <NAME>_FILE (a path) over <NAME> (a literal)."""
    if file_var and (p := Path(file_var)).is_file():
        return p.read_text(encoding="utf-8").strip()
    return value


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="", case_sensitive=False, extra="ignore")

    app_name: str = "shop-api"
    version: str = Field(default="dev", alias="APP_VERSION")
    environment: str = Field(default="development", alias="ENVIRONMENT")
    log_level: str = Field(default="INFO", alias="LOG_LEVEL")
    debug: bool = False

    host: str = "0.0.0.0"
    port: int = 8080

    database_url: str = Field(
        default="postgresql+psycopg2://shop:shop@db:5432/app",
        alias="DATABASE_URL",
    )
    database_password_file: str | None = Field(default=None, alias="DATABASE_PASSWORD_FILE")
    database_user_file: str | None = Field(default=None, alias="DATABASE_USER_FILE")

    db_pool_size: int = Field(default=10, alias="DB_POOL_SIZE")
    db_max_overflow: int = Field(default=5, alias="DB_MAX_OVERFLOW")
    db_pool_timeout: int = Field(default=5, alias="DB_POOL_TIMEOUT")

    request_timeout_s: float = 10.0
    cors_origins: str = Field(default="*", alias="CORS_ORIGINS")

    # Downward API
    pod_name: str = Field(default="local", alias="POD_NAME")
    pod_namespace: str = Field(default="local", alias="POD_NAMESPACE")
    pod_ip: str = Field(default="127.0.0.1", alias="POD_IP")
    node_name: str = Field(default="local", alias="NODE_NAME")

    @field_validator("log_level")
    @classmethod
    def _upper(cls, v: str) -> str:
        return v.upper()

    @property
    def cors_origin_list(self) -> list[str]:
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]

    def resolved_database_url(self) -> str:
        """Swap in credentials read from mounted secret files."""
        url = self.database_url
        pw = _read_secret(None, self.database_password_file)
        user = _read_secret(None, self.database_user_file)
        if pw:
            # postgresql+psycopg2://USER:PASS@host:port/db
            head, _, tail = url.partition("://")
            creds, _, hostpart = tail.partition("@")
            _u, _, _p = creds.partition(":")
            url = f"{head}://{user or _u}:{pw}@{hostpart}"
        return url


@lru_cache
def get_settings() -> Settings:
    return Settings()
```

`api/app/db.py`:

```python
from collections.abc import Generator
from contextlib import contextmanager

from sqlalchemy import create_engine, text
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker
from tenacity import retry, stop_after_attempt, wait_exponential

from .config import get_settings

_s = get_settings()

engine = create_engine(
    _s.resolved_database_url(),
    pool_size=_s.db_pool_size,
    max_overflow=_s.db_max_overflow,
    pool_timeout=_s.db_pool_timeout,
    pool_pre_ping=True,          # ⭐ detect stale connections after a DB failover
    pool_recycle=1800,           # recycle before Postgres' idle timeout kills them
    echo=False,
    future=True,
)

SessionLocal = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False, future=True)


class Base(DeclarativeBase):
    pass


def get_db() -> Generator[Session, None, None]:
    """FastAPI dependency — one session per request."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


@retry(stop=stop_after_attempt(5), wait=wait_exponential(multiplier=1, min=1, max=10))
def wait_for_db(timeout_probe: bool = True) -> None:
    """Used by the readiness probe and by startup."""
    with engine.connect() as conn:
        conn.execute(text("SELECT 1"))
```

`api/app/models.py`:

```python
from datetime import datetime

from sqlalchemy import DateTime, Index, Numeric, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column

from .db import Base


class Product(Base):
    __tablename__ = "products"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    price: Mapped[float] = mapped_column(Numeric(10, 2), nullable=False)
    description: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    __table_args__ = (Index("idx_products_name_lower", func.lower(name)),)

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "name": self.name,
            "price": float(self.price),
            "description": self.description,
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }
```

`api/app/schemas.py`:

```python
from decimal import Decimal
from pydantic import BaseModel, ConfigDict, Field


class ProductCreate(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)
    name: str = Field(min_length=1, max_length=120)
    price: Decimal = Field(ge=0, decimal_places=2)
    description: str | None = Field(default=None, max_length=2000)


class ProductOut(ProductCreate):
    id: int
    created_at: str | None = None


class HealthOut(BaseModel):
    status: str
    version: str
    pod: str
    checks: dict[str, str] = {}
```

`api/app/logging_conf.py`:

```python
"""Structured JSON logs to stdout, with trace-friendly fields."""
import logging
import sys

import structlog

from .config import get_settings

_s = get_settings()


def configure_logging() -> None:
    logging.basicConfig(
        format="%(message)s",
        stream=sys.stdout,
        level=getattr(logging, _s.log_level, logging.INFO),
        force=True,
    )
    # silence noisy libraries
    for noisy in ("uvicorn.access", "sqlalchemy.engine", "asyncio"):
        logging.getLogger(noisy).setLevel(logging.WARNING)

    structlog.configure(
        processors=[
            structlog.contextvars.merge_contextvars,     # ⭐ request_id propagation
            structlog.stdlib.filter_by_level,
            structlog.stdlib.add_logger_name,
            structlog.processors.TimeStamper(fmt="iso", utc=True),
            structlog.processors.StackInfoRenderer(),
            structlog.processors.format_exc_info,
            structlog.processors.UnicodeDecoder(),
            _add_k8s_context,
            structlog.processors.JSONRenderer(),
        ],
        wrapper_class=structlog.stdlib.BoundLogger,
        logger_factory=structlog.stdlib.LoggerFactory(),
        cache_logger_on_first_use=True,
    )


def _add_k8s_context(_logger, _method, event_dict):
    event_dict.setdefault("service", _s.app_name)
    event_dict.setdefault("version", _s.version)
    event_dict.setdefault("env", _s.environment)
    event_dict.setdefault("pod", _s.pod_name)
    event_dict.setdefault("namespace", _s.pod_namespace)
    return event_dict


def get_logger(name: str = __name__) -> structlog.stdlib.BoundLogger:
    return structlog.get_logger(name)
```

`api/app/main.py`:

```python
import asyncio
import contextlib
import os
import signal
import time
import uuid
from collections.abc import AsyncIterator

import structlog
from fastapi import Depends, FastAPI, HTTPException, Query, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from prometheus_fastapi_instrumentator import Instrumentator
from sqlalchemy import text
from sqlalchemy.orm import Session

from .config import get_settings
from .db import Base, engine, get_db
from .logging_conf import configure_logging, get_logger
from .models import Product
from .schemas import HealthOut, ProductCreate, ProductOut

configure_logging()
log = get_logger("app")
settings = get_settings()

# ── global state for chaos-testing the probes ───────────────────
state = {"liveness_ok": True, "readiness_ok": True, "draining": False}

app = FastAPI(
    title=settings.app_name,
    version=settings.version,
    docs_url="/docs" if settings.environment != "production" else None,
    redoc_url=None,
    openapi_url="/openapi.json" if settings.environment != "production" else None,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origin_list,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["X-Request-ID"],
)


# ── request ID + structured access log ─────────────────────────
@app.middleware("http")
async def request_context(request: Request, call_next):
    request_id = request.headers.get("x-request-id") or str(uuid.uuid4())
    structlog.contextvars.clear_contextvars()
    structlog.contextvars.bind_contextvars(request_id=request_id, method=request.method, path=request.url.path)
    t0 = time.perf_counter()
    try:
        response = await call_next(request)
    except Exception:
        log.exception("unhandled_error", request_id=request_id)
        response = JSONResponse({"error": "internal_error", "request_id": request_id}, status_code=500)
    dt_ms = (time.perf_counter() - t0) * 1000
    response.headers["X-Request-ID"] = request_id
    if not request.url.path.startswith(("/healthz", "/readyz", "/metrics")):
        log.info("request", status=response.status_code, duration_ms=round(dt_ms, 2))
    return response


# ── Prometheus metrics at /metrics ─────────────────────────────
Instrumentator(
    should_group_status_codes=True,
    should_ignore_untemplated=True,          # ⭐ prevents label cardinality explosion
    excluded_handlers=["/healthz", "/readyz", "/metrics"],
    inprogress_name="http_requests_in_progress",
).instrument(app).expose(app, endpoint="/metrics", include_in_schema=False)


@app.on_event("startup")
async def on_startup() -> None:
    log.info("startup", version=settings.version, pod=settings.pod_name, env=settings.environment)
    Base.metadata.create_all(bind=engine)     # dev convenience; production uses Alembic
    log.info("startup_complete")


@app.on_event("shutdown")
async def on_shutdown() -> None:
    log.info("shutdown", msg="draining connections")
    engine.dispose()
    log.info("shutdown_complete")


# ── PROBES ─────────────────────────────────────────────────────
@app.get("/healthz", include_in_schema=False)
async def liveness() -> Response:
    """LIVENESS: is the process alive and not deadlocked?
    ⭐ Must NEVER touch the database or any dependency.
    """
    if not state["liveness_ok"]:
        return Response("dead\n", status_code=500, media_type="text/plain")
    return Response("ok\n", media_type="text/plain")


@app.get("/readyz", include_in_schema=False)
async def readiness() -> Response:
    """READINESS: can this replica serve traffic right now?
    Checks the database, with a short timeout so a slow DB doesn't hang the probe.
    """
    if state["draining"]:
        return Response("draining\n", status_code=503, media_type="text/plain")
    if not state["readiness_ok"]:
        return Response("not ready\n", status_code=503, media_type="text/plain")
    try:
        # ⭐ run the blocking DB call in a thread so we don't block the event loop
        await asyncio.wait_for(asyncio.to_thread(_check_db), timeout=2.0)
    except asyncio.TimeoutError:
        log.warning("readiness_db_timeout")
        return Response("db timeout\n", status_code=503, media_type="text/plain")
    except Exception as exc:                                  # noqa: BLE001
        log.warning("readiness_db_error", error=str(exc))
        return Response("db error\n", status_code=503, media_type="text/plain")
    return Response("ready\n", media_type="text/plain")


def _check_db() -> None:
    with engine.connect() as conn:
        conn.execute(text("SELECT 1"))


@app.get("/health", response_model=HealthOut)
async def health() -> HealthOut:
    checks = {}
    try:
        await asyncio.wait_for(asyncio.to_thread(_check_db), timeout=2.0)
        checks["db"] = "up"
    except Exception as exc:                                  # noqa: BLE001
        checks["db"] = f"down: {exc.__class__.__name__}"
    return HealthOut(
        status="ok" if checks.get("db") == "up" else "degraded",
        version=settings.version,
        pod=settings.pod_name,
        checks=checks,
    )


# ── BUSINESS ENDPOINTS ─────────────────────────────────────────
@app.get("/api/products", response_model=list[ProductOut])
async def list_products(
    q: str | None = Query(default=None, max_length=100),
    limit: int = Query(default=50, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
    db: Session = Depends(get_db),
) -> list[ProductOut]:
    query = db.query(Product)
    if q:
        query = query.filter(Product.name.ilike(f"%{q}%"))
    rows = query.order_by(Product.id).offset(offset).limit(limit).all()
    return [ProductOut(**r.to_dict()) for r in rows]


@app.get("/api/products/{product_id}", response_model=ProductOut)
async def get_product(product_id: int, db: Session = Depends(get_db)) -> ProductOut:
    row = db.get(Product, product_id)
    if not row:
        raise HTTPException(404, detail=f"product {product_id} not found")
    return ProductOut(**row.to_dict())


@app.post("/api/products", response_model=ProductOut, status_code=201)
async def create_product(payload: ProductCreate, db: Session = Depends(get_db)) -> ProductOut:
    row = Product(name=payload.name, price=payload.price, description=payload.description)
    db.add(row)
    db.commit()
    db.refresh(row)
    log.info("product_created", product_id=row.id, name=row.name)
    return ProductOut(**row.to_dict())


@app.delete("/api/products/{product_id}", status_code=204)
async def delete_product(product_id: int, db: Session = Depends(get_db)) -> Response:
    row = db.get(Product, product_id)
    if not row:
        raise HTTPException(404, detail=f"product {product_id} not found")
    db.delete(row)
    db.commit()
    log.warning("product_deleted", product_id=product_id)
    return Response(status_code=204)


@app.get("/api/products/slow", include_in_schema=False)
async def slow(seconds: float = Query(default=3.0, le=30)) -> dict:
    """Blocking work — demonstrates why you must not block the event loop."""
    await asyncio.sleep(seconds)
    return {"slept": seconds}


@app.get("/api/products/blocking", include_in_schema=False)
def blocking(seconds: float = Query(default=3.0, le=30)) -> dict:
    """A SYNC def — FastAPI runs it in a threadpool, so it does NOT block the loop."""
    time.sleep(seconds)
    return {"slept": seconds}


# ── CHAOS SWITCHES (for testing probes, alerts, rollbacks) ─────
@app.post("/api/chaos/{what}", include_in_schema=False)
async def chaos(what: str) -> dict:
    if what == "liveness":
        state["liveness_ok"] = False
    elif what == "readiness":
        state["readiness_ok"] = False
    elif what == "drain":
        state["draining"] = True
    elif what == "recover":
        state.update(liveness_ok=True, readiness_ok=True, draining=False)
    elif what == "oom":
        leak: list[bytes] = []
        while True:
            leak.append(os.urandom(10 * 1024 * 1024))
    else:
        raise HTTPException(400, f"unknown chaos mode: {what}")
    log.warning("chaos", mode=what)
    return {"chaos": what, "state": state}


# ── ⭐ GRACEFUL SHUTDOWN ───────────────────────────────────────
def _install_signal_handlers() -> None:
    """SIGTERM → stop accepting connections, let in-flight requests finish.

    Gunicorn handles this itself; this is for bare Uvicorn.
    """
    loop = asyncio.get_running_loop()

    def handle(sig: signal.Signals) -> None:
        log.info("signal_received", signal=sig.name)
        state["draining"] = True          # readiness → 503 → removed from endpoints
        loop.create_task(_shutdown())

    async def _shutdown() -> None:
        await asyncio.sleep(2)            # let endpoint removal propagate
        log.info("draining_complete")
        os._exit(0)

    for sig in (signal.SIGTERM, signal.SIGINT):
        with contextlib.suppress(NotImplementedError):
            loop.add_signal_handler(sig, handle, sig)
```

`api/gunicorn_conf.py`:

```python
"""Gunicorn config tuned for Kubernetes.

The worker-count math matters:
  Python's GIL means one worker process uses ~one CPU core.
  sync workers:      workers = (2 × cores) + 1
  gevent/eventlet:   workers = 2-4 × cores (I/O bound only)
  uvicorn workers:   workers = cores  (async; each handles many connections)

Kubernetes sets no CPU affinity, so read the CGROUP limit, not os.cpu_count().
"""
import multiprocessing
import os


def _container_cpu_limit() -> float:
    """Read the cgroup CPU quota — os.cpu_count() returns the NODE's cores!"""
    # cgroup v2
    try:
        with open("/sys/fs/cgroup/cpu.max", encoding="utf-8") as f:
            quota, period = f.read().split()
            if quota != "max":
                return int(quota) / int(period)
    except (FileNotFoundError, ValueError, ZeroDivisionError):
        pass
    # cgroup v1
    try:
        with open("/sys/fs/cgroup/cpu/cpu.cfs_quota_us", encoding="utf-8") as f:
            quota = int(f.read())
        with open("/sys/fs/cgroup/cpu/cpu.cfs_period_us", encoding="utf-8") as f:
            period = int(f.read())
        if quota > 0:
            return quota / period
    except (FileNotFoundError, ValueError):
        pass
    return float(multiprocessing.cpu_count())


CPUS = _container_cpu_limit()
WORKERS = os.environ.get("WEB_CONCURRENCY") or max(2, int(CPUS))

# ── networking ──
bind = f"0.0.0.0:{os.environ.get('PORT', '8080')}"
worker_class = "uvicorn.workers.UvicornWorker"     # async
workers = int(WORKERS)
worker_connections = 1000

# ── ⭐ timeouts must exceed your slowest endpoint, or gunicorn kills workers ──
timeout = int(os.environ.get("GUNICORN_TIMEOUT", "60"))
graceful_timeout = int(os.environ.get("GUNICORN_GRACEFUL", "30"))
keepalive = 5

# ── ⭐ worker recycling: the defence against Python memory creep ──
max_requests = int(os.environ.get("GUNICORN_MAX_REQUESTS", "2000"))
max_requests_jitter = int(os.environ.get("GUNICORN_MAX_JITTER", "200"))

# ── lifecycle ──
preload_app = os.environ.get("GUNICORN_PRELOAD", "true").lower() == "true"
# preload_app=True  → import the app ONCE, then fork. Faster startup, ~40% less RSS.
#                     ⚠️ anything opened before the fork (DB pools, sockets, locks)
#                        is SHARED and corrupt. Dispose engines in post_fork.
proc_name = "shop-api"
errorlog = "-"          # stderr → collected by Kubernetes
accesslog = None        # we log with structlog middleware instead
loglevel = os.environ.get("LOG_LEVEL", "info").lower()
capture_output = True
enable_stdio_inheritance = False


def post_fork(server, worker):
    """After forking, each worker needs its OWN connection pool."""
    server.log.info(f"worker {worker.pid} spawned (container sees {CPUS:.2f} CPUs)")
    try:
        from app.db import engine
        engine.dispose(close=False)     # drop the parent's inherited sockets
    except Exception as exc:            # noqa: BLE001
        server.log.warning(f"engine.dispose failed: {exc}")


def worker_exit(server, worker):
    server.log.info(f"worker {worker.pid} exiting")
```

`api/alembic.ini` + `api/migrations/` — standard Alembic:

```bash
cd api && python -m venv .venv && . .venv/bin/activate
pip install -r requirements.txt
alembic init migrations
```

`api/migrations/env.py` (the important part):

```python
from app.config import get_settings
from app.db import Base
from app import models                       # noqa: F401  — register the models!

config = context.config
config.set_main_option("sqlalchemy.url", get_settings().resolved_database_url())
target_metadata = Base.metadata
```

```bash
alembic revision --autogenerate -m "create products"
alembic upgrade head
```

`api/Dockerfile` — 🔵 Case 1 (simple) and 🟢 Case 2 (production) in one file with targets:

```dockerfile
# syntax=docker/dockerfile:1

# ═══════════════════════════════════════════════════════════
# 🔵 CASE 1 — simple: everything in one stage
# ═══════════════════════════════════════════════════════════
FROM python:3.13-slim AS simple
WORKDIR /app
ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1 PIP_NO_CACHE_DIR=1
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
EXPOSE 8080
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]


# ═══════════════════════════════════════════════════════════
# 🟢 CASE 2 — production, multi-stage
# ═══════════════════════════════════════════════════════════

# ── builder: compile wheels, then throw the toolchain away ──
FROM python:3.13-slim AS builder
ENV PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1
WORKDIR /build

# build deps only needed if a package has no wheel
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential gcc libpq-dev \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN --mount=type=cache,target=/root/.cache/pip \
    pip wheel --wheel-dir /wheels -r requirements.txt


# ── runtime: no compiler, no headers, no root ──
FROM python:3.13-slim AS runtime

# libpq5 is the RUNTIME lib psycopg2 needs (build-essential/libpq-dev are gone)
RUN apt-get update && apt-get install -y --no-install-recommends \
        libpq5 tini curl \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd -g 10001 app \
    && useradd  -u 10001 -g app -s /bin/sh -M app \
    && mkdir -p /app /tmp/dumps \
    && chown -R app:app /app /tmp

WORKDIR /app

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONFAULTHANDLER=1 \
    PYTHONPATH=/app \
    PATH=/home/app/.local/bin:$PATH \
    PORT=8080 \
    WEB_CONCURRENCY=4 \
    GUNICORN_TIMEOUT=60 \
    GUNICORN_GRACEFUL=25 \
    GUNICORN_MAX_REQUESTS=2000 \
    GUNICORN_MAX_JITTER=200 \
    GUNICORN_PRELOAD=true

# install from prebuilt wheels — no compiler in the final image
COPY --from=builder /wheels /wheels
COPY requirements.txt .
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-cache-dir --no-index --find-links=/wheels /wheels/* \
    && rm -rf /wheels

COPY --chown=app:app . .

USER 10001:10001
EXPOSE 8080

HEALTHCHECK --interval=15s --timeout=3s --start-period=20s --retries=3 \
    CMD curl -fsS http://localhost:8080/healthz || exit 1

# tini = proper PID 1: forwards SIGTERM to gunicorn, reaps zombies
ENTRYPOINT ["/usr/bin/tini", "--"]
# exec form + gunicorn (gunicorn's master handles SIGTERM properly)
CMD ["gunicorn", "-c", "gunicorn_conf.py", "app.main:app"]

ARG GIT_SHA=unknown
LABEL org.opencontainers.image.title="shop-api-python" \
      org.opencontainers.image.description="Shop REST API (FastAPI)" \
      org.opencontainers.image.vendor="Harish Kumar Brahmandam" \
      org.opencontainers.image.source="https://github.com/3558Bhk/shop-api-python" \
      org.opencontainers.image.revision="${GIT_SHA}"
```

`.dockerignore`:

```
.venv
venv
__pycache__
**/__pycache__
*.py[cod]
.pytest_cache
.mypy_cache
.ruff_cache
.coverage
htmlcov
.git
.env
.env.*
!.env.example
tests
k8s
scripts
*.md
Dockerfile
.dockerignore
alembic/versions/*.pyc
```

Build both:

```bash
docker build --target simple   -t shop-api-py:simple .
docker build --target runtime  -t shop-api-py:prod --build-arg GIT_SHA=$(git rev-parse --short HEAD) .
docker images | grep shop-api-py
# shop-api-py   simple   ...   410MB
# shop-api-py   prod     ...   185MB      ← no compiler, no headers
```

```bash
# always test the image standalone BEFORE Kubernetes
docker run --rm -p 8080:8080 -e ENVIRONMENT=development \
  -e DATABASE_URL="postgresql+psycopg2://shop:shop@host.docker.internal:5432/app" \
  shop-api-py:prod &
sleep 8
curl -s localhost:8080/healthz
curl -s localhost:8080/metrics | head -20
docker logs $(docker ps -q | head -1) | head -5
kill %1
```

---

## 11.2 🔵 CASE 1 — Simple manifests

`k8s/simple.yaml` — the whole stack, one file (DB omitted here; it's identical to [Project 10 §10.2](13-PROJECT-10-react-java-fullstack.md#102-one-file-the-whole-stack)):

```yaml
apiVersion: apps/v1
kind: Deployment
metadata: {name: shop-api, labels: {app: shop-api}}
spec:
  replicas: 2
  selector: {matchLabels: {app: shop-api}}
  template:
    metadata: {labels: {app: shop-api}}
    spec:
      initContainers:
        - name: wait-for-db
          image: busybox:1.37
          command: ["sh","-c","until nc -z db 5432; do echo waiting; sleep 2; done"]
      containers:
        - name: api
          image: shop-api-py:simple
          imagePullPolicy: IfNotPresent
          ports: [{name: http, containerPort: 8080}]
          env:
            - {name: DATABASE_URL, value: "postgresql+psycopg2://db:5432/app"}
            - {name: DATABASE_USER_FILE,     value: /run/secrets/db/username}
            - {name: DATABASE_PASSWORD_FILE, value: /run/secrets/db/password}
            - {name: ENVIRONMENT, value: development}
          readinessProbe: {httpGet: {path: /readyz,  port: http}, initialDelaySeconds: 5,  periodSeconds: 5}
          livenessProbe:  {httpGet: {path: /healthz, port: http}, initialDelaySeconds: 15, periodSeconds: 20}
          resources:
            requests: {cpu: 200m, memory: 256Mi}
            limits:   {cpu: "1",   memory: 512Mi}
          volumeMounts:
            - {name: db, mountPath: /run/secrets/db, readOnly: true}
      volumes:
        - name: db
          secret:
            secretName: pg-creds
            items: [{key: username, path: username}, {key: POSTGRES_PASSWORD, path: password}]
            defaultMode: 0400
---
apiVersion: v1
kind: Service
metadata: {name: shop-api}
spec:
  selector: {app: shop-api}
  ports: [{name: http, port: 8080}]
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: shop
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
spec:
  ingressClassName: nginx
  rules:
    - host: shop.local
      http:
        paths:
          - path: /api
            pathType: Prefix
            backend: {service: {name: shop-api, port: {number: 8080}}}
          - path: /
            pathType: Prefix
            backend: {service: {name: shop-ui, port: {number: 80}}}
```

Note: no rewrite needed, because the FastAPI routes are already declared as `/api/products`. **Choose one convention and stick to it** — either the app owns the `/api` prefix (simpler) or the Ingress strips it (cleaner app, more Ingress config).

```bash
kubectl apply -f k8s/simple.yaml
kubectl rollout status deploy/shop-api
kubectl port-forward svc/shop-api 8080:8080 & sleep 2
curl -s localhost:8080/health | jq .
curl -s -XPOST localhost:8080/api/products -H 'Content-Type: application/json' \
  -d '{"name":"Widget","price":9.99,"description":"a widget"}' | jq .
curl -s localhost:8080/api/products | jq .
curl -s localhost:8080/metrics | grep -E '^http_request' | head
kill %1
```

---

## 11.3 🟢 CASE 2 — Production manifests

`k8s/api.yaml`:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata: {name: shop-api, namespace: shop}
automountServiceAccountToken: false
---
apiVersion: v1
kind: ConfigMap
metadata: {name: shop-api-config, namespace: shop}
data:
  ENVIRONMENT: "production"
  LOG_LEVEL: "INFO"
  DATABASE_URL: "postgresql+psycopg2://db.shop.svc.cluster.local:5432/app"
  DATABASE_USER_FILE: "/run/secrets/db/username"
  DATABASE_PASSWORD_FILE: "/run/secrets/db/password"
  DB_POOL_SIZE: "15"
  DB_MAX_OVERFLOW: "5"
  DB_POOL_TIMEOUT: "5"
  WEB_CONCURRENCY: "4"              # gunicorn workers; see the sizing note below
  GUNICORN_TIMEOUT: "60"
  GUNICORN_GRACEFUL: "25"
  GUNICORN_MAX_REQUESTS: "2000"
  GUNICORN_MAX_JITTER: "200"
  GUNICORN_PRELOAD: "true"
  CORS_ORIGINS: "https://shop.example.com"
  REQUEST_TIMEOUT_S: "10"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: shop-api
  namespace: shop
  labels:
    app: shop-api
    app.kubernetes.io/name: shop-api
    app.kubernetes.io/component: backend
    app.kubernetes.io/part-of: shop
spec:
  replicas: 3
  revisionHistoryLimit: 8
  strategy:
    type: RollingUpdate
    rollingUpdate: {maxSurge: 1, maxUnavailable: 0}
  selector: {matchLabels: {app: shop-api}}
  template:
    metadata:
      labels: {app: shop-api, version: v1}
      annotations:
        checksum/config: REPLACE_WITH_SHA
    spec:
      serviceAccountName: shop-api
      terminationGracePeriodSeconds: 60
      securityContext:
        runAsNonRoot: true
        runAsUser: 10001
        runAsGroup: 10001
        fsGroup: 10001
        seccompProfile: {type: RuntimeDefault}
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: DoNotSchedule
          minDomains: 3
          labelSelector: {matchLabels: {app: shop-api}}
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: ScheduleAnyway
          labelSelector: {matchLabels: {app: shop-api}}

      # ── 1. wait for the database ──
      initContainers:
        - name: wait-for-db
          image: busybox:1.37
          command:
            - sh
            - -c
            - |
              i=0
              until nc -z db.shop.svc.cluster.local 5432; do
                i=$((i+1)); [ $i -gt 60 ] && { echo "db timeout"; exit 1; }
                sleep 2
              done
              echo "db reachable"
          securityContext: {allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: {drop: ["ALL"]}}
          resources: {requests: {cpu: 10m, memory: 8Mi}, limits: {cpu: 100m, memory: 32Mi}}

        # ── 2. run migrations ONCE, before any app pod serves traffic ──
        - name: migrate
          image: ghcr.io/3558bhk/shop-api-py:1.0.0
          command: ["python", "-m", "alembic", "upgrade", "head"]
          envFrom: [{configMapRef: {name: shop-api-config}}]
          securityContext: {allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: {drop: ["ALL"]}}
          resources: {requests: {cpu: 100m, memory: 128Mi}, limits: {cpu: 500m, memory: 256Mi}}
          volumeMounts: [{name: tmp, mountPath: /tmp}]

      containers:
        - name: api
          image: ghcr.io/3558bhk/shop-api-py:1.0.0
          imagePullPolicy: IfNotPresent
          ports: [{name: http, containerPort: 8080}]
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities: {drop: ["ALL"]}
          envFrom: [{configMapRef: {name: shop-api-config}}]
          env:
            - {name: POD_NAME,      valueFrom: {fieldRef: {fieldPath: metadata.name}}}
            - {name: POD_NAMESPACE, valueFrom: {fieldRef: {fieldPath: metadata.namespace}}}
            - {name: POD_IP,        valueFrom: {fieldRef: {fieldPath: status.podIP}}}
            - {name: NODE_NAME,     valueFrom: {fieldRef: {fieldPath: spec.nodeName}}}
            - {name: APP_VERSION,   value: "1.0.0"}
          resources:
            requests: {cpu: 500m, memory: 512Mi, ephemeral-storage: 128Mi}
            limits:   {cpu: "2",  memory: 768Mi, ephemeral-storage: 512Mi}

          # Python starts fast — a short startupProbe is fine
          startupProbe:
            httpGet: {path: /healthz, port: http}
            periodSeconds: 2
            failureThreshold: 30            # 60s ceiling
            timeoutSeconds: 2
          readinessProbe:
            httpGet: {path: /readyz, port: http}   # ⭐ checks the DB
            periodSeconds: 5
            failureThreshold: 2
            successThreshold: 1
            timeoutSeconds: 3                      # the endpoint has a 2s internal timeout
          livenessProbe:
            httpGet: {path: /healthz, port: http}  # ⭐ process only, NEVER the DB
            periodSeconds: 15
            failureThreshold: 3
            timeoutSeconds: 3

          lifecycle:
            preStop:
              exec:
                # 1. flip readiness to 503 so endpoints drain
                # 2. sleep so kube-proxy/ingress propagate
                # 3. then gunicorn gets SIGTERM and drains gracefully
                command: ["/bin/sh", "-c", "curl -sf -XPOST localhost:8080/api/chaos/drain >/dev/null 2>&1 || true; sleep 8"]

          volumeMounts:
            - {name: tmp,   mountPath: /tmp}
            - {name: db,    mountPath: /run/secrets/db, readOnly: true}

      volumes:
        - {name: tmp, emptyDir: {sizeLimit: 256Mi}}
        - name: db
          secret:
            secretName: pg-creds
            defaultMode: 0400
            items:
              - {key: username, path: username}
              - {key: password, path: password}
---
apiVersion: v1
kind: Service
metadata: {name: shop-api, namespace: shop, labels: {app: shop-api}}
spec:
  selector: {app: shop-api}
  ports: [{name: http, port: 8080, targetPort: http}]
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata: {name: shop-api, namespace: shop}
spec:
  maxUnavailable: 1
  selector: {matchLabels: {app: shop-api}}
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata: {name: shop-api, namespace: shop}
spec:
  scaleTargetRef: {apiVersion: apps/v1, kind: Deployment, name: shop-api}
  minReplicas: 3
  maxReplicas: 25
  metrics:
    - type: Resource
      resource: {name: cpu, target: {type: Utilization, averageUtilization: 65}}
    - type: Pods
      pods:
        metric: {name: http_requests_in_progress}      # from the instrumentator
        target: {type: AverageValue, averageValue: "20"}
  behavior:
    scaleUp:   {stabilizationWindowSeconds: 0,   policies: [{type: Percent, value: 100, periodSeconds: 30}], selectPolicy: Max}
    scaleDown: {stabilizationWindowSeconds: 300, policies: [{type: Percent, value: 25,  periodSeconds: 60}], selectPolicy: Min}
```

> 🔑 **Migrations as an init container vs a Job.** An init container runs on **every** replica — Alembic's lock table makes that safe (they serialise), but it means N pods each spend time on it and a failure blocks the whole rollout. A Job runs **once**. For anything beyond a trivial migration, use the Job pattern from [Project 10 §10.12](13-PROJECT-10-react-java-fullstack.md#1012-k8sbasemigrate-jobyaml) and remove the init container.

---

## 11.4 ⭐ Sizing Gunicorn workers for a container

The classic mistake: `WEB_CONCURRENCY=8` in a Pod with `limits.cpu: 1`. You get 8 processes contending for 1 CPU, context-switching constantly, all slow.

**The rule for async workers (UvicornWorker):**

```
workers = container CPU limit        (not the node's core count!)
```

**For sync workers:**

```
workers = (2 × container CPU limit) + 1
```

**Verify Python reads the cgroup, not the node:**

```bash
kubectl exec -n shop deploy/shop-api -- python -c "
import multiprocessing, os
print('os.cpu_count()          :', os.cpu_count())          # ← the NODE's cores. WRONG to use.
print('multiprocessing.cpu_count:', multiprocessing.cpu_count())  # same, also wrong
for p in ('/sys/fs/cgroup/cpu.max', '/sys/fs/cgroup/cpu/cpu.cfs_quota_us'):
    if os.path.exists(p):
        print(p, '=', open(p).read().strip())
"
```

```
os.cpu_count()          : 8          ← the node has 8 cores
multiprocessing.cpu_count: 8
/sys/fs/cgroup/cpu.max = 200000 100000    ← the CONTAINER is limited to 2.0 CPUs
```

`gunicorn_conf.py` above reads `cpu.max` — that's the fix. Without it, **every** Python library that auto-sizes threads/processes (`multiprocessing.Pool()`, `joblib`, `concurrent.futures.ProcessPoolExecutor()`, numpy/BLAS, torch) will over-provision and thrash.

```python
# and cap BLAS/OpenMP threads, or numpy will spawn 8 threads per worker
# in the Deployment env:
- {name: OMP_NUM_THREADS,        value: "1"}
- {name: OPENBLAS_NUM_THREADS,   value: "1"}
- {name: MKL_NUM_THREADS,        value: "1"}
- {name: NUMEXPR_NUM_THREADS,    value: "1"}
```

**The full sizing table:**

| Container limit | Worker class | Workers | Memory per worker | Suggested `limits.memory` |
|---|---|---|---|---|
| 0.5 CPU | uvicorn | 2 | ~80 Mi | 384 Mi |
| 1 CPU | uvicorn | 2–4 | ~80 Mi | 512 Mi |
| 2 CPU | uvicorn | 4 | ~80 Mi | 768 Mi |
| 4 CPU | uvicorn | 8 | ~80 Mi | 1.5 Gi |
| 1 CPU | sync | 3 | ~60 Mi | 384 Mi |

`preload_app=true` cuts per-worker memory by ~40% (copy-on-write from the fork), so a 4-worker preload Pod uses maybe 120 + 3×50 = 270 Mi instead of 4×80 = 320 Mi.

**Measure it, don't guess:**

```bash
kubectl exec -n shop deploy/shop-api -- sh -c 'ps -eo pid,rss,cmd --sort=-rss | head -12'
# PID   RSS   CMD
#   1  4200  /usr/bin/tini -- gunicorn …       ← master
#  21 78400  gunicorn: worker                   ← ~76 Mi each
#  22 78100  gunicorn: worker
#  23 77900  gunicorn: worker
#  24 78200  gunicorn: worker

# total = master + Σ workers. Compare with the limit:
kubectl top pod -n shop -l app=shop-api
kubectl get deploy shop-api -n shop -o jsonpath='{.spec.template.spec.containers[0].resources.limits.memory}'; echo
```

If `Σ RSS > 0.85 × limit`, you will be OOMKilled. Reduce workers or raise the limit.

---

## 11.5 ⭐ Python memory: why you get OOMKilled with "plenty free"

Python's allocator (pymalloc + glibc malloc) **almost never returns memory to the OS.** RSS is a high-water mark, not current usage.

```bash
kubectl exec -n shop deploy/shop-api -- python -c "
import os, resource, gc
data = [bytearray(1024*1024) for _ in range(200)]     # allocate 200 MB
print('after alloc  RSS =', resource.getrusage(resource.RUSAGE_SELF).ru_maxrss // 1024, 'MB')
del data; gc.collect()
print('after free   RSS =', resource.getrusage(resource.RUSAGE_SELF).ru_maxrss // 1024, 'MB')
print('cgroup usage =', int(open('/sys/fs/cgroup/memory.current').read()) // 1024 // 1024, 'MB')
"
```

```
after alloc  RSS = 213 MB
after free   RSS = 213 MB      ← ⛔ never returned to the OS
cgroup usage = 41 MB           ← the kernel sees it as free (cached/reclaimable)
```

Two numbers matter:

| Metric | Source | What the OOM killer uses |
|---|---|---|
| `ru_maxrss` | Python's resource module | No — peak, never decreases |
| **`memory.current`** | `/sys/fs/cgroup/memory.current` | **Yes** (via `memory.max`) |
| `container_memory_working_set_bytes` | cAdvisor | = `memory.current` − inactive_file. **This is what Kubernetes reports and what triggers OOMKill** |

**Mitigations, in order of effectiveness:**

1. **`max_requests` + jitter** — recycle workers before they grow. Already in `gunicorn_conf.py`. This is the single most effective Python-in-a-container trick.
   ```python
   max_requests = 2000
   max_requests_jitter = 200     # so all workers don't restart simultaneously
   ```
2. **`jemalloc` or `mimalloc`** — much better at returning memory than glibc malloc:
   ```dockerfile
   RUN apt-get update && apt-get install -y --no-install-recommends libjemalloc2 && rm -rf /var/lib/apt/lists/*
   ENV LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libjemalloc.so.2
   ```
   Typically 20–40% lower steady-state RSS for allocation-heavy Python.
3. **`MALLOC_ARENA_MAX=2`** — stops glibc creating 8 arenas per core:
   ```yaml
   env: [{name: MALLOC_ARENA_MAX, value: "2"}]
   ```
4. **Fewer, bigger workers** — 4 workers × 200 MB beats 8 × 200 MB.
5. **`tracemalloc` in dev** to find the actual leak:
   ```python
   import tracemalloc
   tracemalloc.start(25)
   # … later …
   snapshot = tracemalloc.take_snapshot()
   for stat in snapshot.statistics("lineno")[:20]: print(stat)
   ```
6. **`memray`** for real profiling:
   ```bash
   pip install memray
   memray run --live-remote -o /tmp/dump.bin python -m app.main
   memray flamegraph /tmp/dump.bin
   ```

**Set the limit with headroom:**

```yaml
resources:
  requests: {memory: 512Mi}
  limits:   {memory: 768Mi}      # ⭐ NOT equal to requests, unless you've measured the true peak
```

Unlike Java, Python's memory is genuinely variable, so `requests == limits` (Guaranteed QoS) requires real measurement. Most teams run Burstable for Python.

---

## 11.6 ⭐ Graceful shutdown for a Python process

The chain that must work:

```
kubectl delete pod
  → preStop: curl /api/chaos/drain  (readiness → 503 → endpoints removed)
  → preStop: sleep 8                (kube-proxy + ingress propagate)
  → SIGTERM to PID 1 (tini)
  → tini forwards SIGTERM to gunicorn master
  → master signals workers: finish in-flight, accept nothing new
  → graceful_timeout (25s) elapses → SIGKILL any stragglers
  → master exits
  → terminationGracePeriodSeconds (60s) is the absolute backstop
```

**Prove it:**

```bash
kubectl logs -n shop -f deploy/shop-api &
LOGS=$!
POD=$(kubectl get pod -n shop -l app=shop-api -o jsonpath='{.items[0].metadata.name}')
kubectl delete pod -n shop $POD
wait $LOGS
```

```
{"event":"chaos","mode":"drain",…}
{"event":"signal_received","signal":"SIGTERM",…}
{"event":"request","status":200,"duration_ms":12.4}     ← in-flight requests still served
{"event":"shutdown","msg":"draining connections"}
{"event":"shutdown_complete"}
```

**Under load:**

```bash
hey -z 90s -q 40 -c 10 -host shop.example.com "http://$LB_IP/api/products" > py-rollout.txt &
HEY=$!
sleep 3
kubectl rollout restart deploy/shop-api -n shop
kubectl rollout status deploy/shop-api -n shop
wait $HEY
grep -A3 'Status code distribution' py-rollout.txt
```

**The failure modes:**

| Symptom | Cause | Fix |
|---|---|---|
| Pod takes exactly `terminationGracePeriodSeconds` to die | SIGTERM never reached Python | Shell-form CMD (`sh` is PID 1). Use exec form or `exec gunicorn …` |
| `WORKER TIMEOUT` in gunicorn logs | An endpoint exceeded `timeout` | Raise `GUNICORN_TIMEOUT`; find the slow endpoint |
| In-flight requests cut off | `graceful_timeout` < your slowest request | Raise it, but keep preStop + graceful < grace period |
| Workers killed mid-response on `max_requests` | Recycling during a request | Gunicorn handles this correctly — it finishes the request first. If not, check `max_requests` isn't tiny |
| DB connections leak on worker restart | `preload_app` + forked engine | `engine.dispose(close=False)` in `post_fork` (already done) |

> 🔑 **Never use `os._exit()` in a request handler**, and never `sys.exit()` from a signal handler in a threaded server — it raises `SystemExit` in an arbitrary thread. Gunicorn/Uvicorn handle this; if you write your own server, use `loop.stop()`.

---

## 11.7 Blocking the event loop — the FastAPI trap

```bash
kubectl port-forward -n shop svc/shop-api 8080:8080 &
sleep 2

# 1. Fire a BLOCKING async endpoint (await asyncio.sleep is fine, but a sync call inside
#    an `async def` is not). Our /api/products/blocking is a SYNC def → runs in a threadpool → OK.
for i in 1 2 3; do curl -s "localhost:8080/api/products/blocking?seconds=3" & done
curl -s -o /dev/null -w 'healthz during blocking: %{time_total}s\n' localhost:8080/healthz
# healthz during blocking: 0.004s     ✅ threadpool absorbed it

# 2. Now demonstrate the WRONG pattern — a sync call inside async def
kill %1
```

Add this to `main.py` to see the damage:

```python
@app.get("/api/products/bad-blocking", include_in_schema=False)
async def bad_blocking(seconds: float = 3.0):
    time.sleep(seconds)          # ⛔ blocks the ENTIRE event loop for this worker
    return {"slept": seconds}
```

```bash
curl -s "localhost:8080/api/products/bad-blocking?seconds=5" &
sleep 0.5
curl -s -o /dev/null -w 'healthz: %{time_total}s\n' localhost:8080/healthz
# healthz: 4.502311s      ← ⛔ the liveness probe just took 4.5s. Three of those = restart.
```

**The rules:**

| Situation | Do |
|---|---|
| I/O-bound (HTTP, DB, Redis) | `async def` + an async client (`httpx.AsyncClient`, `asyncpg`, `redis.asyncio`) |
| CPU-bound or a blocking library | Plain `def` — FastAPI runs it in a threadpool automatically |
| Must call a blocking library from `async def` | `await asyncio.to_thread(blocking_fn, arg)` or `run_in_executor` |
| Heavy CPU work (ML inference, image processing) | A separate Pod/Deployment, called over HTTP or a queue |

**Why this matters for Kubernetes specifically:** a blocked event loop means `/healthz` doesn't answer → liveness probe times out → **Kubernetes restarts a perfectly healthy Pod**, repeatedly. This is one of the most common causes of mystery `CrashLoopBackOff` in async Python apps.

```promql
# detect it: liveness probe failures with no app errors
increase(kube_pod_container_status_restarts_total{pod=~"shop-api.*"}[15m]) > 0
and
increase(container_cpu_cfs_throttled_periods_total{pod=~"shop-api.*"}[15m]) == 0
```

---

## 11.8 Extra Tasks

### Task 11.1 — Right-size the Python Pod with real measurements

Don't guess. Measure the worker count, memory, and CPU under load, then write the numbers into the manifest.

<details>
<summary>Show answer</summary>

**Step 1 — instrument the app to report what it knows.**

Add to `main.py`:

```python
import os, resource
from pathlib import Path

@app.get("/api/stats", include_in_schema=False)
async def stats() -> dict:
    def cgroup(path: str, default=None):
        p = Path(path)
        return p.read_text().strip() if p.exists() else default
    rss = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss // 1024          # MB, peak
    cur = int(cgroup("/sys/fs/cgroup/memory.current", 0)) // 1024 // 1024     # MB, current
    mx  = cgroup("/sys/fs/cgroup/memory.max", "max")
    cpu = cgroup("/sys/fs/cgroup/cpu.max", "max 100000")
    quota, period = (cpu.split() + ["100000"])[:2]
    cpus = "max" if quota == "max" else round(int(quota) / int(period), 2)
    # sum RSS across all gunicorn workers
    total_rss = 0
    for p in Path("/proc").iterdir():
        if p.name.isdigit():
            try:
                with open(p / "statm") as f:
                    total_rss += int(f.read().split()[1]) * 4096 // 1024 // 1024
            except (OSError, IndexError, ValueError):
                pass
    return {
        "pod": settings.pod_name,
        "workers": int(os.environ.get("WEB_CONCURRENCY", 1)),
        "container_cpu_limit": cpus,
        "container_memory_limit_mb": None if mx == "max" else int(mx) // 1024 // 1024,
        "cgroup_memory_current_mb": cur,
        "all_processes_rss_mb": total_rss,
        "this_process_peak_rss_mb": rss,
    }
```

**Step 2 — a matrix test.**

```bash
#!/usr/bin/env bash
# size-test.sh — measure throughput/latency/memory across worker counts
set -uo pipefail
NS=shop
LB_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
HOST=shop.example.com

printf '%-10s %-8s %-10s %-10s %-10s %-10s %-10s\n' \
  WORKERS CPU_LIM MEM_LIM RPS P50 P99 RSS_MB

for workers in 1 2 4 6 8; do
  for cpu in 500m 1 2; do
    kubectl patch deploy shop-api -n $NS --type=json -p="[
      {\"op\":\"replace\",\"path\":\"/spec/replicas\",\"value\":1},
      {\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/env/4/value\",\"value\":\"$workers\"},
      {\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/resources/limits/cpu\",\"value\":\"$cpu\"}
    ]" >/dev/null
    kubectl rollout status deploy/shop-api -n $NS --timeout=180s >/dev/null
    sleep 20    # let it warm up

    R=$(hey -z 60s -c 20 -q 40 -host $HOST "http://$LB_IP/api/products?limit=10" 2>/dev/null)
    RPS=$(echo "$R" | awk '/Requests\/sec/{print $2}')
    P50=$(echo "$R" | awk '/^  50%/{print $3}')
    P99=$(echo "$R" | awk '/^  99%/{print $3}')
    ERRS=$(echo "$R" | grep -A5 'Status code distribution' | grep -cE '\[(4|5)' || true)

    STATS=$(kubectl exec -n $NS deploy/shop-api -- curl -s localhost:8080/api/stats)
    RSS=$(echo "$STATS" | jq -r '.all_processes_rss_mb')

    MEM_LIM=$(kubectl get deploy shop-api -n $NS -o jsonpath='{.spec.template.spec.containers[0].resources.limits.memory}')
    printf '%-10s %-8s %-10s %-10s %-10s %-10s %-10s %s\n' \
      "$workers" "$cpu" "$MEM_LIM" "$RPS" "$P50" "$P99" "$RSS" "$([ "$ERRS" -gt 0 ] && echo "⚠️ $ERRS error codes")"
  done
done
```

Typical output for a FastAPI + Postgres app:

```
WORKERS  CPU_LIM  MEM_LIM    RPS        P50        P99        RSS_MB
1        500m     768Mi      212.4      0.0180     0.0910     98
2        500m     768Mi      298.1      0.0210     0.1240     164      ← best per-CPU
4        500m     768Mi      271.6      0.0380     0.4100     288      ⚠️ throttled
1        1        768Mi      390.2      0.0140     0.0680     98
2        1        768Mi      585.7      0.0160     0.0740     164      ← sweet spot
4        1        768Mi      612.3      0.0190     0.0910     288
6        1        768Mi      598.0      0.0260     0.2100     412      ⚠️ near limit
8        1        768Mi      561.2      0.0340     0.5200     540      ⚠️ OOMKilled at peak
1        2        768Mi      402.1      0.0140     0.0660     98
2        2        768Mi      598.4      0.0160     0.0720     164
4        2        768Mi      920.6      0.0170     0.0810     288      ← best absolute
8        2        768Mi      1042.3     0.0210     0.1100     540      ⚠️ memory-bound, not CPU
```

**Read it:**
- At `cpu=500m`, 2 workers is the ceiling — more workers just thrash and throttle.
- At `cpu=1`, 2–4 workers; 6+ costs memory and buys nothing.
- At `cpu=2`, 4–8 workers, but **memory becomes the binding constraint** at 6+.
- RPS per worker drops as workers increase (contention) but total RPS rises — up to a point.

**Step 3 — check throttling explicitly.**

```promql
sum by (pod) (rate(container_cpu_cfs_throttled_periods_total{pod=~"shop-api.*"}[5m]))
/ sum by (pod) (rate(container_cpu_cfs_periods_total{pod=~"shop-api.*"}[5m]))
```

Anything above 0.10 sustained is costing you latency.

**Step 4 — write the answer into the manifest.**

```yaml
# chosen: 4 workers, 2 CPU, 768Mi  →  920 rps, p99 81ms, 288MB RSS (37% of limit)
resources:
  requests: {cpu: "1",   memory: 512Mi}     # typical steady state
  limits:   {cpu: "2",   memory: 768Mi}     # peak + 2.5× headroom
env:
  - {name: WEB_CONCURRENCY, value: "4"}
```

**Step 5 — the scaling math.**

```
target RPS       = 5,000
RPS per pod      = 920  (at p99 < 100ms)
pods needed      = ceil(5000 / 920) = 6
+ 25% headroom   = 8
HPA: minReplicas = 4, maxReplicas = 20, target = 65% CPU
```

And the HPA target should be verified too:

```bash
kubectl get hpa -n shop
kubectl describe hpa shop-api -n shop | grep -A5 Targets
# cpu: 412m/1 (65%) → desired 8   ← matches our math ✅
```

**Step 6 — set up the guard rails so it can't drift.**

```yaml
- alert: PythonWorkerMemoryHigh
  expr: |
    sum by (pod) (container_memory_working_set_bytes{pod=~"shop-api.*"})
    / on(pod) kube_pod_container_resource_limits{resource="memory",pod=~"shop-api.*"} > 0.85
  for: 10m
  labels: {severity: warning}
  annotations:
    summary: "{{ $labels.pod }} at {{ $value | humanizePercentage }} of its memory limit"
    description: "Reduce WEB_CONCURRENCY or raise limits.memory. Check /api/stats."
```

</details>

---

### Task 11.2 — Handle a Postgres failover without dropping requests

The DB Pod is deleted and rescheduled. The API must survive it.

<details>
<summary>Show answer</summary>

**First, watch it fail.**

```bash
kubectl run load -n shop --rm -it --image=nicolaka/netshoot --restart=Never -- \
  sh -c 'while true; do curl -s -o /dev/null -w "%{http_code} " http://shop-api:8080/api/products; sleep 0.3; done'
```

In another terminal:

```bash
kubectl delete pod -n shop db-0
```

```
200 200 200 500 500 500 500 500 500 500 500 200 200 200
        └──── ~15-40s of 500s ────┘
```

```bash
kubectl logs -n shop deploy/shop-api --tail=50 | jq -r 'select(.level=="error") | .error' | head
# psycopg2.OperationalError: server closed the connection unexpectedly
# sqlalchemy.exc.OperationalError: (psycopg2.OperationalError) connection already closed
```

**Four problems to fix:**

### 1. Stale pooled connections

SQLAlchemy's pool holds sockets to a Postgres that no longer exists. `pool_pre_ping=True` tests each connection before handing it out:

```python
engine = create_engine(
    url,
    pool_pre_ping=True,       # ⭐ SELECT 1 before each checkout — costs ~0.3ms
    pool_recycle=1800,        # recycle connections older than 30 min
    pool_size=15,
    max_overflow=5,
    pool_timeout=5,           # ⭐ fail fast instead of hanging forever
)
```

Without `pool_pre_ping` you get `InterfaceError: connection already closed` on the first request after a failover, every time.

### 2. Retries with backoff

```python
from sqlalchemy.exc import DBAPIError, OperationalError
from tenacity import (retry, retry_if_exception_type, stop_after_attempt,
                      wait_exponential_jitter, before_sleep_log)

RETRYABLE = (OperationalError, DBAPIError)

@retry(
    retry=retry_if_exception_type(RETRYABLE),
    stop=stop_after_attempt(4),
    wait=wait_exponential_jitter(initial=0.2, max=5, jitter=0.5),
    reraise=True,
    before_sleep=before_sleep_log(log, "WARNING"),
)
def list_products(db: Session, q: str | None, limit: int, offset: int):
    query = db.query(Product)
    if q:
        query = query.filter(Product.name.ilike(f"%{q}%"))
    return query.order_by(Product.id).offset(offset).limit(limit).all()
```

⚠️ **Only retry idempotent operations.** A `POST` that creates a row must not be retried blindly — use an idempotency key:

```python
@app.post("/api/orders")
async def create_order(payload: OrderCreate, request: Request, db: Session = Depends(get_db)):
    idem = request.headers.get("idempotency-key")
    if idem and (existing := db.query(Order).filter_by(idempotency_key=idem).one_or_none()):
        return existing.to_dict()                     # safe replay
    ...
```

### 3. A circuit breaker so a dead DB doesn't cascade

```python
# pip install pybreaker
import pybreaker

db_breaker = pybreaker.CircuitBreaker(
    fail_max=5,                 # 5 consecutive failures → open
    reset_timeout=15,           # try again after 15s
    exclude_exceptions=[HTTPException],   # 404s aren't DB failures
    state_change_callback=lambda s, prev: log.warning("breaker", state=s.current_state, previous=prev),
)

@db_breaker
def _query_products(db: Session, q: str | None):
    ...

@app.get("/api/products")
async def list_products(q: str | None = None, db: Session = Depends(get_db)):
    try:
        return await asyncio.to_thread(_query_products, db, q)
    except pybreaker.CircuitBreakerError:
        log.error("circuit_open", endpoint="/api/products")
        raise HTTPException(503, detail="database unavailable",
                            headers={"Retry-After": "15"})
```

Returning **503 with `Retry-After`** is correct behaviour: it tells the client (and the load balancer) to back off, and it keeps the request cheap instead of hanging for 30 s.

### 4. Readiness must reflect it

```python
@app.get("/readyz")
async def readiness():
    if state["draining"]:
        return Response("draining\n", 503)
    if db_breaker.current_state == "open":          # ⭐ don't take traffic we can't serve
        return Response("circuit open\n", 503)
    try:
        await asyncio.wait_for(asyncio.to_thread(_check_db), timeout=2.0)
    except Exception as exc:
        return Response(f"db error\n", 503)
    return Response("ready\n", 200)
```

Now when the DB dies, **all API Pods go NotReady within ~10 s**, the Service has no endpoints, and the Ingress returns 503 cleanly (instead of a 30-second hang followed by a 500). Clients with retries succeed the moment the DB is back.

### 5. And the platform side

```bash
# the DB shouldn't take 30s to come back either
kubectl get sts db -n shop -o jsonpath='{.spec.template.spec.terminationGracePeriodSeconds}'; echo
kubectl describe pod db-0 -n shop | grep -A3 Readiness
```

```yaml
# Postgres: fast readiness detection so the API sees recovery quickly
readinessProbe:
  exec: {command: ["sh","-c","pg_isready -U $POSTGRES_USER -h 127.0.0.1 -t 1"]}
  periodSeconds: 5          # not 30
  failureThreshold: 2
  timeoutSeconds: 3
```

For real HA, don't do any of this by hand — **CloudNativePG** does leader election, automatic failover in ~10 s, and connection-pool-aware readiness:

```bash
helm install cnpg cnpg/cloudnative-pg -n cnpg-system --create-namespace
```

**Retest:**

```bash
kubectl rollout restart deploy/shop-api -n shop && kubectl rollout status deploy/shop-api -n shop
kubectl run load -n shop --rm -it --image=nicolaka/netshoot --restart=Never -- \
  sh -c 'ok=0; bad=0; while true; do
    c=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://shop-api:8080/api/products);
    [ "$c" = 200 ] && ok=$((ok+1)) || bad=$((bad+1));
    echo "$(date +%T) $c  ok=$ok bad=$bad"; sleep 0.3; done' &
LOAD=$!
sleep 10
kubectl delete pod -n shop db-0
sleep 60
kill $LOAD
```

```
14:22:01 200 ok=31 bad=0
14:22:15 503 ok=72 bad=1     ← circuit open, fast failure instead of a hang
14:22:16 503 ok=72 bad=4
14:22:38 200 ok=145 bad=12   ← recovered
```

**12 fast 503s instead of 40 slow 500s.** That's the improvement. The client can retry a 503; it can't do much with a 30-second hang.

</details>

---

### Task 11.3 — Run a Python worker that consumes a queue (non-HTTP workload)

A Deployment with no Service, no Ingress, scaling on queue depth.

<details>
<summary>Show answer</summary>

HTTP probes don't apply. You need a **liveness signal that means "the consumer loop is alive"**, not "an HTTP server is up".

`api/app/worker.py`:

```python
"""Redis queue consumer. Designed to run as a Deployment with no Service."""
import json
import os
import signal
import time
from datetime import datetime, timezone

import redis
import structlog

from .config import get_settings
from .logging_conf import configure_logging

configure_logging()
log = structlog.get_logger("worker")
settings = get_settings()

QUEUE = os.environ.get("QUEUE_NAME", "work:queue")
DONE = os.environ.get("DONE_QUEUE", "work:done")
DEAD = os.environ.get("DEAD_QUEUE", "work:dead")
HEARTBEAT_FILE = "/tmp/heartbeat"
VISIBILITY_TIMEOUT = 300

shutdown = False


def handle_sig(signum, _frame):
    global shutdown
    log.info("signal", signal=signal.Signals(signum).name)
    shutdown = True


signal.signal(signal.SIGTERM, handle_sig)
signal.signal(signal.SIGINT, handle_sig)


def beat():
    """Touch a file so the liveness probe can see we're alive."""
    with open(HEARTBEAT_FILE, "w", encoding="utf-8") as f:
        f.write(str(time.time()))


def main():
    r = redis.Redis.from_url(
        os.environ.get("REDIS_URL", "redis://redis:6379/0"),
        socket_timeout=10, socket_connect_timeout=10, socket_keepalive=True,
        health_check_interval=30, retry_on_timeout=True,
    )
    log.info("worker_start", queue=QUEUE, pod=settings.pod_name)
    processed = failed = 0

    while not shutdown:
        try:
            item = r.brpop(QUEUE, timeout=5)         # ⭐ blocking pop with a timeout
            beat()                                    # alive even when idle
            if item is None:
                continue
            _, raw = item
            payload = json.loads(raw)
            log.info("item_start", id=payload.get("id"))
            t0 = time.perf_counter()
            try:
                process(payload, r)
                r.lpush(DONE, raw)
                processed += 1
                log.info("item_done", id=payload.get("id"),
                         ms=round((time.perf_counter() - t0) * 1000, 1))
            except Exception as exc:
                failed += 1
                payload["_error"] = f"{exc.__class__.__name__}: {exc}"
                payload["_attempts"] = payload.get("_attempts", 0) + 1
                if payload["_attempts"] >= 3:
                    r.lpush(DEAD, json.dumps(payload))
                    log.error("item_dead", id=payload.get("id"), error=payload["_error"])
                else:
                    r.lpush(QUEUE, json.dumps(payload))     # requeue for another worker
                    log.warning("item_requeued", id=payload.get("id"),
                                attempts=payload["_attempts"])
        except redis.exceptions.ConnectionError as exc:
            log.error("redis_connection_error", error=str(exc))
            beat()
            time.sleep(5)                                   # back off, don't spin
        except Exception:
            log.exception("worker_loop_error")
            beat()
            time.sleep(1)

    log.info("worker_shutdown", processed=processed, failed=failed)


def process(payload: dict, r) -> None:
    """The actual work. Raise to trigger a requeue."""
    time.sleep(0.2)
    r.incr(f"stats:processed:{datetime.now(timezone.utc).strftime('%Y%m%d')}")


if __name__ == "__main__":
    main()
```

`k8s/worker.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: shop-worker
  namespace: shop
  labels: {app: shop-worker}
spec:
  replicas: 3
  selector: {matchLabels: {app: shop-worker}}
  template:
    metadata: {labels: {app: shop-worker}}
    spec:
      terminationGracePeriodSeconds: 90      # ⭐ long enough for the slowest item
      securityContext:
        runAsNonRoot: true
        runAsUser: 10001
        seccompProfile: {type: RuntimeDefault}
      containers:
        - name: worker
          image: ghcr.io/3558bhk/shop-api-py:1.0.0
          command: ["python", "-m", "app.worker"]     # ⭐ exec form; no Service, no HTTP
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities: {drop: ["ALL"]}
          env:
            - {name: QUEUE_NAME, value: "work:queue"}
            - {name: REDIS_URL,  value: "redis://redis.shop.svc.cluster.local:6379/0"}
            - {name: LOG_LEVEL,  value: "INFO"}
            - {name: POD_NAME,   valueFrom: {fieldRef: {fieldPath: metadata.name}}}
          resources:
            requests: {cpu: 200m, memory: 256Mi}
            limits:   {cpu: "1",   memory: 512Mi}

          # ⭐ LIVENESS = "is the consumer loop still ticking?"
          #    The heartbeat file is touched every loop iteration (≤5s).
          #    If the process deadlocks, the file stops updating → restart.
          livenessProbe:
            exec:
              command:
                - sh
                - -c
                - |
                  test -f /tmp/heartbeat || exit 1
                  AGE=$(( $(date +%s) - $(cut -d. -f1 /tmp/heartbeat) ))
                  [ "$AGE" -lt 60 ] || { echo "heartbeat stale: ${AGE}s"; exit 1; }
            periodSeconds: 20
            timeoutSeconds: 5
            failureThreshold: 3
            initialDelaySeconds: 30

          # ⭐ READINESS = "may this worker take more items?"
          #    False when draining, when Redis is unreachable, or when overloaded.
          readinessProbe:
            exec:
              command:
                - sh
                - -c
                - |
                  test -f /tmp/ready || exit 1          # worker writes this when healthy
                  grep -q draining /tmp/state && exit 1
            periodSeconds: 10
            failureThreshold: 2

          lifecycle:
            preStop:
              exec:
                command: ["/bin/sh", "-c", "echo draining > /tmp/state; sleep 5"]
          volumeMounts:
            - {name: tmp, mountPath: /tmp}
      volumes:
        - {name: tmp, emptyDir: {sizeLimit: 64Mi}}
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata: {name: shop-worker, namespace: shop}
spec:
  maxUnavailable: 1
  selector: {matchLabels: {app: shop-worker}}
```

**Scaling on queue depth** — HPA on CPU is useless for a worker (CPU tracks consumer count, not backlog). Use KEDA:

```yaml
apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata: {name: redis-trigger, namespace: shop}
spec:
  secretTargetRef:
    - parameter: address
      name: redis-creds
      key: url
---
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata: {name: shop-worker, namespace: shop}
spec:
  scaleTargetRef: {name: shop-worker}
  pollingInterval: 15
  cooldownPeriod: 300
  minReplicaCount: 1              # ⭐ KEDA can go to 0; keep 1 if items must not wait
  maxReplicaCount: 50
  advanced:
    horizontalPodAutoscalerConfig:
      behavior:
        scaleUp:
          stabilizationWindowSeconds: 0
          policies: [{type: Percent, value: 200, periodSeconds: 30}]
        scaleDown:
          stabilizationWindowSeconds: 300
          policies: [{type: Pods, value: 1, periodSeconds: 60}]
  triggers:
    - type: redis-lists
      metadata:
        addressFromEnv: REDIS_URL
        listName: work:queue
        listLength: "50"          # ⭐ target: 50 items per worker
        activationListLength: "5" # don't scale up from 0 until 5 items exist
```

```bash
helm repo add kedacore https://kedacore.github.io/charts
helm install keda kedacore/keda -n keda --create-namespace
kubectl apply -f k8s/worker.yaml -f k8s/scaledobject.yaml

# seed the queue and watch it scale
kubectl run seed -n shop --rm -i --restart=Never --image=redis:7-alpine -- sh -c '
  for i in $(seq 1 5000); do
    redis-cli -h redis lpush work:queue "{\"id\":$i}" >/dev/null
  done
  redis-cli -h redis llen work:queue'

kubectl get scaledobject,hpa,pods -n shop -l app=shop-worker -w
```

```
NAME                                    TARGETS       MINPODS MAXPODS REPLICAS
horizontalpodautoscaler/keda-hpa-shop-worker  4200/50   1       50      1 → 8 → 50
```

**Worker-specific gotchas:**

| Problem | Cause | Fix |
|---|---|---|
| Items processed twice | Pod killed mid-item; the item was already popped | Use `BRPOPLPUSH`/`LMOVE` into a processing list, and requeue on startup; or a real broker (RabbitMQ/SQS/Kafka) with acks |
| Items lost on crash | `BRPOP` removes from the queue immediately | Same: `LMOVE` to an in-flight list, `LREM` on success |
| Grace period too short | `SIGTERM` during a 5-minute item | `terminationGracePeriodSeconds` > max item time |
| Scale-down kills an active worker | HPA doesn't know about in-flight work | PDB + a `preStop` that finishes the current item, and KEDA's `cooldownPeriod` |
| One poison item blocks the queue forever | Infinite requeue | Max attempts → dead-letter queue |
| Idle workers cost money | `minReplicaCount: 3` | KEDA can scale to **0** |
| No `/healthz` to probe | It's not an HTTP server | Heartbeat file + exec probe, or a tiny sidecar HTTP server |

**The heartbeat alternative** — a metrics sidecar that also gives you an HTTP probe:

```yaml
      containers:
        - name: worker
          # … as above, plus expose stats on a unix socket or write to /tmp/stats.json
        - name: stats                    # tiny exporter
          image: python:3.13-alpine
          command: ["python","-c"]
          args:
            - |
              import http.server, json, pathlib, time
              class H(http.server.BaseHTTPRequestHandler):
                  def do_GET(s):
                      try:
                          hb = float(pathlib.Path('/tmp/heartbeat').read_text())
                          age = time.time() - hb
                          if s.path == '/healthz':
                              code, body = (200, 'ok') if age < 60 else (500, f'stale {age:.0f}s')
                          else:
                              code, body = 200, json.dumps({'heartbeat_age_seconds': age})
                      except FileNotFoundError:
                          code, body = 500, 'no heartbeat'
                      s.send_response(code); s.end_headers(); s.wfile.write(body.encode())
                  def log_message(s, *a): pass
              http.server.HTTPServer(('0.0.0.0', 9090), H).serve_forever()
          ports: [{name: stats, containerPort: 9090}]
          volumeMounts: [{name: tmp, mountPath: /tmp, readOnly: true}]
```

Now `livenessProbe: {httpGet: {path: /healthz, port: stats}}` works, and you get metrics for free.

</details>

---

### Task 11.4 — Build the smallest safe Python image

Get from 410 MB (`python:3.13-slim` + deps) to under 100 MB without breaking anything.

<details>
<summary>Show answer</summary>

**Measure the starting point:**

```bash
docker history shop-api-py:prod --format 'table {{.CreatedBy}}\t{{.Size}}' | head -25
docker run --rm shop-api-py:prod du -sh /usr/local/lib/python3.13/site-packages/* 2>/dev/null \
  | sort -h | tail -15
```

**The levers, in order of payoff:**

### 1. Drop the build toolchain (biggest single win)

```dockerfile
FROM python:3.13-slim AS builder
RUN apt-get update && apt-get install -y --no-install-recommends build-essential libpq-dev
COPY requirements.txt .
RUN pip wheel --wheel-dir /wheels -r requirements.txt

FROM python:3.13-slim AS runtime
RUN apt-get update && apt-get install -y --no-install-recommends libpq5 tini curl   # runtime ONLY
COPY --from=builder /wheels /wheels
RUN pip install --no-index --find-links=/wheels /wheels/* && rm -rf /wheels
```

`libpq-dev` (headers, ~40 MB) → `libpq5` (runtime, ~4 MB). `build-essential` (~250 MB) → gone.

### 2. Use binary wheels, never compile

```dockerfile
RUN pip install --only-binary=:all: -r requirements.txt
```

If this fails, some package has no wheel → either swap it (`psycopg2-binary` → `psycopg[binary]` v3, which ships wheels and is faster) or accept the builder stage for that one package.

### 3. Strip Python itself

```dockerfile
RUN find /usr/local/lib/python3.13 -depth \( -name '__pycache__' -o -name 'test' -o -name 'tests' \
        -o -name 'idlelib' -o -name 'tkinter' -o -name 'ensurepip' -o -name 'lib2to3' \) \
      -exec rm -rf {} + 2>/dev/null || true \
 && find /usr/local/lib/python3.13 -name '*.pyc' -delete \
 && find /usr/local/lib/python3.13 -name '*.pyo' -delete \
 && rm -rf /usr/local/lib/python3.13/site-packages/pip \
           /usr/local/lib/python3.13/site-packages/setuptools \
           /usr/local/bin/pip* /usr/local/bin/2to3* /usr/local/bin/idle*
```

Saves ~25–40 MB. `PYTHONDONTWRITEBYTECODE=1` keeps `.pyc` from being regenerated.

### 4. Strip the installed packages

```dockerfile
RUN find /usr/local/lib/python3.13/site-packages -depth \
      \( -name 'tests' -o -name 'test' -o -name '*.dist-info' -o -name 'py.typed' \
         -o -name '*.pyx' -o -name '*.pxd' \) -exec rm -rf {} + 2>/dev/null || true \
 && find /usr/local/lib/python3.13/site-packages -name '*.so' -exec strip --strip-unneeded {} + 2>/dev/null || true
```

⚠️ **Don't delete `*.dist-info` if you use `importlib.metadata`** (FastAPI, Pydantic and many others do for version detection). Delete only `RECORD` and `*.dist-info/*/tests`.

### 5. Drop unused heavy dependencies

```bash
docker run --rm shop-api-py:prod du -sh /usr/local/lib/python3.13/site-packages/* | sort -h | tail -20
```

Typical offenders and their replacements:

| Package | Size | Alternative |
|---|---|---|
| `pandas` | 60 MB | `polars` (smaller, faster) or plain SQL |
| `numpy` | 40 MB | Often only needed by pandas |
| `psycopg2-binary` | 12 MB | `psycopg[binary]` v3 (~8 MB, faster) |
| `pydantic v1` + `email-validator` | 15 MB | Pydantic v2 (Rust core, already smaller) |
| `uvicorn[standard]` | 20 MB | `uvicorn` + only the extras you use (`--no-deps` then add `httptools`, `uvloop`) |
| `pillow` | 12 MB | Needed only if you process images |
| `cryptography` | 15 MB | Often pulled in transitively — check if you need it |
| `boto3` + `botocore` | **90 MB** | `aioboto3` is no smaller; use direct HTTP to S3, or `minio-py` (2 MB) |

```bash
# find what pulls in botocore
pip install pipdeptree && pipdeptree -r -p botocore
```

### 6. Distroless (the extreme)

```dockerfile
FROM gcr.io/distroless/python3-debian12:nonroot AS runtime
COPY --from=builder /usr/local/lib/python3.13/site-packages /usr/local/lib/python3.13/site-packages
COPY --chown=nonroot:nonroot . /app
WORKDIR /app
ENV PYTHONPATH=/usr/local/lib/python3.13/site-packages
USER nonroot
ENTRYPOINT ["python", "-m", "gunicorn", "-c", "gunicorn_conf.py", "app.main:app"]
```

~90 MB, no shell, no package manager, tiny attack surface.

**Costs:** no `sh` (so no `kubectl exec` debugging), no `curl` (so exec probes and preStop hooks must use Python), no `tini` (distroless has its own init if you use `--entrypoint` carefully).

The `preStop` hook must change:

```yaml
lifecycle:
  preStop:
    exec:
      command: ["python", "-c", "import urllib.request,time; urllib.request.urlopen(urllib.request.Request('http://localhost:8080/api/chaos/drain', method='POST'), timeout=2); time.sleep(8)"]
```

And liveness/readiness must be `httpGet` (which the kubelet does itself — no shell needed).

### 7. Alpine — usually a **bad** idea for Python

```dockerfile
FROM python:3.13-alpine
RUN pip install pandas psycopg2    # ⛔ compiles from source: 8+ minutes, needs gcc/musl-dev/openblas-dev
```

| | slim (Debian/glibc) | alpine (musl) |
|---|---|---|
| Base size | 130 MB | 55 MB |
| With numpy/pandas | +60 MB, wheels work | +400 MB of build deps, compiles for 10 min |
| Final image | ~185 MB | ~350 MB (if it builds at all) |
| Runtime bugs | Rare | musl DNS quirks, thread-stack differences, slower `malloc` |

**Alpine only wins if your dependencies are pure Python.** For a web API with a DB driver, `slim` is smaller *and* more reliable.

**Results:**

```bash
docker images | grep shop-api-py
# shop-api-py   simple       410MB
# shop-api-py   prod         185MB   ← step 1-4
# shop-api-py   lean         142MB   ← + step 5 (dropped boto3, pandas)
# shop-api-py   distroless    94MB   ← + step 6
# shop-api-py   alpine       338MB   ← ⛔ "smaller base" made it BIGGER
```

**Verify nothing broke:**

```bash
docker run --rm shop-api-py:distroless python -c "
import fastapi, uvicorn, gunicorn, sqlalchemy, psycopg2, pydantic, prometheus_fastapi_instrumentator
print('all imports ok')
print('pydantic', pydantic.VERSION)
"
docker run --rm -p 8080:8080 shop-api-py:distroless &
sleep 8
curl -s localhost:8080/healthz
curl -s localhost:8080/openapi.json | jq '.paths | keys'
kill %1
```

**And scan it:**

```bash
trivy image --severity CRITICAL,HIGH --ignore-unfixed shop-api-py:distroless
# distroless typically reports 0-2 vulnerabilities vs 40+ for slim
```

</details>

---

### Task 11.5 — Debug a Python Pod that's OOMKilled but whose app looks fine

<details>
<summary>Show answer</summary>

**Step 1 — Confirm and characterise.**

```bash
POD=$(kubectl get pod -n shop -l app=shop-api -o jsonpath='{.items[?(@.status.containerStatuses[0].lastState.terminated.reason=="OOMKilled")].metadata.name}')
kubectl describe pod -n shop $POD | grep -B2 -A8 "Last State"
# Reason: OOMKilled   Exit Code: 137
kubectl get pod -n shop $POD -o jsonpath='{.status.containerStatuses[0].restartCount}'; echo
```

Three distinct flavours of Python OOM — tell them apart first:

| Flavour | Signature | Meaning |
|---|---|---|
| **A. Steady creep** | Restarts every ~6–24 h, memory graph climbs linearly | A real leak (caches, listeners, unclosed sessions) |
| **B. Spike** | Restarts under load, memory graph is spiky | A request allocates hugely (loading a big file, `SELECT *` with no LIMIT) |
| **C. Startup** | OOMKilled within seconds, never Ready | Too many workers for the limit; `preload_app` off; heavy imports |

```promql
# A vs B: look at the shape
container_memory_working_set_bytes{pod=~"shop-api.*"}
# A: a straight line up, sawtooth only at restarts
# B: flat with tall spikes
# C: never gets off the ground
```

**Step 2 — Flavour C first (the easy one).**

```bash
kubectl exec -n shop deploy/shop-api -- python -c "
from gunicorn_conf import CPUS, WORKERS
print('container CPUs:', CPUS, '→ workers:', WORKERS)"
kubectl exec -n shop deploy/shop-api -- sh -c 'ps -eo pid,rss,cmd --sort=-rss | head -12'
```

```
container CPUs: 2.0 → workers: 4
   PID   RSS   CMD
     1  4180   /usr/bin/tini -- gunicorn …
    21 91204   gunicorn: worker        ← 89 Mi
    22 91180   gunicorn: worker
    23 91300   gunicorn: worker
    24 91150   gunicorn: worker
                        total ≈ 360 Mi
```

`limits.memory: 256Mi` with 4 workers at 90 Mi each → **guaranteed OOMKill at startup**. Fix:

```bash
kubectl patch deploy shop-api -n shop --type=json -p='[
  {"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/memory","value":"768Mi"}]'
# or reduce workers
kubectl patch cm shop-api-config -n shop --type=merge -p '{"data":{"WEB_CONCURRENCY":"2"}}'
kubectl rollout restart deploy/shop-api -n shop
```

Also check `preload_app`: with `preload_app=false`, each worker imports the whole app separately (~2× memory). With `true`, they fork from a shared image (copy-on-write).

**Step 3 — Flavour B: find the request that allocates.**

```bash
# correlate the spike with access logs
kubectl logs -n shop deploy/shop-api --since=1h | jq -r '
  select(.event=="request") | "\(.duration_ms)\t\(.status)\t\(.method) \(.path)"' \
  | sort -rn | head -20
```

The usual suspects:

```python
# ⛔ SELECT * with no LIMIT — 2M rows into memory
products = db.query(Product).all()
# ✅
products = db.query(Product).limit(100).all()

# ⛔ reading an uploaded file fully
data = await file.read()                     # a 2 GB upload = 2 GB of RAM
# ✅ stream it
with open(dest, "wb") as out:
    while chunk := await file.read(1024 * 1024):
        out.write(chunk)

# ⛔ building a huge JSON response
return {"rows": [r.to_dict() for r in db.query(Product).all()]}
# ✅ paginate, or use StreamingResponse

# ⛔ pandas read_csv on a huge file
df = pd.read_csv(path)
# ✅ chunked
for chunk in pd.read_csv(path, chunksize=50_000): process(chunk)
```

Add a guard at the framework level:

```yaml
# Ingress: cap the request body so a huge upload can't reach the app
nginx.ingress.kubernetes.io/proxy-body-size: "10m"
```

```python
# App: cap result sets
MAX_LIMIT = 200
limit: int = Query(default=50, ge=1, le=MAX_LIMIT)
```

**Step 4 — Flavour A: find the leak.**

Enable `tracemalloc` behind a flag:

```python
# app/debug.py
import tracemalloc, os
_snapshots = []

def maybe_start():
    if os.environ.get("TRACEMALLOC", "").lower() in ("1", "true"):
        tracemalloc.start(25)

def top(n=20):
    snap = tracemalloc.take_snapshot()
    if _snapshots:
        stats = snap.compare_to(_snapshots[-1], "lineno")
    else:
        stats = snap.statistics("lineno")
    _snapshots.append(snap)
    return [{"file": str(s.traceback), "size_diff_kb": s.size_diff // 1024,
             "count_diff": s.count_diff} for s in stats[:n]]
```

```python
@app.post("/api/debug/snapshot", include_in_schema=False)
async def snapshot():
    from . import debug
    return debug.top(25)
```

```bash
kubectl set env deploy/shop-api -n shop TRACEMALLOC=true
kubectl rollout status deploy/shop-api -n shop
# hit the app for a while, then:
curl -s -XPOST localhost:8080/api/debug/snapshot | jq '.[] | select(.size_diff_kb > 100)'
```

```json
[
  {"file":"app/cache.py:34",      "size_diff_kb": 48210, "count_diff": 1204},
  {"file":"sqlalchemy/pool/…:88", "size_diff_kb":  9120, "count_diff":  312}
]
```

**The classic Python leaks in a web app:**

| Leak | Pattern | Fix |
|---|---|---|
| Unbounded module-level cache | `_cache = {}` growing forever | `functools.lru_cache(maxsize=…)` or a TTL cache (`cachetools.TTLCache`) |
| SQLAlchemy sessions never closed | `SessionLocal()` without a `finally: db.close()` | Use the FastAPI dependency (`Depends(get_db)`) — it always closes |
| `expire_on_commit=True` holding object graphs | Detached objects keep references | `expire_on_commit=False` |
| Event listeners registered per request | `event.listen(...)` inside a handler | Register once at import time |
| `contextvars` / `structlog.contextvars` never cleared | Bound context accumulates | `clear_contextvars()` per request (done in the middleware above) |
| Global lists for metrics | `HISTORY.append(...)` | A ring buffer (`collections.deque(maxlen=1000)`) |
| Open file handles / HTTP clients | `httpx.Client()` per request | One module-level client, or `async with` |
| Circular references + `__del__` | GC can't collect | Break the cycle; avoid `__del__` |

**Step 5 — the pragmatic mitigation while you hunt.**

```python
# gunicorn_conf.py — recycle workers before they grow into the limit
max_requests = 1000              # tighter while debugging
max_requests_jitter = 100
```

```yaml
# and cap the memory so a leak fails fast and loud instead of taking the node down
resources:
  requests: {memory: 512Mi}
  limits:   {memory: 768Mi}
```

```bash
# watch the sawtooth: memory climbs, worker recycles, memory drops
kubectl get pods -n shop -l app=shop-api -o jsonpath='{.items[0].status.containerStatuses[0].restartCount}'; echo
kubectl exec -n shop deploy/shop-api -- sh -c 'while true; do ps -eo rss,cmd | grep -c gunicorn; sleep 5; done'
```

**Step 6 — memray for a real flame graph.**

```bash
kubectl debug -n shop deploy/shop-api --image=shop-api-py:debug --target=api --share-processes
# (a debug image with memray installed and SYS_PTRACE)
memray attach --aggregate -o /tmp/live.bin <worker-pid>
sleep 300
memray flamegraph -o /tmp/flame.html /tmp/live.bin
kubectl cp shop/$POD:/tmp/flame.html ./flame.html -c api
```

**Step 7 — alert so you find out before users do.**

```yaml
- alert: PythonMemoryCreep
  expr: |
    deriv(container_memory_working_set_bytes{pod=~"shop-api.*"}[30m]) > 0
    and
    container_memory_working_set_bytes{pod=~"shop-api.*"}
      / on(pod) kube_pod_container_resource_limits{resource="memory",pod=~"shop-api.*"} > 0.75
  for: 20m
  labels: {severity: warning}
  annotations:
    summary: "{{ $labels.pod }} memory is climbing and above 75% of its limit"
    description: "deriv > 0 means it is still growing. Expect an OOMKill soon. Check /api/debug/snapshot."
```

</details>

---

## 11.9 Checklist

- [ ] Explain why `python:slim` beats `python:alpine` for real dependencies
- [ ] Write a multi-stage build with a wheel-builder stage and no compiler in the runtime
- [ ] Size gunicorn workers from the **cgroup** CPU limit, not `os.cpu_count()`
- [ ] Explain the GIL's effect on scaling and why workers = processes
- [ ] Cap BLAS/OpenMP threads so numpy doesn't oversubscribe the CPU
- [ ] Explain why Python RSS never shrinks and name four mitigations
- [ ] Distinguish `memory.current`, `working_set_bytes`, and `ru_maxrss`
- [ ] Configure `preStop` + `graceful_timeout` + `terminationGracePeriodSeconds` coherently
- [ ] Use exec-form ENTRYPOINT with tini so SIGTERM reaches Python
- [ ] Explain how blocking the event loop causes mystery Pod restarts
- [ ] Use `pool_pre_ping`, retries, and a circuit breaker to survive a DB failover
- [ ] Write liveness/readiness exec probes for a non-HTTP worker with a heartbeat file
- [ ] Scale a queue worker with KEDA on queue depth
- [ ] Find a Python memory leak with tracemalloc / memray

**Next → [`15-PROJECT-12-react-go-fullstack.md`](15-PROJECT-12-react-go-fullstack.md)** — Go: tiny images, `FROM scratch`, and the easiest runtime to run on Kubernetes.

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish%20Kumar%20Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn → <https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260>
🐙 GitHub → <https://github.com/3558Bhk>

*Built for engineers who learn by breaking things on purpose.*

</div>
