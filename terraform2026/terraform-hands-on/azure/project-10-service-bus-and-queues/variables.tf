variable "project" {                               # input: name prefix
  type    = string                                 # a string
  default = "msg"                                  # keep it short
}

variable "location" {                                # input: where to build
  type    = string                                 # a string
  default = "eastus"                               # a region
}
