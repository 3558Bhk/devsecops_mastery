# Global Accelerator — Terraform how-to

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

**What:** two **anycast** static IPs that route each client to the **healthiest region** (via AWS's backbone, not the public internet).

**Interview angle (SDE3):**
- GA sits in front of NLBs / EC2 IPs / EIPs in **2+ regions**; health checks steer traffic to the best endpoint.
- It's about **latency + resilience** (one region dies → traffic reroutes in seconds), not a CDN.
- $$$: accelerator ~$0.30/hr + data transfer — this is the priciest "how-to" in this folder. **Destroy immediately.**

## Run it
```bash
terraform init && terraform plan && terraform apply   # ⚠️ costs real money from second one
# verify: aws globalaccelerator list-accelerators
# test: curl http://<one of the two anycast IPs>
```

## Clean up
```bash
terraform destroy   # do this the moment you're done
```

## Common mistakes
| Mistake | Fix |
|---|---|
| Traffic never leaves region A | endpoint groups are weighted; set `traffic_dial_percentage` to force B's share |
| "The IP changed" | the anycast IPs are static — but the backend (NLB) IPs move; publish the GA IPs |
