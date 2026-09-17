# CHILD MODULE: a reusable VPC.
# Note there is NO terraform {} or provider {} block here — the root config supplies them.

data "aws_availability_zones" "available" {       # data block: read the AZs we can create in
  state = "available"                             # only AZs that accept new resources
}

locals {                                          # local values: computed once, reused
  az_count = 2                                    # how many AZs to use (a VPC needs 2 for an ALB later)
}

resource "aws_vpc" "this" {                       # the VPC itself
  cidr_block           = var.cidr_block          # address space from the module input
  enable_dns_support   = true                    # resolve hostnames inside the VPC
  enable_dns_hostnames = true                    # give instances a DNS name too
  tags                 = { Name = var.name }     # label from the module input
}

resource "aws_internet_gateway" "this" {          # the internet gateway: the VPC's door to the internet
  vpc_id = aws_vpc.this.id                        # attach it to this VPC
}

resource "aws_route_table" "public" {             # the route table: "where does traffic go?"
  vpc_id = aws_vpc.this.id                        # belongs to this VPC

  route {                                          # one route entry
    cidr_block = "0.0.0.0/0"                       # destination: anywhere on the internet
    gateway_id = aws_internet_gateway.this.id      # send it through the internet gateway
  }
}

resource "aws_subnet" "public" {                  # ONE block, but one public subnet PER AZ (count over the AZs)
  count                   = local.az_count        # run this block N times (N AZs)
  vpc_id                  = aws_vpc.this.id       # inside this VPC
  cidr_block              = cidrsubnet(var.cidr_block, 8, count.index)   # carve /24s: 10.0.0.0/24, 10.0.1.0/24
  availability_zone       = data.aws_availability_zones.available.names[count.index]   # this subnet lives in this AZ
  map_public_ip_on_launch = true                  # instances here automatically get a public IP
  tags                    = { Name = "${var.name}-public-${count.index}" }   # label per subnet
}

resource "aws_route_table_association" "public" { # tie each subnet to the public route table
  for_each = aws_subnet.public                    # one association per subnet
  subnet_id      = each.value.id                  # this subnet
  route_table_id = aws_route_table.public.id      # using the public routes
}
