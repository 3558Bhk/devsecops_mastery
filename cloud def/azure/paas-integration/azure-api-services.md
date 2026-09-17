# Azure API Management (API Services) — Interview Questions

> **Cloud:** Azure · **Category:** PaaS & Integration · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~8 min

---

## JSON File Format

Azure API Management APIs are defined in **OpenAPI (Swagger) JSON**, imported to auto-generate the API and operations.

```json
{
  "openapi": "3.0.1",
  "info": { "title": "Orders API", "version": "1.0.0" },
  "servers": [{ "url": "https://apim.azure-api.net/orders/v1" }],
  "paths": {
    "/orders": {
      "get": {
        "summary": "List orders",
        "responses": { "200": { "description": "OK" } }
      }
    }
  }
}
```

**Key fields:** `openapi` version · `paths` (operations → APIM operations) · `info`/`servers`. Note: APIM **policies are XML** (not JSON) — the exception to the JSON rule in APIM. The APIM service itself is ARM JSON (`Microsoft.ApiManagement/service`).


## Case A — Basic

**A1. What is Azure API Management (APIM)?**
**Answer:** A managed service that publishes, secures, transforms, and monitors **APIs** — acting as a gateway/facade between API consumers and your backend services, with portals, policies, and analytics.

**A2. What are the main APIM components?**
**Answer:** **API Gateway** (runtime proxy), **Management plane/Azure portal** (administration), and **Developer portal** (self-service docs/onboarding).

**A3. What is an API vs an operation in APIM?**
**Answer:** An **API** = a logical grouping of endpoints (e.g., "Orders API"). An **operation** = a single endpoint (method + URL) within an API (e.g., `GET /orders`).

**A4. What is a product in APIM?**
**Answer:** A bundle of APIs offered to developers, with **subscription requirements, throttling, and quota** policies — the commercial/packaging unit.

**A5. What is a subscription key?**
**Answer:** A key issued to a developer for a **product** — required to call the APIs in that product (identifies/rate-limits the consumer).

**A6. What are policies?**
**Answer:** Configurable rules executed in the gateway pipeline (inbound/backend/outbound/on-error) — for auth, rate limiting, caching, transformation, CORS, etc., written in XML.

**A7. What is the policy pipeline order?**
**Answer:** **inbound** (request → backend) → **backend** (the call) → **outbound** (response → client) → **on-error** (exception handling).

**A8. What are the APIM tiers?**
**Answer:** **Developer** (dev/test, no SLA), **Basic**, **Standard**, **Premium** (multi-region, VNet, higher scale), plus **Consumption** (serverless, pay-per-call) and **v2 tiers** (Basic/Standard v2).

**A9. What is the difference between APIM and an API Gateway / Application Gateway?**
**Answer:** APIM = **API management** (subscriptions, policies, portals, developer experience, throttling). Application Gateway = **L7 load balancer/WAF**. Azure Functions/App Service = API hosting. APIM typically sits in **front of** those backends as the management layer.

**A10. How does APIM secure APIs (authentication options)?**
**Answer:** **Subscription keys**, **OAuth 2.0 / OpenID Connect** (Entra ID), **client certificates (mTLS)**, **IP allowlisting**, and **validate-jwt** policies — layered per API/product.

**A11. What is rate limiting vs quota in APIM?**
**Answer:** **Rate limit** = max calls per time window (e.g., 100/min, short window, rejected after). **Quota** = total calls over a longer period (e.g., 10,000/month, enforced over time). Both set via policies per product/key.

**A12. What is a backend in APIM?**
**Answer:** The actual service that implements the API (App Service, Function, VM, any HTTP endpoint) — APIM proxies and transforms traffic to/from it.

**A13. What is the Developer Portal?**
**Answer:** A self-service website (customizable) where developers discover APIs, read docs, and get **subscription keys** — the developer experience layer.

