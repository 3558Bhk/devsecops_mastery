# Project 11 — DynamoDB, Secrets (SSM + Secrets Manager) & Scoped IAM (AWS)

**Difficulty:** ⭐⭐⭐ · **⏱️ ~45 min** · **Cost:** ~$0 (PAY_PER_REQUEST DynamoDB + free SSM/SM limits)

The three "boring" things every production app needs: a NoSQL table, a place for secrets,
and an IAM role that can touch *exactly* those things and nothing else.

## Concepts practiced
- DynamoDB: partition keys, GSI, TTL, pay-per-request → `../terraform-mastery/01-aws-provider/06-databases-rds-dynamodb-aurora.md`
- SSM Parameter Store vs Secrets Manager (when each) → `../terraform-mastery/01-aws-provider/05-iam-identity-and-security.md`
- Writing a **custom** IAM policy scoped to specific ARNs (least privilege, hands-on)

## SSM vs Secrets Manager (memorize)

| | SSM Parameter Store | Secrets Manager |
|---|---|---|
| for | config, connection strings, small strings | passwords/keys that **rotate** |
| cost | free up to 300K params | $0.40/secret/month |
| rotation | no (you change it) | **yes** (AWS rotates DB passwords for you) |
| versioning | yes | yes (+ recovery) |

## Files in this folder

| File | What it is |
|---|---|
| `variables.tf` | project name, region |
| `main.tf` | table + parameters + secret + role + custom policy |
| `outputs.tf` | table ARN, parameter names, secret ARN, role ARN |

## Run it

```bash
cd project-11-dynamodb-secrets-and-iam
terraform init
terraform plan
terraform apply
```

## Verify it

```bash
TABLE=$(terraform output -raw table_arn)

# 1. put + get an item
aws dynamodb put-item --table-name $(terraform output -raw table_name) \
  --item '{"order_id": {"S": "1"}, "status": {"S": "new"}, "total": {"N": "99.50"}}'
aws dynamodb get-item --table-name $(terraform output -raw table_name) \
  --key '{"order_id": {"S": "1"}}'

# 2. read the parameters (SecureString shows the value only via GetParameter with WithDecryption)
aws ssm get-parameter --name /$(terraform output -raw project)/app/env            --query "Parameter.Value" --output text
aws ssm get-parameter --name /$(terraform output -raw project)/app/api_token --with-decryption --query "Parameter.Value" --output text

# 3. read the secret
aws secretsmanager get-secret-value --secret-id $(terraform output -raw secret_arn) --query SecretString --output text

# 4. prove least privilege: assume the role and try to read ANOTHER account's resource
aws sts assume-role --role-arn $(terraform output -raw role_arn) --role-session-name test
# (with the assumed role): aws dynamodb list-tables works, but `aws s3 ls` should DENY
aws dynamodb list-tables
aws s3 ls        # ← expect: AccessDenied (the role has no S3 permissions — that's the point)
aws sts get-caller-identity
```

## Break it (this is the learning)

1. Add an item with `"expires_at": {"N": "<unix timestamp 1 day from now>"}` → wait for TTL
   (up to 48h — conceptually) → the table deletes it for free.
2. Query the GSI: `aws dynamodb query --table-name ... --index-name StatusIndex \
   --key-conditions-expression "status = :s" --expression-attribute-values '{":s":{"S":"new"}}'`
3. In the policy, remove the `Condition` block → `plan` → in-place. Why was the condition there?
   (so the role can't read the token from *another* project's parameter path).

## Clean up

```bash
terraform destroy
```

## Common mistakes

| Mistake | Fix |
|---|---|
| `ValidationException` on put-item | DynamoDB item values need type wrappers: `{"S": "x"}` not `"x"` |
| `AccessDenied` on get-parameter for the token | you forgot `--with-decryption` (SecureString parameters) |
| GSI query fails | the key you're querying must be the GSI's partition key (`status` here), and you need the expression values syntax |
