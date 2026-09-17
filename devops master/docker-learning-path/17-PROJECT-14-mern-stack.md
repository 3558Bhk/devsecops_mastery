# PROJECT 14 · 🟣 MERN Stack — React + Node/Express + MongoDB

> **Part of the Docker Learning Path.** Previous: [`16-PROJECT-13-databases.md`](16-PROJECT-13-databases.md) — Project 13 — Databases.
>
> 🎯 **Instructions & techniques:** npm workspaces · multi-stage Node builds · `--omit=dev` · `node_modules` pitfalls · runtime config for React · a **replica-set** MongoDB in Compose · healthchecks with `depends_on: condition` · `mongodump` backups
>
> 📚 **What you learn:** How to containerise a **full JavaScript stack** where the database ships *with* the application — and why that is harder than it looks
>
> 🔁 **Every project here is written TWICE:**
> - **🔵 CASE 1 — a SIMPLE Dockerfile.** Easy to read, easy to get working, usually too big for production.
> - **🟢 CASE 2 — a MULTI-STAGE Dockerfile.** The production version: smaller, faster to rebuild, more secure, tests can fail the build.
>
> **Build Case 1 first**, run it, understand it — then build Case 2 and **measure the difference**. That comparison *is* the lesson.

---

# D.7 — PROJECT 14 · 🟣 MERN Stack (React + Express + MongoDB)

**🎯 What you learn:** Projects 8–12 taught you one runtime at a time, and Project 13 taught you databases as *someone else's problem*. MERN collapses both assumptions:

- **One language, three tiers.** React, Express and your tooling all run on Node — so there is **one** lockfile, **one** build cache, **one** toolchain. That is the easy part.
- ⭐⭐ **The database is inside the release.** MongoDB is not a managed service you point at; it is a container in your `docker-compose.yml`, with a volume, a backup story and a schema **nobody enforces but your own code**.

```
THE SENTENCE THAT DEFINES THIS PROJECT:

   The toolchain got easier and the data got harder, at the same time.

   Postgres rejects a row that violates the schema. Your bad deploy FAILS,
   loudly, immediately, and the data stays clean.

   ⛔ MongoDB ACCEPTS it. Mongoose validates on the way IN — but only through
     your app. Anything that writes around the app writes whatever it likes.
```

---

## 14.0 Structure

```
14-mern-stack/
├── docker-compose.yml            ← 🔵 Case 1: everything, one file
├── docker-compose.prod.yml       ← 🟢 Case 2: the production overlay
├── docker-compose.ci.yml         ← ⭐ the E2E-test stack (built images, no dev server)
├── Makefile
├── .env.example
├── .dockerignore                 ← ⭐⭐ the file that makes or breaks the build cache
│
├── package.json                  ← ⭐ the WORKSPACES root
├── package-lock.json             ← ⭐⭐ ONE lockfile for all three tiers
├── .nvmrc                        ← 24
├── tsconfig.base.json
│
├── packages/
│   └── shared/                   ← ⭐⭐ THE CONTRACT (types + zod schemas)
│       ├── package.json          name: @shop-mern/shared
│       ├── src/api-types.ts
│       ├── src/routes.ts
│       └── tsconfig.json
│
├── apps/
│   ├── web/                      ← React 19 + Vite → nginx
│   │   ├── package.json
│   │   ├── vite.config.ts
│   │   ├── nginx/nginx.conf
│   │   ├── nginx/docker-entrypoint.d/40-inject-config.sh
│   │   ├── Dockerfile.simple     ← 🔵 Case 1
│   │   ├── Dockerfile            ← 🟢 Case 2
│   │   └── src/
│   │       ├── config.ts         ← ⭐ the ONLY reader of /config.js
│   │       └── api/client.ts
│   │
│   └── api/                      ← Node 24 + Express 5 + Mongoose 8
│       ├── package.json
│       ├── Dockerfile.simple     ← 🔵 Case 1
│       ├── Dockerfile            ← 🟢 Case 2
│       ├── src/
│       │   ├── server.ts         ← listen()
│       │   ├── app.ts            ← the express app, EXPORTED (so tests import it)
│       │   ├── db.ts             ← ⭐ the connection + the replica-set check
│       │   ├── health.ts         ← ⭐ /healthz and /readyz mean different things
│       │   └── routes/orders.ts
│       └── tests/
│           ├── unit/             ← no database
│           └── integration/      ← ⭐⭐ a REAL mongod
│
├── migrations/                   ← ⭐⭐ THE LEDGER YOU MUST BUILD
│   └── 20260910093000-backfill-total-cents.js
├── migrate-mongo-config.js
│
└── mongo/
    ├── mongod.conf               ← ⭐ container-tuned WiredTiger settings
    └── init-replica.sh           ← ⭐ rs.initiate(), idempotently
```

### The ports

| Service | Container port | Published in dev? | ⭐ Note |
|---|---|---|---|
| `mern-web` | 80 | ✅ `8080:80` | nginx serving a static bundle |
| `mern-api` | 4000 | ⛔ **no** | only reachable through nginx's proxy — like Project 12 |
| `mern-mongo` | 27017 | ⛔ **no** | ⛔ never publish a database to the host in anything but a throwaway dev stack |

---

## 14.1 ⭐ npm workspaces — one lockfile, and why that changes your Dockerfiles

```jsonc
// package.json (the root)
{
  "name": "shop-mern",
  "private": true,
  "workspaces": ["packages/*", "apps/*"],
  "engines": { "node": "24" },
  "scripts": {
    "build":     "npm run build -w @shop-mern/shared && npm run build --workspaces --if-present",
    "build:web": "npm run build -w @shop-mern/shared && NODE_OPTIONS=--max-old-space-size=6144 npm run build -w @shop-mern/web",
    "build:api": "npm run build -w @shop-mern/shared && npm run build -w @shop-mern/api",
    "test":      "vitest run --coverage",
    "lint":      "eslint . && prettier --check .",
    "typecheck": "tsc -b --pretty"
  }
}
```

⭐⭐ **The consequence that surprises everyone:** in a workspace monorepo, `npm ci` **fails** unless *every* workspace's `package.json` is present. So the "copy the manifests first, then the source" caching trick from Project 9 needs **all** of them:

```dockerfile
# ⛔ THIS FAILS: "npm error code ENOENT … no workspace configuration found"
COPY package.json package-lock.json ./
COPY apps/api/package.json apps/api/
RUN npm ci

# ✅ THIS WORKS — every workspace declared in the root must exist
COPY package.json package-lock.json ./
COPY packages/shared/package.json packages/shared/
COPY apps/api/package.json        apps/api/
COPY apps/web/package.json        apps/web/
RUN npm ci
```

| Property | ⭐ Why it matters |
|---|---|
| **One `package-lock.json`** | one cache key, one `npm ci`, one `npm audit` surface. Compare Project 11/12: two lockfiles, two caches |
| ⛔ never `npm install` in CI | it can **rewrite** the lockfile, so the artifact is no longer reproducible |
| ⭐ `packages/shared` builds **first** | both apps import it; skip it and you get confusing "cannot find module" errors instead of real ones |
| ⛔ the cost | a dependency bump in `apps/web` invalidates the cache for `apps/api` too. `npm ci` is fast enough (20 s warm) that this is acceptable |

### ⭐⭐ `.dockerignore` — the file that makes or breaks the build cache

```gitignore
# .dockerignore  ← lives at the BUILD CONTEXT root
**/node_modules          # ⭐⭐ THE MOST IMPORTANT LINE IN THIS PROJECT
**/dist
**/.git
**/coverage
**/.venv
**/*.log
.env
.env.*
**/.DS_Store
**/test-results
**/playwright-report
```

```
⛔ WITHOUT `**/node_modules` IN .dockerignore:

   COPY . . sends your HOST's node_modules into the image.
   • it is built for YOUR platform (macOS arm64) — native modules
     (bcrypt, sharp, esbuild) SEGFAULT in the linux/amd64 container
   • it invalidates the cache on EVERY build, because node_modules
     changes whenever you install anything
   • it is 300 MB of build context uploaded to the daemon each time
   • ⛔ and it SILENTLY OVERWRITES the node_modules your RUN npm ci
     just created correctly, if the COPY comes after

   THE SYMPTOM: "works on my machine, segfaults in the container."
   THE FIX: one line in .dockerignore.
```

---

## 14.2 The API — the application

```typescript
// apps/api/src/app.ts — ⭐ EXPORTED SEPARATELY FROM listen()
import express from 'express';
import { health } from './health.js';
import { orders } from './routes/orders.js';

export function createApp() {
  const app = express();
  app.disable('x-powered-by');              // ⭐ do not advertise the framework
  app.use(express.json({ limit: '100kb' })); // ⭐⭐ CAP THE BODY. An uncapped
                                             //   JSON body is a memory-exhaustion
                                             //   DoS: 2 GB of JSON parses fine.
  app.use(health);
  app.use(orders);
  app.use((_req, res) => res.status(404).json({ error: 'NOT_FOUND' }));
  return app;
}
```

