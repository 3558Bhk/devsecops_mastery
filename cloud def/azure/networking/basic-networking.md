# Azure Basic Networking (VNet) — Interview Questions

> **Cloud:** Azure · **Category:** Networking · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~9 min

---

## JSON File Format

Azure VNets are deployed with **ARM templates** (JSON). Every Azure resource follows the same ARM JSON shape: `type`, `apiVersion`, `name`, `properties`.

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "resources": [{
    "type": "Microsoft.Network/virtualNetworks",
    "apiVersion": "2023-04-01",
    "name": "myVNet",
    "properties": {
      "addressSpace": { "addressPrefixes": ["10.0.0.0/16"] },
      "subnets": [
        { "name": "web", "properties": { "addressPrefix": "10.0.0.0/24" } },
        { "name": "db",  "properties": { "addressPrefix": "10.0.1.0/24" } }
      ]
    }
  }]
}
```

**Key fields:** `type` (resource provider path) · `apiVersion` · `name` · `properties.addressSpace` / `subnets[].addressPrefix`. Bicep compiles down to this same ARM JSON.


## Case A — Basic

**A1. What is an Azure Virtual Network (VNet)?**
**Answer:** A logically isolated, private network in Azure where you deploy VMs, databases, and other resources — analogous to a data-center network or an AWS VPC. It provides isolation, segmentation, and connectivity.

**A2. What is a subnet?**
**Answer:** A range of IP addresses within a VNet that segments resources (e.g., web subnet, db subnet) — a boundary for security (NSGs) and routing.

**A3. What is an address space?**
**Answer:** The IP range(s) assigned to a VNet, defined in CIDR notation (e.g., `10.0.0.0/16`). Subnets are carved from this space.

**A4. What is a Network Interface (NIC)?**
**Answer:** The connection point that attaches a VM (or other resource) to a subnet — each VM has at least one NIC with a private IP.

**A5. What is the difference between a private and public IP in Azure?**
**Answer:** **Private IPs** are used within VNets (not internet-routable). **Public IPs** are internet-facing, assigned to resources like load balancers, VMs, and VPN gateways.

**A6. How do resources within a VNet communicate by default?**
**Answer:** All resources in a VNet can communicate with each other by default (across subnets) — no additional config needed, unless you restrict with NSGs.

**A7. What is VNet peering?**
**Answer:** Connecting two VNets directly (same or different regions/subscriptions) over Microsoft's backbone with private IPs — enabling cross-VNet communication without gateways.

**A8. What is a route table (UDR)?**
**Answer:** User-Defined Routes that override Azure's default system routes to steer traffic (e.g., through a firewall/NVA, or to a specific next hop).

**A9. What is an Internet Gateway equivalent in Azure?**
**Answer:** Azure doesn't use a separate IGW resource — internet access is via the **default internet route** on subnets (and a public IP on the resource or NAT).

**A10. What is a NAT Gateway in Azure?**
**Answer:** A managed service that gives outbound-only internet connectivity to private subnets (SNAT), with predictable public IPs and scale.

**A11. What is a DNS server in a VNet?**
**Answer:** By default, Azure-provided DNS resolves VNet-internal names; you can set a custom DNS server at the VNet level for hybrid/custom resolution.

**A12. What is Azure Private Link?**
**Answer:** Private, one-directional connectivity to a PaaS service (or your own service) via a private endpoint in your VNet — traffic never leaves the private network.

**A13. What is a service endpoint?**
**Answer:** Extends a subnet to specific Azure PaaS services (e.g., Storage, SQL) so traffic to them stays on the Microsoft backbone — simpler than Private Link but less granular.

**A14. What is the difference between VNet peering and a VPN gateway?**
**Answer:** Peering connects **VNet-to-VNet** over the Azure backbone (low latency, high bandwidth, no gateway). VPN gateway connects **Azure-to-on-premises** (or VNets) over encrypted IPSec tunnels across the internet.

**A15. Can VNets have overlapping address spaces when peered?**
**Answer:** No — peered VNets (like most connectivity scenarios) must have **non-overlapping** address spaces.

---

## Case B — Advanced (Senior)

**B1. Explain Azure's default system routes and how UDRs interact with them.**
**Answer:** Azure creates system routes: within-VNet, VNet-to-VNet (peering), to the internet (0.0.0.0/0), and to on-prem (via VPN/ER). **UDRs** override system routes (longest-prefix match wins, and UDRs beat system routes for the same prefix). A common pattern: route 0.0.0.0/0 to an **NVA/firewall** to force-tunnel internet traffic through inspection.

**B2. How does VNet peering work across regions and subscriptions, and what are the costs?**
**Answer:** **Global VNet peering** spans regions (over the backbone); peering also works across subscriptions/tenants. Inbound/outbound **data transfer across peered VNets is billed** (unlike within-VNet traffic, which is free). Latency is low but cross-region adds distance; bandwidth is high (no gateway).

**B3. What is the difference between Azure's "virtual network gateway" and "NAT gateway"?**
**Answer:** VNet **gateway** = VPN/ExpressRoute connectivity (site-to-site, point-to-site) — for hybrid networking. **NAT gateway** = outbound internet SNAT for private subnets with static, scalable public IPs. They solve different problems: gateways connect networks; NAT provides outbound internet.

**B4. How do you design a hub-and-spoke topology with a firewall, and what is forced tunneling?**
**Answer:** Central **hub VNet** hosts shared services (Azure Firewall, VPN/ER gateway); **spoke VNets** peer to the hub. Spokes route 0.0.0.0/0 (and inter-spoke traffic) to the firewall via **UDRs** — "forced tunneling" sends all traffic through the firewall for inspection. This centralizes security and egress.

**B5. Explain private DNS resolution in Azure (Azure DNS, custom DNS, Private DNS zones).**
**Answer:** By default, VNets use **Azure-provided DNS** (168.63.129.16) which resolves VNet-internal names. **Azure Private DNS zones** provide name resolution within (and linked across) VNets for your domains. Custom DNS servers can be set per-VNet, and **Private DNS zones link to VNets** for centralized, private name resolution (with auto-registration for VMs).

**B6. How does Azure Private Link differ from service endpoints, and when do you choose each?**
**Answer:** **Service endpoints** = subnet-level, public endpoint of the PaaS service is bypassed via a private route (simpler, but the service still has a public endpoint and access is from the whole subnet). **Private Link** = a **private IP in your VNet** mapped to a specific service instance (more granular, works from on-prem via ER/VPN, and the service's public endpoint can be disabled). Choose Private Link for strict security and on-prem access; service endpoints for simplicity.

**B7. How do you monitor and troubleshoot VNet connectivity (NSG flow logs, Network Watcher)?**
**Answer:** **Network Watcher** provides tools: **NSG flow logs**, **connection troubleshoot**, **next hop**, **IP flow verify**, **packet capture**, and **topology**. Use "next hop" to see how a packet routes, "IP flow verify" to test NSG allow/deny, and flow logs for traffic analytics.

**B8. What are the key VNet limits you must design around?**
**Answer:** e.g., address spaces (default max 50 per VNet, adjustable), subnets (3,000 per VNet), private IPs per NIC, peering limits per VNet, and the fact that **the first 4 IPs of every subnet are reserved** (network, gateway, DNS ×2, broadcast-ish) — so usable IPs = size − 5 for Azure-internal reservations.

**B9. How does Azure handle east-west traffic inspection (firewall between subnets) without hairpinning issues?**
**Answer:** Use **UDRs** to send inter-subnet traffic to the **Azure Firewall/NVA** (next-hop = firewall private IP) and enable the NVA's IP forwarding. Beware **asymmetric routing** (return path bypassing the firewall) — design symmetric routes (route both directions through the firewall) and use NSGs to enforce.

**B10. Compare Azure VNet networking with AWS VPC networking (key mental model differences).**
**Answer:** Azure has no "Internet Gateway" or explicit NAT needed for inbound (public IPs attach directly); subnets are not tied to AZs the way AWS subnets are (Azure subnets span AZs); NSGs attach to subnets **and** NICs; and peering supports transitive-ish designs via hub-spoke + UDRs (but is non-transitive by default, like AWS). Knowing both models helps cross-cloud designs.

**B11. How do you plan IP addressing at enterprise scale (supernets, subnet sizing, IPAM)?**
**Answer:** Reserve a **supernet** (e.g., 10.0.0.0/8) per environment/region, carve /16s for VNets, and /24s (or right-sized) for subnets — leaving room for growth. Use a **hub** with small subnets (gateways/firewalls) and spokes with workload subnets. Enforce via policy (deny overlapping/oversized), and track allocations in an IPAM.

**B12. What is Azure Virtual WAN and how does it scale hub-spoke networking?**
**Answer:** Virtual WAN is a managed, global hub-and-spoke service: branch connectivity (VPN/SD-WAN/ER) and VNet connections converge on a Microsoft-managed hub with routing, firewalling, and inter-region transit — replacing manual hub-spoke + gateways at large scale.

---

## Case C — Scenario

**C1. Scenario:** A three-tier app (web/app/db) must be segmented with web public and db strictly private.
**Question:** Design the VNet + subnets + NSGs.
**Expected answer:** One VNet (10.0.0.0/16) with three subnets: web (public, NSG allows 80/443 in), app (NSG allows only from web subnet), db (NSG allows only 3306/1433 from app subnet). Route all outbound via NAT or a firewall; use service endpoints/Private Link for the DB. Deny all by default in NSGs except required flows.

**C2. Scenario:** Two VNets (10.1.0.0/16 and 10.2.0.0/16) in different regions need to talk with low latency and private IPs.
**Question:** How, and what are the cost implications?
**Answer:** **Global VNet peering** — private connectivity over the backbone, no gateway. Costs: **cross-region data transfer is billed** on the peered traffic (ingress/egress), so plan for that; also ensure non-overlapping address spaces and update NSGs to allow the peer CIDRs.

**C3. Scenario:** A VM can't reach the internet; other VMs in the same subnet can.
**Question:** Diagnose.
**Answer:** Check the **VM's NIC**: missing **public IP** or a restrictive **NSG on the NIC**, or a **UDR** on its NIC/subnet, or the VM's OS firewall. Use **Network Watcher → Next hop** and **IP flow verify** to see the effective path and NSG decision. Confirm a NAT/SNAT exists for outbound if no public IP.

**C4. Scenario:** You must force all outbound internet traffic from spoke VNets through a central Azure Firewall.
**Question:** Implement forced tunneling.
**Answer:** Peer spokes to the hub. In each spoke, create a **route table** with `0.0.0.0/0 → next hop = Azure Firewall's private IP` (or an NVA), and associate it with the spoke subnets. Ensure the firewall has a public IP + outbound rules, and enable **IP forwarding** if using an NVA. This is the standard hub-spoke forced-tunneling design.

**C5. Scenario:** Applications in a VNet need to reach a Storage Account and a SQL Database privately, including from on-premises.
**Question:** Which private connectivity options, and which for on-prem?
**Answer:** Use **Private Link/private endpoints** for both Storage and SQL — they give private IPs in the VNet and are reachable **from on-prem over ExpressRoute/VPN**. (Service endpoints are subnet-only and don't extend to on-prem.) Disable public access on the services after migration.

**C6. Scenario:** After peering VNet-A and VNet-B, VMs can't ping each other even though peering status is "Connected."
**Question:** Diagnose.
**Answer:** Check: (1) **NSGs** on both sides allowing ICMP (and the required ports) from the peer CIDR, (2) **route tables** don't override the peering route, (3) **OS firewalls** (Windows/Linux) allow ping, and (4) address spaces don't overlap. Use **Network Watcher IP flow verify / connection troubleshoot** to pinpoint the blocking NSG.
