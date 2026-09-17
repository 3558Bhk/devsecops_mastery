# 08 Rebase & Advanced — Scenario Questions

## Scenario 1
Your PR has 23 commits: "wip", "fix", "oops", "fix again". The reviewer asks you to tidy up.
```bash
git fetch origin
git log --oneline origin/main..HEAD        # confirm these 23 are all yours and unpushed elsewhere
git branch backup-before-squash            # safety net: instant undo point
git rebase -i origin/main                  # mark the first as pick, the rest as squash/fixup
# write one clear message, save, then:
git log --oneline origin/main..HEAD        # should be 1 (or a few logical) commits
git push --force-with-lease                # publish the rewritten branch
git branch -D backup-before-squash         # delete the backup once you are happy
```

## Scenario 2
A production bug must be fixed on `release/1.4`, but you already fixed it on `main`.
```bash
git log --oneline -5 main                  # find the fix commit's hash
git switch release/1.4                     # go to the release branch
git cherry-pick -x <fix-hash>              # -x records where it came from
git log --oneline -2                       # verify it landed
git push origin release/1.4
git tag -a v1.4.1 -m "patch release" && git push origin v1.4.1   # tag the patched release
```

## Scenario 3
Something broke in the last two weeks and nobody knows which commit did it.
```bash
git log --oneline --since="3 weeks ago" | wc -l   # how many suspects?
git bisect start HEAD v1.4.0                      # bad = now, good = last known-good release
git bisect run npm test                           # let Git binary-search using your test suite
git bisect reset                                  # it names the culprit commit, then clean up
git show <culprit>                                # read what changed
git revert <culprit>                              # undo it safely on a shared branch
```
~1000 commits need only about 10 steps.

## Scenario 4
A 500 MB video was committed last month and every clone is now enormous.
```bash
git count-objects -vH                             # current repo size
git log --all --oneline --diff-filter=A -- "*.mp4"   # find when it was added
pip install git-filter-repo
git clone --mirror <url> repo-mirror && cd repo-mirror   # rewrite a mirror copy, not your working repo
git filter-repo --strip-blobs-bigger-than 100M    # remove every blob over 100 MB
git push --force --mirror                         # publish the rewritten history
```
Then everyone must **re-clone** (not pull), and the host may need to run its own GC.

## Scenario 5
You rebased and now the conflict markers look backwards — "HEAD" shows main's code.
```bash
git status                                        # you are mid-rebase
cat conflicted.js                                 # <<<<<<< HEAD = the NEW BASE (main)
                                                  # >>>>>>> your-commit = the change being replayed
```
Decide per hunk, then:
```bash
git add conflicted.js
git rebase --continue                             # or git rebase --skip to drop this commit
git rebase --abort                                # or give up entirely — nothing is lost
```

## Scenario 6
Your feature branch is 60 commits behind main and you want a clean, linear result.
```bash
git config --global rerere.enabled true           # so repeated conflicts are remembered
git fetch origin
git switch feature && git rebase origin/main      # resolve conflicts once; rerere replays the rest
git rerere status                                 # see what was auto-resolved
npm test                                          # verify the rebased result actually works
git push --force-with-lease
```

## Scenario 7
You need to move only the last two commits of a branch onto a different base.
```bash
git log --oneline -5 feature                      # identify the boundary commit
git rebase --onto release/1.4 feature~2 feature   # replay feature~2..feature onto release/1.4
git log --oneline -3                              # verify only those two commits moved
```

## Scenario 8
A secret was committed and pushed. Full incident response.
```bash
git log --all --oneline -S"AKIA1234567890"        # find every commit containing it
# 1. ROTATE THE CREDENTIAL NOW — assume it is compromised
printf 'AKIA1234567890ABCDEF==>REDACTED\n' > expressions.txt
pip install git-filter-repo
git filter-repo --replace-text expressions.txt    # redact it from all history
git push --force --all && git push --force --tags
# 2. everyone re-clones; 3. add a pre-commit secret scanner (gitleaks/trufflehog) to CI
```

## Scenario 9
Split one commit that mixed a bug fix with an unrelated refactor.
```bash
git rebase -i HEAD~1                              # mark the commit "edit"
git reset HEAD~1                                  # unstage all of its changes
git add src/auth.js && git commit -m "fix(auth): reject expired tokens"
git add src/utils/ && git commit -m "refactor(utils): extract date helpers"
git status -s                                     # confirm nothing is left behind
git rebase --continue
git log --oneline -3                              # two clean commits instead of one mixed one
```

## Scenario 10
You want to try a risky history rewrite without any chance of losing work.
```bash
git clone --no-local . ../experiment              # a full local clone to experiment in
cd ../experiment && git rebase -i HEAD~10         # do whatever you like here
git log --oneline --graph                         # inspect the result
cd - && rm -rf ../experiment                      # throw it away, or copy the recipe back
```
Even simpler: `git switch -c try-it` first, so your real branch is never touched.
