variable "environment" {                         # which environment this build is for
  type    = string                               # a string
  default = "dev"                                # safe default
}

variable "instance_type" {                        # how big the server is
  type    = string                               # a string
  default = "t4g.micro"                          # smallest ARM instance (free tier friendly)
}

variable "allowed_cidr" {                         # which IP address may SSH into the box
  type        = string                           # a CIDR like "1.2.3.4/32"
  default     = "0.0.0.0/0"                      # DEFAULT IS INSECURE — replace with your own IP!
  description = "Your public IP, e.g. 45.12.8.77/32 (get it: curl ifconfig.co)"   # hint for the user
}
