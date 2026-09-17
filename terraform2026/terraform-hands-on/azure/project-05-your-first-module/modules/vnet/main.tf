# CHILD MODULE: a reusable VNet with three subnets.
# No terraform {} or provider {} here — the root config supplies them.

resource "azurerm_virtual_network" "this" {        # the VNet itself
  name                = var.name                  # from the module input
  location            = var.location              # from the module input
  resource_group_name = var.resource_group_name   # from the module input
  address_space       = [var.prefix]              # the total address space from the module input
}

resource "azurerm_subnet" "this" {                 # ONE block, but one subnet PER entry in the map
  for_each = var.subnets                          # loop over the subnets map (web/app/data)
  name                 = each.key                 # the subnet is named after its purpose (web/app/data)
  resource_group_name  = var.resource_group_name  # which group
  virtual_network_name = azurerm_virtual_network.this.name   # which VNet
  address_prefixes     = [each.value]             # the CIDR for this subnet from the map
}

# optional: let the ROOT attach a firewall to the web subnet (the capstone passes one in)
# (in this azurerm version the attachment is a separate association resource)
resource "azurerm_subnet_network_security_group_association" "web" {   # the glue: web subnet ⇄ firewall
  count = var.web_nsg_id == null ? 0 : 1        # only exists when the root provides an NSG
  subnet_id                 = azurerm_subnet.this["web"].id            # the web subnet
  network_security_group_id = var.web_nsg_id                      # the NSG from the root
}
