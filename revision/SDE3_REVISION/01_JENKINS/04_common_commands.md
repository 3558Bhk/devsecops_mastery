# Jenkins Common Commands / Groovy

## CLI Commands
```bash
# Download CLI jar
wget http://localhost:8080/jnlpJars/jenkins-cli.jar

# List jobs
java -jar jenkins-cli.jar -s http://localhost:8080 -auth admin:token list-jobs

# Build job
java -jar jenkins-cli.jar -s http://localhost:8080 -auth admin:token build my-job

# Reload config
java -jar jenkins-cli.jar -s http://localhost:8080 reload-configuration
```

## Pipeline DSL Must-Know
```groovy
pipeline {
 agent any
 environment { ENV = 'prod' }
 parameters { string(name: 'BRANCH', defaultValue: 'main') }
 triggers { cron('H */4 * * *') }
 options { timeout(time: 30, unit: 'MINUTES'); buildDiscarder(logRotator(numToKeepStr: '10')) }
 stages {
  stage('Build'){ steps { sh 'mvn clean package' } }
  stage('Parallel'){ parallel {
   stage('Unit'){ steps { sh 'mvn test' } }
   stage('Lint'){ steps { sh 'npm run lint' } }
  }}
 }
 post { success { echo 'Done'} failure { mail to: 'team@x.com', subject: 'Failed' } }
}
```

## Useful sh steps
- `sh 'docker build -t app .'` 
- `withCredentials([string(credentialsId: 'secret', variable: 'TOKEN')]){ sh 'echo $TOKEN' }`
- `withDockerRegistry([credentialsId: 'dockerhub']) { }`

## System Management
```bash
sudo systemctl restart jenkins
sudo systemctl stop jenkins
sudo journalctl -u jenkins -f
```

## Backup
```bash
tar -czvf jenkins-backup.tar.gz /var/lib/jenkins/
# Thin backup plugin does same
```
