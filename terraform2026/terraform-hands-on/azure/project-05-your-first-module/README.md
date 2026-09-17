# Project 05 — Your First Module (Azure)

**Difficulty:** ⭐⭐⭐ · **⏱️ ~60 min** · **Cost:** ~$0.02/hr (one B1s — destroy after!)

Same lesson as AWS project 05: a reusable **VNet module** + a root that calls it.
The module creates three subnets (`web`, `app`, `data`) with `for_each` over a map —
so you can add a fourth later by editing one list.

## Structure

```
project-05-your-first-module/
├── main.tf                  ← ROOT: calls the module + one VM in the web subnet
├── variables.tf             ← ROOT inputs
├── outputs.tf               ← ROOT outputs (read from the module)
└── modules/
    └── vnet/                ← CHILD MODULE
        ├── main.tf
        ├── variables.tf
        └── outputs.tf
```

## Run it

```bash
cd project-05-your-first-module
terraform init
terraform plan        # resources appear as module.vnet.* — that's the module at work
terraform apply
```

## Verify it

```bash
terraform output subnets      # web/app/data subnet IDs
az network vnet list -g tf-mod-rg -o table
az vm list -g tf-mod-rg -o table          # one VM, sitting in the web subnet
```

## Break it (this is the learning)

1. Add `"cache" = "10.5.3.0/24"` to the `subnets` variable's default in `modules/vnet/variables.tf`
   → `plan` → **one new subnet**, nothing else. Apply.
2. Change the root's `prefix` to `10.9.0.0/16` → `plan` → the VNet updates in place;
   subnets are replaced (their CIDRs move). Read carefully, then revert.
3. Delete the VM from the root `main.tf` → `plan` → only the VM goes; the module's subnets stay.

## Clean up

```bash
terraform destroy
```

## Common mistakes

| Mistake | Fix |
|---|---|
| `No declaration for "module.vnet"` | typo in the `source` path — it must be `./modules/vnet` |
| `Error: Unsupported block: terraform` inside the module | child modules never declare `terraform {}`/`provider {}` — the root owns them |
| Subnet "cannot overlap" | your new subnet CIDR overlaps an existing one — use a fresh /24 slice |
