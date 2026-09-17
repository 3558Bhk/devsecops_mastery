# 06 Remotes & Collaboration — Basic Questions

**Q1.** See which remote repositories this project talks to.
```bash
git remote -v                  # name plus fetch and push URLs
```

**Q2.** Add a remote called `origin`.
```bash
git remote add origin https://github.com/user/repo.git
```

**Q3.** Upload your commits to the remote.
```bash
git push origin main           # remote name, then branch name
git push                       # after -u is set once, this is enough
```

**Q4.** Make `git push` remember where this branch goes.
```bash
git push -u origin feature     # -u sets the UPSTREAM (tracking) branch
```

**Q5.** Download new commits WITHOUT changing your working files.
```bash
git fetch                      # updates origin/* refs only — completely safe
```

**Q6.** Download and integrate in one step.
```bash
git pull                       # = git fetch + git merge
git pull --rebase              # = git fetch + git rebase (linear history)
```

**Q7.** See how far ahead or behind the remote you are.
```bash
git status -sb                 # shows "## main...origin/main [ahead 2, behind 1]"
```

**Q8.** List the branches that exist on the remote.
```bash
git branch -r                  # your cached view after the last fetch
git ls-remote --heads origin   # ask the remote directly, right now
```

**Q9.** Delete a branch on the remote.
```bash
git push origin --delete feature
```

**Q10.** Clone a repository from GitHub.
```bash
git clone https://github.com/user/repo.git
```

**Q11.** Publish your tags.
```bash
git push --tags                # all tags
git push --follow-tags         # only annotated tags reachable from what you pushed
```

**Q12.** What is the conventional name for the remote you cloned from?
```bash
git remote                     # prints "origin" by default
```

**Q13.** Test whether your SSH key works with GitHub.
```bash
ssh -T git@github.com          # "Hi USERNAME! You've successfully authenticated..."
```

**Q14.** See what a push WOULD do, without doing it.
```bash
git push --dry-run             # reports the refs it would update
```

**Q15.** Remove branches from your local cache that no longer exist upstream.
```bash
git fetch --prune              # or: git remote prune origin
```
