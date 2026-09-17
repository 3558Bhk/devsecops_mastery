# 01 Setup & Config — Scenario Questions

## Scenario 1
Your first `git commit` fails with *"Please tell me who you are"*.
```bash
git config --global user.name "Alex Kumar"       # set the identity Git is asking for
git config --global user.email "alex@example.com"
git commit -m "retry"                            # now it works
git log -1 --format='%an <%ae>'                  # confirm the commit carries the right identity
```

## Scenario 2
Your commits on GitHub show as a grey anonymous avatar, not your profile.
```bash
git config user.email                            # check what you actually committed with
```
The email must EXACTLY match one of the emails on your GitHub account.
```bash
git config --global user.email "alex@example.com"    # fix it for future commits
git commit --amend --reset-author --no-edit          # fix the MOST RECENT commit's author
git push --force-with-lease                          # only if you already pushed it (and it's your branch)
```

## Scenario 3
You accidentally committed `node_modules/` (30 000 files) and the repo is huge.
```bash
git rm -r --cached node_modules/                 # untrack it, keep the files on disk
echo "node_modules/" >> .gitignore               # ignore it from now on
git commit -m "stop tracking node_modules"
du -sh .git                                      # the old snapshots still live in history
git filter-repo --path node_modules --invert-paths   # to really purge it (install git-filter-repo)
```
Purging history rewrites commits, so coordinate with the team and force-push afterwards.

## Scenario 4
You committed an `.env` file containing a real API key.
```bash
git log --oneline -- .env                        # confirm it is in history
git rm --cached .env && echo ".env" >> .gitignore   # stop tracking it going forward
git commit -m "remove .env from tracking"
git filter-repo --path .env --invert-paths       # remove it from ALL history
```
⚠️ If it was ever pushed, **rotate the key immediately**. Removing it from Git does not
un-leak it — clones, caches and bots may already have it.

## Scenario 5
Two teams share one machine and need different names/emails per project folder.
```bash
git config --global --edit                       # add conditional includes
```
```text
[includeIf "gitdir:/srv/team-a/"]
    path = ~/.gitconfig-team-a
[includeIf "gitdir:/srv/team-b/"]
    path = ~/.gitconfig-team-b
```
```bash
cd /srv/team-a/api && git config user.email      # verify the right identity is picked up
```

## Scenario 6
You keep typing the same long `git log` incantation. Make it one word.
```bash
git config --global alias.lg "log --oneline --graph --decorate --all"
git config --global alias.last "log -1 --stat"
git lg                                           # now the whole history graph in one command
git aliases 2>/dev/null || git config --get-regexp '^alias\.'   # list what you have defined
```

## Scenario 7
Teammates on Windows keep committing CRLF line endings and every diff looks changed.
```text
# create .gitattributes in the repo root — this travels with the repo and fixes it for everyone
* text=auto eol=lf
*.bat text eol=crlf
*.sh  text eol=lf
*.png binary
*.jpg binary
```
```bash
git add .gitattributes && git commit -m "enforce LF line endings"
git add --renormalize .                          # re-apply the rules to every existing file
git status                                       # review what changed
git commit -m "renormalize line endings"
```

## Scenario 8
You want to know why a weird setting is being applied to one repo only.
```bash
git config --list --show-origin | less           # every setting with the file that supplied it
cat .git/config                                  # the repo-local file (highest priority)
git config --local --list                        # just the local settings
git config --local --unset some.key              # remove a stray local override
```

## Scenario 9
Set up a brand-new machine for Git work in one pass.
```bash
sudo apt install git jq curl                     # Git plus a few essentials
git config --global user.name "Alex Kumar"       # identity
git config --global user.email "alex@example.com"
git config --global init.defaultBranch main      # modern default branch name
git config --global pull.rebase false            # predictable pull behaviour
git config --global core.editor "nano -w"        # commit-message editor
git config --global credential.helper 'cache --timeout=3600'   # don't retype passwords
git config --global core.excludesFile ~/.gitignore_global      # personal ignore file
printf '.DS_Store\n*.swp\n.idea/\n' > ~/.gitignore_global
ssh-keygen -t ed25519 -C "alex@example.com"      # key for GitHub/GitLab
ssh -T git@github.com                            # test the key
git config --global --list                       # final review
```
