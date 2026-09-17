# RTIQ — Real-Time Interview Questions (Git)

**Target roles:** Senior DevOps Engineer · Senior Systems Administrator · SDE-3 · SRE · Platform Engineer
**Format:** topic-wise, matching the folders in this course. Each entry gives the question,
*what the interviewer is really testing*, a senior-level answer with real commands, the follow-ups
they will ask, and the signal that separates senior from mid-level.

> Git questions at senior level are rarely "what does `git pull` do". They are about **the object
> model**, **safe collaboration at scale**, **incident recovery**, and **the process you impose on a
> team**. Structure every answer: model → command → trade-off → what I'd automate.

---

## Topic 1 — The object model & internals (the senior filter)

### Q1. Explain Git's data model. What is actually stored in `.git`?

**Testing:** whether you understand Git or just memorised commands. This single answer sets the tone
for the rest of the interview.

**Answer:** Git is a **content-addressable key-value store**. Everything is an object identified by
its SHA-1 (or SHA-256) hash of its contents. Four object types:

| Object | Contains | Created by |
|---|---|---|
| **blob** | file *content* only — no name, no mode | `git hash-object -w` |
| **tree** | a directory listing: mode, type, hash, name | every commit |
| **commit** | one tree hash + parent hash(es) + author/committer + message | `git commit` |
| **tag** | an annotated tag: target hash + tagger + message (optional signature) | `git tag -a` |

Commits point to parents, forming a **DAG** (directed acyclic graph). A **branch** is a 41-byte file
containing one commit hash (`refs/heads/main`); a **tag** is `refs/tags/v1`; **HEAD** is a symbolic
ref pointing at a branch. The **index/staging area** is a binary file (`.git/index`) holding a sorted
list of path → blob hash + mode + stat data, which is why `git status` is fast.

```bash
git cat-file -p HEAD                     # a commit: tree, parent, author, committer, message
git cat-file -p HEAD^{tree}              # that commit's tree: mode/type/hash/name per entry
git cat-file -p <blob-hash>              # the raw file content
git cat-file -t <hash>                   # object type
git ls-tree -r HEAD --long               # recursive listing with sizes
git hash-object -w somefile              # store an object and print its hash
git rev-parse HEAD HEAD^{tree} main@{u}  # resolve any ref/revision to a hash
cat .git/HEAD; cat .git/refs/heads/main; cat .git/packed-refs
git verify-pack -v .git/objects/pack/*.idx | head   # what's inside a packfile
```

**Key consequences to state out loud:**
- Identical content in 100 files = **one blob** (deduplication is free).
- A commit is a **snapshot**, not a diff. Diffs are computed on demand.
- Renames are **not stored** — `git log --follow` and `diff -M` *detect* them by content similarity.
- Changing anything changes its hash → hence "rebase rewrites history" and force-push is required.
- Integrity is built in: any corruption changes the hash and fails verification.

**Follow-ups:** Why is SHA-1 still OK? → Git's threat model treats collisions as an availability issue;
`sha1CollisionDetection` is compiled in, and SHA-256 repos are supported (`git init --object-format=sha256`).
What's the difference between author and committer? → author wrote it, committer applied it; rebase,
cherry-pick and `--amend` change the committer, keeping the author.

---

### Q2. What is a packfile, and why does `git gc` matter on a big repo?

```bash
git count-objects -vH                    # loose objects vs packed, and total size
ls .git/objects/pack/                    # .pack + .idx pairs
git verify-pack -v .git/objects/pack/*.idx | sort -k3 -n | tail -10   # the biggest objects
git cat-file --batch-all-objects --batch-check | sort -k3 -n | tail   # every object by size
git gc                                   # repack, prune unreachable objects, write commit-graph
git gc --aggressive --prune=now          # heavier delta compression (slow; do it offline)
git repack -a -d -f --depth=250 --window=250    # manual aggressive repack
git maintenance start                    # scheduled background maintenance (gc, commit-graph, prefetch)
git multi-pack-index write               # speed up lookups when there are many packfiles
git prune --expire=now                   # remove unreachable loose objects
git reflog expire --expire=now --all && git gc --prune=now   # the "actually reclaim space" combo
```

**Answer:** Loose objects are zlib-compressed individual files — fine for a few, terrible at scale.
`git gc` packs them into **packfiles** with **delta compression** (storing differences between similar
objects), writes an index (`.idx`) for O(log n) lookup, prunes unreachable objects past the expiry
window, and writes a **commit-graph** file that makes `git log`/`merge-base` orders of magnitude faster
on large histories.

**Senior signal:** you mention `gc.auto`, `fetch.writeCommitGraph`, `core.untrackedCache`,
`core.fsmonitor` (huge on monorepos), `feature.manyFiles=true`, and that after a `filter-repo` rewrite
the space isn't reclaimed until reflogs expire and GC runs — and that hosts like GitHub run their own
GC afterwards.

---

### Q3. What is a refspec? Explain what `git fetch` actually does.

```bash
git config --get-all remote.origin.fetch      # +refs/heads/*:refs/remotes/origin/*
git fetch origin                              # apply that refspec: update local remote-tracking refs
git fetch origin main:refs/heads/upstream-main   # fetch a branch into an arbitrary local ref
git fetch origin 'refs/pull/*/head:refs/remotes/origin/pr/*'   # GitHub PR refs (magic refs)
git push origin refs/heads/main:refs/heads/release   # push local main to remote release
git push origin :refs/heads/old-branch        # empty src = DELETE the remote ref
git ls-remote origin                          # the remote's refs, no download
git show-ref | head                           # all local refs
git for-each-ref --format='%(refname:short) %(objectname:short) %(upstream:short)' refs/heads
```

