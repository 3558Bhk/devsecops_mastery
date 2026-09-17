# ============================================================================
#  ASG (App Security Group) — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

resource "azurerm_resource_group" "lab" {        # the resource group
  name     = "rg-lab-asg"                        # the group's name
  location = var.region      # <- set in variables.tf (the region everything is built in)
}

resource "azurerm_virtual_network" "lab" {       # the VNet
  name                = "vnet-asg"               # the VNet's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
  address_space       = ["10.5.0.0/16"]          # the IP space
}

resource "azurerm_subnet" "app" {                # the subnet
  name                 = "subnet-app"            # the subnet's name
  resource_group_name  = azurerm_resource_group.lab.name   # which RG
  virtual_network_name = azurerm_virtual_network.lab.name  # which VNet
  address_prefixes     = ["10.5.1.0/24"]         # the slice
}

resource "azurerm_network_interface" "app" {      # the NIC
  name                = "nic-asg"                 # the NIC's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG

  ip_configuration {                                # the IP configuration
    name                           = "ipconfig1"   # the config's name
    subnet_id                      = azurerm_subnet.app.id   # which subnet
    private_ip_address_allocation   = "Dynamic"     # assign an IP from the subnet
  }
}

resource "azurerm_application_security_group" "app" {   # the ASG
  name                = "asg-app"                   # the ASG's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG

  # NOTE (azurerm v5): ASG *rules* are no longer managed by the Terraform provider
  # (they were removed in v5 — NSG rules cover most needs). Create the rule via CLI:
  #   az network asg rule create --name allow-8080-in --priority 100 --direction Inbound \
  #     --access Allow --protocol Tcp --destination-port-ranges 8080 \
  #     --source-address-prefixes VirtualNetwork \
  #     --resource-group rg-lab-asg --name asg-app
  # (The group itself + the NIC association below are fully managed here.)
}

resource "azurerm_network_interface_application_security_group_association" "app" {   # attach the ASG to the NIC
  network_interface_id        = azurerm_network_interface.app.id   # which NIC
  application_security_group_id = azurerm_application_security_group.app.id   # which ASG
}
