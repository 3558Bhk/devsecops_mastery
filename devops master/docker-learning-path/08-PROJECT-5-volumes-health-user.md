# 🐓 PROJECT 5 — Persistent Data App (`VOLUME`, `USER`, `HEALTHCHECK`, `STOPSIGNAL`)

> **Part of the Docker Learning Path.** Do Projects 1–4 first.
>
> ⏱️ **Time:** 45–60 minutes · 🎓 **Level:** intermediate
> 🎯 **Instructions learned:** `USER`, `VOLUME`, `HEALTHCHECK`, `STOPSIGNAL`, `COPY --chown` · **Concepts:** named volumes vs bind mounts, non-root containers, liveness vs readiness, restart policies

---

## 1. The idea

A note-taking API that **writes to disk**. You will prove three things with your own hands:

1. Data **survives** container deletion (volumes) — and how it can be destroyed by accident.
2. Docker can tell whether your app is **actually alive**, not just "running" (healthcheck).
3. Running as **non-root** is easy — and that `USER` is a default, not a security wall.

---

## 2. Files to create

```
05-volumes-health-user/
├── Dockerfile
├── .dockerignore
├── notes_app.py
└── healthcheck.sh
```

### `notes_app.py`

```python
"""A note-taking API that persists to a JSON file, using only the stdlib.

Routes
  GET  /notes        -> list all notes
  POST /notes        -> {"text": "..."} creates a note
  GET  /notes/<id>   -> one note
  DELETE /notes/<id> -> delete a note
  GET  /health       -> liveness:  is the process serving?
  GET  /ready        -> readiness: is the DATA DIR actually writable?
  GET  /             -> tiny HTML UI
"""
import json
import os
import signal
import sys
import threading
import uuid
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

DATA_DIR = os.environ.get("DATA_DIR", "/app/data")
DATA_FILE = os.path.join(DATA_DIR, "notes.json")
PORT = int(os.environ.get("PORT", "8000"))
HOST = os.environ.get("HOST", "0.0.0.0")

_lock = threading.Lock()


def _log(msg: str) -> None:
    print(f"[notes] {msg}", flush=True)


def load() -> list:
    if not os.path.exists(DATA_FILE):
        return []
    try:
        with open(DATA_FILE, encoding="utf-8") as fh:
            return json.load(fh)
    except (json.JSONDecodeError, OSError) as exc:
        _log(f"WARN could not read {DATA_FILE}: {exc}")
        return []


def save(notes: list) -> None:
    # write to a temp file then rename -> atomic, never leaves a half-written file
    tmp = DATA_FILE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(notes, fh, indent=2, ensure_ascii=False)
    os.replace(tmp, DATA_FILE)


def data_dir_writable() -> bool:
    probe = os.path.join(DATA_DIR, ".write-probe")
    try:
        with open(probe, "w") as fh:
            fh.write("ok")
        os.remove(probe)
        return True
    except OSError:
        return False


def shutdown(signum, _frame):
    _log(f"received signal {signum} — flushing and exiting cleanly")
    sys.exit(0)


signal.signal(signal.SIGTERM, shutdown)
signal.signal(signal.SIGINT, shutdown)

PAGE = """<!doctype html><html><head><meta charset="utf-8"><title>Notes</title>
<style>body{font-family:system-ui,sans-serif;max-width:640px;margin:2rem auto;padding:0 1rem;line-height:1.6}
input{padding:.5rem;width:70%}button{padding:.5rem 1rem}li{border-bottom:1px solid #ddd;padding:.4rem 0}
code{background:#eee;padding:.1em .35em;border-radius:3px}</style></head><body>
<h1>📝 Container Notes</h1>
<p>Saved to <code>{file}</code> — which is a <b>volume</b>, so it survives container deletion.</p>
<form id="f"><input id="t" placeholder="What did you learn today?" autofocus>
<button>Add</button></form><ul id="l"></ul>
<script>
const l=document.getElementById('l');
async function refresh(){{const r=await fetch('/notes');const n=await r.json();
 l.innerHTML=n.map(x=>`<li>${{x.text}} <small>(${{x.created}})</small></li>`).join('')||'<li><i>no notes yet</i></li>';}}
document.getElementById('f').onsubmit=async e=>{{e.preventDefault();
 const t=document.getElementById('t');if(!t.value.trim())return;
 await fetch('/notes',{{method:'POST',headers:{{'Content-Type':'application/json'}},
   body:JSON.stringify({{text:t.value}})}});t.value='';refresh();}};
refresh();
</script></body></html>"""


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body, ctype="application/json"):
        if isinstance(body, str):
            body = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?")[0]
        if path in ("/", "/index.html"):
            self._send(200, PAGE.format(file=DATA_FILE), "text/html; charset=utf-8")
        elif path == "/notes":
            with _lock:
                self._send(200, json.dumps(load(), indent=2))
        elif path.startswith("/notes/"):
            nid = path.rsplit("/", 1)[-1]
            with _lock:
                note = next((n for n in load() if n["id"] == nid), None)
            self._send(200, json.dumps(note, indent=2)) if note else self._send(404, '{"error":"not found"}')
        elif path == "/health":          # LIVENESS — is the process up?
            self._send(200, '{"status":"ok"}')
        elif path == "/ready":           # READINESS — can it actually do its job?
            ok = data_dir_writable()
            self._send(200 if ok else 503,
                       json.dumps({"ready": ok, "data_dir": DATA_DIR, "writable": ok}))
        else:
            self._send(404, '{"error":"no such route"}')

    def do_POST(self):
        if self.path != "/notes":
            return self._send(404, '{"error":"no such route"}')
        length = int(self.headers.get("Content-Length", 0))
        try:
            payload = json.loads(self.rfile.read(length) or b"{}")
            text = str(payload.get("text", "")).strip()
        except json.JSONDecodeError:
            return self._send(400, '{"error":"invalid JSON"}')
        if not text:
            return self._send(400, '{"error":"text is required"}')
        note = {
            "id": uuid.uuid4().hex[:8],
            "text": text,
            "created": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        }
        with _lock:
            notes = load()
            notes.append(note)
            try:
                save(notes)
            except OSError as exc:
                _log(f"ERROR cannot write {DATA_FILE}: {exc}")
                return self._send(500, json.dumps({"error": "storage unavailable", "detail": str(exc)}))
        _log(f"created note {note['id']}: {text[:60]}")
        self._send(201, json.dumps(note, indent=2))

    def do_DELETE(self):
        if not self.path.startswith("/notes/"):
            return self._send(404, '{"error":"no such route"}')
        nid = self.path.rsplit("/", 1)[-1]
        with _lock:
            notes = load()
            remaining = [n for n in notes if n["id"] != nid]
            if len(remaining) == len(notes):
                return self._send(404, '{"error":"not found"}')
            save(remaining)
        self._send(200, json.dumps({"deleted": nid}))

    def log_message(self, fmt, *args):
        _log(f"{self.command} {self.path} -> {fmt % args}")


if __name__ == "__main__":
    _log(f"starting on {HOST}:{PORT}, data dir = {DATA_DIR} (writable={data_dir_writable()})")
    os.makedirs(DATA_DIR, exist_ok=True)
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
```

