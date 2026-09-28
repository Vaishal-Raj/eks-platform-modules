variable "name" {
  description = "Name prefix, e.g. client-a-dev"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,40}$", var.name))
    error_message = "name must be 3-40 chars: lowercase letters, digits, hyphens."
  }

  validation {
    condition     = !startswith(var.name, "sg-")
    error_message = "name can't start with \"sg-\": AWS reserves that prefix for security group IDs."
  }
}

variable "vpc_id" {
  description = "VPC the security groups belong to"
  type        = string
}

# ---------------- Who talks to the nodes (pods) ----------------

variable "alb_security_group_ids" {
  description = "ALB security group(s) (from the alb module). The nodes accept app_ports from them. Empty = no ALB rule."
  type        = list(string)
  default     = []
}

variable "app_ports" {
  description = "Ports the pods listen on, which the ALB forwards to (must match the alb module's target_port)"
  type        = list(number)
  default     = [8080]

  validation {
    condition     = alltrue([for p in var.app_ports : p >= 1 && p <= 65535])
    error_message = "app_ports must be between 1 and 65535."
  }
}

# ---------------- Where the nodes (pods) may go ----------------

variable "vpce_security_group_ids" {
  description = "VPC endpoints security group(s) (from the vpc-endpoints module). Nodes may reach them on 443. Empty = no rule."
  type        = list(string)
  default     = []
}

variable "allow_s3_gateway_egress" {
  description = "Let nodes reach S3 on 443 through the S3 gateway endpoint (ECR image layers live in S3)"
  type        = bool
  default     = true
}

# ---------------- Data tier ----------------

variable "create_rds_sg" {
  description = "Create the database security group (inbound db_port from the nodes only)"
  type        = bool
  default     = true
}

variable "db_port" {
  description = "Database port (3306 for MySQL)"
  type        = number
  default     = 3306

  validation {
    condition     = var.db_port >= 1 && var.db_port <= 65535
    error_message = "db_port must be between 1 and 65535."
  }
}

variable "create_cache_sg" {
  description = "Create the cache (ElastiCache Redis) security group (inbound cache_port from the nodes only)"
  type        = bool
  default     = true
}

variable "cache_port" {
  description = "Cache port (6379 for Redis)"
  type        = number
  default     = 6379

  validation {
    condition     = var.cache_port >= 1 && var.cache_port <= 65535
    error_message = "cache_port must be between 1 and 65535."
  }
}

variable "additional_db_source_sg_ids" {
  description = "Other security groups allowed to reach the database (e.g. a migration job or bastion). Empty = nodes only."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Extra tags for every resource in this module"
  type        = map(string)
  default     = {}
}
