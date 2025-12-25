# API Gateway routes for Job app
# Routes: GET/POST /jobs, GET/PUT/DELETE /jobs/{id}

# ============================================================================
# /jobs Resource
# ============================================================================

resource "aws_api_gateway_resource" "jobs" {
  rest_api_id = data.aws_api_gateway_rest_api.main.id
  parent_id   = data.aws_api_gateway_resource.root.id
  path_part   = "jobs"
}

# ============================================================================
# GET /jobs - List all jobs (Protected)
# ============================================================================

resource "aws_api_gateway_method" "list_jobs" {
  rest_api_id   = data.aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.jobs.id
  http_method   = "GET"
  authorization = "CUSTOM"
  authorizer_id = data.aws_api_gateway_authorizer.jwt[0].id

  request_parameters = {
    "method.request.header.Authorization" = true
  }
}

resource "aws_api_gateway_integration" "list_jobs" {
  rest_api_id             = data.aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.jobs.id
  http_method             = aws_api_gateway_method.list_jobs.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.job.invoke_arn
}

resource "aws_api_gateway_method_response" "list_jobs_200" {
  rest_api_id = data.aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.jobs.id
  http_method = aws_api_gateway_method.list_jobs.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

# ============================================================================
# POST /jobs - Create job (Protected)
# ============================================================================

resource "aws_api_gateway_method" "create_job" {
  rest_api_id   = data.aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.jobs.id
  http_method   = "POST"
  authorization = "CUSTOM"
  authorizer_id = data.aws_api_gateway_authorizer.jwt[0].id

  request_parameters = {
    "method.request.header.Authorization" = true
    "method.request.header.Content-Type"  = true
  }
}

resource "aws_api_gateway_integration" "create_job" {
  rest_api_id             = data.aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.jobs.id
  http_method             = aws_api_gateway_method.create_job.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.job.invoke_arn
}

resource "aws_api_gateway_method_response" "create_job_200" {
  rest_api_id = data.aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.jobs.id
  http_method = aws_api_gateway_method.create_job.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

# ============================================================================
# /jobs/{id} Resource
# ============================================================================

resource "aws_api_gateway_resource" "job_by_id" {
  rest_api_id = data.aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.jobs.id
  path_part   = "{id}"
}

# ============================================================================
# GET /jobs/{id} - Get job by ID (Protected)
# ============================================================================

resource "aws_api_gateway_method" "get_job" {
  rest_api_id   = data.aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.job_by_id.id
  http_method   = "GET"
  authorization = "CUSTOM"
  authorizer_id = data.aws_api_gateway_authorizer.jwt[0].id

  request_parameters = {
    "method.request.header.Authorization" = true
    "method.request.path.id"              = true
  }
}

resource "aws_api_gateway_integration" "get_job" {
  rest_api_id             = data.aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.job_by_id.id
  http_method             = aws_api_gateway_method.get_job.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.job.invoke_arn
}

resource "aws_api_gateway_method_response" "get_job_200" {
  rest_api_id = data.aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.job_by_id.id
  http_method = aws_api_gateway_method.get_job.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

# ============================================================================
# PUT /jobs/{id} - Update job (Protected)
# ============================================================================

resource "aws_api_gateway_method" "update_job" {
  rest_api_id   = data.aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.job_by_id.id
  http_method   = "PUT"
  authorization = "CUSTOM"
  authorizer_id = data.aws_api_gateway_authorizer.jwt[0].id

  request_parameters = {
    "method.request.header.Authorization" = true
    "method.request.header.Content-Type"  = true
    "method.request.path.id"              = true
  }
}

resource "aws_api_gateway_integration" "update_job" {
  rest_api_id             = data.aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.job_by_id.id
  http_method             = aws_api_gateway_method.update_job.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.job.invoke_arn
}

resource "aws_api_gateway_method_response" "update_job_200" {
  rest_api_id = data.aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.job_by_id.id
  http_method = aws_api_gateway_method.update_job.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

# ============================================================================
# DELETE /jobs/{id} - Delete job (Protected)
# ============================================================================

resource "aws_api_gateway_method" "delete_job" {
  rest_api_id   = data.aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.job_by_id.id
  http_method   = "DELETE"
  authorization = "CUSTOM"
  authorizer_id = data.aws_api_gateway_authorizer.jwt[0].id

  request_parameters = {
    "method.request.header.Authorization" = true
    "method.request.path.id"              = true
  }
}

resource "aws_api_gateway_integration" "delete_job" {
  rest_api_id             = data.aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.job_by_id.id
  http_method             = aws_api_gateway_method.delete_job.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.job.invoke_arn
}

resource "aws_api_gateway_method_response" "delete_job_200" {
  rest_api_id = data.aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.job_by_id.id
  http_method = aws_api_gateway_method.delete_job.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

# ============================================================================
# CORS OPTIONS Methods
# ============================================================================

# OPTIONS /jobs
resource "aws_api_gateway_method" "jobs_options" {
  rest_api_id   = data.aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.jobs.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "jobs_options" {
  rest_api_id = data.aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.jobs.id
  http_method = aws_api_gateway_method.jobs_options.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "jobs_options_200" {
  rest_api_id = data.aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.jobs.id
  http_method = aws_api_gateway_method.jobs_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "jobs_options" {
  rest_api_id = data.aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.jobs.id
  http_method = aws_api_gateway_method.jobs_options.http_method
  status_code = aws_api_gateway_method_response.jobs_options_200.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,Authorization'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

# OPTIONS /jobs/{id}
resource "aws_api_gateway_method" "job_by_id_options" {
  rest_api_id   = data.aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.job_by_id.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "job_by_id_options" {
  rest_api_id = data.aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.job_by_id.id
  http_method = aws_api_gateway_method.job_by_id_options.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "job_by_id_options_200" {
  rest_api_id = data.aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.job_by_id.id
  http_method = aws_api_gateway_method.job_by_id_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "job_by_id_options" {
  rest_api_id = data.aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.job_by_id.id
  http_method = aws_api_gateway_method.job_by_id_options.http_method
  status_code = aws_api_gateway_method_response.job_by_id_options_200.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,Authorization'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,PUT,DELETE,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

# ============================================================================
# API Gateway Deployment
# ============================================================================

resource "aws_api_gateway_deployment" "job" {
  rest_api_id = data.aws_api_gateway_rest_api.main.id

  # Force new deployment on route changes
  triggers = {
    redeployment = sha256(jsonencode([
      aws_api_gateway_integration.list_jobs.id,
      aws_api_gateway_integration.create_job.id,
      aws_api_gateway_integration.get_job.id,
      aws_api_gateway_integration.update_job.id,
      aws_api_gateway_integration.delete_job.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_method.list_jobs,
    aws_api_gateway_method.create_job,
    aws_api_gateway_method.get_job,
    aws_api_gateway_method.update_job,
    aws_api_gateway_method.delete_job,
    aws_api_gateway_integration.list_jobs,
    aws_api_gateway_integration.create_job,
    aws_api_gateway_integration.get_job,
    aws_api_gateway_integration.update_job,
    aws_api_gateway_integration.delete_job,
  ]
}

# ============================================================================
# Stage
# ============================================================================

resource "aws_api_gateway_stage" "job" {
  deployment_id = aws_api_gateway_deployment.job.id
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
