# 06 Release & Hotfix — Scenario Questions

## Scenario 1
`release/1.4` has been "stabilising" for 5 weeks and is 300 commits behind main.
```bash
git rev-list --count release/1.4.0..main         # how far it has drifted
git log --oneline release/1.4.0..main | head -20 # what landed since the cut
git diff --shortstat release/1.4.0 main          # size of the divergence
```
Decide: (a) ship what you have — the scope was too big, cut smaller next time; (b) re-cut the release
from current main if nothing has actually been tested against the old cut; (c) merge main in
deliberately (`git merge main`) accepting a re-test cycle. Prevention: time-box stabilisation to days,
enforce a release size budget, and use flags so trunk is always releasable.

## Scenario 2
A customer reports a crash in v1.3.2. You are on v1.6. Reproduce, fix, and ship to both.
```bash
git switch -c repro/v1.3.2 v1.3.2                # reproduce on the customer's exact version
# confirm the bug still exists on trunk:
git switch main && git log --oneline -S"<suspect function>" -- src/ | head   # has it changed since?
git switch -c fix/crash-1234 main                # author the fix on trunk, with a regression test
git commit -am "fix(core): guard nil page in renderer"
# backport:
git switch support/1.3.x && git cherry-pick -x <sha> && git tag -a v1.3.3 -m "crash fix"
git push origin support/1.3.x --follow-tags
git tag --contains <sha>                          # prove coverage
```

## Scenario 3
Two teams cut `release/1.5` from main at different times and now both exist.
```bash
git log --oneline --graph --all --decorate -20    # see the duplication
git rev-parse release/1.5 origin/release/1.5      # are they the same ref?
git log --oneline origin/release/1.5..release/1.5 # local-only commits
```
Resolve: pick one (usually the one CI already built), rename the other
(`git branch -m release/1.5 release/1.5-teamB`), and add a CI rule that refuses to create
`release/*` branches — only the release pipeline may.

## Scenario 4
A version bump commit landed on `main` and now every release branch conflicts on `package.json`.
```bash
git switch release/1.5 && git cherry-pick -x <sha>
# conflict in package.json → resolve by keeping the release line's version:
git checkout --ours package.json && git add package.json && git cherry-pick --continue
```
Prevention: never commit version bumps by hand on trunk. Use `semantic-release`/`release-please` so
versions are computed at release time on the release artefact, and add `package.json` to a
`merge=ours` driver or exclude version files from backports.

## Scenario 5
You must produce an audit report: every security fix in the last year and which versions contain it.
```bash
git log --since="1 year ago" --oneline -i -E --grep="CVE|security" --all > sec-commits.txt
while read -r sha _; do
    printf '%s  tags: %s\n' "$sha" "$(git tag --contains "$sha" | tr '\n' ' ')"
done < sec-commits.txt > sec-coverage.txt
git branch -a --list 'release/*' 'support/*'      # the supported lines to check against
```
Cross-reference with your support matrix; any supported line missing a fix is an open risk item with
an owner and a date.

## Scenario 6
The release train leaves in 2 hours and a feature is 90% done.
```bash
# the answer is NO — it misses the train. Make that safe and cheap:
git switch main && git log --oneline release/1.5..main | head   # confirm it is not on the release branch
# the feature stays on trunk behind a flag and ships in train 1.6
```
If the business insists, the only safe route is: merge it to trunk **flagged off**, then cherry-pick to
`release/1.5` with the flag off, and enable it post-release. Never merge unfinished work into a release
branch — that is how "stabilisation" becomes six weeks.

## Scenario 7
A tag was pushed pointing at the wrong commit and CI already published artefacts for it.
```bash
git show v1.5.0 --stat                       # confirm the wrong target
git ls-remote --tags origin | grep v1.5.0    # what the remote has
git tag -d v1.5.0 && git push origin :refs/tags/v1.5.0     # delete everywhere
git tag -a v1.5.0 <correct-sha> -m "release 1.5.0" && git push origin v1.5.0
# BUT: anyone who fetched it keeps the old tag:
git fetch --tags --force                     # tell every consumer and CI runner to do this
```
If artefacts were already distributed, the clean answer is to abandon `v1.5.0` and release `v1.5.1` —
mutating a published tag breaks reproducibility for everyone who cached it.

## Scenario 8
Design the release automation for a product with 3 supported versions and weekly security patches.
```text
1. Trunk: main, trunk-based, flags for incomplete work, deploy continuously to SaaS.
2. Cut: CI creates release/X.Y from main on the train date, bumps version, opens a release PR.
3. Stabilise: only cherry-picks with a "release/X.Y" label; CI rejects feature commits.
4. Ship: tag vX.Y.0 → build ONE immutable artefact → promote the same digest through staging → prod.
5. Patch: security fixes authored on main, auto-backported by a bot to all supported release/* lines,
   each producing vX.Y.Z+1 and its own artefact.
6. Guard: nightly job asserts every release/* commit exists in main (no lost fixes) and reports
   branch age, drift, and EOL dates.
7. Retire: at EOL, tag vX.Y-EOL, delete the branch, remove it from the support matrix and the bot.
```
Metrics: lead time from fix to patched release per version, % CVEs patched within SLA, number of
supported lines, and drift between release branches and main.
