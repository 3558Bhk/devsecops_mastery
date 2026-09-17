# Terraform Basics (AWS) — Interview Questions

> **Cloud:** AWS · **IaC Tool:** Terraform · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~7 min

---

## Case A — Basic

**A1. What is Terraform and what problem does it solve?**
**Answer:** Terraform is HashiCorp's Infrastructure-as-Code tool. You declare the desired end-state of your infrastructure in HCL, and Terraform reconciles the real world to that state via provider APIs. It removes manual clicking, gives repeatable/reviewable changes, and tracks resources in a state file.

**A2. What is HCL?**
**Answer:** HCL (HashiCorp Configuration Language) is Terraform's declarative language. It uses blocks, arguments, and expressions and is designed to be human-readable and machine-friendly, unlike raw JSON.

**A3. What is the core Terraform workflow?**
**Answer:** `terraform init` (set up working dir, download providers), `terraform plan` (preview changes), `terraform apply` (make changes), and `terraform destroy` (tear down). `validate` and `fmt` support it.

**A4. What does `terraform init` do?**
**Answer:** It initializes the working directory: installs required providers and modules, configures the backend, and creates the `.terraform` directory plus the `.terraform.lock.hcl` dependency lock file.

**A5. What does `terraform plan` do?**
**Answer:** It compares the desired configuration against the current state and real resources, then prints the changes Terraform would make (create/update/destroy) without applying them.

**A6. What does `terraform apply` do?**
**Answer:** It executes the plan: calls provider APIs to create, update, or delete resources, then updates the state file. Without arguments it shows a plan and prompts for confirmation first.

**A7. What is a provider?**
**Answer:** A provider is a plugin that translates Terraform config into API calls for a platform. The `aws` provider talks to AWS; each provider defines its own resources and data sources.

**A8. What is a resource block?**
**Answer:** A `resource` block declares a single object Terraform manages, e.g. `resource "aws_instance" "web"`. The resource type (`aws_instance`) is provider-defined and the name (`web`) is local.

**A9. What is a data source?**
**Answer:** A `data` block is a read-only query of existing infrastructure not managed by this config, e.g. `data "aws_ami" "latest"`. It doesn't create anything but its attributes can feed resources.

**A10. What is the state file (terraform.tfstate)?**
**Answer:** It's a JSON file that maps resources in your config to real AWS object IDs and records their attributes. It's how Terraform knows what exists and what changed.

**A11. What do `terraform fmt` and `terraform validate` do?**
**Answer:** `fmt` reformats HCL to the canonical style; `validate` checks syntax and internal consistency (references, types) locally without contacting providers.

**A12. What is `.terraform.lock.hcl`?**
**Answer:** A lock file pinning the exact provider versions (and checksums) your config uses, so teammates and CI get identical provider binaries.

**A13. What is the difference between `.tf` and `.tfvars` files?**
**Answer:** `.tf` files contain the configuration (resources, variables with defaults). `.tfvars` files supply values for input variables, often per environment. `.tf` is loaded automatically; `.tfvars` must be passed with `-var-file`.

**A14. What does `terraform destroy` do?**
**Answer:** It deletes every resource tracked in the current state (in reverse dependency order). It's the inverse of apply and also supports `-target` for partial teardown.

**A15. What is an argument versus an expression?**
**Answer:** An argument assigns a value to a name inside a block (e.g. `ami = "ami-123"`). An expression is code that computes a value (e.g. `"${var.prefix}-web"` or a function call).

## Case B — Advanced / Senior

**B1. Explain plan files and `-out`.**
**Answer:** `terraform plan -out=tfplan` writes a binary plan file; `terraform apply tfplan` executes exactly that plan. This guarantees CI applies only what was reviewed, even if config changed in between.

**B2. How does resource addressing work?**
**Answer:** Resources are addressed by `resource_type.name[index]`, e.g. `aws_instance.web[0]`, or across modules as `module.vpc.aws_subnet.public`. This is used in `-target`, `state mv`, and `taint`.

**B3. How do implicit vs explicit dependencies differ?**
**Answer:** Implicit dependencies are inferred when one resource references another's attribute (e.g. subnet ID). `depends_on` is explicit and forces ordering when no reference exists — use it sparingly since it can over-constrain the graph.

