# Git Commands - SDE3 Level

## Basics
```bash
git init
git clone https://github.com/user/repo.git
git clone -b develop <url>
git status
git add .
git add file.txt
git commit -m "feat: add login"
git commit --amend -m "new msg"
git log --oneline --graph --all -20
git diff
git diff --staged
```

## Branching (Most Asked)
```bash
git branch
git branch -a
git branch feature/login
git checkout -b feature/login
git switch -c feature/login # new way
git checkout develop
git merge feature/login
git merge --no-ff feature/login # keep history
git rebase main # replay commits
git rebase -i HEAD~3 # interactive squash
git cherry-pick commit_hash
git branch -d feature/login
git branch -D feature/login # force
```

## Remote
```bash
git remote -v
git remote add origin <url>
git push origin main
git push -u origin feature/login
git push --force-with-lease # safe force
git fetch origin
git pull origin main
git pull --rebase origin main
```

## Undo / Fix
```bash
git restore file.txt # discard changes
git restore --staged file.txt # unstage
git reset HEAD~1 # soft reset last commit keep changes
git reset --hard HEAD~1 # delete last commit
git revert <commit> # create revert commit
git stash
git stash list
git stash pop
git stash apply stash@{0}
git stash drop
```

## Advanced SDE3
```bash
git bisect start # find bug commit
git blame file.txt
git tag v1.0.0
git tag -a v1.0.0 -m "release"
git push origin --tags
git show <commit>
git reflog # recover lost commits
git config --global user.name "Name"
git config --global user.email "email"
git config --global alias.lg "log --oneline --graph --all"
```

## GitFlow Questions
- **merge vs rebase**: merge keeps history, rebase linear clean history but rewrites.
- **squash**: Combine multiple commits into one before PR.
- **force push**: Dangerous, use --force-with-lease.
- **PR**: feature -> develop -> release -> main

## Jenkins + Git
- Webhook: GitHub -> Jenkins URL /github-webhook/
- Poll SCM: `H/5 * * * *`
- Checkout: `git branch: 'main', url: '...'`
