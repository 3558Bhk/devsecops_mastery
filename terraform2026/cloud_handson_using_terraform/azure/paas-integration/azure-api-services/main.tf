# ============================================================================
#  Azure API Services (API Management) — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

resource "azurerm_resource_group" "lab" {        # the resource group
  name     = "rg-lab-apim"                       # the group's name
  location = var.region      # <- set in variables.tf (the region everything is built in)
}

resource "azurerm_api_management" "lab" {        # the APIM service
  name                = "apim-lab"              # the service's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG

  sku_name            = "Developer_1"           # the SKU (Developer_1 = the cheapest dedicated)

  publisher_name      = "Lab Publisher"         # the publisher's name (shown in the portal)
  publisher_email     = "publisher@example.com" # the publisher's email (CHANGE)
}

resource "azurerm_api_management_product" "lab" {   # the product
  api_management_name = azurerm_api_management.lab.name   # which service
  resource_group_name = azurerm_resource_group.lab.name   # which RG

  display_name        = "Lab Product"           # the product's display name
  product_id          = "lab-product"           # the product's public id (used in the portal)
  published           = true                    # the product is published (visible to consumers)
}

resource "azurerm_api_management_api" "lab" {    # the API
  name                = "api-lab"               # the API's id (used in URLs)
  api_management_name = azurerm_api_management.lab.name   # which service
  resource_group_name = azurerm_resource_group.lab.name   # which RG

  display_name        = "Lab API"               # the API's display name
  revision            = "1"                     # the API's revision (version)
  path                = "lab"                   # the API's base path (the gateway prefix)
  service_url         = "https://httpbin.org"   # the BACKEND the gateway proxies to (CHANGE)
  subscription_required = false                 # (false = no key needed; true = require a key)
  protocols           = ["https"]               # the protocols the gateway accepts
}

resource "azurerm_api_management_product_api" "lab" {   # the API → product link
  api_management_name = azurerm_api_management.lab.name   # which service
  api_name            = azurerm_api_management_api.lab.name   # which API
  product_id          = azurerm_api_management_product.lab.product_id   # which product
  resource_group_name = azurerm_resource_group.lab.name   # which RG
}
