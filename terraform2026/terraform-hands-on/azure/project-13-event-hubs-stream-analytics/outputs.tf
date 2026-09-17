output "namespace_name" {                         # output: the Event Hub namespace
  value       = azurerm_eventhub_namespace.telemetry.name   # the name
  description = "az eventhubs event send -n <this> --eventhub-name telemetry"   # push a reading
}

output "storage_name" {                           # output: the sink storage account
  value       = azurerm_storage_account.sink.name      # the name
  description = "az storage blob list -c hot-readings --account-name <this>"   # check the results
}

output "job_name" {                               # output: the Stream Analytics job
  value       = azurerm_stream_analytics_job.hot_readings.name   # the name
  description = "az stream-analytics job show -n <this> (status must be Running)"   # health check
}

output "rg_name" {                                # output: the resource group
  value       = azurerm_resource_group.stream.name   # the name
  description = "For az commands: -g <this>"        # handy
}
