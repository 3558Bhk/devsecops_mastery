# Terraform VPC Networking (AWS) — Interview Questions

> **Cloud:** AWS · **IaC Tool:** Terraform · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~6 min

---

## Case A — Basic

**A1. What resources make up a basic VPC in Terraform?**
**Answer:** `aws_vpc`, `aws_subnet`, `aws_internet_gateway`, `aws_route_table` (+ `aws_route_table_association`), and `aws_security_group`. A NAT gateway plus elastic IP is added for private subnets' egress.

**A2. How do you declare a VPC?**
**Answer:** `resource "aws_vpc" "main" { cidr_block = "10.0.0.0/16" ; enable_dns_support = true ; enable_dns_hostnames = true }`.

**A3. What is an Internet Gateway and how do you attach it?**
**Answer:** A horizontally scaled gateway that gives a VPC internet access. Attach with `resource "aws_internet_gateway" "igw" { vpc_id = aws_vpc.main.id }` — one per VPC.

**A4. What is a subnet and how is it declared?**
**Answer:** A CIDR range within an AZ inside the VPC: `resource "aws_subnet" "public" { vpc_id = ... ; cidr_block = "10.0.1.0/24" ; availability_zone = "us-east-1a" ; map_public_ip_on_launch = true }`.

**A5. What is a route table?**
**Answer:** A set of rules directing traffic from subnets. A public subnet's route table has a route `0.0.0.0/0 → internet_gateway`; a private subnet's goes `0.0.0.0/0 → nat_gateway`.

**A6. How do you associate a subnet with a route table?**
**Answer:** `resource "aws_route_table_association" "a" { subnet_id = ... ; route_table_id = ... }`.

**A7. What is a NAT Gateway and what does it need?**
**Answer:** It lets private subnets reach the internet (outbound only). It needs a public subnet and an `aws_eip`, and it's AZ-specific (so one per AZ for HA).

**A8. How do you get available AZs dynamically?**
**Answer:** `data "aws_availability_zones" "available" { state = "available" }`, then iterate with `count`/`for_each`.

**A9. What is `cidrsubnet()`?**
**Answer:** A function that computes subnet CIDRs from a base, e.g. `cidrsubnet("10.0.0.0/16", 8, 0)` → `10.0.0.0/24`, useful for generating subnet blocks programmatically.

**A10. What is a VPC endpoint in Terraform?**
**Answer:** `aws_vpc_endpoint` for Gateway endpoints (S3, DynamoDB) or Interface endpoints (private access to AWS services), with `vpc_endpoint_type`, `service_name`, and route/security group config.

**A11. What is VPC peering in Terraform?**
**Answer:** `aws_vpc_peering_connection` + `aws_vpc_peering_connection_accepter` (cross-account) + routes in both VPCs' route tables pointing at the peer connection.

**A12. What does `enable_dns_hostnames` do?**
**Answer:** Enables public DNS hostnames for instances in the VPC — required for many services and for SSH-friendly naming.

**A13. How do you set a default security group/route table on a VPC?**
**Answer:** With `aws_default_route_table`, `aws_default_security_group`, `aws_default_network_acl` resources, which adopt and modify the VPC's default objects rather than creating new ones.

**A14. What is `aws_network_interface`?**
**Answer:** An ENI you can create and attach to instances/endpoints explicitly, with its own private IPs, security groups, and subnet.

**A15. What is a subnet group concept (for RDS/ElastiCache)?**
**Answer:** `aws_db_subnet_group` / `aws_elasticache_subnet_group` — a named set of subnets spanning AZs that the managed service places replicas into.

## Case B — Advanced / Senior

**B1. How do you build a three-tier VPC with high availability?**
**Answer:** A VPC with public subnets (IGW + NAT in one AZ) and private app/data subnets across ≥2 AZs; NAT per AZ for resilience; route tables per tier; and flow logs. Loop resources with `count = length(local.azs)`.

**B2. What is the subnet-per-AZ NAT pattern and why?**
**Answer:** One NAT Gateway per AZ so each AZ's private subnets egress through their own AZ's NAT — surviving an AZ outage and avoiding cross-AZ data charges.

**B3. How do you avoid "chicken-and-egg" ordering with subnets and NAT?**
**Answer:** Terraform's dependency graph handles it via references (NAT references the public subnet; private route references the NAT). For cyclic cases, split tiers into modules or use `depends_on` deliberately.

