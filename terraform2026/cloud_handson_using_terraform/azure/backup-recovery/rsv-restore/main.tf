# ============================================================================
#  Azure RSV Restore — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

resource "azurerm_resource_group" "lab" {        # the resource group
  name     = "rg-lab-rsvrestore"                 # the group's name
  location = var.region      # <- set in variables.tf (the region everything is built in)
}

resource "azurerm_recovery_services_vault" "lab" {   # the vault
  name                = "rsv-restore"           # the vault's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
  sku                 = "Standard"                    # the sku
}

resource "azurerm_virtual_network" "lab" {       # the VNet
  name                = "vnet-restore"           # the VNet's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
  address_space       = ["10.14.0.0/16"]         # the IP space
}

resource "azurerm_subnet" "vm" {                 # the subnet
  name                 = "subnet-restore"        # the subnet's name
  resource_group_name  = azurerm_resource_group.lab.name   # which RG
  virtual_network_name = azurerm_virtual_network.lab.name  # which VNet
  address_prefixes     = ["10.14.1.0/24"]        # the slice
}

resource "azurerm_public_ip" "restore" {         # a public IP for the restored VM
  name                = "pip-restore"            # the IP's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
  allocation_method   = "Static"                  # reserved
  sku            = "Standard"                # Standard
}

resource "azurerm_network_interface" "restore" {   # the NIC
  name                = "nic-restore"            # the NIC's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG

  ip_configuration {                                # the IP config
    name                           = "ipconfig1"   # the config's name
    subnet_id                      = azurerm_subnet.vm.id   # which subnet
    private_ip_address_allocation   = "Dynamic"     # Azure assigns the IP
    public_ip_address_id           = azurerm_public_ip.restore.id   # attach the public IP
  }
}

resource "azurerm_linux_virtual_machine" "restore_target" {   # the target VM
  name                = "vm-restore-target"     # the VM's name (the recovery point restores onto this)
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
  size                = "Standard_B1s"          # the size (match the source's size)

  admin_username                  = "azureadmin"  # the admin user (CHANGE)
  admin_password                  = "Lab-Passw0rd!"  # the admin password (CHANGE)
  disable_password_authentication = false         # allow password login

  network_interface_ids           = [azurerm_network_interface.restore.id]   # the NIC

  os_disk {                                   # the OS disk (the restore overwrites this)
    name              = "osdisk-restore"      # the disk's name
    caching           = "ReadWrite"           # the caching mode
    disk_size_gb      = 30                    # the size (match the source)
    storage_account_type = "Standard_LRS"     # the tier
  }

  source_image_reference {                    # the base image (placeholder; the restore replaces the OS disk)
    publisher = "Canonical"                   # the publisher
    offer     = "0001-com-ubuntu-server-jammy" # the offer
    sku       = "22_04-lts-gen2"              # the sku
    version   = "latest"                      # the version
  }
}