**Answer:** A refspec is `+src:dst` — "take refs matching `src` on the remote and write them to `dst`
locally"; the leading `+` permits non-fast-forward updates. `fetch` never touches your working tree or
your own branches: it downloads objects and updates **remote-tracking refs** (`refs/remotes/origin/*`),
which are local *caches* of the remote's state. That is why `git fetch` is always safe and
`git pull` (= fetch + merge/rebase) is not.

**Follow-ups:** What is `refs/notes/*`? → metadata attached to commits without rewriting them:
```bash
git notes add -m "deployed to prod 2026-09-15" HEAD
git log --show-notes --oneline -3
git push origin refs/notes/*                 # notes are NOT pushed by default
```
Great for audit trails (review approval, deploy records) because it doesn't change commit hashes.
What is `git replace`? → locally substitute one object for another (history surgery experiments
without rewriting); `git replace -l`, and it's not transferred by default.

---

## Topic 2 — Branching strategies & workflow at scale

### Q4. Compare GitFlow, GitHub Flow, trunk-based development, and release trains. Which do you pick and why?

| Model | Branches | Release cadence | Best for | Main cost |
|---|---|---|---|---|
| **GitFlow** | `main`, `develop`, `feature/*`, `release/*`, `hotfix/*` | periodic, versioned | shrink-wrapped/versioned software, mobile apps with store review | long-lived `develop`, painful merges, history noise, hard CI |
| **GitHub Flow** | `main` + short-lived feature branches + PRs | continuous deploy from main | SaaS/web with good test coverage | requires strong CI and feature flags |
| **Trunk-based** | `main` only (+ optional short release branches) | many deploys/day | high-performing DevOps teams | demands small PRs, flags, fast tests, discipline |
| **Release train / GitLab flow** | `main` + `release/X.Y` + environment branches | scheduled | regulated, multi-environment promotion | promotion complexity |

**My answer in an interview:** "Trunk-based with short-lived branches and feature flags, for anything
deployed continuously. GitFlow's `develop` branch is a merge-conflict factory and delays feedback;
I'd only use it for versioned artefacts with external release cycles — and even then I'd use
`release/*` branches cut from main rather than a permanent `develop`."

**Evidence to cite:** DORA/Accelerate research — short-lived branches, small batches and continuous
integration correlate with elite delivery performance (higher deploy frequency, lower lead time and
change-failure rate, faster MTTR).

**Follow-ups:** How do you ship unfinished work to trunk? → **feature flags** (LaunchDarkly, Unleash,
config-driven), dark launches, branch-by-abstraction. How long is "short-lived"? → under 1–2 days;
if longer, split the change or flag it. What about long-running rewrites? → strangler-fig pattern,
parallel implementations behind an interface, not a 6-month branch.

---

### Q5. Your team has 40 engineers on one repo and merges to main conflict constantly. Fix it.

**Answer as a system, not a command:**
1. **Measure first:** conflict rate, PR size (files/lines), time-to-merge, hot files
   (`git log --since="3 months" --name-only --pretty=format: | sort | uniq -c | sort -rn | head -20`).
   Conflicts concentrate in a few files — usually generated code, lockfiles, changelogs, big switch
   statements, and shared config.
2. **Integrate more often:** small PRs (<400 lines), branch lifetime <2 days, `pull.rebase=true`,
   auto-rebase buttons, required "branch must be up to date" only if it doesn't create a stampede.
3. **Remove conflict sources mechanically:**
   - lockfiles → custom merge driver that regenerates them
     ```bash
     printf 'package-lock.json merge=npm\n' >> .gitattributes
     git config merge.npm.driver "npm install --package-lock-only"
     ```
   - changelogs → generate from Conventional Commits at release time; never edit by hand
   - `union` merge for append-only files (`CHANGELOG.md merge=union`)
   - code ownership/structure → split hot modules, use plugin registries instead of giant switch files
4. **Enable `rerere`** for long-lived branches: `git config --global rerere.enabled true`.
5. **Automate:** merge queues (GitHub merge queue, GitLab merge trains, Bors) serialise integrations
   and test the *result* of combining several PRs — this eliminates the "both PRs were green, the
   merge is red" problem.
6. **Culture:** reviewers approve fast, authors rebase themselves, and nobody force-pushes main.

**Senior signal:** you identify **merge queues** and **hot-file analysis** — most candidates jump
straight to "rebase more often".

---

### Q6. Monorepo vs polyrepo — and what does Git need to survive a monorepo?

**Answer:** Monorepo: atomic cross-service changes, shared tooling, one version of truth, easier
refactors — but requires serious Git performance work, code ownership (CODEOWNERS), fine-grained CI
(only test what changed), and access control at the path level. Polyrepo: independent scaling, clear
ownership, simpler CI — but cross-cutting changes need N coordinated PRs and version skew.

