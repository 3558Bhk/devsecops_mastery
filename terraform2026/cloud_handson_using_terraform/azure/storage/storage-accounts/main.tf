# ============================================================================
#  Azure Storage Accounts — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

resource "azurerm_resource_group" "lab" {        # the resource group
  name     = "rg-lab-storage"                    # the group's name
  location = var.region      # <- set in variables.tf (the region everything is built in)
}

resource "random_string" "suffix" {              # the random suffix
  length  = 8                                    # 8 characters
  special = false                                # no special chars (account names)
  lower = true                               # lowercase only
}

resource "azurerm_storage_account" "lab" {       # the storage account
  name                = "storlab${random_string.suffix.result}"   # a unique name (globally unique)
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG

  account_tier            = "Standard"          # the tier (Standard / Premium)
  account_replication_type = "LRS"              # the replication (LRS = locally redundant)
  https_traffic_only_enabled = true             # force HTTPS
  min_tls_version         = "TLS1_2"            # the minimum TLS version
  allow_nested_items_to_be_public = false               # no nested public items (security)

  tags = { env = "lab" }                        # a label
}

resource "azurerm_storage_container" "blobs" {   # the container (like an S3 bucket folder)
  name                 = "lab-blobs"            # the container's name
  storage_account_id   = azurerm_storage_account.lab.id     # which account (by id, v5)
  container_access_type = "private"             # the access level (private)
}

resource "azurerm_storage_blob" "hello" {        # a sample blob (from a local file)
  name                 = "hello.txt"            # the blob's name
  storage_container_id = azurerm_storage_container.blobs.id   # which container (by id, v5)
  type                 = "Block"                # the blob type (Block)
  source               = "${path.module}/hello.txt"   # the local file to upload
}

resource "azurerm_storage_share" "files" {       # a file share (for SMB mounts)
  name                 = "lab-files"            # the share's name
  storage_account_id   = azurerm_storage_account.lab.id     # which account (by id, v5)
  quota                = 50                     # the quota (GB)
}
