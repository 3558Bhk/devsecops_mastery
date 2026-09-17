# 🐳 Docker Learning Path — From Zero to End-to-End Project

Everything you need to learn the **Dockerfile**, in order. Written for a complete beginner.
**13 projects** (one file each), every Dockerfile instruction, and a full production-style capstone with tasks + answers.

> ⚡ **Only have one day?** Start with **[`00-ONE-DAY-MASTER-PLAN.md`](00-ONE-DAY-MASTER-PLAN.md)** — an hour-by-hour IST schedule (9 AM → 9 PM) that turns these files into a single intensive day, with a command-only fast track, 4 checkpoints, a 40-question quiz and answers, and a Days 2–7 follow-up plan.

> 📁 **One project = one file.** Projects 8–13 each show **two versions**: 🔵 **Case 1** = a *simple* Dockerfile, 🟢 **Case 2** = a *multi-stage* Dockerfile. Build both and measure the difference — that comparison is the lesson.

---

## 📂 What is in this folder

| # | File | Contents |
|---|---|---|
| — | **`README.md`** | This index |
| ⚡ | **`00-ONE-DAY-MASTER-PLAN.md`** | **The one-day battle plan** — hour-by-hour schedule, command-only fast track for every project, checkpoints, 40-question quiz + answers, stuck-ladder, Days 2–7 plan |
| — | **`01-DOCKERFILE-GUIDE.md`** | ⭐ The core guide: what Docker/images/containers/layers are + the **complete instruction reference** (`FROM` `RUN` `CMD` `ENTRYPOINT` `COPY` `ADD` `WORKDIR` `EXPOSE` `ENV` `ARG` `LABEL` `USER` `VOLUME` `HEALTHCHECK` `STOPSIGNAL` `ONBUILD` `SHELL`) + shell vs exec form + multi-stage + `.dockerignore` + the whole `docker` CLI + troubleshooting + best practices |
| — | `03-CHEATSHEET.md` | One-page revision sheet — every instruction, every flag, the 10 rules |
| 1 | `04-PROJECT-1-hello-docker.md` | 🥚 `FROM`, `RUN`, `CMD`, layers, caching |
| 2 | `05-PROJECT-2-static-site.md` | 🐣 `COPY`, `ADD`, `WORKDIR`, `.dockerignore`, `EXPOSE` |
| 3 | `06-PROJECT-3-config-and-env.md` | 🐥 `ENV`, `ARG`, `LABEL`, build-time vs run-time config |
| 4 | `07-PROJECT-4-cli-entrypoint.md` | 🐤 `ENTRYPOINT` vs `CMD`, exec vs shell form, PID 1 & signals |
| 5 | `08-PROJECT-5-volumes-health-user.md` | 🐓 `VOLUME`, `USER`, `HEALTHCHECK`, `STOPSIGNAL` |
| 6 | `09-PROJECT-6-multistage-build.md` | 🦅 multi-stage, `COPY --from`, `--target`, cache mounts, secrets |
| 7 | `10-PROJECT-7-compose-stack.md` | 🦉 Docker Compose: services, networks, volumes, `depends_on` |
| 🏆 | **`02-CAPSTONE-END-TO-END.md`** | **The end-to-end project** — Section A: the task (10 requirements) · Section B: the starting code · Section C: **complete answers** |
| 8 | `11-PROJECT-8-react-frontend.md` | ⚛️ React (Vite) frontend |
| 9 | `12-PROJECT-9-java-backend.md` | ☕ Java / Spring Boot backend |
| 10 | `13-PROJECT-10-react-java-fullstack.md` | ⚛️ + ☕ React & Java full stack |
| 11 | `14-PROJECT-11-react-python-fullstack.md` | ⚛️ + 🐍 React & Python full stack |
| 12 | `15-PROJECT-12-react-go-fullstack.md` | ⚛️ + 🐹 React & Go full stack |
| 13 | `16-PROJECT-13-databases.md` | 🗄️ **6 separate DB mini-projects**: MySQL · MongoDB · Redis · DynamoDB Local · Cassandra · Neo4j |
| **14** | **`17-PROJECT-14-mern-stack.md`** | 🟣 ⭐ **MERN STACK** — React 19 + Node 24 + Express 5 + MongoDB 8 as an npm-workspaces monorepo. The database ships **inside** the release: a replica set in Compose, `--omit=dev` multi-stage Node builds, runtime `config.js`, `autoIndex: false`, a migration ledger you build yourself, and a restore-verified backup |
| ⌨️ | **`18-DOCKER-CLI-COMPLETE-REFERENCE.md`** | ⭐ **The single CLI reference for this folder** — every `docker` / `docker compose` / `docker buildx` subcommand and flag, organised by job (build · run · inspect · debug · network · volume · registry · system), with the exact command for each of the 12 classic errors, plus a copy-paste troubleshooting ladder. Keep it open beside you the whole way through. |

