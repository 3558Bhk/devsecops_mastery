# Azure 11 — Capstone: A Complete 3-Tier Web App

> **⏱️ Time to complete: ~2.5–3 hrs** (full hands-on build: VNet → AppGW/VMSS → Azure SQL → Key Vault)

The "put it all together" build on Azure:

```
Public DNS → App Gateway (L7, TLS, WAF)
   → VMSS (web, private subnet)
   → Azure SQL (private, isolated subnet, firewall from app)
   + Storage (static assets + logs), Key Vault (secrets), Managed Identity,
     Log Analytics (monitoring), NSGs, tags
```

## 11.1 File Layout

```
capstone/
├── versions.tf
├── backend.tf
├── providers.tf
├── variables.tf
├── locals.tf
├── network.tf        # RG, VNet, subnets, NSGs, DNS
├── identity.tf       # managed identity, Key Vault
├── compute.tf        # VMSS
├── gateway.tf        # App Gateway + WAF
├── database.tf       # Azure SQL
├── storage.tf        # storage account
├── monitoring.tf     # Log Analytics, diagnostics, alerts
└── outputs.tf
```

## 11.2 `versions.tf`

```hcl
terraform {                          # the terraform config block
  required_version = ">= 1.9"        # require Terraform 1.9+
  required_providers {               # declare providers
    azurerm = { source = "hashicorp/azurerm"; version = "~> 5.0" }   # the Azure provider (5.x)
    random  = { source = "hashicorp/random"; version = "~> 3.0" }    # the random provider (3.x)
  }
}
```

## 11.3 `providers.tf`

```hcl
provider "azurerm" {                  # configure the Azure provider
  client_id       = var.client_id     # the SP's app id
  client_secret   = var.client_secret # the SP's secret
  tenant_id       = var.tenant_id     # the tenant
  subscription_id = var.subscription_id   # the subscription

  features {                           # the features block (required)
    key_vault {                        # Key Vault tuning
      purge_protection_enabled   = false   # allow purge
      soft_delete_retention_days = 90      # soft-delete retention
    }
  }
}
```

## 11.4 `variables.tf`

```hcl
variable "project"         { type = string; default = "webapp" }     # the project
variable "environment"     { type = string; default = "dev" }        # the environment
variable "location"        { type = string; default = "australiacentral" }   # the region
variable "client_id"       { type = string; sensitive = true }       # the SP's app id
variable "client_secret"   { type = string; sensitive = true }       # the SP's secret
variable "tenant_id"       { type = string; default = "" }           # the tenant
variable "subscription_id" { type = string; default = "" }           # the subscription
variable "rg_name"         { type = string; default = "rg-webapp" }  # the RG name
variable "ssh_public_key"  { type = string; default = "" }           # (optional) SSH key
variable "domain"          { type = string; default = "example.com" }    # the domain
variable "webhook_url"     { type = string; default = "" }           # (optional) webhook
```

## 11.5 `locals.tf`

```hcl
data "azurerm_client_config" "current" {}   # the current identity

locals {                                      # named expressions
  name_prefix = "${var.project}-${var.environment}"   # e.g. "webapp-dev"
  prod        = (var.environment == "prod")           # true only in prod
  common_tags = {                                   # the common tags
    Project     = var.project                        #  project
    Environment = var.environment                    #  environment
    ManagedBy   = "terraform"                        #  managed-by
    CostCenter  = "1001"                             #  cost center
  }
}
```

## 11.6 `network.tf`

