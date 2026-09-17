# RTIQ — Azure Global Traffic Routing (Real-Time Interview Questions)

> **Cloud:** Azure · **Domain:** Traffic Manager, Azure Front Door · **Target roles:** SDE-3 · Cloud Engineer · DevOps · DevSecOps · SRE · Platform Engineer · **Reading time:** ~15 min

**How this file is used live:** these two services are the answer to "we need multi-region" — so interviewers ask you to *pick* and *justify*, then stress the choice: "the primary region is degraded, walk me through what happens" or "DNS failover took 8 minutes, why?". The senior signal is knowing DNS-based vs anycast-based failover and the data-layer implications.

**Legend:** ⚡ Rapid · 🔍 Deep dive + follow-ups · 🚨 War room · ⚖️ Trade-off debate · 🎯 Senior signal

---

## 1. Traffic Manager — `traffic-manager.md`

**⚡ Rapid**
1. **Q:** How does Traffic Manager actually route?
**A.** DNS-based: it returns a CNAME to the chosen endpoint's DNS name based on the routing method and endpoint health (using DNS TTL). It's not in the data path, so it can't cache or inspect — and failover is bounded by TTL + client resolver caching.
2. **Q:** Routing methods?
**A.** Priority (active-passive), Weighted (canary/gradual), Performance (lowest latency for the user), Geographic (by region for compliance), MultiValue (multiple healthy endpoints returned), Subnet (source IP mapping for specific clients). Know when each is appropriate.
3. **Q:** Monitoring options?
**A.** HTTP/HTTPS/TCP probes with custom paths, ports, expected status/body, and interval/timeout/tolerated failures; plus custom headers (for host-header routing or auth) and "expected status code ranges" for things like 301/401. A shallow monitor is the #1 failover failure.
4. **Q:** What are nested profiles for?
**A.** Combining methods — e.g. Performance at the top level with Priority per region for intra-region failover. Also used to work around per-profile endpoint limits.
5. **Q:** What's the failover time to promise?
**A.** Bounded by TTL × resolver caching: with a 30–60 s TTL, expect ~1–5 minutes realistically. If you need seconds, that's Front Door/Global anycast, not DNS.
6. **Q:** What about non-HTTP protocols?
**A.** Traffic Manager routes DNS, so it's protocol-agnostic (it just returns an endpoint) — but health checks are HTTP/HTTPS/TCP only, and the endpoint must still be reachable by the client. Useful for non-HTTP global failover in a way Front Door isn't.

**🔍 Deep dive**
7. **Q:** Design active-passive DR across two regions with fast failover and a documented RPO/RTO.
**A.** Traffic Manager priority profile with a 30 s TTL and a deep health check (dependency-aware endpoint that fails fast when the app's dependencies are unhealthy), hot standby in the secondary region (infrastructure deployed, scaled down or zero, ready to scale), data replicated with a documented RPO (SQL geo-replication/failover groups, Cosmos multi-region), a runbook that includes scaling up DR, promoting the DB, and validating, plus quarterly failover drills that measure actual detection + propagation + recovery time.
**↳ Follow-up:** "The health check passed but users were broken. How?"
**A.** The monitored endpoint was served by the load balancer or a static page that stayed healthy while the app's backend dependency was down — the probe must exercise the real path (e.g. a synthetic that touches the DB) or be driven by app-level health signals, not just an HTTP 200.
8. **Q:** How do you canary a new region or version with Traffic Manager?
**A.** Weighted routing with a small percentage to the new endpoint (e.g. 5%), with monitoring (error rate, latency) and a fast rollback (set weight to 0). Combine with endpoint-level monitoring so a bad canary is removed automatically. Remember the DNS caching means weight changes aren't perfectly uniform across users — say that.
9. **Q:** Geographic vs Performance routing for compliance?
**A.** Geographic pins users to a region by their DNS source for data-residency/regulatory reasons (with a mapping you control and a default for unmapped regions). Performance optimises latency but may route a user outside their legal region — never use it to satisfy residency requirements.
10. **Q:** How do you handle the "client still hits the old region" problem?
**A.** Short TTLs before changes, client-side retry/re-resolve logic (many clients cache DNS indefinitely — especially JVMs/Node with old resolvers and some mobile SDKs), avoid connection pinning, and use application-level health checks that endpoint away from the dead region. Acknowledge DNS limits rather than claiming instant failover.
11. **Q:** How do you monitor the routing layer itself?
**A.** Traffic Manager endpoint monitor status, per-endpoint health metrics, and the profile's DNS query metrics; plus synthetic users in each region hitting the public hostname (that's the only true end-to-end test). Alert on endpoint status change with a message including the affected region.
12. **Q:** What about TLS for a Traffic Manager-fronted multi-region app?
**A.** Each regional endpoint needs a valid certificate for the shared hostname (or a wildcard), managed per region (Key Vault + App Gateway/App Service) with automated renewal, and alerts on expiry — Traffic Manager itself doesn't terminate TLS. Certificate drift across regions is a classic cause of "failover succeeded but browsers errored".

