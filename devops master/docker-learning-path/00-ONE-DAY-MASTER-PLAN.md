# ⚡ MASTER DOCKER IN ONE DAY — The Hour-by-Hour Battle Plan

> Times are **IST** for a 9:00 AM start. Shift the whole schedule if you start later.
> Total: **12 hours wall-clock, ~9.5 hours hands-on.**

---

## 🎯 First, the honest truth

| Claim | Reality |
|---|---|
| "Master Docker in a day" | ❌ Not possible. Mastery = ~40 repetitions of the same cycle on real apps. |
| "Become **competent** in Docker in a day" | ✅ **Absolutely possible**, if you type every command. |
| What "competent" means by 9 PM tonight | You can containerise any app you're given, write a multi-stage Dockerfile from memory, debug a broken container, run a multi-service stack with Compose, and answer the 10 standard interview questions. |

**The one rule that decides whether this works:**

> 🚨 **You must TYPE every command. Reading gives you 10% of this. Typing, breaking it, and fixing it gives you 90%.**
> If you find yourself scrolling instead of typing — stop, go back, and run it.

**The second rule:** your files total 65,000 words. **Do not read them.** Each block below tells you exactly which *section* to read (5–10 minutes) and then gives you the commands to run (30–60 minutes). Read to explain what you just saw — never the other way round.

---

## ✅ BLOCK 0 · 9:00 – 9:30 · Pre-flight (do NOT skip)

### 0.1 Run this checklist

```bash
docker --version            # need 24+ (28.x is current)
docker compose version      # need v2.x  ← "docker compose", NOT "docker-compose"
docker run hello-world      # MUST print "Hello from Docker!"
docker info --format '{{.ServerVersion}} / {{.OSType}} / {{.NCPU}} CPUs / {{.MemTotal}}'
docker system df
```

**All five work → go to Block 1.** Anything fails → fix it now, or the whole day is lost.

### 0.2 Fix table

| Symptom | Fix |
|---|---|
| `docker: command not found` | Docker isn't installed, or not on `PATH`. Linux: `curl -fsSL https://get.docker.com \| sh`. Windows/Mac: install **Docker Desktop**. |
| `permission denied ... docker.sock` (Linux) | `sudo usermod -aG docker $USER` then **log out and back in** (or reboot). Test with `docker ps`, *not* `sudo docker ps`. |
| `Cannot connect to the Docker daemon` | Docker Desktop isn't running (Win/Mac) → start it and wait for the whale to stop animating. Linux → `sudo systemctl start docker && sudo systemctl enable docker`. |
| Windows: `WSL 2 installation is incomplete` | Admin PowerShell: `wsl --install`, reboot, then update the kernel: `wsl --update`. In Docker Desktop → Settings → General → tick **Use the WSL 2 based engine**. |
| Mac Apple Silicon: image runs but `exec format error` | You pulled an amd64 image. Add `--platform linux/amd64` to `docker run`/`docker build`, or use `-alpine`/multi-arch tags. |
| `hello-world` works but `docker compose` doesn't | Old Docker. Update Docker Desktop, or install the plugin: `sudo apt-get install docker-compose-plugin`. |
| Disk full / very slow | `docker system prune -a` (⚠️ removes unused images) and give Docker Desktop more disk in Settings → Resources. |

### 0.3 Machine requirements

- **RAM:** 8 GB minimum, 16 GB comfortable. Project 13's Cassandra+Neo4j need more — skip those today.
- **Disk:** 20 GB free.
- **Windows:** WSL2 backend, and run your terminal **inside** Ubuntu/WSL, not PowerShell, for the `$(pwd)` and `watch` commands to work.
- Close Chrome tabs, Slack and your IDE's indexing. You need the RAM and the attention.

### 0.4 Set up your workspace

```bash
mkdir -p ~/docker-day && cd ~/docker-day
mkdir -p p1 p2 p3 p4 p5 p6 p7 cap
```

### 0.5 Your recovery commands (pin these)

```bash
docker ps -a                                   # what's running / what crashed
docker logs -f <name>                          # WHY it crashed
docker rm -f $(docker ps -aq) 2>/dev/null      # delete every container
docker rmi $(docker images -q) -f 2>/dev/null  # delete every image
docker system prune -a --volumes -f            # ☠️ full factory reset (deletes data)
```

> If you ever get lost or your machine gets weird: run the last line, take a breath, and restart the current block. It costs 2 minutes and saves 30.

---

## 🧠 BLOCK 1 · 9:30 – 10:45 (75 min) · The 5 mental models

**Read:** `01-DOCKERFILE-GUIDE.md` → **Part 1 only** (sections 1.1 → 1.5). ~12 minutes.

Then **say these out loud in your own words** — if you can't, re-read that subsection:

