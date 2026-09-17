# ============================================================================
#  NSG Inbound Rules — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

resource "azurerm_resource_group" "lab" {        # the resource group
  name     = "rg-lab-nsgin"                      # the group's name
  location = var.region      # <- set in variables.tf (the region everything is built in)
}

resource "azurerm_virtual_network" "lab" {       # the VNet
  name                = "vnet-nsgin"             # the VNet's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
  address_space       = ["10.3.0.0/16"]          # the IP space
}

resource "azurerm_subnet" "web" {                # the subnet
  name                 = "subnet-web"            # the subnet's name
  resource_group_name  = azurerm_resource_group.lab.name   # which RG
  virtual_network_name = azurerm_virtual_network.lab.name  # which VNet
  address_prefixes     = ["10.3.1.0/24"]         # the slice
}

resource "azurerm_network_security_group" "inbound" {   # the NSG
  name                = "nsg-inbound"             # the NSG's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG

  security_rule {                                           # RULE 1: ALLOW HTTPS from the Internet
    name                        = "allow-https-in"   # the rule's name
    priority                    = 100                 # evaluated first (lower = earlier)
    direction                   = "Inbound"           # incoming traffic
    access                      = "Allow"             # allow it
    protocol                    = "Tcp"               # TCP
    source_port_range           = "*"                 # any source port
    destination_port_range      = "443"               # to port 443
    source_address_prefix       = "Internet"          # from the Internet (service tag)
    destination_address_prefix  = "*"                 # to anything in the subnet
    description                 = "Public HTTPS"      # a note
  }

  security_rule {                                           # RULE 2: DENY plain HTTP from the Internet
    name                        = "deny-http-in"     # the rule's name
    priority                    = 110                 # evaluated next
    direction                   = "Inbound"           # incoming
    access                      = "Deny"              # deny it
    protocol                    = "Tcp"               # TCP
    source_port_range           = "*"                 # any source port
    destination_port_range      = "80"                # to port 80
    source_address_prefix       = "Internet"          # from the Internet
    destination_address_prefix  = "*"                 # to anything
    description                 = "No plain HTTP"     # a note
  }

  security_rule {                                           # RULE 3: RDP only from an office IP (example)
    name                        = "allow-rdp-office" # the rule's name
    priority                    = 120                 # evaluated after
    direction                   = "Inbound"           # incoming
    access                      = "Allow"             # allow it
    protocol                    = "Tcp"               # TCP
    source_port_range           = "*"                 # any source port
    destination_port_range      = "3389"              # the RDP port
    source_address_prefix       = "203.0.113.10/32"   # a single office IP (CHANGE)
    destination_address_prefix  = "*"                 # to anything
    description                 = "RDP from the office only"   # a note
  }
}

resource "azurerm_subnet_network_security_group_association" "web" {   # attach to the subnet
  subnet_id                 = azurerm_subnet.web.id             # which subnet
  network_security_group_id = azurerm_network_security_group.inbound.id   # which NSG
}
