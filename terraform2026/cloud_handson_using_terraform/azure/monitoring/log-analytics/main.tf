# ============================================================================
#  Log Analytics — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

resource "azurerm_resource_group" "lab" {        # the resource group
  name     = "rg-lab-law"                        # the group's name
  location = var.region      # <- set in variables.tf (the region everything is built in)
}

resource "azurerm_log_analytics_workspace" "lab" {   # the workspace
  name                = "law-lab"                # the workspace's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
  sku                 = "PerGB2018"             # the pricing tier
  retention_in_days   = 30                      # how long logs are kept
}

resource "azurerm_log_analytics_solution" "activity" {   # the solution
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
  solution_name       = "Microsoft-Activity"  # the solution's name
  workspace_name      = azurerm_log_analytics_workspace.lab.name   # which workspace
  workspace_resource_id = azurerm_log_analytics_workspace.lab.id   # the workspace's id

  plan {                                          # the solution's plan (publisher + product)
    publisher = "Microsoft"                       # the publisher
    product   = "OMSGallery/Activity"             # the product (the Activity gallery item)
  }
}
