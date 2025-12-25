# RTR API - General Infrastructure - Production Environment
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
    key    = "general/prod/terraform.tfstate"
    region = "ap-south-1"
  }
}

provider "aws" {
  region = "ap-south-1"

  default_tags {
    tags = {
      Environment = "prod"
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
  env     = "prod"
  project = "general"

  # AWS configuration
  aws_region     = "ap-south-1"
  aws_account_id = "YOUR_AWS_ACCOUNT_ID"  # TODO: Replace with actual account ID

  # VPC configuration
  vpc_cidr            = "10.2.0.0/16"  # Different CIDR from dev/ppe
  availability_zones  = ["ap-south-1a", "ap-south-1b", "ap-south-1c"]  # 3 AZs for HA
  private_subnet_cidrs = ["10.2.1.0/24", "10.2.2.0/24", "10.2.3.0/24"]
  public_subnet_cidrs  = ["10.2.11.0/24", "10.2.12.0/24", "10.2.13.0/24"]
  database_subnet_cidrs = ["10.2.21.0/24", "10.2.22.0/24", "10.2.23.0/24"]

  # S3 configuration
  enable_s3_versioning = true  # Always enable versioning in prod
  s3_lifecycle_days    = 365   # Keep artifacts for 1 year

  # Secrets configuration
  jwt_key_type = "RS256"




  # Tags
  additional_tags = {
    CostCenter = "Production"
    Owner      = "PlatformTeam"
    Compliance = "Required"
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
