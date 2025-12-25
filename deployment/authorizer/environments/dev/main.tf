# RTR API - Lambda Authorizer - Development Environment
# ConnectX Pattern: JWT validation Lambda for API Gateway

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
    key    = "authorizer/dev/terraform.tfstate"
    region = "ap-south-1"
  }
}

provider "aws" {
  region = "ap-south-1"

  default_tags {
    tags = {
      Environment = "dev"
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
  env     = "dev"
  project = "authorizer"

  # AWS configuration
  aws_region     = "ap-south-1"
  aws_account_id = "037610439839"  # TODO: Replace

  # Lambda Configuration (FREE TIER: 1M requests, 400K GB-seconds/month)
  authorizer_name    = "rtr-dev-authorizer"
  authorizer_timeout = 10               # 10 seconds
  authorizer_memory  = 256              # 256 MB (minimum for Node.js)
  authorizer_runtime = "nodejs18.x"     # Node.js 18.x LTS
  authorizer_handler = "index.handler"  # index.handler function

  # Logging
  authorizer_log_level = "DEBUG"  # Verbose logging for dev
  log_retention_days   = 7        # Minimal retention

  # VPC Configuration (disabled for dev - authorizer doesn't need database access)
  enable_vpc = false

  # Monitoring (disabled for cost savings in dev)
  enable_xray_tracing           = false
  enable_reserved_concurrency   = false
  reserved_concurrent_executions = 0

  # Cognito Configuration
  # Note: These values come from deployment/cognito/
  jwt_user_pool_id        = "ap-south-1_cxbuwKQks"  # TODO: Replace after deploying Cognito
  jwt_user_pool_client_id = "69q6o2lsqid3nhq8up8g6k6j4v"  # TODO: Replace after deploying Cognito
  jwt_issuer              = "cognito-idp.ap-south-1.amazonaws.com/ap-south-1_cxbuwKQks"  # TODO: Replace

  # Lambda Deployment (uses local ZIP file for dev)
  lambda_s3_bucket = null  # null = use local ZIP file
  lambda_s3_key    = null

  # Tags
  additional_tags = {
    FreeTier   = "true"
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
  description = "Lambda authorizer invoke ARN (for API Gateway)"
  value       = module.resources.authorizer_invoke_arn
}

output "authorizer_name" {
  description = "Lambda authorizer function name"
  value       = module.resources.authorizer_name
}

output "authorizer_function_url" {
  description = "Lambda function URL (for testing)"
  value       = module.resources.authorizer_function_url
}

output "log_group_name" {
  description = "CloudWatch log group name"
  value       = module.resources.log_group_name
}
