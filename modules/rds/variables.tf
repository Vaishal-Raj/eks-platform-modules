variable "name" {
  description = "Name prefix, e.g. client-a-dev -> DB instance client-a-dev-mysql"
  type        = string

  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{1,38}[a-z0-9])$", var.name)) && !strcontains(var.name, "--")
    error_message = "name must be 3-40 chars, start with a letter, end with a letter or digit, use lowercase letters/digits/hyphens, and not contain '--' (RDS identifier rules)."
  }
}

# ---------------- Network placement ----------------

variable "subnet_ids" {
  description = "Isolated subnets for the DB subnet group (at least 2, in different AZs)"
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "RDS needs at least 2 subnets in different AZs."
  }
}

variable "security_group_ids" {
  description = "Security groups for the instance (normally sg-rds from the security-groups module)"
  type        = list(string)

  validation {
    condition     = length(var.security_group_ids) > 0
    error_message = "Pass at least one security group (e.g. the security-groups module's rds_security_group_id)."
  }
}

# ---------------- Engine and size ----------------

variable "engine_version" {
  description = "MySQL version. \"8.4\" = latest 8.4 minor (8.4 is the LTS line; 8.0 is in paid Extended Support since July 2026)"
  type        = string
  default     = "8.4"

  validation {
    condition     = can(regex("^8\\.(0|4)(\\.[0-9]+)?$", var.engine_version))
    error_message = "engine_version must be 8.0 or 8.4 (optionally with a minor version, e.g. 8.4.5)."
  }
}

variable "parameter_group_family" {
  description = "Parameter group family. null = derived from engine_version (8.4 -> mysql8.4)"
  type        = string
  default     = null
}

variable "instance_class" {
  description = "Instance size, e.g. db.t4g.micro (dev), db.r6g.large (prod)"
  type        = string
  default     = "db.t4g.micro"

  validation {
    condition     = can(regex("^db\\.[a-z0-9]+\\.[a-z0-9]+$", var.instance_class))
    error_message = "instance_class must look like db.<family>.<size>, e.g. db.t4g.micro."
  }
}

variable "allocated_storage" {
  description = "Initial storage in GiB (gp3 minimum is 20)"
  type        = number
  default     = 20

  validation {
    condition     = var.allocated_storage >= 20 && var.allocated_storage <= 65536
    error_message = "allocated_storage must be between 20 and 65536 GiB."
  }
}

variable "max_allocated_storage" {
  description = "Storage autoscaling ceiling in GiB (0 = autoscaling off)"
  type        = number
  default     = 100
}

variable "storage_type" {
  description = "gp3 (general purpose) or io1/io2 (provisioned IOPS)"
  type        = string
  default     = "gp3"

  validation {
    condition     = contains(["gp3", "gp2", "io1", "io2"], var.storage_type)
    error_message = "storage_type must be gp3, gp2, io1 or io2."
  }
}

# ---------------- Database and credentials ----------------

variable "db_name" {
  description = "Initial database created on the instance"
  type        = string
  default     = "appdb"

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9_]{0,63}$", var.db_name))
    error_message = "db_name must start with a letter and contain only letters, digits and underscores (max 64)."
  }
}

variable "master_username" {
  description = "Master user name. The password is generated and stored by RDS in Secrets Manager."
  type        = string
  default     = "dbadmin"

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9_]{0,15}$", var.master_username)) && !contains(["root", "rdsadmin"], lower(var.master_username))
    error_message = "master_username: start with a letter, letters/digits/underscores, max 16, and not root/rdsadmin (reserved by RDS)."
  }
}

variable "port" {
  description = "MySQL port"
  type        = number
  default     = 3306
}

# ---------------- Encryption ----------------

variable "kms_key_arn" {
  description = "Customer-managed KMS key (kms module: key_arns[\"rds\"]) for storage, snapshots, replicas AND the master password secret. null = AWS-managed keys."
  type        = string
  default     = null
}

variable "require_tls" {
  description = "Force every client connection to use TLS (require_secure_transport = ON)"
  type        = bool
  default     = true
}

variable "ca_cert_identifier" {
  description = "Certificate authority for the server certificate"
  type        = string
  default     = "rds-ca-rsa2048-g1"
}

# ---------------- Availability, backups, maintenance ----------------

variable "multi_az" {
  description = "Synchronous standby in a second AZ with automatic failover (recommended for prod)"
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "Days of automated backups / point-in-time recovery (1-35; 0 disables backups and read replicas)"
  type        = number
  default     = 7

  validation {
    condition     = var.backup_retention_days >= 0 && var.backup_retention_days <= 35
    error_message = "backup_retention_days must be between 0 and 35."
  }
}

variable "backup_window" {
  description = "Daily backup window (UTC), must not overlap the maintenance window"
  type        = string
  default     = "18:00-19:00"
}

variable "maintenance_window" {
  description = "Weekly maintenance window (UTC)"
  type        = string
  default     = "sun:19:30-sun:20:30"
}

variable "deletion_protection" {
  description = "Block deleting the instance (turn on for prod)"
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "Delete without a final snapshot (only for throwaway environments)"
  type        = bool
  default     = false
}

variable "apply_immediately" {
  description = "Apply changes now instead of in the next maintenance window"
  type        = bool
  default     = false
}

# ---------------- Read replica ----------------

variable "create_read_replica" {
  description = "Create a same-region read replica for read-heavy traffic (needs backups enabled)"
  type        = bool
  default     = false
}

variable "replica_instance_class" {
  description = "Replica size. null = same as the primary."
  type        = string
  default     = null
}

# ---------------- Logs and parameters ----------------

variable "cloudwatch_log_exports" {
  description = "MySQL logs to send to CloudWatch: error, slowquery, general, audit"
  type        = list(string)
  default     = ["error", "slowquery"]

  validation {
    condition     = alltrue([for l in var.cloudwatch_log_exports : contains(["error", "slowquery", "general", "audit", "iam-db-auth-error"], l)])
    error_message = "cloudwatch_log_exports may only contain error, slowquery, general, audit, iam-db-auth-error."
  }
}

variable "log_retention_days" {
  description = "Retention of the exported log groups"
  type        = number
  default     = 30
}

variable "logs_kms_key_arn" {
  description = "KMS key for the exported log groups (kms module: key_arns[\"logs\"]). null = CloudWatch default encryption."
  type        = string
  default     = null
}

variable "parameters" {
  description = "Extra MySQL parameters, merged over the module defaults (utf8mb4, slow query log, TLS)"
  type = map(object({
    value        = string
    apply_method = optional(string, "immediate")
  }))
  default = {}
}

variable "tags" {
  description = "Extra tags for every resource in this module"
  type        = map(string)
  default     = {}
}
