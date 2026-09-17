# AWS Config — Terraform how-to

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

**What:** the **compliance** engine: a recorder (watch all resources), a delivery channel (snapshots → S3), and a rule (a policy-as-check).

**Interview angle (SDE3):**
- Config vs CloudTrail: Config = **state over time** ("was the bucket encrypted yesterday?"), Trail = **events** ("who called DeleteBucket?").
- A **conformance** question: "how do you stop unencrypted EBS from appearing?" → Config rule + (in prod) remediation via SSM Automation.
- Rules run continuously; compliance state (COMPLIANT/NON_COMPLIANT) drives alerts and auto-remediation.

## Run it
```bash
terraform init && terraform plan && terraform apply
# verify: aws config describe-configuration-recorders
#         aws config describe-config-rules
# trigger NON_COMPLIANT: create an unencrypted volume → check the rule's state
```

## Clean up
```bash
terraform destroy
```

## Common mistakes
| Mistake | Fix |
|---|---|
| Recorder "on" but no data | the delivery channel's S3 bucket/policy must allow `config.amazonaws.com` (Terraform sets the bucket policy for you when you use the `aws_config_delivery_channel` pattern with a dedicated bucket) |
| Rule shows NO_CONFIG_RULE / not evaluated yet | rules evaluate on change + a baseline scan — give it a few minutes after the first resource change |
