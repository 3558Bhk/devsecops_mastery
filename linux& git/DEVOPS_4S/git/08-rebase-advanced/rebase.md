# Pattern: `git rebase` — replaying commits

`merge` joins two lines of history. `rebase` **moves** your commits to a new starting point,
producing a straight line.

```bash
git switch feature                        # stand on the branch you want to MOVE
git rebase main                           # replay feature's commits on top of main's tip
git rebase origin/main                    # the usual real case: rebase onto the fetched remote main
git fetch origin && git rebase origin/main   # always fetch first, or you rebase onto stale data
git rebase --continue                     # after resolving a conflict: stage the files, then continue
git rebase --skip                         # abandon the current commit entirely (it disappears)
git rebase --abort                        # cancel the whole rebase, back to where you started
git rebase --quit                         # stop the rebase but KEEP the current state
git rebase --onto newbase oldbase feature # move only the commits between oldbase and feature
git rebase -i HEAD~5                      # INTERACTIVE: edit the last 5 commits
git log --oneline --graph --all           # check the result
```

## What rebase does, drawn

```text
BEFORE:   A---B---C---D  (main)
                   \
                    E---F  (feature)

git rebase main  →  A---B---C---D  (main)
                                 \
                                  E'---F'  (feature)   new hashes, same changes
```
The old commits E and F still exist until garbage collection — that's why `git reflog` can rescue
a broken rebase.

## Interactive rebase — the command list

```bash
git rebase -i HEAD~4                      # opens your editor with the last 4 commits, oldest first
```
```text
pick a1b2c3d feat: add cart              # keep the commit as it is
reword e4f5g6h fix: typo                 # keep it, but edit the message
edit 9i0j1k2 wip: broken                 # stop after applying it so you can amend/split
squash 3l4m5n6 fixup stuff                # melt into the PREVIOUS commit, keep both messages
fixup 7o8p9q0 more fixup stuff            # melt into the previous commit, DISCARD this message
drop 1r2s3t3 debug prints                 # delete the commit (or just delete the line)
exec npm test                             # run a shell command after the previous commit
label / reset / merge                     # advanced graph operations
```
Reordering the LINES reorders the commits. Deleting a line removes that commit.

## The golden rule

```bash
git log --oneline origin/main..HEAD       # these are YOUR unpushed commits — safe to rebase
# Never rebase commits that are already on a shared branch: other people have them.
git push --force-with-lease               # after rebasing a branch you already pushed (yours only)
```

## When to rebase vs merge

| Goal | Use |
|---|---|
| Keep your private feature branch current with main | `git rebase origin/main` |
| Clean up messy WIP commits before a PR | `git rebase -i` |
| Integrate a feature into main for the team to see | `git merge --no-ff` |
| Anything on a shared/public branch | `merge`, never rebase |

## Make rebases painless

```bash
git config --global rebase.autoStash true    # stash/unstash your dirty tree automatically
git config --global rebase.autoSquash true   # apply fixup!/squash! commits automatically
git config --global rerere.enabled true      # REuse REcorded REsolution: remember conflict fixes
git config --global pull.rebase true         # make "git pull" rebase instead of merge
git rebase -i --autosquash main              # fold "fixup!" commits into their targets
```
