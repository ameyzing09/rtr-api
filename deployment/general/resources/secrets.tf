# AWS Secrets Manager - JWT Keys and Other Secrets
# ConnectX Pattern: Central secrets, apps reference via ARN

# ============================================================================
# TLS Private Key for JWT Signing (RS256)
# ============================================================================

resource "tls_private_key" "jwt" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# ============================================================================
# JWT Keys Secret (Private + Public Key)
# ============================================================================

resource "aws_secretsmanager_secret" "jwt_keys" {
  name        = local.jwt_secret_name
  description = "JWT signing keys (RS256) for ${var.env} environment"

  recovery_window_in_days = var.env == "prod" ? 30 : 7

  tags = merge(
    local.common_tags,
    {
      Name = local.jwt_secret_name
    }
  )
}

resource "aws_secretsmanager_secret_version" "jwt_keys" {
  secret_id = aws_secretsmanager_secret.jwt_keys.id

  secret_string = jsonencode({
    algorithm   = var.jwt_key_type
    private_key = tls_private_key.jwt.private_key_pem
    public_key  = tls_private_key.jwt.public_key_pem
    key_id      = "rtr-${var.env}-key-${formatdate("YYYYMMDDhhmmss", timestamp())}"
  })

  lifecycle {
    ignore_changes = [secret_string] # Don't rotate keys on every apply
  }
}

# ============================================================================
# Database Credentials Secret
# ============================================================================
# NOTE: Database credentials are now created by the database module
# (deployment/database/resources/rds.tf) because it has the actual
# RDS endpoint and connection information. Removed from general module
# to avoid duplicate resource error.

# ============================================================================
# API Keys Secret (for external service integrations)
# ============================================================================

resource "aws_secretsmanager_secret" "api_keys" {
  name        = "${local.prefix}-api-keys"
  description = "External API keys for ${var.env} environment"

  recovery_window_in_days = var.env == "prod" ? 30 : 7

  tags = merge(
    local.common_tags,
    {
      Name = "${local.prefix}-api-keys"
    }
  )
}

resource "aws_secretsmanager_secret_version" "api_keys" {
  secret_id = aws_secretsmanager_secret.api_keys.id

  secret_string = jsonencode({
    # Add external API keys here as needed
    example_service_key = "placeholder"
    # stripe_api_key = "sk_test_xxx"
    # sendgrid_api_key = "SG.xxx"
  })
}