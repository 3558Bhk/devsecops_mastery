# REST API - Complete Guide - From Basics to Advanced

## What is REST?

- **REST**: REpresentational State Transfer, architectural style for distributed hypermedia systems, defined by Roy Fielding in 2000 PhD dissertation
- Not protocol, not standard, but style with constraints
- Uses HTTP as transport, but can use other protocols theoretically
- Resource based, stateless, client-server

## REST Constraints (6 Constraints)

1. **Client-Server**: Separation, client UI, server data, independent evolution
2. **Stateless**: Each request contains all info needed, server doesn't store client session, any server can handle any request, scalable
3. **Cacheable**: Responses must define themselves cacheable or not (Cache-Control), improves performance
4. **Uniform Interface**: 4 sub-constraints:
   - Resource identification in requests (URI)
   - Resource manipulation through representations (JSON)
   - Self-descriptive messages (MIME types, status codes)
   - HATEOAS (Hypermedia as Engine of Application State) - optional, advanced
5. **Layered System**: Client doesn't know if connected to end server or intermediary (proxy, gateway, CDN), improves scalability, security
6. **Code on Demand (Optional)**: Server can send executable code to client (e.g. JavaScript)

## Resources & URIs

- **Resource**: Anything important enough to be referenced: User, Order, Product, Collection
- **URI**: Identifier for resource: `/users`, `/users/123`, `/users/123/orders`
- **Collection**: `/users` - list of users
- **Element**: `/users/123` - single user
- **Sub-collection**: `/users/123/orders` - orders of user 123
- **Best Practices for URIs**:
  - Nouns not verbs: `/users` not `/getUsers` (verb is HTTP method)
  - Plural: `/users` not `/user` for collection, but both acceptable if consistent
  - Lowercase, hyphen for readability: `/user-profiles` not `/userProfiles` or `/user_profiles`
  - No trailing slash: `/users` not `/users/`
  - No file extensions: `/users` not `/users.json` (use Accept header)
  - Hierarchy via `/`: `/users/123/orders/456`
  - Filtering, sorting, pagination via query params not path: `/users?role=admin&sort=name&page=2`

## HTTP Methods (Verbs) - CRUD Mapping

| Method | CRUD | Idempotent | Safe | Cacheable | Body | Use | Status on Success |
|--------|------|------------|------|-----------|------|-----|-------------------|
| **GET** | Read | Yes | Yes | Yes | No (but can, not recommended) | Retrieve resource(s) | 200 OK with body, 404 if not found |
| **POST** | Create | No | No | No (but can) | Yes | Create new resource, or action (e.g. /users/123/activate) | 201 Created + Location header, 200 if action |
| **PUT** | Full Update / Create if not exists (upsert) | Yes | No | No | Yes | Replace entire resource, client provides full representation, id must be in URI | 200 with body or 204 No Content if no body |
| **PATCH** | Partial Update | No (can be idempotent if designed) | No | No | Yes | Partial update, only fields to update | 200 with body |
| **DELETE** | Delete | Yes | No | No | No (can have) | Delete resource | 204 No Content, or 200 with status |
| **HEAD** | Read headers only | Yes | Yes | Yes | No | Like GET but only headers, for checking existence, size | 200 no body |
| **OPTIONS** | - | Yes | Yes | No | No | CORS preflight, allowed methods | 200 with Allow header |
| **TRACE, CONNECT** | Rare | - | - | - | - | Debugging, tunneling | - |

### Idempotent vs Safe

- **Safe**: Doesn't modify server state, only read (GET, HEAD, OPTIONS)
- **Idempotent**: Multiple same requests have same effect as one (GET, PUT, DELETE, HEAD, OPTIONS are idempotent, POST, PATCH not idempotent generally)
- Why important? Client can safely retry idempotent methods on network failure

### PUT vs PATCH vs POST

```
POST /users
Body: { "name": "John", "email": "a@b.com" }
=> Creates new user, server assigns ID 123, returns 201 Location: /users/123

PUT /users/123
Body: { "name": "John", "email": "john@example.com", "age": 30 } // full object required
=> Replaces entire user 123 with new data, if not exists may create (upsert), idempotent

PATCH /users/123
Body: { "email": "new@example.com" } // only field to update
=> Partial update email only, other fields unchanged
```

- Use PUT when client knows ID and provides full resource, PATCH when partial, POST when server assigns ID or for actions

## HTTP Status Codes - Complete (Already covered but here with REST context)

### 2xx Success
- **200 OK**: GET success, PUT success with body, PATCH success
- **201 Created**: POST created, must include Location header `/users/123`
- **202 Accepted**: Request accepted but processing async (e.g. batch job, queue), return job ID to poll
- **204 No Content**: Success but no body to return (DELETE success, PUT success no body)

### 3xx Redirection
- **301 Moved Permanently**: Resource moved permanently, client should use new URL, SEO juice transferred, cached
- **302 Found**: Temporary redirect, client should continue using old URL for future, not cached
- **304 Not Modified**: Cached version still valid, client uses cached, for conditional GET with ETag/Last-Modified

### 4xx Client Errors
- **400 Bad Request**: Invalid syntax, validation fail (e.g. missing required field, invalid JSON)
- **401 Unauthorized**: No auth or invalid auth, missing token, expired token, should include WWW-Authenticate header
- **403 Forbidden**: Authenticated but no permission, e.g. user trying to access admin endpoint
- **404 Not Found**: Resource doesn't exist
- **405 Method Not Allowed**: Method not allowed on resource, e.g. GET on /users but only POST allowed, must include Allow header
- **406 Not Acceptable**: Server can't produce response matching Accept header (e.g. client asks XML but server only JSON)
- **408 Request Timeout**: Client didn't send request in time
- **409 Conflict**: Conflict with current state, e.g. duplicate email, version conflict (optimistic locking)
- **410 Gone**: Resource permanently deleted, no longer available, don't try again
- **412 Precondition Failed**: Condition in If-Match/If-None-Match failed
- **413 Payload Too Large**: Request body too large
- **415 Unsupported Media Type**: Content-Type not supported (e.g. server expects JSON but client sends XML)
- **422 Unprocessable Entity**: Syntax correct but semantic error (e.g. end date before start date, validation business logic)
- **429 Too Many Requests**: Rate limiting, must include Retry-After header

