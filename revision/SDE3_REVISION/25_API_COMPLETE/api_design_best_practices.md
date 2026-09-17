# API Design Best Practices - SDE3 Complete Checklist

## 1. General Principles

### RESTful Principles Recap
- Resource based nouns, not verbs
- HTTP methods properly (GET read, POST create, PUT full update, PATCH partial, DELETE delete)
- Stateless
- Proper status codes
- Versioning

### API First Design
- Design API contract first (OpenAPI), review with frontend and consumers, then implement
- Mock server from OpenAPI for frontend to start early

### Consistency
- Consistent naming (camelCase vs snake_case - pick one, e.g. snake_case for JSON is common, but JS uses camelCase - decide and document)
- Consistent error format
- Consistent pagination, filtering, sorting
- Consistent auth, rate limiting, headers

## 2. Security Best Practices (Must for SDE3)

- **HTTPS only**: Never HTTP in prod, HSTS header
- **Authentication**: OAuth2 + JWT Bearer token in Authorization header, not URL, short lived access token 15 min + refresh token rotation HttpOnly cookie
- **Authorization**: RBAC/ABAC check server side, never trust client, deny by default
- **Input Validation**: Whitelist validation, reject invalid, use @Valid, sanitize, max length, type check
- **Output Encoding**: Prevent XSS
- **SQL Injection**: Prepared statements, ORM
- **Rate Limiting**: Per user/IP, 429 + Retry-After, at API Gateway
- **CORS**: Allow specific origins not *, handle preflight OPTIONS
- **Security Headers**: Strict-Transport-Security, Content-Security-Policy, X-Content-Type-Options nosniff, X-Frame-Options DENY
- **No sensitive data in URL**: Passwords, tokens not in query params (logged)
- **No sensitive data in logs**: Mask PII, card, password
- **Secrets management**: Vault, AWS Secrets Manager, not in code/env file git, scan with TruffleHog
- **Dependency scanning**: Snyk, Dependabot for vulnerable libs
- **WAF**: Web Application Firewall (AWS WAF, Cloudflare) for SQL injection, XSS protection
- **Idempotency**: For payments, use Idempotency-Key

## 3. Performance Best Practices

- **Pagination**: Always paginate list endpoints, default limit 20, max 100, cursor based for large
- **Field Selection**: `?fields=id,name` to reduce payload
- **Compression**: gzip/br, 70-80% reduction for JSON
- **Caching**: ETag + If-None-Match 304, Cache-Control, Redis for DB queries, CDN for static
- **Connection Pooling**: DB pool (HikariCP), HTTP client pool
- **HTTP/2**: Multiplexing, header compression
- **Keep-Alive**: Reuse TCP connections
- **Async**: For long running, return 202 + job ID, or queue
- **Batching**: Bulk endpoints for multiple creates
- **Rate Limiting**: Protect backend from overload
- **Monitoring**: P95 latency, error rate, QPS

## 4. Reliability Best Practices

- **Idempotency**: POST with Idempotency-Key for critical operations
- **Retries**: Client should retry idempotent methods with exponential backoff + jitter on 5xx, 429, network errors, not on 4xx
- **Circuit Breaker**: Fail fast if downstream down, prevent cascade, use Resilience4j
- **Timeouts**: Set timeouts for all external calls (DB, API), e.g. 500ms for DB, 1 sec for internal service, 5 sec for external
- **Bulkhead**: Isolate thread pools per dependency
- **Graceful Degradation**: If recommendation service down, still show product page without recommendations, fallback cache
- **Health Checks**: /health endpoint returns 200 if healthy, checks DB, cache, downstream
- **Versioning**: Never break existing clients, add optional fields, deprecate with Sunset header

## 5. Documentation Best Practices

- **OpenAPI / Swagger**: Define all endpoints, methods, request/response schemas, examples, auth, errors, generate interactive UI at /swagger-ui.html
- **Examples**: Provide request/response examples for each endpoint
- **Error Codes**: Document all error codes with meaning and how to handle
- **Changelog**: Maintain changelog for API versions
- **Postman Collection**: Provide collection for easy testing
- **SDKs**: Provide client SDKs for popular languages (generated from OpenAPI)
- **Getting Started Guide**: How to auth, first request, common flows

## 6. Versioning Best Practices

