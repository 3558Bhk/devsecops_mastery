# 1. Introduction, Installation & the CLI

> **⏱️ Time to complete: ~45 min** (read + run the "hello" lab)

## 1.1 What is Infrastructure as Code (IaC)?

IaC = managing infrastructure (servers, networks, databases, DNS…) with **machine-readable definition files** under **version control**, instead of clicking through a console.

Two philosophies:

| | Declarative (Terraform, Bicep, CDK) | Imperative (CloudFormation, Ansible) |
|---|---|---|
| You describe | *What* the end state should be | *How* (step-by-step commands) |
| Engine decides | Order, dependencies, diffs | You decide the order |
| Terraform | ✅ | |

**Key Terraform properties**

- **Declarative** — write the goal, Terraform computes the *plan* to reach it.
- **Idempotent** — applying the same config twice = no changes.
- **Dependency graph** — resources are nodes; references are edges; Terraform derives create/destroy order automatically.
- **Provider plugins** — one engine, hundreds of backends (AWS, Azure, GCP, Kubernetes, HTTP APIs, DNS…).
- **Plan/Apply separation** — a human (or CI) can review the diff before anything changes.

> **Licensing note:** Terraform 1.x is under the **BUSL 1.1** license (source-available, not OSI open source). If you want pure open source, **OpenTofu** (Linux Foundation) is a drop-in fork with nearly identical CLI/config for most cases. Everything in these notes applies to both.

## 1.2 Installation

```bash
# Ubuntu/Debian (via HashiCorp's apt repo or a direct download)
curl -fsSL https://releases.hashicorp.com/terraform/1.16.0/terraform_1.16.0_linux_amd64.zip -o tf.zip
unzip tf.zip && sudo mv terraform /usr/local/bin/
terraform -version   # prints: terraform 1.16.0

# macOS
brew install terraform

# Windows
winget install HashiCorp.Terraform    # or choco install terraform
```

Verify:

```bash
terraform -version
terraform version -json   # machine-readable version (useful in scripts)
```

### CLI configuration file: `~/.terraformrc` (or `TF_CLI_CONFIG_FILE`)

Used for **provider plugin cache**, **provider filesystem mirrors** (air-gapped environments), and **provider network** settings:

```hcl
provider_installation {                        # top block: controls HOW providers are downloaded
  filesystem_mirror {                          # a local directory that stores provider binaries
    path    = "/opt/terraform/providers"       # absolute path to the mirror directory
    include = ["registry.terraform.io/*/*"]    # which provider namespaces/types the mirror may serve
  }
  direct {                                     # the normal "download from registry" path, as a fallback
    exclude = ["registry.terraform.io/*/*"]    # but skip these (the mirror already has them) → air-gapped safe
  }
}
```

## 1.3 The Core Workflow

```
terraform init  →  terraform plan  →  terraform apply  →  terraform destroy
  (bootstrap)       (diff/preview)     (execute)          (teardown, reverse order)
```

### `terraform init`

- Validates the config directory structure.
- Downloads provider plugins declared in `required_providers`.
- Configures the **backend** (where state will live) — this is why backend changes require a re-init.
- Idempotent & re-runnable any time (add `-upgrade` to fetch newer provider versions within the constraint).

Flags worth knowing: `-backend=false` (no backend init — for `validate` on a new module), `-plugin-dir`, `-upgrade`, `-reconfigure`.

### `terraform plan`

Produces a **resource action graph**: `+ create`, `- destroy`, `-/+ replace`, `~ update in-place`, `= no-op`, `↷ replace` (ordering matters: destroy-then-create vs create-before-destroy).

```bash
terraform plan -out=prod.plan                    # compute the plan and SAVE it to a file (recommended in CI)
terraform apply prod.plan                        # apply *exactly* that saved plan (nothing else)
terraform plan -var-file=prod.tfvars             # load variable values from a named file
terraform plan -target=aws_instance.web          # DANGER: partial plan; see gotchas
terraform plan -refresh-only                     # only refresh state vs reality, propose NO changes
terraform plan -lock-timeout=2m                  # wait up to 2m for a stale state lock instead of failing
```

Plan file flags: a saved plan is **bound** to the exact config + provider versions that produced it; it cannot be applied after unrelated config edits.

### `terraform apply`

```bash
terraform apply
terraform apply -auto-approve        # skip the confirmation prompt (CI-only! never in interactive use)
terraform apply -replace=aws_instance.web   # force replacement of a specific resource
terraform apply -target=... -replace=...   # combinations are legal but rarely wise
terraform apply -var environment=prod -var 'tag_map={"team":"platform"}'   # inline variable values
terraform apply -parallelism=10        # default 10; lower if you hit API throttling
```