### `healthcheck.sh`

```sh
#!/bin/sh
# A readable, script-based healthcheck (used in Task 5.3).
set -e
URL="http://127.0.0.1:${PORT:-8000}/ready"
wget -q --spider "$URL" || exit 1
exit 0
```

### `Dockerfile`

```dockerfile
# syntax=docker/dockerfile:1
FROM python:3.13-alpine

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    DATA_DIR=/app/data \
    HOST=0.0.0.0 \
    PORT=8000

WORKDIR /app

# 1) create a non-root user & group FIRST
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

# 2) copy the code, setting ownership in the SAME instruction (no extra chown layer)
COPY --chown=appuser:appgroup notes_app.py ./
COPY --chown=appuser:appgroup --chmod=755 healthcheck.sh /usr/local/bin/healthcheck.sh

# 3) create the writable data directory and hand it to the app user
RUN mkdir -p /app/data && chown -R appuser:appgroup /app/data

# 4) declare the mount point (see the notes below about why this is optional)
VOLUME /app/data

# 5) everything below now runs as the unprivileged user
USER appuser

EXPOSE 8000

HEALTHCHECK --interval=15s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -q --spider http://127.0.0.1:8000/ready || exit 1

STOPSIGNAL SIGTERM

CMD ["python", "notes_app.py"]
```