- **URL Versioning**: `/api/v1/users` most common, simple, cache friendly
- **Never break v1**: Add optional fields, don't remove or rename required fields, don't change type
- **Deprecation**: Add `Deprecation: true` header + `Sunset: Sat, 31 Dec 2024 23:59:59 GMT` + `Link: <https://docs.example.com/deprecation>; rel="deprecation"` + docs
- **Support 2 versions**: When v2 released, support v1 for 6-12 months, monitor usage, notify consumers, then sunset
- **Semantic Versioning for API**: MAJOR breaking, MINOR new feature backward compatible, PATCH bug fix

## 7. Error Handling Best Practices

- **Consistent Format**:
```json
{
  "error": {
    "code": "USER_NOT_FOUND",
    "message": "User with ID 123 not found",
    "details": [{ "field": "email", "message": "Invalid format" }],
    "requestId": "abc-123",
    "timestamp": "2026-09-13T10:00:00Z"
  }
}
```
- **Proper Status Codes**: Use correct 4xx for client errors, 5xx for server
- **No Stack Trace in Prod**: Log detailed internally, return generic to client + requestId for tracing
- **Machine Readable Code**: `USER_NOT_FOUND` not just message, client can handle programmatically
- **Validation Errors**: 400 with details array of field errors

## 8. Testing Best Practices

- **Unit**: Test controller with mocked service
- **Integration**: Test with real DB via Testcontainers + RestAssured
- **Contract**: Pact consumer-driven for microservices
- **E2E**: Critical flows via Postman/Newman or Cypress
- **Load**: k6 for performance
- **Security**: OWASP ZAP

## 9. Monitoring & Observability Best Practices

- **Metrics**: RED (Rate, Errors, Duration) per endpoint, custom business metrics
- **Logs**: Structured JSON logs with requestId, userId, traceId, level, message, error
- **Traces**: OpenTelemetry + Jaeger, traceId propagated via headers
- **Alerting**: Alert on high error rate >1%, high latency P95 >500ms, high QPS drop
- **Dashboard**: Grafana dashboard per service with QPS, error %, latency P50/P95/P99, CPU, memory, DB connections

## 10. Design Checklist for New API (Use in Interview)

Before implementing new API, check:

- [ ] Resource naming nouns plural? URI hierarchy correct?
- [ ] HTTP methods proper? Idempotent where needed?
- [ ] Status codes proper? 201 with Location for POST create?
- [ ] Versioning? /v1/
- [ ] Pagination? Cursor based for large?
- [ ] Filtering, sorting, field selection?
- [ ] Auth? JWT Bearer? RBAC?
- [ ] Rate limiting? 429 + Retry-After?
- [ ] Input validation? @Valid? Whitelist?
- [ ] Idempotency-Key for critical POST?
- [ ] Caching? ETag? Cache-Control?
- [ ] Error format consistent? Code + message + requestId?
- [ ] Security? HTTPS, CORS, security headers, no sensitive data in URL?
- [ ] Performance? Compression, connection pooling, async for long running?
- [ ] Documentation? OpenAPI with examples?
- [ ] Monitoring? Metrics, logs with requestId, traces?
- [ ] Testing? Unit + integration + contract?
- [ ] Deprecation strategy? Sunset header?
- [ ] Bulk operations? Need bulk endpoint?
- [ ] File upload? Need S3 presigned URL?
- [ ] Webhooks? Need to notify external?
- [ ] Real-time? Need WebSocket/SSE?

## 11. Common Anti-Patterns to Avoid

- **Tunneling everything via POST**: Use proper methods, not POST for all
- **Ignoring status codes**: Always return proper status, not always 200 with error in body
- **No versioning**: Breaking clients when changing API
- **Chatty API**: N+1 API calls from frontend, should aggregate via BFF or GraphQL or expand param
- **Large payloads**: Returning 1000 items without pagination, or 50 fields when client needs 3 (use fields param or GraphQL)
- **No rate limiting**: Vulnerable to DDoS, abuse
- **Sensitive data in URL**: Tokens, passwords in query params
- **No idempotency for payments**: Double charge on retry
- **No timeout**: Hanging requests, thread pool exhaustion
- **Exposing internal errors**: Stack trace to client (security risk)
- **Inconsistent naming**: /users and /userProfiles mixed, camelCase and snake_case mixed
- **No documentation**: No OpenAPI, no examples
- **No monitoring**: No metrics, no logs, no traces, can't debug prod issues

## 12. API Gateway vs Direct

