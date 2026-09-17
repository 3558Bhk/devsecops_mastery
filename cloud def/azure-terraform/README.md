# Terraform on Azure — Interview Questions

Terraform interview prep for **Azure**, split into small topic files. Every file follows the same structure:

- **Case A — Basic** (15 questions): fundamentals, workflow, syntax.
- **Case B — Advanced / Senior** (12 questions): internals, tradeoffs, state, modules.
- **Case C — Scenario** (6 questions): real-world situations with expected answers.
- A **reading-time estimate** in the header (200 wpm basis).

Every question includes a **full model answer**.

## Structure

```
azure-terraform/
├── core/                 → HCL, workflow, state, variables, modules, workspaces, CI/CD (Azure DevOps)
├── foundations/          → Resource groups, naming, tags, locks
├── networking/           → VNet/subnets, NSGs, load balancing
├── compute/              → VMs, App Service, Azure Functions, AKS
├── storage-databases/    → Storage accounts, Azure SQL + Cosmos DB
├── identity-security/    → Entra ID + RBAC, Key Vault
└── ops/                  → Azure Monitor / Log Analytics, Service Bus / Event Hub / Event Grid
```

## Index

| Group | File | Topic |
|---|---|---|
| Core | `core/terraform-basics.md` | HCL, init/plan/apply/destroy, resources, data sources |
| Core | `core/providers.md` | azurerm provider, features block, subscriptions, versioning |
| Core | `core/state-management.md` | State file, Azure Storage backend, lease locking, import |
| Core | `core/variables-outputs-locals.md` | Variables, tfvars, outputs, locals, validation |
| Core | `core/modules.md` | Module structure, registry, versioning, composition |
| Core | `core/workspaces-environments.md` | Workspaces vs folder strategies, env separation |
| Core | `core/ci-cd-azure-devops.md` | Azure DevOps pipelines, service connections, plan/apply |
| Foundations | `foundations/resource-groups-tags.md` | Resource groups, naming, tags, management locks |
| Networking | `networking/vnet-subnets.md` | VNet, subnets, route tables, peering, NAT GW |
| Networking | `networking/nsg-security.md` | NSG rules, ASGs, flow control |
| Networking | `networking/load-balancing.md` | Load Balancer, App Gateway, Front Door, Traffic Manager |
| Compute | `compute/virtual-machines.md` | VMs, disks, availability sets/zones, scale sets |
| Compute | `compute/app-service.md` | App Service plan, web apps, slots, deployment |
| Compute | `compute/azure-functions.md` | Function App, consumption vs premium |
| Compute | `compute/aks.md` | AKS cluster, node pools, workload identity |
| Storage & DB | `storage-databases/storage-accounts.md` | Storage account, blobs, replication, private endpoints |
| Storage & DB | `storage-databases/databases.md` | Azure SQL + Cosmos DB |
| Identity | `identity-security/identity-rbac.md` | Service principals, role assignments, managed identity |
| Identity | `identity-security/key-vault.md` | Key Vault, secrets, access policies, soft delete |
| Ops | `ops/monitoring-messaging.md` | Azure Monitor, Log Analytics, Service Bus, Event Hub, Event Grid |
