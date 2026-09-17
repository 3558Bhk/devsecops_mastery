# 07 Stash & Tags — Scenario Questions

## Scenario 1
You are halfway through a feature when a P1 production bug lands. Switch context safely.
```bash
git status -s                          # see what is in flight
git stash push -u -m "wip: search filters"   # -u so your new files come along too
git switch main && git pull            # clean, current main
git switch -c hotfix/p1-checkout-crash
# ...fix, commit, push, PR...
git switch feature/search-filters      # back to your feature
git stash pop                          # resume exactly where you stopped
```

## Scenario 2
You stashed three days ago and now `git stash pop` conflicts with everything.
```bash
git stash list --date=local            # how old are the stashes?
git stash show -p stash@{2} --stat     # inspect before applying
git stash branch wip-recover stash@{2} # apply it on its ORIGINAL base commit — usually conflict-free
git switch feature/x && git merge wip-recover   # then merge it into your current work
```

## Scenario 3
You ran `git stash clear` and lost work you needed.
```bash
git fsck --unreachable | grep commit   # dropped stashes survive as unreachable commits
git show <hash> --stat                 # identify the right one by its files
git stash apply <hash>                 # bring it back
```
This works only until Git's garbage collector runs (default: ~2 weeks for unreachable objects).

## Scenario 4
Ship release v1.5.0 properly, with a tag everyone can trust.
```bash
git switch main && git pull            # 1. up-to-date main
npm test                               # 2. green build
git tag -a v1.5.0 -m "release 1.5.0"   # 3. annotated tag on the release commit
git push origin main --follow-tags     # 4. publish branch and tag together
git log --oneline v1.4.0..v1.5.0 --no-merges --pretty='* %s'   # 5. changelog text
```
Then create the GitHub/GitLab Release from `v1.5.0` and paste the changelog.

## Scenario 5
A critical security bug is found in production, which runs v1.4.0 — but main has moved on.
```bash
git fetch --tags
git switch -c hotfix/1.4.1 v1.4.0      # branch from the deployed tag, not from main
# ...apply the minimal fix, test...
git commit -am "fix(security): validate redirect URL"
git tag -a v1.4.1 -m "security patch"  # tag the patched release line
git push origin hotfix/1.4.1 --follow-tags
git switch main && git cherry-pick <fix-hash>   # port the fix forward so it isn't lost
```

## Scenario 6
A tag was created on the wrong commit and already pushed.
```bash
git show v1.2.0 --stat                 # confirm it points at the wrong commit
git tag -d v1.2.0                      # delete locally
git tag -a v1.2.0 -m "release 1.2.0" <correct-hash>   # recreate on the right commit
git push origin :refs/tags/v1.2.0      # delete the remote tag
git push origin v1.2.0                 # push the corrected one
```
Tell the team to run `git fetch --tags --force`, and prefer releasing `v1.2.1` if anyone already built from it.

## Scenario 7
You need to test a colleague's branch but your working tree is dirty and you don't want to stash.
```bash
git fetch origin
git worktree add ../review origin/feature/x   # a second folder on their branch — your tree untouched
cd ../review && npm ci && npm test
cd - && git worktree remove ../review         # clean up afterwards
```

## Scenario 8
Your CI build number should reflect Git state, not a hard-coded string.
```bash
VERSION=$(git describe --tags --always --dirty)     # v1.4.0-12-ga1b2c3d or ...-dirty
COMMIT=$(git rev-parse --short HEAD)                # short hash for the artefact name
BRANCH=$(git rev-parse --abbrev-ref HEAD)           # current branch
echo "$VERSION $BRANCH $COMMIT"                     # e.g. v1.4.0-12-ga1b2c3d main a1b2c3d
```
In CI, fetch tags first (`git fetch --tags --depth=1`) or `describe` will fail on a shallow clone.

## Scenario 9
You want to keep a long-running experiment without polluting your stash list.
```bash
git switch -c experiment/weird-idea    # a branch is a better home than a stash for anything lasting
git add -A && git commit -m "wip: experiment"   # commit freely — you can squash it later
git switch main                        # main stays clean
git log --oneline experiment/weird-idea -3      # the work is always there
```
Rule of thumb: stash is for minutes or hours; a WIP branch is for days.

## Scenario 10
Someone asks "what exactly is running in production right now?"
```bash
git tag --points-at $(git rev-parse origin/main)   # is HEAD tagged as a release?
git describe --tags origin/main                    # nearest tag + distance: v1.4.0-3-gabc1234
git log -1 --format='%H %ci %s' v1.4.0             # the exact commit and date of that release
ssh prod 'cat /app/VERSION'                        # and compare with what the server reports
```
