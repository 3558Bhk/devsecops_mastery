# 09 Conflicts & Troubleshooting — Advanced Questions

**Q1.** During a rebase the conflict markers seem reversed. Explain.
```bash
git status                       # confirm you are rebasing, not merging
```
```text
<<<<<<< HEAD                     # in a REBASE, HEAD is the NEW BASE (e.g. main)
main's version
=======
your commit's version            # the incoming side is YOUR commit being replayed
>>>>>>> a1b2c3d (my commit)
```
During a **merge**, HEAD is your own branch. During a **rebase**, HEAD is the branch you moved onto.

**Q2.** See all three versions of a conflicted file, not just two.
```bash
git ls-files -u                       # stage 1 = base, stage 2 = ours, stage 3 = theirs
git show :1:file.js > base.js         # the common ancestor version
git show :2:file.js > ours.js         # your version
git show :3:file.js > theirs.js       # their version
git config --global merge.conflictStyle zdiff3   # show the base inline as ||||||| <hash>
```

**Q3.** Resolve a conflict in a binary file.
```bash
git status                            # reports "binary files differ"
git checkout --ours  -- assets/logo.png   # binaries cannot be merged — you must choose a side
git checkout --theirs -- assets/logo.png
git add assets/logo.png
```

**Q4.** A lockfile (`package-lock.json`, `poetry.lock`) conflicts on every merge. Fix it properly.
```bash
git checkout --ours package-lock.json     # take either side, it does not matter
npm install                               # regenerate it from package.json
git add package-lock.json
git merge --continue
```
```bash
printf 'package-lock.json merge=npm\n' >> .gitattributes
git config merge.npm.driver "npm install --package-lock-only"   # custom drivers must be DEFINED
git config merge.npm.name "regenerate npm lockfile"
```

**Q5.** A file was deleted on one branch and modified on the other.
```bash
git status                            # "deleted by them" or "deleted by us"
git rm path/to/file                   # accept the deletion
git add path/to/file                  # or keep your modified version
git merge --continue
```

**Q6.** Both branches added the same new file with different content.
```bash
git status                            # "added by both"
git show :2:newfile.js                # ours
git show :3:newfile.js                # theirs
# edit newfile.js to the merged content, then:
git add newfile.js && git merge --continue
```

**Q7.** Make Git remember your conflict resolutions across rebases.
```bash
git config --global rerere.enabled true    # REuse REcorded REsolution
git rerere status                          # what was auto-resolved this time
git rerere diff                            # review the recorded resolution before trusting it
ls .git/rr-cache                           # the cache itself
git rerere forget file.js                  # un-learn a wrong resolution
```

**Q8.** Open a proper three-pane merge tool.
```bash
git config --global merge.tool meld          # or vimdiff, vscode, kdiff3, p4merge
git config --global mergetool.keepBackup false   # don't scatter .orig files
git config --global mergetool.vscode.cmd 'code --wait $MERGED'   # custom tool definition
git mergetool                                # launch it for every conflicted file
```

**Q9.** Detect a "criss-cross" merge and understand the recursive strategy.
```bash
git merge-base --all main feature        # more than one common ancestor = criss-cross
git merge -X ours feature                # on conflict, prefer OUR side automatically
git merge -X theirs feature              # on conflict, prefer THEIR side automatically
git merge -s ort -X ignore-all-space feature   # ignore whitespace while merging
```
`-X ours/theirs` only affects CONFLICTING hunks; non-conflicting changes from both sides are kept.
That is different from `-s ours`, which discards the other branch's changes entirely:
```bash
git merge -s ours legacy                 # record a merge but keep our tree exactly as it is
```

**Q10.** A hook keeps rejecting your commits and you need to understand why.
```bash
ls -l .git/hooks/                        # which hooks exist and are they executable?
git config core.hooksPath                # a repo may point hooks elsewhere (e.g. .githooks)
bash -x .git/hooks/pre-commit            # trace the hook manually
git commit --no-verify                   # bypass it ONCE (⚠️ fix the cause, don't habitually skip)
```

**Q11.** Your repo is slow. Diagnose and compact it.
```bash
git count-objects -vH                    # object count and on-disk size
git log --all --oneline | wc -l          # how many commits?
git verify-pack -v .git/objects/pack/*.idx | sort -k3 -n | tail -5   # the biggest objects
git gc --aggressive --prune=now          # repack and drop unreachable objects
git config --global gc.auto 1            # let Git auto-maintain
```

**Q12.** Prove that a specific commit is an ancestor of another (used in CI checks).
```bash
git merge-base --is-ancestor v1.4.0 HEAD && echo "yes, contains the release"
git branch --contains <hash>             # which branches include this commit
git describe --contains <hash>           # the first tag that contains it
```
