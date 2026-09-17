# Pattern: The daily loop — status, add, commit

```bash
git status                              # THE most important command: what changed, what is staged
git status -s                           # short format: two columns (staged, unstaged)
git status -sb                          # short + branch and how far ahead/behind the remote you are
git add file.txt                        # stage ONE file for the next commit
git add .                               # stage everything in the current folder and below
git add -A                              # stage ALL changes in the whole repo (adds, edits, deletions)
git add -u                              # stage only MODIFIED and DELETED tracked files (no new files)
git add -p                              # stage INTERACTIVELY, hunk by hunk — the pro move
git add -n .                            # -n dry run: show what WOULD be staged, stage nothing
git diff --staged                       # review exactly what you are about to commit
git commit -m "add login validation"    # create the snapshot with a one-line message
git commit                              # opens your editor for a multi-line message
git commit -am "fix typo"               # -a stages all TRACKED modified files, then commits
git commit -m "title" -m "body text"    # two -m flags = subject line + detailed body
git commit --amend -m "better message"  # rewrite the LAST commit's message (or add staged files to it)
git commit --allow-empty -m "trigger CI"  # an empty commit, useful to re-run a pipeline
git show --stat HEAD                    # inspect the commit you just made
git log --oneline -5                    # the last 5 commits, one line each
```

## Reading `git status -s`

```text
 M file.txt        # space+M = modified but NOT staged
M  file.txt        # M+space = modified AND staged
MM file.txt        # staged some changes, then modified it again afterwards
A  new.txt         # new file, staged
?? new.txt         # untracked: Git has never seen this file
D  old.txt         # deleted and staged
 D old.txt         # deleted on disk but not staged yet
```

## A good commit message

```bash
git commit -m "fix: handle empty cart in checkout" -m "Previously checkout crashed with a
ZeroDivisionError when the cart had no items. Return early with a 400 instead.

Refs: #1234"        # -m paragraphs become the message body; reference the ticket at the end
```
Subject line: ≤ 50 characters, imperative mood ("add", not "added"), no full stop.
Body: explain WHY, not what — the diff already shows what.

## Remove a file properly

```bash
rm file.txt && git add file.txt         # manual: delete then stage the deletion
git rm file.txt                         # one step: delete from disk AND stage it
git rm --cached file.txt                # untrack it but KEEP the file on disk
git mv old.txt new.txt                  # rename/move and stage it in one command
```
