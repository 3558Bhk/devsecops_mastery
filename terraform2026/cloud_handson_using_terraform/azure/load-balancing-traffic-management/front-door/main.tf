# ============================================================================
#  Front Door — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

resource "azurerm_resource_group" "lab" {        # the resource group
  name     = "rg-lab-fd"                         # the group's name
  location = var.region      # <- set in variables.tf (the region everything is built in)
}

resource "azurerm_cdn_frontdoor_profile" "lab" {   # the Front Door profile
  name                = "fd-lab"                 # the profile's name
  resource_group_name = azurerm_resource_group.lab.name   # which RG (the profile keeps its RG in v5)
  sku_name            = "Standard_AzureFrontDoor"   # the sku (Standard / Premium)
}

resource "azurerm_cdn_frontdoor_origin_group" "lab" {   # the origin group
  name                = "fd-og-lab"              # the group's name
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.lab.id   # which profile (v5)

  load_balancing {                                # how traffic is spread
    sample_size               = 100                # probe 100% of origins
    successful_samples_required = 50               # this many good samples = healthy
  }
}

resource "azurerm_cdn_frontdoor_origin" "origin1" {   # origin 1
  name                = "fd-origin1"             # the origin's name
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.lab.id   # which group (v5)
  host_name           = "backend1.example.com"   # the backend's hostname (CHANGE)
  certificate_name_check_enabled = false          # don't validate the cert's name (lab)
}

resource "azurerm_cdn_frontdoor_origin" "origin2" {   # origin 2
  name                = "fd-origin2"             # the origin's name
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.lab.id   # which group (v5)
  host_name           = "backend2.example.com"   # the backend's hostname (CHANGE)
  certificate_name_check_enabled = false          # don't validate the cert's name (lab)
}

resource "azurerm_cdn_frontdoor_endpoint" "lab" {   # the endpoint
  name                = "fd-endpoint-lab"        # the endpoint's name
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.lab.id   # which profile (v5)
  # (v5: the endpoint is auto-global — no location attribute anymore)
}

resource "azurerm_cdn_frontdoor_route" "lab" {    # the route
  name                = "fd-route-lab"           # the route's name
  cdn_frontdoor_endpoint_id   = azurerm_cdn_frontdoor_endpoint.lab.id   # which endpoint (v5)
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.lab.id   # which origin group (v5)

  patterns_to_match   = ["/*"]                   # the path patterns this route handles
  supported_protocols = ["Http", "Https"]        # which protocols        # the protocols allowed
  forwarding_protocol = "MatchRequest"           # forward using the same protocol as the request
}
