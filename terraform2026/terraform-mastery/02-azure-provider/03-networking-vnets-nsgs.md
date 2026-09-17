# Azure 3 — Networking (VNet, Subnets, NSGs, NICs, Routes)

> **⏱️ Time to complete: ~75 min** (read + deploy the VNet + subnets + NSGs)

## 3.1 The Mental Model

```
VNet (e.g. 10.0.0.0/16)
├── Subnet /app  (10.0.1.0/24)   → NSG app   → NSG allows 80/443 from LB
├── Subnet /db   (10.0.2.0/24)   → NSG db    → NSG allows 5432 from app subnet only
├── Subnet /gw   (gateway subnet, if VPN)
└── (service endpoints for Storage/SQL → private API access)

Public IP → Load Balancer / NIC → VM
Route Table (UDR) → override next-hop (VPN, appliance)
```

Key concepts:
- **Virtual Network (VNet)** = the private network (a CIDR).
- **Subnet** = a CIDR slice inside the VNet (NOT AZ-tied like AWS — AZs are a VM/pool property).
- **NSG (Network Security Group)** = stateful firewall; applied at **subnet** or **NIC** level; **Inbound/Outbound** rules with **priority (100–4096, lower = higher priority)**; **Allow/Deny** (last matching rule wins by priority).
- **NIC** = the interface; can have its own NSG (overrides/combines with the subnet NSG).
- **Public IP** = the public address (attached to a NIC, LB, or App Gateway).
- **Route table (UDR)** = user-defined routes (override next-hop).
- **Service endpoints** = private access to Azure services (Storage, SQL) from a subnet without public exposure.
- **VNet peering** = connect two VNets.

> **NSG evaluation**: rules are evaluated **by priority (100→4096)**; the **first match wins** (Allow or Deny). If no rule matches, **default-deny** (inbound) / **default-allow** (outbound). There are built-in **default rules** (e.g. DenyAllInbound at 65500, AllowVNetInbound, AllowAzureLoadBalancerInbound).

## 3.2 A Complete VNet + Subnets + NSGs

```hcl
locals {                                      # named expressions
  name_prefix = "${var.project}-${var.environment}"   # e.g. "webapp-dev"
}

resource "azurerm_virtual_network" "main" {   # create the VNet
  name                = "${local.name_prefix}-vnet"   # the name
  location            = azurerm_resource_group.main.location   # the location
  resource_group_name = azurerm_resource_group.main.name   # the RG
  address_space       = ["10.0.0.0/16"]      # the VNet CIDR
  tags                = local.common_tags    # the common tags
}

# App subnet
resource "azurerm_subnet" "app" {             # the app subnet
  name                 = "${local.name_prefix}-app"   # the name
  resource_group_name  = azurerm_resource_group.main.name   # the RG
  virtual_network_name = azurerm_virtual_network.main.name  # the VNet
  address_prefixes     = ["10.0.1.0/24"]     # the subnet CIDR
  network_security_group_id = azurerm_network_security_group.app.id   # the app NSG
  # service_endpoints = ["Microsoft.Storage", "Microsoft.Sql"]   # (optional)
}

# DB subnet (isolated — only reachable from app)
resource "azurerm_subnet" "db" {              # the db subnet
  name                 = "${local.name_prefix}-db"   # the name
  resource_group_name  = azurerm_resource_group.main.name   # the RG
  virtual_network_name = azurerm_virtual_network.main.name  # the VNet
  address_prefixes     = ["10.0.2.0/24"]     # the subnet CIDR
  network_security_group_id = azurerm_network_security_group.db.id   # the db NSG
}

# App NSG: allow 80/443 from the load balancer, all outbound
resource "azurerm_network_security_group" "app" {   # the app NSG
  name                = "${local.name_prefix}-app-nsg"   # the name
  location            = azurerm_resource_group.main.location   # the location
  resource_group_name = azurerm_resource_group.main.name   # the RG
  tags                = local.common_tags    # the common tags
}

resource "azurerm_network_security_rule" "app_http" {   # allow HTTP from the VNet
  name                        = "allow-lb-http"   # the rule name
  priority                    = 100               # the priority (lower = first)
  direction                   = "Inbound"         # inbound
  access                      = "Allow"           # allow
  protocol                    = "Tcp"             # the protocol
  source_port_range           = "*"               # any source port
  destination_port_range      = "80"              # to port 80
  source_address_prefix       = "VirtualNetwork"      # (or the LB's subnet)
  destination_address_prefix  = "*"               # any destination
  network_security_group_name = azurerm_network_security_group.app.name   # the NSG
  resource_group_name         = azurerm_resource_group.main.name   # the RG
}

resource "azurerm_network_security_rule" "app_https" {   # allow HTTPS from the VNet
  name                        = "allow-lb-https"   # the rule name
  priority                    = 110               # the priority
  direction                   = "Inbound"         # inbound
  access                      = "Allow"           # allow
  protocol                    = "Tcp"             # the protocol
  source_port_range           = "*"               # any source port
  destination_port_range      = "443"             # to port 443
  source_address_prefix       = "VirtualNetwork"  # from the VNet
  destination_address_prefix  = "*"               # any destination
  network_security_group_name = azurerm_network_security_group.app.name   # the NSG
  resource_group_name         = azurerm_resource_group.main.name   # the RG
}

# DB NSG: allow 5432 from the app subnet only
resource "azurerm_network_security_group" "db" {   # the db NSG
  name                = "${local.name_prefix}-db-nsg"   # the name
  location            = azurerm_resource_group.main.location   # the location
  resource_group_name = azurerm_resource_group.main.name   # the RG
  tags                = local.common_tags    # the common tags
}

resource "azurerm_network_security_rule" "db_pg" {   # allow postgres from the app subnet
  name                        = "allow-app-pg"   # the rule name
  priority                    = 100              # the priority
  direction                   = "Inbound"        # inbound
  access                      = "Allow"          # allow
  protocol                    = "Tcp"            # the protocol
  source_port_range           = "*"              # any source port
  destination_port_range      = "5432"           # to postgres
  source_address_prefix       = azurerm_subnet.app.id      # (or its address prefix)
  destination_address_prefix  = "*"              # any destination
  network_security_group_name = azurerm_network_security_group.db.name   # the NSG
  resource_group_name         = azurerm_resource_group.main.name   # the RG
}
```

