# NAT Gateway — Interview Questions

> **Cloud:** AWS · **Category:** Networking · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~10 min

---

## JSON File Format

A NAT Gateway is declared in JSON via CloudFormation `AWS::EC2::NatGateway` (and the Elastic IP via `AWS::EC2::EIP`).

```json
{
  "Type": "AWS::EC2::NatGateway",
  "Properties": {
    "SubnetId": "subnet-public-1",
    "AllocationId": { "Fn::GetAtt": ["MyEIP", "AllocationId"] },
    "ConnectivityType": "public"
  }
}
```

**Key fields:** `SubnetId` (must be a **public** subnet) · `AllocationId` (the Elastic IP) · `ConnectivityType` (public / private for private-NAT). Route tables reference the NAT via `AWS::EC2::Route` with `NatGatewayId`.


## Case A — Basic

**A1. What is a NAT Gateway and what does it do?**
**Answer:** A managed AWS service that lets instances in a **private subnet** initiate outbound traffic to the internet (e.g., download patches) while preventing the internet from initiating connections to those instances. It performs network address translation.

**A2. Where is a NAT Gateway deployed — public or private subnet?**
**Answer:** In a **public subnet** (with a route to the Internet Gateway). Private subnets then route their 0.0.0.0/0 traffic to the NAT Gateway.

**A3. Why can't a private-subnet instance just use the Internet Gateway?**
**Answer:** An instance must have a public IPv4 address to use the IGW directly. Private instances have no public IP. The NAT Gateway provides a public IP and forwards their outbound traffic, translating the source address.

**A4. Is the NAT Gateway stateful?**
**Answer:** Yes. It tracks connections so return traffic from the internet is allowed back to the originating instance, but unsolicited inbound connections are dropped.

**A5. What are NAT Gateways vs NAT Instances?**
**Answer:** NAT Gateway is a fully managed, highly available, higher-throughput service. NAT Instance is a self-managed EC2 instance running a NAT AMI (cheaper to run but a single point of failure, manual patching, limited bandwidth). AWS recommends NAT Gateway.

**A6. Is a NAT Gateway highly available across AZs?**
**Answer:** A single NAT Gateway is **not** AZ-redundant — it lives in one AZ. For HA, deploy one NAT Gateway **per AZ** and route each AZ's private subnets to the NAT in the same AZ.

**A7. How does NAT Gateway handle IP addresses?**
**Answer:** It gets an Elastic IP (or auto-assigned public IP) in the public subnet. All outbound traffic from private instances appears to come from this IP, so you can also use it for IP allowlisting to third parties.

**A8. What is the main cost driver of NAT Gateways?**
**Answer:** An hourly charge for the gateway **plus** a per-GB data processing charge for data going through it. Heavy egress (e.g., backups) becomes expensive — a common reason to use VPC Endpoints or S3 Gateway Endpoints instead.

**A9. Can a NAT Gateway be used for inbound traffic from the internet?**
**Answer:** No — it only supports outbound-initiated connections. For inbound you need a load balancer, bastion host, or other internet-facing resource.

**A10. What's needed in route tables to make NAT work?**
**Answer:** Public subnet route table: 0.0.0.0/0 → IGW (so NAT can reach the internet). Private subnet route table: 0.0.0.0/0 → NAT Gateway ID (so private instances can reach the internet via NAT).

**A11. Does a NAT Gateway need a Security Group?**
**Answer:** No — NAT Gateways don't use security groups. Access control is done on the instances' security groups and the subnet NACLs.

**A12. How much bandwidth does a NAT Gateway support?**
**Answer:** Up to **5 Gbps** per gateway by default (bursts up to 45 Gbps with some newer instance types); beyond that, you can shard traffic across multiple NAT Gateways.

**A13. Can a NAT Gateway serve multiple subnets?**
**Answer:** Yes — multiple private subnets (in the same or different AZs) can route to a single NAT Gateway, though this creates cross-AZ traffic and a shared point of failure.

**A14. What is the difference between a NAT Gateway and an Internet Gateway?**
**Answer:** IGW is a horizontally scaled, redundant, free attachment that provides internet **connectivity both directions** for public IPs. NAT Gateway provides **outbound-only** access for private IPs and costs per hour + per GB.

