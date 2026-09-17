# Jenkins - Common Plugins (SDE3 Must Know)

## Top 30 Most Used Plugins

### 1. Pipeline & Build
- **Pipeline** - Jenkinsfile as code
- **Blue Ocean** - Modern UI for pipeline
- **Build Pipeline** - Visualize build chain
- **Parameterized Trigger** - Trigger other jobs

### 2. Source Control
- **Git Plugin / GitHub Plugin / GitLab Plugin / Bitbucket**
- **GitHub Branch Source** - Multibranch pipeline
- **SCM API** - Base for all SCM

### 3. Build Tools
- **Maven Integration**
- **Gradle Plugin**
- **NodeJS Plugin**
- **Docker Plugin / Docker Pipeline**

### 4. Testing & Quality
- **JUnit Plugin** - Test reports
- **JaCoCo / Cobertura** - Code coverage
- **SonarQube Scanner**
- **HTML Publisher**

### 5. Deployment & Infra
- **Kubernetes Plugin** - Dynamic agents on K8s
- **Amazon EC2 Plugin** - Agents on EC2
- **Ansible Plugin**
- **Deploy to container**

### 6. Notifications & Security
- **Email Extension (emailext)**
- **Slack Notification**
- **Credentials Binding / Credentials Plugin**
- **Role-based Authorization Strategy**
- **LDAP / Active Directory**

### 7. Utilities
- **Timestamper**
- **Workspace Cleanup**
- **Throttle Concurrent Builds**
- **Job DSL** - Seed jobs

> Interview Tip: Explain plugin for your use case: GitHub Branch Source + Docker Pipeline + K8s Plugin + SonarQube + Slack = Modern CI/CD

## How plugins installed?
Manage Jenkins > Manage Plugins > Available > Install without restart
Or via Groovy/JCasC: `jenkins.plugins`

## Jenkinsfile example using plugins
```groovy
pipeline {
 agent { kubernetes { yamlFile 'pod.yaml' } }
 tools { nodejs 'Node18' }
 stages {
  stage('Checkout'){ steps { git url: '...' } }
  stage('Test'){ steps { sh 'npm test'; junit 'reports/*.xml' } }
  stage('Sonar'){ steps { withSonarQubeEnv('sonar'){ sh 'sonar-scanner' } } }
  stage('Docker'){ steps { docker.build("app:${BUILD_NUMBER}").push() } }
 }
 post { always { slackSend color: 'good', message: "Build ${BUILD_NUMBER}" } }
}
```
