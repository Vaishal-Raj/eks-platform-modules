variable "name" {
  description = "Name prefix, e.g. client-a-dev"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,40}$", var.name))
    error_message = "name must be 3-40 chars: lowercase letters, digits, hyphens."
  }
}

# ---------------- The origin: an internal ALB reached through a VPC origin ----------------

variable "vpc_id" {
  description = "VPC of the ALB (CloudFront creates its VPC origin security group here). The VPC must have an internet gateway attached."
  type        = string
}

variable "alb_arn" {
  description = "ARN of the internal ALB (from the alb module)"
  type        = string
}

variable "alb_dns_name" {
  description = "DNS name of the internal ALB (from the alb module)"
  type        = string
}

variable "alb_security_group_id" {
  description = "ALB security group; this module adds its only inbound rule (from CloudFront's VPC origin SG)"
  type        = string
}

variable "alb_http_port" {
  description = "ALB listener port CloudFront connects to"
  type        = number
  default     = 80
}

variable "origin_read_timeout" {
  description = "Seconds CloudFront waits for the ALB to respond (1-180)"
  type        = number
  default     = 30

  validation {
    condition     = var.origin_read_timeout >= 1 && var.origin_read_timeout <= 180
    error_message = "origin_read_timeout must be between 1 and 180."
  }
}

variable "origin_keepalive_timeout" {
  description = "Seconds CloudFront keeps an idle connection to the ALB open (1-60)"
  type        = number
  default     = 5

  validation {
    condition     = var.origin_keepalive_timeout >= 1 && var.origin_keepalive_timeout <= 60
    error_message = "origin_keepalive_timeout must be between 1 and 60."
  }
}

# ---------------- WAF ----------------

variable "web_acl_arn" {
  description = "ARN of a CLOUDFRONT-scope WAFv2 web ACL (from the waf module). null = no WAF."
  type        = string
  default     = null
}

# ---------------- Caching ----------------

variable "uncached_path_patterns" {
  description = "Path patterns that are never cached and pass all viewer headers/cookies/query strings to the ALB (dynamic API traffic)"
  type        = list(string)
  default     = ["/api/*"]
}

variable "default_cache_policy_name" {
  description = "AWS managed cache policy for everything else (static assets, SPA)"
  type        = string
  default     = "Managed-CachingOptimized"
}

variable "uncached_cache_policy_name" {
  description = "AWS managed cache policy for uncached_path_patterns"
  type        = string
  default     = "Managed-CachingDisabled"
}

variable "uncached_origin_request_policy_name" {
  description = "AWS managed origin request policy for uncached_path_patterns (what is forwarded to the ALB)"
  type        = string
  default     = "Managed-AllViewerExceptHostHeader"
}

variable "response_headers_policy_name" {
  description = "AWS managed response headers policy added to every response (null = none)"
  type        = string
  default     = "Managed-SecurityHeadersPolicy"
}

# ---------------- Distribution ----------------

variable "price_class" {
  description = "PriceClass_100 (NA+EU), PriceClass_200 (+Asia incl. India), PriceClass_All"
  type        = string
  default     = "PriceClass_200"

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.price_class)
    error_message = "price_class must be PriceClass_100, PriceClass_200 or PriceClass_All."
  }
}

variable "aliases" {
  description = "Custom domain names (e.g. [\"app.client-a.com\"]). Needs acm_certificate_arn. Empty = use *.cloudfront.net."
  type        = list(string)
  default     = []
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN in us-east-1 covering aliases. null = CloudFront's default *.cloudfront.net certificate."
  type        = string
  default     = null
}

variable "wait_for_deployment" {
  description = "Wait until the distribution is fully deployed to all edge locations before finishing apply"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Extra tags for every resource in this module"
  type        = map(string)
  default     = {}
}
