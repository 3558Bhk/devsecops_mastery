variable "project" {                               # input: name prefix
  type    = string                                 # a string
  default = "iot"                                  # keep it short
}

variable "location" {                                # input: where to build
  type    = string                                 # a string
  default = "eastus"                               # a region near you
}

variable "hot_threshold" {                           # input: readings above this land in the blob
  type    = number                                 # a number
  default = 80                                     # e.g. 80 degrees
}