### NSG rules via `dynamic` (data-driven)

```hcl
variable "app_rules" {                        # a list of rule objects
  type = list(object({                        # the object type
    name     = string                         # the rule name
    priority = number                         # the priority
    direction = string                        # Inbound/Outbound
    access   = string                         # Allow/Deny
    protocol = string                         # the protocol
    src      = string                         # the source prefix
    dst_port = string                         # the destination port
  }))
}

resource "azurerm_network_security_group" "app" {   # the app NSG
  ...
  dynamic "security_rule" {                    # a dynamic block: repeat the rule
    for_each = var.app_rules                   # once per rule object
    content {                                  # the body of each rule
      name                       = security_rule.value.name          # the name
      priority                   = security_rule.value.priority      # the priority
      direction                  = security_rule.value.direction     # the direction
      access                     = security_rule.value.access        # allow/deny
      protocol                   = security_rule.value.protocol      # the protocol
      source_port_range          = "*"               # any source port
      destination_port_range     = security_rule.value.dst_port     # the destination port
      source_address_prefix      = security_rule.value.src           # the source
      destination_address_prefix = "*"               # any destination
    }
  }
}
```

## 3.3 NIC, Public IP

```hcl
resource "azurerm_public_ip" "app" {           # a public IP
  name                = "${local.name_prefix}-app-ip"   # the name
  location            = azurerm_resource_group.main.location   # the location
  resource_group_name = azurerm_resource_group.main.name   # the RG
  allocation_method   = "Static"               # static allocation
  sku_name            = "Standard"     # (required for Standard LB / App Gateway)
  tags                = local.common_tags    # the common tags
}

resource "azurerm_network_interface" "app" {   # a network interface
  name                = "${local.name_prefix}-app-nic"   # the name
  location            = azurerm_resource_group.main.location   # the location
  resource_group_name = azurerm_resource_group.main.name   # the RG
  network_security_group_id = azurerm_network_security_group.app.id   # (optional; subnet NSG usually suffices)

  ip_configuration {                            # the IP configuration
    name                          = "internal"  # the config name
    subnet_id                     = azurerm_subnet.app.id   # the subnet
    private_ip_allocation_method  = "Dynamic"   # dynamic private IP
    public_ip_address_id          = azurerm_public_ip.app.id   # (attach the public IP)
  }
  tags = local.common_tags                     # the common tags
}
```

> **Standard vs Basic SKU** (public IP, LB): **Standard** is required for App Gateway, Standard LB, and supports zone-redundancy + higher limits. Use **Standard** in prod.

## 3.4 Route Table (UDR)

