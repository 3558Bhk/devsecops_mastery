# Network ACLs (NACL) — Interview Questions

> **Cloud:** AWS · **Category:** Networking · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~9 min

---

## JSON File Format

NACL entries are JSON in CloudFormation (`AWS::EC2::NetworkAcl` + `AWS::EC2::NetworkAclEntry`) or `create-network-acl-entry`. Because NACLs are stateless, you model **both** directions.

```json
{
  "Type": "AWS::EC2::NetworkAclEntry",
  "Properties": {
    "NetworkAclId": "acl-0abc123",
    "RuleNumber": 100,
    "Protocol": "6",
    "RuleAction": "allow",
    "Egress": false,
    "CidrBlock": "0.0.0.0/0",
    "PortRange": { "From": 443, "To": 443 }
  }
}
```

**Key fields:** `RuleNumber` (1–32766, evaluated in order) · `RuleAction` (allow/deny) · `Egress` (false = inbound, true = outbound) · `Protocol` (IANA number, e.g. 6 = TCP) · `PortRange`.


## Case A — Basic

**A1. What is a Network ACL?**
**Answer:** A stateless firewall at the **subnet** level that controls traffic entering and leaving a subnet. Every subnet must be associated with one NACL; a NACL can be associated with many subnets.

**A2. Are NACLs stateful or stateless?**
**Answer:** **Stateless.** Inbound and outbound rules are evaluated independently — return traffic must be explicitly allowed in both directions (including ephemeral ports).

**A3. Do NACLs support allow and deny rules?**
**Answer:** Yes. Unlike Security Groups (allow-only), NACLs support **both allow and deny** rules, evaluated in order by rule number.

**A4. How are NACL rules evaluated?**
**Answer:** By **ascending rule number**, starting from the lowest. The first rule that matches (allow or deny) is applied. If no numbered rule matches, the implicit **deny all (*)** rule applies.

**A5. What is the default NACL and its behavior?**
**Answer:** Every VPC has a default NACL that **allows all** inbound and outbound traffic (rule 100 allow all, and * deny that never triggers). Custom NACLs start by **denying all** until you add rules.

**A6. What are ephemeral ports, and why do NACLs need rules for them?**
**Answer:** Ephemeral ports (1024–65535; commonly 32768–61000 on Linux, 49152–65535 on Windows) are the client-side ports used for return traffic. Because NACLs are stateless, you must explicitly allow these outbound/inbound so response traffic can flow.

**A7. What fields define a NACL rule?**
**Answer:** Rule number, type (protocol), protocol, port range, source (inbound) / destination (outbound) CIDR, and allow/deny action.

**A8. What is the difference between NACL and Security Group?**
**Answer:** NACL = subnet-level, stateless, allow+deny, ordered rules. SG = resource-level, stateful, allow-only, unordered (union of rules). They complement each other for defense in depth.

**A9. Can two subnets share one NACL? Can one subnet use two NACLs?**
**Answer:** A single NACL can be associated with multiple subnets. A subnet can be associated with **only one** NACL at a time.

**A10. What happens if you associate a new NACL with a subnet?**
**Answer:** The subnet's previous NACL association is replaced immediately; the new NACL's rules now govern that subnet's traffic.

**A11. What is the implicit rule at the end of every NACL?**
**Answer:** An implicit **deny all** rule (deny 0.0.0.0/0) with rule number `*`, which cannot be deleted or edited.

**A12. How do NACL rules help with the return traffic of a web server (port 443)?**
**Answer:** Inbound: allow 443 from clients. Outbound: allow the **ephemeral port range** to the client CIDR so the server's responses can leave. Statelessness forces both rules.

**A13. Are NACLs evaluated before or after Security Groups?**
**Answer:** Both are evaluated: NACL (subnet boundary) first, then the Security Group (instance boundary) for inbound; the reverse order for outbound. A packet must pass **both** to be delivered.

**A14. What is the maximum number of rules per NACL?**
**Answer:** 20 rules per direction by default (adjustable up to 40). Rule numbers range from 1 to 32766.

