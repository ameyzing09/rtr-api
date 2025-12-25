# Outputs for ConnectX Pattern
# These values are used by apps via data sources

# ============================================================================
# RDS Instance Outputs
# ============================================================================

output "db_instance_id" {
  value       = aws_db_instance.main.id
  description = "RDS instance identifier"
}

output "db_instance_arn" {
  value       = aws_db_instance.main.arn
  description = "RDS instance ARN"
}

output "db_instance_resource_id" {
  value       = aws_db_instance.main.resource_id
  description = "RDS instance resource ID"
}

# ============================================================================
# Connection Information
# ============================================================================

output "db_endpoint" {
  value       = aws_db_instance.main.endpoint
  description = "RDS instance endpoint (host:port)"
}

output "db_address" {
  value       = aws_db_instance.main.address
  description = "RDS instance hostname"
}

output "db_port" {
  value       = aws_db_instance.main.port
  description = "RDS instance port"
}

output "db_name" {
  value       = aws_db_instance.main.db_name
  description = "Database name"
}

# ============================================================================
# Security
# ============================================================================

output "db_security_group_id" {
  value       = aws_security_group.rds.id
  description = "Security group ID for RDS"
}

output "db_security_group_name" {
  value       = aws_security_group.rds.name
  description = "Security group name for RDS"
}

# ============================================================================
# Secrets Manager
# ============================================================================

output "db_credentials_secret_arn" {
  value       = aws_secretsmanager_secret.db_credentials.arn
  description = "Secrets Manager ARN for database credentials"
  sensitive   = true
}

output "db_credentials_secret_name" {
  value       = aws_secretsmanager_secret.db_credentials.name
  description = "Secrets Manager secret name for database credentials"
}

# ============================================================================
# Subnet and Network
# ============================================================================

output "db_subnet_group_name" {
  value       = aws_db_subnet_group.main.name
  description = "DB subnet group name"
}

output "db_subnet_group_arn" {
  value       = aws_db_subnet_group.main.arn
  description = "DB subnet group ARN"
}

# ============================================================================
# Parameter and Option Groups
# ============================================================================

output "db_parameter_group_name" {
  value       = aws_db_parameter_group.main.name
  description = "DB parameter group name"
}

output "db_option_group_name" {
  value       = aws_db_option_group.main.name
  description = "DB option group name"
}

# ============================================================================
# Monitoring
# ============================================================================

output "db_monitoring_role_arn" {
  value       = var.monitoring_interval > 0 ? aws_iam_role.rds_monitoring[0].arn : null
  description = "IAM role ARN for RDS enhanced monitoring"
}

output "db_cloudwatch_log_groups" {
  value       = [for lg in aws_cloudwatch_log_group.rds_logs : lg.name]
  description = "CloudWatch log group names for RDS logs"
}

# ============================================================================
# Read Replica (for reference in future)
# ============================================================================

output "db_read_replica_endpoint" {
  value       = null  # Will be populated when read replica is created
  description = "RDS read replica endpoint (if created)"
}

# ============================================================================
# General Information
# ============================================================================

output "db_engine" {
  value       = aws_db_instance.main.engine
  description = "Database engine"
}

output "db_engine_version" {
  value       = aws_db_instance.main.engine_version_actual
  description = "Actual database engine version"
}

output "db_instance_class" {
  value       = aws_db_instance.main.instance_class
  description = "RDS instance class"
}

output "db_allocated_storage" {
  value       = aws_db_instance.main.allocated_storage
  description = "Allocated storage in GB"
}

output "db_multi_az" {
  value       = aws_db_instance.main.multi_az
  description = "Whether Multi-AZ is enabled"
}

# ============================================================================
# Backup Information
# ============================================================================

output "db_backup_retention_period" {
  value       = aws_db_instance.main.backup_retention_period
  description = "Backup retention period in days"
}

output "db_backup_window" {
  value       = aws_db_instance.main.backup_window
  description = "Backup window"
}

output "db_maintenance_window" {
  value       = aws_db_instance.main.maintenance_window
  description = "Maintenance window"
}

# ============================================================================
# Resource Name (for consistency)
# ============================================================================

output "resource_name" {
  value       = local.resource_name
  description = "Resource naming prefix"
}

output "prefix" {
  value       = local.prefix
  description = "Naming prefix (group-env)"
}
