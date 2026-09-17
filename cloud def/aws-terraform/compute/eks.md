# Terraform EKS (AWS) — Interview Questions

> **Cloud:** AWS · **IaC Tool:** Terraform · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~6 min

---

## Case A — Basic

**A1. What is EKS and its core Terraform resources?**
**Answer:** AWS's managed Kubernetes control plane. Core resources: `aws_eks_cluster`, `aws_eks_node_group`, and supporting IAM roles/VPC resources.

**A2. How do you declare an EKS cluster?**
**Answer:** `resource "aws_eks_cluster" "main" { name = ... ; role_arn = ... ; vpc_config { subnet_ids = [...] } }`.

**A3. What is the cluster IAM role?**
**Answer:** `aws_iam_role` with `eks.amazonaws.com` in the trust policy and the `AmazonEKSClusterPolicy` attached — the service role EKS uses.

**A4. What is a managed node group?**
**Answer:** `aws_eks_node_group` — EKS-managed EC2 instances (with auto-healing/updates) that join the cluster as worker nodes.

**A5. What is the node IAM role?**
**Answer:** A role with `ec2.amazonaws.com` trust, plus `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`, and `AmazonEC2ContainerRegistryReadOnly` attached.

**A6. How do you get kubeconfig after creating a cluster?**
**Answer:** `aws eks update-kubeconfig --name <cluster>` (CLI), or build it from Terraform outputs (`endpoint`, `certificate_authority`, token). 

**A7. What is the `aws_eks_addon` resource?**
**Answer:** It installs/manages EKS add-ons (VPC CNI, CoreDNS, kube-proxy) declaratively.

**A8. What is the community `terraform-aws-modules/eks/aws` module?**
**Answer:** The de-facto standard module wrapping cluster, node groups, IAM, and networking best practices — most teams use it instead of raw resources.

**A9. What is `vpc_config` for?**
**Answer:** Tells EKS which subnets the control plane ENIs and nodes use, and optionally which cluster security group to apply.

**A10. What is cluster endpoint access control?**
**Answer:** `endpoint_public_access`/`endpoint_private_access` and `public_access_cidrs` control whether the API server is reachable publicly/privately.

**A11. How do you enable logging on the cluster?**
**Answer:** `enabled_cluster_log_types = ["api", "audit", "authenticator", ...]` on `aws_eks_cluster`.

**A12. What is a Fargate profile?**
**Answer:** `aws_eks_fargate_profile` runs pods on Fargate for selected namespaces/labels — serverless nodes.

**A13. How do you output cluster info for other stacks?**
**Answer:** Outputs like `cluster_endpoint`, `cluster_certificate_authority_data`, `cluster_name`, and `oidc_provider_arn`.

**A14. What does `kubernetes` provider do alongside the `aws` provider?**
**Answer:** It manages in-cluster resources (namespaces, deployments, RBAC) after the cluster exists, using the cluster's credentials.

**A15. What is the OIDC provider ARN used for?**
**Answer:** It enables IAM Roles for Service Accounts (IRSA) — associating Kubernetes service accounts with IAM roles.

## Case B — Advanced / Senior

**B1. How do you build a production EKS cluster with Terraform?**
**Answer:** Use the official EKS module: dedicated VPC (private node subnets, public/private endpoints), managed node groups across AZs, cluster security group, add-ons, logging enabled, and IRSA for workload IAM.

