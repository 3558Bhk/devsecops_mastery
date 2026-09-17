# ============================================================================
#  Application Gateway — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

resource "azurerm_resource_group" "lab" {      # the resource group
  name     = "lab-appgw-rg"               # its name
  location = var.region      # <- set in variables.tf (the region everything is built in)
}

resource "azurerm_virtual_network" "lab" {     # the VNet (App Gateway needs a dedicated subnet)
  name                = "lab-appgw-vnet"      # its name
  location            = "eastus"                # the region (required in v5)
  resource_group_name = azurerm_resource_group.lab.name   # which RG
  address_space       = ["10.0.0.0/16"]       # the CIDR
}

resource "azurerm_subnet" "appgw" {            # the App Gateway's DEDICATED subnet (separate in v5)
  name                 = "appgw-subnet"        # its name
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.lab.name
  address_prefixes     = ["10.0.1.0/24"]       # the CIDR
}

resource "azurerm_subnet" "app" {              # the app subnet (the backends)
  name                 = "app-subnet"          # its name
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.lab.name
  address_prefixes     = ["10.0.2.0/24"]       # the CIDR
}

resource "azurerm_public_ip" "appgw" {         # the gateway's public IP
  name                = "pip-appgw"           # its name
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  allocation_method   = "Static"              # reserved
  sku            = "Standard"              # Standard (WAF v2 needs Standard)
}

resource "azurerm_application_gateway" "lab" { # the Application Gateway (layer-7)
  name                = "appgw-lab"           # its name
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name

  # v5: the sku is now a BLOCK (name + tier). For WAF v2: name = tier = "WAF_v2".
  sku {
    name = "WAF_v2"
    tier = "WAF_v2"
  }

  # v5: WAF settings moved from waf_v2_configuration to waf_configuration.
  waf_configuration {
    enabled          = true                  # turn the WAF on
    firewall_mode    = "Prevention"          # block (vs Detection = just log)
    rule_set_type    = "OWASP"               # the OWASP core rule set
    rule_set_version = "3.2"                 # the rule set version
  }

  # App Gateway is a NATURAL NETWORK for this lab:
  # a public IP + a frontend + a backend pool + a listener + a routing rule
  # + a health probe, all in ONE resource.

  gateway_ip_configuration {                # which subnet the gateway sits in
    name      = "appgw-ipconfig"
    subnet_id = azurerm_subnet.appgw.id                      # the dedicated subnet
  }

  request_routing_rule {                    # the routing rule (listener → backend)
    name                       = "rule-web"
    priority                   = 100
    rule_type                  = "Basic"     # simple: one listener → one backend

    http_listener_name         = "listener-web"   # which listener
    backend_address_pool_name  = "backend-web"    # which pool (inline pools are referenced by NAME)
    backend_http_settings_name = "bhs-web"        # the backend http settings (v5: required)
  }

  http_listener {                           # the listener (what we watch for)
    name         = "listener-web"
    protocol     = "Http"                    # we listen on plain HTTP (port 80)
    frontend_ip_configuration_name = "frontend-1"   # which frontend
    frontend_port_name             = "port-80"      # which frontend port
  }

  frontend_ip_configuration {               # the frontend (the public face)
    name                 = "frontend-1"
    public_ip_address_id = azurerm_public_ip.appgw.id
  }

  frontend_port {                           # the frontend port
    name = "port-80"
    port = 80
  }

  backend_http_settings {                   # the backend http settings (v5: required block)
    name                = "bhs-web"         # the settings name
    port                = 80                # the port we talk to on the backends
    protocol            = "Http"            # plain HTTP (the backends are nginx)
    cookie_based_affinity = "Enabled"            # sticky sessions by cookie (v5: required)
  }

  backend_address_pool {                    # the backend pool (the VMs)
    name         = "backend-web"
    ip_addresses = ["10.0.2.4", "10.0.2.5"] # the VM IPs (v5: a list, not a single value)
  }

  probe {                                   # the health probe
    name                 = "probe-web"       # the probe's name
    protocol             = "Http"            # probe over HTTP
    path                 = "/health"         # the URL path to hit
    interval             = 5                 # every 5s
    timeout              = 5                 # wait up to 5s
    unhealthy_threshold  = 2                 # 2 misses = unhealthy
  }
}

resource "azurerm_linux_virtual_machine" "vm1" {   # backend VM #1
  name                            = "vm-appgw-1"
  location                        = azurerm_resource_group.lab.location
  resource_group_name             = azurerm_resource_group.lab.name
  size                            = "Standard_B1s"
  admin_username                  = "azureuser"

  network_interface_ids = [azurerm_network_interface.vm1.id]

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

resource "azurerm_network_interface" "vm1" {       # VM #1's NIC (static private IP)
  name                = "nic-appgw-1"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.app.id                    # the app subnet
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.2.4"    # must match the pool's ip_addresses
  }
}

resource "azurerm_linux_virtual_machine" "vm2" {   # backend VM #2
  name                            = "vm-appgw-2"
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
  name                = "nic-appgw-2"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.app.id                    # the app subnet
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.2.5"    # must match the pool's ip_addresses
  }
}
