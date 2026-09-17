# Azure Traffic Manager — Interview Questions

> **Cloud:** Azure · **Category:** Load Balancing & Traffic Management · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~9 min

---

## JSON File Format

Traffic Manager profiles are ARM JSON (`Microsoft.Network/trafficManagerProfiles`) with DNS config, routing method, monitor config, and endpoints.

```json
{
  "type": "Microsoft.Network/trafficManagerProfiles",
  "apiVersion": "2022-04-01",
  "name": "tmprofile",
  "properties": {
    "profileStatus": "Enabled",
    "trafficRoutingMethod": "Performance",
    "dnsConfig": { "relativeName": "myapp", "ttl": 60 },
    "monitorConfig": { "protocol": "HTTPS", "port": 443, "path": "/health", "intervalInSeconds": 30, "toleratedNumberOfFailures": 3 },
    "endpoints": [{
      "name": "us",
      "type": "Microsoft.Network/trafficManagerProfiles/azureEndpoints",
      "properties": { "endpointStatus": "Enabled", "target": "app-us.azurewebsites.net" }
    }]
  }
}
```

**Key fields:** `trafficRoutingMethod` (Priority/Weighted/Performance/Geographic/Multivalue/Subnet) · `dnsConfig` (relativeName + TTL) · `monitorConfig` (health probes) · `endpoints[].properties` (`priority`, `weight`, `geoMapping`, `target`).


## Case A — Basic

**A1. What is Azure Traffic Manager?**
**Answer:** A **global, DNS-based** traffic router that directs client requests to the best endpoint (across regions) based on routing method and endpoint health — it does **not** proxy traffic, only answers DNS.

**A2. How does Traffic Manager work at a high level?**
**Answer:** Clients resolve your domain → Traffic Manager returns the DNS answer (CNAME/A) pointing to the **chosen endpoint's IP** → the client connects directly to that endpoint. The data path never goes through Traffic Manager.

**A3. What are the routing methods?**
**Answer:** **Priority** (primary→secondary failover), **Weighted** (percentage split), **Performance** (lowest latency), **Geographic** (by user region), **Multivalue** (multiple healthy endpoints), and **Subnet** (by user subnet).

**A4. What is the Priority routing method?**
**Answer:** All traffic goes to the first (priority 1) endpoint while healthy; on failure, Traffic Manager fails over to the next priority — for active-passive DR.

**A5. What is the Weighted routing method?**
**Answer:** Distributes traffic across endpoints by assigned **weights** (e.g., 80/20) — for A/B testing or gradual migrations.

**A6. What is the Performance routing method?**
**Answer:** Routes users to the endpoint with the **lowest network latency** for them (based on an internet latency table) — for multi-region performance.

**A7. What is the Geographic routing method?**
**Answer:** Routes users to endpoints based on their **geographic location** (country/region/continent mapping) — for data-sovereignty/geo-compliance.

**A8. What is an endpoint in Traffic Manager?**
**Answer:** A target (Azure resource like a VM/App Service/Public IP, or an external IP/domain) that Traffic Manager can route to, with a priority/weight and health monitoring.

**A9. What are endpoint monitors (health checks)?**
**Answer:** Traffic Manager probes each endpoint (HTTP/HTTPS GET or TCP) and **stops returning unhealthy endpoints** in DNS answers — enabling automatic failover.

**A10. Is Traffic Manager stateful or does it proxy traffic?**
**Answer:** Neither — it's **stateless DNS routing**; after the DNS answer, the client talks directly to the endpoint (no tunnel through Traffic Manager).

**A11. What is the relationship between Traffic Manager and a CNAME?**
**Answer:** You point your domain's **CNAME** at the Traffic Manager profile name; Traffic Manager then answers with the selected endpoint's DNS name/IP.

**A12. How does Traffic Manager differ from Azure Load Balancer / App Gateway?**
**Answer:** Traffic Manager = **global DNS routing** (no data path, no port-based LB). Azure LB/App GW = **regional** load balancing of actual traffic. They complement: Traffic Manager routes between regions; LB balances within a region.

