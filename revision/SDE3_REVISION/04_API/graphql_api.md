# GraphQL - Revision

## What?
- Query language for API, runtime to execute queries
- Developed by Facebook 2012, open source 2015
- Single endpoint: `/graphql`
- Client asks exactly what it needs

## Core Concepts
- **Schema**: Type definitions (SDL)
- **Query**: Read (GET equivalent)
- **Mutation**: Write (POST/PUT/DELETE)
- **Subscription**: Real-time via WebSocket
- **Resolver**: Function that returns data for field
- **Type System**: Strongly typed

## Example Schema
```graphql
type User {
  id: ID!
  name: String!
  email: String!
  posts: [Post!]!
}

type Post {
  id: ID!
  title: String!
  author: User!
}

type Query {
  user(id: ID!): User
  users(limit: Int, offset: Int): [User!]!
}

type Mutation {
  createUser(name: String!, email: String!): User!
}

type Subscription {
  userCreated: User!
}
```

## Example Queries
```graphql
# Query - get only needed fields (solves over-fetching)
query {
  user(id: "123") {
    name
    email
    posts {
      title
    }
  }
}

# Mutation
mutation {
  createUser(name: "John", email: "john@example.com") {
    id
    name
  }
}

# Variables
query GetUser($id: ID!) {
  user(id: $id) {
    name
  }
}
# variables JSON: { "id": "123" }

# Subscription
subscription {
  userCreated {
    id
    name
  }
}
```

## Advantages
- No over-fetching / under-fetching
- Single request for multiple resources (avoid REST N+1)
- Strong typing + introspection
- Real-time via subscriptions
- Versionless (add fields, deprecate)

## Disadvantages / Challenges
- Caching harder (single endpoint, POST)
- File uploads complex (need multipart)
- N+1 problem - need DataLoader
- Rate limiting complex (query complexity analysis)
- Overkill for simple CRUD

## Caching
- Use persisted queries
- Apollo Client cache
- Server side: DataLoader batching

## Security
- Query depth limiting
- Complexity limiting
- Disable introspection in prod (optional)
- Auth in context

## When Use?
- Frontend needs flexible data (mobile + web different needs)
- Microservices aggregation (GraphQL gateway / federation)
- Real-time apps

## Federation (SDE3 Level)
- Apollo Federation: multiple GraphQL services compose into one supergraph
- Each microservice owns its types

## Tools
- Apollo Server/Client, Relay, GraphiQL, Postman

## Interview Q: REST vs GraphQL?
REST multiple endpoints, over-fetching. GraphQL single endpoint, client-driven. GraphQL good for complex nested frontend needs, REST better for caching, simple APIs, public APIs.
