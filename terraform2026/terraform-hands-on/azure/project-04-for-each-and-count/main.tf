terraform {                                      # the terraform block: settings about Terraform itself
  required_version = ">= 1.5"                    # minimum Terraform version
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 5.0" }   # Azure provider, any 5.x
  }
}

provider "azurerm" {                             # configure the Azure provider
  features {}                                    # required in v5 (empty is fine to start)
}

resource "azurerm_resource_group" "loop" {       # the resource group
  name     = "tf-loop-rg"                        # the group's name
  location = "eastus"                            # the region
}

resource "azurerm_virtual_network" "loop" {      # the virtual network
  name                = "tf-loop-vnet"          # the VNet's name
  location            = "eastus"                # same region
  resource_group_name = azurerm_resource_group.loop.name   # which group
  address_space       = ["10.4.0.0/16"]         # the VNet's address space
}

resource "azurerm_subnet" "loop" {               # the subnet the VMs live in
  name                 = "tf-loop-subnet"       # the subnet's name
  resource_group_name  = azurerm_resource_group.loop.name   # which group
  virtual_network_name = azurerm_virtual_network.loop.name   # which VNet
  address_prefixes     = ["10.4.1.0/24"]        # this slice
}

# in this azurerm version the firewall is attached with a DEDICATED association resource
resource "azurerm_subnet_network_security_group_association" "loop" {   # the glue: subnet ⇄ firewall
  subnet_id                 = azurerm_subnet.loop.id                          # which subnet
  network_security_group_id = azurerm_network_security_group.loop.id          # which firewall
}

resource "azurerm_network_security_group" "loop" {   # the NSG: holds all the rules
  name                = "tf-loop-nsg"           # the NSG's name
  location            = "eastus"                # same region
  resource_group_name = azurerm_resource_group.loop.name   # which group
}

resource "azurerm_network_security_rule" "rules" {   # ONE block, but one rule PER entry in the map
  for_each                = var.rules           # loop over the map: keys are ssh/http/https
  name                    = "allow-${each.key}" # each.key = the map key → allow-ssh, allow-http...
  priority                = each.value.priority # from the object
  direction               = "Inbound"           # traffic coming IN
  access                  = "Allow"             # allow
  protocol                = "Tcp"               # TCP
  source_port_range       = "*"                 # any source port
  destination_port_range  = tostring(each.value.port)   # the port from the object (must be a string!)
  source_address_prefix   = "0.0.0.0/0"         # from anywhere (tighten in real life)
  destination_address_prefix = "*"              # to anything in the subnet
  resource_group_name     = azurerm_resource_group.loop.name   # which group
  network_security_group_name = azurerm_network_security_group.loop.name   # which NSG
}

resource "azurerm_network_interface" "vm" {      # ONE block, but one NIC PER VM
  count                 = var.vm_count          # run this block N times
  name                  = "tf-loop-nic-${count.index}"   # tf-loop-nic-0, tf-loop-nic-1...
  location              = "eastus"              # same region
  resource_group_name   = azurerm_resource_group.loop.name   # which group
  # NOTE: no NSG on the NIC in this azurerm version — the firewall is attached to the subnet
  # via a separate association resource (declared above)

  ip_configuration {                               # the NIC's IP setup
    name                         = "ipconfig1"     # a name for this config
    subnet_id                    = azurerm_subnet.loop.id   # into the shared subnet
    private_ip_address_allocation = "Dynamic"      # Azure picks the private IP
  }
}

resource "azurerm_linux_virtual_machine" "vm" {  # ONE block, but one VM PER NIC
  count                 = var.vm_count          # same N as the NICs
  name                  = "tf-loop-vm-${count.index}"   # tf-loop-vm-0, tf-loop-vm-1
  location              = "eastus"              # same region
  resource_group_name   = azurerm_resource_group.loop.name   # which group
  network_interface_ids = [azurerm_network_interface.vm[count.index].id]   # THIS vm's NIC (match the index!)
  size                  = "Standard_B1s"        # the cheapest burstable VM

  admin_username = "adminuser"                   # the admin account
  admin_password = "LoopLab-12345!"              # (lab only — a real system uses an SSH key)

  os_disk {                                        # the OS disk
    caching              = "ReadWrite"             # cache on host
    storage_account_type = "Standard_LRS"          # cheapest disk
  }

  source_image_reference {                         # boot from Ubuntu 22.04
    publisher = "Canonical"                         # who makes it
    offer     = "0001-com-ubuntu-server-jammy"      # the product line
    sku       = "22_04-lts"                         # the version
    version   = "latest"                            # newest
  }
}
