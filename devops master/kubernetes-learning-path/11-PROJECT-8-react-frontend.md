# ⚛️ Project 8 — React Frontend on Kubernetes

> **Time:** 2 hours · **Prereq:** [Project 6](09-PROJECT-6-ingress-tls.md) (Ingress) and [Project 3](06-PROJECT-3-config-secrets.md) (ConfigMaps)
>
> **The format:** every project from here on has two cases.
> - 🔵 **CASE 1 — Simple.** The minimum working manifest set. Get it running, understand every line.
> - 🟢 **CASE 2 — Production.** Multi-stage Docker build, hardened nginx, correct SPA routing, cache headers, non-root, probes, HPA, PDB, NetworkPolicy, Ingress with TLS, and CI.
>
> **Do Case 1 first.** Then Case 2, which replaces it.

---

## 8.0 Why a React app is a special case in Kubernetes

A production React build is **static files**. No process, no runtime, no health endpoint. That changes everything:

| Question | Answer for a React SPA |
|---|---|
| What image do I ship? | Just `nginx` + the `dist/` folder — **not** Node |
| What's the health check? | nginx serving `index.html`, or a `/healthz` location |
| Do I need graceful shutdown? | Barely — but `preStop: sleep 5` still prevents dropped requests |
| What breaks most often? | **Client-side routing** — `/products/42` returns 404 because nginx looks for a file |
| Second most common? | **Caching** — users get a stale `index.html` pointing at hashed JS that no longer exists |
| Third? | API URL — `localhost:3000` hardcoded in a production build |
| How big should the image be? | ~25 MB (nginx:alpine + your dist). Not 1.2 GB (node + node_modules). |

**The #1 React-on-Kubernetes bug** is client-side routing. Fix it once, correctly, and you're ahead of most teams:

```nginx
location / {
  try_files $uri $uri/ /index.html;
}
```

`try_files` says: if the exact file exists, serve it; else if the directory exists, serve it; **else serve `index.html`** and let React Router handle the path. Without that line, refreshing `/products/42` gives a 404 from nginx.

---

# 🔵 CASE 1 — Simple (30 minutes)

## 8.1 The app

```bash
mkdir -p ~/k8s-learn/p8 && cd ~/k8s-learn/p8
npm create vite@latest shop-ui -- --template react
cd shop-ui && npm install
```

`src/App.jsx`:

```jsx
import { useEffect, useState } from 'react'
import { BrowserRouter, Routes, Route, Link } from 'react-router-dom'
import './App.css'

const API = import.meta.env.VITE_API_URL || '/api'   // ⭐ relative path → same origin → no CORS

function Home() {
  const [msg, setMsg] = useState('loading…')
  useEffect(() => {
    fetch(`${API}/health`).then(r => r.json()).then(d => setMsg(d.message)).catch(e => setMsg(`API unreachable: ${e}`))
  }, [])
  return (
    <div className="card">
      <h2>Home</h2>
      <p>API says: <code>{msg}</code></p>
      <p>Pod: <code>{import.meta.env.VITE_POD_NAME ?? 'built locally'}</code></p>
    </div>
  )
}

const Products = () => (
  <div className="card">
    <h2>Products</h2>
    <p>This route only exists in the browser. Refresh it — nginx must return index.html.</p>
    <ul><li>Widget</li><li>Gadget</li><li>Doohickey</li></ul>
  </div>
)

const NotFound = () => <div className="card"><h2>404</h2><p>React Router caught this.</p></div>

export default function App() {
  return (
    <BrowserRouter>
      <div className="app">
        <header>
          <h1>🛍️ Shop UI</h1>
          <nav><Link to="/">Home</Link> · <Link to="/products">Products</Link> · <Link to="/products/42">Deep link</Link></nav>
        </header>
        <Routes>
          <Route path="/" element={<Home />} />
          <Route path="/products" element={<Products />} />
          <Route path="/products/:id" element={<Products />} />
          <Route path="*" element={<NotFound />} />
        </Routes>
        <footer>version {import.meta.env.VITE_VERSION ?? 'dev'} · built {new Date().toISOString()}</footer>
      </div>
    </BrowserRouter>
  )
}
```

```bash
npm install react-router-dom
npm run dev        # sanity check locally at http://localhost:5173
```

## 8.2 The simple Dockerfile

`Dockerfile`:

```dockerfile
# CASE 1: build with Node, serve with Node (deliberately suboptimal — see Case 2)
FROM node:22-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build
RUN npm install -g serve
EXPOSE 3000
CMD ["serve", "-s", "dist", "-l", "3000"]
```

`-s` is `serve`'s single-page-app flag — it does the `try_files → index.html` thing for you.

```bash
docker build -t shop-ui:case1 .
docker images shop-ui:case1
# shop-ui   case1   a1b2c3d4e5f6   10 seconds ago   245MB      ← 😬
kind load docker-image shop-ui:case1 --name learn
```

**245 MB to serve 300 KB of static files.** That's the problem Case 2 solves.

## 8.3 The simple manifests

`k8s/simple.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: shop-ui
  labels: {app: shop-ui}
spec:
  replicas: 2
  selector:
    matchLabels: {app: shop-ui}
  template:
    metadata:
      labels: {app: shop-ui}
    spec:
      containers:
        - name: web
          image: shop-ui:case1
          imagePullPolicy: IfNotPresent
          ports:
            - {name: http, containerPort: 3000}
          resources:
            requests: {cpu: 50m, memory: 64Mi}
            limits:   {cpu: 300m, memory: 256Mi}
          readinessProbe:
            httpGet: {path: /, port: http}
            periodSeconds: 5
          livenessProbe:
            httpGet: {path: /, port: http}
            initialDelaySeconds: 10
            periodSeconds: 20
---
apiVersion: v1
kind: Service
metadata:
  name: shop-ui
spec:
  selector: {app: shop-ui}
  ports:
    - {name: http, port: 80, targetPort: http}
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: shop-ui
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
spec:
  ingressClassName: nginx
  rules:
    - host: shop.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend: {service: {name: shop-ui, port: {number: 80}}}
```

```bash
kubectl apply -f k8s/simple.yaml
kubectl rollout status deploy/shop-ui
kubectl get pods -l app=shop-ui -o wide
kubectl get svc,ingress shop-ui
```

Test:

```bash
LB_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

curl -s -H "Host: shop.local" http://$LB_IP/ | head -5
curl -s -H "Host: shop.local" http://$LB_IP/products/42 | head -5     # ← MUST return index.html
curl -s -o /dev/null -w '%{http_code}\n' -H "Host: shop.local" http://$LB_IP/products/42
# 200  ✅
```

**If `/products/42` returns 404**, your SPA fallback is missing. With `serve -s` it should work; with plain nginx it won't until you add `try_files`.

```bash
# prove the deep link works from a browser too
echo "$LB_IP shop.local" | sudo tee -a /etc/hosts
# open http://shop.local/  → click "Deep link" → hit F5 → should still work
```

## 8.4 Case 1 review — what's wrong with it

| Problem | Impact |
|---|---|
| Image contains Node.js + all `node_modules` | 245 MB instead of 25 MB. Slow pulls, big attack surface, wasted disk |
| Build and serve in one stage | Every deploy re-runs `npm ci` even for a CSS change; no cache reuse |
| `serve` is not a production server | No gzip/brotli, no fine-grained cache control, no HTTP/2 tuning |
| No security context | Runs as root |
| No NetworkPolicy, PDB, or HPA | Fine for a toy, unacceptable for prod |
| `VITE_API_URL` baked at build time | One image per environment → you can't promote dev→staging→prod |

**Every one of those is fixed in Case 2.**

