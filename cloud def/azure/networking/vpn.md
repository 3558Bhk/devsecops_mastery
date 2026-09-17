# Azure VPN (VPN Gateway) — Interview Questions

> **Cloud:** Azure · **Category:** Networking · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~9 min

---

## JSON File Format

Azure VPN Gateways are ARM JSON: `Microsoft.Network/virtualNetworkGateways`, `localNetworkGateways`, and `connections`.

```json
{
  "type": "Microsoft.Network/virtualNetworkGateways",
  "apiVersion": "2023-04-01",
  "name": "vpn-gw",
  "properties": {
    "gatewayType": "Vpn",
    "vpnType": "RouteBased",
    "sku": { "name": "VpnGw1", "tier": "VpnGw1" },
    "ipConfigurations": [{
      "name": "gw-ip",
      "properties": { "subnet": { "id": "/subscriptions/<sub>/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/GatewaySubnet" } }
    }]
  }
}
```

**Key fields:** `gatewayType` (Vpn / ExpressRoute) · `vpnType` (RouteBased / PolicyBased) · `sku` (VpnGw1–5) · `ipConfigurations[].subnet` (must be **GatewaySubnet**). `localNetworkGateways` JSON holds the on-prem public IP + `localNetworkAddressSpace`; `connections` JSON holds the shared key (`sharedKey`).


## Case A — Basic

**A1. What is Azure VPN Gateway?**
**Answer:** A managed service that provides **encrypted (IPsec/IKE) connectivity** between Azure VNets and on-premises networks (site-to-site) or individual clients (point-to-site), and between VNets.

**A2. What are the VPN Gateway types?**
**Answer:** **VPN** (route-based and policy-based) and **ExpressRoute** gateways. VPN gateways come in SKUs (Basic, VpnGw1–5) with increasing throughput.

**A3. What is the difference between route-based and policy-based VPN?**
**Answer:** **Route-based** (recommended) routes traffic based on routes in the route table — supports any-to-any topology, IKEv2. **Policy-based** routes by traffic selectors (specific IP ranges) — legacy, IKEv1 only.

**A4. What is a Site-to-Site (S2S) VPN?**
**Answer:** An IPsec tunnel between your **on-premises VPN device** and the Azure VPN gateway, connecting your on-prem network to a VNet over the internet.

**A5. What is a Point-to-Site (P2S) VPN?**
**Answer:** A VPN connection from **individual client machines** (laptops) to the VNet — used for admins/developers, using certificates or Entra ID authentication (OpenVPN/IKEv2/SSTP).

**A6. What is a Local Network Gateway?**
**Answer:** The Azure object representing your **on-premises site** — its public IP and address prefixes — used to define the S2S connection's remote end.

**A7. What is a Connection resource?**
**Answer:** The object linking a VPN gateway to a Local Network Gateway (or another VNet gateway), defining the shared key and connection type.

**A8. What is VNet-to-VNet VPN and when is it used instead of peering?**
**Answer:** A VPN tunnel between two VNet gateways — used when the VNets **can't be peered** (overlapping IPs, different tenants/regions with policy restrictions) or when you want encrypted transit. Peering is preferred when possible (lower latency, higher bandwidth).

**A9. What is the difference between VPN and ExpressRoute?**
**Answer:** VPN = encrypted tunnel over the **public internet** (lower cost, variable latency, up to ~10 Gbps). ExpressRoute = **private, dedicated** connection via a carrier (higher bandwidth/reliability, not encrypted by default, higher cost).

**A10. What protocols does Azure VPN support?**
**Answer:** **IKEv2** (route-based, recommended), **IKEv1** (policy-based, legacy), and client protocols **OpenVPN**, **SSTP**, and **IKEv2** for P2S.

