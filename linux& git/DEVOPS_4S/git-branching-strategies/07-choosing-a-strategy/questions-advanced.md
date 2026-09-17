# 07 Choosing a Strategy — Advanced Questions

**Q1.** "Strategy must match deploy capability, not ambition." Justify with examples.
**Answer:** A team that deploys monthly by hand cannot benefit from trunk-based development: every
merge to trunk carries a month of accumulated risk, so they will (rationally) batch into long branches
and reintroduce GitFlow by accident. Conversely a team with 20 deploys/day, flags and canaries gains
nothing from a `develop` branch — it only delays feedback and manufactures conflicts. The evidence base
(DORA/Accelerate) links short-lived branches and small batches to elite performance, but *only* where
CI/CD and observability already exist.

**Q2.** Your org has 12 teams. Do you mandate one strategy?
**Answer:** Mandate the **invariants**, not the model: short-lived branches, protected trunk, PR size
limits, required checks, tags for every release, no force-push to protected branches, and DORA
measurement. Let teams choose GitFlow/GitLab/trunk within those guardrails based on their release
model. A hard mandate fails where release models genuinely differ (SaaS team vs firmware team).

**Q3.** How do you handle a repo that must serve both continuous SaaS and versioned on-prem?
```bash
# trunk-based for SaaS + patch lines for on-prem — the hybrid
git tag -a v2.4.0 <sha> -m "on-prem GA"
git switch -c release/2.4 v2.4.0                 # security/critical fixes only
# SaaS deploys from trunk continuously; on-prem ships from release/2.4 tags
```
One codebase, two release mechanisms. The rule that keeps it sane: features go to trunk only;
`release/*` receives cherry-picks and nothing else.

**Q4.** Compare the risk profile of each model in one line each.
```text
GitFlow       → risk accumulates in develop and detonates at the release merge
GitHub Flow   → risk lands in production immediately; mitigated by flags, canaries and fast rollback
GitLab Flow   → risk is staged; mitigated by soak time, cost is cherry-pick drift between branches
Trunk-Based   → risk lands immediately but is tiny per change; mitigated by flags + small batches
Release Train → risk is time-boxed; cost is latency (features wait for the next train)
```

**Q5.** What breaks first when you adopt a model without the supporting practices?
| Adopted without | First failure |
|---|---|
| Trunk-based, no flags | unfinished work blocks releases → long branches return |
| Trunk-based, slow CI | batching → broken trunk → everyone waits |
| GitHub Flow, no rollback | a bad merge becomes an incident with no exit |
| GitFlow, no back-merge automation | release fixes regress in the next version |
| GitLab Flow, no one-way-flow guard | environment branches drift; staging ≠ prod |
| Any model, no branch protection | someone force-pushes main and destroys work |

**Q6.** How do you evaluate a proposed change of strategy?
```bash
# 1. baseline metrics for 4 weeks
git log --first-parent --since="4 weeks" --oneline main | wc -l      # integrations
git log --since="4 weeks" --oneline -i --grep=revert main | wc -l    # reverts (change-failure proxy)
gh pr list --state merged --json createdAt,mergedAt,additions > prs.json   # cycle time, size
# 2. pilot with one team for 6-8 weeks; 3. re-measure; 4. roll out with automation, not exhortation
```
Include a rollback plan for the process change itself, and publish the numbers.

**Q7.** Where do feature flags stop being a good idea?
**Answer:** when they multiply combinatorially (n flags = 2ⁿ states), when they are never retired
(flag debt becomes unreadable code), when they hide security-relevant behaviour, or when they are used
to avoid a hard conversation about scope. Mitigations: flag registry with owners and expiry, CI that
fails on flags older than N days, both-states testing only for changed areas, and periodic deletion
sprints. Flags are for *release* control, not for permanent code branching.