```bash
kubectl delete -f k8s/simple.yaml
```

---

# 🟢 CASE 2 — Production (90 minutes)

## 8.5 The multi-stage Dockerfile

`Dockerfile`:

```dockerfile
# syntax=docker/dockerfile:1
# ═══════════════════════════════════════════════════════════════
# STAGE 1 — build. Everything heavy lives here and is thrown away.
# ═══════════════════════════════════════════════════════════════
FROM node:22-alpine AS build

WORKDIR /app

# ── dependency layer: cached until package*.json changes ──
COPY package.json package-lock.json ./
RUN --mount=type=cache,target=/root/.npm \
    npm ci --no-audit --no-fund

# ── source layer: invalidated on any code change ──
COPY . .

# Build-time configuration. ⭐ Note: these are BAKED INTO the JS bundle.
ARG VITE_API_URL=/api
ARG VITE_VERSION=dev
ARG VITE_BUILD_TIME
ENV VITE_API_URL=${VITE_API_URL} \
    VITE_VERSION=${VITE_VERSION} \
    VITE_BUILD_TIME=${VITE_BUILD_TIME:-unknown} \
    NODE_OPTIONS=--max-old-space-size=1536

RUN npm run build \
 && echo "built ${VITE_VERSION} at ${VITE_BUILD_TIME}" > dist/BUILDINFO

# ── prune to the minimum: no sourcemaps, no .map files in prod unless you want them ──
RUN find dist -name '*.map' -delete \
 && du -sh dist

# ═══════════════════════════════════════════════════════════════
# STAGE 2 — runtime. nginx + static files. Nothing else.
# ═══════════════════════════════════════════════════════════════
FROM nginx:1.29-alpine AS runtime

# ── remove the default site & config ──
RUN rm -rf /etc/nginx/conf.d/default.conf /usr/share/nginx/html/*

# ── a non-root nginx needs writable pid/temp paths and a port > 1024 ──
COPY nginx.conf /etc/nginx/nginx.conf
COPY default.conf /etc/nginx/conf.d/default.conf

# ── the built assets ──
COPY --from=build --chown=nginx:nginx /app/dist /usr/share/nginx/html

# ── a health file that doesn't hit the SPA fallback ──
RUN echo "ok" > /usr/share/nginx/html/healthz.txt

# ── fix temp dirs so nginx can run fully read-only + non-root ──
RUN mkdir -p /var/cache/nginx /var/run /var/log/nginx \
 && chown -R nginx:nginx /var/cache/nginx /var/run /var/log/nginx \
 && chmod -R g+w /var/cache/nginx /var/run /var/log/nginx

EXPOSE 8080

# tini: proper PID 1 — reaps zombies, forwards SIGTERM to nginx
RUN apk add --no-cache tini
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["nginx", "-g", "daemon off;"]

# ── image metadata (OCI labels) ──
LABEL org.opencontainers.image.title="shop-ui" \
      org.opencontainers.image.description="Shop React frontend" \
      org.opencontainers.image.vendor="Harish Kumar Brahmandam" \
      org.opencontainers.image.source="https://github.com/3558Bhk/shop-ui" \
      org.opencontainers.image.licenses="MIT"
```

`nginx.conf` — the main config, tuned for non-root + read-only root filesystem:

```nginx
# run as the nginx user (uid 101 in the alpine image); the container's
# securityContext sets runAsUser, so this must match or be omitted
user  nginx;
worker_processes  auto;
worker_rlimit_nofile 8192;

error_log  /dev/stderr warn;
pid        /var/run/nginx.pid;                 # writable via emptyDir

events {
    worker_connections  4096;
    multi_accept        on;
    use                 epoll;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    # ── logs to stdout/stderr so Kubernetes collects them ──
    access_log  /dev/stdout  main;
    log_format  main escape=json
      '{"ts":"$time_iso8601","remote_addr":"$remote_addr",'
      '"method":"$request_method","path":"$uri","args":"$args",'
      '"status":$status,"body_bytes":$body_bytes_sent,'
      '"request_time":$request_time,"referer":"$http_referer",'
      '"ua":"$http_user_agent","req_id":"$request_id",'
      '"cache":"$upstream_cache_status"}';

    # ── temp paths must be writable when the rootfs is read-only ──
    client_body_temp_path /tmp/client_body;
    proxy_temp_path       /tmp/proxy;
    fastcgi_temp_path     /tmp/fastcgi;
    uwsgi_temp_path       /tmp/uwsgi;
    scgi_temp_path        /tmp/scgi;

    sendfile           on;
    tcp_nopush         on;
    tcp_nodelay        on;
    keepalive_timeout  65;
    keepalive_requests 1000;
    server_tokens      off;                      # don't advertise the version

    # ── compression: huge win for JS/CSS bundles ──
    gzip               on;
    gzip_vary          on;
    gzip_proxied       any;
    gzip_comp_level    6;
    gzip_min_length    1024;
    gzip_types
        text/plain text/css text/xml text/javascript
        application/javascript application/json application/xml application/rss+xml
        image/svg+xml font/woff2;

    # ── brotli needs the module; skip unless you build nginx with it ──
    # brotli on; brotli_comp_level 6; brotli_types ...;

    # ── security headers (applied to every response) ──
    add_header X-Content-Type-Options "nosniff"       always;
    add_header X-Frame-Options        "SAMEORIGIN"    always;
    add_header Referrer-Policy        "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy     "camera=(), microphone=(), geolocation=()" always;
    add_header Cross-Origin-Opener-Policy "same-origin" always;
    # ⚠️ HSTS belongs on the Ingress/edge where TLS terminates — enabling it here over HTTP locks you out.

    # ── rate limiting zone (used in default.conf) ──
    limit_req_zone $binary_remote_addr zone=perip:10m rate=30r/s;
    limit_conn_zone $binary_remote_addr zone=perconn:10m;

    include /etc/nginx/conf.d/*.conf;
}
```

`default.conf` — the server block, where SPA routing and caching live:

```nginx
server {
    listen       8080;                 # > 1024 → no NET_BIND_SERVICE capability needed
    listen       [::]:8080;
    server_name  _;
    root         /usr/share/nginx/html;
    index        index.html;

    # ── health & readiness: cheap, never cached, never logged ──
    location = /healthz {
        access_log off;
        add_header Content-Type text/plain;
        return 200 "ok\n";
    }
    location = /healthz.txt {
        access_log off;
    }
    location = /nginx_status {
        stub_status on;
        access_log off;
        allow 127.0.0.1;
        allow 10.0.0.0/8;
        deny all;
    }

    # ── ⭐ hashed assets: immutable, cache forever ──
    #    Vite emits assets/index-a1b2c3d4.js — the hash IS the version
    location ~* \.(?:js|css|woff2?|ttf|eot|otf|png|jpe?g|gif|svg|webp|avif|ico|map)$ {
        expires 1y;
        add_header Cache-Control "public, max-age=31536000, immutable";
        access_log off;
        try_files $uri =404;
        limit_req off;
    }

    # ── ⭐ index.html: NEVER cache. This is what makes deploys safe. ──
    location = /index.html {
        add_header Cache-Control "no-store, no-cache, must-revalidate, max-age=0";
        add_header Pragma "no-cache";
        expires -1;
        etag off;
        if_modified_since off;
    }

    # ── build info & service worker: also never cache ──
    location = /BUILDINFO   { add_header Cache-Control "no-store"; }
    location = /sw.js       { add_header Cache-Control "no-store"; }
    location = /manifest.json { add_header Cache-Control "no-store"; }
    location = /robots.txt  { add_header Cache-Control "max-age=3600"; }

    # ── ⭐ SPA FALLBACK: the single most important line in this file ──
    location / {
        limit_req zone=perip burst=50 nodelay;
        limit_conn perconn 20;
        try_files $uri $uri/ /index.html;
    }

    # ── deny dotfiles and source maps ──
    location ~ /\. { deny all; access_log off; log_not_found off; }

    # ── friendly 404 that still serves the SPA shell for unknown paths ──
    error_page 404 /index.html;
}
```

