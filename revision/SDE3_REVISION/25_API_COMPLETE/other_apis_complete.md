# Other APIs Complete - SOAP, GraphQL, gRPC, WebSocket, SSE, Webhooks

## 1. SOAP API - Complete

### What is SOAP?

- **SOAP**: Simple Object Access Protocol, protocol (strict standard), not architectural style like REST
- XML based, W3C standard, transport independent (HTTP, SMTP, TCP, JMS)
- Heavy, verbose, but enterprise features: ACID, WS-* standards, formal contract

### Structure

```xml
<?xml version="1.0"?>
<soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope/"
               xmlns:m="http://www.example.com/stock">
  <soap:Header>
    <!-- Optional, auth, transaction, routing -->
    <m:Auth>
      <m:Token>abc123</m:Token>
    </m:Auth>
    <wss:Security xmlns:wss="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd">
      <wss:UsernameToken>
        <wss:Username>user</wss:Username>
        <wss:Password>pass</wss:Password>
      </wss:UsernameToken>
    </wss:Security>
  </soap:Header>
  <soap:Body>
    <!-- Actual request/response -->
    <m:GetStockPrice>
      <m:StockName>GOOG</m:StockName>
    </m:GetStockPrice>
  </soap:Body>
  <soap:Fault>
    <!-- Error, optional, only in response if error -->
    <faultcode>soap:Server</faultcode>
    <faultstring>Internal Error</faultstring>
    <detail>
      <m:ErrorCode>123</m:ErrorCode>
    </detail>
  </soap:Fault>
</soap:Envelope>
```

### Components

- **Envelope**: Root element, defines XML doc as SOAP message, required
- **Header**: Optional, contains application specific info like auth, transaction, mustUnderstand attribute
- **Body**: Required, contains actual message (request/response), or Fault
- **Fault**: Optional, error handling, contains faultcode, faultstring, faultactor, detail
- **WSDL**: Web Services Description Language - XML contract describing service: What operations, what messages, what data types (XSD), where endpoint, how binding (protocol)
- **XSD**: XML Schema Definition - defines data types
- **UDDI**: Universal Description Discovery Integration - registry to discover SOAP services (mostly obsolete now)

### WSDL Structure Example

```xml
<definitions name="StockService" targetNamespace="http://example.com/stock" ...>
  <types>
    <!-- XSD data types -->
    <xsd:schema>
      <xsd:element name="GetStockPrice">
        <xsd:complexType>
          <xsd:sequence>
            <xsd:element name="StockName" type="xsd:string"/>
          </xsd:sequence>
        </xsd:complexType>
      </xsd:element>
      <xsd:element name="GetStockPriceResponse">
        <xsd:complexType>
          <xsd:sequence>
            <xsd:element name="Price" type="xsd:float"/>
          </xsd:sequence>
        </xsd:complexType>
      </xsd:element>
    </xsd:schema>
  </types>
  
  <message name="GetStockPriceRequest">
    <part name="parameters" element="tns:GetStockPrice"/>
  </message>
  <message name="GetStockPriceResponse">
    <part name="parameters" element="tns:GetStockPriceResponse"/>
  </message>
  
  <portType name="StockPortType">
    <operation name="GetStockPrice">
      <input message="tns:GetStockPriceRequest"/>
      <output message="tns:GetStockPriceResponse"/>
    </operation>
  </portType>
  
  <binding name="StockBinding" type="tns:StockPortType">
    <soap:binding style="document" transport="http://schemas.xmlsoap.org/soap/http"/>
    <operation name="GetStockPrice">
      <soap:operation soapAction="http://example.com/GetStockPrice"/>
      <input><soap:body use="literal"/></input>
      <output><soap:body use="literal"/></output>
    </operation>
  </binding>
  
  <service name="StockService">
    <port name="StockPort" binding="tns:StockBinding">
      <soap:address location="http://example.com/stock"/>
    </port>
  </service>
</definitions>
```

### WS-* Standards (Enterprise Features)

- **WS-Security**: Encryption, signing, UsernameToken, SAML, Kerberos - message level security (vs HTTPS transport level)
- **WS-ReliableMessaging**: Guaranteed delivery, ordering, exactly-once
- **WS-AtomicTransaction**: ACID transactions across distributed services (2PC)
- **WS-Addressing**: Routing info in header
- **WS-Policy**: Policies
- These make SOAP suitable for enterprise needing formal security, transactions, reliability

### SOAP Characteristics

- **Protocol**: Strict standard, W3C
- **Format**: XML only, verbose (3-10x larger than JSON)
- **Transport**: HTTP, SMTP, TCP, JMS, etc
- **State**: Can be stateful or stateless (can maintain state via WS-*)
- **Security**: WS-Security (message level) + HTTPS (transport level) - very secure, suitable for banking
- **Transactions**: ACID via WS-AtomicTransaction
- **Contract**: WSDL strict contract, code generation from WSDL (wsimport Java, svcutil .NET)
- **Caching**: No HTTP caching (POST only)
- **Performance**: Slow due to XML parsing, heavy
- **Error Handling**: SOAP Fault

### When to Use SOAP?

- Enterprise, banking, payment gateways (old banks), telecom where WS-Security, transactions, formal contract required
- Legacy systems integration
- Need ACID transactions across services
- When you need stateful operations with formal contract
- **Don't use for**: New public APIs, mobile, modern web - use REST/GraphQL/gRPC

### Tools

- **SoapUI**: Testing SOAP APIs
- **Postman**: Supports SOAP
- **WSDL to Code**: wsimport (Java), wsdl2java (Apache CXF), svcutil (.NET)
- **Code to WSDL**: Java annotations @WebService generates WSDL

### Example Java JAX-WS

```java
@WebService
public class StockService {
  @WebMethod
  public float getStockPrice(@WebParam(name="StockName") String stockName) {
    // logic
    return 123.45f;
  }
}
// Generates WSDL at http://localhost:8080/stock?wsdl
```

---

## 2. GraphQL - Complete

### What is GraphQL?

- Query language for API + runtime to execute queries, developed by Facebook 2012, open source 2015
- Single endpoint `/graphql`, client asks exactly what it needs, solves over-fetching and under-fetching of REST
- Strongly typed, introspection, real-time via subscriptions

### Core Concepts

- **Schema**: Type definitions in SDL (Schema Definition Language), contract
- **Types**: Object, Query, Mutation, Subscription, Scalar (ID, String, Int, Float, Boolean), Enum, Input, Interface, Union
- **Query**: Read (like GET)
- **Mutation**: Write (like POST/PUT/DELETE)
- **Subscription**: Real-time via WebSocket
- **Resolver**: Function that returns data for field, one resolver per field, can fetch from DB, API, etc
- **DataLoader**: Batching and caching to solve N+1 problem

### Example Schema

```graphql
# Scalar types: ID, String, Int, Float, Boolean, custom Date

type User {
  id: ID!
  name: String!
  email: String!
  age: Int
  role: Role!
  posts: [Post!]! # list of posts, non-null list of non-null posts
  createdAt: String!
}

type Post {
  id: ID!
  title: String!
  content: String!
  author: User!
  comments: [Comment!]!
}

type Comment {
  id: ID!
  text: String!
  author: User!
  post: Post!
}

enum Role {
  ADMIN
  USER
  GUEST
}

type Query {
  user(id: ID!): User
  users(limit: Int = 10, offset: Int = 0, role: Role): [User!]!
  post(id: ID!): Post
  search(query: String!): [SearchResult!]! # Union example
}

type Mutation {
  createUser(input: CreateUserInput!): User!
  updateUser(id: ID!, input: UpdateUserInput!): User!
  deleteUser(id: ID!): Boolean!
  createPost(input: CreatePostInput!): Post!
}

type Subscription {
  userCreated: User!
  postAdded(authorId: ID!): Post!
}

input CreateUserInput {
  name: String!
  email: String!
  age: Int
}

input UpdateUserInput {
  name: String
  email: String
}

union SearchResult = User | Post | Comment

# Interface example
interface Node {
  id: ID!
}
type User implements Node {
  id: ID!
  name: String!
}
```

### Example Queries

