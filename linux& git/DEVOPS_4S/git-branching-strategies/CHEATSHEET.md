# CHEATSHEET — Git Branching Strategies (one page)

## 1. The 60-second decision matrix

| | GitFlow | GitHub Flow | GitLab Flow | Trunk-Based |
|---|---|---|---|---|
| **Long-lived branches** | `main` + `develop` | `main` | `main` + env/release | `main` (trunk) |
| **Short-lived** | `feature/*`, `hotfix/*` | any branch | any branch | `< 2 days` |
| **Deploy frequency** | weeks–months | many/day | daily–weekly | many/day |
| **Conflict risk** | **high** | low | medium | **lowest** |
| **CI/CD maturity needed** | low | high | high | **very high** |
| **Feature flags** | no | recommended | no | **mandatory** |
| **Multi-version support** | **yes** | no | **yes** | yes (patch lines) |
| **Regulated promotion** | partly | no | **yes** | no |
| **Use when** | versioned product, mobile, on-prem, weak CI | SaaS/web, continuous delivery | multiple environments, compliance, staged rollout | high-performing team, fast CI, flags |
| **Don't use when** | you deploy continuously | you ship versioned artefacts | you have one environment | CI is slow, no flags, no rollback |

```text
ONE LINE EACH
GitFlow      = versioned & scheduled
GitHub Flow  = continuous & simple
GitLab Flow  = promoted & regulated
Trunk-Based  = continuous & disciplined
Release Train= fixed cadence, missed it → wait
```

## 2. The 4-part interview answer

```text
1. PICK       name a strategy immediately — never open with "it depends"
2. JUSTIFY    tie it to deploy capability + release model + team shape
3. TRADE-OFF  the cost you accept, and the mitigation
4. ADAPT      the exception case and your hybrid
CLOSER        "the branching model is downstream of your deploy capability"
```

## 3. Numbers that make you sound senior

```text
branch lifetime  < 1–2 days          PR size          < ~400 lines, < 20 files
CI to merge      < 10 minutes        integrate        ≥ once per dev per day
review turnaround< 1 business day    revert rate      < 15%
supported versions 2–3 (N, N-1, N-2 security only)
```

## 4. Daily commands

```bash
git switch main && git pull --rebase                 # sync with the trunk (linear)
git switch -c feat/PROJ-123-thing main               # create a branch (switch uses -c, NOT -b)
git push -u origin feat/PROJ-123-thing               # publish + set upstream
gh pr create --draft --fill                          # open the PR on DAY ONE
git rebase origin/main                               # re-sync daily
git push --force-with-lease                          # safe force-push to YOUR branch only
gh pr merge --squash --delete-branch                 # merge + auto-delete
git switch -                                          # previous branch
git branch --merged main | grep -vE 'main|master'    # branches safe to delete
git push origin --delete old-branch                  # delete on the remote
```

## 5. Inspect / diagnose a repo

```bash
git log --oneline --graph --all --decorate -20        # the actual shape of the model
git for-each-ref --sort=-committerdate refs/remotes/origin --format='%(committerdate:short)|%(refname:short)' | head
git log --first-parent --since="1 month" --oneline main | wc -l     # integration cadence
git rev-list --left-right --count origin/main...origin/develop      # divergence both ways
git rev-list --count main..develop                                  # unreleased backlog
git diff --shortstat origin/main...HEAD                             # PR size
git merge-base main feat                                            # the common ancestor
git merge-tree --write-tree main feat >/dev/null 2>&1 && echo CLEAN || echo CONFLICT   # predict conflicts (2.38+)
git tag -l --sort=-creatordate --format='%(creatordate:short) %(refname:short)' | head
git log --since="1 month" -i --grep=revert --oneline main           # change-failure proxy
git describe --tags --always --dirty                                # build stamp
```

## 6. Releases & hotfixes

```bash
git switch -c release/1.4.0 main                     # cut a release branch
npm version 1.4.0-rc.1 --no-git-tag-version && git commit -am "chore(release): 1.4.0-rc.1"
git tag -a v1.4.0 -m "release 1.4.0"                 # ANNOTATED tag (not lightweight)
git push origin release/1.4.0 --follow-tags
git log --oneline v1.3.0..v1.4.0 --no-merges --pretty='* %s (%an)' > RELEASE-NOTES.md
git log v1.3.0..v1.4.0 --no-merges --grep 'BREAKING CHANGE' -p      # breaking changes
# hotfix an old version — ALWAYS fix on trunk first, then cherry-pick DOWN:
git switch release/1.4 && git cherry-pick -x <trunk-fix-sha>        # -x records provenance
git tag -a v1.4.3 -m "security fix" && git push origin release/1.4 --follow-tags
git tag --contains <sha>                             # proof of coverage across versions
git branch -a --contains <sha>
git tag -a v1.4-EOL -m "end of support" && git push origin --delete release/1.4   # retire a line
```