1. What problem Docker solves (one sentence).
2. Container vs VM.
3. Dockerfile = recipe, image = cake, container = slice.
4. Layers, and why a change invalidates everything below it.
5. The build context (the `.` in `docker build -t x .`).

**Do (15 min) — prove each model to yourself:**

```bash
cd ~/docker-day/p1

# model 3: one image, three containers
docker pull alpine:3.22
docker run -d --name a1 alpine:3.22 sleep 300
docker run -d --name a2 alpine:3.22 sleep 300
docker run -d --name a3 alpine:3.22 sleep 300
docker ps                                   # 3 containers
docker images alpine                        # 1 image
docker exec a1 hostname; docker exec a2 hostname   # different → isolated
docker rm -f a1 a2 a3; docker images alpine        # image untouched

# model 4: layers are visible
docker history alpine:3.22
docker inspect alpine:3.22 --format '{{len .RootFS.Layers}} layers'

# model 5: the build context
mkdir ctx && cd ctx && echo hi > a.txt && mkdir sub && echo hi > sub/b.txt
printf 'FROM alpine\nCOPY . /x\nRUN ls -la /x /x/sub\n' > Dockerfile
docker build --progress=plain -t ctxdemo . 2>&1 | grep -E 'transferring context|total|b.txt'
echo "node_modules" > .dockerignore && mkdir -p node_modules && head -c 5000000 /dev/urandom > node_modules/junk
docker build --progress=plain -t ctxdemo . 2>&1 | grep 'transferring context'   # bigger!
echo "node_modules" >> .dockerignore
docker build --progress=plain -t ctxdemo . 2>&1 | grep 'transferring context'   # small again ✅
cd ..
```

**✅ Checkpoint 1:** you can explain why the second `transferring context` number jumped and the third dropped.

---

## 📖 BLOCK 2 · 10:45 – 12:15 (90 min) · The instruction reference

**Read `01-DOCKERFILE-GUIDE.md` Part 3 — but only these, in this order (≈55 min):**

| Priority | Section | Why it's non-negotiable |
|---|---|---|
| 🔴 | 3.1 `FROM` | base image choice = 90% of your image size |
| 🔴 | 3.2 `RUN` | build-time execution, `&&` chaining, cleanup in the same layer |
| 🔴 | 3.3 `CMD` + 3.4 `ENTRYPOINT` | the #1 confusion in all of Docker |
| 🔴 | **3.18 shell form vs exec form** | PID 1 / SIGTERM. Interviewers ask this constantly. |
| 🔴 | 3.5 `COPY` (+ 3.6 `ADD`) | trailing slashes, `--from`, `--chown` |
| 🔴 | 3.7 `WORKDIR`, 3.8 `EXPOSE` | EXPOSE ≠ publishing a port |
| 🔴 | 3.9 `ENV` vs 3.10 `ARG` | build-time vs run-time |
| 🟡 | 3.12 `USER`, 3.14 `HEALTHCHECK` | production basics |
| 🟡 | 3.19 multi-stage (skim), 3.20 `.dockerignore` | you'll do it properly in Block 6 |
| ⚪ | 3.11, 3.13, 3.15, 3.16, 3.17 | **skip today** — glance at the summary card 3.21 |

**Also read (5 min):** Part 2.2 — the BUILD-time vs RUN-time table. Memorise it.

**Do (30 min) — write a Dockerfile from memory, no copy-paste:**

```bash
cd ~/docker-day/p2 && mkdir -p site && cd ..
```

Create `p2/site/index.html`:
```html
<!doctype html><meta charset="utf-8"><title>Day 1</title>
<h1>🐳 I wrote this Dockerfile from memory</h1>
```

Now create `p2/Dockerfile` **by typing it, from recall** — it must contain, in this order:
`FROM` (an alpine-based web server) · `LABEL` · `WORKDIR` · `COPY` · `ENV` · `EXPOSE` · `USER` · `HEALTHCHECK` · `CMD`.

Then:
```bash
cd ~/docker-day/p2
docker build -t day1:v1 .
docker run -d --name day1 -p 8080:8080 day1:v1
docker ps                                   # wait for (healthy)
curl -I localhost:8080
docker exec day1 whoami                     # must NOT be root
docker inspect day1:v1 --format '{{json .Config.Env}}'
docker history day1:v1 --human | head
docker rm -f day1
```

**If you got stuck writing it from memory** — that's the most valuable information of your day. Re-read the sections you couldn't recall, then **delete your file and write it again from scratch.** Repeat until it flows.

**✅ Checkpoint 2:** you wrote a 9-instruction Dockerfile from recall, it built, it served HTTP, it ran as non-root, and it reported `healthy`.

---