`.dockerignore` — this matters more than people think:

```
node_modules
dist
build
.git
.gitignore
.env
.env.*
!.env.example
*.log
npm-debug.log*
coverage
.nyc_output
.vscode
.idea
.DS_Store
Dockerfile
.dockerignore
k8s
README.md
**/*.test.jsx
**/*.spec.jsx
```

Build and measure the difference:

```bash
docker build \
  --build-arg VITE_API_URL=/api \
  --build-arg VITE_VERSION=$(git rev-parse --short HEAD 2>/dev/null || echo dev) \
  --build-arg VITE_BUILD_TIME=$(date -u +%FT%TZ) \
  -t shop-ui:case2 .

docker images | grep shop-ui
# shop-ui   case1   ...   245MB
# shop-ui   case2   ...   24.8MB      ← 10× smaller
```

```bash
# what's actually in it?
docker history shop-ui:case2 --no-trunc --format 'table {{.CreatedBy}}\t{{.Size}}' | head -20
docker run --rm shop-ui:case2 ls -la /usr/share/nginx/html
docker run --rm shop-ui:case2 nginx -T | grep -A3 'try_files'
```

## 8.6 The production manifests

`k8s/namespace.yaml`:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: shop
  labels:
    team: shop
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/warn: restricted
```

`k8s/config.yaml`:

```yaml
# ── runtime config, injected at CONTAINER START (not build time) ──
apiVersion: v1
kind: ConfigMap
metadata:
  name: shop-ui-runtime
  namespace: shop
data:
  env.js: |
    // Served at /env.js and loaded BEFORE the bundle.
    // Lets one image run in dev/staging/prod with different backends.
    window.__APP_CONFIG__ = {
      apiUrl: "__API_URL__",
      version: "__VERSION__",
      features: { newCheckout: false }
    };
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: shop-ui-nginx
  namespace: shop
data:
  default.conf: |
    server {
        listen 8080;
        server_name _;
        root /usr/share/nginx/html;
        index index.html;
        location = /healthz { access_log off; return 200 "ok\n"; }
        location = /env.js {
            add_header Cache-Control "no-store";
            sub_filter '__API_URL__'  '$api_url';
            sub_filter '__VERSION__'  '$app_version';
            sub_filter_once off;
            alias /runtime/env.js;
        }
        location ~* \.(?:js|css|woff2?|png|jpe?g|svg|webp)$ {
            expires 1y;
            add_header Cache-Control "public, max-age=31536000, immutable";
            access_log off;
            try_files $uri =404;
        }
        location = /index.html {
            add_header Cache-Control "no-store, no-cache, must-revalidate";
        }
        location / { try_files $uri $uri/ /index.html; }
    }
```

`k8s/deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: shop-ui
  namespace: shop
  labels:
    app: shop-ui
    app.kubernetes.io/name: shop-ui
    app.kubernetes.io/component: frontend
    app.kubernetes.io/part-of: shop
    version: v1
spec:
  replicas: 3
  revisionHistoryLimit: 5
  strategy:
    type: RollingUpdate
    rollingUpdate: {maxSurge: 1, maxUnavailable: 0}
  selector:
    matchLabels: {app: shop-ui}
  template:
    metadata:
      labels: {app: shop-ui, version: v1}
      annotations:
        # makes a ConfigMap change roll the Deployment automatically
        checksum/runtime: CHECKSUM_PLACEHOLDER
    spec:
      # ── Pod-level hardening ──
      securityContext:
        runAsNonRoot: true
        runAsUser: 101               # nginx user in nginx:alpine
        runAsGroup: 101
        fsGroup: 101
        seccompProfile: {type: RuntimeDefault}

      serviceAccountName: shop-ui
      terminationGracePeriodSeconds: 40
      automountServiceAccountToken: false    # a static site does NOT need API access

      # ── spread replicas across zones & nodes ──
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: ScheduleAnyway
          labelSelector: {matchLabels: {app: shop-ui}}
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: ScheduleAnyway
          labelSelector: {matchLabels: {app: shop-ui}}

      containers:
        - name: web
          image: ghcr.io/3558bhk/shop-ui:1.0.0     # ⭐ pinned, never :latest
          imagePullPolicy: IfNotPresent
          ports:
            - {name: http, containerPort: 8080, protocol: TCP}

          # ── container-level hardening ──
          securityContext:
            allowPrivilegeEscalation: false
            privileged: false
            readOnlyRootFilesystem: true
            capabilities: {drop: ["ALL"]}

          # ── writable paths nginx needs ──
          volumeMounts:
            - {name: cache,     mountPath: /var/cache/nginx}
            - {name: run,       mountPath: /var/run}
            - {name: logs,      mountPath: /var/log/nginx}
            - {name: tmp,       mountPath: /tmp}
            - {name: runtime,   mountPath: /runtime, readOnly: true}
            - {name: nginx-conf,mountPath: /etc/nginx/conf.d/default.conf, subPath: default.conf, readOnly: true}

          resources:
            requests: {cpu: 50m,  memory: 64Mi,  ephemeral-storage: 50Mi}
            limits:   {cpu: 500m, memory: 128Mi, ephemeral-storage: 200Mi}

          # ── probes: three of them, all correct ──
          startupProbe:
            httpGet: {path: /healthz, port: http}
            periodSeconds: 2
            failureThreshold: 15          # up to 30s to start
            timeoutSeconds: 2
          readinessProbe:
            httpGet: {path: /healthz, port: http}
            periodSeconds: 5
            failureThreshold: 2
            successThreshold: 1
            timeoutSeconds: 2
          livenessProbe:
            httpGet: {path: /healthz, port: http}
            periodSeconds: 20
            failureThreshold: 3
            timeoutSeconds: 3

          lifecycle:
            preStop:
              exec: {command: ["/bin/sh", "-c", "sleep 8"]}   # drain before SIGTERM

      volumes:
        - {name: cache,  emptyDir: {sizeLimit: 100Mi}}
        - {name: run,    emptyDir: {sizeLimit: 10Mi}}
        - {name: logs,   emptyDir: {sizeLimit: 100Mi}}
        - {name: tmp,    emptyDir: {sizeLimit: 50Mi}}
        - {name: runtime, configMap: {name: shop-ui-runtime}}
        - {name: nginx-conf, configMap: {name: shop-ui-nginx}}
```

`k8s/service.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: shop-ui
  namespace: shop
  labels: {app: shop-ui}
spec:
  type: ClusterIP
  selector: {app: shop-ui}
  ports:
    - {name: http, port: 80, targetPort: http, protocol: TCP}
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: shop-ui
  namespace: shop
  labels: {app: shop-ui}
automountServiceAccountToken: false
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: shop-ui
  namespace: shop
spec:
  minAvailable: 2
  selector: {matchLabels: {app: shop-ui}}
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: shop-ui
  namespace: shop
spec:
  scaleTargetRef: {apiVersion: apps/v1, kind: Deployment, name: shop-ui}
  minReplicas: 3
  maxReplicas: 20
  metrics:
    - type: Resource
      resource: {name: cpu, target: {type: Utilization, averageUtilization: 70}}
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 0
      policies: [{type: Percent, value: 100, periodSeconds: 30}]
      selectPolicy: Max
    scaleDown:
      stabilizationWindowSeconds: 300
      policies: [{type: Percent, value: 25, periodSeconds: 60}]
      selectPolicy: Min
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: shop-ui-allow-ingress-only
  namespace: shop
