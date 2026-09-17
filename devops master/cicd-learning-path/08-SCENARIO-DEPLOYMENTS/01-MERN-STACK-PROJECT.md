# 🟣 THE MERN STACK PROJECT — `shop-mern`
### The sixth application shape, and the one that is genuinely new: **one language across all three tiers, with a stateful database inside the application tier.** Tool-agnostic — every pipeline in every scenario and every tool folder deploys *this* spec.

> **Why MERN is not just "shape D again":** shapes A–D all treat the database as *someone else's problem* (P13, deployed separately, 🔒 forever). MERN puts **MongoDB inside the release**. That changes the migration story, the rollback story, the CI infrastructure story and the Case 1 / Case 2 verdict — and it is the shape most junior candidates have actually built and most senior candidates have been burned by.
>
> **Used by:** every file in [`scenario-1-ci-only/`](./scenario-1-ci-only/), [`scenario-2-cd-only/`](./scenario-2-cd-only/), [`scenario-3-ci-plus-cd/`](./scenario-3-ci-plus-cd/) and all three tool folders in [`../09-TOOL-MASTERY/`](../09-TOOL-MASTERY/).
>
> ⭐ **Where the application itself is built:** [`docker-learning-path/17-PROJECT-14-mern-stack.md`](../../docker-learning-path/17-PROJECT-14-mern-stack.md) (**Docker P14** — the images, Compose, the replica set, migrations, backups) and [`kubernetes-learning-path/18-PROJECT-15-mern-stack.md`](../../kubernetes-learning-path/18-PROJECT-15-mern-stack.md) (**K8s P15** — the StatefulSet, the gated migration Job, the backup CronJob, the probes). **This file is the CI/CD layer on top of those two**: it assumes both are done and adds the pipelines.

---

## 📇 Contents

