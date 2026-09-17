# Pattern: Config levels, aliases, and includes

## The three levels

```bash
git config --system core.pager less     # /etc/gitconfig     → every user on this machine (needs sudo)
git config --global user.name "Alex"    # ~/.gitconfig       → every repo of YOUR user account
git config user.name "Alex (Work)"      # .git/config        → THIS repository only (highest priority)
git config --local --list               # show only this repo's settings
git config --global --list              # show only your user settings
git config --show-origin user.name      # which file supplied this value?
```
Highest wins: **local → global → system**.

## Aliases — the biggest daily time saver

```bash
git config --global alias.st status                        # git st
git config --global alias.co checkout                      # git co
git config --global alias.br branch                        # git br
git config --global alias.ci commit                        # git ci
git config --global alias.last "log -1 HEAD --stat"        # git last = the newest commit + its files
git config --global alias.unstage "restore --staged"       # git unstage file
git config --global alias.amend "commit --amend --no-edit" # git amend = fix the last commit silently
git config --global alias.lg "log --oneline --graph --decorate --all"   # git lg = visual history
git config --global alias.aliases "config --get-regexp ^alias\."          # git aliases = list my aliases
git config --global alias.cleanup "!git branch --merged | grep -v main | xargs -r git branch -d"  # ! runs a shell command
git config --global --unset alias.st                       # remove an alias
```
An alias starting with `!` is executed by the shell, so you can use pipes and loops.

## Conditional includes — different identity per folder

```bash
git config --global --edit              # add this block to ~/.gitconfig
```
```text
[includeIf "gitdir:~/work/"]
    path = ~/.gitconfig-work            # use these settings for any repo under ~/work/
```
```bash
cat > ~/.gitconfig-work <<'CONF'        # the work-specific identity file
[user]
    name = Alex Kumar
    email = alex@company.com
CONF
cd ~/work/anyrepo && git config user.email   # prints alex@company.com automatically
```

## Other useful config keys

```bash
git config --global core.excludesFile ~/.gitignore_global   # a .gitignore for ALL your repos
git config --global merge.tool vimdiff                      # tool used by git mergetool
git config --global advice.detachedHead false               # silence the scary detached-HEAD warning
git config --global fetch.prune true                        # drop remote branches that no longer exist
git config --global rebase.autoStash true                   # stash automatically before a rebase
```
