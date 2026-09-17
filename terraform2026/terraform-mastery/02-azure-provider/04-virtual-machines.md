# Azure 4 — Virtual Machines

> **⏱️ Time to complete: ~50 min** (read + create a VM + a VMSS)

## 4.1 The Core: `azurerm_linux_virtual_machine`

```hcl
locals {                                      # named expressions
  name_prefix = "${var.project}-${var.environment}"   # e.g. "webapp-dev"
}

# (VNet + subnet + NSG from the networking chapter)
# (NIC + optional public IP from the networking chapter)

resource "azurerm_linux_virtual_machine" "app" {   # a Linux VM
  name                            = "${local.name_prefix}-app"   # the VM name
  location                        = azurerm_resource_group.main.location   # the location
  resource_group_name             = azurerm_resource_group.main.name   # the RG
  size                            = "Standard_B2s"   # the VM size
  admin_username                  = "azureuser"      # the admin user
  network_interface_ids           = [azurerm_network_interface.app.id]   # the NIC
  admin_ssh_key {                            # the SSH key (Linux)
    username   = "azureuser"                  # the key's user
    public_key = var.ssh_public_key           # the public key
  }
  os_disk {                                    # the OS disk
    caching              = "ReadWrite"         # the caching mode
    storage_account_type = "StandardSSD_LRS"   # the disk type
    disk_encryption_set_id = null   # (set a disk encryption set for encryption)
  }
  source_image_reference {                     # the marketplace image
    publisher = "Canonical"                    # the publisher
    offer     = "0001-com-ubuntu-server-jammy" # the offer
    sku       = "22_04-lts"                    # the SKU (Ubuntu 22.04)
    version   = "latest"                       # the version
  }
  computer_name = "${local.name_prefix}-app"   # the computer name

  # (optional)
  availability_zone = "1"                      # an availability zone
  identity {                                   # the identity
    type = "SystemAssigned"                    # a system-assigned identity
  }
  additional_tags = local.common_tags          # the common tags
}
```

## 4.2 Windows VM

```hcl
resource "azurerm_windows_virtual_machine" "win" {   # a Windows VM
  name                            = "${local.name_prefix}-win"   # the name
  location                        = azurerm_resource_group.main.location   # the location
  resource_group_name             = azurerm_resource_group.main.name   # the RG
  size                            = "Standard_B2s"   # the size
  admin_username                  = "azureuser"      # the admin user
  admin_password                  = var.admin_password   # (use a Key Vault secret; it's in state)
  network_interface_ids           = [azurerm_network_interface.win.id]   # the NIC

  os_disk {                                    # the OS disk
    caching              = "ReadWrite"         # the caching mode
    storage_account_type = "StandardSSD_LRS"   # the disk type
  }
  source_image_reference {                     # the marketplace image
    publisher = "MicrosoftWindowsServer"       # the publisher
    offer     = "WindowsServer"                # the offer
    sku       = "2022-datacenter-azure-edition"  # the SKU
    version   = "latest"                       # the version
  }
  computer_name = "${local.name_prefix}-win"   # the computer name
}
```

## 4.3 VM Sizes (families)

| Family | Use | Examples |
|---|---|---|
| **B** (burstable) | Dev, low baseline | B1s, B2s, B12s |
| **D** (general) | Most apps | D2s_v3, D4s_v5 |
| **E** (memory) | DB, caches | E2s_v3, E8s_v5 |
| **F** (compute) | CPU-heavy | F4s_v2, F8s_v2 |
| **H** (HPC) | High perf | H16, H16r |
| **N** (GPU) | ML/graphics | NV6, NC6 |
| **L** (memory, SSD) | In-mem DBs | L4s, L8s |

Sizing: `B1s` (dev) → `D2s_v3`/`D4s_v5` (prod web) → `E*` (memory/DB).

## 4.4 Disks

```hcl
# OS disk is configured inline (os_disk). Data disks are separate + attached.
resource "azurerm_managed_disk" "data" {        # a managed data disk
  name                = "${local.name_prefix}-data"   # the name
  location            = azurerm_resource_group.main.location   # the location
  resource_group_name = azurerm_resource_group.main.name   # the RG
  storage_account_type = "StandardSSD_LRS"       # the disk type
  create_option       = "Empty"                 # create empty
  disk_size_gb        = 128                     # 128 GB
}

resource "azurerm_managed_disk_attachment" "data" {   # attach the disk to a VM
  data_disk_order   = 1                         # the attachment order
  caching           = "None"                    # the caching mode
  managed_disk_id   = azurerm_managed_disk.data.id   # the disk
  virtual_machine_id = azurerm_linux_virtual_machine.app.id   # the VM
}
```

- **Managed disks** (standard) vs **unmanaged** (rare).
- **Storage account types**: `Standard_LRS`, `StandardSSD_LRS`, `PremiumSSD_LRS`, `UltraSSD_LRS` (increasing perf/cost).
- **`create_option`**: `Empty`, `FromImage`, `Copy`, `Restore`.
- **Encryption**: use a **Disk Encryption Set** (for OS + data at rest with customer-managed keys).

## 4.5 Availability & Redundancy

```hcl
# Availability set (for VMs that need zone-agnostic redundancy)
resource "azurerm_availability_set" "app" {     # an availability set
  name                          = "${local.name_prefix}-as"   # the name
  location                      = azurerm_resource_group.main.location   # the location
  resource_group_name           = azurerm_resource_group.main.name   # the RG
  sku                           = "Aligned"       # aligned (required for VMs in an NSG)
  platforms_fault_domain_count  = 2               # fault domains
  platforms_update_domain_count = 3               # update domains
  managed                       = true            # managed (required)
}

# reference in the VM:
# availability_set_id = azurerm_availability_set.app.id
# (or use availability_zone = "1" for zone-redundant)
```

