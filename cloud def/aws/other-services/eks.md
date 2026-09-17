# Amazon EKS — Interview Questions

> **Cloud:** AWS (Other Services) · **Category:** Compute / Containers · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~9 min

---

## JSON File Format

Kubernetes objects (used with EKS) are expressed as JSON — the API wire format — though manifests are usually written in YAML. A Deployment manifest in JSON:

```json
{
  "apiVersion": "apps/v1",
  "kind": "Deployment",
  "metadata": { "name": "web", "namespace": "prod" },
  "spec": {
    "replicas": 3,
    "selector": { "matchLabels": { "app": "web" } },
    "template": {
      "metadata": { "labels": { "app": "web" } },
      "spec": { "containers": [{ "name": "web", "image": "repo/web:1.0" }] }
    }
  }
}
```

**Key fields:** `apiVersion` + `kind` · `metadata` (name/namespace/labels) · `spec` (replicas, selector, template, containers) · `status` (runtime state). ConfigMaps/Secrets, Services, and Ingresses follow the same JSON schema.


## Case A — Basic

**A1. What is Amazon EKS?**
**Answer:** A managed **Kubernetes** service — AWS runs the Kubernetes control plane (highly available, multi-AZ) while you run worker nodes (EC2 or Fargate) and manage workloads.

**A2. What does "managed control plane" mean?**
**Answer:** AWS operates the API server, etcd, and controllers across multiple AZs — handling patching, upgrades, and HA — so you don't run Kubernetes masters yourself.

**A3. What is a node group?**
**Answer:** A set of EC2 instances (managed by an ASG) that run your pods. **Managed node groups** are provisioned/updated by EKS; **self-managed** node groups you control directly.

**A4. What is a pod, deployment, and service in Kubernetes?**
**Answer:** **Pod** = smallest unit (one or more containers). **Deployment** = declarative desired state for pods (replicas, rolling updates). **Service** = stable network endpoint (DNS/IP) in front of a set of pods.

**A5. What is a namespace?**
**Answer:** A logical partition of the cluster for organizing/isolating resources (dev, prod, teams) with quotas and RBAC scoping.

**A6. How do you access an EKS cluster?**
**Answer:** Via **kubectl** configured with `aws eks update-kubeconfig`, authenticated through **IAM** (the aws-auth config map maps IAM principals to K8s users/groups) or newer IAM-based access entries.

**A7. What is Fargate for EKS?**
**Answer:** Serverless compute for pods — you schedule pods on **AWS Fargate profiles** (by namespace/labels) with no node management.

**A8. What is the difference between EKS and ECS?**
**Answer:** EKS = managed **Kubernetes** (portable, huge ecosystem, more complex). ECS = AWS-native orchestration (simpler, tighter AWS integration). Choose EKS for K8s standards/tooling; ECS for simplicity.

**A9. What is a service account and IRSA?**
**Answer:** **IRSA** (IAM Roles for Service Accounts) lets a pod's service account assume an **IAM role** to call AWS services — the EKS-native way to grant AWS permissions to pods (instead of node-level creds).

**A10. What is the Container Network Interface (CNI) in EKS?**
**Answer:** The **AWS VPC CNI** assigns each pod a VPC **IP address** (from your subnets), so pods use VPC networking directly (security groups, routing, LB integration).

**A11. What is a LoadBalancer service and the AWS Load Balancer Controller?**
**Answer:** The **AWS Load Balancer Controller** provisions ALBs/NLBs automatically from K8s `Service`/`Ingress` resources, integrating K8s workloads with AWS load balancers.

**A12. What is an Ingress?**
**Answer:** A K8s API object defining external HTTP routing rules (hosts/paths) — realized in EKS as an **ALB** via the Load Balancer Controller.

**A13. What is Helm?**
**Answer:** The Kubernetes package manager — templated, versioned charts for deploying applications consistently (widely used with EKS).

**A14. What is a ConfigMap and Secret?**
**Answer:** ConfigMap = non-sensitive config. Secret = sensitive data (credentials). In EKS, secrets are often integrated with **Secrets Manager/SSM** via external secrets controllers.

**A15. What are the EKS versions and upgrade responsibility?**
**Answer:** EKS supports specific Kubernetes versions (e.g., 1.28–1.31); AWS manages control-plane upgrades, but you manage **node** and **add-on** upgrades and version compatibility.

