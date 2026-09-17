# ============================================================================
#  App Service — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

resource "azurerm_resource_group" "lab" {        # the resource group
  name     = "rg-lab-appsvc"                     # the group's name
  location = var.region      # <- set in variables.tf (the region everything is built in)
}

resource "azurerm_service_plan" "lab" {          # the plan
  name                = "asp-lab"                # the plan's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
  os_type             = "Linux"                 # the OS type (Linux)
  sku_name            = "Y1"                    # the SKU (Y1 = Consumption, the cheapest)
}

resource "azurerm_linux_web_app" "lab" {         # the web app
  name                = "webapp-lab"            # the app's name (globally unique)
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
  service_plan_id     = azurerm_service_plan.lab.id   # which plan

  https_only          = true                     # force HTTPS

  # The app's environment variables (config as settings)
  app_settings = {                                # the settings (key/value)
    "WEBSITE_RUN_FROM_PACKAGE" = ""               # (empty = not running from a package)
    "SAMPLE_CONFIG"            = "hello"          # a sample config value
  }

  site_config {                                   # the site config
    always_on          = false                   # keep-alive (false on Consumption)
    minimum_tls_version = "1.2"                  # the minimum TLS version
  }
}
