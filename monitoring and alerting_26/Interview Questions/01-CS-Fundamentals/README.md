# 01 · CS Fundamentals

Operating systems, Linux internals, networking, HTTP/TLS. These come up in **every** role on your list — DevOps/SRE/Platform screens lean on them hardest, and SDE III candidates lose points here because they assume it won't be asked.

---

## 🟢 Basic

### 1. Process vs thread vs coroutine
A **process** is an instance of a program with its own virtual address space, file descriptors and resource limits — isolated, so a crash takes only itself down, but context switches are expensive (page-table/TLB flush). A **thread** lives inside a process, shares its address space and fds, but has its own stack and registers — cheap to switch, but one thread's memory bug corrupts everyone. A **coroutine** (goroutine, green thread, async task) is scheduled in *user space* by the runtime, not the kernel: switching costs nanoseconds and stacks are small and growable, so you can run hundreds of thousands.

**Trade-off to state:** threads give you preemption and true parallelism with kernel scheduling; coroutines give you massive concurrency cheaply but only parallelise across the OS threads the runtime pins them to, and a blocking syscall can stall others unless the runtime handles it (Go's netpoller does; naive Python asyncio doesn't).

### 2. What happens when you type a URL and press Enter?
The canonical question — give the full chain and *volunteer* where you'd dig deeper:

1. **URL parse** → scheme, host, port, path, query
2. **HSTS check** (if the domain is on the preload/list, force HTTPS)
3. **DNS resolution**: browser cache → OS cache (`nscd`/`systemd-resolved`) → `/etc/hosts` → resolver in `/etc/resolv.conf` → recursive resolver → root → TLD → authoritative → A/AAAA record (plus CNAME chain). TTLs decide caching at each hop.
4. **TCP handshake** (SYN, SYN-ACK, ACK) — or QUIC/HTTP3 over UDP with TLS 1.3 0-RTT
5. **TLS handshake**: ClientHello (SNI, cipher suites, ALPN) → server cert → verify chain against trust store + hostname + expiry → key exchange (ECDHE) → finished. Session resumption via tickets skips most of this.
6. **HTTP request** sent; may traverse CDN edge → cloud LB → ingress → service → app
7. **Server processes**, may hit cache/DB/downstream services
8. **Response** returned; browser parses HTML → CSSOM + DOM → render tree → layout → paint; subresources fetched (with their own DNS/TCP/TLS unless connection-reused)
9. **Connection** kept alive for reuse or closed

**Senior addition:** "The three places I look first when this is slow are DNS (resolution latency, TTLs), TLS (handshake count, session reuse, cert chain length) and the redirect chain. Each is invisible in the app's own metrics."

### 3. TCP vs UDP — when each?
**TCP**: connection-oriented, ordered, reliable, flow- and congestion-controlled (slow start → congestion avoidance → fast retransmit). Costs a handshake, head-of-line blocking, and retransmit latency. Use for anything that must not lose or reorder data: HTTP/1.1, HTTP/2, SSH, databases.

**UDP**: connectionless datagrams, no ordering, no retransmission, no congestion control. Costs nothing in setup and never blocks a later packet on an earlier one. Use for DNS, QUIC/HTTP3, media streaming, game state, metrics (StatsD), service discovery.

**The senior point:** QUIC moved HTTP/3 to UDP *precisely* to escape TCP head-of-line blocking — one lost packet in HTTP/2 stalls every stream on that connection. QUIC also folds TLS 1.3 into the transport handshake (1-RTT, or 0-RTT on resume) and migrates connections across network changes via connection IDs.

### 4. What's in an HTTP request/response, and which methods are safe/idempotent?
Request: method, path, version, headers, optional body. Response: status line, headers, optional body.

| Method | Safe (no server state change) | Idempotent (N calls = 1 call) |
|---|---|---|
| GET | ✅ | ✅ |
| HEAD | ✅ | ✅ |
| OPTIONS | ✅ | ✅ |
| PUT | ❌ | ✅ |
| DELETE | ❌ | ✅ |
| POST | ❌ | ❌ |
| PATCH | ❌ | ❌ (usually) |

**Why it matters in interviews:** idempotency is what makes retries safe. A `POST /charge` retried after a timeout can double-charge; that's why payment APIs require an `Idempotency-Key` header and dedupe server-side. Say this — it connects theory to a real design decision.

