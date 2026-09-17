# ============================================================================
#  Azure Monitor — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

resource "azurerm_resource_group" "lab" {        # the resource group
  name     = "rg-lab-monitor"                    # the group's name
  location = var.region      # <- set in variables.tf (the region everything is built in)
}

resource "azurerm_virtual_network" "lab" {       # the VNet
  name                = "vnet-monitor"           # the VNet's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
  address_space       = ["10.15.0.0/16"]         # the IP space
}

resource "azurerm_subnet" "vm" {                 # the subnet
  name                 = "subnet-monitor"        # the subnet's name
  resource_group_name  = azurerm_resource_group.lab.name   # which RG
  virtual_network_name = azurerm_virtual_network.lab.name  # which VNet
  address_prefixes     = ["10.15.1.0/24"]        # the slice
}

resource "azurerm_network_interface" "vm" {      # the NIC
  name                = "nic-monitor"            # the NIC's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG

  ip_configuration {                                # the IP config
    name                           = "ipconfig1"   # the config's name
    subnet_id                      = azurerm_subnet.vm.id   # which subnet
    private_ip_address_allocation   = "Dynamic"     # Azure assigns the IP
  }
}

resource "azurerm_linux_virtual_machine" "watched" {   # the VM the alert watches
  name                = "vm-watched"            # the VM's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
  size                = "Standard_B1s"          # the size (cheap)

  admin_username                  = "azureadmin"  # the admin user (CHANGE)
  admin_password                  = "Lab-Passw0rd!"  # the admin password (CHANGE)
  disable_password_authentication = false         # allow password login

  network_interface_ids           = [azurerm_network_interface.vm.id]   # the NIC

  os_disk {                                   # the OS disk
    name              = "osdisk-watched"      # the disk's name
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

resource "azurerm_log_analytics_workspace" "lab" {   # the workspace
  name                = "law-lab"                # the workspace's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
  sku                 = "PerGB2018"             # the pricing tier
  retention_in_days   = 30                      # how long logs are kept
}

resource "azurerm_monitor_action_group" "lab" {   # the action group
  name                = "ag-lab"                 # the group's name
  resource_group_name = azurerm_resource_group.lab.name   # which RG
  short_name          = "labpage"                # the short name (used in the URL)

  email_receiver {                                         # an EMAIL receiver
    name        = "ops-email"                     # the receiver's name
    email_address = "you@example.com"            # the destination (CHANGE)
    use_common_alert_schema = true                # use the modern schema
  }
}

resource "azurerm_monitor_metric_alert" "cpu" {   # the alert rule
  name                = "alert-cpu-high"        # the alert's name
  resource_group_name = azurerm_resource_group.lab.name   # which RG
  scopes              = [azurerm_linux_virtual_machine.watched.id]   # the resource to watch

  criteria {                                       # the condition
    metric_namespace = "microsoft.compute/virtualmachines"   # the metric's namespace
    metric_name      = "Percentage CPU"           # the metric
    aggregation      = "Average"                  # how to aggregate
    operator         = "GreaterThanOrEqual"       # the comparison
    threshold        = 80                         # the threshold (percent)
  }

  action {                                         # what to do when it fires
    action_group_id = azurerm_monitor_action_group.lab.id   # the action group
  }
}
