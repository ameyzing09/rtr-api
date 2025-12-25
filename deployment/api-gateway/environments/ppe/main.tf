# RTR API - API Gateway - PPE Environment
# ConnectX Pattern: REST API with enhanced monitoring

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
    key    = "api-gateway/ppe/terraform.tfstate"
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
      Component   = "api-gateway"
    }
  }
}

module "resources" {
  source = "../../resources"

  # Core identifiers (ConnectX pattern)
  group   = "rtr"
  env     = "ppe"
  project = "api-gateway"

  # AWS configuration
  aws_region     = "ap-south-1"
  aws_account_id = "037610439839"  # TODO: Replace

  # API Gateway Configuration
  api_name        = "rtr-ppe-api"
  api_description = "RTR API Gateway - Pre-Production"

  # Throttling (moderate for PPE)
  throttle_burst_limit = 2000
  throttle_rate_limit  = 1000

  # Logging (detailed for PPE)
  enable_access_logs  = true
  log_retention_days  = 14
  logging_level       = "INFO"
  enable_data_trace   = false
  enable_xray_tracing = true  # Enable X-Ray for PPE

  # Stage Configuration
  stage_name = "ppe"

  # Custom Domain (optional for PPE)
  enable_custom_domain = false
  domain_name          = "api-ppe.rtr.com"
  certificate_arn      = null  # TODO: Create ACM certificate
  route53_zone_id      = null  # TODO: Get hosted zone ID

  # Lambda Authorizer Configuration
  enable_authorizer             = true
  authorizer_name               = "rtr-ppe-authorizer"
  authorizer_type               = "REQUEST"
  authorizer_function_name      = "rtr-ppe-authorizer"  # Lambda function name (looked up via data source)
  authorizer_cache_ttl          = 300
  authorizer_identity_source    = "method.request.header.Authorization"

  # CloudWatch Alarms
  alarm_4xx_threshold    = 100
  alarm_5xx_threshold    = 20
  alarm_latency_threshold = 5000  # 5 seconds
  alarm_sns_topic_arn    = null   # TODO: Create SNS topic

  # Tags
  additional_tags = {
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
