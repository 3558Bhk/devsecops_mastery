# 04 GitLab Flow — Scenario Questions

## Scenario 1
A fix landed on `production` two weeks ago and nobody upstreamed it. Staging now regressed.
```bash
git log --oneline origin/main..origin/production          # commits downstream but not upstream
git log --oneline origin/pre-production..origin/production
git cherry -v origin/main origin/production               # + = missing upstream
git switch main && git cherry-pick -x <missing-sha>       # bring it up
git switch pre-production && git merge --ff-only main && git push   # re-promote
git branch -a --contains <missing-sha>                    # verify everywhere now
```
Prevention: a scheduled CI job that fails when `main..production` is non-empty.

## Scenario 2
You ship a SaaS from `main` and an on-prem appliance from `release/2.4`. A CVE affects both.
```bash
git switch main && git switch -c fix/CVE-2026-1234        # author the fix upstream FIRST
git commit -am "fix(security): CVE-2026-1234" && git push && gh pr create --base main --fill
# after merge, backport to the supported release lines:
for b in release/2.4 release/2.3; do
  git switch "$b" && git cherry-pick -x <sha> || { echo "conflict on $b"; git cherry-pick --abort; }
  git push origin "$b"
done
git switch release/2.4 && git tag -a v2.4.3 -m "security release" && git push origin v2.4.3
git tag --contains <sha>                                   # prove which releases carry the fix
```

## Scenario 3
Promotion to `pre-production` fails because main has moved since the release candidate was chosen.
```bash
git fetch origin
git log --oneline origin/pre-production..origin/main      # what arrived after the cut
# choose deliberately:
git cherry-pick -x <sha1> <sha2>                          # A) promote ONLY the intended commits
git merge --ff-only <rc-sha>                              # B) promote an exact commit (not main's tip)
git switch -c release/1.5 <rc-sha>                        # C) cut a release branch to freeze scope
```
Never `git merge main` blindly into pre-production — you would ship unreviewed work.

## Scenario 4
Compliance requires proof that what is in production was reviewed and tested.
```bash
git log -1 --format='%H %an %ae %ci' production            # the deployed commit and author
git tag --points-at production                             # the release tag on it
gh pr list --search "<sha>" --state merged --json number,url,reviews   # the PR and its approvals
git notes list production 2>/dev/null; git log -1 --format='%N' production   # audit annotations
```
Best practice: CI writes `git notes add -m "deployed to prod by pipeline #1234, approvals: X,Y"` and
pushes `refs/notes/*`, so audit metadata never rewrites history.

## Scenario 5
A mobile app needs store review (3–7 days) before it can reach users.
```bash
git switch -c release/4.2 main                 # freeze the feature set
# bump version/build number, run full regression, submit to the store from this branch
git tag -a v4.2.0-rc1 -m "submitted to store"
# store rejects it → fix on the release branch only
git commit -am "fix: iOS crash on launch" && git tag -a v4.2.0-rc2 -m "resubmitted"
# approved → promote
git switch production && git merge --ff-only release/4.2 && git tag -a v4.2.0 -m "released"
git switch main && git merge --no-ff release/4.2 -m "back-merge 4.2 fixes"    # don't lose the fixes
```
Meanwhile `main` keeps moving for 4.3 — which is exactly why the release branch exists.

## Scenario 6
Only CI may push to `production`, but a manager asks you to "just push it".
```bash
# refuse politely and use the pipeline:
git switch main && git cherry-pick -x <sha> && git push     # get it reviewed upstream
# then trigger the promotion job (manual gate in CI) rather than pushing by hand
gh workflow run promote-production.yml -f sha=<sha>
```
If the pipeline genuinely cannot run, the exception path is: two-person approval, a recorded
cherry-pick to main in the same hour, and a postmortem item to fix the pipeline. Protecting the branch
is what makes the audit trail trustworthy.

## Scenario 7
`pre-production` and `production` have drifted and nobody knows which is "right".
```bash
git fetch origin
git rev-list --left-right --count origin/pre-production...origin/production   # divergence
git log --oneline origin/production..origin/pre-production   # promoted but never released
git log --oneline origin/pre-production..origin/production   # released but never in staging (!)
# rebuild both from main, which is the only source of truth:
git switch production && git reset --hard <last-known-good-tag> && git push --force-with-lease
git switch pre-production && git reset --hard origin/main && git push --force-with-lease
```
Then add the one-way-flow CI guard so drift is detected in minutes, not months.
