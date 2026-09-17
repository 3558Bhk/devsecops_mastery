# 08 Interview Scenarios — Basic Questions

**Q1.** What is the 4-part structure for answering "which strategy do you use?"
```text
PICK → JUSTIFY (deploy capability + release model) → TRADE-OFF → ADAPT (the exception).
```

**Q2.** What should you never start an answer with?
```text
"It depends." Pick a model first, then explain the conditions.
```

**Q3.** Name the four models and their one-line identity.
```text
GitFlow: main + develop, versioned scheduled releases.
GitHub Flow: main + short-lived branches, deploy from main.
GitLab Flow: + environment/release branches, one-way promotion.
Trunk-based: one trunk, daily integration, feature flags.
```

**Q4.** What diagram should you be able to draw in 30 seconds?
```text
main ──●────●────●────●──►
        \  /  \  /
         ●●    ●●        short-lived branches merging back into one trunk
```

**Q5.** What is the first thing you do when main is broken?
```bash
git revert --no-edit <sha> && git push     # restore green; diagnose afterwards
```

**Q6.** What is the golden rule of hotfixing an old version?
```bash
# fix on trunk first, then cherry-pick DOWN — never merge an old branch upward
git switch release/2.4 && git cherry-pick -x <trunk-fix-sha>
```

**Q7.** How do you prove a fix reached every supported version?
```bash
git tag --contains <sha> && git branch -a --contains <sha>
```

**Q8.** What numbers should you quote for healthy practice?
```text
Branch < 1-2 days · PR < ~400 lines / 20 files · CI < 10 min · integrate ≥ daily · reverts < 15%.
```

**Q9.** How do you describe "merge ≠ release"?
```text
Deployment ships code; release turns it on for users via a flag. Trunk-based decouples the two.
```

**Q10.** What closes a branching answer at senior level?
```text
"The branching model is downstream of your deploy capability — pick what your pipeline can support,"
plus the metrics you would use to prove it works (DORA, branch age, PR cycle time).
```
