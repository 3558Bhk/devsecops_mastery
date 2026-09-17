# 🐳 The Dockerfile — Complete Beginner Guide

> **Read this file top to bottom, then do the 7 projects.**
> Each project has 3–5 extra tasks so the commands stick.
> The final end-to-end project is in a **separate file**: `02-CAPSTONE-END-TO-END.md`.

---

# PART 1 — The 5 Concepts You Must Understand First

Before any command makes sense, you need these five ideas. Read slowly. This is the part most tutorials skip, and it's why people get confused later.

## 1.1 What problem does Docker solve?

The classic developer sentence:

> **"But it works on my machine!"** 🤷

Your app works on your laptop. Your colleague's laptop has a different Python version. The server has an older Linux. It breaks everywhere except your machine.

**Docker packages your app together with everything it needs** — the OS libraries, the runtime (Python/Node/Java), your code, and your configuration — into one sealed box that runs **identically everywhere**. Laptop, colleague's laptop, AWS, your office server. Same box, same result.

```
WITHOUT Docker                          WITH Docker
┌──────────────┐  ┌──────────────┐      ┌─────────────────────────┐
│ Your laptop  │  │ Prod server  │      │  📦 my-app:1.0 image    │
│ Python 3.13  │  │ Python 3.9   │      │  (code + python + libs) │
│ Node 22      │  │ Node 16      │      └───────────┬─────────────┘
│ libssl 3     │  │ libssl 1.1   │                  │ runs the same on
│ your code    │  │ your code    │        ┌─────────┼─────────┐
└──────────────┘  └──────────────┘        ▼         ▼         ▼
     ✅ works          ❌ breaks       laptop   colleague   server
                                          ✅        ✅         ✅
```

## 1.2 Virtual Machine vs Container (important!)

| | 🖥️ Virtual Machine | 📦 Container |
|---|---|---|
| Contains | Full guest OS + kernel + your app | Only your app + the libraries it needs |
| Size | 1–10 **GB** | 5 MB – 500 **MB** |
| Boot time | 30 seconds – 2 minutes | **Milliseconds – seconds** |
| How many on one laptop | 2–3 | 50+ |
| Isolation | Very strong (separate kernel) | Good (shared kernel, isolated processes) |

