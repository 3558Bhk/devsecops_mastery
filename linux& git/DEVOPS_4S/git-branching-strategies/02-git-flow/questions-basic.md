# 02 GitFlow — Basic Questions

**Q1.** Which two branches are permanent in GitFlow?
```text
main (or master) — only released code, every commit tagged
develop          — the integration branch; all finished features land here first
```

**Q2.** Where does a `feature/*` branch start, and where does it merge back?
```bash
git switch develop && git pull        # start from develop (NOT main)
git switch -c feature/PROJ-123-x
# ...then PR base = develop
```

**Q3.** Which branch do you cut a `release/*` from?
```bash
git switch -c release/1.4.0 develop   # from develop — it freezes the feature set
```

**Q4.** Where does a finished `release/*` branch merge to?
```bash
git switch main    && git merge --no-ff release/1.4.0 && git tag -a v1.4.0 -m "release"
git switch develop && git merge --no-ff release/1.4.0   # the back-merge is mandatory
```
Both — main (to ship) and develop (so the release fixes are not lost).

**Q5.** Where does a `hotfix/*` branch start from?
```bash
git switch -c hotfix/1.4.1 v1.4.0     # from the released TAG, not from develop
```

**Q6.** Which two flags do GitFlow merges use, and why?
```bash
git merge --no-ff feature             # always create a merge commit so the feature is visible as a unit
git tag -a v1.4.0 -m "..."            # annotated tags carry author, date and message
```

**Q7.** What kinds of change are allowed on a `release/*` branch?
```text
version bumps, documentation, and release-blocking bug fixes ONLY — no new features
```

**Q8.** Name the tool that automates GitFlow.
```bash
git flow init                         # apt install git-flow / brew install git-flow
git flow release start 1.4.0 && git flow release finish 1.4.0
```

**Q9.** What is the most common GitFlow mistake?
```bash
# opening a feature PR against main instead of develop
git branch -vv                          # check the tracking branch
gh pr create --base develop             # explicit base every time
```

**Q10.** When is GitFlow the right model?
```text
versioned products (mobile, desktop, on-prem, SDKs), scheduled releases with a QA window,
and multiple versions maintained in parallel
```