**A11. What is the Basic SKU limitation?**
**Answer:** Basic SKU supports only policy-based? (actually it's route-based with restrictions) — limited to **one S2S tunnel**, lower throughput, no active-active, no P2S with some protocols, and is being deprecated for new gateways.

**A12. What is "active-active" VPN?**
**Answer:** Two VPN gateway instances, each with its own public IP, both active — enabling **BGP-based redundancy** and higher availability/throughput.

**A13. What is BGP in Azure VPN?**
**Answer:** Border Gateway Protocol — dynamically exchanges routes between on-prem and Azure (instead of static address prefixes), enabling redundancy, failover, and route propagation (requires route-based gateway).

**A14. How does a VM in a VNet reach on-prem via the VPN gateway?**
**Answer:** The gateway creates **routes** in the VNet (GatewaySubnet) — learned via BGP or the Local Network Gateway prefixes — so subnets route on-prem traffic to the gateway, which encrypts and sends it over the tunnel.

**A15. What is the GatewaySubnet?**
**Answer:** A special subnet named `GatewaySubnet` that hosts the VPN/ExpressRoute gateway instances — it must exist and be the right size (/27 or larger recommended) before creating a gateway.

---

## Case B — Advanced (Senior)

**B1. Explain the site-to-site VPN setup steps and the components involved.**
**Answer:** (1) Create the VNet + **GatewaySubnet** (/27+). (2) Create the **VPN gateway** (route-based, SKU per throughput). (3) Create the **Local Network Gateway** (on-prem public IP + prefixes). (4) Create the **Connection** (S2S, shared key). (5) Configure the **on-prem device** (matching IKE/IPsec policies, PSK). (6) Validate tunnel + routing (BGP or static). Each component maps to a real config element on both sides.

**B2. What are the main causes of S2S tunnel flapping or failure, and how do you troubleshoot?**
**Answer:** Common causes: mismatched **pre-shared key**, mismatched **IKE/IPsec policy settings** (encryption/hash/DH/PFS), on-prem device **idle timeout/firewall** blocking UDP 500/4500, **NAT** breaking IPsec (needs NAT-T on 4500), or **route/BGP** issues. Troubleshoot with **VPN diagnostics**, gateway logs, and packet captures; verify both sides' policy parameters match.

**B3. How does BGP improve VPN redundancy (active-active, multiple tunnels, route failover)?**
**Answer:** With BGP, routes are exchanged dynamically: you can run **active-active** gateways (two public IPs), multiple on-prem devices, and routes fail over automatically when a session drops — no manual static-route updates. BGP also supports **AS-path prepending** for traffic engineering and faster convergence than static routes.

**B4. Compare VPN vs ExpressRoute vs SD-WAN for hybrid connectivity (when to pick each).**
**Answer:** **VPN** = quick, low-cost, internet-based (best for small/medium or backup). **ExpressRoute** = private, guaranteed bandwidth/latency, higher cost (best for production-critical, high-volume, compliance). **SD-WAN (Virtual WAN)** = intelligent multi-path (VPN+ER) with app-aware routing at scale (best for many branches). Often combined: ER primary + VPN backup.

**B5. What are the throughput and scale limits of VPN gateways (SKUs, tunnels, P2S connections)?**
**Answer:** SKUs VpnGw1–5 provide ~650 Mbps–10 Gbps aggregate throughput; limits exist for S2S tunnels (~10–100 per gateway by SKU), P2S concurrent connections, and BGP peers. For >10 Gbps or many branches, use **Virtual WAN** with multiple scale units. Always check current SKU limits when sizing.

**B6. How do you achieve high availability for VPN (active-active, zone-redundant, dual tunnels)?**
**Answer:** (1) **Active-active** gateway (two public IPs, BGP) with two on-prem devices, (2) **zone-redundant** gateways (AZ-spanning, newer SKUs), (3) **dual S2S tunnels** from one gateway to two on-prem endpoints, (4) a **backup connection** (secondary ISP or ExpressRoute). Design for N+1 tunnel redundancy and test failover.

**B7. What is the role of the GatewaySubnet size and why does it matter for HA/scale?**
**Answer:** The GatewaySubnet hosts gateway VMs; too small (/29) limits the gateway's scale/HA options (e.g., can't do active-active or add more instances). Use **/27 or larger** to accommodate redundancy and future growth.

**B8. How does Point-to-Site authentication work (certificate, Entra ID, RADIUS)?**
**Answer:** P2S authenticates via **client certificates** (root cert uploaded to the gateway), **Microsoft Entra ID** (with OpenVPN protocol), or **RADIUS** (external auth server). Entra ID is the modern choice (MFA, conditional access); certificates are traditional; RADIUS integrates with existing AAA.

