# Azure Front Door — Interview Questions

> **Cloud:** Azure · **Category:** Load Balancing & Traffic Management · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~9 min

---

## JSON File Format

Azure Front Door (Standard/Premium) is ARM JSON under `Microsoft.Cdn/profiles` (or the Classic `Microsoft.Network/frontDoors`): origins, origin groups, and routes.

```json
{
  "type": "Microsoft.Cdn/profiles",
  "apiVersion": "2023-05-01",
  "name": "fd-profile",
  "sku": { "name": "Premium_AzureFrontDoor" },
  "properties": {
    "originGroups": [{
      "name": "default",
      "properties": {
        "loadBalancing": { "sampleSize": 4 },
        "healthProbeSettings": { "probePath": "/health", "probeProtocol": "Https" }
      }
    }],
    "origins": [{ "name": "app", "properties": { "hostName": "app.azurewebsites.net" } }],
    "routes": [{ "name": "api", "properties": { "originGroup": { "id": "[...]" }, "patternsToMatch": ["/api/*"] } }]
  }
}
```

**Key fields:** `originGroups` (health probes + load balancing) · `origins` (backends) · `routes` (`patternsToMatch`) · `endpoints` (frontend domains) · `securityPolicies` (WAF) · `ruleSets` (rules engine). Classic Front Door uses `frontendEndpoints`/`routingRules` instead.


## Case A — Basic

**A1. What is Azure Front Door?**
**Answer:** A **global, Layer 7** load balancer and CDN with anycast entry points — providing fast global routing, URL/path-based routing, TLS termination, caching, and integrated **WAF** at the edge.

**A2. What is the difference between Front Door and Traffic Manager?**
**Answer:** Traffic Manager = **DNS-based** routing (no data path, TTL-bound failover). Front Door = **edge proxy** (anycast) that actually forwards traffic — instant failover, WAF, caching, URL rewrite, TLS at the edge.

**A3. What are the main Front Door components?**
**Answer:** **Frontend endpoints/domains** (anycast entry), **origin groups** (backends with health probes), **routes** (path → origin group), **rule sets** (rewrite/redirect/header engine), **WAF policy**, and **caching** settings.

**A4. What is an origin and an origin group?**
**Answer:** An **origin** is a backend (App Service, VM, Storage static site, external IP/FQDN). An **origin group** is a set of origins with health-probe + load-balancing settings (priority/weight) — Front Door's failover unit.

**A5. How does Front Door achieve low latency globally?**
**Answer:** Via **anycast** — the same IP is announced from many edge POPs, so users connect to the **nearest edge**, then traffic travels Microsoft's backbone to the origin.

**A6. What is URL/path-based routing in Front Door?**
**Answer:** Routes match URL patterns (e.g., `/images/*`, `/api/*`) and send matching requests to different origin groups — microservice routing at the edge.

**A7. What is Front Door's caching?**
**Answer:** Edge caching of responses (per route, with TTL/compression rules) — serving cached content from the edge to reduce origin load and latency.

**A8. What is the WAF on Front Door?**
**Answer:** **Azure WAF on Front Door** (global) protects at the edge — OWASP managed rules, bot protection, rate limiting, geo/custom rules — before traffic reaches origins.

**A9. What is TLS/SSL offloading at Front Door?**
**Answer:** Front Door terminates TLS with your certificate (or a managed one) at the edge and re-encrypts to the origin (end-to-end TLS optional).

**A10. What are rule sets?**
**Answer:** A rules engine for **request/response manipulation**: URL redirect/rewrite, header add/modify, caching overrides — applied per route.

**A11. What are the two SKUs / tiers of Front Door?**
**Answer:** **Classic** (older) and **Standard/Premium** (current). Premium adds **Private Link origins**, larger rule sets, and advanced security (bot, more WAF features).

**A12. How does Front Door do automatic failover?**
**Answer:** **Origin groups** with health probes: if an origin (or region) fails probes, Front Door routes to the next healthy origin **instantly** (no DNS TTL wait, unlike Traffic Manager).