```typescript
// apps/api/src/db.ts — ⭐⭐ three settings that decide whether production survives
import mongoose from 'mongoose';

export async function connect() {
  await mongoose.connect(process.env.MONGODB_URL!, {
    autoIndex:  false,     // ⭐⭐ NEVER let Mongoose build indexes at boot (§14.8)
    autoCreate: false,     // ⛔ never let the app create databases either
    serverSelectionTimeoutMS: 10_000,
    maxPoolSize: Number(process.env.MONGO_POOL_SIZE ?? 20),
  });

  // ⭐⭐ FAIL FAST if this is not a replica set and we intend to use transactions
  const hello = await mongoose.connection.db!.admin().command({ hello: 1 });
  if (!hello.setName && process.env.REQUIRE_REPLICA_SET === 'true') {
    throw new Error(
      '⛔ transactions require a replica set; connected to a standalone mongod');
  }
  console.log(`✅ mongo connected · ${hello.setName ?? 'standalone'} · primary=${hello.primary}`);
}

export async function disconnect() { await mongoose.disconnect(); }
```

```typescript
// apps/api/src/health.ts — ⭐⭐ the two endpoints must mean DIFFERENT things
import { Router } from 'express';
import mongoose from 'mongoose';
import { CONTRACT_VERSION } from '@shop-mern/shared';

export const health = Router();

// LIVENESS: "can the process respond at all?"
// ⛔ MUST NOT TOUCH MONGO. If it did, a 5-second mongo blip would make
//   every instance unhealthy at once — and in Kubernetes it would
//   restart-loop your entire fleet, turning an outage into a worse outage.
health.get('/healthz', (_req, res) => res.status(200).json({ ok: true }));

// READINESS: "can I serve a REAL request?" — ⭐ MUST touch mongo.
health.get('/readyz', async (_req, res) => {
  try {
    if (mongoose.connection.readyState !== 1)
      return res.status(503).json({ ok: false, reason: 'mongo-not-connected' });

    await mongoose.connection.db!.admin().command({ ping: 1 });   // ⭐ real round-trip

    const hello = await mongoose.connection.db!.admin().command({ hello: 1 });
    if (process.env.REQUIRE_REPLICA_SET === 'true' && !hello.setName)
      return res.status(503).json({ ok: false, reason: 'not-a-replica-set' });

    res.json({ ok: true, replicaSet: hello.setName ?? null,
               contract: CONTRACT_VERSION, digest: process.env.APP_DIGEST ?? 'dev' });
  } catch (e) {
    res.status(503).json({ ok: false, reason: String(e) });
  }
});
```

```typescript
// apps/api/src/server.ts — ⭐⭐ GRACEFUL SHUTDOWN, the part everyone skips
import { createApp } from './app.js';
import { connect, disconnect } from './db.js';

const app = createApp();
const server = app.listen(4000, () => console.log('✅ api on :4000'));

// ⭐ Node has NO default SIGTERM handling. Without this, `docker stop`
//   waits 10 s and then SIGKILLs you mid-request.
let shuttingDown = false;
async function shutdown(signal: string) {
  if (shuttingDown) return;
  shuttingDown = true;
  console.log(`⏻ ${signal} — draining`);

  // ⭐ 1. stop the HEALTH endpoints answering "ready" FIRST, so the
  //       load balancer / Kubernetes removes us from rotation
  //    2. stop accepting NEW connections and finish the IN-FLIGHT ones
  const timer = setTimeout(() => {
    console.error('⛔ drain timed out — forcing'); process.exit(1);
  }, 9_000);                                        // ⭐ < Docker's 10 s stop grace

  server.close(async () => {                        // ⭐ close(), NOT closeAllConnections()
    clearTimeout(timer);
    try { await disconnect(); }                     // ⭐ flush the mongo pool
    catch (e) { console.error('mongo disconnect failed', e); }
    console.log('✅ drained cleanly'); process.exit(0);
  });
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT',  () => shutdown('SIGINT'));

// ⭐ an unhandled rejection in Node 24 terminates the process by default.
//   Log it, then let it die — do NOT swallow it and keep serving corrupt state.
process.on('unhandledRejection', (r) => { console.error('💥 unhandledRejection', r); });
process.on('uncaughtException',  (e) => { console.error('💥 uncaughtException', e);
                                          shutdown('uncaughtException'); });
```

### ⭐⭐ The Node PID 1 problem

```
⛔ THE SYMPTOM: `docker stop` always takes exactly 10 seconds and the
   container exits 137, even though you wrote a perfect SIGTERM handler.

   WHY: if your CMD runs node via a SHELL (`CMD npm start`), then PID 1 is
   `sh`, and sh does NOT forward SIGTERM to its child. Your handler never
   fires. Docker waits the 10 s grace period, then SIGKILLs.

✅ THREE FIXES, in order of preference:
   1. ⭐ exec form:  CMD ["node", "apps/api/dist/server.js"]
      → node IS PID 1 and receives SIGTERM directly
   2. ⭐ an init:    docker run --init …  (or `init: true` in compose)
      → tini is PID 1, forwards signals, AND reaps zombies
   3. dumb-init / tini in the image, ENTRYPOINT ["dumb-init","--"]

   ⭐ Node as PID 1 is fine for signals but does NOT reap orphaned
     grandchildren. If your app spawns child processes, use --init.
```

---

## 14.3 ⭐⭐ MongoDB as a replica set — in Compose

```
THE FACT THAT BREAKS MOST MERN STACKS:

   Mongoose's session.withTransaction() — and therefore ANY multi-document
   atomicity — REQUIRES A REPLICA SET.

   Against a standalone mongod it throws:
      MongoServerError: Transaction numbers are only allowed on a
      replica set member or mongos

   ⛔ AND THE WORSE VERSION: code guarded by `if (session)` silently SKIPS
     the transaction. Your "atomic" order creation is not atomic, your tests
     pass, and you find out during an incident.

   ⭐ So: run a replica set even in dev. A ONE-MEMBER replica set is fine
     and costs nothing.
```

```bash
#!/bin/sh
# mongo/init-replica.sh — ⭐⭐ IDEMPOTENT: "already initialized" is SUCCESS
set -eu
echo "waiting for mongod to accept connections…"
for i in $(seq 1 30); do
  if mongosh --quiet --eval 'db.adminCommand({ping:1}).ok' >/dev/null 2>&1; then break; fi
  sleep 1
done

OUT=$(mongosh --quiet --eval '
  try {
    rs.initiate({ _id: "rs0", members: [ { _id: 0, host: "mern-mongo:27017" } ] });
    "ok"
  } catch (e) {
    e.codeName === "AlreadyInitialized" ? "ok" : "fail:" + e.message
  }')

echo "$OUT" | grep -q '^ok$' || { echo "⛔ rs.initiate failed: $OUT"; exit 1; }

# ⭐ wait until there is actually a PRIMARY — initiate is asynchronous
for i in $(seq 1 30); do
  mongosh --quiet --eval 'rs.status().members[0].stateStr' | grep -q PRIMARY && break
  sleep 1
done
echo "✅ replica set rs0 has a PRIMARY"
```

```yaml
# docker-compose.yml — 🔵 CASE 1: the whole stack, readable
name: shop-mern

services:
  # ── ⭐⭐ MONGODB — a ONE-MEMBER REPLICA SET, not a standalone ──────────
  mern-mongo:
    image: mongo:8.0                       # ⭐ pinned minor; ⛔ never :latest
    container_name: mern-mongo
    command: ["--replSet", "rs0", "--bind_ip_all"]
    # ⭐ --bind_ip_all: by default mongod binds 127.0.0.1 ONLY, and the api
    #   container cannot reach it. The #1 "why can't my app connect" answer.
    environment:
      MONGO_INITDB_ROOT_USERNAME: shop
      MONGO_INITDB_ROOT_PASSWORD: shop-pass   # ⭐ dev only — see .env below
    volumes:
      - mongo-data:/data/db                   # ⭐⭐ NAMED VOLUME. Without it,
      - mongo-config:/data/configdb           #   `docker compose down` destroys
      - ./mongo/init-replica.sh:/init-replica.sh:ro   #   every document you have
    # ⭐ run the initiator ONCE, after mongod is up
    healthcheck:
      test: ["CMD", "mongosh", "--quiet", "-u", "shop", "-p", "shop-pass",
             "--authenticationDatabase", "admin",
             "--eval", "rs.status().ok === 1 && db.hello().isWritablePrimary"]
      interval: 10s
      timeout: 5s
      retries: 12
      start_period: 40s        # ⭐ replica-set election takes a few seconds
    networks: [mern]
    # ⛔ NO `ports:` — nothing outside this compose network should reach mongo

  # ── the replica-set initiator: runs once and exits ────────────────────
  mongo-init:
    image: mongo:8.0
    depends_on:
      mern-mongo: { condition: service_started }
    entrypoint: ["sh", "/init-replica.sh"]
    volumes:
      - ./mongo/init-replica.sh:/init-replica.sh:ro
    environment:
      MONGO_INITDB_ROOT_USERNAME: shop
      MONGO_INITDB_ROOT_PASSWORD: shop-pass
    networks: [mern]
    restart: "no"              # ⭐ it must NOT loop

  # ── EXPRESS API ───────────────────────────────────────────────────────
  mern-api:
    build: { context: ., dockerfile: apps/api/Dockerfile.simple }
    image: shop-mern-api:dev
    container_name: mern-api
    init: true                 # ⭐⭐ PID 1 forwards SIGTERM and reaps zombies
    environment:
      NODE_ENV: development
      PORT: "4000"
      # ⭐⭐ list the replica-set name, or the driver treats it as standalone
      MONGODB_URL: mongodb://shop:shop-pass@mern-mongo:27017/shop?replicaSet=rs0&authSource=admin&retryWrites=true&w=majority
      REQUIRE_REPLICA_SET: "true"
      APP_DIGEST: dev
    depends_on:
      # ⭐⭐ `condition: service_healthy`, NOT `service_started`.
      #   started means "the process launched"; healthy means "it can serve".
      #   With service_started the api connects before mongod accepts
      #   connections, fails, and crash-loops — the classic Compose bug.
      mern-mongo: { condition: service_healthy }
      mongo-init: { condition: service_completed_successfully }
    healthcheck:
      test: ["CMD", "node", "-e",
             "fetch('http://127.0.0.1:4000/readyz').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"]
      interval: 10s
      timeout: 5s
      retries: 6
      start_period: 20s
    networks: [mern]
    # ⛔ NO `ports:` — reachable only through mern-web's proxy (Project 12's lesson)

  # ── REACT + NGINX ─────────────────────────────────────────────────────
  mern-web:
    build: { context: ., dockerfile: apps/web/Dockerfile.simple }
    image: shop-mern-web:dev
    container_name: mern-web
    ports: ["8080:80"]         # ⭐ the ONLY published port in the stack
    environment:
      MERN_API_URL: "http://mern-api:4000"   # ⭐⭐ injected at RUNTIME (§14.5)
      MERN_ENV: development
      APP_DIGEST: dev
    depends_on:
      mern-api: { condition: service_healthy }
    networks: [mern]

volumes:
  mongo-data:       # ⭐⭐ the data. `docker compose down` keeps it;
  mongo-config:     #    `down -v` DESTROYS it. Know the difference.

networks:
  mern: { driver: bridge }
```

