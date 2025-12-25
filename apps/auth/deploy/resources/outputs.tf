# Outputs for Auth app deployment
# ConnectX Pattern: Output critical identifiers for cross-referencing

# ============================================================================
# Lambda Outputs
# ============================================================================

output "lambda_function_name" {
  description = "Name of the Auth Lambda function"
  value       = aws_lambda_function.auth.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Auth Lambda function"
  value       = aws_lambda_function.auth.arn
}

output "lambda_invoke_arn" {
  description = "Invoke ARN of the Auth Lambda function"
  value       = aws_lambda_function.auth.invoke_arn
}

output "lambda_version" {
  description = "Version of the Auth Lambda function"
  value       = aws_lambda_function.auth.version
}

# ============================================================================
# API Gateway Outputs
# ============================================================================

output "api_gateway_stage_name" {
  description = "API Gateway stage name"
  value       = aws_api_gateway_stage.auth.stage_name
}

output "api_gateway_deployment_id" {
  description = "API Gateway deployment ID"
  value       = aws_api_gateway_deployment.auth.id
}

output "auth_endpoint_url" {
  description = "Full URL for auth endpoints"
  value       = "https://${data.aws_api_gateway_rest_api.main.id}.execute-api.${var.aws_region}.amazonaws.com/${aws_api_gateway_stage.auth.stage_name}/auth"
}

# ============================================================================
# API Routes
# ============================================================================

output "login_endpoint" {
  description = "Login endpoint URL"
  value       = "https://${data.aws_api_gateway_rest_api.main.id}.execute-api.${var.aws_region}.amazonaws.com/${aws_api_gateway_stage.auth.stage_name}/auth/login"
}

output "federate_endpoint" {
  description = "Federate endpoint URL"
  value       = "https://${data.aws_api_gateway_rest_api.main.id}.execute-api.${var.aws_region}.amazonaws.com/${aws_api_gateway_stage.auth.stage_name}/auth/federate"
}

output "refresh_endpoint" {
  description = "Refresh token endpoint URL"
  value       = "https://${data.aws_api_gateway_rest_api.main.id}.execute-api.${var.aws_region}.amazonaws.com/${aws_api_gateway_stage.auth.stage_name}/auth/refresh"
}

output "logout_endpoint" {
  description = "Logout endpoint URL"
  value       = "https://${data.aws_api_gateway_rest_api.main.id}.execute-api.${var.aws_region}.amazonaws.com/${aws_api_gateway_stage.auth.stage_name}/auth/logout"
}

# ============================================================================
# CloudWatch Outputs
# ============================================================================

output "log_group_name" {
  description = "CloudWatch log group name for Auth Lambda"
  value       = aws_cloudwatch_log_group.auth.name
}

output "api_access_log_group" {
  description = "CloudWatch log group name for API access logs"
  value       = aws_cloudwatch_log_group.api_access_logs.name
}