> 📌 **Every project file is self-contained** — complete runnable code inline (Dockerfile + application source + compose file). Just create the folder it describes, paste the files, and run the commands. No other downloads needed.

---

## 🗺️ The learning order

### Phase 0 — If you only have today
**[`00-ONE-DAY-MASTER-PLAN.md`](00-ONE-DAY-MASTER-PLAN.md)** → Blocks 0–8, 9:00 AM to 9:00 PM IST. It tells you exactly which sections to read and which to skip, and gives copy-paste command tracks for Projects 1–7 plus a capstone speedrun.

### Phase 1 — Foundations (`01-DOCKERFILE-GUIDE.md`)
| Step | Read | You learn |
|---|---|---|
| 1 | Parts 1–2 | images vs containers, layers, build context, build-time vs run-time |
| 2 | Part 3 | **every** Dockerfile instruction, one by one |
| 3 | Parts 5–6 | the 12 classic errors + the best-practices checklist |

### Phase 2 — The 7 core projects (one file each)
| Step | File | Project | Time |
|---|---|---|---|
| 4 | `04-PROJECT-1-hello-docker.md` | 🥚 Hello, Docker | 25 min |
| 5 | `05-PROJECT-2-static-site.md` | 🐣 Static website | 35 min |
| 6 | `06-PROJECT-3-config-and-env.md` | 🐥 Configurable Python app | 40 min |
| 7 | `07-PROJECT-4-cli-entrypoint.md` | 🐤 CLI tool | 45 min |
| 8 | `08-PROJECT-5-volumes-health-user.md` | 🐓 Persistent data app | 50 min |
| 9 | `09-PROJECT-6-multistage-build.md` | 🦅 Multi-stage builds | 60 min |
| 10 | `10-PROJECT-7-compose-stack.md` | 🦉 Compose stack | 70 min |

### Phase 3 — The capstone (`02-CAPSTONE-END-TO-END.md`)
**TaskNest**: API + PostgreSQL + Redis + nginx reverse proxy.

| Section | What |
|---|---|
| **A — THE TASK** | A real ticket: 10 requirements + a Definition of Done acceptance test |
| **B — THE STARTING CODE** | The application you're given (pure Python stdlib) |
| **C — THE ANSWERS** | Multi-stage Dockerfiles, `docker-compose.yml`, `Makefile`, backup/restore/smoke-test scripts, requirement-by-requirement proof, GitHub Actions CI, runbook |

### Phase 4 — Full-stack & databases (Projects 8–13, one file each)
Every project has **🔵 CASE 1: simple Dockerfile** and **🟢 CASE 2: multi-stage Dockerfile**.

| Project | File | Case 1 (simple) → Case 2 (multi-stage) |
|---|---|---|
| **8** | `11-PROJECT-8-react-frontend.md` | ⚛️ React/Vite — node dev server **230 MB** → nginx + static build **52 MB** |
| **9** | `12-PROJECT-9-java-backend.md` | ☕ Java Spring Boot — prebuilt jar + JRE → JDK build stage + **layered jar** (60 MB rebuilds → 50 KB) |
| **10** | `13-PROJECT-10-react-java-fullstack.md` | ⚛️ + ☕ — two ports + CORS → one origin behind nginx proxy, dev/prod compose overrides |
| **11** | `14-PROJECT-11-react-python-fullstack.md` | ⚛️ + 🐍 — uvicorn `--reload` as root → wheels + pytest stage + gunicorn non-root |
| **12** | `15-PROJECT-12-react-go-fullstack.md` | ⚛️ + 🐹 — full Go SDK **380 MB** → static binary **18 MB** → `FROM scratch` **9 MB** |
| **13** | `16-PROJECT-13-databases.md` | 🗄️ **6 separate DB mini-projects** — MySQL · MongoDB · Redis · DynamoDB Local · Cassandra · Neo4j, each with init scripts, real healthchecks, tuned configs, volumes, backup/restore, GUI tool, gotchas table |
| **14** | `17-PROJECT-14-mern-stack.md` | 🟣 ⭐ **MERN** — ~1.1 GB simple → **~180 MB** multi-stage (`--omit` dev, `dist` only). One lockfile, one shared contract package, a **replica-set** MongoDB, `--oplog` backups that are restore-verified, and the reason an image rollback is **not** a data rollback |

---

## ✅ Before you start (one-time setup)