spec:
  podSelector: {matchLabels: {app: shop-ui}}
  policyTypes: [Ingress, Egress]
  ingress:
    - from:
        - namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: ingress-nginx}}
          podSelector: {matchLabels: {app.kubernetes.io/name: ingress-nginx}}
      ports: [{protocol: TCP, port: 8080}]
  egress:
    # DNS only — a static site has no other business talking out
    - to: [{namespaceSelector: {}}]
      ports: [{protocol: UDP, port: 53}, {protocol: TCP, port: 53}]
```

`k8s/ingress.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: shop-ui
  namespace: shop
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/proxy-body-size: "5m"
    # HSTS belongs here (where TLS terminates), not in the Pod's nginx
    nginx.ingress.kubernetes.io/configuration-snippet: |
      more_set_headers "Strict-Transport-Security: max-age=31536000; includeSubDomains; preload";
      more_set_headers "Content-Security-Policy: default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; connect-src 'self' https://api.example.com; font-src 'self' data:; frame-ancestors 'self'";
spec:
  ingressClassName: nginx
  tls:
    - hosts: [shop.example.com]
      secretName: shop-example-com-tls
  rules:
    - host: shop.example.com
      http:
        paths:
          - {path: /, pathType: Prefix, backend: {service: {name: shop-ui, port: {number: 80}}}}
---
# ── same host, separate Ingress so /api can carry its own annotations ──
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: shop-api
  namespace: shop
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/rewrite-target: /$2
    nginx.ingress.kubernetes.io/proxy-read-timeout: "60"
spec:
  ingressClassName: nginx
  tls:
    - hosts: [shop.example.com]
      secretName: shop-example-com-tls
  rules:
    - host: shop.example.com
      http:
        paths:
          - path: /api(/|$)(.*)
            pathType: ImplementationSpecific
            backend: {service: {name: shop-api, port: {number: 8080}}}
```

Deploy:

```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/config.yaml
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/ingress.yaml

kubectl get all,pdb,hpa,netpol,ingress -n shop
kubectl rollout status deploy/shop-ui -n shop
```

## 8.7 Verify everything, one thing at a time

```bash
# ── 1. Hardened? ──
kubectl get pod -n shop -l app=shop-ui -o jsonpath='{.items[0].status.qosClass}'; echo
kubectl exec -n shop deploy/shop-ui -- id
# uid=101(nginx) gid=101(nginx)
kubectl exec -n shop deploy/shop-ui -- touch /etc/passwd
# touch: /etc/passwd: Read-only file system          ✅
kubectl exec -n shop deploy/shop-ui -- touch /tmp/ok && echo "/tmp writable ✅"

# ── 2. Probes work? ──
kubectl exec -n shop deploy/shop-ui -- wget -qO- localhost:8080/healthz
# ok
kubectl describe pod -n shop -l app=shop-ui | grep -E 'Liveness|Readiness|Startup'

# ── 3. SPA routing? ──
LB_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
for p in / /products /products/42 /deep/nested/route /does/not/exist; do
  printf '%-24s %s\n' "$p" "$(curl -sk -o /dev/null -w '%{http_code}' --resolve shop.example.com:443:$LB_IP https://shop.example.com$p)"
done
# /                        200
# /products                200
# /products/42             200
# /deep/nested/route       200
# /does/not/exist          200     ← SPA fallback; React Router shows the 404 page

