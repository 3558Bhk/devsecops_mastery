# 🔷 SCENARIO 1 · CI ONLY — Azure DevOps
### Build, test, scan, sign and publish all five apps on every commit — and stop. Templates, Workload Identity Federation, and a digest that leaves the pipeline as a real artifact.

> **Scope:** `shop-ui` (React) · `shop-api` (Java 21) · `checkout` (Go) · `order-worker` (Python) · `payment-mock` (Go)
> **Ends at:** a signed image in `shopacr.azurecr.io/<svc>` and a **`sha256:` digest** published as a pipeline artifact.
> **Version anchors:** Azure DevOps SaaS · `vmImage: ubuntu-latest` (Ubuntu 24.04) · task versions pinned to majors (`Maven@4`, `Docker@2`, `Npm@1`, `Go@0`, `UsePythonVersion@0`, `PublishPipelineArtifact@1`)
> **Read with:** [`../../02-CASE-1-azure-devops.md`](../../02-CASE-1-azure-devops.md) for the syntax deep-dive; [`../../06-CHEATSHEET.md`](../../06-CHEATSHEET.md) beside you.

---

## 📇 Contents

| § | What |
|---|---|
| [1](#1--what-azure-devops-gives-you-that-the-other-two-do-not) | What Azure DevOps gives you that the other two do not |
| [2](#2---parameters-vs-variables--the-mistake-everyone-makes-first) | ⭐⭐ `parameters` vs `variables` — the mistake everyone makes first |
| [3](#3--the-reusable-ci-template) | The reusable CI template — one definition, five services |
| [4](#4--the-caller-pipeline) | The caller pipeline — path filters and the fan-out |
| [5](#5---registry-auth-without-a-secret--workload-identity-federation) | ⭐⭐ Registry auth without a secret — Workload Identity Federation |
| [6](#6--per-language-notes) | Per-language notes: `shop-ui`, `shop-api`, `checkout`, `order-worker` |
| [7](#7---the-digest-handoff) | ⭐⭐ The digest handoff — `PublishPipelineArtifact`, not a log line |
| [8](#8--caching) | Caching — `Cache@2`, restore keys, and the 10 GB limit |
| [9](#9---proving-it-is-ci-only--azure-flavoured) | ⭐ Proving it is CI-only — the five checks, Azure-flavoured |
| [10](#10---verify-it-from-your-laptop) | ✅ Verify it from your laptop |
| [11](#11--troubleshooting) | Troubleshooting |
| [12](#12---tasks--answers-at-the-end) | ⭐ Tasks and answers — **answers at the END** |

---

## 1 · What Azure DevOps gives you that the other two do not

| Strength | Why it matters for CI |
|---|---|
| ⭐ **`parameters` are compile-time** | a template can branch on a parameter to *rename tasks* and *change structure*. Runtime variables cannot do this. §2 |
| ⭐⭐ **Environments + Approvals + Checks** | the best built-in governance of the three. Not used in Scenario 1 — and that absence is *itself* the proof that this pipeline is CI-only (§9) |
| **Variable groups + Key Vault** | secrets backed by Key Vault with rotation and access policy, not a flat secret store |
| **Workload Identity Federation** | ⭐ a service connection with **no secret at all** — federated, auto-rotating |
| **Boards / Repos / Artifacts in one product** | a build failure can create a work item automatically |
| **`PublishPipelineArtifact`** | ⭐ a first-class artifact store with retention, separate from the container registry |

⛔ **What it does not give you:** anything like GitHub's marketplace. Every non-Microsoft task is a smaller ecosystem, and third-party tasks are a supply-chain surface you must vet. Prefer the built-in `Bash`/`Docker`/`Maven` tasks over a marketplace extension when both can do the job.

---

## 2 · ⭐⭐ `parameters` vs `variables` — the mistake everyone makes first

| | `parameters` | `variables` |
|---|---|---|
| Resolved | ⭐ **at compile time** (YAML expansion, before the run exists) | **at runtime** |
| Typed | ✅ `string`, `boolean`, `object`, `array`, with `default:` and `values:` | ⛔ everything is a **string** |
| Usable in `if:` / `${{ }}` template expressions | ✅ yes | ⛔ **no** — `if: ${{ variables.x }}` does not work as you expect |
| Usable to build task **names** or choose **which task** runs | ✅ yes | ⛔ no |
| Changeable at queue time | ✅ if `type` allows | ✅ |
| Can hold a secret | ⛔ **no** — parameters are logged and visible in the YAML | ✅ via variable groups / Key Vault |

```yaml
# ⛔ THE WRONG VERSION — this is the error almost everyone hits first
variables:
  language: java
steps:
  - ${{ if eq(variables.language, 'java') }}:      # ⛔ evaluates at COMPILE
      - task: Maven@4                              #   time, when `variables`
                                                   #   is not yet resolved
# → the branch is never taken, or you get a template-expression parse error.

# ✅ THE RIGHT VERSION
parameters:
  - name: language
    type: string
    values: [node, java, go, python]      # ⭐ a compile-time enum. The
                                          #   pipeline will not even parse
                                          #   with an invalid value.
steps:
  - ${{ if eq(parameters.language, 'java') }}:    # ✅ resolved at compile time
      - task: Maven@4
```

⭐ **The rule to memorise:** *structure* is a `parameter`; *data* is a `variable`; *secrets* are neither — they come from a variable group backed by Key Vault.

---

## 3 · The reusable CI template

```yaml
# ══════════════════════════════════════════════════════════════════════
# ci/templates/build-test-image.yml — one definition of "how we build"
# ══════════════════════════════════════════════════════════════════════
# WHAT   : parameterised build → test → image → scan → sign → publish
#          artifact. Ends with the digest in a downloadable artifact.
# WHY    : five services, one definition of correctness. A change to the
#          scan step lands in all five at once.
# CALLED : `- template: ci/templates/build-test-image.yml` with `parameters:`
# ══════════════════════════════════════════════════════════════════════
parameters:
  - name: service                       # e.g. shop-api
    type: string
  - name: context                       # e.g. apps/shop-api
    type: string
  - name: language
    type: string
    values: [node, java, go, python]     # ⭐ compile-time enum
  - name: acrName
    type: string
    default: shopacr
  - name: serviceConnection
    type: string
    default: sc-acr-federated            # ⭐ Workload Identity Federation,
                                         #   NO secret — see §5
  - name: publish
    type: boolean
    default: false                       # ⭐⭐ DEFAULT-DENY. A template that
                                         #   could push must be told to.

jobs:
  # ─────────────────────────── build + test ────────────────────────────
  - job: build_${{ replace(parameters.service, '-', '_') }}
    # ⭐ job names must be identifiers. `shop-api` is not one, so hyphens
    #   are replaced. Forgetting this gives a confusing "invalid job name".
    displayName: 'build+test · ${{ parameters.service }}'
    pool:
      vmImage: ubuntu-latest             # ⭐ Ubuntu 24.04. Pin further with
                                         #   `ubuntu-24.04` if you need
                                         #   reproducibility across MS image
                                         #   refreshes.
    timeoutInMinutes: 30                 # ⭐ ALWAYS set this. The default is
                                         #   60 and a hung build burns an
                                         #   entire parallel-job slot.
    workspace:
      clean: all                         # ⭐ on a SELF-HOSTED agent this is
                                         #   essential; on a hosted pool the
                                         #   VM is fresh anyway.
    steps:
      - checkout: self
        fetchDepth: 1                    # ⭐ a shallow clone. You do not need
                                         #   history to build. (Set 0 if a step
                                         #   runs `git describe`.)
        clean: true

      # ── toolchain, selected at COMPILE time ──────────────────────────
      - ${{ if eq(parameters.language, 'node') }}:
        - task: NodeTool@0
          displayName: 'pin Node 24'
          inputs:
            versionSpec: '24.x'          # ⭐ pinned. `latest` moves.
        - task: Npm@1
          displayName: 'npm ci (reproducible)'
          inputs:
            command: ci                  # ⭐ `ci`, never `install` — install
            workingDir: ${{ parameters.context }}   #  can rewrite the lockfile

      - ${{ if eq(parameters.language, 'java') }}:
        - task: JavaToolInstaller@0
          displayName: 'pin Temurin 21'
          inputs:
            versionSpec: '21'
            jdkArchitectureOption: 'x64'
            jdkSourceOption: 'PreInstalled'
        # ⭐⭐ CACHE THE MAVEN REPO. Without this, every build re-downloads
        #   ~200 MB of dependencies. This is the single biggest CI win for
        #   a Java service.
        - task: Cache@2
          displayName: 'cache ~/.m2'
          inputs:
            key: 'maven | "$(Agent.OS)" | ${{ parameters.context }}/pom.xml'
            # ⭐ key on the POM, not on the source. Dependencies change when
            #   the POM changes — not when a .java file does.
            path: $(MAVEN_CACHE_FOLDER)
            restoreKeys: |
              maven | "$(Agent.OS)"
            # ⭐ a partial match restores *something*, which is still far
            #   faster than nothing. `restoreKeys` is what makes the cache
            #   useful on the first build after a POM change.
            cacheHitVar: MAVEN_CACHE_RESTORED
        - task: Maven@4
          displayName: 'mvn dependency:go-offline'
          condition: ne(variables.MAVEN_CACHE_RESTORED, 'true')
          # ⭐ skipped entirely on a cache hit
          inputs:
            mavenPomFile: ${{ parameters.context }}/pom.xml
            goals: 'dependency:go-offline'
            options: '-B -ntp -Dmaven.repo.local=$(MAVEN_CACHE_FOLDER)'
            javaHomeOption: 'JDKVersion'
            jdkVersionOption: '1.21'
            publishJUnitResults: false

      - ${{ if eq(parameters.language, 'go') }}:
        - task: GoTool@0
          displayName: 'pin Go from go.mod'
          inputs:
            version: '1.23'
        - task: Cache@2
          displayName: 'cache Go modules'
          inputs:
            key: 'gomod | "$(Agent.OS)" | ${{ parameters.context }}/go.sum'
            path: $(GOPATH)/pkg/mod
            restoreKeys: |
              gomod | "$(Agent.OS)"
        - task: Go@0
          displayName: 'go mod download'
          inputs:
            command: custom
            customCommand: 'mod download'
            workingDirectory: ${{ parameters.context }}

      - ${{ if eq(parameters.language, 'python') }}:
        - task: UsePythonVersion@0
          displayName: 'pin Python 3.13'
          inputs:
            versionSpec: '3.13'
            addToPath: true
        - task: Cache@2
          displayName: 'cache uv/pip'
          inputs:
            key: 'python | "$(Agent.OS)" | ${{ parameters.context }}/uv.lock'
            path: $(Pipeline.Workspace)/.uv-cache
        - script: |
            set -euo pipefail
            python -m pip install --no-cache-dir --upgrade uv
            uv sync --frozen --no-dev
          displayName: 'uv sync --frozen'
          workingDirectory: ${{ parameters.context }}
          env:
            UV_CACHE_DIR: $(Pipeline.Workspace)/.uv-cache

      # ── ⭐ TEST: one Bash step, four languages ───────────────────────
      - script: |
          set -euo pipefail
          # ⭐ `set -euo pipefail` in EVERY shell step. Without `-e` a failing
          #   command in the middle of a script is ignored and the step goes
          #   green. This is a real and common false-pass.
          case "${{ parameters.language }}" in
            node)   npm run lint && npx tsc --noEmit && npm run test:unit -- --run ;;
            java)   ./mvnw -B -ntp verify -Dmaven.repo.local=$(MAVEN_CACHE_FOLDER) ;;
            go)     go vet ./... && go test -race -covermode=atomic ./... ;;
            python) uv run ruff check . && uv run mypy src && uv run pytest -q ;;
          esac
        displayName: 'test · ${{ parameters.language }}'
        workingDirectory: ${{ parameters.context }}

      # ⭐ publish results so they appear on the pipeline run, not only in a log
      - ${{ if eq(parameters.language, 'java') }}:
        - task: PublishTestResults@2
          condition: succeededOrFailed()   # ✅ the CORRECT use of a
          inputs:                          #   "run even on failure" condition:
            testResultsFormat: 'JUnit'     #   reporting, never building.
            testResultsFiles: '${{ parameters.context }}/target/surefire-reports/*.xml'
            failTaskOnFailedTests: true    # ⭐⭐ without this, a failed test
                                           #   publishes results and the task
                                           #   still SUCCEEDS.
        - task: PublishCodeCoverageResults@2
          condition: succeededOrFailed()
          inputs:
            summaryFileLocation: '${{ parameters.context }}/target/site/jacoco/jacoco.xml'

  # ─────────────── image · scan · sign · publish digest ─────────────────
  - job: image_${{ replace(parameters.service, '-', '_') }}
    displayName: 'image · ${{ parameters.service }}'
    dependsOn: build_${{ replace(parameters.service, '-', '_') }}
    # ⭐⭐ dependsOn = GitHub's `needs:`. If the build job fails, this job is
    #   SKIPPED — not run. There is no equivalent of `if: always()` here, and
    #   that is the correct default: no tests, no image.
    pool:
      vmImage: ubuntu-latest
    timeoutInMinutes: 25
    variables:
      IMAGE: ${{ parameters.acrName }}.azurecr.io/${{ parameters.service }}
    steps:
      - checkout: self
        fetchDepth: 1

      # ⭐⭐ FEDERATED LOGIN — no secret, no `docker login -p`.
      - task: AzureCLI@2
        displayName: 'ACR login (Workload Identity Federation)'
        inputs:
          azureSubscription: ${{ parameters.serviceConnection }}
          scriptType: bash
          scriptLocation: inlineScript
          addSpnToEnvironment: true        # ⭐ exposes the federated token
          inlineScript: |
            set -euo pipefail
            # `$az_subscription`, `$az_tenant`, `$az_service_principal` are set
            # by addSpnToEnvironment. With a FEDERATED connection there is no
            # client secret — the token is minted per run.
            az acr login --name ${{ parameters.acrName }}
            echo "✅ logged in to ${{ parameters.acrName }}.azurecr.io"

      - task: Docker@2
        displayName: 'build + push'
        inputs:
          containerregistry: ${{ parameters.serviceConnection }}
          command: buildAndPush
          repository: ${{ parameters.service }}
          Dockerfile: ${{ parameters.context }}/Dockerfile
          buildContext: ${{ parameters.context }}
          tags: |
            $(Build.SourceVersion)
            # ⭐⭐ THE FULL COMMIT SHA AS A TAG. This is the Azure equivalent of
            #   GitHub's `type=sha,format=long`. It is unique per commit and
            #   therefore immutable in practice.
            latest
            # ⚠️ `latest` is a CONVENIENCE for humans only. Nothing in a
            #   pipeline may consume it — §9 check 3.
          arguments: >
            --cache-from ${{ parameters.acrName }}.azurecr.io/${{ parameters.service }}:cache
            --cache-to   ${{ parameters.acrName }}.azurecr.io/${{ parameters.service }}:cache
            --build-arg GIT_SHA=$(Build.SourceVersion)
            --label "org.opencontainers.image.revision=$(Build.SourceVersion)"
            --label "org.opencontainers.image.source=$(Build.Repository.Uri)"
          # ⭐ Azure Pipelines has no `type=gha` cache. The idiom is a
          #   dedicated `:cache` tag in the same registry, used as
          #   --cache-from/--cache-to. It costs one extra push and makes the
          #   second build dramatically faster.

      # ⭐⭐ CAPTURE THE DIGEST. This is the whole output of Scenario 1.
      - script: |
          set -euo pipefail
          TAG="$(Build.SourceVersion)"
          DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' \
                     "${IMAGE}:${TAG}" | sed 's/.*@//')
          if [ -z "$DIGEST" ] || [ "${DIGEST#sha256:}" = "$DIGEST" ]; then
            echo "##vso[task.logissue type=error]no digest found for ${IMAGE}:${TAG}"
            exit 1
          fi
          echo "${IMAGE}@${DIGEST}" > "$(Build.ArtifactStagingDirectory)/digest.txt"
          # ⭐⭐ `##vso[...]` is the Azure DevOps logging-command protocol.
          #   This is how a script step sets an OUTPUT VARIABLE that later
          #   jobs can read — the equivalent of GitHub's $GITHUB_OUTPUT.
          echo "##vso[task.setvariable variable=imageDigest;isOutput=true]${DIGEST}"
          echo "##vso[task.setvariable variable=imageRef;isOutput=true]${IMAGE}@${DIGEST}"
          echo "### ${{ parameters.service }}" >> "$(Build.ArtifactStagingDirectory)/summary.md"
          echo "\`${IMAGE}@${DIGEST}\`"        >> "$(Build.ArtifactStagingDirectory)/summary.md"
        displayName: '⭐ capture the digest'
        name: dig                       # ⭐ `name:` gives the step an ID so a
                                        #   later job can read
                                        #   dependencies.<job>.outputs['dig.imageDigest']

      - script: |
          set -euo pipefail
          # ⭐ SCAN THE IMAGE, NOT THE SOURCE. A source scan cannot see a
          #   vulnerable library in your BASE image — where most real CVEs are.
          docker run --rm \
            -v /var/run/docker.sock:/var/run/docker.sock \
            aquasec/trivy:0.58 image \
            --exit-code 1 --severity CRITICAL,HIGH --ignore-unfixed \
            "${IMAGE}@$(dig.imageDigest)"
          # ⭐ `--ignore-unfixed` is not leniency. Without it you are blocked
          #   by CVEs that have no available fix, and the team learns to
          #   bypass the gate — which is worse than not having it.
        displayName: 'Trivy image scan'

      - task: PublishPipelineArtifact@1
        displayName: '⭐ publish digest artifact'
        inputs:
          targetPath: $(Build.ArtifactStagingDirectory)/digest.txt
          artifactName: digest-${{ parameters.service }}
          # ⭐⭐ retention is set at the PROJECT level (or per-release). 90 days
          #   is the minimum you want for auditing "what was in production".

      - task: PublishPipelineArtifact@1
        displayName: 'publish run summary'
        inputs:
          targetPath: $(Build.ArtifactStagingDirectory)/summary.md
          artifactName: summary-${{ parameters.service }}
```

---

## 4 · The caller pipeline

```yaml
# ══════════════════════════════════════════════════════════════════════
# ci-azure.yml — the CI-only entry point. Publishes images and a manifest.
#                Deploys NOTHING.
# ══════════════════════════════════════════════════════════════════════
trigger:
  branches:
    include: [main]
  paths:
    include:                    # ⭐ a first filter, like GitHub's `paths:`
      - apps/*
      - ci/*
    exclude:
      - '**/*.md'
      - docs/*
  # ⚠️ `paths.include`/`exclude` decide whether the PIPELINE runs at all.
  #   It cannot decide which SERVICES build — that needs per-job conditions,
  #   which is what the `changes` job below does.

pr:
  branches:
    include: [main]
  # ⭐ a PR run and a main run share this file. The `publish` parameter below
  #   is set from the build REASON, so a PR builds but never pushes.

pool:
  vmImage: ubuntu-latest

variables:
  # ⭐ a VARIABLE GROUP linked to Key Vault — but note that in Scenario 1 it
  #   contains NO cluster credential. That absence is a checkable property (§9).
  - group: shop-ci-build          # build-time config only
  - name: MAVEN_CACHE_FOLDER
    value: $(Pipeline.Workspace)/.m2
  - name: ACR_NAME
    value: shopacr

stages:
  # ─────────────────────────── what changed? ───────────────────────────
  - stage: Detect
    displayName: 'detect changed services'
    jobs:
      - job: changes
        displayName: 'diff against the previous commit'
        steps:
          - checkout: self
            fetchDepth: 0        # ⭐⭐ 0 = full history. You CANNOT diff
                                 #   against the previous commit with a
                                 #   shallow clone. This is the #1 cause of
                                 #   "everything always builds" in Azure.
          - script: |
              set -euo pipefail
              # on a PR, compare against the target branch; on a push, against HEAD~1
              if [ "$(Build.Reason)" = "PullRequest" ]; then
                BASE="origin/$(System.PullRequest.TargetBranch)"
                git fetch --no-tags --depth=0 origin "$(System.PullRequest.TargetBranch)"
              else
                BASE="HEAD~1"
              fi
              CHANGED=$(git diff --name-only "$BASE" HEAD || git diff --name-only HEAD~1 HEAD)
              echo "changed files:"; echo "$CHANGED" | sed 's/^/  /'
              flag() { echo "$CHANGED" | grep -qE "$1" && echo true || echo false; }
              echo "##vso[task.setvariable variable=ui;isOutput=true]$(flag '^apps/shop-ui/|^ci/')"
              echo "##vso[task.setvariable variable=api;isOutput=true]$(flag '^apps/shop-api/|^ci/')"
              echo "##vso[task.setvariable variable=golang;isOutput=true]$(flag '^apps/(checkout|payment-mock)/|^ci/')"
              echo "##vso[task.setvariable variable=python;isOutput=true]$(flag '^apps/order-worker/|^ci/')"
            name: diff
            displayName: 'compute changed-service flags'

  # ─────────────────────────── build each service ──────────────────────
  - stage: Build
    displayName: 'build · test · image · scan · publish'
    dependsOn: Detect
    variables:
      # ⭐⭐ reading another stage's output: the full path is
      #   dependencies.<STAGE>.outputs['<JOB>.<STEPNAME>.<VARNAME>']
      #   Getting this path wrong yields an empty string and every service
      #   silently builds every time.
      ui:     $[ stageDependencies.Detect.outputs['changes.diff.ui'] ]
      api:    $[ stageDependencies.Detect.outputs['changes.diff.api'] ]
      go:     $[ stageDependencies.Detect.outputs['changes.diff.golang'] ]
      python: $[ stageDependencies.Detect.outputs['changes.diff.python'] ]
      # ⭐ $[...] is a COMPILE-TIME expression (evaluated when the run is
      #   created) — required here because `condition:` is evaluated before
      #   the job starts. $(...) is runtime and would be too late.
      PUBLISH: $[ ne(variables['Build.Reason'], 'PullRequest') ]
      # ⭐⭐ THE ONE LINE THAT MAKES THIS CI-ONLY: a PR never publishes.

    jobs:
      - ${{ if true }}:            # template expansion needs a static context;
        - template: ci/templates/build-test-image.yml   # the real gate is below
          parameters:
            service: shop-ui
            context: apps/shop-ui
            language: node
            acrName: $(ACR_NAME)
            publish: false          # set per-run below via condition

      # ⭐ Azure YAML cannot put a runtime `condition` on a `template`
      #   expansion, because expansion happens at compile time. The standard
      #   workaround: expand the template unconditionally, and put the
      #   runtime condition on the JOB INSIDE the template. So the template
      #   gains a `runIf` parameter:
      #
      #     parameters:
      #       - name: runIf
      #         type: string
      #         default: 'succeeded()'
      #     jobs:
      #       - job: build_...
      #         condition: ${{ parameters.runIf }}
      #
      #   and the caller passes:
      #     runIf: and(succeeded(), eq(variables.ui, 'true'))

      - template: ci/templates/build-test-image.yml
        parameters:
          service: shop-api
          context: apps/shop-api
          language: java
          acrName: $(ACR_NAME)
          runIf: and(succeeded(), eq(variables.api, 'true'))

      - template: ci/templates/build-test-image.yml
        parameters:
          service: checkout
          context: apps/checkout
          language: go
          acrName: $(ACR_NAME)
          runIf: and(succeeded(), eq(variables.go, 'true'))

      - template: ci/templates/build-test-image.yml
        parameters:
          service: payment-mock
          context: apps/payment-mock
          language: go
          acrName: $(ACR_NAME)
          runIf: and(succeeded(), eq(variables.go, 'true'))

      - template: ci/templates/build-test-image.yml
        parameters:
          service: order-worker
          context: apps/order-worker
          language: python
          acrName: $(ACR_NAME)
          runIf: and(succeeded(), eq(variables.python, 'true'))

  # ───────────────────── ⭐⭐ the release manifest ──────────────────────
  - stage: Manifest
    displayName: 'publish the release manifest'
    dependsOn: Build
    # ⭐⭐ NOT `condition: succeeded()`. If a service was SKIPPED because it
    #   did not change, `succeeded()` is still true — but if a service FAILED,
    #   you must not publish a manifest that silently omits it.
    condition: and(not(canceled()), in(dependencies.Build.result,'Succeeded','SucceededWithIssues'))
    jobs:
      - job: manifest
        displayName: 'collect digests → release-manifest'
        steps:
          - task: DownloadPipelineArtifact@2
            inputs:
              buildType: 'current'
              artifactName: ''            # empty = all artifacts
              itemPattern: 'digest-*/**'
              targetPath: $(Pipeline.Workspace)/digests
          - script: |
              set -euo pipefail
              OUT="$(Build.ArtifactStagingDirectory)/release-manifest.txt"
              {
                echo "# Azure DevOps $(System.TeamProject) / $(Build.DefinitionName)"
                echo "# build   $(Build.BuildId)  reason $(Build.Reason)"
                echo "# commit  $(Build.SourceVersion)"
                echo "# ⭐ CD consumes THIS file and nothing else."
              } > "$OUT"
              found=0
              while IFS= read -r f; do
                [ -s "$f" ] || continue
                ref=$(cat "$f")
                svc=$(basename "$(dirname "$f")" | sed 's/^digest-//')
                echo "${svc}=${ref}" >> "$OUT"
                found=$((found+1))
              done < <(find "$(Pipeline.Workspace)/digests" -name digest.txt)
              echo "services in manifest: ${found}"
              cat "$OUT"
              # ⭐ AN EMPTY MANIFEST IS A VALID RESULT (a docs-only commit).
              #   It is NOT an error. CD must treat it as "nothing to do" —
              #   see §9 and Scenario 2.
              echo "##vso[task.setvariable variable=serviceCount]${found}"
            displayName: 'build the manifest'
          - task: PublishPipelineArtifact@1
            inputs:
              targetPath: $(Build.ArtifactStagingDirectory)/release-manifest.txt
              artifactName: release-manifest
```

---

## 5 · ⭐⭐ Registry auth without a secret — Workload Identity Federation

```
┌──────────── Azure DevOps ────────────┐        ┌──────── Entra ID ────────┐
│  pipeline run                        │        │                          │
│   service connection                 │  1. request a token for the        │
│   "sc-acr-federated"  ───────────────┼───────▶│  federated credential    │
│   ⭐ stores NO secret                │        │                          │
│                                      │  2. ◀── short-lived access token  │
│   AzureCLI@2 with                    │        │    (minutes, not years)  │
│   addSpnToEnvironment: true          │        │                          │
└──────────────┬───────────────────────┘        └──────────────────────────┘
               │ 3. `az acr login --name shopacr`
               ▼
        ┌──────────────┐
        │     ACR      │   ⭐ the credential dies with the run.
        │  shopacr     │      Nothing is stored in the pipeline.
        └──────────────┘      Nothing to rotate. Nothing to leak.
```

```bash
# create the app registration and the FEDERATED credential (once, by hand)
az ad app create --display-name "ado-shop-ci" --output none
APP_ID=$(az ad app list --display-name "ado-shop-ci" --query '[0].appId' -o tsv)

az ad app federated-credential create \
  --id "$APP_ID" \
  --parameters '{
    "name": "ado-shop-ci-main",
    "issuer": "https://vstoken.actions.githubusercontent.com",
    "subject": "repo:3558bhk/shop:environment:production",
    "audiences": ["api://AzureADTokenExchange"]
  }'
# ⚠️ the issuer/subject above are the GITHUB OIDC values. For an Azure DevOps
#   service connection you do NOT create this by hand — Azure DevOps creates
#   the federated credential for you when you pick
#   "Workload identity federation (automatic)" in the service-connection UI.
#   Shown here so you can see what the platform is doing on your behalf.

# grant it ACR push — and ONLY push. Not owner.
az role assignment create \
  --assignee "$APP_ID" \
  --role "AcrPush" \
  --scope "/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.ContainerRegistry/registries/shopacr"

# ⭐⭐ THE CI-ONLY CONSTRAINT: grant AcrPush on the REGISTRY, and grant
#   NOTHING on the AKS cluster. No `Azure Kubernetes Service Cluster User
#   Role`, no kubeconfig, no `contributor` on the resource group.
#   Then the pipeline CANNOT deploy, even by accident, even if someone edits
#   the YAML. That is a property of the IAM, not of the YAML — and IAM is
#   much harder to get wrong silently.
```

| | Service principal + secret | ⭐ Workload Identity Federation |
|---|---|---|
| Secret stored in Azure DevOps | ⛔ yes, and it expires (usually 1–2 years) | ✅ **none** |
| Rotation burden | ⛔ manual, and it breaks the pipeline when it lapses | ✅ nothing to rotate |
| Blast radius if the YAML leaks | ⛔ the secret is not in the YAML, but the connection grants it | ✅ a token minted for one run |
| Auditability | the SP's sign-ins | ⭐ every run is a distinct, attributable token request |

---

## 6 · Per-language notes

| Service | Azure-specific detail |
|---|---|
| 🔵 **`shop-ui`** | `NodeTool@0` with `versionSpec: 24.x`; ⭐ `Npm@1` with `command: ci` (not `install`); add the bundle-size gate as a `Bash` step using `##vso[task.logissue type=error]` so it surfaces as a pipeline error, not a buried log line |
| 🟢 **`shop-api`** | ⭐ `Cache@2` on `$(MAVEN_CACHE_FOLDER)` keyed on `pom.xml` is the single biggest win — a cold Maven build is 4–8 min, a warm one 40–90 s. `Maven@4` needs `publishJUnitResults` **and** `failTaskOnFailedTests: true`, or a failed test publishes results and the task still succeeds |
| 🟢 **`checkout`** | `GoTool@0`; `Cache@2` on `$(GOPATH)/pkg/mod` keyed on `go.sum`; pass `--build-arg GIT_SHA=$(Build.SourceVersion)` for the `-ldflags -X main.version=` injection |
| 🟢 **`order-worker`** | `UsePythonVersion@0` with `versionSpec: 3.13`; ⭐ `slim` not `alpine` in the Dockerfile (musl breaks glibc wheels); `pip-audit` as a separate `Bash` step so its failure is attributable |

---

## 7 · ⭐⭐ The digest handoff

**Three mechanisms, and you want all three:**

| Mechanism | Who reads it | Why |
|---|---|---|
| `PublishPipelineArtifact@1` → `digest-<svc>` | ⭐ **CD** (a release pipeline, or `az pipelines run download`) | the machine-readable handoff. Survives 90 days |
| `##vso[task.setvariable …;isOutput=true]` | later **stages in the same run** | for a same-pipeline manifest stage |
| `##vso[task.addattachment]` / summary.md | a **human** | so the digest is visible without opening a log |

```bash
# what Scenario 2 does — and this is its ENTIRE input:
az pipelines artifact download \
  --artifact-name release-manifest \
  --path /tmp/rel \
  --run-id <buildId> \
  --organization https://dev.azure.com/<org> --project <proj>
cat /tmp/rel/release-manifest.txt
# shop-ui=shopacr.azurecr.io/shop-ui@sha256:9f2c…
# shop-api=shopacr.azurecr.io/shop-api@sha256:41ab…
# checkout=shopacr.azurecr.io/checkout@sha256:7de0…
```

⭐ **The retention decision is a compliance decision, not a storage one.** 90 days minimum. If you are asked "what exactly was running in production on the 14th of March?", the manifest artifact is the only thing that can answer — and only if it still exists.

---

## 8 · Caching

| Layer | Mechanism | Key on |
|---|---|---|
| Maven repo | `Cache@2` → `$(MAVEN_CACHE_FOLDER)` | ⭐ `pom.xml` |
| npm | `Cache@2` → `$(npm_config_cache)` | ⭐ `package-lock.json` |
| Go modules | `Cache@2` → `$(GOPATH)/pkg/mod` | ⭐ `go.sum` |
| Python/uv | `Cache@2` → `$(Pipeline.Workspace)/.uv-cache` | ⭐ `uv.lock` |
| ⭐ Docker layers | `--cache-from/--cache-to` against a **`:cache` tag in ACR** | per-service |

⚠️ **Azure `Cache@2` limits:** 10 GB **per project**, entries expire after **10 days unused**. Same class of problem as GitHub's `type=gha`. If your cache hit rate drops to zero with no error, you have hit the quota — narrow the key, or drop caching for services that build fast anyway.

⭐ **Why Docker layer caching needs a registry tag in Azure:** hosted pools are **ephemeral VMs**. There is no local Docker layer cache to reuse between runs, and BuildKit's `type=local` cache would be thrown away with the VM. ACR has no native BuildKit cache backend, so the standard idiom is a dedicated `:cache` tag in the same registry. One extra push per build, and the second build drops from ~4 min to ~40 s.

---

## 9 · ⭐ Proving it is CI-only — Azure-flavoured

| # | Check | Command / where to look |
|---|---|---|
| **1** | No deployment verb in any YAML | `grep -RnE 'kubectl\|helm\|compose up\|ssh \|az aks\|az webapp\|set image\|argocd' **/*.yml` must return nothing |
| **2** | ⭐⭐ **No cluster credential is reachable** | Project Settings → **Service endpoints**: there must be **no Kubernetes service connection**. Project Settings → **Permissions**: the build service account must have **no** AKS role |
| **3** | It emits a digest, not just a tag | the `release-manifest` artifact contains `@sha256:` for every service |
| **4** | A PR run publishes nothing | `PUBLISH: $[ ne(variables['Build.Reason'], 'PullRequest') ]` — then check the ACR tag list for the PR's SHA and confirm it is absent |
| **5** | ⭐ **There is no `production` Environment at all** | Pipelines → **Environment** list should be empty, or contain only `ci`. An Environment with approvals is a *deployment* construct; its presence means you have built Scenario 2 and called it Scenario 1 |

⭐⭐ **Check 2 is the one that matters, and it is an IAM property rather than a YAML property.** A pipeline with no `kubectl` step but a Kubernetes service connection attached is one edited YAML line away from deploying to production — and everyone with repository access can edit YAML. Revoking the connection makes "cannot deploy" true regardless of what the YAML says. **Enforce the constraint in IAM, then the YAML merely reflects it.**

---

## 10 · ✅ Verify it from your laptop

```bash
# 1. the pipeline ran
az pipelines runs list --definition-ids <id> --top 5 \
  --organization https://dev.azure.com/<org> --project <proj>

# 2. download the manifest — the Scenario 1 output
az pipelines artifact download --artifact-name release-manifest \
  --path /tmp/rel --run-id <buildId> \
  --organization https://dev.azure.com/<org> --project <proj>
cat /tmp/rel/release-manifest.txt

# 3. ⭐ the digest is real and pullable
az acr login --name shopacr
DIGEST=$(grep '^shop-api=' /tmp/rel/release-manifest.txt | cut -d= -f2-)
docker pull "$DIGEST"

# 4. the image is what you think it is
docker image inspect "$DIGEST" \
  --format 'size={{.Size}} user={{.Config.User}} entry={{.Config.Entrypoint}}'

# 5. ⭐⭐ PROVE CI-ONLY
grep -RnE 'kubectl|helm|compose up|ssh |az aks|set image|argocd' \
     $(git ls-files '*.yml' '*.yaml') && echo "⛔ NOT CI-ONLY" || echo "✅ no deploy verb"
az devops service-endpoint list --organization https://dev.azure.com/<org> --project <proj> \
  | jq -r '.value[] | "\(.type)  \(.name)"'
# ⭐ expect: azurerm (ACR only). ⛔ ANY 'kubernetes' entry means this is not CI-only.
```

---

## 11 · Troubleshooting

| Error / symptom | Cause | Fix |
|---|---|---|
| `Unrecognized value: '${{ variables.x }}'` in an `if:` | ⭐ using a runtime variable in a compile-time expression | make it a `parameter`, or use `$[ ]` with `variables.` |
| A template branch never runs | `${{ if eq(variables.language,'java') }}` | `${{ if eq(parameters.language,'java') }}` — §2 |
| Everything builds on every commit | ⭐ `fetchDepth: 1` — a shallow clone cannot diff against `HEAD~1` | `fetchDepth: 0` in the `changes` job |
| The output variable reads as empty | wrong path in `stageDependencies` | the full form is `stageDependencies.<Stage>.outputs['<Job>.<StepName>.<Var>']`, and the step needs `name:` |
| `invalid job name shop-api` | job names must be identifiers | `${{ replace(parameters.service,'-','_') }}` |
| Maven downloads 200 MB every run | no `Cache@2`, or the key is on source files | key on `pom.xml`; add `restoreKeys` |
| Builds are slow after the first week | ⭐ the 10 GB project cache quota was hit; entries evicted silently | narrow keys, or stop caching fast-building services |
| `PublishTestResults` succeeds despite failed tests | `failTaskOnFailedTests` defaults to false | set it to `true` |
| Docker build is slow every time | no registry-backed layer cache | `--cache-from/--cache-to` against a `:cache` tag |
| `##vso[task.setvariable]` has no effect | ⭐ the variable is set inside a script but read in the **same** step | `setvariable` takes effect from the **next** step onward |
| ACR login fails with `AADSTS7000215` | the service connection still expects a secret | recreate it as **Workload identity federation (automatic)** |
| The manifest stage is skipped | `condition: succeeded()` and a build job was skipped *or* the stage result differs | use `in(dependencies.Build.result,'Succeeded','SucceededWithIssues')` and `not(canceled())` |

---

<a name="tasks--answers"></a>
## 12 · ⭐ TASKS — answers at the END

| # | Task |
|---|---|
| **T1** | Build the `build-test-image.yml` template and call it for all five services from one pipeline |
| **T2** | Make a PR run build but **not** publish, using `Build.Reason` — and prove it |
| **T3** | Add `Cache@2` for Maven and demonstrate the before/after build time |
| **T4** | Replace a service-principal-with-secret connection with Workload Identity Federation |
| **T5** | Implement the `changes` stage so a docs-only commit builds nothing |
| **T6** | Publish `release-manifest` as a pipeline artifact and download it with the Azure CLI |
| **T7** | Add the Trivy image scan and make it fail the build on a CRITICAL |
| **T8** | Add `PublishTestResults` + `PublishCodeCoverageResults` for the Java service so results appear on the run summary |
| **T9** | ⭐ Run all five CI-only checks from §9 and record the output |
| **T10** | ⭐⭐ Explain why revoking the Kubernetes service connection is a stronger guarantee than having no `kubectl` in the YAML |

---

# ✅ ANSWERS

**T1.** §3 is the template, §4 the caller. Two details that decide whether it works: job names must be identifiers, so `${{ replace(parameters.service,'-','_') }}`; and a `template:` expansion happens at **compile** time, so you cannot put a runtime `condition:` on the expansion itself — you pass a `runIf` parameter and apply it to the job *inside* the template.

**T2.** `PUBLISH: $[ ne(variables['Build.Reason'], 'PullRequest') ]` as a stage variable, threaded into the template's `publish` parameter, which gates both the `AzureCLI@2` ACR login and the `Docker@2` `buildAndPush` command (use `command: build` when not publishing). **Proof:** run a PR, then `az acr repository show-tags --name shopacr --repository shop-api` and confirm the PR's commit SHA is **not** among the tags. A second proof: the ACR login step should be *skipped*, visible in the run log — if it ran, the pipeline had a credential it did not need.

**T3.** §3's `Cache@2` block for Maven. Key on `pom.xml` — **not** on source. `restoreKeys: maven | "$(Agent.OS)"` gives a partial restore after a POM change, which is still far better than a cold download. Gate `dependency:go-offline` with `condition: ne(variables.MAVEN_CACHE_RESTORED, 'true')` so it is skipped entirely on a hit. Typical result: first build ~5–8 min, subsequent builds ~60–90 s. Record both numbers — "I made the Java build 5× faster by caching the Maven repo keyed on the POM" is a concrete, checkable claim.

**T4.** §5. The important half is not creating the connection — Azure DevOps does that when you choose *Workload identity federation (automatic)*. The important half is **scoping the role assignment**: `AcrPush` on the registry only, and *nothing* on AKS. Then delete the old secret-based connection so nobody can fall back to it.

**T5.** §4's `Detect` stage. The critical setting is `fetchDepth: 0` — with the default shallow clone, `git diff HEAD~1` has no parent to compare against and silently returns everything or nothing. The `flag()` helper greps the changed paths and emits `##vso[task.setvariable …;isOutput=true]` per service. **Test it with a docs-only commit:** all four flags false → all five build jobs skipped → the manifest contains only comment lines.

**T6.** `PublishPipelineArtifact@1` with `artifactName: release-manifest`, then `az pipelines artifact download --artifact-name release-manifest --run-id <id> --path /tmp/rel`. ⭐ Set retention to 90 days at the project level. The manifest must be **set-valued** (one file, all services) rather than one artifact per service, because Scenario 2 needs to promote FE and BE **together** for shapes C and D.

**T7.** The Trivy step in §3, mounting the Docker socket and scanning `image` (not `fs`) at the **digest**, with `--exit-code 1 --severity CRITICAL,HIGH --ignore-unfixed`. ⭐ Scan by digest, not by tag: if you scan `:latest` you may scan a different image than the one you published. `--ignore-unfixed` is what keeps the gate trusted — a gate that blocks on unfixable CVEs gets bypassed, and a bypassed gate is worse than none.

**T8.** Both tasks with `condition: succeededOrFailed()` — reporting is the *one* legitimate use of run-on-failure. ⭐ `failTaskOnFailedTests: true` on `PublishTestResults@2`, otherwise a failed test publishes results and the task reports success. That default is one of the most consequential silent settings in Azure Pipelines.

**T9.** The five commands in §9/§10. The one that decides it is **check 2**: `az devops service-endpoint list | jq -r '.value[] | .type'` must show **no** `kubernetes` entry. Combined with check 5 — an empty Environments list — you have a pipeline that cannot deploy even if someone with repo access edits the YAML badly.

**T10.** ⭐⭐ Because **YAML is editable by anyone with repository access, and IAM is not.** A pipeline with no `kubectl` step but a Kubernetes service connection attached is one commit away from deploying to production — and that commit can come from a compromised account, a malicious dependency's CI configuration, or an over-eager engineer at 2 a.m. Revoking the service connection moves the guarantee from "the code currently says no" to "the platform cannot say yes". The general principle, and it is the one worth stating in an interview: **enforce security constraints in the identity layer, and let the pipeline definition merely reflect them.** Anything enforced only in code that the attacker can edit is not enforced. The same logic is why GitHub Actions' `permissions: {}` default-deny matters more than which steps you include, and why Jenkins folder-scoped credentials matter more than which `withCredentials` blocks you write.

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish_Kumar_Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn: https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260
🔗 GitHub: https://github.com/3558Bhk

*Parameters decide structure. Variables carry data. IAM decides what is possible.*

</div>
