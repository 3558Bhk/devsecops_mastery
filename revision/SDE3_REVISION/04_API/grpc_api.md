# gRPC - Revision

## What?
- gRPC = gRPC Remote Procedure Call
- Developed by Google 2015
- High performance RPC framework
- Uses HTTP/2 + Protocol Buffers (Protobuf)
- Contract-first, strongly typed

## Key Features
- **HTTP/2**: Multiplexing, binary, header compression, bidirectional streaming
- **Protobuf**: Binary serialization, small, fast, language neutral, 3-10x smaller than JSON
- **Streaming**: 4 types
- **Language agnostic**: Java, Go, Node, Python, C++, etc generate code
- **Bi-directional**

## 4 Communication Types
1. **Unary**: Traditional Request -> Response (like REST)
2. **Server Streaming**: Client request -> Server stream responses (e.g. large list)
3. **Client Streaming**: Client stream -> Server single response (e.g. upload)
4. **Bi-directional Streaming**: Both stream (chat, real-time)

## Protobuf Example
```proto
syntax = "proto3";

package user;

service UserService {
  rpc GetUser (GetUserRequest) returns (UserResponse);
  rpc ListUsers (ListUsersRequest) returns (stream UserResponse); // server streaming
  rpc CreateUsers (stream CreateUserRequest) returns (Summary); // client streaming
  rpc Chat (stream ChatMessage) returns (stream ChatMessage); // bidi
}

message GetUserRequest {
  string id = 1;
}

message UserResponse {
  string id = 1;
  string name = 2;
  string email = 3;
}

message ListUsersRequest {
  int32 page = 1;
  int32 limit = 2;
}
```

## gRPC vs REST

| Aspect | gRPC | REST |
|--------|------|------|
| Format | Protobuf binary | JSON text |
| Protocol | HTTP/2 | HTTP/1.1 (mostly) |
| Speed | Very fast, low latency | Slower |
| Streaming | Yes 4 types | No (need WebSocket/SSE) |
| Browser support | Limited (needs grpc-web) | Native |
| Contract | .proto strict | OpenAPI optional |
| Code Gen | Yes auto | Manual |
| Use Case | Microservices internal | Public APIs, external |

## Advantages
- Performance: 7-10x faster than REST+JSON
- Strong typing
- Streaming perfect for microservices
- Built-in load balancing, deadlines, cancellation

## Disadvantages
- Not browser friendly (grpc-web proxy needed)
- Not human readable (binary)
- Learning curve
- Limited tooling vs REST (Postman now supports)

## Concepts SDE3 Must Know
- **Channel**: Connection to server
- **Stub**: Client object
- **Deadlines/Timeouts**: `context.WithTimeout`
- **Interceptors**: Like middleware for auth/logging
- **Error Handling**: gRPC status codes (0 OK, 2 Unknown, 5 Not Found, 7 PermissionDenied, 14 Unavailable)
- **Load Balancing**: Client side LB, lookaside LB

## When to Use?
- Internal microservices communication (service mesh)
- Low latency, high throughput (real-time, IoT, ML)
- Polyglot environments
- Streaming needs

## Tools
- grpcurl (like curl): `grpcurl -plaintext localhost:50051 list`
- BloomRPC, Postman gRPC
- Envoy proxy for grpc-web

## Interview Answer
"In our system, public APIs are REST for compatibility, internal inter-service calls use gRPC for performance, and mobile flexible needs use GraphQL via BFF. SOAP only for legacy bank integration."
