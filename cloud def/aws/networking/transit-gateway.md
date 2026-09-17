# AWS Transit Gateway (TGW) — Interview Questions

> **Cloud:** AWS · **Category:** Networking · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~9 min

---

## JSON File Format

Transit Gateway (TGW) attachments and route tables are modelled as JSON in CloudFormation (`AWS::EC2::TransitGateway`, `AWS::EC2::TransitGatewayAttachment`, `AWS::EC2::TransitGatewayRouteTable`).

```json
{
  "Type": "AWS::EC2::TransitGateway",
  "Properties": {
    "Description": "Shared network hub",
    "AmazonSideAsn": 64512,
    "AutoAcceptSharedAttachments": "disable",
    "DefaultRouteTableAssociation": "enable",
    "DefaultRouteTablePropagation": "enable"
  }
}
```

**Key fields:** `AmazonSideAsn` (BGP ASN used for VPN/DX) · `AutoAcceptSharedAttachments` (shared-via-RAM behaviour) · `DefaultRouteTableAssociation` / `DefaultRouteTablePropagation` (routing policy defaults).


## Case A — Basic

**A1. What is AWS Transit Gateway?**
**Answer:** A regional, highly available network hub ("hub-and-spoke") that connects multiple VPCs, VPNs, and Direct Connect connections through a single gateway. It is transitive — anything attached can route to anything else via route tables.

**A2. What are "attachments" in Transit Gateway?**
**Answer:** An attachment is a link between the TGW and a resource: a VPC, a VPN connection, a Direct Connect Gateway, a Connect peer, or a peering attachment to another TGW. Each attachment gets an ENI in each AZ of the VPC.

**A3. Is a Transit Gateway regional or global?**
**Answer:** Each Transit Gateway is regional. To connect across regions you create multiple TGWs and connect them with **inter-region Transit Gateway peering attachments**.

**A4. What problem does Transit Gateway solve compared to VPC peering?**
**Answer:** Peering is non-transitive and becomes a messy N(N−1)/2 mesh. TGW provides transitive routing, centralized management, a single place to apply routing policy, and scales to thousands of VPCs and on-premises networks.

**A5. What is a TGW route table?**
**Answer:** A route table attached to the TGW that controls where traffic from an attachment can go. You associate attachments to route tables and propagate routes from attachments, giving fine-grained segmentation (e.g., dev VPCs cannot reach prod VPCs).

**A6. What does "propagation" mean in TGW?**
**Answer:** Propagation automatically advertises an attachment's CIDRs into a TGW route table. E.g., if a VPC attachment propagates to the default route table, other attachments associated with that table learn the VPC's routes.

**A7. How does TGW connect to on-premises data centers?**
**Answer:** Via **Site-to-Site VPN** attachments (attaching a Customer Gateway + VPN connection) or **Direct Connect Gateway** attachments. TGW supports ECMP (equal-cost multipath) across multiple VPN tunnels.

**A8. Does TGW support multicast?**
**Answer:** Yes, TGW supports IP multicast within a multicast domain (useful for financial market-data feeds), which VPC peering does not support.

**A9. What is the difference between TGW association and propagation?**
**Answer:** **Association** decides which route table an attachment *uses to send* traffic. **Propagation** decides which attachments *advertise their routes* into a route table. They are independent and together define routing policy.

**A10. What is a "Transit Gateway Connect" attachment?**
**Answer:** It connects third-party virtual appliances (SD-WAN/firewalls) to the TGW using GRE tunnels and BGP, allowing appliances to inject routes into TGW route tables.

**A11. What is the default route-table behavior when you create a TGW?**
**Answer:** A default route table is created. Attachments that don't have an explicit association use the default route table, and attachments propagate into it unless disabled — which is why you should design route tables deliberately.

**A12. Can one VPC attach to multiple Transit Gateways?**
**Answer:** Yes, a VPC can attach to multiple TGWs (up to the service limits), though each attachment is to one TGW. This supports advanced topologies (e.g., separate prod and dev networks).

