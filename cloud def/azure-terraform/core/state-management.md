# Terraform State Management (Azure) — Interview Questions

> **Cloud:** Azure · **IaC Tool:** Terraform · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~6 min

---

## Case A — Basic

**A1. What is Terraform state?**
**Answer:** A JSON record mapping your configuration to real Azure resource IDs and attributes, so Terraform knows what it manages and what changed.

**A2. What is the recommended Azure backend for state?**
**Answer:** The `azurerm` backend storing state in an Azure Storage blob container, with blob leasing for state locking.

**A3. How do you configure the Azure backend?**
**Answer:** `backend "azurerm" { resource_group_name, storage_account_name, container_name, key = "prod.terraform.tfstate" }`.

**A4. What is a state "key"?**
**Answer:** The blob path/name in the container for that state file — different keys isolate environments/components (`dev.tfstate`, `prod.tfstate`).

**A5. How does Azure state locking work?**
**Answer:** The backend acquires a lease on the state blob during operations; another operation can't write until the lease is released — equivalent to DynamoDB locking in AWS.

**A6. Why use a storage account for state instead of local files?**
**Answer:** It's shared, durable, versionable, and lockable — so a team collaborates safely and CI reads the same source of truth.

**A7. What is `terraform state list`?**
**Answer:** Lists all resource addresses in the current state, e.g. `azurerm_virtual_network.main`.

**A8. What is `terraform state show`?**
**Answer:** Prints the full state of one resource by address.

**A9. What is `terraform state rm`?**
**Answer:** Removes a resource from state without deleting the real Azure object — Terraform "forgets" it.

**A10. What is `terraform import`?**
**Answer:** Adopts an existing Azure resource into state using its ARM resource ID: `terraform import azurerm_virtual_network.vnet /subscriptions/.../resourceGroups/.../providers/Microsoft.Network/virtualNetworks/vnet1`.

**A11. What is `terraform state mv`?**
**Answer:** Moves a resource to a new address in state (after a rename or refactor) without recreating it.

**A12. What is `terraform apply -refresh-only`?**
**Answer:** Updates state to match Azure reality without changing resources — adopting drift made in the portal.

**A13. What happens if two people run apply simultaneously without locking?**
**Answer:** They can overwrite each other's state, causing lost records, orphaned resources, or duplicate deployments. Blob leasing serializes applies.

**A14. What is `terraform force-unlock`?**
**Answer:** Releases a stuck lease/lock after confirming no operation is actually running.

**A15. Why shouldn't you hand-edit the state file?**
**Answer:** Corrupting the JSON breaks the mapping to real resources. Use `state` subcommands or `moved` blocks instead.

## Case B — Advanced / Senior

**B1. How do you bootstrap the state backend (chicken-and-egg problem)?**
**Answer:** Create the storage account/container outside Terraform (CLI or a small bootstrap Terraform run with a local backend), or use a dedicated "bootstrap" state that manages only the backend resources, then configure the real backends.

**B2. How do `moved` blocks help Azure refactors?**
**Answer:** Declaring `moved { from = azurerm_vnet.a ; to = azurerm_vnet.b }` records a rename so the next plan updates state instead of destroying/recreating the resource.

**B3. How do you split a large Azure state into smaller ones?**
**Answer:** Use `terraform state mv -state-out=other.tfstate` to relocate resources, then give each component its own backend key (or workspace). Smaller states speed up plans and limit blast radius.

**B4. What are the tradeoffs of one state vs many states in Azure?**
**Answer:** One state is simpler for cross-references but slow and risky; many states are faster and safer but need more backend config and cross-state coordination (data sources/remote state).

**B5. How does the Azure backend handle state versioning/rollback?**
**Answer:** Enable blob soft-delete and versioning (or snapshots) on the storage account, so you can restore a previous state version after a bad apply.

**B6. What is the `-state` flag used for?**
**Answer:** Running a command against a specified state file instead of the active backend — useful for one-off migrations and importing into a non-current state.

**B7. How do you import a resource with nested identity (e.g. a VM with managed identity)?**
**Answer:** Import the resource by its ARM ID, then write matching config including `identity` blocks. Plan will show whether config matches; use `-refresh-only` to adopt exact current settings.

**B8. How do workspaces interact with the Azure backend?**
**Answer:** Workspaces are stored under different keys by default (`workspaces/<name>/...` unless you override `key`), giving isolated state per environment with the same config.

**B9. What is `terraform state pull` / `state push`?**
**Answer:** `pull` downloads the current state JSON; `push` uploads a state file. `push` is used for state migrations (e.g. moving to a new backend) — dangerous without care.

**B10. How do you migrate state between backends (local → Azure Storage)?**
**Answer:** Reconfigure the `backend` block and run `terraform init -migrate-state`, which copies state into the new backend. Verify with `state list`/`plan` before deleting the old state.

**B11. How do you detect drift on Azure resources managed by Terraform?**
**Answer:** `terraform plan -refresh-only` or a nightly CI `plan -detailed-exitcode` that alerts when exit code 2 (drift) — then reconcile by re-applying or adopting the change.

**B12. What are the risks of `terraform state rm` in Azure and how do you mitigate them?**
**Answer:** The Azure resource keeps running but is unmanaged (orphan risk, future import conflicts). Document why, and re-import or delete the resource promptly.

## Case C — Scenario

**C1. A teammate's apply corrupted the state blob. How do you recover?**
**Answer:** Restore the previous blob version/snapshot (or soft-deleted blob), then run `terraform plan` to reconcile with reality, using `-refresh-only` to adopt any drift since that version.

**C2. `terraform apply` is stuck waiting for a lease.**
**Answer:** Identify the holder (a crashed CI job or another engineer). If it's a dead process, `terraform force-unlock -force <id>` after verifying nothing is running; otherwise coordinate to wait.

**C3. You renamed an `azurerm_virtual_network` resource and plan shows destroy+recreate.**
**Answer:** Add a `moved` block (or `terraform state mv old new`) so Terraform treats it as a rename and keeps the real VNet — verify the plan is clean before applying.

**C4. You need to move the state backend from one storage account to another.**
**Answer:** Update the `backend` block to the new account/container, run `terraform init -migrate-state`, confirm `state list` matches, then decommission the old account after a verification window.

**C5. State contains secrets and an auditor wants them protected.**
**Answer:** Restrict the storage account (private endpoint, no public access, RBAC on the container), enable encryption (default) and soft-delete/versioning, and limit CI identities to least privilege.

**C6. A resource was deleted in the portal but still exists in Terraform state.**
**Answer:** `terraform plan` will propose to recreate it (config says it should exist). Decide: re-apply to restore it, or remove it from config and `state rm` the address to stop managing it.
