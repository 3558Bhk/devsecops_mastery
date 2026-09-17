# ============================================================================
#  NSG Outbound Rules — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

resource "azurerm_resource_group" "lab" {        # the resource group
  name     = "rg-lab-nsgout"                     # the group's name
  location = var.region      # <- set in variables.tf (the region everything is built in)
}

resource "azurerm_virtual_network" "lab" {       # the VNet
  name                = "vnet-nsgout"            # the VNet's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
  address_space       = ["10.4.0.0/16"]          # the IP space
}

resource "azurerm_subnet" "app" {                # the subnet
  name                 = "subnet-app"            # the subnet's name
  resource_group_name  = azurerm_resource_group.lab.name   # which RG
  virtual_network_name = azurerm_virtual_network.lab.name  # which VNet
  address_prefixes     = ["10.4.1.0/24"]         # the slice
}

resource "azurerm_network_security_group" "outbound" {   # the NSG
  name                = "nsg-outbound"            # the NSG's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG

  security_rule {                                           # RULE 1: allow outbound HTTPS to the upstream API
    name                        = "allow-api-out"  # the rule's name
    priority                    = 100               # evaluated first
    direction                   = "Outbound"        # outgoing traffic
    access                      = "Allow"           # allow it
    protocol                    = "Tcp"             # TCP
    source_port_range           = "*"               # any source port
    destination_port_range      = "443"             # to 443
    source_address_prefix       = "*"               # from anything in the subnet
    destination_address_prefix  = "198.51.100.0/24" # to this API's range (CHANGE)
    description                 = "Upstream API only"   # a note
  }

  security_rule {                                           # RULE 2: allow DNS (needed for name resolution)
    name                        = "allow-dns-out"  # the rule's name
    priority                    = 110               # evaluated next
    direction                   = "Outbound"        # outgoing
    access                      = "Allow"           # allow it
    protocol                    = "Udp"             # UDP
    source_port_range           = "*"               # any source port
    destination_port_range      = "53"              # the DNS port
    source_address_prefix       = "*"               # from anything
    destination_address_prefix  = "*"               # to anything
    description                 = "DNS resolution"  # a note
  }

  security_rule {                                           # RULE 3: deny outbound to a known-bad prefix (explicit)
    name                        = "deny-bad-out"   # the rule's name
    priority                    = 120               # evaluated after
    direction                   = "Outbound"        # outgoing
    access                      = "Deny"            # deny it
    protocol                    = "*"               # any protocol
    source_port_range           = "*"               # any source port
    destination_port_range      = "*"               # any destination port
    source_address_prefix       = "*"               # from anything
    destination_address_prefix  = "203.0.113.66/32" # to this single bad IP (CHANGE)
    description                 = "Block a known-bad host"   # a note
  }

  # NOTE: everything else is covered by the default AllowInternetOutbound rule —
  # in a hardening lab you'd flip the default to DENY and allow-list explicitly.
}

resource "azurerm_subnet_network_security_group_association" "app" {   # attach to the subnet
  subnet_id                 = azurerm_subnet.app.id             # which subnet
  network_security_group_id = azurerm_network_security_group.outbound.id   # which NSG
}
