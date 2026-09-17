# Terraform Variables, Outputs & Locals (AWS) — Interview Questions

> **Cloud:** AWS · **IaC Tool:** Terraform · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~6 min

---

## Case A — Basic

**A1. What is an input variable?**
**Answer:** A value you parameterize so config can be reused, declared with a `variable` block and referenced as `var.name`. Values come from defaults, `-var`, `-var-file`, or env vars.

**A2. How do you declare a variable with a default?**
**Answer:** `variable "region" { type = string ; default = "us-east-1" }`. The default makes the variable optional.

**A3. What is a local value?**
**Answer:** A computed convenience value declared in a `locals` block, e.g. `locals { name = "${var.prefix}-web" }`, referenced as `local.name`. Locals cannot be set from outside.

**A4. What is an output value?**
**Answer:** A value exposed after apply, declared with `output "name" { value = ... }`, referenced as `module.x.name` from a parent module. Outputs surface IDs/ARNs and can be printed with `terraform output`.

**A5. How do you pass a value on the CLI?**
**Answer:** `terraform plan -var="instance_type=t3.micro"` or `-var-file=prod.tfvars`. Order matters: later `-var`/`-var-file` flags override earlier ones.

**A6. What is a `.tfvars` file?**
**Answer:** A file of `key = value` assignments for input variables, loaded with `-var-file`. `terraform.tfvars` and `*.auto.tfvars` load automatically.

**A7. What types can a variable be?**
**Answer:** `string`, `number`, `bool`, and collections `list`, `set`, `map`, plus `object` and `tuple` for structural typing, and `any`.

**A8. How do you reference an element of a list/map variable?**
**Answer:** `var.subnets[0]` or `var.tags["env"]`. With `for_each` you'd iterate `for_each = var.subnets`.

**A9. What is variable validation?**
**Answer:** A `validation` block inside a `variable` block that asserts a condition and returns a custom error message, e.g. forcing an instance type to start with "t3.".

**A10. What does `terraform output` do?**
**Answer:** Prints output values from the current state; `terraform output name` prints one, `-json` emits machine-readable output for scripts.

**A11. What is the difference between locals and variables?**
**Answer:** Variables are inputs set from outside; locals are internal derived values computed inside config. Locals can reference other locals and resources.

**A12. Can a module read the caller's variables automatically?**
**Answer:** No — modules are isolated. The caller must pass values in explicitly via module arguments; the module declares matching variables.

**A13. What is `sensitive = true` on an output?**
**Answer:** It redacts the value from the console and `terraform output` (shows `<sensitive>`), preventing accidental disclosure of secrets.

**A14. How do you give a variable a type with attributes?**
**Answer:** Use an object type: `variable "app" { type = object({ name = string, ports = list(number) }) }`.

**A15. What happens if a required variable has no value at plan time?**
**Answer:** Terraform prompts interactively (or errors in non-interactive/CI mode, unless `TF_INPUT=0` or `-input=false` forces an error).

## Case B — Advanced / Senior

**B1. What is variable precedence order?**
**Answer:** From lowest to highest: defaults < `terraform.tfvars` < `*.auto.tfvars` (alphabetical) < `-var-file` < `-var` < environment variables (`TF_VAR_name`). Later CLI flags override files.

**B2. When would you use a `set` vs a `list` variable?**
**Answer:** Use a set when order is irrelevant and duplicates must be excluded (e.g. unique AZ names); use a list when order matters. Sets also work better with `for_each` for stable keys.

**B3. What is `type = any` and when is it appropriate?**
**Answer:** It accepts any value. It's convenient for compatibility but weakens validation and documentation — prefer concrete types, especially in published modules.

**B4. How do `nullable` and `sensitive` variable arguments behave?**
**Answer:** `nullable = false` forbids explicitly passing `null` (useful so resources don't silently drop arguments). `sensitive = true` hides the value in plan/apply output and any expression it feeds.

**B5. Explain `TF_VAR_` environment variables.**
**Answer:** Any env var named `TF_VAR_<name>` supplies a value for variable `<name>`. It's a common way to inject secrets in CI without writing them to files. Complex types are parsed as HCL (or JSON with `TF_VAR_...` set to JSON? — actually typed via HCL parsing).

**B6. Why shouldn't modules declare `locals` that shadow inputs?**
**Answer:** It creates confusion and hidden coupling. Keep a clear convention: inputs via `var.`, derived values via `local.`, and expose only `output`. Shadowing names between var/local is legal but unmaintainable.

**B7. How do you output structured data for downstream automation?**
**Answer:** Build a consolidated object output, e.g. `output "endpoints" { value = { web = aws_instance.web.public_ip, db = aws_db_instance.db.endpoint } }`, then `terraform output -json endpoints` for scripts.

**B8. How does `for_each` interact with map/list variables?**
**Answer:** `for_each = var.subnets` creates one resource per map key (stable identity) — safer than `count` for add/remove. Sets also work but maps give meaningful keys.

**B9. What are the risks of over-parameterizing a module?**
**Answer:** Too many variables recreate a scripting language inside HCL: hard to test, document, and review. Keep a small, well-typed surface with sensible defaults; compute the rest internally.

**B10. How do you validate variable values that depend on each other?**
**Answer:** Use `validation` blocks for single-variable checks and `precondition` blocks on resources/data sources (or `lifecycle` postconditions) for cross-variable or post-apply checks, failing early with clear messages.

**B11. How are locals scoped?**
**Answer:** Locals are visible within their module only; child modules do not inherit them. Shared values must be passed as inputs or recomputed via data sources.

**B12. What's the difference between `terraform output` values in state vs config?**
**Answer:** Outputs are stored in state after apply. If an output is defined but resources changed, it reflects the last apply's value until you re-apply. Use `-json` to read current state outputs in CI.

## Case C — Scenario

**C1. Your module is used by three teams with different naming conventions. How do you design the inputs?**
**Answer:** Provide a `name_prefix` and optional full `name` override, sensible defaults, object-typed options with `optional()` attributes for newer versions, and clear validation. Avoid forcing one convention; document with examples.

**C2. A secret is printed in plaintext in `terraform plan` output. How do you fix it?**
**Answer:** Mark the variable and the output `sensitive = true`, and avoid passing secrets through resources that echo them into non-sensitive outputs. Re-run plan to confirm `<sensitive>` redaction.

**C3. A required variable has no default and CI is failing non-interactively.**
**Answer:** Supply it via `-var-file=ci.tfvars`, `TF_VAR_*` env var, or add a safe default. Ensure CI uses `-input=false` so missing values fail loudly instead of hanging.

**C4. Dev needs different subnets per AZ than prod, but you want one module.**
**Answer:** Make subnets a map input (`subnets = { a = "10.0.1.0/24", ... }`) and pass per-environment values via `dev.tfvars`/`prod.tfvars`. Compute AZs from `data "aws_availability_zones"` inside the module.

**C5. After a refactor, `terraform output` returns stale values.**
**Answer:** Outputs reflect the last successful apply, so re-run `terraform apply` (or `refresh`) to update them. For automation, read `terraform output -json` only after apply in the pipeline.

**C6. A module consumer keeps passing invalid instance types. How do you harden the module?**
**Answer:** Add a `validation` block with a regex (e.g. `^t3\\.|^m5\\.`) and an informative error message, and document supported types. Optionally `precondition` on the resource for checks needing computed data.
