# ============================================================================
#  Azure RSV Backup — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

resource "azurerm_resource_group" "lab" {        # the resource group
  name     = "rg-lab-rsv"                        # the group's name
  location = var.region      # <- set in variables.tf (the region everything is built in)
}

resource "azurerm_virtual_network" "lab" {       # the VNet
  name                = "vnet-rsv"               # the VNet's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
  address_space       = ["10.13.0.0/16"]         # the IP space
}

resource "azurerm_subnet" "vm" {                 # the subnet
  name                 = "subnet-vm"             # the subnet's name
  resource_group_name  = azurerm_resource_group.lab.name   # which RG
  virtual_network_name = azurerm_virtual_network.lab.name  # which VNet
  address_prefixes     = ["10.13.1.0/24"]        # the slice
}

resource "azurerm_network_interface" "vm" {      # the NIC
  name                = "nic-rsv"                # the NIC's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG

  ip_configuration {                                # the IP config
    name                           = "ipconfig1"   # the config's name
    subnet_id                      = azurerm_subnet.vm.id   # which subnet
    private_ip_address_allocation   = "Dynamic"     # Azure assigns the IP
  }
}

resource "azurerm_linux_virtual_machine" "source" {   # the VM to protect
  name                = "vm-source"             # the VM's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
  size                = "Standard_B1s"          # the size (cheap)

  admin_username                  = "azureadmin"  # the admin user (CHANGE)
  admin_password                  = "Lab-Passw0rd!"  # the admin password (CHANGE)
  disable_password_authentication = false         # allow password login

  network_interface_ids           = [azurerm_network_interface.vm.id]   # the NIC

  os_disk {                                   # the OS disk
    name              = "osdisk-source"       # the disk's name
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

resource "azurerm_recovery_services_vault" "lab" {   # the vault (where recovery points live)
  name                = "rsv-lab"                # the vault's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
  sku                 = "Standard"                    # the sku (RS1 = the standard)
}

resource "azurerm_backup_policy_vm" "lab" {      # the policy
  name                = "bpol-lab"              # the policy's name
  resource_group_name = azurerm_resource_group.lab.name   # which RG
  recovery_vault_name = azurerm_recovery_services_vault.lab.name   # which vault
  timezone            = "UTC"                   # the schedule's timezone

  backup {                                       # the schedule
    frequency = "Daily"                          # back up every day
    time      = "01:00"                          # at 01:00 (in the timezone)
  }

  retention_daily {                              # how many DAILY recovery points to keep
    count = 7                                    # keep 7 days
  }

  # (For a stronger DR posture: add retention_weekly { count = 4, weekdays = [1] }
  #  and retention_monthly { count = 6 } — weekly + monthly retention.)
}

resource "azurerm_backup_protected_vm" "lab" {   # the protection binding
  resource_group_name  = azurerm_resource_group.lab.name   # which RG
  recovery_vault_name  = azurerm_recovery_services_vault.lab.name   # which vault
  source_vm_id         = azurerm_linux_virtual_machine.source.id   # the VM to protect
  backup_policy_id     = azurerm_backup_policy_vm.lab.id   # which policy
}
