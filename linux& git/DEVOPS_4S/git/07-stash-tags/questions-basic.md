# 07 Stash & Tags — Basic Questions

**Q1.** Save your uncommitted work and get a clean tree.
```bash
git stash                      # tracked modifications are put aside
```

**Q2.** Save it with a name you will recognise.
```bash
git stash push -m "wip login form"   # the message appears in git stash list
```

**Q3.** Include new, untracked files in the stash.
```bash
git stash push -u -m "wip"     # -u = also stash untracked files
```

**Q4.** See what you have stashed.
```bash
git stash list                 # stash@{0}, stash@{1}, ... newest first
```

**Q5.** Look inside a stash before applying it.
```bash
git stash show -p stash@{0}    # the full diff of that stash
```

**Q6.** Bring your stashed work back.
```bash
git stash pop                  # apply the newest stash and remove it from the list
```

**Q7.** Apply a stash but keep it in the list.
```bash
git stash apply                # safe: you can apply it again elsewhere
```

**Q8.** Delete one stash, and all stashes.
```bash
git stash drop stash@{0}       # delete one
git stash clear                # delete all (⚠️ no confirmation)
```

**Q9.** List all tags in the repository.
```bash
git tag                        # every tag
git tag -l "v1.*"              # only tags matching a pattern
```

**Q10.** Create a release tag with a message.
```bash
git tag -a v1.0.0 -m "release 1.0.0"   # -a = annotated tag (has author, date, message)
```

**Q11.** Publish a tag to the remote.
```bash
git push origin v1.0.0         # one tag
git push origin --tags         # all of them
```

**Q12.** Delete a tag locally and on the remote.
```bash
git tag -d v1.0.0              # local
git push origin --delete v1.0.0   # remote
```

**Q13.** See what a tag points at.
```bash
git show v1.0.0                # the tag message plus the commit
```

**Q14.** Inspect an old release without creating a branch.
```bash
git switch --detach v1.0.0     # detached HEAD: look around safely
git switch main                # come back
```

**Q15.** List the commits between two releases (a changelog).
```bash
git log --oneline v1.0.0..v1.1.0
```