**Git performance toolkit for big repos:**
```bash
git clone --filter=blob:none <url>          # PARTIAL clone: commits+trees now, blobs on demand
git clone --filter=tree:0 <url>             # even leaner: blobs AND trees on demand
git sparse-checkout init --cone             # cone mode = fast directory-based matching
git sparse-checkout set services/payments libs/common    # materialise only what you need
git sparse-checkout add services/billing    # add later
git config core.fsmonitor true              # filesystem monitor: massive status speedup
git config core.untrackedCache true         # cache untracked-file scans
git config feature.manyFiles true           # bundle of monorepo-friendly defaults
git config index.version 4                  # smaller, faster index
git config gc.writeCommitGraph true
git maintenance start                       # background gc/commit-graph/prefetch
git log --oneline -1 -- services/payments   # scoped queries
```
**CI side:** affected-only builds (`nx affected`, `bazel query`, `turborepo`, or
`git diff --name-only origin/main...HEAD` feeding a path filter), remote caching, and shallow-ish
fetches (`--filter=blob:none --depth=50`) with `git fetch --deepen` when history is needed.

**Follow-ups:** When does partial clone hurt? → operations that need all blobs (full `git log -p`,
blame across history) trigger on-demand fetches and can be slow offline. What about submodules? →
pinned SHA dependencies, poor ergonomics (`--recurse-submodules` everywhere, detached HEAD), prefer
package managers or a monorepo. Subtrees? → `git subtree` vendoring without the ergonomics cost.

---

## Topic 3 — Merge vs rebase (guaranteed question)

### Q7. Merge vs rebase — when is each correct, and what is the golden rule?

**Golden rule:** *never rewrite history that others have already pulled.* Rebase your own unpushed
commits freely; merge (or fast-forward) shared branches.

```bash
git rebase origin/main            # replay my commits onto the new base: linear history
git merge origin/main             # create a merge commit: preserves true chronology
git merge --no-ff feature         # force a merge commit so the feature is visible as a unit
git merge --squash feature        # collapse a branch into staged changes, then one commit
git rebase -i origin/main         # clean up my own commits before the PR
git push --force-with-lease       # publish a rebased branch SAFELY
```

| | `merge` | `rebase` |
|---|---|---|
| History | true DAG, merge commits | linear, rewritten hashes |
| Traceability | shows when work integrated | hides it; bisect/blame cleaner |
| Conflicts | resolved once | possibly resolved per commit (use `rerere`) |
| Safety on shared branches | ✅ | ❌ |
| Undo | `git revert -m 1` | `git reflog` + reset |
| Best for | integrating into main, audit trails | updating a private feature branch, tidying a PR |

**Senior signal:** you mention
- `git config --global rerere.enabled true` — records conflict resolutions and replays them, which
  removes the biggest practical objection to rebasing long-lived branches;
- **the rebase conflict sides are swapped**: `<<<<<<< HEAD` is the *new base*, and the incoming side
  is *your* commit. Getting this wrong silently inverts your fix;
- `--force-with-lease` (and the trap that running `git fetch` immediately before it defeats the
  protection, since the lease is based on your remote-tracking ref);
- squashing at merge time via the platform ("Squash and merge") as a team-level policy that removes
  the need for contributors to rebase at all.

---

### Q8. "Rebase or merge" — but the branch is already pushed and two people are working on it. What now?

**Answer:** You don't rebase a shared branch. Options:
1. Merge main into the shared feature branch (`git merge origin/main`) — safe, adds a merge commit.
2. If the team insists on linearity, coordinate: agree a time, everyone pushes, one person rebases
   and force-pushes with `--force-with-lease`, everyone else runs
   `git fetch && git reset --hard origin/feature` (or `git rebase --onto`).
3. Best structural fix: **short-lived branches** so this situation doesn't arise.
```bash
git log --oneline origin/feature..feature    # who has unpushed work?
git branch --contains <hash>                 # which branches already contain the commits
```

---

## Topic 4 — Undo, recovery & incident response

### Q9. A junior ran `git reset --hard origin/main` and lost a day of work. Recover it.

```bash
git reflog                                  # every HEAD movement with hashes and timestamps
git reflog --date=iso | head -20
git reset --hard HEAD@{3}                   # jump back to the pre-reset state
git switch -c rescue HEAD@{3}               # safer: rescue onto a new branch
git fsck --lost-found                       # dangling commits if reflog entries expired
git fsck --unreachable | grep commit        # also catches dropped stashes
git stash apply <hash>                      # re-apply a recovered stash
```
**Answer:** Committed work is essentially always recoverable — `reset` moves a ref, it doesn't delete
objects; they stay reachable via reflog (default 90 days for reachable, 30 for unreachable, then
`gc.pruneExpire`). **Uncommitted** work is gone: `reset --hard` and `clean -fd` have no undo.

**Prevention (this is what a senior says):**
```bash
git config --global alias.safe-reset '!git stash push -u -m "pre-reset" && git reset --hard'
git config --global gc.reflogExpire 180.days      # keep the safety net longer
git config --global gc.reflogExpireUnreachable 90.days
```
Plus habits: commit often (WIP commits are free — squash later), `git stash` before destructive ops,
`git branch backup-$(date +%s)` before any history rewrite, and CI that pushes every branch so
nothing exists only on a laptop.

---

### Q10. `git revert` vs `git reset` in production. Which do you use and why?

**Answer:** On a **shared/pushed** branch: `revert` — it adds a new commit, so nobody's clone diverges
and the audit trail is preserved. On a **local unpushed** branch: `reset` is fine and cleaner.