**B4. What are the tradeoffs of one NAT vs multiple NATs?**
**Answer:** One NAT is cheaper but a single AZ point of failure and cross-AZ traffic cost. Multiple NATs cost more but are HA. Choose based on availability requirements.

**B5. Explain Gateway vs Interface endpoints and their Terraform config.**
**Answer:** Gateway endpoints (S3/DynamoDB) add routes in the route table, no ENI, no cost. Interface endpoints create ENIs + security groups in subnets, cost hourly, and support PrivateLink to many services.

**B6. How do you peer VPCs across accounts in Terraform?**
**Answer:** In the requester account, `aws_vpc_peering_connection` with `peer_owner_id`; in the accepter, `aws_vpc_peering_connection_accepter` (with an aliased provider); then add routes in both route tables and update security groups.

**B7. When would you use a Transit Gateway over peering?**
**Answer:** For hub-and-spoke or many-to-many connectivity (e.g. 20+ VPCs, on-prem VPN). `aws_ec2_transit_gateway` + attachments + route tables scale better than full-mesh peering.

**B8. How do you structure a reusable VPC module?**
**Answer:** Inputs: CIDR, AZs, subnet counts/CIDRs, NAT preference; outputs: VPC ID, subnet IDs grouped by tier, SG IDs, route table IDs. Use `for_each`/`cidrsubnet` internally and expose clean grouped outputs.

**B9. What is `aws_vpc_dhcp_options`?**
**Answer:** Custom DHCP option sets for the VPC (domain name, NTP, NetBIOS). Attach with `aws_vpc_dhcp_options_association`.

**B10. How do you enable VPC Flow Logs in Terraform?**
**Answer:** `aws_flow_log` targeting CloudWatch Logs or S3, with `traffic_type`, `log_destination`, and an IAM role for CloudWatch. Flow logs capture accepted/rejected IP traffic metadata.

**B11. What's the risk of editing CIDRs after resources exist?**
**Answer:** Most CIDR changes force replacement of the VPC/subnets and everything inside. Plan your CIDR scheme up front and use IPAM or careful `cidrsubnet` math.

**B12. How do you avoid recreation churn from ordering a list of subnets?**
**Answer:** Use `for_each` with stable keys (names/AZ) instead of `count`, and never reorder/insert into lists that feed `count` — a shifted index replaces the wrong resources.

## Case C — Scenario

**C1. You must migrate an existing single-AZ VPC to multi-AZ without downtime.**
**Answer:** Add new subnets/NAT in the second AZ (additive changes), move/duplicate workloads across AZs, then retire old subnets. Terraform handles additions cleanly; avoid changing existing resource keys so nothing is recreated.

**C2. Your private subnets can't reach S3 and you want to avoid NAT data charges.**
**Answer:** Add S3 Gateway endpoints in each subnet's route table (`aws_vpc_endpoint` with `route_table_ids`), so S3 traffic flows through the endpoint instead of the NAT/internet.

**C3. A plan wants to destroy and recreate your NAT Gateway because the EIP changed.**
**Answer:** The EIP `id`/allocation changed — either the EIP resource was recreated or imported incorrectly. Keep the EIP stable, and if unavoidable, accept a brief egress blip; otherwise pin the allocation and use `ignore_changes` on the allocation_id if it's managed elsewhere.

**C4. You need to connect a third-party's VPC (different account) to yours for a private API.**
**Answer:** Either VPC peering across accounts (requester/accepter + routes) or, better for a controlled API, an Interface VPC endpoint / PrivateLink exposing your service behind an NLB, so the third party connects via endpoint without peering their whole network.

**C5. A dev deployed the same CIDR in two VPCs that now need peering.**
**Answer:** Peering requires non-overlapping CIDRs — re-IP one VPC (painful) or route through a NAT/proxy or Transit Gateway with NAT (still tricky). Plan: rebuild the smaller VPC with a unique CIDR and migrate workloads.

**C6. You're asked to enforce "no public subnets" in a compliance rule.**
**Answer:** In the module, don't create IGW routes to subnets; add policy-as-code checks that no route targets an IGW and no `map_public_ip_on_launch = true`; expose only private subnets. Centralize egress through NAT or a shared egress VPC.