- **Direct**: Client -> Service (simple, but no auth, rate limiting, routing central)
- **API Gateway**: Client -> Gateway (auth, rate limiting, routing, aggregation, transformation, monitoring) -> Services
- Use Gateway for microservices, public APIs, need cross-cutting concerns central
- Tools: Kong (open source, plugins), AWS API Gateway (managed, serverless), Apigee (enterprise), NGINX, Zuul, Spring Cloud Gateway

## 13. GraphQL vs REST vs gRPC Decision (Recap)

- **REST**: Public APIs, simple CRUD, need caching, browser native, team familiar - default
- **GraphQL**: Flexible frontend needs (web vs mobile different fields), aggregate many microservices via BFF, over-fetching problem, real-time subscriptions
- **gRPC**: Internal microservices high perf, low latency, high throughput, streaming, polyglot
- **Hybrid**: Public REST, internal gRPC, frontend BFF GraphQL, real-time WebSocket, events via Kafka, webhooks for external notifications

This checklist ensures you design production ready APIs for SDE3 level.

---

## Expanded: More Best Practices & Production Checklist

### 13. Pagination Deep Dive - Cursor vs Offset Implementation

**Offset Pagination (SQL)**:
```sql
SELECT * FROM users ORDER BY id LIMIT 20 OFFSET 40; -- page 3 (0-indexed)
-- Problem: OFFSET 1000000 is slow (DB scans 1M rows and discards)
-- Inconsistent if new users inserted between page requests (duplicate/missing)
```

**Cursor (Keyset) Pagination (Recommended for Large)**:
```sql
-- First page
SELECT * FROM users ORDER BY id ASC LIMIT 20;
-- Next page: cursor = last id from previous page (e.g. 123)
SELECT * FROM users WHERE id > 123 ORDER BY id ASC LIMIT 20;
-- Fast (uses index on id, no offset scan), consistent (new inserts after cursor not affecting)
-- Implementation: cursor = base64(last_id) or base64(last_id + timestamp)
```

**Cursor with Timestamp for Real-time Feeds**:
```sql
-- For feeds ordered by created_at desc, need handle same timestamp
SELECT * FROM posts WHERE (created_at < '2026-09-13T10:00:00Z') OR (created_at = '2026-09-13T10:00:00Z' AND id < 123) ORDER BY created_at DESC, id DESC LIMIT 20;
-- Cursor = base64(created_at + id)
```

### 14. Filtering Best Practices - RSQL / FIQL

**Simple Filtering via Query Params**:
```
GET /users?role=admin&status=active
GET /products?price[gte]=100&price[lte]=1000&category=electronics
GET /users?createdAt[gte]=2024-01-01
```

**Advanced Filtering via RSQL (RESTful Search)**:
```
GET /users?search=role==admin;status==active;age>=18
GET /products?search=price>=100;price<=1000;category==electronics
```
- RSQL: `==` eq, `!=` ne, `=gt=` >, `=ge=` >=, `=lt=` <, `=le=` <=, `=in=` in, `=out=` not in, `;` AND, `,` OR
- Library: rsql-parser (Java)

**Complex Filtering via POST /search (if URL too long)**:
```json
POST /users/search
{
  "filters": {
    "and": [
      { "field": "role", "op": "eq", "value": "admin" },
      { "field": "age", "op": "gte", "value": 18 },
      { "or": [
        { "field": "status", "op": "eq", "value": "active" },
        { "field": "status", "op": "eq", "value": "pending" }
      ]}
    ]
  },
  "sort": [{ "field": "createdAt", "order": "desc" }],
  "pagination": { "page": 1, "limit": 20 }
}
```

### 15. Sorting Best Practices

```
GET /users?sort=name (asc)
GET /users?sort=-name (desc, - prefix)
GET /users?sort=-createdAt,name (multiple: first by createdAt desc then name asc)
GET /users?sort=age:desc,name:asc (alternative syntax)
```

- Implementation: Validate sort fields against whitelist to prevent SQL injection via sort param
```java
List<String> allowedSortFields = List.of("name", "createdAt", "age");
if (!allowedSortFields.contains(sortField)) throw new BadRequestException("Invalid sort field");
```

### 16. Field Selection (Sparse Fieldsets) - Solve Over-fetching Partially

```
GET /users?fields=id,name,email
GET /users/123?fields=id,name
```

- Implementation: Use Jackson @JsonView or manual filtering, or GraphQL for full solution
- Pros: Reduces payload (e.g. /users returns 50 fields but UI needs 3), saves bandwidth
- Cons: Cache fragmentation (different fields different cache keys), complexity

### 17. Embedding / Expanding - Avoid N+1 API Calls