**A15. What happens to connections through a NAT Gateway if the gateway fails or you delete it?**
**Answer:** Existing connections drop and new outbound connections fail until the gateway is restored or replaced. Per-AZ NAT gateways avoid this single point of failure.

---

## Case B — Advanced (Senior)

**B1. Explain the difference between the NAT Gateway's use of source NAT and why unsolicited inbound is blocked.**
**Answer:** The NAT Gateway performs SNAT (source NAT) plus PAT (port address translation): it rewrites the private source IP/port to its Elastic IP and a unique ephemeral port, and keeps a connection table. Return packets are matched to the table; anything not matching (unsolicited inbound) has no mapping and is dropped — that's the security boundary.

**B2. How do you design NAT for multi-AZ high availability, and what's the tradeoff of a single NAT?**
**Answer:** Best practice: one NAT Gateway in each AZ, with each AZ's private subnets routing to the local NAT Gateway. This keeps traffic local (no cross-AZ charges) and survives an AZ failure. A single NAT is cheaper but is a cross-AZ single point of failure.

**B3. When should you use a VPC Endpoint instead of a NAT Gateway, and why (cost + security)?**
**Answer:** For AWS services like S3 and DynamoDB, use **Gateway Endpoints** (free) or **Interface Endpoints** so private instances reach the service without internet, without NAT data-processing charges, and without exposing traffic. This avoids NAT egress cost and keeps traffic on the AWS backbone.

**B4. How do you mitigate NAT Gateway egress costs for large data transfers?**
**Answer:** (1) Use S3 Gateway Endpoints for S3/DynamoDB. (2) Use Interface Endpoints for other AWS services. (3) Keep cross-AZ data local to avoid NAT + cross-AZ double-charging. (4) Consolidate egress through Direct Connect or a proxy if on-prem is the destination. (5) Monitor via Cost Explorer (NAT Gateway-Hours and NAT Gateway-Bytes).

**B5. How does NAT Gateway behave with connection tracking, and what are the connection/port limits?**
**Answer:** It maintains a NAT translation table with limits (roughly ~55,000 simultaneous connections per unique destination IP:port). Exceeding it causes connection failures — mitigated by distributing load, scaling NATs, or using a proxy. Also be aware of idle-connection timeouts (a NAT Gateway can time out idle connections after ~350s for TCP).

**B6. What is the idle-timeout behavior of NAT Gateways and how does it affect long-lived connections?**
**Answer:** NAT Gateways enforce idle timeouts (e.g., ~350 seconds for TCP, ~30s for some protocols) to reclaim ports. Long-lived idle connections (e.g., DB keepalives) can be dropped — mitigate with TCP keepalives configured below the timeout, or application-level reconnects.

**B7. How does a NAT Gateway interact with NACLs and Security Groups?**
**Answer:** The NAT Gateway itself has no SG, but it sits in a subnet whose **NACL** applies to its traffic. The private instances' **SGs** still control what outbound traffic they may initiate. So egress policy = instance SG (allow destination) + subnet NACLs (both directions, ephemeral returns).

**B8. Compare NAT Gateway vs a NAT Instance for throughput, HA, and cost in a production design.**
**Answer:** NAT Gateway: managed, per-AZ HA via multiple gateways, 5–45 Gbps, pay per hour+GB, no patching. NAT Instance: self-managed, can be a single point of failure (mitigated with Auto Scaling groups), throughput limited by instance size, needs patching/AMIs, but has no per-GB processing fee (only EC2 cost). Choose NAT Gateway for production reliability; NAT Instance mainly for budget or specific routing needs.

**B9. Can a NAT Gateway be reached by an instance in the same public subnet it resides in?**
**Answer:** No. NAT Gateway traffic must come from a **different subnet**. Instances in the NAT's own public subnet must use the IGW (they have public IPs) for internet access, not the NAT.

**B10. What are the considerations for using NAT Gateway with IPv6?**
**Answer:** NAT Gateways are IPv4-only. For IPv6, you use an **egress-only internet gateway**, which provides outbound-only IPv6 access (the IPv6 equivalent of NAT). Private IPv4 traffic still uses the NAT Gateway.