### 5. Status codes you should never fumble
| Class | Codes |
|---|---|
| **2xx** | 200 OK · 201 Created · 202 Accepted · 204 No Content · 206 Partial Content |
| **3xx** | 301 Moved Permanently · 302 Found · 304 Not Modified (cache) · 307/308 temporary/permanent **preserving method** |
| **4xx** | 400 Bad Request · 401 **Unauthenticated** · 403 **Authorised but forbidden** · 404 · 405 · 408 Request Timeout · 409 Conflict · 413 Payload Too Large · 422 Unprocessable · 429 **Too Many Requests** (rate limit; pair with `Retry-After`) |
| **5xx** | 500 Internal · 501 Not Implemented · 502 **Bad Gateway** (upstream gave garbage/refused) · 503 **Service Unavailable** (overloaded/down — retryable) · 504 **Gateway Timeout** (upstream too slow) |

**The distinction interviewers probe:** 502 vs 504. 502 = upstream responded with something invalid or refused the connection. 504 = upstream accepted but didn't respond in time. Different root causes, different fixes. And **401 vs 403**: 401 means "who are you?" (authentication failed/missing), 403 means "I know who you are and you may not."

### 6. What is DNS, and what's a TTL?
A hierarchical distributed database mapping names → records. Resolution is recursive from the client's stub resolver to a recursive resolver, then iterative down root → TLD → authoritative.

**TTL** is how long each record may be cached by resolvers. Operational consequences you should volunteer:
- **Low TTL (30–60s)** for records you may need to change during failover — but it increases query load and adds resolution latency on cold caches.
- **High TTL (1h–1d)** for stable records — cheaper and faster, but a failover then takes as long as the old TTL to drain, and some resolvers ignore TTLs and cache longer.
- **Lower the TTL *before* the migration, not during.** This is a classic ops mistake.
- Negative caching (`NXDOMAIN`) is governed by the SOA minimum, not the record TTL.

### 7. Symmetric vs asymmetric encryption; how does TLS use both?
**Symmetric** (AES-GCM, ChaCha20-Poly1305): one shared key, fast, used for bulk data. **Asymmetric** (RSA, ECDSA): public/private pair, ~1000× slower, used for key agreement and signatures.

TLS uses asymmetric crypto **only** to establish a symmetric key: ECDHE key exchange gives a shared secret over an open channel; the server's certificate (signed by a CA whose public key you trust) proves it owns the private key for that hostname. All subsequent data is symmetric AEAD — authenticated *and* encrypted, so tampering is detected.

**Forward secrecy** is the point of the E in ECDHE: the session key is ephemeral, so compromising the server's long-term private key later does **not** let an attacker decrypt recorded past sessions. RSA key transport (deprecated) had no such property.

### 8. What is a load balancer, and L4 vs L7?
**L4** (transport): routes on IP + port, no HTTP parsing. Fast, cheap, protocol-agnostic (works for TCP/gRPC/anything). Cannot route on path, host, header or cookie; cannot terminate TLS to inspect; health checks are connect-only.

**L7** (application): terminates TLS and parses HTTP. Can route by path/host/header/cookie, do retries with a different backend, rewrite, compress, WAF, read `X-Forwarded-For`, and health-check a real endpoint (`GET /healthz` expecting 200). Costs more CPU and terminates the connection, so the backend sees the LB as the client.

**Real stacks use both:** cloud L4 (NLB/CLB) in front → L7 (ingress/ALB/Envoy) → services. **Senior point:** with L4 you lose the real client IP unless you use PROXY protocol or preserve source IP (which constrains the LB); with L7 you must set and *trust* `X-Forwarded-For` correctly, or your rate limiter keys on the LB's IP and blocks everyone at once.

### 9. Virtual memory, and why does the OOM killer exist?
Each process gets a virtual address space mapped to physical pages by the MMU via page tables. Benefits: isolation, memory larger than RAM (swap), copy-on-write for `fork`, and randomisation (ASLR).

The **OOM killer** fires when the kernel cannot satisfy an allocation and reclaim enough. It scores processes (`oom_score`, driven mostly by RSS, tunable with `oom_score_adj`) and kills the worst. `-1000` makes a process unkillable (use for sshd/kubelet, sparingly).

**The distinction that matters in Kubernetes:** a container exceeding its memory **limit** is cgroup-OOMKilled (`reason: OOMKilled`, exit 137) — that's Kubernetes/cgroup enforcement, not host memory pressure. Host-level OOM with `MemoryPressure` node condition is different and evicts pods by QoS class. Mixing these up is a very common tell.

