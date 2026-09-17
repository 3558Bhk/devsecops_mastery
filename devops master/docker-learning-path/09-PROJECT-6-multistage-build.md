# 🦅 PROJECT 6 — Multi-stage Builds (small, secure, production-grade images)

> **Part of the Docker Learning Path.** Do Projects 1–5 first.
>
> ⏱️ **Time:** 60 minutes · 🎓 **Level:** intermediate
> 🎯 **Instructions learned:** multiple `FROM ... AS`, `COPY --from`, `RUN --mount=type=cache`, `RUN --mount=type=secret`, `--target` · **Concepts:** image size, build vs runtime dependencies, `scratch`/`distroless`, cross-platform builds

---

## 1. The idea

Build the **same application four different ways** and measure the sizes. This is the most satisfying project in the path — you watch a ~900 MB image become ~50 MB, then ~8 MB, and you learn to audit *where* every megabyte went.

---

## 2. Files to create

```
06-multistage-build/
├── Dockerfile.naive          ❌ the beginner way (huge)
├── Dockerfile.multistage     ✅ builder + runner
├── Dockerfile.cached         ⚡ + BuildKit cache mounts
├── Dockerfile.final          🏆 + non-root + healthcheck + labels
├── Dockerfile.scratch        🪶 the extreme: FROM scratch
├── requirements.txt
├── .dockerignore
├── secret.txt                (for Task 6.5 only — delete afterwards)
├── app/
│   ├── main.py
│   └── util.py
└── tests/
    └── test_app.py
```

### `app/util.py`

```python
"""Pure functions — easy to unit-test inside the build."""
from __future__ import annotations


def slugify(text: str) -> str:
    keep = []
    for ch in text.strip().lower():
        keep.append(ch if ch.isalnum() else "-")
    out = "".join(keep)
    while "--" in out:
        out = out.replace("--", "-")
    return out.strip("-")


def celsius_to_fahrenheit(c: float) -> float:
    return round(c * 9 / 5 + 32, 2)


def summarize(items: list) -> dict:
    return {"count": len(items), "first": items[0] if items else None, "empty": not items}
```

### `app/main.py`

```python
"""A tiny stdlib HTTP app used to demonstrate image-size optimisation."""
import json
import os
import platform
import subprocess
import sys
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from app.util import celsius_to_fahrenheit, slugify, summarize  # noqa: E402

PORT = int(os.environ.get("PORT", "8000"))
HOST = os.environ.get("HOST", "0.0.0.0")


def image_facts() -> dict:
    """Report what is (and isn't) present in this image."""
    def has(cmd: str) -> bool:
        from shutil import which
        return which(cmd) is not None

    size_hint = "unknown"
    try:
        out = subprocess.run(["du", "-sh", "/"], capture_output=True, text=True, timeout=10)
        if out.returncode == 0:
            size_hint = out.stdout.split()[0]
    except Exception:
        pass

    return {
        "python": platform.python_version(),
        "os_release": (open("/etc/os-release").read().splitlines()[0]
                       if os.path.exists("/etc/os-release") else "no /etc/os-release"),
        "user": os.environ.get("USER") or str(os.getuid()),
        "root_filesystem_size": size_hint,
        "tools_present": {t: has(t) for t in
                          ("sh", "curl", "wget", "gcc", "git", "pip", "du", "ps")},
        "tests_copied_in": os.path.exists("/app/tests"),
        "now_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    }


class Handler(BaseHTTPRequestHandler):
    def _send(self, code: int, body) -> None:
        if not isinstance(body, bytes):
            body = json.dumps(body, indent=2).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/health":
            self._send(200, {"status": "ok"})
        elif path == "/facts":
            self._send(200, image_facts())
        elif path.startswith("/slug/"):
            self._send(200, {"input": path[6:], "slug": slugify(path[6:])})
        elif path.startswith("/f/"):
            try:
                self._send(200, {"c": path[3:], "f": celsius_to_fahrenheit(float(path[3:]))})
            except ValueError:
                self._send(400, {"error": "not a number"})
        elif path == "/":
            self._send(200, {"routes": ["/", "/health", "/facts", "/slug/<text>", "/f/<celsius>"],
                             "summary": summarize(["multi", "stage", "builds"])})
        else:
            self._send(404, {"error": "no such route"})

    def log_message(self, fmt, *args):
        print(f"[main] {self.command} {self.path}", flush=True)


if __name__ == "__main__":
    print(f"🚀 listening on {HOST}:{PORT}", flush=True)
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
```

