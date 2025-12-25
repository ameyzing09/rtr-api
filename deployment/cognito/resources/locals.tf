# Local variables following ConnectX pattern
# Consistent naming across all resources

locals {
  # Naming convention: {group}-{env}-{project}
  prefix        = "${var.group}-${var.env}"          # rtr-dev
  resource_name = "${local.prefix}-${var.project}"   # rtr-dev-cognito

  # User Pool naming
  user_pool_name = var.user_pool_name != "" ? var.user_pool_name : "${local.resource_name}-users"

  # App Client naming
  app_client_name = var.app_client_name != "" ? var.app_client_name : "${local.resource_name}-client"

  # Secrets Manager naming
  app_client_secret_name = "${local.resource_name}-client-secret"

  # Domain naming (if needed)
  user_pool_domain = "${local.prefix}-auth"  # rtr-dev-auth

  # Common tags
  common_tags = merge(
    {
      Group       = var.group
      Environment = var.env
      Project     = var.project
      Component   = "cognito"
      ManagedBy   = "Terraform"
    },
    var.additional_tags
  )
}
