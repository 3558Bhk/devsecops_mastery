# 02 Repo Basics — Scenario Questions

## Scenario 1
You edited five files but only want to commit the bug fix, not your debug prints.
```bash
git status -s                    # see all five modified files
git add -p app.js                # stage only the hunks that belong to the fix (y/n per hunk)
git diff --staged                # verify exactly what will be committed
git commit -m "fix: null check in user parser"
git add -A && git commit -m "wip: debug logging"   # then commit the rest separately (or stash it)
```

## Scenario 2
You typed `git commit` and it says "nothing to commit, working tree clean" — but you ARE sure you edited a file.
```bash
pwd                              # are you in the repo you think you are in?
git status                       # does Git see the change at all?
git check-ignore -v myfile.txt   # is it being ignored by a .gitignore rule?
git ls-files myfile.txt          # is it even tracked? (empty output = untracked)
git add myfile.txt               # untracked files are never committed by -a; add them explicitly
```

## Scenario 3
You committed to the wrong branch (you were on `main` instead of your feature branch).
```bash
git branch                       # confirm you are on main
git switch -c feature/fix-login  # create the feature branch HERE — it now contains your commit
git log --oneline -3             # verify the commit came with you
git switch main                  # go back to main
git reset --hard HEAD~1          # remove the commit from main (⚠️ only if not pushed)
git switch feature/fix-login     # continue working on the correct branch
```

## Scenario 4
You staged the wrong files and want to start the commit over without losing your edits.
```bash
git diff --staged --stat         # see what you accidentally staged
git restore --staged .           # unstage everything — your working-tree edits are untouched
git status -s                    # confirm: files now show " M" instead of "M "
git add only/this/file.txt       # stage just what you meant
```

## Scenario 5
A teammate cloned the repo and gets "fatal: not a git repository".
```bash
ls -a                            # is there a .git folder here?
git rev-parse --show-toplevel    # from inside, prints the root; from outside, errors
cd "$(git -C . rev-parse --show-toplevel 2>/dev/null || echo .)"   # move to the repo root if any
git init                         # if there is genuinely no repo, create one
```
Usually they are one folder too high or too low — `clone` creates a subfolder named after the repo.

## Scenario 6
You need to hand over a project to a client with NO history (clean snapshot only).
```bash
git clone --depth 1 file:///path/to/repo client-copy   # shallow clone: latest commit only
cd client-copy && rm -rf .git                          # remove all Git data
git init && git add -A && git commit -m "initial delivery"   # start fresh history
du -sh .git                                            # confirm it is small
```

## Scenario 7
You deleted a file with `rm` and Git is confused about its state.
```bash
git status -s                    # shows " D file.txt" — deleted on disk, deletion NOT staged
git add file.txt                 # stage the deletion (git add understands deletions)
git rm file.txt                  # or do both in one step next time
git commit -m "remove unused file"
git restore file.txt             # changed your mind? bring the file back from HEAD
```

## Scenario 8
A 500 MB build artefact got committed and every `git status` is slow.
```bash
git ls-files | xargs -r du -ch 2>/dev/null | sort -rh | head   # find the largest tracked files
git rm -r --cached dist/ build/                                # untrack the artefacts
printf 'dist/\nbuild/\n' >> .gitignore                         # ignore them from now on
git commit -m "stop tracking build output"
du -sh .git                                                    # history is still heavy until you purge it
```

## Scenario 9
You want a script that refuses to run unless the working tree is clean.
```bash
if [ -n "$(git status --porcelain)" ]; then    # --porcelain = machine-readable, empty when clean
    echo "Commit or stash your changes first" >&2
    exit 1
fi
git rev-parse --abbrev-ref HEAD                # print the current branch for the log line
```