```
GET /users/123?expand=orders
GET /users/123?include=orders,profile
GET /users?include=orders
```

- Instead of: GET /users/123 then GET /users/123/orders (2 calls), do 1 call with expand
- Implementation: If expand param present, JOIN FETCH orders in DB query
- Caution: Can cause large payload and N+1 DB if not careful (use JOIN FETCH)

### 18. Bulk Operations Best Practices

**Bulk Create**:
```
POST /users/bulk
Body: [{ "name": "John" }, { "name": "Jane" }]
Response: 207 Multi-Status
{
  "results": [
    { "status": 201, "data": { "id": "1", "name": "John" } },
    { "status": 400, "error": { "code": "VALIDATION_ERROR", "message": "Email required" } }
  ]
}
```

**Bulk Update**:
```
PATCH /users/bulk
Body: [{ "id": "1", "name": "John Updated" }, { "id": "2", "name": "Jane Updated" }]
```

**Best Practices**:
- Limit bulk size (e.g. max 100 items) to prevent overload, return 413 if too large
- Use 207 Multi-Status for mixed success/failure
- Make bulk atomic? Or partial success? Document clearly. Usually partial success with 207, not all-or-nothing
- For large bulk (1000+), use async: POST /bulk/jobs => 202 Accepted with job ID, process via queue, client polls job status

### 19. Idempotency Best Practices Expanded

- **When required**: POST for creation that should not duplicate on retry (payments, orders), critical
- **How**: Client generates UUID v4 as Idempotency-Key header, sends with request, server stores key + request hash + response in DB/Redis with TTL 24h, if same key seen returns cached response without re-executing, if same key but different request hash returns 422 (key already used for different request)
- **Implementation**: See rest_api_complete.md expanded section with DB table
- **Key generation**: Client side UUID, not server side (client needs to generate same key for retry)
- **Storage**: Redis with TTL 24h for fast, or DB table idempotency_keys with expiry for persistence
- **Scope**: Per endpoint per user (key should be unique per user per endpoint, e.g. userId + key)
- **Methods**: Only for POST (and PATCH if not idempotent), not needed for GET/PUT/DELETE (already idempotent)

### 20. Security Checklist Expanded (OWASP API Top 10)

**OWASP API Security Top 10 2023**:

1. **API1 Broken Object Level Authorization (BOLA) / IDOR**: /users/123 -> change to 124 get other user data, fix: Check owner, RBAC, use UUID not sequential IDs
2. **API2 Broken Authentication**: Weak JWT, no expiry, fix: Short expiry, RS256, validate signature, use OAuth2
3. **API3 Broken Object Property Level Authorization**: User can update role via PATCH /users/123 { "role": "admin" }, fix: Whitelist updatable fields, don't allow updating sensitive fields
4. **API4 Unrestricted Resource Consumption**: No rate limiting, large payload, fix: Rate limiting, max payload size, pagination limit
5. **API5 Broken Function Level Authorization**: Regular user can access /admin/users, fix: RBAC check per endpoint
6. **API6 Unrestricted Access to Sensitive Business Flows**: No limit on e.g. buying, can buy 1M items, fix: Business logic limits, rate limiting per flow
7. **API7 Server Side Request Forgery (SSRF)**: Server fetches attacker URL, accesses internal metadata 169.254.169.254, fix: Whitelist URLs, disable internal access
8. **API8 Security Misconfiguration**: Default creds, verbose errors, CORS *, fix: Hardening, minimal config, security headers
9. **API9 Improper Inventory Management**: Old versions still running, fix: Inventory all API versions, deprecate old, docs
10. **API10 Unsafe Consumption of APIs**: Trusting external API without validation, fix: Validate external API responses

**Security Headers for APIs**:
```
Strict-Transport-Security: max-age=31536000; includeSubDomains
Content-Security-Policy: default-src 'none' (for API not needed but for docs)
X-Content-Type-Options: nosniff
X-Frame-Options: DENY
X-XSS-Protection: 0 (deprecated, use CSP)
Referrer-Policy: no-referrer
```

### 21. Versioning Deprecation Strategy Production Grade

**Phase 1: Announce Deprecation**:
- Add Deprecation header to old version responses
```http
GET /api/v1/users/123
Deprecation: true
Sunset: Sat, 31 Dec 2025 23:59:59 GMT
Link: <https://api.example.com/api/v2/users/123>; rel="successor-version"
Warning: 299 - "API v1 deprecated, migrate to v2 by 2025-12-31, see https://docs.example.com/migration"
```
- Docs: Migration guide v1->v2 with breaking changes list
- Email: Notify consumers via email 6 months before
- Metrics: Monitor usage of v1 via Prometheus `api_requests_total{version="v1"}`