```graphql
# Query - get only needed fields (solves over-fetching)
query GetUser {
  user(id: "123") {
    name
    email
    posts {
      title
      comments {
        text
        author {
          name
        }
      }
    }
  }
}

# Query with variables (recommended)
query GetUser($id: ID!, $limit: Int) {
  user(id: $id) {
    name
    posts(limit: $limit) {
      title
    }
  }
}
# Variables JSON: { "id": "123", "limit": 5 }

# Multiple resources in one request (solves under-fetching, avoids N+1 REST calls)
query GetUserAndPosts {
  user(id: "123") {
    name
    email
  }
  posts(limit: 10) {
    title
    author {
      name
    }
  }
}

# Aliases - same field with different args
query {
  firstUser: user(id: "1") { name }
  secondUser: user(id: "2") { name }
}

# Fragments - reusable pieces
fragment UserFields on User {
  id
  name
  email
}
query {
  user(id: "123") {
    ...UserFields
    posts { title }
  }
  users(limit: 5) {
    ...UserFields
  }
}

# Mutation
mutation CreateUser($input: CreateUserInput!) {
  createUser(input: $input) {
    id
    name
    email
  }
}
# Variables: { "input": { "name": "John", "email": "john@example.com" } }

# Subscription (via WebSocket)
subscription OnUserCreated {
  userCreated {
    id
    name
    email
  }
}
```

### Resolvers Example (Node.js)

```js
const resolvers = {
  Query: {
    user: (parent, args, context, info) => {
      // args.id, context contains auth user, db, etc
      return db.users.findById(args.id);
    },
    users: (parent, { limit, offset, role }) => {
      return db.users.find({ role }).limit(limit).skip(offset);
    }
  },
  Mutation: {
    createUser: (parent, { input }, context) => {
      if (!context.user.isAdmin) throw new Error('Not authorized');
      return db.users.create(input);
    }
  },
  Subscription: {
    userCreated: {
      subscribe: () => pubsub.asyncIterator(['USER_CREATED'])
    }
  },
  User: {
    // Field resolver for User.posts - called when query asks for posts
    posts: (user, args, context) => {
      // user is parent object (user object returned from Query.user)
      return db.posts.findByAuthorId(user.id);
    }
  }
};
```

### N+1 Problem & DataLoader

```js
// Problem: Query users and their posts
// Query: { users { name posts { title } } }
// If 100 users, naive resolver does 1 query for users + 100 queries for posts (one per user) = 101 queries N+1

// Solution: DataLoader batches
const DataLoader = require('dataloader');
const postsLoader = new DataLoader(async (userIds) => {
  // userIds = [1,2,3,...100]
  // Single query: SELECT * FROM posts WHERE author_id IN (1,2,3,...100)
  const posts = await db.posts.findByAuthorIds(userIds);
  // Group by authorId
  return userIds.map(id => posts.filter(p => p.authorId === id));
});

// Resolver uses loader
User: {
  posts: (user) => postsLoader.load(user.id) // batched
}
// Now 2 queries only: 1 for users, 1 for all posts
```

### Advantages

- No over-fetching (client asks only needed fields) and no under-fetching (multiple resources in one request)
- Single endpoint `/graphql` simplifies
- Strong typing + introspection (tools can auto generate docs, client can introspect schema)
- Real-time via subscriptions (WebSocket)
- Versionless (add fields, deprecate old with @deprecated directive, no v1/v2)
- Great for frontend flexible needs (web vs mobile different needs same API)

### Disadvantages / Challenges

- Caching harder (single endpoint POST, not HTTP caching, need persisted queries or Apollo cache)
- File uploads complex (need multipart spec or separate REST endpoint)
- N+1 problem if not using DataLoader
- Rate limiting complex (one query can be expensive, need query complexity analysis)
- Performance: Deep nested queries can be expensive, need depth limiting
- Overkill for simple CRUD (REST simpler)
- Error handling: Always 200 OK even if error, errors in `errors` field, need to check
- Learning curve: Schema, resolvers, DataLoader

### Security Best Practices

- Query depth limiting (e.g. max depth 10 to prevent `user { posts { author { posts { author ... } } } }` deep)
- Query complexity analysis (assign cost to fields, reject if cost > 1000)
- Disable introspection in prod (optional, but helpful for attackers to know schema)
- Auth in context, check in resolvers
- Use persisted queries (whitelist queries) for public APIs

### When Use GraphQL?

- Frontend needs flexible data (web vs mobile different fields)
- Aggregate many microservices in one call (GraphQL gateway / BFF - Backend for Frontend)
- Over-fetching problem (REST /users returns 50 fields but UI needs 3)
- Real-time subscriptions needed
- Rapid frontend development (frontend can add fields without backend change if field already exists)
- **Don't use for**: Simple CRUD, public APIs where caching important, file uploads heavy, need HTTP caching

### Federation (SDE3 Level - Microservices GraphQL)

- Apollo Federation: Multiple GraphQL services (each microservice owns its types) compose into one supergraph via gateway
- Each service defines its types + extends others
- Example: User service defines User type, Post service extends User with posts field, gateway composes
- Tools: Apollo Federation, GraphQL Mesh, WunderGraph

### Tools

- **Server**: Apollo Server, GraphQL Yoga, Hasura (auto GraphQL from DB), PostGraphile
- **Client**: Apollo Client (caching), Relay (Facebook), urql, TanStack Query with GraphQL
- **IDE**: GraphiQL, Apollo Studio, Postman (supports GraphQL)
- **Codegen**: GraphQL Code Generator generates TypeScript types from schema

---

## 3. gRPC - Complete

### What is gRPC?

- gRPC = gRPC Remote Procedure Call, high performance RPC framework, developed by Google 2015, uses HTTP/2 + Protocol Buffers (Protobuf)
- Contract-first, strongly typed, language agnostic, code generation
- 7-10x faster than REST+JSON, low latency, small payload

### Key Features

- **HTTP/2**: Binary, multiplexing (many streams one TCP), header compression (HPACK), bidirectional streaming, flow control
- **Protobuf**: Binary serialization, small (3-10x smaller than JSON), fast, language neutral, schema, backward/forward compatible via field numbers
- **Streaming**: 4 types (see below)
- **Language Agnostic**: Generate client/server code in Java, Go, Node, Python, C++, etc from .proto
- **Bi-directional**: Both client and server can stream
- **Built-in Features**: Load balancing, deadlines/timeouts, cancellation, interceptors (middleware)

### Protobuf Example

```proto
syntax = "proto3";

package user;

import "google/protobuf/timestamp.proto";

option java_package = "com.example.user";
option java_multiple_files = true;

// Service definition
service UserService {
  // Unary
  rpc GetUser (GetUserRequest) returns (UserResponse);
  
  // Server streaming: Client sends one request, server streams many responses
  rpc ListUsers (ListUsersRequest) returns (stream UserResponse);
  
  // Client streaming: Client streams many requests, server returns one response
  rpc CreateUsers (stream CreateUserRequest) returns (CreateUsersSummary);
  
  // Bidirectional streaming: Both stream
  rpc Chat (stream ChatMessage) returns (stream ChatMessage);
  
  // Another unary
  rpc CreateUser (CreateUserRequest) returns (UserResponse);
}

message GetUserRequest {
  string id = 1; // field number 1, never reuse, never change type
}

message UserResponse {
  string id = 1;
  string name = 2;
  string email = 3;
  int32 age = 4;
  Role role = 5;
  google.protobuf.Timestamp created_at = 6;
  repeated string tags = 7; // list
  map<string, string> metadata = 8; // map
}

message ListUsersRequest {
  int32 page = 1;
  int32 limit = 2;
  Role role = 3;
}

message CreateUserRequest {
  string name = 1;
  string email = 2;
}

message CreateUsersSummary {
  int32 created_count = 1;
  repeated string ids = 2;
}

message ChatMessage {
  string user_id = 1;
  string message = 2;
  google.protobuf.Timestamp timestamp = 3;
}

enum Role {
  ROLE_UNSPECIFIED = 0; // first must be 0 for default
  ROLE_ADMIN = 1;
  ROLE_USER = 2;
  ROLE_GUEST = 3;
}

// Oneof example
message SearchRequest {
  oneof query {
    string name = 1;
    string email = 2;
    int32 id = 3;
  }
}
```

