# Outputs for Job app deployment
# ConnectX Pattern: Output critical identifiers for cross-referencing

# ============================================================================
# Lambda Outputs
# ============================================================================

output "lambda_function_name" {
  description = "Name of the Job Lambda function"
  value       = aws_lambda_function.job.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Job Lambda function"
  value       = aws_lambda_function.job.arn
}

output "lambda_invoke_arn" {
  description = "Invoke ARN of the Job Lambda function"
  value       = aws_lambda_function.job.invoke_arn
}

output "lambda_version" {
  description = "Version of the Job Lambda function"
  value       = aws_lambda_function.job.version
}

# ============================================================================
# API Gateway Outputs
# ============================================================================

output "api_gateway_stage_name" {
  description = "API Gateway stage name"
  value       = aws_api_gateway_stage.job.stage_name
}

output "api_gateway_deployment_id" {
  description = "API Gateway deployment ID"
  value       = aws_api_gateway_deployment.job.id
}

output "jobs_endpoint_url" {
  description = "Full URL for jobs endpoints"
  value       = "https://${data.aws_api_gateway_rest_api.main.id}.execute-api.${var.aws_region}.amazonaws.com/${aws_api_gateway_stage.job.stage_name}/jobs"
}

# ============================================================================
# API Routes
# ============================================================================

output "list_jobs_endpoint" {
  description = "List jobs endpoint URL (GET)"
  value       = "https://${data.aws_api_gateway_rest_api.main.id}.execute-api.${var.aws_region}.amazonaws.com/${aws_api_gateway_stage.job.stage_name}/jobs"
}

output "create_job_endpoint" {
  description = "Create job endpoint URL (POST)"
  value       = "https://${data.aws_api_gateway_rest_api.main.id}.execute-api.${var.aws_region}.amazonaws.com/${aws_api_gateway_stage.job.stage_name}/jobs"
}

output "get_job_endpoint" {
  description = "Get job by ID endpoint URL (GET)"
  value       = "https://${data.aws_api_gateway_rest_api.main.id}.execute-api.${var.aws_region}.amazonaws.com/${aws_api_gateway_stage.job.stage_name}/jobs/{id}"
}

output "update_job_endpoint" {
  description = "Update job endpoint URL (PUT)"
  value       = "https://${data.aws_api_gateway_rest_api.main.id}.execute-api.${var.aws_region}.amazonaws.com/${aws_api_gateway_stage.job.stage_name}/jobs/{id}"
}

output "delete_job_endpoint" {
  description = "Delete job endpoint URL (DELETE)"
  value       = "https://${data.aws_api_gateway_rest_api.main.id}.execute-api.${var.aws_region}.amazonaws.com/${aws_api_gateway_stage.job.stage_name}/jobs/{id}"
}

# ============================================================================
# CloudWatch Outputs
# ============================================================================

output "log_group_name" {
  description = "CloudWatch log group name for Job Lambda"
  value       = aws_cloudwatch_log_group.job.name
}

output "api_access_log_group" {
  description = "CloudWatch log group name for API access logs"
  value       = aws_cloudwatch_log_group.api_access_logs.name
}
