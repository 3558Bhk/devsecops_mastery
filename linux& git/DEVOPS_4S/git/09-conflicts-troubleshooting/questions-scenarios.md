# 09 Conflicts & Troubleshooting — Scenario Questions

## Scenario 1
Merging `feature` into `main` produces conflicts in 9 files, and you have 30 seconds of confidence left.
```bash
git status                              # see the full list of unmerged files
git diff --name-only --diff-filter=U    # just their names
git merge --abort                       # it is perfectly fine to retreat and plan first
git config --global merge.conflictStyle zdiff3   # show the base version in future conflicts
git config --global rerere.enabled true          # remember resolutions you make now
git merge feature                       # try again, better equipped
```

## Scenario 2
`package-lock.json` conflicts on every single merge and nobody knows what is correct.
```bash
git checkout --ours package-lock.json   # the content does not matter — it is generated
npm install                             # regenerate it from package.json
git add package-lock.json
git merge --continue
npm ci && npm test                      # verify the tree is consistent
```
Then prevent it permanently with `.gitattributes` plus a defined `merge=npm` driver.

## Scenario 3
You resolved a conflict, committed, and the app no longer builds — you probably deleted a marker line.
```bash
git diff HEAD~1 -- src/app.js           # review what the resolution actually changed
grep -rn "<<<<<<<\|>>>>>>>" src/        # any leftover markers?
git diff --check HEAD~1                 # Git's own leftover-marker check
git reset --hard HEAD~1                 # undo the bad merge commit (if not pushed)
git merge feature                       # redo it carefully
```

## Scenario 4
`git pull` says "fatal: refusing to merge unrelated histories".
```bash
git log --oneline -3                    # your local history
git fetch origin && git log --oneline origin/main -3   # the remote's history
git pull origin main --allow-unrelated-histories       # merge the two roots
# resolve any conflicts, commit, then push
```
This happens when a repo was created both locally (`git init`) and on the host ("add a README").

## Scenario 5
Git says "Another git process seems to be running... unable to create index.lock".
```bash
ps aux | grep -v grep | grep git        # is a Git process genuinely running? WAIT for it
ls -l .git/index.lock                   # check the lock file's age
rm .git/index.lock                      # remove it ONLY if no git process is alive
git status                              # confirm the repo is usable again
```
Deleting the lock while another process runs can corrupt the index.

## Scenario 6
Your editor crashed mid-commit and now the repo seems stuck mid-merge.
```bash
git status                              # tells you exactly which operation is in progress
git merge --continue                    # resume the merge with the prepared message
git rebase --continue                   # ...or whichever operation it reports
git merge --abort                       # or start over
ls .git/MERGE_HEAD .git/rebase-merge .git/CHERRY_PICK_HEAD 2>/dev/null   # the raw state files
```

## Scenario 7
A colleague's branch will not check out: "pathspec did not match any file(s)".
```bash
git branch -a                           # is the branch visible locally?
git fetch --prune origin                # refresh the remote-tracking branches
git switch their-branch                 # Git auto-creates a local branch tracking origin/their-branch
git switch --track origin/their-branch  # the explicit form
git ls-remote --heads origin | grep their   # does it exist on the remote at all?
```

## Scenario 8
CI passes on the PR but fails after merging into main. Reproduce it locally.
```bash
git fetch origin
git switch -c integration-test origin/main      # start from the real main
git merge --no-ff origin/feature/x              # reproduce the exact merge
npm ci && npm test                              # run the same steps CI runs
git log --oneline --graph -5                    # confirm the shape matches CI's
git merge --abort 2>/dev/null; git switch main  # clean up
```

## Scenario 9
The repository grew to 3 GB and cloning takes 20 minutes.
```bash
git count-objects -vH                            # current size
git verify-pack -v .git/objects/pack/*.idx | sort -k3 -n | tail -10   # the biggest blobs
git log --all --diff-filter=A --name-only --pretty=format: -- "*.zip" | sort -u | head  # who added archives
pip install git-filter-repo
git clone --mirror <url> repo.git && cd repo.git
git filter-repo --strip-blobs-bigger-than 20M     # drop the heavy blobs from all history
git push --force --mirror                          # publish, then have the team re-clone
```
Prevention: keep binaries in Git LFS or an artefact store, and add them to `.gitignore`.

## Scenario 10
Everything is broken and you need to get back to a known-good state fast.
```bash
git status && git log --oneline -5                 # where am I and what happened
git reflog | head -15                              # the last 15 things HEAD did
git stash list                                     # is unsaved work sitting here?
git branch backup-now                              # snapshot the current state before touching anything
git reset --hard <known-good-hash>                 # go back to a commit you trust
git fsck --lost-found                              # find anything dangling afterwards
```
Order matters: **reflog → backup branch → then act.** Almost nothing in Git is unrecoverable
as long as it was committed.