### `tests/test_app.py`

```python
"""These run INSIDE the builder stage — if they fail, the image is never produced."""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from app.util import celsius_to_fahrenheit, slugify, summarize


def test_slugify_basic():
    assert slugify("Hello Docker World") == "hello-docker-world"

def test_slugify_punctuation():
    assert slugify("  Multi-stage  Builds!! ") == "multi-stage-builds"

def test_celsius():
    assert celsius_to_fahrenheit(0) == 32.0
    assert celsius_to_fahrenheit(100) == 212.0

def test_summarize():
    assert summarize([]) == {"count": 0, "first": None, "empty": True}
    assert summarize(["a", "b"])["count"] == 2
```

### `requirements.txt`

```
# pytest is a BUILD/TEST dependency — it must NOT reach the final image.
# That is precisely what multi-stage builds solve.
pytest==8.3.4
```

### `.dockerignore`

```gitignore
.git
__pycache__
**/__pycache__
*.pyc
.venv
venv
*.log
.env
*.env
secret.txt
.DS_Store
.vscode
.idea
Dockerfile*
.dockerignore
```

---

## 3. The four Dockerfiles

### ❌ `Dockerfile.naive` — what most beginners write

```dockerfile
FROM python:3.13
WORKDIR /app
COPY . .
RUN pip install -r requirements.txt
EXPOSE 8000
CMD ["python", "app/main.py"]
```

Everything ships: full Debian, gcc toolchain, pip cache, pytest, your tests, your `.git` if you forgot `.dockerignore`.

### ✅ `Dockerfile.multistage` — builder + runner

```dockerfile
# syntax=docker/dockerfile:1

# ==================== STAGE 1: build & test ====================
FROM python:3.13-alpine AS builder

WORKDIR /app

# Compilers and test tools live HERE and never reach the final image.
RUN apk add --no-cache gcc musl-dev

COPY requirements.txt .
# Build wheels once, so the runtime stage can install WITHOUT a compiler.
RUN pip wheel --no-cache-dir --wheel-dir /wheels -r requirements.txt

COPY . .
# Fail the build if the tests fail. Bad code never produces an image. 🎯
RUN python -m pytest tests/ -q

# ==================== STAGE 2: runtime ====================
FROM python:3.13-alpine AS runner

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PORT=8000
WORKDIR /app

RUN addgroup -S app && adduser -S app -G app

# Install from the pre-built wheels: --no-index means "don't touch the network".
COPY --from=builder /wheels /wheels
RUN pip install --no-cache-dir --no-index --find-links=/wheels /wheels/* \
 && rm -rf /wheels /root/.cache

# Copy ONLY what runs. No tests, no gcc, no pip cache, no source clutter.
COPY --from=builder --chown=app:app /app/app ./app

USER app
EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD python -c "import urllib.request,sys;sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health',timeout=2).status==200 else 1)"

CMD ["python", "-m", "app.main"]
```

### ⚡ `Dockerfile.cached` — BuildKit cache mounts

```dockerfile
# syntax=docker/dockerfile:1

FROM python:3.13-alpine AS builder
WORKDIR /app
COPY requirements.txt .
# The pip download/build cache PERSISTS between builds but never enters a layer.
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --prefix=/install -r requirements.txt

FROM python:3.13-alpine AS runner
ENV PYTHONUNBUFFERED=1 PORT=8000
WORKDIR /app
# Copy the installed packages straight into site-packages
COPY --from=builder /install/lib/python3.13/site-packages /usr/local/lib/python3.13/site-packages
COPY --from=builder /install/bin /usr/local/bin
COPY app ./app
EXPOSE 8000
CMD ["python", "-m", "app.main"]
```

