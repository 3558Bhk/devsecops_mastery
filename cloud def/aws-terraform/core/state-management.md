# Terraform State Management (AWS) — Interview Questions

> **Cloud:** AWS · **IaC Tool:** Terraform · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~6 min

---

## Case A — Basic

**A1. What is Terraform state?**
**Answer:** State is a JSON record mapping the resources in your configuration to their real AWS object IDs and attributes. It's how Terraform knows what it created previously and what needs to change.

**A2. Where is state stored by default?**
**Answer:** Locally, in `terraform.tfstate` in the working directory (the "local" backend). For teams you configure a remote backend.

**A3. What is a remote backend?**
**Answer:** A backend that stores state somewhere shared and durable — for AWS, typically an S3 bucket, optionally with DynamoDB for locking.

**A4. What is the recommended AWS backend configuration?**
**Answer:** S3 bucket with versioning and SSE enabled, plus a DynamoDB table for state locking, e.g. `backend "s3" { bucket, key, region, dynamodb_table }`.

**A5. Why shouldn't you edit the state file by hand?**
**Answer:** It's easy to corrupt the JSON and break the mapping to real resources. Terraform provides `state` subcommands for safe manipulation.

**A6. What is state locking?**
**Answer:** A mechanism (DynamoDB table for S3) that prevents two people or jobs from running apply concurrently and corrupting state. One operation holds the lock until it finishes.

**A7. What does `terraform state list` do?**
**Answer:** Lists all resource addresses currently tracked in state, e.g. `aws_instance.web`.

**A8. What does `terraform state show` do?**
**Answer:** Prints the full state (attributes and metadata) of a single resource by its address.

**A9. What does `terraform state rm` do?**
**Answer:** Removes a resource from state without destroying the real object — Terraform "forgets" it. Useful before re-importing or when retiring managed resources from config.

**A10. What does `terraform import` do?**
**Answer:** It adopts an existing real resource into state so Terraform manages it going forward, e.g. `terraform import aws_instance.web i-0abc123`. It writes state only; you must still write matching config.

**A11. What is `terraform refresh` (or `-refresh-only`)?**
**Answer:** It updates state to reflect the real world without applying changes — reconciling drift between state and actual AWS resources.

**A12. What is a state "key" in the S3 backend?**
**Answer:** The object path within the bucket where that workspace's state is stored, e.g. `prod/terraform.tfstate`. Different keys isolate different environments/components.

**A13. Why enable S3 versioning on the state bucket?**
**Answer:** So every state write keeps a history; if state is corrupted or a bad apply occurs, you can restore a previous version.

**A14. Why enable server-side encryption on the state bucket?**
**Answer:** State can contain sensitive values (passwords, ARNs, keys). SSE encrypts it at rest; you should also restrict read access.

**A15. What is a workspace's effect on state?**
**Answer:** Workspaces give you isolated state files (and locks) for the same config — e.g. `default` vs `prod` — typically stored under different backend keys.

## Case B — Advanced / Senior

**B1. What is the difference between state and configuration?**
**Answer:** Configuration is the desired state you author in HCL; state is the record of what Terraform actually manages and its last-known attributes. Plan diffs configuration against state (+ live refresh) to compute changes.

**B2. What is `terraform state mv` and when do you use it?**
**Answer:** It moves a resource to a new address in state (e.g. after renaming or moving it into a module). It preserves the resource so Terraform doesn't destroy/recreate it — critical during refactors.

**B3. How do `moved` blocks work?**
**Answer:** Declaring `moved { from = aws_instance.a ; to = aws_instance.b }` in config records a rename so state is updated on the next plan — cleaner and more declarative than ad-hoc `state mv`.

**B4. What is `terraform taint` and why is it now deprecated in favor of `replace`?**
**Answer:** Taint marked a resource for destruction/recreation on next apply. `-replace=ADDRESS` does the same thing more explicitly without mutating state flags, so it's the modern approach.

**B5. What happens if two applies race without locking?**
**Answer:** Both read the same state, both write different results, and one overwrites the other — resources can be orphaned or double-provisioned. DynamoDB locking serializes applies.

**B6. How do you split a large state into smaller states?**
**Answer:** Move resources with `terraform state mv -state-out=other.tfstate`, then configure separate backends/keys per component, or re-import into new root modules. This shrinks blast radius and speeds plans.

**B7. What's the risk of `terraform state rm` and how do you mitigate it?**
**Answer:** The real resource keeps running but is no longer managed, which can leave orphans or cause import conflicts. Document why, and re-import or delete the resource explicitly soon after.

**B8. How does Terraform handle resources that exist in state but not in config?**
**Answer:** On plan/apply it proposes to destroy them (unless they're excluded via `-target` or moved into another state). This is why deleting a resource block without intent is dangerous.

**B9. Explain `terraform plan -refresh=false`.**
**Answer:** It skips the live refresh so planning uses only config vs cached state — faster, and useful when credentials allow read of state but not of some live APIs. The plan may be stale, so use it carefully.

**B10. What does `terraform force-unlock` do and when is it justified?**
**Answer:** It releases a stuck lock (e.g. a crashed apply). Only use it after confirming no other operation is actually running, or you can cause concurrent applies.

**B11. How do you detect and fix drift systematically?**
**Answer:** Run `terraform plan -refresh-only` or `apply -refresh-only` to adopt drift, diff config to see differences, then re-apply to converge. In CI, a nightly `plan -detailed-exitcode` flags drift as an alert.

**B12. What are the tradeoffs of one monolithic state vs many small states?**
**Answer:** Monolith = simpler cross-referencing but slower plans and bigger blast radius. Many states = faster, safer, but more backend configs, more cross-state coordination (data sources/remote state), and harder refactors.

## Case C — Scenario

**C1. A teammate ran apply and the state file is now corrupted or lost. How do you recover?**
**Answer:** Restore the last good version from S3 versioning, verify with `terraform plan` that it matches reality, and `-refresh-only` to reconcile any drift. If no backup exists, re-import resources and accept some manual cleanup.

**C2. `terraform apply` hangs waiting for a lock. What do you do?**
**Answer:** Identify who/what holds the lock (CI job, another engineer). If it's a genuine crash, `terraform force-unlock -force <lock-id>` after verifying nothing is running. Otherwise wait and coordinate.

**C3. You renamed a resource block and the plan now wants to destroy and recreate it. How do you avoid downtime?**
**Answer:** Add a `moved` block (or `terraform state mv old new`) before applying, so Terraform treats it as a rename and updates state instead of replacing the real resource.

**C4. You need to move a set of resources out of one root module into a new, separate root module.**
**Answer:** Write the new root module's config, then `terraform state mv -state-out=<new-state>` each resource address, or import them into the new module's state and remove from the old. Verify each plan is clean before any apply.

**C5. The DynamoDB lock table's capacity keeps being exhausted during busy days.**
**Answer:** Switch the table to on-demand billing/capacity, ensure a single table (or keyed by state) is used consistently, and check for abandoned locks. Optionally partition large teams into separate state keys/tables.

**C6. An auditor asks: "who changed this instance, when, and what did it look like before?"**
**Answer:** Point to the S3 backend's version history (every apply writes a new state version), plus the VCS/CI audit trail of the config change that produced it, and CloudTrail for out-of-band API changes.
