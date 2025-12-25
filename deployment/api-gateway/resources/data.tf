# Data sources for API Gateway module
# ConnectX Pattern: Reference shared resources via data sources

# ============================================================================
# Reference Authorizer Lambda Function
# ============================================================================

data "aws_lambda_function" "authorizer" {
  count         = var.enable_authorizer ? 1 : 0
  function_name = var.authorizer_function_name
}
