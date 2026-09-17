variable "project" {                               # input: name prefix
  type    = string                                 # a string
  default = "alarmlab"                             # default
}

variable "region" {                                 # input: where to build
  type    = string                                 # a string
  default = "us-east-1"                            # default region
}

variable "alarm_email" {                             # OPTIONAL: where alarm emails go
  type    = string                                 # an email address (or "" to skip)
  default = ""                                     # empty = no email subscription created
}
