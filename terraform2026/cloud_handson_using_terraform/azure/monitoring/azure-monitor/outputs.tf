# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "alert_name" {                              # output: the alert
  value       = azurerm_monitor_metric_alert.cpu.name       # the name
  description = "az monitor metric-alarm list -g rg-lab-monitor"   # inspect
}

output "workspace_id" {                            # output: the workspace id
  value       = azurerm_log_analytics_workspace.lab.id      # the id
  description = "the Log Analytics workspace (for log-based alerts)"   # the log store
}
