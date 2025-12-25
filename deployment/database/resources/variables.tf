# ConnectX Pattern: All variables declared here with NO defaults for environment-specific values
# Defaults set in environments/{env}/main.tf

# ============================================================================
# Core Identifiers (ConnectX Pattern)
# ============================================================================

variable "group" {
  type        = string
  description = "Group identifier (e.g., rtr)"
}

variable "env" {
  type        = string
  description = "Environment (dev, ppe, prod)"
}

variable "project" {
  type        = string
  description = "Project name (database)"
}

# ============================================================================
# AWS Configuration
# ============================================================================

variable "aws_region" {
  type        = string
  description = "AWS region for resource deployment"
}

variable "aws_account_id" {
  type        = string
  description = "AWS account ID"
}

# ============================================================================
# RDS Engine Configuration
# ============================================================================

variable "engine" {
  type        = string
  description = "Database engine (postgres, mysql, mariadb)"
}

variable "engine_version" {
  type        = string
  description = "Database engine version"
}

variable "instance_class" {
  type        = string
  description = "RDS instance class (e.g., db.t3.micro, db.t3.small)"
}

# ============================================================================
# Storage Configuration
# ============================================================================

variable "allocated_storage" {
  type        = number
  description = "Initial allocated storage in GB"
}

variable "max_allocated_storage" {
  type        = number
  description = "Maximum allocated storage for autoscaling in GB"
}

variable "storage_type" {
  type        = string
  description = "Storage type (gp2, gp3, io1)"
}

variable "storage_encrypted" {
  type        = bool
  description = "Enable storage encryption"
}

# ============================================================================
# Database Configuration
# ============================================================================

variable "database_name" {
  type        = string
  description = "Initial database name"
}

variable "database_port" {
  type        = number
  description = "Database port"
}

# ============================================================================
# High Availability Configuration
# ============================================================================

variable "multi_az" {
  type        = bool
  description = "Enable Multi-AZ deployment for high availability"
}

variable "publicly_accessible" {
  type        = bool
  description = "Make database publicly accessible (should be false)"
}

# ============================================================================
# Backup Configuration
# ============================================================================

variable "backup_retention_period" {
  type        = number
  description = "Backup retention period in days (0-35)"
}

variable "backup_window" {
  type        = string
  description = "Preferred backup window (UTC)"
}

variable "maintenance_window" {
  type        = string
  description = "Preferred maintenance window (UTC)"
}

# ============================================================================
# Deletion Protection
# ============================================================================

variable "deletion_protection" {
  type        = bool
  description = "Enable deletion protection"
}

variable "skip_final_snapshot" {
  type        = bool
  description = "Skip final snapshot when destroying"
}

variable "final_snapshot_identifier" {
  type        = string
  description = "Final snapshot identifier (if skip_final_snapshot = false)"
  default     = null
}

# ============================================================================
# Performance Monitoring
# ============================================================================

variable "performance_insights_enabled" {
  type        = bool
  description = "Enable Performance Insights"
}

variable "performance_insights_retention_period" {
  type        = number
  description = "Performance Insights retention period in days"
  default     = null
}

variable "monitoring_interval" {
  type        = number
  description = "Enhanced monitoring interval in seconds (0, 1, 5, 10, 15, 30, 60)"
}

variable "monitoring_role_arn" {
  type        = string
  description = "IAM role ARN for enhanced monitoring"
  default     = null
}

# ============================================================================
# CloudWatch Logs
# ============================================================================

variable "enabled_cloudwatch_logs_exports" {
  type        = list(string)
  description = "List of log types to export to CloudWatch (postgresql, upgrade)"
}

# ============================================================================
# Auto Updates
# ============================================================================

variable "auto_minor_version_upgrade" {
  type        = bool
  description = "Enable automatic minor version upgrades"
}

# ============================================================================
# Parameter Group Configuration
# ============================================================================

variable "parameter_group_family" {
  type        = string
  description = "Parameter group family (e.g., postgres15)"
}

variable "parameters" {
  type        = map(string)
  description = "Map of parameter group parameters"
  default     = {}
}

# ============================================================================
# Tags
# ============================================================================

variable "additional_tags" {
  type        = map(string)
  description = "Additional tags to apply to all resources"
  default     = {}
}
