# ============================================================================
#  NAT Gateway — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

resource "aws_vpc" "main" {                      # the VPC
  cidr_block = "10.0.0.0/16"                     # the address space
  tags       = { Name = "nat-lab" }              # a label
}

resource "aws_subnet" "public" {                 # the public subnet (the NAT lives here)
  vpc_id                  = aws_vpc.main.id      # which VPC
  cidr_block              = "10.0.1.0/24"        # inside the VPC
  availability_zone       = "us-east-1a"         # which AZ
  map_public_ip_on_launch = true                 # instances here get public IPs
}

resource "aws_internet_gateway" "igw" {          # the VPC's door to the internet
  vpc_id = aws_vpc.main.id                       # which VPC
  tags   = { Name = "igw" }                      # a label
}

resource "aws_eip" "nat" {                       # the Elastic IP the NAT gateway uses
  domain = "vpc"                                 # a VPC-scoped EIP (NAT requires this)

  depends_on = [aws_internet_gateway.igw]        # create the IGW first (classic ordering gotcha)
}

resource "aws_nat_gateway" "nat" {               # the NAT gateway itself
  allocation_id = aws_eip.nat.id                 # which EIP it owns
  subnet_id     = aws_subnet.public.id           # which PUBLIC subnet it sits in

  tags = { Name = "nat-gw" }                     # a label

  depends_on = [aws_internet_gateway.igw]        # NAT needs the IGW to exist first
}

resource "aws_route_table" "public" {            # the public subnet's route table
  vpc_id = aws_vpc.main.id                       # which VPC
  tags   = { Name = "public-rt" }                # a label
}

resource "aws_route" "public_internet" {         # public subnet → internet
  route_table_id         = aws_route_table.public.id   # which table
  destination_cidr_block = "0.0.0.0/0"             # everything
  gateway_id             = aws_internet_gateway.igw.id # out the IGW
}

resource "aws_route_table_association" "public" {   # wire the public subnet to its table
  subnet_id      = aws_subnet.public.id         # which subnet
  route_table_id = aws_route_table.public.id    # which table
}

resource "aws_subnet" "private" {                # the private subnet
  vpc_id            = aws_vpc.main.id            # which VPC
  cidr_block        = "10.0.2.0/24"              # inside the VPC
  availability_zone = "us-east-1a"               # same AZ as the NAT (cheap)
}

resource "aws_route_table" "private" {           # the private subnet's route table
  vpc_id = aws_vpc.main.id                       # which VPC
  tags   = { Name = "private-rt" }               # a label
}

resource "aws_route" "private_nat" {             # THE KEY ROUTE: private → out via NAT
  route_table_id         = aws_route_table.private.id   # which table
  destination_cidr_block = "0.0.0.0/0"             # everything
  nat_gateway_id         = aws_nat_gateway.nat.id      # out the NAT (no IGW!)
}

resource "aws_route_table_association" "private" {   # wire the private subnet to its table
  subnet_id      = aws_subnet.private.id        # which subnet
  route_table_id = aws_route_table.private.id   # which table
}
