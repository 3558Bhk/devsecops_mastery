variable "project" {                               # input: name prefix
  type    = string                                 # a string
  default = "apim"                                 # keep it short
}

variable "location" {                                # input: where to build
  type    = string                                 # a string
  default = "eastus"                               # a region near you
}

variable "rate_limit_calls" {                        # input: max calls per client per renewal period
  type    = number                                 # a number
  default = 10                                     # e.g. 10
}

variable "rate_limit_seconds" {                      # input: the renewal period (seconds)
  type    = number                                 # a number
  default = 1                                      # e.g. 1 second
}
