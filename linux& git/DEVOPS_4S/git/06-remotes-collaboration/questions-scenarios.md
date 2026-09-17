# 06 Remotes & Collaboration — Scenario Questions

## Scenario 1
`git push` fails: "Updates were rejected because the remote contains work that you do not have".
```bash
git fetch origin                        # what arrived?
git log --oneline --graph HEAD origin/main -8   # see the divergence
git pull --rebase                       # replay your commits on top of theirs
# resolve conflicts if any, then:
git rebase --continue
git push
```

## Scenario 2
You rebased your feature branch and now `git push` is rejected.
```bash
git push --force-with-lease             # rebasing rewrites hashes, so a force push IS correct here
```
This is safe because it is YOUR feature branch. Never do this to `main`.

## Scenario 3
Your company moved the repo from GitHub to GitLab.
```bash
git remote -v                           # note the current URL
git remote set-url origin git@gitlab.company.com:team/repo.git   # point at the new home
git fetch origin                        # verify you can reach it
git branch -vv                          # check tracking still lines up
git push -u origin main                 # re-establish upstream if needed
```

## Scenario 4
You cloned a project you want to contribute to, but you have no write access.
```bash
# fork it on the website first, then:
git remote rename origin upstream                       # the original becomes "upstream"
git remote add origin git@github.com:YOU/repo.git       # your fork becomes "origin"
git remote -v                                           # verify both
git fetch upstream                                      # pull the original's state
git switch -c feature/my-fix                            # branch, commit, then:
git push -u origin feature/my-fix                       # push to YOUR fork and open a PR upstream
```

## Scenario 5
HTTPS pushes keep asking for a password, and your password no longer works.
```bash
git remote -v                           # confirm it is an https:// URL
ssh-keygen -t ed25519 -C "you@example.com"    # create a key if you don't have one
cat ~/.ssh/id_ed25519.pub               # copy this into GitHub → Settings → SSH keys
git remote set-url origin git@github.com:user/repo.git   # switch to SSH
ssh -T git@github.com                   # test
git push                                # no more prompts
```
Or stay on HTTPS and use a **Personal Access Token** as the password plus a credential helper.

## Scenario 6
A teammate force-pushed main and your local history no longer matches.
```bash
git fetch origin
git log --oneline --graph origin/main -5      # what main looks like now
git log --oneline --graph main -5             # what yours looks like
git switch main && git reset --hard origin/main   # adopt their version (⚠️ loses your local-only commits)
git reflog                                    # if you needed those commits, find them here first
git switch -c rescue <hash>                   # and save them on a branch
```

## Scenario 7
You need an exact backup of a repository before a risky migration.
```bash
git clone --mirror <url> backup.git           # every branch, tag and ref, nothing checked out
cd backup.git && git count-objects -vH        # size check
git push --mirror /mnt/backup/repo.git        # copy to another location
git remote update --prune                     # refresh the mirror later
```

## Scenario 8
CI needs a fast clone of a huge monorepo, latest commit only.
```bash
git clone --depth 1 --single-branch -b main <url>   # minimal history, one branch
git submodule update --init --depth 1               # shallow submodules too
git fetch --unshallow                               # only if the job genuinely needs full history
```

## Scenario 9
Two developers keep creating merge commits on every pull and history looks like a railway map.
```bash
git config --global pull.rebase true        # each developer sets this
git config --global rebase.autoStash true   # so local edits don't block the rebase
git log --oneline --graph -15               # before
git pull --rebase && git log --oneline --graph -15   # after: linear
```
Team-wide, enforce it with a pre-push hook or by requiring "Rebase and merge" on the host.

## Scenario 10
You pushed a commit containing an API key to a shared branch five minutes ago.
```bash
git log --oneline -5                        # find the commit
git revert <hash> && git push               # remove it going forward on a shared branch
```
Then, non-negotiably:
1. **Rotate/revoke the key right now** — treat it as compromised.
2. Purge history with `git filter-repo --replace-text` if policy requires it.
3. Force-push the rewritten history and have everyone re-clone.
4. Add `.env` and secret patterns to `.gitignore` and a pre-commit secret scanner.
