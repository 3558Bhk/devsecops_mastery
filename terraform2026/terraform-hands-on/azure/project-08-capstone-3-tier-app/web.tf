# ── WEB TIER: VM + Application Gateway (WAF v2) in front of it ─────────────────

resource "azurerm_network_security_group" "web" {   # firewall for the web VM
  name                = "${var.project}-web-nsg"   # the NSG's name
  location            = var.location              # same location
  resource_group_name = azurerm_resource_group.capstone.name   # which group

  security_rule {                                    # allow inbound HTTP (from the App Gateway's subnet)
    name                       = "allow-http"       # the rule's name
    priority                   = 100                # evaluated first (lower = first)
    direction                  = "Inbound"          # traffic coming IN
    access                     = "Allow"            # allow
    protocol                   = "Tcp"              # TCP
    source_port_range          = "*"                # any source port
    destination_port_range     = "80"               # only port 80
    source_address_prefix      = "10.5.0.0/16"      # only from inside our VNet (the App GW's subnet)
    destination_address_prefix = "*"                # to anything in the subnet
  }

  security_rule {                                    # keep SSH open for YOUR debugging only
    name                       = "allow-ssh"        # the rule's name
    priority                   = 110                # evaluated second
    direction                  = "Inbound"          # IN
    access                     = "Allow"            # allow
    protocol                   = "Tcp"              # TCP
    source_port_range          = "*"                # any source port
    destination_port_range     = "22"               # port 22
    source_address_prefix      = "0.0.0.0/0"        # from anywhere (tighten to your IP in real life)
    destination_address_prefix = "*"                # to anything
  }
}

resource "azurerm_network_interface" "web" {        # the web VM's NIC
  name                = "${var.project}-web-nic"   # the NIC's name
  location            = var.location              # same location
  resource_group_name = azurerm_resource_group.capstone.name   # which group
  # NOTE: no NSG on the NIC in this azurerm version — the firewall reaches this VM via the
  # subnet (the module attaches azurerm_network_security_group.web to the web subnet, see network.tf)

  ip_configuration {                                  # the NIC's IP setup
    name                         = "ipconfig1"        # a name for this config
    subnet_id                    = module.vnet.subnets["web"]   # the module's web subnet
    private_ip_address           = "10.5.1.10"        # a STATIC private IP (so the App GW can point at it)
    private_ip_address_allocation = "Static"          # static: we chose the address
  }
}

resource "azurerm_linux_virtual_machine" "web" {    # the web server
  name                = "${var.project}-web-vm"    # the VM's name
  location            = var.location              # same location
  resource_group_name = azurerm_resource_group.capstone.name   # which group
  network_interface_ids = [azurerm_network_interface.web.id]   # attach the NIC
  size                = "Standard_B1s"            # smallest burstable

  admin_username = "adminuser"                     # the admin account
  admin_password = var.admin_password              # from the sensitive variable

  # runs once at first boot (the VM's user_data equivalent).
  # azurerm REQUIRES base64 here, so we wrap the heredoc in base64encode():
  custom_data = base64encode(<<-EOF
    #cloud-config
    runcmd:
      - apt-get update -y
      - apt-get install -y nginx
      - systemctl enable --now nginx
      - echo "Hello from the Azure capstone!" > /var/www/html/index.html
  EOF
)

  os_disk {                                          # the OS disk
    caching              = "ReadWrite"               # cache on host
    storage_account_type = "Standard_LRS"            # cheapest disk
  }

  source_image_reference {                           # Ubuntu 22.04
    publisher = "Canonical"                           # who makes it
    offer     = "0001-com-ubuntu-server-jammy"        # the product line
    sku       = "22_04-lts"                           # the version
    version   = "latest"                              # newest
  }
}

resource "azurerm_public_ip" "appgw" {              # the public IP for the App Gateway (Standard: required by WAF v2)
  name                = "${var.project}-appgw-pip"  # the IP's name
  location            = var.location              # same location
  resource_group_name = azurerm_resource_group.capstone.name   # which group
  allocation_method   = "Static"                  # static: survives stop/start
  sku                 = "Standard"                # WAF v2 needs the Standard SKU
}

resource "azurerm_application_gateway" "web" {      # the Application Gateway: L7 LB + WAF
  name                = "${var.project}-appgw"     # the gateway's name
  location            = var.location              # same location
  resource_group_name = azurerm_resource_group.capstone.name   # which group

  sku {                                             # the SKU (a block in this azurerm version, not a single argument)
    name = "WAF_v2"                                 # WAF v2 = web application firewall, generation 2
    tier = "WAF_v2"                                 # the tier
  }

  gateway_ip_configuration {                         # where the gateway itself lives
    name      = "gw-ipconfig"                        # a name for this config
    subnet_id = azurerm_subnet.appgw.id              # the DELEGATED subnet from network.tf
  }

  identity { type = "SystemAssigned" }                # the gateway's own identity: lets it push WAF logs to Log Analytics

  frontend_ip_configuration {                           # the front door (internet-facing)
    name                 = "frontend-ip"               # a name
    public_ip_address_id = azurerm_public_ip.appgw.id  # the public IP from above
  }

  frontend_port {                                       # the public port people hit
    name = "port-80"                                    # a name (the listener refers to it BY NAME)
    port = 80                                            # HTTP
  }

  backend_address_pool {                                 # the pool of servers behind the gateway
    name         = "web-pool"                            # a name (the routing rule refers to it BY NAME)
    ip_addresses = [azurerm_linux_virtual_machine.web.private_ip_address]   # our web VM (static private IP)
  }

  backend_http_settings {                                # how the gateway talks to the pool
    name                  = "web-settings"              # a name (the routing rule refers to it BY NAME)
    port                  = 80                           # hit the VM on port 80
    protocol              = "Http"                       # speak plain HTTP (the WAF terminates for us)
    request_timeout       = 30                           # seconds to wait per request
    cookie_based_affinity = "Disabled"                   # required in this version: "Disabled" or "Enabled"
  }

  # NOTE: in this azurerm version the listener/routing rule refer to the other blocks
  # BY NAME (frontend_port_name, http_listener_name, ...) — not by ID, because those
  # blocks are sets and their IDs aren't indexable.
  http_listener {                                        # "when someone hits the front door..."
    name                           = "route-listener"      # a name
    frontend_ip_configuration_name = "frontend-ip"         # on this front door (by name)
    frontend_port_name             = "port-80"             # on this port (by name)
    protocol                       = "Http"                # over HTTP
  }

  request_routing_rule {                                 # "...do this with the request"
    name                         = "route-to-web"         # a name
    rule_type                    = "Basic"                # route by listener (no conditions)
    http_listener_name           = "route-listener"       # which listener (by name)
    backend_address_pool_name    = "web-pool"             # to this pool (by name)
    backend_http_settings_name   = "web-settings"         # using these settings (by name)
  }
}
