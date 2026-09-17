# AWS Auto Scaling — Interview Questions

> **Cloud:** AWS · **Category:** Compute · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~9 min

---

## JSON File Format

Auto Scaling groups are JSON via CloudFormation (`AWS::AutoScaling::AutoScalingGroup`, `::ScalingPolicy`, `::LaunchConfiguration`) and via `create-auto-scaling-group` CLI JSON.

```json
{
  "Type": "AWS::AutoScaling::AutoScalingGroup",
  "Properties": {
    "MinSize": "2",
    "MaxSize": "10",
    "DesiredCapacity": "3",
    "VPCZoneIdentifier": ["subnet-a", "subnet-b"],
    "TargetGroupARNs": ["arn:aws:elasticloadbalancing:...:targetgroup/app/xyz"],
    "LaunchTemplate": { "LaunchTemplateId": "lt-0abc123", "Version": "$Latest" }
  }
}
```

**Key fields:** `MinSize` / `MaxSize` / `DesiredCapacity` · `VPCZoneIdentifier` (subnets across AZs) · `TargetGroupARNs` (LB integration) · `LaunchTemplate`. Scaling-policy JSON adds `PolicyType` (TargetTrackingScaling etc.) + `TargetValue`.


## Case A — Basic

**A1. What is EC2 Auto Scaling?**
**Answer:** A service that automatically adjusts the number of EC2 instances (or other resources) in a fleet to match demand — scaling out when load increases and scaling in when it drops — while maintaining availability and cost efficiency.

**A2. What are the core components of an Auto Scaling group (ASG)?**
**Answer:** Launch template/config (what to launch), min/max/desired capacity, VPC subnets (AZs), scaling policies (when to scale), health checks, and optional load balancer/target group integration.

**A3. What are min, max, and desired capacity?**
**Answer:** **Min** = fewest instances to keep (HA floor). **Max** = most instances allowed (cost ceiling). **Desired** = current target count; the ASG maintains this, bounded by min/max.

**A4. What is a launch template vs a launch configuration?**
**Answer:** Launch template is the modern, versioned, feature-rich way to define instance settings (AMIs, types, user data, EBS, networking, spot, etc.). Launch configurations are **legacy** (no versioning/editing) and being deprecated.

**A5. What are scaling policies?**
**Answer:** Rules that trigger scaling actions, e.g., target tracking (keep CPU at 60%), step scaling (add N instances per step), or simple scaling (single action per alarm), based on CloudWatch metrics.

**A6. What is a target tracking policy?**
**Answer:** You set a target metric (e.g., average CPU 50%, request count per target); the ASG automatically adds/removes instances to keep the metric near the target — the simplest recommended policy.

**A7. What are the health check types in an ASG?**
**Answer:** **EC2 health checks** (instance status) and **ELB health checks** (load balancer target health). Using both ensures unhealthy instances are replaced even if the OS is up but the app is failing.

**A8. What is a cooldown period?**
**Answer:** A wait time after a scaling activity before another can start, preventing the ASG from launching/terminating repeatedly before metrics stabilize.

**A9. What is instance warm-up?**
**Answer:** The time for a newly launched instance to reach full capacity (warming caches, registering with LB). The ASG ignores/ramps new instances during warm-up so it doesn't over- or under-scale.

**A10. What is the difference between scaling out and scaling in?**
**Answer:** Scale **out** = add instances (increased load). Scale **in** = remove instances (decreased load) to save cost.

**A11. How does an ASG maintain instance count across AZs?**
**Answer:** You specify multiple subnets/AZs; the ASG distributes instances across them and can rebalance to keep AZs evenly loaded (AZ rebalancing).

**A12. What is a lifecycle hook?**
**Answer:** A pause at launch or terminate (e.g., to install software, run backups, deregister from DNS) before the instance enters/leaves service. The ASG waits until you complete the hook or it times out.

**A13. How does ASG integrate with a load balancer?**
**Answer:** Attach the ASG to an ALB/NLB target group; instances register automatically on launch and deregister on scale-in (with connection draining). Health checks drive replacement.

