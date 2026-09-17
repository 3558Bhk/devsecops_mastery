# ============================================================================
#  NSG Intro — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

resource "azurerm_resource_group" "lab" {        # the resource group
  name     = "rg-lab-nsg"                        # the group's name
  location = var.region      # <- set in variables.tf (the region everything is built in)
}

resource "azurerm_virtual_network" "lab" {       # the VNet
  name                = "vnet-nsg"               # the VNet's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
  address_space       = ["10.2.0.0/16"]          # the IP space
}

resource "azurerm_subnet" "web" {                # the subnet
  name                 = "subnet-web"            # the subnet's name
  resource_group_name  = azurerm_resource_group.lab.name   # which RG
  virtual_network_name = azurerm_virtual_network.lab.name  # which VNet
  address_prefixes     = ["10.2.1.0/24"]         # the slice
}

resource "azurerm_network_security_group" "intro" {   # the NSG
  name                = "nsg-intro"               # the NSG's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG

  # (No `rule {}` blocks: the NSG runs on its DEFAULT rules only —
  #  AllowVNetInbound (65000...), AllowAzureLoadBalancerInbound, DenyAllInbound (65001).)
}

resource "azurerm_subnet_network_security_group_association" "web" {   # attach to the subnet
  subnet_id                 = azurerm_subnet.web.id             # which subnet
  network_security_group_id = azurerm_network_security_group.intro.id   # which NSG
}
