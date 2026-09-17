# Project 06 — Remote Backend, State Surgery & Import (AWS)

**Difficulty:** ⭐⭐⭐ · **⏱️ ~60 min** · **Cost:** ~$0

Until now your state lived in a local file. Teams store it in a remote backend (S3 here)
so it survives your laptop and can be locked. You'll also learn to operate on state
directly, and to adopt (import) resources that already exist.

## Concepts practiced
- S3 + DynamoDB remote backend (locking) → `../terraform-mastery/00-terraform-core/04-state-and-backends.md`
- `terraform state list / show / mv / rm`
- `terraform import` → `../terraform-mastery/00-terraform-core/07-advanced-resource-configuration.md`

## Structure

```
project-06-remote-backend-state/
├── 00-bootstrap/        ← step 1: creates the state bucket + lock table (run this once)
│   └── main.tf
├── backend.tf           ← tells the MAIN project to store state in S3
├── main.tf              ← the main project: 2 buckets (one declared for import)
├── outputs.tf
└── variables.tf
```

## Run it — step by step

**Step 1 — bootstrap the backend (run once, in its own folder):**

```bash
cd project-06-remote-backend-state/00-bootstrap
terraform init && terraform apply
cd ..
```

**Step 2 — run the main project against the remote backend:**

```bash
terraform init
# Terraform will ask: "Do you want to copy existing state to the backend?" → yes
terraform plan && terraform apply
```

**Step 3 — prove the state is remote:**

```bash
aws s3api get-object --bucket my-tf-state-bucket-2026 --key dev/terraform.tfstate /tmp/state.json && head -c 200 /tmp/state.json
ls terraform.tfstate          # → No such file: nothing local anymore!
```

**Step 4 — state surgery (do these in order, read each plan afterwards):**

```bash
terraform state list                              # what Terraform is tracking
terraform state show aws_s3_bucket.data           # the full recorded configuration
terraform state mv aws_s3_bucket.data aws_s3_bucket.data_v2   # rename in state only
# (after `mv`, the address in main.tf must match — rename the resource in main.tf too, then `terraform plan` shows NO changes: the magic moment)
terraform state rm aws_s3_bucket.data_v2          # stop tracking it (bucket still exists in AWS!)
```

**Step 5 — import an existing resource:**

1. In the AWS console, create a bucket named `my-legacy-bucket-2026` (empty, same region).
2. `main.tf` already declares an empty `aws_s3_bucket.legacy` for this purpose.
3. Adopt it:

```bash
terraform import aws_s3_bucket.legacy my-legacy-bucket-2026
terraform plan        # now ~0 changes: Terraform manages the existing bucket
```

## Clean up

```bash
terraform destroy          # destroys BOTH buckets, including the imported one
aws s3 rb my-tf-state-bucket-2026 --force   # empty the state bucket (or use the console)
cd 00-bootstrap && terraform destroy && cd ..
```

## Common mistakes

| Mistake | Fix |
|---|---|
| `Error: Error fetching S3 state: AccessDenied` | the account in `aws configure` isn't the one that created the bucket |
| After `state mv`, plan wants to create+destroy | you renamed in state but not in `main.tf` — keep both in sync |
| `import` says "resource not found" | wrong region, or the bucket name has different casing |
| `state rm` and the resource vanished from AWS! | it shouldn't — if it did, you ran `terraform apply` after the rm with a stale plan; re-plan first |
