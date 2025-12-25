# RTR API - Database Infrastructure - Production Environment
# ConnectX Pattern: RDS PostgreSQL with Maximum Reliability

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
    key    = "database/prod/terraform.tfstate"
    region = "ap-south-1"
  }
}

provider "aws" {
  region = "ap-south-1"

  default_tags {
    tags = {
      Environment = "prod"
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
  env     = "prod"
  project = "database"

  # AWS configuration
  aws_region     = "ap-south-1"
  aws_account_id = "YOUR_AWS_ACCOUNT_ID"  # TODO: Replace

  # RDS Configuration (Production-grade instance)
  engine         = "postgres"
  engine_version = "18.1"  # Latest stable minor version
  instance_class = "db.t3.medium"  # 2 vCPU, 4 GB RAM - Production ready

  # Storage (larger for production)
  allocated_storage     = 100  # 100 GB starting
  max_allocated_storage = 500  # Auto-scale up to 500 GB
  storage_type          = "gp3"  # GP3 for better IOPS
  storage_encrypted     = true

  # Database settings
  database_name = "rtr_db"
  database_port = 5432

  # Multi-AZ (REQUIRED for production)
  multi_az               = true  # Automatic failover to standby
  publicly_accessible    = false # Never expose production DB

  # Backup settings (maximum retention)
  backup_retention_period = 30  # 30 days (maximum for RDS)
  backup_window          = "03:00-04:00"  # Low traffic window
  maintenance_window     = "sun:05:00-sun:06:00"

  # Deletion protection (MUST BE ENABLED in prod)
  deletion_protection       = true
  skip_final_snapshot      = false
  final_snapshot_identifier = "rtr-prod-db-final-snapshot"

  # Performance Insights (REQUIRED for production monitoring)
  performance_insights_enabled          = true
  performance_insights_retention_period = 31  # 31 days (maximum for free tier PI)

  # Enhanced Monitoring (1 minute granularity)
  monitoring_interval = 60  # Check every 60 seconds
  monitoring_role_arn = null  # Will be created

  # CloudWatch Logs (all logs for production)
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  # Auto minor version upgrades (apply during maintenance window)
  auto_minor_version_upgrade = true

  # Parameter group settings (production-optimized)
  parameter_group_family = "postgres18"
  parameters = {
    "shared_preload_libraries"   = "pg_stat_statements"
    "log_statement"              = "mod"  # Log INSERT/UPDATE/DELETE
    "log_min_duration_statement" = "1000"  # Log queries >1s
    "max_connections"            = "200"  # Higher connection limit
    "shared_buffers"             = "{DBInstanceClassMemory/4096}"  # 25% of RAM
    "effective_cache_size"       = "{DBInstanceClassMemory*3/4096}"  # 75% of RAM
    "maintenance_work_mem"       = "524288"  # 512 MB
    "work_mem"                   = "32768"  # 32 MB
    "random_page_cost"           = "1.1"  # Optimized for SSD
  }

  # Tags
  additional_tags = {
    CostCenter = "Production"
    Owner      = "PlatformTeam"
    Compliance = "Required"
    Backup     = "Critical"
  }
}

# Outputs
output "db_endpoint" {
  description = "RDS endpoint for database connections"
  value       = module.resources.db_endpoint
}

output "db_read_replica_endpoint" {
  description = "RDS read replica endpoint (if created)"
  value       = module.resources.db_read_replica_endpoint
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