```bash
git revert <hash>                       # undo one commit
git revert -m 1 <merge-hash>            # undo a merge (keep parent 1 = the branch merged INTO)
git revert --no-commit A^..B && git commit -m "revert range"   # undo a range as one commit
git reset --hard origin/main            # local-only branch: discard and match remote
```
**The revert-a-merge trap (a favourite senior follow-up):** after `git revert -m 1 <merge>`, Git
considers that branch *already merged*, so re-merging it later does nothing. To bring the work back
you must revert the revert (`git revert <revert-hash>`) or rebase the feature branch to new hashes.
Explain this and you've clearly done it in anger.

---

### Q11. Someone force-pushed main and destroyed three people's commits. Incident response?

```bash
# 1. Stop the bleeding
#    On GitHub/GitLab: enable branch protection NOW (no force push, no deletion)
# 2. Find the lost commits — anyone who fetched them has a copy
git reflog show origin/main | head      # the remote-tracking ref's own reflog
git log --oneline --all --not main | head -30    # commits reachable from nowhere else
git fsck --lost-found                   # dangling commits
# 3. Recreate a recovery branch from a known-good hash
git branch recovery-main <good-hash>
git log --oneline recovery-main -10     # verify it contains the lost work
# 4. Restore: either reset main to it (coordinated force push) or cherry-pick the missing commits
git switch main && git merge --ff-only recovery-main
git cherry-pick <hash1> <hash2>         # or pick back individual commits
git push origin main
# 5. Tell everyone to run: git fetch && git reset --hard origin/main  (after they've saved local work)
```
**Postmortem actions:** protected branches, required reviews, `--force-with-lease` in team guidelines
(and `receive.denyNonFastForwards=true` on self-hosted servers), CI checks, and a documented
"how to recover from a bad force push" runbook. Blameless — the mechanism allowed it, so the
mechanism is the bug.

---

## Topic 5 — Remotes, PRs & collaboration mechanics

### Q12. `git fetch` vs `git pull` vs `git pull --rebase` — and what do you standardise on?

```bash
git fetch --prune                 # download + prune dead remote branches; touches nothing local
git pull                          # fetch + merge → merge commits on every sync ("railway map" history)
git pull --rebase                 # fetch + rebase → linear history
git pull --ff-only                # fetch, and FAIL unless it fast-forwards → most conservative
```
**My standard:** `git config --global pull.rebase true` + `rebase.autoStash true` for developers;
`pull.ff only` on protected branches/CI so an unexpected divergence fails loudly instead of silently
creating a merge commit. And: always `fetch` + inspect before integrating when something looks off.

**Follow-ups:** What does `git pull origin feature` do to my current branch? → merges the *remote*
branch into whatever you have checked out — a classic self-inflicted mess. What's `--autostash`?
Why is `git push --force` on main a fireable offence? (See Q11.)

---

### Q13. Design a PR/review process that keeps quality high and cycle time under a day.

**Answer — the mechanics plus the guardrails:**
- **Small PRs:** <400 lines of diff, one logical change. Enforce culturally; measure
  (`git diff --shortstat origin/main...HEAD`).
- **Branch naming:** `<type>/<ticket>-<slug>` → `feat/PROJ-1234-coupon-codes`; makes automation trivial.
- **Conventional Commits** (`feat:`, `fix:`, `chore:`) → automated changelogs and semver via
  semantic-release.
- **PR template** with: what/why, how tested, screenshots, migration steps, feature flag name,
  rollback plan.
- **CI gates:** lint, shellcheck, unit, integration, security scan (SAST/secret scan/dependency
  audit), coverage delta, build, preview environment. Required checks, no self-merge.
- **CODEOWNERS** for automatic reviewer assignment on sensitive paths.
- **Merge queue** to serialise integration and test the merged result.
- **Merge policy:** squash for feature branches (clean main), rebase for stacked/atomic commits,
  merge-commit only when the branch history has review value.
- **Post-merge:** delete the branch automatically; deploy via progressive delivery; watch error budget.

```bash
# what I'd automate in CI:
git fetch origin main
git diff --stat origin/main...HEAD              # PR size gate
git log --oneline origin/main..HEAD             # commit message lint (commitlint)
git diff --check origin/main...HEAD             # whitespace and leftover conflict markers
grep -rn "<<<<<<<\|>>>>>>>" --include='*' . || true   # conflict-marker guard
```
**Senior signal:** you optimise for **review latency** (a blocked PR costs more than a slightly
imperfect one), you mention WIP/draft PRs for early feedback, and you say the process is only as good
as the team's willingness to review — so you track and publish PR cycle time.

---

### Q14. How do you give CI access to a repo? Compare the options.

| Method | Security | Notes |
|---|---|---|
| **Deploy key** (read-only SSH key per repo) | good | one key per repo, no write unless enabled; rotate |
| **Machine user / bot account + PAT** | medium | broad blast radius, PAT expiry management |
| **GitHub App / GitLab Deploy Token** | best | fine-grained permissions, short-lived installation tokens, auditable |
| **OIDC federation** (GitHub Actions → AWS/GCP via OIDC) | best | no long-lived cloud credentials at all |
| Personal SSH key of an employee | ❌ | never — attribution and offboarding nightmare |

