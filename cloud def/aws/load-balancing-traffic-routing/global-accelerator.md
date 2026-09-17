# AWS Global Accelerator — Interview Questions

> **Cloud:** AWS · **Category:** Load Balancing & Traffic Routing · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~9 min

---

## JSON File Format

Global Accelerator resources are JSON in CloudFormation: `AWS::GlobalAccelerator::Accelerator`, `::Listener`, `::EndpointGroup`, `::Endpoint`.

```json
{
  "Type": "AWS::GlobalAccelerator::Accelerator",
  "Properties": {
    "Name": "my-accelerator",
    "IpAddressType": "IPV4",
    "Enabled": true
  }
}
```

**Key fields:** `IpAddressType` (IPV4 / DUAL_STACK) · `IpAddresses` (BYOIP) · Listener `PortRanges` + `Protocol` (TCP/UDP) · EndpointGroup `EndpointGroupRegion` + `TrafficDialPercentage` (0–100) · Endpoint `Weight`.


## Case A — Basic

**A1. What is AWS Global Accelerator?**
**Answer:** A networking service that provides **two static anycast IP addresses** as a fixed entry point for your application and routes traffic over AWS's global backbone to the nearest/healthiest regional endpoint (ALB, NLB, EC2, or Elastic IP).

**A2. What problem does Global Accelerator solve?**
**Answer:** It removes dependence on DNS for failover/latency (no TTL waiting), gives static IPs (no IP changes when you swap endpoints), and routes over AWS's backbone instead of the public internet for better latency and jitter.

**A3. How is Global Accelerator different from CloudFront?**
**Answer:** CloudFront is a CDN that **caches content** at edge locations (best for static/cacheable content, HTTP/HTTPS). Global Accelerator does **no caching** — it's a network-path optimizer for any TCP/UDP application (best for dynamic apps, gaming, IoT, APIs, VoIP).

**A4. What are the main components of Global Accelerator?**
**Answer:** Accelerator (with 2 static anycast IPs), **listeners** (TCP/UDP ports), **endpoint groups** (per region, with traffic dials), and **endpoints** (ALB/NLB/EC2/EIP) with weights.

**A5. Does Global Accelerator work with non-HTTP protocols?**
**Answer:** Yes — it supports **TCP and UDP**, so it works for gaming, IoT, custom protocols, and databases, unlike CloudFront (HTTP/S only).

**A6. What are the two static IP addresses Global Accelerator provides?**
**Answer:** Two anycast IPv4 addresses (you can also bring your own IPs via BYOIP). They're announced from many edge locations, so clients always connect to the nearest edge.

**A7. How does Global Accelerator choose which endpoint to send traffic to?**
**Answer:** Traffic enters the nearest edge location, then travels the AWS backbone to the **healthiest endpoint** in the closest region (based on traffic dials and endpoint weights, plus health checks).

**A8. What is an "endpoint group" and "traffic dial"?**
**Answer:** An endpoint group is a set of endpoints in one region. The **traffic dial** (0–100%) controls the percentage of traffic that region receives — used to shift traffic between regions (e.g., failover or migration).

**A9. Does Global Accelerator provide health checks?**
**Answer:** Yes — it monitors endpoint health (ALB/NLB/EC2) and automatically routes around unhealthy endpoints, enabling fast, DNS-independent failover.

**A10. What is the benefit of routing over the AWS backbone?**
**Answer:** Lower, more consistent latency and fewer internet hops/packet loss compared to the public internet. Each TCP/UDP flow stays on the backbone from the edge to the endpoint.

**A11. Can Global Accelerator front a Lambda function?**
**Answer:** Not directly — endpoints are ALB/NLB/EC2/EIP. You can front an ALB that targets Lambda, or use API Gateway/CloudFront for Lambda-backed HTTP APIs.

**A12. Is Global Accelerator regional or global?**
**Answer:** **Global** — the accelerator itself is global (anycast IPs worldwide), while its endpoint groups span regions.