```hcl
resource "azurerm_resource_group" "main" {   # the resource group
  name     = var.rg_name                     # the name
  location = var.location                    # the location
  tags     = local.common_tags               # the common tags
}

resource "azurerm_virtual_network" "main" {   # the VNet
  name                = "${local.name_prefix}-vnet"   # the name
  location            = azurerm_resource_group.main.location   # the location
  resource_group_name = azurerm_resource_group.main.name   # the RG
  address_space       = ["10.0.0.0/16"]      # the VNet CIDR
  tags                = local.common_tags    # the common tags
}

resource "azurerm_subnet" "app" {             # the app subnet
  name                 = "${local.name_prefix}-app"   # the name
  resource_group_name  = azurerm_resource_group.main.name   # the RG
  virtual_network_name = azurerm_virtual_network.main.name  # the VNet
  address_prefixes     = ["10.0.1.0/24"]     # the CIDR
  network_security_group_id = azurerm_network_security_group.app.id   # the app NSG
  service_endpoints    = ["Microsoft.Sql"]   # the SQL service endpoint
}

resource "azurerm_subnet" "db" {              # the db subnet
  name                 = "${local.name_prefix}-db"   # the name
  resource_group_name  = azurerm_resource_group.main.name   # the RG
  virtual_network_name = azurerm_virtual_network.main.name  # the VNet
  address_prefixes     = ["10.0.2.0/24"]     # the CIDR
  network_security_group_id = azurerm_network_security_group.db.id   # the db NSG
}

resource "azurerm_subnet" "appgw" {           # the app gateway subnet
  name                 = "${local.name_prefix}-appgw"   # the name
  resource_group_name  = azurerm_resource_group.main.name   # the RG
  virtual_network_name = azurerm_virtual_network.main.name  # the VNet
  address_prefixes     = ["10.0.3.0/24"]     # the CIDR
}

# App NSG: allow 80/443 from the App Gateway subnet
resource "azurerm_network_security_group" "app" {   # the app NSG
  name                = "${local.name_prefix}-app-nsg"   # the name
  location            = azurerm_resource_group.main.location   # the location
  resource_group_name = azurerm_resource_group.main.name   # the RG
  tags                = local.common_tags    # the common tags
}

resource "azurerm_network_security_rule" "app_http" {   # allow HTTP from the App GW
  name                        = "allow-appgw-http"   # the rule name
  priority                    = 100               # the priority
  direction                   = "Inbound"         # inbound
  access                      = "Allow"           # allow
  protocol                    = "Tcp"             # the protocol
  source_port_range           = "*"               # any source port
  destination_port_range      = "80"              # to port 80
  source_address_prefix       = azurerm_subnet.appgw.id   # from the App GW subnet
  destination_address_prefix  = "*"               # any destination
  network_security_group_name = azurerm_network_security_group.app.name   # the NSG
  resource_group_name         = azurerm_resource_group.main.name   # the RG
}

resource "azurerm_network_security_rule" "app_https" {   # allow HTTPS from the App GW
  name                        = "allow-appgw-https"   # the rule name
  priority                    = 110               # the priority
  direction                   = "Inbound"         # inbound
  access                      = "Allow"           # allow
  protocol                    = "Tcp"             # the protocol
  source_port_range           = "*"               # any source port
  destination_port_range      = "443"             # to port 443
  source_address_prefix       = azurerm_subnet.appgw.id   # from the App GW subnet
  destination_address_prefix  = "*"               # any destination
  network_security_group_name = azurerm_network_security_group.app.name   # the NSG
  resource_group_name         = azurerm_resource_group.main.name   # the RG
}

# DB NSG: allow SQL (1433) from the app subnet only
resource "azurerm_network_security_group" "db" {   # the db NSG
  name                = "${local.name_prefix}-db-nsg"   # the name
  location            = azurerm_resource_group.main.location   # the location
  resource_group_name = azurerm_resource_group.main.name   # the RG
  tags                = local.common_tags    # the common tags
}

resource "azurerm_network_security_rule" "db_sql" {   # allow SQL from the app subnet
  name                        = "allow-app-sql"   # the rule name
  priority                    = 100              # the priority
  direction                   = "Inbound"        # inbound
  access                      = "Allow"          # allow
  protocol                    = "Tcp"            # the protocol
  source_port_range           = "*"              # any source port
  destination_port_range      = "1433"           # to SQL
  source_address_prefix       = azurerm_subnet.app.id   # from the app subnet
  destination_address_prefix  = "*"              # any destination
  network_security_group_name = azurerm_network_security_group.db.name   # the NSG
  resource_group_name         = azurerm_resource_group.main.name   # the RG
}

# Public IP + DNS
resource "azurerm_public_ip" "appgw" {           # a public IP for the App GW
  name                = "${local.name_prefix}-appgw-ip"   # the name
  location            = azurerm_resource_group.main.location   # the location
  resource_group_name = azurerm_resource_group.main.name   # the RG
  allocation_method   = "Static"               # static allocation
  sku_name            = "Standard"             # Standard SKU
}

resource "azurerm_dns_zone" "main" {             # a public DNS zone
  name                = var.domain               # the zone name
  resource_group_name = azurerm_resource_group.main.name   # the RG
}

resource "azurerm_dns_a_record" "www" {          # the www A record
  name            = "www"                        # the record name
  zone_name       = azurerm_dns_zone.main.name   # the zone
  ttl             = 300                          # the TTL
  a_record_values = [azurerm_public_ip.appgw.ip_address]   # the App GW's IP
}
```

