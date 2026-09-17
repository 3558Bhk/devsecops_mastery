# Azure Basic Networking — Terraform how-to

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

**What:** the foundation: Resource Group + VNet + app/db subnets + NSG + a public IP.

**Interview angle (SDE3):**
- VNet = a virtual **network in a region**; subnets partition it; NSGs are the **firewall** (at subnet or NIC level).
- NSG rules are **priority** (100–4096, lower = first) and **directional**; the default is "allow within VNet, deny everything inbound from outside" (default NSGs attached automatically).
- **ASG vs NSG**: NSG = stateless (inbound + outbound are separate rules); **ASG = stateful** (return traffic is automatic).

## Run it
```bash
terraform init && terraform plan && terraform apply
# verify: az network vnet list --query "[?name=='vnet-lab'].addressSpace.addressPrefixes" -o table
```

## Clean up
```bash
terraform destroy   # destroying the resource group removes everything
```

## Common mistakes
| Mistake | Fix |
|---|---|
| "No address space available" | the subnet prefix must be **inside** the VNet's address space (e.g. 10.1.0.0/24 inside 10.1.0.0/16) |
| Inbound traffic dropped | default NSG denies inbound from *outside* the VNet — add an explicit inbound rule |
| Two VNets can't talk | they need **peering** or a hub — same region ≠ automatic routing |