### 🏆 `Dockerfile.final` — the production template

```dockerfile
# syntax=docker/dockerfile:1

# ---------- pin the base by digest for reproducible builds ----------
ARG PYTHON_VERSION=3.13-alpine

# ==================== STAGE 1: deps ====================
FROM python:${PYTHON_VERSION} AS deps
WORKDIR /app
RUN apk add --no-cache gcc musl-dev
COPY requirements.txt .
RUN --mount=type=cache,target=/root/.cache/pip \
    pip wheel --no-cache-dir --wheel-dir /wheels -r requirements.txt

# ==================== STAGE 2: test ====================
FROM deps AS test
COPY . .
RUN python -m pytest tests/ -q

# ==================== STAGE 3: runtime ====================
FROM python:${PYTHON_VERSION} AS runtime

ARG APP_VERSION=1.0.0
ARG GIT_COMMIT=unknown
ARG BUILD_DATE=unknown
ENV APP_VERSION=${APP_VERSION} \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PORT=8000 \
    HOST=0.0.0.0

LABEL org.opencontainers.image.title="multistage-demo" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.revision="${GIT_COMMIT}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.source="https://github.com/you/multistage-demo"

WORKDIR /app

RUN addgroup -S app && adduser -S app -G app \
 && mkdir -p /app/data

# runtime deps only — no compiler, no pytest
COPY --from=deps /wheels /wheels
RUN pip install --no-cache-dir --no-index --find-links=/wheels /wheels/* \
 && rm -rf /wheels /root/.cache

COPY --from=test --chown=app:app /app/app ./app

# an immutable build-info file (works in every language)
RUN printf '{"version":"%s","commit":"%s","built":"%s"}\n' \
      "${APP_VERSION}" "${GIT_COMMIT}" "${BUILD_DATE}" > /app/build-info.json \
 && chown app:app /app/build-info.json

USER app
EXPOSE 8000
STOPSIGNAL SIGTERM

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD python -c "import urllib.request,sys;sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health',timeout=2).status==200 else 1)"

CMD ["python", "-m", "app.main"]
```

---

## 4. Build them all and measure

```bash
cd 06-multistage-build

docker build -f Dockerfile.naive      -t app:naive   .
docker build -f Dockerfile.multistage -t app:multi   .
docker build -f Dockerfile.cached     -t app:cached  .

docker build -f Dockerfile.final \
  --build-arg APP_VERSION=1.0.0 \
  --build-arg GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo nogit) \
  --build-arg BUILD_DATE=$(date -u +%FT%TZ) \
  -t app:final .

docker images app --format "table {{.Tag}}\t{{.Size}}\t{{.ID}}"
```

**Typical result:**

| Tag | Size | What's inside |
|---|---|---|
| `app:naive` | **~350 MB – 1 GB** | full Debian + gcc + pip cache + pytest + tests + source |
| `app:multi` | ~55 MB | alpine + wheels + runtime code only |
| `app:cached` | ~55 MB | same, but rebuilds in **seconds** |
| `app:final` | ~50 MB | + non-root + healthcheck + labels + build-info |

### Find out where the megabytes went

```bash
docker history app:naive --human --format "table {{.Size}}\t{{.CreatedBy}}" | head -15
docker history app:final --human --format "table {{.Size}}\t{{.CreatedBy}}" | head -15

# how many layers each has
docker inspect app:naive --format '{{len .RootFS.Layers}} layers'
docker inspect app:final --format '{{len .RootFS.Layers}} layers'

# is pytest in the final image? (it should NOT be)
docker run --rm app:final python -c "import pytest" ; echo "exit=$?"   # ModuleNotFoundError ✅
docker run --rm app:final ls /app                                      # only app/ + build-info.json
docker run --rm app:final cat /app/build-info.json
docker run --rm app:final whoami                                       # app (uid 100)
```

