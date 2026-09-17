# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "dashboard_url" {                          # output: the dashboard
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards:lab-dashboard"   # the URL
  description = "open it once the metric has data"   # it's empty until the filter matches something
}
