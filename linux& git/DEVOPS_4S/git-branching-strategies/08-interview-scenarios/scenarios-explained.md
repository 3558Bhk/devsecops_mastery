# Interview scenarios explained — 16 worked scenarios with diagrams

Every scenario uses the same 4-part answer structure. Learn the structure and any question becomes easy.

```text
1. PICK      — name a strategy immediately (never say "it depends" first)
2. JUSTIFY   — tie it to deploy capability + release model + team shape
3. TRADE-OFF — state the cost you accept and how you mitigate it
4. ADAPT     — the exception case and your hybrid answer
```

---

## Scenario 1 — "Which branching strategy have you used?"

**What they're testing:** can you describe a real model precisely, or do you only know buzzwords.

**Answer:**
```text
PICK:      "Trunk-based development with short-lived branches and squash merges."
JUSTIFY:   "We deploy to production several times a day from main. CI runs in about 8 minutes,
            every risky change goes behind a feature flag, and branches never live more than a day."
TRADE-OFF: "The cost is that merge is not release — we own flags, and flags become debt, so every
            release flag gets an owner and an expiry ticket the day it is created."
ADAPT:     "For our on-prem customers we cut release/X.Y branches from a tag and cherry-pick security
            fixes down to them. That is the only place we keep long-lived branches."
```

**Diagram to draw (30 seconds, whiteboard):**
```text
main ──●────●────●────●────●────●──►  deploy many times/day
        \  /  \  /  \  /
         ●●    ●●    ●●             branches live < 1 day, deleted on merge
                                     unfinished work: behind a flag, dark in prod
```

**Follow-ups to expect:** How big are your PRs? (~400 lines / 20 files max.) How do you roll back?
(flag off → seconds; revert + redeploy → minutes.) What protects main? (required checks, no
force-push, merge queue.)

**Senior signal:** you mention *measurement* and *guardrails*, not just the model name.

---

## Scenario 2 — "Your team is growing from 5 to 40 engineers. What changes?"

**What they're testing:** do you understand that branching strategy is an organisational design decision.

**Answer:**
```text
PICK:      "Keep the same model (trunk-based) and add mechanical guardrails — do NOT add branches."
JUSTIFY:   "Adding a develop branch to control 40 people just moves the coordination cost into merge
            conflicts. What scales is automation: merge queue, CODEOWNERS, affected-only CI, PR-size
            gates, flaky-test quarantine."
TRADE-OFF: "Investment in CI/CD and platform tooling, and a temporary velocity dip."
ADAPT:     "If teams own independently released products, give each its own trunk or path-scoped
            ownership rather than one shared long-lived integration branch."
```

```text
 5 engineers            40 engineers (WRONG)              40 engineers (RIGHT)
 main ◄──●              main ◄── develop ◄── feat/*        main ◄── merge queue ◄── many short branches
 (talking works)        (bottleneck + conflicts)           + CODEOWNERS + affected-only CI + flags
```

**Senior signal:** "Coordination cost grows with people; you pay it with tooling, not with branches."

---

## Scenario 3 — "A hotfix is needed in production. Walk me through it."

**What they're testing:** speed, safety, and whether you fix forward and backport correctly.

**Answer:**
```bash
git switch main && git pull --ff-only                    # 1. always start from the latest trunk
git switch -c hotfix/PROJ-999-null-order                 # 2. short, obvious name
# 3. reproduce with a FAILING TEST first — this is the part juniors skip
npm test -- --grep "null order"                          # red
# 4. fix, keep the diff tiny
git commit -am "fix(orders): guard null order in total()"
git push -u origin hotfix/PROJ-999-null-order
gh pr create --fill                                      # 5. PR with required checks (fast path)
gh pr merge --squash --delete-branch                     # 6. merge to main
# 7. CI deploys; verify with the canary and the error budget
# 8. backport to any supported patch lines
git tag -a v2.4.1 -m "hotfix PROJ-999" && git push origin v2.4.1
git switch release/2.4 && git cherry-pick -x <sha>       # old supported version
git push origin release/2.4 --follow-tags
git tag --contains <sha>                                 # 9. prove coverage
```

```text
main ──●───●───●(hotfix)───●──►  deployed in minutes
                    └──cherry-pick -x──► release/2.4 ──●──► v2.4.1 (customer still on 2.4)
```

**Critical rule to say out loud:** never fix directly on the old release branch and merge upward —
that reverts newer work.