**Phase 2: Sunset**:
- After Sunset date, return 410 Gone or 404 with message and link to v2, or still support but with degraded performance
- Give 6-12 months notice

**Phase 3: Removal**:
- Remove v1 code after 0 traffic for 1 month

### 22. Testing APIs Expanded

**Unit Testing Controller (Spring Boot)**:
```java
@WebMvcTest(UserController.class)
class UserControllerTest {
  @MockBean UserService userService;
  @Autowired MockMvc mockMvc;

  @Test
  void shouldGetUser() throws Exception {
    when(userService.getUser(123L)).thenReturn(new User(123L, "John"));
    mockMvc.perform(get("/api/v1/users/123")
      .header("Authorization", "Bearer token"))
      .andExpect(status().isOk())
      .andExpect(jsonPath("$.name").value("John"));
  }
}
```

**Integration Testing with Testcontainers + RestAssured**:
```java
@SpringBootTest(webEnvironment = RANDOM_PORT)
@Testcontainers
class UserIntegrationTest {
  @Container static PostgreSQLContainer<?> pg = new PostgreSQLContainer<>("postgres:15");
  @LocalServerPort int port;
  @Autowired UserRepository repo;

  @Test
  void shouldCreateUser() {
    given().port(port).contentType(JSON).body(new CreateUserRequest("John","a@b.com"))
    .when().post("/api/v1/users")
    .then().statusCode(201).body("name", equalTo("John")).header("Location", containsString("/users/"));
    
    assertTrue(repo.findByEmail("a@b.com").isPresent());
  }
}
```

**Contract Testing with Pact (Consumer-Driven)**:
- Consumer defines expected contract (e.g. GET /users/123 returns { id, name, email }), Pact generates pact file, Provider verifies pact file in CI, ensures provider doesn't break consumer
- Important for microservices: User service (consumer) depends on Order service (provider), contract ensures Order service doesn't break User service

**Load Testing with k6**:
```js
import http from 'k6/http';
import { check, sleep } from 'k6';
export const options = {
  stages: [
    { duration: '1m', target: 100 }, // ramp up 100 VUs
    { duration: '3m', target: 100 }, // stay 100
    { duration: '1m', target: 0 }, // ramp down
  ],
  thresholds: {
    http_req_failed: ['rate<0.01'], // error <1%
    http_req_duration: ['p(95)<200'], // P95 <200ms
  },
};
export default function() {
  const res = http.get('https://api.example.com/api/v1/users/123', { headers: { Authorization: 'Bearer token' } });
  check(res, { 'status 200': (r) => r.status === 200, 'latency <200ms': (r) => r.timings.duration < 200 });
  sleep(1);
}
```

### 23. Monitoring & Alerting for APIs

**Metrics to Monitor (RED + USE)**:
- Rate: QPS per endpoint `rate(http_requests_total[5m])`
- Errors: Error rate % `rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m])`
- Duration: Latency P50, P95, P99 `histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))`
- Saturation: CPU, memory, DB connections, thread pool queue
- Business: Orders per min, payment success rate, active users

**Dashboard**:
- Row 1: QPS, Error %, P95 latency, CPU, Memory per service
- Row 2: JVM Heap, GC pause, Thread count, DB connections active/idle, Redis hit ratio
- Row 3: Business metrics
- Row 4: Logs panel filtered by error, Traces slow >500ms

**Alerting**:
```yaml
- alert: HighErrorRate
  expr: rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m]) > 0.05
  for: 5m
  labels: { severity: critical }
  annotations: { summary: "High error rate {{ $value }}", runbook: "https://runbooks.example.com/high-error-rate" }

- alert: HighLatency
  expr: histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m])) > 0.5
  for: 5m
  labels: { severity: warning }
```

### 24. API Gateway Implementation (Kong Example)

```yaml
# Kong declarative config
_format_version: "3.0"
services:
- name: user-service
  url: http://user-service:8080
  routes:
  - name: user-route
    paths: ["/api/v1/users"]
    methods: [GET, POST, PUT, PATCH, DELETE]
  plugins:
  - name: jwt
    config:
      secret_is_base64: false
      run_on_preflight: false
  - name: rate-limiting
    config:
      minute: 100
      policy: redis
      redis_host: redis
      limit_by: consumer
  - name: cors
    config:
      origins: ["https://app.example.com"]
      methods: [GET, POST, PUT, PATCH, DELETE, OPTIONS]
      headers: [Authorization, Content-Type, Idempotency-Key]
      credentials: true
  - name: prometheus
  - name: opentelemetry
    config:
      endpoint: http://otel-collector:4317
```