**A14. What is dynamic vs predictive scaling?**
**Answer:** **Dynamic** reacts to current metrics. **Predictive** uses machine learning on historical patterns to scale ahead of anticipated load (e.g., daily peaks).

**A15. What is a scheduled scaling action?**
**Answer:** Scale to a known capacity at specific times (e.g., 10 instances at 9 AM weekdays) — for predictable, time-based demand without relying on metric alarms.

---

## Case B — Advanced (Senior)

**B1. Explain the scale-in protection mechanisms: cooldowns, termination policies, and instance protection.**
**Answer:** On scale-in, the ASG picks instances using the **termination policy** (default: AZ balance → oldest launch template → closest to billing hour), honors **instance scale-in protection** (pinned instances), applies **cooldowns** to avoid flapping, and respects **connection draining** via the LB. Understanding this ordering is key to avoiding terminating the wrong instances.

**B2. How do you design scaling policies that don't flap (oscillate)?**
**Answer:** Use **target tracking** (self-correcting, less flappy) with a sensible warm-up, use **scale-in cooldowns** longer than scale-out, avoid step policies with tiny thresholds, and aggregate metrics over multiple datapoints (e.g., 3×1-minute). Flapping usually means thresholds are too tight or warm-up too short.

**B3. What is the difference between target tracking, step, and simple scaling — and when each?**
**Answer:** Target tracking = "keep metric at X" (best default, self-tuning). Step scaling = graduated response to alarm breach severity (for bursty, quantized workloads). Simple scaling = single action per breach (legacy, limited). Choose target tracking unless you need precise, stepped capacity changes.

**B4. How does Auto Scaling interact with Spot Instances (mixed instance policies)?**
**Answer:** A **mixed instances policy** lets the ASG launch across multiple instance types and purchase options (On-Demand + Spot with a % split). The ASG distributes across the cheapest pools, falls back to On-Demand, and replaces reclaimed Spot instances automatically — key for cost optimization.

**B5. Explain lifecycle hooks in depth with a real example (termination hook for draining jobs).**
**Answer:** On termination, a lifecycle hook puts the instance in `Terminating:Wait`, emits an event (EventBridge/SNS/SQS) so you can drain work (e.g., finish in-flight jobs, deregister from custom services), then signals `complete-lifecycle-action` to proceed. Default heartbeat timeout aborts if you don't respond — critical for graceful shutdown of stateful workers.

**B6. How does an ASG handle a failed AZ, and what is "AZ rebalancing"?**
**Answer:** If an AZ's instances become unhealthy/unavailable, the ASG launches replacements in the remaining healthy AZs to maintain desired capacity. AZ rebalancing also redistributes instances when capacity is added back. Multi-AZ ASG + per-AZ capacity keeps the app available through an AZ outage.

**B7. What are warm pools and how do they speed up scale-out?**
**Answer:** A warm pool keeps a set of **stopped** (or running-but-not-in-service) pre-configured instances ready. On scale-out, the ASG "resumes" them instantly instead of full boot + config, dramatically cutting scale-out latency — useful for latency-critical scale events.

**B8. How do you achieve zero-downtime deployments with an ASG (rolling vs blue-green vs instance refresh)?**
**Answer:** **Rolling** = replace instances gradually (instance refresh) with new AMI/config. **Blue-green** = build a new ASG with the new version, shift traffic via the LB/DNS, then retire the old. **Instance refresh** automates in-place rolling replacement with min-health and warm-up controls. Choose blue-green for risky changes; instance refresh for routine image updates.

**B9. What are the common reasons an ASG "doesn't scale" when you expect it to?**
**Answer:** Wrong min/max/desired, missing/wrong CloudWatch alarm metric, cooldown still active, warm-up too long, health checks failing (instances replaced but not added), launch template AMI issues, instance type capacity unavailable in an AZ, or the target tracking metric isn't exposed. Debug via **scaling activities** history, which records every decision and reason.

