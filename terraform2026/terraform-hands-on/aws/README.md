# AWS Track — 14 Hands-On Projects (Basic → Mastery)

Every project lives in its own folder with its own `.tf` files (each line commented).

## Prerequisites (once)

```bash
aws configure              # Access Key ID, Secret Access Key, region = us-east-1
aws sts get-caller-identity   # confirm it works
```

Free tier you're relying on: 750 hrs `t4g.micro`/month, 5 GB S3, 20 GB EBS,
12 months of `db.t4g.micro` RDS, 1 M Lambda invocations.

## The ladder

| Project | You will... | Skills | ⏱️ |
|---|---|---|---|
| `project-01-first-s3-bucket` | create your very first real resource | init / plan / apply / destroy, state file | ~30 min |
| `project-02-variables-outputs` | make the bucket configurable | `variable`, `output`, `tfvars`, validation rules | ~40 min |
| `project-03-ec2-web-server` | launch a web server and open it in a browser | data sources, security groups, `user_data` | ~60 min |
| `project-04-for-each-and-count` | create N buckets and N instances with 2 code blocks | `for_each`, `count`, splat expressions | ~45 min |
| `project-05-your-first-module` | build a reusable VPC module + a root that uses it | child modules, module inputs/outputs, `for_each` | ~60 min |
| `project-06-remote-backend-state` | move state to S3, perform state surgery, import a resource | S3 + DynamoDB backend, `state mv/show`, `import` | ~60 min |
| `project-07-iam-lambda-serverless` | an S3 upload that triggers a Lambda function | IAM roles, policy documents, `archive_file`, triggers | ~75 min |
| `project-08-capstone-3-tier-app` | VPC + ALB + ASG + RDS + S3/CloudFront, like the real world | everything, combined | ~2.5 hrs |
| `project-09-cloudwatch-alarms-autoscaling` | an ASG that scales on CPU + a CloudWatch alarm that pages you via SNS | `aws_autoscaling_policy`, metric alarms, SNS subscriptions | ~50 min |
| `project-10-sns-sqs-decoupled-architecture` | a real-time event flow: topic → 2 queues → 2 Lambdas, with dead letters | SNS/SQS fan-out, queue policies, Lambda + event sources, DLQ | ~60 min |
| `project-11-dynamodb-secrets-and-iam` | a DynamoDB table + secrets (SSM/SecretsManager) + a least-privilege role | DynamoDB GSI/TTL, SSM SecureString, SecretsManager, custom policies | ~60 min |
| `project-12-apigw-lambda-dynamodb` | a public REST API (POST/GET orders) served by one Lambda into DynamoDB | API Gateway REST + CORS + deployments, AWS_PROXY integrations | ~60 min |
| `project-13-step-functions-order-workflow` | an order pipeline: validate → route by amount (approval branch) → archive, with retries | Step Functions, Choice states, Retry, multi-Lambda orchestration | ~60 min |
| `project-14-kinesis-eventbridge-realtime` | a real-time clickstream: Kinesis → Lambda aggregator → S3 → SNS fan-out | Kinesis, event source mappings, continuous consumption, event-driven notifications | ~60 min |

**Total: ~7.5 hrs**

## Cost guardrails

- Smallest instances only: `t4g.micro` (~$0.016/hr), `db.t4g.micro` (~$0.017/hr).
- The capstone (project 08) is the most expensive lab: **~$1.50–2.50/hr while running**. Run it, test it, destroy it — don't leave it overnight.
- If you're unsure what's running: AWS Console → Cost Explorer, or `aws ec2 describe-instances` / `aws rds describe-db-instances`.

## Folder conventions (same in every project)

| File | Purpose |
|---|---|
| `main.tf` | resources (and `terraform`/`provider` blocks in simple projects) |
| `variables.tf` | inputs (`variable` blocks) |
| `outputs.tf` | values shown after `apply` |
| `terraform.tfvars.example` | sample input values — copy to `terraform.tfvars` |
| `README.md` | the plan: what, why, steps, verification, cleanup |
