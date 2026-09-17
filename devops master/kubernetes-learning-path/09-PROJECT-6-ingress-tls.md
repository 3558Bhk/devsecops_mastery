# 🌐 Project 6 — Ingress, Host Routing & Real TLS

> **Time:** 2.5 hours · **Prereq:** [Project 5](08-PROJECT-5-storage-statefulset.md)
>
> **What you'll learn:** how to expose many services behind one hostname-routed entry point, why your Ingress returns 404, how to get real certificates with cert-manager, and a first look at Gateway API.
>
> **By the end:** `https://shop.local` → frontend, `https://shop.local/api` → backend, both with a valid cert, all on your laptop.

---

## 6.1 The 60-second theory

```
Internet ─► Cloud LB ─► Ingress Controller (nginx Pods)  ─┬─► Service web ─► Pods
                          ▲                               ├─► Service api ─► Pods
                          │ reads Ingress objects         └─► Service admin ─► Pods
                          │
                       Ingress (a config resource: "route host X path Y to service Z")
```

Two things people conflate:

| | What it is | Without the other |
|---|---|---|
| **`kind: Ingress`** | A *configuration object* — routing rules | Inert YAML; nothing happens |
| **Ingress Controller** | A *Deployment* that watches Ingress objects and programs a real proxy (nginx/Envoy/HAProxy) | Your app is unreachable from outside |

> 🔑 **An Ingress resource does nothing without a controller.** If you `kubectl apply` an Ingress and `ADDRESS` stays empty and nothing routes, that's why. It's the #1 Ingress problem.

Why not just `type: LoadBalancer` per service? Because each one provisions a **separate cloud load balancer** with its own public IP — $15–20/month each on AWS. An Ingress gives you **one** LB routing to hundreds of services by host and path.

---

## 6.2 Step 1 — Install an Ingress controller

Pick the one matching your cluster:

### kind

