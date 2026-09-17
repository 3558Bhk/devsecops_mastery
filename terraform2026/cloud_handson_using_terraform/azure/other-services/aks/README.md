# AKS (Azure Kubernetes Service) — Terraform how-to

## 📁 File structure (the standard Terraform layout)

| File | What it does |
|---|---|
| `providers.tf` | the `terraform` block (required_providers) + provider config — "which cloud, which provider version, how to log in" |
| `variables.tf` | input variables — the knobs (e.g. `region`) you change without touching the resources |
| `main.tf` | the resources — the actual infrastructure Terraform creates (and any `data` lookups) |
| `outputs.tf` | output values — the endpoints/ids/URLs Terraform prints after `apply` |

> Why four files? Terraform reads **every** `.tf` file in the folder as one program. Splitting by
> concern is the industry convention: reviewers find the resources in `main.tf`, you change
> settings in `variables.tf`, and you read results in `outputs.tf` — instead of one 500-line file.

**What:** a **managed Kubernetes cluster** (AKS) with a **system node pool** (1 small node) + RBAC.

**Interview angle (SDE3):**
- **AKS** = a **managed control plane** (free) + your **nodes** (you pay) — the Azure equivalent of EKS/GKE.
- The **node pool** = the worker nodes (a VMSS under the hood); you can have **multiple pools** (different sizes/skus/availability).
- **RBAC** is on by default — access is via **`kubectl`** + **RBAC roles** (the interview: "how do you give a dev access to a namespace?" → a **RoleBinding**).
- AKS vs **ACI** (Container Instances = serverless containers) vs **App Service Containers** — the interview: "which for a bursty, short-lived job?" → **ACI**.

## Run it
```bash
terraform init && terraform plan && terraform apply   # ⚠️ node costs — destroy when done
# verify: az aks show -g rg-lab-aks -n aks-lab
#   az aks get-credentials -g rg-lab-aks -n aks-lab
#   kubectl get nodes
```

## Clean up
```bash
terraform destroy   # do this the moment you're done
```

## Common mistakes
| Mistake | Fix |
|---|---|
| `kubectl` "403 Forbidden" | run `az aks get-credentials` first (and the user needs the right **RBAC** role) — RBAC is on by default |
| Node "NotReady" | the node has **no internet egress** (it needs a **public IP** or a **NAT gateway**) to pull images |
| "Insufficient capacity" | the **VM size**/SKU is unavailable in the region — pick a different `vm_size` or **availability zone** |
