# 🔵 SCENARIO 3 · FRONTEND ONLY — CI + CD END TO END
### `shop-ui` (React 19 / Vite / nginx) and the static site (Docker P2): one image, runtime config, bundle gates, and the easiest full path in the estate.

> **Apps:** `shop-ui` — Docker P8 · K8s P8 · and the FE half of P10/P11/P12 · plus `static-site` (Docker P2).
> **Stack:** React 19.3 · Vite · Vitest · Node 24 LTS · `nginx:1.29-alpine` · port 80.
> **Verdict up front:** ⭐ **this is the shape to build your first CI+CD pipeline for.** No state, no schema, no warm-up, rollback in seconds — and the highest change frequency, so the payoff arrives fastest.

---

## 📇 Contents

| § | What |
|---|---|
| [1](#1---why-the-frontend-is-the-easiest-full-path) | ⭐ Why the frontend is the easiest full path — and the one trap |
| [2](#2---the-dockerfile--runtime-config) | ⭐⭐ The Dockerfile — runtime config, so **one image** serves every environment |
| [3](#3--the-two-frontend-only-ci-gates) | The two frontend-only CI gates — bundle size and Lighthouse |
| [4](#4--ci--github-actions) | CI — GitHub Actions, full file |
| [5](#5--ci--azure-devops) | CI — Azure DevOps, full file |
| [6](#6--ci--jenkins) | CI — Jenkins, full file |
| [7](#7--cd--the-three-tools-and-why-it-is-short) | CD — the three tools, and why it is short |
| [8](#8---the-cache-header-deploy-check) | ⭐⭐ The cache-header deploy check — the incident that only frontends have |
| [9](#9--static-site-p2--the-minimal-version) | `static-site` (P2) — the minimal version of everything here |
| [10](#10---case-1-or--case-2) | 🔒 Case 1 or 🤖 Case 2 — and why the answer is usually 🤖 |
| [11](#11--️-run-it-end-to-end--the-acceptance-checks) | ▶️ Run it end to end — the acceptance checks |
| [12](#12--troubleshooting) | Troubleshooting |
| [13](#13---tasks--answers-at-the-end) | Tasks and answers — **answers at the END** |

---

## 1 · ⭐ Why the frontend is the easiest full path

| Property | Consequence |
|---|---|
| ⭐ **The artifact is static files** | no process to warm up, no connection pool, no JIT |
| **No schema** | ⭐ no migration → prerequisite 5 is satisfied by definition |
| **No state** | any pod can serve any request; a partial fleet is not inconsistent |
| **Rollback is trivial** | re-point at the previous digest; old pods serve instantly |
| **Build is fast** (30–90 s) | fine on every push to every branch |
| **Runtime deps: none** (nginx) | the smallest attack surface and image in the estate |
| ⭐ **Highest change frequency** | so automating it pays back fastest |

**The one trap — and it is a big one:**

```
⛔ BUILD-TIME CONFIG.  Vite INLINES `import.meta.env.VITE_*` into the
   emitted JavaScript as string literals. Build once per environment and
   the artifact you tested in staging is NOT the artifact you ship to
   production — different bytes, different digest.

   ⭐ That breaks the digest contract silently: every pipeline is green,
     everything works, and you have simply lost the guarantee.

✅ RUNTIME CONFIG.  One image; an entrypoint script writes /config.js from
   environment variables at container start; the browser fetches it before
   the bundle loads.
```

Everything in §2 exists to make that one sentence true.

---

## 2 · ⭐⭐ The Dockerfile — runtime config

### 2.1 ⛔ The wrong version

```dockerfile
FROM node:24-alpine AS build
ARG VITE_API_URL                       # ⚠️ baked in at BUILD time
ENV VITE_API_URL=$VITE_API_URL
WORKDIR /app
COPY . .
RUN npm ci && npm run build            # ⭐ Vite inlines it into the JS
FROM nginx:1.29-alpine
COPY --from=build /app/dist /usr/share/nginx/html
```

**Cost:** one image per environment, a broken digest contract, and a staging build that proves nothing about the production artifact.

### 2.2 ✅ The right version

`apps/shop-ui/Dockerfile`

```dockerfile
# ═══════════════════════════════════════════════════════════════════════
#  WHAT : multi-stage build for shop-ui. ONE image for every environment.
#  WHY  : config is injected at RUNTIME (entrypoint → /config.js), so the
#         bytes published by CI are the bytes running in production.
#         ⭐ That is what makes the digest contract mean anything.
#  TARGET: nginx:1.29-alpine · port 80 · ~50 MB
# ═══════════════════════════════════════════════════════════════════════

# ── STAGE 1 · dependencies only (the cacheable layer) ──────────────────
FROM node:24-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
# ⭐ `npm ci` — never `npm install` in CI. `ci` honours the lockfile exactly
#   and fails if package.json and the lock disagree. `install` can silently
#   resolve something new, which breaks reproducibility.
RUN --mount=type=cache,target=/root/.npm npm ci

# ── STAGE 2 · build ────────────────────────────────────────────────────
FROM node:24-alpine AS build
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
# ⭐⭐ NO VITE_API_URL HERE. That is the whole point.
RUN npm run build
# ⭐ fail the build if a secret leaked into the bundle
RUN ! grep -rqE 'AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----' dist/ \
    || { echo "⛔ a secret is embedded in the bundle"; exit 1; }

# ── STAGE 3 · runtime ──────────────────────────────────────────────────
FROM nginx:1.29-alpine AS runtime
# ⭐ pin the base by DIGEST for full reproducibility
#    FROM nginx:1.29-alpine@sha256:…
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
# ⭐⭐ the entrypoint hook: nginx's official image runs every executable in
#   /docker-entrypoint.d/ at container start, BEFORE nginx starts.
COPY docker-entrypoint.d/40-inject-config.sh /docker-entrypoint.d/40-inject-config.sh
RUN chmod +x /docker-entrypoint.d/40-inject-config.sh
EXPOSE 80
# ⭐ run as non-root — nginx-unprivileged listens on 8080; if you keep 80,
#   at least drop the capabilities
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://localhost:80/ >/dev/null || exit 1
```

`apps/shop-ui/docker-entrypoint.d/40-inject-config.sh`

```bash
#!/bin/sh
# ═══════════════════════════════════════════════════════════════════════
#  WHAT : writes /config.js from environment variables at container start.
#  WHY  : so ONE image serves dev, staging and production. The browser
#         fetches /config.js before the bundle, so config is runtime data.
# ═══════════════════════════════════════════════════════════════════════
set -eu

: "${API_URL:=http://localhost:8080}"      # ⭐ defaults keep local dev working
: "${APP_ENV:=dev}"
: "${GIT_SHA:=unknown}"

# ⭐⭐ ESCAPE THE VALUES. An unescaped quote in an env var breaks the JS —
#   and an attacker-controlled env var becomes XSS.
esc() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e "s/'/\\\\'/g" -e 's|</|\\<\\/|g'; }

cat > /usr/share/nginx/html/config.js <<EOF
window.__APP_CONFIG__ = {
  API_URL: "$(esc "$API_URL")",
  ENV:     "$(esc "$APP_ENV")",
  BUILD:   "$(esc "$GIT_SHA")",
  BUILT_AT: "$(date -u +%FT%TZ)"
};
EOF
echo "✅ injected API_URL=$API_URL ENV=$APP_ENV BUILD=$GIT_SHA"
```

`apps/shop-ui/index.html`

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <!-- ⭐⭐ BEFORE the bundle, so the config exists when the app runs -->
    <script src="/config.js"></script>
    <script type="module" src="/src/main.tsx"></script>
  </head>
  <body><div id="root"></div></body>
</html>
```

`apps/shop-ui/src/config.ts` — ⭐ the ONE place the app reads config

```ts
type AppConfig = { apiUrl: string; env: string; build: string };

const runtime = (window as unknown as { __APP_CONFIG__?: Partial<AppConfig> }).__APP_CONFIG__;

export const config: AppConfig = {
  // ⭐ runtime config wins; the build-time value is the LOCAL DEV fallback
  apiUrl: runtime?.apiUrl ?? import.meta.env.VITE_API_URL ?? 'http://localhost:8080',
  env:    runtime?.env    ?? 'dev',
  build:  runtime?.build  ?? 'local',
};

// ⭐ fail loudly rather than calling the wrong API silently
if (config.env === 'production' && /localhost|127\.0\.0\.1/.test(config.apiUrl)) {
  console.error('⛔ production build pointed at a localhost API_URL — check config.js');
}
```

### 2.3 ⭐ The proof that it works

```bash
# build ONE image
docker build -t shop-ui:test apps/shop-ui

# run it twice with different config
docker run -d --name a -p 8081:80 -e API_URL=https://api.dev.shop shop-ui:test
docker run -d --name b -p 8082:80 -e API_URL=https://api.shop     shop-ui:test
sleep 2

curl -s localhost:8081/config.js     # API_URL: "https://api.dev.shop"
curl -s localhost:8082/config.js     # API_URL: "https://api.shop"

# ⭐⭐ THE SAME IMAGE ID. That is the entire point.
docker image inspect shop-ui:test --format '{{.Id}}'
# sha256:<one value> — used by BOTH containers
```

**If those two `config.js` files differ and the image ID is the same, you have one artifact for all environments** — and the digest contract from CI to production is intact.

---

## 3 · The two frontend-only CI gates

```bash
# ── GATE 1 · BUNDLE SIZE ───────────────────────────────────────────────
# ⭐ WHY: a frontend regression is usually a SIZE regression, and unit tests
#   cannot see it. Somebody adds a 400 KB date library; every test passes.
SIZE=$(du -sk dist | cut -f1)
BUDGET=450                       # KiB — set from TODAY's value, ratchet DOWN
echo "dist = ${SIZE} KiB (budget ${BUDGET})"
[ "$SIZE" -le "$BUDGET" ] || { echo "⛔ bundle over budget"; exit 1; }

# ⭐ BETTER: per-chunk budgets. A 50 KB regression in the CRITICAL path can
#   hide inside a flat total, and it is the one that hurts.
npx vite-bundle-visualizer --output dist/stats.html || true
jq -e '.[] | select(.isEntry) | .size < 307200' dist/bundle-report.json

# ── GATE 2 · LIGHTHOUSE ────────────────────────────────────────────────
npm run preview -- --port 4173 &
sleep 5
npx @lhci/cli autorun \
  --collect.url=http://localhost:4173 \
  --collect.numberOfRuns=3 \                 # ⭐⭐ 3 runs, take the MEDIAN
  --assert.preset=lighthouse:no-pwa \
  --assert.assertions='{
    "categories:performance":   ["error", {"minScore": 0.9}],
    "categories:accessibility": ["error", {"minScore": 0.95}],
    "categories:best-practices":["warn",  {"minScore": 0.9}],
    "resource-summary:script:size": ["error", {"maxNumericValue": 307200}]
  }'
# ⭐ WHY numberOfRuns=3: a single Lighthouse run on a shared CI runner has
#   ±10 points of noise. Gating on one run produces flaky failures, and a
#   flaky gate gets disabled — which is worse than no gate.
```

| Gate | ⭐ Failure mode it catches |
|---|---|
| Unit (Vitest) | logic regressions |
| ⭐ Bundle size | a new dependency nobody noticed |
| ⭐ Lighthouse performance | a render-blocking script, an unoptimised image |
| ⭐ Lighthouse accessibility | a missing label, a contrast regression |
| Secret-in-bundle grep | ⭐ an env var that should not have been public |
| Trivy on the **image** | an nginx CVE — ⭐ not `npm audit`, which misses base layers |

---

## 4 · CI — GitHub Actions

`.github/workflows/ci-shop-ui.yml`

```yaml
# ═══════════════════════════════════════════════════════════════════════
#  WHAT : CI for shop-ui — test, bundle gate, Lighthouse, image, sign, push.
#  WHY  : it PUBLISHES a digest and CANNOT deploy (no cluster secret here).
# ═══════════════════════════════════════════════════════════════════════
name: CI · shop-ui
on:
  push:         { paths: ['apps/shop-ui/**'], branches: [main] }
  pull_request: { paths: ['apps/shop-ui/**'], branches: [main] }

concurrency:
  group: ci-shop-ui-${{ github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}

permissions: { contents: read }
env: { APP: apps/shop-ui, IMAGE: ghcr.io/${{ github.repository_owner }}/shop-ui }

jobs:
  test:
    name: 1 · Test and gates
    runs-on: ubuntu-latest
    permissions: { contents: read }
    defaults: { run: { working-directory: apps/shop-ui } }
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-node@v6
        with: { node-version: '24', cache: npm, cache-dependency-path: apps/shop-ui/package-lock.json }
      - run: npm ci                          # ⭐ never `npm install` in CI

      - name: Lint + typecheck
        run: |
          npm run lint
          npm run typecheck                   # ⭐ tsc --noEmit

      - name: Unit tests + coverage gate
        run: npm run test:ci -- --coverage.thresholds.lines=80

      - name: Build
        run: npm run build                    # ⭐ NO VITE_API_URL — §2

      - name: ⭐ Bundle-size gate
        run: |
          set -euo pipefail
          SIZE=$(du -sk dist | cut -f1); BUDGET=450
          echo "dist = ${SIZE} KiB (budget ${BUDGET})"
          [ "$SIZE" -le "$BUDGET" ] || { echo "::error::bundle over budget"; exit 1; }

      - name: ⭐ Secret-in-bundle gate
        run: |
          ! grep -rqE 'AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----' dist/ \
            || { echo "::error::a secret is embedded in the bundle"; exit 1; }

      - name: ⭐ Lighthouse (3 runs, median)
        run: |
          npm run preview -- --port 4173 &
          sleep 5
          npx @lhci/cli autorun --collect.url=http://localhost:4173 \
            --collect.numberOfRuns=3 --assert.preset=lighthouse:no-pwa \
            --assert.assertions='{"categories:performance":["error",{"minScore":0.9}],
                                  "categories:accessibility":["error",{"minScore":0.95}]}'
      - uses: actions/upload-artifact@v4
        if: always()
        with: { name: lighthouse, path: apps/shop-ui/.lighthouseci/ }

  image:
    name: 2 · Build, sign, publish
    needs: test
    runs-on: ubuntu-latest
    permissions: { contents: read, packages: write, id-token: write }
    steps:
      - uses: actions/checkout@v7
      - uses: docker/setup-buildx-action@v3
      - id: flags
        run: |
          # ⭐⭐ PUSH only on main. NEVER on a pull_request from a fork.
          [ "${{ github.event_name }}" = "push" ] && [ "${{ github.ref }}" = "refs/heads/main" ] \
            && echo "push=true" >> "$GITHUB_OUTPUT" || echo "push=false" >> "$GITHUB_OUTPUT"
      - uses: docker/login-action@v3
        if: steps.flags.outputs.push == 'true'
        with: { registry: ghcr.io, username: '${{ github.actor }}', password: '${{ secrets.GITHUB_TOKEN }}' }
      - uses: docker/build-push-action@v6
        id: build
        with:
          context: apps/shop-ui
          push: ${{ steps.flags.outputs.push == 'true' }}
          tags: ghcr.io/${{ github.repository_owner }}/shop-ui:sha-${{ github.sha }}
          cache-from: type=gha,scope=shop-ui
          cache-to: type=gha,scope=shop-ui,mode=max
          provenance: mode=max
          sbom: true
      - uses: aquasecurity/trivy-action@0.33.1
        if: steps.flags.outputs.push == 'true'
        with:
          image-ref: ${{ env.IMAGE }}@${{ steps.build.outputs.digest }}
          exit-code: '1'
          severity: CRITICAL,HIGH
          ignore-unfixed: true              # ⭐ no fix = not actionable
      - uses: sigstore/cosign-installer@v4
      - if: steps.flags.outputs.push == 'true'
        env: { COSIGN_YES: 'true' }
        run: cosign sign --yes "${{ env.IMAGE }}@${{ steps.build.outputs.digest }}"
      - name: ⭐⭐ Emit the digest
        if: steps.flags.outputs.push == 'true'
        run: |
          mkdir -p out
          printf '%s@%s\n' "${{ env.IMAGE }}" "${{ steps.build.outputs.digest }}" > out/digest.txt
          cat out/digest.txt
      - uses: actions/upload-artifact@v4
        if: steps.flags.outputs.push == 'true'
        with: { name: image-digest, path: out/, retention-days: 90 }
      # ⭐ CI STOPS HERE — no cluster credential, no deploy verb.
```

---

## 5 · CI — Azure DevOps

`pipelines/ci-shop-ui.yml`

```yaml
trigger:
  branches: { include: [main] }
  paths:    { include: ['apps/shop-ui/*'] }
pr:
  branches: { include: [main] }
  paths:    { include: ['apps/shop-ui/*'] }

pool: { vmImage: ubuntu-latest }
variables:
  app:       apps/shop-ui
  acr:       shopacr
  imageName: shopacr.azurecr.io/shop-ui
  ${{ if eq(variables['Build.Reason'], 'PullRequest') }}: { doPush: 'false' }
  ${{ else }}:                                            { doPush: 'true' }

steps:
  - checkout: self
  - task: NodeTool@0
    inputs: { versionSpec: '24.x' }                 # ⭐ pinned
  - task: Cache@2
    inputs:
      key: 'npm | "$(Agent.OS)" | $(Build.SourcesDirectory)/$(app)/package-lock.json'
      path: $(System.DefaultWorkingDirectory)/$(app)/node_modules
      restoreKeys: npm | "$(Agent.OS)"
  - bash: npm ci
    workingDirectory: $(app)
  - bash: npm run lint && npm run typecheck
    workingDirectory: $(app)
  - bash: npm run test:ci -- --coverage.thresholds.lines=80
    workingDirectory: $(app)
  - bash: npm run build                              # ⭐ NO API URL baked in
    workingDirectory: $(app)

  - bash: |
      set -euo pipefail
      SIZE=$(du -sk dist | cut -f1); BUDGET=450
      echo "dist = ${SIZE} KiB (budget ${BUDGET})"
      [ "$SIZE" -le "$BUDGET" ] || { echo "##vso[task.logissue type=error]⛔ over budget"; exit 1; }
      ! grep -rqE 'AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----' dist/ \
        || { echo "##vso[task.logissue type=error]⛔ a secret is in the bundle"; exit 1; }
    workingDirectory: $(app)
    displayName: '⭐ Bundle + secret gates'

  - bash: |
      set -euo pipefail
      npm run preview -- --port 4173 & sleep 5
      npx @lhci/cli autorun --collect.url=http://localhost:4173 \
        --collect.numberOfRuns=3 --assert.preset=lighthouse:no-pwa \
        --assert.assertions='{"categories:performance":["error",{"minScore":0.9}],
                              "categories:accessibility":["error",{"minScore":0.95}]}'
    workingDirectory: $(app)
    displayName: '⭐ Lighthouse (3 runs, median)'

  - task: AzureCLI@2
    condition: eq(variables.doPush, 'true')
    inputs:
      azureSubscription: 'sc-shop-ci'                # ⭐ AcrPush, no AKS role
      scriptType: bash
      scriptLocation: inlineScript
      inlineScript: az acr login --name $(acr)

  - task: Docker@2
    condition: eq(variables.doPush, 'true')
    inputs:
      command: buildAndPush
      repository: shop-ui
      containerRegistry: 'sc-shop-ci-docker'
      Dockerfile: $(app)/Dockerfile
      buildContext: $(app)
      tags: 'sha-$(Build.SourceVersion)'
      arguments: '--provenance=mode=max --sbom=true --cache-from type=registry,ref=$(imageName):buildcache --cache-to type=registry,ref=$(imageName):buildcache,mode=max'

  - bash: |
      set -euo pipefail
      DIGEST=$(docker buildx imagetools inspect "$(imageName):sha-$(Build.SourceVersion)" \
               --format '{{json .Manifest}}' | jq -r '.digest')
      [ -n "$DIGEST" ] && [ "$DIGEST" != "null" ] || { echo "##vso[task.logissue type=error]⛔ no digest"; exit 1; }
      REF="$(imageName)@${DIGEST}"
      docker run --rm aquasec/trivy:0.66.0 image --exit-code 1 \
        --severity CRITICAL,HIGH --ignore-unfixed "$REF"
      az keyvault secret show --vault-name kv-shop --name cosign-key --query value -o tsv > /tmp/cosign.key
      COSIGN_PASSWORD='' cosign sign --key /tmp/cosign.key --yes "$REF"
      cosign public-key --key /tmp/cosign.key > cosign.pub
      shred -u /tmp/cosign.key                        # ⭐ do not leave it
      mkdir -p out && printf '%s\n' "$REF" > out/digest.txt
      cp cosign.pub out/
      echo "##vso[build.addbuildtag]$DIGEST"
      echo "⭐ $REF"
    displayName: '⭐ Scan, sign, emit the digest'
    condition: eq(variables.doPush, 'true')

  - publish: out
    artifact: image-digest
    condition: eq(variables.doPush, 'true')
    displayName: '⭐⭐ Publish the digest artifact (the contract)'
# ⭐ CI STOPS HERE — sc-shop-ci has NO AKS role assignment.
```

---

## 6 · CI — Jenkins

`jenkins/ci-shop-ui.Jenkinsfile`

```groovy
pipeline {
  agent {
    kubernetes { yaml '''
apiVersion: v1
kind: Pod
spec:
  serviceAccountName: jenkins-ci-agent
  securityContext: { runAsNonRoot: true, runAsUser: 1000, seccompProfile: { type: RuntimeDefault } }
  containers:
  - name: node
    image: node:24-alpine
    command: ["sleep"]
    args: ["infinity"]
    resources: { requests: { cpu: 500m, memory: 1Gi }, limits: { cpu: "2", memory: 3Gi } }
    volumeMounts: [{ name: npm, mountPath: /home/node/.npm }]
  - name: kaniko
    image: gcr.io/kaniko-project/executor:v1.25.0
    command: ["sleep"]
    args: ["infinity"]
    volumeMounts:
      - { name: docker-config, mountPath: /kaniko/.docker }
  - { name: tools, image: alpine:3.22, command: ["sleep"], args: ["infinity"] }
  volumes:
    - { name: npm, persistentVolumeClaim: { claimName: jenkins-npm-cache } }
    - name: docker-config
      secret: { secretName: regcred-kaniko, items: [{ key: .dockerconfigjson, path: config.json }] }
  nodeSelector: { pool: ci }
''' }
  }
  options { timestamps(); disableConcurrentBuilds(); timeout(time: 30, unit: 'MINUTES') }
  environment {
    APP      = 'apps/shop-ui'
    SERVICE  = 'shop-ui'
    REGISTRY = 'shopacr.azurecr.io'
    // ⭐⭐ PUSH only on main, never on a PR (CHANGE_ID), never from a fork
    PUSH     = "${env.BRANCH_NAME == 'main' && env.CHANGE_ID == null}"
    TAG      = "sha-${env.GIT_COMMIT?.take(8) ?: 'local'}"
  }

  stages {
    stage('1 · Test and gates') {
      steps {
        container('node') {
          dir("${env.APP}") {
            sh '''
              set -eu
              npm ci
              npm run lint
              npm run typecheck
              npm run test:ci -- --coverage.thresholds.lines=80
              npm run build
            '''
            // ── ⭐ the two frontend-only gates ────────────────────────
            sh '''
              set -eu
              SIZE=$(du -sk dist | cut -f1); BUDGET=450
              echo "dist = ${SIZE} KiB (budget ${BUDGET})"
              [ "$SIZE" -le "$BUDGET" ] || { echo "⛔ bundle over budget"; exit 1; }
              ! grep -rqE 'AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----' dist/ \\
                || { echo "⛔ a secret is embedded in the bundle"; exit 1; }
            '''
            // ── ⭐ Lighthouse: 3 runs, median ─────────────────────────
            //   ⛔ Chrome in a pod agent needs /dev/shm; give it space.
            sh '''
              set -eu
              npm run preview -- --port 4173 &
              sleep 5
              CHROME_PATH=$(which chromium || which chromium-browser) \\
              npx @lhci/cli autorun --collect.url=http://localhost:4173 \\
                --collect.numberOfRuns=3 --collect.settings.chromeFlags="--no-sandbox --disable-dev-shm-usage" \\
                --assert.preset=lighthouse:no-pwa \\
                --assert.assertions='{"categories:performance":["error",{"minScore":0.9}],
                                      "categories:accessibility":["error",{"minScore":0.95}]}'
            '''
          }
        }
      }
    }

    stage('2 · Build image') {
      steps {
        container('kaniko') {
          sh '''
            set -eu
            /kaniko/executor --context dir://$WORKSPACE/$APP --dockerfile Dockerfile \
              --destination $REGISTRY/$SERVICE:$TAG \
              --cache=true --cache-repo=$REGISTRY/$SERVICE-cache \
              --cache-copy-layers=true --snapshot-mode=redo \
              --compressed-caching=false --use-new-run \
              --label org.opencontainers.image.revision=$GIT_COMMIT \
              ${PUSH:+--reproducible} \
              --image-name-with-digest-file /tmp/digest.txt
            cat /tmp/digest.txt
          '''
          script {
            def full = readFile('/tmp/digest.txt').trim()
            env.IMAGE_REF = env.PUSH == 'true' ? full : "${env.REGISTRY}/${env.SERVICE}:${env.TAG}"
            env.DIGEST    = full.contains('@') ? full.split('@')[1] : ''
          }
        }
      }
    }

    stage('3 · Scan + sign + publish') {
      when { expression { env.PUSH == 'true' } }
      steps {
        container('tools') {
          sh '''
            set -eu
            apk add --no-cache curl >/dev/null
            curl -fsSL https://github.com/aquasecurity/trivy/releases/download/0.66.0/trivy_0.66.0_Linux-64bit.tar.gz | tar xz -C /tmp trivy
            /tmp/trivy image --exit-code 1 --severity CRITICAL,HIGH --ignore-unfixed "$IMAGE_REF"
            curl -fsSL -o /tmp/cosign https://github.com/sigstore/cosign/releases/download/v2.6.1/cosign-linux-amd64
            chmod +x /tmp/cosign
          '''
          withCredentials([file(credentialsId: 'cosign-private-key', variable: 'COSIGN_KEY')]) {
            sh '''
              set -eu
              COSIGN_PASSWORD="$COSIGN_KEY_PASSWORD" /tmp/cosign sign --key "$COSIGN_KEY" --yes "$IMAGE_REF"
              /tmp/cosign public-key --key "$COSIGN_KEY" > cosign.pub
            '''
          }
          script {
            env.COSIGN_PUB = readFile('cosign.pub').trim()
            writeFile(file: 'digest.txt', text: "${env.IMAGE_REF}\n")
            archiveArtifacts artifacts: 'digest.txt,cosign.pub', fingerprint: true
            sh 'mkdir -p /var/jenkins/digests && cp digest.txt /var/jenkins/digests/shop-ui-main.txt'
          }
        }
      }
    }
    // ⭐ CI STOPS HERE — kubeconfig-* does not exist in the /shop-ci folder.
  }

  post {
    success {
      script {
        if (env.PUSH == 'true' && env.IMAGE_REF) {
          build job: '/shop-cd/cd-shop-ui',
                parameters: [string(name: 'IMAGE', value: env.IMAGE_REF),
                             string(name: 'GIT_SHA', value: env.GIT_COMMIT),
                             string(name: 'CI_BUILD', value: env.BUILD_URL),
                             string(name: 'COSIGN_PUB', value: env.COSIGN_PUB)],
                wait: false, propagate: false
        }
      }
    }
  }
}
```

---

## 7 · CD — the three tools, and why it is short

⭐ **The frontend's CD is the shortest in the estate**, because there is no migration, no warm-up and no schema.

| | 🔵 FE (`shop-ui`) | 🟢 BE (`shop-api`) |
|---|---|---|
| Migration Job | ⛔ none | ⭐ gated, first |
| Startup probe | 10 s | ⭐ 150 s (JVM) |
| Smoke | `GET /` + ⭐ `config.js` | `/actuator/health/readiness` + business endpoints |
| Canary | optional (static files) | ⭐ recommended |
| Rollback | ⭐ seconds | minutes |
| Total CD steps | **4** | 8+ |

**The four CD steps for the frontend:**

```bash
# 1 · validate the digest + verify provenance          (the artifact contract)
# 2 · kubectl set image deploy/shop-ui shop-ui=<digest>
# 3 · kubectl rollout status --timeout=180s
# 4 · ⭐⭐ THE FE-SPECIFIC VERIFICATION (§8)
```

The tool-specific wiring is identical to the backend's — see [`../scenario-2-cd-only/case-1-continuous-delivery/`](../scenario-2-cd-only/case-1-continuous-delivery/README.md) and [`case-2`](../scenario-2-cd-only/case-2-continuous-deployment/README.md) for GitHub Actions, Azure DevOps and Jenkins. **Only step 4 differs**, and §8 is that step.

```yaml
# ⭐ the FE smoke check, in whatever tool you use
- name: Verify the frontend serves the RIGHT config
  run: |
    set -euo pipefail
    kubectl -n shop-production port-forward deploy/shop-ui 18080:80 &
    PF=$!; sleep 5; trap 'kill $PF 2>/dev/null || true' EXIT

    # (a) the page loads
    curl -fsS -o /dev/null http://127.0.0.1:18080/

    # (b) ⭐⭐ RUNTIME CONFIG IS CORRECT FOR THIS ENVIRONMENT
    curl -fsS http://127.0.0.1:18080/config.js | grep -q 'https://api.shop' \
      || { echo "::error::⛔ config.js has the wrong API_URL"; exit 1; }

    # (c) ⭐⭐ index.html IS NOT CACHED (§8)
    curl -fsSI http://127.0.0.1:18080/index.html | grep -qi 'cache-control:.*no-cache' \
      || { echo "::error::⛔ index.html is cacheable — users will get stale asset URLs"; exit 1; }

    # (d) ⭐ hashed assets ARE cached forever
    ASSET=$(curl -fsS http://127.0.0.1:18080/ | grep -oE '/assets/[a-zA-Z0-9._-]+\.js' | head -1)
    curl -fsSI "http://127.0.0.1:18080$ASSET" | grep -qi 'immutable' \
      || { echo "::error::⛔ $ASSET is not immutable — you are wasting every user's bandwidth"; exit 1; }

    # (e) ⭐ the deployed digest is what we asked for
    kubectl -n shop-production get deploy shop-ui \
      -o jsonpath='{.spec.template.spec.containers[?(@.name=="shop-ui")].image}'
```

---

## 8 · ⭐⭐ The cache-header deploy check

**This is the incident that only frontends have.**

```
t0  deploy succeeds. new image live. index.html references /assets/index-NEW.js
t1  a user's browser has index.html CACHED from yesterday
t2  it requests /assets/index-OLD.js  →  ⛔ 404
t3  the user sees a BLANK PAGE, or:
      Uncaught TypeError: t.default is not a function
t4  they hard-refresh. it works. they report "it was broken for a second".
t5  ⛔ the ticket is closed as "cannot reproduce". THE BUG IS STILL THERE.
```

`nginx.conf`

```nginx
server {
  listen 80;
  server_name _;
  root /usr/share/nginx/html;
  index index.html;

  # ⭐⭐ THE ENTRY POINT MUST NEVER BE CACHED.
  #   `no-cache` means "revalidate every time", NOT "do not cache" — the
  #   browser may store it but must ask before using it. That is exactly
  #   right: a cheap 304, and never a stale asset list.
  location = /index.html {
    add_header Cache-Control "no-cache, must-revalidate" always;
    etag on;
  }

  # ⭐ runtime config must be fresh on EVERY load
  location = /config.js {
    add_header Cache-Control "no-store" always;
  }

  # ⭐⭐ CONTENT-HASHED ASSETS: cache forever. The filename contains a hash,
  #   so a given name can never change meaning. `immutable` tells the browser
  #   not to even revalidate — one request, ever.
  location /assets/ {
    add_header Cache-Control "public, max-age=31536000, immutable" always;
    access_log off;
  }

  # ⭐ SPA fallback — otherwise a refresh on /orders is a 404
  location / {
    try_files $uri $uri/ /index.html;
    add_header Cache-Control "no-cache" always;      # the fallback IS index.html
  }

  # ⭐ security headers, cheap and worth it
  add_header X-Content-Type-Options nosniff always;
  add_header Referrer-Policy strict-origin-when-cross-origin always;
  add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; img-src 'self' data: https:; connect-src 'self' https://api.shop" always;
  # ⚠️ 'unsafe-inline' is needed because config.js is a classic script.
  #   ⭐ Better: serve config.js as a real file (as here) and drop 'unsafe-inline'.

  gzip on;
  gzip_types text/css application/javascript application/json image/svg+xml;
  gzip_min_length 1024;
}
```

| File | ⭐ Policy | Why |
|---|---|---|
| `index.html` | `no-cache, must-revalidate` | it lists the asset URLs. If cached, users load **old** URLs |
| `/config.js` | `no-store` | runtime config must be fresh every load |
| `/assets/*` | `public, max-age=31536000, immutable` | the filename carries a content hash — it can never change meaning |
| ⭐ `X-App-Digest` header | the deployed digest | "which version served this request?" becomes `curl -I` |

```nginx
# ⭐ add the digest as a header — three lines, enormous debugging value
add_header X-App-Digest "sha256:41ab7c…" always;
# (inject it from the entrypoint script, the same way as config.js:
#  envsubst < nginx.conf.template > /etc/nginx/conf.d/default.conf)
```

---

## 9 · `static-site` (P2) — the minimal version

**Docker P2 is the smallest possible CI+CD**, and it is the right place to learn the whole shape in 20 minutes.

```dockerfile
# ⭐ no build stage at all — the "app" IS the files
FROM nginx:1.29-alpine
COPY site/ /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
HEALTHCHECK --interval=30s --timeout=3s --retries=3 CMD wget -qO- http://localhost/ >/dev/null
```

| Step | What |
|---|---|
| CI test | ⭐ `html-validate site/**/*.html` + a link checker (`lychee`) |
| CI build | `docker build` — no compile step |
| CI scan | Trivy on the **image** — the nginx base is the only attack surface |
| CI publish | push + sign + emit the digest |
| CD | `kubectl set image` + `rollout status` + `curl /` |
| ⭐ Case | 🤖 **Case 2** — there is nothing to approve |

⭐ **Why start here:** every concept in this file appears — digest contract, provenance, environment scoping, read-back verification, cache headers — with no build toolchain, no test framework and no migration to distract you. Get it green end to end, then do `shop-ui`.

---

## 10 · 🔒 Case 1 or 🤖 Case 2

| Prerequisite ([`../scenario-2-cd-only/00-delivery-vs-deployment.md`](../scenario-2-cd-only/00-delivery-vs-deployment.md) §6) | 🔵 `shop-ui` |
|---|---|
| 1 · fast, reversible deploys | ⭐ **trivially yes** — static files, no warm-up, rollback in seconds |
| 2 · tests that catch what matters | ✅ unit + bundle + Lighthouse. ⭐ no integration-test infrastructure needed |
| 3 · observability that can say "this is worse" | ⚠️ **needs RUM** — server metrics say nothing about a blank page |
| 4 · immutable artifacts by digest | ✅ — **provided config is runtime, not build-time** (§2) |
| 5 · decoupled migrations | ⭐ **n/a — there is no schema** |

⭐⭐ **Verdict: 🤖 Case 2 — with one condition.** Prerequisite 3 is the only real gap: a frontend regression is often invisible to server-side metrics (the server returns 200 and the correct bytes; the *browser* fails). So before automating promotion, add **Real User Monitoring**:

| Signal | Why |
|---|---|
| ⭐ JS error rate (Sentry / a RUM beacon) | the only way to see `TypeError: t.default is not a function` |
| ⭐ Asset 404 rate | the cache-header incident of §8, detected |
| Largest Contentful Paint p75 | a performance regression |
| ⭐ `X-App-Digest` on every RUM event | so you can attribute an error to a **version** |

Without RUM, use **pattern 3** ([`../scenario-2-cd-only/00-delivery-vs-deployment.md`](../scenario-2-cd-only/00-delivery-vs-deployment.md) §7): canary automatic, full rollout needs a click. With RUM, full Case 2 is appropriate — and the frontend is the best place in the estate to *learn* Case 2, because the consequences of being wrong are the smallest.

---

## 11 · ▶️ Run it end to end — the acceptance checks

```bash
# ── THE ONE-IMAGE PROOF (the whole point of §2) ───────────────────────
docker build -t shop-ui:test apps/shop-ui
docker run -d --name a -p 8081:80 -e API_URL=https://api.dev.shop shop-ui:test
docker run -d --name b -p 8082:80 -e API_URL=https://api.shop     shop-ui:test
sleep 2
curl -s localhost:8081/config.js | grep API_URL
curl -s localhost:8082/config.js | grep API_URL
docker image inspect shop-ui:test --format '{{.Id}}'
# ⭐ two different configs, ONE image id

# ── CI ────────────────────────────────────────────────────────────────
grep -c 'VITE_API_URL' apps/shop-ui/Dockerfile            # ⭐ must be 0
grep -c 'kubeconfig\|kubectl\|aks get-credentials' .github/workflows/ci-shop-ui.yml   # ⭐ 0
grep -q 'du -sk dist' .github/workflows/ci-shop-ui.yml && echo "✅ bundle gate"
grep -q 'numberOfRuns=3' .github/workflows/ci-shop-ui.yml && echo "✅ Lighthouse median"

# ── CD ────────────────────────────────────────────────────────────────
grep -c 'docker build\|npm ci\|npm run build' .github/workflows/cd-shop-ui.yml  # ⭐ 0

# ── ⭐ THE CACHE-HEADER CHECKS (§8) ───────────────────────────────────
kubectl -n shop-production port-forward deploy/shop-ui 18080:80 &
sleep 4
curl -fsSI localhost:18080/index.html | grep -i cache-control
# ⭐ must contain no-cache
ASSET=$(curl -fsS localhost:18080/ | grep -oE '/assets/[a-zA-Z0-9._-]+\.js' | head -1)
curl -fsSI "localhost:18080$ASSET" | grep -i cache-control
# ⭐ must contain immutable
curl -fsSI localhost:18080/config.js | grep -i cache-control
# ⭐ must contain no-store
kill %1

# ── ⭐ THE INCIDENT SIMULATION — prove the cache headers save you ──────
curl -fsS localhost:18080/ -o /tmp/old-index.html       # "cache" the entry point
kubectl -n shop-production set image deploy/shop-ui shop-ui=<NEW_DIGEST>
kubectl -n shop-production rollout status deploy/shop-ui
# now replay the CACHED index.html's asset URLs against the new deployment
grep -oE '/assets/[a-zA-Z0-9._-]+\.js' /tmp/old-index.html | while read -r A; do
  curl -fsS -o /dev/null -w "%{http_code} $A\n" "localhost:18080$A" || echo "404 $A"
done
# ⛔ WITHOUT no-cache on index.html: 404s. The user sees a blank page.
# ✅ WITH it: the browser revalidates, gets the NEW index.html, and never
#    asks for a stale asset at all.

# ── ⭐ what is running, one command ───────────────────────────────────
kubectl -n shop-production get deploy shop-ui \
  -o jsonpath='{.spec.template.spec.containers[?(@.name=="shop-ui")].image}{"\n"}'
```

---

## 12 · Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| ⛔ The app calls the wrong API in production | `config.js` not loaded before the bundle, or `API_URL` not set in the Deployment | §2 — `<script src="/config.js">` **before** the module script |
| `window.__APP_CONFIG__` is undefined | `config.js` 404s, or nginx does not serve it | check the entrypoint script ran (`docker logs`) |
| ⭐ Blank page after a deploy | `index.html` was cached → stale asset URLs → 404 | §8 — `no-cache` on `index.html` |
| `Uncaught TypeError: t.default is not a function` | same — an old chunk loaded against a new one | §8 |
| Refreshing `/orders` gives a 404 | no SPA fallback | `try_files $uri $uri/ /index.html` (§8) |
| ⛔ Lighthouse passes locally, fails in CI | shared-runner noise, or `/dev/shm` too small in a container | `numberOfRuns=3` + median; `--disable-dev-shm-usage` |
| Lighthouse fails in a Jenkins pod | no Chrome, or `--no-sandbox` missing | `CHROME_PATH=…` + `--chromeFlags="--no-sandbox --disable-dev-shm-usage"` |
| The bundle gate fails on every PR | the budget was set too low, or a legitimate dependency was added | ⭐ ratchet **deliberately**: raise it in a PR that says why |
| `npm ci` fails | `package-lock.json` is out of sync with `package.json` | ⛔ never `npm install` in CI to "fix" it — commit the lockfile |
| Trivy reports unfixed nginx CVEs and blocks every build | no `--ignore-unfixed` | §4 — a CVE with no available fix is not a decision anyone can make |
| The image is 900 MB | the build stage leaked into the runtime stage | multi-stage, `COPY --from=build /app/dist` only |
| ⛔ A secret appears in the bundle | a `VITE_`-prefixed env var at build time | ⭐ the secret-grep in §3, plus: never prefix a secret with `VITE_` |
| The digest differs between two builds of the same commit | timestamps in layers | ⭐ `--reproducible` (Kaniko) / pinned base image digest |

---

<a name="tasks--answers"></a>
## 13 · ⭐ TASKS — answers at the END

| # | Task |
|---|---|
| **T1** | Convert `shop-ui` to runtime config and prove **one image** serves dev, staging and production |
| **T2** | Add the bundle-size and Lighthouse gates so they do not flake |
| **T3** | Write `nginx.conf` with correct cache headers for `index.html`, `/assets/` and `/config.js`, plus the SPA fallback |
| **T4** | Simulate the stale-`index.html` incident and show that your cache headers prevent it |
| **T5** | Add `X-App-Digest` to responses so any request can be attributed to a version |
| **T6** | Build the full CI in your chosen tool: test → gates → image → scan → sign → digest artifact |
| **T7** | Build the CD: digest input → set image → rollout status → the five FE-specific verifications |
| **T8** | Do the same for `static-site` (P2) and note what disappears |
| **T9** | Decide Case 1 or Case 2 for `shop-ui`, and name the one prerequisite that is not yet met |
| **T10** | ⭐⭐ Production users report a blank page 20 minutes after a successful deploy. The pipeline is green, `curl /` returns 200, and the pod is Running. Give your diagnosis in order of likelihood, the command that confirms each, and the permanent fix |

---

# ✅ ANSWERS

**T1.** §2 in full: remove `ARG VITE_API_URL` from the build stage; add `docker-entrypoint.d/40-inject-config.sh` writing `/usr/share/nginx/html/config.js` from real env vars at container start (⭐ **escaping the values** — an unescaped quote breaks the JS, and an attacker-controlled env var becomes XSS); load it with `<script src="/config.js">` **before** the module script; read it through one `src/config.ts` with a `?? import.meta.env` fallback so `npm run dev` still works without a container. **The proof is §2.3:** build one image, run two containers with different `API_URL`, `curl` each `config.js` (they differ), and `docker image inspect --format '{{.Id}}'` (⭐ **identical**). That single check is the whole point — same bytes, different config — and it is what makes the digest contract meaningful: the artifact you verified in staging is byte-for-byte the artifact running in production.

**T2.** §3. Two decisions make them non-flaky. **Bundle size:** set the budget from *today's measured value* (`du -sk dist`) and ratchet it **down** deliberately, never up silently; prefer per-chunk budgets over a total, because a 50 KB regression in the critical path can hide inside a flat total. **Lighthouse:** `--collect.numberOfRuns=3` and take the **median** — a single run on a shared runner carries ±10 points of noise, and a flaky gate gets disabled, which is worse than no gate. In a container also pass `--chromeFlags="--no-sandbox --disable-dev-shm-usage"`, because Chrome's default `/dev/shm` (64 MB in Docker) causes intermittent renderer crashes that look like score fluctuations. ⭐ **When a gate legitimately fails:** raise the budget in a PR whose description says *why* — that converts a silent ratchet-up into a reviewed decision.

**T3.** §8. `location = /index.html { add_header Cache-Control "no-cache, must-revalidate" always; }` — ⭐ `no-cache` means "revalidate every time", not "do not store": the browser may keep it but must ask, giving a cheap 304 and never a stale asset list. `location = /config.js { … "no-store" … }` — runtime config must be fresh on every load. `location /assets/ { … "public, max-age=31536000, immutable" … }` — safe because the filename carries a content hash, so a given name can never change meaning; `immutable` also suppresses revalidation entirely, which is one fewer request per asset per user forever. Plus `location / { try_files $uri $uri/ /index.html; add_header Cache-Control "no-cache" always; }` — the SPA fallback, without which a browser refresh on `/orders` is a 404. ⭐ Use `always` on every `add_header`: without it, nginx omits the header on non-2xx responses, so your 404s and 500s are served cacheable.

**T4.** §11's incident simulation. Save the current `index.html`, deploy a new digest, then replay the **saved** file's asset URLs against the new deployment and count 404s. ⛔ Without `no-cache` on `index.html`, the old asset filenames are gone (Vite hashes them) and every one 404s — which is exactly what a user with a cached entry point experiences: a blank page or `TypeError`, self-resolving on a hard refresh. ✅ With `no-cache`, the browser revalidates, receives the new `index.html` (a 200 or a 304), and never requests a stale asset at all. ⭐ **Why this test is worth running:** the failure is intermittent, user-specific and self-healing, so it is reported as "it was broken for a second" and closed as unreproducible. Proving the mechanism once, deliberately, is the only way it gets fixed rather than tolerated.

**T5.** §8. Have the entrypoint script `envsubst` the digest into `nginx.conf` (`add_header X-App-Digest "$GIT_SHA" always;` from a template), so it is injected at container start from the same env var as `config.js` — never hardcoded at build time, or you are back to one image per environment. ⭐ **The payoff is attribution:** put the header on every RUM/error event, and "which version produced this JS error?" becomes a `groupBy` instead of a log-correlation project. It also makes the canary measurable from outside the cluster — `for i in $(seq 1 200); do curl -sI … ; done | sort | uniq -c` shows your real traffic split, which is the check that proves a canary is actually a canary rather than a pod-count accident. Three lines of config; it turns version attribution from an investigation into a `curl -I`.

**T6.** §4, §5 or §6 for your tool. The order and the reasons: `npm ci` (⭐ never `npm install` — `ci` honours the lockfile exactly and fails on a mismatch, which is what makes the build reproducible) → lint + `tsc --noEmit` → unit tests with a coverage threshold → `npm run build` (⭐ with **no** `VITE_API_URL`) → bundle gate → secret-grep → Lighthouse ×3 → image build with `provenance=mode=max` and `sbom=true` → **Trivy on the image** with `--exit-code 1 --ignore-unfixed` (⭐ `npm audit` misses the nginx base layer, which is the only real attack surface in the runtime image) → cosign sign → **emit the digest as an artifact** → stop. ⭐ Two rules that define CI-only: the push flag is `event_name == 'push' && ref == 'refs/heads/main'` (never a PR, never a fork), and the file contains **no** cluster credential and **no** deploy verb.

**T7.** §7's four steps plus the five verifications. Validate the digest shape and `cosign verify` provenance → `kubectl set image deploy/shop-ui shop-ui=<digest>` → `rollout status --timeout=180s` → then verify: **(a)** `GET /` is 200; **(b)** ⭐ `config.js` contains this environment's `API_URL`; **(c)** ⭐ `index.html` is served `no-cache`; **(d)** ⭐ hashed assets are served `immutable`; **(e)** the digest read back from the cluster equals the one requested. **Two details matter:** run the smoke from **inside** the cluster (a throwaway `curlimages/curl` pod against the Service DNS name) so you test the Service selector and endpoints, which an external curl through the ingress cannot isolate; and read the image back with the JSONPath **name filter** `[?(@.name=="shop-ui")]`, not `[0]`, because a sidecar makes `[0]` the wrong container. ⭐ Checks (b)–(d) are frontend-specific and are the ones that catch the two failure modes no other shape has: environment-specific config baked into the image, and stale-cache blank pages.

**T8.** §9. What disappears: the whole build stage (`npm ci`, Vite, TypeScript), the bundle gate, Lighthouse, the runtime-config machinery, and the SPA fallback. What remains — ⭐ **and this is the point** — is the entire *pipeline architecture*: a digest-only artifact contract, a push flag that excludes PRs and forks, an image scan (Trivy on the nginx base, now the only attack surface), cosign signing, environment-scoped credentials, `set image` + `rollout status`, the read-back assertion, and a `curl /` smoke. The CD is four steps and unambiguously 🤖 Case 2. **Use it as the learning vehicle:** get P2 green end to end in an afternoon, and every concept you need for `shop-ui`, `shop-api` and the polyglot shapes is already understood — you will only be adding toolchains, not architecture.

**T9.** ⭐ **🤖 Case 2 — with one prerequisite unmet.** Prerequisites 1, 2, 4 and 5 are satisfied: rollback is seconds (static files, no warm-up, no state), the test suite needs no infrastructure, artifacts are digests *provided config is runtime* (§2 — if it is build-time, prerequisite 4 fails and Case 2 is off the table), and there is no schema at all. **The unmet one is prerequisite 3 — observability that can say "this is worse".** A frontend regression is frequently invisible to server-side metrics: nginx returns 200 with the correct bytes while the browser throws `TypeError` or renders nothing. So add **Real User Monitoring** before automating promotion — JS error rate, ⭐ **asset 404 rate** (which is the §8 incident, detected), LCP p75, and `X-App-Digest` on every event so errors are attributable to a version (T5). **Until RUM exists, use pattern 3** ([`../scenario-2-cd-only/00-delivery-vs-deployment.md`](../scenario-2-cd-only/00-delivery-vs-deployment.md) §7): canary automatic, full rollout needs a click. ⭐ **And the strategic point:** the frontend is the best place in the estate to *learn* Case 2, because the consequences of a wrong automated decision are the smallest and the rollback is the fastest — which is exactly how you should choose a pilot.

**T10.** ⭐⭐ Green pipeline, 200 from `curl /`, pod Running, users on a blank page. **In order of likelihood:**

1. **Stale `index.html` in browser caches → old asset URLs → 404 → blank page.** By far the most likely, and the timing fits: it appears *after* the deploy and grows as cached clients navigate. ⭐ **Confirm:** `curl -fsSI https://shop/ index.html | grep -i cache-control` — if it is not `no-cache`, that is it. Then take the asset URLs from a pre-deploy copy of `index.html` and request them: **404s confirm it.** Note why `curl /` returning 200 proves nothing — the *server* is fine; the *cached client* is not.
2. **A JS runtime error, not a 404** — a new dependency, a changed API response shape, or a build that inlined an undefined env var. **Confirm:** the browser console (one user, remote session, or your RUM feed). ⭐ This is why T9's prerequisite-3 gap matters: server metrics cannot see it.
3. **`config.js` missing or wrong** — `window.__APP_CONFIG__` is undefined, so `config.apiUrl` falls back to `localhost` and every API call fails. **Confirm:** `curl -fsS https://shop/config.js` — a 404 or a `localhost` API_URL. Check the entrypoint script ran: `kubectl logs deploy/shop-ui`.
4. **A CSP that blocks the bundle** — `script-src` too narrow, or `'unsafe-inline'` removed while `config.js` still needs it. **Confirm:** the console shows `Refused to execute script … violates Content Security Policy`.
5. **The deploy did not actually change anything** — `set image` with a mistyped container name succeeds silently. **Confirm:** `kubectl get deploy shop-ui -o jsonpath='{.spec.template.spec.containers[?(@.name=="shop-ui")].image}'` and compare with the digest you shipped. ⭐ This is the CHECK 4 read-back, and it is why it exists.
6. **An ingress/CDN cache serving the old `index.html`** — a CDN in front of nginx with its own TTL, independent of your headers. **Confirm:** compare `curl -I` direct-to-pod (via `port-forward`) against `curl -I` through the CDN.

**The permanent fix — all three, because they address different layers:**
- ⭐ **`Cache-Control: no-cache, must-revalidate` on `index.html`** and `no-store` on `/config.js`, with `immutable, max-age=31536000` on `/assets/` (§8). The entry point must never be cached; content-hashed assets should be cached forever. Add `always` so error responses carry it too, and **purge the CDN on deploy** if one exists.
- ⭐ **Make the check a CD gate, not a runbook** — §7's verification step (c) fails the deploy if `index.html` is cacheable. A rule in a document is followed once; a rule in a pipeline is followed always.
- ⭐ **Add RUM with `X-App-Digest`** (T5, T9) so the *next* occurrence is detected by a rising JS-error or asset-404 rate within minutes, attributed to a specific digest, rather than by user reports of a page that "was broken for a second".

**The meta-lesson:** `curl /` returning 200 tests the server. A frontend incident lives in the **browser**, on a client whose state you do not control and whose cache lifetime you set. ⭐ Verifying a frontend deployment means asserting on *headers and client-visible behaviour*, not on status codes — which is why §7's five checks include three that no backend pipeline needs.

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish_Kumar_Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn: https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260
🔗 GitHub: https://github.com/3558Bhk

*One image, runtime config, `no-cache` on the entry point — and the frontend becomes the safest place to learn Case 2.*

</div>
