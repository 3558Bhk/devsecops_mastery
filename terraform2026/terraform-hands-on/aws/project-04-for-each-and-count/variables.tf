variable "environments" {                         # the list of environments to build
  type    = list(string)                          # a list of strings
  default = ["dev", "staging", "prod"]            # build three by default
}

variable "instance_count" {                        # how many worker instances to run
  type    = number                                # a number
  default = 1                                     # one by default (cheap!)
}
