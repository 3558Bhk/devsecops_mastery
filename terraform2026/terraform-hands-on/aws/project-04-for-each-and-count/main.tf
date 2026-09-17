terraform {                                      # the terraform block: settings about Terraform itself
  required_version = ">= 1.5"                    # minimum Terraform version
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }   # AWS provider, any 5.x
  }
}

provider "aws" {                                 # configure the AWS provider
  region = "us-east-1"                           # where everything is created
}

data "aws_ami" "al2023" {                        # data block: find the newest Amazon Linux 2023 image
  most_recent = true                             # newest one
  owners      = ["amazon"]                       # official Amazon images only
  filter {                                          # a filter: only AMIs matching this
    name   = "name"                                 # filter on the image name
    values = ["al2023-ami-2023*-x86_64"]            # the name pattern
  }
}

resource "aws_s3_bucket" "per_env" {             # ONE block, but one bucket PER environment
  for_each = toset(var.environments)             # loop: run this block once per list item (toset: a set of strings)
  bucket   = "app-${each.value}-data"            # each.value = the current item → app-dev-data, app-staging-data, ...
  tags     = { Environment = each.value }        # label each bucket with its environment
}

resource "aws_instance" "workers" {              # ONE block, but `count` identical instances
  count         = var.instance_count             # run this block N times (N from the variable)
  ami           = data.aws_ami.al2023.id         # the image found by the data source
  instance_type = "t4g.micro"                    # keep it tiny (free tier)

  tags = { Name = "worker-${count.index}" }      # count.index = 0, 1, 2... → worker-0, worker-1
}