### 10. Threads vs async I/O — what's the actual difference?
Both handle concurrency; they differ in *who blocks*. With threads, a blocked syscall parks a kernel thread (you pay ~1–8 MB stack reservation and a kernel context switch). With async I/O, you register interest in fds and the runtime multiplexes via `epoll`/`kqueue`/`io_uring` — no thread is parked, so 10k concurrent connections cost ~1 thread.

**Async's cost:** every call site must be non-blocking, or you stall the whole loop; the code is coloured (async/await infects the call stack); CPU-bound work still needs a thread/process pool; and stack traces are worse.

**Go's answer** is why people like it: goroutines look like threads (blocking style, no colouring) but the runtime multiplexes them onto few OS threads and intercepts network syscalls into the netpoller. You get async economics with sync ergonomics — except for truly blocking work (cgo, file I/O on some platforms), which still ties up an OS thread.

---

## 🔵 Advanced

### 11. What actually happens on a context switch, and why is it expensive?
**Process switch:** save/restore registers and kernel state, switch the page-table base register (CR3 on x86), which **invalidates the TLB** — so subsequent memory accesses walk page tables until the TLB refills. Also cold caches: the new process's working set isn't in L1/L2/L3. Mitigations: ASIDs/PCIDs tag TLB entries per address space so they survive switches; KPTI (Meltdown mitigation) costs extra page-table switches on every syscall.

**Thread switch within a process:** no address-space change, so the TLB survives — much cheaper. Still costs register save/restore, possible cache pollution, and scheduler work.

**Costs that dominate in practice:** it's rarely the switch itself (~1–5 µs); it's the **cache and TLB pollution afterwards**. A context-switch storm shows up as high `sys` CPU with low throughput.

**How to see it:** `vmstat 1` (`cs` column), `pidstat -w` (voluntary = waiting on I/O/locks; involuntary = preempted, means CPU contention), `perf stat -e context-switches`, `/proc/<pid>/status`. **Voluntary vs involuntary is the diagnostic:** high involuntary means you're oversubscribed on CPU or your scheduling latency is bad; high voluntary means you're I/O- or lock-bound.

### 12. Explain `epoll` vs `select`/`poll`, and edge- vs level-triggered
`select`/`poll` pass the *entire* fd set to the kernel on every call and the kernel scans it linearly — O(n) per wakeup, plus copying the set each time. Useless past a few hundred fds.

`epoll` keeps the fd set **inside the kernel** (`epoll_ctl` to add/remove once), and `epoll_wait` returns only the ready fds — O(ready), not O(n). That's what makes C10k+ servers possible. (`kqueue` is the BSD/macOS equivalent; `io_uring` is the newer Linux ring-buffer interface that also batches and can do zero-copy and true async file I/O.)

**Level-triggered** (default): `epoll_wait` keeps reporting an fd while it's *ready* (data remains unread). Simple and forgiving — you can read partially and be told again.

**Edge-triggered**: you're notified only on the *transition* to ready. You must drain until `EAGAIN` in a loop, or you'll never be told again and the connection silently hangs. Fewer wakeups, but a whole class of bugs.

**Where you'd encounter this:** nginx uses edge-triggered epoll; most Go programs never think about it because the netpoller abstracts it. Knowing *why* nginx's worker loop looks the way it does is the difference between reciting and understanding.

### 13. A service is at 100% CPU but throughput is flat. How do you diagnose?
First, split user vs system vs iowait vs steal:

```bash
top / htop            # %us, %sy, %wa, %st
mpstat -P ALL 1       # per-core: is one core pegged (single-threaded bottleneck) or all?
pidstat -u 1          # which process
```

- **High `%sy`** → syscalls, context switches, network stack, memory reclaim. Check `vmstat 1` (`cs`, `in`), `perf top`, strace a sample. Often lock contention, tiny writes, or excessive `getaddrinfo`.
- **High `%us`, one core pegged** → single-threaded bottleneck (Python GIL, a hot loop, GC). Fix the algorithm or parallelise; adding CPUs won't help.
- **High `%us`, all cores** → real work or GC thrash. Profile: `pprof` (Go), `async-profiler` (JVM), `py-spy` (Python), `perf record`. Look for a flame-graph plateau.
- **High `%wa`** → not CPU-bound at all; you're blocked on I/O. `iostat -x 1`, check `%util` and `await`.
- **High `%st`** → the hypervisor is starving you (noisy neighbour / oversubscribed host / CPU limits throttling). In Kubernetes, check **CPU throttling**, not just usage.
- **GC** → JVM: `jstat -gcutil`, look for full-GC frequency; Go: `GODEBUG=gctrace=1`.

