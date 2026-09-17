# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "zone_id" {                                # output: the zone
  value       = aws_route53_zone.lab.id              # the id
  description = "aws route53 list-resource-record-sets --hosted-zone-id <this>"   # list the records
}

output "zone_nameservers" {                      # output: the NS to delegate the domain to
  value       = aws_route53_zone.lab.name_servers   # the four nameservers
  description = "set these as the domain's NS records at your registrar"   # the delegation step
}
