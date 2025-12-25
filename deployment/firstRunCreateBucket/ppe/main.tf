# First-run script to create Terraform state S3 bucket - PPE
# Uses same bucket as dev (different keys per environment)
# Run this ONLY if you need separate buckets per environment

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-south-1"

  default_tags {
    tags = {
      Project     = "rtr-api"
      ManagedBy   = "Terraform"
      Environment = "shared"
    }
  }
}

# NOTE: PPE uses the same bucket created in dev
# This file exists for reference only
# Run the dev/main.tf to create the shared bucket

output "message" {
  value = "PPE uses the same state bucket created in dev: rtr-tfstate"
}

output "state_bucket" {
  value = "rtr-tfstate"
}

output "lock_table" {
  value = "rtr-terraform-locks"
}
