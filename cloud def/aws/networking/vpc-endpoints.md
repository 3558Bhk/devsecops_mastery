# VPC Endpoints (Gateway & Interface) — Interview Questions

> **Cloud:** AWS · **Category:** Networking · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~10 min

---

## JSON File Format

VPC Endpoints are JSON in CloudFormation (`AWS::EC2::VPCEndpoint`). The **endpoint policy** (an IAM-style policy document) is the important JSON payload inside it.

```json
{
  "Type": "AWS::EC2::VPCEndpoint",
  "Properties": {
    "VpcEndpointType": "Interface",
    "ServiceName": "com.amazonaws.us-east-1.ssm",
    "VpcId": "vpc-0abc123",
    "SubnetIds": ["subnet-1", "subnet-2"],
    "PrivateDnsEnabled": true,
    "SecurityGroupIds": ["sg-0abc123"],
    "PolicyDocument": { "Statement": [ { "Effect": "Allow", "Action": "*", "Resource": "*" } ] }
  }
}
```

**Key fields:** `VpcEndpointType` (Interface / Gateway) · `ServiceName` · `PrivateDnsEnabled` · `PolicyDocument` (endpoint policy — extra gate on top of IAM).


## Case A — Basic

**A1. What is a VPC Endpoint?**
**Answer:** A service that lets you privately connect your VPC to supported AWS services (and PrivateLink-powered services) without going over the internet, a NAT gateway, a VPN, or Direct Connect. Traffic stays on the AWS network.

**A2. What are the two types of VPC Endpoints?**
**Answer:** **Gateway Endpoints** (for S3 and DynamoDB — free, route-table based) and **Interface Endpoints** (ENI-based, powered by AWS PrivateLink, for most other services — hourly + per-GB charges).

**A3. What services support Gateway Endpoints?**
**Answer:** Only **Amazon S3** and **Amazon DynamoDB**. Everything else (e.g., SSM, KMS, SQS, SNS, ECR, API Gateway, etc.) uses Interface Endpoints.

**A4. How does a Gateway Endpoint work?**
**Answer:** It adds a target entry in your **route table**: traffic destined for the S3/DynamoDB public IP ranges is routed directly to the service via the endpoint instead of through the internet/NAT. No ENI is created.

**A5. How does an Interface Endpoint work?**
**Answer:** It creates an **ENI with a private IP** in each selected subnet. Applications connect to that private IP (or a private DNS name) and traffic is routed via PrivateLink to the service.

**A6. Do VPC Endpoints work across regions or VPCs?**
**Answer:** An endpoint lives in **one VPC in one region** and serves that VPC. (PrivateLink can also be shared across VPCs/accounts, but the endpoint itself is regional and VPC-scoped.)

**A7. What is the main benefit of using VPC Endpoints?**
**Answer:** Security and cost: private instances reach AWS services without internet/NAT (no NAT per-GB charges, no exposure to the internet), lower latency, and you can restrict access with endpoint policies.

**A8. What is AWS PrivateLink?**
**Answer:** The underlying technology that powers Interface Endpoints. It also lets **service providers** expose their own services to **consumers** in other VPCs/accounts privately, without VPC peering.

**A9. Can you attach a Security Group to a VPC Endpoint?**
**Answer:** To **Interface Endpoints** yes (each endpoint ENI has SGs). **Gateway Endpoints** do not have security groups — you control them via endpoint policies and route tables.

**A10. What is an endpoint policy?**
**Answer:** An IAM resource policy attached to the endpoint that controls **which** requests can use it (e.g., allow only `s3:GetObject` on a specific bucket via this endpoint). It's an additional layer beyond IAM user/role policies.

**A11. Do you need internet access for a VPC Endpoint to work?**
**Answer:** No — that's the point. Endpoints work entirely within the AWS network; the private subnet needs no IGW or NAT.

**A12. What's the difference between a VPC Endpoint and VPC Peering?**
**Answer:** Peering connects **two VPCs**. An endpoint connects your VPC to an **AWS service** (or a shared PrivateLink service). PrivateLink is typically one-directional (consumer → provider).

**A13. How does DNS resolution work with Interface Endpoints?**
**Answer:** With **Private DNS** enabled, requests to the default service endpoint (e.g., `sqs.us-east-1.amazonaws.com`) resolve to the endpoint's private IPs automatically. Without it, you must use the endpoint-specific DNS names or your own Route 53 entries.

