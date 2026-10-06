variable "name" {
  description = "Cluster name, e.g. client-a-dev"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{1,98}[a-zA-Z0-9]$", var.name))
    error_message = "name must be 3-100 chars: letters, digits, hyphens; start and end with a letter or digit."
  }
}

variable "kubernetes_version" {
  description = "Kubernetes minor version, e.g. 1.35. Check what EKS offers: aws eks describe-cluster-versions"
  type        = string

  validation {
    condition     = can(regex("^1\\.[0-9]{2}$", var.kubernetes_version))
    error_message = "kubernetes_version must look like 1.35 (major.minor only; EKS picks the patch)."
  }
}

variable "support_type" {
  description = "STANDARD (cluster must be upgraded before end of standard support) or EXTENDED (keeps running, extra hourly charge)"
  type        = string
  default     = "STANDARD"

  validation {
    condition     = contains(["STANDARD", "EXTENDED"], var.support_type)
    error_message = "support_type must be STANDARD or EXTENDED."
  }
}

# ---------------- Network ----------------

variable "subnet_ids" {
  description = "Private subnets for the control plane ENIs (at least 2, in different AZs)"
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "EKS needs at least 2 subnets in different AZs."
  }
}

variable "additional_security_group_ids" {
  description = "Extra security groups for the control plane ENIs (EKS always creates its own cluster security group)"
  type        = list(string)
  default     = []
}

variable "service_ipv4_cidr" {
  description = "Range for Kubernetes Service IPs. Must not overlap the VPC. null = EKS default (10.100.0.0/16 or 172.20.0.0/16)"
  type        = string
  default     = null
}

# ---------------- API endpoint ----------------

variable "endpoint_public_access" {
  description = "Also expose the API server publicly (still IAM-authenticated). The private endpoint is always on."
  type        = bool
  default     = false
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to reach the PUBLIC endpoint (e.g. your office/VPN, CI egress). Required if endpoint_public_access = true."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.public_access_cidrs : can(cidrhost(c, 0))])
    error_message = "public_access_cidrs must be valid CIDR blocks."
  }
}

# ---------------- Access (who can use kubectl) ----------------

variable "bootstrap_cluster_creator_admin" {
  description = "Give whoever creates the cluster implicit admin. false = only the access_entries below have access (explicit, recommended)."
  type        = bool
  default     = false
}

variable "access_entries" {
  description = <<-EOT
    IAM roles/users allowed into the cluster, keyed by a short label.
      principal_arn  IAM role or user ARN (for an assumed role use the ROLE ARN, not the sts ARN)
      policy         EKS access policy: AmazonEKSClusterAdminPolicy, AmazonEKSAdminPolicy,
                     AmazonEKSEditPolicy or AmazonEKSViewPolicy
      namespaces     empty = whole cluster; otherwise only these namespaces
  EOT
  type = map(object({
    principal_arn = string
    policy        = optional(string, "AmazonEKSClusterAdminPolicy")
    namespaces    = optional(list(string), [])
  }))
  default = {}

  validation {
    condition = alltrue([
      for e in values(var.access_entries) :
      contains(["AmazonEKSClusterAdminPolicy", "AmazonEKSAdminPolicy", "AmazonEKSEditPolicy", "AmazonEKSViewPolicy"], e.policy)
    ])
    error_message = "policy must be AmazonEKSClusterAdminPolicy, AmazonEKSAdminPolicy, AmazonEKSEditPolicy or AmazonEKSViewPolicy."
  }

  validation {
    condition     = alltrue([for e in values(var.access_entries) : !can(regex(":sts::", e.principal_arn))])
    error_message = "Use the IAM role ARN (arn:aws:iam::<acct>:role/<name>), not an assumed-role sts ARN."
  }
}

# ---------------- Encryption, logs, add-ons ----------------

variable "encrypt_secrets" {
  description = "Envelope-encrypt Kubernetes Secrets with kms_key_arn. A separate on/off switch because a key ARN created in the same run is unknown at plan time, so Terraform can't use it to decide what to create."
  type        = bool
  default     = false
}

variable "kms_key_arn" {
  description = "Customer-managed KMS key for Kubernetes Secrets (kms module: key_arns[\"eks\"]). Required when encrypt_secrets = true."
  type        = string
  default     = null

  validation {
    condition     = !var.encrypt_secrets || var.kms_key_arn != null
    error_message = "encrypt_secrets = true needs kms_key_arn (e.g. the kms module's key_arns[\"eks\"])."
  }
}

variable "enabled_log_types" {
  description = "Control plane logs to send to CloudWatch: api, audit, authenticator, controllerManager, scheduler"
  type        = list(string)
  default     = ["api", "audit", "authenticator"]

  validation {
    condition     = alltrue([for l in var.enabled_log_types : contains(["api", "audit", "authenticator", "controllerManager", "scheduler"], l)])
    error_message = "enabled_log_types may only contain api, audit, authenticator, controllerManager, scheduler."
  }
}

variable "log_retention_days" {
  description = "Retention of the control plane log group"
  type        = number
  default     = 30
}

variable "logs_kms_key_arn" {
  description = "KMS key for the control plane log group (kms module: key_arns[\"logs\"]). null = CloudWatch default."
  type        = string
  default     = null
}

variable "bootstrap_self_managed_addons" {
  description = "Let EKS install unmanaged vpc-cni/coredns/kube-proxy. false = install them as MANAGED add-ons (eks-addons module). Changing it replaces the cluster."
  type        = bool
  default     = false
}

variable "create_oidc_provider" {
  description = "Create the IAM OIDC provider for IRSA (pods assuming IAM roles)"
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "Block deleting the cluster (turn on for prod)"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Extra tags for every resource in this module"
  type        = map(string)
  default     = {}
}
