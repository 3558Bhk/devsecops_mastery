# SNS — Terraform how-to

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

**What:** the notification bus: a topic + subscriptions (email, SMS, SQS, Lambda) — fan-out for events and alarms.

**Interview angle (SDE3):**
- SNS = **fan-out** (1 publish → N subscribers); SQS = **fan-in/queue**. Together they make the decoupled pattern (SNS→SQS→worker).
- Subscription confirmation: email/SMS subs must be **confirmed** once (the link) — a classic "why am I not getting alerts" cause.
- Filter policies per subscription = "this subscriber only gets messages where severity=high".

## Run it
```bash
terraform init && terraform plan && terraform apply
# publish: aws sns publish --topic-arn $(aws sns list-topics --query 'Topics[?TopicName=`lab-alerts`].TopicArn | [0]' --output text) \
#           --message "hello from terraform"
```

## Clean up
```bash
terraform destroy
```

## Common mistakes
| Mistake | Fix |
|---|---|
| Email sub never delivers | the subscription was never **confirmed** (check the inbox for the confirmation link) |
| "Everyone gets everything" | add a `filter_policy` on the subscription — that's how you scope a sub |
| SMS not working | the account needs a verified number + SMS opt-in in the account settings |
