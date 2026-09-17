# 🐤 PROJECT 4 — CLI Tool (`ENTRYPOINT` vs `CMD`, the confusion killer)

> **Part of the Docker Learning Path.** Do Projects 1–3 first.
>
> ⏱️ **Time:** 40–50 minutes · 🎓 **Level:** beginner+
> 🎯 **Instructions learned:** `ENTRYPOINT`, `CMD`, `COPY --chmod` · **Concepts:** exec vs shell form, argument appending vs replacing, PID 1 and signals, `exec` in shell scripts

---

## 1. The idea

Build a container that behaves like a **command-line program**: `docker run mytool greet Ravi`. You will run **6 side-by-side experiments** that permanently settle the `ENTRYPOINT` vs `CMD` question — and one more that shows why shell-form `CMD` silently breaks graceful shutdown.

---

## 2. Files to create

```
04-cli-entrypoint/
├── tool.py
├── entrypoint.sh
├── Dockerfile.cmd-only
├── Dockerfile.entrypoint-only
├── Dockerfile.both          ← ⭐ the recommended pattern
└── Dockerfile.shellform     ← ❌ deliberately wrong, for comparison
```

### `tool.py`

```python
#!/usr/bin/env python3
"""A tiny CLI so we can watch exactly how Docker passes arguments."""
import argparse
import json
import os
import socket
import sys
import time
from datetime import datetime, timezone


def main() -> int:
    p = argparse.ArgumentParser(
        prog="tool",
        description="Demo CLI for learning ENTRYPOINT vs CMD",
    )
    p.add_argument("--host", default="localhost", help="target host")
    p.add_argument("--port", type=int, default=5432, help="target port")
    sub = p.add_subparsers(dest="command")

    g = sub.add_parser("greet", help="greet someone")
    g.add_argument("name", nargs="?", default="World")

    sub.add_parser("time", help="print the container's UTC time")
    sub.add_parser("env", help="print all environment variables as JSON")
    sub.add_parser("args", help="print exactly what argv the process received")
    sub.add_parser("wait", help="run forever (for signal / PID-1 experiments)")

    a = p.parse_args()

    print(f"[tool.py] PID={os.getpid()}  argv={sys.argv}", flush=True)
    print(f"[tool.py] parsed: command={a.command!r} host={a.host!r} port={a.port!r}", flush=True)

    if a.command == "greet":
        print(f"Hello, {a.name}! 👋  (from {socket.gethostname()})")
    elif a.command == "time":
        print(datetime.now(timezone.utc).isoformat())
    elif a.command == "env":
        print(json.dumps(dict(sorted(os.environ.items())), indent=2))
    elif a.command == "args":
        print(json.dumps(sys.argv, indent=2))
    elif a.command == "wait":
        print("running forever — send me SIGTERM with `docker stop`", flush=True)
        while True:
            time.sleep(1)
    else:
        p.print_help()
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

### `entrypoint.sh`

```sh
#!/bin/sh
set -e

echo "[entrypoint.sh] PID=$$ user=$(whoami)"
echo "[entrypoint.sh] arguments received: $*"

# Escape hatch: if asked for a shell, hand over control completely.
if [ "$1" = "sh" ] || [ "$1" = "bash" ]; then
  exec "$@"
fi

# `exec` REPLACES this shell process with python.
# -> python becomes PID 1 -> it receives SIGTERM directly -> graceful shutdown.
# Without `exec`, sh stays PID 1, swallows the signal, and Docker SIGKILLs after the timeout.
exec python /app/tool.py "$@"
```

### `Dockerfile.cmd-only` — CMD only

```dockerfile
FROM python:3.13-alpine
WORKDIR /app
COPY tool.py .
CMD ["python", "tool.py", "--help"]
```

### `Dockerfile.entrypoint-only` — ENTRYPOINT only

```dockerfile
FROM python:3.13-alpine
WORKDIR /app
COPY tool.py .
ENTRYPOINT ["python", "tool.py"]
```

### `Dockerfile.both` ⭐ — the pattern used in real life

```dockerfile
FROM python:3.13-alpine