**The senior move:** say "I'd first determine whether it's CPU-bound or CPU-*waiting*" — because 100% CPU with flat throughput usually means spin/lock contention, GC, or syscall overhead, not productive work. Then name the specific tool for the language.

```promql
# Kubernetes CPU throttling — the thing everyone misses
sum by (pod) (rate(container_cpu_cfs_throttled_periods_total[5m]))
  / sum by (pod) (rate(container_cpu_cfs_periods_total[5m])) > 0.5
```
A pod can show 400m/1000m average CPU and still be heavily throttled, because throttling is enforced per 100ms period — a bursty single-threaded workload hits its quota in 40ms and sleeps for 60. **Symptom: latency spikes with unremarkable average CPU.**

### 14. What is the GIL, and does it mean Python can't do concurrency?
The **Global Interpreter Lock** is a mutex around CPython's interpreter state, so only one thread executes Python bytecode at a time. It exists because CPython's object refcounting isn't thread-safe; removing it would cost single-thread performance and break C-extension assumptions.

What it means precisely:
- **CPU-bound threads don't parallelise.** Use `multiprocessing` (separate interpreters, real cores, IPC cost) or push the work into C/Rust extensions (NumPy releases the GIL) or a native runtime.
- **I/O-bound threads work fine** — the GIL is released during blocking syscalls, so 500 threads doing socket I/O genuinely overlap.
- **asyncio works for I/O** — one thread, cooperative, no GIL contention at all, but any blocking call stalls everything.
- **3.13+ has free-threaded (no-GIL) builds** and per-interpreter GILs (PEP 684, `concurrent.futures.InterpreterPoolExecutor`). It's opt-in and the ecosystem (C extensions) is still catching up, so I'd not bet production on it yet — but it's the direction.

**The interview-winning answer:** "The GIL blocks *parallelism*, not *concurrency*. I choose multiprocessing for CPU-bound, threads or asyncio for I/O-bound, and I'd measure before assuming — often the real bottleneck is the downstream service, not the interpreter."

### 15. Explain memory management: stack vs heap, and how GC differs across Go/JVM/Python
**Stack**: per-thread, LIFO, allocation is a pointer bump (near-free), automatically reclaimed on return, cache-friendly, size-limited (`ulimit -s`, default 8 MB; goroutine stacks start ~2–8 KB and grow). Holds locals, frames, and value types.

**Heap**: shared, arbitrary lifetime, allocated/freed explicitly or by GC, can fragment, needs synchronisation. Holds anything that outlives its frame or is dynamically sized.

**Go**: escape analysis decides stack vs heap at compile time (`go build -gcflags="-m"` shows it). Concurrent **tri-colour mark-and-sweep** with write barriers, targeting ~25% CPU overhead (`GOGC`, plus `GOMEMLIMIT` for a soft memory ceiling — essential in containers, because Go otherwise sizes the heap from *host* memory). No compaction; relies on size classes and span reuse. Pause times are sub-millisecond.

**JVM**: generational (young/old) with sophisticated collectors — G1 (default, region-based, predictable pauses), ZGC and Shenandoah (concurrent, sub-ms pauses at multi-hundred-GB heaps). Compacting, so no fragmentation. Tunable to an extreme, which is both its strength and its operational risk.

**Python**: refcounting (immediate, deterministic reclaim, but cycles leak) plus a generational mark-sweep cycle collector for exactly that case. Refcounting means every object mutation touches the count → contention → part of why the GIL exists.

**Where this bites in production:** a JVM/Go process in a container that doesn't know its memory limit will OOMKill. Fix: `GOMEMLIMIT`/`-XX:MaxRAMPercentage` (not `-Xmx` hardcoded), and always set both requests and limits.

### 16. What is a race condition vs a data race? How do you detect them?
A **data race** is the low-level, mechanical thing: two threads access the same memory concurrently, at least one writes, and there's no synchronisation. It's undefined behaviour in C/C++, and detectable by tooling.

A **race condition** is the higher-level, semantic thing: correctness depends on the *timing or interleaving* of operations. You can have a race condition with no data race — e.g. check-then-act (`if balance >= 100 { balance -= 100 }`) where each access is properly locked but the compound operation isn't atomic. TOCTOU (time-of-check-to-time-of-use) in filesystem operations is the classic: you `stat` a file, then open it, and it was swapped between.

