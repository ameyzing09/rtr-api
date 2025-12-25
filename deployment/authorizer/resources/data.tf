# Data sources to reference central resources
# ConnectX Pattern: Reference shared resources from general module

# ============================================================================
# Reference shared Lambda execution role from general module
# ============================================================================

data "aws_iam_role" "lambda_execution" {
  name = "${var.group}-${var.env}-general"
}

# ============================================================================
# Reference VPC and Subnets (if VPC is enabled)
# ============================================================================

data "aws_vpc" "main" {
  count = var.enable_vpc ? 1 : 0

  filter {
    name   = "tag:Name"
    values = ["${var.group}-${var.env}-vpc"]
  }
}

data "aws_subnets" "private" {
  count = var.enable_vpc ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main[0].id]
  }

  filter {
    name   = "tag:Type"
    values = ["private"]
  }
}

data "aws_security_group" "lambda" {
  count = var.enable_vpc ? 1 : 0

  filter {
    name   = "group-name"
    values = ["${var.group}-${var.env}-lambda-sg"]
  }

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main[0].id]
  }
}
