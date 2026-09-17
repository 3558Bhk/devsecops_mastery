# Azure Service Bus — Interview Questions

> **Cloud:** Azure (Other Services) · **Category:** Integration / Messaging · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~8 min

---

## JSON File Format

Service Bus **message bodies** are typically JSON payloads; the queue/topic resources themselves are ARM JSON (`Microsoft.ServiceBus/namespaces/queues`, `.../topics`).

```json
{
  "orderId": "1001",
  "customerId": "cust-9",
  "amount": 42.5,
  "currency": "USD"
}
```

Queue ARM JSON (key settings):
```json
{
  "type": "Microsoft.ServiceBus/namespaces/queues",
  "apiVersion": "2022-10-01-preview",
  "name": "sbns/orders",
  "properties": {
    "maxDeliveryCount": 10,
    "requiresSession": false,
    "enablePartitioning": true,
    "lockDuration": "PT1M"
  }
}
```

**Key fields (message):** body (JSON) + broker properties `MessageId`, `SessionId`, `TimeToLive`, `Label`. **Key fields (entity):** `maxDeliveryCount` (→ DLQ), `requiresSession` (FIFO), `enablePartitioning`, `lockDuration`.


## Case A — Basic

**A1. What is Azure Service Bus?**
**Answer:** A fully managed **enterprise message broker** supporting **queues** and **topics/subscriptions** — reliable, asynchronous messaging between applications and services.

**A2. What are the messaging entities?**
**Answer:** **Queues** (point-to-point) and **Topics + Subscriptions** (pub/sub fan-out). Topics deliver each message to all subscriptions (with optional filters).

**A3. What is the difference between a queue and a topic?**
**Answer:** A **queue** = one consumer (or competing consumers) processes each message once. A **topic** = a message is copied to **every subscription**, each processed independently — fan-out.

**A4. What is the difference between Service Bus and Azure Storage Queues?**
**Answer:** Service Bus = enterprise features: **sessions, dead-lettering, duplicate detection, transactions, topics/subscriptions, larger messages** (up to 100 MB premium). Storage Queues = simpler, larger scale, cheaper, basic FIFO. Choose Service Bus for complex enterprise messaging; Storage Queues for simple high-volume.

**A5. What is a dead-letter queue (DLQ)?**
**Answer:** A sub-queue where messages go when they can't be delivered/processed (expired, exceeded max delivery attempts, or explicitly dead-lettered) — for inspection/replay.

**A6. What is "peek-lock" vs "receive-and-delete"?**
**Answer:** **Peek-lock** = receive + lock (invisible to others); complete to delete, or abandon to retry (at-least-once). **Receive-and-delete** = receive + delete immediately (at-most-once, no retry). Peek-lock is the safe default.

**A7. What is a session?**
**Answer:** A grouping of related messages with a **Session ID**, processed **in order** by one receiver — for FIFO/stateful workflows.

**A8. What is duplicate detection?**
**Answer:** Service Bus dedupes messages with the same **Message ID** within a window — ensuring exactly-once *send* semantics despite retries.

**A9. What is a message TTL (TimeToLive)?**
**Answer:** How long a message remains in the queue before it **expires** (and optionally dead-letters) — for time-sensitive data.

**A10. What are the Service Bus tiers?**
**Answer:** **Standard** (shared, multi-tenant, pay-per-operation) and **Premium** (dedicated resources, VNet, larger messages, predictable performance, geo-DR).

**A11. What is the maximum message size?**
**Answer:** **Standard: 256 KB**, **Premium: 100 MB** (larger via claim-check pattern with blob storage).

**A12. How do you secure Service Bus?**
**Answer:** **Shared Access Signatures (SAS)** or **Entra ID (RBAC)**, network restrictions (private endpoints/VNet), TLS in transit, and encryption at rest.

**A13. What is the difference between Service Bus and Event Hubs / Event Grid?**
**Answer:** Service Bus = **enterprise messaging** (queues, ordered, competing consumers). Event Hubs = **high-throughput event streaming** (millions/sec, replay). Event Grid = **reactive event routing** (push, pub/sub over events). They compose in event-driven architectures.

**A14. What is a subscription filter/rule?**
**Answer:** A rule on a subscription that filters which messages it receives (by SQL-like properties/correlation filters) — routing subsets of a topic's messages to specific consumers.

**A15. What is a "scheduled message"?**
**Answer:** A message enqueued with a future delivery time (e.g., process later, retry with delay).

---

## Case B — Advanced (Senior)

**B1. Explain at-least-once vs at-most-once delivery in Service Bus and how to achieve exactly-once *processing*.**
**Answer:** **Peek-lock** gives at-least-once (retries can duplicate on abandon/timeout); **receive-and-delete** gives at-most-once (loss on failure). For exactly-once *processing*, use **peek-lock + duplicate detection + idempotent consumers** (dedupe by Message ID/business key). Service Bus's `MessageId`-based dedup handles resends; consumer idempotency handles reprocessing.

**B2. How do sessions provide FIFO and what are the patterns (session-aware processing)?**
**Answer:** Messages with the same **Session ID** are locked to one receiver and delivered **in order**. Use for ordered workflows (e.g., per-account events). Patterns: **session-enabled queues** (FIFO per session), **session state** (persist processing state in the session), and **parallel processing across sessions** (each session handled by a different receiver — high throughput while keeping per-session order).

**B3. How does the competing-consumers pattern work, and how do you scale processing?**
**Answer:** Multiple consumers read the same queue; Service Bus **locks each message to one consumer** (peek-lock) — work is distributed. Scale by **adding consumers** (and enable **partitioning**/Premium for throughput). Ordering across all messages isn't guaranteed in this pattern (use sessions for that).

