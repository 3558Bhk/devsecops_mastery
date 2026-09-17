# Jenkins Installation Steps - All Methods

## 1. Prerequisites
- Java 17 or 21 (Jenkins 2.479+ requires Java 17+)
- 2GB RAM min, 4GB recommended
- 10GB Disk

## 2. On Ubuntu/Debian (Most Common Interview Answer)
```bash
sudo apt update
sudo apt install fontconfig openjdk-17-jre -y
sudo wget -O /usr/share/keyrings/jenkins-keyring.asc https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" | sudo tee /etc/apt/sources.list.d/jenkins.list
sudo apt update
sudo apt install jenkins -y
sudo systemctl enable jenkins
sudo systemctl start jenkins
sudo systemctl status jenkins
# Get initial password
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```

## 3. Docker (Fastest for Dev)
```bash
docker run -d --name jenkins -p 8080:8080 -p 50000:50000 \
 -v jenkins_home:/var/jenkins_home \
 jenkins/jenkins:lts-jdk17

# With Docker-in-Docker
docker run -d --name jenkins -p 8080:8080 -p 50000:50000 \
 -v /var/run/docker.sock:/var/run/docker.sock \
 -v jenkins_home:/var/jenkins_home jenkins/jenkins:lts-jdk17
```

## 4. Kubernetes (Helm - Production)
```bash
helm repo add jenkins https://charts.jenkins.io
helm repo update
helm install jenkins jenkins/jenkins -n jenkins --create-namespace \
 --set controller.adminPassword=admin \
 --set controller.serviceType=LoadBalancer
kubectl get svc -n jenkins
```

## 5. WAR File (Old method)
```bash
wget https://get.jenkins.io/war-stable/2.479.1/jenkins.war
java -jar jenkins.war --httpPort=8080
```

## 6. Post Installation
1. Open http://localhost:8080
2. Paste initialAdminPassword
3. Install Suggested Plugins
4. Create Admin User
5. Configure URL
6. Setup Agents: Manage Jenkins > Nodes > New Node

## 7. JCasC (Configuration as Code) - SDE3 Level
```yaml
jenkins:
  systemMessage: "Jenkins configured via JCasC"
  numExecutors: 0
securityRealm:
  local:
    allowsSignup: false
```
Path: Manage Jenkins > Configuration as Code

## Common Locations
- Home: `/var/lib/jenkins`
- Logs: `/var/log/jenkins/jenkins.log`
- Config: `/var/lib/jenkins/config.xml`
- Jobs: `/var/lib/jenkins/jobs/`
