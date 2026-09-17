# ============================================================================
#  Hub & Spoke — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

resource "azurerm_resource_group" "lab" {        # the resource group
  name     = "rg-lab-hubspoke"                   # the group's name
  location = var.region      # <- set in variables.tf (the region everything is built in)
}

resource "azurerm_virtual_network" "hub" {       # the hub VNet
  name                = "vnet-hub"               # the hub's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
  address_space       = ["10.0.0.0/16"]          # the hub's IP space
}

resource "azurerm_subnet" "hub_gw" {             # the vNet gateway subnet (special: for VPN/ER)
  name                 = "vnet-gateway-subnet"   # the conventional name
  resource_group_name  = azurerm_resource_group.lab.name   # which RG
  virtual_network_name = azurerm_virtual_network.hub.name  # which VNet
  address_prefixes     = ["10.0.0.0/24"]         # a /24 reserved for the gateway
}

resource "azurerm_subnet" "hub_common" {         # a general hub subnet
  name                 = "subnet-hub"            # the subnet's name
  resource_group_name  = azurerm_resource_group.lab.name   # which RG
  virtual_network_name = azurerm_virtual_network.hub.name  # which VNet
  address_prefixes     = ["10.0.1.0/24"]         # the slice
}

resource "azurerm_virtual_network" "spoke_a" {   # spoke VNet A
  name                = "vnet-spoke-a"           # the spoke's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
  address_space       = ["10.1.0.0/16"]          # the spoke's IP space (no overlap)
}

resource "azurerm_subnet" "spoke_a" {            # spoke A's subnet
  name                 = "subnet-spoke-a"        # the subnet's name
  resource_group_name  = azurerm_resource_group.lab.name   # which RG
  virtual_network_name = azurerm_virtual_network.spoke_a.name   # which VNet
  address_prefixes     = ["10.1.1.0/24"]         # the slice
}

resource "azurerm_virtual_network" "spoke_b" {   # spoke VNet B
  name                = "vnet-spoke-b"           # the spoke's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
  address_space       = ["10.2.0.0/16"]          # the spoke's IP space (no overlap)
}

resource "azurerm_subnet" "spoke_b" {            # spoke B's subnet
  name                 = "subnet-spoke-b"        # the subnet's name
  resource_group_name  = azurerm_resource_group.lab.name   # which RG
  virtual_network_name = azurerm_virtual_network.spoke_b.name   # which VNet
  address_prefixes     = ["10.2.1.0/24"]         # the slice
}

resource "azurerm_virtual_network_peering" "hub_to_a" {        # hub → spoke A
  name          = "hub-to-spoke-a"        # the peering's name
  resource_group_name = azurerm_resource_group.lab.name   # which RG
  virtual_network_name        = azurerm_virtual_network.hub.name     # the local VNet
  remote_virtual_network_id   = azurerm_virtual_network.spoke_a.id   # the remote VNet
  allow_virtual_network_access = true        # allow spoke A to reach the hub
  allow_forwarded_traffic    = true          # allow transit (routed) traffic
}

resource "azurerm_virtual_network_peering" "a_to_hub" {        # spoke A → hub
  name          = "spoke-a-to-hub"      # the peering's name
  resource_group_name = azurerm_resource_group.lab.name   # which RG
  virtual_network_name        = azurerm_virtual_network.spoke_a.name   # the local VNet
  remote_virtual_network_id   = azurerm_virtual_network.hub.id         # the remote VNet
  allow_virtual_network_access = true        # allow the hub to reach spoke A
  allow_forwarded_traffic    = true          # allow transit traffic
}

resource "azurerm_virtual_network_peering" "hub_to_b" {        # hub → spoke B
  name          = "hub-to-spoke-b"      # the peering's name
  resource_group_name = azurerm_resource_group.lab.name   # which RG
  virtual_network_name        = azurerm_virtual_network.hub.name     # the local VNet
  remote_virtual_network_id   = azurerm_virtual_network.spoke_b.id   # the remote VNet
  allow_virtual_network_access = true        # allow spoke B to reach the hub
  allow_forwarded_traffic    = true          # allow transit traffic
}

resource "azurerm_virtual_network_peering" "b_to_hub" {        # spoke B → hub
  name          = "spoke-b-to-hub"      # the peering's name
  resource_group_name = azurerm_resource_group.lab.name   # which RG
  virtual_network_name        = azurerm_virtual_network.spoke_b.name   # the local VNet
  remote_virtual_network_id   = azurerm_virtual_network.hub.id         # the remote VNet
  allow_virtual_network_access = true        # allow the hub to reach spoke B
  allow_forwarded_traffic    = true          # allow transit traffic
}
