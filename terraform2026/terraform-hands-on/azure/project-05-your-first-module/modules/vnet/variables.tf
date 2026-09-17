# The MODULE's inputs — the root fills these in when it calls us.

variable "name" {                                 # input: the VNet's name
  type = string                                   # a string
}

variable "location" {                              # input: where to build
  type = string                                   # a string
}

variable "resource_group_name" {                   # input: which RG (the module has no RG of its own)
  type = string                                   # a string
}

variable "prefix" {                                 # input: the VNet's address space
  type = string                                   # a CIDR like "10.5.0.0/16"
}

variable "subnets" {                                 # input: which subnets to create
  type = map(string)                               # a map: purpose → CIDR
  default = {                                      # the standard three tiers
    web  = "10.5.1.0/24"                           # frontend tier
    app  = "10.5.2.0/24"                           # backend tier
    data = "10.5.3.0/24"                           # storage/DB tier
  }
}

variable "web_nsg_id" {                                # OPTIONAL input: an NSG to attach to the web subnet
  type     = string                                  # an NSG resource ID (or null)
  default  = null                                    # null = no firewall (the capstone passes one in)
  nullable = true                                    # explicitly allow null
}
