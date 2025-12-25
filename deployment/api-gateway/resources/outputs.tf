# Outputs for API Gateway (REST API)
# ConnectX Pattern: These values are used by apps via data sources

# ============================================================================
# API Gateway Outputs
# ============================================================================

output "api_gateway_id" {
  description = "API Gateway REST API ID"
  value       = aws_api_gateway_rest_api.api_gateway.id
}

output "api_gateway_arn" {
  description = "API Gateway REST API ARN"
  value       = aws_api_gateway_rest_api.api_gateway.arn
}

output "api_gateway_root_resource_id" {
  description = "API Gateway root resource ID"
  value       = aws_api_gateway_rest_api.api_gateway.root_resource_id
}

output "api_gateway_execution_arn" {
  description = "API Gateway execution ARN"
  value       = aws_api_gateway_rest_api.api_gateway.execution_arn
}

output "api_gateway_name" {
  description = "API Gateway name"
  value       = aws_api_gateway_rest_api.api_gateway.name
}

# ============================================================================
# Stage Outputs
# ============================================================================

output "api_gateway_stage" {
  description = "API Gateway stage name"
  value       = aws_api_gateway_stage.main.stage_name
}

output "api_gateway_stage_arn" {
  description = "API Gateway stage ARN"
  value       = aws_api_gateway_stage.main.arn
}

output "api_gateway_url" {
  description = "API Gateway invoke URL"
  value       = aws_api_gateway_stage.main.invoke_url
}

output "api_gateway_deployment_id" {
  description = "API Gateway deployment ID"
  value       = aws_api_gateway_deployment.main.id
}

# ============================================================================
# Custom Domain Outputs
# ============================================================================

output "custom_domain_name" {
  description = "Custom domain name (if enabled)"
  value       = var.enable_custom_domain ? aws_api_gateway_domain_name.main[0].domain_name : null
}

output "custom_domain_regional_domain_name" {
  description = "Custom domain regional domain name for Route53 (if enabled)"
  value       = var.enable_custom_domain ? aws_api_gateway_domain_name.main[0].regional_domain_name : null
}

output "custom_domain_regional_zone_id" {
  description = "Custom domain regional zone ID for Route53 (if enabled)"
  value       = var.enable_custom_domain ? aws_api_gateway_domain_name.main[0].regional_zone_id : null
}

# ============================================================================
# Authorizer Outputs
# ============================================================================

output "authorizer_id" {
  description = "Lambda authorizer ID"
  value       = var.enable_authorizer ? aws_api_gateway_authorizer.jwt[0].id : null
}

output "authorizer_arn" {
  description = "Lambda authorizer ARN"
  value       = var.enable_authorizer ? data.aws_lambda_function.authorizer[0].arn : null
}

output "authorizer_name" {
  description = "Lambda authorizer name"
  value       = var.enable_authorizer ? aws_api_gateway_authorizer.jwt[0].name : null
}

output "authorizer_invocation_role_arn" {
  description = "Authorizer invocation role ARN"
  value       = var.enable_authorizer ? aws_iam_role.authorizer_invocation[0].arn : null
}

# ============================================================================
# CloudWatch Outputs
# ============================================================================

output "access_log_group_name" {
  description = "CloudWatch log group name for access logs"
  value       = var.enable_access_logs ? aws_cloudwatch_log_group.access_logs[0].name : null
}

output "access_log_group_arn" {
  description = "CloudWatch log group ARN for access logs"
  value       = var.enable_access_logs ? aws_cloudwatch_log_group.access_logs[0].arn : null
}

output "cloudwatch_role_arn" {
  description = "CloudWatch role ARN for API Gateway logging"
  value       = aws_iam_role.cloudwatch.arn
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

output "endpoint_type" {
  description = "API Gateway endpoint type"
  value       = "REGIONAL"
}

# ============================================================================
# Integration Information (for apps)
# ============================================================================

output "throttle_settings" {
  description = "Throttle settings"
  value = {
    burst_limit = var.throttle_burst_limit
    rate_limit  = var.throttle_rate_limit
  }
}

output "stage_settings" {
  description = "Stage configuration"
  value = {
    name                 = aws_api_gateway_stage.main.stage_name
    logging_level        = var.logging_level
    data_trace_enabled   = var.enable_data_trace
    xray_tracing_enabled = var.enable_xray_tracing
  }
}
