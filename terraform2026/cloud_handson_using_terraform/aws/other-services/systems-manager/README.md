# Systems Manager — Terraform how-to

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

**What:** a small EC2 instance enrolled in SSM (Session Manager, Parameter Store, Run Command) — with the right IAM.

**Interview angle (SDE3):**
- SSM = the "no SSH/keys, no bastion, no open port 22" toolkit: **Session Manager** (browser RDP/SSH), **Parameter Store** (config/secrets), **Run Command** (run a shell script on many instances at once), **Patches**.
- The magic = the instance **profile** with `AmazonSSMManagedInstanceCore` + a VPC endpoint (private subnets) so it can call the SSM API.
- SSM Parameter Store vs Secrets Manager: SSM = config + cheaper; Secrets Manager = secrets + rotation.

## Run it
```bash
terraform init && terraform plan && terraform apply
# open a session:  aws ssm start-session --target <instance-id>
# put a param:     aws ssm put-parameter --name /lab/env --value prod --type SecureString
# get it:          aws ssm get-parameter --name /lab/env --with-decryption
```

## Clean up
```bash
terraform destroy
```

## Common mistakes
| Mistake | Fix |
|---|---|
| "session couldn't start" | the instance profile doesn't have `AmazonSSMManagedInstanceCore` (the #1 SSM problem) |
| Private instance can't reach SSM API | it needs the **VPC endpoint** (`com.amazonaws.<region>.ssm`) — public subnets are fine |
| `SecureString` won't read | you need `--with-decryption` AND `kms:Decrypt` on the CMK (SSM uses a default KMS key unless you specify one) |