### `terraform destroy`

Destroys in **reverse dependency order** (children first, e.g. instances before subnets, subnets before VPC).

```bash
terraform destroy            # asks for interactive confirmation first
terraform destroy -auto-approve
```

> **Rule:** `force_destroy` / `skip_final_snapshot` / `skip_resource_group_deletion` flags exist on many cloud resources precisely so that `destroy` works in dev. **Never** set these in production.

## 1.4 The Full Command Catalog (grouped)

**Workflow**
`init`, `validate`, `fmt` (`-check -recursive`), `plan`, `apply`, `destroy`, `show` (render plan/state), `output`, `state`, `import`, `untaint` (legacy), `console`, `graph`, `test`, `force-unlock`, `version`.

**State surgery** (use sparingly — state is truth)

```bash
terraform state list                      # list all resource addresses in state
terraform state show aws_instance.web     # print one resource's recorded state
terraform state mv aws_instance.old aws_instance.new   # rename/move an address in state
terraform state rm  aws_instance.web[0]   # remove from state only (the live resource is NOT deleted!)
terraform state pull / state push         # read/write raw state JSON (advanced)
```

**Debugging**

```bash
terraform validate                 # syntax/schema check (requires init first)
terraform console                  # interactive REPL: try functions against real variables
terraform graph                    # DOT dependency graph → render with Graphviz
TF_LOG=DEBUG terraform plan        # full API-level logs (huge output; tail them)
terraform plan -no-color -detailed-exitcode   # exit code 2 = changes present (CI gate!)
```

`-detailed-exitcode` is the CI workhorse: exit `0` = no changes, `1` = error, `2` = changes planned.

## 1.5 Your First End-to-End Lab

```bash
mkdir tf-hello && cd tf-hello
cat > main.tf <<'EOF'
provider "null" {}                            # use the built-in "null" provider — no cloud credentials needed

resource "null_resource" "hello" {            # declare one (fake) resource, type null_resource, local name "hello"
  triggers = {                                # a map that, when changed, forces the resource to be replaced
    name = "world"                            # one trigger entry; the value is arbitrary
  }
}
EOF
cat > outputs.tf <<'EOF'
output "id" {                                 # expose an output named "id" (shown by `terraform output`)
  value = null_resource.hello.id              # its value = the id attribute of the null_resource above
}
EOF

terraform init
terraform plan
terraform apply -auto-approve
terraform output
terraform apply -auto-approve   # → "No changes" (this is idempotency!)
terraform destroy -auto-approve
```

Notice: the second apply is a **no-op**. That single behavior is the entire promise of Terraform.

## 1.6 Variables on the CLI: Precedence Order

```bash
terraform apply -var env=dev -var-file=dev.tfvars
```

Precedence, **lowest → highest** (later overrides earlier):

1. `terraform.tfvars`
2. `*.auto.tfvars` (lexicographic order)
3. `-var` flags (left to right)
4. `-var-file` (left to right)
5. `TF_VAR_<name>` environment variables (highest)

## 1.7 Common Errors You WILL See (and their meaning)

| Error | Cause / Fix |
|---|---|
| `Error: Missing required provider` | Forgot `required_providers` or `init` after adding one |
| `Backend initialization required` | Backend config changed → `terraform init -reconfigure` (⚠️ reconfigure can lose state; back up first) |
| `Error acquiring the state lock` | Someone else is applying. Wait or `force-unlock` **only** if you're 100% sure the other run is dead |
| `NoCredentialProviders` / `unable to validate AWS credentials` | Provider auth not configured (see AWS 01) |
| `Provider produced inconsistent result after apply` | Usually a race in a cloud API or an out-of-band change; re-plan, check console |
| `Error: Resource not found` on refresh | Someone deleted the resource in the console (drift) — Terraform will recreate it on next apply |
| `Inconsistent dependency lock file` | `.terraform.lock.hcl` changed across machines — share the lock file, don't edit by hand |

## 1.8 Exam/Interview Quick Facts

- Terraform is written in **Go**; config language is **HCL** (HashiCorp Configuration Language), JSON is also accepted but not recommended (you lose comments/locals ergonomics).
- Terraform does **not** run an agent; it talks to cloud APIs via **providers** using your credentials.
- A `plan` is **not** a script — it is a *description of the intended changes*, and apply re-validates it.
- Terraform never changes anything without your `apply`. It has **no** console-clicking automation.