### Protobuf Rules & Best Practices

- Field numbers 1-15 use 1 byte, 16-2047 use 2 bytes, so reserve 1-15 for frequently used fields
- Never reuse field numbers, never change field type, only add new fields with new numbers for backward compatibility
- Use `reserved` to prevent reuse: `reserved 2, 3; reserved "old_field";`
- Use wrapper types for optional: `google.protobuf.StringValue` or in proto3 optional keyword `optional string name = 1;`
- Use `repeated` for lists, `map<K,V>` for maps, `oneof` for union (only one set)
- Enum first value must be 0

### 4 Communication Types

#### 1. Unary (Traditional Request -> Response like REST)

```java
// Server
public void getUser(GetUserRequest req, StreamObserver<UserResponse> obs) {
  UserResponse user = db.findById(req.getId());
  obs.onNext(user);
  obs.onCompleted();
}

// Client
UserResponse user = blockingStub.getUser(GetUserRequest.newBuilder().setId("123").build());
```

#### 2. Server Streaming (Client request -> Server stream responses)

- Use: Large list, real-time feed, download
- Example: ListUsers returns stream of users, server sends as soon as available

```java
// Server
public void listUsers(ListUsersRequest req, StreamObserver<UserResponse> obs) {
  for (User user : db.findAll(req.getPage(), req.getLimit())) {
    obs.onNext(convert(user));
    Thread.sleep(10); // simulate
  }
  obs.onCompleted();
}

// Client
Iterator<UserResponse> users = blockingStub.listUsers(ListUsersRequest.newBuilder().setPage(1).setLimit(100).build());
while (users.hasNext()) {
  UserResponse user = users.next();
  System.out.println(user.getName());
}
```

#### 3. Client Streaming (Client stream -> Server single response)

- Use: Upload large file in chunks, batch create

```java
// Server
public StreamObserver<CreateUserRequest> createUsers(StreamObserver<CreateUsersSummary> responseObserver) {
  return new StreamObserver<CreateUserRequest>() {
    List<String> ids = new ArrayList<>();
    public void onNext(CreateUserRequest req) {
      String id = db.create(req);
      ids.add(id);
    }
    public void onCompleted() {
      responseObserver.onNext(CreateUsersSummary.newBuilder().setCreatedCount(ids.size()).addAllIds(ids).build());
      responseObserver.onCompleted();
    }
    public void onError(Throwable t) { /* handle */ }
  };
}

// Client
StreamObserver<CreateUserRequest> requestObserver = asyncStub.createUsers(new StreamObserver<CreateUsersSummary>() {
  public void onNext(CreateUsersSummary summary) { System.out.println("Created: " + summary.getCreatedCount()); }
  public void onCompleted() {}
  public void onError(Throwable t) {}
});
requestObserver.onNext(CreateUserRequest.newBuilder().setName("John").setEmail("a@b.com").build());
requestObserver.onNext(CreateUserRequest.newBuilder().setName("Jane").setEmail("j@b.com").build());
requestObserver.onCompleted();
```

#### 4. Bidirectional Streaming (Both stream)

- Use: Chat, real-time collaborative, gaming, IoT

```java
// Server
public StreamObserver<ChatMessage> chat(StreamObserver<ChatMessage> responseObserver) {
  return new StreamObserver<ChatMessage>() {
    public void onNext(ChatMessage msg) {
      // Broadcast to all connected clients
      broadcast(msg);
      // Echo back
      responseObserver.onNext(ChatMessage.newBuilder().setMessage("Received: " + msg.getMessage()).build());
    }
    public void onCompleted() { responseObserver.onCompleted(); }
    public void onError(Throwable t) {}
  };
}
```

### gRPC Concepts

- **Channel**: Connection to server, one channel can have many streams (HTTP/2 multiplexing)
- **Stub**: Client object to call methods, types: Blocking (sync), Async (async), Future (future)
- **Deadlines/Timeouts**: Client sets deadline, server must respect, `stub.withDeadlineAfter(5, TimeUnit.SECONDS)`
- **Interceptors**: Like middleware for auth, logging, metrics
```java
// Server interceptor for auth
class AuthInterceptor implements ServerInterceptor {
  public <ReqT, RespT> ServerCall.Listener<ReqT> interceptCall(ServerCall<ReqT, RespT> call, Metadata headers, ServerCallHandler<ReqT, RespT> next) {
    String token = headers.get(Metadata.Key.of("authorization", Metadata.ASCII_STRING_MARSHALLER));
    if (!isValid(token)) { call.close(Status.UNAUTHENTICATED, new Metadata()); return new ServerCall.Listener<>(){}; }
    return next.startCall(call, headers);
  }
}
```
- **Error Handling**: gRPC status codes (0 OK, 1 CANCELLED, 2 UNKNOWN, 3 INVALID_ARGUMENT, 5 NOT_FOUND, 7 PERMISSION_DENIED, 14 UNAVAILABLE, 16 UNAUTHENTICATED)
- **Load Balancing**: Client side LB (pick first, round_robin, etc), lookaside LB (Envoy, Istio)
- **Health Checking**: gRPC health checking protocol
- **Reflection**: Server reflection to list services (for grpcurl)

### gRPC vs REST Comparison

| Aspect | gRPC | REST |
|--------|------|------|
| Format | Protobuf binary (small, fast) | JSON text (human readable, larger) |
| Protocol | HTTP/2 (multiplexing, binary, header compression) | HTTP/1.1 mostly (text, one request per connection, but HTTP/2 also possible) |
| Speed | Very fast (7-10x), low latency | Slower |
| Streaming | Yes 4 types | No (need WebSocket/SSE for streaming) |
| Browser support | Limited (needs grpc-web + Envoy proxy) | Native (fetch) |
| Contract | .proto strict, code generation | OpenAPI optional, manual |
| Code Gen | Yes auto client/server | Manual or via OpenAPI generator |
| Human readable | No binary | Yes JSON |
| Use Case | Internal microservices, high throughput, low latency, polyglot, streaming | Public APIs, external, browser, simple CRUD |
| Caching | No HTTP caching | Yes HTTP caching |
| Learning | Medium-Hard (protobuf, HTTP/2) | Easy |

### When to Use gRPC?

- Internal microservices communication (<10ms latency requirement, 1000+ RPS)
- High throughput, low latency (real-time, IoT, ML inference)
- Polyglot environments (generate code for many languages)
- Streaming needs (chat, real-time updates)
- Service mesh (Istio uses Envoy which speaks gRPC)
- **Don't use for**: Public APIs exposed to browsers (use REST), simple CRUD where JSON fine, need human readable/debuggable

### Tools

- **grpcurl**: Like curl for gRPC `grpcurl -plaintext localhost:50051 list`, `grpcurl -plaintext -d '{"id":"123"}' localhost:50051 user.UserService/GetUser`
- **BloomRPC / Postman gRPC**: GUI client
- **Envoy**: Proxy for grpc-web (browser -> Envoy (grpc-web) -> gRPC server)
- **grpc-web**: JS library for browser to call gRPC via Envoy

### gRPC-Web (Browser Support)

- Browser can't do gRPC native (needs HTTP/2 trailers, binary), so need grpc-web proxy
- Flow: Browser (grpc-web JS) -> Envoy proxy (translates grpc-web to gRPC) -> gRPC server
- Alternative: Use Connect protocol (Buf) - supports gRPC, gRPC-Web, Connect all via HTTP/1.1 and HTTP/2, more browser friendly

### Interview Answer for Mixed Usage

"In our system, public APIs are REST for compatibility and browser support, internal inter-service calls use gRPC for performance (7x faster, low latency), mobile flexible needs use GraphQL via BFF (Backend for Frontend) to avoid over-fetching, and legacy bank integration uses SOAP where we have no choice. For real-time chat we use WebSocket, and for live updates like stock prices we use SSE."

---

## 4. WebSocket - Complete

### What is WebSocket?

- Full-duplex bidirectional persistent connection over single TCP, after HTTP upgrade handshake, protocol `ws://` and `wss://` (secure)
- Unlike HTTP request-response, both client and server can send anytime
- Use: Chat, live notifications, collaborative editing (Google Docs), gaming, stock tickers, real-time dashboards

