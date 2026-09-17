# SDE3 (Senior Software Engineer) — Real Interview Questions

> ~60 questions across 5 parts. Answers are the *key points* — say them in your own words out loud.
> SDE3 interviews grade: depth of fundamentals, **trade-off judgment**, ownership, and how you operate with other engineers.

---

## Part 1 — Basic Level (phone screen / fundamentals)

**Q1. Complexity: O(1), O(log n), O(n), O(n log n) — give an example of each.**
→ O(1): array index lookup. O(log n): binary search. O(n): scan a list for a max. O(n log n): merge sort / heapify. Say *what dominates* as n grows, and "n log n is practically linear for sane n".

**Q2. How does a hash map work internally? What happens on collision?**
→ Array of buckets + hash function → index. Collisions: chaining (list per bucket) or open addressing. Average O(1), worst O(n) with bad hashing/many collisions. Resizing (rehash) when load factor exceeds threshold.

**Q3. INNER JOIN vs LEFT JOIN? When does a query get slow?**
→ INNER: rows matching in both tables. LEFT: all rows from the left + nulls when no match. Slowness: missing index, full scans, huge intermediate results, unselective `WHERE`, N+1 patterns in app code, lock contention.

**Q4. What is a database index? When can it hurt?**
→ B-tree (usually) mapping column values → row locations; speeds reads on that column, costs write amplification + disk. Hurts: many indexes on a high-write table, index on low-cardinality column (e.g. status) used alone, index bloat.

**Q5. Thread vs process. What is a deadlock and how do you prevent it?**
→ Process = separate address space (expensive switch); thread = shared memory (cheap, but race conditions). Deadlock = two tasks each hold a lock the other needs. Prevent: acquire locks in a global order, timeouts, try-lock-and-back-off, or avoid multi-lock designs (single-writer queues).

**Q6. PUT vs PATCH? What are HTTP status codes for?**
→ PUT = replace the whole resource (idempotent, full body); PATCH = partial update (may not be idempotent). Codes: 200/201/202 (done/created/accepted), 301/304, 400/401/403/404/409/422/429, 500/502/503/504. 409 conflict, 429 too many requests are the ones interviewers probe for.

**Q7. Git: rebase vs merge? What is cherry-pick?**
→ merge: keeps history, creates merge commit. rebase: rewrites your commits onto another base (linear history; never rebase shared/pushed branches). cherry-pick: apply *one* commit onto another branch (hotfix flow).

**Q8. Unit vs integration test? What coverage is "good"?**
→ Unit: one class/function, fast, mocks dependencies. Integration: real components together (DB, queue, API). Coverage number is a vanity metric — say "coverage of the *critical paths* and *edge cases* matters more than 80% blanket coverage; I aim high on money/permission logic, lower on glue code."

**Q9. What is idempotency? Why do we care?**
→ Repeating an operation has the same effect as once. Care: clients retry on timeout — a non-idempotent POST /payment double-charges. Implement with idempotency keys: client sends a unique key, server stores result keyed by it, replays stored response on duplicate.

**Q10. Explain CAP. Can you get all three?**
→ Consistency (every read gets the latest write), Availability (every request gets an answer), Partition tolerance (system works across node failures). Networks *will* partition, so you really choose CP (refuse stale reads, e.g. ZooKeeper) or AP (serve possibly-stale, e.g. DynamoDB/Cassandra eventual).

**Q11. Open/Closed Principle — example.**
→ Open for extension, closed for modification: new payment method = new class implementing `PaymentStrategy`, zero changes to the ordering code. (Strategy pattern / interfaces / plugins.)

**Q12. When do you use the Strategy pattern?**
→ When an algorithm varies at runtime and you want to swap it without if/else chains: sorting strategies, pricing rules, payment processors, retry policies.

**Q13. Interface vs inheritance — when do you use which?**
→ Interface = "can do" (capability contract, multiple allowed); inheritance = "is a" (shared implementation). Prefer composition + interfaces; use inheritance sparingly for true taxonomies (e.g. `HttpTransport` → `KafkaTransport`, `SqsTransport` is *not* inheritance material).

**Q14. Design a parking lot — list the classes.**
→ `ParkingLot`, `Level`, `Spot` (type: compact/ev/handicap), `Vehicle` (type/size), `Ticket`, `RateCalculator`. Probe points: which methods do you give Spot vs Level (encapsulation), how to find a free spot fast (free-spot queue per type), how does validation (vehicle fits spot) work.

