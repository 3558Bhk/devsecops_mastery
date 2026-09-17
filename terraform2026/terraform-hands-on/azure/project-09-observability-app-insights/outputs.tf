output "app_url" {                                # output: the web app's hostname
  value       = azurerm_linux_web_app.app.default_hostname   # e.g. obs-obs-web.azurewebsites.net
  description = "curl -sI https://<this> → 200"     # how to test
}

output "instrumentation_key" {                    # output: the App Insights key
  value       = azurerm_application_insights.app.instrumentation_key   # the key
  description = "What the app uses to ship telemetry"   # what it is
}

output "law_name" {                               # output: the Log Analytics workspace
  value       = azurerm_log_analytics_workspace.law.name   # the name
  description = "Portal → Log Analytics → Log Analytics queries"   # where to query
}

output "alert_name" {                             # output: the metric alert
  value       = azurerm_monitor_metric_alert.cpu.name      # the name
  description = "az monitor metrics alert list -g $(terraform output -raw rg_name)"   # how to check
}

output "rg_name" {                                # output: the resource group
  value       = azurerm_resource_group.obs.name      # the name
  description = "For az commands: -g <this>"        # handy
}