**B4. What is the dead-lettering flow, and how do you handle poison messages systematically?**
**Answer:** A message dead-letters after **max delivery count** (default 10), on **TTL expiry**, or explicitly. To handle poison messages: inspect the DLQ, fix the consumer, then **resubmit** (copy DLQ → main queue) via tooling/automation. Alert on DLQ depth (Azure Monitor) to catch issues early.

**B5. How does duplicate detection work under the hood, and what are its limits?**
**Answer:** Service Bus tracks **Message IDs** (or a property you set as the dedup key) for a **configurable window** (default 10 min, max 7 days); a duplicate within the window is dropped. Limits: the window is finite, and it only dedupes by the key — design the key from the business operation ID. Works with **sessions** too.

**B6. How do you build a fan-out + filtered pipeline (topics/subscriptions + rules)?**
**Answer:** Publish to a **topic**; each **subscription** declares a **rule** (SQL filter on properties, e.g., `Region = 'EU'`). Each subscriber only receives matching messages — enabling a single publish to feed many services, each getting only its relevant events (the core pub/sub decoupling pattern).

**B7. What is the claim-check pattern and when do you use it (large messages)?**
**Answer:** For messages > the size limit, store the payload in **blob storage** and send a **small message with the blob reference**. The consumer fetches the blob. Use for large files/payloads while keeping messaging cheap and within limits.

**B8. How do you make Service Bus highly available and disaster-recoverable (Premium geo-DR)?**
**Answer:** **Premium geo-DR** pairs a primary namespace with a **secondary region** (active-passive): metadata + messages replicate; on failover, the alias switches to the secondary. **Availability zones** protect within a region. Design consumers to handle the alias and failover; test RTO.

**B9. What are the throttling/performance considerations (premium, partitioning, batching)?**
**Answer:** Standard tier shares resources (can throttle); **Premium** gives dedicated capacity. Use **batching** (send/receive batches), **partitioned entities** (16 partitions for higher throughput), and tune **prefetch** to balance latency vs message locks. Monitor **throttled requests** and **queue depth**.

**B10. How do you monitor and alert on Service Bus (metrics, logs)?**
**Answer:** Metrics: **Active/Deadletter message count**, **Queue/Topic depth**, **ThrottledRequests**, **ServerErrors**, **Incoming/Outgoing messages**. Enable **diagnostics** to Log Analytics; alert on DLQ depth, throttling, and idle consumers (age of oldest message). Route to Sentinel for security monitoring.

**B11. How does Service Bus integrate with Logic Apps/Functions/Event Grid?**
**Answer:** **Logic Apps/Functions** have native Service Bus triggers (peek-lock sessions/batches); **Event Grid** can fan out Service Bus events (or bridge to other services). Common pattern: producer → Service Bus → Function/Logic App consumer, with Event Grid for operational notifications.

**B12. How do you implement retries and backoff in consumers, and avoid message lock loss?**
**Answer:** Use **peek-lock with auto-renew (maxAutoLockRenewalDuration)** so long processing doesn't lose the lock; on failure **abandon** (retry) or **dead-letter** after N attempts; implement **exponential backoff** for transient errors (or let the SDK's retry policy handle). Match the lock duration to processing time to avoid duplicate delivery.

---

## Case C — Scenario

**C1. Scenario:** An order service must handle Black Friday spikes without the web tier blocking.
**Question:** Design with Service Bus.
**Answer:** Web tier enqueues **order messages** to a **queue** (fast, async) and returns "received"; order workers (Functions/containers) process via **peek-lock** with retries and **idempotency**; **autoscale** workers by **queue depth**; failed messages go to the **DLQ** for inspection. The queue absorbs the burst, decoupling producer from consumer.

**C2. Scenario:** Messages keep re-appearing and then land in the DLQ; users see duplicate charges.
**Question:** Diagnose and fix.
**Answer:** Likely a **poison message** (always fails) or the **lock expires** during long processing → redelivery → duplicates. Fix: increase the **lock duration / auto-renew**, make the consumer **idempotent** (dedupe by order ID), set a sensible **max delivery count**, and inspect the DLQ to find/fix the actual bad payload. 

**C3. Scenario:** Per-user events must be processed in the exact order they occurred, but you want high throughput overall.
**Question:** Which feature?
**Answer:** **Sessions** — set **Session ID = user ID**; messages per session are delivered **in order to one receiver**, while different sessions process **in parallel** across consumers. This gives per-user FIFO with overall parallelism. (Alternatively use a partitioned queue + session state.)

**C4. Scenario:** A payment gateway webhook might deliver the same event twice (network retries).
**Question:** Prevent double-processing.
**Answer:** Enable **duplicate detection** with the **Message ID = the gateway's event/transaction ID** (within the dedup window), **and** make the consumer **idempotent** (check/insert a processed-events table, conditional write). Both layers ensure the payment isn't applied twice.

**C5. Scenario:** A message payload is 50 MB (attachments); the queue rejects it.
**Question:** How do you handle it?
**Answer:** Use the **claim-check pattern**: store the 50 MB attachment in **Blob Storage**, enqueue a small message containing the **blob reference + metadata**, and have the consumer download the blob. (Or upgrade to Premium for 100 MB messages, but claim-check is the scalable pattern.)

**C6. Scenario:** You need a region-level DR story: if the primary region fails, messaging must fail over to a secondary region.
**Question:** Design it.
**Answer:** Use **Premium tier + geo-DR**: pair the namespace with a **secondary region**, so messages + metadata replicate; apps use the **alias** so failover (manual/scripted) re-points them to the secondary automatically. Combine with **availability zones** in the primary for local HA, and test the failover RTO/RPO.
