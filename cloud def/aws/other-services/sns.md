# Amazon SNS — Interview Questions

> **Cloud:** AWS (Other Services) · **Category:** Integration / Messaging · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~8 min

---

## JSON File Format

SNS delivers a **notification envelope** JSON to subscribers (Lambda, HTTP, SQS); the actual payload sits in the `Message` field.

```json
{
  "Type": "Notification",
  "MessageId": "abc-123-xyz",
  "TopicArn": "arn:aws:sns:us-east-1:111122223333:orders",
  "Subject": "New order",
  "Message": "{"orderId": "1001"}",
  "Timestamp": "2026-09-13T10:00:00Z",
  "MessageAttributes": {
    "eventType": { "Type": "String", "Value": "order-created" }
  }
}
```

**Key fields:** `Message` (the payload — typically JSON) · `MessageAttributes` (used by **subscription filter policies**) · `TopicArn` / `Subject`. Filter policies are also JSON (`{"eventType": ["order-created"]}`).


## Case A — Basic

**A1. What is Amazon SNS?**
**Answer:** A fully managed **publish/subscribe (pub/sub)** messaging service: a publisher sends a message to a **topic**, and all **subscribers** receive a copy — used for fan-out, notifications, and event distribution.

**A2. What is a topic?**
**Answer:** A communication channel (identified by an ARN) to which publishers send messages and subscribers subscribe. Messages are delivered to all subscribers.

**A3. What can subscribe to an SNS topic?**
**Answer:** SQS queues, Lambda functions, HTTP/HTTPS endpoints, email, SMS, and **mobile push notifications** (APNs/FCM/GCM, via platform endpoints).

**A4. What is the difference between SNS and SQS?**
**Answer:** SNS = pub/sub **push** (fan-out to many, message not retained for later). SQS = **pull** queue (point-to-point, retained until consumed). Common pattern: SNS fan-out → multiple SQS queues.

**A5. What are the two topic types?**
**Answer:** **Standard** (high throughput, best-effort ordering, at-least-once) and **FIFO** (strict ordering, exactly-once, limited throughput).

**A6. What is a message attribute?**
**Answer:** Metadata on a message that subscribers can use to filter messages (via subscription filter policies) without reading the body.

**A7. What is a filter policy?**
**Answer:** A JSON policy on a **subscription** that controls which messages are delivered to that subscriber based on message attributes (e.g., only `eventType=order_created`).

**A8. What is a delivery retry policy?**
**Answer:** For HTTP/S endpoints, SNS retries failed deliveries with backoff and moves to a **DLQ** after exhausting retries.

**A9. Does SNS retain messages for later retrieval?**
**Answer:** No (for most protocols). SNS pushes once; if no subscriber is listening, the message is lost (unlike SQS). (FIFO topics can archive/replay with SQS subscriptions.)

**A10. What is mobile push in SNS?**
**Answer:** SNS can send push notifications to mobile apps via **platform applications** (APNs for iOS, FCM for Android), using device tokens and platform endpoints.

**A11. What is an SNS dead-letter queue?**
**Answer:** A queue (or Lambda) that receives messages whose delivery failed after retries (for HTTP/S and other async endpoints) — for troubleshooting.

**A12. How do you secure SNS?**
**Answer:** Topic policies (resource-based, cross-account), IAM policies, SSE encryption (KMS), VPC endpoints, and HTTPS endpoints for delivery.

**A13. What is the maximum message size?**
**Answer:** **256 KB**. Larger payloads use the S3-pointer pattern (publish an S3 URL).

**A14. What is message delivery status logging?**
**Answer:** CloudWatch logging per message/per subscriber showing delivery success/failure — key for debugging push/email delivery.

**A15. What's a common SNS + SQS + Lambda fan-out use case?**
**Answer:** A single event (e.g., "order placed") published to an SNS topic fans out to multiple SQS queues/Lambdas (billing, inventory, notification) — each consumer processes independently.

---

## Case B — Advanced (Senior)

**B1. Explain the SNS fan-out pattern and why SNS→SQS is preferred over direct SQS.**
**Answer:** SNS decouples the producer from the number/identity of consumers: one `Publish` reaches N subscribers, and adding a consumer is just a new subscription (no producer change). SNS→SQS gives each consumer a durable, independently-processed copy (queue semantics) — the standard for multi-service event distribution.

**B2. How do subscription filter policies work, and how do you design efficient topic routing?**
**Answer:** Each subscription declares a filter (attribute names/values, e.g., `{"eventType": ["created","updated"]}`). SNS evaluates attributes and delivers only matches — reducing noise and Lambda invocations. Design: use consistent attribute schemas and one topic per domain, with filters instead of many topics.

**B3. What is message delivery retry + DLQ for HTTP endpoints, and how do you tune it?**
**Answer:** SNS retries failed HTTP deliveries (default 3 tries, with backoff) per the delivery policy, then sends to the subscription's **DLQ** (SQS) if configured. Tune retries/backoff for transient errors, require 2xx, and alarm on the DLQ. Use delivery status logging to see per-message outcomes.

**B4. How does FIFO SNS work, and how do you preserve ordering end-to-end with SQS?**
**Answer:** FIFO topics require **MessageGroupId** for ordering and **MessageDeduplicationId** for exactly-once. Subscribe FIFO **SQS** queues; the group ID propagates to the queue, preserving per-group order. Throughput is limited (~300 msg/s, more with batching) — use only when ordering is essential.