### Run it

```bash
docker run -d --name ms -p 8000:8000 app:final
curl -s localhost:8000/facts  | python3 -m json.tool    # ← shows which tools exist in the image
curl -s localhost:8000/slug/Hello%20Multi%20Stage
curl -s localhost:8000/f/37
docker rm -f ms
```

`/facts` is the interesting one — it tells you `gcc: false`, `tests_copied_in: false`, and the real root filesystem size **from inside**.

---

## 5. Build a single stage in isolation (the debugging superpower)

```bash
docker build --target builder -f Dockerfile.multistage -t app:debug .
docker run --rm -it app:debug sh
  whoami                 # root (build stages run as root)
  ls -la /app            # tests ARE here
  python -m pytest tests/ -v
  gcc --version          # the compiler IS here
  exit
```

> 🎯 Named stages turn one Dockerfile into **several debuggable environments**: `--target deps`, `--target test`, `--target builder`. No more "I can't reproduce the build failure locally".

---

## 6. ✅ Check yourself

1. Why is `pip wheel` in stage 1 and `pip install --no-index` in stage 2?
2. Why run `pytest` inside the **build** rather than after it?
3. What happens to stage 1's filesystem when the build finishes?
4. Why does `docker build --target test` help you debug CI failures?

<details>
<summary>👉 Answers</summary>

1. `pip wheel` **compiles** any C-extension packages and produces portable `.whl` files — that needs `gcc`/`musl-dev`. Stage 2 then installs those pre-built wheels with `--no-index` (no network, no compiler), so the runtime image needs no build toolchain at all. If you installed directly in stage 2 you'd have to ship gcc.
2. Because a failing `RUN` **aborts the build** — no image is produced, so broken code can never be tagged, pushed or deployed. It's a hard gate at the earliest possible moment. It also reuses the exact same dependency layer as the runtime, so you test what you ship.
3. It's **discarded** (kept only in the build cache). Nothing from stage 1 exists in the final image except what you explicitly `COPY --from=builder`. That's the entire mechanism behind the size reduction — and why a `RUN rm -rf` in the final stage is pointless while a multi-stage split is decisive.
4. CI failures in a build stage are otherwise invisible — the container disappears. `--target test` materialises that exact intermediate filesystem so you can poke at it interactively with the same toolchain, same dependencies, same Alpine version. Add `--progress=plain` to see full logs.
</details>

---

## 7. 🔨 Extra Tasks (do all 5)

### ▶ Task 6.1 — Go smaller than Alpine: `FROM scratch`

**`main.go`** (create it — or use any statically-compiled binary):
```go
package main

import (
	"fmt"
	"net/http"
	"os"
	"time"
)

func main() {
	host, _ := os.Hostname()
	fmt.Println("starting on :8080, hostname", host)
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "Hello from a %d MB scratch image! host=%s time=%s\n",
			0, host, time.Now().UTC().Format(time.RFC3339))
	})
	http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprint(w, `{"status":"ok"}`)
	})
	http.ListenAndServe(":8080", nil)
}
```

**`Dockerfile.scratch`:**
```dockerfile
# syntax=docker/dockerfile:1

FROM golang:1.24-alpine AS build
WORKDIR /src
COPY main.go go.mod* ./
# CGO_ENABLED=0  -> a fully STATIC binary with no libc dependency
# -ldflags="-s -w" -> strip symbols & debug info (30-40% smaller)
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /bin/app .

FROM scratch
COPY --from=build /bin/app /app
# scratch has NO /etc/passwd, so create one if your app needs a user identity
COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
EXPOSE 8080
ENTRYPOINT ["/app"]
```

