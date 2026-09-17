# 16 — 🔴 Scenario Design Round (12 big scenarios · SDE-3 level)

> These are the 15–30 minute whiteboard questions. Answer with the 5-part structure: **requirements → architecture → mechanisms → failure story → trade-off**. Course ref: [16-scenario-cookbook.md](../ansible-mastery/16-scenario-cookbook.md)

## 🎬 S1. Zero-downtime rollout of v2 to 200 app servers
> **Architecture:** `serial: [1, 5, "25%"]` waves · per-host: drain from LB (delegate_to LB/API) → wait drained → versioned release + symlink flip → config template with `validate:` → handler restart + `flush_handlers` → local health gate (`uri` + until/retries) → re-enable in LB. **Failure:** block/rescue = rollback to captured previous release + re-verify; `always` re-enables LB; `max_fail_percentage: 0` stops new waves on first failure; final aggregate report + Slack. **Trade-off:** rolling (gradual exposure, no extra capacity) vs blue-green (instant rollback, 2× cost) — I pick by risk tolerance and infra budget.

## 🎬 S2. Design automation for onboarding a new microservice end-to-end
> **Architecture:** a role per service pattern (data-driven: ports, health path, replicas as defaults), one `deploy` role, inventories per env, group_vars per service tier; provisioning via Terraform → dynamic inventory; config via templates validated; secrets via Vault lookups. **Mechanisms:** role params for instantiation; Molecule per role; lint+check in CI. **Failure story:** health-gate + rollback; **trade-off:** one generic role vs per-service roles (I choose pattern-roles until a service truly diverges).

## 🎬 S3. 400 servers need monthly patching with reboots, business-hours safe
> **Architecture:** per-OS patch plays (`package state=latest security=yes`), `serial: "10%"`, maintenance-window groups per timezone, `reboot` module only `when: patching is changed`, re-gather facts, aggregate report + dashboard update. **Failure:** max_fail_percentage per wave; failed patch → host marked, waves continue, report pages exceptions. **Trade-off:** security-only default vs full updates (risk vs exposure window); AAP schedules + approvals make it operator-free.

## 🎬 S4. DR: primary region down, warm standby exists — automate failover
> **Architecture:** confirmation-gated runbook (`vars_prompt`/AAP approval) → replica-lag check before promote (refuse stale) → promote DB → repoint app tier config (validate) → DNS cutover (TTL 60 pre-set) → end-to-end public health check → declare + notify. **Failure:** each phase re-runnable; lag gate prevents data loss; failback is the documented inverse. **Trade-off:** fully-automatic vs gated (I gate — rare, high-blast operations deserve a human).

## 🎬 S5. 40 engineers need to run automation; no SSH; full audit
> **Architecture:** AAP: projects from git, per-env inventories, job templates + surveys, workflows with approval nodes, RBAC teams, notifications. CI integrates via API tokens. **Mechanisms:** EE per team domain; credentials vaulted in controller. **Failure:** job history + stdout artifacts = audit; RBAC review quarterly. **Trade-off:** platform overhead vs CLI chaos — platform wins above ~10 users.

## 🎬 S6. Legacy fleet: 300 VMs configured by hand, introduce Ansible without disruption
> **Architecture:** start read-only: dynamic inventory + fact-gathering + drift-report playbooks (check-mode scheduled); then baseline role (users/ssh/monitoring agents) applied with `serial` + health checks; then service-by-service conversion, starting with the most-changed system. **Mechanisms:** `--check --diff` everywhere early; canary groups; Molecule for new roles. **Failure:** any drift incident becomes the next conversion candidate. **Trade-off:** big-bang baseline vs incremental (incremental — trust grows with evidence).

## 🎬 S7. Design the pipeline for an Ansible repo (branch to prod)
> **Architecture:** PR: yamllint + ansible-lint + syntax + Molecule (changed roles) → merge to main: `--check --diff` staging artifact → apply staging (auto) → prod (manual approval + `--limit` canary first). **Mechanisms:** environment-scoped secrets, pinned requirements.yml, EE images per release. **Failure:** check-diff artifacts = reviewable plan; prod apply idempotent → safe re-runs. **Trade-off:** trunk-based vs release branches (trunk + env gates for infra).

## 🎬 S8. One playbook must configure app servers that depend on DB servers that don't exist yet
> **Architecture:** multi-play: provision DB (cloud modules or Terraform) → `add_host`/dynamic inventory refresh → configure DB (primary/replica roles) → wait_for DB port → configure app tier with `hostvars[groups['db'][0]]` connection strings → smoke test. **Failure:** every wait bounded (`wait_for` timeouts); retries on provider API flakiness. **Trade-off:** Ansible-only provisioning vs Terraform (I use Terraform above trivial scale; Ansible keeps it for demo/homelab flows).

## 🎬 S9. Security team demands: no plaintext secrets anywhere, rotation every 90 days, audit of every secret read
> **Architecture:** external secrets manager (Vault/SSM) as the only store; Ansible uses lookups with per-identity auth (CI roles, AAP credentials); dynamic DB creds where possible; nothing secret in git (pre-commit scanning); rotation native to the manager; audit from its logs. **Failure:** leaked token = revoke (TTL-bounded), rotation automated. **Trade-off:** infra cost vs Vault-files-in-git (mandate decides — here it's external).

## 🎬 S10. A config change must roll out to 1,000 nginx boxes, but you're the only automation engineer and on call that week
> **Architecture:** maximum built-in safety: `serial: [1, "5%"]`, validate + handlers, health gates, auto-rollback rescue, AAP workflow with approval + scheduled during low-traffic windows, notifications to team channel, runbook doc for the covering engineer. **Failure:** playbook stops itself on anomaly; rollback automatic; human only needed for judgment calls. **Trade-off:** speed of rollout vs sleep — the design buys both.

## 🎬 S11. Two teams' playbooks fight over `/etc/resolv.conf` every night
> **Architecture:** identify via drift reports + run logs; single owner: a `resolver` role with one declarative source (`group_vars/all/dns.yml`); playbooks of both teams consume it; contested file under `mark`-managed block or audit-only mode. **Mechanisms:** ownership registry (CODEOWNERS), lint rule banning direct writes to system files outside roles. **Failure:** scheduled check-mode detects any regression. **Trade-off:** shared role vs duplicated config (shared — drift needs one owner).

## 🎬 S12. Leadership asks: "prove our Ansible estate is healthy" — design observability for automation
> **Architecture:** structured logs (AAP job history or callback to log store), metrics per run (duration, changed counts, failure counts → dashboard), scheduled `--check` drift audits per env (drift = ticket), ansible-lint posture tracked per repo, secret-scan status. **Failure story:** rising changed-counts = drift/nondeterminism regression; failing scheduled audits page on-call. **Trade-off:** build on callbacks vs buy AAP analytics — start with callbacks + dashboards, adopt platform features as scale demands.