---

This expanded best practices guide ensures production-grade API design for SDE3.

---

## Expanded Again: API Governance, Breaking Changes, SDK Generation

### 25. API Governance - For Large Org with Many Teams

**What**: Rules and processes for designing, building, publishing, versioning, deprecating APIs consistently across org

**Why**: Without governance, each team designs API differently (different naming, error formats, auth, pagination), inconsistency, bad UX for consumers, security risks

**Governance Practices**:

1. **API Design Guidelines**: Document standards: Naming (snake_case vs camelCase), versioning (URI /v1/), pagination (cursor), filtering, sorting, error format, auth (JWT), rate limiting, security headers, etc - all teams follow same guidelines
   - Example: Google API Design Guide, Microsoft REST API Guidelines, Zalando RESTful API Guidelines

2. **API Review Process**: New API design doc must be reviewed by API guild (senior engineers) before implementation, similar to code review but for API design
   - Design doc includes: Resources, URIs, methods, status codes, schemas, examples, auth, rate limiting, pagination, error handling

3. **Linting**: Use Spectral to lint OpenAPI specs against guidelines automatically in CI
```yaml
# spectral.yaml - lint OpenAPI
rules:
  operation-operationId: error
  operation-tags: error
  no-eval-in-markdown: error
  openapi-tags: error
```

4. **Breaking Change Detection**: Use tools like openapi-diff to detect breaking changes in PR, fail CI if breaking change without version bump
```bash
openapi-diff old.yaml new.yaml --fail-on-breaking
# Fails if breaking change detected (e.g. removed required field, changed type)
```

5. **API Catalog**: Central catalog of all APIs in org (e.g. Backstage catalog), searchable, with docs, owners, status (production, deprecated)

6. **Deprecation Policy**: Standard policy for deprecating APIs: Announce 6 months before, Sunset header, migration guide, monitoring usage, email通知

7. **Security Review**: Security team reviews new APIs for OWASP Top 10, auth, rate limiting

**Tools**: Backstage (Spotify IDP), SwaggerHub (API design + governance), Stoplight, Optic (API diff, linting)

### 26. Breaking Changes - How to Handle Without Breaking Clients

**What is Breaking Change?**
- Removing field, removing endpoint, renaming field, changing type (string to int), making optional field required, changing status code, removing enum value, changing auth

**What is Non-Breaking?**
- Adding optional field, adding endpoint, adding enum value, adding optional query param

**Expand-Contract Pattern (For DB and API)**:

**For API**:
1. **Expand**: Add new field optional, deploy, clients can use new field but old clients ignore (backward compatible)
   - Example: Add `fullName` new field, keep `firstName` and `lastName` old fields
   ```json
   // v1
   { "firstName": "John", "lastName": "Doe" }
   // v1 expanded (backward compatible) - add fullName optional
   { "firstName": "John", "lastName": "Doe", "fullName": "John Doe" }
   ```
2. **Migrate**: Update all clients to use new field `fullName`, monitor usage of old fields via metrics
3. **Contract**: After all clients migrated (0 usage of old fields for 1 month), remove old fields `firstName`, `lastName` in next version v2 (breaking change but okay because no clients use old fields)

**For DB** (similar):
1. Expand: Add new column nullable, deploy code that writes to both old and new columns
2. Migrate: Backfill old data to new column via batch job, update code to read from new column
3. Contract: Remove old column after all code uses new column

**Versioning for Breaking Changes**:
- When breaking change needed, create v2 endpoint `/api/v2/users` with breaking changes, keep v1 for 6-12 months, monitor v1 usage, give notice, then sunset v1

**Sunset Flow**:
```
Day 0: Release v2, announce v1 deprecated with Sunset header + docs + email
Day 0-180: Support both v1 and v2, monitor v1 usage via metrics, help consumers migrate
Day 180: Sunset v1 - return 410 Gone or 404 with link to v2, or still support but degraded
Day 210: Remove v1 code after 0 traffic
```

### 27. SDK Generation - From OpenAPI to Client SDKs

**Why**: Provide client SDKs for popular languages (JS, Python, Java, Go) so consumers don't need to manually write fetch calls, SDK handles auth, retries, pagination, errors