## 🥚 BLOCK 3 · 12:15 – 13:15 (60 min) · Projects 1 + 2

**Files:** `04-PROJECT-1-hello-docker.md` and `05-PROJECT-2-static-site.md`

### Fast track — Project 1 (25 min)

Do **§3 (build & run)** and **§4 (v2 → v5)** exactly as written. **Skip §6 tasks today** except this one, which is essential:

```bash
# Task 1.4 compressed: two RUNs vs one RUN — the layer lesson in 60 seconds
cd ~/docker-day/p1
printf 'FROM alpine:3.22\nRUN apk add --no-cache curl\nRUN apk add --no-cache git\n' > Dockerfile.A
printf 'FROM alpine:3.22\nRUN apk add --no-cache curl git\n' > Dockerfile.B
docker build -q -f Dockerfile.A -t two . && docker build -q -f Dockerfile.B -t one .
docker images --format '{{.Repository}} {{.Size}}' | grep -E '^(one|two) '
docker history two | head -5
```
Then answer out loud: *why is `one` smaller, and why can't a later `RUN rm` fix `two`?*

**The four things you must take away from Project 1:**
1. `RUN` = build time, `CMD` = run time.
2. Second identical build = all `CACHED`.
3. Anything after the image name **replaces** `CMD`.
4. One image → many independent containers.

### Fast track — Project 2 (35 min)

Do **§2 (files)**, **§3 (build & run)**, and **all three experiments in §4**. The experiments are the whole point — they're 5 minutes and they permanently fix `EXPOSE` vs `-p` in your head.

```bash
# §4 compressed — run all three, in order
docker build -t mysite:v1 .

# A: EXPOSE is documentation only
docker run -d --rm --name t1 -p 8080:80 mysite:v1 && curl -sI localhost:8080 | head -1 && docker rm -f t1

# B: -p is what actually opens the port
docker run -d --rm --name t2 mysite:v1 && (curl -sI --max-time 3 localhost:8080 || echo "❌ refused — as expected") \
  && docker exec t2 wget -qO- http://localhost/ | head -2 && docker rm -f t2

# C: images are immutable
docker run -d --rm --name t3 -p 8080:80 mysite:v1
echo "<h1>CHANGED</h1>" >> site/index.html
curl -s localhost:8080 | grep CHANGED || echo "❌ not there — image is frozen (correct)"
docker build -q -t mysite:v1 . && docker rm -f t3
docker run -d --rm --name t3 -p 8080:80 mysite:v1 && curl -s localhost:8080 | grep CHANGED && echo "✅ now it is"
docker rm -f t3
```

**Skip:** Tasks 2.1–2.5 today. Do 2.3 (`.dockerignore` proof) if you have 5 spare minutes — you already did the same experiment in Block 1.

**🍛 LUNCH · 13:15 – 14:00.** Step away from the screen. Your brain consolidates the layer model right now.

---

## 🐥 BLOCK 4 · 14:00 – 15:00 (60 min) · Projects 3 + 4 — the highest-value hour

> If you only remember two things from today, make them **`ARG` vs `ENV`** and **`ENTRYPOINT` vs `CMD`**. These are asked in essentially every Docker interview.

### Fast track — Project 3 (`06-PROJECT-3-config-and-env.md`, 25 min)

Do **§2 (files)**, **§3 (build & run + "one image, many personalities")**, and the **"Prove ARG ≠ ENV"** box. Skip Tasks 3.1–3.5.

```bash
cd ~/docker-day/p3        # paste app.py, requirements.txt, dev.env, Dockerfile from the file
docker build -t configapp:1.0 .
docker run -d --name c-prod -p 8000:8000 configapp:1.0
docker run -d --name c-stage -p 8001:8000 -e APP_ENV=staging -e GREETING="STAGING ⚠️" configapp:1.0
docker run -d --name c-dev -p 8002:8000 --env-file dev.env configapp:1.0
for p in 8000 8001 8002; do echo "--- :$p"; curl -s localhost:$p/version; done

# THE experiment — ARG dies, ENV survives
docker run --rm configapp:1.0 python -c \
 "import os;print('APP_VERSION=',repr(os.environ.get('APP_VERSION')));print('BUILD_DATE=',repr(os.environ.get('BUILD_DATE')))"
```

Say out loud: **`ARG` is build-time and disappears; `ENV` is baked in and survives into the container; you promote one to the other with `ENV X=${X}`.**

### Fast track — Project 4 (`07-PROJECT-4-cli-entrypoint.md`, 35 min)

Do **§2 (files)**, **§3 (build all four)**, and **the 6 experiments in §4**. Then **§5 (PID 1 and signals)** — that one is the difference between "knows syntax" and "understands containers".

