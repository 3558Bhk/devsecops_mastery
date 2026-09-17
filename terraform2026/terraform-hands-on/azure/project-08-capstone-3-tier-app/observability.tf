# ── OBSERVABILITY: Log Analytics + WAF logs ────────────────────────────────────

resource "azurerm_log_analytics_workspace" "logs" {  # the Log Analytics workspace (the "firehose" for logs)
  name                = "${var.project}-capstone-law"   # the workspace's name
  location            = var.location                  # same location
  resource_group_name = azurerm_resource_group.capstone.name   # which group
  sku                 = "PerGB2018"                   # pay-per-GB ingestion (the modern default)
  retention_in_days   = 30                            # keep raw logs for 30 days
}

resource "azurerm_monitor_diagnostic_setting" "appgw" {   # "stream this resource's logs to the workspace"
  name               = "appgw-waf-logs"                  # a name for the setting
  target_resource_id = azurerm_application_gateway.web.id   # which resource (the App Gateway)
  log_analytics_workspace_id = azurerm_log_analytics_workspace.logs.id   # where to send

  enabled_log {                                          # which logs to send
    category = "WAFLogs"                                # the WAF's request/block log
  }

  # (the gateway's SystemAssigned identity in web.tf authorizes the write automatically)
}
