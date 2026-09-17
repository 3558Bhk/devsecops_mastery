# 02 · DSA & Coding

SDE III coding rounds differ from SDE II in three ways: the problems are less about tricks and more about **clean decomposition**, you're expected to **state complexity before you code**, and you're judged on **how you handle the follow-up**. Many infra roles (DevOps/SRE/Platform) replace LeetCode with **practical coding** — parsers, CLI tools, concurrency, API clients — so both are covered here.

---

## 🟢 Basic — the patterns you must recognise instantly

### The pattern → complexity table

| Pattern | Recognise when | Typical complexity |
|---|---|---|
| **Two pointers** | Sorted array, pair/triplet sum, remove duplicates, palindrome | O(n) time, O(1) space |
| **Sliding window** | Contiguous subarray/substring with a constraint ("longest without repeats") | O(n) |
| **Prefix sums** (+ hash map) | Subarray sum equals K, range sums, "count subarrays" | O(n) |
| **Binary search** | Sorted/monotonic, "minimum X such that…", search in rotated array | O(log n) |
| **Fast/slow pointers** | Linked list cycle, middle node, kth from end | O(n), O(1) |
| **Stack** | Next greater element, valid parentheses, monotonic sequences, expression eval | O(n) |
| **Heap / priority queue** | Top-K, Kth largest, merge K lists, running median | O(n log k) |
| **Hash map/set** | Deduplication, frequency, two-sum, grouping | O(n) |
| **BFS** | Shortest path in unweighted graph/grid, level-order | O(V+E) |
| **DFS / backtracking** | All paths, permutations/combinations, constraint satisfaction, connected components | O(V+E) or exponential (say so!) |
| **Union-Find** | Connected components, cycle detection, "number of islands" over a stream | ~O(α(n)) per op |
| **Topological sort** | Dependency ordering, build systems, course schedule | O(V+E) |
| **Trie** | Prefix search, autocomplete, word dictionary | O(L) per word |
| **Interval / sweep line** | Merge intervals, meeting rooms, max overlapping | O(n log n) |
| **DP** | Optimal substructure + overlapping subproblems | O(n²) or O(n·W) |
| **Bit manipulation** | Single number, counting bits, masks, XOR tricks | O(1)/O(n) |

**How to use this in an interview:** in the first 60 seconds, say out loud *"This looks like a sliding-window problem because we want the longest contiguous substring satisfying a constraint — that gives O(n) instead of O(n²) brute force."* Naming the pattern before coding is the single clearest senior signal in a coding round.

### Complexity you should have memorised

| Structure | Access | Search | Insert | Delete | Notes |
|---|---|---|---|---|---|
| Array | O(1) | O(n) | O(n) | O(n) | cache-friendly; append amortised O(1) |
| Sorted array | O(1) | **O(log n)** | O(n) | O(n) | binary search, bad writes |
| Linked list | O(n) | O(n) | O(1)* | O(1)* | *given the node; no cache locality |
| Hash map | — | **O(1) avg**, O(n) worst | O(1) avg | O(1) avg | worst case = collisions; load factor |
| BST (unbalanced) | O(h) | O(h) | O(h) | O(h) | h = O(n) degenerate |
| AVL / Red-Black | O(log n) | O(log n) | O(log n) | O(log n) | self-balancing |
| B-tree / B+tree | O(log n) | O(log n) | O(log n) | O(log n) | **disk-optimised**: high fan-out, few seeks; B+tree stores data only in leaves + leaf links → great range scans. This is why databases use it. |
| Heap | O(1) peek | O(n) | O(log n) | O(log n) | priority queue |
| Trie | O(L) | O(L) | O(L) | O(L) | L = key length; memory-hungry |
| Skip list | O(log n) | O(log n) | O(log n) | O(log n) | probabilistic; Redis sorted sets, some memtables |
| LSM tree | O(1) write | O(n) worst read | O(1) | — | write-optimised: memtable → SSTables → compaction. RocksDB/Cassandra/ScyllaDB. Trade: read amplification, compaction CPU. |

