terraform {                                      # the terraform block: settings about Terraform itself
  required_version = ">= 1.5"                    # minimum Terraform version

  required_providers {                           # the providers this project needs
    azurerm = {                                  # the Azure provider
      source  = "hashicorp/azurerm"              # where to download it
      version = "~> 5.0"                         # any 5.x, never 6.x (pin the major)
    }
  }
}

provider "azurerm" {                             # configure the Azure provider
  # no auth settings here: it picks up your `az login` session automatically (azure_auth)

  features {}                                    # REQUIRED in azurerm v5: an empty block is fine to start
                                                 # (it's where per-resource-type behavior tweaks go)
}

resource "azurerm_resource_group" "first" {      # the resource group: a container that holds resources
  name     = "tf-lab-rg-2026"                    # the group's name
  location = "eastus"                            # where it lives (resources will live here too)
  tags = {                                        # key-value labels
    Purpose = "learning"                         # what it's for
  }
}

resource "azurerm_storage_account" "first" {     # the storage account: holds blobs, tables, queues
  name                     = "tflabstorage2026"  # globally unique: 3–24 lowercase letters/numbers, NO hyphens
  resource_group_name      = azurerm_resource_group.first.name   # which group it lives in
  location                 = azurerm_resource_group.first.location   # same location as the group (cheap + consistent)
  account_tier             = "Standard"          # performance tier (Standard or Premium)
  account_replication_type = "LRS"               # LRS = locally redundant (1 copy in the region; RRA/RGZ cost more)
}