**A13. What is "flow logs" support in TGW?**
**Answer:** Transit Gateway supports **VPC Flow Logs on TGW attachments**, giving visibility into accepted/rejected traffic at the TGW level — useful for security and troubleshooting.

**A14. What are the main components of a TGW?**
**Answer:** The gateway itself, attachments (VPC/VPN/DX/peering/Connect), route tables, associations, propagations, route table routes (static or propagated), and optional features like multicast domains, flow logs, and sharing via AWS RAM.

**A15. How do you share a TGW across accounts?**
**Answer:** Using **AWS Resource Access Manager (RAM)**. The owner shares the TGW with other accounts/OU; recipients accept and can then create attachments from their VPCs to the shared TGW.

---

## Case B — Advanced (Senior)

**B1. Explain how Transit Gateway achieves isolation between environments sharing one TGW.**
**Answer:** Using multiple route tables. Create a "prod" route table and a "dev" route table; associate prod VPCs with the prod table and dev VPCs with the dev table, and configure propagation so dev attachments never learn prod routes (and vice versa). A shared-services table can bridge only intended paths. This replaces many point-to-point ACLs with a single routing policy layer.

**B2. How does inter-region TGW peering differ from VPC peering and when would you use it?**
**Answer:** Inter-region TGW peering connects two regional TGWs so *all* attachments in both regions can talk transitively — scaling cross-region connectivity far better than per-VPC inter-region peering. It uses AWS backbone, is encrypted, and incurs inter-region data transfer charges. Use it for multi-region hub architectures.

**B3. How does ECMP work in TGW, and why is it important for VPN throughput?**
**Answer:** TGW can route a VPN flow over multiple equal-cost tunnels simultaneously (ECMP), aggregating bandwidth up to 50 Gbps per VPN attachment by distributing flows across tunnels. It requires BGP and equal AS-path/cost. This directly addresses the historical 1.25 Gbps single-tunnel VPN limit.

**B4. Discuss route priority/conflict resolution in a TGW route table.**
**Answer:** For a destination, the most specific route wins. If multiple routes have the same prefix, static routes take precedence over propagated routes. Among propagated routes, routes from a VPN/DX attachment with BGP can be influenced by AS path length. Understanding this ordering is key to debugging asymmetric routing.

**B5. What is asymmetric routing in TGW and how do you avoid it?**
**Answer:** Asymmetric routing occurs when traffic to a destination uses one path and return traffic uses another (e.g., via different TGWs or appliances), which stateful firewalls/NATs will drop. Avoid it by keeping route tables deterministic and by making sure return paths match forward paths — especially when using inline appliances.

**B6. How do you integrate a third-party firewall (e.g., Palo Alto) into TGW for east-west inspection?**
**Answer:** Use an **appliance (TGW Connect)** attachment or a "security VPC" pattern: the firewall VPC attaches to TGW, and the TGW route table sends inter-VPC traffic to the firewall ENIs (using a 0.0.0.0/0 or specific routes), which inspect and return traffic. This enables centralized inspection without changing spoke VPCs.

**B7. What are the limits you must design around with TGW?**
**Answer:** Key limits (check current AWS docs): attachments per TGW, route tables and routes per table, bandwidth per VPC attachment (~50 Gbps), bandwidth per VPN attachment, and inter-region peering bandwidth. Design accounts/regions and bandwidth aggregation accordingly; request limit increases where needed.

**B8. How does TGW interact with Direct Connect, and what are "Direct Connect Gateway" and "transit VIF"?**
**Answer:** A Direct Connect Gateway (global) links a DX connection to TGWs in multiple regions via a **transit virtual interface (VIF)**. BGP sessions run over the transit VIF, advertising on-prem routes into TGW and VPC routes to on-prem. This is the standard hybrid-cloud architecture.

**B9. What is the "blackhole" route in TGW and why use it?**
**Answer:** You can create a route pointing to `blackhole` to explicitly drop traffic for a destination (e.g., quarantine a compromised CIDR, or deny a leaked route). It is a deliberate null-route mechanism used for security and route hygiene.

