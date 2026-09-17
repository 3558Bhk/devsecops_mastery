# REST API - Revision

## What is REST?
- REpresentational State Transfer
- Architectural style, not protocol
- Stateless, Client-Server, Cacheable, Uniform Interface, Layered System

## Principles
1. **Stateless**: Each request contains all info, server no session
2. **Resource Based**: Everything is resource with URI /users/123
3. **HTTP Verbs**: GET, POST, PUT, PATCH, DELETE
4. **Representation**: JSON/XML, usually JSON
5. **HATEOAS**: Hypermedia as engine (optional advanced)

## HTTP Methods (CRUD)
| Method | Use | Idempotent | Safe | Status |
|--------|-----|------------|------|--------|
| GET | Read | Yes | Yes | 200 |
| POST | Create | No | No | 201 |
| PUT | Full Update | Yes | No | 200/204 |
| PATCH | Partial Update | No | No | 200 |
| DELETE | Delete | Yes | No | 204 |
| HEAD | Headers only | Yes | Yes | 200 |
| OPTIONS | CORS preflight | Yes | Yes | 200 |

## Best Practices (Interview Gold)
- Nouns not verbs: `/users` not `/getUsers`
- Plural: `/users/123/orders`
- Versioning: `/api/v1/users` or header `Accept: application/vnd.api.v1+json`
- Filtering: `/users?role=admin&status=active`
- Pagination: `/users?page=1&limit=20` + headers `X-Total-Count`, or cursor
- Sorting: `/users?sort=-createdAt,name`
- Status codes proper
- Use HTTPS
- Error format consistent:
```json
{
  "error": { "code": "USER_NOT_FOUND", "message": "User 123 not found" },
  "status": 404,
  "timestamp": "2026-09-13T10:00:00Z"
}
```

## Security
- HTTPS + TLS
- Auth: JWT Bearer, OAuth2, API Key in header (not URL)
- Rate limiting: 429
- CORS

## Idempotency
- PUT DELETE idempotent: multiple same calls same result
- POST not: creates duplicate
- Implement Idempotency-Key header for POST payments

## Caching
- Headers: Cache-Control, ETag, Last-Modified
- ETag: `If-None-Match` -> 304

## Example
```
GET /api/v1/users/123
Authorization: Bearer <jwt>
Accept: application/json

POST /api/v1/users
Content-Type: application/json
{
  "name": "John",
  "email": "john@example.com"
}
=> 201 Created
Location: /api/v1/users/124
```

## Interview Q: REST vs RESTful?
REST = principles, RESTful = API implementing REST.

## Performance
- Gzip compression
- Pagination
- Sparse fieldsets: `/users?fields=id,name`
- HTTP/2
