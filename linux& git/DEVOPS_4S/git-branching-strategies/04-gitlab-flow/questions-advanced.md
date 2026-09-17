# 04 GitLab Flow — Advanced Questions

**Q1.** Why prefer fast-forward promotion over merge commits on environment branches?
```bash
git merge --ff-only main                     # same hashes on every branch → one history to reason about
git merge --no-ff main -m "promote"          # creates promotion commits → divergence and cherry-pick drift
```
With `--ff-only`, a commit on `production` is *literally the same object* you tested on
`pre-production` and reviewed on `main`. Anything else breaks traceability and makes
`git branch --contains <sha>` ambiguous. If main has moved on, cherry-pick the specific release
commits rather than merging all of main.

**Q2.** How do you answer "what exactly is running in production right now?"
```bash
git describe --tags production               # v1.5.0-3-gabc1234
git log -1 --format='%H %ci %s' production
git tag --points-at production               # is the tip itself a tagged release?
```
Better: record the deployed SHA/digest in the deploy system and query it
(`kubectl get deploy api -o jsonpath='{.spec.template.spec.containers[0].image}'`), then map back
with `git log -1 <sha>`. The branch is intent; the running artefact is truth.

**Q3.** Enforce the one-way flow mechanically.
```bash
# CI guard on the promotion job:
git fetch origin main pre-production production
git log --oneline origin/main..origin/pre-production    # must be EMPTY
git log --oneline origin/pre-production..origin/production   # must be EMPTY
git merge-base --is-ancestor origin/pre-production origin/main || exit 1
```
Plus host protection: production/pre-production pushable only by the deploy identity, no force push,
no deletion. Then the "hotfix straight on production" mistake becomes impossible rather than a policy.

**Q4.** An emergency requires patching production directly. Do it safely.
```bash
git switch production && git cherry-pick -x <emergency-sha> && git push origin production
# then IMMEDIATELY, in the same incident:
git switch main && git cherry-pick -x <emergency-sha> && git push
git switch pre-production && git cherry-pick -x <emergency-sha> && git push
git branch -a --contains <emergency-sha>      # prove all three branches have it
```
Log it as an exception with a ticket, and add a CI check that flags commits present downstream but
absent upstream (see Q3) so it cannot be forgotten.

**Q5.** Release branches AND environment branches together — model it.
```text
main ──► release/1.4 ──► pre-production ──► production ──► tag v1.4.0
                              ▲                  ▲
                        staging soak        prod deploy
```
```bash
git switch -c release/1.4 main                # cut the release line
git switch pre-production && git merge --ff-only release/1.4   # promote the RELEASE, not main
git switch production && git merge --ff-only pre-production
git tag -a v1.4.0 -m "release"
git switch main && git merge --no-ff release/1.4 -m "back-merge release fixes"   # or cherry-pick fixes
```
Use this for products with both a scheduled version and staged environments (mobile + backend, on-prem).

**Q6.** How do you handle configuration differences between environments in this model?
**Answer:** never with per-environment code on per-environment branches — that guarantees drift. Use
the same artefact everywhere and vary configuration at runtime: 12-factor config (env vars/secret
store), Helm values per environment, kustomize overlays, or Spring profiles. The branch model
promotes *immutable artefacts*; config is injected.

**Q7.** Compare GitLab Flow's promotion with progressive delivery.
| | GitLab Flow branches | Progressive delivery |
|---|---|---|
| Gate mechanism | merge into `production` | traffic shifting / canary analysis |
| Rollback | revert + redeploy | instant weight shift to previous version |
| Env fidelity | staging ≈ prod | real prod traffic at low % |
| Best for | regulated promotion, separate infra | high-volume services with good telemetry |
They compose well: promote to `production` by branch, then roll out 1% → 10% → 100% with Argo Rollouts/Flagger.

**Q8.** Why do some teams abandon environment branches?
**Answer:** because with immutable artefacts + infrastructure as code, an environment is a *deployment
target*, not a *branch*. GitLab's own later guidance treats environment branches as one option among
several. If your staging and prod differ only by config, promoting an artefact (image digest) is
simpler and safer than promoting a branch — fewer refs, no drift, one history.
