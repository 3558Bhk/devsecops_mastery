# 04 GitLab Flow — Basic Questions

**Q1.** What problem does GitLab Flow solve that GitHub Flow does not?
```text
Multiple environments and promotion: merging to main does not necessarily mean "deployed to prod".
```

**Q2.** Name its three variants.
```text
Environment branches (main → pre-production → production)
Release branches    (main → release/1.4 → tags v1.4.0, v1.4.1)
Upstream first      (fork → PR → upstream, never build on unmerged upstream work)
```

**Q3.** Which direction do commits flow?
```text
One way only:  main → pre-production → production
```

**Q4.** Where do you author a hotfix found in production?
```bash
git switch main && git switch -c fix/PROJ-999   # on main (upstream first), then promote DOWN
```

**Q5.** How do you promote code to pre-production?
```bash
git switch pre-production && git merge --ff-only main    # fast-forward keeps hashes identical
git cherry-pick -x <sha>                                  # or pick specific commits if main moved on
```

**Q6.** What marks a production release in GitLab Flow?
```bash
git tag -a v1.5.0 -m "release" && git push origin v1.5.0   # tags on the production branch
```

**Q7.** Who is allowed to push to `production`?
```text
Only CI (a deploy token / protected environment). Humans push to feature branches and main only.
```

**Q8.** What goes into a `release/*` branch?
```text
Bug fixes only — plus version bumps and docs. Every fix is cherry-picked back to main.
```

**Q9.** What is the classic GitLab Flow bug?
```text
Fixing directly on production/pre-production and forgetting to bring the fix upstream —
so the next promotion from main reverts it.
```

**Q10.** When is GitLab Flow overkill?
```text
One environment, continuous deploy, small team → GitHub Flow or trunk-based development.
```
