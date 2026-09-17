# RTIQ — Azure PaaS & Integration (Real-Time Interview Questions)

> **Cloud:** Azure · **Domain:** App Service, API Services (API Management) · **Target roles:** SDE-3 · Cloud Engineer · DevOps · DevSecOps · SRE · Platform Engineer · **Reading time:** ~18 min

**How this file is used live:** App Service and APIM are where "just deploy it" meets production reality — slots, VNet integration, cold starts, plan sizing, and API lifecycle. Expect "the app is slow at 9 a.m.", "we need a zero-downtime deploy", and "how do you govern 40 APIs".

**Legend:** ⚡ Rapid · 🔍 Deep dive · 🚨 War room · ⚖️ Trade-off · 🎯 Senior signal

---

## 1. App Service — `app-service.md`

**⚡ Rapid**
1. **Q:** What are App Service plans and tiers?
**A.** The plan defines the compute (VM instances, SKU) that apps run on. Tiers: Free/Shared (dev only), Basic (no slots/autoscale), Standard (slots + autoscale), Premium v3 (better performance, more slots, VNet integration, zone redundancy), Isolated (App Service Environment, private/dedicated). Production = Standard or Premium v3 minimum.
2. **Q:** What are deployment slots for?
**A.** Staging slots with their own hostname/config; you deploy to staging, warm it up (hit the app so JIT/caches are ready), then swap — the swap is near-instantaneous because the platform switches the hostname bindings, and `sticky settings` keep connection strings per-slot. It's the standard zero-downtime release mechanism.
3. **Q:** How do you configure App Service access to a VNet?
**A.** Outbound: VNet Integration (subnet delegation) so the app can reach private resources. Inbound: private endpoint (make it private-only) or access restrictions/service endpoints. Configure both — many teams do one and wonder why it doesn't work.
4. **Q:** How do you scale App Service?
**A.** Scale up (bigger SKU) or scale out (more instances, autoscale rules on CPU/memory/queue length or custom metrics); be aware of the per-plan limits, and that zone redundancy requires ≥3 instances (and a supporting region). Also know that the *plan* is the scaling unit — apps in the same plan share resources, which is a common performance surprise.
5. **Q:** Where do secrets and settings go?
**A.** App settings with Key Vault references (via managed identity) or Key Vault-backed config; never in source control, and prefer identity-based connections for storage/SQL over connection strings. Slot-sticky settings for environment-specific values.
6. **Q:** What is the cold start / warm-up problem?
**A.** JIT compilation, dependency loading, and TLS/DB connection establishment make the first requests after deploy/scale-out slow. Mitigate with warm-up in slots, `WEBSITE_WARMUP_PATH`/Application Initialization, always-on for low-traffic apps (Basic+), and keeping instances warm (min instance count ≥2 for production).
7. **Q:** What are the common App Service platform limits?
**A.** Request timeouts (230 s for HTTP requests, 240 in some configurations), connection limits, file storage (persistent `/home` has quotas), and the fact that the platform recycles instances (you must tolerate restarts). Plan statelessness and put state in external stores.

