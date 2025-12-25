# API Gateway routes for Auth app
# Routes: POST /auth/login, POST /auth/federate, POST /auth/refresh, POST /auth/logout

# ============================================================================
# /auth Resource
# ============================================================================

resource "aws_api_gateway_resource" "auth" {
  rest_api_id = data.aws_api_gateway_rest_api.main.id
  parent_id   = data.aws_api_gateway_resource.root.id
  path_part   = "auth"
}

# ============================================================================
# POST /auth/login
# ============================================================================

resource "aws_api_gateway_resource" "login" {
  rest_api_id = data.aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.auth.id
  path_part   = "login"
}

resource "aws_api_gateway_method" "login" {
  rest_api_id   = data.aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.login.id
  http_method   = "POST"
  authorization = "NONE"  # Public endpoint

  request_parameters = {
    "method.request.header.Content-Type" = true
  }
}

resource "aws_api_gateway_integration" "login" {
  rest_api_id             = data.aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.login.id
  http_method             = aws_api_gateway_method.login.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.auth.invoke_arn
}

resource "aws_api_gateway_method_response" "login_200" {
  rest_api_id = data.aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.login.id
  http_method = aws_api_gateway_method.login.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

# ============================================================================
# POST /auth/federate
# ============================================================================

resource "aws_api_gateway_resource" "federate" {
  rest_api_id = data.aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.auth.id
  path_part   = "federate"
}

resource "aws_api_gateway_method" "federate" {
  rest_api_id   = data.aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.federate.id
  http_method   = "POST"
  authorization = "NONE"  # Public endpoint

  request_parameters = {
    "method.request.header.Content-Type" = true
  }
}

resource "aws_api_gateway_integration" "federate" {
  rest_api_id             = data.aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.federate.id
  http_method             = aws_api_gateway_method.federate.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.auth.invoke_arn
}

resource "aws_api_gateway_method_response" "federate_200" {
  rest_api_id = data.aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.federate.id
  http_method = aws_api_gateway_method.federate.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

# ============================================================================
# POST /auth/refresh (Protected)
# ============================================================================

resource "aws_api_gateway_resource" "refresh" {
  rest_api_id = data.aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.auth.id
  path_part   = "refresh"
}

resource "aws_api_gateway_method" "refresh" {
  rest_api_id   = data.aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.refresh.id
  http_method   = "POST"
  authorization = "CUSTOM"
  authorizer_id = data.aws_api_gateway_authorizer.jwt[0].id

  request_parameters = {
    "method.request.header.Authorization" = true
    "method.request.header.Content-Type"  = true
  }
}

resource "aws_api_gateway_integration" "refresh" {
  rest_api_id             = data.aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.refresh.id
  http_method             = aws_api_gateway_method.refresh.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.auth.invoke_arn
}

resource "aws_api_gateway_method_response" "refresh_200" {
  rest_api_id = data.aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.refresh.id
  http_method = aws_api_gateway_method.refresh.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

# ============================================================================
# POST /auth/logout (Protected)
# ============================================================================

resource "aws_api_gateway_resource" "logout" {
  rest_api_id = data.aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.auth.id
  path_part   = "logout"
}

resource "aws_api_gateway_method" "logout" {
  rest_api_id   = data.aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.logout.id
  http_method   = "POST"
  authorization = "CUSTOM"
  authorizer_id = data.aws_api_gateway_authorizer.jwt[0].id

  request_parameters = {
    "method.request.header.Authorization" = true
    "method.request.header.Content-Type"  = true
  }
}

resource "aws_api_gateway_integration" "logout" {
  rest_api_id             = data.aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.logout.id
  http_method             = aws_api_gateway_method.logout.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.auth.invoke_arn
}

resource "aws_api_gateway_method_response" "logout_200" {
  rest_api_id = data.aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.logout.id
  http_method = aws_api_gateway_method.logout.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

# ============================================================================
# CORS OPTIONS Methods
# ============================================================================

# OPTIONS /auth/login
resource "aws_api_gateway_method" "login_options" {
  rest_api_id   = data.aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.login.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "login_options" {
  rest_api_id = data.aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.login.id
  http_method = aws_api_gateway_method.login_options.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "login_options_200" {
  rest_api_id = data.aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.login.id
  http_method = aws_api_gateway_method.login_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "login_options" {
  rest_api_id = data.aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.login.id
  http_method = aws_api_gateway_method.login_options.http_method
  status_code = aws_api_gateway_method_response.login_options_200.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,Authorization'"
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

# OPTIONS /auth/federate
resource "aws_api_gateway_method" "federate_options" {
  rest_api_id   = data.aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.federate.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "federate_options" {
  rest_api_id = data.aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.federate.id
  http_method = aws_api_gateway_method.federate_options.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "federate_options_200" {
  rest_api_id = data.aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.federate.id
  http_method = aws_api_gateway_method.federate_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "federate_options" {
  rest_api_id = data.aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.federate.id
  http_method = aws_api_gateway_method.federate_options.http_method
  status_code = aws_api_gateway_method_response.federate_options_200.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,Authorization'"
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

# ============================================================================
# API Gateway Deployment
# ============================================================================

resource "aws_api_gateway_deployment" "auth" {
  rest_api_id = data.aws_api_gateway_rest_api.main.id

  # Force new deployment on route changes
  triggers = {
    redeployment = sha256(jsonencode([
      aws_api_gateway_integration.login.id,
      aws_api_gateway_integration.federate.id,
      aws_api_gateway_integration.refresh.id,
      aws_api_gateway_integration.logout.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_method.login,
    aws_api_gateway_method.federate,
    aws_api_gateway_method.refresh,
    aws_api_gateway_method.logout,
    aws_api_gateway_integration.login,
    aws_api_gateway_integration.federate,
    aws_api_gateway_integration.refresh,
    aws_api_gateway_integration.logout,
  ]
}

# ============================================================================
# Stage
# ============================================================================

resource "aws_api_gateway_stage" "auth" {
  deployment_id = aws_api_gateway_deployment.auth.id
  rest_api_id   = data.aws_api_gateway_rest_api.main.id
  stage_name    = var.env

  # Access logging
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_access_logs.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      caller         = "$context.identity.caller"
      user           = "$context.identity.user"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      resourcePath   = "$context.resourcePath"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
    })
  }

  # X-Ray tracing
  xray_tracing_enabled = var.env == "prod" ? true : false

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "api_access_logs" {
  name              = "/aws/apigateway/${local.resource_name}"
  retention_in_days = var.env == "prod" ? 30 : 7

  tags = local.common_tags
}
