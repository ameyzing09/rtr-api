# RTR API - Database Infrastructure - PPE Environment
# ConnectX Pattern: RDS PostgreSQL with High Availability

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
    key    = "database/ppe/terraform.tfstate"
    region = "ap-south-1"
  }
}

provider "aws" {
  region = "ap-south-1"

  default_tags {
    tags = {
      Environment = "ppe"
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
  env     = "ppe"
  project = "database"

  # AWS configuration
  aws_region     = "ap-south-1"
  aws_account_id = "YOUR_AWS_ACCOUNT_ID"  # TODO: Replace

  # RDS Configuration (Small production-like instance)
  engine         = "postgres"
  engine_version = "18.1"  # Latest stable minor version
  instance_class = "db.t3.small"  # 2 vCPU, 2 GB RAM - Better than free tier

  # Storage
  allocated_storage     = 50  # More storage for PPE
  max_allocated_storage = 200 # Auto-scaling limit
  storage_type          = "gp3"  # GP3 for better performance
  storage_encrypted     = true

  # Database settings
  database_name = "rtr_db"
  database_port = 5432

  # Multi-AZ (ENABLED for high availability)
  multi_az               = true  # Automatic failover
  publicly_accessible    = false

  # Backup settings (longer retention for PPE)
  backup_retention_period = 14  # 2 weeks
  backup_window          = "03:00-04:00"
  maintenance_window     = "sun:05:00-sun:06:00"

  # Deletion protection (ENABLED for PPE)
  deletion_protection       = true
  skip_final_snapshot      = false
  final_snapshot_identifier = "rtr-ppe-db-final-snapshot"

  # Performance Insights (ENABLED for PPE monitoring)
  performance_insights_enabled          = true
  performance_insights_retention_period = 7  # 7 days

  # Enhanced Monitoring (basic - 60 seconds)
  monitoring_interval = 60
  monitoring_role_arn = null  # Will be created

  # CloudWatch Logs
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  # Auto minor version upgrades
  auto_minor_version_upgrade = true

  # Parameter group settings
  parameter_group_family = "postgres18"
  parameters = {
    "shared_preload_libraries" = "pg_stat_statements"
    "log_statement"            = "ddl"  # Only log DDL in PPE
    "log_min_duration_statement" = "500"  # Log slow queries (>500ms)
    "max_connections"          = "100"
  }

  # Tags
  additional_tags = {
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