**Q15. What does a good code review look like (from both sides)?**
→ Author: small PRs (< ~400 lines), clear description, self-review first, tests pass. Reviewer: block on correctness/security/UX; style → suggestions not blocks; comment *why*; praise good parts; respond to feedback even when you disagree (explain, don't ignore).

**Q16. How do you estimate a task?**
→ Break into steps, estimate each with uncertainty (small/medium/large or range), add unknowns explicitly ("I don't know how the third-party API behaves — I'll spike for 2h first"). Senior signal: you estimate *what you don't know*, not just effort.

**Q17. What is technical debt? When is it OK to incur?**
→ Shortcuts that cost more later (missing tests, duplicated logic, god classes). OK when: time-boxed (launch, incident), *visible and tracked*, and paid down in a planned way. Not OK when: invisible, compounding, and "we'll fix it later" becomes the roadmap.

**Q18. Refactor vs new feature — how do you decide?**
→ Rule of three (third time you copy-paste), cyclomatic complexity, "does this change make the next change easier?", and risk. Refactor under test coverage, small commits, no behavior change.

**Q19. A production bug is found 2 weeks after release. Walk me through it.**
→ Reproduce (or find logs/traces) → assess blast radius (users? data?) → fix on a branch, hotfix process (cherry-pick, review, deploy behind feature flag) → verify in staging then prod with monitoring → communicate to stakeholders → postmortem if user-impacting.

**Q20. Tell me about a time you wrote bad code. What did you learn?**
→ STAR. Pick a real example with a *concrete* lesson ("I cached user preferences without invalidation; stale data for 24h; learned to design cache TTL + invalidation *before* adding the cache"). No "I'm a perfectionist" fluff.

---

## Part 2 — Real Job-Specific Questions (the "real time" round)

**Q21. How do you design an API consumed by 3 internal teams + mobile?**
→ Version from day 1 (`/v1/`), OpenAPI spec, backward-compat policy (add fields, never remove/retype), deprecation headers (26+ weeks notice), idempotency keys for writes, pagination (cursor), rate limits per consumer, error model (machine-readable codes + human messages), docs + examples + SDKs.

**Q22. How do you keep a public API backward compatible?**
→ Additive changes only: new optional fields, new endpoints. Breaking changes need a new version + dual-run period. Use contract tests so consumers' expectations are locked. Monitor unknown-field tolerance on both sides.

**Q23. A batch job takes 6h and started failing at hour 5. How do you fix it?**
→ First: is it data-dependent or infra? Add progress/checkpointing (resume from last good point), shard the work (per-region/per-tenant) so one bad shard doesn't kill the run, add per-item error collection (don't stop on first error), alert on partial failure, and make it idempotent so re-runs are safe.

**Q24. Add a NOT NULL column to a 1B-row table without downtime.**
→ Expand→migrate→contract: (1) add column nullable with default, (2) backfill in batches (throttled, resumable), (3) verify backfill, (4) flip app code to always write it, (5) add NOT NULL constraint (online DDL / `ALTER ... ALGORITHM=INPLACE`). Never do it in one giant ALTER on a hot table.

**Q25. Design a cache for a product page. What's the invalidation strategy?**
→ Cache at the entity level (product, price, stock) with different TTLs (price short, description long) + event-driven invalidation on write (product updated → evict). Say the trade-offs: cache-aside vs write-through; stampede protection (singleflight/request coalescing); stale-while-revalidate; and "cache keys must encode everything that changes the result".

**Q26. How do you prevent duplicate processing of webhooks/payments?**
→ Idempotency keys (event ID from provider), persist seen-keys (dedup table with TTL), make the handler idempotent (upserts, conditional inserts), and alert when the same key appears repeatedly (sign of a stuck retry loop).

**Q27. Retry with backoff — how do you implement it *correctly*?**
→ Exponential backoff + **jitter** (avoid thundering herd), max attempts, and only retry on retryable errors (5xx, timeouts, 429) — never on 4xx. Respects `Retry-After` when present. For clients: circuit breaker so you stop hammering a dead dependency.

**Q28. How do you measure the quality of your service?**
→ SLIs/SLOs (availability, p99 latency, error rate), plus product signals (checkout success rate). Say you pick SLOs with the product, not in a vacuum, and use error budgets to balance velocity vs reliability.

