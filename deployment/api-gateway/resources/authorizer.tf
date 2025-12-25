# Lambda Authorizer for JWT validation (REST API)
# ConnectX Pattern: REQUEST authorizer with IAM role

# ============================================================================
# Lambda Authorizer
# ============================================================================

resource "aws_api_gateway_authorizer" "jwt" {
  count = var.enable_authorizer ? 1 : 0

  name                             = local.authorizer_name
  rest_api_id                      = aws_api_gateway_rest_api.api_gateway.id
  type                             = var.authorizer_type
  authorizer_uri                   = data.aws_lambda_function.authorizer[0].invoke_arn
  authorizer_credentials           = aws_iam_role.authorizer_invocation[0].arn
  authorizer_result_ttl_in_seconds = var.authorizer_cache_ttl
  identity_source                  = var.authorizer_identity_source
}

# ============================================================================
# IAM Role for API Gateway to Invoke Authorizer Lambda
# ============================================================================

resource "aws_iam_role" "authorizer_invocation" {
  count = var.enable_authorizer ? 1 : 0
  name  = "${local.authorizer_name}-invocation-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "apigateway.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "authorizer_invocation" {
  count = var.enable_authorizer ? 1 : 0
  name  = "InvokeLambdaFunction"
  role  = aws_iam_role.authorizer_invocation[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "lambda:InvokeFunction"
      Resource = data.aws_lambda_function.authorizer[0].arn
    }]
  })
}

# ============================================================================
# CloudWatch Log Group for Authorizer (if Lambda has logs)
# ============================================================================

resource "aws_cloudwatch_log_group" "authorizer_logs" {
  count             = var.enable_authorizer ? 1 : 0
  name              = "/aws/lambda/${local.authorizer_name}"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

# ============================================================================
# CloudWatch Alarms for Authorizer
# ============================================================================

resource "aws_cloudwatch_metric_alarm" "authorizer_errors" {
  count               = var.enable_authorizer ? 1 : 0
  alarm_name          = "${local.authorizer_name}-errors"
  alarm_description   = "Lambda authorizer errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 10

  dimensions = {
    FunctionName = local.authorizer_name
  }

  alarm_actions = var.alarm_sns_topic_arn != null ? [var.alarm_sns_topic_arn] : []

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "authorizer_throttles" {
  count               = var.enable_authorizer ? 1 : 0
  alarm_name          = "${local.authorizer_name}-throttles"
  alarm_description   = "Lambda authorizer throttles"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Throttles"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 5

  dimensions = {
    FunctionName = local.authorizer_name
  }

  alarm_actions = var.alarm_sns_topic_arn != null ? [var.alarm_sns_topic_arn] : []

  tags = local.common_tags
}
