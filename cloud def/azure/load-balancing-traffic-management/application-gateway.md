# Azure Application Gateway — Interview Questions

> **Cloud:** Azure · **Category:** Load Balancing & Traffic Management · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~8 min

---

## JSON File Format

Application Gateway is ARM JSON (`Microsoft.Network/applicationGateways`): listeners, backend pools, HTTP settings, path maps, and routing rules.

```json
{
  "type": "Microsoft.Network/applicationGateways",
  "apiVersion": "2023-04-01",
  "name": "appgw",
  "properties": {
    "sku": { "name": "WAF_v2", "tier": "WAF_v2" },
    "backendAddressPools": [{ "name": "api-pool", "properties": { "backendAddresses": [{ "fqdn": "api.internal" }] } }],
    "backendHttpSettingsCollection": [{ "name": "api-settings", "properties": { "port": 8080, "protocol": "Http" } }],
    "httpListeners": [{ "name": "https", "properties": { "frontendIPConfiguration": { "id": "[...]" }, "protocol": "Https", "sslCertificate": { "id": "[...]" } } }],
    "requestRoutingRules": [{ "name": "api-route", "properties": { "httpListener": { "id": "[...]" }, "backendAddressPool": { "id": "[...]" }, "backendHttpSettings": { "id": "[...]" } } }]
  }
}
```

**Key fields:** `sku` (Standard_v2 / WAF_v2) · `httpListeners` (SNI/TLS) · `backendAddressPools` · `backendHttpSettingsCollection` · `requestRoutingRules` + `urlPathMaps` (path routing) · `probes`. WAF policies (`Microsoft.Network/ApplicationGatewayWebApplicationFirewallPolicies`) are separate JSON.


## Case A — Basic

**A1. What is Azure Application Gateway?**
**Answer:** A regional **Layer 7 (HTTP/HTTPS)** load balancer and web traffic manager with URL path/host-based routing, TLS termination, cookie-based session affinity, and integrated **Web Application Firewall (WAF)**.

**A2. What OSI layer does Application Gateway operate at?**
**Answer:** **Layer 7** — it inspects HTTP/HTTPS and routes by URL path, host header, query params, and headers (unlike Azure Load Balancer at L4).

**A3. What are the main components?**
**Answer:** **Frontend IP**, **listeners** (protocol/port + hostname), **routing rules** (listener → backend), **backend pools**, **HTTP settings** (port, protocol, affinity, timeouts), and **health probes**.

**A4. What is a listener?**
**Answer:** The entry point that receives traffic on a frontend IP/port (e.g., HTTPS 443) and optionally a hostname — it routes to rules/backends based on the URL.

**A5. What is path-based routing?**
**Answer:** Routing requests to different backend pools based on URL path — e.g., `/images/*` → image servers, `/api/*` → API servers, on one gateway.

**A6. What is multi-site (host-based) routing?**
**Answer:** Hosting multiple domains on one gateway, routing by **host header** — e.g., `app1.example.com` → pool 1, `app2.example.com` → pool 2.

**A7. What is TLS/SSL termination?**
**Answer:** The App Gateway decrypts HTTPS at the gateway (with a certificate), then forwards plain HTTP (or re-encrypts) to backends — offloading TLS from servers.

**A8. What is end-to-end TLS?**
**Answer:** TLS from client → gateway **and** gateway → backend (re-encryption), so traffic is encrypted all the way to the server.

**A9. What is WAF in Application Gateway?**
**Answer:** The Web Application Firewall SKU adds protection against OWASP top-10 (SQLi, XSS, etc.), with managed/custom rules, rate limiting, and bot protection.

**A10. What is session affinity in App Gateway?**
**Answer:** Cookie-based affinity — the gateway sets a cookie so a user's requests stick to the same backend server (for stateful apps).

**A11. What are the two SKUs?**
**Answer:** **Standard_v2** and **WAF_v2** (the v2 SKUs are current: zone-redundant, autoscaling, better performance). The older v1 SKUs are being retired.