**Q29. You disagree with a tech lead's architectural decision. What do you do?**
→ Understand the constraint first ("what problem is this solving?"). If still disagreeing: write the trade-offs down (A/B with costs, risks, migration paths), propose an experiment or timebox, and **decide-then-commit** once decided — no passive resistance. (Senior signal: escalate with data, not emotion.)

**Q30. How do you mentor a mid-level engineer? Give an example.**
→ STAR. Example: paired on a gnarly concurrency bug, let *them* drive, I asked questions instead of giving answers; they shipped the fix and wrote the postmortem. Principles: review their code with depth (teach in reviews), give a stretch task with a safety net, give feedback specific and timely, and celebrate publicly.

**Q31. Large PR vs small PR — how do you split work?**
→ Small PRs: one logical change, < ~400 lines, independently reviewable and revertable. Split vertical slices (feature end-to-end) when possible, horizontal (schema, then API, then UI) when a change spans layers — but never ship a broken intermediate state.

**Q32. Monolith vs microservices for a new product? Your call?**
→ Default: modular monolith (modules with clean boundaries, single deploy). Microservices buy: independent scale, independent teams, isolation of failure — and cost you: ops complexity, distributed debugging, network failures. Ask: how many teams? how different are the scaling profiles? "Start monolith, split when the *org* demands it (Conway's law)."

**Q33. How do you design feature flags?**
→ Granularity: per-feature (not per-bug), scoped to audience (%, user attribute, region). Lifecycle: flags have owners and **expiry** (flag debt is real); kill-switch flags for risky features; combine with staged rollouts. Store flags where they can be flipped fast (config service with < 60s propagation).

**Q34. Config for 50 environments — how do you manage it?**
→ Layers: defaults → environment overrides → per-instance dynamic (flags/secrets). Secrets never in config (vault/SSM). Config-as-code reviewed in PRs. One source of truth (no 50 hand-edited YAMLs). Versioned + auditable changes.

