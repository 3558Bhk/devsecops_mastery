# Project 13 — Order Pipeline with Approval Branch (AWS)

**Difficulty:** ⭐⭐⭐⭐⭐ · **⏱️ ~60 min** · **Cost:** ~$0.05/mo (Step Functions free tier covers it) — destroy after

A **real-time order pipeline** the way companies actually build it: an order comes in, a state
machine routes it (big orders get flagged to a human, small ones go straight through), everything
gets archived, and failures are retried — all orchestrated, all observable.

## The real-time flow

```
Start (start the machine from the console, or an EventBridge rule on a DynamoDB write)
  │
  ▼
[ReceiveOrder] Lambda: validate the order
  │
  ▼
[RouteByAmount] Choice: $.amount > 1000 ?
  │ yes                              │ no
  ▼                                  ▼
[NotifyLargeOrder]            [ArchiveOrder] Lambda:
  Lambda → SNS topic               write order JSON to S3
  (a human gets paged)               │
  │                                  │
  └──────────────┬───────────────────┘
                 ▼
            [ArchiveOrder]  (retries 3× on failure, then the run fails)
```

## Concepts practiced
- Step Functions (state machines, Choice, Retry) → `../terraform-mastery/01-aws-provider/10-serverless-aws.md`
- Wiring services with a shared role + exact ARNs → `../terraform-mastery/01-aws-provider/07-iam.md`
- "Orchestrate, don't couple" — the Lambdas never call each other

## Files in this folder

| File | What it is |
|---|---|
| `variables.tf` | project, region, big-order threshold |
| `main.tf` | S3 + SNS + 3 Lambdas + the state machine |
| `lambda/order_received.py` | step 1: validate |
| `lambda/notify_large.py` | step 2 (branch): page via SNS |
| `lambda/archive_order.py` | final step: persist to S3 |
| `outputs.tf` | machine ARN + console URL |
| `terraform.tfvars.example` | sample inputs |

## Run it

```bash
cd project-13-step-functions-order-workflow
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
```

## Verify it (start it twice — small order, then big one)

```bash
SM=$(terraform output -raw state_machine_arn)

# 1. a SMALL order (skips the approval branch)
aws stepfunctions start-sync-execution \
  --state-machine-arn "$SM" \
  --input '{"order_id":"small-1","item":"mouse","amount":25}'

# 2. a BIG order (takes the NotifyLargeOrder branch — check your SNS email)
aws stepfunctions start-sync-execution \
  --state-machine-arn "$SM" \
  --input '{"order_id":"big-1","item":"server","amount":4500}'

# 3. the archive: both orders are now in S3
BUCKET=$(terraform output -raw archive_bucket)
aws s3 ls s3://$BUCKET/orders/
aws s3 cp s3://$BUCKET/orders/big-1.json -    # see the "reviewed" annotation
```

## Break it (this is the learning)

1. Start with `"amount": 5000` but **no `order_id`** → the ReceiveOrder Lambda raises → the run fails.
   Open the **Visual Workflow** in the console and watch the red state. That picture is your debugging tool.
2. Change `big_order_threshold` to `10` in tfvars → `apply` → the machine's JSON is regenerated → start a
   `$25` order → it now takes the "large" branch. (Variables flow into the definition string.)
3. Delete the archive bucket's policy? (No — instead: temporarily rename the S3 bucket in the Lambda's
   env to a bucket that doesn't exist → start → watch the **Retry** block attempt 3 times, ~1s and ~2s apart.)

## Clean up

```bash
terraform destroy
```

## Common mistakes

| Mistake | Fix |
|---|---|
| `Invalid state machine definition` | the `definition` must be valid JSON *and* valid ASL — a typo in a state name breaks it; read the error's state name |
| Lambda state shows `States.TaskFailed` after retries | the Lambda is erroring — check its CloudWatch logs (90% of the time: missing env var / wrong bucket name) |
| "Execution can't start" / quota | check `aws stepfunctions describe-state-machine` + your SNS topic exists (a missing topic ARN in env → publish error inside the notify Lambda) |
| `start-sync-execution` not found in old CLI | use `aws stepfunctions start-execution` + poll `describe-execution` instead |