```hcl
resource "azurerm_route_table" "main" {        # a route table
  name                = "${local.name_prefix}-rt"   # the name
  location            = azurerm_resource_group.main.location   # the location
  resource_group_name = azurerm_resource_group.main.name   # the RG

  routing {                                     # a routing entry
    name           = "to-vpn"                   # the route name
    address_prefix = "10.0.0.0/8"               # the destination prefix
    next_hop_type  = "VirtualNetworkGateway"   # (or "None", "Internet", "VirtualAppliance", "VnetLocal")
  }

  tags = local.common_tags                     # the common tags
}

# attach to a subnet
resource "azurerm_subnet" "app" {              # the app subnet
  ...
  route_table_id = azurerm_route_table.main.id   # the route table to use
}
```

## 3.5 VNet Peering

```hcl
# VNet A
resource "azurerm_virtual_network_peering" "a_to_b" {   # peering A → B
  name                      = "a-to-b"                 # the peering name
  resource_group_name       = azurerm_resource_group.main.name   # the RG
  virtual_network_name      = azurerm_virtual_network.main.name  # VNet A
  remote_virtual_network_id = azurerm_virtual_network.b.id   # VNet B
  allow_virtual_network_access = true   # allow VNet access
  allow_forwarded_traffic    = true     # allow forwarded traffic
  allow_gateway_transit      = false    # no gateway transit
}

resource "azurerm_virtual_network_peering" "b_to_a" {   # peering B → A
  name                      = "b-to-a"                 # the peering name
  resource_group_name       = azurerm_resource_group.b.name   # VNet B's RG
  virtual_network_name      = azurerm_virtual_network.b.name   # VNet B
  remote_virtual_network_id = azurerm_virtual_network.main.id   # VNet A
  allow_virtual_network_access = true   # allow VNet access
}
```
Peering is **bidirectional** (create both sides) and **non-transitive** (A↔B, B↔C ≠ A↔C). For many VNets, use **Virtual WAN (vWAN)**.

## 3.6 Service Endpoints (private access to Azure services)

```hcl
resource "azurerm_subnet" "app" {              # the app subnet
  ...
  service_endpoints = ["Microsoft.Storage", "Microsoft.Sql", "Microsoft.ServiceBus"]   # the services
}
```
- Enables **private** (no public IP) access from the subnet to those services, with NSG control on port 443.
- Pair with **Private Endpoint** (ch. 10) for full private connectivity.

## 3.7 DNS

```hcl
# Public DNS zone
resource "azurerm_dns_zone" "main" {           # a public DNS zone
  name                = "example.com"          # the zone name
  resource_group_name = azurerm_resource_group.main.name   # the RG
}

resource "azurerm_dns_a_record" "www" {        # an A record
  name    = "www"                              # the record name
  zone_name = azurerm_dns_zone.main.name       # the zone
  ttl     = 300                                # the TTL (s)
  a_record_values = [azurerm_public_ip.app.ip_address]   # the target IP
}

# Private DNS (VNet-internal)
resource "azurerm_private_dns_zone" "internal" {   # a private DNS zone
  name                = "internal.example.com"   # the zone name
  resource_group_name = azurerm_resource_group.main.name   # the RG
}
resource "azurerm_private_dns_zone_virtual_network_link" "link" {   # link the zone to a VNet
  name                  = "vnet-link"            # the link name
  resource_group_name   = azurerm_resource_group.main.name   # the RG
  private_dns_zone_name = azurerm_private_dns_zone.internal.name   # the zone
  virtual_network_id    = azurerm_virtual_network.main.id   # the VNet
}
```

## 3.8 Getting It Right / Gotchas

- **NSG priority**: lower = evaluated first; **first match wins** (Allow or Deny). Default-deny inbound, default-allow outbound.
- **Subnet NSG + NIC NSG** both apply (NIC NSG can be more specific); the most specific winning rule applies.
- **Load Balancer health probes** need an NSG allow from the LB (the built-in `AllowAzureLoadBalancerInbound` default rule handles it from the `LoadBalancer` prefix).
- **Standard SKU** for public IP/LB in prod (required by App Gateway).
- **Subnets are NOT AZ-tied** (unlike AWS) — AZs apply to VMs/availability sets/scale sets.
- **Service endpoints** = private API access; **Private Endpoints** = private IP in the VNet (stronger).
- **Peering is bidirectional + non-transitive**.
- **Gateway subnets** (`GatewaySubnet`) are reserved for VPN/ExpressRoute.

## 3.9 Interview Quick Facts

- **VNet → Subnet → NSG → NIC**.
- **NSG** = stateful, priority-based, Allow/Deny, first-match-wins; subnet or NIC level.
- **Standard vs Basic** SKU (public IP/LB) — Standard for prod/App Gateway.
- **Service endpoints** = private service access; **Private endpoints** = private IP.
- **Peering** = bidirectional, non-transitive; **vWAN** for many VNets.
- **Route table (UDR)** = override next-hop.
- **DNS** = public zone / private zone + VNet link.
