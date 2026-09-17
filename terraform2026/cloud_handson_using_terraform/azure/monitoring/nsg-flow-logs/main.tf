# ============================================================================
#  NSG Flow Logs — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

resource "azurerm_resource_group" "lab" {        # the resource group
  name     = "rg-lab-flowlog"                    # the group's name
  location = var.region      # <- set in variables.tf (the region everything is built in)
}

resource "azurerm_virtual_network" "lab" {       # the VNet
  name                = "vnet-flowlog"           # the VNet's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
  address_space       = ["10.16.0.0/16"]         # the IP space
}

resource "azurerm_subnet" "app" {                # the subnet
  name                 = "subnet-flowlog"        # the subnet's name
  resource_group_name  = azurerm_resource_group.lab.name   # which RG
  virtual_network_name = azurerm_virtual_network.lab.name  # which VNet
  address_prefixes     = ["10.16.1.0/24"]        # the slice
}

resource "azurerm_network_security_group" "app" {   # the NSG (the flow-log target)
  name                = "nsg-flowlog"            # the NSG's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
}

resource "azurerm_subnet_network_security_group_association" "app" {   # attach the NSG to the subnet
  subnet_id                 = azurerm_subnet.app.id             # which subnet
  network_security_group_id = azurerm_network_security_group.app.id   # which NSG
}

resource "random_string" "suffix" {              # a random suffix for the storage account
  length  = 8                                    # 8 characters
  special = false                                # no special chars
  lower = true                               # lowercase only
}

resource "azurerm_storage_account" "flow" {      # the storage account (raw flow logs)
  name                = "storflow${random_string.suffix.result}"   # a unique name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
  account_tier            = "Standard"          # the tier
  account_replication_type = "LRS"              # the replication
  https_traffic_only_enabled = true             # force HTTPS
  min_tls_version         = "TLS1_2"            # the minimum TLS version
}

resource "azurerm_log_analytics_workspace" "lab" {   # the workspace (for traffic analytics)
  name                = "law-flowlog"           # the workspace's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
  sku                 = "PerGB2018"             # the pricing tier
  retention_in_days   = 30                      # how long to keep
}

resource "azurerm_network_watcher" "lab" {       # the network watcher (required by flow logs)
  name                = "nw-lab"                 # the watcher's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
}

resource "azurerm_network_watcher_flow_log" "lab" {   # the flow log
  name                = "flowlog-lab"           # the flow log's name
  network_watcher_name = azurerm_network_watcher.lab.name   # which network watcher
  resource_group_name = azurerm_resource_group.lab.name   # which RG
  enabled             = true                     # the flow log is on

  storage_account_id  = azurerm_storage_account.flow.id   # where the raw logs go
  target_resource_id  = azurerm_network_security_group.app.id   # the NSG to log

  retention_policy {                            # how long to keep the raw logs
    days    = 7                                 # 7 days
    enabled = true                              # retention on
  }

  traffic_analytics {                           # the aggregated analytics (in Log Analytics)
    enabled             = true                  # analytics on
    interval_in_minutes = 60                    # aggregate every 60 minutes
    workspace_id        = azurerm_log_analytics_workspace.lab.id   # the workspace
    workspace_region    = azurerm_resource_group.lab.location   # the workspace's region
    workspace_resource_id = azurerm_log_analytics_workspace.lab.id   # the workspace's id
  }
}