**B10. Compare Transit Gateway vs VPC Peering vs PrivateLink for connecting many accounts.**
**Answer:** TGW = transitive, hub-and-spoke, policy-rich, for network-to-network connectivity at scale. Peering = point-to-point, simple, cheap (no TGW hourly/attachment fees) for few VPCs. PrivateLink = one-directional, service-to-consumer connectivity that hides the provider network (no CIDR overlap concerns). Choose by topology, scale, and whether you're sharing networks or consuming services.

**B11. How do you monitor and audit TGW?**
**Answer:** TGW flow logs (attach-level traffic visibility), CloudWatch metrics (BytesIn/BytesOut, PacketsIn/PacketsOut, PacketsDropped per attachment), CloudTrail for API/configuration changes, and AWS Config for compliance tracking of attachments and route tables.

**B12. How does AWS RAM sharing interact with TGW route table design?**
**Answer:** When a TGW is shared via RAM, the owner controls route tables. Best practice: share a TGW and create per-spoke route tables so each spoke only sees intended routes; recipients can associate/propagate their attachments only as permitted, keeping network segmentation centralized under the network team.

---

## Case C — Scenario

**C1. Scenario:** 200 VPCs across 3 regions and an on-premises DC must all be inter-connected with centralized control.
**Question:** Design the network.
**Expected answer:** One TGW per region; attach all regional VPCs; attach the on-prem DX/VPN to the primary TGW (or each region for redundancy). Peer the three TGWs with inter-region peering. Use shared route tables for segmentation, TGW flow logs, and AWS RAM to let account owners attach their VPCs under network-team governance.

**C2. Scenario:** After migrating from a peering mesh to TGW, the dev environment can suddenly reach production databases.
**Question:** Diagnose and fix.
**Expected answer:** Likely all attachments are associated with (and propagating into) the single **default route table**, making everything visible to everything. Fix: create separate prod/dev/shared route tables, associate each VPC with the right table, and disable cross-propagation. Verify with a route-lookup and flow logs that prod CIDRs are unreachable from dev.

**C3. Scenario:** A financial firm needs market-data multicast to 500 instances across 20 VPCs in one region.
**Question:** What architecture do you propose?
**Expected answer:** Use a **TGW multicast domain**: attach the 20 VPCs, register the multicast group, and configure IGMP-enabled instances. Multicast requires TGW (VPC peering doesn't support it). Design sender/receiver subnets and enable IGMP on the instances; monitor via multicast domain membership.

**C4. Scenario:** A single VPN to TGW is the only path to on-prem, and users report intermittent slowness to a specific on-prem application.
**Question:** How do you improve bandwidth and resilience?
**Expected answer:** Add a **second VPN connection/tunnel** to the same Customer Gateway so TGW uses ECMP to aggregate bandwidth, or attach a second Customer Gateway at another site. Confirm BGP is advertising prefixes over both tunnels so flows are spread. Long-term, add Direct Connect with a transit VIF for guaranteed capacity.

**C5. Scenario:** The security team mandates that all east-west traffic between business units pass through a central firewall.
**Question:** Design centralized inspection with TGW.
**Expected answer:** Create a security VPC with the firewall (or use TGW Connect appliances). In the TGW route table, route inter-VPC traffic (0.0.0.0/0 or specific supernets) to the firewall ENI attachment with appliance-mode enabled, and have the firewall return traffic. Ensure symmetric routing so the firewall sees both directions, and enable flow logs on attachments.

**C6. Scenario:** Your TGW route table shows two routes for 10.10.0.0/16 — one static, one propagated from a VPN — and traffic isn't going where you expect.
**Question:** Explain which route wins and why, and how you'd verify the actual path.
**Expected answer:** For the same prefix, the **static route wins** over the propagated route. Verify using the route-table route lookup / `aws ec2 search-transit-gateway-routes` to see which route would actually be selected, then adjust (remove the static or change BGP metrics) to steer traffic as intended.
