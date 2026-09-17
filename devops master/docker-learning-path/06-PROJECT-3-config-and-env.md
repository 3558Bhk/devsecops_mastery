# 🐥 PROJECT 3 — Configurable Python App (`ENV`, `ARG`, `LABEL`, `EXPOSE`)

> **Part of the Docker Learning Path.** Do Projects 1–2 first.
>
> ⏱️ **Time:** 40 minutes · 🎓 **Level:** beginner+
> 🎯 **Instructions learned:** `ENV`, `ARG`, `LABEL`, `EXPOSE`, layered `COPY` · **Concepts:** build-time vs run-time config, dependency-layer caching, `-e` / `--env-file` overrides

---

## 1. The idea

A tiny web server that reads **all** of its settings from environment variables. Same image, three different behaviours — dev, staging, production — with zero rebuilds. This is how real applications are configured, and it teaches the single most important Dockerfile optimisation (dependency-layer caching).

> 🎁 **No pip packages needed.** The app uses Python's built-in `http.server`, so it works even with no internet access. A `requirements.txt` is included anyway, because you need to learn the layering pattern.

---

## 2. Files to create

```
03-config-and-env/
├── Dockerfile
├── .dockerignore
├── requirements.txt
├── dev.env
└── app.py
```

### `app.py`

```python
"""A tiny config-driven web server using ONLY the Python standard library.

Every setting comes from an environment variable, so the SAME image can run
as dev / staging / production just by changing env vars at `docker run` time.
"""
import html
import json
import os
import platform
import socket
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# ---- all configuration is read from the environment ----
APP_NAME = os.environ.get("APP_NAME", "Unnamed App")
APP_VERSION = os.environ.get("APP_VERSION", "0.0.0")
BUILD_DATE = os.environ.get("BUILD_DATE", "")
GREETING = os.environ.get("GREETING", "Hello from inside a container")
HOST = os.environ.get("HOST", "0.0.0.0")
PORT = int(os.environ.get("PORT", "8000"))
ENVIRONMENT = os.environ.get("APP_ENV", "development")

CSS = """
:root{color-scheme:light dark}
body{font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif;max-width:820px;
     margin:2.5rem auto;padding:0 1.25rem;line-height:1.6}
h1{color:#2496ed} h2{margin-top:2rem;border-bottom:1px solid rgba(127,127,127,.3);padding-bottom:.3rem}
table{border-collapse:collapse;width:100%}
td,th{border:1px solid rgba(127,127,127,.35);padding:.45rem .7rem;text-align:left;font-size:.92rem}
th{background:rgba(36,150,237,.12)}
code{background:rgba(127,127,127,.18);padding:.12em .4em;border-radius:4px}
.badge{display:inline-block;background:#2496ed;color:#fff;border-radius:999px;padding:.2rem .8rem;font-size:.85rem}
nav a{margin-right:1rem}
"""


def page(title: str, body: str) -> bytes:
    doc = f"""<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{html.escape(title)}</title><style>{CSS}</style></head><body>
<nav><a href="/">Home</a><a href="/env">All env vars</a><a href="/health">Health</a><a href="/version">Version</a></nav>
{body}</body></html>"""
    return doc.encode()


def home() -> bytes:
    rows = "".join(
        f"<tr><th>{html.escape(k)}</th><td><code>{html.escape(str(v))}</code></td></tr>"
        for k, v in [
            ("APP_NAME", APP_NAME),
            ("APP_VERSION", APP_VERSION),
            ("BUILD_DATE", BUILD_DATE or "(empty — ARG was not promoted to ENV)"),
            ("APP_ENV", ENVIRONMENT),
            ("GREETING", GREETING),
            ("listening on", f"{HOST}:{PORT}"),
            ("container hostname", socket.gethostname()),
            ("python", platform.python_version()),
            ("server time (UTC)", datetime.now(timezone.utc).isoformat(timespec="seconds")),
        ]
    )
    return page(
        APP_NAME,
        f"<h1>🐳 {html.escape(GREETING)}</h1>"
        f'<p><span class="badge">{html.escape(ENVIRONMENT)}</span> '
        f"<span class=\"badge\">v{html.escape(APP_VERSION)}</span></p>"
        f"<h2>Configuration this container is running with</h2><table>{rows}</table>"
        "<h2>Why this matters</h2>"
        "<p>This image was built <strong>once</strong>. Every value above came from an "
        "environment variable, so the same image can run as dev, staging or production "
        "just by passing different <code>-e</code> flags at <code>docker run</code> time.</p>",
    )


def env_page() -> bytes:
    rows = "".join(
        f"<tr><td><code>{html.escape(k)}</code></td><td>{html.escape(str(v))}</td></tr>"
        for k, v in sorted(os.environ.items())
    )
    return page("env", f"<h1>All environment variables ({len(os.environ)})</h1><table>{rows}</table>")


class Handler(BaseHTTPRequestHandler):
    server_version = f"{APP_NAME}/{APP_VERSION}"

    def _send(self, code: int, body: bytes, ctype: str = "text/html; charset=utf-8"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?")[0].rstrip("/") or "/"
        if path == "/":
            self._send(200, home())
        elif path == "/env":
            self._send(200, env_page())
        elif path == "/health":
            self._send(200, b'{"status":"ok"}', "application/json")
        elif path == "/version":
            self._send(
                200,
                json.dumps(
                    {"name": APP_NAME, "version": APP_VERSION, "built": BUILD_DATE, "env": ENVIRONMENT},
                    indent=2,
                ).encode(),
                "application/json",
            )
        else:
            self._send(404, page("404", f"<h1>404</h1><p>No route for <code>{html.escape(path)}</code></p>"))

    def log_message(self, fmt, *args):  # keep logs tidy and on stdout
        print(f"[{self.log_date_time_string()}] {self.address_string()} {fmt % args}", flush=True)


if __name__ == "__main__":
    print(f"🚀 {APP_NAME} v{APP_VERSION} starting on {HOST}:{PORT} ({ENVIRONMENT})", flush=True)
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
```

