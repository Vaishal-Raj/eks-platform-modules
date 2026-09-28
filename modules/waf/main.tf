data "aws_region" "current" {}

locals {
  # Metric names can't contain hyphens: client-a-dev -> clientadev
  metric_prefix = replace(var.name, "-", "")
}

# ---------------- IP sets and regex sets (referenced by the rules) ----------------

resource "aws_wafv2_ip_set" "trusted" {
  count = length(var.trusted_ip_cidrs) > 0 ? 1 : 0

  name               = "${var.name}-trusted"
  scope              = var.scope
  ip_address_version = "IPV4"
  addresses          = var.trusted_ip_cidrs
  tags               = var.tags
}

resource "aws_wafv2_ip_set" "blocked" {
  count = length(var.blocked_ip_cidrs) > 0 ? 1 : 0

  name               = "${var.name}-blocked"
  scope              = var.scope
  ip_address_version = "IPV4"
  addresses          = var.blocked_ip_cidrs
  tags               = var.tags
}

resource "aws_wafv2_regex_pattern_set" "sensitive_paths" {
  name  = "${var.name}-sensitive-paths"
  scope = var.scope

  dynamic "regular_expression" {
    for_each = var.sensitive_path_patterns
    content {
      regex_string = regular_expression.value
    }
  }

  tags = var.tags
}

resource "aws_wafv2_regex_pattern_set" "bad_user_agents" {
  name  = "${var.name}-bad-user-agents"
  scope = var.scope

  dynamic "regular_expression" {
    for_each = var.bad_user_agent_patterns
    content {
      regex_string = regular_expression.value
    }
  }

  tags = var.tags
}

# ---------------- The web ACL ----------------

