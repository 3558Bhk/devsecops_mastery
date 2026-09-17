variable "project" {                               # input: prefix for every resource name
  type    = string                                 # a string
  default = "capstone"                             # e.g. "capstone" → capstone-alb, capstone-db...
}

variable "instance_type" {                          # input: web server size
  type    = string                                 # a string
  default = "t4g.micro"                            # keep it the smallest
}

variable "db_username" {                             # input: the DB admin user
  type    = string                                 # a string
  default = "admin"                                # the username
}

variable "db_password" {                             # input: the DB admin password
  type      = string                               # a string
  default   = "CHANGE-ME"                          # CHANGE THIS for any real use
  sensitive = true                                 # hides it from plan/apply output
}

variable "db_name" {                                 # input: the initial database name
  type    = string                                 # a string
  default = "appdb"                                # created automatically with the instance
}