**A14. What is versioning and revisioning?**
**Answer:** **Versions** = distinct, parallel API versions (e.g., v1/v2). **Revisions** = non-breaking changes within a version (e.g., rev 1, rev 2) with rollback — both manage API evolution.

**A15. What is caching in APIM?**
**Answer:** Response caching policies store backend responses (per key, TTL) to reduce backend load and latency — at the gateway.

---

## Case B — Advanced (Senior)

**B1. Explain the APIM request pipeline and where each policy runs (inbound/backend/outbound/on-error).**
**Answer:** **inbound** policies (auth, rate-limit, transform request) → **backend** policies (call, retry, cache-lookup) → backend → **outbound** policies (transform response, cache-store, headers) → response to client. **on-error** runs if any stage throws. Mastering this ordering is essential for writing correct policies (e.g., validate-jwt must be inbound, before backend).

**B2. How do you implement authentication flows (OAuth2, JWT validation, client certs) in APIM?**
**Answer:** **validate-jwt** policy verifies OIDC/OAuth tokens (issuer, audience, signing key); **OAuth2 server + client credentials/authorization-code** flows integrate with Entra ID; **client-certificate** auth (mTLS) validates the client cert (via `context.Request.Certificate` / validate-client-certificate); **subscription keys** gate by product. Layer multiple for defense in depth.

**B3. What is the role of APIM in a microservices architecture (gateway pattern, BFF)?**
**Answer:** APIM is the **API gateway**: single entry point, cross-cutting concerns (auth, throttling, logging, CORS), routing to backend microservices, **versioning**, and **Backends for Frontends (BFF)** — different API surfaces for web/mobile. It decouples clients from the microservice topology.

**B4. How does APIM integrate with virtual networks (internal vs external mode, and v2 tiers)?**
**Answer:** **External** mode = gateway publicly reachable, backend private via VNet. **Internal** mode = gateway **only reachable from within the VNet** (via private IP/endpoint) — for private APIs. v2 tiers use **private endpoints + VNet integration** (simpler). Choose internal mode for purely internal APIs; external for public-facing.

**B5. What are the throttling/rate-limit policy patterns (rate-limit-by-key, quota-by-key) and how do you choose?**
**Answer:** **rate-limit-by-key** = strict short-window limit (rejects once exceeded, returns 429). **quota-by-key** = longer-term allowance (allows until total exhausted). Use rate-limit for abuse protection (per subscription/IP), quota for business/tier limits (per subscription key). Key = subscription ID, IP, or a custom expression.

**B6. How do you version APIs and manage revisions/rollback?**
**Answer:** Create **versions** (v1, v2) as separate API sets (path/query/header versioning schemes) for breaking changes; use **revisions** for non-breaking updates with the ability to **set a revision online** and **rollback**. Publish via **products** and deprecate old versions with a **deprecation/retirement** policy (headers notifying consumers).

**B7. How does APIM handle transformation (XML→JSON, SOAP→REST)?**
**Answer:** Policies like **json-to-xml / xml-to-json**, **set-body** (with expressions/templates), and **liquid templates** transform payloads — e.g., expose a legacy **SOAP** service as **REST/JSON** via WSDL import + transformation policies. This is APIM's "legacy modernization" superpower.

**B8. How do you monitor and troubleshoot APIM (analytics, logs, Application Insights)?**
**Answer:** **APIM analytics** (requests, responses, latency, errors per API/product), **Application Insights integration** (end-to-end tracing with correlation IDs), **diagnostic settings** → Log Analytics for gateway logs, and **Policy tracing** (Azure API Management Dev Portal "Test" console shows policy execution). Alert on 5xx and latency.

**B9. What is caching strategy in APIM (internal vs external cache, cache policies)?**
**Answer:** APIM has a **built-in internal cache** (per-unit, in-memory) and supports **external Redis** (shared across regions/units). **cache-lookup/cache-store** policies (with vary-by headers/query) reduce backend load; use **cache-lookup-value/store-value** for snippets. Choose external cache for multi-region Premium consistency.