### `requirements.txt`

```
# Deliberately almost empty — the app uses only the Python standard library,
# so this project builds fast and offline.
# Add a real package here (e.g. `requests`) to complete Task 3.3.
```

### `dev.env`

```bash
APP_NAME=Local Dev
APP_ENV=development
GREETING=Namaste from my dev container 🙏
PORT=8000
HOST=0.0.0.0
# NOTE: never put real secrets in a file that gets committed.
# *.env is listed in .dockerignore AND .gitignore.
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
.DS_Store
.vscode
.idea
# secrets must never enter the build context
.env
*.env
*.pem
*.key
# Docker's own files
Dockerfile
.dockerignore
docker-compose*.yml
```

### `Dockerfile`

```dockerfile
# syntax=docker/dockerfile:1
FROM python:3.13-alpine

# ================= BUILD-TIME variables (disappear after the build) =================
ARG APP_VERSION=1.0.0
ARG BUILD_DATE=unknown

# ================= RUN-TIME variables (stay inside the container) =================
ENV APP_NAME="Docker Learner" \
    APP_ENV="production" \
    HOST=0.0.0.0 \
    PORT=8000 \
    GREETING="Hello from inside a container" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

# 👇 This line is the whole point of ARG: promote a build-time value into the image
#    so the RUNNING container can still see it. Delete it and BUILD_DATE becomes empty.
ENV APP_VERSION=${APP_VERSION} \
    BUILD_DATE=${BUILD_DATE}

LABEL org.opencontainers.image.title="Docker Learner" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.description="Learning ENV, ARG and LABEL"

WORKDIR /app

# ---------- THE CACHING PATTERN (memorise this order) ----------
# 1) copy ONLY the dependency manifest  → this layer stays cached for weeks
COPY requirements.txt .
# 2) install dependencies               → expensive, but only re-runs when line 1 changed
RUN pip install --no-cache-dir -r requirements.txt
# 3) copy the application code LAST     → changes often, but it's cheap to rebuild
COPY . .
# ----------------------------------------------------------------

EXPOSE 8000

CMD ["python", "app.py"]
```

---

## 3. Build and run

```bash
cd 03-config-and-env

docker build -t configapp:1.0 .
docker run -d --name configapp -p 8000:8000 configapp:1.0
```

🌐 **http://localhost:8000** → a page showing every config value
🌐 **http://localhost:8000/env** → *all* environment variables in the container
🌐 **http://localhost:8000/health** → `{"status":"ok"}`
🌐 **http://localhost:8000/version** → JSON version info

```bash
docker logs -f configapp      # Ctrl+C to stop following
docker exec -it configapp sh
  env | sort                # see everything
  python -c "import os;print(os.environ['APP_VERSION'])"
  exit
```

### Now the magic — one image, many personalities

```bash
# "staging" — override with -e
docker run -d --name app-staging -p 8001:8000 \
  -e APP_ENV=staging \
  -e APP_NAME="Staging Build" \
  -e GREETING="Careful, this is STAGING ⚠️" \
  configapp:1.0

# "dev" — override with a file
docker run -d --name app-dev -p 8002:8000 --env-file dev.env configapp:1.0

docker ps
```

