# ======================================================================
#  variables.tf
#  Input variables — the knobs you change (region, names, sizes) without
#  touching the resources. `terraform plan` shows the effect of any change.
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

variable "region_east" {                         # region A (the east endpoint)
  description = "the east region"                # which region the east endpoint lives in
  type        = string                          # a string
  default     = "us-east-1"                     # the default
}

variable "region_west" {                         # region B (the west endpoint)
  description = "the west region"                # which region the west endpoint lives in
  type        = string                          # a string
  default     = "us-west-2"                     # the default
}
