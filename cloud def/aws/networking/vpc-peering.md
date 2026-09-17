# VPC Peering — Interview Questions

> **Cloud:** AWS · **Category:** Networking · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~10 min

---

## JSON File Format

VPC Peering is defined in **Infrastructure-as-Code** and CLI input as JSON. The most common form is the CloudFormation `AWS::EC2::VPCPeeringConnection` resource (JSON or YAML). Routes and route-table entries are separate JSON resources.

```json
{
  "Type": "AWS::EC2::VPCPeeringConnection",
  "Properties": {
    "VpcId": "vpc-0abc123",
    "PeerVpcId": "vpc-0def456",
    "PeerRegion": "us-west-2",
    "PeerOwnerId": "111122223333"
  }
}
```

**Key fields:** `VpcId` (requester VPC) · `PeerVpcId` (accepter VPC) · `PeerRegion` (cross-region) · `PeerOwnerId` (cross-account). The CLI also accepts `--cli-input-json` for `create-vpc-peering-connection` / `accept-vpc-peering-connection`.


## Case A — Basic

**A1. What is VPC Peering?**
**Answer:** It is a private, direct network connection between two VPCs (same or different accounts/regions) that lets them communicate using private IPv4/IPv6 addresses as if they were in the same network. It does not use a gateway, VPN, or the public internet.

**A2. Is VPC Peering transitive?**
**Answer:** No. If VPC-A is peered with VPC-B and VPC-B is peered with VPC-C, VPC-A cannot reach VPC-C through VPC-B. Each pair of VPCs needs its own peering connection.

**A3. Can you peer VPCs in different AWS Regions?**
**Answer:** Yes, inter-region peering is supported (also called cross-region peering). Traffic stays on AWS's global backbone, is encrypted, and never traverses the public internet. It has associated data-transfer charges.

**A4. Can you peer VPCs in different AWS accounts?**
**Answer:** Yes. The owner of one VPC sends a peering request, and the other account's owner must accept it. Cross-account peering usually requires an IAM role or explicit `AcceptVpcPeeringConnection` permission in the accepter account.

**A5. What is the CIDR requirement for peering two VPCs?**
**Answer:** The two VPCs must have **non-overlapping CIDR ranges**. AWS will not allow a peering connection between VPCs whose CIDRs overlap, and requests to peer overlapping VPCs fail.

**A6. After creating a peering connection, what else is required for traffic to flow?**
**Answer:** You must add routes in **both** VPCs' route tables pointing to the peer VPC's CIDR via the peering connection (pcx-xxxx). Security groups and NACLs must also allow the traffic.

**A7. Does VPC peering use a physical link or a gateway?**
**Answer:** Neither. It is a logical connection built on AWS's existing network backbone — there is no dedicated hardware, no single point of failure, and no bandwidth bottleneck imposed by a device.

**A8. Is peering traffic encrypted?**
**Answer:** Traffic over inter-region peering is encrypted in transit (AWS backbone encryption). Traffic within the same region stays within the AWS network and never leaves it. Application-layer encryption is still recommended for sensitive data.

**A9. Can two VPCs with overlapping CIDRs be peered?**
**Answer:** No. Overlapping CIDRs cannot be peered at all. If you need to connect such VPCs you must re-architect (re-IP, use private NAT, or a Transit Gateway with isolated routing).

**A10. What is the MTU of a VPC peering connection?**
**Answer:** The default and maximum MTU is **9001 bytes** (jumbo frames), same as intra-VPC traffic. You should avoid fragmentation issues by configuring consistent MTU on instances.

**A11. How is VPC peering different from a VPC Endpoint?**
**Answer:** Peering connects **two VPCs** to each other. A VPC Endpoint connects your VPC **privately to an AWS service** (e.g., S3, DynamoDB) without internet, NAT, or VPN.

**A12. How many peering connections can a single VPC have?**
**Answer:** There is a default soft limit of **125 peering connections per VPC** (adjustable on request). This is why a hub-and-spoke or mesh of many VPCs is often better served by Transit Gateway.

