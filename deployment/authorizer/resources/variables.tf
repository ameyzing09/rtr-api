# Variables for Lambda Authorizer deployment
# ConnectX Pattern: No defaults, all values from environment-specific configs

# ============================================================================
# Core Identifiers (ConnectX pattern)
# ============================================================================

variable "group" {
  description = "Group/organization identifier"
  type        = string
}

variable "env" {
  description = "Environment (dev, ppe, prod)"
  type        = string
}

variable "project" {
  description = "Project identifier"
  type        = string
}

# ============================================================================
# AWS Configuration
# ============================================================================

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}

# ============================================================================
# Lambda Configuration
# ============================================================================

variable "authorizer_name" {
  description = "Name for the Lambda authorizer function"
  type        = string
}

variable "authorizer_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
}

variable "authorizer_memory" {
  description = "Lambda function memory in MB"
  type        = number
}

variable "authorizer_runtime" {
  description = "Lambda runtime (nodejs18.x, nodejs20.x, etc.)"
  type        = string
}

variable "authorizer_handler" {
  description = "Lambda handler (e.g., index.handler)"
  type        = string
}

variable "authorizer_log_level" {
  description = "Log level for Lambda function (DEBUG, INFO, WARN, ERROR)"
  type        = string
}

# ============================================================================
# VPC Configuration (optional)
# ============================================================================

variable "enable_vpc" {
  description = "Enable VPC configuration for Lambda"
  type        = bool
}

# ============================================================================
# Monitoring Configuration
# ============================================================================

variable "enable_xray_tracing" {
  description = "Enable X-Ray tracing"
  type        = bool
}

variable "enable_reserved_concurrency" {
  description = "Enable reserved concurrency"
  type        = bool
}

variable "reserved_concurrent_executions" {
  description = "Number of reserved concurrent executions"
  type        = number
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
}

# ============================================================================
# Environment Variables for Lambda
# ============================================================================

variable "jwt_user_pool_id" {
  description = "Cognito User Pool ID for JWT validation"
  type        = string
}

variable "jwt_user_pool_client_id" {
  description = "Cognito App Client ID for JWT validation"
  type        = string
}

variable "jwt_issuer" {
  description = "JWT issuer URL"
  type        = string
}

# ============================================================================
# Lambda Deployment
# ============================================================================

variable "lambda_s3_bucket" {
  description = "S3 bucket containing Lambda ZIP file (optional, uses local ZIP if null)"
  type        = string
}

variable "lambda_s3_key" {
  description = "S3 key for Lambda ZIP file"
  type        = string
}

# ============================================================================
# Tags
# ============================================================================

variable "additional_tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {}
}
