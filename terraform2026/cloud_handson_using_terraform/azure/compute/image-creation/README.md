# Azure Image Creation — Terraform how-to

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

**What:** a "golden" VM → an **Azure Image** (a template of its disks) → a second VM created FROM that image (the golden-AMI pattern).

**Interview angle (SDE3):**
- An **Image** = a template of one or more disks (here: the VM's OS disk) — the Azure equivalent of an AWS **AMI**.
- The workflow: build/patch/configure a VM → **generalize** (Sysprep on Windows) → **create an image** → **deploy new VMs from the image** (fast, identical).
- This is how you do **config as code for the OS**: bake software into the image, then scale out identical VMs (VMSS from the image).
- Images are **region-scoped** (shared across regions via **Shared Image Gallery**).

## Run it
```bash
terraform init && terraform plan && terraform apply   # ⚠️ 2 VMs — destroy when done
# the image: az image list -g rg-lab-image
# a new VM from it: az vm create --image <image-id> ...
```

## Clean up
```bash
terraform destroy   # do this the moment you're done
```

## Common mistakes
| Mistake | Fix |
|---|---|
| "Can't create image from a running VM" | the source VM's disk must be **generalized** (deprovisioned) — on Windows run Sysprep; Terraform images work best from a stopped VM |
| New VM from the image has the same hostname/keys | a **generalized** image must not contain a hostname/SSH keys — use a **custom script**/Cloud Init at deploy to set per-VM config |
| Image not in another region | images are **regional** — use a **Shared Image Gallery (SIG)** to replicate across regions |
