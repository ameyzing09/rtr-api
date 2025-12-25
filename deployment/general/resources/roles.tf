# IAM Roles for Lambda Functions
# ConnectX Pattern: Shared execution role, apps reference via data source

# ============================================================================
# Lambda Execution Role
# ============================================================================

resource "aws_iam_role" "lambda_execution" {
  name = local.lambda_execution_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })

  tags = merge(
    local.common_tags,
    {
      Name = local.lambda_execution_role_name
    }
  )
}

# ============================================================================
# Basic Lambda Execution Policy (CloudWatch Logs)
# ============================================================================

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ============================================================================
# VPC Access Policy (for Lambda in VPC)
# ============================================================================

resource "aws_iam_role_policy_attachment" "lambda_vpc_execution" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# ============================================================================
# X-Ray Tracing Policy
# ============================================================================

resource "aws_iam_role_policy_attachment" "lambda_xray" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

# ============================================================================
# Custom Policy for RTR API Lambdas
# ============================================================================

resource "aws_iam_role_policy" "lambda_custom" {
  name = "${local.lambda_execution_role_name}-custom"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # DynamoDB Access (apps will use this)
      {
        Sid    = "DynamoDBAccess"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:BatchGetItem",
          "dynamodb:BatchWriteItem",
          "dynamodb:ConditionCheckItem"
        ]
        Resource = [
          "arn:aws:dynamodb:${var.aws_region}:${var.aws_account_id}:table/${local.prefix}-*"
        ]
      },

      # Secrets Manager Access (JWT keys, DB credentials)
      {
        Sid    = "SecretsManagerAccess"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          "arn:aws:secretsmanager:${var.aws_region}:${var.aws_account_id}:secret:${local.prefix}-*"
        ]
      },

      # S3 Access (artifacts bucket)
      {
        Sid    = "S3Access"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${local.artifacts_bucket_name}",
          "arn:aws:s3:::${local.artifacts_bucket_name}/*",
          "arn:aws:s3:::${local.lambda_code_bucket_name}",
          "arn:aws:s3:::${local.lambda_code_bucket_name}/*"
        ]
      },

      # Lambda Invocation (for async calls between Lambdas)
      {
        Sid    = "LambdaInvokeAccess"
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction",
          "lambda:InvokeAsync"
        ]
        Resource = [
          "arn:aws:lambda:${var.aws_region}:${var.aws_account_id}:function:${local.prefix}-*"
        ]
      },

      # Cognito Access (user pool operations)
      {
        Sid    = "CognitoAccess"
        Effect = "Allow"
        Action = [
          "cognito-idp:AdminGetUser",
          "cognito-idp:AdminCreateUser",
          "cognito-idp:AdminUpdateUserAttributes",
          "cognito-idp:AdminDeleteUser",
          "cognito-idp:ListUsers"
        ]
        Resource = [
          "arn:aws:cognito-idp:${var.aws_region}:${var.aws_account_id}:userpool/*"
        ]
      }
    ]
  })
}