# ============================================================================
#  Azure Load Balancer — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

resource "azurerm_resource_group" "lab" {      # the resource group
  name     = "lab-lb-rg"                  # its name
  location = var.region      # <- set in variables.tf (the region everything is built in)
}

resource "azurerm_virtual_network" "lab" {     # the VNet
  name                = "lab-lb-vnet"         # its name
  location            = "eastus"                # the region (required in v5)
  resource_group_name = azurerm_resource_group.lab.name   # which RG
  address_space       = ["10.0.0.0/16"]       # the CIDR range
}

resource "azurerm_subnet" "lab" {              # the public subnet (separate resource in v5)
  name                 = "lab-subnet"          # its name
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.lab.name
  address_prefixes     = ["10.0.1.0/24"]       # the CIDR
}

resource "azurerm_public_ip" "lb" {            # the LB's public IP
  name                = "pip-lb"              # its name
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  allocation_method   = "Static"              # reserved (vs Dynamic)
  sku            = "Standard"              # Standard
}

resource "azurerm_lb" "lab" {                  # the Load Balancer itself
  name                = "lb-lab"              # its name
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name

  sku      = "Standard"                        # the sku (v5: sku + sku_tier, not sku_name)
  sku_tier = "Regional"                      # the tier (Global | Regional — v5 enum)

  frontend_ip_configuration {                 # the front-end IP (clients hit this)
    name                 = "front-1"          # the config's name
    public_ip_address_id = azurerm_public_ip.lb.id   # the IP it uses
  }

  # v5 change: the backend pool, the probe and the rule are now SEPARATE
  # resources (azurerm_lb_backend_address_pool / _probe / _rule), not inline blocks.
}

resource "azurerm_lb_backend_address_pool" "web" {   # the backend pool (the VMs)
  name           = "backend-web"                   # the pool's name
  loadbalancer_id = azurerm_lb.lab.id             # which LB (v5: required)
}

resource "azurerm_lb_probe" "http" {               # the health probe (a heartbeat)
  name           = "probe-http"                    # the probe's name
  loadbalancer_id = azurerm_lb.lab.id             # which LB
  port           = 80                              # probe port 80
  protocol       = "Http"                          # probe with HTTP

  request_path   = "/health"                       # the URL path to hit
  interval_in_seconds = 5                        # every 5 seconds (v5: interval_in_seconds)
  number_of_probes   = 2                           # 2 misses = unhealthy
}

resource "azurerm_lb_rule" "http" {                # the rule (front-end → back-end)
  name            = "rule-http"                   # the rule's name
  loadbalancer_id = azurerm_lb.lab.id             # which LB

  frontend_ip_configuration_name = "front-1"      # the front-end config (by name)
  frontend_port     = 80                          # the port clients hit
  backend_port      = 80                          # the port the pool is talked on
  protocol          = "Tcp"                       # the transport protocol
  load_distribution = "Default"                   # the distribution algorithm
  tcp_reset_enabled = true                      # send TCP RSTs (v5: tcp_reset_enabled)
  disable_outbound_snat = true                # don't allocate outbound ports (v5: disable_outbound_snat)

  backend_address_pool_ids = [azurerm_lb_backend_address_pool.web.id]   # which pool
  probe_id                 = azurerm_lb_probe.http.id   # which probe
}

resource "azurerm_linux_virtual_machine" "vm1" {   # backend VM #1
  name                            = "vm-lb-1"
  location                        = azurerm_resource_group.lab.location
  resource_group_name             = azurerm_resource_group.lab.name
  size                            = "Standard_B1s"
  admin_username                  = "azureuser"

  network_interface_ids = [azurerm_network_interface.vm1.id]   # the NIC

  admin_ssh_key {
    username   = "azureuser"
    public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDwD/tOxjvSkxisAmNx/12+sl1lB4SLEw1FWDCUua+X3zb1b3FHOftA4QEqB3DI20psBIAurjBpcVm4BnGzFENOUbAHFf7Fc4f+u8k8Pn7trZMA9RAwvO7Ob6EwpniiV/I8bFZGwLDorRLDc1Mo3Q6JhLHYWkosiknXZUcY7zuhTUYAKwtAd041Fr/j37H8kbM8vwG2sJ7cIuCFbUZfA4d6G875th4K5nGhAlzpShtllsLd0umpV2r38m3bR7lWtOHJx2ARmY5jiJVA9uimrgCjHURa8O72bVjjTk3XO0MxZavBFiqZihQJXloyMHIj/vBhqnwbz0SFzVLThzmSOz5B"            # ⚠️ DUMMY lab key — REPLACE with YOUR key
  }

  os_disk {
    caching              = "ReadWrite"     # the caching mode
    storage_account_type = "Standard_LRS"  # the disk storage type (required in v5)
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
}

resource "azurerm_network_interface" "vm1" {       # VM #1's NIC
  name                = "nic-vm1"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.lab.id                 # which subnet
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.1.4"    # a STATIC ip (so the pool can target it)
  }
}

resource "azurerm_lb_backend_address_pool_address" "vm1" {   # add the VM's IP to the pool (v5: separate resource)
  name                    = "addr-vm1"             # the entry's name
  backend_address_pool_id = azurerm_lb_backend_address_pool.web.id   # which pool
  ip_address              = "10.0.1.4"             # the VM's static IP
}

resource "azurerm_linux_virtual_machine" "vm2" {   # backend VM #2 (identical shape)
  name                            = "vm-lb-2"
  location                        = azurerm_resource_group.lab.location
  resource_group_name             = azurerm_resource_group.lab.name
  size                            = "Standard_B1s"
  admin_username                  = "azureuser"

  network_interface_ids = [azurerm_network_interface.vm2.id]

  admin_ssh_key {
    username   = "azureuser"
    public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDwD/tOxjvSkxisAmNx/12+sl1lB4SLEw1FWDCUua+X3zb1b3FHOftA4QEqB3DI20psBIAurjBpcVm4BnGzFENOUbAHFf7Fc4f+u8k8Pn7trZMA9RAwvO7Ob6EwpniiV/I8bFZGwLDorRLDc1Mo3Q6JhLHYWkosiknXZUcY7zuhTUYAKwtAd041Fr/j37H8kbM8vwG2sJ7cIuCFbUZfA4d6G875th4K5nGhAlzpShtllsLd0umpV2r38m3bR7lWtOHJx2ARmY5jiJVA9uimrgCjHURa8O72bVjjTk3XO0MxZavBFiqZihQJXloyMHIj/vBhqnwbz0SFzVLThzmSOz5B"            # ⚠️ DUMMY lab key — REPLACE with YOUR key
  }

  os_disk {
    caching              = "ReadWrite"     # the caching mode
    storage_account_type = "Standard_LRS"  # the disk storage type (required in v5)
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
}

resource "azurerm_network_interface" "vm2" {       # VM #2's NIC
  name                = "nic-vm2"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.lab.id                 # which subnet
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.1.5"    # a STATIC ip (so the pool can target it)
  }
}

resource "azurerm_lb_backend_address_pool_address" "vm2" {   # add the VM's IP to the pool (v5: separate resource)
  name                    = "addr-vm2"             # the entry's name
  backend_address_pool_id = azurerm_lb_backend_address_pool.web.id   # which pool
  ip_address              = "10.0.1.5"             # the VM's static IP
}