**A14. What is a VPC endpoint's pricing model?**
**Answer:** Gateway Endpoints are **free** (you pay only standard S3/DynamoDB costs). Interface Endpoints cost an **hourly fee per AZ** + a **per-GB** data processing charge.

**A15. Can Gateway and Interface endpoints coexist for the same service?**
**Answer:** Gateway endpoints exist only for S3/DynamoDB; S3/DynamoDB can also use Interface endpoints (charged) if you need them in a shared VPC or for on-prem via DX. You can have both types in one VPC.

---

## Case B — Advanced (Senior)

**B1. Explain how a Gateway Endpoint route and endpoint policy combine to secure S3 access.**
**Answer:** The route table entry ensures traffic to S3 goes via the endpoint. The endpoint policy acts as an extra gate: even if an instance's IAM role allows S3, the request must also match the endpoint policy (e.g., only `s3:GetObject` on bucket `prod-data-*`). This gives defense-in-depth: IAM role (who) + endpoint policy (what/which bucket) + bucket policy (resource side).

**B2. How do you prevent instances from bypassing a Gateway Endpoint and going to S3 over the internet/NAT?**
**Answer:** (1) Route S3 prefixes to the endpoint in the route table. (2) Add an endpoint policy that **denies** access unless `aws:sourceVpce` is the endpoint ID. (3) Restrict the bucket policy to the VPC endpoint (aws:SourceVpce). (4) Remove/scope NAT and IGW routes so internet egress to S3 isn't possible. This is the standard "lock S3 to the VPC" pattern.

**B3. When would you choose an Interface Endpoint for S3 over a Gateway Endpoint?**
**Answer:** When you need S3 access from **on-premises over Direct Connect/VPN**, from **another region**, from a **shared VPC** (e.g., a participant VPC), or when you need granular private DNS and SG control on the endpoint itself. Interface endpoints support these; Gateway endpoints are VPC-local and route-table-based only.

**B4. How does PrivateLink enable multi-tenant service sharing without peering or overlapping-CIDR issues?**
**Answer:** The provider creates a VPC Endpoint **Service** (NLB-backed) and grants access to consumer AWS accounts/principals. The consumer creates an Interface Endpoint in **their** VPC — no CIDR overlap concerns, no transitive network, no peering, and traffic is unidirectional (consumer→provider), keeping provider networks hidden.

**B5. What are the key limits/considerations for Interface Endpoints in production?**
**Answer:** (1) One endpoint can serve multiple subnets in one VPC (one ENI per AZ), but a single endpoint spans the VPC. (2) Private DNS only works within the VPC (enable `enableDnsHostnames`). (3) You pay per AZ-hour + per GB. (4) Endpoint policies size limits. (5) For cross-account on-prem access, you may need the consumer to share DNS or use Route 53 Resolver endpoints.

**B6. How do VPC Endpoints interact with Route 53 Resolver and hybrid DNS?**
**Answer:** Interface endpoint private DNS uses the VPC's Route 53 Resolver (VPC +2 address). For on-premises to resolve AWS service names through the endpoint, you need Route 53 Resolver **Inbound Endpoints** or a hybrid DNS design (or use the endpoint's private DNS name explicitly). This is a frequent hybrid-cloud interview topic.

**B7. How do you grant cross-account access to a VPC Endpoint Service, and how is acceptance handled?**
**Answer:** Provider: create NLB + endpoint service, then `ModifyVpcEndpointServicePermissions` to allow consumer account IDs (or all principals). Consumer: create the Interface Endpoint targeting the service name (auto-accept, or provider accepts the connection request). The provider controls who can connect; the consumer controls routing/DNS/SGs.

**B8. What's the difference between an endpoint policy and an SCP/bucket policy, and how do they compose?**
**Answer:** Endpoint policy = which requests may traverse **this endpoint**. Bucket policy = what the **resource** allows. IAM/SCP = what the **principal** may do. Effective permission = intersection of all. SCPs cap the account; endpoint policies add a network-path gate. All must allow for the action to succeed.

**B9. How do you troubleshoot "private DNS not resolving" for an Interface Endpoint?**
**Answer:** Check (1) `enableDnsSupport`/`enableDnsHostnames` on the VPC, (2) endpoint "Private DNS enabled" flag, (3) the endpoint's security group allows inbound 443 from the consumer subnets, (4) NACL allows traffic to the endpoint ENIs, (5) DNS resolution from the instance (nslookup the service name) and the endpoint ENI IPs.