### How Works?

1. Client sends HTTP request with Upgrade: websocket
```
GET /chat HTTP/1.1
Host: example.com
Upgrade: websocket
Connection: Upgrade
Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==
Sec-WebSocket-Version: 13
```
2. Server responds 101 Switching Protocols
```
HTTP/1.1 101 Switching Protocols
Upgrade: websocket
Connection: Upgrade
Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=
```
3. Persistent TCP connection, both can send frames (text or binary) anytime
4. Close via close frame

### Example

```js
// Frontend
const ws = new WebSocket('wss://api.example.com/ws');
ws.onopen = () => { console.log('Connected'); ws.send(JSON.stringify({type:'join', room:'123'})); };
ws.onmessage = (event) => { const data = JSON.parse(event.data); console.log('Received:', data); };
ws.onclose = () => console.log('Closed');
ws.onerror = (err) => console.error(err);

// Backend Node.js with ws library
const WebSocket = require('ws');
const wss = new WebSocket.Server({ port: 8080 });
wss.on('connection', (ws, req) => {
  console.log('Client connected');
  ws.on('message', (message) => {
    const data = JSON.parse(message);
    // Broadcast to all clients
    wss.clients.forEach(client => {
      if (client.readyState === WebSocket.OPEN) client.send(JSON.stringify({user: data.user, msg: data.msg}));
    });
  });
  ws.on('close', () => console.log('Client disconnected'));
});

// With rooms (like Socket.io)
const rooms = new Map();
function joinRoom(ws, roomId) {
  if (!rooms.has(roomId)) rooms.set(roomId, new Set());
  rooms.get(roomId).add(ws);
  ws.roomId = roomId;
}
function broadcastToRoom(roomId, message) {
  const clients = rooms.get(roomId);
  if (clients) clients.forEach(c => c.send(message));
}
```

### Socket.io (Library on top of WebSocket)

- Provides fallback to long polling if WebSocket not supported, rooms, namespaces, auto reconnection, binary support
- Easier than raw WebSocket
- Example:
```js
// Server
const io = require('socket.io')(server);
io.on('connection', (socket) => {
  socket.on('join', (room) => socket.join(room));
  socket.on('chat', (data) => io.to(data.room).emit('chat', data));
});
// Client
const socket = io('https://api.example.com');
socket.emit('join', 'room123');
socket.on('chat', (data) => console.log(data));
```

### WebSocket vs HTTP vs SSE

| Feature | WebSocket | HTTP REST | SSE |
|---------|-----------|-----------|-----|
| Direction | Bi-directional | Client->Server request/response | Server->Client only |
| Persistent | Yes | No (keep-alive short) | Yes |
| Overhead | Low after handshake (2 bytes frame header) | High (headers each request) | Low |
| Use | Chat, gaming, collaborative | CRUD | Live feed, notifications, stock prices |
| Protocol | ws:// wss:// | http:// https:// | http:// https:// with text/event-stream |
| Browser support | Yes | Yes | Yes (except IE) |
| Reconnection | Manual | N/A | Auto (browser auto reconnects) |

### Scaling WebSocket

- **Problem**: WebSocket connection sticky to one server, if user A connected to server 1 and user B to server 2, how to send message from A to B?
- **Solution**: Use Redis pub/sub or Kafka
  - Server 1 publishes message to Redis channel `chat:room123`
  - All servers subscribe to Redis channel, server 2 receives and sends to its connected clients in room123
- **Sticky Sessions**: Use IP hash LB or cookie affinity to route same client to same server, but still need pub/sub for cross-server messaging
- **Example with Redis**:
```js
const redis = require('redis');
const pub = redis.createClient();
const sub = redis.createClient();
sub.subscribe('chat');
sub.on('message', (channel, message) => {
  const data = JSON.parse(message);
  // Broadcast to local clients in room
  wss.clients.forEach(client => {
    if (client.roomId === data.roomId) client.send(JSON.stringify(data));
  });
});
// When server receives message from its client
ws.on('message', (msg) => {
  const data = JSON.parse(msg);
  pub.publish('chat', JSON.stringify({roomId: data.roomId, msg: data.msg}));
});
```

---

## 5. Server-Sent Events (SSE) - Complete

### What is SSE?

- One-way server to client real-time updates over HTTP, text/event-stream MIME type, browser API EventSource
- Simpler than WebSocket, auto reconnection, HTTP based, firewall friendly
- Use: Live feed, stock prices, notifications where client doesn't need to send often (only server pushes), progress updates

### How Works?

- Client makes GET request to /stream, server keeps connection open and sends events as text
- Format: `data: {...}\n\n` (double newline ends event), optional `event: customEvent`, `id: 123`, `retry: 10000`

### Example

```js
// Frontend
const es = new EventSource('/api/stream');
es.onmessage = (event) => {
  const data = JSON.parse(event.data);
  console.log('Received:', data);
};
es.addEventListener('customEvent', (event) => {
  console.log('Custom:', event.data);
});
es.onerror = (err) => console.error(err);
// Close
es.close();

// Backend Node.js
app.get('/api/stream', (req, res) => {
  res.writeHead(200, {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache',
    'Connection': 'keep-alive',
    'Access-Control-Allow-Origin': '*'
  });
  // Send event every 1 sec
  const interval = setInterval(() => {
    const data = { time: new Date().toISOString(), value: Math.random() };
    res.write(`data: ${JSON.stringify(data)}\n\n`);
    // Or with event type and id
    // res.write(`id: ${Date.now()}\n`);
    // res.write(`event: stockUpdate\n`);
    // res.write(`data: ${JSON.stringify(data)}\n\n`);
  }, 1000);
  // Clean up on client disconnect
  req.on('close', () => {
    clearInterval(interval);
    res.end();
  });
});

// Java Spring Boot SSE
@RestController
class SseController {
  @GetMapping("/stream")
  public SseEmitter stream() {
    SseEmitter emitter = new SseEmitter(Long.MAX_VALUE);
    Executors.newSingleThreadExecutor().execute(() -> {
      try {
        for (int i=0; i<10; i++) {
          emitter.send(SseEmitter.event().name("message").data("Data " + i));
          Thread.sleep(1000);
        }
        emitter.complete();
      } catch (Exception e) { emitter.completeWithError(e); }
    });
    return emitter;
  }
}
```

### SSE vs WebSocket

- SSE is simpler, HTTP based, auto reconnection, text only (but can send JSON string), one-way server->client, browser limit 6 connections per domain for HTTP/1.1 (HTTP/2 multiplexing solves)
- WebSocket is bidirectional, binary + text, more complex, needs ws protocol
- **Use SSE when**: Only server needs to push, client rarely sends (e.g. stock ticker, news feed, progress), need simple HTTP, need auto reconnection
- **Use WebSocket when**: Both client and server need to send frequently (chat, gaming, collaborative editing)

---

## 6. Webhooks - Complete

### What are Webhooks?

- User-defined HTTP callbacks, when event happens in system A, system A POSTs to URL registered by user in system B
- Reverse of API: Instead of you polling API for changes, API pushes to you when change happens
- Also called HTTP callbacks, reverse APIs

### How Works?

1. User registers webhook: POST /webhooks with `url: https://myapp.com/webhook`, `events: ["order.created", "payment.succeeded"]`, maybe secret for signing
2. Server stores webhook
3. When event occurs (order created), server POSTs to registered URL with event payload
4. User's server receives POST and processes (e.g. send email, update DB)
5. Server should retry with exponential backoff if user's URL fails (e.g. 3 retries), and have DLQ

### Example

