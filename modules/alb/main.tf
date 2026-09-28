resource "aws_security_group" "this" {
  name        = "${var.name}-alb"
  description = "Internal ALB. Inbound is added by the cloudfront module (from CloudFront's VPC origin SG only)."
  vpc_id      = var.vpc_id
  tags = merge(var.tags, {
    Name = "${var.name}-alb"
  })
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_egress_rule" "to_targets" {
  for_each = toset(var.target_egress_cidrs)

  security_group_id = aws_security_group.this.id
  description       = "To targets on ${var.target_port} in ${each.value}"
  ip_protocol       = "tcp"
  from_port         = var.target_port
  to_port           = var.target_port
  cidr_ipv4         = each.value
}

resource "aws_lb" "this" {
  name               = "${var.name}-alb"
  internal           = true
  load_balancer_type = "application"
  subnets            = var.subnet_ids
  security_groups    = [aws_security_group.this.id]

  idle_timeout               = var.idle_timeout
  enable_deletion_protection = var.deletion_protection
  drop_invalid_header_fields = true
  tags                       = merge(var.tags, { Name = "${var.name}-alb" })
}

# - drop_invalid_header_fields = true: a security best practice (it blocks HTTP header smuggling tricks). tflint's AWS ruleset and security scanners check for it.

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = var.listener_port
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      status_code  = var.fixed_response.status_code
      content_type = var.fixed_response.content_type
      message_body = coalesce(var.fixed_response.message_body, "hello from ${var.name} ALB")
    }
  }
  tags = var.tags
}

#Why HTTP, not HTTPS: the connection CloudFront → ALB runs inside AWS's private network through the 
# VPC origin, and users still get HTTPS at CloudFront. HTTPS to the ALB would need its own certificate. That's something to add with the dns-acm step, not now.

resource "aws_lb_target_group" "this" {
  count = var.create_target_group ? 1 : 0

  name                 = "${var.name}-tg"
  vpc_id               = var.vpc_id
  target_type          = "ip"
  port                 = var.target_port
  protocol             = "HTTP"
  deregistration_delay = 30

  health_check {
    path                = var.health_check.path
    matcher             = var.health_check.matcher
    interval            = var.health_check.interval
    healthy_threshold   = var.health_check.healthy_threshold
    unhealthy_threshold = var.health_check.unhealthy_threshold
  }

  tags = merge(var.tags, { Name = "${var.name}-tg" })
}


# - target_type = "ip": EKS pods get real VPC IPs (VPC CNI), and the Load Balancer Controller registers pod IPs directly.
# - Not attached to the listener yet. A listener pointing at an empty target group returns 503. In M3 you'll change the default action to "forward", once pods are registered.
# - deregistration_delay = 30: when a pod stops, the ALB waits 30 seconds for in-flight requests (the AWS default of 300 seconds makes deploys slow).