---

## Case B — Advanced (Senior)

**B1. Explain EKS architecture: control plane, nodes, networking (VPC CNI), and how pods get IPs.**
**Answer:** The managed control plane (API server, etcd, controllers) runs in AWS-managed subnets. Worker nodes join via the kubelet. The **AWS VPC CNI** allocates pod IPs from VPC subnets (secondary ENI IPs), so each pod is a first-class VPC citizen — enabling security groups, VPC routing, and direct LB targeting. IP exhaustion per node is a key constraint (addressed with prefix delegation).

**B2. How does IRSA (IAM Roles for Service Accounts) work and why is it better than node-level credentials?**
**Answer:** IRSA uses an **OIDC provider** for the cluster; a K8s service account is annotated with an IAM role ARN. Pods using that SA receive **temporary IAM credentials** (via the STS web-identity flow) scoped to the role — least-privilege per workload instead of broad node IAM roles (which all pods on a node share).

**B3. What is the AWS Load Balancer Controller and how does it map Ingress → ALB?**
**Answer:** It watches K8s `Ingress`/`Service` objects and calls AWS APIs to create **ALB/NLB** resources, target groups, and listeners — translating K8s routing rules (hosts/paths) into ALB rules. Requires IRSA and correct tagging of subnets (public/private). This replaces the legacy in-tree load balancer integration.

**B4. How do you handle cluster upgrades with minimal downtime (control plane + nodes + add-ons)?**
**Answer:** Upgrade order: control plane (AWS, brief API server disruption) → **node groups** (rolling, cordon/drain with PDBs) → **add-ons** (VPC CNI, CoreDNS, kube-proxy) → workloads. Verify version compatibility, test in staging, use PodDisruptionBudgets, and drain nodes gracefully. Automate with eksctl/Blueprints.

**B5. What is cluster autoscaling (Cluster Autoscaler vs Karpenter)?**
**Answer:** **Cluster Autoscaler** scales the node ASG when pods are unschedulable (and scales in idle nodes). **Karpenter** is the modern alternative — faster, pod-driven provisioning of right-sized EC2 instances (and Spot) without predefined ASGs. Both keep cluster capacity matched to workload demand.

**B6. How do you secure an EKS cluster (RBAC, network policies, pod security, secrets)?**
**Answer:** (1) **IAM + RBAC** least privilege (via aws-auth/access entries), (2) **network policies** (Calico/Cilium) for pod-to-pod segmentation, (3) **Pod Security Standards/admission controllers** (PSA, OPA/Gatekeeper) for workload hardening, (4) **IRSA** for AWS access, **Secrets Manager/External Secrets** for secrets, (5) private API endpoint, (6) image scanning + signed images, (7) GuardDuty EKS protection + audit logging.

**B7. What are the key add-ons in a production EKS cluster (CNI, CoreDNS, kube-proxy, others)?**
**Answer:** **VPC CNI** (pod networking), **CoreDNS** (service discovery), **kube-proxy** (service routing), plus common additions: **AWS Load Balancer Controller**, **Cluster Autoscaler/Karpenter**, **metrics-server** (HPA), **ExternalDNS**, **cert-manager**, and observability (CloudWatch/Prometheus/Grafana). Add-ons must be kept version-compatible with the cluster.

**B8. How does pod-to-pod networking differ between EKS (VPC CNI) and other CNIs, and what is prefix delegation?**
**Answer:** VPC CNI gives each pod a real VPC IP (no overlay), so VPC Flow Logs/SGs/NACLs apply directly — but consumes subnet IPs per pod. **Prefix delegation** assigns /28 prefixes to ENIs to increase pod density per node and reduce ENI churn. Alternative CNIs (Calico VXLAN) use overlays for higher density but lose native VPC visibility.

**B9. How do you design multi-tenancy in one EKS cluster (namespaces, quotas, isolation)?**
**Answer:** Use **namespaces** + **ResourceQuotas** (CPU/mem/objects) + **LimitRanges**, **RBAC** per team (role bindings), **network policies** for isolation, **Pod Security Standards** per namespace, and optionally **node taints/pools** for dedicated capacity. For stronger isolation (noisy neighbors, compliance), prefer separate clusters or virtual clusters (vCluster).

