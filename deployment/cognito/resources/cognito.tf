# Cognito User Pool - Main Configuration
# ConnectX Pattern: Single User Pool with custom tenantId attribute

# ============================================================================
# Cognito User Pool
# ============================================================================

resource "aws_cognito_user_pool" "main" {
  name = local.user_pool_name

  # Deletion protection
  deletion_protection = var.deletion_protection

  # Username Configuration
  username_configuration {
    case_sensitive = var.username_case_sensitive
  }

  # Username attributes (email or phone_number)
  username_attributes = var.username_attributes

  # Auto-verified attributes
  auto_verified_attributes = var.auto_verified_attributes

  # Custom attributes for multi-tenancy
  schema {
    name                     = "tenantId"
    attribute_data_type      = "String"
    mutable                  = true
    required                 = false
    developer_only_attribute = false

    string_attribute_constraints {
      min_length = 1
      max_length = 256
    }
  }

  # Standard attributes
  schema {
    name                = "email"
    attribute_data_type = "String"
    mutable             = true
    required            = true

    string_attribute_constraints {
      min_length = 0
      max_length = 2048
    }
  }

  # Password Policy
  password_policy {
    minimum_length                   = var.password_minimum_length
    require_lowercase                = var.password_require_lowercase
    require_numbers                  = var.password_require_numbers
    require_symbols                  = var.password_require_symbols
    require_uppercase                = var.password_require_uppercase
    temporary_password_validity_days = var.temp_password_validity_days
  }

  # MFA Configuration
  mfa_configuration = var.mfa_configuration

  # Software token MFA (TOTP)
  software_token_mfa_configuration {
    enabled = var.software_token_mfa_enabled
  }

  # Account Recovery
  account_recovery_setting {
    dynamic "recovery_mechanism" {
      for_each = var.account_recovery_mechanisms
      content {
        name     = recovery_mechanism.value.name
        priority = recovery_mechanism.value.priority
      }
    }
  }

  # Email Configuration
  email_configuration {
    email_sending_account = var.email_sending_account
    from_email_address    = var.email_from_address != null ? var.email_from_address : null
    reply_to_email_address = var.email_reply_to != null ? var.email_reply_to : null
  }

  # Admin Create User Config
  admin_create_user_config {
    allow_admin_create_user_only = false

    invite_message_template {
      email_message = "Your username is {username} and temporary password is {####}."
      email_subject = "Your temporary password"
      sms_message   = "Your username is {username} and temporary password is {####}."
    }
  }

  # User Pool Add-ons (Advanced Security)
  dynamic "user_pool_add_ons" {
    for_each = var.enable_user_pool_add_ons ? [1] : []
    content {
      advanced_security_mode = var.advanced_security_mode
    }
  }

  # Device Configuration
  device_configuration {
    challenge_required_on_new_device      = true
    device_only_remembered_on_user_prompt = true
  }

  # Verification Message Template
  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
    email_subject        = "Your verification code"
    email_message        = "Your verification code is {####}."
    sms_message          = "Your verification code is {####}."
  }

  # Lambda Triggers (for future use)
  # lambda_config {
  #   pre_sign_up                    = var.pre_sign_up_lambda_arn
  #   post_confirmation              = var.post_confirmation_lambda_arn
  #   pre_authentication             = var.pre_authentication_lambda_arn
  #   post_authentication            = var.post_authentication_lambda_arn
  #   pre_token_generation           = var.pre_token_generation_lambda_arn
  #   custom_message                 = var.custom_message_lambda_arn
  # }

  tags = local.common_tags
}

# ============================================================================
# App Client
# ============================================================================

resource "aws_cognito_user_pool_client" "main" {
  name         = local.app_client_name
  user_pool_id = aws_cognito_user_pool.main.id

  # Generate secret for server-side apps
  generate_secret = true

  # Token validity
  access_token_validity  = var.access_token_validity
  id_token_validity      = var.id_token_validity
  refresh_token_validity = var.refresh_token_validity

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }

  # OAuth Configuration
  allowed_oauth_flows                  = var.allowed_oauth_flows
  allowed_oauth_scopes                 = var.allowed_oauth_scopes
  allowed_oauth_flows_user_pool_client = var.allowed_oauth_flows_user_pool_client
  callback_urls                        = var.callback_urls
  logout_urls                          = var.logout_urls
  supported_identity_providers         = ["COGNITO"]

  # Security
  enable_token_revocation       = var.enable_token_revocation
  prevent_user_existence_errors = var.prevent_user_existence_errors

  # Authentication flows
  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_PASSWORD_AUTH"
  ]

  # Read/Write Attributes
  read_attributes = [
    "email",
    "email_verified",
    "custom:tenantId"
  ]

  write_attributes = [
    "email",
    "custom:tenantId"
  ]
}

# ============================================================================
# User Pool Domain (optional)
# ============================================================================

resource "aws_cognito_user_pool_domain" "main" {
  domain       = local.user_pool_domain
  user_pool_id = aws_cognito_user_pool.main.id
}

# ============================================================================
# Store App Client Secret in Secrets Manager
# ============================================================================

resource "aws_secretsmanager_secret" "app_client_secret" {
  name        = local.app_client_secret_name
  description = "Cognito App Client Secret for ${local.resource_name}"

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "app_client_secret" {
  secret_id = aws_secretsmanager_secret.app_client_secret.id
  secret_string = jsonencode({
    client_id     = aws_cognito_user_pool_client.main.id
    client_secret = aws_cognito_user_pool_client.main.client_secret
    user_pool_id  = aws_cognito_user_pool.main.id
  })
}

# ============================================================================
# CloudWatch Log Group (for Lambda triggers)
# ============================================================================

resource "aws_cloudwatch_log_group" "cognito" {
  name              = "/aws/cognito/${local.user_pool_name}"
  retention_in_days = var.env == "prod" ? 30 : 7

  tags = local.common_tags
}
