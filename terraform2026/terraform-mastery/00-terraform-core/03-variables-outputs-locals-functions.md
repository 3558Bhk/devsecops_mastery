# 3. Variables, Outputs, Locals & Functions

> **⏱️ Time to complete: ~45 min** (read + test functions in `terraform console`)

## 3.1 Input Variables

```hcl
variable "environment" {          # declare an input variable named "environment"
  description = "Deployment environment"   # shown in docs/CLI prompts
  type        = string            # type constraint: must be a string
  default     = "dev"             # used when no value is supplied

  validation {                    # optional: validate the value at plan time
    condition     = contains(["dev", "staging", "prod"], var.environment)  # allowed values list
    error_message = "Environment must be one of: dev, staging, prod."      # message on failure
  }
}

variable "instance_count" {       # a numeric input
  type    = number                # must be a number
  default = 2                     # default value
}

variable "db_password" {          # a secret input
  type      = string              # string type
  sensitive = true                # masks the value in plan/output/CLI display
}

variable "tag_map" {              # a map of tags
  type    = map(string)           # keys and values are strings
  default = {}                    # empty object by default
}

variable "instance_config" {      # a structured object input
  type = object({                 # an object type with fixed attributes
    size   = string               # attribute "size" is a string
    disk   = number               # attribute "disk" is a number
    ports  = list(number)         # attribute "ports" is a list of numbers
  })
}

variable "optional_zones" {       # a nullable list input
  type        = list(string)      # list of strings
  default     = null              # explicit null default
  nullable    = false             # (1.4+) reject null values even if allowed
}
```

Key points:
- `sensitive = true` hides the value in plans, outputs, and console output. It does **not** encrypt state.
- Type constraints are enforced at plan time; coercion applies (see HCL types).
- Use `validation` blocks to fail *early* with a helpful message (better than letting AWS reject it 40 seconds into apply).

### Where variable values come from (lowest → highest precedence)

1. `terraform.tfvars`
2. `*.auto.tfvars` (alphabetical order)
3. `-var` / `-var-file` flags
4. `TF_VAR_<NAME>` env vars (highest)

Unset variables with no default → `plan`/`apply` prompts interactively (in CI, make all variables have defaults or pass them explicitly).

## 3.2 Outputs

```hcl
output "alb_dns_name" {           # expose an output named "alb_dns_name"
  description = "Public DNS name of the ALB"   # shown by `terraform output -json`
  value       = aws_lb.web.dns_name            # value = the ALB's dns_name attribute
}

output "db_password" {            # a sensitive output
  value     = var.db_password     # value from the variable
  sensitive = true                # must use `terraform output -raw db_password` to read
}

output "needs_fresh_apply" {      # an output that depends on another resource
  value     = aws_instance.web[0].id != old_value   # (illustrative comparison)
  depends_on = [aws_instance.web]   # emit AFTER this resource exists
}
```

Rules:
- `depends_on` on outputs matters when the value is computed from a **data source** or local logic that needs ordering.
- **Never output secrets** (passwords, private keys) — even with `sensitive`, they persist in state.
- Use outputs as the **contract between modules** (the child's outputs are the parent's data).

## 3.3 Locals

```hcl
locals {                          # a block of named expressions (not real resources)
  name_prefix = "prod"            # a named constant
  common_tags = merge(var.tag_map, {        # merge two maps
    Environment = var.environment   #  key "Environment" from the variable
    ManagedBy   = "terraform"       #  key "ManagedBy" literal
  })
  all_instance_ids = aws_instance.web[*].id   # attribute splat: list of all instance ids
  private_subnets  = [for s in aws_subnet.private : s.id]  # for expression: list of subnet ids
}
```

- `locals` is just **named expressions** — no state, no reordering, evaluated at plan time.
- Rule of thumb: *if you'd write it twice, make it a local*; *if it varies per environment, make it a variable*.

## 3.4 Function Catalog (the ones you'll actually use)

### Strings
```hcl
upper("x"), lower("X"), replace("a-b", "-", "_"), trim(" x "),   # case, replace, trim
trimprefix("prod-web", "prod-"), title("web server"),            # strip prefix, title case
substr("hello", 0, 2)                    # substring from index 0, length 2 → "he"
split("-", "a-b-c")                       # split into a list → ["a","b","c"]
join(",", ["a","b"])                      # join a list with a separator → "a,b"
format("v%s-%s", "1", "2")                # printf-style → "v1-2"
formatlist("%s-web", ["a","b"])           # format each list element → ["a-web","b-web"]
indent(2, "a\nb")                          # indent each line by 2 spaces
chomp("x\n\n")                             # strip trailing newlines → "x"
length("abcd")                             # number of characters → 4
regex("^v(\\d+)", "v12")                    # capture group match → ["12"]
regexall("[0-9]+", "a1b22")                 # all matches → ["1","22"]
```