**A12. How does App Gateway differ from Azure Load Balancer?**
**Answer:** App GW = L7 HTTP routing, TLS, WAF, cookies. Azure LB = L4 TCP/UDP, higher throughput, no HTTP features. They're complementary (often LB → App GW → backends).

**A13. What is autoscaling in App Gateway v2?**
**Answer:** The gateway automatically scales instances up/down with traffic (min/max instances), removing manual capacity planning.

**A14. What are backend HTTP settings?**
**Answer:** Configuration for the gateway→backend connection: port, protocol (HTTP/HTTPS), cookie affinity, request timeout, connection draining, and host-name override.

**A15. What is a redirect (e.g., HTTP → HTTPS)?**
**Answer:** App Gateway can redirect requests (301/302) — commonly forcing HTTP to HTTPS via a redirect rule on the port-80 listener.

---

## Case B — Advanced (Senior)

**B1. Explain the request routing flow: listener → rule → backend pool, including path vs host evaluation.**
**Answer:** A **listener** accepts traffic (frontend IP/port + optional hostname). **Routing rules** are evaluated (priority-ordered): each rule has conditions (path patterns, hostnames, headers, query strings) and maps to a **backend pool** + **HTTP settings**. The first matching rule wins; a default rule catches the rest. Understanding priority/conditions is key to debugging routing.

**B2. How does App Gateway v2 autoscaling work, and how do you size min/max instances?**
**Answer:** v2 scales based on **capacity units** (compute, persistent connections, throughput). Set **min/max instances** to bound cost/capacity; autoscaling handles bursts. For predictable high load, set a higher min to pre-provision; monitor **Current Capacity Units** to tune.

**B3. What is TLS termination vs end-to-end TLS vs mutual TLS (mTLS), and how do you configure each?**
**Answer:** **Termination**: gateway decrypts with its cert, backend HTTP. **End-to-end**: gateway decrypts then re-encrypts to backend (backend needs certs). **mTLS**: gateway validates **client certificates** (mutual auth) — upload trusted CA, require client cert on the listener. Choose per security/compliance requirements.

**B4. How does WAF on App Gateway work (managed rules, exclusions, custom rules, rate limiting)?**
**Answer:** WAF v2 evaluates requests against **OWASP managed rulesets** (CRS), with **exclusions** to suppress false positives, **custom rules** (IP allow/deny, geo, string match), and **rate limiting** (per-client thresholds). It runs in **detection** or **prevention** mode; logs go to Azure Monitor/Sentinel for tuning.

**B5. What is the backend health probe and how do you tune it (interval, threshold, path, host)?**
**Answer:** App GW probes backends (default every 30s, HTTP GET `/`); tune **path** (e.g., `/health`), **host** (override), **interval/threshold** to avoid flapping. Probes must return 2xx; if backends need a host header, set the probe's hostname. Unhealthy backends are excluded from routing.

**B6. How do you implement blue-green/canary releases with App Gateway (path/header-based traffic splitting)?**
**Answer:** Options: (1) **weighted backend pools** (if using v2 with multiple pools? — actually use header/path rules), (2) route by **header/cookie** (e.g., `x-version: v2`) to a new pool, (3) use **App Service deployment slots** with traffic %, or (4) **Front Door** in front for percentage-based split. The gateway's rule engine gives header/path-based canaries; for % splits use Front Door/slots.

**B7. How does connection draining and request timeout protect during backend maintenance/deploys?**
**Answer:** **Connection draining** lets in-flight requests to a backend finish (during the drain period) while new connections are stopped — enabling graceful VM decommission. **Request timeout** (default 20s, up to ~2600s in v2) bounds how long the gateway waits for a backend response (504 after timeout). Tune both for zero-downtime deploys.

**B8. What are the common causes of 502/504 errors on App Gateway and how do you distinguish them?**
**Answer:** **502 Bad Gateway** = backend unreachable/misconfigured (probe failing, TLS/host mismatch, NSG block). **504 Gateway Timeout** = backend took longer than the request timeout. Diagnose via **backend health**, **access logs** (`serverStatus`, `timeTaken`), NSG rules, and backend metrics — separate gateway-side vs backend-side latency.

