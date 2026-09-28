provider "aws" {
  region = "us-east-1"

  # Tags added by the organization's Cloud Custodian (an SCP forbids deleting them)
  ignore_tags {
    keys         = ["Owner"]
    key_prefixes = ["c7n-"]
  }

  default_tags {
    tags = {
      Project   = "poc-gvr"
      Purpose   = "module-example"
      ManagedBy = "terraform"
    }
  }
}

module "network" {
  source = "../../modules/network"

  name             = var.name
  vpc_cidr         = var.vpc_cidr
  exclude_zone_ids = ["use1-az3"]
}

# Stand-ins for the ALB and VPC-endpoint security groups, so this example costs nothing
# (no load balancer, no interface endpoints). In the real stacks these IDs come from
# the alb and vpc-endpoints modules.
resource "aws_security_group" "alb_standin" {
  name        = "${var.name}-alb-standin"
  description = "Stand-in for the alb module security group (example only)"
  vpc_id      = module.network.vpc_id
}

resource "aws_security_group" "vpce_standin" {
  name        = "${var.name}-vpce-standin"
  description = "Stand-in for the vpc-endpoints module security group (example only)"
  vpc_id      = module.network.vpc_id
}

module "security_groups" {
  source = "../../modules/security-groups"

  name                   = var.name
  vpc_id                 = module.network.vpc_id
  alb_security_group_ids = [aws_security_group.alb_standin.id]
  vpce_security_group_ids = [
    aws_security_group.vpce_standin.id,
  ]
  app_ports = [8000]
}
