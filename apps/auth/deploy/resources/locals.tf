# Local variables following ConnectX pattern
# Auth app naming

locals {
  # Naming convention: {group}-{env}-{app}
  prefix        = "${var.group}-${var.env}"          # rtr-dev
  resource_name = "${local.prefix}-auth"             # rtr-dev-auth

  # Lambda function naming
  function_name = local.resource_name

  # CloudWatch Log Group
  log_group_name = "/aws/lambda/${local.function_name}"

  # Lambda ZIP file path
  lambda_zip_path = "${path.module}/../../../../dist/apps/auth/lambda.zip"

  # Common tags
  common_tags = merge(
    {
      Group       = var.group
      Environment = var.env
      App         = "auth"
      Component   = "lambda"
      ManagedBy   = "Terraform"
    },
    var.additional_tags
  )
}
