# NSG Inbound Rules — Terraform how-to

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

**What:** inbound NSG rules: allow HTTPS from the Internet, block plain HTTP, allow RDP only from an office IP.

**Interview angle (SDE3):**
- Inbound rules define **who can initiate** a connection in (source → destination, port, protocol).
- `source_address_prefix` accepts a single IP, a CIDR, `*` (any), or **service tags** (`Internet`, `VirtualNetwork`, `AzureLoadBalancer`) — service tags are the clean way to say "from anywhere but on the Internet".
- The interview favourite: **allow HTTPS, deny HTTP** as two rules, and explain why the deny must have the LOWER (earlier) priority to win.

## Run it
```bash
terraform init && terraform plan && terraform apply
# verify: az network nsg list-rule -g rg-lab-nsgin -n nsg-inbound
```

## Clean up
```bash
terraform destroy
```

## Common mistakes
| Mistake | Fix |
|---|---|
| Rule "not working" | a **lower-priority number** rule matched first — priorities are unique and evaluated ascending |
| Allowed the wrong direction | `direction = "Inbound"` is for *incoming* traffic — outbound is a separate rule (NSG is stateless) |
| `source_address_prefix = "0.0.0.0/0"` | works, but the clearer **service tag** is `Internet` — it's the same thing, just readable |
