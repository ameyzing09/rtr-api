# Local variables following ConnectX pattern
# Consistent naming across all resources

locals {
  # Naming convention: {group}-{env}-{project}
  prefix        = "${var.group}-${var.env}"          # rtr-dev
  resource_name = "${local.prefix}-${var.project}"   # rtr-dev-api-gateway

  # API Gateway naming
  api_name = var.api_name != "" ? var.api_name : "${local.prefix}-api"

  # Stage naming
  stage_name = var.stage_name != "" ? var.stage_name : var.env

  # Authorizer naming
  authorizer_name = var.authorizer_name != "" ? var.authorizer_name : "${local.prefix}-authorizer"

  # CloudWatch Log Group naming
  access_log_group_name = "/aws/apigateway/${local.api_name}"

  # Common tags
  common_tags = merge(
    {
      Group       = var.group
      Environment = var.env
      Project     = var.project
      Component   = "api-gateway"
      ManagedBy   = "Terraform"
    },
    var.additional_tags
  )
}