**🚨 War room**
13. **Q:** The primary region's app is returning errors, but Traffic Manager didn't fail over. Why?
**A.** The health check is passing (wrong path, cache, or a load balancer serving a healthy error page), the tolerated-failure/interval settings are too permissive, the secondary endpoint is also unhealthy (so nothing to fail to), or the client's DNS cache is pinned. Check endpoint monitor status first, then the probe configuration and the secondary's readiness.
14. **Q:** Failover works, but the DR region can't take the load.
**A.** DR was never load-tested at production scale (scaled down or smaller SKUs), data replication lag made reads stale/broken, or dependencies (Key Vault/storage/DNS/quotas) weren't ready. Fix: keep DR at a realistic minimum capacity, run drills with production-level synthetic load, document the scale-up step in the runbook with a time estimate, and pre-warm images/caches.
15. **Q:** You accidentally published a wrong endpoint weight and all traffic went to one region.
**A.** Correct the profile immediately (weights are a fast change), watch the affected region's saturation, then prevent via IaC-only changes, a change review for routing profiles, and automated post-change validation (synthetic checks per region confirming traffic distribution). Routing changes are production changes — treat them like code.
16. **Q:** DNS TTL was set to 3600 "for performance"; DR took an hour. What do you tell the incident review?
**A.** The TTL dominates failover time — lower it (30–60 s) for failover-critical records and accept slightly more DNS traffic; also design the app to be resilient to slow steering (retries, connection re-resolution) and consider anycast (Front Door) for sub-minute failover. Own it as a design decision that was wrong for the RTO.

**⚖️ Trade-off**
17. **Q:** Traffic Manager vs Front Door for failover?
**A.** TM: DNS-based, protocol-agnostic, cheap, minutes-scale failover, no caching/inspection. Front Door: anycast data path, seconds-scale failover, caching, WAF, and it fixes the "client cached DNS" problem (clients always hit the same anycast IPs). Choose by RTO and whether you need L7 features.
18. **Q:** Performance routing vs Geo routing?
**A.** Performance optimises user latency but can send traffic across compliance boundaries; Geo enforces residency but may be slower for edge cases. If residency matters, Geo (or Front Door with explicit origin groups) — never "performance and hope".
19. **Q:** Priority (active-passive) vs Weighted (active-active)?
**A.** Active-passive is cheaper, simpler, and gives a clear primary; active-active uses both regions' capacity and improves latency but demands data-layer multi-master/staleness handling and more testing. Cost and complexity of the data layer usually decide.
20. **Q:** Should Traffic Manager front internal (private) services?
**A.** It's DNS-only and public-DNS-oriented; internal equivalents use Private DNS zones with health-checked records, or an internal ingress with its own failover. Don't use a public TM profile as your internal routing layer.
21. **Q:** Monitoring interval: aggressive vs conservative?
**A.** Aggressive (10 s interval, 1 tolerated failure) fails over fast but can flap on transient blips and cause churn; conservative (30 s, 3 failures) is stable but slow. Tune with the app's own load balancer health, and require multiple consecutive failures for the deepest checks.

**🎯 Senior**
22. **Q:** How do you validate a multi-region DR plan without waiting for a real outage?
**A.** Scheduled game days with controlled trigger (force the health check to fail or lower a priority), timed measurements (detection, DNS propagation, app recovery, data RPO), a checklist of everything that broke, and tracked follow-ups. Automate the failover where possible so the runbook is a script, not a person — and rehearse it at least twice a year.

**🎯 Senior signal:** "failover is bounded by TTL and client caching", "the health probe must exercise the real dependency path", and running timed game days. That's the SRE answer to multi-region.

---

## 2. Azure Front Door — `azure-front-door.md`

