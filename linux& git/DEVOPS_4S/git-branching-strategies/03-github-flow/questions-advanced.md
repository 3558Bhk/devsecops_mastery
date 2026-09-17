# 03 GitHub Flow — Advanced Questions

**Q1.** GitHub Flow assumes continuous deploy. What if you deploy weekly?
**Answer:** then you are not doing GitHub Flow — you are doing an unlabelled release train, and you
will accumulate risk in `main` between deploys. Either (a) make deploy continuous, (b) add
`release/*` branches and a stabilisation window, or (c) use calendar-versioned tags to mark what
actually shipped. Say this in an interview: *"the strategy must match your deploy capability, not
your aspiration."*

**Q2.** Without a `develop` branch, how do you integrate half-finished work?
```js
// feature flags in code
if (flags.enabled('new-checkout')) { newCheckout() } else { legacyCheckout() }
# branch by abstraction: both implementations behind one interface
# config-driven kill switch + gradual rollout (1% → 10% → 100%)
```
This is the crux: GitHub Flow pushes the integration problem from *branching* into *runtime flags*.
Without flags, teams regress to long-lived branches and lose the model's benefit.

**Q3.** 30 PRs merge to main daily. Two were green independently but break together. Fix it.
```bash
# a MERGE QUEUE serialises integration and tests the combined result
gh api repos/:owner/:repo/branches/main -q '.protection'   # check protection config
```
Enable the host's merge queue (GitHub merge queue, GitLab merge trains, Bors). It builds the
*prospective* merge result of several PRs before allowing any to land. Combine with:
`git config --global pull.rebase true`, required "branch up to date" only if it doesn't stampede,
and fast CI so queue throughput is high.

**Q4.** How do you keep history useful when squash-merging everything?
```bash
git log --oneline -20                        # one line per PR = one deployable change (good for bisect)
git revert <squash-commit>                   # one command undoes a whole feature (good for rollback)
```
Trade-offs: you lose intermediate commits and per-commit authorship (`git blame` attributes
everything to the merger — mitigate with `Co-authored-by:` trailers, which GitHub adds
automatically on squash). For changes where intermediate steps matter (big refactors), use rebase-merge.

**Q5.** How do you trace which production version corresponds to which commit?
```bash
git tag -a deploy-2026-09-15.1 <sha> -m "deployed to prod"   # CI tags every deploy
git tag -l 'deploy-*' --sort=-creatordate | head -5
git describe --tags                          # v2026.09.15-12-gabc1234
```
Deploy tags (or an immutable image digest recorded in the deploy log) are what let you answer
"what was running at 03:00?" during an incident.

**Q6.** A PR has been open 9 days with 40 review comments. What is the systemic problem?
**Answer:** the PR is too big and was opened too late. Fix: open Draft PRs on day one for early
feedback, split into stacked PRs (`git switch -c part2 part1`), enforce a size budget in CI
(`git diff --shortstat origin/main...HEAD`), and track PR cycle time as a team metric. Long-open PRs
are a leading indicator of future merge pain.

**Q7.** How do you handle a database migration in GitHub Flow (schema and code deploy separately)?
```text
expand → migrate → contract:
1. PR A: add the new column/table, dual-write (backwards compatible) → deploy
2. PR B: backfill data (idempotent job) → run
3. PR C: read from the new schema → deploy behind a flag
4. PR D: remove the old column and dual-write code → deploy later
```
Every step is independently deployable and reversible, so no long-lived branch is needed. This is the
"expand/contract" (parallel-change) pattern — a strong senior answer.

**Q8.** What do you do when main is broken despite required checks?
```bash
git log --oneline -5                        # what landed
git revert --no-edit <sha> && git push      # revert first, investigate second
```
Then the systemic fixes: flaky-test quarantine, faster feedback, canary/progressive delivery, an
automatic "revert on SLO burn" pipeline, and a blameless postmortem on *the gate that let it through*.
