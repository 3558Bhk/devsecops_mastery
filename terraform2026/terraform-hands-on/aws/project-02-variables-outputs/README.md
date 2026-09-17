# Project 02 — S3 with Variables, Outputs & tfvars (AWS)

**Difficulty:** ⭐ · **⏱️ ~40 min** · **Cost:** ~$0

Your first bucket was hardcoded. This time the same bucket becomes *configurable*:
change inputs in one file, and Terraform rebuilds to match.

## Concepts practiced
- `variable` blocks, types, defaults, validation → `../terraform-mastery/00-terraform-core/03-variables-outputs-locals-functions.md`
- `output` blocks, `description`
- `terraform.tfvars` and the value-lookup order
- The v5 provider split: versioning and public access are now **separate resources**

## Files in this folder

| File | What it is |
|---|---|
| `variables.tf` | 3 inputs: project, environment, versioning |
| `main.tf` | bucket + versioning + public-access lock |
| `outputs.tf` | bucket name, ARN, environment |
| `terraform.tfvars.example` | sample inputs — copy to `terraform.tfvars` |

## Run it

```bash
cd project-02-variables-outputs

cp terraform.tfvars.example terraform.tfvars     # create YOUR input file
cat terraform.tfvars                             # you can edit values here later

terraform init
terraform plan                                   # see how variables appear in the plan
terraform apply
```

## Verify it

```bash
aws s3api get-bucket-versioning --bucket hello-dev-data     # Status: Enabled
terraform output                                       # all three outputs
```

## Break it (this is the learning)

1. In `terraform.tfvars` set `environment = "staging"` → `terraform plan`.
   Terraform will **replace** the bucket (name changes → new resource). Apply, then switch back.
2. Set `versioning = false` → `plan` → it updates the versioning resource **in place** (no replacement). Apply.
3. Set `environment = "production"` → `terraform plan` → **validation error** (only dev/staging/prod allowed).
4. Try the CLI override without editing the file: `terraform apply -var="environment=staging"` — CLI beats tfvars.

## Clean up

```bash
terraform destroy
rm terraform.tfvars        # optional: keep it for the next run
```

## Common mistakes

| Mistake | Fix |
|---|---|
| `Error: Variable not set` | you deleted tfvars but a variable has no default — either restore it or add a default |
| Plan says "replace" but I only changed a tag | it was probably the *name* that changed; check the `-/+` lines and the reason under "because:" |
| `terraform.tfvars` in git? | never commit it — `.gitignore` it. Commit `*.tfvars.example` instead |
