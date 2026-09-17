# 11 — Performance Tuning (From 40 Minutes to 8)

> ⏱️ **Time to complete: ~1.5 hrs** — read 30 min · practice/benchmark 60 min · self-quiz 15 min
> 📦 **Covers:** profiling callbacks (profile_tasks/timer) · pipelining & SSH multiplexing · forks sizing · fact strategy (skip/subset/cache) · scheduling wins (free, async, throttle, --limit) · task & module design · the 40-min→8-min on 500 hosts case study · ansible-pull & scale-out options

> **Interview framing:** *"Our playbook takes 40 minutes on 500 hosts. Fix it."* This is a favorite senior question because the answer is a layered diagnosis: SSH layer → facts → scheduling → task design → measurement. Here's the full playbook (pun intended).

---

## 1. The layered speed model (your answer skeleton)

```
┌─ 1. MEASURE FIRST: profile_tasks / timer callbacks
├─ 2. SSH CONNECTION LAYER: pipelining, multiplexing, forks
├─ 3. FACT GATHERING: skip, subset, or cache
├─ 4. SCHEDULING: strategy, serial batches, throttle
├─ 5. TASK DESIGN: fewer tasks, native modules, no shell soup
└─ 6. SCALE OUT: execution nodes (AAP), or ansible-pull
```

**Rule zero:** never tune blind. Add profiling first:

```ini
# ansible.cfg
[defaults]
callbacks_enabled = profile_tasks, profile_roles, timer
stdout_callback   = community.general.yaml
```

```
PLAY RECAP: ~ 34m ... 
nginx : 12m14s   ← 36% of runtime in ONE role
  → template render: 4m   → apt update: 6m  (per-host!)
```

Now you're tuning with data. Say that sentence.

---

## 2. SSH layer (the biggest single win: pipelining)

**The problem:** by default, for EVERY task Ansible: SSH in → SFTP-upload the module zip → execute → clean up. That's one extra round trip + transfer per task per host.

**Pipelining** (off by default for legacy `requiretty` sudo compat) streams the module via stdin over the existing SSH session — **no SFTP hop**:

```ini
[ssh_connection]
pipelining = True                     # THE big win: often 2-3× on task-heavy plays
ssh_args = -o ControlMaster=auto -o ControlPersist=300s -o ControlPath=/tmp/ansible-ssh-%r@%h:%p
```

Prereq on targets (rare on modern systems): `Defaults !requiretty` in sudoers. If a security team asks "is pipelining safe?" — yes; it's still per-task SSH sessions, just fewer file transfers.

**Connection reuse:** `ControlPersist=300s` keeps TCP/SSH sessions warm across tasks — with 30 tasks × 500 hosts that's 15,000 handshakes avoided.

** forks sizing:**

```bash
ansible-playbook site.yml -f 50
```

- Default 5 is way too low for fleets; 20–50 typical.
- Ceiling: control-node CPU/RAM (each fork = a Python interpreter) + SSH daemon `MaxStartups` on targets + target load sensitivity (50 parallel `apt update`s can hurt a small VM).
- Interview line: *"Forks is a bandwidth×CPU budget; I tune it empirically — 10, 25, 50, watching wall-clock and control-node load."*

---

## 3. Facts — the silent tax

`gather_facts: true` runs `setup` on EVERY host at play start — a full hardware/network/software enumeration taking seconds per host, serialized against your fork budget.

```yaml
# Win 1: skip entirely
- hosts: all
  gather_facts: false          # if your tasks don't use facts — instant win

# Win 2: subset only what you need
- hosts: all
  tasks:
    - ansible.builtin.setup:
        gather_subset: "!all,min"          # or 'network', '!hardware', etc.

# Win 3: cache facts between runs (smart gathering)
```

```ini
[defaults]
gathering = smart
fact_caching = community.general.jsonfile     # or redis for shared/central
fact_caching_connection = /tmp/fact_cache
fact_caching_timeout = 86400
```

With `gathering = smart`, facts are fetched **only if not cached and not expired** — `ansible-playbook --flush-cache` forces refresh. For 500-host fleets, fact caching alone can cut minutes per run; Redis flavor lets all operators share one cache.

> 💬 **Say:** *"Fact caching changes facts from per-run cost to amortized cost — but I add a freshness play (`setup` with `flush cache`) before fleet audits, because stale facts on autoscaled fleets cause 'ghost host' bugs."*

---

## 4. Scheduling wins

```yaml
# Strategy: hosts that CAN go fast, should
- hosts: all
  strategy: free               # no cross-host ordering needed → wall-clock win

# Long independent waits shouldn't serialize (async — file 10)
- ansible.builtin.command: /opt/app/slow-warmup
  async: 900
  poll: 0

# Throttle hammering tasks (paradoxically speeds the FLEET up)
- name: Register with the licensing server (rate-limited!)
  ansible.builtin.uri: ...
  throttle: 4                  # don't DoS the shared dependency

# Don't re-run unchanged heavy tasks: idempotency + tags/when guards
- ansible.builtin.command: /usr/bin/rebuild-index
  when: index_stale is changed
```

Also: **`--limit` discipline** — running the full play when you need 10 hosts wastes everything; and `--start-at-task`/tags for surgical re-runs.