WORKDIR /app
COPY tool.py .

# --chmod avoids a separate `RUN chmod +x` layer (needs Dockerfile syntax 1.2+)
COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh

# ENTRYPOINT = the fixed program.  CMD = its default arguments.
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["--help"]
```

### `Dockerfile.shellform` ❌ — deliberately wrong

```dockerfile
FROM python:3.13-alpine
WORKDIR /app
COPY tool.py .
# Shell form: Docker wraps these in /bin/sh -c ... and STRING-CONCATENATES them.
ENTRYPOINT python /app/tool.py
CMD --help
```

---

## 3. Build all four

```bash
cd 04-cli-entrypoint

docker build -f Dockerfile.cmd-only        -t t-cmd   .
docker build -f Dockerfile.entrypoint-only -t t-entry .
docker build -f Dockerfile.both            -t t-both  .
docker build -f Dockerfile.shellform       -t t-shell .
```

See what Docker recorded for each:

```bash
for t in t-cmd t-entry t-both t-shell; do
  printf '%-10s Entrypoint=%-45s Cmd=%s\n' "$t" \
    "$(docker inspect $t --format '{{json .Config.Entrypoint}}')" \
    "$(docker inspect $t --format '{{json .Config.Cmd}}')"
done
```

```
t-cmd      Entrypoint=null                                   Cmd=["python","tool.py","--help"]
t-entry    Entrypoint=["python","tool.py"]                   Cmd=null
t-both     Entrypoint=["/usr/local/bin/entrypoint.sh"]       Cmd=["--help"]
t-shell    Entrypoint=["/bin/sh","-c","python /app/tool.py"] Cmd=["--help"]
```

👀 Look at `t-shell`: Docker rewrote your words into `/bin/sh -c "..."`. **That's what shell form means.**

---

## 4. 🧪 The 6 experiments (run every one, write down the output)

| # | Command | Result | Lesson |
|---|---------|--------|--------|
| 1 | `docker run --rm t-cmd` | prints help | `CMD` is the default |
| 2 | `docker run --rm t-cmd greet Ravi` | `sh: greet: not found` ❌ | args **REPLACE** the whole `CMD` — including `python tool.py`! |
| 3 | `docker run --rm t-entry` | argparse error: needs a command | `ENTRYPOINT` alone has **no defaults** |
| 4 | `docker run --rm t-entry greet Ravi` | `Hello, Ravi! 👋` ✅ | args are **APPENDED** to `ENTRYPOINT` |
| 5 | `docker run --rm t-both` | prints help ✅ | `ENTRYPOINT` + `CMD` as default args |
| 6 | `docker run --rm t-both greet Ravi` | `Hello, Ravi! 👋` ✅ | `CMD` replaced, `ENTRYPOINT` kept — **exactly what you want** |

Run them:

```bash
docker run --rm t-cmd
docker run --rm t-cmd greet Ravi          # 💥 experiment 2 — read the error!
docker run --rm t-entry                   # 💥 experiment 3
docker run --rm t-entry greet Ravi        # ✅ experiment 4
docker run --rm t-both                    # ✅ experiment 5
docker run --rm t-both greet Ravi         # ✅ experiment 6
```

### Why experiment 2 explodes

`CMD ["python","tool.py","--help"]` is the **entire** command. Passing `greet Ravi` replaces it completely, so Docker tries to execute a program literally named `greet`. That's why a "program image" needs `ENTRYPOINT` — it pins the program and leaves only the *arguments* flexible.

### The complete rule table

| | `CMD` only | `ENTRYPOINT` only | **`ENTRYPOINT` + `CMD`** |
|---|---|---|---|
| `docker run img` | runs CMD | runs ENTRYPOINT (may fail — no args) | ENTRYPOINT + CMD ✅ |
| `docker run img a b` | **CMD replaced** → runs `a b` | ENTRYPOINT + `a b` | ENTRYPOINT + `a b` (CMD dropped) ✅ |
| Flexible for the user? | very | yes | yes |
| Program pinned? | ❌ no | ✅ yes | ✅ yes |
| Best for | base images (`alpine`, `ubuntu`) | simple fixed tools | **real applications** |

---

## 5. 🧪 Bonus experiment — PID 1 and signals

```bash
docker run -d --name sig-shell t-shell wait
docker run -d --name sig-exec  t-both  wait

