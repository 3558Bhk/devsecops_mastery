# 01 — Basics & Architecture (🟢 8 · 🟡 8 · 🔴 6)

> Course ref: [01-fundamentals.md](../ansible-mastery/01-fundamentals.md)

## 🟢 Basic

**Q1. What is Ansible?**
> A: An agentless, push-based automation tool (written in Python) for configuration management, deployment, and orchestration. It connects over SSH, runs small modules that enforce desired state, and needs nothing installed on targets except Python.

**Q2. What does "agentless" mean and why does it matter?**
> A: No daemon/software is installed on managed nodes — Ansible pushes modules over SSH temporarily. Benefits: no agent upgrade/maintenance, low attack surface, works on any SSH-reachable host.

**Q3. What is a control node? Can it be Windows?**
> A: The machine running Ansible (CLI or AWX/AAP). Officially Linux/macOS only; Windows works via WSL as the control layer.

**Q4. What are the requirements on a managed node?**
> A: SSH access and Python 3 (for most modules). For pre-Python boxes (network gear, bare installs), `raw`/`script` modules work without Python — often used to bootstrap Python itself.

**Q5. What is a playbook? A task? A module?**
> A: Module = unit of work (e.g., `apt`, `copy`). Task = one module invocation with args. Play = ordered tasks applied to a host pattern with shared scope. Playbook = a YAML file of plays.

**Q6. What is idempotency?**
> A: Running the same operation repeatedly produces the same result — a task that already reached desired state reports `ok`, not `changed`. It enables safe re-runs, convergence, and meaningful reports.

**Q7. What does `changed` mean in Ansible output?**
> A: "The module mutated the system during this task." It is not "the task ran" — modules compare desired vs actual state first, and only act (and report changed) when there's a diff.

**Q8. Name three ways to install Ansible.**
> A: `pip install ansible` (core + curated collections), `pip install ansible-core` (engine only), or distro package manager. Air-gapped shops vendor it into Execution Environments.

## 🟡 Intermediate

**Q9. Walk through what happens when one task runs on one host.**
> A: Control node builds an "AnsiballZ" zip of the module, opens SSH, uploads it to a temp dir, executes `python module <json args>`, receives a JSON result (`changed`/`failed`/returned data), then deletes the temp dir.

**Q10. Why is Ansible "declarative but procedural"?**
> A: Modules declare desired state (declarative diffing), but playbook execution order is strictly top-to-bottom (procedural), and `command`/`shell` tasks are imperative escape hatches.

**Q11. ansible vs ansible-core?**
> A: `ansible-core` is the engine: CLI, base plugins, `ansible.builtin` modules. `ansible` is the community package: core plus ~90 popular collections (`community.general`, `amazon.aws`, `kubernetes.core`…).

**Q12. How does Ansible find its configuration?**
> A: First match wins: `$ANSIBLE_CONFIG` → `./ansible.cfg` → `~/.ansible.cfg` → `/etc/ansible/ansible.cfg`. `ansible --version` prints the active file — always check it when config "doesn't apply".

**Q13. What is the `ping` module actually testing?**
> A: Not ICMP — it verifies the whole execution path: SSH auth, Python availability, module upload/execute, and JSON return. `{"ping": "pong"}` means the automation channel is healthy.

**Q14. What are facts? How do you get only some?**
> A: Host data discovered by the `setup` module (OS, IPs, memory…). Limit with `setup: gather_subset: "!all,network"` or `filter:` — or skip gathering entirely with `gather_facts: false`.

**Q15. What's the difference between `command`, `shell`, and `raw`?**
> A: `command` executes without shell features (safe default, no pipes); `shell` runs via /bin/sh (pipes/globs work, injection risk); `raw` doesn't need Python at all (bootstrap only).

**Q16. Why does `--check` mode matter?**
> A: It's a dry run — modules simulate and report what would change without changing it (`--diff` shows file diffs). It's the closest thing to `terraform plan` and a CI safety gate.

## 🔴 Advanced

**Q17. Explain `changed` computation and how you'd handle a module that always reports changed.**
> A: It's computed inside the module by diffing current vs desired state. `command`/`shell` can't know, so they always report changed — fix with real modules, `creates:`/`removes:`, or `changed_when:` on an honest condition; false `changed` triggers handlers and pollutes reports.

**Q18. What are the trade-offs of the push model, and how do you get pull semantics?**
> A: Push centralizes scheduling (control node = choke point, needs network reach). No continuous self-healing like Chef/Puppet daemons. Pull options: `ansible-pull` (cron on nodes pulling git) or AWX/AAP scheduled jobs acting as the pull loop.

**Q19. What does Ansible's lack of a state file imply vs Terraform?**
> A: Ansible diffs live on the target each run — no plan artifact, no drift graph, no destroy/recreate semantics. That makes it operationally light but weaker for provisioning lifecycle; Terraform's state/plan exists precisely for that.

**Q20. Where does the JSON contract between control node and module break, and what happens?**
> A: If anything else writes to module stdout (a stray `print()`, debug lines), Ansible can't parse the result → task fails with a JSON decode error. Custom modules must only emit via `exit_json`/`fail_json`.

**Q21. How do callbacks change execution? Name one you'd enable in prod.**
> A: Callbacks hook task/play lifecycle events for output, notifications, or profiling. Prod: `profile_tasks` + `timer` for visibility, or `community.general.log_plays` for an audit trail; AAP ships its own artifact callbacks.

**Q22. Why is `become` implemented via sudo on the target — and what are its security implications?**
> A: Modules run as the SSH user, `become` re-executes privileged via sudo/su with `become_pass` supplied at runtime. Implications: the deploy user needs narrow sudoers (ideally passwordless for specific paths), and command lines containing secrets can leak via process accounting — hence `no_log` and careful module choice.
