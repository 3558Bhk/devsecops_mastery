# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "image_name" {                             # output: the image
  value       = azurerm_image.golden.name               # the name
  description = "az image show -g rg-lab-image -n img-golden"   # inspect
}

output "vm_from_image" {                          # output: the new VM
  value       = azurerm_linux_virtual_machine.from_image.name   # the name
  description = "az vm show -g rg-lab-image -n vm-from-image"   # inspect
}
