variable "name" {
  description = "Name prefix for key aliases, e.g. client-a-dev -> alias/client-a-dev-rds"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,40}$", var.name))
    error_message = "name must be 3-40 chars: lowercase letters, digits, hyphens."
  }
}

variable "keys" {
  description = <<-EOT
    Customer-managed keys to create, keyed by purpose (the key becomes part of the alias).
      description             what the key protects
      deletion_window_in_days 7-30: waiting period after a destroy before the key is gone for good
      enable_key_rotation     rotate the key material automatically
      rotation_period_in_days 90-2560, how often to rotate
      via_services            AWS services any principal in this account may use the key THROUGH,
                              e.g. ["rds", "secretsmanager"] (kms:ViaService). Keeps the key usable
                              by RDS without naming every IAM role.
      allow_cloudwatch_logs   let CloudWatch Logs in this region encrypt log groups with the key
  EOT
  type = map(object({
    description             = string
    deletion_window_in_days = optional(number, 30)
    enable_key_rotation     = optional(bool, true)
    rotation_period_in_days = optional(number, 365)
    via_services            = optional(list(string), [])
    allow_cloudwatch_logs   = optional(bool, false)
  }))

  validation {
    condition     = length(var.keys) > 0
    error_message = "Define at least one key."
  }

  validation {
    condition     = alltrue([for k in keys(var.keys) : can(regex("^[a-z0-9-]{2,20}$", k))])
    error_message = "Key names must be 2-20 chars: lowercase letters, digits, hyphens (e.g. rds, logs, eks)."
  }

  validation {
    condition     = alltrue([for k in values(var.keys) : k.deletion_window_in_days >= 7 && k.deletion_window_in_days <= 30])
    error_message = "deletion_window_in_days must be between 7 and 30."
  }

  validation {
    condition     = alltrue([for k in values(var.keys) : k.rotation_period_in_days >= 90 && k.rotation_period_in_days <= 2560])
    error_message = "rotation_period_in_days must be between 90 and 2560."
  }
}

variable "key_administrators" {
  description = "IAM ARNs that may manage (not use) the keys. The account root always can, via IAM."
  type        = list(string)
  default     = []
}

variable "key_users" {
  description = "IAM ARNs that may use the keys directly (encrypt/decrypt, and create grants for AWS services)"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Extra tags for every key"
  type        = map(string)
  default     = {}
}
