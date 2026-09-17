# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "endpoint" {                              # output: the connection string
  value       = aws_elasticache_replication_group.redis.primary_endpoint_address   # host:port
  description = "redis-cli -h <host> -p 6379   (from inside the VPC)"   # connect
}

output "node_id" {                               # output: the node
  value       = element(aws_elasticache_replication_group.redis.member_clusters, 0)   # the first node
  description = "aws elasticache describe-cache-clusters -c lab-redis"   # inspect
}