```bash
go mod init app 2>/dev/null || true
docker build -f Dockerfile.scratch -t app:scratch .
docker images app:scratch                 # often 2–10 MB 🤯
docker run -d --name sc -p 8080:8080 app:scratch
curl -s localhost:8080/
curl -s localhost:8080/health

docker exec -it sc sh                     # ❌ FAILS
docker run --rm -it --entrypoint sh app:scratch   # ❌ FAILS too
docker rm -f sc
```

**Question:** Why does `exec sh` fail, and how do you debug such an image?

<details>
<summary>👉 Answer</summary>

**`FROM scratch` is literally an empty filesystem** — no `/bin/sh`, no `ls`, no `cat`, no package manager, not even `/etc/passwd`. Your binary is the *only* file (plus whatever you copied). So there is no shell to exec into. That's a **feature**: an attack surface of essentially zero, nothing to patch, nothing to exploit.

**How to debug it:**
1. **Build to the earlier stage:** `docker build --target build -t app:debug .` then `docker run -it --rm app:debug sh` — you get the full Go/Alpine environment with your compiled binary in `/bin/app`.
2. **Add a debug stage in the same Dockerfile:**
   ```dockerfile
   FROM alpine:3.22 AS debug
   COPY --from=build /bin/app /app
   RUN apk add --no-cache curl bind-tools strace
   ENTRYPOINT ["/app"]
   ```
   then `docker build --target debug -t app:debug .`.
3. **Ephemeral debug container** sharing the running container's namespaces:
   ```bash
   docker run -it --rm --pid=container:sc --net=container:sc nicolaka/netshoot /bin/bash
   ```
4. **Log to stdout** and use `docker logs` — usually the only channel you have.
5. **Static binaries only:** `CGO_ENABLED=0` is mandatory, otherwise the binary links against glibc/musl which doesn't exist in scratch → `no such file or directory` (a confusing error that actually means "missing dynamic loader").

**Middle ground — distroless:** `FROM gcr.io/distroless/static-debian12` gives you a shell-free image **with** CA certs, `/etc/passwd`, tzdata and a non-root user (`USER 65532`) pre-configured. Usually the better production choice than raw `scratch`.

Also: copy `ca-certificates.crt` (as above) or **every HTTPS call will fail** with x509 errors — the classic scratch gotcha.
</details>

---

### ▶ Task 6.2 — Add dedicated `test` and `dev` stages to one Dockerfile

```dockerfile
# syntax=docker/dockerfile:1

FROM python:3.13-alpine AS base
ENV PYTHONUNBUFFERED=1
WORKDIR /app
COPY requirements.txt .

FROM base AS deps
RUN apk add --no-cache gcc musl-dev \
 && pip install --no-cache-dir -r requirements.txt

FROM deps AS test                      # ← stage: run the test suite
COPY . .
RUN python -m pytest tests/ -v --cov=app --cov-report=term-missing

FROM base AS production                # ← stage: slim runtime
RUN addgroup -S app && adduser -S app -G app
COPY --from=deps /usr/local/lib/python3.13/site-packages /usr/local/lib/python3.13/site-packages
COPY --from=test --chown=app:app /app/app ./app
USER app
EXPOSE 8000
CMD ["python", "-m", "app.main"]

FROM deps AS dev                       # ← stage: hot-reload development
COPY . .
EXPOSE 8000
CMD ["python", "-m", "http.server", "8000"]   # or: watchdog / --reload
```

```bash
docker build --target test       -t app:test .
docker build --target production -t app:prod .
docker build --target dev        -t app:dev  .

docker images app
docker run --rm app:test python -m pytest tests/ -v    # re-run tests inside the image
docker run --rm -it app:dev sh                         # dev stage has pytest + gcc + source
docker run -d --name p -p 8000:8000 app:prod && curl -s localhost:8000/health && docker rm -f p
```

**Question:** Why is one Dockerfile with stages better than three separate Dockerfiles?

<details>
<summary>👉 Answer</summary>

