# The MODULE's outputs — the root reads these as module.vpc.<name>.

output "vpc_id" {                                 # the VPC's ID
  value = aws_vpc.this.id                         # straight from the resource
}

output "subnet_ids" {                             # both subnets' IDs, as a list
  value = values(aws_subnet.public)               # values() flattens the for_each map → list of IDs
}

output "internet_gateway_id" {                    # the internet gateway's ID
  value = aws_internet_gateway.this.id            # straight from the resource
}
