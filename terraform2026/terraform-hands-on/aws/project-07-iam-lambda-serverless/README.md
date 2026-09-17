# Project 07 — IAM Role + Lambda Function Triggered by S3 (AWS)

**Difficulty:** ⭐⭐⭐ · **⏱️ ~75 min** · **Cost:** ~$0 (1M Lambda invocations free; 300K GB-s free)

You will wire four moving parts together: an S3 bucket, an IAM role, a Lambda function,
and a trigger. Upload a file → the function runs automatically.

## Concepts practiced
- IAM roles + **assume-role policies** (service principals) → `../terraform-mastery/01-aws-provider/05-iam-identity-and-security.md`
- Attaching AWS-managed policies vs writing your own
- `data.archive_file` — zipping your code with Terraform itself
- Event triggers (S3 → Lambda) → `../terraform-mastery/01-aws-provider/08-serverless-lambda-and-messaging.md`

## The flow

```
you: aws s3 cp hello.txt s3://<bucket>/
   └─► S3 emits "ObjectCreated"
         └─► Lambda function runs handler()
               └─► prints "I saw a new file: hello.txt" to CloudWatch Logs
```

## Files in this folder

| File | What it is |
|---|---|
| `main.tf` | bucket + IAM role + policies + the function + the trigger |
| `variables.tf` | the `project` name |
| `outputs.tf` | bucket name, function ARN |
| `lambda/lambda_function.py` | the actual function code (3 lines) |

## Run it

```bash
cd project-07-iam-lambda-serverless
terraform init
terraform plan
terraform apply
```

`terraform init` also downloads the `hashicorp/archive` provider (declared in `main.tf`).

## Verify it

```bash
# 1. upload a file (any small file)
echo "hi" > hello.txt
aws s3 cp hello.txt s3://$(terraform output -raw bucket_name)/

# 2. read the function's log output from CloudWatch
sleep 15
aws logs tail /aws/lambda/$(terraform output -raw function_name) --since 1m
```

You should see: `Hello! I saw a new file: hello.txt`

## Break it (this is the learning)

1. Change `timeout = 30` to `timeout = 10` → `plan` → in-place update. Apply.
2. Change a line in `lambda/lambda_function.py` → `plan` → Terraform **redeploys the function**
   (that's what `source_code_hash` does — it notices the zip changed). Apply, upload again, read logs.
3. In the console, try to `aws s3 cp` from a different region's config — the event only fires
   for the bucket in us-east-1 (events don't cross regions).

## Clean up

```bash
terraform destroy
rm hello.txt
```

## Common mistakes

| Mistake | Fix |
|---|---|
| `aws logs tail` shows nothing | Lambda log group takes a few seconds to appear; also check the function name in `aws lambda list-functions` |
| Upload works but function never runs | check the notification config: `aws s3api get-bucket-notification-configuration --bucket ...` |
| `InvalidParameterValueException` on the role | an IAM role name already exists from a previous run — `terraform destroy` first |
| Function runs but "Resource not found" in logs | you uploaded from a different region than the bucket |
