# 17 · Networking & Service Mesh

The topic where interviewers separate "has read about it" from "has debugged it at 3am". Expect **L2–L7 fundamentals, DNS, TLS, load balancing, Kubernetes networking, service mesh trade-offs, and eBPF**.

*(Cross-references: L4/L7 and TCP fundamentals in [`01-CS-Fundamentals`](../01-CS-Fundamentals/README.md); cloud networking in [`12-Cloud-AWS`](../12-Cloud-AWS/README.md#5-vpc--subnets-routing-and-the-pieces-people-get-wrong) and [`13-Cloud-Multi-Azure-GCP`](../13-Cloud-Multi-Azure-GCP/README.md#2-azure-networking-essentials).)*

---

## 🟢 Basic

### 1. The OSI/TCP-IP layers and what lives where — with the tooling
| Layer | What | Devices/protocols | Debug tool |
|---|---|---|---|
| **L1 Physical** | Bits on a medium | Cables, fibre, SFPs, link state | `ethtool`, link LEDs, `dmesg` |
| **L2 Data link** | Frames, MAC addresses, switching | Ethernet, ARP, VLAN (802.1Q), STP, bridges | `ip link`, `bridge`, `tcpdump` (MAC), `arp -a` |
| **L3 Network** | Packets, IP addressing, routing | IP, ICMP, BGP, OSPF, IPsec, VXLAN | `ip route`, `traceroute`/`mtr`, `ping`, `ip -s link` |
| **L4 Transport** | Segments, ports, reliability | **TCP**, **UDP**, **QUIC/SCTP** | `ss -tanp`, `netstat`, `tcpdump` (flags), `conntrack -L` |
| **L5/6 Session/Presentation** | (Mostly collapsed in practice) | TLS, sockets | `openssl s_client`, `ss` |
| **L7 Application** | Requests | HTTP/1.1, HTTP/2, HTTP/3, gRPC, DNS, SMTP, WebSocket | `curl -v`, `openssl`, `tcpdump` + HTTP decode, mesh telemetry |

**Why the layering matters in interviews:** every symptom maps to a layer, and **identifying the layer is 80% of the diagnosis.**
- Can't ping but DNS resolves → L3 (routing/firewall/ICMP blocked).
- Ping works, TCP connect fails → L4 (port closed, security group, conntrack full).
- TCP connects, TLS fails → certificate/chain/SNI/protocol mismatch.
- TLS works, HTTP 502 → L7 (backend not responding correctly, proxy misconfig).
- Small requests work, large hang → **MTU/fragmentation** (L3).
- Works from one subnet, not another → routing or policy.

**The MTU/PMTUD blackhole — memorise this one:** if ICMP "fragmentation needed" (type 3 code 4) is blocked, Path MTU Discovery fails → large packets are silently dropped → **TCP handshakes succeed, small requests work, large responses hang**. Classic causes: VPN/overlay encapsulation (VXLAN −50 bytes, IPsec, GRE), cloud LB paths, misconfigured CNI MTU. Diagnose with `ping -M do -s 1472 <host>` (decreasing the size until it works tells you the path MTU), or `tcpdump` showing retransmissions of large segments with no response, or `tracepath`. Fix: lower the MTU on the overlay interface, enable MSS clamping (`iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu`), or unblock ICMP type 3 code 4.

### 2. TCP — the parts that matter operationally
**Handshake:** SYN → SYN-ACK → ACK (1 RTT). **Teardown:** FIN → ACK → FIN → ACK, with **TIME_WAIT** (2×MSL, typically 60s) on the side that sent the first FIN.

**TIME_WAIT — the classic interview topic:**
- **What it is:** a normal, necessary state. It ensures (a) delayed packets from the old connection aren't mistaken for a new one with the same 4-tuple, and (b) the final ACK is retransmittable if lost.
- **Why it hurts:** a high-churn client (a proxy opening many short connections to one backend) accumulates tens of thousands of TIME_WAIT sockets, **exhausting ephemeral ports** (`net.ipv4.ip_local_port_range`, typically ~28k ports) → `EADDRNOTAVAIL` / `cannot assign requested address`.
- **Correct fixes:** use **connection pooling / keep-alive** (fewer connections, the real fix), increase the ephemeral port range, add more client source IPs, **reuse connections via HTTP/2 multiplexing**.
- **Wrong/dangerous fixes:** `tcp_tw_recycle` (**removed in Linux 4.12 — it broke NAT badly**), and `tcp_tw_reuse` (only helps outbound connections with timestamps enabled; a band-aid). **Knowing that `tcp_tw_recycle` was removed and why is a credibility marker.**

**Flow and congestion control:**
- **Flow control** = receiver tells the sender its window (`rwnd`) — prevents overrunning the receiver.
- **Congestion control** = the sender infers network capacity (`cwnd`) — prevents overrunning the network. Algorithms: **Reno/CUBIC** (loss-based, the Linux default), **BBR** (model-based: estimates bottleneck bandwidth and RTT; much better on lossy/high-BDP links), **Vegas/DCTCP** (delay-based; DCTCP is used in datacenters with ECN).
- **Slow start:** cwnd begins small (~10 segments, IW10) and doubles per RTT until `ssthresh`. **Consequence: short-lived connections never leave slow start** — which is why TLS session resumption, connection reuse and HTTP/2/3 matter for latency, and why a load balancer that opens a new connection per request performs terribly.
- **Head-of-line blocking:** TCP delivers bytes in order, so one lost packet stalls everything behind it. **This is the fundamental motivation for QUIC/HTTP3**, which multiplexes independent streams over UDP so a loss affects only one stream.
- **Bufferbloat:** oversized buffers → high latency instead of loss. Fixed with AQM (CoDel, PIE, fq_codel).
- **Nagle's algorithm** (`TCP_NODELAY` disables it): coalesces small writes; **harmful for request/response protocols** — a 40 ms stall on small writes is a classic latency bug. Servers should set `TCP_NODELAY`.

**Useful Linux TCP knobs:** `somaxconn` (accept queue length — **raising it past 128 without raising the app's backlog does nothing**), `tcp_max_syn_backlog`, `tcp_fin_timeout`, `ip_local_port_range`, `tcp_keepalive_time` (default **7200s = 2 hours** — far too long to detect a dead peer; most apps set their own keepalive or a shorter sysctl), `tcp_slow_start_after_idle` (disabling helps long-lived pooled connections), `net.core.rmem_max`/`wmem_max`, and `tcp_tw_reuse`.

**Connection queues (a frequent deep-dive):**
- **SYN queue** (half-open): overflow → dropped SYNs (`tcp_syncookies` mitigates, and protects against SYN floods).
- **Accept queue** (completed, awaiting `accept()`): overflow → the kernel either drops the ACK (client retransmits, connection delayed) or RSTs (client sees `connection reset`). Symptom: **intermittent connection resets/timeouts under load with a healthy app**. Diagnose: `netstat -s | grep -i -E 'listen|overflow'` (`times the listen queue of a socket overflowed`, `SYNs to LISTEN sockets dropped`), or `ss -lnt` showing `Recv-Q` at `Send-Q` (the queue is full). **Fix: raise `somaxconn` AND the application's listen backlog** (both are required), and make the app accept faster.

### 3. DNS — resolution, records, TTLs, and failure modes
**Resolution path:** stub resolver (`/etc/resolv.conf`) → recursive resolver → root servers (`.`) → TLD (`.com`) → authoritative nameserver → answer, cached at each level per TTL.

**Record types:** `A`/`AAAA` (address), `CNAME` (alias — **cannot coexist with other records at the same name, and cannot be used at the zone apex**), `NS`, `SOA` (zone metadata incl. the negative-cache TTL), `MX`, `TXT` (SPF/DKIM/DMARC/domain verification), `SRV` (service:port discovery), `PTR` (reverse), `CAA` (which CAs may issue for the domain — **an underused security control**), `TLSA` (DANE), `SSHFP`, and **alias-ish records** (Route 53 `ALIAS`, Cloudflare `CNAME` flattening) that solve the apex problem.

**The Kubernetes `ndots:5` problem** (see [`07-Kubernetes`](../07-Kubernetes/README.md#14-dns-in-kubernetes--coredns-ndots-and-the-latency-trap)): external names with < 5 dots get expanded through every search domain first → **4–5× DNS amplification**. Fix: trailing dots, `ndots:2`, or NodeLocal DNSCache.

**Failure modes worth knowing cold:**
- **The 5-second DNS timeout**: glibc's resolver retries after 5s; with UDP conntrack insert races (parallel A + AAAA queries) packets get dropped → **exactly 5s (or 10s) stalls**. Fix: **NodeLocal DNSCache**, `single-request-reopen`, or disabling AAAA lookups. **Recognising the "exactly 5 seconds" signature is a strong signal.**
- **TTL ignored/cached too long**: resolvers and JVMs cache beyond the TTL (Java's `networkaddress.cache.ttl` defaults to forever in some configurations → **a DNS failover that never happens**). Set explicit TTLs in the JVM and in the client library.
- **Negative caching**: an NXDOMAIN is cached for the SOA minimum → a transient record deletion causes a longer outage than expected.
- **Resolver as a SPOF**: CoreDNS with 1 replica, or a single upstream. Scale it, anti-affinity it, monitor it.
- **DNS-based failover latency**: health-check interval + evaluation threshold + TTL + client caching = **minutes, not seconds**. Plan for it.
- **DNSSEC** (signed zones, validates authenticity — deployment is partial and it doesn't encrypt) vs **DoT/DoH** (encrypts the resolver path — privacy, and it can bypass corporate DNS policy, which is a security-team concern).
- **Split-horizon DNS** (different answers inside vs outside) — powerful and a debugging trap: "it resolves to the wrong IP" is often correct behaviour for the wrong vantage point.

### 4. TLS — handshake, certificates, and the failure modes
**TLS 1.3 handshake (1-RTT, 0-RTT on resumption):**
```
Client → Server: ClientHello (supported versions, cipher suites, key_share, SNI, ALPN, session ticket)
Server → Client: ServerHello + key_share + Certificate + CertificateVerify + Finished
Client: verifies the chain, sends Finished → application data
```
vs **TLS 1.2** (2-RTT: ClientHello/ServerHello+Cert/ServerHelloDone, then key exchange, then Finished). **TLS 1.3 removed** static RSA key exchange (so **forward secrecy is mandatory**), RC4/3DES/CBC-mode problems, compression (CRIME), and renegotiation weaknesses. **0-RTT resumption has a replay risk** — don't send non-idempotent data in it.

**Certificate chain validation:** the client builds a path from the leaf to a trusted root, checking **signature validity, expiration, hostname match (SAN — CN is deprecated for this), key usage/extended key usage, revocation (CRL/OCSP/OCSP stapling), and basic-constraints/chain length**.

**The failure modes (this is what gets asked):**
| Symptom | Cause |
|---|---|
| `certificate has expired` | Leaf or **intermediate** expired. **Monitor every cert in the chain, not just the leaf** |
| `unable to get local issuer certificate` / `self signed certificate in certificate chain` | **Incomplete chain served** — the server must send intermediates; many clients can't fetch them (and some do, which is why it "works in the browser, fails in curl/Java") |
| Hostname mismatch | Wrong SAN, or connecting by IP when the cert has only a DNS name |
| `certificate revoked` | CRL/OCSP; **OCSP stapling** avoids the client making a third-party call (and avoids the privacy/latency problem) |
| Handshake fails with old clients | TLS 1.0/1.1 disabled, or a modern-only cipher suite / ECDSA-only cert |
| **Java-specific failures** | A missing intermediate in a truststore, an outdated cacerts, or the JVM caching DNS forever after a failover |
| Random handshake failures under load | Session cache exhaustion, or a rate-limited ACME/CA API during renewal |
| Works then breaks after ~30 days | **Automated renewal not configured** (cert-manager, ACME) |

**mTLS:** both peers present certificates and validate each other → **mutual authentication and an encrypted channel without network-level trust**. The foundation of service-mesh security and zero-trust service-to-service auth. Operational requirements: a CA, automated issuance and rotation (**cert-manager + a short-lived policy**, or **SPIFFE/SPIRE** issuing X.509 SVIDs), and revocation strategy (short-lived certs make revocation mostly unnecessary — **rotation instead of revocation is the modern design**).

**SNI vs ALPN:** **SNI** = which certificate to serve (hostname in the ClientHello, plaintext unless ECH/ESNI); **ALPN** = which application protocol (h2, http/1.1) — negotiated in the handshake, which is how HTTP/2 avoids an extra round trip. **A load balancer that terminates TLS must handle SNI to serve multiple certs on one IP.**

**Certificate lifecycle automation (the answer to "how do you manage certs?"):** ACME (Let's Encrypt/ZeroSSL) or an internal CA → **cert-manager** in Kubernetes (with `ClusterIssuer`, DNS-01 or HTTP-01 challenges, automatic renewal at 2/3 of the lifetime) → **monitoring on expiry for every cert including internal ones and intermediates** → short-lived certs for workloads (SPIRE) → and a **runbook for "the CA is down"**, because automated renewal without a fallback becomes a mass expiry event.

### 5. Load balancing — algorithms, health checks, and L4 vs L7
**Algorithms:**
| Algorithm | Behaviour | Best for |
|---|---|---|
| **Round robin** | Cycle | Homogeneous backends, similar request cost |
| **Weighted RR** | Cycle with weights | Heterogeneous capacity (bigger instances get more) |
| **Least connections** | Send to the fewest active | **Long-lived or variable-cost requests** — the usual best default |
| **Weighted least connections** | Least conns normalised by weight | Mixed capacity |
| **Least response time** | Fastest recent response | Latency-sensitive, heterogeneous backends |
| **Consistent hashing** | Hash a key (IP, URL, header, cookie) → a stable backend | **Session affinity, cache locality, sharded workloads**. Bounded disruption on membership change with virtual nodes |
| **Random / power of two choices** | Pick 2 at random, take the less loaded | Simple, near-optimal, no shared state — **used by nginx and Envoy** |
| **IP hash** | Hash the source IP | Crude affinity; **breaks behind NAT** (thousands of users share one IP) |

**L4 vs L7 (be precise):**
- **L4 (TCP/UDP):** the LB sees the 5-tuple only. It forwards bytes; it can't route on path/host/header, can't do per-request retries, and can't terminate HTTP semantics. **Fast, protocol-agnostic** (works for any TCP protocol), **preserves the client IP** (with DSR or proxy protocol), lower overhead. Examples: NLB, LVS, HAProxy in TCP mode, IPVS, kube-proxy.
- **L7 (HTTP/gRPC):** terminates the connection, parses the protocol → host/path/header/cookie routing, **per-request** load balancing and retries, compression, caching, TLS termination with SNI, WAF, auth, rate limiting, request/response transformation, observability per route. Costs: more CPU, and **the client IP is lost unless you use `X-Forwarded-For` / Proxy Protocol**. Examples: ALB, nginx, Envoy, HAProxy in HTTP mode, Traefik, API gateways.
- **The double-hop reality:** most architectures are **L4 in front (fast, static IP, DDoS-resistant) → L7 behind (routing, policy)**, and each hop must correctly propagate client IP and health.
- **Health checks**: L4 (TCP connect) vs L7 (HTTP GET expecting 2xx/3xx on a real endpoint). **A TCP health check passes on a wedged app**; an L7 check that hits a dependency can trigger a **cascade** (see [`07-Kubernetes`](../07-Kubernetes/README.md#3-probes--the-three-types-and-how-to-configure-them-correctly)). Tune interval/threshold/unhealthy-threshold deliberately: too aggressive → flapping; too slow → sending traffic to dead backends.
- **Connection draining / deregistration delay**: on removal, stop new requests but let in-flight finish. **Mismatched drain timeouts between the LB and the app's grace period are a top cause of 502s during deploys.**
- **Session persistence**: cookie-based (L7), source-IP (L4, breaks with NAT), or **make the app stateless** (the right answer).
- **Slow start / warm-up**: gradually increase traffic to a newly added backend so a cold JVM/container isn't crushed instantly.

---

## 🔵 Advanced

### 6. Kubernetes networking — the full request path
**The CNI contract:** every pod gets a unique IP; **pods can reach each other across nodes without NAT**; nodes can reach pods; a pod sees its own IP as others see it.

**The path for `curl http://api.prod.svc.cluster.local` from a pod:**
1. **DNS**: CoreDNS resolves the name → a **ClusterIP** (virtual, exists nowhere as an interface).
2. **Local routing**: the pod's route table sends ClusterIP traffic to the default gateway (the node).
3. **kube-proxy / eBPF DNAT**: an iptables/IPVS/eBPF rule matches the ClusterIP:port and **rewrites the destination to a pod IP:port** chosen from the EndpointSlice (random for iptables; per-algorithm for IPVS; eBPF does it in-kernel with O(1) lookup).
4. **Conntrack** records the NAT mapping so return traffic is de-translated.
5. **CNI datapath to the target pod:**
   - **Same node**: through the bridge or a direct veth route.
   - **Different node, overlay (VXLAN/IPIP)**: the pod packet is encapsulated in a node-to-node UDP/IP packet → sent over the physical network → decapsulated on the destination node → delivered to the target pod's veth.
   - **Different node, native routing (BGP/VPC-CNI)**: the pod IP is routable on the underlay; no encapsulation, no MTU loss.
   - **eBPF (Cilium)**: replaces iptables and optionally the overlay with BPF programs; can do service resolution without conntrack.
6. **NetworkPolicy** is enforced by the CNI (if it implements it) at the pod's interface.

**Ingress from outside:**
```
Client → DNS → Cloud LB (L4) → Ingress/Gateway controller pod (L7: TLS termination, host/path routing)
      → Service (ClusterIP, DNAT) → Pod
```
Or with a cloud-native LB controller: `LB → pod IPs directly` (target-type `ip`, bypassing NodePort and the extra hop — better performance and correct client IPs).

**The problems this creates (and the answers):**
- **Extra hops = extra latency and extra places to fail.** Each hop (LB → ingress → kube-proxy → pod) adds a small amount of latency and a large amount of debugging surface. **Cilium/eBPF and direct pod targeting exist to remove hops.**
- **kube-proxy load-balances per connection, not per request.** With HTTP keep-alive or gRPC (a single long-lived HTTP/2 connection multiplexing all RPCs), **one client pins to one backend pod indefinitely** → severe load imbalance. **This is the single most-cited reason teams adopt a service mesh or L7-aware proxying.** Fixes: shorter idle timeouts, `max_connection_duration` on the server, L7 LB (mesh/ingress), or client-side load balancing with per-request selection (gRPC's `round_robin` with DNS/headless service returning all pod IPs).
- **Conntrack table exhaustion**: high connection churn fills `nf_conntrack_max` → `nf_conntrack: table full, dropping packet` → intermittent failures that are miserable to diagnose. Monitor `node_nf_conntrack_entries` / `..._limit`; raise the limit, reduce churn (keep-alive), or use an eBPF datapath.
- **Endpoint propagation lag** → 502s during rollouts (see [`07-Kubernetes`](../07-Kubernetes/README.md#13-why-do-we-get-502504s-during-rolling-deploys-the-most-common-senior-question)).
- **IP exhaustion** with VPC CNI (one VPC IP per pod) → plan CIDRs, use secondary CIDRs, custom pod CIDRs, or an overlay/eBPF datapath.

### 7. Service mesh — what it is, what it costs, and when to say no
**Definition:** a dedicated **infrastructure layer** for service-to-service communication, implemented as a **sidecar proxy** (or an ambient/per-node proxy) that handles traffic management, security and observability **outside the application**.

**What you get:**
| Capability | Without a mesh | With a mesh |
|---|---|---|
| mTLS between services | Each team implements it (or nobody does) | **Automatic**, with identity (SPIFFE) and rotation |
| Retries/timeouts | Per-client library, inconsistent | Declarative, uniform, per-route |
| Circuit breaking / outlier detection | Hand-rolled | Built in |
| Traffic splitting (canary, A/B, mirroring) | Ingress annotations + custom code | First-class, with analysis integration |
| Observability | Per-app metrics, inconsistent labels | **Uniform L7 metrics, distributed traces, and a service graph for every service, automatically** |
| Access policy (which service may call which) | NetworkPolicy (L3/L4 only) | **L7 authorisation** (method/path-aware, identity-based) |
| Service discovery | DNS/Service | Registry with health and endpoints |

**What it costs (be specific — this is where the answer earns credibility):**
- **Latency and resource overhead**: two extra proxies per request (client-side + server-side). Realistically **~0.5–2 ms p50 added** (more for small payloads, TLS handshake on new connections) and **~50–100 MB RAM + a fraction of a CPU per sidecar**. At 500 pods that's 25–50 GB of RAM spent on the mesh. **Istio's ambient mode and Cilium's sidecar-free approach exist precisely to reduce this.**
- **Operational complexity**: a control plane (istiod, or a mesh CA + config distribution) that is itself a critical, high-availability system requiring upgrades, monitoring and expertise. **Data plane/control plane version skew** is a real compatibility matrix.
- **Debugging surface grows**: "why did this request fail?" now involves the app, two Envoy proxies, mesh policy, and the control plane. Envoy config dumps (`istioctl proxy-config`) are powerful and terrible.
- **Compatibility issues**: HTTP/1.1 protocol upgrades (websockets), gRPC keepalives, `Host` header handling, MTU, connection draining, and apps that don't behave (long-lived connections, custom protocols).
- **Init ordering / traffic capture**: iptables redirection means **outbound traffic is captured before the app is ready** — hence `holdApplicationUntilProxyStarts` and the classic "app starts before the sidecar and fails" bug.

**Alternatives and their positioning:**
| Approach | Model | Notes |
|---|---|---|
| **Istio** | Sidecar (Envoy) + istiod; **ambient mode** (ztunnel per node for L4 mTLS + optional waypoint proxies for L7) | The most feature-complete; the most complex. Ambient mode is the answer to sidecar overhead |
| **Linkerd** | Sidecar (a Rust micro-proxy, `linkerd2-proxy`) | **Radically simpler to operate**, lower resource use, fewer features. The pragmatic default for many teams |
| **Cilium Service Mesh** | **eBPF-based, sidecar-less** (L3/L4 in-kernel) + optional Envoy for L7 | Best performance, integrates with the CNI, no per-pod proxy for the L4 case |
| **Consul Connect** | Sidecar + service discovery + multi-datacenter | Good for hybrid/non-Kubernetes |
| **AWS App Mesh / GCP Anthos Service Mesh / Azure** | Managed Istio variants | Managed control planes; **AWS App Mesh has moved toward deprecation** in favour of ECS Service Connect / VPC Lattice |
| **No mesh** | Library-based (a shared client library with retries/timeouts/tracing) or **Gateway API + Ingress** only | **Perfectly valid**, and the right choice below ~20–30 services |

**The honest answer to "should we adopt a service mesh?":**
> "I'd adopt one when I have a specific problem it solves better than the alternatives, and the platform team to run it. The three problems that justify it: **(1) mTLS everywhere with workload identity** — if you need zero-trust service-to-service auth across many teams, doing it in libraries means N implementations; **(2) uniform L7 observability** across services you don't control; **(3) progressive delivery** (traffic splitting, mirroring, canary analysis) as infrastructure rather than per-app code.
> Below ~20 services, or with a small team, I'd use **Gateway API/Ingress for north-south**, a **shared client library** or the language's native HTTP/2 client for retries and timeouts, **NetworkPolicy** for L3/L4 segmentation, **cert-manager + SPIRE** if I need workload identity, and **OpenTelemetry** for tracing. That gets 80% of the value at 10% of the operational cost.
> And the question I'd ask first is: **do we have a team that will own the mesh?** A mesh without an owner becomes a mystery layer that everyone blames and nobody understands — the worst possible outcome, because it adds failure modes to every request while removing the ability to diagnose them."

### 8. eBPF — why it changed cloud networking and observability
**What it is:** a mechanism to run **sandboxed, verified programs inside the Linux kernel**, attached to hooks (XDP at the NIC driver, tc at the traffic-control layer, kprobes/uprobes on functions, tracepoints, cgroup hooks, LSM hooks). Programs are written in a restricted C, compiled to BPF bytecode, **verified** by the kernel (no unbounded loops, no unbounded memory, safe pointer access), and JIT-compiled to native instructions.

**Why it matters:**
- **Performance**: **XDP** processes packets *before* the kernel allocates an `sk_buff` → millions of packets/sec per core, which is how Cilium/Katran/Cloudflare build L4 load balancers and DDoS mitigation in software.
- **Replaces iptables**: iptables rule matching is **O(n)** — with 5,000 services, every packet walks a long chain. eBPF **hash-map lookups are O(1)**, and it can skip conntrack for service resolution entirely. **In large Kubernetes clusters, replacing kube-proxy's iptables with eBPF is a measurable latency and CPU win.**
- **Observability without instrumentation**: attach to kernel functions and get syscall-level, process-level and network-level telemetry for **unmodified binaries** — that's how Hubble, Tetragon, Pixie, Parca, bcc/bpftrace, and OTel's eBPF auto-instrumentation work.
- **Security enforcement**: LSM hooks and syscall filtering with more context than seccomp (Tetragon can enforce, not just alert).
- **Programmable networking**: service mesh without sidecars (Cilium), policy enforcement in-kernel, load balancing, NAT, and even socket-level redirection (**sockmap/sockops** — bypassing the network stack entirely for same-node pod-to-pod traffic, a significant latency win).

**The caveats (which make the answer credible):** kernel version dependencies (features arrive across 4.x–6.x; older distros limit you), verifier restrictions and debugging difficulty (BPF programs can't be debugged normally), the CO-RE (`BTF`) requirement for portability, security review (kernel code = kernel attack surface, though the verifier is strong), and the fact that **it's a powerful hammer that makes simple problems look like kernel projects**.

**Tools:** `bcc`/`bpftrace` (ad-hoc: `execsnoop`, `opensnoop`, `tcplife`, `tcpretrans`, `biolatency`, `runqlat`), **Cilium/Hubble** (networking + observability), **Tetragon** (runtime security), **Pixie** (in-cluster observability), **Parca/Pyroscope** (profiling), **Falco** (modern eBPF probe), **OTel eBPF auto-instrumentation**, `bpftop`, `bpftool`.

**The one-liner for interviews:** "eBPF lets you put verified programs into the kernel at well-defined hooks, which turns networking, observability and security from *configuration* problems into *programming* problems — that's why kube-proxy's iptables became Cilium, why sidecars became optional, and why you can now profile and trace unmodified binaries in production at ~1% overhead."

### 9. HTTP/1.1 vs HTTP/2 vs HTTP/3 (QUIC) — and what it changes for infra
| | **HTTP/1.1** | **HTTP/2** | **HTTP/3 (QUIC)** |
|---|---|---|---|
| Transport | TCP | TCP (+TLS 1.2/1.3) | **UDP + QUIC** (TLS 1.3 built in) |
| Multiplexing | ❌ (one request per connection; browsers open 6) | ✅ Many streams over one connection | ✅ Many streams over one connection |
| Head-of-line blocking | Per connection | **TCP-level HOL remains** (one lost packet stalls all streams) | **Solved** — streams are independent |
| Handshake | TCP (1 RTT) + TLS (1–2 RTT) | TCP + TLS 1.3 (1 RTT) | **0–1 RTT** (connection resumption with 0-RTT) |
| Headings | Verbose, repeated | **HPACK** compressed | **QPACK** compressed (avoids HOL on the header stream) |
| Connection migration | ❌ (4-tuple bound) | ❌ | ✅ **Connection ID survives IP changes** (Wi-Fi → cellular without reconnecting) |
| Server push | ❌ | Yes (deprecated in practice — rarely helps, often hurts) | ❌ |
| Middlebox ossification | High | High (TCP is inspected/modified by middleboxes) | **Low** (UDP payload is encrypted; QUIC evolves in userspace) |
| Infra impact | Baseline | **L7 LBs must parse it**; **long-lived connections break per-connection LB** | **Requires UDP support** — many LBs, firewalls and clouds historically dropped/throttled UDP; needs a QUIC-aware proxy |

**The infra consequences (the interesting part):**
- **HTTP/2's long-lived connection defeats per-connection load balancing.** One client = one connection = one backend pod for hours. gRPC over HTTP/2 makes this acute: **a service that scales from 3 to 30 pods sees no traffic shift to the new pods** because existing connections never re-balance. Fixes: client-side LB (gRPC `round_robin` with a headless Service returning all pod IPs, or a proxy doing per-request LB), `max_connection_age` on the server (forces periodic reconnect → rebalancing), a mesh/sidecar doing per-request routing, or L4 LB with a client-side resolver. **This is a very common production problem and a great thing to raise unprompted.**
- **HTTP/3 needs UDP**: firewalls, cloud LBs, security groups and corporate networks must permit UDP/443. Fallback to HTTP/2 via the `Alt-Svc` header is the standard deployment path.
- **Observability changes**: you can no longer read the wire (it's encrypted end to end at the transport), so **proxy-level telemetry (Envoy/mesh access logs) becomes the source of truth**, and `tcpdump` becomes much less useful.
- **Timeouts and retries**: QUIC's faster connection establishment changes the latency profile; but middleboxes dropping UDP causes fallback latency. Measure both paths.

### 10. API gateways vs ingress vs service mesh vs BFF — the layering
```
Client
  │
  ├─ CDN / WAF / DDoS protection          (edge: caching, filtering, absorption)
  ├─ Global load balancer                 (geo-routing, failover)
  ├─ L4 load balancer                     (static IP, TLS passthrough or termination)
  ├─ API Gateway                          (product-level: authN/authZ, rate limits per consumer,
  │                                        API keys, quotas, monetisation, versioning, request
  │                                        transformation, developer portal, OpenAPI)
  ├─ Ingress / Gateway API controller     (Kubernetes-native L7 routing: host/path, TLS termination)
  ├─ Service mesh (sidecar/ambient)       (service-to-service: mTLS, retries, circuit breaking,
  │                                        traffic splitting, L7 telemetry and authz)
  └─ Service → BFF (backend-for-frontend) → internal services
```
**The distinctions:**
- **Ingress/Gateway API** = *routing* into the cluster. Kubernetes-native, no auth/quota/monetisation semantics.
- **API Gateway** = a *product* boundary. Consumer identity, API keys, quotas, rate limits per plan, request/response transformation, versioning, caching, a developer portal, analytics per API product. (Kong, Apigee, AWS API Gateway, Azure APIM, Tyk, Gloo, Envoy Gateway with extensions.)
- **Service mesh** = *internal* service-to-service. Nobody outside the cluster sees it.
- **BFF** = an *application-level* aggregation layer tailored to one client type (mobile/web/partner): composes several services into one response, hides internal schema, handles client-specific concerns.
**Overlap is real**: an Envoy-based gateway and an Envoy-based mesh share technology but different responsibilities. **The anti-pattern is doing everything at one layer** — a mesh enforcing per-customer quotas, or an API gateway doing internal service discovery. **Say: "north-south concerns at the gateway, east-west concerns at the mesh, client-specific composition in a BFF, and routing in the Gateway API."**

---

## 🔴 Scenario

### 11. "Users in one region report the service is slow. Everywhere else is fine. Investigate."
**The regional scoping is the biggest clue — it eliminates application code and points at region-specific infrastructure.**

**Step 1 — Confirm and characterise (2 minutes).**
- **Which users?** All users in that region, or some? Which ISP/carrier/network? (A single ISP → a peering/transit problem, not yours.)
- **What kind of slow?** DNS resolution slow? TLS handshake slow? TTFB slow? Download slow? **Each points to a different layer.**
- **Since when, and what changed?** (Deploy, DNS change, cert rotation, config change, cloud event, traffic spike, a new peering route.)
- **Is the server-side latency also high?** Compare **server-measured latency** (your app/proxy metrics for that region) with **client-measured latency** (RUM/synthetic probes from that region).
  - **Server-side high too** → the problem is inside the region (a dependency, a node, a database, capacity).
  - **Server-side normal, client-side high** → **the problem is between the client and your edge**: DNS, routing, peering, TLS, CDN, MTU, or a middlebox. **This distinction halves the search space and is the single most important first step.**

**Step 2 — Walk the path, in order.**
```
Client → Local DNS → Recursive resolver → Authoritative DNS → Anycast/Geo edge
      → CDN/LB → TLS → Ingress → App → Cache → DB → 3rd party
```
1. **DNS**: is the regional resolver returning a different (worse) record? Geo/latency-based routing may be sending them to a distant edge — **check what IP the regional clients actually resolve to**, and whether a health check flipped a routing policy. Also check for an **NXDOMAIN/negative cache** or a resolver outage. Use `dig +trace` from a regional vantage point (or a looking glass / RUM data).
2. **Routing/peering**: `mtr`/`traceroute` from the region to your edge. Look for a **route change** (a new hop, a different AS path, higher RTT at a specific hop), packet loss at a specific hop (note: **ICMP deprioritisation mid-path is normal and not necessarily loss** — judge by the *end-to-end* loss and by TCP behaviour), or a **satellite/long-hairpin path** (traffic leaving the region and coming back). Cloud provider **transit/peering incidents** and **BGP hijacks/leaks** are real and regional.
3. **CDN/edge**: cache hit ratio dropped (a config change, a purge, a cache-key change → everything goes to origin → origin slow *and* expensive)? A specific PoP degraded? An edge TLS/cert issue? **Check per-PoP metrics, not global aggregates** — a global average hides a bad PoP.
4. **TLS**: a certificate rotation in that region, OCSP stapling failing (clients making slow OCSP calls), a session-resumption regression (full handshakes on every request), or an intermediate missing for a specific client population.
5. **MTU/PMTUD**: an overlay or VPN change in that region → large responses hang (see Q1). **Signature: small requests fine, large payloads time out.**
6. **In-region infrastructure**: a database replica lagging or promoted, an AZ degraded, node pool capacity short (autoscaler can't scale in that region — a **quota** problem is common), a dependency (payment provider, third-party API) with a regional endpoint that's slow, or a regional cloud service incident (**check the cloud status page and the service health dashboard early** — it's embarrassing to debug for an hour what the provider announced 40 minutes ago).
7. **Traffic**: a regional marketing campaign, a crawler, a retry storm from a specific client version, or a regional partner integration.
8. **Config**: a regional feature flag, a regional rate limit, a regional config drift (GitOps out of sync in that cluster).

**Step 3 — Tools and vantage points.** You cannot debug a regional network problem from your office:
- **Synthetic monitoring from that region** (Catchpoint, ThousandEyes, Datadog Synthetics, k6 cloud, Checkly) — DNS/TCP/TLS/TTFB breakdown per step. **This is the single most valuable tool and the one most teams lack.**
- **RUM** (real user monitoring) with per-region/ISP/ASN breakdowns.
- **Looking glasses** and cloud provider network diagnostics (AWS Reachability Analyzer, GCP network intelligence, Azure Network Watcher).
- In-region **debug pods** (`kubectl debug`, a `curl`/`mtr`/`dig` pod in the affected cluster) and **`tcpdump` on the edge** to see whether requests arrive and how long the response takes.
- **Third-party status**: Downdetector, the cloud status page, the CDN status page, BGP monitoring (bgp.he.net, RIPE RIS).

**Step 4 — Mitigate while investigating.** If it's routing/DNS: change the routing policy to a healthier region (accepting added latency), or lower the TTL and steer around the bad PoP. If it's an in-region dependency: fail over to another region's replica, enable a cache/degradation path, or shed load. **Communicate with the affected users/region explicitly** — a regional incident often gets under-communicated because global dashboards look green.

**The framing:** "Regional slowness with healthy global metrics means either (a) my regional infrastructure is degraded, or (b) the path between those users and my edge is degraded. I separate those in the first two minutes by comparing server-measured and client-measured latency, then walk the path — DNS, routing, edge/CDN, TLS, MTU, in-region capacity, dependencies — using synthetic probes from that region, because I cannot debug a network path I cannot observe from the affected vantage point."

### 12. "Design the network architecture for a multi-region, multi-tenant platform."
**Requirements to fix:** regions and why (latency to users, data residency, DR), tenant isolation level, east-west vs north-south volumes, compliance constraints, hybrid/on-prem connectivity, and whether traffic must stay in-region (data residency is a hard architectural constraint, not a preference).

**The design:**
```
                        Global anycast edge / DNS-based geo-routing
                        (Route 53 latency+health / Traffic Manager / Cloud DNS)
                                     │
                    ┌────────────────┴────────────────┐
              Region A                             Region B
   ┌──────────────────────────────┐    ┌──────────────────────────────┐
   │ CDN/WAF/DDoS (global edge)    │    │ CDN/WAF/DDoS                  │
   │ L4 LB (static/anycast IP)     │    │ L4 LB                         │
   │ L7 gateway cluster (multi-AZ, │    │ L7 gateway cluster            │
   │   multi-replica, PDB, anti-aff│    │                               │
   │ Transit/hub VPC:              │    │ Transit/hub VPC:              │
   │   - central egress + inspect  │    │   - central egress + inspect  │
   │   - DNS resolver (in/out)     │    │   - DNS resolver              │
   │   - hybrid connect (DX/ER/IC) │    │   - hybrid connect            │
   │ Workload VPCs (per env):      │    │ Workload VPCs (per env):      │
   │   public / app / data subnets │    │   public / app / data subnets │
   │   per-AZ NAT, VPC endpoints   │    │   per-AZ NAT, VPC endpoints   │
   │ Kubernetes: CNI (eBPF),       │    │ Kubernetes: CNI (eBPF),       │
   │   Gateway API, NetworkPolicy  │    │   Gateway API, NetworkPolicy  │
   │   default-deny, mesh/ambient  │    │   default-deny, mesh/ambient  │
   │ Data: regional primary +      │    │ Data: regional primary +      │
   │   cross-region async replica  │    │   cross-region async replica  │
   └──────────────────────────────┘    └──────────────────────────────┘
                    │                                   │
                    └──── cross-region backbone: dedicated interconnect /
                          cloud backbone, encrypted, BGP, health-checked ────┘
```
**The decisions to articulate:**
1. **Traffic routing model**: **anycast** (one IP, nearest edge — fastest, but routing is out of your control and can shift mid-session; great for stateless/CDN, awkward for stateful sessions) vs **DNS-based geo/latency routing** (controllable, but TTL/cache-dependent and slow to change) vs **a global L7 proxy layer** (full control, extra hop and cost). **Most platforms use DNS + CDN/anycast at the edge and explicit routing at the gateway**, with health-checked failover.
2. **Data residency and the "pinning" requirement**: if EU user data must stay in the EU, you need **request routing by tenant/user home region**, not just by latency — which means identity-aware routing at the edge (route on the tenant claim), and a **data-plane partition per residency zone**. **This is the hardest constraint in multi-region design and it drives the whole architecture.**
3. **State placement**: **single-writer per data partition** (route writes to the home region, read replicas elsewhere), **or** multi-active with conflict resolution for the data classes that tolerate it (sessions, carts, feature flags). **Never accidentally multi-active for money or inventory.**
4. **Cross-region connectivity**: the cloud provider's **private backbone** (transit gateway/TGW peering, Virtual WAN, Network Connectivity Center) — encrypted, higher bandwidth, lower and more predictable latency than the public internet, and it avoids egress-to-internet pricing. **Design for the inter-region RTT** (60–150 ms): **no chatty synchronous cross-region calls in a request path**. Anything that needs N round trips cross-region will be unusable — batch, cache, or make it async.
5. **Failure domains**: AZs within a region are the primary failure domain (design for N+1 or N+2 AZ); **regions are the secondary** (design for one region losing all traffic). **And correlated failures exist** — a global DNS provider, a single SaaS auth vendor, one CI system, one observability vendor. **List your global single points of failure explicitly; that list is your real availability posture.**
6. **Tenant isolation in the network**: separate namespaces/VPCs/sub-accounts per tier of tenant; NetworkPolicy default-deny per tenant; **per-tenant rate limits at the gateway** (one tenant must not be able to exhaust shared capacity); and **noisy-neighbour containment** via node pools or cells. For hostile tenants, cell-based architecture (each cell serves N tenants, independently deployable and failover-able) bounds the blast radius.
7. **Egress control**: central egress VPC with an allowlisting proxy/firewall in every region → blocks exfiltration, blocks SSRF-to-metadata paths, gives you one place to audit outbound traffic. **Default-deny egress is a top-3 network security control.**
8. **Private endpoints for all cloud PaaS** so management and data traffic never traverses the public internet.
9. **DNS architecture**: split-horizon (internal names resolve differently inside), **private hosted zones replicated per region**, low TTLs (30–60s) for failover records, health-checked failover, and **a second DNS provider or a documented manual break-glass** — because DNS is a global SPOF. **Cache DNS results in your services and have a fallback for the critical path.**
10. **TLS/certificate architecture**: a global CA strategy (public ACME for edge, internal CA for service-to-service), automated issuance and rotation in every region, **short-lived workload certs (SPIFFE/SPIRE)**, SNI handling at the gateway, and **expiry monitoring for every cert including intermediates** in every region.
11. **Observability of the network itself**: per-region and per-PoP latency/error dashboards (not just global aggregates), synthetic probes from every region and several ISPs, VPC flow logs, eBPF/Hubble service-graph visibility, DNS query metrics, LB health-check state history, and **alerts on cross-region RTT and loss** (a degrading backbone shows up there first).
12. **Failover design**: what fails over automatically (edge routing, DNS with health checks, LB targets), what requires a human decision (database promotion — because it risks data loss), and **what the runbook is**. **Test it**: a quarterly regional failover game day. Untested multi-region failover is a claim, not a capability.

**The trade-off statement:** "I'd resist full active-active unless there's a measured requirement. Active-active doubles cost, requires conflict resolution or strict data partitioning, and multiplies the test matrix — while most of the availability benefit comes from **multi-AZ within a region plus a warm, tested regional failover**. So my default is: **active in every region for reads and for regionally-resident tenants, single-writer per data partition, automated edge failover, human-approved data failover, and a quarterly rehearsed regional outage.**"

### 13. "gRPC calls are unbalanced — 3 new pods get no traffic. Why, and how do you fix it?"
**The mechanism (this is a precise, well-known problem):**
1. gRPC runs over **HTTP/2**, which **multiplexes many RPCs over one long-lived TCP connection**.
2. A Kubernetes **ClusterIP Service** load-balances **at connection establishment** (kube-proxy DNAT picks one backend pod when the connection is created).
3. The gRPC client opens **one connection** and keeps it (HTTP/2 is designed for connection reuse).
4. **So every RPC from that client goes to the same pod forever.** New pods receive traffic only from *new* connections — and if your clients are long-lived services, there are no new connections.
5. Result: after scaling from 3 to 10 pods, the original 3 pods carry ~all the load; the 7 new pods sit idle. **Autoscaling appears broken, HPA does nothing (CPU stays high on the busy pods), and latency degrades.**

**The fixes, best to worst:**
1. **Client-side load balancing with per-RPC selection** — the correct fix for gRPC:
   - Use a **headless Service** (`clusterIP: None`) so DNS returns **all pod IPs** (A records), and configure the gRPC channel with a **`round_robin` (or `pick_first` + resolver) load-balancing policy**. The client's resolver watches DNS, maintains a subchannel per pod, and picks one **per RPC**.
   - Caveat: DNS-based discovery has TTL/caching issues (the client may not re-resolve) — set an appropriate resolver refresh, or use **xDS-based discovery**.
2. **xDS / a service mesh** — Envoy (sidecar or ambient) or Cilium does **per-request (per-stream) L7 load balancing**, which is exactly what HTTP/2 needs. This is one of the strongest concrete justifications for adopting a mesh.
3. **`max_connection_age` / `max_connection_age_grace` on the server** — force clients to reconnect periodically (e.g. every 30–60s with jitter), so new pods get picked up. **A cheap, effective mitigation** that doesn't require client changes; the cost is periodic connection churn (and you must add jitter, or all clients reconnect simultaneously → a thundering herd).
4. **An L7 proxy in front** (an Envoy/Linkerd/ingress with gRPC support) that terminates the client connection and opens its own balanced connections to backends.
5. **Periodic client-side connection recycling** (a hack, but common): tear down and re-create channels on an interval.
6. **What does NOT work:** kube-proxy IPVS mode (still per-connection), increasing replicas without one of the above, `sessionAffinity: None` (it's already effectively per-connection), or L4 load balancers generally.

**The generalisation worth stating:** "This is a general property of **any long-lived multiplexed protocol over an L4 load balancer** — gRPC/HTTP2, WebSockets, database connection pools, Kafka consumers, MQTT. **L4 load balancers balance connections; multiplexed protocols need L7 load balancing or client-side balancing.** Whenever I see a service that doesn't scale horizontally as expected, connection-level load balancing is one of the first things I check — and the diagnostic is trivial: look at the per-pod request rate, and if it's wildly uneven while the pod count is stable, that's it."

### 14. "Traffic to your service intermittently fails with 'connection reset' and 'timeout' under load. Diagnose."
**Ranked causes, each with the specific check:**

1. **Accept queue overflow** (very common, frequently missed).
   - Symptom: intermittent `connection reset by peer` or SYN retransmit timeouts under load, while the app looks healthy.
   - Check: `netstat -s | grep -iE 'overflow|SYNs to LISTEN'` → "times the listen queue of a socket overflowed", "SYNs to LISTEN sockets dropped". Or `ss -lnt` → `Recv-Q` approaching `Send-Q` on the listening socket.
   - Fix: raise **both** `net.core.somaxconn` **and** the application's listen backlog (nginx `listen ... backlog=`, Go `net.Listen` uses the sysctl, Envoy/Tomcat/Netty have their own settings). Also make the app accept faster (a wedged accept loop is the real cause sometimes).

2. **Ephemeral port exhaustion / TIME_WAIT buildup** on the client or proxy side.
   - Symptom: `cannot assign requested address` (`EADDRNOTAVAIL`), failures when opening *outbound* connections.
   - Check: `ss -s`, `ss -tan state time-wait | wc -l`, `cat /proc/sys/net/ipv4/ip_local_port_range`, `netstat -s | grep -i 'TCP: request_sock\|port'`.
   - Fix: **connection pooling/keep-alive** (the real fix), widen the port range, more source IPs, `tcp_tw_reuse` (outbound only, with timestamps). **Never `tcp_tw_recycle`** (removed in 4.12; broke NAT).

3. **Conntrack table full.**
   - Symptom: dropped packets, intermittent failures; `dmesg` shows `nf_conntrack: table full, dropping packet`.
   - Check: `cat /proc/sys/net/netfilter/nf_conntrack_count` vs `nf_conntrack_max`; node metrics `node_nf_conntrack_entries`.
   - Fix: raise `nf_conntrack_max` (and `nf_conntrack_buckets`), reduce connection churn, shorten `nf_conntrack_tcp_timeout_*`, or move to an **eBPF datapath (Cilium)** that avoids conntrack for service resolution.

4. **File descriptor exhaustion.**
   - Symptom: `too many open files` in app logs, or connections refused/reset.
   - Check: `cat /proc/<pid>/limits`, `ls /proc/<pid>/fd | wc -l`, `ss -s`. **Also check the container's and the node's limits, not just the process's.**
   - Fix: raise `nofile` (systemd `LimitNOFILE`, container runtime limits, `fs.nr_open`), **fix the fd leak** (unclosed response bodies, unclosed DB connections, missing `defer Close()`), and set client idle timeouts.

5. **Load balancer / proxy limits.**
   - Idle timeout (ALB 60s default) killing long requests → resets at exactly 60s.
   - Connection limits, per-target limits, WAF rate limits, request body size limits (413 → sometimes surfaced as a reset).
   - Health check flapping → targets repeatedly drained.
   - Deregistration/drain mismatch during deploys.
   - Check: LB metrics (5xx by reason, reset counts, active connections, healthy target count over time), LB access logs.

6. **Kernel/resource saturation on the node.**
   - CPU saturation (softirq/ksoftirqd at 100% → packet processing can't keep up), NIC queue saturation, `netdev_budget`, memory pressure, THP compaction stalls.
   - Check: `mpstat -P ALL 1` (look at `%soft`), `sar -n DEV`, `/proc/pressure/*` (PSI), `dmesg`, node metrics, `ethtool -S <iface>` (dropped/error counters), `tc -s qdisc` (qdisc drops).
   - Fix: RSS/RPS/RFS tuning, more/bigger nodes, reduce per-node connection density, and **don't co-locate a high-connection-churn workload with a latency-sensitive one**.

7. **MTU / PMTUD blackhole** (see Q1) — signature: handshakes fine, large transfers hang. Check with `ping -M do -s`, `tracepath`, or `ip link` MTU vs the overlay overhead.

8. **DNS resolution failures** manifesting as timeouts — especially the 5-second signature (see Q3). Check CoreDNS health, conntrack UDP races, `ndots` amplification.

9. **Application-level limits**: thread pool exhaustion, connection pool exhaustion (to the DB), a bounded queue rejecting, a semaphore, or a GC pause long enough to trip health checks/keepalives. Check pool saturation metrics and GC logs.

10. **Security/egress controls**: a rate limiter, a WAF rule, a NetworkPolicy, a cloud quota (NLB/ALB limits, ENI/IP limits), or a DDoS-mitigation false positive kicking in under load.

**The systematic method:**
```bash
# 1. Classify the failure: reset vs timeout vs refused — they mean different things
#    refused  = nothing listening / RST from the stack (port closed, or accept queue with tcp_abort_on_overflow)
#    reset    = a connection existed and was torn down abnormally (LB drain, app crash, queue overflow, firewall)
#    timeout  = packets silently dropped (conntrack full, MTU, security group, saturation, DNS)
# 2. Correlate with load: at what RPS/connection rate does it start? That number is your real capacity.
# 3. Look at the whole path, one layer at a time, with counters at each:
#    client → DNS → LB → node (conntrack/ports/softirq) → accept queue → app → dependencies
# 4. Read kernel counters, not just app logs: netstat -s, ss -s, /proc/net/sockstat,
#    nf_conntrack_count, ethtool -S, tc -s qdisc, dmesg, PSI
# 5. Reproduce under controlled load (k6/vegeta/wrk) to find the threshold and confirm the fix.
```
**The framing:** "'Connection reset' and 'timeout' are different failures and I treat them separately: a **reset** means something actively tore down a connection (LB drain, accept-queue overflow with abort, an app crash, a firewall RST), while a **timeout** means packets vanished (conntrack full, MTU blackhole, saturation, a security group). Under load the top three are almost always **accept-queue overflow, ephemeral-port/TIME_WAIT exhaustion, and conntrack table exhaustion** — all three are kernel-counter problems, not application problems, so I read `netstat -s`, `ss -s` and `nf_conntrack_count` before I read a single application log. And the fix that addresses two of the three is the same: **connection reuse**, because churn is what exhausts ports and conntrack."

---

## Red flags

| Saying / doing this | Costs you |
|---|---|
| "A container is a VM" / conflating L4 and L7 LB | Foundational misunderstanding |
| `tcp_tw_recycle` to fix TIME_WAIT | Removed in Linux 4.12; broke NAT |
| Raising `somaxconn` without the app's backlog | Does nothing |
| Assuming a TCP health check means the app works | Passes on a wedged process |
| L7 health checks that hit a dependency | Cascade failure when the dependency blips |
| L4 load balancing for gRPC/HTTP2/WebSockets | New pods get no traffic |
| No `max_connection_age` and no client-side LB on gRPC | Horizontal scaling doesn't work |
| Ignoring MTU with overlays/VPN | Small requests fine, large ones hang |
| Not monitoring intermediates' cert expiry | Mass TLS failure |
| Serving an incomplete certificate chain | Works in browsers, fails in Java/curl |
| JVM DNS caching left at default | Failover never happens |
| CoreDNS with 1 replica | Cluster-wide SPOF |
| `ndots:5` left unaddressed in a chatty service | 4–5× DNS amplification |
| No default-deny NetworkPolicy | Flat network; lateral movement is free |
| No egress filtering | Exfiltration and SSRF-to-metadata both work |
| Adopting a service mesh with no owning team | A mystery layer everyone blames |
| Assuming a mesh is free | ~50–100 MB RAM + latency per pod |
| Debugging a regional network issue from your office | You can't observe the path |
| Global-average dashboards for a regional problem | The bad region is invisible in the average |
| Cross-region synchronous chatty calls | 60–150 ms per hop, unusable |
| Multi-active writes for money/inventory | Unresolvable conflicts |
| Untested regional failover | A claim, not a capability |
| Ignoring kernel counters when connections fail | You'll read app logs for an hour and find nothing |

## Rapid recall

1. **Diagnose by layer**: ping fails → L3; TCP connect fails → L4; TLS fails → certs/chain/SNI; HTTP 5xx → L7; large payloads hang → **MTU/PMTUD blackhole**.
2. **TCP**: TIME_WAIT is normal and needed; fix port exhaustion with **connection reuse**, not `tcp_tw_recycle` (removed in 4.12). **Accept queue overflow** → intermittent resets/timeouts → raise `somaxconn` **and** the app backlog. Slow start means short-lived connections never reach full throughput → reuse connections. Set `TCP_NODELAY`. Default keepalive is 2 hours — too long.
3. **Congestion control**: CUBIC (loss-based default) vs **BBR** (bandwidth/RTT model, better on lossy/high-BDP). TCP HOL blocking is why **QUIC/HTTP3** exists.
4. **DNS**: `ndots:5` amplification; **the exactly-5-second timeout = UDP conntrack race → NodeLocal DNSCache**; JVM/resolver TTL overrides break failover; negative caching; CNAME can't be at the apex (use alias records); **CAA** records; split-horizon as a debugging trap.
5. **TLS 1.3**: 1-RTT, mandatory forward secrecy (no static RSA), 0-RTT resumption has replay risk. **Serve the full chain**; validate SAN not CN; **OCSP stapling**; monitor **every cert including intermediates**; automate with cert-manager/ACME; **short-lived workload certs (SPIFFE/SPIRE) — rotate instead of revoke**.
6. **LB algorithms**: least-connections for variable-cost work; **power-of-two-choices** (nginx/Envoy); **consistent hashing** for affinity/cache locality. **L4 = per-connection, protocol-agnostic, preserves client IP; L7 = per-request, routes on content, needs XFF/Proxy Protocol.** Tune health checks, drain timeouts and slow start.
7. **Kubernetes request path**: DNS → ClusterIP (virtual) → kube-proxy/eBPF DNAT → conntrack → CNI (overlay VXLAN/IPIP or native routing/eBPF) → pod. **kube-proxy balances per connection**; endpoint propagation lag causes rollout 502s; conntrack exhaustion is a classic; VPC CNI eats IPs.
8. **Service mesh**: automatic mTLS + workload identity, uniform retries/timeouts/circuit breaking, traffic splitting, L7 telemetry and authz. Costs: **~0.5–2 ms and 50–100 MB per sidecar**, a control plane to run, version skew, and a bigger debugging surface. **Alternatives**: Linkerd (simpler), **Cilium/eBPF (sidecar-less)**, Istio **ambient mode** (ztunnel + waypoints). Below ~20–30 services, use Gateway API + a shared client library + NetworkPolicy + OTel.
9. **eBPF**: verified in-kernel programs at hooks (XDP/tc/kprobe/tracepoint/LSM/cgroup). **O(1) service lookup vs iptables O(n)**, XDP for line-rate L4 LB/DDoS, **sockmap for same-node shortcut**, and observability/security for unmodified binaries (Hubble, Tetragon, Pixie, Parca, Falco).
10. **HTTP/2 vs 3**: H2 multiplexes over TCP (**TCP HOL remains, and long-lived connections break L4 LB**); H3/QUIC runs over UDP with independent streams, 0–1 RTT, and connection migration — but needs **UDP permitted end to end** and moves telemetry into proxies.
11. **Layering**: CDN/WAF/DDoS → global LB → L4 LB → **API gateway (product: auth, quotas, keys, versioning)** → **Ingress/Gateway API (routing)** → **mesh (east-west: mTLS, retries, splitting, telemetry)** → **BFF (client-specific composition)**. Don't do one layer's job in another.
12. **Regional slowness**: compare **server-measured vs client-measured latency** first → inside-the-region vs on-the-path. Then DNS → routing/peering → CDN/PoP → TLS → MTU → in-region capacity/dependencies → traffic → config. **Use synthetic probes from the affected region.**
13. **Multi-region network**: DNS/anycast edge + health-checked failover; **data residency drives identity-aware routing**; **single-writer per partition**; cross-region over the **private backbone** (design for 60–150 ms, no chatty sync calls); default-deny NetworkPolicy + **central egress with allowlisting**; **private endpoints**; split-horizon DNS with low failover TTLs; automated certs everywhere; **per-region (not global-average) dashboards**; **quarterly rehearsed regional failover**.
14. **gRPC imbalance**: HTTP/2 multiplexes over one long-lived connection + kube-proxy balances per connection → new pods get nothing. Fix with **client-side `round_robin` + a headless Service**, **xDS/mesh per-request LB**, or **server-side `max_connection_age` with jitter**. Generalises to WebSockets, DB pools, Kafka, MQTT.
15. **Intermittent resets/timeouts under load**: classify reset vs timeout vs refused, then read **kernel counters** (`netstat -s`, `ss -s`, `nf_conntrack_count`, `ethtool -S`, `tc -s qdisc`, `dmesg`, PSI) — the top three are **accept-queue overflow, ephemeral-port/TIME_WAIT exhaustion, and conntrack exhaustion**, and two of them are fixed by **connection reuse**.

→ Next: [`18-Behavioral-and-Leadership`](../18-Behavioral-and-Leadership/README.md)
