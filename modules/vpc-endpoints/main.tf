data "aws_vpc_endpoint_service" "interface" {
  for_each = toset(var.interface_services)

  service      = each.value
  service_type = "Interface"
}

data "aws_vpc_endpoint_service" "s3" {
  count = var.enable_s3_gateway ? 1 : 0

  service      = "s3"
  service_type = "Gateway"
}

# Security group

resource "aws_security_group" "this" {
  name        = "${var.name}-vpce"
  description = "Interface VPC endpoints: HTTPS from allowed CIDRs only"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-vpce" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  for_each = toset(var.allowed_cidrs)

  security_group_id = aws_security_group.this.id
  description       = "HTTPS from ${each.value}"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = each.value
}

# - No egress rule. Terraform removes AWS's default allow-all egress when it creates the group. Endpoints only answer connections, and replies are allowed back automatically (security groups are stateful).
# - create_before_destroy: if the group ever has to be replaced (say, a renamed module), Terraform builds the new one first. Otherwise AWS can't delete a group that endpoints are still using, and the apply gets stuck.
# - A port number like 443 stays in the code because it's what the module is: every AWS API speaks HTTPS. That's a design fact, not configuration.


# Interface endpoints
resource "aws_vpc_endpoint" "interface" {
  for_each            = data.aws_vpc_endpoint_service.interface
  vpc_id              = var.vpc_id
  service_name        = each.value.service_name
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.subnet_ids
  security_group_ids  = [aws_security_group.this.id]
  private_dns_enabled = var.private_dns_enabled
  tags                = merge(var.tags, { Name = "${var.name}-${each.key}" })
}

# S3 gateway endpoint
resource "aws_vpc_endpoint" "s3" {
  count = var.enable_s3_gateway ? 1 : 0

  vpc_id            = var.vpc_id
  service_name      = data.aws_vpc_endpoint_service.s3[0].service_name
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.route_table_ids

  tags = merge(var.tags, { Name = "${var.name}-s3" })

  lifecycle {
    precondition {
      condition     = length(var.route_table_ids) > 0
      error_message = "enable_s3_gateway = true needs at least one route table in route_table_ids."
    }
  }
}

# - count = condition ? 1 : 0 is the standard Terraform way to make a resource optional. Because it's then a list, you refer to it as [0].
# - The precondition catches "S3 gateway switched on, but no route tables given" at plan time, with a clear message.