🌐 **http://localhost:8000** (production) · **http://localhost:8001** (staging) · **http://localhost:8002** (dev)

**Three different applications. One image. Zero rebuilds.** That is the entire philosophy of container configuration.

### Prove `ARG` ≠ `ENV`

```bash
docker run --rm configapp:1.0 python -c "import os; print('APP_VERSION =', repr(os.environ.get('APP_VERSION'))); print('BUILD_DATE  =', repr(os.environ.get('BUILD_DATE')))"
```
```
APP_VERSION = '1.0.0'      ← survived, because we promoted it with ENV
BUILD_DATE  = 'unknown'    ← survived too (also promoted)
```

Now **comment out** the `ENV BUILD_DATE=${BUILD_DATE}` line, rebuild, and re-run — `BUILD_DATE` comes back empty. `ARG` died with the build. ✅

### Build with your own ARG values

```bash
docker build \
  --build-arg APP_VERSION=2.5.0 \
  --build-arg BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  -t configapp:2.5 .

docker run --rm -d --name v25 -p 8003:8000 configapp:2.5
curl -s http://localhost:8003/version | python3 -m json.tool
docker inspect configapp:2.5 --format '{{json .Config.Labels}}' | python3 -m json.tool
docker rm -f v25
```

---

## 4. ✅ Check yourself

1. I changed `app.py`. Which layers get rebuilt?
2. I changed `requirements.txt`. Which layers get rebuilt?
3. Where does `-e GREETING=hi` fit in the precedence order (Dockerfile `ENV` vs `docker run -e`)?
4. Can I read a secret back out of an image I don't own?

<details>
<summary>👉 Answers</summary>

1. Only the **last `COPY . .`** layer (and anything below it). `FROM`, the `requirements.txt` copy and `pip install` all say `CACHED`. Build takes ~1 second.
2. The `COPY requirements.txt .` layer **and** `pip install` **and** `COPY . .` — everything below the change. This is exactly why `requirements.txt` is copied separately and *first*.
3. **`docker run -e` always wins.** Precedence (lowest → highest): base image `ENV` → your Dockerfile `ENV` → `--env-file` → `-e` on the command line.
4. **Yes.** `docker history --no-trunc <image>`, `docker inspect <image>`, and `docker run --rm <image> env` all reveal every `ENV` and every `RUN` command line. **Anything you put in an image is public.** Secrets go in run-time env, Docker/Kubernetes secrets, or a vault.
</details>

---

## 5. 🔨 Extra Tasks (do all 5)

### ▶ Task 3.1 — `--env-file`, and the secret mistake everybody makes

1. Create `prod.env`:
   ```bash
   APP_NAME=Production API
   APP_ENV=production
   GREETING=Live production traffic 🚨
   DB_PASSWORD=hunter2
   ```
2. Run it:
   ```bash
   docker run -d --name p1 -p 8004:8000 --env-file prod.env configapp:1.0
   curl -s http://localhost:8004/env | grep -o 'DB_PASSWORD[^<]*'
   docker exec p1 env | grep DB_PASSWORD
   docker inspect p1 --format '{{json .Config.Env}}' | tr ',' '\n' | grep DB
   ```
3. Now add `*.env` to `.dockerignore` **and** `.gitignore`, and delete the password line.

**Questions:** Which of the three commands above leaked the password? Is an env var safer than baking it into the image with `ENV`?

<details>
<summary>👉 Answer</summary>

**All three** leaked it. `docker inspect` shows the container's full env, `docker exec env` prints it, and `/env` served it to any HTTP client.

