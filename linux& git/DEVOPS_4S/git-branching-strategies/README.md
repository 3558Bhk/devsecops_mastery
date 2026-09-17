# Git Branching Strategies — Types, Diagrams & Interview Scenarios

A complete deep-dive on **how teams organise branches**: every model, its diagram, its commands,
its failure modes, and the interview questions that come with it.

```text
git-branching-strategies/
├── README.md                        ← you are here
├── CHEATSHEET.md                    ← one-page decision matrix + all diagrams
├── DIAGRAMS.md                      ← every diagram in one place, ASCII + Mermaid gitGraph
├── 01-fundamentals/                 what a branch IS, branch taxonomy, naming conventions
├── 02-git-flow/                     GitFlow: main/develop/feature/release/hotfix
├── 03-github-flow/                  GitHub Flow: main + short-lived PRs + continuous deploy
├── 04-gitlab-flow/                  GitLab Flow: environment branches + release branches
├── 05-trunk-based-development/      Trunk-Based: one trunk, feature flags, small batches
├── 06-release-hotfix/               release trains, semver, hotfix/patch branches
├── 07-choosing-a-strategy/          decision matrix + migrating between models
└── 08-interview-scenarios/          16 worked interview scenarios + 8 drills + 60 rapid-fire answers
```

Every topic folder follows the course format: **pattern files** (commands with a comment on every
line) plus **three question files** — `questions-basic.md`, `questions-advanced.md`,
`questions-scenarios.md`.

---

## The 60-second summary (memorise this table)

| Model | Long-lived branches | Release style | Deploy frequency | Team size | Best when |
|---|---|---|---|---|---|
| **GitFlow** | `main` + `develop` | versioned releases (`release/*`) | weeks–months | 5–50 | Shrink-wrapped / versioned products, mobile apps, on-prem |
| **GitHub Flow** | `main` only | deploy from `main` | many per day | 2–30 | SaaS/web with good CI and rollback |
| **GitLab Flow** | `main` + env/release branches | promotion through environments | daily–weekly | 5–100 | Multiple environments, regulated promotion, on-prem + SaaS mix |
| **Trunk-Based** | `main` only (trunk) | continuous, flags control exposure | many per day | any (elite teams) | High-performing DevOps, feature flags, strong tests |
| **Release Train** | `main` + `release/X.Y` | scheduled trains | fixed cadence | 20–500 | Products with planned releases, multiple maintained versions |
| **Forking (OSS)** | upstream `main` + your fork | maintainer-driven | varies | unbounded | Open source, no write access to the main repo |

---

## How to answer "which branching strategy do you use?" in an interview

Do **not** just name one. Use this four-part structure:

```text
1. PICK     — "Trunk-based development with short-lived branches and squash merges."
2. JUSTIFY  — "We deploy to production continuously behind feature flags, so a long-lived
               develop branch would only delay feedback and manufacture merge conflicts."
3. TRADE-OFF— "The cost is discipline: PRs must stay under ~400 lines and every risky change
               needs a flag. Teams without fast CI get hurt by this model."
4. ADAPT    — "For our on-prem customers on versioned releases we cut release/1.4 branches
               from the trunk and cherry-pick security fixes back — a GitLab-flow hybrid."
```

Naming the **trade-off** and the **hybrid** is what marks a senior answer. Anyone can recite GitFlow.

---

## The one diagram that explains every strategy

All models are the same two questions:

```text
   Q1: Where does finished code live?          Q2: How does it get to production?
   ┌────────────────────────────┐              ┌──────────────────────────────┐
   │  one branch (trunk)        │              │  directly from trunk         │
   │  or two (main + develop)   │              │  via a release branch        │
   │  or many (env branches)    │              │  via environment promotion   │
   └────────────────────────────┘              └──────────────────────────────┘

   GitFlow      → two branches (main + develop)  + release/* branches + hotfix/*
   GitHub Flow  → one branch (main)              + direct deploy from main
   GitLab Flow  → one or more env branches       + promotion preprod → prod
   Trunk-Based  → one branch (trunk)             + direct deploy, flags hide WIP
   Release Train→ one trunk + release/X.Y        + scheduled trains, cherry-pick fixes
```

---

## Prerequisites

Work through these first if any of it is unfamiliar:

| Need | Go to |
|---|---|
| `branch`, `switch`, `merge`, fast-forward vs 3-way | `../git/04-branching-merging/` |
| `rebase`, `cherry-pick`, interactive rebase | `../git/08-rebase-advanced/` |
| `fetch`, `pull`, `push`, remotes, forks, PRs | `../git/06-remotes-collaboration/` |
| Conflict resolution | `../git/09-conflicts-troubleshooting/resolve-conflicts.md` |
| Tags, semver, releases | `../git/07-stash-tags/tags-releases.md` |
| General Git interview questions | `../git/RTIQ.md` |

---

## Practice setup

```bash
mkdir ~/branch-practice && cd ~/branch-practice   # a sandbox you can destroy freely
git init -b main                                   # start on main (modern default)
git config user.name "You" && git config user.email "you@example.com"
echo "# demo" > README.md && git add -A && git commit -m "init"
```
Then follow the command walkthrough in each strategy file — every one of them is a complete,
runnable exercise that builds the diagram you see.
