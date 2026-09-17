# S3 Bucket — Terraform how-to

## 📁 File structure (the standard Terraform layout)

| File | What it does |
|---|---|
| `providers.tf` | the `terraform` block (required_providers) + provider config — "which cloud, which provider version, how to log in" |
| `variables.tf` | input variables — the knobs (e.g. `region`) you change without touching the resources |
| `main.tf` | the resources — the actual infrastructure Terraform creates (and any `data` lookups) |
| `outputs.tf` | output values — the endpoints/ids/URLs Terraform prints after `apply` |

> Why four files? Terraform reads **every** `.tf` file in the folder as one program. Splitting by
> concern is the industry convention: reviewers find the resources in `main.tf`, you change
> settings in `variables.tf`, and you read results in `outputs.tf` — instead of one 500-line file.

**What:** the object storage bucket with the production baseline: versioning, encryption, public-access lock, lifecycle.

**Interview angle (SDE3):**
- S3 is a **flat namespace** (folders are key prefixes); object storage ≠ file storage (no fs semantics).
- The modern default: **deny all public access** (the 4 block settings), SSE-KMS, versioning, lifecycle to IA/Glacier.
- S3 is the origin for CloudFront, the event source for Lambda, the state backend for Terraform — it's the connective tissue.

## Run it
```bash
terraform init && terraform plan && terraform apply
# verify: aws s3api get-bucket-versioning --bucket lab-bucket-2026
#         aws s3api get-bucket-encryption --bucket lab-bucket-2026
```

## Clean up
```bash
terraform destroy
```

## Common mistakes
| Mistake | Fix |
|---|---|
| `PublicAccessBlockNotSupported`-type errors on CloudFront OAC | don't block what CloudFront needs — OAC works with block settings ON (it's not "public") |
| Can't delete the bucket | turn off versioning + delete **versions** (including delete markers) first |
| "Accidentally public" | that's what the 4 block settings + an SCP are for — the block is the default, not an option |
