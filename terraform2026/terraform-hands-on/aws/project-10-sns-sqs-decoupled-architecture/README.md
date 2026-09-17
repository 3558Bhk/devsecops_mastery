# Project 10 — Decoupled Architecture: SNS → 2×SQS → 2×Lambda (AWS)

**Difficulty:** ⭐⭐⭐ · **⏱️ ~60 min** · **Cost:** ~$0 (serverless: 1M invocations + 400K requests free)

One event, two consumers, zero coupling. This is the most common production architecture:
a **fan-out** (SNS topic → multiple SQS queues → independent workers).

## The flow

```
producer: aws sns publish --topic arn '{"order": "123"}'
   │
   ├─► billing queue    ──► billing Lambda    (logs "billing: order 123")
   └─► inventory queue  ──► inventory Lambda  (logs "inventory: order 123")
                                   │ poison message (3+ failures)
                                   └──► dead-letter queue (DLQ)
```

## Concepts practiced
- SNS fan-out + SQS decoupling → `../terraform-mastery/01-aws-provider/08-serverless-lambda-and-messaging.md`
- Queue **policies** (who may publish), DLQ + redrive, `raw_message_delivery`
- `data.archive_file` zipping both consumers

## Files in this folder

| File | What it is |
|---|---|
| `main.tf` | topic + 2 queues + DLQ + policies + 2 Lambdas + event source mappings |
| `variables.tf` | project name, region |
| `outputs.tf` | topic ARN, queue URLs, function names |
| `lambda/billing.py`, `lambda/inventory.py` | the two consumers (3 lines each) |

## Run it

```bash
cd project-10-sns-sqs-decoupled-architecture
terraform init
terraform plan        # 12 resources
terraform apply
```

## Verify it

```bash
TOPIC=$(terraform output -raw topic_arn)

# 1. publish ONE event
aws sns publish --topic-arn "$TOPIC" --message '{"order_id": "123", "amount": 99.5}'

# 2. both lambdas should have run within ~15s — read their logs
sleep 20
aws logs tail /aws/lambda/$(terraform output -raw billing_fn)  --since 2m
aws logs tail /aws/lambda/$(terraform output -raw inventory_fn) --since 2m
# both print the order — one publish, two consumers, neither knows about the other

# 3. prove decoupling: delete the inventory subscription (console or TF) and re-publish:
#    billing still works, inventory is silent — that's decoupling
```

## Break it (this is the learning)

1. **Poison the DLQ:** publish a message with a missing field the code expects:
   `aws sns publish --topic-arn "$TOPIC" --message '{}'` → the lambdas raise KeyError →
   after `max_receive_count` (2) they land in the **DLQ**:
   `aws sqs receive-message --queue-url $(terraform output -raw dlq_url) --max-number-of-messages 5`
2. Change `raw_message_delivery = true` on a subscription → `plan` → only that subscription changes.
3. Add a third consumer: copy one `queue` + one `subscription` + one `lambda` block (rename) → `plan` → 3 new resources.

## Clean up

```bash
terraform destroy
```

## Common mistakes

| Mistake | Fix |
|---|---|
| Lambda never runs after publish | check the queue policy allows SNS: `aws sqs get-queue-attributes --queue-url ... --attribute-names BasedOnPolicy` |
| `InvalidParameterValue` on subscription | the queue policy must reference the **topic ARN** — re-apply if you changed the topic name |
| Logs show `KeyError` | that's your poison test working — check the DLQ instead |
