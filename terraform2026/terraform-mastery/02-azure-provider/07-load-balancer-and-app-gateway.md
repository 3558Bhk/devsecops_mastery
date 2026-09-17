# Azure 7 — Load Balancer & Application Gateway

> **⏱️ Time to complete: ~75 min** (read + create an LB + an Application Gateway)

## 7.1 Azure Load Balancer (Layer 4)

```hcl
locals {                                      # named expressions
  name_prefix = "${var.project}-${var.environment}"   # e.g. "webapp-dev"
}

# Public IP (Standard)
resource "azurerm_public_ip" "lb" {           # a public IP for the LB
  name                = "${local.name_prefix}-lb-ip"   # the name
  location            = azurerm_resource_group.main.location   # the location
  resource_group_name = azurerm_resource_group.main.name   # the RG
  allocation_method   = "Static"               # static allocation
  sku_name            = "Standard"             # Standard SKU
}

resource "azurerm_network_interface" "lb_nic" {   # a NIC for the LB (in the VNet)
  name                = "${local.name_prefix}-lb-nic"   # the name
  location            = azurerm_resource_group.main.location   # the location
  resource_group_name = azurerm_resource_group.main.name   # the RG

  ip_configuration {                            # the IP configuration
    name                          = "lb"        # the config name
    subnet_id                     = azurerm_subnet.app.id   # the subnet
    private_ip_allocation_method  = "Dynamic"   # dynamic private IP
    public_ip_address_id          = azurerm_public_ip.lb.id   # the public IP
  }
}

resource "azurerm_load_balancer" "main" {      # the load balancer
  name                = "${local.name_prefix}-lb"   # the name
  location            = azurerm_resource_group.main.location   # the location
  resource_group_name = azurerm_resource_group.main.name   # the RG
  sku_name            = "Standard"             # Standard SKU

  frontend_ip_configuration {                    # the frontend IP config
    name                 = "FrontEnd"            # the name
    public_ip_address_id = azurerm_public_ip.lb.id   # the public IP
  }

  backend_address_pool {                         # the backend pool
    name = "BackEnd"                             # the name
  }

  probe {                                        # the health probe
    name     = "http-probe"                      # the name
    protocol = "Http"                            # the protocol
    port     = 80                                # the port
    request_path = "/healthz"                    # the path to probe
    interval_in_seconds = 5                      # probe every 5 s
    number_of_probes = 2                         # 2 failures = unhealthy
  }

  load_balancer_rule {                           # the LB rule
    name                       = "http"          # the name
    protocol                   = "Tcp"           # the protocol
    frontend_port              = 80              # the frontend port
    backend_port               = 80              # the backend port
    frontend_ip_configuration_name = "FrontEnd"  # the frontend IP config
    backend_address_pool_id    = azurerm_load_balancer.main.backend_address_pool[0].id   # the backend pool
    probe_id                   = azurerm_load_balancer.main.probe[0].id   # the probe
    enable_tcp_reset           = true            # enable TCP reset
    disable_outbound_snat      = false           # don't disable outbound SNAT
  }

  tags = local.common_tags                       # the common tags
}
```

- **Azure LB** = Layer 4 (TCP/UDP) — like AWS NLB. It does **no** path/host routing and **no** TLS termination (TLS passthrough).
- **Probe** = the health check (port/path/interval).
- **`load_balancer_rule`** = frontend (port) → backend pool (+ probe).
- **Standard SKU** (zone-redundant) for prod.

> **To reach the backend VMs**: add them to the **backend pool** (via a `azurerm_lb_backend_address_pool` reference / NIC) and ensure the **NSG allows** the **`AzureLoadBalancer`** source (the built-in `AllowAzureLoadBalancerInbound` default rule covers the probe).

## 7.2 Application Gateway (Layer 7 — the "ALB equivalent")

Application Gateway (App GW) = the **L7** load balancer: path/host routing, TLS termination, **WAF**.

```hcl
# (App GW needs its own subnet, typically /24, and a WAF policy if using WAF)
resource "azurerm_subnet" "appgw" {             # a dedicated subnet for the App GW
  name                 = "${local.name_prefix}-appgw"   # the name
  resource_group_name  = azurerm_resource_group.main.name   # the RG
  virtual_network_name = azurerm_virtual_network.main.name  # the VNet
  address_prefixes     = ["10.0.3.0/24"]        # the CIDR
  # (delegation is NOT required for App GW, but the subnet should be dedicated)
}

# WAF policy
resource "azurerm_application_gateway_web_application_policy" "waf" {   # a WAF policy
  name                = "${local.name_prefix}-waf"   # the name
  resource_group_name = azurerm_resource_group.main.name   # the RG
  sku                 = "WAF_v2"                 # the SKU
  policy_settings {                              # the policy settings
    mode = "Prevention"   # (or "Detection")
  }
  request_routing_rule {                         # a routing rule
    name       = "rule1"                          # the name
    rule_type  = "MatchRule"                      # a match rule
    conditions {                                   # a condition
      variable = "RemoteAddr"                     # the variable
      operator = "IPAddress"                      # the operator
      values   = ["1.2.3.4"]                      # the IP(s) to match
      negation = true                             # match everything EXCEPT these
    }
    action = "Block"                             # the action
  }
  tags = local.common_tags                       # the common tags
}
```

> In practice, the WAF policy is defined **inline** on the `azurerm_application_gateway` (via `waf_configuration`) or as a standalone policy. Below shows the gateway with an inline WAF.

