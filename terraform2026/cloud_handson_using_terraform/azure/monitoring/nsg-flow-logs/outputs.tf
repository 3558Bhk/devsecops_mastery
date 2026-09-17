# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "flow_log_name" {                         # output: the flow log
  value       = azurerm_network_watcher_flow_log.lab.name       # the name
  description = "az network watcher flow-log show -g rg-lab-flowlog -n flowlog-lab"   # inspect
}

output "workspace_id" {                          # output: the workspace id
  value       = azurerm_log_analytics_workspace.lab.id      # the id
  description = "query NetFlowAppEvents in the workspace"   # the analytics
}
