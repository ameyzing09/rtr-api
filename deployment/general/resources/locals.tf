# Local values following ConnectX naming pattern
# Pattern: {group}-{env}-{project}

locals {
  # Core naming
  prefix        = "${var.group}-${var.env}"           # e.g., rtr-dev
  resource_name = "${local.prefix}-${var.project}"    # e.g., rtr-dev-general

  # Common tags applied to all resources
  common_tags = merge(
    {
      Group       = var.group
      Environment = var.env
      Project     = var.project
      ManagedBy   = "Terraform"
      Component   = "general"
    },
    var.additional_tags
  )

  # VPC configuration
  vpc_name = "${local.prefix}-vpc"

  # S3 bucket names (must be globally unique)
  artifacts_bucket_name    = "${local.prefix}-artifacts"
  lambda_code_bucket_name  = "${local.prefix}-lambda-code"

  # IAM role names
  lambda_execution_role_name = "${local.prefix}-${var.project}"

  # Secrets Manager secret names
  jwt_secret_name = "${local.prefix}-jwt-keys"

  # API Gateway names
  api_gateway_name = "${local.prefix}-api-gateway-base"

  # Calculate subnet count based on availability zones
  az_count = length(var.availability_zones)
}
