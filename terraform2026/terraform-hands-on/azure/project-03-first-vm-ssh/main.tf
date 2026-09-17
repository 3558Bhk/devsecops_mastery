terraform {                                      # the terraform block: settings about Terraform itself
  required_version = ">= 1.5"                    # minimum Terraform version
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 5.0" }   # Azure provider, any 5.x
  }
}

provider "azurerm" {                             # configure the Azure provider
  features {}                                    # required in v5 (empty is fine to start)
}

resource "azurerm_resource_group" "vm" {         # the resource group: container for everything
  name     = "tf-vm-lab-rg"                      # the group's name
  location = var.location                        # from the input
}

resource "azurerm_virtual_network" "vm" {        # the virtual network: your private network in the cloud
  name                = "tf-vm-lab-vnet"        # the VNet's name
  location            = var.location            # same location
  resource_group_name = azurerm_resource_group.vm.name   # which group
  address_space       = ["10.1.0.0/16"]         # the total address space this VNet may use
}

resource "azurerm_subnet" "vm" {                 # the subnet: a slice of the VNet the VM lives in
  name                 = "tf-vm-lab-subnet"     # the subnet's name
  resource_group_name  = azurerm_resource_group.vm.name   # which group
  virtual_network_name = azurerm_virtual_network.vm.name   # which VNet
  address_prefixes     = ["10.1.1.0/24"]        # this slice: 10.1.1.0 – 10.1.1.255
}

# in this azurerm version the firewall is attached with a DEDICATED association resource
resource "azurerm_subnet_network_security_group_association" "vm" {   # the glue: subnet ⇄ firewall
  subnet_id                 = azurerm_subnet.vm.id                        # which subnet
  network_security_group_id = azurerm_network_security_group.vm.id        # which firewall
}

resource "azurerm_network_security_group" "vm" { # the NSG: the subnet's firewall
  name                = "tf-vm-lab-nsg"         # the NSG's name
  location            = var.location            # same location
  resource_group_name = azurerm_resource_group.vm.name   # which group

  security_rule {                                 # one rule
    name                       = "allow-ssh"     # the rule's name
    priority                   = 100             # lower number = evaluated first (100–4099)
    direction                  = "Inbound"       # traffic coming IN
    access                     = "Allow"         # allow (the other value: Deny)
    protocol                   = "Tcp"           # the protocol
    source_port_range          = "*"             # any source port
    destination_port_range     = "22"            # only port 22 (SSH)
    source_address_prefix      = "0.0.0.0/0"     # from anywhere — tighten to your IP in real life!
    destination_address_prefix = "*"             # to any address in the subnet
  }
}

resource "azurerm_network_interface" "vm" {      # the NIC: the VM's network card
  name                = "tf-vm-lab-nic"         # the NIC's name
  location            = var.location            # same location
  resource_group_name = azurerm_resource_group.vm.name   # which group
  # NOTE: no network_security_group_id here — in this azurerm version the firewall is attached
  # with a separate association resource (see azurerm_subnet_network_security_group_association above)

  ip_configuration {                               # one IP config block (the NIC's address setup)
    name                           = "ipconfig1"   # a name for this IP config
    subnet_id                      = azurerm_subnet.vm.id   # plug into this subnet
    private_ip_address_allocation  = "Dynamic"     # Azure assigns the private IP
    public_ip_address_id           = azurerm_public_ip.vm.id   # also attach this public IP
  }
}

resource "azurerm_public_ip" "vm" {              # the public IP: the internet-facing address
  name                = "tf-vm-lab-pip"         # the IP's name
  location            = var.location            # same location
  resource_group_name = azurerm_resource_group.vm.name   # which group
  allocation_method   = "Static"                # static: stays the same across stop/start
  sku                 = "Standard"              # Standard SKU (required for modern NIC features)
}

resource "azurerm_linux_virtual_machine" "vm" {  # the VM itself
  name                            = "tf-vm-lab"          # the VM's name
  location                        = var.location         # same location
  resource_group_name             = azurerm_resource_group.vm.name   # which group
  network_interface_ids           = [azurerm_network_interface.vm.id]   # attach this NIC
  size                            = var.vm_size          # from the input (Standard_B1s)

  admin_username = var.admin_username                  # the local admin account
  admin_password = var.admin_password                  # its password (sensitive)

  os_disk {                                             # the OS disk: where the system is installed
    caching              = "ReadWrite"                   # cache writes on the host (faster)
    storage_account_type = "Standard_LRS"                # cheapest disk type
  }

  source_image_reference {                               # the "image" to boot from (Azure's AMI)
    publisher = "Canonical"                               # who makes it
    offer     = "0001-com-ubuntu-server-jammy"            # which product line
    sku       = "22_04-lts"                               # which version
    version   = "latest"                                  # the newest of that SKU
  }
}
