# Job app deployment - PPE environment
# ConnectX Pattern: All configuration in environment file

terraform {
  backend "s3" {
    bucket         = "rtr-tfstate"
    key            = "apps/job/ppe/terraform.tfstate"
    region         = "ap-south-1"
    encrypt        = true
    dynamodb_table = "rtr-terraform-locks"
  }
}

module "job" {
  source = "../../resources"

  # Core identifiers
  group = "rtr"
  env   = "ppe"

  # AWS configuration
  aws_region     = "ap-south-1"
  aws_account_id = "YOUR_AWS_ACCOUNT_ID"  # TODO: Replace with actual AWS account ID

  # Lambda configuration
  lambda_runtime = "nodejs18.x"
  lambda_handler = "main.handler"
  lambda_timeout = 30
  lambda_memory  = 512

  # VPC configuration
  enable_vpc = true

  # Additional tags
  additional_tags = {
    CostCenter = "Engineering"
    Project    = "RTR-API"
  }
}

# ============================================================================
# Outputs (pass-through from module)
# ============================================================================

output "lambda_function_name" {
  description = "Name of the Job Lambda function"
  value       = module.job.lambda_function_name
}

output "lambda_function_arn" {
  description = "ARN of the Job Lambda function"
  value       = module.job.lambda_function_arn
}

output "jobs_endpoint_url" {
  description = "Base URL for jobs endpoints"
  value       = module.job.jobs_endpoint_url
}

output "list_jobs_endpoint" {
  description = "List jobs endpoint (GET)"
  value       = module.job.list_jobs_endpoint
}

output "create_job_endpoint" {
  description = "Create job endpoint (POST)"
  value       = module.job.create_job_endpoint
}

output "get_job_endpoint" {
  description = "Get job by ID endpoint (GET)"
  value       = module.job.get_job_endpoint
}

output "update_job_endpoint" {
  description = "Update job endpoint (PUT)"
  value       = module.job.update_job_endpoint
}

output "delete_job_endpoint" {
  description = "Delete job endpoint (DELETE)"
  value       = module.job.delete_job_endpoint
}

output "log_group_name" {
  description = "CloudWatch log group name"
  value       = module.job.log_group_name
}
