# 07 Choosing a Strategy — Basic Questions

**Q1.** Which strategy has the most long-lived branches?
```text
GitFlow: main + develop, plus release/* and hotfix/* as needed.
```

**Q2.** Which has the fewest?
```text
GitHub Flow and trunk-based: main only.
```

**Q3.** Which strategy is built for versioned products customers install?
```text
GitFlow (or trunk + release/* patch lines).
```

**Q4.** Which strategy models promotion through staging → production?
```text
GitLab Flow with environment branches.
```

**Q5.** Which strategy REQUIRES feature flags?
```text
Trunk-based development — flags are how unfinished work merges safely.
```

**Q6.** Which strategy has the highest merge-conflict risk?
```text
GitFlow, because develop accumulates divergence until a release is cut.
```

**Q7.** What is the first prerequisite before adopting trunk-based development?
```text
Fast CI (< ~10 min), automated deploy from main, a tested rollback, and a feature-flag service.
```

**Q8.** Name three metrics that tell you which strategy fits.
```bash
git log --first-parent --since="3 months" --oneline main | wc -l    # integration frequency
git tag -l --sort=-creatordate | head -5                            # release cadence
git for-each-ref --sort=committerdate refs/remotes/origin --format='%(committerdate:short) %(refname:short)' | head   # branch age
```

**Q9.** In the GitFlow → trunk migration, what happens last?
```bash
git branch -d develop && git push origin --delete develop   # only after the soak period
```

**Q10.** What is the #1 anti-pattern?
```text
Choosing a strategy from a blog post instead of from your deploy capability and release model.
```
