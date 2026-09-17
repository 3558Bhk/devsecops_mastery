# 08 Interview Scenarios — Scenario Questions (mock interview drills)

Each drill: read the situation, answer out loud in 60 seconds using PICK → JUSTIFY → TRADE-OFF → ADAPT,
then check the model answer.

## Drill 1
**Interviewer:** "Tell me about a branching strategy you used and why."
```text
PICK      Trunk-based with short-lived branches and squash merges.
JUSTIFY   ~20 deploys/day from main, CI ~8 min, everything risky behind a flag, branches < 1 day.
TRADE-OFF Flags are debt; we mitigate with owners, expiry tickets and a CI age check.
ADAPT     On-prem customers get release/X.Y patch lines with cherry-pick -x backports.
```
Then draw the trunk diagram. Follow-ups to prepare: PR size, rollback, protection rules, metrics.

## Drill 2
**Interviewer:** "You join a team and find 40 remote branches, 3 of them long-lived, no docs."
```bash
git for-each-ref --sort=-committerdate refs/remotes/origin --format='%(committerdate:short)|%(refname:short)' | head -20
for b in $(git branch -r --format='%(refname:short)' | grep -v HEAD); do
  printf '%-45s unique:%-5s last:%s\n' "$b" "$(git rev-list --count origin/main..$b)" "$(git log -1 --format=%cs $b)"
done
git log --oneline --graph --all -30
```
**Model answer:** classify (active / release line / stale / abandoned) → archive abandoned ones as tags
→ delete after confirming with authors → write a one-page model → encode it in branch protection and CI
→ re-measure in 30 days. Say: "the CI check is the documentation; a wiki page decays in a month."

## Drill 3
**Interviewer:** "Production is down and the last deploy is suspected. Walk me through it."
```bash
# 1. stop the bleeding (fastest first)
#    flag off (seconds) → redeploy previous artefact (minutes) → revert commit (minutes)
git revert --no-edit <sha> && git push                 # forward fix, never reset --hard on main
git revert -m 1 --no-edit <merge-sha>                  # if the culprit was a merge commit
# 2. confirm: error rate, deploy timeline, feature-flag changes, config changes, dependency releases
# 3. post-incident: what check would have caught it? add it to CI as a required gate
```
**Senior signal:** you ask "what changed?" across *all* change types (code, flags, config, infra,
dependencies) and you separate mitigation from root cause.

## Drill 4
**Interviewer:** "We're a 3-person team with a mobile app and a backend API. One strategy for both?"
```text
Backend: trunk-based, deploy from main, flags + progressive rollout.
Mobile:  trunk-based + release/X.Y branches cut for store submission (external review constraint),
         staged rollout 1%→100%, patch lines for installed versions, forced-update policy for EOL.
Shared:  contract tests between them; API versioning so mobile can lag the backend safely.
```
**Trade-off:** mobile cannot roll back the fleet → extra investment in staged rollout and kill
switches. **Adapt:** if the API ships breaking changes, use expand/contract so old app versions keep
working during the transition.

## Drill 5
**Interviewer:** "Your PR was rejected as 'too big'. It's one atomic change. Defend or fix?"
```bash
git diff --shortstat origin/main...HEAD          # show the real size
git diff --name-only origin/main...HEAD          # is it mostly generated/vendored code?
```
**Model answer:** first check whether the size is *real* (generated code, lockfiles, vendored deps,
migrations) — if so, split those into separate commits/PRs and mark them `linguist-generated`. If the
change is genuinely atomic and large, offer a review strategy: a 10-minute walkthrough of the seam and
invariants, then reviewers read by risk area. Then fix the system: agree a size policy with an
explicit exception path, so "atomic but large" has a documented route instead of an argument.

## Drill 6
**Interviewer:** "How would you introduce trunk-based development to a GitFlow team?"
```bash
git rev-list --count main..develop                 # measure the gap you must close
```
```text
Phase 0  prerequisites: CI < 10 min, deploy from main, tested rollback, flag service
Phase 1  new features branch from main, not develop
Phase 2  drain develop incrementally, feature by feature, behind flags
Phase 3  collapse: git switch main && git merge --no-ff develop
Phase 4  delete develop after a soak period; keep release/* only as patch lines
Phase 5  enforce: branch-age alert, PR-size gate, flag-expiry CI, merge queue
Pilot one team for 6-8 weeks, publish before/after DORA metrics, then roll out.
```
**Trade-off to name:** 1–2 sprints of velocity dip and real platform investment. **Adapt:** teams with
a genuine versioned-artefact product keep release branches — that is not a failure of the migration.

## Drill 7
**Interviewer:** "A vendor patch must go into 4 supported versions within 24 hours."
```bash
git switch main && git switch -c fix/vendor-CVE && git commit -am "fix(deps): bump vendor lib (CVE-2026-1234)"
SHA=$(git rev-parse HEAD)
for b in release/2.4 release/2.3 support/2.2 support/2.1; do
  git switch "$b" && git cherry-pick -x "$SHA" && git tag -a "v$(echo $b | tr -d 'a-z/.')-patch" -m "CVE fix" \
    && git push origin "$b" --follow-tags || echo "MANUAL BACKPORT NEEDED: $b"
done
git tag --contains "$SHA"            # audit evidence
```
**Say:** conflicts get a human immediately, never a silent skip; disclose on a coordinated timeline;
and the long-term fix is fewer supported versions plus automated backport bot PRs.

## Drill 8
**Interviewer:** "Design the branching + release process for a new platform team from scratch."
```text
1. One trunk (main), protected: required reviews, required checks, no force-push, merge queue.
2. Branches < 2 days, PRs < ~400 lines, squash merges, auto-delete.
3. Feature flags for anything not ready; registry with owner + expiry; CI fails on stale release flags.
4. CI < 10 min: affected-only tests, caching, sharding, flaky quarantine with SLAs.
5. Release = tag + ONE immutable artefact, promoted by digest through dev → staging → prod.
6. Patch lines only for versions customers still run; fixes authored on trunk, cherry-pick -x down.
7. Progressive delivery: canary → 10% → 100% with automatic halt on error-budget burn.
8. Metrics published weekly: deploy frequency, lead time, change-failure rate, MTTR, branch age,
   PR cycle time, revert rate, flake rate.
9. Everything above encoded in CI and branch protection — not in a wiki.
```
Close with: "I'd start with 1–3 and 8, because without fast CI and honest metrics the rest is theatre."
