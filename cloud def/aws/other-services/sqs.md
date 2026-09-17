# Amazon SQS — Interview Questions

> **Cloud:** AWS (Other Services) · **Category:** Integration / Messaging · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~8 min

---

## JSON File Format

SQS messages are sent/received as JSON (via `send-message` / `receive-message`). The body is usually a JSON payload, with **message attributes** as structured metadata.

```json
{
  "MessageBody": "{"orderId": "1001", "amount": 42.5}",
  "MessageAttributes": {
    "eventType": { "DataType": "String", "StringValue": "order-created" }
  },
  "DelaySeconds": 0,
  "MessageGroupId": "user-123",
  "MessageDeduplicationId": "ord-1001"
}
```

**Key fields:** `MessageBody` (often JSON) · `MessageAttributes` (typed metadata) · `DelaySeconds` · FIFO-only: `MessageGroupId` (ordering) + `MessageDeduplicationId` (exactly-once). Received messages add `ReceiptHandle`, `MessageId`, `ApproximateReceiveCount`.


## Case A — Basic

**A1. What is Amazon SQS?**
**Answer:** A fully managed **message queue** service that decouples producers from consumers — producers send messages to a queue; consumers poll and process them asynchronously.

**A2. What are the two queue types?**
**Answer:** **Standard** (unlimited throughput, at-least-once delivery, best-effort ordering) and **FIFO** (exactly-once processing, strict ordering, limited throughput ~300 msg/s or higher with batching/high-throughput mode).

**A3. What is the difference between SQS and SNS?**
**Answer:** SQS = **queue** (point-to-point, one consumer processes a message, retained until consumed). SNS = **pub/sub** (fan-out to many subscribers). They're often combined: SNS → multiple SQS queues.

**A4. What is a visibility timeout?**
**Answer:** The period a message is hidden from other consumers after being received, giving the consumer time to process it. If not deleted before expiry, it becomes visible again (re-delivery).

**A5. What is message retention?**
**Answer:** How long a message stays in the queue if not consumed (default 4 days, range 1 min–14 days).

**A6. What is a dead-letter queue (DLQ)?**
**Answer:** A queue that receives messages that failed processing after a configured number of receive attempts (via the `maxReceiveCount` redrive policy) — for isolating and inspecting poison messages.

**A7. What is long polling vs short polling?**
**Answer:** **Long polling** (`WaitTimeSeconds` > 0) waits for a message before returning, reducing empty responses and cost. **Short polling** returns immediately (may return empty). Long polling is the default/recommended.

**A8. What are message attributes?**
**Answer:** Structured metadata (name/type/value) attached to a message, used to route/process messages without reading the body.

**A9. What is the maximum message size?**
**Answer:** **256 KB**. For larger payloads, store the data in **S3** and send the S3 key in the message (the S3 pointer pattern).

**A10. What does "at-least-once" delivery mean?**
**Answer:** A standard-queue message may be delivered **more than once** — consumers must be **idempotent**.

**A11. How do you secure SQS?**
**Answer:** IAM policies (who can send/receive), queue policies (resource-based, cross-account access), **SSE** (SQS-managed or KMS) encryption at rest, and VPC endpoints for private access.

**A12. What is message batching?**
**Answer:** Send/receive/delete up to 10 messages (or 256 KB) in one API call to reduce cost and improve throughput.

**A13. What is a delay queue?**
**Answer:** Delays the delivery of new messages by a configured number of seconds (0–900).

**A14. What is FIFO message group ID and deduplication ID?**
**Answer:** Group ID groups ordered messages; messages in the same group are processed in order. **Deduplication ID** enables exactly-once processing within a 5-minute window.

**A15. What is SQS's pricing based on?**
**Answer:** Number of **requests** (each 64 KB chunk of a request is billable) — no charge for idle queues or stored data (within limits).

---

## Case B — Advanced (Senior)

**B1. How do you build a resilient producer-consumer pipeline with SQS (decoupling, retries, DLQ, idempotency)?**
**Answer:** Producers publish to SQS (with retries). Consumers poll (long polling), process idempotently, and delete on success. Failed messages exceed `maxReceiveCount` → **DLQ** for inspection/replay. Visibility timeout covers processing time; alarms on `ApproximateAgeOfOldestMessage` and DLQ depth signal issues. This pattern absorbs bursts and failures gracefully.

**B2. Explain the DLQ redrive policy and how you analyze/replay poison messages.**
**Answer:** The redrive policy sets `maxReceiveCount`; messages exceeding it move to the DLQ. To fix: inspect DLQ messages (peek), fix the consumer bug, then **redrive** them back to the source queue (manual or automated redrive). Keep the DLQ's retention long and alarm on its depth.

**B3. When do you choose Standard vs FIFO, and what are FIFO's throughput limits/workarounds?**
**Answer:** Standard = max throughput, at-least-once, no ordering — for most workloads. FIFO = exactly-once + strict order — for financial/transactional or order-sensitive flows. FIFO throughput is ~300 msg/s (unbatched); use **batching** (up to 10 messages) and **high-throughput FIFO** mode (up to 30,000 msg/s with batching) to scale. Ordering is per **message group**.

**B4. How does long polling work and how do you tune it to reduce cost and empty responses?**
**Answer:** Set `WaitTimeSeconds` (up to 20s) on ReceiveMessage (or queue-level ReceiveMessageWaitTimeSeconds). Consumers wait for messages, cutting empty polls (and thus billable requests) dramatically. Use 20s with a fleet of consumers for low-latency + low-cost.

