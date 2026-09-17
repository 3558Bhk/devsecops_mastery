# Security Groups (SG) — Interview Questions

> **Cloud:** AWS · **Category:** Networking · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~10 min

---

## JSON File Format

Security Group rules are JSON when created via CLI/CloudFormation — the classic form is an **ingress/egress rule object** inside `AWS::EC2::SecurityGroup` or the `authorize-security-group-ingress` API.

```json
{
  "IpProtocol": "tcp",
  "FromPort": 443,
  "ToPort": 443,
  "IpRanges": [{ "CidrIp": "0.0.0.0/0", "Description": "HTTPS from anywhere" }],
  "UserIdGroupPairs": [{ "GroupId": "sg-0abc123", "Description": "from app tier SG" }]
}
```

**Key fields:** `IpProtocol` (tcp/udp/icmp/-1) · `FromPort`/`ToPort` · `IpRanges` (CIDRs) · `Ipv6Ranges` · `UserIdGroupPairs` (SG-to-SG reference) · `PrefixListIds` (managed prefix lists).


## Case A — Basic

**A1. What is a Security Group?**
**Answer:** A virtual stateful firewall that controls inbound and outbound traffic to AWS resources (EC2, RDS, ELB, etc.) at the instance/ENI level. It operates at Layer 3/4 (IP, protocol, port).

**A2. Are Security Groups stateful or stateless?**
**Answer:** **Stateful.** If you allow inbound traffic, the corresponding response traffic is automatically allowed outbound regardless of outbound rules (and vice versa). You don't need to open ephemeral return ports.

**A3. What is the default behavior of a newly created Security Group?**
**Answer:** It allows **all outbound** traffic and **denies all inbound** traffic by default. You must explicitly add inbound rules to allow access (e.g., SSH/HTTP).

**A4. Are Security Group rules allow-only or can they deny?**
**Answer:** Security Groups support **allow rules only** — there is no "deny" rule. Anything not explicitly allowed is implicitly denied.

**A5. What components define a Security Group rule?**
**Answer:** Protocol (TCP/UDP/ICMP/custom), port or port range, source (inbound: CIDR, IP, another SG, or prefix list) / destination (outbound), and an optional description.

**A6. Can you attach the same Security Group to multiple instances?**
**Answer:** Yes, one SG can be attached to many resources, and one resource can have multiple SGs (up to the ENI limit). Rules from all attached SGs are combined (union) and evaluated.

**A7. What does "Source: another security group" mean in an inbound rule?**
**Answer:** The rule allows traffic from resources that have that SG attached, referenced by the SG's ID — not its IP. This lets you scale resources without maintaining IP lists.

**A8. What is the difference between Security Groups and Network ACLs?**
**Answer:** SGs are stateful, instance-level, allow-only. NACLs are stateless, subnet-level, and support both allow and deny rules with rule numbers evaluated in order. Both are needed for defense in depth.

**A9. Can a Security Group span VPCs or regions?**
**Answer:** A Security Group belongs to a single VPC (and region). You cannot attach an SG from VPC-A to an instance in VPC-B; you can reference a peer VPC's SG in rules only within the same region via peering.

**A10. Does changing a Security Group rule require a reboot or instance stop?**
**Answer:** No. SG changes take effect immediately and are applied at the hypervisor/ENI level.

**A11. What is the difference between the default SG and a custom SG?**
**Answer:** The default SG allows all inbound from resources using the same default SG and all outbound. Custom SGs allow all outbound but **no** inbound by default.

**A12. How many rules / SGs can you have?**
**Answer:** Per SG: up to 60 inbound + 60 outbound rules (adjustable). Per network interface: up to 5 SGs (adjustable to 16). These are soft limits.

**A13. What happens if there is no rule allowing a connection — what error do you typically see?**
**Answer:** The connection is silently dropped (packets dropped, no RST), which often manifests as "connection timed out" rather than "connection refused" — a classic clue that an SG/NACL is blocking vs. a service not listening.

