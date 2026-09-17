# Azure 10 — Advanced: State Backend, Diagnostics, Private Endpoints & Interop

> **⏱️ Time to complete: ~50 min** (read + attach a diagnostic setting + a metric alert)

## 10.1 Terraform State on Azure (blob backend)

```hcl
terraform {                          # the terraform config block
  backend "azurerm" {                # use the Azure blob backend
    resource_group_name  = "rg-tfstate-global"     # the RG holding the storage account
    storage_account_name = "tfstateglobal"       # (globally unique)
    container_name       = "tfstate"               # the container
    key                  = "network/prod.tfstate"  # the blob key (one per state)
    account_sas_token    = "sv=2026-..."         # (scoped, expiring SAS token)
  }
}
```

- Same pattern as AWS S3: **dedicated storage account**, **container**, **versioning**, **SAS token** (or AAD auth).
- One **state key per service/environment** (`network/prod`, `compute/prod`).

## 10.2 Diagnostics & Monitoring (Log Analytics)

```hcl
# Log Analytics workspace
resource "azurerm_log_analytics_workspace" "main" {   # a Log Analytics workspace
  name                = "${local.name_prefix}-law"    # the name
  location            = azurerm_resource_group.main.location   # the location
  resource_group_name = azurerm_resource_group.main.name   # the RG
  sku                 = "PerGB2018"          # the SKU
  retention_in_days   = 30                   # the retention (days)
}

# Diagnostic settings → stream resource logs/metrics to Log Analytics
resource "azurerm_monitor_diagnostic_setting" "vm" {   # a diagnostic setting
  name               = "${local.name_prefix}-vm-diag"  # the name
  target_resource_id = azurerm_linux_virtual_machine.app.id   # the target resource
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id   # the workspace

  log {                                      # a log category
    category = "LinuxSyslog"                 # the category
    enabled  = true                          # enabled
  }
  log {                                      # another log category
    category = "Journals"                    # the category
    enabled  = true                          # enabled
  }
  metric {                                   # a metric category
    category = "AllMetrics"                  # all metrics
    enabled  = true                          # enabled
  }
}
```

- **Diagnostic settings** = stream **logs + metrics** from any resource to **Log Analytics** (or a storage account / event hub).
- Use **`dynamic`** to attach diagnostics to many resources at once.

### Metric alert

```hcl
resource "azurerm_action_group" "ops" {         # an action group (notification target)
  name                = "${local.name_prefix}-ops"   # the name
  short_name          = "ops"                    # the short name
  resource_group_name = azurerm_resource_group.main.name   # the RG
  location            = azurerm_resource_group.main.location   # the location

  webhook {                                    # a webhook action
    receiver_type = "Webhook"                  # the receiver type
    name          = "teams"                    # the name
    webhook_url   = var.webhook_url            # the webhook URL
  }
}

resource "azurerm_monitor_metric_alert" "cpu" {   # a metric alert
  name                = "${local.name_prefix}-cpu"   # the name
  resource_group_name = azurerm_resource_group.main.name   # the RG
  scopes              = [azurerm_linux_virtual_machine.app.id]   # the target resource(s)
  description         = "High CPU"               # the description

  criterion {                                  # the alert criterion
    metric_name          = "cpu_percent"        # the metric
    aggregation          = "Average"            # the aggregation
    operator             = "GreaterThan"        # the operator
    threshold            = 80                   # the threshold
    time_granularity     = "PT1M"               # the granularity
  }

  action {                                     # the action
    action_group_id = azurerm_action_group.ops.id   # the action group
  }

  severity = "Warning"                         # the severity
}
```

- **Metric alert** = threshold on a metric (→ action group → webhook/email/ITSM).
- **Log alert** = query-based (KQL) alert.
- **Action group** = the notification target.

### Autoscale

```hcl
resource "azurerm_monitor_autoscale_setting" "vmss" {   # an autoscale setting
  name                = "${local.name_prefix}-vmss-autoscale"   # the name
  resource_group_name = azurerm_resource_group.main.name   # the RG
  target_resource_id  = azurerm_linux_virtual_machine_scale_set.web.id   # the target
  mode                = "Enabled"                # enabled

  profile {                                     # the autoscale profile
    name = "default"                            # the profile name
    fixed_date {                                # the active window
      start_date = "2026-01-01T00:00:00Z"       # the start
      end_date   = "2027-01-01T00:00:00Z"       # the end
    }

    rule {                                      # a scaling rule
      metric_availability = "Visualize"         # visualize the metric
      metric {                                   # the metric
        resource_uri = azurerm_linux_virtual_machine_scale_set.web.id   # the resource
        name         = "Percentage CPU"         # the metric name
        aggregation  = "Average"                # the aggregation
      }
      scale_action {                             # the scale action
        direction = "Out"                        # scale out
        type      = "ChangeCount"                # change by count
        value     = "1"                          # by 1
        cooldown  = "PT5M"                       # 5-minute cooldown
      }
      threshold {                                # the threshold
        operator = "GreaterThanOrEqual"         # the operator
        value    = 60                           # the value
      }
    }
  }
}
```

