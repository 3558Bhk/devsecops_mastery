# Azure Hub & Spoke Architecture — Interview Questions

> **Cloud:** Azure · **Category:** Networking · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~9 min

---

## JSON File Format

Hub-spoke connectivity is expressed in JSON as **VNet peering** ARM resources (`Microsoft.Network/virtualNetworks/virtualNetworkPeerings`) plus route tables (`Microsoft.Network/routeTables`).

```json
{
  "type": "Microsoft.Network/virtualNetworks/virtualNetworkPeerings",
  "apiVersion": "2023-04-01",
  "name": "hub/spokeA-to-hub",
  "properties": {
    "remoteVirtualNetwork": { "id": "/subscriptions/<sub>/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/hub" },
    "allowVirtualNetworkAccess": true,
    "allowForwardedTraffic": true,
    "useRemoteGateways": true
  }
}
```

**Key fields:** `remoteVirtualNetwork.id` · `allowVirtualNetworkAccess` (enable peering) · `allowForwardedTraffic` (NVA transit) · `allowGatewayTransit` / `useRemoteGateways` (share the hub's VPN/ER gateway). UDRs are `routeTables` with `routes[]` (nextHopType: VirtualAppliance/VirtualNetworkGateway).


## Case A — Basic

**A1. What is a hub-and-spoke network topology in Azure?**
**Answer:** A central **hub VNet** hosts shared services (firewall, VPN/ExpressRoute gateway, DNS, management), and **spoke VNets** host workloads — all spokes connect to the hub (via peering) and route through it for shared services.

**A2. What typically lives in the hub VNet?**
**Answer:** Azure Firewall/NVA, VPN or ExpressRoute gateway, Azure Bastion, DNS resolvers, monitoring/logging, and sometimes Active Directory domain controllers.

**A3. What lives in the spoke VNets?**
**Answer:** Workloads — web/app/db VNets, per-team or per-application environments (dev/test/prod), each isolated but connected to the hub.

**A4. How do spokes connect to the hub?**
**Answer:** Via **VNet peering** (same or cross-region/subscription). Peering is non-transitive, so spokes route **through the hub** to reach each other or on-prem.

**A5. Is VNet peering transitive in a hub-spoke design?**
**Answer:** No — peering is **non-transitive** by default. Spoke-to-spoke communication requires either peering them directly, routing through a hub **NVA/firewall**, or using **Azure Virtual WAN**.

**A6. What are the benefits of hub-and-spoke?**
**Answer:** Centralized security/egress (one firewall), centralized hybrid connectivity (one gateway), cost savings (shared resources), consistent governance, and isolation between spokes.

**A7. What are the downsides?**
**Answer:** Hub can become a bottleneck/single point of failure (needs HA), added latency for inter-spoke traffic, and management complexity as spokes grow.

**A8. What is forced tunneling in hub-spoke?**
**Answer:** Routing a spoke's 0.0.0.0/0 (and often inter-spoke traffic) through the hub's **firewall/NVA** so all traffic is inspected centrally.

**A9. How does a spoke reach on-premises in a hub-spoke design?**
**Answer:** Through the hub's **VPN/ExpressRoute gateway** — on-prem traffic enters the hub, then routes to the spoke via peering (and the gateway can also be shared across spokes).

**A10. What is Azure Virtual WAN and how does it relate to hub-spoke?**
**Answer:** Virtual WAN is Microsoft's **managed hub-spoke** service: a global hub that natively connects VNets, branches (VPN/ER), and provides routing + security — replacing the manual build-your-own hub-spoke.

**A11. Can hub and spokes be in different subscriptions?**
**Answer:** Yes — peering works across subscriptions (and tenants), enabling a central "connectivity" subscription owning the hub, with workload subscriptions owning spokes.

**A12. What is a "landing zone" in this context?**
**Answer:** The Azure landing-zone (Enterprise-Scale) reference architecture: a **connectivity subscription** (hub) + **identity/management** subscriptions + **workload subscriptions** (spokes) organized with consistent policy.

**A13. How do you share DNS in hub-spoke?**
**Answer:** Use **Azure Private DNS zones** linked to the hub (and spokes), or custom DNS servers (e.g., domain controllers in the hub) referenced by spoke VNets.

**A14. What is the recommended way to route spoke-to-spoke through the hub?**
**Answer:** **UDRs** pointing inter-spoke prefixes (or 0.0.0.0/0) to the hub **firewall/NVA**, with IP forwarding enabled — since peering alone won't transit traffic.

**A15. What is the difference between hub-spoke and a full mesh?**
**Answer:** Hub-spoke = N spokes → 1 hub (N peerings, centralized). Full mesh = every VNet peered to every other (N(N−1)/2, no central control). Hub-spoke is the scalable, governable default.

---

## Case B — Advanced (Senior)

**B1. Explain the routing mechanics of hub-spoke: why peering alone isn't enough for spoke-to-spoke, and the role of UDRs + IP forwarding.**
**Answer:** Peering gives spoke→hub connectivity, but a packet from Spoke-A to Spoke-B arriving at the hub must be **forwarded** by a hub resource (firewall/NVA) — Azure won't transit by default. So you (1) put an NVA/firewall in the hub, (2) add **UDRs** in each spoke (0.0.0.0/0 or inter-spoke CIDRs → the NVA), (3) enable **IP forwarding** on the NVA's NIC, and (4) ensure symmetric return routes. This makes the hub a real transit router.

**B2. How do you make the hub highly available (avoiding a single point of failure)?**
**Answer:** Deploy the firewall/NVA in an **active-active or active-passive** configuration across **Availability Zones**, use **Azure Firewall** (managed, auto-HA) or an NVA cluster with a load balancer, redundant gateways (VPN active-active), and zone-redundant DNS. Test failover regularly.

**B3. Compare "build-your-own hub-spoke" vs Azure Virtual WAN for enterprise scale.**
**Answer:** DIY hub-spoke = full control, but you manage gateways, routing tables, firewalls, and scale limits per VNet. **Virtual WAN** = Microsoft-managed hub with built-in transitive routing, branch connectivity (VPN/ER/SD-WAN), integrated Azure Firewall (Secure Virtual Hub), and global mesh — less control, far less ops. Choose VWAN for large/branch-heavy estates; DIY for smaller or highly-customized ones.

**B4. How does the Enterprise-Scale landing zone structure hub-spoke (management/connectivity/identity subscriptions)?**
**Answer:** It defines a **Platform** group (Connectivity subscription = hub/VWAN + firewall + gateways; Identity subscription = domain controllers; Management subscription = monitoring/security tooling) and **Landing zone** subscriptions (workloads = spokes, connected via peering to the hub). Policy (Azure Policy) enforces routing, NSG baselines, and peering rules across all spokes.

**B5. What is "spoke-to-spoke via the hub" vs "direct peering between spokes," and how do you decide?**
**Answer:** Routing through the hub = centralized inspection but hub bandwidth/latency and firewall throughput limits. Direct peering = low latency/high bandwidth but bypasses central inspection (and governance). Decide by security policy: if all east-west must be inspected, force through the hub; otherwise direct-peer for high-throughput pairs (with documented exceptions).

**B6. How do you handle overlapping IP spaces across spokes in a hub-spoke model?**
**Answer:** Overlapping spoke CIDRs break routing (ambiguous routes). Solutions: enforce **non-overlapping** addressing via policy/IPAM, use **NAT on the firewall** for specific overlaps, or isolate overlapping environments behind **separate hubs**. Best practice: unique, planned CIDRs per spoke from the start.

**B7. Explain UDR design for forced tunneling and the "0.0.0.0/0 to NVA" caveats (asymmetric routing).**
**Answer:** Forcing 0.0.0.0/0 (or broad prefixes) to the NVA means **both directions** of a flow must pass the NVA or you get asymmetric routing (the return path bypasses the firewall → stateful firewall drops it). Design symmetric routes: route both subnets' traffic to the NVA, and scope UDRs carefully (don't force the NVA's own subnet through itself).

**B8. How do you monitor and secure a hub at scale (flow logs, firewall logs, NSG baselines)?**
**Answer:** Enable **NSG flow logs + Traffic Analytics** on hub and spokes, **Azure Firewall logs** (or NVA logs) to Log Analytics/Sentinel, **UDR/peering change alerts** (Activity Log), and Azure Policy to enforce: peering only to the hub, mandatory UDRs, and NSG baselines. Centralize in the Management subscription.

**B9. How do you plan hub capacity and costs (firewall throughput, peering data transfer)?**
**Answer:** Size the firewall by **aggregate throughput** (Gbps) and connections; remember **peering traffic is billed** (inbound+outbound) — inter-spoke via hub is billed twice (spoke→hub + hub→spoke), so bandwidth-heavy flows may justify direct peering. Track with Cost Management and right-size the firewall SKU.

**B10. What are the scale limits of a hub-spoke (peerings per VNet, routes per route table)?**
**Answer:** Limits include **peerings per VNet** (default ~500, adjustable), **routes per route table** (400), and hub firewall throughput caps. For very large estates, use **Virtual WAN** or multiple regional hubs with inter-hub connectivity (or hub-to-hub peering/mesh).

**B11. How do you connect multiple regions (hub in each region) and route between them?**
**Answer:** Deploy a **regional hub** per region (with local firewall/gateway), peer regional hubs together (or use **Virtual WAN global transit**), and route inter-region spoke traffic via the hubs. For hybrid, attach ExpressRoute/VPN to the appropriate regional hub. VWAN handles this natively; DIY needs explicit UDRs + hub peering.

**B12. What is the role of Azure Policy in enforcing hub-spoke governance?**
**Answer:** Policies can: **deny VNet peerings** not matching an approved hub, **require UDRs** on spoke subnets, **enforce NSG baselines**, **block public IPs** on internal resources, and **restrict service endpoint/private endpoint** usage — making the hub-spoke topology self-enforcing across subscriptions (via Azure Landing Zones / ALZ policy initiatives).

---

## Case C — Scenario

**C1. Scenario:** A company has 30 app teams, each needing isolated VNets with shared internet egress through one firewall and one ExpressRoute to on-prem.
**Question:** Design the topology.
**Expected answer:** **Hub-and-spoke**: one hub VNet with **Azure Firewall** + **ExpressRoute gateway** (+ Azure Bastion/DNS); each team gets a **spoke VNet** peered to the hub; spoke **UDRs** force 0.0.0.0/0 (and inter-spoke) through the firewall; on-prem reaches spokes via the hub gateway. Enforce with Azure Policy and a landing-zone structure.

**C2. Scenario:** Spoke-A and Spoke-B are peered to the hub, but they can't reach each other.
**Question:** Why, and how do you enable it?
**Answer:** Peering is **non-transitive** — no hub resource forwards between peers. Fix: add a **firewall/NVA in the hub**, create **UDRs** in both spokes pointing the other's CIDR (or 0.0.0.0/0) to the NVA, and enable **IP forwarding** on the NVA. Ensure symmetric routes back.

**C3. Scenario:** After forcing all spoke traffic through the hub firewall, some flows intermittently fail, especially to/from on-prem.
**Question:** Diagnose asymmetric routing.
**Expected answer:** Likely **asymmetric routing**: one direction goes through the firewall (via UDR) but the return path doesn't (e.g., on-prem routes back to the spoke directly via the gateway, or another route). The stateful firewall drops the mismatched flow. Fix: make routes **symmetric** — ensure return paths also transit the firewall, and check gateway/UDR route propagation.

**C4. Scenario:** The hub firewall is saturated; inter-spoke traffic is slow, but spoke-to-internet is fine.
**Question:** Options to relieve the hub?
**Answer:** (1) **Direct-peer** high-throughput spoke pairs (bypassing the firewall) with documented exceptions, (2) **scale up/out** the firewall (larger SKU, active-active), (3) split into **multiple regional hubs**, or (4) move to **Virtual WAN** with distributed routing. Analyze traffic first (flow logs/Traffic Analytics) to target the top flows.

**C5. Scenario:** You must connect 3 regions, each with spokes, and let any spoke reach any other with central inspection.
**Question:** Design multi-region hub-spoke.
**Expected answer:** A **hub per region** (firewall + gateway), spokes peered to their regional hub, and the regional hubs **peered/meshed** (or use **Virtual WAN** for native global transit). Route inter-region traffic hub→hub with UDRs, and terminate on-prem connectivity at the primary hub (with regional ER as needed). Virtual WAN is the simpler, scalable answer.

**C6. Scenario:** A new team created a VNet and peered it directly to another team's VNet, bypassing the hub firewall and violating policy.
**Question:** How do you prevent this structurally?
**Answer:** Enforce via **Azure Policy**: deny VNet peerings unless the target is the approved hub VNet (match by resource ID/tag), require **UDRs** on all spoke subnets, and deny direct spoke-to-spoke peering. Combine with **RBAC** (teams can't create peerings) and **Activity Log alerts** on peering creation. This makes the hub-spoke topology self-enforcing.
