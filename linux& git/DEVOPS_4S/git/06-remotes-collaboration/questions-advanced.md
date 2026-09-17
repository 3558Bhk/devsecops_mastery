# 06 Remotes & Collaboration — Advanced Questions

**Q1.** `git push` is rejected as "non-fast-forward". Walk through the correct recovery.
```bash
git fetch origin                        # 1. get the remote's new commits
git log --oneline HEAD..origin/main     # 2. what they added
git log --oneline origin/main..HEAD     # 3. what only you have
git pull --rebase                       # 4. replay your commits on top
git push                                # 5. now it fast-forwards
```

**Q2.** Force-push without destroying a colleague's work.
```bash
git push --force-with-lease             # aborts if origin/branch moved since your last fetch
git push --force-with-lease=main:a1b2c3 # even stricter: only if the remote is exactly at this hash
git push --force                        # blind overwrite — never on a shared branch
```
Do not `git fetch` immediately before `--force-with-lease`; fetching refreshes the lease and
defeats the protection.

**Q3.** Work with a fork of someone else's project.
```bash
git remote add upstream https://github.com/original/repo.git   # the source project
git fetch upstream
git switch main && git merge --ff-only upstream/main           # sync your main
git push origin main                                           # publish to your fork
git switch -c feature && git rebase main                       # work on top of the synced main
```

**Q4.** Push the same work to two remotes.
```bash
git remote add backup git@backup.example.com:team/repo.git
git push origin main && git push backup main       # explicitly
git remote set-url --add --push origin git@backup.example.com:team/repo.git   # or make push do both
git config --get-all remote.origin.pushurl         # verify
```

**Q5.** Mirror an entire repository, all branches and tags.
```bash
git clone --mirror <url> repo.git          # bare mirror clone
cd repo.git && git push --mirror <new-url> # push every ref to the new home
git remote update --prune                  # keep the mirror current
```

**Q6.** Review a GitHub pull request locally before approving it.
```bash
git fetch origin pull/42/head:pr-42        # GitHub's magic ref for PR #42
git switch pr-42                           # check it out
git diff main...pr-42 --stat               # review the summary
git worktree add ../pr-42 pr-42            # or run it in a separate folder
```

**Q7.** Configure a sane default sync behaviour for the whole team.
```bash
git config --global pull.rebase true       # pull = fetch + rebase → linear history
git config --global rebase.autoStash true  # stash local edits automatically during rebase
git config --global push.default simple    # push only the current branch to its upstream
git config --global fetch.prune true       # always prune dead remote branches
git config --global advice.skippedCherryPicks false   # quieter rebases
```

**Q8.** Exactly how far apart are two branches?
```bash
git rev-list --left-right --count origin/main...main   # prints "behind<TAB>ahead"
git status -sb                                          # the human-readable version
git cherry -v origin/main                               # your commits not yet upstream (+ = missing)
```

**Q9.** Push a single commit from a branch that has other unfinished work.
```bash
git switch -c to-push main               # clean branch from main
git cherry-pick <hash>                   # copy just the commit you want to publish
git push -u origin to-push
```

**Q10.** Debug authentication failures.
```bash
GIT_SSH_COMMAND="ssh -v" git fetch origin   # verbose SSH handshake
GIT_CURL_VERBOSE=1 git fetch origin         # verbose HTTPS
git remote -v                               # is the URL even correct?
ssh -T git@github.com                       # test the key independently
git config --global credential.helper       # is a stale cached credential being used?
```

**Q11.** Fetch only one branch to save time on a huge repo.
```bash
git clone --single-branch -b main <url>     # clone only main
git remote set-branches origin main         # restrict an existing clone to main
git fetch --depth 1 origin main             # shallow: latest commit only
git fetch --unshallow                       # undo the shallowness later
```

**Q12.** Why does `origin/main` exist locally at all?
```bash
git branch -r                               # remote-TRACKING branches are local caches
git log origin/main --oneline -3            # readable offline, updated only by fetch/pull
cat .git/refs/remotes/origin/main           # the raw cached hash (or packed-refs)
```
They are snapshots of the remote's state at your last fetch — not live views.
