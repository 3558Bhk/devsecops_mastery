# Pattern: Branch naming conventions & policies

## The standard scheme

```text
<type>/<ticket>-<short-slug>

feature/PROJ-1234-add-coupon-codes     # new functionality
fix/PROJ-2345-cart-total-rounding      # non-urgent bug fix
hotfix/INC-99-payment-outage           # urgent production fix
release/1.5.0                          # stabilisation branch for a version
support/1.4.x                          # maintained old release line
chore/upgrade-node-20                  # maintenance, no user-visible change
refactor/extract-payment-service       # structural change, no behaviour change
docs/update-runbook                    # documentation only
experiment/redis-vs-memcached          # spike; expected to be deleted
wip/alex                               # personal scratch branch
```

## Characters: what is allowed and what breaks things

```bash
git check-ref-format --print "feature/my-branch"   # validate a name; prints it if legal
git check-ref-format "refs/heads/bad@{name" || echo "REJECTED"
```
```text
ALLOWED     letters, digits, . _ - / and a leading @
FORBIDDEN   space, ~ ^ : ? * [ \ , consecutive "..", ".." anywhere, "@{",
            a leading or trailing "/", a trailing ".", a trailing ".lock",
            a name ending in "/", "refs" alone, and control characters
```
**Why it matters practically:**
```bash
git switch feature/x      # if a branch "feature" also exists, Git cannot create "feature/x"
                          # (a ref cannot be both a file and a directory) → "a branch named X already exists"
git log feature..fix      # ".." is range syntax; a branch containing it is ambiguous
rm -rf build/${BRANCH}    # unvalidated branch names become shell-injection vectors in CI
```

## Case sensitivity gotcha (a real production bug source)

```bash
git branch Feature/X && git branch feature/x    # on Windows/macOS these COLLIDE (case-insensitive FS)
git config --get core.ignorecase                # true on macOS/Windows, false on Linux
```
Policy: **lowercase only**, enforced by a hook:
```bash
#!/usr/bin/env bash
# .githooks/pre-push — reject badly named branches before they reach the server
set -euo pipefail
while read -r local sha remote _; do
    name="${remote#refs/heads/}"
    [[ "$name" =~ ^(feature|fix|hotfix|release|chore|docs|refactor|experiment|support)/[a-z0-9._/-]+$ ]] \
      || { echo "branch '$name' does not match the naming policy" >&2; exit 1; }
done
```

## Enforce the convention (in order of effectiveness)

| Layer | How | Blocks bad names? |
|---|---|---|
| Local hook | `.githooks/pre-push` + `core.hooksPath` | only if the dev installed it |
| **Server hook** | `pre-receive` on the Git server | ✅ always |
| Host rules | GitHub/GitLab branch name rulesets | ✅ always |
| CI check | pipeline step validating `GITHUB_HEAD_REF` | ✅ but after the push |
| PR template | asks for ticket link | ❌ social pressure only |

```bash
# CI check example (GitHub Actions)
name="${GITHUB_HEAD_REF}"
echo "$name" | grep -qE '^(feature|fix|hotfix|chore|release)/[A-Z]+-[0-9]+' \
  || { echo "::error::branch must look like feature/PROJ-123-slug"; exit 1; }
```

## Why the ticket number goes in the branch name

```bash
git log --oneline --all --grep "PROJ-1234"          # find work by ticket in messages
git branch -a --list "*PROJ-1234*"                  # ...or by branch name (faster, works after deletion)
git for-each-ref --format='%(refname:short)' | grep -oE '[A-Z]+-[0-9]+' | sort -u | wc -l   # tickets in flight
```
It links code → ticket → deploy → incident, which is what auditors and postmortems need.

## Team policy worth writing down (copy this into your CONTRIBUTING.md)

```text
1. Branch from an up-to-date main. Never branch from another feature unless stacking deliberately.
2. Name: <type>/<TICKET>-<slug>, lowercase, hyphens only.
3. Lifetime: under 2 working days. If longer, split it or hide it behind a feature flag.
4. Size: under ~400 changed lines and under ~20 files in the PR.
5. Rebase onto main daily; squash-merge; delete the branch on merge (automatic).
6. Never force-push main, develop, release/* or production.
7. Every branch must have a ticket; every ticket must name its branch.
```
