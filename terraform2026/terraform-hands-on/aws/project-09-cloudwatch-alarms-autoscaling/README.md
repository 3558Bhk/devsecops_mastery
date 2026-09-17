# Project 09 — CloudWatch Alarms + Auto Scaling (AWS)

**Difficulty:** ⭐⭐⭐ · **⏱️ ~45 min** · **Cost:** ~$0.02/hr (one t4g.micro — destroy after!)

You will build the *feedback loop* that makes infrastructure self-driving: a metric → an alarm
→ a notification, plus an auto scaling group that scales itself on CPU.

## Concepts practiced
- CloudWatch metrics, alarms, dimensions → `../terraform-mastery/01-aws-provider/09-advanced-networking-dns-cdn-observability.md`
- ASG `target_tracking_policy` (scale to keep CPU at a target)
- SNS as the notification bus

## Files in this folder

| File | What it is |
|---|---|
| `variables.tf` | project name, region |
| `main.tf` | launch template + ASG (with target tracking) + SNS topic + CPU alarm |
| `outputs.tf` | ASG name, topic ARN |
| `terraform.tfvars.example` | sample inputs |

## Run it

```bash
cd project-09-cloudwatch-alarms-autoscaling
cp terraform.tfvars.example terraform.tfvars      # (set alarm_email if you want the email)
terraform init
terraform plan
terraform apply
```

## Verify it

```bash
terraform output asg_name

# 1. the fleet: 1 instance, target tracking active
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names $(terraform output -raw asg_name) \
  --query "AutoScalingGroups[0].{Min:MinSize,Max:MaxSize,Desired:DesiredCapacity}" --output table

# 2. the alarm exists (state: OK while CPU is low)
aws cloudwatch describe-alarms --alarm-names $(terraform output -raw asg_name)-cpu-high --query "MetricAlarms[0].{State:State,Threshold:Threshold}" --output table

# 3. (optional, ~5 min) heat the CPU and watch it scale to 2:
INSTANCE=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names $(terraform output -raw asg_name) \
  --query "AutoScalingGroups[0].Instances[0].InstanceId" --output text)
aws ec2-instance-connect send-ssh-public-key 2>/dev/null   # (skip — use the console instead)
# EASIEST: Console → EC2 → instance → Monitor → CPU, or run a load in the console's "EC2 Instance Connect" shell:
#   (yes > /dev/null) &   ← run for 4 min, watch the ASG add a 2nd instance, then Ctrl+C
```

## Break it (this is the learning)

1. Change `target_value = 40` → `20` → `plan` → in-place update of the ASG policy. Apply (it'll
   probably scale UP immediately, since 40% > 20% — watch it, then revert).
2. Change the alarm `threshold = 50` → `90` → `plan` → in-place. Apply.
3. Delete the `alarm_actions` line → `plan` → in-place. What does an alarm do with no action?
   (It just records state — nothing gets notified. Apply, revert.)

## Clean up

```bash
terraform destroy
```

## Common mistakes

| Mistake | Fix |
|---|---|
| Alarm stuck in `InsufficientData` | it needs 2 × 5 min = 10 min of metric history after apply — wait |
| ASG never scales up in the test | the CPU test must sustain above 40% for ≥ 10 min; also check the policy is attached (describe-asg → TargetTrackingConfigurations) |
| `SNS` email not arriving | you must **confirm** the subscription from the email AWS sends first (console → SNS → subscriptions) |