```bash
cd ~/docker-day/p4        # paste tool.py, entrypoint.sh, and the 4 Dockerfiles
docker build -q -f Dockerfile.cmd-only        -t t-cmd   .
docker build -q -f Dockerfile.entrypoint-only -t t-entry .
docker build -q -f Dockerfile.both            -t t-both  .
docker build -q -f Dockerfile.shellform       -t t-shell .

# the 6 experiments — predict the output BEFORE each one, then check
docker run --rm t-cmd                            ; echo "-----"
docker run --rm t-cmd   greet Ravi               ; echo "----- 💥 CMD replaced entirely"
docker run --rm t-entry                          ; echo "----- 💥 no default args"
docker run --rm t-entry greet Ravi               ; echo "----- ✅ appended"
docker run --rm t-both                           ; echo "----- ✅ ENTRYPOINT + CMD defaults"
docker run --rm t-both  greet Ravi               ; echo "----- ✅ defaults replaced, entrypoint kept"

# PID 1 / SIGTERM — the money shot
docker run -d --name sig-shell t-shell wait >/dev/null
docker run -d --name sig-exec  t-both  wait >/dev/null
docker top sig-shell; echo "---"; docker top sig-exec
time docker stop -t 3 sig-shell      # hangs the full 3s then SIGKILL
time docker stop -t 3 sig-exec       # instant, clean
docker logs sig-exec; docker rm -f sig-shell sig-exec
```

**✅ Checkpoint 3:** you can fill in this table from memory, without looking:

| | `docker run img` | `docker run img a b` |
|---|---|---|
| `CMD ["x","y"]` | ? | ? |
| `ENTRYPOINT ["x"]` | ? | ? |
| `ENTRYPOINT ["x"]` + `CMD ["y"]` | ? | ? |

---

## 🐓 BLOCK 5 · 15:00 – 16:15 (75 min) · Projects 5 + 6

### Fast track — Project 5 (`08-PROJECT-5-volumes-health-user.md`, 35 min)

Do **§2, §3**, then **§4 (THE BIG EXPERIMENT)** and **§6 (break the healthcheck)**. Those two are the entire lesson. Skip §5 and Tasks 5.1–5.5.

```bash
cd ~/docker-day/p5        # paste notes_app.py, healthcheck.sh, Dockerfile
docker build -t notes:v1 .
docker volume create notes-data
docker run -d --name n1 -p 8000:8000 -v notes-data:/app/data notes:v1
watch -n 3 'docker ps --format "{{.Names}} {{.Status}}"'   # starting → healthy (Ctrl+C)

curl -X POST localhost:8000/notes -H 'Content-Type: application/json' -d '{"text":"survive me"}'
curl -s localhost:8000/notes

# 💥 THE experiment: container dies, data lives
docker rm -f n1
docker run -d --name n2 -p 8000:8000 -v notes-data:/app/data notes:v1
curl -s localhost:8000/notes        # ✅ still there

# ☠️ and the destructive version — run it ONCE so you never do it by accident
docker rm -f n2 && docker volume rm notes-data
docker run -d --name n3 -p 8000:8000 -v notes-data:/app/data notes:v1
curl -s localhost:8000/notes        # → []  gone forever
docker exec n3 whoami               # appuser, not root ✅
docker rm -f n3
```

### Fast track — Project 6 (`09-PROJECT-6-multistage-build.md`, 40 min)

Do **§2 (files)**, **§4 (build all four + measure)**, and **§5 (`--target` debugging)**. Skip Tasks 6.1–6.5 today.

```bash
cd ~/docker-day/p6        # paste app/, tests/, requirements.txt and the 4 Dockerfiles
docker build -q -f Dockerfile.naive      -t app:naive  .
docker build -q -f Dockerfile.multistage -t app:multi  .
docker build -q -f Dockerfile.cached     -t app:cached .
docker build -q -f Dockerfile.final      -t app:final  .

docker images app --format "table {{.Tag}}\t{{.Size}}"      # 🤯 the payoff
docker history app:naive --human --format "table {{.Size}}\t{{.CreatedBy}}" | head -12
docker run --rm app:final python -c "import pytest" ; echo "exit=$?  (non-zero = pytest NOT shipped ✅)"
docker run --rm app:final whoami
docker run --rm app:final ls /app

# rebuild speed — the other half of the payoff
sed -i '1i # touched' app/main.py
time docker build -q -f Dockerfile.cached -t app:cached2 .
```

**Tea break · 16:15 – 16:30.**

**✅ Checkpoint 4:** you can state, with real numbers from your own machine, how much smaller `app:multi` is than `app:naive`, and *why* — in terms of which stage's filesystem was discarded.

---

## 🦉 BLOCK 6 · 16:30 – 17:30 (60 min) · Project 7 — Docker Compose

