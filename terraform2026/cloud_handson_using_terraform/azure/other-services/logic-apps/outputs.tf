# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "access_endpoint" {                        # output: the workflow's endpoint
  value       = azurerm_logic_app_workflow.lab.access_endpoint   # the endpoint
  description = "POST a request here to trigger the workflow"   # the entry point
}

output "workflow_id" {                             # output: the workflow's id
  value       = azurerm_logic_app_workflow.lab.id           # the id
  description = "az logic workflow show -g rg-lab-logic -n workflow-lab"   # inspect
}
