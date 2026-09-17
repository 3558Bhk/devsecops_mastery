# API Comparison & Decision Guide

## Quick Decision Matrix

| Criteria | REST | GraphQL | gRPC | SOAP |
|----------|------|---------|------|------|
| Performance | Medium | Medium | High | Low |
| Browser | Excellent | Excellent | Needs proxy | Poor |
| Payload | JSON | JSON | Protobuf binary | XML |
| Caching | Easy HTTP cache | Hard | No | No |
| Streaming | No | Subscription | Yes 4 types | No |
| Contract | Optional OpenAPI | Schema mandatory | Proto mandatory | WSDL mandatory |
| Learning | Easy | Medium | Medium-Hard | Hard |
| Public API? | Yes best | Yes good | No internal | Legacy enterprise |

## Use Case Guide for SDE3

**Use REST when:**
- Public API, third party integration
- Simple CRUD
- Need HTTP caching
- Team familiar

**Use GraphQL when:**
- Frontend needs flexible fields (web vs mobile)
- Aggregate many microservices in one call (BFF)
- Over-fetching problem (e.g. /users returns 50 fields but UI needs 3)
- Real-time subscriptions needed

**Use gRPC when:**
- Internal microservices (<10ms latency requirement)
- High throughput (1000+ RPS per service)
- Polyglot streaming (IoT, chat, ML inference)
- Service mesh (Istio uses Envoy which speaks gRPC)

**Use SOAP when:**
- Legacy bank, telecom, enterprise with WS-Security
- Need ACID transactions across services (WS-AtomicTransaction)
- No choice

## SDE3 Architecture Pattern: Mix Them
```
Client (Web/Mobile)
   |
   | REST / GraphQL
   v
API Gateway (Kong / AWS API Gateway)
   |
   | GraphQL Federation (BFF)
   v
Microservices <--gRPC--> Microservices
   |
   | SOAP (only for bank payment adapter)
   v
Legacy Bank
```

## Security Comparison
- REST: JWT + OAuth2 + HTTPS + Rate Limit
- GraphQL: Same + depth limiting + complexity analysis
- gRPC: TLS + Interceptors for JWT + mTLS for service-to-service
- SOAP: WS-Security + XML Signature/Encryption

## Interview Question: How to version?
- REST: URL /v1/ or header
- GraphQL: No version, evolve schema, deprecate field
- gRPC: Proto field numbers never reuse, package v2
- SOAP: WSDL new endpoint

## Error Handling Unified
Always return standard error:
```json
{
  "code": "RESOURCE_NOT_FOUND",
  "message": "User not found",
  "details": {},
  "requestId": "uuid"
}
```

## Tools to Mention
- OpenAPI Swagger for REST
- Apollo Studio for GraphQL
- grpcurl, protobuf
- Postman supports all 4 now