### `.dockerignore`

```gitignore
.git
__pycache__
*.pyc
.venv
venv
data
*.log
.env
*.env
.DS_Store
.vscode
.idea
Dockerfile
.dockerignore
```

---

## 3. Build and run

```bash
cd 05-volumes-health-user

docker build -t notes:v1 .
docker volume create notes-data
docker volume inspect notes-data --format '{{.Mountpoint}}'   # where it lives on your host

docker run -d --name notes -p 8000:8000 -v notes-data:/app/data notes:v1
```

### Watch the health status change

```bash
docker ps --format "table {{.Names}}\t{{.Status}}"
# Up 2 seconds (health: starting)
sleep 20
docker ps --format "table {{.Names}}\t{{.Status}}"
# Up 22 seconds (healthy)          ← 🎉

docker inspect --format='{{json .State.Health}}' notes | python3 -m json.tool
# see Status, FailingStreak, and the Log of every check with Output + ExitCode
```

### Use the API

🌐 **http://localhost:8000** → a small web UI to add notes

```bash
curl -X POST localhost:8000/notes -H 'Content-Type: application/json' -d '{"text":"Learned COPY today"}'
curl -X POST localhost:8000/notes -H 'Content-Type: application/json' -d '{"text":"Learned ENTRYPOINT vs CMD"}'
curl -X POST localhost:8000/notes -H 'Content-Type: application/json' -d '{"text":"Understood volumes"}'

curl -s localhost:8000/notes  | python3 -m json.tool
curl -s localhost:8000/health
curl -s localhost:8000/ready  | python3 -m json.tool
```

---

## 4. 🔬 THE BIG EXPERIMENT — does data survive?

```bash
# 1) Delete the CONTAINER (the volume is untouched)
docker rm -f notes

# 2) Start a BRAND NEW container on the SAME volume
docker run -d --name notes2 -p 8000:8000 -v notes-data:/app/data notes:v1

# 3) Your notes are still there ✅
curl -s localhost:8000/notes | python3 -m json.tool
```

Now the destructive version — read this twice before running it:

```bash
# 4) Delete the container AND the volume
docker rm -f notes2
docker volume ls                    # notes-data is listed
docker volume rm notes-data         # ☠️ DATA IS GONE FOREVER. No recycle bin.
docker volume ls                    # gone

docker run -d --name notes3 -p 8000:8000 -v notes-data:/app/data notes:v1
curl -s localhost:8000/notes        # → []   (Docker silently created a fresh empty volume)
```

> 🎯 **The three-level lifecycle:**
> | Thing | Lives as long as | Holds |
> |---|---|---|
> | **Container filesystem** | the container exists | ephemeral scratch data |
> | **Volume** | until you `docker volume rm` | ✅ your real data |
> | **Image** | until you `docker rmi` | the read-only program |

Also note what happens with **no volume at all**:
```bash
docker run -d --name ephemeral -p 8006:8000 notes:v1
curl -X POST localhost:8006/notes -H 'Content-Type: application/json' -d '{"text":"I will vanish"}'
docker rm -f ephemeral
docker run -d --name ephemeral2 -p 8006:8000 notes:v1
curl -s localhost:8006/notes        # → []   the note is gone
docker rm -f ephemeral2
```

---

## 5. 🔬 Prove non-root is working

```bash
docker exec -it notes3 sh
whoami                        # appuser           ← NOT root ✅
id                            # uid=100(appuser) gid=101(appgroup)
touch /app/data/ok.txt        # ✅ works — we chowned it
touch /usr/nope.txt           # ❌ Permission denied
apk add curl                  # ❌ Permission denied (can't even install packages)
cat /etc/passwd | grep appuser
exit
```

