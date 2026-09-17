variable "project" {                               # input: prefix for resource names
  type    = string                                 # a string
  default = "kvl"                                  # keep it SHORT: vault names max out at 24 chars
}

variable "environment" {                            # input: which environment
  type    = string                                 # a string
  default = "dev"                                  # safe default
}

variable "location" {                                # input: where to build
  type    = string                                 # a string
  default = "eastus"                               # a region
}

variable "secret_value" {                             # input: the secret to store
  type      = string                               # a string
  default   = "dev-api-key-123"                    # a fake value for the lab
  sensitive = true                                 # hidden from plan/apply output
}
