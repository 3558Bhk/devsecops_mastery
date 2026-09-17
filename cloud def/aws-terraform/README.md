# Terraform on AWS — Interview Questions

Terraform interview prep for **AWS**, split into small topic files. Every file follows the same structure:

- **Case A — Basic** (15 questions): fundamentals, workflow, syntax.
- **Case B — Advanced / Senior** (12 questions): internals, tradeoffs, state, modules.
- **Case C — Scenario** (6 questions): real-world situations with expected answers.
- A **reading-time estimate** in the header (200 wpm basis).

Every question includes a **full model answer**.

## Structure

```
aws-terraform/
├── core/                 → HCL, workflow, state, variables, modules, workspaces, CI/CD
├── networking/           → VPC, SGs/NACLs, load balancers, Route 53 + CloudFront
├── compute/              → EC2 + Auto Scaling, Lambda, ECS, EKS
├── storage-databases/    → S3, RDS + DynamoDB
├── identity-security/    → IAM
└── monitoring-messaging/ → SQS/SNS/EventBridge, CloudWatch + alerts
```

## Index

| Group | File | Topic |
|---|---|---|
| Core | `core/terraform-basics.md` | HCL, init/plan/apply/destroy, resources, data sources |
| Core | `core/providers.md` | AWS provider config, regions, aliases, assume role |
| Core | `core/state-management.md` | State file, S3 backend, DynamoDB locking, import/taint/moved |
| Core | `core/variables-outputs-locals.md` | Variables, tfvars, outputs, locals, validation |
| Core | `core/modules.md` | Module structure, registry, versioning, composition |
| Core | `core/workspaces-environments.md` | Workspaces vs folder strategies, env separation |
| Core | `core/ci-cd.md` | Terraform in pipelines (GitHub Actions/Jenkins), plan/apply gates |
| Networking | `networking/vpc-networking.md` | VPC, subnets, route tables, IGW/NAT, endpoints, peering |
| Networking | `networking/security-groups-nacls.md` | Security group rules, NACLs, ingress/egress |
| Networking | `networking/load-balancers.md` | ALB, NLB, target groups, listeners |
| Networking | `networking/route53-cloudfront.md` | DNS zones/records, ACM, CloudFront |
| Compute | `compute/ec2-autoscaling.md` | EC2, AMI, launch templates, ASG, user data |
| Compute | `compute/lambda-serverless.md` | Lambda, IAM role, API Gateway, permissions |
| Compute | `compute/ecs.md` | ECS cluster, task definition, Fargate |
| Compute | `compute/eks.md` | EKS cluster, node groups, IRSA |
| Storage & DB | `storage-databases/s3.md` | Buckets, versioning, lifecycle, encryption, replication |
| Storage & DB | `storage-databases/rds-dynamodb.md` | RDS + DynamoDB, subnets groups, multi-AZ |
| Identity | `identity-security/iam.md` | IAM users/roles/policies, instance profiles, OIDC |
| Messaging | `monitoring-messaging/messaging.md` | SQS, SNS, EventBridge |
| Monitoring | `monitoring-messaging/monitoring-alerts.md` | CloudWatch alarms/dashboards, CloudTrail, alerts |
