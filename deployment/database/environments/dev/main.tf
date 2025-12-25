# RTR API - Database Infrastructure - Development Environment
# ConnectX Pattern: RDS PostgreSQL optimized for FREE TIER

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }

  backend "s3" {
    bucket = "rtr-tfstate"
    key    = "database/dev/terraform.tfstate"
    region = "ap-south-1"
  }
}

provider "aws" {
  region = "ap-south-1"

  default_tags {
    tags = {
      Environment = "dev"
      Project     = "rtr-api"
      ManagedBy   = "Terraform"
      Component   = "database"
    }
  }
}

module "resources" {
  source = "../../resources"

  # Core identifiers (ConnectX pattern)
  group   = "rtr"
  env     = "dev"
  project = "database"

  # AWS configuration
  aws_region     = "ap-south-1"
  aws_account_id = "037610439839"  # TODO: Replace

  # RDS Configuration (FREE TIER OPTIMIZED)
  engine         = "postgres"
  engine_version = "18.1"  # Latest stable minor version
  instance_class = "db.t3.micro"  # 1 vCPU, 1 GB RAM - FREE TIER

  # Storage (FREE TIER: 20 GB)
  allocated_storage     = 20  # Start with free tier limit
  max_allocated_storage = 100 # Auto-scaling limit
  storage_type          = "gp2"  # General Purpose SSD
  storage_encrypted     = true

  # Database settings
  database_name = "rtr_db"
  database_port = 5432

  # Multi-AZ (disabled for dev to save costs)
  multi_az               = false
  publicly_accessible    = false  # Always private

  # Backup settings (FREE TIER: 7 days max)
  backup_retention_period = 7
  backup_window          = "03:00-04:00"  # 3-4 AM UTC
  maintenance_window     = "sun:05:00-sun:06:00"  # Sunday 5-6 AM UTC

  # Deletion protection (disabled in dev for easy cleanup)
  deletion_protection       = false
  skip_final_snapshot      = true  # Skip snapshot on destroy
  final_snapshot_identifier = null

  # Performance Insights (costs money - DISABLE for free tier)
  performance_insights_enabled          = false
  performance_insights_retention_period = null

  # Enhanced Monitoring (costs money - DISABLE for free tier)
  monitoring_interval = 0  # Disable enhanced monitoring
  monitoring_role_arn = null

  # CloudWatch Logs (basic logs are free)
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  # Auto minor version upgrades
  auto_minor_version_upgrade = true

  # Parameter group settings
  parameter_group_family = "postgres18"
  parameters = {
    "shared_preload_libraries" = "pg_stat_statements"
    "log_statement"            = "all"  # Log all queries in dev
    "log_min_duration_statement" = "100"  # Log slow queries (>100ms)
  }

  # Tags
  additional_tags = {
    FreeTier = "true"
    CostCenter = "Engineering"
    Owner      = "DevTeam"
  }
}

# Outputs
output "db_endpoint" {
  description = "RDS endpoint for database connections"
  value       = module.resources.db_endpoint
}

output "db_instance_id" {
  description = "RDS instance identifier"
  value       = module.resources.db_instance_id
}

output "db_name" {
  description = "Database name"
  value       = module.resources.db_name
}

output "db_port" {
  description = "Database port"
  value       = module.resources.db_port
}

output "db_security_group_id" {
  description = "Security group ID for RDS"
  value       = module.resources.db_security_group_id
}

output "db_credentials_secret_arn" {
  description = "Secrets Manager ARN for DB credentials"
  value       = module.resources.db_credentials_secret_arn
  sensitive   = true
}
