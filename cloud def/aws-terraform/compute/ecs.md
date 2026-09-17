# Terraform ECS (AWS) — Interview Questions

> **Cloud:** AWS · **IaC Tool:** Terraform · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~6 min

---

## Case A — Basic

**A1. What is ECS and its main Terraform resources?**
**Answer:** Amazon's container orchestration service. Core resources: `aws_ecs_cluster`, `aws_ecs_task_definition`, `aws_ecs_service`, and capacity (EC2 ASG capacity provider or Fargate).

**A2. What is an `aws_ecs_cluster`?**
**Answer:** The logical grouping for tasks/services: `resource "aws_ecs_cluster" "main" { name = "app" }`. With Fargate, no EC2 capacity is needed.

**A3. What is a task definition?**
**Answer:** `aws_ecs_task_definition` describes the containers (image, CPU/memory, ports, env, secrets) — the blueprint a service runs.

**A4. How do you declare a container definition?**
**Answer:** As a JSON string (often via `jsonencode`) in `container_definitions`, e.g. `[{ name, image, portMappings, environment }]`.

**A5. What is Fargate vs EC2 launch type?**
**Answer:** Fargate is serverless (no host management, per-task CPU/memory); EC2 runs tasks on your own ASG instances. Set via `requires_compatibilities`/capacity provider.

**A6. What is an `aws_ecs_service`?**
**Answer:** It maintains a desired count of task replicas from a task definition, optionally behind a load balancer, with `desired_count`, `launch_type`, and `network_configuration`.

**A7. What is `network_configuration` on a Fargate service?**
**Answer:** `assign_public_ip`, `subnets`, `security_groups` — where tasks run and how they're reached.

**A8. How do you put an ECS service behind an ALB?**
**Answer:** Add `load_balancer { target_group_arn, container_name, container_port }` on the service; the ALB routes to tasks via the target group.

**A9. What is a task IAM role vs execution role?**
**Answer:** The execution role (in the task definition) lets ECS pull images and read secrets/logs; the task role is the container's runtime identity for AWS API calls.

**A10. What is an ECS capacity provider?**
**Answer:** `aws_ecs_capacity_provider` links an EC2 ASG to the cluster so ECS can scale the underlying hosts, with managed scaling.

**A11. What is `aws_ecs_task_definition` `requires_compatibilities`?**
**Answer:** Declares launch compatibility (`FARGATE`/`EC2`), required before Fargate tasks can run.

**A12. How do you store secrets for a task?**
**Answer:** In the container definition, reference `secrets = [{ name, valueFrom = "arn:aws:ssm/.../secret" }]` (Secrets Manager or SSM) with the execution role permitted.

**A13. What is CloudWatch Logs config for ECS?**
**Answer:** A `logConfiguration` in the container definition pointing to `awslogs` log driver and a log group, so container logs are centralized.

**A14. What is a service discovery namespace?**
**Answer:** `aws_service_discovery_*` resources give services stable internal DNS names, enabling service-to-service calls by name.

**A15. What is `desired_count` and how does scaling work?**
**Answer:** The target number of running tasks. `aws_appautoscaling_target` + `aws_appautoscaling_policy` scale it on CPU/memory/custom metrics.

## Case B — Advanced / Senior

**B1. How do you deploy a new image version with zero downtime?**
**Answer:** Update the task definition (new image tag), and ECS performs a rolling update (or blue-green via CodeDeploy) that registers new tasks and drains old ones. Use `force_new_deployment` to force a redeploy when config alone doesn't change.

**B2. What is `force_new_deployment` and why is it useful?**
**Answer:** Setting it true triggers a new deployment even if the task definition is unchanged — useful when the image tag is mutable (`:latest`) so ECS repulls.

**B3. How do immutable tags (`:latest` vs digest) affect Terraform?**
**Answer:** `:latest` doesn't change the task definition, so Terraform sees no diff and won't redeploy. Pin image digests or bump tags, or use `force_new_deployment` + `ignore_changes` on the definition.

**B4. Explain the execution role vs task role security split.**
**Answer:** Execution role: ECS agent pulls image/registers logs/reads secrets (infra privileges). Task role: the app's own permissions (least privilege). Separating them limits what a compromised container can do.

**B5. How do you run ECS tasks on EC2 with cluster autoscaling?**
**Answer:** Create an ASG, register it via `aws_ecs_capacity_provider` with managed scaling enabled, and associate the capacity provider with the cluster. ECS then scales instances to fit pending tasks.

**B6. What is `platform_version` and when do you pin it?**
**Answer:** The Fargate runtime version. Pin `platform_version = "1.4.0"` (or `LATEST`) for reproducibility, since platform updates can subtly change behavior.

**B7. How do you do blue-green deployments with CodeDeploy?**
**Answer:** `deployment_controller { type = "CODE_DEPLOY" }` on the service + CodeDeploy app/deployment group with two target groups, letting ECS shift traffic between task sets gradually.

**B8. How do you mount EFS or attach EBS volumes to tasks?**
**Answer:** For EFS, define the mount in the task definition with an EFS access point (`aws_efs_access_point`) and ensure the task role/security groups can reach EFS. EBS attach is newer (Fargate) via volume config.

**B9. What are the networking choices for EC2 launch type services?**
**Answer:** Bridge mode (container ports mapped to host ports, dynamic), host mode, or `awsvpc` (per-task ENI). `awsvpc` is required for Fargate and recommended for modern setups.

**B10. How do you structure ECS config in modules for many microservices?**
**Answer:** A `service` module parameterized by image, ports, env, secrets, and target group; iterate with `for_each` over a map of services. Keep cluster/task-definition creation DRY.

**B11. What are service connect and its Terraform config?**
**Answer:** ECS Service Connect (`service_connect_configuration`) gives services stable DNS + mTLS without a service discovery namespace — configure in the service block with port aliases.

**B12. How do you handle task definition revisions and `ignore_changes`?**
**Answer:** ECS revisions accumulate; Terraform tracks the current one. Avoid churn by pinning images and using `ignore_changes` on fields managed by external tools (like image digests updated by CI).

## Case C — Scenario

**C1. Your Fargate tasks can't pull the image — where do you look?**
**Answer:** Execution role missing `ecr:GetAuthorizationToken`/`ecr:BatchGetImage` (or wrong registry), no NAT/egress route for private subnets to reach ECR, and network config SG blocking 443. Fix role/permissions and routes.

**C2. A service is stuck deploying — old tasks never drain.**
**Answer:** Check deployment circuit breaker / health checks failing, insufficient capacity (Fargate limits or ASG scale), or target group deregistration delay too long. Inspect `service events` and adjust health check grace/periods.

**C3. You need two services to talk by name, not IP.**
**Answer:** Enable ECS Service Connect (or Cloud Map service discovery) so each service gets a stable DNS name and port alias; update the calling service to use that name.

**C4. Costs are high because EC2 hosts are always at max.**
**Answer:** Switch to Fargate (pay per task) or enable capacity provider managed scaling + target tracking so hosts shrink when tasks scale in; right-size task CPU/memory to reduce over-provisioning.

**C5. Secrets are appearing in plaintext in the task definition.**
**Answer:** Move them to Secrets Manager/SSM and reference via `valueFrom` in `secrets` (not `environment`), grant the execution role read access, and never bake secrets into the JSON or image.

**C6. You must deploy a canary: 10% of traffic to the new version, then promote.**
**Answer:** Use CodeDeploy blue-green with a canary/linear deployment config (`deployment_config_name`), two target groups, and let CodeDeploy shift traffic; or use two ECS services with weighted ALB routing.
