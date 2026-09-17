# Project 01 — Your First S3 Bucket (AWS)

**Difficulty:** ⭐ (complete beginner) · **⏱️ ~30 min** · **Cost:** ~$0 (S3 storage is pennies)

You will run Terraform for the very first time and create one real cloud resource.

## Concepts practiced
- The `terraform` and `provider` blocks → `../terraform-mastery/00-terraform-core/05-providers.md`
- The `init` → `plan` → `apply` → `destroy` loop → `../terraform-mastery/00-terraform-core/01-introduction-installation-cli.md`
- The state file (`terraform.tfstate`) → `../terraform-mastery/00-terraform-core/04-state-and-backends.md`

## Files in this folder

| File | What it is |
|---|---|
| `main.tf` | the `terraform` + `provider` blocks + your bucket |
| `outputs.tf` | values Terraform prints after `apply` |

## Run it

```bash
cd project-01-first-s3-bucket

terraform init        # downloads the AWS provider (first time in this folder)
terraform plan        # Terraform says: "I will CREATE 1 resource" — READ that
terraform apply       # type yes when asked
```

## Verify it

```bash
aws s3 ls                                   # your bucket should be listed
terraform output -json                      # see the values from outputs.tf
```

Or: AWS Console → S3 → you should see the bucket.

**Look at the new files Terraform made:**

```bash
ls -la                                      # see .terraform/ and terraform.tfstate
cat terraform.tfstate | head -30            # that file IS your infrastructure's memory
```

## Break it (this is the learning)

1. Add a `#` comment anywhere — `terraform plan` → nothing happens (comments are ignored).
2. Change the bucket name in `main.tf` → `terraform plan` → it says **destroy + create** (a bucket's name can never change in place). Apply it, then destroy.

## Clean up

```bash
terraform destroy     # type yes — watch the "Destroy complete" line
```

## Common mistakes

| Mistake | Fix |
|---|---|
| `init` fails: `no valid credential sources found` | run `aws configure` first (see `aws/README.md`) |
| `apply` fails: `BucketAlreadyExists` | bucket names are unique across ALL of AWS — pick a more unique name |
| I forgot to destroy | Console → S3 → delete the bucket, then delete the `terraform.tfstate` file too (or it'll try to "manage" a bucket that no longer exists) |