```hcl
# (A certificate — from Key Vault — for TLS termination)
data "azurerm_key_vault_certificate" "app" {   # read a cert from Key Vault
  name         = "app-cert"                   # the cert name
  key_vault_id = azurerm_key_vault.kv.id      # the Key Vault
}

resource "azurerm_application_gateway" "main" {   # the Application Gateway
  name                = "${local.name_prefix}-appgw"   # the name
  location            = azurerm_resource_group.main.location   # the location
  resource_group_name = azurerm_resource_group.main.name   # the RG
  sku_name            = "WAF_v2"
  # (WAF_v2 is elastic — no capacity arg needed)

  gateway_ip_configuration {                     # the gateway IP config
    name                              = "gwip"    # the name
    subnet_id                         = azurerm_subnet.appgw.id   # the subnet
    private_ip_allocation_method      = "Dynamic"   # dynamic allocation
  }

  frontend_ip_configuration {                    # the frontend IP config
    name          = "feip"                       # the name
    subnet_id     = azurerm_subnet.appgw.id      # the subnet
  }

  frontend_port {                                # the HTTP frontend port
    name = "http"                                # the name
    port = 80                                    # the port
  }
  frontend_port {                                # the HTTPS frontend port
    name = "https"                               # the name
    port = 443                                   # the port
  }

  backend_address_pool {                         # the backend pool
    name = "backend"                             # the name
    # (IP addresses of the backend VMs / or a VMSS)
    ip_addresses = [ azurerm_linux_virtual_machine.app.private_ip_address ]   # the backends
  }

  probe {                                        # the health probe
    name      = "probe"                          # the name
    protocol  = "Http"                           # the protocol
    port      = 80                               # the port
    path      = "/healthz"                       # the path
    interval  = 30                               # probe every 30 s
    number_of_probes = 2                         # 2 failures = unhealthy
  }

  http_listener {                                # the HTTP listener
    name                           = "http"      # the name
    frontend_ip_configuration_name = "feip"      # the frontend IP config
    frontend_port_name             = "http"      # the frontend port
    protocol                       = "Http"      # the protocol
  }

  request_routing_rule {                         # the routing rule
    name               = "route-http"            # the name
    rule_type          = "Basic"                 # a basic rule
    http_listener_name = "http"                  # the listener
    backend_address_pool_id = azurerm_application_gateway.main.backend_address_pool[0].id   # the backend pool
    probe_id           = azurerm_application_gateway.main.probe[0].id   # the probe
  }

  # (For TLS: a server_certificate + an https listener)
  # server_certificate {
  #   name  = "app"
  #   data  = base64encode(file("cert.pfx"))
  #   password = "..."
  # }
  # http_listener {
  #   name                           = "https"
  #   frontend_ip_configuration_name = "feip"
  #   frontend_port_name             = "https"
  #   protocol                       = "Https"
  #   server_certificate_id          = azurerm_application_gateway.main.server_certificate[0].id
  # }

  identity {                                     # the identity
    type = "SystemAssigned"                      # a system-assigned identity
  }

  tags = local.common_tags                       # the common tags
}
```

> **Note:** `sku_name = "WAF_v2"` / `"Standard_v2"` is **elastic** (auto-scales, no fixed `capacity`). The v1 SKUs (`WAF_v1`/`Standard_v1`) take a `capacity` (units). Use **v2** in prod.

## 7.3 LB vs App Gateway (Azure)

| | **Load Balancer** | **Application Gateway** |
|---|---|---|
| Layer | L4 (TCP/UDP) | L7 (HTTP/HTTPS) |
| Path/host routing | ❌ | ✅ |
| TLS termination | ❌ (passthrough) | ✅ |
| WAF | ❌ | ✅ (WAF_v2) |
| SKU | Basic/Standard | Standard_v1/WAF_v1, **Standard_v2/WAF_v2 (elastic)** |
| Use | TCP/UDP, fixed IP | Web/API, routing, TLS, WAF |

- **LB** = the "NLB" (L4). **App Gateway** = the "ALB" (L7 + WAF).
- For a **web app**: **App Gateway** (L7, TLS, WAF) in front of a **VMSS**.
- For **TCP/UDP / fixed IP / high-perf**: **LB**.

## 7.4 Getting It Right / Gotchas

- **App GW needs a dedicated subnet** (its own CIDR, /24).
- **WAF_v2 / Standard_v2** = elastic (no `capacity`); v1 takes `capacity`.
- **Probe** = the health check (path/port/interval).
- **NSG**: allow the **`AzureLoadBalancer`** source for the LB probe (built-in default rule).
- **TLS**: App GW terminates TLS (needs a **certificate**, typically from **Key Vault**).
- **Standard SKU** (public IP + LB) for prod.
- **`ip_addresses`** in the backend pool = the backend VMs (or a VMSS).
- **Front Door** = the global CDN + L7 (for global routing/Caching) — above App GW.

## 7.5 Interview Quick Facts

- **LB** = L4 (like AWS NLB); **App Gateway** = L7 + WAF (like AWS ALB + WAF).
- **App GW** = path/host routing, TLS termination, WAF, dedicated subnet.
- **v2 SKU** (Standard_v2/WAF_v2) = elastic (no fixed capacity); **v1** = fixed capacity.
- **Probe** = health check.
- **LB** uses the **`AzureLoadBalancer`** NSG source (built-in allow).
- **Front Door** = global CDN + L7 (global tier, above App GW).
