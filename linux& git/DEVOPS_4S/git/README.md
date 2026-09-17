# Git Mastery — Pattern-Based Course for Complete Beginners

Same format as `../linux-mastery`: one topic per folder, **pattern files** (reusable recipes)
plus **three question files** per topic — basic, advanced and scenario-based — every line
commented so you understand *why*, not just *what*.

```text
04-branching-merging/
├── branch-basics.md          ← PATTERN: create, list, delete branches
├── switch-restore.md         ← PATTERN: move between branches and files
├── merge-strategies.md       ← PATTERN: fast-forward, 3-way, squash
├── questions-basic.md        ← warm-up questions + answers
├── questions-advanced.md     ← harder questions + answers
└── questions-scenarios.md    ← real-world incidents to solve
```

---

## The one mental model that explains all of Git

Git is a **snapshot machine** with three working areas. Every command moves data between them.

```text
   WORKING DIRECTORY  ──git add──►  STAGING AREA  ──git commit──►  REPOSITORY (.git)
   the files you edit               what will go in               permanent snapshots
        ▲                            the next commit                with history
        │                                                                │
        └────────────── git checkout / restore / reset ◄─────────────────┘
                                (ways to move data BACK)
```

- `git status` always tells you which area each file is in. **Run it constantly.**
- A **commit** is a snapshot of the whole project plus a pointer to its parent commit(s).
- A **branch** is just a sticky note pointing at one commit. That's why branching is instant.
- `HEAD` is the sticky note pointing at the branch (or commit) you are currently on.

---

## Learning order

| # | Folder | What you master | Key commands |
|---|--------|-----------------|--------------|
| 1 | `01-setup-config` | Identity, config levels, `.gitignore` | `git config` |
| 2 | `02-repo-basics` | The daily loop | `init` `clone` `status` `add` `commit` |
| 3 | `03-history-diff` | Inspecting what changed and who did it | `log` `diff` `show` `blame` |
| 4 | `04-branching-merging` | Parallel work without breaking anything | `branch` `switch` `merge` |
| 5 | `05-undo-fix-mistakes` | Getting out of trouble | `restore` `reset` `revert` `commit --amend` |
| 6 | `06-remotes-collaboration` | GitHub/GitLab, push, pull, PRs | `remote` `push` `pull` `fetch` |
| 7 | `07-stash-tags` | Saving work-in-progress and marking releases | `stash` `tag` |
| 8 | `08-rebase-advanced` | Clean history and archaeology | `rebase` `cherry-pick` `bisect` |
| 9 | `09-conflicts-troubleshooting` | Conflicts and the errors everyone meets | merge conflict markers, `reflog` |

---

## Setup for practice (2 minutes)

```bash
mkdir ~/git-practice && cd ~/git-practice   # a sandbox repo — break it freely
git init                                    # turn this folder into a repository
git config user.name "Your Name"            # local identity for this repo
git config user.email "you@example.com"     # local identity email
echo "# practice" > README.md               # create a first file
git add README.md                           # stage it
git commit -m "first commit"                # snapshot it
git log --oneline                           # verify the commit exists
```

Test the remote parts (folder 06) by creating a free **empty** repository on GitHub/GitLab
and adding it as `origin` — never practise on a real work repo.

---

## Golden rules

```bash
git status                                  # run it before AND after every command while learning
git log --oneline --graph --all             # see the whole shape of history
git reflog                                  # the undo history of HEAD — almost nothing is truly lost
```

- **Commit early, commit often.** Small commits are easy to revert; huge ones are not.
- **Never rewrite history that you already pushed** to a shared branch (`rebase`, `commit --amend`,
  `reset --hard` on pushed commits force everyone else into pain).
- `git reset --hard` and `git clean -fd` destroy uncommitted work **permanently**. Run
  `git stash` first if you are unsure — a stash is recoverable.
- Read the whole error message. Git's errors are unusually good and usually say exactly what to do.
- `git <command> --help` opens the manual; `git help <command>` does too.
