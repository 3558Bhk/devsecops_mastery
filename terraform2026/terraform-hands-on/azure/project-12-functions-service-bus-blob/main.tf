terraform {                                      # the terraform block: settings about Terraform itself
  required_version = ">= 1.5"                    # minimum Terraform version
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 5.0" }   # Azure provider, any 5.x
    archive = { source = "hashicorp/archive", version = "~> 2.0" }   # zips the function code
  }
}

provider "azurerm" {                             # configure the Azure provider
  features {}                                    # required in v5
}

resource "azurerm_resource_group" "app" {        # the resource group
  name     = "${var.project}-pipeline-rg"        # e.g. func-pipeline-rg
  location = var.location                        # from the input
}

# ── 1. STORAGE (Functions on a consumption plan keep their state here) ────────

resource "azurerm_storage_account" "app" {       # the storage account
  name                     = "${var.project}func2026"   # globally unique: 3-24 lowercase, NO hyphens
  location                 = var.location            # same location
  resource_group_name      = azurerm_resource_group.app.name   # which group
  account_tier             = "Standard"             # the tier
  account_replication_type = "LRS"                  # locally redundant (cheapest)
  https_traffic_only_enabled = true                # HTTPS only
}

# ── 2. MESSAGING: the topic (fan-out point), the subscription, the result queue ──

resource "azurerm_servicebus_namespace" "bus" {  # the namespace: the container for all entities
  name                = "${var.project}-sb-2026"  # globally unique name
  location            = var.location              # same location
  resource_group_name = azurerm_resource_group.app.name   # which group
  sku                 = "Standard"               # Standard (supports topics; Basic only has queues)
}

resource "azurerm_servicebus_topic" "orders" {   # the topic: the order service publishes here
  name           = "orders"                       # the topic's name
  namespace_id   = azurerm_servicebus_namespace.bus.id   # which namespace
}

resource "azurerm_servicebus_subscription" "processing" {   # subscription 1: the function's view
  name               = "processing"               # the subscription's name
  topic_id           = azurerm_servicebus_topic.orders.id   # which topic
  max_delivery_count = 3                          # 3 failed deliveries → dead-letter (poison handling)
}

resource "azurerm_servicebus_queue" "processed" {  # the queue: where the function's results go
  name           = "processed"                     # the queue's name
  namespace_id   = azurerm_servicebus_namespace.bus.id   # which namespace
}

# ── 3. THE FUNCTION: consumption plan (pay per execution) + zip-deployed code ──

resource "azurerm_service_plan" "consumption" {  # the "plan": on consumption you pay per execution
  name                = "${var.project}-func-plan"   # the plan's name
  location            = var.location              # same location
  resource_group_name = azurerm_resource_group.app.name   # which group
  os_type             = "Linux"                  # Linux functions
  sku_name            = "Y1"                     # the CONSUMPTION SKU (no idle cost; "FC1" = Flex Consumption)
}

data "archive_file" "function" {                 # zip the function folder (Terraform does the packaging)
  type        = "zip"                            # the format
  source_dir  = "${path.module}/function"        # the folder with main.py
  output_path = "${path.module}/build/function.zip"        # where the zip goes
}

resource "azurerm_linux_function_app" "app" {    # the function app itself
  name                = "${var.project}-func-app-2026"   # the app's name (its hostname, globally unique)
  location            = var.location              # same location
  resource_group_name = azurerm_resource_group.app.name   # which group
  service_plan_id     = azurerm_service_plan.consumption.id   # the consumption plan

  storage_account_name     = azurerm_storage_account.app.name   # where functions keep state/triggers
  storage_account_access_key = azurerm_storage_account.app.primary_access_key   # the key for that storage

  https_only = true                                # force HTTPS

  # app_settings is a TOP-LEVEL map in this azurerm version
  app_settings = {                                 # the app's configuration
    "FUNCTIONS_WORKER_RUNTIME"      = "python"                       # the function's language
    "ServiceBusConnectionString"    = azurerm_servicebus_namespace.bus.default_primary_connection_string   # the connection string the code reads
  }

  site_config {                                    # required block; holds the runtime version
    application_stack {                             # which runtime
      python_version = "3.11"                       # Python 3.11
    }
  }

  zip_deploy_file = data.archive_file.function.output_path   # deploy THIS zip (re-deploys when the code changes)
}