**B9. How does App Gateway integrate with Azure Load Balancer (why both), and with AKS?**
**Answer:** App GW handles L7 routing/WAF/TLS; an **Azure LB** in front (or behind) adds L4 scale/HA and static IPs. With **AKS**, use the **Application Gateway Ingress Controller (AGIC)** to auto-configure the gateway from K8s Ingress resources — path/host routing for cluster services without manual gateway config.

**B10. How do you secure App Gateway (NSGs, WAF, TLS policy, private frontend)?**
**Answer:** Restrict inbound NSG to 80/443 (and 65200–65535 for backend health/management if applicable), enable **WAF in prevention mode**, enforce **TLS 1.2+** and strong cipher policy, use **managed identity + Key Vault** for certificates (auto-rotation), and use an **internal/private frontend** for non-public apps.

**B11. What are App Gateway's scale/performance limits and how do you plan capacity?**
**Answer:** v2 scales via **capacity units** (throughput ~2.22 Mbps/unit, connections/unit); limits exist for max instances (125), listeners, backend pools, and rules. Plan: estimate throughput + connections + request rate, set min instances for baseline, monitor Current Capacity Units, and use multiple gateways or Front Door for global scale.

**B12. How does App Gateway handle WebSocket and HTTP/2?**
**Answer:** App Gateway supports **WebSocket** (long-lived connections proxied to backends) and **HTTP/2** on the frontend. For WebSockets, ensure the backend settings/request timeout accommodate long-lived connections. gRPC over HTTP/2 is supported on newer v2 configurations.

---

## Case C — Scenario

**C1. Scenario:** A monolith must be split into `/api/*` (API servers) and `/app/*` (web servers) behind one public domain with HTTPS.
**Question:** Configure the gateway.
**Answer:** One **App Gateway** with an HTTPS listener (cert via Key Vault/ACM-like), a **path-based routing rule**: `/api/*` → API backend pool, `/app/*` (or `/*` default) → web pool. Health probes per pool, WAF enabled, HTTP→HTTPS redirect, and end-to-end TLS if needed.

**C2. Scenario:** Users hit 502 errors after a deploy; backends are running.
**Question:** Diagnose.
**Answer:** 502 = gateway can't get a valid response: check **backend health** (probes failing → wrong port/path, NSG blocking gateway subnet traffic, or TLS/host mismatch), verify the **backend HTTP settings** (protocol/port/host override), and check backend response time vs timeout. Use access logs to see `serverStatus` and the failing backend.

**C3. Scenario:** You must host `shop.example.com` and `blog.example.com` on the same gateway, each to different backends.
**Question:** Which feature?
**Answer:** **Multi-site (host-based) routing**: create two **listeners** (both on 443 with their hostnames + certs via SNI) and rules mapping `shop.example.com` → shop pool, `blog.example.com` → blog pool. One gateway, one frontend IP, multiple sites.

**C4. Scenario:** An app needs cookie-based stickiness because it stores session state on each VM.
**Answer:** Enable **session affinity** in the backend **HTTP settings** (cookie-based) — the gateway issues an affinity cookie so the user stays on the same backend. Note: with autoscaling/redeploys, sessions on a removed VM are lost; consider a shared session store (Redis) if you need resilience.

**C5. Scenario:** You must block SQL injection and bot traffic at the edge of a regional app.
**Question:** Which SKU/config?
**Answer:** **WAF_v2 App Gateway** with **OWASP managed rules** (SQLi/XSS), **bot protection ruleset**, custom rules (rate limit, IP/geo blocks), and **prevention mode**. Route logs to Log Analytics/Sentinel and tune **exclusions** for false positives.

**C6. Scenario:** Certificates keep expiring and causing outages because they're uploaded manually.
**Question:** Improve certificate management.
**Answer:** Use **Key Vault integration**: store certificates in Key Vault, grant the App Gateway a **managed identity** with access, and reference the **Key Vault certificate** in the listener — the gateway auto-renews the certificate from Key Vault, eliminating manual uploads and expiries. Alert on Key Vault cert near-expiry as a backup.
