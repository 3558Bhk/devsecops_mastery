# ── NETWORK: RG + VNet (from the project-05 module) + the special App Gateway subnet ──

resource "azurerm_resource_group" "capstone" {      # the resource group for everything
  name     = "${var.project}-capstone-rg"          # e.g. capst-capstone-rg
  location = var.location                          # from the input
}

module "vnet" {                                     # module block: call the VNet module from project 05
  source = "../project-05-your-first-module/modules/vnet"   # relative path to that folder
  name             = "${var.project}-capstone-vnet"   # → the module's var.name
  location         = var.location                  # → the module's var.location
  resource_group_name = azurerm_resource_group.capstone.name   # → the module's var.resource_group_name
  prefix           = "10.5.0.0/16"                 # → the module's var.prefix
  subnets          = { web = "10.5.1.0/24", app = "10.5.2.0/24", data = "10.5.3.0/24" }   # the standard three tiers
  # use the module's optional hook: attach our web firewall to the module's web subnet
  web_nsg_id       = azurerm_network_security_group.web.id   # (declared in web.tf; order doesn't matter)
}

# The App Gateway needs a subnet DELEGATED to Microsoft.Network/applicationGateways —
# the generic module can't express that, so this special subnet lives in the root.

resource "azurerm_subnet" "appgw" {                 # the dedicated App Gateway subnet
  name                 = "${var.project}-appgw-subnet"   # the subnet's name
  resource_group_name  = azurerm_resource_group.capstone.name   # which group
  virtual_network_name = module.vnet.vnet_name       # inside the module's VNet
  address_prefixes     = ["10.5.10.0/24"]            # a slice reserved for the gateway

  delegation {                                         # "this subnet exists for App Gateways"
    name = "appgw-delegation"                          # a name for the delegation
    service_delegation {                                # the delegation details
      name    = "Microsoft.Network/applicationGateways"   # which service gets the special treatment
    }
  }
}
