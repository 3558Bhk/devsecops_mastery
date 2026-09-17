# AWS Lambda — Interview Questions

> **Cloud:** AWS (Other Services) · **Category:** Compute (Serverless) · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~8 min

---

## JSON File Format

Lambda uses JSON for **events** (the payload passed to the handler) and for function configuration (CloudFormation `AWS::Lambda::Function`). Events are source-specific JSON structures.

```json
{
  "Records": [{
    "eventSource": "aws:s3",
    "eventTime": "2026-09-13T10:30:00Z",
    "s3": {
      "bucket": { "name": "uploads" },
      "object": { "key": "img/photo.jpg", "size": 1048576 }
    }
  }]
}
```

**Key fields (event):** source wrapper (`Records` for S3/SQS/DynamoDB, `detail` for EventBridge, `body` for API Gateway) + the event payload. **Config JSON:** `Runtime`, `Handler`, `MemorySize`, `Timeout`, `Role`, `Environment`, `VpcConfig`.


## Case A — Basic

**A1. What is AWS Lambda?**
**Answer:** A serverless compute service that runs your code in response to events, scaling automatically — you pay only for the compute time you use, with no servers to manage.

**A2. What triggers a Lambda function?**
**Answer:** Event sources: S3 events, DynamoDB streams, SNS/SQS, API Gateway, EventBridge, CloudWatch, and direct `Invoke` calls — plus scheduled events (CloudWatch/EventBridge).

**A3. What is a Lambda execution role?**
**Answer:** The IAM role Lambda assumes to call other AWS services on your behalf (e.g., read S3, write DynamoDB). It must have a trust policy allowing `lambda.amazonaws.com`.

**A4. What are the main configuration knobs of a Lambda?**
**Answer:** Runtime (language), memory (128 MB–10 GB), timeout (up to 15 min), environment variables, concurrency settings, VPC config, and ephemeral storage (512 MB–10 GB).

**A5. How does Lambda pricing work?**
**Answer:** Per **request** (invocations) + **compute duration** (GB-seconds, based on memory × execution time). There's a generous free tier.

**A6. What is a cold start?**
**Answer:** The latency when Lambda initializes a new execution environment (download code, start runtime) before running your handler — happens when there's no warm instance available.

**A7. What is the handler?**
**Answer:** The function entry point (e.g., `index.handler`) that receives the event object and context and returns a response.

**A8. What is the difference between synchronous and asynchronous invocation?**
**Answer:** **Synchronous** (e.g., API Gateway): caller waits for the response. **Asynchronous** (e.g., S3, SNS): Lambda queues the event, returns 202, and retries on failure. **Event source mapping** (SQS/Kinesis/DynamoDB): Lambda polls the source.

**A9. What is the maximum execution timeout?**
**Answer:** **15 minutes** (900 seconds). Longer jobs need Step Functions, EC2, ECS, or chunking.

**A10. What is concurrency and the default account limit?**
**Answer:** The number of function instances running simultaneously. Default **1,000 concurrent executions** per account (adjustable), with per-function reserved concurrency to cap it.

**A11. What is provisioned concurrency?**
**Answer:** Pre-warmed execution environments that eliminate cold starts for a fixed number of concurrent invocations (costs extra) — for latency-critical workloads.

**A12. What is a layer?**
**Answer:** A packaged set of dependencies/libraries (or custom runtimes) shared across functions, keeping deployment packages small.

**A13. What is a dead-letter queue (DLQ) for Lambda?**
**Answer:** An SQS queue/SNS topic that receives failed **asynchronous** invocations after retries are exhausted — for later inspection/replay.

**A14. What is the difference between Lambda and EC2?**
**Answer:** Lambda = serverless, event-driven, auto-scale, pay-per-use, short-lived (≤15 min), no OS access. EC2 = long-running servers you manage, full control, pay for uptime.

**A15. What is the Lambda free tier?**
**Answer:** 1M free requests and 400,000 GB-seconds of compute per month (as of current pricing) — enough for small workloads.

