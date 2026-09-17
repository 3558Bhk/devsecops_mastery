terraform {                                      # the terraform block (backend lives here, not in main.tf)
  backend "s3" {                                 # use the S3 backend (stores state in a bucket)
    bucket         = "my-tf-state-bucket-2026"   # the bucket from 00-bootstrap — must match exactly
    key            = "dev/terraform.tfstate"     # the "file" inside the bucket; "dev/" = one state per environment
    region         = "us-east-1"                 # where that bucket lives
    dynamodb_table = "my-tf-state-locks-2026"    # the lock table from 00-bootstrap — must match exactly
    encrypt        = true                        # encrypt the state file at rest
  }
}
