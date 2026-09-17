# Pattern: GitLab Flow — main + environment/release branches (promotion model)

GitLab Flow (2014) fixes the two things GitHub Flow ignores: **you usually have more than one
environment**, and **you often cannot deploy to production the instant code merges**. It adds
*downstream* branches that code is **promoted** into — never developed on.

## Variant A — Environment branches (the most common)

```text
                     ┌── feature/a ──┐
                     │               ▼
 main        ──●─────●───────────────●──────●──────●──►   merge = "ready to ship"
 (development)                     merge   merge
                     │               │      │
                     ▼               ▼      ▼        (cherry-pick or fast-forward promotion)
 pre-production ─────●───────────────●──────●──────►   deployed to staging, soak-tested
                                     │      │
                                     ▼      ▼
 production ─────────────────────────●──────●──────►   deployed to customers
                                     ▲      ▲
                                  tag v1.4  tag v1.5

 RULE: commits flow ONE WAY →→→ (main → pre-production → production).
       You never commit directly to pre-production or production.
       A fix made downstream must be merged/cherry-picked BACK UP to main first.
```

## Variant B — Release branches (for versioned software)

```text
 main  ──●───●───●───●───●───●───●───●───●───●──►  ongoing development
              \           \           \
               ▼           ▼           ▼
        release/1.3   release/1.4   release/1.5      stabilise + patch, one per version
           │  │           │  │
        v1.3.0 v1.3.1  v1.4.0 v1.4.1                 patch releases live on the release branch
```
Only bug fixes go into a `release/*` branch, and every one of them is **cherry-picked back to main**.

## Variant C — Upstream first (forks / OSS / vendor patches)

```text
 your fork:  feature/x ──► your-main ──► PULL REQUEST ──► upstream/main
 rule: never build on top of an unmerged change; upstream first, then your fork.
```

## Command walkthrough (Variant A)

```bash
# ---------- develop as usual ----------
git switch main && git pull --ff-only
git switch -c feat/PROJ-123-invoices
git commit -am "feat(billing): invoice PDF export"
git push -u origin feat/PROJ-123-invoices
gh pr create --base main --fill               # PR targets MAIN only

# ---------- promote to pre-production ----------
git switch pre-production && git pull --ff-only
git merge --ff-only main                      # preferred: fast-forward, so hashes are identical
# if main has diverged (it usually has), cherry-pick the release commit(s) instead:
git cherry-pick -x <sha>..<sha>
git push origin pre-production                # CI deploys to staging here
git tag -a rc-2026-09-15 -m "release candidate"   # optional: mark the candidate

# ---------- promote to production ----------
git switch production && git pull --ff-only
git merge --ff-only pre-production            # or cherry-pick the same commits
git push origin production                    # CI deploys to prod
git tag -a v1.5.0 -m "release 1.5.0" && git push origin v1.5.0

# ---------- a hotfix found IN production ----------
# WRONG: committing straight to production
# RIGHT: fix it upstream, then promote it down
git switch main && git switch -c fix/PROJ-999-pdf-crash
git commit -am "fix(billing): null page in PDF export"
git push && gh pr create --base main --fill   # review + CI on main first
# then promote the fix down through pre-production → production as above
```

## The "upstream first" rule for fixes (the part people get wrong)

```text
   production ──X── never commit here directly
        ▲
        │ promote down (merge/cherry-pick)
   pre-production
        ▲
        │ promote down
      main  ◄── ALL fixes are authored here (or on a feature branch off main)
```
```bash
# if you MUST patch production first (outage, no time):
git switch production && git cherry-pick -x <emergency-sha>
git switch main && git cherry-pick -x <emergency-sha>     # IMMEDIATELY bring it upstream
git switch pre-production && git cherry-pick -x <emergency-sha>
git branch -a --contains <emergency-sha>                  # prove all three have it
```
Otherwise the next promotion from main **reverts your production fix** — the classic GitLab Flow bug.

## Enforce one-way flow with CI

```bash
# in the promotion job: fail if this is not a fast-forward of the upstream branch
git fetch origin main pre-production
git merge-base --is-ancestor origin/pre-production origin/main \
  || { echo "pre-production contains commits not in main — refuse to promote"; exit 1; }
git log --oneline origin/main..origin/pre-production      # should be empty
```
Plus branch protection: `pre-production` and `production` allow pushes only from CI (a deploy token
or a protected environment), never from a human.

## Mermaid version

```mermaid
gitGraph
   commit id: "c1"
   branch feature/a
   commit id: "a1"
   checkout main
   merge feature/a id: "PR merged"
   branch pre-production
   checkout pre-production
   merge main id: "promote → staging"
   branch production
   checkout production
   merge pre-production id: "promote → prod" tag: "v1.5.0"
```

## Trade-offs

| Pros | Cons |
|---|---|
| Models real environments and approval gates | Commits exist on several branches → cherry-pick drift risk |
| Works where deploy ≠ merge (regulated, on-prem, mobile) | `production` branch can lag; "what's live?" needs tags to answer |
| Clear promotion audit trail | More branches to protect and monitor |
| Fits both SaaS and versioned releases | Fix-flow discipline (upstream first) must be enforced mechanically |

## When to choose it

```text
✓ You have staging/pre-prod/prod and promotion is a deliberate act
✓ Compliance requires separation of duties (developer cannot deploy to prod)
✓ You ship both a SaaS product and versioned/on-prem releases
✓ Mobile apps with store review delays (main → release → production)
✗ Single environment, continuous deploy, small team → GitHub Flow or trunk-based is simpler
```
