# Pattern: Choosing a branching strategy (and migrating between them)

## The decision tree

```text
                        ┌───────────────────────────────────┐
                        │ Do you deploy to production       │
                        │ continuously and automatically?   │
                        └──────────────┬────────────────────┘
                       NO ◄────────────┴────────────► YES
                        │                                │
        ┌───────────────▼──────────────┐   ┌─────────────▼──────────────────┐
        │ Do you ship VERSIONED        │   │ Do you have feature flags and  │
        │ artefacts customers install  │   │ CI under ~10 minutes?          │
        │ and stay on for years?       │   └───────┬────────────────────────┘
        └──────┬───────────────────────┘     NO ◄──┴──► YES
          YES ◄┴► NO                          │          │
           │    │                    ┌────────▼───┐  ┌───▼──────────────────┐
           │    │                    │ GitHub Flow│  │ TRUNK-BASED          │
           │    │                    │ (build the │  │ DEVELOPMENT          │
           │    │                    │  safety net│  │ (the elite-performer │
           │    │                    │  first)    │  │  default)            │
           │    │                    └────────────┘  └──────────────────────┘
           │    │
           │    └──► Do you have MULTIPLE environments with
           │         mandatory promotion/approval gates?
           │              YES ──► GITLAB FLOW (environment branches)
           │              NO  ──► GITHUB FLOW + release tags
           │
           └────► Do you maintain SEVERAL versions in parallel?
                    YES ──► GITFLOW or trunk + release/* patch lines
                    NO  ──► trunk + release tags (simplest)
```

## The comparison matrix

| Criterion | GitFlow | GitHub Flow | GitLab Flow | Trunk-Based | Release Train |
|---|---|---|---|---|---|
| Long-lived branches | main + develop | main | main + env branches | trunk | trunk + release/* |
| Branch count | highest | lowest | medium | lowest | medium |
| Deploy frequency | weeks–months | many/day | daily–weekly | many/day | fixed cadence |
| Lead time to prod | long | short | medium | shortest | fixed |
| Merge-conflict risk | **high** | low | medium | lowest | medium |
| CI/CD maturity needed | low | **high** | high | **very high** | medium |
| Feature flags needed | no | recommended | no | **mandatory** | recommended |
| Multiple versions supported | **yes** | no | yes | yes (patch lines) | **yes** |
| Regulated promotion / separation of duties | partly | no | **yes** | no | yes |
| Works with weak tests | yes | risky | risky | **no** | yes |
| Auditability of "what shipped" | high (tags+branches) | medium (needs deploy tags) | **high** | medium (needs tags) | **high** |
| Team discipline required | medium | medium | medium | **high** | medium |
| Best fit | versioned products, mobile, on-prem | SaaS/web | multi-env, regulated, mobile+SaaS | high-performing platform teams | enterprise, scheduled releases |

## Score your own repo (do this before answering the interview question)

```bash
# 1. deploy frequency proxy: merges to the trunk per week
git log --first-parent --since="3 months" --oneline main | wc -l
# 2. branch lifetime (are branches short-lived?)
git for-each-ref --sort=committerdate refs/remotes/origin --format='%(committerdate:short) %(refname:short)' | head -10
# 3. PR/commit size (are batches small?)
git log --since="3 months" --pretty='%H' main | while read -r h; do git show --shortstat --oneline "$h" | tail -1; done | head -20
# 4. release cadence
git tag -l --sort=-creatordate --format='%(creatordate:short) %(refname:short)' | head -10
# 5. how much divergence exists between long-lived branches
git rev-list --left-right --count origin/main...origin/develop 2>/dev/null
# 6. revert/hotfix rate (change-failure proxy)
git log --since="6 months" --oneline -i -E --grep="revert|hotfix" main | wc -l
# 7. do you have flags?
grep -rEl "flags?\.(enabled|isOn|get)|FEATURE_|launchdarkly|unleash" src/ 2>/dev/null | head
```
Read the results: many merges/day + small commits + flags → trunk-based is available to you.
Few merges + huge commits + no flags → you must invest in CI, flags and deployment safety first.

## Migration playbooks

### GitFlow → Trunk-Based (the most common request)

```text
PHASE 0  Prerequisites (do NOT skip): CI < 10 min · deploy from main automated · rollback tested ·
         feature-flag service in place · branch protection + required checks on main
PHASE 1  Stop adding to develop; new features branch from main
PHASE 2  Shrink the gap: merge develop into main incrementally, feature by feature
PHASE 3  Collapse: git switch main && git merge --no-ff develop
PHASE 4  Delete develop (after a soak period), keep release/* only for patch lines
PHASE 5  Enforce: branch-age alert, PR-size gate, flag-expiry reports, merge queue
```
```bash
git rev-list --count main..develop              # measure the gap; drive it to zero
git switch main && git merge --no-ff develop -m "absorb develop into main"
git push origin main
git branch -d develop && git push origin --delete develop    # LAST, and only after a soak period
```

### Trunk-Based → add release lines (for an on-prem customer)

```bash
git tag -a v2.0.0 <trunk-sha> -m "on-prem release"
git switch -c release/2.0 v2.0.0                # patch line only — no new features
# security fixes: author on trunk, cherry-pick -x down to release/2.0
```

### GitHub Flow → GitLab Flow (adding environments)

```bash
git switch -c pre-production main && git push -u origin pre-production
git switch -c production main     && git push -u origin production
# protect both: CI-only pushes; promotion via merge --ff-only or cherry-pick
```

## The anti-patterns to name in an interview

```text
✗ "We do GitFlow" but deploy continuously from main → you do GitHub Flow with an unused develop
✗ Trunk-based in name only: branches live 3 weeks → you have GitFlow's risk without its structure
✗ A develop branch nobody can explain → delete it or document it
✗ Environment branches that people commit directly to → drift and "works in staging" incidents
✗ Force-pushing shared branches as a routine → protection rules, --force-with-lease, merge queues
✗ Release branches used for new development → stabilisation never ends
✗ Choosing a strategy because a blog post said so, not because of your deploy capability
```

## The interview answer template

```text
"We use <STRATEGY> because <DEPLOY CAPABILITY + RELEASE MODEL>.
 Concretely: <BRANCHES>, PRs of <SIZE>, merged by <POLICY>, deployed <CADENCE>.
 The main trade-off we accept is <COST>, which we mitigate with <FLAG/QUEUE/CI/AUTOMATION>.
 Where it doesn't fit — <SPECIAL CASE, e.g. on-prem patch lines> — we use <HYBRID>.
 I'd measure success with <DORA METRICS + branch age + PR cycle time>."
```
