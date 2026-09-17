# Interview Day Checklist - SDE3

## Before Interview (30 min)

- [ ] Laptop charged, internet backup (mobile hotspot), quiet room
- [ ] Resume printed, 2 copies, projects with numbers memorized
- [ ] Water, notepad, pen
- [ ] Join 10 min early, test mic/cam
- [ ] Close notifications, Slack

## Projects to Explain (Prepare 5 min each)

For each project:
- What problem? Why needed?
- Users/QPS/scale numbers
- Architecture diagram (draw quickly): Client -> CDN -> LB -> Gateway -> Services (list) -> DB/Cache/Queue
- Tech stack + versions (Java 17, Spring Boot 3.2, PG 15, Redis 7, Kafka, K8s 1.30, AWS EKS)
- Your role: What you owned end-to-end? Design decisions you made? Tradeoffs?
- Challenges: N+1, scaling, incident, how solved?
- Impact: Latency reduced X%, cost saved $Y, availability improved, team velocity

## System Design Round (60 min) - Structure on board

1. **Clarify (5 min)**: Ask: Users? Features must vs nice? Scale? Latency? Read/write ratio? Consistency? Any specific compliance?
2. **Estimation (5 min)**: DAU, QPS peak = avg*3-10, storage per day, bandwidth, cache size
3. **HLD (15 min)**: Draw boxes: Client, CDN, LB, API Gateway, Services, Cache, DB, Queue, External, Monitoring. Explain flow.
4. **Deep Dive (25 min)**: DB schema + sharding key + replication, API design (REST), caching (Redis, TTL, invalidation), queue (Kafka vs SQS), scaling, consistency (SAGA if microservices)
5. **Bottlenecks (5 min)**: SPOF? How HA? How handle celebrity problem? Cache stampede? Rate limiting? Security?
6. **Wrap (5 min)**: Monitoring, alerting, future improvements

- Always mention: Load balancer, cache, DB read replicas/sharding, queue for async, CDN, multi-AZ, auto scaling, rate limiting, auth, monitoring

## LLD Round (45 min)

- Requirements (5 min) - ask clarifying
- Use cases (5 min)
- Class diagram (10 min) - nouns -> classes, show relationships (inheritance, composition), SOLID
- Schema if needed (5 min)
- Code core classes (15 min) - focus on main flow + concurrency handling (synchronized, locks)
- Edge cases + patterns used (5 min)

## Coding Round (45 min)

- Clarify constraints, input size, edge cases (5 min)
- Brute force + complexity (5 min)
- Optimize with pattern (two pointers, sliding window, etc) (20 min)
- Code clean with meaningful names (10 min)
- Test with examples + edge cases (5 min)
- Complexity analysis

## Behavioral Round (30 min)

- Use STAR, quantify, show ownership, collaboration, learning from failure
- Have 5 stories ready: Challenging bug, conflict, leadership/mentoring, failure, tight deadline
- Each story 2-3 min

## Questions to Ask Interviewer (5 min at end)

- What does SDE3 own vs SDE2 here?
- Biggest tech challenge team facing?
- How does team balance tech debt vs features? Error budget?
- On-call rotation and culture?
- Growth path SDE3 -> Staff?
- What would success in first 6 months look like?

## Common Mistakes to Avoid

- Jumping to solution without clarifying requirements
- Not asking about scale (1k vs 1M users changes design)
- Forgetting monitoring, security, caching, rate limiting
- Saying "we" only, not highlighting your contribution
- Not mentioning tradeoffs (no perfect solution)
- Over-engineering LLD (don't code all getters/setters, focus on core logic)
- Not testing code with examples
- Negative about previous company
- Not admitting when don't know (say "I haven't used X but I know Y similar and would learn by docs/POC")

## Last Minute Numbers to Memorize

- Ports: Jenkins 8080/50000, MySQL 3306, PG 5432, Mongo 27017, Redis 6379, Kafka 9092, ES 9200
- Status: 200, 201, 204, 301, 302, 304, 400, 401, 403, 404, 409, 429, 500, 502, 503, 504
- Java: 8 streams/lambda, 11 var/HttpClient, 17 records/sealed, 21 virtual threads
- K8s: 1.24 dockershim removed, 1.30 current, HPA, liveness/readiness probes
- CAP: Choose 2, PACELC
- SOLID one liners
- Rate limiter: Token bucket allows burst, leaky bucket smooths

## Confidence Booster

- You have 4 years experience, you have solved real problems at scale
- Interview is conversation to see how you think, not to trick
- Think aloud, show tradeoff analysis, ask clarifying
- It's okay to say "Let me think for a minute"
- Breathe, smile, be curious

Good luck! You got this! 🚀
From Vijayawada to big tech!
