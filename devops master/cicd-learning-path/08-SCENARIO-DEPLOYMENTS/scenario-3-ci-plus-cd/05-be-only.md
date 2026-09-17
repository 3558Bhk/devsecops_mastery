# 🟢 SCENARIO 3 · BACKEND ONLY — CI + CD END TO END
### Four backends, four languages, one architecture: `shop-api` (Java), `checkout` (Go), `order-worker` (Python), `payment-mock` (Go) — from commit to production.

> **Apps:** Docker P9 / K8s P9 (`shop-api`) · `checkout` · `order-worker` · `payment-mock` · and the P13 data tier as a dependency.
> **Verdict up front:** ⭐ the backend is where CI+CD earns its keep — and where it is hardest. Two things have no frontend analogue: **real infrastructure in CI** (Testcontainers) and **a schema you cannot roll back** (migrations).

---

## 📇 Contents

| § | What |
|---|---|
| [1](#1---what-makes-the-backend-harder) | ⭐ What makes the backend harder — five properties |
| [2](#2--the-four-backends-side-by-side) | The four backends, side by side |
| [3](#3---testcontainers--the-gate-that-makes-backend-ci-mean-anything) | ⭐⭐ Testcontainers — the gate that makes backend CI mean anything |
| [4](#4--ci-per-language) | CI per language — Java, Go, Python (full files) |
| [5](#5--the-dockerfiles-per-language) | The Dockerfiles per language — and the size differences that matter |
| [6](#6---cd--the-migration-job-gates-the-rollout) | ⭐⭐ CD — the migration Job gates the rollout |
| [7](#7---the-worker-problem--order-worker) | ⭐ The worker problem — `order-worker` has no health endpoint |
| [8](#8---case-1-or--case-2--per-backend) | 🔒 Case 1 or 🤖 Case 2 — per backend, with reasons |
| [9](#9--️-the-data-tier-dependency-p13) | 🗄️ The data tier dependency (P13) |
| [10](#10--️-run-it-end-to-end--the-acceptance-checks) | ▶️ Run it end to end — the acceptance checks |
| [11](#11--troubleshooting) | Troubleshooting |
| [12](#12---tasks--answers-at-the-end) | Tasks and answers — **answers at the END** |

---

## 1 · ⭐ What makes the backend harder

| # | Property | Consequence |
|---|---|---|
| **1** | ⭐ **It has a schema** | CI must validate **migrations**, not just code — and a migration is the one thing you cannot roll back |
| **2** | ⭐ **It has dependencies** (Postgres, Redis, RabbitMQ) | tests need **real infrastructure**: Testcontainers, not mocks |
| **3** | **Build time is minutes** | caching is not an optimisation; it is the difference between a usable and an unusable pipeline |
| **4** | ⭐ **It warms up** | JVM JIT, connection pools, caches — the first 60 s are unrepresentative |
| **5** | **It holds connections** | rolling update means draining: `preStop` sleep, `terminationGracePeriodSeconds` |

**And one thing that is *easier* than the frontend:**

```
✅ BACKEND CONFIG IS RUNTIME-BY-DEFAULT.
   Spring reads SPRING_DATASOURCE_URL from the environment at start-up.
   Go reads os.Getenv. Python reads os.environ.
   ⭐ There is no build-time trap. One image serves every environment
     naturally — the property the frontend has to work for (§04 file).
```

---

## 2 · The four backends, side by side

| | `shop-api` (Java) | `checkout` (Go) | `order-worker` (Python) | `payment-mock` (Go) |
|---|---|---|---|---|
| **Docker/K8s project** | P9 | P12 | P11 | P12 |
| Build | `mvnw -B -ntp verify` | `go build -trimpath -ldflags="-s -w"` | `uv sync --frozen` | `go build` |
| Test | Surefire + ⭐ **Failsafe ITs** | `go test -race -count=1 ./...` | `pytest --cov-fail-under=80` | `go test ./...` |
| Infra in CI | ⭐ **Postgres 17** (Testcontainers) | Postgres + Redis | ⭐ **RabbitMQ** | none |
| Lint | SpotBugs, Checkstyle, ErrorProne | `go vet`, `golangci-lint` | `ruff`, `mypy` | `go vet` |
| CVE | `dependency-check`, Trivy | ⭐ `govulncheck` + Trivy | ⭐ `pip-audit` + Trivy | `govulncheck` |
| Runtime image | `temurin:21-jre-alpine` ~230 MB | ⭐ **`scratch`** ~10 MB | `python:3.13-slim` ~120 MB | ⭐ `scratch` ~10 MB |
| Cold build | 4–8 min | ~40 s | ~60 s | ~40 s |
| Warm build | ⭐ 60–90 s | ~15 s | ~20 s | ~15 s |
| Port | 8080 | 9091 | ⛔ **none** | 9093 |
| Health | `/actuator/health/readiness` | `/readyz` | ⭐ **a heartbeat file** | `/healthz` |
| Start-up time | ⭐ 20–60 s (JVM) | ~50 ms | ~1 s | ~50 ms |
| Migration | ⭐ **Flyway** | none | Alembic | none |
| Warm-up matters? | ⭐⭐ **yes** — affects canary choice | no | no | no |
| Deploy risk | ⭐⭐⭐ highest | low | ⭐⭐ medium (in-flight work) | ⭐ **lowest** |
| ⭐ Case | 🔒 **Case 1** | 🤖 **Case 2** | 🔒 **Case 1** | 🤖 **Case 2 — the pilot** |

---

## 3 · ⭐⭐ Testcontainers — the gate that makes backend CI mean anything

```java
// ⛔ THE WEAK VERSION: H2 in "Postgres compatibility mode".
//   It is NOT Postgres. Different types (no real JSONB, no arrays),
//   different constraint enforcement, different SQL, different locking.
//   Tests that pass on H2 regularly fail in production — so the gate is
//   decorative, and worse, it is CONFIDENTLY decorative.
@DataJpaTest
@AutoConfigureTestDatabase(replace = Replace.NONE)   // pointed at H2

// ✅ THE REAL VERSION: an actual Postgres 17, started per test class.
@Testcontainers
@SpringBootTest
class OrderRepositoryIT {

    @Container
    static PostgreSQLContainer<?> PG = new PostgreSQLContainer<>(
        DockerImageName.parse("postgres:17.7")        // ⭐ pin the version
    );
    // ⭐⭐ `static` + `@Container` = ONE container for the whole class.
    //   Per-test containers cost ~2 s each and dominate the runtime.

    @DynamicPropertySource
    static void props(DynamicPropertyRegistry r) {
        r.add("spring.datasource.url",      PG::getJdbcUrl);
        r.add("spring.datasource.username", PG::getUsername);
        r.add("spring.datasource.password", PG::getPassword);
    }

    @Autowired OrderRepository repo;

    @Test
    void findsByStatus() {
        repo.save(new Order("o1", Status.PAID));
        assertThat(repo.findByStatus(Status.PAID)).hasSize(1);
    }
}
```

### 3.1 Where the Docker daemon comes from — per tool

| Tool | Daemon? | ⭐ Solution |
|---|---|---|
| 🐙 GitHub-hosted runners | ✅ yes | nothing to do |
| 🔷 Azure DevOps `vmImage` agents | ✅ yes | nothing to do |
| 🔨 Jenkins **VM** agent | ✅ yes | nothing to do |
| ⛔ Jenkins **Kubernetes pod** agent | ❌ **no** | (a) a **sidecar Postgres** in the pod template, (b) Testcontainers Cloud, (c) a VM agent for that job |
| ⛔ Anywhere | — | ⛔ **NEVER mount `/var/run/docker.sock`.** That is root on the host |

```yaml
# ⭐ (a) the sidecar Postgres — the pragmatic answer on Kubernetes agents
spec:
  containers:
    - name: postgres
      image: postgres:17.7
      env:
        - { name: POSTGRES_PASSWORD, value: shop }
        - { name: POSTGRES_DB,       value: shop }
      readinessProbe:
        exec: { command: ["pg_isready", "-U", "shop"] }
        initialDelaySeconds: 5
        periodSeconds: 2
```

```java
// ⭐ and the test profile that uses it instead of Testcontainers
@TestConfiguration
@Profile("ci-sidecar")
class SidecarDataSource {
  @Bean DataSource ds() {
    return DataSourceBuilder.create()
      .url(System.getenv("SPRING_DATASOURCE_URL"))     // jdbc:postgresql://localhost:5432/shop
      .username("shop").password(System.getenv("SPRING_DATASOURCE_PASSWORD"))
      .build();
  }
}
// ⭐ TRADE-OFF: ONE shared database for the whole build, so tests must not
//   depend on isolation. Use @Transactional tests (rolled back per test) or
//   truncate between classes. A suite with ordering dependencies will produce
//   intermittent failures that LOOK like flakiness and are actually shared state.
```

### 3.2 ⭐ The migration-shadow check — what a clean database cannot tell you

```
CI must prove, on every commit:
  1. the migration SQL PARSES                 → flyway validate
  2. it APPLIES to a real EMPTY database      → Testcontainers + migrate
  3. ⭐⭐ it applies to a COPY OF PRODUCTION'S SCHEMA
  4. the code works AFTER the migration       → the integration tests
  5. ⭐ it is REVERSIBLE, or explicitly marked as not
```

```bash
# ── CHECK 3 · the one everybody skips, and the one that causes incidents ──
psql "$CI_DB_URL" -c "CREATE DATABASE shadow TEMPLATE prod_snapshot;"
flyway -url=jdbc:postgresql://ci-db:5432/shadow \
       -locations=classpath:db/migration migrate
```

⭐⭐ **Why check 3 matters:** a migration that applies cleanly to an empty database can fail on a 40-million-row production table — because of a lock timeout, a `NOT NULL` on a column with existing nulls, a unique index over duplicated data, or an index build that takes twenty minutes. `flyway validate` and a clean-DB test **cannot see any of that.** Check 3 is the only one that can, and it is cheap: restore a schema-only snapshot nightly, and run migrations against it in CI.

---

## 4 · CI per language

### 4.1 ⭐ Java — `shop-api` (GitHub Actions)

```yaml
name: CI · shop-api
on:
  push:         { paths: ['apps/shop-api/**'], branches: [main] }
  pull_request: { paths: ['apps/shop-api/**'], branches: [main] }
concurrency:
  group: ci-shop-api-${{ github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}
permissions: { contents: read }
env: { IMAGE: ghcr.io/${{ github.repository_owner }}/shop-api }

jobs:
  test:
    name: 1 · Build and test
    runs-on: ubuntu-latest
    defaults: { run: { working-directory: apps/shop-api } }
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-java@v5
        with: { distribution: temurin, java-version: '21', cache: maven }   # ⭐ pinned + cached

      - name: Unit tests
        run: ./mvnw -B -ntp verify -DskipITs

      # ── ⭐⭐ INTEGRATION TESTS AGAINST A REAL POSTGRES 17 ────────────
      - name: Integration tests (Testcontainers)
        run: ./mvnw -B -ntp verify -Dit.test='*IT'
        env:
          TESTCONTAINERS_RYUK_DISABLED: 'true'   # ⭐ cleanup by agent teardown
          # ⭐ GitHub-hosted runners HAVE a Docker daemon — nothing else needed

      # ── ⭐ THE MIGRATION-SHADOW CHECK (§3.2 check 3) ─────────────────
      - name: Validate migrations against a production-shaped schema
        run: |
          set -euo pipefail
          docker run -d --name shadow-db -e POSTGRES_PASSWORD=shop -p 55432:5432 postgres:17.7
          sleep 8
          # ⭐ a schema-only dump, refreshed nightly from production
          curl -fsSL "$SCHEMA_SNAPSHOT_URL" | psql "postgresql://postgres:shop@localhost:55432/postgres"
          psql "postgresql://postgres:shop@localhost:55432/postgres" -c 'CREATE DATABASE shadow TEMPLATE postgres;'
          ./mvnw -B -ntp flyway:validate flyway:migrate \
            -Dflyway.url=jdbc:postgresql://localhost:55432/shadow \
            -Dflyway.user=postgres -Dflyway.password=shop
          docker rm -f shadow-db
        env:
          SCHEMA_SNAPSHOT_URL: ${{ secrets.SCHEMA_SNAPSHOT_URL }}

      - name: Static analysis
        run: ./mvnw -B -ntp spotbugs:check checkstyle:check
      - name: ⭐ Dependency CVE scan
        run: ./mvnw -B -ntp org.owasp:dependency-check-maven:check   # ⛔ a gate, not a report
      - uses: actions/upload-artifact@v4
        if: always()
        with: { name: test-results, path: apps/shop-api/target/surefire-reports/ }

  image:
    name: 2 · Image, scan, sign, publish
    needs: test
    runs-on: ubuntu-latest
    permissions: { contents: read, packages: write, id-token: write }
    steps:
      - uses: actions/checkout@v7
      - uses: docker/setup-buildx-action@v3
      - id: flags
        run: |
          [ "${{ github.event_name }}" = "push" ] && [ "${{ github.ref }}" = "refs/heads/main" ] \
            && echo "push=true" >> "$GITHUB_OUTPUT" || echo "push=false" >> "$GITHUB_OUTPUT"
      - uses: docker/login-action@v3
        if: steps.flags.outputs.push == 'true'
        with: { registry: ghcr.io, username: '${{ github.actor }}', password: '${{ secrets.GITHUB_TOKEN }}' }
      - uses: docker/build-push-action@v6
        id: build
        with:
          context: apps/shop-api
          push: ${{ steps.flags.outputs.push == 'true' }}
          tags: ${{ env.IMAGE }}:sha-${{ github.sha }}
          cache-from: type=gha,scope=shop-api
          cache-to: type=gha,scope=shop-api,mode=max
          provenance: mode=max
          sbom: true
      - uses: aquasecurity/trivy-action@0.33.1
        if: steps.flags.outputs.push == 'true'
        with:
          image-ref: ${{ env.IMAGE }}@${{ steps.build.outputs.digest }}
          exit-code: '1'
          severity: CRITICAL,HIGH
          ignore-unfixed: true
      - uses: sigstore/cosign-installer@v4
      - if: steps.flags.outputs.push == 'true'
        env: { COSIGN_YES: 'true' }
        run: cosign sign --yes "${{ env.IMAGE }}@${{ steps.build.outputs.digest }}"
      - name: ⭐⭐ Emit the digest
        if: steps.flags.outputs.push == 'true'
        run: |
          mkdir -p out
          printf '%s@%s\n' "${{ env.IMAGE }}" "${{ steps.build.outputs.digest }}" > out/digest.txt
          # ⭐ migration metadata CD needs to make a Case 2 decision
          cat > out/manifest.json <<EOF
          {"service":"shop-api","image":"${{ env.IMAGE }}@${{ steps.build.outputs.digest }}",
           "commit":"${{ github.sha }}",
           "migrations": $(ls apps/shop-api/src/main/resources/db/migration/*.sql 2>/dev/null | jq -R . | jq -s .),
           "backwardCompatible": true}
          EOF
      - uses: actions/upload-artifact@v4
        if: steps.flags.outputs.push == 'true'
        with: { name: image-digest, path: out/, retention-days: 90 }
```

### 4.2 ⭐ Go — `checkout`

```yaml
name: CI · checkout
on:
  push:         { paths: ['apps/checkout/**'], branches: [main] }
  pull_request: { paths: ['apps/checkout/**'], branches: [main] }
permissions: { contents: read }
env: { IMAGE: ghcr.io/${{ github.repository_owner }}/checkout }

jobs:
  test:
    runs-on: ubuntu-latest
    defaults: { run: { working-directory: apps/checkout } }
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-go@v6
        with: { go-version: '1.25.0', cache-dependency-path: apps/checkout/go.sum }  # ⭐ pinned

      - name: Vet + lint
        run: |
          go vet ./...
          go run github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v2.6.2 run

      # ── ⭐ -race AND -count=1, both matter ───────────────────────────
      - name: Test
        run: go test -race -count=1 -covermode=atomic -coverprofile=cover.out ./...
        # ⭐ -race   : the race detector. Go's killer CI feature; a data race
        #             found here is an incident avoided.
        # ⭐ -count=1 : disables the TEST CACHE. Without it, `go test` prints
        #             "(cached)" and you are not testing anything.

      - name: Coverage gate
        run: |
          go tool cover -func=cover.out | tail -1
          PCT=$(go tool cover -func=cover.out | tail -1 | awk '{print $3}' | tr -d '%')
          [ "${PCT%.*}" -ge 80 ] || { echo "::error::coverage ${PCT}% < 80%"; exit 1; }

      # ── ⭐⭐ govulncheck — Go-specific, and better than a CVE list ────
      - name: govulncheck
        run: go run golang.org/x/vuln/cmd/govulncheck@latest ./...
        # ⭐ WHY IT IS DIFFERENT: it reports only vulnerabilities in code you
        #   ACTUALLY CALL. A CVE in an unused function of a dependency is not
        #   reported. That makes it actionable where `npm audit` is noise.

      - name: Build
        run: CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /tmp/checkout .
        # ⭐ CGO_ENABLED=0 → a STATIC binary → it can run on `scratch`
        # ⭐ -trimpath    → strips build paths → reproducible, no leaked paths
        # ⭐ -s -w        → strips symbols/DWARF → ~30% smaller

  image:
    needs: test
    runs-on: ubuntu-latest
    permissions: { contents: read, packages: write, id-token: write }
    steps:
      - uses: actions/checkout@v7
      - uses: docker/setup-buildx-action@v3
      - id: flags
        run: |
          [ "${{ github.event_name }}" = "push" ] && [ "${{ github.ref }}" = "refs/heads/main" ] \
            && echo "push=true" >> "$GITHUB_OUTPUT" || echo "push=false" >> "$GITHUB_OUTPUT"
      - uses: docker/login-action@v3
        if: steps.flags.outputs.push == 'true'
        with: { registry: ghcr.io, username: '${{ github.actor }}', password: '${{ secrets.GITHUB_TOKEN }}' }
      - uses: docker/build-push-action@v6
        id: build
        with:
          context: apps/checkout
          push: ${{ steps.flags.outputs.push == 'true' }}
          tags: ${{ env.IMAGE }}:sha-${{ github.sha }}
          cache-from: type=gha,scope=checkout
          cache-to: type=gha,scope=checkout,mode=max
          provenance: mode=max
          sbom: true
      - uses: aquasecurity/trivy-action@0.33.1
        if: steps.flags.outputs.push == 'true'
        with: { image-ref: '${{ env.IMAGE }}@${{ steps.build.outputs.digest }}',
                exit-code: '1', severity: CRITICAL,HIGH, ignore-unfixed: true }
      - uses: sigstore/cosign-installer@v4
      - if: steps.flags.outputs.push == 'true'
        env: { COSIGN_YES: 'true' }
        run: cosign sign --yes "${{ env.IMAGE }}@${{ steps.build.outputs.digest }}"
      - if: steps.flags.outputs.push == 'true'
        run: |
          mkdir -p out
          printf '%s@%s\n' "${{ env.IMAGE }}" "${{ steps.build.outputs.digest }}" > out/digest.txt
      - uses: actions/upload-artifact@v4
        if: steps.flags.outputs.push == 'true'
        with: { name: image-digest, path: out/, retention-days: 90 }
```

### 4.3 ⭐ Python — `order-worker`

```yaml
name: CI · order-worker
on:
  push:         { paths: ['apps/order-worker/**'], branches: [main] }
  pull_request: { paths: ['apps/order-worker/**'], branches: [main] }
permissions: { contents: read }
env: { IMAGE: ghcr.io/${{ github.repository_owner }}/order-worker }

jobs:
  test:
    runs-on: ubuntu-latest
    defaults: { run: { working-directory: apps/order-worker } }
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-python@v6
        with: { python-version: '3.13' }
      - uses: astral-sh/setup-uv@v7
        with: { enable-cache: true, cache-dependency-glob: apps/order-worker/uv.lock }

      # ── ⭐ `--frozen` is the Python equivalent of `npm ci` ────────────
      - name: Install
        run: uv sync --frozen --all-extras
        # ⭐ --frozen: use the lockfile EXACTLY. Without it uv may resolve
        #   something newer, and "works on my machine" returns.

      - name: Lint + typecheck
        run: |
          uv run ruff check .
          uv run ruff format --check .
          uv run mypy .                     # ⭐ Python's type gate

      # ── ⭐ A REAL RABBITMQ, because this is a QUEUE CONSUMER ─────────
      - name: Start RabbitMQ (a service container, not a mock)
        uses: addnab/docker-run-action@v3
        with:
          image: rabbitmq:4.2-management-alpine
          options: -p 5672:5672 -p 15672:15672 --name rabbit --health-cmd "rabbitmq-diagnostics -q ping" --health-interval 5s --health-timeout 3s --health-retries 20
      - name: Test
        run: uv run pytest -q --cov --cov-fail-under=80
        env:
          AMQP_URL: amqp://guest:guest@localhost:5672/
          # ⭐ or with Testcontainers-python, which needs no service container:
          #   with RabbitMqContainer("rabbitmq:4.2") as rmq: os.environ["AMQP_URL"]=rmq.get_connection_url()

      - name: ⭐ pip-audit — known CVEs in the resolved set
        run: uv run pip-audit --strict
      - name: ⭐ Bandit — Python-specific security lint
        run: uv run bandit -r src/ -ll

  image:
    needs: test
    runs-on: ubuntu-latest
    permissions: { contents: read, packages: write, id-token: write }
    steps:
      - uses: actions/checkout@v7
      - uses: docker/setup-buildx-action@v3
      - id: flags
        run: |
          [ "${{ github.event_name }}" = "push" ] && [ "${{ github.ref }}" = "refs/heads/main" ] \
            && echo "push=true" >> "$GITHUB_OUTPUT" || echo "push=false" >> "$GITHUB_OUTPUT"
      - uses: docker/login-action@v3
        if: steps.flags.outputs.push == 'true'
        with: { registry: ghcr.io, username: '${{ github.actor }}', password: '${{ secrets.GITHUB_TOKEN }}' }
      - uses: docker/build-push-action@v6
        id: build
        with:
          context: apps/order-worker
          push: ${{ steps.flags.outputs.push == 'true' }}
          tags: ${{ env.IMAGE }}:sha-${{ github.sha }}
          cache-from: type=gha,scope=order-worker
          cache-to: type=gha,scope=order-worker,mode=max
          provenance: mode=max
          sbom: true
      - uses: aquasecurity/trivy-action@0.33.1
        if: steps.flags.outputs.push == 'true'
        with: { image-ref: '${{ env.IMAGE }}@${{ steps.build.outputs.digest }}',
                exit-code: '1', severity: CRITICAL,HIGH, ignore-unfixed: true }
      - uses: sigstore/cosign-installer@v4
      - if: steps.flags.outputs.push == 'true'
        env: { COSIGN_YES: 'true' }
        run: cosign sign --yes "${{ env.IMAGE }}@${{ steps.build.outputs.digest }}"
      - if: steps.flags.outputs.push == 'true'
        run: |
          mkdir -p out
          printf '%s@%s\n' "${{ env.IMAGE }}" "${{ steps.build.outputs.digest }}" > out/digest.txt
      - uses: actions/upload-artifact@v4
        if: steps.flags.outputs.push == 'true'
        with: { name: image-digest, path: out/, retention-days: 90 }
```

### 4.4 ⭐ The three things that differ per language — a summary

| | Java | Go | Python |
|---|---|---|---|
| Install + cache key | `mvnw dependency:go-offline` · `pom.xml` | `go mod download` · `go.sum` | ⭐ `uv sync --frozen` · `uv.lock` |
| The "honour the lockfile" flag | Maven has no lockfile — ⭐ pin the **wrapper** and use `-ntp` | `go.sum` is the lockfile; ⛔ never `go get` in CI | ⭐ `--frozen` (or `pip install --require-hashes`) |
| The race/concurrency check | ⛔ none built in | ⭐⭐ `go test -race` | ⛔ none built in (use `pytest-xdist` carefully) |
| The test-cache trap | Surefire reruns | ⛔ `go test` **caches** — `-count=1` disables it | pytest caches nothing |
| The language-specific vuln tool | `dependency-check` | ⭐⭐ `govulncheck` (reachability-aware) | ⭐ `pip-audit`, `bandit` |
| Real infra needed | Postgres | Postgres + Redis | ⭐ RabbitMQ |
| Static binary possible? | ⛔ needs a JRE | ✅ `CGO_ENABLED=0` → `scratch` | ⛔ needs an interpreter |

---

## 5 · The Dockerfiles per language

### 5.1 ⭐ Java — the ~230 MB one

```dockerfile
# ── build ──────────────────────────────────────────────────────────────
FROM maven:3.9.11-eclipse-temurin-21 AS build
WORKDIR /app
COPY pom.xml .
RUN --mount=type=cache,target=/root/.m2 mvn -B -ntp dependency:go-offline   # ⭐ cached layer
COPY src ./src
RUN --mount=type=cache,target=/root/.m2 mvn -B -ntp package -DskipTests

# ── ⭐ EXTRACT THE LAYERS — Spring Boot's layertools ───────────────────
FROM build AS extract
WORKDIR /app
RUN java -Djarmode=layertools -jar target/*.jar extract

# ── runtime ────────────────────────────────────────────────────────────
FROM eclipse-temurin:21-jre-alpine AS runtime
RUN addgroup -S app && adduser -S app -G app
WORKDIR /app
# ⭐⭐ COPY IN DEPENDENCY ORDER — least-changed first.
#   dependencies/ almost never changes → cached across builds.
#   snapshot-dependencies/ rarely. application/ always.
COPY --from=extract /app/dependencies/ ./
COPY --from=extract /app/spring-boot-loader/ ./
COPY --from=extract /app/snapshot-dependencies/ ./
COPY --from=extract /app/application/ ./
USER app
EXPOSE 8080
# ⭐⭐ JVM IN A CONTAINER: three flags that matter
ENV JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75 -XX:+UseContainerSupport -XX:InitialRAMPercentage=50"
# ⛔ NEVER set -Xmx by hand: the JVM must size itself from the cgroup limit.
#   A hardcoded -Xmx larger than the container limit = OOMKilled.
ENTRYPOINT ["java","org.springframework.boot.loader.launch.JarLauncher"]
# ⭐ Boot 3.2+ launcher class. Pre-3.2: org.springframework.boot.loader.JarLauncher
```

### 5.2 ⭐ Go — the ~10 MB one

```dockerfile
FROM golang:1.25-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod go mod download
COPY . .
# ⭐⭐ CGO_ENABLED=0 → a STATIC binary with no libc dependency → runs on scratch
RUN --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/checkout .

FROM scratch AS runtime
# ⭐ `scratch` is EMPTY. No shell, no ls, no curl, no /etc/passwd, no CA certs.
COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/   # ⭐ needed for TLS
COPY --from=build /etc/passwd /etc/passwd                              # ⭐ so USER works
COPY --from=build /out/checkout /checkout
USER 65534:65534                       # ⭐ nobody — non-root by construction
EXPOSE 9091
ENTRYPOINT ["/checkout"]
# ⭐ RESULT: ~10 MB, ZERO packages, ZERO CVEs from the base layer.
#   ⛔ CONSEQUENCE: you cannot `kubectl exec` into it. Debug with an
#      ephemeral container: kubectl debug -it <pod> --image=busybox --target=checkout
```

### 5.3 ⭐ Python — the ~120 MB one

```dockerfile
FROM python:3.13-slim AS build
WORKDIR /app
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy
COPY --from=ghcr.io/astral-sh/uv:0.9.11 /uv /usr/local/bin/uv     # ⭐ pinned, multi-stage copy
COPY pyproject.toml uv.lock ./
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev --no-install-project
COPY . .
RUN uv sync --frozen --no-dev

FROM python:3.13-slim AS runtime
RUN groupadd -r app && useradd -r -g app app
WORKDIR /app
COPY --from=build --chown=app:app /app /app
ENV PATH="/app/.venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \                     # ⭐ logs appear immediately, not buffered
    PYTHONDONTWRITEBYTECODE=1
USER app
# ⛔ no EXPOSE — a queue consumer listens to nothing
# ⭐ a heartbeat, not an HTTP probe (§7)
CMD ["python","-m","order_worker"]
```

| | Java | Go | Python |
|---|---|---|---|
| Runtime base | `temurin:21-jre-alpine` | ⭐ **`scratch`** | `python:3.13-slim` |
| Size | ~230 MB | ⭐ ~10 MB | ~120 MB |
| CVEs from base | many | ⭐ **zero** | few |
| Shell available | ✅ `sh` | ⛔ **none** | ✅ `sh` |
| Runs as non-root | needs `adduser` | ⭐ `USER 65534` | needs `useradd` |
| Debugging | `kubectl exec` | ⭐ `kubectl debug --image=busybox` | `kubectl exec` |

---

## 6 · ⭐⭐ CD — the migration Job gates the rollout

### 6.1 ⛔ The four wrong ways

| Wrong | Why it breaks |
|---|---|
| Flyway on **application start-up** | ⭐⭐ with 3 replicas, **three** processes race. Flyway locks, two fail — and if `fail-on-error` is off they start anyway against a half-migrated schema |
| An **init container** on every pod | the same race, per pod, on every rollout |
| Migrating **after** the rollout | new code against the old schema → errors for the whole rollout |
| Letting the rollout continue when it fails | ⛔ a fleet half on the new schema, half on the old, with no signal |

### 6.2 ✅ The right way

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: shop-api-migrate
  namespace: shop-production
  labels: { app: shop-api, component: migrate }
spec:
  backoffLimit: 0                  # ⭐⭐ DO NOT RETRY. A failed migration needs
                                   #   a human, not a second attempt that may
                                   #   have half-applied the first.
  ttlSecondsAfterFinished: 86400   # ⭐ keep 24h for inspection, then clean up
  template:
    metadata: { labels: { app: shop-api, component: migrate } }
    spec:
      restartPolicy: Never         # ⭐ pairs with backoffLimit: 0
      imagePullSecrets: [{ name: acr-pull }]
      containers:
        - name: migrate
          image: shopacr.azurecr.io/shop-api@sha256:PLACEHOLDER
          # ⭐⭐ the SAME digest as the app. A different image can carry a
          #   different Flyway version and different SQL on the classpath.
          command: ["java","-cp","/app/app.jar",
                    "org.springframework.boot.loader.launch.JarLauncher"]
          args: ["--spring.flyway.enabled=true",
                 "--spring.main.web-application-type=none"]
          envFrom: [{ configMapRef: { name: shop-api-config } }]
          env:
            - name: DB_PASSWORD
              valueFrom: { secretKeyRef: { name: shop-api-db, key: password } }
          resources:
            requests: { cpu: 250m, memory: 512Mi }
            limits:   { cpu: "1",  memory: 1Gi }
```

```bash
# ⭐ THE SEQUENCE, IN ORDER — the whole of backend CD
kubectl -n shop-production delete job shop-api-migrate --ignore-not-found
kubectl -n shop-production apply  -f k8s/shop-api/migration-job.yaml
kubectl -n shop-production wait   --for=condition=complete job/shop-api-migrate \
                                  --timeout=600s \
  || { echo "⛔ migration FAILED — NOT rolling out"; \
       kubectl -n shop-production logs job/shop-api-migrate --tail=200; exit 1; }
kubectl -n shop-production set image deploy/shop-api shop-api="$REF"
kubectl -n shop-production rollout status deploy/shop-api --timeout=600s \
  || { kubectl -n shop-production set image deploy/shop-api shop-api="$PREV"; exit 1; }
# ⭐⭐ READ IT BACK
NOW=$(kubectl -n shop-production get deploy shop-api \
      -o jsonpath="{.spec.template.spec.containers[?(@.name=='shop-api')].image}")
[ "$NOW" = "$REF" ] || { echo "⛔ running $NOW, wanted $REF"; exit 1; }
```

### 6.3 ⭐ The Deployment that makes a backend rollout safe

```yaml
spec:
  revisionHistoryLimit: 10              # ⭐ 10 rollbacks available
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0                 # ⭐⭐ NEVER drop a replica before a new
                                        #   one is Ready
      maxSurge: 1
  template:
    spec:
      terminationGracePeriodSeconds: 60 # ⭐ time to drain in-flight requests
      containers:
        - name: shop-api
          startupProbe:                 # ⭐⭐ JVM warm-up: 30 × 5s = 150s
            httpGet: { path: /actuator/health/liveness, port: 8080 }
            failureThreshold: 30
            periodSeconds: 5
          readinessProbe:               # ⭐ GATES TRAFFIC
            httpGet: { path: /actuator/health/readiness, port: 8080 }
            periodSeconds: 10
            failureThreshold: 3
          livenessProbe:                # ⭐ RESTARTS A STUCK POD
            httpGet: { path: /actuator/health/liveness, port: 8080 }
            periodSeconds: 20
            failureThreshold: 3
          lifecycle:
            preStop:
              exec: { command: ["/bin/sh","-c","sleep 10"] }
              # ⭐⭐ endpoint removal is ASYNCHRONOUS. Without this the pod
              #   gets SIGTERM while kube-proxy is still routing to it →
              #   a burst of 502s on EVERY deploy. This is the most-skipped
              #   and most-valuable line in a backend manifest.
```

⭐ **`startupProbe` + `readinessProbe` + `livenessProbe` are three different things**, and conflating them is a common backend bug:
- `startupProbe` protects a **slow start** — while it is running, the other two are disabled. Without it, a 40-second JVM boot trips `livenessProbe` and Kubernetes **restart-loops the pod forever**.
- `readinessProbe` gates **traffic** — a failed probe removes the pod from endpoints. It does not restart anything.
- `livenessProbe` restarts a **stuck** pod — a deadlock or a hung thread pool. Setting it to the same path as readiness means a transient DB outage restart-loops your entire fleet, turning an outage into a much worse outage.

---

## 7 · ⭐ The worker problem — `order-worker`

**A queue consumer has no HTTP endpoint. So how does Kubernetes know it is ready?**

```
⛔ THE WRONG ANSWER: no probe at all.
   Then `rollout status` returns as soon as the pod is Running — which for a
   Python process means "the interpreter started". It may be unable to reach
   the broker, or crashed in a retry loop. The rollout reports SUCCESS.

✅ THE RIGHT ANSWER: a HEARTBEAT the worker writes, and an exec probe that
   checks it is recent.
```

```python
# order_worker/heartbeat.py
import os, time, threading
PATH = "/tmp/heartbeat"

def _beat(interval: int = 15) -> None:
    while True:
        # ⭐ touch the file ONLY when the consumer is actually healthy:
        #   connected to the broker AND not paused AND the loop is alive.
        if consumer_is_connected() and not paused():
            os.utime(PATH, None)
        time.sleep(interval)

def start() -> None:
    open(PATH, "a").close()
    threading.Thread(target=_beat, daemon=True).start()
```

```yaml
readinessProbe:
  exec:
    command:
      - /bin/sh
      - -c
      # ⭐ "the worker touched its heartbeat in the last 60 seconds"
      - test -f /tmp/heartbeat && [ $(( $(date +%s) - $(stat -c %Y /tmp/heartbeat) )) -lt 60 ]
  periodSeconds: 15
  failureThreshold: 3
livenessProbe:
  exec:
    command: ["/bin/sh","-c","test -f /tmp/heartbeat"]
  periodSeconds: 30
  failureThreshold: 6            # ⭐ more tolerant than readiness — a restart
                                 #   mid-message is expensive
```

### ⭐ The three worker-specific deploy concerns

| Concern | ⭐ What to do |
|---|---|
| **In-flight messages** | `terminationGracePeriodSeconds: 120` — long enough to *finish* processing, and the app must **stop accepting new work on SIGTERM** |
| ⭐⭐ **Idempotency is a deploy requirement** | a rolling update **will** redeliver some messages. A non-idempotent handler corrupts data on *every* deploy, canary or not |
| **A restart storm** | if the DLQ grows during a deploy, you are losing work. Gate promotion on `queue depth` and `DLQ count`, not on HTTP status |
| ⛔ **Cannot be canaried** | a canary routes 10% of *requests*. A consumer competes for *messages* — you cannot choose which, and a bad message is consumed once |

```bash
# ⭐ the worker smoke check — no HTTP, so use the broker
curl -fsS -u "$RABBIT_USER:$RABBIT_PASS" \
  http://rabbitmq.shop-production.svc:15672/api/queues/shop/orders \
  | jq '{consumers, messages_ready, messages_unacknowledged}'
# ⭐ PASS = consumers > 0 AND messages_ready is not growing.
#   A worker that connects but does not consume shows consumers=1, ready=∞.
```

---

## 8 · 🔒 Case 1 or 🤖 Case 2 — per backend

Applying the five prerequisites ([`../scenario-2-cd-only/00-delivery-vs-deployment.md`](../scenario-2-cd-only/00-delivery-vs-deployment.md) §6):

| Service | P1 reversible | P2 tests | P3 metrics | P4 digest | P5 migrations | ⭐ Verdict |
|---|---|---|---|---|---|---|
| `payment-mock` | ✅ | ✅ | ✅ | ✅ | ✅ n/a | 🤖 **Case 2 — the pilot** |
| `checkout` | ✅ | ✅ `-race` + ITs | ✅ | ✅ | ✅ n/a | 🤖 **Case 2** |
| `order-worker` | ⚠️ in-flight | ⚠️ needs a broker | ⚠️ no HTTP probe | ✅ | ✅ | 🔒 **Case 1** |
| `shop-api` | ⚠️ | ⭐ Testcontainers | ✅ | ✅ | ⛔ **until expand/contract** | 🔒 **Case 1** |

⭐ **Why `payment-mock` is the pilot:** it is the lowest-consequence service in the estate. Prove your canary, your analysis thresholds, your `abort`, your circuit breaker and your drill **there** — where being wrong costs nothing.

⭐ **Why `shop-api` is Case 1 and what would change it:** prerequisite 5. The image rolls back in seconds; the **schema does not**. Once every migration is genuinely expand/contract — additive, dual-written, and reversible by construction — `shop-api` becomes a Case 2 candidate, and the change is a flag plus a blue-green strategy (§5 of the Case 2 targets file) rather than a rewrite.

---

## 9 · 🗄️ The data tier dependency (P13)

**The backends depend on Postgres, Redis, RabbitMQ (P13). Those are 🔒 Case 1 permanently.**

| Property | Consequence |
|---|---|
| ⭐⭐ **Stateful** | a bad deploy can destroy data. There is no rollback |
| Upgrades are **one-way** | a newer server writes a data directory an older one cannot read |
| Replicas exist | upgrade one at a time, checking replication lag between |
| Backups are the real rollback | ⭐ and a backup you have never restored is a hypothesis |

```
✅ THE ONLY ACCEPTABLE SEQUENCE
   1. ⭐ TAKE AND VERIFY A BACKUP — restore it somewhere, check row counts
   2. read the release notes for the version jump
   3. upgrade a REPLICA; let it catch up; check lag == 0
   4. fail over to the upgraded replica
   5. upgrade the old primary
   6. keep the old version's binary available
   7. watch for 24h

⛔ NEVER `docker compose pull && up -d` on a Postgres service.
```

**How this affects the backends' CD:** the migration Job must be **backward-compatible with the database version currently running**, not the one you plan to upgrade to. ⭐ Sequence them: upgrade the database first (Case 1, carefully), let it soak, *then* ship the migration that uses the new feature. Never in the same release window.

---

## 10 · ▶️ Run it end to end — the acceptance checks

```bash
# ── CI: the language-specific gates actually ran ───────────────────────
# Java
grep -q 'Testcontainers\|-Dit.test' .github/workflows/ci-shop-api.yml && echo "✅ real Postgres"
grep -q 'flyway:migrate' .github/workflows/ci-shop-api.yml && echo "✅ migration shadow check"
grep -c 'H2\|hsqldb' apps/shop-api/src/test/resources/application-test.yml   # ⭐ should be 0

# Go
grep -q -- '-race' .github/workflows/ci-checkout.yml && echo "✅ race detector"
grep -q -- '-count=1' .github/workflows/ci-checkout.yml && echo "✅ test cache disabled"
grep -q 'govulncheck' .github/workflows/ci-checkout.yml && echo "✅ reachability-aware CVEs"

# Python
grep -q -- '--frozen' .github/workflows/ci-order-worker.yml && echo "✅ lockfile honoured"
grep -q 'pip-audit' .github/workflows/ci-order-worker.yml && echo "✅ CVE scan"
grep -q 'rabbitmq' .github/workflows/ci-order-worker.yml && echo "✅ real broker"

# ── CI cannot deploy; CD cannot build ──────────────────────────────────
grep -c 'kubectl\|kubeconfig' .github/workflows/ci-*.yml          # ⭐ 0
grep -cE 'docker build|mvn |go build|uv sync' .github/workflows/cd-*.yml   # ⭐ 0

# ── ⭐ THE MIGRATION GATE — prove a bad migration STOPS the pipeline ───
echo 'ALTER TABLE orders ADD COLUMN qty INT NOT NULL;' \
  > apps/shop-api/src/main/resources/db/migration/V999__bad.sql
git commit -am "drill: bad migration" && git push
# ⭐ expect: the shadow-schema CI check FAILS (existing rows have no value),
#   and if it slips through, the CD migration Job fails and NO rollout happens.
kubectl -n shop-production get deploy shop-api \
  -o jsonpath='{.spec.template.spec.containers[?(@.name=="shop-api")].image}{"\n"}'
# ⭐ must still be the PREVIOUS digest

# ── ⭐ THE ROLLOUT-SAFETY DRILL ────────────────────────────────────────
# load traffic, roll out, and count errors during the switch
hey -z 90s -c 20 http://shop-api.shop-production.svc:8080/api/v2/orders &
kubectl -n shop-production rollout restart deploy/shop-api
kubectl -n shop-production rollout status deploy/shop-api
# ⭐ WITH preStop sleep 10 + maxUnavailable 0 → zero non-200s
# ⛔ WITHOUT them → a burst of 502s exactly when each old pod terminates

# ── ⭐ the worker's readiness is real ──────────────────────────────────
kubectl -n shop-production get deploy order-worker -o jsonpath='{.spec.template.spec.containers[0].readinessProbe.exec.command}{"\n"}'
curl -fsS -u "$U:$P" http://rabbitmq.shop-production.svc:15672/api/queues/shop/orders \
  | jq '{consumers, messages_ready}'
# ⭐ consumers > 0 and messages_ready NOT growing

# ── what is running, one command, per service ──────────────────────────
for s in shop-api checkout order-worker payment-mock; do
  printf '%-14s ' "$s"
  kubectl -n shop-production get deploy "$s" \
    -o jsonpath="{.spec.template.spec.containers[?(@.name=='$s')].image}" 2>/dev/null || printf '(none)'
  echo
done
```

---

## 11 · Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| ⛔ `go test` says `(cached)` and passes instantly | Go's test cache | `-count=1` (§4.2) |
| A data race ships | no `-race` in CI | §4.2 — it is Go's best CI feature |
| ⛔ Maven rebuilds everything | no cache, or the cache key is the whole repo | `cache: maven` keyed on `pom.xml`; `dependency:go-offline` in its own layer |
| The Java image is 700 MB | the build stage leaked, or no `layertools` | §5.1 — multi-stage + layer extraction |
| ⛔ OOMKilled Java pods | a hardcoded `-Xmx` above the container limit | ⭐ `-XX:MaxRAMPercentage=75` and let the JVM read the cgroup |
| The JVM pod restart-loops on start | `livenessProbe` fires during warm-up | ⭐ add a `startupProbe` (§6.3) |
| 502s during every deploy | no `preStop` sleep; endpoint removal is async | ⭐ `preStop: sleep 10` + `maxUnavailable: 0` |
| ⛔ Flyway runs three times | `spring.flyway.enabled=true` in the app | §6.1 — a separate Job |
| The migration Job retries and half-applies | `backoffLimit` not 0 | §6.2 |
| Migration succeeds in CI, fails in production | ⛔ no shadow-schema check | §3.2 check 3 |
| ⛔ Testcontainers fails on a pod agent | no Docker daemon | §3.1 — a sidecar, Cloud, or a VM agent |
| Tests pass on H2, fail in production | H2 is not Postgres | §3 — Testcontainers |
| Python logs appear only on pod exit | output buffering | ⭐ `PYTHONUNBUFFERED=1` (§5.3) |
| `uv sync` resolves something new | no `--frozen` | §4.3 |
| ⛔ Cannot `kubectl exec` into the Go pod | `scratch` has no shell | `kubectl debug -it <pod> --image=busybox --target=checkout` |
| The worker's rollout "succeeds" but nothing consumes | no probe, or the probe only checks the process exists | §7 — a heartbeat with recency |
| ⛔ Duplicate side effects after a deploy | the handler is not idempotent | §7 — idempotency is a **deploy** requirement |
| `govulncheck` reports nothing but Trivy reports 40 CVEs | ⭐ different questions: Trivy lists *present* CVEs, govulncheck lists *reachable* ones | both are useful; act on govulncheck first |
| Trivy blocks on an unfixable nginx CVE | no `--ignore-unfixed` | a CVE with no fix is not a decision |

---

<a name="tasks--answers"></a>
## 12 · ⭐ TASKS — answers at the END

| # | Task |
|---|---|
| **T1** | Replace an H2-based `@DataJpaTest` with a real Testcontainers Postgres 17 IT, and explain the two settings that decide whether it is usable |
| **T2** | Solve Testcontainers on a Jenkins Kubernetes pod agent and state the trade-off |
| **T3** | Add the migration-shadow check (§3.2 check 3) and prove it catches something a clean-database test cannot |
| **T4** | Build the `checkout` CI with `-race`, `-count=1`, a coverage gate and `govulncheck` |
| **T5** | Build the `order-worker` CI with a real RabbitMQ and `uv sync --frozen` |
| **T6** | Write all three Dockerfiles and explain the size/CVE/debuggability trade-offs |
| **T7** | Implement the migration Job so it gates the rollout, with `backoffLimit: 0` |
| **T8** | Add `startupProbe`, `readinessProbe`, `livenessProbe` and `preStop` to `shop-api`, and run the rollout-safety drill |
| **T9** | Give `order-worker` a heartbeat-based readiness probe and a broker-based smoke check |
| **T10** | ⭐⭐ `shop-api` passes all its tests in CI and deploys green to production, where it immediately 500s on every request. List every mechanism that could produce this, in order of likelihood, with the command that confirms each |

---

# ✅ ANSWERS

**T1.** §3. `@Testcontainers` on the class, a `static` `@Container PostgreSQLContainer<>(DockerImageName.parse("postgres:17.7"))`, and `@DynamicPropertySource` wiring `PG::getJdbcUrl`/`getUsername`/`getPassword` into the Spring context. **The two settings that decide whether it is usable:** ⭐ **`static`** — a static field with `@Container` gives **one container per test class**; a non-static field gives one **per test method**, at ~2 s each, which on a 40-test class turns a 30-second suite into a two-minute one and makes people skip integration tests. ⭐ **Pinning the version** (`postgres:17.7`, ideally by digest) — an unpinned `postgres:latest` means a patch release can change your test results, and "it passed yesterday" stops being meaningful. **Why H2 is worse than nothing:** it is not Postgres — no real JSONB, no arrays, different constraint enforcement, different SQL dialect and different locking. Tests pass against it and fail in production, which makes the gate *confidently* decorative: worse than no gate, because it buys trust that is not earned.

**T2.** §3.1. Three options. ⭐ **(a) A sidecar Postgres in the pod template** — `postgres:17.7` as a container with a `pg_isready` readiness probe, tests pointed at `localhost:5432` via `@ActiveProfiles("ci-sidecar")`. Cheapest, and it is a **real** Postgres so the tests stay meaningful. ⭐ **The trade-off is isolation:** one shared database for the whole build, so tests cannot depend on ordering or exclusive state. Use `@Transactional` tests (rolled back per method) or explicit truncation between classes. **A suite with hidden ordering dependencies will produce intermittent failures that look like flakiness and are actually shared state** — and then you spend a week "fixing flakes" that are really a test-design problem. **(b) Testcontainers Cloud** — a remote daemon: real per-test isolation, no Jenkinsfile changes beyond an env var, costs money and adds an external build dependency. **(c) A VM agent with Docker** — tests run unmodified, but the agent becomes a **pet** that accumulates images, volumes and state between builds: a cache-poisoning surface and a maintenance burden. ⛔ **Never** mount `/var/run/docker.sock` into the pod to "fix" Testcontainers — that is root on the node, from a container running your dependency tree. **Recommendation:** (a) for this estate, because `shop-api`'s ITs are `@SpringBootTest` + `@Transactional`; (b) the moment isolation becomes a real requirement.

**T3.** §3.2 check 3. Nightly, take a **schema-only** dump of production (`pg_dump --schema-only`) and store it where CI can fetch it. In CI: start a Postgres, restore the snapshot, `CREATE DATABASE shadow TEMPLATE …`, then `./mvnw flyway:validate flyway:migrate -Dflyway.url=…/shadow`. **Proving it catches what a clean-DB test cannot:** add `V999__add_not_null.sql` containing `ALTER TABLE orders ADD COLUMN quantity INT NOT NULL;`. Against an **empty** database this **succeeds** — there are no rows to violate the constraint. Against the production-shaped shadow schema it **fails**, because 40 million existing rows have no value. ⭐ The same class of failure covers a `CREATE UNIQUE INDEX` over a column that contains duplicates in production, and an index build that would lock a large table for twenty minutes. **Why this is the highest-value CI step for a backend:** the migration is the one part of a release you cannot roll back, and check 1 (`flyway validate`) plus check 2 (clean database) are structurally incapable of seeing any of it. The cost is a nightly `pg_dump --schema-only` and one CI step.

**T4.** §4.2. `actions/setup-go@v6` with `go-version: '1.25.0'` and `cache-dependency-path: apps/checkout/go.sum` → `go vet ./...` + `golangci-lint` → ⭐ `go test -race -count=1 -covermode=atomic -coverprofile=cover.out ./...` → a coverage gate parsing `go tool cover -func` → `govulncheck ./...` → `CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w"`. **Why each flag matters:** `-race` is Go's killer CI feature — a data race found in CI is an incident avoided, and races are exactly the class of bug that passes every test on a quiet machine and fails under production concurrency. ⭐ `-count=1` **disables Go's test cache**: without it `go test` prints `(cached)` and exits 0 without running anything, so a green build can mean no tests executed. `-trimpath` strips build paths (reproducibility, and no leaked filesystem layout); `-s -w` strips symbols and DWARF (~30% smaller); `CGO_ENABLED=0` produces a **static** binary, which is what makes `FROM scratch` possible (§5.2). ⭐ **`govulncheck` versus Trivy:** govulncheck is **reachability-aware** — it reports only vulnerabilities in code you actually call — so it is actionable where a CVE list is noise. Keep both: act on govulncheck first, and use Trivy on the image for base-layer CVEs.

**T5.** §4.3. `actions/setup-python@v6` + `astral-sh/setup-uv@v7` with `cache-dependency-glob: apps/order-worker/uv.lock` → ⭐ `uv sync --frozen --all-extras` → `ruff check` + `ruff format --check` + `mypy` → start a **real RabbitMQ** (a service container with a `rabbitmq-diagnostics -q ping` health check, or `RabbitMqContainer` from Testcontainers-python) → `uv run pytest -q --cov --cov-fail-under=80` with `AMQP_URL` pointing at it → `pip-audit --strict` + `bandit -r src/ -ll`. ⭐ **Why `--frozen` is the important flag:** it is the Python equivalent of `npm ci` — resolve exactly what the lockfile says, and fail rather than silently choosing something newer. Without it, "works on my machine" returns and a green build no longer means a reproducible artifact. **Why a real broker rather than a mock:** `order-worker` *is* a queue consumer. Its failure modes are connection handling, acknowledgement semantics, prefetch, redelivery and DLQ behaviour — none of which a mock exercises. A mocked broker test suite is the Python equivalent of H2 for Java: confidently decorative. **`PYTHONUNBUFFERED=1` in the image** (§5.3) is the small thing people miss: without it, logs are buffered and appear only on pod exit, so `kubectl logs` during a crash shows nothing.

**T6.** §5. **Java (§5.1):** multi-stage with `dependency:go-offline` in its own layer, then ⭐ **Spring Boot `layertools` extraction** and `COPY` in dependency order (`dependencies/` → `spring-boot-loader/` → `snapshot-dependencies/` → `application/`), so the layers that rarely change stay cached. ~230 MB, many base-layer CVEs, `sh` available for debugging, and ⛔ **never set `-Xmx` by hand** — use `-XX:MaxRAMPercentage=75` so the JVM sizes itself from the cgroup limit (a hardcoded `-Xmx` above the limit means OOMKilled). **Go (§5.2):** `CGO_ENABLED=0 -trimpath -ldflags="-s -w"` then `FROM scratch`. ⭐ ~10 MB, **zero** base-layer CVEs, non-root by construction (`USER 65534`) — but `scratch` is *empty*: no shell, no `ls`, no CA certs and no `/etc/passwd`, so you must `COPY` the certificates and passwd file in, and debugging means `kubectl debug -it <pod> --image=busybox --target=checkout` rather than `kubectl exec`. **Python (§5.3):** `uv sync --frozen --no-dev` in a build stage, copy the venv into `python:3.13-slim`, `PYTHONUNBUFFERED=1`, non-root user. ~120 MB, few CVEs, shell available. ⭐ **The trade-off to state:** the Go image is 23× smaller and has no base-layer attack surface, at the cost of debuggability; the Java image is the largest and warmest (which is why it needs a `startupProbe` and why canary analysis is misleading for it); the Python image sits in between and needs an interpreter at runtime no matter what. Choose `scratch` where you can, and accept the `kubectl debug` workflow as the price.

**T7.** §6.2. A `batch/v1 Job` with ⭐ `backoffLimit: 0` and `restartPolicy: Never`, `ttlSecondsAfterFinished: 86400`, and the **same digest** as the application image. CD then runs: `delete job --ignore-not-found` → `apply` → ⭐ `kubectl wait --for=condition=complete job/shop-api-migrate --timeout=600s || exit 1` → only then `set image` → `rollout status`. **Three details make it correct:** the image must be the **same digest**, because a different image can carry a different Flyway version and different SQL on the classpath — so the migration you validated is not the one you ran. `backoffLimit: 0` because ⭐ **a failed migration needs a human, not a second attempt that may have half-applied the first**; automatic retry is how you get a schema in a state no migration file describes. And the `wait` must **fail the pipeline**, so the rollout never starts — the alternative (rolling out anyway, or treating it as a warning) leaves a fleet half on the new schema and half on the old, with no signal. **Prove it** with `V999__bad.sql` containing `ALTER TABLE orders ADD COLUMN qty INT NOT NULL;`: the CD pipeline stops at the migration, `kubectl logs job/shop-api-migrate` shows the constraint violation, and `kubectl get deploy shop-api` still shows the **previous** digest with no new ReplicaSet created. Note the Spring Boot 3.2+ launcher class is `org.springframework.boot.loader.launch.JarLauncher`; pre-3.2 it has no `.launch` segment, and getting it wrong produces a `ClassNotFoundException` that looks like a migration bug.

**T8.** §6.3. **`startupProbe`** on `/actuator/health/liveness` with `failureThreshold: 30, periodSeconds: 5` — 150 s of boot time, during which the other two probes are disabled. **`readinessProbe`** on `/actuator/health/readiness`, `periodSeconds: 10, failureThreshold: 3` — gates traffic, restarts nothing. **`livenessProbe`** on `/actuator/health/liveness`, `periodSeconds: 20, failureThreshold: 3` — restarts a stuck pod. **`preStop: exec: sleep 10`** and `terminationGracePeriodSeconds: 60`, plus `maxUnavailable: 0, maxSurge: 1` on the strategy. ⭐ **The three probes are three different things and conflating them is a real bug:** without `startupProbe` a 40-second JVM boot trips `livenessProbe` and Kubernetes **restart-loops the pod forever**; setting `livenessProbe` to the *readiness* path means a transient database outage restart-loops your entire fleet, converting an outage into a much worse one. **The drill (§10):** run `hey -z 90s -c 20` against the Service, `kubectl rollout restart`, and count non-200 responses. **With** `preStop` + `maxUnavailable: 0`: zero. **Without:** a burst of 502s exactly when each old pod terminates. ⭐ **The mechanism:** Kubernetes removes a terminating pod from Service endpoints **asynchronously** — the API server marks it terminating, and only then do kube-proxy and the ingress converge. Meanwhile the JVM has already received SIGTERM and is closing its connector, so requests arriving in that window get connection-refused. Ten seconds of `preStop` sleep costs nothing (the pod is being replaced anyway) and removes them. If your team has learned to ignore "a few 502s during deploys", this is why — and it is fixable in one line.

**T9.** §7. **The probe:** the worker writes/touches `/tmp/heartbeat` from a daemon thread — ⭐ **only when the consumer is genuinely healthy** (connected to the broker, not paused, loop alive); touching it unconditionally from a thread that never checks anything is a probe that always passes. Then `readinessProbe.exec` tests `test -f /tmp/heartbeat && [ $(( $(date +%s) - $(stat -c %Y /tmp/heartbeat) )) -lt 60 ]` — "touched within the last 60 seconds" — with `periodSeconds: 15, failureThreshold: 3`, and a **more tolerant** `livenessProbe` (`failureThreshold: 6`), because restarting mid-message is expensive. **The smoke check:** query the RabbitMQ management API for the queue and assert `consumers > 0` **and** `messages_ready` is not growing. ⭐ That second condition is the one that matters: a worker that connects but never consumes shows `consumers=1, ready=∞` and would pass an HTTP-style probe. **Three deploy concerns that follow:** `terminationGracePeriodSeconds: 120` with the app **stopping accepting new work on SIGTERM** (long enough to finish, not to start); ⭐⭐ **idempotent handlers**, because a rolling update *will* redeliver some messages, so a non-idempotent handler corrupts data on every deploy regardless of strategy; and gate promotion on **queue depth and DLQ count** rather than HTTP status. **And the structural conclusion:** `order-worker` **cannot be canaried** — a canary routes 10% of *requests*, but a consumer competes for *messages*, and you cannot choose which. That is why §8 puts it in Case 1, and why the reason is structural rather than cultural.

**T10.** ⭐⭐ Green CI, green deploy, immediate 500s on every request. **In order of likelihood:**

1. ⭐⭐ **A migration ran against the database but the code is mismatched — or did not run.** Most likely, because it is the one thing CI cannot fully see. **Confirm:** `kubectl -n shop-production get jobs -l component=migrate` (did it run? succeed?), then `flyway info` / `SELECT version, success FROM flyway_schema_history ORDER BY installed_rank DESC LIMIT 5`, then compare the schema against what the entity expects. A `PSQLException: column "quantity" does not exist` in the logs settles it.
2. ⭐ **Configuration** — the ConfigMap/Secret has the wrong value, or ⛔ **the ConfigMap changed but the pods did not restart** (env vars are read at process start, so `kubectl apply` alone changes nothing). **Confirm:** `kubectl exec deploy/shop-api -- env | grep -E 'DB_URL|SPRING_PROFILES'`, and `kubectl describe pod` for `CreateContainerConfigError`.
3. **A dependency it cannot reach** — Postgres password rotated, Redis moved, a network policy added. **Confirm:** `kubectl logs deploy/shop-api --tail=200` for connection errors; `kubectl exec` + `nc -zv postgres 5432`.
4. **The readiness probe passes while the app is broken** — ⭐ Spring Boot's `/actuator/health/readiness` returns UP based on configured indicators; if the DB indicator is not in the readiness group, a pod with no database connectivity is marked Ready and receives traffic. **Confirm:** `curl /actuator/health` and read the *components*, not the aggregate.
5. **A profile/bean wiring difference** — `SPRING_PROFILES_ACTIVE=prod` loads a configuration that tests never exercise. **Confirm:** `kubectl logs` for the "The following profiles are active" line, then reproduce locally with that profile.
6. **The wrong image is running** — `set image` with a mistyped container name succeeds silently. **Confirm:** read it back with the JSONPath **name filter** `[?(@.name=="shop-api")]`. ⭐ This is CHECK 4, and it exists for exactly this.
7. **A JVM/container mismatch** — OOMKilled or restart-looping. **Confirm:** `kubectl get pods` for `RESTARTS` and `kubectl describe pod | grep -A3 'Last State'` → `OOMKilled`.

**The general lesson worth stating:** for a backend, **"the deploy succeeded" means the pods are Ready, and Ready means the readiness probe passed — nothing more.** The gap between "Ready" and "correct" is schema, configuration and dependencies, which is exactly what CI's integration tests, the migration-shadow check and the readiness-indicator configuration exist to close. ⭐ **And the fix that prevents recurrence:** make the CD smoke test hit a **real business endpoint that touches the database**, not `/actuator/health`. A `GET /api/v2/orders` returning 200 proves the schema, the configuration, the connection pool and the wiring in one request — which is why every file in this folder puts "smoke a business endpoint, not just the probe path" in bold.

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish_Kumar_Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn: https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260
🔗 GitHub: https://github.com/3558Bhk

*"Ready" means the probe passed. Smoke a business endpoint, or you have verified nothing.*

</div>
