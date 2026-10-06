variable "cluster_name" {
  description = "EKS cluster to install the add-ons into (eks-cluster module: cluster_name)"
  type        = string
}

variable "kubernetes_version" {
  description = "Cluster Kubernetes version (eks-cluster module: cluster_version). Used to pick compatible add-on versions."
  type        = string
}

variable "addons" {
  description = <<-EOT
    EKS managed add-ons to install, keyed by add-on name (e.g. vpc-cni, coredns, kube-proxy, metrics-server).
      version                   pin an exact version (e.g. v1.19.2-eksbuild.1); null = the default
                                version AWS recommends for this Kubernetes version
      service_account_role_arn  IRSA role for the add-on's pods (e.g. aws-ebs-csi-driver)
      configuration_values      add-on settings as a JSON string (see: aws eks describe-addon-configuration)
      resolve_conflicts         OVERWRITE (Terraform wins) or PRESERVE (keep manual changes) on update
  EOT
  type = map(object({
    version                  = optional(string)
    service_account_role_arn = optional(string)
    configuration_values     = optional(string)
    resolve_conflicts        = optional(string, "OVERWRITE")
  }))

  validation {
    condition     = length(var.addons) > 0
    error_message = "Give at least one add-on."
  }

  validation {
    condition     = alltrue([for a in values(var.addons) : contains(["OVERWRITE", "PRESERVE"], a.resolve_conflicts)])
    error_message = "resolve_conflicts must be OVERWRITE or PRESERVE."
  }

  validation {
    condition     = alltrue([for a in values(var.addons) : a.configuration_values == null || can(jsondecode(a.configuration_values))])
    error_message = "configuration_values must be a valid JSON string (use jsonencode({...}))."
  }
}

variable "use_latest_versions" {
  description = "For add-ons without a pinned version: true = newest compatible version, false = AWS's default for this Kubernetes version (safer)"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Extra tags for every add-on"
  type        = map(string)
  default     = {}
}
