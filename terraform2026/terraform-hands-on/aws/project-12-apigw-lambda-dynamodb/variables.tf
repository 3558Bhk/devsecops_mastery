variable "project" {                               # input: name prefix
  type    = string                                 # a string
  default = "ordersapi"                            # becomes part of every name
}

variable "region" {                                  # input: where to build
  type    = string                                 # a string
  default = "us-east-1"                            # a region
}
