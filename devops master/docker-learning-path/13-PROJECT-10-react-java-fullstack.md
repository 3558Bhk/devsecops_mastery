# PROJECT 10 · ⚛️ React + ☕ Java — Full Stack

> **Part of the Docker Learning Path.** Previous: [`12-PROJECT-9-java-backend.md`](12-PROJECT-9-java-backend.md) — Project 9 — Java Backend.
>
> 🎯 **Instructions & techniques:** two multi-stage images · `docker-compose.yml` · compose override files · nginx reverse proxy · networks
>
> 📚 **What you learn:** Wiring frontend + backend behind ONE origin, eliminating CORS, dev vs production compose files
>
> 🔁 **Every project here is written TWICE:**
> - **🔵 CASE 1 — a SIMPLE Dockerfile.** Easy to read, easy to get working, usually too big for production.
> - **🟢 CASE 2 — a MULTI-STAGE Dockerfile.** The production version: smaller, faster to rebuild, more secure, tests can fail the build.
>
> **Build Case 1 first**, run it, understand it — then build Case 2 and **measure the difference**. That comparison *is* the lesson.

---

# D.3 — PROJECT 10 · ⚛️ React + ☕ Java (Full Stack)

**🎯 What you learn:** wiring two multi-stage images into one Compose stack, killing CORS with a reverse proxy, service DNS, ordered startup, one-command dev vs production, shared env config.

> This is **Project 8 + Project 9 glued together properly** — the way a real team would ship it.

## 10.0 Structure

```
10-react-java-fullstack/
├── docker-compose.yml
├── docker-compose.dev.yml       ← override file for hot-reload development
├── .env.example
├── Makefile
├── frontend/                    ← from Project 8 (Case 2 files)
│   ├── Dockerfile
│   ├── nginx.conf
│   ├── package.json
│   ├── vite.config.js
│   ├── index.html
│   └── src/...
└── backend/                     ← from Project 9 (Case 2 files)
    ├── Dockerfile
    ├── pom.xml
    └── src/...
```

Copy `08-react-frontend/*` → `frontend/` and `09-java-backend/*` → `backend/`, keeping each project's **Case 2** Dockerfile as `Dockerfile`.

### `.env.example`

```bash
COMPOSE_PROJECT_NAME=tasknest-full
APP_VERSION=1.0.0
GIT_COMMIT=local

# backend
BACKEND_PORT=8000
LOG_LEVEL=INFO
JAVA_OPTS=-XX:MaxRAMPercentage=75.0 -XX:+UseSerialGC

# frontend (BUILD-TIME only — inlined into the JS bundle)
VITE_API_URL=/api

# public ports
WEB_PORT=8080
```

---

## 🔵 CASE 1 — SIMPLE (two single-stage Dockerfiles, wired by hand)

### `frontend/Dockerfile` (simple)

```dockerfile
FROM node:22-alpine
WORKDIR /app
COPY package.json package-lock.json* ./
RUN if [ -f package-lock.json ]; then npm ci; else npm install; fi
COPY . .
EXPOSE 5173
CMD ["npm", "run", "dev"]
```

### `backend/Dockerfile` (simple)

```dockerfile
FROM eclipse-temurin:21-jdk-alpine
WORKDIR /app
COPY pom.xml .
RUN mvn -B -q dependency:go-offline || true
COPY src ./src
RUN mvn -B -q -DskipTests package
EXPOSE 8000
CMD ["java", "-jar", "target/app.jar"]
```

### `docker-compose.yml` (Case 1)

```yaml
name: tasknest-simple

services:
  backend:
    build: ./backend
    image: tn-backend:simple
    ports: ["8000:8000"]
    environment:
      PORT: "8000"
      LOG_LEVEL: INFO
    healthcheck:
      test: ["CMD-SHELL", "wget -q --spider http://localhost:8000/api/health || exit 1"]
      interval: 10s
      timeout: 3s
      retries: 10
      start_period: 45s

  frontend:
    build: ./frontend
    image: tn-frontend:simple
    ports: ["5173:5173"]
    volumes:
      - ./frontend/src:/app/src        # hot reload
    environment:
      VITE_API_URL: http://localhost:8000/api
      VITE_PROXY_TARGET: http://backend:8000
    depends_on:
      backend: { condition: service_healthy }
```

```bash
docker compose up -d --build
docker compose ps
open http://localhost:5173
```

