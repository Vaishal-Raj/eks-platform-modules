variable "name" {
  description = "Name prefix for the IAM role, e.g. client-a-dev -> client-a-dev-external-secrets"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{3,40}$", var.name))
    error_message = "name must be 3-40 chars: letters, digits, hyphens."
  }
}

# ---------------- Cluster ----------------

variable "oidc_provider_arn" {
  description = "eks-cluster module: oidc_provider_arn (for the IRSA role)"
  type        = string
}

variable "oidc_provider" {
  description = "eks-cluster module: oidc_provider (issuer without https://)"
  type        = string
}

# ---------------- What it may read ----------------

variable "secret_arns" {
  description = "Secrets Manager secrets the operator may read, e.g. [module.rds.master_user_secret_arn]. A trailing * is allowed (arn:…:secret:client-a/*), a bare * is not."
  type        = list(string)

  validation {
    condition     = alltrue([for a in var.secret_arns : can(regex("^arn:aws[a-z-]*:secretsmanager:[a-z0-9-]+:[0-9]{12}:secret:.+", a))])
    error_message = "secret_arns must be Secrets Manager secret ARNs (arn:aws:secretsmanager:<region>:<account>:secret:<name>)."
  }
}

variable "kms_key_arns" {
  description = "Customer-managed KMS keys the secrets are encrypted with (e.g. the rds module's kms_key_arn). Decrypt is allowed only through Secrets Manager. Empty = secrets use the AWS-managed key."
  type        = list(string)
  default     = []
}

# ---------------- Helm release ----------------

variable "chart_version" {
  description = "external-secrets Helm chart version (chart 2.12.0 = operator v2.12.0). See: https://charts.external-secrets.io/index.yaml"
  type        = string
  default     = "2.12.0"
}

variable "image_repository" {
  description = "Operator image repository (controller, webhook and cert-controller use the same image). Nodes without NAT can't reach ghcr.io: use the ECR pull-through cache, e.g. <registry>/ghcr/external-secrets/external-secrets. null = chart default."
  type        = string
  default     = null
}

variable "namespace" {
  description = "Namespace to install into (created by Helm)"
  type        = string
  default     = "external-secrets"
}

variable "service_account_name" {
  description = "ServiceAccount of the controller (the IRSA role trusts exactly this)"
  type        = string
  default     = "external-secrets"
}

variable "replica_count" {
  description = "Controller pods (only one is active at a time: leader election)"
  type        = number
  default     = 1

  validation {
    condition     = var.replica_count >= 1
    error_message = "replica_count must be at least 1."
  }
}

variable "extra_values" {
  description = "Extra Helm values as YAML strings, applied after the module's values (e.g. resources, nodeSelector)"
  type        = list(string)
  default     = []
}

# ---------------- ClusterSecretStore ----------------

variable "create_cluster_secret_store" {
  description = "Create one ClusterSecretStore for AWS Secrets Manager, so apps only write ExternalSecret objects"
  type        = bool
  default     = true
}

variable "cluster_secret_store_name" {
  description = "Name apps reference in ExternalSecret.spec.secretStoreRef"
  type        = string
  default     = "aws-secrets-manager"
}

variable "store_allowed_namespaces" {
  description = "Namespaces allowed to use the ClusterSecretStore. Empty = every namespace (anyone who can create an ExternalSecret can read every secret in secret_arns)."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Extra tags for the IAM role"
  type        = map(string)
  default     = {}
}
