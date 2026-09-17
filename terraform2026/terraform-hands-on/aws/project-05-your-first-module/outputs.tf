output "vpc_id" {                                 # root output: the VPC's ID (read from the module)
  value       = module.vpc.vpc_id                 # module.vpc = this call, .vpc_id = the module's output
  description = "The VPC created by the module"   # what the value is
}

output "subnet_ids" {                             # root output: both subnets' IDs
  value       = module.vpc.subnet_ids             # a list coming out of the module
  description = "Public subnets (one per AZ)"     # used by the capstone later
}

output "internet_gateway_id" {                    # root output: the IGW's ID
  value       = module.vpc.internet_gateway_id    # from the module
  description = "The internet gateway of the VPC" # for lookups and debugging
}
