terraform {                                      # the terraform block: settings about Terraform itself
  required_version = ">= 1.5"                    # minimum Terraform version
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 5.0" }   # Azure provider, any 5.x
  }
}

provider "azurerm" {                             # configure the Azure provider
  features {}                                    # required in v5
}

resource "azurerm_resource_group" "stream" {     # the resource group
  name     = "${var.project}-stream-rg"          # e.g. iot-stream-rg
  location = var.location                        # from the input
}

# ── 1. THE SINK: a storage container for the hot readings ────────────────────

resource "azurerm_storage_account" "sink" {      # the storage account
  name                     = "${var.project}stream2026"   # globally unique: 3-24 lowercase, NO hyphens
  location                 = var.location            # same location
  resource_group_name      = azurerm_resource_group.stream.name   # which group
  account_tier             = "Standard"             # the tier
  account_replication_type = "LRS"                  # locally redundant (cheapest)
  https_traffic_only_enabled = true                # HTTPS only
}

resource "azurerm_storage_container" "hot" {     # the container the filtered readings land in
  name      = "hot-readings"                     # the container's name
  storage_account_id = azurerm_storage_account.sink.id   # which account
}

# ── 2. THE SOURCE: Event Hubs (the streaming ingest layer) ───────────────────

resource "azurerm_eventhub_namespace" "telemetry" {   # the namespace: one per environment
  name                = "${var.project}-eh-2026"    # globally unique name
  location            = var.location              # same location
  resource_group_name = azurerm_resource_group.stream.name   # which group
  sku                 = "Standard"               # Standard (required for Event Hubs)
  capacity            = 1                         # 1 throughput unit = the cheapest
}

resource "azurerm_eventhub" "telemetry" {         # the hub: the actual stream
  name              = "telemetry"                 # the hub's name
  namespace_id      = azurerm_eventhub_namespace.telemetry.id   # which namespace
  partition_count   = 1                            # 1 partition (each partition = 1MB/s ingest)
  message_retention = 1                            # keep 1 day of events (your replay window)
}

# ── 3. THE BRAIN: a Stream Analytics job running LIVE SQL over the stream ────

resource "azurerm_stream_analytics_job" "hot_readings" {   # the job
  name              = "${var.project}-hot-readings"   # 3-50 chars, lowercase, must start with a letter
  location          = var.location              # same location
  resource_group_name = azurerm_resource_group.stream.name   # which group
  type              = "Cloud"                  # a cloud (streaming) job — the other option is "Edge"
  sku_name          = "Standard"               # the SKU

  # THE live query: runs continuously over the stream — this is the whole pipeline in one line
  transformation_query = <<-QUERY
    SELECT device_id, temperature
    FROM Telemetry
    WHERE temperature > ${var.hot_threshold}
    QUERY

  # the job's internal storage (its own state; can reuse any storage account)
  job_storage_account {                           # where the job keeps its internal state
    account_name = azurerm_storage_account.sink.name   # this account (a dedicated one is cleaner in prod)
  }
}

# In this provider version the job's INPUT is a separate resource
resource "azurerm_stream_analytics_stream_input_eventhub" "telemetry" {   # "read from this Event Hub"
  name                        = "Telemetry"      # the name the QUERY uses (FROM Telemetry)
  resource_group_name         = azurerm_resource_group.stream.name   # which group
  stream_analytics_job_name   = azurerm_stream_analytics_job.hot_readings.name   # which job
  servicebus_namespace        = azurerm_eventhub_namespace.telemetry.name   # which namespace
  eventhub_name               = azurerm_eventhub.telemetry.name   # which hub

  serialization {                                 # how to parse each event
    type = "Json"                                 # events are JSON
  }
}

# ...and the OUTPUT is a separate resource too
resource "azurerm_stream_analytics_output_blob" "hot_readings" {   # "write matching rows to this container"
  name                        = "HotReadings"     # the output's name (shown in the portal)
  resource_group_name         = azurerm_resource_group.stream.name   # which group
  stream_analytics_job_name   = azurerm_stream_analytics_job.hot_readings.name   # which job
  storage_account_name        = azurerm_storage_account.sink.name   # which account
  storage_container_name      = azurerm_storage_container.hot.name   # which container

  # files are written under this path pattern ({partitionId} = which hub partition it came from)
  path_pattern = "hot/{partitionId}"              # e.g. hot-readings/hot/0/2026/09/17/10/42/00/hot.json
  date_format  = "yyyy/ss/dd"                     # year/month/day folders
  time_format  = "HH/mm/00"                       # hour/minute folders (a new file every minute)

  serialization {                                 # how to write each row
    type   = "Json"                               # JSON
    format = "LineSeparated"                      # one row per line (append-friendly, cheap)
  }
}
