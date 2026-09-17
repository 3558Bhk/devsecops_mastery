# RTIQ — Azure Load Balancing & Traffic Management (Real-Time Interview Questions)

> **Cloud:** Azure · **Domain:** Azure Load Balancer, Application Gateway, Traffic Manager, Front Door · **Target roles:** SDE-3 · Cloud Engineer · DevOps · DevSecOps · SRE · Platform Engineer · **Reading time:** ~14 min

**How this file is used live:** the classic Azure networking design question is "users hit intermittent 502s — go", or "design global ingress for a multi-region app". Interviewers want the *layer* (L4 vs L7 vs global), the *health probe* mechanics, and the *decision rule* for choosing among the four services. Expect to be pushed on WAF, TLS, and connection draining.

**Legend:** ⚡ Rapid · 🔍 Deep dive + follow-ups · 🚨 War room · ⚖️ Trade-off debate · 🎯 Senior signal

---

## 1. Azure Load Balancer — `azure-load-balancer.md`

**⚡ Rapid**
1. **Q:** Basic vs Standard SKU?
**A.** Standard: zone-redundant or zonal, secure by default (no inbound unless NSG allows), HA ports, outbound rules, SLA; Basic is legacy (retiring) with no SLA. Always Standard in production.
2. **Q:** Public vs internal load balancer?
**A.** Public faces the internet (frontend public IP); internal (ILB) uses a private IP in a subnet for east-west traffic. Most 3-tier designs have both.
3. **Q:** What are the health probe options?
**A.** TCP (port open), HTTP/HTTPS (expects 200, can use a custom path), from a source IP `168.63.129.16`. Probes drive backend health and failover; a shallow probe keeps broken instances in rotation.
4. **Q:** Why is 168.63.129.16 important?
**A.** It's the Azure platform's health-probe/management IP — your NSG must allow it, and you must never block it. Understanding this is the most practical Azure-LB detail there is.
5. **Q:** How do you make an LB zone-redundant?
**A.** Standard LB with a zone-redundant public IP and zone-spanning backend (VMs/VMSS across zones). Zonal LBs pin to one zone and are only for single-zone designs.
6. **Q:** What are HA ports and when?
**A.** All-protocol/all-port load balancing for NVAs/firewalls (active-active appliances) — used with internal LBs in a gateway-load-balancer-ish pattern (Azure uses a different flow, but HA ports are for appliance HA setups).
7. **Q:** How do you get outbound internet from VMs now?
**A.** NAT Gateway (recommended), LB outbound rules (legacy), or a public IP on the VM (avoid). Default outbound access is retired for new deployments — plan the migration.

**🔍 Deep dive**
8. **Q:** Design a highly available, zone-spanning internal LB for a stateful API tier.
**A.** Standard internal LB with a zone-redundant frontend (private IP), backend pool = VMSS across 3 zones, HTTP probe on a readiness endpoint that checks dependencies, NSG allowing probe source + app port from the caller tier, session persistence only if the app is stateful (otherwise none), and diagnostics to Log Analytics. Add connection draining via the app's graceful shutdown + probe behaviour.
9. **Q:** Users see intermittent 502s through the LB. Diagnose.
**A.** Check the backend health first (probe failing → flapping), then the app's connection handling (idle timeout vs keep-alive mismatch — LB default idle timeout is 4 minutes), slow start, and whether one instance is bad. Also check for a probe that is HTTP while the app is HTTPS/binding only on one port, and for graceful-shutdown handling during deploys. Flow logs/diagnostics plus app logs will separate LB-side from app-side.
10. **Q:** How do you do zero-downtime deployment behind an internal LB?
**A.** VMSS rolling upgrade with health probes and pause/batch controls (or a blue/green pair of scale sets swapped at the LB), readiness probes that fail before the app is truly ready, connection draining so in-flight requests finish, and a canary stage. The probe is what makes it zero-downtime — bad probes mean bad rollouts.
11. **Q:** What is the difference between inbound NAT rules and load-balancing rules?
**A.** LB rules distribute to a backend pool by port; inbound NAT rules map a specific frontend port to a specific backend instance (used for SSH/RDP through the LB — and a source of exposure if not restricted).
12. **Q:** How do you monitor and troubleshoot the LB?
**A.** Metrics: data path availability (`DipAvailability`), health probe status, SYN count, SNAT port usage (with alerts — SNAT exhaustion is a real outage). Logs to Log Analytics for detailed troubleshooting; Connection Monitor for end-to-end latency/loss.

