variable "project" {                                # input: name prefix
  type    = string                                  # a string
  default = "orderflow"                             # becomes part of every name
}

variable "region" {                                  # input: where to build
  type    = string                                  # a string
  default = "us-east-1"                             # a region
}

variable "big_order_threshold" {                     # input: orders above this amount get flagged
  type    = number                                  # a number
  default = 1000                                    # e.g. $1000
}
