variable "name" {
  description = "IAM role name, e.g. client-a-dev-ebs-csi"
  type        = string

  validation {
    condition     = can(regex("^[\\w+=,.@-]{1,64}$", var.name))
    error_message = "name must be 1-64 chars: letters, digits, and + = , . @ _ -"
  }
}

# ---------------- Which cluster's tokens to trust ----------------

variable "oidc_provider_arn" {
  description = "IAM OIDC provider of the cluster (eks-cluster module: oidc_provider_arn)"
  type        = string
}

variable "oidc_provider" {
  description = "Cluster OIDC issuer WITHOUT https:// (eks-cluster module: oidc_provider). Used in the condition keys <issuer>:sub and <issuer>:aud."
  type        = string

  validation {
    condition     = !startswith(var.oidc_provider, "https://")
    error_message = "oidc_provider must not start with https:// (use the eks-cluster module's oidc_provider output)."
  }
}

# ---------------- Which pods may assume the role ----------------

variable "service_accounts" {
  description = "Kubernetes ServiceAccounts allowed to assume this role (namespace + name). Wildcards (*) allowed but discouraged."
  type = list(object({
    namespace = string
    name      = string
  }))

  validation {
    condition     = length(var.service_accounts) > 0
    error_message = "Give at least one ServiceAccount; a role nobody can assume is useless."
  }

  validation {
    condition     = alltrue([for sa in var.service_accounts : sa.namespace != "*" || sa.name != "*"])
    error_message = "namespace = \"*\" with name = \"*\" would let EVERY pod in the cluster assume this role."
  }
}

# ---------------- What the role may do ----------------

variable "policy_arns" {
  description = "Managed policies to attach, keyed by a label (keys must be known at plan time), e.g. { ebs = \"arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy\" }"
  type        = map(string)
  default     = {}
}

variable "inline_policies" {
  description = "Inline policy JSON documents, keyed by a label, e.g. { secrets = data.aws_iam_policy_document.x.json }"
  type        = map(string)
  default     = {}
}

variable "max_session_duration" {
  description = "Maximum session length in seconds (3600-43200)"
  type        = number
  default     = 3600

  validation {
    condition     = var.max_session_duration >= 3600 && var.max_session_duration <= 43200
    error_message = "max_session_duration must be between 3600 and 43200 seconds."
  }
}

variable "permissions_boundary_arn" {
  description = "Optional permissions boundary: a ceiling on what the role can ever do"
  type        = string
  default     = null
}

variable "tags" {
  description = "Extra tags for the role"
  type        = map(string)
  default     = {}
}
