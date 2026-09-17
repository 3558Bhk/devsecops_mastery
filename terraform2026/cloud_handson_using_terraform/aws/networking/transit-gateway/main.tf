# ============================================================================
#  Transit Gateway — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

resource "aws_ec2_transit_gateway" "hub" {       # the transit gateway (the hub)
  description = "lab hub"                        # a human label
  dns_support = "enable"                         # allow DNS resolution between attached VPCs
  # default_route_table_association/propagation default to "enable":
  # every new attachment joins the default route table automatically
}

resource "aws_vpc" "spoke1" {                    # VPC 1
  cidr_block = "10.1.0.0/16"                     # its space (no overlap with spoke2)
  tags       = { Name = "spoke-1" }              # a label
}

resource "aws_subnet" "spoke1a" {                # subnet in AZ a
  vpc_id            = aws_vpc.spoke1.id          # which VPC
  cidr_block        = "10.1.1.0/24"              # inside the VPC
  availability_zone = "us-east-1a"               # which AZ
}

resource "aws_subnet" "spoke1b" {                # subnet in AZ b
  vpc_id            = aws_vpc.spoke1.id          # which VPC
  cidr_block        = "10.1.2.0/24"              # inside the VPC
  availability_zone = "us-east-1b"               # which AZ
}

resource "aws_route_table" "spoke1" {            # spoke 1's route table
  vpc_id = aws_vpc.spoke1.id                     # which VPC
  tags   = { Name = "spoke-1" }                   # a label
}

resource "aws_route" "spoke1_to_tgw" {           # "anything not in 10.1.x → the hub"
  route_table_id         = aws_route_table.spoke1.id   # which table
  destination_cidr_block = "0.0.0.0/0"             # the whole world (hub decides)
  transit_gateway_id     = aws_ec2_transit_gateway.hub.id   # out the hub
}

resource "aws_vpc" "spoke2" {                    # VPC 2
  cidr_block = "10.2.0.0/16"                     # its space
  tags       = { Name = "spoke-2" }              # a label
}

resource "aws_subnet" "spoke2a" {                # subnet in AZ a
  vpc_id            = aws_vpc.spoke2.id          # which VPC
  cidr_block        = "10.2.1.0/24"              # inside the VPC
  availability_zone = "us-east-1a"               # which AZ
}

resource "aws_subnet" "spoke2b" {                # subnet in AZ b
  vpc_id            = aws_vpc.spoke2.id          # which VPC
  cidr_block        = "10.2.2.0/24"              # inside the VPC
  availability_zone = "us-east-1b"               # which AZ
}

resource "aws_route_table" "spoke2" {            # spoke 2's route table
  vpc_id = aws_vpc.spoke2.id                     # which VPC
  tags   = { Name = "spoke-2" }                   # a label
}

resource "aws_route" "spoke2_to_tgw" {           # "anything not in 10.2.x → the hub"
  route_table_id         = aws_route_table.spoke2.id   # which table
  destination_cidr_block = "0.0.0.0/0"             # the whole world (hub decides)
  transit_gateway_id     = aws_ec2_transit_gateway.hub.id   # out the hub
}

resource "aws_ec2_transit_gateway_vpc_attachment" "spoke1" {   # attach VPC 1 to the hub
  transit_gateway_id = aws_ec2_transit_gateway.hub.id   # which hub
  vpc_id             = aws_vpc.spoke1.id                # which VPC
  subnet_ids         = [aws_subnet.spoke1a.id, aws_subnet.spoke1b.id]   # the subnets the hub uses (≥2 AZs)
}

resource "aws_ec2_transit_gateway_vpc_attachment" "spoke2" {   # attach VPC 2 to the hub
  transit_gateway_id = aws_ec2_transit_gateway.hub.id   # which hub
  vpc_id             = aws_vpc.spoke2.id                # which VPC
  subnet_ids         = [aws_subnet.spoke2a.id, aws_subnet.spoke2b.id]   # the subnets the hub uses
}
