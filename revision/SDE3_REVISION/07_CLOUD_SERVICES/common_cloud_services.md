# Common Cloud Services - AWS / Azure / GCP Mapping

## Core Services Cheat Sheet

| Category | AWS | Azure | GCP | What it does |
|----------|-----|-------|-----|--------------|
| Compute VM | EC2 | Virtual Machines | Compute Engine | Virtual servers |
| Containers | ECS, EKS | AKS | GKE | Kubernetes |
| Serverless | Lambda | Functions | Cloud Functions | FaaS |
| App Platform | Elastic Beanstalk | App Service | App Engine | PaaS |
| Storage Object | S3 | Blob Storage | Cloud Storage | File storage |
| Block Storage | EBS | Managed Disks | Persistent Disk | Disk for VM |
| File Storage | EFS | Files | Filestore | NFS |
| DB Relational | RDS (MySQL/PG) | SQL Database | Cloud SQL | Managed SQL |
| DB NoSQL | DynamoDB | Cosmos DB | Firestore/Bigtable | NoSQL |
| Cache | ElastiCache Redis | Redis Cache | Memorystore | Redis |
| Networking | VPC | VNet | VPC | Isolated network |
| Load Balancer | ALB/NLB | Load Balancer | Cloud LB | Distribute traffic |
| CDN | CloudFront | CDN | Cloud CDN | Cache edge |
| DNS | Route53 | DNS | Cloud DNS | Domain |
| API Gateway | API Gateway | API Management | Apigee | Manage APIs |
| Messaging Queue | SQS | Queue Storage | Pub/Sub | Queue |
| Streaming | Kinesis | Event Hubs | Pub/Sub / Dataflow | Stream |
| CI/CD | CodePipeline | DevOps | Cloud Build | CI/CD |
| Monitoring | CloudWatch | Monitor | Operations | Logs/metrics |
| IAM | IAM | AD | IAM | Auth |
| Secrets | Secrets Manager | Key Vault | Secret Manager | Secrets |
| IaC | CloudFormation | ARM/Bicep | Deployment Manager | Infra as code |

## Must Know AWS Services Deep (Most Asked)

### EC2
- Types: t3.micro (burstable), m5 (general), c5 (compute), r5 (memory), p3 (GPU)
- Purchase: On-Demand, Reserved (1-3yr discount 40-60%), Spot (90% cheap, can be terminated)
- EBS: gp3, io2, st1
- AMI, Security Group, Key Pair

### S3
- 11 9's durability
- Classes: Standard, IA, One Zone IA, Glacier, Intelligent Tiering
- Versioning, Encryption SSE-S3/KMS, Lifecycle policy
- No folders, keys, eventual consistency
- Presigned URLs for temporary access

### RDS vs Aurora vs DynamoDB
- RDS: MySQL/PG managed, Multi-AZ for HA, Read Replica
- Aurora: AWS proprietary MySQL/PG compatible, 5x faster, auto scale storage
- DynamoDB: NoSQL key-value, single digit ms, on-demand or provisioned, GSI/LSI

### Lambda
- Max 15 min timeout, 10GB RAM, 512MB tmp
- Cold start problem: Provisioned concurrency, keep warm, use Node/Python fast start
- Trigger: API Gateway, SQS, S3, DynamoDB Stream, EventBridge

### VPC
- CIDR e.g. 10.0.0.0/16
- Subnets: Public (IGW) + Private (NAT Gateway)
- Security Group stateful, NACL stateless
- VPC Peering, Transit Gateway

### Load Balancers
- ALB: Layer 7 HTTP, path/host routing, target groups
- NLB: Layer 4 TCP/UDP ultra high perf
- CLB: Legacy

### CloudWatch
- Metrics, Logs, Alarms, Dashboard, Events (EventBridge)

## Common Architecture Patterns

### 1. 3-Tier Web App on AWS
```
Route53 -> CloudFront -> ALB -> EC2 AutoScaling (Node/Java) -> RDS Multi-AZ
                           -> S3 for assets
                           -> ElastiCache Redis for session/cache
```

### 2. Serverless
```
API Gateway -> Lambda -> DynamoDB
             -> S3
CloudFront + S3 static hosting
```

### 3. Microservices on EKS
```
Route53 -> ALB Ingress -> EKS (Istio service mesh) -> Microservices pods
-> RDS Aurora, ElastiCache, SQS/Kafka (MSK)
-> ECR for images, CloudWatch + X-Ray tracing
```

## Cost Optimization Tips (Interview Bonus)
- Right sizing, Spot instances, Reserved, S3 lifecycle to Glacier, Auto Scaling, turn off dev env nights

## Well-Architected Pillars
- Operational Excellence, Security, Reliability, Performance Efficiency, Cost Optimization, Sustainability
