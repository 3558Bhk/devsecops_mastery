# Amazon API Gateway — Interview Questions

> **Cloud:** AWS (Other Services) · **Category:** PaaS / Integration · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~8 min

---

## JSON File Format

API Gateway REST APIs are imported/exported as **OpenAPI (Swagger) JSON**, including AWS extensions that wire each path to a backend.

```json
{
  "openapi": "3.0.1",
  "info": { "title": "Orders API", "version": "1.0" },
  "paths": {
    "/orders": {
      "get": {
        "x-amazon-apigateway-integration": {
          "type": "aws_proxy",
          "httpMethod": "POST",
          "uri": "arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:...:invocations"
        }
      }
    }
  }
}
```

**Key fields:** `paths` + methods · `x-amazon-apigateway-integration` (`aws_proxy` / `http` / `mock` backend mapping) · `securitySchemes` (auth) · `models` (request/response schemas) · `x-amazon-apigateway-request-validator` (validation).


## Case A — Basic

**A1. What is Amazon API Gateway?**
**Answer:** A fully managed service for creating, publishing, securing, and monitoring **REST, HTTP, and WebSocket APIs** — it sits between clients and your backend (Lambda, EC2, ECS, or other HTTP services).

**A2. What are the API types?**
**Answer:** **REST API** (feature-rich: usage plans, keys, transformations), **HTTP API** (lightweight, cheaper, low-latency — for Lambda/proxy workloads), and **WebSocket API** (real-time, bidirectional).

**A3. What are the main components of an API Gateway REST API?**
**Answer:** **Resources** (paths), **methods** (GET/POST/etc.), **integrations** (backend connection), **stages** (deployment environments), **authorizers**, **models/schemas**, and **usage plans/API keys**.

**A4. What is a "stage"?**
**Answer:** A named snapshot of an API deployment (e.g., `dev`, `prod`), each with its own URL, settings (throttling, caching, logging), and variables.

**A5. What is an integration, and what are the types?**
**Answer:** The backend connection for a method. Types: **Lambda** (proxy or custom), **HTTP** (any HTTP endpoint), **Mock** (returns a fixed response), and **AWS service** (directly call another AWS API).

**A6. What is the difference between proxy and non-proxy (custom) Lambda integration?**
**Answer:** **Proxy** passes the entire request to Lambda and returns its response as-is (simplest). **Custom** lets you transform requests/responses via mapping templates (VTL).

**A7. What is an authorizer?**
**Answer:** A component that validates incoming requests before they reach the backend: **Lambda authorizers** (custom logic) or **Cognito/JWT** authorizers (OIDC/OAuth tokens).

**A8. What is throttling and rate limiting in API Gateway?**
**Answer:** Limits on requests per second (**rate**) and total requests in a window (**burst**), at the account, stage, and usage-plan levels — protecting backends from overload.

**A9. What is an API key and usage plan?**
**Answer:** Usage plans bundle throttling/quota limits and associate **API keys** with clients, monetizing or tiering API access.

**A10. What is request validation and models?**
**Answer:** API Gateway can validate request bodies/parameters against JSON **models** (schemas), rejecting invalid input before it reaches the backend.

**A11. What is API caching?**
**Answer:** Stage-level caching of endpoint responses (with TTL) to reduce backend calls and latency.

**A12. How does API Gateway compare to an ALB for APIs?**
**Answer:** API Gateway = managed API features (auth, keys, throttling, stages, schemas, WebSocket) with per-request cost. ALB = L7 load balancing, cheaper at very high volume, but no API-management features.