**B5. How does SQS + Lambda (event source mapping) work, and how do you avoid the "message stuck" problem?**
**Answer:** Lambda polls the queue and invokes with batches; on success, messages are deleted; on failure, they're returned (visibility) and retried. Set the queue's **visibility timeout > (function timeout × batch size)** so messages aren't re-delivered while still processing, and use **partial batch responses** to retry only failed messages.

**B6. How do you fan out a message to many consumers (SNS + SQS pattern)?**
**Answer:** Publish once to an **SNS topic**; subscribe multiple **SQS queues** (one per consumer/service). Each consumer gets its own copy and processes independently at its own pace — the canonical event fan-out architecture.

**B7. What are the delivery semantics and how do you guarantee exactly-once *processing* (if not delivery)?**
**Answer:** Standard queues = at-least-once delivery, so you can't guarantee exactly-once delivery — but you can guarantee exactly-once **processing** via **idempotent consumers** (dedupe by a business key stored in DynamoDB, conditional writes). FIFO queues provide exactly-once processing natively within the deduplication window.

**B8. How do you handle large messages (>256 KB) with the S3 extended client pattern?**
**Answer:** Store the payload in **S3**, send a message containing the S3 key + metadata. The consumer fetches the object from S3. Handle cleanup with lifecycle policies; use SSE-KMS for encryption. (For Java, the **Amazon SQS Extended Client** library automates this.)

**B9. How does encryption work in SQS (SSE vs KMS) and what are the considerations?**
**Answer:** **SSE-SQS** = SQS-managed keys (simple, free). **SSE-KMS** = customer/AWS-managed KMS keys (control, audit, but KMS API cost and throttling considerations). Encrypt at rest; use **VPC endpoints** to keep traffic off the internet; enforce least-privilege IAM/queue policies.

**B10. What metrics and alarms do you set for SQS in production?**
**Answer:** Alarm on **ApproximateAgeOfOldestMessage** (backlog/latency), **ApproximateNumberOfMessagesVisible** (queue depth), **NumberOfMessagesReceived/Sent**, **DLQ depth**, and consumer-side errors. These catch stuck consumers, poison messages, and throughput anomalies.

**B11. How does SQS compare to Kinesis and EventBridge for streaming/eventing?**
**Answer:** SQS = decoupled message queue (pull, at-least-once, no replay, per-message ack). **Kinesis** = streaming with ordered, replayable records (pull by many consumers, retention window). **EventBridge** = routing/bus for events with pattern matching (push). Choose SQS for work queues, Kinesis for ordered streaming/replay, EventBridge for event-driven fan-out with rules.

**B12. What are the cost/performance optimizations for SQS at high volume?**
**Answer:** Use **long polling**, **batching** (send/receive/delete 10 at a time), appropriate retention (avoid 14-day default cost), right-sized visibility timeouts (avoid excessive re-delivery), and consider FIFO high-throughput mode if ordering is needed at scale. Monitor request counts via CloudWatch/Cost Explorer.

---

## Case C — Scenario

**C1. Scenario:** An order service can't handle Black Friday traffic spikes; the web tier keeps timing out calling it.
**Question:** Redesign with SQS.
**Expected answer:** Insert an **SQS queue** between the web tier and order service. The web tier enqueues orders (fast, decoupled) and returns "order received"; order workers poll the queue and process at their own pace. The queue absorbs the burst, and the workers scale with the backlog. Add a DLQ for failures and idempotency for retries.

**C2. Scenario:** A consumer crashes mid-processing; messages are re-delivered and a payment is charged twice.
**Question:** Diagnose and fix.
**Expected answer:** Standard queues deliver **at-least-once**, so re-delivery after a crash (visibility timeout expiry) causes duplicates — the consumer wasn't idempotent. Fix: make processing idempotent (idempotency key + DynamoDB conditional check) or switch to **FIFO** with deduplication IDs for exactly-once semantics. Keep visibility timeout long enough for processing.

**C3. Scenario:** Messages keep appearing in the DLQ every day; ops manually inspects them one by one.
**Question:** Improve the operational design.
**Expected answer:** (1) Alarm on DLQ depth so failures page someone. (2) Standardize message format/attributes for diagnosis. (3) Build an **automated redrive** workflow (move DLQ → source after fix) and a replay tool. (4) Add retry + backoff in the consumer and fix the root bug per poison-message type. (5) Keep DLQ retention long for forensics.

**C4. Scenario:** A FIFO queue needs to process 5,000 messages/second with per-user ordering.
**Question:** How do you meet the throughput while keeping order?
**Answer:** Use **high-throughput FIFO mode** with **batching** (10 messages per send/receive) — which can reach tens of thousands of msg/s. Use **MessageGroupId = user ID** so each user's messages are ordered while different groups process in parallel. Ensure the consumer batch size and visibility timeouts are tuned.

**C5. Scenario:** Cross-account: Account A's producer must send messages to a queue in Account B, without sharing credentials.
**Question:** Design it.
**Answer:** Attach a **queue policy** in Account B granting Account A's **IAM role ARN** (or account) `sqs:SendMessage` on the queue; in Account A, attach an IAM policy allowing `sqs:SendMessage` on Account B's queue ARN. Both policies must allow. For encryption, share the KMS key if SSE-KMS is used. Producers use the queue URL/ARN directly.

**C6. Scenario:** You must process a stream of events in strict order, and later consumers need to **replay** the last 24 hours of events.
**Question:** SQS or Kinesis? Justify.
**Answer:** **Kinesis** — SQS is a queue (message deleted after consumption, no replay). Kinesis retains records (24h+ window), supports **ordered processing per shard**, and lets multiple consumers **replay** from any point. Use SQS only if you don't need ordering/replay across consumers.
