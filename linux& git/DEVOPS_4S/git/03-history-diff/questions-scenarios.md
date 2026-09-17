# 03 History & Diff — Scenario Questions

## Scenario 1
Production broke and you need to know what shipped since the last good release.
```bash
git log v1.4.0..HEAD --oneline            # every commit since the last tag
git diff v1.4.0..HEAD --stat              # which files changed, and how much
git log v1.4.0..HEAD --author=alex --stat # narrow it to one person's work
```

## Scenario 2
A bug appeared "sometime last week". Find the exact commit that introduced it.
```bash
git log --since="10 days ago" --oneline   # list the suspects
git log -S"suspiciousFunction" --oneline  # find commits that added/removed that code
git bisect start                          # or let Git binary-search for you
git bisect bad                            # current version is broken
git bisect good v1.4.0                    # this older version was fine
git bisect run ./run-tests.sh             # automate: Git checks out candidates and runs your test
git bisect reset                          # when it reports the culprit, return to normal
```

## Scenario 3
A junior dev says "I don't know what I changed". Help them see it.
```bash
git status -s                             # which files are modified/untracked
git diff                                  # exactly what changed, line by line
git diff --stat                           # the summary if the diff is huge
git diff -w                               # if it's mostly whitespace, this reveals the real change
git stash                                 # not ready? save the work and get a clean tree
```

## Scenario 4
You must review a colleague's feature branch without their `main`-side noise.
```bash
git fetch origin                          # get the latest remote state
git log --oneline origin/main..origin/feature/login   # only their new commits
git diff origin/main...origin/feature/login           # three dots: their changes since branching
git diff origin/main...origin/feature/login --stat    # file-level summary first
git checkout origin/feature/login -- . 2>/dev/null    # (avoid) prefer a separate clone/worktree:
git worktree add /tmp/review origin/feature/login     # check it out side by side without switching
```

## Scenario 5
Someone deleted an important config file three months ago. Find and restore it.
```bash
git log --diff-filter=D --summary -- config/prod.yml    # find the commit that deleted it
git log --all --full-history --oneline -- config/prod.yml   # every commit that touched it
git show <commit>^:config/prod.yml > config/prod.yml    # restore the version from BEFORE the deletion
git add config/prod.yml && git commit -m "restore prod.yml deleted in <commit>"
```

## Scenario 6
A file was renamed and `git log -- oldname` shows almost nothing.
```bash
git log --follow --oneline -- src/newname.js   # --follow traces history across the rename
git log --diff-filter=R --summary | grep -i newname   # find the rename event itself
git blame -C -M src/newname.js                 # blame through moves and copies
```

## Scenario 7
You need to know who to ask about a specific function.
```bash
git blame -L :calculateTax src/billing.js      # blame just that function's lines
git log -L :calculateTax:src/billing.js --oneline   # every change ever made to that function
git shortlog -sn -- src/billing.js             # who commits most to this file
```

## Scenario 8
Generate release notes between two tags automatically.
```bash
git log v1.4.0..v1.5.0 --no-merges --pretty=format:'* %s (%an)' > RELEASE-NOTES.md
git log v1.4.0..v1.5.0 --no-merges --grep="^feat" --oneline   # only features (Conventional Commits)
git log v1.4.0..v1.5.0 --no-merges --grep="^fix" --oneline    # only bug fixes
git diff v1.4.0..v1.5.0 --shortstat                          # one-line size of the release
```

## Scenario 9
A huge diff is unreadable because of a formatting change. Isolate the real edits.
```bash
git diff -w --stat                          # ignore whitespace: how much actually changed?
git diff -w -- src/app.js                   # the real change in one file
git diff --word-diff -- src/app.js          # word-level highlighting for dense lines
git log --oneline -S"someIdentifier" -- src/app.js   # or trace one identifier's history
```

## Scenario 10
Hand your uncommitted work to a colleague who is on another machine.
```bash
git diff HEAD > wip.patch                   # capture everything uncommitted
git status -s                               # confirm nothing untracked is missing
git ls-files --others --exclude-standard    # list untracked files to send separately
# colleague applies it:
git apply --check wip.patch                 # verify it applies cleanly first
git apply wip.patch                         # then apply it to their working tree
```
