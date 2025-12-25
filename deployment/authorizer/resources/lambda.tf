# Lambda Authorizer for JWT validation
# ConnectX Pattern: Shared authorizer for all API endpoints

# ============================================================================
# Lambda Function
# ============================================================================

resource "aws_lambda_function" "authorizer" {
  function_name = local.function_name
  role          = data.aws_iam_role.lambda_execution.arn
  handler       = var.authorizer_handler
  runtime       = var.authorizer_runtime
  timeout       = var.authorizer_timeout
  memory_size   = var.authorizer_memory

  # Lambda deployment package
  # Option 1: From S3 bucket (recommended for CI/CD)
  s3_bucket = var.lambda_s3_bucket != null ? var.lambda_s3_bucket : null
  s3_key    = var.lambda_s3_bucket != null ? var.lambda_s3_key : null

  # Option 2: From local file (for manual deployment)
  filename         = var.lambda_s3_bucket == null ? local.lambda_zip_path : null
  source_code_hash = var.lambda_s3_bucket == null ? fileexists(local.lambda_zip_path) ? filebase64sha256(local.lambda_zip_path) : null : null

  # Environment variables
  environment {
    variables = {
      NODE_ENV                 = var.env
      LOG_LEVEL                = var.authorizer_log_level
      COGNITO_USER_POOL_ID     = var.jwt_user_pool_id
      COGNITO_APP_CLIENT_ID    = var.jwt_user_pool_client_id
      JWT_ISSUER               = var.jwt_issuer
      AWS_NODEJS_CONNECTION_REUSE_ENABLED = "1"  # Improve performance
    }
  }

  # VPC Configuration (optional)
  dynamic "vpc_config" {
    for_each = var.enable_vpc ? [1] : []
    content {
      subnet_ids         = data.aws_subnets.private[0].ids
      security_group_ids = [data.aws_security_group.lambda[0].id]
    }
  }

  # X-Ray Tracing
  tracing_config {
    mode = var.enable_xray_tracing ? "Active" : "PassThrough"
  }

  # Reserved Concurrency
  reserved_concurrent_executions = var.enable_reserved_concurrency ? var.reserved_concurrent_executions : -1

  tags = local.common_tags

  # Ensure logs are created before function
  depends_on = [aws_cloudwatch_log_group.authorizer]
}

# ============================================================================
# CloudWatch Log Group
# ============================================================================

resource "aws_cloudwatch_log_group" "authorizer" {
  name              = local.log_group_name
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

# ============================================================================
# CloudWatch Alarms
# ============================================================================

resource "aws_cloudwatch_metric_alarm" "authorizer_errors" {
  alarm_name          = "${local.function_name}-errors"
  alarm_description   = "Lambda authorizer errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 10

  dimensions = {
    FunctionName = aws_lambda_function.authorizer.function_name
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "authorizer_throttles" {
  alarm_name          = "${local.function_name}-throttles"
  alarm_description   = "Lambda authorizer throttles"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Throttles"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 5

  dimensions = {
    FunctionName = aws_lambda_function.authorizer.function_name
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "authorizer_duration" {
  alarm_name          = "${local.function_name}-duration"
  alarm_description   = "Lambda authorizer duration (slow)"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Average"
  threshold           = 3000  # 3 seconds

  dimensions = {
    FunctionName = aws_lambda_function.authorizer.function_name
  }

  tags = local.common_tags
}

# ============================================================================
# Lambda Function URL (optional - for testing)
# ============================================================================

resource "aws_lambda_function_url" "authorizer" {
  count              = var.env == "dev" ? 1 : 0  # Only in dev for testing
  function_name      = aws_lambda_function.authorizer.function_name
  authorization_type = "NONE"
}
