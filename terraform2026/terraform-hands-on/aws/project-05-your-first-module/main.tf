terraform {                                      # the terraform block: settings about Terraform itself
  required_version = ">= 1.5"                    # minimum Terraform version
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }   # AWS provider, any 5.x
  }
}

provider "aws" {                                 # configure the AWS provider (root owns this — not the module)
  region = var.region                            # region comes from a root variable
}

module "vpc" {                                   # module block: call the child module, locally named "vpc"
  source = "./modules/vpc"                       # where the module's files live (relative path)

  name             = var.project                 # root variable → module's var.name
  cidr_block       = "10.0.0.0/16"               # root decides the address space → module's var.cidr_block
}