**Follow-ups:** What if the hotfix conflicts? (`git cherry-pick --abort`, then write a version-specific
fix and link both commits.) What if the deploy makes it worse? (flag off, or revert + redeploy —
never `git reset --hard` on a shared branch.)

---

## Scenario 4 — "Two developers edited the same file. Explain what Git does."

**What they're testing:** do you understand fast-forward vs 3-way merge vs conflict.

**Answer:**
```text
main   ──A──B          (base)
             \
feat   ──A──B──C       (their change)   ← if main has not moved: FAST-FORWARD, no merge commit

main   ──A──B──D       (main moved)
             \
feat   ──A──B──C
       merging C into main = 3-WAY MERGE using base B:
         only C changed the line → auto-merge
         both changed the SAME line → CONFLICT, human decides
```
```bash
git merge-base main feat                     # the common ancestor used by the 3-way merge
git merge-tree --write-tree main feat >/dev/null 2>&1 && echo CLEAN || echo CONFLICT   # predict conflicts (Git 2.38+)
git config --global rerere.enabled true      # remember and replay your conflict resolutions
git log --oneline --graph --all -10          # see the shape
```

**Senior signal:** you mention `rerere`, `git merge-tree` as a pre-flight check, and that rebase
*rewrites* the same conflicts commit by commit (why `rerere` matters most during rebase).

---

## Scenario 5 — "We do GitFlow. Releases take 3 weeks of stabilisation. Fix it."

**What they're testing:** can you diagnose a process problem from symptoms.

**Answer:**
```bash
git rev-list --count main..develop                       # unreleased backlog size
git log --oneline v1.3.0..v1.4.0 --no-merges | wc -l     # commits per release (too many?)
git log --oneline -i --grep="back-merge" --since="6 months" | wc -l   # are fixes flowing back?
git rev-list --left-right --count main...develop         # divergence
```
```text
The loop:  big releases → long stabilisation → develop drifts → painful merges → bigger releases
Break it:  1. shrink release size (smaller trains, more often)
           2. automate back-merges (CI job fails when release fixes are absent from develop/main)
           3. add feature flags so main is always releasable
           4. only THEN collapse develop: git switch main && git merge --no-ff develop
```
**Trade-off to name:** deleting `develop` first just relocates the pain. Sequence matters.

**Senior signal:** you identify the feedback loop, and you sequence the fix instead of prescribing a
model swap on day one.

---

## Scenario 6 — "main is broken. 40 engineers are blocked. What do you do?"

