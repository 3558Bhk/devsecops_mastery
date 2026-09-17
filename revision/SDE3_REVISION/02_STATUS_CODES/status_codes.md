# HTTP Status Codes - Complete Revision

## 1xx Informational
- **100 Continue** - Request part OK, continue
- **101 Switching Protocols** - e.g. WebSocket upgrade
- **102 Processing** - Server processing, no response yet

## 2xx Success (Most Important)
- **200 OK** - Standard success GET/PUT
- **201 Created** - Resource created POST
- **202 Accepted** - Request accepted but processing async
- **204 No Content** - Success but no body (DELETE)
- **206 Partial Content** - Range requests (video streaming)

## 3xx Redirection
- **301 Moved Permanently** - SEO, permanent redirect
- **302 Found** - Temporary redirect (login -> dashboard)
- **304 Not Modified** - Cached, use cache version
- **307 Temporary Redirect** - Same method preserved
- **308 Permanent Redirect** - Same method preserved

## 4xx Client Errors (Your Fault)
- **400 Bad Request** - Invalid syntax / validation fail
- **401 Unauthorized** - No auth / token missing/expired
- **403 Forbidden** - Auth OK but no permission
- **404 Not Found** - Resource doesn't exist
- **405 Method Not Allowed** - e.g. GET on POST endpoint
- **408 Request Timeout**
- **409 Conflict** - Duplicate entry / version conflict
- **410 Gone** - Resource permanently deleted
- **413 Payload Too Large**
- **415 Unsupported Media Type**
- **422 Unprocessable Entity** - Validation semantic error
- **429 Too Many Requests** - Rate limiting
- **451 Unavailable For Legal Reasons**

## 5xx Server Errors (Server Fault)
- **500 Internal Server Error** - Generic crash
- **501 Not Implemented**
- **502 Bad Gateway** - Invalid response from upstream (Nginx -> Node down)
- **503 Service Unavailable** - Overloaded / maintenance
- **504 Gateway Timeout** - Upstream didn't respond in time
- **505 HTTP Version Not Supported**

## Interview Scenarios

**Q: Difference 401 vs 403?**
401 = Who are you? Not logged in. 403 = I know you, but you can't access.

**Q: 301 vs 302?**
301 cached by browser forever, SEO juice transferred. 302 temporary, not cached.

**Q: 502 vs 504?**
502 = Upstream gave bad response. 504 = Upstream timeout.

**Q: When to use 201 vs 200 vs 204?**
POST create -> 201 + Location header. PUT update -> 200 with body. DELETE -> 204.

**Q: What is 429 handling?**
Return Retry-After header. Client should exponential backoff.

## Custom Codes You Should Use
- 200 + error object? BAD. Use proper 4xx.
- Always return JSON: `{ "error": "message", "code": "VALIDATION_ERROR" }`

## gRPC Status Mapping
- OK = 0 (maps to 200)
- NOT_FOUND = 5 (404)
- PERMISSION_DENIED = 7 (403)
- UNAUTHENTICATED = 16 (401)
