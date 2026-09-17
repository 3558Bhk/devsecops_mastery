# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "api_server_ldap_endpoint" {              # output: the API server's FQDN
  value       = azurerm_kubernetes_cluster.lab.kube_config[0].host   # the host
  description = "az aks get-credentials -g rg-lab-aks -n aks-lab && kubectl get nodes"   # get working
}

output "node_resource_group" {                   # output: the node RG
  value       = azurerm_kubernetes_cluster.lab.node_resource_group   # the node RG
  description = "the auto-created RG for the nodes"   # the nodes live here
}