**Be able to contrast B+tree vs LSM out loud** — it comes up in DB, infra and system-design interviews constantly. B+tree: fast predictable reads, write amplification from page rewrites, needs locking. LSM: fast sequential writes, cheap ingestion, but read amplification (check memtable + multiple levels, mitigated by bloom filters) and compaction storms. Choose B+tree for read-heavy OLTP, LSM for write-heavy/time-series/wide-column.

### Amortised analysis — say this correctly
Dynamic array append is O(1) **amortised**: occasional O(n) resize, but doubling means total work for n appends is ~2n, so average is O(1). Same reasoning for hash-map rehashing, union-find with path compression + union by rank (O(α(n)), inverse Ackermann — effectively constant), and splay trees.

If a problem has "occasional expensive operation, cheap most of the time", say **amortised** — and explain why. Interviewers listen for that word.

---

## 🔵 Advanced

### 1. Two Sum — and why the follow-up matters
```python
def two_sum(nums: list[int], target: int) -> list[int]:
    seen: dict[int, int] = {}                 # value -> index
    for i, v in enumerate(nums):
        if (need := target - v) in seen:
            return [seen[need], i]
        seen[v] = i
    return []
```
O(n) time, O(n) space. The O(n²) nested loop is the brute force — **state it, then discard it**.

**Follow-ups you should pre-empt:**
- *Sorted array?* → two pointers, O(1) space.
- *Return all pairs, no duplicates?* → sort + two pointers + skip duplicates.
- *Three-sum?* → sort, fix one, two-sum the rest: O(n²). Hash approaches are harder to dedupe.
- *Stream / can't hold in memory?* → external sort or bloom-filter pre-pass.
- *Concurrency?* → the map is now shared; partition the array and merge, or use a concurrent map — and say the hash map isn't the bottleneck, the lock is.

### 2. Sliding window — the template that solves a family
```python
def length_of_longest_substring(s: str) -> int:
    last: dict[str, int] = {}
    left = best = 0
    for right, ch in enumerate(s):
        if ch in last and last[ch] >= left:   # only shrink if the dup is INSIDE the window
            left = last[ch] + 1
        last[ch] = right
        best = max(best, right - left + 1)
    return best
```
O(n) — each index visited at most twice.

**The generic shape** (memorise it; it covers "longest/shortest substring satisfying P", min-window-substring, max-consecutive-ones-III):
```python
left = 0
for right in range(n):
    add(arr[right])                    # grow window
    while not valid():                 # shrink until constraint restored
        remove(arr[left]); left += 1
    best = max(best, right - left + 1) # for "longest valid"
```
For **"shortest valid"**, invert: shrink *while valid* and record inside the loop.

### 3. Binary search — the bug-free template
```python
def lower_bound(a: list[int], x: int) -> int:
    """First index i where a[i] >= x. Returns len(a) if none."""
    lo, hi = 0, len(a)                 # half-open [lo, hi)
    while lo < hi:
        mid = lo + (hi - lo) // 2      # never (lo+hi)//2 in languages with fixed ints
        if a[mid] < x:
            lo = mid + 1
        else:
            hi = mid                   # mid stays a candidate
    return lo
```
**Why this template:** half-open interval, `lo < hi` termination, invariant "`lo` is the answer boundary". It never infinite-loops and needs no post-hoc edge-case handling.

**The senior move — "binary search on the answer":** when a problem asks for a *minimum/maximum value satisfying a monotonic predicate* (min days to ship packages, min eating speed, max min-distance in aggressive cows, min servers to meet latency SLO), binary-search the answer space and write a cheap `feasible(x)` check. Turn an optimisation problem into O(log(max) · check). Say the word **monotonic** — that's the justification.