**B11. How do you monitor and troubleshoot a NAT Gateway?**
**Answer:** CloudWatch metrics: BytesInFromSource, BytesOutToSource, BytesInFromDestination, BytesOutToDestination, ActiveConnectionCount, ConnectionAttemptCount, ErrorPortAllocation, PacketsDropCount, IdleTimeoutCount. High ErrorPortAllocation → port exhaustion; IdleTimeoutCount → keepalive tuning; use VPC Flow Logs to confirm paths.

**B12. How does NAT Gateway fit into a hub-and-spoke / centralized egress architecture?**
**Answer:** In multi-account designs, you can centralize internet egress in a "network/egress VPC" that has the NAT Gateway(s) and share it via Transit Gateway so spoke VPCs route 0.0.0.0/0 to the central NAT. This consolidates cost/control but adds cross-VPC latency and a central failure point — weigh against per-VPC NATs.

---

## Case C — Scenario

**C1. Scenario:** Private instances can't reach the internet after a change. You verify: private route table has 0.0.0.0/0 → nat-xxxx, and the NAT's public subnet has 0.0.0.0/0 → igw.
**Question:** What else could be wrong? List checks.
**Expected answer:** (1) NAT Gateway is in a public subnet **and** has an Elastic IP still attached. (2) The NAT's subnet NACL allows traffic both directions. (3) Instance SGs allow the outbound destination. (4) The NAT Gateway is in a **different AZ/subnet** than the instance's route expects (routes are fine, but check NAT status = available). (5) Check CloudWatch for ErrorPortAllocation (port exhaustion).

**C2. Scenario:** An app in private subnets downloads S3 data nightly (tens of TB), and the NAT Gateway bill exploded.
**Question:** Propose cost and performance improvements.
**Expected answer:** Add an **S3 Gateway Endpoint** and route S3 traffic to it — S3 traffic then bypasses the NAT entirely (no per-GB NAT charge, no internet). For other AWS services, add Interface Endpoints. Re-verify with Cost Explorer that NAT Bytes drop. Optionally keep NAT only for truly external destinations.

**C3. Scenario:** Company policy: no instance may have a public IP, but devs need outbound internet for package downloads.
**Question:** Design the standard AWS pattern.
**Expected answer:** Private subnets for instances (no public IPs) + NAT Gateway in a public subnet (with EIP) + route private 0.0.0.0/0 → NAT + SG allowing required outbound destinations only + NACLs. For HA, one NAT per AZ. This gives outbound-only access with no publicly reachable instances.

**C4. Scenario:** You use one NAT Gateway for 3 AZs. AZ-1 goes down. Apps in AZ-1's private subnets lose internet even though they're healthy in other AZs.
**Question:** Explain and fix.
**Expected answer:** If the single NAT lives in AZ-1 (or AZ-1's route table points to it and AZ-1 networking is impaired), AZ-1's private instances lose their egress path — a single-NAT cross-AZ failure. Fix: deploy a NAT Gateway in **each** AZ and route each AZ's private subnets to their **local** NAT. This also eliminates cross-AZ data charges.

**C5. Scenario:** A partner SaaS vendor can only allowlist your outbound IP. Your fleet uses NAT Gateways in 3 AZs.
**Question:** What issue will the vendor see, and how do you give them stable IPs?
**Expected answer:** Each NAT Gateway has a different Elastic IP, so the vendor sees three different source IPs depending on AZ. Options: (1) give the vendor all three EIPs, (2) route egress through a single NAT (loses HA), or (3) use a proxy/Network Firewall or AWS Global Accelerator-style egress with one IP — simplest is to publish the full set of NAT EIPs.

**C6. Scenario:** Long-running DB connections from on-prem through a NAT-then-VPN path (or an app's idle pooled connections) keep dropping every ~5–6 minutes.
**Question:** Diagnose and recommend fixes.
**Expected answer:** Likely the NAT Gateway idle timeout (~350s) is killing idle connections. Fixes: enable **TCP keepalives** on clients with an interval below the NAT idle timeout (e.g., every 60–300s), or implement application-level reconnection/retry, or increase connection churn so connections don't idle. Verify with IdleTimeoutCount CloudWatch metric.