**Q35. A dependency team is blocked and it's on your critical path. What now?**
→ Make the dependency explicit in the plan (it's not "their problem"). Options: stub/fake the contract now (integration later), negotiate a contract-freeze date, escalate *with data* (impact on dates, not blame), or descope scope. Never silently wait.

**Q36. How would you improve a service with 15min deploys and no rollback story?**
→ Small frequent deploys (CI gating), immutable releases (tag/commit), blue-green or canary, automated health checks that gate the switch, one-command rollback to the previous known-good release, and a deploy dashboard. "Rollback in 5 minutes is a feature."

**Q37. How do you handle a 10x traffic spike you didn't plan for?**
→ Short term: scale out (ASG/HPA), shed non-critical load (feature flags off recommendations, queue heavy jobs), rate-limit per tenant, static/CDN offload. Long term: load-test at 10x, autoscaling policies tuned with headroom, capacity review.

**Q38. Explain your experience with CI/CD to a non-infrastructure interviewer.**
→ CI = fast feedback (build + unit tests on every PR, < 10 min); CD = any commit that's green can be promoted automatically; the *culture* part: small changes, trunk-based development, flaky-test quarantine. It's about *risk reduction*, not tools.

**Q39. How do you debug a memory leak in production?**
→ Confirm (heap grows monotonically, GC can't reclaim) → identify (heap dump: dominator tree / top retained objects; JVM: MAT; Go: pprof) → hypothesize (growing cache? unclosed resources? listener accumulation?) → fix + regression test (a test that holds N objects and asserts heap stays flat).

**Q40. How do you write a good incident update / status page message?**
→ Template: what happened (impact), current status, what we're doing, next update time, ETA if known. Say "users see X" not "p99 is elevated". Honesty about not knowing > false precision.

---

## Part 3 — Advanced Level (senior deep-dive / design rounds)

**Q41. Design a URL shortener. Go deep.**
→ API: `POST /v1/shorten {url, key?}` → `{code, shortUrl}`; `GET /v1/{code}` → 301. Storage: KV (code→url) is enough — billions of keys, hot reads. Code generation: base62 counter or random + retries on collision; say why not hash(url) (collisions, no uniqueness guarantee). Scale: read-heavy → CDN cache for hot codes, DB shards by code prefix. Extras: custom aliases, analytics (event bus, not in the hot path), abuse control (rate limits, URL validation), expiry. Failure: DB down → serve from cache; cache down → DB.

**Q42. Design a social feed. Fan-out on write vs read?**
→ Write fan-out: on post, write to every follower's feed table (fast reads, cost = fan-out cost; celebrity problem → hybrid: fans fan-out, celebrities fan-in at read time). Read fan-out: on read, merge author timelines (cheap write, expensive reads, needs pagination across N sources). Pick per scale: hybrid is the "senior" answer; discuss storage (per-user feed stream, bounded size), dedup, and notifications.

**Q43. Design a distributed rate limiter (per user, 100 rps).**
→ Token bucket or sliding window log per key. Storage: Redis (atomic via Lua) at the edge; local in-process counter + async flush (approximate) for hot paths. Trade-offs: strictness vs latency vs cost. Where it lives: API gateway (coarse) + per-service (fine). Say how you test it (replay recorded traffic, verify 429 distribution).

**Q44. Design a system to send 100M emails in 1 hour.**
→ Ingest: push events to a queue (SQS/Kafka) — decouples producers. Workers: consume with concurrency, call provider in batches, respect provider QPS (token bucket per provider), retries with backoff + DLQ for permanent failures. Scale: ~30 msg/s average sustained but with 10–20x bursts → autoscale consumers. Idempotency (email ID dedup), suppression lists, per-tenant rate quotas, metrics (sent/failed/latency per provider), and a "what if the provider is down" story (switch providers, queue with TTL).

**Q45. Design direct messages (chat): offline, read receipts, order.**
→ API: `POST /messages`, `GET /conversations/{id}/messages?before=` (cursor pagination). Storage: per-conversation stream (sequential IDs/snowflakes for order). Offline: sender's message lands in recipient's stream + push notification (FCM/APNs) + unread counter. Read receipts: per-recipient `read_at` per message, fan-out on read. Scale: partition by conversation ID. Failure: at-least-once delivery + client dedup by message ID; order by (conversation, seq) not client timestamps.

**Q46. Design a job scheduler with *exactly-once* execution.**
→ Be honest: you can't get exactly-once end-to-end; you get *at-least-once* (queue) + *idempotent workers* = effectively-once. Design: job table (state machine: pending→running→done/failed, lease/claim with heartbeat), workers claim by `UPDATE ... WHERE state='pending' AND (locked_by IS NULL OR locked_at < now()-ttl)` (atomic claim), heartbeat extend lease, dead-letter + alert on max retries, cron via scheduler sharding (consistent hashing by job hash).

**Q47. Scale a single-DB app 10x. Walk the options.**
→ In order of cost: app-level (indexes, queries, caching hot data, connection pooling, pagination) → read replicas (scale reads, accept replica lag — say how you handle it: session-sticky or "read your own writes") → vertical scale → **shard by tenant/user** (pick a sharding key you never query across; say the cross-shard problem) → CQRS (write to master, read from search/projections). "Cache first, shard last."

**Q48. Design an idempotent payment API end-to-end.**
→ Client generates `Idempotency-Key` (UUID) per *intent*, not per attempt. API: if key seen → return stored response (same status); if processing → return 202 "in progress" (don't start a second charge); if new → store row (key, state, result) in DB *before* calling the PSP, transition state atomically. Webhook handling also idempotent (event ID). Testing: replay storms, duplicate keys, key reuse with different body (409).

**Q49. Consistent hashing — how does it work and when do you use it?**
→ Hash ring: nodes and keys placed on a circle; key → first node clockwise. Add/remove node moves only ~1/N keys (vs full rehash with mod-N). Virtual nodes for balance. Use: cache partitions, sharding, CDN edge selection, DynamoDB-style partitioning. Probe: what happens when a node dies (its keys move to next node — say the temporary load spike and how replicas/staging absorb it).

**Q50. Multi-tenancy: DB-level vs app-level?**
→ DB per tenant (strong isolation, high cost/ops), schema per tenant (middle), row-level `tenant_id` + enforced scoping (cheap, but one bad query = cross-tenant leak — enforce in DB: RLS policies / triggers, not just app code). Say the *data leakage* risk explicitly and how you test it (tenant-isolation test suite that fails the build).

**Q51. How would you add ML inference into a request path with p99 < 300ms?**
→ Don't put the model in the hot path: async (compute, store, serve from cache), precompute for known inputs, or small distilled model in-path + big model async. Quantization, batching, model cache (LRU by feature hash), fallback to rules-based if model timeout. Observability: per-model latency histograms, drift alerts.

**Q52. Design a config service with < 60s propagation to 10k instances.**
→ Push vs pull: long-poll or websocket push (fast, server load) vs polling with short TTL (simpler, eventual). Say: signed configs (tamper-proof), per-instance version (ETag) so re-poll is a 304, canary rollout of config changes (1% → 10% → 100%), instant global kill-switch for risky keys, audit log of every change + who.

**Q53. Your service is 50% CPU at peak. How do you find the hot path before profiling blindly?**
→ Start with *what* not *where*: endpoint latency histograms (which route?), downstream call latency (is it us or our dependencies?), GC/heap, thread pools (saturation?), then profile the top endpoint (CPU flame graph: on-CPU vs off-CPU — say the difference; off-CPU = IO/locks, fix differently). Fix the top 2, re-measure.

**Q54. How do you design an audit log that can't be gamed?**
→ Append-only store (WORM bucket / table with no UPDATE/DELETE grants), hash-chain or per-entry HMAC (tamper evidence), written by the *system* not the actor (server-side capture), includes: who, what, when (server time), before/after for mutations, request ID for correlation. Say: "the audit writer must be on the critical path — if it fails, the mutation fails (or is quarantined), never silently skipped."

**Q55. Two senior engineers propose contradictory architectures. You break the tie. How?**
→ Write both down: goals each solves, cost, risk, reversibility. Find the constraint that matters most (deadline? scale? team skill?). Prefer the *reversible* option when data is inconclusive. Propose a timeboxed experiment with a kill criteria. Decision recorded + committed by both parties (write the ADR).

**Q56. How would you design a deprecation of an internal API used by 40 services?**
→ Instrument first (who calls it, how much — API gateway logs / client-side reporter), publish deprecation with 2+ quarter runway and a migration guide, build the replacement *in parallel*, per-consumer migration dashboard, nudge: deprecation headers + Slack digests per team, final step: 410 Gone + break-glass runbook. "Deprecations fail because they're polite, not because they're hard."

---

## Part 4 — Scenario-Based (real-time, "war story" rounds)

> No single right answer. Structure = half the grade. Use: Stabilize → Diagnose → Fix → Communicate → Learn.

**S1. 5% of checkout requests time out for 20 minutes. Walk me through it.**
→ **Stabilize:** check if it's all traffic or a segment (region? device? payment provider?) — if one provider is down, fail over / queue those orders. **Diagnose:** latency histograms by dependency (DB, card processor, session store); recent deploys? new traffic? **Communicate:** incident channel, "5% of checkouts affected, investigating payment path, next update 15min". **Fix:** if deploy-correlated → roll back first, investigate later. **After:** postmortem — why didn't SLO alert catch it earlier? Add per-provider timeout + circuit breaker + provider-level health dashboard.

**S2. You join a team: CI is red 3 days a week, tests flaky, people merge with --no-verify. First 90 days?**
→ Week 1–2: observe + measure (how red, which tests, how long), build rapport, don't fix anything yet. Week 3–4: quarantine flaky tests (mark + auto-retry *once* with a ticket to fix, not silence), get CI green again — "green means something" is the goal. Month 2: cut CI time to < 10 min (parallelize, cache, split unit/integration), enforce: no --no-verify (branch protection), flaky-test budget ("N flakes/week" metric). Month 3: team owns it — rotation, dashboard. **Key phrase:** "I'd fix the *system* that lets red slide, not the individual tests, first."

**S3. Hotfix needed in prod. You're on-call. Last deploy was by someone who left.**
→ Don't debug the old deploy — **roll back** (it's the smallest known-good state) or deploy the hotfix forward on a *hotfix branch* cut from the current prod tag (not main). Steps: reproduce/confirm the bug, minimal change, peer-review even at 2am (async or phone), deploy to canary/1 instance, watch metrics, promote. If rollback isn't safe (schema changed) → fix forward with a feature flag. Afterwards: document what the deploy did (reverse-engineer from state/logs) so the next person isn't you.

**S4. Your service's P99 crept from 200ms to 2s over 6 months. No incident. Investigate.**
→ No incident = no one "fixed" it — so find what *changed*: (1) A/B by time: split p99 by day, find the elbow. (2) At each elbow: deploy? config? data growth? (3) Per-endpoint: is it one route or everything? (4) If one route: query plan changes (data growth → index), downstream latency, cache hit-rate decline, thread pool saturation. Common culprits: table growth without index review, cache TTLs tuned once, a slow dependency that got slower. **Senior move:** add a p99 SLO + weekly trend report so the next creep alerts at 200→400ms, not 2s.

**S5. A bug you wrote deleted 50K rows (≈ $50K). Full response timeline.**
→ 0–5 min: **stop the source** (deploy revert / feature flag off — it's still deleting). 5–20 min: confirm stopped (metrics flat), assess scope (what's gone, what's replicated). 20–60 min: recovery path (backup/point-in-time restore for the table, or recompute from source-of-truth events if available) — pick the one that's *verifiable*. 1h: stakeholders told with numbers, not adjectives. Next 24h: restore + verify counts + spot-check. Week: blameless postmortem where *I* present; guardrails that would have prevented it (dry-run mode, delete-where-count guards, row-level delete caps, DB alerts on anomaly DML). **The trap:** hiding it. Say early: "I'd tell my manager in the first 5 minutes, with the stop-bleeding action already done."

**S6. You inherit a legacy service, nobody understands it, and business needs a feature in 2 weeks. Plan it.**
→ Week 1 day 1–2: map it (endpoints, data model, deploy, on-call doc) via code + logs + traffic, find the 2 previous owners (even by email), write a 1-page "how this works, where it hurts" doc. Days 3–5: build a **characterization test** around the code path you must change (record current behavior — it's your safety net since there's no test suite). Days 5–10: implement the feature *additively* (new path behind a flag; old path untouched) — "I won't refactor the legacy as part of the feature; the feature gets a clean seam." Days 10–14: shadow traffic / canary, then flag-on for 10% → 100%. Deliverable includes the 1-pager (that's the real asset).

**S7. A vendor deprecates an API you depend on in 90 days. Plan the migration.**
→ Day 1: inventory (who calls it, volume, contract differences, new API's limits). Day 1–14: spike the new API with real traffic (mirror 1% to new, compare responses — diff testing). Day 14–45: dual-write/shim layer — abstract behind an interface, implement v2 adapter, route per-tenant 1%→10%→100% with instant fallback to v1. Day 45–75: run both, compare metrics (latency, errors, cost). Day 75–90: kill v1 path, keep v1 code 30 more days as break-glass. Risks named out loud: v2 is *worse* in some dimension (cost/latency) → negotiate with vendor or plan product change.

**S8. You find a critical security issue in prod at 5pm Friday. What do you do?**
→ Assess: is it *actively exploitable* right now (PoC or just a hole)? If yes: it's an incident — page the on-call/security channel immediately (not "I'll handle it Monday"; say so explicitly). Contain first (disable the exposed endpoint/flag, rotate credentials if leaked). Then: coordinate with security team on disclosure obligations. After: fix, verify, and answer "how did it ship" (missing review? no SAST rule?) with a concrete guardrail. **Senior signal:** Friday 5pm honesty — "the day of the week doesn't change the severity."

**S9. You're asked to present a 30-min architecture review of a system you didn't build, to directors who know nothing about it.**
→ Structure: (1) what it does for the business in 2 sentences + the scale numbers that matter (1 min). (2) one diagram: the happy path (3 min). (3) the three things that keep it alive (data model, consistency choice, failure story) (10 min). (4) risks & debt: what could break, what we're not doing (10 min — this is where directors judge you). (5) decision needed from the room (5 min). "Directors don't want the whole system; they want to know what can break and what it costs."

**S10. Your PR is blocked by a reviewer who "just doesn't like" the approach, and it's due tomorrow.**
→ Don't escalate the *person*; escalate the *decision*. Ask for the specific risk they see ("what breaks if we ship this?"). If it's style/taste: agree to a follow-up ticket, ship. If it's a real disagreement: 15-min pairing or a written ADR with both options — a *decision* unblocks faster than a debate. If it's pure stalling: involve your manager with the facts (what's blocked, what's the deadline, what was proposed). Never go around the reviewer silently.

---

## Part 5 — Questions to ask the interviewers

- "What does the on-call experience look like for this team — who's paged, and what does the last 5 incidents look like?"
- "What's the biggest technical debt item on the roadmap, and what's the plan to pay it down?"
- "How are architecture decisions made here — is there an ADR process, or is it hallway consensus?"
- "What would success look like for the person in this role after 6 months?"
- "What's one thing about the team's way of working that surprised you when you joined?"
- (SDE3 specific) "How much ownership does a senior engineer get over *which* problems get solved, vs which ones are handed to them?"