**A13. What is CORS and how do you enable it?**
**Answer:** Cross-Origin Resource Sharing — browser security for cross-domain calls. Enable by adding `Access-Control-Allow-Origin` etc. headers (or using the console's "Enable CORS" which adds an OPTIONS method).

**A14. What is the 29-second integration timeout?**
**Answer:** API Gateway waits up to **29 seconds** (REST/HTTP) for a backend response; longer work needs async patterns (or WebSocket/Step Functions).

**A15. What is the payload limit?**
**Answer:** **10 MB** request/response payload (REST/HTTP); larger payloads use presigned S3 uploads.

---

## Case B — Advanced (Senior)

**B1. Explain the end-to-end request flow: method request → integration request → integration response → method response.**
**Answer:** The client hits a **method**; API Gateway applies **authorization, throttling, validation**, and maps the **method request** (params/headers/body) to an **integration request** (backend format); the backend returns an **integration response**, which is mapped to the **method response** returned to the client. Mapping templates (VTL) or proxy passthrough control each hop.

**B2. Compare REST API vs HTTP API vs WebSocket API — when to choose each.**
**Answer:** **REST API**: full features (usage plans, keys, VTL transforms, WAF, caching, per-method config) — for public/managed APIs. **HTTP API**: minimal, ~70% cheaper, lower latency, JWT auth, Lambda/HTTP backends — for internal/API-proxy workloads. **WebSocket**: real-time bidirectional (chat, live updates) with connection management and `$connect`/`$disconnect` routes.

**B3. How do you secure an API Gateway (authN/authZ layers)?**
**Answer:** (1) **IAM authorization** (SigV4) for AWS-internal callers. (2) **Cognito user pools** (OIDC/JWT) for user auth. (3) **Lambda authorizers** for custom logic (API keys, tokens, RBAC). (4) **API keys + usage plans** for client identification/throttling. (5) **Resource policies** (IP/VPC/account restrictions), **WAF** (REST APIs) for threat protection, and TLS (custom domains via ACM).

**B4. What is a Lambda authorizer (token vs request type) and how does caching work?**
**Answer:** A Lambda that returns an IAM policy (Allow/Deny) + context. **Token authorizer** passes a bearer token; **request authorizer** passes headers/query/context. Responses can be **cached** (per key/identity source) to avoid re-invoking per request. Context values are passed to the backend for authorization decisions.

**B5. How do you design throttling (rate vs burst, per-client, and defense in depth)?**
**Answer:** Set account-level and stage-level rate/burst, use **usage plans** for per-API-key limits, and enable **WAF rate-based rules** to block abusive clients. Return 429 and require clients to honor Retry-After. Layer throttling (edge → stage → plan) so no single client saturates the backend.

**B6. How does API Gateway integrate with Lambda (proxy), and how do you handle cold starts + timeouts?**
**Answer:** Proxy integration forwards the event; Lambda's cold start adds latency (mitigate with provisioned concurrency). The 29s integration timeout caps Lambda duration; for longer work, return 202 and process asynchronously (SQS/Step Functions) or use WebSocket. Handle Lambda errors by mapping error status codes.

**B7. What are mapping templates (VTL) and when do you still need them?**
**Answer:** VTL transforms between the method request and integration (e.g., SOAP→JSON, header/body reshaping, response transformation). With proxy integrations and modern backends you rarely need VTL, but it remains useful for legacy/non-Lambda integrations and custom response shaping.

**B8. How do you do canary deployments and versioning with API Gateway stages?**
**Answer:** Enable **stage canary** — send a % of traffic to a new deployment while the rest uses the stable one; monitor (CloudWatch/Latency/5xx) and promote or roll back by adjusting the percentage. Stage variables (e.g., `lambdaAlias`) let the same API definition point at different backend versions per stage.

**B9. How do you make an API Gateway highly available and multi-region?**
**Answer:** API Gateway is regional by default (edge-optimized uses CloudFront). For multi-region: deploy the API in multiple regions and use **Route 53 latency/failover routing** (or **Global Accelerator**) to steer clients; replicate backend (Lambda/DynamoDB global tables) so each region is self-sufficient.

**B10. How do you monitor API Gateway (metrics, logs, tracing)?**
**Answer:** CloudWatch metrics: `Count`, `4XXError`, `5XXError`, `Latency`, `IntegrationLatency`, `CacheHitCount`. Enable **access logging** (structured, custom format) and **X-Ray** tracing for end-to-end latency. Alarm on 5xx rate, p99 latency, and throttles (429).

**B11. What are API Gateway's limits and pricing considerations?**
**Answer:** 10 MB payload, 29s integration timeout, per-request pricing (REST pricier than HTTP), caching/throttling limits, and edge-optimized/regional/private endpoint costs. Design for the 10 MB cap (use S3 presigned URLs) and choose HTTP APIs for high-volume internal traffic to cut cost.

**B12. How does a private API Gateway work, and how do you access it from on-prem?**
**Answer:** A **private API** is accessible only from within a VPC (via an interface endpoint) — combined with a **resource policy** restricting to VPC endpoints. On-prem clients reach it over Direct Connect/VPN into the VPC. Use it for internal services that need API-management features.

---

## Case C — Scenario

**C1. Scenario:** Expose a Lambda-backed CRUD API with auth: some endpoints public, some require login, and rate-limit third parties.
**Question:** Design the API Gateway setup.
**Expected answer:** One REST (or HTTP) API with resources (`/items`), **Cognito/JWT authorizer** on protected methods, public methods open, **usage plans + API keys** for third-party clients with per-key quotas, **request validation** (models), **stage throttling**, access logs + X-Ray, and a custom domain with ACM. Backend = Lambda proxy integrations.

**C2. Scenario:** A client uploads 50 MB files through your API and it fails.
**Question:** Explain and fix.
**Expected answer:** API Gateway's payload limit is **10 MB**. Fix: use **S3 presigned URLs** — the client requests a presigned PUT URL from the API, uploads directly to S3, then notifies the API. This offloads large payloads from API Gateway entirely (and saves Lambda/data-transfer cost).

**C3. Scenario:** An API returns 5xx intermittently under load; Lambda errors look fine.
**Question:** Diagnose.
**Expected answer:** Check API Gateway metrics: `5XXError` vs Lambda `Errors` — the failures may be **integration latency** exceeding the 29s timeout (or downstream timeouts), or **throttling** (429, often logged as errors), or a backend (HTTP integration) failing. Enable **X-Ray** to see which hop fails and CloudWatch Logs for the API to find the cause (e.g., Lambda cold start + timeout).

**C4. Scenario:** You must roll out a new API version to 10% of users and auto-rollback if errors exceed 1%.
**Question:** Implement it.
**Expected answer:** Use **stage canary**: deploy the new version and set the canary to 10% of traffic; alarm on `5XXError`/`Latency`; on breach, roll back to 0% (or automate via CodeDeploy-style hooks/CloudWatch alarms). Use **stage variables** to point to the new Lambda alias so switching is instant.

**C5. Scenario:** An API must be reachable only from inside your VPC (and your data center via Direct Connect), not the internet.
**Question:** Design it.
**Expected answer:** Create a **private API Gateway** (endpoint type = private) with a **resource policy** allowing only your VPC endpoint(s); create an **interface endpoint** for `execute-api` in your subnets. On-prem users reach it through Direct Connect/VPN into the VPC. No public internet exposure.

**C6. Scenario:** A partner calls your API with a stale API key during a trial and gets 403; you need to differentiate "wrong key" from "quota exceeded."
**Question:** How does API Gateway distinguish, and how do you communicate it?
**Expected answer:** API Gateway returns **403 Forbidden** for missing/invalid keys and **429 Too Many Requests** for throttle/quota violations (with `Retry-After`). Configure usage-plan quotas so partners clearly see quota-exceeded (429) vs auth (403), and document the distinction. Monitor via CloudWatch throttle metrics and key usage reports.