**A13. What is the key limitation of DNS-based routing?**
**Answer:** **DNS caching** — clients/resolvers cache the answer for the TTL, so failover/changes take effect only after the TTL expires (unlike Front Door, which fails over instantly at the edge).

**A14. What is "nested profiles"?**
**Answer:** Using a Traffic Manager profile as an endpoint of another profile — combining routing methods (e.g., performance across regions + failover within a region).

**A15. What is the TTL and why does it matter?**
**Answer:** How long DNS answers are cached; shorter TTL = faster failover but more DNS queries; longer TTL = cheaper/faster resolution but slower changes.

---

## Case B — Advanced (Senior)

**B1. Explain why Traffic Manager is "DNS-only" and the tradeoffs vs a data-path global balancer (Front Door).**
**Answer:** TM only answers DNS — no single point of failure in the data path, low cost, works with any protocol, but **failover latency is bound by DNS TTL/caching** and it can't inspect/rewrite traffic. **Front Door** proxies traffic at the edge (anycast), giving instant failover, WAF, and caching — but adds a data-path dependency and cost. Choose TM for simple global DNS steering; Front Door for instant failover + L7 features.

**B2. How does the Priority method implement DR, and what's the failover latency?**
**Answer:** Primary endpoint (priority 1) is returned while healthy; if its monitor fails, TM returns the priority-2 endpoint. Failover latency = monitor detection time + **DNS TTL expiry at clients** — so a client with a cached primary IP keeps trying it until TTL. Lower TTL (e.g., 30–60s) + monitor settings balance failover speed vs DNS load.

