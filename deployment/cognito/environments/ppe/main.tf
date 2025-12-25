# RTR API - Cognito User Pool - PPE Environment
# ConnectX Pattern: Single User Pool with enhanced security

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
    key    = "cognito/ppe/terraform.tfstate"
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
      Component   = "cognito"
    }
  }
}

module "resources" {
  source = "../../resources"

  # Core identifiers (ConnectX pattern)
  group   = "rtr"
  env     = "ppe"
  project = "cognito"

  # AWS configuration
  aws_region     = "ap-south-1"
  aws_account_id = "YOUR_AWS_ACCOUNT_ID"  # TODO: Replace

  # User Pool Configuration
  user_pool_name = "rtr-ppe-users"

  # Password Policy (stricter for PPE)
  password_minimum_length    = 10
  password_require_lowercase = true
  password_require_numbers   = true
  password_require_symbols   = true  # Required for PPE
  password_require_uppercase = true
  temp_password_validity_days = 3

  # MFA Configuration (optional for PPE)
  mfa_configuration          = "OPTIONAL"  # Users can enable MFA
  software_token_mfa_enabled = true

  # Account Recovery
  account_recovery_mechanisms = [
    {
      name     = "verified_email"
      priority = 1
    },
    {
      name     = "verified_phone_number"
      priority = 2
    }
  ]

  # Email Configuration (use SES for PPE)
  email_sending_account = "DEVELOPER"  # Use SES for higher sending limits
  email_from_address    = "noreply@rtr-ppe.com"  # TODO: Verify in SES
  email_reply_to        = "support@rtr-ppe.com"

  # User Attributes
  auto_verified_attributes = ["email"]

  # Username Configuration
  username_case_sensitive = false
  username_attributes     = ["email"]

  # App Client Configuration
  app_client_name                      = "rtr-ppe-web-client"
  access_token_validity                = 30   # 30 minutes (shorter for PPE)
  id_token_validity                    = 30   # 30 minutes
  refresh_token_validity               = 7    # 7 days (shorter for PPE)
  enable_token_revocation              = true
  prevent_user_existence_errors        = "ENABLED"

  # OAuth Configuration
  allowed_oauth_flows                  = ["code"]  # Only authorization code flow
  allowed_oauth_scopes                 = ["email", "openid", "profile"]
  allowed_oauth_flows_user_pool_client = true
  callback_urls                        = ["https://rtr-ppe.com/callback"]  # PPE domain
  logout_urls                          = ["https://rtr-ppe.com/logout"]

  # Advanced Security (audit mode for PPE)
  advanced_security_mode = "AUDIT"  # Monitor but don't block

  # User Pool Add-ons
  enable_user_pool_add_ons = false

  # Deletion Protection (enabled for PPE)
  deletion_protection = "ACTIVE"

  # Tags
  additional_tags = {
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
