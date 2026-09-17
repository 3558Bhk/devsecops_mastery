# 07 — Roles & Collections (🟢 6 · 🟡 8 · 🔴 6)

> Course ref: [07-roles-collections.md](../ansible-mastery/07-roles-collections.md)

## 🟢 Basic

**Q1. What is a role?**
> A: A structured, reusable bundle — tasks, handlers, defaults, vars, templates, files, meta — loaded by a playbook via `roles:`/`import_role`/`include_role`. It's how playbooks become a library.

**Q2. Name the standard role directories.**
> A: `tasks/`, `handlers/`, `defaults/`, `vars/`, `files/`, `templates/`, `meta/` (plus optional `library/`, `module_defaults/`). Entry point: `tasks/main.yml`.

**Q3. What does `ansible-galaxy init` do?**
> A: Scaffolds the standard role directory tree — the starting point for a new role.

**Q4. What is a collection?**
> A: The modern distribution package: modules, plugins, roles, and docs under a namespace (`community.docker`, `kubernetes.core`), installed via `ansible-galaxy collection install`.

**Q5. What is FQCN and why bother?**
> A: Fully Qualified Collection Name (`ansible.builtin.copy`). Unambiguous against redirects/collisions, grep-able, and enforced by ansible-lint.

**Q6. What lives in `meta/main.yml`?**
> A: Galaxy metadata (author, platforms, min version) and `dependencies:` — roles that run before this one, optionally with their own vars/when.

## 🟡 Intermediate

**Q7. defaults vs vars — the interview classic.**
> A: `defaults/main.yml` = lowest precedence, public overridable knobs. `vars/main.yml` = high precedence internal constants consumers shouldn't override. Knobs in defaults; computed internals in vars.

**Q8. Three ways to consume a role — when each?**
> A: `roles: [nginx]` (simple), role + `vars:` (instantiation with params — same role, different configs), `include_role`/`import_role` (dynamic: conditional, looped, mid-play ordering).

**Q9. How do role dependencies execute?**
> A: In listed order, before the parent role's own tasks. Can carry their own vars/when; `allow_duplicates: true` lets the same role run twice. Deps inherit parent tags on imports — sometimes surprisingly.

**Q10. How do you make one role support Ubuntu and RHEL cleanly?**
> A: `include_vars: "{{ ansible_facts['os_family'] }}.yml"` for names/paths, `include_tasks` per family for differing logic — data in per-family var files, not `when` sprinkled through tasks.

**Q11. What belongs in `requirements.yml` and why pin versions?**
> A: External roles + collections with exact/bounded semver (`community.docker 3.4.x`). Unpinned deps = non-reproducible CI and surprise breaking changes on upstream releases.

**Q12. Role params vs extra vars vs group_vars overriding a role — who wins?**
> A: `-e` beats role params; role params beat role `vars/` which beats play/group vars; role defaults lose to everything. So: defaults for knobs, params for instantiation, `-e` for emergencies.

**Q13. What's a "data-driven role"?**
> A: The role consumes declarative input (e.g., `nginx_vhosts: [...]` from group_vars) and owns the *how* — templates, loops, validation. Consumers declare *what*; one role serves all topologies.

**Q14. When should you NOT write a role?**
> A: One-off orchestration with no reuse value — a well-named task file or play is lighter. Roles earn their structure cost through reuse and testing.

## 🔴 Advanced

**Q15. Design a role library strategy for a 40-repo org.**
> A: Internal collection(s) hosting shared roles + filter/lookup plugins, semver-tagged, published to a private hub (or git pins in `requirements.yml`); consumers pin bounded versions; roles CI'd with Molecule across platform matrix; deprecation policy for knobs (rename via dual-read + warning).

**Q16. A role must serve single-node staging and 3-node prod replication — design it.**
> A: Declarative input like `pg_replication: {enabled, primary, replicas}` computed from `groups['db']`; role branches internally via includes; `defaults` for sizes/ports; idempotent per-role path (primary vs replica tasks). Zero role forks, one code path to maintain.

**Q17. How do role tags interact with dependency trees, and how do you keep `--tags` usable?**
> A: Deps inherit parent import tags; tasks inside roles can add their own. Keep a small documented taxonomy (install/config/deploy/verify), tag handlers identically, and lint against tag soup — otherwise `--tags` silently skips critical steps.

**Q18. What does `module_defaults` give you in a role?**
> A: Default arguments applied to module calls (e.g., default `aws_region` for all `amazon.aws` calls, default dict for `uri` headers) — reduces repetition and centralizes env-specific args.

**Q19. How do you version and deprecate role interface changes?**
> A: Semver: breaking knob renames = major. In-role: read old + new name, `debug`/`assert` deprecation warning when old is used, remove after N releases. Changelog in role README; consumers' CI warns visibly.

**Q20. Explain role execution order inside a play that also has pre_tasks and post_tasks.**
> A: `pre_tasks` → handlers flush point → **roles** → `tasks` → `post_tasks` → final handlers. So role tasks run after pre_tasks and before explicit tasks — critical when pre_tasks do baselines the role expects.