### ⭐ The five Compose details that decide whether this works

| # | Detail | ⛔ If you skip it |
|---|---|---|
| 1 | `condition: service_healthy` | the api starts before mongod accepts connections and crash-loops |
| 2 | ⭐ `condition: service_completed_successfully` on `mongo-init` | the api connects to a replica set that has no PRIMARY yet |
| 3 | ⭐⭐ `--bind_ip_all` | mongod binds 127.0.0.1 and the api container gets `ECONNREFUSED` |
| 4 | ⭐ `replicaSet=rs0` in the connection string | the driver treats it as standalone; transactions throw |
| 5 | ⭐ `init: true` | `docker stop` takes 10 s and SIGKILLs mid-request |

```bash
docker compose up -d --wait       # ⭐ --wait BLOCKS until every service is healthy
docker compose ps                 # ✅ all three "healthy", mongo-init "exited (0)"
```

---

## 14.4 🔵 CASE 1 — SIMPLE Dockerfiles

### `apps/api/Dockerfile.simple`

```dockerfile
# syntax=docker/dockerfile:1
# ═══════════════════════════════════════════════════════════════════════
# 🔵 CASE 1 — simple: one stage, everything included
# ═══════════════════════════════════════════════════════════════════════
FROM node:24-alpine

WORKDIR /app

# copy the manifests first — this layer still caches even in Case 1
COPY package.json package-lock.json ./
COPY packages/shared/package.json packages/shared/
COPY apps/api/package.json        apps/api/
COPY apps/web/package.json        apps/web/

# ⛔ installs EVERYTHING: vitest, playwright, typescript, eslint — ~300 MB
#   of tooling that is pure attack surface in a runtime image
RUN npm ci

# ⛔ copies the SOURCE too — including tests, tsconfig, and anything else
#   your .dockerignore forgot
COPY . .

RUN npm run build -w @shop-mern/shared && npm run build -w @shop-mern/api

EXPOSE 4000
CMD ["node", "apps/api/dist/server.js"]
```

### `apps/web/Dockerfile.simple`

```dockerfile
# syntax=docker/dockerfile:1
# 🔵 CASE 1 — simple
FROM node:24-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
COPY packages/shared/package.json packages/shared/
COPY apps/web/package.json        apps/web/
COPY apps/api/package.json        apps/api/
RUN npm ci
COPY . .
RUN npm run build -w @shop-mern/shared && npm run build -w @shop-mern/web
# ⛔ no NODE_OPTIONS ceiling → a large app dies with
#   "FATAL ERROR: Reached heap limit Allocation failed"

FROM nginx:1.29-alpine
COPY --from=build /app/apps/web/dist /usr/share/nginx/html
# ⛔ default nginx config: index.html is cached, so a deploy can take HOURS
#   to reach users (§14.5)
EXPOSE 80
```

```bash
docker compose -f docker-compose.yml build
docker images --format 'table {{.Repository}}\t{{.Size}}' | grep shop-mern
# 🔵 CASE 1 RESULT (record your own):
#   shop-mern-api   ~1.1 GB     ⛔ the full node_modules, dev deps included
#   shop-mern-web   ~50 MB      ✅ already fine — nginx, not node
```

---

## 14.5 🟢 CASE 2 — MULTI-STAGE Dockerfiles

### ⭐⭐ The React runtime-config discipline — one image, every environment

```
⛔ THE TRAP (and it is the single most expensive frontend mistake):

   # .env.production
   VITE_API_URL=https://api.shop.example.com
   RUN npm run build          ← the URL is COMPILED INTO THE JAVASCRIPT

   Now the image is bound to ONE environment. To deploy to staging you must
   BUILD AGAIN — and the artifact you tested is not the artifact you ship.
   ⛔ That breaks the entire premise of this learning path: the digest that
     leaves CI must be the digest that CD deploys.

✅ THE FIX: inject the config at CONTAINER START, from the real environment.
```

```typescript
// apps/web/src/config.ts — ⭐ the ONLY place that reads window.__APP_CONFIG__
export interface AppConfig { apiUrl: string; env: string; digest: string }

let cached: AppConfig | null = null;

export function cfg(): AppConfig {
  if (cached) return cached;
  const w = window as unknown as { __APP_CONFIG__?: Partial<AppConfig> };
  // ⭐⭐ a MISSING config.js must fail LOUDLY, not render a blank page
  if (!w.__APP_CONFIG__?.apiUrl) {
    console.error('⛔ /config.js did not load — the entrypoint injection failed');
    throw new Error('APP_CONFIG_MISSING');
  }
  cached = { env: 'development', digest: 'dev', ...w.__APP_CONFIG__ } as AppConfig;
  return cached;
}
```

```bash
#!/bin/sh
# apps/web/nginx/docker-entrypoint.d/40-inject-config.sh
# ⭐ nginx:alpine runs every executable in /docker-entrypoint.d/ BEFORE nginx
#   starts. Numbered 10-, 20-, 30- are the defaults; 40- runs after them.
set -eu

: "${MERN_API_URL:=http://localhost:4000}"
: "${MERN_ENV:=development}"
: "${APP_DIGEST:=unknown}"

# ⭐⭐ ESCAPE THE VALUES. A quote, backslash or newline in an env var
#   otherwise produces a config.js that is a SYNTAX ERROR — and the SPA
#   renders a blank page with no error you can see.
esc() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }

cat > /usr/share/nginx/html/config.js <<EOF
window.__APP_CONFIG__ = {
  "apiUrl": "$(esc "$MERN_API_URL")",
  "env":    "$(esc "$MERN_ENV")",
  "digest": "$(esc "$APP_DIGEST")"
};
EOF
echo "✅ config.js written: env=$MERN_ENV api=$MERN_API_URL digest=$APP_DIGEST"
```

```nginx
# apps/web/nginx/nginx.conf
server {
  listen 80;
  server_name _;
  root /usr/share/nginx/html;
  index index.html;

  # ⭐⭐ CACHE HEADERS — this block is the difference between a 90-second
  #   deploy and a four-hour deploy.
  #   index.html must NEVER be cached, or users keep loading a bundle that
  #   references hashed asset filenames that no longer exist → a blank page.
  location = /index.html {
    add_header Cache-Control "no-cache, must-revalidate";
    etag on;
  }
  # hashed assets are immutable — cache them forever
  location /assets/ {
    add_header Cache-Control "public, max-age=31536000, immutable";
    access_log off;
  }
  # ⭐⭐ config.js is per-environment: NEVER cache it, anywhere
  location = /config.js {
    add_header Cache-Control "no-store";
    access_log off;
  }

  # ⭐ proxy the API so the browser sees ONE origin → no CORS at all
  location /api/ {
    proxy_pass         http://mern-api:4000;
    proxy_http_version 1.1;
    proxy_set_header   Host              $host;
    proxy_set_header   X-Real-IP         $remote_addr;
    proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
    proxy_set_header   X-Forwarded-Proto $scheme;
    # ⭐ fail over instead of serving a 502 from a restarting upstream
    proxy_next_upstream error timeout http_502 http_503 http_504;
    proxy_connect_timeout 2s;
    proxy_read_timeout    30s;
  }

  location = /healthz { return 200 "ok\n"; add_header Content-Type text/plain; }

  # ⭐ SPA fallback: every unknown path serves index.html
  location / { try_files $uri $uri/ /index.html; }

  # ⭐ basic hardening
  add_header X-Content-Type-Options nosniff always;
  add_header X-Frame-Options        DENY    always;
  add_header Referrer-Policy        strict-origin-when-cross-origin always;
  server_tokens off;
  client_max_body_size 1m;             # ⭐ cap uploads at the edge
}
```

