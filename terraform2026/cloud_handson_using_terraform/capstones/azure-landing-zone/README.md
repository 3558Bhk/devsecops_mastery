# Capstone 3 — Azure Landing Zone (hub & spoke, governed)

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

**What:** an enterprise-style **landing zone** in one apply:
**Hub VNet** (gateway subnet) + **Spoke VNet** (app + db subnets) + **peering** + **NSG flow logs** (→ storage + Log Analytics) + **Log Analytics workspace** + **Monitor** (action group + metric alert) + **Key Vault** (RBAC) + **App Service** + **Azure SQL** + **RSV backup** (policy + protected VM).

**Why this is a capstone (the story you tell in the interview):**
- **Network**: the **hub & spoke** pattern — spokes peer to the hub (where the VPN/ExpressRoute gateway will live), so east-west traffic is centralized and controllable.
- **Visibility**: **NSG flow logs** (every allow/deny) → raw storage + **traffic analytics** in **Log Analytics**; a **Monitor** metric alert → an **action group** (email).
- **Identity/secrets**: **Key Vault** with **RBAC** (`rbac_authorization_enabled = true`) + a **user-assigned managed identity** + a **Key Vault Secrets Officer** role — the "no stored keys" pattern.
- **PaaS + data**: **App Service** (F1) in the spoke, **Azure SQL** (General Purpose, TDE, 7-day PITR) behind a firewall rule.
- **DR**: a **Recovery Services Vault** + a **backup policy** + a **protected VM** (daily, 7-day retention).

**Run it:**
```bash
cd capstones/azure-landing-zone
terraform init && terraform plan && terraform apply   # ⚠️ VM, App Service, SQL, flow logs cost — DESTROY after
terraform destroy
```

**Interview questions to be ready for:**
1. "Why hub & spoke instead of meshing the spokes?" — **N peering links instead of N×(N-1)/2**, and the **hub is the choke point** (where the VPN/ExpressRoute gateway + central controls live).
2. "Peering is transitive, right?" — **No.** Peering is **not transitive**; spoke-to-spoke traffic still routes **through the hub** (A → hub → B). That's the design, not a bug.
3. "How do you find out why a connection was blocked?" — **NSG flow logs** (was it a DENY?) + the **effective NSG rules** + the **effective route table**.
4. "Where does the app's DB password live?" — **Key Vault**; the App Service has a **managed identity** granted **Key Vault Secrets Officer** (RBAC, v5), so there's **no key to rotate in code**.
5. "What if a VM is corrupted?" — the **RSV** has a **recovery point** (daily, 7-day retention) → restore to a new VM (the `rsv-restore` service folder).
6. "How do you get a security baseline?" — add **Defender for Cloud** (the `defender-for-cloud` service folder) + a **Policy**/Blueprint.