**A container is NOT a small VM.** A container is just a normal Linux process that has been given:
1. Its own private filesystem (from the image),
2. Its own private network,
3. Its own view of processes (it thinks it's alone on the machine).

That trick is done by Linux kernel features called **namespaces** and **cgroups**. You don't need to know how they work — just that a container = *isolated process*, not *virtual computer*.

> 💡 On **Windows/macOS**, Docker Desktop quietly runs one small Linux VM for you, and all containers live inside it. That's why Docker on Windows needs WSL2.

## 1.3 Image vs Container vs Dockerfile — the analogy that finally clicks

Think of **cooking**:

| Docker term | Cooking analogy | Explanation |
|---|---|---|
| **Dockerfile** | 📝 The **recipe** | A plain text file with step-by-step instructions |
| **Image** | 🍰 The **baked cake** (or the frozen ready-meal) | The finished, read-only result of following the recipe |
| **Container** | 🍽️ A **slice being served** | A running instance of the image. You can serve many slices from one cake |
| **Registry** (Docker Hub) | 🛒 The **supermarket** | Where you download ready-made images (`nginx`, `postgres`, `python`) |
| **`docker build`** | 👨‍🍳 **Baking** | Recipe → Cake |
| **`docker run`** | 🍴 **Serving a slice** | Cake → Slice on a plate |

**The key sentence:**

> An **image** is a read-only template. A **container** is a running copy of that template.
> One image → unlimited containers. Delete the container, the image is untouched.

```bash
# ONE image
docker build -t my-app:1.0 .

# THREE containers from that same image, all running at once
docker run -d -p 8001:80 my-app:1.0
docker run -d -p 8002:80 my-app:1.0
docker run -d -p 8003:80 my-app:1.0
```

## 1.4 Layers — why images build so fast the second time

Every instruction in a Dockerfile that *changes the filesystem* creates a **layer**. Layers are stacked like pancakes and each one is **read-only**.

```dockerfile
FROM alpine:3.22              # Layer 1: base OS         (~8 MB)
RUN apk add --no-cache curl   # Layer 2: + curl          (~2 MB)
COPY app.py /app/app.py       # Layer 3: + your code     (~4 KB)
CMD ["python", "app.py"]      # (no layer — metadata only)
```

Two huge consequences:

**① Caching.** When you rebuild, Docker compares each instruction with the cache. If nothing changed, it reuses the old layer instantly (`CACHED`). If one layer changes, **every layer below it must be rebuilt.**

```
Change COPY line  →  only layer 3 rebuilds            ⚡ fast (2 seconds)
Change RUN line   →  layer 2 AND layer 3 rebuild      🐢 slower
Change FROM line  →  everything rebuilds              🐌 slowest
```

> 🎯 **Golden rule of Dockerfile ordering:** put **slow, rarely-changing** instructions at the **top** (installing dependencies), and **fast, often-changing** instructions at the **bottom** (copying your code).

**② Deleting files does NOT shrink the image.** Layers are read-only and permanent.

```dockerfile
# ❌ Image is still ~200 MB bigger! Layer 2 keeps the download forever.
RUN wget https://example.com/huge.tar.gz
RUN tar xzf huge.tar.gz
RUN rm huge.tar.gz

# ✅ One layer, temp file never saved. Image stays small.
RUN wget https://example.com/huge.tar.gz \
 && tar xzf huge.tar.gz \
 && rm huge.tar.gz
```

## 1.5 The Build Context — the invisible box Docker sends

When you run:

```bash
docker build -t myimage .
#                       ↑ this dot is the BUILD CONTEXT
```

that `.` means: **"take every file in this folder (and subfolders), zip it up, and send it to the Docker engine."** Only files inside the context can be `COPY`'d into an image. You **cannot** copy `../secret.txt` from a parent folder — it's outside the box.

If your folder has a 2 GB `node_modules`, Docker uploads **2 GB every single build**. That's what `.dockerignore` fixes (covered in Project 2).

---

# PART 2 — The Anatomy of a Dockerfile

## 2.1 The rules of the file

1. The file is named **`Dockerfile`** — capital D, **no extension**. (`dockerfile` also works; `Dockerfile.txt` does **not**.)
2. One instruction per line, written in **UPPERCASE** by convention (`FROM`, not `from` — both work, but uppercase is the standard).
3. Lines starting with `#` are **comments** (except the very first line if it's a parser directive — see 2.3).
4. Empty lines are ignored.
5. Long commands are split with a trailing backslash `\` (no space after the `\`!).
6. The **only mandatory** instruction is `FROM`.

```dockerfile
# syntax=docker/dockerfile:1        ← parser directive (must be line 1)
# This is a comment — ignored by Docker

FROM alpine:3.22                    ← 1. Pick a starting point (REQUIRED)

LABEL maintainer="you@email.com"    ← 2. Add metadata

WORKDIR /app                        ← 3. Choose a working folder

COPY . .                            ← 4. Copy your code in

RUN apk add --no-cache curl         ← 5. Run shell commands at BUILD time

ENV APP_ENV=production              ← 6. Set environment variables

EXPOSE 8080                         ← 7. Document the port

USER appuser                        ← 8. Don't run as root

HEALTHCHECK CMD curl -f http://localhost:8080/health || exit 1

ENTRYPOINT ["/app/start.sh"]        ← 9. The command that runs at START time
CMD ["--mode", "production"]        ← 10. Default arguments for it
```

## 2.2 The lifecycle of an instruction — BUILD time vs RUN time

This single table prevents 80% of beginner confusion:

| Instruction | When does it happen? | Creates a layer? |
|---|---|---|
| `FROM` | 🏗️ Build time | Yes (base layer) |
| `RUN` | 🏗️ **Build time** — runs while the image is being made | ✅ Yes |
| `COPY` / `ADD` | 🏗️ Build time | ✅ Yes |
| `WORKDIR` | 🏗️ Build time (creates the dir) | ✅ Yes |
| `ENV` / `ARG` / `LABEL` / `USER` / `EXPOSE` / `VOLUME` | 🏗️ Build time — saves **metadata** | ❌ No (0-byte layer) |
| `HEALTHCHECK` | 🏗️ Build time (defines), ▶️ **Run time** (executes repeatedly) | ❌ No |
| `CMD` / `ENTRYPOINT` | ▶️ **RUN time** — runs when the container **starts** | ❌ No |

> 🔥 **The #1 beginner mistake:** expecting `RUN npm start` to start your server.
> `RUN` executes **during the build**, then the build moves on. Your server would start, then the build continues and the container later starts with `CMD` instead.
> **To start your app when the container launches, use `CMD` or `ENTRYPOINT`.**

```dockerfile
RUN npm install        # ✅ build time: install packages into the image
CMD ["npm", "start"]   # ✅ run time: launch the server when the container starts
RUN npm start          # ❌ WRONG: tries to start a server during the build and hangs
```

## 2.3 Parser directives (the special first-line comments)

```dockerfile
# syntax=docker/dockerfile:1
# escape=`
```

- `# syntax=...` tells BuildKit which Dockerfile frontend version to use. Put it as the **very first line** (even a comment above it disables it). Use `docker/dockerfile:1` for the latest stable, or `docker/dockerfile:1-labs` for experimental features like `COPY --exclude`.
- `# escape=` changes the line-continuation character from `\` to something else (only needed for Windows paths).

---

# PART 3 — Every Dockerfile Instruction, Explained

Learn these in this order. ⭐ = you must know it cold. 🔶 = know what it does. 🔹 = nice to know.

## 3.1 `FROM` ⭐ — Where every image begins

Picks the **base image** — the starting filesystem your image is built on top of.

```dockerfile
FROM ubuntu:24.04              # full Linux distro (~78 MB)
FROM alpine:3.22               # tiny Linux (~8 MB) ← favourite for learning
FROM python:3.13-alpine        # alpine + Python pre-installed
FROM node:22-alpine            # alpine + Node.js pre-installed
FROM nginx:1.29-alpine         # ready-made web server
FROM postgres:17-alpine        # ready-made database
FROM openjdk:17-jdk-alpine     # Java
FROM golang:1.24-alpine        # Go compiler
FROM scratch                   # COMPLETELY EMPTY. No OS, no shell, nothing.
FROM myimage AS builder        # named stage (used in multi-stage builds)
FROM debian:bookworm-slim      # smaller debian
FROM mcr.microsoft.com/dotnet/sdk:9.0   # .NET (from Microsoft's registry)
```

**Rules & gotchas:**
- Must be the **first** instruction (only comments/parser directives may come before).
- Multiple `FROM`s in one file = **multi-stage build** (Project 6).
- **Never use `:latest` in production** — `latest` silently changes and one day your build breaks for no visible reason. Pin a version: `node:22.14-alpine` is better than `node:22`, which is better than `node:latest`.

| Base image | Approx. size | Use it when |
|---|---|---|
| `scratch` | 0 MB | Statically-compiled Go/Rust binaries |
| `alpine:3.22` | ~8 MB | Learning, tiny tools, minimal production |
| `*-alpine` variants | ~15–60 MB | **Default choice** for most apps |
| `debian:bookworm-slim` | ~75 MB | You need glibc / more apt packages |
| `ubuntu:24.04` | ~78 MB | You need a familiar full distro |
| `python:3.13` (full) | ~350 MB+ | Heavy scientific packages (numpy etc.) |

## 3.2 `RUN` ⭐ — Execute commands while BUILDING

Runs a shell command **inside the image being built** and saves the result as a new layer.

```dockerfile
# Install packages
RUN apk add --no-cache curl git           # Alpine
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*   # Debian/Ubuntu

# Create folders & users
RUN mkdir -p /app/data
RUN adduser -D appuser                    # Alpine: -D = no password
RUN useradd -m -r appuser                 # Debian: -m home dir, -r system user

# Compile code
RUN go build -o /bin/server .

# Chain commands to keep layers small (&& = "and then, stop if it fails")
RUN apk add --no-cache build-base \
 && make \
 && apk del build-base
```

**Two forms:**

```dockerfile
RUN apt-get update && apt-get install -y curl     # SHELL form (99% of the time)
RUN ["/bin/bash", "-c", "echo hello"]             # EXEC form (rarely needed)
```

**Gotchas:**
- `apt-get update` and `apt-get install` **must be in the same `RUN`**, otherwise Docker caches the old package list and installs outdated versions.
- Always clean up in the **same** layer: `--no-cache` (apk), `rm -rf /var/lib/apt/lists/*` (apt), `npm cache clean --force`, `pip --no-cache-dir`.
- If a `RUN` command exits with a non-zero code, the **build fails immediately**. That's a feature — fail fast.

**🔹 Advanced: BuildKit `RUN --mount`** (needs `# syntax=docker/dockerfile:1`)

```dockerfile
# Cache downloaded packages between builds — HUGE speedup
RUN --mount=type=cache,target=/root/.cache/pip pip install -r requirements.txt
RUN --mount=type=cache,target=/root/.npm npm ci

# Use a SECRET without baking it into the image (no leaked passwords!)
RUN --mount=type=secret,id=dbpass \
    DB_PASS=$(cat /run/secrets/dbpass) ./migrate.sh
# build with: docker build --secret id=dbpass,src=./dbpass.txt .

# Bind-mount a folder only for the duration of this RUN
RUN --mount=type=bind,source=.,target=/src make test
```

**🔹 Heredocs** (Dockerfile 1.4+) — write a multi-line script inline:

```dockerfile
# syntax=docker/dockerfile:1
RUN <<EOF
apk add --no-cache curl
mkdir -p /app
echo "built at $(date)" > /app/build-info.txt
EOF
```

## 3.3 `CMD` ⭐ — The default command when the container STARTS

```dockerfile
CMD ["python", "app.py"]                       # EXEC form ← ALWAYS prefer this
CMD python app.py                              # SHELL form (wraps in /bin/sh -c)
CMD ["--port", "8080"]                         # default ARGS for ENTRYPOINT
```

**Rules:**
- Only the **last** `CMD` in a Dockerfile takes effect.
- `CMD` is **overridable** by anything you type after the image name:
  ```bash
  docker run myimage                    # runs the CMD
  docker run myimage sh                 # CMD is REPLACED by sh → you get a shell
  docker run myimage python -c "print(1+1)"
  ```
- If a base image already has a `CMD` (e.g. `alpine` → `/bin/sh`), your `CMD` replaces it.

## 3.4 `ENTRYPOINT` ⭐ — The non-negotiable command

`ENTRYPOINT` also runs at container start, but arguments you pass are **appended**, not replacing.

```dockerfile
ENTRYPOINT ["ping"]
CMD ["-c", "4", "google.com"]
```

```bash
docker run myimage                 # → ping -c 4 google.com       (CMD used as defaults)
docker run myimage yahoo.com       # → ping -c 4 yahoo.com ???
```

Careful — that last one gives `ping -c 4 google.com yahoo.com`. To **replace the defaults** you override CMD explicitly:

```bash
docker run myimage ping -c 2 yahoo.com      # nope, appends again
```

The clean mental model:

| | `CMD` alone | `ENTRYPOINT` alone | `ENTRYPOINT` + `CMD` |
|---|---|---|---|
| `docker run img` | runs CMD | runs ENTRYPOINT | runs ENTRYPOINT + CMD |
| `docker run img arg1` | **CMD replaced** by `arg1` | ENTRYPOINT + `arg1` | ENTRYPOINT + `arg1` (CMD dropped) |
| Best for | Flexible images (`alpine`, `ubuntu`) | **CLI tools & apps** | Real-world default ✅ |

> 🎯 **Use ENTRYPOINT (exec form) for "this image IS a program". Use CMD for "here are the default settings".**
> Project 4 makes this crystal clear with hands-on experiments.

**Overriding an entrypoint when debugging:**
```bash
docker run --entrypoint sh myimage        # escape into a shell even if ENTRYPOINT is set
docker run -it --entrypoint /bin/bash myimage
```

## 3.5 `COPY` ⭐ — Copy files from your computer into the image

```dockerfile
COPY app.py /app/app.py          # one file  → absolute destination
COPY . /app                      # whole context → /app
COPY . .                         # whole context → WORKDIR (if WORKDIR is set)
COPY *.txt /app/docs/            # wildcard — destination MUST end with / for multiple files
COPY src/ /app/src/              # contents of src/ → /app/src/
COPY --chown=appuser:appuser . /app      # set owner while copying
COPY --chmod=755 start.sh /app/start.sh  # set permissions while copying
COPY --from=builder /app/dist /usr/share/nginx/html   # copy from another STAGE
COPY --link package.json /app/   # copy as a separate layer (better caching)
```

**Critical detail about trailing slashes:**

```dockerfile
COPY src /app/       # copies CONTENTS of src → /app/file1, /app/file2
COPY src/ /app/      # same thing
```
`COPY` **never** copies the source folder itself as a subfolder — it copies its *contents*. (This is different from `cp -r` on Linux and trips up everyone once.)

**Destination rules:**
- If the destination doesn't exist, it's **created** (including parent dirs).
- If you copy **more than one source**, the destination **must end in `/`** and must be a directory.
- Paths are **relative to the build context**, never to the Dockerfile's location, and never absolute on your host.

**Flags:**

| Flag | Version | What it does |
|---|---|---|
| `--chown=<user>:<group>` | 1.0 | Set ownership (avoids an extra `RUN chown` layer) |
| `--chmod=<perms>` | 1.2 | Set permissions |
| `--from=<stage\|image>` | 1.0 | Copy from another stage/image instead of the context |
| `--link` | 1.4 | Create an independent layer → better cache reuse |
| `--parents` | 1.19 (labs) | Keep the source directory structure at the destination |
| `--exclude=<pattern>` | 1.19 (labs) | Skip matching files (needs `# syntax=docker/dockerfile:1-labs`) |

## 3.6 `ADD` 🔶 — COPY's older, fancier cousin

Does everything `COPY` does, **plus three magic tricks**:

```dockerfile
ADD https://example.com/file.tar.gz /app/    # 1. downloads from a URL
ADD archive.tar.gz /app/                     # 2. AUTO-EXTRACTS local tar archives
ADD git@github.com:user/repo.git /src        # 3. clones a git repo (labs syntax)
```

> 🎯 **Official Docker recommendation: use `COPY` unless you specifically need URL download or tar auto-extraction.**
> Why? Because `ADD`'s magic makes builds unpredictable — a tar that extracts when you didn't expect it, a download with no checksum, no cache.
> Even for downloads, prefer:
> ```dockerfile
> RUN curl -fsSL https://example.com/tool.tar.gz | tar xz -C /app
> ```
> …because then it's **visible** what's happening, and you can add a checksum.

Same flags as COPY apply (`--chown`, `--chmod`, `--link`, plus `--checksum` and `--keep-git-dir`).

## 3.7 `WORKDIR` ⭐ — Set the working directory

```dockerfile
WORKDIR /app
COPY . .              # → files land in /app
RUN python main.py    # → runs inside /app
CMD ["python", "main.py"]
```

- **Creates the directory** if it doesn't exist (no need for `RUN mkdir`).
- Affects `RUN`, `CMD`, `ENTRYPOINT`, `COPY`, `ADD`.
- Can be **relative** (stacks on the previous WORKDIR) and can use variables:
  ```dockerfile
  WORKDIR /app
  WORKDIR src          # → /app/src
  ARG VERSION=1.0
  WORKDIR /app/v${VERSION}   # → /app/v1.0
  ```
- Better than `RUN cd /app && ...` — because `cd` only lasts for that one `RUN`.

## 3.8 `EXPOSE` 🔶 — Document the port (does NOT publish it!)

```dockerfile
EXPOSE 8080
EXPOSE 443/tcp
```

> ⚠️ **`EXPOSE` does not make the port reachable from your browser.** It is **documentation** + it enables container-to-container communication on a Docker network.

To actually reach the port from your machine you must publish it at **run** time:

```bash
docker run -p 8080:8080 myimage        # host:container  ← THIS is what opens the port
docker run -P myimage                  # capital -P: publish all EXPOSEd ports to random host ports
docker port <container>                # see the mapping
```

```
Your browser → localhost:8080 → [-p 8080:8080] → container port 8080 → your app
```

## 3.9 `ENV` ⭐ — Environment variables (persist at RUN time)

```dockerfile
ENV APP_ENV=production                       # single variable
ENV APP_NAME="My App" APP_VERSION=2.1        # multiple on one line
ENV PATH="/app/bin:${PATH}"                  # extend PATH
ENV DATABASE_URL=postgres://user:pass@db:5432/app
```

- Available to **all later instructions** in the Dockerfile (`RUN`, `COPY`, …).
- **Baked into the image** and available to the running container.
- Overridable at run time: `docker run -e APP_ENV=staging myimage`
- Inspect them: `docker run --rm myimage env` or `docker inspect myimage`

> 🔐 **Never put real secrets in `ENV`** — they are visible to anyone with `docker inspect` or `docker history`. Use run-time `-e`, `--env-file`, Docker secrets, or a secrets manager.

## 3.10 `ARG` 🔶 — Build-time-only variables

```dockerfile
ARG APP_VERSION=1.0.0
ARG BUILD_DATE
RUN echo "Building version ${APP_VERSION}" > /app/version.txt

# Promote an ARG to an ENV so it survives into the container:
ARG APP_VERSION
ENV APP_VERSION=${APP_VERSION}
```

```bash
docker build --build-arg APP_VERSION=2.5 -t myapp:2.5 .
docker build --build-arg HTTP_PROXY=http://proxy:3128 -t myapp .
```

**`ARG` vs `ENV` — the difference everyone asks about:**

| | `ARG` | `ENV` |
|---|---|---|
| Available during `docker build` | ✅ | ✅ |
| Available in the **running container** | ❌ **disappears** | ✅ stays |
| Set from outside | `--build-arg` | `-e` / `--env-file` |
| Scope | Only within the current build stage | Whole image |
| Use for | Version numbers, build flags, base-image choice | App configuration |

**Predefined ARGs** you don't need to declare: `HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY`, `FTP_PROXY`, `TARGETPLATFORM`, `TARGETOS`, `TARGETARCH`, `BUILDPLATFORM`.

**Gotcha:** an `ARG` declared **before** the first `FROM` is *outside* all stages. To use it inside a stage you must re-declare it:
```dockerfile
ARG VERSION=1.0        # global scope
FROM alpine
ARG VERSION            # re-declare to bring it into this stage
RUN echo $VERSION
```

## 3.11 `LABEL` 🔹 — Metadata

```dockerfile
LABEL org.opencontainers.image.title="Task API"
LABEL org.opencontainers.image.version="1.0.0"
LABEL org.opencontainers.image.authors="you@email.com"
LABEL org.opencontainers.image.description="A tiny task management API"
LABEL maintainer="you@email.com"
```
One layer can hold many labels. View them with `docker inspect myimage`.

## 3.12 `USER` ⭐ — Don't run as root

By default everything runs as **root** — inside the container *and*, with some volume setups, on your host. Fix it:

```dockerfile
RUN adduser -D -H appuser          # Alpine: create a system user, no home dir
# RUN useradd -r -m appuser        # Debian/Ubuntu equivalent
RUN mkdir -p /app/data && chown -R appuser:appuser /app
USER appuser                       # everything below runs as appuser
WORKDIR /app
CMD ["python", "app.py"]
```

- `USER` affects `RUN`, `CMD`, `ENTRYPOINT` **after** it.
- Accepts a name or a numeric ID: `USER 1000:1000`.
- After `USER appuser`, you can't `apk add` or write to `/usr` — do those **before** switching.
- Verify: `docker run --rm myimage whoami` → should print `appuser`, not `root`.

## 3.13 `VOLUME` 🔹 — Declare a mount point for persistent data

```dockerfile
VOLUME /app/data
VOLUME ["/app/data", "/app/logs"]
```

- Tells Docker: *"this path holds data that should survive container deletion."*
- At run time, Docker creates an anonymous volume there automatically.
- Better in practice: **skip `VOLUME` in the Dockerfile and declare volumes in `docker run -v` or `docker-compose.yml`**, because:
  - Data written to a `VOLUME` path **after** the `VOLUME` line in the Dockerfile is silently **discarded**.
  - `VOLUME` breaks build caching for that layer.

```bash
docker volume ls
docker volume inspect mydata
docker run -d -v mydata:/app/data myimage          # named volume
docker run -d -v $(pwd)/data:/app/data myimage     # bind mount (your real folder)
```

## 3.14 `HEALTHCHECK` ⭐ — Is my container actually working?

A container can be "running" while the app inside is frozen. `HEALTHCHECK` makes Docker verify it.

```dockerfile
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:8080/health || exit 1

HEALTHCHECK NONE        # disable a healthcheck inherited from the base image
```

| Option | Default | Meaning |
|---|---|---|
| `--interval` | 30s | How often to check |
| `--timeout` | 30s | Kill the check after this long |
| `--start-period` | 0s | Grace period at startup — failures here don't count |
| `--retries` | 3 | Consecutive failures before marking `unhealthy` |

Exit code `0` = healthy, `1` = unhealthy, `2` = reserved.

```bash
docker ps                 # STATUS column shows (health: starting) → (healthy)
docker inspect --format='{{json .State.Health}}' <container> | python -m json.tool
```

> 💡 Alpine has no `curl` by default. Use `wget -q --spider http://localhost:8080/health || exit 1` or install `curl`.

## 3.15 `STOPSIGNAL` 🔹 — How to politely shut down

```dockerfile
STOPSIGNAL SIGTERM      # the default
STOPSIGNAL SIGQUIT      # e.g. for nginx graceful shutdown
STOPSIGNAL SIGKILL      # brutal, no cleanup — avoid
```
When you run `docker stop`, Docker sends this signal, waits 10 seconds (configurable with `-t`), then sends `SIGKILL`.

## 3.16 `ONBUILD` 🔹 — Instructions for the *child* image

```dockerfile
# base.Dockerfile
FROM node:22-alpine
ONBUILD COPY package.json /app/
ONBUILD RUN npm install
ONBUILD COPY . /app
```
Nothing happens when you build *this* image. The instructions fire only when someone does `FROM my-base-image`. Rarely used today; multi-stage builds replaced most of its use cases.

## 3.17 `SHELL` 🔹 — Change the default shell

```dockerfile
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN grep foo bar.txt | wc -l     # now fails properly if grep fails
SHELL ["powershell", "-Command"]  # Windows containers
```
Default on Linux is `["/bin/sh", "-c"]`.

---

## 3.18 ⭐⭐ THE BIG ONE: Shell form vs Exec form

Applies to `RUN`, `CMD`, `ENTRYPOINT`.

```dockerfile
# SHELL FORM — Docker wraps it in a shell
CMD npm start
#  → actually runs:  /bin/sh -c "npm start"

# EXEC FORM — a JSON array, run directly, no shell
CMD ["npm", "start"]
#  → actually runs:  npm start   (PID 1 is npm itself)
```

**Why exec form matters — the PID 1 / signal problem:**

In shell form, `/bin/sh` becomes **PID 1**. `sh` does **not** forward `SIGTERM` to your app. So when you `docker stop`:

```
Shell form:  docker stop → SIGTERM → sh (PID 1) → ignores it → 10s wait → SIGKILL 💥
             Your app is killed mid-request. No graceful shutdown. No cleanup.

Exec form:   docker stop → SIGTERM → your app (PID 1) → closes connections → exits cleanly ✅
```

| | Shell form | Exec form |
|---|---|---|
| Syntax | `CMD npm start` | `CMD ["npm", "start"]` |
| Runs via | `/bin/sh -c` | directly |
| Environment variable expansion (`$HOME`) | ✅ works | ❌ **does NOT work** |
| Shell features (`&&`, `\|`, `>`, globs) | ✅ | ❌ |
| Receives `SIGTERM` properly | ❌ no | ✅ **yes** |
| Use for | `RUN` (almost always) | `CMD` / `ENTRYPOINT` (almost always) |

**If you need variables in exec form**, call the shell yourself:
```dockerfile
CMD ["sh", "-c", "python app.py --port $PORT"]
```

**JSON rules for exec form:** double quotes only (never single quotes), commas between items, and **no trailing comma**:
```dockerfile
CMD ["python", "app.py"]      # ✅
CMD ['python', 'app.py']      # ❌ single quotes → treated as shell form!
CMD ["python", "app.py",]     # ❌ trailing comma → parse error
```

---

## 3.19 🔶 Multi-stage builds (full hands-on in Project 6)

```dockerfile
# syntax=docker/dockerfile:1

# ---------- STAGE 1: build ----------
FROM node:22-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build           # produces /app/dist

# ---------- STAGE 2: run ----------
FROM nginx:1.29-alpine
COPY --from=builder /app/dist /usr/share/nginx/html
EXPOSE 80
```

The final image contains **only** stage 2 — Node, `node_modules`, source code all thrown away. Typical result: **1.2 GB → 45 MB**.

```bash
docker build -t myapp .                       # builds the LAST stage
docker build --target builder -t myapp:dev .  # stop at a specific stage (great for debugging)
```

---

## 3.20 `.dockerignore` ⭐ — Shrink your build context

Same folder as the Dockerfile, named `.dockerignore`:

```gitignore
# Version control
.git
.gitignore

# Dependencies (they get installed INSIDE the image)
node_modules
**/node_modules
__pycache__
**/__pycache__
*.pyc
.venv
venv

# Build output
dist
build
*.log

# Editor / OS junk
.vscode
.idea
.DS_Store
Thumbs.db

# SECRETS — never send these into a build
.env
*.pem
*.key
id_rsa

# Docker's own files
Dockerfile
docker-compose*.yml
.dockerignore
```

**Why it matters:** smaller context = faster builds, no `node_modules` from Windows/Mac polluting a Linux image, and **no secrets accidentally baked in**.

---

## 3.21 Instruction summary card

| Instruction | Purpose | Layer? | Example |
|---|---|---|---|
| `FROM` ⭐ | Base image (**required**) | ✅ | `FROM alpine:3.22` |
| `RUN` ⭐ | Build-time command | ✅ | `RUN apk add --no-cache curl` |
| `CMD` ⭐ | Default run-time command/args | ❌ | `CMD ["python","app.py"]` |
| `ENTRYPOINT` ⭐ | Fixed run-time command | ❌ | `ENTRYPOINT ["/app/run.sh"]` |
| `COPY` ⭐ | Files: context → image | ✅ | `COPY . /app` |
| `ADD` 🔶 | COPY + URL + auto-untar | ✅ | `ADD app.tar.gz /app` |
| `WORKDIR` ⭐ | Set/create working dir | ✅ | `WORKDIR /app` |
| `EXPOSE` 🔶 | Document a port | ❌ | `EXPOSE 8080` |
| `ENV` ⭐ | Runtime env var | ❌ | `ENV APP_ENV=prod` |
| `ARG` 🔶 | Build-time var | ❌ | `ARG VERSION=1.0` |
| `LABEL` 🔹 | Metadata | ❌ | `LABEL maintainer="me@x.com"` |
| `USER` ⭐ | Non-root user | ❌ | `USER appuser` |
| `VOLUME` 🔹 | Declare a mount point | ❌ | `VOLUME /app/data` |
| `HEALTHCHECK` ⭐ | Liveness probe | ❌ | `HEALTHCHECK CMD wget -q --spider http://localhost/health` |
| `STOPSIGNAL` 🔹 | Shutdown signal | ❌ | `STOPSIGNAL SIGTERM` |
| `ONBUILD` 🔹 | Trigger for child images | ❌ | `ONBUILD COPY . /app` |
| `SHELL` 🔹 | Change default shell | ❌ | `SHELL ["/bin/bash","-c"]` |
| `MAINTAINER` ❌ | **Deprecated** — use `LABEL` | — | — |

---

## 3.22 The `docker` CLI commands you'll actually use

```bash
# ---------- BUILD ----------
docker build -t myapp:1.0 .                  # -t = tag (name:version)
docker build -t myapp . -f Dockerfile.prod   # use a differently-named Dockerfile
docker build --no-cache -t myapp .           # ignore the cache, rebuild everything
docker build --target builder -t myapp .     # stop at a stage
docker build --build-arg VER=2.0 -t myapp .  # pass an ARG
docker build --progress=plain -t myapp .     # show full build output (debugging!)
docker build --platform linux/amd64 -t myapp .   # build for another CPU arch
docker buildx build -t user/myapp --push .   # build & push to a registry

# ---------- RUN ----------
docker run myapp                             # foreground — Ctrl+C stops it
docker run -d myapp                          # detached (background)
docker run -it alpine sh                     # interactive shell inside a container
docker run --rm alpine echo hi               # auto-delete the container when it exits
docker run -p 8080:80 myapp                  # publish port host:container
docker run -e APP_ENV=dev myapp              # set an env var
docker run --env-file .env myapp             # load many env vars from a file
docker run -v mydata:/app/data myapp         # named volume
docker run -v $(pwd):/app myapp              # bind mount the current folder
docker run --name web1 myapp                 # give the container a name
docker run --network mynet myapp             # attach to a network
docker run --entrypoint sh myapp             # override ENTRYPOINT (debugging)
docker run --memory=512m --cpus=1 myapp      # resource limits
docker run --restart=unless-stopped myapp    # auto-restart policy

# ---------- INSPECT ----------
docker ps                                    # running containers
docker ps -a                                 # all containers (incl. stopped)
docker images                                # local images
docker logs -f <container>                   # follow logs
docker exec -it <container> sh               # shell inside a RUNNING container
docker inspect <container|image>             # full JSON details
docker stats                                 # live CPU/RAM per container
docker port <container>                      # port mappings
docker history myapp                         # see every layer and its size ⭐
docker diff <container>                      # files changed vs the image
docker top <container>                       # processes inside
docker image inspect myapp --format '{{json .Config.Cmd}}'

# ---------- CLEAN UP ----------
docker stop <container>                      # graceful (SIGTERM, then SIGKILL after 10s)
docker kill <container>                      # immediate SIGKILL
docker rm <container>                        # delete a stopped container
docker rm -f <container>                     # stop + delete
docker rmi <image>                           # delete an image
docker system prune -a                       # delete everything unused ⚠️
docker volume prune                          # delete unused volumes ⚠️ DATA LOSS
docker container prune && docker image prune

# ---------- REGISTRY ----------
docker pull nginx:1.29-alpine
docker push myuser/myapp:1.0
docker login
docker tag myapp:1.0 myuser/myapp:1.0
docker search redis

# ---------- COMPOSE ----------
docker compose up -d                         # start everything in docker-compose.yml
docker compose down                          # stop & remove containers + networks
docker compose down -v                       # ...and delete the volumes too ⚠️
docker compose logs -f api
docker compose exec api sh
docker compose ps
docker compose build --no-cache
docker compose config                        # validate & print the final YAML
```

---

# PART 4 — The 7 Projects (each in its own file)

Each project is a **separate file** in this folder. Do them in order.

| # | File | Project | Main instructions learned |
|---|------|---------|---------------------------|
| 1 | `04-PROJECT-1-hello-docker.md` | 🥚 Hello, Docker | `FROM`, `RUN`, `CMD`, layers, caching |
| 2 | `05-PROJECT-2-static-site.md` | 🐣 Static Website | `COPY`, `ADD`, `WORKDIR`, `.dockerignore`, `EXPOSE` |
| 3 | `06-PROJECT-3-config-and-env.md` | 🐥 Configurable App | `ENV`, `ARG`, `LABEL`, build args vs runtime env |
| 4 | `07-PROJECT-4-cli-entrypoint.md` | 🐤 CLI Tool | `ENTRYPOINT` vs `CMD`, exec vs shell form, PID 1 |
| 5 | `08-PROJECT-5-volumes-health-user.md` | 🐓 Persistent Data App | `VOLUME`, `USER`, `HEALTHCHECK`, `STOPSIGNAL` |
| 6 | `09-PROJECT-6-multistage-build.md` | 🦅 Multi-stage Build | `FROM ... AS`, `COPY --from`, `--target`, cache mounts, secrets |
| 7 | `10-PROJECT-7-compose-stack.md` | 🦉 Compose Stack | `docker-compose.yml`, networks, volumes, `depends_on` |

Then continue with Projects 8–13, again **one file each**. Every one is written twice: **CASE 1 = a simple Dockerfile**, **CASE 2 = a multi-stage Dockerfile**.

| # | File | Project | Case 1 → Case 2 |
|---|------|---------|-----------------|
| 8 | `11-PROJECT-8-react-frontend.md` | ⚛️ React (Vite) frontend | node dev server 230 MB → nginx + static build 52 MB |
| 9 | `12-PROJECT-9-java-backend.md` | ☕ Java / Spring Boot backend | prebuilt jar + JRE → JDK build stage + **layered jar** |
| 10 | `13-PROJECT-10-react-java-fullstack.md` | ⚛️ + ☕ React & Java full stack | two ports + CORS → one origin behind an nginx proxy |
| 11 | `14-PROJECT-11-react-python-fullstack.md` | ⚛️ + 🐍 React & Python full stack | uvicorn `--reload` as root → wheels + pytest stage + gunicorn non-root |
| 12 | `15-PROJECT-12-react-go-fullstack.md` | ⚛️ + 🐹 React & Go full stack | full Go SDK 380 MB → static binary 18 MB → `FROM scratch` 9 MB |
| 13 | `16-PROJECT-13-databases.md` | 🗄️ **6 separate DB mini-projects** — MySQL · MongoDB · Redis · DynamoDB Local · Cassandra · Neo4j | official image + init scripts → build-time schema validation |

> Every project file is **self-contained**: it includes the complete runnable code (Dockerfile + app source) inline, plus extra practice tasks with answers.
> Just create the folder it describes, paste the files, and run the commands.

---

# PART 5 — Troubleshooting: The 12 Errors Every Beginner Hits

| # | Symptom | Cause | Fix |
|---|---|---|---|
| 1 | Container starts then **exits immediately** | Your `CMD` process finished (e.g. `RUN`-style one-shot command, or no `CMD` at all so the base image's `sh` exited) | Give it a long-running foreground process. Test with `docker run -it myimage sh`. Check `docker logs`. |
| 2 | `COPY failed: file not found` | Path is outside the **build context**, or `.dockerignore` excluded it, or you used an absolute host path | Paths are relative to the context `.`. Never `COPY /home/me/file`. |
| 3 | `localhost:8080` refuses connections | You `EXPOSE`d but didn't `-p` | `docker run -p 8080:80 …`. Check `docker port <c>`. |
| 4 | App inside container can't reach another container via `localhost` | Each container has its **own** network namespace | Use the **service name** (`db`, `redis`) on a shared network. |
| 5 | Build is slow / context is 2 GB | `node_modules`, `.git`, `venv` being uploaded | Write a `.dockerignore`. |
| 6 | Changes to my code don't appear | Layer cache, or you edited files but didn't rebuild | `docker build --no-cache`, and remember images are immutable — you must rebuild. |
| 7 | `permission denied` writing to a volume | Container runs as non-root `USER`, host folder owned by you | `chown` the host folder to the container's uid, or `--user $(id -u):$(id -g)`. |
| 8 | `exec format error` | Wrong CPU architecture (ARM Mac ↔ amd64 image) | `docker build --platform linux/amd64 …` or use multi-arch base images. |
| 9 | `docker stop` takes 10 seconds then kills | Shell-form `CMD`/`ENTRYPOINT` → signals not forwarded | Use **exec form** `["..."]`, and `exec` in shell scripts. |
| 10 | Secrets visible in `docker history` | Used `ARG`/`ENV` for a password, or `RUN echo $PASS` | Use `--mount=type=secret`, or pass at **run** time. |
| 11 | `unknown instruction: FROOM` | Typo, or an instruction not in uppercase at line start, or a missing `\` continuation | Instructions are case-insensitive but must be spelled right; a `\` must have **nothing** after it. |
| 12 | `no space left on device` | Old images/containers/volumes piled up | `docker system df` then `docker system prune -a` (and `docker volume prune` ⚠️). |

### The debugging workflow (memorise this)
```bash
docker build --progress=plain --no-cache -t myapp .   # 1. see EVERY line of build output
docker run --rm -it --entrypoint sh myapp             # 2. get inside the image interactively
ls -la /app ; cat /app/*.py ; env ; whoami            # 3. verify files, env, user
docker run --rm myapp                                 # 4. run in FOREGROUND to read errors
docker logs <container>                               # 5. read logs of a detached container
docker inspect <container> --format '{{json .State}}' # 6. exit code, OOMKilled, health
docker history myapp --no-trunc                       # 7. audit layers for size & leaks
```

---

# PART 6 — Best Practices Checklist (print this)

**Correctness**
- [ ] `FROM` uses a **pinned** tag (`node:22.14-alpine`), never `latest`
- [ ] One image = **one responsibility** (don't run nginx + postgres + app in one container)
- [ ] The main process runs in the **foreground**
- [ ] `CMD` and `ENTRYPOINT` use **exec form** `["a","b"]`

**Build speed & size**
- [ ] `.dockerignore` exists and excludes `.git`, `node_modules`, `venv`, build output, secrets
- [ ] Dependency files are copied **before** source code (`COPY requirements.txt .` → `RUN pip install` → `COPY . .`)
- [ ] Install + clean up in the **same** `RUN` layer
- [ ] **Multi-stage** build: compilers/tests never reach the final image
- [ ] `-alpine` or `-slim` base images
- [ ] `--mount=type=cache` for pip/npm/go caches

**Security**
- [ ] `USER` is **non-root**
- [ ] No secrets in `ENV`, `ARG`, or `RUN echo`
- [ ] Only the ports you need are published; internal services stay on private networks
- [ ] Base images are scanned (`docker scout cves myapp`) and updated regularly
- [ ] Read-only root filesystem where possible (`--read-only` + tmpfs for writable paths)

**Operations**
- [ ] `HEALTHCHECK` defined
- [ ] `EXPOSE` documents the real port
- [ ] `LABEL` with title/version/author (OCI labels)
- [ ] The app writes logs to **stdout/stderr**, not to files
- [ ] `STOPSIGNAL` handled gracefully by the app
- [ ] `restart: unless-stopped` in Compose for always-on services

---

# ➡️ Next

You've now seen every Dockerfile instruction and built 7 progressively harder images.

### 1. The capstone — `02-CAPSTONE-END-TO-END.md`, Sections A–C
A complete end-to-end platform: **TaskNest** — API + PostgreSQL + Redis + nginx reverse proxy, with multi-stage builds, healthchecks, non-root users, read-only filesystems, automated backups, smoke tests, CI/CD and a runbook.
- **Section A** = the task (10 requirements + a Definition of Done)
- **Section B** = the starting application code
- **Section C** = the complete answers

### 2. Projects 8–13 — one file each
Six more projects, each written **two ways** so you can see exactly what multi-stage buys you:

| # | Project | Case 1 (simple) → Case 2 (multi-stage) |
|---|---|---|
| 8 | ⚛️ React frontend | node dev server, 230 MB → nginx + static build, 52 MB |
| 9 | ☕ Java / Spring Boot | prebuilt jar + JRE → JDK build stage + **layered jar** |
| 10 | ⚛️ + ☕ React & Java | two ports with CORS → one origin behind an nginx proxy |
| 11 | ⚛️ + 🐍 React & Python | uvicorn `--reload` as root → wheels + tests + gunicorn non-root |
| 12 | ⚛️ + 🐹 React & Go | full Go SDK, 380 MB → static binary, 18 MB → `FROM scratch`, 9 MB |
| 13 | 🗄️ Databases ×6 | MySQL · MongoDB · Redis · DynamoDB Local · Cassandra · Neo4j — each with init scripts, healthchecks, volumes, backups and a GUI tool |

### 3. Quick revision — `03-CHEATSHEET.md`
Every instruction, every flag, every CLI command, and the 10 rules — on one page.

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish%20Kumar%20Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn → <https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260>
🐙 GitHub → <https://github.com/3558Bhk>

*Built for engineers who learn by breaking things on purpose.*

</div>
