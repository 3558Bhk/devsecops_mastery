# Project 05 — Your First Module (AWS)

**Difficulty:** ⭐⭐⭐ · **⏱️ ~60 min** · **Cost:** ~$0 (VPCs are free)

You will split Terraform code into two parts: a **child module** (a reusable VPC) and a
**root** that calls it. This is the same architecture real teams use.

## Concepts practiced
- Child module layout (`modules/vpc/`) → `../terraform-mastery/00-terraform-core/06-modules.md`
- Module **inputs** = `variable` blocks inside the module; the root passes values in
- Module **outputs** = `output` blocks inside the module; the root reads `module.vpc.xxx`
- A child module has **no** `terraform`/`provider` blocks — the root supplies those
- Bonus: the module uses `count` to make one subnet per AZ (so the capstone can use it later)

## Structure

```
project-05-your-first-module/
├── main.tf                  ← the ROOT: calls the module
├── variables.tf             ← the ROOT's inputs
├── outputs.tf               ← the ROOT's outputs (read from the module)
└── modules/
    └── vpc/                 ← the CHILD MODULE (reusable VPC)
        ├── main.tf
        ├── variables.tf
        └── outputs.tf
```

## Run it

```bash
cd project-05-your-first-module
terraform init
terraform plan        # you'll see resources named module.vpc.aws_subnet.public["..."]
terraform apply
```

## Verify it

```bash
terraform output vpc_id
aws ec2 describe-vpcs --vpc-ids $(terraform output -raw vpc_id) \
  --query "Vpcs[0].{Name:Tags[?Key=='Name']|[0].Value,Subnets:Associations.length()}" --output table
```

Console → VPC → your VPC with **two public subnets** (one per AZ).

## Break it (this is the learning)

1. Change `cidr_block` in `main.tf` to `10.20.0.0/16` → `plan` → the VPC updates **in place**. Apply.
2. Change `name` in `variables.tf` (edit the default) → `plan` → only tags change. Apply.
3. Change `az_count = 2` to `az_count = 1` in `modules/vpc/main.tf` → `plan` →
   one subnet destroyed (`aws_subnet.public[1]`), the other untouched.

## Clean up

```bash
terraform destroy
```

## Common mistakes

| Mistake | Fix |
|---|---|
| `No declaration for "module.vpc"` | typo in `source` path, or the folder isn't named exactly `vpc` |
| `Error: Unsupported block` inside the module | you added a `provider`/`terraform` block to the child — remove it, the root owns those |
| Module input "not set" | the variable in `modules/vpc/variables.tf` has no default AND the root doesn't pass it |
