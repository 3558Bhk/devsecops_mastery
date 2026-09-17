# SDE3 Interview Questions - Quick Answers

## System Design

**Q: Design URL shortener, rate limiter, notification system, chat, news feed?**
- Use 6-step method: Requirements -> Estimation -> HLD -> Deep Dive -> Bottlenecks -> Monitoring
- Always mention: Load balancer, API Gateway, microservices, cache (Redis), DB (SQL/NoSQL), queue, CDN, monitoring, multi-AZ

**Q: How to handle 1M RPS?**
- Horizontal scaling stateless, caching 80% hit, CDN, DB read replicas + sharding, async queue, rate limiting, auto scaling, load balancer, keep-alive, HTTP/2, gRPC internal

**Q: Consistency vs Availability?**
- Explain CAP, PACELC, choose based on use case: Payment needs CP, social feed AP okay

## Jenkins

**Q: Jenkins master-slave?**
- Master schedules jobs, slaves execute. Master has UI, slaves have executors. Benefits: Scalability, different envs (Linux, Windows), security. Now called controller-agent. Use K8s plugin for dynamic agents.

**Q: Declarative vs Scripted pipeline?**
- Declarative: Structured, `pipeline{}` syntax, easier, limited flexibility
- Scripted: Groovy code `node{}`, more flexible but complex
- Use declarative for most, scripted for advanced.

**Q: How to secure Jenkins?**
- RBAC, credentials plugin, folder permissions, agent to controller security, disable CLI, update plugins, use credentials binding not hardcoded, audit logs

## Networking

**Q: What happens when you type google.com?**
- Detailed DNS + TCP + TLS + HTTP + rendering (see networking file)

**Q: TCP vs UDP? When use UDP?**
- DNS, video streaming, gaming, VoIP where speed > reliability

**Q: How to handle CORS?**
- Backend sets Allow-Origin specific not *, handle preflight OPTIONS, credentials

## API

**Q: REST vs gRPC vs GraphQL?**
- Use comparison file, mention mixed usage in real system

**Q: How to version API?**
- URL /v1/ or header, GraphQL no version evolve schema, gRPC package version

**Q: How to ensure idempotency?**
- Idempotency-Key header, store key+response in Redis/DB, check duplicate, for payments critical

## Security

**Q: JWT vs Session?**
- Session stateful need Redis, easy revoke, small cookie. JWT stateless scalable, large, hard revoke. Hybrid: short JWT + refresh token rotation + Redis blacklist

**Q: How to prevent SQL injection, XSS?**
- Prepared statements, ORM, input validation whitelist, output encoding, CSP header, HttpOnly cookie

**Q: OAuth2 flow for SPA?**
- Authorization Code + PKCE, not implicit

## Cloud

**Q: How to design highly available app on AWS?**
- Multi-AZ: ALB across AZs, EC2 ASG across AZs, RDS Multi-AZ, ElastiCache multi-AZ, S3 11 9's, CloudFront, Route53 health checks failover to other region

**Q: EC2 vs Lambda vs ECS?**
- EC2: Full control, long running, stateful
- Lambda: Event driven, short <15min, spiky, no ops
- ECS/EKS: Containers, microservices, need orchestration

## Databases

**Q: SQL vs NoSQL? When to use?**
- See types file, mention polyglot persistence

**Q: How to optimize slow query?**
- EXPLAIN ANALYZE, check missing index, N+1, add index, cache, read replica, denormalize, partitioning

**Q: How to handle transactions in microservices?**
- SAGA pattern, outbox, eventual consistency, compensating transactions

## Caching

**Q: Cache aside vs write-through?**
- Cache aside lazy, only requested cached, stale possible. Write-through consistent but slower write.

**Q: How to prevent cache stampede?**
- Lock, early refresh, jitter TTL, request coalescing

## Errors

**Q: Prod down with 502?**
- Check: Backend down? `kubectl get pods`, `pm2 status`, logs, recent deploy rollback, downstream service health, DB connections, CPU/memory `top`, `df -h`

**Q: How to handle retries?**
- Only idempotent, exponential backoff + jitter, max 3 retries, circuit breaker after threshold

## Behavioral / Leadership (SDE3 expects)

**Q: Tell about a challenging bug?**
- Use STAR: Situation Task Action Result, mention debugging steps, tools, collaboration, prevention

**Q: How do you mentor juniors?**
- Code reviews, pair programming, design docs, share knowledge, set clear expectations

**Q: Conflict with product?**
- Data driven, understand business, propose alternatives, communicate tradeoffs

**Q: Why SDE3?**
- Ownership of complex systems, design, mentoring, cross-team collaboration, impact

## Coding (SDE3 still codes)

- Must know: LRU Cache, Rate Limiter, Design patterns, concurrency, threading
- Practice: LeetCode medium/hard, system design

## Quick Tips for Interview

1. Always clarify requirements before jumping to solution
2. Think aloud, show tradeoff analysis
3. Mention monitoring, logging, alerting, security, scalability in every design
4. Use real numbers for estimation
5. Admit if don't know but show how you'd find out
6. Ask questions about scale, users, latency requirements
7. Mention recent trends: Virtual threads Java 21, React Server Components, K8s 1.30, Valkey fork, OpenTofu

## Final Checklist Before Interview

- [ ] Can explain project architecture end-to-end with diagram
- [ ] Can explain one complex bug and how solved
- [ ] Know CAP, ACID, BASE, SOLID, DRY, KISS
- [ ] Know common ports, status codes, Jenkins plugins
- [ ] Can design 3-4 systems (URL shortener, rate limiter, chat, notification, news feed)
- [ ] Know microservices patterns (SAGA, CQRS, Circuit Breaker)
- [ ] Know caching strategies and pitfalls
- [ ] Know DB indexing and sharding
- [ ] Know CI/CD and deployment strategies
- [ ] Know security OWASP top 10
