# 11 — Performance & Scale (🟢 4 · 🟡 6 · 🔴 6)

> Course ref: [11-performance-tuning.md](../ansible-mastery/11-performance-tuning.md)

## 🟢 Basic

**Q1. What's the default forks value and how do you raise it?**
> A: 5; raise via `forks =` in ansible.cfg or `-f 50` at run time — sized to control-node CPU/RAM and target-side tolerance.

**Q2. Why is `gather_facts: false` the cheapest speed win?**
> A: Skips the per-host `setup` round-trip at play start — tasks that never read facts lose nothing.

**Q3. What does pipelining do?**
> A: Streams the module over the existing SSH session's stdin instead of SFTP-uploading a temp file — removes a transfer per task; often the single biggest win. `[ssh_connection] pipelining = True`.

**Q4. Name the profiling callbacks.**
> A: `profile_tasks` (per-task timing), `profile_roles`, `timer` — enable in `callbacks_enabled` so tuning is data-driven, never blind.

## 🟡 Intermediate

**Q5. How does fact caching work?**
> A: `gathering = smart` + cache plugin (`jsonfile` local, `redis` shared) + TTL: `setup` runs only on cache miss, all runs read the cache until expiry; `--flush-cache` forces refresh.

**Q6. What's `cache_valid_time` for apt?**
> A: Skips `update_cache` if metadata is younger than N seconds — turns a per-host network hit on every run into an hourly one.

**Q7. Strategy/async choices for wall-clock speed?**
> A: `strategy: free` when hosts are independent; `async/poll: 0` for long waits; `throttle` paradoxically *speeds the fleet* when a task hammers a shared dependency.

**Q8. Copying a huge directory tree — faster alternative?**
> A: `ansible.posix.synchronize` (rsync protocol, delta transfer) instead of `copy` — full re-transfer vs checksummed deltas.

**Q9. Why do lookups inside loops hurt?**
> A: The lookup re-executes on each evaluation — hoist it into a var before the loop (one execution) instead of `lookup(...)` per item.

**Q10. When is `--limit` a performance tool?**
> A: When you only need 10 of 500 hosts — skipping inventory-wide fact gathering and irrelevant hosts beats any tuning of a full-fleet run.

## 🔴 Advanced

**Q11. "40 minutes on 500 hosts — fix it." Full diagnosis order.**
> A: Measure (profile_tasks/timer) → SSH layer (pipelining + ControlPersist multiplexing) → forks sizing (empirical 10→25→50 watching CPU/fds) → facts (skip/subset/cache) → scheduling (free/async/throttle) → task design (fewer tasks, native modules, cache_valid_time) → re-measure. Typical outcome 40→8 min.

**Q12. Control node hits 100% CPU at `-f 200`. What now?**
> A: Forks are processes — CPU-bound: reduce forks, or scale out runners (AAP execution nodes/mesh), or check you're actually fd/ControlPath-throttled (`ulimit -n`, socket exhaustion mimics CPU storms). Consider splitting plays or ansible-pull for raw scale.

**Q13. One slow host blocks every task in linear strategy — options?**
> A: `strategy: free` for the play; exclude + remediate separately; fix the host (usually disk I/O during fact gathering — visible in profile_tasks); place runners closer to slow regions via automation mesh.

**Q14. How do you benchmark a tuning change honestly?**
> A: Same inventory snapshot; measure warm AND cold (SSH multiplexing warmup skews run 1); `timer` totals + `profile_tasks` task-level diff; repeat 3×; verify PLAY RECAP changed/ok counts identical — an "optimization" that silently skips work is a regression.

**Q15. What breaks at 5,000 hosts that never breaks at 50?**
> A: SSH handshake storms (MaxStartups), fd/ControlPath exhaustion, control-node memory per fork, dynamic-inventory API latency, fact-cache write contention, and any `run_once`+delegate hot-spot. Answers: mesh/execution nodes, caching layers, job slicing (AAP), pull models.

**Q16. Compare scale-out options: AAP mesh vs ansible-pull vs Mitogen.**
> A: Mesh: licensed, managed runners near hosts, central control retained — enterprise default. Pull: free, infinite scale, loses orchestration primitives. Mitogen: historically large speedups via reduced interpreter overhead, but compatibility risk with modern core — know it, verify before adopting.
