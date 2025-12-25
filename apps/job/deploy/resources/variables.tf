# Variables for Job app deployment
# ConnectX Pattern: No defaults

# ============================================================================
# Core Identifiers
# ============================================================================

variable "group" {
  description = "Group identifier"
  type        = string
}

variable "env" {
  description = "Environment (dev, ppe, prod)"
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

variable "lambda_timeout" {
  description = "Lambda timeout in seconds"
  type        = number
}

variable "lambda_memory" {
  description = "Lambda memory in MB"
  type        = number
}

variable "lambda_runtime" {
  description = "Lambda runtime"
  type        = string
}

variable "lambda_handler" {
  description = "Lambda handler"
  type        = string
}

# ============================================================================
# VPC Configuration
# ============================================================================

variable "enable_vpc" {
  description = "Enable VPC for Lambda"
  type        = bool
}

# ============================================================================
# Tags
# ============================================================================

variable "additional_tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
