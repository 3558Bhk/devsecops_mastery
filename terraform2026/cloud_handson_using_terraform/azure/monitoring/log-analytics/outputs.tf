# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "workspace_id" {                          # output: the workspace id
  value       = azurerm_log_analytics_workspace.lab.id      # the id
  description = "az monitor log-analytics-show -g rg-lab-law -n law-lab"   # inspect
}

output "solution" {                              # output: the solution
  value       = azurerm_log_analytics_solution.activity.solution_name   # the name
  description = "the Activity solution is installed in the workspace"   # ready
}
