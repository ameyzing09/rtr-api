# Variables for Cognito User Pool deployment
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
# User Pool Configuration
# ============================================================================

variable "user_pool_name" {
  description = "Name for the Cognito User Pool"
  type        = string
}

# ============================================================================
# Password Policy
# ============================================================================

variable "password_minimum_length" {
  description = "Minimum length for passwords"
  type        = number
}

variable "password_require_lowercase" {
  description = "Require lowercase letters in password"
  type        = bool
}

variable "password_require_numbers" {
  description = "Require numbers in password"
  type        = bool
}

variable "password_require_symbols" {
  description = "Require symbols in password"
  type        = bool
}

variable "password_require_uppercase" {
  description = "Require uppercase letters in password"
  type        = bool
}

variable "temp_password_validity_days" {
  description = "Number of days temporary password is valid"
  type        = number
}

# ============================================================================
# MFA Configuration
# ============================================================================

variable "mfa_configuration" {
  description = "MFA configuration (OFF, OPTIONAL, ON)"
  type        = string
}

variable "software_token_mfa_enabled" {
  description = "Enable software token MFA (TOTP)"
  type        = bool
}

# ============================================================================
# Account Recovery
# ============================================================================

variable "account_recovery_mechanisms" {
  description = "Account recovery mechanisms"
  type = list(object({
    name     = string
    priority = number
  }))
}

# ============================================================================
# Email Configuration
# ============================================================================

variable "email_sending_account" {
  description = "Email sending account (COGNITO_DEFAULT or DEVELOPER)"
  type        = string
}

variable "email_from_address" {
  description = "From email address (required if using SES)"
  type        = string
}

variable "email_reply_to" {
  description = "Reply-to email address"
  type        = string
}

# ============================================================================
# User Attributes
# ============================================================================

variable "auto_verified_attributes" {
  description = "Attributes to auto-verify (email, phone_number)"
  type        = list(string)
}

# ============================================================================
# Username Configuration
# ============================================================================

variable "username_case_sensitive" {
  description = "Whether username is case sensitive"
  type        = bool
}

variable "username_attributes" {
  description = "Attributes to use as username (email, phone_number)"
  type        = list(string)
}

# ============================================================================
# App Client Configuration
# ============================================================================

variable "app_client_name" {
  description = "Name for the app client"
  type        = string
}

variable "access_token_validity" {
  description = "Access token validity in minutes"
  type        = number
}

variable "id_token_validity" {
  description = "ID token validity in minutes"
  type        = number
}

variable "refresh_token_validity" {
  description = "Refresh token validity in days"
  type        = number
}

variable "enable_token_revocation" {
  description = "Enable token revocation"
  type        = bool
}

variable "prevent_user_existence_errors" {
  description = "Prevent user existence errors (LEGACY or ENABLED)"
  type        = string
}

# ============================================================================
# OAuth Configuration
# ============================================================================

variable "allowed_oauth_flows" {
  description = "Allowed OAuth flows (code, implicit, client_credentials)"
  type        = list(string)
}

variable "allowed_oauth_scopes" {
  description = "Allowed OAuth scopes"
  type        = list(string)
}

variable "allowed_oauth_flows_user_pool_client" {
  description = "Enable OAuth flows for user pool client"
  type        = bool
}

variable "callback_urls" {
  description = "Callback URLs for OAuth"
  type        = list(string)
}

variable "logout_urls" {
  description = "Logout URLs for OAuth"
  type        = list(string)
}

# ============================================================================
# Security Configuration
# ============================================================================

variable "advanced_security_mode" {
  description = "Advanced security mode (OFF, AUDIT, ENFORCED)"
  type        = string
}

variable "enable_user_pool_add_ons" {
  description = "Enable advanced security features (costs money)"
  type        = bool
}

variable "deletion_protection" {
  description = "Deletion protection (ACTIVE or INACTIVE)"
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