**Detection:**
- Go: `go test -race` (ThreadSanitizer) — catches data races only; **it will not find your check-then-act bug.**
- Java: `-Xcheck:jni` is not it; use ThreadSanitizer via native code, jcstress for concurrency tests, or careful review + `java.util.concurrent` primitives.
- Python: hard (GIL hides most data races, not logic races).
- General: **deterministic stress tests** with randomised scheduling, invariant assertions under load, model checkers (TLA+ / P) for protocols, fuzzing with sanitizers (ASan/TSan/UBSan).

**Senior point:** "Races that only appear under production load are almost always check-then-act, not raw data races. I make the *compound* operation atomic — a DB constraint, a CAS loop, a single transaction, or an idempotency key — rather than trying to lock harder."

### 17. Explain TCP congestion control and why it matters for latency
The sender must not overwhelm the network, and it has no direct signal — it infers congestion from loss and RTT.

1. **Slow start**: begin with a small congestion window (cwnd ≈ 10 segments), double each RTT until `ssthresh`. Exponential, so a new connection is *slow* for the first few RTTs.
2. **Congestion avoidance**: past `ssthresh`, grow linearly (additive increase).
3. **On loss**: multiplicative decrease. Classic Reno halves cwnd and fast-retransmits on 3 dup ACKs.
4. **Modern algorithms**: **CUBIC** (Linux default, cubic function of time — better on long fat networks), **BBR** (models bottleneck bandwidth and RTT rather than treating loss as the congestion signal — big wins on lossy links, though it can be aggressive against CUBIC traffic).

**Why you'd raise this in an interview:**
- **Slow start explains why short-lived connections are expensive.** A new TCP+TLS connection per request means you're always in slow start and paying handshake RTTs. This is the real argument for connection pooling, keep-alive, and HTTP/2 multiplexing — not just "fewer handshakes".
- **Bufferbloat**: oversized buffers keep queues full, so RTT balloons before any loss signals congestion. Fixed by AQM (CoDel, FQ-CoDel, PIE).
- **High-BDP links** (long distance, high bandwidth) need large windows: `bandwidth × RTT`. If `net.core.rmem_max` / window scaling caps you, you literally cannot fill the pipe.

### 18. mTLS and service-to-service authentication — how would you design it?
**mTLS**: both peers present certificates and both verify. Gives you encryption, mutual authentication, and (with SPIFFE-style certs) identity in the certificate itself.

Design:
- **Identity**: SPIFFE ID (`spiffe://trust-domain/ns/default/sa/checkout`) encoded in the cert SAN — workload identity, not IP or hostname, so it survives rescheduling.
- **Issuance**: short-lived certs (minutes–hours) auto-rotated by an agent. **cert-manager** in Kubernetes, or a SPIRE server+agent, or the mesh's own CA (Istio Citadel/istiod).
- **Rotation**: certs must rotate without dropping connections — agents watch the file and hot-reload (Envoy does this natively).
- **Trust bundle distribution**: the hard part at scale — how do workloads learn which CAs to trust, and how do you rotate a CA without an outage? Answer: bundle with multiple valid CAs, overlap the rotation window, then remove the old one. **This is the thing that causes outages**, so mention it.
- **Authorisation** is separate from authentication: mTLS proves *who*, policy (OPA/Rego, mesh AuthorizationPolicy, network policy) decides *may they*.

**Trade-off to name:** a service mesh gives you mTLS, retries, timeouts, circuit breaking and observability uniformly — at the cost of a sidecar per pod (~50–100 MB RAM, added latency per hop, another failure domain, and an upgrade treadmill). **Ambient/sidecarless meshes** (Istio ambient with ztunnel + waypoint proxies) and **eBPF-based** approaches (Cilium) exist specifically to cut that cost. If you only need mTLS and L4 policy, Cilium may beat a full mesh.

### 19. How does the kernel handle a file write, and what does `fsync` actually guarantee?
`write()` copies data into the **page cache** and returns — it does *not* touch disk. The kernel flushes dirty pages later (background flusher threads, `dirty_ratio`/`dirty_background_ratio`, or memory pressure). So a successful `write()` means "the kernel has it", not "the disk has it".

`fsync(fd)` forces dirty pages *and* the file's metadata to stable storage and waits for the device to acknowledge. `fdatasync` skips non-essential metadata (e.g. mtime) — cheaper.

