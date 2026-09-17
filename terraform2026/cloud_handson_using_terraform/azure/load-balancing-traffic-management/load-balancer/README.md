# Azure Load Balancer — Terraform how-to

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

**What:** an external Standard LB: frontend (public IP) + backend pool + TCP/HTTP probe + a load-balancing rule.

**Interview angle (SDE3):**
- Load Balancer = **Layer 4** (TCP/UDP) — it balances by port, no knowledge of the HTTP content. (Application Gateway = Layer 7.)
- The 4 pieces: **frontend IP** (the VIP), **backend pool** (the VMs), **probe** (health check), **rule** (maps frontend port → pool).
- A VM in the pool must have the **backend pool IP** — with a standard LB you typically need a **public IP on the NIC** (the pool uses the NIC's IP).
- LB is **stateless**; no TLS termination (that's App Gateway / VM).

## Run it
```bash
terraform init && terraform plan && terraform apply
# add backend VMs: az network lb address-pool address create ...
```

## Clean up
```bash
terraform destroy
```

## Common mistakes
| Mistake | Fix |
|---|---|
| Backend "Not Healthy" | the **probe** is failing (wrong port/protocol, or the VM firewall blocks the probe source `AzureLoadBalancer`) — allow `AzureLoadBalancer` on the VM NSG |
| No traffic reaching the VM | the VM's IP isn't in the **backend pool** (or it uses a different NIC) |
| TLS not working | the classic LB doesn't do TLS termination — use **Application Gateway** for Layer 7 + TLS offload |