**A13. Can Front Door front private origins?**
**Answer:** Yes — **Premium tier** supports **Private Link** origins, so Front Door can reach backends that have **no public IP** (private endpoints).

**A14. What is a typical Front Door + origin architecture?**
**Answer:** Front Door (edge: WAF, TLS, routing, cache) → regional origins (App Services, LBs, App Gateways) across regions — with origin-group health failover.

**A15. How does Front Door handle HTTP→HTTPS redirect?**
**Answer:** Via a **rule set** (redirect rule) or route configuration forcing HTTPS — a common first setup step.

---

## Case B — Advanced (Senior)

**B1. Explain Front Door's anycast architecture and why failover is "instant" vs DNS-based solutions.**
**Answer:** The Front Door anycast IP is announced from many POPs; users always hit the nearest edge, and the edge routes to the **selected origin** per health status in real time. Because the **IP never changes**, there's no DNS caching/TTL to wait out — a failed origin is bypassed on the next request. This is the key architectural advantage over Traffic Manager.

**B2. How do origin groups work (priority, weight, health probes) and how do you design multi-region failover?**
**Answer:** An origin group contains origins with **priority** (failover order) and **weight** (load split within a priority). Health probes continuously test origins. Design: origin group per region with healthy origins; set priority so the primary region serves first and the DR region takes over automatically on probe failure. Weights distribute within a priority level.

**B3. Compare Front Door Standard vs Premium (when do you need Premium)?**
**Answer:** **Standard**: global L7 + WAF + caching + rule sets. **Premium**: adds **Private Link origins** (reach private backends), **bot protection**, larger rule sets/WAF capabilities, and higher limits. Choose Premium for private-origin architectures or advanced security; Standard for most public-origin apps.

**B4. How does Front Door caching work (rules, TTL, cache keys, compression)?**
**Answer:** Per **route**, you enable caching with a **cache key** (URL/query-string config), **TTL** (from origin `Cache-Control` or explicit), and **compression** (gzip/brotli). Cache invalidation via purge (by path/wildcard). Design cache keys carefully so dynamic content isn't over-cached (e.g., exclude auth/query params).

**B5. How do you design Front Door + Private Link to reach backends with no public IP?**
**Answer:** In **Premium**, add an origin with **Private Link** — Front Door creates a private endpoint in your VNet, so it reaches the backend's private IP via the private endpoint (requires approving the connection). This eliminates public exposure on origins, a major security win (works with App Service, storage, internal LB, etc.).

**B6. What is the rules engine (rule sets) and what can it do (rewrite, headers, redirects, overrides)?**
**Answer:** Rule sets apply conditions (path, headers, query, geo, etc.) and actions: **URL rewrite/redirect**, **add/modify request & response headers** (e.g., HSTS, CORS, client-IP), **override route/caching**, and **set TLS/cookie flags**. This is Front Door's programmability layer — e.g., strip `/api` before forwarding, or inject security headers.

**B7. How does WAF on Front Door differ from WAF on Application Gateway?**
**Answer:** Front Door WAF is **global** (edge, before traffic enters a region) — best for global DDoS/bot/geo blocking. App Gateway WAF is **regional** (per-region inspection at L7 LB). They can be layered: Front Door WAF globally + App Gateway WAF regionally (defense in depth), though this adds latency/cost.

**B8. How do you do canary/blue-green with Front Door (percentage-based routing)?**
**Answer:** Use **origin groups with weights** — e.g., 90% old origin, 10% new origin (or route by header/cookie via rule sets). Adjust weights to ramp, and roll back instantly (no DNS). For per-user stickiness, use a **cookie-based** routing rule so a user stays on one version.

**B9. What are the security best practices for Front Door (lock down origins, Private Link, TLS, WAF)?**
**Answer:** (1) Use **Private Link** origins (Premium) or restrict origin access to **Front Door's IPs / a shared secret header**, (2) enforce **TLS 1.2+**, (3) enable **WAF** (prevention, bot protection, rate limits), (4) use **custom domains + managed certs**, (5) apply **rule sets** for security headers (HSTS, X-Frame-Options), and (6) log via **diagnostics** to Sentinel.