**B9. How do you monitor VPN health and alert on tunnel down?**
**Answer:** Metrics via **Azure Monitor**: `TunnelAverageBandwidth`, `TunnelEgressBytes`, `TunnelIngressBytes`, `TunnelStatus`, gateway `Throughput`; **Azure Monitor alerts** on `TunnelStatus` down, **VPN diagnostics**/packet capture, and **Connection Monitor**. Route alerts to on-call; correlate with on-prem device logs.

**B10. How does VPN integrate with hub-spoke (shared gateway) and Virtual WAN?**
**Answer:** In hub-spoke, the **hub's VPN gateway** terminates on-prem connectivity and spokes route through the hub (UDR/peering) — one gateway serves all spokes. **Virtual WAN** replaces the DIY gateway with a managed hub that natively terminates VPN/ER across regions with global transit.

**B11. What are the security considerations for VPN (IPsec policies, key rotation, MFA)?**
**Answer:** Use **IKEv2 + strong IPsec** (AES-256, SHA-256, DH group 14+, PFS), rotate **pre-shared keys**, use **BGP** to avoid static route sprawl, enforce **P2S MFA** (Entra ID conditional access), restrict gateway access via RBAC, log with Azure Monitor, and place on-prem devices in a DMZ. Consider **Azure VPN over ExpressRoute** for encryption on ER.

**B12. How does Azure VPN work with overlapping on-prem and Azure address spaces (NAT on VPN)?**
**Answer:** Overlapping spaces break routing. Options: **NAT on the VPN gateway** (available in some configurations — translate overlapping ranges), re-IP one side, or use **Azure Virtual WAN** with NAT. Plan addressing to avoid overlap; NAT adds complexity and should be a last resort.

---

## Case C — Scenario

**C1. Scenario:** A small office (one firewall) needs site-to-site connectivity to an Azure VNet quickly and cheaply.
**Question:** Design it.
**Expected answer:** VNet + **GatewaySubnet**, **route-based VPN gateway** (VpnGw1), **Local Network Gateway** (office public IP + LAN prefixes), **S2S Connection** with PSK, and configure the office firewall (IKEv2, matching policies). For resilience, add a **second tunnel** or backup path; enable BGP if the office device supports it.

**C2. Scenario:** The VPN tunnel is up ("Connected") but VMs can't reach on-prem servers.
**Question:** Diagnose.
**Answer:** Check **routing**: (1) the on-prem prefixes are in the Local Network Gateway (or learned via BGP), (2) the VNet subnets' route tables don't override the gateway routes, (3) **NSGs** on the VMs allow the on-prem CIDRs (both directions), (4) the **on-prem firewall** routes back to the Azure VNet CIDR, and (5) no overlapping IP spaces. Use **Connection troubleshoot/next hop**.

**C3. Scenario:** The primary VPN goes down during an outage; you need automatic failover to a second on-prem site.
**Question:** Design redundancy.
**Answer:** Use an **active-active gateway** (two public IPs) with **BGP**, two on-prem VPN devices, and two connections — BGP withdraws the failed path and routes over the surviving tunnel automatically. Alternatively, two connections from a standard gateway to two Local Network Gateways with BGP failover. Test failover RTO.

**C4. Scenario:** Developers need secure access to a VNet from home, with MFA enforced.
**Question:** Which P2S config?
**Answer:** **Point-to-Site with OpenVPN + Microsoft Entra ID authentication** — configure the P2S gateway for Entra ID, grant developers access, and enforce **MFA via Conditional Access**. This gives certificate-less, MFA-protected remote access with Azure AD identity governance.

**C5. Scenario:** You need high bandwidth (5 Gbps) and low latency to on-prem; the internet path is unreliable.
**Question:** VPN or ExpressRoute? Justify.
**Answer:** **ExpressRoute** — dedicated private circuit with guaranteed bandwidth/latency/SLA, appropriate for 5 Gbps production workloads. VPN over the internet can't guarantee that. Optionally keep a **VPN as backup** to ExpressRoute for resilience. Cost is higher, but justified for the requirements.

**C6. Scenario:** Two VNets can't be peered (overlapping CIDRs, different tenants) but must be connected securely.
**Question:** What's the VPN-based solution?
**Answer:** Create a **VPN gateway in each VNet** and a **VNet-to-VNet connection** between them (or S2S connections to each other's Local Network Gateways). This creates an encrypted tunnel between the VNets — works with overlapping spaces (with NAT where supported) and across tenants, at the cost of gateway throughput/latency vs peering.
