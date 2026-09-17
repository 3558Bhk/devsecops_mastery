# ============================================================================
#  Azure Virtual Machines — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

resource "azurerm_resource_group" "lab" {        # the resource group: the container for everything
  name     = "rg-lab-vm"                         # the group's name
  location = var.region      # <- set in variables.tf (the region everything is built in)
}

resource "azurerm_virtual_network" "lab" {       # the VNet: the virtual network
  name                = "vnet-vm"                # the VNet's name
  location            = azurerm_resource_group.lab.location   # same region as the RG
  resource_group_name = azurerm_resource_group.lab.name       # which RG
  address_space       = ["10.9.0.0/16"]          # the total IP space
}

resource "azurerm_subnet" "vm" {                 # the subnet the VM lives in
  name                 = "subnet-vm"             # the subnet's name
  resource_group_name  = azurerm_resource_group.lab.name   # which RG
  virtual_network_name = azurerm_virtual_network.lab.name  # which VNet
  address_prefixes     = ["10.9.1.0/24"]         # the slice of the VNet space
}

resource "azurerm_network_security_group" "vm" {   # the NSG
  name                = "nsg-vm"                 # the NSG's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG

  security_rule {                                           # ALLOW inbound SSH (from a single IP)
    name                        = "allow-ssh"     # the rule's name
    priority                    = 100             # evaluated first (lower = earlier)
    direction                   = "Inbound"       # incoming traffic
    access                      = "Allow"         # allow it
    protocol                    = "Tcp"           # the protocol
    source_port_range           = "*"             # any source port
    destination_port_range      = "22"            # the SSH port
    source_address_prefix       = "203.0.113.10/32"   # your office IP (CHANGE)
    destination_address_prefix  = "*"             # to anything in the subnet
  }
}

resource "azurerm_public_ip" "vm" {              # the VM's public IP
  name                = "pip-vm"                 # the IP's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
  allocation_method   = "Static"                  # reserved (vs Dynamic)
  sku            = "Standard"                # Standard
}

resource "azurerm_network_interface" "vm" {      # the NIC: the VM's network card
  name                = "nic-vm"                 # the NIC's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG

  ip_configuration {                                # the NIC's IP configuration
    name                           = "ipconfig1"   # the config's name
    subnet_id                      = azurerm_subnet.vm.id   # which subnet
    private_ip_address_allocation   = "Dynamic"     # Azure assigns a private IP
    public_ip_address_id           = azurerm_public_ip.vm.id   # attach the public IP
  }

}

resource "azurerm_network_interface_security_group_association" "vm" {   # attach the NSG to the NIC (v5: separate resource)
  network_interface_id        = azurerm_network_interface.vm.id   # which NIC
  network_security_group_id = azurerm_network_security_group.vm.id   # which NSG
}

resource "azurerm_linux_virtual_machine" "web" {   # the VM
  name                            = "vm-lab"      # the VM's name
  location                        = azurerm_resource_group.lab.location   # region
  resource_group_name             = azurerm_resource_group.lab.name       # which RG
  size                            = "Standard_B1s"  # the size (the cheapest burstable)

  admin_username                  = "azureadmin"  # the admin user (CHANGE)
  admin_password                  = "Lab-Passw0rd!"  # the admin password (CHANGE; must be strong)
  disable_password_authentication = false         # allow password login (true = key-only, more secure)

  network_interface_ids           = [azurerm_network_interface.vm.id]   # the NIC(s)

  os_disk {                                   # the OS disk (a managed disk)
    name              = "osdisk-vm"           # the disk's name
    caching           = "ReadWrite"           # the caching mode
    disk_size_gb      = 30                    # the size (GB)
    storage_account_type = "Standard_LRS"     # the storage tier (Standard = HDD, cheap)
  }

  source_image_reference {                    # the base image (from the Azure Marketplace)
    publisher = "Canonical"                   # the publisher
    offer     = "0001-com-ubuntu-server-jammy" # the offer (Ubuntu 22.04)
    sku       = "22_04-lts-gen2"              # the sku (22.04 LTS gen2)
    version   = "latest"                      # the version (latest)
  }
}
