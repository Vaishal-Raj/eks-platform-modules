# One provider in us-east-1: the CLOUDFRONT-scope WAF must live there, and it keeps
# this example simple. (A client in another region would use a second, aliased
# us-east-1 provider just for the WAF.)
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

# 1. VPC with an internet gateway attached (no routes): a CloudFront VPC origin prerequisite
module "network" {
  source = "../../modules/network"

  name             = var.name
  vpc_cidr         = var.vpc_cidr
  exclude_zone_ids = ["use1-az3"]
  create_igw       = true
}

# 2. Internal ALB answering "hello from edge-example ALB" (no targets needed)
module "alb" {
  source = "../../modules/alb"

  name                = var.name
  vpc_id              = module.network.vpc_id
  subnet_ids          = module.network.private_subnet_ids
  target_egress_cidrs = module.network.private_subnet_cidrs
}

# 3. WAF with the default rule set (15 rules active)
module "waf" {
  source = "../../modules/waf"

  name = var.name
}

# 4. CloudFront: VPC origin -> ALB, WAF attached, ALB inbound rule from CloudFront only
module "cloudfront" {
  source = "../../modules/cloudfront"

  name                  = var.name
  vpc_id                = module.network.vpc_id
  alb_arn               = module.alb.alb_arn
  alb_dns_name          = module.alb.alb_dns_name
  alb_security_group_id = module.alb.security_group_id
  alb_http_port         = module.alb.listener_port
  web_acl_arn           = module.waf.web_acl_arn

  # The VPC origin can only be created once the VPC has its internet gateway
  depends_on = [module.network]
}