**A15. Do NACLs apply to traffic within the same subnet (instance to instance)?**
**Answer:** Yes — NACLs apply to traffic **entering or leaving** the subnet, including instance-to-instance traffic in the same subnet. (Security Groups also apply.)

---

## Case B — Advanced (Senior)

**B1. Why are NACLs described as "stateless," and what practical consequences follow?**
**Answer:** Each direction's rules are evaluated independently with no connection tracking. Consequence: you must open both the request and the response paths — e.g., allow 443 inbound *and* ephemeral ports outbound. Forgetting the return path is the #1 NACL misconfiguration, causing one-way connectivity.

**B2. Explain the rule-numbering strategy for maintainable NACLs.**
**Answer:** Use gaps (e.g., 100, 200, 300) so you can insert rules between existing ones later without renumbering. Reserve low numbers for explicit DENY rules (since order matters) and higher numbers for broad ALLOW rules, ending with the implicit deny.

**B3. How do you explicitly block a specific IP using NACLs when Security Groups can't deny?**
**Answer:** Add a low-numbered DENY rule (e.g., rule 50) for the offending IP/CIDR before your broader ALLOW rules. Because NACLs evaluate in order and stop at first match, the specific deny wins. Remember to mirror a deny for return traffic as needed.

**B4. How do NACLs and Security Groups interact in a classic "why is my traffic dropped" scenario?**
**Answer:** Traffic must pass NACL (subnet) and SG (instance). A drop can be caused by either. Diagnose with VPC Flow Logs (REJECT records) and Reachability Analyzer. Common trap: SG allows it but NACL lacks the ephemeral outbound rule, so the server receives the request but the client never gets a response.

**B5. Compare the default NACL vs a custom NACL and when you'd deliberately use a custom one.**
**Answer:** Default NACL = allow all (permissive). Custom NACL = deny all by default. You use custom NACLs to enforce subnet-level security policy — e.g., a "quarantine" NACL that denies all traffic to isolate compromised subnets instantly, or blocking a bad actor's IP across a whole subnet.

**B6. How do NACLs behave with ALB/NLB traffic (clients and targets)?**
**Answer:** For internet-facing ALBs: client traffic enters via the ALB's subnets' NACLs, and ALB→target traffic passes the target subnets' NACLs. NACLs must allow the load balancer subnet CIDRs to the target port, and the target's ephemeral ports outbound to the ALB. Because ALBs scale, use the VPC's ALB subnet CIDRs (or the VPC CIDR) in NACL rules, not single IPs.

**B7. How do you design NACLs for a public (DMZ) vs private subnet?**
**Answer:** Public subnet NACL: allow 80/443 from 0.0.0.0/0, allow SSH/RDP only from admin CIDR, and allow ephemeral outbound to 0.0.0.0/0. Private subnet NACL: deny inbound from 0.0.0.0/0 except from the app subnet CIDR on the app port; allow outbound to the NAT gateway / required CIDRs only, plus ephemeral returns.

**B8. What is the relationship between NACLs and VPC Flow Logs?**
**Answer:** Flow logs can show REJECT entries caused by NACL (or SG) rules. Flow logs don't name the rule, but combined with the stateless nature of NACLs you can correlate: if one direction is ACCEPT and the opposite direction of the same flow is REJECT, a NACL (stateless) is the likely cause, whereas an SG (stateful) would allow the return automatically.

**B9. Can NACLs filter by protocol type beyond TCP/UDP (e.g., ICMP, custom protocols)?**
**Answer:** Yes. NACLs support protocol numbers (TCP=6, UDP=17, ICMP=1, or any custom IP protocol number). For ICMP you can further allow specific types/codes if needed (e.g., allow echo request/reply for ping).

**B10. How do NACLs apply to traffic from AWS services like S3 VPC Endpoints or DynamoDB Gateway Endpoints?**
**Answer:** Interface endpoints (ENIs in your subnets) are subject to NACLs like any other traffic. Gateway endpoints (S3/DynamoDB) are routed entries in the route table and are **not** subject to NACLs — they rely on endpoint policies and SG rules (for the resources).

