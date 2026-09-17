# 14 · Cheatsheets

One-page references. Print them, pin them, keep them in a second monitor.

| Cheatsheet | Contents |
|---|---|
| [`promql.md`](promql.md) | Types, selectors, operators, aggregations, the function table, 25 essential queries, debugging flow |
| [`prometheus-config.md`](prometheus-config.md) | `prometheus.yml` skeleton, CLI flags, relabeling actions, service discovery, HTTP API |
| [`alertmanager-config.md`](alertmanager-config.md) | Routing tree, matchers, timing parameters, inhibition, silences, time intervals, receivers, templates, amtool |
| [`kubernetes-monitoring.md`](kubernetes-monitoring.md) | kube-prometheus-stack install, all CRDs with copy-paste YAML, RBAC, cardinality controls |
| [`slo-and-burn-rates.md`](slo-and-burn-rates.md) | SLI/SLO/error budget maths, the burn-rate table, copy-paste rule template, policy template |
| [`commands.md`](commands.md) | promtool, amtool, kubectl, curl/API, docker — every command used in this course |
| [`glossary.md`](glossary.md) | 90 terms, one line each |

## How to use them

Cheatsheets are for **recall**, not for learning. Read the topic README first, do the lab, then use these when you're writing real config and can't remember whether it's `group_interval` or `group_wait`.

The three highest-value pages, if you only print three:
1. **`promql.md`** — you will use this daily for years.
2. **`alertmanager-config.md`** §"timing parameters" — the source of most alerting confusion.
3. **`commands.md`** §"validation" — the four commands that should be in your CI.
