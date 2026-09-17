# 05 Trunk-Based Development — Basic Questions

**Q1.** How many long-lived branches are there?
```text
One: the trunk (main). No develop, no release/*, no environment branches.
```

**Q2.** How often should a developer integrate into the trunk?
```text
At least once a day. Branch lifetime under 1-2 days.
```

**Q3.** How do you merge unfinished work without breaking users?
```text
Feature flags — the code is merged and tested but hidden at runtime.
```

**Q4.** What is the difference between deployment and release in this model?
```text
Deployment = shipping code to production. Release = turning it on for users (the flag).
Trunk-based decouples them.
```

**Q5.** What is the maximum healthy PR size?
```text
Roughly 400 changed lines / 20 files. Above that, review quality collapses.
```

**Q6.** How long should CI take?
```text
Under ~10 minutes. Slow CI forces batching, which destroys the model.
```

**Q7.** What must always be true of the trunk?
```text
Green and deployable. A broken main blocks the whole team.
```

**Q8.** How do you roll back a bad change?
```bash
git revert --no-edit <sha> && git push      # forward fix, then redeploy
# or flip the feature flag off (seconds, no deploy), or redeploy the previous artefact
```

**Q9.** Are release branches ever allowed?
```bash
git switch -c release/1.5 v1.5.0            # yes — only to patch an already-shipped version
git cherry-pick -x <fix>                    # fixes flow forward to trunk by cherry-pick
```

**Q10.** Name the four flag types.
```text
release flags (short-lived) · ops flags (kill switches) · experiment flags (A/B) · permission flags (entitlements)
```

**Q11.** What config makes the trunk stay linear?
```bash
git config --global pull.rebase true        # rebase on pull instead of merging
git config --global rebase.autoStash true
```

**Q12.** How is trunk-based different from GitHub Flow?
```text
Same mechanics; trunk-based adds explicit discipline: daily integration, mandatory flags,
size/cadence limits, and release branches only for patching old versions.
```