**🔍 Deep dive**
8. **Q:** Design a zero-downtime deployment pipeline for a .NET/Node app on App Service.
**A.** Build once → deploy to the staging slot → run smoke/integration tests against the slot's hostname → warm up (application initialization/AI warm-up path) → swap with preview (verify the app on the production hostname before completing) → monitor errors/latency for 10–15 minutes → rollback by swapping back. Keep app settings slot-sticky, and ensure the app supports graceful shutdown/connection draining during instance restarts.
**↳ Follow-up:** "The swap caused 500s for 30 seconds. Why?"
**A.** The staging slot wasn't warmed (cold JIT/DI), the app's health isn't verified before traffic (`/health` returning OK too early), or a slot-specific setting changed behaviour after swap (non-sticky setting pointing to a different DB), or a dependency (private DNS/Key Vault access) wasn't available in staging. Fix by warming and adding a health gate before swap.
9. **Q:** The app is slow at 9 a.m. every weekday. How do you diagnose?
**A.** Metrics: CPU/memory per instance, HTTP queue length, response time by operation, and the plan's instance count — then check whether autoscale actually fired (`InstanceCount`), whether a scheduled job/report coincides, whether it's the app's own startup after an overnight recycle, or a downstream (SQL/Cosmos) being slow. Also check the always-on setting — the classic cause of "slow first morning requests" is instances idling/unloaded.
10. **Q:** How do you secure an App Service end-to-end?
**A.** Private endpoint (no public access) or IP access restrictions + Front Door/App Gateway in front, managed identity for all Azure access, Key Vault references for secrets, HTTPS-only + minimum TLS 1.2, FTPS disabled, client certificates if needed, VNet integration for outbound, Defender for App Service, and monitoring/logging to Log Analytics. Also: no deployment credentials enabled (use the pipeline's federation).
11. **Q:** How do you migrate an app between plans or regions with minimal downtime?
**A.** Create the target plan/app, deploy the same code with the target configuration, sync/point to shared data, validate with a staging slot and synthetic tests, then switch traffic at Front Door/App Gateway/DNS (not by moving the app). Moving a live App Service in place isn't possible — you clone and cut over.
12. **Q:** How do you handle configuration across environments?
**A.** App settings as the 12-factor contract, with environment-specific values supplied by the pipeline (Bicep/Terraform parameters) and secrets via Key Vault references; sticky settings for slot-level differences; App Configuration for feature flags/labels with labels per environment. No environment logic in code.
13. **Q:** How do you monitor and set alerts?
**A.** Application Insights (requests, failures, dependencies, live metrics), platform metrics (CPU, memory, queue length, instance count, HTTP 5xx), health checks with an alert and auto-heal rules (recycle on 5xx/slow response), availability tests, and alerts on 5xx rate/response time/queue length. Standardize dashboards per app via a workbook template.

**🚨 War room**
14. **Q:** The app returns 503 "service unavailable" intermittently. Where do you look?
**A.** Platform vs app: 503 from App Service usually means no instances available to serve (scale-out in progress, plan saturated, or the app failing health probes), or an instance recycling. Check instance count, HTTP queue length, CPU/memory, platform health, and app logs for startup failures/OOM. If it correlates with deploys, fix the warm-up/health gates.
15. **Q:** After enabling a private endpoint, the app can't reach SQL or Key Vault.
**A.** DNS: the app now resolves the private FQDN to a public IP (or vice versa) because the private DNS zone isn't linked to the VNet used for outbound integration, or the app's DNS settings weren't refreshed. Fix zone links and confirm resolution from inside (`nslookup` via Kudu/SSH). The second common cause is a missing private endpoint on the target side for the integrated subnet.
16. **Q:** Memory usage climbs until the app recycles. Diagnose.
**A.** Memory leak (profile via Application Insights/dotnet-counters/Node heap), large in-memory caches, accumulating connections or unclosed streams, or the plan's shared memory being consumed by another app in the same plan. Mitigate by moving to a dedicated plan/bigger SKU, then fix the leak — and add a memory alert so it's caught before recycling.
17. **Q:** Deployment slots won't swap — "swap failed with a bad request".
**A.** Configuration differences blocking the swap (app setting names that exist in one slot only with non-sticky keys, or a `WEBSITE_` setting that can't be swapped), slot-specific bindings/domains, or the staging app failing to start. Check the swap error details, the "preview" option and slot settings, then align configuration between slots.
18. **Q:** The app is under DDoS/abuse and the plan is saturated.
**A.** Front Door/App Gateway with WAF rate limiting in front (absorb at the edge), access restrictions to only allow the edge, autoscale rules raised with a documented max, and blocking the abusive patterns (IP/geo/rate). Then verify the app isn't doing expensive work for unauthenticated traffic — add auth/rate limiting at the app level too.
19. **Q:** Costs doubled after enabling autoscale. What happened?
**A.** The autoscale rules were too aggressive (low thresholds, short cooldowns) or scale-in never fired (long cooldown/CPU floor), leaving instances running idle; also check whether always-on + min instance counts are higher than needed, whether a dev/test plan lacks scheduled shutdown, and whether the app is over-provisioned (huge Premium instances for low load). Right-size thresholds from real metrics and set scale-in deliberately.
20. **Q:** A certificate for a custom domain expired.
**A.** Restore service (upload/renew the cert, rebind), then automate: App Service Managed Certificates auto-renew (with DNS validation working) or Key Vault certs referenced by the app with renewal alerts at 30/14/7 days plus synthetic TLS checks. Broken DNS CNAME/validation records are the usual reason managed certs fail to renew.

**⚖️ Trade-off**
21. **Q:** App Service vs Container Apps vs AKS vs Functions?
**A.** App Service for standard web/API workloads with slots and the least ops; Container Apps for containers without cluster ops + event scaling; AKS when you need platform standardisation/K8s ecosystem; Functions for event-driven/short tasks. Choose on team capability and the operational budget as much as on features.
22. **Q:** Shared plan vs dedicated plan per app?
**A.** Shared plans reduce cost but couple apps' performance (one noisy app degrades others) and complicate scaling decisions; per-app plans isolate performance/costs at higher spend. Typical: shared for low-traffic/internal apps, dedicated for user-facing production.
23. **Q:** Slots vs a second app (blue/green)?
**A.** Slots are cheap, fast, and built-in (with slot-sticky settings) but share the plan's resources; two apps in separate plans give full isolation (better for heavy load tests or different scaling) at double cost. Slots for most deployments; separate apps/plans for high-risk changes or capacity-sensitive releases.
24. **Q:** Autoscale on CPU vs on a custom metric (queue length/requests)?
**A.** CPU is easy but often lags the real bottleneck (I/O-bound apps show low CPU while queueing); queue length/requests per instance tracks actual demand better. Use a composite: CPU/HTTP-queue-length in App Service + a queue metric for worker apps.
25. **Q:** Managed certificates vs Key Vault certificates?
**A.** Managed certs are free and auto-renew but limited (no wildcard in the same way, no export, validation constraints); Key Vault certs give control, reuse across services, and wildcard support but you manage issuance/renewal (or use a CA integration). Multi-service/wildcard → Key Vault; simple single-domain → managed.
26. **Q:** Is ARM/Bicep/Terraform mandatory for App Service config, or is the portal fine?
**A.** IaC is mandatory for anything production: portal drift causes incidents (settings changed by hand, slots misconfigured) and blocks reproducibility. Portal for investigation/debugging only.

**🎯 Senior**
27. **Q:** What does your production App Service standard look like?
**A.** Premium v3 (zone-redundant, min 2–3 instances), private endpoint + Front Door/App Gateway in front with WAF, VNet integration for outbound, managed identity + Key Vault references (no secrets in settings), slots for all deploys with warm-up and swap-with-preview, health check endpoint + auto-heal rules, Application Insights + alerts on 5xx/latency/queue length/memory, autoscale rules derived from real metrics with sane scale-in, backup/DR (or stateless design + redeploy), and all configuration in IaC.

**🎯 Senior signal:** "warm-up and swap-with-preview", "inbound private endpoint *and* outbound VNet integration are different things", and diagnosing 9 a.m. slowness as always-on/JIT rather than "the cloud is slow". Those are real production tells.

---

## 2. API Services (API Management) — `azure-api-services.md`

> **RTIQ note:** this covers Azure API Management (APIM) and the broader "API as a product" governance questions that senior/platform roles get asked.

**⚡ Rapid**
1. **Q:** What does APIM give you over calling the backend directly?
**A.** A single governed front door: authentication (subscription keys, OAuth/JWT validation, mTLS), rate limiting/quotas, request/response transformation, caching, versioning/revisions, developer portal + documentation, and centralized logging/metrics for every API call. Governance and lifecycle, not just proxying.
2. **Q:** Tiers?
**A.** Consumption (serverless, per-call, no VNet/private endpoint in the classic sense), Developer (no SLA, for dev), Basic (small prod, no VNet inject), Standard (SLA, VNet capable), Premium (multi-region gateways, VNet, higher scale). Production with private backends needs Standard/Premium (or a self-hosted gateway).
3. **Q:** How do you protect a backend?
**A.** APIM in front (so the backend has no public access — private endpoint or internal VNet), subscription keys/JWT validation at the gateway, backend auth via managed identity/certificate, IP restrictions on the backend, and rate limits per product/subscription.
4. **Q:** What are products and subscriptions?
**A.** Products bundle APIs with policies and access rules; subscriptions are the keys/permissions a consumer gets to a product (with approval workflows and per-subscription rate limits). This is how you model API consumers, tiers, and SLAs.
5. **Q:** Policies — what are they and where do they run?
**A.** XML policy statements at global/product/API/operation scope with `<inbound>`, `<backend>`, `<outbound>`, `<on-error>` sections: auth, rate limit, CORS, transformation (JSON↔XML), caching, retries, mocking. They're powerful — and a place where logic hides and becomes untestable, so keep them thin.
6. **Q:** How do you version an API?
**A.** Versions (path/header/query-based: `/v1`, `/v2`) for breaking changes with independent lifecycles; revisions for non-breaking updates within a version (with a changelog); and a deprecation policy communicated via the developer portal. Monitor per-version usage before retiring.
7. **Q:** How do you do auth at the gateway?
**A.** `validate-jwt` policy (Entra ID or any OIDC provider) with audience/issuer checks, subscription keys for partner/API-key scenarios, mTLS for B2B, and OAuth2 client-credentials flows for machine-to-machine. Business authorization stays in the backend — the gateway proves identity and applies coarse policy.
8. **Q:** Common limits to plan around?
**A.** Request/response size (varies by tier), policy complexity and processing time, rate-limit accuracy in distributed (multi-region) setups, and the fact that the gateway is in the hot path so Premium/scale is a real consideration. Also the per-tier request limits and backend timeouts.

**🔍 Deep dive**
9. **Q:** Design API governance for 40 teams exposing 200 APIs.
**A.** A shared APIM (Premium, multi-region or standard per region), a naming/versioning standard, products modelled per consumer class (internal, partner, public) with subscriptions and rate limits, mandatory policy baseline (JWT validation, correlation ID injection, rate limiting, CORS, error-shape normalisation) applied via policy fragments so teams can't forget them, OpenAPI specs as the source of truth imported in the pipeline, the developer portal as the internal catalogue, and analytics/usage dashboards per API/consumer. Onboarding is a self-service pipeline, not a ticket to the platform team.
**↳ Follow-up:** "How do you prevent a team from shipping an unauthenticated API?"
**A.** The baseline policy fragment is applied at the product/global level (so no API can bypass it), plus a CI gate that validates the OpenAPI spec against the standards (security scheme present, versioned path, required tags) and a nightly audit that queries all operations and flags any without an auth policy.
10. **Q:** How do you control abuse and cost per consumer?
**A.** Rate limits and quotas (`rate-limit`, `rate-limit-by-key`, `quota`) keyed by subscription/JWT claim, tiered products (free/standard/premium with different limits), spike-arrest for bursts, and per-consumer analytics to evidence it. Handle 429s gracefully in the client with `Retry-After`.
11. **Q:** How do you do zero-downtime API changes?
**A.** Revisions: deploy a revision without making it current, test via the revision URL, then make it current (a fast switch) — with rollback being the reverse. For breaking changes, ship a new version alongside the old, migrate consumers, and retire the old one after the deprecation window with usage evidence.
12. **Q:** How do you integrate APIM with your CI/CD and IaC?
**A.** Bicep/Terraform (or the APIM DevOps Resource Kit extractor) for products, APIs, policies, and named values; pipeline extracts/publishes the definition from source control (OpenAPI + policy XML), applies policies as code, and promotes across environments with environment-specific named values/backends (via Key Vault/named values, not hardcoded). Never edit policies only in the portal — it's drift.
13. **Q:** How do you handle secrets and backend credentials in APIM?
**A.** Named values backed by Key Vault for secrets, managed identity for APIM→backend auth (or client certificates in Key Vault), and per-environment values managed by the pipeline. Avoid secrets in policy XML and avoid long-lived keys for backend calls.
14. **Q:** How do you observe APIs end-to-end?
**A.** APIM request logs (with correlation ID) → Log Analytics + Application Insights with the backend's telemetry stitched by correlation ID; metrics on requests, latency (gateway vs backend), 4xx/5xx by API/operation, and per-subscription usage; alerts on error-rate/latency and on quota breaches. The gateway is the perfect place to standardise observability — with one correlation header propagated everywhere.
15. **Q:** What about self-hosted gateways / multi-region?
**A.** Self-hosted gateways run APIM's runtime in your own K8s/on-prem for data-residency, private backends, or hybrid scenarios — with the control plane in Azure (requires connectivity, and it introduces a caching/sync consideration). Multi-region Premium gateways give geo-distribution with a single control plane; combine with Front Door/Traffic Manager for global ingress.

**🚨 War room**
16. **Q:** All API calls through APIM are failing after a policy change.
**A.** Use the gateway's policy tracing/debug (`Ocp-Apim-Trace`) on a failed call, identify the failing policy section (`on-error` will show the message), and roll back by making the previous revision current — this is why you deploy via revisions. Then test policy changes against a revision URL before activating.
17. **Q:** One consumer is saturating the gateway and degrading everyone.
**A.** Rate limit/quota by subscription or JWT claim (if not already), isolate heavy consumers into their own product/tier with limits, and consider a dedicated gateway/instance for high-volume consumers. Add alerting on per-subscription request volume so you see it before the platform degrades. Also check whether scale (units/instances) hides a design problem rather than fixing it.
18. **Q:** Latency through APIM is 200 ms higher than hitting the backend directly.
**A.** Gateway overhead plus inefficient policies (large transformations, external calls in inbound — e.g. calling a token endpoint per request, or a synchronous logging webhook), caching disabled for cacheable GETs, and cross-region routing. Fix by caching responses, avoiding network calls in policies, moving logic to the backend, and placing gateways near backends.
19. **Q:** Backend is healthy but APIM returns 500/502.
**A.** Backend URL/port mismatch or the wrong protocol (HTTPS vs HTTP), TLS trust issues (custom CA/cert not trusted), the backend rejecting the managed identity/cert, or a policy in `outbound` throwing. Enable tracing to see the exact failure — and verify the backend's own logs to split gateway-side from backend-side.
20. **Q:** A partner's key was leaked. Response?
**A.** Regenerate/rotate the subscription keys (dual-key pattern for rotation without downtime: issue secondary, migrate the partner, revoke primary), review usage analytics/logs for anomalous volumes or endpoints from the leaked key, and add IP restrictions or mTLS if the partner can support it. Then make key rotation a standard process, not an incident-only activity.
21. **Q:** Costs spiked after a new API was onboarded.
**A.** Check APIM tier/units (Premium is expensive; scaling units for a single noisy API is a design smell), request volume per API/subscription, and whether the callers should be internal (bypassing the gateway for east-west traffic — APIM isn't for internal service-to-service chatter at scale). Right-place the traffic: edge-only through APIM, internal traffic direct or via a service mesh.
22. **Q:** The backend is publicly reachable even though it's "behind APIM". Why is that a finding?
**A.** Anyone can bypass the gateway's auth/rate limits and hit the backend directly (and your WAF/gateway logs won't cover it). Fix: private endpoint/internal-only backend with IP restrictions allowing only APIM, or network-level restriction via NSG/VNet integration. This is one of the most common API-security gaps.

**⚖️ Trade-off**
23. **Q:** APIM vs App Gateway vs an ingress controller for APIs?
**A.** APIM for API lifecycle/governance (products, subscriptions, developer portal, policies, transformation, versioning). App Gateway/ingress for L7 routing/WAF without API-product concepts. Many stacks use both: edge gateway for TLS/WAF/routing, APIM for API management. Don't use APIM as a plain proxy for internal services — it's priced and designed for API products.
24. **Q:** Consumption vs Standard vs Premium?
**A.** Consumption: serverless, per-call, cheap at low volume, limited features (no VNet injection, cold starts, no multi-region gateways). Standard: SLA, VNet, predictable monthly cost. Premium: multi-region, higher scale, best for critical/global APIs. Cost model changes at volume — model your request rate.
25. **Q:** Gateway validation vs backend validation?
**A.** Validate cheaply and consistently at the gateway (token validity, scopes, rate limits, schema-shape basics) and keep *business* authorization/entitlement in the backend (who can do what to which object). Duplicating business rules at the gateway creates two sources of truth; skipping backend validation creates a bypass risk.
26. **Q:** Rewrite/transform at the gateway vs fix the backend?
**A.** Transformation helps legacy backends and consumer-facing contracts, but heavy transformation at the gateway is hard to test, invisible to backend teams, and a latency source. Use it deliberately for compatibility; prefer the backend exposing a clean contract long-term.
27. **Q:** Should internal service-to-service traffic go through APIM?
**A.** Generally no — it adds cost/latency for governance you don't need internally. Use service mesh/managed identity/direct calls with mTLS, and reserve APIM for external/partner/internal-product APIs. Say the boundary out loud; it shows cost awareness.
28. **Q:** One APIM instance for all environments vs per environment?
**A.** Per environment (dev/test/prod) is the baseline for isolation and safe policy testing; per-team instances fragment governance and multiply cost. Consolidate APIs into one instance per environment with products/versions for separation.

**🎯 Senior**
29. **Q:** How do you prove an API platform is healthy to leadership and to auditors?
**A.** For leadership: usage/consumer growth, latency (gateway and backend), error rates by API, availability against SLOs, and top consumers. For auditors: authn/authz on every operation (policy evidence), rate limits applied, TLS config, logging/retention of API calls, versioning/deprecation policy, and access reviews on the platform's own control plane. Both come from the same telemetry — build it once, present it twice.

**🎯 Senior signal:** "private backend so nobody can bypass the gateway", "deploy via revisions so rollback is one click", and "internal traffic shouldn't pay for an API-management gateway". Those three are platform-engineer markers.