**A14. Are Security Groups evaluated in any order?**
**Answer:** No. Rules within a Security Group are all evaluated together (there is no rule-number ordering); the effective permission is the union of all rules across attached SGs.

**A15. Can you use a Security Group on a non-EC2 AWS service?**
**Answer:** Yes — RDS, Redshift, ElastiCache, EFS mount targets, Lambda (in a VPC), ALB/NLB, ECS tasks (via ENI), and many other ENI-based services all use SGs.

---

## Case B — Advanced (Senior)

**B1. Explain exactly why a stateful firewall doesn't need return-path rules, and how NACL differs.**
**Answer:** A stateful firewall tracks each connection (5-tuple: src/dst IP, src/dst port, protocol) in a connection table, so it automatically permits packets belonging to an established flow. NACLs are stateless, so they require explicit rules for both directions, including ephemeral ports (1024–65535) for return traffic.

**B2. How do you design least-privilege SG rules across a three-tier architecture (web/app/db)?**
**Answer:** Web SG: allow 80/443 from 0.0.0.0/0 (or CloudFront prefix list). App SG: allow only from the **web SG** on the app port. DB SG: allow only from the **app SG** on 3306/5432. Management SG: allow SSH/RDP only from the corporate VPN/bastion CIDR. Never use 0.0.0.0/0 for DB or SSH.

**B3. When would SG-to-SG references fail, and what is the workaround?**
**Answer:** SG references only work within the same VPC or across **same-region** VPC peering. They fail across regions, on-premises, or VPCs not peered. Workaround: use CIDR rules, or use **AWS-managed prefix lists** to keep IP ranges maintainable.

**B4. What are Managed Prefix Lists and how do they improve SG management?**
**Answer:** A prefix list is a named collection of CIDRs. You can reference a single prefix list in SG rules (and route tables) instead of many individual CIDRs. Updating the list updates all consumers — e.g., keep an "office-egress-ips" list that many SGs reference.

**B5. How do Security Groups interact with VPC Flow Logs for troubleshooting?**
**Answer:** Flow logs record each flow and its action (ACCEPT/REJECT) but do **not** tell you which SG/NACL rule caused a REJECT. You use flow logs to confirm a drop, then check SG and NACL rules manually. (Flow logs also only show REJECT for NACL/SG-level drops.)

**B6. Explain the "implicit deny" and how duplicate/similar rules from multiple SGs combine.**
**Answer:** There is no explicit deny; the default action is deny. When an ENI has multiple SGs, the effective rules are the **union** — if any SG allows a flow, it's allowed (there's no "most restrictive wins"). This is why removing broad rules across many SGs matters for security reviews.

**B7. How do you handle a large list of IPs that exceeds per-SG rule limits?**
**Answer:** Use prefix lists (aggregate CIDRs), or aggregate IPs into supernets, or spread across multiple SGs on the same ENI (each SG has its own rule quota), or use an ALB/NLB in front to consolidate entry points, or AWS Firewall Manager to manage rules centrally.

**B8. Can a Security Group block traffic from a specific IP while allowing others in the same CIDR?**
**Answer:** Not directly — SGs are allow-only. To deny a specific IP you'd rely on NACL deny rules (stateless, with careful return-path handling) or AWS Network Firewall. Common approach: allow the broader CIDR in SG but add a NACL deny for the specific IP.

**B9. How do SGs behave with a NAT Gateway / internet-bound traffic?**
**Answer:** Outbound traffic from instances to the internet goes through the NAT Gateway; the instance's SG controls what outbound traffic the instance may initiate, and inbound return traffic is allowed automatically because the SG is stateful. The NAT Gateway itself has no SG — it allows all outbound and only established return traffic.

**B10. What is the relationship between SGs and the ephemeral port range, and when do you still care about it?**
**Answer:** With stateful SGs you generally don't manage ephemeral ports. But when a **stateless** component is in the path (NACLs, or a stateful SG referencing an external firewall), you must allow the ephemeral range 1024–65535 (or the OS-specific range, e.g., 32768–61000 for many Linux) for return traffic.

