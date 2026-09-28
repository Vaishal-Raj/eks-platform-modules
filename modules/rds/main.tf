locals {
  identifier = "${var.name}-mysql"

  # "8.4" or "8.4.5" -> "mysql8.4"
  parameter_group_family = coalesce(
    var.parameter_group_family,
    "mysql${regex("^[0-9]+\\.[0-9]+", var.engine_version)}"
  )

  # Module defaults; var.parameters overrides or adds to them
  default_parameters = {
    character_set_server     = { value = "utf8mb4", apply_method = "immediate" }
    collation_server         = { value = "utf8mb4_unicode_ci", apply_method = "immediate" }
    slow_query_log           = { value = "1", apply_method = "immediate" }
    long_query_time          = { value = "2", apply_method = "immediate" }
    require_secure_transport = { value = var.require_tls ? "ON" : "OFF", apply_method = "immediate" }
  }

  parameters = merge(local.default_parameters, var.parameters)

  # RDS writes exported logs to /aws/rds/instance/<id>/<log>
  log_groups = toset(var.cloudwatch_log_exports)
}

# ---------------- Placement ----------------

# Which subnets RDS may use: the isolated tier (no route anywhere but the VPC)
resource "aws_db_subnet_group" "this" {
  name        = "${var.name}-mysql"
  description = "Isolated subnets for ${local.identifier}"
  subnet_ids  = var.subnet_ids

  tags = merge(var.tags, { Name = "${var.name}-mysql" })
}

# ---------------- Engine settings ----------------

resource "aws_db_parameter_group" "this" {
  name        = "${var.name}-mysql"
  family      = local.parameter_group_family
  description = "MySQL parameters for ${local.identifier}"

  dynamic "parameter" {
    for_each = local.parameters
    content {
      name         = parameter.key
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  tags = merge(var.tags, { Name = "${var.name}-mysql" })

  lifecycle {
    create_before_destroy = true
  }
}

# ---------------- Log groups (created first, so retention and encryption are ours) ----------------

resource "aws_cloudwatch_log_group" "this" {
  for_each = local.log_groups

  name              = "/aws/rds/instance/${local.identifier}/${each.value}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_kms_key_arn

  tags = var.tags
}

# ---------------- The primary instance ----------------

resource "aws_db_instance" "this" {
  identifier     = local.identifier
  engine         = "mysql"
  engine_version = var.engine_version
  instance_class = var.instance_class
  port           = var.port

  db_name  = var.db_name
  username = var.master_username

  # RDS generates the master password, stores it in Secrets Manager (encrypted with
  # our key) and can rotate it. It never appears in Terraform code or state.
  manage_master_user_password   = true
  master_user_secret_kms_key_id = var.kms_key_arn

  # Storage: encrypted with our customer-managed key, grows automatically
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage > 0 ? var.max_allocated_storage : null
  storage_type          = var.storage_type
  storage_encrypted     = true
  kms_key_id            = var.kms_key_arn

  # Network: isolated subnets, reachable only through its security group(s)
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = var.security_group_ids
  publicly_accessible    = false

  parameter_group_name = aws_db_parameter_group.this.name
  ca_cert_identifier   = var.ca_cert_identifier

  multi_az                = var.multi_az
  backup_retention_period = var.backup_retention_days
  backup_window           = var.backup_window
  maintenance_window      = var.maintenance_window
  copy_tags_to_snapshot   = true

  auto_minor_version_upgrade = true
  apply_immediately          = var.apply_immediately

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${local.identifier}-final"

  enabled_cloudwatch_logs_exports = var.cloudwatch_log_exports

  tags = merge(var.tags, { Name = local.identifier })

  # Our log groups must exist first, or RDS creates its own (no retention, no CMK)
  depends_on = [aws_cloudwatch_log_group.this]

  lifecycle {
    precondition {
      condition     = !var.create_read_replica || var.backup_retention_days > 0
      error_message = "A read replica needs automated backups: set backup_retention_days > 0."
    }
  }
}

# ---------------- Optional read replica (same region) ----------------

resource "aws_db_instance" "replica" {
  count = var.create_read_replica ? 1 : 0

  identifier          = "${local.identifier}-replica"
  replicate_source_db = aws_db_instance.this.identifier
  instance_class      = coalesce(var.replica_instance_class, var.instance_class)

  # Inherited from the source: engine, version, credentials, storage encryption, KMS key.
  vpc_security_group_ids = var.security_group_ids
  parameter_group_name   = aws_db_parameter_group.this.name
  ca_cert_identifier     = var.ca_cert_identifier
  publicly_accessible    = false

  max_allocated_storage   = var.max_allocated_storage > 0 ? var.max_allocated_storage : null
  backup_retention_period = 0
  skip_final_snapshot     = true
  deletion_protection     = var.deletion_protection

  auto_minor_version_upgrade = true
  apply_immediately          = var.apply_immediately

  tags = merge(var.tags, { Name = "${local.identifier}-replica", Role = "read-replica" })
}