docker top sig-shell      # PID 1 is: /bin/sh -c python /app/tool.py wait   ← python is a CHILD
docker top sig-exec       # PID 1 is: python /app/tool.py wait              ← python IS PID 1

time docker stop -t 5 sig-shell   # waits the FULL 5s, then SIGKILL 💥
time docker stop -t 5 sig-exec    # stops almost instantly ✅

docker logs sig-exec
docker rm -f sig-shell sig-exec
```

```
Shell form:  docker stop → SIGTERM → sh (PID 1) → sh ignores/doesn't forward → 5s timeout → SIGKILL
Exec form:   docker stop → SIGTERM → python (PID 1) → handler runs → clean exit
```

> 🎯 **This is why exec form matters in production.** With shell form your app is murdered mid-request: open DB transactions roll back, HTTP connections are reset, in-flight jobs are lost, and buffers may not flush. With exec form you get a graceful shutdown.

---

## 6. ✅ Check yourself

1. Which form lets the user replace *arguments* but never the *program*?
2. Why does `entrypoint.sh` use `exec` before `python`?
3. How do you get a shell into an image whose `ENTRYPOINT` is a compiled binary?
4. Why is `CMD ['echo','hi']` (single quotes) a bug?

<details>
<summary>👉 Answers</summary>

1. **`ENTRYPOINT` (exec form) + `CMD` (exec form) for defaults.** Args you pass replace the `CMD` defaults but are always appended to the fixed `ENTRYPOINT`.
2. `exec` replaces the shell process image with Python, so **Python inherits PID 1** and receives `SIGTERM` directly. Without `exec`, `sh` stays PID 1; BusyBox/`sh` does not forward signals to children, so Docker waits out the stop timeout and sends `SIGKILL`.
3. `docker run --rm -it --entrypoint sh myimage` (or `/bin/bash` on Debian-based images). `--entrypoint` overrides the image's entrypoint for that one run — the universal debugging escape hatch. For a `FROM scratch` image there is no shell at all, so you must debug via an intermediate build stage (`docker build --target builder`).
4. Exec form must be a **JSON array**, and JSON requires double quotes. With single quotes Docker silently falls back to **shell form**, running `/bin/sh -c "['echo', 'hi']"` → `not found`. No build error, just a broken container.
</details>

---

## 7. 🔨 Extra Tasks (do all 5)

### ▶ Task 4.1 — Make the tool genuinely useful

`tool.py` already has `greet`, `time`, `env`, `args` and `wait`. Verify each through `t-both`, then add two more subcommands of your own:

- `calc <a> <op> <b>` — a four-function calculator
- `files <dir>` — list a directory inside the container with sizes

Also add a **default subcommand**: when nothing is passed, print help *and* exit with code `0` (not `1`), because `docker run t-both` with no args should not look like a failure.

```bash
docker run --rm t-both greet Docker
docker run --rm t-both time
docker run --rm t-both env | head -20
docker run --rm t-both args one two three
docker run --rm t-both calc 6 "*" 7
echo "exit code was: $?"
```

<details>
<summary>👉 Hints & answer notes</summary>

- argparse handles operators awkwardly — `*` gets glob-expanded by your **host** shell before Docker ever sees it. Quote it: `t-both calc 6 '*' 7`, or accept `mul`/`add`/`sub`/`div` words instead.
- `echo $?` after `docker run` gives you the **container's exit code** — Docker propagates it. That's what makes containerised CLI tools usable in shell scripts and CI (`&&`, `||`, `set -e` all work).
- To default to help with exit 0, replace `return 1` in the `else` branch with `p.print_help(); return 0`.
- `[tool.py] PID=1` in the output confirms Python really is PID 1 thanks to `exec`.
</details>

---

### ▶ Task 4.2 — Two different escape hatches

```bash
# hatch 1: handled by YOUR script (the `if [ "$1" = "sh" ]` branch)
docker run --rm -it t-both sh
# hatch 2: handled by DOCKER (overrides the image config entirely)
docker run --rm -it --entrypoint sh t-both
# and inspect what the override did
docker run --rm --entrypoint sh t-both -c 'echo entrypoint was replaced'
```

**Question:** Which hatch still works if `entrypoint.sh` is buggy, missing, or not executable? Why should you still keep hatch 1?

<details>
<summary>👉 Answer</summary>

**Hatch 2 (`--entrypoint`) always works**, because Docker replaces the entrypoint *before* your script is ever invoked. It works even if `entrypoint.sh` doesn't exist, has no `+x` bit, or crashes on line 1. It's the reliable debugging tool.

Keep hatch 1 anyway because it's **ergonomic**: `docker run -it myimage sh` is what people instinctively type, and many official images (postgres, redis, mysql) implement exactly this convenience. It also lets your script do setup work before dropping into a shell.

**Two more debugging techniques worth knowing:**
```bash
docker run --rm -it --entrypoint sh t-both     # explore the image before it runs
docker exec -it <running-container> sh         # explore a container that IS running
docker debug <container>                       # ephemeral debug container sharing its namespaces (Docker 20.10+)
```
The difference: `docker exec` needs a **running** container; `--entrypoint` works on a **broken** one. When your container crash-loops and you can't `exec` in, `--entrypoint sh` is the only way in.
</details>

---

### ▶ Task 4.3 — A "database client" tool with sane defaults

Create `Dockerfile.db`:

```dockerfile
FROM python:3.13-alpine
WORKDIR /app
COPY tool.py .
ENTRYPOINT ["python", "tool.py"]
CMD ["--host", "localhost", "--port", "5432"]
```

```bash
docker build -f Dockerfile.db -t t-db .
docker run --rm t-db args                              # host=localhost port=5432 ✅
docker run --rm t-db args --host db.internal           # host=db.internal ... but port=?
```

**Prediction first, then test:** what happens to `--port 5432`?

Then fix it inside `entrypoint.sh` so partial overrides keep the other defaults:

```sh
HOST="${1:-localhost}"
PORT="${2:-5432}"
exec python /app/tool.py --host "$HOST" --port "$PORT"
```

<details>
<summary>👉 Answer</summary>

**`--port 5432` disappears.** `CMD` is replaced **wholesale** — Docker does not merge or append individual flags. `docker run t-db args --host db.internal` becomes `python tool.py args --host db.internal`, and argparse falls back to the *Python-level* default `5432` only because `tool.py` happens to define one. If it didn't, you'd get an error.

**This is a genuinely dangerous trap:** your "defaults" in `CMD` silently vanish the moment a user passes any argument at all.

Two robust fixes:
1. **Put the defaults in the application**, not in the Dockerfile (what `tool.py` does with argparse `default=`). Then `CMD` can be empty and any subset of flags works.
2. **Put them in the entrypoint script** using `${VAR:-default}` shell parameter expansion (as above), which merges user args with defaults deliberately.

**Rule:** `CMD` defaults are all-or-nothing. For anything with more than one optional flag, make the *program* own the defaults.
</details>

---

### ▶ Task 4.4 — Handle `SIGTERM` gracefully in Python, then break it

Add this to `tool.py`'s `wait` branch:

```python
import signal

