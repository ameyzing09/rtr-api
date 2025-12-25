# Auth app deployment - DEV environment
# ConnectX Pattern: All configuration in environment file

terraform {
  backend "s3" {
    bucket         = "rtr-tfstate"
    key            = "apps/auth/dev/terraform.tfstate"
    region         = "ap-south-1"
    encrypt        = true
    dynamodb_table = "rtr-terraform-locks"
  }
}

module "auth" {
  source = "../../resources"

  # Core identifiers
  group = "rtr"
  env   = "dev"

  # AWS configuration
  aws_region     = "ap-south-1"
  aws_account_id = "037610439839"  # TODO: Replace with actual AWS account ID

  # Lambda configuration
  lambda_runtime = "nodejs18.x"
  lambda_handler = "main.handler"
  lambda_timeout = 30
  lambda_memory  = 512  # Auth needs more memory for Cognito operations

  # VPC configuration
  enable_vpc = true  # Auth needs database access

  # Additional tags
  additional_tags = {
    CostCenter = "Engineering"
    Project    = "RTR-API"
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
