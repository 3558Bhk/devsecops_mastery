# 10 — Execution Strategies, Serial, Async & Zero-Downtime Deploys

> ⏱️ **Time to complete: ~3 hrs** — read 30 min · practice (type the full rollout!) 150 min · self-quiz 20 min
> 📦 **Covers:** forks vs strategy vs serial vs throttle · linear/free/host_pinned · canary waves (`serial: [1, 5, "25%"]`) · the zero-downtime LB deploy playbook · blue-green & canary design trade-offs · async/poll & async_status · the reboot-and-verify pattern · stale-facts-after-reboot trap

> **Interview framing:** This is the canonical SDE-3 scenario: *"Walk me through deploying to 100 servers without downtime."* Everything here — serial, strategy, async, canary — exists to answer that question with engineering, not hand-waving.

---

## 1. How Ansible schedules work (the foundation)

Two orthogonal controls:

- **`forks`** (default 5): how many hosts are processed **in parallel overall**. `-f 50` or `forks = 50` in ansible.cfg. This is your concurrency budget; size it to control-node CPU and target-side load.
- **`strategy`**: how the play moves through hosts/tasks.
  - **`linear`** (default): all hosts complete task N before anyone starts N+1. Predictable, sync'd waves.
  - **`free`**: each host rushes through tasks independently. Faster wall-clock when hosts are heterogeneous/slow, but breaks cross-host ordering assumptions.
  - **`host_pinned`**: like free, but each host's full play runs as one unit — useful for per-host concurrency caps.

```yaml
- hosts: web
  strategy: linear            # default
  serial: 5                   # "batches": 5 hosts at a time, fully finished before next wave
  max_fail_percentage: 10     # if >10% of the BATCH fails → abort the whole play
```

**`serial` values you should know:**

```yaml
serial: 5               # fixed batch
serial: "25%"           # percentage of group, rounded up
serial: [1, 5, "25%"]   # CANARY SEQUENCE: 1 host, then 5, then a quarter, then the rest
serial: "{{ serial_count | default(10) }}"   # tunable via -e
```

`serial: [1, 5, "25%"]` **is** a canary deployment in one line — say that sentence in the interview.

---

## 2. 🎬 SCENARIO 1 — Zero-downtime rolling deploy behind a load balancer

> The complete answer to "how do you deploy without downtime". File 08 has the rollback variant; here's the scheduling + LB mechanics.

```yaml
- name: Zero-downtime web rollout
  hosts: web
  become: true
  serial: [1, "10%"]                 # canary wave, then 10% waves
  max_fail_percentage: 0
  strategy: linear

  pre_tasks:
    - name: Sanity — refuse to deploy if too many hosts already down
      ansible.builtin.assert:
        that:
          - groups['web'] | length >= 4
        fail_msg: "Fleet too small to roll safely"
      run_once: true

    - name: Drain this host from HAProxy
      ansible.builtin.command: >
        docker exec haproxy /bin/sh -c
        "echo 'disable server webservers/{{ inventory_hostname }}' | socat stdio /var/run/haproxy.sock"
      delegate_to: "{{ groups['lb'][0] }}"
      changed_when: true

    - name: Wait for connection count to drain
      ansible.builtin.wait_for:
        host: "{{ ansible_facts['default_ipv4']['address'] }}"
        port: 8080
        state: drained                 # waits until ZERO connections!
        timeout: 120

  roles:
    - role: app_deploy                 # the boring part: unpack, symlink, restart (files 03/07)

  tasks:
    - name: Health gate before re-admitting traffic
      ansible.builtin.uri:
        url: "http://localhost:8080/healthz"
        status_code: 200
      register: h
      until: h.status == 200
      retries: 10
      delay: 5

    - name: Re-enable in HAProxy
      ansible.builtin.command: >
        docker exec haproxy /bin/sh -c
        "echo 'enable server webservers/{{ inventory_hostname }}' | socat stdio /var/run/haproxy.sock"
      delegate_to: "{{ groups['lb'][0] }}"
      changed_when: true

    - name: Verify through the LB that this member serves
      ansible.builtin.uri:
        url: "http://{{ hostvars[groups['lb'][0]].ansible_host }}/"
        status_code: 200
        headers:
          X-Backend-Check: "{{ inventory_hostname }}"
      delegate_to: localhost
```

**Narration checklist (why each line earns its place):**
- `serial` waves = limited blast radius; failed wave 1 never poisons wave 2.
- **Drain before deploy, verify before enable** — traffic only ever hits verified healthy backends.
- `wait_for: state: drained` — elegantly waits for in-flight requests to finish.
- `delegate_to: lb` + `hostvars[groups['lb'][0]]` — orchestration happens from a central point.
- `run_once` assert — fail fast before touching anything if the fleet is already degraded.

---

## 3. Blue-green & canary in Ansible terms

### Blue-green
```yaml
# play 1: deploy FULL new fleet (green) alongside blue
- hosts: green
  tasks:
    - name: Deploy + deep-verify the inactive color
      ansible.builtin.import_tasks: tasks/deploy_and_verify.yml

# play 2: flip LB to green (single atomic action)
- hosts: lb[0]
  tasks:
    - name: Point pool at green
      ansible.builtin.template:
        src: haproxy_green.cfg.j2
        dest: /etc/haproxy/haproxy.cfg
        validate: "haproxy -c -f %s"
      notify: Reload haproxy            # reload = zero dropped connections
```
> 💬 Trade-off speech: *"Blue-green gives instant rollback (flip back) and full-fleet testing, but costs 2× capacity and stateful services need replication thought. Rolling gives gradual exposure with less capacity. I choose by blast-radius tolerance and infra cost."*