```js
// Register webhook (client side - your app registers with provider like GitHub, Stripe)
fetch('https://api.github.com/repos/user/repo/hooks', {
  method: 'POST',
  headers: { 'Authorization': 'token abc', 'Content-Type': 'application/json' },
  body: JSON.stringify({
    name: 'web',
    config: { url: 'https://myapp.com/webhooks/github', content_type: 'json', secret: 'mysecret' },
    events: ['push', 'pull_request']
  })
});

// Your app receives webhook (your server endpoint)
app.post('/webhooks/github', (req, res) => {
  // Verify signature
  const signature = req.headers['x-hub-signature-256'];
  const expected = 'sha256=' + crypto.createHmac('sha256', 'mysecret').update(JSON.stringify(req.body)).digest('hex');
  if (signature !== expected) return res.status(401).send('Invalid signature');
  
  const event = req.headers['x-github-event']; // push, pull_request
  console.log('Received event:', event, req.body);
  // Process event
  if (event === 'push') {
    // Trigger CI build
  }
  res.status(200).send('OK'); // Must respond quickly 200, process async via queue
});

// Provider side - sending webhook (e.g. your system sending to user)
async function triggerWebhooks(eventType, payload) {
  const webhooks = await db.webhooks.findByEvent(eventType);
  for (const hook of webhooks) {
    try {
      const signature = crypto.createHmac('sha256', hook.secret).update(JSON.stringify(payload)).digest('hex');
      await fetch(hook.url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-Webhook-Signature': signature, 'X-Event-Type': eventType },
        body: JSON.stringify(payload)
      });
    } catch (err) {
      // Retry with backoff via queue
      await queue.add('webhook_retry', { hookId: hook.id, payload, attempt: 1 }, { delay: 1000 });
    }
  }
}
```

### Webhooks Best Practices

- **Security**: Sign payload with HMAC secret, user verifies signature to ensure from you, use HTTPS, include timestamp to prevent replay, whitelist IPs if possible
- **Retries**: Exponential backoff (1 sec, 2 sec, 4 sec, 8 sec...), max retries 3-5, then DLQ and alert, include `X-Retry-Count` header
- **Idempotency**: Include event ID, user should handle duplicate (at-least-once delivery), store processed event IDs
- **Timeout**: Set timeout 5-10 sec for webhook call, don't block long
- **Async**: Process webhook async via queue, respond 200 quickly, don't do heavy work in webhook handler
- **Versioning**: Include version in payload, allow user to specify version when registering
- **Documentation**: Provide docs for payload format, events, retry policy, how to verify signature
- **Testing**: Provide way to test webhook (e.g. dashboard to send test event)

### Webhooks vs Polling vs WebSocket vs SSE

| Method | Direction | Real-time | Efficiency | Use Case |
|--------|-----------|-----------|------------|----------|
| **Polling** | Client polls server repeatedly | Near real-time (delay = poll interval) | Inefficient (many empty responses) | Simple, when real-time not critical, old browsers |
| **Long Polling** | Client requests, server holds until data, then responds, client immediately re-requests | Near real-time | Better than polling but still overhead | When WebSocket not allowed, legacy |
| **Webhooks** | Server pushes to client URL when event | Real-time | Efficient (only when event) | Server-to-server event notifications (GitHub push, Stripe payment) |
| **WebSocket** | Bi-directional persistent | Real-time | Efficient after handshake | Chat, gaming, collaborative, client-to-server + server-to-client frequent |
| **SSE** | Server pushes to client over HTTP | Real-time | Efficient | Live feed, notifications, server->client only |

---

## 7. API Comparison Summary & Decision Guide

| Criteria | REST | GraphQL | gRPC | SOAP | WebSocket | SSE | Webhooks |
|----------|------|---------|------|------|-----------|-----|----------|
| **Format** | JSON | JSON | Protobuf binary | XML | Text/Binary frames | Text/event-stream | JSON |
| **Protocol** | HTTP/1.1, HTTP/2 | HTTP | HTTP/2 | HTTP/SMTP/TCP | WS/WSS (HTTP upgrade) | HTTP | HTTP |
| **Contract** | OpenAPI optional | Schema mandatory | Proto mandatory | WSDL mandatory | None | None | None (docs) |
| **Caching** | Easy HTTP cache | Hard (single endpoint) | No | No | No | No | No |
| **Browser** | Excellent native | Excellent | Needs grpc-web proxy | Poor | Excellent | Excellent | N/A (server-to-server) |
| **Streaming** | No | Subscription via WS | Yes 4 types | No | Yes bi-di | Yes server->client | No (one-off POST) |
| **Performance** | Medium | Medium | High (binary, HTTP/2) | Low (XML heavy) | Low overhead after handshake | Low | Medium (HTTP POST) |
| **Learning** | Easy | Medium | Medium-Hard | Hard | Easy-Medium | Easy | Easy |
| **Use Case** | Public APIs, CRUD, simple | Flexible frontend, BFF, aggregation | Internal microservices, high perf, streaming | Legacy enterprise, banking with WS-Security | Chat, gaming, collaborative real-time bi-di | Live feed, notifications, stock ticker server->client | Server-to-server event notifications (GitHub, Stripe) |
| **Real-time** | No (polling) | Yes via subscription | Yes via streaming | No | Yes | Yes | Yes (event driven) |

### Decision Tree for SDE3 Interview

```
Need real-time?
  Yes -> Both client and server need to send frequently?
    Yes -> WebSocket (chat, gaming, collaborative)
    No only server pushes -> SSE (live feed, notifications, stock)
  No -> Server-to-server event notification?
    Yes -> Webhooks (GitHub push, Stripe payment)
    No -> Internal microservices high perf?
      Yes -> gRPC (7x faster, streaming, polyglot)
      No -> Flexible frontend needs (web vs mobile different fields) or aggregate many microservices?
        Yes -> GraphQL (BFF, avoid over-fetching)
        No -> Legacy enterprise with WS-Security, ACID transactions?
          Yes -> SOAP (banking, telecom)
          No -> REST (default for public APIs, CRUD, simple, cacheable)
```

### Real World Architecture Example Using All

```
Mobile/Web Client
  |
  | REST (public API) for CRUD
  | GraphQL (BFF) for flexible frontend aggregation
  | WebSocket for chat
  | SSE for live order tracking
  v
API Gateway (Kong) - Auth, Rate Limiting, Routing
  |
  | REST / GraphQL -> Microservices (Node/Spring Boot)
  | gRPC internal between microservices (User Service <-gRPC-> Order Service) for perf
  | Events via Kafka (OrderCreated -> Inventory, Payment, Email)
  | SOAP adapter for legacy bank payment gateway
  | Webhooks to notify external partners (e.g. shipping partner when order shipped)
  v
Databases, Cache, Queue, Storage
```

This is complete guide for all API types. For REST deep dive see rest_api_complete.md

---

## Expanded: More API Types & Modern Alternatives

### 7. tRPC - Type-safe API without REST/gRPC (Trending 2024-25)

**What**: Type-safe RPC framework for TypeScript, no codegen, no schema, TS types shared automatically frontend-backend via inference

**Architecture**: Define procedures (queries, mutations, subscriptions) on server with Zod validation, client gets fully type-safe client with autocomplete, no REST endpoints manually

```ts
// Server - backend
import { initTRPC } from '@trpc/server';
import { z } from 'zod';
const t = initTRPC.create();
export const appRouter = t.router({
  user: t.router({
    getById: t.procedure.input(z.object({ id: z.string() })).query(({ input }) => {
      return db.user.findById(input.id);
    }),
    create: t.procedure.input(z.object({ name: z.string(), email: z.string().email() })).mutation(({ input }) => {
      return db.user.create(input);
    }),
  }),
});
export type AppRouter = typeof appRouter;

// Client - frontend (Next.js)
import { createTRPCReact } from '@trpc/react-query';
import type { AppRouter } from '../server/router';
const trpc = createTRPCReact<AppRouter>();
function UserComponent({ id }: { id: string }) {
  const { data, isLoading } = trpc.user.getById.useQuery({ id }); // fully type-safe, autocomplete, no fetch!
  const mutation = trpc.user.create.useMutation();
  // data is typed as User | undefined
}
// No REST, no OpenAPI, no codegen - TS types inferred!
```

**Pros**: Full type safety from DB to UI without codegen, great DX (autocomplete), no REST boilerplate, fast dev, works with Next.js, TanStack Query under hood for caching
**Cons**: TS only, not for polyglot, not for public APIs (only TS clients), smaller ecosystem than REST
**When**: Fullstack TypeScript (T3 Stack), internal APIs where both frontend and backend TS, startups, need type safety without REST overhead - **trending 2024-25 for TS fullstack**
**Comparison**: REST needs OpenAPI + codegen for types, gRPC needs proto + codegen, tRPC needs nothing - TS inference does all