```bash
# short-lived token pattern in CI (GitHub App example)
TOKEN=$(curl -s -X POST -H "Authorization: Bearer $APP_JWT" \
  https://api.github.com/app/installations/$ID/access_tokens | jq -r .token)
git -c http.extraHeader="Authorization: Bearer $TOKEN" clone https://github.com/org/repo
# depth/filter for speed:
git clone --depth 1 --filter=blob:none --sparse <url>
git config --global --get-regexp 'url\..*\.insteadof'   # rewrite https↔ssh consistently
```
**Follow-ups:** Why avoid `git config --global url."https://x".insteadOf` with embedded tokens? →
the token lands in the global config and leaks into logs/child processes. How do you prevent secret
leakage from CI logs? → masking, OIDC, Vault dynamic credentials, no `set -x` around auth commands.

---

## Topic 6 — Large files, LFS & repository performance

### Q15. Someone committed a 2 GB model file / video / database dump. What now, and what's the long-term fix?

```bash
# 1. Find the damage
git count-objects -vH
git rev-list --objects --all | git cat-file --batch-check='%(objecttype) %(objectname) %(objectsize) %(rest)' \
  | awk '$1=="blob" && $3 > 10485760 {print $3, $4}' | sort -rn | head -20    # blobs > 10 MB with paths
git log --all --oneline --diff-filter=A -- "*.mp4" "*.bin" "*.zip"             # who added archives
# 2. Remove from history (coordinate — everyone must re-clone)
pip install git-filter-repo
git clone --mirror <url> repo.git && cd repo.git
git filter-repo --strip-blobs-bigger-than 50M
git filter-repo --path models/big.bin --invert-paths
git push --force --mirror
# 3. Reclaim space locally
git reflog expire --expire=now --all && git gc --prune=now --aggressive
```
**Long-term fix:**
```bash
git lfs install
git lfs track "*.psd" "*.bin" "*.onnx"        # writes patterns into .gitattributes
git add .gitattributes && git commit -m "track large assets with LFS"
git lfs migrate import --include="*.mp4" --everything   # move EXISTING history into LFS
git lfs ls-files; git lfs status; git lfs prune
```
**The real answer:** binaries don't belong in Git at all. Use an artefact store (S3/Artifactory/Nexus/
OCI registry), Git LFS only where the file must be versioned *with* the code (design assets, test
fixtures), and enforce it with a pre-receive hook or CI size check:
```bash
git diff --cached --name-only -z | xargs -0 -r du -h | sort -rh | head   # pre-commit size gate
```
**LFS trade-offs to mention:** extra server/storage cost, `lfs pull` latency in CI, pointer files break
naive tooling, GitHub LFS bandwidth quotas cause hard failures, and LFS objects aren't deduplicated
across versions of a large binary.

---

### Q16. `git status` takes 20 seconds in a monorepo. Optimise it.

```bash
git config core.fsmonitor true               # filesystem daemon: avoids rescanning the worktree
git config core.untrackedCache true          # cache untracked-file scans (uses mtime of dirs)
git config feature.manyFiles true            # index v4, commitGraph, fsmonitor, maintenance
git config index.version 4                   # more compact index
git config core.preloadIndex true            # parallel lstat of index entries
git config gc.writeCommitGraph true
git maintenance start                        # background gc / commit-graph / prefetch
git commit-graph write --reachable           # speeds up log/merge-base dramatically
git sparse-checkout init --cone && git sparse-checkout set services/mine   # materialise less
git update-index --really-refresh; git status
GIT_TRACE_PERFORMANCE=1 git status           # measure where the time actually goes
git update-index --assume-unchanged path     # last resort for locally-modified generated files
git update-index --skip-worktree path        # better: keeps local config edits out of status
```
**Explain the mechanism:** `status` lstats every file in the worktree and compares against the index;
`fsmonitor` (Watchman or the built-in daemon) makes it event-driven instead of scan-driven.
The commit-graph avoids parsing every commit object for history queries. Sparse checkout reduces the
number of files that exist at all.

**Follow-ups:** `--assume-unchanged` vs `--skip-worktree` → the former is a performance hint Git may
ignore (and it silently drops your changes on some operations); the latter is the intended way to keep
local modifications to tracked files out of `status`/`pull`. Neither is a substitute for `.gitignore`.

---

## Topic 7 — Security: secrets, signing, supply chain

### Q17. An API key was committed and pushed 3 weeks ago. Full incident response.

```bash
# 1. ROTATE THE CREDENTIAL IMMEDIATELY — before any Git work. Assume it's compromised.
# 2. Find every occurrence across all refs
git log --all --oneline -S"AKIA1234567890ABCDEF"
git log --all --oneline -G"AKIA[0-9A-Z]{16}"
# 3. Purge it
printf 'AKIA1234567890ABCDEF==>REDACTED-AWS-KEY\n' > expressions.txt
printf 'regex:(?i)(api[_-]?key|secret|password)\\s*[:=]\\s*\\S+==>\\1=REDACTED\n' >> expressions.txt
pip install git-filter-repo
git clone --mirror <url> repo.git && cd repo.git
git filter-repo --replace-text expressions.txt
git push --force --mirror
# 4. Force everyone to re-clone (a pull will resurrect the old objects)
# 5. Ask the host to GC (GitHub/GitLab support request for cached views/forks)
# 6. Audit: was the key actually used? (CloudTrail / provider audit logs)
```
**Prevention (the part that gets you hired):**
```bash
# pre-commit framework with a secret scanner — runs locally AND in CI
pip install pre-commit gitleaks
cat > .pre-commit-config.yaml <<'YAML'
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.18.4
    hooks: [{id: gitleaks}]
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.6.0
    hooks: [{id: check-added-large-files, args: ['--maxkb=1024']}, {id: detect-private-key}]
YAML
pre-commit install            # installs .git/hooks/pre-commit
pre-commit run --all-files
```
Plus: push protection on the host (GitHub secret scanning push protection), `.gitignore` for `.env`,
secrets in a vault (Vault/AWS SM/SSM/GCP SM) with dynamic short-lived credentials, CI never
`echo`ing secrets, and a `.env.example` with dummy values committed instead.

