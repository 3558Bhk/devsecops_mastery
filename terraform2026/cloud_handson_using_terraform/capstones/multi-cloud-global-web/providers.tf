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
    aws     = { source = "hashicorp/aws",     version = "~> 5.0" }   # AWS provider
    azurerm = { source = "hashicorp/azurerm", version = "~> 5.0" }   # Azure provider
  }
}

provider "aws" {                                 # configure the AWS provider
  region = "us-east-1"                           # where the AWS side lives
}

provider "azurerm" {                             # configure the Azure provider
  features {}                                     # empty features block (required)
}
