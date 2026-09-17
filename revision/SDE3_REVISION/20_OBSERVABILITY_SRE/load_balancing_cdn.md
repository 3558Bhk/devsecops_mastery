# Load Balancing, Proxy, CDN - Deep

## Load Balancer

### What?
- Distributes traffic across multiple servers, no single point overload, HA

### Where?
- Client -> Global LB (DNS, Anycast) -> Regional LB (ALB/NLB) -> Service LB (Nginx) -> App servers

### Layer 4 vs Layer 7

| L4 (Transport) | L7 (Application) |
|----------------|------------------|
| TCP/UDP, IP+Port, no payload inspection | HTTP, URL, headers, cookies |
| Fast, simple, no TLS termination (can passthrough) | Smart routing (path/host), TLS termination, WAF, sticky sessions |
| Example: NLB, LVS, HAProxy L4 | Example: ALB, Nginx, HAProxy L7 |
| Use: High perf, non-HTTP, TCP | Use: HTTP apps, microservices |

### Algorithms

1. **Round Robin**: Sequential, simple, assumes equal capacity
2. **Weighted Round Robin**: More weight = more traffic, for different capacity servers
3. **Least Connections**: Send to server with fewest active connections, good for long-lived connections
4. **Least Response Time**: Send to fastest response + fewest connections
5. **IP Hash**: Hash client IP to server, sticky, but uneven if many clients from same NAT
6. **Consistent Hashing**: Minimal rehash when node added/removed, good for cache (same key to same server), used in Dynamo, Cassandra, CDN
7. **Random / Weighted Random**: Simple
8. **Geographic**: Route to nearest region (Route53 latency routing)

### Features

- **Health Checks**: LB periodically checks /health, removes unhealthy, adds back when healthy
- **Sticky Sessions (Session Affinity)**: Same client to same server via cookie or IP hash, needed if session stored in server memory (bad practice, better use Redis for stateless), but can be used for cache locality
- **SSL Termination**: LB handles TLS, backend plain HTTP, reduces backend CPU, cert management at LB
- **Cross-Zone**: Distribute across AZs
- **Connection Draining**: On deregister, wait for ongoing requests to complete before removing server (e.g. 300 sec)
- **Auto Scaling Integration**: ASG adds/removes servers to LB target group automatically

### Implementations

- **Hardware**: F5 BIG-IP, Citrix NetScaler - expensive, high perf, used in enterprise
- **Software**: Nginx, HAProxy, Envoy (modern, used in service mesh), LVS (Linux Virtual Server)
- **Cloud Managed**: AWS ALB/NLB/GWLB, GCP Cloud Load Balancing, Azure LB

### Nginx as LB

```nginx
upstream backend {
  least_conn;
  server backend1.example.com:8080 max_fails=3 fail_timeout=30s;
  server backend2.example.com:8080 weight=2;
  server backend3.example.com:8080 backup; # only when others down
}

server {
  listen 80;
  location / {
    proxy_pass http://backend;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_connect_timeout 5s;
    proxy_read_timeout 60s;
    # health check via nginx plus or open source via module
  }
}
```

### AWS ALB vs NLB vs CLB vs GWLB

| Feature | ALB (L7) | NLB (L4) | CLB (Legacy L4/L7) | GWLB |
|---------|----------|----------|--------------------|------|
| Protocol | HTTP/HTTPS, gRPC | TCP/UDP/TLS | HTTP/HTTPS/TCP | IP |
| Routing | Path/host/header | - | - | - |
| Target | IP, instance, Lambda, ALB | IP, instance, ALB | Instance | IP, instance |
| Use | Web apps, microservices | High perf TCP, gaming, IoT | Old | Firewall insertion |
| Features | WAF, OIDC, Lambda, weighted | Static IP, zonal, TLS passthrough | - | - |

### Global Server Load Balancing (GSLB)

- DNS based: Route53 routing policies:
  - Simple, Weighted, Latency (lowest latency region), Failover (active-passive), Geolocation (by user location), Geoproximity (bias), Multivalue
- Anycast: Same IP advertised from multiple regions via BGP, network routes to nearest, used by Cloudflare, Google DNS 8.8.8.8

## Reverse Proxy vs Forward Proxy vs Transparent Proxy