### 8. Connect Protocol (Buf - Modern gRPC Alternative)

**What**: Protocol by Buf that supports gRPC, gRPC-Web, and Connect (HTTP/1.1 + HTTP/2) all via same server, browser friendly, no Envoy proxy needed for gRPC-Web

**Why**: gRPC needs HTTP/2 and Envoy proxy for browser, Connect works with HTTP/1.1 and HTTP/2, supports browser natively, simpler than gRPC-Web

**How**: Use Buf's Connect library, server handles all 3 protocols, client can use Connect protocol via fetch

```ts
// Server with Connect (Go example)
connect.NewReadWriteHandler(...)

// Client - browser can call directly via fetch, no Envoy!
fetch('https://api.example.com/user.v1.UserService/GetUser', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ id: "123" })
});
```

**Pros**: Browser friendly without proxy, supports all gRPC features, HTTP/1.1 compatible, simpler than gRPC-Web
**Cons**: Newer, smaller ecosystem than gRPC
**When**: Want gRPC benefits but need browser support without Envoy, modern alternative to gRPC-Web

### 9. GraphQL Federation Expanded (SDE3 Level)

**Problem**: Many microservices each have own GraphQL schema, how to compose into one supergraph for frontend?

**Solution: Apollo Federation**

```graphql
# User service (owns User)
type User @key(fields: "id") {
  id: ID!
  name: String!
  email: String!
}

# Post service (owns Post, extends User)
type Post @key(fields: "id") {
  id: ID!
  title: String!
  author: User!
}
extend type User @key(fields: "id") {
  id: ID! @external
  posts: [Post!]!
}

# Gateway composes both into supergraph
# Client query:
query {
  user(id: "123") {
    name
    posts {
      title
    }
  }
}
# Gateway: Fetches user from User service, then posts from Post service via _entities query, merges
```

**Federation v2**: Improved, @shareable, @override, @provides

**Tools**: Apollo Federation, GraphQL Mesh (can federate REST + gRPC + GraphQL into GraphQL), WunderGraph, Hasura remote joins

**When**: Many microservices with GraphQL, need single endpoint for frontend (BFF), each team owns its types

### 10. AsyncAPI (For Event-Driven APIs)

**What**: Like OpenAPI but for async/event-driven APIs (Kafka, RabbitMQ, WebSocket), defines channels, messages, schemas

**Why**: REST has OpenAPI, async needs AsyncAPI for docs, codegen, testing

```yaml
asyncapi: 2.6.0
info: { title: Order Events, version: 1.0.0 }
servers:
  production:
    url: kafka://kafka.example.com:9092
    protocol: kafka
channels:
  orderCreated:
    address: orders.created
    messages:
      orderCreated:
        payload:
          type: object
          properties:
            orderId: { type: string }
            userId: { type: string }
            total: { type: number }
```

**Use**: Document Kafka topics, generate docs, code, testing for event-driven

---

## Expanded: gRPC Deep Dive - Load Balancing, Error Handling, Interceptors

### gRPC Load Balancing

**Client-side LB** (gRPC client has list of servers from service discovery, chooses):
- Pick first, Round Robin, Weighted Round Robin, Least Request
- Config via service config JSON:
```json
{
  "loadBalancingConfig": [{ "round_robin": {} }]
}
```

**Lookaside LB** (External LB like Envoy, Istio, AWS App Mesh):
- Client talks to Envoy proxy, Envoy does LB to backends, client doesn't know backends
- Used in service mesh

**Example with K8s**: gRPC client uses K8s headless service DNS to get all pod IPs, then round_robin LB across pods

### gRPC Error Handling Best Practices

```java
// Server - return proper status code
public void getUser(GetUserRequest req, StreamObserver<UserResponse> obs) {
  try {
    User user = db.findById(req.getId());
    if (user == null) {
      obs.onError(Status.NOT_FOUND.withDescription("User " + req.getId() + " not found").asRuntimeException());
      return;
    }
    obs.onNext(convert(user));
    obs.onCompleted();
  } catch (Exception e) {
    obs.onError(Status.INTERNAL.withDescription("Internal error").withCause(e).asRuntimeException());
  }
}

// Client - handle status
try {
  UserResponse user = stub.getUser(req);
} catch (StatusRuntimeException e) {
  if (e.getStatus().getCode() == Status.Code.NOT_FOUND) {
    // handle not found
  } else if (e.getStatus().getCode() == Status.Code.UNAUTHENTICATED) {
    // refresh token
  } else {
    // retry with backoff if UNAVAILABLE
  }
}
```

### gRPC Interceptors (Middleware) - Auth, Logging, Metrics

```java
// Server interceptor for logging + metrics
class LoggingInterceptor implements ServerInterceptor {
  public <ReqT, RespT> ServerCall.Listener<ReqT> interceptCall(ServerCall<ReqT, RespT> call, Metadata headers, ServerCallHandler<ReqT, RespT> next) {
    long start = System.nanoTime();
    ServerCall<ReqT, RespT> wrappedCall = new ForwardingServerCall.SimpleForwardingServerCall<ReqT, RespT>(call) {
      public void close(Status status, Metadata trailers) {
        long duration = System.nanoTime() - start;
        log.info("Method {} status {} duration {}ms", call.getMethodDescriptor().getFullMethodName(), status.getCode(), duration/1e6);
        metrics.record(status.getCode().toString(), duration);
        super.close(status, trailers);
      }
    };
    return next.startCall(wrappedCall, headers);
  }
}

// Client interceptor for auth header
class AuthClientInterceptor implements ClientInterceptor {
  public <ReqT, RespT> ClientCall<ReqT, RespT> interceptCall(MethodDescriptor<ReqT, RespT> method, CallOptions callOptions, Channel next) {
    return new ForwardingClientCall.SimpleForwardingClientCall<ReqT, RespT>(next.newCall(method, callOptions)) {
      public void start(Listener<RespT> responseListener, Metadata headers) {
        headers.put(Metadata.Key.of("authorization", Metadata.ASCII_STRING_MARSHALLER), "Bearer " + getToken());
        super.start(responseListener, headers);
      }
    };
  }
}
```

### gRPC Health Checking

```proto
// Standard health checking proto
syntax = "proto3";
package grpc.health.v1;
service Health {
  rpc Check(HealthCheckRequest) returns (HealthCheckResponse);
  rpc Watch(HealthCheckRequest) returns (stream HealthCheckResponse);
}
message HealthCheckRequest { string service = 1; }
message HealthCheckResponse {
  enum ServingStatus { UNKNOWN=0; SERVING=1; NOT_SERVING=2; SERVICE_UNKNOWN=3; }
  ServingStatus status = 1;
}
```
- K8s liveness/readiness probes can use gRPC health check
- Tools: grpc_health_probe binary

---

## Expanded: WebSocket Scaling with Kafka (Production Grade)

**Problem**: 100k concurrent WebSocket connections, 10 servers, user A on server 1 wants to chat with user B on server 2

**Solution: Redis Pub/Sub or Kafka**

**Option 1: Redis Pub/Sub (Simple, for small-medium)**
```js
// Each server subscribes to Redis channel
const redisSub = redis.createClient();
redisSub.subscribe('chat');
redisSub.on('message', (channel, message) => {
  const { roomId, data } = JSON.parse(message);
  // Broadcast to local clients in room
  wss.clients.forEach(client => {
    if (client.roomId === roomId && client.readyState === WebSocket.OPEN) {
      client.send(JSON.stringify(data));
    }
  });
});

// When server receives message from its client
ws.on('message', (msg) => {
  const data = JSON.parse(msg);
  // Publish to Redis, all servers receive
  redisPub.publish('chat', JSON.stringify({ roomId: data.roomId, data }));
});
```

