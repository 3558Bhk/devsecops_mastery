# Azure 8 — Serverless (Functions, App Service, App Insights)

> **⏱️ Time to complete: ~50 min** (read + create a Function App + a web app)

## 8.1 Function App (the Lambda equivalent)

A **Function App** requires a **storage account** (for state/triggers) and a **service plan**.

```hcl
# Storage (required for Function App)
resource "azurerm_storage_account" "func" {   # a storage account for the Function App
  name                     = local.func_storage_name   # the name (globally unique)
  resource_group_name      = azurerm_resource_group.main.name   # the RG
  location                 = azurerm_resource_group.main.location   # the location
  account_tier             = "Standard"      # the tier
  account_replication_type = "LRS"           # the replication
  https_only_enabled       = true            # force HTTPS
  min_tls_version          = "TLS1_2"        # minimum TLS
}

resource "azurerm_storage_container" "func" {   # a blob container (the web container)
  name                 = "$web"                 # the "$web" container
  storage_account_name = azurerm_storage_account.func.name   # the storage account
}

# Service plan (consumption = pay-per-use, scales to 0)
resource "azurerm_service_plan" "func" {        # a service plan
  name                = "${local.name_prefix}-func-plan"   # the name
  location            = azurerm_resource_group.main.location   # the location
  resource_group_name = azurerm_resource_group.main.name   # the RG
  os_type             = "Linux"                  # the OS
  sku_name            = "Y1"          # (Consumption: Y1; or Premium: EP1)
  maximum_elastic_workers = "1"           # the max elastic workers
}

# The Function App
resource "azurerm_linux_function_app" "app" {   # a Linux Function App
  name                       = "${local.name_prefix}-func"   # the name
  location                   = azurerm_resource_group.main.location   # the location
  resource_group_name        = azurerm_resource_group.main.name   # the RG
  service_plan_id            = azurerm_service_plan.func.id   # the service plan
  storage_account_name       = azurerm_storage_account.func.name   # the storage account
  storage_account_access_key = azurerm_storage_account.func.primary_access_key   # the access key
  # NOTE: there is no top-level `runtime` argument — the runtime is set via
  # app_settings["FUNCTIONS_WORKER_RUNTIME"] in the site_config block below.

  identity {                                   # the identity
    type = "SystemAssigned"                    # a system-assigned identity
  }

  site_config {                                # the site config
    app_settings = {                           # app settings (env vars)
      "FUNCTIONS_WORKER_RUNTIME" = "python"   # the worker runtime
      "WEBSITE_RUN_FROM_PACKAGE" = "1"        # run from a package
      # (app-specific settings)
      "MY_SETTING" = "value"                   # an example setting
    }
    ftp_state = "Disabled"                     # disable FTP
  }

  tags = local.common_tags                     # the common tags
}
```

- **Consumption plan** (`Y1`) = pay-per-use, scales to 0 (best for spiky/serverless).
- **Premium plan** (`EP1`) = always-warm (fewer cold starts) + VPC.
- **Runtime** = set via `app_settings["FUNCTIONS_WORKER_RUNTIME"]` (e.g. `python`, `node`, `dotnet`) — there is no top-level `runtime` argument.
- **`site_config.app_settings`** = environment variables / app settings.
- **`identity`** = managed identity (keyless auth to other Azure services).
- **Storage** = required (triggers/state); a **blob/queue/table** can be the trigger.

### Trigger examples (conceptual — defined in the function code, but the resources exist here)
- **HTTP trigger** = an endpoint (like API Gateway → Lambda).
- **Blob trigger** = on new blob.
- **Queue trigger** = on new queue message.
- **Timer** = scheduled.

## 8.2 App Service Plan + Web App (always-on PaaS)

