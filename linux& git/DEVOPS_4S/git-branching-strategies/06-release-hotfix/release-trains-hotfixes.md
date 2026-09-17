# Pattern: Release branches, release trains, versioning & hotfix lines

This folder covers the parts every strategy needs: how you **cut**, **stabilise**, **tag**, **patch**
and **retire** a release.

## Release branch anatomy

```text
 trunk/main ──●───●───●───●───●───●───●───●───●───●───●───●──►  development continues
                   \                   \        ▲   ▲
                    \                   \       │   └ cherry-picked fixes flow FORWARD
                     ▼                   ▼      │
              release/1.4 ──●───●───●───●───●───●──►  stabilise only: version bump, docs, bug fixes
                       ▲    ▲       ▲       ▲
                    v1.4.0-rc1  v1.4.0  v1.4.1  v1.4.2      patch releases on the same line
                                     │
                                     └── support/1.4.x until EOL, then the branch is deleted

 RULE 1  nothing new enters a release branch — only fixes
 RULE 2  every fix on a release branch is cherry-picked (or merged) FORWARD to trunk
 RULE 3  one release branch per maintained version; delete at EOL
```

## Cut a release

```bash
git switch main && git pull --ff-only                       # 1. be current
git log --oneline v1.3.0..HEAD --no-merges | wc -l          # 2. how much is in this release?
git switch -c release/1.4.0                                 # 3. cut the branch
# 4. bump versions and lock the scope
npm version 1.4.0-rc.1 --no-git-tag-version && git commit -am "chore(release): 1.4.0-rc.1"
git push -u origin release/1.4.0                            # 5. CI builds the release candidate
git tag -a v1.4.0-rc.1 -m "release candidate 1" && git push origin v1.4.0-rc.1
```

## Stabilise, then ship

```bash
# fixes ONLY, each one reviewed and cherry-picked forward
git switch release/1.4.0 && git cherry-pick -x <fix-sha>    # if the fix was authored on main
# or author it here for a release-blocking bug, then forward-port:
git switch main && git cherry-pick -x <release-fix-sha>
# ship
git switch release/1.4.0
npm version 1.4.0 --no-git-tag-version && git commit -am "chore(release): 1.4.0"
git tag -a v1.4.0 -m "release 1.4.0"
git push origin release/1.4.0 --follow-tags
git branch -a --contains v1.4.0                             # verify what carries the tag
```

## Generate release notes from the branch

```bash
git log --oneline v1.3.0..v1.4.0 --no-merges --pretty='* %s (%an)' > RELEASE-NOTES.md
git log v1.3.0..v1.4.0 --no-merges --grep '^feat' --pretty='- %s'   # features (Conventional Commits)
git log v1.3.0..v1.4.0 --no-merges --grep '^fix'  --pretty='- %s'   # fixes
git log v1.3.0..v1.4.0 --no-merges --grep 'BREAKING CHANGE' -p      # breaking changes — read the diffs
git diff --stat v1.3.0 v1.4.0 | tail -1                             # size of the release
git shortlog -sn v1.3.0..v1.4.0                                     # contributors
```

## Release train (fixed cadence, many teams)

```text
  week 1-4        week 5           week 6          week 7
 ┌─────────┐   ┌──────────┐    ┌──────────┐    ┌──────────┐
 │ develop  │──►│ cut       │───►│ stabilise│───►│ ship     │──► train departs, next one starts
 │ features │   │ release/  │    │ QA, fixes│    │ tag+deploy│
 └─────────┘   │ 1.5       │    └──────────┘    └──────────┘
               └──────────┘
 MISSED THE TRAIN? Your feature waits for the next one — it does NOT get special treatment.
 That social rule is what makes trains work.
```

```bash
# the "train departs" automation
git switch -c release/1.5.0 main
git tag -a v1.5.0-rc.1 -m "train 1.5 cut"
# anything that missed the cut stays on main for 1.6 — verify with:
git log --oneline main --not release/1.5.0 | head
```

## Hotfix lines — patching versions that are already out

```bash
# find which versions are still supported
git tag -l 'v*' --sort=-v:refname | head -10
git branch -a --list 'release/*' 'support/*'
# patch an old line
git switch release/1.4 && git pull --ff-only
git cherry-pick -x <fix-sha>                    # preferred: fix on trunk first, then backport
git tag -a v1.4.3 -m "security fix CVE-2026-1234"
git push origin release/1.4 --follow-tags
# backport to every supported line in one pass
for b in release/1.5 release/1.6; do
  git switch "$b" && git cherry-pick -x <fix-sha> && git push origin "$b" || echo "CONFLICT on $b"
done
git tag --contains <fix-sha>                    # proof of coverage for the security report
```

**Semver rules for patch lines:** `MAJOR.MINOR.PATCH` — a hotfix bumps PATCH (1.4.2 → 1.4.3).
A backported *feature* to an old line is a policy decision most teams forbid; if allowed, it bumps MINOR.

## Versioning choices

| Scheme | Example | Use when |
|---|---|---|
| **SemVer** | `v2.4.1` | libraries, SDKs, APIs with consumers |
| **CalVer** | `v2026.09.15`, `2026.37` | services deployed continuously, no compatibility promise |
| **SemVer + build metadata** | `v1.4.0+sha.abc1234` | need traceability to the commit |
| **Train number** | `release-1.5` / `24.3` | scheduled enterprise releases |
| **Rolling** | `main-2026-09-15` | internal platforms |

```bash
git describe --tags --always --dirty           # v1.4.0-12-gabc1234-dirty  ← build stamp from Git
VERSION=$(git describe --tags --abbrev=0)      # v1.4.0
git rev-parse --short HEAD                     # abc1234 for the artefact name
```

## Retire a release line (EOL)

```bash
git tag -a v1.4-EOL -m "end of support for 1.4" release/1.4   # keep the evidence as a tag
git push origin v1.4-EOL
git push origin --delete release/1.4                          # delete the branch
git branch -D release/1.4
# the history and tags remain forever — only the moving pointer is removed
```

## Common failure modes

```text
✗ Fixes land on release/1.4 but are never forward-ported → regressions return in 1.5
   ✓ automate: CI job fails when a release branch has commits absent from main
✗ Release branches live for months and drift from main → merge conflicts, "stabilisation" forever
   ✓ time-box stabilisation to days; cut smaller releases
✗ Too many supported versions → every CVE costs N backports
   ✓ publish a support matrix and EOL dates; enforce with automated backport tooling
✗ Version bumped by hand, inconsistently
   ✓ automate: semantic-release / release-please / changesets driven by Conventional Commits
```