def _shutdown(signum, frame):
    print(f"\n[tool.py] received signal {signum} — shutting down cleanly...", flush=True)
    print("[tool.py] closing connections, flushing buffers, bye!", flush=True)
    sys.exit(0)

signal.signal(signal.SIGTERM, _shutdown)
signal.signal(signal.SIGINT, _shutdown)
```

```bash
docker build -f Dockerfile.both -t t-both .
docker run -d --name graceful t-both wait
sleep 2
docker stop graceful            # → instant stop
docker logs graceful            # → you SEE the shutdown messages ✅
docker rm graceful
```

Now **remove `exec`** from `entrypoint.sh** (change `exec python ...` to `python ...`), rebuild, and repeat.

<details>
<summary>👉 Answer</summary>

**With `exec`:** `docker stop` returns almost immediately and the logs show `received signal 15 — shutting down cleanly...`. Python is PID 1, so SIGTERM lands on it directly.

**Without `exec`:** `docker stop` blocks for the full grace period (10 s by default), the shutdown message **never appears**, and Docker eventually sends `SIGKILL`. Why:
```
PID 1 = /bin/sh -c /usr/local/bin/entrypoint.sh ...   ← receives SIGTERM, does not forward it
PID 7 = python tool.py wait                            ← never hears about it
```
`sh` waits for its child and does not relay signals. After the timeout Docker SIGKILLs the whole cgroup.

