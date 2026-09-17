variable "project" {                               # input: name prefix
  type    = string                                 # a string
  default = "cosmos"                               # keep it short
}

variable "location" {                                # input: where to build
  type    = string                                 # a string
  default = "eastus"                               # a region
}

variable "db_password" {                              # input: the password to store in the vault
  type      = string                               # a string
  default   = "Cosmos-12345!"                      # CHANGE for real use
  sensitive = true                                 # hidden from plan/apply output
}
