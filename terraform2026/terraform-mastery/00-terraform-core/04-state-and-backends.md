# 4. State & Backends (the heart of Terraform)

> **⏱️ Time to complete: ~45 min** (read + set up a local/S3 backend & inspect state)

## 4.1 What State Actually Is

Terraform keeps a **map of resource address → recorded attributes** (the "known" state). It's how Terraform:

1. Knows *what it created* (maps address ↔ cloud resource ID).
2. Computes diffs (state + live refresh vs. config).
3. Tracks **order** (dependency graph).

```
terraform state list
# aws_instance.web[0]
# aws_instance.web[1]
# aws_vpc.main
```

**What state is NOT:**
- Not the infrastructure (it's a *record* of it).
- Not encrypted by default (it contains secrets you passed — passwords, keys, tokens!).
- Not something to put in Git (unless you have a very small, disposable demo).

The state file (`terraform.tfstate` by default locally) is JSON: `version`, `terraform_version`, `serial`, `lineage` (a UUID tying all state versions together — **never edit lineage**), and the `resources[]` array.

## 4.2 Local vs Remote

| | Local (default) | Remote |
|---|---|---|
| File | `./terraform.tfstate` in CWD | S3, GCS, Azure Blob, Terraform Cloud, HTTP |
| Team sharing | ❌ (scp it — dangerous) | ✅ |
| Locking | local file lock (single machine) | provider-side (DynamoDB / native / SaaS) |
| Encryption at rest | ❌ | ✅ (server-side) |
| Versioning/audit | manual | ✅ (history) |

**Rule: production always uses a remote backend.**

## 4.3 AWS S3 Backend (canonical pattern)

### Backend configuration (in `backend.tf` — keep separate from `versions.tf`)

```hcl
terraform {                          # the terraform config block
  backend "s3" {                     # use the S3 backend (store state in an S3 bucket)
    bucket         = "mycompany-tfstate-global"   # the S3 bucket holding state
    key            = "network/prod.tfstate"       # object key = layer/environment (one file per state)
    region         = "ap-south-1"                 # the bucket's region
    profile        = "admin"                      # (optional) use this shared-credentials profile
    encrypt        = true                         # encrypt the state object at rest
    dynamodb_table = "tfstate-locks"              # (OPTIONAL since TF 1.6) the lock table
  }
}
```

### Create the backend *without Terraform* (chicken-and-egg)

State bucket + lock table must exist first (console or a small bootstrap stack):

```hcl
resource "aws_s3_bucket" "tfstate" {         # the state bucket itself
  bucket        = "mycompany-tfstate-global"  # globally-unique bucket name
  force_destroy = false                      # NEVER force-destroy a state bucket
}

resource "aws_s3_bucket_versioning" "tfstate" {   # enable versioning (state history)
  bucket = aws_s3_bucket.tfstate.id               # target the bucket
  versioning_configuration {                      # the versioning settings block
    status = "Enabled"                            # turn versioning ON
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {  # SSE on the bucket
  bucket = aws_s3_bucket.tfstate.id               # target bucket
  rule {                                          # one encryption rule
    apply_server_side_encryption_by_default {     # default encryption on upload
      sse_algorithm = "aws:kms"                   # encrypt with KMS (a CMK you control)
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {  # block ALL public access
  bucket                  = aws_s3_bucket.tfstate.id   # target bucket
  block_public_acls       = true   # no public ACLs
  block_public_policy     = true   # no public bucket policy
  ignore_public_acls      = true   # ignore public ACLs on objects
  restrict_public_buckets = true   # fail if the bucket is public
}

resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {  # clean up old versions
  bucket = aws_s3_bucket.tfstate.id               # target bucket
  rule {                                          # one lifecycle rule
    id     = "old-snapshots"                      # rule id (must be unique in the bucket)
    status = "Enabled"                            # active
    noncurrent_version_expiration {               # expire old (non-current) versions
      noncurrent_days = 30                        # after 30 days
    }
  }
}

# Classic locking table (only needed for Terraform < 1.6 or when sharing with old clients)
resource "aws_dynamodb_table" "tfstate_locks" {   # the DynamoDB lock table
  name         = "tfstate-locks"                   # table name
  billing_mode = "PAY_PER_REQUEST"                 # on-demand billing (no capacity math)
  hash_key     = "LockID"                          # the primary key name
  attribute {                                     # define the primary key attribute
    name = "LockID"                                # attribute name
    type = "S"                                     # type = String
  }
}
```

> **Since Terraform 1.6 the S3 backend has NATIVE client-side locking** — no DynamoDB table needed. The DynamoDB pattern is still everywhere in the wild; both work. (The table is still useful as a *second lock layer* if multiple tools touch the same key.)

### Key conventions
- **One state file per environment per service/layer** (`network/prod`, `compute/prod`) — small states, parallel teams, fast plans.
- Never store secrets that you can't rotate. State *history* (versioned S3) accumulates them over years.
- `terraform init` downloads the remote state to a local cache (`terraform.tfstate` in `.terraform/`) — the **real** state lives in S3.

## 4.4 Azure Blob Backend

```hcl
terraform {                          # the terraform config block
  backend "azurerm" {                # use the Azure blob backend
    resource_group_name  = "rg-tfstate-global"     # the RG holding the storage account
    storage_account_name = "tfstateglobal"         # the storage account
    container_name       = "tfstate"               # the blob container
    key                  = "network/prod.tfstate"  # the blob key (one per state)
    account_sas_token    = "sv=2026-..."           # a scoped, expiring SAS token
  }
}
```

Same pattern: dedicated storage account, container, versioning enabled, SAS token (scoped, expiring) or AAD auth.

## 4.5 Terraform Cloud / HCP

- Hosted SaaS: remote execution, **VCS integration** (PR → plan), workspaces, private module registry, policy-as-code (Sentinel), cost estimation, teams/SSO.
- Backend address:
```hcl
terraform {                          # the terraform config block
  cloud {                            # connect to Terraform Cloud (HCP)
    organization = "myorg"           # your HCP organization
    workspaces {                     # which workspace to bind to
      name = "prod-network"           # by name (or tags = { env: "prod" })
    }
  }
}
```
- `terraform login` once; after that `plan`/`apply` runs remotely and state lives in HCP with built-in locking, versioning, and audit.
- Free tier (3 users, 10 workspaces) is enough for a small team.

## 4.6 State Surgery Commands (know all of these)

```bash
terraform state list                          # list all resource addresses
terraform state show aws_instance.web[0]      # inspect one resource
terraform state mv <old-addr> <new-addr>      # rename an address (e.g. after a refactor); plan confirms
terraform state rm  <addr>                    # remove from state ONLY — the cloud resource is untouched
terraform state push / state pull             # raw JSON in/out
terraform force-unlock LOCK_ID                # break a stuck lock (verify it's dead first!)
terraform import -state=... <addr> <cloud_id> # import an existing resource (see ch. 07)
```

**When state surgery is needed**
- Renamed a module or resource in code → `state mv` (otherwise TF thinks old = destroy, new = create).
- Deleted the state by accident → `terraform init -migrate-state` (with backup!) or restore from S3 versioning.
- Imported a resource → `state rm` it and re-add with an `import` block.

## 4.7 Locking

- Every apply takes an **exclusive lock** on the state; the lock record stores who/when.
- If the process dies mid-apply, the lock can be left behind → `Error acquiring the state lock`.
- **`force-unlock` is dangerous**: if another real apply is running, you corrupt state. Verify with the lock's info (timestamp, user, IP) before breaking it.
- `-lock` / `-lock-timeout=3m` control behavior.

## 4.8 Workspaces

```bash
terraform workspace new dev
terraform workspace new prod
terraform workspace select prod
terraform workspace list
terraform workspace delete dev    # only if no resources in it
```

- Workspaces = **one config, many state files** in the same backend (`<key>.tfstate`, `default` is bare `<key>`).
- S3 backend: workspaces create `<key>.tfstate` siblings automatically.
- **Workspace vs. separate directories?** Workspaces are convenient for *simple* env splits, but they forbid `var`-driven structural differences and hide drift in CI. Mature teams usually use **separate root modules (one per env/service) → separate states** and avoid workspaces. Terraform Cloud "workspaces" (a SaaS concept, one per service-env) are the same idea, just hosted.

## 4.9 Drift & Refresh

- **Drift** = out-of-band changes (console edits, auto-scaling, manual patching).
- Every `plan`/`apply` starts with an implicit **refresh**: Terraform re-reads live state of all resources and updates the state file.
- If refresh finds a resource gone → it's removed from state and the plan recreates it (self-healing — good, unless the deletion was intentional; then update the code).
- `plan -refresh-only` = detect drift without proposing changes. Run this on a **schedule** (e.g. weekly in CI) to surface drift early.

## 4.10 Migration Plays (interview favorites)

1. **Change backend** (local → S3):
   - Edit `backend` block → `terraform init -migrate-state` (yes to copy) → verify `state list` → done. (Newer Terraform can also re-init and copy automatically; always back up first: `cp terraform.tfstate backup.tfstate`.)
2. **Split a monolith state** into two:
   - New directory with its own backend → `terraform state mv` each resource (one at a time, or in bulk with a loop over `state list`) → verify both plans are clean.
3. **Merge two states**: `terraform state push`/`pull` + `state mv` into the target; or the `terraform import` route per resource.
4. **Provider upgrade that renames a resource type** (rare): `state mv` the affected addresses.

## 4.11 Gotchas Checklist

- [ ] State file contains the RDS password? It's in every versioned backup. Rotate secrets aggressively; prefer `sensitive` + secrets-manager lookup.
- [ ] Two developers running `apply` on the same state? → lock errors. That's the system working.
- [ ] `terraform destroy` on a state with **imported** resources? It will delete things you didn't create. Know what you imported.
- [ ] Local backend + Git? `.gitignore` must contain `*.tfstate*`, `.terraform/`, `*.tfvars` (if they contain secrets), `crash.log`.
- [ ] `.terraform.lock.hcl` committed? If not, CI may download different provider builds than your laptop.
- [ ] Backend `key` naming includes the environment? (`prod-network`, not just `network`)