You need port mappings in the cluster config **before** creating the cluster ([Guide §0.2](01-KUBERNETES-GUIDE.md#option-a--kind-recommended)):

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod --selector=app.kubernetes.io/component=controller \
  --timeout=180s
```

Then `http://localhost/` (port 80 mapped) reaches the controller.

### minikube

```bash
minikube addons enable ingress
minikube tunnel &        # separate terminal — gives LoadBalancer services real IPs
kubectl get pods -n ingress-nginx
```

### Any cluster (cloud)

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.13.1/deploy/static/provider/cloud/deploy.yaml
```

### Helm (the production way)

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm show values ingress-nginx/ingress-nginx > ingress-values.yaml

helm install ingress ingress-nginx/ingress-nginx \
  -n ingress-nginx --create-namespace \
  -f ingress-values.yaml
```

Key values you'll want in production:

```yaml
controller:
  replicaCount: 3
  service:
    type: LoadBalancer
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-type: nlb
      service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing
  resources:
    requests: {cpu: 500m, memory: 512Mi}
    limits:   {cpu: "2",   memory: 2Gi}
  metrics:
    enabled: true
    serviceMonitor:
      enabled: true                # needs the Prometheus Operator CRDs
  config:
    use-forwarded-headers: "true"
    compute-full-forwarded-for: "true"
    enable-real-ip: "true"
    proxy-body-size: "50m"
    ssl-protocols: "TLSv1.2 TLSv1.3"
    log-format-upstream: '$remote_addr - $request_id [$time_local] "$request" $status $body_bytes_sent "$http_referer" "$http_user_agent" $request_length $request_time [proxy] $proxy_upstream_name $upstream_addr $upstream_response_length $upstream_response_time $upstream_status'
  autoscaling:
    enabled: true
    minReplicas: 3
    maxReplicas: 20
    targetCPUUtilizationPercentage: 70
  topologySpreadConstraints:
    - maxSkew: 1
      topologyKey: topology.kubernetes.io/zone
      whenUnsatisfiable: ScheduleAnyway
      labelSelector: {matchLabels: {app.kubernetes.io/name: ingress-nginx, app.kubernetes.io/component: controller}}
```

### Verify

```bash
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx
kubectl get ingressclass
```

```
NAME    CONTROLLER             PARAMETERS   AGE
nginx   k8s.io/ingress-nginx   <none>       5m
```

```bash
# the controller exposes a health endpoint
kubectl -n ingress-nginx port-forward svc/ingress-nginx-controller 10254:10254 &
sleep 2 && curl -s localhost:10254/healthz && kill %1
# ok
```

---

## 6.3 Step 2 — Deploy something to route to

Three tiny services that identify themselves:

```bash
mkdir -p ~/k8s-learn/p6 && cd ~/k8s-learn/p6

for svc in web api admin; do
  kubectl create deployment $svc --image=nginx:1.29-alpine --replicas=2
  kubectl expose deployment $svc --port=80 --target-port=80
  kubectl patch deployment $svc --type=json -p="[{\"op\":\"add\",\"path\":\"/spec/template/spec/containers/0/lifecycle\",\"value\":{\"postStart\":{\"exec\":{\"command\":[\"/bin/sh\",\"-c\",\"echo '<h1>SERVICE: $svc</h1><p>pod: '$(hostname)'</p>' > /usr/share/nginx/html/index.html\"]}}}]"
done
kubectl rollout status deploy/web && kubectl rollout status deploy/api && kubectl rollout status deploy/admin
kubectl get deploy,svc,pods -o wide
```

Sanity-check them internally first — **always do this before blaming the Ingress**:

```bash
kubectl run t --rm -it --image=nicolaka/netshoot --restart=Never -- bash
# inside:
curl -s http://web/ | head -2
curl -s http://api/ | head -2
curl -s http://admin/ | head -2
exit
```

If those fail, the problem is the Service, not the Ingress. `kubectl get endpointslices` → [Project 2 §2.4](05-PROJECT-2-deployment-service.md).

---

## 6.4 Step 3 — Your first Ingress (host-based routing)

`ingress.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: shop
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"    # keep it simple for now
spec:
  ingressClassName: nginx            # ⭐ ALWAYS set this explicitly
  rules:
    - host: web.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: web
                port:
                  number: 80
    - host: api.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service: {name: api, port: {number: 80}}
    - host: admin.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service: {name: admin, port: {number: 80}}
```

```bash
kubectl apply -f ingress.yaml
kubectl get ingress
```

```
NAME   CLASS   HOSTS                              ADDRESS      PORTS   AGE
shop   nginx   web.local,api.local,admin.local    172.18.0.2   80      10s
```

> ⚠️ If `ADDRESS` is empty after a minute:
> - No Ingress controller → §6.2
> - Wrong `ingressClassName` → `kubectl get ingressclass`
> - The controller isn't watching this namespace → check its `--watch-namespace` arg
> - `kubectl describe ingress shop` and `kubectl -n ingress-nginx logs deploy/ingress-nginx-controller` will say why

### Test it — no DNS needed

```bash
kubectl get svc -n ingress-nginx
# ingress-nginx-controller   LoadBalancer   10.96.x.x   172.18.0.2   80:31234/TCP,443:31235/TCP

LB_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo $LB_IP

# route by the Host header — this is exactly what the controller matches on
curl -s -H "Host: web.local"   http://$LB_IP/ | head -2
curl -s -H "Host: api.local"   http://$LB_IP/ | head -2
curl -s -H "Host: admin.local" http://$LB_IP/ | head -2
curl -s -H "Host: nope.local"  http://$LB_IP/ -o /dev/null -w '%{http_code}\n'   # 404
```

```html
<h1>SERVICE: web</h1>
<h1>SERVICE: api</h1>
<h1>SERVICE: admin</h1>
404
```

**That last 404 is important** — the controller matched no rule, so it returned its own default backend. That's how you'll recognise a misconfigured host.

### Now make the hosts real

```bash
# Linux / macOS
echo "$LB_IP web.local api.local admin.local" | sudo tee -a /etc/hosts
curl -s http://web.local/ | head -2

# kind: the LB IP is inside the docker network, so map to localhost instead
echo "127.0.0.1 web.local api.local admin.local" | sudo tee -a /etc/hosts
curl -s http://web.local:8080/ | head -2      # if you mapped hostPort 8080 → 80

# zero-config alternative: nip.io / sslip.io wildcard DNS
#   <anything>.<ip-with-dashes>.nip.io resolves to that IP
curl -s -H "Host: web.172-18-0-2.nip.io" http://$LB_IP/
```

### Path-based routing (one host, many services)

`ingress-paths.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: shop-paths
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
spec:
  ingressClassName: nginx
  rules:
    - host: shop.local
      http:
        paths:
          # ⭐ more specific paths first — nginx matches longest prefix, but be explicit
          - path: /api
            pathType: Prefix
            backend: {service: {name: api, port: {number: 80}}}
          - path: /admin
            pathType: Prefix
            backend: {service: {name: admin, port: {number: 80}}}
          - path: /
            pathType: Prefix
            backend: {service: {name: web, port: {number: 80}}}
```

```bash
kubectl apply -f ingress-paths.yaml
curl -s -H "Host: shop.local" http://$LB_IP/        | head -1   # web
curl -s -H "Host: shop.local" http://$LB_IP/api     | head -1   # api
curl -s -H "Host: shop.local" http://$LB_IP/admin   | head -1   # admin
```

### `pathType` — the three options

| Type | Behaviour |
|---|---|
| `Exact` | Case-sensitive exact match. `/api` matches `/api` only, not `/api/` or `/api/v1` |
| `Prefix` | Matches on **`/`-separated elements**. `/api` matches `/api`, `/api/`, `/api/v1`, but **not** `/apifoo` |
| `ImplementationSpecific` | Controller decides. Required for regex/capture groups |

Demonstrate:

```bash
curl -s -o /dev/null -w '%{http_code} ' -H "Host: shop.local" http://$LB_IP/api      # 200
curl -s -o /dev/null -w '%{http_code} ' -H "Host: shop.local" http://$LB_IP/api/v1   # 200
curl -s -o /dev/null -w '%{http_code} ' -H "Host: shop.local" http://$LB_ID/apifoo   # 200 (falls to /)
```

### Stripping a path prefix (the classic SPA/API problem)

Your API serves `/health`, but the Ingress exposes it at `/api/health`. Rewrite:

```yaml
metadata:
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /$2
spec:
  rules:
    - host: shop.local
      http:
        paths:
          - path: /api(/|$)(.*)            # ⭐ capture groups
            pathType: ImplementationSpecific
            backend: {service: {name: api, port: {number: 80}}}
```

`/api/health` → `/$2` = `/health` → forwarded to the api Service as `/health`.
`/api` → `/$2` = `` → `/` (the `(/|$)` handles the no-trailing-slash case).

```bash
curl -s -H "Host: shop.local" http://$LB_IP/api/health
kubectl -n ingress-nginx logs deploy/ingress-nginx-controller --tail=5
# … "GET /api/health HTTP/1.1" 200 … [proxy] http://shop-api-80/health   ← the rewritten target
```

---

## 6.5 Step 4 — The annotations you'll actually use

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: production-ingress
  annotations:
    # ── TLS / redirects ──
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"       # even if TLS is terminated upstream
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"        # or GRPC / GRPCS / AJP / FCGI
    cert-manager.io/cluster-issuer: "letsencrypt-prod"

    # ── request size & timeouts (the "413" and "504" fixers) ──
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"           # default 1m ⭐
    nginx.ingress.kubernetes.io/proxy-connect-timeout: "5"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "120"        # default 60
    nginx.ingress.kubernetes.io/proxy-send-timeout: "120"

    # ── buffering (disable for streaming / SSE / websockets-with-long-poll) ──
    nginx.ingress.kubernetes.io/proxy-buffering: "off"
    nginx.ingress.kubernetes.io/proxy-request-buffering: "off"

    # ── rate limiting ──
    nginx.ingress.kubernetes.io/limit-rps: "50"
    nginx.ingress.kubernetes.io/limit-rpm: "1000"
    nginx.ingress.kubernetes.io/limit-connections: "10"
    nginx.ingress.kubernetes.io/limit-whitelist: "10.0.0.0/8"

    # ── access control ──
    nginx.ingress.kubernetes.io/whitelist-source-range: "203.0.113.0/24,198.51.100.7/32"
    nginx.ingress.kubernetes.io/denylist-source-range: "192.0.2.0/24"
    nginx.ingress.kubernetes.io/auth-type: basic
    nginx.ingress.kubernetes.io/auth-secret: admin-basic-auth
    nginx.ingress.kubernetes.io/auth-realm: "Authentication Required"
    # external auth (oauth2-proxy, Authelia)
    nginx.ingress.kubernetes.io/auth-url: "https://auth.example.com/oauth2/auth"
    nginx.ingress.kubernetes.io/auth-signin: "https://auth.example.com/oauth2/start"

    # ── CORS ──
    nginx.ingress.kubernetes.io/enable-cors: "true"
    nginx.ingress.kubernetes.io/cors-allow-origin: "https://shop.example.com"
    nginx.ingress.kubernetes.io/cors-allow-methods: "GET, POST, PUT, DELETE, OPTIONS"
    nginx.ingress.kubernetes.io/cors-allow-credentials: "true"
    nginx.ingress.kubernetes.io/cors-max-age: "600"

    # ── headers ──
    nginx.ingress.kubernetes.io/configuration-snippet: |
      more_set_headers "X-Frame-Options: DENY";
      more_set_headers "X-Content-Type-Options: nosniff";
      more_set_headers "Strict-Transport-Security: max-age=31536000; includeSubDomains";
      more_set_headers "Referrer-Policy: strict-origin-when-cross-origin";
    nginx.ingress.kubernetes.io/server-snippet: |
      location = /nginx_status { stub_status on; access_log off; allow 127.0.0.1; deny all; }

    # ── canary (built into ingress-nginx!) ──
    nginx.ingress.kubernetes.io/canary: "true"
    nginx.ingress.kubernetes.io/canary-weight: "10"                          # 10% of traffic
    nginx.ingress.kubernetes.io/canary-by-header: "X-Canary"                 # header-based
    nginx.ingress.kubernetes.io/canary-by-header-value: "always"
    nginx.ingress.kubernetes.io/canary-by-cookie: "canary"

    # ── app-root / custom errors ──
    nginx.ingress.kubernetes.io/app-root: "/home"
    nginx.ingress.kubernetes.io/custom-http-errors: "502,503,504"
```

> ⚠️ `configuration-snippet` and `server-snippet` are **disabled by default** since ingress-nginx v1.9 (CVE-2023-5043/5044 — IngressNightmare). If you get
> `Snippet directives are disabled by administrator`, either enable them cluster-wide (`allow-snippet-annotations: "true"`) or, much better, use the typed annotations / a `ConfigMap` on the controller.

**Controller-wide defaults** live in a ConfigMap, not annotations:

```bash
kubectl -n ingress-nginx get cm ingress-nginx-controller -o yaml
```

```yaml
data:
  use-forwarded-headers: "true"
  proxy-body-size: "20m"
  ssl-protocols: "TLSv1.2 TLSv1.3"
  server-tokens: "false"
  log-format-upstream: "..."
  keep-alive: "75"
  worker-processes: "auto"
```

### Canary with two Ingresses

```yaml
# stable — the normal Ingress
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata: {name: api-stable}
spec:
  ingressClassName: nginx
  rules:
    - host: shop.local
      http:
        paths: [{path: /api, pathType: Prefix, backend: {service: {name: api-v1, port: {number: 80}}}}]
---
# canary — same host/path, plus canary annotations
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api-canary
  annotations:
    nginx.ingress.kubernetes.io/canary: "true"
    nginx.ingress.kubernetes.io/canary-weight: "10"
spec:
  ingressClassName: nginx
  rules:
    - host: shop.local
      http:
        paths: [{path: /api, pathType: Prefix, backend: {service: {name: api-v2, port: {number: 80}}}}]
```

```bash
for i in $(seq 1 200); do curl -s -H "Host: shop.local" http://$LB_IP/api; done | sort | uniq -c
#    181 SERVICE: api-v1
#     19 SERVICE: api-v2      ≈ 10%
```

Header-based canary (deterministic — great for testing):

```bash
curl -s -H "Host: shop.local" -H "X-Canary: always" http://$LB_IP/api   # always v2
```

---

## 6.6 Step 5 — TLS with a self-signed cert (5 minutes, no internet)

```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout tls.key -out tls.crt \
  -subj "/CN=shop.local/O=Learn Ltd" \
  -addext "subjectAltName=DNS:shop.local,DNS:web.local,DNS:api.local,DNS:admin.local,DNS:*.local"

kubectl create secret tls shop-tls --cert=tls.crt --key=tls.key
kubectl get secret shop-tls -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -text | grep -A1 "Subject Alternative Name"
```

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: shop-tls
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
    - hosts: [shop.local, web.local, api.local, admin.local]
      secretName: shop-tls          # ⭐ must be in the SAME namespace as the Ingress
  rules:
    - host: shop.local
      http:
        paths:
          - {path: /api,   pathType: Prefix, backend: {service: {name: api,   port: {number: 80}}}}
          - {path: /admin, pathType: Prefix, backend: {service: {name: admin, port: {number: 80}}}}
          - {path: /,      pathType: Prefix, backend: {service: {name: web,   port: {number: 80}}}}
```

```bash
kubectl apply -f ingress-tls.yaml
curl -sk https://$LB_IP/ -H "Host: shop.local" | head -1
curl -sk --resolve shop.local:443:$LB_IP https://shop.local/api | head -1

# inspect the served certificate
echo | openssl s_client -connect $LB_IP:443 -servername shop.local 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates

# prove the HTTP → HTTPS redirect works
curl -sI -H "Host: shop.local" http://$LB_IP/ | head -5
# HTTP/1.1 308 Permanent Redirect
# Location: https://shop.local/
```

> ⚠️ **The TLS Secret must be in the same namespace as the Ingress** that references it. Cross-namespace TLS requires a `ReferenceGrant` (Gateway API) or a Secret-mirroring tool.

---

## 6.7 Step 6 — cert-manager: real, auto-renewing certificates

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml
kubectl get pods -n cert-manager
```

```
NAME                                       READY   STATUS    RESTARTS   AGE
cert-manager-7d9f8b6c5d-x2k4j              1/1     Running   0          60s
cert-manager-cainjector-6c5d4b3a2f-mn3p8   1/1     Running   0          60s
cert-manager-webhook-5b4c3d2e1f-qw7rt      1/1     Running   0          60s
```

> ⚠️ **If you get `failed calling webhook "webhook.cert-manager.io"` right after install**, the webhook isn't ready yet. Wait ~60 s and retry. This is the most common cert-manager installation complaint.

### The three cert-manager objects

```
Issuer / ClusterIssuer   "here's how to get certificates"   (ACME server, CA, Vault, self-signed…)
        │
        ▼
Certificate             "I want a cert for these DNS names, stored in this Secret"
        │ creates
        ▼
CertificateRequest → Order → Challenge   (the ACME dance — HTTP-01 or DNS-01)
```

### Self-signed ClusterIssuer (for local dev with automatic certs)

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata: {name: selfsigned}
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata: {name: local-ca, namespace: cert-manager}
spec:
  isCA: true
  commonName: local-ca
  secretName: local-ca-secret
  privateKey: {algorithm: ECDSA, size: 256}
  issuerRef: {name: selfsigned, kind: ClusterIssuer}
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata: {name: local-ca}
spec:
  ca:
    secretName: local-ca-secret      # ← issues certs signed by the CA above
```

```bash
kubectl apply -f local-ca.yaml
kubectl get clusterissuers
kubectl get certificate -n cert-manager
```

Now any Ingress with `cert-manager.io/cluster-issuer: local-ca` gets a cert your laptop can trust (import `local-ca-secret`'s CA into your OS/browser trust store).

### Let's Encrypt for real domains

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata: {name: letsencrypt-staging}       # ⭐ START HERE — staging has generous rate limits
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: you@example.com                    # required: expiry & rate-limit notices
    privateKeySecretRef: {name: letsencrypt-staging-account-key}
    solvers:
      - selector: {}
        http01:
          ingress:
            ingressClassName: nginx
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata: {name: letsencrypt-prod}
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: you@example.com
    privateKeySecretRef: {name: letsencrypt-prod-account-key}
    solvers:
      - selector: {}
        http01:
          ingress:
            ingressClassName: nginx
      # wildcard certs REQUIRE dns01:
      - selector:
          dnsZones: ["example.com"]
          dnsNames: ["*.example.com"]
        dns01:
          route53:
            region: ap-south-1
            hostedZoneID: Z1234567890
            accessKeyIDSecretRef: {name: aws-creds, key: access-key-id}
            secretAccessKeySecretRef: {name: aws-creds, key: secret-access-key}
          # cloudflare: {apiTokenSecretRef: {name: cf-token, key: api-token}}
          # digitalocean: {tokenSecretRef: {name: do-token, key: access-token}}
```

> 🔑 **HTTP-01 vs DNS-01:**
> | | HTTP-01 | DNS-01 |
> |---|---|---|
> | How | Let's Encrypt fetches `http://your-domain/.well-known/acme-challenge/<token>` | Let's Encrypt looks up `_acme-challenge.your-domain` TXT record |
> | Needs | Public DNS pointing at the Ingress + port 80 open | DNS provider API credentials |
> | Wildcards (`*.example.com`) | ❌ Not possible | ✅ Required |
> | Internal/private domains | ❌ | ✅ |
> | Rate limit | 5 duplicate certs per FQDN set per week (prod) | same, but staging is unlimited |
>
> **Always test with `letsencrypt-staging` first.** Production rate limits are brutal and there's no appeal process.

### Annotate the Ingress and let cert-manager do everything

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: shop-real
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod    # ⭐ that's it
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
    - hosts: [shop.example.com]
      secretName: shop-example-com-tls     # ← cert-manager CREATES this secret
  rules:
    - host: shop.example.com
      http:
        paths:
          - {path: /, pathType: Prefix, backend: {service: {name: web, port: {number: 80}}}}
```

```bash
kubectl apply -f ingress-real.yaml

# watch the whole ACME dance
kubectl get certificate,certificaterequest,order,challenge -A
```

```
NAME                                    READY   SECRET                   AGE
certificate.cert-manager.io/shop-…      True    shop-example-com-tls     90s

NAME                                            APPROVED   DENIED   READY   ISSUER   AGE
certificaterequest.cert-manager.io/shop-…-x2k   True                True    le-prod  90s

NAME                                                     STATE     AGE
order.acme.cert-manager.io/shop-…-x2k-1234567890         valid     90s
```

```bash
kubectl describe certificate shop-example-com-tls | sed -n '/Conditions:/,$p'
kubectl get secret shop-example-com-tls -o jsonpath='{.data.tls\.crt}' | base64 -d \
  | openssl x509 -noout -subject -issuer -dates
```

Renewal is automatic — cert-manager renews at 2/3 of the certificate lifetime (Let's Encrypt: 90-day cert, renewed at ~day 60).

```bash
kubectl get certificate -A -o custom-columns='NAME:.metadata.name,READY:.status.conditions[0].status,NOT_AFTER:.status.notAfter,RENEWAL:.status.renewalTime'
# force a renewal to test it
kubectl get certificate -A -o json | jq -r '.items[0].metadata.name' | xargs -I{} cmctl renew {} -n <ns>
```

### When a certificate won't issue

```bash
kubectl describe certificate shop-example-com-tls
kubectl describe challenge -A            # ← the actual ACME error is HERE
kubectl get challenges -A -o json | jq '.items[].status | {processing, reason, state, presented}'
kubectl logs -n cert-manager deploy/cert-manager --tail=100
kubectl -n ingress-nginx logs deploy/ingress-nginx-controller --tail=50 | grep acme
```

| `reason` / message | Cause | Fix |
|---|---|---|
| `unauthorized … 404` on the challenge path | The HTTP-01 solver Ingress isn't reachable | DNS must point at the LB; port 80 must be open; no firewall |
| `no such host` / `DNS problem: NXDOMAIN` | DNS not published or wrong | Point the A/CNAME record at the Ingress LB IP |
| `Timeout during connect` | Firewall / security group blocks :80 | Open :80 to `0.0.0.0/0` (Let's Encrypt validates from many IPs) |
| `too many certificates already issued` | Rate limit hit | Use staging while testing; wait a week |
| `wrong status code ... 301` | A redirect is eating the challenge | Exclude `/.well-known/acme-challenge/` from `ssl-redirect` |
| `TLS-ALPN-01 … incorrect certificate` | Another LB terminates TLS in front | Use HTTP-01 or DNS-01 |
| `secret "..." not found` (dns01) | Missing DNS provider credentials | Create the referenced Secret with the right keys |
| `challenge in failed state` | Solver misconfigured | `kubectl delete challenge <name>` to retry cleanly |

**The redirect-eats-the-challenge fix** (very common):

```yaml
metadata:
  annotations:
    nginx.ingress.kubernetes.io/server-snippet: |
      location /.well-known/acme-challenge/ {
        allow all;
        return 301 http://$host$request_uri;    # keep HTTP for the challenge
      }
```
Or simply set `ssl-redirect: "false"` on the Ingress and let cert-manager's own solver Ingress handle HTTP.

---

## 6.8 Step 7 — Everything else an Ingress needs in production

### Default backend, custom errors, health

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: catch-all
spec:
  ingressClassName: nginx
  rules:
    - http:                                  # ← NO host = matches everything unmatched
        paths:
          - path: /
            pathType: Prefix
            backend: {service: {name: custom-404, port: {number: 80}}}
```

### WebSockets

ingress-nginx supports WebSockets automatically when the client sends `Upgrade`. To be explicit:

```yaml
metadata:
  annotations:
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-buffering: "off"
    nginx.ingress.kubernetes.io/configuration-snippet: |
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection "upgrade";
```

```bash
wscat -c wss://shop.example.com/ws           # brew install wscat
```

### gRPC

```yaml
metadata:
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "GRPC"      # or GRPCS
spec:
  tls: [{hosts: [grpc.example.com], secretName: grpc-tls}]     # gRPC REQUIRES TLS on ingress-nginx
  rules:
    - host: grpc.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend: {service: {name: grpc-api, port: {number: 9000}}}
```

```bash
grpcurl -plaintext grpc-api.default.svc.cluster.local:9000 list         # in-cluster
grpcurl grpc.example.com:443 list                                       # via Ingress
```

### Client certificate auth (mTLS)

```yaml
metadata:
  annotations:
    nginx.ingress.kubernetes.io/auth-tls-verify-client: "on"
    nginx.ingress.kubernetes.io/auth-tls-secret: "prod/ca-certificate"
    nginx.ingress.kubernetes.io/auth-tls-verify-depth: "2"
    nginx.ingress.kubernetes.io/auth-tls-pass-certificate-to-upstream: "true"
```

### Real client IPs behind another LB

```yaml
# controller ConfigMap
data:
  use-forwarded-headers: "true"
  compute-full-forwarded-for: "true"
  enable-real-ip: "true"
  forwarded-for-header: "X-Forwarded-For"
  proxy-real-ip-cidr: "10.0.0.0/8"          # trust only these
```

Without this, every log line shows the upstream LB's IP.

### Ingress-level observability

```bash
kubectl -n ingress-nginx logs deploy/ingress-nginx-controller --tail=100 -f
kubectl -n ingress-nginx logs deploy/ingress-nginx-controller | jq -c 'select(.status>=500)'
kubectl -n ingress-nginx exec deploy/ingress-nginx-controller -- nginx -T | less    # the FULL generated config
kubectl -n ingress-nginx exec deploy/ingress-nginx-controller -- nginx -T | grep -A30 'server_name shop.local'
kubectl -n ingress-nginx exec deploy/ingress-nginx-controller -- curl -s localhost:10246/nginx_status
kubectl -n ingress-nginx exec deploy/ingress-nginx-controller -- curl -s localhost:10254/metrics | head -30
kubectl get ingress -A -o wide
kubectl describe ingress shop
```

`nginx -T` is the ultimate debugging tool — it shows exactly what the controller generated from your Ingress objects. If your rule isn't in there, the controller didn't accept your Ingress.

---

## 6.9 Step 8 — Gateway API (the successor, worth 20 minutes)

Ingress's limits: no typed config (everything is a string annotation), no traffic splitting, no cross-namespace ownership model, no standard for TCP/UDP.

Gateway API splits responsibilities:

| Object | Owner | Analogy |
|---|---|---|
| `GatewayClass` | Infra vendor | "nginx", "istio", "envoy-gateway" |
| `Gateway` | Cluster operator | The listener: port, protocol, TLS cert, allowed hostnames |
| `HTTPRoute` | App developer | The routing rules attached to a Gateway |
| `ReferenceGrant` | Namespace owner | "I permit that namespace to reference my Service" |

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.3.0/standard-install.yaml
kubectl get crds | grep gateway.networking.k8s.io

# install a Gateway API implementation
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
# or Envoy Gateway:
helm repo add envoy-gateway https://storage.googleapis.com/envoy-gateway-helm-charts
helm install eg envoy-gateway/envoy-gateway -n envoy-gateway-system --create-namespace
kubectl get gatewayclass
```

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: {name: shop-gw, namespace: infra}
spec:
  gatewayClassName: eg                    # or nginx
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      allowedRoutes:
        namespaces: {from: Selector, selector: {matchLabels: {team: shop}}}
    - name: https
      protocol: HTTPS
      port: 443
      hostname: "*.example.com"
      tls:
        mode: Terminate
        certificateRefs: [{kind: Secret, name: wildcard-tls, namespace: infra}]
      allowedRoutes: {namespaces: {from: All}}
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: api, namespace: shop}
spec:
  parentRefs: [{name: shop-gw, namespace: infra, sectionName: https}]
  hostnames: ["api.example.com"]
  rules:
    # ── path routing with a rewrite ──
    - matches: [{path: {type: PathPrefix, value: /v1}}]
      filters:
        - type: URLRewrite
          urlRewrite: {path: {type: ReplacePrefixMatch, replacePrefixMatch: /}}
        - type: RequestHeaderModifier
          requestHeaderModifier: {set: [{name: X-Tier, value: "v1"}]}
      backendRefs:
        - {name: api-v1, port: 80, weight: 90}
        - {name: api-v2, port: 80, weight: 10}     # ⭐ typed canary — no annotations
    # ── header-based routing ──
    - matches:
        - headers: [{name: X-User-Tier, value: beta}]
      backendRefs: [{name: api-beta, port: 80}]
    # ── mirror traffic for shadow testing ──
    - matches: [{path: {type: PathPrefix, value: /}}]
      backendRefs:
        - {name: api, port: 80}
        - {name: api-shadow, port: 80, weight: 0}   # 0 weight + a mirror filter
```

```bash
kubectl get gateway,httproute -A
kubectl describe gateway shop-gw -n infra     # conditions: Programmed, Accepted
kubectl describe httproute api -n shop
```

**Learn Ingress first** — it's everywhere and isn't going away. But know that new capabilities (weighted canaries, traffic mirroring, typed policies, cross-namespace delegation) land in Gateway API, and ingress-nginx is now in maintenance mode with Gateway API as its strategic direction.

---

## 6.10 Step 9 — Ingress troubleshooting playbook

### `404 Not Found`

```bash
kubectl describe ingress shop
kubectl get ingress -A -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,CLASS:.spec.ingressClassName,HOSTS:.spec.rules[*].host'
```

| Check | Command |
|---|---|
| Is `ingressClassName` set and correct? | `kubectl get ingressclass` |
| Does the `host` match the request's `Host` header **exactly**? | `curl -v -H "Host: shop.local"` — check what curl actually sent |
| Is the controller watching this namespace? | `kubectl -n ingress-nginx get deploy -o yaml | grep watch-namespace` |
| Is the Ingress `Accepted`? | `kubectl describe ingress` → Events |
| Is your rule in the generated nginx config? | `kubectl -n ingress-nginx exec deploy/ingress-nginx-controller -- nginx -T | grep -B2 -A20 'server_name shop.local'` |
| Are you hitting the right LB/port? | `kubectl get svc -n ingress-nginx` |

The most common: **you `curl` without a `Host` header**, so the controller falls through to the default backend. Always test with `-H "Host: …"`.

### `502 Bad Gateway`

The controller reached a backend and got refused/reset.

```bash
kubectl get endpointslices -l kubernetes.io/service-name=api
kubectl get pods -l app=api -o wide
kubectl exec -n ingress-nginx deploy/ingress-nginx-controller -- \
  curl -sv http://api.default.svc.cluster.local/ | head -20
kubectl -n ingress-nginx logs deploy/ingress-nginx-controller --tail=100 | grep -E ' 502 |upstream'
```

Causes: wrong `targetPort` · Pods not listening yet · backend protocol mismatch (`backend-protocol: HTTPS` when it's HTTP) · app crashing under the request · `proxy_connect_timeout` too low.

### `503 Service Unavailable`

No ready endpoints.

```bash
kubectl get endpointslices -l kubernetes.io/service-name=api
# empty → readiness probe failing, or selector mismatch
kubectl get pods -l app=api          # READY 0/1?
kubectl describe pod <pod> | grep -A5 Readiness
```

### `504 Gateway Timeout`

```bash
kubectl -n ingress-nginx logs deploy/ingress-nginx-controller --tail=50 | grep 504
# raise the timeout, then fix the slow endpoint
kubectl annotate ingress shop nginx.ingress.kubernetes.io/proxy-read-timeout="300" --overwrite
```

### `413 Request Entity Too Large`

```bash
kubectl annotate ingress shop nginx.ingress.kubernetes.io/proxy-body-size="100m" --overwrite
```

### TLS problems

```bash
# what cert is actually served?
echo | openssl s_client -connect shop.example.com:443 -servername shop.example.com 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates -ext subjectAltName

kubectl get certificate -A
kubectl describe certificate <name>
kubectl get secret <tls-secret> -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -text | head -20
```

| Error | Cause |
|---|---|
| `Kubernetes Ingress Controller Mock Certificate` | The Secret doesn't exist or is in the wrong namespace → the controller serves its fake default cert |
| `certificate has expired` | Renewal broken → `kubectl describe certificaterequest` |
| `Hostname mismatch` | The cert's SANs don't include the requested host |
| `unable to get local issuer certificate` | Missing CA chain — your Secret must contain the **full chain** (`cat your.crt intermediate.crt > tls.crt`) |

### Controller-level problems

```bash
kubectl get pods -n ingress-nginx
kubectl -n ingress-nginx describe pod <controller-pod> | sed -n '/Events:/,$p'
kubectl -n ingress-nginx logs <controller-pod> --tail=200
kubectl -n ingress-nginx logs <controller-pod> | grep -iE 'error|failed|reload'
kubectl -n ingress-nginx top pod
kubectl -n ingress-nginx exec deploy/ingress-nginx-controller -- nginx -t     # config valid?
```

A controller stuck reloading: check for conflicting Ingresses (same host+path in two Ingresses → "duplicate location" errors), invalid annotation values, or a `configuration-snippet` with a syntax error.

```bash
kubectl -n ingress-nginx logs deploy/ingress-nginx-controller | grep -i 'duplicate\|invalid\|emerg'
```

---

## 6.11 Extra Tasks

### Task 6.1 — Expose a full stack behind one hostname with TLS and path routing

Frontend at `/`, API at `/api`, admin at `/admin`, with basic auth on `/admin`, rate limiting on `/api`, and a real cert.

<details>
<summary>Show answer</summary>

```yaml
# ── basic-auth secret for /admin ──
# htpasswd -c auth admin        (brew install httpd, or: openssl passwd -apr1 'S3cret')
apiVersion: v1
kind: Secret
metadata: {name: admin-basic-auth}
type: Opaque
data:
  auth: YWRtaW46JGFwcjEkVVRaOFRBRy4uLi4uLi4uLi4uLi4=     # admin:S3cret
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: shop-main
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
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
            backend: {service: {name: api, port: {number: 80}}}
---
# ── SEPARATE Ingress for /api so it can carry its own annotations ──
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: shop-api
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/rewrite-target: /$2
    nginx.ingress.kubernetes.io/limit-rps: "50"
    nginx.ingress.kubernetes.io/limit-connections: "20"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "120"
    nginx.ingress.kubernetes.io/proxy-body-size: "10m"
    nginx.ingress.kubernetes.io/enable-cors: "true"
    nginx.ingress.kubernetes.io/cors-allow-origin: "https://shop.example.com"
spec:
  ingressClassName: nginx
  tls: [{hosts: [shop.example.com], secretName: shop-example-com-tls}]
  rules:
    - host: shop.example.com
      http:
        paths:
          - path: /api(/|$)(.*)
            pathType: ImplementationSpecific
            backend: {service: {name: api, port: {number: 80}}}
---
# ── admin, with basic auth + IP allowlist ──
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: shop-admin
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/auth-type: basic
    nginx.ingress.kubernetes.io/auth-secret: admin-basic-auth
    nginx.ingress.kubernetes.io/auth-realm: "Staff only"
    nginx.ingress.kubernetes.io/whitelist-source-range: "203.0.113.0/24"
spec:
  ingressClassName: nginx
  tls: [{hosts: [shop.example.com], secretName: shop-example-com-tls}]
  rules:
    - host: shop.example.com
      http:
        paths:
          - path: /admin
            pathType: Prefix
            backend: {service: {name: admin, port: {number: 80}}}
---
# ── everything else → the frontend ──
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: shop-web
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls: [{hosts: [shop.example.com], secretName: shop-example-com-tls}]
  rules:
    - host: shop.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend: {service: {name: web, port: {number: 80}}}
```

> 🔑 **Why several Ingress objects instead of one?** Annotations are **per-Ingress**, not per-path. Rate limiting `/api` but not `/` requires separate Ingress objects sharing the same `host`. ingress-nginx merges them into one `server {}` block. This is the single most misunderstood thing about Ingress.

Test:

```bash
LB_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

curl -sk --resolve shop.example.com:443:$LB_IP https://shop.example.com/          # web
curl -sk --resolve shop.example.com:443:$LB_IP https://shop.example.com/api/health # api, rewritten to /health
curl -sk --resolve shop.example.com:443:$LB_IP https://shop.example.com/admin     # 401 Unauthorized
curl -sk --resolve shop.example.com:443:$LB_IP -u admin:S3cret https://shop.example.com/admin  # 200 (if your IP is allowed)

# rate limit proof
for i in $(seq 1 100); do
  curl -sk -o /dev/null -w '%{http_code} ' --resolve shop.example.com:443:$LB_IP https://shop.example.com/api/health
done; echo
# 200 200 … 503 503 503       ← limit-rps kicked in

kubectl get ingress -A
kubectl describe ingress shop-api
```

</details>

---

### Task 6.2 — Debug an Ingress that returns the "fake" certificate

`curl` says `CN=Kubernetes Ingress Controller Mock Certificate`. Find and fix it.

<details>
<summary>Show answer</summary>

That certificate means the controller **could not find a usable TLS Secret** for the requested hostname, so it served its built-in dummy cert. Four causes, in order of likelihood:

```bash
HOST=shop.example.com
NS=prod

# ── Cause 1: the Secret doesn't exist ──
kubectl get secret -n $NS | grep -i tls
kubectl get ingress -n $NS -o jsonpath='{range .items[*]}{.metadata.name}: {.spec.tls}{"\n"}{end}'
# → [{"hosts":["shop.example.com"],"secretName":"shop-tls"}]
kubectl get secret shop-tls -n $NS
# Error from server (NotFound) → create it

# ── Cause 2: the Secret is in the WRONG NAMESPACE ──
kubectl get secret -A | grep shop-tls
# shop-tls is in `default` but the Ingress is in `prod` → ⛔ TLS secrets must be co-located
kubectl get secret shop-tls -n default -o yaml \
  | sed 's/namespace: default/namespace: prod/' \
  | kubectl apply -n $NS -f -

# ── Cause 3: the Secret has the wrong keys or type ──
kubectl get secret shop-tls -n $NS -o jsonpath='{.type}'; echo      # must be kubernetes.io/tls
kubectl get secret shop-tls -n $NS -o json | jq '.data | keys'      # must be ["tls.crt","tls.key"]
# If you see "cert" and "key" → wrong names. Recreate:
kubectl create secret tls shop-tls -n $NS --cert=tls.crt --key=tls.key --dry-run=client -o yaml | kubectl apply -f -

# ── Cause 4: the hostname doesn't match any tls.hosts entry ──
kubectl get ingress -n $NS -o json | jq -r '.items[] | .spec.tls[]? | "\(.secretName): \(.hosts)"'
# you requested www.shop.example.com but tls.hosts is only ["shop.example.com"] → add it
kubectl patch ingress shop-main -n $NS --type=json \
  -p='[{"op":"replace","path":"/spec/tls/0/hosts","value":["shop.example.com","www.shop.example.com"]}]'
```

**Confirm the controller now sees it:**

```bash
kubectl -n ingress-nginx exec deploy/ingress-nginx-controller -- nginx -T \
  | grep -A15 "server_name shop.example.com" | grep ssl_certificate
#   ssl_certificate /ingress-controller/ssl/prod-shop-tls.pem;    ← real secret ✅
#   ssl_certificate /ingress-controller/ssl/default-fake-certificate.pem;   ← ❌ still broken

kubectl -n ingress-nginx logs deploy/ingress-nginx-controller --tail=100 | grep -i 'error obtaining PEM\|secret .* not found'
# "Error obtaining X.509 certificate: secret prod/shop-tls was not found"
```

**And verify the cert itself is valid:**

```bash
kubectl get secret shop-tls -n $NS -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/served.crt
openssl x509 -in /tmp/served.crt -noout -subject -issuer -dates -ext subjectAltName
# subject=CN = shop.example.com
# notAfter=Sep  9 12:00:00 2027 GMT
# X509v3 Subject Alternative Name: DNS:shop.example.com, DNS:www.shop.example.com

# is the chain complete? (a missing intermediate is the #1 "works in Chrome, fails in curl" bug)
openssl verify -CAfile /etc/ssl/certs/ca-certificates.crt /tmp/served.crt
# error: unable to get local issuer certificate → you shipped the leaf only
cat your-domain.crt intermediate.crt > fullchain.crt
kubectl create secret tls shop-tls -n $NS --cert=fullchain.crt --key=your.key \
  --dry-run=client -o yaml | kubectl apply -f -
```

Finally, from the outside:

```bash
echo | openssl s_client -connect shop.example.com:443 -servername shop.example.com -showcerts 2>/dev/null \
  | grep -E '^ [0-9] s:|i:' 
curl -vI https://shop.example.com/ 2>&1 | grep -E 'subject:|issuer:|expire'
```

**Bonus — prevent it:** an alert on the controller's metric `nginx_ingress_controller_ssl_expire_time_seconds`:

```yaml
- alert: IngressCertExpiringSoon
  expr: (nginx_ingress_controller_ssl_expire_time_seconds - time()) / 86400 < 14
  for: 1h
  labels: {severity: warning}
  annotations:
    summary: "TLS cert for {{ $labels.host }} expires in {{ $value }} days"
```

</details>

---

### Task 6.3 — Zero-downtime migration from NodePort to Ingress

Your app is currently exposed on NodePort 30080 and clients hit it directly. Move to an Ingress with no downtime.

<details>
<summary>Show answer</summary>

The safe sequence — **never remove the old path until the new one is proven.**

**Phase 0 — baseline**

```bash
kubectl get svc -o wide
# api   NodePort   10.96.44.12   <none>   8080:30080/TCP
NODE_IP=$(kubectl get node -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}')
[ -z "$NODE_IP" ] && NODE_IP=$(kubectl get node -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
curl -s http://$NODE_IP:30080/health     # current working path — record the response
```

**Phase 1 — add the Ingress alongside (nothing removed)**

```bash
kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
spec:
  ingressClassName: nginx
  rules:
    - host: api.example.com
      http:
        paths:
          - {path: /, pathType: Prefix, backend: {service: {name: api, port: {number: 8080}}}}
EOF
kubectl get ingress api -w     # wait for ADDRESS
```

**Phase 2 — prove the new path works, without moving DNS**

```bash
LB_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl -s -H "Host: api.example.com" http://$LB_IP/health
curl -s --resolve api.example.com:80:$LB_IP http://api.example.com/health
diff <(curl -s http://$NODE_IP:30080/health) <(curl -s --resolve api.example.com:80:$LB_IP http://api.example.com/health) && echo "✅ identical"
```

Run a longer comparison under load:

```bash
hey -z 30s -q 20 -H "Host: api.example.com" http://$LB_IP/health > ingress.txt
hey -z 30s -q 20 http://$NODE_IP:30080/health > nodeport.txt
grep -E 'Requests/sec|99%|Status code distribution' ingress.txt nodeport.txt
```

**Phase 3 — move DNS (low TTL first!)**

```bash
# 24h BEFORE the move: lower the TTL so rollback is fast
aws route53 change-resource-record-sets --hosted-zone-id Z123 --change-batch '{
  "Changes":[{"Action":"UPSERT","ResourceRecordSet":{
    "Name":"api.example.com","Type":"A","TTL":60,
    "ResourceRecords":[{"Value":"'$NODE_IP'"}]}}]}'

# after the TTL has propagated, point at the Ingress LB
aws route53 change-resource-record-sets --hosted-zone-id Z123 --change-batch '{
  "Changes":[{"Action":"UPSERT","ResourceRecordSet":{
    "Name":"api.example.com","Type":"A","TTL":60,
    "ResourceRecords":[{"Value":"'$LB_IP'"}]}}]}'
```

Watch the traffic shift in real time:

```bash
kubectl -n ingress-nginx logs deploy/ingress-nginx-controller -f | grep api.example.com
kubectl top pod -n ingress-nginx
```

Wait **at least 2× the old TTL** before touching anything.

**Phase 4 — add TLS**

```bash
kubectl annotate ingress api cert-manager.io/cluster-issuer=letsencrypt-prod --overwrite
kubectl patch ingress api --type=json \
  -p='[{"op":"add","path":"/spec/tls","value":[{"hosts":["api.example.com"],"secretName":"api-tls"}]}]'
kubectl get certificate api-tls -w
```

Verify:

```bash
curl -sI https://api.example.com/health
echo | openssl s_client -connect api.example.com:443 -servername api.example.com 2>/dev/null \
  | openssl x509 -noout -dates
```

**Phase 5 — force HTTPS, then remove NodePort**

```bash
kubectl annotate ingress api nginx.ingress.kubernetes.io/ssl-redirect="true" --overwrite
curl -sI http://api.example.com/health      # 308 → https
```

Give clients a grace period (a week is reasonable), monitoring the NodePort's traffic:

```bash
# is anything still hitting the NodePort?
kubectl top pod -l app=api
kubectl logs deploy/api --since=24h | grep -c "$NODE_IP" || true
# or check cloud LB/node metrics for port 30080 traffic
```

Then convert:

```bash
kubectl patch svc api -p '{"spec":{"type":"ClusterIP","nodePort":null}}'
kubectl get svc api
# api   ClusterIP   10.96.44.12   <none>   8080/TCP     ← no more :30080
```

**Phase 6 — lock it down**

```bash
# 1. NetworkPolicy: only the ingress controller may reach api
kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: api-allow-ingress-only, namespace: default}
spec:
  podSelector: {matchLabels: {app: api}}
  policyTypes: [Ingress]
  ingress:
    - from:
        - namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: ingress-nginx}}
          podSelector: {matchLabels: {app.kubernetes.io/name: ingress-nginx}}
      ports: [{protocol: TCP, port: 8080}]
EOF
# 2. Close port 30080 in the cloud security group
# 3. Restore the DNS TTL to 300
# 4. Raise the TTL back up and remove the old A record if it's unused
```

**Rollback at any point:**

```bash
kubectl patch svc api -p '{"spec":{"type":"NodePort","ports":[{"port":8080,"targetPort":8080,"nodePort":30080,"protocol":"TCP","name":"http"}]}}'
# and point DNS back at $NODE_IP (still TTL 60, so it takes effect in ~1 minute)
```

**Things that break during this migration (check them):**
- **Health checks:** the cloud LB health-checking NodePort 30080 must be updated to target the Ingress LB.
- **Client IP visibility:** behind an Ingress your app sees the controller's Pod IP, not the client's. Enable `use-forwarded-headers` and read `X-Forwarded-For`.
- **Request size limits:** NodePort had none; ingress-nginx defaults to 1 MB. Set `proxy-body-size`.
- **Timeouts:** NodePort had none; ingress-nginx defaults to 60 s. Long-polling and slow exports need `proxy-read-timeout`.
- **WebSockets:** work by default on ingress-nginx, but timeouts will kill idle connections at 60 s.

</details>

---

### Task 6.4 — Rate-limit and protect an endpoint

Block abuse on a public search endpoint: 5 rps per client IP, burst 10, with a friendly 429.

<details>
<summary>Show answer</summary>

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: search
  annotations:
    # ── rate limits (per client IP by default) ──
    nginx.ingress.kubernetes.io/limit-rps: "5"           # requests/sec sustained
    nginx.ingress.kubernetes.io/limit-burst-multiplier: "2"   # burst = rps × multiplier = 10
    nginx.ingress.kubernetes.io/limit-connections: "5"   # concurrent connections per IP
    nginx.ingress.kubernetes.io/limit-rpm: "200"         # requests/min

    # ── who to trust for the client IP (critical behind a cloud LB) ──
    nginx.ingress.kubernetes.io/enable-real-ip: "true"

    # ── exempt your own infra ──
    nginx.ingress.kubernetes.io/limit-whitelist: "10.0.0.0/8,203.0.113.5/32"

    # ── custom 429 body + status ──
    nginx.ingress.kubernetes.io/custom-http-errors: "429"
    nginx.ingress.kubernetes.io/configuration-snippet: |
      error_page 429 = @too_many;
      location @too_many {
        default_type application/json;
        return 429 '{"error":"rate_limited","message":"Too many requests. Please slow down.","retry_after_seconds":10}';
      }
      # and the Retry-After header on normal responses
      more_set_headers "X-RateLimit-Limit: 5";
spec:
  ingressClassName: nginx
  rules:
    - host: shop.example.com
      http:
        paths:
          - {path: /search, pathType: Prefix, backend: {service: {name: search, port: {number: 80}}}}
```

> ⚠️ `limit-rps` returns **503** by default in ingress-nginx (it uses `limit_req_status 503`). To get a proper 429, set it on the controller ConfigMap:
> ```bash
> kubectl -n ingress-nginx patch cm ingress-nginx-controller --type=merge \
>   -p '{"data":{"limit-req-status-code":"429"}}'
> ```

Test it:

```bash
LB_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# one-off — should pass
curl -s -o /dev/null -w '%{http_code}\n' -H "Host: shop.example.com" http://$LB_IP/search

# hammer it
for i in $(seq 1 60); do
  curl -s -o /dev/null -w '%{http_code} ' -H "Host: shop.example.com" http://$LB_IP/search
done; echo
# 200 200 200 200 429 429 429 200 429 …

# with real load
hey -z 10s -q 50 -c 10 -H "Host: shop.example.com" http://$LB_IP/search
# Status code distribution:  [200] 187   [429] 313
```

Watch the metrics:

```bash
kubectl -n ingress-nginx exec deploy/ingress-nginx-controller -- \
  curl -s localhost:10254/metrics | grep -E 'nginx_ingress_controller_requests\{.*status="(429|503)"' | head
```

**Layered defence — what real protection looks like:**

| Layer | Tool | Protects against |
|---|---|---|
| Edge | Cloudflare / AWS Shield / Cloud Armor | Volumetric DDoS, L3/L4 |
| WAF | AWS WAF / ModSecurity on ingress-nginx | SQLi, XSS, known CVEs |
| Ingress | `limit-rps`, `limit-connections`, IP allowlist | Per-client abuse |
| App | Token bucket per API key/user | Business-level fairness |
| Pod | `resources.limits` + PDB | Blast radius |
| Cluster | HPA | Legitimate spikes |

Enable ModSecurity on ingress-nginx:

```bash
kubectl -n ingress-nginx patch cm ingress-nginx-controller --type=merge -p '{"data":{
  "enable-modsecurity":"true",
  "enable-owasp-modsecurity-crs":"true",
  "modsecurity-snippet":"SecRuleEngine DetectionOnly\nSecAuditLog /dev/stdout\nSecAuditLogFormat JSON"
}}'
```

Start in `DetectionOnly`, watch the audit log for false positives, then switch to `SecRuleEngine On`.

**Application-level rate limiting** (what you should do *anyway*, because the Ingress only sees IPs):

```python
# FastAPI + Redis sliding window
from fastapi import FastAPI, HTTPException, Request
import redis, time

r = redis.Redis(host="redis")
app = FastAPI()

@app.get("/search")
def search(req: Request, q: str):
    key = f"rl:{req.headers.get('x-api-key') or req.client.host}"
    now = time.time()
    pipe = r.pipeline()
    pipe.zremrangebyscore(key, 0, now - 60)
    pipe.zadd(key, {str(now): now})
    pipe.zcard(key)
    pipe.expire(key, 60)
    _, _, count, _ = pipe.execute()
    if count > 100:
        raise HTTPException(429, detail="rate limited", headers={"Retry-After": "60"})
    return {"q": q}
```

</details>

---

## 6.12 Checklist

- [ ] Explain the difference between an `Ingress` resource and an Ingress controller
- [ ] Install and verify an Ingress controller on your cluster
- [ ] Write host-based and path-based routing rules
- [ ] Explain the three `pathType` values and when you need `ImplementationSpecific`
- [ ] Strip a path prefix with `rewrite-target` and capture groups
- [ ] Explain why per-path annotations require separate Ingress objects
- [ ] Create a TLS Secret and serve it; diagnose the "Mock Certificate"
- [ ] Set up cert-manager with a staging ACME issuer and promote to production
- [ ] Explain HTTP-01 vs DNS-01 and when each is required
- [ ] Trace a failing `Certificate` through CertificateRequest → Order → Challenge
- [ ] Diagnose 404 / 502 / 503 / 504 / 413 / TLS errors from the error code alone
- [ ] Read the generated nginx config with `nginx -T`
- [ ] Configure canary by weight and by header
- [ ] Rate-limit an endpoint and return a proper 429
- [ ] Explain what Gateway API adds over Ingress

**Next → [`10-PROJECT-7-observability.md`](10-PROJECT-7-observability.md)** — metrics, Prometheus, Grafana, logging and alerts.

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish%20Kumar%20Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn → <https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260>
🐙 GitHub → <https://github.com/3558Bhk>

*Built for engineers who learn by breaking things on purpose.*

</div>
