# ASG (App Security Group) — Terraform how-to

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

**What:** a **stateful** application security group attached to a network interface (the rule is shown as an `az` CLI example — in azurerm **v5** the provider no longer manages ASG rules).

**Interview angle (SDE3):**
- **ASG vs NSG**: NSG = *stateless*, per subnet/NIC, needs separate inbound+outbound rules; ASG = *stateful* — "allow inbound 8080" automatically allows the **return** traffic, so one rule is enough.
- ASG is attached to a **network interface** (you can associate multiple ASGs per NIC).
- Best practice: **NSG for the perimeter, ASG for the service-to-service** (east-west) rules — the stateful model makes east-west simple.

## Run it
```bash
terraform init && terraform plan && terraform apply
# add the rule (v5: rules are not in the provider):
#   az network asg rule create --name allow-8080-in --priority 100 --direction Inbound \
#     --access Allow --protocol Tcp --destination-port-ranges 8080 \
#     --source-address-prefixes VirtualNetwork --resource-group rg-lab-asg --name asg-app
# verify: az network nic asg list -g rg-lab-asg -n nic-asg
```

## Clean up
```bash
terraform destroy
```

## Common mistakes
| Mistake | Fix |
|---|---|
| "ASG rule doesn't apply to my subnet" | ASG is **NIC-level**, not subnet-level — attach it to the network interface, not the subnet |
| Wrote an outbound rule too and "it doubled up" | ASG is stateful — the return path is implicit; you only write the inbound allow |
| Multiple ASGs on one NIC | they're **unioned** (any allow wins) — the same "first match wins by priority" logic applies |