**B4. Why should state not be committed to Git, and where should it live?**
**Answer:** State can contain secrets and is machine-generated. It should live in a remote backend — for AWS, an S3 bucket with versioning, SSE, and a DynamoDB table for locking — so teams share one source of truth.

**B5. Compare `count` and `for_each`.**
**Answer:** `count` creates N copies indexed 0..N-1; changing the list reshuffles indexes and can force replacements. `for_each` keys resources by set/map keys, so add/remove operations are stable and don't destroy unrelated instances.

**B6. What are the lifecycle meta-arguments?**
**Answer:** `create_before_destroy`, `prevent_destroy`, and `ignore_changes`. They control replacement ordering, safety rails on destructive changes, and which attribute diffs to suppress.

**B7. What does `-refresh-only` do?**
**Answer:** It updates the state to match reality without changing infrastructure — used to import drift (e.g. a security group edited in the console) into state so future plans are clean.

**B8. When are provisioners acceptable, and what are the types?**
**Answer:** Provisioners (`local-exec`, `remote-exec`, `file`, and destroy provisioners) run scripts as a last resort when the provider has no native support. Prefer provider-native mechanisms (user_data, SSM) because provisioners don't participate in diffs and make state drift-prone.

**B9. What is `terraform console` and `plan -json` useful for?**
**Answer:** `console` is an interactive REPL for evaluating expressions/functions. `plan -json` produces a machine-readable plan for CI tooling, policy checks (OPA/Sentinel), and cost estimation.

**B10. How do you decide between modules and plain resources?**
**Answer:** Extract a module when the same pattern repeats (e.g. a VPC or app stack) and when you want versioned, tested, reusable building blocks. Keep one-off resources flat — premature modularization adds indirection.

**B11. How does Terraform handle secrets in state?**
**Answer:** Mark outputs/inputs `sensitive = true` to redact values from console and plan output. The underlying value may still be stored in state, so the state backend itself must be protected (encryption, least-privilege access).

**B12. What is a backend and why use one?**
**Answer:** A backend defines where state is stored and whether operations lock. Remote backends (S3, Terraform Cloud) enable team collaboration, locking, and state history, versus the default local backend.

## Case C — Scenario

**C1. Your team is adopting Terraform for an existing AWS account. What are your first steps?**
**Answer:** Establish remote state (S3 + DynamoDB locking) and a repo layout; pick the provider version and pin it in `.terraform.lock.hcl`; decide module boundaries; import the most critical existing resources; and wire CI to run plan on PRs. Don't mass-import everything day one.

**C2. A `terraform plan` unexpectedly shows an RDS instance will be destroyed and recreated. How do you investigate?**
**Answer:** Look at the diff for the attribute forcing replacement (often `identifier`, `name`, or an immutable parameter that changed). Confirm whether it was changed intentionally; if not, revert the config change or use `ignore_changes`/`prevent_destroy` as a guard, then re-plan.

**C3. Your single `main.tf` has grown to 3,000 lines. How do you refactor it?**
**Answer:** Split by logical domain into modules (network, compute, data, security) with inputs/outputs, move resources with `terraform state mv` so nothing is recreated, keep shared values in locals/data sources, and add per-module READMEs. Verify each `state mv` keeps the plan empty.

**C4. Someone changed a security group in the console; now your config is out of sync. How do you fix it?**
**Answer:** Run `terraform plan -refresh-only` (or `apply -refresh-only`) to adopt the drift into state, then either update the config to match or `terraform apply` to restore the config's version. Enforce the process with least-privilege IAM so console edits are rare.

**C5. You need dev/staging/prod environments from one codebase. What approaches exist?**
**Answer:** Separate state per environment (workspaces or separate backend configs) with `-var-file`/input variables for differences, shared modules for the common shape, and CI gates that promote dev → staging → prod. Workspaces suit small variations; separate directories/backends suit environments that differ structurally.

**C6. Management wants the whole account imported into Terraform within a month. What's a safe plan?**
**Answer:** Phase it by blast radius: start with stateless/cheap resources, use `terraform import` and `aws_` data sources, adopt existing objects into state (not recreate), keep manual freeze on imported resources, and automate a daily plan/drift check until import is complete.
