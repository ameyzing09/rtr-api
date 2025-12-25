# Local variables following ConnectX pattern
# Job app naming

locals {
  # Naming convention: {group}-{env}-{app}
  prefix        = "${var.group}-${var.env}"          # rtr-dev
  resource_name = "${local.prefix}-job"              # rtr-dev-job

  # Lambda function naming
  function_name = local.resource_name

  # CloudWatch Log Group
  log_group_name = "/aws/lambda/${local.function_name}"

  # Lambda ZIP file path
  lambda_zip_path = "${path.module}/../../../../dist/apps/job/lambda.zip"

  # Common tags
  common_tags = merge(
    {
      Group       = var.group
      Environment = var.env
      App         = "job"
      Component   = "lambda"
      ManagedBy   = "Terraform"
    },
    var.additional_tags
  )
}
