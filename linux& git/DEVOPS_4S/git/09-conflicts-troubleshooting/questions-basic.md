# 09 Conflicts & Troubleshooting — Basic Questions

**Q1.** What causes a merge conflict?
```bash
git merge feature            # two branches changed the SAME lines and Git cannot choose for you
```

**Q2.** List the files that are in conflict.
```bash
git status                   # the "Unmerged paths" section
git diff --name-only --diff-filter=U   # just the file names
```

**Q3.** What do the conflict markers mean?
```text
<<<<<<< HEAD                 # start of YOUR version (the branch you are on)
your code
=======                      # separator
their code
>>>>>>> feature              # end of THEIR version (the branch being merged in)
```

**Q4.** Mark a file as resolved.
```bash
git add file.js              # staging it tells Git the conflict is settled
```

**Q5.** Finish a merge after resolving all conflicts.
```bash
git commit                   # or: git merge --continue
```

**Q6.** Cancel a conflicted merge and go back to how things were.
```bash
git merge --abort            # everything returns to the pre-merge state
```

**Q7.** Keep only your side of a conflicted file.
```bash
git checkout --ours file.js  # discard their version entirely
git add file.js
```

**Q8.** Keep only their side.
```bash
git checkout --theirs file.js
git add file.js
```

**Q9.** Check that no conflict markers were left behind by accident.
```bash
grep -rn "<<<<<<<" .         # search for the marker
git diff --check             # Git's own leftover-marker and whitespace check
```

**Q10.** "fatal: not a git repository" — what do you check first?
```bash
pwd                          # am I in the right folder?
ls -a                        # is there a .git directory here?
```

**Q11.** Git refuses to switch branches because of local changes. What are the two options?
```bash
git stash push -u -m "wip"   # save the work and switch cleanly
git checkout -f otherbranch  # or discard the changes (⚠️ they are gone)
```

**Q12.** Your push was rejected. What is the safe sequence?
```bash
git fetch origin             # get their commits
git pull --rebase            # replay yours on top
git push                     # push again
```

**Q13.** What does "detached HEAD" mean?
```bash
git status                   # you are on a commit, not on a branch — new commits belong to no branch
git switch -c save-work      # save them on a new branch
git switch main              # or simply go back
```

**Q14.** A rebase refuses to start because of unstaged changes.
```bash
git stash push -u -m "before rebase"   # stash first
git rebase origin/main
git stash pop                          # restore afterwards
```

**Q15.** Where do you find the answer to almost any Git confusion?
```bash
git status                   # it tells you what state you are in and what to do next
```