**Notice the problems in Case 1:**
- Two public ports (5173 **and** 8000) → the browser talks to two origins → **CORS**.
- The dev server (Vite) is what's serving your "production" app.
- ~230 MB + ~600 MB images.
- The JDK ships in the backend runtime.

---

## 🟢 CASE 2 — MULTI-STAGE + a proper reverse proxy

### `frontend/Dockerfile`

Exactly the Project 8 **Case 2** file (`Dockerfile.multistage`). Its `nginx.conf` already proxies `/api/` → `http://api:8000/`.

### `backend/Dockerfile`

Exactly the Project 9 **Case 2** file (`Dockerfile.multistage`).

### `docker-compose.yml` (Case 2 — production)

```yaml
name: tasknest-full

x-logging: &logging
  driver: json-file
  options: { max-size: "10m", max-file: "3" }

x-security: &security
  no-new-privileges: true

services:

  api:
    build:
      context: ./backend
      dockerfile: Dockerfile
      target: runtime
      args:
        APP_VERSION: ${APP_VERSION:-1.0.0}
        GIT_COMMIT:  ${GIT_COMMIT:-local}
    image: tasknest-api:${APP_VERSION:-1.0.0}
    restart: unless-stopped
    logging: *logging
    security_opt: *security
    environment:
      PORT: "8000"
      LOG_LEVEL: ${LOG_LEVEL:-INFO}
      APP_ENV: production
      JAVA_OPTS: ${JAVA_OPTS:--XX:MaxRAMPercentage=75.0 -XX:+UseSerialGC}
    read_only: true
    tmpfs:
      - /tmp:size=64M
      - /app/data:size=16M
    cap_drop: [ALL]
    deploy:
      resources:
        limits: { cpus: "1.0", memory: 512M }
        reservations: { memory: 192M }
    stop_grace_period: 25s
    networks: [backend]
    healthcheck:
      test: ["CMD-SHELL", "wget -q --spider http://127.0.0.1:8000/api/health || exit 1"]
      interval: 15s
      timeout: 3s
      retries: 5
      start_period: 45s
    # NOT published — only nginx can reach it

  web:
    build:
      context: ./frontend
      dockerfile: Dockerfile
      target: runtime
      args:
        APP_VERSION:   ${APP_VERSION:-1.0.0}
        VITE_API_URL:  ${VITE_API_URL:-/api}     # relative → one origin → no CORS
    image: tasknest-web:${APP_VERSION:-1.0.0}
    restart: unless-stopped
    logging: *logging
    security_opt: *security
    depends_on:
      api: { condition: service_healthy }
    ports:
      - "${WEB_PORT:-8080}:8080"                 # ← the ONLY public port
    read_only: true
    tmpfs:
      - /var/cache/nginx:size=16M
      - /var/run:size=1M
      - /tmp:size=8M
    cap_drop: [ALL]
    deploy:
      resources:
        limits: { cpus: "0.5", memory: 128M }
    networks: [frontend, backend]
    healthcheck:
      test: ["CMD-SHELL", "wget -q --spider http://127.0.0.1:8080/healthz || exit 1"]
      interval: 20s
      timeout: 3s
      retries: 3
      start_period: 5s

networks:
  frontend:
  backend:
```

### `docker-compose.dev.yml` (override for development)

```yaml
# Used as:  docker compose -f docker-compose.yml -f docker-compose.dev.yml up
# Compose MERGES files: later files override earlier ones, key by key.
services:
  api:
    build:
      target: debug                 # the JDK stage — has mvn, tests, a shell
    image: tasknest-api:debug
    ports: ["127.0.0.1:8000:8000"]  # reachable from your IDE
    volumes:
      - ./backend/src:/workspace/src
    environment:
      LOG_LEVEL: DEBUG
    read_only: false
    command: ["sh", "-c", "mvn -q spring-boot:run"]

  web:
    build:
      context: ./frontend
      dockerfile: Dockerfile        # the SIMPLE dev-server Dockerfile
      target: ""
    image: tasknest-web:dev
    ports: ["5173:5173"]
    volumes:
      - ./frontend/src:/app/src
      - ./frontend/index.html:/app/index.html
    environment:
      VITE_PROXY_TARGET: http://api:8000
    command: ["npm", "run", "dev"]
    read_only: false
```

### `Makefile`