**B10. How does an Interface Endpoint achieve HA, and what does an AZ outage do to it?**
**Answer:** It provisions an ENI in **each selected AZ**, and AWS manages redundancy. If you enable only one AZ's subnet, you lose that endpoint ENI in an AZ failure. Best practice: select subnets in **all AZs** where consumers live, so each AZ resolves to a local endpoint ENI.

**B11. Compare NAT Gateway vs VPC Endpoint for accessing AWS services from private subnets.**
**Answer:** NAT = generic outbound internet access, charges per GB, traffic leaves the VPC to the service's public endpoints. Endpoint = private path to specific AWS services, lower latency, no internet exposure, Gateway endpoints are free (S3/DDB), Interface endpoints have AZ-hour+GB fees. For AWS-native services, endpoints are usually the right default; NAT is for everything else.

**B12. How do you secure an Interface Endpoint against cross-tenant or unauthorized use?**
**Answer:** Attach restrictive security groups (allow only consumer CIDRs on 443), attach an endpoint policy limiting principals/actions/resources, enable Private DNS only when needed, use IAM conditions (e.g., `aws:SourceVpce`) on service side, and audit via CloudTrail (which logs endpoint policy changes) and VPC Flow Logs.

---

## Case C — Scenario

**C1. Scenario:** Private EC2 instances need to download from S3, run SSM patches, and use KMS-encrypted EBS, but they currently have no internet access by policy.
**Question:** Design the connectivity.
**Expected answer:** Add an **S3 Gateway Endpoint** (free) for S3, and **Interface Endpoints** for SSM (`ssm`, `ec2messages`, `ssmmessages`) and **KMS** (`kms`). Route S3 traffic via the endpoint in route tables; for interface endpoints enable Private DNS or use endpoint DNS names. No NAT/IGW needed. Attach endpoint policies to limit scope.

**C2. Scenario:** A bucket policy already restricts access to VPC endpoint `vpce-abc`. A new team connects via a second VPC and endpoint `vpce-xyz` and gets AccessDenied.
**Question:** Why, and how do you allow them safely?
**Expected answer:** The bucket policy's `aws:SourceVpce` condition only trusts `vpce-abc`. Requests via `vpce-xyz` don't match, so they're denied (as intended). To allow: add `vpce-xyz` to the bucket policy's condition list, and add an endpoint policy on `vpce-xyz` limiting actions/buckets. Keep least privilege on both sides.

**C3. Scenario:** You must expose an internal REST API (running behind an NLB) to 30 customer VPCs without peering and without internet.
**Question:** Design with PrivateLink.
**Expected answer:** Provider: NLB (internal) → VPC Endpoint Service, grant the 30 consumer account IDs. Consumers: each creates an Interface Endpoint for the service (one per VPC, ENI per AZ), attach SGs, and call via the endpoint's private DNS name. This gives 30 one-way private connections with no peering mesh and no CIDR overlap constraints.

**C4. Scenario:** On-premises users need to reach S3 and a custom SaaS over Direct Connect, but your security policy forbids routing internet traffic over the DX.
**Question:** Which endpoint types solve this?
**Expected answer:** **Interface Endpoints** for S3 (Gateway endpoints are VPC-only and cannot serve on-prem). For the SaaS, consume its **PrivateLink endpoint service** via an Interface Endpoint in your VPC. Both are reachable from on-prem through the DX via the VPC's private routing — no internet path needed. Ensure Route 53 Resolver (inbound) or explicit DNS names for on-prem resolution.

**C5. Scenario:** An Interface Endpoint for SQS was created in one subnet/AZ. During an AZ outage, consumers in another AZ fail to reach SQS.
**Question:** Diagnose and fix.
**Expected answer:** The endpoint only has an ENI in the single selected subnet/AZ. Fix: modify the endpoint to add subnets in **all AZs** where consumers run, so each AZ has a local endpoint ENI. Also confirm consumers' route tables/SGs allow the endpoint ENIs and that Private DNS is enabled.

**C6. Scenario:** The security team wants proof that a specific VPC can *only* reach S3 through the endpoint (no internet fallback).
**Question:** How do you enforce and verify?
**Expected answer:** Enforce: route S3 prefixes to the Gateway Endpoint; add endpoint policy requiring `aws:SourceVpce`; add SCP/bucket policy restricting to the endpoint; remove IGW/NAT routes to S3 public ranges (or deny via NACL). Verify: check route tables, use VPC Flow Logs to confirm no traffic to S3 over IGW/NAT, and test from an instance while monitoring flow logs/CloudTrail (request shows vpce source).
