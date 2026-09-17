# AWS 2 — VPC & Networking Fundamentals

> **⏱️ Time to complete: ~75 min** (read + deploy the full VPC & verify routes)

## 2.1 The Mental Model

```
Internet
   │
   ▼
 Internet Gateway (IGW) ──► Public Subnet (route 0.0.0.0/0 → IGW)
                              │
                              ▼
                        NAT Gateway (EIP attached)
                              │
                              ▼
                        Private Subnet (route 0.0.0.0/0 → NAT)   ← no inbound from internet

VPC Endpoints: S3/DynamoDB traffic → Gateway Endpoint (in-VPC, free)
               Other AWS APIs      → Interface Endpoint (ENI in subnet, charged)
```

Key concepts:
- **VPC** = virtual private cloud (its own CIDR, isolated).
- **Subnet** = CIDR slice inside a VPC, **tied to one AZ**.
- **Route tables** = "how to reach destinations" per subnet.
- **Security Groups** = stateful firewall **at the ENI (instance) level**.
- **NACLs** = stateless firewall **at the subnet level** (rarely used in practice).
- **IGW** = internet egress/ingress for public subnets.
- **NAT GW** = internet egress **only** for private subnets (inbound still blocked).
- **VPCE** = private access to AWS services without public IPs.

## 2.2 A Complete VPC (the pattern you'll copy forever)

```hcl
data "aws_availability_zones" "available" {   # read the available AZs
  state = "available"                         # only AZs in the "available" state
}

locals {                                      # named expressions
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)  # first N AZs

  public_cidrs  = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, i)]        # public subnet CIDRs
  private_cidrs = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, i + 100)]  # private subnet CIDRs
}

resource "aws_vpc" "main" {                    # create the VPC
  cidr_block           = var.vpc_cidr          # the VPC CIDR
  enable_dns_support   = true                  # DNS resolution inside the VPC
  enable_dns_hostnames = true                  # auto DNS hostnames for instances
  tags = { Name = "${local.name_prefix}-vpc" } # the VPC name
}

resource "aws_internet_gateway" "main" {       # the internet gateway
  vpc_id = aws_vpc.main.id                     # attach to this VPC
  tags   = { Name = "${local.name_prefix}-igw" }
}

resource "aws_subnet" "public" {               # a public subnet (one per AZ, via count)
  count             = var.az_count             # one per AZ
  vpc_id            = aws_vpc.main.id          # the VPC
  cidr_block        = local.public_cidrs[count.index]   # this subnet's CIDR (by index)
  availability_zone = local.azs[count.index]   # the AZ (by index)
  tags = { Name = "${local.name_prefix}-public-${count.index}", Tier = "public" }
}

resource "aws_subnet" "private" {              # a private subnet (one per AZ, via count)
  count             = var.az_count             # one per AZ
  vpc_id            = aws_vpc.main.id          # the VPC
  cidr_block        = local.private_cidrs[count.index]   # this subnet's CIDR
  availability_zone = local.azs[count.index]   # the AZ
  tags = { Name = "${local.name_prefix}-private-${count.index}", Tier = "private" }
}

# One EIP + NAT GW per AZ (redundant), or one total (cheaper, single point of failure)
resource "aws_eip" "nat" {                     # an Elastic IP for the NAT (one per AZ via count)
  count = var.nat_count                        # number of NATs
  domain = "vpc"                               # VPC-scoped EIP
  depends_on = [aws_internet_gateway.main]     # wait for the IGW
}

resource "aws_nat_gateway" "main" {            # the NAT gateway (one per AZ via count)
  count         = var.nat_count                # number of NATs
  allocation_id = aws_eip.nat[count.index].id  # the EIP this NAT uses
  subnet_id     = aws_subnet.public[count.index].id   # NATs must be in a PUBLIC subnet
  tags          = { Name = "${local.name_prefix}-nat-${count.index}" }
  depends_on    = [aws_internet_gateway.main]  # wait for the IGW
}

resource "aws_route_table" "public" {          # the public route table
  vpc_id = aws_vpc.main.id                     # the VPC
  route {                                      # one route
    cidr_block = "0.0.0.0/0"                   # everything (the internet)
    gateway_id = aws_internet_gateway.main.id  # goes out via the IGW
  }
  tags = { Name = "${local.name_prefix}-public-rt" }
}

resource "aws_route_table" "private" {         # a private route table (one per NAT via count)
  count  = var.nat_count                       # one per NAT
  vpc_id = aws_vpc.main.id                     # the VPC
  route {                                      # one route
    cidr_block     = "0.0.0.0/0"               # everything
    nat_gateway_id = aws_nat_gateway.main[count.index].id   # goes out via the NAT
  }
  tags = { Name = "${local.name_prefix}-private-rt-${count.index}" }
}

resource "aws_route_table_association" "public" {   # associate public subnets with the public RT
  count          = var.az_count                 # one per AZ
  subnet_id      = aws_subnet.public[count.index].id   # the subnet
  route_table_id = aws_route_table.public.id    # the public route table
}

resource "aws_route_table_association" "private" {   # associate private subnets with a private RT
  count          = var.az_count                 # one per AZ
  subnet_id      = aws_subnet.private[count.index].id   # the subnet
  route_table_id = var.nat_count > 0 && count.index < var.nat_count ?
                   aws_route_table.private[count.index].id :
                   aws_route_table.private[0].id   # spread subnets across NATs (or use the first)
}
```

