# 02 GitFlow — Advanced Questions

**Q1.** Why is the release back-merge into `develop` mandatory, and what breaks without it?
```bash
git switch main    && git merge --no-ff release/1.4.0 && git tag -a v1.4.0 -m x
git switch develop && git merge --no-ff release/1.4.0     # ← skip this and you regress
```
Bug fixes made during stabilisation exist only on `release/1.4.0`. Without the back-merge, the next
release cut from `develop` silently **reintroduces every one of those bugs**. Same for hotfixes —
this is the single most common GitFlow production incident.

**Q2.** How do you automate GitFlow so nobody forgets the back-merge?
```bash
# CI job on merge to main from release/* or hotfix/*:
git switch develop && git pull
git merge --no-ff "$MERGE_COMMIT" -m "back-merge $TAG" || { git merge --abort; exit 1; }
git push origin develop
git tag -a "$TAG" -m "$TAG" && git push origin "$TAG"
git push origin --delete "$RELEASE_BRANCH"
```
Better: encode the whole flow as a pipeline stage (`release`, `backmerge`, `tag`, `cleanup`) so the
process is code, not a wiki page.

**Q3.** `develop` is 400 commits ahead of `main`. What does that tell you, and what do you do?
```bash
git rev-list --count main..develop         # size of the unreleased backlog
git log --oneline main..develop | head -20 # what is waiting
git diff --shortstat main develop          # lines of unreleased change = unreleased RISK
```
A large gap means work is not reaching users — the definition of delayed feedback. Options: ship a
release now; adopt feature flags so code can merge to main dark; or move to trunk-based delivery.
Track `main..develop` distance as a health metric.

**Q4.** Two hotfixes are needed for customers still on v1.2 while you are developing v1.5. Model it.
```bash
git switch -c support/1.2.x v1.2.9        # long-lived maintenance branch from the old tag
# fix, test, release 1.2.10
git tag -a v1.2.10 -m "security fix"
git switch main && git cherry-pick -x <fix-hash>   # port the fix FORWARD to current development
git switch develop && git cherry-pick -x <fix-hash>
```
Support branches are a legitimate GitFlow extension. The rule: fixes flow **forward** by
cherry-pick, never by merging an old branch into main (which would revert newer work).

**Q5.** How do you keep `develop` deployable when features are half-finished?
```js
// option A: feature flags — merge complete-but-disabled code
if (flags.enabled('new-checkout')) { ... }
# option B: branch by abstraction — new implementation behind an interface, switched later
# option C: don't merge until done (the GitFlow default) — costs integration risk
```
Senior answer: flags + branch-by-abstraction, because "don't merge until done" is exactly what
creates the big-bang merge that GitFlow is criticised for.

**Q6.** Squash or `--no-ff` for features merging into develop?
```bash
git merge --squash feature/x && git commit -m "feat: …"    # linear develop, one commit per feature
git merge --no-ff feature/x -m "merge feature/x"           # preserves the feature's internal history
```
`--squash` makes `develop` readable and each commit independently revertable, at the cost of losing
per-commit authorship. Most teams squash features and `--no-ff` the release/hotfix merges (so the
release bubble is visible in `main`).

**Q7.** GitFlow with monorepo and multiple independently deployable services — does it work?
**Answer:** poorly. A single `develop` forces all services to release together. Fixes: per-service
release branches (`release/payments/1.4`), path-scoped CI, or split the repo. If services deploy
independently, they should branch independently — otherwise GitFlow becomes a coordination bottleneck.

**Q8.** How do you audit "which releases contain this security fix"?
```bash
git tag --contains <fix-hash>                     # every tag that includes the commit
git branch -a --contains <fix-hash>               # every branch that includes it
git log --all --oneline --grep "cherry picked from <hash>"   # cherry-picked copies (-x leaves a trail)
```
This is why `cherry-pick -x` matters in a GitFlow/multi-version world.

**Q9.** What happens if a release branch lives for three weeks and develop keeps moving?
```bash
git switch release/1.4.0
git merge develop            # bring in fixes made on develop since the cut (careful: re-opens scope)
git rebase develop           # or replay the release branch (rewrites hashes; avoid if shared)
git log --oneline develop..release/1.4.0    # what the release actually contains
```
Best practice: keep release branches SHORT (days). If stabilisation takes weeks, the feature set was
too big — cut smaller releases, or cherry-pick only the specific fixes you need rather than merging
all of develop.
