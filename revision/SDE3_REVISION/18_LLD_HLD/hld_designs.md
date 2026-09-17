# HLD (High Level Design) - SDE3 Top Designs

## Generic HLD Template (Use for any question)

### 1. Requirements
- Functional: What features?
- Non-functional: Scale (DAU, QPS), latency (P95 <200ms), availability (99.99%), consistency, durability

### 2. Estimation
- Users, QPS, storage, bandwidth, memory
- Example: 1M DAU, 10 req/user/day = 10M req/day ~115 QPS avg peak 10x = 1150 QPS
- Storage: 1KB per record * 10M/day = 10GB/day * 365 = 3.6TB/year * 3 replication = 11TB

### 3. High Level Design
- Draw: Client -> CDN -> LB -> API Gateway -> Services -> Cache -> DB -> Queue -> External
- Mention: Microservices, API Gateway, Load Balancer, Cache, DB, Queue, CDN, Monitoring

### 4. Deep Dive
- DB schema, sharding, replication
- API design
- Caching strategy
- Scaling, partitioning
- Consistency, availability tradeoff

### 5. Bottlenecks & Tradeoffs
- Single point failure? Scale DB? Cache stampede?

### 6. Monitoring & Future

---

## 1. Design URL Shortener (TinyURL)

**Requirements**: Shorten long URL to short, redirect short to long, custom alias, expiry, analytics (clicks)

**Estimation**: 100M URLs/month, 100:1 read:write, 500 bytes per URL -> 50GB/month

**HLD**:
```
Client -> API Gateway -> Write Service -> DB (Cassandra/DynamoDB) + Cache (Redis)
                      -> Read Service -> Cache -> DB
                      -> Base62 Encoder (ID -> short code)
                      -> Analytics Service (Kafka + ClickHouse)
```

**Deep Dive**:
- Short code generation:
  - Hash of long URL (MD5) + collision check, but same long URL should give same short? Optionally
  - Auto-increment ID + Base62: ID 12345 -> Base62 "dnh" (6-7 chars, 62^7 = 3.5T possibilities)
  - Pre-generate IDs via Zookeeper or DB sequence or Snowflake
- DB schema: `id PK, short_code unique indexed, long_url, user_id, created_at, expiry, clicks`
- Cache: `short_code -> long_url` 80% hit, TTL + LRU
- Sharding: By short_code hash
- Redirect: 301 permanent (cached) or 302 temporary (for analytics), use 302 for analytics to hit server
- Custom alias: Check availability

**Bottleneck**: DB for writes, use cache, CDN for redirect caching

---

## 2. Design Rate Limiter

**Requirements**: Limit requests per user/IP, e.g. 100 req/min per user, distributed, low latency

**HLD**:
```
Client -> API Gateway (Rate Limiter Middleware) -> Redis (Token Bucket) -> Backend Service
```

**Algorithms**: Token Bucket (allows burst), Sliding Window Counter (accurate + memory efficient) - use sliding window counter for SDE3

**Distributed**: Redis + Lua script atomic:
```lua
-- Sliding window counter
local key = KEYS[1]
local window = tonumber(ARGV[1]) -- 60 sec
local limit = tonumber(ARGV[2]) -- 100
local now = tonumber(ARGV[3])
local clearBefore = now - window
redis.call('ZREMRANGEBYSCORE', key, 0, clearBefore)
local count = redis.call('ZCARD', key)
if count < limit then
  redis.call('ZADD', key, now, now)
  redis.call('EXPIRE', key, window)
  return 1
else
  return 0
end
```

**Headers**: `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset`, `Retry-After` on 429

---

## 3. Design Notification System

**Requirements**: Send push, SMS, email, in-app, millions per day, priority, retries, templates

**HLD**:
```
Client -> API Gateway -> Notification Service -> Validation -> Template Service
                                          -> Queue (Kafka by priority: high, medium, low topics)
                                          -> Workers (Push Worker, SMS Worker, Email Worker)
                                          -> Third Party (FCM, Twilio, SES)
                                          -> Tracking (Delivery status via webhook -> DB)
                                          -> Retry Queue (DLQ after 3 fails)
```

**Deep Dive**:
- DB: Notification table (id, user_id, type, channel, status, priority, retry_count)
- Queue per channel + priority (3 channels * 3 priorities = 9 topics)
- Idempotency: Notification ID deduplication
- Rate limiting per channel (SMS costly)
- User preferences: Opt-out, quiet hours
- Batching: Group notifications for same user within window
- Template: Variable substitution

