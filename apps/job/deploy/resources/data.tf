# Data sources for Job app
# ConnectX Pattern: Reference shared resources via data sources

# ============================================================================
# VPC Resources (from deployment/general)
# ============================================================================

data "aws_vpc" "main" {
  tags = {
    Name = "${var.group}-${var.env}-vpc"
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }

  tags = {
    Tier = "private"
  }
}

data "aws_security_group" "lambda" {
  vpc_id = data.aws_vpc.main.id

  tags = {
    Name = "${var.group}-${var.env}-lambda-sg"
  }
}

# ============================================================================
# IAM Resources (from deployment/general)
# ============================================================================

data "aws_iam_role" "lambda_execution" {
  name = "${var.group}-${var.env}-lambda-execution-role"
}

# ============================================================================
# API Gateway Resources (from deployment/api-gateway)
# ============================================================================

data "aws_api_gateway_rest_api" "main" {
  name = "${var.group}-${var.env}-api"
}

data "aws_api_gateway_resource" "root" {
  rest_api_id = data.aws_api_gateway_rest_api.main.id
  path        = "/"
}

# ============================================================================
# Authorizer (from deployment/authorizer)
# ============================================================================

data "aws_api_gateway_authorizers" "main" {
  rest_api_id = data.aws_api_gateway_rest_api.main.id
}

data "aws_api_gateway_authorizer" "jwt" {
  count = length(data.aws_api_gateway_authorizers.main.ids) > 0 ? 1 : 0

  rest_api_id   = data.aws_api_gateway_rest_api.main.id
  authorizer_id = data.aws_api_gateway_authorizers.main.ids[0]
}

# ============================================================================
# Database Resources (from deployment/database)
# ============================================================================

data "aws_db_instance" "main" {
  db_instance_identifier = "${var.group}-${var.env}-db"
}

data "aws_secretsmanager_secret" "db_credentials" {
  name = "${var.group}-${var.env}-db-credentials"
}

data "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = data.aws_secretsmanager_secret.db_credentials.id
}
