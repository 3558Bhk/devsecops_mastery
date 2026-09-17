# ============================================================================
#  Traffic Manager — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

resource "azurerm_resource_group" "lab" {        # the resource group
  name     = "rg-lab-tm"                         # the group's name
  location = var.region      # <- set in variables.tf (the region everything is built in)
}

resource "azurerm_traffic_manager_profile" "lab" {   # the profile
  name                = "tm-lab"                 # the profile's name
  resource_group_name = azurerm_resource_group.lab.name   # which RG

  traffic_routing_method = "Performance"         # the method (Performance = lowest latency)
  profile_status        = "Enabled"               # the status (Enabled/Disabled)

  dns_config {                                    # the DNS settings (v5: nested block)
    relative_name = "tm-lab"                      # the DNS name part (tm-lab.trafficmanager.net)
    ttl           = 60                            # the DNS TTL in seconds
  }

  monitor_config {                                # the endpoint MONITOR (v5: nested block)
    protocol              = "HTTPS"               # probe over HTTPS
    port                  = 443                   # the port
    path                  = "/health"             # the probe path
    interval_in_seconds   = 30                    # probe every 30s
    timeout_in_seconds    = 5                     # probe timeout
    tolerated_number_of_failures = 2              # how many failures before marking down
  }
}

resource "azurerm_traffic_manager_azure_endpoint" "east" {   # the east endpoint
  name                = "tm-endpoint-east"      # the endpoint's name
  profile_id          = azurerm_traffic_manager_profile.lab.id   # which profile (by id, v5)
  target_resource_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-lab-tm/providers/Microsoft.Compute/virtualMachines/vm-east"   # the target VM's id (CHANGE)
  enabled             = true                    # the endpoint is enabled
  weight              = 1                       # the weight (for the Weighted method)
}

resource "azurerm_traffic_manager_external_endpoint" "west" {   # the west endpoint
  name                = "tm-endpoint-west"      # the endpoint's name
  profile_id          = azurerm_traffic_manager_profile.lab.id   # which profile (by id, v5)
  target              = "13.107.4.52"           # the external target (an IP / hostname — CHANGE)
  enabled             = true                    # the endpoint is enabled
  weight              = 1                       # the weight
}