**A13. Does VPC peering support IPv6?**
**Answer:** Yes, peering supports both IPv4 and IPv6. You can route IPv6 traffic across a peering connection by adding IPv6 routes to the route table.

**A14. What happens to traffic if you delete the peering connection?**
**Answer:** Traffic immediately stops flowing across the connection. Routes pointing at the pcx-id in each VPC's route table become blackholed (destination unreachable) and should be cleaned up.

**A15. How is a peering connection identified?**
**Answer:** By a unique identifier of the form **pcx-xxxxxxxx** (e.g., pcx-0a1b2c3d4e5f67890). This ID is used in route tables, CLI commands, and CloudFormation references.

---

## Case B — Advanced (Senior)

**B1. Why is VPC peering non-transitive, and how do you scale connectivity across many VPCs?**
**Answer:** Peering is designed as a point-to-point link; AWS deliberately does not forward packets between peering connections to avoid routing loops and to keep the model simple and secure. To scale, use **AWS Transit Gateway** (hub-and-spoke, transitive by design) or **PrivateLink** for service access, instead of a full mesh of peering connections.

**B2. What are the main security considerations for a peered VPC?**
**Answer:** Security Groups and NACLs still apply independently in each VPC. You must explicitly allow the peer CIDR in SGs and NACLs, avoid `0.0.0.0/0` in sensitive environments, use SG-to-SG references (same/peered VPC) for least privilege, and monitor with VPC Flow Logs.

**B3. Can you reference a Security Group from the peered VPC in your SG rules?**
**Answer:** Yes, for **same-region** peering (and cross-account same-region) you can reference a security group ID from the peered VPC in your security group rules. This is not possible for cross-region peering — you must use CIDR-based rules there.

**B4. What are `enableDnsSupport` and `enableDnsHostnames`, and why do they matter for peering?**
**Answer:** `enableDnsSupport` lets instances resolve private DNS hostnames of the peered VPC; `enableDnsHostnames` gives instances public DNS names. For cross-VPC resolution of private DNS names over peering, both VPCs must have these attributes enabled.

**B5. What are the bandwidth/performance limits of peering, and when should you prefer Transit Gateway?**
**Answer:** Peering has no artificial bandwidth cap beyond AWS's backbone, but each connection is a management unit: N VPCs fully meshed = N(N−1)/2 connections, which becomes unmanageable and error-prone beyond ~10–20 VPCs. TGW centralizes routing, is transitive, and scales to thousands of VPCs.

**B6. Walk through the cross-account peering setup flow.**
**Answer:** (1) Requester (owner of VPC-A) creates a peering request specifying the accepter account ID and VPC ID. (2) Accepter (owner of VPC-B) accepts it — acceptance may require an IAM role with `ec2:AcceptVpcPeeringConnection`. (3) Both sides add routes to their route tables. (4) Update SGs/NACLs. (5) Verify with flow logs or connectivity tests.

**B7. How does route precedence behave when a route table has multiple overlapping routes?**
**Answer:** The most specific (longest prefix) route wins. For equal prefixes, the priority order is: local route, then static routes (peering/VPN/IGW), then propagated routes. A VPC peering route is static, so it beats propagated routes of the same prefix.

**B8. Why is "edge-to-edge routing" not supported through a VPC used as a hub (e.g., peering + VPN/Direct Connect)?**
**Answer:** AWS does not allow a VPC to act as a transit router between an internet gateway/VPN/Direct Connect and a peering connection. A peered VPC cannot use your VPN to reach on-premises. This is a classic exam/interview trap — the solution is Transit Gateway, which supports this natively.

**B9. Can a VPC be peered with itself, and can there be duplicate peering connections between the same two VPCs?**
**Answer:** No, you cannot peer a VPC with itself, and you cannot create multiple peering connections between the same two VPCs. One logical connection serves all AZs/subnets of both VPCs.

**B10. Compare same-region vs inter-region peering (cost, latency, DNS, features).**
**Answer:** Same-region is free for intra-region data transfer, supports SG-to-SG references, and shares the regional network. Inter-region incurs data-transfer charges per GB, adds latency, does not support SG references, but works across continents and is encrypted on the backbone.

