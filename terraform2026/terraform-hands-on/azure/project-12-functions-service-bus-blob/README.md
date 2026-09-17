# Project 12 — Order Processing Pipeline (Azure)

**Difficulty:** ⭐⭐⭐⭐ · **⏱️ ~60 min** · **Cost:** ~$0 (consumption plan + free-tier volumes) — destroy after

The Azure version of "decoupled real-time processing": an **order service publishes** to a Service Bus
topic, a **Function** consumes it (via a subscription), processes it, and **publishes the result** to a
queue — the producer never knows (or cares) what consumes its events.

## The real-time flow

```
order service (az servicebus topic send-topic-message)
   │  publish "order.created"
   ▼
Service Bus topic  orders
   │  fan-out (each subscription gets its own copy)
   ▼
subscription  processing  →  Function App (service_bus_trigger)
   │  validates + annotates the order
   ▼
Service Bus queue  processed  (your next consumer / human / dashboard)
```

## Concepts practiced
- Azure Functions (consumption plan, zip deploy, bindings) → `../terraform-mastery/02-azure-provider/05-functions.md`
- Service Bus topic/subscription/queue (the same model as AWS SNS/SQS) → `../terraform-mastery/02-azure-provider/09-messaging.md`
- Deployment as code (`zip_deploy_file`)

## Files in this folder

| File | What it is |
|---|---|
| `variables.tf` | project, location |
| `main.tf` | storage + Service Bus + consumption plan + function app |
| `function/main.py` | the trigger function (topic subscription in → processed queue out) |
| `outputs.tf` | namespace endpoint, topic, function host |
| `terraform.tfvars.example` | sample inputs |

## Run it

```bash
cd project-12-functions-service-bus-blob
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
```

## Verify it (publish an order, watch it come out)

```bash
RG=$(terraform output -raw rg_name)

# 1. publish an order to the TOPIC (this is your "order service")
az servicebus topic send-topic-message \
  --resource-group $RG \
  --namespace-name $(terraform output -raw namespace_name) \
  --name orders \
  --message-body '{"order_id":"az-1","item":"laptop","amount":1499}'

# 2. wait ~30-60s (cold start + processing)

# 3. the processed order is in the QUEUE — receive it (receiving deletes it)
az servicebus queue receive \
  --resource-group $RG \
  --namespace-name $(terraform output -raw namespace_name) \
  --name processed

# 4. the function's own logs (what the function did, step by step)
az functionapp log storage show -g $RG -n $(terraform output -raw function_name)   # if you want the storage logs
```

## Break it (this is the learning)

1. **Poison message**: publish `{"order_id":"az-2"}` with `--message-body 'not-json'` → the function
   raises → after 3 failed deliveries (`max_delivery_count = 3`) the message lands in the
   **dead-letter queue** of the subscription. Find it:
   `az servicebus queue receive --name "$Subscription:processin…ault"` (naming: the subscription's DLQ).
2. **Fan-out**: add a second subscription (copy the `processing` subscription block, new name) →
   publish once → the function consumes it again (the topic gave every subscription its own copy).
   This is exactly AWS SNS fan-out.
3. **Change the function code**: add a line to `function/main.py` → `apply` → the zip re-deploys
   (`zip_deploy_file` changed) → publish again → the new log line appears. Code deploys are just applies.

## Clean up

```bash
terraform destroy
```

## Common mistakes

| Mistake | Fix |
|---|---|
| Message never reaches the queue | the function's connection string is in `app_settings` — check it matches the namespace (`az functionapp show` → app settings); also check the function's logs |
| `401` / auth errors in function logs | the Service Bus connection string is missing or the subscription name is wrong in the decorator |
| Function app stuck "Creating" | consumption plans can take a few minutes; also the name must be globally unique (function hostnames are) |
| `az functionapp log ...` empty | logs go to the function's storage account file share — wait for the flush, or use App Insights (next project) |
