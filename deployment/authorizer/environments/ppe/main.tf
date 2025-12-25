# RTR API - Lambda Authorizer - PPE Environment
# ConnectX Pattern: JWT validation with enhanced monitoring

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
    key    = "authorizer/ppe/terraform.tfstate"
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
      Component   = "authorizer"
    }
  }
}

module "resources" {
  source = "../../resources"

  # Core identifiers (ConnectX pattern)
  group   = "rtr"
  env     = "ppe"
  project = "authorizer"

  # AWS configuration
  aws_region     = "ap-south-1"
  aws_account_id = "YOUR_AWS_ACCOUNT_ID"  # TODO: Replace

  # Lambda Configuration
  authorizer_name    = "rtr-ppe-authorizer"
  authorizer_timeout = 10
  authorizer_memory  = 512              # More memory for PPE
  authorizer_runtime = "nodejs18.x"
  authorizer_handler = "index.handler"

  # Logging
  authorizer_log_level = "INFO"
  log_retention_days   = 14

  # VPC Configuration (disabled - authorizer doesn't need VPC)
  enable_vpc = false

  # Monitoring (enabled for PPE)
  enable_xray_tracing           = true  # Enable X-Ray
  enable_reserved_concurrency   = false
  reserved_concurrent_executions = 0

  # Cognito Configuration
  jwt_user_pool_id        = "ap-south-1_XXXXXXXXX"  # TODO: Replace
  jwt_user_pool_client_id = "XXXXXXXXXXXXXXXXXXXXXXXXXX"  # TODO: Replace
  jwt_issuer              = "https://cognito-idp.ap-south-1.amazonaws.com/ap-south-1_XXXXXXXXX"  # TODO: Replace

  # Lambda Deployment (from S3 bucket in PPE)
  lambda_s3_bucket = "rtr-ppe-lambda-artifacts"  # TODO: Create S3 bucket
  lambda_s3_key    = "authorizer/lambda.zip"

  # Tags
  additional_tags = {
    CostCenter = "Engineering"
    Owner      = "DevTeam"
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