### Canary
```yaml
- hosts: web
  serial: [1, 5, "25%"]            # 1 → 5 → 25% → rest
  tasks: ...deploy...
```
With `-e app_version=...` and `max_fail_percentage: 0`, aborting mid-way leaves only the canary wave exposed. Combine with per-wave metrics gate (Prometheus query task between waves):

```yaml
    - name: Error-rate gate before continuing
      ansible.builtin.uri:
        url: "http://prometheus:9090/api/v1/query?query=sum(rate(http_5xx[5m]))by(instance)"
      register: q
      delegate_to: localhost
      run_once: true
      failed_when: (q.json | to_json) is search('"value":[[^,]+,"[^1-9]')   # simplified gate
```

---

## 4. Async — fire, don't block

```yaml
- name: Kick off a 45-minute dataset rebuild (don't sit waiting)
  ansible.builtin.command: /opt/etl/bin/rebuild --full
  async: 3600                 # max runtime allowed
  poll: 0                     # 0 = fire-and-forget, return immediately
  register: etl_job

- name: ...other useful work can happen here...

- name: Later in the play — check on it
  ansible.builtin.async_status:
    jid: "{{ etl_job.ansible_job_id }}"
    mode: status
  register: job_result
  until: job_result.finished
  retries: 60
  delay: 60
```

When to use (interview soundbite):
> *"`poll: 0` frees the fork slot — essential when a task takes longer than your playbook needs anything else, or when you'd otherwise serialize 100 hosts behind one slow task. Async jobs survive on the target with their own job file; `async_status` reaps them. Caveats: not all modules support async (needs async-capable action), handlers can't be async, and fire-and-forget means you OWN the polling — if the connection drops before you reap, you have an orphan job."*

### 🎬 SCENARIO — reboot-and-verify pattern (uses async-safe modules + wait_for_connection)

```yaml
- name: Kernel patch + controlled reboot
  hosts: all
  become: true
  serial: "10%"
  tasks:
    - name: Upgrade kernel
      ansible.builtin.package: { name: linux-image-generic, state: latest }
      register: kern
      when: ansible_facts['kernel'] is version('5.15.0', '<')

    - name: Reboot if needed
      ansible.builtin.reboot:               # module handles: init reboot, drop, wait, reconnect
        reboot_timeout: 600
        pre_reboot_delay: 5
        test_command: uptime                # sanity after reconnect
      when: kern is changed

    - name: Confirm we're back on new kernel
      ansible.builtin.assert:
        that: ansible_facts['kernel'] is version('5.15.0', '>=')
      # NOTE: facts are from BEFORE reboot — re-gather!
    - ansible.builtin.setup: { filter: ansible_kernel }
```

> ⚠️ The subtle bug everyone hits: `ansible_facts` were gathered at play start — **after a reboot, re-gather (`setup`) before asserting on new state.** Mentioning this in an interview is a strong signal.

---

## 5. 🎤 SDE-3 Interview Corner

**Q1. "Deploy v2 to 200 app servers with zero downtime and auto-rollback." (30-second architecture answer)**
> Inventory split into waves via `serial: [1, 5, 25%]`; per host: drain from LB (socat/API to HAProxy), wait drained, versioned release + symlink flip, handler restart, local health check with `until` retries, re-enable in LB. `block/rescue` wraps deploy with rollback-to-previous-release; `max_fail_percentage: 0` halts on first bad wave; alerting via final notify play. CI passes version via `-e`; check mode + canary wave reviewed before full roll.

**Q2. `linear` vs `free` — when does `free` bite you?**
> `free` helps when hosts are heterogeneous (patching mixed hardware, slow nodes not blocking fast ones). It bites when you have cross-host ordering/orchestration: "everyone stopped before migration starts" breaks — with free, host A may run task 5 while host B is on task 2. Any play using `delegate_to` sequences, run_once gates, or handler flushes wants `linear`.

**Q3. What is `throttle` vs `forks` vs `serial`?**
> `forks` = global parallelism budget. `serial` = play-level batch size (blast radius). `throttle: N` on a single task caps ITS concurrency (e.g., a task that hammers a shared DB, or licensing-limited vendor tool). All three compose; knowing all three is the point.

**Q4. How would you do a controlled migration that runs once while 50 app servers are down?**
> Multi-play: play 1 stops apps (`serial: 100%` or all), play 2 targets `db[0]` run_once, play 3 restarts apps with serial + health checks. Never inside one play with free strategy — ordering is per-host, not global.

**Q5. Playbook must survive SSH drops to remote-site hosts with flaky links.**
> `async: X poll: 0` for long tasks so they run server-side; `pipelining`+`ControlPersist` for connection reuse; `ignore_unreachable` + retry plays; or execute from a local jump host with `delegate_to`. Ultimate: run Ansible FROM the remote site (control node placement) — network boundaries belong in the design.

---

## ⚠️ Common pitfalls

- `serial` + `delegate_to` to a host **in the play's target group** — that host gets restarted mid-delegation chaos; delegate to hosts *outside* the play target.
- Forgetting `poll` must be `0` for true fire-and-forget (a big `poll: N` value just blocks differently).
- `async` on tasks whose module doesn't support it → falls back to sync silently.
- `max_fail_percentage` requires `serial` to be meaningful — percentage is of the current batch.
- Killing a playbook mid-`pause`/mid-async leaves orphans — re-run should reconcile (idempotency saves you; that's *why* idempotency is sacred).
- Not re-gathering facts after `reboot` — asserting on stale pre-reboot data.

---

**➡️ Next:** [11 — Performance Tuning (500-host playbook in 8 minutes)](11-performance-tuning.md)
