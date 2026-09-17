# Terraform Variables, Outputs & Locals (Azure) — Interview Questions

> **Cloud:** Azure · **IaC Tool:** Terraform · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~5 min

---

## Case A — Basic

**A1. What is an input variable?**
**Answer:** A parameter declared with a `variable` block and referenced as `var.name`, letting one config serve many environments. Values come from defaults, `-var`, `-var-file`, or `TF_VAR_*` env vars.

**A2. How do you declare a variable with a default?**
**Answer:** `variable "location" { type = string ; default = "eastus" }` — the default makes it optional.

**A3. What is a local value?**
**Answer:** A derived convenience value in a `locals` block, e.g. `locals { rg_name = "${var.prefix}-rg" }`, referenced as `local.rg_name`. Locals can't be set externally.

**A4. What is an output value?**
**Answer:** A value exposed after apply via `output "name" { value = ... }`, referenced from parent modules as `module.x.name`, e.g. the resource group ID or a VM's public IP.

**A5. How do you pass values on the CLI?**
**Answer:** `terraform plan -var="location=westeurope"` or `-var-file=prod.tfvars`. Later flags override earlier ones.

**A6. What is a `.tfvars` file?**
**Answer:** A file of `key = value` assignments loaded with `-var-file`; `terraform.tfvars` and `*.auto.tfvars` load automatically.

**A7. What variable types does Terraform support?**
**Answer:** `string`, `number`, `bool`, `list`, `set`, `map`, `object`, `tuple`, and `any`.

**A8. How do you validate a variable?**
**Answer:** A `validation` block asserting a `condition` with a custom `error_message`, e.g. forcing `location` to be a known Azure region.

**A9. What is `sensitive = true`?**
**Answer:** It redacts the value from plan/apply/output display — used for passwords, keys, and connection strings.

**A10. What does `terraform output` do?**
**Answer:** Prints output values from state; `-json` emits machine-readable output (e.g. a resource ID for a script).

**A11. What's the difference between a variable and a local?**
**Answer:** Variables are external inputs; locals are internal computed values. Locals can reference resources and other locals.

**A12. Can a module read the caller's variables automatically?**
**Answer:** No — modules are isolated. Values are passed in explicitly via module arguments matched to the module's variables.

**A13. How do you reference a map element?**
**Answer:** `var.tags["env"]` or `var.subnets["web"]`; iterate maps with `for_each`.

**A14. What happens if a required variable has no value?**
**Answer:** Terraform prompts interactively, or fails in non-interactive mode (CI, `-input=false`, or `TF_INPUT=0`).

**A15. How do you type a structured variable?**
**Answer:** `variable "vnet" { type = object({ name = string, address_space = list(string), subnets = map(object({ prefix = string })) }) }`.

## Case B — Advanced / Senior

**B1. What is the full variable precedence order?**
**Answer:** Lowest to highest: default < `terraform.tfvars` < `*.auto.tfvars` (alphabetical) < `-var-file` < `-var` < `TF_VAR_*` environment variables.

**B2. How do you centralize Azure defaults (region, tags) with locals?**
**Answer:** A `locals` block for common values (`default_tags`, `naming` prefixes, environment), merged into resources — keeps naming/tagging consistent across a large Azure estate.

**B3. When would you use `type = any` vs a concrete type?**
**Answer:** `any` accepts anything and eases compatibility, but loses validation/documentation. In published modules prefer concrete types (object/list) for a contract consumers can rely on.

**B4. What are `nullable` and how does it interact with optional object attributes?**
**Answer:** `nullable = false` forbids passing `null`. For objects, `optional(..., null)` marks attributes optional in newer Terraform versions, so callers can omit them without errors.

**B5. How do you expose a full set of Azure IDs for downstream modules?**
**Answer:** Output structured objects: `output "subnet_ids" { value = { for k, v in azurerm_subnet.s : k => v.id } }`, so consumers get a map keyed by name.

**B6. Why avoid shadowing variable names with locals?**
**Answer:** It hides the source of a value and confuses reviewers. Keep a clear convention: `var.` for inputs, `local.` for derived, `output` for results.

**B7. How do `for` expressions transform Azure resource lists?**
**Answer:** e.g. `[for nsg in azurerm_network_security_group.nsgs : nsg.id]` or map forms with conditions (`if`/`=>`) to build derived collections from resources.

**B8. What are preconditions and postconditions, and how do they apply to Azure resources?**
**Answer:** `precondition` blocks fail early if inputs/resource attributes violate a rule (e.g. subnet address space must fit the VNet); `postcondition` checks after apply. They make modules self-defending.

**B9. How do you handle Azure resource naming rules with variables?**
**Answer:** Validate names in `variable` blocks (regex for allowed chars, length limits per resource type), since many Azure resource names are immutable and have strict rules.

**B10. What is `TF_VAR_` usage for Azure secrets in CI?**
**Answer:** `TF_VAR_admin_password` supplies a password without writing it to files. Prefer Key Vault/secret stores referenced at runtime, and mark the variable `sensitive`.

**B11. How do you keep outputs stable for cross-stack consumption?**
**Answer:** Output stable IDs (resource group name, VNet/subnet IDs) that don't change on recreation, and document them as the module's public API — consumers depend on them.

**B12. What are the risks of over-parameterizing an Azure module?**
**Answer:** Too many knobs recreate a scripting language: hard to test, review, and document. Keep a small typed surface with defaults and compute the rest internally.

## Case C — Scenario

**C1. A VM's admin password appeared in plaintext in plan output.**
**Answer:** Mark the variable and any derived outputs `sensitive = true`, and re-run plan to confirm `<sensitive>` redaction. Also avoid echoing the password through non-sensitive outputs or `local-exec`.

**C2. Three teams want different naming conventions from one module.**
**Answer:** Provide `name_prefix` and optional `name` override inputs with validation, or a `naming` object input, so each team can follow its convention without forking the module.

**C3. A required variable is missing in CI and the job hangs.**
**Answer:** Run CI with `-input=false` (or `TF_INPUT=0`) so it fails fast, then supply the value via `-var-file=ci.tfvars` or `TF_VAR_*` and document it in the pipeline.

**C4. Dev and prod need different subnets, but you want one module.**
**Answer:** Pass subnets as a map input (`subnets = { web = "10.0.1.0/24", db = "10.0.2.0/24" }`) with per-environment tfvars, and compute address spaces inside the module with `cidrsubnet`.

**C5. After a refactor, `terraform output` returns stale values.**
**Answer:** Outputs reflect the last apply. Re-run `terraform apply` (or `refresh`) to update state, and in CI read `terraform output -json` only after a successful apply.

**C6. A consumer keeps passing an invalid Azure region.**
**Answer:** Add a `validation` block with a `contains([...known regions], var.location)` check and a clear error, or validate against `data "azurerm_locations"` — failing early instead of at apply time.
