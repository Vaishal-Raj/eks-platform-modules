data "aws_availability_zones" "available" {
  state            = "available"
  exclude_zone_ids = var.exclude_zone_ids
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  private_subnets = {
    for i, az in local.azs : az => cidrsubnet(var.vpc_cidr, var.private_subnet_newbits, i)
  }

  isolated_subnets = {
    for i, az in local.azs : az => cidrsubnet(var.vpc_cidr, var.isolated_subnet_newbits, var.isolated_subnet_offset + i)
  }
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = var.enable_dns_support
  enable_dns_hostnames = var.enable_dns_hostnames

  tags = merge(var.tags, { Name = var.name })

  lifecycle {
    precondition {
      condition     = length(local.azs) == var.az_count
      error_message = "Only ${length(local.azs)} usable AZs in this region after exclusions; az_count is ${var.az_count}."
    }
    precondition {
      condition = alltrue([
        for i in range(var.az_count) :
        can(cidrsubnet(var.vpc_cidr, var.private_subnet_newbits, i)) &&
        can(cidrsubnet(var.vpc_cidr, var.isolated_subnet_newbits, var.isolated_subnet_offset + i))
      ])
      error_message = "Subnets don't fit in ${var.vpc_cidr} with these newbits/offset. Use a larger VPC or adjust the subnet sizing variables."
    }
  }
}

resource "aws_subnet" "private" {
  for_each = local.private_subnets

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = each.value

  tags = merge(var.tags, var.private_subnet_tags, {
    Name = "${var.name}-private-${each.key}"
    Tier = "private"
  })
}

resource "aws_subnet" "isolated" {
  for_each = local.isolated_subnets

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = each.value

  tags = merge(var.tags, var.isolated_subnet_tags, {
    Name = "${var.name}-isolated-${each.key}"
    Tier = "isolated"
  })
}

# One route table per tier, with no routes: only AWS's automatic "local" route.
# No NAT gateway, so there's no reason for one table per AZ.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-private" })
}

resource "aws_route_table" "isolated" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-isolated" })
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "isolated" {
  for_each = aws_subnet.isolated

  subnet_id      = each.value.id
  route_table_id = aws_route_table.isolated.id
}


# - merge(var.tags, var.private_subnet_tags, { Name = … }): later maps win, so the module's own Name and Tier can't be overwritten by accident.
# - precondition inside lifecycle: a check that runs at plan time and can look at several variables together. A variable validation only sees its own variable. Here it catches:
#   - a region with too few AZs after exclusions (otherwise slice would quietly give you fewer than you asked for);
#   - subnet sizes that don't fit the VPC, with a clear message instead of an unhelpful cidrsubnet error.
# - The EKS tag is gone from the module. The caller decides whether its subnets are for EKS.