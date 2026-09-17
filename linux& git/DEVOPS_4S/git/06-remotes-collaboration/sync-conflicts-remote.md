# Pattern: Staying in sync with a moving remote

## The normal daily rhythm

```bash
git fetch --prune                       # refresh remote state, drop dead branches
git status -sb                          # see [ahead 2, behind 3] at a glance
git pull --rebase                       # replay YOUR commits on top of the remote's new ones
git log --oneline --graph -8            # confirm history looks linear and sane
git push                                # publish
```

## When `git push` is rejected

```bash
git push                                # ! [rejected] main -> main (fetch first / non-fast-forward)
git fetch origin                        # 1. find out what arrived on the remote
git log --oneline HEAD..origin/main     # 2. the commits you do not have yet
git log --oneline origin/main..HEAD     # 3. the commits only you have
git pull --rebase                       # 4. integrate them, then push again
git push
```
Never answer a rejection with `git push --force` on a shared branch.

## When `pull` creates merge commits you did not want

```bash
git config --global pull.rebase true    # make pull always rebase (linear history)
git config --global pull.ff only        # or: fail unless it can fast-forward (most conservative)
git config --global rebase.autoStash true   # stash/unstash automatically around rebases
```

## Choose merge or rebase for syncing

| Situation | Command | History result |
|---|---|---|
| Your private feature branch, remote main moved | `git rebase origin/main` | linear, clean |
| Shared branch others are using | `git merge origin/main` | extra merge commit, but safe |
| You already pushed the branch | `git merge` (or rebase + `--force-with-lease` if it is YOUR branch only) | |
| You want main to record the feature | `git merge --no-ff feature` | visible feature bubble |

## Force-push safely

```bash
git push --force-with-lease             # refuses if someone else pushed since your last fetch
git push --force-with-lease=main:abc123 # even stricter: only if the remote is exactly at abc123
git fetch origin                        # ⚠️ never fetch immediately BEFORE --force-with-lease:
                                        #    fetching updates the lease reference and defeats the check
```

## Multiple remotes

```bash
git remote add upstream <url>           # the original project you forked
git remote add backup git@backup:/repo.git   # a second copy for safety
git push origin main && git push backup main # push to both
git fetch --all                         # update every remote's refs
git remote set-url --push origin <url>  # a different URL for pushing than for fetching
```

## Mirror a repository (full backup)

```bash
git clone --mirror <url> repo.git       # bare clone of everything: all branches and tags
cd repo.git && git remote set-url --push origin <new-url>   # point pushes elsewhere
git push --mirror                       # push every ref to the new location
```

## Submodules (a repo inside a repo)

```bash
git submodule add <url> libs/shared   # add another repo as a subfolder
git clone --recurse-submodules <url>    # clone and fetch submodules together
git submodule update --init --recursive # fetch submodule content after a normal clone
git submodule update --remote           # move submodules to their upstream's latest commit
git submodule foreach 'git status -s'   # run a command in every submodule
```
Prefer a package manager or a monorepo unless you truly need pinned sub-repos.
