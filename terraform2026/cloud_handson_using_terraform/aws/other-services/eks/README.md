# EKS — Terraform how-to

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

**What:** a managed Kubernetes cluster: control-plane role + cluster + one managed node group (2 small nodes).

**Interview angle (SDE3):**
- EKS = managed **control plane** (free), you pay for nodes (or Fargate profile pods).
- The VPC CNI needs a **CIDR for pods** (`kubernetes_network_config.service_ipv4_cidr`) and enough secondary IPs per subnet.
- Node group = managed EC2 fleet with kubelet + auto repair; **Fargate profile** = serverless pods (no nodes for specific namespaces).
- EKS vs ECS (the other question): k8s portability + ecosystem vs AWS simplicity.

## Run it
```bash
terraform init && terraform plan && terraform apply   # ⚠️ ~$0.70/hr — DESTROY when done
# verify: aws eks describe-cluster --name lab-eks | grep status   # ACTIVE
#         aws eks list-nodegroups --cluster-name lab-eks
# kubectl: aws eks update-kubeconfig --name lab-eks && kubectl get nodes
```

## Clean up
```bash
terraform destroy   # do this the moment you're done
```

## Common mistakes
| Mistake | Fix |
|---|---|
| `ServiceQuotaException: insufficient secondary IPs` | the subnets are too small for the CNI (each node wants ~64 IPs) — use /23s or larger |
| Nodes stuck `NotReady` | the node role is missing the EKS node policy (this file attaches all 3 managed policies) |
| `403` from kubectl | run `aws eks update-kubeconfig` first (and the user needs `eks:DescribeCluster` + the node-role access) |
