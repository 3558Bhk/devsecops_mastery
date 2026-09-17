# PROJECT 8 · ⚛️ React (Vite) Frontend

> **Part of the Docker Learning Path.** Previous: [`10-PROJECT-7-compose-stack.md`](10-PROJECT-7-compose-stack.md) — Project 7 — Compose Stack.
>
> 🎯 **Instructions & techniques:** `FROM`, `COPY`, `RUN`, `ARG`, `ENV`, `USER`, `EXPOSE`, `HEALTHCHECK` · multi-stage · nginx · `.dockerignore`
>
> 📚 **What you learn:** Building JavaScript inside a container, serving static files with nginx, SPA routing, build-time vs run-time env vars
>
> 🔁 **Every project here is written TWICE:**
> - **🔵 CASE 1 — a SIMPLE Dockerfile.** Easy to read, easy to get working, usually too big for production.
> - **🟢 CASE 2 — a MULTI-STAGE Dockerfile.** The production version: smaller, faster to rebuild, more secure, tests can fail the build.
>
> **Build Case 1 first**, run it, understand it — then build Case 2 and **measure the difference**. That comparison *is* the lesson.

---

# D.1 — PROJECT 8 · ⚛️ React Frontend

**🎯 What you learn:** building JavaScript inside a container, `npm ci` vs `npm install`, why `node_modules` must never be copied, serving static files with nginx, SPA routing, env vars at **build** time vs run time.

## 8.0 The app

```
08-react-frontend/
├── package.json
├── vite.config.js
├── index.html
├── .dockerignore
├── nginx.conf              ← Case 2 only
├── Dockerfile              ← CASE 1 (simple)
├── Dockerfile.multistage   ← CASE 2
├── docker-compose.yml
└── src/
    ├── main.jsx
    ├── App.jsx
    ├── api.js
    └── styles.css
```

### `package.json`

```json
{
  "name": "react-docker-learn",
  "private": true,
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview --host 0.0.0.0 --port 4173",
    "test": "vitest run"
  },
  "dependencies": {
    "react": "18.3.1",
    "react-dom": "18.3.1"
  },
  "devDependencies": {
    "@vitejs/plugin-react": "4.3.4",
    "vite": "6.0.7",
    "vitest": "2.1.8"
  }
}
```

### `vite.config.js`

```js
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: {
    host: '0.0.0.0',      // ← MANDATORY inside a container, else it binds to 127.0.0.1 only
    port: 5173,
    watch: { usePolling: true },   // file-change detection through the Docker volume layer
    proxy: {
      // dev only: forward /api to the backend so the browser sees ONE origin (no CORS)
      '/api': { target: process.env.VITE_PROXY_TARGET || 'http://localhost:8080', changeOrigin: true },
    },
  },
  build: { outDir: 'dist', sourcemap: false },
})
```

### `index.html`

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>React + Docker</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.jsx"></script>
  </body>
</html>
```

### `src/main.jsx`

```jsx
import React from 'react'
import { createRoot } from 'react-dom/client'
import App from './App.jsx'
import './styles.css'

createRoot(document.getElementById('root')).render(<React.StrictMode><App /></React.StrictMode>)
```

### `src/api.js`

```js
// Base URL comes from a BUILD-TIME env var (Vite inlines import.meta.env at build time).
// This is the single most misunderstood thing about frontend containers — see the note below.
const BASE = import.meta.env.VITE_API_URL || '/api'

export async function getTasks() {
  const res = await fetch(`${BASE}/tasks`)
  if (!res.ok) throw new Error(`API ${res.status}`)
  const data = await res.json()
  return data.tasks ?? data
}

export async function createTask(title, priority = 'medium') {
  const res = await fetch(`${BASE}/tasks`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ title, priority }),
  })
  if (!res.ok) throw new Error(`API ${res.status}`)
  return res.json()
}

export async function toggleTask(id) {
  const res = await fetch(`${BASE}/tasks/${id}/toggle`, { method: 'POST' })
  if (!res.ok) throw new Error(`API ${res.status}`)
  return res.json()
}

