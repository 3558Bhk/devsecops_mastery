# dummy.md — Every Dummy Value to Replace Before Running (exact folder → file → line)

> Read this BEFORE you run anything.
> Every project here ships with **dummy (placeholder) values** baked in so it validates out of the box.
> Some are harmless (a name like `hello`), some are **mandatory to change** (passwords, your IP, SAS tokens),
> and some are **globally-unique names** (S3 buckets, Azure storage accounts) that can collide if someone else took them.
>
> Legend: 🔴 = MUST change · 🟡 = should change (uniqueness / your values) · 🟢 = fine as-is
>
> "What to push" = the exact value you type into that slot.

---

## Part 0 — The core structure (how this whole folder is built)

```
terraform-hands-on/
├── README.md               ← the ladder (what to do in which order) + one-time setup
├── dummy.md                ← THIS FILE
├── dummy_azuredevops.md    ← run a project in Azure DevOps pipelines (exact steps + dummies)
├── dummy_jenkins.md        ← run a project in Jenkins pipelines (exact steps + dummies)
├── aws/
│   ├── README.md           ← AWS ladder + notes
│   └── project-01 … project-11   ← ONE project = ONE folder
└── azure/
    ├── README.md           ← Azure ladder + notes
    └── project-01 … project-11   ← ONE project = ONE folder
```

**Inside every project folder** (same shape, 3–7 files):

| File | What it holds |
|---|---|
| `README.md` | what it builds, how to run it, how to verify, what to break, cleanup |
| `variables.tf` | **all inputs** (with defaults where safe) — this is where you push your values |
| `main.tf` | the infrastructure (every line commented) |
| `outputs.tf` | what Terraform prints at the end (URLs, names, ARNs) |
| `terraform.tfvars.example` | a sample values file → **copy to `terraform.tfvars` and edit it** |
| `backend.tf` (p06 only) | where state is stored (S3 / Azure Storage) |
| `lambda/*.py` (aws p10) | the worker code Terraform zips and deploys |

**The flow for any project:**

1. `cp terraform.tfvars.example terraform.tfvars` (only projects that have one)
2. edit `terraform.tfvars` (or `variables.tf` defaults) with your values — use the tables below
3. `terraform init` → `terraform plan` → `terraform apply`
4. verify with the CLI commands in that project's README
5. `terraform destroy` when done (except p06 bootstrap state — see below)

**Two structural rules to remember:**

- **One state file per project.** Each project folder has its own `terraform.tfstate` (or its own S3/Azure backend key). Never run two projects from one folder.
- **Project 06 is special.** It has a `00-bootstrap/` subfolder you run FIRST (creates the state bucket + lock table), and the project's own `backend.tf` points at it. If you rename the bootstrap resources, you MUST rename them in `backend.tf` too (they must match exactly).

---

## Part 1 — AWS projects: dummy values

### AWS `project-01-first-s3-bucket`

| # | Folder | File | Line | Current dummy | 🔴🟡 | What to push |
|---|--------|------|------|---------------|-----|--------------|
| 1 | `aws/project-01-first-s3-bucket` | `main.tf` | 17 | `bucket = "my-first-tf-bucket-2026"` | 🟡 | Your own globally-unique name, e.g. `my-first-tf-bucket-2026-ra` (S3 names are unique across ALL of AWS; if apply says "BucketAlreadyExists", change the suffix) |

