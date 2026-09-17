# Project 10 — Messaging: Service Bus (Topic/Subscription + Queue/DLQ) (Azure)

**Difficulty:** ⭐⭐⭐ · **⏱️ ~40 min** · **Cost:** ~$0.10–0.25/mo (Basic namespace — destroy after)

The Azure flavor of project 10 (AWS SNS/SQS): a **Service Bus namespace** with a *topic*
(pub/sub fan-out) and a *queue* (work buffer with a dead-letter path).

## Concepts practiced
- Service Bus namespace / topic / subscription / queue → `../terraform-mastery/02-azure-provider/08-serverless-functions-and-app-service.md`
- `max_delivery_count` (poison handling) + dead-lettering on expiry
- Namespace **authorization rules** (who may send/receive)

## The flow

```
producer ──► topic "orders"
                ├─► subscription "billing"    (consumed by the billing worker)
                └─► subscription "inventory"  (consumed by the inventory worker)

producer ──► queue "archive"  ──(3 failed deliveries)──► $DeadLetterQueue
                     (messages that expire while waiting also → DLQ)
```

## Files in this folder

| File | What it is |
|---|---|
| `variables.tf` | project, location |
| `main.tf` | namespace + rules + topic + 2 subscriptions + queue |
| `outputs.tf` | namespace host, topic/queue names |
| `terraform.tfvars.example` | sample inputs |

## Run it

```bash
cd project-10-service-bus-and-queues
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
```

## Verify it

```bash
HOST=$(terraform output -raw namespace_host)   # e.g. obs-sb-2026.servicebus.windows.net

# 1. everything exists
az servicebus topic list --resource-group $(terraform output -raw rg_name) -o table
az servicebus subscription list --topic-name orders --resource-group $(terraform output -raw rg_name) -o table

# 2. send a test message to the topic (needs a sender rule; easiest via portal:
#    Service Bus namespace → Topics/queues → orders → Send message → {"order_id":"1"})
# 3. peek (don't consume) at a subscription:
#    Portal → subscriptions → billing → peek messages → you'll see the message
#    (each subscription gets its OWN copy — that's pub/sub)
```

## Break it (this is the learning)

1. Add a third subscription (`audit`) → `plan` → one new resource. All consumers get the message.
2. Lower `max_delivery_count` to 1 → `plan` → in-place on the subscription. Now one failed
   delivery = straight to the DLQ.
3. Change the queue's `max_delivery_count = 5` → `10` → `plan` → in-place.
4. Send 3+ messages to the queue, "complete" none (let them be received-and-abandoned in the
   portal) → watch them land in the queue's `$DeadLetterQueue`.

## Clean up

```bash
terraform destroy
```

## Common mistakes

| Mistake | Fix |
|---|---|
| `ServiceBusAuthorizationRuleNotFound` | the authorization rule (Send/Listen) must exist before clients can connect — check `az servicebus authorization-rule list` |
| Message not visible in a subscription | peek the **subscription**, not the topic (the topic has no messages — subscriptions do) |
| Namespace creation takes a while | it's normal (~2–3 min); don't re-run apply in a panic |