**How**: Generate SDKs from OpenAPI spec automatically via tools

**Tools**:
- **OpenAPI Generator**: Generates SDKs for 50+ languages from OpenAPI spec, most popular
```bash
openapi-generator generate -i openapi.yaml -g typescript-fetch -o ./sdk/ts
openapi-generator generate -i openapi.yaml -g python -o ./sdk/python
openapi-generator generate -i openapi.yaml -g java -o ./sdk/java
```
- **Swagger Codegen**: Older, similar
- **Fern**: Modern, generates beautiful SDKs with docs, used by many startups (e.g. Vercel, Stripe-like)
- **Stainless**: Generates SDKs from OpenAPI with great DX

**SDK Example (Generated TypeScript)**:

```ts
// Generated SDK - consumer uses like this
import { ApiClient } from './sdk/ts';

const client = new ApiClient({ baseUrl: 'https://api.example.com', apiKey: 'abc' });

// Fully typed, auto handles auth, retries, errors
const user = await client.users.getById({ id: '123' }); // typed as User
const users = await client.users.list({ role: 'admin', page: 2, limit: 20 }); // typed
await client.users.create({ name: 'John', email: 'a@b.com' }); // validates via Zod

// With pagination helper
for await (const user of client.users.listPaginated({ role: 'admin' })) {
  console.log(user);
}
```

**Best Practices for SDKs**:
- Provide for popular languages: JS/TS, Python, Java, Go, Ruby
- Include: Auth handling, retries with backoff, pagination helpers, error handling with typed errors, request/response validation
- Docs: Include examples, migration guides
- Versioning: SDK version matches API version (e.g. SDK v1 for API v1)
- Publish to package managers: npm, PyPI, Maven, Go modules

### 28. API Analytics & Monetization

**Analytics**: Track API usage per consumer, per endpoint, per version, latency, error rate, QPS

**Tools**: Moesif, Postman API analytics, custom via Prometheus + Grafana + ELK

**Metrics to Track**:
- QPS per consumer (who uses most)
- Latency P95 per endpoint (which endpoints slow)
- Error rate per endpoint (which endpoints failing)
- Version usage (how many still on v1)
- Top consumers, top endpoints, geographic

**Monetization** (if public API paid):
- Freemium: Free tier 100 req/day, paid tiers 10k, 100k, unlimited
- Pay per use: $0.001 per request
- Tiered: Basic $10/month 10k req, Pro $100/month 100k req, Enterprise custom
- Implementation: Rate limiting per tier via API Gateway, billing via Stripe, usage tracking via Redis + DB

**Example: Stripe-like API monetization**:
```
Free: 100 req/day, no support
Basic $10/month: 10k req/day, email support
Pro $100/month: 100k req/day, priority support, webhooks
Enterprise $1000/month: Unlimited, SLA 99.99%, dedicated support, custom features
```

### 29. GraphQL vs REST vs gRPC vs tRPC Decision Matrix Expanded

| Factor | REST | GraphQL | gRPC | tRPC | WebSocket | Webhooks |
|--------|------|---------|------|------|-----------|----------|
| **Type Safety** | No (need OpenAPI + codegen) | Yes (schema + codegen) | Yes (proto + codegen) | Yes best (TS inference no codegen) | No | No |
| **Browser Support** | Excellent native fetch | Excellent | Needs proxy (grpc-web) | Excellent (fetch) | Excellent | N/A server-to-server |
| **Learning Curve** | Easy | Medium | Medium-Hard | Easy (TS only) | Easy-Med | Easy |
| **Caching** | Easy HTTP cache + CDN | Hard (single endpoint, need persisted queries) | No | No (like GraphQL) | No | No |
| **File Upload** | Easy multipart | Hard (need multipart spec) | Easy streaming | Easy | Easy binary | N/A |
| **Real-time** | No (polling) | Yes via subscriptions (WS) | Yes via streaming | Yes via subscriptions | Yes bi-di | Yes event-driven |
| **Performance** | Medium (JSON text) | Medium (JSON) | High (protobuf binary, HTTP/2) | Medium (JSON) | Low overhead after handshake | Medium |
| **Payload Size** | Medium JSON | Medium JSON (only requested fields) | Small binary (3-10x smaller) | Medium JSON | Small frames | Medium JSON |
| **Ecosystem** | Largest, mature | Large, growing | Medium, growing | Small but growing fast (TS) | Large | Large |
| **Public API** | Excellent (standard) | Good (many public GraphQL APIs) | Bad (not browser friendly) | Bad (TS only) | Good for real-time | Good for server-to-server |
| **Internal Microservices** | Okay but slower | Okay for BFF aggregation | Excellent (fast, streaming, polyglot) | Okay for TS microservices | Okay for real-time | Okay for events |
| **When Use** | Public APIs, CRUD, simple, cacheable, team familiar - default | Flexible frontend (web vs mobile different fields), BFF aggregation, over-fetching problem | Internal high perf, low latency, streaming, polyglot | Fullstack TS internal, type-safe without codegen, T3 Stack | Chat, gaming, collaborative bi-di real-time | Server-to-server event notifications (GitHub, Stripe) |

