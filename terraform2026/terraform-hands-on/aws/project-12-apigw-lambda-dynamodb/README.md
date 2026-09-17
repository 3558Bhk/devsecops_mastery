# Project 12 — Real-Time Order API (AWS)

**Difficulty:** ⭐⭐⭐⭐ · **⏱️ ~60 min** · **Cost:** ~$0 (all serverless + free tier) — destroy after

The classic serverless backend: a public REST API where customers **POST orders in real time**,
a Lambda writes them to DynamoDB, and GET reads them back. Four services working together — no servers.

## The real-time flow

```
customer curl
   │  POST /orders  {"order_id":"o1","item":"laptop","amount":1499}
   ▼
API Gateway (public REST, CORS)
   │  forwards the event (AWS_PROXY)
   ▼
Lambda orders.py (picks POST or GET from the event)
   │
   ▼
DynamoDB orders  (GSI on status, so you can query "all new orders")
```

## Concepts practiced
- API Gateway REST API + CORS + deployments → `../terraform-mastery/01-aws-provider/10-serverless-aws.md`
- DynamoDB GSI (another view of the same data) → `../terraform-mastery/01-aws-provider/09-dynamodb.md`
- Least-privilege Lambda role → `../terraform-mastery/01-aws-provider/07-iam.md`

## Files in this folder

| File | What it is |
|---|---|
| `variables.tf` | project, region |
| `main.tf` | table + IAM + Lambda + the whole REST API |
| `api/orders.py` | the one function that serves POST and GET |
| `outputs.tf` | the public API URL + table name |
| `terraform.tfvars.example` | sample inputs |

## Run it

```bash
cd project-12-apigw-lambda-dynamodb
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
```

## Verify it (the fun part)

```bash
URL=$(terraform output -raw invoke_url)

# 1. create three orders (this is the real-time write path)
curl -s -X POST "$URL" -H 'Content-Type: application/json' \
  -d '{"order_id":"o1","item":"laptop","amount":1499}'
curl -s -X POST "$URL" -H 'Content-Type: application/json' \
  -d '{"order_id":"o2","item":"mouse","amount":25}'
curl -s -X POST "$URL" -H 'Content-Type: application/json' \
  -d '{"order_id":"o3","item":"monitor","amount":349}'

# 2. read them back (the read path)
curl -s "$URL" | python3 -m json.tool

# 3. CORS preflight works (browsers send this before the real call)
curl -s -X OPTIONS "$URL" -o /dev/null -w '%{http_code}\n'   # expect 200
```

## Break it (this is the learning)

1. Add a field to the POST body (e.g. `"customer":"anna"`) → change nothing else → `apply` (no change!
   the table is schemaless) → POST the new field → GET shows it. **DynamoDB has no schema — that's the point.**
2. Change the stage: `stage_name = "dev"` → `"prod"` in `main.tf` → `plan` → a new stage is created.
   The same API now serves two URLs. (Blue/green-style thinking.)
3. Flip the GSI's `projection_type = "ALL"` → `"KEYS_ONLY"` → `plan` → in-place → GET still works
   (you just lose attributes in index-only queries).

## Clean up

```bash
terraform destroy
```

## Common mistakes

| Mistake | Fix |
|---|---|
| `403` from the API | the Lambda role is missing DynamoDB access — check the inline policy's table ARN |
| `Invalid signature` on POST | you're hitting the wrong URL (must end in `/orders` and the region in the URL must match) |
| API returns 502 | the Lambda is crashing — check CloudWatch Logs for the function `orders` (usually a bad JSON body: `order_id` is required) |
| `BucketAlreadyExists`-style name clash on the table | DynamoDB table names are unique per region — change `project` |