**One source of truth.** With three files, the base image version, the dependency install command and the Python flags drift apart within a week — and then "tests pass locally but fail in CI" or "it worked in dev but not prod". With stages:
- All variants share the **exact same** `base`/`deps` layers, so dev, test and prod run identical dependencies. Bit-for-bit.
- A single `docker build` can produce any of them via `--target`; CI runs `--target test` then `--target production` and both reuse the cached `deps` layer.
- Adding a new environment = adding a stage, not a new file to keep in sync.
- The **default** (last stage, or `--target`) is what you ship, so you can't accidentally deploy the dev image.

Add `pytest-cov` to `requirements.txt` for the coverage flags to work — and note that it then lands in the prod image too if you install from `deps`. The cleaner fix is **two requirement files**: `requirements.txt` (runtime) and `requirements-dev.txt` (test-only), installed only in the `test`/`dev` stages. That's exactly the separation multi-stage builds exist to express.
</details>

---

### ▶ Task 6.3 — Frontend multi-stage (the 1.5 GB → 45 MB trick)

If you use npm, a real React/Vue app:

```dockerfile
# syntax=docker/dockerfile:1

# ---------- STAGE 1: build the frontend ----------
FROM node:22-alpine AS web-build
WORKDIR /app
COPY package*.json ./
RUN npm ci                                   # reproducible install from package-lock.json
COPY . .
RUN npm run build                            # → /app/dist  (static HTML/CSS/JS)

# ---------- STAGE 2: serve with nginx ----------
FROM nginx:1.29-alpine AS web
COPY --from=web-build /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
HEALTHCHECK CMD wget -q --spider http://localhost/ || exit 1
```

**No npm? Simulate the effect** — this teaches the identical lesson:

```dockerfile
# syntax=docker/dockerfile:1
FROM alpine:3.22 AS web-build
WORKDIR /app
RUN mkdir -p dist node_modules
# generate 5,000 junk files to imitate node_modules (~30 MB)
RUN i=0; while [ $i -lt 5000 ]; do echo "junk $i" > node_modules/pkg$i.js; i=$((i+1)); done
RUN echo '<h1>Built frontend</h1>' > dist/index.html
RUN du -sh /app

FROM nginx:1.29-alpine AS web
# copy ONLY the build output — the 5,000 junk files stay behind
COPY --from=web-build /app/dist /usr/share/nginx/html
EXPOSE 80
```

```bash
docker build -f Dockerfile.frontend --target web-build -t fe:build .
docker build -f Dockerfile.frontend                  -t fe:final .
docker images fe
docker run --rm fe:build du -sh /app /app/node_modules /app/dist
docker run --rm fe:final du -sh /usr/share/nginx/html
docker run --rm fe:final sh -c 'ls /app 2>&1 || echo "no /app — node_modules is NOT in the final image"'
docker run -d --name fe -p 8080:80 fe:final && curl -s localhost:8080/ && docker rm -f fe
```

<details>
<summary>👉 Answer</summary>

The build stage is ~40 MB of junk + nginx's own ~50 MB base ⇒ but the **final** image contains only nginx (~50 MB) plus a few KB of HTML. `node_modules`, the Node.js runtime, npm and the source code are all gone — they existed only in the discarded `web-build` stage.

In a real React app the numbers are dramatic: build stage **~1.5 GB** (node + 40k files in `node_modules`), final image **~45 MB** (nginx-alpine + `dist`). A ~30× reduction, which means:
- Push/pull in seconds instead of minutes
- Faster autoscaling and rolling deploys
- Vastly smaller CVE surface (no Node.js, no npm, no 800 transitive packages to scan)
- Cheaper storage and registry egress

**Two frontend-specific gotchas:**
1. Copy `package*.json` **before** the source so `npm ci` stays cached (same pattern as Project 3).
2. SPA routing: nginx will 404 on `/some/route` unless you add `try_files $uri $uri/ /index.html;`.
3. Env vars in frontend builds are **baked in at build time** (`VITE_*`, `REACT_APP_*`), not read at runtime — so use `ARG` + build args, and remember one image per environment unless you inject config at container start.
</details>

