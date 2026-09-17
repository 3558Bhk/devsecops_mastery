# 01 Fundamentals — Basic Questions

**Q1.** What is a branch, physically?
```bash
cat .git/refs/heads/main       # a file containing one 41-character commit hash — nothing more
git show-ref                   # every ref and its hash
```

**Q2.** What does HEAD point at?
```bash
cat .git/HEAD                  # "ref: refs/heads/main" — HEAD points at a BRANCH, not a commit
git rev-parse HEAD             # resolves through to the commit hash
```

**Q3.** Why is creating a branch in Git almost free?
```bash
git branch experiment          # writes one small file; no files are copied or snapshotted
```

**Q4.** What is the difference between `refs/heads/main` and `refs/remotes/origin/main`?
```bash
git branch -a                  # local branches vs remote-TRACKING branches
```
`origin/main` is a **local cache** of the remote's state, updated only by `fetch`/`pull`.

**Q5.** Name the three permanent/long-lived branch types.
```text
main (or trunk/master) — always deployable, protected
develop                — GitFlow's integration branch
release/X.Y            — stabilisation + patch line for one version
```

**Q6.** Name four short-lived branch types.
```text
feature/…  fix/…  hotfix/…  experiment/…  chore/…
```

**Q7.** What is a fast-forward merge?
```bash
git merge --ff-only feature    # succeeds only when main has not moved since the branch point
```
The branch pointer simply slides forward; **no merge commit** is created.

**Q8.** What is a three-way merge and how many parents does its commit have?
```bash
git merge --no-ff feature -m "merge"   # creates a merge commit
git cat-file -p HEAD | grep parent     # TWO parent lines
```

**Q9.** Which command shows the common ancestor of two branches?
```bash
git merge-base main feature    # the base used for the three-way merge
```

**Q10.** Which characters are forbidden in a branch name?
```text
space, ~ ^ : ? * [ \ , "..", "@{", leading/trailing "/", trailing "." or ".lock"
```
```bash
git check-ref-format --print "feature/my-branch"   # validate programmatically
```

**Q11.** What naming scheme do most teams use?
```text
<type>/<TICKET>-<short-slug>     e.g. feature/PROJ-1234-add-coupons
```

**Q12.** How do you see which branches are stale?
```bash
git for-each-ref --sort=committerdate refs/heads --format='%(committerdate:short) %(refname:short)'
git branch --no-merged main      # branches whose work has not landed
```

**Q13.** Delete every local branch already merged into main.
```bash
git fetch --prune                                            # refresh + drop dead remote refs
git branch --merged main | grep -vE '^\*|main|develop' | xargs -r git branch -d
```

**Q14.** What is `ORIG_HEAD`?
```bash
git reset --hard ORIG_HEAD       # where HEAD was before the last reset/rebase/merge — your undo
```

**Q15.** Why should every branch carry a ticket number?
```bash
git branch -a --list "*PROJ-1234*"   # it links code → ticket → deploy → incident for audits and postmortems
```
