# 08 Rebase & Advanced — Basic Questions

**Q1.** Move your feature branch onto the latest main.
```bash
git switch feature               # stand on the branch to move
git rebase main                  # replay its commits on top of main
```

**Q2.** Rebase onto what the remote actually has (the usual real case).
```bash
git fetch origin                 # refresh origin/main first
git rebase origin/main           # then rebase onto it
```

**Q3.** What is the difference between `merge` and `rebase`?
```bash
git merge main                   # creates a merge commit; history keeps both lines
git rebase main                  # rewrites your commits onto main; history becomes one straight line
```

**Q4.** Cancel a rebase that is going wrong.
```bash
git rebase --abort               # back to exactly where you were before starting
```

**Q5.** Continue a rebase after fixing conflicts.
```bash
# resolve the conflict markers, then:
git add <resolved-files>         # mark them resolved
git rebase --continue            # carry on with the remaining commits
```

**Q6.** Clean up your last 4 commits interactively.
```bash
git rebase -i HEAD~4             # opens an editor listing the 4 commits, oldest first
```

**Q7.** In the interactive editor, what do `pick`, `reword`, `squash`, `fixup` and `drop` mean?
```text
pick    keep the commit unchanged      reword  keep it, change its message
squash  melt into the previous commit, combine messages
fixup   melt into the previous commit, discard this message
drop    delete the commit (or just delete the line)
```

**Q8.** Copy one commit from another branch onto yours.
```bash
git cherry-pick a1b2c3d          # applies that commit's changes as a new commit here
```

**Q9.** Cherry-pick without committing, so you can adjust first.
```bash
git cherry-pick -n a1b2c3d       # -n stages the changes only
```

**Q10.** Find which commit broke the build, automatically.
```bash
git bisect start                 # begin
git bisect bad                   # the current version is broken
git bisect good v1.4.0           # this older version worked
git bisect reset                 # return to normal when done
```

**Q11.** See which commits your branch has that main does not.
```bash
git log --oneline main..feature  # commits on feature that are not on main
```

**Q12.** Is it ever OK to rebase a shared branch?
```bash
git log --oneline origin/main..HEAD   # if these commits are already on a shared branch: DO NOT rebase
```
Rewriting published history breaks everyone else's clones. Rebase only your own unpushed work.

**Q13.** After rebasing a branch you already pushed, how do you publish it?
```bash
git push --force-with-lease      # safe force push: aborts if the remote moved since your fetch
```

**Q14.** Make Git remember how you resolved a conflict, so it reuses the answer next time.
```bash
git config --global rerere.enabled true   # REuse REcorded REsolution
```