```bash
docker inspect notes:v1 --format 'User in image config = {{json .Config.User}}'
docker run --rm notes:v1 whoami          # appuser
docker run --rm notes:v1 id
```

---

## 6. 🔬 Break the healthcheck on purpose

```bash
# Start the app on the wrong port: HEALTHCHECK probes :8000, app listens on :9999
docker run -d --name broken -p 8005:9999 -e PORT=9999 notes:v1

watch -n 5 'docker ps --filter name=broken --format "{{.Names}}: {{.Status}}"'
# Up 5 seconds (health: starting)
# Up 30 seconds (health: starting)     ← start-period grace
# Up 70 seconds (unhealthy)            ← 3 retries failed

docker inspect --format='{{json .State.Health.Log}}' broken | python3 -m json.tool
# each entry: Start, End, ExitCode:1, Output:""
docker inspect --format='FailingStreak={{.State.Health.FailingStreak}}' broken
docker rm -f broken
```

> Note the container is **still `Up`**. Docker does not restart or kill unhealthy containers by default — it only *reports*. Acting on it is the orchestrator's job (Compose `condition: service_healthy`, Kubernetes readiness probes, or an autoheal container).

---

## 7. ✅ Check yourself

1. What is the difference between `docker rm notes3` and `docker volume rm notes-data`?
2. Why is `USER appuser` placed **after** the `RUN mkdir/chown` and `COPY` lines?
3. What's the difference between `/health` and `/ready` here?
4. Does `VOLUME /app/data` in the Dockerfile actually create the volume?

<details>
<summary>👉 Answers</summary>

1. `docker rm` deletes the **container** (its writable layer) — the volume survives and can be re-attached. `docker volume rm` deletes the **data itself**, permanently.
2. As `root` you can create directories, `chown` them and install packages. Once you switch with `USER appuser`, every later `RUN` is unprivileged and those operations would fail with *Permission denied*. Order: **install → create user → copy → chown → `USER` → `CMD`**.
3. `/health` = **liveness** ("the process is up and answering HTTP"). `/ready` = **readiness** ("my dependencies are fine — the data dir is writable — send me traffic"). A container can be alive but not ready (DB still starting, disk full, read-only mount). Orchestrators restart on liveness failure and *remove from the load balancer* on readiness failure — very different actions.
4. It **declares** a mount point. At `docker run` time Docker creates an **anonymous** volume there if you don't supply `-v`. You can see them with `docker volume ls` — they're the ones with long random hex names, and they're the usual cause of "where did my disk space go?". Because anonymous volumes are easy to leak, many teams skip `VOLUME` entirely and declare volumes explicitly in `docker run -v` / Compose.
</details>

---

## 8. 🔨 Extra Tasks (do all 5)

### ▶ Task 5.1 — Bind mount vs named volume, and the permission trap

```bash
mkdir -p data
docker run -d --name bind1 -p 8007:8000 -v "$(pwd)/data:/app/data" notes:v1
docker logs bind1
curl -X POST localhost:8007/notes -H 'Content-Type: application/json' -d '{"text":"host-mounted"}'
docker logs --tail 5 bind1
ls -la data/
```

You'll likely see **`ERROR cannot write ... Permission denied`**. Diagnose and fix it three different ways:

```bash
# diagnose: compare the UIDs
docker exec bind1 id                                  # uid=100(appuser)
stat -c '%u:%g %n' data                               # probably 1000:1000 (you)

# fix A — chown the host folder to the container's uid
sudo chown -R 100:101 data

# fix B — run the container as YOUR uid instead
docker rm -f bind1
docker run -d --name bind2 -p 8007:8000 --user "$(id -u):$(id -g)" -v "$(pwd)/data:/app/data" notes:v1

# fix C — use a named volume (Docker handles ownership on first use)
docker rm -f bind2
docker run -d --name bind3 -p 8007:8000 -v notes-data:/app/data notes:v1
```

<details>
<summary>👉 Answer — when to use which</summary>

