# 01 Fundamentals — Advanced Questions

**Q1.** Why can't you have both a branch named `feature` and one named `feature/login`?
```bash
git branch feature && git branch feature/login   # error: 'feature' is not a valid ref name here
```
Refs are stored as files under `.git/refs/heads/`. `feature` would have to be both a **file** and a
**directory** at the same time. `git pack-refs` does not help — the D/F (directory/file) conflict is
fundamental to the ref storage model.

**Q2.** Explain the reflog of a *branch* versus the reflog of HEAD.
```bash
git reflog                       # HEAD's movements: every checkout, commit, reset, rebase
git reflog show main             # only the commits the "main" ref has pointed at
git reflog show origin/main      # even remote-tracking refs have a reflog (records fetch/push updates)
```
Use `git reflog show origin/main` to prove what the remote branch looked like before someone
force-pushed it — essential in a force-push incident.

**Q3.** Why does `git branch -d` sometimes refuse, and when is `-D` legitimate?
```bash
git branch -d feature            # refuses unless the branch is fully merged into HEAD or its upstream
git branch --merged main         # the check Git performs
git branch -D feature            # legitimate after a SQUASH merge (hashes differ, so Git can't see it)
```
Squash and rebase merges rewrite hashes, so `--merged` reports "not merged" even though the content
landed. Verify first: `git log main --oneline --grep "PROJ-1234"` or `git cherry main feature`.

**Q4.** What does `git cherry` tell you that `--merged` cannot?
```bash
git cherry -v main feature       # + = commit NOT upstream, - = an equivalent patch IS upstream
```
It compares **patch-ids** (content), not hashes — so it correctly identifies cherry-picked and rebased
commits. This is the right tool for "did my work actually land?"

**Q5.** Case-insensitive filesystems: what breaks and how do you defend?
```bash
git config --get core.ignorecase           # true on macOS/Windows
git branch Feature/X; git branch feature/x # collide on macOS/Windows, coexist on Linux → corrupt clones
```
Defence: enforce lowercase in a server-side `pre-receive` hook or host ruleset; never rely on case to
distinguish branches; watch for "warning: unable to rmdir" and ref errors after cross-OS work.

**Q6.** Stacked branches: how do you re-parent a child PR after the parent merges?
```bash
git rebase --onto main db-schema api-layer
# reads: take the commits in db-schema..api-layer and replay them onto main
git log --oneline main..HEAD              # should now contain only THIS slice's commits
git push --force-with-lease
```
Without `--onto`, `git rebase main` would try to replay the parent's commits too and conflict.

**Q7.** Why is "branch lifetime" a better health metric than "number of branches"?
```bash
git for-each-ref --sort=committerdate refs/heads --format='%(committerdate:relative)|%(refname:short)' | head -5
git log --oneline main..origin/feature/old --  | wc -l   # divergence size, not just age
```
A team can have 50 branches and be healthy if each lives two days. Long-lived branches accumulate
divergence, and divergence is what creates conflicts, risky merges and delayed feedback.

**Q8.** How do you measure divergence between a branch and the trunk?
```bash
git rev-list --left-right --count main...feature   # "behind<TAB>ahead"
git diff --shortstat main...feature                # lines/files the branch changes
git merge-tree --write-tree main feature >/dev/null 2>&1 && echo CLEAN || echo CONFLICT   # predicted
git merge-tree --write-tree --name-only main feature   # which files would conflict
```
`git merge-tree` (Git 2.38+) can predict conflicts **without** touching your working tree — great for
a "will this PR conflict?" CI check.

**Q9.** Protect branches on a self-hosted bare repo (no GitHub/GitLab).
```bash
# in the bare repo: .git/config or a pre-receive hook
git config receive.denyNonFastForwards true      # forbid all force pushes
git config receive.denyDeletes true              # forbid branch/tag deletion
git config receive.denyCurrentBranch refuse      # forbid pushing to the checked-out branch
```
```bash
#!/usr/bin/env bash
# hooks/pre-receive — protect main on the server
protected="refs/heads/main refs/heads/production"
while read -r old new ref; do
    for p in $protected; do
        [ "$ref" = "$p" ] || continue
        [ "$new" = "0000000000000000000000000000000000000000" ] && { echo "deleting $ref is forbidden"; exit 1; }
        git merge-base --is-ancestor "$old" "$new" || { echo "non-fast-forward push to $ref is forbidden"; exit 1; }
    done
done
```

**Q10.** What is a `refs/notes` and why would a branching strategy care?
```bash
git notes add -m "approved by security 2026-09-15" v1.4.0
git log --show-notes -1
git push origin refs/notes/*             # notes are NOT pushed by default
```
Notes attach metadata (review approval, deploy record, audit info) to a commit **without changing its
hash** — so you can annotate releases in a regulated environment without rewriting anything.

**Q11.** Explain `git switch` vs `git checkout` and why the split happened.
```bash
git switch main                  # change branch only
git restore file.txt             # fix files only
git checkout main                # did BOTH — ambiguous, and "checkout file" silently discards edits
git checkout -b new              # old create+switch; modern: git switch -c new
```
`checkout` was overloaded and destructive-by-accident (`git checkout file` throws away edits). Git 2.23
split it into two commands with obvious semantics.

**Q12.** Why do teams squash-merge, and what does it cost?
```bash
git merge --squash feature && git commit -m "feat: …"   # one clean commit on main
```
**Gains:** linear, readable history; each commit = one deployable change; easy `revert`; clean
`bisect`. **Costs:** loses per-commit granularity and authorship of intermediate commits;
`git branch -d` refuses (use `-D`); `git cherry`/`--merged` no longer detect the branch as merged;
and reverting a squashed mega-change is coarser. Mitigation: keep PRs small so the squash is small.
