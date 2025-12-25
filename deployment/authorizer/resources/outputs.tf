# Outputs for Lambda Authorizer
# ConnectX Pattern: These values are used by API Gateway

# ============================================================================
# Lambda Function Outputs
# ============================================================================

output "authorizer_arn" {
  description = "Lambda authorizer function ARN"
  value       = aws_lambda_function.authorizer.arn
}

output "authorizer_invoke_arn" {
  description = "Lambda authorizer invoke ARN (for API Gateway)"
  value       = aws_lambda_function.authorizer.invoke_arn
}

output "authorizer_name" {
  description = "Lambda authorizer function name"
  value       = aws_lambda_function.authorizer.function_name
}

output "authorizer_qualified_arn" {
  description = "Lambda authorizer qualified ARN (with version)"
  value       = aws_lambda_function.authorizer.qualified_arn
}

output "authorizer_version" {
  description = "Lambda authorizer version"
  value       = aws_lambda_function.authorizer.version
}

# ============================================================================
# Lambda Function URL (for testing in dev)
# ============================================================================

output "authorizer_function_url" {
  description = "Lambda function URL (dev only)"
  value       = var.env == "dev" ? aws_lambda_function_url.authorizer[0].function_url : null
}

# ============================================================================
# IAM Role Outputs
# ============================================================================

output "authorizer_role_arn" {
  description = "Lambda execution role ARN"
  value       = data.aws_iam_role.lambda_execution.arn
}

output "authorizer_role_name" {
  description = "Lambda execution role name"
  value       = data.aws_iam_role.lambda_execution.name
}

# ============================================================================
# CloudWatch Outputs
# ============================================================================

output "log_group_name" {
  description = "CloudWatch log group name"
  value       = aws_cloudwatch_log_group.authorizer.name
}

output "log_group_arn" {
  description = "CloudWatch log group ARN"
  value       = aws_cloudwatch_log_group.authorizer.arn
}

# ============================================================================
# General Information
# ============================================================================

output "resource_name" {
  description = "Resource naming prefix"
  value       = local.resource_name
}

output "prefix" {
  description = "Naming prefix (group-env)"
  value       = local.prefix
}

output "function_runtime" {
  description = "Lambda runtime"
  value       = aws_lambda_function.authorizer.runtime
}

output "function_timeout" {
  description = "Lambda timeout in seconds"
  value       = aws_lambda_function.authorizer.timeout
}

output "function_memory" {
  description = "Lambda memory in MB"
  value       = aws_lambda_function.authorizer.memory_size
}

# ============================================================================
# Configuration for API Gateway
# ============================================================================

output "api_gateway_configuration" {
  description = "Configuration values for API Gateway authorizer"
  value = {
    lambda_arn         = aws_lambda_function.authorizer.invoke_arn
    function_name      = aws_lambda_function.authorizer.function_name
    execution_role_arn = data.aws_iam_role.lambda_execution.arn
  }
}
