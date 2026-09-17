# Project 14 — Real-Time Clickstream Pipeline (AWS)

**Difficulty:** ⭐⭐⭐⭐⭐ · **⏱️ ~60 min** · **Cost:** ~$0.10/mo at lab volume — destroy after

The most "real-time" pattern in AWS: data arrives **continuously** (a Kinesis stream),
a Lambda consumes it in batches, aggregates per-minute stats into S3, and **EventBridge-style
events** (S3 notifications) fan out to SNS the moment each minute's file lands.

## The real-time flow

```
app (curl / kinesis put-record)
   │  a firehose of small events, 24/7
   ▼
Kinesis stream (1 shard = the ordered, durable buffer)
   │  polls in batches of 10
   ▼
Lambda aggregate.py (groups the batch)
   │  one PUT per minute
   ▼
S3 bucket  (minute/2026-01-15T10-42.json)
   │  "ObjectCreated" event
   ▼
SNS topic  (an email/Slack/webhook per fresh file — EventBridge does the same job for any event source)
```

## Concepts practiced
- Kinesis + Lambda event source mapping (continuous consumption) → `../terraform-mastery/01-aws-provider/10-serverless-aws.md`
- Event-driven fan-out (S3 → SNS) → `../terraform-mastery/01-aws-provider/05-s3.md`
- The "stream → buffer → aggregate → store → notify" production shape

## Files in this folder

| File | What it is |
|---|---|
| `variables.tf` | project, region, alert email |
| `main.tf` | stream + consumer + S3 + notification fan-out |
| `lambda/aggregate.py` | turns a batch of clicks into one minute-stat file |
| `outputs.tf` | stream ARN, bucket, topic |
| `terraform.tfvars.example` | sample inputs |

## Run it

```bash
cd project-14-kinesis-eventbridge-realtime
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
```

## Verify it (generate real traffic)

```bash
STREAM=$(terraform output -raw stream_arn | awk -F/ '{print $NF}')
REGION=$(terraform output -raw region)

# 1. push 12 fake user clicks into the stream (this is your "app")
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
  aws kinesis put-record --stream-name "$STREAM" \
    --data "{\"user\":\"u$i\",\"page\":\"/home\",\"action\":\"click\"}" \
    --partition-key "u$i" --region "$REGION"
done

# 2. wait ~15-30s for the Lambda to poll the stream
sleep 30

# 3. the aggregate file appeared in S3 (and an SNS event was fired)
BUCKET=$(terraform output -raw stats_bucket)
aws s3 ls s3://$BUCKET/minute/ --region "$REGION"
aws s3 cp s3://$BUCKET/minute/$(aws s3api list-objects-v2 --bucket $BUCKET --prefix minute/ --region $REGION \
  --query 'Contents[0].Key' --output text | xargs basename) -
```

## Break it (this is the learning)

1. **Backpressure**: push 200 records at once → watch the Lambda make multiple invocations (CloudWatch
   metrics: `Invocations` goes up, `IteratorAge` shows stream lag). This is how streaming absorbs spikes.
2. **Replay**: Kinesis keeps data for 24h (the default retention). Create a SECOND event source mapping
   on the same stream with `starting_position = "TRIM_HORIZON"` → a fresh Lambda gets the whole history
   (this is how you "reprocess" a day of data — add a temp mapping, let it catch up, delete it).
3. **The notification hop**: subscribe the SNS topic to an email, push one more batch, and watch the
   "new minute file" email arrive seconds after the S3 PUT.

## Clean up

```bash
terraform destroy
```

## Common mistakes

| Mistake | Fix |
|---|---|
| No S3 file after pushing records | Lambda consumer lag is normal (~15-30s); also check `starting_position` — `LATEST` only sees records pushed AFTER the mapping was created |
| `ValidationException: Invalid partition key` | `--partition-key` is required for `put-record` |
| 502/`ResourceConflictException` on put-record | shard write limit (1MB/s) — at lab volume this won't happen; in prod add shards or use `put-record-batch` |
| SNS email never arrives | you must confirm the subscription email once (the confirmation link) |