```python
def min_eating_speed(piles: list[int], h: int) -> int:
    def hours(k: int) -> int:
        return sum((p + k - 1) // k for p in piles)   # ceil division
    lo, hi = 1, max(piles)
    while lo < hi:
        mid = lo + (hi - lo) // 2
        if hours(mid) > h:
            lo = mid + 1
        else:
            hi = mid
    return lo
```

### 4. Monotonic stack — next greater element
```python
def next_greater(nums: list[int]) -> list[int]:
    out = [-1] * len(nums)
    stack: list[int] = []                    # indices, values decreasing
    for i, v in enumerate(nums):
        while stack and nums[stack[-1]] < v:
            out[stack.pop()] = v
        stack.append(i)
    return out
```
O(n): each element pushed and popped once. Same shape solves: largest rectangle in histogram, daily temperatures, trapping rain water, stock span, "remove K digits".

**Explain the amortised argument** ("each index enters and leaves the stack once, so O(n) despite the nested loop") — that's exactly the kind of reasoning they're listening for.

### 5. Heap — Kth largest / top-K
```python
import heapq
def kth_largest(nums: list[int], k: int) -> int:
    heap = nums[:k]
    heapq.heapify(heap)                      # min-heap of size k
    for v in nums[k:]:
        if v > heap[0]:
            heapq.heapreplace(heap, v)
    return heap[0]
```
O(n log k) time, **O(k) space** — that space bound is the point: it streams. Sorting is O(n log n) and needs the whole array; quickselect is O(n) average but O(n) worst and mutates input.

**Say the trade-off:** "For top-K over a stream or a dataset that doesn't fit in memory, the bounded heap wins. For a one-shot in-memory kth element, quickselect is O(n) average. And if you need all K in sorted order, the heap gives you that for O(k log k) extra."

**Follow-up — running median:** two heaps (max-heap for lower half, min-heap for upper half), rebalance to keep sizes within 1 → O(log n) insert, O(1) median.

