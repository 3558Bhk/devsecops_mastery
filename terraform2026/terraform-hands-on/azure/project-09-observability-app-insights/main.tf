terraform {                                      # the terraform block: settings about Terraform itself
  required_version = ">= 1.5"                    # minimum Terraform version
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 5.0" }   # Azure provider, any 5.x
  }
}

provider "azurerm" {                             # configure the Azure provider
  features {}                                    # required in v5
}

resource "azurerm_resource_group" "obs" {        # the resource group
  name     = "${var.project}-obs-rg"             # e.g. obs-obs-rg
  location = var.location                        # from the input
}

# ── the log warehouse ─────────────────────────────────────────────────────────

resource "azurerm_log_analytics_workspace" "law" {   # Log Analytics: the queryable log warehouse
  name                = "${var.project}-obs-law"     # the workspace's name
  location            = var.location                 # same location
  resource_group_name = azurerm_resource_group.obs.name   # which group
  sku                 = "PerGB2018"                  # pay-per-GB ingestion (the modern default)
  retention_in_days   = 30                           # keep raw logs 30 days
}

# ── the app telemetry store ───────────────────────────────────────────────────

resource "azurerm_application_insights" "app" {   # Application Insights: app-level telemetry
  name                = "${var.project}-obs-appinsights"   # its name
  location            = var.location                 # same location
  resource_group_name = azurerm_resource_group.obs.name   # which group
  application_type    = "web"                        # the workload type (web/mobile/other)
}

# ── the web app (the thing we observe) ────────────────────────────────────────

resource "azurerm_service_plan" "app" {          # the compute pool (F1 = free)
  name                = "${var.project}-f1"      # the plan's name
  location            = var.location            # same location
  resource_group_name = azurerm_resource_group.obs.name   # which group
  os_type             = "Linux"                 # Linux plan
  sku_name            = "F1"                    # FREE plan
}

resource "azurerm_linux_web_app" "app" {         # the web app
  name                       = "${var.project}-obs-web"   # the app's name
  location                   = var.location             # same location
  resource_group_name        = azurerm_resource_group.obs.name   # which group
  service_plan_id            = azurerm_service_plan.app.id      # the free pool
  https_only                 = true                   # force HTTPS

  # app_settings is a TOP-LEVEL map in this azurerm version
  app_settings = {                                       # the app's configuration
    "APPINSIGHTS_INSTRUMENTATIONKEY" = azurerm_application_insights.app.instrumentation_key   # wires the app into App Insights
  }

  site_config {}                                       # an empty site_config block is required
}

# ── the glue: stream the app's logs into the warehouse ────────────────────────

resource "azurerm_monitor_diagnostic_setting" "web" {   # "send this resource's logs to the LAW"
  name               = "web-app-logs"                  # a name for the setting
  target_resource_id = azurerm_linux_web_app.app.id    # which resource
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id   # where to send

  enabled_log {                                          # which logs to stream
    category = "ConsoleLogs"                             # the app's stdout/stderr
  }

  enabled_log {                                          # and the platform event logs
    category = "AppEventLogs"                            # app lifecycle events
  }
}

# ── the alert: "CPU is hot" ───────────────────────────────────────────────────

resource "azurerm_monitor_action_group" "notify" {   # WHERE alerts go (only if you gave an email)
  count = var.alert_email == "" ? 0 : 1            # 0 or 1 action group
  name                = "${var.project}-notify"    # the group's name
  resource_group_name = azurerm_resource_group.obs.name   # which group (required!)
  short_name          = "notify"                   # a short display name

  email_receiver {                                  # the email destination (a block in v5)
    name          = "oncall"                        # a name for this receiver
    email_address = var.alert_email                 # the address to page
  }
}

resource "azurerm_monitor_metric_alert" "cpu" {     # the alert rule
  name                = "${var.project}-cpu-high"   # the alert's name
  resource_group_name = azurerm_resource_group.obs.name   # which group
  scopes              = [azurerm_linux_web_app.app.id]    # watch THIS app
  description         = "Web app CPU above 80% for 5 minutes"   # human label

  criteria {                                           # the condition (evaluated over the alert's frequency window)
    metric_namespace = "website"                      # the app's metric namespace
    metric_name      = "InstanceCpuPercent"           # the CPU metric
    aggregation      = "Average"                      # average over the window
    operator         = "GreaterThan"                  # the comparison
    threshold        = 80                             # the value that trips it
  }

  dynamic "action" {                                  # what to do when it fires (only if an email was given)
    for_each = var.alert_email == "" ? [] : [1]       # 0 blocks (no email) or 1 block
    content {                                          # the content of that block
      action_group_id = azurerm_monitor_action_group.notify[0].id   # the action group above
    }
  }
}
