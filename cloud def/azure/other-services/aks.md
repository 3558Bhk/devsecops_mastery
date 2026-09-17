# Azure Kubernetes Service (AKS) — Interview Questions

> **Cloud:** Azure (Other Services) · **Category:** Compute / Containers · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~8 min

---

## JSON File Format

AKS workloads are Kubernetes objects, expressed as JSON (the API wire format; manifests are usually written in YAML).

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
      "spec": {
        "containers": [{
          "name": "web",
          "image": "myacr.azurecr.io/web:1.0",
          "ports": [{ "containerPort": 80 }]
        }]
      }
    }
  }
}
```

**Key fields:** `apiVersion` + `kind` · `metadata` · `spec` (replicas, selector, template, containers) · `status`. Secrets/ConfigMaps, Services, and Ingresses use the same JSON schema; Helm charts render to this JSON/YAML.


## Case A — Basic

**A1. What is Azure Kubernetes Service (AKS)?**
**Answer:** A managed **Kubernetes** service — Azure operates the control plane (API server, etcd) for free, while you manage worker nodes and workloads.

**A2. What is a node pool?**
**Answer:** A group of VMs (same size/config) in the cluster that run your pods — **system pool** (critical add-ons) and **user pools** (workloads), plus **Windows** or **Spot** pools.

**A3. What is a pod, deployment, and service?**
**Answer:** **Pod** = smallest unit (containers). **Deployment** = declarative desired state (replicas, rolling updates). **Service** = stable network endpoint in front of pods.

**A4. How do you access an AKS cluster?**
**Answer:** Via **kubectl**, authenticated with **Entra ID (Azure AD)** — `az aks get-credentials` configures kubeconfig; RBAC maps Entra users/groups to K8s roles.

**A5. What is the AKS control plane vs worker nodes?**
**Answer:** The **control plane** (API server, scheduler, etcd) is **Azure-managed and free**. **Worker nodes** (VMs) are yours — you pay for and manage them (or use virtual nodes/Serverless).

**A6. What is a namespace?**
**Answer:** A logical partition of the cluster for isolating resources (teams/environments) with quotas and RBAC.

**A7. What is the Container Network Interface (CNI) in AKS?**
**Answer:** **Azure CNI** assigns each pod a **VNet IP** (native VNet integration, but IP exhaustion risk) or **Overlay** (larger pod networks, simpler IP planning). Choose based on IP space and VNet integration needs.

**A8. What is an Ingress controller in AKS?**
**Answer:** A controller (NGINX, or **Application Gateway Ingress Controller – AGIC**) that provisions external access (L7 routing/TLS) to services from Ingress resources.

**A9. What is Helm?**
**Answer:** The Kubernetes package manager — templated charts for consistent deployments (widely used on AKS).

**A10. What is the difference between AKS and Azure Container Instances (ACI)?**
**Answer:** AKS = full orchestration (clusters, scaling, services). ACI = **serverless single containers** (run a container without a cluster). AKS can use ACI via **Virtual Nodes** for burst.

**A11. How does AKS integrate with ACR (Azure Container Registry)?**
**Answer:** AKS pulls images from **ACR** — authenticate via the cluster's **managed identity** (attach ACR role), or image pull secrets. CI/CD pushes to ACR; AKS deploys.

**A12. What is a managed identity for AKS?**
**Answer:** AKS clusters use a **managed identity** (system/user-assigned) to call Azure services (ACR, storage, Key Vault) — the modern replacement for service principals.

**A13. What is workload identity?**
**Answer:** AKS's integration that lets **pods** assume **Entra ID workloads** (federated identity) to access Azure services — the AKS-native alternative to pod-managed identity/aad-pod-identity.

**A14. What is cluster autoscaler vs HPA?**
**Answer:** **HPA** (Horizontal Pod Autoscaler) scales **pods** based on metrics. **Cluster Autoscaler** scales **nodes** when pods can't be scheduled. They work together for elastic scaling.

**A15. What is Azure Policy for AKS?**
**Answer:** Azure Policy can **audit/enforce** cluster configuration (e.g., require HTTPS ingress, disallow privileged pods) via the Azure Policy add-on — governance as code for clusters.

---

## Case B — Advanced (Senior)

**B1. Explain AKS networking modes: kubenet vs Azure CNI vs Azure CNI Overlay — and how to choose.**
**Answer:** **Kubenet** = NAT-based pod networking (pods get private IPs behind the node, simple IP use, but no direct pod IP visibility). **Azure CNI** = pods get **VNet IPs** (native VNet/LB integration, but consumes VNet IPs → subnet sizing matters). **Azure CNI Overlay** = pods on an overlay network with **separate pod CIDR** (high pod density, no VNet IP exhaustion). Choose Overlay for scale; Azure CNI for strict pod-level VNet visibility.

**B2. How do you secure an AKS cluster (Entra RBAC, network policies, pod security, secrets)?**
**Answer:** (1) **Entra ID + Kubernetes RBAC** (least privilege), (2) **network policies** (Azure NPM/Calico/Cilium) for pod segmentation, (3) **Pod Security Standards/admission** (Azure Policy/Gatekeeper), (4) **Workload Identity** for Azure access (no secrets), **Key Vault CSI driver** for secrets, (5) **private cluster** (API server not public), (6) **Defender for Containers** + image scanning.

**B3. What is a private AKS cluster, and how do you access it?**
**Answer:** A **private cluster** has no public API server endpoint — the control plane is reachable only from within the VNet (via private endpoint/private link). Access via a jump VM/VPN/ExpressRoute in the VNet (or Azure Bastion). This is the recommended security posture for production.

**B4. How does the Application Gateway Ingress Controller (AGIC) work?**
**Answer:** AGIC runs in the cluster and **auto-configures an Azure Application Gateway** from Kubernetes **Ingress** resources — so path/host-based routing, TLS, and WAF are provided by App Gateway, driven by K8s config. Choose it over NGINX when you want Azure-managed L7 + WAF.

**B5. Explain autoscaling end-to-end: HPA (metrics) → Cluster Autoscaler (nodes) → and KEDA.**
**Answer:** **HPA** scales replicas from metrics (CPU/mem/custom via metrics-server/Prometheus adapter). **Cluster Autoscaler** adds/removes **nodes** when pods are pending/idle. **KEDA** adds **event-driven autoscaling** (scale on queue length, Kafka lag, etc., including scale-to-zero). Together they make the cluster elastic.

**B6. What is the node upgrade/maintenance strategy (cordon/drain, surge, PDBs)?**
**Answer:** Upgrades replace nodes via **surge** (extra nodes created, pods rescheduled, old nodes removed) with **cordon + drain**. Use **PodDisruptionBudgets** so critical apps keep minimum replicas, schedule **planned maintenance windows** (or use auto-upgrade channels), and test in staging. Zero-downtime requires multiple replicas + PDBs + readiness gates.

**B7. What is Azure Policy + Gatekeeper/OPA for admission control?**
**Answer:** The **Azure Policy add-on** applies policy definitions (e.g., "no privileged containers", "require labels", "deny hostPath") at admission via Gatekeeper/OPA — **audit or deny** non-compliant resources. This enforces governance across all clusters centrally from Azure Policy.

**B8. How do you run stateful workloads (databases) on AKS (StatefulSets, PVCs, CSI)?**
**Answer:** Use **StatefulSets** (stable identities, ordered scaling) with **PersistentVolumeClaims** backed by the **Azure Disk/File CSI drivers** (managed disks/NFS). Set **pod anti-affinity** + **PDBs** for HA, and use **node pools with local/temp storage** only for stateless. Back up via CSI snapshots/Velero.

**B9. What is Workload Identity and how does it differ from aad-pod-identity (now retired)?**
**Answer:** **Workload Identity** federates a **K8s service account** to an **Entra ID managed identity/application** via OIDC — pods get tokens to call Azure (ACR, Key Vault, SQL) **without secrets**. It replaces the deprecated **aad-pod-identity** (which used VM-level identity interception and had security issues). The modern, recommended pattern.

**B10. How do you monitor AKS (Container Insights, Prometheus, logs)?**
**Answer:** **Container Insights** (Azure Monitor) collects cluster/node/pod metrics + logs; **Azure Managed Prometheus/Grafana** for Prometheus-style metrics/alerts; **diagnostic settings** for control-plane logs; **Defender for Containers** for security. Alert on node saturation, pod restarts, and OOMKills.

**B11. What are the key capacity/limit considerations (IPs, pods/node, quotas)?**
**Answer:** **Azure CNI** consumes VNet IPs (size subnets for pod count; Overlay avoids this), **max pods per node** (default 30, up to 250 with Overlay/CNI config), **node pool VM sizes vs pod resource requests**, and **subscription quotas** (vCPUs). Plan IP space and node sizes up front to avoid scale-out failures.

**B12. How does AKS integrate with service mesh (Istio/Open Service Mesh) and Dapr?**
**Answer:** **Service meshes** (Istio/OSM — note OSM is retired, Istio via add-on) provide mTLS, traffic splitting, and observability between services. **Dapr** (Distributed Application Runtime) adds building-block APIs (pub/sub, state, secrets, service invocation) — AKS's recommended way to build resilient microservices. Both are add-ons you enable per workload.

---

## Case C — Scenario

**C1. Scenario:** A microservices platform must auto-scale with traffic and survive node failures with zero downtime.
**Question:** Design the AKS setup.
**Answer:** **User node pool across availability zones**, **HPA** for pod scaling, **Cluster Autoscaler** (or KEDA for event-driven) for nodes, **PDBs** (min 2 replicas) + **readiness/liveness probes**, an **Ingress (AGIC/NGINX)** for routing, **Container Insights + Prometheus** for monitoring, and **Entra RBAC + private cluster** for security.

**C2. Scenario:** Pods are "Pending" during a traffic spike, though the app should scale.
**Question:** Diagnose.
**Answer:** Either the **HPA** isn't scaling (missing metrics-server/metrics), or **nodes are full** (Cluster Autoscaler not enabled/misconfigured/at max), or **VNet IP exhaustion** (Azure CNI subnet full), or **resource requests** exceed node capacity. Check pending-pod events (`kubectl describe pod`) and autoscaler logs; fix IP space or enable/raise autoscaler limits.

**C3. Scenario:** A pod must read from Azure Key Vault and ACR without any secrets in the cluster.
**Question:** Implement.
**Answer:** Enable **Workload Identity**: bind the pod's **service account** to an **Entra ID managed identity** (federated), grant the identity **ACR pull** and **Key Vault Secrets User** roles, and use the **Key Vault CSI driver** to mount secrets (or the SDK with the federated token). No image pull secrets, no Key Vault client secrets.

**C4. Scenario:** You must enforce that no pod runs as root and all ingresses use HTTPS across 50 clusters.
**Question:** Enforce with governance.
**Answer:** Enable the **Azure Policy add-on** on all clusters and assign policies: **deny privileged/root containers**, **require HTTPS/TLS on Ingress**, **require resource requests/limits**, and **audit** for compliance — assigned at management-group level so all 50 clusters inherit. Violations are blocked or reported centrally.

**C5. Scenario:** A stateful app (Elasticsearch) must persist data across pod restarts and node replacements.
**Question:** Design storage.
**Answer:** Use a **StatefulSet** with **PVCs** (Azure Disk CSI for single-node fast IO, or Azure Files/NFS for shared), **pod anti-affinity** to spread across AZs, **PDBs** to avoid mass eviction, and **CSI snapshots/Velero** for backup. Each pod keeps its data via its stable PVC identity across rescheduling.

**C6. Scenario:** The cluster's API server must not be reachable from the internet, but DevOps needs access.
**Question:** Which config?
**Answer:** Deploy a **private AKS cluster** (API server only reachable via the VNet/private link). DevOps connects via **VPN/ExpressRoute into the VNet** (or Azure Bastion to a jump VM) to run `kubectl`. This removes the public attack surface on the control plane.
