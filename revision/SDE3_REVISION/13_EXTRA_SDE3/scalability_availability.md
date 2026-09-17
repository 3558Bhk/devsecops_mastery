# Scalability & Availability - SDE3

## Scalability

### Vertical Scaling (Scale Up)
- Bigger machine: More CPU, RAM, SSD
- Pros: Simple, no code change
- Cons: Hardware limit, downtime to upgrade, single point of failure, costly
- Use: Small apps, DB primary (until limit)

### Horizontal Scaling (Scale Out)
- More machines, load balancer distributes
- Pros: Infinite scale, HA, no downtime
- Cons: Code must be stateless, distributed complexity, data consistency
- Use: Web servers, microservices - preferred for SDE3

### How to Make Stateless?
- Don't store session in server memory, store in Redis or JWT
- Any server can handle any request
- Enables auto scaling

### Scaling Techniques

#### 1. Load Balancing
- ALB, Nginx, HAProxy
- Algorithms: Round Robin, Least Connections, IP Hash, Consistent Hashing
- Health checks remove unhealthy

#### 2. Database Scaling
- **Read Replicas**: Master for writes, replicas for reads, async replication, lag
- **Sharding**: Split by key, each shard subset of data, need shard key, cross-shard query hard
- **Caching**: Redis reduces DB load 80%
- **CQRS**: Separate read/write models
- **NoSQL**: For scale over ACID

#### 3. Caching (as previous file)
- Multi-level: Browser, CDN, App, Redis, DB

#### 4. Async Processing
- Don't do heavy work in request thread, push to queue (SQS/Kafka) and respond 202 Accepted
- Worker processes queue
- Example: Image upload -> API returns 202, worker resizes, emails

#### 5. Microservices + Auto Scaling
- K8s HPA: Horizontal Pod Autoscaler based on CPU/memory/custom metrics (QPS)
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata: {name: myapp-hpa}
spec:
  scaleTargetRef: {apiVersion: apps/v1, kind: Deployment, name: myapp}
  minReplicas: 2
  maxReplicas: 20
  metrics:
  - type: Resource
    resource: {name: cpu, target: {type: Utilization, averageUtilization: 70}}
```

#### 6. CDN
- Static assets at edge, reduces origin load

#### 7. Rate Limiting & Throttling
- Protect from overload, DDoS
- Algorithms: Token Bucket, Leaky Bucket, Fixed Window, Sliding Window Log/Counter
- Implement at API Gateway, Nginx, code (Redis)

## Availability

### Definitions
- Availability = Uptime / (Uptime + Downtime)
- 99.9% = 8h45m downtime/year
- 99.99% = 52m downtime/year
- 99.999% = 5m downtime/year (five nines)

### How to Achieve High Availability?

#### 1. Redundancy
- No single point of failure
- Multiple instances across AZs (Availability Zones)
- DB Multi-AZ, Redis cluster, ALB multi-AZ

#### 2. Failover
- Active-Passive: Passive takes over when active fails (DB Multi-AZ)
- Active-Active: Both serve traffic (app servers behind ALB)

#### 3. Health Checks
- Liveness: Is app alive? If not restart
- Readiness: Is app ready to serve? If not remove from LB
- K8s: livenessProbe, readinessProbe, startupProbe

#### 4. Circuit Breaker & Bulkhead & Retry
- Prevent cascade failure

#### 5. Multi-AZ & Multi-Region
- AZ: Same region different data center isolated (1-2ms latency) - for HA
- Region: Different geography (50-200ms) - for DR (Disaster Recovery) + latency for global users
- Active-Active multi-region complex (data replication conflict)

#### 6. Backup & Restore
- Automated backups, test restore, RPO (Recovery Point Objective - how much data loss) and RTO (Recovery Time Objective - how long to recover)

#### 7. Chaos Engineering
- Intentionally inject failures to test resilience (Chaos Monkey, Litmus, Gremlin)
- Netflix Simian Army

## CAP Theorem Recap
- In network partition (P will happen), choose Availability vs Consistency
- AP: DynamoDB, Cassandra - available but eventual consistency
- CP: MongoDB (primary), HBase - consistent but may be unavailable during partition

## PACELC
- If Partition, choose A/C else choose Latency/Consistency
- Example: DynamoDB PACELC: If P choose A, Else choose L (latency over consistency)

## Performance Metrics

### Latency
- Time to process request
- P50, P95, P99: 95% requests faster than P95 value
- P99 important: 1% slow requests affect many users at scale
- Example: P50 100ms, P95 300ms, P99 1000ms means 1% users see 1 sec

### Throughput
- Requests per second (RPS/QPS)
- Transactions per second (TPS)

### How to Reduce Latency?
- Caching, CDN, DB indexing, connection pooling, async, HTTP/2, gRPC, closer to user (edge), compress, pagination

### How to Increase Throughput?
- Horizontal scaling, caching, async, batching, non-blocking IO, connection pooling

## Scalability Interview Estimation Example

Design Twitter:
- 500M users, 200M DAU, avg 2 tweets/day = 400M tweets/day ~ 4600 tweets/sec peak 10k
- Avg tweet 300 bytes + metadata 500 bytes = 500 bytes
- Storage: 400M * 500 bytes = 200GB/day, 73TB/year, keep 5 years 365TB + replication 3x ~1PB
- Read: Each user follows 200 avg, timeline 200*2=400 tweets/day to read, 200M*400=80B timeline reads/day -> 1M reads/sec
- Need: Sharding by user_id, cache timeline in Redis, fanout on write (push) for active users + pull for inactive, Cassandra for tweets, Redis for timeline, CDN for images, search via Elasticsearch

## Auto Scaling Types
- **Reactive**: Based on metrics (CPU 70%)
- **Predictive**: ML forecast based on history (AWS predictive scaling)
- **Scheduled**: Scale up at 9 AM down at 9 PM for office app

## Interview Tip
Always mention: Stateless, horizontal scaling, caching, DB read replicas/sharding, async queues, CDN, multi-AZ, monitoring, auto scaling, rate limiting.
