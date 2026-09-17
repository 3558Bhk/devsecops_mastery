# 04 — Variables & Precedence (🟢 7 · 🟡 8 · 🔴 7)

> Course ref: [04-variables-facts.md](../ansible-mastery/04-variables-facts.md)

## 🟢 Basic

**Q1. What variable types does YAML/Ansible support?**
> A: Scalars (string/int/bool), lists, and dicts/mappings — accessed as `{{ var }}`, `{{ list[0] }}`, `{{ dict.key }}` (or `dict['key']` when keys are dynamic/odd).

**Q2. Where do you define variables? (name four)**
> A: Inventory (`group_vars`/`host_vars`/inline), play (`vars:`, `vars_files:`), role (`defaults/`, `vars/`), and runtime (`set_fact`, `register`, `-e` extra vars).

**Q3. What are facts?**
> A: Discovered host data collected by `setup` (`ansible_facts['distribution']`, `default_ipv4`, `memtotal_mb`…) — the input for most conditional logic.

**Q4. What is `inventory_hostname`?**
> A: A magic variable holding the host's logical inventory name — not DNS, not `ansible_host`. Use it in names, templates, and conditionals.

**Q5. What does `-e` do?**
> A: Defines **extra vars** — the highest-precedence variables, applied at run time: `ansible-playbook site.yml -e "app_version=1.9.0"`.

**Q6. How do you access another host's variables?**
> A: `hostvars['web1']['something']` — plus `groups['web']` to enumerate members. There's no global namespace; vars are host-scoped.

**Q7. What is `set_fact`?**
> A: A task that computes and assigns host-scoped variables at run time. Near-top precedence (below `-e`), lives for the run (unless `cacheable: true`).

## 🟡 Intermediate

**Q8. Recite the precedence anchors.**
> A: `-e` always wins → `set_fact`/registered → `include_vars` → task vars → block vars → role `vars/` → `vars_files` → play vars → gathered facts → `host_vars` → `group_vars` → inventory → **role `defaults/` last**. Rule: runtime beats static, specific beats general.

**Q9. Role params vs role defaults — difference?**
> A: Defaults (`defaults/main.yml`) are the lowest tier — safe overridable knobs. Role params (the `vars:` under a `roles:` entry) are near the top — they beat group/play vars; use them to instantiate a role differently per play.

**Q10. `set_fact` vs registered variables — same tier, what differs?**
> A: Both land in the strong runtime tier. `set_fact` assigns computed values; register holds module results. set_fact can persist via `cacheable: true`; registered results are never cached.

**Q11. Why is using `set_fact` for configuration values dangerous?**
> A: It outranks nearly all static sources — someone's `set_fact` silently beats group_vars and nothing in review shows it. Use it only for derived values; config belongs in defaults/group_vars/-e.

**Q12. What are magic variables? Name five.**
> A: `inventory_hostname`, `group_names`, `groups`, `hostvars`, `ansible_play_hosts_all` — plus `omit` (removes a parameter) and `ansible_version`.

**Q13. What are custom facts and when do they shine?**
> A: JSON/INI files dropped in `/etc/ansible/facts.d/*.fact`, surfacing under `ansible_local.*`. Shines for fleet reporting: app version/channel as queryable facts across every playbook.

**Q14. What's `gather_facts: false` cost/benefit?**
> A: Benefit: skips the `setup` round-trip per host — big at scale (file 11). Cost: any fact-based conditional fails — so plays that need facts gather subsets explicitly instead.

**Q15. What is lazy templating and why does it matter?**
> A: Jinja in var values evaluates at *use* time, not definition time — so `x: "{{ y }}"` works even if `y` is defined later. It also explains import/include timing differences.

## 🔴 Advanced

**Q16. If `-e` and `set_fact` collide, who wins and why?**
> A: `-e` — extra vars sit above everything by design (deliberate operator override channel). Everything below defers: that's why `-e` is the safe emergency knob and also why CI should treat it as code review-worthy input.

**Q17. Playbook-dir group_vars beats inventory-dir group_vars — but what beats both and where's the trap?**
> A: Runtime sources (set_fact, registered, task vars) and any higher static tier; the trap is `include_vars` — it's *higher than task vars* despite being "just a file load", so dynamically loaded files can override things readers assume are fixed.

**Q18. How do you debug "where is this value coming from?"**
> A: `ansible-inventory --host <name>` for resolved static vars; `-e` bisecting (winner always); `-vv` for templating traces; temporarily shadow the var at task level to prove the layer; `debug: var=` with `hostvars[inventory_hostname] | dict2items` filtered by name.

**Q19. How does `hash_behaviour` affect multi-source dictionaries, and what's the safe pattern?**
> A: Default `replace`: whole-dict override, last definition wins wholesale — no merge. Safe pattern: keep the default and merge explicitly with `combine(dict2, recursive=true)` where needed; relying on `merge` makes behavior environment-dependent on config.

**Q20. Explain fact caching mechanics and one failure mode.**
> A: `gathering=smart` + cache plugin (jsonfile/redis) with TTL: `setup` runs only on cache miss; `set_fact cacheable` values join the cache. Failure mode: stale facts on replaced VMs (same name, new IP/hardware) — flush cache on inventory churn or before audits.

**Q21. How do you share a computed value across hosts in one run?**
> A: Vars are host-scoped, so: `run_once` + loop `set_fact` over `groups['all']` (set on every host), persist to a file/external store and `lookup('file')`, or read via `hostvars[groups['db'][0]].…` when the value lives on a known host.

**Q22. What does `omit` do and where's it most useful?**
> A: Special value that removes a parameter entirely from the module call: `security: "{{ omit if not is_debian else true }}"` — lets one task expression adapt module args per platform instead of duplicating tasks.
