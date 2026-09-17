# Terraform AKS (Azure) — Interview Questions

> **Cloud:** Azure · **IaC Tool:** Terraform · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~6 min

---

## Case A — Basic

**A1. What is AKS in Terraform?**
**Answer:** Azure's managed Kubernetes service, declared with `azurerm_kubernetes_cluster` (and node pools) or the community `Azure/aks/azurerm` module.

**A2. What resources does an AKS cluster need?**
**Answer:** A resource group, a service principal or managed identity, the cluster resource, and a default node pool (or separate `azurerm_kubernetes_cluster_node_pool`s).

**A3. How do you declare a minimal AKS cluster?**
**Answer:** `resource "azurerm_kubernetes_cluster" "aks" { name = ... ; resource_group_name = ... ; location = ... ; dns_prefix = ... ; default_node_pool { name = "default" ; node_count = 1 ; vm_size = "Standard_D2s_v3" } ; identity { type = "SystemAssigned" } }`.

**A4. What identity options does AKS support?**
**Answer:** System-assigned or user-assigned managed identity (recommended over the legacy service principal), used for the cluster to talk to Azure (LB, disks, ACR).

**A5. What is a node pool?**
**Answer:** A group of worker nodes with the same VM size/config. The default pool is inline; additional pools use `azurerm_kubernetes_cluster_node_pool`.

**A6. How do you get cluster credentials after creation?**
**Answer:** `az aks get-credentials -n <name> -g <rg>` (CLI), or build kubeconfig from the cluster's `kube_config` output (only when role-based access is disabled).

**A7. What is the `kubernetes`/`helm` provider's role with AKS?**
**Answer:** To manage in-cluster resources (namespaces, deployments, charts) after the cluster exists — often you bootstrap and let GitOps take over.

**A8. How do you attach an ACR to AKS?**
**Answer:** `azurerm_role_assignment` granting the cluster's managed identity `AcrPull` on the ACR (or `azurerm_kubernetes_cluster` `acr_attachment` in newer providers).

**A9. What is `dns_prefix` used for?**
**Answer:** The prefix for the cluster's public FQDN (`<dns_prefix>.<region>.azmk8s.io`) used to reach the API server.

**A10. What is the cluster's `kubernetes_version`?**
**Answer:** The Kubernetes version to run — pin it for reproducibility or set `automatic_channel_upgrade` for managed upgrades.

**A11. What is `node_resource_group`?**
**Answer:** The automatically created resource group holding cluster infrastructure (VMs, disks, LBs). Specify `node_resource_group` to name it explicitly.

**A12. How do you enable monitoring on AKS?**
**Answer:** `oms_agent` block (Azure Monitor for containers) linking a Log Analytics workspace.

**A13. What is the `azuread` provider's role with AKS?**
**Answer:** Optionally creates groups for cluster admins and grants them access via Kubernetes RBAC/`role_based_access_control`.

**A14. What is a Fargate equivalent in AKS?**
**Answer:** Virtual nodes (`virtual_node`) running pods on Azure Container Instances for serverless burst capacity.

**A15. How do you output the cluster name and resource group for other stacks?**
**Answer:** Output `azurerm_kubernetes_cluster.aks.name` and `node_resource_group` — needed to deploy ingress/other resources into the right group.

## Case B — Advanced / Senior

**B1. How do you build a production AKS cluster with Terraform?**
**Answer:** Use the `Azure/aks/azurerm` module or raw resources: system + user node pools across zones, managed identity, private or restricted API server, network plugin (Azure CNI), Azure Monitor, ACR pull role, and add-ons — with upgrade maintenance windows.

**B2. What is Azure CNI vs kubenet, and how does it affect networking?**
**Answer:** Azure CNI assigns each pod an IP from the VNet (better integration, needs IP planning); kubenet NATs pods behind nodes (fewer IPs, simpler). Azure CNI is the default recommendation for production.

