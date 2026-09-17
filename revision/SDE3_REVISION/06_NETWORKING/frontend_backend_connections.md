# Frontend ↔ Backend Connections

## 1. REST HTTP (Most Common)
```
Browser --HTTP--> Nginx/ALB --HTTP--> Backend (Node/Java) --> DB
```
- Request-Response, stateless
- Methods: GET, POST, etc
- Frontend: fetch/axios

```js
// Frontend
const res = await fetch('/api/users', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer '+token },
  body: JSON.stringify({name: 'John'})
})
```

## 2. WebSocket (Bi-directional Real-time)
- Persistent TCP connection after HTTP upgrade
- Full duplex
- Use: Chat, live notifications, collaborative editing, gaming
- Port 80/443, protocol ws:// wss://

Flow:
1. Client sends HTTP with Upgrade: websocket
2. Server 101 Switching Protocols
3. Persistent connection, frames

```js
// Frontend
const ws = new WebSocket('wss://api.example.com/ws');
ws.onmessage = (e) => console.log(e.data);
ws.send(JSON.stringify({type: 'chat', msg: 'hi'}));

// Backend Node.js
const wss = new WebSocketServer({port: 8080});
wss.on('connection', ws => {
  ws.on('message', data => wss.clients.forEach(c => c.send(data)));
});
```

## 3. Server-Sent Events (SSE) - One-way Server->Client
- Text/event-stream
- Auto reconnect
- Use: Live feed, stock prices, notifications where client doesn't need to send often
- Simpler than WebSocket, HTTP based

```js
// Frontend
const es = new EventSource('/api/stream');
es.onmessage = e => console.log(e.data);

// Backend
res.writeHead(200, {'Content-Type': 'text/event-stream'});
setInterval(()=> res.write(`data: ${JSON.stringify({time: Date.now()})}\n\n`), 1000);
```

## 4. Long Polling
- Client requests, server holds until data, then responds, client immediately re-requests
- Old technique, inefficient but works everywhere
- Use when WebSocket not allowed

## 5. gRPC-Web
- Browser can't do gRPC native, needs Envoy proxy to translate gRPC-Web to gRPC
- Use for internal microservices exposed to frontend via BFF

## 6. GraphQL over HTTP
- Single endpoint POST /graphql with query body
- Frontend flexible

## Connection Comparison

| Method | Direction | Persistent? | Overhead | Use Case |
|--------|-----------|-------------|----------|----------|
| REST | Client->Server req/res | No (keep-alive short) | Medium | CRUD |
| WebSocket | Bi-di | Yes | Low after handshake | Chat, game |
| SSE | Server->Client | Yes | Low | Live updates |
| Long Poll | Client->Server | No | High | Legacy live |
| gRPC | Bi-di streaming | Yes HTTP/2 | Very low | Microservices |

## Frontend to Backend Architecture (Production)

```
User
 |
CDN (CloudFront) -> Static React/Vue (S3)
 |
API Gateway / ALB (WAF, Rate Limit)
 |
Nginx Reverse Proxy (SSL termination, load balancer)
 |
Backend Cluster (Node.js PM2 / Java Spring Boot / K8s pods)
 |
Cache (Redis) / DB (Postgres) / Queue (Kafka)
```

### Reverse Proxy vs Forward Proxy
- **Forward Proxy**: Client side, hides client (e.g. corporate proxy to internet)
- **Reverse Proxy**: Server side, hides server (Nginx in front of backend, load balancing, SSL)

### Nginx Config Snippet
```nginx
upstream backend {
  server backend1:3000;
  server backend2:3000;
}

server {
  listen 443 ssl;
  ssl_certificate /etc/ssl/cert.pem;
  location /api/ {
    proxy_pass http://backend;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
  }
  location / {
    root /var/www/frontend;
    try_files $uri /index.html;
  }
}
```

### CORS Handling
Backend must allow frontend origin:
```js
// Node Express
app.use(cors({
  origin: ['https://app.example.com'],
  credentials: true
}));
```

### How to Keep Connection Efficient?
- HTTP/2 multiplexing
- Keep-Alive
- Connection pooling (DB, HTTP agent)
- CDN for static
- Compression gzip/br
- Caching ETag

## Interview Q: How does React call backend?
- Axios interceptors add JWT
- Proxy in package.json for dev: `"proxy": "http://localhost:5000"`
- In prod, Nginx serves both frontend and proxies /api to backend same origin avoids CORS.