export async function getInfo() {
  try {
    const res = await fetch(`${BASE}/info`)
    return res.ok ? res.json() : null
  } catch { return null }
}
```

### `src/App.jsx`

```jsx
import { useEffect, useState } from 'react'
import { createTask, getInfo, getTasks, toggleTask } from './api.js'

export default function App() {
  const [tasks, setTasks] = useState([])
  const [info, setInfo] = useState(null)
  const [title, setTitle] = useState('')
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(true)

  const load = async () => {
    setLoading(true); setError('')
    try { setTasks(await getTasks()) }
    catch (e) { setError(`Cannot reach the API: ${e.message}`); setTasks([]) }
    finally { setLoading(false) }
  }

  useEffect(() => { load(); getInfo().then(setInfo) }, [])

  const add = async (e) => {
    e.preventDefault()
    if (!title.trim()) return
    try { await createTask(title.trim()); setTitle(''); await load() }
    catch (err) { setError(err.message) }
  }

  return (
    <main>
      <h1>⚛️ React in Docker</h1>
      <p className="sub">
        Built with Vite, served by <b>{info?.server ?? 'a container'}</b>
        {info?.version && <> · API v{info.version}</>}
      </p>

      <form onSubmit={add}>
        <input value={title} onChange={e => setTitle(e.target.value)}
               placeholder="Add a task…" autoFocus />
        <button type="submit">Add</button>
        <button type="button" onClick={load}>↻</button>
      </form>

      {error && <p className="err">⚠️ {error}</p>}
      {loading && <p>Loading…</p>}

      <ul>
        {tasks.map(t => (
          <li key={t.id} className={t.done ? 'done' : ''}>
            <input type="checkbox" checked={!!t.done}
                   onChange={() => toggleTask(t.id).then(load)} />
            <span className={`pri ${t.priority}`}>{t.priority}</span>
            <span>{t.title}</span>
          </li>
        ))}
        {!loading && tasks.length === 0 && <li><i>nothing here</i></li>}
      </ul>
    </main>
  )
}
```

### `src/styles.css`

```css
:root { color-scheme: light dark; --acc:#61dafb; --bg:rgba(127,127,127,.1) }
* { box-sizing: border-box }
body { margin:0; font-family: system-ui,-apple-system,"Segoe UI",Roboto,sans-serif }
main { max-width: 720px; margin: 2.5rem auto; padding: 0 1.25rem; line-height:1.6 }
h1 { color: var(--acc) }
.sub { opacity:.7; margin-top:-.6rem }
form { display:flex; gap:.5rem; margin:1.2rem 0 }
input, button { padding:.55rem .8rem; border-radius:8px; border:1px solid rgba(127,127,127,.4);
                background:transparent; color:inherit; font:inherit }
input[type=text], form input:first-of-type { flex:1 }
button { background:var(--acc); color:#08242e; border:none; cursor:pointer; font-weight:600 }
button:hover { filter:brightness(1.1) }
ul { list-style:none; padding:0 }
li { display:flex; align-items:center; gap:.6rem; padding:.45rem 0; border-bottom:1px solid var(--bg) }
li.done span:last-of-type { text-decoration:line-through; opacity:.5 }
.pri { font-size:.68rem; text-transform:uppercase; padding:.15rem .5rem; border-radius:999px; background:var(--bg) }
.pri.high { background:#e5484d33; color:#e5484d }
.pri.medium { background:#f5a52433; color:#c47f0a }
.pri.low { background:#30a46c33; color:#30a46c }
.err { background:#e5484d22; color:#e5484d; padding:.6rem .9rem; border-radius:8px }
```

### `.dockerignore` ← **the most important file in this project**

```gitignore
# 👇 WITHOUT this line the build breaks or ships your host's node_modules into Linux
node_modules
**/node_modules
npm-debug.log*
yarn-error.log*

dist
build
.git
.gitignore
.env
.env.*
*.local
.DS_Store
.vscode
.idea
coverage
Dockerfile*
docker-compose*.yml
.dockerignore
README.md
```

> 💥 **The #1 React+Docker error:** copying a Windows/macOS `node_modules` into a Linux image. Native modules (`esbuild`, `rollup`, `sharp`) are platform-specific binaries — they explode with `Error: Cannot find module @rollup/rollup-linux-x64-gnu`. `.dockerignore` prevents it entirely.

---

## 🔵 CASE 1 — the SIMPLE Dockerfile (dev server)

### `Dockerfile`

```dockerfile
# ────────────────────────────────────────────────────────────
# CASE 1: SIMPLE. One stage. Runs the Vite DEV SERVER.
# Great for local development with hot reload. NOT for production.
# ────────────────────────────────────────────────────────────
FROM node:22-alpine

WORKDIR /app

# 1) copy ONLY the manifests first → this layer stays cached
COPY package.json package-lock.json* ./

# 2) install dependencies
#    (npm ci needs package-lock.json; fall back to npm install without it)
RUN if [ -f package-lock.json ]; then npm ci; else npm install; fi

# 3) copy the rest of the source
COPY . .

EXPOSE 5173

# exec form: node becomes PID 1 and receives SIGTERM
CMD ["npm", "run", "dev"]
```

### Build & run

```bash
cd 08-react-frontend
npm install                       # creates package-lock.json on your host first time
docker build -t react-simple:v1 .
docker run -d --name react-simple -p 5173:5173 react-simple:v1
docker logs -f react-simple       # → VITE ready in xxx ms  ➜  http://localhost:5173/
```

🌐 **http://localhost:5173**

```bash
docker images react-simple:v1     # ~230 MB  😬
docker exec -it react-simple sh
  ls node_modules | wc -l         # hundreds of packages INSIDE the image
  du -sh /app/node_modules        # ~180 MB of the image is node_modules
  exit
```

### Hot reload with a bind mount

```bash
docker rm -f react-simple
docker run -d --name react-dev -p 5173:5173 \
  -v "$(pwd)/src:/app/src" \
  -v "$(pwd)/index.html:/app/index.html" \
  react-simple:v1
# edit src/App.jsx → the browser updates instantly, no rebuild
docker logs -f react-dev
```

> ⚠️ Mount only `src/` — **never** mount `node_modules` from your host over the container's copy. That's what breaks the native binaries.

### Why Case 1 is not production-ready

| Problem | Detail |
|---|---|
| ~230 MB | Node runtime + 800 dev packages ship to production |
| Dev server | Vite's dev server is unoptimised, unbundled, and not built for traffic |
| Huge attack surface | npm, a shell, a compiler, every transitive dev dependency |
| No tests gate | Broken code produces a working image |

---

## 🟢 CASE 2 — the MULTI-STAGE Dockerfile (nginx, production)

### `nginx.conf`

```nginx
server {
    listen       8080;                 # >1024 so the non-root 'nginx' user can bind
    server_name  _;
    root         /usr/share/nginx/html;
    index        index.html;

    server_tokens off;

    gzip on;
    gzip_comp_level 6;
    gzip_min_length 512;
    gzip_vary on;
    gzip_types text/css application/javascript application/json image/svg+xml;

    add_header X-Content-Type-Options nosniff always;
    add_header X-Frame-Options        DENY    always;
    add_header Referrer-Policy        no-referrer always;

    # hashed build assets are immutable → cache them hard
    location /assets/ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        try_files $uri =404;
    }

    # 🔑 THE SPA RULE: any unknown path falls back to index.html
    # without this, refreshing /tasks/7 gives a 404 from nginx
    location / {
        try_files $uri $uri/ /index.html;
    }

    # reverse-proxy the API → the browser only ever talks to ONE origin (no CORS)
    location /api/ {
        proxy_pass       http://api:8000/;      # "api" = compose service name
        proxy_http_version 1.1;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 3s;
        proxy_read_timeout    15s;
        proxy_next_upstream error timeout http_502 http_503;
    }

    location = /healthz { access_log off; return 200 "ok\n"; add_header Content-Type text/plain; }
    error_page 404 /index.html;
}
```

### `Dockerfile.multistage`

```dockerfile
# syntax=docker/dockerfile:1
# ────────────────────────────────────────────────────────────
# CASE 2: MULTI-STAGE. Build with Node, ship with nginx.
# ────────────────────────────────────────────────────────────

ARG NODE_IMAGE=node:22-alpine
ARG NGINX_IMAGE=nginx:1.29-alpine

# ══════════════ STAGE 1: dependencies ══════════════
# Its own stage so `npm ci` is cached until package*.json changes.
FROM ${NODE_IMAGE} AS deps
WORKDIR /app
COPY package.json package-lock.json* ./
RUN --mount=type=cache,target=/root/.npm \
    if [ -f package-lock.json ]; then npm ci; else npm install; fi

# ══════════════ STAGE 2: test ══════════════
FROM deps AS test
COPY . .
# Uncomment once you have tests; a failure here ABORTS the build.
# RUN npm test

# ══════════════ STAGE 3: build ══════════════
FROM deps AS build
WORKDIR /app
COPY . .

# 🔑 Vite inlines these at BUILD time — they become literal strings in the JS bundle.
ARG VITE_API_URL=/api
ARG VITE_APP_VERSION=1.0.0
ENV VITE_API_URL=${VITE_API_URL} \
    VITE_APP_VERSION=${VITE_APP_VERSION}

RUN npm run build
# → /app/dist contains ONLY static html/css/js. Node is no longer needed.

# ══════════════ STAGE 4: runtime ══════════════
FROM ${NGINX_IMAGE} AS runtime

ARG APP_VERSION=1.0.0
LABEL org.opencontainers.image.title="react-frontend" \
      org.opencontainers.image.version="${APP_VERSION}"

RUN rm -f /etc/nginx/conf.d/default.conf
COPY nginx.conf /etc/nginx/conf.d/app.conf

# copy ONLY the build output from the build stage — 1.4 GB of node_modules stays behind
COPY --from=build /app/dist /usr/share/nginx/html

# run as the unprivileged nginx user that the base image already provides
RUN chown -R nginx:nginx /usr/share/nginx/html \
 && chown -R nginx:nginx /var/cache/nginx \
 && touch /var/run/nginx.pid && chown nginx:nginx /var/run/nginx.pid
USER nginx

EXPOSE 8080
STOPSIGNAL SIGQUIT

HEALTHCHECK --interval=20s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -q --spider http://127.0.0.1:8080/healthz || exit 1

CMD ["nginx", "-g", "daemon off;"]
```

### Build, compare, run

```bash
docker build -f Dockerfile.multistage \
  --build-arg APP_VERSION=1.0.0 \
  --build-arg VITE_API_URL=/api \
  -t react-multi:v1 .

# ── THE PAYOFF ──
docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" | grep -E 'react-(simple|multi)'
#   react-simple   v1   ~230 MB
#   react-multi    v1   ~52 MB        ← ~4.5× smaller

docker run -d --name react-prod -p 8080:8080 react-multi:v1
curl -sI http://localhost:8080/healthz
curl -s  http://localhost:8080/ | head -5
docker exec react-prod sh -c 'ls /usr/share/nginx/html; which node npm 2>&1'
# → index.html  assets/  ...   and: node/npm NOT FOUND ✅
docker rm -f react-prod
```

### Build intermediate stages (debugging superpower)

```bash
docker build -f Dockerfile.multistage --target deps  -t react:deps  .
docker build -f Dockerfile.multistage --target build -t react:build .
docker run --rm -it react:build sh
  ls dist/                 # the built output
  npm test                 # run tests interactively
  du -sh node_modules dist # see what got thrown away
```

---

## ⚠️ The React env-var trap (read this twice)

Frontend frameworks **inline** `import.meta.env.VITE_*` / `process.env.REACT_APP_*` **at build time**. They do **not** exist at runtime — there is no Node process, just static files in nginx.

```bash
# ❌ DOES NOTHING. The bundle was frozen at build time.
docker run -e VITE_API_URL=https://prod.example.com/api react-multi:v1

# ✅ Correct: one build per environment
docker build --build-arg VITE_API_URL=https://prod.example.com/api -t react:prod .
docker build --build-arg VITE_API_URL=https://dev.example.com/api  -t react:dev  .

# ✅ BETTER: build once, use a RELATIVE path, let nginx proxy per environment
docker build --build-arg VITE_API_URL=/api -t react:1.0 .
#   dev    → nginx proxies /api → localhost backend
#   prod   → nginx proxies /api → the prod backend
#   SAME IMAGE everywhere. This is the professional answer.

# ✅ ALSO GOOD: runtime config injection at container start
#   web/site/config.js  →  window.__APP_CONFIG__ = { apiUrl: "/api" };
#   and an entrypoint.sh that rewrites it from env vars before nginx starts.
```

---

## 🔨 Tasks for Project 8

> **8.1** Build both cases and record the exact sizes. Then run `docker history react-simple:v1 --human` and find which single layer is the biggest. What is it, and how does Case 2 eliminate it?

> **8.2** Prove the SPA routing rule. In Case 2, delete the `try_files $uri $uri/ /index.html;` line (use `=404` instead), rebuild, then load `/`, click to a deep route, and **refresh the page**. What breaks? Restore the line and confirm it works.

> **8.3** Add a real test stage. Install `vitest`, write `src/App.test.jsx` that asserts the heading renders, uncomment `RUN npm test` in the `test` stage, and build. Then deliberately break the test and confirm **the build fails and no image is produced**.

> **8.4** Measure the cache. Run `time docker build -f Dockerfile.multistage -t x .` twice. Then change one character in `src/App.jsx` and rebuild — which stages say `CACHED`? Now change one character in `package.json` and rebuild — what happens? Write down the rule.

> **8.5** Make it truly unprivileged and read-only:
> ```bash
> docker run -d --name locked -p 8080:8080 --read-only \
>   --tmpfs /var/cache/nginx --tmpfs /var/run --tmpfs /tmp \
>   --cap-drop ALL --security-opt no-new-privileges:true \
>   --user 101:101 react-multi:v1
> curl -sI localhost:8080/healthz
> docker exec locked touch /usr/share/nginx/html/x    # must fail
> ```
> Explain why `listen 80` would break under `--cap-drop ALL`, and what capability you'd have to add back.

<details>
<summary>👉 Answers</summary>

**8.1** The biggest layer in Case 1 is `RUN npm ci` (~180 MB) — the entire dependency tree, dev packages included. Case 2 never ships it: the `runtime` stage copies **only `/app/dist`** from the build stage, so Node, npm and all 800 packages are discarded with the intermediate stages.

**8.2** Without the SPA fallback, `nginx` looks for a real file at `/tasks/7`, doesn't find one and returns **404**. Client-side routing only works because the browser fetched `index.html` first; a hard refresh asks nginx directly. `try_files $uri $uri/ /index.html` says "serve the file if it exists, otherwise serve the app and let React Router handle it".

**8.3** The point: a `RUN` that exits non-zero **aborts the build**, so `docker images` shows no new tag. Broken code can never be pushed. This is the cheapest CI gate you will ever add.

**8.4** Editing `src/App.jsx` → `deps` is `CACHED` (package.json unchanged), `build` re-runs. ~5 seconds. Editing `package.json` → `deps` re-runs `npm ci` (~40 s) and everything below it. **Rule: a cache hit stops at the first changed instruction; copy the dependency manifest before the source.**

**8.5** It works because nginx listens on **8080**. Binding to port 80 (or any port < 1024) requires `CAP_NET_BIND_SERVICE`, which `--cap-drop ALL` removes → nginx fails with `bind() to 0.0.0.0:80 failed (13: Permission denied)`. You'd add `--cap-add NET_BIND_SERVICE`, but the modern answer is what we did: **listen high inside the container and map with `-p 80:8080`** — the port translation happens in the host's network stack, which runs as root, so the container needs no capability at all.
</details>

---

---

## ➡️ Next

**[`12-PROJECT-9-java-backend.md`](12-PROJECT-9-java-backend.md)** — Project 9.

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish%20Kumar%20Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn → <https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260>
🐙 GitHub → <https://github.com/3558Bhk>

*Built for engineers who learn by breaking things on purpose.*

</div>
