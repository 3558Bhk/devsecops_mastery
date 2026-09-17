# CI/CD Concepts - SDE3

## CI - Continuous Integration
- Developers frequently merge code to main (daily), automated build + test
- Goals: Find bugs early, reduce integration pain
- Practices:
  - Single source repo, automated build, self-testing build, daily commits, fast builds (<10 min), test in clone prod env, easy to get latest, visible build status

## CD - Continuous Delivery vs Deployment

- **Continuous Delivery**: Code always in deployable state, manual approval to deploy to prod (human gate). Every commit can be released.
- **Continuous Deployment**: Every commit that passes pipeline auto deployed to prod, no human gate. Need high test coverage + monitoring + feature flags.

## Pipeline Stages (Typical)

1. **Source**: Git checkout (webhook triggers)
2. **Build**: Compile, package (Maven `mvn package`, Docker build)
3. **Unit Test**: JUnit, Jest, fast, mock
4. **Code Quality**: SonarQube, lint, security scan (Snyk, Trivy for images)
5. **Integration Test**: Testcontainers, API tests
6. **Artifact**: Push to registry (Nexus, Artifactory, ECR, DockerHub)
7. **Deploy to Dev**: Auto deploy to dev env, smoke tests
8. **Deploy to Staging**: Manual or auto, E2E tests, performance tests
9. **Approval**: Manual gate for prod
10. **Deploy to Prod**: Blue-green/canary/rolling
11. **Post-deploy**: Health checks, monitoring, smoke, rollback if needed

## Jenkins Pipeline Example (Declarative)

```groovy
pipeline {
  agent any
  environment {
    DOCKER_REGISTRY = 'my-registry.com'
    IMAGE = "${DOCKER_REGISTRY}/myapp:${BUILD_NUMBER}"
  }
  stages {
    stage('Checkout') { steps { checkout scm } }
    stage('Build & Test') {
      parallel {
        stage('Backend') { steps { sh 'mvn clean test' } }
        stage('Frontend') { steps { sh 'npm ci && npm test' } }
      }
    }
    stage('Sonar') { steps { withSonarQubeEnv('sonar') { sh 'mvn sonar:sonar' } } }
    stage('Docker Build & Push') {
      steps {
        script {
          docker.build(IMAGE).push()
        }
      }
    }
    stage('Deploy Dev') {
      when { branch 'develop' }
      steps { sh 'kubectl set image deployment/myapp myapp=${IMAGE} -n dev' }
    }
    stage('Deploy Prod') {
      when { branch 'main' }
      input { message "Deploy to prod?" }
      steps { sh 'kubectl set image deployment/myapp myapp=${IMAGE} -n prod' }
    }
  }
  post {
    always { junit '**/target/surefire-reports/*.xml'; cleanWs() }
    failure { slackSend channel: '#alerts', message: "Build ${BUILD_NUMBER} failed" }
  }
}
```

## GitHub Actions Example

```yaml
name: CI/CD
on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with: {java-version: '17', distribution: 'temurin'}
      - run: mvn clean test
      - uses: sonarqube/scan-action@v2
      - name: Build Docker
        run: |
          docker build -t myapp:${{ github.sha }} .
          docker push myapp:${{ github.sha }}
  deploy:
    needs: build
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    environment: prod
    steps:
      - run: kubectl set image deployment/myapp myapp=myapp:${{ github.sha }}
```

## Deployment Strategies Recap

### Rolling
- Gradually replace old pods with new, K8s default `maxUnavailable 25%, maxSurge 25%`
- Pros: No extra infra, zero downtime
- Cons: Two versions coexist briefly, no instant rollback

### Blue-Green
- Two identical envs, switch traffic via LB
- Pros: Instant rollback, no version mix
- Cons: Double infra cost

### Canary
- New version to small subset (5% traffic), monitor metrics (error rate, latency), increase gradually
- Tools: Argo Rollouts, Flagger, Istio traffic splitting
- Pros: Safe, catch issues early
- Cons: Complex

### Feature Flags
- Deploy code disabled, enable via config/flag service (LaunchDarkly)
- Pros: Trunk based development, test in prod with internal users, instant off
- Cons: Tech debt if flags not cleaned

## Best Practices SDE3

1. **Fail Fast**: Fast unit tests first, slow E2E later
2. **Immutable Artifacts**: Build once, deploy same artifact across envs (only config changes)
3. **Configuration Externalized**: Env vars, ConfigMaps, not hardcoded
4. **Automated Tests**: Unit > Integration > E2E pyramid, coverage >80% for critical
5. **Small Commits**: Easier to review, rollback, bisect
6. **Trunk Based Development**: Short-lived branches <2 days, feature flags over long branches
7. **Observability**: Logs, metrics, traces after deploy
8. **Rollback Plan**: Always have rollback automated, DB migrations backward compatible (expand-contract pattern)
9. **Security**: Scan dependencies, secrets, images (Trivy, Snyk, Dependabot), no secrets in code
10. **Infrastructure as Code**: Terraform for infra, Helm for K8s, versioned

## DB Migrations in CI/CD

- Tool: Flyway, Liquibase
- Practices:
  - Migrations versioned, applied automatically on deploy
  - Backward compatible: Add column nullable first, then backfill, then make not null (expand-contract)
  - Never drop column in same release as code that stops using it, do in next release

## Monitoring Pipeline

- Metrics: Build duration, success rate, MTTR (Mean Time To Recovery), deployment frequency, change failure rate (DORA metrics)
- DORA Elite: Multiple deploys per day, <1hr lead time, <15% failure rate, <1hr MTTR

## Interview Q: How to achieve zero downtime deployment?

- App: Graceful shutdown (handle SIGTERM, finish ongoing requests, K8s `terminationGracePeriodSeconds`)
- LB: Health checks, readiness probe
- DB: Backward compatible migrations
- Rolling or Blue-Green
- Session: Externalize to Redis so any pod can handle

## GitOps

- Git as single source of truth for infra and app deployment
- Tools: ArgoCD, Flux
- Flow: Dev pushes code -> CI builds image -> CI updates git manifest repo with new image tag -> ArgoCD detects git change -> syncs to K8s cluster
- Benefits: Audit, rollback via git revert, drift detection

## Secrets Management in CI/CD

- Don't store secrets in Jenkinsfile or git
- Use: Jenkins credentials, GitHub Secrets, Vault, AWS Secrets Manager, Sealed Secrets for K8s
- Scan: git-secrets, TruffleHog
