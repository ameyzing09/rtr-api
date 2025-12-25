# Provider configuration for Job app deployment
# ConnectX Pattern: S3 backend for state management

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "rtr-terraform-state"
    key            = "apps/job/{env}/terraform.tfstate"
    region         = "ap-south-1"
    encrypt        = true
    dynamodb_table = "rtr-terraform-locks"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}
