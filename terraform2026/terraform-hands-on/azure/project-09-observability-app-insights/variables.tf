variable "project" {                               # input: name prefix
  type    = string                                 # a string
  default = "obs"                                  # keep it short
}

variable "location" {                                # input: where to build
  type    = string                                 # a string
  default = "eastus"                               # a region
}

variable "alert_email" {                             # input: who gets paged
  type    = string                                 # an email (or "" to skip the action group)
  default = ""                                     # empty = alert has no notification target
}