**File:** `10-PROJECT-7-compose-stack.md`

Do **§2 (files)**, **§3 (run the stack)**, and **all of §4 (the four concepts)**. Skip Tasks 7.1–7.5.

```bash
cd ~/docker-day/p7        # paste api/, web/, db-init/, docker-compose.yml, .env
docker compose config >/dev/null && echo "✅ YAML valid"
docker compose up -d --build --wait --timeout 240
docker compose ps                                   # 4 services, all (healthy)

curl -s localhost:8000/net   | python3 -m json.tool  # 🔑 service DNS
curl -s localhost:8000/items | python3 -m json.tool  # postgres data
curl -s localhost:8000/items | python3 -m json.tool  # ← second call: "source": "redis-cache"
curl -s localhost:8080/ | head -3                    # web UI

docker compose exec api sh -c 'getent hosts db cache api web'   # names → IPs
docker compose exec db psql -U appuser -d appdb -c 'SELECT count(*) FROM items;'
docker compose exec cache redis-cli KEYS '*'
docker compose logs --tail 20 api
docker compose stats --no-stream

# 💥 the persistence lesson
docker compose down          && docker compose up -d --wait && curl -s localhost:8000/items | head -3   # data SURVIVED
docker compose down -v       && docker compose up -d --wait && curl -s localhost:8000/items | head -3   # data GONE (re-seeded)
```

**The four things to be able to say:**
1. Containers reach each other by **service name** (`db`), never `localhost`.
2. `depends_on: {condition: service_healthy}` waits for *readiness*, not just start order.
3. Networks **isolate** — `web` can't reach `db` unless they share one.
4. `down` keeps named volumes; `down -v` destroys them.

---

## 🏆 BLOCK 7 · 17:30 – 19:00 (90 min) · Capstone speedrun

**File:** `02-CAPSTONE-END-TO-END.md`

You are **not** going to write this from scratch today. You're going to **run it** and understand every line.

| Time | Do |
|---|---|
| 15 min | Read **Section A** — the 10 requirements + Definition of Done. This is what a real ticket looks like. |
| 10 min | Skim **Section B** — just note *how many* files there are and that the app is stdlib-only. Don't read the code. |
| 45 min | **Section C** — create the files (`api/Dockerfile`, `web/Dockerfile`, `web/nginx.conf`, `docker-compose.yml`, `Makefile`, the 3 scripts) and run **§C.9 "Full run — the complete command sequence"** top to bottom. |
| 20 min | Read **§C.8** — requirement by requirement, and *run* the proof command for requirements **1, 2, 4 and 7** only. |

```bash
cd ~/docker-day/cap
# ...create the Section C files...
cp .env.example .env && sed -i 's/change-me-in-production/Str0ng-Passw0rd!/' .env
chmod +x scripts/*.sh

make build APP_VERSION=1.0.0
make test                    # unit tests inside the builder stage
make up                      # --wait until everything is healthy
make smoke                   # 20+ assertions → must print ✅ PASSED

# the four proofs that matter
docker images tasknest-api                                    # Req 1: < 80 MB
docker compose exec api whoami                                # Req 2: app (non-root)
docker compose stop cache && sleep 5 \
  && curl -s -o /dev/null -w 'health=%{http_code} ' localhost:8080/api/health \
  && curl -s -o /dev/null -w 'ready=%{http_code}\n' localhost:8080/api/ready   # Req 4: 200 / 503
docker compose start cache
docker history tasknest-api:1.0.0 --no-trunc | grep -iE 'password|secret|token' && echo "❌ LEAK" || echo "✅ Req 7: no secrets in history"

make backup && make nuke && make up && make restore           # Req 8: the full lifecycle
make down
```

**Dinner · 19:00 – 19:30.**

---

## 📝 BLOCK 8 · 19:30 – 21:00 (90 min) · Prove it stuck

### 8.1 The blank-page test (30 min) — the single best exercise

Close every file. Open an empty editor. **From memory only**, write a production-grade Dockerfile for an app of your choice that includes:

`# syntax` directive · pinned `FROM` · `ARG` + `ENV` · OCI `LABEL`s · `WORKDIR` · manifest-first `COPY` · `RUN` install with cleanup in the same layer · a second `COPY` for source · a **build stage** and a **runtime stage** with `COPY --from` · non-root `USER` · `EXPOSE` · `STOPSIGNAL` · `HEALTHCHECK` · exec-form `CMD`.

Plus a matching `.dockerignore`.

**Then** open `03-CHEATSHEET.md` §8 (production template) and diff your answer against it. Every gap you find is a gap that would have shown up at work. Write the missing bits on a physical sticky note.

### 8.2 The 40-question rapid quiz (30 min)

