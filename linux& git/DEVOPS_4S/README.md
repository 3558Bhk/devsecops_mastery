# DEVOPS_4S — DevOps Study Workspace

Pattern-based, beginner-friendly notes. Every folder teaches one subject the same way:
**pattern files** (recipes with a comment on every line) + **three question files**
(basic / advanced / scenario) with answers.

```text
DEVOPS_4S/
├── README.md                    ← you are here
├── linux-mastery/               ← 14 topics · 94 files · Linux from zero to scripting (+ RTIQ.md)
├── git/                         ← 9 topics · 55 files · Git from zero to history surgery (+ RTIQ.md)
└── git-branching-strategies/    ← 8 topics · 38 files · every branching model, with diagrams
```

---

## 📗 linux-mastery/ — 14 topics, 93 files

| # | Folder | Commands you master |
|---|--------|---------------------|
| 01 | navigation | `pwd` `cd` `ls` `tree` paths |
| 02 | listing-finding | `ls -lh` `find` `locate` `which` |
| 03 | file-operations | `mkdir` `cp` `mv` `rm` `ln` `touch` |
| 04 | viewing-files | `cat` `less` `head` `tail -f` `wc` |
| 05 | text-processing | `grep` `sed` `awk` `sort` `uniq` `cut` `tr` |
| 06 | pipes-redirects | `|` `>` `>>` `2>&1` `tee` `xargs` |
| 07 | processes | `ps` `top` `kill` `nohup` `&` `jobs` |
| 08 | users-permissions | `chmod` `chown` `sudo` `useradd` `id` |
| 09 | disk-storage | `df` `du` `lsblk` `mount` cleanup |
| 10 | system-info | `uname` `free` `uptime` `journalctl` `dmesg` |
| 11 | networking | `ip` `ss` `ping` `curl` `wget` `rsync` `ssh` |
| 12 | archives-compression | `tar` `zip` `gzip` `xz` backups |
| 13 | shell-scripting | variables, loops, `if`, functions, `getopts` |
| 14 | productivity | history, aliases, shortcuts, `apt`, `cron`, troubleshooting |

Plus `linux-mastery/CHEATSHEET.md` — one printable page with everything.

## 📘 git/ — 9 topics

| # | Folder | Commands you master |
|---|--------|---------------------|
| 01 | setup-config | `config`, levels, aliases, `.gitignore` |
| 02 | repo-basics | `init` `clone` `status` `add` `commit`, the 3 areas |
| 03 | history-diff | `log` `show` `diff` `blame` `grep` `-S` |
| 04 | branching-merging | `branch` `switch` `restore` `merge` `worktree` |
| 05 | undo-fix-mistakes | `restore` `reset` `revert` `--amend` `reflog` |
| 06 | remotes-collaboration | `remote` `fetch` `pull` `push` forks & PRs |
| 07 | stash-tags | `stash` `tag` releases |
| 08 | rebase-advanced | `rebase -i` `cherry-pick` `bisect` history rewrite |
| 09 | conflicts-troubleshooting | conflict resolution + every common error |

Plus `git/CHEATSHEET.md` — one printable page with everything.

---

## 📙 git-branching-strategies/ — 8 topics, 38 files

| # | Folder | What you master |
|---|---|---|
| 01 | fundamentals | what a branch IS, fast-forward vs 3-way merge, branch taxonomy, naming conventions |
| 02 | git-flow | `main` + `develop` + feature/release/hotfix, the `git flow` tool |
| 03 | github-flow | one `main`, short-lived PRs, deploy on merge, feature flags |
| 04 | gitlab-flow | environment / release / upstream-first variants, one-way promotion |
| 05 | trunk-based-development | daily integration, flags, small batches, merge queues, DORA |
| 06 | release-hotfix | release trains, semver, patch lines, `cherry-pick -x` backports, EOL |
| 07 | choosing-a-strategy | decision tree, comparison matrix, scoring your repo, migration playbooks |
| 08 | interview-scenarios | 16 worked scenarios, 8 mock drills, 60 rapid-fire answers |

Plus `DIAGRAMS.md` (every diagram, ASCII + Mermaid) and `CHEATSHEET.md` (one printable page).

**RTIQ.md** files — real-time interview questions for Senior DevOps / Linux Admin / SDE-3 roles —
live in `linux-mastery/RTIQ.md` (50 questions, 13 topics) and `git/RTIQ.md` (28 questions, 11 topics).
Each entry: question → what they're testing → senior answer with commands → follow-ups → senior signal.

---

## Structure of every topic folder

```text
04-branching-merging/
├── branch-basics.md          PATTERN  — the commands, one comment per line
├── switch-restore.md         PATTERN
├── merge-strategies.md       PATTERN
├── questions-basic.md        12–15 warm-up questions + answers
├── questions-advanced.md     10–15 harder questions + answers
└── questions-scenarios.md    8–10 real-world incidents to solve
```

**Totals across DEVOPS_4S:** 31 topics · 188 files · ~16,800 lines ·
~1,500 documented commands · ~1,000 questions and scenarios.

---

## Suggested path (10 weeks)

| Weeks | Focus | Goal |
|---|---|---|
| 1–2 | linux-mastery 01–06 | Move, find, read, filter, and pipe anything |
| 3 | linux-mastery 07–10 | Processes, permissions, disks, logs |
| 4 | linux-mastery 11–14 | Network, SSH, archives, scripting, cron |
| 5 | git 01–04 | Daily commits, branches and merges |
| 6 | git 05–07 | Undo anything, remotes, PRs, stashes, releases |
| 7 | git 08–09 | Rebase, cherry-pick, bisect, conflicts |
| 8 | Both cheatsheets + all scenario files | Mock-incident practice |
| 9 | git-branching-strategies 01–06 | Every model, its diagram, and its commands |
| 10 | git-branching-strategies 07–08 + RTIQ files | Pick a strategy, defend it, pass the mock |

## How to study each topic (repeatable loop)

1. Read the pattern files, **typing every command** into a real terminal.
2. Do the `## Practice` task at the end of each pattern file.
3. Solve `questions-basic.md` without looking, then check.
4. Solve `questions-advanced.md`.
5. Solve `questions-scenarios.md` — these are the interview questions.
6. Re-read the folder's cheatsheet section.

Wrong answer → re-read the pattern file → **retype** the command. Recognition is not recall.

## Practice environments

```bash
wsl --install -d Ubuntu               # Windows: a real Ubuntu inside Windows
brew install --cask orbstack          # macOS: lightweight Linux VM
mkdir ~/sandbox && cd ~/sandbox && git init   # a Git repo you can destroy freely
```
Git's remote topics (folder 06) need a free GitHub/GitLab account — create an **empty**
repository there and use it as `origin`. Never practise on a real work repo.

## Next topics to add here

- `docker/` — images, containers, volumes, networks, compose
- `ci-cd/` — GitHub Actions, pipelines, artefacts
- `kubernetes/` — pods, deployments, services, kubectl
- `terraform/` or `ansible/` — infrastructure as code
- `monitoring/` — Prometheus, Grafana, alerting