**B11. How do you monitor a peering connection's health and traffic?**
**Answer:** VPC peering itself has no dedicated CloudWatch metrics. You monitor it indirectly via **VPC Flow Logs** (accepted/rejected traffic), instance-level network metrics, and by tracking route table health. Alarms are typically built on flow-log analysis or synthetic connectivity tests.

**B12. When would you choose PrivateLink (VPC Endpoint) instead of peering?**
**Answer:** When one VPC **consumes a service** (e.g., another team's app, a SaaS endpoint) rather than needing full bidirectional network connectivity. PrivateLink exposes a service via an interface endpoint, keeps traffic private, is one-directional from consumer to provider, and avoids CIDR overlap issues entirely.

---

## Case C — Scenario

**C1. Scenario:** Your company has 40 accounts, each with a VPC, and wants full or partial connectivity between them.
**Question:** Would you use a peering mesh or Transit Gateway? Justify.
**Expected answer:** Transit Gateway. A full mesh needs 780 peering connections — unmanageable, hard to audit, and each is point-to-point. TGW gives a single hub with transitive routing, centralized route tables, and per-attachment isolation via route table association/propagation. Peering is only justified for a handful of special-case high-throughput pairs.

**C2. Scenario:** Prod VPC (10.0.0.0/16) and Dev VPC (10.1.0.0/16) are peered. A new team accidentally created a third VPC (10.0.0.0/24) and tries to peer it with Prod.
**Question:** What happens, and how do you resolve it?
**Expected answer:** The peering request fails because CIDRs overlap. Options: (1) re-IP the new VPC, (2) if the /24 is a subset of prod's range, consider whether re-architecting with private NAT or TGW isolated routing tables is needed, (3) enforce CIDR governance via AWS Organizations SCPs/Service Catalog so this cannot recur.

**C3. Scenario:** Two business units in different accounts need their VPCs to talk, but security demands least privilege — only the database tier (port 3306) of VPC-B should be reachable from VPC-A's app tier.
**Question:** Design the peering + security controls.
**Expected answer:** Peer the VPCs. In VPC-B, create a security group on DB instances allowing port 3306 from VPC-A's app-tier security group (SG reference if same region) or from the app tier's CIDR. Add NACL rules on the DB subnet allowing 3306 from app subnet CIDR and the ephemeral-port return range. Add peering routes in both route tables. Deny everything else.

**C4. Scenario:** VPC-A has a VPN connection to on-premises. It is also peered with VPC-B. On-premises servers need to reach VPC-B.
**Question:** Will it work through VPC-A, and what is the correct design?
**Expected answer:** No — edge-to-edge routing is not supported; a peered VPC cannot use VPC-A's VPN to reach on-premises. Correct design: attach the VPN to a **Transit Gateway** and attach both VPC-A and VPC-B to it, so on-premises can route to both VPCs transitively. Alternative: build a second VPN/VGW in VPC-B.

**C5. Scenario:** You peer VPCs in us-east-1 and ap-south-1. An application reports higher-than-expected latency (~150 ms) and occasional timeouts.
**Question:** How do you investigate?
**Expected answer:** Inter-region latency is expected (geographic distance), so first baseline expected RTT. Use VPC Flow Logs to verify the path and check for retransmits, check MTU/fragmentation, inspect instance CPU/network credits, and confirm route tables use the pcx (not NAT/IGW, which would indicate an accidental internet path). Consider a compute migration closer to the data if latency is unacceptable.

**C6. Scenario:** After peering prod and staging, the security team finds that staging can reach **all** prod subnets.
**Question:** Restrict the peering so only one staging subnet can reach one prod subnet.
**Expected answer:** In prod's route table, scope the peering route to only the allowed staging subnet CIDR, and in staging's route table route only the allowed prod subnet CIDR. Then enforce with security groups (allow only from the staging subnet CIDR) and NACLs on both sides. Optionally split the subnets into separate route tables so other subnets have no peering route at all.
