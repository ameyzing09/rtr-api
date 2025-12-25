# Variables for API Gateway deployment
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
# API Gateway Configuration
# ============================================================================

variable "api_name" {
  description = "Name for the API Gateway"
  type        = string
}

variable "api_description" {
  description = "Description for the API Gateway"
  type        = string
}

# ============================================================================
# Throttling Configuration
# ============================================================================

variable "throttle_burst_limit" {
  description = "Throttle burst limit (requests)"
  type        = number
}

variable "throttle_rate_limit" {
  description = "Throttle rate limit (requests per second)"
  type        = number
}

# ============================================================================
# Logging Configuration
# ============================================================================

variable "enable_access_logs" {
  description = "Enable access logs for API Gateway"
  type        = bool
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
}

variable "logging_level" {
  description = "Logging level (OFF, ERROR, INFO)"
  type        = string
}

variable "enable_data_trace" {
  description = "Enable data trace logging (logs full request/response)"
  type        = bool
}

variable "enable_xray_tracing" {
  description = "Enable X-Ray tracing"
  type        = bool
}

# ============================================================================
# Stage Configuration
# ============================================================================

variable "stage_name" {
  description = "Stage name (defaults to environment)"
  type        = string
}

# ============================================================================
# Custom Domain Configuration
# ============================================================================

variable "enable_custom_domain" {
  description = "Enable custom domain for API Gateway"
  type        = bool
}

variable "domain_name" {
  description = "Custom domain name"
  type        = string
}

variable "certificate_arn" {
  description = "ACM certificate ARN for custom domain"
  type        = string
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID for DNS record"
  type        = string
}

# ============================================================================
# Lambda Authorizer Configuration
# ============================================================================

variable "enable_authorizer" {
  description = "Enable Lambda authorizer"
  type        = bool
}

variable "authorizer_name" {
  description = "Name for the Lambda authorizer"
  type        = string
}

variable "authorizer_type" {
  description = "Authorizer type (REQUEST or TOKEN)"
  type        = string
}

variable "authorizer_function_name" {
  description = "Lambda function name for authorization (will be looked up via data source)"
  type        = string
}

variable "authorizer_cache_ttl" {
  description = "Authorizer result cache TTL in seconds"
  type        = number
}

variable "authorizer_identity_source" {
  description = "Identity source for authorizer (e.g., method.request.header.Authorization)"
  type        = string
}

# ============================================================================
# CloudWatch Alarms
# ============================================================================

variable "alarm_4xx_threshold" {
  description = "Threshold for 4XX error alarm"
  type        = number
}

variable "alarm_5xx_threshold" {
  description = "Threshold for 5XX error alarm"
  type        = number
}

variable "alarm_latency_threshold" {
  description = "Threshold for latency alarm (milliseconds)"
  type        = number
}

variable "alarm_sns_topic_arn" {
  description = "SNS topic ARN for alarm notifications"
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
