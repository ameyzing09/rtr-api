# First-run script to create Terraform state S3 bucket - DEV
# Run this ONCE before deploying any infrastructure
# This uses LOCAL state (not S3 backend)

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # NO BACKEND - uses local state file
  # After running this, never run again
}

provider "aws" {
  region = "ap-south-1"

  default_tags {
    tags = {
      Project     = "rtr-api"
      ManagedBy   = "Terraform"
      Environment = "shared"
    }
  }
}

# S3 bucket for Terraform state (shared across all environments)
resource "aws_s3_bucket" "terraform_state" {
  bucket = "rtr-tfstate"

  lifecycle {
    prevent_destroy = true  # Prevent accidental deletion
  }

  tags = {
    Name = "RTR Terraform State"
  }
}

# Enable versioning for state history
resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Enable encryption at rest
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block all public access
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle policy to manage old versions
resource "aws_s3_bucket_lifecycle_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    id     = "delete-old-versions"
    status = "Enabled"

    filter {}  # Apply to all objects in bucket

    noncurrent_version_expiration {
      noncurrent_days = 90  # Keep old versions for 90 days
    }
  }
}

# DynamoDB table for state locking
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "rtr-terraform-locks"
  billing_mode = "PAY_PER_REQUEST"  # FREE TIER: 25 WCU/RCU
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  lifecycle {
    prevent_destroy = true  # Prevent accidental deletion
  }

  tags = {
    Name = "RTR Terraform State Locks"
  }
}

# Outputs
output "state_bucket" {
  description = "S3 bucket for Terraform state"
  value       = aws_s3_bucket.terraform_state.id
}

output "state_bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.terraform_state.arn
}

output "lock_table" {
  description = "DynamoDB table for state locking"
  value       = aws_dynamodb_table.terraform_locks.id
}

output "lock_table_arn" {
  description = "DynamoDB table ARN"
  value       = aws_dynamodb_table.terraform_locks.arn
}
