# 🥚 PROJECT 1 — "Hello, Docker" (your very first image)

> **Part of the Docker Learning Path.** Read `01-DOCKERFILE-GUIDE.md` (Parts 1–3) first.
>
> ⏱️ **Time:** 20–30 minutes · 🎓 **Level:** absolute beginner
> 🎯 **Instructions learned:** `FROM`, `RUN`, `CMD` · **Concepts:** build vs run, layers, caching, overriding CMD

---

## 1. The idea

Build the smallest possible image that prints a message. No application code, no framework — just the raw Dockerfile lifecycle. By the end you will have *seen* the difference between **build time** and **run time**, which is the foundation of everything else.

---

## 2. Files to create

Create a folder and one file:

```
01-hello-docker/
└── Dockerfile
```

### `Dockerfile` — version 1 (the absolute minimum)

```dockerfile
FROM alpine:3.22
CMD ["echo", "Hello from my first Docker image!"]
```

That's it. Two lines. `FROM` is the **only mandatory** instruction in a Dockerfile.

---

## 3. Build and run

```bash
cd 01-hello-docker

docker build -t hello:v1 .
#              │      │ │
#              │      │ └── the BUILD CONTEXT (this folder)
#              │      └──── tag = name:version
#              └─────────── "tag this image"

docker run --rm hello:v1
#          │     └── the image to run
#          └── delete the container automatically when it exits
```

**Expected output:**
```
Hello from my first Docker image!
```

🎉 You just built and ran your first image.

### What actually happened?

```
Dockerfile  --docker build-->  image "hello:v1"  --docker run-->  container  -->  output  -->  deleted (--rm)
   (recipe)                       (cake)                        (a slice)
```

Check what you now have on your machine:

```bash
docker images hello          # the image, its ID, size (~8 MB)
docker ps -a                 # NO containers listed — because --rm deleted it
```

Run it **without** `--rm` and look again:

```bash
docker run hello:v1
docker ps -a                 # now you SEE a stopped container (Exited (0))
docker rm $(docker ps -aq)   # delete all stopped containers
```

---

## 4. Grow it step by step (v2 → v5)

Do **all** of these. Each one teaches a different thing.

### v2 — add `RUN` and witness build-time vs run-time

```dockerfile
FROM alpine:3.22

# ---- these run NOW, during `docker build` ----
RUN echo ">>> This line runs at BUILD time"
RUN apk add --no-cache figlet

# ---- this runs LATER, when `docker run` starts the container ----
CMD ["figlet", "Hello Docker"]
```

```bash
docker build -t hello:v2 .
```

👀 **Watch the build output.** You will literally see `>>> This line runs at BUILD time` printed *during the build*.

```bash
docker run --rm hello:v2
```

```
 _   _      _ _         ____             _
| | | | ___| | | ___   |  _ \  ___   ___| | _____ _ __
| |_| |/ _ \ | |/ _ \  | | | |/ _ \ / __| |/ / _ \ '__|
|  _  |  __/ | | (_) | | |_| | (_) | (__|   <  __/ |
|_| |_|\___|_|_|\___/  |____/ \___/ \___|_|\_\___|_|
```

👀 Notice: the `>>>` line did **NOT** print again. It ran once, at build time, and its *result* was frozen into the image.

> **THE rule to remember:**
> `RUN` = happens while **building** the image.
> `CMD` = happens while **running** the container.

### v3 — inspect the layers

```bash
docker history hello:v2
docker images hello
docker inspect hello:v2 --format '{{json .Config.Cmd}}'
```

`docker history` shows one row per layer with its size. You'll see:

| CREATED BY | SIZE |
|---|---|
| `CMD ["figlet","Hello Docker"]` | 0 B ← metadata, no layer |
| `RUN apk add --no-cache figlet` | ~2 MB |
| `RUN echo ">>> ..."` | 0 B |
| `FROM alpine:3.22` | ~8 MB |

### v4 — prove the layer cache with your own eyes

```bash
docker build -t hello:v4 .     # 1st build: every step executes
docker build -t hello:v4 .     # 2nd build: EVERY step says "CACHED" — finishes in <1 second
```

Now experiment:

1. Change **only the `CMD`** text → rebuild → `apk add` is still `CACHED` (it's above the change). ⚡
2. **Move the `CMD` line above `RUN apk add`**, change the CMD text → rebuild → `apk add` **re-runs**. 🐢

> **Conclusion:** a cache hit stops at the *first* changed instruction. Everything **below** it must be rebuilt.
> **That's why you put slow, rarely-changing steps (dependency installs) at the TOP and your code at the BOTTOM.**

### v5 — override `CMD` from the command line

```bash
docker run --rm hello:v2                              # runs the CMD (figlet banner)
docker run --rm hello:v2 echo "I replaced the CMD"    # CMD is thrown away entirely
docker run --rm -it hello:v2 sh                       # -it = interactive; you're now INSIDE alpine
```

Inside that shell:
```sh
cat /etc/os-release        # you are in Alpine Linux
figlet "inside!"           # the tool we installed at build time is here
whoami                     # root  ← we'll fix that in Project 5
ls -la /
exit                       # back to your own machine
```

> `-i` = keep STDIN open, `-t` = allocate a terminal. Together (`-it`) they give you an interactive shell.

---

## 5. ✅ Check yourself

Say the answers out loud before moving on:

1. Which instructions ran during `docker build`, and which during `docker run`?
2. Why did the second identical build finish in under a second?
3. What does the `.` at the end of `docker build -t hello .` mean?
4. Why did `docker run hello:v2 echo hi` print `hi` instead of the figlet banner?
5. What's the difference between `docker ps` and `docker ps -a`?

<details>
<summary>👉 Answers</summary>

1. `FROM` and both `RUN`s executed at **build** time; `CMD` executed at **run** time.
2. **Layer caching** — every instruction was unchanged, so Docker reused all existing layers (`CACHED`).
3. The **build context** — "send every file in this folder (recursively) to the Docker engine". Only files inside it can be `COPY`'d.
4. Anything you type after the image name **replaces** `CMD` completely.
5. `docker ps` = running containers only. `docker ps -a` = all, including stopped/exited ones.
</details>

---

## 6. 🔨 Extra Tasks (do all 5)

### ▶ Task 1.1 — Switch the base image and measure

Create a second file, `Dockerfile.ubuntu`:

```dockerfile
FROM ubuntu:24.04
RUN echo ">>> built on ubuntu"
CMD ["echo", "Hello from Ubuntu"]
```

```bash
docker build -f Dockerfile.ubuntu -t hello:ubuntu .
docker images hello
```

**Questions to answer:** Which image is bigger and by roughly how much? Why does `alpine` need `apk` while `ubuntu` would need `apt-get`? When would you still choose Ubuntu over Alpine?

<details>
<summary>👉 Answer</summary>

Alpine ≈ **8 MB**, Ubuntu ≈ **78 MB** (~10× bigger). Alpine is a minimal distro built on **musl libc** and **BusyBox** (one binary provides `sh`, `ls`, `cat`, etc.), and its package manager is `apk`. Ubuntu is a full Debian-based distro with glibc, systemd tooling, locales, docs and hundreds of packages preinstalled; it uses `apt-get`.
Choose **Ubuntu/Debian** when: you need glibc (some precompiled Python wheels, Oracle JDK, certain native libs fail on musl), you need many `apt` packages, or your team's troubleshooting skills assume a full distro. Choose **Alpine** for size, speed and a smaller attack surface.
</details>

---

### ▶ Task 1.2 — Print a build timestamp

```dockerfile
FROM alpine:3.22
RUN date -u > /built-at.txt
CMD ["cat", "/built-at.txt"]
```

```bash
docker build -t hello:time . && docker run --rm hello:time
docker build -t hello:time . && docker run --rm hello:time          # same time!
docker build --no-cache -t hello:time . && docker run --rm hello:time   # NEW time
```

**Question:** Why does the timestamp only change with `--no-cache`?

<details>
<summary>👉 Answer</summary>

`RUN date -u > /built-at.txt` is **cached**. On the second build Docker sees the instruction text is unchanged and reuses the old layer — so the file keeps the *original* build time. `--no-cache` forces every layer to be re-executed, so `date` runs again.
**Real-world consequence:** a timestamp is non-deterministic content inside a cached layer. If you truly need the build time inside the image, pass it in as a build argument instead:
`docker build --build-arg BUILD_DATE=$(date -u +%FT%TZ) -t app .` with `ARG BUILD_DATE` + `LABEL org.opencontainers.image.created="${BUILD_DATE}"`.
</details>

---

### ▶ Task 1.3 — Make it fail on purpose (learn to read errors)

Build each of these and read the error message carefully — Docker points at the exact line.

```dockerfile
# failure A — instruction typo
FROOM alpine:3.22
CMD ["echo","hi"]
```
```dockerfile
# failure B — unknown shell command
FROM alpine:3.22
RUN this-command-does-not-exist
```
```dockerfile
# failure C — package not found
FROM alpine:3.22
RUN apk add --no-cache nosuchpackage123
```
```dockerfile
# failure D — bad exec-form JSON
FROM alpine:3.22
CMD ['echo', 'hi']
```

<details>
<summary>👉 Answers</summary>

- **A** → `unknown instruction: FROOM`. Docker highlights the line number. Instructions are case-insensitive but must be spelled correctly.
- **B** → `this-command-does-not-exist: not found`, then `executor failed running [/bin/sh -c ...]: exit code: 127`. **Exit code 127 = command not found.** The build stops at that layer.
- **C** → `ERROR: unable to select packages: nosuchpackage123 (no such package)`, exit code 1.
- **D** → **No error!** Single quotes make Docker treat it as **shell form**, so it runs `/bin/sh -c "['echo', 'hi']"` → `sh: ['echo',: not found`. This is a silent trap: exec form **must** use double quotes.

Useful exit codes: `0` success · `1` general error · `126` not executable (permission) · `127` command not found · `137` = 128+9 → killed by `SIGKILL` (often OOM).
</details>

---

### ▶ Task 1.4 — Two `RUN`s vs one `RUN`

**Image A (two layers):**
```dockerfile
FROM alpine:3.22
RUN apk add --no-cache curl
RUN apk add --no-cache git
```

**Image B (one layer):**
```dockerfile
FROM alpine:3.22
RUN apk add --no-cache curl git
```

```bash
docker build -f Dockerfile.A -t hello:two-runs .
docker build -f Dockerfile.B -t hello:one-run .
docker images hello
docker history hello:two-runs
docker history hello:one-run
```

**Question:** Which is smaller, and why?

<details>
<summary>👉 Answer</summary>

**B (one `RUN`) is smaller** — usually by a few MB. Reasons:
1. Each `RUN` creates a separate layer with its own overhead and its own copy of the package index/metadata written during that step.
2. In A, the first layer writes apk's index/cache state; the second layer writes it again. Neither can remove what the other already committed — **layers are read-only**, so a later `RUN rm` never shrinks an earlier layer.
3. In B, install and cleanup happen in a single filesystem transaction, so temp files never get committed at all.

**Rule:** `install → use → clean up` all inside **one** `RUN`, joined with `&&` and split with `\` for readability:
```dockerfile
RUN apk add --no-cache build-base \
 && make \
 && apk del build-base
```
</details>

---

### ▶ Task 1.5 — One image, three containers at the same time

```dockerfile
FROM alpine:3.22
CMD ["sh", "-c", "echo Container $(hostname) says hello; sleep 30"]
```

```bash
docker build -t hello:multi .

docker run -d --name c1 hello:multi
docker run -d --name c2 hello:multi
docker run -d --name c3 hello:multi

docker ps                          # three containers, ONE image
docker logs c1
docker logs c2
docker logs c3
docker stats --no-stream           # CPU/RAM per container
docker stop c1 c2 c3
docker rm c1 c2 c3
docker images hello:multi          # the image is still there, untouched
```

**Question:** What does this prove about the relationship between images and containers?

<details>
<summary>👉 Answer</summary>

An **image is a read-only template; a container is an independent running copy of it.** One image produced three isolated containers, each with its own hostname, filesystem writes, logs and lifecycle. Stopping/removing containers did **not** damage the image — you can start three more instantly.
This is exactly why Docker scales so well: build once, run thousands of identical isolated instances. It's also why any data you write inside a container **disappears when the container is removed** — which is the problem Project 5 (volumes) solves.
</details>

---

## 7. 🧹 Clean up

```bash
docker rm -f $(docker ps -aq) 2>/dev/null
docker rmi hello:v1 hello:v2 hello:v4 hello:time hello:two-runs hello:one-run hello:multi hello:ubuntu 2>/dev/null
docker system df               # see what's still taking disk space
```

---

## ➡️ Next

**`05-PROJECT-2-static-site.md`** — `COPY`, `ADD`, `WORKDIR`, `.dockerignore` and your first website served from a container.

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish%20Kumar%20Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn → <https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260>
🐙 GitHub → <https://github.com/3558Bhk>

*Built for engineers who learn by breaking things on purpose.*

</div>
