terraform {                                      # the terraform block: settings about Terraform itself
  required_version = ">= 1.5"                    # minimum Terraform version
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 5.0" }   # Azure provider, any 5.x
  }
}

provider "azurerm" {                             # configure the Azure provider
  features {}                                    # required in v5
}

resource "azurerm_resource_group" "api" {        # the resource group
  name     = "${var.project}-gw-rg"              # e.g. apim-gw-rg
  location = var.location                        # from the input
}

# ── 1. THE BACKEND: a tiny web app the gateway will proxy to ──────────────────

resource "azurerm_service_plan" "app" {          # the compute pool (F1 = free)
  name                = "${var.project}-f1"      # the plan's name
  location            = var.location             # same location
  resource_group_name = azurerm_resource_group.api.name   # which group
  os_type             = "Linux"                  # Linux plan
  sku_name            = "F1"                     # FREE plan
}

resource "azurerm_linux_web_app" "backend" {     # the backend (any service would do: VM, App Service, AKS)
  name                       = "${var.project}-backend-web"   # the app's name
  location                   = var.location             # same location
  resource_group_name        = azurerm_resource_group.api.name   # which group
  service_plan_id            = azurerm_service_plan.app.id      # the free pool
  https_only                 = true                   # force HTTPS

  site_config {}                                       # an empty site_config block is required
}

# ── 2. THE GATEWAY: the single public door ────────────────────────────────────

resource "azurerm_api_management" "gw" {         # the APIM service (the gateway itself)
  name                = "${var.project}-apim-2026"   # 3-50 chars, lowercase, starts with a letter
  location            = var.location              # same location
  resource_group_name = azurerm_resource_group.api.name   # which group

  publisher_name  = "Lab Publisher"              # the publisher shown in the developer portal
  publisher_email = "lab@example.com"            # the publisher's email (shown publicly in the portal)
  sku_name        = "Developer_1"                # 1-unit Developer SKU (the cheapest; ~$0.015/hr)
}

# ── 3. THE API: what the gateway exposes (a proxy to the backend) ────────────

resource "azurerm_api_management_api" "hello" {  # the API resource in APIM
  name                = "hello-api"              # internal name (used in URLs/policies)
  api_management_name = azurerm_api_management.gw.name   # which gateway
  resource_group_name = azurerm_resource_group.api.name   # which group

  path          = "hello"                        # the public path: <gateway>/hello
  revision      = "1"                            # the revision (a new revision = a new version of the API)
  service_url   = "https://${azurerm_linux_web_app.backend.default_hostname}"   # the backend to proxy to
  display_name  = "Hello API"                    # the name in the developer portal

  subscription_required = false                  # lab: open (flip to true to force API keys — see README)
}

# ── 4. THE POLICY: what happens to EVERY request (policies ARE code) ─────────

resource "azurerm_api_management_api_policy" "hello" {   # the API-level policy (runs on all its operations)
  api_management_name = azurerm_api_management.gw.name   # which gateway
  api_name            = azurerm_api_management_api.hello.name   # which API
  resource_group_name = azurerm_resource_group.api.name   # which group

  # APIM policies are XML. This one: rate-limit each client IP to
  # rate_limit_calls calls per rate_limit_seconds, then answer 429.
  xml_content = <<-XML
    <policies>
      <inbound>
        <base />
        <rate-limit-by-key
          calls="${var.rate_limit_calls}"
          renewal-period="${var.rate_limit_seconds}"
          counter-key="@(context.Request.IpAddress)">
          <forwarded-client-ip />
        </rate-limit-by-key>
      </inbound>
      <backend>
        <base />
      </backend>
      <outbound>
        <base />
      </outbound>
      <on-error>
        <base />
      </on-error>
    </policies>
    XML
}

# ── 5. THE PRODUCT: how clients get access (subscriptions) ───────────────────

resource "azurerm_api_management_product" "starter" {   # the "Starter" product (a bundle: which APIs + quota)
  product_id          = "starter"                  # internal id (unique in the gateway)
  display_name        = "Starter"                  # the name in the portal
  api_management_name = azurerm_api_management.gw.name   # which gateway
  resource_group_name = azurerm_resource_group.api.name   # which group

  published             = true                     # visible to developers immediately
  subscription_required = false                  # lab: no key (with the API open above)
  subscriptions_limit   = 5                        # max subscriptions per user
}

resource "azurerm_api_management_product_api" "hello" {  # attach the API to the product
  api_management_name = azurerm_api_management.gw.name   # which gateway
  api_name            = azurerm_api_management_api.hello.name   # which API
  product_id          = azurerm_api_management_product.starter.product_id   # which product
  resource_group_name = azurerm_resource_group.api.name   # which group
}
