# AWS Core Services Quick Notes

## IAM
- Users, Groups, Roles, Policies (JSON)
- Policy types: Identity based, Resource based (S3 bucket policy)
- Best practice: No root use, MFA, least privilege, roles for EC2/Lambda not access keys
- STS AssumeRole for cross-account

## EC2 Auto Scaling
- Launch Template + ASG + Scaling policies (target tracking, scheduled, predictive)
- Health checks: EC2 + ELB

## S3 Deep
```bash
aws s3 ls
aws s3 cp file.txt s3://bucket/
aws s3 sync ./dist s3://my-bucket --delete
# Presigned URL
aws s3 presign s3://bucket/file.txt --expires-in 3600
```

## CloudFront
- Edge locations, cache behaviors, origin S3/ALB
- Invalidation: `/*`

## RDS
- Backup automated 7-35 days, manual snapshots
- Multi-AZ sync standby for failover, Read Replica async for scaling
- Parameter groups, subnet groups

## DynamoDB
- PK + optional SK
- RCU/WCU or On-Demand
- GSI: Different PK/SK, eventually consistent
- LSI: Same PK different SK, strongly consistent, only at creation
- Streams + Lambda trigger
- DAX cache

## Lambda Deep
- Environment variables, Layers, VPC config (needs NAT for internet)
- Concurrency limit per account 1000, reserved concurrency
- X-Ray tracing

## SQS
- Standard (at-least-once, unordered) vs FIFO (exactly-once, ordered, 300 TPS)
- Visibility timeout, DLQ after max receives
- Long polling (20 sec) vs short

## SNS
- Pub/Sub, fanout to SQS, Lambda, HTTP, email, SMS
- Topic

## Kinesis vs SQS
- Kinesis: Real-time streaming, replay, ordered per shard, retention 1-365 days
- SQS: Queue, no replay, retention 14 days

## EKS
- Managed control plane, worker nodes EC2/Fargate
- Fargate: Serverless nodes

## Important Ports Recap for Cloud
- SG example: Allow 80,443 from 0.0.0.0/0, 22 from your IP only, 3306 from app SG only (not 0.0.0.0)
