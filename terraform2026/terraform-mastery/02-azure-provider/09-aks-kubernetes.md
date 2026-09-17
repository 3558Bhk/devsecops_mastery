# Azure 9 — AKS (Kubernetes)

> **⏱️ Time to complete: ~75 min** (read + create an AKS cluster with a node pool)

## 9.1 The Cluster (the pattern)

```hcl
locals {                                      # named expressions
  name_prefix = "${var.project}-${var.environment}"   # e.g. "webapp-dev"
}

resource "azurerm_kubernetes_cluster" "main" {   # an AKS cluster
  name                = "${local.name_prefix}-aks"   # the name
  location            = azurerm_resource_group.main.location   # the location
  resource_group_name = azurerm_resource_group.main.name   # the RG
  dns_prefix          = "${local.name_prefix}-aks"   # the DNS prefix

  # --- Networking ---
  network_plugin             = "kubenet"          # (or "azure" = Azure CNI)
  network_policy             = "calico"           # (requires network_plugin = kubenet or azure)
  # For Azure CNI:
  # network_plugin           = "azure"
  # default_node_pool        (pod IP comes from the VNet)

  # --- RBAC / Identity ---
  rbac_enabled        = true                  # enable RBAC
  local_account_disabled = true      # (use AAD, not local admin)
  identity {                                   # the cluster identity
    type = "SystemAssigned"                   # a system-assigned identity
  }

  # --- Monitoring / Logging ---
  monitoring {                                 # the monitoring config
    log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id   # the workspace
  }

  # --- Load balancer ---
  load_balancer_sku = "standard"               # the LB SKU

  default_node_pool {                          # the default node pool
    name       = "default"                     # the pool name
    node_count = 2                             # the node count
    vm_size    = "Standard_D2s_v3"             # the VM size
    mode       = "System"              # (System nodes run cluster components)
    os_disk_size_gb = 30                     # the OS disk size
    # auto-scaling:
    min_count = 2                             # the minimum
    max_count = 6                             # the maximum
    auto_scaling_enabled = true               # enable auto-scaling
  }

  tags = local.common_tags                     # the common tags
}
```

## 9.2 Network Plugins (kubenet vs Azure CNI)

| | **kubenet** | **Azure CNI** (`network_plugin = "azure"`) |
|---|---|---|
| Pod network | overlay (secondary NIC per node) | pods get IPs **directly from the VNet** |
| VNet usage | doesn't consume VNet IPs for pods | consumes VNet IP space for pods |
| Policy | `calico` / `azure` | `azure` / `calico` |
| Use | simpler, less VNet IP pressure | native, better networking, policy |

- **Azure CNI** = pods are first-class VNet citizens (directly addressable, NSG-able). Preferred in most prod.
- **kubenet** = overlay; pods have their own network (NAT to VNet). Simpler IP math.

## 9.3 Node Pools (separate pools for different workloads)

```hcl
resource "azurerm_kubernetes_cluster_node_pool" "app" {   # a node pool
  name                = "app"                            # the pool name
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id   # the cluster
  vm_size             = "Standard_D4s_v5"                # the VM size
  node_count          = 3                                # the node count
  min_count           = 2                                # the minimum
  max_count           = 8                                # the maximum
  auto_scaling_enabled = true                            # enable auto-scaling
  mode                = "User"            # (User = general workloads; System = cluster components)
  os_disk_size_gb     = 50                             # the OS disk size
  tags                = local.common_tags              # the common tags
}
```

- **Multiple node pools** = different VM sizes / SKUs / node counts for different workloads (e.g. a `System` pool + a `User` app pool + a GPU pool).
- **`mode`**: `System` (runs control-plane add-ons) / `User` (your workloads).

## 9.4 Auth & Access

```bash
# Get credentials (uses the Azure AD identity)
az aks get-credentials --resource-group rg --name my-aks --admin
# or, for Terraform-managed, the cluster's FQDN + AAD
```

- **`rbac_enabled = true`** = RBAC on (mandatory).
- **`local_account_disabled = true`** = disable local `admin` (force **Azure AD** auth).
- **Azure AD integration** (managed) = federate Entra ID users/groups to k8s RBAC.
- **OIDC** (`oidc_issuer_url`) = let workloads use **federated credentials** (like GHA) for pod identity.

## 9.5 Add-ons

```hcl
resource "azurerm_kubernetes_cluster" "main" {   # the AKS cluster
  ...
  # Ingress / load balancing
  http_load_balancer_enabled = true    # (ingress controller)

  # (Ingress via App Gateway)
  # ingress_application_gateway {
  #   gateway_id  = azurerm_application_gateway.main.id
  #   subnet_id   = azurerm_subnet.appgw.id
  # }

  # Policy
  azure_policy_enabled = true          # enforce Azure Policy on the cluster

  # (Private cluster: no public API server)
  # private_cluster = true
  # private_dns_zone_id = azurerm_private_dns_zone.aks.id
}
```

- **`http_load_balancer_enabled`** = Azure CNI + an L7 ingress controller.
- **Ingress via App Gateway** = use your existing App GW as the k8s ingress (the recommended L7 ingress for AKS).
- **`azure_policy_enabled`** = Azure Policy enforcement on the cluster.
- **`private_cluster`** = no public API endpoint (access via private IP / jump host).

## 9.6 Getting It Right / Gotchas

- **`network_plugin`**: `kubenet` (overlay) vs `azure` (CNI, pods in VNet). Choose at creation (can't easily change).
- **`rbac_enabled`** + **`local_account_disabled`** (force AAD) for security.
- **`load_balancer_sku = "standard"`** (zone-redundant) for prod.
- **`default_node_pool`** = the first pool (System); add **`node_pool`**s for workloads.
- **`auto_scaling_enabled`** + `min_count`/`max_count` = scale the cluster.
- **Monitoring** = Log Analytics workspace (Kubernetes monitoring).
- **Private cluster** = no public API (private DNS + jump host).
- **Ingress** = App Gateway (L7) or the built-in `http_load_balancer`.

## 9.7 Interview Quick Facts

- **AKS** = managed Kubernetes on Azure.
- **kubenet vs Azure CNI** = overlay vs pods-in-VNet (CNI preferred for prod).
- **RBAC** on; **local accounts disabled** (use AAD).
- **Node pools** = separate pools (System/User, different VM sizes).
- **Auto-scaling** = `auto_scaling_enabled` + min/max.
- **Private cluster** = no public API endpoint.
- **Ingress** = App Gateway (L7) or built-in LB.
- **Monitoring** = Log Analytics workspace.