Env vars at **run time** are *much* safer than `ENV` in the Dockerfile:
- `ENV DB_PASSWORD=...` is **permanently baked into the image layer** — recoverable by anyone who pulls the image, forever, even after you remove it in a later build. It also shows in `docker history --no-trunc`.
- Run-time `-e`/`--env-file` never touches the image. The risk moves to *your host* (shell history, the `.env` file's permissions, `docker inspect` access).

**Better still, in order of preference:**
1. A secrets manager / vault injected at deploy time.
2. Docker secrets (`--secret`, Swarm/K8s) — mounted as files in `/run/secrets`, never in env or layers.
3. BuildKit `RUN --mount=type=secret,id=x` for build-time-only credentials (see Project 6, Task 6.5).
4. Run-time env vars from a `.env` file that is **git-ignored**, `chmod 600`, and never committed.
5. ❌ Never: `ENV`/`ARG` in a Dockerfile that gets pushed to a registry.

Also: `--env-file` does **not** do shell expansion or quoting — `PATH=$HOME/bin` is passed literally. And a `#` only starts a comment at the beginning of a line.
</details>

---

### ▶ Task 3.2 — Prove `EXPOSE` is documentation, and make `PORT` truly configurable

The app already reads `PORT` from the environment. Now break the mapping deliberately:

```bash
# app listens on 9000, but EXPOSE still says 8000
docker run -d --name p2 -p 8005:9000 -e PORT=9000 configapp:1.0
curl -sI http://localhost:8005/health | head -1        # ✅ 200 OK

docker rm -f p2
docker run -d --name p3 -p 8005:8000 -e PORT=9000 configapp:1.0
curl -sI --max-time 3 http://localhost:8005/health | head -1   # ❌ nothing / timeout
docker logs p3                                          # app says it's on :9000
docker rm -f p3

# what does the image CLAIM?
docker inspect configapp:1.0 --format '{{json .Config.ExposedPorts}}'
# what does the container ACTUALLY map?
docker run -d --name p4 -p 8006:9000 -e PORT=9000 configapp:1.0 && docker port p4 && docker rm -f p4
```

**Question:** Write the one-line rule.

<details>
<summary>👉 Answer</summary>

**"`EXPOSE` documents; `-p` publishes. The port your app actually *binds to* is what matters — `-p host:container` must match the container-side port the app is listening on, or traffic goes nowhere."**

`p3` failed because the app bound to `9000` while `-p 8005:8000` forwarded traffic to `8000`, where nothing was listening. `EXPOSE 8000` had no effect whatsoever on either case — it only affects `docker run -P` (capital P, publish-all-exposed-to-random-ports) and container-to-container discovery on a user-defined network.
**Best practice:** keep the app's port and `EXPOSE` in sync via one variable so they can't drift:
```dockerfile
ARG PORT=8000
ENV PORT=${PORT}
EXPOSE ${PORT}
```
</details>

---

### ▶ Task 3.3 — Add a real dependency and watch the cache work

1. Add `requests==2.32.3` to `requirements.txt`.
2. `time docker build -t configapp:dep .` → note the seconds spent in `pip install`.
3. Add a harmless comment to `app.py`. Rebuild. → `pip install` says **`CACHED`**, build ≈ 1 s.
4. **Now break it on purpose.** Reorder the Dockerfile:
   ```dockerfile
   COPY . .
   COPY requirements.txt .
   RUN pip install --no-cache-dir -r requirements.txt
   ```
   Rebuild, touch `app.py` (add a space), rebuild again → **pip reinstalls every single time.**
5. Revert to the correct order.

**Question:** Why is the naive order so much worse, and what does this cost in CI?

<details>
<summary>👉 Answer</summary>

With `COPY . .` first, **any** edit to **any** file invalidates that layer — and every layer below it, including `pip install`. So each code change re-downloads and re-installs all dependencies.

The correct order splits the world into two change frequencies:
| Layer | Changes | Cost |
|---|---|---|
| `COPY requirements.txt .` | rarely | — |
| `RUN pip install ...` | rarely | **expensive** (network + compile) |
| `COPY . .` | every commit | cheap (a few KB) |

**In CI** the difference is enormous: a 4-minute build becomes 40 seconds, you use far less registry/network bandwidth, and your feedback loop shortens. The same pattern applies everywhere:
- Node: `COPY package*.json ./` → `RUN npm ci` → `COPY . .`
- Go: `COPY go.mod go.sum ./` → `RUN go mod download` → `COPY . .`
- Java/Gradle: copy `build.gradle` first, then sources.

**Verify a cache hit** with `docker build --progress=plain .` and look for `CACHED` on the pip step.
</details>

---

### ▶ Task 3.4 — Audit every piece of metadata in the image

Run all of these and study the output:

```bash
docker build --build-arg APP_VERSION=9.9.9 \
             --build-arg BUILD_DATE="$(date -u +%FT%TZ)" -t configapp:audit .

docker history configapp:audit --no-trunc | head -20
docker history configapp:audit --human --format "table {{.Size}}\t{{.CreatedBy}}" | head -12
docker inspect configapp:audit --format '{{json .Config.Env}}'      | tr ',' '\n'
docker inspect configapp:audit --format '{{json .Config.Labels}}'   | python3 -m json.tool
docker inspect configapp:audit --format '{{json .Config.ExposedPorts}}'
docker inspect configapp:audit --format '{{json .Config.Cmd}} {{json .Config.WorkingDir}}'
docker images --digests configapp
```

**Questions:** Which `ENV`s did you never write? Where is your `BUILD_DATE`? How many layers are 0 B?

<details>
<summary>👉 Answer</summary>

- **ENVs you never wrote** come from the base image `python:3.13-alpine`: `PATH`, `LANG`, `GPG_KEY`, `PYTHON_VERSION`, `PYTHON_PIP_VERSION`, `PYTHON_SETUPTOOLS_VERSION`, `PYTHON_GET_PIP_URL`, `PYTHON_GET_PIP_SHA256`, plus your own `PYTHONUNBUFFERED`/`PYTHONDONTWRITEBYTECODE`. Your `ENV` lines are *appended* to the base image's.
- **`BUILD_DATE`** appears in two places: as an `ENV` (because you promoted it) and inside `org.opencontainers.image.created` in the `LABEL`s. If you hadn't promoted it, it would appear **only** in the label.
- **0 B layers:** every metadata-only instruction — `ENV`, `ARG`, `LABEL`, `EXPOSE`, `WORKDIR` (when the dir already exists), `CMD`, `ENTRYPOINT`, `USER`, `HEALTHCHECK`. They change the image *config*, not the *filesystem*. Only `FROM`, `RUN`, `COPY`, `ADD` (and `WORKDIR` when it creates a directory) add real bytes.
- `docker history --no-trunc` prints the **full command line of every layer** — this is how you audit an unknown third-party image for leaked secrets or bloat.
- OCI labels (`org.opencontainers.image.*`) are the modern standard; tools, registries and SBOM generators read them. `MAINTAINER` is deprecated.
</details>

---

### ▶ Task 3.5 — Add a `/version` endpoint driven by `ARG` → `ENV`

`app.py` already has `/version`. Now make it prove the ARG/ENV boundary:

1. Comment out `ENV BUILD_DATE=${BUILD_DATE}` in the Dockerfile.
2. Rebuild with `--build-arg BUILD_DATE=2026-09-08T10:00:00Z`.
3. `curl -s localhost:8000/version | python3 -m json.tool` → what is `built`?
4. Restore the `ENV` line, rebuild, re-run. What is `built` now?
5. Finally, make it bulletproof — inject the version at build time as a **file** instead:
   ```dockerfile
   ARG APP_VERSION=1.0.0
   ARG GIT_COMMIT=unknown
   RUN printf '{"version":"%s","commit":"%s"}\n' "${APP_VERSION}" "${GIT_COMMIT}" > /app/build-info.json
   ```
   and have the app read that file as a fallback when `BUILD_DATE` is empty.

<details>
<summary>👉 Answer</summary>

- **Step 3:** `"built": ""` — empty. The `ARG` existed during the build (the `LABEL` still got the right value, because labels are expanded at build time) but it was **not** available to the running process. This is the ARG/ENV boundary, demonstrated.
- **Step 4:** `"built": "2026-09-08T10:00:00Z"` — the `ENV BUILD_DATE=${BUILD_DATE}` line copied the build-time value into the image config, where it persists for the container's whole life.
- **Step 5** is the pattern used by real projects: write an immutable `build-info.json` (or `VERSION` file) during the build. Advantages: it works with any language, it's visible via `docker exec cat /app/build-info.json`, and it survives even if someone forgets an `ENV` line.

**The summary table to remember:**

| | `ARG` | `ENV` |
|---|---|---|
| Visible during `docker build` | ✅ | ✅ |
| Visible in the running container | ❌ | ✅ |
| Set from outside | `--build-arg` | `-e` / `--env-file` |
| Survives into a `FROM this-image` child | ❌ | ✅ |
| Visible in `docker history` | ⚠️ the command line is | ✅ fully |
| Scope | one build stage only | whole image |
| Typical use | version, base-image choice, build flags | app configuration |
</details>

---

## 6. 🧹 Clean up

```bash
docker rm -f configapp app-staging app-dev p1 p2 p3 p4 2>/dev/null
docker rmi configapp:1.0 configapp:2.5 configapp:dep configapp:audit 2>/dev/null
rm -f prod.env
```

---

## ➡️ Next

**`07-PROJECT-4-cli-entrypoint.md`** — `ENTRYPOINT` vs `CMD`, settled forever with 6 experiments.

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish%20Kumar%20Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn → <https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260>
🐙 GitHub → <https://github.com/3558Bhk>

*Built for engineers who learn by breaking things on purpose.*

</div>
