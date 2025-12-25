# RDS PostgreSQL Database Instance
# ConnectX Pattern: Central database for all apps

# ============================================================================
# Data Sources (reference general infrastructure)
# ============================================================================

data "aws_vpc" "main" {
  filter {
    name   = "tag:Name"
    values = ["${local.prefix}-vpc"]
  }
}

data "aws_subnets" "database" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }

  filter {
    name   = "tag:Type"
    values = ["Database"]
  }
}

data "aws_security_group" "lambda" {
  name = "${local.prefix}-vpc-lambda-sg"
}

# ============================================================================
# Random Password for Database
# ============================================================================

resource "random_password" "db_password" {
  length  = 32
  special = true
  # Exclude characters that might cause issues in connection strings
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# ============================================================================
# Secrets Manager - Database Credentials
# ============================================================================

resource "aws_secretsmanager_secret" "db_credentials" {
  name        = local.db_credentials_secret_name
  description = "RDS PostgreSQL credentials for ${var.env} environment"

  recovery_window_in_days = var.env == "prod" ? 30 : 7

  tags = merge(
    local.common_tags,
    {
      Name = local.db_credentials_secret_name
    }
  )
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id

  secret_string = jsonencode({
    username = local.db_username
    password = random_password.db_password.result
    engine   = var.engine
    host     = aws_db_instance.main.address
    port     = aws_db_instance.main.port
    dbname   = aws_db_instance.main.db_name
    # Connection string for convenience
    connection_string = "postgresql://${local.db_username}:${random_password.db_password.result}@${aws_db_instance.main.address}:${aws_db_instance.main.port}/${aws_db_instance.main.db_name}?sslmode=require"
  })
}

# ============================================================================
# DB Subnet Group
# ============================================================================

resource "aws_db_subnet_group" "main" {
  name       = local.db_subnet_group_name
  subnet_ids = data.aws_subnets.database.ids

  tags = merge(
    local.common_tags,
    {
      Name = local.db_subnet_group_name
    }
  )
}

# ============================================================================
# Security Group for RDS
# ============================================================================

resource "aws_security_group" "rds" {
  name        = local.db_security_group_name
  description = "Security group for RDS PostgreSQL database"
  vpc_id      = data.aws_vpc.main.id

  # Inbound: Allow PostgreSQL from Lambda security group
  ingress {
    from_port       = var.database_port
    to_port         = var.database_port
    protocol        = "tcp"
    security_groups = [data.aws_security_group.lambda.id]
    description     = "Allow PostgreSQL from Lambda functions"
  }

  # Outbound: Allow all (for updates, backups, etc.)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = merge(
    local.common_tags,
    {
      Name = local.db_security_group_name
    }
  )
}

# ============================================================================
# DB Parameter Group (PostgreSQL configuration)
# ============================================================================

resource "aws_db_parameter_group" "main" {
  name   = local.db_parameter_group_name
  family = var.parameter_group_family

  # Apply custom parameters
  dynamic "parameter" {
    for_each = var.parameters
    content {
      name         = parameter.key
      value        = parameter.value
      apply_method = "pending-reboot"  # Use pending-reboot for all parameters
    }
  }

  tags = merge(
    local.common_tags,
    {
      Name = local.db_parameter_group_name
    }
  )

  # Temporarily disabled to allow clean recreation after manual deletion
  # lifecycle {
  #   create_before_destroy = true
  # }
}

# ============================================================================
# DB Option Group (for additional features like pg_stat_statements)
# ============================================================================

