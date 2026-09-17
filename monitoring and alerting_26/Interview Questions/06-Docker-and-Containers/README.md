# 06 · Docker & Containers

Every DevOps/SRE/Platform loop covers this. The senior-level differentiator is understanding **what a container actually is** (namespaces + cgroups + a filesystem view, not a VM), **image layering and caching**, and **build reproducibility & supply chain**.

*Versions referenced: Docker Engine 29.x, containerd 2.2.x, BuildKit (default builder), Buildx. Kubernetes 1.37 for orchestration context.*

---

## 🟢 Basic

### 1. What is a container, really? Not "a lightweight VM."
A container is **a regular process** on the host kernel, with three things applied:
1. **Namespaces** — isolate *what it can see*: PID (own process tree, becomes PID 1), mount (own filesystem tree), network (own NICs/IP/ports/routing table), UTS (own hostname), IPC (own semaphores/message queues), user (own UID/GID mapping), cgroup, and time namespace.
2. **cgroups** — limit *what it can use*: CPU, memory, I/O bandwidth, PIDs, etc.
3. **A root filesystem** — usually a layered union mount (overlayfs) from the image, plus `chroot`/`pivot_root` semantics.

Plus optional hardening: capabilities, seccomp, AppArmor/SELinux, LSMs, and read-only rootfs.

**The line that scores:** "A container isn't virtualised hardware — it's an isolated process. There's one kernel. That's why containers start in milliseconds and why a kernel vulnerability is a container escape, whereas a hypervisor vulnerability is a VM escape. It's also why you can't run a Windows container on a Linux kernel."

### 2. Namespaces in detail — what each isolates
| Namespace | Isolates | Observable symptom |
|---|---|---|
| **PID** | Process IDs | Container's main process is PID 1; `ps` inside shows only its tree. **PID 1 has special semantics** — see Q6 |
| **Mount (mnt)** | Mount points / filesystem tree | Each container has its own `/`; mounts don't propagate (unless a shared/rslave propagation is configured) |
| **Network (net)** | Interfaces, IPs, ports, routing, iptables, `/proc/net` | Two containers can both bind `:8080`; each has its own `lo` |
| **UTS** | Hostname, domain name | `hostname` is per-container |
| **IPC** | System V IPC, POSIX message queues | Shared memory segments are isolated (breaks some DB/Oracle setups → `--ipc=host`) |
| **User** | UID/GID mapping | Root inside (UID 0) can map to an unprivileged host UID — the key hardening feature |
| **Cgroup** | View of the cgroup hierarchy | Container can't see the host's cgroup tree |
| **Time** (newer) | Boot time / monotonic clock offsets | Rarely used |

**Debug use:** `ls -l /proc/<pid>/ns/` — two processes sharing an inode are in the same namespace. That's how you diagnose "why can this container see the host's processes?" (`--pid=host`) or "why does `kubectl exec` share the network?" (pod = shared netns).

### 3. cgroups v1 vs v2 — why does the version matter?
**v1**: separate hierarchies per controller (cpu, memory, blkio each their own tree). Flexible but inconsistent — controllers could disagree about membership, and combining limits was awkward.

**v2 (unified hierarchy)**: a single tree; all controllers attach to the same cgroup. Benefits: consistent membership, better delegation (safe subtree delegation to unprivileged users), **PSI (Pressure Stall Information)** for real pressure metrics, memory+IO control that actually interacts correctly, and `memory.high` (throttle before kill) alongside `memory.max`.

**Why you care in interviews and in production:**
- Kubernetes **requires cgroup v2 for several modern features** — full memory QoS (`memory.swap`, `memory.high`), in-place pod resize, and reliable PSI-based pressure signals. cgroup v1 support is being deprecated across the ecosystem; a 1.37 kubelet on cgroup v1 nodes is a real operational problem.
- **JVM/Go/Node container awareness** reads cgroup limits to size heaps and thread pools. The paths differ between v1 (`/sys/fs/cgroup/memory/memory.limit_in_bytes`) and v2 (`/sys/fs/cgroup/memory.max`) — older runtimes read the wrong file and see the *host's* memory → OOMKills. This is a genuine, frequently-hit bug.
- Check with `stat -fc %T /sys/fs/cgroup/` → `cgroup2fs` (v2) or `tmpfs` (v1).

**Key knobs:** `cpu.max` (quota per period — v2) / `cpu.cfs_quota_us` + `cpu.cfs_period_us` (v1), `memory.max`/`memory.high`, `pids.max`, `io.max`/`io.weight`. CPU throttling is measured at `cpu.stat` → `nr_throttled`, `throttled_usec`.

### 4. Image layers and the copy-on-write filesystem
An image is a **stack of read-only layers** plus metadata (config JSON: env, cmd, entrypoint, user, exposed ports). Each Dockerfile instruction that changes the filesystem creates a layer.

At runtime the container adds **one writable layer** on top. **overlayfs** merges them: `lowerdir` (read-only layers) + `upperdir` (writable) + `workdir`.