**The subtlety that separates seniors:**
- **Filesystem metadata matters**: creating a new file and writing to it needs the *directory entry* durable too, so you must `fsync` the **directory** as well, or a crash can leave the file missing. This is why "atomic write" is `write tmp → fsync tmp → rename → fsync dir`.
- **Lying disks**: drives with write-back cache may ack before the platter/flash has it. `fsync` is only as honest as the device. Databases care enormously; that's why `O_DIRECT`, barriers/FUA and battery-backed caches exist.
- **Cost**: `fsync` per row = disaster. That's why databases use **group commit** and **WAL** — batch many transactions into one durable append.
- **Postgres `synchronous_commit`**, MySQL `innodb_flush_log_at_trx_commit`, Kafka `acks=all` + `min.insync.replicas` are all the same trade-off dial: durability vs latency vs throughput.

**Answer shape:** "`write` is not durable, `fsync` is, and even `fsync` depends on the device being honest. Any durability claim needs three things: the data, the metadata, and the directory entry — which is why the safe-write pattern is write-temp, fsync, rename, fsync-dir."

### 20. Linux namespaces and cgroups — how do they build a container?
A container is **not a VM**. It's a process with restricted visibility and limited resources.

**Namespaces** (isolation — *what you can see*): `pid` (own process tree, PID 1 inside), `net` (own interfaces, IP, routes, iptables, ports), `mnt` (own filesystem tree), `uts` (own hostname), `ipc` (own SysV IPC/POSIX msg queues), `user` (own UID/GID mapping — the security-critical one, and the basis of rootless containers), `cgroup`, `time` (newer).

**cgroups** (limiting — *what you can use*): v2 unified hierarchy with controllers for `cpu` (quota/period → the CFS throttling described above, plus `cpu.weight`), `memory` (`memory.max` → cgroup OOM kill, `memory.high` → throttling reclaim), `io` (blkio weights/throttles), `pids` (fork-bomb defence), `cpuset` (pin to cores/NUMA nodes).