**A13. What is client affinity (sticky sessions) in Global Accelerator?**
**Answer:** It keeps a client's connections routed to the same endpoint (for stateful apps) for a configurable period, using a 5-tuple/source-IP based affinity.

**A14. What are Global Accelerator's pricing components?**
**Answer:** A fixed hourly charge per accelerator + a **data transfer premium (DT-Premium)** per GB for traffic in the dominant direction. It does not change AWS data transfer fees you already pay.

**A15. Does Global Accelerator cache responses like a CDN?**
**Answer:** No. It never caches — it only optimizes the network path. For caching you combine it with CloudFront or put a CDN for static assets separately.

---

## Case B — Advanced (Senior)

**B1. Explain the anycast model: why do the two static IPs matter and how do they improve failover vs DNS-based failover?**
**Answer:** Anycast announces the same two IPs from many edge POPs, so clients connect to the nearest POP (lowest latency) regardless of DNS. Because the IPs never change, you avoid DNS TTL delays during failover — if a region dies, the edge simply routes the same IP to the next healthy endpoint over the backbone, giving near-instant recovery compared to Route 53 failover.

**B2. How do you design multi-region active-active with Global Accelerator (traffic dials + weights)?**
**Answer:** Create endpoint groups for each region with traffic dials distributing load (e.g., 60/40). Within a region, set endpoint weights across ALBs/NLBs. Health checks remove unhealthy endpoints automatically, and the remaining traffic rebalances. Use client affinity only if the app is stateful.

**B3. When would you combine CloudFront + Global Accelerator, and in what order?**
**Answer:** Use both when you need caching **and** static IP/backbone routing for dynamic parts: e.g., CloudFront for static assets (cache hit at edge) and Global Accelerator for the dynamic API/WebSocket origin (no cache). They serve different layers; GA can even front the origin that CloudFront uses. Order depends on need — CloudFront→GA is uncommon; typically they're used in parallel for different traffic.

**B4. What is BYOIP and what are its requirements in Global Accelerator?**
**Answer:** Bring Your Own IP lets you use your own public IPv4 range (via ROA/RPKI authorization and ownership proof) so clients allowlist your IPs and you keep IP reputation during migrations. AWS advertises your /24 over its edge network for the accelerator.

**B5. How does Global Accelerator improve performance for real-time apps (gaming/VoIP/UDP)?**
**Answer:** UDP traffic enters the nearest edge and rides the AWS backbone (fewer hops, lower jitter, less packet loss) to the endpoint. Combined with static anycast IPs and instant failover, this is why it's recommended for game servers, VoIP, and IoT instead of raw internet routing.

**B6. How do you shift traffic between regions for a DR event (regional failover)?**
**Answer:** Update the **traffic dial** on the endpoint group (or use health-based automatic failover). E.g., set primary region dial 100%, DR region dial 0% (or a small standby dial). On failure, raise the DR dial to 100%. Because IPs are static, clients reconnect to the same IP over the backbone without DNS changes.

**B7. Compare Global Accelerator vs Route 53 latency-based routing vs NLB static IPs.**
**Answer:** Route 53 LBR = DNS-level steering (suffers TTL delays, client DNS caching). NLB EIPs = static IPs but **regional only** (no global anycast). Global Accelerator = global anycast static IPs + backbone routing + health-based failover + TCP/UDP. GA is the strongest for global, latency-sensitive, non-HTTP workloads.

**B8. How does Global Accelerator's health checking differ from ALB/NLB health checks?**
**Answer:** GA performs its own health checks against endpoints (for ALB/NLB it checks the LB; for EC2/EIP it checks TCP/HTTP). It uses these to make routing decisions and to automatically move traffic away from unhealthy regions — an independent, global health layer on top of the regional LBs' own target health checks.

**B9. What are the key limits/quotas for Global Accelerator?**
**Answer:** e.g., accelerators per account, listeners per accelerator, endpoint groups per listener (one per region), endpoints per group, and bandwidth per accelerator. Also DT-Premium cost scales with dominant-direction traffic — budget for it. (Check current docs for exact numbers.)

