# ============================================================================
#  AKS (Azure Kubernetes Service) — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

resource "azurerm_resource_group" "lab" {        # the resource group
  name     = "rg-lab-aks"                        # the group's name
  location = var.region      # <- set in variables.tf (the region everything is built in)
}

resource "azurerm_virtual_network" "lab" {       # the VNet
  name                = "vnet-aks"               # the VNet's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
  address_space       = ["10.20.0.0/16"]         # the IP space
}

resource "azurerm_subnet" "node" {               # the subnet for the nodes
  name                 = "subnet-node"           # the subnet's name
  resource_group_name  = azurerm_resource_group.lab.name   # which RG
  virtual_network_name = azurerm_virtual_network.lab.name  # which VNet
  address_prefixes     = ["10.20.1.0/24"]        # the slice
}

resource "azurerm_kubernetes_cluster" "lab" {    # the cluster
  name                = "aks-lab"               # the cluster's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
  dns_prefix          = "aks-lab-dns"           # the DNS prefix (for the API FQDN)

  identity {                                    # the identity (v5: identity or service_principal required)
    type = "SystemAssigned"                     # a system-assigned managed identity
  }

  role_based_access_control_enabled = true      # RBAC is on (the default)

  default_node_pool {                           # the system node pool
    name       = "nodepool1"                    # the pool's name
    node_count = 1                              # the number of nodes
    vm_size    = "Standard_B2s"                 # the node's size (small)
  }

  node_provisioning_profile {                   # node provisioning (required in v5)
    default_node_pools = "Auto"                 # auto-provision the default pool (Auto | None)
  }
}
