variable "name" {
  description = "Prefix for the app repositories: <name>/<repo>, e.g. poc-gvr/api"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+([._-][a-z0-9]+)*$", var.name))
    error_message = "name must be lowercase letters/digits, optionally separated by single . _ or - (ECR naming rules)."
  }
}

# ---------------- App repositories ----------------

variable "repositories" {
  description = <<-EOT
    App image repositories, keyed by short name (becomes <name>/<key>).
      image_tag_mutability  IMMUTABLE (a tag can never be overwritten) or MUTABLE
      scan_on_push          scan every pushed image for known vulnerabilities (CVEs)
      keep_last_images      keep only the newest N images (older ones are expired)
      untagged_expiry_days  delete untagged images (leftover layers from re-pushes) after N days
      force_delete          allow destroy even when images exist (throwaway environments only)
  EOT
  type = map(object({
    image_tag_mutability = optional(string, "IMMUTABLE")
    scan_on_push         = optional(bool, true)
    keep_last_images     = optional(number, 30)
    untagged_expiry_days = optional(number, 7)
    force_delete         = optional(bool, false)
  }))
  default = {}

  validation {
    condition     = alltrue([for k in keys(var.repositories) : can(regex("^[a-z0-9]+([._-][a-z0-9]+)*$", k))])
    error_message = "Repository keys must be lowercase letters/digits, optionally separated by single . _ or -."
  }

  validation {
    condition     = alltrue([for r in values(var.repositories) : contains(["IMMUTABLE", "MUTABLE"], r.image_tag_mutability)])
    error_message = "image_tag_mutability must be IMMUTABLE or MUTABLE."
  }

  validation {
    condition     = alltrue([for r in values(var.repositories) : r.keep_last_images >= 1 && r.untagged_expiry_days >= 1])
    error_message = "keep_last_images and untagged_expiry_days must be at least 1."
  }
}

variable "kms_key_arn" {
  description = "Customer-managed KMS key for the app repositories (key policy must allow via_services [\"ecr\"]). null = AES256."
  type        = string
  default     = null
}

# ---------------- Who may push / pull (repository policy) ----------------

variable "push_principal_arns" {
  description = "IAM ARNs allowed to push (and pull), e.g. the app repo's GitHub OIDC role. Needed for cross-account; same-account roles can rely on IAM alone."
  type        = list(string)
  default     = []
}

variable "pull_principal_arns" {
  description = "IAM ARNs or account roots allowed to pull only, e.g. other client accounts' node roles"
  type        = list(string)
  default     = []
}

# ---------------- Pull-through cache (mirrors of public registries) ----------------

variable "pull_through_cache_rules" {
  description = <<-EOT
    Mirrors of public registries, keyed by the ECR prefix to serve them under.
    Nodes pull <account>.dkr.ecr.<region>.amazonaws.com/<prefix>/<image> and ECR fetches from upstream once.
      upstream_registry_url  e.g. registry.k8s.io, public.ecr.aws, quay.io, ghcr.io, registry-1.docker.io
      credential_arn         Secrets Manager secret (name must start with "ecr-pullthroughcache/"),
                             required for ghcr.io, Docker Hub and GitLab
  EOT
  type = map(object({
    upstream_registry_url = string
    credential_arn        = optional(string)
  }))
  default = {
    "ecr-public" = { upstream_registry_url = "public.ecr.aws" }
    "k8s"        = { upstream_registry_url = "registry.k8s.io" }
    "quay"       = { upstream_registry_url = "quay.io" }
  }

  validation {
    condition = alltrue([
      for r in values(var.pull_through_cache_rules) :
      !contains(["ghcr.io", "registry-1.docker.io", "registry.gitlab.com"], r.upstream_registry_url) || r.credential_arn != null
    ])
    error_message = "ghcr.io, Docker Hub (registry-1.docker.io) and GitLab need a credential_arn (Secrets Manager secret named ecr-pullthroughcache/...)."
  }

  validation {
    condition     = alltrue([for k in keys(var.pull_through_cache_rules) : can(regex("^[a-z0-9]+([._-][a-z0-9]+)*$", k)) && length(k) >= 2 && length(k) <= 30])
    error_message = "Pull-through cache prefixes must be 2-30 chars: lowercase letters/digits, optionally separated by . _ or -."
  }
}

variable "cache_keep_last_images" {
  description = "Keep the newest N images in each pull-through cache repository"
  type        = number
  default     = 10
}

variable "cache_untagged_expiry_days" {
  description = "Delete untagged images in pull-through cache repositories after N days"
  type        = number
  default     = 7
}

variable "tags" {
  description = "Extra tags for every resource in this module"
  type        = map(string)
  default     = {}
}