## 10.3 Private Endpoints (fully private connectivity)

```hcl
resource "azurerm_private_endpoint" "sql" {   # a private endpoint
  name                = "${local.name_prefix}-sql-pe"   # the name
  location            = azurerm_resource_group.main.location   # the location
  resource_group_name = azurerm_resource_group.main.name   # the RG
  subnet_id           = azurerm_subnet.app.id      # the subnet

  private_service_connection {                     # the private service connection
    name                           = "pe-connection"   # the name
    private_connection_resource_id = azurerm_mssql_server.main.id   # the service to connect to
    subnets                        = [azurerm_subnet.app.id]   # the subnets
  }

  application_security_group_ids = []            # (optional) app security groups
  tags = local.common_tags                       # the common tags
}
```

- **Private Endpoint** = gives an Azure service (SQL, Storage, Key Vault, …) a **private IP in your VNet** → no public exposure (stronger than service endpoints).
- Pair with **Private DNS** (a private zone linked to the VNet) so name resolution stays private.
- Use for **fully private** architectures (no public ingress at all).

## 10.4 Bicep / ARM Template Interop (deploy an ARM/Bicep template from Terraform)

Sometimes you have an existing **ARM template** (or **Bicep**) you want to deploy *from* Terraform:

```hcl
resource "azurerm_resource" "custom" {        # deploy a custom ARM resource
  name     = "my-custom-resource"             # the name
  type     = "Microsoft.MyProvider/myResource"   # (the ARM type)
  location = azurerm_resource_group.main.location   # the location
  resource_group_name = azurerm_resource_group.main.name   # the RG

  resource_json = jsonencode({                # the ARM template (as JSON)
    sku = { name = "Standard" }               # the SKU
    properties = {                             # the properties
      # (the ARM template properties)
      enabled = true                           # an example property
    }
  })
}
```

- `azurerm_resource` = deploy an **ARM template** (as JSON) for a resource the provider may not model.
- For **Bicep**: compile to ARM (`az bicep build`) and feed the JSON, or use `azurerm_deployment` (at subscription/RG scope) for a full template.
- This is the escape hatch when the provider lacks a resource.

## 10.5 Importing Existing Resources (Azure)

```bash
terraform import azurerm_resource_group.main rg-name
terraform import azurerm_virtual_network.main /subscriptions/<SUB>/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet
```

- The **`id`** is the Azure **resource ID** (a long `/subscriptions/.../providers/...` path).
- Get it from the portal (Properties → Resource ID) or `az network vnet show --id ... --query id`.
- Config must **match** the real resource (else a big diff).

## 10.6 Drift Detection (scheduled)

```bash
terraform plan -refresh-only
terraform plan -detailed-exitcode   # exit 2 = changes → alert
```
Wire into **Azure DevOps** / **GitHub Actions cron** / **Event Grid** + alert on non-zero exit.

## 10.7 CI/CD with OIDC (recap)

- **GitHub Actions** → `azure/login` (federated credential) → provider reads `AZURE_FEDERATED_TOKEN_FILE`.
- **Azure DevOps** → a service connection (OIDC) or a **managed identity** on a self-hosted agent.
- **Plan as PR gate** + **apply on merge** (with human approval for prod).

## 10.8 Getting It Right / Gotchas

- **State on Azure** = blob backend (SAS token or AAD); dedicated storage account.
- **Diagnostics** = stream logs/metrics to **Log Analytics** (dynamic for many resources).
- **Metric/log alerts** → **action group** (notification).
- **Private Endpoint** = private IP for a service (stronger than service endpoints); pair with **Private DNS**.
- **`azurerm_resource`** = deploy an ARM template the provider doesn't model.
- **Import** = the Azure **resource ID** (long path).
- **OIDC** = the modern CI auth (no secrets).

## 10.9 Interview Quick Facts

- **State on Azure** = blob backend (SAS/AAD).
- **Log Analytics** = the monitoring/query store; **diagnostic settings** stream to it.
- **Metric alert** = threshold; **log alert** = KQL query; both → **action group**.
- **Private Endpoint** = private IP for a service (vs service endpoint = private API access).
- **`azurerm_resource`** = ARM template escape hatch.
- **Import id** = the Azure resource ID.
- **OIDC** = CI auth (federated credential).