### 5xx Server Errors
- **500 Internal Server Error**: Generic server crash, unhandled exception
- **501 Not Implemented**: Method not implemented
- **502 Bad Gateway**: Invalid response from upstream (e.g. Nginx -> Node down, Node returned invalid)
- **503 Service Unavailable**: Overloaded or maintenance, include Retry-After
- **504 Gateway Timeout**: Upstream didn't respond in time (e.g. DB slow, downstream service slow)

## Request & Response Format

### Request

```
GET /api/v1/users/123?fields=id,name,email HTTP/1.1
Host: api.example.com
Authorization: Bearer eyJhbGciOiJIUzI1NiIs...
Accept: application/json
Accept-Language: en-US
User-Agent: Mozilla/5.0
X-Request-ID: abc-123-def-456
If-None-Match: "etag-123"

POST /api/v1/users HTTP/1.1
Host: api.example.com
Content-Type: application/json
Content-Length: 56
Authorization: Bearer ...

{
  "name": "John Doe",
  "email": "john@example.com",
  "age": 30
}
```

### Response

```
HTTP/1.1 200 OK
Content-Type: application/json
Content-Length: 123
Cache-Control: max-age=60, public
ETag: "etag-123"
X-Request-ID: abc-123-def-456
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 99

{
  "id": "123",
  "name": "John Doe",
  "email": "john@example.com",
  "age": 30,
  "createdAt": "2026-09-13T10:00:00Z",
  "links": {
    "self": "/api/v1/users/123",
    "orders": "/api/v1/users/123/orders"
  }
}
```

### Error Response Format (Standardize)

```json
{
  "error": {
    "code": "USER_NOT_FOUND",
    "message": "User with ID 123 not found",
    "details": [
      { "field": "email", "message": "Invalid email format" }
    ],
    "requestId": "abc-123",
    "timestamp": "2026-09-13T10:00:00Z",
    "documentation": "https://docs.example.com/errors/USER_NOT_FOUND"
  }
}
```

- Always include code (machine readable), message (human readable), requestId for tracing, don't expose stack trace in prod

## Best Practices (Interview Gold - Must Mention)

### 1. Versioning

- **URL Versioning** (Most common): `/api/v1/users`, `/api/v2/users`
  - Pros: Simple, visible, cache friendly, easy to test
  - Cons: URL pollution
- **Header Versioning**: `Accept: application/vnd.example.v1+json` or custom `X-API-Version: 1`
  - Pros: Clean URL
  - Cons: Harder to test in browser, cache harder
- **Query Param**: `/api/users?version=1` - not recommended
- **Recommendation**: URL versioning for public APIs, header for internal if you prefer clean URLs
- **Versioning Strategy**: Semantic versioning, never break existing v1, add new fields optional, deprecate old fields with Sunset header

### 2. Pagination

- **Offset-based**: `/users?page=2&limit=20` or `?offset=20&limit=20`
  - Pros: Simple, jump to page
  - Cons: Slow for large offset (DB scans and discards), inconsistent if data changes between pages (duplicate/missing)
  - Response: Include total count, total pages, links
```json
{
  "data": [...],
  "pagination": {
    "page": 2,
    "limit": 20,
    "total": 1000,
    "totalPages": 50,
    "hasNext": true,
    "hasPrev": true
  },
  "links": {
    "self": "/users?page=2&limit=20",
    "next": "/users?page=3&limit=20",
    "prev": "/users?page=1&limit=20"
  }
}
```

- **Cursor-based (Keyset)**: `/users?cursor=eyJpZCI6MTIzfQ&limit=20` where cursor = base64 of last item ID/timestamp
  - Pros: Fast (WHERE id > lastId), consistent even if data changes, good for infinite scroll
  - Cons: Can't jump to random page, only next/prev
  - Use for: Large datasets, real-time feeds (Twitter, Facebook)
  - Recommended for SDE3 for large scale

### 3. Filtering, Sorting, Searching, Field Selection

- **Filtering**: `/users?role=admin&status=active&age[gte]=18` or `?filter[role]=admin`
- **Sorting**: `/users?sort=-createdAt,name` (- for desc, comma for multiple)
- **Searching**: `/users?q=John` or `/users?search=John`
- **Field Selection (Sparse Fieldsets)**: `/users?fields=id,name,email` - reduces payload, solves over-fetching partially
- **Embedding / Expanding**: `/users?expand=orders` or `/users/123?include=orders` to include related resources, avoid N+1 API calls

### 4. Idempotency

- **Why**: Network failures, client retries may cause duplicate creation (e.g. payment double charge)
- **How**: Client sends `Idempotency-Key: uuid` header for POST, server stores key + response in Redis/DB, if same key seen returns cached response without re-executing
- **Implementation**:
```java
@PostMapping("/payments")
public ResponseEntity<Payment> createPayment(@RequestHeader("Idempotency-Key") String key, @RequestBody PaymentRequest req) {
  String cacheKey = "idempotency:" + key;
  if (redis.exists(cacheKey)) {
    return ResponseEntity.ok(redis.get(cacheKey)); // return cached
  }
  Payment payment = paymentService.process(req); // process
  redis.setex(cacheKey, 24*3600, payment); // cache 24h
  return ResponseEntity.status(201).body(payment);
}
```
- **Use for**: POST payments, order creation - critical

### 5. Security

