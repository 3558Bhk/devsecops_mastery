terraform {                                      # the terraform block (backend lives here, not in main.tf)
  backend "azurerm" {                            # use the Azure Storage backend
    storage_account_name = "tflabstate2026"     # the account from 00-bootstrap — must match exactly
    container_name       = "tfstate"             # the container from 00-bootstrap — must match exactly
    key                  = "dev/terraform.tfstate"   # the "file" inside the container; "dev/" = one state per environment
    sas_token            = "PASTE-YOUR-SAS-TOKEN-HERE"   # from `az storage container generate-sas` (includes the leading ?)
  }
}
