variable "project" {                              # variable block: an input the user can set
  type        = string                            # must be a string
  default     = "hello"                           # used when the user doesn't provide a value
  description = "Short name for this project"     # shown by `terraform init` and docs
}

variable "environment" {                          # second input
  type    = string                                # must be a string
  default = "dev"                                 # safe default: dev

  validation {                                    # rule Terraform checks BEFORE running anything
    condition     = contains(["dev", "staging", "prod"], var.environment)   # only these 3 values pass
    error_message = "environment must be one of: dev, staging, prod."       # the error you'll see if it fails
  }
}

variable "versioning" {                            # third input
  type    = bool                                  # true or false
  default = true                                  # versioning on by default (safe)
}