| OS | Install |
|----|---------|
| **Windows 10/11** | `wsl --install` in PowerShell **as Administrator**, reboot, then install **Docker Desktop** from docker.com. In Docker Desktop → Settings → General → enable *"Use the WSL 2 based engine"*. |
| **macOS** | **Docker Desktop** (Apple Silicon → the *Apple Chip* `.dmg`), or `brew install --cask docker`. |
| **Linux (Ubuntu/Debian)** | `curl -fsSL https://get.docker.com \| sh` then `sudo usermod -aG docker $USER` and **log out and back in**. |

### Verify

```bash
docker --version          # Docker version 28.x.x
docker compose version    # Docker Compose version v2.x.x
docker run hello-world    # → "Hello from Docker!"
```

If `hello-world` prints its message, you're ready. 🎉

---

## 🔑 The 6 commands you'll type 90% of the time

```bash
docker build -t myimage:1.0 .        # build from the Dockerfile in this folder
docker run -d -p 8080:80 myimage     # run detached, publish port 80 → your 8080
docker ps -a                         # list containers (running + stopped)
docker logs -f <container>           # follow output (Ctrl+C stops following)
docker exec -it <container> sh       # shell INSIDE a running container
docker stop <c> && docker rm <c>     # clean up
```

---

## 🧹 Housekeeping

```bash
docker system df            # how much disk Docker is using
docker system prune -a      # remove stopped containers + unused images/networks (asks first)
docker volume prune         # remove unused volumes   ⚠️ DELETES DATA
docker compose down -v      # remove a stack AND its volumes  ☠️
```

---

## 🎯 Success checklist

**Core (Projects 1–4)**
- [ ] I can explain image vs container vs Dockerfile in one sentence each
- [ ] I know what a **layer** is and why layer order controls build speed
- [ ] I can explain build **context** and why `.dockerignore` matters
- [ ] I have written `FROM`, `RUN`, `CMD`, `COPY`, `WORKDIR`, `EXPOSE`, `ENV` from memory
- [ ] I can explain `ENTRYPOINT` vs `CMD` **and** shell form vs exec form
- [ ] I know the PID 1 / `SIGTERM` problem and how exec form fixes it
- [ ] I know when to use `ADD` instead of `COPY` (answer: almost never)
- [ ] I can explain `ARG` (build time) vs `ENV` (run time) and how to promote one to the other

**Intermediate (Projects 5–7)**
- [ ] I have built a **multi-stage** image and measured the size difference
- [ ] I have used `HEALTHCHECK` and seen `healthy` in `docker ps`
- [ ] I can explain liveness vs readiness
- [ ] I have run a container as a **non-root** `USER` — and know `USER` is a default, not a wall
- [ ] I have proved data survives `docker rm` but dies with `docker volume rm`
- [ ] I can bring up a multi-container app with `docker compose up -d --wait`
- [ ] I understand Docker's DNS-by-service-name and why `localhost` is always wrong in Compose
- [ ] I have used `RUN --mount=type=cache` and `--mount=type=secret`

**Capstone**
- [ ] All 10 requirements satisfied and the Definition of Done passes
- [ ] `make up && make smoke && make backup && make nuke && make restore` all work

**Full-stack & databases (Projects 8–13)**
- [ ] I have containerised a **React** app and served it from nginx with SPA routing
- [ ] I understand frontend **build-time** env vars and why `-e` at runtime does nothing
- [ ] I have containerised a **Java** app and can explain the layered-jar caching win
- [ ] I know `-XX:MaxRAMPercentage` and why `-Xmx` in a container causes exit 137
- [ ] I have containerised a **Python** app with wheels, gunicorn and non-root
- [ ] I have shipped a **Go** binary in `FROM scratch` and debugged it without a shell
- [ ] I have run **all six** databases with volumes, healthchecks and *tested* backups
- [ ] I have wired a frontend + backend behind **one** origin and eliminated CORS
- [ ] For every project above I have built **both cases** and measured the difference

---

## ⏱️ Realistic pace

| Plan | Duration |
|---|---|
| 1 project per day | ~3 weeks for everything |
| 2 hours/day, focused | ~10 days |
| One intensive weekend + follow-up | Projects 1–7 in a weekend, capstone the next, Projects 8–13 after |

**Don't skip the Extra Tasks.** Reading a command teaches you nothing; breaking it and fixing it teaches you everything.

---

**Start here → [`01-DOCKERFILE-GUIDE.md`](01-DOCKERFILE-GUIDE.md)**

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish%20Kumar%20Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn → <https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260>
🐙 GitHub → <https://github.com/3558Bhk>

*Built for engineers who learn by breaking things on purpose.*

</div>
