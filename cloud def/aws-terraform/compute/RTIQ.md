# RTIQ — Terraform Compute on AWS (Real-Time Interview Questions)

> **Cloud:** AWS · **Tool:** Terraform · **Domain:** EC2/Auto Scaling, Lambda/serverless, ECS, EKS · **Target roles:** SDE-3 · Cloud Engineer · DevOps · DevSecOps · SRE · Platform Engineer · **Reading time:** ~36 min

**How this file is used live:** this round tests whether you can express compute lifecycle—launch templates, rolling updates, scaling policies, task definitions, cluster add-ons—as code you'd trust in production. Interviewers push on the failure modes: a bad launch template version rolling out, a rolling update stuck at 50%, a Lambda concurrency change that throttles the account.

**Legend:** ⚡ Rapid · 🔍 Deep dive · 🚨 War room · ⚖️ Trade-off · 🎯 Senior signal

---

## 1. EC2 & Auto Scaling — `ec2-autoscaling.md`

**⚡ Rapid**
1. **Q:** What's the modern resource set for an ASG-based service?
**A.** `aws_launch_template` (+ versions), `aws_autoscaling_group` (with `vpc_zone_identifier`, `target_group_arns`, `instance_refresh`), `aws_autoscaling_policy` (target tracking), `aws_autoscaling_schedule` for known peaks, and IAM instance profile + SSM association/AMIs. Instances are cattle — no `aws_instance` for the fleet.
2. **Q:** Why launch templates over launch configurations?
**A.** Launch configurations are legacy (no versions, limited features); templates support versioning, mixed instance policies, IMDSv2 enforcement, and per-version changes — which is what makes rolling updates and rollback possible.
3. **Q:** How do you do versioned AMI rollouts?
**A.** `aws_launch_template` with `ami_id = var.ami_id` (fed from a parameter/CI artifact), then `instance_refresh` with `preferences { instance_warmup, min_healthy_percentage }` or a `triggers` list on the ASG so a template change triggers the refresh. The pipeline publishes the AMI ID and Terraform (or a script) rolls it.
4. **Q:** What does `ignore_changes = [desired_capacity]` mean and when is it right?
**A.** Terraform won't fight autoscaling over the instance count — correct when policies manage capacity. Wrong when you *do* want Terraform to own a fixed size; then remove the scaling policies or the ignore.
5. **Q:** How do you do target-tracking scaling in Terraform?
**A.** `aws_autoscaling_policy` with `policy_type = "TargetTrackingScaling"` and a `target_tracking_configuration` (ASGAverageCPUUtilization, ALBRequestCountPerTarget, or a custom metric such as SQS backlog per instance). Include `scale_in_cooldown`/`scale_out_cooldown` and `estimated_instance_warmup`.
6. **Q:** Mixed instances policy (Spot + on-demand) in Terraform?
**A.** `mixed_instances_policy` on the ASG with `launch_template.override` list (instance types/AZs), `instances_distribution { on_demand_base_capacity, on_demand_percentage_above_base_capacity, spot_allocation_strategy }`. Use capacity-optimized Spot and ≥3–5 instance types for interruption resilience.
7. **Q:** How do you attach instances to a load balancer and health checks?
**A.** `target_group_arns` + `health_check_type = "ELB"` + `health_check_grace_period` (long enough for app boot). Attaching via the ASG (not manual attachments) is what keeps autoscaling correct.
8. **Q:** How do you enforce IMDSv2 and other security settings?
**A.** `metadata_options { http_tokens = "required", http_endpoint = "enabled" }` in the launch template (IMDSv2 required is the security baseline), plus `ebs_optimized`, encrypted root volumes, and no key pair where SSM Session Manager is used.

**🔍 Deep dive**
9. **Q:** Design zero-downtime AMI rollouts for a 200-instance ASG in Terraform + CI.
**A.** AMI built by a pipeline (Packer/Image Builder) and published to Parameter Store; a variable feeds `aws_launch_template.ami_id` (new template version); ASG `instance_refresh` with `strategy = "Rolling"`, `min_healthy_percentage = 90`, `instance_warmup = 120s`, `checkpoint_percentages` (e.g. 10/50/100) for staged progress; `health_check_grace_period` + ELB health checks; `deregistration_delay` on the target group for graceful drain; deployment alarms/circuit breaker (via Auto Scaling lifecycle hooks or the pipeline) to abort on failures; and rollback = point the template back at the previous AMI and refresh again.
**↳ Follow-up:** "How do you know the rollout is healthy?"
**A.** Health at three levels: instance (ELB target health + SSM ping), service (ALB 5xx/latency alarms), and business (synthetic transactions). Gate further checkpoints on those alarms and stop the refresh if they breach. Also watch the classic trap: if the app boots but fails requests, only the service/business signals will catch it.
10. **Q:** How do you handle stateful instances (e.g. a node that holds data) in Terraform?
**A.** Ideally don't — externalise state. If unavoidable, use `aws_instance` with `lifecycle { prevent_destroy = true, ignore_changes = [ami] }`, keep data on separate EBS volumes that outlive the instance, and document that Terraform won't recreate it safely. Mixing pets and cattle in one ASG is a common anti-pattern.
11. **Q:** How do you manage Spot interruptions gracefully?
**A.** Handle the 2-minute interruption notice (EventBridge → Lambda/instance action, or `instance_metadata` polling) with drain-and-checkpoint logic, keep `on_demand_base_capacity` for a stable floor, diversify instance types/AZs, and use capacity-optimized allocation; ensure tasks are idempotent and restartable. In Terraform this is mostly policy/config plus app behaviour — the interview point is that code must tolerate termination.
12. **Q:** How do you handle ASG capacity across accounts/environments without duplication?
**A.** One module with inputs for min/max/desired, instance types, subnets (keyed maps), and policies; per-environment tfvars supply the numbers; the module computes naming/tags. Avoid duplicating resource blocks per environment — that's how policies drift.
13. **Q:** What about instance refresh failing or getting stuck?
**A.** Common causes: `min_healthy_percentage` too high to allow any batch to replace, health checks never passing (app/config error), insufficient capacity (launch failures in the AZ/instance type), or a scaling policy fighting the refresh (scale-in during rollout). Diagnose via ASG activity history; fix and re-trigger, or roll back the template version.
14. **Q:** How do you keep the ASG's capacity aligned with a scheduled workload?
**A.** `aws_autoscaling_schedule` (recurring cron) for known peaks with a target-tracking policy as the backstop, or a predictive scaling policy where supported. Document the assumption — scheduled scaling alone fails when traffic doesn't follow the pattern.
15. **Q:** How do you do golden-instance validation in the pipeline?
**A.** A smoke stage launching one instance from the new template in a test VPC/ASG (or via `aws_instance` in a sandbox root), running SSM commands to verify agents/services/versions, then destroying it; plus a canary ASG receiving a small share of traffic before the main fleet. Terraform can manage the canary as a second ASG with a lower listener weight.