### VPC endpoints (private S3/DynamoDB access)

```hcl
# Gateway endpoint: no ENI, no charge, only S3 + DynamoDB
resource "aws_vpc_endpoint" "s3" {             # an S3 gateway endpoint
  vpc_id             = aws_vpc.main.id         # the VPC
  service_name       = "com.amazonaws.${data.aws_region.current.name}.s3"   # the S3 service in this region
  vpc_endpoint_type  = "Gateway"               # gateway type (route-table based)
  route_table_ids    = [aws_route_table.private[0].id]   # which route tables get the S3 route
  tags               = { Name = "${local.name_prefix}-s3-gw-ep" }
}

# Interface endpoint: ENI-based, for most AWS APIs (STS, SSM, EC2, Secrets Manager…)
resource "aws_vpc_endpoint" "secrets" {        # an interface endpoint for Secrets Manager
  vpc_id              = aws_vpc.main.id        # the VPC
  service_name        = "com.amazonaws.${data.aws_region.current.name}.secretsmanager"   # the SM service
  vpc_endpoint_type   = "Interface"            # interface type (ENI based)
  subnet_ids          = aws_subnet.private[*].id   # subnets to place ENIs in
  security_group_ids  = [aws_security_group.vpce.id]   # the SG controlling the ENIs
  private_dns_enabled = true      # resolve AWS SDK calls to the endpoint privately
  tags                = { Name = "${local.name_prefix}-sm-ep" }
}
```

### Flow logs (audit who talked to whom)

```hcl
resource "aws_flow_log" "vpc" {                # VPC flow logs
  vpc_id           = aws_vpc.main.id           # the VPC
  traffic_type     = "ALL"                     # accept + reject
  log_destination  = aws_s3_bucket.flow_logs.arn   # where to send logs (an S3 bucket)
  log_format       = "$vpc-id, $subnet-id, $instance-id, $src-addr, $dst-addr, $src-port, $dst-port, $protocol, $packet-count, $byte-count, $start, $end, $action, $log-status"   # the log columns
  interval         = 60                        # delivery interval (seconds)
  depends_on       = [aws_s3_bucket_lifecycle.flow]   # bucket lifecycle must exist first
}
```

## 2.3 Security Groups (the workhorse firewall)

```hcl
# ALB → instances
resource "aws_security_group" "web" {          # a security group for the web tier
  name_prefix = "${local.name_prefix}-web-"    # name prefix (AWS appends a suffix)
  vpc_id      = aws_vpc.main.id                # the VPC

  ingress {                                    # an inbound rule
    description     = "HTTP from ALB"          # what this rule does
    from_port       = 80                       # start port
    to_port         = 80                       # end port
    protocol        = "tcp"                    # the protocol
    security_groups = [aws_security_group.alb.id]   # best: reference the ALB SG, not a CIDR
  }

  egress {                                     # an outbound rule
    description = "all outbound"               # allow everything out
    from_port   = 0                            # start port (0 with -1 protocol)
    to_port     = 0                            # end port (0 with -1 protocol)
    protocol    = "-1"                         # -1 = all protocols
    cidr_blocks = ["0.0.0.0/0"]                # to anywhere
  }

  tags = { Name = "${local.name_prefix}-web-sg" }
}
```

Rules of thumb:
- **Ingress**: allow **from** (SG ref / CIDR / prefix-list) **to** port+protocol.
- **Egress**: default is allow-all; restrict when you can (DB: only web SG → 5432).
- Prefer **security group references** over CIDRs wherever possible (self-healing when IPs change).
- SGs are **stateful** (return traffic auto-allowed); NACLs are **stateless** (must allow both directions).
- SGs are **allow-only** (no deny rules). For deny, use NACLs (subnet level).

## 2.4 NACLs (rarely needed, know the difference)

