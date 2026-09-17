terraform {                                      # the terraform block: settings about Terraform itself
  required_version = ">= 1.5"                    # minimum Terraform version
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }   # AWS provider, any 5.x
  }
}

provider "aws" {                                 # configure the AWS provider
  region = var.region                            # region from the variable
}

resource "aws_s3_bucket" "data" {                # the "real" project resource: one bucket
  bucket = "my-state-project-data-2026"          # its name (globally unique)
  tags   = { Project = "state-lab" }             # a label
}

resource "aws_s3_bucket" "legacy" {              # EMPTY declaration on purpose: a "slot" we'll import into
  # no attributes yet — after `terraform import`, Terraform fills them in from the live bucket
}
