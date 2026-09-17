# ======================================================================
#  variables.tf
#  Input variables — the knobs you change (region, names, sizes) without
#  touching the resources. `terraform plan` shows the effect of any change.
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

variable "region" {                            # the region everything is built in
  description = "the cloud region"             # what this variable controls
  type        = string                        # a string
  default     = "eastus"            # the default (change to your preferred region)
}