**Senior judgement:** "Purging history is *cleanup*, not remediation. The credential is burned the
moment it's pushed — bots scrape public repos within minutes. Rotation and audit come first, always."

---

### Q18. How do you guarantee a commit actually came from your CI and not an attacker?

```bash
# commit/tag signing — GPG or (modern, easier) SSH keys
git config --global gpg.format ssh
git config --global user.signingkey ~/.ssh/id_ed25519
git commit -S -m "feat: signed commit"
git tag -s v1.2.0 -m "release 1.2.0"
git log --show-signature -1
git verify-commit HEAD; git verify-tag v1.2.0
# enforce it
git config --global commit.gpgsign true
git config --global tag.gpgSign true
```
**Full supply-chain answer:** signed commits + signed tags · protected branches requiring signed
commits · GitHub Actions **OIDC** to cloud providers (no stored cloud keys) · artefact provenance
via **SLSA**/in-toto attestations and **Sigstore/cosign** signing of images · SBOM generation
(SPDX/CycloneDX) · dependency pinning by hash (`package-lock.json`, `go.sum`, Renovate with
immutable digests) · reproducible builds · and a policy engine/admission controller that refuses
unsigned images (Kyverno/cosign policy-controller).

---

## Topic 8 — Hooks, automation & CI/CD integration

### Q19. Which Git hooks would you use, and what are their limits?

| Hook | Runs | Typical use | Can block? |
|---|---|---|---|
| `pre-commit` | before the commit is created | lint, format, secret scan, size check | ✅ |
| `prepare-commit-msg` / `commit-msg` | message editing | ticket-ID enforcement, commitlint | ✅ |
| `pre-push` | before push | tests, block pushes to main, large-file check | ✅ |
| `post-merge` / `post-checkout` | after | `npm install`, invalidate caches | ❌ |
| `pre-receive` / `update` / `post-receive` | **server side** | policy enforcement, CI trigger, mirrors | ✅ |
| `post-receive` (server) | after ref update | webhook fan-out, deploy triggers | ❌ |

```bash
ls .git/hooks/                                # *.sample files ship with every repo
git config core.hooksPath .githooks           # version-control your hooks so the team gets them
chmod +x .githooks/pre-commit                 # hooks must be executable
```
```bash
#!/usr/bin/env bash
# .githooks/pre-commit — fail on secrets, conflict markers, and huge files
set -Eeuo pipefail
files=$(git diff --cached --name-only --diff-filter=ACM)
grep -nE '^(<<<<<<<|>>>>>>>)' $files && { echo "conflict markers staged"; exit 1; }
git diff --cached --name-only -z | xargs -0 -r du -k | awk '$1>2048{print "too large:",$2; f=1} END{exit f}'
command -v gitleaks >/dev/null && gitleaks protect --staged --no-banner
```
**Limits to state clearly:** client-side hooks are **local, not installed by `git clone`, and bypassable**
with `--no-verify`. Therefore: enforcement must live server-side (protected branches, required status
checks, pre-receive hooks) or in CI. Hooks are for *fast feedback*, not for *policy*.

**Follow-ups:** How do you distribute hooks? → `core.hooksPath` + a repo-managed `.githooks/` dir, or
`pre-commit`/`husky`/`lefthook` frameworks. Why is `pre-commit` (the framework) popular? → language-
agnostic, pinned hook versions, runs only on changed files, caches, and works in CI with
`pre-commit run --all-files`.

---

### Q20. Write CI logic that only builds what changed.

```bash
# what did this PR touch?
git fetch origin main --depth=50
BASE=$(git merge-base origin/main HEAD)               # the true comparison point
git diff --name-only "$BASE"...HEAD > changed.txt
git diff --name-only "$BASE" HEAD                     # two-dot equivalent
# scope decisions
grep -q '^services/payments/' changed.txt && echo "build payments"
grep -qE '^(package-lock.json|package.json)' changed.txt && echo "reinstall deps"
git diff --quiet "$BASE" HEAD -- docs/ || echo "docs changed"
# per-service detection loop
for svc in $(ls services); do
  git diff --name-only "$BASE"...HEAD | grep -q "^services/$svc/" && echo "affected: $svc"
done
```
**Gotchas to mention:** shallow clones break `merge-base` (fetch enough depth or use
`--filter=blob:none`); detached HEAD in CI needs explicit refspecs; `HEAD^` doesn't exist on a
single-commit repo; use three-dot diff for PR semantics; and prefer the platform's native
"path filters"/`changes:` rules or a real build graph (Bazel/Nx/Turborepo) over hand-rolled greps for
anything complex.