**🚨 War room**
13. **Q:** All backends show unhealthy, but the app responds locally. What do you check?
**A.** NSG blocking `168.63.129.16` or the probe port, probe path returning non-200 (HTTPS cert issues, auth redirect), the app listening only on localhost, wrong backend port in the pool, or the VM's OS firewall. Check the probe status per backend in metrics — probe failures are explicit about port/path.
14. **Q:** After adding a third instance, some client requests time out. Why?
**A.** The new instance may be missing an NSG/ASG membership, missing config (env vars, certificates, connection strings), or not warmed (slow start). This is why slow-start duration and readiness gates matter. Verify with per-instance health + logs, then fix the provisioning template so new instances are identical.
15. **Q:** SNAT port exhaustion alerts firing. What now?
**A.** Workloads downloading/opening many outbound connections through the LB (legacy outbound rules) — switch to NAT Gateway for outbound (scalable ports, static IPs), reduce connection churn with keep-alive/pooling, and check for connection leaks in the app. NAT Gateway is the structural fix.
16. **Q:** You must fail over an app to another region. Try it. What's missing?
**A.** Typically: DNS/Traffic Manager switching, data replication state/RPO, secrets and certificates in the target region, configuration/dependencies (Key Vault, storage, private endpoints/DNS) not pre-created, and capacity/quota. Also the LB/VMSS in DR must actually be deployed and tested — "pilot light" only works if you've lit it before.
17. **Q:** A Zonal LB has an outage in one zone. Impact?
**A.** Zonal LBs and their frontends live in that zone — that zone's capacity is lost entirely. Zone-redundant LBs spread across zones and keep serving. Interviewers use this to check you understand zonal vs zone-redundant, not just "we have 3 VMs".

**⚖️ Trade-off**
18. **Q:** Azure Load Balancer vs Application Gateway?
**A.** LB is L4 (TCP/UDP), ultra-fast, no L7 features; App Gateway is L7 (HTTP/HTTPS, URL/host routing, WAF, TLS termination, redirects, autoscaling). Need URL routing/WAF → App Gateway; TCP/ultra-low latency/private non-HTTP → LB. Many designs use App Gateway at the edge and LB internally.
19. **Q:** Public LB vs App Gateway for a web app?
**A.** App Gateway gives WAF, TLS termination/offload, path routing, and cookie affinity — usually the right edge for HTTP apps. A public LB in front of web servers means you'd be putting L7 concerns in the app. LB for non-HTTP or when you need raw performance.
20. **Q:** Should you use LB outbound rules or NAT Gateway?
**A.** NAT Gateway: scalable SNAT ports, predictable static egress IPs, no dependency on a backend pool. LB outbound rules are legacy and tied to the LB's SNAT budget. Prefer NAT Gateway and note default outbound is being retired.
21. **Q:** Session persistence — when and why not?
**A.** Use only for genuinely stateful apps (5-tuple/2-tuple/client-IP affinity); it breaks even distribution and makes scaling/rolling updates worse. Prefer externalized state; if needed, use client-IP affinity for HTTP (with the caveats of proxy client IPs).

**🎯 Senior**
22. **Q:** What's your standard for an internet-facing L4 tier?
**A.** Standard SKU (zone-redundant), NSG on the subnet allowing only intended ports (never relying on default open), health probes that test a dependency-aware readiness endpoint, metrics alerts on data-path availability + SNAT usage, diagnostics to a central workspace, outbound via NAT Gateway with static IPs, and everything in IaC with the probe settings identical across environments.

**🎯 Senior signal:** naming `168.63.129.16`, distinguishing probe failure from app failure, and SNAT exhaustion → NAT Gateway. That's lived Azure experience.

---

## 2. Application Gateway — `application-gateway.md`

