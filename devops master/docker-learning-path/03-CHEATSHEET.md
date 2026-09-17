# 📋 Docker & Dockerfile Cheatsheet (one-page revision)

Print this. Keep it next to your keyboard.

---

## 1. Dockerfile instructions at a glance

| Instruction | Purpose | Layer? | Example |
|---|---|---|---|
| `FROM` ⭐ | Base image — **required, first** | ✅ | `FROM python:3.13-alpine` |
| `RUN` ⭐ | Command at **build** time | ✅ | `RUN apk add --no-cache curl` |
| `CMD` ⭐ | Default command at **run** time | ❌ | `CMD ["python","app.py"]` |
| `ENTRYPOINT` ⭐ | Fixed command; args are **appended** | ❌ | `ENTRYPOINT ["/app/run.sh"]` |
| `COPY` ⭐ | Files from build context → image | ✅ | `COPY . /app` |
| `ADD` 🔶 | `COPY` + URL download + auto-untar | ✅ | `ADD app.tar.gz /app/` |
| `WORKDIR` ⭐ | Set/create the working directory | ✅ | `WORKDIR /app` |
| `EXPOSE` 🔶 | **Document** a port (doesn't publish!) | ❌ | `EXPOSE 8080` |
| `ENV` ⭐ | Env var — **persists at run time** | ❌ | `ENV APP_ENV=production` |
| `ARG` 🔶 | Build-time var — **gone after build** | ❌ | `ARG VERSION=1.0` |
| `LABEL` 🔹 | Metadata | ❌ | `LABEL org.opencontainers.image.version="1.0"` |
| `USER` ⭐ | Switch to non-root | ❌ | `USER appuser` |
| `VOLUME` 🔹 | Declare a mount point | ❌ | `VOLUME /app/data` |
| `HEALTHCHECK` ⭐ | Liveness probe | ❌ | `HEALTHCHECK CMD wget -q --spider http://localhost/health` |
| `STOPSIGNAL` 🔹 | Signal for `docker stop` | ❌ | `STOPSIGNAL SIGTERM` |
| `ONBUILD` 🔹 | Fires in **child** images | ❌ | `ONBUILD COPY . /app` |
| `SHELL` 🔹 | Change default shell | ❌ | `SHELL ["/bin/bash","-c"]` |
| `MAINTAINER` ❌ | **Deprecated** → use `LABEL` | — | — |

---

## 2. Build time vs run time (the most important table)

| | Build time (`docker build`) | Run time (`docker run`) |
|---|---|---|
| Instructions | `FROM` `RUN` `COPY` `ADD` `WORKDIR` `ENV` `ARG` `LABEL` `USER` `EXPOSE` `VOLUME` | `CMD` `ENTRYPOINT` `HEALTHCHECK` (executes repeatedly) |
| Variables | `ARG` ✅ / `ENV` ✅ | `ENV` ✅ / `ARG` ❌ gone |
| Set from outside | `--build-arg` | `-e` / `--env-file` |
| Result | an **image** (immutable) | a **container** (mutable, disposable) |

> 🔥 `RUN npm start` is **wrong** — it runs during the build. Use `CMD ["npm","start"]`.

---

## 3. Shell form vs exec form

```dockerfile
CMD npm start                  # SHELL  → /bin/sh -c "npm start"   → sh is PID 1 → signals LOST
CMD ["npm", "start"]           # EXEC   → npm start                → app is PID 1 → signals OK ✅
CMD ["sh","-c","echo $PORT"]   # EXEC + explicit shell = variables AND correct PID 1
```

| | Shell form | Exec form |
|---|---|---|
| `$VAR` expansion | ✅ | ❌ |
| `&&`, `\|`, `>`, globs | ✅ | ❌ |
| Receives `SIGTERM` | ❌ | ✅ |
| Use for | `RUN` | `CMD` / `ENTRYPOINT` |

JSON rules: **double quotes only**, no trailing comma. `CMD ['a','b']` silently becomes shell form. 🐛

---

## 4. `CMD` vs `ENTRYPOINT` — settled

| | `docker run img` | `docker run img a b` |
|---|---|---|
| `CMD ["x","y"]` | runs `x y` | runs `a b` (**CMD replaced**) |
| `ENTRYPOINT ["x"]` | runs `x` (no args) | runs `x a b` (**appended**) |
| `ENTRYPOINT ["x"]` + `CMD ["y"]` ⭐ | runs `x y` | runs `x a b` (**CMD defaults dropped**) |

**Use ENTRYPOINT + CMD for applications. Use CMD alone for flexible base images.**
Escape hatch: `docker run -it --entrypoint sh myimage`

---

## 5. `COPY` gotchas

```dockerfile
COPY src /app/       # copies the CONTENTS of src → /app/file1  (NOT /app/src/file1)
COPY a.txt b.txt /app/   # multiple sources → destination MUST end with /
COPY --chown=app:app --chmod=755 script.sh /app/
COPY --from=builder /app/dist /usr/share/nginx/html      # multi-stage
COPY --link package.json /app/                           # better cache isolation
COPY --exclude=*.md docs/ /app/docs/                     # labs syntax (1.19+)
COPY --parents */src/ /dest/                             # labs syntax (1.20+)
```
Source paths are **relative to the build context** — never absolute host paths, never `../`.

---

## 6. The layer-caching order (memorise)

```dockerfile
FROM ...                      # 1. base          (changes: almost never)
RUN apk add build-deps        # 2. system deps   (rarely)
COPY requirements.txt .       # 3. dep manifest  (occasionally)   ← copy MANIFEST only
RUN pip install -r ...        # 4. install deps  (expensive!)
COPY . .                      # 5. YOUR CODE     (every commit)   ← copy code LAST
USER appuser                  # 6. metadata
CMD ["python","app.py"]       # 7. metadata
```
A cache hit stops at the **first changed instruction** — everything below it rebuilds.

---

## 7. Multi-stage template

```dockerfile
# syntax=docker/dockerfile:1
FROM node:22-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build && npm test

FROM nginx:1.29-alpine
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
USER nginx
HEALTHCHECK CMD wget -q --spider http://localhost/ || exit 1
```
```bash
docker build --target build -t app:debug .    # stop at an earlier stage
docker build --platform linux/amd64 -t app .  # cross-architecture
```

---

## 8. Production Dockerfile template (copy-paste)

```dockerfile
# syntax=docker/dockerfile:1
ARG BASE=python:3.13-alpine

# ---------- build ----------
FROM ${BASE} AS builder
WORKDIR /app
RUN apk add --no-cache gcc musl-dev
COPY requirements.txt .
RUN --mount=type=cache,target=/root/.cache/pip \
    pip wheel --no-cache-dir --wheel-dir /wheels -r requirements.txt
COPY . .
RUN python -m pytest -q

# ---------- runtime ----------
FROM ${BASE} AS runtime
ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION} PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1 PORT=8000
LABEL org.opencontainers.image.title="my-service" \
      org.opencontainers.image.version="${APP_VERSION}"
WORKDIR /app
RUN addgroup -S app && adduser -S app -G app
COPY --from=builder /wheels /wheels
RUN pip install --no-cache-dir --no-index --find-links=/wheels /wheels/* && rm -rf /wheels
COPY --from=builder --chown=app:app /app/src ./src
USER app
EXPOSE 8000
STOPSIGNAL SIGTERM
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request,sys;sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health',timeout=2).status==200 else 1)"
CMD ["python","-m","src.main"]
```

---

## 9. `docker` CLI — build & run

```bash
docker build -t app:1.0 .                     docker run -d --name web -p 8080:80 app:1.0
docker build -f Dockerfile.prod -t app .      docker run -it --rm alpine sh
docker build --no-cache -t app .              docker run --rm -e FOO=bar app
docker build --progress=plain -t app .        docker run --rm --env-file .env app
docker build --target builder -t app:dev .    docker run --rm -v data:/app/data app
docker build --build-arg V=2 -t app .         docker run --rm -v $(pwd):/app -w /app app
docker build --platform linux/amd64 -t app .  docker run --rm --entrypoint sh app
docker build --secret id=k,src=./k.txt .      docker run -d --restart=unless-stopped app
docker buildx build --platform linux/amd64,linux/arm64 -t u/app:1 --push .
docker run -d --read-only --tmpfs /tmp --cap-drop ALL \
  --security-opt no-new-privileges:true --memory 256m --cpus 0.5 --user 1000:1000 app
```

**`-p host:container` · `-v volume:container[:ro]` · `-e KEY=VALUE` · `-d` detached · `-it` interactive · `--rm` auto-remove · `--name`**

---

## 10. `docker` CLI — inspect & debug

```bash
docker ps                      docker exec -it <c> sh          docker history app --no-trunc
docker ps -a                   docker exec <c> env             docker inspect <c> --format '{{json .State}}'
docker images                  docker logs -f <c>              docker inspect app --format '{{json .Config.Cmd}}'
docker stats                   docker logs --tail 100 <c>      docker inspect app --format '{{json .Config.Env}}'
docker port <c>                docker top <c>                  docker inspect --format '{{json .State.Health}}' <c>
docker diff <c>                docker volume ls                docker inspect <c> --format '{{.State.ExitCode}} {{.State.OOMKilled}}'
docker network ls              docker volume inspect v         docker image inspect app --format '{{.Os}}/{{.Architecture}}'
docker system df               docker debug <c>                docker scout cves app
```

---

## 11. `docker` CLI — clean up

```bash
docker stop <c>            # SIGTERM, wait 10s, SIGKILL     docker rmi <image>
docker kill <c>            # SIGKILL immediately            docker rmi -f <image>
docker rm <c>              # remove a stopped container     docker builder prune
docker rm -f <c>           # stop + remove                  docker volume prune    ⚠️ DATA
docker container prune     docker image prune -a             docker system prune -a --volumes  ☠️
```

---

## 12. Registry

```bash
docker login
docker tag app:1.0 <user>/app:1.0
docker push <user>/app:1.0
docker pull <user>/app:1.0
docker search redis
docker run --rm <user>/app:1.0          # anyone, anywhere, one command
```

---

## 13. Docker Compose

```bash
docker compose config              # validate + show merged YAML
docker compose build [--no-cache]  docker compose up -d [--wait] [--build]
docker compose up -d --scale api=3 docker compose down [-v] [--remove-orphans]
docker compose ps [-a]             docker compose restart [svc]
docker compose logs -f [svc]       docker compose stop|start|kill [svc]
docker compose exec api sh         docker compose run --rm api pytest
docker compose stats               docker compose pull
docker compose --profile dev up -d docker compose up -d --no-deps --build api
docker compose watch               # auto-rebuild on file changes (Compose v2.22+)
```

```yaml
name: myproject
services:
  api:
    build: { context: ./api, args: { VER: "1.0" } }
    image: myapi:1.0
    restart: unless-stopped
    depends_on: { db: { condition: service_healthy } }
    environment: { DATABASE_URL: "postgresql://u:p@db:5432/app" }
    env_file: [.env]
    ports: ["8000:8000"]
    volumes: ["./api:/app", "data:/app/data"]
    networks: [backend]
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS localhost:8000/health || exit 1"]
      interval: 10s
      timeout: 3s
      retries: 5
      start_period: 15s
    deploy: { resources: { limits: { cpus: "0.5", memory: 256M } } }
    stop_grace_period: 20s
    profiles: ["dev"]
  db:
    image: postgres:17-alpine
    environment: { POSTGRES_PASSWORD: p, POSTGRES_DB: app }
    volumes: ["pgdata:/var/lib/postgresql/data", "./db-init:/docker-entrypoint-initdb.d:ro"]
    healthcheck: { test: ["CMD-SHELL","pg_isready -U u"], interval: 5s, retries: 10 }
    networks: [backend]
volumes: { data: {}, pgdata: {} }
networks: { backend: {} }
```

> Inside a Compose network, reach other services by **service name** (`db`, `cache`) — **never** `localhost`.

---

## 14. `.dockerignore` starter

```gitignore
.git
.gitignore
**/node_modules
**/__pycache__
*.pyc
.venv
venv
dist
build
*.log
.env
*.env
*.pem
*.key
.vscode
.idea
.DS_Store
Thumbs.db
Dockerfile*
docker-compose*.yml
.dockerignore
```

---

## 15. Exit codes

| Code | Meaning |
|---|---|
| `0` | success |
| `1` | general application error |
| `2` | misuse of a shell command / bad argument |
| `126` | found but **not executable** (missing `chmod +x`) |
| `127` | **command not found** |
| `137` | 128+9 → `SIGKILL` (often **OOM**) |
| `143` | 128+15 → `SIGTERM` (a normal `docker stop`) |

---

## 16. Base image picker

| Need | Use |
|---|---|
| Learning / tiny tools | `alpine:3.22` (~8 MB) |
| Python, small | `python:3.13-alpine` |
| Python, heavy native wheels (numpy, pandas) | `python:3.13-slim` |
| Node build | `node:22-alpine` |
| Node runtime only | build stage → `nginx:1.29-alpine` |
| Web server / static | `nginx:1.29-alpine` |
| Database | `postgres:17-alpine`, `redis:7-alpine`, `mysql:8` |
| Go / Rust static binary | build stage → `scratch` or `gcr.io/distroless/static` |
| Java | `eclipse-temurin:21-jre-alpine` |
| Nothing but your binary | `scratch` (0 MB, no shell, no certs) |

**Never use `:latest` in a Dockerfile you deploy.**

---

## 17. Debugging ladder

```bash
docker build --progress=plain --no-cache -t app .     # 1. see every build line
docker run --rm -it --entrypoint sh app               # 2. get INSIDE the image
ls -la /app; env; whoami; cat /etc/os-release         # 3. verify files, env, user
docker run --rm app                                   # 4. run in FOREGROUND, read the error
docker logs --tail 200 <container>                    # 5. read detached logs
docker inspect <container> --format '{{json .State}}' # 6. exit code / OOMKilled / health
docker history app --no-trunc                         # 7. audit layers, find bloat & leaks
docker exec -it <container> sh                        # 8. explore a RUNNING container
docker network inspect <net>                          # 9. who can reach whom
docker system df -v                                   # 10. disk usage
```

---

## 18. The 10 rules

1. **`FROM` pinned** — never `latest`.
2. **`.dockerignore` always** — faster builds, no leaked secrets.
3. **Manifest first, code last** — protect the dependency layer.
4. **One `RUN` for install + cleanup** — layers are read-only.
5. **Exec form for `CMD`/`ENTRYPOINT`** — so signals reach your app.
6. **`USER` non-root** — but enforce it at runtime too.
7. **Multi-stage** — compilers and tests never ship.
8. **`HEALTHCHECK`** — "running" ≠ "working".
9. **No secrets in the image** — `ARG`/`ENV`/`COPY .env` all leak into `docker history`.
10. **One container, one job** — don't run nginx + postgres + app together.

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish%20Kumar%20Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn → <https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260>
🐙 GitHub → <https://github.com/3558Bhk>

*Built for engineers who learn by breaking things on purpose.*

</div>