**Why it broke:** a bind mount maps your **host** directory into the container *as-is*, including its host ownership (your uid, usually 1000). The image's `USER appuser` is uid **100** inside the container. Linux checks the numeric uid, not the name — 100 ≠ 1000 → permission denied. With a **named volume**, Docker copies the image's directory contents *and ownership* into the fresh volume on first mount, so uid 100 owns it and it works.

**Fix A** aligns the host folder with the container's uid — correct for shared/deploy servers, needs root once.
**Fix B** aligns the container with your uid — the standard trick for local dev on Linux; the files created on your host are then owned by *you*.
**Fix C** lets Docker own the storage — the right answer for databases and production.

| | Named volume (`-v mydata:/path`) | Bind mount (`-v /host/path:/path`) |
|---|---|---|
| Managed by | Docker (`/var/lib/docker/volumes`) | You |
| Created empty? | Pre-populated from the image | Host contents win, image contents hidden |
| Ownership | Handled by Docker | Your host's — causes the trap above |
| Portable | ✅ yes | ❌ path must exist on every host |
| Best for | **Databases, uploads, production state** | **Source code in dev, config files, logs you want to read** |
| Inspect | `docker volume inspect mydata` | `ls /host/path` |

Also note: on **macOS/Windows** bind mounts go through a file-sharing layer (gRPC-FUSE/VirtioFS) — noticeably slower for I/O-heavy work like `node_modules`, which is why you keep dependencies in a named volume even during dev.
</details>

---

### ▶ Task 5.2 — Restart policies and crash recovery

```bash
docker rm -f notes3 2>/dev/null
docker run -d --name crashy --restart=on-failure:3 -p 8008:8000 -v notes-data:/app/data notes:v1

# kill the app process from inside
docker exec crashy pkill -f notes_app.py
sleep 3
docker ps -a --filter name=crashy --format "{{.Status}}"
docker inspect --format 'RestartCount={{.RestartCount}} ExitCode={{.State.ExitCode}} OOM={{.State.OOMKilled}}' crashy
docker logs --tail 20 crashy

# kill it repeatedly and watch the retry limit be hit
for i in 1 2 3 4; do docker exec crashy pkill -f notes_app.py; sleep 4; done
docker inspect --format 'RestartCount={{.RestartCount}}' crashy
```

Then compare the four policies:

```bash
for policy in no on-failure always unless-stopped; do
  docker rm -f rp 2>/dev/null
  docker run -d --name rp --restart=$policy notes:v1 >/dev/null
  docker stop rp >/dev/null                    # a DELIBERATE stop
  sleep 2
  printf '%-18s after manual stop -> %s\n' "$policy" \
    "$(docker inspect rp --format '{{.State.Status}} (restarts={{.RestartCount}})')"
done
docker rm -f rp
```

<details>
<summary>👉 Answer</summary>

| Policy | Restarts on crash | Restarts after **manual** `docker stop` | Restarts after **Docker daemon restart** |
|---|---|---|---|
| `no` (default) | ❌ | ❌ | ❌ |
| `on-failure[:N]` | ✅ only non-zero exit, up to N times | ❌ | ✅ if it was running |
| `always` | ✅ | ❌ (but **does** start again when the daemon restarts) | ✅ |
| `unless-stopped` | ✅ | ❌ **and stays stopped** across daemon restarts | ❌ if you stopped it |

The `always` vs `unless-stopped` distinction only shows up when the Docker daemon/host restarts: `always` resurrects a container you had deliberately stopped; `unless-stopped` remembers your intent. **For development machines use `unless-stopped`; for production services use `always` or `unless-stopped`.**

`RestartCount` increments on every automatic restart. `ExitCode` 137 = SIGKILL (often OOM); 143 = SIGTERM (a clean stop). `OOMKilled=true` means you hit a `--memory` limit.

Note `--restart` only helps with **process crashes**, not with an app that's alive but broken — that's what `HEALTHCHECK` is for, and combining both (`--restart=always` + healthcheck + an autoheal sidecar, or Kubernetes probes) is what gives real self-healing.
</details>

---

### ▶ Task 5.3 — Three healthcheck styles, compared

**(a) wget one-liner** (already in the Dockerfile):
```dockerfile
HEALTHCHECK CMD wget -q --spider http://127.0.0.1:8000/ready || exit 1
```

