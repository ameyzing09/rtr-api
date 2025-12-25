# Lambda function for Job app
# Handles: GET/POST/PUT/DELETE /jobs

# ============================================================================
# CloudWatch Log Group
# ============================================================================

resource "aws_cloudwatch_log_group" "job" {
  name              = local.log_group_name
  retention_in_days = var.env == "prod" ? 30 : 7

  tags = local.common_tags
}

# ============================================================================
# Lambda Function
# ============================================================================

resource "aws_lambda_function" "job" {
  function_name = local.function_name
  role          = data.aws_iam_role.lambda_execution.arn
  handler       = var.lambda_handler
  runtime       = var.lambda_runtime
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory

  # Lambda deployment package
  filename         = local.lambda_zip_path
  source_code_hash = fileexists(local.lambda_zip_path) ? filebase64sha256(local.lambda_zip_path) : null

  # VPC Configuration (conditional)
  dynamic "vpc_config" {
    for_each = var.enable_vpc ? [1] : []
    content {
      subnet_ids         = data.aws_subnets.private.ids
      security_group_ids = [data.aws_security_group.lambda.id]
    }
  }

  # Environment variables
  environment {
    variables = {
      NODE_ENV   = var.env
      AWS_REGION = var.aws_region
      LOG_LEVEL  = var.env == "prod" ? "info" : "debug"

      # Database configuration
      DB_HOST       = data.aws_db_instance.main.address
      DB_PORT       = data.aws_db_instance.main.port
      DB_NAME       = data.aws_db_instance.main.db_name
      DB_SECRET_ARN = data.aws_secretsmanager_secret.db_credentials.arn

      # API Gateway URL (for CORS)
      API_URL = "https://${data.aws_api_gateway_rest_api.main.id}.execute-api.${var.aws_region}.amazonaws.com/${var.env}"
    }
  }

  # Tracing (X-Ray)
  tracing_config {
    mode = var.env == "prod" ? "Active" : "PassThrough"
  }

  # Reserved concurrent executions (prod only)
  reserved_concurrent_executions = var.env == "prod" ? 10 : -1

  tags = local.common_tags

  depends_on = [
    aws_cloudwatch_log_group.job
  ]
}

# ============================================================================
# Lambda Permission for API Gateway
# ============================================================================

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.job.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${data.aws_api_gateway_rest_api.main.execution_arn}/*/*/*"
}

# ============================================================================
# CloudWatch Alarms (Prod only)
# ============================================================================

resource "aws_cloudwatch_metric_alarm" "job_errors" {
  count = var.env == "prod" ? 1 : 0

  alarm_name          = "${local.function_name}-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "Job Lambda function error rate"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.job.function_name
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "job_duration" {
  count = var.env == "prod" ? 1 : 0

  alarm_name          = "${local.function_name}-duration"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Average"
  threshold           = var.lambda_timeout * 800  # 80% of timeout
  alarm_description   = "Job Lambda function duration"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.job.function_name
  }

  tags = local.common_tags
}