**B11. How would you audit and clean up unused/over-permissive Security Groups at scale?**
**Answer:** Use AWS Config (e.g., the `restricted-ssh` and `vpc-sg-open-only-to-authorized-ports` managed rules), AWS Security Hub, Trusted Advisor, or custom Lambda/Steampipe queries. Track SG usage (attached vs. unused), find 0.0.0.0/0 on sensitive ports, and automate remediation or alerting.

**B12. How do Security Groups work with ECS Fargate / Lambda in a VPC?**
**Answer:** Fargate tasks get an ENI and can use security groups directly (via the task's network configuration). Lambda functions running inside a VPC are subject to the VPC's SG rules for outbound access; a common design is a dedicated "lambda" SG allowing only the required destinations, and note that VPC-connected Lambda has no public internet unless routed via NAT.

---

## Case C — Scenario

**C1. Scenario:** SSH to an EC2 instance fails with "connection timed out," but the instance status checks pass and the service is confirmed running on the instance.
**Question:** Walk through your troubleshooting steps.
**Expected answer:** (1) Check instance SG inbound for port 22 from your IP (correct public IP/CIDR). (2) Check the subnet NACL for allow 22 inbound and ephemeral outbound. (3) Check route table has an IGW route if connecting via public IP. (4) Verify the instance is in a public subnet with a public/Elastic IP. (5) Use Reachability Analyzer to pinpoint the blocking component.

**C2. Scenario:** Your auto-scaling web tier uses an SG rule that references the load balancer SG. During a scale-out, new instances intermittently can't receive traffic.
**Question:** Explain the most likely cause and fix.
**Expected answer:** If the SG rule references the ALB's security group ID, scaling is not the problem — SG references are ID-based and work for any number of instances. The likely culprit is a different constraint (NACL rule count/ordering, or a wrong SG reference after a rebuild). Verify the ALB SG ID in the rule matches the actual ALB SG, and check NACL ephemeral ports. If they used CIDR rules for a sub-range, new instance IPs may fall outside it.

**C3. Scenario:** A DBA wants to allow only the app tier (which auto-scales between 3 and 30 instances) to reach RDS on 3306, without editing rules each time.
**Question:** What is the cleanest design?
**Expected answer:** Put the app instances in an "app-tier" security group and add an RDS inbound rule with **source = app-tier SG ID**, port 3306. Because the reference is to the SG (not IPs), any current or future instance with that SG can connect, and scaling requires zero rule changes.

**C4. Scenario:** Security review flags several SGs with 0.0.0.0/0 on ports 22, 3389, and 3306.
**Question:** How do you remediate without breaking existing workloads?
**Expected answer:** Inventory which instances use those SGs and who legitimately connects. Replace 0.0.0.0/0 with the corporate egress IPs (or a managed prefix list), a bastion-host SG reference, or the app-tier SG. Apply in a maintenance window with connectivity tests; use AWS Config/Security Hub to continuously detect recurrence.

**C5. Scenario:** Two instances in the same subnet can't ping each other even though ICMP is allowed in both their security groups.
**Question:** What else could block it, and how do you confirm?
**Expected answer:** Check the **subnet NACL** — it may be denying ICMP or the return path (NACLs are stateless, so both directions must allow ICMP echo request and reply). Also verify no OS-level firewall (iptables/Windows Firewall) blocks it. Use Reachability Analyzer to isolate SG vs NACL vs OS.

**C6. Scenario:** You need a fleet of instances to reach a third-party SaaS endpoint whose IP range changes frequently, and there are 40 SGs to update.
**Question:** Design a maintainable solution.
**Expected answer:** Create an **AWS-managed or customer-managed prefix list** containing the SaaS CIDRs and reference that single prefix list in all 40 SGs. When the SaaS publishes new ranges, update the prefix list once and all SGs update automatically. Alternatively, route through a proxy/ALB so egress is centralized.
