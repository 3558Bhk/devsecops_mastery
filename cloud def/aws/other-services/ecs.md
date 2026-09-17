# Amazon ECS — Interview Questions

> **Cloud:** AWS (Other Services) · **Category:** Compute / Containers · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~9 min

---

## JSON File Format

ECS's signature JSON is the **task definition** — the blueprint for containers, networking, roles, and secrets.

```json
{
  "family": "web-app",
  "networkMode": "awsvpc",
  "executionRoleArn": "arn:aws:iam::111122223333:role/ecsTaskExecutionRole",
  "taskRoleArn": "arn:aws:iam::111122223333:role/appRole",
  "cpu": "512",
  "memory": "1024",
  "containerDefinitions": [{
    "name": "web",
    "image": "111122223333.dkr.ecr.us-east-1.amazonaws.com/web:1.0",
    "portMappings": [{ "containerPort": 8080, "protocol": "tcp" }],
    "secrets": [{ "name": "DB_PASSWORD", "valueFrom": "arn:aws:secretsmanager:us-east-1:111122223333:secret:db" }]
  }]
}
```

**Key fields:** `family` · `networkMode` (awsvpc/bridge/host) · `taskRoleArn` (app permissions) vs `executionRoleArn` (pull images/logs/secrets) · `containerDefinitions[]` (image, portMappings, environment, secrets) · `cpu`/`memory`.


## Case A — Basic

**A1. What is Amazon ECS?**
**Answer:** A fully managed **container orchestration** service for running Docker containers on AWS — managing the scheduling, placement, networking, and scaling of containers across EC2 or Fargate.

**A2. What are the core ECS components?**
**Answer:** **Cluster** (logical group of compute), **task definition** (container blueprint), **task** (a running instance of a task definition), **service** (maintains desired task count), **container agent** (on EC2), and **launch types** (EC2 / Fargate).

**A3. What is a task definition?**
**Answer:** A JSON blueprint defining container images, CPU/memory, environment variables, port mappings, IAM roles, logging, and networking for one or more containers that run together.

**A4. What is a task vs a service?**
**Answer:** A **task** is a single run of a task definition (like a container instance). A **service** ensures N tasks are always running (replacing failed ones), often behind a load balancer.

**A5. What are the two launch types?**
**Answer:** **EC2** (you manage the instance fleet; more control, often cheaper at steady state) and **Fargate** (serverless — AWS manages the compute, pay per task).

**A6. What is Fargate?**
**Answer:** The serverless launch type for ECS/EKS — you specify CPU/memory per task and AWS runs the infrastructure; no EC2 instances to manage.

**A7. What is the ECS agent?**
**Answer:** A process on each EC2 container instance that communicates with the ECS control plane to register the instance and run/stop containers.

**A8. What is a container image and where are they stored?**
**Answer:** The packaged application + dependencies, stored in a registry like **Amazon ECR** (Elastic Container Registry) and referenced by the task definition.

**A9. How does ECS networking work?**
**Answer:** Tasks can use **bridge**, **host**, or (recommended) **awsvpc** networking — awsvpc gives each task its own **ENI** and private IP, integrating with security groups, VPC routing, and load balancers.

**A10. What is a service discovery integration?**
**Answer:** ECS integrates with **AWS Cloud Map** so services can discover each other by DNS name instead of hardcoded endpoints.

**A11. What is a load balancer integration in ECS?**
**Answer:** An **ALB/NLB** (via target groups) fronts a service; tasks register/deregister automatically, and health checks drive traffic + task replacement.

**A12. What is a task role vs task execution role?**
**Answer:** **Task role** = permissions for the application code (e.g., access S3). **Execution role** = permissions ECS needs to run the task (pull images from ECR, write logs to CloudWatch, fetch secrets).

**A13. How does ECS differ from EC2-based app hosting?**
**Answer:** ECS orchestrates containers (scheduling, scaling, self-healing, placement) rather than managing VMs directly — better density, faster deploys, and declarative desired-state management.