---

## Topic 9 — Release engineering

### Q21. Design the release process: versioning, tags, changelogs.

```bash
# Conventional Commits → automatic semver + changelog
git log --oneline v1.4.0..HEAD --no-merges --pretty='%s' | grep -E '^(feat|fix|BREAKING CHANGE)'
npx semantic-release --dry-run         # or: standard-version / release-please / changesets
git tag -a v1.5.0 -m "release 1.5.0" && git push origin v1.5.0
git describe --tags --always --dirty   # v1.5.0 / v1.5.0-12-gabc1234 / ...-dirty
VERSION=$(git describe --tags --abbrev=0)
```
**Answer:** semver (MAJOR.MINOR.PATCH) derived from commit types — `BREAKING CHANGE`/`!` → major,
`feat` → minor, `fix` → patch. Tag on main **after** merge, from CI, with an annotated (or signed) tag;
never tag manually on a laptop. Generate the changelog from commit messages between tags
(`git log v1.4.0..v1.5.0`). Publish a GitHub/GitLab Release with artefacts, SBOM and checksums.
For services, "version" = Git SHA + image digest; tags matter more for libraries and on-prem products.

**Follow-ups:** Hotfix on an old release line? → branch from the tag, fix, tag `v1.4.1`, cherry-pick
forward to main. How do you support N versions? → release branches with a documented support matrix,
security backports only. What is `-dirty` for? → build hygiene: refuse to ship a dirty tree; CI should
fail if `git describe --dirty` reports dirty.

---

## Topic 10 — Rapid-fire scenarios

### Q22. "Your local branch and the remote have diverged." What are your options and how do you choose?

```bash
git fetch origin
git status -sb                          # ## main...origin/main [ahead 2, behind 3]
git rev-list --left-right --count origin/main...main    # exact numbers
git log --oneline --graph --all -15     # SEE the divergence before acting
# option A: linear (my commits are local-only and it's my branch)
git pull --rebase
# option B: preserve (shared branch)
git pull --no-rebase
# option C: theirs wins (they force-pushed, my local commits are junk)
git reset --hard origin/main            # after saving anything you need: git branch rescue
# option D: mine wins (I am the only author and I rebased deliberately)
git push --force-with-lease
```

### Q23. You committed to the wrong branch. Six variants they may ask:

```bash
# a) not pushed, want the commits on a new branch
git switch -c correct-branch && git switch - && git reset --hard origin/main
# b) one commit too many on main, not pushed
git reset --soft HEAD~1                 # keep the changes staged, then commit on the right branch
# c) already pushed to main (protected)
git revert <hash> && git push           # then open a proper PR from a new branch
# d) committed a file that shouldn't exist
git rm --cached secret.env && echo "secret.env" >> .gitignore && git commit --amend --no-edit
# e) committed with the wrong author/email
git commit --amend --reset-author --no-edit     # or: git rebase -i with "edit" + --author
# f) committed to a detached HEAD
git switch -c rescue-branch             # save it, then merge/cherry-pick where it belongs
```

### Q24. Rapid-fire: first command for each symptom

| Symptom | First commands |
|---|---|
| "fatal: not a git repository" | `pwd`; `ls -a`; `git rev-parse --show-toplevel` |
| "Your local changes would be overwritten" | `git status -s`; `git stash -u`; then switch |
| Push rejected (non-fast-forward) | `git fetch`; `git log HEAD..origin/main`; `git pull --rebase` |
| "refusing to merge unrelated histories" | `git pull origin main --allow-unrelated-histories` |
| Detached HEAD | `git status`; `git switch -c save` or `git switch main` |
| Conflict in every file after a rebase | `git rebase --abort`; check `merge.conflictStyle zdiff3` |
| `index.lock` exists | `ps aux | grep git`; if none alive, `rm .git/index.lock` |
| Branch missing after a colleague deleted it | `git reflog`; `git fsck --lost-found`; `git branch name <hash>` |
| Repo is 5 GB, clone takes forever | `git count-objects -vH`; biggest-blob query; `--filter=blob:none`; LFS |
| "Permission denied (publickey)" | `ssh -T git@github.com`; `chmod 600 ~/.ssh/*`; `ssh-add -l` |
| CI sees a different code state than you | `git rev-parse HEAD`; `git status`; is the workspace dirty/cached? |
| Accidentally committed on top of a tag | `git tag -d`; re-tag the right commit; `git push --force origin tag` |
| Submodule shows as modified for no reason | `git submodule status`; `git submodule update --init --recursive` |
| `git log` is unusably slow | `git commit-graph write --reachable`; `feature.manyFiles=true` |

---

## Topic 11 — Senior judgement & design questions

### Q25. Design the source-control strategy for a 200-engineer platform team (30 services, shared libs, IaC).

**Structure:** *repo topology → branching → CI/CD → security → metrics.*
- **Topology:** monorepo for tightly-coupled services + shared libs (atomic changes, one toolchain),
  polyrepo for independently-owned services with different lifecycles/languages. Realistic answer:
  a few monorepos by domain, not one giant repo and not 300 tiny ones. Shared libs published as
  versioned artefacts (not submodules).
- **Branching:** trunk-based, short-lived branches (<2 days), PRs <400 lines, squash-merge to main,
  release branches only for versioned/regulated artefacts.
