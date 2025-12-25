# Local values following ConnectX naming pattern
# Pattern: {group}-{env}-{project}

locals {
  # Core naming
  prefix        = "${var.group}-${var.env}"           # e.g., rtr-dev
  resource_name = "${local.prefix}-${var.project}"    # e.g., rtr-dev-database

  # Common tags applied to all resources
  common_tags = merge(
    {
      Group       = var.group
      Environment = var.env
      Project     = var.project
      ManagedBy   = "Terraform"
      Component   = "database"
    },
    var.additional_tags
  )

  # RDS instance identifier
  db_instance_identifier = "${local.prefix}-db"

  # DB subnet group name
  db_subnet_group_name = "${local.prefix}-db-subnet-group"

  # Security group name
  db_security_group_name = "${local.prefix}-db-sg"

  # Parameter group name
  db_parameter_group_name = "${local.prefix}-db-params"

  # Option group name (for additional features)
  db_option_group_name = "${local.prefix}-db-options"

  # Monitoring role name
  monitoring_role_name = "${local.prefix}-db-monitoring"

  # Secrets Manager secret name for DB credentials
  db_credentials_secret_name = "${local.prefix}-db-credentials"

  # Database username (avoid reserved words like 'admin')
  db_username = "rtr_admin"

  # CloudWatch log group name
  db_log_group_name = "/aws/rds/${local.db_instance_identifier}"

  # Read replica identifier (if needed)
  read_replica_identifier = "${local.db_instance_identifier}-replica"
}