**⚡ Rapid**
1. **Q:** Front Door vs Traffic Manager, in one line?
**A.** Front Door is an anycast L7 edge (data path: caching, WAF, TLS offload, routing, fast failover on the same IPs); Traffic Manager is DNS-only steering. Front Door = seconds-scale failover and no client-caching problem; TM = cheap, protocol-agnostic.
2. **Q:** Standard vs Premium tier?
**A.** Premium adds Private Link origins (private-only backends), enhanced WAF (bot manager, more rulesets), and more scale/features; Standard covers basic CDN+WAF+routing. Regulated/private-backend designs need Premium.
3. **Q:** How do health probes and failover work?
**A.** Probes per origin with latency/sample settings; unhealthy origins are removed and traffic goes to the next by priority/weight — within seconds, because clients hold the same anycast IP regardless of which origin serves them. That's the key advantage.
4. **Q:** What is a rule set / rules engine used for?
**A.** URL redirect/rewrite, header manipulation, cache behaviour overrides, and security-header injection per route — the edge customization layer.
5. **Q:** How does caching differ from Azure CDN?
**A.** Front Door includes caching at the edge with the same platform as (and now replacing) Azure CDN from Microsoft; CDN classic is being consolidated into Front Door. New designs should use Front Door.
6. **Q:** What about origin access control?
**A.** For Azure Storage, use origin authentication/private endpoints; for App Service/App Gateway origins, restrict access to Front Door (service tag `AzureFrontDoor.Backend` + a header secret validation) so nobody can bypass the edge. Bypass-the-CDN is a classic security gap.
7. **Q:** Where's the WAF in the picture?
**A.** Front Door WAF (managed CRS rules + bot manager on Premium + custom/rate-limit rules) at the edge, with per-route policy association; in-region WAF (App Gateway) can layer behind it. Tune exclusions to avoid double-blocking.

**🔍 Deep dive**
8. **Q:** Design global ingress with Front Door for a multi-region SaaS.
**A.** Front Door Premium with a custom domain + managed cert, origin groups per region (priority + weight for canary/DR), health probes hitting a deep readiness endpoint, private endpoints to App Gateway/App Service origins so there's no public origin, WAF policy in prevention with rate limits and bot rules, caching rules for static assets (with appropriate TTLs and cache keys), and diagnostics (access/FD/WAF logs) to Log Analytics with alerts on origin health, 5xx rate, blocked-request spikes, and latency. All in IaC with a documented regional failover drill.
**↳ Follow-up:** "Cache hit ratio is poor on your static assets."
**A.** Check cache key and TTL configuration, whether query strings/cookies are included unnecessarily, `Cache-Control` from the origin, compression, and whether dynamic routes are accidentally catching static paths. Set explicit rules for `/static/*` with long TTLs and immutable versioned filenames; keep HTML short-TTL/no-cache.
9. **Q:** How does Front Door handle an origin outage mid-request?
**A.** In-flight requests to a failed origin error (clients retry), subsequent requests route to the healthy origin health-checked by probes; enable origin-level retries/`Response acceleration` for resilience. Design for retries and idempotency, and keep session state external so any origin can serve.
10. **Q:** How do you do private-only backends?
**A.** Premium with Private Link origins (App Gateway/App Service/Storage via private endpoint), so the backend has no public exposure at all; the Front Door edge connects over Private Link. This is the pattern regulated customers ask for.
11. **Q:** How do you handle WAF false positives at the edge?
**A.** Detection mode first for new rules, review WAF logs for the matching rule and the request element, add targeted exclusions (rule + argument), then switch to prevention per rule; for rate limiting, tune thresholds per route/customer tier rather than globally. Never disable whole rulesets to fix one payload.
12. **Q:** How do you do canary/blue-green at the edge?
**A.** Two origin groups (or origins with weights) per environment, weighted routing to the canary origin group in small percentages, monitoring per-origin metrics (5xx/latency/cache hit) with automated rollback of the weight. Combine with header-based routing (e.g. `x-canary: true`) for internal testing before real users.
13. **Q:** How do you protect an origin key or API from abuse through Front Door?
**A.** WAF rate limiting per IP/route, bot manager (Premium), API key/JWT validation at the origin (not the edge), geo filtering, and monitoring origin request volume for anomalies. Note that Front Door is not an API gateway — auth/business logic stays at the origin.
14. **Q:** What does Front Door not solve?
**A.** It doesn't make the data layer multi-region (replication/conflict handling is yours), doesn't fix a bad app-level retry strategy, doesn't replace an API gateway, and doesn't protect origins that remain publicly reachable. Say this — interviewers check whether you oversell the edge.