---

### ▶ Task 6.4 — Cross-compile for another CPU architecture

```bash
docker buildx version
docker buildx create --use --name multiarch 2>/dev/null || docker buildx use multiarch
docker buildx inspect --bootstrap
```

Add this to your builder stage to see the platform ARGs in action:

```dockerfile
FROM --platform=$BUILDPLATFORM golang:1.24-alpine AS build
ARG TARGETOS TARGETARCH TARGETPLATFORM BUILDPLATFORM
RUN echo "building ON $BUILDPLATFORM FOR $TARGETPLATFORM ($TARGETOS/$TARGETARCH)"
WORKDIR /src
COPY main.go go.mod ./
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH \
    go build -ldflags="-s -w" -o /bin/app .

FROM scratch
COPY --from=build /bin/app /app
ENTRYPOINT ["/app"]
```

```bash
# build for a DIFFERENT architecture than your machine
docker buildx build --platform linux/arm64 -t app:arm64 --load -f Dockerfile.cross .
docker buildx build --platform linux/amd64 -t app:amd64 --load -f Dockerfile.cross .

# build BOTH at once (needs a registry, or --output type=oci)
docker buildx build --platform linux/amd64,linux/arm64 \
  -t <your-username>/app:1.0 --push -f Dockerfile.cross .

docker buildx imagetools inspect <your-username>/app:1.0    # see the manifest list

# prove the architecture of an image
docker inspect app:arm64 --format '{{.Os}}/{{.Architecture}}'
docker inspect app:amd64 --format '{{.Os}}/{{.Architecture}}'

# what happens if you run the wrong one?
docker run --rm app:arm64       # on an amd64 host → "exec format error" (or works via QEMU emulation)
```

<details>
<summary>👉 Answer</summary>

**BuildKit predefines these ARGs** (you must still declare `ARG TARGETARCH` to use them):

| ARG | Meaning | Example |
|---|---|---|
| `BUILDPLATFORM` | Where the build is **running** | `linux/arm64` (your M-series Mac) |
| `TARGETPLATFORM` | What you're building **for** | `linux/amd64` (the cloud server) |
| `TARGETOS` / `TARGETARCH` / `TARGETVARIANT` | Split parts of the above | `linux` / `amd64` / `v2` |

`FROM --platform=$BUILDPLATFORM` is the key trick: it makes the **builder** stage run natively (fast), while `GOARCH=$TARGETARCH` cross-compiles the *output* for the target. Without it, the builder itself is emulated under QEMU and Go builds take 10–20× longer.

**Why this matters:** Apple Silicon laptops are arm64; most cloud servers are amd64. Build on a Mac, push an arm64-only image, and the server dies with **`exec format error`** — the most confusing Docker error there is, because it looks like a permissions problem but is really an architecture mismatch.

`--platform linux/amd64,linux/arm64` produces a **manifest list** (one tag, several architectures); Docker automatically picks the right one at pull time. That's how official images support everything.

Same idea for Python: `pip wheel` outputs are architecture-specific, so for interpreted languages you build the final image *per platform* rather than cross-compiling — buildx handles it, just slower (emulated).
</details>

---

### ▶ Task 6.5 — Use secrets safely, then leak one on purpose

**The RIGHT way** — BuildKit secret mount:

```dockerfile
# syntax=docker/dockerfile:1
FROM alpine:3.22 AS build
# The secret is mounted as a file ONLY for this RUN, and never stored in a layer.
RUN --mount=type=secret,id=mysecret \
    echo "using secret: $(cat /run/secrets/mysecret)" > /tmp/out.txt \
 && wc -c /tmp/out.txt \
 && rm /tmp/out.txt

FROM alpine:3.22
RUN echo "final image — no secret here"
```

