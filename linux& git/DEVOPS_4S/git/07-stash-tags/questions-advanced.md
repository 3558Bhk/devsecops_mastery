# 07 Stash & Tags — Advanced Questions

**Q1.** Stash only some of your changes, hunk by hunk.
```bash
git stash push -p                      # answer y/n for each hunk, exactly like git add -p
git stash push -- src/app.js           # or stash only specific paths
git stash push --keep-index            # stash everything but leave the staged part intact
```

**Q2.** What exactly does a stash contain?
```bash
git stash list                         # each entry is a commit object with 2 or 3 parents
git rev-parse stash@{0}                # its hash
git show stash@{0}^3                   # the third parent holds the UNTRACKED files (stashed with -u)
git log -g stash                       # the stash reflog
```

**Q3.** Turn a stash into a proper branch.
```bash
git stash branch fix/login stash@{0}   # creates the branch at the stash's BASE commit, then applies it
```
This avoids the conflicts you get when applying an old stash onto a much-changed tree.

**Q4.** `git stash pop` reports a conflict. What now?
```bash
git status -s                          # conflicted files show as UU
# resolve the conflict markers, then:
git add <resolved-files>               # mark them resolved
git stash drop                         # pop does NOT auto-drop after a conflict — drop it yourself
```

**Q5.** Recover a stash you dropped or cleared.
```bash
git fsck --unreachable | grep commit   # dropped stashes remain as unreachable commits for a while
git show <hash>                        # inspect a candidate
git stash apply <hash>                 # re-apply it
```

**Q6.** Lightweight vs annotated tags — why do releases need annotated ones?
```bash
git tag v1.0.0                         # lightweight: a ref with no author, date or message
git tag -a v1.0.0 -m "release"         # annotated: a real object, signable, shown by git describe
git cat-file -t v1.0.0                 # "commit" for lightweight, "tag" for annotated
git describe --tags                    # only considers annotated tags unless you pass --tags
```

**Q7.** Move a tag that is already published. What is the safe procedure?
```bash
git tag -a v1.0.0 -m "correct target" --force <hash>   # move it locally
git push origin v1.0.0 --force                         # overwrite the remote tag
```
Anyone who already fetched the old tag keeps it — they must run `git fetch --tags --force`.
Better practice: never move a published tag; release `v1.0.1` instead.

**Q8.** Generate a version string automatically from Git.
```bash
git describe --tags --always --dirty     # e.g. v1.4.0-12-ga1b2c3d-dirty
git describe --tags --abbrev=0           # just the nearest tag: v1.4.0
VERSION=$(git describe --tags --always --dirty)   # capture it in a build script
```
`-12-ga1b2c3d` means "12 commits after the tag, at hash a1b2c3d"; `-dirty` = uncommitted changes.

**Q9.** Start a hotfix from an old release tag and bring it forward to main.
```bash
git fetch --tags                          # make sure you have all tags
git switch -c hotfix/1.0.1 v1.0.0         # branch from the release, not from main
# ...fix, test, commit...
git tag -a v1.0.1 -m "security fix"       # tag the patched release
git switch main && git cherry-pick <fix-hash>   # port the same fix forward to main
```

**Q10.** Stash automatically around a rebase so your edits never block it.
```bash
git config --global rebase.autoStash true # stash before, reapply after, automatically
git rebase origin/main                    # now safe with a dirty working tree
git stash list                            # if the reapply conflicted, the stash is still here
```

**Q11.** List tags sorted by date, with their subjects.
```bash
git tag --sort=-creatordate | head -5                       # newest tags first
git for-each-ref --sort=-creatordate --format='%(refname:short) %(creatordate:short) %(subject)' refs/tags
```

**Q12.** Sign tags so people can verify a release is genuinely yours.
```bash
gpg --list-secret-keys --keyid-format=long   # find your GPG key id
git config --global user.signingkey <KEYID>   # tell Git which key to use
git tag -s v1.0.0 -m "signed release"         # -s creates a GPG-signed tag
git tag -v v1.0.0                             # anyone can then verify it
```