- **CI/CD:** affected-only builds, remote caching, merge queue, preview environments per PR,
  progressive delivery with automatic rollback on SLO burn.
- **IaC:** same repo as the service it manages where possible; plan-on-PR, apply-on-merge; state in a
  remote backend with locking; no manual changes (drift detection scheduled).
- **Security:** CODEOWNERS, signed commits, secret scanning + push protection, dependency scanning,
  protected branches, least-privilege CI identities via OIDC, SBOM per release.
- **Metrics (DORA):** deployment frequency, lead time for change, change failure rate, MTTR — plus
  PR cycle time, review latency, conflict rate, revert rate.

### Q26. Submodules vs subtrees vs packages vs monorepo for shared code?

| Approach | Pros | Cons |
|---|---|---|
| **Submodules** | pinned SHA, separate history/permissions | detached HEAD, `--recurse-submodules` everywhere, confusing for juniors, awkward updates |
| **Subtrees** | one repo, no extra commands for consumers | merge complexity, history bloat |
| **Package/artefact** (npm/PyPI/Maven/OCI) | proper semver, clean dependency graph, cacheable | release ceremony, version skew, no atomic cross-change |
| **Monorepo** | atomic changes, single toolchain, easy refactors | needs build-graph tooling and Git performance work |
**My rule:** libraries with independent consumers → package. Code only one product uses → same repo.
Cross-team atomic changes → monorepo. Submodules only for vendored third-party code you must pin.

### Q27. How do you migrate 50 repos from GitLab to GitHub with zero loss and minimal downtime?

```bash
# per repo: mirror everything, then verify
git clone --mirror git@gitlab.com:team/repo.git
cd repo.git
git remote set-url --push origin git@github.com:org/repo.git
git push --mirror
# verify parity
diff <(git ls-remote git@gitlab.com:team/repo.git | awk '{print $1, $2}' | sort) \
     <(git ls-remote git@github.com:org/repo.git | awk '{print $1, $2}' | sort)
git count-objects -vH        # compare on both sides
```
**Plan:** inventory (repos, size, LFS objects, protected branches, CI variables, webhooks, tokens) →
freeze window → migrate with `git push --mirror` (plus `git lfs fetch --all && git lfs push --all`) →
verify ref parity and LFS → recreate protection rules/CODEOWNERS/secrets (never copy secrets blindly —
rotate them) → redirect CI/CD → set GitLab read-only with a `README` pointer and HTTP redirects →
communicate → decommission after a soak period. Automate the whole thing as a script with a report of
failures; do one pilot repo first.

### Q28. Behavioural questions for senior Git/platform panels — and the framing they want

1. **"Tell me about a time you lost data or caused an outage."** → own it fully, describe detection,
   mitigation, root cause, and the *systemic* guardrail you added (protected branches, backup
   automation, `--force-with-lease` policy). Never blame a junior.
2. **"How do you handle a team that refuses to adopt a workflow?"** → measure the pain, pilot with one
   willing team, automate the good behaviour so it's the path of least resistance, publish metrics.
3. **"A developer bypassed the process and pushed straight to prod."** → blameless postmortem, fix the
   mechanism (protections, deploy pipeline as the only path), then coach.
4. **"How do you keep 200 engineers unblocked by Git?"** → self-service tooling, golden paths,
   docs/runbooks, office hours, and metrics on PR cycle time.
5. **"Describe a hard technical disagreement."** → data over opinion, the experiment you ran,
   disagree-and-commit, and what you learned.

**Anti-patterns:** reciting flags without a mental model · "just force push it" · no prevention story ·
no metrics · blaming "the juniors" or "legacy".

---

## Answering technique — the loop interviewers grade

```text
1. MODEL   — state the underlying Git concept (objects, refs, index, DAG) before the command
2. COMMAND — name the exact command and what output confirms your hypothesis
3. TRADE-OFF — merge vs rebase, safety vs history cleanliness, speed vs completeness
4. SCALE   — how it behaves at 500 repos / 200 engineers / 10 GB history
5. AUTOMATE — the policy, hook, CI gate or platform control that prevents recurrence
6. QUANTIFY — PR cycle time, conflict rate, clone time, DORA metrics
```

**Phrases that signal seniority:** "the commit is a snapshot, not a diff" · "refs are just files with
a hash in them" · "fetch is safe, pull is not" · "never rewrite published history" ·
"client-side hooks are feedback, server-side controls are policy" · "rotate the secret first, purge
history second" · "the root cause is that it wasn't automated".

**Phrases that signal junior:** "`git pull` and `git fetch` are the same" · "rebase is always cleaner
so always rebase" · "delete `.git` and re-clone" as a recovery plan · "`--force` fixes it" ·
not knowing what a merge commit's two parents mean.

---

## Related files in this course

| Need | File |
|---|---|
| Command reference by topic | the pattern files in each `NN-*/` folder |
| Drill questions with answers | `NN-*/questions-basic.md`, `questions-advanced.md`, `questions-scenarios.md` |
| One-page revision before the interview | `CHEATSHEET.md` |
| The mental model of the three areas | `02-repo-basics/three-areas-model.md` |
| Conflict resolution procedure | `09-conflicts-troubleshooting/resolve-conflicts.md` |
| Every common error message | `09-conflicts-troubleshooting/common-errors.md` |
| Linux interview questions | `../linux-mastery/RTIQ.md` |
