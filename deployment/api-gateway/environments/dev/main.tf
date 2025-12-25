# RTR API - API Gateway - Development Environment
# ConnectX Pattern: REST API with Lambda Authorizer

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
    key    = "api-gateway/dev/terraform.tfstate"
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
      Component   = "api-gateway"
    }
  }
}

module "resources" {
  source = "../../resources"

  # Core identifiers (ConnectX pattern)
  group   = "rtr"
  env     = "dev"
  project = "api-gateway"

  # AWS configuration
  aws_region     = "ap-south-1"
  aws_account_id = "037610439839"  # TODO: Replace

  # API Gateway Configuration (FREE TIER: 1M requests/month for 12 months)
  api_name        = "rtr-dev-api"
  api_description = "RTR API Gateway - Development"

  # Throttling (relaxed for dev)
  throttle_burst_limit = 5000
  throttle_rate_limit  = 2000

  # Logging (basic for dev)
  enable_access_logs  = true
  log_retention_days  = 7
  logging_level       = "INFO"
  enable_data_trace   = false  # Full request/response logging (disabled for dev)
  enable_xray_tracing = false  # X-Ray tracing (disabled for cost savings)

  # Stage Configuration
  stage_name = "dev"

  # Custom Domain (disabled for dev)
  enable_custom_domain = false
  domain_name          = "api-dev.rtr.com"
  certificate_arn      = null
  route53_zone_id      = null

  # Lambda Authorizer Configuration
  # Note: Lambda function should be deployed first via deployment/authorizer/
  enable_authorizer             = false  # Set to true after deploying authorizer Lambda
  authorizer_name               = "rtr-dev-authorizer"
  authorizer_type               = "REQUEST"
  authorizer_function_name      = "rtr-dev-authorizer"  # Lambda function name (looked up via data source)
  authorizer_cache_ttl          = 300   # 5 minutes
  authorizer_identity_source    = "method.request.header.Authorization"

  # CloudWatch Alarms (relaxed for dev)
  alarm_4xx_threshold    = 200   # Allow more errors in dev
  alarm_5xx_threshold    = 50
  alarm_latency_threshold = 10000  # 10 seconds
  alarm_sns_topic_arn    = null   # TODO: Create SNS topic for alerts

  # Tags
  additional_tags = {
    FreeTier   = "true"
    CostCenter = "Engineering"
    Owner      = "DevTeam"
  }
}

# Outputs
output "api_gateway_id" {
  description = "API Gateway ID"
  value       = module.resources.api_gateway_id
}

output "api_gateway_arn" {
  description = "API Gateway ARN"
  value       = module.resources.api_gateway_arn
}

output "api_gateway_root_resource_id" {
  description = "API Gateway root resource ID (for apps to create routes)"
  value       = module.resources.api_gateway_root_resource_id
}

output "api_gateway_execution_arn" {
  description = "API Gateway execution ARN (for Lambda permissions)"
  value       = module.resources.api_gateway_execution_arn
}

output "api_gateway_url" {
  description = "API Gateway invoke URL"
  value       = module.resources.api_gateway_url
}

output "api_gateway_stage" {
  description = "API Gateway stage name"
  value       = module.resources.api_gateway_stage
}

output "authorizer_id" {
  description = "Lambda authorizer ID (null if disabled)"
  value       = module.resources.authorizer_id
}
