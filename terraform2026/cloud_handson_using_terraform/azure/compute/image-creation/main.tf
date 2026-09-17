# ============================================================================
#  Azure Image Creation — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

resource "azurerm_resource_group" "lab" {        # the resource group
  name     = "rg-lab-image"                      # the group's name
  location = var.region      # <- set in variables.tf (the region everything is built in)
}

resource "azurerm_virtual_network" "lab" {       # the VNet
  name                = "vnet-image"             # the VNet's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
  address_space       = ["10.11.0.0/16"]         # the IP space
}

resource "azurerm_subnet" "vm" {                 # the subnet
  name                 = "subnet-vm"             # the subnet's name
  resource_group_name  = azurerm_resource_group.lab.name   # which RG
  virtual_network_name = azurerm_virtual_network.lab.name  # which VNet
  address_prefixes     = ["10.11.1.0/24"]        # the slice
}

resource "azurerm_linux_virtual_machine" "golden" {   # the VM you'll capture
  name                = "vm-golden"             # the VM's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
  size                = "Standard_B1s"          # the size (cheap)

  admin_username                  = "azureadmin"  # the admin user (CHANGE)
  admin_password                  = "Lab-Passw0rd!"  # the admin password (CHANGE)
  disable_password_authentication = false         # allow password login

  network_interface_ids           = [azurerm_network_interface.golden.id]   # the NIC

  os_disk {                                   # the OS disk (this becomes the image's disk)
    name              = "osdisk-golden"        # the disk's name
    caching           = "ReadWrite"           # the caching mode
    disk_size_gb      = 30                    # the size
    storage_account_type = "Standard_LRS"     # the tier
  }

  source_image_reference {                    # the base image
    publisher = "Canonical"                   # the publisher
    offer     = "0001-com-ubuntu-server-jammy" # the offer
    sku       = "22_04-lts-gen2"              # the sku
    version   = "latest"                      # the version
  }
}

resource "azurerm_network_interface" "golden" {   # the golden VM's NIC
  name                = "nic-golden"            # the NIC's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG

  ip_configuration {                                # the IP config
    name                           = "ipconfig1"   # the config's name
    subnet_id                      = azurerm_subnet.vm.id   # which subnet
    private_ip_address_allocation   = "Dynamic"     # Azure assigns the IP
  }
}

resource "azurerm_image" "golden" {              # the image
  name                = "img-golden"            # the image's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG

  # v5 captures the whole VM's disks directly from the VM's id:
  source_virtual_machine_id = azurerm_linux_virtual_machine.golden.id   # the golden VM
}

resource "azurerm_linux_virtual_machine" "from_image" {   # a VM created FROM the image
  name                = "vm-from-image"         # the VM's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
  size                = "Standard_B1s"          # the size

  admin_username                  = "azureadmin"  # the admin user (CHANGE)
  admin_password                  = "Lab-Passw0rd!"  # the admin password (CHANGE)
  disable_password_authentication = false         # allow password login

  network_interface_ids           = [azurerm_network_interface.from_image.id]   # the NIC

  # Instead of a Marketplace source, point straight at the IMAGE (v5: source_image_id)
  source_image_id = azurerm_image.golden.id  # the image to deploy from

  os_disk {                                   # the OS disk (still required)
    caching              = "ReadWrite"        # the caching mode
    storage_account_type = "Standard_LRS"     # the disk storage type
  }
}

resource "azurerm_network_interface" "from_image" {   # the new VM's NIC
  name                = "nic-from-image"      # the NIC's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG

  ip_configuration {                                # the IP config
    name                           = "ipconfig1"   # the config's name
    subnet_id                      = azurerm_subnet.vm.id   # which subnet
    private_ip_address_allocation   = "Dynamic"     # Azure assigns the IP
  }
}