**🚨 War room**
15. **Q:** After a DNS move to Front Door, some clients still hit the old region directly.
**A.** Cached DNS/connection pinning on the client side and long TTLs on the old records; plus clients that hardcode IPs or use certificate pinning. Fix with pre-move TTL reduction, keeping the old endpoint serving (with a redirect/health response) for a grace period, and TLS certificates valid on both for a while. Prove it via the access logs showing legacy clients.
16. **Q:** Front Door shows 5xx spikes while origins look healthy — where do you look?
**A.** Origin health probe status, TLS to the origin (protocol/cert/SNI), origin timeouts (long app responses exceeding Front Door limits), WAF blocks (a block returns 403 but a misconfigured rule can produce other codes), and request rate limiting. Then compare Front Door access logs to origin access logs for the same request ID — the mismatch points to which hop is failing.
17. **Q:** The WAF is blocking a legitimate partner integration with large JSON payloads.
**A.** Identify the rule via WAF logs (usually request-body size or an encoded character match), add a precise exclusion for the route/argument, and consider a higher body-size limit for that route. Then re-enable prevention and monitor. Communicate the fix and keep the exclusion documented with an owner.
18. **Q:** Costs increased 3× — where does it come from?
**A.** Requests + data transfer out (uncached content, large files, video), low cache hit ratio forcing origin egress, WAF requests (billed per request on Premium), and log ingestion. Fix with cache rules/TTLs, compression, moving large media to a different distribution approach (or Blob + CDN tier), tuned log levels/retention, and per-route cost dashboards. Cost is a cache-hit-ratio conversation.
19. **Q:** A regional origin is degraded but health probes still mark it healthy.
**A.** Probes are shallow (a static health endpoint), so partial failures (e.g. one dependency) don't register — move to dependency-aware readiness or a synthetic flow, and/or lower the probe sensitivity with more samples. In the meantime, manually set the origin weight/priority to drain the region.
20. **Q:** A certificate for the custom domain didn't renew.
**A.** Front Door managed certificates renew automatically only if the DNS validation record still exists and the domain is correctly CNAME-mapped; if you use your own certificate (Key Vault), the renewal and re-upload is yours to automate with alerts. Check the domain validation state and set expiry alerts 30/14/7 days out.

**⚖️ Trade-off**
21. **Q:** Front Door vs App Gateway as the single ingress?
**A.** App Gateway alone is region-scoped — a regional failure takes the app down, and clients must resolve DNS to a new region (cache problems). Front Door adds global anycast ingress, edge WAF/caching, and fast failover. Use Front Door for global/multi-region, App Gateway for single-region L7 needs or as a regional tier behind Front Door.
22. **Q:** Front Door vs Azure CDN?
**A.** Front Door is the strategic platform (routing + WAF + Private Link + caching) and CDN-from-Microsoft features have been merged into it; use Front Door for new deployments, CDN classic only where legacy constraints exist.
23. **Q:** Edge caching on/off for an API?
**A.** Off for authenticated/personalized responses (cache key pollution and data leakage risk); on for public, idempotent GETs with proper cache keys. Never cache responses containing user data — and if you must, use aggressive `private` directives and per-user cache keys sparingly.
24. **Q:** One Front Door profile for everything vs per-app profiles?
**A.** Fewer profiles simplify WAF/domain management and cost; per-app profiles isolate blast radius and let teams own rules but multiply domains/quotas and config. In practice: segment by environment/public-vs-internal, with routes per app inside a profile.

**🎯 Senior**
25. **Q:** Give me your global ingress standard for a multi-region, regulated workload.
**A.** Front Door Premium (managed cert, custom domains), WAF in prevention with bot manager and tuned rate limits, per-region origin groups with private-link origins to App Gateway/App Service, deep readiness probes plus synthetic user journeys per region, cache rules for static only with versioned filenames, diagnostics to an immutable workspace with alerts on origin health/5xx/latency/WAF blocks, IaC-managed config with change review on routing rules, and a quarterly measured failover drill with a documented RTO/RPO matched to business commitments.

**🎯 Senior signal:** "clients hold the same anycast IPs — that's why Front Door fails over faster than DNS", the bypass-the-CDN gap, and cache-hit-ratio-as-cost-driver. Those three are the tell.
