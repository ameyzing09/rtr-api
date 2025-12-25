# RTR API - Lambda Authorizer - Production Environment
# ConnectX Pattern: Production-grade JWT validation

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
    key    = "authorizer/prod/terraform.tfstate"
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
      Component   = "authorizer"
    }
  }
}

module "resources" {
  source = "../../resources"

  # Core identifiers (ConnectX pattern)
  group   = "rtr"
  env     = "prod"
  project = "authorizer"

  # AWS configuration
  aws_region     = "ap-south-1"
  aws_account_id = "YOUR_AWS_ACCOUNT_ID"  # TODO: Replace

  # Lambda Configuration (optimized for production)
  authorizer_name    = "rtr-prod-authorizer"
  authorizer_timeout = 10
  authorizer_memory  = 512              # Adequate memory for prod
  authorizer_runtime = "nodejs18.x"
  authorizer_handler = "index.handler"

  # Logging
  authorizer_log_level = "INFO"  # Production logging
  log_retention_days   = 30      # Longer retention

  # VPC Configuration (disabled - authorizer is stateless)
  enable_vpc = false

  # Monitoring (full monitoring for production)
  enable_xray_tracing           = true   # Enable X-Ray
  enable_reserved_concurrency   = true   # Reserve capacity
  reserved_concurrent_executions = 100   # 100 concurrent executions

  # Cognito Configuration
  jwt_user_pool_id        = "ap-south-1_XXXXXXXXX"  # TODO: Replace
  jwt_user_pool_client_id = "XXXXXXXXXXXXXXXXXXXXXXXXXX"  # TODO: Replace
  jwt_issuer              = "https://cognito-idp.ap-south-1.amazonaws.com/ap-south-1_XXXXXXXXX"  # TODO: Replace

  # Lambda Deployment (from S3 bucket)
  lambda_s3_bucket = "rtr-prod-lambda-artifacts"  # TODO: Create S3 bucket
  lambda_s3_key    = "authorizer/lambda.zip"

  # Tags
  additional_tags = {
    CostCenter   = "Engineering"
    Owner        = "DevTeam"
    Compliance   = "SOC2"
    DataSecurity = "High"
  }
}

# Outputs
output "authorizer_arn" {
  description = "Lambda authorizer ARN"
  value       = module.resources.authorizer_arn
}

output "authorizer_invoke_arn" {
  description = "Lambda authorizer invoke ARN"
  value       = module.resources.authorizer_invoke_arn
}

output "authorizer_name" {
  description = "Lambda authorizer function name"
  value       = module.resources.authorizer_name
}

output "log_group_name" {
  description = "CloudWatch log group name"
  value       = module.resources.log_group_name
}
