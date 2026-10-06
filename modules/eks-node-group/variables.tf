variable "name" {
  description = "Node group name, e.g. client-a-dev-default (also prefixes the node IAM role and launch template)"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{1,37}$", var.name))
    error_message = "name must be 2-38 chars: letters, digits, hyphens, underscores; start with a letter or digit."
  }
}

variable "cluster_name" {
  description = "EKS cluster to join (eks-cluster module: cluster_name)"
  type        = string
}

variable "kubernetes_version" {
  description = "Node Kubernetes version. null = same as the control plane. Upgrade the control plane first, then this."
  type        = string
  default     = null
}

variable "subnet_ids" {
  description = "Private subnets for the nodes (spread across AZs)"
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 1
    error_message = "At least one subnet is required (use 2+ for high availability)."
  }
}

# ---------------- Size (normally from the client profile) ----------------

variable "instance_types" {
  description = "EC2 instance types; several = more capacity options (useful with SPOT)"
  type        = list(string)
  default     = ["t3.medium"]

  validation {
    condition     = length(var.instance_types) > 0
    error_message = "Give at least one instance type."
  }
}

variable "capacity_type" {
  description = "ON_DEMAND, or SPOT (up to ~70% cheaper, can be interrupted: fine for dev)"
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.capacity_type)
    error_message = "capacity_type must be ON_DEMAND or SPOT."
  }
}

variable "ami_type" {
  description = "Node OS image. AL2023 = Amazon Linux 2023 (x86_64 or ARM_64 for Graviton); BOTTLEROCKET = container-only OS"
  type        = string
  default     = "AL2023_x86_64_STANDARD"

  validation {
    condition     = contains(["AL2023_x86_64_STANDARD", "AL2023_ARM_64_STANDARD", "BOTTLEROCKET_x86_64", "BOTTLEROCKET_ARM_64"], var.ami_type)
    error_message = "ami_type must be AL2023_x86_64_STANDARD, AL2023_ARM_64_STANDARD, BOTTLEROCKET_x86_64 or BOTTLEROCKET_ARM_64."
  }
}

variable "scaling" {
  description = "Node counts: min_size <= desired_size <= max_size"
  type = object({
    min_size     = number
    max_size     = number
    desired_size = number
  })
  default = {
    min_size     = 2
    max_size     = 4
    desired_size = 2
  }

  validation {
    condition     = var.scaling.min_size >= 0 && var.scaling.min_size <= var.scaling.desired_size && var.scaling.desired_size <= var.scaling.max_size && var.scaling.max_size >= 1
    error_message = "scaling must satisfy 0 <= min_size <= desired_size <= max_size, and max_size >= 1."
  }
}

variable "max_unavailable_percentage" {
  description = "During node upgrades, at most this % of nodes are replaced at once"
  type        = number
  default     = 33

  validation {
    condition     = var.max_unavailable_percentage >= 1 && var.max_unavailable_percentage <= 100
    error_message = "max_unavailable_percentage must be between 1 and 100."
  }
}

variable "enable_node_repair" {
  description = "Let EKS automatically replace unhealthy nodes"
  type        = bool
  default     = true
}

# ---------------- Disk ----------------

variable "disk_size_gib" {
  description = "Root volume size (GiB): OS + container images"
  type        = number
  default     = 30

  validation {
    condition     = var.disk_size_gib >= 20
    error_message = "disk_size_gib must be at least 20."
  }
}

variable "ebs_kms_key_arn" {
  description = "KMS key for the root volume. null = AWS-managed EBS key (a customer key would need a grant for the Auto Scaling service-linked role)."
  type        = string
  default     = null
}

# ---------------- Network and security ----------------

variable "cluster_security_group_id" {
  description = "Security group EKS created for the cluster (eks-cluster module output). Must be on the nodes: control plane <-> node traffic."
  type        = string
}

variable "additional_security_group_ids" {
  description = "Extra groups for the nodes, e.g. sg-node from the security-groups module (ALB -> pods, pods -> RDS/Redis)"
  type        = list(string)
  default     = []
}

variable "imds_hop_limit" {
  description = "EC2 metadata hop limit. 1 = pods can't reach the node's metadata (they use IRSA instead). 2 = pods can (only if something needs it)."
  type        = number
  default     = 1

  validation {
    condition     = var.imds_hop_limit >= 1 && var.imds_hop_limit <= 64
    error_message = "imds_hop_limit must be between 1 and 64."
  }
}

# ---------------- Node IAM role ----------------

variable "enable_ssm" {
  description = "Attach AmazonSSMManagedInstanceCore so nodes can be reached with Session Manager (needs the ssm VPC endpoints)"
  type        = bool
  default     = false
}

variable "additional_policy_arns" {
  description = "Extra managed policies for the node role, keyed by a label (keys must be known at plan time)"
  type        = map(string)
  default     = {}
}

variable "additional_policy_jsons" {
  description = "Extra inline policies for the node role, keyed by a label, e.g. { ecr-pull-through-cache = <ecr module pull_through_cache_policy_json> }"
  type        = map(string)
  default     = {}
}

# ---------------- Kubernetes scheduling ----------------

variable "labels" {
  description = "Kubernetes labels on every node (used by nodeSelector / affinity)"
  type        = map(string)
  default     = {}
}

variable "taints" {
  description = "Kubernetes taints: only pods that tolerate them run here. effect: NO_SCHEDULE, PREFER_NO_SCHEDULE, NO_EXECUTE"
  type = list(object({
    key    = string
    value  = optional(string)
    effect = string
  }))
  default = []

  validation {
    condition     = alltrue([for t in var.taints : contains(["NO_SCHEDULE", "PREFER_NO_SCHEDULE", "NO_EXECUTE"], t.effect)])
    error_message = "taint effect must be NO_SCHEDULE, PREFER_NO_SCHEDULE or NO_EXECUTE."
  }
}

variable "tags" {
  description = "Extra tags for every resource (also put on the EC2 instances and volumes)"
  type        = map(string)
  default     = {}
}
