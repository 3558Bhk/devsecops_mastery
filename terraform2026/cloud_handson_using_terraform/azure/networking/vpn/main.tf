# ============================================================================
#  Azure VPN (site-to-site) — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

resource "azurerm_resource_group" "lab" {        # the resource group
  name     = "rg-lab-vpn"                        # the group's name
  location = var.region      # <- set in variables.tf (the region everything is built in)
}

resource "azurerm_virtual_network" "lab" {       # the VNet
  name                = "vnet-vpn"               # the VNet's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
  address_space       = ["10.10.0.0/16"]         # the IP space
}

resource "azurerm_subnet" "gw" {                 # the gateway subnet (conventional name)
  name                 = "GatewaySubnet"         # the name the gateway expects
  resource_group_name  = azurerm_resource_group.lab.name   # which RG
  virtual_network_name = azurerm_virtual_network.lab.name  # which VNet
  address_prefixes     = ["10.10.0.0/27"]        # a small /27 (gateway needs a few IPs)
}

resource "azurerm_subnet" "app" {                # a normal subnet
  name                 = "subnet-app"            # the subnet's name
  resource_group_name  = azurerm_resource_group.lab.name   # which RG
  virtual_network_name = azurerm_virtual_network.lab.name  # which VNet
  address_prefixes     = ["10.10.1.0/24"]        # the slice
}

resource "azurerm_public_ip" "gw" {              # the gateway's public IP
  name                = "pip-vpn-gw"             # the IP's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
  allocation_method   = "Static"                  # reserved
  sku            = "Basic"                   # Basic (matches the Basic gateway sku)
}

resource "azurerm_virtual_network_gateway" "lab" {   # the VNet gateway
  name                = "vpngw-lab"               # the gateway's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG

  type                = "Vpn"              # the gateway type (Vpn, not ExpressRoute)
  vpn_type            = "RouteBased"                     # the VPN protocol (Udp = the modern one)
  active_active       = false                     # single-site (false) — active_active needs 2 zones
  sku                 = "Basic"                   # the sku (Basic = cheap lab option)

  ip_configuration {                                # the gateway's IP config
    name        = "vpngw-ipconfig"                   # the config's name
    public_ip_address_id = azurerm_public_ip.gw.id  # which public IP
    subnet_id   = azurerm_subnet.gw.id               # which (gateway) subnet
  }
}

resource "azurerm_local_network_gateway" "onprem" {   # the on-prem end (its public IP + CIDR)
  name                = "lgn-onprem"                # the local GW's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG

  gateway_address        = "203.0.113.10"        # your on-prem device's PUBLIC IP (CHANGE)
  address_space = ["192.168.0.0/16"]  # your on-prem CIDR (CHANGE)
}

resource "azurerm_virtual_network_gateway_connection" "lab" {   # the IPsec connection
  name                = "conn-onprem"               # the connection's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG

  type                = "IPsec"                     # the connection type
  virtual_network_gateway_id = azurerm_virtual_network_gateway.lab.id   # the cloud end
  local_network_gateway_id   = azurerm_local_network_gateway.onprem.id  # the on-prem end
  shared_key            = "Lab-SharedKey-Change-Me"   # the pre-shared key (MUST match on-prem)
  connection_protocol     = "IKEv2"                # the IKE protocol
  routing_weight            = 1000                    # the route weight (higher wins)
}
