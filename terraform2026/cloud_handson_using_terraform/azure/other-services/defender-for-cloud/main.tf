# ============================================================================
#  Defender for Cloud — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

resource "azurerm_resource_group" "lab" {        # the resource group
  name     = "rg-lab-defender"                   # the group's name
  location = var.region      # <- set in variables.tf (the region everything is built in)
}

resource "azurerm_security_center_subscription_pricing" "lab" {   # the subscription's tier
  tier = "Standard"                              # the tier (Free / Standard)
}

resource "azurerm_log_analytics_workspace" "lab" {   # the workspace
  name                = "law-defender"          # the workspace's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
  sku                 = "PerGB2018"             # the pricing tier
  retention_in_days   = 30                      # how long to keep
}

resource "random_string" "suffix" {              # a random suffix for the account name
  length  = 8                                    # 8 characters
  special = false                                # no special chars
  lower = true                               # lowercase only
}

resource "azurerm_storage_account" "protected" {   # the storage account
  name                = "stordef${random_string.suffix.result}"   # a unique name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
  account_tier            = "Standard"          # the tier
  account_replication_type = "LRS"              # the replication
  https_traffic_only_enabled = true             # force HTTPS
  min_tls_version         = "TLS1_2"            # the minimum TLS version
}

resource "azurerm_security_center_storage_defender" "lab" {   # the Storage Defender plan
  storage_account_id  = azurerm_storage_account.protected.id   # which storage account
}
