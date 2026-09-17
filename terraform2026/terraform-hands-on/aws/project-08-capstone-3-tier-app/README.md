# Project 08 — Capstone: 3-Tier Web App (AWS)

**Difficulty:** ⭐⭐⭐⭐ · **⏱️ ~2.5 hrs** · **Cost: ~$1.50–2.50/hr while running — TEST, THEN DESTROY**

Everything you've learned, combined into one realistic architecture:

```
internet ──► CloudFront (static site)
     └────► ALB ──► Auto Scaling Group (N Apache servers, t4g.micro)
                          └──► RDS PostgreSQL (db.t4g.micro)
```

The web tier reuses **the VPC module you built in project 05** — that's the module payoff.

## Files in this folder

| File | What it is |
|---|---|
| `variables.tf` | environment, instance size, DB credentials |
| `network.tf` | calls the project-05 VPC module |
| `web.tf` | launch template + target group + ALB + listener + ASG |
| `db.tf` | DB subnet group + DB security group + RDS instance |
| `static.tf` | S3 bucket + CloudFront distribution (private via OAC) |
| `outputs.tf` | ALB DNS, CloudFront URL, DB endpoint |

## Run it

```bash
cd project-08-capstone-3-tier-app
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan      # ~15 resources. Read every line. This is your exam.
terraform apply
```

Apply takes ~8–12 minutes (RDS is the slow part — it's being built, not failing).

## Verify it (all four must work)

```bash
# 1. the dynamic site: the ALB in front of the ASG
terraform output alb_dns
curl http://$(terraform output -raw alb_dns)          # → "Hello from the Terraform capstone!"

# 2. the static site: CloudFront in front of private S3
terraform output static_url
curl -s https://$(terraform output -raw static_url)   # → "Hello from S3 + CloudFront!"

# 3. the database: is it up?
aws rds describe-db-instances --query "DBInstances[0].DBInstanceStatus" --output text   # → available

# 4. scale: prove the ASG works
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name $(terraform output -raw asg_name) \
  --min-size 2 --max-size 2 --desired-capacity 2
sleep 90
curl -s http://$(terraform output -raw alb_dns)       # still works, now on 2 instances
```

## Break it (this is the learning)

1. Kill one instance: find it (`aws autoscaling describe-auto-scaling-groups --query 'AutoScalingGroups[0].Instances[].InstanceId'`) and
   `aws ec2 terminate-instances --instance-ids i-...` → the ASG replaces it in ~1 minute. Curl again: still works.
2. `terraform output db_endpoint` → connect from a public box:
   `psql "postgresql://admin:CHANGE-ME@<endpoint>:5432/appdb"` (the password is in your tfvars).

## Clean up (MONEY IS BURNING)

```bash
terraform destroy     # takes ~10 min; RDS is destroyed last (dependency order)
```

Check the bill later: Cost Explorer → your project name appears via the tags.

## Common mistakes

| Mistake | Fix |
|---|---|
| ALB `CreationFailed: at least one subnet in two AZs` | your project-05 module must be the 2-AZ version (it is, if you followed it) |
| RDS never becomes `available` | check `aws rds describe-db-instances --query 'DBInstances[0].Status'`; `db.t4g.micro` is the cheapest, be patient |
| CloudFront URL gives 403 | the bucket policy/OAC wiring in `static.tf` — re-apply and wait (policy propagation takes ~30s) |
| `plan` shows a replacement of RDS | you changed an *immutable* attribute (engine, identifier) — read the plan's "because:" line |
