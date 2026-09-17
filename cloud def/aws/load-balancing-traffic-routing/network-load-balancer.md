# Network Load Balancer (NLB) — Interview Questions

> **Cloud:** AWS · **Category:** Load Balancing & Traffic Routing · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~9 min

---

## JSON File Format

NLB is JSON via CloudFormation `AWS::ElasticLoadBalancingV2::LoadBalancer` with `Type: network`. Static IPs are expressed as per-subnet **mappings** with Elastic IP allocations.

```json
{
  "Type": "AWS::ElasticLoadBalancingV2::LoadBalancer",
  "Properties": {
    "Type": "network",
    "Scheme": "internal",
    "SubnetMappings": [
      { "SubnetId": "subnet-a", "AllocationId": "eipalloc-0aaa" },
      { "SubnetId": "subnet-b", "AllocationId": "eipalloc-0bbb" }
    ]
  }
}
```

**Key fields:** `Type` (network) · `Scheme` (internet-facing / internal) · `SubnetMappings` (one entry per AZ; `AllocationId` = static EIP) · listeners (`TLS`/`TCP`/`UDP`) and target groups (`Protocol: TCP_UDP`).


## Case A — Basic

**A1. What is a Network Load Balancer?**
**Answer:** A Layer 4 load balancer that routes TCP, UDP, and TLS traffic to targets at very high throughput and ultra-low latency, while preserving the client's source IP.

**A2. What OSI layer does an NLB operate at?**
**Answer:** Layer 4 (transport). It forwards connections based on IP/protocol/port without inspecting application content (no HTTP routing rules).

**A3. What are the key differences between NLB and ALB?**
**Answer:** NLB = Layer 4, static IPs, extreme performance, source-IP preservation, no WAF/content routing. ALB = Layer 7, content-based routing, TLS offload, WAF, sticky sessions, Lambda targets. Choose NLB for raw TCP/UDP/TLS and performance; ALB for HTTP apps.

**A4. Does an NLB have a static IP address?**
**Answer:** Yes — you can assign **Elastic IPs** to an NLB (one per AZ/subnet), which is a key reason teams choose NLB when clients need to allowlist fixed IPs.

**A5. What protocols does an NLB support?**
**Answer:** TCP, UDP, TCP_UDP (same port both protocols), and TLS.

**A6. What target types does an NLB support?**
**Answer:** **Instance** (EC2), **IP** (any private IP — on-prem via DX/VPN, other VPCs, containers), and **ALB** (NLB in front of ALB to combine static IP + L7 features).

**A7. Does an NLB terminate TLS?**
**Answer:** Yes, it can (TLS listener with a certificate) and can also pass through TCP without terminating. For end-to-end encryption you can re-encrypt to targets.

**A8. Does an NLB support Security Groups?**
**Answer:** Yes — newer NLBs support security groups (in addition to the subnet NACLs). You can restrict which clients can reach the NLB.

**A9. How is an NLB made highly available?**
**Answer:** Enable it in multiple AZs; each AZ gets a node (with an EIP if assigned). The DNS name resolves to the node IPs.

**A10. Does an NLB preserve the client source IP?**
**Answer:** Yes — for instance/IP targets the client's source IP is preserved by default (unlike ALB), which is why NLB is often used where the backend needs the real IP (or for white-listing).

**A11. What is a "target group" for NLB and its health check types?**
**Answer:** A group of targets with health checks. NLB health checks can be TCP (connection success), HTTP, or HTTPS (status codes), depending on target type.

