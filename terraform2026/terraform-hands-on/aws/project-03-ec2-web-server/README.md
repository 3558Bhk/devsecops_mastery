# Project 03 — Your First EC2 Web Server (AWS)

**Difficulty:** ⭐⭐ · **⏱️ ~60 min** · **Cost:** ~$0.02/hr while the instance runs (destroy after!)

You will launch a real Linux server in AWS that serves a web page, and open it in your browser.

## Concepts practiced
- **Data sources** — reading things that already exist (the AMI) instead of creating them → `../terraform-mastery/01-aws-provider/03-ec2-compute.md`
- **Security groups** — AWS's stateful firewall → `../terraform-mastery/01-aws-provider/02-vpc-and-networking-fundamentals.md`
- **`user_data`** — a script AWS runs once at first boot
- Heredoc (`<<-EOF`) for multi-line strings

## Files in this folder

| File | What it is |
|---|---|
| `variables.tf` | environment, instance type, allowed SSH IP |
| `main.tf` | AMI lookup + security group + the instance |
| `outputs.tf` | public IP + instance ID |
| `terraform.tfvars.example` | sample inputs |

## Run it

```bash
cd project-03-ec2-web-server

cp terraform.tfvars.example terraform.tfvars

# strongly recommended: restrict SSH to YOUR ip
curl -s ifconfig.co                  # copy that IP into terraform.tfvars → allowed_cidr

terraform init
terraform plan                        # 1 data source + 2 resources
terraform apply
```

`apply` takes ~1 minute (the instance must boot).

## Verify it

```bash
terraform output public_ip            # e.g. 54.123.45.67
sleep 30                              # give httpd time to start
curl http://$(terraform output -raw public_ip)
```

Expect: `Hello from Terraform!` — open `http://<that-ip>` in a browser too.

## Break it (this is the learning)

1. Change `instance_type` to `t4g.small` → `plan` → in-place **update**? (yes — type changes don't replace the instance). Apply, then switch back.
2. Change the AMI lookup filter → `plan` → **replacement** (the AMI is immutable). Don't apply — just read the plan.
3. Add a second `ingress` rule (port 443) → `plan` → in-place update.

## Clean up

```bash
terraform destroy     # the instance is gone in ~30s — check with aws ec2 describe-instances
rm terraform.tfvars
```

## Common mistakes

| Mistake | Fix |
|---|---|
| `curl` times out | wait a full minute; then check the SG: `aws ec2 describe-security-groups` |
| Browser works but `curl` from your laptop fails (or vice versa) | you restricted `allowed_cidr` but tested from a different network |
| `NoImageFound` from the data source | check the filter string in `main.tf` — AMI names change occasionally |