**Plus**: `capabilities` (drop `CAP_SYS_ADMIN` etc. — root in a container is much less than root on the host), **seccomp** (syscall allowlist — Docker's default profile blocks ~40 syscalls), **LSM** (AppArmor/SELinux profiles), `chroot`/`pivot_root`, and `rlimits`.

**Senior points:**
- Kubernetes **requests → cgroup weights/cpu.shares; limits → hard caps (cpu.max, memory.max)**. That asymmetry is why CPU limits cause throttling but memory limits cause OOMKill: CPU is compressible, memory is not.
- **PID 1 semantics**: the container's init doesn't reap zombies or forward signals by default. That's why you need `tini`/`dumb-init`, or `shareProcessNamespace`, or Kubernetes' `SIGTERM → grace period → SIGKILL`. A container that ignores SIGTERM and always gets SIGKILLed after 30s is a symptom of exactly this.
- **Rootless/user namespaces** are the real containment upgrade; without them, a container escape means host root.

---

## 🔴 Scenario

### 21. Users in one region report the site is slow; your dashboards show healthy p99. What do you do?
**First, resolve the contradiction — don't assume either side is lying.**

1. **Believe the users and find the measurement gap.** Server-side p99 measures from when *your* server received the request. It excludes DNS, TCP, TLS, upload, CDN edge, and last-mile network. If the pain is in those, your dashboard is structurally blind.
2. **Segment the metric.** Break p99 by region, ISP, client version, endpoint, and by *edge* vs origin. A global p99 hides a 100%-bad segment: if 2% of your users are in that region and they're at 5s, your global p99 barely moves. **This is the single most common version of this scenario — say it explicitly.**
3. **Get client-side evidence.** RUM (real user monitoring), synthetic probes from that region (blackbox_exporter, CloudWatch Synthetics, k6 from a regional runner), or a traceroute/mtr from a host there.
4. **Check the region-specific path.** DNS (which records resolve there? did a TTL/record change? is a resolver caching stale?), CDN edge (which PoP? cache hit ratio? did the origin shield change?), the regional LB, cross-region backend calls (is the app in region A calling a DB in region B? that's an RTT per query, and it doubles when the link degrades).
5. **Check for a partial failure.** One unhealthy backend behind the LB, a saturated NAT gateway, conntrack table exhaustion, an MTU/MSS mismatch causing PMTUD black holes (symptom: small requests fine, large ones hang — very distinctive and often missed).
6. **Then look at what changed.** Deploy, config, infra, dependency, DNS, cert.

**How I'd answer:** "I'd start by assuming my metrics are measuring the wrong thing rather than that users are wrong. Server-side latency excludes DNS, TLS and the network path, and a global p99 averages away a region that's fully broken. So: segment by region and measure from inside that region with a synthetic probe, then compare edge-to-origin timing. Once I know *where* in the path the time goes, the fix is usually obvious — and if it turns out the metric was blind, that's a monitoring bug I'd fix in the same postmortem."

### 22. A process can't open more files: "too many open files". Diagnose and fix.
**Diagnose:**
```bash
cat /proc/<pid>/limits | grep "open files"        # the process's actual limits
ls /proc/<pid>/fd | wc -l                          # how many it's holding
cat /proc/sys/fs/file-nr                           # system-wide: allocated / free / max
lsof -p <pid> | awk '{print $5}' | sort | uniq -c  # what KIND of fd (sock vs reg vs pipe)
ss -s                                              # socket summary
ulimit -n                                          # shell limit
```

**Distinguish two limits**: the **per-process** `RLIMIT_NOFILE` (soft/hard) and the **system-wide** `fs.file-max`. They fail differently and are fixed differently.

**Most likely causes, in order:**
1. **Leaked sockets/connections** — a client not closing responses. In Go, failing to `defer resp.Body.Close()` leaks the connection; in Java, unclosed JDBC connections; in Python, `requests` without a session or context manager. The `lsof` breakdown tells you instantly: thousands of `IPv4`/`IPv6` sockets = connection leak.
2. **No connection pooling** — one connection per request, under load, with slow upstreams. Fix: pool + limits + timeouts.
3. **Too-low default** — containers often inherit 1024. Fix properly, not by blindly raising it.
4. **TIME_WAIT / CLOSE_WAIT accumulation.** `CLOSE_WAIT` piled up means **your** app isn't closing (a real bug); `TIME_WAIT` is normal and mostly harmless (fixed with connection reuse, *not* by disabling it).

**Fix correctly:**
```bash
# systemd unit
[Service]
LimitNOFILE=1048576

# Kubernetes (via container runtime / sysctls)
securityContext: { sysctls: [{name: fs.nr_open, value: "1048576"}] }   # unsafe sysctl, needs allowance
# or set the pod's rlimits through the runtime class / initContainer

# system-wide
sysctl -w fs.file-max=2097152      # /etc/sysctl.d/99-files.conf for persistence
```

**Senior answer:** "Raising `ulimit` treats the symptom. If `lsof` shows thousands of sockets to one downstream, the bug is a missing `Close()` or a missing pool, and raising the limit just delays the outage while making it bigger. I'd raise the limit enough to stop the bleeding, then fix the leak and add a metric on open-fd count with an alert at 70% of the limit — because this failure mode is otherwise invisible until it's fatal."

### 23. Your TLS certificates expire every 90 days. Design the system so this never causes an incident again.
1. **Automate issuance and renewal.** cert-manager with ACME/Let's Encrypt (HTTP-01 or DNS-01) for external; an internal CA (cert-manager + Vault, or step-ca) for service certs. DNS-01 is required for wildcards and for services not internet-exposed.
2. **Short lifetimes are a feature.** 24–90 hour internal certs mean a stolen cert is nearly worthless and rotation is continuously exercised. Renew at 2/3 of lifetime.
3. **Prove renewal works, don't assume.** Alert on `probe_ssl_earliest_cert_expiry - time() < 7d` for every endpoint, via blackbox probes from *outside*. Also alert on cert-manager's own health: `CertificateReady != True`, renewal failures, ACME order errors — because a silently failing issuer looks identical to "everything is fine" until it isn't.
4. **Cover the certs your probes can't see**: internal CA certs, mTLS bundles, webhook server certs, keystores in JARs, certs baked into images, trust anchors in OS images, and anything with a hardcoded expiry in a config file. Inventory them; every one needs an owner and an expiry metric.
5. **Make rotation safe.** Serve a **bundle containing old + new CA** during rotation so clients trusting either keep working; overlap the window; then remove the old. Never rotate a CA in one step — that's the classic self-inflicted outage.
6. **Test failure.** In staging, force a cert to expire and confirm the alert fires and the runbook works. An untested expiry alert is a hope, not a control.
7. **Blast radius**: if a cert does expire, the mitigation must be fast — a documented command, not a research project. And check what *depends* on it (webhooks, API servers, integrations) because expiry usually breaks the thing that would tell you.

**Answer shape:** "Automate with cert-manager, use short-lived certs so rotation is constantly exercised, monitor expiry from *outside* with blackbox probes AND monitor the issuer's own health, keep an inventory of the certs probes can't see, rotate CAs with an overlapping bundle rather than in one step, and rehearse the expiry in staging. The failure mode I'm designing against isn't 'we forgot to renew' — it's 'renewal was failing silently for 60 days and nobody could see it'."

### 24. Two services call each other and the whole system deadlocks under load. What's happening?
Classic **distributed deadlock via thread/connection-pool exhaustion**: A calls B while holding a worker; B calls A while holding a worker; at saturation every worker in A waits on B and every worker in B waits on A. Neither can make progress. No component is "down" — every health check may still pass.

**Diagnose:** thread dumps / goroutine dumps (`kill -QUIT` on Go writes them; `jstack` for JVM) — you'll see all workers blocked in the same downstream call. Pool metrics at max with zero throughput. Requests queued, latency at the timeout ceiling.

**Fix immediately:** break the cycle — shed load, disable one of the calls behind a feature flag, restart one side (buys time, doesn't fix it).

**Fix properly:**
1. **Remove the cycle** — the real answer. Refactor so the dependency graph is a DAG.
2. **Timeouts everywhere**, and they must be *nested-aware*: the caller's deadline must exceed the callee's total work, and the callee must respect the incoming deadline (gRPC/`context` propagation does this) so you don't do work nobody will read.
3. **Bulkheads**: separate pools per downstream so one dependency can't consume all workers.
4. **Circuit breakers**: fail fast when a dependency is unhealthy rather than queueing behind it.
5. **Load shedding / adaptive concurrency limits** (Netflix concurrency-limits, Envoy adaptive concurrency) so the system degrades instead of collapsing.
6. **Retry discipline**: retries multiply load — with 3 retries across 3 layers you can generate 27× the traffic exactly when the system is failing (**retry storm**). Add jitter, exponential backoff, a retry budget (e.g. ≤10% of traffic), and only retry idempotent operations at the layer that owns the semantics.

**Senior framing:** "This is a capacity-coupling failure, not a bug in either service. The system was stable until utilisation crossed a threshold, then it flipped to a stable *bad* equilibrium. The durable fixes are acyclic dependencies, propagated deadlines, and bulkheads — and the reason to add a retry budget is that retries are what turn a slowdown into a total outage."

---

## Red flags in this topic

| Saying this | Costs you because |
|---|---|
| "Just increase the ulimit" | Treats a leak as a capacity problem |
| "100% CPU means we need more CPU" | Might be throttling, GC, syscalls or spin — you didn't check |
| "Python is slow" | Without naming the GIL/CPU-vs-I/O distinction, it's a vibe not an analysis |
| "TCP is reliable so we don't need retries" | Reliability ≠ timeliness; and confusing them breaks timeout design |
| "A container is a lightweight VM" | Misses namespaces/cgroups entirely — fatal for DevOps/SRE roles |
| "mTLS means we're secure" | Authentication ≠ authorisation; and says nothing about CA rotation |
| Not distinguishing 502 from 504 | Signals you've never actually debugged through a proxy |

## Rapid recall

1. DNS → TCP → TLS → HTTP → app: know every hop and its latency contribution.
2. 401 = who are you; 403 = I know, and no. 502 = upstream refused/garbage; 504 = upstream too slow.
3. Idempotency is what makes retries safe → `Idempotency-Key`.
4. `epoll` is O(ready); `select` is O(n). Edge-triggered must drain to `EAGAIN`.
5. 100% CPU: first split us/sy/wa/st, then profile. Voluntary vs involuntary context switches tell you I/O-bound vs preempted.
6. CPU throttling shows as latency spikes with *normal* average CPU — check `container_cpu_cfs_throttled_periods_total`.
7. GIL blocks parallelism, not concurrency.
8. `write()` isn't durable; safe-write = tmp → fsync → rename → fsync(dir).
9. Container = namespaces (visibility) + cgroups (limits) + caps/seccomp/LSM (privilege). CPU is compressible, memory is not.
10. Check-then-act races aren't caught by `-race`. Make the compound operation atomic.
11. Distributed deadlock = pool exhaustion in a dependency cycle. Fix: DAG + deadlines + bulkheads + retry budget.
12. Cert renewal failures are *silent* — monitor the issuer, not just the expiry.

→ Next: [`02-DSA-and-Coding`](../02-DSA-and-Coding/README.md)