```dockerfile
# apps/web/Dockerfile  — 🟢 CASE 2
# syntax=docker/dockerfile:1
# ═══════════════════════════════════════════════════════════════════════
# 🟢 CASE 2 — production: workspace-aware, cached, runtime-configured
# ═══════════════════════════════════════════════════════════════════════

# ── stage 1: install ───────────────────────────────────────────────────
FROM node:24-alpine AS deps
WORKDIR /repo
COPY package.json package-lock.json ./
COPY packages/shared/package.json packages/shared/
COPY apps/web/package.json        apps/web/
COPY apps/api/package.json        apps/api/     # ⭐ every workspace, or npm ci fails
RUN --mount=type=cache,target=/root/.npm \
    npm ci --workspace=@shop-mern/shared --workspace=@shop-mern/web

# ── stage 2: build ─────────────────────────────────────────────────────
FROM node:24-alpine AS build
WORKDIR /repo
COPY --from=deps /repo/node_modules ./node_modules
COPY package.json package-lock.json tsconfig.base.json ./
COPY packages/shared/ packages/shared/
COPY apps/web/        apps/web/
# ⭐⭐ shared FIRST — apps/web imports it
RUN npm run build -w @shop-mern/shared
# ⭐⭐ THE VITE HEAP CEILING. Without it a large React app dies with
#   "FATAL ERROR: Reached heap limit Allocation failed" — which looks
#   exactly like a bug in your code.
RUN NODE_OPTIONS=--max-old-space-size=6144 npm run build -w @shop-mern/web

# ⭐ stage 2b: ⛔ TESTS CAN FAIL THE BUILD
FROM build AS test
RUN npm run typecheck && npm run test -- --run --coverage.thresholds.lines=80
#    ↑ if this fails, there is NO runtime stage, so `docker build` FAILS.
#      That is the point: an untested image cannot exist.

# ── stage 3: runtime ───────────────────────────────────────────────────
FROM nginx:1.29-alpine AS runtime
COPY apps/web/nginx/nginx.conf /etc/nginx/conf.d/default.conf
COPY apps/web/nginx/docker-entrypoint.d/40-inject-config.sh /docker-entrypoint.d/
RUN chmod +x /docker-entrypoint.d/40-inject-config.sh
COPY --from=test /repo/apps/web/dist /usr/share/nginx/html
EXPOSE 80
# ⭐ nginx:alpine already runs workers as the unprivileged `nginx` user
HEALTHCHECK --interval=10s --timeout=3s --retries=3 \
  CMD wget -qO- http://127.0.0.1/healthz >/dev/null || exit 1
# ⛔ no CMD — the base image's entrypoint runs /docker-entrypoint.d/* then nginx
```

### `apps/api/Dockerfile` — 🟢 CASE 2

```dockerfile
# syntax=docker/dockerfile:1
# ═══════════════════════════════════════════════════════════════════════
# 🟢 CASE 2 — production: three stages, --omit=dev, non-root, tested
# ═══════════════════════════════════════════════════════════════════════

# ── stage 1: PRODUCTION dependencies only ──────────────────────────────
FROM node:24-alpine AS deps
WORKDIR /repo
COPY package.json package-lock.json ./
COPY packages/shared/package.json packages/shared/
COPY apps/api/package.json        apps/api/
COPY apps/web/package.json        apps/web/
RUN --mount=type=cache,target=/root/.npm \
    npm ci --workspace=@shop-mern/shared --workspace=@shop-mern/api --omit=dev
    # ⭐⭐ --omit=dev: no vitest, no playwright, no typescript, no eslint.
    #   ~300 MB smaller AND a much smaller CVE surface.

# ── stage 2: build (needs devDependencies, so a SEPARATE install) ──────
FROM node:24-alpine AS build
WORKDIR /repo
COPY package.json package-lock.json tsconfig.base.json ./
COPY packages/shared/package.json packages/shared/
COPY apps/api/package.json        apps/api/
COPY apps/web/package.json        apps/web/
RUN --mount=type=cache,target=/root/.npm npm ci
COPY packages/shared/ packages/shared/
COPY apps/api/        apps/api/
RUN npm run build -w @shop-mern/shared && npm run build -w @shop-mern/api

# ── stage 2b: ⛔ TESTS FAIL THE BUILD ──────────────────────────────────
FROM build AS test
# ⭐ a REAL mongod, not a mock. See §14.7 for how to provide one.
RUN npm run typecheck && npm run test -- --run apps/api/tests
#    Integration tests need MONGODB_URL. Two options:
#      (a) run them OUTSIDE the build (in CI, against a sidecar) — ⭐ preferred
#      (b) `docker build --target test` with a BuildKit secret + network=host
#    ⛔ Do NOT put `network=host` in a production Dockerfile stage.

# ── stage 3: runtime ───────────────────────────────────────────────────
FROM node:24-alpine AS runtime
RUN addgroup -S app && adduser -S app -G app
WORKDIR /app
ENV NODE_ENV=production \
    PORT=4000 \
    # ⭐⭐ THE HEAP CEILING. Node reads the cgroup limit since v14, but an
    #   explicit ceiling stops the heap growing INTO the container limit —
    #   which produces an OOMKill with NO JavaScript error at all, only
    #   "Exit Code 137". Size it to ~75% of the container limit.
    NODE_OPTIONS="--max-old-space-size=384" \
    NPM_CONFIG_UPDATE_NOTIFIER=false

# ⭐ copy ONLY what runs: production node_modules and the two dist trees
COPY --from=deps  --chown=app:app /repo/node_modules              ./node_modules
COPY --from=build --chown=app:app /repo/packages/shared/dist      ./packages/shared/dist
COPY --from=build --chown=app:app /repo/packages/shared/package.json ./packages/shared/
COPY --from=build --chown=app:app /repo/apps/api/dist             ./apps/api/dist
COPY --from=build --chown=app:app /repo/apps/api/package.json     ./apps/api/
# ⭐ migrations ship with the image, so the SAME digest migrates and serves
COPY --chown=app:app migrations/              ./migrations/
COPY --chown=app:app migrate-mongo-config.js  ./

USER app                     # ⭐⭐ non-root. uid 1000 in node:alpine is `node`;
EXPOSE 4000                  #   creating `app` is explicit and reviewable.

# ⭐ a HEALTHCHECK in the image, so `docker compose` and plain Docker agree
#   with Kubernetes about what "healthy" means
HEALTHCHECK --interval=10s --timeout=3s --start-period=15s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:4000/readyz').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
# ⭐ uses node's own fetch — no curl or wget needed in the image

# ⭐⭐ exec form, so node IS PID 1 and receives SIGTERM (§14.2)
CMD ["node", "apps/api/dist/server.js"]
```

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml build
docker images --format 'table {{.Repository}}\t{{.Size}}' | grep shop-mern
```

---

## 14.6 🔬 The two-way comparison

| | 🔵 Case 1 | 🟢 Case 2 | ⭐ Why it matters |
|---|---|---|---|
| **api image size** | ~1.1 GB | ⭐ **~180 MB** | `--omit=dev` + copying only `dist` |
| **web image size** | ~50 MB | ~50 MB | nginx was already right |
| **Build context** | ⛔ huge without `.dockerignore` | ⭐ small | `**/node_modules` |
| **Cache on a source change** | ⛔ reinstalls everything | ⭐ deps layer cached | manifests copied first |
| **Dev tooling in the runtime** | ⛔ vitest, playwright, tsc | ✅ none | ⭐ 300 MB of attack surface |
| **Source code in the runtime** | ⛔ all of it, incl. tests | ✅ only `dist` | your tests are readable in prod |
| **Runs as** | ⛔ root | ✅ `app` (non-root) | |
| **Tests can fail the build** | ⛔ no | ✅ a `test` stage | an untested image cannot exist |
| **React API URL** | ⛔ baked at build time | ⭐ injected at start | **one image, every environment** |
| **`index.html` caching** | ⛔ default (cached) | ⭐ `no-cache` | a 90 s deploy vs a 4 h deploy |
| **SIGTERM** | ⛔ 10 s then SIGKILL | ✅ drains in ~1 s | `init: true` + `server.close()` |
| **Rebuild after a source edit** | ~90 s | ⭐ ~20 s | |

```bash
# ⭐ MEASURE IT, do not trust the table
for f in apps/api/Dockerfile.simple apps/api/Dockerfile; do
  printf '%-34s ' "$f"
  docker build -q -f "$f" -t measure:$(basename $(dirname $f))-$(basename $f) . >/dev/null
  docker images --format '{{.Size}}' measure:$(basename $(dirname $f))-$(basename $f)
done

# ⭐ and prove the runtime contains no dev tooling
docker run --rm --entrypoint sh shop-mern-api:prod -c \
  'ls node_modules | grep -cE "^(vitest|playwright|typescript|eslint)$"'
# ✅ EXPECT: 0
```

### ⭐ Prove one image serves every environment

```bash
docker build -f apps/web/Dockerfile -t mern-web:test .

# environment A
docker run -d --name a -e MERN_API_URL=http://api-a:4000 -e MERN_ENV=staging \
  -p 9001:80 mern-web:test
# environment B — ⭐ THE SAME IMAGE, a different digest would defeat the point
docker run -d --name b -e MERN_API_URL=http://api-b:4000 -e MERN_ENV=production \
  -p 9002:80 mern-web:test

