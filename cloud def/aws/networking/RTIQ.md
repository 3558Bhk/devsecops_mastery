# RTIQ — AWS Networking (Real-Time Interview Questions)

> **Cloud:** AWS · **Domain:** VPC endpoints, NAT gateway, security groups, NACLs, peering, Transit Gateway · **Target roles:** SDE-3 · Cloud Engineer · DevOps · DevSecOps · SRE · Platform Engineer · **Reading time:** ~20 min

**How this file is used live:** networking rounds are the great filter for cloud/DevOps roles. Interviewers draw a box-and-arrow diagram and ask you to say which packets *can't* flow and why. After the definitions, they always land on connectivity failures ("private subnet has no internet", "peered VPCs still can't talk") and cost ("NAT gateway bill is huge").

**Legend:** ⚡ Rapid · 🔍 Deep dive + follow-ups · 🚨 War room · ⚖️ Trade-off debate · 🎯 Senior signal

---

## 1. VPC Endpoints — `vpc-endpoints.md`

**⚡ Rapid**
1. **Q:** Gateway vs interface endpoint — one line each?
**A.** Gateway endpoints (S3, DynamoDB) work via route-table entries and are free. Interface endpoints (PrivateLink, most other services incl. SQS, KMS, ECR, Secrets Manager, STS) create ENIs with private IPs and cost an hourly + per-GB fee.
2. **Q:** Why use endpoints at all?
**A.** Keep traffic off the public internet (security), allow private subnets without a NAT gateway for AWS API calls (cost + resilience), and enforce policy at the endpoint (governance).
3. **Q:** What is an endpoint policy?
**A.** A resource policy on the endpoint restricting what can be done through it — e.g. allow only specific S3 buckets or read-only actions. It's an additional, independent control: identity policy AND endpoint policy must allow.
4. **Q:** Do endpoints need security groups?
**A.** Interface endpoints do (they're ENIs — allow 443 from your app subnets). Gateway endpoints do not — you control access with route tables and policies.
5. **Q:** Does a gateway endpoint work from on-premises over VPN/Direct Connect?
**A.** No — it's route-table based inside the VPC. On-prem needs interface endpoints (or a NAT/proxy), which trips people up during hybrid migrations.

**🔍 Deep dive**
6. **Q:** A private-subnet instance can't reach SQS even though the interface endpoint exists. Debug it.
**A.** Check: endpoint SG allows 443 from the instance's SG; endpoint policy allows the actions; instance's SG permits egress 443 to the endpoint ENI; `enable_dns_support`/`hosted zone` resolution for the service endpoint (private DNS enabled); NACL on the subnet; then service-specific permissions (e.g. KMS for SSE-CMK queues). Endpoint present ≠ reachable.
**↳ Follow-up:** "How would you prove it's the endpoint vs DNS?"
**A.** Compare `nslookup`/`dig` from the instance — private DNS should resolve the service name to the ENI's private IP. If it resolves to a public IP, private DNS is off. Test with `curl` to the private IP and check VPC flow logs for the flow.
7. **Q:** How do you use endpoints to enforce "all S3 traffic stays inside the VPC"?
**A.** Gateway endpoint + route table entries + bucket policy denying requests where `aws:SourceVpce` isn't your endpoint, plus SCP/endpoint policy restricting to approved buckets. Then egress via IGW/NAT to S3 can be blocked or at least alerted on.
8. **Q:** Cost maths: interface endpoints vs NAT gateway for heavy AWS API traffic.
**A.** NAT: ~$0.045/GB processed (plus hourly). Interface endpoint: hourly per ENI per AZ plus ~$0.01/GB. For high-volume S3/DDB → gateway endpoint (free, no brainer). For high-volume ECR/KMS/SQS → interface endpoints usually win, and they also cut NAT dependency/resilience risk. Model the actual GB and show the crossover.
9. **Q:** How do endpoints interact with a centralized egress VPC?
**A.** Shared interface endpoints via PrivateLink in the egress VPC (or endpoint services) let spoke VPCs consume centralised endpoints instead of duplicating ENIs in every VPC — but you must handle DNS (Route 53 Resolver/private zones) and SG referencing across VPCs. It's a real design consideration in large orgs.

**🚨 War room**
10. **Q:** After adding a gateway endpoint, some S3 access broke. Why could that happen?
**A.** Endpoint policy too restrictive (missing `s3:GetObject` for a prefix), or route tables updated in only some subnets — traffic from un-updated subnets still goes via NAT/IGW and now fails the bucket policy's `aws:SourceVpce` condition. Always update every subnet's route table and roll out policies in monitor mode first.
11. **Q:** Multi-AZ app loses access to Secrets Manager when one AZ fails, though the subnet is fine.
**A.** The interface endpoint was created in a single AZ (or one AZ's ENI is unhealthy) — create endpoints in ≥2–3 AZs (or all AZs used) so the failure is survivable. Same lesson applies to NAT gateways.
12. **Q:** Compliance asks "prove no data left the VPC". What do you show?
**A.** VPC Flow Logs filtered for public IP destinations, endpoint policies (only approved buckets/actions), S3/DDB gateway endpoints with restrictive bucket policies, an SCP denying egress outside approved ranges where feasible, and a report from Athena/Log Analytics over flow logs, plus Egress-only internet gateway in place of NAT for IPv6.

**⚖️ Trade-off**
13. **Q:** Gateway endpoint vs NAT for S3 — always the gateway?
**A.** Almost always yes for in-VPC traffic (free, keeps traffic private). Exceptions: cross-account bucket access patterns needing specific policy handling, or architectures where centralised inspection is mandatory; then you may route through a firewall/NAT deliberately and accept the cost.
14. **Q:** PrivateLink vs VPC peering for cross-account service access?
**A.** PrivateLink (endpoint service) exposes only a specific service, one-way, no CIDR overlap issues, and the consumer doesn't see your whole network. Peering exposes the whole VPC and requires non-overlapping CIDRs plus route tables both ways. For "consume a partner service", PrivateLink is the modern answer.
15. **Q:** Endpoint per VPC vs centralised shared endpoints?
**A.** Per-VPC = simple, no DNS gymnastics, higher cost. Centralised = cheaper at scale, needs resolver config and cross-VPC SG handling. Start per-VPC, consolidate when the endpoint bill justifies it.

**🎯 Senior**
16. **Q:** Design private connectivity for a data platform that must never touch the internet but needs S3, Glue, Athena, ECR, KMS, Secrets Manager, and on-prem access.
**A.** Private subnets only, gateway endpoint for S3/DDB, interface endpoints in 3 AZs for the rest (or centralised endpoint VPC), Direct Connect/VPN with BGP for on-prem, Route 53 Resolver inbound/outbound endpoints for hybrid DNS, egress-only IGW for IPv6, restrictive endpoint + bucket policies, flow logs to a central lake, and no NAT at all.

**🎯 Senior signal:** knowing that interface endpoints break in single-AZ and that a *gateway* endpoint can't be used from on-prem are the two details that mark real deployments.

---

## 2. NAT Gateway — `nat-gateway.md`

**⚡ Rapid**
1. **Q:** When do you need a NAT gateway?
**A.** For egress to the internet from private subnets (patching, third-party APIs, pulling public images). Not needed if all outbound traffic goes to AWS services via endpoints.
2. **Q:** Is NAT highly available by itself?
**A.** No — a NAT gateway is AZ-scoped. You must create one per AZ and route each subnet to the NAT in its own AZ, or an AZ failure takes down egress for the subnets pointed at it.
3. **Q:** NAT gateway vs NAT instance?
**A.** NAT gateway is managed, scales automatically, ~45 Gbps per gateway, no patching. NAT instance is cheaper/legacy, needs you to manage HA, patching, and throughput. NAT gateway unless cost is the dominant constraint.
4. **Q:** Does it preserve the client IP?
**A.** No — traffic appears to come from the NAT's Elastic IP. Source IP is lost, so on the destination side you allow-list NAT EIPs.

**🔍 Deep dive**
5. **Q:** "$30k/month NAT bill" — find the cause and fix it.
**A.** Enable VPC Flow Logs and aggregate bytes by destination IP with Athena — the culprits are nearly always S3/DynamoDB (add gateway endpoints), ECR pulls, CloudWatch Logs, or a chatty third-party API. Then: gateway endpoints (free), interface endpoints for frequent AWS services, move bulk data transfer to endpoints, cache image pulls, and check for a "data leak" — a service in a private subnet downloading from the internet at scale.
**↳ Follow-up:** "What if the traffic is genuinely internet-bound?"
**A.** Then optimise rather than eliminate: batch requests, add caching (CloudFront/ElastiCache), use a centralised egress VPC with a shared NAT for many VPCs (still billed, but fewer idle gateways), and validate whether the workload should be in a public-facing architecture.
6. **Q:** Design egress for a 40-VPC organisation.
**A.** Centralised egress VPC with NAT gateways per AZ (or a firewall/NAT appliance fleet), Transit Gateway attaching all spokes, spoke route tables pointing 0.0.0.0/0 at the TGW, egress VPC controlling inspection and logging. Cost is shared, security is central, and spokes stay private.
7. **Q:** How do you make egress resilient across AZs?
**A.** One NAT per AZ + route tables per subnet scoped to the local NAT. If an AZ loses its NAT, that AZ's subnets lose egress until you fail over routes — some teams accept this, others run cross-AZ failover with a secondary route (weaker AZ independence but continuous egress). State your choice and the trade.
8. **Q:** How do you know *which* workload caused a NAT spike with shared NAT?
**A.** VPC Flow Logs with `instance-id`/ENI → aggregate by source ENI in Athena; if flow logs are too coarse, use flow logs at the ENI level plus tagging the ENIs. Without attribution, everyone blames everyone.
9. **Q:** What's the difference between NAT gateway, IGW, and egress-only IGW?
**A.** IGW: bidirectional internet for public subnets (resources have public IPs). NAT: outbound-only for private IPv4. Egress-only IGW: outbound-only for IPv6 (IPv6 has no NAT). Getting this trio right is a common screening question.

**🚨 War room**
10. **Q:** Entire environment loses software updates at 3 a.m. What do you check?
**A.** Route table for the private subnets (points at NAT?), NAT gateway state and `ErrorPortAllocation`/connection errors, NAT's EIP and whether a policy/allow-list changed, subnet's `MapPublicIpOnLaunch` (irrelevant for NAT but a common confusion), associated NACL, and whether the AZ's NAT is in a different AZ than the subnet now. Also check if the destination is being blocked by an egress firewall or SCP-level egress restrictions.
11. **Q:** "Port allocation error" from the NAT gateway under load. Fix?
**A.** Source port exhaustion: too many concurrent connections through one NAT (each connection consumes a port; a NAT supports ~55k simultaneous connections per destination). Mitigations: add more NAT gateways and spread egress across AZs, reduce connection churn with connection pooling/keep-alive, and cut the number of distinct destinations.
12. **Q:** Logs say NAT is fine, but the third-party API blocks you. Why?
**A.** The partner allow-lists the NAT EIPs; if a new AZ's NAT was added (new EIP) or the gateway was replaced, those IPs aren't allowed. Fix: share the full EIP list with the partner, use stable EIPs, and prefer PrivateLink/static endpoints where available.
13. **Q:** You suspect a compromised instance is exfiltrating data via NAT. Immediate response?
**A.** Isolate the instance (SG deny-all / remove from target groups), preserve evidence (snapshot + memory if possible), analyse flow logs for destinations and volumes, rotate any credentials on that instance, notify per IR policy, then fix the exposure (endpoint policies, egress firewall/allow-list, GuardDuty).

**⚖️ Trade-off**
14. **Q:** NAT gateway vs NAT instance vs firewall appliance for egress?
**A.** NAT gateway for 90% of cases (managed, scalable). NAT instance when cost dominates and throughput is small, accepting HA work. Firewall appliance (GWLB + third-party) when you need L7 egress inspection and TLS visibility — much more expensive, but the only option for DLP/URL filtering requirements.
15. **Q:** Per-AZ NATs (resilient, pricier) vs shared NAT (cheap, fragile)?
**A.** Per-AZ by default for production; shared NAT only for dev/test or where cost genuinely dominates. The shared-NAT failure mode is exactly the AZ outage where you need the other AZ most.
16. **Q:** Are private subnets plus NAT still the right default, given endpoints?
**A.** Increasingly, a well-designed VPC uses endpoints for AWS services and little/no NAT. Keep NAT for unexpected egress and third-party calls, but treat every GB through it as a design smell to investigate.

**🎯 Senior**
17. **Q:** Give me a real cost-optimisation you did on networking.
**A.** Concrete shape: flow-log analysis → found 8 TB/month to S3 → gateway endpoint + bucket-policy restriction → NAT traffic dropped ~70% → saved $X/month and removed a NAT dependency; added a weekly cost-anomaly alarm on NAT bytes so regressions are caught in days, not on the invoice.

**🎯 Senior signal:** "we turn on flow logs and aggregate bytes per destination before touching anything" — evidence-driven egress work. Also knowing source-port exhaustion is a hallmark of real production experience.

---

## 3. Security Groups — `security-groups.md`

**⚡ Rapid**
1. **Q:** Stateful or stateless, and what does that mean for response traffic?
**A.** Security groups are stateful: return traffic for an allowed connection is automatically allowed. You never need an egress rule for replies.
2. **Q:** Can you have deny rules in a security group?
**A.** No. SGs are allow-only; the effective policy is the union of all attached SGs. Deny must come from NACLs, SCPs, endpoint policies, or a firewall appliance.
3. **Q:** How do you reference another SG?
**A.** Set the rule's source to the other SG's ID — best practice, because membership replaces IP management and works across VPCs (peered/PrivateLink) where supported.
4. **Q:** What's the default SG behaviour?
**A.** Default SG: allow all traffic from itself, allow all egress. Default egress on new SGs: allow all. Both should be tightened — unrestricted egress is how exfiltration and SSRF work.
5. **Q:** How many rules per SG?
**A.** Quotas exist per SG (inbound/outbound) and per ENI; the practical lesson is that hundreds of IP rules means you should use prefixes lists or SG references instead.

**🔍 Deep dive**
6. **Q:** How do you implement least-privilege networking for a 3-tier app?
**A.** ALB SG: 443 from the internet (or from CloudFront/WAF). App SG: app port only from the ALB SG. DB SG: DB port only from the app SG. Bastion/SSM: no open SSH (use Session Manager). Egress: 443 to endpoints/known CIDRs rather than 0.0.0.0/0. Each hop references the previous SG.
**↳ Follow-up:** "How do you know the rules are right?"
**A.** Flow logs show attempted-and-denied flows (use them to find missing rules instead of guessing), Config rules check for 0.0.0.0/0 on sensitive ports, and `Reachability Analyzer` proves a path exists before you change a rule in production.
7. **Q:** An instance in a public subnet is not reachable from the internet though the SG allows 0.0.0.0/0:443. Why?
**A.** Missing public IP or Elastic IP, subnet route table lacking 0.0.0.0/0 → IGW, NACL blocking, or the resource is behind an ALB without the right target registration. Four-layer check: route table → NACL → SG → app listening.
8. **Q:** How do you restrict outbound traffic meaningfully without breaking everything?
**A.** Start with flow logs to see actual destinations, then allow-list: 443 to AWS endpoints (preferably interface endpoints so you don't need internet egress at all), your dependencies' IPs via prefix lists, plus DNS. Use a firewall/proxy for anything that must reach the open internet.
9. **Q:** How do SGs behave across peering/Transit Gateway/PrivateLink?
**A.** Peering: SG referencing works if the SGs are in the same region and peering is used, but you must also have route tables on both sides. TGW: SG referencing is not supported across attachments (use CIDRs, and be careful). PrivateLink: the consumer's SG allows the endpoint ENI, the provider's SG allows the NLB. Knowing these asymmetric rules is senior-level.
10. **Q:** What is a prefix list and why use it?
**A.** A named set of CIDRs (AWS-managed for services, or customer-managed) referenced in SG/NACL rules. It removes duplicated IP management, makes updates atomic, and is how you whitelist an SaaS provider's ranges safely.
11. **Q:** What does "SG referencing changes things in place" mean for Terraform?
**A.** SG rules can be managed as inline `ingress/egress` blocks on the SG or as separate `aws_security_group_rule`/`aws_vpc_security_group_ingress_rule` resources. Separate rules are safer for large sets (no full replacement on change) but can conflict with inline blocks — mixing both is a common source of flip-flopping plans.

**🚨 War room**
12. **Q:** Someone opened port 22 to 0.0.0.0/0 on a production SG. Response?
**A.** Revoke now (even before RCA), check flow logs/`sshd` logs for successful logins in the exposure window, rotate keys/credentials on that host, then fix structurally: no SSH (SSM Session Manager), SCP/Config auto-remediation to remove public admin rules, and an alarm on SG mutations. Report per security policy.
13. **Q:** Users intermittently can't reach the app; SG looks fine. Where do you look?
**A.** NACL (stateless — check both ingress and ephemeral egress 1024-65535), ALB target health, asymmetric routing in a multi-homed setup, MTU issues, or the app's connection limits. Also check whether a "fix" added a rule to only some of the multi-AZ instances' SGs.
14. **Q:** After a security review, the DB SG allows the app SG but the app still can't connect. Verify what?
**A.** The app's *instances* actually carry that SG (ENI attachment), the DB is listening on that port, SG referencing works only if the app SG is in the same VPC (or a supported peering), subnet route tables exist both ways, and no NACL blocks. Then test with `Reachability Analyzer`.
15. **Q:** You need to add 200 partner IPs to a rule. Best approach?
**A.** Customer-managed prefix list (single rule referencing the list), updated by IaC from the partner's published ranges; keep max entries in mind and add a change process. Never edit 200 rules by hand.

**⚖️ Trade-off**
16. **Q:** SG referencing vs CIDR rules?
**A.** SG referencing scales and survives IP changes; CIDRs are needed across accounts/VPCs where referencing isn't supported, or for external parties. Prefer references internally, CIDR/prefix lists at the edges.
17. **Q:** Firewall appliance (GWLB) vs SGs?
**A.** SGs give L4 micro-segmentation for free; appliances add L7 inspection/IDS/DLP with central policy — big cost, latency, and HA complexity. Adopt when a compliance driver demands inspected east-west traffic, not before.
18. **Q:** One SG for all instances in a tier vs per-service SGs?
**A.** Per-service/per-purpose SGs with references; a shared tier SG means any new rule applies everywhere (and reviewers can't reason about blast radius). The cost is a bit more IaC, which is automated anyway.

**🎯 Senior**
19. **Q:** How do you prove micro-segmentation to an auditor?
**A.** A generated matrix: each workload's SG references only its dependencies, backed by flow logs showing only expected flows and denied attempts, Config rules enforcing "no public admin ports", Reachability Analyzer evidence for approved paths, and change history from IaC for every rule.

**🎯 Senior signal:** "deny is impossible in SGs — statefulness plus allow-union" and doing the 4-layer troubleshooting order (route table → NACL → SG → app) immediately mark you as someone who debugs networks for a living.

---

## 4. Network ACLs — `network-acls.md`

**⚡ Rapid**
1. **Q:** SG vs NACL in one line?
**A.** SG: stateful, instance level, allow-only, all rules evaluated. NACL: stateless, subnet level, allow *and* deny, evaluated in rule-number order until a match.
2. **Q:** Why do NACLs break so many people?
**A.** Statelessness — you must allow ephemeral ports (1024–65535, or 32768–60999 depending on the OS) in *both* directions, plus remember they apply to the whole subnet.
3. **Q:** Default NACL behaviour?
**A.** The default NACL allows all inbound and outbound. Custom NACLs you create deny everything until you add rules (in order). A rule numbered `*` is the implicit final deny.
4. **Q:** When is a NACL genuinely useful?
**A.** Coarse subnet-level deny of known-bad CIDRs, a hard block during an incident, or as a compliance-mandated second layer. Not for fine-grained app segmentation — that's SGs.

**🔍 Deep dive**
5. **Q:** A user can SSH in but the session hangs after authentication. NACL hypothesis?
**A.** Inbound 22 is allowed but outbound ephemeral is not (or inbound ephemeral missing for the response) — stateless filtering drops the return/continuation packets. The classic test is "handshake works, data stalls" = asymmetric ephemeral port rules.
6. **Q:** Rule-ordering trap: allow 0.0.0.0/0 on 443 at rule 200, deny a specific IP at 300. What happens?
**A.** The specific IP is still allowed — the first matching rule wins, and 200 matches everything before 300 is ever evaluated. Deny rules must have lower numbers than the broad allow.
7. **Q:** Would you use NACLs for compliance-driven segmentation?
**A.** Only as defence in depth. Real segmentation is SG referencing (identity-based), because NACLs are IP/CIDR-based and subnet-wide — they'd allow anything in the subnet to talk to the target. Say this and you sound like you've designed networks, not just passed exams.
8. **Q:** How do NACLs interact with load balancers and autoscaling subnets?
**A.** An ALB/NLB needs the subnet's NACL to allow client traffic in and ephemeral out (for health checks, it's the LB node's traffic). A misconfigured NACL on one of several subnets causes "works in AZ-b, not AZ-a" — a favourite interview scenario.
9. **Q:** Do NACLs apply to traffic within the same subnet?
**A.** Traffic between two instances in the same subnet is *not* filtered by that subnet's NACL (AWS doesn't apply NACLs to intra-subnet traffic) — a subtle but real detail when people claim NACLs are "subnet firewalls".

**🚨 War room**
10. **Q:** After a NACL change, only one AZ's instances fail. What happened?
**A.** NACLs are per-subnet, so the change hit the subnet(s) in that AZ — and if the changed subnet hosts an ALB node or NAT gateway, dependent traffic breaks too. Fix: revert the rule, then validate across all subnets with Reachability Analyzer before re-applying.
11. **Q:** Intermittent failures on port 443 for some clients only. NACL or SG?
**A.** If it's intermittent and client-dependent, think ephemeral port ranges and asymmetric rules; if it's uniformly blocked, think SG/route. Check the rule numbers and whether the client source ports fall in a range your NACL denies (some corporate NATs use specific high port ranges).
12. **Q:** You need to block a known malicious IP range immediately, org-wide. Path?
**A.** GuardDuty/Security Hub finding → NACL deny at the edge subnets *and* block at WAF/CloudFront (or a Network Firewall) since NACLs don't help with internet traffic before it hits the ALB in the same way WAF does. Then ensure the block is codified so it isn't lost at the next redeploy.

**⚖️ Trade-off**
13. **Q:** Manage NACLs via IaC or leave them at "allow all"?
**A.** Leave them allow-all unless you have a specific need (defence in depth for a compliance control, or an incident block). Nearly every outage caused by NACLs comes from a rule nobody needed in the first place — complexity without security benefit is anti-value.
14. **Q:** NACL deny vs SCP/endpoint policy for restricting AWS API access?
**A.** NACLs operate on IPs, SCPs and endpoint policies on identity/API context — for AWS service access, endpoint policies and SCPs are far more precise and auditable. Use NACLs for network-level containment only.

**🎯 Senior**
15. **Q:** How do you troubleshoot "one subnet can't reach the internet" in under 5 minutes?
**A.** Order: (1) route table for that subnet (0.0.0.0/0 → IGW/NAT in the same AZ?), (2) NACL rules for that subnet (especially ephemeral out), (3) SG egress + target, (4) whether the resource has a public IP/EIP if the path is via IGW, (5) flow logs to see whether the packet is ACCEPT/REJECT and where. Recite it as a checklist in the interview — that's what they're grading.

**🎯 Senior signal:** NACL rule-ordering and ephemeral-port statelessness plus the "intra-subnet isn't filtered" nuance are the strongest tells that you've operated VPCs at scale.
