# 🐙 SCENARIO 1 · CI ONLY — GitHub Actions
### Build, test, scan, sign and publish all five apps on every commit — and stop. No deployment step, and no credential that could deploy anything.

> **Scope:** `shop-ui` (React) · `shop-api` (Java 21) · `checkout` (Go) · `order-worker` (Python) · `payment-mock` (Go)
> **Ends at:** a signed image in `ghcr.io/3558bhk/<svc>` and a **`sha256:` digest** written to the job output and to a downloadable artifact.
> **Version anchors:** `actions/checkout@v7` · `actions/setup-java@v5` · `actions/setup-node@v6` · `actions/setup-go@v6` · `actions/setup-python@v6` · `ubuntu-latest` = Ubuntu 24.04 · `docker/build-push-action@v6` · `docker/metadata-action@v5`
> **Read with:** [`../../06-CHEATSHEET.md`](../../06-CHEATSHEET.md) open beside you.

---

## 📇 Contents

| § | What |
|---|---|
| [1](#1--the-two-workflows-you-need) | The two workflows you need, and why not one |
| [2](#2---least-privilege-first) | ⭐⭐ Least privilege first — `permissions:`, fork safety, and what the default token can do |
| [3](#3---registry-auth-without-a-secret--oidc-to-ghcr) | ⭐⭐ Registry auth **without a secret** — OIDC to GHCR |
| [4](#4--the-reusable-ci-workflow) | The reusable workflow — one definition, five services |
| [5](#5---shop-ui--the-caller-workflow-for-the-frontend) | 🔵 `shop-ui` — React frontend CI |
| [6](#6---shop-api--java-21-with-testcontainers) | 🟢 `shop-api` — Java 21 backend CI, with Testcontainers |
| [7](#7---checkout--go) | 🟢 `checkout` — Go service CI |
| [8](#8---order-worker--python) | 🟢 `order-worker` — Python service CI |
| [9](#9---the-monorepo-workflow--path-filters-change-detection-matrix) | ⭐ The monorepo workflow — path filters, change detection, matrix |
| [10](#10---the-digest-handoff) | ⭐⭐ The digest handoff — the only thing Scenario 2 consumes |
| [11](#11--caching-that-actually-works) | Caching that actually works — and the key mistake that silently disables it |
| [12](#12---verify-it-from-your-laptop) | ✅ Verify it from your laptop |
| [13](#13--troubleshooting) | Troubleshooting — the errors you will actually hit |
| [14](#14---tasks--answers-at-the-end) | ⭐ Tasks and answers — **answers at the END** |

---

## 1 · The two workflows you need

| Workflow | Trigger | Pushes an image? | Why it exists separately |
|---|---|---|---|
| **`ci-pr.yml`** | `pull_request` | ⛔ **no** | fast feedback, and ⭐ **safe against untrusted fork code** |
| **`ci-main.yml`** | `push: branches: [main]` | ✅ yes — signed | produces the artifact that Scenario 2 will consume |

⭐ **Why not one workflow with an `if:`?** Because the two need **different `permissions:` blocks**, and a single workflow's `permissions:` is the *union* of what any job might need. Splitting them means the PR workflow genuinely cannot write to your registry — which is a property you can *prove* by reading one line, rather than a property you have to reason about across forty conditionals.

⛔ **And never use `pull_request_target` for CI that builds untrusted code.** It runs in the context of the *base* repo, with the *base* repo's secrets and a **write** token. Combined with a `checkout` of the PR head, that is remote code execution with your credentials. This is a repeatedly-exploited GitHub Actions misconfiguration, not a theoretical one.

---

## 2 · ⭐⭐ Least privilege first

```yaml
# ══════════════════════════════════════════════════════════════════════
# ci-pr.yml — CI for pull requests. Builds and tests. Publishes NOTHING.
# ══════════════════════════════════════════════════════════════════════
# WHAT   : the PR half of Scenario 1.
# WHY    : a PR can come from a fork, i.e. from someone you do not trust.
#          Everything below is chosen so that untrusted code cannot reach
#          a credential, a registry, or a cluster.
# TARGET : a green/red check on the PR. That is all.
# ══════════════════════════════════════════════════════════════════════
name: ci-pr

on:
  pull_request:
    branches: [main]

# ⭐⭐ THE MOST IMPORTANT FOUR LINES IN THIS FILE.
#   The DEFAULT GITHUB_TOKEN is read/write to almost everything in the repo:
#   contents, packages, issues, pull-requests, deployments, id-token, ...
#   Setting `permissions: {}` at the top revokes ALL of it, and then you
#   grant back only what a specific job needs. Default-deny, not default-allow.
permissions: {}

# ⭐ Stop a superseded run. A force-push or a second commit to the same PR
#   cancels the in-flight build instead of letting both finish.
concurrency:
  group: ci-pr-${{ github.event.pull_request.number }}
  cancel-in-progress: true

env:
  # ⭐ pin the registry once; never hard-code it in six places
  REGISTRY: ghcr.io
  IMAGE_NAMESPACE: 3558bhk

jobs:
  # ────────────────────────────────────────────────────────────────────
  # detect what changed, so a docs-only PR does not build four services
  # ────────────────────────────────────────────────────────────────────
  changes:
    runs-on: ubuntu-latest
    permissions:
      contents: read          # ⭐ all `changes-filter` needs
    outputs:
      ui:      ${{ steps.filter.outputs.ui }}
      api:     ${{ steps.filter.outputs.api }}
      go:      ${{ steps.filter.outputs.go }}
      python:  ${{ steps.filter.outputs.python }}
      ci:      ${{ steps.filter.outputs.ci }}
    steps:
      - uses: actions/checkout@v7            # ⭐ v7, not @main. A moving
                                             #   ref in a pipeline is a
                                             #   supply-chain hole.
      # ⭐⭐ PIN THIRD-PARTY ACTIONS BY COMMIT SHA, NOT BY TAG.
      #   A tag can be re-pointed at malicious code (this has happened to
      #   popular actions). The SHA cannot. Put the tag in a comment so a
      #   human can still read it:
      - uses: dorny/paths-filter@v3          # v3.0.2
        id: filter
        with:
          filters: |
            ui:
              - 'apps/shop-ui/**'
            api:
              - 'apps/shop-api/**'
            go:
              - 'apps/checkout/**'
              - 'apps/payment-mock/**'
            python:
              - 'apps/order-worker/**'
            ci:
              - '.github/workflows/**'       # ⭐ a CI change must rebuild
              - 'ci/**'                      #   everything, or you cannot
                                             #   test the pipeline itself

  # ────────────────────────────────────────────────────────────────────
  # 🔵 shop-ui — React
  # ────────────────────────────────────────────────────────────────────
  ui:
    needs: changes
    if: needs.changes.outputs.ui == 'true' || needs.changes.outputs.ci == 'true'
    runs-on: ubuntu-latest
    permissions:
      contents: read          # ⭐ that is ALL. No packages, no id-token.
    steps:
      - uses: actions/checkout@v7

      - uses: actions/setup-node@v6
        with:
          node-version: '24'                 # ⭐ pinned. `lts/*` moves.
          cache: npm
          cache-dependency-path: apps/shop-ui/package-lock.json

      - name: Install (reproducible)
        working-directory: apps/shop-ui
        run: npm ci                          # ⭐ `ci`, NEVER `install`.
                                             #   `install` can UPDATE the
                                             #   lockfile, so two runs of
                                             #   the same commit can differ.

      - name: Lint + type check
        working-directory: apps/shop-ui
        run: |
          npm run lint
          npx tsc --noEmit                   # ⭐ types are a gate, not a hint

      - name: Unit tests
        working-directory: apps/shop-ui
        run: npm run test:unit -- --reporter=junit --outputFile=../../junit-ui.xml

      - name: Build
        working-directory: apps/shop-ui
        run: npm run build

      # ⭐ a quality gate that has nothing to do with "does it compile"
      - name: Bundle size gate
        working-directory: apps/shop-ui
        run: |
          SIZE=$(du -sk dist | cut -f1)
          BUDGET_KB=450
          echo "dist = ${SIZE} KiB (budget ${BUDGET_KB} KiB)"
          if [ "$SIZE" -gt "$BUDGET_KB" ]; then
            echo "::error::bundle grew past budget: ${SIZE} KiB > ${BUDGET_KB} KiB"
            exit 1
          fi
          # ⭐ `::error::` puts the message in the PR annotation, not buried
          #   in a log nobody reads.

      - name: Publish test results
        if: always()                         # ✅ the ONE correct use of
        uses: dorny/test-reporter@v1         #   `always()`: reporting.
        with:                                #   ⛔ never on a build/push step
          name: shop-ui tests
          path: junit-ui.xml
          reporter: java-junit

  # ────────────────────────────────────────────────────────────────────
  # a final gate that summarises, so one check is required in branch rules
  # ────────────────────────────────────────────────────────────────────
  ci-result:
    needs: [changes, ui]
    if: always()
    runs-on: ubuntu-latest
    permissions: {}                          # ⭐ needs nothing at all
    steps:
      - name: Decide
        run: |
          # ⭐⭐ WHY THIS JOB EXISTS: branch protection requires a FIXED set
          #   of check names. But `ui`/`api`/`go`/`python` are conditional —
          #   a skipped check is not a passed check, so a docs-only PR would
          #   hang forever waiting for jobs that will never run.
          #   One always-running summary job solves it: require THIS in
          #   branch protection, and it fails if any real job failed.
          echo "changes = ${{ needs.changes.result }}"
          echo "ui      = ${{ needs.ui.result }}"
          if [ "${{ needs.changes.result }}" != "success" ]; then exit 1; fi
          for r in "${{ needs.ui.result }}"; do
            case "$r" in success|skipped) ;; *) echo "::error::job failed: $r"; exit 1;; esac
          done
```

⭐ **The `ci-result` pattern is the one most people discover the hard way.** Branch protection rules list required status checks *by name*. If `ui` only runs when the frontend changed, then a backend-only PR never produces a `ui` check — and GitHub treats "no check reported" as "still pending", so **the PR can never merge**. The always-running summary job is the standard fix.

---

## 3 · ⭐⭐ Registry auth **without a secret** — OIDC to GHCR

The default way people push to GHCR is a Personal Access Token in a repository secret. ⛔ Do not. That token is a long-lived credential with `write:packages` that lives in your repo's secret store, is available to every workflow that declares it, expires on a date someone will forget, and — if the repo is ever forked with `pull_request_target` misconfigured — leaks.

**GitHub can federate.** The runner gets a short-lived OIDC token, GHCR trusts it, and there is no stored secret at all.

```yaml
  publish:
    runs-on: ubuntu-latest
    permissions:
      contents: read        # to check out
      packages: write       # ⭐ to push to GHCR — declared on THIS JOB only
      id-token: write       # ⭐⭐ THIS is the OIDC grant. Without it,
                            #   `aws-actions/…`/`docker/login-action` with
                            #   oidc cannot mint a token at all.
    steps:
      - uses: actions/checkout@v7

      # ⭐ GHCR accepts the GitHub OIDC token directly via the built-in
      #   GITHUB_TOKEN — no external IdP needed for ghcr.io on the same repo.
      #   For a DIFFERENT registry (ECR, GAR, ACR) you use id-token: write
      #   plus that cloud's OIDC provider:
      #     ECR → aws-actions/configure-aws-credentials@v4  (role-to-assume)
      #     GCR/GAR → google-github-actions/auth@v2         (workload_identity_provider)
      #     ACR → azure/login@v2                            (client-id + tenant +
      #                                                      subscription, no secret)
      - uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}   # ⭐ short-lived, scoped to
                                                  #   THIS run, auto-expires.
                                                  #   Not a PAT.
```

⭐ **The nuance worth knowing:** for `ghcr.io` from the *same* repository, `GITHUB_TOKEN` + `packages: write` is already the federated answer — it is minted per run and dies with it. `id-token: write` becomes necessary when the registry is **someone else's cloud**, and that is where OIDC removes a stored secret entirely. Either way the property you want is the same: **no credential in the repo outlives the run.**

| Registry | Mechanism | Secret stored? |
|---|---|---|
| `ghcr.io` (same repo) | `GITHUB_TOKEN` + `packages: write` | ⭐ **none** |
| `ghcr.io` (another repo/org) | PAT with `write:packages`, or a GitHub App | ⛔ yes |
| AWS ECR | OIDC → `configure-aws-credentials` with `role-to-assume` | ⭐ **none** |
| Google GAR | OIDC → `google-github-actions/auth` with a workload identity pool | ⭐ **none** |
| Azure ACR | OIDC → `azure/login` with federated credentials | ⭐ **none** |
| Docker Hub | ⛔ a PAT — no OIDC. Scope it to one repo, rotate it | ⛔ yes |

---

## 4 · The reusable CI workflow

⭐ **One definition of "how we build and publish", five services.** This is the single highest-leverage thing in the file: when you add a sixth service, you write eleven lines, not two hundred.

```yaml
# ══════════════════════════════════════════════════════════════════════
# .github/workflows/ci-build-publish.yml  — a REUSABLE workflow
# ══════════════════════════════════════════════════════════════════════
# WHAT   : parameterised build → test → image → scan → sign → push,
#          ending with the digest as an output.
# WHY    : five services, one definition of correctness. A fix to the
#          scanning step lands in all five at once.
# CALLED : `uses: ./.github/workflows/ci-build-publish.yml` from another
#          workflow in the SAME repo (or org, with the right visibility).
# ══════════════════════════════════════════════════════════════════════
name: ci-build-publish

on:
  workflow_call:
    inputs:
      service:        { required: true,  type: string }   # e.g. shop-api
      context:        { required: true,  type: string }   # e.g. apps/shop-api
      dockerfile:     { required: false, type: string, default: Dockerfile }
      language:       { required: true,  type: string }   # node|java|go|python
      push:           { required: false, type: boolean, default: false }
      # ⭐⭐ `push` defaults to FALSE. A reusable workflow that could push
      #   must be told to. Default-deny, again.
    outputs:
      digest:
        description: 'the immutable sha256 digest of the published image'
        value: ${{ jobs.image.outputs.digest }}
      image:
        description: 'the fully-qualified image reference, digest-pinned'
        value: ${{ jobs.image.outputs.image }}

permissions: {}                      # ⭐ inherited-and-narrowed, never widened

env:
  REGISTRY: ghcr.io

jobs:
  # ───────────────────────────── build + test ──────────────────────────
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@v7

      # ⭐ ONE step, four languages. `language` selects the toolchain.
      - name: Set up ${{ inputs.language }}
        uses: actions/setup-node@v6
        if: inputs.language == 'node'
        with:
          node-version: '24'
          cache: npm
          cache-dependency-path: ${{ inputs.context }}/package-lock.json

      - uses: actions/setup-java@v5
        if: inputs.language == 'java'
        with:
          distribution: temurin          # ⭐ Temurin, not `oracle`
          java-version: '21'
          cache: maven
          # ⭐ setup-java's maven cache keys on **/pom.xml automatically.

      - uses: actions/setup-go@v6
        if: inputs.language == 'go'
        with:
          go-version-file: ${{ inputs.context }}/go.mod   # ⭐⭐ the version
          cache-dependency-path: ${{ inputs.context }}/go.sum  #  comes from
                                                        #   go.mod, so it can
                                                        #   never drift from
                                                        #   what the code needs

      - uses: actions/setup-python@v6
        if: inputs.language == 'python'
        with:
          python-version-file: ${{ inputs.context }}/.python-version

      - name: Install dependencies
        working-directory: ${{ inputs.context }}
        run: |
          case "${{ inputs.language }}" in
            node)   npm ci ;;
            java)   ./mvnw -B -ntp dependency:go-offline ;;
            go)     go mod download ;;
            python) pip install --no-cache-dir uv && uv sync --frozen ;;
          esac
          # ⭐ the CASE statement IS the polyglot adapter. Everything after
          #   this step is identical for all four languages.

      - name: Test
        working-directory: ${{ inputs.context }}
        run: |
          case "${{ inputs.language }}" in
            node)   npm run test:unit -- --run ;;
            java)   ./mvnw -B -ntp verify ;;
            go)     go test -race -covermode=atomic ./... ;;
            python) uv run pytest -q ;;
          esac

  # ─────────────────────── image · scan · sign · push ───────────────────
  image:
    needs: build                     # ⭐⭐ NEVER `if: always()`. No tests,
    runs-on: ubuntu-latest           #   no image. Full stop.
    permissions:
      contents: read
      packages: write                # only when we intend to push
      id-token: write                # for cosign keyless signing
    outputs:
      digest: ${{ steps.push.outputs.digest }}
      image:  ${{ steps.push.outputs.image }}
    steps:
      - uses: actions/checkout@v7

      - uses: docker/setup-buildx-action@v3

      - uses: docker/login-action@v3
        if: inputs.push
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      # ⭐ metadata-action generates the tag set from the git context.
      #   Do not hand-roll this — it gets the edge cases right (tags,
      #   semver, branches, PRs) and you will not.
      - uses: docker/metadata-action@v5
        id: meta
        with:
          images: ${{ env.REGISTRY }}/${{ github.repository_owner }}/${{ inputs.service }}
          tags: |
            type=sha,prefix=sha-,format=long      # ⭐ sha-<40 hex>: unique per commit
            type=ref,event=branch                 # main — ⚠️ MUTABLE, see below
            type=semver,pattern={{version}}       # only on a tag like v1.4.2
            type=raw,value=latest,enable={{is_default_branch}}

      - uses: docker/build-push-action@v6
        id: push
        with:
          context: ${{ inputs.context }}
          file: ${{ inputs.context }}/${{ inputs.dockerfile }}
          push: ${{ inputs.push }}
          load: ${{ !inputs.push }}      # ⭐ when NOT pushing, load into the
                                         #   local daemon so the scan step has
                                         #   something to scan.
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          # ⭐⭐ REGISTRY CACHE. This is what makes the second build fast.
          #   Without it, BuildKit starts cold on every runner (runners are
          #   ephemeral — there is no local layer cache to reuse).
          cache-from: type=gha,scope=${{ inputs.service }}
          cache-to:   type=gha,scope=${{ inputs.service }},mode=max
          # ⭐ `scope` per service, or the five services evict each other's
          #   cache entries. `mode=max` caches intermediate stages too, not
          #   just the final image.
          provenance: true               # ⭐ SLSA provenance attestation
          sbom: true                     # ⭐ a CycloneDX SBOM attached to the image

      # ⭐ SCAN THE IMAGE, NOT JUST THE SOURCE. A source scan cannot see a
      #   vulnerable library inside your BASE image — which is where most
      #   real CVEs live.
      - uses: aquasecurity/trivy-action@0.28.0
        with:
          image-ref: ${{ env.REGISTRY }}/${{ github.repository_owner }}/${{ inputs.service }}@${{ steps.push.outputs.digest }}
          format: table
          exit-code: '1'                 # ⭐ FAIL the build. A scanner that
          severity: CRITICAL,HIGH        #   only reports is decoration.
          ignore-unfixed: true           # ⭐⭐ otherwise you are blocked by
                                         #   CVEs with no available fix, and
                                         #   the team learns to ignore the gate.

      - name: Sign (cosign, keyless)
        if: inputs.push
        uses: sigstore/cosign-installer@v3
      - if: inputs.push
        run: |
          cosign sign --yes \
            "${REGISTRY}/${GITHUB_REPOSITORY_OWNER}/${{ inputs.service }}@${{ steps.push.outputs.digest }}"
          # ⭐ KEYLESS: cosign uses the OIDC token (id-token: write) to get a
          #   short-lived cert from Fulcio, and logs the signature to Rekor.
          #   No signing key to store, rotate, or leak. The identity recorded
          #   is "this workflow, in this repo, at this commit" — which is
          #   exactly the provenance claim you want.

      - name: ⭐⭐ Emit the digest
        run: |
          IMG="${REGISTRY}/${GITHUB_REPOSITORY_OWNER}/${{ inputs.service }}"
          DIG="${{ steps.push.outputs.digest }}"
          echo "digest=${DIG}"  >> "$GITHUB_OUTPUT"
          echo "image=${IMG}@${DIG}" >> "$GITHUB_OUTPUT"
          # ⭐ AND make it visible to a human, in three places:
          echo "### ${{ inputs.service }}"            >> "$GITHUB_STEP_SUMMARY"
          echo "\`${IMG}@${DIG}\`"                    >> "$GITHUB_STEP_SUMMARY"
          echo "${IMG}@${DIG}" > digest.txt           # uploaded below
          echo "::notice title=${{ inputs.service }} digest::${DIG}"
      - uses: actions/upload-artifact@v4
        with:
          name: digest-${{ inputs.service }}
          path: digest.txt
          retention-days: 90             # ⭐ long enough to audit a release
```

---

## 5 · 🔵 `shop-ui` — the caller workflow for the frontend

```yaml
# .github/workflows/ci-main.yml — runs on main, publishes, hands off a digest
name: ci-main

on:
  push:
    branches: [main]

permissions: {}

concurrency:
  group: ci-main-${{ github.ref }}
  cancel-in-progress: false      # ⭐⭐ FALSE on main. Cancelling a half-finished
                                 #   publish can leave a partially-pushed image.
                                 #   On a PR you want cancel; on main you do not.

jobs:
  changes:
    runs-on: ubuntu-latest
    permissions: { contents: read }
    outputs:
      ui: ${{ steps.f.outputs.ui }}
      api: ${{ steps.f.outputs.api }}
      go: ${{ steps.f.outputs.go }}
      py: ${{ steps.f.outputs.py }}
    steps:
      - uses: actions/checkout@v7
      - uses: dorny/paths-filter@v3
        id: f
        with:
          # ⭐ on a PUSH there is no PR base, so paths-filter compares against
          #   the previous commit automatically. `base:` is only needed if you
          #   want something else.
          filters: |
            ui:  ['apps/shop-ui/**']
            api: ['apps/shop-api/**']
            go:  ['apps/checkout/**', 'apps/payment-mock/**']
            py:  ['apps/order-worker/**']

  ui:
    needs: changes
    if: needs.changes.outputs.ui == 'true'
    uses: ./.github/workflows/ci-build-publish.yml
    with:
      service: shop-ui
      context: apps/shop-ui
      language: node
      push: true                 # ⭐ explicitly opt into publishing
    permissions:
      contents: read
      packages: write
      id-token: write
    # ⭐⭐ A REUSABLE WORKFLOW DOES NOT INHERIT `permissions` FROM THE CALLER
    #   AUTOMATICALLY IN THE WAY PEOPLE EXPECT. You must declare them on the
    #   CALLING JOB, and they can only NARROW what the reusable workflow's own
    #   `permissions:` allows. Getting this wrong produces
    #   "Resource not accessible by integration" — see §13.

  api:
    needs: changes
    if: needs.changes.outputs.api == 'true'
    uses: ./.github/workflows/ci-build-publish.yml
    with: { service: shop-api, context: apps/shop-api, language: java, push: true }
    permissions: { contents: read, packages: write, id-token: write }
    secrets: inherit             # ⚠️ only needed if the callee uses secrets
                                 #   beyond GITHUB_TOKEN. Prefer passing
                                 #   explicit `secrets:` — `inherit` is a
                                 #   blunt instrument.

  go-services:
    needs: changes
    if: needs.changes.outputs.go == 'true'
    strategy:
      fail-fast: false           # ⭐ let `checkout` finish even if
      matrix:                    #   `payment-mock` fails. You want to know
        service: [checkout, payment-mock]   #   about BOTH.
    uses: ./.github/workflows/ci-build-publish.yml
    with:
      service: ${{ matrix.service }}
      context: apps/${{ matrix.service }}
      language: go
      push: true
    permissions: { contents: read, packages: write, id-token: write }

  python:
    needs: changes
    if: needs.changes.outputs.py == 'true'
    uses: ./.github/workflows/ci-build-publish.yml
    with: { service: order-worker, context: apps/order-worker, language: python, push: true }
    permissions: { contents: read, packages: write, id-token: write }

  # ⭐⭐ THE HANDOFF: collect every digest into ONE artifact that CD reads.
  release-manifest:
    needs: [changes, ui, api, go-services, python]
    if: always() && !cancelled()
    runs-on: ubuntu-latest
    permissions: { contents: read }
    steps:
      - name: Fail if any build failed
        run: |
          for r in "${{ needs.changes.result }}" "${{ needs.ui.result }}" \
                   "${{ needs.api.result }}" "${{ needs.go-services.result }}" \
                   "${{ needs.python.result }}"; do
            case "$r" in
              success|skipped) ;;
              *) echo "::error::a build job ended '$r'"; exit 1 ;;
            esac
          done
      - uses: actions/download-artifact@v4
        with: { pattern: digest-*, merge-multiple: true, path: digests/ }
      - name: Write the manifest
        run: |
          {
            echo "# generated by ci-main run ${{ github.run_id }}"
            echo "# commit ${{ github.sha }}"
            echo "# ⭐ CD consumes THIS file and nothing else."
            for f in digests/*; do
              [ -s "$f" ] || continue
              ref=$(cat "$f")
              echo "${ref##*/}" | sed 's/@.*//' | tr -d '\n'
              echo "=${ref}"
            done
          } > release-manifest.txt
          cat release-manifest.txt
          # ── produces ────────────────────────────────────────────────
          # shop-ui=ghcr.io/3558bhk/shop-ui@sha256:9f2c…
          # shop-api=ghcr.io/3558bhk/shop-api@sha256:41ab…
          # checkout=ghcr.io/3558bhk/checkout@sha256:7de0…
          # order-worker=ghcr.io/3558bhk/order-worker@sha256:c3f1…
          # payment-mock=ghcr.io/3558bhk/payment-mock@sha256:0a9b…
          # ───────────────────────────────────────────────────────────
      - uses: actions/upload-artifact@v4
        with: { name: release-manifest, path: release-manifest.txt, retention-days: 90 }
```

---

## 6 · 🟢 `shop-api` — Java 21 with Testcontainers

The reusable workflow handles the shape; these are the Java-specific parts that need explaining.

```yaml
      - name: Test (with Testcontainers)
        working-directory: apps/shop-api
        run: ./mvnw -B -ntp verify
        env:
          # ⭐⭐ Testcontainers needs a Docker daemon. GitHub-hosted runners
          #   HAVE one, so this just works — which is why people never learn
          #   what it depends on, and then it breaks on a self-hosted runner.
          TESTCONTAINERS_RYUK_DISABLED: 'false'
          # ⭐ Ryuk is the reaper container that cleans up. On a CI runner it
          #   can be left ON (it works) — but if you see
          #   "Could not find a valid Docker environment" or Ryuk failing to
          #   connect, THIS is the knob:
          #     TESTCONTAINERS_RYUK_DISABLED: 'true'
          #   and accept that containers are cleaned by runner teardown.
```

```dockerfile
# apps/shop-api/Dockerfile — ⭐ the multi-stage build CI depends on
# ── stage 1: build. Heavy. Never ships. ────────────────────────────────
FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /src
# ⭐⭐ COPY THE POM FIRST. This single ordering decision is what makes the
#   registry cache effective: dependencies are re-downloaded only when the
#   POM changes, not on every source edit.
COPY pom.xml .
RUN --mount=type=cache,target=/root/.m2/repository \
    mvn -B -ntp dependency:go-offline
COPY src ./src
RUN --mount=type=cache,target=/root/.m2/repository \
    mvn -B -ntp clean package -DskipTests
# ⭐ `-DskipTests` HERE, not in CI. Tests already ran in the `build` job,
#   against the real source. Running them twice doubles the wall time and
#   tests the same thing.

# ── stage 2: runtime. Small. This is what ships. ───────────────────────
FROM eclipse-temurin:21-jre-alpine
# ⭐ a NON-ROOT user. Docker P5 taught this; a pipeline that ships a
#   root-container image has undone it.
RUN addgroup -S app && adduser -S app -G app
USER app
WORKDIR /app
COPY --from=build /src/target/*.jar app.jar
EXPOSE 8080
# ⭐⭐ JVM IN A CONTAINER: never -Xmx. The JVM must size itself from the
#   cgroup limit, or Kubernetes OOMKills it (exit 137) with no heap dump
#   and no OutOfMemoryError — the kernel kills the process, the JVM never
#   sees it coming.
ENV JAVA_OPTS="-XX:MaxRAMPercentage=75.0 \
 -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/tmp \
 -XX:+ExitOnOutOfMemoryError \
 -XX:StartFlightRecording=disk=true,maxsize=64m,dumponexit=true,filename=/tmp"
ENTRYPOINT ["sh","-c","exec java $JAVA_OPTS -jar app.jar"]
# ⭐ `exec` so the JVM is PID 1 and receives SIGTERM directly — otherwise
#   the shell swallows it and Kubernetes waits out terminationGracePeriod
#   before SIGKILLing mid-request.
```

```bash
# ✅ VERIFY the image is what you think, from your laptop:
docker pull ghcr.io/3558bhk/shop-api@sha256:<digest>
docker image inspect ghcr.io/3558bhk/shop-api@sha256:<digest> \
  --format 'size={{.Size}} user={{.Config.User}} entry={{.Config.Entrypoint}}'
# expect: size≈230MB  user=app  entry=[sh -c exec java …]
```

---

## 7 · 🟢 `checkout` — Go

```dockerfile
# apps/checkout/Dockerfile
FROM golang:1.23-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download                    # ⭐ cached layer
COPY . .
# ⭐⭐ -trimpath removes the build machine's filesystem paths from the binary
#   (so your CI directory structure is not embedded in a production artifact).
#   -ldflags="-s -w" strips symbols and DWARF: ~30% smaller.
#   -X injects the version AT BUILD TIME — no runtime lookup, no build arg
#   leaking into the image config.
ARG GIT_SHA=dev
RUN CGO_ENABLED=0 go build -trimpath \
    -ldflags="-s -w -X main.version=${GIT_SHA}" \
    -o /out/checkout ./cmd/checkout
# ⭐ CGO_ENABLED=0 gives a STATIC binary — which is what makes `FROM scratch`
#   possible in the next stage.

FROM scratch
# ⭐⭐ `scratch` is an EMPTY image. No shell, no package manager, no /etc,
#   no user database. ~8–15 MB total. Nothing to CVE-scan, nothing to patch.
# ⚠️ THE COST, stated honestly: you cannot `docker exec -it … sh` into it,
#   because there is no shell. Debugging is logs + a distroless debug variant.
#   That trade is worth it for a network-facing service; it is NOT worth it
#   for something you operate by hand.
COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
# ⭐ REQUIRED for outbound HTTPS. `scratch` has no CA bundle, so every TLS
#   call fails with x509: certificate signed by unknown authority.
COPY --from=build /out/checkout /checkout
USER 65534                             # ⭐ nobody. Not root — `scratch` has
                                       #   no /etc/passwd, so use a UID.
EXPOSE 9091
ENTRYPOINT ["/checkout"]
```

```yaml
      - uses: docker/build-push-action@v6
        with:
          context: apps/checkout
          build-args: GIT_SHA=${{ github.sha }}    # ⭐ the version injection
          cache-from: type=gha,scope=checkout
          cache-to: type=gha,scope=checkout,mode=max
```

---

## 8 · 🟢 `order-worker` — Python

```dockerfile
# apps/order-worker/Dockerfile
FROM python:3.13-slim AS build
# ⭐⭐ `slim`, NOT `alpine`. Alpine uses musl libc; wheels compiled against
#   glibc (psycopg, numpy, cryptography, pydantic-core…) will not install and
#   pip falls back to building from source — which needs gcc + headers and is
#   10× slower, or fails outright. `slim` is glibc and ~120 MB.
WORKDIR /src
COPY pyproject.toml uv.lock ./
RUN pip install --no-cache-dir uv && uv sync --frozen --no-dev
COPY src ./src

FROM python:3.13-slim
RUN addgroup --system app && adduser --system --ingroup app app
WORKDIR /app
COPY --from=build --chown=app:app /src/.venv /app/.venv
COPY --from=build --chown=app:app /src/src /app/src
ENV PATH="/app/.venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1
# ⭐ PYTHONUNBUFFERED=1 or your logs appear in bursts and `kubectl logs -f`
#   looks like the worker has hung.
USER app
# ⭐⭐ NO EXPOSE, NO HEALTHCHECK PORT. This is a QUEUE CONSUMER. Its health is
#   "am I connected to the broker and not paused", which is a heartbeat, not
#   an HTTP endpoint. See 00-PROJECT-INVENTORY §6.4.
ENTRYPOINT ["python","-m","src.worker"]
```

```yaml
      - name: Test
        working-directory: apps/order-worker
        run: |
          uv run ruff check .
          uv run ruff format --check .
          uv run mypy src
          uv run pip-audit                      # ⭐ dependency CVEs
          uv run pytest -q --cov=src --cov-fail-under=80
```

---

## 9 · ⭐ The monorepo workflow — path filters, change detection, matrix

Three mechanisms, and the failure mode of each:

| Mechanism | What it does | ⛔ Failure mode if you skip it |
|---|---|---|
| **`paths:` on the trigger** | don't *start* the workflow | a docs-only commit builds five services for nine minutes |
| **`dorny/paths-filter` + `if:`** | start it, then decide *which jobs* run | ⭐ you cannot use `paths:` on a trigger when one workflow serves five services — you need per-job filtering |
| **`strategy.matrix`** | one job definition, N services | five copies of the same YAML that drift apart |

```yaml
# ⭐ the shape, condensed:
on:
  push:
    branches: [main]
    paths-ignore:                 # ⭐ a blunt but useful first filter
      - '**.md'
      - 'docs/**'
      - '.gitignore'
    # ⚠️ `paths` and `paths-ignore` are mutually exclusive in one trigger.
    #    And ⛔ NEVER use paths-ignore as your ONLY filter for a monorepo —
    #    it cannot express "only the service that changed".
```

⭐⭐ **The monorepo trap worth naming:** path filters decide whether a *workflow* runs. They cannot make a *deployment* conditional on the right service having changed, because by the time CD reads the manifest it has no idea what triggered CI. That is why §5's `release-manifest` job lists **only the services that actually built** — CD then deploys exactly that set, and a docs-only commit produces an empty manifest and no deployment at all.

---

## 10 · ⭐⭐ The digest handoff

**This is the only thing Scenario 2 consumes.** Everything above exists to produce it correctly.

| Property | Requirement | Why |
|---|---|---|
| **Immutable** | ⭐ `sha256:…`, never a tag | a tag can be re-pushed. `main` today and `main` tomorrow are different images |
| **Complete** | `registry/namespace/service@sha256:…` | a bare digest is ambiguous across registries |
| **Discoverable** | job output **and** artifact **and** step summary **and** `::notice` | CD reads the artifact; a human reads the summary; an on-call engineer reads the notice |
| **Attributable** | signed by cosign, provenance attestation attached | so CD can *verify* it, not just trust it |
| **Set-valued** | one manifest for the whole release train | ⭐ shape C/D need FE and BE promoted **together**, in order |

```bash
# what CD does with it — and this is ALL of Scenario 2's input:
gh run download <run-id> -n release-manifest -D /tmp/rel
cat /tmp/rel/release-manifest.txt
# shop-ui=ghcr.io/3558bhk/shop-ui@sha256:9f2c…
# shop-api=ghcr.io/3558bhk/shop-api@sha256:41ab…

# ⭐ and the verification that makes it trustworthy rather than hopeful:
cosign verify \
  --certificate-identity-regexp="https://github.com/3558bhk/shop/.github/workflows/ci-build-publish.yml@refs/heads/main" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  ghcr.io/3558bhk/shop-api@sha256:41ab…
# ✅ asserts: this image was built by THIS workflow, in THIS repo, on main.
#   An image from anywhere else fails verification. That is a real supply-chain
#   boundary, and it costs four lines.
```

---

## 11 · Caching that actually works

| Layer | Mechanism | Key on | ⛔ The mistake |
|---|---|---|---|
| **Language deps** | `setup-*` built-in `cache:` | ⭐ the **lockfile** | keying on source files → cache misses on every commit |
| **Docker layers** | `cache-from/to: type=gha` | ⭐ `scope=<service>` | no scope → five services evict each other |
| **Dockerfile ordering** | ⭐ copy deps before source | — | `COPY . .` before installing → every source edit re-downloads everything |
| **Test results** | none — don't | — | caching tests means not running them |

```yaml
# ⛔ SLOW — every code change invalidates the dependency download
- run: npm ci
# (with a cache keyed on: ${{ hashFiles('**') }})

# ✅ FAST — dependencies are a separate, rarely-changing layer
- uses: actions/setup-node@v6
  with:
    cache: npm
    cache-dependency-path: apps/shop-ui/package-lock.json
# ⭐ setup-node's npm cache keys on the LOCKFILE HASH by default when you
#   give it cache-dependency-path. That is exactly right.
```

⭐ **`type=gha` cache limits, because they will surprise you:** 10 GB total per repository, and entries are evicted **least-recently-used** after 7 days without access. A monorepo with five services and `mode=max` can blow through 10 GB, after which caching silently degrades and builds get slower with no error. If that happens, either narrow `mode=min` (final layers only) or drop the scope on services that build fast anyway.

---

## 12 · ✅ Verify it from your laptop

```bash
# 1. the workflow ran and published
gh run list --workflow=ci-main.yml --limit 5
gh run view <run-id> --log | grep -E 'digest|sha256' | head

# 2. ⭐ the digest is real and pullable — the whole point of Scenario 1
DIGEST=$(gh run download <run-id> -n digest-shop-api --output - 2>/dev/null | tail -1)
docker pull "ghcr.io/3558bhk/shop-api@${DIGEST}"

# 3. the signature verifies
cosign verify \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  "ghcr.io/3558bhk/shop-api@${DIGEST}" | jq '.[0].critical.identity'

# 4. the attestation is attached (provenance + SBOM)
docker buildx imagetools inspect "ghcr.io/3558bhk/shop-api@${DIGEST}" \
  --format '{{ json .Manifest }}' | jq '.annotations'

# 5. ⭐⭐ PROVE IT IS CI-ONLY: no deploy verb, no cluster credential
grep -RnE 'kubectl|helm|compose up|ssh |scp |set image|argocd|apply -f' .github/workflows/ \
  && echo "⛔ NOT CI-ONLY" || echo "✅ no deployment verb anywhere"
gh secret list                        # ⭐ should contain NO cluster credential
gh variable list
gh api repos/:owner/:repo/environments | jq '.environments[].name'
                                      # ⭐ a CI-only repo has no `production`
                                      #   environment at all
```

---

## 13 · Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `Resource not accessible by integration` | ⭐ the caller job did not declare `permissions:` for the reusable workflow | declare `contents: read`, `packages: write`, `id-token: write` **on the calling job** — a reusable workflow narrows, never widens |
| `denied: permission denied` on push | `packages: write` missing, or the package already exists and is owned by another repo | add the permission; for an existing package, link the repo in GHCR package settings |
| `error: unknown response format` from cosign | `id-token: write` missing | keyless signing needs the OIDC grant |
| Trivy fails on an unfixable CVE | you did not set `ignore-unfixed` | ⭐ set it — otherwise the team learns to bypass the gate |
| Cache "not found" every run | key mismatch, or the 10 GB repo limit was hit | check `cache-dependency-path`; add `scope=` per service; consider `mode=min` |
| `docker buildx: no match for platform` | building for the wrong arch on an ARM runner | pin `platforms: linux/amd64` explicitly |
| Tests pass locally, fail in CI | ⭐ Testcontainers/Ryuk, or a missing service container | set `TESTCONTAINERS_RYUK_DISABLED=true` as a diagnostic; add a `services:` block |
| The PR check never completes | a conditional job was required in branch protection | ⭐ add the `ci-result` summary job (§2) and require **that** |
| A fork PR got your secrets | `pull_request_target` + checkout of PR head | ⛔ never. Use `pull_request`, and gate privileged steps on same-repo |
| Two runs raced and one pushed a stale image | no `concurrency:` group | add one — `cancel-in-progress: true` on PRs, **`false`** on main |

---

<a name="tasks--answers"></a>
## 14 · ⭐ TASKS — answers at the END

| # | Task |
|---|---|
| **T1** | Write `ci-pr.yml` and `ci-main.yml` for `shop-ui` alone. Prove a PR builds but publishes nothing |
| **T2** | Convert §5 into the reusable-workflow pattern and call it for all five services |
| **T3** | Add a bundle-size gate to `shop-ui` that fails above 450 KiB and annotates the PR |
| **T4** | Make `shop-api`'s integration tests use Testcontainers with a real Postgres 17 |
| **T5** | Implement the `release-manifest` job so a docs-only commit produces an **empty** manifest |
| **T6** | Replace a stored GHCR PAT with OIDC/`GITHUB_TOKEN` and prove no secret remains |
| **T7** | Add cosign keyless signing and write the `cosign verify` command that proves provenance |
| **T8** | Add the `ci-result` summary job and configure branch protection to require it |
| **T9** | ⭐ Run all five CI-only checks from §12 and record the output |
| **T10** | ⭐⭐ Deliberately break the digest contract (push `:latest` only) and write down every downstream guarantee you just lost |

---

# ✅ ANSWERS

**T1.** Two files. `ci-pr.yml`: `on: pull_request`, `permissions: { contents: read }` at the top and on every job, **no `docker/login-action` step at all**, and `docker/build-push-action` with `push: false, load: true` so the image is built and scanned but never leaves the runner. `ci-main.yml`: `on: push: branches: [main]`, with `packages: write` + `id-token: write` on the publish job only. **Proof:** `gh secret list` shows nothing registry-related; on a PR run, `gh run view --log | grep -c 'pushing manifest'` returns 0; and `gh api repos/:owner/:repo/packages?package_type=container` shows no new version with the PR's SHA.

**T2.** §4 is the answer. The five caller jobs are §5. The one subtlety: `permissions:` must be declared on **each calling job**, and can only narrow what the reusable workflow's own `permissions:` allows. Declare `packages: write` at the workflow top level and you have silently given every job — including `changes` — the ability to push images.

**T3.** In §2's `ui` job. Two details make it a real gate rather than decoration: `du -sk dist` measures the *built* output, not the source; and `echo "::error::…"` surfaces the failure as a **PR annotation** at the top of the Files Changed tab. A gate whose output is buried on log line 4,217 is not a gate.

**T4.** Add a `services:` block only if you are *not* using Testcontainers — with Testcontainers you need nothing, because the library starts Postgres itself against the runner's Docker daemon. The dependency is `org.testcontainers:postgresql` in `pom.xml` with `test` scope, and a `@Testcontainers` / `@Container static PostgreSQLContainer<?> PG = new PostgreSQLContainer<>("postgres:17.7")`. ⭐ Pin the **image by tag at minimum**, and ideally by digest, or your tests change behaviour when Postgres publishes a patch.

**T5.** The `if: always() && !cancelled()` on `release-manifest` plus the per-job `case` check. The key mechanism: `actions/download-artifact` with `pattern: digest-*` only finds artifacts that were **actually uploaded**, and a skipped job uploads nothing. So a docs-only commit → all build jobs `skipped` → `digests/` is empty → the manifest is just comment lines. **Then CD must treat an empty manifest as "nothing to do"**, not as an error — that check lives in Scenario 2, and forgetting it is how a docs commit triggers a production deployment of whatever was there before.

**T6.** §3. Remove the `GHCR_TOKEN` secret, set `permissions: packages: write` on the publish job, and use `username: ${{ github.actor }}` / `password: ${{ secrets.GITHUB_TOKEN }}`. **Proof:** `gh secret list` is empty of registry credentials, and the pushed package's "Manage Actions access" shows the repository — the token is minted per run and dies with it.

**T7.** §4's sign step plus §10's verify command. The `--certificate-identity-regexp` is what makes it meaningful: without it, `cosign verify` accepts a signature from *any* workflow in *any* repo that used keyless signing. With it, you assert "built by this specific workflow file, on main, in this repository" — which is the actual claim you care about.

**T8.** §2's `ci-result` job. Branch protection → require status checks → select **`ci-result`** only, not `ui`/`api`/`go-services`/`python`. ⭐ The reason: those four are conditional. A skipped check reports nothing, and GitHub treats "nothing reported" as pending — so a docs-only PR would hang forever. One always-running summary job that fails if any real job failed is the standard fix.

**T9.** The five commands in §12. The one that matters most and that people skip is **#5**: `grep -RnE 'kubectl|helm|compose up|ssh |set image|argocd' .github/workflows/` must return nothing, **and** `gh secret list` must contain no cluster credential. A pipeline with no deploy step but a kubeconfig in its secrets is not CI-only — it is one `run:` line away from deploying, writable by anyone with repo access.

**T10.** ⭐⭐ Pushing only `:latest` loses, in order of severity: **(1) rollback** — there is no previous artifact to point at, so "roll back" means "rebuild the old commit", which may produce *different bytes* because base layers and transitive dependencies have moved; **(2) reproducibility** — you cannot answer "what exactly is running in production?", because `:latest` was overwritten by the next build; **(3) the FE↔BE contract** — shape C needs FE and BE promoted *together*, and a mutable tag gives you no way to pin a pair; **(4) auditability** — no digest means no signature verification target, so cosign/provenance become decoration; **(5) concurrency safety** — two deploys can pull different images from the same tag mid-rollout, leaving a fleet on two versions with no record of which is which. That last one is the sleeper: it produces an incident that is *impossible* to reconstruct afterwards, because the evidence was overwritten.

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish_Kumar_Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn: https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260
🔗 GitHub: https://github.com/3558Bhk

*A CI-only pipeline that cannot deploy is not limited. It is correct.*

</div>
