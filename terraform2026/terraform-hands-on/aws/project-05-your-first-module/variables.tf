variable "project" {                              # root input: the name to give the VPC
  type    = string                                # a string
  default = "mymodule"                            # safe default
}

variable "region" {                                # root input: where to build
  type    = string                                # a string
  default = "us-east-1"                           # default region
}