```bash
echo "supersecret123" > secret.txt

docker build --secret id=mysecret,src=secret.txt -f Dockerfile.secret -t app:secret .

# now try REALLY hard to find the password in the image:
docker history app:secret --no-trunc | grep -i secret      # nothing ✅
docker run --rm app:secret cat /run/secrets/mysecret       # No such file ✅
docker run --rm app:secret env | grep -i secret            # nothing ✅
docker save app:secret | tar -xO 2>/dev/null | grep -a supersecret123   # nothing ✅
rm secret.txt
```

**The WRONG way** — `ARG`, then hunt it down:

```dockerfile
FROM alpine:3.22
ARG SECRET
RUN echo "the password is $SECRET" > /app/config.txt
```

```bash
docker build --build-arg SECRET=supersecret123 -f Dockerfile.leak -t app:leak .

docker history app:leak --no-trunc | grep -i supersecret123   # 😱 FOUND IT
docker run --rm app:leak cat /app/config.txt                  # 😱 FOUND IT
docker inspect app:leak | grep -i supersecret                 # sometimes here too
```

**Third way** — an SSH mount for private repos:
```dockerfile
RUN --mount=type=ssh git clone git@github.com:private/repo.git /src
```
```bash
docker build --ssh default -t app:ssh .
```

<details>
<summary>👉 Answer — the rules</summary>

**Anything that appears in a Dockerfile instruction ends up in `docker history`, permanently.** `RUN echo $SECRET` records the literal command line; if the value was expanded into a file or a log, it's in the layer's filesystem forever — even if a later `RUN rm` deletes it, because layers are immutable. Anyone who can `docker pull` your image can extract it with `docker save` + `tar`.

**Hierarchy of secret handling, best to worst:**

| Method | In a layer? | In `docker history`? | Use for |
|---|---|---|---|
| Vault / cloud secret manager fetched at runtime | ❌ | ❌ | **Everything, ideally** |
| Docker/K8s secrets mounted as files (`/run/secrets`) | ❌ | ❌ | Runtime DB passwords, TLS keys |
| `RUN --mount=type=secret,id=x` | ❌ | ❌ | **Build-time-only** creds (private package registry, npm token) |
| `RUN --mount=type=ssh` | ❌ | ❌ | Cloning private repos during build |
| `docker run -e` / `--env-file` at runtime | ❌ | ❌ | Simple apps; visible via `docker inspect` to anyone with docker access |
| `ENV SECRET=...` | ✅ | ✅ | ❌ Never |
| `ARG SECRET` + `RUN echo $SECRET` | ✅ | ✅ | ❌ Never |
| `COPY .env .` | ✅ | ✅ | ❌ Never |

**Extra hygiene:**
- Put `.env`, `*.pem`, `*.key`, `secret.txt` in **`.dockerignore`** so they can't be `COPY`'d by accident.
- Scan your images: `docker scout cves app:final`, `trivy image app:final`, `docker scout secrets`.
- If a secret ever lands in a pushed image, **rotate it immediately** — deleting the tag does not remove it from the registry, mirrors, or anyone's local cache.
- `--mount=type=secret` requires BuildKit (default since Docker 23) and the `# syntax=docker/dockerfile:1` line for older versions.
</details>

---

## 8. 🧹 Clean up

```bash
docker rm -f ms sc fe p 2>/dev/null
docker rmi app:naive app:multi app:cached app:final app:scratch app:test app:prod app:dev \
           app:arm64 app:amd64 app:secret app:leak fe:build fe:final 2>/dev/null
docker builder prune -f          # clears the BuildKit cache (your cache mounts too)
docker system df
```

---

## ➡️ Next

**`10-PROJECT-7-compose-stack.md`** — put many containers together with Docker Compose: API + Postgres + Redis + web, with healthchecks and networking.

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish%20Kumar%20Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn → <https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260>
🐙 GitHub → <https://github.com/3558Bhk>

*Built for engineers who learn by breaking things on purpose.*

</div>
