variable "project" {                               # input: prefix for every resource name
  type    = string                                 # a string
  default = "capst"                                # keep it SHORT: SQL/vault names have length limits
}

variable "location" {                                # input: where to build
  type    = string                                 # a string
  default = "eastus"                               # a region
}

variable "sql_password" {                             # input: the SQL admin password
  type      = string                               # a string
  default   = "Capstone-12345!"                    # CHANGE THIS for any real use
  sensitive = true                                 # hidden from plan/apply output
}

variable "admin_password" {                           # input: the VM admin password
  type      = string                               # a string
  default   = "Capstone-12345!"                    # CHANGE THIS for any real use
  sensitive = true                                 # hidden from plan/apply output
}
