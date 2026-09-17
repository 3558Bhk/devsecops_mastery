# ============================================================================
#  Azure Functions — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

resource "azurerm_resource_group" "lab" {        # the resource group
  name     = "rg-lab-func"                       # the group's name
  location = var.region      # <- set in variables.tf (the region everything is built in)
}

resource "azurerm_service_plan" "lab" {          # the plan
  name                = "asp-func"              # the plan's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
  os_type             = "Linux"                 # the OS type (Linux)
  sku_name            = "Y1"                    # the SKU (Y1 = Consumption)
}

resource "random_string" "suffix" {              # a random suffix for the account name
  length  = 8                                    # 8 characters
  special = false                                # no special chars
  lower = true                               # lowercase only
}

resource "azurerm_storage_account" "func" {      # the storage account
  name                = "storfunc${random_string.suffix.result}"   # a unique name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
  account_tier            = "Standard"          # the tier
  account_replication_type = "LRS"              # the replication
  https_traffic_only_enabled = true             # force HTTPS
  min_tls_version         = "TLS1_2"            # the minimum TLS version
}

resource "azurerm_linux_function_app" "lab" {    # the Function App
  name                = "funcapp-lab"           # the app's name (globally unique)
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
  service_plan_id     = azurerm_service_plan.lab.id   # which plan

  # STORAGE: wired via the managed identity (no connection string / no key)
  storage_account_name      = azurerm_storage_account.func.name   # which storage account
  storage_uses_managed_identity = true                  # use the identity (not a key)

  identity {                                  # the app's identity
    type = "SystemAssigned"                   # a system-assigned identity
  }

  functions_extension_version = "~4"          # the Functions host version

  https_only          = true                 # force HTTPS

  # The app's settings (the worker runtime + a sample config)
  app_settings = {                            # the settings (key/value)
    "FUNCTIONS_WORKER_RUNTIME" = "python"     # the worker runtime (python)
    "SAMPLE_CONFIG"            = "hello"      # a sample config value
  }

  site_config {                                   # the site config
    always_on = false                           # keep-alive (false on Consumption)
  }
}