resource "aws_wafv2_web_acl" "this" {
  name        = "${var.name}-waf"
  description = "Web ACL for ${var.name}"
  scope       = var.scope

  default_action {
    allow {}
  }

  # 0. Trusted IPs skip every other rule
  dynamic "rule" {
    for_each = length(var.trusted_ip_cidrs) > 0 ? [1] : []
    content {
      name     = "allow-trusted-ips"
      priority = 0
      action {
        allow {}
      }
      statement {
        ip_set_reference_statement {
          arn = aws_wafv2_ip_set.trusted[0].arn
        }
      }
      visibility_config {
        cloudwatch_metrics_enabled = true
        sampled_requests_enabled   = true
        metric_name                = "${local.metric_prefix}AllowTrusted"
      }
    }
  }

  # 1. Explicit IP blocklist
  dynamic "rule" {
    for_each = length(var.blocked_ip_cidrs) > 0 ? [1] : []
    content {
      name     = "block-ip-blocklist"
      priority = 1
      action {
        block {}
      }
      statement {
        ip_set_reference_statement {
          arn = aws_wafv2_ip_set.blocked[0].arn
        }
      }
      visibility_config {
        cloudwatch_metrics_enabled = true
        sampled_requests_enabled   = true
        metric_name                = "${local.metric_prefix}BlockIps"
      }
    }
  }

  # 2. Country block
  dynamic "rule" {
    for_each = length(var.blocked_countries) > 0 ? [1] : []
    content {
      name     = "block-countries"
      priority = 2
      action {
        block {}
      }
      statement {
        geo_match_statement {
          country_codes = var.blocked_countries
        }
      }
      visibility_config {
        cloudwatch_metrics_enabled = true
        sampled_requests_enabled   = true
        metric_name                = "${local.metric_prefix}BlockCountries"
      }
    }
  }

  # 3. Site-wide rate limit per IP
  rule {
    name     = "rate-limit-per-ip"
    priority = 3
    action {
      block {}
    }
    statement {
      rate_based_statement {
        limit              = var.rate_limit
        aggregate_key_type = "IP"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      sampled_requests_enabled   = true
      metric_name                = "${local.metric_prefix}RateLimit"
    }
  }

  # 4. Stricter rate limit on the API (login, checkout, search...)
  rule {
    name     = "rate-limit-api"
    priority = 4
    action {
      block {}
    }
    statement {
      rate_based_statement {
        limit              = var.api_rate_limit
        aggregate_key_type = "IP"

        scope_down_statement {
          byte_match_statement {
            search_string         = var.api_path_prefix
            positional_constraint = "STARTS_WITH"
            field_to_match {
              uri_path {}
            }
            text_transformation {
              priority = 0
              type     = "LOWERCASE"
            }
          }
        }
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      sampled_requests_enabled   = true
      metric_name                = "${local.metric_prefix}RateLimitApi"
    }
  }

  # 5. Methods a web app never needs
  rule {
    name     = "block-disallowed-methods"
    priority = 5
    action {
      block {}
    }
    statement {
      regex_match_statement {
        regex_string = "^(${join("|", var.blocked_methods)})$"
        field_to_match {
          method {}
        }
        text_transformation {
          priority = 0
          type     = "NONE"
        }
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      sampled_requests_enabled   = true
      metric_name                = "${local.metric_prefix}BlockMethods"
    }
  }

  # 6. Probes for secrets / admin tools / backups
  rule {
    name     = "block-sensitive-paths"
    priority = 6
    action {
      block {}
    }
    statement {
      regex_pattern_set_reference_statement {
        arn = aws_wafv2_regex_pattern_set.sensitive_paths.arn
        field_to_match {
          uri_path {}
        }
        text_transformation {
          priority = 0
          type     = "LOWERCASE"
        }
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      sampled_requests_enabled   = true
      metric_name                = "${local.metric_prefix}BlockSensitivePaths"
    }
  }

  # 7. Known scanning tools
  rule {
    name     = "block-scanner-user-agents"
    priority = 7
    action {
      block {}
    }
    statement {
      regex_pattern_set_reference_statement {
        arn = aws_wafv2_regex_pattern_set.bad_user_agents.arn
        field_to_match {
          single_header {
            name = "user-agent"
          }
        }
        text_transformation {
          priority = 0
          type     = "LOWERCASE"
        }
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      sampled_requests_enabled   = true
      metric_name                = "${local.metric_prefix}BlockScanners"
    }
  }

  # 8. Oversized URI path
  rule {
    name     = "block-oversized-uri"
    priority = 8
    action {
      block {}
    }
    statement {
      size_constraint_statement {
        comparison_operator = "GT"
        size                = var.max_uri_length
        field_to_match {
          uri_path {}
        }
        text_transformation {
          priority = 0
          type     = "NONE"
        }
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      sampled_requests_enabled   = true
      metric_name                = "${local.metric_prefix}BlockLongUri"
    }
  }

  # 9. Oversized query string
  rule {
    name     = "block-oversized-query"
    priority = 9
    action {
      block {}
    }
    statement {
      size_constraint_statement {
        comparison_operator = "GT"
        size                = var.max_query_length
        field_to_match {
          query_string {}
        }
        text_transformation {
          priority = 0
          type     = "NONE"
        }
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      sampled_requests_enabled   = true
      metric_name                = "${local.metric_prefix}BlockLongQuery"
    }
  }

  # 10. Oversized cookies
  rule {
    name     = "block-oversized-cookie"
    priority = 10
    action {
      block {}
    }
    statement {
      size_constraint_statement {
        comparison_operator = "GT"
        size                = var.max_cookie_size
        field_to_match {
          single_header {
            name = "cookie"
          }
        }
        text_transformation {
          priority = 0
          type     = "NONE"
        }
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      sampled_requests_enabled   = true
      metric_name                = "${local.metric_prefix}BlockBigCookie"
    }
  }

  # 11. Host header is a raw IP address (scanners, not real users)
  rule {
    name     = "block-ip-host-header"
    priority = 11
    action {
      block {}
    }
    statement {
      regex_match_statement {
        regex_string = "^[0-9]{1,3}(\\.[0-9]{1,3}){3}(:[0-9]+)?$"
        field_to_match {
          single_header {
            name = "host"
          }
        }
        text_transformation {
          priority = 0
          type     = "NONE"
        }
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      sampled_requests_enabled   = true
      metric_name                = "${local.metric_prefix}BlockIpHost"
    }
  }

  # 20+. AWS managed rule groups
  dynamic "rule" {
    for_each = { for g in var.managed_rule_groups : g.name => g }
    content {
      name     = rule.value.name
      priority = rule.value.priority

      override_action {
        dynamic "none" {
          for_each = rule.value.override_action == "none" ? [1] : []
          content {}
        }
        dynamic "count" {
          for_each = rule.value.override_action == "count" ? [1] : []
          content {}
        }
      }

      statement {
        managed_rule_group_statement {
          name        = rule.value.name
          vendor_name = rule.value.vendor_name

          # Individual sub-rules switched to count (log only)
          dynamic "rule_action_override" {
            for_each = rule.value.count_rules
            content {
              name = rule_action_override.value
              action_to_use {
                count {}
              }
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        sampled_requests_enabled   = true
        metric_name                = "${local.metric_prefix}${rule.value.name}"
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    sampled_requests_enabled   = true
    metric_name                = "${local.metric_prefix}WebAcl"
  }

  tags = merge(var.tags, { Name = "${var.name}-waf" })

  lifecycle {
    precondition {
      condition     = var.scope != "CLOUDFRONT" || data.aws_region.current.region == "us-east-1"
      error_message = "CLOUDFRONT-scoped web ACLs must be created in us-east-1 (this provider is in ${data.aws_region.current.region})."
    }
  }
}

# ---------------- Optional logging ----------------

resource "aws_cloudwatch_log_group" "this" {
  count = var.logging.enabled ? 1 : 0

  # WAF only accepts log groups whose name starts with "aws-waf-logs-"
  name              = "aws-waf-logs-${var.name}"
  retention_in_days = var.logging.retention_days
  tags              = var.tags
}

resource "aws_wafv2_web_acl_logging_configuration" "this" {
  count = var.logging.enabled ? 1 : 0

  resource_arn            = aws_wafv2_web_acl.this.arn
  log_destination_configs = [aws_cloudwatch_log_group.this[0].arn]
}
