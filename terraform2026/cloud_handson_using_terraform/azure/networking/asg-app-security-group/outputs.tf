# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "asg_name" {                                # output: the ASG
  value       = azurerm_application_security_group.app.name       # the name
  description = "az network nic asg list -g rg-lab-asg -n nic-asg"   # inspect
}
