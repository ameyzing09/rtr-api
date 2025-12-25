# Outputs for ConnectX Pattern
# These values are used by apps via data sources

# ============================================================================
# VPC Outputs
# ============================================================================

output "vpc_id" {
  value       = aws_vpc.main.id
  description = "VPC ID"
}

output "vpc_cidr" {
  value       = aws_vpc.main.cidr_block
  description = "VPC CIDR block"
}

output "private_subnet_ids" {
  value       = aws_subnet.private[*].id
  description = "Private subnet IDs for Lambda functions"
}

output "public_subnet_ids" {
  value       = aws_subnet.public[*].id
  description = "Public subnet IDs"
}

output "database_subnet_ids" {
  value       = aws_subnet.database[*].id
  description = "Database subnet IDs"
}

output "lambda_security_group_id" {
  value       = aws_security_group.lambda.id
  description = "Security group ID for Lambda functions"
}

# ============================================================================
# IAM Role Outputs
# ============================================================================

output "lambda_role_arn" {
  value       = aws_iam_role.lambda_execution.arn
  description = "Lambda execution role ARN"
}

output "lambda_role_name" {
  value       = aws_iam_role.lambda_execution.name
  description = "Lambda execution role name for data source lookups"
}

# ============================================================================
# Secrets Manager Outputs
# ============================================================================

output "jwt_secret_arn" {
  value       = aws_secretsmanager_secret.jwt_keys.arn
  description = "JWT keys secret ARN"
  sensitive   = true
}

output "jwt_secret_name" {
  value       = aws_secretsmanager_secret.jwt_keys.name
  description = "JWT keys secret name"
}

# db_credentials_secret_arn output removed - now created by database module

output "api_keys_secret_arn" {
  value       = aws_secretsmanager_secret.api_keys.arn
  description = "API keys secret ARN"
  sensitive   = true
}

# ============================================================================
# S3 Outputs
# ============================================================================

output "artifacts_bucket_name" {
  value       = aws_s3_bucket.artifacts.id
  description = "S3 artifacts bucket name"
}

output "artifacts_bucket_arn" {
  value       = aws_s3_bucket.artifacts.arn
  description = "S3 artifacts bucket ARN"
}

output "lambda_code_bucket_name" {
  value       = aws_s3_bucket.lambda_code.id
  description = "S3 Lambda code bucket name"
}

output "lambda_code_bucket_arn" {
  value       = aws_s3_bucket.lambda_code.arn
  description = "S3 Lambda code bucket ARN"
}

# ============================================================================
# General Outputs
# ============================================================================

output "resource_name" {
  value       = local.resource_name
  description = "Resource naming prefix"
}

output "prefix" {
  value       = local.prefix
  description = "Naming prefix (group-env)"
}
