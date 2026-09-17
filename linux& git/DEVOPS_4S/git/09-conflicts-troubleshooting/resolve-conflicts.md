# Pattern: Resolving merge conflicts step by step

A conflict happens when two branches changed the **same lines** of the same file and Git cannot
decide which version wins. Git stops and asks you.

## What a conflict looks like

```bash
git merge feature
```
```text
Auto-merging src/app.js
CONFLICT (content): Merge conflict in src/app.js
Automatic merge failed; fix conflicts and then commit the result.
```

```bash
git status                       # "Unmerged paths:" lists every conflicted file
git status -s                    # compact: UU src/app.js  (both sides modified)
git diff --name-only --diff-filter=U   # just the conflicted file names (great in scripts)
git ls-files -u                  # the three versions: stage 1=base, 2=ours, 3=theirs
```

## Inside the conflicted file

```text
function total(cart) {
<<<<<<< HEAD
    return cart.sum() * 1.18;    // OURS: the branch you are ON (main during a merge)
=======
    return cart.sum() * 1.20;    // THEIRS: the branch you are merging IN (feature)
>>>>>>> feature
}
```
- Everything between `<<<<<<< HEAD` and `=======` is **your** current version.
- Everything between `=======` and `>>>>>>>` is the **incoming** version.
- ⚠️ During a **rebase** the sides are SWAPPED: HEAD is the new base, incoming is your commit.

## The four ways to resolve

```bash
# 1. Edit by hand — delete the markers, keep the code you want (the normal case)
nano src/app.js
git add src/app.js               # staging a file marks it RESOLVED
git commit                       # finish the merge (the message is pre-filled)

# 2. Take one side wholesale
git checkout --ours src/app.js   # keep MY version, discard theirs
git checkout --theirs src/app.js # keep THEIR version, discard mine
git add src/app.js

# 3. Use a visual merge tool
git mergetool                    # opens vimdiff/meld/p4merge as configured
git config --global merge.tool meld
git config --global mergetool.keepBackup false   # don't leave .orig files everywhere

# 4. Give up
git merge --abort                # cancel everything, back to the pre-merge state
```

## Finishing up, per operation

| Operation in progress | Resolve, then run |
|---|---|
| `git merge` | `git add <files>` → `git commit` (or `git merge --continue`) |
| `git rebase` | `git add <files>` → `git rebase --continue` |
| `git cherry-pick` | `git add <files>` → `git cherry-pick --continue` |
| `git revert` | `git add <files>` → `git revert --continue` |
| `git stash pop` | `git add <files>` → `git stash drop` (pop keeps the entry on conflict) |

Cancel versions: `git merge --abort`, `git rebase --abort`, `git cherry-pick --abort`,
`git revert --abort`, `git rebase --skip` (drop just this commit).

## Verify before you commit

```bash
grep -rn "<<<<<<<\|>>>>>>>\|=======" src/    # any marker left behind? (also check for stray =======)
git diff --staged                            # review the resolution
git diff --check                             # Git's own check for leftover conflict markers
npm test                                     # make sure the merged code actually works
git status                                   # should say "All conflicts fixed"
```

## Special conflict types

```bash
git status                                   # "deleted by us" / "deleted by them" / "added by both"
git rm path/to/file                          # accept the deletion
git add path/to/file                         # or keep the file
git checkout --ours -- binary.png            # binary files cannot be merged, only chosen
git checkout HEAD -- package-lock.json && npm install   # lockfiles: regenerate instead of merging
```

## Make conflicts less likely

```bash
git config --global rerere.enabled true      # remember and replay your resolutions
git config --global merge.conflictStyle zdiff3   # show the ORIGINAL base version too — much clearer
# with zdiff3 you get a third section: ||||||| <base-hash> between OURS and =======
# seeing what the code looked like BEFORE both sides changed it makes the right answer obvious
git config --global pull.rebase true         # fewer pointless merge commits
```
```text
# .gitattributes — stop fighting over generated files
package-lock.json merge=npm
CHANGELOG.md merge=union
*.png binary
```
```bash
# a custom merge driver only works if you also DEFINE it (otherwise Git warns and falls back):
git config merge.npm.driver "npm install --package-lock-only"
git config merge.npm.name "regenerate npm lockfile"
```
And the human fix: merge or rebase from main **often**. Small, frequent integrations conflict far
less than one big merge at the end.