# ── 4. Caching headers correct? ──
ASSET=$(curl -sk --resolve shop.example.com:443:$LB_IP https://shop.example.com/ | grep -o '/assets/[^"]*\.js' | head -1)
echo "asset: $ASSET"
curl -skI --resolve shop.example.com:443:$LB_IP "https://shop.example.com$ASSET" | grep -iE 'cache-control|expires|etag|content-encoding'
# cache-control: public, max-age=31536000, immutable     ✅

curl -skI --resolve shop.example.com:443:$LB_IP https://shop.example.com/index.html | grep -i cache-control
# cache-control: no-store, no-cache, must-revalidate      ✅

# ── 5. Compression? ──
curl -sk --resolve shop.example.com:443:$LB_IP -H 'Accept-Encoding: gzip, br' \
  -o /dev/null -w 'size=%{size_download} encoding=%{content_type}\n' "https://shop.example.com$ASSET"
curl -skI --resolve shop.example.com:443:$LB_IP -H 'Accept-Encoding: gzip' "https://shop.example.com$ASSET" \
  | grep -i content-encoding
# content-encoding: gzip   ✅ (may be applied by the Ingress instead)

# ── 6. Security headers? ──
curl -skI --resolve shop.example.com:443:$LB_IP https://shop.example.com/ \
  | grep -iE 'x-frame|x-content-type|referrer|strict-transport|content-security|server'
# server: nginx        (no version — server_tokens off ✅)

# ── 7. TLS cert real & auto-renewing? ──
kubectl get certificate -n shop
echo | openssl s_client -connect shop.example.com:443 -servername shop.example.com 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates

# ── 8. NetworkPolicy enforced? ──
kubectl run probe -n shop --rm -it --image=nicolaka/netshoot --restart=Never --labels="app=evil" -- \
  curl -s -m 3 http://shop-ui.shop.svc.cluster.local/
# ⛔ times out — the policy only allows ingress-nginx pods
kubectl -n ingress-nginx exec deploy/ingress-nginx-controller -- \
  curl -s -m 3 http://shop-ui.shop.svc.cluster.local/healthz
# ok ✅

# ── 9. HPA working? ──
kubectl get hpa -n shop
kubectl describe hpa shop-ui -n shop | grep -A5 Targets

# ── 10. Zero-downtime deploy? ──
( for i in $(seq 1 200); do
    curl -sk -o /dev/null -w '%{http_code}\n' --resolve shop.example.com:443:$LB_IP https://shop.example.com/healthz
    sleep 0.05
  done ) | sort | uniq -c &
LOAD=$!
kubectl rollout restart deploy/shop-ui -n shop
kubectl rollout status deploy/shop-ui -n shop
wait $LOAD
#    200 200      ← zero non-200s ✅
```

## 8.8 The "one image, all environments" pattern

Because Vite **bakes** `import.meta.env.*` into the bundle at build time, a naive setup needs one image per environment. That breaks promotion. Fix it with a runtime config file:

`index.html`:

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Shop</title>
    <!-- ⭐ loaded BEFORE the bundle; served by nginx with sub_filter substitution -->
    <script src="/env.js"></script>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.jsx"></script>
  </body>
</html>
```

`src/config.js`:

```js
// Runtime config with a build-time fallback.
// window.__APP_CONFIG__ comes from /env.js, which nginx fills in per environment.
const rc = (typeof window !== 'undefined' && window.__APP_CONFIG__) || {}

export const config = {
  apiUrl:     rc.apiUrl     ?? import.meta.env.VITE_API_URL     ?? '/api',
  version:    rc.version    ?? import.meta.env.VITE_VERSION     ?? 'dev',
  features:   rc.features   ?? {},
}
```

Then one image works everywhere — the ConfigMap supplies the environment. Change `__API_URL__` in the ConfigMap, `rollout restart`, done. No rebuild.

Alternatives:
- **nginx `sub_filter`** on `index.html` itself (replace `%%API_URL%%` at serve time)
- **an entrypoint script** that `envsubst`s `/env.js` from env vars at container start:
  ```dockerfile
  COPY docker-entrypoint.sh /
  ENTRYPOINT ["/docker-entrypoint.sh"]
  ```
  ```sh
  #!/bin/sh
  set -e
  envsubst < /usr/share/nginx/html/env.template.js > /usr/share/nginx/html/env.js
  exec nginx -g 'daemon off;'
  ```
  ⚠️ needs a writable root — use `emptyDir` for the html dir, or write to `/tmp` and serve from there.
- **`nginx-vts` / `lua-resty`** if you're already on OpenResty

---

## 8.9 Extra Tasks

### Task 8.1 — Make the deploy truly zero-downtime under load

Prove it with a real load generator, and find at least one thing that breaks it.

<details>
<summary>Show answer</summary>

```bash
brew install hey        # or: go install github.com/rakyll/hey@latest

LB_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# ── baseline: no deploy happening ──
hey -z 20s -q 50 -c 10 -host shop.example.com \
    "http://$LB_IP/" 2>&1 | tee baseline.txt
grep -E 'Requests/sec|Status code distribution|\[5' baseline.txt
```

```
Status code distribution:
  [200] 1000 responses
```

```bash
# ── under a rolling deploy ──
hey -z 60s -q 50 -c 10 -host shop.example.com "http://$LB_IP/" > during-rollout.txt &
HEY=$!
sleep 2
kubectl set image deploy/shop-ui -n shop web=ghcr.io/3558bhk/shop-ui:1.0.1
kubectl rollout status deploy/shop-ui -n shop
wait $HEY
grep -E 'Requests/sec|Status code distribution|\[5|Error distribution' during-rollout.txt
```

**Things that break zero-downtime, in the order you'll hit them:**

| # | Cause | Symptom | Fix |
|---|---|---|---|
| 1 | **No readiness probe** | 502s at the start of each Pod's life | Add `readinessProbe` on `/healthz` |
| 2 | **`maxUnavailable: 1`** (default with 25%) | Capacity dips; latency spikes | `maxUnavailable: 0`, `maxSurge: 1` |
| 3 | **No `preStop` sleep** | A handful of 502s at the *end* of each Pod's life | `preStop: exec: sleep 8` |
| 4 | **App ignores SIGTERM** | 137 exits, dropped connections | exec-form ENTRYPOINT, or `tini` (we already did both) |
| 5 | **`terminationGracePeriodSeconds` too short** | SIGKILL mid-request | grace > preStop + app shutdown |
| 6 | **Ingress controller reload lag** | 502s for ~1 s after endpoints change | Expected; the preStop sleep covers it |
| 7 | **`keepalive` connections to a dying Pod** | A few `EOF`/`connection reset` errors | preStop sleep ≥ the LB's idle timeout |
| 8 | **HPA scaling during the rollout** | Replica count churns | `scaleDown.stabilizationWindowSeconds: 300` |
| 9 | **PDB too strict** | Rollout hangs | `minAvailable: 2` with 3 replicas, not `minAvailable: 3` |

Isolate #3 empirically — remove the preStop and re-run:

```bash
kubectl patch deploy shop-ui -n shop --type=json \
  -p='[{"op":"remove","path":"/spec/template/spec/containers/0/lifecycle"}]'
kubectl rollout status deploy/shop-ui -n shop

hey -z 60s -q 50 -c 10 -host shop.example.com "http://$LB_IP/" > no-prestop.txt &
HEY=$!; sleep 2
kubectl rollout restart deploy/shop-ui -n shop
kubectl rollout status deploy/shop-ui -n shop
wait $HEY
grep -A3 'Status code distribution' no-prestop.txt
```

You should now see a handful of `[502]` or `[503]`. Put it back:

```bash
kubectl apply -f k8s/deployment.yaml
```

**The full zero-downtime recipe, restated:**

```yaml
strategy:
  rollingUpdate: {maxSurge: 1, maxUnavailable: 0}
spec:
  terminationGracePeriodSeconds: 40
  containers:
    - readinessProbe: {httpGet: {path: /healthz, port: http}, periodSeconds: 5, failureThreshold: 2}
      lifecycle: {preStop: {exec: {command: ["/bin/sh","-c","sleep 8"]}}}
```

Plus: `revisionHistoryLimit` for rollback, a PDB, and `kubectl rollout status --timeout=300s` in CI so a failed deploy fails the pipeline.

</details>

---

### Task 8.2 — Fix a broken cache invalidation

You deployed v2. Users see a white screen. The console says `Failed to load module script: … index-a1b2c3d4.js 404`. Diagnose and prevent it.

<details>
<summary>Show answer</summary>

**What happened:**

```
1. User loaded /index.html from v1  →  cached by the browser (or a CDN)
2. It references /assets/index-a1b2c3d4.js   (v1's hashed bundle)
3. You deploy v2. The old bundle is GONE from the image.
4. The cached index.html asks for a file that no longer exists → 404 → white screen
```

**Diagnose:**

```bash
curl -skI --resolve shop.example.com:443:$LB_IP https://shop.example.com/index.html | grep -iE 'cache-control|etag|last-modified|age|x-cache'
```

If `cache-control` is anything other than `no-store`, that's your bug.

```bash
# is the CDN caching index.html?
curl -skI https://shop.example.com/index.html | grep -iE 'age:|x-cache:|cf-cache-status:'
# cf-cache-status: HIT   ← ⛔ Cloudflare cached your HTML
```

**Fix — three layers:**

**Layer 1: never cache `index.html`.**

```nginx
location = /index.html {
    add_header Cache-Control "no-store, no-cache, must-revalidate, max-age=0";
    add_header Pragma "no-cache";
    expires -1;
    etag off;
    if_modified_since off;
}
```

> ⚠️ **nginx `add_header` inheritance trap:** `add_header` directives in a `location` block **replace** all inherited ones from `http`/`server`. If your security headers are set at the `http` level, they vanish inside this location. Either repeat them here, or set them all at the same level.

**Layer 2: cache hashed assets forever.**

```nginx
location ~* \.(?:js|css|woff2?|png|jpe?g|svg|webp|map)$ {
    expires 1y;
    add_header Cache-Control "public, max-age=31536000, immutable";
}
```

This is safe *because* the filename contains a content hash. A new build → new filenames → no collision.

**Layer 3: configure the CDN correctly.**

Cloudflare:
```
Cache Rule: hostname eq "shop.example.com" AND ends_with(http.request.uri.path, ".html")
            → Cache eligibility: Bypass
Cache Rule: starts_with(http.request.uri.path, "/assets/")
            → Edge TTL: Override origin, 1 year; Browser TTL: 1 year
```

CloudFront (via a cache policy):
```yaml
# OriginRequestPolicy for HTML: min/max/default TTL = 0
# CachePolicy for /assets/*:   min 31536000, max 31536000, default 31536000
```

Fastly/Varnish VCL:
```vcl
sub vcl_recv {
  if (req.url ~ "^/assets/") { set req.http.X-Cacheable = "1"; }
  else { return (pass); }
}
```

**Layer 4: keep old bundles around during a deploy (belt and braces).**

The window between "new index.html served" and "user's browser finishes loading the old chunks" is unavoidable with lazy-loaded routes. Two mitigations:

a. **Retain N previous builds in the image:**

```dockerfile
FROM nginx:1.29-alpine AS runtime
COPY --from=build /app/dist /usr/share/nginx/html
COPY --from=previous /dist/assets /usr/share/nginx/html/assets-previous
```
Complex. Most teams don't.

b. **Catch the failure in the app and hard-reload** (simple, effective, widely used):

```jsx
// src/main.jsx
window.addEventListener('vite:preloadError', (event) => {
  event.preventDefault()                       // stop the error from propagating
  const key = 'last-reload'
  const last = Number(sessionStorage.getItem(key) || 0)
  // guard against a reload loop
  if (Date.now() - last > 30_000) {
    sessionStorage.setItem(key, String(Date.now()))
    window.location.reload()
  } else {
    showErrorBanner('A new version is available. Please refresh.')
  }
})
```

Vite emits `vite:preloadError` exactly when a dynamic import 404s. This is the standard, framework-supported answer.

c. **Notify users of a new version instead of breaking them:**

```jsx
// poll BUILDINFO; when it changes, show a banner
useEffect(() => {
  let current = null
  const check = async () => {
    try {
      const info = await (await fetch('/BUILDINFO', {cache: 'no-store'})).text()
      if (current && info !== current) setShowUpdateBanner(true)
      current = info
    } catch {}
  }
  check()
  const id = setInterval(check, 60_000)
  return () => clearInterval(id)
}, [])
```

**Verify the whole thing after fixing:**

```bash
# index.html must NOT be cached
curl -skI --resolve shop.example.com:443:$LB_IP https://shop.example.com/index.html \
  | grep -i cache-control
# cache-control: no-store, no-cache, must-revalidate, max-age=0   ✅

# assets MUST be cached immutably
curl -skI --resolve shop.example.com:443:$LB_IP "https://shop.example.com$ASSET" \
  | grep -i cache-control
# cache-control: public, max-age=31536000, immutable               ✅

# CDN
curl -skI https://shop.example.com/index.html | grep -iE 'cf-cache-status|age:'
# cf-cache-status: BYPASS or DYNAMIC                               ✅
```

</details>

---

### Task 8.3 — Serve the SPA and proxy the API from the same origin (no CORS)

Your frontend calls `https://api.example.com` from `https://shop.example.com` and gets CORS errors. Fix it properly.

<details>
<summary>Show answer</summary>

**Three options. Pick #1.**

### Option 1 — Same origin via the Ingress (the right answer)

Route both under one hostname. The browser sees one origin → **no CORS at all**.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: shop
  namespace: shop
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/rewrite-target: /$2
spec:
  ingressClassName: nginx
  tls: [{hosts: [shop.example.com], secretName: shop-tls}]
  rules:
    - host: shop.example.com
      http:
        paths:
          - path: /api(/|$)(.*)
            pathType: ImplementationSpecific
            backend: {service: {name: shop-api, port: {number: 8080}}}
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata: {name: shop-ui, namespace: shop}
spec:
  ingressClassName: nginx
  tls: [{hosts: [shop.example.com], secretName: shop-tls}]
  rules:
    - host: shop.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend: {service: {name: shop-ui, port: {number: 80}}}
```

Frontend code:

```js
export const config = { apiUrl: '/api' }        // relative! same origin!
fetch(`${config.apiUrl}/products`)              // → https://shop.example.com/api/products
```

`/api/products` → rewrite strips `/api` → the api Service receives `/products`.

**Verify:**

```bash
curl -sk --resolve shop.example.com:443:$LB_IP https://shop.example.com/api/health
# {"status":"UP"}
curl -skI --resolve shop.example.com:443:$LB_IP https://shop.example.com/api/health | grep -i access-control
# (nothing — and that's CORRECT; no CORS headers needed for same-origin)
```

### Option 2 — Proxy from the SPA's nginx (useful in dev, or when you can't change the Ingress)

```nginx
location /api/ {
    proxy_pass http://shop-api.shop.svc.cluster.local:8080/;
    proxy_http_version 1.1;
    proxy_set_header Host              $host;
    proxy_set_header X-Real-IP         $remote_addr;
    proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Request-ID      $request_id;
    proxy_read_timeout 60s;
    proxy_buffering off;                # SSE / streaming
}
```

⚠️ **But:** your hardened Pod runs with a NetworkPolicy that denies egress. You must allow it:

```yaml
  egress:
    - to: [{podSelector: {matchLabels: {app: shop-api}}}]
      ports: [{protocol: TCP, port: 8080}]
    - to: [{namespaceSelector: {}}]
      ports: [{protocol: UDP, port: 53}, {protocol: TCP, port: 53}]
```

### Option 3 — Real CORS (when the origins genuinely must differ)

Enable it in **one place only** — either the Ingress or the backend, never both (duplicate `Access-Control-Allow-Origin` headers break browsers worse than no headers).

**At the Ingress:**

```yaml
metadata:
  annotations:
    nginx.ingress.kubernetes.io/enable-cors: "true"
    nginx.ingress.kubernetes.io/cors-allow-origin: "https://shop.example.com"
    nginx.ingress.kubernetes.io/cors-allow-methods: "GET, POST, PUT, PATCH, DELETE, OPTIONS"
    nginx.ingress.kubernetes.io/cors-allow-headers: "Authorization, Content-Type, X-Request-ID"
    nginx.ingress.kubernetes.io/cors-expose-headers: "X-Request-ID, X-Total-Count"
    nginx.ingress.kubernetes.io/cors-allow-credentials: "true"
    nginx.ingress.kubernetes.io/cors-max-age: "600"
```

⚠️ With `cors-allow-credentials: "true"` you **cannot** use `*` for the origin. Browsers reject it.

**At the backend (Spring Boot):**

```java
@Configuration
public class CorsConfig implements WebMvcConfigurer {
  @Override public void addCorsMappings(CorsRegistry r) {
    r.addMapping("/api/**")
     .allowedOrigins("https://shop.example.com")
     .allowedMethods("GET","POST","PUT","PATCH","DELETE","OPTIONS")
     .allowedHeaders("*")
     .exposedHeaders("X-Request-ID")
     .allowCredentials(true)
     .maxAge(600);
  }
}
```

**Verify:**

```bash
# preflight
curl -skI -X OPTIONS --resolve api.example.com:443:$LB_IP https://api.example.com/api/products \
  -H 'Origin: https://shop.example.com' \
  -H 'Access-Control-Request-Method: POST' \
  -H 'Access-Control-Request-Headers: content-type,authorization' \
  | grep -i access-control
# access-control-allow-origin: https://shop.example.com
# access-control-allow-methods: GET, POST, PUT, PATCH, DELETE, OPTIONS
# access-control-allow-credentials: true
# access-control-max-age: 600

# actual request
curl -sk --resolve api.example.com:443:$LB_IP https://api.example.com/api/products \
  -H 'Origin: https://shop.example.com' -D - -o /dev/null | grep -i access-control-allow-origin
```

**Common CORS failures:**

| Browser error | Cause |
|---|---|
| `No 'Access-Control-Allow-Origin' header` | Backend didn't handle the preflight, or the Ingress annotation is missing |
| `contains multiple values '*, *'` | Both Ingress and backend added the header. Remove one |
| `credentials mode 'include' … wildcard` | `allow-credentials: true` + `allow-origin: *`. Use an explicit origin |
| `Redirect is not allowed for a preflight request` | The OPTIONS request got a 301/308. Exclude OPTIONS from `ssl-redirect` |
| Works in dev, fails in prod | Different origins per environment → make the allowed-origin list configurable |

</details>

---

### Task 8.4 — Add a CI pipeline that builds, scans, signs, and deploys

GitHub Actions: push to `main` → image in GHCR → cluster updated → verified.

<details>
<summary>Show answer</summary>

`.github/workflows/deploy.yaml`:

```yaml
name: build-and-deploy

on:
  push:
    branches: [main]
    paths: ['src/**', 'public/**', 'package*.json', 'Dockerfile', 'nginx*.conf', 'k8s/**', '.github/workflows/deploy.yaml']
  pull_request:
    branches: [main]
  workflow_dispatch:
    inputs:
      environment: {description: 'dev | staging | prod', default: dev, type: choice, options: [dev, staging, prod]}

permissions:
  contents: read
  packages: write
  id-token: write            # for OIDC to AWS/GCP and for cosign keyless signing

env:
  REGISTRY: ghcr.io
  IMAGE: ${{ github.repository_owner }}/shop-ui

concurrency:
  group: deploy-${{ github.ref }}
  cancel-in-progress: false  # never cancel a deploy mid-flight

jobs:
  # ────────────────────────────────────────────────
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: {node-version: 22, cache: npm}
      - run: npm ci --no-audit --no-fund
      - run: npm run lint --if-present
      - run: npm run test -- --run --coverage --if-present
      - run: npm run build
      - uses: actions/upload-artifact@v4
        with: {name: dist, path: dist, retention-days: 1}

  # ────────────────────────────────────────────────
  build:
    needs: test
    runs-on: ubuntu-latest
    outputs:
      digest: ${{ steps.build.outputs.digest }}
      tags: ${{ steps.meta.outputs.tags }}
    steps:
      - uses: actions/checkout@v4

      - uses: docker/setup-buildx-action@v3

      - uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE }}
          tags: |
            type=ref,event=pr
            type=sha,prefix=sha-,format=short
            type=raw,value=${{ github.sha }}
            type=raw,value=latest,enable={{is_default_branch}}

      - id: build
        uses: docker/build-push-action@v6
        with:
          context: .
          push: ${{ github.event_name != 'pull_request' }}
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          build-args: |
            VITE_VERSION=${{ github.sha }}
            VITE_BUILD_TIME=${{ github.event.head_commit.timestamp }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
          provenance: true
          sbom: true
          platforms: linux/amd64
        # outputs.digest is what we deploy — NOT a mutable tag

      # ── scan ──
      - name: Trivy scan (fail on CRITICAL/HIGH)
        uses: aquasecurity/trivy-action@0.28.0
        with:
          image-ref: ${{ env.REGISTRY }}/${{ env.IMAGE }}@${{ steps.build.outputs.digest }}
          format: table
          exit-code: '1'
          severity: CRITICAL,HIGH
          ignore-unfixed: true

      # ── sign (keyless via OIDC — no long-lived keys to leak) ──
      - uses: sigstore/cosign-installer@v3
      - name: cosign sign
        if: github.event_name != 'pull_request'
        run: |
          cosign sign --yes \
            ${{ env.REGISTRY }}/${{ env.IMAGE }}@${{ steps.build.outputs.digest }}

  # ────────────────────────────────────────────────
  deploy:
    needs: build
    if: github.event_name != 'pull_request'
    runs-on: ubuntu-latest
    environment:
      name: ${{ inputs.environment || 'dev' }}
      url: https://shop.${{ inputs.environment || 'dev' }}.example.com
    steps:
      - uses: actions/checkout@v4

      - name: Configure kubeconfig
        run: |
          mkdir -p ~/.kube
          echo "${{ secrets.KUBE_CONFIG_DEV }}" | base64 -d > ~/.kube/config
          chmod 600 ~/.kube/config
          kubectl version --client
          kubectl cluster-info

      - name: Verify image signature (admission-level enforcement is better; this is a belt)
        uses: sigstore/cosign-installer@v3
      - run: |
          cosign verify \
            --certificate-identity-regexp="https://github.com/${{ github.repository }}/.github/workflows/deploy.yaml" \
            --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
            ${{ env.REGISTRY }}/${{ env.IMAGE }}@${{ needs.build.outputs.digest }}

      - name: Deploy
        run: |
          set -euo pipefail
          NS=${{ inputs.environment || 'dev' }}
          IMAGE="${{ env.REGISTRY }}/${{ env.IMAGE }}@${{ needs.build.outputs.digest }}"

          kubectl apply -f k8s/namespace.yaml
          kubectl apply -f k8s/config.yaml -n $NS
          kubectl apply -f k8s/service.yaml  -n $NS

          # patch the image BY DIGEST — immutable, no tag-cache surprises
          kubectl set image deploy/shop-ui -n $NS web="$IMAGE"
          kubectl annotate deploy/shop-ui -n $NS \
            kubernetes.io/change-cause="gha run ${{ github.run_id }} sha ${{ github.sha }}" --overwrite

          # fail the pipeline if the rollout stalls
          kubectl rollout status deploy/shop-ui -n $NS --timeout=300s

      - name: Smoke test
        run: |
          set -euo pipefail
          URL=https://shop.${{ inputs.environment || 'dev' }}.example.com
          for p in / /healthz /products/42; do
            code=$(curl -sk -o /dev/null -w '%{http_code}' "$URL$p")
            echo "$p → $code"
            [ "$code" = 200 ] || { echo "❌ smoke test failed on $p"; exit 1; }
          done
          # index.html must not be cached
          cc=$(curl -skI "$URL/index.html" | grep -i '^cache-control' || true)
          echo "$cc" | grep -qi 'no-store' || { echo "❌ index.html is cacheable: $cc"; exit 1; }
          echo "✅ smoke tests passed"

      - name: Rollback on failure
        if: failure()
        run: |
          NS=${{ inputs.environment || 'dev' }}
          echo "⚠️ rolling back"
          kubectl rollout undo deploy/shop-ui -n $NS
          kubectl rollout status deploy/shop-ui -n $NS --timeout=180s
          kubectl get pods -n $NS -l app=shop-ui -o wide
```

**Server-side admission: only signed images may run** (much stronger than a CI check):

```bash
# Kyverno policy
kubectl apply -f - <<'EOF'
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata: {name: verify-image-signature}
spec:
  validationFailureAction: Enforce
  rules:
    - name: verify-signature
      match:
        any:
          - resources: {kinds: [Pod]}
      verifyImages:
        - imageReferences: ["ghcr.io/3558bhk/*"]
          attestors:
            - entries:
                - keyless:
                    issuer: https://token.actions.githubusercontent.com
                    subject: "https://github.com/3558Bhk/shop-ui/.github/workflows/deploy.yaml@refs/heads/main"
EOF
```

Now an unsigned image is **rejected by the API server** — no amount of `kubectl set image` will run it.

**Key CI/CD decisions in this pipeline:**

| Decision | Why |
|---|---|
| Deploy by **digest**, not tag | Tags are mutable; a digest is not. Guarantees the artifact you scanned is the artifact you run |
| `rollout status --timeout` | Fails the build on a stuck deploy instead of silently leaving it broken |
| Automatic `rollout undo` on failure | MTTR measured in seconds |
| `concurrency` with `cancel-in-progress: false` | Two deploys can't interleave |
| Trivy `exit-code: 1` | A CRITICAL CVE blocks the deploy, not just warns |
| cosign keyless (OIDC) | No long-lived signing key in GitHub Secrets to leak |
| Smoke test after deploy | "It deployed" ≠ "it works" |
| Separate `environment:` per stage | GitHub gates prod behind a manual approval |

</details>

---

### Task 8.5 — Serve a React app that needs a backend at runtime (SSR / Node server)

Some React apps aren't static: Next.js SSR, Remix, or a custom Node server. How does that change the Kubernetes setup?

<details>
<summary>Show answer</summary>

Everything changes except the shape of the manifests. A Node server is a **real process** with a real lifecycle.

`Dockerfile` (Next.js 15, standalone output):

```dockerfile
# syntax=docker/dockerfile:1
FROM node:22-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN --mount=type=cache,target=/root/.npm npm ci --no-audit --no-fund

FROM node:22-alpine AS build
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
ENV NEXT_TELEMETRY_DISABLED=1
RUN npm run build                      # next.config.js must set output: 'standalone'

FROM node:22-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production \
    NEXT_TELEMETRY_DISABLED=1 \
    PORT=3000 \
    HOSTNAME=0.0.0.0

RUN apk add --no-cache tini curl \
 && addgroup -g 1001 -S nodejs \
 && adduser  -u 1001 -S nextjs -G nodejs

# standalone bundles ONLY the required node_modules → ~150MB instead of 900MB
COPY --from=build --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=build --chown=nextjs:nodejs /app/.next/static ./.next/static
COPY --from=build --chown=nextjs:nodejs /app/public ./public

USER nextjs
EXPOSE 3000
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["node", "server.js"]
```

`next.config.js`:

```js
export default { output: 'standalone' }   // ⭐ required for the small runtime image
```

**The manifest differences vs. the static SPA:**

```yaml
spec:
  template:
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1001                # nextjs, not 101/nginx
        fsGroup: 1001
        seccompProfile: {type: RuntimeDefault}
      containers:
        - name: web
          image: ghcr.io/3558bhk/shop-ui-ssr:1.0.0
          ports: [{name: http, containerPort: 3000}]
          env:
            - {name: NODE_ENV, value: production}
            - {name: NODE_OPTIONS, value: "--max-old-space-size=768"}   # ⭐ ~75% of the limit
            - {name: HOSTNAME, value: "0.0.0.0"}
            - {name: API_URL, value: "http://shop-api.shop.svc.cluster.local:8080"}
            - name: DATABASE_URL
              valueFrom: {secretKeyRef: {name: db-creds, key: url}}
            # Next.js runtime config (no rebuild needed per env)
            - {name: NEXT_PUBLIC_API_BASE, value: "/api"}
          resources:
            requests: {cpu: 200m, memory: 512Mi}
            limits:   {cpu: "1",   memory: 1Gi}     # ⭐ Node needs real headroom
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities: {drop: ["ALL"]}
          startupProbe:                  # ⭐ SSR cold start is SLOW — this is essential
            httpGet: {path: /healthz, port: http}
            periodSeconds: 3
            failureThreshold: 40         # up to 2 minutes
          readinessProbe:
            httpGet: {path: /healthz, port: http}
            periodSeconds: 10
            failureThreshold: 3
          livenessProbe:
            httpGet: {path: /healthz, port: http}
            periodSeconds: 20
            failureThreshold: 3
            timeoutSeconds: 5            # Node can be slow to answer under GC
          lifecycle:
            preStop:
              exec:
                command: ["/bin/sh","-c","sleep 10"]   # longer: Node needs to drain
          volumeMounts:
            - {name: tmp, mountPath: /tmp}             # Node writes here constantly
            - {name: next-cache, mountPath: /app/.next/cache}
      terminationGracePeriodSeconds: 60                # longer than preStop + drain
      volumes:
        - {name: tmp, emptyDir: {sizeLimit: 512Mi}}
        - {name: next-cache, emptyDir: {sizeLimit: 2Gi}}   # or a PVC if it must persist
```

**`app/healthz/route.ts`** — a real health endpoint, not `/` (which renders a whole page):

```ts
export const dynamic = 'force-dynamic'
export async function GET() {
  // liveness: cheap, never touches dependencies
  return Response.json({ status: 'ok', uptime: process.uptime() })
}
```

And a separate readiness endpoint that *does* check dependencies:

```ts
// app/readyz/route.ts
export const dynamic = 'force-dynamic'
export async function GET() {
  try {
    const r = await fetch(`${process.env.API_URL}/health`, { signal: AbortSignal.timeout(2000) })
    if (!r.ok) return new Response('api down', { status: 503 })
    return Response.json({ status: 'ready' })
  } catch (e) {
    return new Response(`dep error: ${e}`, { status: 503 })
  }
}
```

**Node-specific gotchas, all of which will bite you:**

| Problem | Cause | Fix |
|---|---|---|
| OOMKilled at 512 Mi despite "low" heap | V8's default heap (~1.5–4 GB) ignores the cgroup limit | `--max-old-space-size=<75% of limit>` |
| Slow cold start → liveness kills it before it's up | No startupProbe | Add one with a generous `failureThreshold` |
| Requests dropped on deploy | Node's default SIGTERM handler exits immediately | `preStop` sleep + a `process.on('SIGTERM')` that calls `server.close()` |
| `/tmp` fills and the app crashes | `readOnlyRootFilesystem: true` | `emptyDir` at `/tmp` |
| `.next/cache` grows unbounded | Next writes build cache at runtime | `emptyDir` with `sizeLimit`, or a PVC |
| CPU limit throttles the event loop | Node is single-threaded; throttling = frozen event loop | Raise the CPU limit or remove it; watch `container_cpu_cfs_throttled_periods_total` |
| Clustering confusion | `cluster` module inside a container is an anti-pattern | **One process per Pod.** Scale with replicas, not `cluster` |
| Memory creep over days | Leaked closures/listeners | `--heapsnapshot-near-heap-limit=1`, then analyse with `--inspect` + Chrome DevTools via port-forward |

**Graceful shutdown for a Node server:**

```js
// server.js wrapper
const server = app.listen(PORT, () => console.log(`ready on ${PORT}`))

let shuttingDown = false
function shutdown(signal) {
  if (shuttingDown) return
  shuttingDown = true
  console.log(`${signal} received — draining`)
  server.close(() => { console.log('drained'); process.exit(0) })
  // hard deadline, must be < terminationGracePeriodSeconds
  setTimeout(() => { console.error('drain timeout, forcing exit'); process.exit(1) }, 25_000).unref()
}
process.on('SIGTERM', () => shutdown('SIGTERM'))
process.on('SIGINT',  () => shutdown('SIGINT'))
```

**Ingress for SSR — one key difference:** the Node server does its own routing, so no `try_files` fallback is needed. But you *do* want to offload static assets:

```yaml
metadata:
  annotations:
    # let the Ingress cache /_next/static for 1 year
    nginx.ingress.kubernetes.io/proxy-buffering: "on"
    nginx.ingress.kubernetes.io/configuration-snippet: |
      location /_next/static/ {
        proxy_pass http://upstream_balancer;
        proxy_cache_valid 200 365d;
        add_header Cache-Control "public, max-age=31536000, immutable";
      }
```

Or better — put static assets on a CDN/object storage at build time (`assetPrefix: 'https://cdn.example.com'`) so your Node Pods only render HTML.

</details>

---

## 8.10 Checklist

- [ ] Explain why a production React build ships in an nginx image, not a Node image
- [ ] Write a multi-stage Dockerfile that produces a <30 MB image
- [ ] Explain `try_files $uri $uri/ /index.html` and demonstrate the 404 without it
- [ ] Set `no-store` on `index.html` and `immutable, max-age=1y` on hashed assets
- [ ] Explain the nginx `add_header` inheritance trap
- [ ] Run nginx as non-root with a read-only root filesystem
- [ ] Inject runtime config so one image works in dev/staging/prod
- [ ] Handle `vite:preloadError` so a mid-deploy user isn't stranded
- [ ] Eliminate CORS by serving API and UI from one origin via the Ingress
- [ ] Build a CI pipeline that deploys by digest, scans, signs, smoke-tests and auto-rolls-back
- [ ] Explain what changes when the frontend is an SSR Node server

**Next → [`12-PROJECT-9-java-backend.md`](12-PROJECT-9-java-backend.md)** — Spring Boot on Kubernetes, done properly.

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish%20Kumar%20Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn → <https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260>
🐙 GitHub → <https://github.com/3558Bhk>

*Built for engineers who learn by breaking things on purpose.*

</div>
