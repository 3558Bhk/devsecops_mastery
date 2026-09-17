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
    azuredevops = { source = "microsoft/azuredevops", version = "~> 1.1" }   # the Azure DevOps provider
  }
}

provider "azuredevops" {
  org_service_url     = var.org_service_url                # the org's URL (set in variables.tf)
  personal_access_token = "your-pat"                        # a PAT with the right scopes (CHANGE)
}
