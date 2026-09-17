# Pattern: The errors everyone meets — and the fix for each

## "fatal: not a git repository"

```bash
pwd                                  # are you inside the project folder at all?
ls -a                                # is there a .git directory here?
git rev-parse --show-toplevel        # prints the repo root if you are anywhere inside it
cd "$(git rev-parse --show-toplevel)"   # jump to the repo root
git init                             # there really is no repo → create one
```

## "Please tell me who you are"

```bash
git config --global user.name "Your Name"       # set your identity
git config --global user.email "you@example.com"
git commit -m "retry"                            # works now
```

## "Updates were rejected because the remote contains work that you do not have"

```bash
git fetch origin                     # see what arrived
git pull --rebase                    # replay your commits on top of theirs
git push                             # try again
# NEVER answer this with git push --force on a shared branch
```

## "Your local changes would be overwritten by merge/checkout"

```bash
git status -s                        # which files are dirty?
git stash push -u -m "wip"           # save them
git switch otherbranch               # now the switch works
git stash pop                        # restore them later
git checkout -f otherbranch          # -f DISCARDS your changes (only if you are sure)
```

## "error: failed to push some refs" + "non-fast-forward"

Same as the rejected-push case above: `git fetch` then `git pull --rebase` then `git push`.

## "fatal: refusing to merge unrelated histories"

```bash
git pull origin main --allow-unrelated-histories   # two repos with no common ancestor
```
Happens when you `git init` locally and then pull a remote repo that was created separately
(e.g. GitHub's "Add a README" option).

## "You are in a detached HEAD state"

```bash
git status                           # read the message — it is advice, not an error
git switch -c save-my-work           # keep the commits you made while detached
git switch main                      # or just go back; detached commits become unreachable
git reflog                           # find them again if you already left
```

## "cannot rebase: You have unstaged changes"

```bash
git status -s                        # find the dirty files
git stash push -u -m "before rebase" # stash them
git rebase origin/main
git stash pop                        # restore afterwards
git config --global rebase.autoStash true   # or make Git do this automatically forever
```

## "error: pathspec 'branchname' did not match any file(s) known to git"

```bash
git branch -a                        # is the branch spelled correctly? does it exist?
git fetch origin                     # maybe it exists only on the remote and you haven't fetched
git switch -c branchname             # you meant to CREATE it (missing -c)
git switch --track origin/branchname # or check out the remote branch
```

## "fatal: ambiguous argument 'HEAD~1': unknown revision"

```bash
git log --oneline                    # does the repo even have a commit yet?
git rev-list --count HEAD            # 1 means HEAD~1 does not exist (no parent)
```
A brand-new repo with one commit has no `HEAD~1`.

## "CONFLICT (content): Merge conflict in ..."

```bash
git status                           # lists the conflicted files
git diff --name-only --diff-filter=U # just their names
# resolve markers → git add <file> → git merge --continue / git rebase --continue
git merge --abort                    # or give up entirely
```
See `resolve-conflicts.md` for the full procedure.

## "fatal: early EOF" / "RPC failed" while cloning a big repo

```bash
git clone --depth 1 <url>            # shallow clone first
cd repo && git fetch --unshallow     # then download the rest
git config --global http.postBuffer 524288000   # raise the HTTP buffer for flaky connections
```

## "Permission denied (publickey)"

```bash
ssh -T git@github.com                # test the key
ls -l ~/.ssh/id_ed25519              # must be mode 600
chmod 600 ~/.ssh/id_ed25519 && chmod 700 ~/.ssh
ssh-add -l                           # is the key loaded in the agent?
ssh-add ~/.ssh/id_ed25519
git remote -v                        # or switch to HTTPS if you prefer tokens
```

## "error: src refspec main does not match any"

```bash
git branch --show-current            # your branch may be called master, not main
git branch -M main                   # rename it to main
git push -u origin main
```

## "Another git process seems to be running... index.lock"

```bash
ps aux | grep -v grep | grep git     # is a git process genuinely running? wait for it
ls -l .git/index.lock                # if not, it is a stale lock from a crashed process
rm .git/index.lock                   # remove it ONLY when no git process is alive
```

## "fatal: unable to access ... SSL certificate problem"

```bash
sudo apt install ca-certificates && sudo update-ca-certificates   # usually a missing/expired CA bundle
git config --global http.sslVerify true    # keep verification ON; fix the clock or the CA store instead
sudo timedatectl set-ntp true              # a wrong system clock also causes certificate errors
```
Never "fix" this with `http.sslVerify false` on a real project — it disables encryption checks.

## General debugging habits

```bash
git status                           # the answer is usually right here
git <command> --help                 # the manual for any subcommand
GIT_TRACE=1 git fetch                # trace what Git is doing internally
GIT_CURL_VERBOSE=1 git push          # verbose HTTPS debugging
GIT_SSH_COMMAND="ssh -v" git fetch   # verbose SSH debugging
git config --list --show-origin      # which config file is causing this behaviour?
```
