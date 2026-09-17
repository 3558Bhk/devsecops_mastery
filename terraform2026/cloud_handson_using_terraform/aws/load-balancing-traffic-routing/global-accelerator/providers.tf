# ======================================================================
#  providers.tf
#  Terraform settings (required_providers) + provider configuration —
#  "which providers, which versions, and how Terraform logs in to each cloud."
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

terraform {                                      # the terraform block: Terraform-level settings
  required_version = ">= 1.5"                    # minimum Terraform version
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }   # AWS provider, any 5.x
  }
}

provider "aws" {
  alias  = "east"                                # the alias (so we can have two regions)
  region = var.region_east                     # region A (set in variables.tf)
}

provider "aws" {
  alias  = "west"                                # the alias
  region = var.region_west                     # region B (set in variables.tf)
}
