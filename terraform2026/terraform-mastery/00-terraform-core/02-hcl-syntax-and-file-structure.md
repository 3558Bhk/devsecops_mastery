# 2. HCL Syntax & File Structure

> **⏱️ Time to complete: ~40 min** (read + try the expressions in `terraform console`)

## 2.1 Anatomy of HCL

Terraform config is a set of **blocks** containing **arguments** and **expressions**.

```hcl
resource "aws_instance" "web" {          # BLOCK TYPE ("resource") + LABELS (type "aws_instance", name "web")
  ami           = "ami-12345"            # argument (ami) = literal expression (an AMI id string)
  instance_type = var.flavor             # expression: reference the input variable `flavor`
  tags = {                               # object (map) literal: key/value pairs
    Name = "${var.environment}-web"      # string interpolation: ${expr} inside a string
  }
}
```

Block forms:

```hcl
label "single" { ... }      # one label (e.g. output "my_out" { ... })
label1 "a" label2 "b" { }   # two labels (e.g. resource TYPE "aws_instance" NAME "web")
bare { ... }                # zero labels (e.g. terraform { ... }, locals { ... })
```

- **Comments:** `#` or `//` for single-line. (No block comments in HCL2 — use multiple `#` lines.)
- **Expressions** can be nested *anywhere* a value is expected, including inside object values and function calls.
- **Interpolation:** `"${expr}"` is optional for simple cases — a string that is a single expression can drop the `${}`: `name = var.name`.

## 2.2 The Type System (cty)

| Type | Example | Notes |
|---|---|---|
| `bool` | `true` | |
| `number` | `42`, `3.14` | |
| `string` | `"x"`, `<<-EOF ... EOF` heredocs | heredoc `<<-` trims leading whitespace |
| `list(T)` | `[1, 2, 3]` | **ordered**, may contain dupes, `[]` for empty |
| `set(T)` | `toset(["a","b"])` | unordered, unique — `for_each` keys are *unpredictable* |
| `map(T)` | `{ a = 1, b = 2 }` | keys = strings |
| `tuple` | `[1, "x", true]` | mixed types, fixed |
| `object{...}` | `{ name = string, ports = list(number) }` | typed struct |
| `dynamic` (cty) | unknowns from data sources | |

Type coercion rules to know:
- A number `1` given where a string is expected → `"1"` (coerced), but `"1"` given where a number is expected also coerces.
- A single-element list vs string: `["a"]` is NOT a string.
- Empty literal `[]` defaults to `list(string)`; empty object `{}` is `object {}`.
- `set` is the enemy of stable `for_each` keys — prefer `map` or `list` for `for_each`.

## 2.3 Expressions

```hcl
# Arithmetic
count = 2 * 3 + 4                # numbers: multiply then add → 10
price = 9.5                       # numbers are float-precision (be careful with money!)

# Comparison / boolean
a >= b, x == "prod", !(a == b), a && b, a || b   # relational, logical NOT, AND, OR

# Ternary (if/else in one expression)
tier = var.env == "prod" ? "Standard" : "Basic"  # if condition true → "Standard", else "Basic"

# Indexing & slicing
first = var.instances[0]         # first element of a list
ports = range(80, 444)            # function: list [80, 81, ..., 443]
slice = var.list[1:3]             # elements at index 1 and 2

# Attribute access
data.aws_caller_identity.current.account   # read attribute `account` from a data source

# Splat expressions (the power feature)
ids  = aws_instance.web[*].id            # attribute splat → list of the id of EVERY instance
sgs  = aws_instance.web[*].security_groups[0]   # first security group of every instance
flat = tolist(flatten(aws_instance.web[*].security_groups))  # flatten list-of-lists into one list

# For expressions (map/filter/transform collections)
names    = [for n in var.instances : upper(n)]                    # map: uppercase every name
filtered = [for i, n in var.instances : n if n != "legacy"]       # filter: keep only non-"legacy"
as_map   = { for i, n in var.instances : n => i }                 # map: name => index
nested   = [for s in var.subnets : [for z in s.zones : "${s.name}-${z}"]]  # nested: pair each zone with subnet name
```

### Heredocs (for scripts, policies, user-data)

```hcl
user_data = <<-EOT                  # multi-line string; <<- trims common leading indentation
  #!/bin/bash                       # line 1 of the embedded bash script
  echo "hello ${var.environment}"   # interpolation works inside heredocs too
  apt-get update && apt-get install -y nginx   # install nginx on boot
EOT
```

