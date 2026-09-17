# Git Workflows & Branching Strategies - SDE3

## GitFlow (Traditional)

```
main (prod)  ----->  v1.0  v1.1 (tags)
  ^  \                 ^   ^
  |   \               /   /
  |  hotfix/fix-bug  /   /
  |     \           /   /
develop  \---------/---/-----> dev branch (integration)
  ^ \ \       \   /
  |  \ \       \ /
  |   feature/login
  |   feature/payment
```

- Branches:
  - **main/master**: Production, tagged releases
  - **develop**: Integration, next release
  - **feature/***: New features from develop, merge back to develop via PR
  - **release/***: Prepare release from develop, bug fixes, then merge to main + develop
  - **hotfix/***: Urgent prod fix from main, merge to main + develop

- Pros: Structured, good for scheduled releases, clear
- Cons: Complex, long-lived branches cause merge conflicts, slow for CI/CD, not ideal for trunk-based
- Use: Large teams, scheduled releases, need to support multiple versions

## GitHub Flow (Simple)

```
main (always deployable)
  \
   feature/login -> PR -> CI -> Review -> Merge to main -> Auto deploy to prod
```

- Only main + feature branches
- Feature branch from main, PR, review, CI passes, merge to main, auto deploy
- No develop branch, no release branches
- Pros: Simple, fast, continuous deployment, less merge conflicts
- Cons: No handling for multiple versions, need feature flags for incomplete features
- Use: SaaS, continuous deployment, small/medium teams, GitHub

## Trunk Based Development (TBD) - Recommended for SDE3

- Single trunk (main), all devs commit to main daily or short-lived branches <1-2 days
- Feature flags to hide incomplete features
- Pros: Fast, less merge conflicts, CI/CD friendly, Google/Facebook use
- Cons: Need discipline, feature flags management, good test coverage required
- Use: Elite teams, microservices, continuous deployment

```
main (trunk) -----> commit daily
  \  / \  /
   \/   \/
  feature flags hide incomplete
```

- Practices:
  - Small commits, commit at least daily
  - Feature flags (LaunchDarkly)
  - Branch by abstraction (gradually replace old implementation)
  - No long-lived branches

## Comparison

| Aspect | GitFlow | GitHub Flow | Trunk Based |
|--------|---------|-------------|-------------|
| Branches | Many long-lived | Main + short feature | Main + very short (<2 days) |
| Release | Scheduled | Continuous | Continuous |
| Complexity | High | Low | Lowest |
| Merge conflicts | High | Medium | Low |
| Feature flags | Optional | Optional | Required |
| CI/CD friendly | Less | Yes | Most |
| Team size | Large | Small-medium | Any with discipline |

## Which to Use When?

- **GitFlow**: Enterprise with quarterly releases, need to support multiple versions, large team
- **GitHub Flow**: SaaS startup, continuous deployment, small team
- **Trunk Based**: SDE3 recommended for microservices, high velocity, elite DORA teams

## Best Practices

1. **Commit Messages**: Conventional Commits
```
feat: add login API
fix: handle null pointer in user service
docs: update README
chore: update dependencies
refactor: extract payment strategy
test: add unit tests for order service
perf: improve query performance
BREAKING CHANGE: rename API endpoint
```
- Format: `type(scope): description` + body + footer

2. **PR Best Practices**:
   - Small PRs <400 lines, easier review
   - One feature per PR
   - Description: What, Why, How, Testing, Screenshots
   - Link ticket JIRA
   - Self-review before requesting review
   - CI must pass before review
   - At least 1-2 approvals
   - Squash and merge for clean history or rebase and merge

3. **Branch Naming**:
```
feature/JIRA-123-add-login
bugfix/JIRA-124-fix-null-pointer
hotfix/JIRA-125-prod-fix
release/v1.2.0
```

4. **Protect Main Branch**:
   - Require PR, require approvals, require CI pass, no direct push, require linear history (rebase)

5. **Rebase vs Merge vs Squash**:

| Strategy | History | When |
|----------|---------|------|
| Merge commit | Preserves all commits + merge commit, non-linear | Team wants full history |
| Squash and merge | One commit per PR, clean linear | Clean main history, recommended for feature branches |
| Rebase and merge | Linear, preserves individual commits, no merge commit | Clean but keeps commits, need to rebase locally |

- **SDE3 Recommendation**: Squash for feature -> main to keep main clean, rebase for updating feature branch with main (`git pull --rebase origin main` or `git rebase main`)

6. **Handling Merge Conflicts**:
```bash
git checkout feature/login
git fetch origin
git rebase origin/main
# fix conflicts
git add .
git rebase --continue
git push --force-with-lease
```

7. **Git Hooks**:
- Pre-commit: Lint, format, run unit tests fast
- Pre-push: Run tests
- Tools: Husky (JS), pre-commit (Python)

## Release Strategies with Git

- **Semantic Versioning**: MAJOR.MINOR.PATCH (1.2.3)
  - MAJOR: Breaking change
  - MINOR: New feature backward compatible
  - PATCH: Bug fix
- **Tagging**: `git tag v1.0.0` + `git push origin --tags`
- **Changelog**: Auto generate from conventional commits via `semantic-release` or `release-please`

## Monorepo vs Polyrepo

| Monorepo | Polyrepo |
|----------|----------|
| One repo many projects (Google, Meta) | One repo per service |
| Shared code easy, atomic changes, single CI | Independent versioning, team autonomy |
| Build complexity, large repo, need Bazel | Dependency management hard, version drift |
| Tools: Bazel, Nx, Turborepo, Lerna | - |

- For microservices: Polyrepo common but monorepo with Nx gaining popularity for small-medium

## Interview Q

**Q: How to handle hotfix in production?**
- GitFlow: Create hotfix branch from main, fix, test, merge to main (tag) + develop
- GitHub Flow/Trunk: Fix in main via PR fast, cherry-pick if needed to release branch, or fix forward, deploy immediately with canary

**Q: How to keep history clean?**
- Squash feature commits into one meaningful commit per PR, rebase feature branch onto main before merge, conventional commits, no merge commits for feature branches

**Q: What is cherry-pick?**
- Apply specific commit from one branch to another without merging whole branch, use for hotfix
```bash
git checkout main
git cherry-pick abc123 # commit from develop
```