| § | What |
|---|---|
| [1](#1--what-shop-mern-is) | What `shop-mern` is — the three tiers and the continuity contract |
| [2](#2---why-mern-is-a-new-shape-not-a-repeat-of-shape-d) | ⭐⭐ Why MERN is a new shape, not a repeat of shape D |
| [3](#3--the-repo-layout) | The repo layout — npm workspaces, one lockfile, a shared contract package |
| [4](#4--version-anchors) | Version anchors — pinned, verified |
| [5](#5--the-dockerfiles) | The Dockerfiles — web, api, and why the api one is the interesting one |
| [6](#6---the-shared-package-is-the-contract-test) | ⭐⭐ The shared package IS the contract test |
| [7](#7---ci--the-four-mern-specific-gates) | ⭐⭐ CI — the four MERN-specific gates |
| [8](#8---the-migration-problem--mongoose-does-not-solve-it-for-you) | ⭐⭐ The migration problem — Mongoose does not solve it for you |
| [9](#9--kubernetes--the-three-workloads) | Kubernetes — the three workloads, and the replica-set requirement |
| [10](#10---cd--ordering-rollback-and-the-backup-gate) | ⭐ CD — ordering, rollback, and the backup gate |
| [11](#11---case-1-or--case-2--per-tier) | 🔒 Case 1 or 🤖 Case 2 — per tier, with reasons |
| [12](#12--how-each-scenario-and-each-tool-uses-this-project) | How each scenario and each tool uses this project |
| [13](#13--️-run-it-locally--the-acceptance-checks) | ▶️ Run it locally — the acceptance checks |
| [14](#14--troubleshooting) | Troubleshooting |
| [15](#15---tasks--answers-at-the-end) | Tasks and answers — **answers at the END** |

---

## 1 · What `shop-mern` is

```
shop-mern/                       ⭐ ONE repository, ONE language, THREE tiers
│
├── apps/web      React 19 + Vite + TypeScript     → nginx:1.29-alpine   :80
│                 the browser-facing SPA. Same runtime-config discipline
│                 as shop-ui (§04 of scenario 3): ⛔ never bake the API URL.
│
├── apps/api      Node 24 + Express 5 + Mongoose 8 → node:24-alpine      :4000
│                 REST + a health pair. Owns the schema. Owns the migrations.
│
└── (data)        MongoDB 8.0                      → mongo:8.0           :27017
                  ⭐ INSIDE the release, not beside it. A StatefulSet with a
                  PVC, deployed and versioned with the app.
```

| | `mern-web` | `mern-api` | `mern-mongo` |
|---|---|---|---|
| **Language** | TypeScript | TypeScript | — |
| **Runtime** | nginx (static) | Node 24 | mongod 8.0 |
| **Port** | 80 | 4000 | 27017 |
| **Image** | `ghcr.io/3558bhk/mern-web` | `ghcr.io/3558bhk/mern-api` | `mongo:8.0` (⭐ official, pinned by digest) |
| **K8s workload** | Deployment | Deployment | ⭐ **StatefulSet** |
| **Storage** | none | none | ⭐ **PVC** (and a backup) |
| **Build time (cold/warm)** | 3 min / 90 s | ⭐ **60 s / 20 s** | n/a |
| **Start-up** | instant | ⭐ **~1 s** | ~3 s |
| **Health** | `/` + `/config.js` | `/healthz` + ⭐ `/readyz` | `mongosh --eval 'db.adminCommand({ping:1})'` |
| **Non-root** | needs config | ✅ `node` user (uid 1000) | ⛔ **mongod needs to write /data/db** |
| **Rollback** | ⭐ instant (static files) | ⭐ instant (image) | ⛔ **only a backup** |
| **Migrations** | none | ⭐⭐ **`migrate-mongo`, and you build the ledger** | the data itself |
| **Case** | 🤖 **Case 2** | 🔒 **Case 1** | 🔒🔒 **Case 1, forever** |

### 1.1 The continuity contract (same as every other project in this folder)

```
✅ namespaces        shop-dev · shop-staging · shop-production  (+ shop-canary)
   workloads are prefixed mern-* so they sit beside shop-* without collision
✅ registries        ghcr.io/3558bhk/mern-{web,api}   ·   shopacr.azurecr.io/mern-{web,api}
✅ artifact          ⭐ a DIGEST, never a tag — same as every other service
✅ cluster           kind, cluster name `cicd`
✅ environments      dev → staging → production
✅ CI cannot deploy; CD cannot build. The asymmetry is unchanged.
```

---

## 2 · ⭐⭐ Why MERN is a new shape, not a repeat of shape D

| | **Shape D** (polyglot: React + Go + Python + Java) | ⭐ **Shape E** (MERN) |
|---|---|---|
| Languages | 3–4 | ⭐ **1** |
| Toolchains in CI | 4 caches, 4 agents, 4 linters | ⭐ **one** `npm ci`, one cache, one agent |
| CI wall-clock | dominated by the slowest (Java, 6 min) | ⭐ dominated by the **React build** (3 min cold) |
| Cross-language contract | ⛔ protobuf / OpenAPI codegen, drift gates | ⭐⭐ **a shared TypeScript package — the contract is compile-time** |
| The database | ⛔ **outside** the release (P13, deployed separately) | ⭐⭐ **inside** the release |
| Migrations | Flyway / Alembic, with a ledger the tool maintains | ⭐⭐ **Mongoose has none. You build the ledger.** |
| Schema enforcement | the database enforces it | ⛔ **the application enforces it** — the database accepts anything |
| Rollback | image rollback (+ the schema caveat) | ⭐ image rollback **+ a data rollback, which is a restore** |
| Transactions | SQL, always available | ⛔ **require a replica set** — a single mongod silently cannot |
| CI infrastructure | Postgres / RabbitMQ containers | ⭐ **a real mongod**, and the in-memory fake is a trap |

⭐⭐ **The single sentence that defines shape E:** *the toolchain got easier and the data got harder, at the same time.* Everything about building and testing is simpler than shape D — one language, one lockfile, a compile-time contract. Everything about **deploying safely** is harder, because the thing you cannot roll back is now inside your release train instead of beside it.

**And the failure mode that is unique to MERN:**

```
⛔ MONGODB IS SCHEMALESS. THAT IS A DEPLOYMENT HAZARD, NOT A FEATURE.

   Postgres rejects a row that violates the schema. The bad deploy FAILS,
   loudly, immediately, and the data stays clean.

   MongoDB ACCEPTS it. Mongoose validates on the way IN — but only through
   the app. Anything that writes around the app (a script, a migration, an
   old replica, a manual mongosh session, a previous version of your own
   code during a rolling update) writes whatever it likes.

   ⭐⭐ SO: during a rolling update, TWO VERSIONS OF YOUR APP WRITE TO THE
      SAME COLLECTION SIMULTANEOUSLY, and there is no database-level
      constraint stopping either one. Your "schema" is a convention that
      is enforced by whichever process happens to be running.

   That is why MERN needs expand/contract (§06 of scenario 3) MORE than a
   SQL stack does, and why it has no database to catch you when you forget.
```

---

## 3 · The repo layout

```
shop-mern/
├── package.json                 ⭐ workspaces root — ONE lockfile for all tiers
├── package-lock.json            ⭐⭐ the single source of dependency truth
├── .nvmrc                       24                    ⭐ pinned
├── tsconfig.base.json           strict: true, paths → @shop-mern/shared
├── vitest.workspace.ts          ⭐ one test run, both apps
│
├── packages/
│   └── shared/                  ⭐⭐ THE CONTRACT
│       ├── package.json         name: @shop-mern/shared
│       ├── src/
│       │   ├── api-types.ts     request/response DTOs, exported as types
│       │   ├── routes.ts        ⭐ the route table — one place, both sides
│       │   ├── events.ts        queue/event payloads (if any)
│       │   └── validation.ts    ⭐ zod schemas — RUNTIME validation, shared
│       └── tsconfig.json
│
├── apps/
│   ├── web/
│   │   ├── package.json
│   │   ├── vite.config.ts
│   │   ├── index.html
│   │   ├── public/config.template.js   ⭐ runtime config (§04 of scenario 3)
│   │   ├── nginx/
│   │   │   ├── nginx.conf               ⭐ cache headers
│   │   │   └── docker-entrypoint.d/40-inject-config.sh
│   │   ├── Dockerfile
│   │   └── src/
│   │       ├── config.ts                ⭐ the single reader of /config.js
│   │       └── api/client.ts            typed fetch, imports @shop-mern/shared
│   │
│   └── api/
│       ├── package.json
│       ├── Dockerfile
│       ├── src/
│       │   ├── server.ts                ⭐ express app, exported separately
│       │   ├── app.ts                   from listen() — so tests can import it
│       │   ├── db.ts                    ⭐ the mongoose connection + replica-set check
│       │   ├── health.ts                ⭐ /healthz and /readyz
│       │   └── routes/orders.ts         validates with the SHARED zod schema
│       └── tests/
│           ├── unit/                    ⭐ no database
│           └── integration/             ⭐⭐ a REAL mongod (Testcontainers)
│
├── migrations/                  ⭐⭐ THE LEDGER YOU MUST BUILD (§8)
│   ├── 20260901120000-add-quantity-to-orders.js
│   ├── 20260910093000-backfill-total-cents.js
│   └── 20260915140000-create-index-orders-status-created.js
├── migrate-mongo-config.js
│
├── k8s/
│   ├── base/                    mern-web · mern-api · mern-mongo (StatefulSet)
│   └── overlays/{dev,staging,production}/
└── charts/shop-mern/            Helm — takes DIGESTS, never tags
```

### 3.1 ⭐ Why workspaces, and what they buy in CI

```jsonc
// package.json (root)
{
  "name": "shop-mern",
  "private": true,
  "workspaces": ["packages/*", "apps/*"],
  "engines": { "node": "24" },
  "scripts": {
    "build":        "npm run build -w @shop-mern/shared && npm run build --workspaces --if-present",
    "test":         "vitest run --coverage",
    "test:ci":      "vitest run --coverage --reporter=junit --outputFile=test-results.xml",
    "lint":         "eslint . && prettier --check .",
    "typecheck":    "tsc -b --pretty",
    "migrate:status": "migrate-mongo status",
    "migrate:up":     "migrate-mongo up"
  }
}
```

| Property | ⭐ Why it matters for CI/CD |
|---|---|
| **One `package-lock.json`** | ⭐ one cache key, one `npm ci`, one dependency-audit surface. Compare shape D: four lockfiles, four caches |
| **`npm ci` at the root installs everything** | ⛔ never `npm install` — it can rewrite the lockfile |
| ⭐ **`packages/shared` builds FIRST** | `apps/web` and `apps/api` both import it; if it is not built, both typechecks fail with confusing errors |
| **`tsc -b` (build mode)** | ⭐ respects project references and builds in dependency order |
| **One `vitest.workspace.ts`** | one coverage report for the whole repo, so the coverage gate is meaningful |
| ⛔ The cost | a change in `packages/shared` invalidates **both** apps — so the path filter must include it (exactly like `contracts/**` in shape D) |

---

## 4 · Version anchors

| Component | Version | ⭐ Note |
|---|---|---|
| **Node** | **24 LTS** | `setup-node@v6` with `node-version-file: .nvmrc` |
| **npm** | 11 (ships with Node 24) | ⛔ `npm ci`, never `npm install` |
| **TypeScript** | 5.9 | `strict: true` — non-negotiable, it *is* the contract |
| **React** | 19.3.0 | matches `shop-ui` |
| **Vite** | 7 | ⭐ `vite build` needs `NODE_OPTIONS=--max-old-space-size=6144` |
| **Express** | 5.1 | ⭐ Express 5, not 4 — different router semantics, native async error propagation |
| **Mongoose** | 8.20 | ⭐ `autoIndex: false` in production (§8.4) |
| **MongoDB** | **8.0** | pinned **by digest** in the StatefulSet |
| **zod** | 4 | ⭐ runtime validation shared by both tiers |
| **Vitest** | 3 | + `@vitest/coverage-v8` |
| **Playwright** | 1.5x | the E2E gate |
| **@testcontainers/mongodb** | 6.x | ⭐ a real mongod in CI (§7.2) |
| **migrate-mongo** | 9 | ⭐ the migration ledger (§8) |
| **nginx** | 1.29-alpine | matches `shop-ui` |
| **node base image** | `node:24-alpine` | ⭐ or `gcr.io/distroless/nodejs24-debian12` (§5.3) |
| Jenkins LTS | 2.568.3 | Java 21 minimum |
| Kubernetes | v1.37 "Garhwal" | |
| Argo CD | 3.x | |

---

## 5 · The Dockerfiles

### 5.1 ⭐ `apps/api/Dockerfile` — the interesting one

```dockerfile
# ── deps ───────────────────────────────────────────────────────────────
FROM node:24-alpine AS deps
WORKDIR /repo
# ⭐ COPY ONLY THE MANIFESTS FIRST — the layer that caches.
#   In a workspace monorepo you must copy EVERY workspace's package.json,
#   or `npm ci` fails with "no workspace configuration found".
COPY package.json package-lock.json ./
COPY packages/shared/package.json  packages/shared/
COPY apps/api/package.json         apps/api/
COPY apps/web/package.json         apps/web/
RUN --mount=type=cache,target=/root/.npm \
    npm ci --workspace=@shop-mern/shared --workspace=@shop-mern/api --omit=dev
    # ⭐ --omit=dev: no test tooling in the runtime image

# ── build ──────────────────────────────────────────────────────────────
FROM node:24-alpine AS build
WORKDIR /repo
COPY package.json package-lock.json ./
COPY packages/shared/package.json packages/shared/
COPY apps/api/package.json        apps/api/
COPY apps/web/package.json        apps/web/
RUN --mount=type=cache,target=/root/.npm npm ci
COPY tsconfig.base.json ./
COPY packages/shared/  packages/shared/
COPY apps/api/         apps/api/
# ⭐⭐ shared FIRST — api imports it
RUN npm run build -w @shop-mern/shared && npm run build -w @shop-mern/api

# ── runtime ────────────────────────────────────────────────────────────
FROM node:24-alpine AS runtime
RUN addgroup -S app && adduser -S app -G app
WORKDIR /app
ENV NODE_ENV=production \
    # ⭐⭐ THREE NODE FLAGS THAT MATTER IN A CONTAINER
    NODE_OPTIONS="--max-old-space-size=512" \
    #   Node reads the cgroup limit since v14, but an explicit ceiling stops
    #   the heap growing into the container limit and getting OOMKilled.
    NPM_CONFIG_UPDATE_NOTIFIER=false
COPY --from=deps  --chown=app:app /repo/node_modules           ./node_modules
COPY --from=build --chown=app:app /repo/packages/shared/dist   ./packages/shared/dist
COPY --from=build --chown=app:app /repo/packages/shared/package.json ./packages/shared/
COPY --from=build --chown=app:app /repo/apps/api/dist          ./apps/api/dist
COPY --from=build --chown=app:app /repo/apps/api/package.json  ./apps/api/
COPY --chown=app:app migrations/ ./migrations/
COPY --chown=app:app migrate-mongo-config.js ./
USER app
EXPOSE 4000
# ⭐⭐ healthcheck in the IMAGE, so `docker compose` and plain Docker agree
#   with Kubernetes about what "healthy" means
HEALTHCHECK --interval=10s --timeout=3s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:4000/readyz').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
CMD ["node","apps/api/dist/server.js"]
```

| Detail | ⭐ Why |
|---|---|
| Copy **every** workspace's `package.json` before `npm ci` | ⛔ npm workspaces fail without the full workspace map |
| ⭐ `--omit=dev` in the deps stage | vitest, playwright and typescript are ~300 MB and are **attack surface** |
| Build `shared` before `api` | the import graph requires it |
| ⭐ `USER app` (a non-root uid) | `node:alpine` ships a `node` user (uid 1000); creating `app` is explicit |
| ⭐ `NODE_OPTIONS=--max-old-space-size` | prevents the heap growing into the container limit → OOMKilled with no JS error |
| `HEALTHCHECK` in the image | so Docker and Kubernetes agree |
| ⛔ **no `.env` COPY** | config comes from the environment at runtime |

### 5.2 `apps/web/Dockerfile` — same discipline as `shop-ui`

```dockerfile
FROM node:24-alpine AS build
WORKDIR /repo
COPY package.json package-lock.json ./
COPY packages/shared/package.json packages/shared/
COPY apps/web/package.json        apps/web/
COPY apps/api/package.json        apps/api/
RUN --mount=type=cache,target=/root/.npm npm ci
COPY tsconfig.base.json ./
COPY packages/shared/ packages/shared/
COPY apps/web/        apps/web/
RUN npm run build -w @shop-mern/shared && \
    NODE_OPTIONS=--max-old-space-size=6144 npm run build -w @shop-mern/web
    # ⭐ the Vite heap ceiling (§04 of scenario 3)

FROM nginx:1.29-alpine AS runtime
# ⭐⭐ RUNTIME CONFIG — one image, every environment.
#   ⛔ VITE_API_URL baked at build time is the trap that makes you build
#      four images and still get it wrong.
COPY apps/web/nginx/nginx.conf                      /etc/nginx/conf.d/default.conf
COPY apps/web/nginx/docker-entrypoint.d/40-inject-config.sh /docker-entrypoint.d/
COPY --from=build /repo/apps/web/dist               /usr/share/nginx/html
EXPOSE 80
HEALTHCHECK --interval=10s --timeout=3s --retries=3 \
  CMD wget -qO- http://127.0.0.1/ >/dev/null || exit 1
```

```bash
#!/bin/sh
# apps/web/nginx/docker-entrypoint.d/40-inject-config.sh
# ⭐ runs on EVERY container start, from the REAL environment
set -eu
: "${MERN_API_URL:=http://localhost:4000}"
: "${MERN_ENV:=development}"
# ⭐⭐ ESCAPE THE VALUES — a quote or backslash in an env var otherwise
#   produces a config.js that is a SYNTAX ERROR, and the SPA renders blank.
esc() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }
cat > /usr/share/nginx/html/config.js <<EOF
window.__APP_CONFIG__ = {
  "apiUrl":  "$(esc "$MERN_API_URL")",
  "env":     "$(esc "$MERN_ENV")",
  "digest":  "$(esc "${APP_DIGEST:-unknown}")"
};
EOF
echo "✅ config.js written for env=$MERN_ENV api=$MERN_API_URL"
```

### 5.3 ⭐ MongoDB — do **not** build a custom image

```
⛔ THE TEMPTATION: FROM mongo:8.0 + COPY seed scripts + custom config.
   Now you own a database image: you must patch it, scan it, and every CVE
   in your layer is YOURS.

✅ THE ANSWER: use the official image, PINNED BY DIGEST, and put everything
   else in Kubernetes:
     • config        → a ConfigMap mounted at /etc/mongo
     • init/seed     → an init Job (§10.4), not a baked script
     • credentials   → a Secret
     • storage       → a PVC via volumeClaimTemplates
```

```yaml
# ⭐ pinned by digest, because `mongo:8.0` moves
image: mongo@sha256:0f3e6c1a…    # mongo:8.0.x — resolve with:
#   docker buildx imagetools inspect mongo:8.0 | grep -i digest
```

---

## 6 · ⭐⭐ The shared package IS the contract test

**In shape C (React + Java) you need `openapi-diff` and a generated client. In MERN you need neither — the compiler is the contract test.** But only if you set it up correctly, and the default setup does *not* give you this.

### 6.1 ⛔ The version that gives you nothing

```typescript
// apps/web/src/api/client.ts
interface Order { id: string; qty: number; total: number }   // ⛔ hand-written
// apps/api/src/routes/orders.ts
interface Order { id: string; quantity: number; totalCents: number }  // ⛔ also hand-written
```

```
Both compile. Both test suites pass. Production returns 400 / undefined.
⭐ This is EXACTLY the shape-C failure, and MERN does not fix it by being
   one language. It fixes it only if you SHARE the type.
```

### 6.2 ✅ The version that makes the compiler your contract test

```typescript
// packages/shared/src/api-types.ts
import { z } from 'zod';

// ⭐⭐ ONE zod schema → the RUNTIME validator AND the compile-time type.
//   Deriving the type from the schema means they cannot drift, because
//   there is only one declaration.
export const OrderInput = z.object({
  sku:       z.string().min(1),
  quantity:  z.number().int().positive(),
});
export type OrderInput = z.infer<typeof OrderInput>;

export const OrderOutput = z.object({
  orderId:    z.string(),
  quantity:   z.number().int(),
  totalCents: z.number().int(),
  status:     z.enum(['PENDING', 'PAID', 'SHIPPED', 'CANCELLED']),
  createdAt:  z.string().datetime(),
});
export type OrderOutput = z.infer<typeof OrderOutput>;

export const CONTRACT_VERSION = 2;   // ⭐ §6.4
```

```typescript
// packages/shared/src/routes.ts — ⭐ the route table, one place
export const ROUTES = {
  orders: {
    list:   { method: 'GET',  path: '/api/v2/orders'          },
    create: { method: 'POST', path: '/api/v2/orders'          },
    get:    { method: 'GET',  path: '/api/v2/orders/:orderId' },
  },
} as const;
```

```typescript
// apps/api/src/routes/orders.ts — the SERVER side
import { OrderInput, OrderOutput, ROUTES } from '@shop-mern/shared';

router.post(ROUTES.orders.create.path, async (req, res) => {
  const parsed = OrderInput.safeParse(req.body);       // ⭐ runtime validation
  if (!parsed.success)
    return res.status(400).json({ error: 'INVALID_INPUT', issues: parsed.error.issues });

  const doc = await Order.create(parsed.data);
  // ⭐⭐ this line is the contract test. If the document does not satisfy
  //   OrderOutput, TypeScript REFUSES TO COMPILE — in CI, not in production.
  const body: OrderOutput = {
    orderId:    doc.orderId,
    quantity:   doc.quantity,
    totalCents: doc.totalCents,
    status:     doc.status,
    createdAt:  doc.createdAt.toISOString(),
  };
  res.status(201).json(body);
});
```

```typescript
// apps/web/src/api/client.ts — the CLIENT side
import { OrderOutput, ROUTES } from '@shop-mern/shared';

export async function createOrder(input: OrderInput): Promise<OrderOutput> {
  const r = await fetch(`${cfg().apiUrl}${ROUTES.orders.create.path}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(input),
  });
  if (!r.ok) throw new ApiError(r.status, await r.text());
  // ⭐⭐ validate the RESPONSE too — the server may be an older version
  //   during a rolling update (§2's two-writers hazard)
  return OrderOutput.parse(await r.json());
}
```

### 6.3 ⭐ What this buys, and what it does not

| | ⭐ Effect |
|---|---|
| A field is renamed in `shared` | **both** apps fail to compile, in CI, naming the line |
| A route path changes | one edit, both sides move — ⛔ drift is impossible |
| The response shape changes | ⭐ `OrderOutput.parse` fails at **runtime** too, so an old server + new client is a *caught* error, not a silent `undefined` |
| ⛔ What it does **not** cover | a change to what the code *does* with a valid value; a MongoDB document that predates the schema; anything written around the app |

⭐⭐ **The rule:** *derive the type from the validator, never write both.* `z.infer` is the whole trick. Two declarations drift; one cannot.

### 6.4 ⭐ `CONTRACT_VERSION` — still needed, and here is why

Types are compile-time. **A browser holding yesterday's bundle is not recompiled.** So the shape-C `contract-version` mechanism applies verbatim:

```typescript
// api: GET /api/contract-version
router.get('/api/contract-version', (_req, res) =>
  res.json({ version: CONTRACT_VERSION, serves: [1, 2] }));   // ⭐ a LIST

// web: on startup
const { serves } = await (await fetch(`${cfg().apiUrl}/api/contract-version`)).json();
if (!serves.includes(CONTRACT_VERSION)) showRefreshBanner();
```

---

## 7 · ⭐⭐ CI — the four MERN-specific gates

### 7.1 Gate 1 — `npm ci` at the root, with one cache

```yaml
- uses: actions/setup-node@v6
  with:
    node-version-file: .nvmrc                 # ⭐ pinned by the repo, not the workflow
    cache: npm
    cache-dependency-path: package-lock.json  # ⭐ ONE lockfile → ONE cache key
- run: npm ci                                 # ⛔ never `npm install`
```

```
⭐ WHY THIS IS THE CHEAPEST CI IN THE WHOLE FOLDER
   Shape D needs four caches, four toolchain setups, four agents.
   MERN needs one `npm ci` and one cache — the entire monorepo.
   ⛔ AND THE TRAP THAT GOES WITH IT: because there is ONE lockfile, a
     dependency bump in apps/web invalidates the cache for apps/api too.
     With workspaces that is unavoidable; the mitigation is that `npm ci`
     is fast (20 s warm), not that the cache is precise.
```

### 7.2 ⭐⭐ Gate 2 — a REAL mongod, and the in-memory trap

```
⛔ mongodb-memory-server
   It is the default in most MERN tutorials, and it is WRONG for CI:
     1. ⛔ it DOWNLOADS a mongod binary at first run — your CI is not
        hermetic, and a MongoDB CDN outage fails your build
     2. ⛔ the downloaded version is whatever it resolves to, NOT 8.0
     3. ⛔ it runs as a SINGLE NODE — so transactions SILENTLY do not work
     4. ⛔ it uses an ephemeral/in-memory storage engine — no real WAL,
        no real index builds, no real replica-set behaviour
   Tests that pass on it and fail in production: exactly the H2 problem (§05
   of scenario 3), in JavaScript.

✅ @testcontainers/mongodb — a real mongod 8.0, as a REPLICA SET
```

```typescript
// apps/api/tests/integration/setup.ts
import { MongoDBContainer } from '@testcontainers/mongodb';
import mongoose from 'mongoose';

// ⭐⭐ the image is pinned; the container is a real mongod
const container = await new MongoDBContainer('mongo:8.0')
  .withReuse(false)
  .start();

// ⭐⭐ Testcontainers' MongoDB module starts a SINGLE-NODE REPLICA SET,
//   which is exactly what Mongoose transactions require (§9.3).
await mongoose.connect(container.getConnectionString(), {
  // ⛔ DO NOT let Mongoose create indexes behind your back in tests either
  autoIndex: false,
});

export async function teardown() {
  await mongoose.disconnect();
  await container.stop();
}
```

```yaml
# ⭐ where the Docker daemon comes from — same table as §05 of scenario 3
# GitHub-hosted runner / Azure DevOps vmImage / Jenkins VM agent → it exists
# ⛔ Jenkins Kubernetes pod agent → NO daemon. Options:
#    (a) a mongod SIDECAR in the pod template, with --replSet rs0 and an
#        rs.initiate() init step  ← ⭐ needed even for a sidecar, or no transactions
#    (b) Testcontainers Cloud
#    (c) a VM agent for that job
#    ⛔ NEVER mount /var/run/docker.sock
```

### 7.3 Gate 3 — the typecheck IS the contract test

```yaml
- name: ⭐⭐ Build shared, then typecheck the whole repo
  run: |
    set -euo pipefail
    npm run build -w @shop-mern/shared       # ⭐ shared FIRST, always
    npm run typecheck                        # tsc -b across all workspaces
    # ⛔ if this is skipped, the shared contract is decorative: both apps
    #   compile against their OWN stale copy of the .d.ts
```

### 7.4 Gate 4 — the migration dry-run

```yaml
- name: ⭐⭐ Apply migrations to a throwaway database, then verify status
  run: |
    set -euo pipefail
    # a second, empty mongod — not the test one
    docker run -d --name migrate-db -p 27018:27017 mongo:8.0 \
      --replSet rs0 --bind_ip_all
    sleep 6
    docker exec migrate-db mongosh --quiet --eval 'rs.initiate()' >/dev/null
    sleep 4
    export MONGODB_URL="mongodb://localhost:27018/shop_migrate?replicaSet=rs0"
    npx migrate-mongo status            # ⭐ shows what is pending
    npx migrate-mongo up                # ⭐ must exit 0
    npx migrate-mongo status            # ⭐ all "applied"
    # ⭐⭐ AND the shadow check (§05 of scenario 3 §3.2): run the same
    #   migrations against a COPY OF PRODUCTION'S DATA SHAPE, not just empty.
```

### 7.5 The full CI job list

| # | Step | ⭐ MERN-specific? |
|---|---|---|
| 1 | `npm ci` (root, one cache) | ✅ one lockfile |
| 2 | `eslint .` + `prettier --check .` | |
| 3 | ⭐⭐ `build shared` → `tsc -b` | ✅ **the contract test** |
| 4 | `vitest run --coverage` (unit) | |
| 5 | ⭐⭐ integration tests vs a **real mongod 8.0 replica set** | ✅ Testcontainers |
| 6 | ⭐⭐ `migrate-mongo up` on a throwaway DB + shadow schema | ✅ no Flyway here |
| 7 | `NODE_OPTIONS=--max-old-space-size=6144 npm run build -w web` | |
| 8 | ⭐ bundle-size gate + `grep` the bundle for secrets | ✅ same as shop-ui |
| 9 | ⭐ Lighthouse × 3, take the median | ✅ same as shop-ui |
| 10 | Playwright E2E against the built app + a real mongod | ⭐⭐ the highest-value gate |
| 11 | `npm audit --audit-level=high` (⛔ a gate, not a report) | |
| 12 | Build both images → Trivy → cosign sign → **emit digests** | |
| 13 | ⭐ **Playwright against the BUILT IMAGES**, not the dev server | ✅ see §7.6 |

### 7.6 ⭐ Step 13 — test the image, not the dev server

```
⛔ THE COMMON MERN CI MISTAKE
   `npm run dev` + Playwright → GREEN
   ship the image → ⛔ blank page

   WHY: the dev server serves unbundled ESM with Vite's env handling and a
   permissive CORS/host config. The production image serves a BUNDLED SPA
   from nginx, with /config.js injected at container start, a strict CSP,
   and cache headers. Those are DIFFERENT PROGRAMS.

✅ THE FIX — run Playwright against `docker compose up` of the BUILT images
```

```yaml
- name: ⭐⭐ E2E against the built images
  run: |
    set -euo pipefail
    docker compose -f docker-compose.ci.yml up -d --wait   # web + api + mongo
    curl -fsS http://localhost/config.js | grep -q apiUrl  # ⭐ runtime config injected
    npx playwright test --project=chromium
    docker compose -f docker-compose.ci.yml logs --tail=200 > e2e-logs.txt || true
    docker compose -f docker-compose.ci.yml down -v
```

---

## 8 · ⭐⭐ The migration problem — Mongoose does not solve it for you

### 8.1 ⛔ What Mongoose actually does

```
Mongoose schemas are APPLICATION-LEVEL. They:
   ✅ validate documents on the way in (through the app)
   ✅ cast types
   ⛔ DO NOT alter stored data
   ⛔ DO NOT record what has been applied
   ⛔ DO NOT prevent an old document from existing
   ⛔ DO NOT run in order, atomically, or exactly once

⭐ There is no `flyway_schema_history`. There is no ledger. If you do not
   build one, you have no idea what shape your production data is in.
```

### 8.2 ✅ Build the ledger — `migrate-mongo`

```javascript
// migrate-mongo-config.js
module.exports = {
  mongodb: {
    url: process.env.MONGODB_URL,          // ⭐ from the environment, never hardcoded
    options: {
      // ⭐⭐ connect to the REPLICA SET, or transactions in migrations fail
      replicaSet: process.env.MONGO_REPLICA_SET || 'rs0',
      retryWrites: true,
      serverSelectionTimeoutMS: 10000,
    },
  },
  migrationsDir: 'migrations',
  changelogCollectionName: 'schema_migrations',   // ⭐⭐ THE LEDGER
  useFileHash: true,       // ⭐ detect an edited migration that already ran
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
 * ⭐ SAFE:  idempotent, batched, and reversible (see `down`)
 */
module.exports = {
  async up(db) {
    // ⭐⭐ BATCH IT. A single updateMany over 1.2M documents takes a
    //   write lock per document, grows the oplog, and can lag the replicas.
    let touched = 0;
    while (true) {
      const r = await db.collection('orders').updateMany(
        { total: { $exists: true }, totalCents: { $exists: false } },
        [ { $set: { totalCents: { $round: [ { $multiply: ['$total', 100] } ] } } } ],
        { }
      );
      // ⭐ use a bounded batch loop rather than one giant updateMany in prod
      touched += r.modifiedCount;
      if (r.matchedCount === 0) break;
      if (touched > 5_000_000) throw new Error('runaway migration — aborting');
      await new Promise(res => setTimeout(res, 100));   // ⭐ let replicas breathe
    }
    console.log(`✅ backfilled ${touched} orders`);
  },

  async down(db) {
    // ⭐⭐ NOT "drop the column" — MongoDB has none. The reverse of a
    //   backfill is to REMOVE the new field, and that is LOSSY if the app
    //   has since written values the legacy field never had.
    const r = await db.collection('orders').updateMany(
      { totalCents: { $exists: true } },
      { $unset: { totalCents: '' } }
    );
    console.log(`↩️ removed totalCents from ${r.modifiedCount} orders`);
  },
};
```

### 8.3 ⭐ The five rules for a MERN migration

| # | Rule | ⭐ Why |
|---|---|---|
| **1** | ⭐⭐ **Idempotent** — safe to run twice | a Job retry, a partial failure, or a human re-running it must not corrupt data |
| **2** | ⭐ **Batched** — never one unbounded `updateMany` | lock duration, oplog growth, replica lag |
| **3** | **Has a real `down`** — or is explicitly marked irreversible | ⛔ and note that in MongoDB `down` is often **lossy**, unlike a SQL `DROP COLUMN` |
| **4** | ⭐ **Runs in a Job with `backoffLimit: 0`** | a failed migration needs a human, not a second attempt that may have half-applied |
| **5** | **Never edits an already-applied migration** | `useFileHash: true` makes that a hard failure — ⭐ keep it on |

### 8.4 ⭐⭐ The `syncIndexes()` trap

```javascript
// ⛔ THE LINE THAT DESTROYS PRODUCTION
await mongoose.connect(url);        // with Mongoose's default autoIndex: true
// Mongoose calls createIndex for every index in your schemas AT STARTUP.
```

```
WHY IT IS DANGEROUS:
   1. ⛔ createIndex on a large collection takes a LOCK and can run for
      minutes — during a rolling update, on every new pod, simultaneously
   2. ⛔ If you RENAMED an index in the schema, Mongoose creates the new one
      but does NOT drop the old one → index bloat, slower writes, more RAM
   3. ⛔⛔ If you call `Model.syncIndexes()` — which many tutorials recommend —
      it DROPS indexes that are not in the schema. On a 3-replica rolling
      update, an OLD pod can then re-create what a NEW pod just dropped,
      and query plans change mid-rollout.
   4. ⛔ A missing index in production = a collection scan = the database
      falls over under normal load, minutes after a "successful" deploy.

✅ THE FIX
   • autoIndex: false in every environment (set it in code, not by env)
   • indexes are created by a MIGRATION, in a gated Job, before the rollout
   • `migrate-mongo status` shows whether it ran
```

```typescript
// apps/api/src/db.ts
export async function connect() {
  await mongoose.connect(process.env.MONGODB_URL!, {
    autoIndex: false,          // ⭐⭐ ALWAYS false. Indexes come from migrations.
    autoCreate: false,         // ⛔ never let the app create databases either
    serverSelectionTimeoutMS: 10_000,
    maxPoolSize: Number(process.env.MONGO_POOL_SIZE ?? 20),
    // ⭐ the pool size matters: 3 replicas × 20 = 60 connections to mongod,
    //   whose default maxIncomingConnections is 65536 but whose wiredTiger
    //   cache and CPU are not infinite
  });
  // ⭐⭐ fail fast and loudly if this is not a replica set and the app
  //   intends to use transactions
  const hello = await mongoose.connection.db.admin().command({ hello: 1 });
  if (!hello.setName && process.env.REQUIRE_REPLICA_SET === 'true')
    throw new Error('⛔ transactions require a replica set; connected to a standalone mongod');
}
```

---

## 9 · Kubernetes — the three workloads

### 9.1 `mern-web` — a Deployment, identical in shape to `shop-ui`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata: { name: mern-web, namespace: shop-production, labels: { app: mern-web } }
spec:
  replicas: 2
  strategy: { rollingUpdate: { maxUnavailable: 0, maxSurge: 1 } }
  selector: { matchLabels: { app: mern-web } }
  template:
    metadata: { labels: { app: mern-web } }
    spec:
      containers:
        - name: mern-web
          image: ghcr.io/3558bhk/mern-web@sha256:PLACEHOLDER   # ⭐ digest
          ports: [{ containerPort: 80 }]
          env:
            - { name: MERN_API_URL, valueFrom: { configMapKeyRef: { name: mern-web-config, key: apiUrl } } }
            - { name: MERN_ENV,     value: production }
          readinessProbe: { httpGet: { path: /, port: 80 }, periodSeconds: 5 }
          resources: { requests: { cpu: 20m, memory: 32Mi }, limits: { cpu: 200m, memory: 128Mi } }
```

### 9.2 `mern-api` — a Deployment with the three probes

```yaml
apiVersion: apps/v1
kind: Deployment
metadata: { name: mern-api, namespace: shop-production, labels: { app: mern-api } }
spec:
  replicas: 3
  revisionHistoryLimit: 10
  strategy: { rollingUpdate: { maxUnavailable: 0, maxSurge: 1 } }
  selector: { matchLabels: { app: mern-api } }
  template:
    metadata: { labels: { app: mern-api } }
    spec:
      terminationGracePeriodSeconds: 45      # ⭐ drain: close the mongo pool
      containers:
        - name: mern-api
          image: ghcr.io/3558bhk/mern-api@sha256:PLACEHOLDER
          ports: [{ containerPort: 4000 }]
          envFrom: [{ configMapRef: { name: mern-api-config } }]
          env:
            - name: MONGODB_URL
              valueFrom: { secretKeyRef: { name: mern-mongo, key: url } }
            - { name: REQUIRE_REPLICA_SET, value: "true" }
            - { name: NODE_ENV,            value: production }
          startupProbe:                      # ⭐ Node starts in ~1 s, but the
            httpGet: { path: /healthz, port: 4000 }   #   MONGO connection may not be
            failureThreshold: 15             #   ready — probe liveness, not readiness
            periodSeconds: 2
          readinessProbe:                    # ⭐⭐ GATES TRAFFIC — and it must
            httpGet: { path: /readyz, port: 4000 }    #   check the DATABASE
            periodSeconds: 10
            failureThreshold: 3
          livenessProbe:                     # ⭐ RESTARTS A STUCK PROCESS
            httpGet: { path: /healthz, port: 4000 }   # ⛔ NOT /readyz — a mongo
            periodSeconds: 20                         #   blip would restart-loop
            failureThreshold: 3               #   your entire fleet
          lifecycle:
            preStop:
              exec: { command: ["/bin/sh","-c","sleep 8 && node -e \"process.kill(1,'SIGTERM')\" || true"] }
              # ⭐ endpoint removal is asynchronous — the same 502 fix as Java
          resources:
            requests: { cpu: 100m, memory: 128Mi }
            limits:   { cpu: "1",  memory: 512Mi }
```

```typescript
// apps/api/src/health.ts — ⭐⭐ the two endpoints must mean different things
import { Router } from 'express';
import mongoose from 'mongoose';

export const health = Router();

// LIVENESS: "is the process able to respond?" — ⛔ must NOT touch Mongo.
// If it did, a Mongo outage would restart-loop every pod, turning an outage
// into a much worse outage.
health.get('/healthz', (_req, res) => res.status(200).json({ ok: true }));

// READINESS: "can I serve a real request?" — ⭐ MUST touch Mongo.
health.get('/readyz', async (_req, res) => {
  try {
    if (mongoose.connection.readyState !== 1)
      return res.status(503).json({ ok: false, reason: 'mongo-not-connected' });
    await mongoose.connection.db.admin().command({ ping: 1 });       // ⭐ real round-trip
    const hello = await mongoose.connection.db.admin().command({ hello: 1 });
    if (process.env.REQUIRE_REPLICA_SET === 'true' && !hello.setName)
      return res.status(503).json({ ok: false, reason: 'not-a-replica-set' });
    res.json({ ok: true, mongo: hello.setName ?? 'standalone',
               contract: CONTRACT_VERSION, digest: process.env.APP_DIGEST });
  } catch (e) {
    res.status(503).json({ ok: false, reason: String(e) });
  }
});
```

### 9.3 ⭐⭐ `mern-mongo` — a StatefulSet, and the replica-set requirement

```
⭐ THE FACT THAT BREAKS MOST MERN DEPLOYMENTS:
   Mongoose's `session.withTransaction()` — and therefore ANY multi-document
   atomicity — REQUIRES A REPLICA SET. Against a standalone mongod it throws:

      MongoServerError: Transaction numbers are only allowed on a replica
      set member or mongos

   ⛔ AND the worse version: code paths guarded by `if (session)` silently
     skip the transaction, so your "atomic" order creation is not atomic,
     and you find out during an incident.

   So: even in DEV, run a replica set. A single-member replica set is fine
   and costs nothing.
```

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata: { name: mern-mongo, namespace: shop-production }
spec:
  serviceName: mern-mongo                    # ⭐ the headless service
  replicas: 3                                # ⭐ 3 for a real replica set
  updateStrategy:
    type: RollingUpdate
    rollingUpdate: { partition: 0 }          # ⭐ one at a time, highest ordinal first
  selector: { matchLabels: { app: mern-mongo } }
  template:
    metadata: { labels: { app: mern-mongo } }
    spec:
      securityContext:
        fsGroup: 999                         # ⭐ mongod's uid/gid in the official image
      terminationGracePeriodSeconds: 120     # ⭐ flush and step down cleanly
      containers:
        - name: mongod
          image: mongo@sha256:0f3e6c1a…      # ⭐⭐ official image, PINNED BY DIGEST
          args:
            - --replSet=rs0                  # ⭐⭐ the whole point
            - --bind_ip_all
            - --wiredTigerCacheSizeGB=1.5    # ⭐⭐ SET THIS. Default = 50% of
            #   (RAM - 1GB) as seen by mongod, which in a container with no
            #   cgroup awareness can exceed the limit → OOMKilled.
          ports: [{ containerPort: 27017 }]
          env:
            - { name: MONGO_INITDB_ROOT_USERNAME, valueFrom: { secretKeyRef: { name: mern-mongo, key: username } } }
            - { name: MONGO_INITDB_ROOT_PASSWORD, valueFrom: { secretKeyRef: { name: mern-mongo, key: password } } }
          readinessProbe:
            exec:
              command: ["/bin/sh","-c",
                "mongosh --quiet -u \"$MONGO_INITDB_ROOT_USERNAME\" -p \"$MONGO_INITDB_ROOT_PASSWORD\" --authenticationDatabase admin --eval 'db.hello().ok' | grep -q 1"]
            initialDelaySeconds: 10
            periodSeconds: 10
          livenessProbe:
            exec: { command: ["/bin/sh","-c","pgrep -x mongod"] }
            periodSeconds: 20
            failureThreshold: 6              # ⭐ tolerant — restarting mongod is expensive
          resources:
            requests: { cpu: 500m, memory: 2Gi }
            limits:   { cpu: "2",  memory: 3Gi }
          volumeMounts:
            - { name: data, mountPath: /data/db }
            - { name: configdb, mountPath: /data/configdb }
  volumeClaimTemplates:                       # ⭐⭐ a PVC PER POD, and it
    - metadata: { name: data }                #   SURVIVES the pod
      spec:
        accessModes: [ReadWriteOnce]
        resources: { requests: { storage: 20Gi } }
        # ⭐ storageClassName: omit on kind, set explicitly in a real cluster
    - metadata: { name: configdb }
      spec:
        accessModes: [ReadWriteOnce]
        resources: { requests: { storage: 1Gi } }
---
apiVersion: v1
kind: Service                                  # ⭐ HEADLESS — StatefulSets need it
metadata: { name: mern-mongo, namespace: shop-production }
spec:
  clusterIP: None                              # ⭐⭐ `None` = stable DNS per pod
  selector: { app: mern-mongo }
  ports: [{ port: 27017 }]
# → mern-mongo-0.mern-mongo.shop-production.svc.cluster.local
```

```yaml
# ⭐ rs.initiate() — must happen exactly once, against pod 0
apiVersion: batch/v1
kind: Job
metadata:
  name: mern-mongo-initiate
  namespace: shop-production
  annotations:
    argocd.argoproj.io/hook: PostSync          # ⭐ after the StatefulSet exists
spec:
  backoffLimit: 2                              # ⭐ here retry IS safe: initiate
                                               #   is idempotent (it errors
                                               #   harmlessly if already done)
  template:
    spec:
      restartPolicy: OnFailure
      containers:
        - name: initiate
          image: mongo@sha256:0f3e6c1a…
          command: ["/bin/sh","-c"]
          args:
            - |
              set -eu
              # ⭐ wait for pod-0 to accept connections
              until mongosh --host mern-mongo-0.mern-mongo --quiet \
                    -u "$MONGO_USER" -p "$MONGO_PASS" --authenticationDatabase admin \
                    --eval 'db.adminCommand({ping:1})' >/dev/null 2>&1; do
                echo "waiting for mern-mongo-0…"; sleep 5;
              done
              # ⭐⭐ idempotent: "already initialized" is a SUCCESS, not a failure
              OUT=$(mongosh --host mern-mongo-0.mern-mongo --quiet \
                    -u "$MONGO_USER" -p "$MONGO_PASS" --authenticationDatabase admin \
                    --eval 'try { rs.initiate({_id:"rs0", members:[
                      {_id:0,host:"mern-mongo-0.mern-mongo:27017"},
                      {_id:1,host:"mern-mongo-1.mern-mongo:27017"},
                      {_id:2,host:"mern-mongo-2.mern-mongo:27017"}]}) ; "ok" }
                            catch(e) { e.codeName === "AlreadyInitialized" ? "ok" : "fail:"+e.message }')
              echo "$OUT" | grep -q ok || { echo "⛔ $OUT"; exit 1; }
              echo "✅ replica set rs0 initialised"
```

### 9.4 ⭐ The connection string, and why it must list all members

```
⛔ WRONG (and the most common MERN-on-K8s mistake)
   mongodb://mern-mongo-0.mern-mongo:27017/shop?replicaSet=rs0
   → pinned to pod 0. When pod 0 is not the PRIMARY (after a failover, a
     rolling update, or a node drain), every write fails or blocks.

✅ RIGHT
   mongodb://mern-mongo-0.mern-mongo:27017,mern-mongo-1.mern-mongo:27017,mern-mongo-2.mern-mongo:27017/shop?replicaSet=rs0&retryWrites=true&w=majority&readPreference=primaryPreferred
   ⭐ list ALL members. The driver discovers the primary and follows it.
   ⭐ retryWrites=true   → a write retried once on a transient primary election
   ⭐ w=majority          → ⛔ without it, a write acknowledged by a primary
                             that then steps down is LOST. This is a data-loss
                             setting, and it is the default in Mongoose 6+.
```

---

## 10 · ⭐ CD — ordering, rollback, and the backup gate

### 10.1 The deploy order

```
1 · ⭐⭐ BACK UP MONGODB and VERIFY the backup restores      (§10.2)
2 · run the MIGRATION Job, gated on success                  (§10.3)
3 · deploy mern-api      → rollout status → /readyz → business smoke
4 · deploy mern-web      → rollout status → config.js → cache headers
5 · ⛔ mern-mongo is NOT deployed here — it is upgraded SEPARATELY (§10.5)
6 · read back BOTH digests from the cluster
```

⭐ **Why the api before the web:** exactly shape C's rule A — the callee before the caller. The API must serve both the old and the new frontend, because browsers hold the old bundle for hours.

### 10.2 ⭐⭐ The backup gate — the only rollback MongoDB has

```bash
#!/usr/bin/env bash
# ⛔ A BACKUP YOU HAVE NEVER RESTORED IS A HYPOTHESIS.
set -euo pipefail
NS="${NS:-shop-production}"
STAMP=$(date -u +%Y%m%dT%H%M%SZ)

# ── 1 · take it ────────────────────────────────────────────────────────
kubectl -n $NS run mongodump-$STAMP --rm -i --restart=Never \
  --image=mongo@sha256:0f3e6c1a… -- \
  mongodump --uri="$MONGODB_URL" --gzip --archive --oplog \
  > "backup-$STAMP.archive.gz"
# ⭐ --oplog gives a POINT-IN-TIME-consistent dump of a live database.
#   ⛔ without it, a write during the dump produces a torn backup.

# ── 2 · ⭐⭐ PROVE IT RESTORES — into a THROWAWAY database ─────────────
kubectl -n $NS run mongorestore-$STAMP --rm -i --restart=Never \
  --image=mongo@sha256:0f3e6c1a… -- sh -c '
    mongorestore --uri="mongodb://verify-mongo:27017/?replicaSet=rs0" \
                 --gzip --archive --nsInclude "shop_verify.*" ' < "backup-$STAMP.archive.gz"

# ── 3 · ⭐ COMPARE COUNTS — the check that a 0-byte file cannot pass ───
for c in orders users products; do
  SRC=$(kubectl -n $NS run c-$RANDOM --rm -i --restart=Never --image=mongo@sha256:0f3e6c1a… -- \
        mongosh --quiet "$MONGODB_URL" --eval "db.$c.countDocuments()")
  DST=$(kubectl -n $NS run c-$RANDOM --rm -i --restart=Never --image=mongo@sha256:0f3e6c1a… -- \
        mongosh --quiet "mongodb://verify-mongo:27017/shop_verify" --eval "db.$c.countDocuments()")
  [ "$SRC" = "$DST" ] || { echo "⛔ $c: source=$SRC restored=$DST"; exit 1; }
  echo "✅ $c: $SRC documents verified"
done

# ── 4 · record it ──────────────────────────────────────────────────────
echo "$STAMP backup=$(du -h backup-$STAMP.archive.gz | cut -f1) verified=true" >> deploy-audit.log
```

| Why each step | ⭐ |
|---|---|
| `--oplog` | a consistent point-in-time snapshot of a **live** database |
| ⭐⭐ restore it | `mongodump` exits 0 on a dump nobody can read. Restoring is the only proof |
| ⭐ compare counts | catches the empty-file and wrong-namespace cases |
| record it | "was there a verified backup before this deploy?" must be answerable in an incident |

### 10.3 The migration Job — gated, exactly like Flyway

```yaml
apiVersion: batch/v1
kind: Job
metadata: { name: mern-api-migrate, namespace: shop-production }
spec:
  backoffLimit: 0                    # ⭐⭐ NO RETRY — a half-applied data
                                     #   migration must not be run again blindly
  ttlSecondsAfterFinished: 86400
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: migrate
          image: ghcr.io/3558bhk/mern-api@sha256:PLACEHOLDER   # ⭐ SAME digest as the app
          command: ["npx","migrate-mongo","up"]
          env:
            - { name: MONGODB_URL, valueFrom: { secretKeyRef: { name: mern-mongo, key: url } } }
          resources: { requests: { cpu: 100m, memory: 256Mi }, limits: { cpu: "1", memory: 1Gi } }
```

```bash
kubectl -n shop-production delete job mern-api-migrate --ignore-not-found
kubectl -n shop-production apply  -f k8s/mern-api/migration-job.yaml
kubectl -n shop-production wait   --for=condition=complete job/mern-api-migrate --timeout=900s \
  || { echo "⛔ migration FAILED — NOT rolling out"; \
       kubectl -n shop-production logs job/mern-api-migrate --tail=200; exit 1; }
```

### 10.4 Seed / index Job — separate from migrations

```
⭐ KEEP THREE THINGS SEPARATE, even though every MERN tutorial merges them:
   1. MIGRATIONS  — change the shape of existing data. Gated, ordered, ledgered.
   2. INDEXES     — change query performance. A migration, but its own file,
                    because a failed index build must not block a data change.
   3. SEED DATA   — only for dev/staging. ⛔ NEVER in production.
```

```javascript
// migrations/20260915140000-create-index-orders-status-created.js
module.exports = {
  async up(db) {
    // ⭐⭐ background: false is the DEFAULT and CORRECT choice in MongoDB 8
    //   (all index builds are optimised now), but the build still takes a
    //   lock-free-but-expensive pass. Time it in staging FIRST.
    await db.collection('orders').createIndex(
      { status: 1, createdAt: -1 },
      { name: 'idx_status_created', background: false }
    );
    // ⭐ and PROVE it is used
    const plan = await db.collection('orders')
      .find({ status: 'PAID' }).sort({ createdAt: -1 }).limit(1).explain('queryPlanner');
    const stage = JSON.stringify(plan);
    if (!stage.includes('idx_status_created'))
      throw new Error('⛔ the new index is not being used — check the query shape');
  },
  async down(db) { await db.collection('orders').dropIndex('idx_status_created'); },
};
```

### 10.5 ⭐ Upgrading MongoDB itself — never in the app's release train

```
⛔ NEVER: bump mongo:8.0 → mongo:8.2 in the same PR as an app change.

✅ THE SEQUENCE (one version step at a time, and MongoDB's rule is strict:
   you may not skip a feature compatibility version)
   1. ⭐ take and VERIFY a backup (§10.2)
   2. db.adminCommand({ setFeatureCompatibilityVersion: "8.0" })  — confirm
   3. read the release notes for the jump
   4. upgrade SECONDARIES first: `kubectl rollout restart` with partition
      set so only ordinals 1 and 2 move; let each rejoin and catch up
   5. ⭐ check replication lag is 0 between each: rs.printSecondaryReplicationInfo()
   6. step down the primary: rs.stepDown(60) — it re-elects on an upgraded node
   7. upgrade the old primary
   8. only THEN raise featureCompatibilityVersion to "8.2"
   9. ⛔ lowering fCV back is a ONE-WAY DOOR in some versions — that is why
      step 8 is last, and why the backup in step 1 is the real rollback
  10. watch for 24 h
```

⭐ **The consequence for CD:** `mern-mongo`'s image reference must **not** be in the release manifest that `mern-api` and `mern-web` share. Give it its own manifest and its own 🔒 approval, so an app deploy can never accidentally move the database.

---

## 11 · 🔒 Case 1 or 🤖 Case 2 — per tier

Applying the five prerequisites ([`scenario-2-cd-only/00-delivery-vs-deployment.md`](./scenario-2-cd-only/00-delivery-vs-deployment.md) §6):

| Tier | P1 reversible | P2 tests | P3 metrics | P4 digest | P5 migrations | ⭐ Verdict |
|---|---|---|---|---|---|---|
| `mern-web` | ✅ static files, instant | ✅ + Lighthouse | ⚠️ needs RUM | ✅ | ✅ n/a | 🤖 **Case 2** |
| `mern-api` | ✅ the image | ⭐⭐ real-mongod ITs + E2E on images | ✅ `/readyz` + RED | ✅ | ⛔ **until the ledger is disciplined** | 🔒 **Case 1** |
| `mern-mongo` | ⛔ **only a restore** | ⛔ | ✅ `rs.status()` | ⭐ pinned by digest | ⛔ **the data IS the migration** | 🔒🔒 **Case 1, always, separately** |

⭐ **What would move `mern-api` to Case 2:** the same thing that would move `shop-api` — every migration genuinely expand/contract, idempotent, batched, with a real `down`, and a shadow-data check in CI. MERN has an *additional* prerequisite that the Java stack does not: **because MongoDB does not enforce the schema, your integration tests must prove the app tolerates documents in the OLD shape.** A SQL database rejects them; MongoDB serves them to your new code.

---

## 12 · How each scenario and each tool uses this project

### 12.1 Per scenario

| Scenario | What MERN exercises that nothing else does |
|---|---|
| **① CI only** | ⭐ One lockfile, one cache, one toolchain — the cheapest CI in the folder. Plus the **real-mongod** gate and the **migration dry-run**, neither of which appears in shapes A–D. And step 13: Playwright against the **built images** |
| **② CD only, 🔒 Case 1** | ⭐⭐ **The backup gate.** MERN is the only shape where "verify the backup restores" belongs *inside* the deploy pipeline, because the data tier ships with the app |
| **② CD only, 🤖 Case 2** | ⭐ Canary `mern-web` freely (static files); canary `mern-api` **only** with `w=majority` and idempotent writes, because a canary that is rolled back after acknowledging writes has written data the rollback does not undo |
| **③ CI+CD** | ⭐ The **shared package** replaces shape C's `openapi-diff` — the contract test is a `tsc -b`. And the three-tier ordering: backup → migrate → api → web |

### 12.2 Per tool

| Tool | ⭐ The MERN-specific thing to get right |
|---|---|
| 🐙 **GitHub Actions** | `setup-node@v6` with `cache: npm` and `cache-dependency-path: package-lock.json`; ⭐ Testcontainers works because hosted runners have a daemon; `workflow_run` to chain CI→CD |
| 🔷 **Azure DevOps** | `NodeTool@0` + `Npm@3` with `customRegistries` if you use a feed; ⭐ `Cache@2` keyed on `package-lock.json`; a `mongodb-memory-server`-free integration stage on a `vmImage` agent (it has Docker) |
| 🔨 **Jenkins** | ⭐⭐ **the hard one** — a Kubernetes pod agent has **no Docker daemon**, so Testcontainers needs a **mongod sidecar started with `--replSet rs0` and `rs.initiate()`**, or Testcontainers Cloud. Kaniko builds both images; the migration runs as a `kubectl` Job from the CD folder |

Full per-tool pipelines: [`../09-TOOL-MASTERY/`](../09-TOOL-MASTERY/).

---

## 13 · ▶️ Run it locally — the acceptance checks

```bash
# ── 0 · prerequisites ─────────────────────────────────────────────────
node --version        # ✅ v24.x      ⛔ v18 → the lockfile will not resolve
npm --version         # ✅ 11.x
docker --version      # ✅ 24+ with BuildKit
kubectl version --client
kind get clusters | grep -q cicd || kind create cluster --name cicd --wait 5m

# ── 1 · ⭐ ONE lockfile, ONE install ──────────────────────────────────
find . -name package-lock.json -not -path './node_modules/*' | wc -l   # ⭐ 1
npm ci
npm ls --workspaces --depth=0 | head

# ── 2 · ⭐⭐ the shared package builds FIRST and both apps see it ──────
npm run build -w @shop-mern/shared
npm run typecheck && echo "✅ tsc -b passes across all workspaces"

# ── 3 · ⭐⭐ prove the contract test actually fires ────────────────────
#    rename `quantity` → `qty` in packages/shared/src/api-types.ts ONLY
npm run typecheck
# ⛔ EXPECT: errors in BOTH apps/web and apps/api, naming the missing property
git checkout packages/shared/src/api-types.ts

# ── 4 · ⭐ integration tests use a REAL mongod, not the in-memory fake ─
grep -rn 'mongodb-memory-server' apps/ package.json | wc -l   # ⭐ 0
grep -rn '@testcontainers/mongodb' apps/api/tests | head -1    # ✅ present
npm run test -- --run apps/api/tests/integration
# ✅ expect a pulled `mongo:8.0` image and a replica-set connection string

# ── 5 · ⭐⭐ transactions work — i.e. it really is a replica set ───────
node -e '
  const m=require("mongoose");
  (async()=>{ await m.connect(process.env.MONGODB_URL,{autoIndex:false});
    const s=await m.startSession();
    await s.withTransaction(async()=>{ console.log("✅ transaction OK"); });
    await m.disconnect(); })().catch(e=>{console.error("⛔",e.message);process.exit(1)})'

# ── 6 · ⭐ autoIndex is OFF everywhere ────────────────────────────────
grep -rn 'autoIndex' apps/api/src/            # ✅ only `autoIndex: false`
grep -rn 'syncIndexes' apps/ migrations/      # ⭐ 0 — indexes come from migrations

# ── 7 · ⭐ the migration ledger works ─────────────────────────────────
docker run -d --name mern-mongo-dev -p 27017:27017 mongo:8.0 --replSet rs0 --bind_ip_all
sleep 6 && docker exec mern-mongo-dev mongosh --quiet --eval 'rs.initiate()'
sleep 4
export MONGODB_URL="mongodb://localhost:27017/shop_dev?replicaSet=rs0"
npx migrate-mongo status        # ⭐ shows each migration and whether applied
npx migrate-mongo up
npx migrate-mongo status        # ⭐ all "applied"
docker exec mern-mongo-dev mongosh --quiet shop_dev \
  --eval 'db.schema_migrations.find({},{_id:0,fileName:1,appliedAt:1}).toArray()'
# ✅ ⭐ THAT COLLECTION IS THE LEDGER. If it does not exist, you have no
#    idea what shape your data is in.

# ── 8 · ⭐⭐ migrations are idempotent — run them twice ────────────────
docker exec mern-mongo-dev mongosh --quiet shop_dev --eval 'db.schema_migrations.deleteMany({})'
npx migrate-mongo up && npx migrate-mongo up
# ✅ second run applies nothing and exits 0

# ── 9 · ⭐ the runtime-config discipline (no baked API URL) ───────────
docker compose -f docker-compose.ci.yml up -d --build --wait
docker compose -f docker-compose.ci.yml exec mern-web sh -c \
  'grep -rn "localhost:4000" /usr/share/nginx/html/assets/ | wc -l'   # ⭐ 0
curl -fsS http://localhost/config.js                                   # ✅ injected
MERN_API_URL=https://api.example.test docker compose -f docker-compose.ci.yml up -d mern-web
curl -fsS http://localhost/config.js | grep -q api.example.test && echo "✅ same image, new env"

# ── 10 · ⭐ cache headers ─────────────────────────────────────────────
curl -fsSI http://localhost/index.html   | grep -i cache-control   # ✅ no-cache
curl -fsSI http://localhost/assets/$(ls apps/web/dist/assets | head -1) | grep -i cache-control
# ✅ immutable
curl -fsSI http://localhost/config.js    | grep -i cache-control   # ✅ no-store

# ── 11 · ⭐ E2E against the BUILT IMAGES (§7.6) ───────────────────────
npx playwright test --project=chromium && echo "✅ E2E on images, not the dev server"

# ── 12 · deploy to kind and read back BOTH digests ────────────────────
kubectl apply -k k8s/overlays/dev
kubectl -n shop-dev rollout status deploy/mern-api --timeout=300s
kubectl -n shop-dev rollout status deploy/mern-web --timeout=300s
for s in mern-web mern-api; do
  printf '%-10s ' "$s"
  kubectl -n shop-dev get deploy $s \
    -o jsonpath="{.spec.template.spec.containers[?(@.name=='$s')].image}"; echo
done
kubectl -n shop-dev get statefulset mern-mongo \
  -o jsonpath='{.spec.template.spec.containers[?(@.name=="mongod")].image}'; echo
# ⭐ all three must be DIGESTS

# ── 13 · ⭐ the replica set is actually healthy ───────────────────────
kubectl -n shop-dev exec mern-mongo-0 -- mongosh --quiet \
  -u "$MONGO_USER" -p "$MONGO_PASS" --authenticationDatabase admin \
  --eval 'rs.status().members.map(m=>`${m.name} ${m.stateStr} lag=${m.optimeDate}`)'
# ✅ one PRIMARY, two SECONDARY
```

---

## 14 · Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| ⛔ `npm ci` fails: "no workspace configuration found" | not every workspace's `package.json` was copied into the build stage | §5.1 — copy all of them |
| `tsc -b` fails with "cannot find module @shop-mern/shared" | `shared` was not built first | ⭐ `npm run build -w @shop-mern/shared` before anything |
| ⛔ Both apps compile; production returns 400 | the type is hand-written in two places | ⭐⭐ §6.2 — one zod schema, `z.infer` |
| ⛔ `MongoServerError: Transaction numbers are only allowed on a replica set member or mongos` | a standalone mongod | §9.3 — `--replSet rs0`, even in dev |
| Transactions silently do nothing | code guarded by `if (session)` | ⭐ `REQUIRE_REPLICA_SET=true` + the check in `db.ts` |
| ⛔ Writes fail after a pod restart | the connection string is pinned to `mern-mongo-0` | §9.4 — list **all** members |
| A write disappears after a failover | `w:1` (acknowledged by a primary that stepped down) | ⭐ `w=majority` + `retryWrites=true` |
| ⛔ Writes block for 10 s during a rolling update | no `preStop`, endpoints removed asynchronously | §9.2 |
| The pod restart-loops when Mongo blips | `livenessProbe` points at `/readyz` | ⭐⭐ liveness = `/healthz` (never touches Mongo); readiness = `/readyz` |
| `/readyz` is UP but queries fail | readiness does not ping Mongo | §9.2 — a real `adminCommand({ping:1})` |
| ⛔ OOMKilled mongod | WiredTiger sized itself from the node's RAM, not the container limit | ⭐ `--wiredTigerCacheSizeGB` explicitly |
| OOMKilled Node during the build | the Vite/Node default heap | ⭐ `NODE_OPTIONS=--max-old-space-size=6144` |
| ⛔ Deploy takes 10 minutes and locks the collection | `autoIndex: true`, or `syncIndexes()` at boot | §8.4 — `autoIndex: false`, indexes via migration |
| An old index is still there after a rename | `createIndex` never drops | ⭐ an explicit `dropIndex` in a migration |
| Query plans changed mid-rollout | `syncIndexes()` on a rolling fleet | §8.4 rule 3 |
| ⛔ A migration ran twice and corrupted data | not idempotent, or `backoffLimit` > 0 | §8.3 rules 1 and 4 |
| `migrate-mongo` says applied, but the file changed | `useFileHash` off | ⭐ keep it on — an edited migration must fail |
| ⛔ CI is green, the image shows a blank page | Playwright ran against `npm run dev` | §7.6 — run it against the built images |
| Tests download a mongod binary at runtime | `mongodb-memory-server` | ⭐⭐ §7.2 — Testcontainers |
| Testcontainers fails on a Jenkins pod agent | no Docker daemon | §7.2 — a `--replSet rs0` sidecar, Cloud, or a VM agent |
| ⛔ The backup restored to zero documents | `mongodump` without `--archive`, or a namespace mismatch | §10.2 — `--gzip --archive --oplog`, and compare counts |
| A deploy rolled back but the data did not | ⛔ an image rollback is not a data rollback | ⭐ §10.2 — the backup is the only data rollback |
| The Mongo upgrade broke the app | two feature-compatibility versions jumped at once | §10.5 — one step at a time, secondaries first |

---

<a name="tasks--answers"></a>
## 15 · ⭐ TASKS — answers at the END

| # | Task |
|---|---|
| **T1** | Scaffold `shop-mern` as an npm-workspaces monorepo with a `packages/shared` contract package, and prove the contract test fires |
| **T2** | Replace `mongodb-memory-server` with `@testcontainers/mongodb` and prove transactions work |
| **T3** | Write both Dockerfiles, and explain the three flags that stop an OOMKill |
| **T4** | Give `mern-api` a correct `/healthz` + `/readyz` pair and wire the three probes |
| **T5** | Deploy MongoDB as a 3-member replica-set StatefulSet with an idempotent `rs.initiate()` Job |
| **T6** | Build the migration ledger with `migrate-mongo`, and prove idempotency |
| **T7** | Disable `autoIndex`, move index creation into a migration, and prove the index is used |
| **T8** | Implement the backup gate, including the restore verification and count comparison |
| **T9** | Run Playwright against the built images rather than the dev server |
| **T10** | Decide the Case 1 / Case 2 verdict per tier and justify each |
| **T11** | ⭐⭐ During a rolling update of `mern-api`, some orders are created with `quantity` and some with `qty`, and the web UI shows `undefined` for roughly 40 seconds. Explain every mechanism involved, the immediate fix, and the permanent one |

---

# ✅ ANSWERS

**T1.** §3 and §6. Root `package.json` with `"workspaces": ["packages/*", "apps/*"]`, `engines.node: 24`, a `.nvmrc` containing `24`, and `tsconfig.base.json` with `strict: true` plus `paths` mapping `@shop-mern/shared` → `packages/shared/src`. Create `packages/shared` exporting ⭐ **one zod schema per DTO and `z.infer` for its type** — never a hand-written interface alongside it, because two declarations drift and one cannot. Export the route table too, so a path change is one edit. Then `apps/api` does `const body: OrderOutput = {...}` on the response and `apps/web` does `OrderOutput.parse(await r.json())`. **Proving the contract test fires (§13 step 3):** rename `quantity` → `qty` in `packages/shared/src/api-types.ts` **only**, run `npm run typecheck` (`tsc -b`), and confirm ⛔ errors appear in **both** `apps/web` and `apps/api`, each naming the missing property. Revert. ⭐ **Why this is the answer to shape C's `openapi-diff`:** in shape C the contract crosses a language boundary, so you need a spec, a generator and a drift gate. In MERN the contract is inside one type system, so `tsc -b` *is* the gate — cheaper, faster and exact. **And the two things that silently void it:** forgetting `npm run build -w @shop-mern/shared` first (both apps then compile against a stale `.d.ts` and errors are confusing rather than absent), and letting either app declare its own local interface "just for now" — which is exactly §6.1 and reproduces the shape-C failure inside a single-language repo.

**T2.** §7.2. Remove `mongodb-memory-server` from `apps/api` and add `@testcontainers/mongodb`; in `tests/integration/setup.ts`, `await new MongoDBContainer('mongo:8.0').start()` and `mongoose.connect(container.getConnectionString(), { autoIndex: false })`, with a `teardown()` that disconnects and stops. **Proving transactions work (§13 step 5):** `startSession()` then `session.withTransaction(async () => …)` — against a standalone mongod this throws `MongoServerError: Transaction numbers are only allowed on a replica set member or mongos`; against Testcontainers' MongoDB module it succeeds, ⭐ because that module starts a **single-node replica set**, which is precisely what Mongoose requires. **Why `mongodb-memory-server` is disqualified for CI, in four parts:** it **downloads a mongod binary at first run**, so your build is not hermetic and a MongoDB CDN outage fails it; the downloaded version is whatever it resolves to, **not the 8.0 you deploy**; it runs **standalone**, so transactions silently do not work (and code guarded by `if (session)` silently skips them); and it uses an ephemeral storage engine, so there is no real WAL, no real index build and no replica-set behaviour. ⭐ That makes it the JavaScript equivalent of H2-for-Postgres: a test double that passes confidently and tells you nothing. **Also set `autoIndex: false` in tests**, or Mongoose creates indexes behind your back and your tests stop exercising the migration path that production actually uses.

**T3.** §5. **`apps/api`** — three stages: `deps` (copy **every** workspace's `package.json` first, then `npm ci --workspace=… --omit=dev` with a `--mount=type=cache,target=/root/.npm`), `build` (full `npm ci`, copy `tsconfig.base.json` + `packages/shared` + `apps/api`, then build **shared before api**), `runtime` (`node:24-alpine`, a non-root `app` user, copy only `node_modules` and the two `dist` trees plus `package.json`s, `HEALTHCHECK`, `CMD ["node","apps/api/dist/server.js"]`). **`apps/web`** — the same workspace-aware build, then `nginx:1.29-alpine` with `nginx.conf`, ⭐ `docker-entrypoint.d/40-inject-config.sh` and the built `dist` — runtime config, not a baked `VITE_API_URL`. **The three flags that stop an OOMKill:** ⭐ **(1) `NODE_OPTIONS=--max-old-space-size=512` in the api runtime** — Node has read cgroup limits since v14, but an explicit heap ceiling stops the heap growing *into* the container limit, which produces an OOMKill with **no JavaScript error at all**, only `Last State: Terminated, Reason: OOMKilled`. ⭐ **(2) `NODE_OPTIONS=--max-old-space-size=6144` during `vite build`** — bundling a React app exceeds Node's default heap and dies with `FATAL ERROR: Reached heap limit Allocation failed`, which looks like a code bug. ⭐ **(3) `--omit=dev` in the deps stage** — not a memory flag but the same class of fix: ~300 MB of test tooling that is pure attack surface in a runtime image. **Two details people miss:** `npm ci` in a workspace monorepo ⛔ fails with "no workspace configuration found" unless *every* workspace's `package.json` is present, so all of them must be copied before the install; and MongoDB gets the analogous flag from §5.3/§9.3 — `--wiredTigerCacheSizeGB`, because WiredTiger sizes its cache from what it believes is available and will exceed a container limit.

**T4.** §9.2. **`/healthz` (liveness)** returns 200 from the process alone and ⛔ **must not touch MongoDB** — if it did, a Mongo blip would fail liveness on every pod simultaneously and Kubernetes would restart-loop your entire fleet, converting a partial outage into a total one. **`/readyz` (readiness)** must do real work: assert `mongoose.connection.readyState === 1`, issue `db.adminCommand({ ping: 1 })` (a genuine round-trip, not a cached connection object), and — when `REQUIRE_REPLICA_SET=true` — check `db.adminCommand({ hello: 1 }).setName` exists, returning 503 with a `reason` otherwise. Wire **`startupProbe`** on `/healthz` (`failureThreshold: 15, periodSeconds: 2`) so the mongo connection has time to establish without liveness firing; **`readinessProbe`** on `/readyz` (`periodSeconds: 10, failureThreshold: 3`) to gate traffic; **`livenessProbe`** on `/healthz` (`periodSeconds: 20, failureThreshold: 3`) to restart a stuck event loop. Add `preStop: sleep 8` and `terminationGracePeriodSeconds: 45`, plus `maxUnavailable: 0`. ⭐ **The distinction to state:** readiness answers *"can I serve a real request?"* and must include the database; liveness answers *"is the process able to respond at all?"* and must include as little as possible. Conflating them is the single most common backend probe bug, and in MERN it is worse than usual because the dependency being probed is a stateful database whose brief unavailability is normal during an election.

**T5.** §9.3. A `StatefulSet` named `mern-mongo` with `serviceName: mern-mongo` (a **headless** Service, `clusterIP: None`, so each pod gets stable DNS), `replicas: 3`, the official `mongo@sha256:…` image **pinned by digest**, args `--replSet=rs0 --bind_ip_all --wiredTigerCacheSizeGB=1.5`, `securityContext.fsGroup: 999` (mongod's uid/gid in the official image), `terminationGracePeriodSeconds: 120`, a `readinessProbe` running `mongosh --eval 'db.hello().ok'` and a tolerant `livenessProbe` (`pgrep -x mongod`, `failureThreshold: 6` — restarting mongod is expensive), and `volumeClaimTemplates` for both `/data/db` and `/data/configdb` so ⭐ each pod keeps its own PVC across restarts. Then a **Job** that waits for `mern-mongo-0` to answer a ping and runs `rs.initiate({...})` with the three member hostnames, treating `AlreadyInitialized` as **success** — ⭐ that idempotence is what makes `backoffLimit: 2` safe here, unlike the migration Job where `backoffLimit: 0` is mandatory. In Argo CD, annotate it `hook: PostSync` so it runs after the StatefulSet exists. **Why a replica set even in dev:** `session.withTransaction()` requires one, and against a standalone mongod it throws — or, worse, code guarded by `if (session)` silently skips the transaction so your "atomic" order creation is not atomic and you discover it during an incident. A single-member replica set costs nothing and removes the class of bug entirely. **And the connection string (§9.4)** must list **all three** members with `replicaSet=rs0&retryWrites=true&w=majority` — pinning to `-0` breaks the first time that pod is not primary, and `w:1` means a write acknowledged by a primary that then steps down is **lost**.

**T6.** §8. **The ledger:** `migrate-mongo-config.js` with `mongodb.url` from `MONGODB_URL`, `replicaSet` from the environment, `changelogCollectionName: 'schema_migrations'` and ⭐ `useFileHash: true`. Each migration in `migrations/<timestamp>-<slug>.js` exports `up(db)` and `down(db)`. **Proving idempotency (§13 step 8):** clear `schema_migrations`, run `npx migrate-mongo up` twice, and confirm the second run applies nothing and exits 0. **The five rules, and why each exists:** ⭐ **(1) idempotent** — a Job retry, a partial failure or a human re-running must not corrupt data, and `backoffLimit: 0` does not protect you from the *first* attempt having half-applied; **(2) batched** — one unbounded `updateMany` over a million documents holds locks, grows the oplog and lags the secondaries, so loop with a bounded batch, a small sleep, and a runaway guard; **(3) a real `down`** — while noting that in MongoDB `down` is often **lossy**, because `$unset` of a backfilled field discards values the legacy field never had, unlike a SQL `DROP COLUMN`; ⭐ **(4) `backoffLimit: 0`** in the Job, because a failed *data* migration needs a human, not a second attempt; **(5) never edit an applied migration** — `useFileHash: true` turns that into a hard failure, so keep it on. **And the thing that makes MERN different from Flyway (§8.1):** Mongoose schemas are application-level. They validate on the way in *through the app*, and they do not alter stored data, do not record what ran, and do not stop an old document existing. ⛔ **There is no `flyway_schema_history` unless you build one** — so `db.schema_migrations` is not a nicety, it is the only record you have of what shape production data is in.

**T7.** §8.4. Set `autoIndex: false` **and** `autoCreate: false` in `apps/api/src/db.ts` (in code, not by environment variable, so it cannot be turned on by accident), and never call `Model.syncIndexes()`. Create indexes in a migration instead: `db.collection('orders').createIndex({ status: 1, createdAt: -1 }, { name: 'idx_status_created' })`, and ⭐ **prove the index is used in the same migration** by running `.find({status:'PAID'}).sort({createdAt:-1}).limit(1).explain('queryPlanner')` and asserting the plan mentions `idx_status_created` — throwing if it does not. **Why `autoIndex` is dangerous, in four escalating steps:** `createIndex` on a large collection is expensive and, during a rolling update, runs **on every new pod simultaneously**; renaming an index in the schema creates the new one but ⛔ never drops the old, so indexes accumulate and slow every write; ⛔⛔ `syncIndexes()` **drops** indexes absent from the schema, so on a 3-replica rolling fleet an old pod can re-create what a new pod just dropped and query plans change mid-rollout; and a *missing* index in production turns a query into a collection scan, so the database falls over under normal load minutes after a "successful" deploy. **Proving it in CI (§13 step 6):** `grep -rn 'autoIndex' apps/api/src/` shows only `false`, and `grep -rn 'syncIndexes' apps/ migrations/` returns nothing. **One extra:** time the index build in **staging** first — an index that takes four minutes on production's data volume will exceed your Job timeout, and discovering that during the production deploy is the expensive way to learn it.

**T8.** §10.2. Four steps, and the last three are the ones that matter. **(1) Take it** with `mongodump --uri="$MONGODB_URL" --gzip --archive --oplog` — ⭐ `--oplog` is what makes the dump a consistent **point-in-time** snapshot of a *live* database; without it, a write landing mid-dump produces a torn backup that restores to a state that never existed. **(2) Restore it** into a **throwaway** database (`--nsInclude "shop_verify.*"`) — ⭐⭐ this is the whole point, because `mongodump` exits 0 on a dump nobody can read, and **a backup you have never restored is a hypothesis**. **(3) Compare document counts** per collection between source and restored — this catches the empty-file, wrong-namespace and partial-restore cases that a successful `mongorestore` exit code does not. **(4) Record it** (`timestamp`, size, `verified=true`) in the deploy audit log, so "was there a verified backup before this deploy?" is answerable during an incident rather than reconstructable. **Where it belongs:** ⭐ *inside* the CD pipeline, before the migration Job — which makes MERN the only shape in this folder where backup verification is a **pipeline gate** rather than an ops procedure, because here the data tier ships with the application. **And the consequence for rollback (§14, last rows):** an image rollback is **not** a data rollback. If the migration wrote bad data, `kubectl set image` to the previous digest restores the code and leaves the corruption in place; the only data rollback is `mongorestore` from the verified backup, which is a decision a human must make — and is the deepest reason `mern-api` stays 🔒 Case 1 until the migration discipline is proven.

**T9.** §7.6. Build both images, `docker compose -f docker-compose.ci.yml up -d --wait`, assert `curl -fsS http://localhost/config.js | grep -q apiUrl` (⭐ proving the entrypoint injected runtime config), run `npx playwright test --project=chromium`, capture `docker compose logs` on failure, then `down -v`. **Why the dev-server version is worthless:** `npm run dev` serves unbundled ESM with Vite's own environment handling, a permissive host/CORS configuration and **no** `config.js`, no CSP and no cache headers. The production image serves a bundled SPA from nginx with all of those. ⛔ **They are different programs**, so a green dev-server E2E run tells you nothing about the artifact you are about to deploy — and the classic symptom is exactly §14's "CI is green, the image shows a blank page", usually a missing `config.js` (the SPA reads `window.__APP_CONFIG__`, gets `undefined`, and renders nothing) or a CSP that blocks the inline config script. **Two supporting gates from the same idea (§13 steps 9–10):** grep the built bundle for a hardcoded API host (must be **0**, proving no build-time `VITE_API_URL`), and assert `index.html` is `no-cache`, hashed assets are `immutable`, and `config.js` is `no-store` — because a cached `index.html` is what turns a 90-second deploy into hours of stale clients.

**T10.** §11. **`mern-web` → 🤖 Case 2.** P1 ✅ static files roll back instantly; P2 ✅ vitest + Lighthouse + Playwright-on-images; P3 ⚠️ **needs RUM**, because a server-side 200 says nothing about whether the bundle executed; P4 ✅ digest; P5 ✅ n/a. Same verdict and same prerequisite as `shop-ui`. **`mern-api` → 🔒 Case 1.** P1 ✅ the image, but P5 ⛔ — and MERN's P5 is *harder* than Java's, because MongoDB does not enforce the schema, so a bad migration is not rejected by the database on the way in. P2 is strong (real-mongod ITs + E2E), P3 ✅ (`/readyz` plus RED metrics), P4 ✅. **⭐ The extra prerequisite MERN adds:** integration tests must prove the app **tolerates documents in the old shape**, because during a rolling update two versions write to the same collection simultaneously and there is no database-level constraint stopping either — a SQL database would reject the invalid row, MongoDB serves it to your new code. **`mern-mongo` → 🔒🔒 Case 1, always, and separately.** P1 ⛔ the only rollback is a verified restore; upgrades are one-way (feature compatibility version); and the data *is* the migration. ⭐ **The structural decision that follows:** `mern-mongo`'s image reference must live in its **own** manifest with its own approval, never in the release manifest shared with `mern-api` and `mern-web` — otherwise an ordinary app deploy can move the database, which is the one thing §10.5's ten-step sequence exists to prevent.

**T11.** ⭐⭐ **Every mechanism involved, in order.** A rolling update runs **two versions of `mern-api` simultaneously** — old pods terminating, new pods starting, both connected to the same MongoDB, both writing to `orders`. The old code writes `{ qty }`; the new code writes `{ quantity }`. ⭐⭐ **MongoDB accepts both, because the schema lives in Mongoose, in the application, not in the database** (§2's defining hazard): there is no column, no constraint and no rejection — a document is whatever the writer said it was. Meanwhile the browser holds **yesterday's bundle** (or, for ~40 s, the new bundle served against pods that are still old), which reads `order.quantity`; for documents written by the old pod that property is absent, so it renders `undefined`. The 40-second duration is the rollout window (`maxUnavailable: 0, maxSurge: 1` across 3 replicas, plus readiness delays), and the *hours*-long tail would be the browser cache — which is why `index.html` must be `no-cache`. **Immediate fix (minutes):** serve the old field. Make the reader tolerant — `const quantity = order.quantity ?? order.qty ?? 0` in `packages/shared` (one place, both tiers get it) — and re-deploy; then **backfill** the documents written during the window with a batched, idempotent migration (§8.2's pattern), verifying the count of `qty`-only documents reaches zero. ⛔ Do **not** roll back the image: that stops new `quantity` documents but leaves the mixed data in place, and the rollback is not a data rollback (§10.2). **Permanent fix — expand/contract, three releases (§06 of scenario 3 §3):** **(1)** the API accepts **both** `qty` and `quantity` on input and emits **both** on output, with the shared zod schema declaring both (`quantity` required, `qty` optional-deprecated) — safe, and revertible because nothing consumes the new field yet; **(2)** the web app switches to reading and sending `quantity`, while the API still emits `qty`, so a cached old bundle keeps working; **(3)** later, and only after telemetry shows zero `qty` traffic, the API stops emitting it and a migration `$unset`s the legacy field. **⭐ Plus the three gates that would have caught it:** `CONTRACT_VERSION` with the startup `serves` check (§6.4), so a mismatched pair shows a *refresh banner* instead of `undefined`; the API response validated with `OrderOutput.parse` (§6.2), so an unexpected shape throws a **caught, logged** error rather than rendering `undefined`; and ⭐ the integration test that writes a document in the **old** shape and asserts the **new** code reads it correctly — the MERN-specific prerequisite from T10, which exists precisely because the database will not do this for you. **The meta-lesson:** in a SQL stack this incident is a `NOT NULL` violation that fails the deploy. In MERN it is silent mixed data plus `undefined` in the UI — *the same design decision that makes MERN fast to build makes it unforgiving to deploy*, and the compensation is discipline in the shared package, the migration ledger and the contract version, not a constraint you can add later.

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish_Kumar_Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn: https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260
🔗 GitHub: https://github.com/3558Bhk

*MongoDB is schemaless. That is a deployment hazard, not a feature — during a rolling update, two versions of your app are writing to the same collection and nothing will stop either of them.*

</div>
