terraform {                                      # the terraform block: settings about Terraform itself
  required_version = ">= 1.5"                    # minimum Terraform version
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 5.0" }   # Azure provider, any 5.x
  }
}

provider "azurerm" {                             # configure the Azure provider
  features {}                                    # required in v5 (empty is fine to start)
}

locals {                                          # local values: computed, NOT user input
  account_name = replace(lower("${var.project}-${var.environment}"), "-", "")   # strip hyphens: storage names can't have them
  tags         = {                               # tags shared by every resource below
    project     = var.project                    # which project
    environment = var.environment                # which environment
  }
}

resource "azurerm_resource_group" "app" {        # the resource group: container for everything
  name     = "${local.account_name}-rg"          # derived from the local (lowercase, no hyphens is fine for RGs)
  location = var.location                        # from the input
  tags     = local.tags                          # the shared tags
}

resource "azurerm_storage_account" "app" {       # the storage account
  name                     = local.account_name                      # the derived global name
  resource_group_name      = azurerm_resource_group.app.name         # which group
  location                 = azurerm_resource_group.app.location     # same location as the group
  account_tier             = "Standard"                              # performance tier
  account_replication_type = var.replication                         # from the input (LRS by default)
  tags                     = local.tags                              # the shared tags
}

resource "azurerm_storage_container" "app" {     # ONE block, but one container PER name in the list
  for_each = toset(var.containers)               # loop over the container names (toset: set of strings)
  name     = each.value                          # each.value = the current name ("web", "uploads")
  storage_account_id = azurerm_storage_account.app.id   # which account it lives in (referenced by ID)
  container_access_type = "private"              # private (default and safest)
}
