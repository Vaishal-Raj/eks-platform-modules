# Security groups for the application and data tiers. One group per hop:
#
#   internal ALB ──app_ports──► sg-node (EKS nodes/pods) ──db_port────► sg-rds   (RDS MySQL)
#                                        │                ──cache_port─► sg-cache (ElastiCache)
#                                        ├──443──► sg-vpce (VPC interface endpoints)
#                                        └──443──► S3 prefix list (S3 gateway endpoint)
#
# Every rule names a security group (or the S3 prefix list), never 0.0.0.0/0.
# Terraform removes AWS's default "allow all outbound" rule, so a group with no
# egress rule sends nothing. The ALB and VPC-endpoint groups live in their own modules.
#
# Note: EKS also attaches its own cluster security group to nodes (control plane,
# node-to-node, DNS). sg-node adds to it; it does not replace it.

data "aws_region" "current" {}

data "aws_ec2_managed_prefix_list" "s3" {
  count = var.allow_s3_gateway_egress ? 1 : 0
  name  = "com.amazonaws.${data.aws_region.current.region}.s3"
}

locals {
  # for_each keys must be known at plan time. Security group IDs often aren't (they may be
  # created in the same run), so rules are keyed by list POSITION + port, which always are.
  alb_rules = {
    for pair in setproduct(range(length(var.alb_security_group_ids)), var.app_ports) :
    "${pair[0]}-${pair[1]}" => { sg = var.alb_security_group_ids[pair[0]], port = pair[1] }
  }
}

# ---------------- The groups ----------------

resource "aws_security_group" "node" {
  name        = "${var.name}-node"
  description = "EKS worker nodes and pods. Inbound from the ALB on app ports; outbound to data tier and AWS endpoints."
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-node" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "rds" {
  count = var.create_rds_sg ? 1 : 0

  name        = "${var.name}-rds"
  description = "RDS. Inbound on the database port from the nodes only."
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-rds" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "cache" {
  count = var.create_cache_sg ? 1 : 0

  name        = "${var.name}-cache"
  description = "ElastiCache. Inbound on the cache port from the nodes only."
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-cache" })

  lifecycle {
    create_before_destroy = true
  }
}

# ---------------- sg-node: inbound ----------------

resource "aws_vpc_security_group_ingress_rule" "node_from_alb" {
  for_each = local.alb_rules

  security_group_id            = aws_security_group.node.id
  description                  = "From the internal ALB on app port ${each.value.port}"
  ip_protocol                  = "tcp"
  from_port                    = each.value.port
  to_port                      = each.value.port
  referenced_security_group_id = each.value.sg

  tags = var.tags
}

# ---------------- sg-node: outbound ----------------

resource "aws_vpc_security_group_egress_rule" "node_to_rds" {
  count = var.create_rds_sg ? 1 : 0

  security_group_id            = aws_security_group.node.id
  description                  = "To RDS on ${var.db_port}"
  ip_protocol                  = "tcp"
  from_port                    = var.db_port
  to_port                      = var.db_port
  referenced_security_group_id = aws_security_group.rds[0].id

  tags = var.tags
}

resource "aws_vpc_security_group_egress_rule" "node_to_cache" {
  count = var.create_cache_sg ? 1 : 0

  security_group_id            = aws_security_group.node.id
  description                  = "To ElastiCache on ${var.cache_port}"
  ip_protocol                  = "tcp"
  from_port                    = var.cache_port
  to_port                      = var.cache_port
  referenced_security_group_id = aws_security_group.cache[0].id

  tags = var.tags
}

resource "aws_vpc_security_group_egress_rule" "node_to_vpce" {
  count = length(var.vpce_security_group_ids)

  security_group_id            = aws_security_group.node.id
  description                  = "To AWS APIs through the VPC interface endpoints"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = var.vpce_security_group_ids[count.index]

  tags = var.tags
}

resource "aws_vpc_security_group_egress_rule" "node_to_s3" {
  count = var.allow_s3_gateway_egress ? 1 : 0

  security_group_id = aws_security_group.node.id
  description       = "To S3 through the gateway endpoint (ECR image layers)"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  prefix_list_id    = data.aws_ec2_managed_prefix_list.s3[0].id

  tags = var.tags
}

# ---------------- sg-rds: inbound ----------------

resource "aws_vpc_security_group_ingress_rule" "rds_from_node" {
  count = var.create_rds_sg ? 1 : 0

  security_group_id            = aws_security_group.rds[0].id
  description                  = "From EKS nodes/pods on ${var.db_port}"
  ip_protocol                  = "tcp"
  from_port                    = var.db_port
  to_port                      = var.db_port
  referenced_security_group_id = aws_security_group.node.id

  tags = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_additional" {
  count = var.create_rds_sg ? length(var.additional_db_source_sg_ids) : 0

  security_group_id            = aws_security_group.rds[0].id
  description                  = "From an additional source on ${var.db_port}"
  ip_protocol                  = "tcp"
  from_port                    = var.db_port
  to_port                      = var.db_port
  referenced_security_group_id = var.additional_db_source_sg_ids[count.index]

  tags = var.tags
}

# ---------------- sg-cache: inbound ----------------

resource "aws_vpc_security_group_ingress_rule" "cache_from_node" {
  count = var.create_cache_sg ? 1 : 0

  security_group_id            = aws_security_group.cache[0].id
  description                  = "From EKS nodes/pods on ${var.cache_port}"
  ip_protocol                  = "tcp"
  from_port                    = var.cache_port
  to_port                      = var.cache_port
  referenced_security_group_id = aws_security_group.node.id

  tags = var.tags
}
