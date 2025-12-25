# RTR API - General Infrastructure - PPE Environment
# ConnectX Pattern: All environment-specific configuration centralized here

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket = "rtr-tfstate"
    key    = "general/ppe/terraform.tfstate"
    region = "ap-south-1"
  }
}

provider "aws" {
  region = "ap-south-1"

  default_tags {
    tags = {
      Environment = "ppe"
      Project     = "rtr-api"
      ManagedBy   = "Terraform"
      Component   = "general"
    }
  }
}

module "resources" {
  source = "../../resources"

  # Core identifiers (ConnectX pattern)
  group   = "rtr"
  env     = "ppe"
  project = "general"

  # AWS configuration
  aws_region     = "ap-south-1"
  aws_account_id = "YOUR_AWS_ACCOUNT_ID"  # TODO: Replace with actual account ID

  # VPC configuration
  vpc_cidr            = "10.1.0.0/16"  # Different CIDR from dev
  availability_zones  = ["ap-south-1a", "ap-south-1b", "ap-south-1c"]  # 3 AZs for HA
  private_subnet_cidrs = ["10.1.1.0/24", "10.1.2.0/24", "10.1.3.0/24"]
  public_subnet_cidrs  = ["10.1.11.0/24", "10.1.12.0/24", "10.1.13.0/24"]
  database_subnet_cidrs = ["10.1.21.0/24", "10.1.22.0/24", "10.1.23.0/24"]

  # S3 configuration
  enable_s3_versioning = true  # Enable versioning for ppe
  s3_lifecycle_days    = 90    # Keep artifacts longer

  # Secrets configuration
  jwt_key_type = "RS256"




  # Tags
  additional_tags = {
    CostCenter = "Engineering"
    Owner      = "DevTeam"
  }
}

# Outputs
output "vpc_id" {
  description = "VPC ID for reference by other modules"
  value       = module.resources.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs for Lambda functions"
  value       = module.resources.private_subnet_ids
}

output "lambda_role_arn" {
  description = "Lambda execution role ARN"
  value       = module.resources.lambda_role_arn
}

output "lambda_role_name" {
  description = "Lambda execution role name for data source lookups"
  value       = module.resources.lambda_role_name
}

output "api_gateway_root_resource_id" {
  description = "API Gateway root resource ID"
  value       = module.resources.api_gateway_root_resource_id
}

output "jwt_secret_arn" {
  description = "JWT keys secret ARN"
  value       = module.resources.jwt_secret_arn
  sensitive   = true
}

output "artifacts_bucket_name" {
  description = "S3 artifacts bucket name"
  value       = module.resources.artifacts_bucket_name
}
