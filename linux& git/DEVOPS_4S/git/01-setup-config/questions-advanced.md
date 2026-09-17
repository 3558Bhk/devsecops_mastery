# 01 Setup & Config — Advanced Questions

**Q1.** A file is already tracked but you just added it to `.gitignore`, and Git still sees changes. Why?
```bash
git rm --cached tracked.log      # remove it from the INDEX but keep it on disk
git commit -m "stop tracking tracked.log"   # now the .gitignore rule takes effect
```
`.gitignore` only affects **untracked** files.

**Q2.** Find out exactly which rule caused a file to be ignored.
```bash
git check-ignore -v build/app.js   # -v prints the file, line number and pattern that matched
```

**Q3.** Ignore `node_modules` only at the repo root, but not in a nested sub-project.
```text
/node_modules/                   # the leading slash anchors the rule to the repo root
```

**Q4.** Un-ignore one file inside an ignored folder.
```text
logs/                            # ignore the whole folder
!logs/keep.log                   # ! re-includes one file
```
Careful: Git never descends into an ignored directory, so `!logs/keep.log` only works if the
folder itself is not excluded. Use this instead:
```text
logs/*                           # ignore the CONTENTS, so Git still looks inside the folder
!logs/keep.log                   # now the exception works
```

**Q5.** Write an alias that runs a real shell command with pipes.
```bash
git config --global alias.merged "!git branch --merged | grep -vE '(main|master)' | xargs -r git branch -d"
git merged                       # deletes every branch already merged into main
```
The leading `!` hands the string to your shell instead of treating it as a Git subcommand.

**Q6.** Use different identities automatically for work and personal repos.
```bash
git config --global --edit       # add to ~/.gitconfig:
```
```text
[includeIf "gitdir:~/work/"]
    path = ~/.gitconfig-work
[includeIf "gitdir:~/personal/"]
    path = ~/.gitconfig-personal
```
```bash
cd ~/work/api && git config user.email   # resolves to the work email automatically
```

**Q7.** Configure line-ending handling correctly per operating system.
```bash
git config --global core.autocrlf input    # Linux/macOS: convert CRLF→LF on commit, no conversion on checkout
git config --global core.autocrlf true     # Windows: convert LF→CRLF on checkout, CRLF→LF on commit
git config --global core.eol lf            # force LF in the working tree
```
```text
# .gitattributes — the portable, per-repo answer that works for the whole team
* text=auto eol=lf
*.bat text eol=crlf
*.png binary
```

**Q8.** Ignore files for ALL your repos without touching every `.gitignore`.
```bash
git config --global core.excludesFile ~/.gitignore_global   # register a personal global ignore file
printf '.DS_Store\n*.swp\n.idea/\n' > ~/.gitignore_global   # OS and editor junk
```

**Q9.** Verify a repo's local config never leaks a personal setting.
```bash
cat .git/config                  # the repo's own file — this is what teammates do NOT get
git config --local --list        # same content, parsed
```
`.git/config` is not committed; only `.gitignore` and `.gitattributes` are shared with the team.

**Q10.** Make Git's advice messages quieter (or louder) for learning.
```bash
git config --global advice.detachedHead false    # hide the detached-HEAD warning
git config --global advice.statusUoption false   # hide the "-u" hint in status
git config --global --get-regexp '^advice'       # list all advice flags currently set
```

**Q11.** Remove a setting or an alias you no longer want.
```bash
git config --global --unset alias.st        # delete one alias
git config --global --unset-all alias.st    # delete every entry with that key
git config --global --edit                  # or edit the file and delete the lines
```

**Q12.** Which identity will THIS commit use? Check before committing.
```bash
git var GIT_COMMITTER_IDENT      # prints the exact name/email/timestamp Git will stamp
git log -1 --format='%an <%ae>'  # and what the last commit actually used
```