> No `tfvars` — the bucket name is hardcoded on purpose (you're learning where to change it).

### AWS `project-02-variables-outputs`

| # | Folder | File | Line | Current dummy | 🔴🟡 | What to push |
|---|--------|------|------|---------------|-----|--------------|
| 2 | `aws/project-02-variables-outputs` | `terraform.tfvars` (copy of `.example`) | 4 | `project = "hello"` | 🟢→🟡 | Any short name (becomes part of the bucket name — final name must be globally unique) |
| 3 | same | `terraform.tfvars` | 5 | `environment = "dev"` | 🟢 | `dev` / `staging` / `prod` (anything else fails a validation rule — that's the lesson) |
| 4 | same | `terraform.tfvars` | 6 | `versioning = true` | 🟢 | `true` / `false` |

### AWS `project-03-ec2-web-server`

| # | Folder | File | Line | Current dummy | 🔴🟡 | What to push |
|---|--------|------|------|---------------|-----|--------------|
| 5 | `aws/project-03-ec2-web-server` | `terraform.tfvars` | 5 | `instance_type = "t4g.micro"` | 🟢 | Keep it (smallest, free-tier friendly) |
| 6 | `aws/project-03-ec2-web-server` | `terraform.tfvars` | 6 | `allowed_cidr = "0.0.0.0/0"` | 🔴 | Your own IP: run `curl ifconfig.co` → push e.g. `"103.22.55.10/32"` (opening the box to the whole internet is the #1 beginner mistake) |

### AWS `project-04-for-each-and-count` — no dummies. All values have safe defaults; just run it.
### AWS `project-05-your-first-module` — no dummies. Module inputs are wired in the root `main.tf`; just run it.

### AWS `project-06-remote-backend-state` (the multi-step one — order matters!)

Run `00-bootstrap/` FIRST, then the project. The names below **must match between the two folders**.

| # | Folder | File | Line | Current dummy | 🔴🟡 | What to push |
|---|--------|------|------|---------------|-----|--------------|
| 7 | `aws/project-06-remote-backend-state/00-bootstrap` | `main.tf` | 13 | `bucket = "my-tf-state-bucket-2026"` | 🟡 | Keep, or make unique (e.g. `my-tf-state-bucket-2026-ra`) — if you change it, change #8 too |
| 8 | same | `main.tf` | 31 | `name = "my-tf-state-locks-2026"` | 🟡 | Keep, or make unique — must match #9 |
| 9 | `aws/project-06-remote-backend-state` | `backend.tf` | 3 | `bucket = "my-tf-state-bucket-2026"` | 🔴 | **The exact bucket name from #7** (must match character-for-character) |
| 10 | same | `backend.tf` | 4 | `key = "dev/terraform.tfstate"` | 🟢 | Keep `dev/…` (one state "file" per environment per project) |
| 11 | same | `backend.tf` | 5 | `region = "us-east-1"` | 🟡 | The region where the bootstrap bucket lives |
| 12 | same | `backend.tf` | 6 | `dynamodb_table = "my-tf-state-locks-2026"` | 🔴 | **The exact table name from #8** |
| 13 | `aws/project-06-remote-backend-state` | `main.tf` | 13 | `bucket = "my-state-project-data-2026"` | 🟡 | Globally-unique bucket name (change suffix if taken) |
| 14 | same | `variables.tf` | 40 | `default = "us-east-1"` | 🟢 | Any region you like |

### AWS `project-07-iam-lambda-serverless`

| # | Folder | File | Line | Current dummy | 🔴🟡 | What to push |
|---|--------|------|------|---------------|-----|--------------|
| 15 | `aws/project-07-iam-lambda-serverless` | `main.tf` | 16 | `bucket = "my-lambda-lab-events-2026"` | 🟡 | Globally-unique bucket name (change suffix if taken) |

### AWS `project-08-capstone-3-tier-app`

| # | Folder | File | Line | Current dummy | 🔴🟡 | What to push |
|---|--------|------|------|---------------|-----|--------------|
| 16 | `aws/project-08-capstone-3-tier-app` | `terraform.tfvars` | 4 | `project = "capstone"` | 🟢→🟡 | Short prefix (becomes part of RDS/S3/ALB names) |
| 17 | same | `terraform.tfvars` | 5 | `instance_type = "t4g.micro"` | 🟢 | Keep it |
| 18 | same | `terraform.tfvars` | 6 | `db_username = "admin"` | 🟢 | Any username (not a reserved word) |
| 19 | same | `terraform.tfvars` | 7 | `db_password = "CHANGE-ME"` | 🔴 | A strong RDS password: 16 chars, 3+ character classes, no common words — e.g. `Capst0ne-!x9qWz` |
| 20 | same | `terraform.tfvars` | 8 | `db_name = "appdb"` | 🟢 | Any database name |
| 21 | `aws/project-08-capstone-3-tier-app` | `static.tf` | 4 | `bucket = "${var.project}-static-cf-2026"` | 🟡 | The `-2026` suffix exists so the name is globally unique — change it if the bucket name is taken |

### AWS `project-09-cloudwatch-alarms-autoscaling`

| # | Folder | File | Line | Current dummy | 🔴🟡 | What to push |
|---|--------|------|------|---------------|-----|--------------|
| 22 | `aws/project-09-cloudwatch-alarms-autoscaling` | `terraform.tfvars` | 4 | `project = "alarmlab"` | 🟢 | Any short prefix |
| 23 | same | `terraform.tfvars` | 5 | `region = "us-east-1"` | 🟢 | Any region |
| 24 | same | `terraform.tfvars` | 6 | `alarm_email = ""` | 🟡 | Your email (e.g. `you@gmail.com`) to actually get alarm emails — you must then click the confirmation link in the first email; or keep `""` to build without notifications |

### AWS `project-10-sns-sqs-decoupled-architecture` — no `tfvars` file; defaults are safe:

| # | Folder | File | Line | Current dummy | 🔴🟡 | What to push |
|---|--------|------|------|---------------|-----|--------------|
| 25 | `aws/project-10-sns-sqs-decoupled-architecture` | `variables.tf` | 3 | `default = "msglab"` | 🟢 | (optionally create `terraform.tfvars` with `project = "…"` and) keep or rename the prefix |
| 26 | same | `variables.tf` | 8 | `default = "us-east-1"` | 🟢 | Any region |

### AWS `project-11-dynamodb-secrets-and-iam` — no `tfvars` file; the "secrets" have dummy defaults:

| # | Folder | File | Line | Current dummy | 🔴🟡 | What to push |
|---|--------|------|------|---------------|-----|--------------|
| 27 | `aws/project-11-dynamodb-secrets-and-iam` | `variables.tf` | 3 | `default = "datalab"` | 🟢 | Any short prefix |
| 28 | same | `variables.tf` | 8 | `default = "us-east-1"` | 🟢 | Any region |
| 29 | same | `variables.tf` | 13 | `default = "replace-me-with-a-real-token"` (sensitive) | 🔴 | A real API token value (any string is fine for the lab, e.g. `tok-8f3a…`) — create `terraform.tfvars` with `api_token = "…"` |
| 30 | same | `variables.tf` | 19 | `default = "replace-me-with-a-real-password"` (sensitive) | 🔴 | A real password, e.g. `db-pass-2026!` |

---

## Part 2 — Azure projects: dummy values

### Azure `project-01-first-storage`

| # | Folder | File | Line | Current dummy | 🔴🟡 | What to push |
|---|--------|------|------|---------------|-----|--------------|
| 31 | `azure/project-01-first-storage` | `main.tf` | 20 | `name = "tf-lab-rg-2026"` | 🟢 | Any resource-group name |
| 32 | same | `main.tf` | 28 | `name = "tflabstorage2026"` | 🟡 | Keep, or make unique (storage names: 3–24 **lowercase letters/numbers, NO hyphens**, globally unique) |

### Azure `project-02-variables-outputs`

| # | Folder | File | Line | Current dummy | 🔴🟡 | What to push |
|---|--------|------|------|---------------|-----|--------------|
| 33 | `azure/project-02-variables-outputs` | `terraform.tfvars` | 4 | `project = "hello"` | 🟡 | Short name; the resulting storage account name must be 3–24 lowercase alphanumeric, no hyphens |
| 34 | same | `terraform.tfvars` | 5 | `environment = "dev"` | 🟢 | `dev`/`staging`/`prod` |
| 35 | same | `terraform.tfvars` | 6 | `location = "eastus"` | 🟢 | A region near you (`eastus`, `westeurope`, `southcentralindia`, …) |
| 36 | same | `terraform.tfvars` | 7 | `replication = "LRS"` | 🟢 | `LRS` / `ZRS` / `RAGRS` / `RA-GRS` |
| 37 | same | `terraform.tfvars` | 8 | `containers = ["web","uploads"]` | 🟢 | Add more names if you like |

### Azure `project-03-first-vm-ssh`

| # | Folder | File | Line | Current dummy | 🔴🟡 | What to push |
|---|--------|------|------|---------------|-----|--------------|
| 38 | `azure/project-03-first-vm-ssh` | `terraform.tfvars` | 4 | `location = "eastus"` | 🟢 | A region near you |
| 39 | same | `terraform.tfvars` | 5 | `vm_size = "Standard_B1s"` | 🟢 | Keep it (smallest) |
| 40 | same | `terraform.tfvars` | 6 | `admin_username = "adminuser"` | 🟡 | Anything except `admin`, `root`, `azureuser` |
| 41 | same | `terraform.tfvars` | 7 | `admin_password = "CHANGE-ME-123"` | 🔴 | ≥12 chars with 3+ character classes — e.g. `Vm-Passw0rd-2026!` (this variable has NO default — apply fails without it) |

### Azure `project-04-for-each-and-count` — no dummies; just run it.
### Azure `project-05-your-first-module` — no dummies; module inputs are wired in the root `main.tf`.

### Azure `project-06-remote-backend-state` (multi-step — `00-bootstrap/` first, then the project)

| # | Folder | File | Line | Current dummy | 🔴🟡 | What to push |
|---|--------|------|------|---------------|-----|--------------|
| 42 | `azure/project-06-remote-backend-state/00-bootstrap` | `main.tf` | 18 | `name = "tflabstate2026"` | 🟡 | Keep or make unique (3–24 lowercase alnum, no hyphens) — if changed, update #43 |
| 43 | `azure/project-06-remote-backend-state` | `backend.tf` | 3 | `storage_account_name = "tflabstate2026"` | 🔴 | **The exact account name from #42** |
| 44 | same | `backend.tf` | 4 | `container_name = "tfstate"` | 🔴 | The exact container the bootstrap created (`tfstate`) |
| 45 | same | `backend.tf` | 5 | `key = "dev/terraform.tfstate"` | 🟢 | Keep |
| 46 | same | `backend.tf` | 6 | `sas_token = "PASTE-YOUR-SAS-TOKEN-HERE"` | 🔴 | A real SAS token — run: `az storage container generate-sas -n tfstate -f "https://<your-account>.blob.core.windows.net" --auth-level o --permissions rwdl --expiry 2027-12-31T00:00:00Z` and paste the result **including the leading `?`** |
| 47 | `azure/project-06-remote-backend-state` | `main.tf` | 18 | `name = "tflabproject2026"` | 🟡 | Globally-unique storage name |
| 48 | same | `main.tf` | 29 | `name = "tflablegacy2026"` | 🟡 | Create a storage account with THIS exact name in the Azure Portal first (that's the resource you'll `terraform import` into state) |

### Azure `project-07-key-vault-serverless`

| # | Folder | File | Line | Current dummy | 🔴🟡 | What to push |
|---|--------|------|------|---------------|-----|--------------|
| 49 | `azure/project-07-key-vault-serverless` | `terraform.tfvars` | 4 | `project = "kvl"` | 🟡 | Keep it SHORT (vault name = prefix + suffix, max 24 chars total) |
| 50 | same | `terraform.tfvars` | 5 | `environment = "dev"` | 🟢 | `dev`/`staging`/`prod` |
| 51 | same | `terraform.tfvars` | 6 | `location = "eastus"` | 🟢 | A region near you |
| 52 | same | `terraform.tfvars` | 7 | `secret_value = "dev-api-key-123"` | 🔴 | The real secret value you want stored (anything for the lab) |

### Azure `project-08-capstone-3-tier-app`

| # | Folder | File | Line | Current dummy | 🔴🟡 | What to push |
|---|--------|------|------|---------------|-----|--------------|
| 53 | `azure/project-08-capstone-3-tier-app` | `terraform.tfvars` | 4 | `project = "capst"` | 🟡 | Keep it SHORT (SQL server + vault names have length limits) |
| 54 | same | `terraform.tfvars` | 5 | `location = "eastus"` | 🟢 | A region near you |
| 55 | same | `terraform.tfvars` | 6 | `sql_password = "Capstone-12345!"` | 🔴 | A strong SQL admin password (12+ chars, 3+ classes, avoid common words) |
| 56 | same | `terraform.tfvars` | 7 | `admin_password = "Capstone-12345!"` | 🔴 | A strong VM admin password |

### Azure `project-09-observability-app-insights`

| # | Folder | File | Line | Current dummy | 🔴🟡 | What to push |
|---|--------|------|------|---------------|-----|--------------|
| 57 | `azure/project-09-observability-app-insights` | `terraform.tfvars` | 4 | `project = "obs"` | 🟢 | Any short prefix |
| 58 | same | `terraform.tfvars` | 5 | `location = "eastus"` | 🟢 | A region near you |
| 59 | same | `terraform.tfvars` | 6 | `alert_email = ""` | 🟡 | Your email to get the CPU alert (creates the action group) or keep `""` to skip notifications |

### Azure `project-10-service-bus-and-queues`

| # | Folder | File | Line | Current dummy | 🔴🟡 | What to push |
|---|--------|------|------|---------------|-----|--------------|
| 60 | `azure/project-10-service-bus-and-queues` | `terraform.tfvars` | 4 | `project = "msg"` | 🟡 | Short prefix — the namespace becomes `<project>-sb-2026` and must be globally unique |
| 61 | same | `terraform.tfvars` | 5 | `location = "eastus"` | 🟢 | A region near you |

### Azure `project-11-cosmos-key-vault-managed-identity`

| # | Folder | File | Line | Current dummy | 🔴🟡 | What to push |
|---|--------|------|------|---------------|-----|--------------|
| 62 | `azure/project-11-cosmos-key-vault-managed-identity` | `terraform.tfvars` | 4 | `project = "cosmos"` | 🟡 | Short prefix — Cosmos account becomes `<project>-cosmos-2026` (globally unique, lowercase) |
| 63 | same | `terraform.tfvars` | 5 | `location = "eastus"` | 🟢 | A region near you |
| 64 | same | `terraform.tfvars` | 6 | `db_password = "Cosmos-12345!"` | 🔴 | A real password (it will live inside the Key Vault) |

---

## Part 3 — Projects 12–14 (the real-time integration projects)

### AWS `project-12-apigw-lambda-dynamodb` (Real-Time Order API)

| # | Folder | File | Line | Current dummy | 🔴🟡 | What to push |
|---|--------|------|------|---------------|-----|--------------|
| 65 | `aws/project-12-apigw-lambda-dynamodb` | `terraform.tfvars` | 4 | `project = "ordersapi"` | 🟢 | Any prefix (API, Lambda, table are all named from it) |
| 66 | same | `terraform.tfvars` | 5 | `region = "us-east-1"` | 🟢 | Any region (the API URL is region-specific) |

> No hardcoded names: the DynamoDB table name is `<project>-orders` (unique per region).
> The Lambda code (`api/orders.py`) needs no editing — the table name is injected as an env var.

### AWS `project-13-step-functions-order-workflow` (Order Pipeline with Approval Branch)

| # | Folder | File | Line | Current dummy | 🔴🟡 | What to push |
|---|--------|------|------|---------------|-----|--------------|
| 67 | `aws/project-13-step-functions-order-workflow` | `terraform.tfvars` | 4 | `project = "orderflow"` | 🟢 | Any prefix |
| 68 | same | `terraform.tfvars` | 5 | `region = "us-east-1"` | 🟢 | Any region |
| 69 | same | `terraform.tfvars` | 6 | `big_order_threshold = 1000` | 🟡 | The amount that triggers the approval branch (try `10`) |
| 70 | `aws/project-13-step-functions-order-workflow` | `main.tf` | 16 | `bucket = "${var.project}-order-archive-2026"` | 🟡 | Globally-unique S3 name (change the `-2026` suffix if taken) |

### AWS `project-14-kinesis-eventbridge-realtime` (Real-Time Clickstream)

| # | Folder | File | Line | Current dummy | 🔴🟡 | What to push |
|---|--------|------|------|---------------|-----|--------------|
| 71 | `aws/project-14-kinesis-eventbridge-realtime` | `terraform.tfvars` | 4 | `project = "clicklab"` | 🟢 | Any prefix |
| 72 | same | `terraform.tfvars` | 5 | `region = "us-east-1"` | 🟢 | Any region |
| 73 | same | `terraform.tfvars` | 6 | `alert_email = ""` | 🟡 | Your email for "new minute file" alerts (confirm once), or keep `""` |
| 74 | `aws/project-14-kinesis-eventbridge-realtime` | `main.tf` | 79 | `bucket = "${var.project}-click-stats-2026"` | 🟡 | Globally-unique S3 name (change suffix if taken) |

### Azure `project-12-functions-service-bus-blob` (Order Processing Pipeline)

| # | Folder | File | Line | Current dummy | 🔴🟡 | What to push |
|---|--------|------|------|---------------|-----|--------------|
| 75 | `azure/project-12-functions-service-bus-blob` | `terraform.tfvars` | 4 | `project = "func"` | 🟡 | Keep it short (3 storage/namespace names are built from it) |
| 76 | same | `terraform.tfvars` | 5 | `location = "eastus"` | 🟢 | A region near you |
| 77 | `azure/project-12-functions-service-bus-blob` | `main.tf` | 21 | `name = "${var.project}func2026"` | 🟡 | Globally-unique storage name (3–24 lowercase, no hyphens) |
| 78 | same | `main.tf` | 32 | `name = "${var.project}-sb-2026"` | 🟡 | Globally-unique Service Bus namespace |
| 79 | same | `main.tf` | 71 | `name = "${var.project}-func-app-2026"` | 🟡 | Globally-unique function hostname |

> The function code (`function/main.py`) is zip-deployed by Terraform — no editing needed;
> its Service Bus connection string comes from the namespace automatically.

### Azure `project-13-event-hubs-stream-analytics` (IoT Telemetry, Live Filter)

| # | Folder | File | Line | Current dummy | 🔴🟡 | What to push |
|---|--------|------|------|---------------|-----|--------------|
| 80 | `azure/project-13-event-hubs-stream-analytics` | `terraform.tfvars` | 4 | `project = "iot"` | 🟡 | Short prefix (job name must be 3–50 chars) |
| 81 | same | `terraform.tfvars` | 5 | `location = "eastus"` | 🟢 | A region near you |
| 82 | same | `terraform.tfvars` | 6 | `hot_threshold = 80` | 🟡 | The temperature that makes a reading "hot" |
| 83 | `azure/project-13-event-hubs-stream-analytics` | `main.tf` | 20 | `name = "${var.project}stream2026"` | 🟡 | Globally-unique storage name |
| 84 | same | `main.tf` | 36 | `name = "${var.project}-eh-2026"` | 🟡 | Globally-unique Event Hubs namespace |

### Azure `project-14-api-management-gateway` (Public API Behind a Gateway)

| # | Folder | File | Line | Current dummy | 🔴🟡 | What to push |
|---|--------|------|------|---------------|-----|--------------|
| 85 | `azure/project-14-api-management-gateway` | `terraform.tfvars` | 4 | `project = "apim"` | 🟡 | Short prefix (gateway name = `<project>-apim-2026`, 3–50 chars, starts with a letter) |
| 86 | same | `terraform.tfvars` | 5 | `location = "eastus"` | 🟢 | A region near you |
| 87 | same | `terraform.tfvars` | 6 | `rate_limit_calls = 10` | 🟡 | Max calls per client per period (try `3` to see 429s fast) |
| 88 | same | `terraform.tfvars` | 7 | `rate_limit_seconds = 1` | 🟢 | The renewal period in seconds |
| 89 | `azure/project-14-api-management-gateway` | `main.tf` | 40 | `name = "${var.project}-apim-2026"` | 🟡 | Globally-unique gateway name |

> No secrets in this project. If you enable `subscription_required = true` (README "Break it"),
> the API key is generated in the portal (Products → Starter) — it never lives in Terraform.

---

## Part 4 — The five values that actually matter (summary)

1. 🔴 **Your IP** — `aws/project-03…/terraform.tfvars` line 6 (`curl ifconfig.co` → `x.x.x.x/32`).
2. 🔴 **Passwords** — aws p08 line 7, azure p03 line 7, azure p08 lines 6–7, azure p11 line 6, aws p11 (token+password in tfvars).
3. 🔴 **Azure SAS token** — `azure/project-06…/backend.tf` line 6 (from `az storage container generate-sas`, includes `?`).
4. 🟡 **Globally-unique names** — every hardcoded `…2026` name (S3 buckets, storage accounts, namespaces) if "already exists" errors appear.
5. 🟡 **Emails** — aws p09 line 6 / azure p09 line 6 (optional; `""` is valid).

**Credentials are NOT dummy values in the code** — they come from your environment:
`aws configure` (or env vars) for AWS, `az login` for Azure. If a project errors with "no valid credentials", fix that first.