### Collections
```hcl
length(var.list), elements(var.list, 2)     # count; first 2 items
slice(var.list, 1, 3), sort(var.list), distinct(var.list)  # slice, sort, dedupe
flatten([[1,2],[3]])                        # flatten nested lists → [1,2,3]
merge({a=1}, {b=2})                          # merge maps → {a=1,b=2}
merge(var.tag_map, local.extra_tags)         # merge a variable and a local
keys(var.map), values(var.map)               # map keys / map values
contains(var.list, "x")                       # is "x" in the list?
lookup(var.map, "missing", "fallback")       # safe access with a default
setproduct(["a","b"], [1,2])                 # cartesian product → ["a1","a2","b1","b2"]
range(3)                                     # [0,1,2]
```

### Encoding & templates
```hcl
jsonencode({ a = [1, 2] })                   # object → JSON string
jsondecode("{\"a\":1}")                       # JSON string → object
base64encode(file("id_rsa.pub"))             # read a file, base64-encode (for SSH keys)
urlencode("a b")                              # URL-encode a string
templatefile("user_data.sh.tmpl", { env = var.environment, ports = var.ports })  # render a template
csvdecode("a,b\n1,2")                         # decode CSV
```

`templatefile` is the *proper* way to generate scripts:

```hcl
# user_data.sh.tmpl   (a separate template file)
#!/bin/bash
echo "configuring ${env}"                     # ${env} is interpolated from the templatefile() args
%{ for p in ports ~}                          # for each port in the list
echo "port ${p} open"                         # emit one line per port
%{ endfor ~}                                  # end the for loop
```

### Files
```hcl
file("path/to/file")               # read a file's content as a string
filebase64("path")                 # read + base64-encode
filebase64sha256("zip")            # base64 sha256 of a file (lambda source hash)
fileset("templates", "*.sh")       # list matching files in a directory
directory("path")                  # object of directory entries (1.10+)
```

### Math & dates
```hcl
abs(-2), ceil(2.1), floor(2.9), log(100, 10), max(1,2,3), min(1,2)  # math basics
pow(2, 10), parseint("42", 10)      # power; parse a base-10 integer string
timeadd("2026-01-01T00:00:00Z", "72h")   # add 72 hours to a timestamp
timecmp("2026-01-01T00:00:00Z", "2025-01-01T00:00:00Z")   # compare two times (>0 if first is later)
formatdate("MMM YYYY", "2026-01-01T00:00:00Z")            # format a date → "Jan 2026"
```

### Encryption & IDs
```hcl
md5("x"), sha1("x"), sha256("x"), sha512("x")   # hash functions
uuid()                                  # a NEW random uuid EVERY plan (avoid in resource args!)
uuidv5("https://example.com/salt", "my-resource")   # DETERMINISTIC uuid — stable across plans
```

> Gotcha: `uuid()` in a resource arg = a **new value every plan** = perpetual diff. Compute it once in a `local` or use `uuidv5`.

### IP / CIDR (networking gold)
```hcl
cidrsubnet("10.0.0.0/16", 8, 1)    # borrow 8 bits, index 1 → "10.1.0.0/24"
cidrhost("10.0.0.0/24", 10)        # the 10th host → "10.0.0.10"
cidrnetmask("10.0.0.0/24")         # netmask → "255.255.255.0"
cidrprefix("10.0.0.0/24")          # prefix → "10.0.0/24"
ip("10.0.0.0/24")                   # the IP part → "10.0.0"
in-cidr("10.0.0.5", "10.0.0.0/24")  # is the IP in the CIDR? → true
```

### Paths & misc
```hcl
path.module        # absolute path of the current module
path.root          # absolute path of the root module
path.cwd           # working dir (non-hermetic!)
can(1 / 0)         # false (never errors — safe conditional logic)
try(var.missing_key, "fallback")   # first non-error value
nonsensitive(var.sens)             # strip the sensitive flag
alltrue([true, true]), anytrue([false, true])   # boolean reductions
tobool("true"), tonumber("3"), tolist("x"), toset([1,1]), tomap({...}), tostring(5)  # type conversions
```

## 3.5 Design Patterns

**Environment-based sizing**

```hcl
locals {
  sizes = {                       # a map of per-env sizing
    dev     = { cpu = "t3.small",   db = "db.t3.micro" }   # dev sizes
    staging = { cpu = "t3.medium",  db = "db.t3.medium" }  # staging sizes
    prod    = { cpu = "m6i.xlarge", db = "db.m6i.large" }  # prod sizes
  }
  env = lookup(local.sizes, var.environment, local.sizes.dev)  # pick by env, default dev
}
```

**Naming**

```hcl
locals {
  name_prefix = "${local.project}-${var.environment}"   # e.g. "acme-prod"
}
# use everywhere: name = "${local.name_prefix}-web"
```

**Conditional resource lists**

```hcl
locals {
  should_create_monitoring = var.environment == "prod"   # true only in prod
}
```

## 3.6 Quick-Reference: What's a Variable, What's a Local, What's a Data Source?

| Question | Answer |
|---|---|
| Value comes from the **user/environment**? | `variable` |
| Value is **derived** from other config? | `local` or inline expression |
| Value lives **in the cloud already** (existing resource, AMI, current account)? | `data` block |
| Value is **produced by** this Terraform run? | Reference the `resource` attribute |