**🚨 War room**
16. **Q:** An ASG instance refresh is stuck at 10% and instances are launching and terminating in a loop.
**A.** Check the ASG activity history and the instance's system/console logs: usually the app fails the health check (wrong path/port, SG, or boot script failure), the warm-up period is too short, or the launch template has a broken user-data script. Roll the template back to the previous version, confirm the app's readiness endpoint, then retry with a longer warm-up and a staged checkpoint.
17. **Q:** Terraform wants to replace the launch template and the ASG in one apply.
**A.** Find the forcing change (immutable attributes like the name, or `subnet`/`vpc_zone_identifier` changes on the ASG). Fix with in-place-compatible changes, `create_before_destroy` where replacement is unavoidable, and `name_prefix` instead of `name` so new resources can be created before old ones are destroyed. Never let a single apply swap out a production fleet's identity without a plan.
18. **Q:** Costs jumped after a scaling policy change.
**A.** Check the policy's target and cooldowns: a too-low CPU target or an aggressive `scale_out_cooldown` with a long `scale_in_cooldown` leaves instances running. Also check `min_size`, `max_size`, and mixed-instances `on_demand_base_capacity` (an on-demand floor raising the average price). Use `estimated_instance_warmup` so new instances don't trigger more scaling.
19. **Q:** Instances are being terminated by the ASG during business hours.
**A.** Scale-in from a policy with a low target (or a wrong metric value), a scheduled action from a previous test, or an instance-refresh batch. Review ASG activity history to attribute it (policy vs schedule vs refresh), then correct the configuration and add a min-size guard plus a change review for policies.
20. **Q:** A user-data script failed silently on 20% of new instances.
**A.** User data runs once at boot; failures are in the instance's console output/cloud-init logs. Common causes: a dependency on a service/endpoint not reachable (missing NAT/endpoint), IAM permissions for SSM/secret fetch, quoting/`set -e` issues, or AMI-specific paths. Fix, then validate in the pipeline by launching a test instance and asserting the app is healthy before rolling out — not after.
21. **Q:** An internal team manually terminated instances to "fix" something.
**A.** The ASG replaced them (self-healing), but check whether the replacement inherited the fix — if the fix wasn't in the launch template/AMI, it's gone after the next refresh. Codify the fix, then close the loop with the team: console changes to fleet config are drift; the pipeline is the path. This is a process/policy question as much as technical.
22. **Q:** The ASG can't launch instances at peak (insufficient capacity error).
**A.** Insufficient capacity for that instance type/AZ (Spot especially). Mitigate: diversify instance types (override list) and AZs, raise the on-demand base, use capacity-optimized Spot allocation, and add a fallback policy/pool. Add an alarm on `GroupInServiceInstances < desired` and `FailedLaunch` events so you see it before customers do.

**⚖️ Trade-off**
23. **Q:** ASG with launch template vs Spot Fleet vs EKS managed node groups?
**A.** ASG+launch template is the default for EC2 fleets (full control, instance refresh, mixed instances). Spot Fleet is largely superseded by ASG mixed instances. EKS managed node groups (below) when running Kubernetes — it handles the lifecycle for you. Match the tool to the compute model.
24. **Q:** Immutable AMI rollouts vs config management on running instances?
**A.** Immutable (rebuild + refresh) gives reproducibility, rollback, and clean provenance, at the cost of pipeline investment and longer rollouts; config management on long-lived instances enables quick fixes but drifts and can't be rolled back cleanly. Modern default: immutable + minimal boot-time config.
25. **Q:** Terraform-managed instance refresh vs a deployment tool (CodeDeploy/Spinnaker)?
**A.** Terraform's `instance_refresh` is simple and declarative (good for AMI/config changes); dedicated deploy tools give traffic shifting, canaries, and alarms-based rollback with deployment records. If you need staged progressive delivery with automatic rollback, use a deploy tool and let Terraform own the static config — plus `ignore_changes` to avoid conflicts.
26. **Q:** One ASG with mixed instance types vs several single-type ASGs?
**A.** Mixed instances within one ASG gives better Spot resilience and simpler capacity management; several ASGs (via `for_each`) give per-type scaling control but multiply management and complicate the "total capacity" story. Prefer mixed within one ASG unless you need distinct scaling behaviour.
27. **Q:** Predictive scaling vs scheduled vs target tracking?
**A.** Target tracking is the workhorse (reactive, self-tuning); scheduled handles known events (batch windows, marketing campaigns) precisely; predictive scaling anticipates diurnal patterns but needs stable history. Combine: predictive/scheduled for the known shape, target tracking for surprises.
28. **Q:** Should Terraform own the desired capacity at all?
**A.** Rarely for autoscaled fleets — policies should own it, with Terraform setting `min`/`max` and `ignore_changes = [desired_capacity]`. Terraform should own capacity only for fixed-size fleets (and then no scaling policies). Be explicit about which owner applies, or plans and scaling will fight.