Answer out loud or on paper. **Answers are at the bottom of this file.** Score yourself honestly.

**Concepts**
1. Image vs container, one sentence each.
2. What does the `.` mean in `docker build -t app .`?
3. Can you `COPY ../secret.txt` into an image? Why not?
4. Why doesn't `RUN rm bigfile.tar.gz` in a later layer shrink the image?
5. What is a 0-byte layer, and which instructions create one?
6. Container vs VM — three differences.

**Instructions**
7. Which instruction is mandatory in every Dockerfile?
8. `RUN` vs `CMD` — when does each execute?
9. Why is `RUN npm start` wrong?
10. `COPY src /app/` — do you get `/app/src/...` or `/app/...`?
11. Two things `ADD` does that `COPY` doesn't. Which should you normally use?
12. Does `EXPOSE 8080` make port 8080 reachable from your browser?
13. `ENV` vs `ARG` — which survives into the running container?
14. How do you make an `ARG` visible at runtime?
15. What does `WORKDIR` do that `RUN cd /app` doesn't?
16. What does `USER appuser` affect, and what does it *not* protect against?
17. `HEALTHCHECK` exit codes: what do 0 and 1 mean?
18. What is `--start-period` for?
19. Does Docker restart an unhealthy container automatically?
20. What does `STOPSIGNAL` control?
21. Is `MAINTAINER` still recommended?

**Forms & semantics**
22. Shell form vs exec form — write both for `CMD`.
23. Why does exec form matter for `docker stop`?
24. Does `$HOME` expand in exec form? How do you get it to?
25. Why is `CMD ['a','b']` (single quotes) a silent bug?
26. `docker run img arg` — what happens with CMD-only? With ENTRYPOINT-only? With both?
27. How do you get a shell into an image whose ENTRYPOINT is a binary?
28. Why must a shell entrypoint script use `exec`?

**Multi-stage & size**
29. What happens to stage 1's filesystem when the build ends?
30. Name three things that must never reach the final image.
31. What does `docker build --target builder` do, and when do you use it?
32. What does `RUN --mount=type=cache` give you that a normal `RUN` doesn't?
33. Why must `COPY requirements.txt .` come before `COPY . .`?
34. Which two `COPY` flags avoid an extra `chown` layer?

**Operations**
35. `docker stop` vs `docker kill`.
36. Exit code 137 means what? 127?
37. `docker compose down` vs `down -v`.
38. Inside Compose, why is `localhost` always wrong for reaching another service?
39. Name four commands you'd use, in order, to debug a container that exits immediately.
40. Where do secrets go — and name two places they must never go.

### 8.3 Gap remediation (30 min)

For every question you got wrong: find the section in `01-DOCKERFILE-GUIDE.md` Part 3 or the relevant project file, **run the command that demonstrates it**, and add one line to your sticky note.

**Scoring:** 34+/40 = you had a genuinely excellent day. 26–33 = solid, redo the blocks you missed. <26 = you read instead of typing — repeat Blocks 3–6 tomorrow.

---

## 🚫 What is NOT covered on Day 1 (be honest with yourself)

| Topic | Where it lives | Why it's skipped today |
|---|---|---|
| React / Java / Python / Go full stacks | Projects 8–12 (`11-`…`15-*.md`) | Each is a 1-hour project; you'd need 5 more hours |
| Six database containers | Project 13 (`16-PROJECT-13-databases.md`) | Cassandra + Neo4j alone want 4 GB RAM and 30 min each |
| CI/CD pipelines (BuildKit cache, Trivy, Cosign, buildx multi-arch) | the 15-project set you listed | Needs a GitHub repo and real pushes |
| Kubernetes (kompose, containerd/CRI, Ingress) | the 15-project set | A separate multi-day discipline |
| Docker Swarm (routing mesh, secrets, rolling updates) | the 15-project set | Declining relevance vs K8s; do it after K8s |
| Production observability (Prometheus, cAdvisor, Loki) | the 15-project set | Needs the basics to be automatic first |
| Rootless Docker, user namespaces, image signing, SBOMs | advanced | Day 5+ material |

**That's fine.** Day 1 is the foundation every one of those depends on. Trying to do them today would leave you able to recite commands but unable to debug anything.

---

## 📅 Days 2–7 (2 hours a day → genuine mastery)

