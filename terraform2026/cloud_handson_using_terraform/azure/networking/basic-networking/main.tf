# ============================================================================
#  Azure Basic Networking — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

resource "azurerm_resource_group" "lab" {        # the resource group: the container
  name     = "rg-lab-net"                        # the group's name
  location = var.region      # <- set in variables.tf (the region everything is built in)
}

resource "azurerm_virtual_network" "lab" {       # the VNet
  name                = "vnet-lab"               # the VNet's name
  location            = azurerm_resource_group.lab.location   # same region as the RG
  resource_group_name = azurerm_resource_group.lab.name       # which RG
  address_space       = ["10.1.0.0/16"]          # the total IP space
}

resource "azurerm_subnet" "app" {                # the app subnet
  name                 = "subnet-app"            # the subnet's name
  resource_group_name  = azurerm_resource_group.lab.name   # which RG
  virtual_network_name = azurerm_virtual_network.lab.name  # which VNet
  address_prefixes     = ["10.1.1.0/24"]         # the slice (inside 10.1.0.0/16)
}

resource "azurerm_subnet" "db" {                 # the db subnet (separate for security)
  name                 = "subnet-db"             # the subnet's name
  resource_group_name  = azurerm_resource_group.lab.name   # which RG
  virtual_network_name = azurerm_virtual_network.lab.name  # which VNet
  address_prefixes     = ["10.1.2.0/24"]         # the slice
}

resource "azurerm_network_security_group" "app" {   # the NSG
  name                = "nsg-app"                 # the NSG's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
}

resource "azurerm_subnet_network_security_group_association" "app" {   # attach the NSG to the app subnet
  subnet_id                 = azurerm_subnet.app.id             # which subnet
  network_security_group_id = azurerm_network_security_group.app.id   # which NSG
}

resource "azurerm_public_ip" "web" {              # the public IP
  name                = "pip-lab"                 # the IP's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
  allocation_method   = "Static"                  # reserved (vs Dynamic = changes on reboot)
  sku            = "Standard"                # Standard (works with LB/App GW) or "Basic"
}
