terraform {                                      # the terraform block: settings about Terraform itself
  required_version = ">= 1.5"                    # minimum Terraform version
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }   # AWS provider, any 5.x
  }
}

provider "aws" {                                 # configure the AWS provider
  region = "us-east-1"                           # where the state bucket lives
}

resource "aws_s3_bucket" "state" {               # the bucket that will STORE terraform state
  bucket = "my-tf-state-bucket-2026"             # must be globally unique — change if it's taken
}

resource "aws_s3_bucket_versioning" "state" {    # version state: every overwrite is kept (rollback safety net)
  bucket = aws_s3_bucket.state.id                # which bucket

  versioning_configuration { status = "Enabled" }   # turn versioning on
}

resource "aws_s3_bucket_public_access_block" "state" {   # state must NEVER be public
  bucket                    = aws_s3_bucket.state.id     # which bucket
  block_public_acls         = true                       # block public ACLs
  ignore_public_acls        = true                       # ignore public object ACLs
  block_public_policy       = true                       # block public policies
  restrict_public_buckets   = true                       # public policies fail
}

resource "aws_dynamodb_table" "locks" {          # the lock table: one row = "who is applying right now"
  name         = "my-tf-state-locks-2026"        # the table name (must match backend.tf)
  billing_mode = "PAY_PER_REQUEST"               # pay per use, no capacity planning needed
  hash_key     = "LockID"                        # the primary key column

  attribute {                                     # declare the primary key column's type
    name = "LockID"                               # same as hash_key
    type = "S"                                    # S = string
  }
}