**B3. How does the Performance method measure latency, and what are its caveats (resolver location)?**
**Answer:** TM uses an **internet latency table** (Microsoft's measured latencies between user networks and Azure regions) to pick the lowest-latency endpoint. Caveat: it routes based on the **DNS resolver's location** (client subnet via EDNS0 when supported), not the end user precisely — so some users may be routed sub-optimally; verify with real-user telemetry.

**B4. How does the Geographic method handle "no matching region" (default endpoint)?**
**Answer:** You map regions to endpoints and can designate a **default endpoint** (e.g., for users from unmapped countries, or `Group: World`). Users from mapped regions go to their mapped endpoint; everyone else hits the default. This is essential for geo-compliance designs.

**B5. What are endpoint monitor settings (protocol, port, path, interval, tolerated failures) and how do you tune them?**
**Answer:** Monitor probes (HTTP/HTTPS GET on a path, or TCP) run every 10–30s; an endpoint is marked **degraded** after a number of consecutive failures (tolerated failures). Tune: use an **app-specific health path** (not `/`), set tolerated failures to avoid flapping, and note TM probes come from its global monitoring IPs (allow them in NSGs if endpoints are public).

**B6. How do you do weighted A/B testing and gradual region migration with Traffic Manager?**
**Answer:** **Weighted routing**: assign weights (e.g., 90 old / 10 new), adjust gradually (50/50 → 10/90) as confidence grows, and roll back by shifting weights. Remember DNS caching makes the split approximate; for precise control use Front Door percentage routing or App Service slots.

**B7. How do nested profiles combine routing methods (e.g., performance + failover)?**
**Answer:** A parent profile (e.g., **Performance**) has child profiles as endpoints; each child (e.g., **Priority**) handles its region's failover. Example: Performance across three regions, each region = a Priority profile (primary + standby). This layers methods for complex topologies.

**B8. How does Traffic Manager handle endpoint types (Azure, external, nested) and what are the requirements?**
**Answer:** Endpoints can be **Azure** (App Service, Public IP, cloud service) or **External** (any public IP/FQDN). All endpoints must be **internet-facing** (publicly reachable) for monitoring. Azure endpoints can auto-configure their monitor; external endpoints need manual monitor settings.

**B9. What is the difference between Traffic Manager and Azure Front Door for failover speed and features?**
**Answer:** TM = DNS failover (TTL-bound, seconds-to-minutes) with no WAF/caching/rewrite. Front Door = **anycast edge proxy** — failover is near-instant (no TTL), plus WAF, caching, URL rewrite, TLS at edge. For mission-critical global apps needing instant failover + security, Front Door; for simple multi-region DNS steering, TM.

**B10. How do you monitor Traffic Manager (metrics, endpoint status, alerts)?**
**Answer:** Metrics: **ProbeAgentCurrentEndpointStateByProfileResourceId** (endpoint up/down), **QpsByEndpoint**, **EndpointStatus**. Set **alerts** on endpoint status change (degraded/disabled), and correlate with endpoint-side monitors. Use the TM **endpoint health view** for at-a-glance status.

**B11. What are the security considerations for Traffic Manager?**
**Answer:** TM endpoints must be public, so protect them with **NSGs/WAF/Front Door** and restrict direct access (allow only expected clients), use **HTTPS** everywhere, monitor DNS hijacking (lock the domain, DNSSEC), and restrict TM management via RBAC + Activity Log alerts. TM itself doesn't do TLS termination — it just routes DNS.

**B12. How do you design multi-region active-active with Traffic Manager and avoid "split brain" data issues?**
**Answer:** Use **Performance routing** (or weighted) across regional stacks, with **replicated/geo-redundant data** (Cosmos DB multi-region, SQL geo-replication, storage GRS) so each region serves consistent data. Health checks drop unhealthy regions automatically. For write consistency, choose a primary write region (or multi-master Cosmos) to avoid conflicts.

---

## Case C — Scenario

**C1. Scenario:** A global web app runs in two regions; you want users to hit the nearest region and auto-failover if one region dies.
**Question:** Which routing method + setup?
**Answer:** **Performance routing** with both regions as endpoints + **endpoint monitors** (HTTPS health path). Users resolve to the lowest-latency region; if one region's monitor fails, TM stops returning it. Set a **short TTL** (30–60s) for faster failover, and ensure data is replicated between regions.

**C2. Scenario:** During a regional outage, some users couldn't reach the app for 10+ minutes despite failover configured.
**Question:** Why, and how do you improve?
**Answer:** **DNS caching** — clients/resolvers kept the old (failed) region's IP until TTL expiry. Improve: lower TTL, tune monitor settings for faster detection, or migrate to **Azure Front Door** (edge proxy with instant failover, no TTL dependency) for mission-critical workloads.

**C3. Scenario:** You must route EU users to the EU region and US users to the US region, with a fallback for everyone else.
**Question:** Design it.
**Answer:** **Geographic routing**: map Europe → EU endpoint, North America → US endpoint, and set the **default endpoint** (e.g., the US region or a neutral one) for unmapped regions. Add **health checks** so a failed region's users fall back to the default.

**C4. Scenario:** A SaaS is migrating from on-prem to Azure; you want to shift 10% → 50% → 100% of users gradually.
**Question:** How?
**Answer:** **Weighted routing** with the on-prem IP as an **external endpoint** and the Azure endpoint; start 90/10, ramp 50/50, then 0/100 as you validate. Accept that DNS caching makes the split approximate; monitor error rates per endpoint and roll back weights if issues appear.

**C5. Scenario:** An endpoint's monitor fails, but the endpoint is actually serving fine.
**Question:** Diagnose.
**Answer:** Check the monitor config: wrong **protocol/port/path** (e.g., probing `/` which returns 404/redirect), the endpoint's **NSG/firewall blocking Traffic Manager's monitoring IPs**, or **tolerated failures** set too low (flapping). Verify the health path returns 2xx from TM's probe IPs and adjust.

**C6. Scenario:** You need to combine "nearest region" with "failover within the region" (primary + standby per region).
**Question:** Design with nested profiles.
**Answer:** Create a **Priority profile per region** (primary + standby endpoints). Create a **parent Performance profile** whose endpoints are the three regional Priority profiles. Users route to the nearest region (performance), and within that region, priority handles local failover. This is the classic nested-profile pattern.