**⚡ Rapid**
1. **Q:** What does App Gateway give you over an LB?
**A.** L7 routing (path/host/multi-site), TLS termination and end-to-end TLS, WAF (with CRS rules), cookie-based affinity, URL rewrite/redirect, autoscaling (v2), and health probes with path and status-code matching.
2. **Q:** v1 vs v2 SKU?
**A.** v2 (Standard_v2/WAF_v2): autoscaling, zone redundancy, static VIP, faster provisioning, better WAF, and it's what you should deploy. v1 is legacy (no autoscale, no zones) and being retired.
3. **Q:** Which subnet does it need?
**A.** A dedicated subnet (nothing else in it), sized with enough IPs for autoscale instances (a /24 is a common choice), with NSG rules allowing `GatewayManager` inbound on 65200–65535 plus your ingress ports, and (v2) outbound to Azure services/Internet as required.
4. **Q:** How do health probes work here?
**A.** Custom probes per backend pool with a path, port, interval, timeout, and match conditions (status code range + optional body match). Default probes are blunt; a proper readiness path prevents routing to instances whose dependencies are down.
5. **Q:** How do you terminate TLS with multiple domains?
**A.** Multiple listeners (basic or multi-site) with SNI, certificates from Key Vault (managed identity) or uploaded PFX, and per-listener HTTP→HTTPS redirects. Use Key Vault + managed identity so renewals are automatic and secrets aren't in config.
6. **Q:** What's the WAF mode difference?
**A.** Detection = log only (use during rollout/tuning); Prevention = block (production). Always start new rules/customizations in detection, review the logs, then switch to prevention. OWASP CRS rulesets with per-rule exclusions.
7. **Q:** Is it zone-redundant?
**A.** v2 with zone redundancy (choose ≥2 zones) is; a zonal deployment isn't. For production availability, pick zone-redundant and confirm the subnet/backend can span zones.
8. **Q:** Where does the WAF fit vs Front Door WAF?
**A.** Front Door WAF is at the global edge (best for DDoS/geo/bot), App Gateway WAF is in-region at the ingress. Running both is common (edge filtering + regional rules), but tune them so you don't double-block or double-count.

**🔍 Deep dive**
9. **Q:** Design multi-region ingress for a web app with WAF, HTTP/2, and zero-downtime deploys.
**A.** Front Door (global, WAF at edge, health-probed origins per region) → per-region App Gateway (WAF + URL routing + TLS with Key Vault certs) → regional backends (VMSS/App Service) with readiness probes and connection draining. Deploys go region-by-region with Front Door health checks removing a draining region, plus priority/weighted routing for canaries. Observability at both layers (Front Door access logs + App Gateway diagnostics) with end-to-end correlation IDs.
**↳ Follow-up:** "A region is degrading but not fully down. How does traffic move?"
**A.** Front Door health probes (or a manual priority/weight change) shift traffic to the healthy region — automatic drift happens when probes fail; for gradual issues you need app-level health signals (e.g. a canary endpoint reporting error rate) or manual intervention. Be honest: "graceful degradation requires health signals that reflect user experience, not just TCP".
10. **Q:** App Gateway shows 502s for all backends. Debug order.
**A.** Backend health blade (probe status/reason), NSG on the backend subnet (probe and app port), backend listener binding/TLS mismatch (App Gateway talking HTTPS to an HTTP backend or vice versa), custom probe path returning wrong code, and certificate name mismatch on the backend. Then check whether the backend's own logs show the request arriving — that bifurcates network vs app instantly.
11. **Q:** How do you handle long-running requests through App Gateway?
**A.** Default request timeout is 20 s — raise it (max 86400 s for v2) for long requests, ensure the backend's own timeouts are shorter or matched, and prefer async patterns (202 + polling) over long-held connections. This is the Azure equivalent of the ALB idle-timeout answer.
12. **Q:** How do you scale App Gateway?
**A.** v2 autoscaling with a min/max instance count (min ≥2 for HA, min ≥3 for zone-redundant best practice) sized from capacity units (compute + connections + throughput). Watch capacity unit utilisation metrics and set autoscale on them — not just CPU. Also plan IP capacity in the subnet for max instances.
13. **Q:** How do you migrate from v1 to v2 with minimal downtime?
**A.** Build the v2 gateway alongside (separate public IP), duplicate listeners/rules/certs (Key Vault), validate with hosts-file/synthetic tests, then switch DNS (low TTL) to the v2 IP, monitor errors, and keep v1 for rollback until the TTL/soak period ends. Nothing in-place — v1↔v2 isn't an in-place upgrade.
14. **Q:** How do you secure App Gateway end-to-end?
**A.** WAF in prevention with tuned rules, TLS 1.2+ policy, HTTPS-only listeners with redirect, Key Vault certs via managed identity, private backend via VNet-integrated backends (App Service VNet integration/private endpoints), NSG restricting the GatewayManager range and backend access, and diagnostics (access logs + WAF logs + firewall logs) to a central workspace with alerts on blocked-request spikes. Also enable the "prevent direct backend access" pattern (backend only reachable via the gateway).
15. **Q:** How do you do URL-based routing for a microservices monolith split?
**A.** Multi-site/path-based rules mapping `/api/orders/*` → backend pool A, `/api/payments/*` → pool B, with rewrite rules to strip prefixes where the services expect root paths, per-pool probes, and routing rules versioned in IaC. Keep the routing table small and explicit — a 200-rule gateway becomes unmanageable and slow to change.

