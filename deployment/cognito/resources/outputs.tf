# Outputs for Cognito User Pool
# ConnectX Pattern: These values are used by apps via data sources

# ============================================================================
# User Pool Outputs
# ============================================================================

output "user_pool_id" {
  description = "Cognito User Pool ID"
  value       = aws_cognito_user_pool.main.id
}

output "user_pool_arn" {
  description = "Cognito User Pool ARN"
  value       = aws_cognito_user_pool.main.arn
}

output "user_pool_endpoint" {
  description = "Cognito User Pool endpoint"
  value       = aws_cognito_user_pool.main.endpoint
}

output "user_pool_name" {
  description = "Cognito User Pool name"
  value       = aws_cognito_user_pool.main.name
}

# ============================================================================
# App Client Outputs
# ============================================================================

output "app_client_id" {
  description = "Cognito App Client ID"
  value       = aws_cognito_user_pool_client.main.id
}

output "app_client_secret" {
  description = "Cognito App Client Secret (sensitive)"
  value       = aws_cognito_user_pool_client.main.client_secret
  sensitive   = true
}

# ============================================================================
# Secrets Manager Outputs
# ============================================================================

output "app_client_secret_arn" {
  description = "Secrets Manager ARN for app client secret"
  value       = aws_secretsmanager_secret.app_client_secret.arn
}

output "app_client_secret_name" {
  description = "Secrets Manager secret name for app client secret"
  value       = aws_secretsmanager_secret.app_client_secret.name
}

# ============================================================================
# Domain Outputs
# ============================================================================

output "user_pool_domain" {
  description = "Cognito User Pool domain"
  value       = aws_cognito_user_pool_domain.main.domain
}

output "user_pool_domain_cloudfront" {
  description = "CloudFront distribution for Cognito hosted UI"
  value       = aws_cognito_user_pool_domain.main.cloudfront_distribution_arn
}

# ============================================================================
# OAuth Endpoints
# ============================================================================

output "oauth_authorize_url" {
  description = "OAuth 2.0 authorization endpoint"
  value       = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${var.aws_region}.amazoncognito.com/oauth2/authorize"
}

output "oauth_token_url" {
  description = "OAuth 2.0 token endpoint"
  value       = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${var.aws_region}.amazoncognito.com/oauth2/token"
}

output "oauth_userinfo_url" {
  description = "OAuth 2.0 userInfo endpoint"
  value       = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${var.aws_region}.amazoncognito.com/oauth2/userInfo"
}

output "jwks_uri" {
  description = "JSON Web Key Set URI"
  value       = "https://cognito-idp.${var.aws_region}.amazonaws.com/${aws_cognito_user_pool.main.id}/.well-known/jwks.json"
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

output "mfa_configuration" {
  description = "MFA configuration (OFF, OPTIONAL, ON)"
  value       = aws_cognito_user_pool.main.mfa_configuration
}
