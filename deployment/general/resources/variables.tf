# ConnectX Pattern: All variables declared here with NO defaults for environment-specific values
# Defaults set in environments/{env}/main.tf

# ============================================================================
# Core Identifiers (ConnectX Pattern)
# ============================================================================

variable "group" {
  type        = string
  description = "Group identifier (e.g., rtr)"
}

variable "env" {
  type        = string
  description = "Environment (dev, ppe, prod)"
}

variable "project" {
  type        = string
  description = "Project name (general, dynamoDB, cognito, api-gateway)"
}

# ============================================================================
# AWS Configuration
# ============================================================================

variable "aws_region" {
  type        = string
  description = "AWS region for resource deployment"
}

variable "aws_account_id" {
  type        = string
  description = "AWS account ID"
}

# ============================================================================
# VPC Configuration
# ============================================================================

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for VPC"
}

variable "availability_zones" {
  type        = list(string)
  description = "List of availability zones"
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for private subnets"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for public subnets"
}

variable "database_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for database subnets"
}

# ============================================================================
# S3 Configuration
# ============================================================================

variable "enable_s3_versioning" {
  type        = bool
  description = "Enable S3 bucket versioning"
}

variable "s3_lifecycle_days" {
  type        = number
  description = "Days after which objects transition to cheaper storage class"
}

# ============================================================================
# Secrets Configuration
# ============================================================================

variable "jwt_key_type" {
  type        = string
  description = "JWT key algorithm (RS256, ES256, HS256)"
}

# ============================================================================
# Tags
# ============================================================================

variable "additional_tags" {
  type        = map(string)
  description = "Additional tags to apply to all resources"
  default     = {}
}
