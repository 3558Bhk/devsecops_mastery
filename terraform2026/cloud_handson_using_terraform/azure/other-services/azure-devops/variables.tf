# ======================================================================
#  variables.tf
#  Input variables — the knobs you change (region, names, sizes) without
#  touching the resources. `terraform plan` shows the effect of any change.
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

variable "org_service_url" {                   # the Azure DevOps organization
  description = "the org URL (https://dev.azure.com/<your-org>)"   # which org Terraform talks to
  type        = string                        # a string
  default     = "https://dev.azure.com/your-org"   # DUMMY — change to your org
}
