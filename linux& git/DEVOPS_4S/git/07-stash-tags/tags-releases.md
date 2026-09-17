# Pattern: Tags and releases

A **tag** is a permanent label on a commit — normally used for versions (`v1.4.0`).

```bash
git tag                                 # list all tags
git tag -l "v1.*"                       # list tags matching a pattern
git tag v1.0.0                          # LIGHTWEIGHT tag: just a pointer, no metadata
git tag -a v1.0.0 -m "release 1.0.0"    # ANNOTATED tag: has author, date, message (use this)
git tag -a v1.0.0 a1b2c3d               # tag an OLDER commit, not just HEAD
git tag -a v1.0.0 -m "fix" --force      # move a tag to a different commit (avoid on published tags)
git show v1.0.0                         # the tag's message and the commit it points at
git tag -v v1.0.0                       # verify a GPG signature
git tag -d v1.0.0                       # delete a local tag
git push origin v1.0.0                  # publish ONE tag
git push origin --tags                  # publish all tags
git push --follow-tags                  # publish annotated tags reachable from pushed commits
git push origin --delete v1.0.0         # delete a tag on the remote
git push origin :refs/tags/v1.0.0       # older syntax for the same deletion
git describe --tags                     # nearest tag + how many commits since: v1.0.0-14-ga1b2c3d
git describe --tags --abbrev=0          # just the nearest tag name
git log --oneline v1.0.0..v1.1.0        # the commits between two releases = your changelog
git diff v1.0.0 v1.1.0 --stat           # what changed between releases
git switch --detach v1.0.0              # inspect an old release without a branch
git switch -c hotfix/1.0.1 v1.0.0       # start a hotfix branch from an old release
```

## Lightweight vs annotated

| | Lightweight (`git tag v1`) | Annotated (`git tag -a v1 -m "..."`) |
|---|---|---|
| Stored as | a ref only | a full object in the database |
| Metadata | none | tagger, date, message, optional GPG signature |
| `git describe` | ignored by default | included |
| Use for | temporary local markers | **all real releases** |

## Semantic versioning (the convention everyone uses)

```text
v MAJOR . MINOR . PATCH      e.g. v2.4.1
  │        │       └ bug fixes, no new features, fully backwards compatible
  │        └ new features, backwards compatible
  └ breaking changes
Pre-release:  v2.0.0-rc.1  v2.0.0-beta.3
```

## A complete release routine

```bash
git switch main && git pull                       # 1. be on an up-to-date main
npm version patch -m "release %s"                 # 2. bump the version file AND create the tag (Node)
# or manually:
git tag -a v1.4.0 -m "release 1.4.0"              # 2b. create the annotated tag
git push origin main --follow-tags                # 3. publish branch and tag together
git log --oneline v1.3.0..v1.4.0 --no-merges      # 4. generate the changelog entries
```
Then create the GitHub/GitLab **Release** from that tag and paste the changelog in.

## Automate tags from commit messages

```bash
git log --oneline --grep="^feat" v1.3.0..HEAD     # new features since the last release
git log --oneline --grep="^fix" v1.3.0..HEAD      # fixes
```
With Conventional Commits, tools like `semantic-release` or `standard-version` pick the next
version number and create the tag automatically in CI.