- **HTTPS only**: Never HTTP in prod
- **Authentication**: JWT Bearer token in Authorization header `Authorization: Bearer <token>`, not in URL, OAuth2
- **Authorization**: RBAC check server side
- **Rate Limiting**: Per user/IP, return 429 + Retry-After
- **Input Validation**: Whitelist validation, reject invalid, use @Valid, sanitize
- **CORS**: Configure allowed origins, not `*` with credentials
- **Security Headers**: HSTS, CSP, X-Content-Type-Options nosniff, etc
- **No sensitive data in URL**: Passwords, tokens not in query params (logged in logs, browser history)
- **Error handling**: Don't expose stack trace, DB errors to client

### 6. Caching

- **Cache-Control header**: `Cache-Control: public, max-age=60` (60 sec), `private, no-store` for private data, `no-cache` must revalidate
- **ETag**: `ETag: "abc123"` hash of content, client sends `If-None-Match: "abc123"`, server returns 304 Not Modified if same, saves bandwidth
- **Last-Modified**: Similar but timestamp
- **Where cache**: Browser, CDN, Reverse Proxy (Nginx), Application (Redis)
- **Cache invalidation**: TTL, event-based invalidation via queue

### 7. HATEOAS (Hypermedia as Engine of Application State) - Level 3 Richardson Maturity Model

- Response includes links to related actions, client doesn't need to know URLs beforehand, discovers via links
- Level 0: Single endpoint POST all (SOAP like)
- Level 1: Multiple URIs for resources
- Level 2: HTTP methods + status codes properly (most REST APIs are here)
- Level 3: HATEOAS - includes links

```json
{
  "id": "123",
  "name": "John",
  "_links": {
    "self": { "href": "/users/123" },
    "orders": { "href": "/users/123/orders" },
    "update": { "href": "/users/123", "method": "PUT" },
    "delete": { "href": "/users/123", "method": "DELETE" }
  }
}
```