---

## Case B — Advanced (Senior)

**B1. Explain the Lambda execution model and the lifecycle (cold start → warm → concurrency scaling).**
**Answer:** On invoke, Lambda creates an **execution environment** (runtime + code), runs the handler, then freezes it for reuse (warm). Concurrent invocations create parallel environments up to the concurrency limit. Cold starts occur when no warm environment exists. Provisioned concurrency pre-warms environments. Understanding this drives latency and cost optimization.

**B2. How do you optimize Lambda performance (cold starts, memory/CPU, initialization)?**
**Answer:** Increase **memory** (which also scales CPU), minimize **package size** (smaller, fewer dependencies), move heavy init to the **global scope** (runs once per environment), use **SnapStart** (Java) or **provisioned concurrency** for latency-critical paths, choose lighter runtimes, and keep the handler fast.

**B3. How does Lambda integrate with SQS, and what is the "partial batch" failure model?**
**Answer:** An **event source mapping** polls the SQS queue and invokes Lambda with batches. If the function throws, Lambda retries; you can return **partial batch responses** (for SQS) to report which messages failed so only those are retried — avoiding re-processing the whole batch. Configure visibility timeout > function timeout and a DLQ/redrive.

**B4. What is the Lambda concurrency model: unreserved vs reserved concurrency, and throttling?**
**Answer:** **Reserved concurrency** = a per-function cap (guarantees capacity, also prevents one function from starving others). **Unreserved** = the shared pool. When a function hits its limit, excess invocations are **throttled** (429-like errors) — handle with backoff/queues or raise limits. **Provisioned concurrency** = pre-warmed capacity for that function.

**B5. How do you design error handling and retries for async vs stream-based invocations?**
**Answer:** **Async**: Lambda retries twice (with backoff), then sends to the **DLQ**. **Streams (Kinesis/DynamoDB)**: the mapping retries a failed batch until it succeeds or the records expire (no DLQ by default; you can add one by splitting the stream, e.g., via `on-failure` destinations). **SQS**: retries within the visibility timeout, then DLQ/redrive. Always make handlers **idempotent**.

**B6. What are Lambda Destinations and how do they differ from DLQs?**
**Answer:** Destinations route the **result** of async invocations (success or failure) to SQS/SNS/Lambda/EventBridge, giving success-path handling and richer failure info than DLQs. DLQs only capture failures. Destinations are the modern replacement for async DLQs.

**B7. When does Lambda need a VPC, and what are the networking implications (ENIs, NAT, endpoints)?**
**Answer:** When the function must reach private resources (RDS, ElastiCache, internal ALBs). VPC-attached Lambda uses ENIs in your subnets; **outbound internet requires a NAT Gateway** (or a VPC endpoint for AWS services). Cold starts increase slightly due to ENI setup (mitigated by Hyperplane ENIs now). Prefer VPC endpoints over NAT for AWS services.

**B8. How do you trace and observe a Lambda (X-Ray, structured logs, EMF)?**
**Answer:** Enable **X-Ray** (active tracing) to see the full request trace across services. Emit **structured JSON logs** (for Logs Insights) and use **Embedded Metric Format (EMF)** for metrics. Alarm on Errors/Duration/Throttles/IteratorAge. Correlate with a correlation ID passed through the event.

**B9. What is AWS Lambda SnapStart and how does it reduce cold starts (Java)?**
**Answer:** SnapStart pre-initializes the function and snapshots the initialized execution environment (memory + state), restoring it on invoke — reducing Java cold starts from seconds to sub-second. It requires the published alias version and has networking/storage nuances (no X-Ray SDK 2.x init, etc.).

**B10. How do you choose between Lambda, Step Functions, ECS/Fargate, and EC2 for a workload?**
**Answer:** Lambda = short, event-driven, spiky, stateless tasks (≤15 min). **Step Functions** = orchestration of multi-step workflows (and longer runs via integrations). **Fargate/ECS** = containers needing custom runtimes, longer tasks, or persistent workloads. **EC2** = full control, steady-state, or OS-level requirements. Choose by duration, event model, and control needs.

