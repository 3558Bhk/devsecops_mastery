# Azure Virtual Machines — Terraform how-to

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

**What:** a small Linux VM (B1s) in a VNet with a public IP, NSG, and NIC — the single most-referenced Azure compute resource.

**Interview angle (SDE3):**
- A VM = compute + a **network interface (NIC)** + an **OS disk** (managed disk) + optionally a **public IP** (via the NIC's IP config).
- `Standard_B1s`/`B2s` = the cheap "burstable" lab SKUs (pay-as-you-go; not for prod).
- **Managed disks**: the OS disk is a managed disk (`storage_account_type`), separate from the VM — it survives and can move.
- Scale **out** (more VMs) vs scale **up** (bigger VM) — interview loves asking when each is appropriate (stateless web = scale out; big-data job = scale up).
- **Availability Sets** (VMs, anti-affinity, fault/update domains) vs **VM Scale Sets** (managed, auto-scaled fleets).

## Run it
```bash
terraform init && terraform plan && terraform apply   # ⚠️ VM costs — destroy when done
# verify: az vm list -g rg-lab-vm
# connect: ssh azureadmin@<public-ip>   (password in the file)
```

## Clean up
```bash
terraform destroy   # do this the moment you're done
```

## Common mistakes
| Mistake | Fix |
|---|---|
| SSH "Connection refused" | the NSG has no inbound **22/tcp** rule — add one (or use **bastion**) |
| VM in a private subnet can't reach the Internet | it needs a **public IP** (or a **NAT gateway**) and a route |
| "Image not found" | the `source_image_reference` (publisher/offer/sku/version) must match a real Azure Marketplace image |
