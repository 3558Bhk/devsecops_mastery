# 06 Release & Hotfix — Advanced Questions

**Q1.** How do you guarantee a release-branch fix is never lost?
```bash
# CI guard, run on every push to main and on a schedule:
for b in $(git branch -r --list 'origin/release/*' | tr -d ' '); do
    missing=$(git log --oneline "$b" --not origin/main | wc -l)
    [ "$missing" -gt 0 ] && echo "NOT FORWARD-PORTED: $b ($missing commits)"
done
git cherry -v origin/main "$b"        # + means "this patch is not upstream"
```
Better still: author every fix on trunk and cherry-pick **down** to release branches — then
"forward-porting" cannot be forgotten because the direction is already correct.

**Q2.** Automate backporting across N supported versions.
```bash
# label-driven (GitHub): a "backport release/1.4" label triggers a workflow that runs:
git switch release/1.4 && git cherry-pick -x "$SHA" && git push origin release/1.4
gh pr create --base release/1.4 --title "backport: $TITLE" --body "Cherry-pick of #$PR"
# conflicts → the workflow posts a comment asking for a manual backport; it never silently drops one
```

**Q3.** Support matrix design — how many versions should you maintain?
```text
N (latest)      — features + fixes
N-1             — security + critical fixes
N-2             — security only, or EOL
```
Each extra supported line multiplies CVE cost by one backport+test+release cycle. Publish EOL dates,
enforce them, and make the cost visible. If customers refuse EOL, that is a commercial conversation
(paid extended support), not a Git problem.

**Q4.** A CVE requires patching 6 versions in 24 hours. Plan it.
```bash
# 1. fix on trunk first, with a test that proves the vulnerability is closed
git switch main && git switch -c fix/CVE-2026-1234 && git commit -am "fix(security): CVE-2026-1234"
# 2. backport in parallel (one engineer per line, or a bot)
for b in release/1.6 release/1.5 release/1.4 support/1.3; do
  git switch "$b" && git cherry-pick -x <sha> && git tag -a "v$(ver $b)" -m "security" &
done; wait
# 3. verify coverage, then publish advisories
git tag --contains <sha>
# 4. coordinate disclosure timing, notify customers, and rotate anything exposed
```
State the constraint that matters: **never** develop the fix directly on the oldest branch and try to
merge upward — that reverts newer work.

**Q5.** Should release branches be merged back to main, or cherry-picked?
| | Merge back | Cherry-pick forward |
|---|---|---|
| History | merge commit, full context | linear, one commit per fix |
| Risk | can accidentally bring release-only changes (version bumps) into main | misses a fix if someone forgets |
| Tooling | simple `git merge --no-ff release/1.4` | needs discipline/automation |
**Answer:** merge back for GitFlow-style releases (where the release branch may contain many fixes);
cherry-pick forward for trunk-based patch lines (where fixes are authored on trunk anyway). Never do
both for the same change — you get duplicate commits and confusing conflicts.

**Q6.** Version bumping: manual, scripted, or fully automated?
```bash
# fully automated from Conventional Commits:
npx semantic-release --dry-run          # computes next version + changelog from commit types
npx release-please release-pr            # opens a release PR (Google's approach)
# deterministic derivation from Git alone:
git describe --tags --always --dirty     # v1.4.0-12-gabc1234-dirty
```
Automate it. Manual version bumps are the most common source of "two releases with the same version"
and "the tag doesn't match the artefact" incidents. In CI, refuse to build if
`git describe --dirty` reports a dirty tree.

**Q7.** How do you support "customer A is on 1.4.2 with a custom patch"?
**Answer:** you don't — that's a fork, and forks are unmaintainable. Convert the customisation into
configuration, a plugin, or an upstream feature behind a permission flag. If contractually forced,
maintain `support/1.4-customerA` as an explicit, priced, EOL-dated line with its own CI, and treat
every upstream security fix as a cherry-pick onto it. Track the number of such branches as technical
debt with a cost attached.

**Q8.** Release branch vs release tag vs artefact promotion — which is the best model?
```text
tag + artefact promotion (BEST): tag the trunk, build an immutable artefact once, promote the SAME
  artefact through environments. One history, no drift, "what is in prod" is a digest.
release branch (NEEDED when): the version requires ongoing patches after release, or stabilisation
  takes long enough that trunk keeps moving past it.
```
Senior answer: prefer tags + immutable artefacts; use release branches only for maintained patch lines.
