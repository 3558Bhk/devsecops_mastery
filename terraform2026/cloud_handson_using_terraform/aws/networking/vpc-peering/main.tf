# ============================================================================
#  VPC Peering — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

resource "aws_vpc" "a" {                         # VPC A, in us-east-1
  cidr_block = "10.1.0.0/16"                     # its address space (must NOT overlap VPC B)
  tags       = { Name = "vpc-a" }                # a label
}

resource "aws_subnet" "a1" {                     # a subnet so the VPC is usable
  vpc_id            = aws_vpc.a.id               # which VPC
  cidr_block        = "10.1.1.0/24"              # inside VPC A's space
  availability_zone = "us-east-1a"               # which AZ
}

resource "aws_vpc" "b" {                         # VPC B, in us-west-2
  cidr_block = "10.2.0.0/16"                     # its address space (no overlap with A)
  tags       = { Name = "vpc-b" }                # a label
}

resource "aws_subnet" "b1" {                     # a subnet so the VPC is usable
  vpc_id            = aws_vpc.b.id               # which VPC
  cidr_block        = "10.2.1.0/24"              # inside VPC B's space
  availability_zone = "us-west-2a"               # which AZ
}

resource "aws_vpc_peering_connection" "a_to_b" {   # the peering (created in region A)
  vpc_id        = aws_vpc.a.id                     # the local VPC (A)
  peer_vpc_id   = aws_vpc.b.id                     # the remote VPC (B)
  peer_region   = "us-west-2"                      # B lives in this region
  peer_owner_id = data.aws_caller_identity.current.account_id   # B's owner (same account here)

  accepter {                                       # the ACCEPT side (B) — what to do when accepting
    allow_remote_vpc_dns_resolution = true         # let B resolve A's private DNS (and vice versa)
  }

  auto_accept = true                               # same account → accept automatically
}

data "aws_caller_identity" "current" {             # data block: whose account are we (for peer_owner_id)
  # no arguments — returns the account the provider is logged in as
}

resource "aws_route_table" "a_main" {             # VPC A's route table
  vpc_id = aws_vpc.a.id                           # which VPC
  tags   = { Name = "vpc-a-main" }                 # a label
}

resource "aws_route" "a_to_b" {                   # in A: "traffic for 10.2.x → over the peering"
  route_table_id         = aws_route_table.a_main.id   # which table
  destination_cidr_block = "10.2.0.0/16"           # VPC B's space
  vpc_peering_connection_id = aws_vpc_peering_connection.a_to_b.id   # out the peering
}

resource "aws_route_table" "b_main" {             # VPC B's route table (a cross-region reference)
  vpc_id = aws_vpc.b.id                           # which VPC
  tags   = { Name = "vpc-b-main" }                 # a label
}

resource "aws_route" "b_to_a" {                   # in B: "traffic for 10.1.x → over the peering"
  route_table_id         = aws_route_table.b_main.id   # which table
  destination_cidr_block = "10.1.0.0/16"           # VPC A's space
  vpc_peering_connection_id = aws_vpc_peering_connection.a_to_b.id   # out the peering
}
