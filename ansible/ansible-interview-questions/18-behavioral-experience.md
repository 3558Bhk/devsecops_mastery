# 18 — Behavioral / Experience Questions (🟡 5 · 🔴 7)

> SDE-3 rounds weigh *how you operated*, not just syntax. Answer with a real story: **context → your action → outcome with numbers → what you'd do differently.**

## 🟡 Intermediate

**Q1. "Tell me about the most complex thing you've automated with Ansible."**
> Structure it: scale/context (hosts, envs), the hard part (orchestration ordering? secrets? flaky deps?), your design (serial waves, block/rescue, dynamic inventory…), outcome (deploy time 2h→6min, failed-change rate ~0), and one trade-off you'd revisit.

**Q2. "Have you ever broken production with automation? What happened?"**
> They want accountability + systems thinking, not perfection. Name the missing guard honestly (no validate / no canary / silent changed), the immediate mitigation, and the permanent fix (health gates, lint rule, CI gate) — end with how it changed your defaults.

**Q3. "How do you convince a team to adopt idempotent practices when shell scripts 'work fine'?"**
> A: Show, don't tell: convert one painful script, demo re-run safety + drift reports + rollback; quantify incident toil reduced. Meet them where they are — `script:`/`shell` with `changed_when` as a stepping stone, then refactor. Adoption follows visible wins.

**Q4. "How do you review someone else's playbook?"**
> A: Checklist: idempotency (changed_when/creates), blast radius (serial/limit), validation (validate, health checks), secrets (no plaintext, no_log), naming/lint compliance, handlers vs direct restarts, and failure path (what happens when task 7 fails?). Praise the good parts first — review is culture.

**Q5. "How do you keep up with Ansible ecosystem changes (collections, FQCN, EEs)?"**
> A: Release notes for ansible-core + the collections I depend on; pinned requirements with scheduled bump PRs (renovate-style); community (forum/Reddit/mailing lists) for deprecations; internal lunch-and-learns. Concrete example: planning the FQCN migration or an EE upgrade shows real maturity.

## 🔴 Advanced

**Q6. "You inherit a 2,000-line playbook nobody understands. Walk me through your first month."**
> A: Week 1: make it observable — lint report, `--check --diff` runs, inventory map, run history; freeze direct prod edits. Week 2: split by concern into roles with tests (Molecule) as I touch each part — strangler pattern, no big-bang rewrite. Week 3–4: CI + docs + ownership; measure: run duration, failure rate, time-to-change. Never rewrite what you can't run safely.

**Q7. "Describe a time automation saved (or cost) significant money/time. Numbers."**
> A: Have one story with hard numbers ready: e.g., patching 400 hosts monthly: 3 engineer-days → 40 automated minutes, with reboot compliance at 100% vs ~70% manual; or deploy lead time 2h→6min with failed-change rate near zero. Numbers make it senior.

**Q8. "How do you handle 'just add an ignore_errors' pressure from a deadline?"**
> A: Acknowledge the pressure, propose the 5-minute honest version: register + `failed_when` on the acceptable condition, or rescue with explicit fallback — same speed, honest semantics. If truly non-essential, `ignore_errors` + logged follow-up ticket. I don't ship silent failures; that's how 3 a.m. pages happen.

**Q9. "Tell me about a time you disagreed with a team about tooling (e.g., Ansible vs Terraform vs scripts)."**
> A: Frame by decision criteria, not taste: state lifecycle, team skills, blast radius, audit needs. Tell the story of driving to a written decision record (ADR) — and name a case where the other side won and you committed fully. Outcome: clarity, not victory.

**Q10. "How do you test infrastructure changes when staging ≠ production?"**
> A: Layers: Molecule for role logic (hermetic), staging for integration, prod via canary waves + `--check --diff` + scheduled drift audits — acceptance gates at each layer. Also: make prod *more like staging* via EEs/pinned deps. Honest answer includes what still surprises you (shared-state dependencies).

**Q11. "What's your on-call relationship with your automation?"**
> A: My playbooks page me only when they safely stopped (fail-safe design), with `ansible_failed_task` context in the alert; runbooks link to the exact playbook + rollback path; recurring pages become lint rules or Molecule tests. Automation that can't fail safely shouldn't run unattended.

**Q12. "Where do you see the limits of Ansible — when would you NOT use it?"**
> A: Strong answer: continuous reconciliation (K8s controllers/GitOps win), infra lifecycle with destroy/recreate (Terraform wins), sub-second/config-drift-daemon needs (Puppet-style), and heavy data-plane logic (real code, not YAML). Knowing the boundaries is the point — then say what you'd pair it with.