**B10. What is GitOps and how does it apply to EKS (ArgoCD/Flux)?**
**Answer:** GitOps declares cluster desired state in Git; ArgoCD/Flux continuously reconcile the cluster to match — giving auditable, reviewable, self-healing deployments and rollbacks via Git history. It's the standard operational model for production EKS.

**B11. How do you observe an EKS cluster (Container Insights, Prometheus, tracing, logs)?**
**Answer:** **CloudWatch Container Insights** (or managed Prometheus) for metrics; **Fluent Bit/FireLens** for logs to CloudWatch/OpenSearch; **AWS X-Ray/OTel** for tracing; Kubernetes audit logs for security; dashboards (Grafana/CloudWatch) + alerts on node/pod saturation, restarts, and API errors. 

**B12. Compare EKS vs ECS vs Lambda for containerized microservices.**
**Answer:** EKS = full K8s (portability, ecosystem: Helm/operators/service mesh) but operational complexity. ECS = AWS-native simplicity, less overhead. Lambda = serverless functions (no containers to manage) for event-driven, short tasks. Choose EKS for K8s standardization/ecosystem, ECS for simplicity, Lambda for short stateless functions.

---

## Case C — Scenario

**C1. Scenario:** You're migrating a containerized microservices platform from on-prem Kubernetes to AWS.
**Question:** Why EKS, and what's the migration plan?
**Answer:** EKS preserves K8s tooling/manifests/Helm (lift-and-shift with minimal rework) and gives a managed control plane. Plan: recreate workloads via GitOps/Helm, migrate data (DMS/S3), set up IRSA for AWS services, use the Load Balancer Controller for ingress, run in parallel (dual-run) with DNS cutover, and validate scaling/observability before decommissioning on-prem.

**C2. Scenario:** Pods can't be scheduled ("insufficient CPU" / pending pods) during a traffic spike even though the app should scale.
**Question:** Diagnose and fix.
**Expected answer:** Either the **HPA** isn't scaling pods (missing metrics-server/right metrics), or the **cluster lacks nodes** (autoscaler not enabled/misconfigured), or nodes are full (IP/CPU). Fix: verify metrics-server + HPA config, enable **Karpenter/Cluster Autoscaler**, check node capacity and VPC CNI IP exhaustion, and ensure resource requests/limits are set so scheduling works.

**C3. Scenario:** A pod needs to read from S3, but you must not give all pods on the node the same permissions.
**Question:** Implement least-privilege AWS access.
**Expected answer:** Use **IRSA**: create an IAM role with only the needed S3 permissions, annotate the pod's **service account** with the role ARN, and configure the OIDC trust so only that SA's pods get the temp credentials. No node-level S3 access needed — per-workload scoping.

**C4. Scenario:** Two namespaces (payments and public-web) must not talk to each other, but public-web must reach an external API.
**Question:** Enforce with network policies.
**Expected answer:** Install a CNI supporting **NetworkPolicy** (e.g., Calico). Write default-deny policies per namespace, then allow only required flows: payments ↔ its DB, public-web → external API egress (and nothing into payments). Verify with a policy tool (or Cilium Hubble) that cross-namespace traffic is dropped.

**C5. Scenario:** A stateful app (Kafka) must run on EKS with persistent, encrypted storage and survive node replacement.
**Question:** Design storage.
**Answer:** Use **EBS CSI driver** with **StorageClass** (gp3/io2, encrypted via KMS) and **PersistentVolumeClaims**; schedule Kafka pods with **node affinity/anti-affinity** and **PodDisruptionBudgets** so replicas spread across AZs and drain gracefully. Ensure the CSI driver + snapshots are set up, and test node replacement/failover.

**C6. Scenario:** Secrets are committed in a Git repo for the cluster, and security flags it.
**Question:** Remediate with AWS-native tooling.
**Answer:** Remove secrets from Git; store in **Secrets Manager/SSM Parameter Store**, and sync into K8s via the **External Secrets Operator** or **Secrets Store CSI Driver** — pods mount/read secrets at runtime with IRSA-scoped permissions and rotation. Add secret-scanning (git-secrets/TruffleHog) and RBAC so only the controller reads secrets.
