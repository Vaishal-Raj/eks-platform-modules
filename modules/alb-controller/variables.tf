variable "name" {
  description = "Name prefix for the IAM role, e.g. client-a-dev -> client-a-dev-alb-controller"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{3,40}$", var.name))
    error_message = "name must be 3-40 chars: letters, digits, hyphens."
  }
}

# ---------------- Cluster ----------------

variable "cluster_name" {
  description = "EKS cluster (eks-cluster module: cluster_name)"
  type        = string
}

variable "vpc_id" {
  description = "VPC of the cluster. Passed explicitly because pods can't read it from EC2 metadata (IMDS hop limit 1)."
  type        = string
}

variable "oidc_provider_arn" {
  description = "eks-cluster module: oidc_provider_arn (for the IRSA role)"
  type        = string
}

variable "oidc_provider" {
  description = "eks-cluster module: oidc_provider (issuer without https://)"
  type        = string
}

# ---------------- Permissions ----------------

variable "policy_mode" {
  description = <<-EOT
    target-group-binding  (default) least privilege: the controller only registers/deregisters pod IPs in the
                          target groups listed in target_group_arns. It can't create or change load balancers
                          or security groups. Fits this platform: Terraform owns the ALB.
    full                  AWS's published policy for v3.6.0 (policies/aws-published-v3.6.0.json): the controller
                          can create ALBs/NLBs from Ingress/Service objects and manage their security groups.
  EOT
  type        = string
  default     = "target-group-binding"

  validation {
    condition     = contains(["target-group-binding", "full"], var.policy_mode)
    error_message = "policy_mode must be target-group-binding or full."
  }
}

variable "target_group_arns" {
  description = "Target groups the controller may register pod IPs in (alb module: target_group_arn). Required for policy_mode = target-group-binding."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for a in var.target_group_arns : can(regex("^arn:aws[a-z-]*:elasticloadbalancing:", a))])
    error_message = "target_group_arns must be Elastic Load Balancing target group ARNs."
  }
}

# ---------------- Helm release ----------------

variable "chart_version" {
  description = "aws-load-balancer-controller Helm chart version (chart 3.6.0 = controller v3.6.0). See: helm search repo eks/aws-load-balancer-controller --versions"
  type        = string
  default     = "3.6.0"
}

variable "image_repository" {
  description = "Controller image repository. Nodes without NAT can't reach public.ecr.aws: use the ECR pull-through cache, e.g. <registry>/ecr-public/eks/aws-load-balancer-controller. null = chart default."
  type        = string
  default     = null
}

variable "namespace" {
  description = "Namespace to install into"
  type        = string
  default     = "kube-system"
}

variable "service_account_name" {
  description = "ServiceAccount the controller runs as (the IRSA role trusts exactly this)"
  type        = string
  default     = "aws-load-balancer-controller"
}

variable "replica_count" {
  description = "Controller pods (2 = one can restart without stopping target registration)"
  type        = number
  default     = 2

  validation {
    condition     = var.replica_count >= 1
    error_message = "replica_count must be at least 1."
  }
}

variable "enable_service_mutator_webhook" {
  description = "Let the controller turn every Service of type LoadBalancer into an NLB. Off: this platform exposes apps only through the Terraform-managed ALB."
  type        = bool
  default     = false
}

variable "extra_values" {
  description = "Extra Helm values as YAML strings, applied after the module's values (e.g. resources, nodeSelector)"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Extra tags for the IAM role"
  type        = map(string)
  default     = {}
}
