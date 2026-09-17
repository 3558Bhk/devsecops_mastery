# ============================================================================
#  Azure Identity (Entra ID) — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

resource "azurerm_resource_group" "lab" {        # the resource group
  name     = "rg-lab-entra"                      # the group's name
  location = var.region      # <- set in variables.tf (the region everything is built in)
}

resource "random_string" "suffix" {              # a random suffix for the account name
  length  = 8                                    # 8 characters
  special = false                                # no special chars
  lower = true                               # lowercase only
}

resource "azurerm_storage_account" "lab" {       # the storage account
  name                = "storentra${random_string.suffix.result}"   # a unique name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
  account_tier            = "Standard"          # the tier
  account_replication_type = "LRS"              # the replication
  https_traffic_only_enabled = true             # force HTTPS
  min_tls_version         = "TLS1_2"            # the minimum TLS version
}

resource "azurerm_user_assigned_identity" "storage" {   # the identity (standalone)
  name                = "id-storage-admin"      # the identity's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
  # (tenant_id is optional; defaults to the subscription's tenant)
}

resource "azurerm_role_assignment" "blob_owner" {   # the grant: role + scope + principal
  scope                = azurerm_storage_account.lab.id   # on the storage account
  role_definition_name = "Storage Blob Data Owner"   # the role
  principal_id         = azurerm_user_assigned_identity.storage.principal_id   # the identity
}
