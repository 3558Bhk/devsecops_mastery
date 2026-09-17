variable "project" {                               # input: name prefix
  type    = string                                 # a string
  default = "msglab"                               # default
}

variable "region" {                                 # input: where to build
  type    = string                                 # a string
  default = "us-east-1"                            # default region
}
