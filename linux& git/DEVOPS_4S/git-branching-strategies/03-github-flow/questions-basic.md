# 03 GitHub Flow — Basic Questions

**Q1.** How many long-lived branches does GitHub Flow have?
```text
One: main. There is no develop and no release branch.
```

**Q2.** What is the one golden rule?
```text
Anything in main is deployable — and is deployed automatically.
```

**Q3.** First two commands of every task?
```bash
git switch main && git pull --ff-only     # start from an up-to-date main
git switch -c feat/PROJ-123-slug          # small named branch
```

**Q4.** How often should you rebase onto main?
```bash
git fetch origin && git rebase origin/main   # daily — not at review time
git push --force-with-lease                  # safe force push after a rebase
```

**Q5.** Which merge policy does GitHub Flow usually use?
```bash
gh pr merge --squash --delete-branch    # one commit per PR, branch auto-deleted
```

**Q6.** What protects main?
```text
branch protection: required reviews, required status checks, no force push, no deletion
```

**Q7.** How do you roll back a bad deploy?
```bash
git revert --no-edit <hash> && git push      # forward-fix commit, then redeploy
# or redeploy the previous immutable artefact / kubectl rollout undo
```

**Q8.** How do you merge unfinished work without a long-lived branch?
```text
feature flags — merge it dark, expose it later
```

**Q9.** What PR size does the model assume?
```text
under ~400 changed lines; review quality collapses above that
```

**Q10.** When is GitHub Flow the wrong choice?
```text
versioned artefacts customers stay on, mandatory environment promotion, or no safe/fast deploy path
```
