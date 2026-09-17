variable "project" {                                # input: name prefix
  type    = string                                  # a string
  default = "clicklab"                              # becomes part of every name
}

variable "region" {                                  # input: where to build
  type    = string                                  # a string
  default = "us-east-1"                             # a region
}

variable "alert_email" {                             # input: where "new minute file" notifications go
  type    = string                                  # a string
  default = ""                                      # your email, or "" to skip the subscription
}