```hcl
# Plan (the compute underneath)
resource "azurerm_service_plan" "web" {         # a service plan for the web app
  name                = "${local.name_prefix}-web-plan"   # the name
  location            = azurerm_resource_group.main.location   # the location
  resource_group_name = azurerm_resource_group.main.name   # the RG
  os_type             = "Linux"                  # the OS
  sku_name            = "B1"           # (Basic: B1; Standard: S1; Premium: P1v3)
  instance_count      = 2                    # the instance count
}

# Linux web app
resource "azurerm_linux_web_app" "web" {        # a Linux web app
  name                       = "${local.name_prefix}-web"   # the name
  location                   = azurerm_resource_group.main.location   # the location
  resource_group_name        = azurerm_resource_group.main.name   # the RG
  service_plan_id            = azurerm_service_plan.web.id   # the service plan

  site_config {                                # the site config
    always_on      = true                       # keep warm (no cold start)
    http20_enabled = true                       # enable HTTP/2
    app_settings = {                            # app settings
      "WEBSITE_RUN_FROM_PACKAGE" = "1"         # run from a package
      "PYTHON_VERSION"           = "3.11"      # the Python version
    }
  }

  app_stack {                                  # the app stack (runtime)
    python_version = "3.11"                    # the Python version
  }

  identity {                                   # the identity
    type = "SystemAssigned"                    # a system-assigned identity
  }

  tags = local.common_tags                     # the common tags
}
```

- **App Service** = managed **PaaS** for a web app (always-on, autoscale, deployment slots).
- **Plan SKUs**: `F` (free) / `D` (shared) / `B` (basic) / `S` (standard) / `P` (premium) / `EP` (elastic premium).
- **`always_on`** = keep warm (no cold-start on first hit).
- **`app_stack`** = the runtime (python/node/dotnet/java).
- **Windows web app**: `azurerm_windows_web_app` (with `app_stack { dotnet_version = ... }`).

## 8.3 App Insights (application monitoring)

```hcl
resource "azurerm_log_analytics_workspace" "main" {   # a Log Analytics workspace
  name                = "${local.name_prefix}-law"    # the name
  location            = azurerm_resource_group.main.location   # the location
  resource_group_name = azurerm_resource_group.main.name   # the RG
  sku                 = "PerGB2018"          # the SKU
  retention_in_days   = 30                   # the retention (days)
  tags                = local.common_tags    # the common tags
}

resource "azurerm_application_insights" "app" {   # an App Insights resource
  name           = "${local.name_prefix}-ai"     # the name
  location       = azurerm_resource_group.main.location   # the location
  resource_group_name = azurerm_resource_group.main.name   # the RG
  application_type = "web"                       # the app type
  workspace_id   = azurerm_log_analytics_workspace.main.id   # the workspace
  tags           = local.common_tags             # the common tags
}
```

- **App Insights** = APM (requests, exceptions, dependencies, performance).
- Wire it into the Function/Web app via `app_settings["APPINSIGHTS_CONNECTION_STRING"]` (the `connection_string` attribute).
- Backed by a **Log Analytics workspace** (the query store).

## 8.4 Choosing the Compute

| Need | Service |
|---|---|
| Event-driven, spiky, pay-per-use | **Function App** (consumption) |
| Always-on web app (PaaS) | **App Service** (web app) |
| Containers | **AKS** (k8s) / **Container Apps** |
| VMs | **VM** / **VMSS** |

## 8.5 Getting It Right / Gotchas

- **Function App needs a storage account** (required) + a **service plan**.
- **Consumption** (`Y1`) = scales to 0 (serverless); **Premium** (`EP1`) = always-warm + VPC.
- **Runtime** = `app_settings["FUNCTIONS_WORKER_RUNTIME"]` (e.g. `python`, `node`, `dotnet`).
- **App Service** = PaaS web app; **plan SKU** = compute tier (`B`/`S`/`P`/`EP`).
- **`always_on`** = keep warm.
- **`identity`** = managed identity (keyless).
- **App Insights** = APM; needs a **Log Analytics workspace**.
- **`site_config.app_settings`** = env vars / settings.

## 8.6 Interview Quick Facts

- **Function App** = the Lambda equivalent (needs storage + a plan; consumption scales to 0).
- **App Service** = PaaS web app (always-on, autoscale, slots).
- **Consumption vs Premium** (Functions) = pay-per-use vs always-warm.
- **Plan SKUs**: F/D/B/S/P/EP (App Service); Y1/EP1 (Functions).
- **Runtime** = set via the `FUNCTIONS_WORKER_RUNTIME` app setting.
- **App Insights** = APM (backed by Log Analytics).
- **`identity`** = managed identity for keyless auth.
