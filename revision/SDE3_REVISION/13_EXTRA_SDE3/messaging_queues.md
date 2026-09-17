# Messaging Queues & Streaming - Revision

## Why Message Queue?
- Decoupling, async, buffering, resilience, scalability, guaranteed delivery

## Concepts

### Queue vs Topic (Pub/Sub)
- **Queue (Point-to-Point)**: One message consumed by one consumer (e.g. SQS, RabbitMQ queue). Once consumed removed. Load balancing.
- **Topic (Pub/Sub)**: One message to many subscribers (e.g. SNS topic, Kafka topic). Each subscriber gets copy.

### Key Terms
- **Producer**: Sends message
- **Consumer**: Receives
- **Broker**: Middleware (Kafka broker, RabbitMQ)
- **Message**: Data + headers
- **Acknowledgment**: Consumer ack after processing, if no ack message requeued
- **DLQ**: Dead Letter Queue - messages that failed after max retries go to DLQ for investigation

## Tools Comparison

### RabbitMQ
- Traditional message broker, AMQP protocol
- Features: Routing (direct, fanout, topic, headers), low latency, push model, per-message ack, priority queue, TTL
- Use: Task queues, RPC, complex routing, low latency < 100ms, ordering per queue
- Cons: Not for high throughput replay, scaling harder
- Example: Order service -> queue -> Email service

### Apache Kafka
- Distributed streaming platform, log-based, pull model
- Features: High throughput (millions/sec), retention (days), replay, ordering per partition, durability, horizontal scale via partitions, exactly-once semantics with idempotent producer + transactions
- Concepts:
  - **Topic**: Category, split into partitions
  - **Partition**: Ordered log, each message offset
  - **Broker**: Kafka server, holds partitions
  - **Producer**: Writes to partition (key determines partition hash)
  - **Consumer Group**: Group of consumers, each partition consumed by one consumer in group, enables parallel processing + load balancing
  - **Offset**: Position in partition, committed after processing
  - **Replication Factor**: Copies of partition across brokers for HA
  - **ISR**: In-Sync Replicas
- Use: Event streaming, logs, CDC, real-time analytics, event sourcing
- Example: User activity events -> Kafka -> Multiple consumers: Analytics, Search index, Notification

### SQS (AWS)
- Fully managed queue, no ops
- Types:
  - **Standard**: At-least-once, best-effort ordering, almost unlimited TPS, cheap
  - **FIFO**: Exactly-once, ordered, 300 TPS (3000 with batching), deduplication ID
- Features: Visibility timeout (if consumer fails to ack within timeout message visible again), DLQ, long polling (20 sec reduces cost), delay queue
- Use: Decoupling microservices on AWS, simple queues
- Cons: No replay, retention max 14 days, no complex routing

### SNS (AWS)
- Pub/Sub, push to SQS, Lambda, HTTP, email, SMS, mobile push
- Fanout pattern: SNS topic -> multiple SQS queues -> different services
- Use: Notifications, fanout

### Kinesis (AWS)
- Similar to Kafka managed, streaming, shards (like partitions), retention 1-365 days, replay
- Use: Real-time streaming on AWS, alternative to Kafka if on AWS
- Kinesis Data Streams vs Firehose (delivery to S3/Redshift)

## Comparison Table

| Feature | RabbitMQ | Kafka | SQS Standard | SQS FIFO |
|---------|----------|-------|--------------|----------|
| Throughput | ~20k msg/s | ~1M msg/s | ~ Unlimited | 300 TPS |
| Ordering | Per queue | Per partition | No | Yes |
| Replay | No (ack removes) | Yes (by offset) | No | No |
| Retention | Until consumed | Configurable days | 14 days | 14 days |
| Latency | Low ms | Low but batch | ~10ms | ~10ms |
| Push/Pull | Push | Pull | Pull | Pull |
| Routing | Advanced | Key-based partition | Simple | Simple |
| Exactly-once | No (at-least + dedup manual) | Yes with config | No at-least | Yes |

## Patterns

### 1. Work Queue
- Producer -> Queue -> Multiple workers compete (competing consumers)
- Use: Image processing, email sending

### 2. Pub/Sub Fanout
- Producer -> Topic/Exchange -> Multiple queues -> Multiple services
- Use: OrderCreated event -> Inventory, Payment, Email all need it

### 3. Request-Reply (RPC over queue)
- Producer sends message with correlationId + replyTo queue, consumer replies to that queue
- Use: When need response but still async decoupling

### 4. Delayed Queue
- Process after delay (e.g. cancel unpaid order after 15 min)
- RabbitMQ: TTL + DLX, SQS: DelaySeconds, Kafka: Not native need scheduler

### 5. Priority Queue
- High priority messages processed first
- RabbitMQ supports, Kafka/SQS not natively (use separate queues)

## Reliability

### At-Most-Once
- Fire and forget, may lose message, no retry
- Use: Metrics, logs where loss okay

### At-Least-Once
- Retry until ack, may duplicate, need idempotent consumer
- Most common (SQS Standard, RabbitMQ, Kafka default)
- Consumer must handle duplicates: Use idempotency key (messageId stored in DB check before processing)

### Exactly-Once
- Hard in distributed, but Kafka has exactly-once with idempotent producer + transactional + consumer transactional (read committed)
- SQS FIFO exactly-once in 5 min deduplication window
- Best practice: Design idempotent consumer so at-least-once behaves like exactly-once

## Idempotent Consumer Example
```java
// Table processed_messages (message_id PK)
@Transactional
public void handle(String messageId, Order order) {
  if (processedRepo.exists(messageId)) return; // already processed
  // process business logic
  orderRepo.save(order);
  processedRepo.save(messageId);
}
```

## When to Use Which?

- **Need complex routing, low latency, RPC**: RabbitMQ
- **Need high throughput, replay, streaming, event sourcing, large scale**: Kafka
- **On AWS, simple decoupling, no ops, no replay needed**: SQS/SNS
- **Real-time streaming on AWS managed**: Kinesis

## Interview Q: How to handle order processing with queue?

Design:
1. API receives order request -> validates -> saves PENDING to DB -> publishes OrderCreated event to Kafka (with outbox pattern to ensure atomic)
2. Returns 202 Accepted with orderId
3. Payment service consumes OrderCreated, processes payment, publishes PaymentCompleted/Failed
4. Inventory service consumes PaymentCompleted, reserves stock, publishes InventoryReserved/Failed
5. Order service consumes final events and updates order status
6. If any fail, compensating events trigger rollback
7. DLQ for failed messages after 3 retries, alert + manual investigation
8. Idempotency via orderId as key, consumer checks processed

## Commands Quick

### RabbitMQ
```bash
rabbitmqctl list_queues
rabbitmqctl list_exchanges
```

### Kafka
```bash
kafka-topics.sh --create --topic orders --partitions 3 --replication-factor 3 --bootstrap-server localhost:9092
kafka-console-producer.sh --topic orders --bootstrap-server localhost:9092
kafka-console-consumer.sh --topic orders --from-beginning --bootstrap-server localhost:9092
kafka-consumer-groups.sh --bootstrap-server localhost:9092 --group my-group --describe
```

### AWS CLI
```bash
aws sqs send-message --queue-url https://sqs... --message-body "hello"
aws sqs receive-message --queue-url https://sqs...
aws sns publish --topic-arn arn:aws:sns:... --message "hello"
```