**B3. How do you make the API server private or restricted?**
**Answer:** `private_cluster_enabled = true` (private API) or `api_server_access_profile { authorized_ip_ranges = [...] }` to restrict public access to specific IPs.

**B4. How do you manage cluster upgrades safely?**
**Answer:** Control the Kubernetes version + node image, use `automatic_channel_upgrade` or explicit version bumps, and upgrade node pools in waves (`max_surge`) after the control plane, testing between steps.

**B5. What is workload identity and how does Terraform set it up?**
**Answer:** Workload identity federates Kubernetes service accounts to Azure AD identities (no secrets). Terraform enables `workload_identity_enabled`, creates the user-assigned identity, and a federated credential, then the pod references the identity.

**B6. How do you integrate AKS with ACR and Key Vault?**
**Answer:** Grant `AcrPull` to the kubelet identity; for secrets, use the Key Vault CSI driver (`key_vault_secrets_provider`) with a user-assigned identity to mount secrets into pods.

**B7. How do you manage ingress on AKS with Terraform?**
**Answer:** Deploy the ingress controller (nginx/AGIC) via the `helm` provider, or use Azure Application Gateway Ingress Controller with an App Gateway managed in Terraform.

**B8. How do you structure AKS config for multiple clusters/environments?**
**Answer:** An AKS module instantiated per environment via tfvars (version, node pools, size, monitoring, identity), with the shared networking in a separate module and consistent add-ons.

**B9. What is `default_node_pool` vs separate node pools, and how do you move between them?**
**Answer:** The default pool is created with the cluster; separate `azurerm_kubernetes_cluster_node_pool` resources let you add/remove/replace pools (e.g. system vs user, spot vs regular) without recreating the cluster.

**B10. How do you use spot node pools for cost savings?**
**Answer:** A node pool with `priority = "Spot"` and `eviction_policy` for interruptible workloads, while keeping critical pods on a regular system pool with taints/tolerations.

**B11. What are the risks of managing app workloads with Terraform vs GitOps?**
**Answer:** Terraform-managing every pod/chart couples infra and app lifecycles and bloats state. Better: Terraform bootstraps the cluster + GitOps agent (ArgoCD/Flux), and the GitOps tool owns app deployments.

**B12. How do you rotate the AKS control-plane or node credentials/identity?**
**Answer:** For managed identity, rotation is handled by Azure. For legacy service principals, rotate the client secret and update the cluster. Plan rotations outside peak and test in staging first.

## Case C — Scenario

**C1. Pods can't pull images from ACR after cluster creation.**
**Answer:** Grant the cluster's kubelet identity `AcrPull` on the ACR (or use `acr_attachment`), verify the identity is correct, and re-apply. Confirm the image/tag exists.

**C2. You need to add a burst pool of cheaper spot VMs for batch jobs.**
**Answer:** Add a spot node pool with taints, configure the batch workloads with matching tolerations, and keep the system pool on regular VMs — all via a separate `azurerm_kubernetes_cluster_node_pool`.

**C3. The API server must not be reachable from the public internet.**
**Answer:** Set `private_cluster_enabled = true` and access the API from inside the VNet (or via VPN/peering/bastion). Adjust CI to run from a VNet-connected agent.

**C4. A Kubernetes upgrade caused workload issues; you need to roll back.**
**Answer:** Node pool OS/version rollback is limited — restore from the previous node image/version where possible, scale down the bad pool, and redeploy workloads. Going forward, stage upgrades (control plane, then pools) with testing.

**C5. Secrets are stored in plaintext Kubernetes Secrets and security wants Azure-native management.**
**Answer:** Enable the Key Vault CSI driver with a user-assigned identity, migrate secrets to Key Vault, and update workloads to mount them via the CSI — removing plaintext Secrets from the cluster.

**C6. You're migrating from hand-rolled AKS resources to the official module.**
**Answer:** Import the cluster and node pools into the module's resource addresses, match module inputs to current settings, verify `plan` shows no changes, then remove the old raw resources.
