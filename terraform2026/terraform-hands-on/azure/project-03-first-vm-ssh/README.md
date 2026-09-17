# Project 03 — Your First VM (SSH) (Azure)

**Difficulty:** ⭐⭐ · **⏱️ ~60 min** · **Cost:** ~$0.02/hr while the VM runs (B1s — destroy after!)

You will build a Linux VM from scratch — network, firewall, NIC, public IP, image — and
**SSH into it**. This is the full Azure networking stack in one file.

## The five parts (in order)

```
virtual_network → subnet → network_security_group (firewall)
                              → network_interface (the NIC)
                                  → public_ip
                                      → linux_virtual_machine
```

## Concepts practiced
- VNet / subnet / NSG / NIC / public IP → `../terraform-mastery/02-azure-provider/03-networking-vnets-nsgs.md`
- `source_image_reference` — publisher/offer/sku/version (Azure's "AMI") → `../terraform-mastery/02-azure-provider/04-virtual-machines.md`

## Files in this folder

| File | What it is |
|---|---|
| `variables.tf` | location, VM size, admin user/password |
| `main.tf` | all six resources |
| `outputs.tf` | public IP + the ssh command |
| `terraform.tfvars.example` | sample inputs |

## Run it

```bash
cd project-03-first-vm-ssh
cp terraform.tfvars.example terraform.tfvars      # set admin_password!
terraform init
terraform plan
terraform apply         # takes ~3–5 min (the VM must be provisioned)
```

## Verify it

```bash
terraform output ssh_command       # copy-paste this into a terminal
# e.g.  ssh adminuser@20.100.50.25
# once in:  cat /etc/os-release    # should say Ubuntu 22.04
```

## Break it (this is the learning)

1. Change `vm_size` to `Standard_B2s` → `plan` → **in-place resize** (no replacement). Apply, then back.
2. Change the Ubuntu `sku` from `22_04-lts` to `24_04-lts-gen2` → `plan` → **replacement** (image is immutable). Read it, don't apply.
3. Add an NSG rule for port 80 → `plan` → in-place update on the NSG only. Apply.

## Clean up

```bash
terraform destroy
```

## Common mistakes

| Mistake | Fix |
|---|---|
| SSH times out | the NSG's SSH rule — check `az network nsg rule list`; also wait a full minute after apply |
| `Authentication failed` in SSH | `admin_password` in tfvars doesn't match what you typed |
| `Operation could not be completed: ... sku` | `Standard_B1s` is rarely unavailable — if so, try `Standard_B2s` or another region |
| NIC "cannot be deleted" while the VM exists | destroy in the right order — `terraform destroy` handles it (VM first) |
