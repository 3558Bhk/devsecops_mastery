# 06 Release & Hotfix — Basic Questions

**Q1.** What is a release branch for?
```text
Stabilising one version: only bug fixes, version bumps and docs — never new features.
```

**Q2.** Where do you cut a release branch from?
```bash
git switch -c release/1.4.0 main       # from the trunk (or from develop in GitFlow)
```

**Q3.** What two tags/branches mark a shipped release?
```bash
git tag -a v1.4.0 -m "release 1.4.0"   # an ANNOTATED tag on the release commit
git push origin release/1.4.0 --follow-tags
```

**Q4.** Which command lists the commits in a release?
```bash
git log --oneline v1.3.0..v1.4.0 --no-merges
```

**Q5.** How do you patch a version that shipped 8 months ago?
```bash
git switch release/1.4 && git cherry-pick -x <fix-sha> && git tag -a v1.4.3 -m "patch"
```

**Q6.** What must always happen after fixing a release branch?
```bash
git switch main && git cherry-pick -x <fix-sha>   # port the fix FORWARD to trunk
```

**Q7.** What does the `-x` flag on cherry-pick do?
```bash
git cherry-pick -x <sha>     # appends "(cherry picked from commit …)" so you can trace coverage
```

**Q8.** SemVer: which number does a hotfix bump?
```text
PATCH: 1.4.2 → 1.4.3. Features bump MINOR, breaking changes bump MAJOR.
```

**Q9.** Generate release notes between two tags.
```bash
git log v1.3.0..v1.4.0 --no-merges --pretty='* %s (%an)' > RELEASE-NOTES.md
```

**Q10.** How do you prove a security fix reached every supported version?
```bash
git tag --contains <fix-sha>        # every release tag containing it
git branch -a --contains <fix-sha>  # every branch containing it
```

**Q11.** What is a release train?
```text
A fixed-cadence release: cut at a set date, stabilise, ship. Missed the cut → wait for the next train.
```

**Q12.** How do you retire an old release line?
```bash
git tag -a v1.4-EOL -m "end of support" release/1.4 && git push origin --delete release/1.4
```