**(b) pure Python, no external tools:**
```dockerfile
HEALTHCHECK --interval=15s --timeout=3s --retries=3 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/ready',timeout=2).status==200 else 1)"
```

**(c) a script you own:**
```dockerfile
COPY --chmod=755 healthcheck.sh /usr/local/bin/healthcheck.sh
HEALTHCHECK --interval=15s --timeout=3s --start-period=5s --retries=3 \
  CMD ["/usr/local/bin/healthcheck.sh"]
```

Build all three and compare:

```bash
docker build -t notes:hc-a .
# (edit to variant b) → docker build -t notes:hc-b .
# (edit to variant c) → docker build -t notes:hc-c .

for t in a b c; do
  docker run -d --name hc-$t -p 801$((RANDOM%5)):8000 notes:hc-$t >/dev/null
done
sleep 25
docker ps --filter name=hc- --format "table {{.Names}}\t{{.Status}}"

# how long does each check take?
time docker exec hc-a wget -q --spider http://127.0.0.1:8000/ready
time docker exec hc-b python -c "import urllib.request;urllib.request.urlopen('http://127.0.0.1:8000/ready',timeout=2)"
time docker exec hc-c /usr/local/bin/healthcheck.sh
docker rm -f hc-a hc-b hc-c
```

<details>
<summary>👉 Answer</summary>

| Style | Readability | Speed | Dependencies | Portable to a `scratch` image? |
|---|---|---|---|---|
| (a) `wget` | good | **fastest** (~10–30 ms) | BusyBox `wget` — present in alpine, **absent** in `python:*-slim` and `scratch` | ❌ |
| (b) `python -c` | poor (one long line) | slow (~150–300 ms, interpreter startup) | the Python runtime | ❌ (no python in scratch) |
| (c) script | **best** — real logic, comments, logging | fast | whatever the script uses | ⚠️ only if you ship a static binary |

**Gotchas that bite people:**
- `curl` does **not** exist in alpine or in Debian-slim images by default. `wget` exists in alpine (BusyBox) but **not** in `python:3.13-slim`. Check with `docker run --rm <image> which wget curl`.
- Always use `curl -f` (fail on HTTP ≥ 400) — plain `curl http://x` exits 0 even on a 500, so your healthcheck would always say "healthy".
- `--timeout` must be **shorter** than `--interval`, or checks pile up.
- `--start-period` is essential for slow-starting apps (JVMs, DB migrations): failures during it don't count toward `--retries`.
- **Healthcheck output is stored** in `.State.Health.Log` (last 5 entries) — print something useful on failure, it's your first debugging clue.
- For `FROM scratch` / distroless images, the standard solutions are: a tiny static Go health binary copied into the image, a TCP-only check done by the orchestrator (Kubernetes `tcpSocket` probe), or building a separate `debug` stage.
</details>

---

### ▶ Task 5.4 — Split liveness and readiness properly

`notes_app.py` already has both routes. Now:

1. Point `HEALTHCHECK` at `/health` (liveness) and rebuild → container reports `healthy` even if the data dir is broken.
2. Point it at `/ready` → make the data dir read-only and watch it go `unhealthy`:
   ```bash
   docker run -d --name ro -p 8009:8000 -v notes-data:/app/data:ro notes:v1
   curl -s localhost:8009/ready
   sleep 60 && docker ps --filter name=ro
   docker rm -f ro
   ```
3. Add a comment in the Dockerfile explaining which one *should* drive a restart.

<details>
<summary>👉 Answer</summary>

**Restart on LIVENESS failure; stop sending traffic on READINESS failure.**

- `/health` (liveness) answers: *"is this process deadlocked/crashed?"* If it fails, the only useful remedy is a **restart**.
- `/ready` (readiness) answers: *"can I serve a request right now?"* If it fails (DB down, disk read-only, cache warming), restarting makes things **worse** — you'd restart every replica at once during a DB blip and cause a stampede. The right action is to **pull it out of the load balancer** and retry later.