- Pros: Discoverability, loose coupling (client doesn't hardcode URLs)
- Cons: Complexity, overhead, not many clients use, most APIs stop at Level 2
- Use: Public APIs that need to evolve without breaking clients, but for internal Level 2 enough

### 8. Bulk Operations & Batch

- **Bulk Create**: `POST /users/bulk` with array body `[{...},{...}]` or `POST /users` with array
- **Batch**: `POST /batch` with multiple operations
```json
{
  "operations": [
    { "method": "POST", "path": "/users", "body": {...} },
    { "method": "PUT", "path": "/users/123", "body": {...} }
  ]
}
```
- Response: 207 Multi-Status with status per operation

### 9. Async Operations (Long Running)

- For operations >500ms (e.g. report generation, video transcoding)
- Flow:
  1. Client POST /reports -> Server returns 202 Accepted + Location: /jobs/123
  2. Client polls GET /jobs/123 -> returns status: processing, 50% complete
  3. When done, job status completed + result URL /reports/456
  4. Client GET /reports/456 gets result
- Or use Webhook: Client provides callback URL, server POSTs result when done
- Or use WebSocket/SSE for real-time progress

### 10. File Uploads

- **Single file**: `POST /users/123/avatar` with `Content-Type: multipart/form-data`
- **Large file**: Chunked upload, resumable via `Content-Range` or S3 presigned URL for direct upload to S3 (better for large files, reduces server load)
- **S3 Presigned URL Flow**:
  1. Client requests upload URL: POST /uploads with filename
  2. Server generates S3 presigned URL (PUT) with expiry 1 hour and returns
  3. Client directly PUT file to S3 via presigned URL (bypasses server)
  4. Client notifies server upload complete: POST /uploads/complete
  5. Server verifies and saves metadata

### 11. Webhooks

- User registers URL to be notified when event happens, server POSTs to that URL
- Example: GitHub webhook on push, Stripe webhook on payment success
- Implementation: User POST /webhooks with url and events, server stores, on event POSTs to url with signature header `X-Hook-Signature` HMAC for verification, retries with exponential backoff if fails

### 12. Documentation

- **OpenAPI / Swagger**: Standard for REST API docs, defines paths, methods, schemas, examples, generates interactive UI at /swagger-ui.html
- Tools: Swagger UI, ReDoc, Stoplight
- Example OpenAPI snippet:
```yaml
openapi: 3.0.0
info:
  title: User API
  version: 1.0.0
paths:
  /users/{id}:
    get:
      summary: Get user by ID
      parameters:
        - name: id
          in: path
          required: true
          schema: { type: string }
      responses:
        '200':
          description: User found
          content:
            application/json:
              schema: { $ref: '#/components/schemas/User' }
        '404':
          description: User not found
```

- **Postman Collections**: Shareable, executable docs

## Complete REST API Example - E-commerce

```
Base URL: https://api.example.com/api/v1

Auth: Bearer JWT

Endpoints:

# Users
GET    /users?role=admin&sort=-createdAt&page=2&limit=20&fields=id,name,email
POST   /users
GET    /users/{id}
PUT    /users/{id} (full update)
PATCH  /users/{id} (partial)
DELETE /users/{id}
GET    /users/{id}/orders?status=completed

# Products
GET    /products?q=iphone&category=electronics&price[gte]=100&sort=-rating&fields=id,name,price
POST   /products (admin)
GET    /products/{id}
PUT    /products/{id}
DELETE /products/{id}
GET    /products/{id}/reviews

# Orders
POST   /orders (create order)
GET    /orders/{id}
GET    /users/{id}/orders
POST   /orders/{id}/cancel
POST   /orders/{id}/pay

# Cart
GET    /cart
POST   /cart/items { productId, quantity }
PUT    /cart/items/{itemId} { quantity }
DELETE /cart/items/{itemId}

# Payments
POST   /payments { orderId, method } + Idempotency-Key header
GET    /payments/{id}

# Webhooks
POST   /webhooks { url, events: ["order.created", "payment.succeeded"] }
GET    /webhooks
DELETE /webhooks/{id}

# Async
POST   /reports/sales { startDate, endDate } => 202 Accepted Location: /jobs/123
GET    /jobs/{id}
GET    /reports/{id} when job completed

# Bulk
POST   /products/bulk [{...},{...}]

# File upload
POST   /products/{id}/images (multipart)
POST   /uploads/presigned-url { filename, contentType } => { uploadUrl, fileUrl }
```

## Performance Optimization for REST

- **Gzip/Brotli compression**: `Accept-Encoding: gzip`, reduces JSON 70-80%
- **Pagination**: Limit response size
- **Field selection**: `?fields=id,name` reduces payload
- **HTTP/2**: Multiplexing, header compression, faster
- **Keep-Alive**: Reuse TCP connections
- **Caching**: ETag, Cache-Control, Redis
- **Connection pooling**: For DB and HTTP clients
- **Rate limiting**: Protect backend

## Testing REST APIs

- **Unit**: Mock service layer, test controller
- **Integration**: Testcontainers + RestAssured
- **Contract**: Pact
- **E2E**: Postman/Newman, Cypress
- **Load**: k6, JMeter

## Interview Q & A

**Q: How to design REST API for file upload large 1GB?**
- Don't upload via server (memory, timeout), use S3 presigned URL for direct upload to S3, or chunked resumable upload with Content-Range, return upload ID, client uploads chunks, server assembles

**Q: How to handle versioning without breaking clients?**
- URL versioning /v1/, never remove fields, only add optional fields, deprecate with Sunset header and docs, support 2 versions simultaneously, monitor usage of old version, give 6 months notice before sunset

**Q: How to ensure idempotency for payment API?**
- Idempotency-Key header, store key+response in Redis with TTL 24h, if same key return cached response, key should be UUID generated client side, server checks

**Q: Difference between 401 and 403?**
- 401 who are you? Not authenticated. 403 I know who you are but you don't have permission.

**Q: How to handle HATEOAS? Do you use?**
- Most internal APIs Level 2 enough (proper methods + status), HATEOAS Level 3 useful for public APIs that need to evolve without breaking, but adds complexity, we use Level 2 with OpenAPI docs, links for pagination

This is complete REST API guide. For other APIs see other_apis_complete.md

---

## Expanded: Richardson Maturity Model Detailed

### Level 0: The Swamp of POX (Plain Old XML)
- Single endpoint, e.g. POST /api with action in body, like SOAP over HTTP
- Example: POST /api { "action": "getUser", "id": 123 }
- Not RESTful

### Level 1: Resources
- Multiple URIs for resources, but only one method (usually POST)
- Example: POST /users/123, POST /users, POST /users/123/orders
- Better but not using HTTP methods

### Level 2: HTTP Verbs
- Proper use of HTTP methods + status codes + resources
- Example: GET /users/123 -> 200, POST /users -> 201, PUT /users/123 -> 200, DELETE /users/123 -> 204, proper status codes
- Most production REST APIs are Level 2 - this is what interviewers expect

### Level 3: HATEOAS
- Hypermedia controls (links) in responses, client discovers actions via links, not hardcoded URLs
- Example with HAL format:
```json
{
  "id": "123",
  "name": "John",
  "_links": {
    "self": { "href": "/users/123" },
    "orders": { "href": "/users/123/orders" },
    "update": { "href": "/users/123", "method": "PUT" },
    "delete": { "href": "/users/123", "method": "DELETE" }
  },
  "_embedded": {
    "orders": [{ "id": "456", "total": 100 }]
  }
}
```
- Pros: Discoverability, loose coupling, server can change URLs without breaking clients (client follows links), evolvability
- Cons: Complexity, overhead, most clients don't use, need HAL or JSON-LD or Siren format, overkill for internal APIs
- Use: Public APIs that need long-term evolvability (e.g. GitHub API uses some HATEOAS with Link header)

## Expanded: Advanced Versioning Strategies

### 1. URI Versioning (Most Common)
```
GET /api/v1/users/123
GET /api/v2/users/123
```
- Pros: Simple, visible, cache friendly (different URLs cached separately), easy to test in browser, easy to route in gateway
- Cons: URL pollution, breaking REST principle (URI should represent resource not version, version is representation)
- Implementation: In Spring Boot `@RequestMapping("/api/v1/users")`, in gateway route /v1/* to v1 service

### 2. Header Versioning
```
GET /api/users/123
Accept: application/vnd.example.v1+json
or
X-API-Version: 1
or
Accept-Version: v1
```
- Pros: Clean URLs (resource focused), version is representation
- Cons: Harder to test (need set header), cache harder (need Vary header), not visible in browser
- Implementation: Spring Boot `@GetMapping(value="/users/{id}", headers="X-API-Version=1")`

### 3. Query Param Versioning
```
GET /api/users/123?version=1
```
- Pros: Simple
- Cons: Not RESTful, cache pollution, query params for filtering not versioning, not recommended

### 4. Content Negotiation via Accept Header with Vendor MIME
```
Accept: application/vnd.example.user.v1+json
Accept: application/vnd.example.user.v2+json
```
- Most RESTful pure, but complex

### 5. No Versioning (GraphQL style - Evolution)
- Never version, only add optional fields, never remove, deprecate with @deprecated, use expand-contract pattern
- Pros: No versioning overhead, single version
- Cons: Need discipline, can't do breaking changes, need backward compatibility forever
- Use for: Internal APIs where you control all clients, GraphQL does this

### Best Practice for SDE3
- Public API: URI versioning /v1/ for simplicity
- Internal: Header versioning or no versioning with evolution if you control clients
- Always support at least 2 versions simultaneously, monitor usage via metrics, give 6 months notice before sunset old version, return Sunset header + Deprecation header

```http
GET /api/v1/users/123
Deprecation: true
Sunset: Sat, 31 Dec 2025 23:59:59 GMT
Link: <https://api.example.com/api/v2/users/123>; rel="successor-version"
```

## Expanded: OpenAPI 3.0 Complete Example

```yaml
openapi: 3.0.3
info:
  title: E-commerce API
  description: Complete e-commerce API with users, products, orders
  version: 1.0.0
  contact: { name: API Support, email: support@example.com }
  license: { name: MIT }
servers:
  - url: https://api.example.com/api/v1
    description: Production
  - url: https://staging-api.example.com/api/v1
    description: Staging
security:
  - bearerAuth: []
paths:
  /users/{id}:
    get:
      summary: Get user by ID
      operationId: getUserById
      tags: [Users]
      parameters:
        - name: id
          in: path
          required: true
          schema: { type: string, format: uuid }
          example: 123e4567-e89b-12d3-a456-426614174000
        - name: fields
          in: query
          schema: { type: string, example: id,name,email }
          description: Sparse fieldsets
      responses:
        '200':
          description: User found
          headers:
            X-RateLimit-Limit: { schema: { type: integer } }
            X-RateLimit-Remaining: { schema: { type: integer } }
          content:
            application/json:
              schema: { $ref: '#/components/schemas/User' }
              example: { id: "123", name: "John", email: "john@example.com" }
        '401': { $ref: '#/components/responses/Unauthorized' }
        '404': { $ref: '#/components/responses/NotFound' }
        '429': { $ref: '#/components/responses/RateLimited' }
  /users:
    post:
      summary: Create user
      operationId: createUser
      tags: [Users]
      parameters:
        - name: Idempotency-Key
          in: header
          required: true
          schema: { type: string, format: uuid }
      requestBody:
        required: true
        content:
          application/json:
            schema: { $ref: '#/components/schemas/CreateUserRequest' }
      responses:
        '201':
          description: Created
          headers:
            Location: { schema: { type: string }, example: /users/123 }
          content:
            application/json:
              schema: { $ref: '#/components/schemas/User' }
        '400': { $ref: '#/components/responses/BadRequest' }
components:
  securitySchemes:
    bearerAuth:
      type: http
      scheme: bearer
      bearerFormat: JWT
  schemas:
    User:
      type: object
      required: [id, name, email]
      properties:
        id: { type: string, format: uuid }
        name: { type: string, minLength: 2, maxLength: 100 }
        email: { type: string, format: email }
        createdAt: { type: string, format: date-time }
        links:
          type: object
          properties:
            self: { type: string, format: uri }
            orders: { type: string, format: uri }
    CreateUserRequest:
      type: object
      required: [name, email]
      properties:
        name: { type: string, example: John Doe }
        email: { type: string, format: email, example: john@example.com }
  responses:
    Unauthorized:
      description: Unauthorized
      content:
        application/json:
          schema: { $ref: '#/components/schemas/Error' }
          example: { error: { code: UNAUTHORIZED, message: Missing token } }
    NotFound:
      description: Not found
      content:
        application/json:
          schema: { $ref: '#/components/schemas/Error' }
    BadRequest:
      description: Bad request
      content:
        application/json:
          schema: { $ref: '#/components/schemas/Error' }
    RateLimited:
      description: Too many requests
      headers:
        Retry-After: { schema: { type: integer }, example: 60 }
      content:
        application/json:
          schema: { $ref: '#/components/schemas/Error' }
```

## Expanded: Idempotency Implementation with DB (Production Grade)

```java
@Entity
@Table(name="idempotency_keys")
class IdempotencyRecord {
  @Id String key; // Idempotency-Key header value
  String responseStatus;
  String responseBody; // JSON
  LocalDateTime createdAt;
  LocalDateTime expiresAt;
}

@Service
class IdempotencyService {
  @Transactional
  public ResponseEntity<?> handle(String idempotencyKey, String requestHash, Supplier<ResponseEntity<?>> action) {
    // Check if key exists
    Optional<IdempotencyRecord> existing = repo.findById(idempotencyKey);
    if (existing.isPresent()) {
      IdempotencyRecord rec = existing.get();
      // If same request hash, return cached response (idempotent)
      // If different request hash but same key, return 422 (key already used for different request)
      if (!rec.getRequestHash().equals(requestHash)) {
        throw new IdempotencyConflictException("Idempotency-Key already used for different request");
      }
      return ResponseEntity.status(rec.getResponseStatus()).body(rec.getResponseBody());
    }
    // Execute action
    ResponseEntity<?> response = action.get();
    // Save
    IdempotencyRecord rec = new IdempotencyRecord();
    rec.setKey(idempotencyKey);
    rec.setRequestHash(requestHash);
    rec.setResponseStatus(String.valueOf(response.getStatusCodeValue()));
    rec.setResponseBody(objectMapper.writeValueAsString(response.getBody()));
    rec.setCreatedAt(LocalDateTime.now());
    rec.setExpiresAt(LocalDateTime.now().plusHours(24));
    repo.save(rec);
    return response;
  }
}

@RestController
class PaymentController {
  @PostMapping("/payments")
  public ResponseEntity<Payment> create(@RequestHeader("Idempotency-Key") String key, @RequestBody PaymentRequest req) {
    String requestHash = hash(req); // hash of request body to detect same key different request
    return (ResponseEntity<Payment>) idempotencyService.handle(key, requestHash, () -> {
      Payment payment = paymentService.process(req);
      return ResponseEntity.status(201).body(payment);
    });
  }
}
```

## Expanded: Rate Limiting Implementation (Redis + Lua - Production)

```java
// Lua script for sliding window counter
String luaScript = 
  "local key = KEYS[1]\n" +
  "local limit = tonumber(ARGV[1])\n" +
  "local window = tonumber(ARGV[2])\n" +
  "local now = tonumber(ARGV[3])\n" +
  "local clearBefore = now - window\n" +
  "redis.call('ZREMRANGEBYSCORE', key, 0, clearBefore)\n" +
  "local count = redis.call('ZCARD', key)\n" +
  "if count < limit then\n" +
  "  redis.call('ZADD', key, now, now)\n" +
  "  redis.call('EXPIRE', key, window)\n" +
  "  return {1, limit - count - 1}\n" +
  "else\n" +
  "  return {0, 0}\n" +
  "end";

@Component
class RateLimiter {
  private final RedisScript<List> script;
  private final StringRedisTemplate redis;

  public boolean allow(String userId, int limit, int windowSec) {
    String key = "ratelimit:" + userId;
    long now = System.currentTimeMillis() / 1000;
    List result = redis.execute(script, List.of(key), String.valueOf(limit), String.valueOf(windowSec), String.valueOf(now));
    long allowed = (Long) result.get(0);
    long remaining = (Long) result.get(1);
    // Set headers
    // X-RateLimit-Remaining = remaining
    return allowed == 1;
  }
}

// Usage as Spring Boot filter
@Component
class RateLimitFilter extends OncePerRequestFilter {
  protected void doFilterInternal(HttpServletRequest req, HttpServletResponse res, FilterChain chain) {
    String userId = getUserId(req); // from JWT or IP
    if (!rateLimiter.allow(userId, 100, 60)) {
      res.setHeader("Retry-After", "60");
      res.setStatus(429);
      res.getWriter().write("{\"error\":{\"code\":\"RATE_LIMITED\",\"message\":\"Too many requests\"}}");
      return;
    }
    chain.doFilter(req, res);
  }
}
```

## Expanded: File Upload - S3 Presigned URL + Multipart + Resumable

### Option 1: Direct Server Upload (Small files <10MB)
```java
@PostMapping("/users/{id}/avatar")
public ResponseEntity<?> uploadAvatar(@PathVariable Long id, @RequestParam("file") MultipartFile file) {
  if (file.getSize() > 10*1024*1024) throw new PayloadTooLargeException();
  String key = "avatars/" + id + "/" + UUID.randomUUID() + "-" + file.getOriginalFilename();
  s3Client.putObject(PutObjectRequest.builder().bucket("my-bucket").key(key).build(), RequestBody.fromBytes(file.getBytes()));
  String url = "https://my-bucket.s3.amazonaws.com/" + key;
  userService.updateAvatar(id, url);
  return ResponseEntity.ok(Map.of("url", url));
}
```

### Option 2: S3 Presigned URL (Large files, Recommended)
```java
@PostMapping("/uploads/presigned-url")
public ResponseEntity<?> getPresignedUrl(@RequestBody PresignedUrlRequest req) {
  String key = "uploads/" + UUID.randomUUID() + "-" + req.getFilename();
  PutObjectRequest putReq = PutObjectRequest.builder().bucket("my-bucket").key(key).contentType(req.getContentType()).build();
  PutObjectPresignRequest presignReq = PutObjectPresignRequest.builder().signatureDuration(Duration.ofMinutes(15)).putObjectRequest(putReq).build();
  String presignedUrl = s3Presigner.presignPutObject(presignReq).url().toString();
  return ResponseEntity.ok(Map.of("uploadUrl", presignedUrl, "fileUrl", "https://my-bucket.s3.amazonaws.com/" + key, "key", key));
}
// Client: PUT file directly to uploadUrl via fetch, no server load, then POST /uploads/complete to confirm
```

### Option 3: Resumable Chunked Upload (Very large 1GB+)
```
1. Client POST /uploads with filename, total size, chunk size => returns uploadId
2. Client uploads chunks: PUT /uploads/{uploadId}/chunks/{chunkNumber} with Content-Range: bytes 0-1048575/1073741824
3. Server stores chunks temporarily (S3 multipart upload)
4. Client POST /uploads/{uploadId}/complete => server assembles chunks via S3 CompleteMultipartUpload
5. Server returns fileUrl

Benefits: Resume if fails, progress bar, parallel chunk uploads
Tools: Tus protocol (open protocol for resumable uploads), S3 Multipart Upload
```

## Expanded: Webhooks Implementation Production Grade

```java
@Entity
class Webhook {
  @Id String id;
  String url;
  List<String> events; // ["order.created", "payment.succeeded"]
  String secret; // for HMAC signing
  boolean active;
  int retryCount;
  LocalDateTime createdAt;
}

@Service
class WebhookService {
  // Register
  public Webhook register(String url, List<String> events) {
    Webhook hook = new Webhook();
    hook.setId(UUID.randomUUID().toString());
    hook.setUrl(url);
    hook.setEvents(events);
    hook.setSecret(UUID.randomUUID().toString()); // generate secret
    hook.setActive(true);
    return repo.save(hook);
  }

  // Trigger - async via queue
  public void trigger(String eventType, Object payload) {
    List<Webhook> hooks = repo.findByEventsContainingAndActiveTrue(eventType);
    for (Webhook hook : hooks) {
      queue.add(() -> sendWebhook(hook, eventType, payload));
    }
  }

  private void sendWebhook(Webhook hook, String eventType, Object payload) {
    String payloadJson = objectMapper.writeValueAsString(payload);
    String signature = "sha256=" + HmacUtils.hmacSha256Hex(hook.getSecret(), payloadJson);
    try {
      HttpRequest req = HttpRequest.newBuilder()
        .uri(URI.create(hook.getUrl()))
        .header("Content-Type", "application/json")
        .header("X-Webhook-Signature", signature)
        .header("X-Event-Type", eventType)
        .header("X-Request-ID", UUID.randomUUID().toString())
        .POST(HttpRequest.BodyPublishers.ofString(payloadJson))
        .timeout(Duration.ofSeconds(5))
        .build();
      HttpResponse<String> res = httpClient.send(req, BodyHandlers.ofString());
      if (res.statusCode() >= 200 && res.statusCode() < 300) {
        log.info("Webhook delivered to {}", hook.getUrl());
      } else {
        throw new RuntimeException("Webhook failed with status " + res.statusCode());
      }
    } catch (Exception e) {
      // Retry with exponential backoff via queue
      int attempt = 1;
      if (attempt < 5) {
        long delay = (long) Math.pow(2, attempt) * 1000; // 2,4,8,16 sec
        queue.add(() -> sendWebhook(hook, eventType, payload), delay);
      } else {
        // DLQ and alert
        dlq.save(hook, payload, e);
        alertService.alert("Webhook failed after 5 retries: " + hook.getUrl());
      }
    }
  }
}
```

## Expanded: Interview Q&A More

**Q: How to handle API evolution without breaking clients?**
- Use expand-contract pattern: Expand - add new field optional, deploy, clients can use new field but old clients ignore; Contract - after all clients migrated to new field, remove old field in next version
- Never remove required field, never rename, never change type, only add optional
- Use @deprecated directive in OpenAPI, add Sunset header, give 6 months notice, monitor usage of old field via metrics
- For breaking change, create v2 endpoint, support v1 and v2 simultaneously

**Q: How to design API for search with many filters?**
- Use query params for filtering: /products?category=electronics&brand=apple&price[gte]=100&price[lte]=1000&inStock=true&sort=-rating,price&fields=id,name,price
- For complex filters, use POST /products/search with body containing filters (if URL too long or complex AND/OR logic)
```json
POST /products/search
{
  "filters": {
    "and": [
      { "field": "category", "op": "eq", "value": "electronics" },
      { "field": "price", "op": "gte", "value": 100 },
      { "or": [
        { "field": "brand", "op": "eq", "value": "apple" },
        { "field": "brand", "op": "eq", "value": "samsung" }
      ]}
    ]
  },
  "sort": [{ "field": "rating", "order": "desc" }],
  "pagination": { "page": 1, "limit": 20 }
}
```

**Q: How to handle long running task >30 sec?**
- Don't keep HTTP connection open 30 sec (timeout, thread blocking)
- Return 202 Accepted with Location header to job status: POST /reports => 202 Location: /jobs/123
- Client polls GET /jobs/123 => { status: "processing", progress: 50, resultUrl: null } or { status: "completed", resultUrl: "/reports/456" }
- Or use Webhook: Client provides callbackUrl in request, server POSTs result to callbackUrl when done
- Or use WebSocket/SSE for real-time progress: Client connects via WebSocket, server sends progress updates

**Q: How to design API for idempotency with DB?**
- See expanded implementation above with idempotency_keys table, store key + request hash + response, check before processing, return cached response if same key, error if same key different request

**Q: What is the difference between PUT and PATCH idempotency?**
- PUT is idempotent by definition (full replace, multiple same PUT same result), PATCH can be idempotent if designed (e.g. PATCH with { "status": "completed" } is idempotent, but PATCH with { "increment": 1 } is not idempotent)
- For true idempotency, use PUT for full replace, or design PATCH to be idempotent (e.g. set absolute value not increment)


---

## Expanded Again: More Production Patterns

### 13. API Composition vs Aggregation vs BFF

**API Composition** (Gateway aggregates):

```
Client GET /users/123/dashboard
  -> API Gateway
    -> Parallel calls via Promise.all:
      -> User Service GET /users/123
      -> Order Service GET /users/123/orders?limit=5
      -> Recommendation Service GET /users/123/recommendations
    -> Joins results in memory and returns combined
{
  "user": { "id": "123", "name": "John" },
  "recentOrders": [...],
  "recommendations": [...]
}
```

- Pros: Simple, no duplication, fresh data, single call for client avoids N+1 API calls
- Cons: Latency = sum of slowest (if parallel, max latency), if one service slow whole API slow, need handle partial failures (e.g. recommendations down still return user + orders)
- Implementation: Gateway does Promise.all with timeout 500ms per service, if one fails return partial with warning header

**BFF (Backend for Frontend)**: Similar to composition but separate BFF per frontend (Web BFF returns detailed, Mobile BFF minimal)

**GraphQL as Aggregation**: GraphQL gateway does composition automatically via resolvers + DataLoader batching

### 14. Caching Strategies for REST APIs Detailed

**Where to Cache**:

1. **Browser Cache**: Cache-Control header, ETag, browser caches GET responses
2. **CDN Cache**: CloudFront caches GET /api/products?category=electronics with TTL 60 sec, 90% offload
3. **Reverse Proxy Cache**: Nginx proxy_cache caches GET responses, fast
4. **Application Cache**: Redis caches DB query results or API responses
5. **Database Cache**: DB query cache, buffer pool

**Cache-Aside for API**:

```java
@GetMapping("/products/{id}")
public Product getProduct(@PathVariable String id) {
  String cacheKey = "product:" + id;
  Product cached = redis.get(cacheKey);
  if (cached != null) return cached; // hit
  Product product = db.findById(id); // miss, load from DB
  redis.setex(cacheKey, 300, product); // cache 5 min
  return product;
}
```

**Write-Through for API**:

```java
@PutMapping("/products/{id}")
public Product updateProduct(@PathVariable String id, @RequestBody ProductUpdate req) {
  Product updated = db.update(id, req);
  redis.setex("product:" + id, 300, updated); // update cache synchronously
  // Also invalidate list cache
  redis.del("products:list:*");
  return updated;
}
```

**Cache Invalidation via Events**:

```java
// When product updated, publish event to Kafka
@PutMapping("/products/{id}")
public Product update(@PathVariable String id, @RequestBody ProductUpdate req) {
  Product updated = db.update(id, req);
  kafka.send("product-updated", new ProductUpdatedEvent(id)); // async
  return updated;
}

// Cache service listens product-updated and invalidates
@KafkaListener(topics="product-updated")
public void handle(ProductUpdatedEvent event) {
  redis.del("product:" + event.getId());
  redis.del("products:list:*");
  // Also purge CDN cache
  cloudFront.createInvalidation("/products/" + event.getId(), "/products/list*");
}
```

### 15. Security - OAuth2 Authorization Code + PKCE Flow Detailed for REST API

Already covered in api_design_best_practices.md but here with sequence diagram:

```
User (Browser) -> Client (React SPA) -> Auth Server (Keycloak/Auth0) -> Resource Server (API)

1. User clicks Login in React
2. React generates code_verifier random 128 chars, code_challenge = BASE64URL(SHA256(code_verifier)), state random
3. React redirects to Auth Server: GET https://auth.example.com/authorize?response_type=code&client_id=react_app&redirect_uri=https://app.example.com/callback&scope=openid profile email&code_challenge=xxx&code_challenge_method=S256&state=yyy
4. Auth Server shows login page, user logs in (username/password + MFA)
5. Auth Server redirects to React callback: https://app.example.com/callback?code=auth_code&state=yyy
6. React verifies state matches (prevent CSRF), then POST https://auth.example.com/token with { grant_type=authorization_code, code=auth_code, client_id=react_app, code_verifier=original_verifier, redirect_uri=https://app.example.com/callback }
7. Auth Server validates code + code_verifier (SHA256(verifier) == challenge), returns { access_token (JWT 15 min), id_token (JWT user info), refresh_token (opaque 7 days) }
8. React stores access_token in memory (JS variable), refresh_token in HttpOnly Secure SameSite=Strict cookie (via backend /auth/callback endpoint that sets cookie)
9. React calls API: GET /api/users/me with Authorization: Bearer access_token
10. API validates JWT signature via public key, checks exp, iss, aud, then returns user
11. When access_token expires (15 min), React calls POST /auth/refresh with refresh_token cookie, backend validates refresh_token via Auth Server and returns new access_token + new refresh_token (rotation)
```

**Why PKCE?** Prevents authorization code interception attack - even if attacker intercepts code, they don't have code_verifier so can't exchange for tokens

### 16. Rate Limiting Headers & Retry-After

```http
HTTP/1.1 200 OK
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 99
X-RateLimit-Reset: 1713000600

HTTP/1.1 429 Too Many Requests
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 0
X-RateLimit-Reset: 1713000600
Retry-After: 60
Content-Type: application/json

{
  "error": {
    "code": "RATE_LIMIT_EXCEEDED",
    "message": "Too many requests, limit 100 per minute",
    "retryAfter": 60
  }
}
```

### 17. Content Negotiation

```http
GET /users/123
Accept: application/json -> returns JSON
Accept: application/xml -> returns XML (if supported)
Accept: application/vnd.example.v1+json -> returns v1 JSON
Accept-Language: en-US -> returns English, fr -> French

Server:
Content-Type: application/json
Content-Language: en-US
```

### 18. API Versioning with Sunset & Deprecation Headers (Production)

```http
GET /api/v1/users/123
200 OK
Deprecation: true
Sunset: Sat, 31 Dec 2025 23:59:59 GMT
Link: <https://api.example.com/api/v2/users/123>; rel="successor-version"
Warning: 299 - "API v1 deprecated, migrate to v2 by 2025-12-31, see https://docs.example.com/migration-v1-v2"
Sunset: Sat, 31 Dec 2025 23:59:59 GMT
```

### 19. Complete E-commerce REST API with HATEOAS HAL Format

```json
GET /api/v1/users/123

{
  "id": "123",
  "name": "John Doe",
  "email": "john@example.com",
  "_links": {
    "self": { "href": "/api/v1/users/123", "type": "application/json" },
    "orders": { "href": "/api/v1/users/123/orders", "type": "application/json" },
    "cart": { "href": "/api/v1/cart?userId=123", "type": "application/json" },
    "update": { "href": "/api/v1/users/123", "method": "PUT", "type": "application/json" },
    "delete": { "href": "/api/v1/users/123", "method": "DELETE" }
  },
  "_embedded": {
    "recentOrders": [
      {
        "id": "456",
        "total": 100,
        "_links": {
          "self": { "href": "/api/v1/orders/456" },
          "pay": { "href": "/api/v1/orders/456/pay", "method": "POST" }
        }
      }
    ]
  }
}
```

### 20. Testing REST APIs with Contract Testing (Pact) Detailed

**Consumer (Frontend) defines contract**:

```js
// Frontend Pact test - defines expected provider behavior
import { Pact } from '@pact-foundation/pact';

const provider = new Pact({
  consumer: 'WebApp',
  provider: 'UserService',
  port: 1234
});

describe('User API contract', () => {
  beforeAll(() => provider.setup());
  afterAll(() => provider.finalize());
  afterEach(() => provider.verify());

  it('should get user by id', async () => {
    await provider.addInteraction({
      state: 'user 123 exists',
      uponReceiving: 'a request for user 123',
      withRequest: { method: 'GET', path: '/api/v1/users/123', headers: { Authorization: 'Bearer token' } },
      willRespondWith: { status: 200, headers: { 'Content-Type': 'application/json' }, body: { id: '123', name: 'John', email: 'john@example.com' } }
    });
    // Make request to mock provider
    const user = await fetchUser(123);
    expect(user.name).toBe('John');
  });
});
// Generates pact file: webapp-userservice.json with contract
```

**Provider (Backend) verifies contract**:

```java
// Backend Pact verification - ensures provider satisfies consumer contract
@PactTestFor(providerName = "UserService")
@SpringBootTest(webEnvironment = RANDOM_PORT)
class UserServicePactTest {
  @TestTemplate
  @ExtendWith(PactVerificationInvocationContextProvider.class)
  void pactVerificationTestTemplate(PactVerificationContext context) {
    context.verifyInteraction();
  }

  @State("user 123 exists")
  void user123Exists() {
    // Setup state: Create user 123 in DB
    userRepo.save(new User(123L, "John", "john@example.com"));
  }
}
// If provider breaks contract (e.g. removes name field), Pact verification fails in CI, prevents breaking consumer
```

---

This expanded REST API guide now covers Richardson, versioning, OpenAPI, idempotency, rate limiting, file uploads, webhooks, composition, caching, OAuth2 PKCE, HATEOAS HAL, and contract testing for production-grade SDE3.