**B2. Explain IRSA and how Terraform sets it up.**
**Answer:** Create an IAM role with an OIDC trust policy (the cluster's OIDC provider), attach policies, and annotate a service account with the role ARN (via the `kubernetes` provider) so pods get scoped AWS credentials without node-wide permissions.

**B3. How do you manage the `kubernetes` provider's dependency on the cluster?**
**Answer:** The provider needs cluster data (endpoint/CA/token), so configure it from the cluster's outputs and ensure ordering (the cluster must exist first). For separate stacks, read the cluster via `data "aws_eks_cluster"`.

**B4. What is the difference between managed node groups and self-managed nodes?**
**Answer:** Managed groups are AWS-provisioned, auto-updated, and integrated with ASG; self-managed (your own ASG + join script/bottlerocket) give more control but more ops burden. Managed is the default choice.

**B5. How do you handle node group AMI and Kubernetes version upgrades?**
**Answer:** Set `ami_type`/`release_version` explicitly, upgrade in a controlled sequence (control plane first, then node groups one at a time), and use `update_config { max_unavailable }` for draining during node updates.

**B6. What is cluster autoscaler vs Karpenter, and their Terraform role?**
**Answer:** They scale nodes based on pending pods. Terraform typically installs them (Helm provider or `aws_eks_addon`/IRSA roles); Karpenter provisions nodes dynamically via its own CRDs.

**B7. How do you deploy workloads with Terraform (Helm vs raw)?**
**Answer:** Use the `helm`/`kubernetes` providers for app manifests, or just bootstrap the cluster and let ArgoCD/Flux manage apps (GitOps). Terraform-managing all app YAML is often an anti-pattern.

**B8. What are the security-group considerations for EKS?**
**Answer:** A cluster SG for control-plane↔node traffic, node SG for pod/node traffic (with CNI SG support for per-pod SGs), and careful management of `public_access_cidrs` to restrict the API endpoint.

**B9. How do you restrict who can administer the cluster (auth)?**
**Answer:** EKS uses `aws-auth` ConfigMap (managed by the EKS module's `manage_aws_auth` option) or, better, access entries (`access_config`) to map IAM principals to Kubernetes RBAC roles.

**B10. How do you upgrade the VPC CNI and other add-ons safely?**
**Answer:** Pin add-on versions (`aws_eks_addon` with `addon_version`) and upgrade with `resolve_conflicts_on_update = "PRESERVE"` plus testing; keep the CNI compatible with the cluster version.

**B11. How do you make the control plane fully private?**
**Answer:** `endpoint_public_access = false` + `endpoint_private_access = true`, ensure the VPC has private DNS/endpoints, and access the API only from within the VPC (or via VPN/peering).

**B12. What is the risk of deleting a cluster in Terraform while workloads remain?**
**Answer:** Terraform destroys the cluster and node groups, but PVCs (EBS), load balancers, and other AWS resources created by Kubernetes may orphan. Clean up via the cloud provider or `prevent_destroy` on the cluster.

## Case C — Scenario

**C1. Nodes register but pods can't pull images from ECR.**
**Answer:** Check the node role's ECR policy, the CNI/route table for registry access (private subnets need NAT or ECR interface endpoints), and image permissions. Add the ECR pull policy/endpoint and re-apply.

**C2. You need to give one team access to only their namespace.**
**Answer:** Map their IAM role/group to a Kubernetes RBAC role scoped to the namespace via `aws-auth`/access entries, and create the RBAC RoleBinding (via the `kubernetes` provider or GitOps).

**C3. A Terraform change to the node group is recreating all nodes and dropping traffic.**
**Answer:** Node groups replace instances on immutable changes. Use `update_config { max_unavailable_percentage }` to drain gradually, and schedule the change with enough spare capacity. Avoid changing AMI/launch template fields needlessly.

**C4. You're migrating from raw `aws_eks_cluster` resources to the official EKS module.**
**Answer:** Import the existing cluster/node groups into the module's resource addresses (`terraform import` per resource), match module inputs to current settings, and verify `plan` shows no changes before removing old code.

**C5. Pods need AWS credentials but the node role is too broad.**
**Answer:** Implement IRSA: create per-workload IAM roles with OIDC trust, attach least-privilege policies, and annotate the service accounts — so each pod gets only its own permissions.

**C6. The Kubernetes API endpoint is exposed to the internet and security wants it locked down.**
**Answer:** Restrict `public_access_cidrs` to office/CI ranges or set `endpoint_public_access = false` with private access only, and require VPN/SSM for admin access. Re-apply and verify from outside.
