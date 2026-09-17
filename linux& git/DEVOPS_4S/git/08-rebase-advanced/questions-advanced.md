# 08 Rebase & Advanced — Advanced Questions

**Q1.** During a rebase conflict, which side is "HEAD"?
```bash
git status                       # shows both versions; note the labels in the file
```
```text
<<<<<<< HEAD
main version                     # HEAD = the branch you are rebasing ONTO (the new base)
=======
topic version                    # the incoming side = YOUR commit being replayed
>>>>>>> 194fad9 (topic change)
```
This is the **opposite** of a merge, where HEAD is your own branch. Misreading it is the most
common rebase mistake.

**Q2.** Move only part of a branch onto a new base.
```bash
git rebase --onto newbase oldbase feature
# takes the commits in oldbase..feature and replays them onto newbase
git rebase --onto main release/1.4 feature   # "give me feature's commits that are not in release/1.4"
```

**Q3.** Split one commit into two during an interactive rebase.
```bash
git rebase -i HEAD~2             # mark the target commit as "edit"
git reset HEAD~1                 # unstage its changes, leaving them in the working tree
git add src/fix.js && git commit -m "fix: null check"        # first part
git add tests/ && git commit -m "test: null check coverage"  # second part
git rebase --continue            # finish the rebase
```

**Q4.** Squash everything your branch added into a single commit, without the editor.
```bash
git reset --soft origin/main     # keep all changes staged, remove the commits
git commit -m "feat: search filters"
git log --oneline -2             # one clean commit on top of main
```

**Q5.** Cherry-pick a merge commit.
```bash
git show --format='%P' -s <merge-hash>   # list its parents to pick the mainline
git cherry-pick -m 1 <merge-hash>        # -m 1 = diff against parent 1 (usually main)
```

**Q6.** Copy a range of commits, and understand the two range syntaxes.
```bash
git cherry-pick A..B             # commits AFTER A up to and including B (A excluded)
git cherry-pick A^..B            # A itself included (^ steps back one)
git cherry-pick -x A^..B         # -x records where each commit came from
```

**Q7.** Automate `git bisect` with a test script.
```bash
git bisect start HEAD v1.4.0     # bad = HEAD, good = v1.4.0
git bisect run ./scripts/test.sh # exit 0 = good, 1-127 = bad, 125 = skip this commit
git bisect reset                 # always clean up afterwards
```

**Q8.** Purge a secret or a huge file from the entire history.
```bash
pip install git-filter-repo
git branch backup-before-rewrite                     # instant undo point
git filter-repo --path config/secrets.yml --invert-paths   # remove that path everywhere
git filter-repo --strip-blobs-bigger-than 10M        # or drop every blob over 10 MB
git count-objects -vH && du -sh .git                 # confirm it shrank
git push --force --all && git push --force --tags    # everyone must re-clone
```
Rotate any leaked credential immediately — rewriting history does not un-leak it.

**Q9.** Rewrite only commit MESSAGES across many commits.
```bash
git rebase -i origin/main        # change pick → reword on each line
FILTER_BRANCH_SQUELCH_WARNING=1 git filter-branch --msg-filter 'sed "s/oldterm/newterm/"' origin/main..HEAD
# the env var silences Git's "use filter-repo instead" warning; verified working on a range
```

**Q10.** Test a rebase result without touching your branch.
```bash
git switch -c try-rebase feature      # throwaway branch
git rebase origin/main                # experiment freely
git switch feature                    # if it went badly, your branch is untouched
git branch -D try-rebase
```

**Q11.** What happens to the original commits after a rebase?
```bash
git reflog | head -10            # they are still there, just unreachable from any branch
git reset --hard HEAD@{5}        # which is why you can always go back
git fsck --lost-found            # eventually they become dangling and are garbage collected
```

**Q12.** Rebase a long-lived branch that keeps hitting the same conflicts.
```bash
git config --global rerere.enabled true    # record and replay your resolutions
git rerere status                          # see what was auto-resolved this time
git rerere diff                            # review it before committing
```

**Q13.** Verify nobody else's work was destroyed by your force push.
```bash
git fetch origin
git reflog show origin/main | head         # the remote branch's history as you saw it
git log --oneline origin/main -5           # current state
```
Better: rely on `--force-with-lease`, which refuses to push if the remote moved.