**Decision Flowchart**:

```
Need real-time?
  Yes -> Both client and server need to send frequently?
    Yes -> WebSocket (chat, gaming, collaborative)
    No only server pushes -> SSE (live feed, notifications)
  No -> Server-to-server event notification?
    Yes -> Webhooks (GitHub push, Stripe payment)
    No -> Internal microservices high perf <10ms?
      Yes -> gRPC (7x faster, binary, streaming) or tRPC if TS only
      No -> Flexible frontend needs or aggregate many microservices?
        Yes -> GraphQL (BFF, avoid over-fetching, single request multiple resources)
        No -> Public API or simple CRUD?
          Yes -> REST (default, cacheable, browser native, standard)
```

### 30. API Security Advanced - OAuth2 Flows Detailed

**OAuth2 Roles**: Resource Owner (user), Client (app), Authorization Server (auth server), Resource Server (API)

**Flows**:

1. **Authorization Code + PKCE (Recommended for web, mobile, SPA - most secure)**:
   ```
   1. User clicks Login in Client (e.g. React app)
   2. Client redirects to Authorization Server /authorize?response_type=code&client_id=abc&redirect_uri=https://app.com/callback&scope=openid profile&code_challenge=xyz&code_challenge_method=S256&state=random
   3. Auth Server shows login page, user logs in
   4. Auth Server redirects to Client callback with code: https://app.com/callback?code=auth_code&state=random
   5. Client verifies state (prevent CSRF), then exchanges code + code_verifier for tokens via POST /token { code, client_id, code_verifier, redirect_uri }
   6. Auth Server validates code + code_verifier (PKCE prevents code interception), returns access_token + id_token + refresh_token
   7. Client uses access_token for API calls: Authorization: Bearer access_token
   8. When access_token expires (15 min), client uses refresh_token to get new access_token via POST /token { grant_type=refresh_token, refresh_token }
   ```
   - PKCE: Proof Key for Code Exchange, prevents authorization code interception attack, required for public clients (SPA, mobile)
   - State: Random value to prevent CSRF

2. **Client Credentials (For service-to-service, no user)**:
   ```
   Service A -> Auth Server POST /token { grant_type=client_credentials, client_id=serviceA, client_secret=secret, scope=api }
   Auth Server returns access_token
   Service A uses access_token to call Service B API
   ```
   - Use for: Microservices internal auth, no user involved

3. **Implicit Flow (Deprecated, don't use)**:
   - Old flow for SPA, returns token directly in URL fragment, insecure, use Auth Code + PKCE instead

4. **Password Flow (Deprecated, don't use)**:
   - Client collects username/password and sends to Auth Server, insecure, use Auth Code + PKCE

**OpenID Connect (OIDC)**: Identity layer on top of OAuth2, adds id_token (JWT with user info like name, email, profile), /userinfo endpoint, discovery via /.well-known/openid-configuration

**JWT Structure**:
```
Header: { "alg": "RS256", "typ": "JWT" }
Payload: { "sub": "123", "name": "John", "email": "john@example.com", "role": "admin", "iss": "https://auth.example.com", "aud": "api.example.com", "iat": 1713000000, "exp": 1713000900, "jti": "unique-id" }
Signature: RS256(header + payload, private key)
Token: base64(header).base64(payload).signature
```

**Best Practices**:
- Short expiry: Access 15 min, Refresh 7 days rotation (refresh token rotation - new refresh token each use, old invalidated, prevents replay)
- Store access token in memory (JS variable), refresh token in HttpOnly Secure SameSite=Strict cookie (not localStorage - XSS steals)
- Validate signature, exp, iss, aud, jti on server
- Use RS256 (asymmetric) for microservices (auth server signs with private key, microservices verify with public key, no need share secret)
- Use jti (JWT ID) for revocation tracking in Redis