| Type | Position | Hides | Use |
|------|----------|-------|-----|
| **Forward Proxy** | Client side, client configures proxy, client -> proxy -> internet | Hides client from server | Corporate proxy to internet, bypass geo, caching |
| **Reverse Proxy** | Server side, client doesn't know, client -> reverse proxy -> servers | Hides servers from client | Load balancing, SSL termination, caching, WAF, e.g. Nginx in front of Node |
| **Transparent** | Intercept without config, ISP level | - | Caching, filtering |

## CDN - Content Delivery Network

### What?
- Distributed edge servers cache static content close to user, reduces latency, origin load, bandwidth cost, DDoS protection

### How Works?
1. User requests `https://cdn.example.com/image.jpg`
2. DNS resolves to nearest edge PoP (Point of Presence) via Anycast/latency routing
3. Edge checks cache: If hit returns, if miss fetches from origin (S3/ALB), caches, returns, next user from same edge gets cached
4. TTL controls cache duration

### What to Cache?
- Static: Images, CSS, JS, videos, fonts - long TTL (1 year with versioned filename `app.v123.js`)
- Dynamic: Can cache API responses short TTL (1 min) or via cache-control, but careful
- Not cache: Personalized, private, POST

### CDN Features

- **Pull vs Push**: Pull (CDN fetches from origin on miss, common), Push (you upload to CDN, less common)
- **Invalidation**: Purge cache when origin updated, e.g. `/*` or `/images/*`, takes 5-15 min, costly, better use versioned filenames
- **Cache Control Headers**:
```
Cache-Control: public, max-age=31536000, immutable // 1 year for versioned static
Cache-Control: private, no-store // don't cache
ETag: "abc123" // for validation
```
- **Origin Shield**: Extra layer between edges and origin to reduce origin load (only shield fetches from origin, edges fetch from shield)
- **Dynamic Acceleration**: TCP optimization, keep-alive, route optimization for dynamic content not cacheable
- **WAF & DDoS**: CDN like Cloudflare, AWS Shield + CloudFront provide protection
- **Image Optimization**: Resize, WebP conversion on fly

### Providers
- Cloudflare (large, free tier, WAF, DDoS), Akamai (enterprise, largest), AWS CloudFront, Fastly (fast purge, edge compute), GCP Cloud CDN, Azure CDN

### CloudFront Example

```
S3 bucket (origin) -> OAC (Origin Access Control) -> CloudFront Distribution -> Edge Locations -> User
ALB (origin) -> CloudFront -> User
Behaviors: /api/* -> ALB origin no cache, /static/* -> S3 origin cache 1 year
```

### Performance Benefits

- Latency: 200ms to origin -> 20ms to edge (10x)
- Origin offload: 90% requests served from edge, origin handles 10%
- Bandwidth cost: CDN bandwidth cheaper than origin

## Service Mesh LB

- In microservices, service-to-service LB via sidecar Envoy
- Client-side LB: Client has list of servers (from service discovery) and chooses (e.g. gRPC client-side LB)
- Server-side LB: Dedicated LB (ALB)
- Service mesh: Sidecar does LB, retries, mTLS

## Interview Q

**Q: How to achieve sticky sessions without breaking stateless?**
- Better to make stateless with Redis for session, but if must sticky: Use cookie-based affinity (ALB stickiness cookie), or IP hash, but mention downsides (uneven load, scaling issues, server failure loses session). Recommend stateless.

**Q: Consistent hashing?**
- Normal hashing: hash(key) % N, when N changes (add/remove node) most keys remap -> cache miss storm. Consistent hashing: Hash both nodes and keys onto ring (0-2^32), key assigned to next node clockwise, when node added/removed only K/N keys remap (K keys, N nodes). Use virtual nodes to balance uneven distribution.

**Q: How CDN handles dynamic content?**
- Short TTL or no cache, but still accelerates via TCP optimization, keep-alive to origin, route optimization, Anycast. Use dynamic acceleration feature. Or cache at edge with small TTL + stale-while-revalidate.

**Q: Difference between load balancer and API Gateway?**
- LB: Distributes traffic, L4/L7, simple
- API Gateway: LB + advanced: Auth, rate limiting, request transformation, aggregation, versioning, monetization, developer portal, e.g. Kong, AWS API Gateway, Apigee. API Gateway often sits in front of LB or includes LB functionality.