**🎯 Senior**
29. **Q:** What does a production-ready ASG module include?
**A.** Launch template with IMDSv2 required, encrypted volumes, no SSH keys (SSM access), instance profile with least privilege; ASG across ≥3 AZs with ELB health checks and a warm-up period; mixed instances with an on-demand base and capacity-optimized Spot; target tracking on the real bottleneck metric plus scheduled policies for known peaks; `instance_refresh` configured with staged checkpoints and health gates; `prevent_destroy`/`create_before_destroy` semantics where appropriate; tags for ownership/cost; alarms on capacity, health, and 5xx; and a documented rollback path (previous launch template version).

**🎯 Senior signal:** "instance_refresh with checkpoints and alarm gates", "the real bottleneck metric, not CPU", and knowing that `ignore_changes = [desired_capacity]` is a deliberate ownership decision. Those are earned answers.

---

## 2. Lambda & Serverless — `lambda-serverless.md`

**⚡ Rapid**
1. **Q:** Core Terraform resources for a Lambda?
**A.** `aws_lambda_function` (runtime, handler, memory, timeout, `filename`/`s3_bucket` or image), `aws_lambda_permission` (invoke rights for API Gateway/EventBridge/S3), `aws_cloudwatch_log_group` (with retention — don't let Lambda create it with "never expire"), IAM role with least privilege, and event sources (`aws_lambda_event_source_mapping` for SQS/Kinesis/DynamoDB Streams).
2. **Q:** How do you deploy code — zip in S3 or container image?
**A.** CI builds the artifact and Terraform references it (`s3_bucket`/`s3_key`/`source_code_hash` or `image_uri`). Terraform should not build code — it deploys a versioned artifact. Use `source_code_hash` so changes trigger updates.
3. **Q:** How do you handle function versions and aliases?
**A.** `aws_lambda_function` + `aws_lambda_alias` (e.g. `live`, `canary`) + `aws_lambda_function_event_invoke_config`; publish versions and point the alias at them for progressive delivery. Aliases are how you do weighted canaries and instant rollback.
4. **Q:** How do you set reserved/provisioned concurrency?
**A.** `reserved_concurrent_executions` on the function (a cap *and* a guarantee — it also throttles beyond it), and `aws_lambda_provisioned_concurrency_config` for pre-warmed environments on a version/alias. Reserve to protect downstreams; provision to remove cold starts on critical paths.
5. **Q:** What do you always configure for reliability?
**A.** A dead-letter target (`dead_letter_config` or `destination_config` for async invokes), retries understood (async retries twice; SQS/Kinesis you control), timeout < the caller's timeout, and failure alarms. Async without a DLQ is silent data loss.
6. **Q:** How do you configure log retention?
**A.** Explicit `aws_cloudwatch_log_group` with `retention_in_days` managed by Terraform *before* the function creates it implicitly (use `depends_on`/`name = "/aws/lambda/<fn>"`), so retention and tags are enforced rather than defaulting to never-expire.
7. **Q:** Environment variables vs runtime config?
**A.** Environment variables for non-secret config (with `aws_lambda_function` `environment` and `kms_key_arn` if needed); secrets via Secrets Manager/SSM at runtime with the function's role. Note that env vars appear in state and in the console — never put secrets there if you can avoid it.
8. **Q:** How do you do VPC-attached Lambdas?
**A.** `vpc_config` with subnet IDs and SG IDs, plus the role permissions for ENI creation (or rely on managed policy), and endpoints/NAT for the resources it needs. Remember: VPC Lambdas need egress to reach AWS APIs (endpoints) or the internet (NAT).

**🔍 Deep dive**
9. **Q:** Design a serverless API with Terraform: API Gateway → Lambda → DynamoDB, plus observability and safety.
**A.** HTTP API (or REST where features are needed) with routes/integrations defined in Terraform; Lambda per route (or one handler with routing) with reserved concurrency, timeout ~10 s, memory sized from real usage, ARM64 for cost; DynamoDB with on-demand or provisioned+autoscaling; least-privilege IAM per function; log groups with retention and alarms on `Errors`/`Throttles`/duration p99; DLQ/destinations for async paths; X-Ray/OTel tracing enabled; and a canary alias with weighted routing for deploys. All in modules so a new endpoint is a small PR.
**↳ Follow-up:** "How do you deploy a new version safely?"
**A.** Publish a version, point an alias (`live`) at it with a canary weight (e.g. 10% to the new version via the alias routing config, or CodeDeploy), monitor error/latency alarms for a defined window, then shift to 100%. Rollback = point the alias back at the previous version — seconds, not a redeploy.
10. **Q:** How do you manage Lambda concurrency at account level?
**A.** Reserve concurrency per function for critical paths and downstream protection, keep unreserved headroom (don't reserve everything — reserved capacity is subtracted from the account's pool), and use SQS buffering to smooth spikes. Alarm on `Throttles` and on `ConcurrentExecutions` approaching limits.
11. **Q:** How do you handle SQS/Kinesis event source mappings?
**A.** `aws_lambda_event_source_mapping` with `batch_size`, `maximum_batching_window_in_seconds`, `function_response_types = ["ReportBatchItemFailures"]` (partial batch failure handling — avoid retrying a whole batch for one bad message), `maximum_retry_attempts`, and `destination_config` for on-failure. For Kinesis, tune `parallelization_factor` and watch iterator age; for SQS set `scaling_config` (maximum concurrency) so the function can't flood downstreams.
12. **Q:** How do you structure Terraform for a monorepo of 40 functions?
**A.** A reusable `lambda` module (runtime, memory, timeout, env, tracing, log retention, DLQ, alarms, IAM role from a policy document variable), one root per bounded context with `for_each` over functions, per-function artifacts published by CI to S3 with versioned keys, and shared layers only where they genuinely reduce cold start/size. Path-filtered CI so a change deploys only the affected service root.
13. **Q:** How do you handle IAM for Lambdas without over-permissioning?
**A.** Per-function roles built from `aws_iam_role` + scoped inline/managed policies (specific table ARNs with `dynamodb:Query` conditions, specific secret ARNs, specific bucket prefixes), no wildcard resources, and a boundary for risky functions. Note that a Lambda's role is a common privilege-escalation path if it can invoke other services (`lambda:InvokeFunction` + `iam:PassRole` audit).
14. **Q:** How do you handle cold starts in Terraform?
**A.** `aws_lambda_provisioned_concurrency_config` on the live alias (with `auto_publish`/version tracking), ARM64 (Graviton) for cheaper/faster init, smaller packages (dev-only deps excluded), SnapStart where supported (`snap_start { apply_on = "PublishedVersions" }`), and memory tuning (more memory = more CPU = faster init). Provisioned concurrency is the only guaranteed mitigation — say what it costs.
15. **Q:** How do you test/deploy Lambda changes without breaking production?
**A.** Alias-based canary, a staging environment with the same observability, integration tests invoked directly (`aws lambda invoke` in a test root) or through a test API stage, and alarms on the canary before shifting 100%. Terraform-wise, keep environment/version as inputs so the same module produces both.

**🚨 War room**
16. **Q:** Lambda throttling (`TooManyRequestsException`) during peak. What do you do?
**A.** Check whether it's account-level concurrency exhaustion (other functions consuming the pool) or the function's own reserved concurrency. Mitigate by raising/removing the cap on the critical function and adding SQS buffering; structurally, reserve concurrency per critical path and alarm on `Throttles`. In Terraform, that's a `reserved_concurrent_executions` change plus the event source.
17. **Q:** A function's log group already exists with different retention and Terraform errors on create.
**A.** Import it into state (`import` block or `terraform import aws_cloudwatch_log_group.fn /aws/lambda/<name>`) so Terraform manages the retention, or restructure so the log group is created explicitly before the function (depends_on). Recurring "already exists" errors are an import problem, not a config problem.
18. **Q:** DLQ is filling and nobody knows why.
**A.** Inspect messages and correlate with function logs (a schema change, a downstream outage, or a permissions error), fix the handler, then replay the DLQ after verifying idempotency. Add an alarm on DLQ depth and on failure destinations — and a runbook for replay, because DLQ recovery without a documented process becomes a 2 a.m. improvisation.
19. **Q:** Terraform apply fails because the deployment package is too large or hash-unstable.
**A.** Build deterministically (fixed timestamps, sorted archives) so `source_code_hash` is stable, upload the artifact to S3 from CI and reference it (rather than a local file that changes), and keep the package small (dev dependencies excluded, layers for shared code). Also check for the 50 MB direct-upload limit — S3 uploads bypass it.
20. **Q:** After a VPC change, all VPC-attached Lambdas time out.
**A.** The function lost egress: NAT/endpoint route removed, SG changed, or the subnets lost their route table association. Lambdas in a VPC with no NAT/endpoints can't reach AWS APIs or the internet — check the effective routes of the Lambda's subnets and the SG's egress rules.
21. **Q:** A restricted IAM change broke secret retrieval at runtime (not at deploy).
**A.** The function's role lost `secretsmanager:GetSecretValue` or `kms:Decrypt` on the key (a separate permission people forget) — test-time success means the cached/old credential was still valid. Add a smoke test that exercises the real call path post-deploy, and include KMS in the policy review checklist.
22. **Q:** Costs spiked 3× with stable traffic.
**A.** Look for: increased duration (a slower dependency or a cold-start-prone configuration), more invocations (a loop/polling pattern, retries on failure), provisioned concurrency left enabled, log ingestion (verbose logging), and NAT data processing for VPC Lambdas. In Terraform, check for provisioned concurrency configs and memory settings that changed; in code, check for retry storms.

**⚖️ Trade-off**
23. **Q:** Lambda vs Fargate vs ECS on EC2 for a new service?
**A.** Lambda for event-driven/spiky/short tasks with low ops; Fargate for steady container workloads with less ops overhead; ECS on EC2 for high sustained utilisation where cost per vCPU matters most. Consider cold-start sensitivity, execution duration, and team familiarity — and model the cost at your actual utilisation.
24. **Q:** One function with routing vs a function per endpoint?
**A.** Function-per-endpoint isolates permissions, scaling, and blast radius but multiplies cold starts and configuration; a single handler with routing reduces overhead but creates a shared blast radius and a large IAM policy. Default: function per bounded capability, not per route.
25. **Q:** Reserved concurrency everywhere vs only on critical paths?
**A.** Reserving everything starves the account and throttles other functions (reserved capacity is deducted from the shared pool); reserved concurrency is a protection mechanism for critical paths and downstream safety. Use it deliberately, not as a default.
26. **Q:** Terraform-managed code deployment vs CI-managed (CodeDeploy/SAM/CDK)?
**A.** Terraform excels at the infrastructure (roles, triggers, config, aliases); code deployment with canary/rollback is better done by a deploy tool if you need traffic shifting and automatic rollback. Many teams let Terraform manage everything except the function's code hash, or use `aws_lambda_alias` with weights updated by the pipeline — pick one owner and document it.
27. **Q:** Provisioned concurrency vs on-demand with a warm-up?
**A.** Provisioned is a hard guarantee with a cost even when idle; warm-up pings are a workaround that only partly helps (and can keep unused capacity). If latency matters enough to pay, provision; otherwise optimise the init path, use ARM64/SnapStart, and accept occasional cold starts.
28. **Q:** Layers vs bundled dependencies?
**A.** Layers share code across functions and reduce package size, but they add versioning complexity (functions pinning stale layer versions) and can increase cold start if they're large. Bundle for single-function dependencies; layers for genuinely shared, slow-changing libraries.

**🎯 Senior**
29. **Q:** What does production-ready Lambda look like in Terraform?
**A.** Explicit log group with retention and tags; least-privilege role per function; timeout/memory sized from real metrics (ARM64 where possible); reserved concurrency for critical paths and downstream protection; DLQ or failure destinations on async paths with alarms; tracing enabled; versions + alias with canary weights for deploys and instant rollback; event source mappings with partial batch failure handling and tunable concurrency; alarms on errors/throttles/duration/DLQ depth; and a documented runbook for the two classic incidents (throttling and DLQ buildup).

**🎯 Senior signal:** "reserved concurrency is a cap *and* a guarantee cut from the shared pool", partial batch failure handling on SQS, and alias-based canary with instant rollback. Those three separate practitioners from tutorial-followers.

---

## 3. ECS — `ecs.md`

**⚡ Rapid**
1. **Q:** Core ECS resources in Terraform?
**A.** `aws_ecs_cluster`, `aws_ecs_task_definition` (container defs, CPU/memory, env/secrets, logs, health check), `aws_ecs_service` (desired count, launch type/capacity provider, load balancer, deployment config), `aws_ecs_capacity_provider` (EC2/Spot), plus `aws_ecs_cluster_capacity_providers` for defaults.
2. **Q:** Fargate vs EC2 launch type in Terraform terms?
**A.** Fargate: `launch_type = "FARGATE"` with `network_configuration` (subnets + SGs) and `requires_compatibilities = ["FARGATE"]`; EC2: `launch_type = "EC2"` (or a capacity provider strategy) with an ASG of container instances. Fargate is simpler; EC2 is cheaper at scale with more control.
3. **Q:** How do you do zero-downtime deploys?
**A.** `deployment_configuration { maximum_percent, minimum_healthy_percent }`, `deployment_circuit_breaker { enable = true, rollback = true }` (the critical setting — automatic rollback on failure), a healthy ALB target group, `health_check_grace_period_seconds`, and connection draining via the target group's deregistration delay.
4. **Q:** How do secrets reach containers?
**A.** `secrets` in the container definition referencing Secrets Manager/SSM ARNs (injected at task start using the execution role), or fetch at app start with the task role. Never in `environment` plaintext or baked into images.
5. **Q:** Task role vs execution role?
**A.** Execution role: what the ECS agent needs (pull image from ECR, write logs, read secrets for injection). Task role: what the application needs (S3, DynamoDB, SQS). Confusing them is the most common ECS permissions bug.
6. **Q:** How do you enable autoscaling?
**A.** `aws_appautoscaling_target` on the service (min/max count) + `aws_appautoscaling_policy` (target tracking on ECS service CPU/memory utilization, ALB request count per target, or a custom metric like SQS backlog). Configure `scale_in_cooldown` conservatively and handle graceful shutdown.
7. **Q:** How do you wire logging?
**A.** `logConfiguration` with `awslogs` (CloudWatch Logs group, stream prefix, region) — and create the log group in Terraform with retention so it doesn't default to never-expire. Consider FireLens for routing to other destinations.
8. **Q:** How do you attach an ALB?
**A.** `load_balancer { target_group_arn, container_name, container_port }` on the service, the target group created with the right health check, and the service's SG allowed from the ALB's SG. Dynamic port mapping (`hostPort = 0`) for EC2 launch type, or fixed ports for Fargate with awsvpc.

**🔍 Deep dive**
9. **Q:** Design an ECS service in Terraform with blue/green deployments and autoscaling.
**A.** Cluster (with capacity providers: an on-demand base + Spot), task definition (ARM64 where possible, least-privilege task role, secrets from Secrets Manager, log group with retention, health check), service with `deployment_controller = "CODE_DEPLOY"` (or a second service + weighted target groups), CodeDeploy app/deployment group with `load_balancer_info` and alarms-based rollback, two target groups (blue/green) behind one listener with weights, autoscaling on request-count-per-target with sane cooldowns, and alarms on 5xx/latency/task health. Rollback is a CodeDeploy action or a weight flip — seconds.
**↳ Follow-up:** "How do you avoid Terraform and the deploy tool fighting?"
**A.** Terraform owns the cluster, task definition skeleton, service, target groups, and alarms; the deploy tool owns which task definition revision and target-group weights are live. Use `ignore_changes` for `task_definition`/`desired_count` where the pipeline or autoscaling owns them, and document the ownership boundary in the module README.
10. **Q:** How do you handle task-definition changes with Terraform?
**A.** A new `aws_ecs_task_definition` revision is created on every change (they're immutable and versioned); the service references `family:revision`. Terraform creating a new revision + updating the service triggers a rolling deployment — that's the standard path. Keep the container image as a variable so CI can bump it, and be careful with anything in the task def that isn't changing (avoid churn that forces needless rolling deployments).
11. **Q:** How do you protect downstreams from an ECS service scaling up?
**A.** Cap the task count (`max_capacity` on the autoscaling target), tune the scaling metric to reflect the real bottleneck (request count per target rather than CPU), align the per-task connection pool with the DB limit (or use RDS Proxy), and set `deployment_maximum_percent` so a rollout doesn't double the fleet and the DB pressure.
12. **Q:** How do you give tasks VPC access and egress?
**A.** `network_configuration` with private subnets and an SG allowing only what's needed; NAT gateway or VPC endpoints for AWS APIs (ECR pulls need S3 + ECR endpoints or NAT — a common gotcha for private-only subnets); and security groups per service (not one shared SG).
13. **Q:** How do you handle Spot capacity for ECS?
**A.** Capacity provider with `managed_scaling` (target capacity %, minimum/maximum) and Spot instances with `capacity_provider_strategy` (base on-demand + Spot weight), plus interruption handling (`ECS_ENABLE_SPOT_INSTANCE_DRAINING` and the agent's drain on interruption notice) and `stopTimeout` so tasks finish. Tasks must be stateless.
14. **Q:** How do you manage multiple services/environments without duplication?
**A.** `for_each` over a services map in one root (or a module per service) with per-environment tfvars for counts/sizes/images; shared modules for the task definition and service. Watch out: `for_each` over services can couple their lifecycles — separate roots per service are better when teams own them independently.
15. **Q:** How do you do service discovery / inter-service communication?
**A.** Service Connect (`aws_service_discovery_http_namespace` + `service_connect_configuration`) or Cloud Map (`aws_service_discovery_service` + `service_registries` on the service) for DNS-based discovery. Avoid hardcoded task IPs — they change on every deployment.

**🚨 War room**
16. **Q:** An ECS service deployment is stuck and tasks keep getting replaced.
**A.** Read the service events (`cannot start task`, health check failures, image pull errors, port/SG issues): the classic causes are a task that never becomes healthy (probe path/port), insufficient ENIs/IPs in the subnets, ECR permissions, or the circuit breaker not enabled so it retries forever. Enable `deployment_circuit_breaker` with rollback and fix the root cause, then redeploy.
17. **Q:** Tasks are OOM-killed in production.
**A.** Task-level vs container-level memory: check the container's `memory`/`memoryReservation` against actual usage (Container Insights), then raise the container memory or fix the leak; note that Fargate task sizes are discrete combinations, so choose the right CPU/memory pair. Also check for memory-hungry sidecars.
18. **Q:** A Terraform apply replaced the task definition and rolled out a broken image.
**A.** Roll back by pointing the service at the previous task definition revision (`aws_ecs_service.task_definition` back to the known-good revision) — the fastest path is reverting the commit and applying, or using the deploy tool's rollback. Then add a smoke test gate after deployment and enable the circuit breaker so future breakage self-reverts.
19. **Q:** The service can't pull the image from ECR after a private-networking change.
**A.** Private subnets without NAT need interface endpoints for `ecr.api`, `ecr.dkr`, plus the S3 gateway endpoint (image layers live in S3) and often `logs`/`secretsmanager`. Missing the S3 gateway endpoint is the most common cause — check the endpoint set and the subnet route tables.
20. **Q:** ECS tasks are being killed during scale-in and dropping requests.
**A.** Align the target group's `deregistration_delay` with the app's request duration, handle `SIGTERM` with graceful shutdown (and set `stopTimeout`), and enable `ECS_ENABLE_TASK_IAM_ROLE`-style draining correctly on EC2 instances. In Terraform terms, these are target-group and task-definition settings — not just app code.
21. **Q:** Container Insights shows CPU at 20% but latency is high.
**A.** The bottleneck isn't CPU: check memory pressure/swap, network/ENI throughput limits, the app's thread/connection pool, and downstream dependencies (DB, cache). Low CPU + high latency is nearly always an I/O or pool-exhaustion problem — scale on the right metric or fix the pool sizing.
22. **Q:** Costs doubled after switching from EC2 to Fargate scaling.
**A.** Fargate bills per vCPU/GB-second, so over-provisioned task sizes and low utilisation hit harder; also check whether tasks are running at minimum capacity indefinitely, whether `desired_count` is above need, and whether Fargate Spot could cover part of the fleet. Right-size with Container Insights data and consider a mixed EC2/Fargate strategy for steady load.

**⚖️ Trade-off**
23. **Q:** Fargate vs EC2 launch type?
**A.** Fargate: no instance management, per-task billing, isolation per task — costlier at sustained high utilisation and no daemon/privileged containers. EC2: cheaper at scale, more control (GPU, daemons, bigger instances), but you own patching, capacity, and bin-packing. Model cost at your utilisation — the crossover is real.
24. **Q:** ECS vs EKS?
**A.** ECS is simpler with fewer moving parts and native AWS integration; EKS gives the Kubernetes ecosystem, portability, and a broader platform surface — with real operational cost. For a small team running containers, ECS usually wins; for a platform team standardising across many workloads, EKS.
25. **Q:** Rolling vs blue/green in ECS?
**A.** Rolling is built-in and simple (with the circuit breaker for auto-rollback), but you briefly run mixed versions and rollback takes another deployment. Blue/green (CodeDeploy + two target groups) gives instant rollback, avoids mixed versions, and supports canary/linear strategies at double the cost during deployment. Regulated or high-risk services → blue/green.
26. **Q:** One task definition with many containers vs one per service?
**A.** Multiple containers in one task = co-located, share network/memory, scaled together (good for sidecars like envoys/log routers). Separate services = independent scaling/deployment and blast radius (good for distinct workloads). Don't bundle unrelated apps into one task to save configuration effort.
27. **Q:** Service discovery with Service Connect vs an internal ALB?
**A.** Service Connect/Cloud Map gives east-west discovery without a load balancer (cheaper, no extra hop, works for internal calls) but lacks L7 routing/WAF features; an internal ALB gives routing/health at an extra cost and hop. East-west service-to-service → Service Connect; HTTP routing with L7 needs → internal ALB.
28. **Q:** Terraform managing `desired_count` vs autoscaling?
**A.** Autoscaling should own it (`aws_appautoscaling_target` sets min/max), and the service should have `ignore_changes = [desired_count]` so Terraform doesn't reset capacity on every apply. Terraform owning desired count alongside autoscaling causes flapping — one owner per attribute.

**🎯 Senior**
29. **Q:** What does a production-ready ECS service look like in Terraform?
**A.** Least-privilege task role (separate from the execution role), secrets injected from Secrets Manager, ARM64 where possible, log group with retention, health checks and graceful shutdown with a matched drain delay, deployment circuit breaker with rollback enabled, autoscaling on the real bottleneck metric with bounded max capacity, private subnets with the full endpoint set (ECR/S3/logs/secrets), per-service SGs, Container Insights enabled, alarms on 5xx/latency/task health, and blue/green wiring for high-risk services with documented ownership between Terraform and the deploy tool.

**🎯 Senior signal:** the circuit breaker with rollback, task-vs-execution role, and the ECR/S3 endpoint requirement for private subnets. Those three are the marks of someone who has shipped ECS services.

---

## 4. EKS — `eks.md`

**⚡ Rapid**
1. **Q:** Core Terraform resources for EKS?
**A.** `aws_eks_cluster` (+ `aws_eks_cluster_version` implicit), `aws_eks_node_group` (managed node groups) or `aws_launch_template` + `aws_autoscaling_group` for self-managed, `aws_eks_addon` (vpc-cni, coredns, kube-proxy, ebs-csi), `aws_iam_role` for cluster/nodes, and `aws_eks_access_entry`/`aws_eks_access_policy_association` for RBAC.
2. **Q:** Cluster vs node IAM roles?
**A.** Cluster role: what the control plane needs (EKS service, describe resources). Node role: what the kubelet/runtime needs (ECR pull, CNI describe/create ENI, logs). Apps should use IRSA/Pod Identity, never the node role.
3. **Q:** How do pods get AWS permissions in Terraform?
**A.** IRSA: `aws_iam_openid_connect_provider` for the cluster + a role with a trust policy on the service account (`system:serviceaccount:ns:name`) + a Kubernetes service account annotation. Or EKS Pod Identity (`aws_eks_pod_identity_association`) which avoids OIDC plumbing. Prefer one per workload.
4. **Q:** Managed node groups vs self-managed?
**A.** Managed node groups handle AMI updates, draining, and lifecycle via `aws_eks_node_group` (with `update_config` for rolling updates and `capacity_type = SPOT` for spot); self-managed ASGs give full control (custom AMIs, bootstrap args) but you own draining and upgrades. Managed first unless you have a specific need.
5. **Q:** How do you manage cluster add-ons?
**A.** `aws_eks_addon` per add-on with `addon_version` pinned and `resolve_conflicts_on_update = "OVERWRITE"` where appropriate — or manage them via Helm/Terraform Kubernetes resources if you need customisation. Pin versions so upgrades are deliberate.
6. **Q:** How do you do private-only clusters?
**A.** `vpc_config` with `endpoint_private_access = true`, `endpoint_public_access = false` (plus public CIDR restrictions if public is needed), private subnets for nodes, endpoints/NAT for image pulls, and Bastion/SSM/VPN for administration. Also plan for how CI reaches a private endpoint (self-hosted runner in the VPC).
7. **Q:** How do you template/version the AMI for nodes?
**A.** `aws_eks_node_group.ami_type` (AL2023/Bottlerocket) plus `release_version` (AMI release) pinned or left to EKS; for custom AMIs use a launch template. Bottlerocket is the security/operationally-simpler choice for many teams.
8. **Q:** How do you connect Terraform to the cluster for Kubernetes resources?
**A.** A `kubernetes`/`helm` provider configured using the cluster's `endpoint`, `certificate_authority`, and auth (`exec` with `aws eks get-token` or the `aws_eks_cluster_auth` data source). Note the provider must be configured *after* the cluster exists — hence the common two-stage root pattern.

**🔍 Deep dive**
9. **Q:** Design a multi-team EKS platform in Terraform.
**A.** Cluster with private endpoint, KMS encryption for secrets, control-plane logging to CloudWatch, OIDC provider (or Pod Identity), managed node groups per workload class (system/general/memory/spot) with taints and labels, cluster autoscaler or Karpenter, add-ons pinned via `aws_eks_addon`, VPC CNI with custom networking/prefix delegation if IP-hungry, and namespaces/RBAC/quota/network-policy as a second stage via Helm/Kubernetes providers or (better) GitOps. Platform guardrails as code: Policy for Kubernetes, admission policies (Kyverno/Gatekeeper), image scanning, and a documented upgrade cadence. Teams get namespace + role + quota through a module, not by editing cluster config.
**↳ Follow-up:** "Why separate the cluster root from the workload root?"
**A.** Lifecycle and blast radius: the cluster changes rarely and is high-risk; workloads change constantly. Also the Kubernetes provider needs cluster details, which requires a two-stage apply (or a separate root reading cluster outputs). Separating avoids one giant root where a workload change can threaten the control plane.
10. **Q:** How do you do zero-downtime node group upgrades with Terraform?
**A.** Update the `aws_eks_node_group` `version`/`release_version` with `update_config { max_unavailable_percentage = 25 }` (or `max_unavailable = 1`) so nodes drain and replace in batches; ensure PodDisruptionBudgets, multiple replicas, and topology spread so draining doesn't cause outages. For managed groups EKS handles the drain; verify workloads tolerate it. Rollback = set the version back (nodes are replaced again) — keep the previous AMI release available.
11. **Q:** How do you handle IP exhaustion (VPC CNI)?
**A.** Options: larger subnets, more ENIs per node (bigger instances), prefix delegation (`ENABLE_PREFIX_DELEGATION=true` on the CNI add-on, ~16× more IPs per ENI), secondary CIDR + custom networking (`AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG`), or Karpenter choosing instance types with higher ENI limits. Configure via `aws_eks_addon.configuration_values`. This is one of the most common real-world EKS scaling problems — have the answer ready.
12. **Q:** How do you implement node autoscaling?
**A.** Cluster Autoscaler (deployed via Helm, working with ASG tags that Terraform must set: `k8s.io/cluster-autoscaler/enabled` and `k8s.io/cluster-autoscaler/<cluster-name>`) or Karpenter (provisioner/NodePool CRDs + IAM role with EC2/SSM/Spot permissions, deployed via Helm). Karpenter gives faster, more flexible provisioning and consolidation; it's the modern default answer.
13. **Q:** How do you do secrets and encryption in EKS with Terraform?
**A.** Enable `encryption_config` with a KMS key (envelope encryption for Kubernetes secrets), then prefer not to store secrets in Kubernetes at all — use Secrets Store CSI driver or IRSA to fetch from Secrets Manager/Key Vault at runtime. Add `aws_eks_addon` for the CSI driver and its IAM role.
14. **Q:** How do you handle logging and observability?
**A.** `enabled_cluster_log_types` (api, audit, authenticator, controllerManager, scheduler) to CloudWatch with retention, Container Insights or managed Prometheus/Grafana (AMP/AMG) via Terraform, and log groups created with retention so costs don't creep. Keep audit logs long enough for incident response; alert on auth failures/denied RBAC.
15. **Q:** How do you manage RBAC and access entries in Terraform?
**A.** `aws_eks_access_entry` + `aws_eks_access_policy_association` for IAM→Kubernetes mapping (the modern approach, replacing the `aws-auth` ConfigMap), scoped to least privilege (namespace-scoped roles where possible), with `AWS`-managed policies only where appropriate. Manage the *cluster* access in Terraform, and in-cluster RBAC (roles/bindings) via GitOps workloads with review.

**🚨 War room**
16. **Q:** A node group rolling update is stuck with nodes draining forever.
**A.** Check for pods that won't evict: missing/zero-ready PodDisruptionBudgets, standalone pods without a controller, or DaemonSets that block drain; plus long `terminationGracePeriodSeconds` and unprepared app shutdown. Fix the PDBs/replicas and rollout config (`max_unavailable`, `update_config`), then re-trigger. Remember: if a workload has 1 replica and a PDB of 1, the drain can never proceed.
17. **Q:** All pods in the cluster can't reach the internet after a Terraform networking change.
**A.** The NAT/endpoint routes or the node subnets changed, the CNI add-on version/`configuration_values` broke IP allocation, or the node SG changed. Check the CNI pods' logs and node conditions, verify the effective routes of node/pod subnets, and roll back the change if it was caused by the apply.
18. **Q:** The EKS control plane is unreachable for `kubectl` and the CI.
**A.** If the endpoint is private-only, your access path changed (VPN/Bastion/runner in the VPC) or the endpoint access config was modified; if public, check `public_access_cidrs` and that your IP is allowed. Also check cluster status/`aws eks describe-cluster` for health and whether the security group on the ENIs changed.
19. **Q:** Pods are stuck in `Pending` and nodes have capacity.
**A.** Check taints/tolerations (a spot node's taint with no toleration is the classic), node selectors/affinity, PVC topology constraints (an EBS volume in one AZ can't attach to a node in another), and the scheduler's events (`kubectl describe pod`). Terraform-side, verify node group labels/taints are what your manifests expect.
20. **Q:** EKS costs jumped after enabling some add-ons and logging.
**A.** Control-plane logs (especially all five types, high volume) into CloudWatch, Container Insights metric ingestion, managed Prometheus storage, and idle node groups (multiple pools with minimum sizes). Reduce log types to what you use, set retention, and right-size node pools; review data-processing charges for cross-AZ traffic through CNI if networking changed.
21. **Q:** Someone deleted a namespace manually and Terraform wants to recreate everything in it.
**A.** If the resources are managed by Terraform (kubernetes provider resources), a plan would recreate them — but Terraform state may still think they exist, causing "already exists" errors. Reconcile by applying (recreate) or `state rm` + re-import, then consider whether Terraform or GitOps should own in-cluster resources: pick one tool per layer to avoid two controllers fighting over the same objects.
22. **Q:** After an upgrade, workloads fail with "forbidden" errors.
**A.** Deprecated/removed API versions (RBAC or CRDs) between Kubernetes versions, or access-entry changes; check the API deprecations (`pluto`/`kubent`) before upgrading, and diff RBAC if Terraform manages it. Add a pre-upgrade check in CI that scans manifests for removed APIs.

**⚖️ Trade-off**
23. **Q:** Managed node groups vs Karpenter-provisioned nodes?
**A.** Managed node groups are simpler with EKS handling AMI/drain, but they're static pools (you size them ahead) and slower to react; Karpenter provisions just-in-time from pod requirements with better bin-packing and Spot diversity, and consolidates idle capacity — at the cost of another controller with IAM permissions. Karpenter is the modern default for dynamic workloads; managed groups suit fixed system pools.
24. **Q:** Terraform for everything in the cluster vs Terraform for infra + GitOps for workloads?
**A.** Terraform for cluster/infra/add-ons/IAM (slow-changing, cross-cutting) and GitOps (Argo CD/Flux) for workloads and in-cluster config (fast-changing, app-owned) is the mainstream split — it avoids two controllers managing the same objects and gives app teams a safe path. Full-Terraform creates coupling and slow pipelines; full-GitOps leaves cloud infra to a tool not designed for it.
25. **Q:** IRSA vs Pod Identity?
**A.** IRSA uses OIDC federation from the cluster (widely supported, per-service-account role, no node-level access) but requires the OIDC provider and careful trust policies; Pod Identity is newer, simpler to set up (associations managed by EKS), and avoids token-file mechanics. New clusters can use Pod Identity where supported by the SDKs/tools in use.
26. **Q:** One cluster for everything vs cluster per environment/team?
**A.** Fewer, larger clusters are cheaper and simpler to operate but widen blast radius and couple upgrade timing; many clusters isolate but multiply control planes, add-ons, and monitoring cost. Segment by environment and by hard boundaries (compliance/data classification), not per team.
27. **Q:** Private endpoint only vs public with CIDR restrictions?
**A.** Private-only is the strongest security posture but requires network paths for every operator and CI runner (VPN/Bastion/self-hosted runners) and complicates tooling; public with tight CIDRs plus audit logging is a pragmatic middle ground. Choose based on who needs access and how they connect — and document it.
28. **Q:** Cluster Autoscaler vs Karpenter?
**A.** CA scales the ASGs you already have (works with managed node groups, tagging requirements, slower reaction, limited instance flexibility); Karpenter provisions instances directly from pod requirements (fast, diverse, consolidation-aware). If you're building new, Karpenter; if you have managed node groups and it works, CA is fine.

**🎯 Senior**
29. **Q:** What does production-ready EKS look like in Terraform?
**A.** Private endpoint with a documented access path, KMS envelope encryption for secrets, all control-plane log types to a retained log group, OIDC/Pod Identity configured and per-workload roles (never the node role), pinned add-on versions with an upgrade cadence, managed node groups or Karpenter with system/workload separation and Spot for interruptible work, CNI configured for IP headroom (prefix delegation/custom networking), Container Insights/Prometheus + alarms, PodDisruptionBudgets and topology spread for safe drains, Kubernetes guardrails via Policy/admission control, and a documented, rehearsed version-upgrade procedure.

**🎯 Senior signal:** the two-stage root (cluster then Kubernetes resources), CA tags/Karpenter IAM as an IaC concern, and prefix delegation for IP exhaustion. Those three are the marks of real EKS ownership.
