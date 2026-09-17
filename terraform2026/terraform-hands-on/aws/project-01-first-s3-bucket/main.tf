terraform {                                      # the terraform block: settings about Terraform itself
  required_version = ">= 1.5"                    # refuse to run on Terraform older than 1.5

  required_providers {                           # the providers this project needs
    aws = {                                       # the AWS provider
      source  = "hashicorp/aws"                   # where Terraform downloads it from
      version = "~> 5.0"                          # any 5.x version, but never 6.x (pin the major)
    }
  }
}

provider "aws" {                                 # configure how we talk to AWS
  region = "us-east-1"                           # the region where resources are created
}

resource "aws_s3_bucket" "hello" {               # resource block: create ONE S3 bucket, locally named "hello"
  bucket = "my-first-tf-bucket-2026"             # the global bucket name — must be unique across all of AWS
}
