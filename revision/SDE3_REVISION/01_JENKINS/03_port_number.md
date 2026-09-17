# Port Numbers - Complete Revision for SDE3

## Jenkins Specific
- **8080** - Default HTTP web UI
- **50000** - JNLP / Agent communication (TCP)
- **8443** - HTTPS if configured

> Change port: `sudo nano /etc/default/jenkins` -> HTTP_PORT=9090
> Or `java -jar jenkins.war --httpPort=9090`

## Most Frequently Asked Ports in Interview

### Web & Application
| Service | Port | Protocol |
|---------|------|----------|
| HTTP | 80 | TCP |
| HTTPS | 443 | TCP |
| Jenkins | 8080 | TCP |
| Tomcat | 8080 / 8443 | TCP |
| Node.js default | 3000 | TCP |
| React/Vite | 3000 / 5173 | TCP |
| Angular | 4200 | TCP |

### Databases
| DB | Port |
|----|------|
| MySQL | 3306 |
| PostgreSQL | 5432 |
| MongoDB | 27017 |
| Redis | 6379 |
| Cassandra | 9042 |
| Elasticsearch | 9200 / 9300 |
| Oracle | 1521 |
| SQL Server | 1433 |

### DevOps Tools
| Tool | Port |
|------|------|
| Docker Daemon | 2375 / 2376 |
| Kubernetes API | 6443 |
| Kubelet | 10250 |
| etcd | 2379-2380 |
| Grafana | 3000 |
| Prometheus | 9090 |
| SonarQube | 9000 |
| Nexus | 8081 |
| GitLab | 80 / 443 / 22 |

### Messaging & Others
| Service | Port |
|---------|------|
| Kafka | 9092 |
| Zookeeper | 2181 |
| RabbitMQ | 5672 / 15672 UI |
| SSH | 22 |
| FTP | 21 / 20 |
| SMTP | 25 / 587 |
| DNS | 53 |
| LDAP | 389 / 636 |

### How to Check Ports?
```bash
netstat -tulpn | grep 8080
lsof -i :8080
ss -tulpn
sudo ufw allow 8080
# Kill process on port
sudo kill -9 $(lsof -t -i:8080)
```

> Interview Tip: If Jenkins 8080 conflicts with Tomcat, change one. Mention `netstat` check.