**Answer (in this exact order):**
```bash
git log --oneline -8                                  # 1. what landed
git revert --no-edit <sha> && git push                # 2. REVERT FIRST — restore green
# 3. tell the team; 4. investigate with the author; 5. re-land with the missing test
git log --oneline --since="2 hours" --first-parent main   # anything landed on top? revert newest first
```
```text
restore green  ►  communicate  ►  diagnose  ►  re-land with a test  ►  systemic fix
                                                        (flaky quarantine, merge queue, faster CI)
```
**What NOT to do:** `git reset --hard` + force-push (rewrites shared history and destroys other
people's work), or leaving main red "while we investigate".

**Senior signal:** "Revert is a forward fix. Never rewrite published history to hide a mistake."

---

## Scenario 7 — "You must support three versions in parallel. Design it."

**Answer:**
```bash
git tag -l 'v*' --sort=-v:refname | head                # what exists
# support matrix: N (features+fixes), N-1 (security+critical), N-2 (security only or EOL)
git switch -c fix/PROJ-1 main                           # author the fix on trunk
git commit -am "fix(auth): token refresh race"
for b in release/2.4 release/2.3 support/2.2; do
  git switch "$b" && git cherry-pick -x <sha> && git push origin "$b" || echo "CONFLICT: $b"
done
git tag --contains <sha>                                # audit evidence
git branch -a --contains <sha>
```
```text
trunk ──●───●(fix)───●──►  v2.5 line
              │
              ├─cherry-pick -x─► release/2.4 ──●──► v2.4.3
              ├─cherry-pick -x─► release/2.3 ──●──► v2.3.7
              └─cherry-pick -x─► support/2.2 ──●──► v2.2.9
```
**Trade-off:** every supported line multiplies CVE cost. Publish EOL dates and enforce them; a bot
auto-opens backport PRs and never silently drops a conflict.

---

## Scenario 8 — "Explain squash vs merge vs rebase merge. Which do you use?"

**Answer:**
| Policy | Result on main | Bisect | History | Revert |
|---|---|---|---|---|
| `--squash` | 1 commit per PR | excellent (1 commit = 1 PR) | cleanest | one revert undoes the PR |
| `--no-ff` merge | merge commit + branch commits | good | noisy, shows real shape | `git revert -m 1 <merge>` |
| rebase merge (FF) | linear, branch commits kept | good | clean but loses PR grouping | per-commit |

```bash
gh pr merge --squash --delete-branch      # our default: linear main, one commit per PR
git revert -m 1 --no-edit <merge-sha>     # how you undo a merge commit if you chose --no-ff
```
**Pick squash** for trunk-based/SaaS (linear history, trivial revert, clean bisect).
**Pick merge commits** when individual commits inside a PR are meaningful (big refactors, GitFlow
release merges) — and remember `-m 1` when reverting.
**Never** rebase or force-push a shared branch; use `--force-with-lease` on your own PR branch only.

---

## Scenario 9 — "You need a feature that takes 3 months. Trunk-based forbids long branches."

**Answer — strangler fig / branch by abstraction:**
```bash
# 1. introduce the seam (no behaviour change) → merge it
git switch -c refactor/billing-interface && git commit -am "refactor: extract BillingProvider"
# 2. add the new implementation, dead code behind a flag → merge it
git switch -c refactor/billing-v2 && git commit -am "feat(billing): v2 provider [flag billing_v2 off]"
# 3. migrate call sites in small PRs → each merges
# 4. progressive rollout: 1% → 10% → 100%, watching the error budget
# 5. delete the legacy path and the flag
git switch -c refactor/billing-cleanup && git commit -am "chore(billing): remove legacy + flag"
```
```text
week 1   week 3        week 6          week 10         week 12
 seam ─► new impl ────► migrate sites ► dark launch ──► cleanup
 (merged) (flagged off)  (many PRs)     (1%→100%)       (flag deleted)
```
**If flags are impossible** (schema changes, hardware): expand/contract migrations —
add column → dual-write → backfill → switch reads → drop old. Still no long branch.

**Senior signal:** you say "merge ≠ release" and describe how each slice stays independently revertable.

---

## Scenario 10 — "A developer force-pushed main and lost commits. Recover."

```bash
git reflog --date=iso | head -30                    # local reflog (only on the machine that had them)
git fsck --lost-found --no-reflogs | head           # dangling commits still in the object store
git cat-file -p <sha>                               # inspect a recovered object
git branch recovery-$(date +%s) <sha>               # pin it before it is garbage-collected
# on the remote host: GitHub/GitLab keep an audit/events log and support-ref recovery; open a ticket fast
```
Prevention (say this):
```bash
# server-side: branch protection → no force push, no deletion; required reviews
# local habit:
git config --global alias.safe-push '!git push --force-with-lease'
git config --global gc.reflogExpireUnreachable 90.days   # keep unreachable objects longer
```
**Senior signal:** recovery is possible but not guaranteed — the real answer is prevention, and you
know exactly which protection settings provide it.

---

## Scenario 11 — "How do you keep staging and production from drifting?"

**Answer (GitLab Flow with a one-way rule):**
```bash
git log --oneline origin/main..origin/production        # MUST be empty — nothing skips the trunk
git merge-base --is-ancestor origin/pre-production origin/main || exit 1
# promotion:
git switch production && git merge --ff-only pre-production && git push origin production
```
```text
main ──●──► pre-production ──(soak)──► production      arrows never point left
        ▲                                    │
        └──── hotfixes land on main, then flow right ───┘
```
**Better than per-environment branches:** build ONE immutable artefact and promote the digest
(`git tag` + registry digest), with configuration in env vars / a config service (12-factor). Branches
per environment duplicate history; artefacts per environment do not.

---

## Scenario 12 — "Review this PR." (they show a 3,000-line diff on a 3-week-old branch)

**Answer:**
```bash
gh pr diff --name-only | wc -l                 # files touched
git diff --shortstat origin/main...HEAD        # insertions/deletions
git log --oneline origin/main..HEAD | wc -l    # commits
git log -1 --format=%cd origin/main            # how stale is the base?
```
```text
Verdict: do not review it as-is.
1. Ask for a split: interface/seam PR, then behaviour PRs, then cleanup PR (stacked if needed).
2. Rebase onto main NOW to surface conflicts early: git rebase origin/main
3. If it cannot be split, review by risk: contracts/DB/schema first, then logic, then tests, then style.
4. Add a mechanical gate so this cannot recur: PR-size check in CI, branch-age alert at 3 days.
```
```bash
git switch -c part1 && git checkout -p                 # interactive: stage only the seam changes
git rebase --onto main part1 part2                     # re-parent a stacked branch
```
**Senior signal:** you fix the *system* (size gate, branch-age alert), not just this PR.

---

## Scenario 13 — "Your CI is flaky, so people merge anyway. What do you do?"

```bash
# quantify it before arguing
gh run list --limit 200 --json conclusion,displayTitle | jq '[.[]|select(.conclusion=="failure")]|length'
git log --oneline --since="1 month" -i --grep=revert main | wc -l   # reverts caused by bad merges
```
```text
1. Quarantine flaky tests: auto-skip + a ticket with an owner and a due date (never delete silently).
2. Split "must pass to merge" (fast, deterministic: unit, contract) from "must pass to deploy"
   (slow: e2e, soak).
3. Add a merge queue so the COMBINED result is tested before landing.
4. Track flake rate as a first-class metric with a budget; burn it and you stop shipping features.
```
**Senior signal:** "A red test that people ignore is worse than no test — it destroys the signal that
the whole model depends on."

---

## Scenario 14 — "Design the branching model for a mobile app with store reviews."

```text
main ──●───●───●───●──►  trunk (continuous integration)
            \
        release/3.2 ──●(rc1)──●(rc2)──●(3.2.0 submitted)──► awaiting store review (days)
                          │                    │
                          │                    └── hotfix/3.2.1 cherry-picked while 3.2 is in review
                          └── nothing else enters: fixes only
```
**Answer:** trunk-based development + release branches that exist because of an *external* constraint
(store review), plus feature flags for anything unfinished, plus staged rollouts (1% → 100%) which
mobile platforms provide natively. Patch lines for versions still installed by users; EOL enforced by
forced-update policy.

**Senior signal:** you identified that the branching model must mirror an external release constraint,
not an internal preference.

---

## Scenario 15 — "Nobody on the team knows which strategy we use. How do you find out and fix it?"

```bash
# forensics — the truth is in the refs
git for-each-ref --sort=-committerdate refs/remotes/origin --format='%(committerdate:short)|%(refname:short)' | head -20
git branch -r | wc -l                                    # total branches
git log --first-parent --oneline --since="3 months" main | wc -l   # integration cadence
git tag -l --sort=-creatordate | head -5                 # release cadence
git log --oneline --graph --all -30                      # the actual shape
```
```text
1. Classify branches: active / release line / stale / abandoned.
2. Write ONE page: the model, branch lifecycle, merge policy, protection rules, who may push where.
3. Encode it: branch protection, PR templates, CI checks (size gate, branch-age alert, one-way flow).
4. Delete the abandoned branches (archive as tags first) — visible clutter teaches the wrong model.
5. Re-measure in 30 days and publish the numbers.
```
**Senior signal:** "Documentation without enforcement decays in a month. The CI check is the document."

---

## Scenario 16 — "Compare GitFlow, GitHub Flow, GitLab Flow and trunk-based in two minutes."

```text
GITFLOW      main + develop + feature/release/hotfix. Built for versioned software with scheduled
             releases and multiple supported versions. Cost: divergence, big-bang merges, slow feedback.
GITHUB FLOW  main + short-lived branches + PR + deploy from main. Built for continuously delivered web
             services. Cost: everything lands in prod, so you need CI, flags and fast rollback.
GITLAB FLOW  GitHub Flow + environment or release branches to model promotion (staging → prod) or
             supported versions, with a strict one-way flow. Cost: cherry-pick drift between branches.
TRUNK-BASED  one trunk, integrate at least daily, branches under 2 days, unfinished work behind flags,
             release branches only to patch old versions. Cost: demands fast CI, flags and discipline.
ONE LINE     GitFlow = versioned & scheduled · GitHub Flow = continuous & simple ·
             GitLab Flow = promoted & regulated · Trunk-based = continuous & disciplined.
```
Then add the senior closer: **"The right answer is whichever one your deploy pipeline can actually
support — the branching model is downstream of your release capability."**
