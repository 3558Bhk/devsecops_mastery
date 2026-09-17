# 01 Setup & Config — Basic Questions

**Q1.** Check that Git is installed and which version.
```bash
git --version                  # prints e.g. git version 2.47.3
```

**Q2.** Set the name and email that appear on your commits.
```bash
git config --global user.name "Alex Kumar"       # --global applies to every repo of your account
git config --global user.email "alex@example.com"
```

**Q3.** See every setting currently in effect.
```bash
git config --list              # all settings, merged from every level
```

**Q4.** See which FILE each setting came from.
```bash
git config --list --show-origin   # shows ~/.gitconfig vs .git/config vs /etc/gitconfig
```

**Q5.** Read one specific setting.
```bash
git config user.email          # prints your configured email
```

**Q6.** What are the three config levels, and which one wins?
```bash
git config --system ...        # /etc/gitconfig    → whole machine
git config --global ...        # ~/.gitconfig      → your user account
git config ...                 # .git/config       → this repo only, and it WINS
```

**Q7.** Use a different email for one work repo only.
```bash
cd ~/work/project              # go into the repo
git config user.email "alex@company.com"   # no --global = this repo only
```

**Q8.** Make new repositories start on a branch called `main`.
```bash
git config --global init.defaultBranch main   # affects every future "git init"
```

**Q9.** Choose the editor Git opens for commit messages.
```bash
git config --global core.editor "nano -w"   # -w makes Git wait until you close the file
```

**Q10.** Create a shortcut so `git st` means `git status`.
```bash
git config --global alias.st status   # aliases live in ~/.gitconfig under [alias]
```

**Q11.** Which file lists the paths Git should ignore?
```bash
cat .gitignore                   # in the repo root; commit it so the team shares the rules
```

**Q12.** Write a rule that ignores every `.log` file and the `node_modules` folder.
```text
*.log                            # matches any .log file anywhere in the tree
node_modules/                    # trailing slash = a directory
```

**Q13.** Add a brand-new ignore file to the repository.
```bash
git add .gitignore               # stage it like any other file
git commit -m "add .gitignore"   # commit it
```

**Q14.** Open your global config file in an editor.
```bash
git config --global --edit       # opens ~/.gitconfig
cat ~/.gitconfig                 # or just read it
```