## 7. Rollback ladder (fastest first)

```bash
# 1. flag OFF            (seconds, no deploy)
# 2. redeploy previous artefact by digest   (minutes, no code change)
git revert --no-edit <sha> && git push                    # 3. forward fix (minutes)
git revert -m 1 --no-edit <merge-sha> && git push         # 4. undo a MERGE (mainline = 1)
# 5. roll forward (fix + ship) when reverting is riskier
# 6. NEVER reset --hard + force-push a shared branch
git reflog --date=iso | head                              # recover if someone did 6 anyway
git fsck --lost-found --no-reflogs | head                 # dangling commits
git branch recovery-$(date +%s) <sha>                     # pin it before gc
```

## 8. Guardrails to configure once

```bash
git config --global pull.rebase true                      # keep the trunk linear
git config --global rebase.autoStash true                 # stash around rebases
git config --global rerere.enabled true                   # replay conflict resolutions
git config --global init.defaultBranch main
git config --global merge.conflictstyle zdiff3            # shows the merge base in conflicts
git config --global gc.reflogExpireUnreachable 90.days    # longer recovery window
```
Server-side: branch protection (no force-push, no delete), required reviews, required status checks,
merge queue, signed commits/tags, CODEOWNERS, and a one-way-flow CI check for environment branches:
```bash
git log --oneline origin/main..origin/production          # must be empty
git merge-base --is-ancestor origin/pre-production origin/main || exit 1
```

## 9. Flag types (trunk-based essential)

```text
RELEASE flag     hides unfinished work    short-lived (days)   MUST be removed → expiry ticket
OPS flag         kill switch / degrade    long-lived           owned by SRE
EXPERIMENT flag  A/B assignment           lives as long as the experiment
PERMISSION flag  per-customer entitlement permanent, it IS the product
```
```bash
grep -rn "flags.enabled(" src/ | wc -l                    # flag inventory
grep -rn "new_coupon_ui" src/                             # every reference before deleting one
```

## 10. Anti-patterns (name these and you sound senior)

```text
✗ "We do GitFlow" but deploy from main continuously → you do GitHub Flow with an unused develop
✗ Trunk-based in name only: branches live 3 weeks → GitFlow's risk without its structure
✗ A develop branch nobody can explain → document it or delete it
✗ Committing directly to environment branches → drift, "works in staging" incidents
✗ Fixing on an old release branch and merging UP → reverts newer work
✗ Routine force-push to shared branches → protection + --force-with-lease + merge queue
✗ Release branches used for new development → stabilisation never ends
✗ Choosing a strategy from a blog post, not from your deploy capability
✗ Never retiring flags → hundreds of dead code paths
✗ Reviewing 3,000-line PRs → review theatre; add a size gate instead
```

## 11. Migration cheat (GitFlow → trunk-based)

```text
P0 prerequisites  CI < 10 min · auto-deploy from main · tested rollback · flag service
P1                new features branch from main, not develop
P2                drain develop incrementally, behind flags
P3                git switch main && git merge --no-ff develop
P4                delete develop after a soak period; keep release/* only as patch lines
P5                enforce: branch-age alert, PR-size gate, flag-expiry CI, merge queue
```

## 12. File map of this course

```text
01-fundamentals/            branch = a ref, FF vs 3-way merge, taxonomy, naming conventions
02-git-flow/                main + develop + feature/release/hotfix, git-flow tooling
03-github-flow/             one main, PRs, deploy on merge, flags, non-Git requirements
04-gitlab-flow/             environment / release / upstream-first variants, one-way promotion
05-trunk-based-development/ daily integration, flags, small batches, merge queues, DORA
06-release-hotfix/          release trains, semver, patch lines, cherry-pick backports, EOL
07-choosing-a-strategy/     decision tree, comparison matrix, scoring your repo, migrations
08-interview-scenarios/     16 worked scenarios, 8 drills, 60 rapid-fire answers
DIAGRAMS.md                 every diagram (ASCII primary + mermaid)
README.md                   where to start
```
