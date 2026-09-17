# Pattern: `cherry-pick`, `bisect`, and other archaeology tools

## `git cherry-pick` — copy a commit from somewhere else

```bash
git cherry-pick a1b2c3d                 # apply that commit's changes onto your current branch
git cherry-pick a1b2c3d e4f5g6h         # several specific commits, in order
git cherry-pick a1b2c3d..e4f5g6h        # a RANGE: everything after a1b2c3d up to e4f5g6h
git cherry-pick a1b2c3d^..e4f5g6h       # inclusive range (a1b2c3d itself included)
git cherry-pick -n a1b2c3d              # -n = no commit: stage the changes so you can adjust them
git cherry-pick -x a1b2c3d              # -x appends "(cherry picked from commit ...)" to the message
git cherry-pick -m 1 <merge-hash>       # cherry-pick a MERGE commit: -m 1 selects the mainline parent
git cherry-pick main                    # copy main's tip commit
git cherry-pick --continue              # after resolving conflicts
git cherry-pick --skip                  # skip this one commit and carry on
git cherry-pick --abort                 # cancel and return to the pre-cherry-pick state
git cherry -v main feature              # list feature's commits not yet in main (+ = not applied)
```

Typical use: a fix committed to `main` that must also land in the `release/1.4` branch.

## `git bisect` — find the breaking commit by binary search

```bash
git bisect start                        # begin the search
git bisect bad                          # the current commit is broken
git bisect good v1.4.0                  # this older commit was known good
# Git now checks out a commit in the middle; test it, then say:
git bisect bad                          # still broken → search the older half
git bisect good                         # works now → search the newer half
git bisect reset                        # finish and return to your original branch
```

Fully automated version:
```bash
git bisect start HEAD v1.4.0            # bad = HEAD, good = v1.4.0
git bisect run ./test.sh                # your script's exit code decides: 0=good, 1-127(but not 125)=bad
git bisect reset                        # clean up when it names the culprit
```
Exit code 125 means "cannot test this commit, skip it". With ~1000 commits, bisect needs only ~10 steps.

## Other archaeology tools

```bash
git log -S"removedFunction" --oneline   # pickaxe: which commit added/removed this string
git log -G"regex" --oneline             # which commit's diff matches this regex
git log -L :funcName:src/app.js         # the full change history of ONE function
git log -L 20,40:src/app.js             # ...or of one line range
git blame -L 20,40 -w -C -M src/app.js  # who last touched these lines (ignoring whitespace/moves)
git reflog                              # every movement of HEAD — your undo history
git fsck --lost-found                   # find dangling commits with no branch pointing at them
git count-objects -vH                   # how much data the repo stores
git verify-commit a1b2c3d               # check a GPG signature
```

## `git replace` and `grafts` — surgery without rewriting

```bash
git replace --edit a1b2c3d              # open an old commit in your editor and rewrite it locally
git replace a1b2c3d e4f5g6h             # pretend commit X is actually commit Y
git replace -l                          # list active replacements
git replace -d a1b2c3d                  # remove one
git filter-branch --tag-name-filter cat -- --all   # the old, slow rewriter (Git now warns: prefer filter-repo)
```
Replacements are local to your clone — useful for experimenting before a real rewrite.

## Quick decision table

| You need to... | Use |
|---|---|
| Copy one commit to another branch | `cherry-pick` |
| Move your whole branch onto newer main | `rebase` |
| Clean up your own commits before a PR | `rebase -i` |
| Find which commit broke something | `bisect` |
| Find who wrote a line | `blame` |
| Find which commit touched a string | `log -S` |
| Undo a pushed commit safely | `revert` |
