# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "rule_name" {                                # output: the rule
  value       = aws_config_config_rule.ebs_encrypted.name   # the name
  description = "aws config describe-config-rules --rule-names <this>"   # check compliance
}
