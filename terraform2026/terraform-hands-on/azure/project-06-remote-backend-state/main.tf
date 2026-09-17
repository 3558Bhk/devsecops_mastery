terraform {                                      # the terraform block: settings about Terraform itself
  required_version = ">= 1.5"                    # minimum Terraform version
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 5.0" }   # Azure provider, any 5.x
  }
}

provider "azurerm" {                             # configure the Azure provider
  features {}                                    # required in v5
}

resource "azurerm_resource_group" "app" {       # the RG for the "real" project
  name     = "tf-state-project-rg"               # the group's name
  location = "eastus"                            # the region
}

resource "azurerm_storage_account" "main" {     # the project's storage account
  name                     = "tflabproject2026"  # globally unique name
  resource_group_name      = azurerm_resource_group.app.name   # which group
  location                 = azurerm_resource_group.app.location   # same location
  account_tier             = "Standard"          # performance tier
  account_replication_type = "LRS"               # cheapest replication
  tags                     = { project = "state-lab" }   # a label
}

# "Import slot": declared with the FULL values of the account you create in the portal,
# so that after `terraform import` Terraform sees NO drift (name/location/tier must match exactly).
resource "azurerm_storage_account" "legacy" {   # the account you create in the portal first
  name                     = "tflablegacy2026"  # create THIS exact name in the portal (globally unique)
  resource_group_name      = azurerm_resource_group.app.name   # same group this project uses
  location                 = azurerm_resource_group.app.location   # same location (eastus)
  account_tier             = "Standard"          # pick "Standard" in the portal
  account_replication_type = "LRS"               # pick "LRS" in the portal
}
