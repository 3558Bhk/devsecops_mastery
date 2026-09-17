# ============================================================================
#  EKS — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

resource "aws_vpc" "main" {                      # the VPC
  cidr_block = "10.0.0.0/16"                     # the space
}

resource "aws_subnet" "a" {                      # node subnet A (generous size for the CNI's IPs)
  vpc_id            = aws_vpc.main.id            # which VPC
  cidr_block        = "10.0.4.0/22"              # 1024 IPs (the CNI needs headroom)
  availability_zone = "us-east-1a"               # AZ a
}

resource "aws_subnet" "b" {                      # node subnet B
  vpc_id            = aws_vpc.main.id            # which VPC
  cidr_block        = "10.0.8.0/22"              # 1024 IPs
  availability_zone = "us-east-1b"               # AZ b
}

data "aws_iam_policy_document" "eks_assume" {     # who may assume the cluster role
  statement {
    effect  = "Allow"                             # allow
    actions = ["sts:AssumeRole"]                  # the assume action
    principals {
      type        = "Service"                     # a service
      identifiers = ["eks.amazonaws.com"]        # the EKS control plane
    }
  }
}

resource "aws_iam_role" "cluster" {               # the cluster (control plane) role
  name               = "lab-eks-cluster"         # the role's name
  assume_role_policy = data.aws_iam_policy_document.eks_assume.json   # the trust document
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {   # the cluster policy
  role       = aws_iam_role.cluster.id           # which role
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"   # manage the cluster
}

resource "aws_iam_role_policy_attachment" "service_policy" {   # service role policy
  role       = aws_iam_role.cluster.id           # which role
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServiceRolePolicy"   # for Fargate/service mesh
}

resource "aws_eks_cluster" "lab" {                # the cluster
  name     = "lab-eks"                            # the cluster's name
  role_arn = aws_iam_role.cluster.arn             # the control-plane role

  enabled_cluster_log_types = ["api", "audit"]    # which control-plane logs to send to CloudWatch

  vpc_config {                                     # the network wiring
    subnet_ids             = [aws_subnet.a.id, aws_subnet.b.id]   # which subnets
    endpoint_private_access = true                  # the private API endpoint (the k8s way)
    endpoint_public_access  = true                  # the public endpoint (for kubectl from a laptop)
  }

  kubernetes_network_config {                       # the POD IP space (the CNI's CIDR)
    service_ipv4_cidr = "172.20.0.0/16"            # where the CNI allocates pod IPs
  }
}

data "aws_iam_policy_document" "node_assume" {     # who may assume the node role
  statement {
    effect  = "Allow"                             # allow
    actions = ["sts:AssumeRole"]                  # the assume action
    principals {
      type        = "Service"                     # a service
      identifiers = ["ec2.amazonaws.com"]        # the worker nodes
    }
  }
}

resource "aws_iam_role" "node" {                   # the node role
  name               = "lab-eks-node"             # the role's name
  assume_role_policy = data.aws_iam_policy_document.node_assume.json   # the trust document
}

resource "aws_iam_role_policy_attachment" "node_policy" {   # the node policy
  role       = aws_iam_role.node.id               # which role
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"   # be a k8s node
}

resource "aws_iam_role_policy_attachment" "cni_policy" {   # the CNI policy
  role       = aws_iam_role.node.id               # which role
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"   # allocate pod IPs
}

resource "aws_iam_role_policy_attachment" "ssm_policy" {   # SSM (for node patching/inspection)
  role       = aws_iam_role.node.id               # which role
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"   # pull from ECR
}

resource "aws_eks_node_group" "workers" {          # the managed node group
  cluster_name    = aws_eks_cluster.lab.id         # which cluster
  node_group_name = "workers"                      # the group's name
  node_role_arn   = aws_iam_role.node.arn          # the node role
  subnet_ids      = [aws_subnet.a.id, aws_subnet.b.id]   # which subnets

  instance_types = ["t3.small"]                   # the worker size (needs ≥2GB for k8s)
  capacity_type  = "ON_DEMAND"                    # on-demand (SPOT = 60-80% cheaper, interruptible)

  scaling_config {                                 # the fleet size
    desired_size = 2                               # start with 2
    min_size     = 1                               # never below 1
    max_size     = 3                               # never above 3
  }

  update_config {                                  # how in-place upgrades roll
    max_unavailable_percentage = 50                # replace at most half at a time
  }
}