## 11.7 `identity.tf` (managed identity + Key Vault)

```hcl
resource "azurerm_user_assigned_identity" "app" {   # a user-assigned identity
  name                = "${local.name_prefix}-app-identity"   # the name
  resource_group_name = azurerm_resource_group.main.name   # the RG
  location            = azurerm_resource_group.main.location   # the location
}

resource "azurerm_key_vault" "kv" {            # a Key Vault
  name                = replace(local.name_prefix, "-", "")   # no hyphens, globally unique
  location            = azurerm_resource_group.main.location   # the location
  resource_group_name = azurerm_resource_group.main.name   # the RG
  tenant_id           = data.azurerm_client_config.current.tenant_id   # the tenant
  sku_name            = "standard"             # the SKU
  soft_delete_retention_days = 90              # soft-delete retention
  purge_protection_enabled   = local.prod      # purge protection (prod)
  enabled_for_deployment     = true            # allow VM deployments
}

resource "azurerm_key_vault_secret" "db_password" {   # the DB password secret
  name         = "db-password"                   # the secret name
  key_vault_id = azurerm_key_vault.kv.id         # the Key Vault
  value        = random_password.sql.result      # the value
  content_type = "text/plain"                    # the content type
}

# Grant the identity access to the secret (RBAC)
resource "azurerm_role_assignment" "kv" {           # a role assignment
  scope                = azurerm_key_vault.kv.id    # the scope (the Key Vault)
  role_definition_name = "Key Vault Secrets User"   # the role
  principal_id         = azurerm_user_assigned_identity.app.principal_id   # the identity
}
```

## 11.8 `compute.tf` (VMSS)

```hcl
resource "azurerm_linux_virtual_machine_scale_set" "web" {   # a Linux VMSS
  name                = "${local.name_prefix}-web-vmss"   # the name
  location            = azurerm_resource_group.main.location   # the location
  resource_group_name = azurerm_resource_group.main.name   # the RG
  sku_name            = "Standard_B2s"   # the VM size
  capacity            = 2                 # the current count
  min_capacity        = 2                 # the minimum
  max_capacity        = 6                 # the maximum
  autoscale_enabled   = true              # enable autoscale
  upgrade_mode        = "Manual"          # the upgrade mode

  os_disk {                                    # the OS disk
    caching              = "ReadWrite"         # the caching mode
    storage_account_type = "StandardSSD_LRS"   # the disk type
  }
  source_image_reference {                     # the marketplace image
    publisher = "Canonical"                    # the publisher
    offer     = "0001-com-ubuntu-server-jammy" # the offer
    sku       = "22_04-lts"                    # the SKU
    version   = "latest"                       # the version
  }

  network_interface {                          # the network interface
    name    = "nic"                            # the NIC name
    primary = true                             # the primary NIC
    ip_configuration {                         # the IP configuration
      name                           = "ipconfig"   # the config name
      primary                        = true         # primary
      subnet_id                      = azurerm_subnet.app.id   # the app subnet
    }
  }

  os_profile {                                 # the OS profile
    computer_name_prefix = "web"               # the computer name prefix
    admin_username       = "azureuser"         # the admin user
    linux_configuration {                       # the Linux config
      disable_password_authentication = true   # no password auth
      ssh_keys {                                 # the SSH key
        path     = "/home/azureuser/.ssh/authorized_keys"   # where to put it
        key_data = var.ssh_public_key           # the public key
      }
    }
  }

  identity {                                   # the identity
    type         = "UserAssigned"             # a user-assigned identity
    identity_ids = [azurerm_user_assigned_identity.app.id]   # the identity
  }

  tags = local.common_tags                     # the common tags
}
```

## 11.9 `gateway.tf` (App Gateway + WAF)

