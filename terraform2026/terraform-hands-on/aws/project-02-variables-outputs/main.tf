terraform {                                      # the terraform block: settings about Terraform itself
  required_version = ">= 1.5"                    # minimum Terraform version

  required_providers {                           # the providers this project needs
    aws = {                                       # the AWS provider
      source  = "hashicorp/aws"                   # where to download it
      version = "~> 5.0"                          # any 5.x, never 6.x
    }
  }
}

provider "aws" {                                 # configure the AWS provider
  region = "us-east-1"                           # the region for this project
}

resource "aws_s3_bucket" "app" {                 # the bucket itself
  bucket = "${var.project}-${var.environment}-data"   # name built from inputs: e.g. hello-dev-data
  tags = {                                        # key-value labels for finding/cost grouping
    Project     = var.project                     # e.g. "hello"
    Environment = var.environment                 # e.g. "dev"
  }
}

resource "aws_s3_bucket_versioning" "app" {      # versioning is a SEPARATE resource in the v5 provider
  bucket = aws_s3_bucket.app.id                  # which bucket to version (reference, not a name)

  versioning_configuration {                     # the versioning settings
    status = var.versioning ? "Enabled" : "Suspended"   # ternary: true → Enabled, false → Suspended
  }
}

resource "aws_s3_bucket_public_access_block" "app" {   # lock the bucket against public access
  bucket                    = aws_s3_bucket.app.id      # which bucket
  block_public_acls         = true                      # block public ACLs
  ignore_public_acls        = true                      # ignore public ACLs on objects
  block_public_policy       = true                      # block public bucket policies
  restrict_public_buckets   = true                      # public policies must fail the request
}
