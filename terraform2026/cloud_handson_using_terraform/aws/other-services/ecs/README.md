# ECS (Fargate) — Terraform how-to

## 📁 File structure (the standard Terraform layout)

| File | What it does |
|---|---|
| `providers.tf` | the `terraform` block (required_providers) + provider config — "which cloud, which provider version, how to log in" |
| `variables.tf` | input variables — the knobs (e.g. `region`) you change without touching the resources |
| `main.tf` | the resources — the actual infrastructure Terraform creates (and any `data` lookups) |
| `outputs.tf` | output values — the endpoints/ids/URLs Terraform prints after `apply` |

> Why four files? Terraform reads **every** `.tf` file in the folder as one program. Splitting by
> concern is the industry convention: reviewers find the resources in `main.tf`, you change
> settings in `variables.tf`, and you read results in `outputs.tf` — instead of one 500-line file.

**What:** a serverless container platform: cluster + task definition + service running a public nginx container.

**Interview angle (SDE3):**
- ECS = AWS-managed **container orchestration** (tasks/services); Fargate = no EC2 to manage (vs EC2 launch type where you run the agents).
- Task definition = the immutable "what a container is" (image, cpu, memory, ports, env, roles); Service = "keep N of these running".
- Two roles per task: **task role** (what the container may call) + **execution role** (what Fargate may do to run it — pull images, write logs).
- ECS vs EKS: ECS = simpler, AWS-opinionated; EKS = full Kubernetes (portability, ecosystem).

## Run it
```bash
terraform init && terraform plan && terraform apply
# verify: aws ecs list-services --cluster lab-ecs
#         aws ecs describe-services --cluster lab-ecs --services nginx
#         the container gets a public IP → curl http://<ip>
```

## Clean up
```bash
terraform destroy
```

## Common mistakes
| Mistake | Fix |
|---|---|
| Service stuck at `SETUP` / no tasks | `no such host` image pull errors — check the execution role can pull (public ECR images are fine) |
| "cpu/memory must be in 256MB units" | Fargate memory must be ≥ cpu×ratio (e.g. 256cpu → ≥512MB) — the classic 256/512 pairing |
| Container logs nowhere to be seen | you didn't configure the `awslogs` log driver + env vars — add the LOG_GROUP/LOG_STREAM env pairs |
