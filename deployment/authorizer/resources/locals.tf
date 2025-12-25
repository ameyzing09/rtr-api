# Local variables following ConnectX pattern
# Consistent naming across all resources

locals {
  # Naming convention: {group}-{env}-{project}
  prefix        = "${var.group}-${var.env}"          # rtr-dev
  resource_name = "${local.prefix}-${var.project}"   # rtr-dev-authorizer

  # Lambda function naming
  function_name = var.authorizer_name != "" ? var.authorizer_name : local.resource_name

  # CloudWatch Log Group naming
  log_group_name = "/aws/lambda/${local.function_name}"

  # Lambda ZIP file path (placeholder - will be built by CI/CD)
  lambda_zip_path = "${path.module}/../../../dist/authorizer/lambda.zip"

  # Common tags
  common_tags = merge(
    {
      Group       = var.group
      Environment = var.env
      Project     = var.project
      Component   = "authorizer"
      ManagedBy   = "Terraform"
    },
    var.additional_tags
  )
}