**🚨 War room**
16. **Q:** WAF started blocking legitimate customer traffic after a ruleset upgrade.
**A.** Switch to detection mode immediately (or disable the specific rule IDs), pull the WAF logs to find the matching rule and match details (often an encoded payload in a JSON field, a large body, or a base64 upload), add targeted exclusions (rule ID + argument), re-enable prevention for that rule group, and stage future ruleset upgrades in detection for a week. Communicate with the affected customers.
17. **Q:** Users in one region are getting 504s through App Gateway while others are fine.
**A.** Check per-region backend health (a backend pool member in that region failing), Front Door origin health/priority if it's global, gateway capacity-unit saturation, and long-running requests hitting the timeout. Also check for a regional dependency (DB replica, regional PaaS) being degraded — App Gateway is often the messenger, not the cause.
18. **Q:** Certificate expired and took the site down. What should have prevented it?
**A.** Key Vault-managed certificates with auto-renewal and a managed-identity reference (not uploaded PFX), plus an alert on certificate expiry (Key Vault event/monitor alert) 30/14/7 days out, and synthetic checks on TLS from multiple regions. Also make sure the *listener* actually points at the Key Vault secret version-less ID so renewal is picked up.
19. **Q:** App Gateway provisioning failed due to subnet/IP exhaustion. Impact and fix?
**A.** Scaling/provisioning fails, so you may be stuck at fewer instances than needed (capacity risk) — check the subnet's free IPs, free space by removing unused resources or resizing the subnet (with the gateway recreated if needed), and plan the max autoscale instance count against subnet size. This is a design-time constraint people discover at the worst moment.
20. **Q:** A DDoS/HTTP flood is saturating the gateway.
**A.** Front Door + WAF rate limiting and geo rules at the edge (absorb before the regional gateway), Azure DDoS Protection on the public IPs, autoscale max raised, bot-manager rules for known botnets, and identify the attack signature to block — but note the real fix is edge absorption, and app-level rate limiting/queueing for what gets through.

**⚖️ Trade-off**
21. **Q:** App Gateway vs Front Door vs both?
**A.** Front Door for global anycast ingress, edge WAF, caching, and multi-region failover; App Gateway for in-region L7 routing/WAF and private backends. Both is the standard enterprise pattern; Front Door alone works if you don't need regional URL routing or private-only backends.
22. **Q:** WAF at the edge vs in-region?
**A.** Edge (Front Door) absorbs volume and blocks bad traffic before it crosses regions — cheaper and better for DDoS. In-region (App Gateway) sees internal/private traffic paths and can enforce rules closer to the app. Prefer edge for internet traffic, in-region for compliance/belt-and-braces.
23. **Q:** Autoscaling vs fixed instance count?
**A.** Fixed = predictable cost and capacity planning but either over-provisioned or at risk in spikes; autoscale = matches demand with capacity-unit-based scaling but requires min instances for HA and careful max sizing (subnet IPs, backend capacity). Production default: autoscale with min 2–3.
24. **Q:** Cookie affinity vs stateless backends?
**A.** Affinity is a crutch that hurts even distribution and deploys; externalize session state (Redis/App Service ARR off) and remove affinity. Keep affinity only for genuinely stateful backends where refactoring isn't feasible yet — and document it as debt.

**🎯 Senior**
25. **Q:** Give me your ingress reference architecture for a regulated multi-region web app.
**A.** Front Door (Premium, WAF with managed + custom rules, bot manager, geo filtering) → per-region zone-redundant App Gateway v2 (WAF, TLS with Key Vault certs via managed identity, path routing, private backends) → VMSS/App Service with private endpoints and no public access → NSGs limiting GatewayManager and backend access → diagnostics and WAF logs to an immutable central workspace → alerts on backend health, capacity units, blocked spikes, and certificate expiry → all defined in IaC with a tested regional failover and a documented runbook.

**🎯 Senior signal:** "WAF starts in detection then moves to prevention", the probe-path-vs-liveness distinction, and mixing edge + regional WAF with a tuning plan. Those three signal real ownership of a production ingress.
