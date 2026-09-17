# Terraform Messaging — SQS, SNS, EventBridge (AWS) — Interview Questions

> **Cloud:** AWS · **IaC Tool:** Terraform · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~5 min

---

## Case A — Basic

**A1. What is SQS in Terraform?**
**Answer:** `aws_sqs_queue` — a managed message queue. Queues decouple producers from consumers with durable, async delivery.

**A2. What are the two SQS queue types?**
**Answer:** Standard (at-least-once, best-effort ordering) and FIFO (`fifo_queue = true`, exactly-once, ordered). FIFO requires `.fifo` in the name.

**A3. What is the default retention period for messages?**
**Answer:** 4 days by default, configurable via `message_retention_seconds` (60 seconds to 14 days).

**A4. What is a visibility timeout?**
**Answer:** `visibility_timeout_seconds` — how long a received message is hidden from other consumers before it can be re-delivered if not deleted.

**A5. What is a dead-letter queue?**
**Answer:** A queue receiving messages that failed processing too many times, via `redrive_policy` (or `redrive_allow_policy`) with `maxReceiveCount`.

**A6. How do you send a message with Terraform?**
**Answer:** You generally don't — apps send at runtime. But `aws_sqs_queue` config includes policies, encryption, and DLQ wiring. (There's no persistent "message" resource; send via CLI/SDK.)

**A7. What is SNS in Terraform?**
**Answer:** `aws_sns_topic` — a pub/sub fan-out topic; `aws_sns_topic_subscription` subscribes endpoints (SQS, Lambda, email, HTTP).

**A8. How do you subscribe an SQS queue to an SNS topic?**
**Answer:** `aws_sns_topic_subscription` with `protocol = "sqs"`, `endpoint = queue.arn`, plus an SQS queue policy allowing the topic to send.

**A9. What is `aws_sqs_queue_policy`?**
**Answer:** A resource-based policy on the queue (e.g. allowing an SNS topic or another account to send).

**A10. What is EventBridge in Terraform?**
**Answer:** `aws_cloudwatch_event_bus`, `aws_cloudwatch_event_rule`, and `aws_cloudwatch_event_target` — a serverless event router.

**A11. What is an event rule?**
**Answer:** A pattern (or schedule) that matches events and routes them to targets (Lambda, SQS, SNS, Step Functions).

**A12. What is `aws_cloudwatch_event_target`?**
**Answer:** Connects a rule to a target (ARN) with optional input transformation.

**A13. How do you schedule a rule (cron)?**
**Answer:** `schedule_expression = "rate(1 hour)"` or `"cron(0 12 * * ? *)"` on the rule.

**A14. What is `aws_sns_topic_policy`?**
**Answer:** A resource policy on the topic controlling who can publish/subscribe.

**A15. What is encryption at rest for SQS/SNS?**
**Answer:** SQS `sqs_managed_sse_enabled = true` (SSE-SQS) or `kms_master_key_id`; SNS `kms_master_key_id` on the topic.

## Case B — Advanced / Senior

**B1. How do you wire SQS → Lambda with error handling in Terraform?**
**Answer:** `aws_lambda_event_source_mapping` (batch size, `function_response_types`), a DLQ for poison messages, and a queue policy/IAM role letting Lambda read. Use `ReportBatchItemFailures` so partial failures are retried.

**B2. Explain the SNS → SQS fan-out pattern and its Terraform pieces.**
**Answer:** Publish once to the topic, multiple subscribed queues each get a copy. Terraform: topic + N queues + N subscriptions + queue policies granting `sns.amazonaws.com` send. Decouples publishers from consumer scaling.

**B3. What is a DLQ vs redrive policy and how do you configure it?**
**Answer:** `redrive_policy = jsonencode({ deadLetterTargetArn, maxReceiveCount })` routes messages to the DLQ after N failed receives. For Lambda, an SQS trigger has its own DLQ (`aws_lambda_event_source_mapping` `destination_config`).

**B4. How do FIFO queues differ in configuration and limits?**
**Answer:** `fifo_queue = true`, `content_based_deduplication` optional, `deduplication_scope`/`fifo_throughput_limit`; ~300 msg/s default per queue (up to 3,000 with batching/high throughput), and message groups for ordering.

**B5. How do you configure cross-account SNS→SQS?**
**Answer:** In the topic's account, allow the other account's queue (or principal) to subscribe; in the queue's account, a queue policy allowing the topic ARN to `sqs:SendMessage`. Terraform uses aliased providers for each account.

**B6. What is EventBridge archive/replay and how does Terraform manage it?**
**Answer:** `aws_cloudwatch_event_bus` + archive + `aws_cloudwatch_event_archive` for replaying past events into a rule — useful for backfills and disaster recovery of event streams.

**B7. How do you transform events between a rule and its target?**
**Answer:** In `aws_cloudwatch_event_target`, use `input_transformer { input_paths, input_template }` to reshape the event payload before delivery.

**B8. What is an EventBridge pipe (vs rule)?**
**Answer:** `aws_pipes_pipe` is a point-to-point integration (source → enrichment → target) with filtering/transforms, simpler than a bus+rule when you don't need fan-out.

**B9. How do you design idempotent consumers with SQS?**
**Answer:** Standard queues deliver at-least-once, so consumers must dedupe (idempotency keys in a DB/DynamoDB). FIFO + content dedup reduces but doesn't eliminate the need for idempotent handlers.

**B10. How do you set retention/DLQ/encryption consistently via a module?**
**Answer:** A queue module with inputs (fifo, retention, DLQ ARN/maxReceiveCount, SSE) applied to all queues, so every queue inherits the organization's standards.

**B11. What are the SQS long polling options?**
**Answer:** `receive_wait_time_seconds` (0–20s) reduces empty responses and cost versus short polling. Set 20s in prod consumers.

**B12. How do you avoid message duplication across retries and re-deliveries?**
**Answer:** Design handlers idempotent, use `MessageDeduplicationId` (FIFO), track processed message IDs in a store, and set appropriate visibility timeouts so in-flight messages aren't reprocessed prematurely.

## Case C — Scenario

**C1. Messages are landing in the DLQ constantly. How do you diagnose?**
**Answer:** Inspect the DLQ messages for the failure cause, check consumer logs, verify the poison-message pattern (bad payload, missing resource), fix the handler, then replay DLQ messages back to the main queue (via a replay Lambda or console).

**C2. You need to notify three systems when a file is uploaded to S3.**
**Answer:** S3 event → single SNS topic, with three subscriptions (e.g. two SQS queues + one Lambda). Terraform: `aws_s3_bucket_notification` to the topic, topic, subscriptions, and queue policies.

**C3. A consumer takes 5 minutes per message and messages keep being delivered twice.**
**Answer:** Visibility timeout (default 30s) is shorter than processing time, so messages become visible and re-delivered. Raise `visibility_timeout_seconds` above the max processing time, and keep processing idempotent.

**C4. You need ordered processing of per-user events with high throughput.**
**Answer:** Use a FIFO queue with `message_group_id = userId` so ordering is per group, enable high-throughput mode, and scale consumers carefully (FIFO limits in-flight per group).

**C5. Events from an old release broke a downstream consumer; you need to re-run last week's events.**
**Answer:** If the bus has archives enabled, replay the archive window into the (fixed) rule; otherwise backfill from a source of truth (DynamoDB stream, S3) by re-publishing events.

**C6. A partner account must publish events into your event bus.**
**Answer:** Allow the partner's principal in the bus policy (`aws_cloudwatch_event_bus_policy`) for `events:PutEvents`, and route their events via rules. Use an aliased provider if you also need to configure their side.
