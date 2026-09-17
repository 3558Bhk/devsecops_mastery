variable "location" {                               # input: where everything is built
  type    = string                                 # a string
  default = "eastus"                               # a region
}

variable "vm_size" {                                 # input: how big the VM is
  type    = string                                 # a string
  default = "Standard_B1s"                         # burstable micro (cheapest that's always free-eligible)
}

variable "admin_username" {                           # input: the local admin user
  type    = string                                 # a string
  default = "adminuser"                            # can't be "admin", "root", "azureuser"... (Azure blocks common ones)
}

variable "admin_password" {                           # input: the admin password
  type      = string                               # a string
  sensitive = true                                 # hidden from plan/apply output
  validation {                                      # Azure's minimum password rules
    condition     = length(var.admin_password) >= 12   # at least 12 characters
    error_message = "admin_password must be at least 12 characters."   # the error shown
  }
  # NOTE: for real systems use an SSH key (admin_ssh_key), not a password
}
