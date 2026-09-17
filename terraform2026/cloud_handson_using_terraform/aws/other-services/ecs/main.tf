# ============================================================================
#  ECS (Fargate) — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

resource "aws_vpc" "main" {                      # the VPC
  cidr_block = "10.0.0.0/16"                     # the space
}

resource "aws_subnet" "a" {                      # subnet A
  vpc_id            = aws_vpc.main.id            # which VPC
  cidr_block        = "10.0.1.0/24"              # inside
  availability_zone = "us-east-1a"               # AZ a
}

resource "aws_subnet" "b" {                      # subnet B
  vpc_id            = aws_vpc.main.id            # which VPC
  cidr_block        = "10.0.2.0/24"              # inside
  availability_zone = "us-east-1b"               # AZ b
}

resource "aws_security_group" "web" {            # the container's firewall
  name   = "ecs-web"                            # the group's name
  vpc_id = aws_vpc.main.id                       # which VPC

  ingress {                                      # HTTP in (lab: from anywhere)
    description = "HTTP"                        # a label
    from_port   = 80                           # the port
    to_port     = 80                           # the same
    protocol    = "tcp"                        # TCP
    cidr_blocks = ["0.0.0.0/0"]                # anywhere
  }
}

resource "aws_ecs_cluster" "lab" {               # the cluster
  name = "lab-ecs"                              # the cluster's name

  setting {                                      # a cluster-level setting
    name  = "containerInsights"                  # enable Container Insights
    value = "enabled"                            # on
  }
}

data "aws_iam_policy_document" "task_assume" {    # who may assume the TASK role
  statement {
    effect  = "Allow"                             # allow
    actions = ["sts:AssumeRole"]                  # the assume action
    principals {
      type        = "Service"                     # a service
      identifiers = ["ecs-tasks.amazonaws.com"]  # the ECS tasks service
    }
  }
}

resource "aws_iam_role" "task" {                 # the task role (what the CONTAINER may call)
  name               = "lab-ecs-task-role"       # the role's name
  assume_role_policy = data.aws_iam_policy_document.task_assume.json   # the trust document

  # in a real app: attach the permissions the container needs (s3, ddb, api calls...)
}

data "aws_iam_policy_document" "exec_assume" {    # who may assume the EXECUTION role
  statement {
    effect  = "Allow"                             # allow
    actions = ["sts:AssumeRole"]                  # the assume action
    principals {
      type        = "Service"                     # a service
      identifiers = ["ecs-tasks.amazonaws.com"]  # ECS tasks
    }
  }
}

resource "aws_iam_role" "execution" {            # the execution role (what FARGATE may do)
  name               = "lab-ecs-exec-role"       # the role's name
  assume_role_policy = data.aws_iam_policy_document.exec_assume.json   # the trust document
}

resource "aws_iam_role_policy_attachment" "exec" {   # Fargate's managed policy (pull images, write logs)
  role       = aws_iam_role.execution.id         # which role
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"   # the managed policy
}

resource "aws_ecs_task_definition" "nginx" {      # the task definition
  family                   = "nginx-lab"          # the family name (versioned automatically)
  requires_compatibilities = ["FARGATE"]          # it must run on Fargate
  network_mode             = "awsvpc"             # each task gets its own ENI (Fargate requirement)
  cpu                      = 256                  # 0.25 vCPU (the minimum)
  memory                   = 512                  # 512 MB (must be ≥ cpu×2 for Fargate)

  execution_role_arn = aws_iam_role.execution.arn # the execution role
  task_role_arn      = aws_iam_role.task.arn      # the task role

  # container_definitions is a JSON string (yes — JSON in JSON)
  container_definitions = jsonencode([{           # one container
    name  = "nginx"                                # the container's name
    image = "public.ecr.aws/nginx/nginx:1.25"      # the image (public nginx)
    essential = true                               # if it dies, the task dies
    portMappings = [{                               # the ports
      containerPort = 80                           # the container's port
      hostPort      = 80                           # the host (ENI) port
      protocol      = "tcp"                        # the protocol
    }]
    # logConfiguration = { ... awslogs ... }        # ← add for CloudWatch log streaming (see README)
  }])
}

resource "aws_ecs_service" "nginx" {              # the service
  name            = "nginx"                       # the service's name
  cluster         = aws_ecs_cluster.lab.id        # which cluster
  task_definition = aws_ecs_task_definition.nginx.arn   # which task definition
  desired_count   = 1                             # keep 1 task running
  launch_type     = "FARGATE"                     # serverless compute (vs EC2)
  platform_version = "LATEST"                     # the Fargate platform version

  network_configuration {                          # where the task's ENI lives
    subnets         = [aws_subnet.a.id, aws_subnet.b.id]   # the subnets
    security_groups = [aws_security_group.web.id]  # the firewall
    assign_public_ip = true                   # give the task a public IP (lab)
  }

  depends_on = [aws_iam_role_policy_attachment.exec]   # the role's policy must be attached before the service starts
}
