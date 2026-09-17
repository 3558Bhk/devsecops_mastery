terraform {                                      # the terraform block: settings about Terraform itself
  required_version = ">= 1.5"                    # minimum Terraform version
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 5.0" }   # Azure provider, any 5.x
  }
}

provider "azurerm" {                             # configure the Azure provider
  features {}                                    # required in v5
}

resource "azurerm_resource_group" "state" {      # the RG for the state storage account
  name     = "tf-state-rg"                       # the group's name
  location = "eastus"                            # the region
}

resource "azurerm_storage_account" "state" {     # the storage account that will STORE the state
  name                     = "tflabstate2026"    # globally unique, lowercase, no hyphens
  resource_group_name      = azurerm_resource_group.state.name   # which group
  location                 = azurerm_resource_group.state.location   # same location
  account_tier             = "Standard"          # performance tier
  account_replication_type = "LRS"               # cheapest replication
}

resource "azurerm_storage_container" "state" {   # the container: the "folder" for state files
  name      = "tfstate"                          # the container's name
  storage_account_id = azurerm_storage_account.state.id   # which account
}
