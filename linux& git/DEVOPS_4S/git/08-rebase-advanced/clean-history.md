# Pattern: Cleaning history — squashing, rewriting, purging secrets

⚠️ Everything here **rewrites commit hashes**. Fine on your own unpushed branch; dangerous on
anything shared. Coordinate before rewriting a branch other people have cloned.

## Squash messy WIP commits before a pull request

```bash
git log --oneline origin/main..HEAD      # 1. see exactly which commits are yours
git rebase -i origin/main                # 2. mark all but the first as squash/fixup
git rebase --autosquash -i origin/main   # 2b. automatic if you used --fixup while working
git reset --soft origin/main && git commit -m "feat: complete search filters"   # 3. the brute-force alternative
git log --oneline -3                     # 4. verify one clean commit remains
git push --force-with-lease              # 5. publish the rewritten branch
```

## Split one commit into two

```bash
git rebase -i HEAD~1                     # mark the commit as "edit"
git reset HEAD~1                         # unstage everything from that commit
git add src/fix.js && git commit -m "fix: handle null user"      # first logical commit
git add tests/ && git commit -m "test: cover null user case"     # second logical commit
git rebase --continue                    # finish
```

## Remove a file from ALL history (secrets, large binaries)

```bash
pip install git-filter-repo              # the officially recommended tool
git filter-repo --path config/secrets.yml --invert-paths   # delete that path from every commit
git filter-repo --path node_modules --invert-paths         # same for an accidentally committed folder
git filter-repo --strip-blobs-bigger-than 10M              # drop every blob over 10 MB
git filter-repo --replace-text expressions.txt             # redact secrets in place (see below)
git count-objects -vH                    # check the repo actually shrank
git push --force --all && git push --force --tags   # publish the rewritten history
```

`expressions.txt` format for redaction:
```text
AKIA1234567890ABCDEF==>REDACTED-AWS-KEY
regex:password\s*=\s*\S+==>password=REDACTED
```

## The alternative tool (older, still common)

```bash
# BFG Repo-Cleaner — faster and simpler for common cases
bfg --delete-files id_rsa                # remove a file by name from all history
bfg --replace-text passwords.txt         # redact secrets
bfg --strip-blobs-bigger-than 100M       # remove huge blobs
git reflog expire --expire=now --all && git gc --prune=now --aggressive   # reclaim the space afterwards
```

## Reclaim disk space after a rewrite

```bash
git reflog expire --expire=now --all     # forget the old unreachable commits
git gc --prune=now --aggressive          # garbage-collect and repack
du -sh .git                              # confirm the size dropped
```

## Remember conflict resolutions automatically (`rerere`)

```bash
git config --global rerere.enabled true  # REuse REcorded REsolution
git rerere status                        # what rerere resolved for you this time
git rerere diff                          # review the recorded resolution
ls .git/rr-cache                         # the cached resolutions
```
Massive win when you rebase a long-lived branch repeatedly and hit the same conflicts.

## Prevent problems instead of fixing them (hooks)

```bash
ls .git/hooks                            # sample hooks ship with every repo (*.sample)
cat > .git/hooks/pre-commit <<'HOOK'     # a real pre-commit hook
#!/usr/bin/env bash
set -e
if git diff --cached --name-only | grep -qE '\.env$|secret'; then
    echo "Refusing to commit a secret-looking file" >&2; exit 1
fi
HOOK
chmod +x .git/hooks/pre-commit           # hooks must be executable to run
git config core.hooksPath .githooks      # keep hooks IN the repo so the whole team gets them
```
Hooks are local and bypassable (`git commit --no-verify`), so also enforce rules in CI.

## Safety checklist before any history rewrite

```bash
git status                               # clean tree?
git stash push -u -m "before rewrite"    # save anything uncommitted
git branch backup-before-rewrite         # a branch pointing at the current state = instant undo
git log --oneline -5                     # note the hashes
# ...do the rewrite...
git push --force-with-lease              # never plain --force on a shared branch
git branch -D backup-before-rewrite      # delete the backup only once you are sure
```