```makefile
.DEFAULT_GOAL := help
COMPOSE := docker compose
APP_VERSION ?= 1.0.0
GIT_COMMIT  := $(shell git rev-parse --short HEAD 2>/dev/null || echo local)

help: ## show targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-14s\033[0m %s\n",$$1,$$2}'

prod: ## build & run the PRODUCTION stack (nginx + JRE)
	$(COMPOSE) build --build-arg APP_VERSION=$(APP_VERSION) --build-arg GIT_COMMIT=$(GIT_COMMIT)
	$(COMPOSE) up -d --wait --timeout 180
	$(COMPOSE) ps

dev: ## run the DEVELOPMENT stack (hot reload, JDK, Vite dev server)
	$(COMPOSE) -f docker-compose.yml -f docker-compose.dev.yml up -d --build
	@echo "  frontend → http://localhost:5173   backend → http://localhost:8000"

down: ## stop and remove
	$(COMPOSE) down --remove-orphans
	-$(COMPOSE) -f docker-compose.yml -f docker-compose.dev.yml down --remove-orphans

logs: ## follow logs
	$(COMPOSE) logs -f --tail=100

smoke: ## verify the platform
	@set -e; \
	echo "--- production stack ---"; \
	curl -fsS localhost:8080/healthz      && echo " ✅ web healthz"; \
	curl -fsS localhost:8080/api/health   && echo " ✅ api via proxy"; \
	curl -fsS localhost:8080/api/tasks    >/dev/null && echo " ✅ tasks via proxy"; \
	curl -fsS localhost:8080/ | grep -q root && echo " ✅ SPA served"; \
	test $$(curl -s -o /dev/null -w '%{http_code}' localhost:8080/some/deep/route) = 200 \
	  && echo " ✅ SPA deep-link fallback"; \
	echo "--- isolation ---"; \
	(curl -s --max-time 2 localhost:8000/api/health >/dev/null && echo " ❌ api port is public!") \
	  || echo " ✅ api is NOT reachable from the host (only via nginx)"

sizes: ## compare Case 1 vs Case 2 image sizes
	@docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" | grep -E 'tasknest|tn-' || true

shell-web: ; $(COMPOSE) exec web sh
shell-api: ; $(COMPOSE) exec api sh
nuke:      ; $(COMPOSE) down -v --remove-orphans && docker system prune -f
```

### Run it

```bash
cd 10-react-java-fullstack
cp .env.example .env

make prod
# → http://localhost:8080        nginx serves the built React app AND proxies /api

make smoke
make sizes
```

**Expected `make sizes`:**

| Image | Case 1 | Case 2 |
|---|---|---|
| frontend | ~230 MB (node + dev deps) | **~52 MB** (nginx + static) |
| backend | ~600 MB (full JDK + Maven cache) | **~195 MB** (JRE + layered jar) |
| **total** | **~830 MB** | **~247 MB** |

---

## 🔬 The CORS lesson (why the proxy matters)

```bash
# Case 1: browser on :5173 calls API on :8000 → two different origins
curl -sI -H "Origin: http://localhost:5173" localhost:8000/api/tasks | grep -i access-control
# → Access-Control-Allow-Origin: *   (only because @CrossOrigin is on the controller)

# Case 2: browser on :8080 calls /api on :8080 → SAME origin, no CORS at all
curl -sI localhost:8080/api/tasks | grep -i access-control
# → (nothing — CORS headers are unnecessary)
```

| | Case 1 (two origins) | Case 2 (one origin via nginx) |
|---|---|---|
| Browser calls | `http://localhost:8000/api` | `http://localhost:8080/api` |
| Preflight `OPTIONS` requests | yes, on every non-simple call | none |
| Needs `@CrossOrigin` / CORS config | yes | **no** |
| Cookies / credentials | painful (`SameSite`, `withCredentials`) | trivial (same origin) |
| API exposed to the internet | **yes** 😱 | no — only nginx is public |
| Environment switching | rebuild the frontend with a new API URL | change nginx config only |

> 🎯 **Professional pattern:** the frontend build always uses a **relative** `/api` path; nginx decides where `/api` goes per environment. **One frontend image for dev, staging and production.**

---

## 🔨 Tasks for Project 10

> **10.1** Bring the stack up and confirm the isolation: `make prod && make smoke`. Then deliberately publish the api port (`ports: ["8000:8000"]`), restart, and show that `curl localhost:8000/api/tasks` now works from your host. Explain why that's a security regression, then revert it.

> **10.2** Break the DNS name. In `frontend/nginx.conf`, change `proxy_pass http://api:8000/;` to `http://backend:8000/;` and rebuild. What exact nginx error do you get, and at what moment does it appear (build time, container start, or first request)? Fix it, then explain how to make nginx tolerate a missing upstream at startup.

