# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "cluster_endpoint" {                        # output: the API endpoint
  value       = aws_eks_cluster.lab.endpoint          # the URL
  description = "aws eks update-kubeconfig --name lab-eks && kubectl get nodes"   # get working
}

output "node_group" {                              # output: the node group
  value       = aws_eks_node_group.workers.id           # the name
  description = "aws eks describe-nodegroup --cluster-name lab-eks --nodegroup-name workers"   # inspect
}