**B10. How do you size min/max and design for cost + availability?**
**Answer:** Set **min** to survive an AZ loss with enough capacity for baseline load (e.g., 2 AZs × N/2 + 1), **max** to the cost ceiling, use Spot for elastic capacity, rightsize instance types via Compute Optimizer, and set scale-in policies conservative to avoid churn. Also use savings plans/reserved for the predictable baseline (min capacity).

**B11. How do Auto Scaling and Kubernetes/ECS Fargate compare for scaling, and when to use ASG?**
**Answer:** EC2 ASG scales at the **instance** level (coarse). ECS/K8s scale at the **container/task** level with finer granularity and faster bin-packing (they may also use ASG for the node pool). Use ASG for VM-based workloads; use ECS/EKS for containerized microservices. ASG remains the control plane for EC2-based clusters.

**B12. How do you audit/monitor ASG behavior at scale?**
**Answer:** Use **scaling activity history** (every launch/terminate + reason), CloudWatch metrics (GroupInServiceInstances, GroupDesiredCapacity, GroupTerminatingInstances), alarm history, and CloudTrail for config changes. Alert on repeated failed activities (e.g., `Failed` status, InsufficientInstanceCapacity) and on capacity below min.

---

## Case C — Scenario

**C1. Scenario:** A web app must handle a daily 3x traffic spike at 6 PM and stay cost-efficient overnight.
**Question:** Design the scaling strategy.
**Expected answer:** Baseline: set **min** for off-peak traffic (with some headroom). Use **scheduled scaling** to pre-scale before 6 PM, plus a **target tracking policy** (e.g., CPU 60% or ALB request count per target) to absorb variance, and scale-in at night back to min. Combine with a warm pool if the ramp is steep, and Spot for the elastic portion to cut cost.

**C2. Scenario:** Instances are being terminated and relaunched repeatedly (flapping) every few minutes.
**Question:** Diagnose and stabilize.
**Expected answer:** Likely causes: aggressive scale-in policy + tight alarm thresholds, or health checks marking instances unhealthy only under load (failing then recovering), or no cooldown. Stabilize: use target tracking with warm-up, lengthen scale-in cooldown, require multiple consecutive alarm datapoints, and review ELB health check thresholds. Check scaling activity history for the trigger reasons.

**C3. Scenario:** During an AZ outage, your single-AZ ASG went to zero instances (desired was 3 in one AZ).
**Question:** What went wrong and how do you redesign?
**Expected answer:** The ASG's only AZ failed, so all instances were unhealthy/unavailable and there was no other AZ to relaunch into. Redesign: spread the ASG across **multiple AZs** with sufficient min capacity per AZ, enable ELB health checks, and verify the AMI/instance type is available in each AZ. Multi-AZ is a core ASG best practice.

**C4. Scenario:** A stateful worker fleet must finish in-flight jobs before any instance is terminated during scale-in.
**Question:** Implement graceful scale-in.
**Expected answer:** Use a **termination lifecycle hook** with a heartbeat: on `autoscaling:EC2_INSTANCE_TERMINATING`, the worker stops taking new jobs, drains its queue, then signals `complete-lifecycle-action`. Pair with **instance scale-in protection** for critical workers and a generous heartbeat timeout so jobs complete before the instance is terminated.

**C5. Scenario:** Your ASG can't scale out during a flash-crowd event — activity history shows "InsufficientInstanceCapacity" in one AZ.
**Question:** Explain and fix.
**Expected answer:** AWS temporarily lacks your chosen instance type in that AZ. Fix: use a **mixed instances policy** with multiple instance types/sizes (and Spot+On-Demand) so the ASG picks from available pools, spread across more AZs, and consider a warm pool or pre-scaling for known events. This is the standard resilience pattern for capacity shortages.

**C6. Scenario:** A new app version in a rolling instance refresh briefly causes 5xx errors for users.
**Question:** Why, and how do you make refreshes zero-downtime?
**Expected answer:** New instances may register with the LB before passing health checks, or old instances are terminated before the new ones are ready, or the new code fails health checks causing replacement churn. Fix: configure instance refresh with **min healthy percentage** (e.g., 100%), proper ELB health checks + warm-up, connection draining on the old instances, and health check grace period. Blue-green is even safer for risky changes.