**B10. How does Front Door integrate with App Service/AKS/static sites as origins?**
**Answer:** App Service = origin (Front Door routes + caches, optionally Private Link). **AKS** = origin via the ingress's public IP/domain (or Private Link to an internal LB). **Static sites** = Storage static website as origin with caching. Front Door adds global reach, WAF, and TLS to all of these.

**B11. How do you monitor Front Door (metrics, logs, health)?**
**Answer:** Metrics: **RequestCount, RequestSize, ResponseSize, Latency (TotalTime/BackendLatency), CacheHitRatio, 4xx/5xx rates, OriginHealthPercentage**. Enable **diagnostic logs** (FrontDoorAccessLog, WebApplicationFirewallLog, HealthProbeLog) to Log Analytics; alert on origin health drops and 5xx spikes.

**B12. What are the costs and limits to consider with Front Door at scale?**
**Answer:** Costs: **base fee (Standard/Premium) + per-GB egress + requests + WAF rules/requests**. Limits: routes/origins/rule sets per profile, request size (64 KB header/response body limits on some features), and caching size limits. Cache aggressively and choose the right tier to control cost; check current quotas when designing.

---

## Case C — Scenario

**C1. Scenario:** A global app needs instant failover between two regions, WAF, and TLS at the edge — users must not wait on DNS.
**Question:** Which service and why not Traffic Manager?
**Answer:** **Azure Front Door** — anycast edge proxy with **origin-group health failover** (instant, no TTL), integrated **WAF**, and **TLS termination** at the edge. Traffic Manager is DNS-only, so failover is TTL-bound and it can't do WAF/TLS/caching.

**C2. Scenario:** A backend (App Service) has a public URL, but security wants it reachable **only** through Front Door.
**Question:** How do you lock it down?
**Answer:** Options: (1) **Premium + Private Link**: make the App Service private and let Front Door reach it via private endpoint (no public exposure at all). (2) Restrict App Service access to Front Door's **service tag/backend IPs** (`AzureFrontDoor.Backend`) and add a **custom header** (rule set) that the origin validates. Prefer Private Link for strongest isolation.

**C3. Scenario:** Static assets (images/CSS) are served from origin every time, causing load and latency.
**Question:** Optimize with Front Door.
**Answer:** Enable **caching** on the static routes (`/images/*`, `/assets/*`) with appropriate **TTL** and **compression** (brotli/gzip), and design **cache keys** (exclude noise query params). This serves assets from the edge, slashing origin load and improving global latency. Purge via cache invalidation on deploys.

**C4. Scenario:** You need to redirect all HTTP traffic to HTTPS and add HSTS + security headers globally.
**Question:** Implement with Front Door.
**Answer:** Create a **rule set** with: an **HTTP→HTTPS redirect** rule (301) on the route, and **response-header actions** to add `Strict-Transport-Security`, `X-Content-Type-Options`, `X-Frame-Options`, and `Content-Security-Policy`. Attach the rule set to the routes. This applies consistent security headers at the edge.

**C5. Scenario:** A canary release: 5% of users to a new backend version, sticky per-user, instant rollback.
**Question:** Design it.
**Answer:** Front Door **origin group** with **weights** (95% old / 5% new) and a **cookie-based affinity** rule so a user stays on their assigned version. Ramp the weight gradually; roll back by shifting to 100/0 **instantly** (no DNS). Monitor 5xx/latency per origin and automate rollback on alerts.

**C6. Scenario:** Users in Asia report slow response; the origin is in the US.
**Question:** How does Front Door help, and what else improves it?
**Answer:** Front Door serves via the **nearest anycast edge** in Asia, caching cacheable responses there and using the **Microsoft backbone** to the origin — cutting latency vs public internet. Additional wins: cache static content at the edge, and deploy a **second origin in Asia** with origin-group routing (performance/priority) so dynamic content is also regional.