resource "aws_db_option_group" "main" {
  name                     = local.db_option_group_name
  option_group_description = "Option group for ${local.db_instance_identifier}"
  engine_name              = var.engine
  major_engine_version     = split(".", var.engine_version)[0]

  tags = merge(
    local.common_tags,
    {
      Name = local.db_option_group_name
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# ============================================================================
# IAM Role for Enhanced Monitoring
# ============================================================================

resource "aws_iam_role" "rds_monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0

  name = local.monitoring_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "monitoring.rds.amazonaws.com"
      }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0

  role       = aws_iam_role.rds_monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# ============================================================================
# RDS Database Instance
# ============================================================================

resource "aws_db_instance" "main" {
  identifier = local.db_instance_identifier

  # Engine configuration
  engine         = var.engine
  engine_version = var.engine_version
  instance_class = var.instance_class

  # Storage configuration
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = var.storage_type
  storage_encrypted     = var.storage_encrypted
  kms_key_id            = var.storage_encrypted ? null : null  # Use default AWS key

  # Database configuration
  db_name  = var.database_name
  port     = var.database_port
  username = local.db_username
  password = random_password.db_password.result

  # Network configuration
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = var.publicly_accessible

  # High availability
  multi_az = var.multi_az

  # Backup configuration
  backup_retention_period = var.backup_retention_period
  backup_window          = var.backup_window
  maintenance_window     = var.maintenance_window

  # Snapshot configuration
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : var.final_snapshot_identifier
  copy_tags_to_snapshot     = true
  deletion_protection       = var.deletion_protection

  # Parameter and option groups
  parameter_group_name = aws_db_parameter_group.main.name
  option_group_name    = aws_db_option_group.main.name

  # Monitoring
  enabled_cloudwatch_logs_exports       = var.enabled_cloudwatch_logs_exports
  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_retention_period = var.performance_insights_retention_period
  monitoring_interval                   = var.monitoring_interval
  monitoring_role_arn                   = var.monitoring_interval > 0 ? aws_iam_role.rds_monitoring[0].arn : null

  # Auto updates
  auto_minor_version_upgrade  = var.auto_minor_version_upgrade
  allow_major_version_upgrade = false  # Require manual major version upgrades

  # IAM database authentication
  iam_database_authentication_enabled = true  # Allow IAM authentication

  # Apply changes immediately in dev, during maintenance window in prod
  apply_immediately = var.env == "dev" ? true : false
  tags = merge(
    local.common_tags,
    {
      Name = local.db_instance_identifier
    }
  )

  lifecycle {
    prevent_destroy = false  # Set to true in production after initial deployment
    ignore_changes  = [password]  # Don't update password on subsequent applies
  }
}

# ============================================================================
# CloudWatch Log Group (for database logs)
# ============================================================================

resource "aws_cloudwatch_log_group" "rds_logs" {
  for_each = toset(var.enabled_cloudwatch_logs_exports)

  name              = "/aws/rds/instance/${local.db_instance_identifier}/${each.value}"
  retention_in_days = var.env == "prod" ? 90 : 30

  tags = local.common_tags
}

# ============================================================================
# CloudWatch Alarms
# ============================================================================

# CPU Utilization Alarm
resource "aws_cloudwatch_metric_alarm" "db_cpu" {
  alarm_name          = "${local.db_instance_identifier}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = var.env == "prod" ? "80" : "90"
  alarm_description   = "This metric monitors RDS CPU utilization"
  alarm_actions       = []  # TODO: Add SNS topic ARN for notifications

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }

  tags = local.common_tags
}

# Storage Space Alarm
resource "aws_cloudwatch_metric_alarm" "db_storage" {
  alarm_name          = "${local.db_instance_identifier}-low-storage"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "5000000000"  # 5 GB in bytes
  alarm_description   = "This metric monitors RDS free storage space"
  alarm_actions       = []  # TODO: Add SNS topic ARN for notifications

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }

  tags = local.common_tags
}

# Database Connections Alarm
resource "aws_cloudwatch_metric_alarm" "db_connections" {
  count = var.env == "prod" ? 1 : 0

  alarm_name          = "${local.db_instance_identifier}-high-connections"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "150"  # Alert when connections exceed 150
  alarm_description   = "This metric monitors RDS connection count"
  alarm_actions       = []  # TODO: Add SNS topic ARN for notifications

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }

  tags = local.common_tags
}