**Copy-on-write semantics:**
- **Read** a file → served from whichever lower layer has it.
- **Modify** → the file is **copied up** into the upper layer, then modified. Original untouched.
- **Delete** → a **whiteout** character device is created in the upper layer to mask the lower file. **The image size does not shrink** — deleting a 500 MB file added in an earlier layer saves nothing. This is *the* classic Dockerfile mistake:
  ```dockerfile
  RUN apt-get update && apt-get install -y bigpackage    # 500 MB layer
  RUN apt-get remove -y bigpackage                       # new layer with whiteouts; still 500 MB
  ```
  Fix: do it in **one `RUN`** with `&& \` continuation, and `rm -rf /var/lib/apt/lists/*` in the same instruction.
- **Write-heavy paths** (databases, logs) suffer copy-up latency → mount a volume to bypass the CoW layer entirely.

**Layer sharing:** identical layers (same digest) are stored **once** on disk and shared across images/containers. That's why basing everything on a common base image saves enormous space and pull time.

**Verification:** `docker history <image>` (layers + sizes + which instruction), `docker inspect` (config), `dive` (interactive per-layer file analysis — excellent for finding accidental bloat).

### 5. Dockerfile caching — the rules that decide your build time
BuildKit walks instructions in order and reuses a cached layer if:
- For **`COPY`/`ADD`**: the **checksum of the copied content** matches (not the timestamp).
- For **`RUN`**: the **command string** matches *exactly* (byte-for-byte).
- **And every preceding layer is also cached** — the cache is invalidated *forward*. Change instruction 3 and instructions 4–N all rebuild.

**Consequences — order instructions from least to most frequently changing:**
```dockerfile
# 1. Base + OS deps        (changes monthly)
FROM node:22-bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# 2. Dependency manifests ONLY   (changes weekly)
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force     # cached unless lockfile changes

# 3. Source code            (changes every commit)
COPY . .
RUN npm run build

USER node
CMD ["node", "dist/server.js"]
```
Copying `package.json` before the source means a code-only change **skips `npm ci`** — often a 5-minute saving per build. Same pattern for `go.mod`/`go.sum` (+ `go mod download`), `requirements.txt` (+ `pip install`), `pom.xml`, `Cargo.toml`.

**Cache busters to know:**
- `COPY . .` early → everything after rebuilds on every commit.
- `ARG` used before a `RUN` → changing the arg invalidates that layer (useful deliberately: `ARG CACHEBUST=1`).
- `apt-get update` alone in a layer → cached forever → you install stale/vulnerable packages. **Always pair update+install in one RUN.**
- Non-deterministic commands (`curl` a moving URL, `git clone` a branch, `date`) → same instruction, different output. Cache *correctness* lies to you.
- `--no-cache` when debugging; `--pull` to refresh base images.

**BuildKit cache mounts** (the senior move) — cache *across builds* without baking into a layer:
```dockerfile
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    go build -o /app .
```
Also `--mount=type=secret,id=aws,env=AWS_KEY` for credentials that never land in a layer, and `--mount=type=ssh` for private-repo access. **These are the correct answers to "how do I pass secrets at build time?"** — never `ARG SECRET` (it's in `docker history`).

### 6. `ENTRYPOINT` vs `CMD`, and the PID 1 problem
| Form | Behaviour |
|---|---|
| `CMD ["node","app.js"]` | Default command; **overridden entirely** by `docker run <img> <args>` |
| `ENTRYPOINT ["node","app.js"]` | Fixed executable; `docker run <img> <args>` **appends** args |
| Both | `CMD` supplies **default args** to `ENTRYPOINT` — the idiomatic combination |
| **Shell form** `CMD node app.js` | Runs as `/bin/sh -c "node app.js"` → **`sh` becomes PID 1**, your app is a child |
| **Exec form** `CMD ["node","app.js"]` | Your app **is** PID 1 |

**Use exec form (JSON array).** Shell form breaks signal handling.

**The PID 1 problem — very commonly asked:**
PID 1 in Linux has two special behaviours:
1. **Default signal handlers are not installed.** A normal process dies on SIGTERM by default; **PID 1 ignores signals it has no explicit handler for.** So `docker stop` sends SIGTERM, your app doesn't handle it, nothing happens, and after 10s Docker sends SIGKILL. You get hard kills every time → dropped requests, corrupted writes.
2. **Orphan reaping.** PID 1 must `wait()` on reparented zombies. A shell or your app that doesn't reap them accumulates zombies.

**Fixes:** `docker run --init` (tini, ~30 KB), `init: true` in compose, or an explicit init in Kubernetes (`shareProcessNamespace` doesn't fix it — you need an init process). Or handle SIGTERM in your app **and** use exec form. **A base image whose entrypoint is a shell script wrapper is a common source of both problems.**

**Graceful shutdown contract:** SIGTERM → stop accepting new work, drain in-flight requests (within `terminationGracePeriodSeconds`/`--stop-timeout`), close connections, flush, exit 0. If you need more than the grace period, you get SIGKILL.

### 7. Volumes vs bind mounts vs tmpfs
| | Backed by | Managed by | Use for |
|---|---|---|---|
| **Named volume** | Docker's storage area (`/var/lib/docker/volumes/<name>/_data`) | Docker (`docker volume create/ls/rm`) | Persistent data (DB files), when you don't care about host path |
| **Bind mount** | An arbitrary host path you specify | You | Local dev (mount source code), host config, log collection |
| **Anonymous volume** | Docker storage, random name | Docker, but orphan-prone | Auto-created by `VOLUME` in a Dockerfile — often a surprise leak |
| **tmpfs** | RAM | Kernel | Secrets, scratch space, high-I/O temp files. Gone on stop. Watch memory limits |

**Key gotchas:**
- **Bind mounts bypass copy-on-write** → much faster writes, but they **expose the host path** and the ownership/permission mismatch (host UID vs container UID) is a constant source of "permission denied".
- **`VOLUME` in a Dockerfile is usually a mistake**: it creates anonymous volumes that are hard to clean, and **any subsequent `RUN` that writes to that path is silently discarded**. Don't declare volumes in library images.
- On **macOS/Windows**, bind mounts cross a VM boundary → file I/O is dramatically slower (gRPC-FUSE/VirtioFS improved this a lot, but it's still the #1 cause of "why is my dev container slow"). Use named volumes for `node_modules`/`.venv`.
- Volume **propagation** (`:ro`, `:z`/`:Z` for SELinux relabel, `rslave`/`rshared` for mount propagation) matters for Docker-in-Docker and CSI drivers.

### 8. Multi-stage builds
```dockerfile
# ---- build stage ----
FROM golang:1.24-bookworm AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod go mod download
COPY . .
RUN --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w -X main.version=${VERSION}" -o /out/app .

# ---- runtime stage ----
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/app /app
COPY --chown=nonroot:nonroot config.yaml /etc/app/config.yaml
USER nonroot
EXPOSE 8080
ENTRYPOINT ["/app"]
```
**Why:** the final image contains only the binary + config. Go from ~1.2 GB (golang image) to **~10 MB**. Fewer CVEs, faster pulls, smaller attack surface, no shell for an attacker to use.

**Techniques:**
- `COPY --from=<stage>` and `COPY --from=builder --chown=...`.
- **Parallel stages** — BuildKit builds independent stages concurrently (great for building frontend + backend + docs then combining).
- `--target <stage>` to build only part of the graph (build the `test` stage in CI, the runtime stage for release).
- External stages: `COPY --from=ghcr.io/aquasecurity/trivy:latest /usr/local/bin/trivy /usr/local/bin/` — pull a tool from an image instead of installing it.
- `CGO_ENABLED=0` for a **statically linked** Go binary so `distroless/static` works (otherwise you need `distroless/base` with libc).

### 9. Base image choices — the trade-offs
| Base | Size | Shell? | Package manager | Notes |
|---|---|---|---|---|
| `ubuntu` / `debian` | 30–80 MB | ✅ | apt | Most compatible, most CVEs, needs patching cadence |
| `*-slim` | ~15–30 MB | ✅ | apt | Debian minus docs/locales; good default |
| `alpine` | ~5–8 MB | ✅ (ash) | apk | **musl libc, not glibc** — breaks some Python wheels, JVM DNS caching behaviour, anything expecting glibc. Smaller but not free |
| `distroless` | ~2–20 MB | ❌ | ❌ | Nothing but your app + runtime libs. `:nonroot` variant runs as UID 65532. **Hard to debug** — no shell, no `ls` |
| `scratch` | 0 MB | ❌ | ❌ | Empty. Static binaries only. No CA certs unless you copy them (`COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/`) |
| `chainguard/static`, `wolfi` | ~10–30 MB | varies | apk (wolfi) | glibc-based *and* minimal — arguably the best of both; actively patched, near-zero CVEs |
| UBI (Red Hat) | ~80–200 MB | ✅ | dnf | Supported/redistributable, enterprise compliance |

**Alpine's musl caveat is the specific thing to mention:** DNS resolution differences (no `nsswitch`, musl's resolver historically didn't honour search domains the same way), no prebuilt wheels for many Python C extensions (so `pip install` compiles → slow builds, needs build deps), and JVM/Go behaviours that assume glibc.

**Distroless debugging problem → the answer:** `kubectl debug <pod> --image=busybox --target=<container>` (ephemeral container sharing the target's namespaces), or build a parallel `debug` target stage with a shell and switch to it temporarily. Never ship the debug stage to production.

**Choosing — say this:** "I optimise for *patchability* before size. A 5 MB Alpine image with a 6-month-old base and 40 CVEs is worse than a 30 MB slim Debian image rebuilt nightly from a pinned digest. Size matters for cold-start and pull time; currency matters for security. I'd pin by digest, automate base-image updates (Renovate/Dependabot), and scan in CI with a policy that fails on new fixable criticals."

---

## 🔵 Advanced

### 10. `docker run` vs `containerd` vs `CRI-O` vs `runc` — the stack
```
kubectl ──► kubelet ──► CRI (gRPC) ──► containerd / CRI-O   ← "high-level runtime"
                                             │
                                        CRI/shim ──► runc    ← "low-level runtime" (OCI)
                                             │
                                     namespaces + cgroups + seccomp + caps + overlayfs
                                             │
                                          your process
```
- **OCI specs**: *image-spec* (what an image is), *runtime-spec* (`config.json` describing how to run it), *distribution-spec* (registry protocol). runc implements the runtime spec.
- **runc** is the low-level runtime: it does the actual `clone`/`unshare`, mounts, capability drops, seccomp filter application, then `exec`s your process and exits (the container is just a process; `containerd-shim` survives to hold stdio and the exit code).
- **containerd** is a daemon managing the lifecycle: image pull/unpack, snapshotting, container/snapshot management, networking hooks, and a CRI plugin so kubelet can talk to it.
- **CRI-O** is a Kubernetes-only alternative to containerd — implements CRI and nothing more, so a smaller surface.
- **dockershim** was the adapter letting kubelet speak to the Docker daemon. **Removed in Kubernetes 1.24.** This is why "Kubernetes is dropping Docker" was a thing — it dropped *dockershim*, not Docker images (which are OCI-compatible and work fine). Docker Engine can still run on nodes via containerd's CRI plugin.
- **Alternatives to runc** for isolation: **gVisor** (`runsc`, user-space kernel intercepting syscalls — strong isolation, syscall overhead and compatibility gaps), **Kata Containers** (lightweight VMs per pod — real hardware isolation, ~seconds of startup and more memory), **Firecracker** (microVM, powers Lambda/Fargate). **Know when to use which:** untrusted multi-tenant code → gVisor or Kata; your own trusted workloads → runc is fine.

**Interview-winning framing:** "The container is a process, the runtime stack is a set of layered APIs (CRI → shim → OCI runtime), and the isolation boundary is the *kernel*, not the runtime. That's why runtime choice is a security/isolation decision and image choice is a supply-chain decision, and they're independent."

### 11. Container networking — what happens on `docker run -p 8080:80`
1. Container gets a **veth pair**: one end (`eth0`) inside the container's network namespace, the other end attached to a **Linux bridge** (`docker0`, default subnet `172.17.0.0/16`).
2. Container gets an IP from that bridge's subnet; its default route points at the bridge.
3. Docker installs **iptables/nftables DNAT rules** in the `nat` table (`DOCKER` chain) mapping `host:8080` → `container_ip:80`, plus MASQUERADE for egress so the container's traffic appears to come from the host.
4. **Userland proxy** (`docker-proxy`) may also bind the host port — historically for hairpin/localhost access; often disabled for performance (`"userland-proxy": false`).

**Network modes:**
| Mode | Behaviour | Use |
|---|---|---|
| `bridge` (default) | Isolated netns + veth + NAT | Single-host multi-container |
| Custom bridge | Same + **automatic DNS by container name** + isolation | Always prefer over the default bridge — the default bridge has no DNS and `--link` legacy behaviour |
| `host` | Shares the host netns | Maximum performance (no NAT), no port isolation. Common for CNI agents, node exporters |
| `none` | Only loopback | Sandboxing, jobs that must not have network |
| `container:<id>` | Shares another container's netns | **This is exactly what a Kubernetes pod does** — the pause container holds the netns |
| `overlay` (Swarm) | VXLAN across hosts | Multi-host without a CNI |
| `macvlan` | Container gets a real MAC/L2 presence on the physical network | Legacy appliances needing a routable L2 identity |

**Performance points worth naming:**
- **NAT/conntrack is a bottleneck at scale.** The conntrack table (`nf_conntrack_max`) fills under high connection churn → `nf_conntrack: table full, dropping packet`. This is a *very* common production incident and the answer is: raise `nf_conntrack_max`, reduce TIME_WAIT churn, use `hostNetwork`/IPVS/eBPF-based datapaths (Cilium) that bypass conntrack, or use a service mesh sidecar carefully.
- **MTU mismatches** between the overlay and the underlay cause silent blackholes for large packets (TLS handshakes work, big downloads hang). Set the CNI MTU below the underlay MTU (VXLAN overhead = 50 bytes; typical underlay 1500 → overlay 1450). **Symptom to recognise: small requests fine, large payloads time out, `ping` works but `curl` hangs.** Diagnose with `ping -M do -s 1400`.
- **eBPF datapaths** (Cilium) replace iptables with BPF programs → O(1) lookup instead of O(n) rule scan, no conntrack for service resolution, and much better performance at 1000s of services. In large clusters, iptables rule count itself becomes a latency problem.

### 12. Container security hardening — the checklist that scores
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 10001
  runAsGroup: 10001
  readOnlyRootFilesystem: true
  allowPrivilegeEscalation: false
  capabilities:
    drop: ["ALL"]
    add: ["NET_BIND_SERVICE"]      # only if you must bind <1024
  seccompProfile:
    type: RuntimeDefault
  # privileged: false  (never true unless it's a CNI/storage agent)
```
Layers of defence:
1. **Don't run as root.** Most CVE exploitation gets easier as UID 0. Use `USER` in the Dockerfile *and* enforce with `runAsNonRoot` / a `Restricted` Pod Security Standard.
2. **Drop all capabilities.** Containers get ~14 by default (`CHOWN`, `NET_RAW`, `SETUID`…). `NET_RAW` allows packet spoofing/ARP attacks inside the network — dropping it is cheap and valuable. Add back only what's needed.
3. **Read-only root filesystem.** Forces you to declare writable paths explicitly (`emptyDir` for `/tmp`), which prevents an attacker writing a binary or webshell. Catches a surprising number of "the app writes to its own install dir" bugs.
4. **seccomp** filters syscalls (RuntimeDefault blocks ~40+ dangerous ones like `keyctl`, `kexec_load`, `bpf`, `mount`). Custom profiles reduce further but need maintenance.
5. **AppArmor/SELinux** MAC policies — mandatory access control that survives a root escape.
6. **User namespaces** (`userns-remap` / **User Namespaces GA in Kubernetes 1.36+**): map container UID 0 to an unprivileged host UID (e.g. 100000). **The single most effective escape mitigation** — a container root who is host UID 165536 can't `chown /etc/shadow`. Historically hard (volume ownership, subuid ranges, no hostPath); now supported per-pod with `hostUsers: false`. Worth naming as a 1.36/1.37-era capability.
7. **No `privileged: true`, no `hostPID`/`hostNetwork`/`hostPath`** except for infrastructure agents with a documented reason. `privileged` + `hostPath: /` = root on the node = cluster compromise.
8. **Image supply chain**: pin by **digest** (tags are mutable — `latest` can silently change under you), scan (Trivy/Grype/Scout), sign & verify (cosign/Notation + Sigstore, or a policy controller like Kyverno/Connaisseur), and prefer minimal, actively patched bases.
9. **Secrets**: never in env vars if avoidable (`docker inspect` shows them; they leak into child processes, crash dumps and `/proc/<pid>/environ`). Use mounted files (tmpfs), Vault Agent, or the External Secrets Operator. **Build-time secrets via BuildKit `--mount=type=secret`**, never `ARG`.
10. **Runtime detection**: Falco/Tetragon for syscall-level anomaly detection (a shell spawned in a Java container, a write to `/etc`, an outbound connection to a rare IP).

### 13. Image supply chain, SBOM, signing, attestation
- **SBOM** (SPDX or CycloneDX): `syft <image> -o cyclonedx-json`, `docker sbom`, or Buildx's built-in `--sbom=true`. Lets you answer "are we affected by CVE-2024-XXXX?" in minutes instead of days — **that's the real business value of an SBOM, and saying it beats reciting the acronym.**
- **Signing**: `cosign sign --key ... <image>@<digest>` writes the signature to the registry as an OCI artifact. Verify at admission with **Kyverno**/Connaisseur/policy-controller. **Keyless signing** via Sigstore Fulcio + OIDC identity + Rekor transparency log removes key management (the hardest part) — the signature binds to the *identity* (your CI's workload identity) rather than a long-lived secret.
- **Provenance/SLSA**: Buildx `--provenance=true` produces an attestation describing the builder, source commit, build parameters. `docker buildx imagetools inspect` shows them. Answers "where did this artifact come from, exactly?"
- **Reproducible builds**: `SOURCE_DATE_EPOCH` to fix timestamps, sort file order, avoid `ARG`-injected build times, pin base digests, pin package versions. Then two builds of the same commit produce the same digest — which makes tampering detectable and caching globally effective. BuildKit supports this; it's an increasingly common interview topic.
- **Registry hygiene**: immutable tags in production registries, garbage collection, retention policy, per-environment promotion (**promote the digest, never rebuild per environment** — rebuilding breaks the "the artifact you tested is the artifact you shipped" guarantee).
- **Scanning reality check:** "A scanner report is not a security posture. What matters is: fixable + reachable + exploitable-in-context. Most images have hundreds of CVEs that aren't reachable because the vulnerable code path isn't exercised or the package is only in the build stage. I triage by *reachability* (VEX statements help) and set policy on **new** criticals rather than blocking on the backlog — otherwise teams route around the gate."

### 14. Docker Compose — the parts beyond `up -d`
```yaml
name: myapp                                  # explicit project name → stable network/volume names
services:
  api:
    build: { context: ., target: runtime }    # multi-stage target selection
    image: registry.internal/api:${TAG:-dev}
    init: true                                # proper PID 1 → signal handling + zombie reaping
    depends_on:
      db: { condition: service_healthy }      # NOT just "started" — the difference matters
      redis: { condition: service_started }
    environment:
      DATABASE_URL: postgres://app:app@db:5432/app
    env_file: [.env]
    healthcheck:
      test: ["CMD", "/api", "--health"]        # exec form: no shell needed
      interval: 10s
      timeout: 3s
      retries: 5
      start_period: 30s                        # grace for slow startup, doesn't count as failures
    restart: unless-stopped
    read_only: true
    tmpfs: [/tmp]
    security_opt: ["no-new-privileges:true"]
    cap_drop: [ALL]
    deploy:
      resources:
        limits:   { cpus: "1.0", memory: 512M }
        reservations: { cpus: "0.25", memory: 128M }
    develop:
      watch:                                   # Compose Watch: hot reload
        - action: sync+restart
          path: ./src
          target: /app/src
    volumes:
      - ./src:/app/src:cached
      - node_modules:/app/node_modules         # named volume: keeps host node_modules out
    networks: [backend]
    ports: ["8080:8080"]                        # prefer "127.0.0.1:8080:8080" on shared machines
  db:
    image: postgres:17
    environment: { POSTGRES_PASSWORD_FILE: /run/secrets/db_pw }   # file, not plaintext env
    secrets: [db_pw]
    volumes: ["pgdata:/var/lib/postgresql/data"]
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U app"]
      interval: 5s
      retries: 10
    networks: [backend]
secrets:
  db_pw: { file: ./secrets/db_pw.txt }          # or external: true
volumes: { pgdata: {}, node_modules: {} }
networks:
  backend: {}
  # frontend: { internal: true }                # no external egress — good for a DB tier
```
**Things that reveal experience:**
- **`depends_on` with `condition: service_healthy`** — plain `depends_on` only orders *startup*, not readiness. Without a healthcheck, your app connects before Postgres is accepting connections and crash-loops. **This is the single most common Compose bug.**
- **`start_period`** so slow-starting services don't get marked unhealthy and restarted.
- **Named volumes for dependency dirs** (`node_modules`, `.venv`) — bind-mounting them from the host injects host-platform binaries (macOS ARM) into a Linux container.
- **Secrets as files**, not env vars.
- **`internal: true` networks** for tiers that shouldn't reach the internet.
- **`docker compose watch`** for hot reload without a rebuild loop.
- **Overrides**: `docker-compose.override.yml` (auto-merged, dev-only) and `-f a.yml -f b.yml` for layering. Keep the base file environment-agnostic.
- Compose is **not an orchestrator**: no scheduling, no self-healing across hosts, no rolling updates in any real sense. It's for dev and single-host deployments — and being clear about that boundary is part of the answer.

### 15. Docker/BuildKit performance tuning for CI
- **Registry cache**: `--cache-from type=registry,ref=…:buildcache --cache-to type=registry,mode=max,ref=…:buildcache` — shares cache across runners (essential for ephemeral CI). `mode=max` caches intermediate layers, not just final ones.
- **GitHub Actions cache**: `--cache-to type=gha` / `--cache-from type=gha`.
- **`--mount=type=cache`** for language package caches (npm/go/pip/cargo/maven) — survives across builds on the same runner.
- **Parallel stage execution** — BuildKit builds independent stages concurrently; structure the Dockerfile so frontend/backend/test stages don't depend on each other.
- **Multi-platform** with `--platform linux/amd64,linux/arm64` via QEMU (slow) or **native cross-builders** (fast; set up a builder with one node per architecture). Apple Silicon teams hit this constantly.
- **`--squash`** is generally *not* what you want (loses layer sharing). Multi-stage achieves the size win properly.
- **BuildKit inline cache** (`--build-arg BUILDKIT_INLINE_CACHE=1`) for older setups.
- **Measure first**: `docker buildx build --progress=plain` shows per-step timing. Don't guess.

---

## 🔴 Scenario

### 16. "Our production image is 1.8 GB and takes 4 minutes to pull. Fix it."
**Diagnose before cutting** — don't guess:
```bash
docker history --no-trunc --human <image>     # which instruction added how much
docker inspect <image>                        # layers, config
dive <image>                                  # per-layer file tree, "wasted space" view
docker buildx build --progress=plain .        # per-step timing
```
**The usual culprits, in order of impact:**
1. **Build toolchain in the final image** (compilers, `node_modules` with devDeps, Maven repos, `.git`) → **multi-stage build**. Typically 1.8 GB → 100 MB.
2. **Base image too fat** (`ubuntu` → `-slim`, or `openjdk:17` (500 MB) → `eclipse-temurin:17-jre-alpine`/`-jammy` (180 MB) → or `jlink` a custom runtime (~50 MB)).
3. **`apt-get update` in a separate layer, or `--no-install-recommends` missing** → pulls hundreds of MB of suggested packages. Always `--no-install-recommends` and `rm -rf /var/lib/apt/lists/*` **in the same RUN**.
4. **Delete-after-install across layers** (the CoW whiteout problem from Q4) → merge into one `RUN`.
5. **Language caches baked in** (`~/.cache/pip`, `/go/pkg/mod`, `~/.m2`) → BuildKit cache mounts, or `--no-cache`/`npm cache clean` in the same layer.
6. **`.dockerignore` missing** → `COPY . .` ships `node_modules`, `.git`, test fixtures, local build output. A `.dockerignore` is also a **cache-stability** fix and a secret-leak prevention.
7. **Static Go/Rust binary → `distroless/static` or `scratch`** → 10 MB.

**And the pull-time half of the question** (size isn't the only factor):
- **Lazy pulling**: Stargz/eSOCI/SOCI snapshotter pulls only the blocks needed to start → cold start drops from minutes to seconds even for large images. Worth naming as the modern answer for serverless/scale-from-zero.
- **Layer locality**: put a registry mirror/cache in each region (ECR pull-through cache, Harbor replication, Dragonfly for P2P distribution). A 100-node rollout from one registry is a bandwidth problem, not a size problem.
- **Shared base layers**: if all services share one base, only the top layer is pulled. Standardising the base is a platform-team win with a bigger effect than any individual Dockerfile tweak.
- **Pre-pull / warm nodes**: a DaemonSet or node-image pre-puller for common bases; `imagePullPolicy: IfNotPresent` with digest pinning.

**The trade-off statement that closes it:** "I wouldn't optimise for size alone. `scratch` images can't be debugged and can't run `curl` for a healthcheck — so I'd choose distroless-with-`nonroot` plus an ephemeral-debug workflow, and measure cold-start time, not megabytes. The metric I actually care about is time-to-first-request on a cold node."

### 17. "A container exits immediately with code 137 / 143 / 1 / 0 — how do you tell them apart?"
Exit code = **128 + signal number** when killed by a signal.

| Code | Meaning | Likely cause | First check |
|---|---|---|---|
| **137** | 128+9 = SIGKILL | **OOMKilled** (most common), or liveness probe failure → kill, or grace period expired after SIGTERM was ignored | `kubectl describe pod` → `Last State: Terminated, Reason: OOMKilled`; `container_memory_working_set_bytes` vs limit; **cgroup PSI** (`memory.pressure`); for JVM/Go, whether the runtime read the container limit |
| **143** | 128+15 = SIGTERM | Normal shutdown, or liveness/startup probe killed it, or a rolling update | Expected during deploys. Unexpected → probe misconfiguration, node drain, eviction |
| **1** | App error | Unhandled exception, config missing, connection refused at startup | App logs (`kubectl logs --previous`) |
| **0** | Clean exit | **But the container was supposed to run forever** → the entrypoint script finished (a backgrounded process, `exec` missing) or the app treats "no work" as "done" | Entry form of `ENTRYPOINT`; is the app daemonising? |
| **126** | Not executable | Missing exec bit, wrong architecture binary, script with no shebang | `ls -l`, `file <binary>`, build platform |
| **127** | Command not found | Wrong `ENTRYPOINT`/`CMD`, missing binary, wrong `PATH`, shell-form command in a distroless image | `docker run --entrypoint sh <img>` (if it has a shell), else build a debug stage |
| **139** | 128+11 = SIGSEGV | Native crash — CGO, JNI, a bad shared library, or memory corruption | Core dump, `dmesg`, native stack trace |
| **134** | 128+6 = SIGABRT | `assert`/abort — often a JVM crash, glibc heap corruption, or double-free | hs_err_pid log, `dmesg` |

**The distinguishing move for 137 — is it OOM or a probe kill?**
```bash
kubectl get pod X -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}'
# OOMKilled  → memory.  Error/Completed → something else sent SIGKILL
kubectl describe node   # look for MemoryPressure, evictions
dmesg -T | grep -i -E 'oom|killed process'    # on the node: the kernel's own OOM record
```
**Also know:** the container's *cgroup* OOM is separate from the *node's* OOM. Node-level memory pressure triggers **kubelet eviction** (pod gets evicted with a reason, not exit 137). And `memory.max` kills at the cgroup limit even when the node has plenty of free memory — a limit too low is far more common than a leak.

**And the JVM/Go/Node container-awareness angle** (ties to topic 05): the runtime sized its heap/pool from the *node's* memory rather than the limit → OOMKill with a healthy-looking heap dump. Fix: `-XX:MaxRAMPercentage`, `GOMEMLIMIT`, `--max-old-space-size`, and set memory requests == limits.

### 18. "The same Dockerfile builds fine locally but fails in CI." Enumerate causes.
1. **Stale local cache.** Your machine has layers cached from weeks ago; CI starts cold or has a different cache. `--no-cache` locally to reproduce. **Also the reverse**: CI reuses a poisoned cache — `--pull` and cache-bust.
2. **Architecture mismatch.** Local Apple Silicon (arm64), CI amd64. Native builds diverge; QEMU emulation exposes different failures (`exec format error`, `SIGILL`, wildly slow builds, packages with no arm64 wheel). Fix: `--platform linux/amd64` explicitly in both, or use cross-builders.
3. **Different Docker/BuildKit version.** Feature flags, `RUN --mount` syntax support, cache behaviour, default builder (`DOCKER_BUILDKIT=1`). Pin the builder version in CI.
4. **`.dockerignore` not applied / different build context.** CI may check out into a different path, include untracked files, or use a shallow clone (`.git` missing → a `git describe` version step fails). **A build that depends on `.git` fails in shallow clones** — pass the version as a build arg from CI metadata instead.
5. **Secrets present locally, absent in CI** (or vice versa): `~/.docker/config.json`, AWS creds, SSH agent, npm tokens. BuildKit secret mounts should be explicit; a build that silently works because your laptop has credentials is a broken build.
6. **Non-determinism**: `apt-get install <pkg>` without a version, `pip install <pkg>` without a pin, `npm install` instead of `npm ci`, `curl` of a moving tag, `git clone` of a branch, `date`/`timestamp` baked in, `ARG CACHEBUST`.
7. **Network**: CI has no internet egress (or a proxy), registry auth differs, DNS differs, an internal mirror serves different package versions, rate limits (Docker Hub anonymous pulls are throttled — CI runners sharing an IP get `429`).
8. **Resource limits**: CI runners have less memory/disk than your laptop → build OOMs (a common cause of "worked locally" for large Node/Java/Rust builds), or `/var/lib/docker` fills up. Check `df -h` and the runner's memory.
9. **Filesystem differences**: case-sensitive (Linux CI) vs case-insensitive (macOS local) → `import Foo` works locally, fails in CI. Symlink handling, file permissions/ownership, and executable bits lost in git (`core.fileMode`).
10. **Timing/flakiness**: healthchecks with too-short `start_period`, tests that need a dependency that isn't ready, port collisions on shared runners.

**The senior closer:** "My general rule is that a build must be **hermetic**: pinned base digest, locked dependency manifests, no reliance on ambient credentials, no dependence on `.git`, explicit platform, and a reproducible timestamp. Then 'works on my machine' stops being a category of bug. I'd add a CI job that builds with `--no-cache --pull` on a schedule — it finds non-determinism before your release does."

### 19. "We need to run untrusted user-submitted code (a CI system / a notebook service). Design the isolation."
**Threat model first:** the adversary is inside the container and will attempt (a) container escape → node root, (b) network egress → internal services/cloud metadata, (c) resource exhaustion → noisy neighbour, (d) data exfiltration, (e) cryptocurrency mining / persistence.

**Layered design:**
1. **Stronger isolation than runc.** For genuinely untrusted code, **gVisor (runsc)** — a user-space kernel that intercepts syscalls, so the guest never talks to the host kernel directly; or **Kata/Firecracker microVMs** — hardware virtualisation per sandbox. **This is the central decision.** runc + hardening is defence-in-depth for *your* code; it is not sufficient for arbitrary adversarial code, because any kernel LPE becomes an escape. RuntimeClass in Kubernetes lets you schedule untrusted pods to gVisor/Kata nodes. Name the cost: gVisor adds syscall overhead and breaks some workloads (no full POSIX, some ioctls); Kata adds ~seconds of startup and per-sandbox memory overhead.
2. **Drop everything:** `runAsNonRoot`, `drop: [ALL]`, `readOnlyRootFilesystem`, `allowPrivilegeEscalation: false`, seccomp strict, no `hostPath`/`hostNetwork`/`hostPID`/`privileged`, **user namespaces enabled** (`hostUsers: false`) so container root ≠ host root.
3. **Network egress control — the highest-value control after isolation.** Default-deny egress NetworkPolicy; block the **cloud metadata endpoint (169.254.169.254)** explicitly (credential theft is the #1 real-world payoff); block RFC1918/internal ranges; allow only an egress proxy with a domain allowlist. **Also disable IMDSv1 / enforce IMDSv2 (hop-limit 1)** on the nodes so even a network escape can't grab node credentials — and give the sandbox nodes an IAM role with *no* permissions.
4. **Resource limits**: CPU, memory, **`pids.max`** (fork bombs), disk quota (a writable emptyDir with `sizeLimit`), and **runtime limits** (kill after N minutes). Also limit open files and bandwidth. Noisy-neighbour isolation → dedicated node pools with taints so untrusted workloads never share a node with your control plane or databases.
5. **Ephemeral, single-use sandboxes.** Fresh VM/container per job, destroyed after. No persistent state to poison, no reuse across tenants. Warm pools for startup latency — but pool per-tenant only if you must, and never across tenants.
6. **Filesystem**: read-only root + a small writable tmpfs; no host mounts; artifacts uploaded explicitly to object storage with scoped, short-lived credentials (not node credentials).
7. **Secrets**: the sandbox gets *job-scoped* credentials minted at runtime (OIDC federation → short-lived cloud role), never long-lived shared keys.
8. **Detection**: Falco/Tetragon syscall monitoring for escape attempts (mount, ptrace, raw socket creation, writes to `/proc/sys`), egress anomaly detection, and per-job audit logs shipped off-box (assume the sandbox is compromised).
9. **Assume breach.** Design so that a full sandbox compromise yields: no credentials, no network reach, no persistence, no other tenants' data, and a loud alarm. **Say this explicitly — it's the maturity marker.**

**Reference points:** GitHub Actions runners (Firecracker microVMs), Gitpod/Coder (gVisor or VMs), Jupyter Hub (KubeSpawner + gVisor RuntimeClass is a common pattern), AWS Lambda (Firecracker), Replit.

---

## Red flags

| Saying / doing this | Costs you |
|---|---|
| "A container is a lightweight VM" | Signals you don't know the mechanism |
| `ARG SECRET=...` for build-time credentials | Visible in `docker history`; use BuildKit secret mounts |
| `apt-get update` in its own layer | Stale packages + cache correctness lie |
| `RUN apt-get install` then `RUN apt-get remove` | CoW whiteouts: zero size savings |
| No `.dockerignore` | Bloated context, cache thrash, secret leaks |
| Shell-form `CMD` for a long-running service | Broken signals → SIGKILL every deploy |
| No `--init` / no SIGTERM handling | Hard kills, dropped requests, zombie accumulation |
| `depends_on` without a healthcheck condition | Crash-loop on startup ordering |
| `latest` tag in production | Non-reproducible, silently mutable |
| "We scan with Trivy so we're secure" | Volume ≠ posture; no triage/reachability story |
| runc for untrusted user code | Insufficient isolation for the threat model |
| Forgetting conntrack/MTU in networking answers | Misses the two most common real incidents |
| VOLUME in a library Dockerfile | Orphaned anonymous volumes, silently discarded writes |

## Rapid recall

1. Container = namespaces (visibility) + cgroups (limits) + layered rootfs + caps/seccomp/LSM. One kernel.
2. cgroup v2 = unified hierarchy, PSI, memory.high; required for modern K8s memory QoS and in-place resize.
3. Layer deletion doesn't shrink the image (whiteouts) → single `RUN`.
4. Cache invalidates forward; order instructions least→most frequently changing; copy manifests before source.
5. BuildKit: `--mount=type=cache` for deps, `type=secret` for creds, `type=ssh` for private repos.
6. Exec form ENTRYPOINT; PID 1 ignores unhandled signals and must reap zombies → `--init`.
7. Multi-stage: 1.8 GB → 10 MB; `--target` for CI; `COPY --from=<image>` for tools.
8. Alpine = musl (DNS/wheel caveats); distroless = no shell (use `kubectl debug` ephemeral containers).
9. Stack: kubelet → CRI → containerd/CRI-O → shim → runc (OCI). dockershim gone in 1.24. gVisor/Kata for stronger isolation.
10. `-p` = veth + bridge + iptables DNAT. Conntrack table full and MTU mismatch are the classic incidents.
11. Hardening: nonroot, drop ALL caps, readOnlyRootFilesystem, seccomp RuntimeDefault, user namespaces, no privileged/hostPath.
12. Supply chain: pin by digest, SBOM, cosign keyless signing, provenance, promote digests not rebuilds.
13. 137 = SIGKILL (usually OOM); 143 = SIGTERM; 127 = not found; 126 = not executable. Check `lastState.terminated.reason`.
14. Hermetic builds: pinned digest, locked deps, no `.git` dependency, explicit platform, no ambient creds.

→ Next: [`07-Kubernetes`](../07-Kubernetes/README.md)
