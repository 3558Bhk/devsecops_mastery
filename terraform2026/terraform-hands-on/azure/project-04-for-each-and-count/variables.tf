variable "vm_count" {                               # input: how many identical VMs to run
  type    = number                                 # a number
  default = 2                                      # two by default (B1s is ~$0.02/hr each)
}

variable "rules" {                                  # input: the firewall rules, as a map of objects
  type = map(object({                               # each value is an object with:
    priority = number                              #   a unique priority (lower = first)
    port     = number                              #   the destination port
  }))                                              #   (names come from the map keys)

  default = {                                      # three rules by default
    ssh   = { priority = 100, port = 22 }          # key "ssh"   → priority 100, port 22
    http  = { priority = 200, port = 80 }          # key "http"  → priority 200, port 80
    https = { priority = 250, port = 443 }         # key "https" → priority 250, port 443
  }
}
