# Project 04 — Looping: for_each and count (Azure)

**Difficulty:** ⭐⭐ · **⏱️ ~45 min** · **Cost:** ~$0.04/hr (2× B1s — destroy after!)

Same two-loop lesson as AWS project 04, with Azure flavor:
`for_each` over **named NSG rules**, `count` over **identical VMs**.

## Concepts practiced
- `for_each` over a `map(object(...))` — the most practical use (rules, subnets, users)
- `count` + `count.index`
- Splat expressions (`[*]`)
- → `../terraform-mastery/00-terraform-core/07-advanced-resource-configuration.md`

## Files in this folder

| File | What it is |
|---|---|
| `variables.tf` | `rules` (a map of objects) + `vm_count` (a number) |
| `main.tf` | VNet/subnet/NSG + N rules + N VMs |
| `outputs.tf` | VM names and IPs |

## Run it

```bash
cd project-04-for-each-and-count
terraform init
terraform plan        # count the resources: 1 RG + 1 VNet + 1 subnet + 1 NSG + 3 rules + 2 NICs + 2 VMs = 10
terraform apply
```

## Verify it

```bash
az network nsg rule list --nsg-name tf-loop-nsg -g tf-loop-rg -o table   # ssh, http, https
az vm list -g tf-loop-rg -o table                                        # two VMs
terraform output vm_names
```

## Break it (this is the learning)

1. Add `"rdp" = { priority = 300, port = 3389 }` to `rules` in the file → `plan` → **one new rule only**. Apply.
2. Remove `"http"` → `plan` → only that rule destroyed (for_each identity by key). Apply.
3. `vm_count = 3` → `plan` → a third VM `tf-loop-vm[2]` appears. Apply. Back to 2: VM `[2]` goes away.

## Clean up

```bash
terraform destroy
```

## Common mistakes

| Mistake | Fix |
|---|---|
| `InvalidSecurityRulePriority` | two rules share a priority — priorities must be unique within an NSG |
| `for_each` over a map: "invalid keys" | map keys can't be empty; keep them lowercase words |
| Changing a rule's `port` wants a replacement | name/priority are immutable on NSG rules — change the rule's *name* too if you need a clean update, or accept the replace |
