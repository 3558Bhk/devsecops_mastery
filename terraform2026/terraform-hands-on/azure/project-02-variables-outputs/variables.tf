variable "project" {                               # input: your project name (goes into all names)
  type    = string                                 # a string
  default = "hello"                                # safe default
}

variable "environment" {                            # input: which environment
  type    = string                                 # a string
  default = "dev"                                  # safe default

  validation {                                      # rule checked before anything runs
    condition     = contains(["dev", "staging", "prod"], var.environment)   # only these three
    error_message = "environment must be one of: dev, staging, prod."       # the error shown on failure
  }
}

variable "location" {                                # input: where to build
  type    = string                                 # a string
  default = "eastus"                               # a region close to most users
}

variable "replication" {                              # input: how many copies of the data
  type    = string                                 # a string
  default = "LRS"                                  # LRS = cheapest, one availability zone
  # options: LRS, ZRS, RAGRS, RA-GRS (each costs more)
}

variable "containers" {                               # input: which blob containers to create
  type    = list(string)                           # a list of strings
  default = ["web", "uploads"]                     # two containers by default
}
