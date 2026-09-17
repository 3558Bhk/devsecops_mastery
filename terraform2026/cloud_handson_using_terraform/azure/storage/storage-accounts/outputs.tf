# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "primary_endpoint" {                       # output: the blob endpoint
  value       = azurerm_storage_account.lab.primary_blob_endpoint   # the URL
  description = "az storage container list --account-name <account>"   # inspect
}

output "container_name" {                          # output: the container
  value       = azurerm_storage_container.blobs.name        # the name
  description = "the sample blob 'hello.txt' lives here"   # ready
}