curl -s localhost:9001/config.js     # ✅ apiUrl: http://api-a:4000, env: staging
curl -s localhost:9002/config.js     # ✅ apiUrl: http://api-b:4000, env: production
docker inspect -f '{{.Image}}' a b   # ✅ IDENTICAL

# ⛔ and prove nothing was baked in at build time
docker run --rm --entrypoint sh mern-web:test -c \
  'grep -rl "api-a\|api-b\|localhost:4000" /usr/share/nginx/html/assets/ | wc -l'
# ✅ EXPECT: 0     ⛔ non-zero means you have a build-time env var somewhere

# ⭐ cache headers
curl -sI localhost:9001/index.html | grep -i cache-control   # ✅ no-cache
curl -sI localhost:9001/config.js  | grep -i cache-control   # ✅ no-store
curl -sI localhost:9001/assets/$(docker run --rm --entrypoint sh mern-web:test -c \
  'ls /usr/share/nginx/html/assets | head -1') | grep -i cache-control  # ✅ immutable

docker rm -f a b
```

---

## 14.7 ⭐⭐ Testing against a REAL mongod

```
⛔ mongodb-memory-server — the default in most MERN tutorials, and WRONG for CI:
     1. ⛔ it DOWNLOADS a mongod binary at first run → your CI is not
        hermetic, and a MongoDB CDN outage fails your build
     2. ⛔ the version it downloads is whatever it resolves to, NOT your 8.0
     3. ⛔ it runs STANDALONE → transactions silently do not work
     4. ⛔ an ephemeral storage engine → no real WAL, no real index builds

   Tests that pass on it and fail in production. That is the H2-for-Postgres
   problem (Project 9's lesson), in JavaScript.

✅ THREE real options, best first:
```

| Option | How | ⭐ When |
|---|---|---|
| **A compose test stack** | `docker-compose.ci.yml` with a real `mongo:8.0 --replSet rs0` + an init job, then `vitest run` against it | ⭐ local + any CI with a Docker daemon |
| **`@testcontainers/mongodb`** | `new MongoDBContainer('mongo:8.0').start()` — ⭐ it starts a **single-node replica set** for you | ⭐ CI with a Docker daemon; per-test isolation |
| **A sidecar mongod** | a second container in the build/agent pod with `--replSet rs0` + `rs.initiate()` | ⭐⭐ CI **without** a daemon (a Kubernetes agent) |

```yaml
# docker-compose.ci.yml — ⭐ the stack your E2E tests run against
name: shop-mern-ci
services:
  mern-mongo:
    image: mongo:8.0
    command: ["--replSet", "rs0", "--bind_ip_all"]
    healthcheck:
      test: ["CMD", "mongosh", "--quiet", "--eval", "db.hello().ok"]
      interval: 5s
      retries: 20
      start_period: 20s
  mongo-init:
    image: mongo:8.0
    depends_on: { mern-mongo: { condition: service_started } }
    entrypoint: ["mongosh","--host","mern-mongo","--quiet","--eval",
                 "try{rs.initiate();'ok'}catch(e){e.codeName==='AlreadyInitialized'?'ok':'fail'}"]
    restart: "no"
  mern-api:
    image: shop-mern-api:${DIGEST:-prod}       # ⭐⭐ a DIGEST in CI, never :latest
    init: true
    environment:
      MONGODB_URL: mongodb://mern-mongo:27017/shop_ci?replicaSet=rs0&retryWrites=true&w=majority
      REQUIRE_REPLICA_SET: "true"
    depends_on:
      mern-mongo: { condition: service_healthy }
      mongo-init: { condition: service_completed_successfully }
    healthcheck:
      test: ["CMD","node","-e","fetch('http://127.0.0.1:4000/readyz').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"]
      interval: 5s
      retries: 20
  mern-web:
    image: shop-mern-web:${DIGEST:-prod}
    ports: ["8080:80"]
    environment: { MERN_API_URL: "http://mern-api:4000", MERN_ENV: ci }
    depends_on: { mern-api: { condition: service_healthy } }
```

```bash
# ⭐⭐ RUN PLAYWRIGHT AGAINST THE BUILT IMAGES — not the dev server
docker compose -f docker-compose.ci.yml up -d --wait
curl -fsS localhost:8080/config.js | grep -q apiUrl && echo "✅ runtime config injected"
npx playwright test --project=chromium
docker compose -f docker-compose.ci.yml logs --tail=200 > e2e-logs.txt || true
docker compose -f docker-compose.ci.yml down -v
```

```
⛔ WHY "npm run dev + playwright" IS WORTHLESS AS A SHIP GATE:
   the dev server serves UNBUNDLED ESM with Vite's env handling, a permissive
   host/CORS config, and NO config.js, NO CSP, NO cache headers.
   The production image serves a BUNDLED SPA from nginx with all of those.
   ⭐ THEY ARE DIFFERENT PROGRAMS. The classic symptom: CI is green and the
     image shows a BLANK PAGE — usually a missing config.js, so cfg() throws.
```

---

## 14.8 ⭐⭐ `autoIndex` — the setting that takes production down

```javascript
// ⛔ THE LINE THAT DESTROYS PRODUCTION
await mongoose.connect(url);      // Mongoose's default is autoIndex: TRUE
// → on EVERY process start, Mongoose calls createIndex for every index in
//   every schema.
```

```
WHY IT IS DANGEROUS:
  1. ⛔ createIndex on a large collection is EXPENSIVE. During a rolling
     update it runs on every new instance simultaneously.
  2. ⛔ RENAMING an index in the schema creates the new one but NEVER drops
     the old → index bloat → slower writes → more RAM.
  3. ⛔⛔ Model.syncIndexes() — which many tutorials recommend — DROPS
     indexes not in the schema. With 3 instances rolling, an OLD instance
     re-creates what a NEW one just dropped. Query plans change mid-rollout.
  4. ⛔ A MISSING index in production = a collection scan = the database
     falls over under normal load, minutes after a "successful" deploy.

✅ autoIndex: false ALWAYS (in code, not via an env var, so it cannot be
   turned on by accident). Indexes come from a MIGRATION (§14.9).
```

---

## 14.9 ⭐⭐ Migrations — the ledger you must build yourself

```
Mongoose schemas are APPLICATION-LEVEL. They:
   ✅ validate documents on the way in (through the app)
   ✅ cast types
   ⛔ DO NOT alter stored data
   ⛔ DO NOT record what has been applied
   ⛔ DO NOT stop an old document from existing
   ⛔ DO NOT run in order, atomically, or exactly once

⭐ There is no flyway_schema_history. There is no ledger. If you do not
   build one, you have NO IDEA what shape your production data is in.
```

```javascript
// migrate-mongo-config.js
module.exports = {
  mongodb: {
    url: process.env.MONGODB_URL,            // ⭐ from the env, never hardcoded
    options: {
      replicaSet: process.env.MONGO_REPLICA_SET || 'rs0',   // ⭐ or transactions fail
      retryWrites: true,
      serverSelectionTimeoutMS: 10000,
    },
  },
  migrationsDir: 'migrations',
  changelogCollectionName: 'schema_migrations',   // ⭐⭐ THE LEDGER
  useFileHash: true,          // ⭐ detect an EDITED migration that already ran
  migrationFileExtension: '.js',
  moduleSystem: 'commonjs',
};
```

```javascript
// migrations/20260910093000-backfill-total-cents.js
/**
 * ⭐ WHAT:  backfill totalCents from the legacy `total` (a float)
 * ⭐ WHY:   expand/contract release 2 — the app now reads totalCents, but
 *          1.2M existing documents only have `total`
 * ⭐ SAFE:  idempotent · batched · has a real `down`
 */
module.exports = {
  async up(db) {
    const BATCH = 5000;
    let touched = 0;
    while (true) {
      // ⭐⭐ a bounded batch, not one giant updateMany. An unbounded update
      //   over 1.2M documents holds locks, grows the oplog, and lags replicas.
      const ids = await db.collection('orders')
        .find({ total: { $exists: true }, totalCents: { $exists: false } })
        .limit(BATCH).project({ _id: 1 }).toArray();
      if (ids.length === 0) break;

      await db.collection('orders').updateMany(
        { _id: { $in: ids.map(d => d._id) } },
        [{ $set: { totalCents: { $round: [{ $multiply: ['$total', 100] }] } } }]
      );
      touched += ids.length;
      if (touched > 5_000_000) throw new Error('⛔ runaway migration — aborting');
      await new Promise(r => setTimeout(r, 50));   // ⭐ let the replicas breathe
    }
    console.log(`✅ backfilled ${touched} orders`);
  },

  async down(db) {
    // ⭐⭐ NOT "drop the column" — MongoDB has none. The reverse of a backfill
    //   is to REMOVE the new field, and that is LOSSY if the app has since
    //   written values the legacy field never had.
    const r = await db.collection('orders')
      .updateMany({ totalCents: { $exists: true } }, { $unset: { totalCents: '' } });
    console.log(`↩️ removed totalCents from ${r.modifiedCount} orders`);
  },
};
```

```javascript
// migrations/20260915140000-create-index-orders-status-created.js
module.exports = {
  async up(db) {
    await db.collection('orders').createIndex(
      { status: 1, createdAt: -1 }, { name: 'idx_status_created' });
    // ⭐⭐ and PROVE the index is actually used
    const plan = await db.collection('orders')
      .find({ status: 'PAID' }).sort({ createdAt: -1 }).limit(1).explain('queryPlanner');
    if (!JSON.stringify(plan).includes('idx_status_created'))
      throw new Error('⛔ the new index is not used — check the query shape');
  },
  async down(db) { await db.collection('orders').dropIndex('idx_status_created'); },
};
```

```bash
# ⭐ run migrations from the SAME image that serves — never from a laptop
docker compose -f docker-compose.yml run --rm \
  -e MONGODB_URL="mongodb://shop:shop-pass@mern-mongo:27017/shop?replicaSet=rs0&authSource=admin" \
  mern-api npx migrate-mongo status
docker compose -f docker-compose.yml run --rm \
  -e MONGODB_URL="mongodb://shop:shop-pass@mern-mongo:27017/shop?replicaSet=rs0&authSource=admin" \
  mern-api npx migrate-mongo up

# ⭐⭐ PROVE THE LEDGER EXISTS
docker exec mern-mongo mongosh --quiet -u shop -p shop-pass --authenticationDatabase admin shop \
  --eval 'db.schema_migrations.find({},{_id:0,fileName:1,appliedAt:1}).toArray()'
# ✅ that collection IS the ledger. If it does not exist you have no record
#   of what shape your data is in.

# ⭐⭐ PROVE IDEMPOTENCY — the property that makes a retry safe
docker exec mern-mongo mongosh --quiet -u shop -p shop-pass --authenticationDatabase admin shop \
  --eval 'db.schema_migrations.deleteMany({})'
docker compose -f docker-compose.yml run --rm -e MONGODB_URL="…" mern-api npx migrate-mongo up
docker compose -f docker-compose.yml run --rm -e MONGODB_URL="…" mern-api npx migrate-mongo up
# ✅ the second run applies nothing and exits 0
```

---

## 14.10 ⭐ Backups — the only rollback MongoDB has

```bash
# ⛔ A BACKUP YOU HAVE NEVER RESTORED IS A HYPOTHESIS.

STAMP=$(date -u +%Y%m%dT%H%M%SZ)

# ── 1 · TAKE IT ────────────────────────────────────────────────────────
docker exec mern-mongo mongodump \
  --uri="mongodb://shop:shop-pass@localhost:27017/shop?replicaSet=rs0&authSource=admin" \
  --gzip --archive --oplog > "backup-$STAMP.archive.gz"
# ⭐ --oplog gives a POINT-IN-TIME-CONSISTENT dump of a LIVE database.
#   ⛔ without it, a write landing mid-dump produces a TORN backup that
#     restores to a state that never existed.

# ── 2 · ⭐⭐ PROVE IT RESTORES — into a THROWAWAY container ─────────────
docker run -d --name verify-mongo -p 27099:27017 mongo:8.0 --replSet rs0 --bind_ip_all
sleep 8
docker exec verify-mongo mongosh --quiet --eval 'rs.initiate()' >/dev/null
sleep 5
gunzip -c "backup-$STAMP.archive.gz" | docker exec -i verify-mongo \
  mongorestore --archive --gzip --nsInclude='shop_verify.*' --numInsertionWorkers 4

# ── 3 · ⭐ COMPARE COUNTS — the check an empty file cannot pass ─────────
for c in orders users products; do
  SRC=$(docker exec mern-mongo mongosh --quiet -u shop -p shop-pass \
        --authenticationDatabase admin shop --eval "db.$c.countDocuments()")
  DST=$(docker exec verify-mongo mongosh --quiet shop_verify --eval "db.$c.countDocuments()")
  [ "$SRC" = "$DST" ] && echo "✅ $c: $SRC documents verified" \
                      || { echo "⛔ $c: source=$SRC restored=$DST"; exit 1; }
done

docker rm -f verify-mongo
echo "$STAMP size=$(du -h backup-$STAMP.archive.gz | cut -f1) verified=true" >> backup-audit.log
```

| Step | ⭐ Why it is not optional |
|---|---|
| `--oplog` | a consistent snapshot of a **live** database; without it the backup is torn |
| ⭐⭐ restore it | `mongodump` exits 0 on a dump nobody can read |
| ⭐ compare counts | catches the empty-file, wrong-namespace and partial-restore cases |
| record it | "was there a verified backup before this change?" must be answerable in an incident |

```
⭐⭐ AND THE CONSEQUENCE FOR ROLLBACKS:
   `docker compose down && up -d` with the PREVIOUS image tag rolls back
   your CODE. It does NOT roll back your DATA.

   If a migration wrote bad values, the rollback restores the old code and
   LEAVES THE CORRUPTION IN PLACE — and now the old code is reading fields
   the migration changed. That is worse than not rolling back.

   ⛔ The only data rollback is `mongorestore` from the verified backup,
     and that is a DECISION A HUMAN MUST MAKE. Which is exactly why the
     MERN stack is 🔒 Continuous Delivery, not 🤖 Continuous Deployment,
     until every migration is provably expand/contract.
```

---

## 14.11 The production overlay and the Makefile

```yaml
# docker-compose.prod.yml — 🟢 layered over the base
services:
  mern-mongo:
    image: mongo:8.0
    command:
      - --replSet=rs0
      - --bind_ip_all
      # ⭐⭐ SET THE CACHE SIZE EXPLICITLY. WiredTiger defaults to
      #   50% of (RAM − 1 GB) as mongod sees it. In a container with a
      #   limit, mongod may size from the HOST's RAM → it exceeds the
      #   limit → OOMKilled, with no mongod error, just exit 137.
      - --wiredTigerCacheSizeGB=1.5
    volumes:
      - ./mongo/mongod.conf:/etc/mongo/mongod.conf:ro
    deploy:
      resources:
        limits:   { memory: 3G, cpus: "2" }
        reservations: { memory: 2G }
    restart: unless-stopped

  mern-api:
    image: shopacr.azurecr.io/mern-api@sha256:REPLACE_ME   # ⭐⭐ A DIGEST
    init: true
    environment:
      NODE_ENV: production
      REQUIRE_REPLICA_SET: "true"
      MONGO_POOL_SIZE: "20"
    deploy:
      replicas: 2
      resources: { limits: { memory: 512M, cpus: "1" } }
    # ⭐ read-only root filesystem: the api writes NOTHING except /tmp
    read_only: true
    tmpfs: [/tmp]
    security_opt: ["no-new-privileges:true"]
    restart: unless-stopped

  mern-web:
    image: shopacr.azurecr.io/mern-web@sha256:REPLACE_ME   # ⭐⭐ A DIGEST
    environment: { MERN_ENV: production }
    deploy: { replicas: 2, resources: { limits: { memory: 128M, cpus: "0.5" } } }
    read_only: true
    # ⭐ nginx needs to write the client-body temp dir and /config.js
    tmpfs: [/var/cache/nginx, /var/run, /usr/share/nginx/html/config.js]
    security_opt: ["no-new-privileges:true"]
    restart: unless-stopped
```

```makefile
# Makefile
SHELL := /bin/bash
DIGEST_WEB ?= $(shell docker inspect -f '{{index .RepoDigests 0}}' shop-mern-web:prod 2>/dev/null | cut -d@ -f2)

.PHONY: up down build test migrate backup verify logs clean

up:        ## 🔵 dev stack
	docker compose up -d --wait && docker compose ps

down:      ## stop, KEEP the mongo volume
	docker compose down

nuke:      ## ⛔ DESTROY the mongo volume — know what you are doing
	docker compose down -v --remove-orphans

build:     ## 🟢 production images
	docker compose -f docker-compose.yml -f docker-compose.prod.yml build

test:      ## ⭐⭐ E2E against the BUILT IMAGES
	docker compose -f docker-compose.ci.yml up -d --wait
	npx playwright test --project=chromium || (docker compose -f docker-compose.ci.yml logs --tail=200; exit 1)
	docker compose -f docker-compose.ci.yml down -v

typecheck: ## ⭐ the contract test — one shared package, both apps
	npm run build -w @shop-mern/shared && npm run typecheck

migrate:   ## ⭐⭐ from the IMAGE, never from a laptop
	docker compose run --rm mern-api npx migrate-mongo status
	docker compose run --rm mern-api npx migrate-mongo up

backup:    ## take + RESTORE-VERIFY + count-compare (§14.10)
	./scripts/backup-and-verify.sh

logs:      ## all three, interleaved, with timestamps
	docker compose logs -f --tail=100 -t

clean:
	docker system prune -af --volumes --filter 'label!=keep'
```

---

## 🔨 Tasks for Project 14

> **14.1** Build both cases for `mern-api` and record the exact sizes. Then list every package present in Case 1's `node_modules` but absent from Case 2's, and explain why each one being in a production image is a problem rather than just wasted bytes.

> **14.2** Prove the `node_modules` pitfall. Delete `**/node_modules` from `.dockerignore`, rebuild on an Apple-silicon Mac, and run the image on `--platform linux/amd64`. What exact error do you get, and why does it name a file that exists?

> **14.3** Make `mern-web` environment-agnostic. Prove one image, one digest, serves two different API URLs — and prove nothing was baked in at build time.

> **14.4** Get MongoDB running as a replica set in Compose, and prove Mongoose transactions work. Then break it in three different ways and record the three different error messages.

> **14.5** Implement graceful shutdown. Prove `docker stop` drains in under a second rather than taking the full 10-second grace period, and identify the setting that silently undoes your work.

> **14.6** Build the migration ledger, prove idempotency, and prove the ledger collection exists.

> **14.7** Set `autoIndex: false`, move index creation into a migration, and prove the index is used. Then explain what happens in production if you skip this.

> **14.8** Implement the backup, restore-verify it, and compare document counts. Then explain why an image rollback is not a data rollback.

> **14.9** Run Playwright against the built images rather than `npm run dev`, and find the bug that only the built image has.

> **14.10** ⭐⭐ During a rolling update of `mern-api` from v1 to v2, some orders are created with `quantity` and some with `qty`, and the web UI shows `undefined` for about forty seconds. Name every mechanism involved, the immediate fix, and the permanent one.

<details>
<summary>👉 Answers</summary>

**14.1** Run `docker images --format 'table {{.Repository}}\t{{.Size}}'` for both; expect roughly **1.1 GB → ~180 MB**. Get the real list with `docker run --rm --entrypoint sh <image> -c 'ls node_modules' | sort > case1.txt` for each and `comm -23 case1.txt case2.txt`. It will contain `vitest`, `@vitest/*`, `playwright`, `@playwright/test`, `typescript`, `eslint`, `prettier`, `@types/*`, `tsx` and their transitive trees. ⭐ **Why each is a problem, not just bytes:** every one of them is (a) **executable code that runs at install time** — `npm ci` runs postinstall scripts, so a compromised dev dependency becomes remote code execution in your *build*, and dev dependencies are far less scrutinised than runtime ones; (b) **CVE surface** — `npm audit` and Trivy both report against everything in the image, so dev-only packages generate production findings you must triage or ignore, and ignoring trains you to ignore the real ones; (c) **attack surface at runtime** — a TypeScript compiler, a test runner and a browser automation library in a container that has been compromised are a *toolkit*: `playwright` ships a full Chromium, `tsx` lets an attacker execute arbitrary TypeScript, and `vitest` will happily run anything. ⭐ **The mechanism that removes them is `--omit=dev` in the `deps` stage** combined with a *separate* `build` stage that installs everything and is then discarded. The reason you need two installs is that `tsc` is itself a devDependency — so a single-stage "install prod only, then build" cannot work, and a single-stage "install everything, then build" ships the tooling.

**14.2** With `**/node_modules` removed, `COPY . .` ships your host's tree into the image. If you built on macOS arm64 and run `--platform linux/amd64`, any package with a **native binding** fails. The error looks like: `Error: Cannot find module '/app/node_modules/@esbuild/linux-x64/bin/esbuild'` or `Error: Cannot find module '@rollup/rollup-linux-x64-gnu'` — ⛔ **about a file that "exists"**, because what exists is the `darwin-arm64` binary, and Node's resolver is looking for the `linux-x64` one that npm never installed on your Mac. Confirm with `docker run --rm --entrypoint sh <image> -c 'ls node_modules/@esbuild'` (you will see `darwin-arm64`, not `linux-x64`) and `file node_modules/.bin/esbuild` (`Mach-O 64-bit executable arm64` instead of `ELF 64-bit … x86-64`). ⭐ **There are three separate failures bundled into this one line of `.dockerignore`:** the platform mismatch above; **cache invalidation** — `node_modules` changes whenever you install anything, so the `COPY . .` layer and everything after it rebuilds every time, turning a 20-second build into a 90-second one; and **silent overwriting** — if `COPY . .` comes *after* `RUN npm ci`, your host tree replaces the correctly-installed one, so the image contains dependencies resolved on a different platform with a possibly different lockfile state. ⭐ The fix is one line, and the diagnostic (`file` on a binary inside the image) is the transferable skill.

**14.3** Build once: `docker build -f apps/web/Dockerfile -t mern-web:test .`. Run it twice with different environments — `docker run -d --name a -e MERN_API_URL=http://api-a:4000 -e MERN_ENV=staging -p 9001:80 mern-web:test` and the same with `api-b`/`production` on `9002`. `curl -s localhost:9001/config.js` and `:9002/config.js` must show the two different URLs, and `docker inspect -f '{{.Image}}' a b` must be **identical**. ⭐ **Proving nothing was baked in:** `docker run --rm --entrypoint sh mern-web:test -c 'grep -rl "api-a\|api-b\|localhost:4000" /usr/share/nginx/html/assets/ | wc -l'` → **0**. If that is non-zero you have a `VITE_*` variable being inlined by Vite somewhere, and the one-image property is false even though `config.js` looks right. **The mechanism:** nginx's `docker-entrypoint.d/` directory runs every executable before nginx starts, so `40-inject-config.sh` writes `/usr/share/nginx/html/config.js` from the *real* environment on every container start; `index.html` loads it with a `<script src="/config.js">` **before** the bundle, and `config.ts` is the only reader. ⭐ **Two details that make it robust:** the `esc()` function — an unescaped quote or backslash in an env var produces a `config.js` that is a *syntax error*, and the SPA renders a **blank page with no visible error**; and `cfg()` **throwing** when `__APP_CONFIG__` is missing, because silently defaulting to `localhost:4000` turns a broken deploy into a confusing one.

**14.4** Compose: `mongo:8.0` with `command: ["--replSet","rs0","--bind_ip_all"]`, a named volume on `/data/db`, and a one-shot `mongo-init` service running `rs.initiate()` that treats `AlreadyInitialized` as **success**. The api's `depends_on` must use `mongo-init: { condition: service_completed_successfully }`. **Proving transactions work:** `docker compose exec mern-api node -e '...'` with `const s = await mongoose.startSession(); await s.withTransaction(async () => { … })` → succeeds. ⭐ **The three ways to break it, and the three *different* errors:** **(1)** drop `--replSet rs0` → `MongoServerError: Transaction numbers are only allowed on a replica set member or mongos`. **(2)** keep `--replSet rs0` but skip `rs.initiate()` → the connection succeeds and reads work, but transactions hang or throw `MongoServerSelectionError: getaddrinfo ENOTFOUND … -0` / no primary; ⭐ this is the nastiest because everything *looks* healthy. **(3)** drop `replicaSet=rs0` from the connection string while the server *is* a replica set → the driver connects in standalone-ish mode, topology discovery is off, and you get `MongoServerSelectionError` on failover or silent `w:1` writes. ⭐ **And the fourth failure that produces no error at all:** code written as `if (session) { …transaction… } else { …plain write… }` silently takes the else branch, so your "atomic" order creation is not atomic and every test passes. That is why `REQUIRE_REPLICA_SET=true` plus the `hello.setName` check in `db.ts` matters — it converts a silent wrongness into a boot failure. Also note `--bind_ip_all` is required or mongod binds `127.0.0.1` only and the api container gets `ECONNREFUSED`.

**14.5** Add `init: true` to the compose service **and** the SIGTERM handler in `server.ts` (`server.close()` → `await disconnect()` → `process.exit(0)`), with a ~9 s force-exit timer. **Proving it:** `time docker stop mern-api` → ⭐ **under ~2 s** instead of exactly `10.0s` followed by exit code 137. Better proof that it *drained* rather than merely exited fast: open a slow request (`curl 'localhost:8080/api/slow'` where the handler sleeps 3 s), then `docker stop` in another terminal, and confirm the slow request **completes with 200** while a request started *after* the stop is refused. **The setting that silently undoes all of it:** ⛔ `CMD npm start` (or any shell-form CMD). Then PID 1 is `sh`, which does **not** forward SIGTERM to its child; your handler never fires, Docker waits the full grace period and SIGKILLs. The symptom is indistinguishable from "my handler is broken", which is why you check `docker exec mern-api ps -o pid,comm` and confirm **PID 1 is `node`** (or `tini`/`dumb-init`). ⭐ Two related details: `server.close()` stops accepting new connections and finishes in-flight ones — `server.closeAllConnections()` would abort them, which is the opposite of draining; and Node as PID 1 receives signals correctly but does **not** reap orphaned grandchildren, so if your app spawns child processes you want `init: true` regardless.

**14.6** `migrate-mongo-config.js` with `mongodb.url` from `MONGODB_URL`, `replicaSet` from the environment, `changelogCollectionName: 'schema_migrations'`, ⭐ `useFileHash: true`. Run migrations **from the image**, never from a laptop: `docker compose run --rm -e MONGODB_URL=… mern-api npx migrate-mongo up`. **Proving the ledger:** `docker exec mern-mongo mongosh --quiet … --eval 'db.schema_migrations.find({},{_id:0,fileName:1,appliedAt:1}).toArray()'` — ⭐ that collection is the *only* record you have of what shape production data is in. **Proving idempotency:** clear the ledger, run `up` twice, and confirm the second run applies nothing and exits 0. **Why `useFileHash: true` matters:** without it, editing an already-applied migration file does nothing and nobody notices — so the file in git and the change that ran diverge silently, and the next environment to be migrated gets a *different* migration under the same name. With it, an edited applied migration is a hard failure. ⭐ **And the reason MERN needs a ledger at all** (which SQL stacks get for free): Mongoose schemas are application-level — they validate on the way in *through the app*, do not alter stored data, do not record what ran, and do not prevent an old document existing. There is no `flyway_schema_history` unless you build one.

**14.7** Set `autoIndex: false` **and** `autoCreate: false` in `db.ts` — in code, not via an env var, so it cannot be switched on by accident — and never call `Model.syncIndexes()`. Create indexes in a migration: `createIndex({status:1, createdAt:-1}, {name:'idx_status_created'})`, and ⭐ **prove it is used in the same migration** with `.find({status:'PAID'}).sort({createdAt:-1}).limit(1).explain('queryPlanner')`, throwing if the plan does not mention the index name. Verify in CI: `grep -rn 'autoIndex' apps/api/src/` shows only `false`, and `grep -rn 'syncIndexes' apps/ migrations/` returns nothing. ⭐ **What happens in production if you skip it, in four escalating steps:** `createIndex` on a large collection is expensive and, during a rolling update, runs **on every new instance simultaneously**; renaming an index in the schema creates the new one but never drops the old, so indexes accumulate and every write gets slower; ⛔⛔ `syncIndexes()` **drops** indexes absent from the schema, so with three instances rolling an old instance re-creates what a new one just dropped and **query plans change mid-rollout**; and a *missing* index turns a query into a **collection scan**, so the database falls over under normal load minutes after a deploy that reported success. **One extra:** time the index build against staging-sized data first — an index that takes four minutes on production's volume will blow past your migration timeout, and discovering that during the production deploy is the expensive way to learn it.

**14.8** §14.10. `mongodump --uri=… --gzip --archive --oplog > backup-$STAMP.archive.gz`, then restore into a **throwaway** container with `mongorestore --archive --gzip --nsInclude='shop_verify.*'`, then compare `countDocuments()` per collection between source and restored, then append a record to an audit log. ⭐ **Why each piece is load-bearing:** `--oplog` makes the dump a consistent **point-in-time** snapshot of a *live* database — without it a write landing mid-dump produces a torn backup that restores to a state that never existed; **restoring** is the only proof, because `mongodump` exits 0 on an archive nobody can read; **comparing counts** catches the empty-file, wrong-namespace and partial-restore cases that a successful `mongorestore` exit code does not. ⭐⭐ **Why an image rollback is not a data rollback:** `docker compose down && up -d` with the previous digest restores your **code** and leaves the **data** exactly as the migration wrote it. If the migration backfilled or reshaped fields, the old code is now reading data the new code changed — which is frequently *worse* than not rolling back, because you have two problems and a misleading "rollback succeeded" signal. The only data rollback is `mongorestore` from the verified backup, and that discards every write since the backup — so it is a **decision a human must make**, not a pipeline step. That is the deepest reason MERN is 🔒 Continuous Delivery rather than 🤖 Continuous Deployment until every migration is provably expand/contract, idempotent and batched.

**14.9** `docker compose -f docker-compose.ci.yml up -d --wait` with `mern-web`/`mern-api` referenced **by digest**, then `npx playwright test`. ⭐ **The bug that only the built image has** is almost always one of three: **(1)** `/config.js` is missing or a syntax error — `cfg()` throws, React never mounts, and the page is **blank** with only a console error, because `npm run dev` has no `config.js` at all and reads `import.meta.env` instead; **(2)** the **SPA fallback** is missing, so a deep link like `/orders/123` returns nginx's 404 instead of `index.html` — the dev server rewrites everything to `index.html` automatically, so this never appears locally; **(3)** a **CSP or `server_tokens`/MIME** difference — `nosniff` plus a wrong content type on a hashed asset, or a CSP that blocks the inline config script. **Why the dev-server run is worthless as a ship gate:** `npm run dev` serves unbundled ESM with Vite's env handling, a permissive host/CORS config, no `config.js`, no CSP and no cache headers. The production image serves a bundled SPA from nginx with all of them. ⛔ **They are different programs**, so a green dev-server E2E run tells you nothing about the artifact you are shipping — which is exactly the gap this task closes.

**14.10** ⭐⭐ **Every mechanism, in order.** A rolling update runs **two versions of `mern-api` at once** — old containers draining, new ones starting, both connected to the same MongoDB, both writing to `orders`. The old code writes `{ qty }`; the new code writes `{ quantity }`. ⭐⭐ **MongoDB accepts both, because the schema lives in Mongoose — in your application — not in the database.** There is no column, no constraint, no rejection: a document is whatever the writer said it was. Meanwhile the browser holds **yesterday's bundle** (or, for ~40 s, the new bundle served by containers that are still old), which reads `order.quantity`; on documents written by the old container that property is absent, so it renders `undefined`. The forty-second duration is the rollout window; the *hours*-long tail would be the browser cache, which is why `index.html` must be `no-cache`.

**Immediate fix (minutes):** make the *reader* tolerant in one place — `const quantity = order.quantity ?? order.qty ?? 0` inside `packages/shared`, so both tiers get it from a single edit — and redeploy; then **backfill** the documents written during the window with a batched, idempotent migration (§14.9's pattern), and verify the count of `qty`-only documents reaches zero. ⛔ **Do not just roll back the image:** that stops new `quantity` documents but leaves the mixed data in place, and a rollback is not a data rollback (§14.8).

**Permanent fix — expand/contract, three releases:** **(1)** the API accepts **both** `qty` and `quantity` on input and emits **both** on output, declared once in the shared zod schema (`quantity` required, `qty` optional-deprecated) — safe, and revertible because nothing consumes the new field yet; **(2)** the web app switches to reading and sending `quantity`, while the API still emits `qty`, so a cached old bundle keeps working; **(3)** later — and only after telemetry shows zero `qty` traffic — the API stops emitting it and a migration `$unset`s the legacy field.

⭐ **Plus the three gates that would have caught it:** `CONTRACT_VERSION` with a startup `serves` check, so a mismatched pair shows a **refresh banner** instead of `undefined`; the API response validated with `OrderOutput.parse(await r.json())`, so an unexpected shape becomes a **caught, logged** error rather than a silent `undefined`; and ⭐ the integration test that writes a document in the **old** shape and asserts the **new** code reads it correctly — the MERN-specific test that exists precisely because the database will not do this for you.

**The meta-lesson:** in a Postgres stack this incident is a `NOT NULL` violation that **fails the deploy**. In MERN it is silent mixed data plus `undefined` in the UI. ⭐ *The same design decision that makes MERN fast to build makes it unforgiving to deploy* — and the compensation is discipline in the shared package, the migration ledger and the contract version, not a constraint you can add later.

</details>

---

## 14.12 Checklist

- [ ] Scaffold an npm-workspaces monorepo with ONE lockfile and a `packages/shared` contract
- [ ] Write `.dockerignore` with `**/node_modules` and explain the three failures it prevents
- [ ] Copy EVERY workspace's `package.json` before `npm ci`
- [ ] Build `packages/shared` before either app
- [ ] `--omit=dev` in the runtime image; a separate build stage that is discarded
- [ ] `USER app` — non-root
- [ ] `NODE_OPTIONS=--max-old-space-size` in BOTH the Vite build and the runtime
- [ ] exec-form `CMD` so node is PID 1, plus `init: true`
- [ ] SIGTERM → stop readiness → `server.close()` → `mongoose.disconnect()` → exit 0
- [ ] `express.json({ limit })` — cap the body
- [ ] `/healthz` (never touches mongo) vs `/readyz` (does, with a real ping)
- [ ] MongoDB with `--replSet rs0 --bind_ip_all` and an idempotent `rs.initiate()`
- [ ] `depends_on: condition: service_healthy` / `service_completed_successfully`
- [ ] `replicaSet=rs0&retryWrites=true&w=majority` in the connection string
- [ ] Prove a Mongoose transaction actually runs
- [ ] `autoIndex: false`, `autoCreate: false`, never `syncIndexes()`
- [ ] Indexes created in a migration, with an `explain()` assertion that they are used
- [ ] A `schema_migrations` ledger with `useFileHash: true`
- [ ] Migrations idempotent and batched, run from the image
- [ ] Runtime `config.js` injection; prove ONE image serves two environments
- [ ] `index.html` `no-cache` · `/assets/` `immutable` · `config.js` `no-store`
- [ ] nginx proxies `/api/` → one origin, no CORS anywhere
- [ ] `mongodump --oplog`, restore-verify, compare counts
- [ ] Playwright against the BUILT images, not the dev server
- [ ] Explain why an image rollback is not a data rollback

---

## ➡️ Next

**[`18-DOCKER-CLI-COMPLETE-REFERENCE.md`](18-DOCKER-CLI-COMPLETE-REFERENCE.md)** — every Docker CLI command, on one page.

⭐ **And then, in Kubernetes:** [`../../kubernetes-learning-path/18-PROJECT-15-mern-stack.md`](../kubernetes-learning-path/18-PROJECT-15-mern-stack.md) — the same MERN stack as a Deployment pair plus a **replica-set StatefulSet**, with the migration as a gated Job and the backup as a CronJob.

⭐ **And then, in CI/CD:** [`../cicd-learning-path/08-SCENARIO-DEPLOYMENTS/01-MERN-STACK-PROJECT.md`](../cicd-learning-path/08-SCENARIO-DEPLOYMENTS/01-MERN-STACK-PROJECT.md) — the same stack through all three scenarios in all three tools, where it becomes **shape E**.

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish%20Kumar%20Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn → <https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260>
🐙 GitHub → <https://github.com/3558Bhk>

*Built for engineers who learn by breaking things on purpose.*

</div>