`<<-` strips common leading indentation. Use `templatefile()` (see functions) when you want a *separate* `.tmpl` file with conditional logic — don't build huge scripts inside HCL.

## 2.4 Operators & Gotchas

- `/` and `%` on numbers are float-based; use `parseint("8080", 10)` if you read a port from a string.
- String `+` concatenates; list `+` concatenates lists.
- There is **no** `and`/`or` keyword — it's `&&`/`||`.
- `==` on objects/lists compares deeply; a `set` comparison is order-independent.
- **Unknown values** (data sources, `count` in some positions) are fine in config but `terraform plan` will show them as `(known after apply)`.

## 2.5 Conventional File Layout

```
my-infra/
├── versions.tf        # terraform block: required_version, required_providers
├── backend.tf         # backend config (kept separate so `init` can be scripted)
├── providers.tf       # provider "aws" { ... } blocks
├── variables.tf       # variable "..." {} blocks (with description/type/default)
├── locals.tf          # locals { ... }
├── main.tf            # the resources (or split: network.tf, compute.tf, db.tf)
├── outputs.tf         # output "..." {} blocks
├── data.tf            # data "..." {} blocks
├── terraform.tfvars   # committed local values (dev only — never secrets!)
├── prod.tfvars        # per-env values
└── .terraform.lock.hcl  # provider version LOCK FILE → commit it
```

Rules:
- Only `*.tf` and `*.tfvars` files are read (plus `*.tf.json`).
- Split resources into files by *concern* (`network.tf`, `iam.tf`), not by resource type.
- **`.terraform.lock.hcl` is a normal source file** — commit it. It guarantees every teammate/CI uses the exact provider binary hashes.
- One **root module** per environment is the norm (`environments/dev`, `environments/prod`).

## 2.6 The `terraform {}` Block

```hcl
terraform {                                  # the configuration block for Terraform itself
  required_version = ">= 1.9, < 1.17"       # constrain the Terraform engine version (a range)

  required_providers {                       # declare which provider plugins this config needs
    aws = {                                  # provider label "aws" (used as the default alias)
      source  = "hashicorp/aws"              # registry address: namespace/type
      version = "~> 5.0"                     # pessimistic constraint: any 5.x, never 6.x
    }
    azurerm = {                              # second provider (Azure)
      source  = "hashicorp/azurerm"          # registry address for the Azure provider
      version = "~> 5.0"                     # allow 5.x only
    }
    # aliased provider (a second configuration of the same plugin):
    aws_east = {                             # label "aws_east" → referenced as provider "aws" { alias = "east" }
      source  = "hashicorp/aws"              # same plugin...
      version = "~> 5.0"                     # ...same constraint
    }
  }
}
```

Version constraint operators:

| Syntax | Meaning |
|---|---|
| `= 5.2.0` | exact |
| `~> 5.2` | 5.2.x (patch-only, same minor) |
| `~> 5.0` | 5.x (any minor within major 5) |
| `>= 5.0, < 6.0` | explicit range |

> **Why `~>` matters in practice:** providers *add* resources and rarely break things, but major bumps (aws 4→5, azurerm 4→5) DO break things. Pinning the major with `~>` = new features, no surprises.

## 2.7 `fmt`, `validate`, and JSON

- `terraform fmt -recursive -check` is a CI gate; run it in pre-commit.
- `terraform validate` needs `init` first (it checks against provider schemas).
- Terraform also accepts **JSON** config (`.tf.json`) — useful if your tooling emits config; you lose comments and some ergonomics but gain machine-generatability (used by CDK and some codegen tools).

## 2.8 Common Syntax Mistakes

| Mistake | Fix |
|---|---|
| Missing `=` in an argument | HCL requires `label` or `arg = value` form |
| Trailing comma in a list `[1, 2, 3,]` | Illegal in HCL |
| `if` as a statement | No bare `if` statements — use ternary or `for ... if ...` |
| Quoting a whole object `"{...}"` | Use a real object literal or `jsonencode()` |
| Forgetting `"` around keys in a map with special chars | `tags = {"my-key" = "v"}` |
| Heredoc not at column 0 for `<<-` | The closing marker must align per `<<-` rules (fmt will tell you) |