**B10. Explain "client affinity" internals and when to disable it.**
**Answer:** Affinity binds a client (by source IP) to a specific endpoint for a set duration so stateful sessions stay put. Disable it for stateless workloads so traffic can be redistributed freely for better balance and faster failover; enable it only when the backend truly needs session stickiness at the connection level.

**B11. How does Global Accelerator handle TLS?**
**Answer:** GA is L3/L4 — it does **not terminate TLS**. TLS passes through to the endpoint (ALB/NLB). So certificates remain on the load balancer, and GA can accelerate any TCP including TLS connections transparently.

**B12. How would you measure the benefit of Global Accelerator for your app?**
**Answer:** Baseline RTT/latency/jitter and packet loss with and without GA (client → regional ALB directly vs via GA) across key geographies. Use CloudWatch GA metrics (new flow count, processed bytes, healthy endpoint count) and client-side telemetry. Justify DT-Premium cost against measured latency improvement and reduced failover time.

---

## Case C — Scenario

**C1. Scenario:** A global gaming company needs UDP game traffic with lowest possible latency, static IPs for client configs, and instant failover if a region dies.
**Question:** Design the network entry.
**Expected answer:** **Global Accelerator** with a UDP listener, two static anycast IPs, and endpoint groups per region (NLB/EC2 endpoints) with traffic dials. Clients hardcode the static IPs. If a region fails, health checks re-route to healthy endpoints over the backbone with no DNS change and no client reconfiguration.

**C2. Scenario:** Your API is behind an ALB in us-east-1. During a region outage, DNS-based failover took 10+ minutes because of TTL and client caches.
**Question:** How do you get near-instant failover?
**Expected answer:** Front the ALBs with **Global Accelerator** (endpoint groups in us-east-1 and us-west-2, traffic dials). The static anycast IPs don't change, so clients reconnect to the same IP and GA routes to the healthy region immediately over the backbone — no DNS dependency. Keep Route 53 as a fallback/control-plane only.

**C3. Scenario:** A VoIP provider must give telecom carriers two fixed IPs for SIP/RTP, allowlistable in their firewalls, with global reach.
**Question:** Propose the solution and note any considerations.
**Expected answer:** Global Accelerator with TCP (SIP) and UDP (RTP) listeners on the two static IPs; endpoint groups in multiple regions with NLBs. Considerations: client affinity for SIP sessions, health checks for SIP endpoints, and possibly BYOIP so the provider keeps its existing IPs. RTP benefits from backbone routing (low jitter).

**C4. Scenario:** You're migrating a SaaS from an old datacenter to AWS and clients have your old IPs hardcoded/allowed in firewalls.
**Question:** How can Global Accelerator + BYOIP smooth the migration?
**Expected answer:** Bring your **own IP range** (BYOIP) into Global Accelerator so the app keeps the **same public IPs** clients already use. Cut over by pointing the accelerator's endpoint groups at AWS endpoints (ALB/NLB) — clients see no IP change, avoiding firewall updates and DNS migrations.

**C5. Scenario:** A global web app serves dynamic content (no cacheable pages) to users in 30 countries; latency is inconsistent over the public internet.
**Question:** Why choose Global Accelerator over CloudFront here?
**Expected answer:** CloudFront caches content — with little cacheable content it adds little and still traverses the public internet from edge to origin. Global Accelerator routes every request over the AWS backbone to the origin with static IPs and health-based routing, directly cutting latency/jitter for **dynamic** traffic. Combine with CloudFront only for static assets.

**C6. Scenario:** During a load test through Global Accelerator, one region's ALB gets overwhelmed while another region sits idle, despite equal traffic dials.
**Question:** Diagnose and fix.
**Expected answer:** Likely **client affinity** is pinning users to one endpoint/region, or endpoint weights are uneven, or the traffic dial/weights were misconfigured. Fix: disable affinity for stateless traffic, set equal weights, verify health checks so both regions are healthy, and confirm the dial values. Use GA CloudWatch metrics (processed bytes/endpoint) to verify balance.