**Option 2: Kafka (For large scale, persistent, replay)**
```js
// Producer: When server receives message, produce to Kafka topic chat-messages partitioned by roomId
await kafkaProducer.send({ topic: 'chat-messages', messages: [{ key: roomId, value: JSON.stringify(data) }] });

// Consumer: Each server consumes Kafka topic, but only processes messages for rooms where it has clients
// Use consumer group per server? Actually each server needs all messages for its rooms, so use pub/sub not queue
// Solution: Each server is in same consumer group? No, then only one server gets message. Need each server gets all messages for its rooms.
// Approach: Use Kafka with each server as separate consumer group, or use Redis for pub/sub and Kafka for persistence

// Better: Use Redis for real-time pub/sub + Kafka for persistence
// Real-time: Redis pub/sub for instant delivery
// Persistence: Also produce to Kafka for storage, offline messages, history
```

**Option 3: Consistent Hashing for Room Affinity**
- Hash roomId to server, all users in same room go to same server via LB consistent hashing (e.g. roomId % N servers)
- Pros: No cross-server messaging needed for same room, efficient
- Cons: Hot room (100k users in one room) overloads one server, need handle hot rooms via splitting

**Production Stack for Chat (WhatsApp scale)**:
```
Client (WebSocket) -> ALB (least connections + sticky cookie for WS) -> Chat Servers (Netty, 10k connections per server, 100 servers for 1M concurrent)
  -> Redis Cluster (pub/sub for real-time cross-server + presence online/offline via SETEX with TTL heartbeat)
  -> Kafka (persistence for messages, offline queue, history)
  -> Cassandra (message storage partitioned by conversation_id)
  -> S3 + CDN for media
```

---

## Expanded: SSE with Last-Event-ID (Resume on Reconnect)

**Problem**: SSE connection drops, client reconnects, misses events during disconnect

**Solution: Last-Event-ID**

```js
// Server sends id
res.write(`id: ${eventId}\n`);
res.write(`data: ${JSON.stringify(data)}\n\n`);

// Client auto sends Last-Event-ID on reconnect
const es = new EventSource('/stream');
es.onmessage = (e) => {
  console.log(e.data, e.lastEventId); // lastEventId is id sent by server
};
// On reconnect, browser automatically sends header Last-Event-ID: <last received id>
// Server can read header and replay missed events from that id

// Backend handling Last-Event-ID
app.get('/stream', (req, res) => {
  const lastEventId = req.headers['last-event-id'] || 0;
  // Fetch missed events from DB/Kafka from lastEventId
  const missedEvents = db.getEventsSince(lastEventId);
  missedEvents.forEach(event => {
    res.write(`id: ${event.id}\n`);
    res.write(`data: ${JSON.stringify(event.data)}\n\n`);
  });
  // Then continue live
});
```

---

## Expanded: API Gateway Pattern for Mixed APIs

**How to handle REST + GraphQL + gRPC + WebSocket + Webhooks in one gateway?**

```
Client
  |
  | HTTP/REST, GraphQL, WebSocket, SSE, Webhooks
  v
API Gateway (Kong / AWS API Gateway / Apigee / NGINX)
  - Features:
    - Auth: JWT validation, OAuth2
    - Rate Limiting: Redis token bucket per user/IP
    - Routing: /api/v1/users -> user-service, /graphql -> graphql-gateway, /ws -> chat-service
    - Protocol Translation: REST to gRPC (gateway translates REST JSON to gRPC protobuf to backend)
    - Aggregation: /api/v1/users/{id}/dashboard aggregates calls to user-service, order-service, payment-service via gRPC parallel and returns combined
    - Caching: Cache GET responses in Redis
    - Logging, Metrics, Tracing: OpenTelemetry
    - WAF: OWASP protection
  |
  | gRPC internal (fast) + Kafka events async
  v
Microservices
  - REST services (Spring Boot)
  - gRPC services (Go, Java)
  - GraphQL gateway (Apollo Federation) that composes REST + gRPC via DataSources
  - WebSocket service (Node.js)
  - Legacy SOAP adapter service that translates REST to SOAP for bank
```

**Kong Example for Protocol Translation (REST to gRPC)**:
```yaml
# Kong route: REST /api/v1/users/{id} -> gRPC user.UserService/GetUser
services:
- name: user-service-grpc
  url: grpc://user-service:50051
  routes:
  - name: get-user-rest
    paths: ["/api/v1/users/(?<id>[^/]+)"]
    plugins:
    - name: grpc-gateway
      config:
        proto: user.proto
        service: user.UserService
        method: GetUser
        # Translates REST GET /api/v1/users/123 to gRPC GetUserRequest { id: "123" }
```

**GraphQL as BFF (Backend for Frontend) Aggregation**:
```js
// GraphQL gateway aggregates REST and gRPC
const resolvers = {
  Query: {
    user: async (_, { id }, { dataSources }) => {
      // Parallel fetch from REST and gRPC
      const [user, orders, recommendations] = await Promise.all([
        dataSources.userAPI.getUser(id), // REST
        dataSources.orderService.getOrdersByUserId(id), // gRPC
        dataSources.recommendationService.getForUser(id) // gRPC
      ]);
      return { ...user, orders, recommendations };
    }
  }
};
// Frontend single GraphQL query gets all: user + orders + recommendations in one request, avoids 3 REST calls
```

This expanded guide covers all API types with production-grade examples, scaling, and decision making for SDE3.

---

## Expanded Again: Even More Modern API Technologies

### 11. WebTransport - Next Gen WebSocket (HTTP/3 based)

**What**: New protocol for low latency bidirectional communication over HTTP/3 (QUIC), multiplexed streams, unidirectional and bidirectional streams, datagrams (unreliable like UDP), better than WebSocket for low latency

**Why**: WebSocket is HTTP/1.1 based, one stream per connection, head-of-line blocking, no datagrams. WebTransport uses HTTP/3 QUIC which has multiplexing, no head-of-line blocking, supports unreliable datagrams for gaming (like UDP), faster handshake (0-RTT)

**Features**:
- Multiple streams (bidirectional and unidirectional) over one connection (multiplexing)
- Datagrams (unreliable, like UDP) for gaming, live media where loss okay but latency critical
- 0-RTT handshake (faster than WebSocket)
- HTTP/3 based (QUIC)

**Use**: Gaming (low latency + datagrams for player positions), live media, low latency real-time where WebSocket not enough

**Status**: New, browser support growing (Chrome 97+), server support via Cloudflare, etc

**Example**:
```js
// Client
const transport = new WebTransport('https://example.com:4433/counter');
await transport.ready;
const stream = await transport.createBidirectionalStream();
const writer = stream.writable.getWriter();
const reader = stream.readable.getReader();
writer.write(new TextEncoder().encode('Hello'));
const { value } = await reader.read();
console.log(new TextDecoder().decode(value));

// Datagrams (unreliable)
const datagramWriter = transport.datagrams.writable.getWriter();
datagramWriter.write(new TextEncoder().encode('Player position x:10 y:20')); // unreliable, like UDP
```

**WebSocket vs WebTransport**:

| Feature | WebSocket | WebTransport |
|---------|-----------|--------------|
| Protocol | HTTP/1.1 upgrade, TCP | HTTP/3 QUIC, UDP based |
| Streams | One stream per connection | Multiple streams (bidi + uni) |
| Datagrams | No (reliable only) | Yes (unreliable like UDP) |
| Handshake | 1-RTT | 0-RTT possible (faster) |
| Head-of-line blocking | Yes (TCP) | No (QUIC) |
| Use | Chat, real-time | Gaming, live media, low latency |

### 12. MQTT - IoT Protocol

**What**: Lightweight pub/sub protocol for IoT, small header (2 bytes), low bandwidth, low power, reliable, for constrained devices

**Architecture**: Publisher -> Broker (MQTT broker like Mosquitto, HiveMQ, AWS IoT) -> Subscribers, topics hierarchical `sensors/temperature/room1`

**QoS Levels**:
- QoS 0: At most once (fire and forget, like UDP)
- QoS 1: At least once (ack, may duplicate)
- QoS 2: Exactly once (4-way handshake, no duplicate, no loss)

**Use**: IoT sensors, smart home, connected cars, low bandwidth, low power devices

**Example**:
```js
// Publisher (IoT sensor)
mqttClient.publish('sensors/temperature/room1', JSON.stringify({ temp: 25, time: Date.now() }), { qos: 1 });

// Subscriber (backend)
mqttClient.subscribe('sensors/temperature/#'); // # wildcard for all rooms
mqttClient.on('message', (topic, message) => {
  const data = JSON.parse(message);
  console.log(`Temperature in ${topic}: ${data.temp}`);
});
```