**A14. What is a capacity provider?**
**Answer:** The link between a cluster and its compute (ASG for EC2, or FARGATE), defining how capacity is provisioned and scaled for tasks.

**A15. How does ECS differ from EKS?**
**Answer:** ECS is AWS-native orchestration (simpler, no control plane to manage). EKS is managed **Kubernetes** (portable, rich ecosystem, more complex). Choose ECS for simplicity/AWS-native; EKS for K8s portability/ecosystem.

---

## Case B — Advanced (Senior)

**B1. Explain ECS service scaling: desired count, target tracking, and how it interacts with cluster capacity.**
**Answer:** A service maintains the **desired count** of tasks. **Application Auto Scaling** (target tracking on CPU/memory/ALB request count or custom metrics) adjusts desired count. On EC2 launch type, the **capacity provider/ASG** must scale instances too (via capacity provider managed scaling), or tasks can't be placed. On Fargate, capacity is serverless (no instance scaling needed).

**B2. What is a rolling update vs blue-green vs canary deployment in ECS (CodeDeploy)?**
**Answer:** **Rolling**: replace tasks gradually (min/max healthy %). **Blue-green**: create a new task set, shift traffic via the ALB, then retire the old (with auto-rollback). **Canary**: shift a small % of traffic to new tasks first. CodeDeploy orchestrates blue-green/canary with ALB target groups — safer for risky changes.

**B3. How does awsvpc networking work, and what are ENI limits and security implications?**
**Answer:** Each task gets an **ENI** with its own IP, security group, and routing — enabling per-task isolation, SG rules, and direct LB integration. Limits: ENIs per instance (EC2 launch type) constrain task density (mitigate with `awsvpcTrunking`/larger instances); Fargate has per-task ENI limits. Design SGs per service for least privilege.

**B4. How do you manage secrets and config in ECS (SSM Parameter Store, Secrets Manager, AppConfig)?**
**Answer:** Inject via task definition `secrets`/`environmentFiles` referencing **Secrets Manager** or **SSM Parameter Store** (the execution role needs read access). Values are resolved at container start, keeping secrets out of images/code. For dynamic config, use AppConfig. Never bake secrets into images.

**B5. How does ECS health checking and self-healing work (container health checks, LB health checks)?**
**Answer:** Task definitions support **container health checks** (Docker HEALTHCHECK) for per-container health; services behind an **ALB** use target-group health checks. ECS restarts unhealthy containers and replaces tasks failing LB checks, keeping the desired count healthy. Tune grace periods to avoid flapping during startup.

**B6. Compare EC2 vs Fargate launch types: cost, control, and operational tradeoffs.**
**Answer:** EC2 = you manage/patch instances, can use reserved/spot pricing, supports daemon scheduling, GPU/specialized instances, and higher density — more ops. Fargate = no instance management, per-task pricing, fast scale, simpler security (per-task ENI/SG) — slightly higher unit cost at steady state. Use EC2 for predictable baselines + specialized needs; Fargate for variable/ops-light workloads.

**B7. How do you design logging and monitoring for ECS (awslogs, FireLens, Container Insights)?**
**Answer:** Use the `awslogs` driver (or **FireLens** to route to Fluent Bit → CloudWatch/OpenSearch/third-party) for container logs. Enable **Container Insights** for cluster/task CPU-memory-network metrics. Alarm on task restarts, memory/CPU saturation, and service steady-state breaches. Use X-Ray for tracing.

**B8. What is task placement strategy and how do you influence it (constraints, spread, binpack)?**
**Answer:** Placement strategies: **binpack** (least available CPU/memory — maximize density), **spread** (distribute across instances/AZs — for HA), **random**. Combine strategies and add **constraints** (e.g., distinctInstance). Default is spread across AZs then binpack. Understanding this helps balance cost vs resilience on EC2.

**B9. How does ECS Service Connect / Cloud Map service discovery work, and when to use it vs an ALB?**
**Answer:** **Service Connect** (or Cloud Map) gives services stable DNS names + mutual TLS + metrics for **service-to-service** (east-west) traffic without a load balancer. Use an ALB for **north-south** (external) traffic. Combining both is the typical microservices pattern.

