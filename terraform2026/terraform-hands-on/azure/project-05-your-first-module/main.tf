terraform {                                      # the terraform block: settings about Terraform itself
  required_version = ">= 1.5"                    # minimum Terraform version
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 5.0" }   # Azure provider, any 5.x
  }
}

provider "azurerm" {                             # configure the Azure provider (root owns this — not the module)
  features {}                                    # required in v5
}

module "vnet" {                                  # module block: call the child module
  source = "./modules/vnet"                      # where the module's files live
  name             = "tf-mod-vnet"               # → the module's var.name
  location         = var.location                # root variable → module's var.location
  resource_group_name = azurerm_resource_group.app.name   # → the module's var.resource_group_name
  prefix           = "10.5.0.0/16"               # root decides the address space → module's var.prefix
}

# ── Proof the module works: one VM placed inside the module's web subnet ──────

resource "azurerm_resource_group" "app" {        # (the module has no RG — the root owns the container)
  name     = "tf-mod-rg"                         # the group's name
  location = var.location                        # from the input
}

resource "azurerm_network_interface" "vm" {      # the VM's NIC
  name                = "tf-mod-nic"            # the NIC's name
  location            = var.location            # same location
  resource_group_name = azurerm_resource_group.app.name   # which group

  ip_configuration {                               # the NIC's IP setup
    name                         = "ipconfig1"     # a name for this config
    subnet_id                    = module.vnet.subnets["web"]   # READ THE MODULE'S OUTPUT: the web subnet's ID
    private_ip_address_allocation = "Dynamic"      # Azure picks the private IP
  }
}

resource "azurerm_linux_virtual_machine" "vm" {  # the proof VM
  name                = "tf-mod-vm"             # the VM's name
  location            = var.location            # same location
  resource_group_name = azurerm_resource_group.app.name   # which group
  network_interface_ids = [azurerm_network_interface.vm.id]   # attach the NIC
  size                = "Standard_B1s"          # smallest burstable

  admin_username = "adminuser"                   # the admin account
  admin_password = "ModLab-12345!"               # lab only

  os_disk {                                        # the OS disk
    caching              = "ReadWrite"             # cache on host
    storage_account_type = "Standard_LRS"          # cheapest disk
  }

  source_image_reference {                         # Ubuntu 22.04
    publisher = "Canonical"                         # who makes it
    offer     = "0001-com-ubuntu-server-jammy"      # the product line
    sku       = "22_04-lts"                         # the version
    version   = "latest"                            # newest
  }
}