```hcl
resource "aws_network_acl" "private" {         # a dedicated network ACL (replace the VPC's default one)
  vpc_id     = aws_vpc.main.id                 # the VPC it belongs to
  subnet_ids = aws_subnet.private[*].id        # the subnets it applies to

  ingress {                                    # an inbound NACL rule
    rule_no = 100                              # rule number (lower = higher priority)
    egress  = false                            # this is an INGRESS rule
    protocol = "tcp"                           # the protocol
    from_port = 22                             # start port (SSH)
    to_port   = 22                             # end port
    rule_action = "allow"                      # allow
    cidr_block = "10.0.0.0/8"                  # from this CIDR
  }

  egress {                                     # an outbound NACL rule
    rule_no = 100                              # rule number
    protocol = "-1"                            # all protocols
    rule_action = "allow"                      # allow
    cidr_block = "0.0.0.0/0"                   # to anywhere
  }
}
```

- `rule_no` (1–32766), lowest number wins; **stateless** → you must add explicit ingress AND egress.
- Use for: subnet-level blanket denials, audit, or when you need stateless behavior.
- In 95% of real architectures: **SGs are enough**.

## 2.5 Network Design Patterns

| Pattern | When |
|---|---|
| **Public + private** | Web tier internet-facing; app/DB tier private |
| **Public + private + isolated (DB)** | DB has **no route to internet at all** |
| **1 NAT per AZ** | Production (no single AZ failure) |
| **1 NAT total** | Dev (cost) |
| **VPC peering** | 2 VPCs, same/diff account, mesh-OK (no transitivity) |
| **Transit Gateway** | >2 VPCs, hub-and-spoke, many accounts |
| **Direct Connect / ExpressRoute** | On-prem ↔ cloud private backbone |
| **Client VPN / Site-to-Site VPN** | Remote/on-prem → VPC over IPsec |

### VPC peering (simple 2-VPC case)

```hcl
resource "aws_vpc_peering_connection" "to_data" {   # a VPC peering connection
  vpc_id         = aws_vpc.main.id                  # this side's VPC
  peer_vpc_id    = var.peer_vpc_id                  # the peer VPC
  peer_owner_id  = var.peer_account_id              # the peer account
  auto_accept    = var.same_account                 # auto-accept if same account
  options = {                                        # peering options
    accept_remote_gateway_routes = false   # don't accept remote gateway routes
    dns_resolution               = true    # allow DNS resolution across
    allow_egress_from_local_cidr = true    # allow egress from local CIDR
  }
}
# add routes in BOTH sides' route tables to the peer's CIDR via the peering conn
```

## 2.6 IPv6 (optional)

```hcl
resource "aws_vpc" "main" {                    # the VPC
  cidr_block              = "10.40.0.0/16"     # the IPv4 CIDR
  assign_generated_ipv6_cidr_block = true   # enables IPv6: AWS gives you an fd00::/8 block
}
# subnets inherit; IGW becomes an egress-only IGW for IPv6 if you don't need inbound
```

## 2.7 Getting the Pieces Right (ordering / gotchas)

- **NAT GW depends on IGW** (and an EIP). Add `depends_on = [aws_internet_gateway.main]` where the reference isn't obvious.
- **Route table associations** can reference subnets before routes exist; that's fine.
- **S3 gateway endpoint** must be attached to route tables that contain the subnets using S3.
- **Interface endpoints** need a **security group** and resolve via **private DNS** (enable `private_dns_enabled`).
- **Public subnet** = `map_public_ip_on_launch = true` **or** a NAT/IGW route. (Both is a common mistake → instances get *two* public-ish paths.)
- **S3 bucket names are global** — never name a bucket after a VPC/subnet pattern.
- **CIDR planning matters**: you can *add* a CIDR block later but can't *shrink* one. Use `cidrsubnet()` so subnets are derived, not hand-typed.

## 2.8 Verifying Your VPC

```bash
aws ec2 describe-vpcs
aws ec2 describe-subnets --filters Name=vpc-id,Values=vpc-xxxx
aws ec2 describe-route-tables
aws ec2 describe-security-groups
aws ec2 describe-vpc-endpoints
aws ec2 describe-nat-gateways
```

## 2.9 Interview Quick Facts

- **SG vs NACL**: stateful/ENI/allow-only vs stateless/subnet/allow+deny.
- **IGW vs NAT**: IGW = internet gateway (bidirectional for public subnets); NAT = egress-only for private subnets.
- **Gateway vs Interface endpoints**: gateway = free, S3/DynamoDB only, route-table-based; interface = ENI, most services, charged, private DNS.
- **1 NAT per AZ** for prod HA.
- **DB subnet = isolated** (no 0.0.0.0/0 route at all).
- VPC peering is **non-transitive** (A↔B, B↔C does not mean A↔C).
- `default_tags` + `cidrsubnet()` + `for_each`/`count` over AZs = the modern VPC module pattern.