**A12. What is "cross-zone load balancing" on an NLB?**
**Answer:** When enabled, each NLB node can distribute traffic to targets in **all** AZs (default **disabled** for NLB, unlike ALB where it's enabled by default). Disabled means AZ-local routing, which can cause imbalance.

**A13. Can an NLB route based on URL path?**
**Answer:** No — Layer 4 only. Path-based routing requires an ALB (Layer 7). You can combine: NLB → ALB.

**A14. What is a common reason to put an NLB in front of an ALB?**
**Answer:** To get **static IPs** (NLB EIPs) plus ALB's Layer 7 features (WAF, path routing, TLS offload). Clients see fixed IPs; NLB forwards to the ALB.

**A15. What is the connection idle timeout on an NLB?**
**Answer:** 350 seconds for TCP (and 120s for UDP flows). Long-lived idle connections must use keepalives below this.

---

## Case B — Advanced (Senior)

**B1. Explain NLB's architecture (nodes, ENIs, zonal IPs) and why it can handle millions of RPS.**
**Answer:** Each enabled AZ gets an NLB node (an ENI with its own IP/EIP). DNS returns all node IPs; clients connect to a node, which routes to targets. Because it operates at L4 with connection-level hashing and no content inspection, it achieves very high throughput and single-digit-millisecond latency, scaling automatically.

**B2. How does NLB handle source-IP preservation, and when is that a problem?**
**Answer:** With instance targets, the client's IP is preserved by default (packets arrive with the original source IP). Problem: if the target is also behind a security group, the target's SG must allow the **client IPs** (not an NLB IP), and return traffic may be asymmetric. With **IP targets** in a different subnet, you can choose client-IP preservation or the NLB node's IP as source.

**B3. Why might you disable cross-zone load balancing on an NLB, and what's the tradeoff?**
**Answer:** Disabling keeps traffic within an AZ (no cross-AZ data charges, lower latency, but uneven distribution if targets are unevenly spread). Enabling balances across AZs but adds cross-AZ cost/latency. Choose per cost/latency vs. balance requirements; monitor healthy-target distribution.

**B4. How does NLB TLS work, including passthrough vs termination vs re-encryption?**
**Answer:** (1) **TCP passthrough**: NLB forwards raw TCP, TLS ends at the target (NLB sees nothing). (2) **TLS termination**: NLB terminates with an ACM cert and forwards plaintext to targets. (3) **Terminate + re-encrypt**: TLS listener with TLS target group — NLB re-encrypts to the backend, giving end-to-end encryption with centralized certs.

**B5. How does an NLB interact with PrivateLink (VPC Endpoint Services)?**
**Answer:** An NLB is the entry point for a **VPC Endpoint Service**. Consumers create Interface Endpoints that connect privately to your NLB. Requirements: internal NLB, enable proxy protocol if targets need client IPs, and manage endpoint service permissions (which accounts can connect).

**B6. What is Proxy Protocol v2 and why does NLB use it?**
**Answer:** Proxy Protocol prepends the original client IP/port to the connection when the NLB forwards traffic — used for IP/instance targets when client-IP preservation would otherwise be lost (e.g., when targets see the NLB node IP, or with TLS termination). Backends must be configured to parse it.

**B7. How do you design NLB for hybrid (on-premises) targets?**
**Answer:** Use **IP target groups** with the on-prem private IPs, reachable over Direct Connect/VPN. NLB routes to those IPs; health checks cross the DX/VPN link. This lets you load balance to on-prem servers from the cloud with a fixed entry point.

**B8. Compare NLB vs ALB vs Global Accelerator for a latency-sensitive, static-IP, global service.**
**Answer:** NLB = regional, static EIPs, L4. ALB = regional, L7, no static IP. Global Accelerator = global anycast entry (two static IPs) that routes to regional ALB/NLB/EC2 over AWS backbone — best for global users needing static IPs + backbone routing + L7 features via ALB behind it.

**B9. What are NLB's limits you must design around?**
**Answer:** Targets per target group, target groups per NLB, listeners, and per-flow/connection behaviors (idle timeout 350s). Also the number of EIPs equals AZs. For extreme scale, spread targets across AZs and use multiple NLBs. Check current quotas since they change.

**B10. How do NLB health checks differ from ALB, and what does "healthy threshold/unhealthy threshold" do?**
**Answer:** NLB supports TCP/HTTP/HTTPS checks (ALB adds gRPC). Thresholds define consecutive successes/failures before marking healthy/unhealthy, and the interval controls frequency. For UDP targets, health checks still use TCP/HTTP (since UDP has no handshake). Tuning these avoids flapping during deploys.

**B11. How does NLB behave during AZ failures or target failures?**
**Answer:** The NLB's per-AZ node fails over via DNS (clients re-resolve to other node IPs). Unhealthy targets are drained; with cross-zone LB enabled, other AZs' nodes serve the failed AZ's traffic. DNS TTL matters — clients with long DNS caching may keep trying a dead node IP, so use Global Accelerator or Route 53 failover for faster convergence.

**B12. When would you *not* use an NLB and pick ALB instead?**
**Answer:** When you need content-based routing (paths/hosts), header-based routing, WAF, Cognito/OIDC auth, sticky sessions via app cookies, redirects/fixed responses, Lambda targets, or HTTP/2/gRPC — all Layer 7 features that NLB lacks.

---

## Case C — Scenario

**C1. Scenario:** A partner requires your API to be reachable only from their firewall, which can only allowlist fixed IP addresses. Your service runs on auto-scaling EC2 behind an ALB.
**Question:** How do you give them fixed IPs without losing L7 features?
**Expected answer:** Put an **NLB with Elastic IPs** in front of the existing **ALB** (NLB target type = ALB). The partner allowlists the NLB's EIPs; NLB forwards to the ALB, which keeps path routing, WAF, and TLS. This is the classic "static IP in front of ALB" pattern.

**C2. Scenario:** A game server uses UDP, needs very high packets-per-second, and must see each player's real IP for anti-cheat.
**Question:** Which load balancer and settings?
**Expected answer:** **NLB** with a **UDP** listener and **instance** or **IP targets** with **client IP preservation** enabled so the game server sees the real player IP. Enable cross-zone LB only if needed; use TCP-based health checks since UDP has no handshake; assign EIPs if players must connect to static IPs.

**C3. Scenario:** Backend servers log the NLB node IP instead of client IPs for some connections after you enabled TLS termination.
**Question:** Why, and how do you restore real client IPs?
**Expected answer:** With TLS termination, the NLB opens a new connection to the target, so the source becomes the NLB node IP. Fix: enable **Proxy Protocol v2** on the target group and configure the backend (nginx/Apache/app) to parse the proxy-protocol header to recover the original client IP/port.

**C4. Scenario:** You expose an internal service to 15 customer accounts via PrivateLink. Customers occasionally see connection resets.
**Question:** What checks would you perform on the NLB side?
**Answer:** Verify (1) NLB is **internal** with the correct target group health (targets healthy), (2) **cross-zone** is enabled so consumers in any AZ reach all targets, (3) idle timeout (350s) isn't killing idle connections (advise keepalives), (4) target SG/NACL allow endpoint traffic, (5) endpoint service permissions include the right accounts and no accept-pending connections are stuck.

**C5. Scenario:** An on-premises failover design: primary app on-prem, standby in AWS behind an NLB using IP targets. Failover causes intermittent 5xx for a few minutes.
**Question:** Diagnose.
**Expected answer:** Likely health checks hadn't yet marked the standby IPs healthy, or DNS caching pointed clients at stale node IPs, or cross-zone imbalance. Verify health check thresholds/intervals, pre-register standby IPs (or use warm standby with passing checks), and tune Route 53 TTL / use Global Accelerator to shorten convergence during failover.

**C6. Scenario:** A microservices platform wants service discovery + L4 routing with mTLS end-to-end (client → service, service → service) and static ingress IPs.
**Question:** Propose the ingress + mesh design.
**Expected answer:** Use an **NLB (EIPs) with a TCP/TLS passthrough listener** at the ingress so TLS/mTLS terminates at the service mesh (e.g., Envoy/App Mesh sidecars) — preserving end-to-end encryption and client identity. The mesh handles service discovery and L7 policy internally. NLB's L4 passthrough keeps the mesh's mTLS intact while giving static IPs.
