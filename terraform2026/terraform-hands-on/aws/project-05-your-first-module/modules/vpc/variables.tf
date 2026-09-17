# The MODULE's inputs — the root fills these in when it calls us.

variable "name" {                                 # input: what to name the VPC (and label subnets)
  type = string                                   # a string
}

variable "cidr_block" {                            # input: the VPC's IPv4 address space
  type        = string                            # a CIDR like "10.0.0.0/16"
  description = "The VPC address space"           # shown in docs
  # no default on purpose: force the caller to decide (a module shouldn't guess networking)
}