**B11. What is the Lambda "scale-to-zero" and cost model for intermittent workloads?**
**Answer:** With no invocations, you pay **nothing** (no idle cost) — only when functions run. This makes Lambda extremely cheap for intermittent/bursty workloads (cron jobs, webhooks), where EC2 would idle 24/7. Compare: beyond a sustained, high-RPS threshold, EC2/containers can be cheaper.

**B12. How do you do safe deployments with Lambda (aliases, versions, traffic shifting)?**
**Answer:** Use **versions** (immutable snapshots) + **aliases** (stable pointers like `prod`). Shift traffic gradually between versions via **alias weights** (canary), integrate with **CodeDeploy** for automated canary with rollback on CloudWatch alarm, and use environment variables/Parameter Store for config. Roll back by moving the alias weight.

---

## Case C — Scenario

**C1. Scenario:** An image-processing pipeline: user uploads to S3, thumbnails must be generated automatically.
**Question:** Design the serverless flow.
**Expected answer:** S3 **event notification** (object created) → Lambda (thumbnail generation) → write thumbnails back to S3 + record metadata in DynamoDB. Handle failures with a DLQ/destinations, make the function idempotent, and set appropriate memory/timeout. Optionally fan out via SQS for resilience and to control concurrency.

**C2. Scenario:** A function times out at 15 minutes processing a huge file, and a batch job fails.
**Question:** How do you handle workloads longer than 15 minutes?
**Answer:** Options: (1) **Step Functions** with Lambda chunks or Express/Standard workflows (and integration patterns like "run a job" with wait states), (2) **SQS + multiple Lambda invocations** (chunk the work), (3) move to **ECS/Fargate** or **Batch** for heavy compute, or (4) process asynchronously and poll (S3 → Lambda → mark progress in DynamoDB → poll).

**C3. Scenario:** A Lambda-backed API has sporadic high latency (cold starts) for a Java service during traffic bursts.
**Question:** Diagnose and fix.
**Expected answer:** Cold starts from environment initialization (Java is heavy). Fix: enable **SnapStart** (Java), add **provisioned concurrency** for the expected concurrent load, reduce package size/dependencies, move init to global scope, and/or consider a lighter runtime. Measure with X-Ray init vs handler duration to confirm.

**C4. Scenario:** SQS-triggered Lambda keeps re-processing the same messages and then they land in the DLQ.
**Question:** Diagnose the retry loop.
**Expected answer:** Likely causes: a poison message (always fails) or the function is slow — the **visibility timeout** may be shorter than the function duration, causing messages to become visible again and re-invoked (duplicate processing). Fix: set visibility timeout > (function timeout × max retries), implement **partial batch responses**, add idempotency, and inspect the DLQ for the failing payload.

**C5. Scenario:** A Lambda needs to read a secret and query RDS, and the security team forbids hardcoded credentials and public RDS.
**Question:** Design it securely.
**Expected answer:** Put the Lambda in the **same VPC/subnets as RDS** (private), use **Secrets Manager** to store DB credentials and retrieve at init (cache in memory), grant the execution role `secretsmanager:GetSecretValue` + DB access, and ensure the Lambda's SG is allowed in RDS's SG. No NAT needed if it only talks to RDS (in-VPC). Rotate credentials via Secrets Manager.

**C6. Scenario:** A user-reported bug: an order was processed twice, creating duplicate charges, from an async Lambda.
**Question:** Explain and fix.
**Expected answer:** Async invocations **retry** on failure, and network/redelivery can cause **at-least-once** delivery — the function wasn't idempotent. Fix: make the handler **idempotent** (use a unique order ID as the idempotency key, check/insert in DynamoDB with a conditional write, dedupe by key), and ensure retries don't duplicate side effects. This is the core serverless reliability principle.