---

## 4. Design News Feed (Facebook/Twitter)

**Requirements**: User posts, follow, news feed (posts from followed users sorted by time/relevance), 500M users

**Estimation**: 200M DAU, avg 2 posts/day = 400M posts/day, each user follows 200, fanout 200*400M = 80B feed items/day huge

**HLD**:
```
Post Service -> DB (Cassandra for posts) -> Fanout Service -> Cache (Redis timeline per user) -> Feed Service -> Client
Follow Service -> Graph DB (or Cassandra)
```

**Fanout Strategies**:
- **Push (Fanout on Write)**: When user posts, push post to all followers' feeds in cache. Fast read O(1) but heavy write for celebrity with 10M followers (10M writes). Good for normal users.
- **Pull (Fanout on Read)**: Don't push, when user requests feed, pull from followed users' posts and merge. Slow read (need to query 200 users) but fast write. Good for celebrity.
- **Hybrid**: Push for normal users (<10k followers), pull for celebrities (>10k). Celeb posts not pushed, but when follower requests feed, include celeb posts via pull. Twitter uses this.

**Feed Ranking**: Time-based (simple) vs Relevance (ML features: recency, likes, comments, user affinity)

**Cache**: User timeline in Redis sorted set by timestamp, pagination via cursor

---

## 5. Design Chat System (WhatsApp)

**Requirements**: 1-1 chat, group chat, online/offline, last seen, delivery receipts (sent, delivered, read), typing indicator, media sharing, 2B users

**HLD**:
```
Client (WebSocket) -> Load Balancer (Sticky for WebSocket? Or use Redis pub/sub for cross-server) -> Chat Servers (Netty/WebSocket) -> Message Service -> DB (Cassandra for messages) + Cache (Redis for online status)
-> Presence Service (online/offline via heartbeat)
-> Notification Service (Push for offline)
-> Media Service (S3 + CDN)
```

**Deep Dive**:
- WebSocket persistent connection for real-time
- How to handle multiple devices? Each device has connection, message fanout to all devices of recipient
- Message table: `message_id, conversation_id, sender_id, content, timestamp, status` Partition by conversation_id, clustering by timestamp
- Delivery receipts: Message status updates via separate table or same
- Group chat: Message to group_id, fanout to all members (like news feed push)
- Online status: Heartbeat every 30 sec to Presence Service via Redis, if no heartbeat for 60 sec offline, use Redis with TTL
- Typing indicator: Ephemeral event via WebSocket, not stored
- Media: Upload to S3, thumbnail generation async via queue
- Search: Elasticsearch for message search
- E2E encryption: Signal protocol (advanced)

**Scaling WebSocket**: Need to route message to correct chat server where recipient connected, use Redis pub/sub: When server A receives message for user connected to server B, publish to Redis channel, server B subscribes and delivers

---

## 6. Design YouTube / Video Streaming

**Requirements**: Upload video, transcode to multiple resolutions, streaming, thumbnails, search, recommendations, likes/comments

**HLD**:
```
Upload -> API Gateway -> Upload Service -> S3 (raw video) -> Queue (SQS/Kafka) -> Transcoding Service (FFmpeg workers on EC2) -> S3 (transcoded HLS/DASH segments) -> CDN (CloudFront) -> Client (Video Player HLS)
Metadata -> DB (MySQL for video metadata, Cassandra for comments)
Search -> Elasticsearch
Recommendations -> ML Service
```

**Transcoding**: HLS (HTTP Live Streaming) splits video into 10 sec segments with different resolutions (1080p, 720p, 480p), manifest file .m3u8 lists segments, player adapts based on bandwidth (ABR)

**Streaming**: Not download whole file, stream segments via CDN

---

## More HLDs to Prepare

- Design Google Drive / Dropbox (Chunking, deduplication, sync)
- Design Uber / Location tracking (QuadTree, GeoHash, WebSocket for driver location)
- Design Typeahead / Autocomplete (Trie + Elasticsearch, cache top queries)
- Design Distributed Cache (Consistent hashing)
- Design Job Scheduler (Quartz, delayed queue)
- Design Web Crawler (BFS, politeness, deduplication via Bloom filter)
- Design Payment System (Idempotency, SAGA, double entry ledger)
