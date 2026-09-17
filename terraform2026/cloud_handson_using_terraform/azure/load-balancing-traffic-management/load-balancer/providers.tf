# ======================================================================
#  providers.tf
#  Terraform settings (required_providers) + provider configuration —
#  "which providers, which versions, and how Terraform logs in to each cloud."
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"   # the Azure provider
      version = "~> 5.0"              # pin a major version
    }
  }
}

provider "azurerm" {
  features {}                        # v5: an empty features block is still required
}
