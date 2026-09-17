# ============================================================================
#  VPC Endpoints — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

resource "aws_vpc" "main" {                      # the VPC the endpoints live in
  cidr_block = "10.0.0.0/16"                     # the address space
  tags       = { Name = "endpoint-lab" }         # a label
}

resource "aws_subnet" "a" {                      # subnet A
  vpc_id            = aws_vpc.main.id            # which VPC
  cidr_block        = "10.0.1.0/24"              # inside the VPC
  availability_zone = "us-east-1a"               # which AZ
}

resource "aws_subnet" "b" {                      # subnet B
  vpc_id            = aws_vpc.main.id            # which VPC
  cidr_block        = "10.0.2.0/24"              # inside the VPC
  availability_zone = "us-east-1b"               # which AZ
}

resource "aws_route_table" "main" {              # the route table the subnets use
  vpc_id = aws_vpc.main.id                       # which VPC
  tags   = { Name = "main-rt" }                  # a label
}

resource "aws_route_table_association" "a" {     # subnet A → the table
  subnet_id      = aws_subnet.a.id              # which subnet
  route_table_id = aws_route_table.main.id      # which table
}

resource "aws_route_table_association" "b" {     # subnet B → the table
  subnet_id      = aws_subnet.b.id              # which subnet
  route_table_id = aws_route_table.main.id      # which table
}

resource "aws_vpc_endpoint" "s3" {               # the S3 gateway endpoint
  vpc_id       = aws_vpc.main.id                 # which VPC
  service_name = "com.amazonaws.us-east-1.s3"    # the S3 service (region-specific!)
  vpc_endpoint_type = "Gateway"                  # the type: Gateway (vs Interface)

  route_table_ids = [aws_route_table.main.id]    # which route tables get the S3 route
}

resource "aws_vpc_endpoint" "dynamodb" {         # the DynamoDB gateway endpoint
  vpc_id       = aws_vpc.main.id                 # which VPC
  service_name = "com.amazonaws.us-east-1.dynamodb"   # the DynamoDB service (region-specific!)
  vpc_endpoint_type = "Gateway"                  # the type: Gateway

  route_table_ids = [aws_route_table.main.id]    # which route tables get the DDB route
}