**Two extra refinements for real apps:**
- Use a **tini-style init** if your container spawns child processes: `FROM ... ` → `RUN apk add --no-cache tini` → `ENTRYPOINT ["/sbin/tini","--"]` → `CMD ["python","app.py"]`. tini becomes PID 1, reaps zombies and forwards signals properly.
- Set `STOPSIGNAL SIGTERM` explicitly in the Dockerfile and match your orchestrator's grace period (`docker stop -t 30`, `stop_grace_period: 30s` in Compose, `terminationGracePeriodSeconds` in Kubernetes) to how long your app actually needs to drain.
</details>

---

### ▶ Task 4.5 — Publish it as a one-word command

```bash
docker build -f Dockerfile.both -t mytool:1.0 .
docker tag mytool:1.0 mytool:latest
```

Add an alias to your shell profile (`~/.bashrc` or `~/.zshrc`):

```bash
alias mytool='docker run --rm -i mytool:1.0'
```
```bash
source ~/.bashrc

mytool greet World
mytool time
mytool calc 21 '*' 2
mytool env | head
```

Now push it so any machine can use it:
```bash
docker login
docker tag mytool:1.0 <your-dockerhub-username>/mytool:1.0
docker push <your-dockerhub-username>/mytool:1.0
# on ANY other machine with Docker:
docker run --rm <your-dockerhub-username>/mytool:1.0 greet Ravi
```

**Question:** Why is this genuinely useful, beyond being a party trick?

<details>
<summary>👉 Answer</summary>

**It packages a program together with its exact runtime, so users need nothing but Docker.** Compare installing a Python CLI traditionally: create a venv, get the right Python version, resolve dependency conflicts, maybe compile C extensions, fight `PATH`, repeat on every machine and in CI. With a container image: `docker run`. One command, identical everywhere, no pollution of the host, trivially removable.

This is exactly how tools like `aws-cli`, `terraform`, `kubectl`, `hugo`, `pandoc`, linters and code formatters are distributed today.

Notes on making it feel native:
- **`-i`** is required in the alias so piped stdin works (`cat data.json | mytool parse`). Add `-t` only for interactive prompts — `-t` breaks pipes.
- Add **`--user $(id -u):$(id -g)`** and **`-v "$PWD":/work -w /work`** if the tool must read/write files in the current directory:
  ```bash
  alias mytool='docker run --rm -i -v "$PWD":/work -w /work --user $(id -u):$(id -g) mytool:1.0'
  ```
- Version tags let a team standardise: everyone runs `mytool:1.0`, nobody has "works on my machine" version drift.
- Startup cost is ~100–300 ms — fine for tooling, noticeable in tight shell loops.
</details>

---

## 8. 🧹 Clean up

```bash
docker rm -f sig-shell sig-exec graceful t-db 2>/dev/null
docker rmi t-cmd t-entry t-both t-shell t-db mytool:1.0 mytool:latest 2>/dev/null
```

---

## ➡️ Next

**`08-PROJECT-5-volumes-health-user.md`** — `VOLUME`, `USER`, `HEALTHCHECK`, `STOPSIGNAL`: making data survive and locking the container down.

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish%20Kumar%20Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn → <https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260>
🐙 GitHub → <https://github.com/3558Bhk>

*Built for engineers who learn by breaking things on purpose.*

</div>