| Day | Do | Outcome |
|---|---|---|
| **2** | `11-PROJECT-8-react-frontend.md` + `14-PROJECT-11-react-python-fullstack.md` (both cases of each) | Frontend & Python containerisation, build-time env vars, CORS elimination |
| **3** | `12-PROJECT-9-java-backend.md` **or** `15-PROJECT-12-react-go-fullstack.md` — whichever matches your job | JVM layered jars **or** `FROM scratch` static binaries |
| **4** | `16-PROJECT-13-databases.md` — do **MySQL, MongoDB, Redis** fully; skim the other three | Volumes, init-once semantics, per-engine healthchecks, tested backups |
| **5** | Capstone again — but this time **write Section C from scratch** before looking at the answers | The real test. Expect 3–4 hours. |
| **6** | CI/CD projects 1–3 (pipeline, preview environments, multi-arch buildx) | Images built, scanned, signed and published automatically |
| **7** | Kubernetes projects 1–3 with **kind** | Compose → Deployments/Services, containerd & `crictl`, Ingress |
| **8+** | Swarm, production monitoring, troubleshooting labs | Depth, and the debugging reflexes |

**The mastery loop, repeated until it's automatic:**
```
write Dockerfile → build → run → break it on purpose → read the error → fix → measure (size, build time) → refactor → repeat
```

---

## 🩹 When you get stuck (the 3-minute ladder)

Run these **in order**. 90% of Day-1 problems are solved by step 2 or 3.

```bash
# 1. what state am I actually in?
docker ps -a ; docker images ; docker volume ls ; docker compose ps

# 2. why did it fail?  ← the single most useful command in Docker
docker logs --tail 100 <container>
docker inspect <container> --format 'ExitCode={{.State.ExitCode}} OOM={{.State.OOMKilled}} Error={{.State.Error}}'

# 3. get inside and look
docker exec -it <container> sh                       # if it's RUNNING
docker run --rm -it --entrypoint sh <image>          # if it CRASHES on start ← the escape hatch
ls -la /app ; env ; whoami ; cat /etc/os-release

# 4. rebuild loudly
docker build --progress=plain --no-cache -t app .

# 5. audit the image
docker history app --no-trunc | head -20
docker inspect app --format '{{json .Config.Cmd}} {{json .Config.Entrypoint}} {{json .Config.User}}'

# 6. nuclear option — reset and restart the block
docker compose down -v --remove-orphans ; docker system prune -a --volumes -f
```

| Symptom | Almost always means |
|---|---|
| Container exits instantly | Your `CMD` process finished. Needs a **foreground** long-running process. |
| `port is already allocated` | An old container still holds it. `docker ps -a`, then `docker rm -f`. |
| `connection refused` on localhost | You `EXPOSE`d but didn't `-p`. Or the app bound to `127.0.0.1` instead of `0.0.0.0`. |
| `permission denied` on a volume | Non-root `USER` vs your host uid. `--user $(id -u):$(id -g)` or `chown`. |
| `exec format error` | Wrong CPU architecture (Apple Silicon ↔ amd64). |
| `no such file or directory` on a binary that exists | Dynamically-linked binary in `FROM scratch` — needs `CGO_ENABLED=0`. |
| Build is suddenly slow | A layer above your change got invalidated. Check instruction order. |
| `docker stop` takes 10 s then kills | Shell-form `CMD`/`ENTRYPOINT` — signals aren't reaching your app. |

---

## 📜 QUIZ ANSWERS

<details>
<summary>👉 Open only after you've answered all 40</summary>

