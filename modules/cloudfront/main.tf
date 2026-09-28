locals {
  origin_id  = "${var.name}-alb"
  use_custom = var.acm_certificate_arn != null
}

# ---------------- AWS managed policies (looked up by name) ----------------

data "aws_cloudfront_cache_policy" "default" {
  name = var.default_cache_policy_name
}

data "aws_cloudfront_cache_policy" "uncached" {
  name = var.uncached_cache_policy_name
}

data "aws_cloudfront_origin_request_policy" "uncached" {
  name = var.uncached_origin_request_policy_name
}

data "aws_cloudfront_response_headers_policy" "this" {
  count = var.response_headers_policy_name == null ? 0 : 1
  name  = var.response_headers_policy_name
}

# ---------------- VPC origin: CloudFront's private path into the VPC ----------------
# CloudFront places its own ENIs in the ALB's subnets and reaches the ALB over the
# AWS network. The ALB stays internal (no public IP). The VPC must have an internet
# gateway attached (a CloudFront prerequisite; no routes are needed).

resource "aws_cloudfront_vpc_origin" "this" {
  vpc_origin_endpoint_config {
    name                   = "${var.name}-alb"
    arn                    = var.alb_arn
    http_port              = var.alb_http_port
    https_port             = 443
    origin_protocol_policy = "http-only"

    origin_ssl_protocols {
      items    = ["TLSv1.2"]
      quantity = 1
    }
  }

  tags = merge(var.tags, { Name = "${var.name}-vpc-origin" })

  # Deploying (or deleting) a VPC origin commonly takes 10-15+ minutes
  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }
}

# AWS creates this security group in the VPC when the VPC origin is deployed.
# CloudFront's ENIs use it, so it is the ONLY source the ALB should accept.
data "aws_security_group" "cloudfront_vpc_origin" {
  filter {
    name   = "group-name"
    values = ["CloudFront-VPCOrigins-Service-SG"]
  }

  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }

  depends_on = [aws_cloudfront_vpc_origin.this]
}

# The ALB's only inbound rule: CloudFront's VPC origin, on the listener port
resource "aws_vpc_security_group_ingress_rule" "alb_from_cloudfront" {
  security_group_id            = var.alb_security_group_id
  description                  = "HTTP from the CloudFront VPC origin only"
  ip_protocol                  = "tcp"
  from_port                    = var.alb_http_port
  to_port                      = var.alb_http_port
  referenced_security_group_id = data.aws_security_group.cloudfront_vpc_origin.id

  tags = var.tags
}

# ---------------- The distribution ----------------

resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  comment             = "${var.name}: CloudFront -> VPC origin -> internal ALB"
  price_class         = var.price_class
  http_version        = "http2and3"
  is_ipv6_enabled     = true
  aliases             = var.aliases
  web_acl_id          = var.web_acl_arn # WAFv2: this argument takes the web ACL ARN
  wait_for_deployment = var.wait_for_deployment

  origin {
    origin_id   = local.origin_id
    domain_name = var.alb_dns_name

    vpc_origin_config {
      vpc_origin_id            = aws_cloudfront_vpc_origin.this.id
      origin_read_timeout      = var.origin_read_timeout
      origin_keepalive_timeout = var.origin_keepalive_timeout
    }
  }

  # Everything else: static assets / SPA, cached at the edge
  default_cache_behavior {
    target_origin_id           = local.origin_id
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = data.aws_cloudfront_cache_policy.default.id
    response_headers_policy_id = one(data.aws_cloudfront_response_headers_policy.this[*].id)
  }

  # Dynamic paths (/api/*): never cached, all methods, viewer data forwarded
  dynamic "ordered_cache_behavior" {
    for_each = var.uncached_path_patterns
    content {
      path_pattern               = ordered_cache_behavior.value
      target_origin_id           = local.origin_id
      viewer_protocol_policy     = "redirect-to-https"
      allowed_methods            = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
      cached_methods             = ["GET", "HEAD"]
      compress                   = true
      cache_policy_id            = data.aws_cloudfront_cache_policy.uncached.id
      origin_request_policy_id   = data.aws_cloudfront_origin_request_policy.uncached.id
      response_headers_policy_id = one(data.aws_cloudfront_response_headers_policy.this[*].id)
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none" # country blocking lives in the WAF (rule block-countries)
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = local.use_custom ? null : true
    acm_certificate_arn            = local.use_custom ? var.acm_certificate_arn : null
    ssl_support_method             = local.use_custom ? "sni-only" : null
    minimum_protocol_version       = local.use_custom ? "TLSv1.2_2021" : "TLSv1"
  }

  tags = merge(var.tags, { Name = "${var.name}-cdn" })

  # The ALB must accept CloudFront before traffic is sent to it
  depends_on = [aws_vpc_security_group_ingress_rule.alb_from_cloudfront]

  lifecycle {
    precondition {
      condition     = length(var.aliases) == 0 || var.acm_certificate_arn != null
      error_message = "aliases (custom domains) need an acm_certificate_arn from us-east-1."
    }
  }
}
