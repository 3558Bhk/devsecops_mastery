# Pattern: Installing Git and first-time setup

```bash
sudo apt install git                    # Debian/Ubuntu/Mint
sudo dnf install git                    # Fedora/RHEL
sudo pacman -S git                      # Arch
brew install git                        # macOS
git --version                           # confirm the install and see the version
```

## The two settings Git refuses to work without

```bash
git config --global user.name "Alex Kumar"          # the name stamped on every commit you make
git config --global user.email "alex@example.com"   # the email stamped on every commit
```
Without these, `git commit` stops with *"Please tell me who you are"*.
Use the SAME email as your GitHub/GitLab account so your commits show your avatar.

## Recommended one-time settings

```bash
git config --global init.defaultBranch main         # new repos start on "main" instead of "master"
git config --global core.editor "nano -w"           # editor for commit messages (-w = wait until you close it)
git config --global core.autocrlf input             # Linux/Mac: normalise Windows line endings on commit
git config --global pull.rebase false               # pull = fetch + merge (false) or fetch + rebase (true)
git config --global color.ui auto                   # coloured output (already the default on modern Git)
git config --global push.default simple             # push only the current branch to its upstream
git config --global credential.helper 'cache --timeout=3600'   # remember your password for 1 hour
git config --global alias.st status                 # create "git st" as a shortcut for status
git config --global alias.lg "log --oneline --graph --all"     # "git lg" = pretty history graph
```

## Inspect what you configured

```bash
git config --list                       # every setting in effect, all levels merged
git config --list --show-origin         # same, but shows WHICH file each setting came from
git config user.email                   # read one specific value
git config --global --edit              # open ~/.gitconfig in your editor
cat ~/.gitconfig                        # or just read the file directly
```

## Per-repo identity (work email vs personal email)

```bash
cd ~/work/project                       # go to the repo that needs a different identity
git config user.email "alex@company.com"   # WITHOUT --global = this repo only
git config user.name "Alex (Work)"         # overrides the global value inside this repo
git config --list --show-origin            # verify which file won
```
Precedence: **repo (.git/config) > user (~/.gitconfig) > system (/etc/gitconfig)**.