In the `:ro` test above, the app is perfectly alive but cannot persist → `/ready` returns 503 → Docker marks it `unhealthy` → an orchestrator would stop routing to it. That's the correct behaviour. Note that Docker itself has only **one** healthcheck (it conflates the two); Kubernetes is where you define `livenessProbe`, `readinessProbe` and `startupProbe` separately.

**Rule of thumb:** make the liveness check *cheap and dependency-free* (never call the database from it, or a DB outage restarts your whole fleet), and make the readiness check *thorough*.
</details>

---

### ▶ Task 5.5 — Discover that `USER` is not a security boundary

```bash
# 1) tighten the files
#    add to the Dockerfile: RUN chmod -R g-w,o-rwx /app
docker build -t notes:v2 .
docker run --rm notes:v2 ls -la /app

# 2) the app still runs fine
docker run -d --name tight -p 8010:8000 -v notes-data:/app/data notes:v2
curl -s localhost:8010/health

# 3) BUT the default can be overridden at run time:
docker run --rm --user 0 notes:v2 whoami          # → root  😱
docker run --rm --user 0 notes:v2 apk add --no-cache curl   # → works, as root

# 4) and inspect what's actually recorded
docker inspect notes:v2 --format 'Config.User={{json .Config.User}}'
docker rm -f tight
```

Then add real enforcement and document it:

```dockerfile
LABEL org.opencontainers.image.authors="you@example.com" \
      dev.learn.expected.uid="100" \
      dev.learn.runAsNonRoot="required"
```

<details>
<summary>👉 Answer</summary>

`USER appuser` in a Dockerfile sets a **default**, stored in the image config. Anyone who can run the container can override it with `--user 0` and be root instantly. So `USER` is *hygiene*, not *enforcement*.

**What it does buy you:** protection against accidents — a bug in your app writing to `/etc`, or a compromised dependency, is contained to uid 100 and can't modify system files. Combined with a read-only root filesystem (`--read-only`) and dropped capabilities, that's a big real-world improvement.

**What actually enforces non-root:**
| Layer | Mechanism |
|---|---|
| `docker run` | `--user 1000:1000` explicitly; or a Podman/rootless setup where "root in container" is your own user on the host |
| Docker Daemon | `daemon.json` → `"userns-remap": "default"` (user namespaces: container root maps to an unprivileged host uid) |
| Compose | `user: "1000:1000"` per service, plus `read_only: true`, `cap_drop: [ALL]`, `security_opt: [no-new-privileges:true]` |
| Kubernetes | Pod Security Standards `restricted`, `securityContext.runAsNonRoot: true`, `runAsUser`, `allowPrivilegeEscalation: false`, plus an OPA/Kyverno policy that **rejects** images whose `Config.User` is root |
| CI | `docker inspect --format '{{.Config.User}}'` must be non-empty and non-zero, or the pipeline fails |

**Hardening combo worth memorising:**
```bash
docker run -d --name locked \
  --user 100:101 \
  --read-only --tmpfs /tmp \
  --cap-drop ALL \
  --security-opt no-new-privileges:true \
  --memory 256m --cpus 0.5 \
  -v notes-data:/app/data \
  notes:v2
```
Test it: `docker exec locked touch /app/x` → denied (read-only rootfs), while `/app/data` still works (it's a volume).
</details>

---

## 9. 🧹 Clean up

```bash
docker rm -f notes notes2 notes3 bind1 bind2 bind3 crashy rp hc-a hc-b hc-c ro tight locked ephemeral ephemeral2 2>/dev/null
docker rmi notes:v1 notes:v2 notes:hc-a notes:hc-b notes:hc-c 2>/dev/null
docker volume rm notes-data     # ⚠️ only if you don't need the notes
docker volume prune             # ⚠️ removes ALL unused volumes
```

---

## ➡️ Next

**`09-PROJECT-6-multistage-build.md`** — shrink a 900 MB image to 15 MB with multi-stage builds, cache mounts and secrets.

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish%20Kumar%20Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn → <https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260>
🐙 GitHub → <https://github.com/3558Bhk>

*Built for engineers who learn by breaking things on purpose.*

</div>
