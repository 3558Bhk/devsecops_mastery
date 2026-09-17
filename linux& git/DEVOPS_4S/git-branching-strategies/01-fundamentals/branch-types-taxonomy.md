# Pattern: Types of branches — the complete taxonomy

Branches are classified by **lifetime**, **purpose**, and **who may push**. Every strategy is a
different selection from this menu.

## 1. By lifetime

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│ PERMANENT (live forever, never deleted)                                     │
│   main / master / trunk   ── the source of truth, always deployable         │
│   develop                 ── GitFlow's integration branch                   │
│   production / staging    ── GitLab Flow's environment branches             │
├─────────────────────────────────────────────────────────────────────────────┤
│ LONG-LIVED (weeks to months)                                                │
│   release/1.4             ── stabilisation + patch line for one version     │
│   support/1.x             ── maintained old major version                   │
├─────────────────────────────────────────────────────────────────────────────┤
│ SHORT-LIVED (hours to 2 days — the goal for every modern team)              │
│   feature/PROJ-123-x      ── one unit of work, deleted after merge          │
│   fix/PROJ-456-y          ── a bug fix                                      │
│   hotfix/urgent           ── emergency production fix                       │
│   experiment/name         ── spike, may be thrown away                      │
└─────────────────────────────────────────────────────────────────────────────┘
```

**The single most important metric in branching:** *branch lifetime.* Long-lived branches accumulate
divergence, and divergence is what produces conflicts, big risky merges and delayed feedback.
DORA's research ties short-lived branches and small batches to elite delivery performance.

```bash
# measure branch age across your repo — the health check most teams never run
git for-each-ref --sort=committerdate refs/heads/ \
    --format='%(committerdate:short) %(refname:short)' | head -20      # oldest first = stale branches
git branch --no-merged main --format='%(committerdate:relative) %(refname:short)'   # unmerged + age
git for-each-ref --format='%(refname:short) %(authorname)' refs/heads | wc -l       # branch count
```

## 2. By purpose

| Branch type | Prefix | Created from | Merged into | Deleted? | Contains |
|---|---|---|---|---|---|
| Mainline / trunk | `main` | — | — | never | only finished, tested, deployable code |
| Integration | `develop` | `main` | `main` (via release) | never (GitFlow) | merged features awaiting release |
| Feature | `feature/`, `feat/` | `main` or `develop` | same | ✅ after merge | one unit of work |
| Bug fix | `fix/`, `bugfix/` | `main` | same | ✅ | non-urgent defect fix |
| Hotfix | `hotfix/` | the **release tag** or `main` | `main` (+ `release/*`, `develop`) | ✅ | urgent production patch |
| Release | `release/1.4` | `main`/`develop` | `main` **and** `develop` | after EOL of that version | stabilisation: version bumps, docs, last fixes |
| Support / maintenance | `support/1.x` | an old release tag | itself only | at EOL | backported security fixes |
| Environment | `staging`, `production` | `main` | never (promotion only) | never | exactly what runs in that env |
| Experiment / spike | `experiment/`, `spike/` | anywhere | usually nowhere | ✅ | throwaway investigation |
| Personal / sandbox | `<username>/`, `wip/` | anywhere | rarely | ✅ | individual WIP |
| Topic (stacked PRs) | `feat/a` ← `feat/b` | another feature branch | the parent | ✅ | a slice of a bigger change |
| Fork branch | in *your* fork | upstream `main` | upstream via PR | ✅ | OSS contribution |

## 3. By protection level (who may push)

```text
┌──────────────────────────────────────────────────────────────────────────┐
│ TIER 1 — PROTECTED, no direct push, no force push, no deletion           │
│   main, production                                                       │
│   → changes only via Pull Request + required reviews + green CI          │
├──────────────────────────────────────────────────────────────────────────┤
│ TIER 2 — PROTECTED, reviews required, force-push allowed for the author  │
│   develop, release/*, staging                                            │
├──────────────────────────────────────────────────────────────────────────┤
│ TIER 3 — OPEN, author-owned                                              │
│   feature/*, fix/*, experiment/*                                         │
│   → force-with-lease after a rebase is normal and expected               │
└──────────────────────────────────────────────────────────────────────────┘
```

```bash
# server-side enforcement on a self-hosted repo
git config receive.denyNonFastForwards true     # forbid force pushes entirely
git config receive.denyDeletes true             # forbid branch deletion
git config receive.denyCurrentBranch refuse     # forbid pushing to the checked-out branch
# GitHub/GitLab: Settings → Branches → protection rules (the practical answer for most teams)
```

## 4. Stacked / chained branches (used for large changes)

```text
   main ──► A ──► B          (PR #1: database schema)
                    \
                     C ──► D (PR #2: API layer, based on PR #1)
                              \
                               E  (PR #3: UI, based on PR #2)
```
```bash
git switch -c api-layer db-schema        # branch FROM another feature branch
git rebase db-schema                     # when the parent changes, rebase the child
git rebase --onto main db-schema api-layer   # after PR #1 merges, re-parent PR #2 onto main
git log --oneline main..HEAD             # only THIS slice's commits should appear
```
Stacked PRs keep each review small. The cost: every parent change forces a rebase cascade. Tools
(`ghstack`, `graphite`, `git-spice`, `spr`) automate it.

## 5. The lifecycle of a healthy short-lived branch

```text
 1. git switch main && git pull              ← always start from an up-to-date trunk
 2. git switch -c fix/PROJ-123-cart-total    ← one ticket, one branch
 3. commit in small steps (5-10 commits is fine)
 4. git fetch && git rebase origin/main      ← stay current daily; resolve conflicts early
 5. git push -u origin fix/PROJ-123-cart-total
 6. open PR → CI → review → address comments
 7. squash-merge or rebase-merge into main
 8. branch auto-deletes (local + remote)     ← if it isn't deleted, it becomes stale
```

```bash
# cleanup routine — run it weekly
git fetch --prune                                        # drop refs for deleted remote branches
git branch --merged main | grep -vE '^\*|main|master|develop' | xargs -r git branch -d
git branch -r --merged main | grep -vE 'main|HEAD' | sed 's|origin/||' | xargs -r -I{} git push origin --delete {}
git for-each-ref --sort=committerdate refs/heads --format='%(committerdate:short) %(refname:short)' | head
```

## Practice

```bash
git for-each-ref --sort=committerdate refs/heads --format='%(committerdate:relative)|%(refname:short)'
# Which branch in your repo is the oldest? How long has it been unmerged?
# That number is your team's real branching-strategy health score.
```
