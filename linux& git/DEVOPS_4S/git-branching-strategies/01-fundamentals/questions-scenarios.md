# 01 Fundamentals — Scenario Questions

## Scenario 1
Your repo has 240 local branches and nobody knows which are alive. Clean it up.
```bash
git fetch --prune                                     # drop refs for branches deleted upstream
git for-each-ref --sort=committerdate refs/heads \
  --format='%(committerdate:short)|%(refname:short)|%(authorname)' > /tmp/branches.csv   # inventory
git branch --merged main | grep -vE '^\*|main|master|develop' | xargs -r git branch -d   # safe deletes
git branch --no-merged main --format='%(refname:short) %(committerdate:relative)' | head -20   # the risky ones
# for each unmerged branch: ask the author, then either merge it, archive it as a tag, or delete it
git tag archive/old-experiment <hash> && git branch -D old-experiment    # archive instead of deleting
git push origin --delete old-experiment                                  # and remove the remote copy
```
Then prevent recurrence: auto-delete branches on merge (host setting), a weekly cleanup job, and a
branch-lifetime policy.

## Scenario 2
Two developers created `feature` and `feature/login`, and now pushes fail with a D/F conflict.
```bash
git show-ref | grep feature            # confirm both refs exist
git branch -m feature feature/misc     # rename the parent-less one out of the way
git push origin :refs/heads/feature    # delete the offending remote ref
git fetch --prune
```
Prevention: forbid branch names that are prefixes of namespaces (`feature`, `release`, `fix`) in a
server hook or host ruleset.

## Scenario 3
A teammate force-pushed a shared feature branch and your local copy diverged. Recover.
```bash
git fetch origin
git log --oneline --graph --all -15                    # see both histories
git reflog show origin/feature/x | head                # what the remote ref was before their push
git branch rescue-my-work feature/x                    # save YOUR local work first
git reset --hard origin/feature/x                      # adopt their version
git cherry -v origin/feature/x rescue-my-work          # which of your commits are missing?
git cherry-pick <hash> <hash>                          # re-apply the ones that are
git branch -D rescue-my-work
```
Prevention: `--force-with-lease` in team guidelines, and protection on any branch two people share.

## Scenario 4
You need to know whether a 3-week-old feature branch will conflict before asking for a rebase.
```bash
git fetch origin
git rev-list --left-right --count origin/main...origin/feature/x    # how far apart are they?
git merge-tree --write-tree origin/main origin/feature/x >/dev/null 2>&1 && echo CLEAN || echo CONFLICT
git merge-tree --write-tree --name-only origin/main origin/feature/x   # conflicted files, if any
git diff --name-only origin/main...origin/feature/x > /tmp/theirs.txt
git diff --name-only $(git merge-base origin/main origin/feature/x) origin/main > /tmp/mains.txt
comm -12 <(sort /tmp/theirs.txt) <(sort /tmp/mains.txt)   # files BOTH sides touched = conflict candidates
```
`git merge-tree` predicts conflicts without touching your working tree, so this is safe to run in CI
and post as a PR comment.

## Scenario 5
A stale branch from 8 months ago must be deleted, but you need to keep evidence for an audit.
```bash
git log --oneline main..old-branch                     # what unique work does it hold?
git cherry -v main old-branch                          # did any of it land via cherry-pick/squash?
git tag archive/2026-01-old-branch old-branch          # freeze it as a tag (cheap, permanent)
git push origin archive/2026-01-old-branch             # publish the tag so the evidence survives
git branch -D old-branch && git push origin --delete old-branch
```
Tags are the right archival mechanism: immutable, cheap, and they don't clutter the branch list.

## Scenario 6
CI needs to build only the services changed in a PR, but shallow clones break `merge-base`.
```bash
git fetch --depth=50 origin main                 # deepen enough to contain the branch point
BASE=$(git merge-base origin/main HEAD) || git fetch --unshallow    # fall back if still too shallow
git diff --name-only "$BASE"...HEAD              # three-dot: changes on the PR side only
git clone --filter=blob:none <url>               # better: partial clone keeps full history, no blobs
```

## Scenario 7
Your team wants to enforce "no branch older than 5 days" without policing people manually.
```bash
# weekly CI job:
git for-each-ref --format='%(committerdate:unix) %(refname:short)' refs/remotes/origin \
 | while read -r ts name; do
     age=$(( ( $(date +%s) - ts ) / 86400 ))
     [ "$age" -gt 5 ] && echo "STALE ($age d): $name"
   done | tee stale-branches.txt
# post the list to Slack; auto-comment on the open PR; never auto-delete other people's work
```

## Scenario 8
You must apply one commit to three long-lived release branches.
```bash
git log --oneline -1 main                       # note the fix commit hash
for b in release/1.3 release/1.4 release/1.5; do
    git switch "$b" && git pull --ff-only
    git cherry-pick -x <hash> || { echo "conflict on $b"; git cherry-pick --abort; }
    git push origin "$b"
done
git switch main
```
`-x` records "(cherry picked from commit …)" so you can trace which releases contain the fix —
essential during a security audit.
