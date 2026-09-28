variable "name" {
  description = "Name prefix, e.g. client-a-dev"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,40}$", var.name))
    error_message = "name must be 3-40 chars: lowercase letters, digits, hyphens."
  }
}

variable "scope" {
  description = "CLOUDFRONT (global, must be created in us-east-1) or REGIONAL"
  type        = string
  default     = "CLOUDFRONT"

  validation {
    condition     = contains(["CLOUDFRONT", "REGIONAL"], var.scope)
    error_message = "scope must be CLOUDFRONT or REGIONAL."
  }
}


variable "trusted_ip_cidrs" {
  description = "IPv4 CIDRs allowed straight through (office/VPN). Empty = rule off."
  type        = list(string)
  default     = []
}

variable "blocked_ip_cidrs" {
  description = "IPv4 CIDRs always blocked. Empty = rule off."
  type        = list(string)
  default     = []
}

variable "blocked_countries" {
  description = "ISO 3166 country codes to block, e.g. [\"KP\"]. Empty = rule off."
  type        = list(string)
  default     = []
}

# ---------- rate limits (per client IP, per 5 minutes) ----------

variable "rate_limit" {
  description = "Max requests per IP per 5 min, whole site"
  type        = number
  default     = 2000

  validation {
    condition     = var.rate_limit >= 10
    error_message = "rate_limit must be at least 10."
  }
}

variable "api_rate_limit" {
  description = "Max requests per IP per 5 min to paths starting with api_path_prefix"
  type        = number
  default     = 300

  validation {
    condition     = var.api_rate_limit >= 10
    error_message = "api_rate_limit must be at least 10."
  }
}

variable "api_path_prefix" {
  description = "Path prefix that gets the stricter API rate limit"
  type        = string
  default     = "/api/"
}

# ---------- request hygiene ----------

variable "blocked_methods" {
  description = "HTTP methods to block"
  type        = list(string)
  default     = ["TRACE", "TRACK", "DEBUG", "CONNECT"]
}

variable "sensitive_path_patterns" {
  description = "Regexes (max 10) for paths no real user should request; matched on the lowercased path"
  type        = list(string)
  default = [
    "^/\\.env",
    "^/\\.git",
    "^/\\.(aws|ssh|docker)",
    "/wp-(admin|login|content|includes)",
    "/phpmyadmin",
    "/(server-status|server-info)",
    "\\.(bak|old|sql|swp|log|ini)$",
    "/(actuator|console)(/|$)",
    "/(etc/passwd|proc/self)",
    "/cgi-bin/",
  ]

  validation {
    condition     = length(var.sensitive_path_patterns) > 0 && length(var.sensitive_path_patterns) <= 10
    error_message = "A WAF regex pattern set holds 1 to 10 patterns."
  }
}

variable "bad_user_agent_patterns" {
  description = "Regexes (max 10) matched on the lowercased User-Agent of known scanning tools"
  type        = list(string)
  default = [
    "sqlmap",
    "nikto",
    "nmap",
    "masscan",
    "zgrab",
    "nuclei",
    "(go|dir)buster|dirb",
    "wpscan",
    "acunetix|netsparker",
    "havij|w3af|jaeles",
  ]

  validation {
    condition     = length(var.bad_user_agent_patterns) > 0 && length(var.bad_user_agent_patterns) <= 10
    error_message = "A WAF regex pattern set holds 1 to 10 patterns."
  }
}

variable "max_uri_length" {
  description = "Block URI paths longer than this (bytes)"
  type        = number
  default     = 2048
}

variable "max_query_length" {
  description = "Block query strings longer than this (bytes)"
  type        = number
  default     = 2048
}

variable "max_cookie_size" {
  description = "Block Cookie headers larger than this (bytes)"
  type        = number
  default     = 8192
}


# ---------- AWS managed rule groups ----------

variable "managed_rule_groups" {
  description = "AWS managed rule groups. override_action: none = enforce, count = log only. count_rules: sub-rules set to count."
  type = list(object({
    name            = string
    priority        = number
    vendor_name     = optional(string, "AWS")
    override_action = optional(string, "none")
    count_rules     = optional(list(string), [])
  }))
  default = [
    { name = "AWSManagedRulesAmazonIpReputationList", priority = 20 },
    { name = "AWSManagedRulesAnonymousIpList", priority = 21, count_rules = ["HostingProviderIPList"] },
    { name = "AWSManagedRulesKnownBadInputsRuleSet", priority = 22 },
    { name = "AWSManagedRulesCommonRuleSet", priority = 23 },
    { name = "AWSManagedRulesSQLiRuleSet", priority = 24 },
    { name = "AWSManagedRulesLinuxRuleSet", priority = 25 },
  ]

  validation {
    condition     = alltrue([for g in var.managed_rule_groups : contains(["none", "count"], g.override_action)])
    error_message = "override_action must be none or count."
  }

  validation {
    condition     = alltrue([for g in var.managed_rule_groups : g.priority >= 20])
    error_message = "Managed groups use priority 20+ (0-11 are reserved for the custom rules)."
  }

  validation {
    condition     = length(distinct([for g in var.managed_rule_groups : g.priority])) == length(var.managed_rule_groups)
    error_message = "Each managed rule group needs a unique priority."
  }
}

variable "logging" {
  description = "Send WAF logs to CloudWatch (log group aws-waf-logs-<name>)"
  type = object({
    enabled        = optional(bool, false)
    retention_days = optional(number, 30)
  })
  default = {}
}

variable "tags" {
  description = "Extra tags for every resource in this module"
  type        = map(string)
  default     = {}
}