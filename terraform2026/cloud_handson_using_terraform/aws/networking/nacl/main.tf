# ============================================================================
#  NACL — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

resource "aws_vpc" "main" {                      # the VPC NACLs attach to
  cidr_block = "10.0.0.0/16"                     # the address space
  tags       = { Name = "nacl-lab" }             # a label
}

resource "aws_subnet" "edge" {                   # a subnet the NACL will guard
  vpc_id            = aws_vpc.main.id            # which VPC
  cidr_block        = "10.0.1.0/24"              # inside the VPC
  availability_zone = "us-east-1a"               # which AZ
}

resource "aws_network_acl" "edge" {              # the NACL itself (one per VPC/subnet-guard)
  vpc_id = aws_vpc.main.id                       # which VPC
  tags   = { Name = "edge-nacl" }                # a label

  # default behavior of a brand-new NACL: ALLOW everything (each direction).
  # We replace that with explicit numbered rules below — remember: unnumbered = DENY.

  ingress {                                       # rule 100: allow ICMP (ping) in from the VPC
    rule_no    = 100                              # the priority (lower = evaluated first)
    action     = "allow"                            # allow (explicit — NACL default is deny-all anyway)
    protocol   = "1"                              # protocol 1 = ICMP
    from_port  = 0                                # NACLs use 0 for "any port"
    to_port    = 0                                # 0
    cidr_block = "10.0.0.0/16"                    # from within the VPC
  }

  ingress {                                       # rule 110: allow inbound ephemeral ports (RETURN traffic — stateless!)
    rule_no    = 110                              # the priority
    action     = "allow"                            # allow (explicit — NACL default is deny-all anyway)
    protocol   = "6"                              # protocol 6 = TCP
    from_port  = 1024                             # ephemeral ports start here
    to_port    = 65535                            # ...and end here
    cidr_block = "10.0.0.0/16"                    # from the VPC
  }

  egress {                                        # rule 100: allow outbound web traffic
    rule_no    = 100                              # the priority
    action     = "allow"                            # allow (explicit — NACL default is deny-all anyway)
    protocol   = "6"                              # TCP
    from_port  = 80                               # HTTP
    to_port    = 443                              # ...to HTTPS
    cidr_block = "0.0.0.0/0"                      # to anywhere
  }

  egress {                                        # rule 110: allow outbound ephemeral ports (so RETURN traffic can leave)
    rule_no    = 110                              # the priority
    action     = "allow"                            # allow (explicit — NACL default is deny-all anyway)
    protocol   = "6"                              # TCP
    from_port  = 1024                             # ephemeral range
    to_port    = 65535                            # ephemeral range
    cidr_block = "0.0.0.0/0"                      # to anywhere
  }
}

resource "aws_network_acl_association" "edge" {   # the wiring
  subnet_id     = aws_subnet.edge.id             # which subnet
  network_acl_id = aws_network_acl.edge.id        # which NACL
}