**B5. How do you handle cross-account SNS publishing securely?**
**Answer:** The topic owner adds a **topic policy** allowing the other account (or its IAM role) `sns:Publish`. The publisher's IAM policy must also allow `sns:Publish` on the topic ARN. Both sides must permit. For KMS-encrypted topics, share the KMS key too.

**B6. Compare SNS, EventBridge, and SQS for event-driven architectures.**
**Answer:** SNS = simple pub/sub fan-out (many targets, limited filtering). **EventBridge** = richer event bus with pattern matching, schema registry, cross-account/SaaS integration, replay — the modern default for event routing. **SQS** = durable pull queue for workloads. Choose EventBridge for rule-based routing; SNS for simple fan-out/alerts; SQS for work queues.

**B7. How do you build reliable notifications (SMS/email/push) and handle bounces/opt-outs?**
**Answer:** Use SNS with the appropriate protocol; for email, verify identities/domains (SES can be used too). Monitor **delivery status logging**, handle SMS opt-outs (SNS honors STOP), and route failures to a DLQ. For critical alerts, use multiple channels (SNS → email + Slack webhook + PagerDuty).

**B8. What are SNS's throughput/limits and how do you scale topic-based architectures?**
**Answer:** Standard topics = very high throughput (no hard per-topic limit); FIFO = ~300 msg/s (higher with batching). Limits exist for subscriptions per topic, filter policy size, and message size (256 KB). Scale by sharding topics or using EventBridge when you hit filter/complexity limits.

**B9. How does SNS integrate with Lambda and what are the retry semantics?**
**Answer:** SNS invokes Lambda **asynchronously**; Lambda's own retry (2 retries) applies, and failures can go to the function's destination/DLQ. SNS also supports a subscription-level DLQ for delivery failures. For guaranteed processing with durability, subscribe an SQS queue and have Lambda poll it instead.

**B10. How do you use SNS for infra/ops alerting (CloudWatch alarms → SNS → on-call)?**
**Answer:** CloudWatch alarms publish to an SNS topic; subscribers include email, SMS, Lambda (→ Slack/Teams), and HTTP (→ PagerDuty/Opsgenie). Use filter policies to route severity-based alerts to different channels, and delivery status + DLQ to ensure alerts are never silently dropped.

**B11. What is the SNS message signature verification pattern (for HTTP endpoints)?**
**Answer:** SNS signs HTTP/S delivery requests (via `x-amz-sns-message-type` and Signature fields); subscribers can **verify the signature** using the SNS public certificate to confirm the message truly came from SNS — preventing spoofed webhooks.

**B12. How do you cost-optimize and monitor SNS at scale?**
**Answer:** Cost is per publish + per delivery (and per mobile push/email). Optimize with **filter policies** (fewer deliveries), batched publishes (`PublishBatch`), and right-sizing. Monitor via CloudWatch (NumberOfMessagesPublished, NumberOfNotificationsDelivered/Failed) and delivery status logging.

---

## Case C — Scenario

**C1. Scenario:** A "user registered" event must trigger: a welcome email, an analytics Lambda, and a CRM update — with each service able to fail independently.
**Question:** Design the messaging.
**Expected answer:** Publish to an **SNS topic**; subscribe (1) the email service (SES), (2) the analytics **Lambda**, (3) an **SQS queue** for the CRM consumer. Each processes independently; failed consumers use their own DLQ/retry without blocking others. Add filter policies if some consumers only want subsets.

**C2. Scenario:** A payment gateway webhook returns 500 occasionally; some payment notifications are being lost.
**Question:** How does SNS delivery retry + DLQ prevent loss, and how do you configure it?
**Expected answer:** Subscribe the gateway's **HTTPS endpoint** and configure a **delivery retry policy** (e.g., 5 retries with backoff) + a **DLQ (SQS)** for exhausted attempts. SNS will retry transient 500s and, on permanent failure, preserve the message in the DLQ for replay. Enable **delivery status logging** to monitor.

**C3. Scenario:** You need strict ordering of "account transaction" events per account, fan-out to two services.
**Question:** Which SNS type and settings?
**Expected answer:** Use a **FIFO topic** with **MessageGroupId = account ID** (per-account ordering) and **MessageDeduplicationId** for exactly-once. Subscribe two **FIFO SQS queues** (one per service) so the group ordering propagates end-to-end. Accept the FIFO throughput limits (batch for scale).

**C4. Scenario:** Mobile push notifications to 500k devices must be sent efficiently with analytics on failures.
**Question:** Design with SNS.
**Expected answer:** Create a **platform application** per OS (APNs/FCM), register device tokens as **platform endpoints** (maybe grouped in topics for bulk), publish notifications to endpoints/topics, and enable **delivery status logging** to CloudWatch to track delivered/failed per endpoint (e.g., invalid tokens to prune).

**C5. Scenario:** Your team publishes directly to 15 SQS queues from the producer; adding a new consumer requires changing producer code.
**Question:** Refactor with SNS and justify.
**Answer:** Create an **SNS topic** as the single publish point and subscribe the 15 SQS queues (and any future consumers). The producer publishes once; adding a consumer = new subscription, **no producer change**. Use **filter policies** so each queue only receives relevant events. This is the canonical fan-out decoupling refactor.

**C6. Scenario:** Alerts from CloudWatch stopped reaching the on-call Slack channel silently.
**Question:** Diagnose with SNS tooling.
**Expected answer:** Check the alarm → SNS topic → Lambda (Slack) path: verify the topic's subscription (Lambda) is confirmed, check **delivery status logging** and the Lambda's invocation/error metrics, and inspect the subscription **DLQ** (if configured) for failed deliveries. Add a DLQ + CloudWatch alarm on delivery failures so silent drops page the team next time.
