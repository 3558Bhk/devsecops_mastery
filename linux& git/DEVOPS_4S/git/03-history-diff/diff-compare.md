# Pattern: Comparing things with `git diff`

`git diff` answers "what is different between X and Y?" for any two points.

```bash
git diff                                # working directory vs staging area (your unstaged edits)
git diff --staged                       # staging area vs HEAD (what the next commit will contain)
git diff --cached                       # exact synonym of --staged
git diff HEAD                           # working directory vs HEAD (all changes, staged or not)
git diff HEAD~1 HEAD                    # between the previous commit and the last one
git diff main feature                   # between two branch tips
git diff main...feature                 # three dots: changes on feature SINCE it branched off main
git diff a1b2c3d e4f5g6h                # between any two commits
git diff -- src/app.js                  # only one file
git diff HEAD~3 -- src/                 # only one folder, over three commits
git diff --stat                         # summary: file names with +N -N counts
git diff --shortstat                    # one line total: "3 files changed, 42 insertions(+)"
git diff --name-only                    # just the file names (perfect for scripts)
git diff --name-status                  # names with M/A/D/R status letters
git diff -w                             # ignore ALL whitespace changes
git diff --ignore-space-at-eol          # ignore only end-of-line whitespace (CRLF noise)
git diff --word-diff                    # highlight changed WORDS instead of whole lines
git diff --color-words                  # same idea, cleaner output
git diff --diff-filter=M                # only Modified files (A=added, D=deleted, R=renamed)
git diff --no-index file1.txt file2.txt # diff two files that are NOT in a repo at all
git difftool                            # open the diff in your configured visual tool
```

## The three-dot vs two-dot difference (memorise this)

```bash
git diff main..feature                  # two dots: full difference between the two tips
git diff main...feature                 # three dots: only what feature changed since the merge base
git merge-base main feature             # the common ancestor the three-dot form starts from
```
For reviewing a pull request you almost always want the **three-dot** form.

## Patch files — save and apply a diff

```bash
git diff > mychanges.patch              # save your uncommitted work as a patch file
git diff HEAD~2 HEAD > last2.patch      # save two commits' worth of changes
git apply mychanges.patch               # apply a patch to the working directory
git apply --check mychanges.patch       # test whether it would apply cleanly, change nothing
git apply --stat mychanges.patch        # see what the patch contains first
git format-patch -1 HEAD                # produce an email-ready .patch WITH commit metadata
git am 0001-fix.patch                   # apply such a patch and recreate the commit
```

## Reading a diff

```text
diff --git a/src/app.js b/src/app.js    # which file, a=old version, b=new version
index 8a3f2c1..91b4d7e 100644           # blob hashes and the file mode
--- a/src/app.js                        # the old side
+++ b/src/app.js                        # the new side
@@ -12,7 +12,9 @@ function login() {     # hunk header: old starts line 12 (7 lines), new line 12 (9 lines)
-    const x = 1                         # red  - = removed line
+    const x = 2                         # green + = added line
     return x                            # no prefix = unchanged context line
```
