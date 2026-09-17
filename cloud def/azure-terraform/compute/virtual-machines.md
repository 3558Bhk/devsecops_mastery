# Terraform Virtual Machines (Azure) — Interview Questions

> **Cloud:** Azure · **IaC Tool:** Terraform · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~5 min

---

## Case A — Basic

**A1. What resources make up an Azure VM in Terraform?**
**Answer:** `azurerm_linux_virtual_machine` (or `_windows_`), a NIC (`azurerm_network_interface`), plus supporting resources: resource group, subnet, and optionally a public IP and managed disk.

**A2. How do you declare a Linux VM?**
**Answer:** `resource "azurerm_linux_virtual_machine" "vm" { name = ... ; resource_group_name = ... ; location = ... ; size = "Standard_B2s" ; admin_username = "azureuser" ; network_interface_ids = [azurerm_network_interface.nic.id] ; admin_ssh_key { username, public_key } ; os_disk { caching, storage_account_type } ; source_image_reference { publisher, offer, sku, version } }`.

**A3. What is a NIC in Azure?**
**Answer:** `azurerm_network_interface` — the network adapter connecting a VM to a subnet, with a private IP config (and optional public IP).

**A4. What is `source_image_reference`?**
**Answer:** The marketplace/gallery image (publisher, offer, sku, version) used to create the OS disk.

**A5. What is a managed disk?**
**Answer:** `azurerm_managed_disk` (data disks) and the VM's `os_disk` — Azure-managed storage for the VM, optionally encrypted.

**A6. How do you add a data disk to a VM?**
**Answer:** `azurerm_managed_disk` + `azurerm_virtual_machine_data_disk_attachment` (or inline `os_disk`/data disk blocks on some resources).

**A7. What is an availability set?**
**Answer:** `azurerm_availability_set` groups VMs across fault/update domains to improve availability against hardware/maintenance events.

**A8. What are availability zones?**
**Answer:** Physically separate datacenters in a region; setting `zone = "1"` on the VM (or zone-redundant resources) protects against a whole-datacenter failure.

**A9. What is a Virtual Machine Scale Set (VMSS)?**
**Answer:** `azurerm_linux_virtual_machine_scale_set` — a group of identical VMs that autoscale, with load balancing support.

**A10. How do you provision a VM at boot?**
**Answer:** `custom_data` (cloud-init for Linux, or a script) on the VM resource.

**A11. What is a VM extension?**
**Answer:** `azurerm_virtual_machine_extension` — an agent-based post-deploy config (run scripts, install agents, join domain).

**A12. What is a public IP resource?**
**Answer:** `azurerm_public_ip` — a public address you can attach to a NIC/LB for inbound access.

**A13. How do you protect a VM's admin credentials?**
**Answer:** SSH keys (Linux) or Key Vault-stored passwords (Windows), marked `sensitive` — never hardcode secrets.

**A14. What is a managed identity on a VM?**
**Answer:** A `identity` block giving the VM an Azure AD identity to access Azure resources without credentials.

**A15. How do you pick the VM size?**
**Answer:** Set `size` (e.g. `Standard_D2s_v3`); validate against the region with `data "azurerm_virtual_machine_sizes"` if needed.

## Case B — Advanced / Senior

**B1. Availability set vs availability zone vs VMSS — how do you choose?**
**Answer:** Availability set: intra-region fault/update domain protection for individual VMs. Availability zone: datacenter-level isolation (better SLA). VMSS: identical, autoscalable instances across zones. Modern HA defaults to zones or VMSS.

**B2. How do you build a golden image pipeline with Terraform?**
**Answer:** Use Packer (or Azure Image Builder) to bake the image, publish to a Shared Image Gallery (`azurerm_shared_image_gallery` + `azurerm_shared_image`), and reference the image version in `source_image_id`.

**B3. What is a Shared Image Gallery and its Terraform resources?**
**Answer:** A versioned image repository: gallery → image definition → image version. VMs reference the image version ID, enabling consistent, replicable builds across regions.

**B4. How do you do zero-downtime VM updates?**
**Answer:** For VMSS, rolling upgrades (`rolling_upgrade_policy`) with max unhealthy %; for single VMs, use load balancer + blue-green (new VM, shift traffic, retire old) since in-place size/OS changes often require reboot/recreate.

**B5. What changes force a VM recreation in Terraform?**
**Answer:** Changes to the OS disk image, zone, availability set, or admin credentials (some fields) can force replace. Know which fields are `ForceNew` and plan migrations accordingly.

**B6. How do you enable VM boot diagnostics and monitoring?**
**Answer:** `boot_diagnostics` (storage account for console logs/screenshots), plus the Azure Monitor agent/Diagnostics extension for guest metrics.

**B7. How do you encrypt VM disks with customer-managed keys?**
**Answer:** Create a Disk Encryption Set (`azurerm_disk_encryption_set`) backed by a Key Vault key, and reference it on the OS/data disks (`disk_encryption_set_id`).

**B8. How do you join VMs to a domain with Terraform?**
**Answer:** The `azurerm_virtual_machine_extension` with the `JsonADDomainExtension` (or a custom script) using credentials from Key Vault — Terraform deploys the extension, the agent performs the join.

**B9. How do you configure a VM's private DNS and hostname?**
**Answer:** Set the NIC `internal_dns_name_label`, use private DNS zones for record management, and set the VM `computer_name` where supported.

**B10. How do you attach a VM to a backend pool and NAT rules?**
**Answer:** `azurerm_network_interface_backend_address_pool_association` and `azurerm_network_interface_nat_rule_association` link the NIC to the LB's pool/NAT rules.

**B11. What is Spot/priority pricing and how does Terraform configure it?**
**Answer:** VM `priority = "Spot"` with `eviction_policy` (e.g. Deallocate) for deeply discounted, interruptible VMs — good for batch, risky for stateful workloads.

**B12. How do you keep VM config DRY across environments?**
**Answer:** A VM module with inputs (size, image, subnet, disks, extensions, tags) instantiated per environment via tfvars, with shared images from the gallery.

## Case C — Scenario

**C1. Your VM is unreachable over SSH after a Terraform change.**
**Answer:** Check the public IP/NIC still attached, NSG rule for port 22, the SSH key unchanged, and boot diagnostics for OS errors. Roll back the change if it altered networking.

**C2. You need to resize a VM with minimal downtime.**
**Answer:** Deallocate → resize → start. In Terraform, changing `size` does this in-place for supported sizes. If the size isn't available in the region/AZ, pick another or migrate.

**C3. A compliance rule requires all VM disks encrypted with your own key.**
**Answer:** Create a Disk Encryption Set in Key Vault, reference it on OS/data disks, and add a policy check that VMs must set `disk_encryption_set_id`. Encrypt existing disks by migrating them.

**C4. Your VMSS isn't scaling despite high CPU.**
**Answer:** Check the autoscale settings (capacity/monitor metrics) on the scale set, that the metric is being emitted, and that instance limits aren't hit. Fix the scale rule thresholds/cooldowns.

**C5. You must upgrade the OS image across a VMSS without downtime.**
**Answer:** Update the image version and use rolling upgrades (`rolling_upgrade_policy` with `max_batch_instance_percent` and pause) so instances update in batches while the service stays healthy.

**C6. A Windows VM needs to run a script on first boot with secrets.**
**Answer:** Use `custom_data`/a VM extension referencing Key Vault secrets (via managed identity), keeping credentials out of the config, and log the extension output for verification.
