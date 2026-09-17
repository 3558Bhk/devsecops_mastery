# ============================================================================
#  Identity Mgmt in Storage — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

resource "azurerm_resource_group" "lab" {        # the resource group
  name     = "rg-lab-identity"                   # the group's name
  location = var.region      # <- set in variables.tf (the region everything is built in)
}

resource "random_string" "suffix" {              # a random suffix for the account name
  length  = 8                                    # 8 characters
  special = false                                # no special chars
  lower = true                               # lowercase only
}

resource "azurerm_storage_account" "lab" {       # the storage account
  name                = "storid${random_string.suffix.result}"   # a unique name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
  account_tier            = "Standard"          # the tier
  account_replication_type = "LRS"              # the replication
  https_traffic_only_enabled = true             # force HTTPS
  min_tls_version         = "TLS1_2"            # the minimum TLS version
}

resource "azurerm_user_assigned_identity" "storage" {   # the identity (standalone, shareable)
  name                = "id-storage"            # the identity's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
  # (tenant_id is optional; it defaults to the subscription's tenant)
}

resource "azurerm_role_assignment" "blob_owner" {   # the grant
  scope                = azurerm_storage_account.lab.id   # on the storage account
  role_definition_name = "Storage Blob Data Owner"   # the role (full blob access)
  principal_id         = azurerm_user_assigned_identity.storage.principal_id   # the identity
}

resource "azurerm_virtual_network" "lab" {       # the VNet
  name                = "vnet-identity"          # the VNet's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
  address_space       = ["10.12.0.0/16"]         # the IP space
}

resource "azurerm_subnet" "vm" {                 # the subnet
  name                 = "subnet-vm"             # the subnet's name
  resource_group_name  = azurerm_resource_group.lab.name   # which RG
  virtual_network_name = azurerm_virtual_network.lab.name  # which VNet
  address_prefixes     = ["10.12.1.0/24"]        # the slice
}

resource "azurerm_network_interface" "vm" {      # the NIC
  name                = "nic-identity"           # the NIC's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG

  ip_configuration {                                # the IP config
    name                           = "ipconfig1"   # the config's name
    subnet_id                      = azurerm_subnet.vm.id   # which subnet
    private_ip_address_allocation   = "Dynamic"     # Azure assigns the IP
  }
}

resource "azurerm_linux_virtual_machine" "consumer" {   # the VM that reads the blobs
  name                = "vm-consumer"           # the VM's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
  size                = "Standard_B1s"          # the size (cheap)

  admin_username                  = "azureadmin"  # the admin user (CHANGE)
  admin_password                  = "Lab-Passw0rd!"  # the admin password (CHANGE)
  disable_password_authentication = false         # allow password login

  network_interface_ids           = [azurerm_network_interface.vm.id]   # the NIC

  identity {                                  # the VM's identity
    type                = "UserAssigned"      # use a User-assigned identity
    identity_ids        = [azurerm_user_assigned_identity.storage.id]   # which identity
  }

  os_disk {                                   # the OS disk
    name              = "osdisk-consumer"     # the disk's name
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