**B10. How do you build a self-service developer experience (portal, products, onboarding)?**
**Answer:** Define **products** (tiers with quotas), group **APIs** into products, customize the **Developer Portal** (branding, docs, test console), enable **self-signup**, issue **subscription keys**, and document via **OpenAPI specs**. This lets external developers discover, subscribe, and test without manual onboarding.

**B11. What are the APIM scale/HA options (Premium multi-region, zones, autoscaling)?**
**Answer:** **Premium** supports **multi-region deployment** (gateway replicas across regions, active-active with the same domain + Traffic Manager/Front Door), **availability zones**, and **autoscaling** of gateway units. For HA, deploy across zones/regions and use **custom domains** with a global LB. Standard/Developer are single-region.

**B12. How does APIM integrate with Azure Functions/Logic Apps/backend services, and how do you protect direct backend access?**
**Answer:** APIM proxies to Function Apps/App Services/HTTP backends; secure the backend with **managed identity auth** (APIM authenticates to the backend), **restrict access** (backend only accepts APIM's IP/subnet or a shared secret header), and use **private endpoints/VNet** so the backend isn't publicly reachable. This ensures APIs are only consumed via APIM.

---

## Case C — Scenario

**C1. Scenario:** A company exposes internal REST APIs to external partners who need API keys, quotas, and docs.
**Question:** Design the APIM setup.
**Answer:** Create an **API** for each service (import OpenAPI), group them into **products** (partner tiers with quotas), enable **subscription keys**, customize the **Developer Portal** for self-service onboarding, apply **rate-limit-by-key** and **validate-jwt/OAuth** policies, and monitor via analytics + Application Insights.

**C2. Scenario:** A legacy SOAP service must be exposed to modern clients as REST/JSON.
**Question:** How does APIM do it?
**Answer:** **Import the WSDL** as an API; use **transformation policies** (`xml-to-json` on outbound, `json-to-xml` on inbound, `set-body`) to convert between SOAP/XML and REST/JSON, and expose clean REST operations in front of the SOAP backend. This modernizes the interface without rewriting the backend.

**C3. Scenario:** A public API is being abused (scraping, no API key); you must throttle and block abusers.
**Question:** Implement protection.
**Answer:** Enforce **subscription key** (require it), apply **rate-limit-by-key** (e.g., 100 req/min per subscription) and **quota** policies, add **IP-based throttling** for anonymous abusers, return **429** with `Retry-After`, and add **OAuth/JWT validation** for sensitive endpoints. Monitor top consumers and block via policies/access restrictions.

**C4. Scenario:** An API returns different data for mobile vs web clients (BFF pattern).
**Question:** Design with APIM.
**Answer:** Create **separate API products/versions** (e.g., "Mobile API", "Web API") as **BFFs** — each tailored surface with its own policies (throttling, field filtering via `set-body`/policy expressions) routing to the same or different backends. This keeps client-specific logic in the gateway, not the backend.

**C5. Scenario:** You need multi-region API availability with a single domain, serving users from the nearest region.
**Question:** Which APIM tier/config?
**Answer:** **Premium tier with multi-region deployment**: deploy APIM gateway replicas in multiple regions (active-active), front them with **Traffic Manager** (performance routing) or **Front Door** on a single custom domain, and use an **external Redis cache** so caching is consistent across regions. Backends replicate per region for full locality.

**C6. Scenario:** An internal API must be reachable only from your VNet (and on-prem via ExpressRoute), never the internet.
**Question:** Configure APIM.
**Answer:** Deploy APIM in **internal mode** (gateway only inside the VNet via a private IP/endpoint), or v2 tier with a **private endpoint**. Clients in the VNet (and on-prem through ExpressRoute/VPN) reach the gateway privately; the public internet has no path. Restrict the backend similarly with private endpoints + managed identity auth.