```hcl
resource "azurerm_application_gateway" "main" {   # the Application Gateway
  name                = "${local.name_prefix}-appgw"   # the name
  location            = azurerm_resource_group.main.location   # the location
  resource_group_name = azurerm_resource_group.main.name   # the RG
  sku_name            = "WAF_v2"               # WAF v2 (elastic)

  gateway_ip_configuration {                     # the gateway IP config
    name                         = "gwip"        # the name
    subnet_id                    = azurerm_subnet.appgw.id   # the App GW subnet
    private_ip_allocation_method = "Dynamic"     # dynamic allocation
    public_ip_address_id         = azurerm_public_ip.appgw.id   # the public IP
  }

  frontend_ip_configuration {                    # the frontend IP config
    name      = "feip"                           # the name
    subnet_id = azurerm_subnet.appgw.id          # the App GW subnet
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
    # (VMSS provides the backends; in a full build, reference the pool)
    ip_addresses = []   # (populated by the VMSS / or an explicit pool)
  }

  probe {                                        # the health probe
    name             = "probe"                   # the name
    protocol         = "Http"                    # the protocol
    port             = 80                        # the port
    path             = "/healthz"                # the path
    interval         = 30                        # probe every 30 s
    number_of_probes = 2                         # 2 failures = unhealthy
  }

  http_listener {                                # the HTTP listener
    name                           = "http"      # the name
    frontend_ip_configuration_name = "feip"      # the frontend IP config
    frontend_port_name             = "http"      # the frontend port
    protocol                       = "Http"      # the protocol
  }

  request_routing_rule {                         # the routing rule
    name                      = "route-http"     # the name
    rule_type                 = "Basic"          # a basic rule
    http_listener_name        = "http"           # the listener
    backend_address_pool_id   = azurerm_application_gateway.main.backend_address_pool[0].id   # the backend pool
    probe_id                  = azurerm_application_gateway.main.probe[0].id   # the probe
  }

  waf_configuration {                            # the WAF configuration
    enabled        = true                        # WAF enabled
    firewall_policy_id = null   # (inline WAF; or reference a standalone policy)
  }

  identity {                                     # the identity
    type = "SystemAssigned"                      # a system-assigned identity
  }

  tags = local.common_tags                       # the common tags
}
```

## 11.10 `database.tf`

```hcl
resource "random_password" "sql" {              # a random SQL password
  length  = 20                                  # 20 chars
  special = false                               # no special chars
}

resource "azurerm_mssql_server" "main" {        # an Azure SQL server
  name                         = replace(local.name_prefix, "-", "")   # globally unique
  location                     = azurerm_resource_group.main.location   # the location
  resource_group_name          = azurerm_resource_group.main.name   # the RG
  administrator_login          = "sqladmin"     # the admin user
  administrator_login_password = random_password.sql.result   # the admin password
  version                      = "12.0"          # the SQL version
  minimum_tls_version          = "1.2"           # minimum TLS
  tags                         = local.common_tags   # the common tags
}

resource "azurerm_mssql_firewall_rule" "app" {   # a firewall rule (allow the app subnet)
  name                  = "app-subnet"           # the rule name
  resource_group_name   = azurerm_resource_group.main.name   # the RG
  server_name           = azurerm_mssql_server.main.name   # the server
  start_ip_address      = "10.0.1.0"             # the start IP
  end_ip_address        = "10.0.1.255"           # the end IP
}

resource "azurerm_mssql_database" "app" {        # an Azure SQL database
  name                = "app"                    # the database name
  resource_group_name = azurerm_resource_group.main.name   # the RG
  server_id           = azurerm_mssql_server.main.id   # the server
  sku_name            = "Standard"               # the SKU
  max_size_gb         = 250                      # auto-grow to 250 GB
  zone_redundant      = local.prod               # HA (prod)
  tags                = local.common_tags        # the common tags
}
```

## 11.11 `storage.tf`

```hcl
resource "azurerm_storage_account" "assets" {   # a storage account for assets
  name                     = replace(local.name_prefix, "-", "")   # globally unique
  resource_group_name      = azurerm_resource_group.main.name   # the RG
  location                 = azurerm_resource_group.main.location   # the location
  account_tier             = "Standard"      # the tier
  account_replication_type = "LRS"           # the replication
  https_only_enabled       = true            # force HTTPS
  min_tls_version          = "TLS1_2"        # minimum TLS
  tags                     = local.common_tags   # the common tags
}

resource "azurerm_storage_container" "assets" {   # a blob container
  name                  = "assets"               # the container name
  storage_account_name  = azurerm_storage_account.assets.name   # the storage account
  public_access_level   = "None"                 # private by default
}
```

## 11.12 `monitoring.tf`

