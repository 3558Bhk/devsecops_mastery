# Pattern: Ignoring files with `.gitignore`

```bash
touch .gitignore                        # create the ignore rules file in your repo root
git add .gitignore                      # ignore rules belong IN the repo, so commit them
git commit -m "add .gitignore"          # now the whole team shares the same rules
git check-ignore -v node_modules/x.js   # show WHICH rule ignored a given path (great for debugging)
git status --ignored                    # list ignored files too, so you can see what is being skipped
git ls-files --others --ignored --exclude-standard   # every ignored, untracked file
```

## Rules syntax

```text
node_modules/           # ignore this folder anywhere in the tree (trailing / = directory only)
/node_modules/          # ignore ONLY at the repo root (leading / anchors it)
*.log                   # ignore every .log file anywhere
!important.log          # ! un-ignores a file matched by an earlier rule
build/                  # ignore any folder named build
dist/**                 # everything inside dist, at any depth
temp?.txt               # ? matches one character: temp1.txt, tempA.txt
**/logs/*.log           # ** matches any number of folders
*.min.js                # generated files nobody should hand-edit
.env                    # SECRETS: never commit API keys or passwords
.DS_Store               # macOS junk
Thumbs.db               # Windows junk
.idea/  .vscode/        # editor settings (unless your team shares them on purpose)
```

## A ready-to-use starter for a Node/Python project

```text
# dependencies
node_modules/
venv/
__pycache__/
*.pyc

# build output
dist/
build/
*.egg-info/

# secrets and local config
.env
.env.local
*.pem

# logs and OS junk
*.log
.DS_Store
Thumbs.db
```

## Global ignore (for junk that is YOUR problem, not the project's)

```bash
git config --global core.excludesFile ~/.gitignore_global   # point Git at a personal ignore file
printf '.DS_Store\n*.swp\n.idea/\n' > ~/.gitignore_global   # editor and OS files you never want to see
```

## ⚠️ The #1 `.gitignore` mistake

```bash
git rm --cached secret.env                # file already tracked? ignoring it does NOTHING — untrack it first
git rm -r --cached node_modules/          # untrack a whole folder but KEEP it on disk
git commit -m "stop tracking node_modules"
echo "secret.env" >> .gitignore           # now the ignore rule takes effect
```
`.gitignore` only affects **untracked** files. Anything already committed keeps being tracked
until you remove it from the index with `--cached`.