### 13. RSocket - Reactive Streaming

**What**: Binary protocol for reactive streams, supports 4 interaction models like gRPC (request-response, fire-and-forget, request-stream, channel), plus backpressure, resumability, multiplexing over single connection

**Use**: Reactive microservices, IoT, browser-server reactive, Spring WebFlux uses RSocket

**Comparison gRPC vs RSocket**:
- Both support 4 streaming types
- RSocket has better backpressure, resumability (resume after disconnect), multiplexing, binary
- gRPC more mature, more languages, better tooling
- RSocket used in Spring ecosystem, gRPC more general

### 14. Falcor (Netflix) - Alternative to GraphQL

**What**: Netflix's alternative to GraphQL, one model for all data, JSON Graph, client asks for paths, server returns JSON Graph with requested paths

**Example**:
```js
// Falcor - client asks for paths
model.get(["users", 123, ["name", "email"]], ["users", 123, "posts", { from: 0, to: 5 }, "title"])
// Returns JSON Graph
{
  users: {
    123: {
      name: "John",
      email: "a@b.com",
      posts: {
        0: { title: "Post 1" },
        1: { title: "Post 2" }
      }
    }
  }
}
```

**GraphQL vs Falcor**:
- GraphQL: Query language, strong typing, introspection, many tools
- Falcor: JSON Graph, paths, simpler, but less ecosystem than GraphQL
- Both solve over-fetching, Falcor less popular than GraphQL

### 15. OData - Open Data Protocol (Microsoft)

**What**: Standard for building and consuming RESTful APIs with querying capabilities via URL (filtering, sorting, pagination, expanding) - like GraphQL but via REST URL conventions

**Example**:
```
GET /Products?$filter=Price ge 100 and Price le 1000&$orderby=Rating desc&$top=20&$skip=40&$expand=Category&$select=Name,Price
```

**Use**: Microsoft ecosystem, Dynamics, SharePoint, enterprise needing standardized querying via REST

**Pros**: Standardized querying, many libs, $filter, $orderby, $top, $skip, $expand, $select
**Cons**: Verbose URLs, complex, less flexible than GraphQL, Microsoft centric

---

## Expanded: Production Patterns for APIs

### 16. API Rate Limiting Distributed with Sliding Window Counter (Production Code)

Already covered but add more on **multi-level rate limiting**:

```java
// Multi-level: Global + Per User + Per Endpoint

@Component
class MultiLevelRateLimiter {
  // Global: 10k RPS for whole system
  // Per User: 100 req/min per user
  // Per Endpoint: /api/payment 10 req/min (critical)

  public boolean allow(String userId, String endpoint) {
    // Check global
    if (!checkGlobal()) return false; // 10k RPS
    // Check per user
    if (!checkPerUser(userId)) return false; // 100 req/min
    // Check per endpoint
    if ("/api/payment".equals(endpoint) && !checkPerEndpoint(userId, endpoint)) return false; // 10 req/min for payment
    return true;
  }

  private boolean checkGlobal() {
    // Redis INCR with TTL 1 sec, if count > 10000 reject
    Long count = redis.incr("ratelimit:global:" + System.currentTimeMillis()/1000);
    if (count == 1) redis.expire("ratelimit:global:" + System.currentTimeMillis()/1000, 1);
    return count <= 10000;
  }

  private boolean checkPerUser(String userId) {
    // Sliding window counter via Lua as earlier
    return slidingWindowAllow("ratelimit:user:" + userId, 100, 60);
  }

  private boolean checkPerEndpoint(String userId, String endpoint) {
    return slidingWindowAllow("ratelimit:endpoint:" + userId + ":" + endpoint, 10, 60);
  }
}
```

### 17. API Caching with CDNs and Cache Invalidation

**CDN Caching for REST APIs**:

```
GET /api/products?category=electronics

CDN caches with TTL 60 sec, key = URL + query params + maybe Authorization header? No, don't cache personalized, only public

Cache-Control: public, max-age=60, s-maxage=60, stale-while-revalidate=30

- public: Can be cached by CDN and browser
- max-age=60: Browser cache 60 sec
- s-maxage=60: CDN cache 60 sec (shared cache)
- stale-while-revalidate=30: If stale, serve stale while revalidating in background for 30 sec (fast)

For personalized: Cache-Control: private, no-store or private, max-age=60 (only browser, not CDN)
```

**Cache Invalidation**:

- **TTL**: Expire after time, simple but stale
- **Event-based**: When product updated, publish event to Kafka, cache service listens and deletes cache key + purges CDN via CloudFront invalidation API
```java
@KafkaListener(topics="product-updated")
public void handle(ProductUpdatedEvent event) {
  redis.del("product:" + event.getId());
  cloudFront.createInvalidation("/api/products/" + event.getId(), "/api/products*");
}
```
- **Versioned URL**: `/api/products?version=123` where version is updated when data changes, old version cached, new version new URL, no invalidation needed but need update URL

### 18. API Versioning with GraphQL (No Versioning, Evolution)

**GraphQL Evolution**:

- No URL versioning, only one endpoint /graphql, evolve schema by adding fields, deprecating old fields with @deprecated directive

```graphql
type User {
  id: ID!
  firstName: String! @deprecated(reason: "Use fullName instead")
  lastName: String! @deprecated(reason: "Use fullName instead")
  fullName: String! # new field
  email: String!
}

# Client can still query old fields but gets deprecation warning in tools
# After all clients migrated, remove old fields in next major version (breaking but okay with notice)
```

**Pros**: No versioning overhead, single endpoint, clients can migrate gradually
**Cons**: Need discipline, can't do breaking changes without deprecation period, need monitor deprecated field usage via metrics

### 19. gRPC + REST Transcoding (gRPC-Gateway)

**What**: Define gRPC service with HTTP annotations, gRPC-Gateway generates REST API from gRPC proto automatically, one proto serves both gRPC and REST

```proto
syntax = "proto3";
package user;
import "google/api/annotations.proto";

service UserService {
  rpc GetUser (GetUserRequest) returns (UserResponse) {
    option (google.api.http) = {
      get: "/api/v1/users/{id}"
    };
  }
  rpc CreateUser (CreateUserRequest) returns (UserResponse) {
    option (google.api.http) = {
      post: "/api/v1/users"
      body: "*"
    };
  }
}

// gRPC-Gateway generates REST API from this proto:
// GET /api/v1/users/{id} -> gRPC GetUser
// POST /api/v1/users -> gRPC CreateUser
```

**Pros**: One proto serves both gRPC (internal high perf) and REST (public browser friendly), no duplication, single source of truth
**Cons**: Need gRPC-Gateway proxy (Envoy or grpc-gateway), adds hop
**Use**: Want gRPC internal + REST public from same proto, e.g. microservices internal gRPC but public REST for external

**Tools**: grpc-gateway (Go), Envoy gRPC-JSON transcoder filter

### 20. OpenAPI + gRPC + GraphQL Comparison for Code Generation

| Feature | OpenAPI (REST) | gRPC (Protobuf) | GraphQL (SDL) |
|---------|----------------|-----------------|---------------|
| **Contract** | openapi.yaml | .proto | schema.graphql |
| **Code Gen Client** | openapi-generator (50+ languages) | protoc (many languages) | GraphQL Codegen (TS, etc) |
| **Code Gen Server** | openapi-generator server stubs | protoc server stubs | Apollo Server resolvers from schema |
| **Docs** | Swagger UI, ReDoc | No built-in docs (need comments) | GraphiQL, Apollo Studio |
| **Validation** | Via schema, but runtime validation needed (e.g. @Valid) | Via proto types, automatic | Via schema, automatic |
| **Type Safety** | Partial (need codegen for full) | Yes (generated code typed) | Yes (generated types) |
| **Best For** | Public REST APIs | Internal high perf microservices | Flexible frontend BFF |

---

This expanded file now covers 20 API types including modern tRPC, Connect, WebTransport, MQTT, RSocket, Falcor, OData, plus production patterns for rate limiting, caching, versioning, transcoding.
