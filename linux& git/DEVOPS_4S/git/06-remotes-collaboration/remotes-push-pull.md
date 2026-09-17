# Pattern: Remotes, push, pull, fetch

A **remote** is a named bookmark for another repository (usually `origin` = where you cloned from).

```bash
git remote -v                           # list your remotes with their URLs
git remote show origin                  # detailed info: branches, tracking, HEAD
git remote add origin https://github.com/user/repo.git   # add a remote called "origin"
git remote add upstream https://github.com/original/repo.git  # the repo you forked FROM
git remote rename origin github         # rename a remote
git remote set-url origin git@github.com:user/repo.git   # switch from HTTPS to SSH
git remote remove origin                # delete the bookmark
git ls-remote --heads origin            # list the remote's branches WITHOUT downloading anything
```

## fetch vs pull (the distinction that causes most confusion)

```bash
git fetch                               # download new commits and update origin/* refs — changes NOTHING locally
git fetch origin                        # explicit remote
git fetch --all                         # every remote
git fetch --prune                       # also delete origin/* refs whose remote branch is gone
git fetch --tags                        # refresh tags too
git log origin/main --oneline -5        # inspect what you just fetched, before touching your work
git diff HEAD origin/main --stat        # see how your branch differs from the remote's

git pull                                # = fetch + MERGE into your current branch
git pull --rebase                       # = fetch + REBASE your commits on top (cleaner history)
git pull --ff-only                      # = fetch, but fail instead of creating a merge commit
git pull origin feature                 # pull a specific branch from a specific remote
```
Rule: **`fetch` is always safe.** `pull` modifies your branch, so prefer fetch + inspect while learning.

## push

```bash
git push                                # push the current branch to its upstream
git push origin main                    # explicit: remote, then branch
git push -u origin feature              # -u sets the upstream so plain "git push" works afterwards
git push --set-upstream origin feature  # long form of -u
git push origin --delete feature        # delete a branch on the remote
git push origin :feature                # the older syntax for the same deletion
git push --tags                         # publish your tags
git push --follow-tags                  # push only ANNOTATED tags reachable from pushed commits
git push --force-with-lease             # force push, but ABORT if the remote moved since your fetch
git push --force                        # blind force push — overwrites others' work (avoid)
git push --dry-run                      # show what would happen, change nothing
git push origin main --atomic           # all-or-nothing when pushing several refs
```

## Track and inspect the relationship

```bash
git branch -vv                          # show each branch, its upstream, and ahead/behind counts
git status -sb                          # compact: "## main...origin/main [ahead 2]"
git rev-list --left-right --count origin/main...main   # exact ahead/behind numbers
git config --get branch.main.remote     # which remote this branch tracks
git config --get branch.main.merge      # which remote branch it tracks
git config --global push.default simple # push only the current branch (the sane default)
```

## HTTPS vs SSH

```bash
git remote set-url origin https://github.com/user/repo.git   # HTTPS: asks for a token/password
git remote set-url origin git@github.com:user/repo.git       # SSH: uses your key, no prompts
ssh -T git@github.com                                        # test that your SSH key works
git config --global credential.helper 'cache --timeout=3600' # remember HTTPS credentials briefly
```
GitHub and GitLab no longer accept account passwords over HTTPS — use a **Personal Access Token**
as the password, or switch to SSH.
