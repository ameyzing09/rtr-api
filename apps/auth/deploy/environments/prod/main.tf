# Auth app deployment - PROD environment
# ConnectX Pattern: All configuration in environment file

terraform {
  backend "s3" {
    bucket         = "rtr-tfstate"
    key            = "apps/auth/prod/terraform.tfstate"
    region         = "ap-south-1"
    encrypt        = true
    dynamodb_table = "rtr-terraform-locks"
  }
}

module "auth" {
  source = "../../resources"

  # Core identifiers
  group = "rtr"
  env   = "prod"

  # AWS configuration
  aws_region     = "ap-south-1"
  aws_account_id = "YOUR_AWS_ACCOUNT_ID"  # TODO: Replace with actual AWS account ID

  # Lambda configuration
  lambda_runtime = "nodejs18.x"
  lambda_handler = "main.handler"
  lambda_timeout = 30
  lambda_memory  = 1024  # Higher memory for production

  # VPC configuration
  enable_vpc = true

  # Additional tags
  additional_tags = {
    CostCenter = "Engineering"
    Project    = "RTR-API"
    Compliance = "SOC2"
  }
}

# ============================================================================
# Outputs (pass-through from module)
# ============================================================================

output "lambda_function_name" {
  description = "Name of the Auth Lambda function"
  value       = module.auth.lambda_function_name
}

output "lambda_function_arn" {
  description = "ARN of the Auth Lambda function"
  value       = module.auth.lambda_function_arn
}

output "auth_endpoint_url" {
  description = "Base URL for auth endpoints"
  value       = module.auth.auth_endpoint_url
}

output "login_endpoint" {
  description = "Login endpoint URL"
  value       = module.auth.login_endpoint
}

output "federate_endpoint" {
  description = "Federate endpoint URL"
  value       = module.auth.federate_endpoint
}

output "refresh_endpoint" {
  description = "Refresh token endpoint URL"
  value       = module.auth.refresh_endpoint
}

output "logout_endpoint" {
  description = "Logout endpoint URL"
  value       = module.auth.logout_endpoint
}

output "log_group_name" {
  description = "CloudWatch log group name"
  value       = module.auth.log_group_name
}