**B11. What are the pitfalls of using NACLs for access control at scale (vs SGs)?**
**Answer:** NACLs are coarse (per-subnet), stateless (easy to break return paths), limited rule counts, and apply to everything in the subnet — a shared subnet means shared policy. For fine-grained, per-application control, prefer SGs; use NACLs for subnet-level policy, blocklists, and defense-in-depth.

**B12. How would you implement a "block entire CIDR" fast-fail (incident response) with NACLs?**
**Answer:** Keep a pre-built "DENY ALL" or partial-deny NACL ready (e.g., deny the attacker CIDR in rule 10, allow all else in rule 100). On incident, associate it with the affected subnet(s) — changes take effect immediately with no instance impact. Automate with AWS Systems Manager/Step Functions or AWS Network Firewall for richer controls.

---

## Case C — Scenario

**C1. Scenario:** Users report that a web app loads the page but some assets (from the same server) never finish loading; sometimes the page itself times out intermittently.
**Question:** How does NACL misconfiguration explain this, and what do you check?
**Expected answer:** The inbound rule allows 443, but the **outbound ephemeral-port** rule is missing or too narrow, so responses are dropped — classic stateless-NACL symptom. Check outbound rules for the ephemeral range to the client CIDR; also confirm the inbound allow covers all client CIDRs. Fix by adding the correct ephemeral range outbound.

**C2. Scenario:** A subnet's NACL has: 100 ALLOW 0.0.0.0/0 (inbound), 200 DENY 203.0.113.0/24 (inbound).
**Question:** Does the deny actually block that CIDR? Why or why not?
**Expected answer:** No. Rule 100 (ALLOW all) is evaluated first and matches everything, so rule 200 never runs. NACL rules are order-sensitive: the DENY must have a **lower rule number** than the ALLOW (e.g., 50 DENY 203.0.113.0/24, then 100 ALLOW all).

**C3. Scenario:** An app tier in subnet-A calls a database in subnet-B. The app times out connecting, and flow logs show REJECT on subnet-B inbound.
**Question:** Walk through both NACLs and what rules each needs.
**Expected answer:** Subnet-A NACL outbound must ALLOW the DB port to subnet-B CIDR, and inbound must ALLOW ephemeral ports from subnet-B (return). Subnet-B NACL inbound must ALLOW the DB port from subnet-A CIDR, and outbound must ALLOW ephemeral ports to subnet-A CIDR. Both directions on both NACLs are required because NACLs are stateless.

**C4. Scenario:** Security wants to isolate a compromised subnet immediately while you investigate.
**Question:** What's the fastest NACL-based response, and what's the risk?
**Expected answer:** Associate (or pre-stage) a NACL that **denies all** inbound and outbound to the compromised subnet — the change applies instantly and blocks all traffic. Risk: it also cuts legitimate traffic, so coordinate with the app owner, and be aware that traffic already permitted by stateful SGs will still be stopped at the NACL boundary.

**C5. Scenario:** After enabling a new NACL on the public subnet, the ALB's health checks start failing and targets are marked unhealthy.
**Question:** Which NACL rules are likely missing?
**Expected answer:** The NACL must allow (1) inbound health-check traffic from the ALB subnet CIDR (or VPC CIDR) to the target's health-check port, and (2) outbound ephemeral ports from targets back to the ALB subnet. If the health checks come from the ALB nodes, blocking the ALB subnet CIDR inbound to targets breaks them.

**C6. Scenario:** You must allow HTTPS from anywhere, SSH only from the corporate CIDR 198.51.100.0/24, and explicitly block a known bad CIDR 192.0.2.0/24 — all at the subnet level.
**Question:** Write the ordered inbound NACL rules.
**Expected answer:** Rule 10: DENY 192.0.2.0/24 (block first). Rule 20: ALLOW TCP 22 from 198.51.100.0/24. Rule 30: ALLOW TCP 443 from 0.0.0.0/0. Rule 40: ALLOW ephemeral ports as needed for return traffic inbound. (Implicit * deny all). Order matters: the specific deny precedes the broad allow.
