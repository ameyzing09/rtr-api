# RTR API - API Gateway - Production Environment
# ConnectX Pattern: REST API with custom domain

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
    key    = "api-gateway/prod/terraform.tfstate"
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
      Component   = "api-gateway"
    }
  }
}

module "resources" {
  source = "../../resources"

  # Core identifiers (ConnectX pattern)
  group   = "rtr"
  env     = "prod"
  project = "api-gateway"

  # AWS configuration
  aws_region     = "ap-south-1"
  aws_account_id = "YOUR_AWS_ACCOUNT_ID"  # TODO: Replace

  # API Gateway Configuration
  api_name        = "rtr-prod-api"
  api_description = "RTR API Gateway - Production"

  # Throttling (strict for production)
  throttle_burst_limit = 1000
  throttle_rate_limit  = 500

  # Logging (comprehensive for production)
  enable_access_logs  = true
  log_retention_days  = 30
  logging_level       = "INFO"
  enable_data_trace   = false  # Expensive in prod
  enable_xray_tracing = true   # Enable for production monitoring

  # Stage Configuration
  stage_name = "prod"

  # Custom Domain (enabled for production)
  enable_custom_domain = true
  domain_name          = "api.rtr.com"
  certificate_arn      = "arn:aws:acm:ap-south-1:037610439839:certificate/CERTIFICATE_ID"  # TODO: Replace
  route53_zone_id      = "Z1234567890ABC"  # TODO: Replace

  # Lambda Authorizer Configuration
  enable_authorizer             = true
  authorizer_name               = "rtr-prod-authorizer"
  authorizer_type               = "REQUEST"
  authorizer_function_name      = "rtr-prod-authorizer"  # Lambda function name (looked up via data source)
  authorizer_cache_ttl          = 600  # 10 minutes (longer for prod)
  authorizer_identity_source    = "method.request.header.Authorization"

  # CloudWatch Alarms (strict for production)
  alarm_4xx_threshold    = 50
  alarm_5xx_threshold    = 10
  alarm_latency_threshold = 3000  # 3 seconds
  alarm_sns_topic_arn    = "arn:aws:sns:ap-south-1:YOUR_AWS_ACCOUNT_ID:rtr-prod-alerts"  # TODO: Replace

  # Tags
  additional_tags = {
    CostCenter   = "Engineering"
    Owner        = "DevTeam"
    Compliance   = "SOC2"
    DataSecurity = "High"
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
  description = "API Gateway root resource ID"
  value       = module.resources.api_gateway_root_resource_id
}

output "api_gateway_execution_arn" {
  description = "API Gateway execution ARN"
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
  description = "Lambda authorizer ID"
  value       = module.resources.authorizer_id
}