---

## 5. Task & module design

- **`shell`/`command` loops** → replace with native modules; each shell task is a full interpreter spin + transfer.
- **`apt: update_cache: true` every run** → expensive; use `cache_valid_time: 3600`.
- **Many small file edits** → one `template` beats 15 `lineinfile`s (fewer module invocations).
- **`copy` of huge trees** → `synchronize` (rsync protocol, delta transfer) instead:
  ```yaml
  - ansible.posix.synchronize:
      src: app/
      dest: /opt/app/
  ```
- **`lookup('pipe', ...)` inside loops** → hoist out of the loop (lookup re-executes per evaluation).
- **Windows:** enable PowerShell 5.1+, `pipelining` analog in winrm config, `ansible.windows.win_powershell` sparingly.

---

## 6. 🎬 SCENARIO — the 40-minute playbook, diagnosed and fixed

> Walk through this like a war story: numbers before, numbers after.

```text
BEFORE (500 hosts, forks=5, no pipelining, full facts):
  gather facts:        9m30s
  apt update:         11m02s
  62 tasks @ ~20s:    19m00s (serialized by 5 forks + SFTP overhead)
  TOTAL ≈ 40m
```

**Fix 1 — connection layer:**
```ini
[defaults]
forks = 30
gathering = smart
fact_caching = community.general.jsonfile
fact_caching_connection = /opt/ansible/fact_cache
[ssh_connection]
pipelining = True
ssh_args = -o ControlMaster=auto -o ControlPersist=300s
```

**Fix 2 — playbook level:**
```yaml
- hosts: web
  gather_facts: false                      # this play never reads facts
  tasks:
    - name: Only refresh apt when older than an hour
      ansible.builtin.apt:
        update_cache: true
        cache_valid_time: 3600
```

**Fix 3 — measure what remains:**
```text
AFTER:
  facts: cached → ~15s (smart, most hosts cached)
  apt update: skipped on 480/500 hosts (cache warm)
  tasks: pipelined, 30 forks → ~6.5× more parallel
  TOTAL ≈ 8m
```

**Present it as:** *"Measured → removed the per-task transfer tax (pipelining) → bought parallelism (forks) → amortized facts (caching) → stopped doing redundant work (cache_valid_time) → kept profiling on (`profile_tasks`) so regressions scream."*

---

## 7. Bigger hammers (mention, know trade-offs)

| Option | What it is | Trade-off |
|---|---|---|
| **AAP execution nodes** | Scale-out runners close to hosts (automation mesh) | Licensed; ops burden; the real answer at 10k+ hosts |
| **ansible-pull** | Nodes pull from git via cron, run locally | Push→pull inversion; great for huge fleets/edge; loses central orchestration, run_once, delegate_to |
| **Mitogen** | Alternate Python strategy, big speedups | Historical favorite; compatibility issues with newer core versions — know it, don't lead with it |
| **EE slimming** | Faster collection resolution, smaller interpreter payload | Marginal per-task, but free |

---

## 8. 🎤 SDE-3 Interview Corner

**Q1. What is pipelining and why is it off by default?**
> Streaming module code over SSH stdin instead of SFTP temp files — removes one transfer round-trip per task. Off by default for ancient sudo `requiretty` compatibility; on modern fleets I enable it first thing in `[ssh_connection]`.

**Q2. How does fact caching work? Where's the cache?**
> `setup` results stored per host in a cache plugin (jsonfile per-node dir, or Redis shared). With `gathering=smart`, playbooks read cache instead of re-running setup until TTL. It's *facts*, not vars — `set_fact` is uncached unless `cacheable: true`.

**Q3. Control node hits 100% CPU with `-f 200`. What now?**
> Forks = processes; CPU-bound. Options: raise forks but monitor; move to more/faster runners (AAP execution nodes); split plays; reduce Python startup weight; or invert with ansible-pull for raw scale. Also check it's not actually SSH `ControlPath` socket exhaustion (file descriptor limits!) — `ulimit -n` matters at this scale.

**Q4. One host is 10× slower — it blocks every task in linear strategy. Fixes?**
> `strategy: free` for that play; or exclude + separate play; or fix the host (usually it's disk I/O on fact gathering — see profile_tasks). Persistent slow region → regional runner via AAP mesh.

**Q5. How do you benchmark a playbook change honestly?**
> Same inventory snapshot, warm/cold cache both measured, `timer` callback totals, `profile_tasks` for task-level diffs, repeat 3× (SSH multiplexing warmup skews run 1), and track PLAY RECAP changed/ok counts to ensure the optimization didn't silently skip work.

---

## ⚠️ Common pitfalls

- Enabling pipelining but keeping `requiretty` on some hosts → weird sudo failures only on those.
- Fact cache as truth: stale facts on replaced VMs (same name, new IP) → check `ansible_host` divergence; flush on inventory churn.
- Cranking forks to 500 → control-node OOM or SSH MaxStartups throttling (`"connection refused"` storms).
- `strategy: free` in a play that uses `run_once` + handlers + flush — ordering illusions.
- Profiling with `-v` enabled — verbosity itself is a measurable slowdown.

---

**➡️ Next:** [12 — Cloud & Dynamic Inventory](12-cloud-dynamic-inventory.md)
