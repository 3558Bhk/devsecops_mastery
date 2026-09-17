# Types of Possible Errors - Complete Revision

## 1. By Layer

### Frontend Errors
- **SyntaxError**: `Unexpected token`
- **ReferenceError**: Variable not defined
- **TypeError**: Cannot read property of undefined
- **RangeError**: Invalid array length
- **CORS Error**: Blocked by CORS policy
- **Network Error**: Failed to fetch, backend down
- **Chunk Load Error**: Deployment new version old chunk missing

### Backend Errors
- **Compilation Error**: Java compile fail
- **Runtime Error**: NullPointerException, OutOfMemoryError
- **Logic Error**: Wrong output but no crash (hardest to find)
- **Configuration Error**: Wrong port, env var missing, YAML syntax

### Database Errors
- **Connection Error**: Too many connections, timeout, auth fail
- **Constraint Violation**: Duplicate key, foreign key fail, not null
- **Deadlock**: Two transactions waiting each other
- **Slow Query**: Missing index, N+1, full scan
- **Replication Lag**: Slave behind master

### Infrastructure Errors
- **Out of Memory (OOM)**: Container killed, need more memory or leak fix
- **Disk Full**: No space left on device
- **CPU Throttling**: High load, need scale
- **Network**: DNS resolution fail, timeout, connection refused

## 2. HTTP Errors (Covered but grouped)

### 4xx Client
- 400 Validation fail (Zod, Joi)
- 401 Token expired/invalid -> redirect login, refresh token
- 403 Forbidden -> show not authorized page
- 404 Not Found -> check route, resource deleted
- 409 Conflict -> duplicate email, version conflict (optimistic locking)
- 413 Payload too large -> increase limit or chunk upload
- 422 Semantic error -> e.g. end date before start date
- 429 Rate limit -> exponential backoff

### 5xx Server
- 500 Null pointer, unhandled exception -> check logs, fix bug, return generic message not stack trace (security)
- 502 Bad Gateway -> backend down, Nginx can't connect to Node, check `pm2 status`, `kubectl get pods`
- 503 Service Unavailable -> overloaded, circuit breaker open, maintenance
- 504 Gateway Timeout -> DB slow, downstream service slow, increase timeout or optimize

## 3. Types by Nature

### Syntax Errors
- Detected at compile/lint time
- Missing semicolon, bracket, typo
- Fix: Linter ESLint, IDE, compiler

### Runtime Errors
- Occurs during execution
- Examples: Null pointer, division by zero, out of bounds
- Handling: try-catch, null checks, Optional

### Logical Errors
- Code runs but wrong result
- Off-by-one, wrong condition, infinite loop
- Hardest, need tests, code review

### Semantic Errors
- Code syntactically correct but meaningless
- Example: Using variable before initialization in some languages

## 4. Distributed System Errors

### Network Failures
- **Timeout**: Service didn't respond in time -> retry with backoff
- **Connection Refused**: Service down, wrong port
- **DNS Failure**: Service discovery fail
- **Packet Loss**: Unreliable network

### Consistency Errors
- **Race Condition**: Two threads/processes modify same data concurrently without lock
  - Fix: Locking (pessimistic), versioning (optimistic), atomic operations, queue
- **Deadlock**: A waits B, B waits A -> detection, timeout, ordered locking
- **Livelock**: Keeps changing state but no progress
- **Starvation**: Low priority never gets resource

### Data Errors
- **Dirty Read, Phantom Read** (isolation levels)
- **Eventual Consistency Lag**: Read stale data right after write -> read-your-writes consistency, use primary for critical reads

## 5. Security Errors
- **Auth Fail**: Token expired, signature invalid, issuer mismatch
- **Brute Force**: Too many login attempts -> lock account
- **Injection**: SQL injection error may show DB structure (don't expose details)
- **XSS**: Script injected
- **CSRF**: Invalid token

## 6. DevOps / Deployment Errors

### Docker
- `port already allocated`: Change port or kill process
- `no space left`: `docker system prune`
- `manifest unknown`: Wrong tag
- `permission denied`: User not in docker group

### Kubernetes
- **ImagePullBackOff**: Wrong image name, private registry no secret, tag not exist
- **CrashLoopBackOff**: App crashes on start, check logs `kubectl logs --previous`
- **OOMKilled**: Container exceeded memory limit, increase limit or fix leak
- **Pending**: No nodes with enough resources, PVC not bound
- **Liveness probe failed**: App hung, will restart
- **Readiness probe failed**: App not ready to serve traffic
- **Node NotReady**: Node down

### Jenkins
- `No space left`: Clean workspace, old builds
- `Permission denied`: Wrong file permissions, user
- `Agent offline`: JNLP port blocked, agent down
- `Out of memory`: Increase heap `JAVA_OPTS=-Xmx4g`

## 7. Common Java/Node Errors

### Java
- **NullPointerException**: Most common, check null, use Optional, Objects.requireNonNull
- **OutOfMemoryError: Java heap space**: Increase -Xmx, fix leak, check large lists
- **StackOverflowError**: Infinite recursion
- **ClassNotFoundException**: Missing jar
- **ConcurrentModificationException**: Modify collection while iterating
- **IllegalStateException**: Wrong state

### Node.js
- **Cannot read property of undefined**: Check optional chaining `user?.profile?.name`
- **EADDRINUSE port in use**: Kill process or change port
- **UnhandledPromiseRejection**: Missing catch
- **Maximum call stack exceeded**: Recursion
- **Memory leak**: Event listeners not removed, global variables, closures

## 8. How to Handle Errors? Best Practices

### 1. Fail Fast
Validate input early, throw early

### 2. Central Error Handling
```js
// Express global error handler
app.use((err, req, res, next) => {
  logger.error({err, requestId: req.id});
  if (err instanceof ValidationError) return res.status(400).json({code: err.code});
  if (err instanceof NotFoundError) return res.status(404).json({});
  return res.status(500).json({code: 'INTERNAL_ERROR', message: 'Something went wrong'}); // don't expose stack in prod
});
```

### 3. Don't Expose Sensitive Info
- In prod, don't return stack trace, DB errors, file paths to client
- Log detailed internally, return generic to client + requestId for tracing

### 4. Retry Strategies
- Only retry idempotent operations (GET, PUT, DELETE)
- Don't retry 4xx (except 429, 408)
- Retry 5xx, network errors with exponential backoff + jitter + max retries 3
- Use circuit breaker to stop retrying failing service

### 5. Logging
- Log with levels: DEBUG, INFO, WARN, ERROR, FATAL
- Include: timestamp, requestId, userId, error code, stack
- Use structured logging JSON

### 6. Monitoring & Alerting
- Metrics: Error rate, latency, throughput (RED), CPU, memory
- Alert if error rate > 1% or latency P95 > 500ms

### 7. Graceful Degradation
- If recommendation service down, still show product page without recommendations
- Fallback cache, default values

## 9. Debugging Checklist for SDE3 Interview

When told "Prod is down, 500 errors":

1. Check metrics/dashboard: When started? Which endpoint? Error rate?
2. Check logs: `kubectl logs`, CloudWatch, ELK - stack trace?
3. Recent deployment? Rollback? `kubectl rollout undo`
4. Infrastructure: `kubectl get pods`, `top`, `df -h`, DB connections
5. Dependencies: Downstream service health? DB slow? Redis down?
6. Reproduce in staging
7. Fix + test + deploy
8. Post-mortem: 5 Whys, action items

> Interview Tip: Always mention requestId correlation across services for debugging distributed systems.
