# Azure 5 — Storage Accounts

> **⏱️ Time to complete: ~35 min** (read + create a storage account + blob container)

## 5.1 The Storage Account (the container)

```hcl
locals {                                      # named expressions
  # Storage account names: 3–24 lowercase letters/digits, GLOBALLY UNIQUE
  storage_name = lower(replace("${var.project}-${var.environment}storage", "-", ""))   # e.g. "webappdevstorage"
  # or: replace(uuidv5("https://example.com/salt", var.project), "-", "")   # a deterministic unique name
}

resource "azurerm_storage_account" "main" {   # create the storage account
  name                     = local.storage_name   # the name (globally unique)
  resource_group_name      = azurerm_resource_group.main.name   # the RG
  location                 = azurerm_resource_group.main.location   # the location
  account_tier             = "Standard"      # Standard | Premium
  account_replication_type = "LRS"           # LRS | GRS | RAGRS | ZRS | GZRS | RAGZRS
  access_tier              = "Hot"           # Hot | Cool (for blob)
  https_only_enabled       = true            # force HTTPS
  min_tls_version          = "TLS1_2"        # minimum TLS version
  allow_nested_items       = true            # allow nested items (table entities)
  tags                     = local.common_tags   # the common tags
}
```

### Replication types

| Type | Meaning |
|---|---|
| `LRS` | Locally redundant (single region, 3 copies) — cheapest |
| `ZRS` | Zone-redundant (3 AZs) |
| `GRS` | Geo-redundant (mirror to a paired region) — DR |
| `RAGRS` | Read-access geo-redundant (read from the secondary) |
| `GZRS` / `RAGZRS` | Zone + geo combinations |

**Rule:** dev = `LRS`; prod data = `ZRS` (AZ) or `GRS/RAGRS` (DR).

## 5.2 Blob Container

```hcl
resource "azurerm_storage_container" "app" {   # a blob container
  name      = "app"                            # the container name
  storage_account_name = azurerm_storage_account.main.name   # the storage account
  public_access_level = "None"      # None | Blob | Container (private by default)
  metadata = { owner = "platform" }   # metadata
}
```

### Static website

```hcl
resource "azurerm_storage_account" "web" {     # a storage account for a static site
  ...
  blob_properties {                            # the blob service properties
    static_website {                           # the static website config
      index_document = "index.html"            # the index document
      error_404_document = "error.html"        # the 404 document
    }
  }
}
```
(For prod, put **Front Door / CDN** in front; keep the container private.)

## 5.3 Access Keys & Endpoints (consume)

```hcl
# The primary access key (sensitive — don't output it)
output "storage_primary_key" {               # an output for the primary key
  value     = azurerm_storage_account.main.primary_access_key   # the key
  sensitive = true                           # mask it
}

output "blob_endpoint" {                      # an output for the blob endpoint
  value = azurerm_storage_account.main.primary_blob_endpoint   # the endpoint
}
```

> **azurerm v4+**: storage access uses **Azure AD** by default (no need to expose keys to the provider). For **your apps**, prefer **managed identity** / **RBAC** over shared keys (the account keys are a last resort).

## 5.4 Other Storage Services

```hcl
# Queue
resource "azurerm_storage_queue" "orders" {   # a storage queue
  name                 = "orders"             # the queue name
  storage_account_name = azurerm_storage_account.main.name   # the storage account
  metadata             = { owner = "platform" }   # metadata
}

# Table
resource "azurerm_storage_table" "orders" {   # a storage table
  name                 = "orders"             # the table name
  storage_account_name = azurerm_storage_account.main.name   # the storage account
}

# File share (SMB)
resource "azurerm_storage_share" "files" {    # a file share
  name                 = "files"              # the share name
  storage_account_name = azurerm_storage_account.main.name   # the storage account
  quota_in_mb          = 5120                 # the quota (MB)
}
```

## 5.5 Choosing Storage

| Need | Service |
|---|---|
| Web assets, logs, backups, data lake | **Blob** |
| Shared file system (SMB) | **File share** / **Azure Files** |
| Message queue | **Queue** / **Service Bus** |
| NoSQL table | **Table** / **Cosmos DB** |
| High-throughput shared (HPC) | **Azure NetApp Files** |

## 5.6 Getting It Right / Gotchas

- **Storage account name is globally unique** (all of Azure) → `uuidv5` or a strong prefix.
- **`https_only_enabled = true`** + **`min_tls_version = "TLS1_2"`** (security baseline).
- **`public_access_level = "None"`** by default; grant access via **RBAC** / **managed identity** / **SAS tokens**, not public containers.
- **Replication**: `LRS` (dev) / `ZRS` (AZ) / `GRS`/`RAGRS` (DR).
- **Shared keys** = last resort; prefer **RBAC + managed identity**.
- **One storage account per purpose** (app, logs, state) — don't cram everything into one.
- **`access_tier`** (Hot/Cool) for blob cost.

## 5.7 Interview Quick Facts

- **Storage account** = the container (globally unique name); holds **blob/queue/table/file**.
- **Replication**: LRS / ZRS / GRS / RAGRS / GZRS / RAGZRS.
- **Blob container** = the bucket (public access level: None/Blob/Container).
- **Static website** via `blob_properties.static_website`.
- **Access**: **RBAC + managed identity** (preferred) > SAS > shared keys (last resort).
- **`https_only`** + **TLS1.2** baseline.
- **Queue / Table / File share** for their respective patterns.