**B10. What is capacity provider managed scaling, and how does it keep EC2 clusters elastic?**
**Answer:** The capacity provider scales the **ASG** automatically based on pending task demand (target capacity %) — adding instances when tasks can't be placed and scaling in when idle. This closes the gap between task-level autoscaling and instance-level capacity on EC2 launch type.

**B11. How do you do zero-downtime deployments with connection draining in ECS?**
**Answer:** Set **deployment configuration** (minimumHealthyPercent=100, maximumPercent=200) so new tasks are healthy before old ones are deregistered, and the ALB's **deregistration delay** drains in-flight requests. For stricter control, use CodeDeploy blue-green with traffic shifting and automatic rollback on alarm.

**B12. How do you secure ECS end-to-end?**
**Answer:** IAM roles (task vs execution, least privilege), **secrets via Secrets Manager/SSM**, private subnets + SGs per service, **ECR** image scanning (Inspector) + image immutability, signed images, no `latest` tags, read-only root filesystem + non-root user, encrypted EBS/EFS, CloudTrail for API audit, and runtime protection (GuardDuty ECS protection). 

---

## Case C — Scenario

**C1. Scenario:** A containerized web app needs to scale with traffic, be highly available, and cost-efficient.
**Question:** Design the ECS architecture.
**Expected answer:** **Fargate** service (or EC2 with capacity provider) behind an **ALB** (target group per service), task definition with health checks, **target-tracking autoscaling** on CPU/requests, multi-AZ subnets, secrets in Secrets Manager, images in ECR with scanning, logs to CloudWatch, and per-service security groups. Use Service Connect for internal calls.

**C2. Scenario:** A service scales out (more tasks) but tasks fail to start with "insufficient resources" on an EC2 cluster.
**Question:** Diagnose and fix.
**Expected answer:** The **EC2 cluster lacks capacity** — the ASG didn't scale, or instances are too small/full (placement can't find room). Fix: enable **capacity provider managed scaling** so the ASG scales with pending tasks, use larger/more instances, or move to **Fargate** (no capacity management). Check cluster reservation metrics.

**C3. Scenario:** During a rolling deployment, users see 5xx errors for a few minutes.
**Question:** Why, and how do you make it zero-downtime?
**Expected answer:** Old tasks are being deregistered before new ones are healthy (or health checks pass too slowly). Fix: set **minimumHealthyPercent=100 / maximumPercent=200**, add a **health check grace period**, ensure the ALB **deregistration delay** drains connections, and verify new tasks pass health checks before old ones stop. For risky changes, use CodeDeploy blue-green.

**C4. Scenario:** A task crashes repeatedly and restarts in a loop; the container exits with OOMKilled.
**Question:** Diagnose and fix.
**Expected answer:** The container exceeded its **memory limit** and was killed (OOMKilled). Fix: check the app's memory usage vs the task definition's memory, increase the task memory (or add swap/reservations), profile for leaks, and set CloudWatch alarms on memory utilization. Also verify the `memoryReservation` vs `memory` hard limit semantics.

**C5. Scenario:** Two services need to talk to each other; the team hardcoded an ALB DNS for internal traffic, and security wants internal traffic encrypted + not exposed.
**Question:** Redesign.
**Expected answer:** Remove the public/internal ALB hop for east-west traffic and use **ECS Service Connect** (or Cloud Map) with stable DNS names and **mutual TLS** — services call each other by name over private networking with encryption. Keep the ALB only for external (north-south) entry.

**C6. Scenario:** You must run a one-off batch job container that exits when done — but the task keeps getting restarted.
**Question:** What's wrong and how do you run batch tasks correctly?
**Expected answer:** A **service** maintains desired count and restarts stopped tasks. For one-off jobs, use a **standalone task** (`RunTask`) or **AWS Batch**/Step Functions instead of a service — a standalone task runs once and is not restarted. Set the container to exit 0 on completion and capture logs.