- **Availability Set** = fault + update domains (same-AZ redundancy).
- **Availability Zones** = physically separate datacenters (zone-redundant).
- **Scale sets** (below) = the preferred "many VMs" pattern.

## 4.6 Virtual Machine Scale Sets (VMSS)

```hcl
resource "azurerm_linux_virtual_machine_scale_set" "web" {   # a Linux VM scale set
  name                = "${local.name_prefix}-web-vmss"   # the name
  location            = azurerm_resource_group.main.location   # the location
  resource_group_name = azurerm_resource_group.main.name   # the RG
  sku_name            = "Standard_B2s"   # the VM size
  capacity            = 3                 # the current instance count
  min_capacity        = 2                 # the minimum
  max_capacity        = 6                 # the maximum
  autoscale_enabled   = true              # enable autoscale
  upgrade_mode        = "Manual"          # the upgrade mode

  os_disk {                                    # the OS disk
    caching              = "ReadWrite"         # the caching mode
    storage_account_type = "StandardSSD_LRS"   # the disk type
  }
  source_image_reference {                     # the marketplace image
    publisher = "Canonical"                    # the publisher
    offer     = "0001-com-ubuntu-server-jammy" # the offer
    sku       = "22_04-lts"                    # the SKU
    version   = "latest"                       # the version
  }

  network_interface {                          # the network interface
    name    = "nic"                            # the NIC name
    primary = true                             # the primary NIC
    ip_configuration {                         # the IP configuration
      name                                    = "ipconfig"   # the config name
      primary                                 = true         # primary
      subnet_id                               = azurerm_subnet.app.id   # the subnet
      primary                                 = true         # primary IP
      load_balancer_backend_address_pool_ids  = [azurerm_lb_backend_pool.web.id]   # (the LB pool)
    }
  }

  os_profile {                                 # the OS profile
    computer_name_prefix = "web"               # the computer name prefix
    admin_username       = "azureuser"         # the admin user
    linux_configuration {                       # the Linux config
      disable_password_authentication = true   # no password auth
      ssh_keys {                                 # the SSH key
        path     = "/home/azureuser/.ssh/authorized_keys"   # where to put it
        key_data = var.ssh_public_key           # the public key
      }
    }
  }

  # (optional) health extension for the LB
  # health_extension { status_uri = "..." }

  tags = local.common_tags                     # the common tags
}
```

- **VMSS** = auto-scaled pool of identical VMs (like AWS ASG). The go-to for scalable web tiers.
- **`autoscale_enabled`** + an **autoscale rule** (ch. 10) to scale on CPU.
- **`upgrade_mode`**: `Manual` (you control) / `Rolling` / `Automatic`.

## 4.7 VM Extensions (run scripts / install agents)

```hcl
# Custom Script extension (run a script on the VM)
resource "azurerm_virtual_machine_extension" "bootstrap" {   # a VM extension
  name                 = "bootstrap"             # the extension name
  virtual_machine_name = azurerm_linux_virtual_machine.app.name   # the VM
  location             = azurerm_resource_group.main.location   # the location
  resource_group_name  = azurerm_resource_group.main.name   # the RG
  publisher            = "Microsoft.Azure.ActiveDirectory"   # the publisher
  type                 = "LinuxScript"           # the extension type
  type_handler_version = "2.0"                   # the handler version

  settings = jsonencode({                          # the settings
    fileUris = ["https://<storage>.blob.core.windows.net/scripts/bootstrap.sh"]   # the script URL
    commandToExecute = "bash bootstrap.sh"         # the command to run
  })

  # (or, for a local/inline script)
  # protected_settings = jsonencode({ commandToExecute = "..." })
}
```

- Extensions = the Azure equivalent of "run this on the VM". Prefer **user data / custom image / Ansible** for idempotent config; extensions are for one-off or agent install.

## 4.8 Getting It Right / Gotchas

- **`admin_ssh_key`** (Linux) or **`admin_password`** (Windows) — Linux should disable password auth.
- **`source_image_reference`** = publisher/offer/sku/version (the marketplace image). Use a **custom image** (from a VM template) for pre-baked software.
- **`os_disk.storage_account_type`** matters for perf (use SSD for prod).
- **VM vs VMSS**: single VMs for app/servers; **VMSS** for scalable, load-balanced pools.
- **Availability**: zones (preferred) or availability sets.
- **Extensions** = run scripts/agents (not idempotent config management).
- **`identity { type = "SystemAssigned" }`** = keyless auth for the VM's apps.
- **Cost**: B-series for dev; stop/delete dev VMs (scheduled).
- **Data disks** = separate `azurerm_managed_disk` + `attachment`.

## 4.9 Interview Quick Facts

- **VM** = 1 VM; **VMSS** = auto-scaled pool (the scalable web tier).
- **`source_image_reference`** = marketplace image (publisher/offer/sku/version).
- **OS disk** (inline) vs **data disks** (managed disk + attachment).
- **Availability zones** (preferred) vs **availability sets** (fault/update domains).
- **Extensions** = run scripts/agents on the VM.
- **`identity`** = managed identity for keyless auth.
- **B-series** for dev; **D/E/F** for prod.
