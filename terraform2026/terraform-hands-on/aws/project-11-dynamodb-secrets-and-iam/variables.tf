variable "project" {                               # input: name prefix
  type    = string                                 # a string
  default = "datalab"                              # default
}

variable "region" {                                 # input: where to build
  type    = string                                 # a string
  default = "us-east-1"                            # default region
}

variable "api_token" {                               # input: a fake token to store as a SecureString
  type      = string                               # a string
  default   = "replace-me-with-a-real-token"       # CHANGE for real use
  sensitive = true                                 # hidden from plan/apply output
}

variable "db_password" {                              # input: the secret to store in Secrets Manager
  type      = string                               # a string
  default   = "replace-me-with-a-real-password"    # CHANGE for real use
  sensitive = true                                 # hidden from plan/apply output
}
