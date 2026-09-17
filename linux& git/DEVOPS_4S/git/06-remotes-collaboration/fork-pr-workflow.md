# Pattern: Forks, pull requests, and the daily team workflow

## The fork workflow (open source and most company projects)

```bash
# 1. On GitHub/GitLab: click Fork — this creates YOUR copy of the project
git clone git@github.com:YOURNAME/repo.git          # 2. clone YOUR fork
cd repo
git remote add upstream git@github.com:ORIGINAL/repo.git   # 3. add the original as "upstream"
git remote -v                                        # verify: origin = your fork, upstream = the original
git fetch upstream                                   # 4. get the original's latest state

git switch -c feature/search-filters                 # 5. always work on a branch, never on main
# ...edit, test...
git add -A && git commit -m "feat: add search filters"
git push -u origin feature/search-filters            # 6. push the branch to YOUR fork

# 7. On the website: "Compare & pull request" → base: ORIGINAL/main ← head: YOURNAME/feature
# 8. Address review comments with new commits, push again — the PR updates automatically
git push                                             # 9. no need for -u again

# 10. After the PR is merged, sync up:
git switch main
git fetch upstream && git merge --ff-only upstream/main   # bring your main up to date
git push origin main                                     # and publish it to your fork
git branch -d feature/search-filters                     # delete the merged local branch
git push origin --delete feature/search-filters          # and the remote one
```

## Keeping your fork in sync

```bash
git fetch upstream                       # refresh upstream's refs
git switch main && git merge --ff-only upstream/main   # fast-forward your main (never commit on it)
git switch feature/x && git rebase main  # rebase your feature onto the updated main
git push --force-with-lease              # rebase rewrote hashes, so a force push is required
```

## Daily team workflow (trunk-based / feature branches)

```bash
git switch main && git pull              # 1. start from an up-to-date main
git switch -c fix/1234-cart-total        # 2. small, focused branch named after the ticket
# 3. code in small steps
git status -s                            # 4. review before staging
git add -p                               # 5. stage deliberately
git commit -m "fix(cart): round totals to 2 decimals"   # 6. Conventional Commits style
git push -u origin fix/1234-cart-total   # 7. publish and open a PR
```

## Conventional Commits (makes changelogs automatic)

```text
feat:     a new feature
fix:      a bug fix
docs:     documentation only
style:    formatting, no code change
refactor: code change that neither fixes a bug nor adds a feature
perf:     performance improvement
test:     adding or fixing tests
chore:    build process, dependencies, tooling
```
```bash
git log --oneline --grep="^fix" main..HEAD   # list just the fixes in this branch
```

## Reviewing someone else's PR locally

```bash
git fetch origin pull/42/head:pr-42    # GitHub: fetch PR #42 into a local branch
git switch pr-42                       # check it out and test it
git worktree add ../pr-42 pr-42        # or test it in a separate folder
git diff main...pr-42 --stat           # review the file-level summary first
```

## Protect the important branches

On GitHub/GitLab (not in Git itself): mark `main` as protected → require PR reviews, require
passing CI, forbid force-push and deletion. Then these mistakes become impossible:
```bash
git push --force origin main           # rejected by the server
git push origin --delete main          # rejected by the server
```