### 6. Graph — BFS shortest path, Dijkstra, topological sort
```python
from collections import deque
def shortest_path_unweighted(graph, start, goal):
    dist = {start: 0}; prev = {start: None}
    q = deque([start])
    while q:
        u = q.popleft()
        if u == goal: break
        for v in graph[u]:
            if v not in dist:
                dist[v] = dist[u] + 1; prev[v] = u; q.append(v)
    if goal not in dist: return None
    path, cur = [], goal
    while cur: path.append(cur); cur = prev[cur]
    return path[::-1]
```
- **Unweighted** → BFS, O(V+E). **Weighted non-negative** → Dijkstra with a heap, O((V+E) log V). **Negative edges** → Bellman-Ford O(VE), and it detects negative cycles. **All pairs** → Floyd-Warshall O(V³) (or Johnson's).
- **Topological sort** (Kahn's): repeatedly take zero-in-degree nodes; if you can't finish, there's a **cycle**. This is dependency resolution — build systems, package managers, Terraform's graph, Airflow DAGs, Spring bean wiring. Be ready to say "and this is how I'd detect a circular dependency in a build graph."

```python
def topo_sort(n, edges):
    indeg = [0]*n; adj = [[] for _ in range(n)]
    for a, b in edges: adj[a].append(b); indeg[b] += 1
    q = deque(i for i in range(n) if indeg[i] == 0); order = []
    while q:
        u = q.popleft(); order.append(u)
        for v in adj[u]:
            indeg[v] -= 1
            if indeg[v] == 0: q.append(v)
    return order if len(order) == n else None      # None ⇒ cycle
```

### 7. Union-Find — the "grouping over a stream" tool
```python
class DSU:
    def __init__(self, n): self.p = list(range(n)); self.r = [0]*n
    def find(self, x):
        while self.p[x] != x:
            self.p[x] = self.p[self.p[x]]      # path halving
            x = self.p[x]
        return x
    def union(self, a, b):
        ra, rb = self.find(a), self.find(b)
        if ra == rb: return False              # already connected ⇒ cycle in an undirected graph
        if self.r[ra] < self.r[rb]: ra, rb = rb, ra
        self.p[rb] = ra
        if self.r[ra] == self.r[rb]: self.r[ra] += 1
        return True
```
Near-O(1) per op. Use for: number of islands (dynamic), redundant connection, Kruskal's MST, equivalence classes, sharding/merging partitions. **`union` returning False is cycle detection** — a nice thing to point out.

### 8. DP — how to derive it instead of memorising it
Ask four questions in order:
1. **What is the state?** (smallest thing that fully determines the future) — e.g. `dp[i]` = answer for prefix ending at i; `dp[i][j]` = for two sequences; `dp[i][w]` = with capacity w.
2. **What is the recurrence?** Express `dp[i]` in terms of smaller states.
3. **Base cases and order of evaluation?**
4. **Can you drop dimensions?** Often `dp[i]` only needs `dp[i-1]` → O(1) space.

```python
# House Robber — the minimal example of state compression
def rob(nums):
    prev2 = prev1 = 0
    for v in nums:
        prev2, prev1 = prev1, max(prev1, prev2 + v)
    return prev1                                   # O(n) time, O(1) space
```

**Categories worth naming:** linear DP, knapsack (0/1 vs unbounded — iterate capacity backwards vs forwards), longest common subsequence / edit distance (O(nm)), interval DP, DP over subsets (bitmask, O(2ⁿ·n)), DP on trees, digit DP.

**Senior framing:** "I'd first check whether greedy works and *prove or disprove* it with a counterexample before reaching for DP — DP is O(n²) where greedy might be O(n log n). And I always ask whether the state can be compressed, because in production the space bound usually matters more than the time bound."

### 9. Backtracking — and knowing when to refuse
```python
def permutations(nums):
    out, path, used = [], [], [False]*len(nums)
    def bt():
        if len(path) == len(nums): out.append(path[:]); return
        for i in range(len(nums)):
            if used[i]: continue
            used[i] = True; path.append(nums[i]); bt()
            path.pop(); used[i] = False           # ← undo: the defining step
    bt(); return out
```
Complexity: **state it as a bound and say it's exponential** — permutations O(n·n!), subsets O(n·2ⁿ), combinations O(k·C(n,k)). Then add: "I'd prune early — if the partial solution can't lead to a valid one, return before recursing. For N-Queens that's the diagonal/column sets; for subset-sum it's the remaining-capacity check."

**The senior move:** if n is large, say so. "With n > ~20 this is intractable; I'd switch to DP over subsets, or branch-and-bound, or accept an approximation — which one depends on whether you need all solutions or just one good one."

### 10. Practical/infra coding (what DevOps/SRE/Platform rounds actually ask)
These are far more common than LeetCode for infra roles. Be ready for all five:

**(a) Parse and aggregate a log file** — streaming, O(1) memory:
```python
import sys, collections, re
PAT = re.compile(r'(?P<ip>\S+) .* \[(?P<ts>[^\]]+)\] "(?P<method>\S+) (?P<path>\S+)[^"]*" (?P<status>\d{3}) (?P<size>\d+|-)')
counts = collections.Counter(); status_by_path = collections.defaultdict(collections.Counter)
for line in sys.stdin:                       # never readlines(): stream it
    if m := PAT.match(line):
        d = m.groupdict()
        path = re.sub(r'/\d+', '/:id', d["path"])          # ← normalise or you blow up cardinality
        counts[path] += 1
        status_by_path[path][d["status"][0] + "xx"] += 1
for path, n in counts.most_common(20):
    print(f"{n:>8}  {path}  {dict(status_by_path[path])}")
```
Things they're checking: streaming vs loading, regex precompiled outside the loop, **path normalisation** (cardinality!), error tolerance for malformed lines, output sorted by relevance.

**(b) Implement a rate limiter** — see [`04-Low-Level-Design`](../04-Low-Level-Design/README.md) for the full version; the token bucket in 15 lines:
```python
import time
class TokenBucket:
    def __init__(self, rate: float, capacity: float):
        self.rate, self.capacity, self.tokens, self.ts = rate, capacity, capacity, time.monotonic()
    def allow(self, n: float = 1.0) -> bool:
        now = time.monotonic()
        self.tokens = min(self.capacity, self.tokens + (now - self.ts) * self.rate)
        self.ts = now
        if self.tokens >= n: self.tokens -= n; return True
        return False
```
Use `time.monotonic()`, never `time.time()` (wall clock jumps backwards on NTP sync). Say that out loud — it's a real-world detail juniors miss. Then discuss thread safety (lock or atomic CAS) and distributed state (Redis + Lua for atomicity).

**(c) Retry with exponential backoff + jitter:**
```python
import random, time
def retry(fn, attempts=5, base=0.5, cap=30.0, retryable=(Exception,)):
    for i in range(attempts):
        try: return fn()
        except retryable as e:
            if i == attempts - 1: raise
            delay = min(cap, base * (2 ** i))
            time.sleep(delay / 2 + random.uniform(0, delay / 2))   # "equal jitter"
```
**Explain jitter:** without it, N clients that failed together retry together → **thundering herd / retry storm**. Equal jitter (half fixed, half random) keeps a floor while decorrelating. Mention retry budgets (cap retries at ~10% of traffic) and that you only retry idempotent operations.

**(d) Health-check / poll a set of endpoints concurrently:**
```go
// Go — the version they'd want from a platform engineer
func checkAll(ctx context.Context, urls []string) map[string]error {
    g, ctx := errgroup.WithContext(ctx)
    g.SetLimit(10)                                  // bounded concurrency — the important bit
    var mu sync.Mutex
    out := map[string]error{}
    for _, u := range urls {
        u := u
        g.Go(func() error {
            req, _ := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
            resp, err := client.Do(req)
            if err == nil { resp.Body.Close() }
            mu.Lock(); out[u] = err; mu.Unlock()
            return nil                              // don't fail the group on one bad URL
        })
    }
    _ = g.Wait()
    return out
}
```
Checklist they're scoring: **bounded concurrency** (not 10k goroutines), **context with timeout and cancellation**, `resp.Body.Close()` (fd leak — see the file-descriptor scenario in topic 01), mutex around shared state, and *not* aborting the whole batch on one failure.

**(e) Diff two directory trees / compare two YAML manifests / merge k8s overrides.** Usually recursion + hashing + a stable ordering. The trap is non-deterministic map iteration order — **sort keys** so output is reproducible and diffable in CI.

### 11. Concurrency correctness questions they love
- **Implement a thread-safe LRU cache.** → `HashMap` + doubly-linked list + a mutex; O(1) both ops. Follow-up: shard by key hash to cut contention (and note that sharding breaks the global LRU eviction order — name that trade-off).
- **Producer-consumer / bounded blocking queue.** → condition variables (`not_full`, `not_empty`) or channels. The interesting answer is what happens when the queue is full: block (backpressure), drop (lossy), or drop-oldest. That's a **product decision**, not just code.
- **Implement `sync.Once` / a singleton.** → double-checked locking with proper memory barriers, or language primitives. Know why naive double-checked locking is broken without a fence (instruction reordering can publish a partially-constructed object).
- **Deadlock: four Coffman conditions** → mutual exclusion, hold-and-wait, no preemption, **circular wait**. Break any one; the practical fix is a global lock ordering (breaks circular wait) or timeouts (breaks hold-and-wait).
- **Dining philosophers** → resource hierarchy (number the forks, always take lower first) or a limit of n−1 diners.

---

## 🔴 Scenario

### 12. "Write a function that finds the first non-repeating character in a stream of 10 billion items."
**Don't code immediately — interrogate.** 10 billion items: what's the alphabet? If it's characters (≤ a few thousand distinct), a frequency map is trivially small and the answer is O(n) time, O(σ) space — the *stream size is irrelevant*, only the distinct count matters. That reframing **is** the answer they want.

```python
def first_unique(stream):
    count = {}
    order = []                          # first-seen order
    for x in stream:                    # one pass, streaming
        if x not in count:
            count[x] = 0; order.append(x)
        count[x] += 1
    for x in order:
        if count[x] == 1: return x
    return None
```
If it needs to answer *continuously* as items arrive (not one pass at the end), maintain a doubly-linked list + hashmap so insertion/removal is O(1) and the head is always the answer.

**If the alphabet is also huge** (10B distinct items — e.g. user IDs): exact tracking needs ~10B counters, which won't fit. Now it's an approximation problem: **Count-Min Sketch** for frequencies (bounded memory, overestimates only) plus a probabilistic "seen once" structure, or a **bloom filter of seen-once** minus a bloom filter of seen-twice (false positives, tunable). Or: shard by hash across machines and merge — embarrassingly parallel, exact, and the merge is cheap because each shard only tracks its own keys.

**Say the decision rule:** "If distinct count is small, it's a trivial hashmap problem regardless of stream size. If distinct count is huge, I choose between exact-but-sharded and approximate-in-memory based on whether a false positive is acceptable for the use case. For a UI feature, approximate. For billing, shard and be exact."

### 13. "Design the retry logic for a payment webhook delivery system."
This is a coding question wearing a design hat. Score points by structuring:

1. **Idempotency first.** Every delivery carries a unique `event_id`; the receiver must dedupe. Without that, retries cause double-charges and the whole discussion is moot. Add an `Idempotency-Key` and server-side dedupe with a TTL'd store.
2. **What's retryable?** Distinguish: network error / 5xx / 429 → retry. 4xx (400, 401, 404) → **do not retry** (the request is wrong; retrying wastes resources and delays the real fix), except 408/429. Timeout → retryable **only if idempotent** (you don't know whether it landed).
3. **Backoff schedule.** Exponential with **equal jitter**, capped: 1s, 5s, 25s, 2m, 10m, 1h, 6h, 24h. Webhooks need long tails (receivers have outages for hours) — but each attempt must be cheap.
4. **Retry budget / cap.** Max N attempts (e.g. 20 over 3 days), then move to a **dead-letter state** with alerting, not silent drop. Enforce a global rate limit on retries so a mass receiver outage doesn't turn into a self-DDoS.
5. **Persistence.** Attempts must survive process restarts → durable queue (SQS with visibility timeout + DLQ, or a DB table with `next_attempt_at` and an index on it). In-memory retry = lost events.
6. **Observability.** Metrics per receiver: attempts, success rate, current backoff stage, DLQ depth. Alert on DLQ depth > 0 and on per-receiver success rate collapse.
7. **Circuit breaking.** If receiver X has failed 100 times, stop hammering every 1s — back off globally for that receiver and surface it to the customer.

```python
@dataclass
class Delivery:
    event_id: str; url: str; attempt: int = 0; next_attempt_at: float = 0.0
    state: str = "pending"          # pending | delivered | dead

def schedule_next(d: Delivery) -> None:
    d.attempt += 1
    if d.attempt > MAX_ATTEMPTS:
        d.state = "dead"; alert_dlq(d); return
    base = min(CAP_SECONDS, INITIAL * (4 ** (d.attempt - 1)))   # 1s,4s,16s,... capped
    d.next_attempt_at = time.monotonic() + base/2 + random.uniform(0, base/2)
```

**Then name the hard parts:** ordering guarantees (if events must be delivered in order, per-key serialisation is required and retries block that key — usually you choose at-least-once + unordered + receiver-side sequencing via a monotonic `sequence` field); and the fact that **your retry system needs its own SLO** ("99.9% of webhooks delivered within 60s"), otherwise you can't tell if it's working.

### 14. "Your CI job that processes 1M files takes 6 hours. Make it fast."
This is a **systems** question disguised as coding. Work through it in order:

1. **Measure before optimising.** Profile: where does the 6 hours go — I/O wait, CPU, network, or serialisation? `py-spy`/`perf`/`strace -c`. Guessing is the junior move; say "first I'd profile".
2. **Check it's not accidentally quadratic.** The most common real cause: re-reading an index, appending to a list in a loop, a DB query inside the loop (N+1). Fixing an N+1 often gives 100× with one line.
3. **Batch the I/O.** One file at a time = one syscall storm + one network round trip each. Batch reads, use multipart upload, coalesce DB writes (`COPY`/bulk insert), read sequentially instead of randomly (disk and page-cache friendly).
4. **Parallelise at the right level.**
   - I/O-bound → threads or async, concurrency ~ 2–4× the number of downstream connections you're allowed.
   - CPU-bound → processes (bypass the GIL), sized to cores.
   - Both → process pool with an async/threaded I/O layer inside each worker.
   - **Bound the concurrency** to match the downstream's capacity, or you'll trade a slow job for an outage.
5. **Don't do the work at all.** Incremental processing: keep a manifest of `(path, mtime, hash)` and skip unchanged files. Caching intermediate results keyed by content hash. This usually beats every micro-optimisation.
6. **Shard across machines.** Partition by hash prefix, run N CI jobs in parallel, merge results. Now it's a distributed job and you need: idempotency (a retried shard must not double-count), progress tracking, and failure handling for one bad shard.
7. **Choose better data structures/formats.** JSON → Parquet/Arrow for columnar bulk data (10–50× smaller, vectorised reads). If you're doing joins, let a database or DuckDB do it instead of Python loops.

**Answer shape:** "I'd profile first — I don't want to parallelise an N+1 query. Then the biggest wins are usually: eliminate repeated work with a content-hash manifest, batch the I/O, then parallelise with bounded concurrency, then shard across machines. Only after that would I micro-optimise. In my experience the ordering matters: step 1 and 2 have gotten me from hours to minutes twice, and parallelising a bad algorithm just makes it fail faster and louder."

---

## Red flags

| Doing this | Costs you |
|---|---|
| Coding before clarifying | Signals you'll build the wrong thing |
| Never stating complexity | Automatic downgrade in most rubrics |
| Not handling the empty/single/duplicate input | "Doesn't test their own code" |
| `(lo+hi)/2` in a language with fixed-width ints | Small thing, but shows you've only solved toy inputs |
| Using `time.time()` for intervals/durations | Wall clock jumps; use `monotonic()` |
| Retrying everything, forever, with no jitter | You just designed a retry storm |
| Sorting when a heap suffices | O(n log n) + full materialisation instead of O(n log k) streaming |
| Reaching for DP before checking greedy | Over-engineering; and you can't defend the choice |
| Writing `resp.Body.Close()`-free HTTP code | Real fd leaks; infra interviewers notice |
| Silent `except: pass` | You just made a bug invisible |

## Rapid recall

1. Name the pattern **before** coding, and say what it beats.
2. Binary-search template: half-open `[lo,hi)`, `lo<hi`, `hi=mid`. And "binary search on the answer" for monotonic predicates.
3. Sliding window: grow → `while not valid(): shrink` → record.
4. Top-K over a stream → bounded min-heap, O(n log k), O(k) space.
5. Monotonic stack = O(n) because each element enters and leaves once.
6. Kahn's topo sort returning short ⇒ **cycle detected**.
7. DSU `union` returning False ⇒ already connected ⇒ cycle.
8. B+tree = read-optimised, disk-friendly, range scans. LSM = write-optimised, compaction, read amplification + bloom filters.
9. DP: state → recurrence → base → order → **compress dimensions**.
10. Backtracking: state the exponential bound and how you prune.
11. Infra coding checklist: stream, bounded concurrency, context/timeout, close resources, sort keys for deterministic output, tolerate malformed input.
12. Jitter exists to prevent thundering herd. Retry budgets exist to prevent retry storms.

→ Next: [`03-System-Design-HLD`](../03-System-Design-HLD/README.md)