1. An **image** is a read-only template (code + runtime + libs, built from a Dockerfile); a **container** is a running, isolated, writable instance of that image.
2. The **build context** — every file in this folder, recursively, minus `.dockerignore`, is sent to the Docker engine.
3. **No.** `COPY` sources are resolved relative to the build context; anything outside it (`..`, absolute host paths) is unreachable.
4. Layers are **read-only and additive**. The earlier layer still contains the file; a later `rm` only adds a "whiteout" marker. Delete it in the *same* `RUN`.
5. A metadata-only layer (0 bytes of filesystem change): `ENV`, `ARG`, `LABEL`, `EXPOSE`, `USER`, `VOLUME`, `CMD`, `ENTRYPOINT`, `HEALTHCHECK`, `STOPSIGNAL`.
6. Containers share the host kernel and are isolated processes (MB, milliseconds); VMs run a full guest OS + kernel (GB, tens of seconds). Containers: many per host; VMs: few.
7. `FROM`.
8. `RUN` at **build** time (creates a layer); `CMD` at **run** time (the container's default process).
9. It starts a server *during the build*, which never exits → the build hangs, and even if it returned, the server would be gone from the final image.
10. `/app/...` — `COPY` copies the **contents** of a directory, never the directory itself as a subfolder.
11. `ADD` downloads from a **URL** and **auto-extracts local tar archives**. Use `COPY` unless you specifically need one of those.
12. **No.** It's documentation (+ affects `docker run -P` and container-to-container discovery). Only `-p host:container` publishes.
13. `ENV`.
14. `ARG X` then `ENV X=${X}`.
15. `WORKDIR` **persists** for all later instructions and creates the directory; `cd` inside a `RUN` dies with that shell.
16. It sets the default user for later `RUN`/`CMD`/`ENTRYPOINT`. It does **not** prevent `docker run --user 0` — it's a default, not a security boundary.
17. `0` = healthy, `1` = unhealthy (`2` is reserved).
18. A grace period at startup during which failures **don't count** toward `--retries` — for slow-starting apps (JVMs, DB migrations).
19. **No.** Docker only *reports* the status. Acting on it is the orchestrator's job (Compose `condition`, Kubernetes probes, or an autoheal container).
20. Which signal `docker stop` sends before falling back to `SIGKILL` after the timeout.
21. **No** — deprecated. Use `LABEL maintainer=` or the OCI labels.
22. `CMD npm start` (shell) vs `CMD ["npm","start"]` (exec).
23. In shell form `/bin/sh` is PID 1 and doesn't forward `SIGTERM`; your app gets `SIGKILL`ed after the grace period with no chance to drain connections.
24. **No.** Wrap it yourself: `CMD ["sh","-c","python app.py --port $PORT"]`.
25. JSON requires double quotes. Single quotes make Docker silently fall back to shell form → `sh: ['a',: not found`.
26. CMD-only: `CMD` is **replaced** by `arg`. ENTRYPOINT-only: `arg` is **appended**. Both: `CMD` defaults are dropped, `arg` is appended to `ENTRYPOINT`.
27. `docker run -it --rm --entrypoint sh myimage`.
28. `exec` replaces the shell process so your app **becomes PID 1** and receives signals directly.
29. It's **discarded** (kept only in the build cache). Only what you `COPY --from=` survives.
30. Compilers/build toolchains, test frameworks and test sources, package-manager caches, source control and secrets.
31. It stops the build at that named stage and produces an image from it — used to debug a build failure interactively with the build toolchain present.
32. A cache directory that **persists between builds** but is never written into a layer (e.g. `/root/.cache/pip`, `/root/.npm`, `/go/pkg/mod`) → dramatically faster rebuilds with no image bloat.
33. So the expensive dependency-install layer stays `CACHED` when only your code changes. A cache hit stops at the first changed instruction.
34. `--chown=user:group` and `--chmod=perms`.
35. `stop` = `SIGTERM`, wait 10 s (or `-t N`), then `SIGKILL` — graceful. `kill` = `SIGKILL` immediately — no cleanup.
36. **137** = 128+9 = `SIGKILL`, usually the cgroup OOM killer. **127** = command not found.
37. `down` removes containers + networks (+ anonymous volumes), **keeps named volumes**. `down -v` also deletes named volumes → **permanent data loss**.
38. Each container has its own network namespace; `localhost` is the container itself. Compose provides DNS for **service names** on a shared user-defined network.
39. `docker ps -a` (did it exit? what code?) → `docker logs` (why) → `docker inspect --format '{{json .State}}'` (exit code / OOMKilled / Error) → `docker run --rm -it --entrypoint sh <image>` (look inside).
40. A secrets manager / vault, Docker or Kubernetes **secrets** mounted as files, or BuildKit `RUN --mount=type=secret`. Never in `ENV`/`ARG`/`RUN echo` in a Dockerfile, and never `COPY .env`.
</details>

---

## 🏁 Definition of "I had a successful Day 1"

Tick every box. If you can, you are competent with Docker.

- [ ] `docker run hello-world` worked before 9:30
- [ ] I explained layers, build context and image-vs-container out loud
- [ ] I wrote a 9-instruction Dockerfile **from memory** and it ran as non-root and reported `healthy`
- [ ] I saw `RUN` output during a build and `CMD` output during a run, and can explain the difference
- [ ] I proved `EXPOSE` does nothing and `-p` does everything
- [ ] I filled in the `CMD`/`ENTRYPOINT` table from memory
- [ ] I watched a shell-form container ignore `SIGTERM` and an exec-form one shut down cleanly
- [ ] I deleted a container and the data survived; I deleted a volume and it didn't
- [ ] I measured a naive image vs a multi-stage image on my own machine and can explain the delta
- [ ] I brought up a 4-service Compose stack and saw `"source": "redis-cache"` on the second request
- [ ] The capstone `make smoke` printed ✅ PASSED
- [ ] I wrote a production Dockerfile on a blank page and diffed it against the cheatsheet
- [ ] I scored ≥ 34/40 on the quiz

**Then sleep.** Your brain consolidates procedural memory overnight — which is why one 12-hour day beats two 6-hour days, and why Day 2 will feel much easier than you expect.

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish%20Kumar%20Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn → <https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260>
🐙 GitHub → <https://github.com/3558Bhk>

*Built for engineers who learn by breaking things on purpose.*

</div>
