# RTR API - Cognito User Pool - Development Environment
# ConnectX Pattern: Single User Pool with custom tenantId attribute

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
    key    = "cognito/dev/terraform.tfstate"
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
      Component   = "cognito"
    }
  }
}

module "resources" {
  source = "../../resources"

  # Core identifiers (ConnectX pattern)
  group   = "rtr"
  env     = "dev"
  project = "cognito"

  # AWS configuration
  aws_region     = "ap-south-1"
  aws_account_id = "037610439839"  # TODO: Replace

  # User Pool Configuration (FREE TIER: 50K MAU forever)
  user_pool_name = "rtr-dev-users"

  # Password Policy (relaxed for dev)
  password_minimum_length    = 8
  password_require_lowercase = true
  password_require_numbers   = true
  password_require_symbols   = false  # Relaxed for dev
  password_require_uppercase = true
  temp_password_validity_days = 7

  # MFA Configuration (disabled for dev ease of use)
  mfa_configuration          = "OFF"  # OFF, OPTIONAL, ON
  software_token_mfa_enabled = false

  # Account Recovery (email only for dev)
  account_recovery_mechanisms = [
    {
      name     = "verified_email"
      priority = 1
    }
  ]

  # Email Configuration (Cognito default for dev)
  email_sending_account = "COGNITO_DEFAULT"  # Free 50 emails/day
  email_from_address    = null  # Use Cognito default
  email_reply_to        = null

  # User Attributes
  auto_verified_attributes = ["email"]

  # Username Configuration
  username_case_sensitive = false
  username_attributes     = ["email"]  # Users sign in with email

  # App Client Configuration
  app_client_name                      = "rtr-dev-web-client"
  access_token_validity                = 60   # 60 minutes
  id_token_validity                    = 60   # 60 minutes
  refresh_token_validity               = 30   # 30 days
  enable_token_revocation              = true
  prevent_user_existence_errors        = "ENABLED"

  # OAuth Configuration
  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_scopes                 = ["email", "openid", "profile"]
  allowed_oauth_flows_user_pool_client = true
  callback_urls                        = ["http://localhost:3000/callback"]  # Dev localhost
  logout_urls                          = ["http://localhost:3000/logout"]

  # Advanced Security (disabled for free tier)
  advanced_security_mode = "OFF"  # OFF, AUDIT, ENFORCED (costs money)

  # User Pool Add-ons
  enable_user_pool_add_ons = false  # Disable advanced features for free tier

  # Deletion Protection (disabled in dev)
  deletion_protection = "INACTIVE"  # ACTIVE or INACTIVE

  # Tags
  additional_tags = {
    FreeTier   = "true"
    CostCenter = "Engineering"
    Owner      = "DevTeam"
  }
}

# Outputs
output "user_pool_id" {
  description = "Cognito User Pool ID"
  value       = module.resources.user_pool_id
}

output "user_pool_arn" {
  description = "Cognito User Pool ARN"
  value       = module.resources.user_pool_arn
}

output "user_pool_endpoint" {
  description = "Cognito User Pool endpoint"
  value       = module.resources.user_pool_endpoint
}

output "app_client_id" {
  description = "Cognito App Client ID"
  value       = module.resources.app_client_id
}

output "app_client_secret_arn" {
  description = "Secrets Manager ARN for app client secret"
  value       = module.resources.app_client_secret_arn
  sensitive   = true
}
