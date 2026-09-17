# Rate Limiter Deep Dive - SDE3

## Why Rate Limiter?
- Prevent DDoS, brute force, scraping, protect backend from overload, fair usage, cost control

## Where to Implement?
- Client side (throttle), API Gateway (Kong, AWS API Gateway, Nginx), Service side (middleware), Infrastructure (WAF)

## Algorithms Detailed

### 1. Fixed Window Counter
- Divide time into fixed windows (e.g. 1 min), counter per window
- Pros: Simple, memory efficient
- Cons: Burst at boundary (100 req at 00:59 and 100 at 01:00 = 200 in 1 sec across boundary)
```java
Map<String, Integer> counters = new HashMap<>();
Map<String, Long> windowStart = new HashMap<>();
boolean allow(String user) {
  long now = System.currentTimeMillis();
  long window = 60_000;
  if (!windowStart.containsKey(user) || now - windowStart.get(user) > window) {
    windowStart.put(user, now);
    counters.put(user, 1);
    return true;
  }
  if (counters.get(user) < 100) {
    counters.put(user, counters.get(user)+1);
    return true;
  }
  return false;
}
```

### 2. Sliding Window Log
- Store timestamp of each request in sorted set, remove old timestamps outside window, count remaining
- Pros: Accurate, no boundary burst
- Cons: Memory heavy (store each request timestamp)
```java
// Redis ZSET implementation as earlier
```

### 3. Sliding Window Counter (Hybrid)
- Combine fixed window + weighted previous window
- Formula: Count = prevWindowCount * (1 - overlap%) + currentWindowCount
- Example: Window 1 min, request at 30 sec into current window, overlap 50% of previous window counts
- Pros: Memory efficient (only 2 counters), smooth, 99% accurate
- Cons: Not 100% accurate but good enough
- Used by: Most production systems

### 4. Token Bucket
- Bucket capacity = max burst, refill rate = sustained rate
- Each request consumes 1 token, if no tokens reject
- Pros: Allows burst up to capacity, smooths to refill rate, memory efficient
- Cons: Need to handle refill
```java
class TokenBucket {
  long capacity, tokens;
  double refillRate; // tokens per ms
  long lastRefill;
  synchronized boolean allow() {
    refill();
    if(tokens>0) { tokens--; return true; }
    return false;
  }
  void refill() {
    long now = System.currentTimeMillis();
    long toAdd = (long)((now-lastRefill)*refillRate);
    tokens = Math.min(capacity, tokens+toAdd);
    lastRefill = now;
  }
}
```
- Use: API rate limiting where burst allowed (e.g. 100 req/min but allow 20 burst at once)

### 5. Leaky Bucket
- Queue (bucket) with fixed leak rate, requests added to queue, processed at fixed rate, if queue full reject
- Pros: Smooth output rate, no burst
- Cons: No burst allowed, queue may grow
- Use: Traffic shaping, smooth downstream load

## Comparison

| Algorithm | Burst | Memory | Accuracy | Use Case |
|-----------|-------|--------|----------|----------|
| Fixed Window | Yes at boundary | Low | Low | Simple |
| Sliding Log | No | High | High | Accurate needed |
| Sliding Counter | Some | Low | Medium-High | Production balanced |
| Token Bucket | Yes allowed | Low | Medium | Allow burst |
| Leaky Bucket | No | Low | Medium | Smooth traffic |

## Distributed Rate Limiter

### Problem: Single server in-memory not enough, need shared across servers

### Solution 1: Redis + Lua (Recommended)
- Lua script atomic, single round trip
- Use sliding window log or token bucket in Redis
- Example token bucket Lua:
```lua
local key = KEYS[1]
local capacity = tonumber(ARGV[1])
local refillRate = tonumber(ARGV[2]) -- tokens per sec
local now = tonumber(ARGV[3])
local requested = tonumber(ARGV[4])

local bucket = redis.call('HMGET', key, 'tokens', 'lastRefill')
local tokens = tonumber(bucket[1]) or capacity
local lastRefill = tonumber(bucket[2]) or now

local elapsed = now - lastRefill
local toAdd = elapsed * refillRate
tokens = math.min(capacity, tokens + toAdd)

local allowed = 0
if tokens >= requested then
  tokens = tokens - requested
  allowed = 1
end

redis.call('HMSET', key, 'tokens', tokens, 'lastRefill', now)
redis.call('EXPIRE', key, 3600)
return allowed
```

### Solution 2: Sticky Sessions + Local
- User always goes to same server via IP hash, local limiter, but if server down or scaling uneven, not accurate

### Solution 3: Centralized Service
- Dedicated rate limiter service, but single point failure, latency

## Headers to Return

```
HTTP/1.1 429 Too Many Requests
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 0
X-RateLimit-Reset: 1713000000 (unix timestamp when window resets)
Retry-After: 60 (seconds to retry)
Content-Type: application/json
{
  "error": "Rate limit exceeded",
  "code": "RATE_LIMIT_EXCEEDED"
}
```

## Rate Limiting Levels

- **IP based**: Limit per IP, prevent DDoS, but NAT shares IP
- **User based**: Per user ID (after auth), more accurate
- **API based**: Per endpoint (e.g. /login 5 req/min, /search 100 req/min)
- **Tier based**: Free tier 100 req/min, paid 1000 req/min, check subscription

## Advanced

### Multi-level Rate Limiting
- Global: 10k req/sec for whole system
- Per user: 100 req/min
- Per endpoint: /api/payment 10 req/min
- Implement chain: Check global -> user -> endpoint, if any fails reject

### Soft vs Hard Limit
- Soft: Throttle (slow down) but allow with delay
- Hard: Reject with 429

### Rate Limiter as Middleware (Express)

```js
const redis = require('redis');
const client = redis.createClient();

async function rateLimiter(req, res, next) {
  const userId = req.user.id;
  const key = `ratelimit:${userId}`;
  const limit = 100;
  const window = 60; // sec
  const count = await client.incr(key);
  if (count === 1) await client.expire(key, window);
  res.setHeader('X-RateLimit-Remaining', Math.max(0, limit-count));
  if (count > limit) {
    res.setHeader('Retry-After', await client.ttl(key));
    return res.status(429).json({error: 'Too many requests'});
  }
  next();
}
```

### Nginx Rate Limiting
```nginx
limit_req_zone $binary_remote_addr zone=mylimit:10m rate=10r/s;
server {
  location /api/ {
    limit_req zone=mylimit burst=20 nodelay;
  }
}
```

## Interview Q

**Q: How to handle rate limiter for 1M RPS distributed?**
- Use Redis cluster, sliding window counter, Lua atomic, local cache with eventual sync for performance (allow slight over-limit for speed), use token bucket for burst, multi-level, return 429 with Retry-After, monitor via metrics, use Kafka for async logging

**Q: Difference between rate limiting and throttling?**
- Rate limiting: Hard reject when limit exceeded (429)
- Throttling: Slow down processing, queue or delay, but eventually process

**Q: How to prevent bypass?**
- Implement at API Gateway not just service, use IP + user ID, use WAF, captcha for brute force
