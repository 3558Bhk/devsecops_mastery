variable "project" {                               # input: name prefix
  type    = string                                 # a string
  default = "func"                                 # keep it short (storage names are length-limited)
}

variable "location" {                                # input: where to build
  type    = string                                 # a string
  default = "eastus"                               # a region near you
}