> **10.3** Prove the dependency ordering. Run `docker compose up -d` **without** `depends_on ... service_healthy` and watch `docker compose logs -f web`. What happens when nginx starts before the API is ready? Add the healthcheck condition back and compare.

> **10.4** Scale the backend. Remove nothing from `web`, but run `docker compose up -d --scale api=3`. Does it work? What must you change in the api service definition for scaling to be allowed, and how does nginx's `upstream` block handle multiple replicas?

> **10.5** Add a real database (PostgreSQL from Project 7) and make the Java backend use it. Add `spring-boot-starter-data-jpa` + `postgresql` to the POM, set `SPRING_DATASOURCE_URL=jdbc:postgresql://db:5432/app` from an env var, add `depends_on: db: service_healthy`, and verify data survives `docker compose down && up`.

> **10.6** Wire the dev override correctly. Run `make dev`, edit `frontend/src/App.jsx`, and confirm the browser updates without a rebuild. Then edit `backend/src/.../TaskController.java` — does it hot-reload? If not, what would you add? (Hint: `spring-boot-devtools`.)

<details>
<summary>👉 Answers</summary>

**10.1** Publishing `8000:8000` makes the API reachable directly from anything that can reach your host — bypassing nginx's TLS termination, rate limiting, auth, request filtering and logging. In production that's an unauthenticated admin surface. Revert: the API stays on the `backend` network only, reachable by service name from `web`.

**10.2** nginx resolves `proxy_pass` hostnames **at startup** when written as a literal. With a non-existent name you get `host not found in upstream "backend"` and **the container exits immediately** — `docker compose logs web` shows it, `docker compose ps` shows `Exited (1)`. Fix: use the correct service name (`api`). To tolerate a missing upstream at startup, use a variable + resolver:
```nginx
resolver 127.0.0.11 valid=10s ipv6=off;
set $api_upstream http://api:8000;
proxy_pass $api_upstream;
```
`127.0.0.11` is Docker's embedded DNS. With a variable, nginx defers resolution to request time and returns 502 instead of failing to boot — the right behaviour for rolling deploys.

**10.3** Without the health condition, `web` starts as soon as the `api` **container** exists (not when Spring finishes booting — which takes 5–20 s on a JVM). nginx's first proxied requests return **502 Bad Gateway**, and if the upstream was unresolvable at boot nginx may exit outright. With `condition: service_healthy`, Compose waits for the api healthcheck to pass, so `web` never starts too early. `docker compose up -d --wait` enforces it for the whole stack and blocks your CI until everything is healthy.

**10.4** It fails: Compose refuses to scale a service with a **`container_name`** or a **fixed host port** (`8000:8000` can only be bound once). Remove both (our production file already omits them for `api`). Then nginx's `upstream tasknest_api { server api:8000; }` works because Docker's embedded DNS returns **all** replica IPs for the name `api` and rotates them. For robust dynamic discovery add `resolver 127.0.0.11 valid=10s;` and use a variable in `proxy_pass`, plus `proxy_next_upstream error timeout http_502 http_503;` so a dead replica fails over instead of erroring.

**10.5** The key points: (a) `SPRING_DATASOURCE_URL/USERNAME/PASSWORD` as **env vars**, never in `application.properties`; (b) the hostname is the Compose **service name** `db`, not `localhost`; (c) `depends_on: {db: {condition: service_healthy}}` plus Spring's own retry; (d) `spring.jpa.hibernate.ddl-auto=validate` in production with real migrations (Flyway/Liquibase) — never `create-drop`; (e) data lives in a **named volume**, so `down && up` preserves it while `down -v` destroys it.

**10.6** The frontend hot-reloads because Vite's dev server watches the bind-mounted `src/` (`watch.usePolling: true` helps across the volume layer). The Java backend does **not** — `mvn spring-boot:run` compiles once at start. Add `spring-boot-devtools` as a `runtime`-scoped dependency and enable trigger-file reload, or mount `./backend/target/classes` and let devtools restart on change. Realistically most teams just rebuild the api image (`docker compose up -d --build api`) — a JVM dev loop is measured in tens of seconds, which is exactly why GraalVM native and tools like JRebel exist.
</details>

---

---

## ➡️ Next

**[`14-PROJECT-11-react-python-fullstack.md`](14-PROJECT-11-react-python-fullstack.md)** — Project 11.

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish%20Kumar%20Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn → <https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260>
🐙 GitHub → <https://github.com/3558Bhk>

*Built for engineers who learn by breaking things on purpose.*

</div>
