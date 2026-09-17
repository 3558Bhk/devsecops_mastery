# 06 — Templates & Jinja2 (🟢 6 · 🟡 8 · 🔴 6)

> Course ref: [06-jinja2-templates.md](../ansible-mastery/06-jinja2-templates.md)

## 🟢 Basic

**Q1. template vs copy?**
> A: `copy` ships bytes verbatim (checksum-diffed); `template` renders Jinja2 first from vars/facts. Static → `copy`, anything host/env-specific → `template`.

**Q2. What are `{{ }}`, `{% %}`, `{# #}`?**
> A: Expression (print a value), statement (if/for logic), and comment — comments never reach the rendered file.

**Q3. What does `{{ var | default('x') }}` do?**
> A: Falls back to `'x'` when var is undefined. Note: it does NOT replace empty strings or false — that needs `default('x', true)`.

**Q4. How do you filter a list of dicts by a field?**
> A: `{{ servers | selectattr('env', 'equalto', 'prod') | list }}` (or `rejectattr`), often chained with `map(attribute='host') | list`.

**Q5. What is `mandatory`?**
> A: A filter that fails the run with a clear error if the variable is undefined — the loud way to require inputs instead of silently rendering empty.

**Q6. What's `to_json`/`from_json` used for?**
> A: Serializing structures into JSON strings (config bodies, API payloads) and parsing JSON strings back into template-usable data.

## 🟡 Intermediate

**Q7. How do you generate an nginx upstream block for all `web` hosts?**
> A: Template loop over inventory: `{% for h in groups['web'] %}server {{ hostvars[h]['ansible_host'] }}:8080;{% endfor %}` — sorted for deterministic output, filtered for healthy members.

**Q8. lookup vs query?**
> A: `lookup()` returns a string (comma-joined if multiple); `query()`/`q()` returns a proper list. Use `query` whenever results are plural.

**Q9. Where do lookups execute — control node or target? Why does it matter?**
> A: Control node, at templating time. So they can read secrets/secrets-stores and local files cheaply, but are not check-mode-safe and can't see target state (use `slurp`/`command` for that).

**Q10. How do you validate a rendered config before deployment?**
> A: `validate: "nginx -t -c %s"` on the template task — temp file rendered, validator run, real file replaced only on success; pair with a reload handler so bad config never causes an outage.

**Q11. Why do loops over dicts sometimes churn config on every run?**
> A: Dict iteration order/derivable data (timestamps, random) — non-deterministic rendering changes the file each run → perpetual `changed` + spurious reloads. Sort everything, keep templates deterministic.

**Q12. How do you emit literal `{{ }}` in a template?**
> A: Quote-delimit: `{{ '{{' }}`, or `{% raw %}…{% endraw %}` for whole blocks — needed when generating other templating systems' files (Helm, Prometheus relabel configs).

**Q13. What does `ternary` do?**
> A: Inline conditional: `{{ is_prod | ternary('0640', '0644') }}` — keeps small mode/path/logic decisions in one line instead of `{% if %}` blocks.

**Q14. `password_hash('sha512', salt)` — what's it for?**
> A: Generating `/etc/shadow`-compatible hashes for the `user` module — so you can set passwords idempotently without plaintext in the final file.

## 🔴 Advanced

**Q15. A template renders but one variable is silently empty. Root causes and policy?**
> A: Undefined suppressed by `default()`, guarded `{% if %}`, or a typo matching nothing. Policy: `mandatory` for required inputs, `default(…, true)` only where empty is legitimate, lint + `--check --diff` review, and never trust rendered-blank output.

**Q16. How do you keep fleet configs byte-identical yet host-specific?**
> A: Deterministic templates: sort all loops, no timestamps/random, canonical joins; host specifics only from facts/inventory. Then checksum drift detection (scheduled check-mode runs) reports real drift, not render noise.

**Q17. Explain `!unsafe` and when you'd use it.**
> A: A YAML tag marking data as never-templated — Ansible will not process `{{ }}` inside it. Use for content that legitimately contains braces (certs, scripts embedding templates) to avoid templating errors/injection.

**Q18. Write a filter chain: unique, sorted, comma-joined FQDNs of prod web hosts.**
> A: `{{ groups['web'] | map('extract', hostvars, 'ansible_facts') | map(attribute='fqdn') | unique | sort | join(', ') }}` — knowing `map('extract', hostvars, …)` is the senior tell.

**Q19. What's the security story for templates that embed secrets?**
> A: Tight `mode:` on destination (0600/0640), `no_log: true` on the task, avoid `--diff` on those tasks in shared CI (or `diff: false`), and prefer external secret lookups so the template itself stays secret-free.

**Q20. How would you implement a custom filter for your team, and where does it live?**
> A: Python `FilterModule` exposing a filters dict (e.g., `cidr_host`), shipped in `filter_plugins/` for a repo or properly inside a collection's `plugins/filter/` — versioned and pinned like any code, so 40 repos share one implementation (course file 14).