```hcl
resource "azurerm_log_analytics_workspace" "main" {   # a Log Analytics workspace
  name                = "${local.name_prefix}-law"    # the name
  location            = azurerm_resource_group.main.location   # the location
  resource_group_name = azurerm_resource_group.main.name   # the RG
  sku                 = "PerGB2018"          # the SKU
  retention_in_days   = 30                   # the retention
}

resource "azurerm_monitor_diagnostic_setting" "vmss" {   # diagnostics for the VMSS
  name               = "${local.name_prefix}-vmss-diag"  # the name
  target_resource_id = azurerm_linux_virtual_machine_scale_set.web.id   # the VMSS
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id   # the workspace

  log {                                      # a log category
    category = "LinuxSyslog"                 # the category
    enabled  = true                          # enabled
  }
  metric {                                   # a metric category
    category = "AllMetrics"                  # all metrics
    enabled  = true                          # enabled
  }
}

resource "azurerm_action_group" "ops" {         # an action group
  name                = "${local.name_prefix}-ops"   # the name
  short_name          = "ops"                    # the short name
  resource_group_name = azurerm_resource_group.main.name   # the RG
  location            = azurerm_resource_group.main.location   # the location

  webhook {                                    # a webhook action
    receiver_type = "Webhook"                  # the receiver type
    name          = "notify"                   # the name
    webhook_url   = var.webhook_url            # the webhook URL
  }
}

resource "azurerm_monitor_metric_alert" "cpu" {   # a CPU metric alert
  name                = "${local.name_prefix}-cpu"   # the name
  resource_group_name = azurerm_resource_group.main.name   # the RG
  scopes              = [azurerm_linux_virtual_machine_scale_set.web.id]   # the VMSS

  criterion {                                  # the criterion
    metric_name      = "Percentage CPU"        # the metric
    aggregation      = "Average"               # the aggregation
    operator         = "GreaterThan"           # the operator
    threshold        = 80                      # the threshold
    time_granularity = "PT1M"                  # the granularity
  }

  action {                                     # the action
    action_group_id = azurerm_action_group.ops.id   # the action group
  }
  severity = "Warning"                         # the severity
}
```

## 11.13 `outputs.tf`

```hcl
output "appgw_frontend_ip" { value = azurerm_public_ip.appgw.ip_address }          # the App GW's IP
output "appgw_fqdn"        { value = azurerm_application_gateway.main.hostname }   # the App GW's FQDN
output "site_url"          { value = "http://www.${var.domain}" }                  # the site URL
output "sql_server_fqdn"   { value = azurerm_mssql_server.main.fully_qualified_domain_name }   # the SQL FQDN
output "storage_account"   { value = azurerm_storage_account.assets.name }         # the storage account
output "key_vault_uri"     { value = azurerm_key_vault.kv.vault_uri }              # the Key Vault URI
output "subscription"      { value = data.azurerm_client_config.current.subscription_id }   # the subscription
```

## 11.14 Build & Verify

```bash
terraform init
terraform plan -out=plan
terraform apply plan
# 1) curl http://www.<domain>/healthz → 200
# 2) az sql db show --resource-group rg --server <server> --name app
# 3) az keyvault secret show --vault-name <vault> --name db-password
terraform plan   # → "No changes" (idempotent!)
```

**Teardown** (dev): `terraform destroy -auto-approve`

## 11.15 What to Study in This Capstone

1. **Dependency order**: RG → VNet → subnets/NSGs → (AppGW / VMSS / SQL).
2. **Isolation**: the DB subnet is only reachable from the app subnet (NSG) + SQL firewall.
3. **L7 + WAF**: App Gateway (`WAF_v2`) in front of the VMSS; TLS + WAF.
4. **Identity**: **managed identity** on the VMSS + **Key Vault** RBAC for the DB password.
5. **Monitoring**: Log Analytics + diagnostic settings + metric alert → action group.
6. **Naming**: globally-unique names (storage, key vault, SQL) via `replace`/prefix.
7. **`local.prod`** gates: `zone_redundant`, `purge_protection`, etc.

## 11.16 Extend It (your homework)

- [ ] Add a **Cosmos DB** account for sessions.
- [ ] Add a **Private Endpoint** for the SQL server (fully private).
- [ ] Add **App Insights** + wire into the VMSS app.
- [ ] Split `network` into its **own root module** + `terraform_remote_state`.
- [ ] Add **Front Door** (global CDN) in front of the App Gateway.
- [ ] Add **autoscale** on the VMSS (CPU).
- [ ] Add a **second environment** (staging) as a separate root module.
